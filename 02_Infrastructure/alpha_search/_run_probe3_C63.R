# Config C: MOM=63 (3-month slow diffusion, Hou 2007 horizon) follower=all
Sys.setenv(SP_MOM="63", SP_LEADER_FRAC="0.30", SP_FOLLOWER="all", SP_SECTOR_COL="Sector_Lv2")
source("G:/Quant_Module_Moltbot/02_Infrastructure/alpha_search/run_alpha_search.R")
r <- run_alpha_search(
  strategy_name      = "Sector Spillover (Hou2007) MOM63 follower=all",
  strategy_idea      = "산업 lead-lag spillover 3개월 horizon: 산업 leader 대형주 trailing 63d VW 수익이 follower로 확산 (Hou 2007, KR K200/KQ150 long-only top25)",
  factor_engine_path = "G:/Quant_Module_Moltbot/02_Infrastructure/alpha_search/fe_sector_spillover.R",
  n_holdings = 25L, weight_method = "equal", commission = 0.0015,
  start_date = "2005-01-01", universe = "K200_KQ150",
  factor_analysis = TRUE, send_telegram = FALSE
)
cat("\n=== PROBE3-C63 RETURN ===\n"); str(r)
saveRDS(r, "G:/Quant_Module_Moltbot/stage_artifacts/alpha_search/_probe3_C63_return.rds")
