## ============================================================
## WT-S20260626_001 FORGE — incumbent(product) vs max-cash(min) overlay A/B
## Pure-function fresh A/B backtest. build_bt_result() 10-component.
## PerformanceAnalytics standard functions only.
## ============================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate); library(sandwich)
})
try(arrow::set_cpu_count(1), silent = TRUE)
`%||%` <- function(a,b) if (is.null(a) || length(a)==0) b else a

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/audit_bt_result.R"))

WT_ID <- "WT-S20260626_001"
STAGE_DIR <- file.path(ROOT, "stage_artifacts/WT_WT_S20260626_001")
MAILBOX   <- file.path(ROOT, "qepm/mailbox/worktask", WT_ID)
BPS <- 0.0015  # 15bps one-way

cat("============================================================\n")
cat("FORGE A/B: incumbent(product) vs max-cash(min)\n")
cat("============================================================\n\n")

## ── 1. Base sleeve return (STR_1715 ret_net, Iter31 tilt baked, pre AR/R05 overlay)
pr <- fread(file.path(ROOT,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))
pr[, date := as.Date(date)]
pr[, ym := format(date, "%Y-%m")]
setorder(pr, date)
stopifnot(all(pr$cash_weight == 0, na.rm = TRUE))   # base = fully invested sleeve, cash split is the overlay's job
base <- pr[, .(ym, date, ret_orig = ret_net, ret_gross_base = ret_gross)]

## ── 2. Overlay combine schedule (already verified: invested_mult = m4*bAR*bR05; invested_maxcash = m4*min)
sch <- fread(file.path(STAGE_DIR, "overlay_combine_schedule.csv"))
sch[, sig_date := as.Date(sig_date)]
setorder(sch, sig_date)
# risk weights are ALREADY pit-lagged (betas derived from production *_lag cols) -> apply to same-ym ret_orig
sch_use <- sch[, .(ym, regime, m4, beta_AR, beta_R05,
                   rw_inc = invested_mult, rw_mc = invested_maxcash)]

panel <- merge(base, sch_use, by = "ym", all.x = TRUE)
setorder(panel, date)
# guard: any month missing overlay -> full invested (no de-risk) both arms (should not happen, all 269 covered)
panel[is.na(rw_inc), rw_inc := 1.0]
panel[is.na(rw_mc),  rw_mc  := 1.0]
stopifnot(nrow(panel) == 269)
cat(sprintf("[1] panel months: %d  | %s ~ %s\n", nrow(panel),
            min(panel$ym), max(panel$ym)))
cat(sprintf("    co-firing (rw_inc != rw_mc): %d months\n",
            sum(abs(panel$rw_inc - panel$rw_mc) > 1e-9)))

## ── 3. Cash-leg turnover cost (|Δ risk_weight| × 15bps), per arm.
##     Base sleeve stock churn (784%/yr) is ALREADY in ret_orig (production ret_net). We add ONLY the
##     incremental cash-leg rebalancing cost that differs between arms. Cash leg earns 0 (production convention,
##     risk_free_ret==0 in source -> apples-to-apples with incumbent production NAV).
panel[, d_rw_inc := abs(rw_inc - shift(rw_inc, 1, fill = 1.0))]
panel[, d_rw_mc  := abs(rw_mc  - shift(rw_mc,  1, fill = 1.0))]
panel[is.na(d_rw_inc), d_rw_inc := 0]
panel[is.na(d_rw_mc),  d_rw_mc  := 0]

## ── 4. Arm returns. Port = risk_weight * ret_orig + (1-risk_weight)*cash(0) - cashleg_turnover_cost
panel[, ret_inc := rw_inc * ret_orig - d_rw_inc * BPS]
panel[, ret_mc  := rw_mc  * ret_orig - d_rw_mc  * BPS]
## gross variants (no cash-leg incremental cost) for nav_gross
panel[, ret_inc_gross := rw_inc * ret_gross_base]
panel[, ret_mc_gross  := rw_mc  * ret_gross_base]

## ── 5. Monthly benchmark (KOSPI200) from canonical daily benchmark.parquet
bmd <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))
bmd[, Date := as.Date(Date)]
bmd[, ym := format(Date, "%Y-%m")]
bmd <- bmd[!is.na(BM_Ret)]
bm_m <- bmd[, .(bm_ret = prod(1 + BM_Ret) - 1), by = ym]   # compound daily within month (BM index aggregation, not portfolio synth)
panel <- merge(panel, bm_m, by = "ym", all.x = TRUE)
setorder(panel, date)
cat(sprintf("[5] BM monthly coverage: %d / %d months have BM\n",
            sum(!is.na(panel$bm_ret)), nrow(panel)))
panel[is.na(bm_ret), bm_ret := 0]

## ── 6. Helper: assemble sim_result + build_bt_result for one arm
build_arm <- function(ret_net_vec, ret_gross_vec, dates, bm_vec, arm_label) {
  dts <- as.Date(dates)
  strat_xts <- xts(ret_net_vec, order.by = dts)
  nav_net   <- cumprod(1 + ret_net_vec)
  nav_gross <- cumprod(1 + ret_gross_vec)
  nav_dt <- data.table(Date = dts, NAV = nav_net, NAV_gross = nav_gross)
  bm_xts <- xts(bm_vec, order.by = dts)
  sim <- list(
    DAILY_NAV_DT = nav_dt,
    strategy_xts = strat_xts,
    bm_xts = bm_xts,
    HOLDINGS_LOG = NULL,
    PORTFOLIO_LOG = NULL
  )
  spec <- list(
    name = paste0("STR_1715_overlay_", arm_label),
    description = paste0("STR_1715 Iter31 base sleeve x M4 x AR x R05 overlay; combine=", arm_label),
    universe = "KOSPI200 U KOSDAQ150",
    rebalance = "monthly", weighting = "Iter31_linear_tilt + regime cash overlay",
    lookahead_prevention = "All overlay risk-weights (m4, beta_AR, beta_R05) are t-1 lagged (shift(1)); risk_weight(t) decided from end-of-(t-1) info, applied to month-t base ret_orig. Base sleeve ret_orig = STR_1715 production ret_net (Iter31 tilt baked, score_eff top-20 PIT). C1/C2/C9/C13/C14 inherited from STR_1715 frozen pipeline; combine-operator change (product->min) is order-preserving on PIT inputs -> no new look-ahead.",
    survivorship_bias_control = "Inherited from STR_1715 frozen base sleeve (KOSPI200 U KOSDAQ150 PIT membership at each sig_date via alpha_scores.parquet lineage). Overlay re-weights frozen sleeve only; introduces no universe selection.",
    pit_reference = "C1_C2_C9_C13_C14 (STR_1715 frozen) + overlay t-1 lag"
  )
  bt <- build_bt_result(
    sim_result = sim, strategy_spec = spec,
    run_id = paste0(WT_ID, "_", arm_label),
    strategy_id = paste0("STR_1715_overlay_", arm_label),
    benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
    transaction_cost_bps = 15, slippage_bps = 0, risk_free_rate = 0,
    frequency = "monthly", annualization_factor = 12,
    universe_id = "KOSPI200_KOSDAQ150",
    code_version = "forge_ab_maxcash_v1", created_by_agent = "forge")
  bt <- audit_bt_result(bt)
  bt
}

cat("\n[6] Build bt_result A (incumbent product)\n")
bt_inc <- build_arm(panel$ret_inc, panel$ret_inc_gross, panel$date, panel$bm_ret, "incumbent_product")
cat("\n[6] Build bt_result B (max-cash min)\n")
bt_mc  <- build_arm(panel$ret_mc,  panel$ret_mc_gross,  panel$date, panel$bm_ret, "maxcash_min")

## ── 7. Extract metrics per arm (PerformanceAnalytics)
arm_metrics <- function(bt, ret_vec, dts, bm_vec, label) {
  xr <- xts(ret_vec, order.by = as.Date(dts))
  ann <- table.AnnualizedReturns(xr, scale = 12, Rf = 0)
  cagr <- as.numeric(ann[1,1]); vol <- as.numeric(ann[2,1]); sr <- as.numeric(ann[3,1])
  mdd <- as.numeric(maxDrawdown(xr))
  calmar <- as.numeric(CalmarRatio(xr))
  sortino <- as.numeric(SortinoRatio(xr, MAR = 0))
  # active series vs BM
  act <- ret_vec - bm_vec
  xa <- xts(act, order.by = as.Date(dts))
  ann_a <- table.AnnualizedReturns(xa, scale = 12, Rf = 0)
  act_cagr <- as.numeric(ann_a[1,1]); te <- as.numeric(ann_a[2,1])
  net_ir <- if (te > 0) act_cagr / te else NA_real_
  # portfolio_alpha_t_nw_lag3: NW lag-3 t-stat on active mean (intercept-only regression on active series)
  fit <- lm(act ~ 1)
  V <- NeweyWest(fit, lag = 3, prewhite = FALSE, adjust = TRUE)
  pa_t <- as.numeric(coef(fit)[1] / sqrt(V[1,1]))
  list(label = label, n = length(ret_vec),
       SR = round(sr,4), CAGR = round(cagr,4), Vol = round(vol,4),
       MDD = round(-mdd,4), Calmar = round(calmar,4), Sortino = round(sortino,4),
       net_IR = round(net_ir,4), TE = round(te,4),
       portfolio_alpha_t_nw_lag3 = round(pa_t,4),
       active_cagr = round(act_cagr,4))
}

m_inc <- arm_metrics(bt_inc, panel$ret_inc, panel$date, panel$bm_ret, "incumbent_product")
m_mc  <- arm_metrics(bt_mc,  panel$ret_mc,  panel$date, panel$bm_ret, "maxcash_min")

cat("\n=== ARM A incumbent(product) ===\n"); print(m_inc)
cat("\n=== ARM B max-cash(min) ===\n"); print(m_mc)

## ── 8. Deltas (max-cash MINUS incumbent)
deltas <- list(
  dSR     = round(m_mc$SR     - m_inc$SR, 4),
  dCAGR   = round(m_mc$CAGR   - m_inc$CAGR, 4),
  dMDD    = round(m_mc$MDD    - m_inc$MDD, 4),   # MDD stored negative; positive delta = LESS deep (better)
  dIR     = round(m_mc$net_IR - m_inc$net_IR, 4),
  dCalmar = round(m_mc$Calmar - m_inc$Calmar, 4),
  dPORTt  = round(m_mc$portfolio_alpha_t_nw_lag3 - m_inc$portfolio_alpha_t_nw_lag3, 4)
)
cat("\n=== DELTA (max-cash - incumbent) ===\n"); print(deltas)

## ── 9. 32 co-firing month concentrated analysis
cf <- panel[abs(rw_inc - rw_mc) > 1e-9]
cat(sprintf("\n[9] co-firing months: %d\n", nrow(cf)))
cf_inc_ret <- cf$ret_inc; cf_mc_ret <- cf$ret_mc
cf_analysis <- list(
  n_cofiring = nrow(cf),
  cofiring_yms = cf$ym,
  cofiring_regimes = as.list(table(cf$regime)),
  # cumulative return over co-firing months only (segment, NOT a synthetic full-period NAV)
  incumbent_cum_ret_cofiring = round(prod(1 + cf_inc_ret) - 1, 4),
  maxcash_cum_ret_cofiring   = round(prod(1 + cf_mc_ret) - 1, 4),
  incumbent_mean_monthly_cofiring = round(mean(cf_inc_ret), 5),
  maxcash_mean_monthly_cofiring   = round(mean(cf_mc_ret), 5),
  # segment MDD over the co-firing months treated as a contiguous return stream (diagnostic)
  incumbent_segment_mdd = round(-as.numeric(maxDrawdown(xts(cf_inc_ret, order.by = cf$date))), 4),
  maxcash_segment_mdd   = round(-as.numeric(maxDrawdown(xts(cf_mc_ret, order.by = cf$date))), 4),
  # worst single co-firing month per arm
  incumbent_worst_month = list(ym = cf$ym[which.min(cf_inc_ret)], ret = round(min(cf_inc_ret),4)),
  maxcash_worst_month   = list(ym = cf$ym[which.min(cf_mc_ret)], ret = round(min(cf_mc_ret),4))
)
cat("  incumbent cum (cofiring):", cf_analysis$incumbent_cum_ret_cofiring,
    "| maxcash cum (cofiring):", cf_analysis$maxcash_cum_ret_cofiring, "\n")

## ── 10. GFC stress window (2008-09 .. 2009-03) — both arms
gfc <- panel[ym >= "2008-09" & ym <= "2009-03"]
gfc_stress <- list(
  window = "2008-09..2009-03", n = nrow(gfc),
  incumbent_cum = round(prod(1 + gfc$ret_inc) - 1, 4),
  maxcash_cum   = round(prod(1 + gfc$ret_mc) - 1, 4),
  incumbent_mdd = round(-as.numeric(maxDrawdown(xts(gfc$ret_inc, order.by = gfc$date))), 4),
  maxcash_mdd   = round(-as.numeric(maxDrawdown(xts(gfc$ret_mc, order.by = gfc$date))), 4)
)
cat("[10] GFC stress incumbent_cum:", gfc_stress$incumbent_cum,
    "maxcash_cum:", gfc_stress$maxcash_cum, "\n")

## ── 11. Save bt_result.rds (representative = max-cash arm = the WT's new arm) + both
saveRDS(bt_mc, file.path(STAGE_DIR, "bt_result.rds"))
saveRDS(list(incumbent = bt_inc, maxcash = bt_mc),
        file.path(STAGE_DIR, "bt_result_both_arms.rds"))
saveRDS(bt_mc, file.path(MAILBOX, "bt_result.rds"))
fwrite(panel, file.path(STAGE_DIR, "ab_panel_full.csv"))
cat("\n[11] saved bt_result.rds (max-cash arm) + both_arms + ab_panel_full.csv\n")

## ── 12. dump JSON-ready results
res <- list(
  task_id = WT_ID,
  metric_type = "backtested",
  n_months = nrow(panel),
  period = paste0(min(panel$ym), "..", max(panel$ym)),
  arm_incumbent_product = m_inc,
  arm_maxcash_min = m_mc,
  delta_maxcash_minus_incumbent = deltas,
  cofiring_analysis = cf_analysis,
  gfc_stress = gfc_stress,
  bm_source = ".cache/benchmark.parquet (daily KOSPI200 -> monthly compound)",
  audit_inc = list(integrity = bt_inc$manifest$integrity_status[1] %||% NA),
  audit_mc  = list(integrity = bt_mc$manifest$integrity_status[1] %||% NA)
)
write_json(res, file.path(STAGE_DIR, "ab_results.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 6)
cat("\n[12] ab_results.json written\n")
cat("\nDONE.\n")
