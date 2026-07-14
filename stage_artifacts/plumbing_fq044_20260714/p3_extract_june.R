## p3_extract_june.R — #74: pure factor FWL extraction, single month signal 2026-06-30.
## Modeled on 02_Infrastructure/ramp/_extract_chunk.R (fresh process, resumable chunk path).
## Factor set = FULL 316 (current pure_factor_scores.parquet has 316 factors — 2026-06-19
## RAMP_FULL_FACTORS=1 팩터군 보강 빌드와 정합; approved-102가 아님을 실측 확인).
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/pure_factor_extraction.R")
af<-as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
factor_set<-sort(unique(af$factor_id))          # FULL 316
cat(sprintf("[june] factor_set=%d (full)\n", length(factor_set)))
.need<-c("Date","Ticker","Sector","Size","Ret","Vol","Close","BM_Ret","K200","KQ150")
rawdata<-as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
stopifnot(max(rawdata$Date) >= as.Date("2026-06-30"))
sig_dates <- as.Date("2026-06-30")
pf<-extract_pure_factor(factor_set, sig_dates, rawdata, verbose=TRUE)
cat(sprintf("[june] scores rows=%d factors=%d tickers=%d | orth ok=%d fail=%d\n",
  nrow(pf$scores), uniqueN(pf$scores$factor_id), uniqueN(pf$scores$security_id),
  nrow(pf$orth_summary[status=="ok"]), nrow(pf$orth_summary[status!="ok"])))
dir.create("outputs/ramp/_chunks",recursive=TRUE,showWarnings=FALSE)
out<-"outputs/ramp/_chunks/scores_202606.parquet"
.t<-paste0(out,".tmp_",Sys.getpid()); write_parquet(pf$scores,.t); if(file.exists(out))file.remove(out); file.rename(.t,out)
saveRDS(pf$orth_summary, "stage_artifacts/plumbing_fq044_20260714/p3_orth_summary.rds")
cat(sprintf("[june] %d rows -> %s\nP3_EXTRACT_DONE\n", nrow(pf$scores), out))
