## _combine_fullcycle.R — 전주기(2005~) pure_factor_scores 결합.
## 신규 _chunks(2005-2014, 승인102) + 기존 2015~(316→승인102 subset) → 전주기 102팩터 파일.
## 기존 316-팩터 파일은 백업 보존. 단일스레드·tmp-rename(arrow mmap 안전).
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
af<-as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
sig<-sort(af[status=="approved",factor_id]); cat(sprintf("승인 팩터 %d개\n",length(sig)))
COLS<-c("signal_date","data_available_date","rebalance_date","security_id","factor_id",
        "raw","winsorized","z","neutralized_z","rank","source_strategy_id")

## 1) 기존 2015~ (316팩터) → 백업 + 승인102 subset
ex<-"outputs/ramp/pure_factor_scores.parquet"
bak<-"outputs/ramp/pure_factor_scores_2015plus_316.parquet"
E<-as.data.table(read_parquet(ex)); E[,signal_date:=as.Date(signal_date)]
if(!file.exists(bak)){ write_parquet(E,paste0(bak,".tmp")); file.rename(paste0(bak,".tmp"),bak); cat(sprintf("[백업] 기존 316팩터 → %s\n",bak)) }
Es<-E[factor_id %in% sig]
miss<-setdiff(COLS,names(Es)); for(m in miss) Es[[m]]<-NA
Es<-Es[,..COLS]
cat(sprintf("기존 2015~ (승인subset): %d rows | %s~%s | 팩터%d\n",nrow(Es),min(Es$signal_date),max(Es$signal_date),uniqueN(Es$factor_id)))

## 2) 신규 _chunks (2005-2014)
ch<-list.files("outputs/ramp/_chunks",pattern="^scores_.*\\.parquet$",full.names=TRUE)
cat(sprintf("청크 %d개: %s\n",length(ch),paste(basename(ch),collapse=",")))
NL<-lapply(ch,function(f){d<-as.data.table(read_parquet(f)); if(nrow(d)==0)return(NULL); d[,signal_date:=as.Date(signal_date)]
  mm<-setdiff(COLS,names(d)); for(m in mm)d[[m]]<-NA; d[,..COLS]})
N<-rbindlist(Filter(Negate(is.null),NL),fill=TRUE)
if(nrow(N)>0) cat(sprintf("신규 2005-2014: %d rows | %s~%s | 팩터%d\n",nrow(N),min(N$signal_date),max(N$signal_date),uniqueN(N$factor_id)))

## 3) 결합 (2005-2014 신규 + 2015~ 기존, 비중복) → dedup
S<-rbindlist(list(N,Es),fill=TRUE,use.names=TRUE)
setkey(S,signal_date,security_id,factor_id); S<-unique(S,by=c("signal_date","security_id","factor_id"))
cat(sprintf("\n[전주기 결합] %d rows | %s ~ %s | 고유월 %d | 팩터 %d\n",
  nrow(S),as.character(min(S$signal_date)),as.character(max(S$signal_date)),uniqueN(S$signal_date),uniqueN(S$factor_id)))
S[,yr:=format(signal_date,"%Y")]; print(S[,.(months=uniqueN(signal_date)),by=yr][order(yr)])
S[,yr:=NULL]
.t<-paste0(ex,".tmp"); write_parquet(S,.t); file.remove(ex); file.rename(.t,ex)
cat("[combine_fullcycle] pure_factor_scores.parquet (2005~ 전주기, 승인102) 갱신\n")
