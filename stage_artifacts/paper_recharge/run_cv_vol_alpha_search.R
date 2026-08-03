source("02_Infrastructure/alpha_search/run_alpha_search.R")

run_alpha_search(
  strategy_name      = "CV_Vol_liquidity_uncertainty",
  strategy_idea      = "일별 거래량 변동계수(CV=std/mean) 낮은 종목 선택 — 유동성 불안정성 프리미엄 (2607.01377 파생). EV check NOVEL (cor L13=0.41, L16=0.23). FQ-143.",
  factor_engine_path = "02_Infrastructure/alpha_search/factor_engine_cv_vol.R",
  n_holdings         = 25L
)
