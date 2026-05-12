#==============================================================================
# WT-D20260508_010 Forge Step 2 — 4-ratio Hybrid combine + Backtest Result Contract v1.0
#
# Inputs:
#   - WT-P20260505_001/output/S3_Hybrid_70_15_15/03_period_returns.csv (256m baseline)
#   - stage_artifacts/WT-D20260508_010/forge/r14_duvol_sleeve_returns.csv (59m R14_DUVOL net)
#
# 4 ratios:
#   A: 70/15/15/0   (status quo, R14_DUVOL=0)
#   B: 63/13.5/13.5/10  (10% R14_DUVOL — Optimizer Primary)
#   C: 56/12/12/20      (20% R14_DUVOL — Alternate)
#   D: 49/10.5/10.5/30  (30% R14_DUVOL — Aggressive)
#
# Method:
#   - Align sleeve dates to Hybrid first-of-month convention (sleeve 2021-06-30 → Hybrid 2021-07-01)
#   - For 256m extended view: hold R14_DUVOL=0 for 197 pre-2021-07 months
#   - Combined return: w_hybrid * r_S3 + w_r14duvol * r_sleeve (renormalized when sleeve absent)
#   - Apples-to-apples joint window 2021-07-01 to 2026-05-01 (59m) for direct SR comparison
#   - Plus 256m extended view for full-period equity curve
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(PerformanceAnalytics); library(xts)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

WT_ID <- "WT-D20260508_010"
SA_DIR <- file.path("stage_artifacts", WT_ID)
FORGE_DIR <- file.path(SA_DIR, "forge")

cat("================================================================\n")
cat("[FORGE STEP 2] 4-ratio Hybrid combine\n")
cat("================================================================\n")

# Load Hybrid S3 baseline (256m)
hyb <- fread("qepm/mailbox/worktask/WT-P20260505_001/output/S3_Hybrid_70_15_15/03_period_returns.csv")
hyb[, date := as.Date(date)]
setkey(hyb, date)
cat("Hybrid S3 baseline: n_rows =", nrow(hyb), "/ range =",
    as.character(min(hyb$date)), "~", as.character(max(hyb$date)), "\n")

# Load R14_DUVOL sleeve (59m at end-of-month)
sleeve <- fread(file.path(FORGE_DIR, "r14_duvol_sleeve_returns.csv"))
sleeve[, date := as.Date(date)]
# Sleeve dates are sig_date_next (e.g., 2021-06-30 = June return realized at June 30 sig_date next)
# Hybrid dates are first-business-day of (return_month + 1). E.g., Hybrid 2021-08-02 = July 2021 return.
# Mapping logic: sleeve return earned in month M (sig_date M-end) ↔ Hybrid first-bday of (M+1)
# Use year-month bridge:
sleeve[, ret_ym := format(date, "%Y-%m")]  # month return earned
hyb[, hyb_ym_minus1 := format(date - 1, "%Y-%m")]  # Hybrid date - 1d gives prior month-end which == ret_ym for that row
# E.g., Hybrid 2021-08-02 -> -1d = 2021-08-01 -> "2021-08"... not correct
# Try: Hybrid ret reported at first-bday of (M+1), so subtracting one calendar month gets ret_ym
# Hybrid 2021-08-02 (return for July 2021) -> month-1 = July 2021
hyb[, hyb_return_month := {
  d <- as.Date(paste0(format(date, "%Y-%m"), "-01"))
  format(d - 1, "%Y-%m")
}]

cat("Sleeve: n_rows =", nrow(sleeve), "/ realized range =",
    as.character(min(sleeve$date)), "~", as.character(max(sleeve$date)), "\n")
cat("Sleeve return-month range:", min(sleeve$ret_ym), "~", max(sleeve$ret_ym), "\n")
cat("Hybrid return-month range:", min(hyb$hyb_return_month), "~", max(hyb$hyb_return_month), "\n")

# Verify alignment via year-month bridge
joint_yms <- intersect(sleeve$ret_ym, hyb$hyb_return_month)
cat("Joint return-months (Hybrid ∩ Sleeve):", length(joint_yms), "\n")
stopifnot(length(joint_yms) == nrow(sleeve))  # all 59 sleeve months align

# Build merged DT keyed by hyb_return_month (the month the return represents)
sleeve_aligned <- sleeve[, .(hyb_return_month = ret_ym, ret_r14 = ret_net,
                              to_r14 = turnover, n_h_r14 = n_holdings)]
mrg <- merge(hyb[, .(date, hyb_return_month, ret_h = ret_net, to_h = turnover, n_h = n_holdings)],
             sleeve_aligned, by = "hyb_return_month", all.x = TRUE)
setkey(mrg, date)
mrg[is.na(ret_r14), ret_r14 := 0]
mrg[is.na(to_r14), to_r14 := 0]
mrg[is.na(n_h_r14), n_h_r14 := 0]
mrg[, has_r14 := hyb_return_month %in% sleeve_aligned$hyb_return_month]
cat("Merged: n_rows =", nrow(mrg), "/ has_r14 months =", sum(mrg$has_r14), "\n")

# Define 4 ratios (sum w_str + w_tsmom + w_kr + w_r14 = 1)
# When w_r14=0 we use exact A/B/C/D split. When R14_DUVOL out-of-period, renormalize Hybrid to fill 1.0.
ratios <- list(
  A = c(w_hybrid = 1.00, w_r14 = 0.00),  # 70/15/15/0
  B = c(w_hybrid = 0.90, w_r14 = 0.10),  # 63/13.5/13.5/10
  C = c(w_hybrid = 0.80, w_r14 = 0.20),  # 56/12/12/20
  D = c(w_hybrid = 0.70, w_r14 = 0.30)   # 49/10.5/10.5/30
)

# Compute combined returns + KOSPI200 benchmark
# Load KOSPI200 monthly benchmark from Hybrid output
bm <- fread("qepm/mailbox/worktask/WT-P20260505_001/output/S3_Hybrid_70_15_15/05_benchmark_returns.csv")
bm[, date := as.Date(date)]
setkey(bm, date)

# Storage for results
results_per_ratio <- list()
joint_window_metrics <- list()

for (rname in names(ratios)) {
  w <- ratios[[rname]]
  w_h <- w["w_hybrid"]; w_r <- w["w_r14"]

  # Combined return: outside R14_DUVOL window, renormalize Hybrid to 1.0
  mrg[, ret_combo := ifelse(has_r14,
                              w_h * ret_h + w_r * ret_r14,
                              ret_h)]
  # Combined turnover (proxy): w_h * to_h + w_r * to_r14 + |w_r - w_r_prev| at activation
  mrg[, to_combo := ifelse(has_r14, w_h * to_h + w_r * to_r14, to_h)]

  res <- data.table(
    date = mrg$date,
    ret_h = mrg$ret_h,
    ret_r14 = mrg$ret_r14,
    has_r14 = mrg$has_r14,
    ret_combo = mrg$ret_combo,
    to_combo = mrg$to_combo
  )
  results_per_ratio[[rname]] <- res

  # Joint window (R14_DUVOL active 59m): apples-to-apples
  jw <- res[has_r14 == TRUE]
  jw_xts <- xts(jw$ret_combo, order.by = jw$date)
  sr_jw <- as.numeric(SharpeRatio.annualized(jw_xts, scale = 12))
  cagr_jw <- as.numeric(Return.annualized(jw_xts, scale = 12))
  mdd_jw <- as.numeric(maxDrawdown(jw_xts))
  vol_jw <- as.numeric(sd.annualized(jw_xts, scale = 12))
  to_jw_mean <- mean(jw$to_combo)

  # Full window 256m (with R14_DUVOL=0 prior to 2021-07)
  fw_xts <- xts(res$ret_combo, order.by = res$date)
  sr_fw <- as.numeric(SharpeRatio.annualized(fw_xts, scale = 12))
  cagr_fw <- as.numeric(Return.annualized(fw_xts, scale = 12))
  mdd_fw <- as.numeric(maxDrawdown(fw_xts))
  vol_fw <- as.numeric(sd.annualized(fw_xts, scale = 12))
  sortino_fw <- as.numeric(SortinoRatio(fw_xts) * sqrt(12))
  calmar_fw <- cagr_fw / abs(mdd_fw)

  # vs KOSPI200 BM (joint window)
  bm_jw <- merge(jw[, .(date)], bm[, .(date, benchmark_ret)], by = "date")
  active <- jw$ret_combo - bm_jw$benchmark_ret
  te_ann <- sd(active, na.rm = TRUE) * sqrt(12)
  ar_ann <- mean(active, na.rm = TRUE) * 12
  ir_ann <- ar_ann / te_ann

  joint_window_metrics[[rname]] <- list(
    ratio = rname,
    composition = sprintf("STR_1715_AR=%.0f%% / TSMOM=%.0f%% / KR_10y=%.0f%% / R14_DUVOL=%.0f%%",
                          w_h * 70, w_h * 15, w_h * 15, w_r * 100),
    joint_window_59m = list(
      sr_a = round(sr_jw, 4),
      cagr = round(cagr_jw, 4),
      mdd = round(mdd_jw, 4),
      vol_ann = round(vol_jw, 4),
      to_avg_per_period = round(to_jw_mean, 4),
      n_periods = nrow(jw),
      ar_vs_kospi200 = round(ar_ann, 4),
      te_vs_kospi200 = round(te_ann, 4),
      ir_vs_kospi200 = round(ir_ann, 4)
    ),
    full_window_256m = list(
      sr_a = round(sr_fw, 4),
      cagr = round(cagr_fw, 4),
      mdd = round(mdd_fw, 4),
      vol_ann = round(vol_fw, 4),
      sortino = round(sortino_fw, 4),
      calmar = round(calmar_fw, 4),
      n_periods = nrow(res)
    )
  )

  cat(sprintf("\n[%s] %s\n", rname,
              joint_window_metrics[[rname]]$composition))
  cat(sprintf("  Joint 59m: SR=%.4f  CAGR=%.4f  MDD=%.4f  vol=%.4f  TO=%.4f  IR=%.4f\n",
              sr_jw, cagr_jw, mdd_jw, vol_jw, to_jw_mean, ir_ann))
  cat(sprintf("  Full 256m: SR=%.4f  CAGR=%.4f  MDD=%.4f  vol=%.4f  Sortino=%.4f  Calmar=%.4f\n",
              sr_fw, cagr_fw, mdd_fw, vol_fw, sortino_fw, calmar_fw))
}

# Save consolidated comparison table
cmp_dt <- rbindlist(lapply(joint_window_metrics, function(x) {
  data.table(
    ratio = x$ratio,
    composition = x$composition,
    SR_joint_59m = x$joint_window_59m$sr_a,
    CAGR_joint_59m = x$joint_window_59m$cagr,
    MDD_joint_59m = x$joint_window_59m$mdd,
    Vol_joint_59m = x$joint_window_59m$vol_ann,
    TO_joint_59m = x$joint_window_59m$to_avg_per_period,
    IR_joint_59m = x$joint_window_59m$ir_vs_kospi200,
    TE_joint_59m = x$joint_window_59m$te_vs_kospi200,
    SR_full_256m = x$full_window_256m$sr_a,
    CAGR_full_256m = x$full_window_256m$cagr,
    MDD_full_256m = x$full_window_256m$mdd,
    Vol_full_256m = x$full_window_256m$vol_ann,
    Sortino_full_256m = x$full_window_256m$sortino,
    Calmar_full_256m = x$full_window_256m$calmar
  )
}), fill = TRUE)
fwrite(cmp_dt, file.path(FORGE_DIR, "four_ratio_comparison.csv"))
write_json(joint_window_metrics, file.path(FORGE_DIR, "four_ratio_metrics.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("\n[saved] forge/four_ratio_comparison.csv\n")
cat("[saved] forge/four_ratio_metrics.json\n")

# Save per-ratio combined returns + holdings + nav
for (rname in names(results_per_ratio)) {
  res <- results_per_ratio[[rname]]
  out_dir <- file.path(FORGE_DIR, sprintf("%s_%dpct",
    if (rname == "A") "A" else if (rname == "B") "B" else if (rname == "C") "C" else "D",
    as.integer(ratios[[rname]]["w_r14"] * 100)))
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  # period_returns.csv (Backtest Contract v1.0 schema)
  pr <- data.table(
    run_id = sprintf("WT-D20260508_010_%s_%dpct_forge", rname, as.integer(ratios[[rname]]["w_r14"] * 100)),
    strategy_id = sprintf("hybrid_4sleeve_R14_DUVOL_%dpct", as.integer(ratios[[rname]]["w_r14"] * 100)),
    date = res$date,
    frequency = "monthly",
    ret_gross = NA_real_,
    ret_net = res$ret_combo,
    risk_free_ret = 0,
    excess_ret_net = res$ret_combo,
    turnover = res$to_combo,
    cost_ret = NA_real_,
    cash_weight = NA_real_,
    leverage = 1,
    n_holdings = NA_integer_
  )
  fwrite(pr, file.path(out_dir, "03_period_returns.csv"))
  cat(sprintf("  [%s] saved 03_period_returns.csv (n=%d)\n", rname, nrow(pr)))

  # NAV
  pr_xts <- xts(pr$ret_net, order.by = pr$date)
  nav_xts <- cumprod(1 + pr_xts)
  dd_xts <- nav_xts / cummax(nav_xts) - 1
  nav <- data.table(
    run_id = pr$run_id[1],
    strategy_id = pr$strategy_id[1],
    date = index(nav_xts),
    nav_gross = NA_real_,
    nav_net = as.numeric(nav_xts),
    cash_weight = NA_real_,
    gross_exposure = 1,
    net_exposure = 1,
    leverage = 1,
    cum_cost = NA_real_,
    drawdown_net = as.numeric(dd_xts),
    is_rebalance_date = TRUE
  )
  fwrite(nav, file.path(out_dir, "02_nav.csv"))
}

cat("\n[FORGE STEP 2] DONE — 4-ratio comparison + per-ratio period_returns/nav saved\n")
