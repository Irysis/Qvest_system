source("02_Infrastructure/config.R")
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))

sections <- list(
  list(
    type    = "kv",
    emoji   = "\U0001F4C4",
    heading = "소스 배분 (ArXiv 30편)",
    kv      = list(
      "alpha route"     = "2편",
      "optimizer route" = "4편",
      "risk route"      = "3편",
      "regime route"    = "2편",
      "skip"            = "19편",
      "curated 신규"    = "0편 (전체 처리완료)",
      "testable 팩터"   = "1건 (SpectralPersistence_Hurst)"
    )
  ),
  list(
    type    = "bullet",
    emoji   = "\U0001F916",
    heading = "AUTORUN #1 — SpectralPersistence_Hurst (Grade C)",
    items   = c(
      "신호: rolling-252일 R/S Hurst지수, H>0.5=추세 long (Sepp&Lucic 2607.19497)",
      "PORT_t=0.978 / OOS=0.369 — HARD FAIL (기준 2.95 / 0.70)",
      "위기 알파: Rate_2022 +17.4%pp, EuDebt_2011 +39.7%pp",
      "next: FQ-158 금리국면 조건부, FQ-159 cap-tier 분해"
    )
  ),
  list(
    type    = "bullet",
    emoji   = "\U0001F4E5",
    heading = "Optimizer 큐 4건",
    items   = c(
      "Knowledge-Optimising Sharpe — 지식단위 통합 Sharpe 대안 (alpha-fixed A/B)",
      "Same-Grid Duality — 제약 동적포트 solver primal-dual 검증 방법론",
      "Path Signature Portfolio — IS CE 60배 개선, shrinkage 필수 (고차원)",
      "Conformal Kelly — WARNING: 2022+ holdout OOS FAIL. 방법론 참고만"
    )
  ),
  list(
    type    = "bullet",
    emoji   = "\U0001F4CA",
    heading = "Risk/Regime 큐 5건",
    items   = c(
      "[Risk] MFCCA Multifractality — signed fluctuation으로 VaR/ES 감소, Sigma 추정기 후보",
      "[Risk] Proper-score 필터 — 변동성 밀도 추정 개선 (국제 주식 적용)",
      "[Risk] AI Crowding 모델 — 기관 수렴시 joint drawdown 39%->79%, crowding 측정 강화",
      "[Regime] Stationary Ambiguity — 잠재 레짐 강건 오버레이 정책 설계 프레임워크",
      "[Regime] TF Systems Science — Hurst/스펙트럼 분해로 추세추종 수익 귀속 (SR 공식 실용화)"
    )
  )
)

result <- tryCatch(
  tg_agent_brief(
    agent      = "AlphaSearch",
    title      = "리서치 소스 배분 + 팩터 마이닝 (2026-08-08)",
    sections   = sections,
    relaxed    = TRUE,
    force      = TRUE,
    lock_scope = "paper_router_20260808"
  ),
  error = function(e) {
    cat("[TG] 발송 실패:", conditionMessage(e), "\n")
    list(ok = FALSE, error = conditionMessage(e))
  }
)

if (isTRUE(result$ok)) {
  cat("telegram ok\n")
} else {
  cat("telegram FAIL:", result$error %||% "unknown", "\n")
}
