suppressPackageStartupMessages({library(arrow)})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache"
for (f in c("rawdata.parquet","RAWDATA.parquet","regime_daily_v2.parquet")) { p <- file.path(root,f); if (file.exists(p)) { s <- open_dataset(p)$schema; cat(f, ":", paste(names(s), collapse=","), "\n") } }
