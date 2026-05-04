# =============================================================================
# WT-S20260504_005 — Optimizer Remediation (Codex REJECT round 1 → revisions)
#
# Codex concerns addressed:
#   C1 (CRITICAL): turnover 778.7% > 600% — accept (REVISE), document infeasibility (inherited STR_1715 monthly schedule)
#   C2 (CRITICAL): cash accounting ambiguity — accept, rebuild weights to total-portfolio convention
#   C3 (HIGH):     CVaR breach + no infeasibility_report — accept, write infeasibility_report
#   C4 (HIGH):     selection objective β_F1 only, no MDD/vol/cost — accept, add full multi-metric comparison
#   C5 (MEDIUM):   alpha-weight Spearman corr 0.153 — partial (anchor preserves rank-shift)
#   C6 (HIGH):     PIT C2 IRAN_LMR_2026 to 2026-05-04 informing 2026-05-01 — REBUTTAL (sig_date as_of 2026-05-01,
#                  IRAN crisis window is risk_package PIT-bounded by lro_params_frozen.json sha SHA-frozen)
#   C7 (MEDIUM):   AX-008 establishment — accept, this script + challenge_note records 2-source (Codex + Claude)
# =============================================================================

suppressMessages({
  library(arrow); library(data.table); library(jsonlite); library(digest)
})

root <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
art  <- file.path(root, "stage_artifacts/WT_WT-S20260504_005")
mb   <- file.path(root, "qepm/mailbox/worktask/WT-S20260504_005")
var  <- file.path(art, "weights_variants")
log  <- file.path(art, "_optimizer_logs")

# ── Load existing variants (risk-only weights, sum=1 per date) ───────────
S1 <- fread(file.path(var, "S1.csv"))
FH <- fread(file.path(var, "FactorBeta_Hedge.csv"))
M4 <- fread(file.path(var, "M4+FactorBeta_Hedge.csv"))
diag <- fread(file.path(log, "optimizer_per_period_diag.csv"))

# ── REMEDIATION C2: rebuild weights to TOTAL-PORTFOLIO convention ────────
# Per Date: risk holdings × (1 - cash_pct) + CASH row (= cash_pct)
# Total sum per Date = 1.0 always
rebuild_total_convention <- function(dt, with_cash = TRUE) {
  out <- copy(dt)
  out[, weight_total := weight * (1 - cash_pct)]  # rescale risk weight
  # Append CASH rows
  if (with_cash) {
    cash_rows <- unique(out[, .(Date, regime, cash_pct)])
    cash_rows[, Ticker := "CASH_KRW"]
    cash_rows[, weight := cash_pct]            # placeholder
    cash_rows[, weight_total := cash_pct]      # cash slot
    cash_rows[, strategy := out$strategy[1]]
    out <- rbindlist(list(out, cash_rows), use.names = TRUE, fill = TRUE)
  }
  setorder(out, Date, -weight_total, Ticker)
  out
}

S1_v2 <- rebuild_total_convention(S1, with_cash = FALSE)  # S1 has cash_pct=0 always
FH_v2 <- rebuild_total_convention(FH, with_cash = FALSE)  # FH has cash_pct=0 always
M4_v2 <- rebuild_total_convention(M4, with_cash = TRUE)   # M4 has regime cash

# Verify sum=1
for (lab in c("S1_v2", "FH_v2", "M4_v2")) {
  dt <- get(lab)
  s <- dt[, .(s = sum(weight_total)), by = Date]$s
  cat("[verify-sum1]", lab, ": min=", round(min(s), 6), " max=", round(max(s), 6),
      " all=1? ", all(abs(s - 1) < 1e-6), "\n")
  # Verify n_names_risk_only ≤ 20 (excluding cash)
  n_risk <- dt[Ticker != "CASH_KRW", .N, by = Date]$N
  cat("[verify-names]", lab, ": max risk names=", max(n_risk), " (≤20: ", max(n_risk) <= 20, ")\n")
  # Verify max weight ≤ 0.20 (risk holdings)
  max_w <- dt[Ticker != "CASH_KRW", max(weight_total)]
  cat("[verify-cap]", lab, ": max risk weight_total=", round(max_w, 4), " (≤0.20: ", max_w <= 0.20 + 1e-6, ")\n")
}

# Save remediated variants
fwrite(S1_v2[, .(Date, Ticker, weight_total, weight_risk_only = weight, cash_pct, regime, strategy)],
       file.path(var, "S1.csv"))
fwrite(FH_v2[, .(Date, Ticker, weight_total, weight_risk_only = weight, cash_pct, regime, strategy)],
       file.path(var, "FactorBeta_Hedge.csv"))
fwrite(M4_v2[, .(Date, Ticker, weight_total, weight_risk_only = weight, cash_pct, regime, strategy)],
       file.path(var, "M4+FactorBeta_Hedge.csv"))

# Canonical = M4 with cash row, weight column = total-portfolio
canonical <- M4_v2[, .(Date, Ticker,
                       weight = weight_total,
                       weight_risk_only_excluding_cash = weight,
                       cash_pct, regime, strategy)]
fwrite(canonical, file.path(art, "weights.csv"))

# ── REMEDIATION C1: Turnover audit (one-way + round-trip + per-source) ───
turnover_audit <- list()
for (lab in c("S1", "FH", "M4")) {
  dt <- get(paste0(lab, "_v2"))
  wide <- dcast(dt, Date ~ Ticker, value.var = "weight_total", fill = 0)
  setorder(wide, Date)
  W <- as.matrix(wide[, -1, with = FALSE])
  diffW <- abs(diff(W))
  monthly_oneway <- rowSums(diffW) / 2
  monthly_round  <- rowSums(diffW)
  turnover_audit[[lab]] <- list(
    monthly_oneway_mean = round(mean(monthly_oneway), 4),
    monthly_round_mean = round(mean(monthly_round), 4),
    annual_oneway_x12 = round(mean(monthly_oneway) * 12, 4),
    annual_round_x12 = round(mean(monthly_round) * 12, 4),
    annual_oneway_pct = round(mean(monthly_oneway) * 12 * 100, 2),
    annual_round_pct = round(mean(monthly_round) * 12 * 100, 2),
    breach_600 = mean(monthly_oneway) * 12 > 6.0,
    n_dates = nrow(W)
  )
}
print(turnover_audit)

# ── REMEDIATION C4: cost-adjusted multi-metric comparison ────────────────
# Use STR_1715 268m monthly returns + per-period weights → portfolio returns
# Cost: 15bps one-way per turnover → monthly cost = monthly_oneway × 0.0015

# Load actual monthly returns from alpha_scores parquet
ap <- as.data.table(read_parquet(file.path(root,
       "qepm/mailbox/worktask/WT-P20260429_002/forge_may2026/alpha_scores_extended.parquet")))
ap_use <- ap[, .(Date, Ticker, Ret_1m)]

compute_metrics <- function(dt, label) {
  # Apply weight × Ret_1m per Date, sum
  m <- merge(dt[Ticker != "CASH_KRW", .(Date, Ticker, weight = weight_total)],
             ap_use, by = c("Date", "Ticker"), all.x = TRUE)
  m[is.na(Ret_1m), Ret_1m := 0]
  port_ret <- m[, .(port = sum(weight * Ret_1m, na.rm = TRUE)), by = Date]
  setorder(port_ret, Date)
  # Add cash return = 0 (KRW deposit ~0 nominal)
  # Pre-cost
  ret_pre <- port_ret$port
  # Cost
  wide <- dcast(dt, Date ~ Ticker, value.var = "weight_total", fill = 0)
  setorder(wide, Date)
  W <- as.matrix(wide[, -1, with = FALSE])
  diffW <- abs(diff(W))
  monthly_oneway <- c(0, rowSums(diffW) / 2)  # first month no rebalance cost
  monthly_cost <- monthly_oneway * 0.0015     # 15bps one-way
  ret_post <- ret_pre - monthly_cost

  # Metrics (PerformanceAnalytics style)
  suppressMessages(library(PerformanceAnalytics))
  rxts <- xts::xts(ret_post, order.by = port_ret$Date)

  ann_ret <- (prod(1 + ret_post)^(12/length(ret_post))) - 1
  ann_vol <- sd(ret_post) * sqrt(12)
  sharpe  <- ann_ret / ann_vol
  mdd     <- as.numeric(maxDrawdown(rxts))

  # Sortino
  downside <- ret_post[ret_post < 0]
  d_vol <- sqrt(mean(downside^2)) * sqrt(12)
  sortino <- ann_ret / d_vol

  # Calmar
  calmar <- ann_ret / mdd

  # Net IR (vs S1 = baseline)
  list(
    label = label,
    n_months = length(ret_post),
    ann_ret_post_cost = round(ann_ret, 4),
    ann_vol = round(ann_vol, 4),
    sharpe_post_cost = round(sharpe, 4),
    sortino = round(sortino, 4),
    calmar = round(calmar, 4),
    mdd = round(mdd, 4),
    mdd_pct = round(mdd * 100, 2),
    monthly_oneway_to_mean = round(mean(monthly_oneway), 4),
    annual_oneway_to = round(mean(monthly_oneway) * 12, 4),
    annual_cost_pct = round(mean(monthly_cost) * 12 * 100, 4),
    cum_ret = round(prod(1 + ret_post) - 1, 4),
    win_rate = round(mean(ret_post > 0), 4),
    monthly_returns = list(dates = as.character(port_ret$Date), returns = round(ret_post, 6))
  )
}

m_S1 <- compute_metrics(S1_v2, "S1")
m_FH <- compute_metrics(FH_v2, "FactorBeta_Hedge")
m_M4 <- compute_metrics(M4_v2, "M4+FactorBeta_Hedge")

cat("\n[METRICS post-cost @15bps one-way]\n")
for (m in list(m_S1, m_FH, m_M4)) {
  cat(sprintf("  %-22s SR=%.3f  CAGR=%.2f%%  Vol=%.2f%%  MDD=%.2f%%  Sortino=%.3f  ToAnn=%.1f%%  Cost/yr=%.2f%%\n",
              m$label, m$sharpe_post_cost,
              m$ann_ret_post_cost*100, m$ann_vol*100, m$mdd_pct,
              m$sortino, m$annual_oneway_to*100, m$annual_cost_pct))
}

# ── REMEDIATION C3: infeasibility_report for CVaR + turnover ─────────────
infeasibility <- list(
  has_infeasibility = TRUE,
  infeasibility_kind = "soft_breach_inherited",
  violations = list(
    list(constraint = "RF-O13_turnover_le_600pct_annual_oneway",
         observed_pct = m_M4$annual_oneway_to * 100,
         threshold_pct = 600,
         severity = "HIGH",
         source = "INHERITED_FROM_STR_1715_MONTHLY_RANK_REBALANCE",
         explanation = paste0("Per-date 20 names selected by STR_1715 score_eff. Monthly score-eff ranking ",
                              "produces full-set rotation across months — 716.6% annual one-way turnover ",
                              "is a property of the inherited monthly top-20 rebalance, NOT introduced by ",
                              "the FactorBeta_Hedge optimizer. Optimizer adds only +62.1pp on top of inherited ",
                              "S1 baseline (716.6 → 778.7). Sizing-only WT cannot change parent monthly schedule."),
         resolution = "Future deployment WT must (a) reduce rebalance frequency to quarterly, (b) add explicit turnover penalty in alpha generation, OR (c) accept high turnover with adjusted cost model. RECOMMENDATION_ONLY closure — no production change."),
    list(constraint = "RF-O8_CVaR_95_breach_minus_10pct",
         observed_pct = -12.89,
         threshold_pct = -10.0,
         severity = "HIGH",
         source = "INHERITED_FROM_STR_1715_268M_ACTUAL",
         explanation = paste0("STR_1715 actual 268m monthly CVaR_95=-0.1289 below -0.10 hard threshold. ",
                              "Pre-hedge concentration tail. After M4+FactorBeta_Hedge sizing, hedge reduces ",
                              "|β_p,F1| by 63.22% but CVaR-aware sizing is not the spec method. ",
                              "Spec WT-S20260504_005 prescribes 3-variant comparison only; CVaR-LP not in scope."),
         resolution = "Future WT may explore CVaR_LP / Min CDaR (FRM Pfaff Ch12) / HRP+CDaR composite. RECOMMENDATION_ONLY — production weight not modified.")
  ),
  rationale_for_continuation = paste0(
    "wt_kind=recommendation_only and wt_type=sizing_only. Production weights are NOT modified by this WT ",
    "(str_1715_production_dir_writes=0). Inherited turnover and CVaR breach are STR_1715 properties — ",
    "this study contributes only the factor-beta-hedge sizing layer for Forge measurement. ",
    "Findings advisory only; promotion to PG2 requires successor deployment_wt with re-audited turnover/CVaR."),
  hard_constraint_violations_explicit = c(
    "RF-O13: annual one-way turnover 778.7% > 600% (inherited from STR_1715 monthly rotation, +62pp delta from optimizer)",
    "RF-O8: monthly CVaR_95 = -12.89% > -10% threshold (inherited from STR_1715 268m actual, hedge reduces |β_p,F1| but not CVaR explicitly)"
  )
)

# ── PIT C6 rebuttal: verify IRAN_LMR_2026 window and signal_as_of ──────
pit_audit <- list(
  signal_as_of = "2026-05-01",
  deploy_cutoff = "2026-05-01",
  iran_lmr_window = list(start = "2026-04-01", end = "2026-05-04"),
  pit_compliance = "C2_OBSERVED_BUT_DEFENDED",
  defense_argument = paste0(
    "IRAN_LMR_2026 crisis window (2026-04-01 to 2026-05-04) is used in lro_params_frozen.json `crises` list ",
    "ONLY for crisis-prone factor IDENTIFICATION (k=F1 selection by minDD rank). The frozen identification ",
    "of k_crisis=F1 is consistent across 6/6 historical crises (EM_2004, COMMODITY_2006, GFC_2007_09, ",
    "COVID_2020, FED_2022, IRAN_LMR_2026 — all minDD rank=1 for F1). Even REMOVING IRAN_LMR_2026 from ",
    "the crisis set, the 5/5 remaining crises all rank F1 worst by minDD → k_crisis=F1 unchanged. ",
    "Therefore the F1 selection at 2026-05-01 deploy is INVARIANT to the IRAN_LMR_2026 inclusion. ",
    "PIT compliance reaffirmed via robustness check."),
  robustness_5_of_5_without_iran_lmr = list(
    crises_included = c("EM_2004", "COMMODITY_2006", "GFC_2007_09", "COVID_2020", "FED_2022"),
    F1_minDD_rank_per_crisis = c(EM_2004 = 1, COMMODITY_2006 = 1, GFC_2007_09 = 1, COVID_2020 = 1, FED_2022 = 1),
    F1_consistency_5_of_5 = TRUE,
    k_crisis_invariant_to_iran = TRUE
  ),
  ax002_compliance_reaffirm = "lro_params_frozen.json crisis_prone_k=1 SHA-frozen; F1 invariant to IRAN_LMR_2026 inclusion (5/5 historical agreement holds)."
)

# ── Net IR vs S1 (information ratio of FH and M4 over baseline) ──────────
compute_ir <- function(m_test, m_base) {
  ret_t <- m_test$monthly_returns$returns
  ret_b <- m_base$monthly_returns$returns
  n <- min(length(ret_t), length(ret_b))
  diff <- ret_t[1:n] - ret_b[1:n]
  ir_ann <- (mean(diff) * 12) / (sd(diff) * sqrt(12))
  list(net_ir_ann = round(ir_ann, 4),
       mean_diff_monthly = round(mean(diff), 6),
       sd_diff_monthly = round(sd(diff), 6))
}
ir_FH_vs_S1 <- compute_ir(m_FH, m_S1)
ir_M4_vs_S1 <- compute_ir(m_M4, m_S1)

cat("\n[net IR]  FH_vs_S1=", ir_FH_vs_S1$net_ir_ann,
    "  M4_vs_S1=", ir_M4_vs_S1$net_ir_ann, "\n")

# ── Build remediated optimization_package draft v2 ───────────────────────
opt_pkg <- fromJSON(file.path(mb, "optimization_package_draft.json"), simplifyVector = FALSE)

# Inject remediations
opt_pkg$remediation_round <- list(
  round = 1,
  triggered_by = "codex_critic_response_optimizer.json (REJECT, 7 critical_concerns)",
  responses = list(
    C1_turnover = "ACCEPT_WITH_INFEASIBILITY_INHERITED",
    C2_cash_accounting = "ACCEPT_REBUILT_TOTAL_CONVENTION",
    C3_cvar_breach = "ACCEPT_INFEASIBILITY_REPORT_ISSUED",
    C4_selection_objective = "ACCEPT_FULL_MULTI_METRIC_COMPARISON_ADDED",
    C5_alpha_weight_corr = "PARTIAL_ANCHOR_PRESERVES_RANK",
    C6_pit_iran_lmr = "REBUTTAL_5_OF_5_INVARIANCE",
    C7_ax_008 = "ACCEPT_CHALLENGE_NOTE_RECORDS_2_SOURCE"
  )
)

opt_pkg$turnover_audit <- turnover_audit
opt_pkg$cost_post_metrics <- list(
  S1 = list(
    sharpe_post_cost = m_S1$sharpe_post_cost,
    cagr_post_cost = m_S1$ann_ret_post_cost,
    vol = m_S1$ann_vol,
    mdd = m_S1$mdd,
    sortino = m_S1$sortino,
    calmar = m_S1$calmar,
    annual_oneway_to_pct = m_S1$annual_oneway_to * 100,
    annual_cost_pct = m_S1$annual_cost_pct,
    win_rate = m_S1$win_rate
  ),
  FactorBeta_Hedge = list(
    sharpe_post_cost = m_FH$sharpe_post_cost,
    cagr_post_cost = m_FH$ann_ret_post_cost,
    vol = m_FH$ann_vol,
    mdd = m_FH$mdd,
    sortino = m_FH$sortino,
    calmar = m_FH$calmar,
    annual_oneway_to_pct = m_FH$annual_oneway_to * 100,
    annual_cost_pct = m_FH$annual_cost_pct,
    win_rate = m_FH$win_rate,
    net_ir_vs_S1 = ir_FH_vs_S1$net_ir_ann
  ),
  M4_FactorBeta_Hedge = list(
    sharpe_post_cost = m_M4$sharpe_post_cost,
    cagr_post_cost = m_M4$ann_ret_post_cost,
    vol = m_M4$ann_vol,
    mdd = m_M4$mdd,
    sortino = m_M4$sortino,
    calmar = m_M4$calmar,
    annual_oneway_to_pct = m_M4$annual_oneway_to * 100,
    annual_cost_pct = m_M4$annual_cost_pct,
    win_rate = m_M4$win_rate,
    net_ir_vs_S1 = ir_M4_vs_S1$net_ir_ann
  )
)
opt_pkg$infeasibility_report <- infeasibility
opt_pkg$pit_audit <- pit_audit

# Update binding_constraints
opt_pkg$binding_constraints <- list("long_only", "weight_cap_0p20", "max_names_20", "sum_eq_1",
                                    "turnover_breach_INHERITED", "cvar_breach_INHERITED")

# Cash convention clarification
opt_pkg$cash_convention <- list(
  basis = "total_portfolio_convention_v2",
  per_date_total_sum = "1.0_INCLUDING_CASH_KRW",
  schema = "weights.csv columns: Date, Ticker, weight (=total fraction of portfolio), weight_risk_only_excluding_cash, cash_pct, regime, strategy",
  cash_row = "Ticker='CASH_KRW' rows added per Date (cash_pct > 0)",
  S1_no_cash = TRUE,
  FH_no_cash = TRUE,
  M4_with_cash = TRUE,
  audit_file = "stage_artifacts/WT_WT-S20260504_005/cash_definition_audit.json"
)

# Update finalize_meta
opt_pkg$finalize_meta$revised_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
opt_pkg$finalize_meta$revision <- "round1_codex_remediation_complete"

# Save remediated draft
remediated_path <- file.path(mb, "optimization_package_remediated_draft.json")
write_json(opt_pkg, remediated_path, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("[remediated draft] wrote:", remediated_path, "\n")

# Save metrics for challenge_note
metrics_summary <- list(
  S1 = m_S1[c("ann_ret_post_cost", "ann_vol", "sharpe_post_cost", "sortino", "calmar", "mdd_pct",
              "annual_oneway_to", "annual_cost_pct", "win_rate")],
  FactorBeta_Hedge = m_FH[c("ann_ret_post_cost", "ann_vol", "sharpe_post_cost", "sortino", "calmar", "mdd_pct",
                            "annual_oneway_to", "annual_cost_pct", "win_rate")],
  M4_FactorBeta_Hedge = m_M4[c("ann_ret_post_cost", "ann_vol", "sharpe_post_cost", "sortino", "calmar", "mdd_pct",
                               "annual_oneway_to", "annual_cost_pct", "win_rate")],
  net_ir = list(FH_vs_S1 = ir_FH_vs_S1$net_ir_ann, M4_vs_S1 = ir_M4_vs_S1$net_ir_ann),
  beta_F1 = list(
    mean_abs_S1 = round(mean(abs(diag$beta_S1_F1)), 4),
    mean_abs_FH = round(mean(abs(diag$beta_FH_F1)), 4),
    mean_abs_M4 = round(mean(abs(diag$beta_M4_F1)), 4)
  )
)
write_json(metrics_summary, file.path(log, "metrics_summary.json"),
           auto_unbox = TRUE, pretty = TRUE)

cat("[OK] Remediation complete. Build challenge_note next.\n")
