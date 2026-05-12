#==============================================================================
# Finalize alpha_package.json from alpha_package_draft.json + codex round 1 outcome
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite); library(digest)
})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

draft <- fromJSON("qepm/mailbox/worktask/WT-D20260508_013/alpha_package_draft.json",
                  simplifyVector = FALSE)
codex <- fromJSON("qepm/mailbox/worktask/WT-D20260508_013/codex_critic_response_alpha.json",
                  simplifyVector = FALSE)

# Add codex round summary to final
draft$codex_critic_round_summary <- list(
  round = 1,
  stance_received = codex$stance,
  stance_rationale = codex$stance_rationale,
  weakest_assumption = codex$weakest_assumption,
  response_file = "qepm/mailbox/worktask/WT-D20260508_013/codex_critic_response_alpha.json",
  challenge_note_file = "qepm/mailbox/worktask/WT-D20260508_013/challenge_note.md",
  concerns_total = length(codex$critical_concerns),
  classification = list(
    ACCEPT = 5,
    PARTIAL = 1,
    REBUTTAL = 1,
    summary = "C1 ACCEPT (Harvey-NW math fixed) / C2 ACCEPT (full-panel fail honest) / C3 PARTIAL (mechanism plausible, ex-post narrative acknowledged) / C4 REBUTTAL (resolved by C5 fix decile mono 0.59->0.71) / C5 ACCEPT (C10 strict t-1 fixed) / C6 ACCEPT (C15 direct parquet fixed) / C7 ACCEPT (AX-008 alpha-layer 1/3 deferred to downstream)"
  ),
  high_severity_resolved = 1,    # C1 math fix
  high_severity_partial = 1,      # C3 RF-A3
  high_severity_unresolved = 1,   # C2 strict 5/5 full-panel fail (intrinsic)
  pit_c10_c15_fixed = TRUE,
  silent_override = FALSE,
  escalate_to_q_lead = FALSE,
  escalate_rationale = "HIGH=3 < trigger 5; AX hard FAIL=0; PIT C1 lockbox no violation. Single-judgment within alpha agent scope.",
  final_stance = "APPROVE_CONDITIONAL_DIVERSIFIER",
  final_stance_basis = "Strict full-panel 5/5 graduation FAILS at 4 of 5 (rank_ic 0.0321 < 0.04 / ICIR 0.184 < 0.20 / corrected Harvey-t 2.86 < 3.0 / DSR strict 0). Recent 60m strict 3/3 PASS. Defensive ratio +17.9 + perfect orthogonality. DIVERSIFIER role candidate dependent on Risk + Forge + Architect downstream verification."
)

# Final package summary
draft$final_summary <- list(
  graduation_strict_full_panel = "FAIL (1 of 5 core gates: subperiod sign-consistency only)",
  graduation_strict_recent_60m = "PASS (3 of 3 core gates: rank_ic + ICIR + Harvey-t)",
  decision = "APPROVE_CONDITIONAL_DIVERSIFIER (alpha agent honest stance)",
  next_agent = "risk-research",
  risk_agent_mandate = c(
    "Crisis_alpha measurement during 8 stress windows (2008/2011/2015/2018/2020/2022 etc) >= +0.05 IC",
    "Core MDD attenuation vs STR_1715 baseline >= 5pp improvement",
    "Sigma estimation + diversification ratio with alpha_z_013 vs Hybrid 70/15/15 incremental",
    "Tail risk + crowding + style audit",
    "AX-001 v2 conditional defense FORMAL classification"
  ),
  forge_mandate = c(
    "Multi-sleeve Hybrid 75/10/10/5 (or alternative weights from Optimizer) backtest 2010-2026",
    "Strict PIT C1-C15 + lockbox + 15bps cost",
    "ΔSharpe >= +0.05 vs Hybrid 70/15/15 baseline (current 1.665)",
    "ΔMDD <= -2pp (current -16.6%)"
  ),
  architect_mandate = c(
    "Independent VaR + Mom factor implementation reproduction",
    "Same ICIR +-0.05",
    "AX-008 triangulation 3rd source"
  )
)

write_json(draft, "qepm/mailbox/worktask/WT-D20260508_013/alpha_package.json",
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[saved] alpha_package.json\n")
cat("File size:", file.info("qepm/mailbox/worktask/WT-D20260508_013/alpha_package.json")$size, "bytes\n")

# Lineage record for final
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260508_013",
  package_type = "alpha_package",
  method_selected = "c4_rcomp = rank-composite (R02_VaR_99 + M01_Mom_12_1) Z_Score_Aligned",
  input_file_paths = c(
    ".cache/factor_db/factor_db_202604.parquet",
    ".cache/factor_db/factor_ic_monthly.parquet",
    ".cache/rawdata.parquet",
    "qepm/mailbox/worktask/WT-D20260508_013/codex_critic_response_alpha.json",
    "qepm/mailbox/worktask/WT-D20260508_013/challenge_note.md"
  ),
  windows = list(
    panel_full   = "2005-05-31 ~ 2026-04-30 (252 monthly sig_dates)",
    panel_recent = "2021-05-31 ~ 2026-04-30 (60 monthly sig_dates)",
    var_rolling_window = 252L,
    mom_window = "12m skip last 1m",
    burn_in_ic_history_months = 36L
  ),
  random_seed = 20260508013,
  extra = list(
    candidates_tried = 5L,
    candidates = c("c1_var","c2_mom","c3_mult","c4_rcomp","c5_corner"),
    codex_round = 1,
    codex_stance = codex$stance,
    final_stance = "APPROVE_CONDITIONAL_DIVERSIFIER",
    bug_fixes_2026_05_08 = c("nw_lrv formula", "C10 t-1 liquidity", "C15 sig_date enumeration")
  )
)
cat("[saved] artifact_lineage.json (alpha_package final entry)\n")

# Also create status.json indicating ALPHA_DONE → next Risk Agent
status <- list(
  task_id = "WT-D20260508_013",
  current_phase = "ALPHA_DONE",
  next_agent = "risk-research",
  alpha_completion_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  alpha_package_path = "qepm/mailbox/worktask/WT-D20260508_013/alpha_package.json",
  alpha_scores_parquet = "stage_artifacts/WT-D20260508_013/alpha_scores.parquet",
  codex_critic_round_1 = list(
    stance = codex$stance,
    response = "qepm/mailbox/worktask/WT-D20260508_013/codex_critic_response_alpha.json",
    challenge_note = "qepm/mailbox/worktask/WT-D20260508_013/challenge_note.md"
  ),
  alpha_agent_final_stance = "APPROVE_CONDITIONAL_DIVERSIFIER",
  alpha_agent_assessment = "Strict full-panel 5/5 graduation FAIL at 4 of 5 core gates (rank_ic, ICIR, Harvey-t 2.86, DSR strict). Recent 60m 3/3 PASS. Defensive ratio +17.9. Strong orthogonality vs Hybrid + WT_009 + WT_010. DIVERSIFIER candidate dependent on Risk + Forge + Architect downstream verification."
)
write_json(status, "qepm/mailbox/worktask/WT-D20260508_013/status.json",
           pretty = TRUE, auto_unbox = TRUE)
cat("[saved] status.json (current_phase=ALPHA_DONE)\n")
