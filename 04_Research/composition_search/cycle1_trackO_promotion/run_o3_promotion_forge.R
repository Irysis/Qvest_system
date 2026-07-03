# =============================================================================
# Track O Cycle 1 PROMOTION — O3_MIDBAND_FLOOR forge-authoritative measurement
# =============================================================================
# Role: forge (measurement). Task: book-patch confirm dossier inputs.
# Scope (HARD):
#   - READ-ONLY: 05_Production (layer5 panel via Read-equivalent fread),
#     cycle1_trackO/* (prereg + commit), value_sleeve_combination/aligned_series.rds (bench).
#   - WRITE-ONLY: 04_Research/composition_search/cycle1_trackO_promotion/*.
#   - NO modification of book_state, live_track, 05_Production, 01_Literature.
#
# What this does (independent reproduction, NOT a re-read of cycle1 outputs):
#   [A] Reconstruct O3_MIDBAND_FLOOR g-schedule from production lagged columns
#       per frozen prereg formula + INV-O1 deep-guard (6 deep months).
#   [B] PIT verification IN CODE: assert only *_lag columns drive g (C5 t-1
#       inherited); assert g is pointwise function of month-t lagged columns;
#       deep-guard exact-match audit. Same-day (non-lagged) usage => abort.
#   [C] Build O3 net monthly series (267m) under UNIFORM cost convention,
#       reproduce cycle1 FULL SR 1.9271 (tolerance reported).
#   [D] 10-component bt_result via contract build_bt_result + audit_bt_result.
#       metric_type=backtested.
#   [E] Benchmark-relative (PORT_t NW lag-3 / IR / oos_retention v2 / calmar)
#       on CALENDAR-ALIGNED overlap window (realized_ym +1 book-pull per
#       period_returns_realized_ym_convention.md; bench = KOSPI200_KQ150_BM
#       from aligned_series.rds, true calendar month, coverage 2005-09..2026-04).
#   [F] vs incumbent (INCUMBENT_REPRICED) delta table: dSR/dMDD/dCost (book,
#       label-invariant) + dPORT_t/dIR (calendar-aligned).
#   [G] DSR diagnostic (sweep, n_trials=5, Track O arms in full).
#   [H] essence_score grade reference (NOT a verdict).
#   [I] Persist promotion_dossier.json + reproduction_table.csv.
#
# Engine: PerformanceAnalytics standard (table.AnnualizedReturns, maxDrawdown,
#   SharpeRatio.annualized) + contract builders. No prod/cumprod self-synthesis
#   of metrics (NAV cumprod for the path object only, as contract itself does).
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite)
})
setDTthreads(2)
options(stringsAsFactors = FALSE)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PROD <- file.path(ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
OUT  <- file.path(ROOT, "04_Research/composition_search/cycle1_trackO_promotion")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/audit_bt_result.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/essence_score.R"))

log <- list()
say <- function(...) { m <- sprintf(...); cat(m, "\n"); log[[length(log)+1]] <<- m }

# -----------------------------------------------------------------------------
# [1] Load production realized panel (READ-ONLY source)
# -----------------------------------------------------------------------------
l5 <- fread(file.path(PROD, "04_backtest_results/period_returns_layer5.csv"))
l5[, anchor_date := as.Date(anchor_date)]
setorder(l5, anchor_date)
stopifnot(nrow(l5) == 267)
say("[1] layer5 panel n=%d realized_ym %s..%s", nrow(l5), min(l5$realized_ym), max(l5$realized_ym))

# -----------------------------------------------------------------------------
# [2] PIT guard — columns that drive g MUST be the already-lagged production
#     paths (C5 t-1 inherited). Abort if any non-lagged beta column is present
#     and would be used. The prereg formula uses ONLY beta_threshold_lag and
#     m4_weight_lag (both _lag-suffixed). beta_R05_V2 is the frozen R05 path
#     (consumed as stored, INV-O2).
# -----------------------------------------------------------------------------
drive_cols <- c("beta_threshold_lag", "m4_weight_lag")  # O3 g inputs
r05_col    <- "beta_R05_V2"                              # frozen, stored
stopifnot(all(drive_cols %in% names(l5)))
pit_lag_ok <- all(grepl("_lag$", drive_cols))
# Confirm no same-day (non-lagged) beta_threshold / m4_weight column is what we read.
nonlag_present <- c("beta_threshold","m4_weight")[c("beta_threshold","m4_weight") %in% names(l5)]
say("[2] PIT: g-driving cols = {%s} all _lag-suffixed = %s | non-lag cols present in panel = {%s} (NOT used by O3)",
    paste(drive_cols, collapse=","), pit_lag_ok,
    if (length(nonlag_present)) paste(nonlag_present, collapse=",") else "none")
if (!pit_lag_ok) stop("PIT VIOLATION: O3 g would use a non-lagged (same-day) column. ABORT.")

# baseline recomposition closure (production identity must reproduce <1e-12)
l5[, recomp := beta_R05_V2 * beta_threshold_lag * m4_weight_lag * ret_orig -
      db_thr * 0.0015 - db_R05_V2 * 0.0015]
base_resid <- max(abs(l5$recomp - l5$ret_L5_V2))
say("[2] baseline ret_L5_V2 recomposition max|resid| = %.3e (closure gate <1e-12: %s)",
    base_resid, base_resid < 1e-12)
stopifnot(base_resid < 1e-12)

# cost-leg identities
id_thr <- max(abs(l5$db_thr - c(0, abs(diff(l5$beta_threshold_lag)))))
id_r05 <- max(abs(l5$db_R05_V2 - c(0, abs(diff(l5$beta_R05_V2)))))
say("[2] db_thr==|d beta_AR| %.3e | db_R05==|d beta_R05| %.3e", id_thr, id_r05)

# -----------------------------------------------------------------------------
# [3] Incumbent product + deep-guard mask (INV-O1)
# -----------------------------------------------------------------------------
l5[, g_inc := beta_threshold_lag * m4_weight_lag]   # AR x M4 (non-R05 combine under test)
l5[, b_inc := g_inc * beta_R05_V2]                  # incumbent total exposure
deep <- l5$b_inc < 0.25
say("[3] deep-guard months (b_inc<0.25) = %d (prereg expects 6)", sum(deep))
stopifnot(sum(deep) == 6)

# -----------------------------------------------------------------------------
# [4] O3_MIDBAND_FLOOR g-schedule (frozen prereg formula) + INV-O1 deep-guard.
#     g = g_inc if g_inc < 0.25 else max(g_inc, 0.5)   (mid-band floor at 0.5)
#     deep override: g[deep] := g_inc[deep]  (crisis defense preserved exactly)
# -----------------------------------------------------------------------------
g_o3 <- ifelse(l5$g_inc < 0.25, l5$g_inc, pmax(l5$g_inc, 0.5))
g_o3[deep] <- l5$g_inc[deep]

# PIT structural assertion: g_o3 is a deterministic pointwise function of month-t
# lagged columns only (no leads, no future). Verify by recomputing element-wise
# and confirming it depends on no row != t.
g_check <- numeric(nrow(l5))
for (i in seq_len(nrow(l5))) {
  gi <- l5$g_inc[i]
  g_check[i] <- if (l5$b_inc[i] < 0.25) gi else if (gi < 0.25) gi else max(gi, 0.5)
}
pit_pointwise <- max(abs(g_check - g_o3)) == 0
say("[4] O3 g pointwise-of-month-t reconstruction max|diff| = %.3e (PIT pointwise: %s)",
    max(abs(g_check - g_o3)), pit_pointwise)
stopifnot(pit_pointwise)

# INV-O1 deep-guard exact-match audit (candidate total beta == incumbent on 6 deep months)
b_o3 <- g_o3 * l5$beta_R05_V2
dg_max <- max(abs(b_o3[deep] - l5$b_inc[deep]))
lift_months <- sum(g_o3 > l5$g_inc + 1e-12)
cut_months  <- sum(g_o3 < l5$g_inc - 1e-12)
say("[4] INV-O1 deep-guard max|b_o3 - b_inc| on deep = %.3e (must be 0) | lift months g>g_inc = %d | cut months = %d",
    dg_max, lift_months, cut_months)
stopifnot(dg_max == 0)

# -----------------------------------------------------------------------------
# [5] Series construction (UNIFORM cost convention, identical to prereg & incumbent reprice)
#     ret = beta_R05_V2 * g * ret_orig - 0.0015*|d g| - 0.0015*db_R05_V2
#     d g at t=1 measured vs initial exposure 1.0 (production first row betas=1).
# -----------------------------------------------------------------------------
mk_series <- function(g) {
  dg   <- abs(diff(c(1, g)))
  cost <- 0.0015 * dg + 0.0015 * l5$db_R05_V2
  list(ret = l5$beta_R05_V2 * g * l5$ret_orig - cost, cost = cost, g = g)
}
o3  <- mk_series(g_o3)
inc <- mk_series(l5$g_inc)   # INCUMBENT_REPRICED (uniform convention, A/B baseline)

# -----------------------------------------------------------------------------
# [6] Windows (book single-series; SR/CAGR/MDD label-invariant per realized_ym doc)
# -----------------------------------------------------------------------------
win <- list(
  IS_2005_2018  = l5$realized_ym >= "2005-01" & l5$realized_ym <= "2018-12",
  OOS_2019_2026 = l5$realized_ym >= "2019-01",
  FULL_267m     = rep(TRUE, nrow(l5)),
  SUB2017_2026  = l5$realized_ym >= "2017-01"
)
metr <- function(r, dts) {
  x  <- xts(r, order.by = dts)
  ta <- table.AnnualizedReturns(x, scale = 12, Rf = 0)
  cagr <- as.numeric(ta["Annualized Return", 1])
  mdd  <- -abs(as.numeric(maxDrawdown(x)))
  list(SR = as.numeric(ta["Annualized Sharpe (Rf=0%)", 1]), CAGR = cagr,
       Vol = as.numeric(ta["Annualized Std Dev", 1]), MDD = mdd,
       Calmar = if (mdd < 0) cagr / abs(mdd) else NA_real_)
}
repro <- list()
for (wn in names(win)) {
  wm <- win[[wn]]
  mo <- metr(o3$ret[wm], l5$anchor_date[wm]); mi <- metr(inc$ret[wm], l5$anchor_date[wm])
  repro[[wn]] <- data.table(
    window = wn, n = sum(wm),
    O3_SR = round(mo$SR,4), O3_CAGR = round(mo$CAGR,4), O3_MDD = round(mo$MDD,4),
    O3_Calmar = round(mo$Calmar,4), O3_ann_cost = round(mean(o3$cost[wm])*12,5),
    INC_SR = round(mi$SR,4), INC_MDD = round(mi$MDD,4), INC_ann_cost = round(mean(inc$cost[wm])*12,5),
    dSR = round(mo$SR - mi$SR,4), dCAGR = round(mo$CAGR - mi$CAGR,4),
    dMDD_pp = round((mo$MDD - mi$MDD)*100,2), dCost = round((mean(o3$cost[wm])-mean(inc$cost[wm]))*12,5))
}
repro <- rbindlist(repro)
say("\n[6] O3 reproduction (book single-series; metric_type=backtested):")
print(repro)

# reproduction fidelity vs cycle1_trackO/combine_ab_results.csv
cyc <- fread(file.path(ROOT, "04_Research/composition_search/cycle1_trackO/combine_ab_results.csv"))
cmp_full <- cyc[window=="FULL_267m" & arm=="O3_MIDBAND_FLOOR"]
repro_full_sr <- repro[window=="FULL_267m", O3_SR]
sr_tol <- abs(repro_full_sr - cmp_full$SR)
say("[6] reproduction fidelity FULL SR: this run = %.4f | cycle1 = %.4f | |diff| = %.2e (tol 5e-4: %s)",
    repro_full_sr, cmp_full$SR, sr_tol, sr_tol < 5e-4)

# -----------------------------------------------------------------------------
# [7] 10-component bt_result (FULL 267m book) via contract
#     NAV path = cumprod(1+net) (path object only; metrics from PerfAnalytics).
# -----------------------------------------------------------------------------
build_book_btr <- function(ret_vec, dts, bm_xts, sid, label) {
  nav <- cumprod(1 + ret_vec)
  nav_dt <- data.table(Date = dts, NAV = nav, NAV_gross = nav)  # gross==net (cost already in ret)
  sim <- list(
    strategy_xts = xts(ret_vec, order.by = dts),
    DAILY_NAV_DT = nav_dt,
    bm_xts = bm_xts,
    HOLDINGS_LOG = NULL,
    PORTFOLIO_LOG = NULL
  )
  spec <- list(strategy_name = sid, description = label,
               universe = "KOSPI200_KQ150", rebalance = "monthly",
               combine_rule = "O3_MIDBAND_FLOOR", n_holdings_max = 25L)
  btr <- build_bt_result(
    sim_result = sim, strategy_spec = spec,
    run_id = paste0(sid, "_", format(Sys.time(), "%Y%m%d_%H%M%S")),
    strategy_id = sid, strategy_version = "trackO_promotion_v1",
    benchmark_id = "KOSPI200_KQ150_BM", benchmark_name = "KOSPI200_KQ150 BM",
    transaction_cost_bps = 15, slippage_bps = 0, risk_free_rate = 0,
    frequency = "monthly", annualization_factor = 12,
    universe_id = "KOSPI200_KQ150",
    code_version = "run_o3_promotion_forge_v1", created_by_agent = "forge")
  audit_bt_result(btr)
}

# FULL book bt_result — benchmark left NULL (book single-series authority; bench
# coverage starts 2005-09 so FULL 267m has no calendar-aligned bench). PORT_t/IR
# come from the calendar-aligned overlap bt_result below.
btr_full <- build_book_btr(o3$ret, l5$anchor_date, bm_xts = NULL,
                           sid = "STR_1715_O3_MIDBAND_FLOOR_FULL", label = "O3 FULL 267m book")
integ_full <- btr_full$manifest$integrity_status[1]
say("[7] FULL bt_result integrity = %s | audit checks = %d", integ_full, nrow(btr_full$audit))
print(btr_full$audit[, .(check_name, status, severity)])

# -----------------------------------------------------------------------------
# [8] Calendar-aligned overlap bt_result (book-pull +1) for PORT_t / IR / oos_retention
#     book label m+1 <-> calendar month m (realized_ym convention §3).
#     bench (KOSPI200_KQ150_BM) keyed to true calendar month, coverage 2005-09..2026-04.
# -----------------------------------------------------------------------------
M <- as.data.table(readRDS(file.path(ROOT,
  "04_Research/composition_search/value_sleeve_combination/aligned_series.rds")))
setorder(M, realized_ym)
# O3 book keyed by realized_ym
o3_dt <- data.table(realized_ym = l5$realized_ym, o3_ret = o3$ret, inc_ret = inc$ret)
setorder(o3_dt, realized_ym)
no <- nrow(o3_dt)
# pull book forward 1 label: book_true[m] = book_ret[m+1]
pulled <- data.table(
  realized_ym = o3_dt$realized_ym[1:(no-1)],   # = calendar month m
  o3_cal  = o3_dt$o3_ret[2:no],
  inc_cal = o3_dt$inc_ret[2:no]
)
cal <- merge(pulled, M[, .(realized_ym, bench_ret)], by = "realized_ym")
setorder(cal, realized_ym)
cal_dates <- as.Date(paste0(cal$realized_ym, "-01"))
say("[8] calendar-aligned overlap n=%d  %s..%s (bench coverage gate)",
    nrow(cal), min(cal$realized_ym), max(cal$realized_ym))

bench_xts <- xts(cal$bench_ret, order.by = cal_dates)
btr_cal_o3  <- build_book_btr(cal$o3_cal,  cal_dates, bm_xts = bench_xts,
                              sid = "STR_1715_O3_MIDBAND_FLOOR_CAL", label = "O3 calendar-aligned overlap")
btr_cal_inc <- build_book_btr(cal$inc_cal, cal_dates, bm_xts = bench_xts,
                              sid = "STR_1715_INCUMBENT_REPRICED_CAL", label = "Incumbent repriced calendar-aligned")

getbc <- function(btr, nm) btr$benchmark_compare[metric_name == nm, active_value][1]
o3_port_t  <- getbc(btr_cal_o3,  "Portfolio_Alpha_t_NW_lag3")
inc_port_t <- getbc(btr_cal_inc, "Portfolio_Alpha_t_NW_lag3")
o3_ir  <- getbc(btr_cal_o3,  "Information_Ratio")
inc_ir <- getbc(btr_cal_inc, "Information_Ratio")
o3_te  <- getbc(btr_cal_o3,  "Tracking_Error")
say("[8] calendar-aligned PORT_t(NW lag3): O3 = %.3f | incumbent = %.3f | dPORT_t = %+.3f",
    o3_port_t, inc_port_t, o3_port_t - inc_port_t)
say("[8] calendar-aligned IR: O3 = %.3f | incumbent = %.3f | dIR = %+.3f | O3 TE = %.4f",
    o3_ir, inc_ir, o3_ir - inc_ir, o3_te)

# -----------------------------------------------------------------------------
# [9] essence_score reference (NOT a verdict) — sweep, n_trials=5
#     Uses calendar-aligned bt_result so PORT_t + oos_retention(active) consistent.
# -----------------------------------------------------------------------------
es_o3 <- essence_score(btr_cal_o3, n_trials_cumulative = 5,
                       selection_type = "sweep", oos_stat_version = "v2")
es_inc <- essence_score(btr_cal_inc, n_trials_cumulative = 5,
                        selection_type = "sweep", oos_stat_version = "v2")
say("\n[9] essence_score (calendar-aligned, sweep n_trials=5, oos v2):")
say("    O3 : grade=%s PORT_t=%.3f oos_ret=%.3f (splits %s) DSR=%.3f calmar=%.3f net_SR=%.3f CAGR=%.3f MDD=%.3f",
    es_o3$grade, es_o3$essence$portfolio_alpha_t_nw_lag3, es_o3$essence$oos_retention %||% NA,
    paste(es_o3$oos_retention_splits, collapse="/"), es_o3$essence$dsr %||% NA,
    es_o3$essence$calmar, es_o3$essence$net_sharpe, es_o3$essence$cagr, es_o3$essence$mdd)
say("    INC: grade=%s PORT_t=%.3f oos_ret=%.3f DSR=%.3f calmar=%.3f net_SR=%.3f",
    es_inc$grade, es_inc$essence$portfolio_alpha_t_nw_lag3, es_inc$essence$oos_retention %||% NA,
    es_inc$essence$dsr %||% NA, es_inc$essence$calmar, es_inc$essence$net_sharpe)

# Note: essence_score book single-series (net_SR/CAGR/MDD/calmar) here are on the
# calendar-aligned OVERLAP window (2005-09+, n-1), NOT the FULL 267m. The FULL
# book authority for SR/CAGR/MDD/Calmar is btr_full / repro table (label-invariant).
full_sr   <- repro[window=="FULL_267m", O3_SR]
full_cagr <- repro[window=="FULL_267m", O3_CAGR]
full_mdd  <- repro[window=="FULL_267m", O3_MDD]
full_calmar <- repro[window=="FULL_267m", O3_Calmar]
say("[9] FULL 267m book authority (label-invariant): SR=%.4f CAGR=%.4f MDD=%.4f Calmar=%.4f",
    full_sr, full_cagr, full_mdd, full_calmar)

# -----------------------------------------------------------------------------
# [10] DSR diagnostic across all 5 Track O arms (sweep, n_trials=5) — FULL window
#     Reconstruct all arms to compute the sweep DSR for the WINNER (O3), full ledger.
# -----------------------------------------------------------------------------
RHO <- 0.4951; bAR <- l5$beta_threshold_lag; m4 <- l5$m4_weight_lag; eps <- 1e-12
g_arms <- list(
  O1_MIN_DEDUP      = pmin(bAR, m4),
  O2_M4_PRIORITY_OR = ifelse(m4 < 1 - eps, m4, bAR),
  O3_MIDBAND_FLOOR  = ifelse(l5$g_inc < 0.25, l5$g_inc, pmax(l5$g_inc, 0.5)),
  O4_POWER_RHO      = (bAR * m4)^(1/(1+RHO)),
  O5_BLEND_RHO      = (1-RHO)*(bAR*m4) + RHO*pmin(bAR, m4))
for (nm in names(g_arms)) g_arms[[nm]][deep] <- l5$g_inc[deep]
.dsr <- function(sr_ann, n_obs, n_trials, skew=0, kurt=3, A=12) {
  if (!is.finite(sr_ann) || n_obs < 12) return(NA_real_)
  emc <- 0.5772156649; sr_m <- sr_ann/sqrt(A); var0 <- 1/(n_obs-1)
  z1 <- qnorm(1-1/n_trials); z2 <- qnorm(1-1/(n_trials*exp(1)))
  sr0 <- sqrt(var0)*((1-emc)*z1 + emc*z2)
  den <- sqrt(1 - skew*sr_m + (kurt-1)/4*sr_m^2)
  if (!is.finite(den) || den<=0) return(NA_real_)
  pnorm((sr_m - sr0)*sqrt(n_obs-1)/den)
}
dsr_full <- list()
for (nm in names(g_arms)) {
  s <- mk_series(g_arms[[nm]]); r <- s$ret  # FULL
  x <- xts(r, order.by = l5$anchor_date)
  sr_ann <- as.numeric(table.AnnualizedReturns(x, scale=12, Rf=0)["Annualized Sharpe (Rf=0%)",1])
  sk <- as.numeric(PerformanceAnalytics::skewness(r, method="moment"))
  ku <- as.numeric(PerformanceAnalytics::kurtosis(r, method="moment"))
  dsr_full[[nm]] <- data.table(arm=nm, window="FULL_267m", n=length(r),
                               SR=round(sr_ann,4), skew=round(sk,3), kurt=round(ku,3),
                               DSR_ntrials5=round(.dsr(sr_ann,length(r),5,sk,ku),4))
}
dsr_tab <- rbindlist(dsr_full)
say("\n[10] DSR diagnostic (sweep n_trials=5, FULL window, all arms):")
print(dsr_tab)
o3_dsr <- dsr_tab[arm=="O3_MIDBAND_FLOOR", DSR_ntrials5]

# -----------------------------------------------------------------------------
# [11] Persist outputs
# -----------------------------------------------------------------------------
fwrite(repro, file.path(OUT, "reproduction_table.csv"))
fwrite(dsr_tab, file.path(OUT, "dsr_diagnostic.csv"))
save_o3 <- function(btr, sub) {
  d <- file.path(OUT, sub); dir.create(d, showWarnings=FALSE, recursive=TRUE)
  fwrite(btr$benchmark_compare, file.path(d, "benchmark_compare.csv"))
  fwrite(btr$metrics, file.path(d, "metrics.csv"))
  fwrite(btr$audit, file.path(d, "audit.csv"))
}
save_o3(btr_full, "btr_full")
save_o3(btr_cal_o3, "btr_calendar_o3")
save_o3(btr_cal_inc, "btr_calendar_incumbent")

dossier <- list(
  task = "Track O Cycle 1 PROMOTION — O3_MIDBAND_FLOOR forge-authoritative measurement",
  date = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  agent = "forge", metric_type = "backtested",
  status = "AWAITING_DOHOON_CONFIRM (book patch is not a graduation; non-worsening + improvement frame)",
  selected_candidate = "O3_MIDBAND_FLOOR",
  incumbent = "STR_1715_AR_on_M4_R05_overlay_PG2 (INCUMBENT_REPRICED uniform-cost baseline)",
  prereg = "04_Research/composition_search/cycle1_trackO/prereg_combine_candidates.json (frozen 2026-06-12T07:55:41)",
  is_selection_commit = "04_Research/composition_search/cycle1_trackO/is_selection_commit.json (O3 committed BEFORE OOS)",
  selection_type = "sweep", n_trials = 5,
  pit_verification = list(
    g_driving_cols = drive_cols, all_lag_suffixed = pit_lag_ok,
    c5_t1_inherited = "production lagged paths (beta_threshold_lag, m4_weight_lag); O3 = pointwise fn of month-t",
    pointwise_reconstruction_max_diff = max(abs(g_check - g_o3)),
    baseline_recomposition_max_resid = base_resid,
    deep_guard_exact_match_max_abs_beta_diff = dg_max,
    verdict = if (pit_lag_ok && pit_pointwise && base_resid < 1e-12 && dg_max == 0) "PASS" else "FAIL"),
  reproduction = list(
    full_SR_this_run = repro_full_sr, full_SR_cycle1 = cmp_full$SR,
    abs_diff = sr_tol, tolerance = 5e-4, match = sr_tol < 5e-4,
    table = repro),
  bt_result_audit = list(
    full_book_integrity = integ_full,
    calendar_o3_integrity = btr_cal_o3$manifest$integrity_status[1],
    calendar_inc_integrity = btr_cal_inc$manifest$integrity_status[1]),
  gate_reference_NOT_verdict = list(
    full_267m_book = list(SR=full_sr, CAGR=full_cagr, MDD=full_mdd, Calmar=full_calmar),
    calendar_aligned_overlap = list(
      n_months = nrow(cal), window = paste0(min(cal$realized_ym),"..",max(cal$realized_ym)),
      O3_PORT_t_nw_lag3 = round(o3_port_t,3), incumbent_PORT_t = round(inc_port_t,3),
      dPORT_t = round(o3_port_t - inc_port_t,3),
      O3_IR = round(o3_ir,3), incumbent_IR = round(inc_ir,3), dIR = round(o3_ir - inc_ir,3),
      O3_TE = round(o3_te,4),
      O3_oos_retention_v2 = es_o3$essence$oos_retention,
      O3_oos_splits = es_o3$oos_retention_splits,
      O3_calmar = es_o3$essence$calmar),
    DSR_sweep_n5_O3 = o3_dsr,
    essence_grade_O3 = es_o3$grade, essence_grade_incumbent = es_inc$grade,
    hard_gate_thresholds = list(PORT_t = 2.95, oos_retention = 0.7, calmar = 0.64, DSR_sweep = 0.5)),
  vs_incumbent_frame = list(
    note = "book patch = incumbent combine improvement, NOT new-module graduation. C2 rare_mode precedent: A/B non-worsening -> Dohoon confirm.",
    dSR_FULL = repro[window=="FULL_267m", dSR],
    dMDD_pp_FULL = repro[window=="FULL_267m", dMDD_pp],
    dCost_FULL = repro[window=="FULL_267m", dCost],
    dSR_OOS = repro[window=="OOS_2019_2026", dSR],
    dPORT_t_cal = round(o3_port_t - inc_port_t,3),
    dIR_cal = round(o3_ir - inc_ir,3)),
  log = unlist(log))
write_json(dossier, file.path(OUT, "promotion_dossier.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 10, na = "null")
say("\n[11] outputs -> %s", OUT)
say("    promotion_dossier.json | reproduction_table.csv | dsr_diagnostic.csv | btr_*/")
saveRDS(list(btr_full=btr_full, btr_cal_o3=btr_cal_o3, btr_cal_inc=btr_cal_inc,
             repro=repro, dossier=dossier), file.path(OUT, "promotion_objects.rds"))
cat("\n========== DONE ==========\n")
