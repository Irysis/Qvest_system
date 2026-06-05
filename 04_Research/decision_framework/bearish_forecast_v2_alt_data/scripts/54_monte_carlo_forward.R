#==============================================================================
# 54_monte_carlo_forward.R — Cycle 25 Monte Carlo forward simulation
#
# Block bootstrap (block_size=12 for monthly returns) of historical (KOSPI, STR_1715).
# Simulate 1000 synthetic 60m (5y) futures.
# Apply 2m/-5%% V1aV3 strategy to each.
# Output: SR/MDD/CAGR distribution + percentile (5/25/50/75/95).
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xts);
  library(PerformanceAnalytics); library(ggplot2); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
PROD_DIR <- file.path(PROJECT_ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

# ── (1) Load historical (KOSPI + STR_1715) ──
bt <- readRDS(file.path(PROD_DIR, "04_backtest_results/bt_result_layer5_R05.rds"))
nav <- as.data.table(bt$nav)
nav[, anchor_date := as.Date(anchor_date)]
baseline <- nav[, .(anchor_date, realized_ym, nav_L5_V5)]
setorder(baseline, anchor_date)
baseline[, ret_str := c(nav_L5_V5[1] - 1, diff(nav_L5_V5) / head(nav_L5_V5, -1))]

bm <- as.data.table(read_parquet(
  file.path(WS, "outputs/02_targets/targets_full.parquet")))
bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y-%m")]
setorder(bm, Date)
eom <- bm[, .(close_eom = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)
eom[, ret_kospi := shift(close_eom, n = 1L, type = "lead") / close_eom - 1]
eom[, realized_ym := shift(ym, n = 1L, type = "lead")]

panel <- merge(baseline, eom[, .(realized_ym, ret_kospi)],
               by = "realized_ym", all.x = TRUE)
setorder(panel, anchor_date)
hist <- panel[!is.na(ret_kospi), .(ret_str, ret_kospi)]
N_hist <- nrow(hist)
cat(sprintf("Historical pool: %d months\n", N_hist))

# Joint returns (preserve correlation)
hist_mat <- as.matrix(hist)

# ── (2) Build hybrid function ──
compute_m <- function(ret_vec) {
  if (length(ret_vec) < 12) return(c(SR = NA, MDD = NA, CAGR = NA))
  xret <- xts::xts(ret_vec, order.by = seq(as.Date("2026-05-01"),
                                            by = "month",
                                            length.out = length(ret_vec)))
  ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
  c(SR = as.numeric(ann[3, 1]),
    MDD = -as.numeric(maxDrawdown(xret)),
    CAGR = as.numeric(ann[1, 1]))
}

build_hyb_path <- function(ret_str, ret_kospi, cost = 0.003) {
  N <- length(ret_str)
  kospi_log_cum <- cumsum(log(1 + replace(ret_kospi, is.na(ret_kospi), 0)))
  kospi_lvl <- exp(kospi_log_cum)
  kospi_2m_max <- pmax(kospi_lvl,
                       c(kospi_lvl[1], head(kospi_lvl, -1)))
  kospi_dd_2m <- kospi_lvl / kospi_2m_max - 1
  bear_trigger <- !is.na(kospi_dd_2m) & kospi_dd_2m <= -0.05
  bear_trigger_lag1 <- c(FALSE, head(bear_trigger, -1))
  dd_lag <- c(0, head(kospi_dd_2m, -1))

  trig_run <- integer(N)
  for (i in seq_len(N)) {
    if (bear_trigger_lag1[i]) {
      trig_run[i] <- ifelse(i > 1 && bear_trigger_lag1[i - 1],
                             trig_run[i - 1] + 1L, 1L)
    }
  }
  active <- bear_trigger_lag1 & trig_run <= 2
  pos_combo <- pmax(0.0, 0.7 - 3.0 * pmax(0, -(dd_lag + 0.10)))
  ret_active <- pos_combo * ret_kospi

  state <- ifelse(active, "BEAR", "BULL")
  state_change <- state != c("BULL", head(state, -1))

  ret_hyb <- ifelse(active, ret_active, ret_str)
  ret_hyb[state_change] <- ret_hyb[state_change] - cost
  ret_hyb
}

# ── (3) Block bootstrap simulation ──
sim_horizon <- 60  # 5 years
n_sims <- 1000
block_size <- 12

cat(sprintf("\nBlock bootstrap: %d sims × %d months (block_size=%d)\n",
            n_sims, sim_horizon, block_size))

set.seed(42)
sim_results <- matrix(NA_real_, n_sims, 6,
                       dimnames = list(NULL, c("SR_base", "MDD_base", "CAGR_base",
                                                 "SR_hyb", "MDD_hyb", "CAGR_hyb")))

for (s in seq_len(n_sims)) {
  # Block bootstrap: sample block starts
  n_blocks <- ceiling(sim_horizon / block_size)
  block_starts <- sample(seq_len(N_hist - block_size + 1), n_blocks, replace = TRUE)
  # Concatenate blocks
  idx <- unlist(lapply(block_starts, function(s) seq(s, s + block_size - 1)))
  idx <- idx[1:sim_horizon]
  sim_ret <- hist_mat[idx, ]

  # Compute baseline + hybrid
  m_b <- compute_m(sim_ret[, "ret_str"])
  ret_hyb <- build_hyb_path(sim_ret[, "ret_str"], sim_ret[, "ret_kospi"])
  m_h <- compute_m(ret_hyb)

  sim_results[s, ] <- c(m_b["SR"], m_b["MDD"], m_b["CAGR"],
                         m_h["SR"], m_h["MDD"], m_h["CAGR"])
}

# Remove NAs
sim_dt <- as.data.table(sim_results)
sim_dt <- sim_dt[!is.na(SR_base) & !is.na(SR_hyb)]
sim_dt[, dSR := SR_hyb - SR_base]
sim_dt[, dMDD := MDD_hyb - MDD_base]
sim_dt[, dCAGR := CAGR_hyb - CAGR_base]

# ── (4) Percentiles ──
cat(sprintf("\n━━━ Forward 5-year simulation distribution (n=%d) ━━━\n", nrow(sim_dt)))
pctiles <- c(0.05, 0.25, 0.50, 0.75, 0.95)
metrics <- c("SR_base", "SR_hyb", "MDD_base", "MDD_hyb",
              "CAGR_base", "CAGR_hyb", "dSR", "dMDD", "dCAGR")
cat(sprintf("%-12s %-10s %-10s %-10s %-10s %-10s\n",
            "Metric", "P5", "P25", "P50", "P75", "P95"))
for (m in metrics) {
  q <- quantile(sim_dt[[m]], pctiles, na.rm = TRUE)
  cat(sprintf("%-12s %+10.4f %+10.4f %+10.4f %+10.4f %+10.4f\n",
              m, q[1], q[2], q[3], q[4], q[5]))
}

# ── (5) Probability metrics ──
cat(sprintf("\n━━━ Probability (forward 5-year) ━━━\n"))
p_dsr_pos <- mean(sim_dt$dSR > 0)
p_dsr_strict <- mean(sim_dt$dSR >= 0.05)
p_dmdd_better <- mean(sim_dt$dMDD >= 0)
p_dcagr_pos <- mean(sim_dt$dCAGR > 0)
p_hyb_sr_2 <- mean(sim_dt$SR_hyb >= 2.0)
p_hyb_mdd_25 <- mean(sim_dt$MDD_hyb >= -0.25)
cat(sprintf("  P(dSR > 0):           %.1f%%%%\n", 100 * p_dsr_pos))
cat(sprintf("  P(dSR >= 0.05):       %.1f%%%%\n", 100 * p_dsr_strict))
cat(sprintf("  P(dMDD >= 0):         %.1f%%%%\n", 100 * p_dmdd_better))
cat(sprintf("  P(dCAGR > 0):         %.1f%%%%\n", 100 * p_dcagr_pos))
cat(sprintf("  P(Hybrid SR >= 2.0):  %.1f%%%%\n", 100 * p_hyb_sr_2))
cat(sprintf("  P(Hybrid MDD >= -25%%%%): %.1f%%%%\n", 100 * p_hyb_mdd_25))

# ── (6) Tail risk (worst 5%% / best 5%%) ──
cat(sprintf("\n━━━ Tail Risk Analysis ━━━\n"))
worst5 <- sim_dt[order(SR_hyb)][1:50]
best5 <- sim_dt[order(-SR_hyb)][1:50]
cat(sprintf("  Worst 5%%%% Hybrid SR:  mean %.4f / range [%.4f, %.4f]\n",
            mean(worst5$SR_hyb), min(worst5$SR_hyb), max(worst5$SR_hyb)))
cat(sprintf("  Worst 5%%%% Hybrid MDD: mean %.4f / worst %.4f\n",
            mean(worst5$MDD_hyb), min(worst5$MDD_hyb)))
cat(sprintf("  Best 5%%%% Hybrid SR:   mean %.4f / range [%.4f, %.4f]\n",
            mean(best5$SR_hyb), min(best5$SR_hyb), max(best5$SR_hyb)))

# ── (7) Save ──
out <- list(
  n_sims = nrow(sim_dt),
  sim_horizon_months = sim_horizon,
  block_size = block_size,
  percentiles = lapply(metrics, function(m) {
    q <- quantile(sim_dt[[m]], pctiles, na.rm = TRUE)
    list(metric = m, P5 = unname(q[1]), P25 = unname(q[2]),
          P50 = unname(q[3]), P75 = unname(q[4]), P95 = unname(q[5]))
  }),
  probabilities = list(
    P_dSR_pos = p_dsr_pos,
    P_dSR_strict = p_dsr_strict,
    P_dMDD_better = p_dmdd_better,
    P_dCAGR_pos = p_dcagr_pos,
    P_hyb_SR_2 = p_hyb_sr_2,
    P_hyb_MDD_25 = p_hyb_mdd_25),
  tail_risk = list(
    worst_5pct_mean_SR = mean(worst5$SR_hyb),
    worst_case_MDD = min(worst5$MDD_hyb),
    best_5pct_mean_SR = mean(best5$SR_hyb)),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "monte_carlo_forward.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/monte_carlo_forward.json\n", EVAL_DIR))

# Chart: dSR distribution
g1 <- ggplot(sim_dt, aes(x = dSR)) +
  geom_histogram(bins = 40, fill = "#073B4C", alpha = 0.7) +
  geom_vline(xintercept = 0, color = "red", linetype = "dashed") +
  geom_vline(xintercept = median(sim_dt$dSR), color = "#06D6A0", linewidth = 1) +
  labs(title = sprintf("MC Forward 5y simulation: ΔSR distribution (n=%d)", nrow(sim_dt)),
       subtitle = sprintf("P(dSR>0)=%.1f%%%% / median %+.3f / 95%%%% CI [%+.3f, %+.3f]",
                          100 * p_dsr_pos, median(sim_dt$dSR),
                          quantile(sim_dt$dSR, 0.025), quantile(sim_dt$dSR, 0.975)),
       x = "ΔSR (Hybrid - STR_1715)", y = "Count") +
  theme_minimal(base_size = 11)

# SR_base vs SR_hyb scatter
g2 <- ggplot(sim_dt, aes(x = SR_base, y = SR_hyb)) +
  geom_point(alpha = 0.4, color = "#073B4C") +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "red") +
  geom_hline(yintercept = 2.0, color = "orange", linetype = "dotted") +
  labs(title = "Hybrid SR vs Baseline SR (5y MC paths)",
       subtitle = sprintf("P(Hybrid SR >= 2.0) = %.1f%%%%", 100 * p_hyb_sr_2),
       x = "STR_1715 baseline SR (5y)", y = "Hybrid V1aV3 SR (5y)") +
  theme_minimal(base_size = 11)
g_comb <- patchwork::wrap_plots(g1, g2, ncol = 1)
ggsave(file.path(CHART_DIR, "32_monte_carlo.png"),
       plot = g_comb, width = 12, height = 9, dpi = 120)
cat(sprintf("[Chart 32] %s/32_monte_carlo.png\n", CHART_DIR))

cat("\n[DONE]\n")
