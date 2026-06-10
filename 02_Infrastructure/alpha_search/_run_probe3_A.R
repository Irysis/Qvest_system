# Config A: faithful Hou small-follower (시총 중위 이하) MOM=21
Sys.setenv(SP_MOM="21", SP_LEADER_FRAC="0.30", SP_FOLLOWER="small", SP_SECTOR_COL="Sector_Lv2")
source("G:/Quant_Module_Moltbot/02_Infrastructure/alpha_search/run_alpha_search.R")
r <- run_alpha_search(
  strategy_name      = "Sector Spillover (Hou2007) MOM21 follower=small",
  strategy_idea      = "산업 lead-lag spillover (Hou 2007 충실): 산업 leader 대형주 VW 수익을 그 산업 소형 follower(시총 중위 이하)가 따라옴 (KR K200/KQ150 long-only top25; breadth 주의)",
  factor_engine_path = "G:/Quant_Module_Moltbot/02_Infrastructure/alpha_search/fe_sector_spillover.R",
  n_holdings = 25L, weight_method = "equal", commission = 0.0015,
  start_date = "2005-01-01", universe = "K200_KQ150",
  factor_analysis = TRUE, send_telegram = FALSE
)
cat("\n=== PROBE3-A RETURN ===\n"); str(r)
saveRDS(r, "G:/Quant_Module_Moltbot/stage_artifacts/alpha_search/_probe3_A_return.rds")
