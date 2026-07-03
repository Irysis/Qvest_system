## _diag_permonth.R — 2005 각 월 extract_pure_factor 개별 timing (즉시 flush로 hang 월 특정).
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/pure_factor_extraction.R")
PF<-".cache/_permonth_progress.txt"; cat("=== 2005 per-month timing ===\n",file=PF)
logp<-function(...) { cat(sprintf(...),file=PF,append=TRUE); flush.console() }
af<-as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet")); factor_set<-sort(af[status=="approved",factor_id])
need<-c("Date","Ticker","Sector","Size","Ret","Vol","Close","BM_Ret","K200","KQ150")
rd<-as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(need))); rd[,Date:=as.Date(Date)]
logp("rawdata 슬라이스 로드 완료 %d rows\n", nrow(rd))
me<-function(d){x<-seq(as.Date(format(d,"%Y-%m-01")),by="month",length.out=2)[2];x-1}
sig<-sort(unique(as.Date(sapply(seq(as.Date("2005-01-01"),as.Date("2005-12-01"),by="month"),function(d)as.character(me(as.Date(d)))))))
for(sd in as.character(sig)){
  t0<-Sys.time()
  pf<-tryCatch(extract_pure_factor(factor_set, as.Date(sd), rd, verbose=FALSE), error=function(e)paste0("ERR:",conditionMessage(e)))
  el<-as.numeric(Sys.time()-t0,units="secs")
  if(is.character(pf)) logp("[%s] %s (%.1fs)\n", sd, pf, el)
  else logp("[%s] scores=%d (%.1fs)\n", sd, nrow(pf$scores), el)
}
logp("DONE\n")
cat("PERMONTH_DONE\n")
