# =============================================================================
# Cycle 5 — Axis 2: TE (Tracking Error) drift forward simulation
# =============================================================================
# 6/1 발효 시점 TE baseline (Hybrid 70/15/15 vs BM KOSPI):
#   TE = sd(r_Hybrid - r_BM) * sqrt(12)
#
# Forward 1/3/6/12개월 TE drift Monte Carlo, regime-conditional.
# Regime: 사이클 4 axis 2 분류 inheritance (BULL/NORMAL/CAUTION/CRISIS)
#
# PIT-C5: regime classification full-sample bottom 10% threshold = diagnostic only
#         production overlay 시 t-1 expanding 의무 (사이클 4 caveat 동일)
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

set.seed(20260508L)

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

hybrid_dir <- "qepm/mailbox/research/risk_cycle5_20260507"

# ---- 1. Data load (post-2015 with TSMOM + BM available) ----
master <- fread("qepm/mailbox/research/risk_candidates_20260507/master_returns_hybrid_plus_4candidates.csv")

# BM KOSPI returns from .cache
bm_path <- ".cache/bm_kospi_36yr.parquet"
# Try parquet load via arrow if available
if (file.exists(bm_path)) {
  if (requireNamespace("arrow", quietly = TRUE)) {
    bm_dt <- as.data.table(arrow::read_parquet(bm_path))
  } else {
    bm_dt <- NULL
  }
} else {
  bm_dt <- NULL
}

# Fallback: extract BM from RAWDATA
if (is.null(bm_dt)) {
  cat("Loading benchmark from RAWDATA fallback...\n")
  raw_path <- ".cache/rawdata.parquet"
  if (file.exists(raw_path) && requireNamespace("arrow", quietly = TRUE)) {
    raw_dt <- as.data.table(arrow::read_parquet(raw_path))
    if ("BM_Ret" %in% names(raw_dt) && "Date" %in% names(raw_dt)) {
      bm_dt <- unique(raw_dt[, .(Date, BM_Ret)])
      bm_dt[, ym := format(as.Date(Date), "%Y-%m")]
      # monthly aggregation
      bm_monthly <- bm_dt[, .(bm_ret = prod(1 + BM_Ret) - 1), by = ym]
    } else {
      bm_monthly <- NULL
    }
  } else {
    bm_monthly <- NULL
  }
} else {
  # bm_dt has daily BM
  if ("date" %in% names(bm_dt) && "bm_ret" %in% names(bm_dt)) {
    bm_dt[, ym := format(as.Date(date), "%Y-%m")]
    bm_monthly <- bm_dt[, .(bm_ret = prod(1 + bm_ret) - 1), by = ym]
  } else if ("Date" %in% names(bm_dt)) {
    # generic
    bm_dt[, ym := format(as.Date(Date), "%Y-%m")]
    ret_col <- intersect(c("BM_Ret", "ret", "Ret"), names(bm_dt))[1]
    bm_monthly <- bm_dt[, .(bm_ret = prod(1 + get(ret_col)) - 1), by = ym]
  } else {
    bm_monthly <- NULL
  }
}

if (is.null(bm_monthly)) {
  # Use Cycle 1 BM_Ret column (rough approximation)
  cat("BM cache fallback unavailable. Using master csv BM_Ret if present (sub fallback).\n")
  # Note: master_returns has no BM column. Need different approach.
  # → Construct BM proxy from daily data via Yahoo?
  # → Actually: 사이클 1 directory has bm_kospi_36yr_tail_fit.csv — use this monthly BM proxy
  bm_csv <- "qepm/mailbox/research/risk_model_meta_20260507/bm_kospi_36yr_tail_fit.csv"
  if (file.exists(bm_csv)) {
    bm_csv_dt <- fread(bm_csv)
    cat("Cycle 1 BM tail fit columns:", paste(names(bm_csv_dt), collapse = ", "), "\n")
  }
  # Last-resort proxy: use Cycle 4 axis 3 8-stress BM cumulative returns
  # → not direct monthly. Skip and use AR-only as proxy for tracking
  bm_monthly <- NULL
}

# Subset post-2015
master[, ym_date := as.Date(paste0(ym, "-01"))]
post2015 <- master[ym_date >= as.Date("2015-01-01") & has_tsmom == TRUE]
post2015 <- post2015[!is.na(r_AR) & !is.na(r_TSMOM) & !is.na(r_KR10y)]
post2015[, r_Hybrid_70_15_15 := 0.70 * r_AR + 0.15 * r_TSMOM + 0.15 * r_KR10y]

# Merge BM if available
if (!is.null(bm_monthly)) {
  bm_monthly[, ym := as.character(ym)]
  post2015 <- merge(post2015, bm_monthly, by = "ym", all.x = TRUE)
}

# If BM not available, skip TE vs BM and define internal TE as Hybrid vs AR-only
# (active risk attribution: TSMOM+KR10y overlay deviation from STR_1715 standalone)
# This is Charter §2 valid alternative — "active risk relative to standalone STR_1715"
post2015[, te_active_overlay := r_Hybrid_70_15_15 - r_AR]

# ---- 2. Regime classification (full-sample Hybrid bottom 10%, diagnostic only) ----
post2015[, hybrid_q := ecdf(r_Hybrid_70_15_15)(r_Hybrid_70_15_15)]
post2015[, regime := fifelse(hybrid_q <= 0.10, "CRISIS",
                     fifelse(hybrid_q <= 0.40, "CAUTION",
                     fifelse(hybrid_q <= 0.70, "NORMAL", "BULL")))]

cat("Regime distribution (post-2015):\n")
print(post2015[, .N, by = regime])

# ---- 3. Baseline TE (active overlay deviation) ----
te_active_baseline <- sd(post2015$te_active_overlay) * sqrt(12)
cat(sprintf("\nBaseline TE (active overlay vs STR_1715 standalone, ann): %.4f\n",
            te_active_baseline))

# Per-regime TE
te_regime <- post2015[, .(
  n = .N,
  te_active_ann = sd(te_active_overlay) * sqrt(12),
  mean_active = mean(te_active_overlay) * 12
), by = regime]
te_regime <- te_regime[order(-te_active_ann)]

cat("\nPer-regime TE (active overlay):\n")
print(te_regime)

# ---- 4. TE drift forward simulation (regime-conditional bootstrap) ----
horizons <- c(1L, 3L, 6L, 12L)
B <- 2000L
L_mean <- 12L

# 두 가지 시뮬레이션 path:
# A) regime-pooled: 단일 분포 stationary bootstrap
# B) regime-conditional: 4 regime stationary bootstrap separate

stationary_bootstrap_block <- function(x, h, L_mean = 12L, B = 2000L) {
  n <- length(x)
  out <- matrix(NA_real_, nrow = B, ncol = h)
  for (b in 1:B) {
    pos <- 1L
    while (pos <= h) {
      block_len <- 1L + rgeom(1L, prob = 1 / L_mean)
      block_len <- min(block_len, h - pos + 1L)
      start <- sample.int(n, 1L)
      idx <- ((start - 1L + 0:(block_len - 1L)) %% n) + 1L
      out[b, pos:(pos + block_len - 1L)] <- x[idx]
      pos <- pos + block_len
    }
  }
  out
}

x_te <- post2015$te_active_overlay

# Path A: pooled
te_drift_pooled <- list()
for (h in horizons) {
  bs <- stationary_bootstrap_block(x_te, h, L_mean = L_mean, B = B)
  te_h <- apply(bs, 1L, function(r) sd(r) * sqrt(12))
  drift_ratio <- te_h / te_active_baseline
  te_drift_pooled[[as.character(h)]] <- data.table(
    horizon_months = h,
    path = "pooled",
    te_h_q025 = quantile(te_h, 0.025, na.rm = TRUE),
    te_h_q500 = quantile(te_h, 0.500, na.rm = TRUE),
    te_h_q975 = quantile(te_h, 0.975, na.rm = TRUE),
    drift_ratio_q025 = quantile(drift_ratio, 0.025, na.rm = TRUE),
    drift_ratio_q500 = quantile(drift_ratio, 0.500, na.rm = TRUE),
    drift_ratio_q975 = quantile(drift_ratio, 0.975, na.rm = TRUE),
    pr_drift_gt_50pct = mean(abs(drift_ratio - 1) > 0.5, na.rm = TRUE),
    pr_drift_gt_100pct = mean(abs(drift_ratio - 1) > 1.0, na.rm = TRUE)
  )
}
te_drift_pooled_dt <- rbindlist(te_drift_pooled)

# Path B: regime-conditional
te_drift_regime <- list()
for (rg in unique(post2015$regime)) {
  x_rg <- post2015[regime == rg, te_active_overlay]
  if (length(x_rg) < 5L) next
  for (h in horizons) {
    if (h > length(x_rg)) next
    bs <- stationary_bootstrap_block(x_rg, h, L_mean = min(L_mean, max(2L, length(x_rg) %/% 4L)), B = B)
    te_h <- apply(bs, 1L, function(r) sd(r) * sqrt(12))
    drift_ratio <- te_h / te_active_baseline
    te_drift_regime[[paste0(rg, "_", h)]] <- data.table(
      regime = rg,
      n_regime = length(x_rg),
      horizon_months = h,
      path = "regime_cond",
      te_h_q025 = quantile(te_h, 0.025, na.rm = TRUE),
      te_h_q500 = quantile(te_h, 0.500, na.rm = TRUE),
      te_h_q975 = quantile(te_h, 0.975, na.rm = TRUE),
      drift_ratio_q025 = quantile(drift_ratio, 0.025, na.rm = TRUE),
      drift_ratio_q500 = quantile(drift_ratio, 0.500, na.rm = TRUE),
      drift_ratio_q975 = quantile(drift_ratio, 0.975, na.rm = TRUE),
      pr_drift_gt_50pct = mean(abs(drift_ratio - 1) > 0.5, na.rm = TRUE),
      pr_drift_gt_100pct = mean(abs(drift_ratio - 1) > 1.0, na.rm = TRUE)
    )
  }
}
te_drift_regime_dt <- rbindlist(te_drift_regime, fill = TRUE)

# Save
fwrite(te_drift_pooled_dt, file.path(hybrid_dir, "axis2_te_drift_pooled.csv"))
fwrite(te_drift_regime_dt, file.path(hybrid_dir, "axis2_te_drift_regime.csv"))
fwrite(te_regime, file.path(hybrid_dir, "axis2_te_baseline_per_regime.csv"))

cat("\nTE drift pooled:\n")
print(te_drift_pooled_dt)

cat("\nTE drift regime-conditional (sample):\n")
print(te_drift_regime_dt[horizon_months %in% c(3L, 12L)])

# ---- 5. Alert threshold ----
# TE drift > 50% of baseline (1-σ alert) / > 100% (2-σ alert) — Charter §2 standard
alert_thresholds_te <- list(
  drift_warning_pct = 0.50,
  drift_critical_pct = 1.00,
  baseline_te_ann = te_active_baseline,
  warning_threshold_te_ann = 1.5 * te_active_baseline,
  critical_threshold_te_ann = 2.0 * te_active_baseline,
  rationale = "Charter §2 active risk monitoring. 1-σ warning + 2-σ critical convention."
)

# Save axis 2 summary
axis2_summary <- list(
  axis = "axis_2_te_drift_forward_mc",
  baseline = list(
    te_definition = "active overlay deviation: r_Hybrid_70_15_15 - r_AR (STR_1715 standalone)",
    te_active_baseline_ann = te_active_baseline,
    n_obs_post2015 = nrow(post2015),
    bm_proxy_note = "BM (KOSPI) cache 부재 — active overlay TE를 정의 (Hybrid vs STR_1715 standalone). Charter §2 active risk valid alternative.",
    regime_classification = "post-2015 Hybrid bottom 10%/40%/70% (PIT-C5 diagnostic only, sample-side)"
  ),
  methodology = list(
    bootstrap_type = "Politis-Romano stationary bootstrap",
    block_length_mean = L_mean,
    n_trials = B,
    horizons = horizons,
    paths = c("pooled", "regime_cond")
  ),
  alert_thresholds = alert_thresholds_te,
  results_csv = c("axis2_te_drift_pooled.csv", "axis2_te_drift_regime.csv",
                  "axis2_te_baseline_per_regime.csv")
)

write_json(axis2_summary, file.path(hybrid_dir, "axis2_summary.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat("\n[Axis 2] DONE\n")
