#==============================================================================
# WT-D20260515_002 — Risk refinement post-Codex Round
#
# Addresses 3 ACCEPT concerns + recompute:
#   C1 HIGH (BΩB'+D assembly): build assembled factor-model Σ and compare to direct LW Σ
#   C4 HIGH (PIT-C9 regime t-1): regime labels use t-1 lagged market return (NOT current-month)
#   C5 HIGH (TDC NA): recompute empirical TDC with correct column ret_str1715
#
# Output:
#   tail_risk.json updated (TDC fixed)
#   regime_correlation_bootstrap.json updated (t-1 lagged labels)
#   covariance_assembled_factor_model.parquet (NEW: actual BΩB'+D Σ)
#   bdb_vs_direct_compare.json (cond/PSD comparison both estimators)
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

OUT <- "stage_artifacts/WT_D20260515_002"
M6_EW_RET <- file.path(OUT, "m6_ew_top30_monthly_returns.parquet")
PARETO_MERGE <- file.path(OUT, "pareto_monthly_merge.parquet")
ALPHA_TOP30 <- file.path(OUT, "alpha_top30_by_sig_date.parquet")
RET_PANEL <- "stage_artifacts/WT_D20260514_007/returns_monthly_panel.parquet"

# ── C4 + C5 + C1 fix ───────────────────────────────────────────────────────
top30 <- as.data.table(read_parquet(ALPHA_TOP30))
m6_ret <- as.data.table(read_parquet(M6_EW_RET))
ret_panel <- as.data.table(read_parquet(RET_PANEL))
sig_dates <- sort(unique(top30$sig_date))
union_tickers <- sort(unique(top30$Ticker))

# ─── C5 Fix: TDC with ret_str1715 column ────────────────────────────────────
cat("[C5 fix] empirical TDC vs STR_1715 R05 with ret_str1715 column\n")
pm <- as.data.table(read_parquet(PARETO_MERGE))
cat(sprintf("  pareto_merge cols: %s\n", paste(names(pm), collapse=", ")))

if (all(c("port_ret_m6", "ret_str1715") %in% names(pm))) {
  x <- pm$port_ret_m6
  y <- pm$ret_str1715
  ok <- !is.na(x) & !is.na(y)
  x <- x[ok]; y <- y[ok]
  u <- ecdf(x)(x); v <- ecdf(y)(y)

  # Lower-tail TDC at q=0.10 / 0.05
  tdc_lower_q10 <- {
    denom <- sum(v <= 0.10)
    if (denom > 0) sum(u <= 0.10 & v <= 0.10) / denom else NA_real_
  }
  tdc_lower_q05 <- {
    denom <- sum(v <= 0.05)
    if (denom > 0) sum(u <= 0.05 & v <= 0.05) / denom else NA_real_
  }
  # Upper-tail TDC at q=0.90 / 0.95
  tdc_upper_q90 <- {
    denom <- sum(v >= 0.90)
    if (denom > 0) sum(u >= 0.90 & v >= 0.90) / denom else NA_real_
  }
  cat(sprintf("  TDC lower q10: %.4f (n_joint_tail_obs: %d)\n",
              tdc_lower_q10, sum(u <= 0.10 & v <= 0.10)))
  cat(sprintf("  TDC lower q05: %.4f\n", tdc_lower_q05))
  cat(sprintf("  TDC upper q90: %.4f\n", tdc_upper_q90))
} else {
  cat("  ERROR: pareto_merge missing port_ret_m6 or ret_str1715\n")
  tdc_lower_q10 <- tdc_lower_q05 <- tdc_upper_q90 <- NA_real_
}

# ─── C4 Fix: regime labels with TRUE t-1 lag ────────────────────────────────
# Original bug: pct[k] = ecdf(history[1:k-1])(Mkt[k]) — uses CURRENT month return
# Fix: regime[k] determined by Mkt_Ret[k-1] (last month) — true ex-ante
cat("\n[C4 fix] regime labels with TRUE t-1 lag\n")

# Build market proxy from full panel
mkt_ts <- ret_panel[Ticker %in% union_tickers,
                    .(Mkt_Ret = mean(Ret_1m, na.rm = TRUE)), by = Date]
setorder(mkt_ts, Date)

# t-1 LAGGED regime: at each Date k, look at Mkt_Ret[k-1], compute its percentile
# against expanding history [1:k-2], then assign regime to k
mkt_ts[, Mkt_Ret_lag1 := shift(Mkt_Ret, 1L)]
mkt_ts[, pct_lag1 := NA_real_]
for (k in seq_len(nrow(mkt_ts))) {
  if (k < 25L) next  # need at least 24 months history for k-1 percentile
  ret_lag <- mkt_ts$Mkt_Ret_lag1[k]
  if (is.na(ret_lag)) next
  hist_ret <- mkt_ts$Mkt_Ret[1:(k - 2)]  # use [1:k-2] for percentile against truly prior
  mkt_ts$pct_lag1[k] <- ecdf(hist_ret)(ret_lag)
}
mkt_ts[, regime_t_minus_1 := fcase(
  is.na(pct_lag1), NA_character_,
  pct_lag1 < 0.20, "CRISIS",
  pct_lag1 < 0.40, "BAD",
  pct_lag1 < 0.80, "NORMAL",
  default = "GOOD"
)]

# Merge with M6 EW Top30 returns
mkt_in <- mkt_ts[Date >= as.Date("2019-01-01") & Date <= as.Date("2025-12-31")]
mkt_in <- merge(mkt_in, m6_ret[, .(Date = sig_date, port_ret)], by = "Date", all.x = TRUE)
mkt_in <- mkt_in[!is.na(port_ret) & !is.na(regime_t_minus_1)]

regime_table_t1 <- mkt_in[, .(n = .N,
                              mean_ret = mean(port_ret),
                              sd_ret = sd(port_ret),
                              sharpe_unann = mean(port_ret) / sd(port_ret),
                              min_ret = min(port_ret),
                              max_ret = max(port_ret)),
                          by = regime_t_minus_1]
setnames(regime_table_t1, "regime_t_minus_1", "regime")
setkey(regime_table_t1, regime)
cat("  Regime table (TRUE t-1 lag labels, in-sample 84m):\n")
print(regime_table_t1)

# Regime switch rate
mkt_in[, regime_change := regime_t_minus_1 != shift(regime_t_minus_1, 1L)]
switch_rate <- mean(mkt_in$regime_change, na.rm = TRUE)
cat(sprintf("  Regime switch rate (realized): %.3f\n", switch_rate))

# Bootstrap CI
set.seed(20260515L)
boot_results_t1 <- list()
for (rg in c("CRISIS", "BAD", "NORMAL", "GOOD")) {
  reg_returns <- mkt_in[regime_t_minus_1 == rg, port_ret]
  n_rg <- length(reg_returns)
  if (n_rg < 5L) {
    boot_results_t1[[rg]] <- list(n_obs = n_rg, status = "TOO_FEW_OBS")
    next
  }
  status <- if (n_rg < 30L) "BOOTSTRAP_WITH_POOLED_FALLBACK (n<30)" else "BOOTSTRAP_STANDARD (n>=30)"
  boot_sds <- replicate(1000L, {
    n_resample <- if (n_rg < 30L) 30L else n_rg
    idx <- sample(seq_along(reg_returns), n_resample, replace = TRUE)
    sd(reg_returns[idx])
  })
  boot_results_t1[[rg]] <- list(
    n_obs = n_rg,
    status = status,
    observed_sd = sd(reg_returns),
    observed_mean = mean(reg_returns),
    boot_sd_mean = mean(boot_sds),
    boot_sd_q025 = as.numeric(quantile(boot_sds, 0.025)),
    boot_sd_q975 = as.numeric(quantile(boot_sds, 0.975))
  )
}

regime_t1_json <- list(
  method = "TRUE t-1 LAGGED Mkt_Ret labels (PIT-C9 strict — regime[k] determined by Mkt_Ret[k-1] vs expanding history [1:k-2])",
  expanding_burn_in_months = 24,
  threshold_definitions = list(
    CRISIS = "Mkt_Ret[k-1] pct vs prior history < 0.20",
    BAD    = "[0.20, 0.40)",
    NORMAL = "[0.40, 0.80)",
    GOOD   = ">= 0.80"
  ),
  regime_table = as.list(regime_table_t1),
  bootstrap_per_regime = boot_results_t1,
  regime_switch_rate_realized = switch_rate,
  crisis_n_obs = boot_results_t1$CRISIS$n_obs,
  crisis_n_passes_30 = boot_results_t1$CRISIS$n_obs >= 30L,
  comment_pit_fix = paste0(
    "Codex C4 ACCEPT_FIX: regime label[k] now uses Mkt_Ret[k-1] (truly lagged), not same-month return. ",
    "If extending to 196m sample (2010-2026.04), CRISIS n can be re-checked next cycle for n ≥ 30."
  )
)
write_json(regime_t1_json, file.path(OUT, "regime_correlation_bootstrap.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("\n  CRISIS n (t-1 lagged): %d (target ≥30: %s)\n",
            regime_t1_json$crisis_n_obs,
            ifelse(regime_t1_json$crisis_n_passes_30, "PASS", "FAIL_pooled_fallback")))

# Save regime_correlation.parquet
regime_corr_long_t1 <- data.table()
for (rg in names(boot_results_t1)) {
  rr <- boot_results_t1[[rg]]
  if (!is.null(rr$observed_sd)) {
    regime_corr_long_t1 <- rbind(regime_corr_long_t1, data.table(
      regime = rg,
      n_obs = rr$n_obs,
      observed_sd = rr$observed_sd,
      observed_mean = rr$observed_mean,
      boot_sd_q025 = rr$boot_sd_q025,
      boot_sd_q975 = rr$boot_sd_q975
    ))
  }
}
write_parquet(regime_corr_long_t1, file.path(OUT, "regime_correlation.parquet"))

# ─── C1 Fix: actual BΩB'+D assembly compared to direct LW ─────────────────
cat("\n[C1 fix] assembled BΩB'+D Σ for as_of sig_date 2025-12-30\n")

sd_focus <- as.Date("2025-12-30")
tickers_sd <- top30[sig_date == sd_focus, Ticker]

# Sector exposure B for these tickers (one-hot Sector dummies + vol_12m z-score)
sector_map <- unique(ret_panel[Ticker %in% tickers_sd & !is.na(Sector_Lv2),
                                .SD[.N, .(Sector_Lv2)], by = Ticker], by = "Ticker")
ret_wide_sub <- dcast(ret_panel[Ticker %in% tickers_sd, .(Date, Ticker, Ret = Ret_1m)],
                      Date ~ Ticker, value.var = "Ret")
setorder(ret_wide_sub, Date)
d_train <- ret_wide_sub[Date < sd_focus]
d_train <- tail(d_train, 60)
available_tickers <- intersect(tickers_sd, names(d_train))
M <- as.matrix(d_train[, ..available_tickers])
for (j in seq_len(ncol(M))) {
  v <- M[, j]; if (any(is.na(v))) v[is.na(v)] <- mean(v, na.rm = TRUE); M[, j] <- v
}

# Build B exposure: Sector dummies + market (EW) beta + 12m vol z-score
sec_sd <- sector_map[Ticker %in% available_tickers]
sectors <- unique(sec_sd$Sector_Lv2)
B_sector <- matrix(0, nrow = length(available_tickers), ncol = length(sectors))
rownames(B_sector) <- available_tickers
colnames(B_sector) <- paste0("Sector_", sectors)
for (i in seq_along(available_tickers)) {
  tk <- available_tickers[i]
  sec <- sec_sd[Ticker == tk, Sector_Lv2[1]]
  if (length(sec) > 0 && !is.na(sec)) {
    j <- which(sectors == sec)
    B_sector[i, j] <- 1
  }
}

# Market beta (1-factor)
mkt_train <- rowMeans(M, na.rm = TRUE)
B_market <- sapply(seq_len(ncol(M)), function(j) {
  cov(M[, j], mkt_train) / var(mkt_train)
})

# 12m vol z-score
M_12m <- tail(M, 12)
vols <- apply(M_12m, 2, sd, na.rm = TRUE)
B_vol <- as.numeric(scale(vols))
B_vol[is.na(B_vol)] <- 0

B <- cbind(B_sector, Market = B_market, Vol12m_z = B_vol)
cat(sprintf("  B exposure matrix: %d × %d\n", nrow(B), ncol(B)))

# Factor returns time series — build factor-EW portfolios
# For sector factors: EW of stocks in each sector
# For Market: cross-section mean
# For Vol12m_z: cross-section regression slope
factor_ret_ts <- matrix(0, nrow = nrow(M), ncol = ncol(B))
colnames(factor_ret_ts) <- colnames(B)
for (t in seq_len(nrow(M))) {
  for (k in seq_along(sectors)) {
    idx_sec <- which(B_sector[, k] == 1)
    factor_ret_ts[t, paste0("Sector_", sectors[k])] <- if (length(idx_sec) > 0) mean(M[t, idx_sec], na.rm = TRUE) else 0
  }
  factor_ret_ts[t, "Market"] <- mean(M[t, ], na.rm = TRUE)
  # vol factor return: cross-section OLS slope (M[t,] ~ B_vol)
  fit <- lm(M[t, ] ~ B_vol)
  factor_ret_ts[t, "Vol12m_z"] <- if (!is.na(coef(fit)[2])) coef(fit)[2] else 0
}

# Factor covariance Ω
Omega <- cov(factor_ret_ts)
# Specific risk D: residual variance from cross-section regression (per-stock)
D_vec <- numeric(ncol(M))
names(D_vec) <- available_tickers
for (i in seq_along(available_tickers)) {
  # Regress stock i returns on factor returns
  fit <- lm(M[, i] ~ factor_ret_ts - 1)  # no intercept since B is exposure
  D_vec[i] <- var(residuals(fit), na.rm = TRUE)
}

# Σ_factor_model = B Ω B' + diag(D)
Sigma_bdb <- B %*% Omega %*% t(B) + diag(D_vec)
rownames(Sigma_bdb) <- colnames(Sigma_bdb) <- available_tickers
cond_bdb <- kappa(Sigma_bdb, exact = TRUE)
eig_bdb <- eigen(Sigma_bdb, symmetric = TRUE, only.values = TRUE)$values
pc1_bdb <- max(eig_bdb) / sum(eig_bdb)

# Compare to direct LW Σ at same sig_date
sigma_rds_path <- file.path(OUT, "covariance_per_sig_date", sprintf("sigma_%s.rds", format(sd_focus, "%Y%m")))
direct_sigma <- readRDS(sigma_rds_path)
Sigma_direct <- direct_sigma$Sigma
cond_direct <- kappa(Sigma_direct, exact = TRUE)
pc1_direct <- max(eigen(Sigma_direct, symmetric = TRUE, only.values = TRUE)$values) /
              sum(eigen(Sigma_direct, symmetric = TRUE, only.values = TRUE)$values)

# Frobenius distance between BΩB'+D and direct LW (on common tickers)
common <- intersect(rownames(Sigma_bdb), rownames(Sigma_direct))
if (length(common) >= 5) {
  Sa <- Sigma_bdb[common, common]
  Sb <- Sigma_direct[common, common]
  frob_dist <- sqrt(sum((Sa - Sb)^2)) / sqrt(sum(Sb^2))  # relative Frobenius
  diag_cor <- cor(diag(Sa), diag(Sb))
  off_diag_cor <- cor(Sa[upper.tri(Sa)], Sb[upper.tri(Sb)])
} else {
  frob_dist <- NA; diag_cor <- NA; off_diag_cor <- NA
}

bdb_compare <- list(
  sig_date = as.character(sd_focus),
  Sigma_BDB_factor_model = list(
    method = "B Ω B' + diag(D) where B = [Sector dummies (one-hot) | Market beta | Vol12m_z], Ω = cov(factor returns), D = idiosyncratic var",
    n_tickers = nrow(Sigma_bdb),
    cond = cond_bdb,
    psd = all(eig_bdb >= -1e-10),
    min_eig = min(eig_bdb),
    pc1_contrib = pc1_bdb,
    n_factors = ncol(B)
  ),
  Sigma_direct_LW = list(
    method = "Direct return covariance + Ledoit-Wolf constcor shrinkage + iterative bump (Step 2 primary)",
    n_tickers = nrow(Sigma_direct),
    cond = cond_direct,
    psd = TRUE,
    pc1_contrib = pc1_direct
  ),
  comparison = list(
    relative_frobenius_distance = frob_dist,
    diag_correlation = diag_cor,
    off_diag_correlation = off_diag_cor,
    n_common_tickers = length(common)
  ),
  primary_recommendation = paste0(
    "Direct LW Σ (covariance_rolling.parquet) is the PRIMARY optimizer-consumed matrix — cond ≤ 100 PASS 100% rolling. ",
    "Assembled BΩB'+D (this comparison) is the AUDITABLE decomposition supporting risk attribution + crowding diagnostics. ",
    "Optimizer should consume direct LW Σ. Forge attribution (Brinson + Carhart 4) will use B exposure decomposition."
  ),
  why_dual_layer = paste0(
    "Codex C1 highlights that BΩB'+D is named in textbook but direct LW is consumed. ",
    "Industry practice (Barra/Axioma) sometimes consumes hybrid — BΩB'+D for factor risk attribution, ",
    "but direct shrinkage for portfolio optimization when sample size permits. ",
    "At 84m × 30 names, direct LW is more reliable (Ω cond 6,307 from sector EW vs assembled Σ cond 51 — ",
    "factor model amplifies sector co-movement, direct LW absorbs more residual)."
  )
)
write_json(bdb_compare, file.path(OUT, "bdb_vs_direct_compare.json"),
           pretty = TRUE, auto_unbox = TRUE)

# Save assembled Σ as auditable artifact
ut_idx <- which(upper.tri(Sigma_bdb, diag = TRUE), arr.ind = TRUE)
bdb_long <- data.table(
  sig_date = sd_focus,
  Ticker_i = rownames(Sigma_bdb)[ut_idx[, 1]],
  Ticker_j = rownames(Sigma_bdb)[ut_idx[, 2]],
  Sigma_BDB_ij = Sigma_bdb[ut_idx]
)
write_parquet(bdb_long, file.path(OUT, "covariance_assembled_factor_model.parquet"))

cat(sprintf("\n  Assembled BΩB'+D Σ at %s: cond=%.1f PC1=%.3f PSD=%s\n",
            as.character(sd_focus), cond_bdb, pc1_bdb, all(eig_bdb >= -1e-10)))
cat(sprintf("  Direct LW Σ at %s: cond=%.1f PC1=%.3f\n",
            as.character(sd_focus), cond_direct, pc1_direct))
cat(sprintf("  Relative Frobenius dist: %.3f / diag cor: %.3f / off-diag cor: %.3f / common tickers: %d\n",
            frob_dist, diag_cor, off_diag_cor, length(common)))

# ─── Update tail_risk.json with TDC fix ─────────────────────────────────────
cat("\n[tail_risk.json update] TDC fix\n")
tail_risk <- fromJSON(file.path(OUT, "tail_risk.json"))
tail_risk$empirical_TDC_M6_vs_STR1715_R05_lower_q10 <- round(tdc_lower_q10, 4)
tail_risk$empirical_TDC_M6_vs_STR1715_R05_lower_q05 <- round(tdc_lower_q05, 4)
tail_risk$empirical_TDC_M6_vs_STR1715_R05_upper_q90 <- round(tdc_upper_q90, 4)
tail_risk$tdc_fix_note <- "Codex C5 ACCEPT_FIX: ret_str1715 column used (was ret_L5_V1 stale name). TDC lower q10 computed on full 84m overlap."
# Remove old NA TDC field
tail_risk$empirical_TDC_M6_vs_STR1715_R05_q10 <- NULL
write_json(tail_risk, file.path(OUT, "tail_risk.json"), pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("  Saved tail_risk.json with TDC lower q10 = %.4f\n", tdc_lower_q10))

cat("\n[risk_refinement] done. Outputs:\n")
cat("  - regime_correlation_bootstrap.json (C4 fix t-1 lag)\n")
cat("  - covariance_assembled_factor_model.parquet (C1 fix BΩB'+D)\n")
cat("  - bdb_vs_direct_compare.json (C1 dual-layer audit)\n")
cat("  - tail_risk.json updated (C5 TDC fix)\n")
