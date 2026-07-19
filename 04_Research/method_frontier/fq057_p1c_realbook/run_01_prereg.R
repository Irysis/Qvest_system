# =============================================================================
# FQ-057 NP4-P1c run_01: 사전등록(preregistration) — 측정 전 불변 기록
#   목적: P1(FORM proxy, cap-w mom top-25)이 낸 SPLIT 판정
#         (a) risk_package 대형-유니버스 Σ = ADOPT lw_nls
#         (b) monitoring TE 기준선       = KEEP EWMA-direct
#         이 '실 production book(STR_1715_on_M4_R05_noLayer4_PG2)의 active weight'
#         에서도 부호·유의성이 유지되는가를 재확인 (P1 정직 caveat C3 해소).
#   설계: P1과 동일한 predicted-vs-realized QLIKE + paired DM(NW lag3) 하네스를
#         실 book FORM(LinearTilt score_eff top-20 × invested=m4×β_R05)에 적용.
#   판정: P1의 (a)/(b) 방향이 실 book에서 부호·유의성 유지되면 '확증',
#         뒤집히면 'FORM proxy 아티팩트 → P1 소비권고 재판정'. small-n이면 무판정.
# =============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
PRE_PATH <- file.path(OUT_DIR, "p1c_preregistration.json")

if (file.exists(PRE_PATH)) {
  cat("[prereg] 이미 존재 — 불변성 유지, overwrite 거부:", PRE_PATH, "\n")
  quit(save = "no", status = 0)
}

prereg <- list(
  id = "FQ-057-NP4-P1c",
  parent = "FQ-057-NP4-P1",
  lane = "method_frontier",
  round_type = "independent_research_round_not_WT",
  agent = "risk-research",
  registered_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  pin_tag = "fq057_20260718_171024",
  pin_note = paste0("P1 vintage 상속(read_pinned 경유, daily_refresh 활성 — measurement-graduation §7). ",
    "월간/일간/liq/snapshot 입력은 P1 pinned 재사용(재빌드 없음) → Σ·bench·realized 머신러리 P1과 bit-동일. ",
    "유일 변경 = 포트폴리오 active vector(FORM proxy → 실 book FORM)."),
  metric_type = "risk_forecast_accuracy_diagnostic",
  selection_objective = "estimation_quality (QLIKE 예측손실 — R4 P3 준수, SR/IR/alpha 미사용)",
  capital_claim = FALSE, graduation_claim = FALSE, weight_proposal = FALSE,

  hypothesis = paste0(
    "P1의 SPLIT 판정 [(a) risk_package 대형-유니버스 Σ = ADOPT lw_nls / ",
    "(b) monitoring TE 기준선 = KEEP EWMA-direct] 는 book FORM proxy(cap-w mom_12_1 top-25)로 측정됐다. ",
    "실 production book(STR_1715_on_M4_R05_noLayer4_PG2)의 active weight — score_eff top-20 LinearTilt(λ=1.5) × ",
    "invested(m4×β_R05) — 로 재측정해도 (a)/(b)의 부호·유의성이 유지되는가."),

  book_source = list(
    admitted_id = "STR_1715_on_M4_R05_noLayer4_PG2 (book_state.json n_admitted=1, weight 1.0)",
    production_code_path = "05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/01_reproducible_code/forward_weights_R05_noLayer4.R",
    recipe = "w_base = LinearTilt(score_eff top-N=20, λ=1.5, UB=0.20, LIQ 2e8 t-1) [.tilt/.norm production verbatim port]; invested = m4×β_R05; w_stock = w_base×invested, cash = 1-invested",
    score_base = paste0("alpha_scores_str1715_268m_cleanT1.parquet (score_eff, 268m 200401..202604). ",
      "meta label=production_parity_verified: production _recompute_alpha_asof.R 직접실행 대비 spearman 0.975~0.997 (4 sample months). §7b 소비자격 충족."),
    invested_source = "05_Production/.../2-2.../period_returns_layer5_faith.csv (production materialized m4·beta_R05 per return_ym; realized_ym=return_ym+1). NP4 book 정합.",
    section7b_compliance = "production 코드 파생 신호만 소비 — 저장 파생 패널 직접 재사용 아님(cleanT1은 production_parity_verified 라벨 후 소비). 05_Production 무수정(read-only)."),

  arms = list(
    structural = list(
      lw_linear   = "hrp_core .get_cor_cov('ledoit_wolf') — incumbent (p>n rho-cap 퇴화)",
      lw_nls      = "hrp_core .get_cor_cov('lw_nls') — NP3 등재 analytical NLS (full-rank PSD)",
      ewma_struct = "RiskMetrics 지수가중 다변량 공분산 (λ=0.94 고정, 표준 구현)"),
    direct = list(
      ewma_direct = "포트 자기 실현분산의 univariate 지수가중 (⑧행 TE 기준선 EWMA 후보)")),
  ewma_lambda = 0.94,

  portfolios = list(
    capw_mom_proxy = list(
      role = "P1 REPLICA (in-run 대조)",
      def = "P1 PRIMARY 정확 복제 — elig 중 mom_12_1 z 상위 25종 cap-w [0,0.20]. 동일 window/머신러리에서 P1 방향 재현 확인 = proxy↔realbook 격차 격리."),
    real_book_fullinv = list(
      role = "REAL BOOK FORM (structure isolation)",
      def = "elig 중 score_eff 상위 20종 LinearTilt(λ=1.5, UB0.20) 완전투자(invested=1). 실 book의 선택신호(4F consensus)+가중(LinearTilt) 정확 반영 — P1 proxy와의 유일 구조차 격리."),
    real_book_overlaid = list(
      role = "REAL BOOK DEPLOYED (invested overlay 포함)",
      def = "real_book_fullinv × 월별 invested(m4×β_R05); cash=1-invested (CASH col r=0). 실 배포 book의 진짜 active vector(위기 de-risking 포함, 2026-07 실측 equity 24.78%).")),
  weights_sigma_independent = TRUE,
  weights_sigma_independent_note = "세 포트 비중 모두 Σ 무관(mom/score_eff/invested 결정) → 전 arm 완전 동일 비중, paired 무결.",

  universe_rules = list(
    universe = "KOSPI200 ∪ KOSDAQ150 (member at month-end) — P1 elig 규칙 정확 재사용",
    liquidity = "AvgTV20 >= 2e8 KRW (t-1 PIT, P1 np4_liq_snapshot)",
    complete_history = "60m rolling 완전관측 (P1 elig)",
    risk_universe = "elig = member ∩ liquid ∩ complete60 — Σ·active·bench·realized 전부 이 집합. ★실 book 선택도 elig로 제한(Σ 이차형식 coverage 필수) → production 대비 complete60 필터 추가(overlap 진단 보고).",
    benchmark = "cap-w over elig (Size 비례) — P1 정합, TE 예측/실현 유니버스 일치. ★실 book benchmark(KOSPI200)와 다름(limitation) — paired DM는 arm 상대비교라 벤치 불변."),

  window_months = 60L,
  rebalance_range = "200912..202605 (P1 full range, 실 book FORM은 score 패널 200401~로 walk-forward 가능 = P1 대비 power 동일). 추가: 최근-60m 하위창(202007..202605) 별도 보고 = next_probe P1c '최근 60m' + small-n honest.",

  measurement = list(
    predicted = "예측 월간분산 = w' Σ w (Σ=60m 월간수익, month-end t). total=port 비중, TE=active 비중.",
    realized = "실현 월간분산 = 홀딩월(t+1) 일간 포트/벤치 수익(Return.portfolio) → RV=Σ_d r_d^2. rawdata 일간 직접(fdb_daily 미사용). overlaid는 CASH col(r=0) 포함해 Return.portfolio.",
    ewma_direct = "예측(t+1) = 실현분산{홀딩월 <= t}의 λ-EWMA (warmup >=12). PIT: 과거 실현만."),

  loss_and_tests = list(
    primary_loss = "QLIKE = RV/h - ln(RV/h) - 1 (Patton 2011)",
    secondary_loss = "RMSE(vol_ann) + MZ b (calibration)",
    paired_test = "Diebold-Mariano NW HAC(lag=3) on per-month QLIKE 차이. 음수 t = 좌항 우월."),

  decision_rules = list(
    split_verdict_holds_a = paste0(
      "(a) ADOPT lw_nls 유지 iff: real_book(fullinv 또는 overlaid) TE-분산에서 ",
      "DM(lw_nls − lw_linear) t <= -2.0 ∧ mean_qlike_diff<0 (P1과 동일 부호·유의). ",
      "미충족(부호역전 또는 유의성 소실) → FORM proxy 아티팩트 의심 → P1 (a) 재판정."),
    split_verdict_holds_b = paste0(
      "(b) KEEP EWMA-direct 유지 iff: real_book TE-분산에서 DM(lw_nls − ewma_direct) 가 ",
      "t <= -2 를 달성하지 '못함'(tie 또는 EWMA 우월) = P1과 동일(lw_nls가 EWMA를 유의 초과 못함). ",
      "만약 real_book에서 lw_nls가 EWMA-direct를 t<=-2로 유의 초과 → P1 (b) KEEP 재판정(ADOPT 검토)."),
    small_n = "단일 book·recent-60m 하위창은 검정력 제한 — DM |t|<2 는 무판정(방향만). full-range(~180m)가 주 검정."),
  role_boundary = "Σ + 위험 예측 정확도 진단만. 포트는 진단 instrument. alpha 재해석·weight 결정 금지.",
  hard_constraints = "종목 20(실 book N_TARGET) / long-only / weight [0,0.20] / LIQ 2e8 / PIT C1~C15. 위험예측 진단(자본 backtest 아님).",
  R_discipline = ".R 파일 경유·setDTthreads(1)·temp-rename·RAM 80%·Return.portfolio only·05_Production read-only"
)

write_json(prereg, PRE_PATH, auto_unbox = TRUE, pretty = TRUE)
cat("[prereg] 사전등록 기록 완료 (불변):", PRE_PATH, "\n")
