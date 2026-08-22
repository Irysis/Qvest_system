## probe_a5_dofcheck.R — 3단(longwin) E2 8.79 vs 4/5단 8.19 불일치의 원인 특정
## 가설: longwin build_w 의 `score>0` 선-필터 (미선언 자유도). 월별 양수 스코어 개수로 검증.
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM); setDTthreads(4)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
OUT<-file.path(QM,"stage_artifacts/probe_a5_20260822")
L<-readRDS(file.path(OUT,"probe_a5_longwin.rds")); DEC<-L$DEC
ZP<-readRDS(file.path(OUT,"_zpanel_long.rds"))
FAC <- c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
  Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
  Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
  Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets",
  LowVol="D03_RealVol", LowBeta="D02_Beta", TailRisk="R05_Tail_Risk",
  Liquidity="L45_Composite_Liquidity", Accrual="AC18_Accrual_Quality",
  Consensus="C19_Composite_Earnings", SUE="C01_SUE", Crowding="CR07_Momentum_Crowding",
  ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")
facn<-names(FAC)
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)];setorder(R,Date);R<-R[is.finite(Market)]
fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market"));R[,ym:=format(Date,"%Y-%m")]
mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),by=ym,.SDcols=c("Market",fac)]
setorder(mon,medate);NM<-nrow(mon);NAx<-1+length(fac)
S<-matrix(NA_real_,NM,length(fac));colnames(S)<-fac
for(fi in seq_along(fac)) for(m in 12:NM){w<-(m-11):m;S[m,fi]<-prod(1+mon[[fac[fi]]][w])/prod(1+mon$Market[w])-1}
Wapp<-matrix(NA_real_,NM,NAx);colnames(Wapp)<-c("Market",fac);wprev<-rep(1/NAx,NAx);wcur<-NULL
for(m in 13:NM){d<-m-1
  if(is.null(wcur)||((m-13)%%3==0)){s<-S[d,];pos<-which(is.finite(s)&s>0);w<-rep(0,NAx)
    if(length(pos)==0)w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]);wcur<-w}
  Wapp[m,]<-wcur;ri<-unlist(mon[m,c("Market",fac),with=FALSE]);ri[!is.finite(ri)]<-0
  wd<-wcur*(1+ri);wprev<-wd/sum(wd);wcur<-wprev}
mkz<-function(){rows<-vector("list",nrow(DEC))
  for(i in seq_len(nrow(DEC))){d0<-DEC$d0[i];z<-ZP[[as.character(d0)]];if(is.null(z))next
    wv<-setNames(Wapp[DEC$mrow[i],-1],facn); if(sum(wv)<=1e-12)next
    f<-z$f;tk<-z$uni$Ticker;capv<-setNames(z$uni$cap,z$uni$Ticker)
    sc<-setNames(rep(0,length(tk)),tk);hit<-setNames(rep(0,length(tk)),tk)
    for(nm in facn){wf<-wv[[nm]];if(!is.finite(wf)||wf<=0)next
      sub<-f[Factor_Name==FAC[[nm]]&is.finite(Z_Score_Aligned)];if(nrow(sub)<15)next
      v<-setNames(sub$Z_Score_Aligned,sub$Ticker);sc[names(v)]<-sc[names(v)]+wf*v;hit[names(v)]<-hit[names(v)]+wf}
    keep<-hit>0;if(!any(keep))next
    rows[[i]]<-data.table(Date=d0,Ticker=names(sc)[keep],score=as.numeric(sc[keep]),cap=as.numeric(capv[names(sc)[keep]]))}
  rbindlist(rows)}
ZA<-mkz()
RAWD<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAWD[,Date:=as.Date(Date)];RAWD<-RAWD[Date>=as.Date("2011-01-01")&Date<=as.Date("2026-07-31")]
alld<-sort(unique(RAWD$Date));rym<-format(alld,"%Y-%m");ME_all<-alld[!duplicated(rym,fromLast=TRUE)]
ME<-ME_all[format(ME_all,"%Y-%m")>="2011-07"&format(ME_all,"%Y-%m")<="2026-07"]
ADV20<-build_adv20_t1(RAWD[,.(Date,Ticker,Vol,Close)],at_dates=ME)
RAWME<-RAWD[Date %in% ME];rm(RAWD);invisible(gc())
fwd<-build_monthly_forward_returns(RAWME,ME,liq_daily=ADV20)
RET<-fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)];BEN<-fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)]
LIQ<-fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
Z<-merge(ZA,LIQ,by=c("Date","Ticker"),all.x=TRUE)[is.na(adv)|adv>=2e8]
cnt<-Z[,.(n_all=.N,n_pos=sum(score>0)),by=Date]
cat(sprintf("[dof] 유동성 통과 종목수 중앙 %.0f | 양수 스코어 수 중앙 %.0f | 양수<25 인 달 = %d / %d\n",
  median(cnt$n_all),median(cnt$n_pos),sum(cnt$n_pos<25),nrow(cnt)))
capw<-function(v,cap=0.20){w<-v/sum(v);for(k in 1:200){if(max(w)<=cap+1e-12)break
  ex<-pmax(w-cap,0);w<-pmin(w,cap);w<-w+sum(ex)*w/sum(w)};w/sum(w)}
run<-function(posfilter){ s<-copy(Z); if(posfilter) s<-s[score>0]
  setorderv(s,c("Date","score"),c(1L,-1L)); s<-s[,head(.SD,25L),by=Date]
  s[,w:=capw(cap),by=Date]
  ws<-weighted_screen_bt(s[,.(Date,Ticker,w)],RET,BEN,cost_bps_oneway=15,run_id="dof",strategy_id="DOF")
  p<-as.data.table(ws$period_returns);a<-p$ret_net-p$benchmark_ret
  c(t=ws$portfolio_alpha_t_nw_lag3, act=100*mean(a)*12, TO=ws$turnover_annual, n=mean(s[,.N,by=Date]$N)) }
a<-run(TRUE); b<-run(FALSE)
cat(sprintf("[dof] score>0 선필터 O: PORT_t=%.3f active=%.2f%%p TO=%.2f 평균종목=%.2f\n",a[1],a[2],a[3],a[4]))
cat(sprintf("[dof] score>0 선필터 X: PORT_t=%.3f active=%.2f%%p TO=%.2f 평균종목=%.2f\n",b[1],b[2],b[3],b[4]))
cat("DOFCHECK_DONE\n")
