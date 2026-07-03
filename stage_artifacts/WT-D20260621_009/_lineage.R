setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ok <- tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = "WT-D20260621_009",
    package_type = "alpha_package",
    method_selected = "BuybackYield_Confirmed (TTM4Q buyback/Size * 1{M03>median}) top-25 EW; SCREEN_ROUTE clean negative",
    input_file_paths = c(".cache/stock_buyback.parquet", ".cache/RAWDATA.parquet",
                         ".cache/benchmark.parquet", ".cache/kr_factor_returns_v2.parquet")
  )
  TRUE
}, error=function(e){ cat("lineage err:", conditionMessage(e), "\n"); FALSE })
cat("lineage_recorded:", ok, "\n")
