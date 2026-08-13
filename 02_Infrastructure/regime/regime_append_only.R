#!/usr/bin/env Rscript
## regime_append_only.R — 국면 계열 append-only 원장 (도훈 지시 2026-08-13 "1번 가자")
##
## **왜 필요한가**: 재서술의 원천이 둘인데 코드 수리는 하나만 닫는다.
##   내부 생성 — MSM 전체표본 디민(commit b514830e 수리) · 파라미터 mtime 선택 · 기타 전체표본 통계
##   외부 개정 — **FRED 가 시계열을 소급 개정한다**. 핀 스냅샷 실측(2026-08-13):
##     2026-07-16 핀 → 2026-08 핀   과거 1,521셀
##     2026-09 핀   → 라이브        과거 **3,000셀** (Chi_Fin_Cond 1,320 · StL_Fin_Stress 1,361 ·
##                                   US_M2 312, 최초 개정일 2000-01-07 = 26년 전 값까지)
##   후자는 우리 코드의 결함이 아니라 외부 사실이라 **어떤 코드 수리로도 제거되지 않는다**.
##   그리고 FRED 는 Regime_Score = layer1 + **0.35*FRED_MRS** + layer3 로 합성의 35%다.
##   ⇒ 외부 개정을 막는 층은 코드가 아니라 **발행 원장(append-only)** 뿐이다.
##   m4 는 m4_append_only.R 로 보호되는데 정작 **그 상류인 국면 계열이 무방비**였다.
##
## **국면 계열 고유 조건 — 진행 중인 구간은 동결하지 않는다**:
##   월간 계열은 월말 날짜로 스탬프되는데 마지막 행이 **진행 중인 달**이다(실측: 오늘 2026-08-13
##   기준 2026-08-31 행 존재). 그 행은 매일 갱신되는 게 정상이므로 동결 대상이 아니다.
##   완료 경계 = 월간이면 현재월 1일, 일간이면 오늘. 그 이전 행만 동결한다.
##   ★이걸 안 나누면 "정상 갱신"을 재서술로 오탐해 매일 차단이 걸린다.
##
## 사용: Rscript regime_append_only.R [--series monthly|daily] [--as-of YYYY-MM-DD] [--init] [--dry-run]
## 종료: 0 정상 / 1 동결행 결정값 재서술 검출(발행본 보존) / 2 입력·환경 오류

## ★★arrow 교착 방어 — `ARROW_IO_THREADS=1` ∧ `mmap=FALSE` 에서만 read_parquet 가 자기 교착한다
##   (2026-08-13 2×3 격자 실측. 상세 = m4_append_only.R 상단). 이 스크립트도 mmap=FALSE 를 쓰므로
##   호출자가 =1 을 걸면 daily_refresh 가 조용히 멈춘다. 저장소 관행(reports/ 15개)대로 2로 올린다.
if (suppressWarnings(as.integer(Sys.getenv("ARROW_IO_THREADS", "0"))) %in% 1L) Sys.setenv(ARROW_IO_THREADS = "2")
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
try(if (arrow::io_thread_count() < 2L) arrow::set_io_thread_count(2L), silent = TRUE)
options(scipen = 999)
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))

a <- commandArgs(TRUE)
getarg <- function(k, d = NA) { i <- which(a == k); if (length(i) && length(a) > i[1]) a[i[1] + 1L] else d }
SERIES <- getarg("--series", "monthly")
AS_OF  <- as.Date(getarg("--as-of", as.character(Sys.Date())))
INIT   <- "--init" %in% a
DRY    <- "--dry-run" %in% a
if (!SERIES %in% c("monthly", "daily")) stop("--series 는 monthly|daily")

LIVE   <- file.path(ROOT, if (SERIES == "monthly") ".cache/unified_regime_signal.parquet"
                          else ".cache/unified_regime_signal_daily.parquet")
PUBDIR <- file.path(ROOT, "06_Registry/regime_published")
PUB    <- file.path(PUBDIR, sprintf("regime_signal_%s_published.parquet", SERIES))
META   <- file.path(PUBDIR, sprintf("regime_signal_%s_meta.json", SERIES))
SIDE   <- file.path(PUBDIR, sprintf("regime_signal_%s_ledger.jsonl", SERIES))
DLOG   <- file.path(PUBDIR, "regime_drift_log.jsonl")

## 2계층: 결정값이 바뀌면 차단, 입력값 이동은 로그 (m4_append_only.R 와 같은 규약)
DECISION_COLS <- c("Regime_Score", "Category", "Cash_Pct")
INPUT_COLS    <- c("MSM_Crisis_Prob", "FRED_MRS", "KTRI_Score", "VEA_Score")

say <- function(...) cat(sprintf(...))
die <- function(code, msg) { cat(sprintf("[regime-append] ERROR %s\n", msg)); quit(status = code) }
## ★Windows: read_parquet mmap=TRUE 는 같은 경로 쓰기를 막는다(error 1224) — 되쓸 파일은 FALSE
rp <- function(p) as.data.table(read_parquet(p, mmap = FALSE))

if (!file.exists(LIVE)) die(2, sprintf("라이브 계열 부재: %s", LIVE))
live <- rp(LIVE); live[, Date := as.Date(Date)]; setorder(live, Date)
say("[regime-append] %s 라이브 n=%d  %s ~ %s\n", SERIES, nrow(live), min(live$Date), max(live$Date))

## ── 완료 경계 ────────────────────────────────────────────────────────────────
cur_start <- if (SERIES == "monthly") as.Date(format(AS_OF, "%Y-%m-01")) else AS_OF
completed <- live[Date < cur_start]
if (!nrow(completed)) die(2, sprintf("완료 구간이 비어 있음 (경계 %s)", cur_start))
ft_new <- max(completed$Date)
say("[regime-append] 완료 경계 %s → 동결 대상 종점 %s · 진행중 행 %d개\n",
    cur_start, ft_new, nrow(live[Date >= cur_start]))

if (!dir.exists(PUBDIR)) dir.create(PUBDIR, recursive = TRUE, showWarnings = FALSE)
if (!file.exists(PUB)) {
  if (!INIT) die(2, sprintf("발행 원장 부재 — 최초 1회 --init 로 현재 상태를 기준선으로 동결할 것: %s", PUB))
  write_parquet(live, PUB)
  write_json(list(series = SERIES, frozen_through = as.character(ft_new),
                  initialized = as.character(Sys.time()), n = nrow(live)),
             META, auto_unbox = TRUE, pretty = TRUE)
  say("[regime-append] ★발행 원장 초기화 (n=%d, frozen_through=%s)\n", nrow(live), ft_new)
  quit(status = 0)
}
pub <- rp(PUB); pub[, Date := as.Date(Date)]; setorder(pub, Date)
mt <- fromJSON(META); ft_prev <- as.Date(mt$frozen_through)
say("[regime-append] 발행 원장 n=%d · frozen_through %s\n", nrow(pub), ft_prev)

## ── 동결 구간 대조 (Date <= ft_prev) — 보고만, 적용하지 않음 ─────────────────
frz <- as.character(intersect(as.character(pub[Date <= ft_prev]$Date), as.character(live$Date)))
say("[regime-append] 동결 구간 공통 %d행 대조\n", length(frz))
hard <- list(); soft <- list()
cmpcol <- function(cl) {
  if (!(cl %in% names(pub)) || !(cl %in% names(live))) return(NULL)
  p <- pub[as.character(Date) %in% frz][order(Date)]; l <- live[as.character(Date) %in% frz][order(Date)]
  x <- p[[cl]]; y <- l[[cl]]
  bad <- if (is.numeric(x) && is.numeric(y)) which(!is.na(x) & !is.na(y) & abs(x - y) > 1e-9)
         else which(as.character(x) != as.character(y))
  if (!length(bad)) return(NULL)
  list(col = cl, n = length(bad),
       mx = if (is.numeric(x)) max(abs(y[bad] - x[bad])) else NA_real_,
       ex = paste(sprintf("%s %s->%s", as.character(p$Date[bad]), x[bad], y[bad])[seq_len(min(3, length(bad)))],
                  collapse = " | "))
}
for (cl in DECISION_COLS) { r <- cmpcol(cl); if (!is.null(r)) hard[[cl]] <- r }
for (cl in INPUT_COLS)    { r <- cmpcol(cl); if (!is.null(r)) soft[[cl]] <- r }
if (length(soft)) {
  say("[regime-append] 입력 드리프트(로그): ")
  for (r in soft) say("%s %d행%s  ", r$col, r$n, if (is.na(r$mx)) "" else sprintf("(최대 Δ%.4g)", r$mx))
  say("\n            └ FRED 소급 개정 등 — 결정값에 닿지 않는 한 통과\n")
}
if (length(hard)) {
  say("\n[regime-append] ★★동결 구간 결정값 재서술 시도 — 적용하지 않고 발행본 유지\n")
  for (r in hard) say("   %s: %d행%s\n      %s\n", r$col, r$n,
                      if (is.na(r$mx)) "" else sprintf(" (최대 Δ%.4g)", r$mx), r$ex)
}

## ── 병합: 동결분은 발행본, 그 이후는 라이브 ─────────────────────────────────
final <- rbindlist(list(pub[Date <= ft_prev], live[Date > ft_prev, .SD, .SDcols = names(pub)]),
                   use.names = TRUE)
setorder(final, Date)
n_newfrozen <- nrow(live[Date > ft_prev & Date <= ft_new])
n_open      <- nrow(final[Date > ft_new])
say("[regime-append] 병합: 동결 %d행(발행본) + 신규동결 %d행(라이브, 이번에 완료) + 진행중 %d행\n",
    nrow(pub[Date <= ft_prev]), n_newfrozen, n_open)

## ★R 최상위에서 if/else 를 줄바꿈으로 나누면 파싱 오류 — 중괄호로 묶는다
gaps <- if (SERIES == "monthly") {
  setdiff(format(seq(min(final$Date), max(final$Date), by = "month"), "%Y-%m"),
          format(final$Date, "%Y-%m"))
} else character(0)
if (length(gaps)) say("[regime-append] ★월 결손 %d개: %s\n", length(gaps), paste(utils::head(gaps, 8), collapse = " "))

if (DRY) { say("[regime-append] dry-run — 기록 안 함\n"); quit(status = if (length(hard)) 1 else 0) }

ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
invisible(file.copy(PUB, paste0(PUB, ".bak_", ts), overwrite = FALSE))
write_parquet(final, PUB)
invisible(file.copy(LIVE, paste0(LIVE, ".regen_", ts), overwrite = FALSE))
write_parquet(final, LIVE)   ## 소비자가 안정된 이력을 보도록 라이브도 발행본으로 동기화
write_json(list(series = SERIES, frozen_through = as.character(ft_new),
                updated = as.character(Sys.time()), n = nrow(final)),
           META, auto_unbox = TRUE, pretty = TRUE)

## git 추적용 텍스트 사이드카 (.parquet 은 gitignore 대상 — 원칙① 증거가 diff 로 남아야 한다)
sd_ <- final[, .SD, .SDcols = intersect(c("Date", DECISION_COLS, INPUT_COLS), names(final))][order(Date)]
sd_[, Date := as.character(Date)]
con <- file(SIDE, "w", encoding = "UTF-8")
for (i in seq_len(nrow(sd_))) writeLines(toJSON(as.list(sd_[i]), auto_unbox = TRUE, digits = 10), con)
close(con)
cat(toJSON(list(ts = ts, series = SERIES, frozen_through_prev = as.character(ft_prev),
                frozen_through_new = as.character(ft_new), n = nrow(final),
                n_newly_frozen = n_newfrozen, n_open = n_open,
                drift_hard = lapply(hard, function(r) list(col = r$col, n = r$n, ex = r$ex)),
                drift_soft = lapply(soft, function(r) list(col = r$col, n = r$n, max = r$mx))),
           auto_unbox = TRUE), "\n", file = DLOG, append = TRUE)
say("[regime-append] 기록 완료 — 원장 n=%d · frozen_through %s → %s · 사이드카 %d행\n",
    nrow(final), ft_prev, ft_new, nrow(sd_))

if (length(hard)) { say("[regime-append] 종료 1 — 동결 구간 재서술 시도(발행본 보존). 상류 확인 필요.\n"); quit(status = 1) }
say("[regime-append] OK\n"); quit(status = 0)
