## p5c_append_group.R — #74: June group rows append (p5b 재계산 산출 소비, append-only).
## 게이트(생성기 동정): 2005-2010 블록 bit-exact(max|d|<1e-9) — icw 생성기 확정 증거.
## 2011+ 잔차(med~1e-4, 2026 max 5.85)는 07-11 rawdata 전면 재빌드의 input drift
##   (expanding ic_trail 전파) — 저장 구월 값은 손대지 않음(vintage pin 준수).
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
TD<-"stage_artifacts/plumbing_fq044_20260714"
GS<-"outputs/ramp/factor_group_scores.parquet"
BAK<-"outputs/ramp/factor_group_scores_pre202606ext_backup_20260714.parquet"
GRP<-as.data.table(read_parquet(file.path(TD,"p5_GRP_recomputed.parquet"))); GRP[,signal_date:=as.Date(signal_date)]
G<-as.data.table(read_parquet(GS)); G[,signal_date:=as.Date(signal_date)]
stopifnot(max(G$signal_date)==as.Date("2026-05-31"))
n_old<-nrow(G)
ckG0<-G[,.(n=.N, s=sum(as.numeric(group_z),na.rm=TRUE)), by=signal_date][order(signal_date)]

## 게이트: 2005-2010 bit-exact (생성기 동정)
M<-merge(GRP[signal_date<=as.Date("2010-12-31")],
         G[signal_date<=as.Date("2010-12-31"),.(signal_date,security_id,family,ref=group_z)],
         by=c("signal_date","security_id","family"), all=TRUE)
stopifnot(sum(is.na(M$group_z)|is.na(M$ref))==0)
d0510<-M[,max(abs(group_z-ref))]
cat(sprintf("[gate] 2005-2010 block n=%d max|d|=%.3e\n", nrow(M), d0510))
stopifnot(d0510 < 1e-9)

JG<-GRP[signal_date==as.Date("2026-06-30")]
cat(sprintf("[grp] June rows=%d families=%d tickers=%d\n", nrow(JG), uniqueN(JG$family), uniqueN(JG$security_id)))
stopifnot(nrow(JG)>1000, uniqueN(JG$family)==uniqueN(G$family))
if(!file.exists(BAK)){ .t<-paste0(BAK,".tmp_",Sys.getpid()); file.copy(GS,.t); file.rename(.t,BAK); cat("[grp] backup ->",BAK,"\n") }
## 원 행순서 보존 append (setkey 금지 — 월별 float-sum 체크섬이 덧셈순서 의존, v1 실측 교훈)
ALL<-rbindlist(list(G,JG), use.names=TRUE, fill=TRUE)
.t<-paste0(GS,".tmp_",Sys.getpid()); write_parquet(ALL,.t)
rm(ALL,GRP,M); invisible(gc())
if(!file.remove(GS)) stop("remove fail"); if(!file.rename(.t,GS)) stop("rename fail")

A<-as.data.table(read_parquet(GS)); A[,signal_date:=as.Date(signal_date)]
ckG1<-A[signal_date<=as.Date("2026-05-31"),.(n=.N, s=sum(as.numeric(group_z),na.rm=TRUE)), by=signal_date][order(signal_date)]
same_ord<-isTRUE(all.equal(ckG0, ckG1, tolerance=0)) && nrow(ckG0)==nrow(ckG1)
## order-free bitwise set check (권위 판정): (sig,sec,family) 병합 후 group_z 완전일치
SC<-merge(A[signal_date<=as.Date("2026-05-31")], G[,.(signal_date,security_id,family,ref=group_z)],
          by=c("signal_date","security_id","family"), all=TRUE)
set_ok <- sum(is.na(SC$group_z)|is.na(SC$ref))==0 && SC[,max(abs(group_z-ref))]==0 && nrow(SC)==n_old
cat(sprintf("[verify] pre-June ordered-checksum=%s | set-bitwise-identical=%s | rows %d->%d | months=%d max=%s\n",
  same_ord, set_ok, n_old, nrow(A), uniqueN(A$signal_date), as.character(max(A$signal_date))))
if(!set_ok){ file.remove(GS); file.copy(BAK,GS); stop("group vintage guard fail — restored") }
saveRDS(list(generator="factor_group_consolidation_icw.R (동정 확정: 2005-2010 bit-exact)",
             gate_2005_2010_maxd=d0510,
             drift_note="2011+ 잔차=07-11 rawdata 재빌드 input drift(ic_trail 전파). 구월 저장값 무변경(append-only). June=금일 입력 기준 생성기 산출(PIT).",
             n_june=nrow(JG)), file.path(TD,"p5_group_verify.rds"))
cat("P5C_APPEND_DONE\n")
