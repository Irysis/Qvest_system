# =============================================================================
# Cycle 5 — Build risk_package.json (final, post-Codex round)
# =============================================================================
# Codex disposition 반영 + corrections + ax_008 final + qlead_escalate
# =============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
hd <- "qepm/mailbox/research/risk_cycle5_20260507"

# Load draft
draft <- fromJSON(file.path(hd, "risk_package_draft.json"), simplifyVector = FALSE)

# Load codex response
codex_resp <- fromJSON(file.path(hd, "codex_critic_response_risk.json"), simplifyVector = FALSE)

# ---- Corrections from Codex round ----

# Correction 1: AX-001 v2 overall_verdict 정정
draft$axis_5_regime_shift_markov$ax_001_v2_check$overall_verdict <-
  "PASS_3_OF_3_WITH_MARGINAL_TEST3 — Test 1 + Test 2 strict PASS, Test 3 marginal (cor crisis -0.485 vs normal -0.477 = 0.008 차이). 정식 lifecycle bootstrap CI + IC ratio direct measurement (alpha-research scope) 의무. Charter §7 conditional defense 강화 retain."

# Correction 2: axis 3 dcc sim seed casting issue 명시
draft$axis_3_crowding_evolution_forward$dcc_sim_outcome <- list(
  status = "FAIL_SEED_CASTING",
  error_msg = "supplied seed is not a valid integer (rmgarch 1.3-9 dccsim)",
  fallback = "DCC fit + 12-step forward forecast successful (mean reversion to static cor)",
  ar1_fallback_applied = "AR(1) on 12m rolling correlations as alternative forward projection",
  rationale = "DCC sim 1000-trial seed casting issue (R version + rmgarch interaction). 정식 lifecycle 시 seed integer cast 강제 + rerun 의무"
)

# Correction 3: BM proxy caveat 강화
draft$axis_2_te_drift_forward$bm_proxy_caveat_strict <- list(
  current_definition = "active overlay TE = r_Hybrid_70_15_15 - r_AR (Hybrid vs STR_1715 standalone)",
  charter_2_alternative = "Charter §2 active risk valid alternative: portfolio - existing primary alpha (Hybrid - AR baseline)",
  formal_BM_obligation = "정식 risk-research WT spawn 시 KOSPI/KOSDAQ benchmark active risk 의무. 본 cycle proxy retain은 monitoring inheritance baseline only",
  h1_te_NA_acknowledged = "h=1m TE rows NA (1-month sd undefined for stationary bootstrap block 1) — 정직 명시 retain"
)

# ---- Final risk_package.json ----

risk_package <- draft

# Add Codex disposition section
risk_package$codex_critic_round_status <- list(
  stage = "post_codex_round_disposition_final",
  codex_response_path = "qepm/mailbox/research/risk_cycle5_20260507/codex_critic_response_risk.json",
  codex_stance = "REJECT",
  codex_veto = FALSE,
  codex_concerns_count = 10L,
  codex_severity_distribution = list(
    HIGH = 7L,
    MEDIUM = 3L
  ),
  challenge_note_path = "qepm/mailbox/research/risk_cycle5_20260507/risk_challenge_note.md",
  rationalization_corrections_count = 1L,
  consecutive_codex_reject = "5 cycles (1+2+3+4+5)"
)

# Add Codex concerns disposition (8-field schema)
risk_package$cycle5_codex_concerns_disposition <- list(
  C1_artifacts_absence = list(
    severity = "HIGH",
    codex_text = "user-specified stage artifact dirs, weights.csv, alpha_scores.parquet, covariance.parquet, and 3-agent context absent",
    cycle5_disposition = "ACCEPT",
    rebuttal_argument = "Q-Lead 온디맨드 메타 리서치 scope 자체. 정식 WT path는 qepm/mailbox/worktask/{WT_id}/. Cycle 5 path qepm/mailbox/research/risk_cycle5_20260507/는 _meta_self_research 명시. 본 cycle은 hypothesis generation, formal approval-grade verification cannot be completed (Codex 정확 식별)",
    action = "scope_disclaimer + research_type=meta_self_research_qlead_ondemand_cycle5_time_projecting retain. termination_recommendation 정식 lifecycle 권고 retain",
    evidence = "scope_disclaimer field + termination_recommendation 5 next actions",
    citations = list("Lopez de Prado 2018 AFML Ch.13", "L-272", "AX-002 process honesty")
  ),
  C2_post_shrink_sigma_absence = list(
    severity = "HIGH",
    codex_text = "no BΩB'+D, no post-shrink covariance, no shrinkage delta, no Ledoit-Wolf/Gerber/RMT comparison, no selection-objective log, no cond<=100 evidence, no factor coverage R2",
    cycle5_disposition = "ACCEPT",
    rebuttal_argument = "사이클 1~4 inheritance 한계. 본 cycle 5는 시간 projecting axis 추가, security-level Σ 정식 lifecycle 의무 retain",
    action = "정식 risk-research WT spawn 시 (a) Ledoit-Wolf direct + cond<=100 (b) Gerber/RMT 비교 (c) selection_objective enum (d) factor coverage R² (e) BΩB'+D 종목 단위 — 사이클 4 next_action_recommendation 의무 retain",
    evidence = "사이클 1 covariance_3src_5estimator_summary.csv + 사이클 2 covariance_4src_5estimator_summary.csv + 사이클 4 axis2_regime_sigma_pd.csv inheritance",
    citations = list("Ledoit-Wolf 2003 JEFAS", "Pfaff 2016 FRM Ch.4-9", "L-274")
  ),
  C3_fixed_weight_static = list(
    severity = "HIGH",
    codex_text = "70/15/15 is projected over post-2015 returns without walk-forward alpha→risk→optimizer recalculation",
    cycle5_disposition = "PARTIAL_ACCEPT",
    rebuttal_argument = "ACCEPT: walk-forward 자체는 정식 lifecycle 의무. 본 cycle은 hypothesis generation. PARTIAL REBUTTAL: 시간 projecting axis는 fixed-weight static과 다른 차원 — Politis-Romano stationary bootstrap (block L=12) + DCC-GARCH 12-step forward + Markov simulation은 forward-looking statistical projection. Charter §2 'Realized vs Predicted' 사전 monitoring budget 산출 자체가 본 cycle 목적",
    action = "walk_forward_caveat 명시 retain. termination_recommendation 정식 lifecycle 진입 권고 retain. Hypothesis generation 차원 + monitoring agent 인계 alert thresholds 정량 산출 가치 retain",
    evidence = "5축 forward-looking method (axis 1 MC 2000 trials × 4 horizon, axis 2 regime-conditional bootstrap, axis 3 DCC 12-step + AR(1) fallback, axis 4 Mann-Kendall + Pettitt change-point, axis 5 Markov 1000 trial)",
    citations = list("Politis-Romano 1994 JASA", "Engle 2002 JBES", "L-119 정적 EW 팩터 블렌드 패턴")
  ),
  C4_regime_n_fragility = list(
    severity = "HIGH",
    codex_text = "Full-sample Hybrid quantiles, CRISIS n=13, no pooled fallback or bootstrap CI",
    cycle5_disposition = "ACCEPT",
    rebuttal_argument = "사이클 4 동일 한계 (n=14 → cycle 5 n=13). 통계 검증 traditional n>=30 미달, pooled fallback / bootstrap CI 정식 lifecycle 의무",
    action = "red_flags.RF_R9_regime_n_insufficient 명시 retain. EVT GPD parametric extension (Pfaff 2016 Ch.7) 정식 lifecycle 의무 명시",
    evidence = "post-2015 regime n: BULL 41 / NORMAL 40 / CAUTION 41 / CRISIS 13. Markov transition CRISIS row only 13 transitions",
    citations = list("Pfaff 2016 FRM Ch.7", "Hamilton 1989 ECMA", "L-274")
  ),
  C5_tail_risk_missing = list(
    severity = "HIGH",
    codex_text = "no CVaR95 cap test, CDaR95, Hill alpha, EVT-GPD, VaR99/ES99, or named 8-period stress table",
    cycle5_disposition = "ACCEPT",
    rebuttal_argument = "본 cycle 5 tail-risk 직접 산출 X. 사이클 1+2+4 inheritance. 정식 lifecycle 의무",
    action = "정식 risk-research WT spawn 시 CVaR95/CDaR95/VaR99/ES99 + EVT GPD + 8 named stress periods 의무. red_flags.RF_R6 명시 retain",
    evidence = "사이클 1 bm_kospi_36yr_tail_fit.csv + 사이클 2 candidates_tail_risk_metrics.csv + 사이클 4 axis3_8stress_historical.csv inheritance",
    citations = list("Pfaff 2016 FRM Ch.4 + Ch.7", "Bertsimas-Lauprete-Samarov 2004", "L-129")
  ),
  C6_crowding_wrong_object = list(
    severity = "HIGH",
    codex_text = "Pairwise correlations do not clear TDC vs PG2 active book, HHI, style correlation >0.7, family saturation",
    cycle5_disposition = "ACCEPT",
    rebuttal_argument = "PG2 active book × 6-source style correlation 정식 lifecycle scope. 사이클 4 C5 동일 disposition (ACCEPT_OUT_OF_SCOPE)",
    action = "정식 risk-research WT spawn 시 PG2 active book TDC + sleeve HHI + style correlation > 0.7 + L-219 family saturation 의무",
    evidence = "본 cycle 3-source pairwise cor recent 12m max abs 0.355 (vs warning 0.50)",
    citations = list("Brunnermeier-Pedersen 2009 RFS", "L-219")
  ),
  C7_ax_001_overclaim = list(
    severity = "HIGH",
    codex_text = "KR10y bad/normal correlation differs by only 0.008, uses correlation rather than IC, CRISIS n=13 full-sample labels, sits beside 76% KR10y SR decay",
    cycle5_disposition = "PARTIAL_ACCEPT",
    rebuttal_argument = "ACCEPT: 0.008 차이 marginal — Test 3 marginal 명시 retain. CRISIS n=13 full-sample labels PIT-C5 limitation. KR10y 60m SR 0.07 (76% decay) 정량 명시. PARTIAL REBUTTAL: AX-001 v2 conditional defense는 IC ratio 단일 metric 아니라 3-test (crisis_alpha + Core MDD relief + bad/normal IC ratio). Test 1 + Test 2 strict PASS",
    action = "ax_001_v2_check.test3 marginal 명시 retain. overall_verdict 'PASS_3_OF_3_WITH_MARGINAL_TEST3' 정정. 정식 lifecycle conditional defense 강화 의무 (Q07 + multi-axis quality + BAB)",
    evidence = "Test 1 KR10y CRISIS +0.0038/m. Test 2 Hybrid MDD -15.7% vs AR -25.2% = 9.5pp relief. Test 3 cor crisis -0.485 vs normal -0.477 (0.008 차이)",
    citations = list("AX-001 v2 (L-274)", "Frazzini-Pedersen 2014 JFE")
  ),
  C8_te_bm_proxy = list(
    severity = "MEDIUM",
    codex_text = "TE drift uses Hybrid minus AR as alternative because KOSPI BM cache absent. Not formal BM active risk. h=1 TE blank",
    cycle5_disposition = "PARTIAL_ACCEPT",
    rebuttal_argument = "ACCEPT: 정식 BM active risk = vs KOSPI/KOSDAQ 의무. h=1 TE blank (1-month sd undefined). PARTIAL REBUTTAL: Charter §2 active risk = portfolio - existing primary alpha valid alternative",
    action = "BM_proxy_caveat 명시 강화 (정식 lifecycle BM (KOSPI/KOSDAQ) active risk 의무 explicit). h=1 TE NA 정직 명시 retain",
    evidence = "te_active_baseline_ann 0.0652 + per-regime TE",
    citations = list("Charter §2", "Roll 1992 JoPM")
  ),
  C9_dcc_mc_file_absent = list(
    severity = "MEDIUM",
    codex_text = "axis3_summary references axis3_dcc_mc_12m_forward.csv, but that file is absent",
    cycle5_disposition = "ACCEPT",
    rebuttal_argument = "dcc sim 1000-trial 시 seed coercion error 발생 → file 미생성. axis3_summary.json은 reference만 명시",
    action = "dcc_sim_outcome FAIL_SEED_CASTING 명시 + AR(1) fallback에 의존 retain. 정식 lifecycle 시 seed integer cast 강제 + rerun 의무",
    evidence = "DCC fit successful + 12-step forward forecast successful (mean reversion). dccsim 1000-trial seed error → AR(1) fallback (axis3_ar1_forward12m.csv)",
    citations = list("Engle 2002 JBES", "rmgarch documentation")
  ),
  C10_ax_008_incomplete = list(
    severity = "MEDIUM",
    codex_text = "Forge OK, Codex pending, Architect NA after four prior Codex REJECT cycles; another meta cycle cannot create the required two independent PASS sources",
    cycle5_disposition = "ACCEPT",
    rebuttal_argument = "5 consecutive Codex REJECT (cycle 1~5). Architect NA risk-research scope. AX-008 2/3 PASS 충족 path = 정식 lifecycle Architect 검증 의무",
    action = "ax_axiom_compliance.ax_008 status 'FAIL_INCOMPLETE_5_CONSECUTIVE_CODEX_REJECT' 명시. termination_recommendation 정식 lifecycle 진입 의무 retain",
    evidence = "Cycle 1+2+3+4+5 = 5 consecutive Codex REJECT (veto=false)",
    citations = list("AX-008 (L-159/167/168)", "L-272")
  )
)

# Update ax_008 status (final)
risk_package$ax_axiom_compliance$ax_008_verification_triangulation <- list(
  status = "FAIL_INCOMPLETE_5_CONSECUTIVE_CODEX_REJECT",
  evidence = "1/3 (Forge OK + Codex REJECT + Architect NA). 5 consecutive Codex REJECT (cycle 1~5) — 메타 path saturation 결정적 증거. 정식 lifecycle Architect 검증이 AX-008 2/3 충족 path"
)

# Update ax_001 status (post-correction)
risk_package$ax_axiom_compliance$ax_001_v2_conditional_metric <- list(
  status = "PASS_MARGINAL",
  evidence = "Test 1 KR10y CRISIS +0.0038/m PASS / Test 2 Hybrid MDD -15.7% vs AR -25.2% PASS / Test 3 cor crisis -0.485 vs normal -0.477 (0.008 차이) marginal. 정식 lifecycle bootstrap CI + IC ratio direct measurement (alpha-research scope) 의무"
)

# Add qlead_escalate
risk_package$qlead_escalate <- list(
  triggered = TRUE,
  trigger_criteria = list(
    high_severity_count = 7L,
    high_severity_threshold = 5L,
    ax_axiom_hard_fail_count = 3L,
    ax_axiom_threshold = 3L,
    pit_hard_violation_new = FALSE,
    consecutive_codex_reject = 5L
  ),
  escalate_summary = "Codex 사이클 5 REJECT (veto=false) — HIGH 7 + MEDIUM 3. 5 consecutive cycles (1~5) Codex REJECT 패턴은 메타 path saturation 결정적 증거. AX-001 v2 PASS_MARGINAL + AX-002 + AX-008 FAIL. 정식 alpha-research → risk-research → optimizer-research lifecycle 진입이 path forward (walk-forward / Q07 direct / post-shrink Σ / KRX 옵션 / PG2 active book / Architect 검증).",
  qlead_action_recommended = list(
    action_1 = "메타 리서치 cycle 5 종료 (TERMINATE_BENEFICIAL_FORMAL_LIFECYCLE_NOW)",
    action_2 = "정식 alpha-research WT spawn (Q07 + multi-axis quality + Defensive Frazzini-Pedersen factor specs)",
    action_3 = "정식 risk-research WT spawn (BΩB'+D + post-shrink Σ + PG2 crowding + EVT GPD + walk-forward)",
    action_4 = "정식 optimizer-research WT spawn (70/15/15 retain vs ERC vs 70/10/10/10)",
    action_5 = "monitoring agent 사이클 5 alert thresholds 5축 인계 (P1 IMMEDIATE: TSMOM 60m 32% decay + KR_10y 60m 76% decay)",
    action_6_parallel = "KRX OpenAPI 인증 + KOSPI200 옵션 chain cron 등록 (사이클 1~4 retain)"
  )
)

# Set version
risk_package$version <- "v2_post_codex_round_disposition_final"
risk_package$cycle <- 5L

# Write final
write_json(risk_package, file.path(hd, "risk_package.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string")

cat("[Build final] DONE\n")
cat("Path:", file.path(hd, "risk_package.json"), "\n")
cat("Status: REJECT (5 consecutive cycles 1~5) — TERMINATE_BENEFICIAL_FORMAL_LIFECYCLE_NOW\n")
