# ============================================================
# Track O combine A/B measurement (Composition Search Cycle 1)
# Preregistered candidates ONLY:
#   04_Research/composition_search/cycle1_trackO/prereg_combine_candidates.json
#   (frozen 2026-06-12T07:55:41+09:00, 5 candidates, sweep, n_trials=5)
# Method: realized-path recomposition (v24_book_remeasure precedent).
#   ret_cand_t = beta_R05_V2_t * g_cand_t * ret_orig_t
#                - 0.0015*|delta g_cand_t| - 0.0015*db_R05_V2_t
#   Uniform cost convention applied to all candidates AND incumbent
#   reference (production charged |delta beta_AR| only - both rows kept).
# metric_type = estimated (NOT forge-authoritative; grades nothing).
# PerformanceAnalytics standard functions only (table.AnnualizedReturns,
# maxDrawdown). ASCII output only.
# ============================================================
suppressPackageStartupMessages({
  library(data.table)
  library(xts)
  library(PerformanceAnalytics)
  library(jsonlite)
})

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PROD <- file.path(ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
OUT  <- file.path(ROOT, "04_Research/composition_search/cycle1_trackO")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# ------------------------------------------------------------
# [1] Load realized layer5 panel (production = READ-ONLY source)
# ------------------------------------------------------------
l5 <- fread(file.path(PROD, "04_backtest_results/period_returns_layer5.csv"))
l5[, anchor_date := as.Date(anchor_date)]
setorder(l5, anchor_date)
stopifnot(nrow(l5) == 267)

# ------------------------------------------------------------
# [2] Baseline integrity: recompose stored ret_L5_V2 (must be <1e-12)
# ------------------------------------------------------------
l5[, recomp := beta_R05_V2 * beta_threshold_lag * m4_weight_lag * ret_orig -
      db_thr * 0.0015 - db_R05_V2 * 0.0015]
base_resid <- max(abs(l5$recomp - l5$ret_L5_V2))
cat(sprintf("[2] baseline L5_V2 recomposition max|resid| = %.3e\n", base_resid))
stopifnot(base_resid < 1e-12)

# cost-leg identities (prereg verified_identities re-check)
dthr <- c(0, abs(diff(l5$beta_threshold_lag)))
dr05 <- c(0, abs(diff(l5$beta_R05_V2)))
id_thr <- max(abs(l5$db_thr - dthr))
id_r05 <- max(abs(l5$db_R05_V2 - dr05))
cat(sprintf("[2] db_thr==|d beta_AR| max|resid| = %.3e | db_R05==|d beta_R05| = %.3e\n",
            id_thr, id_r05))

# ------------------------------------------------------------
# [3] Incumbent paths + deep-guard mask (INV-O1)
# ------------------------------------------------------------
l5[, g_inc := beta_threshold_lag * m4_weight_lag]   # AR x M4 product (combine under test)
l5[, b_inc := g_inc * beta_R05_V2]                  # incumbent total exposure
deep <- l5$b_inc < 0.25
cat(sprintf("[3] deep-guard months (b_inc<0.25) = %d (prereg expects 6)\n", sum(deep)))
stopifnot(sum(deep) == 6)

# ------------------------------------------------------------
# [4] Candidate combine schedules (prereg formulas, frozen constants)
# ------------------------------------------------------------
RHO <- 0.4951  # B2 frozen diagnostic constant (NOT fitted)
bAR <- l5$beta_threshold_lag
m4  <- l5$m4_weight_lag
eps <- 1e-12

g_list <- list(
  O1_MIN_DEDUP      = pmin(bAR, m4),
  O2_M4_PRIORITY_OR = ifelse(m4 < 1 - eps, m4, bAR),
  O3_MIDBAND_FLOOR  = ifelse(l5$g_inc < 0.25, l5$g_inc, pmax(l5$g_inc, 0.5)),
  O4_POWER_RHO      = (bAR * m4)^(1 / (1 + RHO)),
  O5_BLEND_RHO      = (1 - RHO) * (bAR * m4) + RHO * pmin(bAR, m4)
)

# INV-O1 deep-guard override: g_cand := g_inc on deep months
for (nm in names(g_list)) g_list[[nm]][deep] <- l5$g_inc[deep]

# reference arm (re-priced incumbent under uniform convention)
g_list_all <- c(g_list, list(INCUMBENT_REPRICED = l5$g_inc))

# ------------------------------------------------------------
# [5] Series construction under UNIFORM cost convention
#   delta g at t=1 vs initial exposure 1.0 (production: first row betas=1)
# ------------------------------------------------------------
mk_series <- function(g) {
  dg   <- abs(diff(c(1, g)))                       # t=1 vs initial 1.0
  cost <- 0.0015 * dg + 0.0015 * l5$db_R05_V2      # uniform legs + stored R05 leg
  list(ret  = l5$beta_R05_V2 * g * l5$ret_orig - cost,
       cost = cost, g = g)
}
arms <- lapply(g_list_all, mk_series)

# context + traceability rows (NOT trials)
arms$INCUMBENT_STORED <- list(ret  = l5$ret_L5_V2,
                              cost = l5$db_thr * 0.0015 + l5$db_R05_V2 * 0.0015,
                              g    = l5$g_inc)
arms$BASE_NO_OVERLAY  <- list(ret = l5$ret_orig, cost = rep(0, nrow(l5)), g = rep(1, nrow(l5)))

# ------------------------------------------------------------
# [6] Mandatory audits (prereg evaluation_prereg$mandatory_audits)
# ------------------------------------------------------------
audits <- list()
for (nm in names(g_list)) {
  b_cand <- g_list[[nm]] * l5$beta_R05_V2
  audits[[nm]] <- list(
    deep_guard_max_abs_beta_diff = max(abs(b_cand[deep] - l5$b_inc[deep])),
    months_exposure_gt_incumbent = sum(g_list[[nm]] > l5$g_inc + eps),
    months_exposure_lt_incumbent = sum(g_list[[nm]] < l5$g_inc - eps)
  )
  cat(sprintf("[6] %-18s deep-guard max|b diff| = %.3e | lift months (g>g_inc) = %d | cut months = %d\n",
              nm, audits[[nm]]$deep_guard_max_abs_beta_diff,
              audits[[nm]]$months_exposure_gt_incumbent,
              audits[[nm]]$months_exposure_lt_incumbent))
  stopifnot(audits[[nm]]$deep_guard_max_abs_beta_diff == 0)
}
# incumbent repriced vs stored reconciliation
rec_diff <- arms$INCUMBENT_REPRICED$ret - arms$INCUMBENT_STORED$ret
cat(sprintf("[6] incumbent repriced-vs-stored: max|ret diff| = %.3e | mean ann cost diff = %.5f\n",
            max(abs(rec_diff)), mean(arms$INCUMBENT_REPRICED$cost - arms$INCUMBENT_STORED$cost) * 12))

# ------------------------------------------------------------
# [7] Windows + metrics (PerformanceAnalytics standard only)
# ------------------------------------------------------------
win_def <- list(
  IS_2005_2018   = l5$realized_ym >= "2005-01" & l5$realized_ym <= "2018-12",
  OOS_2019_2026  = l5$realized_ym >= "2019-01",
  FULL_267m      = rep(TRUE, nrow(l5)),
  SUB2017_2026   = l5$realized_ym >= "2017-01"
)
cat(sprintf("[7] window n: IS=%d OOS=%d FULL=%d SUB2017=%d\n",
            sum(win_def$IS_2005_2018), sum(win_def$OOS_2019_2026),
            sum(win_def$FULL_267m), sum(win_def$SUB2017_2026)))

metr <- function(r, dts) {
  x  <- xts(r, order.by = dts)
  ta <- table.AnnualizedReturns(x, scale = 12, Rf = 0)
  list(CAGR = as.numeric(ta[1, 1]), Vol = as.numeric(ta[2, 1]),
       SR = as.numeric(ta[3, 1]), MDD = -abs(as.numeric(maxDrawdown(x))))
}

calc_window <- function(wmask) {
  rows <- list()
  for (nm in names(arms)) {
    a <- arms[[nm]]
    m <- metr(a$ret[wmask], l5$anchor_date[wmask])
    rows[[nm]] <- data.table(arm = nm, n_months = sum(wmask),
                             SR = round(m$SR, 4), CAGR = round(m$CAGR, 4),
                             Vol = round(m$Vol, 4), MDD = round(m$MDD, 4),
                             ann_overlay_cost = round(mean(a$cost[wmask]) * 12, 5))
  }
  rbindlist(rows)
}

# --- [7a] IS first: compute + COMMIT selection before any OOS inspection ---
is_tab <- calc_window(win_def$IS_2005_2018)
cand_is <- is_tab[arm %in% names(g_list)]
best_sr <- max(cand_is$SR)
tied <- cand_is[SR > best_sr - 0.005]
winner <- if (nrow(tied) > 1) tied[which.min(MDD), arm] else cand_is[which.max(SR), arm]
tie_break_used <- nrow(tied) > 1
sel_commit <- list(committed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                   rule = "argmax IS net SR; tie |dSR|<0.005 -> lower IS MDD",
                   is_table_candidates = cand_is,
                   tie_break_used = tie_break_used,
                   selected = winner,
                   note = "committed BEFORE OOS/FULL/SUB2017 computation (prereg selection_rule)")
write_json(sel_commit, file.path(OUT, "is_selection_commit.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 10)
cat(sprintf("\n[7a] IS selection COMMITTED: %s (tie_break_used=%s)\n", winner, tie_break_used))
print(cand_is)

# --- [7b] now the remaining windows ---
all_tabs <- list()
for (wn in names(win_def)) {
  tb <- calc_window(win_def[[wn]])
  tb[, window := wn]
  # deltas vs incumbent repriced (same window)
  inc <- tb[arm == "INCUMBENT_REPRICED"]
  tb[, dSR_vs_inc      := round(SR - inc$SR, 4)]
  tb[, dCAGR_vs_inc    := round(CAGR - inc$CAGR, 4)]
  tb[, dMDD_pp_vs_inc  := round((MDD - inc$MDD) * 100, 2)]
  tb[, dCost_vs_inc    := round(ann_overlay_cost - inc$ann_overlay_cost, 5)]
  all_tabs[[wn]] <- tb
}
res <- rbindlist(all_tabs)
setcolorder(res, c("window", "arm", "n_months", "SR", "CAGR", "Vol", "MDD",
                   "ann_overlay_cost", "dSR_vs_inc", "dCAGR_vs_inc",
                   "dMDD_pp_vs_inc", "dCost_vs_inc"))
cat("\n[7b] full A/B table (metric_type=estimated)\n")
print(res, nrows = 200)

# ------------------------------------------------------------
# [8] OOS confirmation (prereg rule) for committed winner
# ------------------------------------------------------------
oos <- all_tabs$OOS_2019_2026
w_oos   <- oos[arm == winner]
inc_oos <- oos[arm == "INCUMBENT_REPRICED"]
sr_ok  <- w_oos$SR  >= inc_oos$SR - 0.05
mdd_ok <- w_oos$MDD >= inc_oos$MDD - 0.03   # MDD negative: candidate MDD <= inc MDD + 3pp abs
oos_confirmed <- sr_ok && mdd_ok
cat(sprintf("\n[8] OOS confirm %s: SR %.4f vs inc %.4f (>=inc-0.05: %s) | MDD %.4f vs inc %.4f (<=inc+3pp: %s) -> %s\n",
            winner, w_oos$SR, inc_oos$SR, sr_ok, w_oos$MDD, inc_oos$MDD, mdd_ok,
            ifelse(oos_confirmed, "CONFIRMED", "FAIL")))

# ------------------------------------------------------------
# [9] DSR diagnostic (BLdP 2014, essence_score.R formula, n_trials=5)
# ------------------------------------------------------------
.dsr <- function(sr_ann, n_obs, n_trials, skew = 0, kurt = 3, A = 12) {
  if (!is.finite(sr_ann) || !is.finite(n_obs) || n_obs < 12) return(NA_real_)
  emc <- 0.5772156649
  sr_m <- sr_ann / sqrt(A)
  var0 <- 1 / (n_obs - 1)
  z1 <- qnorm(1 - 1 / n_trials); z2 <- qnorm(1 - 1 / (n_trials * exp(1)))
  sr0 <- sqrt(var0) * ((1 - emc) * z1 + emc * z2)
  den <- sqrt(1 - skew * sr_m + (kurt - 1) / 4 * sr_m^2)
  if (!is.finite(den) || den <= 0) return(NA_real_)
  pnorm((sr_m - sr0) * sqrt(n_obs - 1) / den)
}
dsr_rows <- list()
for (nm in names(g_list)) {
  for (wn in c("IS_2005_2018", "FULL_267m")) {
    r <- arms[[nm]]$ret[win_def[[wn]]]
    sk <- as.numeric(PerformanceAnalytics::skewness(r, method = "moment"))
    ku <- as.numeric(PerformanceAnalytics::kurtosis(r, method = "moment"))
    sr_ann <- all_tabs[[wn]][arm == nm, SR]
    dsr_rows[[paste(nm, wn)]] <- data.table(
      arm = nm, window = wn, n_obs = length(r),
      skew = round(sk, 3), kurt_moment = round(ku, 3),
      DSR_ntrials5 = round(.dsr(sr_ann, length(r), 5, sk, ku), 4))
  }
}
dsr_tab <- rbindlist(dsr_rows)
cat("\n[9] DSR diagnostic (n_trials=5, sweep; gate binds only at graduation tier)\n")
print(dsr_tab)

# ------------------------------------------------------------
# [10] Persist results
# ------------------------------------------------------------
fwrite(res, file.path(OUT, "combine_ab_results.csv"))
out <- list(
  task = "Track O combine A/B (Composition Search Cycle 1, B3 overlay combine redesign)",
  date = format(Sys.Date()),
  metric_type = "estimated",
  note_authority = "realized-path recomposition (v24_book_remeasure precedent); forge-authoritative re-run required before any graduation/admission claim",
  prereg_file = "04_Research/composition_search/cycle1_trackO/prereg_combine_candidates.json",
  selection_type = "sweep", n_trials = 5,
  integrity = list(
    baseline_L5V2_recomposition_max_resid = base_resid,
    db_thr_identity_max_resid = id_thr,
    db_R05_identity_max_resid = id_r05,
    deep_guard_months = sum(deep)
  ),
  cost_convention = "UNIFORM 15bps x |delta g_cand| + stored R05 leg (incumbent re-priced identically; stored row kept for traceability)",
  incumbent_reconciliation = list(
    max_abs_ret_diff_repriced_vs_stored = max(abs(rec_diff)),
    ann_cost_diff_repriced_minus_stored = mean(arms$INCUMBENT_REPRICED$cost - arms$INCUMBENT_STORED$cost) * 12
  ),
  audits_inv_o1 = audits,
  is_selection = list(selected = winner, tie_break_used = tie_break_used,
                      committed_file = "is_selection_commit.json"),
  oos_confirmation = list(selected = winner,
                          oos_sr = w_oos$SR, incumbent_oos_sr = inc_oos$SR, sr_rule_pass = sr_ok,
                          oos_mdd = w_oos$MDD, incumbent_oos_mdd = inc_oos$MDD, mdd_rule_pass = mdd_ok,
                          confirmed = oos_confirmed),
  dsr_diagnostic = dsr_tab,
  table = res
)
write_json(out, file.path(OUT, "combine_ab_results.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 10)
cat("\n[done] outputs written:\n  ", file.path(OUT, "combine_ab_results.csv"),
    "\n  ", file.path(OUT, "combine_ab_results.json"), "\n")
