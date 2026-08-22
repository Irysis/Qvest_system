## run_dfa_pg2overlay_r23.R — R23: PG2 정본 국면 오버레이를 R20 채택팔(F1 top-quintile k=5)에 적용 (prereg dfa_v19)
## ★적용 지점 = '팩터 비중'이 아니라 '총 노출'. 팩터 비중 결정 로직은 무국면(팩터 모멘텀)으로 불변.
suppressPackageStartupMessages({library(data.table);library(arrow);library(xts)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
source("02_Infrastructure/regime/apply_regime_overlay.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
source("02_Infrastructure/contracts/essence_score.R")
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
MDD<-function(r){n<-cumprod(1+r);min(n/cummax(n)-1)}; CAGR<-function(r)prod(1+r)^(12/length(r))-1
KTOP<-5L   # R20 채택팔
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)];setorder(R,Date);R<-R[is.finite(Market)]
fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market")); R[,ym:=format(Date,"%Y-%m")]
mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),by=ym,.SDcols=c("Market",fac)]
setorder(mon,medate); NM<-nrow(mon); NAx<-1+length(fac)
S<-matrix(NA_real_,NM,length(fac))
for(fi in seq_along(fac)) for(m in 12:NM){ w<-(m-11):m; S[m,fi]<-prod(1+mon[[fac[fi]]][w])/prod(1+mon$Market[w])-1 }
Rmat<-as.matrix(R[,c("Market",fac),with=FALSE]); Rmat[!is.finite(Rmat)]<-0
mon_idx<-match(R$ym,mon$ym); ND<-nrow(R)
coh_daily<-matrix(NA_real_,3,ND)
for(cc in 0:2){ st<-13+cc; wprev<-rep(1/NAx,NAx); wlive<-NULL; wcur<-NULL
  for(m in st:NM){ d<-m-1
    if(is.null(wcur)||((m-st)%%3==0)){ s<-S[d,]; pos<-which(is.finite(s)&s>0)
      if(length(pos)>KTOP) pos<-pos[order(s[pos],decreasing=TRUE)][1:KTOP]     # ★top-quintile (R20 채택)
      w<-rep(0,NAx); if(length(pos)==0) w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); wcur<-w; wlive<-wcur }
    rows<-which(mon_idx==m); if(!length(rows)) next
    for(j in seq_along(rows)){ t<-rows[j]; ri<-Rmat[t,]
      dlt<-if(j==1) sum(abs(wlive-wprev)) else 0
      coh_daily[cc+1,t]<-sum(wlive*ri)-(15/1e4)*dlt
      wd<-wlive*(1+ri); wlive<-wd/sum(wd) }
    wprev<-wlive } }
ok_d<-which(apply(coh_daily,2,function(v)all(is.finite(v))))
DAILY<-data.table(Date=R$Date[ok_d],Strategy_Ret=colMeans(coh_daily[,ok_d,drop=FALSE]),Market_Ret=Rmat[ok_d,1])
DAILY[,NAV:=1e8*cumprod(1+Strategy_Ret)]; DAILY[,ym:=format(Date,"%Y-%m")]
cat(sprintf("일별 재구성: %d일 %s ~ %s\n",nrow(DAILY),format(min(DAILY$Date)),format(max(DAILY$Date))))
## sanity: 월집계가 R20 월간 채택팔과 일치하는가
Z<-readRDS(".cache/_dfa_r20.rds"); mo<-Z$mon
magg<-DAILY[,.(pr=prod(1+Strategy_Ret)-1,mk=prod(1+Market_Ret)-1),by=ym]
cm<-intersect(mo$ym[is.finite(Z$res$F1_topquintile_k5$pr)],magg$ym); cm<-cm[cm<="2026-07"]
pn<-nwt(magg[match(cm,ym),pr-mk]); po<-nwt((Z$res$F1_topquintile_k5$pr-mo$Market)[match(cm,mo$ym)])
cat(sprintf("[sanity] 재구성 pt=%.3f vs R20 월간 pt=%.3f | Δ=%.3f -> %s\n",pn,po,pn-po,
  ifelse(abs(pn-po)<=0.15,"PASS","FAIL(측정무효)")))
## 국면 오버레이
rp<-".cache/regime_daily_v2.parquet"; stopifnot(file.exists(rp))
reg<-as.data.table(read_parquet(rp)); reg[,Date:=as.Date(Date)]
run_ov<-function(lag_days=0L){
  rr<-copy(reg)[,.(Date,MRS,n_axes_firing)]
  if(lag_days>0L){ setorder(rr,Date); rr[,MRS:=shift(MRS,lag_days)][,n_axes_firing:=shift(n_axes_firing,lag_days)]; rr<-rr[!is.na(MRS)] }
  sim<-list(DAILY_NAV_DT=DAILY[,.(Date,Strategy_Ret,NAV)],strategy_xts=xts(DAILY$Strategy_Ret,order.by=DAILY$Date))
  o<-tryCatch(apply_regime_overlay(sim,rr,DAILY[,.(Date,BM_Ret=Market_Ret)]),error=function(e){cat("[ov ERR]",conditionMessage(e),"\n");NULL})
  if(is.null(o)) return(NULL)
  O<-as.data.table(o$DAILY_NAV_DT); O[,ym:=format(Date,"%Y-%m")]
  rc<-grep("^Ret_overlay$|^Strategy_Ret_overlay$|overlay",names(O),value=TRUE)[1]
  O[,.(r=prod(1+get(rc))-1),by=ym] }
agg0<-DAILY[,.(r=prod(1+Strategy_Ret)-1,mk=prod(1+Market_Ret)-1),by=ym][ym<="2026-07"]
E<-list(full=rep(TRUE,nrow(agg0)), clean=agg0$ym>="2015-07")
report<-function(v,lab,ymv){ for(w in c("full","clean")){ s<-if(w=="full") rep(TRUE,length(v)) else ymv>="2015-07"
  x<-v[s]; b<-agg0$mk[match(ymv[s],agg0$ym)]
  cat(sprintf("  %-22s [%-5s] n=%3d | CAGR %+.3f MDD %.3f **calmar %.3f** | pt=%+.3f IR=%+.3f\n",
    lab,w,length(x),CAGR(x),MDD(x),CAGR(x)/abs(MDD(x)),nwt(x-b),IRf(x-b))) } }
cat("\n=== R23: PG2 정본 국면 오버레이 → R20 채택팔 (prereg dfa_v19) ===\n")
cat("[H0 대조 — 오버레이 없음]\n"); report(agg0$r,"H0_control",agg0$ym)
for(lg in c(0L,1L,5L)){ ov<-run_ov(lg); if(is.null(ov)) next
  m<-merge(agg0[,.(ym)],ov,by="ym",all.x=TRUE); setorder(m,ym); m<-m[is.finite(r)]
  cat(sprintf("\n[H1 오버레이 · 신호지연 %d일%s]\n",lg,ifelse(lg==0," (정본)"," (lag 스트레스)")))
  report(m$r,"H1_pg2overlay",m$ym) }
cat("\n[문턱 대비]\n  calmar 문턱 0.64 · PORT_t 문턱 2.95\n")
saveRDS(list(DAILY=DAILY,agg0=agg0),".cache/_dfa_r23.rds")
cat("\nR23_DONE\n")
