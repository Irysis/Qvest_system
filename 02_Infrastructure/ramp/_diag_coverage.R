## _diag_coverage.R — BM_Ret 연도별 커버리지 + 2005/2010 월 full extract_pure_factor 검증.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/pure_factor_extraction.R")
need<-c("Date","Ticker","Sector","Size","Ret","Vol","Close","BM_Ret","K200","KQ150")
rd<-as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(need))); rd[,Date:=as.Date(Date)]
rd[,yr:=format(Date,"%Y")]
cat("=== BM_Ret 연도별 non-NA 비율 + K200/KQ150 멤버 ===\n")
cov<-rd[,.(bm_nonNA=round(mean(!is.na(BM_Ret)),3), k200=uniqueN(Ticker[K200==TRUE]), kq150=uniqueN(Ticker[KQ150==TRUE])),by=yr][order(yr)]
print(cov)
af<-as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet")); factor_set<-sort(af[status=="approved",factor_id])
cat("\n=== full extract_pure_factor (승인102, 슬라이스 rawdata) ===\n")
for(sd in c("2005-06-30","2008-10-31","2010-06-30","2015-06-30")){
  t0<-Sys.time()
  pf<-tryCatch(extract_pure_factor(factor_set, as.Date(sd), rd, verbose=FALSE), error=function(e)paste0("ERR:",conditionMessage(e)))
  if(is.character(pf)){cat(sprintf("[%s] FAIL %s\n",sd,pf));next}
  ns<-nrow(pf$scores); nf<-if(ns>0)uniqueN(pf$scores$factor_id)else 0
  okorth<-if(nrow(pf$orth_summary)>0)pf$orth_summary[status=="ok",.N]else 0
  cat(sprintf("[%s] scores=%d 팩터=%d orth_ok=%d (%.1fs)\n", sd, ns, nf, okorth, as.numeric(Sys.time()-t0,units="secs")))
}
cat("DIAG_COV_DONE\n")
