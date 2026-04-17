## STR_1071: NoShortDD + MRS 12/25 (두 최적 변형 합성)
## Parent: STR_1060. Change: MRS threshold 15/30→12/25 (위기 조기감지)
set.seed(1071); options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
STRATEGY_NAME <- "NoShortDD_MRS1225"; STRATEGY_ID <- "STR_1071"
QEPM_AUTO_COMMIT <- TRUE

cat("=== STR_1071: No Short DD + MRS 12/25 ===\n")

SCRIPT_DIR <- tryCatch({
  d <- dirname(sys.frame(1)$ofile)
  if (d == ".") getwd() else d
}, error = function(e) {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    p <- sub("--file=", "", file_arg[1])
    p <- gsub("~+~", " ", p, fixed = TRUE)
    dirname(p)
  } else getwd()
})

INFRA_DIR <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))

tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check("STR_1071", family = "5sleeve_combo")
}, error = function(e) cat("[Preflight] ", e$message, "\n"))

cat(sprintf("\n=== %s: %s ===\n\n", STRATEGY_ID, STRATEGY_NAME))
LIQ_THRESHOLD <- 2e8

# ============================================================================
# Phase 1: Run 5 independent sleeves (identical to STR_1028/1034)
# ============================================================================
BASE_DIR <- file.path(dirname(SCRIPT_DIR), "STR_770_phase2_cross")

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA); BM_DT_ORIG <- copy(BM_DT)

# -- Phase 1a: Defense sleeve (N=6) --
cat("[Phase 1a] Defense sleeve (N=6)...\n")
source(file.path(BASE_DIR, "defense_sleeve.R"))
FACTORS_DEF <- copy(FACTORS)
setkey(RAWDATA, Ticker, Date); gc(verbose = FALSE)

sim_def <- run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS_DEF,
  n_holdings = 6, weight_method = "equal",
  commission = 0.0015,
  buffer_zone = list(keep_n = 12L, entry_n = 6L),
  vol_target = 0.25, vol_lookback = 60L
)

# -- Phase 1b: IndMom sleeve (N=6) --
cat("[Phase 1b] IndMom sleeve (N=6)...\n")
RAWDATA <- copy(RAWDATA_ORIG); BM_DT <- copy(BM_DT_ORIG)
source(file.path(BASE_DIR, "indmom_sleeve.R"))
FACTORS_IND <- copy(FACTORS)
setkey(RAWDATA, Ticker, Date); gc(verbose = FALSE)

sim_ind <- run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS_IND,
  n_holdings = 6, weight_method = "equal",
  commission = 0.0015,
  buffer_zone = list(keep_n = 12L, entry_n = 6L),
  vol_target = 0.15, vol_lookback = 60L
)

# -- Phase 1c: Consensus sleeve (SUE Pure 100%, N=6) --
cat("[Phase 1c] Consensus sleeve (N=6)...\n")
RAWDATA <- copy(RAWDATA_ORIG); BM_DT <- copy(BM_DT_ORIG)
W_CONF <- 0.0; W_SUE_824 <- 1.0; W_IDIOVOL_824 <- 0.0
source(file.path(dirname(SCRIPT_DIR), "STR_824_rev_breadth_ivol", "factor_engine.R"))
FACTORS_CONS <- copy(FACTORS)
setkey(RAWDATA, Ticker, Date); gc(verbose = FALSE)

sim_cons <- run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS_CONS,
  n_holdings = 6, weight_method = "equal",
  commission = 0.0015,
  buffer_zone = list(keep_n = 12L, entry_n = 6L),
  vol_target = 0.18, vol_lookback = 60L
)

# -- Phase 1d: ConsGate Pure sleeve (N=6) --
cat("[Phase 1d] ConsGate Pure sleeve (N=6)...\n")
RAWDATA <- copy(RAWDATA_ORIG); BM_DT <- copy(BM_DT_ORIG)
MACRO_HARD_THRESH  <- 30L
REGIME_SOFT_THRESH <- 15L
source(file.path(SCRIPT_DIR, "consgate_pure_engine.R"))
FACTORS_GATE <- copy(FACTORS)
setkey(RAWDATA, Ticker, Date); gc(verbose = FALSE)

sim_gate <- run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS_GATE,
  n_holdings = 6, weight_method = "equal",
  commission = 0.0015,
  buffer_zone = list(keep_n = 12L, entry_n = 6L),
  vol_target = 0.18, vol_lookback = 60L
)

# -- Phase 1e: TP Gap sleeve (N=6) --
cat("[Phase 1e] TP Gap sleeve (N=6)...\n")
RAWDATA <- copy(RAWDATA_ORIG); BM_DT <- copy(BM_DT_ORIG)

source(file.path(DATA_DIR, "consensus_parser.R"))
cs <- consensus_load(metrics = c("target_price", "coverage"), date_from = "2001-01-01")

MIN_COVERAGE   <- 3L
TP_MOM_LAG     <- 21L
W_TPGAP        <- 0.6
W_TPMOM        <- 0.4

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
all_signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM]
tp_signal_dates <- sort(all_signal_dates$Signal_Date)
all_dates <- sort(unique(RAWDATA$Date))
min_start <- as.Date("2002-07-01")
tp_signal_dates <- tp_signal_dates[tp_signal_dates >= min_start]

RAWDATA[, TradingValue := Close * Vol]
# AvgTV20: shift by 1 to exclude today's volume (t-20 ~ t-1) — no lookahead
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"), n = 1L, type = "lag"), by = Ticker]

z_safe <- function(x) {
  s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-8) return(rep(0, length(x)))
  (x - mean(x, na.rm = TRUE)) / s
}

factor_list_tp <- list()
n_done_tp <- 0L; n_skipped_tp <- 0L

for (sig_d in tp_signal_dates) {
  sig_d <- as.Date(sig_d)
  snap <- RAWDATA[Date == sig_d, .(Ticker, Close, AvgTV20, Sector)]
  snap <- snap[!is.na(Close) & Close > 0]
  snap <- snap[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(snap) < 30) { n_skipped_tp <- n_skipped_tp + 1L; next }

  cs_now <- cs[Date >= (sig_d - 7) & Date <= sig_d]
  if (nrow(cs_now) == 0) { n_skipped_tp <- n_skipped_tp + 1L; next }
  cs_now <- cs_now[order(Date)][, .SD[.N], by = Ticker]
  cs_now <- cs_now[!is.na(coverage) & coverage >= MIN_COVERAGE & !is.na(target_price)]
  if (nrow(cs_now) < 15) { n_skipped_tp <- n_skipped_tp + 1L; next }

  tp_lag_date <- sig_d - 35
  cs_lag <- cs[Date >= (tp_lag_date - 7) & Date <= tp_lag_date]
  if (nrow(cs_lag) > 0) {
    cs_lag <- cs_lag[order(Date)][, .SD[.N], by = Ticker]
    cs_lag <- cs_lag[!is.na(target_price), .(Ticker, tp_lag = target_price)]
  } else {
    cs_lag <- data.table(Ticker = character(0), tp_lag = numeric(0))
  }

  dt <- merge(snap, cs_now[, .(Ticker, target_price, coverage)], by = "Ticker", all.x = FALSE)
  dt <- merge(dt, cs_lag, by = "Ticker", all.x = TRUE)
  if (nrow(dt) < 15) { n_skipped_tp <- n_skipped_tp + 1L; next }

  dt[, TPGap := (target_price - Close) / Close]
  dt[, TPGap := pmin(pmax(TPGap, -0.5), 2.0)]
  dt[!is.na(tp_lag) & tp_lag > 0, TPMom := (target_price - tp_lag) / tp_lag]
  dt[!is.na(TPMom), TPMom := pmin(pmax(TPMom, -0.5), 1.0)]

  has_gap <- !is.na(dt$TPGap)
  has_mom <- !is.na(dt$TPMom)
  if (sum(has_gap) < 15) { n_skipped_tp <- n_skipped_tp + 1L; next }

  dt[has_gap, z_gap := z_safe(TPGap)]
  dt[!has_gap, z_gap := 0]
  if (sum(has_mom) >= 15) {
    dt[has_mom, z_mom := z_safe(TPMom)]
    dt[!has_mom, z_mom := 0]
  } else { dt[, z_mom := 0] }

  dt[, Score := W_TPGAP * z_gap + W_TPMOM * z_mom]
  dt[, Score := Score - mean(Score, na.rm = TRUE), by = Sector]
  dt[, Date := sig_d]
  factor_list_tp[[length(factor_list_tp) + 1L]] <- dt[!is.na(Score), .(Date, Ticker, Score)]
  n_done_tp <- n_done_tp + 1L
}

FACTORS_TP <- rbindlist(factor_list_tp)
setorder(FACTORS_TP, Date, -Score)
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
for (col in c("TradingValue", "AvgTV20")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}

sim_tp <- run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS_TP,
  n_holdings = 6, weight_method = "equal",
  commission = 0.0015,
  buffer_zone = list(keep_n = 12L, entry_n = 6L),
  vol_target = 0.18, vol_lookback = 60L
)

# ============================================================================
# Phase 2: Gerber+MAD+Detoned RMT + Regime-Adaptive EWMA + HRP
# ============================================================================
cat("\n[Phase 2] Gerber+MAD+Detoned+Regime-Adaptive EWMA HRP...\n")
RAWDATA <- copy(RAWDATA_ORIG)
all_dates <- sort(unique(RAWDATA$Date))

all_sims <- list(def = sim_def, ind = sim_ind, cons = sim_cons,
                 gate = sim_gate, tp = sim_tp)

all_exec_dates <- sort(unique(unlist(lapply(all_sims, function(s) {
  if (nrow(s$HOLDINGS_LOG) > 0) unique(s$HOLDINGS_LOG$Exec_Date)
  else NULL
}))))

common_idx <- sort(as.Date(Reduce(intersect, list(
  as.Date(index(sim_def$strategy_xts)),
  as.Date(index(sim_ind$strategy_xts)),
  as.Date(index(sim_cons$strategy_xts)),
  as.Date(index(sim_gate$strategy_xts)),
  as.Date(index(sim_tp$strategy_xts))
))))
n <- length(common_idx)
cat(sprintf("  Common dates: %d (%s ~ %s)\n", n, min(common_idx), max(common_idx)))

# ---- Improvement 1: Gerber with MAD threshold ----
calc_gerber_mad_cor <- function(ret_mat, threshold_mult = 0.5) {
  p <- ncol(ret_mat)
  n_obs <- nrow(ret_mat)
  if (n_obs < 30 || p < 2) return(cor(ret_mat, use = "pairwise.complete.obs"))

  # MAD instead of SD for threshold (more robust to outliers)
  thresholds <- apply(ret_mat, 2, function(x) median(abs(x - median(x, na.rm = TRUE)), na.rm = TRUE)) * threshold_mult
  thresholds[thresholds < 1e-8] <- 1e-8

  signs <- matrix(0, nrow = n_obs, ncol = p)
  for (j in seq_len(p)) {
    signs[ret_mat[, j] > thresholds[j], j] <- 1
    signs[ret_mat[, j] < -thresholds[j], j] <- -1
  }

  gerber <- matrix(0, p, p)
  for (i in seq_len(p)) {
    for (j in i:p) {
      if (i == j) { gerber[i, j] <- 1; next }
      both_active <- signs[, i] != 0 & signs[, j] != 0
      n_active <- sum(both_active)
      if (n_active < 10) {
        gerber[i, j] <- 0; gerber[j, i] <- 0; next
      }
      concordant <- sum(signs[both_active, i] == signs[both_active, j])
      discordant <- n_active - concordant
      gerber[i, j] <- (concordant - discordant) / n_active
      gerber[j, i] <- gerber[i, j]
    }
  }
  gerber
}

# ---- Improvement 2: Marcenko-Pastur denoising + Detoning ----
denoise_and_detone_cor <- function(cor_mat, q_ratio) {
  p <- ncol(cor_mat)

  eig <- eigen(cor_mat, symmetric = TRUE)
  vals <- eig$values
  vecs <- eig$vectors

  # Marcenko-Pastur bounds
  lambda_plus  <- (1 + 1/sqrt(q_ratio))^2
  lambda_minus <- (1 - 1/sqrt(q_ratio))^2

  # Identify noise eigenvalues (below MP upper bound)
  noise_idx <- which(vals <= lambda_plus)
  signal_idx <- which(vals > lambda_plus)

  if (length(noise_idx) > 0) {
    noise_mean <- mean(vals[noise_idx])
    vals[noise_idx] <- noise_mean
  }

  # Detoning: remove the LARGEST eigenvalue (market factor)
  max_idx <- which.max(vals)
  vals[max_idx] <- mean(vals[-max_idx])

  # Reconstruct
  cor_denoised <- vecs %*% diag(vals) %*% t(vecs)

  # Rescale diagonal to 1
  d_inv <- 1 / sqrt(diag(cor_denoised))
  d_inv[!is.finite(d_inv)] <- 1
  cor_denoised <- diag(d_inv) %*% cor_denoised %*% diag(d_inv)
  cor_denoised <- (cor_denoised + t(cor_denoised)) / 2
  diag(cor_denoised) <- 1

  cor_denoised
}

# ---- Improvement 3: EWMA with regime-adaptive lambda ----
calc_regime_ewma_cov <- function(ret_mat) {
  n_obs <- nrow(ret_mat)
  p <- ncol(ret_mat)
  if (n_obs < 30 || p < 2) return(cov(ret_mat, use = "pairwise.complete.obs"))

  if (n_obs >= 40) {
    recent_vol <- sd(ret_mat[(n_obs - 19):n_obs, 1]) * sqrt(252)
    long_vol   <- sd(ret_mat[1:(n_obs - 20), 1]) * sqrt(252)
    lambda <- if (!is.na(recent_vol) && !is.na(long_vol) &&
                  long_vol > 1e-6 && recent_vol > 1.5 * long_vol) 0.90 else 0.96
  } else {
    lambda <- 0.94
  }

  cat(sprintf("    EWMA lambda = %.2f\n", lambda))

  cov_mat <- cov(ret_mat[1:30, , drop = FALSE], use = "pairwise.complete.obs")
  cov_mat[is.na(cov_mat)] <- 0

  means <- colMeans(ret_mat[1:30, , drop = FALSE], na.rm = TRUE)
  for (t in 31:n_obs) {
    r_t <- ret_mat[t, ] - means
    r_t[is.na(r_t)] <- 0
    cov_mat <- lambda * cov_mat + (1 - lambda) * (r_t %o% r_t)
  }
  cov_mat <- (cov_mat + t(cov_mat)) / 2
  cov_mat
}

# ---- Combined: Gerber MAD + Detoned + Regime EWMA + HRP ----
calc_gerber_mad_detoned_hrp_weights <- function(tickers, ret_dt, n_days = 120, max_w = 0.15) {
  ret_mat <- .build_ret_matrix(tickers, ret_dt, n_days)
  if (is.null(ret_mat) || ncol(ret_mat) < 3) {
    return(setNames(rep(1 / length(tickers), length(tickers)), tickers))
  }

  col_tickers <- colnames(ret_mat)
  n_obs <- nrow(ret_mat)
  p <- ncol(ret_mat)

  # 1. Gerber correlation with MAD threshold
  gerber_cor <- calc_gerber_mad_cor(ret_mat, threshold_mult = 0.5)
  gerber_cor <- pmin(pmax(gerber_cor, -1), 1)
  diag(gerber_cor) <- 1

  # 2. Denoise + Detone
  q_ratio <- n_obs / p
  gerber_cor <- denoise_and_detone_cor(gerber_cor, q_ratio)
  gerber_cor <- pmin(pmax(gerber_cor, -1), 1)

  # Distance matrix for clustering
  dist_mat <- as.dist(sqrt(pmax(0, 0.5 * (1 - gerber_cor))))

  # HRP clustering
  hc <- tryCatch(hclust(dist_mat, method = "ward.D2"),
                 error = function(e) NULL)
  if (is.null(hc)) {
    return(setNames(rep(1 / p, p), col_tickers))
  }
  order_idx <- hc$order

  # 3. Regime-adaptive EWMA covariance for risk allocation
  ewma_cov <- calc_regime_ewma_cov(ret_mat)
  eig <- eigen(ewma_cov, symmetric = TRUE)
  eig$values <- pmax(eig$values, 1e-8)
  ewma_cov <- eig$vectors %*% diag(eig$values) %*% t(eig$vectors)

  # HRP recursive bisection
  w <- .hrp_bisect(ewma_cov, order_idx)
  w <- w / sum(w)

  # Cap weights
  if (any(w > max_w)) {
    w <- pmin(w, max_w)
    w <- w / sum(w)
  }
  setNames(w, col_tickers)
}

# ---- Build holdings map (same as STR_1028) ----
holdings_map <- list()
for (ed in all_exec_dates) {
  ed <- as.Date(ed)
  tickers_all <- character(0)
  scores_all  <- numeric(0)

  for (sname in names(all_sims)) {
    hl <- all_sims[[sname]]$HOLDINGS_LOG
    if (nrow(hl) == 0) next
    hl_ed <- hl[Exec_Date == ed]
    if (nrow(hl_ed) == 0) next
    tickers_all <- c(tickers_all, hl_ed$Ticker)
    scores_all  <- c(scores_all, hl_ed$Score)
  }

  if (length(tickers_all) > 0) {
    dt_tmp <- data.table(Ticker = tickers_all, Score = scores_all)
    dt_tmp <- dt_tmp[, .(Score = max(Score, na.rm = TRUE)), by = Ticker]
    holdings_map[[as.character(ed)]] <- dt_tmp
  }
}

cat(sprintf("  %d execution dates with holdings\n", length(holdings_map)))

# ---- Compute daily portfolio returns ----
COMMISSION <- 0.0015
GERBER_LOOKBACK <- 120L

combined_ret <- numeric(n)
current_tickers <- character(0)
current_weights <- numeric(0)
prev_tickers    <- character(0)
prev_weights    <- numeric(0)

exec_date_set <- sort(as.Date(names(holdings_map)))

for (i in seq_len(n)) {
  d <- common_idx[i]

  if (d %in% exec_date_set) {
    h_info <- holdings_map[[as.character(d)]]
    new_tickers <- h_info$Ticker

    lookback_dates <- tail(all_dates[all_dates < d], GERBER_LOOKBACK)
    ret_sub <- RAWDATA[Ticker %in% new_tickers & Date %in% lookback_dates,
                       .(Date, Ticker, Ret)]

    w <- tryCatch({
      calc_gerber_mad_detoned_hrp_weights(new_tickers, ret_sub,
                                           n_days = GERBER_LOOKBACK, max_w = 0.15)
    }, error = function(e) {
      setNames(rep(1 / length(new_tickers), length(new_tickers)), new_tickers)
    })

    # Realistic turnover cost
    turnover_cost <- 0
    new_w <- as.numeric(w)
    names(new_w) <- names(w)
    if (length(prev_tickers) > 0 && length(prev_weights) > 0) {
      all_tk <- union(prev_tickers, names(new_w))
      w_old_full <- setNames(rep(0, length(all_tk)), all_tk)
      w_new_full <- setNames(rep(0, length(all_tk)), all_tk)
      w_old_full[prev_tickers] <- prev_weights
      w_new_full[names(new_w)] <- new_w
      dollar_turnover <- sum(abs(w_new_full - w_old_full)) / 2
      turnover_cost <- dollar_turnover * COMMISSION * 2
    } else {
      turnover_cost <- COMMISSION
    }

    current_tickers <- names(w)
    current_weights <- as.numeric(w)
    prev_tickers <- current_tickers
    prev_weights  <- current_weights
  }

  if (length(current_tickers) == 0) {
    combined_ret[i] <- 0
    next
  }

  day_rets <- RAWDATA[Ticker %in% current_tickers & Date == d, .(Ticker, Ret)]
  if (nrow(day_rets) == 0) { combined_ret[i] <- 0; next }

  w_day <- current_weights[match(day_rets$Ticker, current_tickers)]
  valid <- !is.na(w_day) & !is.na(day_rets$Ret)
  if (sum(valid) == 0) { combined_ret[i] <- 0; next }

  w_valid <- w_day[valid]
  w_valid <- w_valid / sum(w_valid)
  combined_ret[i] <- sum(w_valid * day_rets$Ret[valid])

  if (d %in% exec_date_set && turnover_cost > 0) {
    combined_ret[i] <- combined_ret[i] - turnover_cost
    turnover_cost <- 0
  }
}

cat(sprintf("  Portfolio return computed: %d days\n", n))

# ============================================================================
# Phase 3: Multi-Timeframe DD Brake (1-day lagged)
# ============================================================================
cat("[Phase 3] Multi-Timeframe DD Brake...\n")
n_f <- length(combined_ret)

nav_med <- cumprod(1 + combined_ret)
dd_med  <- 1 - nav_med / cummax(nav_med)
dd_exp_med <- ifelse(dd_med <= 0.04, 1.0,
                     ifelse(dd_med >= 0.35, 0.30,
                            pmax(0.30, 1.0 - (dd_med - 0.04) / 0.31 * 0.70)))

# Short DD Brake REMOVED (BRK_02). DD_med only.
dd_exp_combined_lagged <- c(1.0, head(dd_exp_med, -1))
after_dd <- combined_ret * dd_exp_combined_lagged

# ============================================================================
# Phase 4: Daily Regime Engine v2 (replaces monthly Soft MRS)
# ============================================================================
cat("[Phase 4] Daily Regime Engine v2 (9-axis)...\n")
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
daily_regime <- build_daily_regime(common_idx)

# Soft ramp using daily MRS: 15->30 -> exposure 100%->30%
# (MRS already t-1 lagged inside build_daily_regime)
MRS_LOW <- 12; MRS_HIGH <- 25; MRS_MIN_EXP <- 0.30
soft_mrs_exp <- numeric(n_f)
for (i in seq_len(n_f)) {
  mrs_val <- daily_regime[Date == common_idx[i], MRS]
  if (length(mrs_val) == 0 || is.na(mrs_val)) mrs_val <- 0
  if (mrs_val < MRS_LOW) {
    soft_mrs_exp[i] <- 1.0
  } else if (mrs_val >= MRS_HIGH) {
    soft_mrs_exp[i] <- MRS_MIN_EXP
  } else {
    soft_mrs_exp[i] <- 1.0 - (mrs_val - MRS_LOW) / (MRS_HIGH - MRS_LOW) * (1.0 - MRS_MIN_EXP)
  }
}
final_ret <- after_dd * soft_mrs_exp

# ============================================================================
# Phase 5: Final assembly + Performance
# ============================================================================
cat("\n[Phase 5] Final assembly...\n")

combined_xts <- xts(final_ret, order.by = common_idx)
names(combined_xts) <- "Strategy"

sim <- sim_def
sim$strategy_xts <- combined_xts
sim$bm_xts <- sim_def$bm_xts[common_idx]
sim$DAILY_NAV_DT <- data.table(
  Date = common_idx,
  NAV = cumprod(1 + final_ret) * 10000,
  Strategy_Ret = final_ret
)

perf <- summarise_perf(combined_xts, STRATEGY_ID)
bm_perf <- summarise_perf(sim$bm_xts, "KOSPI200")

cat(sprintf("\n  %s Results\n", STRATEGY_ID))
cat(sprintf("  CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n",
            perf$CAGR, perf$Sharpe, perf$MDD))
print(rbind(perf, bm_perf))

# ============================================================================
# Phase 6: Output + Analysis + Hurdle
# ============================================================================
out_dir <- file.path(SCRIPT_DIR, "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))
fwrite(rbind(perf, bm_perf), file.path(out_dir, "performance.csv"))

generate_charts(sim, output_dir = out_dir,
                strategy_name = sprintf("%s: %s", STRATEGY_ID, STRATEGY_NAME))

FACTORS_a <- copy(FACTORS_DEF)
RAWDATA_a <- copy(RAWDATA_ORIG)

source(file.path(INFRA_DIR, "strategy_analyzer.R"))
run_analysis(sim, FACTORS_a, RAWDATA_a, BM_DT_ORIG, out_dir,
             strategy_name = STRATEGY_ID)

hurdle <- tryCatch({
  source(file.path(INFRA_DIR, "hurdle_gate.R"))
  run_hurdle_gate(sim_result = sim, strategy_name = STRATEGY_ID,
                  output_dir = out_dir)
}, error = function(e) { cat("Hurdle error:", e$message, "\n"); NULL })

tryCatch({
  if (!is.null(hurdle)) {
    hr <- jsonlite::fromJSON(file.path(out_dir, "hurdle_result.json"))
    tg_strategy_result_with_chart(STRATEGY_ID, hr, out_dir)
  }
}, error = function(e) cat("[TG]", e$message, "\n"))

cat(sprintf("\n[%s] Complete.\n", STRATEGY_ID))
