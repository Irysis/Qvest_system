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
        "가설: lw_nls가 잔차 분산 구조를 보존해 sample·RMT엔 없는 새 crowding 경보를 내는가",
        "방법: 전종목(p>n) 60m rolling 3방법 Σ → 시장모드(PC1) 제거 → 잔차 집중도 201m 비교",
        "결과①: RMT는 종목수>관측수 구간서 무작동(201/201) → 'RMT가 잔차를 뭉갠다' 전제 거짓",
        "결과②: lw_nls 강점축(공분산)서 잔차 집중이 sample과 동일 — 새 정보 없음",
        "의미: lw_nls는 총분산 안전엔 유효(FQ-057)나 이 crowding 신호엔 기여 없음")),
    list(type="kv", emoji="🔬", heading="핵심 발산 (lw_nls ~ sample 시계열)",
      kv=list(
        "RMT 무작동"        = "201/201 window (p>n) sample과 동일",
        "공분산 PC1 흡수율" = "pearson 1.000 (Absorption Ratio 동일)",
        "공분산 잔차 집중"  = "pearson 0.958 / spearman 0.916 (동일)",
        "상관 잔차 집중"    = "pearson 0.532 (cov2cor confound)",
        "대각 통제 probe"   = "0.532 -> 0.644 (co-movement 보존 아님)")),
    list(type="bullet", emoji="🚩", heading="주의 · 한계",
      items=c(
        "상관 발산(0.53) 실재 — 단 명제어(잔차분산 보존) 충실축=공분산서 동일=기전 반증(JUDGMENT)",
        "상관 발산의 정보성은 미증명(different != uninformative) — lw_nls 특이 기전 아님만 확립",
        "월간 60m 단일 틀 — 일간 63d 재현은 값싼 후속(결론 이식 예상)",
        "올바른 p>n RMT·목적-빌드 잔차-상관 denoiser는 별개 후보 — lw_nls 부활 아님")),
    list(type="bullet", emoji="➡️", heading="판정 · 다음",
      items=c(
        "판정: KILL_lw_nls_incidental — 자본/성과 주장 ZERO(위험-축 진단)",
        "다음①: 잔차-상관 monitor 필요시 목적-빌드 denoiser + AR 대비 incremental 실증",
        "다음②: crowding 신규 차원은 신용/대차(FQ-005)가 co-movement 갭 더 직접 보완",
        "부활: lw_nls는 tail-conditional 잔차 스펙트럼 등 새 측정틀서만 재검토"))
  ),
  charts = charts,
  footer = "FQ-062 · pin fq062_20260719_130727 · n_windows 201 · metric_type spectral_diagnostic · verdict KILL_lw_nls_incidental"
)
cat("FQ062_TELEGRAM_DONE charts=", length(charts), "\n")
