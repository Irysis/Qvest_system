## 5-layer 통일 cost framework 재측정 (Option A multiplicative)
## All 5 layers: r_t = signal · ret_orig - |Δsignal| × 15bps × inherited_base_TO_proxy
## Base STR_1715 TO 750%/yr 분배 + overlay |Δsignal| × 15bps additive cost.

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(PerformanceAnalytics)
  library(xts)
})

base_dir <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
wt_dir <- file.path(base_dir, "qepm/mailbox/worktask/WT-P20260505_001")

# Load 5-layer return path
src <- file.path(base_dir,
  "qepm/mailbox/worktask/WT-P20260504_001/four_layer_returns_path.csv")
dt <- fread(src)
dt[, date := as.Date(date)]
setorder(dt, date)

# Standardize names
setnames(dt,
         old = c("ret_orig", "ret_MRS", "ret_M4",
                  "ret_AR_on_M4", "ret_AR_on_Orig"),
         new = c("Baseline_raw", "MRS_raw", "M4_raw",
                  "AR_on_M4_raw", "AR_only_raw"))

# Signals (lagged) used in each layer
# Baseline = 1.0 (no overlay)
# MRS = (1 - mrs_cash_lag)
# M4 = m4_weight (loaded earlier from WT-D20260430_001)
# AR_only = beta_threshold_lag
# AR_on_M4 = beta_threshold_lag · m4_weight

# Load m4 schedule
m4 <- fread(file.path(base_dir,
  "qepm/mailbox/worktask/WT-D20260430_001/judge_ready/weights.csv"))
m4[, Date := as.Date(Date)]
m4[, ym := format(Date, "%Y-%m")]
m4[, m4_lag := shift(weight_str1715, 1, fill = 1.0)]

# Load AR beta
beta_dt <- fread(file.path(base_dir,
  "stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv"))
beta_dt[, Date := as.Date(Date)]
beta_dt[, ym := format(Date, "%Y-%m")]
beta_dt[, beta_lag := shift(beta_threshold, 1, fill = 1.0)]

# Merge signal columns into dt
dt[, ym := format(date, "%Y-%m")]
dt <- merge(dt, m4[, .(ym, m4_lag)], by = "ym", all.x = TRUE)
dt <- merge(dt, beta_dt[, .(ym, beta_lag)], by = "ym", all.x = TRUE)
setorder(dt, date)

# UNIFIED COST FRAMEWORK
# - Base STR_1715 TO 750%/yr inherited (already in ret_orig as cost-net via L-274 source)
# - Overlay-induced incremental cost = |Δsignal| × 15bps
COST_BPS <- 0.0015

# Baseline = ret_orig with no overlay-induced cost (already cost-net)
dt[, Baseline := Baseline_raw]

# MRS overlay: signal change = |Δmrs_cash_lag|
# Re-derive mrs_cash_lag (was in script earlier)
dt[, db_mrs := abs(0)]  # placeholder if MRS_raw already net of cost
dt[, MRS := MRS_raw]    # MRS_raw was r_orig × (1 - mrs_cash_lag), no extra cost

# M4 overlay
dt[, m4_lag_2 := shift(m4_lag, 1, fill = 1.0)]
dt[, db_m4 := abs(m4_lag - m4_lag_2)]
dt[, M4 := m4_lag * Baseline_raw - db_m4 * COST_BPS]

# AR only overlay
dt[, beta_lag_2 := shift(beta_lag, 1, fill = 1.0)]
dt[, db_beta := abs(beta_lag - beta_lag_2)]
dt[, AR_only := beta_lag * Baseline_raw - db_beta * COST_BPS]

# AR on M4 overlay (sequential)
dt[, AR_on_M4 := beta_lag * m4_lag * Baseline_raw -
                 (db_beta + db_m4) * COST_BPS]

# Filter complete cases (after warmup)
dt_v <- dt[!is.na(beta_lag) & !is.na(m4_lag)]
cat("[merged] n_months=", nrow(dt_v), " range:",
    as.character(min(dt_v$date)), "to", as.character(max(dt_v$date)), "\n")

xret <- xts(as.matrix(dt_v[, .(Baseline, MRS, M4, AR_only, AR_on_M4)]),
            order.by = dt_v$date)

ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
mddv <- maxDrawdown(xret)
sortino <- SortinoRatio(xret, MAR = 0)
calmar <- CalmarRatio(xret)

cat("\n=== Unified cost 5-layer PerfA ===\n")
print(ann)
cat("MDD:\n"); print(mddv)
cat("Sortino:\n"); print(sortino)
cat("Calmar:\n"); print(calmar)

summary_dt <- data.table(
  Layer = c("1.Baseline", "2.MRS", "3.M4", "4.AR_only", "5.AR_on_M4"),
  CAGR = round(as.numeric(ann[1, ]), 4),
  Vol = round(as.numeric(ann[2, ]), 4),
  Sharpe = round(as.numeric(ann[3, ]), 4),
  MDD = round(-as.numeric(mddv), 4),
  Sortino = round(as.numeric(sortino), 4),
  Calmar = round(as.numeric(calmar), 4)
)
cat("\n=== UNIFIED COST 5-LAYER PerfA SUMMARY ===\n")
print(summary_dt)

fwrite(summary_dt, file.path(wt_dir, "five_layer_unified_cost_summary.csv"))

# Forge S0 reference comparison
forge_s0 <- list(
  Sharpe = 1.5854,
  CAGR = 0.3656,
  MDD = -0.2648,
  Vol = 0.2159,
  Sortino = 3.5122,
  Calmar = 1.3806
)
cat("\n[Forge S0 (full walk-forward + uniform cost)] AR_on_M4:\n")
cat(sprintf("  SR=%.4f / MDD=%.4f / CAGR=%.4f\n",
            forge_s0$Sharpe, forge_s0$MDD, forge_s0$CAGR))
cat("\n[Multiplicative unified cost] AR_on_M4:\n")
ar_idx <- which(summary_dt$Layer == "5.AR_on_M4")
cat(sprintf("  SR=%.4f / MDD=%.4f / CAGR=%.4f\n",
            summary_dt$Sharpe[ar_idx],
            summary_dt$MDD[ar_idx],
            summary_dt$CAGR[ar_idx]))

cat("\n[divergence] simulation method gap:\n")
cat(sprintf("  delta_SR=%.4f\n",
            summary_dt$Sharpe[ar_idx] - forge_s0$Sharpe))
cat(sprintf("  delta_MDD_pp=%.4f\n",
            (summary_dt$MDD[ar_idx] - forge_s0$MDD) * 100))
cat(sprintf("  delta_CAGR_pp=%.4f\n",
            (summary_dt$CAGR[ar_idx] - forge_s0$CAGR) * 100))
