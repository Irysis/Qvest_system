setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/axiom/lcode_emit.R")
lesson <- paste0(
"[canonical_screen 실측] R26 FQ-039 PG2 score_eff 8번째 팩터 add/remove/replace 스크린(도훈 지시 2026-07-14, book_enhancement) = CONFIG_SCOPED_NEGATIVE(book-marginal 자본) + frontier 2. ",
"base=frozen score_eff top-25 cap-w(selection-level, M4×R05 오버레이 상쇄) canonical PORT_t 5.324·net-active IR 1.275(window-matched w=0, 255m). ",
"★추가(ADD, frozen authoritative) 14 arms(7후보×w{.15,.30}): 어떤 것도 paired NW-t≥2.0 미달(best V14_EBIT_EV w0.30=1.87 ΔIR+0.102 holdout1.76; V07_EV_EBITDA w0.15=1.81 ΔIR+0.120 holdout0.39감쇠). 합격=paired≥2.0∧ΔIR≥0.05 동시 → 불충족. ",
"Stage1: deployzone 102(r6_factor_deployzone_active)−book7, |cor_active book|<0.5 전량통과(max0.48), tier_survival(cap-rank≤30 rank-IC)+IS PORT_t 순위→shortlist5={IN03_RD_to_Market,M27_Analyst_Rev_Mom,V07_EV_EBITDA,V02_EP,V14_EBIT_EV}. R16 micro(VPRC_CORR/VSHK_P/TOD_DT) tier_survival FAIL→shortlist밖(task-flagged 별도측정: VPRC add 0.20무의미·VSHK_P sign-flip add -2.02해로움). ",
"★교체(Extension B, 도훈 확장지시 2026-07-14)=recon-proxy(frozen score_eff를 7 constituent에서 재구성, fid_eff median 0.914 q05 0.731 @same-month-end factor_db — 절대 자본판정 아님). LOO7: C06_TP_Gap 제거=최대개선(recon IS paired 2.45 ΔIR+0.22 PORT_t 5.94→7.10) / C02_EPS_Chg_1m 필수(제거 paired -7.09 book붕괴) / Q07 제거 -2.31. removal-only 대조=C06 2.45. replace C06×shortlist: M27만 소폭상회(IS 2.63, 삽입기여 +0.18 over 단순제거) 나머지 음. ",
"★holdout(2024-07..2026-04, 21m) 결정적: C06 제거 IS 2.45→OOS -0.60(붕괴)=IS-특이/과적합 + recon 아티팩트 가능(C06=analyst TP vintage-noisy). replace C06→M27 IS2.63→HO1.64(<2.0). value(V14) IS1.51/HO1.76 유일 일관 양이나 <2.0. ",
"DSR sweep n_trials=26(add14+LOO7+replace5). binding=paired NW-t(book-marginal)이지 DSR-absolute(1.0, base SR 1.28 높아 전부통과) 아님. ",
"프론티어2: (1)value 축=book 최유망 미결 노출(alpha=Core 4F-Consensus+Defense Q07/M08/Q25, 순수 value 부재; value cor-0.05직교·ΔIR+·holdout+ but sub-significant) → P2 value를 z-blend아닌 제3 sleeve로 통합 재시험. (2)C06_TP_Gap 최약슬롯 recon flag → P1 frozen-book 재구축(_recompute SLEEVE_CORE−C06 268m)만 settle(recon≠frozen+holdout붕괴, EV보수). ",
"방법론: cap-w authoritative+EW/cap-tier dual-basis · ΔIR window-matched(stored 1.416 미사용=07-13 deltair_diag 트랩 방어) · paired∧ΔIR AND-게이트(ΔIR 단독 허위통과 차단) · IS-only 선택+holdout1회(C06 과적합 자체검거) · pin R26_FQ039_20260714. ",
"메타: 06-24 직교327 t>2=0·07-10 프로브fleet0·WT-H001 내부튜닝포화 prior 재확인 — composite z-blend 소비형태도 book-marginal 자본기여 부재. 단 value 미결 노출 + C06 pruning frozen검증 = 신규 frontier(negative≠dead)."
)
res <- emit_lcode(
  mode = "alpha_research",
  strategy_id = "R26_FQ039_PG2_8TH_FACTOR",
  grade = "F",
  lesson_text = lesson,
  metric_type = "canonical_screen",
  construction_type = "book_marginal_composite_zblend_and_loo_replace",
  selection_type = "sweep",
  mechanism_hypothesis = "score_eff composite에 8번째 팩터 z-blend(추가) 또는 최약슬롯 교체가 book-marginal ΔIR≥0.05를 만드는가 — add 14arms 어떤것도 paired≥2.0 미달(best 1.87), Ext-B(recon) C06 제거 IS양성이나 holdout붕괴. value=최유망 미결노출·C06=최약슬롯(frozen검증 필요).",
  portfolio_alpha_t = 1.87,
  oos_months = 255L,
  core_reference = "FQ-039 도훈 2026-07-14 'PG2에 어떤 팩터 추가' + 확장 '교체도'; prereg_sha256 f34e8ff9; base STR_1715_on_M4_R05_noLayer4_PG2; deltair_diag window-matched(07-13); r6_factor_deployzone_active; 06-24 직교327 + L-AR-20260710_150153 프로브fleet prior",
  tags = c("book_enhancement","book_marginal","composite_zblend","loo_replace","screen_tier",
           "config_scoped_negative","frontier_open","value_missing_axis","c06_tpgap_pruning_candidate",
           "recon_proxy","window_matched_deltair","fq_039","captier_localization"),
  metrics = list(
    base_capw_port_t = 5.324, base_ir_windowmatched = 1.275,
    best_add_paired_t = 1.87, best_add_factor = "V14_EBIT_EV_w0.30", best_add_dIR = 0.102,
    extB_weakest_slot = "C06_TP_Gap", extB_removal_paired_is = 2.45, extB_removal_holdout = -0.60,
    extB_replace_C06_M27_paired_is = 2.63, extB_recon_fid_eff = 0.914,
    dsr_n_trials = 26,
    next_probe = "P1 frozen-book C06 pruning 재구축(_recompute SLEEVE_CORE-C06); P2 value 제3-sleeve 통합"
  ),
  dry_run = FALSE
)
cat("[emit] l_code=", res$l_code %||% res$entry$l_code %||% "?", "\n")
