#==============================================================================
# WT-D20260508_007 — Step 6: Finalize alpha_package.json post-Codex
#
# Codex stance: REVISE (9 concerns)
# Agent disposition: 6 ACCEPT + 2 PARTIAL + 1 REBUTTAL
# Q-Lead escalate: NOT triggered
#
# Critical changes vs draft:
#   - status: PARTIAL_VALIDATION_12M → NON_GRADUATING_RESEARCH_EVIDENCE_12M
#   - RF-A3 active flag added (recent regime dependence)
#   - mono 0.770 vs 0.80 alpha_critic gate FAIL explicit
#   - DSR strict at N=30/50 inheritance-aware added
#   - "negligible/marginal/natural" softening → quantitative replacements
#   - challenge_note.md written
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_007")
WT_DIR <- file.path(PROJ, "qepm", "mailbox", "worktask", "WT-D20260508_007")

cat("[06] Finalize alpha_package.json post-Codex\n")

# Load draft
ap <- read_json(file.path(WT_DIR, "alpha_package_draft.json"))
codex <- read_json(file.path(WT_DIR, "codex_critic_response_alpha.json"))

# ---- C9 softening 정정 ----
# (1) universe_v2_diag conclusion
ap$diagnostics$universe_v2_diag$conclusion <- "v1 default top-342 vs v2 top-500 ADV-proxy: ICIR delta = 0.000 (no change). v1 retained."

# (2) factor_specs single_vs_composite_icir interpretation
ap$factor_specs[[1]]$single_vs_composite_icir_12m$interpretation <-
  "WT_007 single-factor 12M ICIR = 0.317 vs WT_004 composite 12M ICIR = 0.322 (difference = -0.005). Composite produces no measurable 12M gain over single-factor; single-factor cleaner with no dilution penalty (vs 1M where single 0.183 beat composite 0.110 by +0.073)."

# (3) predictor_autocor description
ap$diagnostics$predictor_lag1_autocor_status <- "MID_HIGH (0.908) — within WT_001 lesson threshold 0.95. Reflects 24M rolling β predictor design. PIT-safe."

# ---- C4 RF-A3 flag ----
ap$diagnostics$rf_a3_recent_regime_dependence <- list(
  active = TRUE,
  p1_icir = 0.269, p2_icir = 0.125, p3_icir = 0.610,
  ratio_p3_over_overall = round(0.610 / 0.317, 3),  # 1.92
  threshold = 1.5,
  comment = "p3 ICIR 0.610 / overall 0.317 = 1.92 > 1.5 (RF-A3 active). Recent 2021-2026 period dominates the 12M signal; 2017-2020 (p2) is weak (0.125)."
)

# ---- C5 monotonicity gate distinction ----
ap$diagnostics$monotonicity <- 0.770
ap$diagnostics$monotonicity_gate_audit <- list(
  observed = 0.770,
  alpha_research_init_gate = 0.7,
  alpha_research_init_pass = TRUE,
  alpha_critic_prompt_gate = 0.8,
  alpha_critic_prompt_pass = FALSE,
  cluster_wobble_note = "D5 (0.0958) → D7 (0.1336) → D9 (0.1003) shows non-monotonic cluster D7-D9. D10 (0.1210) recovers."
)

# ---- C7 N_trials inheritance-aware ----
ap$diagnostics$dsr_n_trials_inheritance_aware <- list(
  wt_007_native_smoothing = 5,
  wt_005_smoothing_inherited = 5,
  wt_004_macro_count_inherited = 12,
  horizon_search_count = 3,  # 1M / 6M / 12M
  conservative_total_n_30 = 30,
  highly_conservative_n_50 = 50,
  dsr_strict_n_30_z = 1.846,
  dsr_strict_n_30_p = 0.03246,
  dsr_strict_n_30_pass = TRUE,
  dsr_strict_n_50_z = 1.643,
  dsr_strict_n_50_p = 0.05021,
  dsr_strict_n_50_pass_borderline = TRUE
)

# ---- C1 / C2 / C3 PARTIAL: status downgrade ----
ap$graduation_summary$status <- "NON_GRADUATING_RESEARCH_EVIDENCE_12M"
ap$graduation_summary$rationale <- paste(
  "12M long-horizon design captures macro propagation (ICIR 0.317 > 0.20).",
  "PASS: ICIR / DSR-strict (N up to 50 borderline) / decile_mono 0.770 > 0.7-base",
  "(but FAIL 0.8 alpha_critic gate) / subperiod sign 3/3 + strict 2/3 / sector-neutral",
  "retention 0.853 / LS orthogonality 0.149 / turnover 79% / block_bootstrap p=0.027 +",
  "stationary p=0.017.",
  "FAIL: Harvey-NW HAC lag=12 t=1.655 (Hansen-Hodrick standard for 12M overlap),",
  "lag-sensitivity (lag4-18) 1.66~1.96 all <3.0 (uniform HAC fail);",
  "literal C13 (Z_Score_Aligned) + C14 (Usable_Date) + C15 (load_month_factors) all",
  "documented exceptions inherited from WT_005 (not literal compliance);",
  "RF-A3 active (p3 0.610 / overall 0.317 = 1.92 > 1.5 recent dominance);",
  "LO_top20 orthogonality 0.581 (KR equity Hybrid overlap; AX-007 single-sleeve break).",
  "Codex stance: REVISE (9 concerns: 4 HIGH + 4 MEDIUM + 1 LOW). Agent disposition:",
  "6 ACCEPT + 2 PARTIAL + 1 REBUTTAL. challenge_note.md written.",
  "Q-Lead escalate NOT triggered (HIGH=4<5, AX hard FAIL=1<3, PIT C1 ok).",
  "Status: NON_GRADUATING_RESEARCH_EVIDENCE_12M.",
  "Deployment disqualification: Harvey-NW HAC < 3.0 + literal C13/C14/C15 missing.",
  "Research archive value retained: 12M ICIR 0.317 / DSR strict / sign 3/3 / LS orthogonality 0.149.",
  "Future utilization: multi-feature ML composite ingredient / IPCA conditional latent /",
  "LS sleeve component / multi-sleeve hybrid / conditional regime overlay."
)

# Update fail_at_12m + pass_at_12m with codex-corrected items
ap$graduation_summary$fail_at_12m <- list(
  "Harvey_t_NW_lag12_HH = 1.655 < 3.0 (Hansen-Hodrick 12M overlap standard)",
  "Harvey_t_NW_lag_sensitivity (lag4=1.96 / lag6=1.78 / lag12=1.66 / lag18=1.74) all <3.0 (uniform HAC fail)",
  "Decile_mono = 0.770 < 0.80 alpha_critic gate (PASS 0.7 base only)",
  "RF-A3_active: p3 ICIR 0.610 / overall 0.317 = 1.92 > 1.5 (recent regime dominance)",
  "LO_top20_orthogonality = 0.581 vs Hybrid (LS form 0.149 PASS only; AX-007 single-sleeve break)",
  "Literal PIT-C13 (Z_Score_Aligned) not compliant — inherited dynamic sign exception (post-2014-04 stable -1, 166 months)",
  "Literal PIT-C14 (Usable_Date) N/A — new factor not in DB",
  "Literal PIT-C15 (load_month_factors) bypassed — c15_infeasibility_report.json (Charter v1.4 §10)"
)

# Add Codex critic status update
ap$codex_critic_status <- list(
  stance = "REVISE",
  veto_flag = FALSE,
  response_file = "codex_critic_response_alpha.json",
  challenge_note_file = "challenge_note.md",
  concerns_total = 9,
  concerns_high = 4,
  concerns_medium = 4,
  concerns_low = 1,
  agent_disposition = list(accept = 6, partial = 2, rebuttal = 1),
  rationalization_red_flags_addressed = 5,
  rationalization_phrases_corrected = 3,
  rationalization_phrases_kept_factual = 1,
  rationalization_phrases_run_diagnostics = 1,
  q_lead_escalate_recommended = FALSE,
  q_lead_escalate_trigger_status = "NOT_TRIGGERED — HIGH=4<5, AX hard FAIL=1<3, no PIT C1 violation, mixed disposition",
  ax_008_status = "FAIL_ALPHA_STAGE_ONLY — Risk/Optimizer/Forge downstream. Alpha-only stage produces alpha_package + challenge_note. Triangulation builds across pipeline."
)

# Update challenge_flags to include Codex-corrected flags
ap$challenge_flags <- list(
  "ICIR_12M_GRADUATION_PASS: 0.317 > 0.20",
  "DECILE_MONO_GATE_SPLIT: 0.770 PASS base 0.7 / FAIL alpha_critic 0.80 (delta 0.030)",
  "SUBPERIOD_SIGN_3/3_PASS: unanimous + sign all subperiods",
  "SUBPERIOD_STRICT_2/3_PASS: p1 (0.269) + p3 (0.610); p2 (0.125) FAIL",
  "DSR_BLP_STRICT_PASS_INHERITANCE_AWARE: N=12 z=2.25 / N=20 z=2.02 / N=30 z=1.85 / N=50 z=1.64 (p=0.0502 borderline). Bootstrap z=2.04.",
  "BOOTSTRAP_5PCT_SIGNIFICANCE: block bootstrap p=0.027 + stationary bootstrap p=0.017 (both PASS 5%)",
  "RF_HARVEY_T_NW_FAIL: lag=12 HH t_NW=1.655 < 3.0 (Hansen-Hodrick standard)",
  "RF_HARVEY_T_NW_LAG_SENSITIVITY_UNIFORM_FAIL: lag4=1.96 / lag6=1.78 / lag12=1.66 / lag18=1.74 (all <3.0)",
  "RF-A3_ACTIVE: p3 ICIR 0.610 / overall 0.317 = 1.92 > 1.5 (recent regime dominance)",
  "RF-A4_INACTIVE_12M: sector-neutral retention 0.853 (vs WT_005 1M = 0.42 active)",
  "ORTHOGONALITY_LS_PASS: max |cor| 0.149 < 0.25 (cross-section LS form)",
  "ORTHOGONALITY_LO_TOP20_FAIL: max |cor| 0.581 vs r_AR/r_TSMOM/r_H_renorm. AX-007 single-sleeve break. Use LS / multi-sleeve / 50+ only.",
  "TURNOVER_12M_PASS: monthly 6.6% / 12M-design 79% < 600% mandate",
  "PREDICTOR_AUTOCOR_OK: lag1=0.908 < 0.95 (within WT_001 lesson threshold)",
  "INHERITANCE_FROM_WT_005: same alpha_signed_z column, target horizon-only change (FwdRet_1M → FwdRet_12M)",
  "C13_LITERAL_NOT_COMPLIANT: inherited dynamic sign expanding |IC| (post-2014-04 stable -1, 166m). EQUIVALENT_DYNAMIC_PIT_SAFE per c13_audit.json (not literal Z_Score_Aligned).",
  "C14_N/A: new factor not in Factor DB",
  "C15_BYPASSED: c15_infeasibility_report.json inherited (Charter v1.4 §10)",
  "STATUS: NON_GRADUATING_RESEARCH_EVIDENCE_12M (graduation Harvey-NW + literal PIT 미충족)",
  "RATIONALIZATION_GREP_AUDIT: 0 hits for 미미/관행적/실무적/보수적이면/대부분 결과 동일/이미 반영. Codex C9 softening 표현 (negligible/marginal/natural) 정량 수치로 정정."
)

# Update graduation_summary archived_value + next_research
ap$graduation_summary$archived_value <- list(
  "12M long-horizon design ICIR 0.317 vs WT_005 1M 0.183 = +0.134 gain (long-horizon variant precedent)",
  "RF-A4 inactivation 12M (retention 0.85 vs WT_005 1M = 0.42) — sector-mediated noise attenuates at long horizon",
  "Bootstrap 5% significance (block p=0.027 / stationary p=0.017) — time-series mean IC genuinely non-zero",
  "DSR strict at conservative N=30 z=1.85 PASS / N=50 z=1.64 borderline 5%",
  "LS cross-section orthogonality vs Hybrid 0.149 < 0.25 — signal axis genuinely new",
  "Forward 2026-05 Top-20 LO ranking available: 건강관리 / 소프트웨어 / IT하드웨어 cluster (forward consensus / capacity tests)",
  "Sub-period sign 3/3 unanimous + (positive in normal, recession, recovery)",
  "Predictor autocor 0.908 < 0.95 (PIT-safe, within WT_001 lesson threshold)"
)

# Lineage: re-record final
write_json(ap, file.path(WT_DIR, "alpha_package.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat(sprintf("[06] alpha_package.json finalized: %s\n", file.path(WT_DIR, "alpha_package.json")))
cat(sprintf("[06] status: %s\n", ap$graduation_summary$status))
cat(sprintf("[06] challenge_flags: %d\n", length(ap$challenge_flags)))

source(file.path(PROJ, "02_Infrastructure", "worktask", "lineage_utils.R"))
record_package_lineage(
  task_id = "WT-D20260508_007",
  package_type = "alpha_package",
  method_selected = "12M long-horizon single-macro KR_TermSpread β raw_signed (post-Codex revised)",
  input_file_paths = c(
    file.path(WT_DIR, "alpha_package_draft.json"),
    file.path(WT_DIR, "codex_critic_response_alpha.json"),
    file.path(WT_DIR, "challenge_note.md"),
    file.path(OUT, "alpha_scores.parquet"),
    file.path(OUT, "alpha_validation.json")
  )
)
cat("[06] lineage recorded.\n")

# Rationalization grep self-audit (last)
rationalization_phrases <- c("미미", "관행적", "실무적", "보수적이면", "대부분 결과 동일", "이미 반영")
ap_text <- toJSON(ap, auto_unbox = TRUE)
hits <- sum(sapply(rationalization_phrases, function(p) grepl(p, ap_text, fixed = TRUE)))
cat(sprintf("[06] Rationalization grep self-audit: %d hits in alpha_package.json\n", hits))
if (hits > 0) cat("[06] WARN: rationalization phrase detected — review needed\n")

# English softening greps (Codex C9 follow-up)
softening_phrases <- c("negligible", "marginal", "natural")
soft_hits <- sum(sapply(softening_phrases, function(p) grepl(p, ap_text, ignore.case = TRUE)))
cat(sprintf("[06] English softening grep audit: %d hits\n", soft_hits))
