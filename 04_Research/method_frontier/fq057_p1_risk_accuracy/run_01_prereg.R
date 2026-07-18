# =============================================================================
# FQ-057 NP4-P1 run_01: 사전등록(preregistration) — 측정 전 불변 기록
#   위험-축 소비면 판정: 대형-유니버스(p>n) rolling Σ 에서 lw_nls 가 linear LW(퇴화)
#   대비 위험 예측 정확도(predicted vs realized vol/TE)를 유의 개선하는가 +
#   ⑧행 TE 기준선(EWMA) 대비 실소비 가치가 있는가.
# =============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
PRE_PATH <- file.path(OUT_DIR, "p1_preregistration.json")

if (file.exists(PRE_PATH)) {
  cat("[prereg] 이미 존재 — 불변성 유지, overwrite 거부:", PRE_PATH, "\n")
  quit(save = "no", status = 0)
}

prereg <- list(
  id = "FQ-057-NP4-P1",
  lane = "method_frontier",
  round_type = "independent_research_round_not_WT",
  agent = "risk-research",
  registered_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  pin_tag = "fq057_20260718_171024",
  pin_note = "FQ-057/NP4 동일 vintage 상속 (daily_refresh 활성 — read_pinned 경유만 소비, measurement-graduation §7)",
  metric_type = "risk_forecast_accuracy_diagnostic",
  selection_objective = "estimation_quality (QLIKE 예측손실 — R4 P3 준수, SR/IR/alpha 미사용)",
  capital_claim = FALSE, graduation_claim = FALSE, weight_proposal = FALSE,

  hypothesis = paste0(
    "대형-유니버스(p>n, 약 300종목·60m 창) rolling Σ 에서 lw_nls 가 linear LW(p>n 퇴화 → μI) ",
    "대비 위험 예측 정확도(predicted vs realized 월간 분산/TE-분산)를 유의 개선하며, ",
    "⑧행 TE 기준선(univariate EWMA-direct) 대비 실소비 가치(QLIKE 유의 우월)가 있는가. ",
    "NP4가 실측한 'lw_nls 우위=위험-축(net vol 31.4→30.0%)'을 소비 가능한 형태로 판정."),

  arms = list(
    structural = list(
      lw_linear   = "hrp_core .get_cor_cov('ledoit_wolf') — incumbent (p>n rho-cap 퇴화)",
      lw_nls      = "hrp_core .get_cor_cov('lw_nls') — NP3 등재 analytical NLS (full-rank PSD)",
      ewma_struct = "RiskMetrics 지수가중 다변량 공분산 (λ 고정, 표준 구현 — 자체 신규 합성 아님)"),
    direct = list(
      ewma_direct = "포트 자기 실현분산의 univariate 지수가중 (⑧행 'TE 기준선 EWMA 후보' — 구조 Σ 불요, monitoring 표준 직접법)")
  ),
  ewma_lambda = 0.94,
  ewma_lambda_note = "RiskMetrics canonical 0.94 사전고정. 0.97(월간 관례)은 robustness 진단으로만 보고(선택 아님).",

  targets = list(
    total_variance = "보유 25종 포트 월간 총분산 (25x25 sub-block — p<n, 퇴화 비바인딩 → arm 수렴 예상, 기전 분해)",
    te_variance    = "active(port - cap-w bench) 월간 TE-분산 (active 비중이 전체 elig 유니버스 span → p>n 퇴화 바인딩 = PRIMARY 판정 축)"),
  primary_target = "te_variance",

  portfolios = list(
    capw_tilt_top25 = list(
      role = "PRIMARY (book-form proxy)",
      def = "elig 중 mom_12_1 z 상위 25종, cap-weight(w ∝ size, [0,0.20] cap renorm). 배포 book FORM(STR_1715 cap-w LinearTilt top-25)의 프록시 — 실 production 홀딩/스코어 아님(PIT·anachronism·저장패널 look-ahead caveat로 재구성 회피, challenge_note 공개)"),
    ew_top25 = list(
      role = "CONTROL (breadth)",
      def = "elig 중 mom_12_1 z 상위 25종 EW(1/25). active가 소형/중형에 크게 노출 → 상반 active 프로파일로 robustness")),
  weights_sigma_independent = TRUE,
  weights_sigma_independent_note = "두 포트 비중은 Σ 무관(EW·cap-w) → 전 arm 완전 동일 비중, paired 무결(Σ 는 예측분산에만 개입).",

  universe_rules = list(
    universe = "KOSPI200 ∪ KOSDAQ150 (member at month-end)",
    liquidity = "AvgTV20 >= 2e8 KRW (t-1 PIT, np4_liq_snapshot 재사용)",
    complete_history = "60m rolling 완전관측 (NP4 elig 규칙 재사용)",
    risk_universe = "elig = member ∩ liquid ∩ complete60 — Σ·active·bench·realized 전부 이 집합에서 정의(예측/실현 유니버스 일치)",
    benchmark = "cap-w over elig (Size 비례) — TE 예측/실현 유니버스 정합"),

  alpha_signal = "mom_12_1 (months t-11..t-1 skip t) z-score — 종목선택 신호(성과합성 아님, NP4 동일)",
  window_months = 60L,

  measurement = list(
    predicted = "예측 월간분산 = w' Σ w (Σ = 60m 월간수익 추정, month-end t 기준). total=port 비중, TE=active 비중.",
    realized = "실현 월간분산 = 홀딩월(t+1) 일간 포트수익 제곱합 (Return.portfolio 로 일간 포트/벤치 수익 구성 후 active=port-bench, RV=Σ_d r_d^2). rawdata 일간 직접(fdb_daily 미사용).",
    scale_note = "예측(월간 Σ)·실현(일간 제곱합) 모두 월간분산 스케일. 월내 일간 자기상관 미미 시 동일기대. paired 비교는 공통 realized target 이라 스케일 불변. MZ slope b 로 calibration 진단.",
    ewma_direct = "예측(t+1) = 실현분산{홀딩월 <= t}의 λ-EWMA (warmup >=12 실현월). PIT: 과거 실현만."),

  scored_set = list(
    common = "홀딩월 201101..202606 (structural 60m ∧ ewma_direct 12m warmup 모두 가용 — 전 arm paired 동일집합)",
    structural_robustness = "structural pair(lw_nls vs lw_linear)는 warmup 불요 → 201001..202606 full set 병행 보고"),

  loss_and_tests = list(
    primary_loss = "QLIKE = RV/h - ln(RV/h) - 1 (Patton 2011, 잡음 프록시 robust)",
    secondary_loss = "RMSE(vol) = sqrt(mean((sqrt RV - sqrt h)^2)) (해석용)",
    paired_test = "Diebold-Mariano NW HAC(lag=3) on per-month QLIKE loss 차이. 음수 t = 좌항 손실 낮음(우월).",
    calibration = "MZ 회귀 RV ~ a + b*h (a=0,b=1 이상). arm별 b 보고(공통 스케일 진단)."),

  decision_rules = list(
    a_risk_package_large_universe_sigma = paste0(
      "ADOPT lw_nls over lw_linear (risk_package 대형-유니버스 Σ) iff: TE-분산 타깃에서 PRIMARY 포트(capw_tilt) ",
      "QLIKE(lw_nls) < QLIKE(lw_linear) 이고 DM NW-t(lw_nls − lw_linear) <= -2.0, ",
      "AND EW control 동일방향(mean loss diff < 0). 미충족 시 HOLD/재라우팅(기전 진단)."),
    b_monitoring_te_baseline = paste0(
      "ADOPT lw_nls-예측 TE over EWMA-direct (monitoring TE 기준선) iff: TE-분산 타깃에서 PRIMARY 포트 ",
      "QLIKE(lw_nls) < QLIKE(ewma_direct) 이고 DM NW-t(lw_nls − ewma_direct) <= -2.0. ",
      "미충족(EWMA 동률/우월) 시 KEEP EWMA-direct (더 단순·⑧행 확정 후보 유지).")
  ),
  role_boundary = "Σ + 위험 예측 정확도 진단만. 포트는 진단 instrument(FQ-057 MVP 관례) — allocation 제안 아님. alpha 재해석·weight 결정 금지.",
  hard_constraints = "종목 25 / long-only(포트비중>=0) / weight [0,0.20] / Σw=1 / LIQ 2e8 / PIT C1~C15. 단 본 라운드는 자본 backtest 아닌 위험예측 진단.",
  R_discipline = ".R 파일 경유(-e 한글 금지)·setDTthreads(1)·temp-rename·RAM 80%·Return.portfolio only(포트수익 구성)"
)

write_json(prereg, PRE_PATH, auto_unbox = TRUE, pretty = TRUE)
cat("[prereg] 사전등록 기록 완료 (불변):", PRE_PATH, "\n")
