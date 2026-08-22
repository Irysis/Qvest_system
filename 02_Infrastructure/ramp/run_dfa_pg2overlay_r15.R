## run_dfa_pg2overlay_r15.R — R15: PG2 정본 위기 자본배분 로직을 A5E에 적용 (prereg dfa_v14)
## 오버레이 = apply_regime_overlay.R 정본(수정 금지, 기본 파라미터). NORMAL 100% / CAUTION 선형축소 / CRISIS 50%+인버스20%+현금30%
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
source("02_Infrastructure/regime/apply_regime_overlay.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
source("02_Infrastructure/contracts/essence_score.R")
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}

## ---- 1) A5E 일별 재구성 (월간 비중 → 일별 드리프트, 3코호트) ----
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market")); R[,ym:=format(Date,"%Y-%m")]
mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),by=ym,.SDcols=c("Market",fac)]
setorder(mon,medate); NM<-nrow(mon); NAx<-1+length(fac)
S<-matrix(NA_real_,NM,length(fac))
for(fi in seq_along(fac)) for(m in 12:NM){ w<-(m-11):m; S[m,fi]<-prod(1+mon[[fac[fi]]][w])/prod(1+mon$Market[w])-1 }
Rmat<-as.matrix(R[,c("Market",fac),with=FALSE]); Rmat[!is.finite(Rmat)]<-0
mon_idx<-match(R$ym, mon$ym); ND<-nrow(R)
## 코호트별 일별 수익 (분기 결정, 월말 결정 → 익월부터 적용, 일별 드리프트)
coh_daily<-matrix(NA_real_,3,ND); coh_to<-matrix(0,3,ND)
for(cc in 0:2){ st<-13+cc; wprev<-rep(1/NAx,NAx); wcur<-NULL; wlive<-NULL
  for(m in st:NM){ d<-m-1
    if(is.null(wcur) || ((m-st)%%3==0)){
      s<-S[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
      if(length(pos)==0) w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); wcur<-w
      wlive<-wcur }
    rows<-which(mon_idx==m); if(!length(rows)) next
    for(j in seq_along(rows)){ t<-rows[j]; ri<-Rmat[t,]
      if(j==1){ dlt<-sum(abs(wlive-wprev)); coh_to[cc+1,t]<-dlt } else dlt<-0
      coh_daily[cc+1,t]<-sum(wlive*ri)-(15/1e4)*dlt
      wd<-wlive*(1+ri); wlive<-wd/sum(wd) }
    wprev<-wlive } }
ok_d<-which(apply(coh_daily,2,function(v)all(is.finite(v))))
DAILY<-data.table(Date=R$Date[ok_d], Strategy_Ret=colMeans(coh_daily[,ok_d,drop=FALSE]),
                  Market_Ret=Rmat[ok_d,1])
DAILY[,NAV:=1e8*cumprod(1+Strategy_Ret)]
cat("일별 재구성:",nrow(DAILY),"일 |",format(min(DAILY$Date)),"~",format(max(DAILY$Date)),"\n")

## ---- sanity: 월 집계가 기존 월간 A5E와 일치하는가 (prereg sanity_gate) ----
DAILY[,ym:=format(Date,"%Y-%m")]
magg<-DAILY[,.(pr=prod(1+Strategy_Ret)-1, mk=prod(1+Market_Ret)-1, d=max(Date)),by=ym]
Zold<-readRDS(".cache/_dfa_a5e_r12.rds")$base
cm<-intersect(format(Zold$d,"%Y-%m"), magg$ym)
pt_new<-nwt(magg[match(cm,ym),pr-mk]); pt_old<-nwt((Zold$pr-Zold$mk)[match(cm,format(Zold$d,"%Y-%m"))])
cat(sprintf("[sanity] 재구성 월집계 pt=%.3f vs 기존 월간 A5E pt=%.3f | Δ=%.3f -> %s\n",
  pt_new,pt_old,pt_new-pt_old, ifelse(abs(pt_new-pt_old)<=0.15,"PASS","FAIL(측정무효)")))

## ---- 2) PG2 오버레이 적용 ----
reg<-as.data.table(read_parquet(".cache/regime_daily_v2.parquet"))
reg[,Date:=as.Date(Date)]
regime_dt<-reg[,.(Date,MRS,n_axes_firing)]
BM_DT<-DAILY[,.(Date, BM_Ret=Market_Ret)]
sim<-list(DAILY_NAV_DT=DAILY[,.(Date,Strategy_Ret,NAV)], strategy_xts=xts(DAILY$Strategy_Ret,order.by=DAILY$Date))
ov<-tryCatch(apply_regime_overlay(sim, regime_dt, BM_DT), error=function(e){cat("[overlay ERROR]",conditionMessage(e),"\n"); NULL})
if(is.null(ov)) quit(status=1)
OV<-as.data.table(ov$DAILY_NAV_DT)
cat("\n[Layer 분포]"); print(ov$overlay_stats)

## ---- 3) 월 집계 후 계약 채점 (전체창 + 안정창) ----
mk_month<-function(dt,retcol){ x<-copy(dt); x[,ym:=format(Date,"%Y-%m")]
  x[,.(pr=prod(1+get(retcol))-1, d=max(Date)),by=ym] }
mm_base<-mk_month(DAILY,"Strategy_Ret"); mm_ov<-mk_month(OV,"Ret_overlay")
mm_mkt<-mk_month(DAILY,"Market_Ret")
## 시장 오버레이 단독 (8-1 순서 요건)
sim_m<-list(DAILY_NAV_DT=data.table(Date=DAILY$Date,Strategy_Ret=DAILY$Market_Ret,NAV=1e8*cumprod(1+DAILY$Market_Ret)),
            strategy_xts=xts(DAILY$Market_Ret,order.by=DAILY$Date))
ovm<-apply_regime_overlay(sim_m, regime_dt, BM_DT)
mm_mkov<-mk_month(as.data.table(ovm$DAILY_NAV_DT),"Ret_overlay")

score<-function(mm,lab,win="full"){
  ymv<-mm$ym; sel<-if(win=="ex2026") substr(ymv,1,4)<"2026" else rep(TRUE,length(ymv))
  d<-mm$d[sel]; p<-mm$pr[sel]; mk<-mm_mkt$pr[match(mm$ym[sel],mm_mkt$ym)]
  k<-is.finite(p)&is.finite(mk); d<-d[k];p<-p[k];mk<-mk[k]
  sim2<-list(DAILY_NAV_DT=data.table(Date=d,Strategy_Ret=p,NAV=cumprod(1+p)),
             strategy_xts=xts(p,order.by=d),bm_xts=xts(mk,order.by=d),cost_model_version="r15_15bps")
  spec<-list(strategy_name=lab,description="R15 PG2 overlay",universe="KR broad-21",rebalance="monthly 1/3",signal="FM+PG2ov")
  bt<-build_bt_result(sim2,spec,run_id=tolower(gsub("[^A-Za-z0-9]","_",paste0(lab,win))),strategy_id=lab,
      benchmark_id="CAPW_PARENT",benchmark_name="cap-w",transaction_cost_bps=15,slippage_bps=0,
      frequency="monthly",universe_id="K200_KQ150",code_version="run_dfa_pg2overlay_r15.R",created_by_agent="Q-Lead")
  es<-essence_score(bt,n_trials_cumulative=68,selection_type="chain"); e<-es$essence
  cat(sprintf("%-22s [%-7s] n=%3d | pt=%+.3f oos=%+.3f calmar=%.3f MDD=%.3f SR=%.3f\n",
    lab,win,length(p),e$portfolio_alpha_t_nw_lag3,e$oos_retention,e$calmar,e$mdd,e$net_sharpe))
  invisible(e) }
cat("\n=== 계약 채점 ===\n")
for(w in c("full","ex2026")){
  score(mm_base,"A5E_daily_base",w); score(mm_ov,"A5E_x_PG2overlay",w); score(mm_mkov,"MKT_x_PG2overlay",w) }
saveRDS(list(DAILY=DAILY,OV=OV,stats=ov$overlay_stats),".cache/_dfa_pg2ov_r15.rds")
cat("R15_DONE\n")
