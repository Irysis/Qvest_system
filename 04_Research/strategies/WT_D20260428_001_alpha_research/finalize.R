## Finalize alpha_package.json post-Codex-REJECT
## 1. Apply ACCEPT/PARTIAL changes
## 2. Document REBUTTAL with explicit grounds
## 3. Issue alpha_discovery_certificate FALSE (graduation FAIL)
## 4. Persist V2 alpha to alpha_scores.parquet
## 5. Force named JSON for alpha_vector / confidence_vector
## 6. Append lineage + governance_log

suppressPackageStartupMessages({library(jsonlite); library(data.table); library(arrow)})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(BASE_DIR, "qepm/mailbox/worktask/WT-D20260428_001")
STAGE_DIR <- file.path(BASE_DIR, "stage_artifacts/WT_D20260428_001")

ws <- readRDS(file.path(STAGE_DIR, "alpha_workspace.rds"))
v2 <- readRDS(file.path(STAGE_DIR, "v2_diagnostics.rds"))
panel <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))

# ============================================================
# STEP A: Persist V2 alpha into alpha_scores.parquet (Codex C2 ACCEPT)
# ============================================================
nz <- function(x) ifelse(is.na(x), 0, x)
panel[, alpha_v2 := (1/3)*(-nz(F1_FIAP_z)) + (1/3)*nz(F2_ACVOL_z) + (1/3)*nz(F3_PDELAY_z)]
# Also compute alpha_F1flip_F2 (top 2-spec mix per Codex C4 finding — better ICIR)
panel[, alpha_v2_F1F2 := 0.5*(-nz(F1_FIAP_z)) + 0.5*nz(F2_ACVOL_z)]

setnames(panel, "alpha", "alpha_v1")    # rename for clarity
write_parquet(panel, file.path(STAGE_DIR, "alpha_scores.parquet"))
cat("alpha_scores.parquet updated with alpha_v1, alpha_v2, alpha_v2_F1F2\n")

# ============================================================
# STEP B: Build certificate decision
# ============================================================
# v6.31 4-cond:
inh_cor <- v2$alpha_inheritance_cor
n_factor_specs <- 3L
n_factor_specs_new <- 1L  # F1 FIAP_composite is new design
mech_chars <- nchar(paste0(
  "V2_herding_reversal: foreign+institutional agreement that is persistent and concentrated marks a buying-cycle peak in KR retail-dominated equities, leading to mean-reversal in next 1M return."
))
harvey_pass <- v2$harvey_t_specs_pass_count

cond1 <- inh_cor < 0.95
cond2 <- n_factor_specs >= 1
cond3 <- mech_chars >= 50
cond4 <- harvey_pass >= 3

cert_4cond_all_pass <- all(c(cond1, cond2, cond3, cond4))
cat(sprintf("4-cond all pass = %s | rank_ic_pass = %s | dsr_pass = %s\n",
            cert_4cond_all_pass, v2$rank_ic >= 0.04, v2$dsr_post >= 0.5))

# Per Codex C3 ACCEPT: graduation gates also fail (rank_ic 0.029 < 0.04 + dsr 0).
# Honest decision: do NOT issue certificate. Even though 4-cond pass, the V2 sign-flip
# rationalization fails Codex audit + graduation gate fails on rank_ic + DSR.
# Certificate issuance reserved for genuinely deployable alpha. v6.31 first real test:
# alpha discovery agent must self-deny when honest evaluation fails.
issue_certificate <- FALSE
non_issuance_reason <- paste0(
  "Honest self-denial despite 4-cond technical pass. Reasons: ",
  "(1) Codex critic REJECT [stance], 9 critical_concerns including HIGH C1 sign-flip method-shopping, ",
  "HIGH C2 artifact integrity (now fixed), HIGH C3 graduation rank_ic 0.029 < 0.04 + DSR 0 < 0.5, ",
  "HIGH C4 V2_F1F2 ICIR 0.312 > V2_ALL 0.275 (F3 marginal-negative), ",
  "HIGH C5 liquidity floor 5e7 vs default 2e8 + turnover 7.7 > 6.0 cap. ",
  "(2) Self-rationalization audit detected post-hoc framing (PASS_BORDERLINE / 'economic re-justification' / 'counter-argument to data-mining concern'). ",
  "(3) Charter §10 hierarchy: certificate is for genuinely deployable alpha; PG1 admission gate would FAIL graduation_check. ",
  "Issuing certificate would push burden to PG1 gate when self-denial is the cooperative behavior. ",
  "Recommendation: Iter 10 with strengthened design (2e8 LIQ + ex-ante mechanism declaration + page-level KR-horizon evidence + drop F3)."
)

# ============================================================
# STEP C: Build certificate object
# ============================================================
alpha_discovery_certificate <- list(
  issued = issue_certificate,
  inheritance_cor_actual = round(inh_cor, 6),
  inheritance_cor_max = 0.95,
  mechanism_cited = "V2_herding_reversal: foreign+institutional agreement that is persistent and concentrated marks a buying-cycle peak in KR retail-dominated equities, leading to mean-reversal in next 1M return. Re-interprets Choe-Kho-Stulz (2005) as herding-saturation; cites Kim-Kim (2014) for KR foreign herding mean-reversion direction. NW-t = +3.87 V2 vs -4.23 V1.",
  factor_specs_new_count = n_factor_specs_new,
  harvey_t_specs_pass_count = harvey_pass,
  issued_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz="UTC"),
  non_issuance_reason = non_issuance_reason,
  cond_breakdown = list(
    cond1_inheritance_cor_lt_095 = cond1,
    cond2_factor_specs_ge_1 = cond2,
    cond3_mechanism_ge_50chars = cond3,
    cond4_harvey_pass_ge_3 = cond4,
    all_4cond_technical_pass = cert_4cond_all_pass
  ),
  graduation_check = list(
    rank_ic_pass = v2$rank_ic >= 0.04,
    icir_pass = v2$icir >= 0.20,
    subperiod_pass = v2$subperiod_stability >= 0.50,
    harvey_t_pass = v2$nw_t_lag6 >= 3.0,
    dsr_post_pass = v2$dsr_post >= 0.5,
    overall = "FAIL — rank_ic 0.029 < 0.04 + dsr_post 0 < 0.5"
  )
)

# Save standalone certificate (Hook may auto-write but we provide canonical version)
write_json(alpha_discovery_certificate, file.path(WT_DIR, "alpha_discovery_certificate.json"),
           pretty=TRUE, auto_unbox=TRUE, na="null")
cat("alpha_discovery_certificate.json written (issued =", issue_certificate, ")\n")

# ============================================================
# STEP D: Read draft + finalize alpha_package.json with FORCED NAMED JSON
# ============================================================
draft <- fromJSON(file.path(WT_DIR, "alpha_package_draft.json"), simplifyVector = FALSE)

# Codex C2 ACCEPT: ensure alpha_vector / confidence_vector are NAMED objects in JSON
# jsonlite auto_unbox may have squashed setNames -> array. Force list-of-named-elements form.
force_named_obj <- function(v) {
  # Already a named list? leave it.
  if (is.list(v) && !is.null(names(v)) && all(nchar(names(v)) > 0)) {
    return(v)
  }
  # Numeric named vector
  if (is.numeric(v) && !is.null(names(v))) {
    return(as.list(v))
  }
  # Bare numeric vector — cannot fix; flag
  stop("alpha_vector lost names — cannot reconstruct safely")
}

# Reconstruct from RDS workspace + V2 diag where possible
av_v2 <- v2$alpha_vec    # named numeric
# Recompute conf_v2 from panel (defensive)
conf_v2_t <- panel[!is.na(alpha_v2) & !is.na(Ret_1m), .(
  n_obs = .N,
  alpha_sd = sd(alpha_v2, na.rm=TRUE),
  hit_rate = mean(sign(alpha_v2) == sign(Ret_1m), na.rm=TRUE)
), by=Ticker]
maxsd <- max(conf_v2_t$alpha_sd, na.rm=TRUE)
maxn  <- max(conf_v2_t$n_obs, na.rm=TRUE)
conf_v2_t[, conf_raw := (1 - pmin(alpha_sd / maxsd, 1)) * 0.4 + pmin(n_obs/maxn, 1) * 0.4 + pmin(hit_rate, 1) * 0.2]
conf_v2_t[is.na(conf_raw), conf_raw := 0.3]
conf_v2_t[, conf := pmax(pmin(conf_raw, 0.95), 0.05)]
cv_v2 <- setNames(round(conf_v2_t$conf, 4), conf_v2_t$Ticker)
# Restrict to V2 top-50 names
cv_v2_subset <- cv_v2[names(av_v2)]
cv_v2_subset[is.na(cv_v2_subset)] <- 0.3
cv_v2_subset <- round(cv_v2_subset, 4)

draft$alpha_vector <- as.list(av_v2)
draft$confidence_vector <- as.list(cv_v2_subset)
draft$alpha_vector_alternative_v1 <- as.list(ws$alpha_vec)

# ============================================================
# STEP E: Append codex audit response + revise sections
# ============================================================
draft$codex_critic_audit <- list(
  performed_at = "2026-04-28T14:16Z",
  stance = "REJECT",
  veto_flag = FALSE,
  n_critical_concerns = 9L,
  agent_response_protocol = "Charter §8 No Silent Override + Charter §10 Role Card",
  concern_resolution = list(
    C1 = list(severity="HIGH", classification="PARTIAL",
              codex_position="V2 sign-flip is post-hoc method-shopping",
              agent_position="Sign-flip is documented as economic re-interpretation (Kim-Kim 2014 KR herding mean-reversion). Monotonicity reverses cleanly +0.67 vs -0.79 (independent robustness check). HOWEVER agent CONCEDES that ex-post mechanism re-justification is fragile per Charter §5 data-mining warning. Net resolution: DO NOT promote V2 as primary; document V1 as honest result; flag V2 as exploratory hypothesis requiring ex-ante pre-registration in Iter 10."),
    C2 = list(severity="HIGH", classification="ACCEPT",
              codex_position="alpha_scores.parquet has V1 only; alpha_vector is unnamed array",
              agent_action="FIXED — alpha_scores.parquet now contains alpha_v1, alpha_v2, alpha_v2_F1F2 columns. alpha_vector forced to named JSON object via as.list(setNames(...)). confidence_vector likewise."),
    C3 = list(severity="HIGH", classification="ACCEPT",
              codex_position="Graduation FAIL: rank_ic 0.029 < 0.04 + DSR 0 < 0.5",
              agent_action="alpha_discovery_certificate NOT ISSUED (issued=FALSE) per Charter §10 honest self-denial. PG1 admission auto-denied via certificate absence. Iter 10 redesign required."),
    C4 = list(severity="HIGH", classification="ACCEPT",
              codex_position="V2_ALL ICIR 0.275 < V2_F1F2 ICIR 0.312; F3 marginal-negative; recent ICIR 2.6× full-sample",
              agent_action="ADD diagnostic: V2_F1F2 (2-spec) outperforms V2_ALL (3-spec). F3_L19_Price_Delay should be DROPPED from any future iteration. Recent-regime ICIR concentration flag added to challenge_flags. RF-A3 trigger acknowledged."),
    C5 = list(severity="HIGH", classification="PARTIAL",
              codex_position="LIQ 5e7 < default 2e8 + turnover 7.7 > 6.0 cap",
              agent_position="LIQ 5e7 was specified by request.json (user-defined override per discovery WT). Default 2e8 is for deployment WT mandate. agent followed request explicitly. HOWEVER Iter 10 should re-run with LIQ 2e8 for deployability check. turnover 7.7 IS above 6.0 cap — this is alpha-level signal turnover. Optimizer applies TO penalty + buffer zone; final portfolio TO will be lower. Note: alpha-level top-20 raw turnover ≠ optimized portfolio TO. agent_action: explicit Optimizer hand-off note added (existing) + Iter 10 LIQ 2e8 mandate."),
    C6 = list(severity="MEDIUM", classification="ACCEPT",
              codex_position="No challenge_note.md, no artifact_lineage.json, AX-008 triangulation FAIL",
              agent_action="FIXED — challenge_note.md now created. lineage_utils::record_package_lineage() called. AX-008 partially satisfied (Codex critic = 2nd source; Architect would need to be 3rd, but Iter 10 design phase only)."),
    C7 = list(severity="MEDIUM", classification="PARTIAL",
              codex_position="Academic refs lack page-level + KR monthly-horizon evidence",
              agent_position="references list 5+ papers covering primary mechanism (Kim-Kim 2014, Hong-Stein 1999, Froot-O'Connell-Seasholes 2001, Choe-Kho-Stulz 2005, Brennan-Cao 1997). Page-level not provided in alpha agent stage (literature review depth is more appropriate at Scout/PG1). HOWEVER Codex correctly flags that Kim-Kim 2014 specifically validates KR daily/weekly herding-reversal but not necessarily monthly. agent_action: Iter 10 must verify Kim-Kim horizon + add Goyal et al. or Hwang-Salmon 2004 for KR monthly herding."),
    C8 = list(severity="MEDIUM", classification="REBUTTAL",
              codex_position="AX-007 deferred to optimizer is unproven",
              agent_position="Charter §10 Alpha Agent role card — Alpha Agent outputs alpha_vector + signal_matrix + factor_specs only. Sleeve structure / weighting / 20-name cap is OPTIMIZER's domain. Alpha Agent crossing into sleeve declaration violates 'No Silent Override' and 'Cooperative Behavior' principles. AX-007 exception (multi-sleeve / long-short / 50+ universe / ML sizing) is decided downstream when Optimizer constructs the actual portfolio. Alpha Agent's role-respectful answer is to attach signal_matrix and let Optimizer decide. evidence: Charter §10 + alpha_research_init.md scope + parent STR_1715 alpha_package.json also defers same concern to Optimizer."),
    C9 = list(severity="HIGH", classification="ACCEPT",
              codex_position="6 rationalization phrases detected ('PASS_BORDERLINE', 'economic re-justification', 'DEFERRED_TO_OPTIMIZER', 'Counter-argument to data-mining concern', 'not a manual factor-level direction override', 'typically [0, 0.20]')",
              agent_action="ACCEPT 4-of-6 phrases as rationalization (PASS_BORDERLINE / economic re-justification / Counter-argument / not a manual override). REBUTTAL 2-of-6 (DEFERRED_TO_OPTIMIZER is a literal role-boundary statement per C8; 'typically [0, 0.20]' is informational). agent_action: revise hypothesis_summary + alternative_variants prose to remove rationalization framing; replace with honest 'V2 was sign-flipped after observing V1 NW-t=-4.23 sign reversal — this constitutes post-hoc method-shopping under Charter §5 unless ex-ante pre-registered, which it was NOT.'"),
    summary = "9 concerns: 4 ACCEPT (C2 fix, C3 cert deny, C4 F3 drop, C6 lineage) + 4 PARTIAL (C1 honest re-frame, C5 LIQ defer to Iter10, C7 Kim-Kim horizon caveat, C9 prose) + 1 REBUTTAL (C8 role boundary). NO BLANKET ACCEPT. NO SILENT REBUT."
  ),
  rationalization_audit_post_resolution = list(
    pass_phrases_remaining = 0L,
    note = "After resolution, primary recommendation is Iter 10 redesign, not V2 promotion. PASS_BORDERLINE replaced with FAIL_WITH_BORDERLINE_TECHNICAL_CERT_4COND."
  ),
  q_lead_escalate_trigger = list(
    high_severity_count = 5L,
    threshold = 5L,
    triggered = TRUE,
    rationale = "Charter §8 auto-escalate: HIGH severity ≥ 5. Q-Lead must review Iter 10 redesign before next discovery WT spawn. Alpha Agent self-denies certificate as cooperative response."
  )
)

# Update primary_variant disclaimer
draft$primary_variant <- "V1_FIAPAS_information_asymmetry_HONEST_RESULT"
draft$primary_variant_post_codex_revision_note <- paste0(
  "Post-Codex REJECT (4 ACCEPT + 4 PARTIAL + 1 REBUTTAL), agent reverts primary to V1 (information_asymmetry, NW-t=-4.23 honest negative). ",
  "V2 (herding_reversal sign-flipped) is documented as exploratory hypothesis requiring ex-ante pre-registration in Iter 10. ",
  "alpha_discovery_certificate NOT ISSUED. PG1 admission auto-denied via certificate absence. ",
  "Iter 10 redesign mandate: (a) LIQ 2e8 default mandate, (b) drop F3_L19_Price_Delay (Codex C4 marginal-negative), ",
  "(c) F1 mechanism pre-register before measurement, (d) Kim-Kim 2014 horizon verification, (e) ex-ante 2-spec design (F1+F2 only)."
)

draft$alpha_discovery_certificate <- alpha_discovery_certificate

draft$status <- "ALPHA_DONE_CERTIFICATE_NOT_ISSUED_GRADUATION_FAIL_ITER10_REDESIGN_REQUESTED"

# Write final
write_json(draft, file.path(WT_DIR, "alpha_package.json"),
           pretty=TRUE, auto_unbox=TRUE, na="null")
cat("alpha_package.json finalized (size =", file.info(file.path(WT_DIR, "alpha_package.json"))$size, "bytes)\n")

# ============================================================
# STEP F: Lineage call (R11 mandate)
# ============================================================
tryCatch({
  source(file.path(BASE_DIR, "02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(
    task_id = "WT-D20260428_001",
    package_type = "alpha_package",
    method_selected = "FIAPAS_3F_composite_V1_honest_V2_signflip_documented",
    input_file_paths = c(
      file.path(BASE_DIR, ".cache/factor_db/factor_db_*.parquet (240 monthly factor DB)"),
      file.path(BASE_DIR, ".cache/rawdata.parquet"),
      file.path(BASE_DIR, ".cache/benchmark.parquet")
    )
  )
  cat("lineage recorded\n")
}, error = function(e) {
  cat("Lineage call failed:", conditionMessage(e), "\n")
  cat("Manual lineage append below\n")
  # manual fallback
  lineage <- list(
    task_id = "WT-D20260428_001",
    package_type = "alpha_package",
    package_path = "qepm/mailbox/worktask/WT-D20260428_001/alpha_package.json",
    method_selected = "FIAPAS_3F_composite_V1_honest_V2_signflip_documented",
    input_file_paths = c(".cache/factor_db/factor_db_*.parquet", ".cache/rawdata.parquet", ".cache/benchmark.parquet"),
    output_artifacts = c("stage_artifacts/WT_D20260428_001/alpha_scores.parquet",
                         "stage_artifacts/WT_D20260428_001/alpha_validation.json",
                         "stage_artifacts/WT_D20260428_001/method_shopping_log.json",
                         "stage_artifacts/WT_D20260428_001/v2_diagnostics.rds",
                         "qepm/mailbox/worktask/WT-D20260428_001/alpha_discovery_certificate.json",
                         "qepm/mailbox/worktask/WT-D20260428_001/codex_critic_response_alpha.json",
                         "qepm/mailbox/worktask/WT-D20260428_001/challenge_note.md"),
    recorded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz="UTC")
  )
  write_json(list(lineage), file.path(WT_DIR, "artifact_lineage.json"),
             pretty=TRUE, auto_unbox=TRUE, na="null")
  cat("Manual artifact_lineage.json written\n")
})

cat("\n=== FINALIZE COMPLETE ===\n")
cat("Certificate issued:", issue_certificate, "\n")
cat("Status: ALPHA_DONE (revised post-Codex)\n")
