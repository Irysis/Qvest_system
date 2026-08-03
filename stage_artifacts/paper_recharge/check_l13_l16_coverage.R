library(arrow)
library(data.table)
fp <- ".cache/factor_db/factor_db_202506.parquet"
dt <- as.data.table(read_parquet(fp))
# Check L13/L16 coverage
l_factors <- dt[grepl("^L1[3-6]", Factor_Name), .(n=.N, n_unique_ticker=uniqueN(Ticker)), by=Factor_Name]
cat("L13-L16 in 202506:\n")
print(l_factors)
# Also check if any L-factor has actual data
cat("\nAll L-factors:\n")
all_l <- dt[grepl("^L", Factor_Name), .(n=.N), by=Factor_Name]
print(all_l[order(Factor_Name)])
