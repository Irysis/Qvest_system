## STR_1028: Gerber+DCC Stock-Level Portfolio Optimization
## Base: STR_1000 5-Sleeve ConsGate Pure
## Change: After Phase 1 selects 30 stocks (6 per sleeve), compute Gerber
##   statistic correlation + EWMA dynamic correlation + HRP on the combined
##   30-stock portfolio. Replaces both sleeve allocation AND stock weighting.
## Overlays: Multi-TF DD Brake + Soft MRS (15->30)
set.seed(1028); options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
STRATEGY_NAME <- "Gerber_DCC_HRP_StockLevel"; STRATEGY_ID <- "STR_1028"
QEPM_AUTO_COMMIT <- TRUE

cat("=== STR_1028: Gerber+DCC Stock-Level HRP ===\n")

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
  preflight_check("STR_1028", family = "5sleeve")
}, error = function(e) cat("[Preflight] ", e$message, "\n"))

cat(sprintf("\n=== %s: %s ===\n\n", STRATEGY_ID, STRATEGY_NAME))
LIQ_THRESHOLD <- 2e8

# ============================================================================
# Phase 1: Run 5 independent sleeves (identical to STR_1000)
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
# Phase 2: Stock-Level Gerber+DCC HRP Optimization
# ============================================================================
cat("\n[Phase 2] Gerber+DCC Stock-Level HRP Optimization...\n")
RAWDATA <- copy(RAWDATA_ORIG)
all_dates <- sort(unique(RAWDATA$Date))

# Collect holdings from all 5 sleeves
all_sims <- list(def = sim_def, ind = sim_ind, cons = sim_cons,
                 gate = sim_gate, tp = sim_tp)

# Get all unique signal dates (exec dates from HOLDINGS_LOG)
all_exec_dates <- sort(unique(unlist(lapply(all_sims, function(s) {
  if (nrow(s$HOLDINGS_LOG) > 0) unique(s$HOLDINGS_LOG$Exec_Date)
  else NULL
}))))

# Common daily dates
common_idx <- sort(as.Date(Reduce(intersect, list(
  as.Date(index(sim_def$strategy_xts)),
  as.Date(index(sim_ind$strategy_xts)),
  as.Date(index(sim_cons$strategy_xts)),
  as.Date(index(sim_gate$strategy_xts)),
  as.Date(index(sim_tp$strategy_xts))
))))
n <- length(common_idx)
cat(sprintf("  Common dates: %d (%s ~ %s)\n", n, min(common_idx), max(common_idx)))

# ---- Gerber Statistic Function ----
# Gerber (2022): Replace Pearson correlation with co-movement indicator
# For each pair (i,j), count concordant/discordant moves beyond threshold
calc_gerber_cor <- function(ret_mat, threshold_mult = 0.5) {
  p <- ncol(ret_mat)
  n_obs <- nrow(ret_mat)
  if (n_obs < 30 || p < 2) return(cor(ret_mat, use = "pairwise.complete.obs"))

  # Threshold = threshold_mult * SD of each column
  sds <- apply(ret_mat, 2, sd, na.rm = TRUE)
  sds[sds < 1e-8] <- 1e-8
  thresholds <- sds * threshold_mult

  # Sign indicators: +1 if above threshold, -1 if below -threshold, 0 otherwise
  signs <- matrix(0, nrow = n_obs, ncol = p)
  for (j in seq_len(p)) {
    signs[ret_mat[, j] > thresholds[j], j] <- 1
    signs[ret_mat[, j] < -thresholds[j], j] <- -1
  }

  # Gerber correlation: for each pair, count concordant - discordant
  gerber <- matrix(0, p, p)
  for (i in seq_len(p)) {
    for (j in i:p) {
      if (i == j) { gerber[i, j] <- 1; next }
      # Only count observations where both have non-zero signs
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

# ---- EWMA Dynamic Correlation (simplified DCC) ----
# Lambda = 0.94 (RiskMetrics standard)
calc_ewma_cov <- function(ret_mat, lambda = 0.94) {
  n_obs <- nrow(ret_mat)
  p <- ncol(ret_mat)
  if (n_obs < 30 || p < 2) return(cov(ret_mat, use = "pairwise.complete.obs"))

  # Initialize with sample covariance of first 30 obs
  cov_mat <- cov(ret_mat[1:30, , drop = FALSE], use = "pairwise.complete.obs")
  cov_mat[is.na(cov_mat)] <- 0

  # EWMA update
  means <- colMeans(ret_mat[1:30, , drop = FALSE], na.rm = TRUE)
  for (t in 31:n_obs) {
    r_t <- ret_mat[t, ] - means
    r_t[is.na(r_t)] <- 0
    cov_mat <- lambda * cov_mat + (1 - lambda) * (r_t %o% r_t)
  }
  # Ensure symmetry
  cov_mat <- (cov_mat + t(cov_mat)) / 2
  cov_mat
}

# ---- HRP with Gerber correlation ----
calc_gerber_hrp_weights <- function(tickers, ret_dt, n_days = 120, max_w = 0.15) {
  ret_mat <- .build_ret_matrix(tickers, ret_dt, n_days)
  if (is.null(ret_mat) || ncol(ret_mat) < 3) {
    return(setNames(rep(1 / length(tickers), length(tickers)), tickers))
  }

  # Map column names back to tickers
  col_tickers <- colnames(ret_mat)

  # Gerber correlation for clustering
  gerber_cor <- calc_gerber_cor(ret_mat, threshold_mult = 0.5)
  gerber_cor <- pmin(pmax(gerber_cor, -1), 1)
  diag(gerber_cor) <- 1

  # Distance matrix from Gerber correlation
  dist_mat <- as.dist(sqrt(0.5 * (1 - gerber_cor)))

  # HRP clustering
  hc <- tryCatch(hclust(dist_mat, method = "ward.D2"),
                 error = function(e) NULL)
  if (is.null(hc)) {
    return(setNames(rep(1 / length(col_tickers), length(col_tickers)), col_tickers))
  }
  order_idx <- hc$order

  # EWMA covariance for risk allocation
  ewma_cov <- calc_ewma_cov(ret_mat, lambda = 0.94)
  # Ensure positive definite
  eig <- eigen(ewma_cov, symmetric = TRUE)
  eig$values <- pmax(eig$values, 1e-8)
  ewma_cov <- eig$vectors %*% diag(eig$values) %*% t(eig$vectors)

  # Recursive bisection with EWMA covariance
  w <- .hrp_bisect(ewma_cov, order_idx)
  w <- w / sum(w)

  # Cap weights
  if (any(w > max_w)) {
    w <- pmin(w, max_w)
    w <- w / sum(w)
  }
  setNames(w, col_tickers)
}

# ---- Build combined stock-level portfolio returns ----
# For each day, determine which stocks are held and their weights
# Holdings change at execution dates

# Build a map: for each exec_date, the list of tickers from all sleeves
# and their factor scores
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
    # Deduplicate: if same ticker in multiple sleeves, keep highest score
    dt_tmp <- data.table(Ticker = tickers_all, Score = scores_all)
    dt_tmp <- dt_tmp[, .(Score = max(Score, na.rm = TRUE)), by = Ticker]
    holdings_map[[as.character(ed)]] <- dt_tmp
  }
}

cat(sprintf("  %d execution dates with holdings\n", length(holdings_map)))

# ---- Compute daily portfolio returns ----
# For each period between execution dates, compute Gerber HRP weights
# then hold constant until next rebalance

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

  # Check if this is an execution date -> rebalance
  if (d %in% exec_date_set) {
    h_info <- holdings_map[[as.character(d)]]
    new_tickers <- h_info$Ticker

    # Get recent returns for Gerber HRP
    lookback_dates <- tail(all_dates[all_dates < d], GERBER_LOOKBACK)
    ret_sub <- RAWDATA[Ticker %in% new_tickers & Date %in% lookback_dates,
                       .(Date, Ticker, Ret)]

    # Compute Gerber HRP weights
    w <- tryCatch({
      calc_gerber_hrp_weights(new_tickers, ret_sub, n_days = GERBER_LOOKBACK,
                              max_w = 0.15)
    }, error = function(e) {
      setNames(rep(1 / length(new_tickers), length(new_tickers)), new_tickers)
    })

    # Realistic turnover: sum(|w_new - w_old|) / 2 (dollar-weighted)
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
      turnover_cost <- dollar_turnover * COMMISSION * 2  # buy + sell
    } else {
      turnover_cost <- COMMISSION
    }

    current_tickers <- names(w)
    current_weights <- as.numeric(w)
    prev_tickers <- current_tickers
    prev_weights  <- current_weights
  }

  # Compute daily return
  if (length(current_tickers) == 0) {
    combined_ret[i] <- 0
    next
  }

  day_rets <- RAWDATA[Ticker %in% current_tickers & Date == d, .(Ticker, Ret)]
  if (nrow(day_rets) == 0) { combined_ret[i] <- 0; next }

  # Match weights to available tickers
  w_day <- current_weights[match(day_rets$Ticker, current_tickers)]
  valid <- !is.na(w_day) & !is.na(day_rets$Ret)
  if (sum(valid) == 0) { combined_ret[i] <- 0; next }

  # Renormalize weights for available tickers
  w_valid <- w_day[valid]
  w_valid <- w_valid / sum(w_valid)
  combined_ret[i] <- sum(w_valid * day_rets$Ret[valid])

  # Subtract commission on rebalance day
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

SHORT_DD_START <- 0.02; SHORT_DD_FULL <- 0.08; SHORT_DD_MIN <- 0.50
dd_short_exp <- rep(1.0, n_f)
for (i in 21:n_f) {
  window_ret <- combined_ret[(i - 20):(i - 1)]
  window_nav <- cumprod(1 + window_ret)
  window_dd  <- 1 - window_nav[20] / max(window_nav)
  if (window_dd <= SHORT_DD_START) {
    dd_short_exp[i] <- 1.0
  } else if (window_dd >= SHORT_DD_FULL) {
    dd_short_exp[i] <- SHORT_DD_MIN
  } else {
    dd_short_exp[i] <- pmax(SHORT_DD_MIN,
      1.0 - (window_dd - SHORT_DD_START) / (SHORT_DD_FULL - SHORT_DD_START) * (1.0 - SHORT_DD_MIN))
  }
}

dd_exp_combined <- pmin(dd_exp_med, dd_short_exp)
dd_exp_combined_lagged <- c(1.0, head(dd_exp_combined, -1))
after_dd <- combined_ret * dd_exp_combined_lagged

# ============================================================================
# Phase 4: Soft MRS (15 -> 30 linear ramp)
# ============================================================================
cat("[Phase 4] Soft MRS overlay...\n")
MRS_LOW <- 15; MRS_HIGH <- 30; MRS_MIN_EXP <- 0.30

macro_regime_dt <- as.data.table(read_parquet(FRED_REGIME_CACHE))
macro_regime_dt[, YM := substr(Date, 1, 7)]
setkey(macro_regime_dt, YM)
mrs_monthly <- macro_regime_dt[, .(YM, Macro_Risk_Score)]
mrs_monthly <- mrs_monthly[!duplicated(YM)]

daily_ym_f <- format(common_idx, "%Y-%m")
soft_mrs_exp <- numeric(n_f)
for (i in seq_len(n_f)) {
  mrs_val <- mrs_monthly[YM == daily_ym_f[i], Macro_Risk_Score]
  if (length(mrs_val) == 0) mrs_val <- 0
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
