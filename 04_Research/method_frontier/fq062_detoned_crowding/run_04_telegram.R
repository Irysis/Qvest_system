## FQ-062 텔레그램 v7 — Risk 진단 보고 (metric_type = spectral_diagnostic)
suppressPackageStartupMessages({library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/telegram/telegram_notify.R")

CH <- "stage_artifacts/method_frontier/fq062/charts"
charts <- c(file.path(CH,"fq062_divergence_bar.png"),
            file.path(CH,"fq062_cov_ar_pc1.png"),
            file.path(CH,"fq062_cov_mfix.png"),
            file.path(CH,"fq062_cor_mfix.png"))
charts <- charts[file.exists(charts)]

tg_agent_brief(
  agent = "Risk",
  title = "FQ-062 SPECTRAL — detoned 잔차-crowding 3-estimator 발산",
  as_of = format(Sys.Date(), "%Y-%m-%d"),
  sections = list(
    list(type="summary", emoji="📌",
      body="detoned 잔차-crowding이 lw_nls 고유 능력인지 반증검증 — sample과 사실상 동일(incidental), KILL. 위험-축 진단, 성과 ZERO."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
      items=c(
        "가설: 정교한 공분산 추정기(lw_nls)가 '잔차 분산 구조'를 보존해, 단순 방법(sample)이나 잡음제거(RMT)로는 안 보이는 새 과밀(crowding) 경보를 만드는가",
        "방법: K200∪KQ150 전종목(p>n) 60개월 rolling에서 3가지 방법으로 공분산 추정 → 시장모드(PC1) 제거 → 잔차 집중도 시계열 201개월(2009~2026) 비교",
        "결과①: 잡음제거(RMT)는 종목수>관측수 구간에서 아무 것도 안 함(201/201 무작동) → 'RMT가 잔차를 뭉갠다'는 전제 자체가 이 조건에서 거짓",
        "결과②: lw_nls의 실제 강점(공분산) 축에서 잔차 집중도 시계열이 sample과 사실상 동일(시장 흡수율 pearson 1.000) → 새 정보 없음",
        "의미: lw_nls는 '총분산 안전'용으로는 유효(FQ-057 확립)하나, 이 crowding 신호에는 특별한 기여 없음")),
    list(type="kv", emoji="🔬", heading="핵심 발산 수치 (lw_nls ~ sample 시계열)",
      kv=list(
        "RMT 무작동"        = "201/201 window (q_ratio 0.19~0.33, p>n) — sample과 완전 동일",
        "공분산 PC1 흡수율" = "pearson 1.000 (고전 Absorption Ratio 완전 동일)",
        "공분산 잔차 집중"  = "pearson 0.958 / spearman 0.916 (near-identical)",
        "상관 잔차 집중"    = "pearson 0.532 — 발산하나 cov2cor 정규화 confound",
        "대각 통제 probe"   = "0.532 -> 0.644 (분산수축 대각 일부 + 부분공간 회전, co-movement 보존 아님)")),
    list(type="bullet", emoji="🚩", heading="주의 · 한계 (정직 병기)",
      items=c(
        "상관 축 발산(0.53)은 실재 — 리터럴 자동규칙만 보면 DIVERGENT 판독 가능. 단 가설 명제어('잔차 분산 보존')의 충실한 축=공분산에서 near-identical이므로 기전 반증으로 봄(JUDGMENT)",
        "상관 발산의 '정보성 없음'은 본 라운드서 미증명(different != uninformative) — lw_nls 특이 기전이 아님만 확립",
        "월간 60m 단일 측정틀 — 일간 63d 재현은 값싼 후속(구조적으로 결론 이식 예상)",
        "올바른 p>n RMT(bulk-clip)·목적-빌드 잔차-상관 denoiser는 별개 후보 — lw_nls 부활 아님")),
    list(type="bullet", emoji="➡️", heading="판정 · 다음",
      items=c(
        "판정: KILL_lw_nls_incidental — 자본/성과 주장 ZERO(위험-축 진단, INV-7 성과 방화벽)",
        "다음①: detoned 잔차-상관 crowding monitor가 필요하면 목적-빌드 denoiser + Absorption Ratio 대비 incremental 실증 (lw_nls 특권 없음)",
        "다음②: crowding 신규 차원은 신용/대차(FQ-005)가 co-movement 갭을 더 직접 보완",
        "부활: lw_nls는 tail-conditional 잔차 스펙트럼 등 새 측정틀서만 재검토"))
  ),
  charts = charts,
  footer = "FQ-062 · pin fq062_20260719_130727 · n_windows 201 · metric_type spectral_diagnostic · verdict KILL_lw_nls_incidental"
)
cat("FQ062_TELEGRAM_DONE charts=", length(charts), "\n")
