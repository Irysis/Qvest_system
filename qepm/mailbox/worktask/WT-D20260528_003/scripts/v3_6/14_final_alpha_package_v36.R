#==============================================================================
# Final alpha_package.json v3.6 (post-Codex revisions)
#
# Codex stance: REJECT. 9 concerns. Adjudication:
#   ACCEPT: C1, C2, C3, C4, C5, C9 (6)
#   PARTIAL: C6, C7 (2)
#   REBUTTAL: C8 (1)
#
# All ACCEPT concerns numerically corrected.
# PreToolUse codex_round_pre_enforcer.sh requires: alpha_package_draft.json exists +
# codex_critic_response_alpha.json exists. Both present → final write allowed.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_6")
WT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003_v3_6")
STAGE_DIR_CODEX <- file.path(BASE, "qepm/stage_artifacts/WT_WT-D20260528_003")

cat("[Final v3.6] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load draft + Codex response + revisions ----
draft <- fromJSON(file.path(WT_DIR, "alpha_package_draft.json"), simplifyVector = FALSE)
codex <- fromJSON(file.path(WT_DIR, "codex_critic_response_alpha.json"), simplifyVector = FALSE)
revisions <- fromJSON(file.path(OUT_DIR, "codex_revisions_v36.json"), simplifyVector = FALSE)

# ---- 2. Load updated alpha_scores (post-C5 fix, latest sig_date 2023-11-30) ----
alpha_scores <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))
alpha_scores[, Date := as.Date(Date)]
latest_d <- max(alpha_scores$Date)
latest_sub <- alpha_scores[Date == latest_d]
setorder(latest_sub, -alpha_score)
cat("Latest sig_date:", as.character(latest_d), " | N tickers:", nrow(latest_sub), "\n")

# Update alpha_vector
alpha_vector <- as.list(round(latest_sub$alpha_score, 4))
names(alpha_vector) <- latest_sub$Ticker

# Confidence vector — derive from recent 3 sig_dates rank stability
recent_3 <- sort(unique(alpha_scores$Date), decreasing = TRUE)[1:3]
recent_dt <- alpha_scores[Date %in% recent_3]
recent_dt[, rank := frank(-alpha_score), by = Date]
rank_stab <- recent_dt[, .(rank_cv = sd(rank, na.rm = TRUE) / mean(rank, na.rm = TRUE),
                              N = .N), by = Ticker]
rank_stab[is.na(rank_cv), rank_cv := 1.0]
max_cv <- max(rank_stab$rank_cv, na.rm = TRUE)
rank_stab[, conf := pmax(pmin((1 - rank_cv / max_cv * 0.7) * (N / 3), 1.0), 0.1)]
conf_map <- rank_stab[Ticker %in% latest_sub$Ticker, .(Ticker, conf)]
conf_map <- merge(latest_sub[, .(Ticker)], conf_map, by = "Ticker", all.x = TRUE)
conf_map[is.na(conf), conf := 0.3]
confidence_vector <- as.list(round(conf_map$conf, 3))
names(confidence_vector) <- conf_map$Ticker

# ---- 3. Build final alpha_package.json ----
cat("Building final alpha_package.json ...\n")

# Inherit factor_specs, method_log, axiom_compliance from draft
package <- draft

# OVERRIDE alpha_vector + confidence_vector (post-C5 fix)
package$alpha_vector <- alpha_vector
package$confidence_vector <- confidence_vector
package$as_of_date <- "2026-05-28"
package$latest_sig_date_emitted <- as.character(latest_d)

# Update hypothesis_description with Codex outcome
package$hypothesis_description <- paste0(
  "v3.6 PIVOT spec (Q-Lead Option 1 mandate 2026-05-28). v3.5 → v3.6 fixes: ",
  "(1) Sector neutralization (Asness-Frazzini 2013 dummy regression residual, per-Date per-family); ",
  "(2) HMM 4-state via depmixS4 (Hamilton 1989) replacing K-means 9-state; ",
  "(3) 3-way single vs composite vs regime-weighted composite RF-A2 verdict. ",
  "v3.6 PRE-CODEX claimed: 2/3 fix PASS; RF-A2 still FAIL. ",
  "Codex REJECT (5 HIGH + 3 MEDIUM + 1 LOW concerns) revealed: ",
  "(a) Fix 2 HMM PASS OVERSTATED — true fallback over 82 alpha dates = 36.6% (> 30% target FAIL), not 10.8%; ",
  "(b) Pre-cutoff regime state counts S2=4 (post-cutoff incl S2=9) — PIT-C1 violation in diagnostic; ",
  "(c) alpha_vector stale (was 2023-10-31 fwd_ret-dependent); corrected to latest pre-cutoff 2023-11-30. ",
  "Final verdict: only fix 1 (sector retention 67.8%) genuinely PASS. ",
  "3 cycles FAIL (v1 + v3.5 + v3.6) — Charter §5 Data Mining 방지 정합 = TERMINATE STR_1721 family 권고."
)

# Update diagnostics — replace overstated metrics with Codex-corrected ones
package$diagnostics$regime_diag$fallback_pct_pre_codex <- 10.8
package$diagnostics$regime_diag$fallback_pct_corrected <- 36.6
package$diagnostics$regime_diag$fallback_target_lt_30_corrected_verdict <- FALSE
package$diagnostics$regime_diag$state_specific_pct_corrected <- 63.4

package$diagnostics$regime_diag$state_counts_pre_codex <- list(S1 = 8, S2 = 9, S3 = 25, S4 = 49)
package$diagnostics$regime_diag$state_counts_pre_cutoff_pit_strict <- list(S1 = 8, S2 = 4, S3 = 17, S4 = 37)
package$diagnostics$regime_diag$pit_c1_violation_acknowledged <- TRUE
package$diagnostics$regime_diag$pit_c1_violation_detail <- "Pre-Codex state counts S2=9 included post-cutoff data (2024-2026). PIT-strict (clip <= 2023-12-22): S2=4, well below n>=30 target."

# Update v3_5_v3_6_fix_effectiveness with Codex corrections
package$v3_5_v3_6_fix_effectiveness$fix_2_regime_state_reduction$v3_6_result_pre_codex <- list(
  fallback = 10.8, fallback_target_lt_30_claim = TRUE)
package$v3_5_v3_6_fix_effectiveness$fix_2_regime_state_reduction$v3_6_result_codex_corrected <- list(
  fallback_full_over_82_dates = 36.6,
  fallback_target_lt_30_corrected = FALSE,
  state_specific_full = 63.4,
  all_state_fallback = 8.5,
  bootstrap_overall = 7.3,
  no_weight_row_equal_weight = 20.7
)
package$v3_5_v3_6_fix_effectiveness$fix_2_regime_state_reduction$verdict_pre_codex <- "PASS"
package$v3_5_v3_6_fix_effectiveness$fix_2_regime_state_reduction$verdict_codex_corrected <- "FAIL"
package$v3_5_v3_6_fix_effectiveness$fix_2_regime_state_reduction$per_state_monthly_caveat <- "Pre-cutoff PIT-strict: S1=8 / S2=4 / S3=17 / S4=37. Only S3, S4 meet n>=30."

# Add new challenge flags from Codex
new_flags <- c(
  package$challenge_flags,
  "CODEX_C3_HMM_FIX_OVERSTATED_ACCEPT: full fallback over 82 alpha dates = 36.6% > 30% target FAIL. Pre-Codex 10.8% only counted 65 state_w rows, missed 17 no-weight-row equal-weight months. Fix 2 verdict revised PASS->FAIL.",
  "CODEX_C4_PIT_C1_VIOLATION_ACCEPT: regime_labels_monthly_v36 included post-cutoff data (2024-2026, n=25 rows). State counts S2 dropped from 9 (full) to 4 (pre-cutoff strict). PIT-C1 diagnostic contamination acknowledged.",
  "CODEX_C5_ALPHA_VECTOR_STALE_ACCEPT: pre-Codex alpha_vector at 2023-10-31 (fwd_ret label dependency). Corrected to 2023-11-30 (latest pre-cutoff sig_date, PIT-safe via regime_state_lag1 + past IC weights, NO fwd_ret label required).",
  "CODEX_C6_AX_008_PARTIAL: stage_artifacts namespace mirror created at qepm/stage_artifacts/WT_WT-D20260528_003/. Missing weights/covariance/risk/optimization packages are NORMAL for alpha stage (Common Charter §8 role boundary).",
  "CODEX_C7_PIT_C15_MACRO_PARTIAL_RETAIN: load_month_factors() API gap for macro time-series. Architect agent advisory queue 적립. PIT-C9 expanding-z 본질 보장.",
  "CODEX_C8_AX_007_REBUTTAL: Optimizer/Judge 단계 책임. Alpha 산출 = universe-wide score (200 stocks K200), downstream evaluate.",
  "CODEX_C9_LIQUIDITY_CONFLICT_ACCEPT: request.json 5e7 vs base hard mandate 2e8 conflict. Q-Lead governance decision needed.",
  "Q_LEAD_AUTO_ESCALATE: HIGH=5 (>= threshold 5) + AX-001 v2 hard FAIL (crisis_alpha negative) + PIT-C1 violation (C4). Auto-escalate trigger 발동."
)
package$challenge_flags <- new_flags

# Update red_flags
package$red_flags$RF_A2 <- TRUE
package$red_flags$RF_A2_severity <- "HIGH"
package$red_flags$RF_A4 <- FALSE
package$red_flags$RF_A4_fix_applied <- TRUE
package$red_flags$harvey_pass_below_3 <- TRUE
package$red_flags$hmm_fix_overstated_codex_C3 <- TRUE
package$red_flags$pit_c1_post_cutoff_diagnostic_C4 <- TRUE
package$red_flags$alpha_vector_stale_C5_fixed <- TRUE
package$red_flags$liquidity_conflict_C9 <- TRUE

# Update PIT compliance with Codex acknowledgment
package$pit_compliance$C1_pre_cutoff_strict_codex_C4 <- "ACCEPT — pre-Codex regime state diagnostic included post-cutoff data. Pre-cutoff strict state counts S1=8/S2=4/S3=17/S4=37."
package$pit_compliance$C15_macro_codex_C7 <- "PARTIAL retain — load_month_factors() API designed for cross-section Z, not macro time-series single value. PIT-C9 expanding-z PIT 본질 보장. Architect advisory: load_macro_factors() API 신설 권고."

# AX-001 v2 hard FAIL acknowledge
package$axiom_compliance$AX_001v2_defensive_conditional_codex_acknowledge <- TRUE
package$axiom_compliance$AX_001v2_defensive_conditional <- "HARD FAIL: bad period mean IC = -0.1232 (3 crisis dates). bad/normal ratio = -4.8227 (negative). Crisis alpha REVERSED. AX-001 v2 condition (bad/normal >= 0.5 OR bad > 0) 미충족."

# Q-Lead auto-escalate
package$q_lead_auto_escalate <- TRUE
package$q_lead_auto_escalate_reason <- list(
  high_severity_count = 5,
  threshold = 5,
  pit_c1_violation = "C4 post-cutoff diagnostic acknowledged",
  ax_001_v2_hard_fail = "crisis_alpha NEGATIVE, bad/normal ratio = -4.82"
)

# Codex round summary
package$codex_round <- list(
  performed = TRUE,
  model = "gpt-5.5",
  effort = "xhigh",
  audit_log = "/tmp/codex_qepm_critic_WT-D20260528_003_alpha_1779956912.log",
  response_file = "codex_critic_response_alpha.json",
  stance = "REJECT",
  veto_flag = FALSE,
  weakest_assumption = codex$weakest_assumption,
  concerns_total = 9,
  concerns_HIGH = 5,
  concerns_MEDIUM = 3,
  concerns_LOW = 1,
  adjudication_summary = list(
    ACCEPT = c("C1 graduation fail", "C2 RF-A2", "C3 HMM fix overstated",
                "C4 post-cutoff PIT-C1", "C5 alpha_vector stale", "C9 liquidity conflict"),
    PARTIAL = c("C6 AX-008 namespace mirror", "C7 PIT-C15 macro architect advisory"),
    REBUTTAL = c("C8 AX-005/007 Optimizer scope")
  ),
  ax_axiom_compliance = list(
    AX_003 = "PASS", AX_004 = "PASS",
    AX_005 = "FAIL (per Codex, AX-005 EXCLUSION proof Optimizer 단계 책임 — REBUTTAL by scope)",
    AX_007 = "FAIL (per Codex, AX-007 EXCLUSION proof Optimizer 단계 책임 — REBUTTAL by scope)",
    AX_001_v2 = "HARD FAIL — crisis_alpha negative ACCEPT",
    AX_002 = "PASS (honest reporting, no rationalization retain)",
    AX_008 = "PARTIAL — alpha stage 4 artifacts complete (alpha_package + alpha_scores + alpha_validation + challenge_note). risk/optimization 누락은 정상 (Charter §8 역할 경계)."
  ),
  rationalization_red_flags_detected = list(
    "Markov chain persistence high mitigates sparse-state risk",
    "only required >=8 for HMM identification",
    "load_month_factors() designed for cross-section Z assignment doesn't apply",
    "Score-based universe alpha vector; downstream Optimizer responsibility",
    "Mitigation downstream: forge backtest carry-forward semantics"
  ),
  challenge_note = "challenge_note.md (Codex Round 5단계 흐름 final note)",
  auto_escalate_q_lead = TRUE,
  auto_escalate_reason = "HIGH = 5 (threshold reached) + AX-001 v2 hard FAIL + PIT-C1 violation"
)

# Final graduation status — TERMINATE 권고
package$final_graduation_status$status <- "FAIL"
package$final_graduation_status$pass_count <- "1 of 9 metrics POST-CODEX (Subperiod stability 1.00 PASS; ICIR 0.224 borderline; all others FAIL or borderline-FAIL)"
package$final_graduation_status$fail_count <- "8 of 9 metrics (Rank IC, Harvey, DSR, Monotonicity, AX-001 v2, Turnover, RF-A2, fallback corrected 36.6%)"
package$final_graduation_status$codex_stance <- "REJECT"
package$final_graduation_status$reasoning <- paste0(
  "v3.6 PIVOT 3 fix axes Codex-corrected verdict: ",
  "Fix 1 (sector retention 67.8%) PASS — Asness-Frazzini residualization 성공. ",
  "Fix 2 (HMM fallback) FAIL — pre-Codex 10.8% overstated; actual 36.6% over 82 dates. ",
  "Fix 3 (RF-A2) FAIL — composite_rw_neut 0.224 < single F_low_vol_raw 0.386. ",
  "Additional: Rank IC 0.020 < 0.04 threshold, Harvey 0/5 strict, DSR=0, ",
  "AX-001 v2 crisis_alpha NEGATIVE (-0.12), Monotonicity 0.07. ",
  "1/3 fix PASS - 인정. 그러나 graduation gate 8개 FAIL."
)
package$final_graduation_status$q_lead_recommendation_primary <- paste0(
  "TERMINATE STR_1721 family — Charter §5 Data Mining 방지 정합: ",
  "v1 (composite 64% dilution, regime same-date IC artifact) + ",
  "v3.5 (Harvey 1/5, sector retention 48.1%, composite 0.339 < single 0.393) + ",
  "v3.6 (3 fix axes 1/3 PASS, RF-A2 still fail, AX-001 v2 crisis reverse) = ",
  "3 cycles FAIL. Composite paradigm forcing inflate via Data Mining."
)
package$final_graduation_status$q_lead_recommendation_secondary <- list(
  salvage_path_a = "Long-short F_low_vol_neut vs F_quality_neut (ICIR spread 0.275 - (-0.065) = 0.340). AX-007 long-short exception applies.",
  salvage_path_b = "ML-based dynamic factor selection (XGBoost/LightGBM net-of-cost loss). AX-007 ML sizing exception applies.",
  salvage_path_c = "F_low_vol_neut single-family 50+ name diversification (no top20 single sleeve). AX-007 50+ diversification exception applies.",
  pivot_terminate_default = "Charter §5 정합 default = TERMINATE. Salvage paths require explicit 도훈 mandate."
)
package$final_graduation_status$alternative_terminate_path <- "STR_1721 family terminated after 3 cycles. Suggested new WT: ML/long-short hypothesis (별개 WT-D... 발급 필요)."

package$status <- "GRADUATION_FAIL_CODEX_REJECT_TERMINATE_RECOMMENDED_PENDING_Q_LEAD"
package$built_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
package$agent <- "alpha-research-v3.6-pivot-codex-revised"

# ---- 4. Write final alpha_package.json (PreToolUse codex_round_pre_enforcer.sh allows) ----
final_path <- file.path(WT_DIR, "alpha_package.json")
writeLines(toJSON(package, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            final_path)
cat("FINAL: ", final_path, "\n")

# ---- 5. Also mirror to stage dirs ----
file.copy(final_path, file.path(STAGE_DIR_CODEX, "alpha_package.json"), overwrite = TRUE)

cat("\n[Final v3.6] === DONE === elapsed:",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")
cat("alpha_package.json final saved.\n")
cat("Q-Lead auto-escalate: TRUE (HIGH=5 + AX-001 v2 hard FAIL + PIT-C1 violation)\n")
