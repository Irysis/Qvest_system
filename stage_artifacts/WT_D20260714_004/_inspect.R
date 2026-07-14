## R28 inspection — stored panel Date convention + schemas
suppressPackageStartupMessages({library(arrow); library(data.table)})
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)

bkp <- file.path(QM,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet")
bk <- as.data.table(read_parquet(bkp))
cat("=== stored panel columns ===\n"); print(names(bk))
cat("=== nrow / uniq Date / range ===\n")
bk[,Date:=as.Date(Date)]
cat(sprintf("nrow=%d uniqDate=%d range=%s..%s\n", nrow(bk), uniqueN(bk$Date), as.character(min(bk$Date)), as.character(max(bk$Date))))
cat("=== first 6 unique dates ===\n"); print(head(sort(unique(bk$Date)),6))
cat("=== last 4 unique dates ===\n"); print(tail(sort(unique(bk$Date)),4))
cat("=== sample rows ===\n"); print(head(bk[Date==min(Date)][order(-score_eff)],4))
cat("=== per-Date ticker count summary ===\n"); print(summary(bk[,.N,by=Date]$N))

## factor_ic_monthly
ic <- as.data.table(read_parquet(file.path(QM,".cache/factor_db/factor_ic_monthly.parquet")))
cat("\n=== factor_ic_monthly cols ===\n"); print(names(ic))
cat("=== IC date range ===\n"); ic[,Usable_Date:=as.Date(Usable_Date)]; print(range(ic$Usable_Date, na.rm=TRUE))
cat("=== SLEEVE_CORE factors present in IC ===\n")
print(ic[Factor_Name %in% c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap"), .N, by=Factor_Name])

## sample factor_db schema (mid-history month)
fdb <- as.data.table(read_parquet(file.path(QM,".cache/factor_db/factor_db_201506.parquet")))
cat("\n=== factor_db_201506 cols ===\n"); print(names(fdb))
cat("=== factors present (subset) ===\n")
print(intersect(c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap","Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O"), unique(fdb$Factor_Name)))
cat("INSPECT_DONE\n")
