PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
source(file.path(PROJECT_ROOT, "02_Infrastructure/alpha_search/run_alpha_search.R"))
run_alpha_search(
  strategy_name      = "ARFIMA_TSMOM",
  strategy_idea      = "분산비(VR(3)>1)로 추세 구간을 식별해 12-1 모멘텀 신호를 조건부 적용. VR<=1 종목은 신호 제거.",
  factor_engine_path = file.path(PROJECT_ROOT, "stage_artifacts/paper_recharge/factor_engine_arfima_tsmom.R"),
  n_holdings    = 25L,
  weight_method = "equal",
  commission    = 0.0015,
  start_date    = "2005-01-01",
  universe      = "K200_KQ150",
  factor_analysis = TRUE,
  send_telegram = TRUE,
  tg_dry_run    = FALSE
)
