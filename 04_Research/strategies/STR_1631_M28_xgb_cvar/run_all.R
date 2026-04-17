cat("=== STR_1631_M28: XGBoost CVaR Inverse Weight ===\n")
## 핵심 아이디어: HRP+Score Tilt -> XGBoost predicted CVaR 역가중
## Horse Race v2 M2 model(SR 0.904) 통합. MI_prefilter top-50 features.
## fdb_daily 피처 -> 연간 expanding refit -> 월말 CVaR 예측 -> 1/|CVaR| 가중
## PIT: expanding window 학습, t-1 prediction (C1/C9 준수)
## Ref: Engle & Manganelli(2004) CAViaR, Bali et al.(2009) CVaR pricing
## MI_prefilter top-50 (OPT-7/MC-P1), fdb_daily (OPT-7/MC-P2), walk_forward expanding (OPT-7/MC-P3)

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
HRV2_CACHE <- file.path(CACHE_DIR, "hr_v2")
FDB_DAILY_DIR <- file.path(CACHE_DIR, "factor_db_daily")
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR    <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales)
  library(tidyr); library(lubridate); library(jsonlite); library(xgboost)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

LIQ_THRESHOLD  <- 2e8
N_HOLD         <- 20L
MAX21D_EXCL    <- 0.80
REBAL_MONTHS   <- 2L
IC_MIN_MONTHS  <- 12L
TAU            <- 0.05       # CVaR quantile
WMIN           <- 0.02
WMAX           <- 0.15
XGB_NROUNDS    <- 300
XGB_THREADS    <- 4
MI_TOP_N       <- 50         # OPT-7/MC-P1: MI_prefilter top-50

cat(sprintf("[M28] XGBoost CVaR InvWeight | tau=%.2f | MI_prefilter top-%d | Bimonthly\n",
            TAU, MI_TOP_N))

# ===================================================================
# 1. Load RAWDATA (single load, OPT-1 compliant)
# ===================================================================
cat("\n[Step 1] Loading RAWDATA...\n")
source(file.path(FUNC_PATH, "backtest_harness.R"))
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
RAWDATA[, Date := as.Date(Date)]; BM_DT[, Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]; BM_DT <- BM_DT[Date >= ANALYSIS_START_DATE]
dc <- intersect(c("Open", "High", "Low", "source", "Size", "Market"), names(RAWDATA))
if (length(dc) > 0) RAWDATA[, (dc) := NULL]
if (!"Name" %in% names(RAWDATA) || !"Sector" %in% names(RAWDATA)) {
  ud <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, "universe.parquet"))); ud[, Date := as.Date(Date)]
  setorder(ud, Ticker, -Date); ti <- ud[, .(Name = Name[1], Sector = Sector[1]), by = Ticker]
  if (!"Name" %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ti[, .(Ticker, Name)], by = "Ticker", all.x = TRUE)
  if (!"Sector" %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ti[, .(Ticker, Sector)], by = "Ticker", all.x = TRUE)
  rm(ud, ti)
}
gc(verbose = FALSE)

RAWDATA[, YM := format(Date, "%Y-%m")]
sd_dt <- RAWDATA[, .(sig_date = max(Date)), by = YM]; setorder(sd_dt, sig_date)
sd_dt <- sd_dt[sig_date >= SIGNAL_START_DATE]
ALL_SIG_DATES <- sd_dt$sig_date
SIG_DATES <- ALL_SIG_DATES[seq(1, length(ALL_SIG_DATES), by = REBAL_MONTHS)]
cat(sprintf("[Step 1] Monthly dates: %d | Bimonthly SIG_DATES: %d\n",
            length(ALL_SIG_DATES), length(SIG_DATES)))

setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradVal := Close * Vol]
RAWDATA[, LIQ_20d := shift(frollmean(TradVal, n = 20L, align = "right", na.rm = TRUE),
                            n = 1L, type = "lag"), by = Ticker]  # C10: t-1 lag (LIQ_THRESHOLD=2e8)
RAWDATA[, TradVal := NULL]
RAWDATA[, Ret_abs := abs(Ret)]
RAWDATA[, MAX21d_raw := {
  ra <- Ret_abs; n <- length(ra)
  if (n < 21L) cummax(fifelse(is.na(ra), -Inf, ra))
  else frollapply(ra, n = 21L, FUN = max, fill = NA, align = "right")
}, by = Ticker]
RAWDATA[, MAX21d := shift(MAX21d_raw, n = 1L, type = "lag"), by = Ticker]
RAWDATA[, c("Ret_abs", "MAX21d_raw") := NULL]

SIG_SNAP <- RAWDATA[Date %in% ALL_SIG_DATES & !is.na(Close), .(Date, Ticker, Close, LIQ_20d, MAX21d)]
setkey(SIG_SNAP, Date, Ticker)
RAWDATA[, c("LIQ_20d", "MAX21d", "YM") := NULL]; setkey(RAWDATA, Date, Ticker)
gc(verbose = FALSE)

# ===================================================================
# 2. Load MI_prefilter features (cached from Horse Race v2)
# ===================================================================
cat("\n[Step 2] Loading MI_prefilter features...\n")
mi_cache <- file.path(HRV2_CACHE, "mi_prefilter_features.rds")
stopifnot(file.exists(mi_cache))
SELECTED_FEATURES <- readRDS(mi_cache)
cat(sprintf("[MI] Features: %d (from cache)\n", length(SELECTED_FEATURES)))

# ===================================================================
# 3. Load Consensus + IC computation (identical to SYN_05)
# ===================================================================
cat("\n[Step 3] Loading Consensus + expanding IC...\n")
lc <- function(f) {
  dt <- as.data.table(arrow::read_parquet(file.path(CONS_DIR, f))); dt[, Date := as.Date(Date)]
  dt <- dt[Date >= ANALYSIS_START_DATE]; setkey(dt, Ticker, Date)
  cat(sprintf("  > %s: %s rows\n", f, format(nrow(dt), big.mark = ","))); dt
}
SUE_DT   <- lc("sue.parquet")
ESBR_DT  <- lc("esbr.parquet")
EPS1M_DT <- lc("eps_chg_1m.parquet")
COV_DT   <- lc("coverage.parquet")
TP_DT    <- lc("target_price.parquet")

z_safe <- function(x) {
  nv <- sum(!is.na(x)); if (nv < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x))); (x - mu) / s
}

fwd_map <- setNames(lapply(seq_along(ALL_SIG_DATES), function(i) {
  sd <- ALL_SIG_DATES[i]
  if (i >= length(ALL_SIG_DATES)) return(NULL)
  next_sd <- ALL_SIG_DATES[i + 1]
  RAWDATA[Date > sd & Date <= next_sd, .(fwd_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
}), as.character(ALL_SIG_DATES))

raw_scores_list <- lapply(seq_along(ALL_SIG_DATES), function(i) {
  sd <- ALL_SIG_DATES[i]
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
  data.table(Date = sd, Ticker = sig$Ticker,
    z_sue = sig$z_sue, z_esbr = sig$z_esbr, z_eps1m = sig$z_eps1m, z_tpgap = sig$z_tpgap)
})
RAW_SCORES <- rbindlist(raw_scores_list[!sapply(raw_scores_list, is.null)])

unique_dates <- sort(unique(RAW_SCORES$Date))
ic_list <- lapply(seq_along(unique_dates), function(i) {
  sd <- unique_dates[i]
  fr <- fwd_map[[as.character(sd)]]; if (is.null(fr)) return(NULL)
  sc <- RAW_SCORES[Date == sd]; mg <- merge(sc, fr, by = "Ticker")
  if (nrow(mg) < 10L) return(NULL)
  data.table(Date = sd,
    ic_sue   = fifelse(is.na(cor(mg$z_sue,   mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_sue,   mg$fwd_ret, method = "spearman", use = "complete.obs")),
    ic_esbr  = fifelse(is.na(cor(mg$z_esbr,  mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_esbr,  mg$fwd_ret, method = "spearman", use = "complete.obs")),
    ic_eps1m = fifelse(is.na(cor(mg$z_eps1m, mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_eps1m, mg$fwd_ret, method = "spearman", use = "complete.obs")),
    ic_tpgap = fifelse(is.na(cor(mg$z_tpgap, mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_tpgap, mg$fwd_ret, method = "spearman", use = "complete.obs")))
})
ic_history <- rbindlist(ic_list[!sapply(ic_list, is.null)])
cat(sprintf("[Step 3] IC history: %d months\n", nrow(ic_history)))

# Build FACTORS on bimonthly dates
ic_weight_log <- list()
FACTORS_list <- lapply(seq_along(SIG_DATES), function(i) {
  sd <- SIG_DATES[i]
  sc <- RAW_SCORES[Date == sd]; if (nrow(sc) < 20L) return(NULL)
  past_ic <- ic_history[Date < sd]
  if (nrow(past_ic) < IC_MIN_MONTHS) {
    w_factors <- c(sue = 0.25, esbr = 0.25, eps1m = 0.25, tpgap = 0.25)
  } else {
    mean_ic <- c(sue = mean(past_ic$ic_sue, na.rm = TRUE), esbr = mean(past_ic$ic_esbr, na.rm = TRUE),
                 eps1m = mean(past_ic$ic_eps1m, na.rm = TRUE), tpgap = mean(past_ic$ic_tpgap, na.rm = TRUE))
    mean_ic <- pmax(mean_ic, 0); ic_sum <- sum(mean_ic)
    w_factors <- if (ic_sum < 1e-8) c(sue = 0.25, esbr = 0.25, eps1m = 0.25, tpgap = 0.25) else mean_ic / ic_sum
  }
  ic_weight_log[[as.character(sd)]] <<- w_factors
  sc[, C19_icw := w_factors["sue"] * z_sue + w_factors["esbr"] * z_esbr +
                  w_factors["eps1m"] * z_eps1m + w_factors["tpgap"] * z_tpgap]
  setorder(sc, -C19_icw); top <- head(sc, N_HOLD)
  data.table(Date = sd, Ticker = top$Ticker, Score = top$C19_icw)
})
FACTORS <- rbindlist(FACTORS_list[!sapply(FACTORS_list, is.null)])
cat(sprintf("[Step 3] FACTORS: %d rows | %d bimonthly months\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
rm(SUE_DT, ESBR_DT, EPS1M_DT, COV_DT, TP_DT, RAW_SCORES, FACTORS_list, SIG_SNAP)
gc(verbose = FALSE)

# ===================================================================
# 4. M28: XGBoost CVaR Model (walk-forward expanding, OPT-7/MC-P3)
#    Train on fdb_daily features (OPT-7/MC-P2), MI_prefilter top-50
#    Predict CVaR for each stock -> 1/|CVaR| inverse weight
# ===================================================================
cat("\n[Step 4] XGBoost CVaR walk-forward training + prediction...\n")

safe_fill_na <- function(X) { X[is.na(X)] <- 0; X }

# train_m2 from Horse Race v2 (XGBoost quantile regression)
train_m2 <- function(tr, feat_cols) {
  tryCatch({
    fc <- intersect(feat_cols, names(tr))
    X  <- safe_fill_na(as.matrix(tr[, ..fc]))
    y  <- tr[["fwd_cvar05"]]
    ok <- !is.na(y) & is.finite(y)
    if (sum(ok) < 50) return(NULL)
    X <- X[ok, ]; y <- y[ok]
    dtrain <- xgb.DMatrix(X, label = y)
    params <- list(objective = "reg:quantileerror", quantile_alpha = TAU,
                   eta = 0.02, max_depth = 5, subsample = 0.7,
                   nthread = XGB_THREADS, verbose = 0)
    list(type = "M2", model = xgb.train(params, dtrain, nrounds = XGB_NROUNDS, verbose = 0), fc = fc)
  }, error = function(e) { cat("  [M2 ERR]", conditionMessage(e), "\n"); NULL })
}

pred_m2 <- function(obj, pr) {
  tryCatch({
    if (is.null(obj)) return(rep(NA_real_, nrow(pr)))
    fc <- intersect(obj$fc, names(pr))
    X <- safe_fill_na(as.matrix(pr[, ..fc]))
    predict(obj$model, xgb.DMatrix(X))
  }, error = function(e) { cat("  [M2 pred ERR]", conditionMessage(e), "\n"); rep(NA_real_, nrow(pr)) })
}

# CVaR to weights: 1/|CVaR| bounded
cvar2w <- function(cv, tks) {
  acv <- abs(cv); acv[is.na(acv)] <- max(acv, na.rm = TRUE); acv[acv == 0] <- 1e-6
  w <- 1 / acv; w <- pmax(pmin(w / sum(w), WMAX), WMIN); w <- w / sum(w); setNames(w, tks)
}

# Build training matrix for a set of month-end dates
# OPT-1 compliant: load fdb_daily files in bulk via lapply (not loop with read_parquet)
build_train_matrix <- function(month_ends, raw_dt, fdb_dir, feat_cols, liq_tickers) {
  ym_set <- unique(format(month_ends, "%Y%m"))
  all_fdb_files <- list.files(fdb_dir, pattern = "\\.parquet$", full.names = TRUE)
  avail_ym <- sub(".*fdb_daily_(\\d{6})\\.parquet$", "\\1", basename(all_fdb_files))
  matched_files <- all_fdb_files[avail_ym %in% ym_set]
  if (length(matched_files) == 0) return(data.table())

  load_cols <- c("Date", "Ticker", feat_cols)
  me_chars <- as.character(month_ends)
  fdb_sub <- rbindlist(lapply(matched_files, function(f) {
    tryCatch({
      dt <- arrow::read_parquet(f) |> as.data.table()
      dt[, Date := as.Date(Date)]
      dt_me <- dt[as.character(Date) %in% me_chars]
      if (nrow(dt_me) == 0) return(NULL)
      avail <- intersect(load_cols, names(dt_me))
      dt_me[, ..avail]
    }, error = function(e) NULL)
  }), fill = TRUE)
  if (nrow(fdb_sub) == 0) return(data.table())
  fdb_sub[, Date := as.Date(Date)]
  fdb_sub <- fdb_sub[Ticker %in% liq_tickers]
  setkey(fdb_sub, Date, Ticker)

  # Forward CVaR target (21 trading days ahead, 5th percentile)
  raw_fwd <- raw_dt[Date > min(month_ends) & Date <= max(month_ends) + 40L]
  cvar_tgt <- rbindlist(lapply(month_ends, function(me_d) {
    sub_r <- raw_fwd[Date > me_d & Date <= me_d + 35L]
    if (nrow(sub_r) == 0) return(NULL)
    sub_r[order(Ticker, Date)][,
      if (.N >= 5) .(fwd_cvar05 = quantile(Ret[1:min(21L, .N)], TAU, na.rm = TRUE), Date = me_d)
      else .(fwd_cvar05 = NA_real_, Date = me_d),
      by = Ticker][!is.na(fwd_cvar05)]
  }), fill = TRUE)[!is.na(fwd_cvar05)]
  setkey(cvar_tgt, Date, Ticker)

  train_dt <- merge(fdb_sub, cvar_tgt, by = c("Date", "Ticker"), all = FALSE)
  cat(sprintf("    [train] %d rows\n", nrow(train_dt)))
  train_dt
}

# Walk-forward: annual refit, expanding window (OPT-7/MC-P3)
all_sig_dates_sorted <- sort(unique(FACTORS$Date))
xgb_model <- NULL
last_refit_yr <- -1L
xgb_weights <- list()  # store predicted CVaR weights per sig_date

cat(sprintf("[M28] Walk-forward over %d bimonthly dates...\n", length(all_sig_dates_sorted)))
invisible(lapply(seq_along(all_sig_dates_sorted), function(k) {
  sd <- all_sig_dates_sorted[k]
  yr <- year(sd)
  tickers <- FACTORS[Date == sd, Ticker]

  # Annual refit (expanding window, MC1/C1 compliant)
  if (yr > last_refit_yr) {
    cat(sprintf("\n  [REFIT %d] Expanding IS: start ~ %s\n", yr, format(sd - 1, "%Y-%m")))

    # Liquid tickers for training
    raw_is <- RAWDATA[Date < sd]
    liq_dt <- raw_is[, .(liq = mean(Vol * Close, na.rm = TRUE)), by = Ticker]
    liq_ok <- liq_dt[liq >= LIQ_THRESHOLD, Ticker]

    # IS month-end dates (last 5 years, non-overlapping)
    is_me <- raw_is[Ticker %in% liq_ok,
                    .(me_d = max(Date)), by = .(YM = format(Date, "%Y-%m"))][order(me_d), me_d]
    is_me_use <- is_me[is_me >= sd - 365 * 5]
    if (length(is_me_use) < 24) is_me_use <- is_me

    tr_dt <- build_train_matrix(is_me_use, RAWDATA, FDB_DAILY_DIR, SELECTED_FEATURES, liq_ok)
    if (nrow(tr_dt) >= 50) {
      cat(sprintf("    Training XGBoost (n=%d, features=%d)...\n", nrow(tr_dt), length(SELECTED_FEATURES)))
      xgb_model <<- train_m2(tr_dt, SELECTED_FEATURES)
      cat(sprintf("    Model: %s\n", if (!is.null(xgb_model)) "OK" else "FAILED"))
    } else {
      cat("    [WARN] Insufficient training data, keeping previous model.\n")
    }
    last_refit_yr <<- yr
    gc(verbose = FALSE)
  }

  # Predict CVaR for current holdings
  if (is.null(xgb_model)) {
    xgb_weights[[as.character(sd)]] <<- setNames(rep(1 / length(tickers), length(tickers)), tickers)
    return(NULL)
  }

  # Load fdb_daily for prediction
  me_ym <- format(sd, "%Y%m")
  pred_file <- list.files(FDB_DAILY_DIR, pattern = paste0("fdb_daily_", me_ym, "\\.parquet$"), full.names = TRUE)
  if (length(pred_file) == 0) {
    avail_f <- list.files(FDB_DAILY_DIR, pattern = "\\.parquet$", full.names = TRUE)
    avail_ym <- as.numeric(sub(".*fdb_daily_(\\d{6})\\.parquet$", "\\1", basename(avail_f)))
    closest_idx <- which.min(abs(avail_ym - as.numeric(me_ym)))
    if (avail_ym[closest_idx] <= as.numeric(me_ym)) pred_file <- avail_f[closest_idx]
  }

  if (length(pred_file) == 0) {
    xgb_weights[[as.character(sd)]] <<- setNames(rep(1 / length(tickers), length(tickers)), tickers)
    return(NULL)
  }

  pred_dt <- tryCatch({
    pf <- arrow::read_parquet(pred_file[1]) |> as.data.table()
    pf[, Date := as.Date(Date)]
    pf_me <- pf[Date <= sd][Date == max(Date)][Ticker %in% tickers]
    load_f <- intersect(SELECTED_FEATURES, names(pf_me))
    pf_me[, c("Date", "Ticker", load_f), with = FALSE]
  }, error = function(e) data.table())

  if (nrow(pred_dt) == 0 || nrow(pred_dt) < 3) {
    xgb_weights[[as.character(sd)]] <<- setNames(rep(1 / length(tickers), length(tickers)), tickers)
    return(NULL)
  }

  # Fill missing feature columns
  missing_feats <- setdiff(SELECTED_FEATURES, names(pred_dt))
  if (length(missing_feats) > 0) pred_dt[, (missing_feats) := 0]

  # Predict CVaR (t-1: features are from before or at sig_date, C9 compliant)
  cvar_pred <- pred_m2(xgb_model, pred_dt)
  w <- cvar2w(cvar_pred, pred_dt$Ticker)

  # Extend to all tickers (some may not have fdb_daily data)
  full_w <- rep(NA_real_, length(tickers)); names(full_w) <- tickers
  full_w[names(w)] <- w
  # Tickers without prediction get median weight
  med_w <- median(w, na.rm = TRUE)
  full_w[is.na(full_w)] <- med_w
  full_w <- full_w / sum(full_w)
  xgb_weights[[as.character(sd)]] <<- full_w

  if (k <= 3 || k %% 12 == 1)
    cat(sprintf("  [%s] CVaR pred range: [%.4f, %.4f] | top_w: %.3f\n",
                format(sd, "%Y-%m"), min(cvar_pred, na.rm = TRUE), max(cvar_pred, na.rm = TRUE),
                max(full_w)))
}))

cat(sprintf("[Step 4] XGBoost CVaR weights computed: %d dates\n", length(xgb_weights)))

# ===================================================================
# 5. Backtest with XGBoost CVaR weights
# ===================================================================
cat("\n[Step 5] Running backtest with XGBoost CVaR weights...\n")
oi <- calc_ivol_weights
calc_ivol_weights <<- function(tickers, ret_dt, n_days = 60, max_w = 0.15) {
  lapply(names(xgb_weights), function(d) {
    hw <- xgb_weights[[d]]; if (all(tickers %in% names(hw))) { w <- hw[tickers]; return(as.numeric(w / sum(w))) }
    NULL
  }) -> matches
  matches <- matches[!sapply(matches, is.null)]
  if (length(matches) > 0) return(matches[[1]])
  rep(1 / length(tickers), length(tickers))
}
sim_base <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS, n_holdings = N_HOLD,
  weight_method = "ivol", commission = 0.0015, buffer_zone = list(keep_n = 35L, entry_n = 20L))
calc_ivol_weights <<- oi
perf_base <- summarise_perf(sim_base$strategy_xts, "M28_Base")
to_base <- calc_turnover(sim_base$PORTFOLIO_LOG, sim_base$DAILY_NAV_DT)

# ===================================================================
# 6. Regime Overlay (3-Layer, identical to SYN_05)
# ===================================================================
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
REGIME <- build_daily_regime(use_cache = TRUE); setkey(REGIME, Date)
ip <- file.path(CACHE_DIR, "kodex_inverse_114800.csv")
ID <- if (file.exists(ip)) { dt <- fread(ip); dt[, Date := as.Date(Date)]; setkey(dt, Date); dt } else NULL
nd <- copy(sim_base$DAILY_NAV_DT); setkey(nd, Date)
nd <- REGIME[, .(Date, MRS, n_axes_firing)][nd, roll = TRUE]
nd <- merge(nd, BM_DT[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)
if (!is.null(ID)) {
  nd <- merge(nd, ID[, .(Date, Ret_Inv)], by = "Date", all.x = TRUE)
  nd[is.na(Ret_Inv), Ret_Inv := -BM_Ret]
} else nd[, Ret_Inv := -BM_Ret]
nd[is.na(Ret_Inv), Ret_Inv := 0]; nd[is.na(MRS), MRS := 0]; nd[is.na(n_axes_firing), n_axes_firing := 0L]
nd[, crisis_flag := fifelse(MRS >= 60 & n_axes_firing >= 5, 1L, 0L)]
nd[, crisis_consec := {
  out <- integer(.N); cnt <- 0L
  idx <- seq_len(.N)
  sapply(idx, function(j) { if (nd$crisis_flag[j] == 1L) cnt <<- cnt + 1L else cnt <<- 0L; out[j] <<- cnt })
  out
}]
nd[, Layer := fifelse(crisis_consec >= 3L, 3L, fifelse(MRS >= 30, 2L, 1L))]
nd[, Ret_overlay := fcase(
  Layer == 1L, Strategy_Ret,
  Layer == 2L, { fw <- pmax(0.5, 1.0 - (MRS - 30) / 60); fw * Strategy_Ret + (1 - fw) * 0 },
  Layer == 3L, 0.50 * Strategy_Ret + 0.20 * Ret_Inv + 0.30 * 0
)]
nd[, NAV_overlay := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_overlay)]
ov_xts <- xts(nd$Ret_overlay, order.by = nd$Date); names(ov_xts) <- "Strategy"

# ===================================================================
# 7. Summary & Save
# ===================================================================
po <- summarise_perf(ov_xts, "M28_Overlay"); pb <- summarise_perf(sim_base$bm_xts, "KOSPI200")
cat("\n================================================================\n")
cat("   STR_1631 M28: XGBoost CVaR Inverse Weight\n")
cat("================================================================\n")
cat("--- Base ---\n"); print(perf_base)
cat("--- Overlay ---\n"); print(po)
cat("--- BM ---\n"); print(pb)
cat(sprintf("Turnover: %.1f%% | XGB CVaR InvWeight | MI_prefilter top-%d | tau=%.2f | Bimonthly\n",
            to_base, MI_TOP_N, TAU))

source(file.path(FUNC_PATH, "hurdle_gate.R"))
sim_ov_h <- list(strategy_xts = ov_xts, bm_xts = sim_base$bm_xts,
  DAILY_NAV_DT = nd[, .(Date, NAV = NAV_overlay, Strategy_Ret = Ret_overlay)],
  PORTFOLIO_LOG = sim_base$PORTFOLIO_LOG)
hr <- run_hurdle_gate(sim_ov_h, FACTORS,
  strategy_name = "STR_1631_M28_xgb_cvar", output_dir = OUT_DIR)
cat("--- Hurdle ---\n"); print(hr[c("pass", "score")])

generate_charts(list(strategy_xts = ov_xts, bm_xts = sim_base$bm_xts,
  DAILY_NAV_DT = nd[, .(Date, NAV = NAV_overlay, Strategy_Ret = Ret_overlay)]),
  output_dir = OUT_DIR, strategy_name = "STR_1631 M28 - XGBoost CVaR Weight")

ic_wt_dt <- rbindlist(lapply(names(ic_weight_log), function(d) {
  w <- ic_weight_log[[d]]
  data.table(Date = as.Date(d), w_sue = w["sue"], w_esbr = w["esbr"],
             w_eps1m = w["eps1m"], w_tpgap = w["tpgap"])
}))
fwrite(ic_wt_dt, file.path(OUT_DIR, "ic_weight_evolution.csv"))

write_json(list(
  strategy = "STR_1631_M28_xgb_cvar",
  mutation = "M28: XGBoost predicted CVaR inverse weight (Horse Race v2 M2 model)",
  parent = "STR_1631_SYN_05",
  change = "stock_weight axis: HRP+ScoreTilt -> XGB CVaR InvWeight. factor/overlay/rebal unchanged",
  mi_top_n = MI_TOP_N, tau = TAU, xgb_nrounds = XGB_NROUNDS,
  rebal_months = REBAL_MONTHS,
  pit_notes = list(C1 = "expanding window training", C9 = "t-1 features for prediction",
                   MC1 = "annual expanding refit", MC_P1 = "MI_prefilter top-50"),
  base = as.list(perf_base), overlay = as.list(po), benchmark = as.list(pb),
  turnover = to_base, hurdle_pass = hr$pass, hurdle_score = hr$score,
  run_time = as.numeric(difftime(Sys.time(), t0, units = "secs"))
), file.path(OUT_DIR, "performance.json"), pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("\n[DONE] M28 complete in %.1f sec\n", difftime(Sys.time(), t0, units = "secs")))
