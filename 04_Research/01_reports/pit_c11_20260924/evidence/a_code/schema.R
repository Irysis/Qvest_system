suppressMessages({library(arrow)})
source_cfg <- tryCatch({source("02_Infrastructure/config.R"); TRUE}, error=function(e) FALSE)
p <- if (exists("RAWDATA_CACHE")) RAWDATA_CACHE else ".cache/RAWDATA.parquet"
cat("RAWDATA:", p, "\n")
print(open_dataset(p)$schema)
for (f in c(".cache/regime_daily_v2.parquet", ".cache/benchmark.parquet")) if (file.exists(f)) {cat(f,"\n"); print(open_dataset(f)$schema)}
