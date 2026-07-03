suppressMessages({library(arrow); library(data.table)})
setDTthreads(1)
sink("stage_artifacts/WT-D20260621_009/_inspect2.txt")
# read only schema + small sample of RAWDATA
sch <- arrow::open_dataset(".cache/RAWDATA.parquet")$schema
cat("=== RAWDATA columns ===\n"); print(names(sch))
# sample one recent date for BM_Ret non-empty check
rd <- read_parquet(".cache/RAWDATA.parquet",
   col_select=c("Date","Ticker","K200","KQ150","Close","Vol","Size","Ret","BM_Ret","AdminStock","TradingHalt","UnfaithfulDisc"))
rd <- as.data.table(rd)
cat("rows:",nrow(rd)," date range:",as.character(range(rd$Date,na.rm=T)),"\n")
cat("BM_Ret nonNA frac:", mean(!is.na(rd$BM_Ret)),"  BM_Ret nonzero frac:", mean(rd$BM_Ret!=0,na.rm=T),"\n")
cat("K200 dist:", sum(rd$K200==1,na.rm=T), " KQ150:", sum(rd$KQ150==1,na.rm=T),"\n")
cat("UnfaithfulDisc present:", "UnfaithfulDisc" %in% names(rd), "\n")
cat("Date class:", class(rd$Date),"\n")
print(head(rd[K200==1 & Date==max(Date)],2))
sink()
cat("DONE\n")
