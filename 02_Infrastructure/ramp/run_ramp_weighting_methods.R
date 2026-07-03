## run_ramp_weighting_methods.R — 도훈: "EW는 기준이고 다양한 비중결정방법론 이용 가능".
## IC-가중 M_regdd score 위에 종목가중법 비교: EW(기준) vs score-가중 vs inverse-vol vs 결합 vs top-N확장.
## weighted_screen_bt(contract-grade cap-w port_t) 경유. 게이트: pt_capwt·oos_retention·calmar.
## 가설: inverse-vol→MDD↓→calmar↑ / score-가중→port_t↑. PIT: vol·score 모두 trailing.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R"); source("02_Infrastructure/contracts/backtest_result_contract.R")
suppressMessages({library(sandwich);library(lmtest)})
con<-file(".cache/_ramp_weighting.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)
PG<-".cache/_wm_prog.txt"; cat("start\n",file=PG); pg<-function(...)cat(sprintf(...),file=PG,append=TRUE)
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9) x-m else (x-m)/s}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}

## --- M_regdd score (IC-가중 군 → 레짐-IC 결합) ---
g<-as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet")); g[,signal_date:=as.Date(signal_date)]
gw<-dcast(g,signal_date+security_id~family,value.var="group_z"); grp<-setdiff(names(gw),c("signal_date","security_id"))
a<-as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); a[,Date:=as.Date(Date)]
reg<-unique(a[,.(ym=format(Date,"%Y-%m"),regime=regime_state)])[,.SD[1],by=ym]
gw[,ym:=format(signal_date,"%Y-%m")]; gw<-merge(gw,reg,by="ym",all.x=TRUE); gw[is.na(regime),regime:="NORMAL"]
.need<-c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata<-as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
sig_dates<-sort(unique(g$signal_date)); fwd<-build_monthly_forward_returns(rawdata,sig_dates)
ic<-merge(g[,.(signal_date,security_id,family,group_z)],fwd$returns_dt[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)],by=c("signal_date","security_id"))
gic<-ic[,.(ic=if(.N>=10&&sd(group_z)>0&&sd(Ret_1m)>0)cor(group_z,Ret_1m,method="spearman")else NA_real_),by=.(signal_date,family)]
gic<-merge(gic,unique(gw[,.(signal_date,regime)]),by="signal_date"); setorder(gic,family,signal_date)
rows<-list()
for(d in as.character(sig_dates)){dd<-as.Date(d);rg<-gw[signal_date==dd,regime][1]
  wts<-sapply(grp,function(fm){p<-gic[family==fm&regime==rg&signal_date<dd,ic];p<-p[is.finite(p)];if(length(p)>=3)max(mean(p),0)else 0})
  if(sum(wts)<1e-9)wts<-setNames(rep(1,length(grp)),grp);ww<-wts/sum(wts)
  sub<-gw[signal_date==dd];X<-as.matrix(sub[,..grp]);X[is.na(X)]<-0
  rows[[d]]<-data.table(signal_date=dd,security_id=sub$security_id,score=as.numeric(X%*%ww))}
sc<-rbindlist(rows); sc[,score:=zc(score),by=signal_date]; pg("score built %d rows\n",nrow(sc))

## --- 종목 trailing vol (PIT, 24m) — frollapply 대신 frollsd-동등(연산 안정) ---
rr<-fwd$returns_dt[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)]; setorder(rr,security_id,signal_date)
rr[,vsd:=frollapply(Ret_1m,24,FUN=function(x)sd(x,na.rm=TRUE),fill=NA_real_,align="right"),by=security_id]
rr[,vol_trail:=shift(vsd,1),by=security_id]   # 직전까지 24m vol (PIT)
volmap<-rr[,.(signal_date,security_id,vol_trail)]; pg("volmap built %d rows\n",nrow(volmap))

## --- 비중법별 weights_dt 생성 (각 월 top-N 선택 후 가중) ---
fwd_ret<-fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)]; bench<-fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)]
liq<-fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
mk_w<-function(method, topn=25L){
  S<-merge(sc[,.(signal_date,security_id,score)],volmap,by=c("signal_date","security_id"),all.x=TRUE)
  S<-merge(S,liq[,.(signal_date=Date,security_id=Ticker,adv)],by=c("signal_date","security_id"),all.x=TRUE)
  S<-S[is.na(adv)|adv>=2e8]                                  # 유동성
  out<-list()
  for(dch in as.character(unique(S$signal_date))){ dd<-as.Date(dch)   # [수정] character 순회 — Date 클래스 보존(for-loop가 Date→numeric 벗김 방지)
    sub<-S[signal_date==dd][order(-score)][1:min(topn,.N)]
    sub<-sub[is.finite(score)]; if(nrow(sub)<3)next
    vv<-sub$vol_trail; vv[is.na(vv)|vv<1e-4]<-median(vv,na.rm=TRUE); if(all(is.na(vv)))vv<-rep(1,nrow(sub))
    wv<-switch(method,
      EW          = rep(1,nrow(sub)),
      SCORE       = pmax(sub$score-min(sub$score)+1e-6,0),   # 양수 conviction
      INVVOL      = 1/vv,
      SCORE_INVVOL= pmax(sub$score-min(sub$score)+1e-6,0)/vv,
      rep(1,nrow(sub)))
    wv<-pmin(wv/sum(wv),0.20); wv<-wv/sum(wv)                # cap 0.20 + 정규화
    out[[dch]]<-data.table(Date=dd,Ticker=sub$security_id,w=wv) }
  rbindlist(out)
}
## --- 게이트 산출 (weighted_screen_bt) ---
gates<-function(W,lab){
  r<-tryCatch(weighted_screen_bt(W,fwd_ret[,.(Date,Ticker,Ret_1m)],bench,cost_bps_oneway=15,run_id="wm",strategy_id=lab),error=function(e)NULL)
  if(is.null(r)||is.null(r$period_returns))return(NULL)
  pr<-as.data.table(r$period_returns); setorder(pr,date); act<-pr$ret_net-pr$benchmark_ret
  n<-nrow(pr); .sp<-c(0.55,0.65,0.75)
  rets<-sapply(.sp,function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA})
  cal<-if(!is.na(r$abs_mdd)&&r$abs_mdd<0) r$abs_cagr/abs(r$abs_mdd) else NA
  data.table(method=lab, pt_capwt=r$portfolio_alpha_t_nw_lag3, oos_reten=median(rets,na.rm=TRUE),
    calmar=cal, IR=r$information_ratio, abs_mdd=r$abs_mdd, TO=r$turnover_annual)
}
methods<-c("EW","SCORE","INVVOL","SCORE_INVVOL")
R<-list()
for(m in methods){ pg("method %s start\n",m); W<-mk_w(m,25L); pg("  %s weights %d rows\n",m,nrow(W)); R[[m]]<-gates(W,paste0(m,"_top25")); pg("  %s gates done\n",m) }
pg("top40 start\n"); R[["EW_top40"]]<-gates(mk_w("EW",40L),"EW_top40")
R[["INVVOL_top40"]]<-gates(mk_w("INVVOL",40L),"INVVOL_top40"); pg("all done\n")
RES<-rbindlist(Filter(Negate(is.null),R),fill=TRUE)

w("=== 종목 비중법 비교 (IC-가중 M_regdd score, cap-w, book ref: pt 2.95/oos 0.7/cal 0.64) ===")
w(sprintf("  %-16s %8s %9s %7s %6s %7s %6s","method","pt_capwt","oos_reten","calmar","IR","MDD","TO"))
for(i in seq_len(nrow(RES)))w(sprintf("  %-16s %+8.2f %+9.2f %+7.2f %+6.2f %+7.2f %6.1f",
  RES$method[i],RES$pt_capwt[i],RES$oos_reten[i],RES$calmar[i],RES$IR[i],RES$abs_mdd[i],RES$TO[i]))
w("\n게이트 통과(HARD pt≥2.95∧oos≥0.7∧cal≥0.64):")
for(i in seq_len(nrow(RES))){r<-RES[i];p<-c(isTRUE(r$pt_capwt>=2.95),isTRUE(r$oos_reten>=0.7),isTRUE(r$calmar>=0.64))
  w(sprintf("  %-16s pt %s oos %s cal %s → %s",r$method,ifelse(p[1],"✓","✗"),ifelse(p[2],"✓","✗"),ifelse(p[3],"✓","✗"),ifelse(all(p),"★GRAD","미달")))}
saveRDS(RES,".cache/_ramp_weighting.rds"); close(con); cat("WEIGHTING_DONE\n")
