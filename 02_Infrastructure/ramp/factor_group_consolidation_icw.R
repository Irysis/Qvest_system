## factor_group_consolidation_icw.R — 팩터군 보강 v2: IC-품질 가중 composite (equal-weight 희석 해소)
## 전체 316 breadth 사용하되 군내 팩터를 PIT-trailing rank-IC로 가중 → 약한/기각 팩터 자동 down-weight,
##   강한 팩터 dominate. 순진한 equal-weight(316)가 noise 희석으로 악화된 것 교정.
## PIT: weight_m,t = max(trailing_IC_m(signal_date<t), 0) — 미래 미참조. 군별 net 검증 + group_scores.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source(file.path(QM,"02_Infrastructure/config.R")); source("02_Infrastructure/ramp/factor_validation.R")
con<-file(".cache/_consol_icw.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)
fam_of <- function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V") "Value" else if(p1=="M"&&p!="MA") "Momentum" else if(p1=="Q") "Quality"
  else if(p1=="D") "LowRisk" else if(p1=="L") "Size_Liquidity" else if(p1=="S"&&p!="SE") "Size_Liquidity"
  else if(p1=="R") "Reversal" else if(p=="GR") "Growth_Profit" else if(p=="AC") "Accruals"
  else if(p1=="C"&&p!="CR") "Consensus" else if(p=="CR") "Credit" else if(p=="IN") "Growth_Profit"
  else if(p=="XF") "Composite" else if(p=="MA") "Macro" else if(p=="TR") "Size_Liquidity" else "Composite" }

af<-as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
sig<-sort(unique(af$factor_id))  # 전체 316
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet",
      col_select=c("signal_date","security_id","factor_id","neutralized_z")))
sc[,signal_date:=as.Date(signal_date)]; sc<-sc[factor_id %in% sig]
sc[,family:=sapply(factor_id,fam_of)]; sc<-sc[family!="Macro"]
w(sprintf("보강 v2 (IC-가중) | 기저 %d 팩터, %d rows", uniqueN(sc$factor_id), nrow(sc)))

# forward returns (IC 계산용)
rawdata<-as.data.table(read_parquet(".cache/rawdata.parquet",
  col_select=all_of(c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret"))))
rawdata[,Date:=as.Date(Date)]
sig_dates<-sort(unique(sc$signal_date)); fwd<-build_monthly_forward_returns(rawdata,sig_dates)
fr<-fwd$returns_dt[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)]

# 팩터별 월별 rank-IC (cross-sectional spearman)
icm<-merge(sc[,.(signal_date,security_id,factor_id,neutralized_z)],fr,by=c("signal_date","security_id"))
fic<-icm[,.(ic=if(.N>=20&&sd(neutralized_z)>0&&sd(Ret_1m)>0)cor(neutralized_z,Ret_1m,method="spearman")else NA_real_),
         by=.(signal_date,factor_id)]
setorder(fic,factor_id,signal_date)
# trailing 평균 IC (expanding, signal_date<t) — PIT
fic[,ic_trail:=shift(cumsum(fifelse(is.na(ic),0,ic))/cumsum(!is.na(ic)),1),by=factor_id]  # 직전까지 누적평균
fic[is.na(ic_trail),ic_trail:=0]
w(sprintf("팩터-월 IC 계산 완료: %d rows", nrow(fic)))

# IC-가중 group composite: weight = max(ic_trail,0), 군내 정규화
sc2<-merge(sc,fic[,.(signal_date,factor_id,ic_trail)],by=c("signal_date","factor_id"),all.x=TRUE)
sc2[is.na(ic_trail),ic_trail:=0]; sc2[,wgt:=pmax(ic_trail,0)]
# 군내 weight 합 0이면 equal-weight fallback
sc2[,wsum:=sum(wgt),by=.(signal_date,security_id,family)]
sc2[,wgt2:=fifelse(wsum<1e-9, 1.0, wgt)]
grp<-sc2[,.(z=sum(neutralized_z*wgt2)/sum(wgt2), n_members=uniqueN(factor_id)),by=.(signal_date,security_id,family)]
grp[,gz:={m<-mean(z,na.rm=T);s<-sd(z,na.rm=T);if(is.na(s)||s<1e-9)z-m else (z-m)/s},by=.(signal_date,family)]

# 군별 net 검증
fams<-sort(unique(grp$family)); mets<-list()
for(fm in fams){ sdt<-grp[family==fm,.(signal_date,security_id,factor_id=fm,neutralized_z=gz)]
  v<-tryCatch(validate_factor(sdt,fwd,top_n=20L,cost_bps=15),error=function(e)NULL)
  if(is.null(v))next
  mets[[fm]]<-data.table(group=fm,net_sr=v$net_sr,port_t=v$portfolio_alpha_t_nw,ir=v$information_ratio) }
M<-rbindlist(mets,fill=TRUE)[order(-port_t)]
w("\n=== 군별 long-only top-20 net (IC-가중 v2) ===")
for(i in seq_len(nrow(M))) w(sprintf("  %-16s net_sr=%+.3f port_t=%+.2f ir=%+.2f",M$group[i],M$net_sr[i],M$port_t[i],M$ir[i]))
wide<-dcast(grp,signal_date+security_id~family,value.var="gz"); fcols<-setdiff(names(wide),c("signal_date","security_id"))
cmat<-cor(as.matrix(wide[,..fcols]),use="pairwise.complete.obs"); od<-cmat[upper.tri(cmat)]
w(sprintf("\n군간 |cor|: mean=%.3f max=%.3f", mean(abs(od)), max(abs(od))))

write_parquet(grp[,.(signal_date,security_id,family,group_z=gz)],"outputs/ramp/factor_group_scores.parquet")
w("\n[보강 v2 완료] IC-가중 316 → factor_group_scores 갱신")
close(con); cat("ICW_DONE\n")
