root <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(root)
source(file.path("02_Infrastructure","data","pin_cache.R"))
tag <- "WT-D20260718_004_r1"
paths <- c(".cache/benchmark.parquet",".cache/fred_macro_wide.parquet",
           "06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet",
           "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
existing <- tryCatch(read_pinned(".cache/benchmark.parquet", tag), error=function(e) NULL)
if (is.null(existing)) { pin_cache(paths, tag); cat("PINNED tag=",tag,"\n") } else cat("already pinned\n")
