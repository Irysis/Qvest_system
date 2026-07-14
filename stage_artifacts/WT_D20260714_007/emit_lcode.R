setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
`%||%` <- function(a,b) if(is.null(a)||length(a)==0) b else a
source("02_Infrastructure/axiom/lcode_emit.R")
lesson <- paste0(
"[weighted_screen 실측] R31 FQ-047 밸류 정의 스펙트럼 확장 x B2 tier-조건부(non-mega만 value 틸트, mega 순수 base) = 밸류 아크(R26~FQ-046) 완결 라운드. 7 하위축: BM(V01)·EP(V02)·CFP(V03)·FCF(V10)·SP(V20)·SHY(V11)·EBIT_EV(V14+V07 control). base=clean 0_stored_S7(production_parity_verified off0 T-1). ",
"★판정: VALUE_DEFINITION_AXIS = CONFIG-SCOPED NEGATIVE(screening/cap-w) + 프론티어. cap-w top-25 paired NW-t AND-게이트(paired>=2.0 ∧ dIR>=0.05) 통과 = EBIT_EV(2.378) 유일. 신규 6종 전멸: SP 1.523·SHY 1.275·BM 1.291·EP 1.229·CFP 0.332·FCF -0.214. R30 EBIT/EV screening 관통은 밸류 정의축으로 일반화 안 됨. ",
"★parity 확증: EBIT_EV B2가 R30 정확 재현(paired 2.378·dIR 0.232·var_pt 4.23·EWuni 6.59) — 하네스·base·B2 구성 verbatim. ",
"★정보성 결과 2건(정직): (1) 2024+ 감쇠는 정의-특이(value-보편 아님): EBIT_EV(pre 2.21->post 0.92)·FCF(0.00->-0.52) 감쇠 vs SP(0.99->1.85)·EP(0.77->1.33)·CFP(-0.03->0.79) 개선 = 밸류 정의축 내부 스타일 로테이션(기업가치배수 죽고 매출/이익 yield 살아있음). FQ-046 '2024+ value 감쇠' 서사 정련. (2) incumbent 잉여=구성-바운드(정의-바운드 아님): cor_active 전 정의 0.86~0.93 균일, EBIT/EV와 신호 직교(cross-corr 0.07)인 FCF조차 cor 0.928 = 잉여는 cap-w tier-틸트(w=0.3~base) 구성 산물 => '실낱 EV'(덜 중복 정의) 반증(caveat: cor_active screening 프록시·게이트 통과 EBIT/EV뿐이라 moot). ",
"특성화(게이트 미달분): SP placebo(N=40) p_emp 0.025 실신호·lag1 2.147(붕괴 없음 PIT-safe)·EWuni 6.60·oos 0.61(신규 최고)·dIR_post +0.104(신규 유일 양); EP p_emp 0.000·lag1 1.006. 둘 다 실신호·PIT-safe이나 cap-w AND-게이트 미달. ",
"하위축 상관(concern#1): EBIT_EV 기준 median cross-sec corr BM 0.64·EP 0.57·SP 0.61·SHY 0.47·CFP 0.30·FCF 0.07 = 진짜 독립 정의 다수(1테스트 아님). ",
"방법론: R28 recon_panels(clean 0_stored_S7)+factor_db 밸류 7종 aligned-z off0 T-1(R29 parity 승계) 재사용. cap-w authoritative(weighted_screen paired)+EW-uni dual-basis. n_trials_r31=7(chain-각 독립 정의·argmax 아님·DSR sweep 부적용, 진단만). value family 누적 ~15 trial(R26-R31). book_state/05_Production/outputs.ramp 무변경·02:00 insider crawl+R9 무접촉·DART API 금지·cov/weights 미산출(역할경계). pin R28_current_20260714·prereg_sha256 6e4d278c. ",
"아크 완결 답(도훈 '밸류 추가 방향 끝났나'): QEPM cap-w book-marginal=예(config-scoped 소진)-정의 전스펙트럼 중 EBIT/EV만 게이트, 그마저 FQ-046 자본 REJECT, 잉여 구성-바운드. 단 밸류 자체 사멸 아님-sales/earnings yield 2024+ 살아있고 EW-basis 강함. ",
"next_probe: P1(SP sales-yield->EW-basis/OVERLAY_CANDIDATE 재라우팅, V02_EP FQ-008/009 경로, feasible now); P2(EBIT/EV-vs-sales-yield 상대성과 monitoring tripwire-FQ-046 부활조건 정련, value 정의-로테이션 조기감지); P3(구성-바운드 잉여 우회-비-cap-w EW/벤치-상대 밸류 소비, RAMP 모드, 저순위)."
)
res <- emit_lcode(
  mode = "alpha_research",
  strategy_id = "R31_FQ047_VALUE_DEFINITION_SPECTRUM",
  grade = "C",
  lesson_text = lesson,
  metric_type = "canonical_screen",
  construction_type = "value_definition_spectrum x b2_nonmega_tier_conditional_slotting",
  selection_type = "chain",
  mechanism_hypothesis = "EBIT/EV 계열 밖 밸류 정의(BM/EP/CFP/FCF/SP/SHY)를 B2 관통구성(non-mega tier-조건부)으로 넣으면 2024+ recency 감쇠를 덜 겪거나 incumbent 잉여가 낮은 정의가 있는가. 결과: cap-w AND-게이트는 EBIT/EV 유일 통과(신규 6종 전멸). 감쇠는 정의-특이(SP/EP 개선), 잉여는 구성-바운드(정의 무관 cor~0.9). '밸류 추가 방향'=config-scoped 소진(EW-basis SP는 프론티어).",
  portfolio_alpha_t = 1.523,
  oos_months = 268L,
  core_reference = "FQ-047 (FQ-046 judge_reject 후속, 밸류 아크 완결); parent FQ-045 R30 L-AR-20260714_191441; base STR_1715_on_M4_R05_noLayer4_PG2 clean 0_stored_S7 production_parity_verified; prereg_sha256 6e4d278cd4f82734fe48eb70b7d955b231af91d6b43bb5c4d9b1cfbb27383e70",
  tags = c("book_enhancement","value_definition_spectrum","captier_conditional","non_mega_slotting",
           "value_arc_complete","config_scoped_negative","screen_tier","recency_definition_specific",
           "incumbent_redundancy_construction_bound","sales_yield_frontier","ew_basis_frontier",
           "captier_localization","pit_clean","lag1_robust","placebo_pass","value_definition_rotation",
           "fq_047","fq_046","frontier_open","chain_selection"),
  metrics = list(
    base_clean_capw_port_t = 3.058,
    BM_paired = 1.291, EP_paired = 1.229, CFP_paired = 0.332, FCF_paired = -0.214,
    SP_paired = 1.523, SHY_paired = 1.275, EBIT_EV_paired = 2.378,
    EBIT_EV_paired_r30_parity = 2.378, EBIT_EV_dIR = 0.232, EBIT_EV_varpt = 4.234,
    gate_pass_count_new = 0L, gate_pass_only = "EBIT_EV",
    EBIT_EV_pre2024 = 2.21, EBIT_EV_post2024 = 0.92,
    SP_pre2024 = 0.99, SP_post2024 = 1.85, SP_dIR_post = 0.104, SP_post17_t = 1.88,
    EP_pre2024 = 0.77, EP_post2024 = 1.33, CFP_post2024 = 0.79, FCF_post2024 = -0.52,
    cor_active_min = 0.859, cor_active_max = 0.929,
    SP_ewuni_t = 6.60, SP_ewuni_oos = 0.61, BM_ewuni_t = 6.73,
    SP_placebo_p = 0.025, SP_lag1 = 2.147, EP_placebo_p = 0.000, EP_lag1 = 1.006,
    subaxis_corr_fcf_ebitev = 0.07, subaxis_corr_bm_ebitev = 0.64,
    n_trials_r31 = 7L, value_family_cumulative_trials = 15L,
    next_probe = "P1 SP sales-yield EW-basis/OVERLAY 재라우팅(feasible now); P2 EBIT/EV-vs-sales-yield 정의-로테이션 monitoring tripwire; P3 비-cap-w EW/벤치-상대 밸류 소비(RAMP, 저순위)"
  ),
  dry_run = FALSE
)
cat("[emit] l_code=", res$l_code %||% res$entry$l_code %||% "?", "\n")
cat("EMIT_DONE\n")
