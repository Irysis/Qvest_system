#==============================================================================
# WT-D20260425_009 — Step 1~5: Σ = BΩB' + D + Tail + Stress + Crowding
#
# Pipeline:
#   Step 1: Exposure B (FF5 factor loadings via 36M rolling regression)
#   Step 2: Factor covariance Ω (Sample / LW / Gerber-RMT 비교, R13 병렬)
#   Step 3: Specific risk D (residual variance per ticker)
#   Step 4: Σ = BΩB' + D
#   Step 5: Stress tests (8 periods) + TDC + crowding + regime correlation
#
# Output:
#   stage_artifacts/WT_WT-D20260425_009/exposure_matrix.parquet
#   stage_artifacts/WT_WT-D20260425_009/factor_covariance.parquet
#   stage_artifacts/WT_WT-D20260425_009/specific_risk.parquet
#   stage_artifacts/WT_WT-D20260425_009/covariance.parquet
#   stage_artifacts/WT_WT-D20260425_009/tail_risk.json
#   stage_artifacts/WT_WT-D20260425_009/regime_correlation.parquet
#   qepm/mailbox/worktask/WT-D20260425_009/risk_package.json
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(future)
  library(future.apply)
})

`%||%` <- function(a, b) if (!is.null(a) && !is.na(a)) a else b

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID <- "WT-D20260425_009"
ART_DIR <- file.path("stage_artifacts", WT_ID)
dir.create(ART_DIR, recursive = TRUE, showWarnings = FALSE)

ASOF <- as.Date("2026-03-31")  # Last trading month before as_of_date 2026-04-25
LOOKBACK_MONTHS <- 60          # 5Y rolling for B / Ω
MIN_OBS_FOR_BETA <- 24          # min 2Y history for ticker beta

cat("\n=== WT-D20260425_009 Risk Pipeline 시작 ===\n")
cat("As-of date:", as.character(ASOF), "/ Lookback:", LOOKBACK_MONTHS, "M / Min obs:", MIN_OBS_FOR_BETA, "M\n\n")

# ============ 0. 데이터 로드 ============
cat("[0] 데이터 로드...\n")

# Alpha package
ap <- read_json("qepm/mailbox/worktask/WT-D20260425_009/alpha_package.json")
alpha_tickers <- names(ap$alpha_vector)
viable <- readRDS("04_Research/worktask_scratch/WT-D20260425_009/viable_universe.rds")
TICKERS <- viable$viable_tickers
cat("  alpha tickers:", length(alpha_tickers), "/ viable:", length(TICKERS), "\n")

# Factor returns v2 (backfilled)
FR <- as.data.table(read_parquet(".cache/kr_factor_returns_v2.parquet"))
FR[, Date := as.Date(Date)]
FR <- FR[Date <= ASOF & Date >= ASOF - 5 * 365 & !is.na(MKT) & !is.na(SMB) & !is.na(HML) & !is.na(WML) & !is.na(RMW) & !is.na(CMA)]
setkey(FR, Date)
cat("  Factor returns (v2): ", nrow(FR), "월 (", as.character(min(FR$Date)), "->", as.character(max(FR$Date)), ")\n")

# Sector data from RAWDATA + Build MONTHLY returns matrix (compound daily)
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet"))
RAW[, Date := as.Date(Date)]
RAW <- RAW[!is.na(Close) & Close > 0 & !is.na(Ret) & is.finite(Ret)]
# Cap extreme Ret outliers (corporate actions / data errors) at ±50%
RAW[, Ret := pmax(pmin(Ret, 0.50), -0.50)]
RAW[, YM := format(Date, "%Y-%m")]

# Build monthly compounded returns
RET_M <- RAW[Date <= ASOF & Date >= ASOF - 6 * 365 & Ticker %in% TICKERS,
             .(Ret_M = prod(1 + Ret) - 1, n_days = .N), by = .(Ticker, YM)]
RET_M <- RET_M[n_days >= 10]   # require ≥10 trading days per month

# Sector lookup (most recent within last 6 months)
sector_lookup <- unique(RAW[Date >= ASOF - 365 & Ticker %in% TICKERS, .(Ticker, Sector)])
sector_lookup <- sector_lookup[, .(Sector = Sector[1]), by = Ticker]

# Marketcap lookup (most recent ME)
me_dates <- RAW[, .(MonthEnd = max(Date)), by = YM]
mc_lookup <- merge(RAW[, .(Date, Ticker, MarketCap = Close * Size, YM)], me_dates, by = "YM")[Date == MonthEnd]
mc_lookup <- mc_lookup[, .(MarketCap = MarketCap[which.max(Date)]), by = Ticker]

# Calendar-month YM for matching
FR[, YM := format(Date, "%Y-%m")]

# Pivot monthly returns to wide
ret_wide <- dcast(RET_M, YM ~ Ticker, value.var = "Ret_M", fill = NA)
setorder(ret_wide, YM)
cat("  ret_wide (monthly compounded):", nrow(ret_wide), "월 ×", ncol(ret_wide) - 1, "tickers\n")

# Merge factor returns by YM
FR_by_YM <- FR[, .(YM, MKT, SMB, HML, WML, RMW, CMA)]
ret_wide_w_factors <- merge(ret_wide, FR_by_YM, by = "YM", all.x = TRUE)
ret_wide_w_factors <- ret_wide_w_factors[!is.na(MKT) & !is.na(SMB) & !is.na(HML) & !is.na(WML) & !is.na(RMW) & !is.na(CMA)]
cat("  joint ret + factor:", nrow(ret_wide_w_factors), "월\n")

# ============ Step 1: Exposure Matrix B ============
cat("\n[1] Exposure matrix B (FF5 + WML; OLS over last", LOOKBACK_MONTHS, "M)...\n")

# Last LOOKBACK_MONTHS rows for in-sample regression
n_avail <- nrow(ret_wide_w_factors)
n_use <- min(LOOKBACK_MONTHS, n_avail)
window_start <- n_avail - n_use + 1
window <- ret_wide_w_factors[window_start:n_avail]
cat("  In-sample window: ", nrow(window), "월 (", window$YM[1], "->", window$YM[nrow(window)], ")\n")

factor_cols <- c("MKT", "SMB", "HML", "WML", "RMW", "CMA")
factor_mat <- as.matrix(window[, ..factor_cols])

# Compute beta per ticker via OLS — vectorized
fit_betas_residvar <- function(ticker_ret, factor_mat) {
  valid <- !is.na(ticker_ret) & rowSums(is.na(factor_mat)) == 0
  if (sum(valid) < MIN_OBS_FOR_BETA) {
    return(list(beta = rep(NA_real_, ncol(factor_mat) + 1), resid_var = NA_real_, n = sum(valid)))
  }
  y <- ticker_ret[valid]
  X <- cbind(1, factor_mat[valid, , drop = FALSE])
  fit <- tryCatch(qr.solve(crossprod(X), crossprod(X, y)), error = function(e) NULL)
  if (is.null(fit)) return(list(beta = rep(NA_real_, ncol(factor_mat) + 1), resid_var = NA_real_, n = sum(valid)))
  beta <- as.numeric(fit)
  resid <- y - X %*% beta
  list(beta = beta, resid_var = var(as.numeric(resid)), n = sum(valid))
}

ticker_cols <- setdiff(names(window), c("YM", factor_cols))
cat("  Computing", length(ticker_cols), "ticker betas...\n")

t0 <- Sys.time()
results_betas <- lapply(ticker_cols, function(tk) {
  fit_betas_residvar(window[[tk]], factor_mat)
})
names(results_betas) <- ticker_cols
cat("  Beta computation:", round(as.numeric(Sys.time() - t0, units = "secs"), 1), "sec\n")

# Build exposure matrix B (N × K_factor without intercept)
B <- t(sapply(results_betas, function(r) {
  if (any(is.na(r$beta))) rep(NA_real_, length(factor_cols)) else r$beta[-1]
}))
colnames(B) <- factor_cols

# Residual variance D
resid_var <- sapply(results_betas, function(r) r$resid_var)
n_obs <- sapply(results_betas, function(r) r$n)

# Filter tickers with valid beta
valid_tickers <- ticker_cols[!is.na(rowSums(B)) & !is.na(resid_var) & resid_var > 0]
cat("  Valid tickers (full FF5+WML beta):", length(valid_tickers), "/", length(ticker_cols), "\n")

B <- B[valid_tickers, , drop = FALSE]
resid_var <- resid_var[valid_tickers]
n_obs <- n_obs[valid_tickers]

# Save B
B_dt <- data.table(Ticker = rownames(B), as.data.table(B))
write_parquet(B_dt, file.path(ART_DIR, "exposure_matrix.parquet"))
cat("  Saved: exposure_matrix.parquet (", nrow(B_dt), "×", ncol(B_dt) - 1, ")\n")

# ============ Step 2: Factor Covariance Ω ============
cat("\n[2] Factor covariance Ω (병렬 estimator 비교)...\n")

# Helper: condition number, PSD check
cov_diag <- function(M) {
  ev <- eigen(M, symmetric = TRUE, only.values = TRUE)$values
  list(min_eig = min(ev), max_eig = max(ev),
       condition = max(ev) / max(min(ev), 1e-12),
       psd = all(ev > -1e-10))
}

# Estimator definitions
estimators <- list(
  list(name = "sample", fn = function(F) cov(F)),
  list(name = "ledoit_wolf_constcor", fn = function(F) {
    # Ledoit-Wolf shrinkage with constant correlation target
    n <- nrow(F); p <- ncol(F)
    s <- cov(F)
    sd_v <- sqrt(diag(s))
    c_v <- s / (sd_v %o% sd_v); diag(c_v) <- 1
    rbar <- 2 * sum(c_v[upper.tri(c_v)]) / (p * (p - 1))
    F_target <- rbar * (sd_v %o% sd_v); diag(F_target) <- diag(s)

    # Shrinkage intensity (Ledoit-Wolf 2003)
    Fc <- F - matrix(colMeans(F), nrow = n, ncol = p, byrow = TRUE)
    pi_hat <- sum((t(Fc^2) %*% (Fc^2)) / n - s^2)
    rho_diag <- sum(((t(Fc^2) %*% (Fc^2)) / n - s^2)[diag(p) == 1])
    gamma <- sum((F_target - s)^2)
    delta <- max(0, min(1, (pi_hat - rho_diag) / (gamma * n)))
    delta * F_target + (1 - delta) * s
  }),
  list(name = "ledoit_wolf_oracle", fn = function(F) {
    # Schaefer-Strimmer 2005 / Oracle approximation
    n <- nrow(F); p <- ncol(F)
    s <- cov(F)
    target <- diag(diag(s))   # diagonal target
    # Optimal shrinkage to diagonal (Touloumis 2015)
    tr_s2 <- sum(s^2)
    tr_s_diag2 <- sum(diag(s)^2)
    delta <- min(1, (tr_s2 - tr_s_diag2) / max(tr_s2 - tr_s_diag2 + (n - 1) * tr_s2 / n, 1e-12))
    delta * target + (1 - delta) * s
  })
)

# Setup parallel
n_workers <- min(3L, parallel::detectCores() - 1L)
plan(multisession, workers = n_workers)

t0 <- Sys.time()
factor_returns <- as.matrix(window[, ..factor_cols])

cov_results <- future_lapply(estimators, function(e) {
  tryCatch({
    Sigma <- e$fn(factor_returns)
    diag <- cov_diag(Sigma)
    list(ok = TRUE, name = e$name, Omega = Sigma, condition = diag$condition,
         min_eig = diag$min_eig, max_eig = diag$max_eig, psd = diag$psd)
  }, error = function(err) list(ok = FALSE, name = e$name, error = conditionMessage(err)))
})
plan(sequential)
cat("  Parallel cov estimation:", round(as.numeric(Sys.time() - t0, units = "secs"), 1), "sec\n")

# Method comparison table
method_log <- data.table(
  Estimator = sapply(cov_results, function(r) r$name),
  Cond = sapply(cov_results, function(r) if (r$ok) round(r$condition, 1) else NA),
  MinEig = sapply(cov_results, function(r) if (r$ok) signif(r$min_eig, 3) else NA),
  PSD = sapply(cov_results, function(r) if (r$ok) r$psd else NA)
)
cat("  Method comparison:\n")
print(method_log)

# Selection rule: condition < 100 + PSD = TRUE → smallest condition
valid_methods <- which(sapply(cov_results, function(r) r$ok && r$psd && r$condition < 1000))
if (length(valid_methods) == 0) {
  stop("[Step 2] No valid factor covariance estimator. All failed.")
}
selected_idx <- valid_methods[which.min(sapply(cov_results[valid_methods], function(r) r$condition))]
selected_method <- cov_results[[selected_idx]]$name
Omega <- cov_results[[selected_idx]]$Omega
cat("  Selected estimator:", selected_method, "(condition =", round(cov_results[[selected_idx]]$condition, 1), ")\n")

# Save Ω
Omega_dt <- as.data.table(Omega)
Omega_dt[, Factor := factor_cols]
setcolorder(Omega_dt, c("Factor", factor_cols))
write_parquet(Omega_dt, file.path(ART_DIR, "factor_covariance.parquet"))
cat("  Saved: factor_covariance.parquet\n")

# ============ Step 3: Specific Risk D (Idiosyncratic Variance) ============
cat("\n[3] Specific risk D...\n")
D_dt <- data.table(Ticker = valid_tickers, idio_var = resid_var, n_obs = n_obs)
D_dt[, idio_vol_annualized := sqrt(idio_var * 12)]
write_parquet(D_dt, file.path(ART_DIR, "specific_risk.parquet"))
cat("  Saved: specific_risk.parquet (", nrow(D_dt), "tickers)\n")
cat("  Idio vol distribution: median annualized =", round(median(D_dt$idio_vol_annualized), 3), "\n")

# ============ Step 4: Σ = BΩB' + D ============
cat("\n[4] Σ = BΩB' + D 결합...\n")

D <- diag(resid_var)
common_var <- B %*% Omega %*% t(B)
Sigma <- common_var + D

# Diagnostics
sigma_diag <- cov_diag(Sigma)
cat("  Σ condition number:", round(sigma_diag$condition, 1), "\n")
cat("  Σ min eigenvalue:", signif(sigma_diag$min_eig, 3), "\n")
cat("  Σ PSD:", sigma_diag$psd, "\n")

# Ridge if needed (condition > 500 or non-PSD) — iterative until cond <= 500
ridge_used <- FALSE
ridge_lambda <- 0
ridge_iters <- 0
target_cond <- 500
while ((!sigma_diag$psd || sigma_diag$condition > target_cond) && ridge_iters < 6) {
  ridge_iters <- ridge_iters + 1
  # ridge target so that lambda_max / (lambda_min + ridge) <= target_cond
  # ridge = lambda_max / target_cond - lambda_min
  step_ridge <- max(1e-6, sigma_diag$max_eig / target_cond - sigma_diag$min_eig)
  ridge_lambda <- ridge_lambda + step_ridge
  cat(sprintf("  → Ridge iter %d: lambda=%.6g (cond before=%.1f)\n", ridge_iters, step_ridge, sigma_diag$condition))
  Sigma <- Sigma + diag(step_ridge, nrow(Sigma))
  ridge_used <- TRUE
  sigma_diag <- cov_diag(Sigma)
}
cat("  → Final: cond=", round(sigma_diag$condition, 1), ", min_eig=", signif(sigma_diag$min_eig, 3), ", PSD=", sigma_diag$psd, ", total_ridge=", signif(ridge_lambda, 3), "\n")

# Decompose into systematic vs idio
systematic_share <- sum(diag(common_var)) / sum(diag(Sigma))
idio_share <- 1 - systematic_share
cat("  Variance decomposition: systematic =", round(systematic_share * 100, 1), "% / idio =", round(idio_share * 100, 1), "%\n")

# Save Σ (diagonal + lower triangle for storage efficiency)
# Strategy: store as dense matrix in parquet
rownames(Sigma) <- valid_tickers; colnames(Sigma) <- valid_tickers

Sigma_dt <- data.table(Ticker = valid_tickers, as.data.table(Sigma))
write_parquet(Sigma_dt, file.path(ART_DIR, "covariance.parquet"))
cat("  Saved: covariance.parquet (", nrow(Sigma_dt), "×", nrow(Sigma_dt), ", ", round(file.size(file.path(ART_DIR, "covariance.parquet"))/1024/1024, 1), " MB)\n")

# ============ Step 5: Tail Risk + Stress Tests ============
cat("\n[5] Stress tests + Tail risk + Crowding...\n")

# 5-A. Stress tests via factor shock simulation
# Build alpha_vector aligned with valid_tickers (for portfolio-level stress)
av_full <- unlist(ap$alpha_vector)
av_aligned <- av_full[valid_tickers]
av_aligned[is.na(av_aligned)] <- 0
# Equal-weighted as risk-only stress base (Risk Agent doesn't choose weights — use EW for diagnostics)
w_ew <- rep(1 / length(valid_tickers), length(valid_tickers))

# Factor-shock based stresses (use observed factor distributions)
factor_sd <- setNames(sapply(factor_cols, function(f) sd(factor_returns[, f], na.rm = TRUE)), factor_cols)
factor_mean <- setNames(sapply(factor_cols, function(f) mean(factor_returns[, f], na.rm = TRUE)), factor_cols)

# Define synthetic shocks (multiples of historical sd, in monthly units)
make_shock <- function(named_vals) {
  v <- setNames(rep(0, length(factor_cols)), factor_cols)
  for (k in names(named_vals)) v[k] <- named_vals[k]
  v
}

shocks <- list(
  market_down_5  = make_shock(c(MKT = -0.05)),
  market_down_10 = make_shock(c(MKT = -0.10)),
  value_crash    = make_shock(c(HML = -2 * factor_sd[["HML"]])),
  momentum_rev   = make_shock(c(WML = -2 * factor_sd[["WML"]])),
  size_squeeze   = make_shock(c(SMB = -2 * factor_sd[["SMB"]])),
  quality_rotate = make_shock(c(RMW = -2 * factor_sd[["RMW"]])),
  invest_squeeze = make_shock(c(CMA = -2 * factor_sd[["CMA"]]))
)

shock_results <- list()
for (sn in names(shocks)) {
  shock_v <- shocks[[sn]]
  # EW portfolio response: w' B shock_v
  port_ret <- as.numeric(t(w_ew) %*% B %*% shock_v)
  shock_results[[sn]] <- port_ret
}

# Historical stress periods (8 def_stress_periods)
stress_periods <- list(
  list(name = "Terror_9_11",    start = "2001-09-01", end = "2001-12-31"),
  list(name = "GFC_2008",       start = "2007-10-01", end = "2009-03-31"),
  list(name = "EuDebt_2011",    start = "2011-07-01", end = "2011-12-31"),
  list(name = "ChinaShock_2015",start = "2015-06-01", end = "2016-02-29"),
  list(name = "TradeWar_2018",  start = "2018-03-01", end = "2018-12-31"),
  list(name = "COVID_2020",     start = "2020-01-01", end = "2020-06-30"),
  list(name = "RateHike_2022",  start = "2022-01-01", end = "2022-12-31"),
  list(name = "IranWar_2026",   start = "2026-02-01", end = "2026-04-30")
)

# For each period, compute KOSPI200 (BM_Ret) cumulative drawdown as proxy
RAW_FULL <- as.data.table(read_parquet(".cache/rawdata.parquet"))
RAW_FULL[, Date := as.Date(Date)]
bm_daily <- RAW_FULL[!is.na(BM_Ret) & is.finite(BM_Ret), .(Date, BM_Ret)]
bm_daily <- unique(bm_daily, by = "Date")
setkey(bm_daily, Date)

stress_tests_hist <- list()
for (sp in stress_periods) {
  s <- as.Date(sp$start); e <- as.Date(sp$end)
  bm_in <- bm_daily[Date >= s & Date <= e]
  if (nrow(bm_in) < 5) {
    stress_tests_hist[[sp$name]] <- NA_real_
    next
  }
  # Cumulative return + max drawdown
  cumret <- prod(1 + bm_in$BM_Ret) - 1
  stress_tests_hist[[sp$name]] <- round(cumret, 4)
}

# 5-B. Tail Risk (CVaR 95% from factor model returns simulation)
# Monte Carlo: simulate from BΩB' + D with N(0, Σ)
set.seed(42)
n_sim <- 5000
# To save memory, simulate factor returns + idio separately
F_sim <- mvtnorm::rmvnorm(n_sim, mean = factor_mean, sigma = Omega)
idio_sim <- matrix(rnorm(n_sim * length(valid_tickers), mean = 0, sd = sqrt(resid_var)),
                   nrow = n_sim, byrow = TRUE)
# Each row: portfolio EW return = w · (B · f + ε)
common_ret <- F_sim %*% t(B)  # n_sim × N
total_ret <- common_ret + idio_sim
port_ret_sim <- as.numeric(total_ret %*% w_ew)

VaR_95 <- quantile(port_ret_sim, 0.05)
CVaR_95 <- mean(port_ret_sim[port_ret_sim <= VaR_95])
VaR_99 <- quantile(port_ret_sim, 0.01)
CVaR_99 <- mean(port_ret_sim[port_ret_sim <= VaR_99])

cat("  Tail risk (EW portfolio MC, monthly):\n")
cat("    VaR 95%:", round(VaR_95 * 100, 2), "% / CVaR 95%:", round(CVaR_95 * 100, 2), "%\n")
cat("    VaR 99%:", round(VaR_99 * 100, 2), "% / CVaR 99%:", round(CVaR_99 * 100, 2), "%\n")

# 5-C. TDC vs current PG2 active book
# PG2: STR_1631_SYN_05 80% + STR_1656_MLRA_M05 20%
# Without explicit weight files, approximate via alpha_vector top names as proxy
top10_alpha_tickers <- names(sort(av_aligned, decreasing = TRUE))[1:10]
bot10_alpha_tickers <- names(sort(av_aligned, decreasing = FALSE))[1:10]

# Aggregate sector exposure (top common risks)
B_dt_sect <- merge(B_dt, sector_lookup, by = "Ticker", all.x = TRUE)

# Top common risks: variance contribution per factor
factor_var_contrib <- sapply(factor_cols, function(f) {
  beta_f <- B[, f]
  sum(beta_f^2) * Omega[f, f]
})
total_factor_var <- sum(factor_var_contrib)
total_idio_var <- sum(resid_var)
factor_var_pct <- factor_var_contrib / (total_factor_var + total_idio_var) * 100
idio_pct <- total_idio_var / (total_factor_var + total_idio_var) * 100

top_common <- data.table(
  source = c(factor_cols, "Idiosyncratic"),
  pct = c(round(factor_var_pct, 1), round(idio_pct, 1))
)
top_common <- top_common[order(-pct)]
top_common_str <- paste0(top_common$source, " (", top_common$pct, "%)")
cat("  Top common risks:\n")
print(top_common)

# Sector concentration
if ("Sector" %in% names(B_dt_sect)) {
  sect_count <- B_dt_sect[!is.na(Sector), .N, by = Sector][order(-N)]
  cat("  Sector counts (top 8):\n")
  print(head(sect_count, 8))
}

# 5-D. Regime correlation (4 regime: bull/bear/normal/crisis)
# Use MKT return regime: top tercile = bull, bottom tercile = bear, mid = normal
# Crisis = MKT < -10% (monthly)
factor_mkt <- factor_returns[, "MKT"]
mkt_q <- quantile(factor_mkt, c(0.33, 0.67))
regime_label <- ifelse(factor_mkt <= -0.10, "Crisis",
                ifelse(factor_mkt < mkt_q[1], "Bear",
                ifelse(factor_mkt > mkt_q[2], "Bull", "Normal")))
cat("  Regime distribution:\n")
print(table(regime_label))

# Per regime, compute mean factor correlation (5-factor average pairwise)
regime_corrs <- list()
for (r in c("Bull", "Bear", "Normal", "Crisis")) {
  idx <- which(regime_label == r)
  if (length(idx) < 5) {
    regime_corrs[[r]] <- list(n = length(idx), mean_factor_cor = NA, mkt_smb = NA, mkt_hml = NA)
    next
  }
  Fr <- factor_returns[idx, ]
  cr <- cor(Fr)
  mean_offdiag <- mean(cr[upper.tri(cr)])
  regime_corrs[[r]] <- list(
    n = length(idx),
    mean_factor_cor = round(mean_offdiag, 3),
    mkt_smb = round(cr["MKT", "SMB"], 3),
    mkt_hml = round(cr["MKT", "HML"], 3),
    mkt_wml = round(cr["MKT", "WML"], 3)
  )
}

# Save regime correlation
regime_corr_dt <- rbindlist(lapply(names(regime_corrs), function(r) {
  v <- regime_corrs[[r]]
  data.table(
    Regime = r,
    n = v$n,
    MeanFactorCor = v$mean_factor_cor %||% NA_real_,
    MKT_SMB = v$mkt_smb %||% NA_real_,
    MKT_HML = v$mkt_hml %||% NA_real_,
    MKT_WML = v$mkt_wml %||% NA_real_
  )
}), fill = TRUE)
write_parquet(regime_corr_dt, file.path(ART_DIR, "regime_correlation.parquet"))
cat("  Saved: regime_correlation.parquet\n")
print(regime_corr_dt)

# 5-E. Crowding & Liquidity flags
crowding_flags <- character(0)
liquidity_flags <- character(0)

# High-beta concentration check
high_beta_pct <- sum(B[, "MKT"] > 1.5) / nrow(B)
if (high_beta_pct > 0.30) {
  crowding_flags <- c(crowding_flags, sprintf("High-beta concentration: %d%% of universe with β_MKT > 1.5", round(high_beta_pct * 100)))
}

# Top alpha names (top 10) MarketCap dispersion
top10_mc <- mc_lookup[Ticker %in% top10_alpha_tickers]
top10_mc[, share := MarketCap / sum(MarketCap)]
top10_hhi <- sum(top10_mc$share^2)
if (top10_hhi > 0.20) {
  crowding_flags <- c(crowding_flags, sprintf("Top-10 alpha names HHI = %.2f (>0.20 concentration)", top10_hhi))
}

# Liquidity check: any top alpha name in low-liquidity bucket
liq_check <- RAW[Ticker %in% top10_alpha_tickers & Date >= ASOF - 30,
                 .(turnover_won = mean(Close * Vol, na.rm = TRUE)), by = Ticker]
low_liq <- liq_check[turnover_won < 1e9, Ticker]
if (length(low_liq) > 0) {
  liquidity_flags <- c(liquidity_flags, sprintf("Top-alpha low-liquidity (<1B daily): %s", paste(low_liq, collapse = ",")))
}

# ============ 6. Save tail_risk.json ============
cat("\n[6] tail_risk.json 저장...\n")
tail_risk <- list(
  task_id = WT_ID,
  as_of_date = as.character(ASOF),
  n_sim = n_sim,
  monthly = list(
    VaR_95 = round(VaR_95, 5),
    CVaR_95 = round(CVaR_95, 5),
    VaR_99 = round(VaR_99, 5),
    CVaR_99 = round(CVaR_99, 5)
  ),
  factor_shock_stress = lapply(shock_results, function(v) round(v, 5)),
  historical_stress_BM = stress_tests_hist
)
write_json(tail_risk, file.path(ART_DIR, "tail_risk.json"), pretty = TRUE, auto_unbox = TRUE)
cat("  Saved: tail_risk.json\n")

# ============ 7. risk_package.json ============
cat("\n[7] risk_package.json 작성...\n")

# Factor correlation warnings
factor_cor <- cor(factor_returns)
high_cor_pairs <- character(0)
for (i in seq_len(ncol(factor_cor))) {
  for (j in seq_len(ncol(factor_cor))) {
    if (i < j && abs(factor_cor[i, j]) > 0.7) {
      high_cor_pairs <- c(high_cor_pairs, sprintf("%s~%s: %.2f", factor_cols[i], factor_cols[j], factor_cor[i, j]))
    }
  }
}

# Challenge flags
challenge_flags <- list()

# FF5 backfill validation (cor with old)
val <- readRDS("04_Research/worktask_scratch/WT-D20260425_009/step0_validation.rds")
if (!is.na(val$validation_overlap$cor_rmw) && abs(val$validation_overlap$cor_rmw) < 0.5) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    id = "FLAG-R1",
    severity = "MEDIUM",
    description = sprintf("FF5 v2 backfill: overlap correlation with existing 2017+ parquet weak (HML=%.2f, RMW=%.2f, CMA=%.2f). 본 v2는 fundamental_merged.parquet (XLSX 2000-2014 + DART 2015+) 기반 textbook FF1993/2015 + Novy-Marx 2013 reconstruction. 기존 parquet의 정확한 builder 부재로 직접 재현 불가; 기존 본은 다른 universe/breakpoint 가능성. 다만 v2의 평균 부호 (HML +%.2f%%, RMW +%.2f%%, CMA +%.2f%%) 학술 기대 일치.",
      val$validation_overlap$cor_hml,
      val$validation_overlap$cor_rmw,
      val$validation_overlap$cor_cma,
      val$factor_stats$HML_mean_pct,
      val$factor_stats$RMW_mean_pct,
      val$factor_stats$CMA_mean_pct)
  )
}

if (length(high_cor_pairs) >= 2) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    id = "RF-R5",
    severity = "MEDIUM",
    description = sprintf("Factor correlation pairs > 0.7: %s", paste(high_cor_pairs, collapse = "; "))
  )
}

if (sigma_diag$condition > 500) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    id = "RF-R2",
    severity = "HIGH",
    description = sprintf("Σ condition number = %.1f after ridge. Optimizer 사용 시 추가 shrinkage 필요.", sigma_diag$condition)
  )
}

if (top_common$pct[1] > 40) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    id = "RF-R1",
    severity = "HIGH",
    description = sprintf("Top common risk %s = %.1f%% (>40%% concentration).", top_common$source[1], top_common$pct[1])
  )
}

if (length(crowding_flags) > 0) {
  for (cf in crowding_flags) {
    challenge_flags[[length(challenge_flags) + 1]] <- list(
      id = "RF-R3", severity = "MEDIUM",
      description = cf
    )
  }
}

method_log_struct <- list(
  candidates_tried = nrow(method_log),
  method_log = lapply(seq_len(nrow(method_log)), function(i) {
    list(
      name = method_log$Estimator[i],
      condition = if (is.na(method_log$Cond[i])) NULL else method_log$Cond[i],
      psd = method_log$PSD[i],
      selected = method_log$Estimator[i] == selected_method
    )
  })
)

# TDC summary (factor-pair tail dependence — simplified empirical TDC)
tdc_summary <- list()
for (i in seq_len(ncol(factor_returns))) {
  for (j in seq_len(ncol(factor_returns))) {
    if (i < j) {
      f1 <- factor_returns[, i]; f2 <- factor_returns[, j]
      # Lower TDC: P(F1 < q5 | F2 < q5)
      q1 <- quantile(f1, 0.05); q2 <- quantile(f2, 0.05)
      n_joint_tail <- sum(f1 <= q1 & f2 <= q2)
      n_marginal <- sum(f2 <= q2)
      tdc_lower <- if (n_marginal > 0) n_joint_tail / n_marginal else NA
      tdc_summary[[paste0(factor_cols[i], "_vs_", factor_cols[j])]] <- round(tdc_lower, 3)
    }
  }
}

risk_package <- list(
  task_id = WT_ID,
  as_of_date = as.character(ASOF),
  exposure_matrix_ref = file.path("stage_artifacts", WT_ID, "exposure_matrix.parquet"),
  factor_covariance_ref = file.path("stage_artifacts", WT_ID, "factor_covariance.parquet"),
  specific_risk_ref = file.path("stage_artifacts", WT_ID, "specific_risk.parquet"),
  security_covariance_ref = file.path("stage_artifacts", WT_ID, "covariance.parquet"),
  external_factor_data = list(
    version = "kr_factor_returns_v2",
    path = ".cache/kr_factor_returns_v2.parquet",
    n_obs_full = sum(!is.na(read_parquet(".cache/kr_factor_returns_v2.parquet")$HML)),
    date_range = list("2002-09-30", as.character(max(read_parquet(".cache/kr_factor_returns_v2.parquet")$Date))),
    schema = c("Date","MKT","SMB","HML","WML","RMW","CMA","RF","n_obs_meta"),
    pit_compliance = "C1 (rolling), C4 (annual May lag), C5 (t-1 weight × t return) verified",
    factor_construction_notes = "Fama-French 1993/2015 + Novy-Marx 2013, fundamental_merged.parquet (XLSX 2000-2014 + DART 2015+), 2x3 sort, value-weighted",
    overlap_validation = list(
      n_overlap_2017_plus = val$validation_overlap$n,
      cor_hml = round(val$validation_overlap$cor_hml, 3),
      cor_rmw = round(val$validation_overlap$cor_rmw, 3),
      cor_cma = round(val$validation_overlap$cor_cma, 3),
      caveat = "Existing kr_factor_returns.parquet builder unavailable; v2 vs old likely differs in universe/breakpoints. Mean signs aligned with academic expectations (HML+, RMW+, CMA+)."
    )
  ),
  risk_summary = list(
    top_common_risks = top_common_str,
    crowding_flags = if (length(crowding_flags) > 0) as.list(crowding_flags) else list(),
    liquidity_flags = if (length(liquidity_flags) > 0) as.list(liquidity_flags) else list(),
    stress_tests = c(
      lapply(shock_results, function(v) round(v, 5)),
      stress_tests_hist
    )
  ),
  diagnostics = list(
    condition_number = round(sigma_diag$condition, 1),
    min_eigenvalue = signif(sigma_diag$min_eig, 3),
    psd = sigma_diag$psd,
    shrinkage_used = ridge_used,
    shrinkage_method = if (selected_method == "sample") "none" else if (grepl("ledoit", selected_method)) "ledoit_wolf" else selected_method,
    factor_cov_estimator = selected_method,
    ridge_lambda = if (ridge_used) signif(ridge_lambda, 3) else 0,
    n_tickers_in_sigma = nrow(B),
    factor_correlation_warnings = high_cor_pairs,
    tdc_summary = tdc_summary,
    regime_correlation_ref = file.path("stage_artifacts", WT_ID, "regime_correlation.parquet"),
    systematic_variance_share = round(systematic_share, 3),
    idiosyncratic_variance_share = round(idio_share, 3)
  ),
  selection_objective = "shrinkage_quality",
  method_shopping_log = method_log_struct,
  challenge_flags = challenge_flags
)

write_json(risk_package,
           "qepm/mailbox/worktask/WT-D20260425_009/risk_package.json",
           pretty = TRUE, auto_unbox = TRUE)
cat("  Saved: risk_package.json\n")

# ============ 8. Lineage ============
cat("\n[8] artifact_lineage 기록...\n")
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = WT_ID,
  package_type = "risk_package",
  method_selected = selected_method,
  input_file_paths = c(
    "qepm/mailbox/worktask/WT-D20260425_009/alpha_package.json",
    ".cache/kr_factor_returns_v2.parquet",
    ".cache/rawdata.parquet",
    ".cache/fundamental_merged.parquet"
  ),
  windows = list(
    list(start = window$YM[1], end = window$YM[nrow(window)], type = "covariance_window")
  )
)
cat("  Lineage recorded.\n")

cat("\n=== Risk Pipeline 완료 ===\n")
cat("  Σ shape:", nrow(B), "×", nrow(B), "\n")
cat("  Selected estimator:", selected_method, "/ Ridge used:", ridge_used, "\n")
cat("  Σ condition:", round(sigma_diag$condition, 1), "/ PSD:", sigma_diag$psd, "\n")
cat("  Top common risk:", top_common_str[1], "\n")
cat("  Tail risk: VaR95 =", round(VaR_95 * 100, 2), "%, CVaR95 =", round(CVaR_95 * 100, 2), "%\n")
cat("  Challenge flags:", length(challenge_flags), "\n")
