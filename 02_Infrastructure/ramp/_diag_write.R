## _diag_write.R — write_parquet 행(hang) 격리. 2005 추출 → 누적 → write 단계별 timing.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R"); source("02_Infrastructure/ramp/pure_factor_extraction.R")
PF<-".cache/_write_progress.txt"; cat("=== write 격리 ===\n",file=PF); lp<-function(...){cat(sprintf(...),file=PF,append=TRUE)}
af<-as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet")); fs<-sort(af[status=="approved",factor_id])
need<-c("Date","Ticker","Sector","Size","Ret","Vol","Close","BM_Ret","K200","KQ150")
rd<-as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(need))); rd[,Date:=as.Date(Date)]
me<-function(d){x<-seq(as.Date(format(d,"%Y-%m-01")),by="month",length.out=2)[2];x-1}
sig<-sort(unique(as.Date(sapply(seq(as.Date("2005-01-01"),as.Date("2005-12-01"),by="month"),function(d)as.character(me(as.Date(d)))))))
acc<-list(); t0<-Sys.time()
for(sd in as.character(sig)){pf<-tryCatch(extract_pure_factor(fs,as.Date(sd),rd,verbose=FALSE),error=function(e)NULL); if(!is.null(pf)&&nrow(pf$scores)>0)acc[[sd]]<-pf$scores}
lp("추출+누적 12월: %.1fs, acc=%d개\n", as.numeric(Sys.time()-t0,units="secs"), length(acc))
t1<-Sys.time(); S<-rbindlist(acc,fill=TRUE); lp("rbindlist: %.1fs, %d rows\n", as.numeric(Sys.time()-t1,units="secs"), nrow(S))

## A) write_parquet → OneDrive 경로
t2<-Sys.time(); okA<-tryCatch({write_parquet(S,".cache/_wtest_onedrive.parquet"); TRUE},error=function(e){lp("A-ERR %s\n",conditionMessage(e));FALSE})
lp("A) write_parquet OneDrive(.cache): ok=%s %.1fs\n", okA, as.numeric(Sys.time()-t2,units="secs"))

## B) write_parquet → 로컬 TEMP 경로 (비-OneDrive)
tmp<-file.path(Sys.getenv("TEMP","C:/Users/99922/AppData/Local/Temp"),"_wtest_local.parquet")
t3<-Sys.time(); okB<-tryCatch({write_parquet(S,tmp); TRUE},error=function(e){lp("B-ERR %s\n",conditionMessage(e));FALSE})
lp("B) write_parquet LOCAL-TEMP: ok=%s %.1fs (%s)\n", okB, as.numeric(Sys.time()-t3,units="secs"), tmp)

## C) saveRDS → OneDrive
t4<-Sys.time(); okC<-tryCatch({saveRDS(S,".cache/_wtest.rds"); TRUE},error=function(e){lp("C-ERR %s\n",conditionMessage(e));FALSE})
lp("C) saveRDS OneDrive: ok=%s %.1fs\n", okC, as.numeric(Sys.time()-t4,units="secs"))
lp("WRITE_DIAG_DONE\n"); cat("DONE\n")
