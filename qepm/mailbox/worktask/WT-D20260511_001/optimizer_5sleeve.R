#==============================================================================
# WT-D20260511_001 — 5-sleeve Allocation Simulation
# Optimizer Research Agent v1.2
#
# Mission:
#   S4 v2 4-sleeve baseline (50/25/20/5 cash) + 4th orthogonal source (3-Axis Vol/Skew)
#   3 candidate addition levels: Low (5%) / Medium (10%) / High (20%)
#   subject to: TDC mitigation, CVaR cap, turnover smoothing, single asset cap 0.20,
#               long-only, Σw=1, max_names 20 (4th sleeve internal)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

WT_ID <- "WT-D20260511_001"
WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"
SA_DIR <- "stage_artifacts/WT_D20260511_001"
OUT_DIR <- WT_DIR
SLEEVE_RET_PATH <- "qepm/mailbox/worktask/WT-P20260509_001/output/sleeve_returns_master.csv"

dir.create(SA_DIR, recursive = TRUE, showWarnings = FALSE)

#==============================================================================
# STEP 0: Load Input Packages
#==============================================================================
alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"))
risk_pkg <- fromJSON(file.path(WT_DIR, "risk_package.json"))
req <- fromJSON(file.path(WT_DIR, "request.json"))

cat("=================================================================\n")
cat("WT:", WT_ID, "— 5-sleeve allocation simulation\n")
cat("=================================================================\n")
cat("alpha hypothesis:", alpha_pkg$hypothesis$title, "\n")
cat("rank_IC:", alpha_pkg$diagnostics$rank_ic, "/ ICIR:", alpha_pkg$diagnostics$icir, "\n")
cat("Σ method:", risk_pkg$diagnostics$sigma_method_selected, "/ cond:", risk_pkg$diagnostics$sigma_security_factor_cond, "\n")
cat("TDC PG2:", risk_pkg$diagnostics$tdc_summary$tdc_new_vs_pg2, "(cap 0.30 — RF-R3 HIGH)\n")

# Alpha vector + confidence
alpha_vec <- unlist(alpha_pkg$alpha_vector)
conf_vec <- unlist(alpha_pkg$confidence_vector)
cat("\nalpha vector N=", length(alpha_vec), "/ confidence vector N=", length(conf_vec), "\n")

#==============================================================================
# STEP 1: Reconstruct NEW sleeve top20 EW returns (sig_date 2011-01 ~ 2023-11)
#==============================================================================
ap <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores.parquet")))
ret_cache <- readRDS(file.path(SA_DIR, "_monthly_returns_cache.rds"))
setDT(ret_cache)

# Re-compute month_ret from month_end_close (stored month_ret is ~100x off)
setorder(ret_cache, Ticker, ym)
ret_cache[, month_ret_calc := c(NA_real_, diff(month_end_close) / head(month_end_close, -1)), by = Ticker]
# Sanity check: |ratio of manual to stored| ≈ 100, so use manual
cat("ret_cache sanity: median |stored / manual_ret| =",
    round(median(abs(ret_cache$month_ret / ret_cache$month_ret_calc), na.rm = TRUE), 3), "\n")

# ym helper
ap[, ym := format(sig_date, "%Y-%m")]

# Top20 selection per sig_date
top20 <- ap[order(sig_date, -alpha), head(.SD, 20), by = .(sig_date, ym)]
top20[, wt := 1/20]

# Forward 1M return convention:
# sig_date = M01 means alpha observed at start of month M.
# We BUY at M01 (open) and SELL at end of M (close).
# This is the standard "form portfolio at sig_date M, hold for month M" convention.
# ret_cache.month_ret_calc[ym=M] = close(M)/close(M-1) - 1 — but we need (close(M) / open(M)) ≈ (close(M)/close(M-1))
# Practical: use month_ret_calc[ym=M] as the realized return for holding from M01 to M-end.

setkey(ret_cache, Ticker, ym)
setkey(top20, Ticker, ym)

# Merge top20 with realized monthly returns (manual-computed)
slv_holdings <- ret_cache[top20, on = c("Ticker", "ym"), nomatch = 0L]

# EW top20 portfolio per sig_date
new_sleeve_monthly <- slv_holdings[, .(ret = sum(month_ret_calc * wt, na.rm = TRUE),
                                       n_active = sum(!is.na(month_ret_calc))),
                                   by = .(sig_date)]
setorder(new_sleeve_monthly, sig_date)

cat("\nNEW sleeve monthly returns reconstructed:\n")
cat(" n_obs:", nrow(new_sleeve_monthly), "/ n_active avg:", round(mean(new_sleeve_monthly$n_active), 1), "\n")
cat(" sample:\n"); print(head(new_sleeve_monthly, 3))

new_ret_mean_ann <- mean(new_sleeve_monthly$ret, na.rm = TRUE) * 12
new_ret_sd_ann <- sd(new_sleeve_monthly$ret, na.rm = TRUE) * sqrt(12)
new_ret_sr_ann <- new_ret_mean_ann / new_ret_sd_ann
cat(" NEW sleeve: mean ann", round(new_ret_mean_ann, 4), "vol ann", round(new_ret_sd_ann, 4),
    "SR ann", round(new_ret_sr_ann, 3), "\n")
# Check vs alpha pkg reported (top20 SR 1.749 / ret_ann 50.65%)
cat(" Cross-check vs alpha pkg top20: SR_pkg=", alpha_pkg$diagnostics$orthogonality_S4_v2$top20_portfolio_sharpe_ann,
    "/ ret_pkg=", alpha_pkg$diagnostics$orthogonality_S4_v2$top20_portfolio_ret_ann, "\n")

#==============================================================================
# STEP 2: Align with 4 baseline sleeves
#==============================================================================
slv_master <- fread(SLEEVE_RET_PATH)
slv_master[, date := as.Date(date)]
new_sleeve_monthly[, date := sig_date]
new_sleeve_monthly[, sig_date := NULL]

# Inner join on dates where all 5 sleeves are available
combo <- merge(slv_master[, .(date, AR_on_M4, TSMOM, KR_10y, Cash)],
               new_sleeve_monthly[, .(date, NEW = ret)],
               by = "date", all = FALSE)
combo <- combo[complete.cases(combo)]

cat("\nMerged 5-sleeve panel:\n")
cat(" n_obs:", nrow(combo), "\n")
cat(" date range:", paste(range(combo$date), collapse=" - "), "\n")
cat(" pairwise stats:\n")
sl <- combo[, .(AR_on_M4, TSMOM, KR_10y, Cash, NEW)]
cat("  mean ann:\n"); print(round(colMeans(sl) * 12, 4))
cat("  vol ann:\n"); print(round(apply(sl, 2, sd) * sqrt(12), 4))
# SR with Cash safe (0/0 → 0)
sds_ann <- apply(sl, 2, sd) * sqrt(12)
srs <- ifelse(sds_ann > 1e-12, colMeans(sl) / sds_ann * 12, 0)
cat("  SR ann:\n"); print(round(srs, 3))
# Correlation only on non-zero variance columns
nonzero_cols <- which(sds_ann > 1e-12)
cor_mat <- diag(ncol(sl))
rownames(cor_mat) <- colnames(cor_mat) <- colnames(sl)
cor_mat[nonzero_cols, nonzero_cols] <- cor(sl[, ..nonzero_cols])
cat("  correlation matrix (Cash row/col is 0, not NA):\n"); print(round(cor_mat, 3))

#==============================================================================
# STEP 3: 5-sleeve allocation candidates (Low / Medium / High)
#==============================================================================

# Baseline S4 v2 4-sleeve: AR_on_M4=0.50 / TSMOM=0.25 / KR_10y=0.20 / Cash=0.05
# 3 candidate addition levels (proportional redistribution to preserve 50:25:20:5 ratio in non-NEW):
make_5sleeve <- function(new_wt) {
  remain <- 1 - new_wt
  c(AR_on_M4 = 0.50 * remain, TSMOM = 0.25 * remain,
    KR_10y = 0.20 * remain, Cash = 0.05 * remain, NEW = new_wt)
}

candidates <- list(
  baseline_S4 = make_5sleeve(0.00),
  low_3pct    = make_5sleeve(0.03),
  low_5pct    = make_5sleeve(0.05),
  med_10pct   = make_5sleeve(0.10),
  high_20pct  = make_5sleeve(0.20)
)

# Verify Σw = 1, long-only
for (nm in names(candidates)) {
  w <- candidates[[nm]]
  stopifnot(abs(sum(w) - 1) < 1e-9)
  stopifnot(all(w >= 0))
}

# Compute portfolio metrics for each candidate
compute_metrics <- function(w, sl_ret) {
  port_ret <- as.matrix(sl_ret) %*% w
  port_ret <- as.numeric(port_ret)
  port_mean_ann <- mean(port_ret) * 12
  port_sd_ann <- sd(port_ret) * sqrt(12)
  port_sr <- port_mean_ann / port_sd_ann

  # MDD from cumulative
  port_nav <- cumprod(1 + port_ret)
  peak <- cummax(port_nav)
  dd <- port_nav / peak - 1
  port_mdd <- min(dd)

  # Sortino
  neg <- port_ret[port_ret < 0]
  port_dvol <- sqrt(mean(neg^2)) * sqrt(12)
  port_sortino <- port_mean_ann / port_dvol

  # Calmar
  port_calmar <- port_mean_ann / abs(port_mdd)

  # CVaR_95 monthly (5% tail)
  cvar95 <- mean(port_ret[port_ret <= quantile(port_ret, 0.05)])
  cvar99 <- mean(port_ret[port_ret <= quantile(port_ret, 0.01)])

  # Hit rate
  hit_rate <- mean(port_ret > 0)

  list(
    SR_ann = round(port_sr, 4),
    CAGR = round(prod(1 + port_ret)^(12/length(port_ret)) - 1, 4),
    mean_ann = round(port_mean_ann, 4),
    vol_ann = round(port_sd_ann, 4),
    MDD = round(port_mdd, 4),
    Sortino = round(port_sortino, 4),
    Calmar = round(port_calmar, 4),
    CVaR_95_monthly = round(cvar95, 4),
    CVaR_99_monthly = round(cvar99, 4),
    hit_rate = round(hit_rate, 4),
    n_obs = length(port_ret)
  )
}

cat("\n========================================\n")
cat("CANDIDATE METRICS\n")
cat("========================================\n")
candidate_metrics <- list()
for (nm in names(candidates)) {
  m <- compute_metrics(candidates[[nm]], sl)
  candidate_metrics[[nm]] <- m
  cat("\n", nm, "(w=", paste(round(candidates[[nm]], 4), collapse=", "), "):\n")
  cat("  SR:", m$SR_ann, "| CAGR:", m$CAGR, "| MDD:", m$MDD,
      "| Sortino:", m$Sortino, "| Calmar:", m$Calmar, "\n")
  cat("  CVaR_95 monthly:", m$CVaR_95_monthly, "(cap 0.025)",
      ifelse(abs(m$CVaR_95_monthly) <= 0.025, "PASS", "BREACH"), "\n")
}

#==============================================================================
# STEP 4: TDC mitigation analysis
#==============================================================================
# TDC linear approximation: TDC_portfolio ≈ TDC_NEW_vs_S4 × NEW_weight
# Risk_pkg: TDC_NEW_vs_PG2 = 0.438 (PG2 = 1715 alone)
# 5-sleeve TDC_portfolio_to_PG2 ≈ (NEW_weight / S4_baseline_concentration) × TDC_pair_NEW_S4

tdc_pair <- risk_pkg$mandate_6_tail_stress_crowding$crowding$tdc_new_vs_pg2_active_book
tdc_cap <- risk_pkg$mandate_6_tail_stress_crowding$crowding$tdc_cap_RF_R3

cat("\n========================================\n")
cat("TDC MITIGATION ANALYSIS (RF-R3)\n")
cat("========================================\n")
cat("TDC pair NEW vs PG2 (1715 alone):", tdc_pair, "\n")
cat("TDC cap (RF-R3):", tdc_cap, "\n")

# Linear approx: portfolio TDC contribution ≈ NEW_weight × TDC_pair × (1715 weight in S4)
# 1715 weight in S4 = 0.50 → effective tail correlation with PG2 active book scaled
tdc_estimates <- sapply(names(candidates), function(nm) {
  w <- candidates[[nm]]
  # Approximate TDC_portfolio ≈ w_NEW × TDC_pair (this is sleeve-internal TDC contribution)
  # plus baseline TDC from 1715 (which is already PG2 by definition)
  w["NEW"] * tdc_pair
})
cat("\nTDC contribution from NEW sleeve by candidate (linear approx):\n")
print(round(tdc_estimates, 4))

#==============================================================================
# STEP 5: Turnover smoothing analysis
#==============================================================================
# Alpha agent: turnover proxy 556% (5.56× monthly Jaccard 0.46)
# This is the cross-section ranking turnover (raw signal)
# Smoothing options:
#   (A) Persistence weighting (e.g., 0.7 × prev + 0.3 × new)
#   (B) Partial rebalance (quarterly = 4 reb/year × 100% = 400% turnover)
#   (C) MVO + turnover penalty in objective

cat("\n========================================\n")
cat("TURNOVER SMOOTHING REQUIREMENTS\n")
cat("========================================\n")
TO_RAW <- 5.56  # 556% from alpha pkg
TO_CAP <- 3.00  # 300% post-smoothing mandate

cat("Raw NEW sleeve turnover (1-way ann):", round(TO_RAW * 100, 1), "%\n")
cat("Cap (Codex C4 mandate):", round(TO_CAP * 100, 1), "%\n")
cat("Required reduction:", round((TO_RAW - TO_CAP) / TO_RAW * 100, 1), "%\n")
cat("Persistence factor needed: phi ≈ 1 - TO_CAP/TO_RAW =", round(1 - TO_CAP/TO_RAW, 3), "\n")
cat("Recommended: phi = 0.5 (50% smoothing) → eff TO ≈", round(TO_RAW * 0.5 * 100, 1), "%\n")

#==============================================================================
# STEP 6: Variance decomposition + sleeve VaR contribution
#==============================================================================
cat("\n========================================\n")
cat("VARIANCE DECOMPOSITION\n")
cat("========================================\n")

sl_cov <- cov(sl) * 12  # annualized cov
for (nm in names(candidates)) {
  w <- candidates[[nm]]
  port_var <- as.numeric(t(w) %*% sl_cov %*% w)
  mctr <- sl_cov %*% w / sqrt(port_var)  # marginal contribution to risk
  ctr <- as.numeric(w * mctr)  # total contribution
  rc_pct <- ctr / sum(ctr)

  if (nm %in% c("baseline_S4", "low_5pct", "med_10pct", "high_20pct")) {
    cat("\n", nm, ":\n")
    cat("  port_vol_ann:", round(sqrt(port_var), 4), "\n")
    cat("  Risk contribution %:\n")
    for (sleeve_nm in colnames(sl)) {
      cat("    ", sleeve_nm, ": w=", round(w[sleeve_nm], 4),
          "| RC=", round(rc_pct[colnames(sl) == sleeve_nm] * 100, 2), "%\n")
    }
  }
}

#==============================================================================
# STEP 7: AX-001 v2 conditional defense ratio at portfolio level
#==============================================================================
# Use alpha pkg ic_bad_regime / ic_normal_regime ratio mapped to sleeve weight
ax001_bad_ratio <- alpha_pkg$diagnostics$crisis_alpha_ax001_v2$ratio_bad_over_normal
cat("\n========================================\n")
cat("AX-001 v2 — Conditional Defense\n")
cat("========================================\n")
cat("Single-sleeve bad/normal IC ratio (alpha pkg):", ax001_bad_ratio, "(>1 borderline defensive)\n")
cat("Risk pkg bootstrap CI 95% lower:", risk_pkg$mandate_1_ax001_v2_anomaly$bad_normal_ratio_bootstrap$ci_95_lower, "\n")
cat("Severity: INCONCLUSIVE (n_BAD=7 small sample)\n")
cat("Portfolio-level defense: NEW sleeve weight × ratio penalty diagnostic\n")

#==============================================================================
# STEP 8: Save outputs
#==============================================================================
# weights.csv — single static snapshot (5-sleeve allocation)
# Note: This is a SLEEVE-LEVEL allocation, not security-level top20 holdings.
# Forge handoff includes both sleeve weights + reference to NEW sleeve top20 holdings.

cat("\n========================================\n")
cat("RECOMMENDATION\n")
cat("========================================\n")

# Decision logic:
# 1. baseline_S4 → admit baseline reference (not 4th source addition)
# 2. low_3pct → TDC contribution 0.013 (very low) — over-cautious, SR gain trivial
# 3. low_5pct → TDC contribution 0.022 (still under 0.30 cap) — recommended candidate
# 4. med_10pct → TDC contribution 0.044 — moderate, more aggressive
# 5. high_20pct → TDC contribution 0.088 — aggressive, beyond Risk Codex C2 concern

# Best metric tradeoffs evaluation — net of turnover cost (15bps × turnover smoothing)
# Realized cost = 15bps × eff_TO (smoothed). Persistence phi=0.5 → eff_TO ≈ 278% × NEW_weight
# (TO scales with sleeve weight since baseline sleeves have 0 turnover)
TO_cap_smoothed <- 2.78  # 278% post-smoothing
cost_per_sleeve_weight <- 0.0015 * TO_cap_smoothed  # ~42bps cost per 100% NEW weight per year

compute_net_metrics <- function(sr_raw, new_wt) {
  cost_annual <- new_wt * cost_per_sleeve_weight
  # Approximate net SR: ret penalty / vol unchanged
  cost_annual
}

score_summary <- data.table(
  candidate = names(candidate_metrics),
  SR = sapply(candidate_metrics, function(m) m$SR_ann),
  CAGR = sapply(candidate_metrics, function(m) m$CAGR),
  MDD = sapply(candidate_metrics, function(m) m$MDD),
  Sortino = sapply(candidate_metrics, function(m) m$Sortino),
  Calmar = sapply(candidate_metrics, function(m) m$Calmar),
  CVaR_95 = sapply(candidate_metrics, function(m) m$CVaR_95_monthly),
  TDC_contrib_linear = round(tdc_estimates, 4),
  est_tc_drag_ann = round(sapply(names(candidates), function(nm)
    candidates[[nm]]["NEW"] * cost_per_sleeve_weight), 4)
)
cat("\nScore summary:\n")
print(score_summary)

fwrite(score_summary, file.path(OUT_DIR, "score_summary_5sleeve.csv"))

# Save sleeve returns 5-panel for Forge
fwrite(combo, file.path(SA_DIR, "sleeve_panel_5sleeve.csv"))

# Save weights as CSV: candidate × sleeve
weights_csv <- rbindlist(lapply(names(candidates), function(nm) {
  w <- candidates[[nm]]
  data.table(candidate = nm, sleeve = names(w), weight = w)
}))
fwrite(weights_csv, file.path(SA_DIR, "weights.csv"))

# Save deployment-ready weights for recommended candidate (5-sleeve LOW_5pct)
recommended_w <- candidates$low_5pct
deployment_weights <- data.table(
  as_of_date = as.Date("2026-05-01"),
  sleeve = names(recommended_w),
  weight = recommended_w
)
fwrite(deployment_weights, file.path(SA_DIR, "deployment_weights_recommended.csv"))

cat("\n========================================\n")
cat("OUTPUT FILES:\n")
cat("  ", file.path(OUT_DIR, "score_summary_5sleeve.csv"), "\n")
cat("  ", file.path(SA_DIR, "sleeve_panel_5sleeve.csv"), "\n")
cat("  ", file.path(SA_DIR, "weights.csv"), "\n")
cat("  ", file.path(SA_DIR, "deployment_weights_recommended.csv"), "\n")
cat("========================================\n")

# Compute summary deltas for draft package
baseline <- candidate_metrics$baseline_S4
delta_low5 <- list(
  delta_SR = candidate_metrics$low_5pct$SR_ann - baseline$SR_ann,
  delta_CAGR = candidate_metrics$low_5pct$CAGR - baseline$CAGR,
  delta_MDD = candidate_metrics$low_5pct$MDD - baseline$MDD,
  delta_Sortino = candidate_metrics$low_5pct$Sortino - baseline$Sortino
)
delta_med10 <- list(
  delta_SR = candidate_metrics$med_10pct$SR_ann - baseline$SR_ann,
  delta_CAGR = candidate_metrics$med_10pct$CAGR - baseline$CAGR,
  delta_MDD = candidate_metrics$med_10pct$MDD - baseline$MDD,
  delta_Sortino = candidate_metrics$med_10pct$Sortino - baseline$Sortino
)
delta_high20 <- list(
  delta_SR = candidate_metrics$high_20pct$SR_ann - baseline$SR_ann,
  delta_CAGR = candidate_metrics$high_20pct$CAGR - baseline$CAGR,
  delta_MDD = candidate_metrics$high_20pct$MDD - baseline$MDD,
  delta_Sortino = candidate_metrics$high_20pct$Sortino - baseline$Sortino
)

cat("\nDelta vs baseline S4:\n")
cat("  LOW 5%: SR ", round(delta_low5$delta_SR, 4), "| CAGR", round(delta_low5$delta_CAGR, 4),
    "| MDD", round(delta_low5$delta_MDD, 4), "| Sortino", round(delta_low5$delta_Sortino, 4), "\n")
cat("  MED 10%: SR ", round(delta_med10$delta_SR, 4), "| CAGR", round(delta_med10$delta_CAGR, 4),
    "| MDD", round(delta_med10$delta_MDD, 4), "| Sortino", round(delta_med10$delta_Sortino, 4), "\n")
cat("  HIGH 20%: SR ", round(delta_high20$delta_SR, 4), "| CAGR", round(delta_high20$delta_CAGR, 4),
    "| MDD", round(delta_high20$delta_MDD, 4), "| Sortino", round(delta_high20$delta_Sortino, 4), "\n")

# Save complete metrics JSON for draft package consumption
output_metrics <- list(
  task_id = WT_ID,
  agent = "optimizer-research",
  as_of_date = "2026-05-11",
  candidates = candidates,
  candidate_metrics = candidate_metrics,
  delta_vs_baseline = list(low_5pct = delta_low5, med_10pct = delta_med10, high_20pct = delta_high20),
  tdc_estimates_contribution = round(tdc_estimates, 4),
  sleeve_correlation = round(cor(sl), 3),
  sleeve_panel_n_obs = nrow(combo),
  sleeve_panel_date_range = c(as.character(min(combo$date)), as.character(max(combo$date))),
  new_sleeve_standalone = list(
    mean_ann = round(new_ret_mean_ann, 4),
    vol_ann = round(new_ret_sd_ann, 4),
    sr_ann = round(new_ret_sr_ann, 4),
    n_obs = nrow(new_sleeve_monthly)
  )
)
write_json(output_metrics, file.path(OUT_DIR, "optimizer_metrics.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 8)

cat("\n  ", file.path(OUT_DIR, "optimizer_metrics.json"), "\n")
cat("\nDONE.\n")
