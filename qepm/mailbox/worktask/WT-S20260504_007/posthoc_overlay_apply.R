## Post-hoc Absorption Ratio overlay applied directly to STR_1715 PG2 actual returns
## Forge S0_baseline used static May-2026 snapshot — invalid baseline.
## This script: r_overlay,t = beta_{t-1} * r_STR1715,t + (1 - beta_{t-1}) * 0 (cash @ 0)
##              + 15bps * |Delta beta_t| (overlay-induced cash trading cost)
## Then compute CAGR / SR / MDD per variant and compare to L-274 baseline.

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(PerformanceAnalytics)
})

base_dir <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
wt_dir <- file.path(base_dir, "qepm/mailbox/worktask/WT-S20260504_007")
sa_dir <- file.path(base_dir, "stage_artifacts/WT_WT-S20260504_007")

# --- 1. Load STR_1715 PG2 monthly returns (ret_net) ---
str_path <- file.path(base_dir,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv")
ret_dt <- fread(str_path)
ret_dt[, date := as.Date(date)]
ret_dt <- ret_dt[, .(date, ret_str = ret_net, rf = risk_free_ret)]
setorder(ret_dt, date)
cat("[STR_1715] n_months=", nrow(ret_dt), " from ", as.character(min(ret_dt$date)),
    " to ", as.character(max(ret_dt$date)), "\n")

# --- 2. Load beta_t mapping ---
beta_path <- file.path(sa_dir, "beta_t_mapping.csv")
beta_dt <- fread(beta_path)
beta_dt[, Date := as.Date(Date)]
setorder(beta_dt, Date)
cat("[beta_t] n_months=", nrow(beta_dt), " from ", as.character(min(beta_dt$Date)),
    " to ", as.character(max(beta_dt$Date)), "\n")

# --- 3. Align dates ---
# beta_t_mapping uses month-start dates; STR_1715 uses month-start as well.
# Apply beta with 1-period lag (PIT: AR computed at t-1 close, applied at t).
beta_dt[, beta_linear_lag := shift(beta_linear, 1, fill = 1.0)]
beta_dt[, beta_threshold_lag := shift(beta_threshold, 1, fill = 1.0)]
beta_dt[, beta_sigmoid_lag := shift(beta_sigmoid, 1, fill = 1.0)]

# Merge by date (nearest month-start)
ret_dt[, ym := format(date, "%Y-%m")]
beta_dt[, ym := format(Date, "%Y-%m")]
mrg <- beta_dt[ret_dt, on = "ym"]
mrg <- mrg[!is.na(beta_linear_lag)]
cat("[merged] n_months=", nrow(mrg), "\n")

# --- 4. Apply overlay: r_overlay = beta_lag * r_str + (1-beta_lag) * 0 ---
# cash at 0 (conservative; rf available but ~0 in dataset)
# overlay-induced cost: 15bps * |Delta beta|
# (Delta beta means the underlying STR_1715 sleeve is scaled, not full repurchase)
mrg[, ret_S0 := ret_str]   # baseline = STR_1715 PG2 actual (no overlay)
mrg[, db_lin := abs(beta_linear_lag - shift(beta_linear_lag, 1, fill = 1.0))]
mrg[, db_thr := abs(beta_threshold_lag - shift(beta_threshold_lag, 1, fill = 1.0))]
mrg[, db_sig := abs(beta_sigmoid_lag - shift(beta_sigmoid_lag, 1, fill = 1.0))]

# overlay TO contribution = |Delta beta| (sleeve scaling = trade |db| * gross
# of underlying); cost = 15bps each side
COST_BPS <- 0.0015
mrg[, ret_S1 := beta_threshold_lag * ret_str - db_thr * COST_BPS]
mrg[, ret_S2 := beta_linear_lag    * ret_str - db_lin * COST_BPS]
mrg[, ret_S3 := beta_sigmoid_lag   * ret_str - db_sig * COST_BPS]

# --- 5. Compute metrics (PerformanceAnalytics standard) ---
xret <- xts::xts(as.matrix(mrg[, .(ret_S0, ret_S1, ret_S2, ret_S3)]),
                 order.by = mrg$date)

cat("\n=== POST-HOC AR OVERLAY ON STR_1715 PG2 ACTUAL RETURNS ===\n")
ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
print(ann)
mddv <- maxDrawdown(xret)
cat("\n--- MaxDrawdown ---\n"); print(mddv)
sortino <- SortinoRatio(xret, MAR = 0)
cat("\n--- Sortino ---\n"); print(sortino)
calmar <- CalmarRatio(xret)
cat("\n--- Calmar ---\n"); print(calmar)

# --- 6. Build summary table ---
build_summary <- function() {
  data.table(
    variant = c("S0_baseline_STR_1715_PG2_actual",
                "S1_threshold_step",
                "S2_linear_band",
                "S3_sigmoid_smooth"),
    CAGR = as.numeric(ann[1, ]),
    Vol = as.numeric(ann[2, ]),
    Sharpe = as.numeric(ann[3, ]),
    MDD = -as.numeric(mddv),
    Sortino = as.numeric(sortino),
    Calmar = as.numeric(calmar)
  )
}
summary_dt <- build_summary()
cat("\n=== SUMMARY ===\n")
print(summary_dt)

# Delta vs S0 baseline
delta_dt <- data.table(
  variant = summary_dt$variant[2:4],
  delta_CAGR_pp = (summary_dt$CAGR[2:4] - summary_dt$CAGR[1]) * 100,
  delta_MDD_pp = (summary_dt$MDD[2:4] - summary_dt$MDD[1]) * 100,
  delta_vol_pp = (summary_dt$Vol[2:4] - summary_dt$Vol[1]) * 100,
  vol_relative_pct = (summary_dt$Vol[2:4] / summary_dt$Vol[1] - 1) * 100,
  delta_Sharpe = summary_dt$Sharpe[2:4] - summary_dt$Sharpe[1]
)
cat("\n=== DELTA vs S0 baseline ===\n")
print(delta_dt)

# Save outputs
fwrite(summary_dt, file.path(wt_dir, "posthoc_summary.csv"))
fwrite(delta_dt, file.path(wt_dir, "posthoc_delta_vs_baseline.csv"))

# JSON summary
result <- list(
  task_id = "WT-S20260504_007",
  method = "posthoc_AR_overlay_on_STR_1715_PG2_actual",
  baseline = "STR_1715 PG2 monthly ret_net (L-274 source: 03_period_returns.csv)",
  n_months = nrow(mrg),
  cost_bps = 0.0015,
  cash_rate = 0,
  variants = lapply(seq_len(4), function(i) {
    list(
      variant = summary_dt$variant[i],
      CAGR = summary_dt$CAGR[i],
      Vol = summary_dt$Vol[i],
      Sharpe = summary_dt$Sharpe[i],
      MDD = summary_dt$MDD[i],
      Sortino = summary_dt$Sortino[i],
      Calmar = summary_dt$Calmar[i]
    )
  }),
  delta_vs_S0 = lapply(seq_len(3), function(i) {
    list(
      variant = delta_dt$variant[i],
      delta_CAGR_pp = delta_dt$delta_CAGR_pp[i],
      delta_MDD_pp = delta_dt$delta_MDD_pp[i],
      delta_vol_relative_pct = delta_dt$vol_relative_pct[i],
      delta_Sharpe = delta_dt$delta_Sharpe[i]
    )
  }),
  pass_gate_evaluation = list(
    cagr_floor_20pct = ifelse(summary_dt$CAGR[2:4] >= 0.20,
                              "PASS", "FAIL"),
    mdd_target_25pct = ifelse(summary_dt$MDD[2:4] >= -0.25,
                              "PASS", "FAIL"),
    mdd_3pp_improvement = ifelse(delta_dt$delta_MDD_pp >= 3,
                                 "PASS", "FAIL"),
    vol_20pct_improvement = ifelse(delta_dt$vol_relative_pct <= -20,
                                   "PASS", "FAIL"),
    sortino_1_0 = ifelse(summary_dt$Sortino[2:4] >= 1.0,
                         "PASS", "FAIL"),
    alpha_rank_corr_1_0 = "PASS_MATHEMATICAL_PROOF (rank preserved by scalar β)"
  ),
  alpha_preservation_audit = list(
    weight_rank_correlation = 1.0,
    relative_proportion_invariance = TRUE,
    selection_invariance = TRUE,
    m4_schedule_preserved = TRUE,
    note = "STR_1715 PG2 monthly return time series used directly; β_t scalar applied as cash overlay; alpha 100% preserved by construction"
  ),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
)

write_json(result,
  file.path(wt_dir, "posthoc_overlay_result.json"),
  pretty = TRUE, auto_unbox = TRUE)

cat("\n[saved] posthoc_summary.csv / posthoc_delta_vs_baseline.csv / posthoc_overlay_result.json\n")
