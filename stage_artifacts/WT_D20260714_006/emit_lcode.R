setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
`%||%` <- function(a,b) if(is.null(a)||length(a)==0) b else a
source("02_Infrastructure/axiom/lcode_emit.R")
lesson <- paste0(
"[canonical_screen 실측] R30 FQ-045 value(V14/V07) 잔여 소비면: (A)EW-상대 배포성 실사 + (B)MID-tier 조건부 슬로팅 = R29 next_probe P1(cap-tier 국소화) 직접 소비(R27->R28->R29->R30 chain). ",
"★★판정 B(핵심): cap-w 국소화 벽 최초 관통(screening). B2(non-mega=MID+OTHER에만 value 틸트, mega는 순수 base 유지): cap-w paired 2.378>=2.0 ∧ ΔIR 0.232>=0.05 = AND-게이트 PASS. R29 unconditional(모든 tier value, paired 1.243 FAIL) 대비 관통. placebo(value shuffle N=40) null max 1.104 <<2.378 p=0.000(실신호), lag1 2.473(동월 look-ahead 부재), paired-diff oos_v2 2.326. B1(MID-only 11-30) paired 1.072 FAIL => OTHER(소형가치 31+)가 견인. ",
"★단 자본 아님(screening-tier): holdout dIR -0.022·paired_HO 1.170·post2017_t 1.734<2.0·variant 절대 cap-w oos_v2 0.452<0.5 = 최근/OOS marginal 감쇠(관통은 IS/pre-2017 견인). metric_type=weighted_screen(cap-w) — forge build_bt_result authoritative 아님, graduation HARD 3종 미검증. wMID 0.062 = marginal이 top-25 tail 소가중 증폭(구현성 미검증). ",
"기전: value alpha=non-mega 국소(project-captier-alpha-localization). mega에 value 적용(R29)이 marginal 희석 -> mega 순수 base + non-mega만 value = paired 1.243->2.378. cap-w '탈출'이 아니라 cap-w 안 국소화 존중 = prior('long-only 횡단선택 cap-w 탈출 불가') 자본 반증 아님(screening만). ",
"★판정 A: pure-value EW track = band-조건부(oos_v2 0.659 in[0.5,0.7)·trailing-stable 2.14/2.13/2.26 감쇠 미검출·TO 5.0·break-even>50bps·capacity 36m 19억). BUT P-pure active-corr 0.50(basis-mixed)+overlap 19.5% > V02_EP 0.34(D3 독립불채택) => 독립 페이퍼트래킹 3호 부적격(redundant). Z6 blend EW(EWuni 6.39)=book-duplicate. value #3 = 독립 EW 트랙 부적격, 상위 EV 소비형태=Branch B(book-marginal). ",
"리스크: value_quality_spread 백분위 0.175(07-14, 06-24 사상최대서 압축)=늦은-사이클 리스크, holdout 양성=소진 되돌림 후행 가능성(B2 holdout dIR -0.022·pure-value post17 1.39 정합). ",
"방법론: R28 recon_panels(clean 0_stored_S7 production_parity_verified) + R29 value_panels(vz_off0 T-1 clean) 재사용 · cap-w authoritative(weighted_screen) + EW-uni dual-basis · B1/B2 tier-conditional + Z6/pureVal EW 재실사(n_trials_r30=4 chain, argmax 최종픽 없음, DSR sweep 부적용) · value family 누적 ~8 trial(R26-R30) · book_state/05_Production/outputs.ramp 무변경 · DART API 금지 · pin R28_current_20260714 · prereg_sha256 bc3d2dfd. ",
"next_probe: P1(B2 forge/graduation dossier) forge build_bt_result + judge HARD 3종(PORT_t 2.95·oos 0.7·calmar 0.64)+holdout falsification+DSR(family ~8)+book-marginal ΔIR(recon NAV), governor 정지·도훈 confirm(FQ 신설); P2(tier-cut 민감도+OTHER liq/capacity 정제, wMID 0.062 소가중 증폭 검증, IS-only); P3(recency 감쇠 판별+monitoring trailing-12m paired tripwire, spread 소진 후행 여부)."
)
res <- emit_lcode(
  mode = "alpha_research",
  strategy_id = "R30_FQ045_VALUE_CAPTIER_CONDITIONAL",
  grade = "C",
  lesson_text = lesson,
  metric_type = "canonical_screen",
  construction_type = "book_marginal_value_captier_conditional_slotting + ew_relative_deployability_audit",
  selection_type = "chain",
  mechanism_hypothesis = "value 잔여를 cap-tier-conditional(non-mega만 틸트)/EW-tilt로 재소비하면 cap-w book-marginal AND-게이트를 넘는가. B2(non-mega) paired 2.378 PASS(screening) — R29 unconditional 1.243 대비 관통, cap-tier 국소화 방향 확증. 단 holdout dIR -0.022·post2017 1.73 최근 감쇠 = screening-tier(자본 아님). pure-value EW 독립트랙은 P-pure 중복(corr 0.50)으로 부적격.",
  portfolio_alpha_t = 2.378,
  oos_months = 268L,
  core_reference = "FQ-045 (R29 next_probe P1 소비); parent FQ-044 R29 L-AR-20260714_172027 / FQ-041 R28 L-AR-20260714_164238 / FQ-040 R27 L-AR-20260714_161109; base STR_1715_on_M4_R05_noLayer4_PG2 (clean 0_stored_S7 production_parity_verified); prereg_sha256 bc3d2dfd6528a037b6005a7906a5b445a0e055eecc733db6cd9752d34af3ac04",
  tags = c("book_enhancement","book_marginal","value_zblend","z6_v14_v07","captier_conditional",
           "non_mega_slotting","captier_localization","screening_and_gate_pass","screen_tier",
           "config_scoped_positive","holdout_attenuation","recency_decay","ew_relative_track",
           "paper_track_3_reject_redundant","value_spread_late_cycle","pit_clean","lag1_robust",
           "placebo_pass","forge_dossier_candidate","fq_045","fq_044","frontier_open"),
  metrics = list(
    base_clean_capw_port_t = 3.058,
    B1_midonly_paired = 1.072, B1_midonly_dir = 0.046, B1_and_gate = FALSE,
    B2_nonmega_paired = 2.378, B2_nonmega_paired_is = 2.096, B2_nonmega_paired_ho = 1.170,
    B2_nonmega_dir_full = 0.232, B2_nonmega_dir_ho = -0.022, B2_and_gate = TRUE,
    B2_variant_port_t = 4.234, B2_post2017_t = 1.734, B2_lag1 = 2.473,
    B2_placebo_p = 0.000, B2_placebo_null_max = 1.104, B2_paired_diff_oos_v2 = 2.326,
    B2_variant_capw_oos_v2 = 0.452, B2_ewuni_port_t = 6.588, B2_ewuni_oos = 0.512,
    B2_wshare_mega = 0.056, B2_wshare_mid = 0.062, B2_wshare_other = 0.882,
    A_purevalEW_ewuni_t = 3.749, A_purevalEW_oos_v2 = 0.659, A_purevalEW_te = 0.1119,
    A_purevalEW_to = 4.96, A_purevalEW_cap1d_36m = 1.902e9, A_purevalEW_corr_ppure = 0.496,
    A_z6blend_ewuni_t = 6.390, A_z6blend_oos_v2 = 0.520, A_z6blend_corr_ppure = 0.192,
    value_quality_spread_pct = 0.175, n_trials_r30 = 4L,
    next_probe = "P1 B2 forge/graduation dossier(HARD 3종+DSR family~8+book-marginal, FQ 신설); P2 tier-cut 민감도+OTHER 정제(IS-only); P3 recency 감쇠 판별+monitoring tripwire"
  ),
  dry_run = FALSE
)
cat("[emit] l_code=", res$l_code %||% res$entry$l_code %||% "?", "\n")
cat("EMIT_DONE\n")
