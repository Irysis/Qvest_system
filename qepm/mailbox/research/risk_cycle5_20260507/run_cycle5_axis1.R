# =============================================================================
# Cycle 5 — Axis 1: Realized α vs Predicted forward simulation
# =============================================================================
# Hybrid 70/15/15 (STR_1715_AR + TSMOM + KR_10y) 6/1 발효 시점 baseline α 분포 →
# forward Monte Carlo 1000+ trials × {1, 3, 6, 12} 개월 horizon
#
# Methodology:
#  - Q-Lead Charter §2 "Realized vs Predicted" 사전 monitoring 대비
#  - Block bootstrap (Politis-Romano 1994 stationary bootstrap, mean block L=12)
#    → autocorrelation + 시계열 구조 보존
#  - Hybrid baseline α = 256m 백테 SR 1.665 (PerformanceAnalytics convention)
#  - realized α / predicted α ratio 분포 (각 horizon)
#  - PIT C1: full-sample 통계 사용 X — 256m ICA 누적 분포는 reference baseline only,
#    forward simulation 자체는 sample 분포 추출
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

set.seed(20260508L)

# ---- 0. Config ----
hybrid_dir <- "qepm/mailbox/research/risk_cycle5_20260507"
master_csv <- "qepm/mailbox/research/risk_candidates_20260507/master_returns_hybrid_plus_4candidates.csv"

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

# ---- 1. Data load ----
master <- fread(master_csv)
# Hybrid 70/15/15 weights (admit FINAL 2026-05-05)
w_AR <- 0.70
w_TSMOM <- 0.15
w_KR10y <- 0.15

# Subset post-2015 (TSMOM availability)
master[, ym_date := as.Date(paste0(ym, "-01"))]
post2015 <- master[ym_date >= as.Date("2015-01-01") & has_tsmom == TRUE]
post2015 <- post2015[!is.na(r_AR) & !is.na(r_TSMOM) & !is.na(r_KR10y)]
post2015[, r_Hybrid_70_15_15 := w_AR * r_AR + w_TSMOM * r_TSMOM + w_KR10y * r_KR10y]

cat("Post-2015 sample:", nrow(post2015), "months\n")
cat("Range:", as.character(min(post2015$ym_date)), "~", as.character(max(post2015$ym_date)), "\n")

# ---- 2. Baseline α (Hybrid full-sample monthly mean) ----
# CONVENTION: PerformanceAnalytics standard
# Annualized α = mean(monthly_ret) * 12
# Annualized vol = sd(monthly_ret) * sqrt(12)
# SR = annualized α / annualized vol (rf=0 가정)

mu_hyb <- mean(post2015$r_Hybrid_70_15_15)
sd_hyb <- sd(post2015$r_Hybrid_70_15_15)
ann_alpha_hyb <- mu_hyb * 12
ann_vol_hyb <- sd_hyb * sqrt(12)
sr_hyb_post2015 <- ann_alpha_hyb / ann_vol_hyb

cat("\nBaseline (post-2015 Hybrid 70/15/15):\n")
cat(sprintf("  monthly mean: %.4f\n", mu_hyb))
cat(sprintf("  monthly sd:   %.4f\n", sd_hyb))
cat(sprintf("  ann alpha:    %.4f\n", ann_alpha_hyb))
cat(sprintf("  ann vol:      %.4f\n", ann_vol_hyb))
cat(sprintf("  SR (post2015): %.4f\n", sr_hyb_post2015))

# ---- 3. Block bootstrap forward simulation ----
# Politis-Romano 1994 stationary bootstrap, mean block length L=12
# B = 2000 trials × 4 horizons {1, 3, 6, 12}m
#
# Note: 사이클 4 256m SR 1.665 baseline / post-2015 sub-sample SR 위 계산
# Forward 시뮬레이션은 sample 분포에서 추출 (PIT-C1: full-sample 통계 사용 X)

stationary_bootstrap_block <- function(x, h, L_mean = 12L, B = 2000L) {
  # x: vector of monthly returns
  # h: forward horizon (months)
  # L_mean: mean block length
  # B: number of trials
  n <- length(x)
  out <- matrix(NA_real_, nrow = B, ncol = h)
  for (b in 1:B) {
    pos <- 1L
    while (pos <= h) {
      block_len <- 1L + rgeom(1L, prob = 1 / L_mean)  # geometric block length
      block_len <- min(block_len, h - pos + 1L)
      start <- sample.int(n, 1L)
      idx <- ((start - 1L + 0:(block_len - 1L)) %% n) + 1L
      out[b, pos:(pos + block_len - 1L)] <- x[idx]
      pos <- pos + block_len
    }
  }
  out
}

x_hyb <- post2015$r_Hybrid_70_15_15

cat("\nBlock bootstrap forward simulation (B=2000, L=12):\n")
horizons <- c(1L, 3L, 6L, 12L)
mc_results <- list()

for (h in horizons) {
  bs <- stationary_bootstrap_block(x_hyb, h, L_mean = 12L, B = 2000L)
  # cumulative return per trial
  cum_ret_h <- apply(bs, 1L, function(r) prod(1 + r) - 1)
  # annualized (h-month → 12-month)
  ann_factor <- 12 / h
  ann_ret_h <- (1 + cum_ret_h)^ann_factor - 1
  # realized vs predicted
  ratio_realized_pred <- ann_ret_h / ann_alpha_hyb

  mc_results[[as.character(h)]] <- list(
    horizon_months = h,
    n_trials = 2000L,
    cum_ret_q025 = quantile(cum_ret_h, 0.025),
    cum_ret_q500 = quantile(cum_ret_h, 0.500),
    cum_ret_q975 = quantile(cum_ret_h, 0.975),
    ann_ret_q025 = quantile(ann_ret_h, 0.025),
    ann_ret_q500 = quantile(ann_ret_h, 0.500),
    ann_ret_q975 = quantile(ann_ret_h, 0.975),
    realized_pred_ratio_q025 = quantile(ratio_realized_pred, 0.025),
    realized_pred_ratio_q500 = quantile(ratio_realized_pred, 0.500),
    realized_pred_ratio_q975 = quantile(ratio_realized_pred, 0.975),
    pr_underperform_50pct = mean(ratio_realized_pred < 0.5),
    pr_outperform_150pct = mean(ratio_realized_pred > 1.5),
    pr_neg_cum_ret = mean(cum_ret_h < 0)
  )
}

# Save results
mc_dt <- rbindlist(lapply(mc_results, function(r) {
  data.table(
    horizon_months = r$horizon_months,
    n_trials = r$n_trials,
    cum_ret_q025 = r$cum_ret_q025,
    cum_ret_q500 = r$cum_ret_q500,
    cum_ret_q975 = r$cum_ret_q975,
    ann_ret_q025 = r$ann_ret_q025,
    ann_ret_q500 = r$ann_ret_q500,
    ann_ret_q975 = r$ann_ret_q975,
    realized_pred_ratio_q025 = r$realized_pred_ratio_q025,
    realized_pred_ratio_q500 = r$realized_pred_ratio_q500,
    realized_pred_ratio_q975 = r$realized_pred_ratio_q975,
    pr_underperform_50pct = r$pr_underperform_50pct,
    pr_outperform_150pct = r$pr_outperform_150pct,
    pr_neg_cum_ret = r$pr_neg_cum_ret
  )
}))
fwrite(mc_dt, file.path(hybrid_dir, "axis1_realized_vs_predicted_mc.csv"))

cat("\nResults summary:\n")
print(mc_dt)

# ---- 4. Alert threshold (monitoring agent inheritance) ----
# Charter §2 Realized vs Predicted convention:
#   - Mild drift: ratio ∈ [0.7, 1.3]
#   - Material drift: ratio ∈ [0.5, 0.7] ∪ [1.3, 1.5]
#   - Severe drift: ratio < 0.5 OR > 1.5
alert_thresholds <- list(
  mild_drift_lower = 0.7,
  mild_drift_upper = 1.3,
  material_drift_lower = 0.5,
  material_drift_upper = 1.5,
  severe_drift_lower = 0.5,
  severe_drift_upper = 1.5,
  rationale = "Charter §2 Realized vs Predicted convention. Forward simulation의 P(severe drift) > 25% 시 monitoring agent 사전 alert 권장"
)

# Pr(severe drift) by horizon
pr_severe <- sapply(horizons, function(h) {
  res <- mc_results[[as.character(h)]]
  res$pr_underperform_50pct + res$pr_outperform_150pct
})
names(pr_severe) <- paste0("h", horizons, "m")

cat("\nP(severe drift) by horizon:\n")
print(pr_severe)

# Save axis 1 summary
axis1_summary <- list(
  axis = "axis_1_realized_vs_predicted_forward_mc",
  baseline = list(
    sample_period = paste0(min(post2015$ym_date), "_to_", max(post2015$ym_date)),
    n_obs = nrow(post2015),
    monthly_mean = mu_hyb,
    monthly_sd = sd_hyb,
    ann_alpha = ann_alpha_hyb,
    ann_vol = ann_vol_hyb,
    sr_post2015 = sr_hyb_post2015,
    sr_256m_l284 = 1.665
  ),
  methodology = list(
    bootstrap_type = "Politis-Romano stationary bootstrap",
    block_length_mean = 12L,
    n_trials = 2000L,
    horizons = horizons,
    citation = "Politis-Romano 1994 JASA"
  ),
  alert_thresholds = alert_thresholds,
  pr_severe_drift_by_horizon = as.list(pr_severe),
  results_csv = "axis1_realized_vs_predicted_mc.csv"
)

write_json(axis1_summary, file.path(hybrid_dir, "axis1_summary.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat("\n[Axis 1] DONE\n")
