suppressPackageStartupMessages({library(data.table);library(xts);library(sandwich);library(lmtest)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/backtest_result_contract.R"); source("02_Infrastructure/contracts/essence_score.R")
Z<-readRDS("stage_artifacts/probe_a5_20260822/adv_refute/adv_core.rds"); mon<-Z$mon; fac<-Z$fac; S<-Z$S12
TOs<-readRDS("stage_artifacts/probe_a5_20260822/adv_refute/idx_turnover.rds")$S
NM<-nrow(mon); NAx<-1+length(fac)
nwt<-function(x){x<-x[is.finite(x)];m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
arm<-function(RETm,bps=15,freq=3,start_m=13,phase=0,Sx=S){
  pr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM); WH<-matrix(NA_real_,NM,NAx)
  wprev<-rep(1/NAx,NAx); wcur<-NULL
  for(m in start_m:NM){ d<-m-1
    if(is.null(wcur)||((m-start_m-phase)%%freq==0)){ s<-Sx[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
      if(length(pos)==0)w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); wcur<-w }
    WH[m,]<-wcur; ri<-RETm[m,]; dlt<-sum(abs(wcur-wprev)); tov[m]<-dlt
    pr[m]<-sum(wcur*ri)-(bps/1e4)*dlt; wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev }
  list(pr=pr,tov=tov,W=WH) }
RET<-as.matrix(mon[,c("Market",fac),with=FALSE]); RET[!is.finite(RET)]<-0
base<-arm(RET); k<-is.finite(base$pr)
cat("== A5 average weights (time-mean over 236 months) ==\n")
wm<-colMeans(base$W[k,]); names(wm)<-c("Market",fac)
print(round(sort(wm,decreasing=TRUE),4))
cat("  sum=",round(sum(wm),4),"\n")
## omitted monthly index-level cost per index (15bps per leg on |dw|): c = oneway*2*0.0015
cst<-setNames(rep(NA_real_,NAx),c("Market",fac))
for(nm in names(cst)) cst[nm]<-TOs[idx==nm,mean_oneway_monthly]*2*0.0015
cat("\n== omitted monthly index-level cost (bps/mo) ==\n"); print(round(cst*1e4,1))
cat("  A5 weight-averaged omitted cost = ",round(sum(wm*cst)*1200,3),"%/yr | Market benchmark = ",
    round(cst["Market"]*1200,3),"%/yr | NET drag on active = ",round((sum(wm*cst)-cst["Market"])*1200,3),"%/yr\n")
## rebuild indices net of their own rebalancing cost, then rerun A5 (metric_type = estimated)
RET2<-RET; for(j in seq_len(NAx)) RET2[,j]<-RET[,j]-cst[j]
a2<-arm(RET2); k2<-is.finite(a2$pr)
act0<-base$pr[k]-mon$Market[k]; act2<-a2$pr[k2]-RET2[k2,1]
cat("\n== A5 with index-level costs charged (estimated) ==\n")
cat(sprintf("  base   : pt=%.3f  ann_active=%.4f\n",nwt(act0),mean(act0)*12))
cat(sprintf("  netcost: pt=%.3f  ann_active=%.4f   (delta pt = %+.3f)\n",nwt(act2),mean(act2)*12,nwt(act2)-nwt(act0)))
sc<-function(p,mk,d,tag){ sim<-list(DAILY_NAV_DT=data.table(Date=d,Strategy_Ret=p,NAV=cumprod(1+p)),
   strategy_xts=xts(p,order.by=d),bm_xts=xts(mk,order.by=d),cost_model_version="adv_netidxcost")
  spec<-list(strategy_name=tag,description="adv",universe="KR broad-21",rebalance="q",signal="fm")
  bt<-build_bt_result(sim,spec,run_id=tolower(tag),strategy_id=toupper(tag),benchmark_id="CAPW_PARENT",
   benchmark_name="cap-w parent",transaction_cost_bps=15,slippage_bps=0,frequency="monthly",
   universe_id="K200_KQ150",code_version="adv_r08",created_by_agent="adversary")
  es<-essence_score(bt,n_trials_cumulative=56,selection_type="chain"); e<-es$essence
  data.table(tag=tag,n=length(p),pt=e$portfolio_alpha_t_nw_lag3,oos=e$oos_retention,calmar=e$calmar,SR=e$net_sharpe)}
print(rbind(sc(base$pr[k],mon$Market[k],mon$medate[k],"A5_gross_idx"),
            sc(a2$pr[k2],RET2[k2,1],mon$medate[k2],"A5_net_idxcost")))
## C1 comparison under net-cost indices
c1a<-arm(RET,15,1); c1b<-arm(RET2,15,1); kc<-is.finite(c1a$pr)
cat(sprintf("\n  C1 base pt=%.3f -> netcost pt=%.3f\n",nwt(c1a$pr[kc]-RET[kc,1]),nwt(c1b$pr[kc]-RET2[kc,1])))
## which factors carry A5 weight vs their turnover
cat("\n== weight x turnover cross-table (top 8 by weight) ==\n")
DT<-data.table(idx=names(wm),wt=wm,ow=TOs[match(names(wm),idx),mean_oneway_monthly])[order(-wt)]
print(head(DT,10),digits=3)
