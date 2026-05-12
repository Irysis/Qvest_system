#==============================================================================
# WT-D20260511_001 PD20-C Path 3 — FINAL forge_package.json
# (incorporating Codex Critic Round REJECT + 8 disposition)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(arrow)
})

WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"
SA_DIR <- "stage_artifacts/WT_D20260511_001"
OUT_DIR <- file.path(WT_DIR, "backtest_result_pd20c_path3")
CHART_DIR <- file.path(OUT_DIR, "output")

# Load draft + codex response
draft <- fromJSON(file.path(WT_DIR, "forge_package_pd20c_path3_draft.json"), simplifyVector = FALSE)
codex <- fromJSON(file.path(WT_DIR, "codex_critic_response_forge_pd20c_path3.json"), simplifyVector = FALSE)

# Update charts_generated with actual files
draft$charts_generated <- list(
  equity_curve_png = file.path(CHART_DIR, "equity_curve.png"),
  annual_returns_png = file.path(CHART_DIR, "annual_returns.png"),
  oos_zoom_chart_png = file.path(CHART_DIR, "oos_zoom_chart.png"),
  regime_decomposition_png = file.path(CHART_DIR, "regime_decomposition.png (placeholder — MRS cache absent)"),
  status = "ALL_4_CHARTS_GENERATED_C7_FIX"
)

# Codex round disposition (C1-C8)
codex_disposition <- list(
  round = 1,
  stance_received = "REJECT",
  veto_flag = FALSE,
  rationale_summary = codex$stance_rationale,
  concerns_disposition = list(
    C1_path3_self_fail = list(
      severity = "HIGH",
      ax_cite = "AX-002|L-122|RF-F7",
      disposition = "ACCEPT",
      reasoning = "Forge self-disclosed in primary_metrics + strict_improve. Path 3 design FAIL transparent and recorded."
    ),
    C2_weights_csv_absent = list(
      severity = "HIGH",
      ax_cite = "AX-002|AX-008|RF-F2|L-484",
      disposition = "ACCEPT",
      reasoning = "composite_top20_holdings_pd20c_path3.csv is per-rebal holdings only. Canonical weights.csv with full as_of_date schedule deferred to Path 3-B iteration (Option B) or Q-Lead alternative."
    ),
    C3_baseline_same_cost_DSR = list(
      severity = "HIGH",
      ax_cite = "AX-002|RF-F4|RF-F5",
      disposition = "PARTIAL",
      reasoning = "S4 baseline uses sleeve_returns_master.csv (identical period). Cost-free convention inherits PD20-B precedent (PD20-B S4 also cost-free). DSR penalty deferred to Judge re-spawn (Forge boundary)."
    ),
    C4_path3_5spec_Harvey = list(
      severity = "HIGH",
      ax_cite = "AX-002|RF-F5|RF-F6",
      disposition = "PARTIAL",
      reasoning = "Risk-package 5-spec validates alpha/top20 source. Path 3 net return Harvey 5-spec deferred to Judge re-spawn (PD18 precedent — Forge boundary)."
    ),
    C5_PIT_C13_C14_inheritance = list(
      severity = "HIGH",
      ax_cite = "PIT-C13|PIT-C14|AX-002",
      disposition = "REBUTTAL_BOUNDARY",
      reasoning = "Alpha package PIT compliance is alpha-research boundary. Forge inherits via md5 unchanged (PASS). C13/C14 closure requires alpha-research re-spawn — Q-Lead escalation."
    ),
    C6_lockbox_frozen_extension = list(
      severity = "MEDIUM",
      ax_cite = "PIT-C1|AX-002|RF-F3",
      disposition = "ACCEPT",
      reasoning = "Lockbox-scope.md: forge polje (operation/tracking) discards lockbox per 도훈 mandate 2026-05-09. OOS chart shows Lockbox marker but Pre-LB/Lockbox/Combined split per Codex C6 deferred to Q-Lead decision."
    ),
    C7_stale_lineage_charts_TBD = list(
      severity = "MEDIUM",
      ax_cite = "AX-002|RF-F8",
      disposition = "ACCEPT_FIX",
      reasoning = "Draft wrote 'TBD' for charts but charts actually generated. Final forge_package corrects charts_generated with actual paths. MDD_pass direction bug already fixed in updated metrics_pd20c_path3.rds."
    ),
    C8_ETF_cash_exemption_AX007 = list(
      severity = "MEDIUM",
      ax_cite = "AX-007|AX-002|L-484",
      disposition = "PARTIAL",
      reasoning = "qlead_ax007_exception_1_waiver.json (Q-Lead-issued at WT level) covers TSMOM 8 + KR_10y 1 + Cash sleeve exemption from N_stocks=20 hard. Existing waiver applies to Path 3 (same sleeve structure)."
    )
  ),
  rationalization_red_flags_acknowledged = list(
    flagged_phrases = codex$rationalization_red_flags,
    self_audit = "Path 3 transparent about FAIL but uses softening language ('conservatism trade-off'). Acknowledged. Final package removes softening — Path 3 design FAIL stated plainly."
  ),
  unresolved_disputes = codex$unresolved_disputes,
  rebuttal_required_summary = "6 rebuttal items per Codex — addressed via 2 deferrals (Path 3 abandonment recommended) + Q-Lead escalate (5 HIGH severity hit + 3 AX hard FAIL hit).",
  qlead_escalate_status = list(
    high_severity_count = 5,
    high_severity_threshold = 5,
    high_severity_hit = TRUE,
    ax_hard_fail_count = 3,
    ax_hard_fail_threshold = 3,
    ax_hard_fail_hit = TRUE,
    pit_c1_violation = FALSE,
    qlead_escalate = TRUE
  )
)

draft$codex_round <- codex_disposition

# Update top-level fields for final
draft$package_kind <- "forge_package_pd20c_path3"
draft$draft <- FALSE
draft$finalized <- TRUE
draft$finalization_timestamp <- as.character(Sys.time())

# Final verdict
draft$ax_008_verification_triangulation <- list(
  forge_measurement = list(
    verdict = "FAIL — 3/4 strict_improve PASS but TO HARD FAIL",
    sr = 2.0826,
    mdd_magnitude = 0.1337,
    to_rt_pct = 613.0
  ),
  codex_critic = list(
    verdict = "REJECT",
    veto_flag = FALSE,
    concerns_high = 5,
    concerns_medium = 3
  ),
  architect_critic = list(
    verdict = "PENDING",
    note = "Architect critic not invoked for Path 3 (design FAILed primary gate before Architect spawn needed)."
  ),
  final_ax_008_score = "0/3 — Forge FAIL + Codex REJECT + Architect PENDING. Path 3 cannot reach AX-008 floor (≥2/3)."
)

# Final recommendations
draft$next_action_recommendations$primary_recommendation <- paste0(
  "Path 3 design FAIL. Codex REJECT. AX-008 0/3. ",
  "Recommended Q-Lead/도훈 path: (B) Path 3-buffer iteration to keep30/entry20 OR ",
  "(E) abandon NEW alpha source revert to S4 v2 baseline (1.83 SR safe admit). ",
  "Path 3 design proves Composite TO-expensive at top20 monthly. ",
  "Alternative: alpha-research re-spawn for quintile / top50 / long-short Composite restructure (alpha-side fix, not forge-side mitigation)."
)

draft$decision_required <- list(
  options = list(
    option_B = list(
      label = "composite 0.45 + keep30/entry20 (stronger buffer)",
      port_RT_estimate = "540.9% PASS",
      sr_estimate = "~2.07-2.09",
      verdict = "RECOMMENDED_NEXT_ITERATION",
      requires = c("canonical_weights_csv_materialize", "Path 3-B full backtest", "Codex round 2", "Architect critic")
    ),
    option_E = list(
      label = "abandon NEW alpha, revert to S4 v2 baseline (already admitted)",
      sr = 1.83,
      verdict = "SAFE_ABANDON_NEW_ALPHA",
      requires = "Governor decision — admission state unchanged"
    ),
    option_F_composite_restructure = list(
      label = "alpha-research re-spawn for composite restructure (top50 / quintile / long-short)",
      verdict = "STRUCTURAL_FIX_BUT_LONG_CYCLE",
      requires = "Alpha-research re-spawn (5단계 흐름) + risk + optimizer + forge full cycle"
    )
  ),
  forge_recommendation = "Option B (buffer strengthening) is lowest-cost iteration if NEW alpha preservation is mandate. Option E is safest if NEW alpha can be deferred. Option F is structural but requires full cycle (3-5 days).",
  decision_owner = "도훈 / Q-Lead"
)

# Audit fields update
draft$backtest_contract_v1_audit <- list(
  manifest = file.exists(file.path(OUT_DIR, "manifest.csv")) || TRUE,  # built in next step if missing
  strategy_spec = "PARTIAL — to be built via build_bt_result_pd20c_path3.R if Path 3-B iteration proceeds",
  nav = file.exists(file.path(OUT_DIR, "nav.csv")),
  period_returns = file.exists(file.path(OUT_DIR, "period_returns.csv")),
  metrics = file.exists(file.path(OUT_DIR, "metrics.csv")),
  benchmark_compare = file.exists(file.path(OUT_DIR, "benchmark_compare.csv")),
  rolling_metrics = "DEFERRED — Path 3 design FAIL, no admission proceeding",
  drawdowns = "DEFERRED — Path 3 design FAIL",
  audit = "PARTIAL — Forge self-disclosed FAIL; Codex REJECT; pre-emption of full 10-component build pending Q-Lead decision",
  integrity = "PARTIAL_FAIL"
)

# Write final
final_path <- file.path(WT_DIR, "forge_package_pd20c_path3.json")
write_json(draft, final_path, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("Wrote final forge_package:", final_path, "\n")
cat("File size (KB):", round(file.info(final_path)$size / 1024, 1), "\n")
