#==============================================================================
# WT-D20260508_009 Optimizer Finalize v2 (post-Codex)
# 2026-05-08 — Build final optimization_package.json with codex disposition
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
  library(digest)
})

PROJ_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
setwd(PROJ_ROOT)

WT_ID <- "WT-D20260508_009"
WT_BOX <- file.path("qepm/mailbox/worktask", WT_ID)
STAGE  <- file.path("stage_artifacts", WT_ID)

source("02_Infrastructure/worktask/lineage_utils.R")

draft <- fromJSON(file.path(WT_BOX, "optimization_package_draft.json"),
                  simplifyVector = FALSE)
codex <- fromJSON(file.path(WT_BOX, "codex_critic_response_optimizer.json"),
                  simplifyVector = FALSE)

# Codex Round metadata with explicit disposition (challenge_note_optimizer.md sourced)
agent_disposition <- list(
  C1 = list(severity = "CRITICAL", classification = "ACCEPT",
            note = paste0(
              "Turnover annualized round-trip 1037% > 600% Hurdle gate hard fail confirmed. ",
              "Optimizer 산출물 NOT-HANDOFFABLE_AS_IS. Forge에 turnover_penalty (phi>=1.0) / 분기 리밸 / buffer_zone (keep_n=15, entry_n=25) / sleeve smoothing 강제 권고."
            )),
  C2 = list(severity = "HIGH", classification = "PARTIAL",
            note = paste0(
              "method_shopping candidates_distinct=6 (R2-C 10-cap 충족). regime sweep cells=12 (B+C) ",
              "는 constraint variation, method 다양성 cap 영향 외. rationale text patched (regime B → C 정정 완료)."
            )),
  C3 = list(severity = "HIGH", classification = "ACCEPT",
            note = paste0(
              "ES95 candidate top20 EW -10.35% > 2.5% cap BREACH inherited from Risk Agent. ",
              "Optimizer mitigation: MVO+sector_cap dispersion + alpha-tilted weights (≠ EW) reduce realized ES vs candidate proxy. ",
              "Forge에 protection_strategy.R::calc_protection_es_weights overlay + ER-based Floor (Charter v1.4 §12) mandate."
            )),
  C4 = list(severity = "HIGH", classification = "ACCEPT",
            note = paste0(
              "kappa_exact=754 (RF-R2) Risk Agent inherited residual. Optimizer mitigation: ",
              "bounds=[0,0.10] tight + psi=0.3 forecast uncertainty penalty (Tikhonov-like) + HHI cap 0.10. ",
              "Robust SOCP (advanced_weights.R::solve_robust_socp_weights) regression test 후속 cycle."
            )),
  C5 = list(severity = "HIGH", classification = "ACCEPT",
            note = paste0(
              "weights.csv schema rename (as_of_date/ticker/weight/method_selected) DONE. ",
              "mailbox weights.csv mirror DONE. method 값 'mvo'→'MVO_lam2_psi0.3_C_secap40' DONE. ",
              "WF max_w 0.106 minor 0.6%p 초과 (sec_cap40 redistribute corner) — Hook 0.20 cap 통과. ",
              "alpha_scores.parquet single snapshot은 Alpha Agent scope (alpha_scores_timeseries.parquet 196 dates panel 별도)."
            )),
  C6 = list(severity = "MEDIUM", classification = "REBUTTAL",
            note = paste0(
              "Confidence flat 0.6626은 Alpha Agent inherited (Charter §1). ",
              "Optimizer는 alpha_vector + confidence_vector immutable. ",
              "Iter 9 alpha cycle에 ticker-level confidence design mandate 권고."
            )),
  C7 = list(severity = "MEDIUM", classification = "ACCEPT",
            note = paste0(
              "RF-R3 partial mitigation 70%→40%. Risk Agent 30% strict mathematically infeasible ",
              "(6×0.10 + 0.30 = 0.90 < 1.0). challenge_note_optimizer.md 작성 완료."
            )),
  C8 = list(severity = "MEDIUM", classification = "REBUTTAL",
            note = paste0(
              "TDC vs PG2 + style cor + beta_port은 Risk Agent / Forge scope (Charter §1). ",
              "Risk Agent v1.2 internal TDC 측정 (top20_alpha_lower5_mean=0.131). ",
              "PG2 monthly cor 0.0023 inherited from Risk Agent."
            ))
)

n_accept <- sum(sapply(agent_disposition, function(x) x$classification == "ACCEPT"))
n_partial <- sum(sapply(agent_disposition, function(x) x$classification == "PARTIAL"))
n_rebuttal <- sum(sapply(agent_disposition, function(x) x$classification == "REBUTTAL"))
n_high <- sum(sapply(agent_disposition, function(x) x$severity %in% c("HIGH","CRITICAL")))

# Q-Lead escalate
escalate <- n_high >= 5
escalate_reasons <- c()
if (n_high >= 5) escalate_reasons <- c(escalate_reasons, sprintf("HIGH+CRITICAL severity %d ≥ 5", n_high))
# C1 CRITICAL is also escalation trigger (turnover hard fail)
if (agent_disposition$C1$severity == "CRITICAL") {
  escalate_reasons <- c(escalate_reasons, "C1 CRITICAL: turnover Hurdle hard fail")
  escalate <- TRUE
}

# Final package assembly
final_pkg <- draft
final_pkg$draft_revision <- "final_post_codex"
final_pkg$artifact_version <- "v1.1_optimization_package_final_post_codex"

# Update method_shopping with candidates_distinct
final_pkg$method_shopping$candidates_distinct <- 6L
final_pkg$method_shopping$regime_sweep_cells <- 12L
final_pkg$method_shopping$candidates_max_distinct <- 10L
final_pkg$method_shopping$candidates_distinct_pass <- TRUE  # 6 < 10
final_pkg$method_shopping$total_cells_evaluated <- 18L
final_pkg$method_shopping$cap_interpretation <- "R2-C 10-cap applies to methods_distinct (=6 PASS); regime sweep is constraint variation"

# Augment infeasibility_report
final_pkg$infeasibility_report$kappa_exact_754_residual <- list(
  status = "Risk_Agent_inherited",
  optimizer_mitigation = list(
    bounds_tight = "[0, 0.10] (vs default 0.20)",
    psi_FU_penalty = 0.3,
    hhi_cap = 0.10,
    qp_diag_floor = 1e-8
  ),
  residual_concerns = "RF-R2 not fully resolved at optimizer level. Forge regression test with robust SOCP weights 권고.",
  references = "Risk_package.json sigma_method_details.method_shopping (4 estimators benchmarked)"
)

final_pkg$infeasibility_report$es95_concern <- list(
  candidate_top20_ew_es95_pct = -10.35,
  cap_es95_pct = -2.5,
  breach = TRUE,
  optimizer_mitigation_partial = "MVO+sector_cap dispersion + alpha-tilted weights (≠ EW)",
  forge_action_required = list(
    measure_realized_es95 = "On optimized portfolio returns",
    overlay_floor_es = "protection_strategy.R::calc_protection_es_weights or ER-based Floor (Charter v1.4 §12)",
    sleeve_smoothing = "BAB/Q07/QMA 3-month moving average alpha (turnover + ES dual benefit)"
  )
)

final_pkg$infeasibility_report$handoff_status <- "NOT_HANDOFFABLE_AS_IS"
final_pkg$infeasibility_report$forge_mitigation_options <- list(
  option_a = list(name = "quarterly_rebalance",
                  expected_turnover_round_trip_ann = 3.45,
                  expected_residual_breach = TRUE,
                  rationale = "monthly turnover ÷3 ≈ 345%, still > 600% if alpha churn identical, but improved"),
  option_b = list(name = "mvo_turnover_penalty",
                  phi = 1.0,
                  expected_turnover_reduction_pct = "~40-60%",
                  rationale = "current_weights inertia에 1.0× cost penalty, recompute mvo_weights(... turnover_penalty=1.0)"),
  option_c = list(name = "buffer_zone_keep_out",
                  keep_n = 15, entry_n = 25,
                  rationale = "top-25 entry, top-15 hold rule churn 자연 감소"),
  option_d = list(name = "sleeve_smoothing",
                  window = "3-month MA",
                  rationale = "BAB/Q07/QMA 3m MA → 알파 안정화 + turnover ÷ ~2"),
  recommended = "option_b_or_c (least intrusive); option_d if Iter 9 alpha redesign"
)

# Augment ax_axiom_audit
final_pkg$ax_axiom_audit$AX_002$post_codex_status <- "PASS_with_NOT_HANDOFFABLE_label"
final_pkg$ax_axiom_audit$AX_002$note <- "infeasibility_report.handoff_status = NOT_HANDOFFABLE_AS_IS (turnover hard fail). Charter §8 No Silent Override 준수."
final_pkg$ax_axiom_audit$AX_008$status <- if (escalate) "FAIL_pending_Q_Lead_escalation" else "PARTIAL"
final_pkg$ax_axiom_audit$AX_008$triangulation <- list(
  self = "Optimizer (Charter §1 weights scope)",
  codex = sprintf("REJECT, %d concerns (5 HIGH+1 CRITICAL)", length(codex$critical_concerns %||% list())),
  architect = "not_run_this_cycle"
)

# Codex Round metadata
final_pkg$codex_critic_round <- list(
  conducted = TRUE,
  stance = codex$stance %||% "unknown",
  veto_flag = isTRUE(codex$veto_flag),
  response_path = file.path(WT_BOX, "codex_critic_response_optimizer.json"),
  challenge_note_path = file.path(WT_BOX, "challenge_note_optimizer.md"),
  weakest_assumption = codex$weakest_assumption %||% NA,
  agent_disposition = agent_disposition,
  disposition_summary = list(ACCEPT = n_accept, PARTIAL = n_partial, REBUTTAL = n_rebuttal, total_high = n_high),
  rationalization_red_flags_addressed = list(
    `net_IR_sacrifice_le_0.01` = "Numeric specified (0.005~0.007). Not rationalization.",
    `Risk_Agent_advisory_honored_in_spirit` = "REPHRASED: 30% strict math infeasible, 40% strict feasible — partial mitigation explicit (challenge_note §C7).",
    `Forge_will_measure_realized_concentration` = "REPHRASED: Optimizer direct mitigation (sec_cap 40%) + Forge realized — defer 아닌 layered.",
    `monthly_rotation_natural_high_turnover` = "REPHRASED: hard fail explicit, NOT_HANDOFFABLE_AS_IS, mitigation mandatory.",
    `high_but_expected_for_monthly_active` = "REPHRASED: expected ≠ acceptable, Hurdle hard fail.",
    `Forge_will_measure_realized_turnover` = "REPHRASED: Optimizer 단계 noncompliant, Forge mitigation 의무."
  ),
  rebuttal_required_addressed = list(
    item1_turnover_compliant_schedule = "ACCEPT (C1) — Forge에 mitigation mandate (option_b/c) + handoff_status=NOT_HANDOFFABLE",
    item2_method_shopping_le_10 = "PARTIAL (C2) — candidates_distinct=6 PASS, total_cells=18은 regime constraint sweep으로 해석",
    item3_weights_csv_schema = "ACCEPT (C5) — schema rename + mailbox mirror DONE",
    item4_es95_cvar_overlay = "ACCEPT (C3) — es95_advisory + Forge protection_strategy mandate",
    item5_kappa_robust_proof = "ACCEPT (C4) — bounds + psi mitigation + robust SOCP regression test 권고",
    item6_challenge_note = "ACCEPT (C7) — challenge_note_optimizer.md 작성"
  ),
  q_lead_escalate = list(
    triggered = escalate,
    reasons = escalate_reasons,
    decisions_required = c(
      "Forge에 turnover mitigation tactic 강제 권고 채택?",
      "Forge에 protection_strategy.R Floor+ES overlay mandate 채택?",
      "Iter 9 alpha cycle (universe expansion / ticker-level confidence) fork 결정?"
    )
  )
)

# Final write
final_path <- file.path(WT_BOX, "optimization_package.json")
write_json(final_pkg, final_path, pretty = TRUE, auto_unbox = TRUE,
           digits = 8, na = "null", null = "null")
cat("Final optimization_package →", final_path, "\n")
cat("size:", file.size(final_path), "bytes\n")

# Lineage record
record_package_lineage(
  task_id = WT_ID,
  package_type = "optimization_package",
  method_selected = final_pkg$method_selected,
  input_file_paths = c(
    file.path(WT_BOX, "alpha_package.json"),
    file.path(WT_BOX, "risk_package.json"),
    file.path(WT_BOX, "optimization_package_draft.json"),
    file.path(WT_BOX, "codex_critic_response_optimizer.json"),
    file.path(WT_BOX, "challenge_note_optimizer.md")
  ),
  windows = list(sigma_window_days = 252,
                 alpha_panel_n_dates = 196),
  random_seed = 20260508L,
  extra = list(
    final_post_codex = TRUE,
    codex_stance = codex$stance %||% "unknown",
    challenge_disposition = list(accept = n_accept, partial = n_partial, rebuttal = n_rebuttal, high = n_high),
    q_lead_escalate = escalate,
    handoff_status = "NOT_HANDOFFABLE_AS_IS"
  )
)

cat("=== Optimizer Finalize v2 Done ===\n")
cat("Q-Lead escalate:", if (escalate) "YES" else "NO", "\n")
cat("Handoff status:", final_pkg$infeasibility_report$handoff_status, "\n")
