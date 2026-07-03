## _diag_one_month.R — 단일 월 추출 진단 (debug-first). 2005 월 데이터 가용성 + 단계별 timing.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/pure_factor_extraction.R")

af<-as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
factor_set<-sort(af[status=="approved",factor_id])
cat(sprintf("승인팩터 %d개\n", length(factor_set)))
rawdata<-as.data.table(read_parquet(".cache/rawdata.parquet")); rawdata[,Date:=as.Date(Date)]
cat(sprintf("rawdata: %s ~ %s, %d rows\n", min(rawdata$Date), max(rawdata$Date), nrow(rawdata)))

for(sd in c("2005-01-31","2005-06-30","2008-10-31","2015-06-30")){
  sig_d<-as.Date(sd)
  t0<-Sys.time()
  Xdf<-tryCatch(build_fwl_controls(rawdata, sig_d), error=function(e)paste0("ERR:",conditionMessage(e)))
  t1<-Sys.time()
  if(is.character(Xdf)){cat(sprintf("[%s] build_fwl_controls FAIL: %s\n",sd,Xdf)); next}
  fdb<-tryCatch(load_month_factors(sig_d, factor_names=factor_set), error=function(e)paste0("ERR:",conditionMessage(e)))
  t2<-Sys.time()
  if(is.character(fdb)){cat(sprintf("[%s] Xrows=%d | load_month_factors FAIL: %s\n",sd,nrow(Xdf),fdb)); next}
  nfac<-if(is.null(fdb)||nrow(fdb)==0) 0L else uniqueN(fdb$Factor_Name)
  cat(sprintf("[%s] Xrows=%d (%.1fs) | fdb_rows=%d fac=%d (%.1fs)\n",
    sd, nrow(Xdf), as.numeric(t1-t0,units="secs"), if(is.null(fdb))0 else nrow(fdb), nfac, as.numeric(t2-t1,units="secs")))
}
cat("DIAG_ONE_DONE\n")
