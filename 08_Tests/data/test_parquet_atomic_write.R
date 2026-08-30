#!/usr/bin/env Rscript
#==============================================================================
# test_parquet_atomic_write.R — parquet 원자적 쓰기 정본의 위반 주입 검사
#   대상: 02_Infrastructure/utils/atomic_parquet.R::qvest_atomic_write_parquet
#   신설: 2026-08-30 (PG2 9월 리밸 오버레이 배관 결함 ③ 수리 동반)
#
# ## 무엇을 재는가
# 벤치마크/RAWDATA 캐시 쓰기가 (a) 실패해도 **원본을 남기는가** (b) 실패를 **삼키지 않는가**
# (c) 구판의 **선삭제 부재 창**을 정말로 없앴는가.
#
# ## 왜 (2026-08-29 23:27 실사고)
# `.cache/benchmark.parquet` 이 삭제된 뒤 재작성 전에 프로세스가 죽어 **부재**로 남았다.
# 하류 정지: `[bm-gate][B] benchmark.parquet 부재 — 거래일 판정 불가` ·
# `[regime_jump_model] ERR: Windows error 2` · `SJM regime_jump refresh FAILED`.
# 구판 3지점(krx_build_rawdata BM/RAWDATA · rawdata_sanitize BM/RAWDATA)이 전부
# `write_parquet(tmp)` → **`file.remove(target)`** → `file.rename` 이었고, rename 반환값을
# 버려서 실패가 조용했다.
#
# ## 검출력 실증 (돌연변이)
# 축 B1 이 구판 패턴을 그대로 재현해 **부재 창이 실제로 열린다**는 것을 보인다 —
# 통과가 검사기 사망이 아님을 증명한다(양성 대조 없는 계기는 방어선으로 세지 않는다).
#
# 실행: Rscript 08_Tests/data/test_parquet_atomic_write.R
#==============================================================================
suppressPackageStartupMessages({ library(arrow); library(data.table) })

## ── 루트 앵커 = self 최우선 (r-portability.md ④-b) ───────────────────────────
##   테스트 러너는 **자기가 실린 트리**를 검사해야 한다. env(QM_ROOT)를 먼저 보면
##   worktree 에서 낸 초록이 main 의 코드를 검증하게 된다(run_all_hooks.sh 선례).
.self <- tryCatch(normalizePath(dirname(sub("^--file=", "",
           grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), winslash = "/"),
         error = function(e) NA_character_)
.MARKER <- "02_Infrastructure/utils/atomic_parquet.R"
.pick_root <- function() {
  cands <- c(if (!is.na(.self)) file.path(.self, "..", ".."),
             Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())
  for (c in cands) {
    if (!nzchar(c)) next
    c <- gsub("\\\\", "/", c)
    if (file.exists(file.path(c, .MARKER))) return(normalizePath(c, winslash = "/"))
  }
  NULL
}
ROOT <- .pick_root()
if (is.null(ROOT)) { cat("PROJECT_ROOT 해석 실패 — 표지", .MARKER, "없음\n"); quit(status = 2) }
source(file.path(ROOT, .MARKER))

PASS <- 0L; FAILS <- character(0)
ok <- function(name, note = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n          %s\n", name, note)) }
bad <- function(name, msg) { FAILS <<- c(FAILS, name); cat(sprintf("  ★FAIL %s\n          %s\n", name, msg)) }
chk <- function(name, expr) {
  r <- tryCatch(expr, error = function(e) structure(conditionMessage(e), class = "terr"))
  if (inherits(r, "terr")) bad(name, r) else ok(name, r)
}

TD <- file.path(tempdir(), paste0("atomparq_", Sys.getpid()))
dir.create(TD, recursive = TRUE, showWarnings = FALSE)
.fix <- function(n = 100L) data.table(Date = as.Date("2026-01-01") + seq_len(n) - 1L,
                                      BM_Close = as.numeric(seq_len(n)),
                                      BM_Ret = rep(0.001, n))
.fresh <- function(tag, n = 100L) {
  p <- file.path(TD, paste0(tag, ".parquet")); write_parquet(.fix(n), p); p
}
.strays <- function(p) length(list.files(dirname(p), pattern = paste0("^\\.", basename(p), "\\.tmp"),
                                         all.files = TRUE))

cat(strrep("=", 78), "\n")
cat("test_parquet_atomic_write — qvest_atomic_write_parquet 위반 주입\n")
cat(strrep("=", 78), "\n")

## ── A. 정상 경로 ─────────────────────────────────────────────────────────────
chk("A1  정상 기록 — 내용 교체 + tmp 잔재 0", {
  p <- .fresh("a1")
  qvest_atomic_write_parquet(.fix(250L), p, tag = "t/a1")
  out <- as.data.table(read_parquet(p))
  if (nrow(out) != 250L) stop(sprintf("행 수 %d (기대 250)", nrow(out)))
  if (.strays(p) != 0L) stop(sprintf("tmp 잔재 %d개", .strays(p)))
  sprintf("100행 → %d행 교체, tmp 잔재 0", nrow(out))
})

chk("A2  대상 부재에서도 생성된다 (최초 기록)", {
  p <- file.path(TD, "a2_new.parquet")
  qvest_atomic_write_parquet(.fix(7L), p, tag = "t/a2")
  if (!file.exists(p)) stop("생성 안 됨")
  sprintf("신규 생성 %d행", nrow(read_parquet(p)))
})

## ── B. ★돌연변이: 구판 선삭제 패턴이 부재 창을 만든다 ────────────────────────
chk("B1  ★검출력 실증: 구판(선삭제) 패턴은 부재 창을 실제로 연다", {
  p <- .fresh("b1")
  tmp <- paste0(p, ".tmp")
  write_parquet(.fix(250L), tmp)
  if (file.exists(p)) file.remove(p)              # ← 구판 그대로
  gap <- !file.exists(p)                          # 이 순간 소비자는 '부재'를 본다
  file.rename(tmp, p)
  if (!gap) stop("구판이 부재 창을 안 만듦 — 돌연변이 무효(검사가 아무것도 시험 못 함)")
  # 신판은 같은 지점에서 부재 창이 없다: tmp 로 쓰는 동안 대상은 계속 존재한다.
  p2 <- .fresh("b1b")
  seen_absent <- FALSE
  qvest_atomic_write_parquet(.fix(250L), p2, tag = "t/b1", validate = TRUE)
  if (!file.exists(p2)) seen_absent <- TRUE
  if (seen_absent) stop("신판도 부재를 남김")
  "구판: remove~rename 사이 exists=FALSE / 신판: 전 구간 exists=TRUE"
})

## ── C. 실패 주입 — 원본이 살아남는가, 실패가 시끄러운가 ──────────────────────
chk("C1  tmp 검증 실패 주입 → stop + 원본 불변 + tmp 정리", {
  p <- .fresh("c1")
  before <- read_parquet(p)
  # write_parquet 을 '적게 쓰는' 것으로 바꿔 검증 축(행 수)이 발화하게 한다.
  # ★정본은 globalenv 로 source 되므로 조회 순서가 local → globalenv → package:arrow 다.
  #   globalenv 에 섀도를 두면 가로채진다 — assignInNamespace 는 이 경로를 못 잡는다(실측:
  #   초판이 그렇게 짜서 주입이 무해해졌고 검사가 거짓 빨강을 냈다).
  .real <- arrow::write_parquet
  assign("write_parquet",
         function(x, sink, ...) .real(utils::head(as.data.frame(x), 3L), sink, ...),
         envir = globalenv())
  e <- tryCatch({ qvest_atomic_write_parquet(.fix(250L), p, tag = "t/c1"); NULL },
                error = function(e) conditionMessage(e))
  if (exists("write_parquet", envir = globalenv(), inherits = FALSE))
    rm("write_parquet", envir = globalenv())
  if (is.null(e)) stop("검증 실패가 통과됨 — 가드 사망")
  if (!grepl("검증 실패", e)) stop(sprintf("다른 가드가 발화: %s", e))
  after <- read_parquet(p)
  if (!identical(nrow(before), nrow(after))) stop("원본이 변경됨")
  if (.strays(p) != 0L) stop("실패했는데 tmp 가 남음(검증 실패 경로는 정리한다)")
  sprintf("차단 + 원본 %d행 불변", nrow(after))
})

chk("C2  rename 실패 주입(대상 핸들 점유) → stop + 원본 불변 + tmp 보존", {
  p <- .fresh("c2")
  before_n <- nrow(read_parquet(p))
  con <- file(p, "rb")                            # 소비자가 읽는 중을 모사(file() 이 이미 연 채 반환)
  on.exit(try(close(con), silent = TRUE), add = TRUE)
  e <- tryCatch({ qvest_atomic_write_parquet(.fix(250L), p, tag = "t/c2", retries = 2L); NULL },
                error = function(e) conditionMessage(e))
  close(con)
  if (is.null(e)) {
    # 이 플랫폼에서 핸들이 rename 을 막지 않으면 주입이 성립하지 않는다 —
    # '통과'가 아니라 '미측정'으로 보고한다(빈 결과 = 합격 금지).
    stop("SKIPPABLE: 열린 핸들이 rename 을 막지 않음 — 주입 무효")
  }
  if (!grepl("원자적 기록 실패", e)) stop(sprintf("다른 경로로 실패: %s", e))
  if (nrow(read_parquet(p)) != before_n) stop("원본이 변경됨")
  if (.strays(p) < 1L) stop("tmp 가 보존되지 않음 — 페이로드 회수 불가")
  sprintf("차단 + 원본 %d행 불변 + tmp 보존", before_n)
})

## ── D. 배선 도달 — 정본을 **실제로 쓰는가** ─────────────────────────────────
##   "만들었다" 와 "부른다" 는 다른 명제다. 구 결함이 정확히 3벌 인라인 복제였으므로
##   소비자 쪽에서 선삭제가 사라졌는지까지 본다.
chk("D1  소비자 배선 — krx_build_rawdata.R / rawdata_sanitize.R 가 정본을 호출", {
  miss <- character(0)
  for (f in c("02_Infrastructure/data/krx_build_rawdata.R",
              "02_Infrastructure/data/rawdata_sanitize.R")) {
    s <- paste(readLines(file.path(ROOT, f), warn = FALSE), collapse = "\n")
    if (!grepl("qvest_atomic_write_parquet", s, fixed = TRUE)) miss <- c(miss, f)
  }
  if (length(miss)) stop(sprintf("정본 미호출: %s", paste(miss, collapse = ", ")))
  "2/2 호출"
})

chk("D2  ★선삭제 잔재 0 — BM_CACHE/RAWDATA_CACHE 를 지우고 쓰는 코드가 없다", {
  hits <- character(0)
  for (f in c("02_Infrastructure/data/krx_build_rawdata.R",
              "02_Infrastructure/data/rawdata_sanitize.R")) {
    ln <- readLines(file.path(ROOT, f), warn = FALSE)
    h <- grep("file\\.remove\\((BM_CACHE|RAWDATA_CACHE)\\)", ln)
    if (length(h)) hits <- c(hits, sprintf("%s:%s", f, paste(h, collapse = ",")))
  }
  if (length(hits)) stop(sprintf("선삭제 잔존: %s", paste(hits, collapse = " | ")))
  "2/2 청소됨"
})

chk("D3  정본 자신은 선삭제도 copy 폴백도 갖지 않는다", {
  # ★주석은 제외한다 — 정본 docstring 이 "copy 폴백은 절단원"이라고 **설명**하고 있어서
  #   원문 전체 검사는 자기 설명에 걸린다(초판 실측 오탐). 코드 라인만 본다.
  ln <- readLines(file.path(ROOT, .MARKER), warn = FALSE)
  code <- sub("#.*$", "", ln[!grepl("^\\s*#", ln)])
  s <- paste(code, collapse = "\n")
  if (grepl("file\\.copy\\(", s)) stop("copy 폴백 존재 — 절단원(카드 규칙 2 위반)")
  if (grepl("file\\.remove\\(path\\)", s)) stop("대상 선삭제 존재")
  # 음성 대조: 주석 제거가 검사까지 죽이지 않았는지 — 코드에 copy 를 넣으면 반드시 걸려야 한다.
  if (!grepl("file\\.copy\\(", paste(c(code, "  file.copy(tmp, path)"), collapse = "\n")))
    stop("돌연변이 무효 — 주석 제거가 검사기까지 눈멀게 함")
  "copy 폴백 0 · 대상 선삭제 0 (돌연변이 대조 통과)"
})

unlink(TD, recursive = TRUE, force = TRUE)

cat(strrep("-", 78), "\n")
NT <- PASS + length(FAILS)
cat(sprintf("  %d/%d PASS\n", PASS, NT))
if (length(FAILS)) cat("  ★실패:", paste(FAILS, collapse = ", "), "\n")
cat(sprintf('{"test":"parquet_atomic_write","pass":%d,"fail":%d,"total":%d,"skipped":0}\n',
            PASS, length(FAILS), NT))
quit(status = if (length(FAILS)) 1L else 0L)
