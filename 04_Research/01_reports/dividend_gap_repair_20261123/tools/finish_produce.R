## finish_produce.R — fundamental_produce_v2.R 의 3/4(후보 검사) · 4/4(사본 · 교체)만 그대로 돌린다.
##   까닭: 2026-11-24 08:27 실행이 1/4 · 2/4(분기 표 · 캐시 후보)를 끝낸 직후 메모리 안전장치에 걸려 멈췄다(후보는 온전 · 정본 그대로).
##   아래 3 · 4 단계 코드는 02_Infrastructure/data/fundamental_produce_v2.R 의 것을 글자 그대로 옮긴 것이다.
##   다른 점 둘: ① 1 · 2 단계를 다시 돌리지 않는다(후보가 분기 표보다 새것인지 먼저 단정) ② 끝의 '사본은 최근 3개만' 정리를 하지 않는다(옛 사본을 지우지 않음).
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
t0 <- Sys.time()
.say <- function(...) cat("[fund-v2-produce:finish]", sprintf(...), "\n")
ROOT <- "G:/OneDrive/Quant_Module_Moltbot"
CACHE <- file.path(ROOT, ".cache")
V2D <- file.path(CACHE, "fundamental_v2")
CAND_M <- file.path(V2D, "candidate_fundamental_quarterly.parquet")
CAND_X <- file.path(V2D, "candidate_fundamental_annual.parquet")
CANON_M <- file.path(CACHE, "fundamental_quarterly.parquet")
CANON_X <- file.path(CACHE, "fundamental_annual.parquet")
CAND_ONLY <- "--candidate-only" %in% commandArgs(trailingOnly = TRUE)

## ---- 단정: 후보는 이번 분기 표로 만든 것이다 ----
qt <- file.path(V2D, "fund_v2_quarterly.parquet")
rep <- fromJSON(file.path(V2D, "fundamental_caches_report.json"))
stopifnot(file.exists(CAND_M), file.exists(CAND_X), file.exists(qt),
          file.mtime(CAND_M) > file.mtime(qt), file.mtime(CAND_X) > file.mtime(qt),
          normalizePath(rep$input, winslash = "/", mustWork = FALSE) == normalizePath(qt, winslash = "/", mustWork = FALSE))
.say("후보 = 분기 표(%s) 뒤에 만든 것 · 생산 보고 %s", format(file.mtime(qt), "%m-%d %H:%M:%S"), rep$built_at)

# ---- 3. 후보 검사 ----------------------------------------------------------------------------------
.fail <- character()
.check <- function(path, label, canon) {
  if (!file.exists(path)) { .fail <<- c(.fail, sprintf("%s 후보 없음", label)); return(invisible(NULL)) }
  d <- as.data.table(read_parquet(path, col_select = c("Ticker", "Item", "Period_Date", "Factor_Date")))
  if (uniqueN(d$Ticker) < 2000L) .fail <<- c(.fail, sprintf("%s 종목 %d(< 2000)", label, uniqueN(d$Ticker)))
  if (uniqueN(d$Item) < 300L) .fail <<- c(.fail, sprintf("%s 항목 %d(< 300)", label, uniqueN(d$Item)))
  setorder(d, Ticker, Item, Period_Date)
  bad <- d[, .(v = Factor_Date <= shift(Factor_Date) & Ticker == shift(Ticker) & Item == shift(Item))][v == TRUE, .N]
  if (bad > 0L) .fail <<- c(.fail, sprintf("%s 날짜 순서 계약 위반 %d", label, bad))
  if (any(d$Factor_Date <= d$Period_Date)) .fail <<- c(.fail, sprintf("%s Factor_Date <= Period_Date", label))
  if (file.exists(canon)) {
    n_old <- nrow(read_parquet(canon, col_select = "Ticker"))
    if (nrow(d) < 0.95 * n_old)
      .fail <<- c(.fail, sprintf("%s 행 %s < 지금 정본 %s 의 95%%", label, format(nrow(d), big.mark = ","), format(n_old, big.mark = ",")))
  }
  .say("   %s 후보: 행 %s · 종목 %d · 항목 %d · 날짜 %s~%s", label, format(nrow(d), big.mark = ","), uniqueN(d$Ticker),
       uniqueN(d$Item), format(min(d$Factor_Date)), format(max(d$Factor_Date)))
  invisible(NULL)
}
.say("3/4 후보 검사...")
WAS_V2 <- file.exists(file.path(CACHE, "fundamental_backup", "ACTIVE_V2"))
.check(CAND_M, "분기 캐시", CANON_M)
invisible(gc())
.check(CAND_X, "연간 캐시", CANON_X)
if (length(.fail)) { .say("오류: 후보 검사 실패 — 정본 그대로: %s", paste(.fail, collapse = " | ")); quit(save = "no", status = 1) }
if (CAND_ONLY) { .say("후보만(--candidate-only) — 정본 그대로 · %.0fs", as.numeric(difftime(Sys.time(), t0, units = "secs"))); quit(save = "no", status = 0) }

# ---- 4. 사본 · 교체 --------------------------------------------------------------------------------
stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
bdir <- file.path(CACHE, "fundamental_backup", paste0(if (!WAS_V2) "pre_v2_" else "", stamp))
dir.create(bdir, recursive = TRUE, showWarnings = FALSE)
for (f in c(CANON_M, CANON_X)) if (file.exists(f) && !file.copy(f, file.path(bdir, basename(f)), overwrite = FALSE)) {
  .say("오류: 사본 실패 — 교체하지 않는다: %s", f); quit(save = "no", status = 1)
}
.say("4/4 사본: %s", bdir)
.replace <- function(src, dst) {
  tmp <- paste0(dst, ".tmp", Sys.getpid())
  if (!file.copy(src, tmp, overwrite = TRUE)) return(FALSE)
  if (file.exists(dst)) unlink(dst)
  file.rename(tmp, dst)
}
if (!.replace(CAND_M, CANON_M) || !.replace(CAND_X, CANON_X)) {
  .say("오류: 교체 실패 — 사본에서 되돌릴 것: %s", bdir); quit(save = "no", status = 1)
}
writeLines(c(stamp, bdir), file.path(CACHE, "fundamental_backup", "ACTIVE_V2"))
.say("정본 교체 완료: %s · %s · %.0fs", CANON_M, CANON_X, as.numeric(difftime(Sys.time(), t0, units = "secs")))
quit(save = "no", status = 0)
