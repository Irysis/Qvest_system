# Finalize alpha_package.json + alpha_discovery_certificate + lineage
suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(arrow)
  library(digest)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
TASK_ID <- "WT-D20260428_002"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", TASK_ID)
ART_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260428_002")

source(file.path(PROJECT_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))

# Load draft + Codex response
draft <- fromJSON(file.path(WT_DIR, "alpha_package_draft.json"),
                  simplifyVector = FALSE)
codex <- fromJSON(file.path(WT_DIR, "codex_critic_response_alpha.json"),
                   simplifyVector = FALSE)

# ============================================================
# 1. Update package with Codex critic audit + revised prose
# ============================================================
pkg <- draft

# revise hypothesis_summary to remove rationalization framing per Codex C9 prose flag
pkg$hypothesis_summary <- "Iter 10 V2 FIAPAS Redesign — pre-registered hypothesis with sign(F1)=-1 declared BEFORE measurement (Charter §5 ex-ante mandate). 2-spec composite (F1 herding-reversal + F2 accrual volatility). F3_L19_Price_Delay dropped pre-measurement (Iter 9 Codex C4: marginal-negative ICIR contribution). LIQ 2e8 deployment-grade floor. Kim-Kim (2014 PBFJ) + Hwang-Salmon (2004 JEF) Korean foreign herding mean-reversion verified at monthly horizon. Result vs Iter 9 baseline: ICIR 0.275 → 0.331, NW-t 3.87 → 4.36, monotonicity 0.673 → 0.697, DSR_post 0 → 13.63 (the DSR_post improvement comes mechanically from n_candidates=3 vs Iter 9's 6, not from absolute alpha quality). Pre-registration check PASS — F1 t-stat positive after pre-committed -1 sign-flip. Honest gaps: rank_ic 0.0293 still < 0.04 graduation threshold. monotonicity 0.697 still < 0.80. F2 univariate t=2.22 < 3 (cond4 harvey 2/3). KR_TOP500_FREEFLOAT v2 universe shows ICIR attenuation 0.331 → 0.105, indicating alpha is universe-restricted (deployability concern). Codex critic raised 10 concerns (7 HIGH + 3 MEDIUM); 4 ACCEPT (cert NOT ISSUED, fwd_ret leakage fix, lineage, candidate-count cumulation) + 4 PARTIAL (PIT-C13 sign-flip dispute, RF-A3 recent-regime, turnover, sector-neutral) + 2 REBUTTAL (FF5/6 downstream scope, AX-007 Optimizer domain)."

# add codex_critic_audit field
pkg$codex_critic_audit <- list(
  performed_at = "2026-04-28T15:21+0900",
  stance = "REJECT",
  veto_flag = FALSE,
  n_critical_concerns = 10,
  n_high_severity = 7,
  n_medium_severity = 3,
  agent_response_protocol = "Charter §8 No Silent Override + Charter §10 Role Card",
  concern_resolution = list(
    C1 = list(severity = "HIGH", classification = "PARTIAL",
              codex_position = "PIT-C13 forbids manual sign flips; ex-ante registration does not waive the prohibition",
              agent_position = "Composite-level multiplier on already Z_Score_Aligned individual factors is structurally distinct from per-factor direction reversal. Pre-registration in method_shopping_log.json before measurement. Mechanism citation Kim-Kim 2014 + Hwang-Salmon 2004 valid for KR monthly horizon. Empirical confirmation: F1 univariate t_NW=4.53 + decile-rank monotonicity 0.697 directionally matches mechanism prediction.",
              agent_concession = "Iter 11 should explore alternative architecture: (a) Factor DB registry direction update for INV09/INV11 (PIT-safe automatic via load_month_factors IC inference), (b) raw INV-Z weighted-Z composite without global -1 multiplier."),
    C2 = list(severity = "HIGH", classification = "ACCEPT",
              codex_position = "rank_ic 0.029<0.04, monotonicity 0.697<0.80, harvey 2/3 not 3/3",
              agent_action = "alpha_discovery_certificate NOT ISSUED. Self-denial per Charter §10 cooperative behavior."),
    C3 = list(severity = "HIGH", classification = "PARTIAL",
              codex_position = "Multi-testing FF5/FF6 missing + DSR_post cumulative penalty undercounts Iter 9 candidates",
              agent_position_FF56_REBUTTAL = "Charter §10 Alpha Agent role: factor-model regressions (CAPM/Carhart/FF5/FF6) on portfolio with weights are Forge/Judge stage scope. Alpha agent stage: t_NW + DSR + multi-spec t-stats are standard.",
              agent_concession_candidate_count = "Iter 9 (6) + Iter 10 (3) = 9 cumulative candidates → DSR_post_cumulative = 13.78 - 9*0.05 = 13.33 (still well above 0.5 threshold but conceptual point valid)."),
    C4 = list(severity = "HIGH", classification = "ACCEPT",
              codex_position = "alpha_scores.parquet contains fwd_ret = future label leakage in downstream signal artifact",
              agent_action = "FIXED — fwd_ret + parent_z columns DROPPED from alpha_scores.parquet. Schema now: sig_date, Ticker, alpha_v2, F1z, F2z, universe, alpha_v2_TOP500."),
    C5 = list(severity = "HIGH", classification = "PARTIAL",
              codex_position = "Recent 3Y ICIR 1.68x > RF-A3 1.5x cap",
              agent_position = "1.68x ratio is correctly DISCLOSED in rolling_3yr_icir field. Iter 9 had p1 negative IC; Iter 10 has p1 positive (0.015), so recent-regime concentration is mitigated vs Iter 9 but not eliminated. Cert NOT ISSUED makes RF-A3 deployment-binding non-binding here."),
    C6 = list(severity = "HIGH", classification = "PARTIAL",
              codex_position = "Annual turnover 822% > 600% hard constraint",
              agent_position = "Alpha-level signal turnover (top-N rank churn) ≠ realized portfolio turnover. Hurdle Gate v2.2 hard fail applies to portfolio-level. Charter §10 Optimizer applies buffer zone + TO penalty.",
              agent_concession = "If Optimizer reduces 50%, realized ~411% still high. Iter 11 should reduce alpha-level TO via 3M EWMA on INV09."),
    C7 = list(severity = "HIGH", classification = "ACCEPT",
              codex_position = "KR_TOP500 ICIR 0.105 / NW-t 0.46 — alpha not robust to universe expansion",
              agent_action = "Critical deployability finding DISCLOSED in universe_comparison. Cert NOT ISSUED corroborated. Strongest single argument beyond rank_ic miss."),
    C8 = list(severity = "MEDIUM", classification = "REBUTTAL",
              codex_position = "User hard max_names=20 long-only, top-50 alpha vector + AX-007 not satisfied",
              agent_position = "Charter §10 Alpha Agent role: alpha_vector + signal_matrix only. Hard max_names=20 is OPTIMIZER's binding constraint. Alpha provides top-50 (per request schema max_names=null discovery WT) so Optimizer has selection room. AX-007 EXCLUSION 4 cases downstream-achievable. Iter 9 Codex ACCEPTED this REBUTTAL precedent."),
    C9 = list(severity = "MEDIUM", classification = "ACCEPT",
              codex_position = "No challenge_note.md / artifact_lineage.json / weights.csv / covariance.parquet",
              agent_action = "FIXED — challenge_note.md + artifact_lineage.json written. weights/cov intentionally absent (Risk/Optimizer pipeline NOT triggered because Alpha did not graduate)."),
    C10 = list(severity = "MEDIUM", classification = "PARTIAL",
              codex_position = "post_neutralization_ic = raw rank_ic, no sector-neutral comparison (RF-A4)",
              agent_position = "Iter 10 used liquidity floor only neutralization. Sector-neutral testing appropriate at Forge/Judge stage.",
              agent_concession = "Iter 11 must include sector-neutral pre-residualization at alpha stage with ICIR before/after disclosed."),
    summary = "10 concerns: 4 ACCEPT (C2/C4/C7/C9) + 4 PARTIAL (C1/C3/C5/C6/C10) + 2 REBUTTAL (C3 FF56 part, C8). NO BLANKET ACCEPT. NO SILENT REBUT. Q-Lead escalate triggered (HIGH≥5)."
  ),
  rationalization_audit_post_resolution = list(
    pass_phrases_remaining = 0,
    codex_flagged_phrases = 6,
    accepted_5 = "rationalization framing removed (massive improvement / Build cost / NOT a post-hoc / honest disclosure / downstream achievable)",
    rebuttal_1 = "DEFERRED_TO_OPTIMIZER_PER_CHARTER_§10 retained as literal role boundary",
    note = "After resolution + prose revision, primary recommendation is Iter 11 redesign with alternative architecture, not Iter 10 promotion."
  ),
  q_lead_escalate_trigger = list(
    high_severity_count = 7,
    threshold = 5,
    triggered = TRUE,
    rationale = "Charter §8 auto-escalate: HIGH severity ≥ 5. Q-Lead must review Iter 10 outcome + Iter 11 mandate before next discovery WT spawn."
  )
)

# update primary_variant_post_codex_revision_note
pkg$primary_variant_post_codex_revision_note <- "Post-Codex REJECT (4 ACCEPT + 4 PARTIAL + 2 REBUTTAL), Iter 10 result is informational. alpha_discovery_certificate NOT ISSUED. PG1 admission auto-denied via certificate absence. STR_1715 100% mandate persists. Iter 11 redesign mandate (conditional on Q-Lead approval): (1) alternative architecture without composite-level multiplier (registry direction update OR raw INV-Z weighted), (2) sector-neutral pre-residualization at alpha stage, (3) rolling 3Y ICIR drift ex-ante, (4) alpha-level TO reduction 3M EWMA, (5) v2 universe robustness, (6) cumulative candidate count tracking, (7) ex-ante pre-registration discipline retained."

pkg$alpha_discovery_certificate <- list(
  issued = FALSE,
  inheritance_cor_actual = pkg$diagnostics$alpha_inheritance_cor,
  inheritance_cor_max = 0.95,
  mechanism_cited = "V2_herding_reversal pre-registered: foreign+institutional consensus + persistence + concentration marks buying-cycle peak in KR retail-dominated equities → next 1M mean-reversion. Kim-Kim 2014 + Hwang-Salmon 2004 monthly horizon. NW-t = 4.36. ICIR = 0.331. monotonicity = 0.697.",
  factor_specs_new_count = 1,
  harvey_t_specs_pass_count = 2,
  issued_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  non_issuance_reason = "Honest self-denial. Reasons: (1) Codex critic REJECT [stance], 10 critical concerns including 7 HIGH (C1 PIT-C13 sign-flip dispute, C2 graduation rank_ic 0.029<0.04 + monotonicity 0.697<0.80, C3 multi-testing scope, C4 fwd_ret leakage [FIXED], C5 RF-A3 recent-regime 1.68x, C6 turnover 822%, C7 KR_TOP500 ICIR attenuation 0.331→0.105). (2) Graduation gates: rank_ic FAIL + monotonicity FAIL + cond4 (harvey 2/3) FAIL. (3) Iter 10 vs Iter 9 improvement measurable (ICIR +20%, NW-t +13%, DSR_post 0→13.6) but graduation thresholds not crossed. (4) Charter §10 cooperative behavior: certificate self-denial when graduation FAIL is the honest action. Recommendation: Iter 11 with alternative architecture (per concern_resolution.C1), or halt FIAPAS family.",
  cond_breakdown = list(
    cond1_inheritance_cor_lt_095 = pkg$diagnostics$alpha_inheritance_cor < 0.95,
    cond2_factor_specs_ge_1 = TRUE,
    cond3_mechanism_ge_50chars = TRUE,
    cond4_harvey_pass_ge_3 = pkg$diagnostics$harvey_t_specs_pass_count >= 3,
    all_4cond_technical_pass = pkg$diagnostics$harvey_t_specs_pass_count >= 3 &&
                               pkg$diagnostics$alpha_inheritance_cor < 0.95
  ),
  graduation_check = list(
    rank_ic_pass = pkg$diagnostics$rank_ic >= 0.04,
    icir_pass = pkg$diagnostics$icir >= 0.20,
    subperiod_pass = pkg$diagnostics$subperiod_stability >= 0.5,
    harvey_t_pass = abs(pkg$diagnostics$harvey_t_stat_pooled) >= 3,
    dsr_post_pass = pkg$diagnostics$dsr_post >= 0.5,
    monotonicity_pass = pkg$diagnostics$monotonicity >= 0.80,
    overall = "FAIL — rank_ic 0.0293 < 0.04 + monotonicity 0.697 < 0.80 + cond4 (harvey 2/3) FAIL"
  )
)

pkg$status <- "ALPHA_DONE_CERTIFICATE_NOT_ISSUED_GRADUATION_FAIL_ITER11_REDESIGN_REQUESTED"
pkg$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

# ============================================================
# 2. Save final alpha_package.json
# ============================================================
write(toJSON(pkg, pretty = TRUE, auto_unbox = TRUE, digits = 6, na = "null"),
      file.path(WT_DIR, "alpha_package.json"))
cat(sprintf("[Iter 10] alpha_package.json saved: %d KB\n",
            round(file.info(file.path(WT_DIR, "alpha_package.json"))$size/1024)))

# ============================================================
# 3. alpha_discovery_certificate.json (standalone)
# ============================================================
cert <- pkg$alpha_discovery_certificate
cert$task_id <- TASK_ID
cert$wt_type <- "discovery"
cert$parent_iter_promotion_status <- "STR_1715 100% PG2 mandate persists (no replacement)"
write(toJSON(cert, pretty = TRUE, auto_unbox = TRUE, digits = 6, na = "null"),
      file.path(WT_DIR, "alpha_discovery_certificate.json"))
cat(sprintf("[Iter 10] alpha_discovery_certificate.json saved (issued=%s)\n",
            cert$issued))

# ============================================================
# 4. artifact_lineage.json (R11 mandate)
# ============================================================
record_package_lineage(
  task_id = TASK_ID,
  package_type = "alpha_package",
  method_selected = "FIAPAS_2spec_pre_registered_signF1_neg1",
  input_file_paths = c(
    file.path(ART_DIR, "alpha_scores.parquet"),
    file.path(ART_DIR, "alpha_validation.json"),
    file.path(WT_DIR, "method_shopping_log.json")
  ),
  windows = list(
    sig_date_range = c("2004-01-30", "2023-12-28"),
    n_sig_dates = 240,
    forecast_horizon = "1M",
    rebalance = "monthly"
  ),
  random_seed = 20260428L,
  extra = list(
    iter = 10,
    iter_name = "V2_FIAPAS_Redesign_pre_registered",
    parent_task_id = "WT-D20260428_001",
    pre_registration_protocol = "ex-ante method_shopping_log.json sign(F1)=-1 + n_candidates=3",
    universe_primary = "KR_top342",
    universe_secondary = "KR_TOP500_FREEFLOAT (sparse 20)",
    liquidity_floor_krw = 200000000L,
    codex_stance = "REJECT",
    cert_issued = FALSE,
    graduation_status = "FAIL_rank_ic_monotonicity_cond4"
  )
)

cat(sprintf("[Iter 10] artifact_lineage.json appended\n"))

# ============================================================
# 5. governance_log.json append
# ============================================================
gov_path <- file.path(WT_DIR, "governance_log.json")
gov <- if (file.exists(gov_path)) {
  fromJSON(gov_path, simplifyVector = FALSE)
} else {
  list(task_id = TASK_ID, events = list())
}
if (is.null(gov$events) || !is.list(gov$events)) gov$events <- list()

new_events <- list(
  list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
    agent = "alpha_research",
    action = "ALPHA_RUN_COMPLETE",
    summary = "Iter 10 V2 FIAPAS Redesign measurement complete: KR_top342 ICIR 0.331 / NW-t 4.36 / monotonicity 0.697 / rank_ic 0.0293. KR_TOP500_FREEFLOAT sparse ICIR 0.105 (attenuation). 7-spec mandate compliance verified."
  ),
  list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
    agent = "codex_critic",
    action = "CODEX_CRITIC_REJECT",
    summary = "Codex GPT-5.5 xhigh: REJECT with 10 critical_concerns (7 HIGH + 3 MEDIUM). Agent resolution: 4 ACCEPT + 4 PARTIAL + 2 REBUTTAL. Q-Lead escalate triggered (HIGH≥5)."
  ),
  list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
    agent = "alpha_research",
    action = "CERT_NOT_ISSUED",
    summary = "alpha_discovery_certificate.issued=FALSE per Charter §10 self-denial. graduation FAIL (rank_ic 0.0293<0.04, monotonicity 0.697<0.80, cond4 harvey 2/3). PG1 auto-denied. Iter 11 redesign mandate proposed pending Q-Lead decision."
  )
)
for (ev in new_events) {
  gov$events[[length(gov$events) + 1]] <- ev
}
write_json(gov, gov_path, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("[Iter 10] governance_log.json updated\n"))

# ============================================================
# 6. status.json
# ============================================================
status <- list(
  task_id = TASK_ID,
  current_phase = "ALPHA_DONE",
  updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  blocker = NULL,
  cert_issued = FALSE,
  cert_non_issuance_reason = "Honest self-denial — graduation FAIL on rank_ic 0.0293<0.04 + monotonicity 0.697<0.80 + cond4 harvey 2/3. Codex REJECT 10 concerns.",
  iter11_proposed = TRUE,
  q_lead_escalate_required = TRUE
)
write_json(status, file.path(WT_DIR, "status.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("[Iter 10] status.json updated: phase=ALPHA_DONE\n"))

cat("\n[Iter 10] === Finalize complete ===\n")
