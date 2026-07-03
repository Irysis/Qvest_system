suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1L)
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
cat("panel ic...\n"); flush.console()
p <- as.data.table(read_parquet(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/defense_factor_panel.parquet")))
cat("panel OK", nrow(p), "\n"); flush.console()
cat("benchmark pin...\n"); flush.console()
b <- as.data.table(read_parquet(file.path(ED_ROOT,".cache/benchmark_pin20260703.parquet")))
cat("bm OK", nrow(b), "\n")
