## ============================================================================
## STR_1715 May 2026 Forward Recompute — Step 1: Extend regime_panel
##
## Source: stage_artifacts/WT_D20260425_007/run_alpha_regime.R lines 142-264
## Modification:
##   - TRAIN_END 2024-01-22 → SIGNAL_CUTOFF_MAY 2026-04-22 (lockbox 만료, 도훈 명시)
##   - Lockbox window 만료 처리 (2024-01-23 ~ 2026-01-23 calendar passed)
##   - Logic 자체는 변경 없음 (expanding percentile + 4-state regime, C1 + C2 + C9 + C11)
##
## Output:
##   - qepm/mailbox/worktask/WT-P20260429_002/forge_may2026/regime_panel_extended.parquet
##   (원본 stage_artifacts/WT_D20260425_007/regime_panel.parquet 보존)
## ============================================================================

cat("=== STR_1715 May 2026 Forward Recompute — Step 1: regime_panel extension ===\n")
cat("시작:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(lubridate)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-P20260429_002"
OUT_DIR      <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID, "forge_may2026")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

# ---- Lockbox release per 도훈 directive ----
LOCKBOX_START   <- as.Date("2024-01-23")
LOCKBOX_END     <- as.Date("2026-01-23")  # calendar passed on 2026-05-01
# SIGNAL_CUTOFF for regime panel = month_end of latest fully-realized month (= 2026-04-30).
# This produces sig_date 2026-05-01 (first day of next month) for 5월 운용.
# C2 compliance: regime_state at 2026-05-01 sig_date is built from data through 2026-04-30 (t-1 days strictly).
SIGNAL_CUTOFF   <- as.Date("2026-04-30")
TRAIN_END_NEW   <- SIGNAL_CUTOFF
cat(sprintf("[Step 1] SIGNAL_CUTOFF = %s (extended from 2024-01-22 lockbox-pre)\n", SIGNAL_CUTOFF))

# ---- Load RAWDATA + BM_DT ----
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)
setkey(RAWDATA, Date, Ticker)

cat(sprintf("[Step 1] RAWDATA: %d rows, max=%s | BM_DT: %d rows, max=%s\n",
            nrow(RAWDATA), as.character(max(RAWDATA$Date)),
            nrow(BM_DT), as.character(max(BM_DT$Date))))

bm_ret_col <- if ("BM_Ret" %in% names(BM_DT)) "BM_Ret" else
              if ("Ret"    %in% names(BM_DT)) "Ret"    else NULL
stopifnot(!is.null(bm_ret_col))

# Daily breadth proxy
breadth_daily <- RAWDATA[!is.na(Ret), .(
  breadth_pos_pct = mean(Ret > 0, na.rm = TRUE),
  n_active        = .N
), by = Date]
setkey(breadth_daily, Date)

# ---- Build regime feature panel — extend to SIGNAL_CUTOFF ----
me_dates <- BM_DT[Date <= SIGNAL_CUTOFF,
  .(month_end = max(Date)),
  by = .(YM = format(Date, "%Y-%m"))]$month_end
me_dates <- sort(unique(me_dates))
cat(sprintf("[Step 1] me_dates: %d months (%s ~ %s)\n",
            length(me_dates), as.character(min(me_dates)), as.character(max(me_dates))))

build_regime_features <- function(me) {
  win_60 <- BM_DT[Date <= me & Date >  me - 90]
  if (nrow(win_60) < 30L) return(NULL)
  rv60 <- sd(win_60[[bm_ret_col]], na.rm = TRUE) * sqrt(252)
  win_21 <- BM_DT[Date <= me & Date > me - 35]
  ret_1m <- if (nrow(win_21) >= 5L) prod(1 + win_21[[bm_ret_col]], na.rm = TRUE) - 1 else NA_real_
  win_252 <- BM_DT[Date <= me & Date > me - 380]
  if (nrow(win_252) < 20L) {
    dd_12m <- NA_real_
  } else {
    px      <- cumprod(1 + win_252[[bm_ret_col]])
    peak    <- cummax(px)
    dd_12m  <- min(px / peak - 1, na.rm = TRUE)
  }
  br_60 <- breadth_daily[Date <= me & Date > me - 90, mean(breadth_pos_pct, na.rm = TRUE)]
  data.table(
    month_end = me,
    rv60      = rv60,
    ret_1m    = ret_1m,
    dd_12m    = dd_12m,
    breadth60 = br_60
  )
}

regime_feat <- rbindlist(lapply(me_dates, build_regime_features), fill = TRUE)
regime_feat <- regime_feat[!is.na(rv60) & !is.na(dd_12m)]
setorder(regime_feat, month_end)
cat(sprintf("[Step 1] Regime feature panel: %d months (%s ~ %s)\n",
            nrow(regime_feat),
            as.character(min(regime_feat$month_end)),
            as.character(max(regime_feat$month_end))))

# ---- Expanding percentile + 4-state classification (logic 동일) ----
expanding_percentile <- function(x) {
  n <- length(x); out <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (i == 1L) { out[i] <- 0.5; next }
    past <- x[seq_len(i - 1L)]
    past <- past[is.finite(past)]
    if (length(past) < 6L) { out[i] <- 0.5; next }
    out[i] <- mean(past <= x[i], na.rm = TRUE)
  }
  out
}

regime_feat[, pct_rv60     := expanding_percentile(rv60)]
regime_feat[, pct_neg_ret  := expanding_percentile(-ret_1m)]
regime_feat[, pct_neg_dd   := expanding_percentile(-dd_12m)]
regime_feat[, pct_neg_brth := expanding_percentile(-breadth60)]
regime_feat[, regime_score := 0.35 * pct_rv60 + 0.25 * pct_neg_ret +
                              0.25 * pct_neg_dd + 0.15 * pct_neg_brth]

cls_thr_q <- function(scores, qs = c(0.30, 0.65, 0.85)) {
  n <- length(scores); out <- character(n)
  for (i in seq_len(n)) {
    if (i < 12L) { out[i] <- "NORMAL"; next }
    past <- scores[seq_len(i - 1L)]
    past <- past[is.finite(past)]
    if (length(past) < 12L) { out[i] <- "NORMAL"; next }
    th <- quantile(past, probs = qs, na.rm = TRUE)
    s  <- scores[i]
    out[i] <- if (s <= th[1]) "BULL"
              else if (s <= th[2]) "NORMAL"
              else if (s <= th[3]) "CAUTION"
              else "CRISIS"
  }
  out
}
regime_feat[, regime_state := cls_thr_q(regime_score)]

# Signal lag — built at month_end, applied at first day of next month
regime_feat[, sig_date := {
  d <- month_end + 1L
  as.Date(format(d, "%Y-%m-01"))
}]
# Deduplicate: keep latest month_end per sig_date (when month has multiple Date observations
# in BM_DT that produce same first-day-of-next-month sig_date, use the most recent).
# This matches Iter 2 behavior on the original train window.
setorder(regime_feat, sig_date, -month_end)
regime_feat <- regime_feat[, .SD[1L], by = sig_date]
setkey(regime_feat, sig_date)

cat("[Step 1] Regime distribution (extended window):\n")
print(regime_feat[, .N, by = regime_state][order(-N)])

cat("\n[Step 1] Tail (2024+ extension):\n")
print(regime_feat[sig_date >= as.Date("2024-01-01"),
                  .(sig_date, regime_state, regime_score)])

# Save extended regime_panel
out_path <- file.path(OUT_DIR, "regime_panel_extended.parquet")
write_parquet(regime_feat, out_path)
cat(sprintf("\n[Step 1] Saved: %s (%d rows)\n", out_path, nrow(regime_feat)))

# Audit comparison vs original
orig_path <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260425_007/regime_panel.parquet")
if (file.exists(orig_path)) {
  orig <- as.data.table(read_parquet(orig_path))
  orig[, sig_date := as.Date(sig_date)]
  cat(sprintf("\n[Step 1 AUDIT] Original regime_panel: %d rows, max=%s\n",
              nrow(orig), as.character(max(orig$sig_date))))
  # Check whether overlap region is identical
  common <- intersect(orig$sig_date, regime_feat$sig_date)
  if (length(common) > 0) {
    o <- orig[sig_date %in% common, .(sig_date, regime_state)][order(sig_date)]
    n <- regime_feat[sig_date %in% common, .(sig_date, regime_state)][order(sig_date)]
    setnames(n, "regime_state", "regime_state_new")
    m <- merge(o, n, by = "sig_date")
    n_match <- sum(m$regime_state == m$regime_state_new, na.rm = TRUE)
    cat(sprintf("[Step 1 AUDIT] Overlap rows: %d, regime_state match: %d/%d (%.1f%%)\n",
                length(common), n_match, length(common), 100*n_match/length(common)))
  }
}

cat("\n=== Step 1 DONE ===\n")
