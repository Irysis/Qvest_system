## _diag_slice.R — 가설: 14M행 full rawdata가 build_fwl_controls 세그폴트 원인.
## 필요 컬럼만 col_select + 2005 윈도우로 슬라이스 후 build_fwl_controls 작동 검증.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/pure_factor_extraction.R")

## 1) 컬럼 스키마 확인
sch<-arrow::open_dataset(".cache/rawdata.parquet")$schema
cat("rawdata 컬럼:", paste(names(sch),collapse=", "), "\n")
need<-c("Date","Ticker","Sector","Size","Ret","Vol","Close","BM_Ret","K200","KQ150")
have<-intersect(need, names(sch)); miss<-setdiff(need,names(sch))
cat("필요컬럼 보유:", paste(have,collapse=","), "| 결측:", if(length(miss))paste(miss,collapse=",")else "(없음)","\n")

## 2) 필요컬럼만 + 2005-01-31 이전 버퍼만 슬라이스 로드
t0<-Sys.time()
rd<-as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(have)))
rd[,Date:=as.Date(Date)]
cat(sprintf("슬라이스 컬럼-only 로드: %d rows, %.1fMB (%.1fs)\n", nrow(rd),
  as.numeric(object.size(rd))/1e6, as.numeric(Sys.time()-t0,units="secs")))
cat(sprintf("2005 K200 TRUE: %d, KQ150 TRUE: %d (2005-01 cross-section 멤버십 존재?)\n",
  rd[Date>="2005-01-01"&Date<="2005-02-01"&K200==TRUE,uniqueN(Ticker)],
  rd[Date>="2005-01-01"&Date<="2005-02-01"&KQ150==TRUE,uniqueN(Ticker)]))
cat(sprintf("BM_Ret 2005 non-NA 비율: %.2f\n", rd[Date>="2005-01-01"&Date<="2005-12-31",mean(!is.na(BM_Ret))]))

## 3) build_fwl_controls 2005-01-31 (슬라이스 rawdata)
for(sd in c("2005-01-31","2005-06-30","2008-10-31")){
  t1<-Sys.time()
  X<-tryCatch(build_fwl_controls(rd, as.Date(sd)), error=function(e)paste0("ERR:",conditionMessage(e)))
  if(is.character(X)){cat(sprintf("[%s] FAIL %s\n",sd,X));next}
  cat(sprintf("[%s] Xrows=%d beta_nonNA=%d (%.1fs)\n", sd, nrow(X),
    if("beta"%in%names(X))sum(!is.na(X$beta))else -1, as.numeric(Sys.time()-t1,units="secs")))
}
cat("DIAG_SLICE_DONE\n")
