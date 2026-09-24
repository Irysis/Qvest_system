suppressPackageStartupMessages({library(arrow); library(data.table)})
m <- as.data.table(read_parquet("C:/qm_cache/macro_fred.parquet", mmap=FALSE)); m[, Date:=as.Date(Date)]
for (s in c("CPIAUCSL","INDPRO")) { z <- m[Series_ID==s & Date >= as.Date("2025-06-01"), Date]; all <- seq(as.Date("2025-06-01"), max(z), by="month"); cat(s, "missing months:", format(setdiff(all, z) |> as.Date(origin="1970-01-01")), "\n") }
