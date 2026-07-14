## p4_append_june.R — #74: append June chunk to pure_factor_scores.parquet (append-only,
## vintage pin guard: 기존 1970~2026-05 rows must be bit-identical after write; else restore).
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
TD<-"stage_artifacts/plumbing_fq044_20260714"
EX<-"outputs/ramp/pure_factor_scores.parquet"
CH<-"outputs/ramp/_chunks/scores_202606.parquet"
BAK<-"outputs/ramp/pure_factor_scores_pre202606ext_backup_20260714.parquet"
COLS<-c("signal_date","data_available_date","rebalance_date","security_id","factor_id",
        "raw","winsorized","z","neutralized_z","rank","source_strategy_id")

E<-as.data.table(read_parquet(EX)); E[,signal_date:=as.Date(signal_date)]
n_old<-nrow(E); mx_old<-max(E$signal_date)
cat(sprintf("[append] existing rows=%d months=%d max=%s\n", n_old, uniqueN(E$signal_date), as.character(mx_old)))
stopifnot(mx_old == as.Date("2026-05-31"))

## vintage checksums BEFORE (per month: n, sum z, sum neutralized_z)
ck0<-E[,.(n=.N, sz=sum(as.numeric(z),na.rm=TRUE), snz=sum(as.numeric(neutralized_z),na.rm=TRUE)), by=signal_date][order(signal_date)]

## backup (원본 보존 — 복구 경로)
if(!file.exists(BAK)){ .t<-paste0(BAK,".tmp_",Sys.getpid()); file.copy(EX,.t); file.rename(.t,BAK); cat("[append] backup ->",BAK,"\n") }

N<-as.data.table(read_parquet(CH)); N[,signal_date:=as.Date(signal_date)]
N<-N[signal_date==as.Date("2026-06-30")]
for(m in setdiff(COLS,names(N))) N[[m]]<-NA
N<-N[,..COLS]
## schema align to existing (date cols as Date)
for(dc in c("data_available_date","rebalance_date")) if(dc %in% names(N)) N[,(dc):=as.Date(get(dc))]
## dedup: existing wins
key3<-c("signal_date","security_id","factor_id")
N<-N[!E[,..key3], on=key3]
cat(sprintf("[append] new June rows=%d factors=%d tickers=%d\n", nrow(N), uniqueN(N$factor_id), uniqueN(N$security_id)))
stopifnot(nrow(N) > 10000)

S<-rbindlist(list(E,N), use.names=TRUE, fill=TRUE)
setkey(S, signal_date, security_id, factor_id)
.t<-paste0(EX,".tmp_",Sys.getpid()); write_parquet(S,.t)
rm(E,S); invisible(gc())
if(!file.remove(EX)) stop("remove fail"); if(!file.rename(.t,EX)) stop("rename fail")

## verify AFTER: pre-June months bit-identical (checksums), June present
A<-as.data.table(read_parquet(EX)); A[,signal_date:=as.Date(signal_date)]
ck1<-A[signal_date<=as.Date("2026-05-31"),.(n=.N, sz=sum(as.numeric(z),na.rm=TRUE), snz=sum(as.numeric(neutralized_z),na.rm=TRUE)), by=signal_date][order(signal_date)]
same<-isTRUE(all.equal(ck0, ck1, tolerance=0)) && nrow(ck0)==nrow(ck1)
nj<-A[signal_date==as.Date("2026-06-30"),.N]
cat(sprintf("[verify] pre-June checksums identical=%s | rows %d -> %d (+%d) | June rows=%d | months=%d max=%s\n",
  same, n_old, nrow(A), nrow(A)-n_old, nj, uniqueN(A$signal_date), as.character(max(A$signal_date))))
if(!same){ cat("[FAIL-CLOSED] checksum mismatch — restoring backup\n")
  file.remove(EX); file.copy(BAK, EX); stop("vintage guard fail — restored") }
stopifnot(nj>10000, max(A$signal_date)==as.Date("2026-06-30"))
saveRDS(list(ck0=ck0, n_old=n_old, n_new=nrow(A), n_june=nj), file.path(TD,"p4_append_verify.rds"))
cat("P4_APPEND_DONE\n")
