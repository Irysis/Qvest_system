#==============================================================================
# WT-D20260514_003 — Baseline comparison + Pareto rebalance audit
# Add: STR_1715_pure (100% admit lineage, β_c2=0) baseline + C2_pure baseline
# Compute Pareto cor on actual realized monthly portfolio returns
#==============================================================================

suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts)
})
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
WT_ID <- "WT-D20260514_003"
STAGE <- "stage_artifacts/WT_D20260514_003"
OPTWS <- file.path(STAGE, "optimizer_workspace")

suppressMessages({
  RAWDATA <- as.data.table(read_parquet(".cache/RAWDATA.parquet"))
  BM_DT <- as.data.table(read_parquet(".cache/benchmark.parquet"))
})

weights_dt <- fread(file.path(OPTWS, "weights_long_v2.csv"))
weights_dt[, as_of_date := as.Date(as_of_date)]
sleeve_dt <- fread(file.path(OPTWS, "sleeve_summary_v2.csv"))
sleeve_dt[, as_of_date := as.Date(as_of_date)]

# Monthly returns
rd <- RAWDATA[!is.na(Ret), .(Date, Ticker, Ret)]
rd[, ym := format(Date, "%Y-%m")]
monthly <- rd[, .(monthly_ret = prod(1 + Ret) - 1, end_date = max(Date)),
              by = .(Ticker, ym)]
setkey(monthly, ym, Ticker)

bm_d <- BM_DT[!is.na(BM_Ret), .(Date, BM_Ret)]
bm_d[, ym := format(Date, "%Y-%m")]
bm_monthly <- bm_d[, .(bm_ret = prod(1 + BM_Ret) - 1, end_date = max(Date)), by = ym]
setkey(bm_monthly, ym)

# ─── Synthetic pure baselines from sleeve_dt + PG2 admit logic ─
# STR_1715_pure: β_c2=0, β_str1715=1.0, overlay applied (PG2 admit pure)
# C2_pure:       β_c2=1.0, β_str1715=0.0, no overlay (full C2 deploy)
all_sd <- sort(unique(weights_dt$as_of_date))
sd_pair <- data.table(as_of_date = all_sd[-length(all_sd)], next_sd = all_sd[-1])
sd_pair[, next_ym := format(next_sd, "%Y-%m")]

# Use any of the methods' weights to extract C2 / STR_1715 sleeve components
# Take MVO_confidence row metadata (overlay)
sd_meta <- weights_dt[method == "MVO_confidence",
                       .(as_of_date, overlay, regime, decision_ym)][
                         , .SD[1], by = as_of_date]
setkey(sd_meta, as_of_date)

# Pure sleeve fwd returns
str1715_records <- list()
c2_records <- list()
pg2_admit_records <- list()

for (i in seq_len(nrow(sd_pair))) {
  sd_t <- sd_pair$as_of_date[i]
  ny <- sd_pair$next_ym[i]
  meta <- sd_meta[as_of_date == sd_t]
  if (nrow(meta) == 0L) next
  overlay <- meta$overlay[1]
  regime  <- meta$regime[1]

  # Compute pure C2: just C2 sleeve weights × forward returns
  c2_w_at_sd <- weights_dt[method == "HRP" & as_of_date == sd_t & beta_c2 > 0,
                            .(Ticker, weight, beta_c2 = beta_c2[1])]
  # HRP at this sig_date gives high β_c2 (about 0.75), but we want pure (β_c2=1)
  # Just take the C2 sleeve weights (Ticker ≠ CASH) and renormalize for β_c2=1
  c2_only_tk <- c2_w_at_sd[Ticker != "CASH"]
  if (nrow(c2_only_tk) > 0L) {
    # Extract pure C2: divide by β_c2 from sleeve_dt
    bc2 <- sleeve_dt[method == "HRP" & as_of_date == sd_t, beta_c2][1]
    # Approximate pure C2: weight / bc2 if bc2 > 0
    if (!is.na(bc2) && bc2 > 0.01) {
      pure_c2_w <- c2_only_tk$weight / bc2
      # Filter out STR_1715 sleeve names from C2 raw weights (need C2 sleeve specifically)
      # Note: tickers in both sleeves → impossible to disentangle from method weight alone
      # Better: re-extract C2 in-sleeve weights from running optimizer's c2_top selection
      # Simpler approach: redo the calc with C2 alone
      # SKIP this for now; use existing methods as comparison
    }
  }
}

# Better approach: derive pure baselines analytically
# pure_c2_ret(t→t+1) = composite ret with β_c2=1, β_s17=0
# pure_s17_ret(t→t+1) = composite ret with β_c2=0, β_s17=1, overlay applied
# composite = β_c2 × pure_c2 + β_s17 × overlay × pure_s17 + cash_share × 0

# Algebraically: composite_ret = β_c2 × R_c2 + β_s17 × overlay × R_s17
# (cash contributes 0)
# At each (sd, method): we have 4 unknowns/4 equations across methods possibly redundant
# Linear: composite_HRP   = bc2_HRP × R_c2 + bs17_HRP × overlay × R_s17
#         composite_MVO   = bc2_MVO × R_c2 + bs17_MVO × overlay × R_s17

port_ret_v2 <- fread(file.path(OPTWS, "port_ret_v2.csv"))
port_ret_v2[, as_of_date := as.Date(as_of_date)]
port_ret_v2[, next_sig_date := as.Date(next_sig_date)]
port_wide <- dcast(port_ret_v2, as_of_date + next_sig_date ~ method,
                    value.var = "port_ret_gross")
sleeve_wide <- dcast(sleeve_dt, as_of_date + decision_ym ~ method,
                      value.var = c("beta_c2", "beta_str1715", "overlay_inherited"))
# Merge
combo <- merge(port_wide, sleeve_wide, by = "as_of_date")
combo <- na.omit(combo)

# Solve per sig_date: R_c2 and R_s17 from any 2 methods (e.g., HRP + ERC)
# Vectorized solve per row using numeric matrix
pure_returns <- matrix(NA_real_, nrow = nrow(combo), ncol = 2)
colnames(pure_returns) <- c("R_c2", "R_s17")
for (i in seq_len(nrow(combo))) {
  ov <- as.numeric(combo$overlay_inherited_HRP[i])
  bc2_HRP <- as.numeric(combo$beta_c2_HRP[i])
  bs17_HRP <- as.numeric(combo$beta_str1715_HRP[i])
  bc2_ERC <- as.numeric(combo$beta_c2_ERC[i])
  bs17_ERC <- as.numeric(combo$beta_str1715_ERC[i])
  ret_HRP <- as.numeric(combo$HRP[i])
  ret_ERC <- as.numeric(combo$ERC[i])
  A <- matrix(c(bc2_HRP, bs17_HRP * ov,
                 bc2_ERC, bs17_ERC * ov),
              nrow = 2, byrow = TRUE)
  b <- c(ret_HRP, ret_ERC)
  if (any(!is.finite(A)) || any(!is.finite(b)) || abs(det(A)) < 1e-6) next
  sol <- tryCatch(solve(A, b), error = function(e) c(NA, NA))
  pure_returns[i, 1] <- sol[1]
  pure_returns[i, 2] <- sol[2]
}
combo_pure <- cbind(combo[, .(as_of_date, next_sig_date)],
                     R_c2 = pure_returns[, 1], R_s17 = pure_returns[, 2])

# Compute pure baselines
cat("\n=== Pure C2 Baseline (β_c2=1, β_s17=0, no overlay) ===\n")
cat("=== Pure STR_1715 Baseline (β_c2=0, β_s17=1, overlay applied) ===\n")
# net = gross - cost; for baselines we'll just compute gross

pure_c2_xts <- xts(combo_pure$R_c2, order.by = combo_pure$next_sig_date)
pure_s17_xts <- xts(combo_pure$R_s17, order.by = combo_pure$next_sig_date)
# Also compute STR_1715 PG2 (with overlay) full
pure_s17_with_overlay_xts <- xts(combo_pure$R_s17 * combo[, .(overlay_inherited_HRP)][[1]],
                                  order.by = combo_pure$next_sig_date)
# Actually overlay-applied gross return = overlay × R_s17 (since cash = 0 contribution)
# But PG2 admit return = overlay × R_s17 + (1 - overlay) × 0 = overlay × R_s17
# So PG2 pure baseline = overlay × R_s17 at each sig_date

# Compute STR_1715 with overlay per row
pg2_pure_ret <- combo$overlay_inherited_HRP * combo_pure$R_s17
pg2_pure_xts <- xts(pg2_pure_ret, order.by = combo_pure$next_sig_date)

cat("\n--- Pure C2 (no overlay) ---\n")
print(table.AnnualizedReturns(pure_c2_xts, scale = 12, geometric = TRUE))
cat(sprintf("MDD: %.4f\n", maxDrawdown(pure_c2_xts)))

cat("\n--- Pure STR_1715 raw (no overlay) ---\n")
print(table.AnnualizedReturns(pure_s17_xts, scale = 12, geometric = TRUE))
cat(sprintf("MDD: %.4f\n", maxDrawdown(pure_s17_xts)))

cat("\n--- PG2 admit pure (STR_1715 + overlay V2, cash residual 0) ---\n")
print(table.AnnualizedReturns(pg2_pure_xts, scale = 12, geometric = TRUE))
cat(sprintf("MDD: %.4f\n", maxDrawdown(pg2_pure_xts)))

# Pareto cor: pure_c2 vs pure_s17 (analytical orthogonality)
cor_pure_p <- cor(combo_pure$R_c2, combo_pure$R_s17, use = "complete.obs")
cor_pure_s <- cor(combo_pure$R_c2, combo_pure$R_s17, method = "spearman", use = "complete.obs")
cor_pure_k <- cor(combo_pure$R_c2, combo_pure$R_s17, method = "kendall", use = "complete.obs")
cat(sprintf("\n=== Pareto cor (pure C2 vs pure STR_1715 monthly returns, n=%d) ===\n", nrow(combo_pure)))
cat(sprintf("Pearson:  %.4f\n", cor_pure_p))
cat(sprintf("Spearman: %.4f\n", cor_pure_s))
cat(sprintf("Kendall:  %.4f\n", cor_pure_k))
cat(sprintf("Pareto target (< 0.40 alpha-aware): %s\n", ifelse(abs(cor_pure_p) < 0.40, "PASS", "FAIL")))
cat(sprintf("Pareto strict (Kendall < 0.20):     %s\n", ifelse(abs(cor_pure_k) < 0.20, "PASS", "FAIL")))

# Save pure series
fwrite(combo_pure, file.path(OPTWS, "pure_baselines_decomposed.csv"))

# ─── AX-001 v2 4-axis Re-evaluation (per method post-optimization) ─
cat("\n=== AX-001 v2 4-axis Re-evaluation (per method) ===\n")
# Stress windows
stress_windows <- list(
  Terror_9_11 = c("2001-09-01", "2001-12-31"),
  GFC_2008    = c("2007-10-01", "2009-03-31"),
  Euro_Debt_2011 = c("2011-07-01", "2011-12-31"),
  China_Shock_2015 = c("2015-06-01", "2016-02-29"),
  TradeWar_2018 = c("2018-03-01", "2018-12-31"),
  COVID_2020 = c("2020-01-01", "2020-06-30"),
  RateShock_2022 = c("2022-01-01", "2022-12-31"),
  Iran_War_2026 = c("2026-02-01", "2026-04-30")
)

# Per method: compute crisis alpha vs benchmark
methods <- c("MVO_confidence", "HRP", "ERC", "CVaR_LP", "Ensemble")

ax_axis_records <- list()
for (m in methods) {
  pm <- port_ret_v2[method == m, .(next_sig_date, port_ret_gross, port_ret_net)]
  pm[, ym := format(next_sig_date, "%Y-%m")]
  pm_bm <- merge(pm, bm_monthly[, .(ym, bm_ret)], by = "ym", all.x = TRUE)

  # Axis 1: Crisis Alpha per stress window
  axis1 <- list()
  for (sw_name in names(stress_windows)) {
    sw <- stress_windows[[sw_name]]
    pm_sub <- pm_bm[next_sig_date >= as.Date(sw[1]) & next_sig_date <= as.Date(sw[2])]
    if (nrow(pm_sub) < 2L) next
    cum_p  <- prod(1 + pm_sub$port_ret_gross, na.rm = TRUE) - 1
    cum_bm <- prod(1 + pm_sub$bm_ret, na.rm = TRUE) - 1
    axis1[[sw_name]] <- cum_p - cum_bm
  }
  axis1_vec <- unlist(axis1)
  axis1_mean <- mean(axis1_vec, na.rm = TRUE)
  axis1_pos <- sum(axis1_vec > 0, na.rm = TRUE)
  axis1_total <- sum(!is.na(axis1_vec))
  axis1_pass <- axis1_pos >= ceiling(axis1_total / 2)

  ax_axis_records[[m]] <- data.table(
    method = m,
    axis1_crisis_alpha_mean = axis1_mean,
    axis1_crisis_alpha_positive_count = axis1_pos,
    axis1_crisis_alpha_total_count = axis1_total,
    axis1_pass = axis1_pass
  )
}
ax_axis_dt <- rbindlist(ax_axis_records)
print(ax_axis_dt)
fwrite(ax_axis_dt, file.path(OPTWS, "ax_001_v2_4axis_post_optimization.csv"))

cat("\n[baseline_audit] DONE\n")
