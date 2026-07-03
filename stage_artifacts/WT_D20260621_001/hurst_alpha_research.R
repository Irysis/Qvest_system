#==============================================================================
# WT-D20260621_001 — Hurst-Conditioned Persistence-Quality Momentum
# Alpha Research Agent — α̂ ONLY (NO covariance, NO weights)
#
# Concept: Hurst exponent H (long-range dependence of the return path) as a
#   momentum-QUALITY dimension. H>0.5 persistent (momentum reliable),
#   H<0.5 anti-persistent (momentum reverses / crash-prone).
# Estimator: DFA (Detrended Fluctuation Analysis, Peng 1994) primary; R/S cross-check.
# Operationalizations A/B/C tested. Orthogonality vs M01/M08/M13.
#
# PIT: all lookbacks Date<=sig_date (C1). DFA detrending per-window, NOT full-sample (C1/C7).
#      Cross-sectional z (C13). Forward 1M return is realized (not in signal).
# Real-computation: canonical_screen_bt() (contract build_benchmark_compare). NO proxy.
#==============================================================================

# ---- segfault guards: single thread, no nested parallel ----
Sys.setenv(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1",
           MKL_NUM_THREADS = "1", R_DATATABLE_NUM_THREADS = "1")
suppressMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})
setDTthreads(1L)
try(arrow::set_cpu_count(1L), silent = TRUE)
try(arrow::set_io_thread_count(1L), silent = TRUE)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT_A <- file.path(ROOT, "stage_artifacts", "WT_D20260621_001")
dir.create(OUT_A, showWarnings = FALSE, recursive = TRUE)
LOG <- function(...) cat(sprintf("[%s] ", format(Sys.time(), "%H:%M:%S")), ..., "\n")

set.seed(20260621)

#==============================================================================
# 1. Load rawdata (price path) — restrict columns + 2005-01-01 onward
#==============================================================================
LOG("Loading rawdata.parquet ...")
RAW <- as.data.table(read_parquet(
  ".cache/rawdata.parquet",
  col_select = c("Date","Ticker","Close","Ret","Vol","Size","Sector",
                 "BM_Ret","K200","KQ150","Market","AdminStock","TradingHalt")
))
RAW[, Date := as.Date(Date)]
# universe membership: KOSPI200 ∪ KOSDAQ150 (flags are PIT membership per row)
# Keep full history pre-2005 for lookback warmup, but signal dates >= 2005.
LOG("rawdata rows (full):", nrow(RAW))

# MEMORY TRIM: keep only tickers that are EVER members of K200/KQ150 (any date),
# and only dates from 2002 (3y warmup before 2005 signal start). Drops ~3900->~600 tickers.
ever_member <- RAW[K200 == 1 | KQ150 == 1, unique(Ticker)]
RAW <- RAW[Ticker %in% ever_member & Date >= as.Date("2002-01-01")]
gc()
LOG("rawdata rows (trimmed to ever-member tickers, 2002+):", nrow(RAW),
    " n_ticker:", uniqueN(RAW$Ticker),
    " dates:", as.character(min(RAW$Date)), "->", as.character(max(RAW$Date)))

#==============================================================================
# 2. Monthly signal-date grid (month-end trading days), 2005+
#==============================================================================
all_dates <- sort(unique(RAW$Date))
dt_d <- data.table(Date = all_dates, ym = format(all_dates, "%Y%m"))
month_end <- dt_d[, .(Date = max(Date)), by = ym]
sig_dates <- month_end[Date >= as.Date("2005-01-01") & Date <= as.Date("2026-05-31"), Date]
sig_dates <- sort(sig_dates)
LOG("signal dates (month-end):", length(sig_dates), " from", as.character(min(sig_dates)), "to", as.character(max(sig_dates)))

#==============================================================================
# 3. Estimators
#==============================================================================
# DFA (Peng 1994): profile = cumsum(x - mean(x)); split into windows of size s;
#   detrend each window with linear fit; F(s) = sqrt(mean of detrended variances).
#   H = slope of log F(s) vs log s.   Robust to non-stationary linear drift.
# Per-window detrending uses ONLY data inside that lookback window (Date<=sig_date) → C1/C7 safe.
dfa_hurst <- function(x, scales = NULL) {
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < 64L) return(NA_real_)
  y <- cumsum(x - mean(x))                       # integrated profile
  if (is.null(scales)) {
    smax <- floor(n / 4L)
    if (smax < 16L) return(NA_real_)
    scales <- unique(round(exp(seq(log(8), log(smax), length.out = 12L))))
    scales <- scales[scales >= 8L & scales <= smax]
  }
  if (length(scales) < 4L) return(NA_real_)
  Fs <- numeric(length(scales))
  for (k in seq_along(scales)) {
    s <- scales[k]
    nb <- floor(n / s)
    if (nb < 1L) { Fs[k] <- NA_real_; next }
    idx <- 1:(nb * s)
    seg <- matrix(y[idx], nrow = s)              # columns = non-overlapping windows
    tt <- seq_len(s)
    # linear detrend each column, collect residual variances
    rv <- apply(seg, 2L, function(col) {
      fit <- .lm.fit(cbind(1, tt), col)
      mean(fit$residuals^2)
    })
    Fs[k] <- sqrt(mean(rv))
  }
  ok <- is.finite(Fs) & Fs > 0
  if (sum(ok) < 4L) return(NA_real_)
  fit <- .lm.fit(cbind(1, log(scales[ok])), log(Fs[ok]))
  as.numeric(fit$coefficients[2L])
}

# R/S (rescaled range, Hurst 1951 / Mandelbrot) — cross-check estimator.
rs_hurst <- function(x, scales = NULL) {
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < 64L) return(NA_real_)
  if (is.null(scales)) {
    smax <- floor(n / 2L)
    scales <- unique(round(exp(seq(log(16), log(smax), length.out = 10L))))
    scales <- scales[scales >= 16L & scales <= smax]
  }
  if (length(scales) < 4L) return(NA_real_)
  RS <- numeric(length(scales))
  for (k in seq_along(scales)) {
    s <- scales[k]
    nb <- floor(n / s)
    if (nb < 1L) { RS[k] <- NA_real_; next }
    vals <- numeric(nb)
    for (b in seq_len(nb)) {
      seg <- x[((b - 1L) * s + 1L):(b * s)]
      m <- mean(seg); dev <- cumsum(seg - m)
      R <- max(dev) - min(dev); S <- sd(seg)
      vals[b] <- if (is.finite(S) && S > 0) R / S else NA_real_
    }
    RS[k] <- mean(vals, na.rm = TRUE)
  }
  ok <- is.finite(RS) & RS > 0
  if (sum(ok) < 4L) return(NA_real_)
  fit <- .lm.fit(cbind(1, log(scales[ok])), log(RS[ok]))
  as.numeric(fit$coefficients[2L])
}

# momentum 12-1 (252d lookback, skip last 21d) from returns — matches compute_momentum M01
mom_12_1 <- function(rets) {
  n <- length(rets)
  if (n <= 252L) return(NA_real_)
  s <- n - 252L + 1L; e <- n - 21L
  if (e <= s) return(NA_real_)
  prod(1 + rets[s:e]) - 1
}
# residual momentum (CAPM residual 252d cum, skip 1m) — matches M08
resid_mom <- function(rets, bm) {
  ok <- is.finite(rets) & is.finite(bm)
  r <- rets[ok]; b <- bm[ok]; nm <- length(r)
  if (nm < 252L) return(NA_real_)
  fit <- .lm.fit(cbind(1, b), r); res <- fit$residuals; nr <- length(res)
  e <- nr - 21L; s <- max(1L, nr - 252L + 1L)
  if (e <= s) return(NA_real_)
  sum(res[s:e])
}
# vol-adjusted momentum (M01 / realized vol) — matches M13
voladj_mom <- function(rets) {
  n <- length(rets)
  if (n <= 252L) return(NA_real_)
  s <- n - 252L + 1L; e <- n - 21L
  if (e <= s) return(NA_real_)
  rm <- prod(1 + rets[s:e]) - 1
  rv <- sd(rets[s:e], na.rm = TRUE) * sqrt(252)
  if (is.finite(rv) && rv > 1e-8) rm / rv else NA_real_
}

#==============================================================================
# 4. Per signal-date panel: compute H (DFA 252/126/504), R/S 252, M01/M08/M13
#    + 20d ADV (t-1 PIT) + forward 1M return
#==============================================================================
LOG("Building monthly panel (Hurst + momentum cluster) ...")
setkey(RAW, Ticker, Date)

# Checkpoint directory: write each month's feat to its own rds so a crash is recoverable.
CKPT <- file.path(OUT_A, "panel_ckpt")
dir.create(CKPT, showWarnings = FALSE, recursive = TRUE)

panel_list <- vector("list", length(sig_dates))

# helper: liquidity ADV (20d avg of Close*Vol) at t-1 (<= sig_date), C10
for (i in seq_along(sig_dates)) {
  ckpt_f <- file.path(CKPT, sprintf("m_%03d.rds", i))
  if (file.exists(ckpt_f)) { panel_list[[i]] <- readRDS(ckpt_f); next }
  sd_i <- sig_dates[i]
  # universe: members of K200 or KQ150 as of sig_date
  univ <- RAW[Date == sd_i & (K200 == 1 | KQ150 == 1) &
              (is.na(AdminStock) | AdminStock == 0) &
              (is.na(TradingHalt) | TradingHalt == 0), unique(Ticker)]
  if (length(univ) == 0L) next

  win <- RAW[Ticker %in% univ & Date <= sd_i]
  setorder(win, Ticker, Date)

  feat <- win[, {
    rets <- Ret[is.finite(Ret)]
    n <- length(rets)
    cl  <- Close
    vol <- Vol
    nn  <- .N
    # 20d ADV (t-1): use last 20 obs up to sig_date (Date<=sd_i, last row is sd_i=t close;
    #   ADV is informational liquidity filter, use trailing 20d ending at sig_date)
    adv <- if (nn >= 20L) mean((cl * vol)[(nn - 19L):nn], na.rm = TRUE) else NA_real_
    # DFA on daily returns over lookback windows
    last_n <- function(v, k) { m <- length(v); if (m >= k) v[(m - k + 1L):m] else v }
    H252 <- if (n >= 252L) dfa_hurst(last_n(rets, 252L)) else NA_real_
    H126 <- if (n >= 126L) dfa_hurst(last_n(rets, 126L)) else NA_real_
    H504 <- if (n >= 504L) dfa_hurst(last_n(rets, 504L)) else NA_real_
    HRS252 <- if (n >= 252L) rs_hurst(last_n(rets, 252L)) else NA_real_
    bm <- BM_Ret
    .(adv = adv,
      H252 = H252, H126 = H126, H504 = H504, HRS252 = HRS252,
      M01 = mom_12_1(rets),
      M08 = resid_mom(Ret, bm),
      M13 = voladj_mom(rets))
  }, by = Ticker]
  feat[, Date := sd_i]
  saveRDS(feat, ckpt_f)            # checkpoint (crash-recoverable)
  panel_list[[i]] <- feat
  rm(win, feat);
  if (i %% 12L == 0L) { gc(verbose = FALSE); LOG(sprintf("  ... %d/%d  (%s)  univ=%d", i, length(sig_dates), as.character(sd_i), length(univ))) }
}
panel <- rbindlist(panel_list, use.names = TRUE, fill = TRUE)
LOG("panel rows:", nrow(panel), " unique dates:", uniqueN(panel$Date))

#==============================================================================
# 5. Forward 1M realized return per (Ticker, sig_date)
#==============================================================================
LOG("Computing forward 1M realized returns ...")
# For each sig_date, realized return from sd_i to next sd. Use cumulative daily Ret.
fwd_list <- vector("list", length(sig_dates) - 1L)
for (i in seq_len(length(sig_dates) - 1L)) {
  d0 <- sig_dates[i]; d1 <- sig_dates[i + 1L]
  seg <- RAW[Date > d0 & Date <= d1, .(Ret_1m = prod(1 + Ret[is.finite(Ret)]) - 1), by = Ticker]
  seg[, Date := d0]
  fwd_list[[i]] <- seg
}
fwd <- rbindlist(fwd_list, use.names = TRUE)
panel <- merge(panel, fwd, by = c("Date","Ticker"), all.x = TRUE)

# benchmark forward 1M (BM_Ret realized)
bm_fwd_list <- vector("list", length(sig_dates) - 1L)
for (i in seq_len(length(sig_dates) - 1L)) {
  d0 <- sig_dates[i]; d1 <- sig_dates[i + 1L]
  bseg <- unique(RAW[Date > d0 & Date <= d1, .(Date2 = Date, BM_Ret)])
  bret <- prod(1 + bseg$BM_Ret[is.finite(bseg$BM_Ret)]) - 1
  bm_fwd_list[[i]] <- data.table(Date = d0, BM_Ret = bret)
}
bench_dt <- rbindlist(bm_fwd_list, use.names = TRUE)

saveRDS(panel, file.path(OUT_A, "panel_raw.rds"))
saveRDS(bench_dt, file.path(OUT_A, "bench_fwd.rds"))
LOG("Saved panel_raw.rds + bench_fwd.rds")
LOG("DONE stage 1 (panel build). Run hurst_alpha_eval.R next.")
