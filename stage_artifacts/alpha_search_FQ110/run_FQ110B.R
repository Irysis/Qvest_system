## FQ-110B 실행 스크립트
## Direction B: 저 jump-share long — frog-in-the-pan 역방향 확증
## 근거: Direction A IC=-0.028(음수) → 역방향 FQ-110B
source("02_Infrastructure/alpha_search/run_alpha_search.R")

run_alpha_search(
  strategy_name      = "FQ110_JumpShare_B",
  strategy_idea      = "12개월 창 저 jump-share long — 분산된 소폭 수익 누적 종목 지속 상승 가설(frog-in-the-pan 역방향, Direction A IC=-0.028 역효과 실측)",
  factor_engine_path = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/alpha_search_FQ110/factor_engine_JumpShare_B.R",
  n_holdings         = 25,
  weight_method      = "equal",
  commission         = 0.0015,
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE,
  send_telegram      = TRUE
)
