library(arrow)
library(data.table)
fp <- ".cache/factor_db/factor_db_202506.parquet"
dt <- as.data.table(read_parquet(fp))
cat("Columns (first 20):", paste(names(dt)[1:min(20,ncol(dt))], collapse=", "), "\n")
cat("nrow:", nrow(dt), "\n")
# Look for vol/turnover related columns
vol_cols <- names(dt)[grepl("Vol|vol|L13|L16|turnover|Turnover", names(dt))]
cat("Vol/Turnover cols:", paste(vol_cols, collapse=", "), "\n")
# Check Date column
date_cols <- names(dt)[grepl("Date|date|YM|ym", names(dt))]
cat("Date-like cols:", paste(date_cols, collapse=", "), "\n")
# Show head
print(head(dt[, c(date_cols, vol_cols[1:min(3,length(vol_cols))]), with=FALSE], 3))
