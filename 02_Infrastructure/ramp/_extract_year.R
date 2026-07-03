## _extract_year.R — FWL 추출 1개 연도 (fresh 짧은 프로세스, 장시간 단일-run 세그폴트 회피)
## env: BATCH_YEAR (YYYY). 승인팩터(approved)만. → outputs/ramp/_chunks/scores_<YYYY>.parquet
## 이미 존재하면 skip (재개 가능). 월별 누적 후 연도 끝에 1회 write.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1)  # [2026-06-18] arrow set_io_thread_count(1) 제거 — parquet read hang 유발(실측). data.table 세그폴트는 setDTthreads(1)로 제어, arrow IO는 기본값 안전.
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
YR<-Sys.getenv("BATCH_YEAR"); stopifnot(nchar(YR)==4)
out<-sprintf("outputs/ramp/_chunks/scores_%s.parquet",YR)
if(file.exists(out)){ cat(sprintf("[year %s] 이미 존재 — skip\n",YR)); quit(save="no",status=0) }
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/pure_factor_extraction.R")
af<-as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
## [2026-06-19 도훈: 팩터군 보강] RAMP_FULL_FACTORS=1 → 전체 316(승인+기각). 기각은 standalone 허들(advisory §3)이라 군 멤버십엔 부적합 — composite는 z-표준화 평균이라 멤버多=강건.
factor_set<-if(Sys.getenv("RAMP_FULL_FACTORS")=="1") sort(unique(af$factor_id)) else sort(af[status=="approved",factor_id])
## [2026-06-18 수리] 필요컬럼만 col_select (full 14M×21col=2.5GB 풀로드 세그폴트 회피) — 슬라이스 1.1GB
.need<-c("Date","Ticker","Sector","Size","Ret","Vol","Close","BM_Ret","K200","KQ150")
rawdata<-as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
me<-function(d){x<-seq(as.Date(format(d,"%Y-%m-01")),by="month",length.out=2)[2];x-1}
all_m<-seq(as.Date(sprintf("%s-01-01",YR)), as.Date(sprintf("%s-12-01",YR)), by="month")
sig_dates<-sort(unique(as.Date(sapply(all_m,function(d)as.character(me(as.Date(d)))))))
sig_dates<-sig_dates[sig_dates<=max(rawdata$Date)]
cat(sprintf("[year %s] %d 월말 × %d 팩터\n", YR, length(sig_dates), length(factor_set)))
## 월별 추출 + 누적 (extract_pure_factor 1-month씩 — 진행 가시화)
## [2026-06-18] gc() per-iter 제거 — 대용량 heap full-gc가 OneDrive 페이징하에서 ~10s/call로
## 240s timeout 유발했음(실측). 12개월 누적은 OOM 없음(_diag_write 9s 실증). 진행로그는 별도 파일 append.
PLOG<-sprintf(".cache/_year%s_progress.txt",YR); cat(sprintf("=== year %s ===\n",YR),file=PLOG)
acc<-list()
for(sd in as.character(sig_dates)){
  t0<-Sys.time()
  pf<-tryCatch(extract_pure_factor(factor_set, as.Date(sd), rawdata, verbose=FALSE),
               error=function(e){cat(sprintf("  [%s] ERR %s\n",sd,conditionMessage(e)),file=PLOG,append=TRUE);NULL})
  if(!is.null(pf) && nrow(pf$scores)>0) acc[[sd]]<-pf$scores
  cat(sprintf("  [%s] %d rows (%.1fs)\n", sd, if(is.null(pf))0 else nrow(pf$scores),
    as.numeric(Sys.time()-t0,units="secs")), file=PLOG, append=TRUE)
}
S<-if(length(acc)) rbindlist(acc,fill=TRUE) else data.table()
dir.create("outputs/ramp/_chunks",recursive=TRUE,showWarnings=FALSE)
.t<-paste0(out,".tmp")
ok<-tryCatch({write_parquet(S,.t); if(file.exists(out))file.remove(out); file.rename(.t,out); TRUE},
             error=function(e){cat(sprintf("[year %s] WRITE-ERR %s\n",YR,conditionMessage(e)));FALSE})
cat(sprintf("[year %s] DONE write_ok=%s — %d rows → %s\n", YR, ok, nrow(S), out))
