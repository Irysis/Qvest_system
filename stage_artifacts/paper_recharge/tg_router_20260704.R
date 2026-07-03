suppressWarnings(suppressMessages({
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  source(file.path(root, "02_Infrastructure/telegram/telegram_notify.R"))
}))

ok <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "리서치 소스 배분 + 팩터 마이닝 (20260704)",
  relaxed = TRUE,
  force = TRUE,
  lock_scope = "paper_router_20260704",
  sections = list(
    list(
      type = "summary",
      body = "arXiv 신규 2건 배분(alpha 1·risk 1)·이월 31·curated 신규 0. testable 팩터 0건(정직 null)."
    ),
    list(
      type = "bullet",
      heading = "결과",
      items = c(
        "alpha-search autorun 0건 실행 (MAX_ALPHA=2) — 자격 후보 없음.",
        "발굴 testable 팩터 없음: 'Liquidity Premium and Investment Horizons'(2607.01377)의 유동성 신호 3종(Kyle-lambda/Amihud, volume-volatility, signed order flow) 전부 373팩터 DB에 이미 존재(Amihud x3, Turnover Volatility, Volume Variance Ratio, On-Balance Volume 등) -> redundant. 진짜 signed-flow 추정은 틱데이터 필요 = KR 불가.",
        "risk 큐: 'A Cap-Axis Integral Diagnostic of Factor Models'(2607.01765) — 팩터모델 pricing-error 진단(잔차-alpha 감사용, 종목 선택 신호 아님).",
        "curated 헤지펀드 소스 15건 전량 기처리, 신규 0."
      )
    )
  )
)
cat("TG_OK=", isTRUE(ok), "\n", sep = "")
