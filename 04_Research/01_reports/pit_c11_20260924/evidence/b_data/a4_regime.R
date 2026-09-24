suppressPackageStartupMessages({library(data.table); library(arrow)})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache"
r <- as.data.table(read_parquet(file.path(root,"macro_regime.parquet"), mmap=FALSE))
cat("macro_regime cols:", paste(names(r), collapse=","), "\n")
options(width=220)
print(tail(r[, .(YM, Date, VIX, US_CPI, CPI_YoY, US_Unemployment, UMich_Sentiment, US_IndProd, Init_Claims, Chi_Fin_Cond, Macro_Risk_Score)], 5))
m <- as.data.table(read_parquet(file.path(root,"macro_fred.parquet"), mmap=FALSE)); m[,Date:=as.Date(Date)]
cat("\nCheck: macro_regime row Date 2026-08-31 US_CPI equals CPIAUCSL obs 2026-08-01 value:",
    r[Date==as.Date("2026-08-31")]$US_CPI, "vs", m[Series_ID=="CPIAUCSL" & Date==as.Date("2026-08-01")]$Value, "\n")
cat("VIX row 2026-09-30:", r[Date==as.Date("2026-09-30")]$VIX, " vs VIXCLS 2026-09-22:", m[Series_ID=="VIXCLS" & Date==as.Date("2026-09-22")]$Value, "\n")
# ECOS
for (f in c("ecos_krw_usd.parquet","ecos_bond_rates.parquet")) {
  e <- as.data.table(read_parquet(file.path(root,f), mmap=FALSE)); cat("\n==", f, "cols:", paste(names(e), collapse=","), " rows", nrow(e), "\n")
  print(head(e,3)); print(tail(e,4))
}
