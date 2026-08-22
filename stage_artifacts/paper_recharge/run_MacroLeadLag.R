setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(CLAUDE_PROJECT_DIR = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

source("02_Infrastructure/alpha_search/run_alpha_search.R")

run_alpha_search(
  strategy_name      = "MacroLeadLag_PureBeta",
  strategy_idea      = "매크로 지표(신용스프레드, 환율, VIX, 산업생산 등) 변화에 beta가 높은 종목이 지표 변화 후 후행 반응하는 현상. signal=sum(beta_im * delta_macro_m_lag2). Lane D 매크로 조건부 비대칭 알파.",
  factor_engine_path = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/paper_recharge/factor_engine_MacroLeadLag.R",
  n_holdings    = 25L,
  weight_method = "equal",
  commission    = 0.0015,
  start_date    = "2014-01-01",   # FRED 계열 유효 시작 실측: 2014-03-31~ (Lane D precheck 결과 반영)
  universe      = "K200_KQ150",
  factor_analysis = TRUE,
  send_telegram = TRUE,
  tg_dry_run    = FALSE
)
