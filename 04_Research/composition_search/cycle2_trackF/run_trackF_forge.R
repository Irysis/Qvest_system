# ============================================================
# Track F — O3_MIDBAND_FLOOR overlay combine: forge-authoritative
# confirmation (Composition Search Cycle 2, Dohoon confirm 2026-06-12)
#
# Goal: re-run the production L5 overlay engine from UPSTREAM sources
#   (base PR + M4 weights + AR beta mapping; R05 leg AS STORED per
#   INV-O2) for BOTH combines:
#     incumbent: g_inc = beta_AR_lag * m4_weight_lag (product)
#     O3       : g = g_inc if g_inc < 0.25 else max(g_inc, 0.5)
#                + INV-O1 deep-guard (b_inc < 0.25 -> g := g_inc)
#   under the UNIFORM v2.4-delta cost convention (15bps x |dg| +
#   stored R05 leg), then score through build_bt_result 10-component
#   + audit_bt_result + essence_score (selection_type=sweep, n=5).
#
# O3 formula FROZEN from prereg_combine_candidates.json (2026-06-12
# 07:55:41+09:00). NO modification permitted.
#
# Data boundary: 2026-04-30 cutoff (rawdata 2026-05+ contaminated,
# Track R repairing). Panel native end = 2026-04 (assert).
# metric_type = backtested (contract-built, audit-gated).
# PerformanceAnalytics standard functions only. ASCII output only.
# book_state / admission NOT touched (governor + Dohoon manual).
# ============================================================
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(xts)
  library(PerformanceAnalytics)
  library(jsonlite)
})

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PROD <- file.path(ROOT, "05_Production/2.Factor_Model",
                  "2-1.STR_1715_AR_on_M4_R05_overlay_PG2")  # READ-ONLY
OUT  <- file.path(ROOT, "04_Research/composition_search/cycle2_trackF")
INP  <- file.path(OUT, "inputs")
dir.create(INP, recursive = TRUE, showWarnings = FALSE)

CUTOFF <- as.Date("2026-04-30")

# load with one retry after 60s (atomic-replace possibility during repair)
load_retry <- function(expr_fn, label) {
  r <- tryCatch(expr_fn(), error = function(e) e)
  if (inherits(r, "error")) {
    cat(sprintf("[load] %s failed (%s) - retry in 60s\n", label, conditionMessage(r)))
    Sys.sleep(60)
    r <- expr_fn()
  }
  r
}

# ------------------------------------------------------------
# [0] Contracts
# ------------------------------------------------------------
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/audit_bt_result.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/essence_score.R"))

# ------------------------------------------------------------
# [1] Production realized panel: READ-ONLY -> copy to inputs/
# ------------------------------------------------------------
l5 <- load_retry(function() fread(file.path(PROD, "04_backtest_results/period_returns_layer5.csv")),
                 "period_returns_layer5.csv")
l5[, anchor_date := as.Date(anchor_date)]
setorder(l5, anchor_date)
stopifnot(nrow(l5) == 267)
fwrite(l5, file.path(INP, "period_returns_layer5_prod_copy.csv"))
cat(sprintf("[1] production realized panel copied: n=%d | %s .. %s\n",
            nrow(l5), l5$realized_ym[1], l5$realized_ym[nrow(l5)]))
stopifnot(max(l5$anchor_date) <= CUTOFF)        # 2026-04-30 cutoff (native)
stopifnot(max(l5$realized_ym) == "2026-04")

# ------------------------------------------------------------
# [2] FULL RE-RUN: rebuild panel from UPSTREAM sources
#     (mirrors 01_reproducible_code/run_layer5_R05_overlay.R steps 1-5;
#      R05 leg consumed AS STORED per INV-O2 - upstream admit-lineage
#      parquet WT_D20260425_010 absent on this machine, caveat)
# ------------------------------------------------------------
pr <- load_retry(function() fread(file.path(ROOT,
        "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv")),
        "base PR 03_period_returns.csv")
pr[, date := as.Date(date)]
pr[, ym := format(date, "%Y-%m")]
setorder(pr, date)
stopifnot(all(pr$cash_weight == 0, na.rm = TRUE))

panel <- pr[, .(date, realized_ym = ym, ret_orig = ret_net)]
setorder(panel, date)

m4 <- load_retry(function() fread(file.path(ROOT,
        "qepm/mailbox/worktask/WT-D20260430_001/judge_ready/weights.csv")), "M4 weights.csv")
m4[, Date := as.Date(Date)]
m4[, ym := format(Date, "%Y-%m")]
setorder(m4, Date)
m4[, weight_str1715_lag := shift(weight_str1715, 1, fill = 1.0)]   # t-1 lag (C5)

beta_dt <- load_retry(function() fread(file.path(ROOT,
             "stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv")), "AR beta_t_mapping.csv")
beta_dt[, Date := as.Date(Date)]
beta_dt[, ym := format(Date, "%Y-%m")]
setorder(beta_dt, Date)
beta_dt[, beta_threshold_lag := shift(beta_threshold, 1, fill = 1.0)]  # t-1 lag (C5)

panel <- merge(panel, m4[, .(realized_ym = ym, m4_weight_lag = weight_str1715_lag)],
               by = "realized_ym", all.x = TRUE)
panel[is.na(m4_weight_lag), m4_weight_lag := 1.0]
panel <- merge(panel, beta_dt[, .(realized_ym = ym, beta_threshold_lag)],
               by = "realized_ym", all.x = TRUE)
panel[is.na(beta_threshold_lag), beta_threshold_lag := 1.0]
setorder(panel, date)
panel[, db_thr := abs(beta_threshold_lag - shift(beta_threshold_lag, 1, fill = 1.0))]

# R05 leg AS STORED (INV-O2)
panel <- merge(panel,
               l5[, .(realized_ym, beta_R05_V2, db_R05_V2, regime,
                      ret_orig_stored = ret_orig,
                      beta_thr_stored = beta_threshold_lag,
                      m4_stored = m4_weight_lag,
                      db_thr_stored = db_thr,
                      ret_L5_V2_stored = ret_L5_V2)],
               by = "realized_ym", all.x = TRUE)
setorder(panel, date)
panel <- panel[realized_ym >= "2004-02" & realized_ym <= "2026-04"]
stopifnot(nrow(panel) == 267, !anyNA(panel$beta_R05_V2))
cat(sprintf("[2] rebuilt panel from upstream: n=%d | %s .. %s (cutoff %s native)\n",
            nrow(panel), panel$realized_ym[1], panel$realized_ym[nrow(panel)],
            as.character(CUTOFF)))

# ------------------------------------------------------------
# [3] Reconciliation: rebuilt-from-upstream vs production stored
# ------------------------------------------------------------
rec <- list(
  ret_orig          = max(abs(panel$ret_orig - panel$ret_orig_stored)),
  beta_threshold_lag = max(abs(panel$beta_threshold_lag - panel$beta_thr_stored)),
  m4_weight_lag     = max(abs(panel$m4_weight_lag - panel$m4_stored)),
  db_thr            = max(abs(panel$db_thr - panel$db_thr_stored))
)
# recompose stored ret_L5_V2 under PRODUCTION cost convention from rebuilt legs
panel[, recomp_V2 := beta_R05_V2 * beta_threshold_lag * m4_weight_lag * ret_orig -
        db_thr * 0.0015 - db_R05_V2 * 0.0015]
rec$ret_L5_V2_recomposition <- max(abs(panel$recomp_V2 - panel$ret_L5_V2_stored))
cat("[3] reconciliation rebuilt vs stored (max |diff|):\n")
for (nm in names(rec)) cat(sprintf("    %-26s %.3e\n", nm, rec[[nm]]))
stopifnot(rec$ret_orig < 1e-12, rec$beta_threshold_lag < 1e-12,
          rec$m4_weight_lag < 1e-12, rec$db_thr < 1e-12,
          rec$ret_L5_V2_recomposition < 1e-12)
cat("    => full re-run reproduces production path exactly\n")

# ------------------------------------------------------------
# [4] Arms under UNIFORM v2.4-delta cost convention (prereg)
# ------------------------------------------------------------
panel[, g_inc := beta_threshold_lag * m4_weight_lag]
panel[, b_inc := g_inc * beta_R05_V2]
deep <- panel$b_inc < 0.25
cat(sprintf("[4] deep-guard months (b_inc<0.25) = %d (prereg expects 6)\n", sum(deep)))
stopifnot(sum(deep) == 6)

# O3 frozen formula + INV-O1 deep-guard
g_o3 <- ifelse(panel$g_inc < 0.25, panel$g_inc, pmax(panel$g_inc, 0.5))
g_o3[deep] <- panel$g_inc[deep]

# INV-O1 audit
b_o3 <- g_o3 * panel$beta_R05_V2
inv_o1_max_diff <- max(abs(b_o3[deep] - panel$b_inc[deep]))
lift_months <- sum(g_o3 > panel$g_inc + 1e-12)
cat(sprintf("[4] INV-O1 deep-guard max|b diff| = %.3e (must be 0) | lift months = %d (cycle1: 33)\n",
            inv_o1_max_diff, lift_months))
stopifnot(inv_o1_max_diff == 0)

mk_arm <- function(g) {
  dg    <- abs(diff(c(1, g)))                        # t=1 vs initial exposure 1.0
  cost  <- 0.0015 * dg + 0.0015 * panel$db_R05_V2    # uniform legs + stored R05 leg
  gross <- panel$beta_R05_V2 * g * panel$ret_orig    # overlay-cost-free (base cost inside ret_orig)
  list(g = g, dg = dg, cost = cost, gross = gross, net = gross - cost)
}
arm_inc <- mk_arm(panel$g_inc)
arm_o3  <- mk_arm(g_o3)
# traceability arm: stored production cost convention
arm_stored <- list(net = panel$ret_L5_V2_stored,
                   cost = panel$db_thr * 0.0015 + panel$db_R05_V2 * 0.0015)

# ------------------------------------------------------------
# [5] Benchmark monthly (K200 BM cache, cut 2026-04-30)
# ------------------------------------------------------------
bm <- load_retry(function() as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet"))),
                 "benchmark.parquet")
bm[, Date := as.Date(Date)]
bm <- bm[Date <= CUTOFF & is.finite(BM_Ret)]
bx <- xts(bm$BM_Ret, order.by = bm$Date)
bm_m <- apply.monthly(bx, Return.cumulative)
bm_dt <- data.table(realized_ym = format(as.Date(index(bm_m)), "%Y-%m"),
                    BM_Ret_m = as.numeric(bm_m))
panel <- merge(panel, bm_dt, by = "realized_ym", all.x = TRUE)
setorder(panel, date)
stopifnot(!anyNA(panel$BM_Ret_m))

# BM sanity vs production benchmark_comparison reference
bm_x <- xts(panel$BM_Ret_m, order.by = panel$date)
bm_ta <- table.AnnualizedReturns(bm_x, scale = 12, Rf = 0)
bm_mdd <- as.numeric(maxDrawdown(bm_x))
cat(sprintf("[5] BM (2004-02..2026-04): CAGR=%.4f Vol=%.4f SR=%.4f MDD=%.4f\n",
            as.numeric(bm_ta[1,1]), as.numeric(bm_ta[2,1]), as.numeric(bm_ta[3,1]), bm_mdd))
cat("    production reference: CAGR=0.0972 Vol=0.2138 SR=0.4544 MDD=0.4852\n")

# ------------------------------------------------------------
# [6] Windows
# ------------------------------------------------------------
win_def <- list(
  FULL_267m     = rep(TRUE, nrow(panel)),
  IS_2005_2018  = panel$realized_ym >= "2005-01" & panel$realized_ym <= "2018-12",
  OOS_2019_2026 = panel$realized_ym >= "2019-01",
  SUB2017_2026  = panel$realized_ym >= "2017-01"
)
stopifnot(sum(win_def$IS_2005_2018) == 168, sum(win_def$OOS_2019_2026) == 88,
          sum(win_def$SUB2017_2026) == 112)

# ------------------------------------------------------------
# [7] build_bt_result + audit per arm x window (contract path)
# ------------------------------------------------------------
mk_spec <- function(arm_label) list(
  strategy_id = sprintf("STR_1715_AR_M4_R05_L5_%s", arm_label),
  strategy_name = sprintf("STR_1715 L5 overlay - %s combine (Track F forge confirm)", arm_label),
  strategy_family = "overlay_combine",
  signal_description = paste("Sequential overlay on STR_1715 Iter31 baked PR:",
    "ret = beta_R05_V2 * g * ret_orig - 15bps*|dg| - 15bps*db_R05_V2;",
    if (arm_label == "O3") "g = g_inc if g_inc<0.25 else max(g_inc,0.5), INV-O1 deep-guard"
    else "g = beta_AR_lag * m4_weight_lag (incumbent product)"),
  universe_rule = "KOSPI200 + KOSDAQ150 (STR_1715 admit lineage, baked)",
  rebalance_frequency = "monthly",
  signal_date_rule = "t-1 EOM decision (all overlay paths lagged shift(1))",
  execution_date_rule = "month_start_t (production realized path)",
  weighting_method = "Iter31 linear_tilt baked in PR ret_net; overlay = cash-control scalar",
  max_position_weight = 0.20, max_leverage = 1.0,
  cash_rule = "overlay scalar g*beta_R05 in [0,1]; remainder cash (uncharged)",
  cost_model = "v2.4_kr_retail_15bps delta-based: uniform 15bps x |d g| + stored R05 leg; base costs inside ret_orig",
  missing_data_rule = "overlay paths NA -> 1.0 (no signal = full exposure)",
  risk_controls = "INV-O1 deep-guard: b_inc<0.25 months frozen to incumbent exposure",
  lookahead_prevention = "C1,C2,C5,C9,C11,C14 - t-1 lagged production realized paths (shift(1)); no re-estimation (INV-O3)",
  survivorship_bias_control = "inherited from STR_1715 production lineage (PIT universe, baked PR)"
)

build_arm_window <- function(arm, arm_label, wmask, win_label) {
  d   <- panel$date[wmask]
  net <- arm$net[wmask]
  grs <- if (!is.null(arm$gross)) arm$gross[wmask] else arm$net[wmask]
  DAILY_NAV_DT <- data.table(Date = d,
                             NAV = cumprod(1 + net),
                             NAV_gross = cumprod(1 + grs))
  strategy_xts <- xts(net, order.by = d); names(strategy_xts) <- "Strategy"
  bm_xts <- xts(panel$BM_Ret_m[wmask], order.by = d); names(bm_xts) <- "Benchmark"
  sim_result <- list(DAILY_NAV_DT = DAILY_NAV_DT,
                     PORTFOLIO_LOG = data.table(Exec_Date = d),
                     HOLDINGS_LOG = data.table(),
                     strategy_xts = strategy_xts, bm_xts = bm_xts)
  btr <- build_bt_result(sim_result, mk_spec(arm_label),
                         run_id = sprintf("TRACKF_%s_%s_20260612", arm_label, win_label),
                         strategy_id = sprintf("STR_1715_L5_%s", arm_label),
                         strategy_version = "trackF_v1",
                         benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
                         transaction_cost_bps = 15, slippage_bps = 0,
                         risk_free_rate = 0,
                         frequency = "monthly", annualization_factor = 12,
                         universe_id = "K200_KQ150_STR1715_lineage",
                         code_version = "run_trackF_forge_v1",
                         created_by_agent = "trackF_forge_agent")
  audit_bt_result(btr)
}

getm_  <- function(btr, nm) { M <- btr$metrics; as.numeric(M[metric_name == nm, metric_value][1]) }
getbc_ <- function(btr, nm) { B <- btr$benchmark_compare; as.numeric(B[metric_name == nm, active_value][1]) }

rows <- list(); builds <- list()
for (wn in names(win_def)) {
  for (al in c("INC", "O3")) {
    arm <- if (al == "INC") arm_inc else arm_o3
    btr <- build_arm_window(arm, al, win_def[[wn]], wn)
    builds[[paste(al, wn, sep = "_")]] <- btr
    crit_fail <- nrow(btr$audit[severity == "critical" & status == "FAIL"])
    # like-for-like (cycle1 method) values for the estimated-vs-backtested table
    xx <- xts(arm$net[win_def[[wn]]], order.by = panel$date[win_def[[wn]]])
    ta <- table.AnnualizedReturns(xx, scale = 12, Rf = 0)
    rows[[paste(al, wn)]] <- data.table(
      window = wn, arm = al, n_months = sum(win_def[[wn]]),
      SR = round(getm_(btr, "Sharpe"), 4),
      CAGR = round(getm_(btr, "CAGR"), 4),
      MDD = round(-getm_(btr, "MDD"), 4),
      Calmar = round(getm_(btr, "Calmar"), 4),
      PORT_t_NW3 = round(getbc_(btr, "Portfolio_Alpha_t_NW_lag3"), 3),
      PORT_t_p = signif(getbc_(btr, "Portfolio_Alpha_t_pvalue"), 3),
      IR = round(getbc_(btr, "Information_Ratio"), 4),
      TE = round(getbc_(btr, "Tracking_Error"), 4),
      ann_overlay_cost = round(mean(arm$cost[win_def[[wn]]]) * 12, 5),
      SR_ta_likeforlike = round(as.numeric(ta[3, 1]), 4),
      CAGR_ta_likeforlike = round(as.numeric(ta[1, 1]), 4),
      audit_integrity = btr$manifest$integrity_status[1],
      audit_critical_fails = crit_fail,
      metric_type = "backtested")
  }
}
res <- rbindlist(rows)
# deltas O3 vs INC per window
for (wn in names(win_def)) {
  inc_r <- res[window == wn & arm == "INC"]
  res[window == wn, `:=`(dSR_vs_inc = round(SR - inc_r$SR, 4),
                         dCAGR_vs_inc = round(CAGR - inc_r$CAGR, 4),
                         dMDD_pp_vs_inc = round((MDD - inc_r$MDD) * 100, 2),
                         dPORTt_vs_inc = round(PORT_t_NW3 - inc_r$PORT_t_NW3, 3),
                         dCost_vs_inc = round(ann_overlay_cost - inc_r$ann_overlay_cost, 5))]
}
cat("\n[7] forge-authoritative comparison table (metric_type=backtested):\n")
print(res, nrows = 50)
stopifnot(all(res$audit_critical_fails == 0))

# stored-convention incumbent FULL (traceability row)
x_st <- xts(arm_stored$net, order.by = panel$date)
ta_st <- table.AnnualizedReturns(x_st, scale = 12, Rf = 0)
stored_row <- list(SR_ta = round(as.numeric(ta_st[3,1]), 4),
                   CAGR_ta = round(as.numeric(ta_st[1,1]), 4),
                   MDD = round(-as.numeric(maxDrawdown(x_st)), 4),
                   ann_overlay_cost = round(mean(arm_stored$cost) * 12, 5))
cat(sprintf("[7] incumbent STORED-convention (traceability, FULL): SR=%.4f CAGR=%.4f MDD=%.4f cost=%.5f\n",
            stored_row$SR_ta, stored_row$CAGR_ta, stored_row$MDD, stored_row$ann_overlay_cost))

# ------------------------------------------------------------
# [8] essence_score on FULL builds (sweep, n_trials_cumulative=5)
# ------------------------------------------------------------
ess <- list()
for (al in c("INC", "O3")) {
  e <- essence_score(builds[[paste0(al, "_FULL_267m")]],
                     n_trials_cumulative = 5, selection_type = "sweep")
  ess[[al]] <- e
  cat(sprintf("\n[8] essence %s: grade=%s metric_type=%s\n    PORT_t=%.3f oos_retention=%s dsr=%s calmar=%.3f sharpe=%.3f cagr=%.3f mdd=%.3f\n    reasons=%s\n",
              al, e$grade, e$metric_type,
              e$essence$portfolio_alpha_t_nw_lag3,
              ifelse(is.na(e$essence$oos_retention), "NA", sprintf("%.3f", e$essence$oos_retention)),
              ifelse(is.na(e$essence$dsr), "NA", sprintf("%.3f", e$essence$dsr)),
              e$essence$calmar, e$essence$net_sharpe, e$essence$cagr, e$essence$mdd,
              e$reasons))
  cat(sprintf("    oos splits {55/65/75}: %s | band=%s | dsr_gate_applied=%s\n",
              paste(e$oos_retention_splits, collapse = " / "),
              e$oos_band_status, e$dsr_gate_applied))
}
gates <- function(e) list(
  PORT_t_ge_2.95 = isTRUE(e$essence$portfolio_alpha_t_nw_lag3 >= 2.95),
  oos_retention_ge_0.7 = isTRUE(is.finite(e$essence$oos_retention) && e$essence$oos_retention >= 0.7),
  calmar_ge_0.64 = isTRUE(e$essence$calmar >= 0.64),
  dsr_ge_0.5_sweep = isTRUE(is.finite(e$essence$dsr) && e$essence$dsr >= 0.5))
g_inc_gates <- gates(ess$INC); g_o3_gates <- gates(ess$O3)
cat("\n[8] graduation HARD gates (overlay variant: RELATIVE judgment primary):\n")
cat(sprintf("    %-22s INC=%s O3=%s\n", "PORT_t>=2.95", g_inc_gates$PORT_t_ge_2.95, g_o3_gates$PORT_t_ge_2.95))
cat(sprintf("    %-22s INC=%s O3=%s\n", "oos_retention>=0.7", g_inc_gates$oos_retention_ge_0.7, g_o3_gates$oos_retention_ge_0.7))
cat(sprintf("    %-22s INC=%s O3=%s\n", "calmar>=0.64", g_inc_gates$calmar_ge_0.64, g_o3_gates$calmar_ge_0.64))
cat(sprintf("    %-22s INC=%s O3=%s\n", "DSR>=0.5 (sweep)", g_inc_gates$dsr_ge_0.5_sweep, g_o3_gates$dsr_ge_0.5_sweep))

# ------------------------------------------------------------
# [9] estimated (cycle1) vs backtested (this run) reconciliation
# ------------------------------------------------------------
c1 <- fromJSON(file.path(ROOT, "04_Research/composition_search/cycle1_trackO/combine_ab_results.json"))
c1t <- as.data.table(c1$table)
map_arm <- c(O3_MIDBAND_FLOOR = "O3", INCUMBENT_REPRICED = "INC")
c1s <- c1t[arm %in% names(map_arm),
           .(window, arm_f = map_arm[arm], SR_est = SR, CAGR_est = CAGR,
             MDD_est = MDD, cost_est = ann_overlay_cost)]
disc <- merge(c1s,
              res[, .(window, arm_f = arm, SR_bt = SR_ta_likeforlike,
                      CAGR_bt = CAGR_ta_likeforlike, MDD_bt = MDD,
                      cost_bt = ann_overlay_cost,
                      SR_contract = SR, CAGR_contract = CAGR)],
              by = c("window", "arm_f"))
disc[, `:=`(dSR = round(SR_bt - SR_est, 4), dCAGR = round(CAGR_bt - CAGR_est, 4),
            dMDD = round(MDD_bt - MDD_est, 4), dCost = round(cost_bt - cost_est, 5))]
cat("\n[9] estimated (cycle1 recomposition) vs backtested (forge, like-for-like method):\n")
print(disc, nrows = 20)

# ------------------------------------------------------------
# [10] Persist
# ------------------------------------------------------------
saveRDS(builds$INC_FULL_267m, file.path(OUT, "bt_result_incumbent_FULL.rds"))
saveRDS(builds$O3_FULL_267m,  file.path(OUT, "bt_result_O3_FULL.rds"))
fwrite(res, file.path(OUT, "trackF_forge_comparison.csv"))

out <- list(
  task = "Track F - O3_MIDBAND_FLOOR forge-authoritative confirmation (Composition Search Cycle 2)",
  date = format(Sys.Date()),
  metric_type = "backtested",
  authority_note = paste("Full re-run from upstream sources (base PR + M4 + AR beta);",
                         "R05 leg AS STORED per INV-O2;",
                         "build_bt_result 10-component + audit_bt_result + essence_score;",
                         "uniform v2.4-delta cost convention (prereg)."),
  data_boundary = "2026-04-30 cutoff (panel native end 2026-04; BM cache cut at 2026-04-30; rawdata 2026-05+ contaminated, Track R repairing)",
  prereg_file = "04_Research/composition_search/cycle1_trackO/prereg_combine_candidates.json",
  selection_type = "sweep", n_trials_cumulative = 5,
  reconciliation_rebuilt_vs_stored_max_abs_diff = rec,
  inv_o1_audit = list(deep_guard_months = sum(deep),
                      deep_guard_max_abs_beta_diff = inv_o1_max_diff,
                      lift_months_o3 = lift_months),
  benchmark_sanity = list(bm_id = "KOSPI200 (.cache/benchmark.parquet, cut 2026-04-30)",
                          full_window = list(CAGR = round(as.numeric(bm_ta[1,1]),4),
                                             Vol = round(as.numeric(bm_ta[2,1]),4),
                                             SR = round(as.numeric(bm_ta[3,1]),4),
                                             MDD = round(bm_mdd,4)),
                          production_reference = list(CAGR = 0.0972, Vol = 0.2138,
                                                      SR = 0.4544, MDD = 0.4852)),
  incumbent_stored_convention_traceability_FULL = stored_row,
  forge_table = res,
  essence_FULL = list(
    INC = ess$INC[c("grade","metric_type","essence","hard_fail","n_trials_cumulative",
                    "selection_type","dsr_gate_applied","oos_stat_version",
                    "oos_retention_splits","oos_band_status","reasons")],
    O3  = ess$O3[c("grade","metric_type","essence","hard_fail","n_trials_cumulative",
                   "selection_type","dsr_gate_applied","oos_stat_version",
                   "oos_retention_splits","oos_band_status","reasons")]),
  graduation_gates_FULL = list(INC = g_inc_gates, O3 = g_o3_gates,
    note = "Overlay variant of incumbent book - relative judgment (O3 non-inferior + improving vs INC on identical gates) is primary; standalone gates reported for both arms"),
  estimated_vs_backtested = disc,
  caveats = c(
    "O3 band constants (0.25/0.5) derive from B2 full-sample diagnostic - design contamination; IS(2005-2018)/OOS(2019+) split reported, OOS was confirm-only in prereg",
    "R05 leg (beta_R05_V2/db_R05_V2/regime) consumed AS STORED per INV-O2; upstream admit-lineage parquet (stage_artifacts/WT_D20260425_010) absent on this machine - R05 signal not independently recomputed",
    "Uniform v2.4-delta cost convention re-prices incumbent slightly vs production stored series (production charged |d beta_AR| only); stored row kept for traceability",
    "holdings not modeled in bt_result (overlay = cash-control scalar on baked PR) - turnover audit WARN expected, stock-level holdings unchanged by design",
    "contract CAGR uses (final/initial)^(12/n)-1 on NAV (excludes month-1 return from ratio) - like-for-like rows use table.AnnualizedReturns for cycle1 comparison",
    "book_state/admission untouched - replacement decision is governor + Dohoon manual"),
  book_state_written = FALSE
)
write_json(out, file.path(OUT, "trackF_comparison.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 10, null = "null")
cat("\n[done] outputs:\n")
cat("  ", file.path(OUT, "bt_result_incumbent_FULL.rds"), "\n")
cat("  ", file.path(OUT, "bt_result_O3_FULL.rds"), "\n")
cat("  ", file.path(OUT, "trackF_forge_comparison.csv"), "\n")
cat("  ", file.path(OUT, "trackF_comparison.json"), "\n")
