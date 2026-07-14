## p5_group_june.R (v2) — #74: factor_group_scores.parquet 6월 연장 (append-only).
## v1 실측: 저장 파일은 equal-mean(factor_group_consolidation.R) 재현 불가(max|d| 4.4/11.5)
##   → 생성기 = **factor_group_consolidation_icw.R** (IC-가중 v2, 316 breadth,
##   weight=max(PIT expanding trailing rank-IC,0), wsum~0시 EW fallback)로 판명. 자구 재현.
## parity 테스트월은 2026-04 rawdata 재빌드(07-11 April-gap 수리) 영향권 밖(<2026-01)으로 선정.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
TD<-"stage_artifacts/plumbing_fq044_20260714"
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns
GS<-"outputs/ramp/factor_group_scores.parquet"
BAK<-"outputs/ramp/factor_group_scores_pre202606ext_backup_20260714.parquet"

## fam_of — factor_group_consolidation_icw.R 자구동일
fam_of <- function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V") "Value" else if(p1=="M"&&p!="MA") "Momentum" else if(p1=="Q") "Quality"
  else if(p1=="D") "LowRisk" else if(p1=="L") "Size_Liquidity" else if(p1=="S"&&p!="SE") "Size_Liquidity"
  else if(p1=="R") "Reversal" else if(p=="GR") "Growth_Profit" else if(p=="AC") "Accruals"
  else if(p1=="C"&&p!="CR") "Consensus" else if(p=="CR") "Credit" else if(p=="IN") "Growth_Profit"
  else if(p=="XF") "Composite" else if(p=="MA") "Macro" else if(p=="TR") "Size_Liquidity" else "Composite" }

G<-as.data.table(read_parquet(GS)); G[,signal_date:=as.Date(signal_date)]
stopifnot(max(G$signal_date)==as.Date("2026-05-31"))
n_old<-nrow(G)
ckG0<-G[,.(n=.N, s=sum(as.numeric(group_z),na.rm=TRUE)), by=signal_date][order(signal_date)]

af<-as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
sig<-sort(unique(af$factor_id))  # 전체 316 (icw 자구)
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet",
      col_select=c("signal_date","security_id","factor_id","neutralized_z")))
sc[,signal_date:=as.Date(signal_date)]; sc<-sc[factor_id %in% sig]
sc[,family:=sapply(factor_id,fam_of)]; sc<-sc[family!="Macro"]
cat(sprintf("[icw] base %d factors, %d rows, %d months (June incl)\n", uniqueN(sc$factor_id), nrow(sc), uniqueN(sc$signal_date)))

## forward returns (IC용) — icw 자구: sig_dates = pure 파일 전체 월
rawdata<-as.data.table(read_parquet(".cache/rawdata.parquet",
  col_select=all_of(c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret"))))
rawdata[,Date:=as.Date(Date)]
sig_dates<-sort(unique(sc$signal_date)); fwd<-build_monthly_forward_returns(rawdata,sig_dates)
fr<-fwd$returns_dt[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)]
rm(rawdata); invisible(gc())

## 팩터-월 rank-IC + PIT expanding trailing mean (icw 자구동일)
icm<-merge(sc[,.(signal_date,security_id,factor_id,neutralized_z)],fr,by=c("signal_date","security_id"))
fic<-icm[,.(ic=if(.N>=20&&sd(neutralized_z)>0&&sd(Ret_1m)>0)cor(neutralized_z,Ret_1m,method="spearman")else NA_real_),
         by=.(signal_date,factor_id)]
rm(icm); invisible(gc())
## NA 월 삽입 주의: icw는 fic가 (signal_date,factor_id) 존재행만 갖고 shift(cumsum/cumsum)로 직전까지 누적평균.
## 팩터가 특정 월에 IC 미산출(merge 자체에 행 없음)이면 그 월은 fic에 없음 — 자구 재현 위해 동일하게 둠.
setorder(fic,factor_id,signal_date)
fic[,ic_trail:=shift(cumsum(fifelse(is.na(ic),0,ic))/cumsum(!is.na(ic)),1),by=factor_id]
fic[is.na(ic_trail),ic_trail:=0]

## IC-가중 composite (자구동일)
sc2<-merge(sc,fic[,.(signal_date,factor_id,ic_trail)],by=c("signal_date","factor_id"),all.x=TRUE)
sc2[is.na(ic_trail),ic_trail:=0]; sc2[,wgt:=pmax(ic_trail,0)]
sc2[,wsum:=sum(wgt),by=.(signal_date,security_id,family)]
sc2[,wgt2:=fifelse(wsum<1e-9, 1.0, wgt)]
grp<-sc2[,.(z=sum(neutralized_z*wgt2)/sum(wgt2)),by=.(signal_date,security_id,family)]
grp[,gz:={m<-mean(z,na.rm=T);s<-sd(z,na.rm=T);if(is.na(s)||s<1e-9)z-m else (z-m)/s},by=.(signal_date,family)]
GRP<-grp[,.(signal_date,security_id,family,group_z=gz)]
rm(sc,sc2,grp); invisible(gc())

## parity: April-2026 rawdata 수리 영향권 밖 테스트월 3곳 (ic_trail 윈도 < 2026-01)
tm<-as.Date(c("2015-06-30","2020-08-31","2025-11-28"))
tm<-tm[tm %in% unique(G$signal_date)]
if(length(tm)<3){ alt<-sort(unique(G$signal_date)); tm<-c(tm, alt[format(alt,"%Y")=="2025"][1:(3-length(tm))]) }
m<-merge(GRP[signal_date %in% tm], G[signal_date %in% tm,.(signal_date,security_id,family,ref=group_z)],
         by=c("signal_date","security_id","family"), all=TRUE)
n_miss<-sum(is.na(m$group_z)|is.na(m$ref)); d<-m[!is.na(group_z)&!is.na(ref),max(abs(group_z-ref))]
cat(sprintf("[icw parity %s] n=%d miss=%d max|d|=%.3e\n", paste(as.character(tm),collapse=","), nrow(m), n_miss, d))
## 진단: 최근월(2026-05-31) delta — April 수리 영향 가시화 (게이트 아님)
m5<-merge(GRP[signal_date==as.Date("2026-05-31")], G[signal_date==as.Date("2026-05-31"),.(signal_date,security_id,family,ref=group_z)],
          by=c("signal_date","security_id","family"))
cat(sprintf("[icw diag 2026-05] n=%d max|d|=%.3e (rawdata 04월 수리 후 재현 — 참고용)\n", nrow(m5), m5[,max(abs(group_z-ref))]))
stopifnot(n_miss==0, d < 1e-9)

## June rows + append-only
JG<-GRP[signal_date==as.Date("2026-06-30")]
cat(sprintf("[grp] June rows=%d families=%d tickers=%d\n", nrow(JG), uniqueN(JG$family), uniqueN(JG$security_id)))
stopifnot(nrow(JG)>1000)
if(!file.exists(BAK)){ .t<-paste0(BAK,".tmp_",Sys.getpid()); file.copy(GS,.t); file.rename(.t,BAK); cat("[grp] backup ->",BAK,"\n") }
ALL<-rbindlist(list(G,JG), use.names=TRUE, fill=TRUE); setkey(ALL, signal_date, family, security_id)
.t<-paste0(GS,".tmp_",Sys.getpid()); write_parquet(ALL,.t)
rm(G,ALL); invisible(gc())
if(!file.remove(GS)) stop("remove fail"); if(!file.rename(.t,GS)) stop("rename fail")

A<-as.data.table(read_parquet(GS)); A[,signal_date:=as.Date(signal_date)]
ckG1<-A[signal_date<=as.Date("2026-05-31"),.(n=.N, s=sum(as.numeric(group_z),na.rm=TRUE)), by=signal_date][order(signal_date)]
same<-isTRUE(all.equal(ckG0, ckG1, tolerance=0)) && nrow(ckG0)==nrow(ckG1)
cat(sprintf("[verify] pre-June identical=%s | rows %d->%d | months=%d max=%s\n",
  same, n_old, nrow(A), uniqueN(A$signal_date), as.character(max(A$signal_date))))
if(!same){ file.remove(GS); file.copy(BAK,GS); stop("group vintage guard fail — restored") }
saveRDS(list(generator="factor_group_consolidation_icw.R", parity_months=as.character(tm), maxd=d,
             diag_202605_maxd=m5[,max(abs(group_z-ref))], n_june=nrow(JG)), file.path(TD,"p5_group_verify.rds"))
cat("P5_GROUP_DONE\n")
