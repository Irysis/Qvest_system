Sys.setenv(CLAUDE_PROJECT_DIR = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/alpha_search/run_alpha_search.R")
result <- run_alpha_search(
  strategy_name      = "DFA_FM_A5E_Stock25",
  strategy_idea      = "무국면 팩터 모멘텀(A5E)의 종목 전파: broad-21 팩터 중 trailing 12M active>0 인 팩터에 크기비례 가중(3-코호트 중첩 앙상블, 분기 홀딩) -> Score_i = sum_f w_f x Z_f,i -> top-25 EW. 감사 사양 8-7b(뷰->롱온리 종목 틸트 번역) 실측. 지수배분 A5E 실측 pt 2.894/oos 0.706/calmar 0.284 대비 종목 레벨 MDD 구조 차이가 calmar 게이트를 여는지가 1급 질문. 대조군 = DFA 국면판 종목 변환(Grade F 22.8)",
  factor_engine_path = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/alpha_search/fe_dfa_fm_a5e_stock.R",
  n_holdings         = 25L,
  weight_method      = "equal",
  commission         = 0.0015,
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE
)
cat("\n=== [AlphaSearch] 최종 결과 ===\n")
cat("grade:",result$grade," score:",result$score," pass:",result$pass,"\n")
cat("out_dir:",result$out_dir,"\n")
