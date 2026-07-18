# FQ-057 env check: schema + packages (read-only)
suppressPackageStartupMessages({library(data.table); library(arrow)})
data.table::setDTthreads(1)
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/config.R")
cat("RAWDATA_CACHE:", RAWDATA_CACHE, "size_MB:", round(file.size(RAWDATA_CACHE)/1024^2,1), "\n")
cat("BM_CACHE:", BM_CACHE, "size_MB:", round(file.size(BM_CACHE)/1024^2,1), "\n")
sch <- arrow::open_dataset(RAWDATA_CACHE)$schema
cat("RAWDATA cols:", paste(sch$names, collapse=", "), "\n")
for (p in c("PerformanceAnalytics","xts","nlshrink","jsonlite","future.apply")) {
  cat(sprintf("pkg %s: %s\n", p, requireNamespace(p, quietly=TRUE)))
}
# date range via row-group stats (cheap): read only Date col head/tail
dt <- as.data.table(read_parquet(RAWDATA_CACHE, col_select = c("Date")))
cat("Date range:", as.character(min(dt$Date)), "to", as.character(max(dt$Date)), "n_rows:", nrow(dt), "\n")
