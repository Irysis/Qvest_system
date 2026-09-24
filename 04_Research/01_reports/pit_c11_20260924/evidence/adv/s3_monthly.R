suppressPackageStartupMessages({library(arrow); library(data.table)})
C <- "C:/qm_cache"
m <- as.data.table(read_parquet(file.path(C,"macro_fred.parquet"), mmap=FALSE)); m[, Date:=as.Date(Date)]
for (s in c("CPIAUCSL","INDPRO")) { cat(s, "\n"); print(m[Series_ID==s & Date>=as.Date("2026-05-01"), .(Date, Value)]) }
# first appearance in fred_macro backups
bk <- sort(list.files(C, pattern="^fred_macro[.]parquet[.]bak_", full.names=TRUE))
f0 <- as.data.table(read_parquet(bk[1], mmap=FALSE)); cat("fred_macro cols:", paste(names(f0), collapse=","), "\n")
first_seen <- function(sid, d) {
  for (b in c(bk, file.path(C,"fred_macro.parquet"))) {
    x <- as.data.table(read_parquet(b, mmap=FALSE)); idc <- intersect(c("Series_ID","series_id","Series"), names(x))[1]
    x[, Date:=as.Date(Date)]
    if (nrow(x[get(idc)==sid & Date==as.Date(d) & !is.na(Value)])>0) return(basename(b))
  }
  NA }
for (q in list(c("CPIAUCSL","2026-07-01"), c("CPIAUCSL","2026-08-01"), c("INDPRO","2026-07-01"), c("INDPRO","2026-08-01"))) cat(q[1], q[2], "first seen in:", first_seen(q[1], q[2]), "\n")
fd <- as.data.table(read_parquet(file.path(C,"factor_db","factor_db_202608.parquet"), mmap=FALSE))
for (fn in c("RE14_Inflation_YoY","MA07_BusinessCycle_Composite","MA01_GDP_Sensitivity","MA02_CPI_Sensitivity","MA03_Rate_Sensitivity","MA04_YieldCurve_Sensitivity","D32_Beta_VIX")) {
  z <- fd[Factor_Name==fn]; cat(sprintf("%-32s n=%d uniqueRaw=%d nonNA_Z=%d\n", fn, nrow(z), uniqueN(z$Raw_Value), sum(!is.na(z$Z_Score)))) }
cpi <- m[Series_ID=="CPIAUCSL"]; setkey(cpi, Date)
yoy <- function(d) cpi[Date==as.Date(d), Value]/cpi[Date==seq(as.Date(d), by="-12 month", length.out=2)[2], Value]-1
cat(sprintf("RE14 stored 202608 = %.6f ; -(CPI 2026-08 YoY)=%.6f ; -(CPI 2026-07 YoY)=%.6f\n", fd[Factor_Name=="RE14_Inflation_YoY", Raw_Value][1], -yoy("2026-08-01"), -yoy("2026-07-01")))
ip <- m[Series_ID=="INDPRO"]; setkey(ip, Date)
ipy <- function(d) ip[Date==as.Date(d), Value]/ip[Date==seq(as.Date(d), by="-12 month", length.out=2)[2], Value]-1
ma07_aug <- 0.5*ipy("2026-08-01") - 0.5*yoy("2026-08-01"); ma07_jul <- 0.5*ipy("2026-07-01") - 0.5*yoy("2026-07-01")
cat(sprintf("MA07 stored 202608 = %.6f ; with Aug obs=%.6f ; with Jul obs=%.6f\n", fd[Factor_Name=="MA07_BusinessCycle_Composite", Raw_Value][1], ma07_aug, ma07_jul))
# other months RE14
for (ym in c("202003","202208")) { f <- as.data.table(read_parquet(file.path(C,"factor_db",sprintf("factor_db_%s.parquet",ym)), mmap=FALSE))[Factor_Name=="RE14_Inflation_YoY"]
  mo <- as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01")); pm <- seq(mo, by="-1 month", length.out=2)[2]
  cat(sprintf("%s RE14 stored=%.6f  -(YoY same month)=%.6f  -(YoY prev month)=%.6f\n", ym, f$Raw_Value[1], -yoy(mo), -yoy(pm))) }
