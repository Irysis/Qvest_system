## _extract_chunk.R — FWL 추출 1개 배치 (fresh 프로세스, 장시간 단일-run 불안정 회피)
## env: BATCH_START, BATCH_END (YYYY-MM-DD). 신호승인 102팩터. → outputs/ramp/_chunks/scores_<start>.parquet
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/pure_factor_extraction.R")
B0<-as.Date(Sys.getenv("BATCH_START")); B1<-as.Date(Sys.getenv("BATCH_END"))
af<-as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
factor_set<-sort(af[status=="approved",factor_id])
## [2026-06-18 수리] 필요컬럼만 col_select — full 14M×21col 로드(2.5GB)가 단일스레드 R 세그폴트 주범.
## 슬라이스(10col,1.1GB)로 build_fwl_controls 0.9s/월 안정. ([[project-r-segfault-stray-process-multithread]])
.need<-c("Date","Ticker","Sector","Size","Ret","Vol","Close","BM_Ret","K200","KQ150")
rawdata<-as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
me<-function(d){x<-seq(as.Date(format(d,"%Y-%m-01")),by="month",length.out=2)[2];x-1}
all_m<-seq(B0,B1,by="month"); sig_dates<-sort(unique(as.Date(sapply(all_m,function(d)as.character(me(as.Date(d)))))))
sig_dates<-sig_dates[sig_dates<=max(rawdata$Date)]
cat(sprintf("[chunk %s~%s] %d 월말 × %d 팩터\n", B0, B1, length(sig_dates), length(factor_set)))
pf<-extract_pure_factor(factor_set, sig_dates, rawdata, verbose=FALSE)
dir.create("outputs/ramp/_chunks",recursive=TRUE,showWarnings=FALSE)
out<-sprintf("outputs/ramp/_chunks/scores_%s.parquet",format(B0,"%Y%m"))
.t<-paste0(out,".tmp"); write_parquet(pf$scores,.t); if(file.exists(out))file.remove(out); file.rename(.t,out)
cat(sprintf("[chunk] %d rows → %s\n", nrow(pf$scores), out))
