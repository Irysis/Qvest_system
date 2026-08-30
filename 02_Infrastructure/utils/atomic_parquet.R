#==============================================================================
# atomic_parquet.R — parquet 캐시 원자적 쓰기 공용 정본 (2026-08-30)
#
# 왜 승격했나: `atomic_json.R`(2026-08-23)이 JSON 원장에 대해 정확히 같은 병을 이미
#   고쳤는데, **parquet 캐시 쪽은 손대지 않은 채로 남아 있었다.** 그래서 같은 결함이
#   `krx_build_rawdata.R` · `rawdata_sanitize.R` · `build_cache.R` ·
#   `incremental_cache_update.R` · `incremental_update_file.R` 에 5벌 복제돼 있다
#   (전부 `write_parquet(tmp)` → **`file.remove(target)`** → `file.rename`).
#   사본이 갈라진 게 아니라 **같은 오류가 복제**된 것이라 개별 수리로는 재발이 멎지 않는다.
#
# 소비자(2026-08-30 현재 2): krx_build_rawdata.R(BM_CACHE) ·
#   rawdata_sanitize.R(RAWDATA_CACHE + BM_CACHE).
#   배선 도달 검사 = 08_Tests/data/test_parquet_atomic_write.R 축 D.
#
#------------------------------------------------------------------------------
# ★실측 (2026-08-30, pyarrow 24.0.0 / R 4.5.2 ucrt · Windows 11 · OneDrive 경로)
#
#   [측정 1] **선삭제가 실제로 캐시를 날렸다.** 2026-08-29 23:27 사고 —
#            `.cache/benchmark.parquet` 이 삭제된 뒤 재작성 전에 프로세스가 죽어
#            파일이 **부재** 상태로 남았다. 하류가 줄줄이 정지:
#              `[bm-gate][B] benchmark.parquet 부재 — 거래일 판정 불가`
#              `[regime_jump_model] ERR: ... [Windows error 2]`
#            재현: remove(target) 직후 rename 전 창에서 target exists = FALSE.
#            ⇒ `file.rename` 은 대상이 존재해도 덮어쓰므로(atomic_json.R [측정 1])
#              선삭제는 **얻는 게 0이고 잃는 게 파일 전체**다.
#
#   [측정 2] **제자리 쓰기는 조용히 자른다.** 같은 경로에 직접 write 하다가 중간에
#            죽으면 파일이 남긴 남는데 **내용이 절단**된다 — 실측 9,017행 → 500행,
#            그리고 그 결과물은 **정상적으로 읽힌다**. 소비자는 오류 대신 짧은
#            시리즈를 본다(= 침묵 실패). tmp 경유는 같은 죽음에서 원본 9,017행 불변.
#
#   [측정 3] tmp 는 target 과 **같은 디렉터리**에 만든다 — 다른 볼륨이면 rename 이
#            원자적일 수 없다. 같은 디렉터리면 cross-device 실패 자체가 불가능하다.
#
#   [측정 4] 소비자가 대상 핸들을 점유 중이면 rename 은 FALSE 를 낸다.
#            `file.copy(overwrite=TRUE)` 는 이때 **성공하지만 제자리에서 자른다**
#            = 절단원. 1차 수단은 **유한 재시도**(핸들은 ms 단위로 풀린다), 소진 시 stop().
#            근거 카드: reference-windows-atomic-write-copy-fallback-is-the-tear
#
#------------------------------------------------------------------------------
# ★mmap 주의: 같은 경로를 arrow 로 읽은 채 그 경로에 쓰면 Windows 가
#   `error 1224 (ERROR_USER_MAPPED_FILE)` 로 거부할 수 있다. tmp→rename 은 대상 파일을
#   **열지 않으므로** 이 조건을 원천 회피한다 — 호출자가 읽은 객체를 `rm()` 할 필요가 없다
#   (rename 은 디렉터리 엔트리를 갈아끼울 뿐, 기존 inode 의 매핑은 그대로 유효하다).
#==============================================================================
suppressPackageStartupMessages({ library(arrow) })

# 재시도 사다리 — atomic_json.R 과 동일 규약(0.02s 부터 배증, 개별 상한 0.25s, 8회 ≈ 1.3s).
ATOMIC_PARQUET_RETRIES    <- 8L
ATOMIC_PARQUET_SLEEP_INIT <- 0.02
ATOMIC_PARQUET_SLEEP_CAP  <- 0.25

#' data.frame/data.table 을 parquet 으로 원자적으로 기록한다
#' (tmp → rename, **선삭제 없음**, 유한 재시도, copy 폴백 없음).
#'
#' @param df        기록할 테이블
#' @param path      최종 경로. tmp 는 같은 디렉터리에 만든다([측정 3]).
#' @param ...       write_parquet() 에 그대로 전달
#' @param validate  TRUE 면 promote 전에 tmp 를 되읽어 **행 수**까지 확인한다.
#'                  "썼다" 와 "읽을 수 있는 것을 썼다" 는 다른 명제다([측정 2]).
#' @param tag       로그/에러 접두어 (호출자 식별)
#' @return invisible(TRUE). 실패 시 stop() — 정본은 **미갱신 상태로 보존**된다.
qvest_atomic_write_parquet <- function(df, path, ..., validate = TRUE,
                                       tag = "atomic_parquet",
                                       retries = ATOMIC_PARQUET_RETRIES) {
  d <- dirname(path)
  if (nzchar(d) && !dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)

  # tmp 는 반드시 같은 디렉터리 + pid 로 유일화([측정 3]). 동시 실행이 서로의 tmp 를 밟지 않는다.
  tmp <- file.path(d, sprintf(".%s.tmp%s", basename(path), Sys.getpid()))
  n_in <- nrow(df)
  write_parquet(df, tmp, ...)

  if (isTRUE(validate)) {
    chk <- tryCatch(nrow(read_parquet(tmp)), error = function(e) e)
    if (inherits(chk, "error") || !identical(as.integer(chk), as.integer(n_in))) {
      suppressWarnings(file.remove(tmp))
      stop(sprintf("[%s] 산출물 검증 실패 — 정본 미갱신: %s (기대 %d행, 실측 %s)",
                   tag, path, n_in,
                   if (inherits(chk, "error")) paste0("판독불가: ", conditionMessage(chk)) else chk))
    }
  }

  # ★선삭제 없음([측정 1]). file.rename 은 존재하는 대상을 덮어쓴다.
  for (i in seq_len(max(1L, as.integer(retries)))) {
    if (isTRUE(suppressWarnings(file.rename(tmp, path)))) return(invisible(TRUE))
    Sys.sleep(min(ATOMIC_PARQUET_SLEEP_CAP, ATOMIC_PARQUET_SLEEP_INIT * 2^(i - 1)))
  }

  # ★copy 폴백 없음([측정 4]) — rename 이 실패하는 유일한 실전 사유가 "소비자가 읽는 중"인데,
  #   그 순간이 정확히 copy 가 파일을 찢는 순간이다. tmp 를 남겨 페이로드를 회수 가능하게 한다.
  stop(sprintf(paste0("[%s] 원자적 기록 실패 (rename %d회) — 정본 미갱신(원본 보존): %s\n",
                      "  기록분은 %s 에 보존됨. 대개 소비자가 대상 핸들을 점유 중이다([측정 4])."),
               tag, retries, path, tmp))
}

# 소스 확인용 표지 — 배선 도달 검사(축 D)가 이 심볼의 존재로 "정본을 실제로 쓰는가"를 판정한다.
ATOMIC_PARQUET_SOT <- "02_Infrastructure/utils/atomic_parquet.R"
