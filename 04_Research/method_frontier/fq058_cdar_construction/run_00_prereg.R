# =============================================================================
# FQ-058 method_frontier — structural-drawdown-aware construction
#   run_00: 사전등록(preregistration) — 측정 전 불변 기록 (overwrite 거부)
#
#   가설: 구성(construction)-레벨에서 위험 MEASURE를 분산(variance)에서
#   drawdown-aware(CDaR)/tail(CVaR)로 바꾸면 06-13 게이트가 정의한 structural
#   drawdown(45%+ 에피소드 빈도·drawdown 점유·최장 수중기간·MDD)이 표적 개선되어
#   동일 알파 basket에서 calmar 0.64 통과율이 오르는가.
#
#   ★ 핵심 설계 결정 (self-adversarial 선제 차단): "objective swap"을 순수하게
#   측정하려면 alpha-drop 교란을 제거해야 한다. 따라서 PRIMARY 비교는
#   pure risk-min 계열 내에서 위험 MEASURE만 바꾼 paired:
#       MinCDaR vs MinVar  (drawdown 목적 vs 분산 목적, 둘 다 alpha 미사용·동일 basket)
#   이 arm 쌍은 동일 top-25 basket·동일 daily-120 표본에서 위험 measure만 다르다.
#   MVO(alpha+분산)·EW는 참조(현 파이프라인 / Cycle-2 1/N 벤치)로 병기.
# =============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
PRE_PATH <- file.path(OUT_DIR, "fq058_preregistration.json")

if (file.exists(PRE_PATH)) {
  cat("[prereg] 이미 존재 — 불변성 유지, overwrite 거부:", PRE_PATH, "\n")
  quit(save = "no", status = 0)
}

prereg <- list(
  id = "FQ-058",
  lane = "method_frontier",
  round_type = "independent_research_round_not_WT",
  agent = "optimizer-research",
  registered_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  round_tag = "fq058_20260718_191740",
  pin_consumed = "fq057_20260718_171024",
  pin_note = paste0(
    "rawdata/월간패널/일간수익/유동성 스냅샷 vintage = FQ-057 pin 상속(동일 스냅샷 소비, ",
    "measurement-graduation §7 read_pinned 경유). daily_refresh 활성 중이므로 pinned만 소비. ",
    "round_tag 는 본 라운드 식별자로 산출물 전부에 stamp."),
  metric_type_policy = "canonical_screen (screen_diagnostic) — 모든 수치에 metric_type 라벨. proxy 손계산 금지. 포트수익 구성=Return.portfolio only.",
  capital_claim = FALSE, graduation_claim = FALSE, weight_proposal = FALSE,
  claim_scope = "construction-level MDD 레버의 체계 진단 — 자본/졸업 주장 없음. PORT_t 2.95 관문은 별개(본 라운드 밖).",

  # ---- Step 0 차별 대조 (hypothesis_index lookup 결과) ----------------------
  step0_prior_differentiation = list(
    priors = c(
      "WT-D20260424_011 (STR_1631_MEGA NLS+CVaR cap)",
      "WT-D20260425_001 (Rolling MinCVaR + Regime)",
      "WT-D20260425_007 (Regime-Sigma MinCVaR)",
      "idea-registry CVaR 계열 4건 (미측정)",
      "DIST-AR-001 (defense composite — 별개 family)"),
    what_is_different = paste0(
      "선행 3건은 pre-v8.x 시대(calmar HARD 게이트 도입 이전)·특정 단일전략(STR_1631_MEGA)의 ",
      "optimizer 교체(regime-Sigma·rolling MinCVaR)로, '위험 measure 목적함수를 바꾸면 structural ",
      "drawdown 게이트가 개선되는가'를 게이트-실패 pool 대상 paired A/B로 체계 검증한 라운드가 아니다. ",
      "본 FQ-058는 (a) v8.x structural-drawdown 게이트(06-13 정의) 대상, (b) calmar-FAIL & screen_pass ",
      "재료를 사전등록 규칙으로 선정, (c) MinCDaR vs MinVar 를 위험 measure만 다르게 격리한 paired 비교, ",
      "(d) canonical PORT_t 계약·pin 고정·oos_retention·DSR 게이트로 판정. 선행은 전략-특정 optimizer ",
      "교체였고 본 라운드는 construction-method-frontier 체계 진단이다."),
    relation_to_construction_ceiling = paste0(
      "R10~R13(cap-w ~2.94 천장)·RAMP R1 은 '수익 최적화'의 construction 천장. 본 라운드는 수익이 아니라 ",
      "drawdown 형상 통제(structural DD)가 표적 — 다른 목적함수·다른 판정축(calmar/structural DD)."),
    return_pool_note = paste0(
      "재료 alpha 는 return-derived(모멘텀 등, 감쇠 벽 posterior)이나, 본 라운드의 질문은 alpha 신규성이 ",
      "아니라 '주어진 alpha basket 을 drawdown 목적으로 구성하면 structural DD 가 개선되는가'다.")
  ),

  # ---- 재료 선정 규칙 (사전등록 — 결과 보고 아님) ----------------------------
  material_selection = list(
    candidate_factor_set = list(
      mom_12_1  = "누적수익 months t-11..t-1 (skip t) z-score",
      mom_6_1   = "누적수익 months t-6..t-1 z-score",
      low_vol   = "-(월간수익 t-11..t-0 12m 표준편차) z-score (저변동성 = 高 z)",
      reversal_1m = "-(ret_m at month t) z-score (단기 반전)",
      small_size  = "-(log size at month-end t) z-score (소형주)"),
    candidate_rationale = "전부 pinned 월간패널(수익+size)에서 PIT 계산 가능 — vintage 정합(§7). factor_db 로드 회피(vintage 혼입 방지).",
    canonical_screen = paste0(
      "각 후보 F_i: elig(member∩liquid AvgTV20>=2e8∩60m 완전관측) 중 z 상위 top-25 EW long-only, ",
      "월간 재구성, 2010-01..2026-05, net-active vs cap-w K200|KQ150 fresh 벤치(15bps delta 비용). ",
      "SR/CAGR/MDD/calmar/PORT_t(NW lag3) 실측 (Return.portfolio only)."),
    screen_pass_def = "(net SR>=0.7 AND net CAGR>=0.12) OR (net SR>=0.5 AND PORT_t>=2.0). [measurement-graduation §3 screening-tier proxy]",
    selection_rule = paste0(
      "재료 = { F_i : screen_pass=TRUE AND calmar<0.64 }, MDD 내림차순(structural-DD severity) 정렬 후 상위 ≤3. ",
      "동점·부족 시: 순수 calmar-단독 FAIL 재료가 없으면 screen_pass ∧ calmar<0.64 로 유지하되 ",
      "그 사실을 selection 산출물에 기록. '개선 기대가 큰 것' 사후선택 금지 — 오직 게이트-실패 메타데이터 기준."),
    n_max_materials = 3L
  ),

  # ---- Arm 정의 (5개) --------------------------------------------------------
  arms = list(
    EW = list(role = "REFERENCE (Cycle-2 1/N)", def = "top-25 basket 균등 1/25"),
    MVO = list(role = "REFERENCE (현 파이프라인)",
               def = "alpha(basket z*0.01) + 60m lw_nls monthly Sigma, mvo_weights(lambda=2,psi=0.3,bounds[0,0.20],max25,min15,hhi 우회 support-only)"),
    MinVar = list(role = "PRIMARY BASELINE (분산 measure)",
                  def = "pure min w'Sw over daily-120 sample cov(basket), no alpha, quadprog, 0<=w<=0.20, sum=1"),
    MinCDaR = list(role = "PRIMARY TREATMENT (drawdown measure)",
                   def = "calc_cdar_weights(basket, daily ret, alpha=0.95, n_days=120, max_w=0.20) — cccp LP (Chekhlov 2005), no alpha"),
    MinCVaR = list(role = "SECONDARY TREATMENT (tail measure)",
                   def = "calc_cvar_lp_weights(basket, daily ret, alpha=0.95, n_days=120, max_w=0.20) — cccp LP (Rockafellar-Uryasev 2000), no alpha")
  ),
  arm_confound_control = paste0(
    "PRIMARY 판정축 = MinCDaR vs MinVar: 동일 top-25 basket·동일 daily-120 표본·동일 제약, ",
    "위험 MEASURE(drawdown vs variance)만 상이 → alpha-drop 교란 없음. EW/MVO 는 참조."),
  fixed_params = list(
    top_n = 25L, max_w = 0.20, sum_w = 1.0, long_only = TRUE,
    liq_min_krw = 2e8, window_monthly_m = 60L, window_daily_d = 120L,
    cvar_cdar_alpha = 0.95, cost_bps_oneway = 15,
    cost_model = "v2.4_kr_retail_15bps delta 과금 (|Delta보유명목|*15bps, round-trip 아님 per-leg)",
    reb_from = 201001L, reb_to = 202605L, holding = "t+1",
    alpha_scale_mvo = 0.01, mvo_lambda = 2.0, mvo_psi = 0.3),

  # ---- 판정 게이트 (사전등록 불변) ------------------------------------------
  decision_gates = list(
    primary_hypothesis = paste0(
      "H1: MinCDaR 가 MinVar 대비 structural drawdown 을 표적 개선(MDD 감소 AND ",
      "45%+ 에피소드 수 감소 AND drawdown 점유율 감소 AND 최장 수중일수 감소 중 다수) ",
      "AND calmar 상승, 재료 다수(>=2/3)에서."),
    g1_structural_dd = "MinCDaR structural DD 지표(maxDrawdown/table.Drawdowns/findDrawdowns 표준함수) < MinVar, 재료별 부호 기록",
    g2_paired_nw_t = "paired NW-t(lag3) on monthly net-active diff (MinCDaR - MinVar): |t|>=2 로 유의 (표적은 calmar이나 활성수익 차이도 기록)",
    g3_oos_retention = "oos_retention v2 (anchored 3분할 {55,65,75} 중앙값) — MinCDaR 활성수익 시계열, >=0.7 목표(진단)",
    g4_dsr = "다중 method 비교 = sweep형 → DSR HARD >=0.5 적용 (n_trials_family=arms=5, Bailey-LdP sr0). best treatment arm 대상.",
    g5_calmar_gate = "calmar 0.64 HARD 도달 여부 보고. 단 PORT_t 2.95 등 graduation 관문은 별개(본 라운드 자본 주장 없음).",
    verdict_logic = paste0(
      "POSITIVE: H1 충족 AND DSR>=0.5 AND oos>=0.7 (drawdown 목적이 structural DD 레버로 확립). ",
      "PARTIAL: structural DD 개선하나 calmar 미도달 또는 oos<0.7 (레버 실재·자본 미달). ",
      "NEGATIVE(config-scoped): structural DD 개선 없음/역효과 → 기전 진단 + next_probe>=2. ",
      "제약 완화 제안 금지(INV-7) — max25/[0,0.20]/sum=1/liq/15bps delta 는 고정 축.")
  ),
  robustness_diagnostics = list(
    cvar_cdar_alpha_alt = "alpha 0.90/0.975 로 재측정(선택 아님·verdict 불변성 진단만)",
    turnover_honesty = "회전율 = 캘린더연 one-way 실합산(x12 금지) + round-trip x2 병기. delta 과금 |Delta보유명목|*15bps.",
    lp_fallback_audit = "매 rebalance calc_cdar/cvar 의 LP status=optimal 확인. fallback(min-vol/inverse-ES) 발동 시 그 셀 카운트·격리 보고(fallback 은 CDaR/CVaR 아님)."),
  hard_constraints = "종목<=25 / long-only(w>=0) / weight [0,0.20] / sum(w)=1 / LIQ AvgTV20>=2e8 / PIT C1~C15 / 15bps delta 과금. 완화 금지.",
  role_boundary = "weights(구성)만. alpha 재해석·Sigma 재정의 금지. 재료 alpha 는 selection 신호로만 소비.",
  R_discipline = ".R 파일 경유(-e 한글 금지)·setDTthreads(1)·temp-rename·RAM 80%·future_lapply 병렬(월 독립)·Return.portfolio only."
)

write_json(prereg, PRE_PATH, auto_unbox = TRUE, pretty = TRUE)
cat("[prereg] 사전등록 기록 완료 (불변):", PRE_PATH, "\n")
