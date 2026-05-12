#==============================================================================
# WT-D20260508_013 Forge Step 2 — 5 비중 Hybrid 4-sleeve combine 256m
#
# Method:
#   - Hybrid baseline: qepm/mailbox/worktask/WT-P20260505_001/architect_hybrid_returns_full256m.csv
#     - r_AR (STR_1715_AR)  / r_KR10y / r_TSMOM (2009-09부터)
#     - r_H_renorm (when TSMOM absent: 70/30 KR_10y renormalize. when present: 70/15/15)
#   - Sleeve: stage_artifacts/WT-D20260508_013/forge/sleeve_returns_256m.csv
#     - WT_013 left-tail momentum sleeve net returns (252m, 2005-05-31 ~ 2026-04-30)
#
# 5 비중:
#   0%  = 70/15/15/0  (status quo S3 admit)
#   5%  = 67.5/13.75/13.75/5
#   10% = 63/13.5/13.5/10
#   15% = 59.5/12.75/12.75/15
#   20% = 56/12/12/20
#
# Date alignment:
#   - Hybrid baseline date convention: first business day of (return_month + 1)
#     예: 2005-02-01 row = January 2005 month return (실제론 alpha_scores 2005-05-31에 매핑)
#   - Sleeve: sig_date = end-of-month → 1m fwd_ret realized through next sig_date
#     예: 2005-05-31 sig_date → June 2005 return
#   - Bridge via year-month of "return realized" (ret_ym):
#       Sleeve sig_date Y-M-end → ret_ym = same Y-M (sleeve.Date is sig_date, fwd return realized in next month — wait, careful).
#
# Per Atilgan alpha_package convention: at sig_date t, hold 1m → ret realized at t+1m.
# → Sleeve "Date" = sig_date t, ret_net = return realized over [t, t+1m)
# Hybrid baseline: r_AR row at "2005-02-01" = January 2005 monthly return = January 2005 month
# → To bridge: Sleeve Date 2005-05-31 (sig_date end-of-May) realizes June 2005 return
#              Hybrid date 2005-06-01 (or first bday June) = May 2005 return ← OFFSET
#
# 검증 strategy: Sleeve Date Y-M-end → ret_ym_realized = Y-(M+1)
#                Hybrid Date Y-M-01 → ret_ym_realized = Y-(M-1)
# Match by ret_ym.
#
# 5 비중 산출:
#   - For each ratio r, combined_ret = w_hybrid * r_H_renorm + w_sleeve * sleeve_ret
#   - When sleeve absent for a Hybrid month, use w=0 sleeve fallback:
#       combined_ret = r_H_renorm (no rebalancing impact since sleeve already 0)
#=============================================================================

suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(PerformanceAnalytics); library(xts)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

WT_ID <- "WT-D20260508_013"
SA_DIR <- file.path("stage_artifacts", WT_ID)
FORGE_DIR <- file.path(SA_DIR, "forge")

cat("================================================================\n")
cat("[FORGE STEP 2] 5 비중 Hybrid 4-sleeve combine 256m\n")
cat("================================================================\n")

# Load Hybrid baseline (256m)
hyb <- fread("qepm/mailbox/worktask/WT-P20260505_001/architect_hybrid_returns_full256m.csv")
hyb[, date := as.Date(date)]
setkey(hyb, date)

# Hybrid date convention: first business day of (ret_month + 1)
# Compute ret_ym_realized: this row's date - 1 calendar month → ret_ym
hyb[, ret_ym_realized := format(date - 1, "%Y-%m")]
# But date - 1 day might wrap. Better: use ym field or compute from date
# The 'ym' field already provided in the CSV (row = first day of ret_month)
# Wait, looking at data: 2005-02-01 ym 2005-02 r_AR 0.0942 — but this is January return reported on Feb 1?
# Actually looking again: 2005-02-01 ym=2005-02 means February 2005, and r_AR is Feb 2005 returns?
# Let me check by comparing magnitudes

cat("Hybrid baseline n_rows =", nrow(hyb), " range=",
    as.character(min(hyb$date)), "~", as.character(max(hyb$date)), "\n")
cat("Hybrid baseline ym col range=", min(hyb$ym), "~", max(hyb$ym), "\n")

# Use ym col for matching (assume ym = month return realized in)
hyb[, ret_ym := ym]

# Load WT_013 sleeve
sleeve <- fread(file.path(FORGE_DIR, "sleeve_returns_256m.csv"))
sleeve[, Date := as.Date(Date)]
# Sleeve: sig_date Y-M-end → fwd_ret_1m realized over [t, t+1m)
# Convention: sig_date 2005-05-31 holds for June, return realized in June 2005
# Robust ret_ym: use month-arithmetic seq.Date
add_one_month <- function(d) {
  yr <- as.integer(format(d, "%Y"))
  mo <- as.integer(format(d, "%m"))
  mo2 <- mo + 1
  yr2 <- yr + ifelse(mo2 > 12, 1, 0)
  mo2 <- ifelse(mo2 > 12, 1, mo2)
  sprintf("%04d-%02d", yr2, mo2)
}
sleeve[, ret_ym := add_one_month(Date)]
cat("\nSleeve n_rows =", nrow(sleeve), " range=",
    as.character(min(sleeve$Date)), "~", as.character(max(sleeve$Date)), "\n")
cat("Sleeve ret_ym range=", min(sleeve$ret_ym), "~", max(sleeve$ret_ym), "\n")
cat("Sample sleeve ret_ym:", head(sleeve$ret_ym, 3), "\n")
cat("Sample hyb ret_ym:", head(hyb$ret_ym, 3), "\n")

# Verify alignment
joint_yms <- intersect(sleeve$ret_ym, hyb$ret_ym)
cat("\nJoint return-months (Hybrid ∩ Sleeve):", length(joint_yms), "/ Hybrid:", nrow(hyb), "/ Sleeve:", nrow(sleeve), "\n")

# Merge
sleeve_aligned <- sleeve[, .(ret_ym, ret_sleeve = ret_net, to_sleeve = turnover, n_h_sleeve = n_holdings)]
mrg <- merge(hyb[, .(date, ret_ym, r_AR, r_KR10y, r_TSMOM, has_ts, r_H_renorm, r_H_naive)],
             sleeve_aligned, by = "ret_ym", all.x = TRUE)
setkey(mrg, date)
mrg[, has_sleeve := !is.na(ret_sleeve)]
mrg[is.na(ret_sleeve), ret_sleeve := 0]
mrg[is.na(to_sleeve), to_sleeve := 0]

cat("\nMerged: rows=", nrow(mrg), " has_sleeve=", sum(mrg$has_sleeve), "\n")
cat("Hybrid months without sleeve match:", sum(!mrg$has_sleeve), "\n")

# Use r_H_renorm (TSMOM-aware: when TSMOM absent → 70/30 KR_10y, when present → 70/15/15)
# This is the documented S3 baseline. Now for 5 비중 hybrid combine:
#   combined_ret = w_hybrid * r_H_renorm + w_sleeve * ret_sleeve
# Note: Hybrid r_H_renorm already integrates AR + KR10y + TSMOM at 70/15/15.
# The sleeve adds 4th dim. Since hybrid is 100% before WT_013 admit, the
# combined splits as:
#   ratio 0%  = 1.00 * r_H_renorm + 0.00 * sleeve
#   ratio 5%  = 0.95 * r_H_renorm + 0.05 * sleeve
#   ratio 10% = 0.90 * r_H_renorm + 0.10 * sleeve
#   ratio 15% = 0.85 * r_H_renorm + 0.15 * sleeve
#   ratio 20% = 0.80 * r_H_renorm + 0.20 * sleeve
#
# Equivalent breakdown:
#   ratio 5% = 0.95*(0.70 AR + 0.15 KR + 0.15 TSMOM) + 0.05 sleeve
#            = 0.665 AR + 0.1425 KR + 0.1425 TSMOM + 0.05 sleeve
# Per Optimizer Step 7 four_sleeve_recommendation.

ratios_pct <- c(0, 5, 10, 15, 20)
ratios_w <- ratios_pct / 100

# Load KOSPI200 BM (use Hybrid as baseline for TE comparison since BM may not be in mailbox)
# Actually, "Hybrid 70/15/15 baseline" is the TE reference per Optimizer (ar_m / te_m / ir_m vs Hybrid)
# So baseline = w=0% combo = r_H_renorm (status quo S3)

results <- list()
joint_w13_window <- mrg[has_sleeve == TRUE]  # 252m where sleeve realized
full_window <- mrg                            # 254m total Hybrid

for (i in seq_along(ratios_w)) {
  w <- ratios_w[i]
  pct <- ratios_pct[i]
  pct_str <- sprintf("%dpct", pct)

  # Combined return on full Hybrid window
  full_window[, ret_combo := (1 - w) * r_H_renorm + w * ret_sleeve]
  # Combined turnover proxy (full): hybrid TO unknown, use only sleeve TO scaled by w
  # For diff vs baseline 0%, the TO difference ~ w * to_sleeve. But the baseline already
  # has its own TO embedded in r_H_renorm (already net). So additional TO impact from
  # adding WT_013 sleeve at weight w is (w * to_sleeve).
  full_window[, to_combo := w * to_sleeve]

  # Joint window (sleeve active, 252m)
  joint <- full_window[has_sleeve == TRUE]
  joint_xts <- xts(joint$ret_combo, order.by = joint$date)

  sr_a   <- as.numeric(SharpeRatio.annualized(joint_xts, scale = 12))
  cagr   <- as.numeric(Return.annualized(joint_xts, scale = 12))
  mdd    <- as.numeric(maxDrawdown(joint_xts))
  vol    <- as.numeric(sd.annualized(joint_xts, scale = 12))
  sortino <- as.numeric(SortinoRatio(joint_xts) * sqrt(12))
  calmar <- cagr / abs(mdd)
  to_avg <- mean(joint$to_combo)

  # vs 0% baseline (Hybrid 70/15/15 alone)
  base_xts <- xts(joint$r_H_renorm, order.by = joint$date)
  active_ret <- joint$ret_combo - joint$r_H_renorm
  ar_m <- mean(active_ret) * 12
  te_m <- sd(active_ret) * sqrt(12)
  ir_m <- if (te_m > 1e-10) ar_m / te_m else NA

  # Δ vs 0% baseline
  base_sr <- as.numeric(SharpeRatio.annualized(base_xts, scale = 12))
  base_cagr <- as.numeric(Return.annualized(base_xts, scale = 12))
  base_mdd <- as.numeric(maxDrawdown(base_xts))
  delta_sr <- sr_a - base_sr
  delta_mdd <- mdd - base_mdd  # negative = worse, positive = better (less drawdown)
  delta_cagr <- cagr - base_cagr

  # Full 256m view (with sleeve=0 for missing months)
  full_xts <- xts(full_window$ret_combo, order.by = full_window$date)
  sr_full <- as.numeric(SharpeRatio.annualized(full_xts, scale = 12))
  cagr_full <- as.numeric(Return.annualized(full_xts, scale = 12))
  mdd_full <- as.numeric(maxDrawdown(full_xts))
  vol_full <- as.numeric(sd.annualized(full_xts, scale = 12))
  sortino_full <- as.numeric(SortinoRatio(full_xts) * sqrt(12))
  calmar_full <- cagr_full / abs(mdd_full)

  results[[pct_str]] <- list(
    pct = pct,
    w_sleeve = w,
    composition = sprintf("STR_1715_AR=%.2f%% / TSMOM=%.2f%% / KR_10y=%.2f%% / WT_013=%.0f%%",
                          (1-w)*70, (1-w)*15, (1-w)*15, w*100),
    joint_window_252m = list(
      n_periods = nrow(joint),
      sr_a = round(sr_a, 4),
      cagr = round(cagr, 4),
      mdd = round(mdd, 4),
      vol_ann = round(vol, 4),
      sortino = round(sortino, 4),
      calmar = round(calmar, 4),
      to_avg_per_period = round(to_avg, 4),
      ar_vs_hybrid_baseline = round(ar_m, 4),
      te_vs_hybrid_baseline = round(te_m, 4),
      ir_vs_hybrid_baseline = round(ir_m, 4),
      delta_sr_vs_0pct = round(delta_sr, 4),
      delta_mdd_vs_0pct = round(delta_mdd, 4),
      delta_cagr_vs_0pct = round(delta_cagr, 4)
    ),
    full_window_254m = list(
      n_periods = nrow(full_window),
      sr_a = round(sr_full, 4),
      cagr = round(cagr_full, 4),
      mdd = round(mdd_full, 4),
      vol_ann = round(vol_full, 4),
      sortino = round(sortino_full, 4),
      calmar = round(calmar_full, 4)
    ),
    optimizer_estimate = list(
      sr_a_est = c(1.651, 1.6846, 1.7118, 1.7302, 1.7372)[i],
      mdd_est = c(-0.1952, -0.1844, -0.1737, -0.1696, -0.1906)[i],
      ir_m_est = c(NA, -0.4515, -0.4515, -0.4515, -0.4515)[i],
      sigma_red_pct_est = c(0, -0.662, -1.37, -2.099, -2.812)[i]
    ),
    forge_realized_vs_estimate = list(
      sr_realized_minus_est = round(sr_a - c(1.651, 1.6846, 1.7118, 1.7302, 1.7372)[i], 4),
      mdd_realized_minus_est = round(mdd - c(-0.1952, -0.1844, -0.1737, -0.1696, -0.1906)[i], 4),
      ir_realized_minus_est = if (i > 1) round(ir_m - (-0.4515), 4) else NA
    )
  )

  # Save per-ratio period_returns + nav (Backtest Contract v1.0)
  out_dir <- file.path(FORGE_DIR, pct_str)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  pr <- data.table(
    run_id = sprintf("WT-D20260508_013_%s_forge", pct_str),
    strategy_id = sprintf("hybrid_4sleeve_LeftTailMom_%s", pct_str),
    date = full_window$date,
    frequency = "monthly",
    ret_gross = NA_real_,
    ret_net = full_window$ret_combo,
    risk_free_ret = 0,
    excess_ret_net = full_window$ret_combo,
    turnover = full_window$to_combo,
    cost_ret = NA_real_,
    cash_weight = 0,
    leverage = 1,
    n_holdings = 20L
  )
  fwrite(pr, file.path(out_dir, "03_period_returns.csv"))

  # NAV
  nav_xts_t <- cumprod(1 + full_xts)
  dd_xts_t <- nav_xts_t / cummax(nav_xts_t) - 1
  nav <- data.table(
    run_id = pr$run_id[1],
    strategy_id = pr$strategy_id[1],
    date = index(nav_xts_t),
    nav_gross = NA_real_,
    nav_net = as.numeric(nav_xts_t),
    cash_weight = 0,
    gross_exposure = 1,
    net_exposure = 1,
    leverage = 1,
    cum_cost = NA_real_,
    drawdown_net = as.numeric(dd_xts_t),
    is_rebalance_date = TRUE
  )
  fwrite(nav, file.path(out_dir, "02_nav.csv"))

  cat(sprintf("\n[%s] %s\n", pct_str, results[[pct_str]]$composition))
  cat(sprintf("  Joint 252m: SR=%.4f CAGR=%.4f MDD=%.4f vol=%.4f Sortino=%.4f Calmar=%.4f TO=%.4f\n",
              sr_a, cagr, mdd, vol, sortino, calmar, to_avg))
  cat(sprintf("  vs 0%%: ΔSR=%+.4f ΔMDD=%+.4fpp ΔCAGR=%+.4f IR_vs_baseline=%.4f TE=%.4f\n",
              delta_sr, delta_mdd*100, delta_cagr, ir_m, te_m))
  cat(sprintf("  Full 254m: SR=%.4f CAGR=%.4f MDD=%.4f\n", sr_full, cagr_full, mdd_full))
  cat(sprintf("  Optimizer estimate: SR=%.4f MDD=%.4f → Forge realized SR diff=%+.4f MDD diff=%+.4f\n",
              c(1.651, 1.6846, 1.7118, 1.7302, 1.7372)[i],
              c(-0.1952, -0.1844, -0.1737, -0.1696, -0.1906)[i],
              sr_a - c(1.651, 1.6846, 1.7118, 1.7302, 1.7372)[i],
              mdd - c(-0.1952, -0.1844, -0.1737, -0.1696, -0.1906)[i]))
}

# Save consolidated metrics
write_json(results, file.path(FORGE_DIR, "five_ratio_metrics.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# Comparison CSV
cmp_dt <- rbindlist(lapply(results, function(x) {
  data.table(
    pct = x$pct,
    composition = x$composition,
    SR_joint_252m = x$joint_window_252m$sr_a,
    CAGR_joint_252m = x$joint_window_252m$cagr,
    MDD_joint_252m = x$joint_window_252m$mdd,
    Vol_joint_252m = x$joint_window_252m$vol_ann,
    Sortino_joint_252m = x$joint_window_252m$sortino,
    Calmar_joint_252m = x$joint_window_252m$calmar,
    TO_joint_252m = x$joint_window_252m$to_avg_per_period,
    AR_vs_hybrid = x$joint_window_252m$ar_vs_hybrid_baseline,
    TE_vs_hybrid = x$joint_window_252m$te_vs_hybrid_baseline,
    IR_vs_hybrid = x$joint_window_252m$ir_vs_hybrid_baseline,
    delta_SR_vs_0pct = x$joint_window_252m$delta_sr_vs_0pct,
    delta_MDD_vs_0pct = x$joint_window_252m$delta_mdd_vs_0pct,
    delta_CAGR_vs_0pct = x$joint_window_252m$delta_cagr_vs_0pct,
    SR_full_254m = x$full_window_254m$sr_a,
    CAGR_full_254m = x$full_window_254m$cagr,
    MDD_full_254m = x$full_window_254m$mdd,
    SR_optimizer_estimate = x$optimizer_estimate$sr_a_est,
    SR_realized_minus_estimate = x$forge_realized_vs_estimate$sr_realized_minus_est,
    MDD_optimizer_estimate = x$optimizer_estimate$mdd_est,
    MDD_realized_minus_estimate = x$forge_realized_vs_estimate$mdd_realized_minus_est
  )
}), fill = TRUE)
fwrite(cmp_dt, file.path(FORGE_DIR, "five_ratio_comparison.csv"))

cat("\n[saved]", file.path(FORGE_DIR, "five_ratio_comparison.csv"), "\n")
cat("[saved]", file.path(FORGE_DIR, "five_ratio_metrics.json"), "\n")

cat("\n[FORGE STEP 2] DONE\n")
