#==============================================================================
# atomic_json.R — JSON 원장 원자적 쓰기 공용 정본 (2026-08-23 v9.1 후속)
#
# 왜 승격했나: tmp→rename 을 각자 인라인으로 구현한 사본이 저장소에 3벌 있었고
#   (auto_spawn_queue.R::.asq_atomic_write · standalone_track_queue.R 처분 기록 ·
#   hypothesis_index.R F-1), **셋이 같은 결함을 공유**했다(아래 §실측 ①). 사본이
#   갈라진 게 아니라 **같은 오류가 복제**된 것이라 개별 수리로는 재발이 멎지 않는다.
#
# 소비자(2026-08-23 현재 4): auto_spawn_queue.R · overlay_candidate_queue.R ·
#   standalone_track_queue.R(큐 + 처분 원장 2지점).
#   배선 도달 검사 = 08_Tests/contracts/test_atomic_json_write.R 축 D.
#
#------------------------------------------------------------------------------
# ★실측 (R 4.5.2 ucrt · Windows 11 · OneDrive 경로 · 2026-08-23)
#
#   [측정 1] file.rename(tmp, target) 은 target 이 **존재해도 덮어쓴다** → TRUE.
#            로컬 NTFS(TEMP) · OneDrive 경로 양쪽 동일.
#            ⇒ 구 사본들의 `if (file.exists(path)) file.remove(path)` 선삭제는
#              **불필요할 뿐 아니라 원자성을 깬다** — 삭제와 rename 사이에 파일이
#              아예 없는 창이 생겨, 그 창에 읽은 소비자는 "부재"를 관측한다.
#              (axiom_context_inject.sh 가 겪은 "변동부 통째 소실"과 같은 모양.)
#              본 정본은 선삭제를 하지 않는다.
#
#   [측정 2] 소비자가 대상 파일 핸들을 연 채이면:
#              file.remove(target)              -> FALSE
#              file.rename(tmp, target)         -> FALSE   (WinError 5 계열)
#              file.copy(tmp, target, overwrite)-> **TRUE** ← 제자리 덮어쓰기 = 절단원
#            핸들 해제 후 file.rename            -> TRUE
#            ⇒ 구 사본의 copy 폴백은 "rename 이 실패하는 유일한 실전 사유"에서
#              정확히 발화하는데, 그 사유가 **바로 copy 가 파일을 찢는 상황**이다.
#              폴백이 결함을 고치는 게 아니라 결함을 만든다.
#            ⇒ 본 정본의 1차 수단은 **유한 재시도**다(핸들은 ms 단위로 풀린다).
#
#   [측정 3] tmp 는 target 과 **같은 디렉터리**에 만든다 — 다른 볼륨이면 rename 이
#            원자적일 수 없다. 같은 디렉터리면 cross-device 실패 자체가 불가능하다.
#
#------------------------------------------------------------------------------
# ★copy 폴백의 한계 (allow_copy_fallback = TRUE 로 명시 선택할 때만 발화)
#   file.copy(overwrite=TRUE) 는 대상을 **제자리에서** 자르고 다시 쓴다. 그 사이
#   읽는 소비자는 절단된 JSON 을 본다 — 즉 이 경로는 **원자적이지 않다**. 위 [측정 2]
#   대로 이 경로가 필요한 상황 = 소비자가 읽는 중인 상황이므로, 폴백은 사실상
#   "찢을 확률이 가장 높은 순간에만 켜지는 스위치"다. 기본값이 FALSE 인 이유가 이것이다.
#   기본 동작: 재시도 소진 시 **stop()** — 조용한 훼손보다 시끄러운 실패를 택한다
#   (침묵 실패 금지). 호출자가 훼손을 감수해야 하는 사유가 있다면 명시적으로 켤 것.
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })

# 재시도 사다리 — 0.02s 부터 배증, 개별 상한 0.25s. 8회 총 ≈ 1.3s.
#   근거: [측정 2] 의 핸들 점유는 소비자 1회 read 시간(수 ms)이라 첫 1~2회에서 대개 풀린다.
#   상한을 두는 이유 = 무인 러너가 여기서 무한정 매달리면 정체 경보가 늦는다.
ATOMIC_JSON_RETRIES    <- 8L
ATOMIC_JSON_SLEEP_INIT <- 0.02
ATOMIC_JSON_SLEEP_CAP  <- 0.25

#' JSON 을 원자적으로 기록한다 (tmp → rename, 선삭제 없음, 유한 재시도).
#'
#' @param obj      jsonlite 로 직렬화할 객체
#' @param path     최종 경로. tmp 는 같은 디렉터리에 만든다([측정 3]).
#' @param ...      write_json() 에 그대로 전달 (auto_unbox / pretty / digits / null / na 등)
#' @param validate TRUE 면 promote 전에 tmp 를 되읽어 파싱 가능한지 확인한다.
#'                 직렬화가 깨진 산출물을 정본 자리에 올리지 않기 위한 것 — "썼다"와
#'                 "읽을 수 있는 것을 썼다"는 다른 명제다.
#' @param allow_copy_fallback 재시도 소진 시 file.copy 로 덮어쓸지. **원자성 없음**(위 한계 참조).
#' @param tag      로그/에러 접두어 (호출자 식별)
#' @return invisible(TRUE). 실패 시 stop().
qvest_atomic_write_json <- function(obj, path, ..., validate = TRUE,
                                    allow_copy_fallback = FALSE,
                                    tag = "atomic_json",
                                    retries = ATOMIC_JSON_RETRIES) {
  d <- dirname(path)
  if (nzchar(d) && !dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)

  # tmp 는 반드시 같은 디렉터리 — cross-device rename 불가 조건을 원천 제거([측정 3]).
  tmp <- file.path(d, sprintf(".%s.tmp%s", basename(path), Sys.getpid()))
  write_json(obj, tmp, ...)

  if (isTRUE(validate)) {
    chk <- tryCatch(fromJSON(tmp, simplifyVector = FALSE), error = function(e) e)
    if (inherits(chk, "error")) {
      suppressWarnings(file.remove(tmp))
      stop(sprintf("[%s] 직렬화 산출물이 파싱 불가 — 정본 미갱신: %s (%s)",
                   tag, path, conditionMessage(chk)))
    }
  }

  # ★선삭제 없음([측정 1]). file.rename 은 존재하는 대상을 덮어쓴다.
  for (i in seq_len(max(1L, as.integer(retries)))) {
    if (isTRUE(suppressWarnings(file.rename(tmp, path)))) return(invisible(TRUE))
    Sys.sleep(min(ATOMIC_JSON_SLEEP_CAP, ATOMIC_JSON_SLEEP_INIT * 2^(i - 1)))
  }

  if (isTRUE(allow_copy_fallback)) {
    # ⚠원자성 없음: file.copy 는 대상을 제자리에서 자르고 다시 쓴다. 이 순간 읽는
    #   소비자는 절단 JSON 을 본다. 발화 자체를 사건으로 남긴다(조용한 강등 금지).
    warning(sprintf("[%s] rename %d회 실패 → copy 폴백 (★비원자적 — 동시 읽기 시 절단 가능): %s",
                    tag, retries, path), call. = FALSE)
    ok <- suppressWarnings(file.copy(tmp, path, overwrite = TRUE))
    suppressWarnings(file.remove(tmp))
    if (!isTRUE(ok)) stop(sprintf("[%s] copy 폴백도 실패: %s", tag, path))
    return(invisible(TRUE))
  }

  # tmp 를 남긴다 — 페이로드 회수 가능하게. 에러가 시끄러우므로 잔재가 방치되지 않는다.
  stop(sprintf(paste0("[%s] 원자적 기록 실패 (rename %d회) — 정본 미갱신: %s\n",
                      "  기록분은 %s 에 보존됨. 대개 소비자가 대상 핸들을 점유 중이다([측정 2])."),
               tag, retries, path, tmp))
}

# 소스 확인용 표지 — 배선 도달 검사(축 D)가 이 심볼의 존재로 "정본을 실제로 쓰는가"를 판정한다.
ATOMIC_JSON_SOT <- "02_Infrastructure/utils/atomic_json.R"
