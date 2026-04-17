cat("=== STR_1631 Weight Extreme: C19 Top-20 Weight Method Exhaustive Comparison ===\n")
## 핵심 아이디어: C19 상위 20종목 유니버스 고정, 비중결정 방법만 극한 테스트
## run_monthly_simulation() + mclapply 병렬 (OPT-3/4 준수)
## 월간 리밸런싱, 오버레이 없음 (순수 비중 결정력 측정)
## PIT: C1(expanding/rolling only), C2(t-1 lag), C9(vol/dd t-1)

t0 <- Sys.time()

# ===================================================================
# 0. Environment Setup
# ===================================================================
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR  <- file.path(PROJECT_ROOT, ".cache")
CONS_DIR   <- file.path(CACHE_DIR, "consensus")
REGIME_DIR <- file.path(FUNC_PATH, "regime")
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR    <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales)
  library(lubridate); library(jsonlite); library(parallel)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

LIQ_THRESHOLD <- 2e8
N_HOLD        <- 20L
MAX21D_EXCL   <- 0.80
MAX_W         <- 0.15
N_CORES       <- min(4L, detectCores() - 1L)

cat(sprintf("[setup] PROJECT_ROOT: %s | cores: %d\n", PROJECT_ROOT, N_CORES))

# ===================================================================
# 1. Load RAWDATA + infrastructure (single bulk load, OPT-1/2)
# ===================================================================
cat("\n[Step 1] Loading RAWDATA + infrastructure...\n")
source(file.path(FUNC_PATH, "backtest_harness.R"))
source(file.path(FUNC_PATH, "portfolio/hrp_core.R"))
source(file.path(FUNC_PATH, "portfolio/advanced_weights.R"))

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
RAWDATA[, Date := as.Date(Date)]; BM_DT[, Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]; BM_DT <- BM_DT[Date >= ANALYSIS_START_DATE]
dc <- intersect(c("Open", "High", "Low", "source", "Size", "Market"), names(RAWDATA))
if (length(dc) > 0) RAWDATA[, (dc) := NULL]
if (!"Name" %in% names(RAWDATA) || !"Sector" %in% names(RAWDATA)) {
  ud <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, "universe.parquet")))
  ud[, Date := as.Date(Date)]; setorder(ud, Ticker, -Date)
  ti <- ud[, .(Name = Name[1], Sector = Sector[1]), by = Ticker]
  if (!"Name" %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ti[, .(Ticker, Name)], by = "Ticker", all.x = TRUE)
  if (!"Sector" %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ti[, .(Ticker, Sector)], by = "Ticker", all.x = TRUE)
  rm(ud, ti)
}
gc(verbose = FALSE)

# ===================================================================
# 1b. Bulk consensus load (all 5 files at once, OPT-1)
# ===================================================================
cat("[Step 1b] Bulk loading consensus parquets...\n")
cons_files <- c("sue.parquet", "esbr.parquet", "eps_chg_1m.parquet",
                "coverage.parquet", "target_price.parquet")
cons_list <- lapply(cons_files, function(f) {
  dt <- as.data.table(arrow::read_parquet(file.path(CONS_DIR, f)))
  dt[, Date := as.Date(Date)]; dt <- dt[Date >= ANALYSIS_START_DATE]
  setkey(dt, Ticker, Date); dt
})
names(cons_list) <- c("sue", "esbr", "eps1m", "cov", "tp")
SUE_DT <- cons_list$sue; ESBR_DT <- cons_list$esbr; EPS1M_DT <- cons_list$eps1m
COV_DT <- cons_list$cov; TP_DT <- cons_list$tp
rm(cons_list)

# Signal dates (monthly)
RAWDATA[, YM := format(Date, "%Y-%m")]
sd_dt <- RAWDATA[, .(sig_date = max(Date)), by = YM]; setorder(sd_dt, sig_date)
sd_dt <- sd_dt[sig_date >= SIGNAL_START_DATE]
SIG_DATES <- sd_dt$sig_date

# Pre-compute LIQ and MAX21d
setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradVal := Close * Vol]
RAWDATA[, LIQ_20d := frollmean(TradVal, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
RAWDATA[, TradVal := NULL]
RAWDATA[, Ret_abs := abs(Ret)]
RAWDATA[, MAX21d_raw := {
  ra <- Ret_abs; n <- length(ra)
  if (n < 21L) cummax(fifelse(is.na(ra), -Inf, ra))
  else frollapply(ra, n = 21L, FUN = max, fill = NA, align = "right")
}, by = Ticker]
RAWDATA[, MAX21d := shift(MAX21d_raw, n = 1L, type = "lag"), by = Ticker]
RAWDATA[, c("Ret_abs", "MAX21d_raw") := NULL]

SIG_SNAP <- RAWDATA[Date %in% SIG_DATES & !is.na(Close),
                     .(Date, Ticker, Close, LIQ_20d, MAX21d)]
setkey(SIG_SNAP, Date, Ticker)
RAWDATA[, c("LIQ_20d", "MAX21d", "YM") := NULL]
setkey(RAWDATA, Date, Ticker)
gc(verbose = FALSE)

cat(sprintf("[Step 1] %d signal dates (%s ~ %s)\n",
            length(SIG_DATES), min(SIG_DATES), max(SIG_DATES)))

# ===================================================================
# 2. Build C19 FACTORS (vectorized lapply, no for+parquet)
# ===================================================================
cat("\n[Step 2] Building C19 top-20...\n")
z_safe <- function(x) {
  nv <- sum(!is.na(x)); if (nv < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x))); (x - mu) / s
}

FACTORS <- rbindlist(lapply(seq_along(SIG_DATES), function(i) {
  sd <- SIG_DATES[i]
  univ <- SIG_SNAP[Date == sd & !is.na(LIQ_20d)][LIQ_20d >= LIQ_THRESHOLD]
  if (nrow(univ) < 30L) return(NULL)
  mq <- quantile(univ$MAX21d, MAX21D_EXCL, na.rm = TRUE)
  univ <- univ[is.na(MAX21d) | MAX21d <= mq]; if (nrow(univ) < 30L) return(NULL)
  probe <- data.table(Ticker = univ$Ticker, Date = sd); setkey(probe, Ticker, Date)
  sue_j   <- SUE_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, sue)]
  esbr_j  <- ESBR_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, esbr)]
  eps1m_j <- EPS1M_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, eps_chg_1m)]
  cov_j   <- COV_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, coverage)]
  tp_j    <- TP_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, target_price)]
  sig <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = FALSE),
                list(univ[, .(Ticker, Close)], sue_j, esbr_j, eps1m_j, cov_j, tp_j))
  sig <- sig[!is.na(coverage) & coverage >= 3L]; if (nrow(sig) < 20L) return(NULL)
  sig[, TP_Gap := (target_price - Close) / Close]
  sig[, z_sue := z_safe(sue)]; sig[, z_esbr := z_safe(esbr)]
  sig[, z_eps1m := z_safe(eps_chg_1m)]; sig[, z_tpgap := z_safe(TP_Gap)]
  sig <- sig[!is.na(z_sue) & !is.na(z_esbr) & !is.na(z_eps1m) & !is.na(z_tpgap)]
  if (nrow(sig) < 20L) return(NULL)
  sig[, C19 := (z_sue + z_esbr + z_eps1m + z_tpgap) / 4]
  setorder(sig, -C19); top <- head(sig, N_HOLD)
  data.table(Date = sd, Ticker = top$Ticker, Score = top$C19)
}))
cat(sprintf("[Step 2] FACTORS: %d rows | %d months\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
rm(SUE_DT, ESBR_DT, EPS1M_DT, COV_DT, TP_DT, SIG_SNAP); gc(verbose = FALSE)

# ===================================================================
# 3. Load Regime v7 (single read)
# ===================================================================
cat("\n[Step 3] Loading Regime v7...\n")
REGIME <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, "regime_v7.parquet")))
# regime_v7: month_end = Date, apply_month = char
if ("month_end" %in% names(REGIME)) {
  REGIME[, Date := tryCatch(as.Date(month_end), error = function(e) as.Date(as.numeric(month_end), origin="1970-01-01"))]
} else {
  REGIME[, Date := as.Date(paste0(apply_month, "-01")) + 30L]
}
REGIME <- REGIME[!is.na(Date)]; setkey(REGIME, Date)
cat(sprintf("[Step 3] Regime: %d rows\n", nrow(REGIME)))

# ===================================================================
# 4. Pre-compute weight lookup tables (all methods, vectorized)
# ===================================================================
cat("\n[Step 4] Pre-computing weight lookups...\n")

all_trade_dates <- sort(unique(RAWDATA$Date))
sig_date_list <- sort(unique(FACTORS$Date))

get_ret_sub <- function(sd, lookback = 120L) {
  idx <- which(all_trade_dates < sd)
  if (length(idx) < lookback) lb_dates <- all_trade_dates[idx]
  else lb_dates <- all_trade_dates[tail(idx, lookback)]
  RAWDATA[Date %in% lb_dates, .(Date, Ticker, Ret)]
}

get_mrs <- function(d) {
  v <- REGIME[Date <= d][.N, MRS]
  if (length(v) == 0 || is.na(v)) 0 else v
}

# MRS momentum: MRS(t-1) - MRS(t-2). Both already t-1 lagged in regime_v7.
# REGIME rows are monthly. For sig_date d, get the 2 most recent rows.
get_mrs_mom <- function(d) {
  sub <- REGIME[Date <= d]
  n <- nrow(sub)
  if (n < 2) return(list(mrs = 0, mrs_prev = 0, mom = 0))
  mrs_curr <- sub[n, MRS]; mrs_prev <- sub[n - 1L, MRS]
  if (is.na(mrs_curr)) mrs_curr <- 0; if (is.na(mrs_prev)) mrs_prev <- 0
  list(mrs = mrs_curr, mrs_prev = mrs_prev, mom = mrs_curr - mrs_prev)
}

weight_bank <- list()

# Vectorized weight computation helper (lapply-based)
compute_weights_lapply <- function(method_name, weight_fn) {
  cat(sprintf("  [weights] %s... ", method_name))
  t_w <- Sys.time()
  wl <- setNames(lapply(sig_date_list, function(sd) {
    w <- tryCatch(weight_fn(sd), error = function(e) NULL)
    if (is.null(w)) {
      tickers <- FACTORS[Date == sd, Ticker]
      return(setNames(rep(1/length(tickers), length(tickers)), tickers))
    }
    w
  }), as.character(sig_date_list))
  cat(sprintf("%.1fs\n", as.numeric(difftime(Sys.time(), t_w, units = "secs"))))
  wl
}

# M01-M18: base methods
weight_bank[["EW"]] <- compute_weights_lapply("EW", function(sd) {
  tickers <- FACTORS[Date == sd, Ticker]; setNames(rep(1/length(tickers), length(tickers)), tickers)
})

weight_bank[["InvVol"]] <- compute_weights_lapply("InvVol", function(sd) {
  tickers <- FACTORS[Date == sd, Ticker]; n <- length(tickers)
  ret_sub <- get_ret_sub(sd, 60L)
  vols <- ret_sub[Ticker %in% tickers, .(vol = sd(Ret, na.rm = TRUE)), by = Ticker]
  vol_vec <- setNames(rep(NA_real_, n), tickers); vol_vec[vols$Ticker] <- vols$vol
  med_v <- median(vol_vec, na.rm = TRUE)
  if (is.na(med_v) || med_v < 1e-10) return(setNames(rep(1/n, n), tickers))
  vol_vec[is.na(vol_vec)] <- med_v; vol_vec[vol_vec < 1e-10] <- med_v
  w <- 1 / vol_vec; w <- pmin(w / sum(w), MAX_W); w / sum(w)
})

weight_bank[["HRP_GerberRMT"]] <- compute_weights_lapply("HRP_GerberRMT", function(sd) {
  tickers <- FACTORS[Date == sd, Ticker]; ret_sub <- get_ret_sub(sd, 60L)
  w <- calc_hrp_weights(tickers, ret_sub, n_days = 60, max_w = MAX_W, cov_method = "gerber_rmt")
  setNames(w, tickers)
})

weight_bank[["ScoreTilt"]] <- compute_weights_lapply("ScoreTilt", function(sd) {
  f <- FACTORS[Date == sd]; tickers <- f$Ticker; scores <- setNames(f$Score, f$Ticker)
  ret_sub <- get_ret_sub(sd, 60L)
  w <- calc_score_tilt_weights(tickers, scores, ret_sub, n_days = 60, max_w = MAX_W,
                                alpha = 0.4, cov_method = "gerber_rmt")
  setNames(w, tickers)
})

weight_bank[["MinVar"]] <- compute_weights_lapply("MinVar", function(sd) {
  tickers <- FACTORS[Date == sd, Ticker]; ret_sub <- get_ret_sub(sd, 120L)
  w <- calc_minvar_weights(tickers, ret_sub, n_days = 120, max_w = MAX_W); setNames(w, tickers)
})

weight_bank[["RiskParity"]] <- compute_weights_lapply("RiskParity", function(sd) {
  tickers <- FACTORS[Date == sd, Ticker]; ret_sub <- get_ret_sub(sd, 120L)
  w <- calc_riskparity_weights(tickers, ret_sub, n_days = 120, max_w = MAX_W); setNames(w, tickers)
})

weight_bank[["NCO"]] <- compute_weights_lapply("NCO", function(sd) {
  tickers <- FACTORS[Date == sd, Ticker]; ret_sub <- get_ret_sub(sd, 120L)
  w <- calc_nco_weights(tickers, ret_sub, n_days = 120, max_w = MAX_W); setNames(w, tickers)
})

weight_bank[["CVaR_LP"]] <- compute_weights_lapply("CVaR_LP", function(sd) {
  tickers <- FACTORS[Date == sd, Ticker]; ret_sub <- get_ret_sub(sd, 120L)
  w <- calc_cvar_lp_weights(tickers, ret_sub, alpha = 0.95, n_days = 120, max_w = MAX_W); setNames(w, tickers)
})

weight_bank[["CDaR"]] <- compute_weights_lapply("CDaR", function(sd) {
  tickers <- FACTORS[Date == sd, Ticker]; ret_sub <- get_ret_sub(sd, 120L)
  w <- calc_cdar_weights(tickers, ret_sub, alpha = 0.95, n_days = 120, max_w = MAX_W); setNames(w, tickers)
})

weight_bank[["HigherMoment"]] <- compute_weights_lapply("HigherMoment", function(sd) {
  tickers <- FACTORS[Date == sd, Ticker]; ret_sub <- get_ret_sub(sd, 120L)
  w <- calc_higher_moment_weights(tickers, ret_sub, n_days = 120, max_w = MAX_W); setNames(w, tickers)
})

weight_bank[["Omega"]] <- compute_weights_lapply("Omega", function(sd) {
  tickers <- FACTORS[Date == sd, Ticker]; ret_sub <- get_ret_sub(sd, 120L)
  w <- calc_omega_weights(tickers, ret_sub, n_days = 120, max_w = MAX_W); setNames(w, tickers)
})

weight_bank[["CVaR_Budget"]] <- compute_weights_lapply("CVaR_Budget", function(sd) {
  tickers <- FACTORS[Date == sd, Ticker]; ret_sub <- get_ret_sub(sd, 120L)
  w <- calc_cvar_budget_weights(tickers, ret_sub, alpha = 0.95, n_days = 120, max_w = MAX_W); setNames(w, tickers)
})

weight_bank[["PMTD"]] <- compute_weights_lapply("PMTD", function(sd) {
  tickers <- FACTORS[Date == sd, Ticker]; ret_sub <- get_ret_sub(sd, 120L)
  w <- calc_pmtd_weights(tickers, ret_sub, alpha = 0.95, n_days = 120, max_w = MAX_W); setNames(w, tickers)
})

weight_bank[["Kelly"]] <- compute_weights_lapply("Kelly", function(sd) {
  tickers <- FACTORS[Date == sd, Ticker]; ret_sub <- get_ret_sub(sd, 120L)
  w <- calc_kelly_weights(tickers, ret_sub, n_days = 120, max_w = MAX_W, fraction = 0.25); setNames(w, tickers)
})

weight_bank[["MaxDiv"]] <- compute_weights_lapply("MaxDiv", function(sd) {
  tickers <- FACTORS[Date == sd, Ticker]; ret_sub <- get_ret_sub(sd, 120L)
  w <- calc_maxdiv_weights(tickers, ret_sub, n_days = 120, max_w = MAX_W); setNames(w, tickers)
})

weight_bank[["Entropy"]] <- compute_weights_lapply("Entropy", function(sd) {
  f <- FACTORS[Date == sd]; tickers <- f$Ticker; scores <- setNames(f$Score, f$Ticker)
  ret_sub <- get_ret_sub(sd, 120L)
  w <- calc_entropy_weights(tickers, scores, ret_sub, n_days = 120, max_w = MAX_W); setNames(w, tickers)
})

weight_bank[["Resampled"]] <- compute_weights_lapply("Resampled", function(sd) {
  tickers <- FACTORS[Date == sd, Ticker]; ret_sub <- get_ret_sub(sd, 120L)
  w <- calc_resampled_weights(tickers, ret_sub, n_days = 120, max_w = MAX_W, n_sim = 50); setNames(w, tickers)
})

weight_bank[["RobustMV"]] <- compute_weights_lapply("RobustMV", function(sd) {
  tickers <- FACTORS[Date == sd, Ticker]; ret_sub <- get_ret_sub(sd, 120L)
  w <- calc_robust_mv_weights(tickers, ret_sub, n_days = 120, max_w = MAX_W, shrinkage = 0.5); setNames(w, tickers)
})

# M19: InvVol x Score (multiplicative)
weight_bank[["InvVol_x_Score"]] <- compute_weights_lapply("InvVol_x_Score", function(sd) {
  f <- FACTORS[Date == sd]; tickers <- f$Ticker; scores <- f$Score; n <- length(tickers)
  ret_sub <- get_ret_sub(sd, 60L)
  vols <- ret_sub[Ticker %in% tickers, .(vol = sd(Ret, na.rm = TRUE)), by = Ticker]
  vol_vec <- setNames(rep(NA_real_, n), tickers); vol_vec[vols$Ticker] <- vols$vol
  med_v <- median(vol_vec, na.rm = TRUE)
  if (is.na(med_v) || med_v < 1e-10) return(setNames(rep(1/n, n), tickers))
  vol_vec[is.na(vol_vec)] <- med_v; vol_vec[vol_vec < 1e-10] <- med_v
  sc <- scores - min(scores) + 0.01
  w <- (1 / vol_vec) * sc; w <- pmin(w / sum(w), MAX_W); setNames(w / sum(w), tickers)
})

# M20-M23: Top-N methods
compute_topn_lapply <- function(method_name, n_top, weight_fn) {
  cat(sprintf("  [weights] %s... ", method_name))
  t_w <- Sys.time()
  wl <- setNames(lapply(sig_date_list, function(sd) {
    f <- FACTORS[Date == sd]; setorder(f, -Score)
    top <- head(f, n_top); tickers <- top$Ticker
    w <- tryCatch(weight_fn(sd, tickers, top), error = function(e) NULL)
    if (is.null(w)) return(setNames(rep(1/length(tickers), length(tickers)), tickers))
    w
  }), as.character(sig_date_list))
  cat(sprintf("%.1fs\n", as.numeric(difftime(Sys.time(), t_w, units = "secs"))))
  wl
}

weight_bank[["Top10_EW"]] <- compute_topn_lapply("Top10_EW", 10, function(sd, tickers, top) {
  setNames(rep(1/length(tickers), length(tickers)), tickers)
})

weight_bank[["Top10_InvVol"]] <- compute_topn_lapply("Top10_InvVol", 10, function(sd, tickers, top) {
  n <- length(tickers); ret_sub <- get_ret_sub(sd, 60L)
  vols <- ret_sub[Ticker %in% tickers, .(vol = sd(Ret, na.rm = TRUE)), by = Ticker]
  vol_vec <- setNames(rep(NA_real_, n), tickers); vol_vec[vols$Ticker] <- vols$vol
  med_v <- median(vol_vec, na.rm = TRUE)
  if (is.na(med_v) || med_v < 1e-10) return(setNames(rep(1/n, n), tickers))
  vol_vec[is.na(vol_vec)] <- med_v; vol_vec[vol_vec < 1e-10] <- med_v
  w <- 1 / vol_vec; w <- pmin(w / sum(w), 0.20); setNames(w / sum(w), tickers)
})

weight_bank[["Top10_ScoreTilt"]] <- compute_topn_lapply("Top10_ScoreTilt", 10, function(sd, tickers, top) {
  scores <- setNames(top$Score, tickers); ret_sub <- get_ret_sub(sd, 60L)
  w <- calc_score_tilt_weights(tickers, scores, ret_sub, n_days = 60, max_w = 0.20,
                                alpha = 0.4, cov_method = "gerber_rmt")
  setNames(w, tickers)
})

weight_bank[["Top15_HRP"]] <- compute_topn_lapply("Top15_HRP", 15, function(sd, tickers, top) {
  ret_sub <- get_ret_sub(sd, 60L)
  w <- calc_hrp_weights(tickers, ret_sub, n_days = 60, max_w = MAX_W, cov_method = "gerber_rmt")
  setNames(w, tickers)
})

# M24-M26: Blends (derived from pre-computed weights)
cat("  [weights] Blends... ")
t_w <- Sys.time()

weight_bank[["Blend_HRP_InvVol"]] <- setNames(lapply(seq_along(sig_date_list), function(i) {
  sd_chr <- as.character(sig_date_list[i])
  h <- weight_bank[["HRP_GerberRMT"]][[sd_chr]]; iv <- weight_bank[["InvVol"]][[sd_chr]]
  tickers <- names(h); w <- 0.5 * h[tickers] + 0.5 * iv[tickers]
  w <- pmin(w / sum(w), MAX_W); setNames(w / sum(w), tickers)
}), as.character(sig_date_list))

weight_bank[["Blend_HRP_InvVol_Score"]] <- setNames(lapply(seq_along(sig_date_list), function(i) {
  sd <- sig_date_list[i]; sd_chr <- as.character(sd)
  h <- weight_bank[["HRP_GerberRMT"]][[sd_chr]]; iv <- weight_bank[["InvVol"]][[sd_chr]]
  f <- FACTORS[Date == sd]; tickers <- names(h)
  scores <- setNames(f$Score[match(tickers, f$Ticker)], tickers); scores[is.na(scores)] <- 0
  sc <- scores - min(scores) + 0.01; sc_w <- sc / sum(sc)
  w <- 0.4 * h[tickers] + 0.3 * iv[tickers] + 0.3 * as.numeric(sc_w[tickers])
  w <- pmin(w / sum(w), MAX_W); setNames(w / sum(w), tickers)
}), as.character(sig_date_list))

weight_bank[["Blend_MinVar_Score"]] <- setNames(lapply(seq_along(sig_date_list), function(i) {
  sd <- sig_date_list[i]; sd_chr <- as.character(sd)
  mv <- weight_bank[["MinVar"]][[sd_chr]]
  f <- FACTORS[Date == sd]; tickers <- names(mv)
  scores <- setNames(f$Score[match(tickers, f$Ticker)], tickers); scores[is.na(scores)] <- 0
  sc <- scores - min(scores) + 0.01; sc_w <- sc / sum(sc)
  w <- 0.5 * mv[tickers] + 0.5 * as.numeric(sc_w[tickers])
  w <- pmin(w / sum(w), MAX_W); setNames(w / sum(w), tickers)
}), as.character(sig_date_list))

cat(sprintf("%.1fs\n", as.numeric(difftime(Sys.time(), t_w, units = "secs"))))

# M27-M29: Regime Conditional
cat("  [weights] Regime methods... ")
t_w <- Sys.time()

weight_bank[["Regime_STi_HRP_MV"]] <- setNames(lapply(seq_along(sig_date_list), function(i) {
  sd <- sig_date_list[i]; sd_chr <- as.character(sd); mrs <- get_mrs(sd)
  if (mrs < 20) weight_bank[["ScoreTilt"]][[sd_chr]]
  else if (mrs <= 50) weight_bank[["HRP_GerberRMT"]][[sd_chr]]
  else weight_bank[["MinVar"]][[sd_chr]]
}), as.character(sig_date_list))

weight_bank[["Regime_STi_InvVol"]] <- setNames(lapply(seq_along(sig_date_list), function(i) {
  sd <- sig_date_list[i]; sd_chr <- as.character(sd); mrs <- get_mrs(sd)
  if (mrs < 20) weight_bank[["ScoreTilt"]][[sd_chr]]
  else weight_bank[["InvVol"]][[sd_chr]]
}), as.character(sig_date_list))

weight_bank[["Regime_Hybrid"]] <- setNames(lapply(seq_along(sig_date_list), function(i) {
  sd <- sig_date_list[i]; sd_chr <- as.character(sd); mrs <- get_mrs(sd)
  if (mrs < 20) {
    h <- weight_bank[["HRP_GerberRMT"]][[sd_chr]]
    f <- FACTORS[Date == sd]; tickers <- names(h)
    scores <- setNames(f$Score[match(tickers, f$Ticker)], tickers); scores[is.na(scores)] <- 0
    sc <- scores - min(scores) + 0.01; sc_w <- sc / sum(sc)
    w <- 0.6 * h[tickers] + 0.4 * as.numeric(sc_w[tickers])
    w <- pmin(w / sum(w), MAX_W); setNames(w / sum(w), tickers)
  } else weight_bank[["InvVol"]][[sd_chr]]
}), as.character(sig_date_list))

cat(sprintf("%.1fs\n", as.numeric(difftime(Sys.time(), t_w, units = "secs"))))

# M32-M34: MRS Momentum methods (PIT: mrs/mrs_prev both t-1 lagged from regime_v7)
cat("  [weights] MRS Momentum methods... ")
t_w <- Sys.time()

# M32: MRS Momentum Discrete Switch
# mrs_mom > 5 (deteriorating): MinVar | mrs_mom < -5 (improving): ScoreTilt | else: HRP
weight_bank[["MRS_Mom_Discrete"]] <- setNames(lapply(seq_along(sig_date_list), function(i) {
  sd <- sig_date_list[i]; sd_chr <- as.character(sd)
  mm <- get_mrs_mom(sd)
  if (mm$mom > 5) weight_bank[["MinVar"]][[sd_chr]]
  else if (mm$mom < -5) weight_bank[["ScoreTilt"]][[sd_chr]]
  else weight_bank[["HRP_GerberRMT"]][[sd_chr]]
}), as.character(sig_date_list))

# M33: MRS Momentum Continuous Blend (sigmoid)
# defense_ratio = sigmoid(mrs_mom / 10) -> 0~1
# weight = (1 - defense_ratio) * ScoreTilt + defense_ratio * MinVar
weight_bank[["MRS_Mom_Sigmoid"]] <- setNames(lapply(seq_along(sig_date_list), function(i) {
  sd <- sig_date_list[i]; sd_chr <- as.character(sd)
  mm <- get_mrs_mom(sd)
  dr <- 1 / (1 + exp(-mm$mom / 10))  # sigmoid: 0.5 at mom=0, >0.5 when deteriorating
  st <- weight_bank[["ScoreTilt"]][[sd_chr]]
  mv <- weight_bank[["MinVar"]][[sd_chr]]
  tickers <- names(st)
  w <- (1 - dr) * st[tickers] + dr * mv[tickers]
  w <- pmin(w / sum(w), MAX_W); setNames(w / sum(w), tickers)
}), as.character(sig_date_list))

# M34: MRS Momentum + Level Combined
# level >= 30 AND mom > 0: MinVar (confirmed deterioration)
# level < 20 AND mom < 0: ScoreTilt (confirmed improvement)
# else: InvVol (neutral)
weight_bank[["MRS_Mom_Level"]] <- setNames(lapply(seq_along(sig_date_list), function(i) {
  sd <- sig_date_list[i]; sd_chr <- as.character(sd)
  mm <- get_mrs_mom(sd)
  if (mm$mrs >= 30 && mm$mom > 0) weight_bank[["MinVar"]][[sd_chr]]
  else if (mm$mrs < 20 && mm$mom < 0) weight_bank[["ScoreTilt"]][[sd_chr]]
  else weight_bank[["InvVol"]][[sd_chr]]
}), as.character(sig_date_list))

cat(sprintf("%.1fs\n", as.numeric(difftime(Sys.time(), t_w, units = "secs"))))

# M35-M36: MRS Dual Momentum (absolute + relative)
# PIT: mrs_lag1/lag3 = past MRS values, expanding_median/sd = C1 expanding window
cat("  [weights] MRS Dual Momentum methods... ")
t_w <- Sys.time()

# Pre-compute expanding MRS statistics for dual momentum
# REGIME is sorted by Date (setkey). Build expanding median and sd.
mrs_expanding_stats <- setNames(lapply(seq_along(sig_date_list), function(i) {
  sd <- sig_date_list[i]
  sub <- REGIME[Date <= sd]
  n <- nrow(sub)
  if (n < 4) return(list(lag1 = 0, lag3 = 0, exp_median = 0, exp_sd = 1))
  mrs_all <- sub$MRS; mrs_all[is.na(mrs_all)] <- 0
  list(
    lag1 = mrs_all[n],                           # MRS(t-1)
    lag3 = if (n >= 3) mrs_all[n - 2] else mrs_all[1],  # MRS(t-3)
    exp_median = median(mrs_all, na.rm = TRUE),  # expanding median
    exp_sd = max(sd(mrs_all, na.rm = TRUE), 1)   # expanding sd (floor 1)
  )
}), as.character(sig_date_list))

# M35: MRS Dual Momentum Discrete (2x2 matrix)
# abs_up = lag1 > lag3 (3-month trend up = deteriorating)
# rel_high = lag1 > expanding_median (above long-term level)
weight_bank[["MRS_DualMom_Discrete"]] <- setNames(lapply(seq_along(sig_date_list), function(i) {
  sd_chr <- as.character(sig_date_list[i])
  ms <- mrs_expanding_stats[[sd_chr]]
  abs_up <- ms$lag1 > ms$lag3         # MRS rising = risk increasing
  rel_high <- ms$lag1 > ms$exp_median  # above median = high risk level
  if (abs_up && rel_high)        weight_bank[["MinVar"]][[sd_chr]]       # full defense
  else if (abs_up && !rel_high)  weight_bank[["HRP_GerberRMT"]][[sd_chr]] # caution
  else if (!abs_up && rel_high)  weight_bank[["InvVol"]][[sd_chr]]       # watch
  else                           weight_bank[["ScoreTilt"]][[sd_chr]]    # full attack
}), as.character(sig_date_list))

# M36: MRS Dual Momentum Continuous Blend (sigmoid)
# abs_score = (lag1 - lag3) / exp_sd  (z-scored 3m change)
# rel_score = (lag1 - exp_median) / exp_sd (z-scored level)
# dual_score = 0.5 * abs + 0.5 * rel -> sigmoid -> defense_ratio
weight_bank[["MRS_DualMom_Sigmoid"]] <- setNames(lapply(seq_along(sig_date_list), function(i) {
  sd <- sig_date_list[i]; sd_chr <- as.character(sd)
  ms <- mrs_expanding_stats[[sd_chr]]
  abs_score <- (ms$lag1 - ms$lag3) / ms$exp_sd
  rel_score <- (ms$lag1 - ms$exp_median) / ms$exp_sd
  dual_score <- 0.5 * abs_score + 0.5 * rel_score
  dr <- 1 / (1 + exp(-dual_score))  # sigmoid: >0.5 = more defensive
  st <- weight_bank[["ScoreTilt"]][[sd_chr]]
  mv <- weight_bank[["MinVar"]][[sd_chr]]
  tickers <- names(st)
  w <- (1 - dr) * st[tickers] + dr * mv[tickers]
  w <- pmin(w / sum(w), MAX_W); setNames(w / sum(w), tickers)
}), as.character(sig_date_list))

cat(sprintf("%.1fs\n", as.numeric(difftime(Sys.time(), t_w, units = "secs"))))

# M30-M31: Score tilt variants
weight_bank[["NCO_ScoreTilt"]] <- compute_weights_lapply("NCO_ScoreTilt", function(sd) {
  f <- FACTORS[Date == sd]; tickers <- f$Ticker; scores <- setNames(f$Score, f$Ticker)
  ret_sub <- get_ret_sub(sd, 60L)
  w <- calc_nco_score_tilt_weights(tickers, scores, ret_sub, alpha = 0.4, n_days = 60, max_w = MAX_W)
  setNames(w, tickers)
})

weight_bank[["RegimeSoftmax"]] <- compute_weights_lapply("RegimeSoftmax", function(sd) {
  f <- FACTORS[Date == sd]; tickers <- f$Ticker; scores <- setNames(f$Score, f$Ticker)
  ret_sub <- get_ret_sub(sd, 60L); mrs <- get_mrs(sd)
  w <- calc_regime_softmax_weights(tickers, scores, ret_sub, regime_mrs = mrs,
                                    n_days = 60, max_w = MAX_W, cov_method = "gerber_rmt")
  setNames(w, tickers)
})

cat(sprintf("[Step 4] %d weight methods pre-computed.\n", length(weight_bank)))

# ===================================================================
# 5. Run backtests via mclapply + run_monthly_simulation() (OPT-3/4)
#    Fork COW: RAWDATA/BM_DT shared read-only across children
# ===================================================================
cat("\n[Step 5] Running backtests via mclapply...\n")

method_names <- names(weight_bank)
orig_ivol_fn <- calc_ivol_weights

# Build method metadata: FACTORS_mod and n_hold per method
method_meta <- lapply(method_names, function(mname) {
  is_topn <- grepl("^Top", mname)
  if (is_topn) {
    n_top <- as.integer(sub("Top(\\d+)_.*", "\\1", mname))
    fmod <- rbindlist(lapply(sig_date_list, function(sd) {
      f <- FACTORS[Date == sd]; setorder(f, -Score); head(f, n_top)
    }))
    list(factors = fmod, n_hold = n_top)
  } else {
    list(factors = FACTORS, n_hold = N_HOLD)
  }
})
names(method_meta) <- method_names

# mclapply: each child overrides calc_ivol_weights and runs simulation
sim_results <- mclapply(method_names, function(mname) {
  wl <- weight_bank[[mname]]
  meta <- method_meta[[mname]]

  # Override calc_ivol_weights in this fork
  calc_ivol_weights <<- function(tickers, ret_dt, n_days = 60, max_w = 0.15) {
    lapply(names(wl), function(d) {
      hw <- wl[[d]]
      if (all(tickers %in% names(hw))) return(as.numeric(hw[tickers] / sum(hw[tickers])))
      NULL
    }) -> matches
    matches <- matches[!sapply(matches, is.null)]
    if (length(matches) > 0) return(matches[[1]])
    rep(1 / length(tickers), length(tickers))
  }

  sim <- tryCatch(
    run_monthly_simulation(RAWDATA, BM_DT, meta$factors,
                           n_holdings = meta$n_hold,
                           weight_method = "ivol",
                           commission = 0.0015,
                           buffer_zone = list(keep_n = meta$n_hold + 15L,
                                              entry_n = meta$n_hold)),
    error = function(e) NULL
  )

  if (is.null(sim)) return(NULL)
  perf <- summarise_perf(sim$strategy_xts, mname)
  to <- calc_turnover(sim$PORTFOLIO_LOG, sim$DAILY_NAV_DT)
  list(perf = perf, to = to, nav_dt = sim$DAILY_NAV_DT)
}, mc.cores = N_CORES)

names(sim_results) <- method_names
calc_ivol_weights <<- orig_ivol_fn

# ===================================================================
# 6. Summarize + Compare
# ===================================================================
cat("\n[Step 6] Summarizing results...\n")

perf_list <- lapply(method_names, function(mn) {
  r <- sim_results[[mn]]
  if (is.null(r)) return(NULL)
  p <- r$perf; p[, TO := r$to]; p
})
names(perf_list) <- method_names
perf_list <- perf_list[!sapply(perf_list, is.null)]
comparison <- rbindlist(perf_list, fill = TRUE)

if (nrow(comparison) == 0) {
  cat("[ERROR] No methods produced valid results!\n")
} else {
  setorder(comparison, -Sharpe)

  cat("\n================================================================\n")
  cat("   STR_1631 Weight Extreme: C19 Top-20 Exhaustive Comparison\n")
  cat(sprintf("   %d methods | %s ~ %s\n", nrow(comparison),
              min(sig_date_list), max(sig_date_list)))
  cat("================================================================\n\n")

  cat("=== ALL METHODS (sorted by Sharpe) ===\n")
  print(comparison[, .(Label, CAGR, AnnVol, Sharpe, Sortino, MDD, Calmar, TO)])

  cat("\n=== TOP 5 by SR ===\n")
  print(head(comparison[, .(Label, CAGR, AnnVol, Sharpe, Sortino, MDD, Calmar)], 5))

  mdd_order <- copy(comparison); setorder(mdd_order, MDD)
  cat("\n=== TOP 5 by MDD (lowest drawdown) ===\n")
  print(head(mdd_order[, .(Label, CAGR, AnnVol, Sharpe, Sortino, MDD, Calmar)], 5))

  calmar_order <- copy(comparison); setorder(calmar_order, -Calmar)
  cat("\n=== TOP 5 by Calmar ===\n")
  print(head(calmar_order[, .(Label, CAGR, AnnVol, Sharpe, Sortino, MDD, Calmar)], 5))

  # ===================================================================
  # 7. Save CSV
  # ===================================================================
  fwrite(comparison, file.path(OUT_DIR, "weight_extreme_comparison.csv"))

  # ===================================================================
  # 8. Equity Curve Chart
  # ===================================================================
  cat("\n[Step 8] Generating charts...\n")

  top5_names <- head(comparison$Label, 5)
  if (!"EW" %in% top5_names && "EW" %in% names(sim_results)) top5_names <- c(top5_names, "EW")

  plot_data <- rbindlist(lapply(top5_names, function(mn) {
    r <- sim_results[[mn]]
    if (is.null(r)) return(NULL)
    nd <- r$nav_dt
    data.table(Date = nd$Date, NAV = nd$NAV / nd$NAV[1], Method = mn)
  }))

  if (nrow(plot_data) > 0) {
    p <- ggplot(plot_data, aes(x = Date, y = NAV, color = Method)) +
      geom_line(linewidth = 0.6) +
      scale_y_log10(labels = scales::comma) +
      labs(title = "STR_1631 Weight Extreme: Top 5 Methods + EW",
           x = NULL, y = "NAV (log scale)", color = "Method") +
      theme_minimal(base_size = 11) +
      theme(legend.position = "bottom")
    ggsave(file.path(OUT_DIR, "equity_curve_extreme.png"), p, width = 12, height = 7, dpi = 150)
  }

  mdd_plot <- comparison[!is.na(MDD), .(Label, MDD_abs = abs(MDD), Sharpe)]
  setorder(mdd_plot, -Sharpe)
  mdd_plot[, Label := factor(Label, levels = Label)]
  p2 <- ggplot(mdd_plot, aes(x = Label, y = MDD_abs)) +
    geom_col(aes(fill = Sharpe), width = 0.7) +
    scale_fill_gradient(low = "tomato", high = "steelblue") +
    coord_flip() +
    labs(title = "MDD by Method (color = Sharpe)", x = NULL, y = "MDD (%)") +
    theme_minimal(base_size = 10)
  ggsave(file.path(OUT_DIR, "mdd_comparison.png"), p2, width = 10, height = 8, dpi = 150)

  # ===================================================================
  # 9. JSON summary
  # ===================================================================
  write_json(list(
    strategy = "STR_1631_weight_extreme",
    description = "Exhaustive weight method comparison on C19 top-20 universe",
    n_methods = nrow(comparison),
    top5_sr = as.list(head(comparison[, .(Label, Sharpe, CAGR, MDD)], 5)),
    top5_mdd = as.list(head(mdd_order[, .(Label, Sharpe, CAGR, MDD)], 5)),
    run_time_sec = as.numeric(difftime(Sys.time(), t0, units = "secs"))
  ), file.path(OUT_DIR, "performance.json"), pretty = TRUE, auto_unbox = TRUE)
}

elapsed <- difftime(Sys.time(), t0, units = "secs")
cat(sprintf("\n[DONE] Weight Extreme complete in %.1f seconds (%d methods).\n",
            elapsed, nrow(comparison)))
cat("=== END ===\n")
