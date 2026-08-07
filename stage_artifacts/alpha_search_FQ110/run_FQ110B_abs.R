## FQ-110B 절대경로 실행 스크립트 (한글 segfault 회피)
PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

source(file.path(PROJECT_ROOT, "02_Infrastructure/alpha_search/run_alpha_search.R"))

run_alpha_search(
  strategy_name      = "FQ110_JumpShare_B",
  strategy_idea      = "12M low jump-share long - frog-in-the-pan reverse, Direction A IC=-0.028",
  factor_engine_path = file.path(PROJECT_ROOT, "stage_artifacts/alpha_search_FQ110/factor_engine_JumpShare_B.R"),
  n_holdings         = 25L,
  weight_method      = "equal",
  commission         = 0.0015,
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE,
  send_telegram      = TRUE
)
