## _combine_chunks.R — 배치 청크 → pure_factor_scores.parquet (2005~ full-cycle) 결합
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
ch<-list.files("outputs/ramp/_chunks", pattern="^scores_.*\\.parquet$", full.names=TRUE)
cat(sprintf("청크 %d개: %s\n", length(ch), paste(basename(ch),collapse=",")))
L<-lapply(ch, function(f) as.data.table(read_parquet(f)))
S<-rbindlist(L, fill=TRUE, use.names=TRUE)
S[,signal_date:=as.Date(signal_date)]; setkey(S, signal_date, security_id, factor_id)
S<-unique(S, by=c("signal_date","security_id","factor_id"))
cat(sprintf("결합: %d rows | %s ~ %s | 고유월 %d | 팩터 %d\n",
  nrow(S), as.character(min(S$signal_date)), as.character(max(S$signal_date)), uniqueN(S$signal_date), uniqueN(S$factor_id)))
out<-"outputs/ramp/pure_factor_scores.parquet"
.t<-paste0(out,".tmp"); write_parquet(S,.t); if(file.exists(out))file.remove(out); file.rename(.t,out)
cat("[combine] pure_factor_scores.parquet (full-cycle) 갱신\n")
