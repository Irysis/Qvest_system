suppressPackageStartupMessages({library(arrow); library(data.table)})
C <- "C:/qm_cache"
m <- as.data.table(read_parquet(file.path(C,"macro_fred.parquet"), mmap=FALSE)); m[,Date:=as.Date(Date)]
cat("macro cols:", names(m), "\n")
v <- m[Series_ID=="VIXCLS"][order(Date)]
cat("anchor 2020-03-12..18 (CBOE closes: 3/12 75.47, 3/13 57.83, 3/16 82.69, 3/17 75.91, 3/18 76.45)\n"); print(v[Date>=as.Date("2020-03-12")&Date<=as.Date("2020-03-18"), .(Date, wday=weekdays(Date), Value)])
cat("anchor 2008-11-20 (80.86):\n"); print(v[Date>=as.Date("2008-11-19")&Date<=as.Date("2008-11-21"), .(Date, Value)])
cat("anchor 2024-08-05 (38.57):\n"); print(v[Date>=as.Date("2024-08-02")&Date<=as.Date("2024-08-06"), .(Date, Value)])
cat("VIX 2026-08-26..09-02:\n"); print(v[Date>=as.Date("2026-08-26")&Date<=as.Date("2026-09-02"), .(Date, wday=weekdays(Date), Value)])
rs <- open_dataset(file.path(C,"RAWDATA.parquet"))
cn <- names(rs$schema); cat("RAWDATA cols:", cn, "\n"); cat("has VIX:", "VIX"%in%cn, " has VKOSPI:", "VKOSPI"%in%cn, "\n")
fd <- as.data.table(read_parquet(file.path(C,"factor_db","factor_db_202608.parquet"), mmap=FALSE))
cat("fdb cols:", names(fd), "\n"); print(fd[, .N, by=Date])
for (f in c("D32_Beta_VIX","MA01_GDP_Sensitivity","MA02_CPI_Sensitivity","MA03_Rate_Sensitivity","MA04_YieldCurve_Sensitivity","MA05_MonetaryPolicy_Mom","MA07_BusinessCycle_Composite","RE10_VIX_Pctile","RE11_VIX_Change_EWMA","RE12_VIX_Regime_3State","RE13_Credit_Spread_Pctile","RE14_Inflation_YoY","RE16_Canary_Signal")) {
  x <- fd[Factor_Name==f]
  cat(sprintf("%-32s n=%5d nonNA_raw=%5d uniq_raw=%5d nonNA_Z=%5d cov=%d\n", f, nrow(x), sum(!is.na(x$Raw_Value)), uniqueN(x$Raw_Value), sum(!is.na(x$Z_Score)), sum(x$Coverage %in% TRUE)))
}
