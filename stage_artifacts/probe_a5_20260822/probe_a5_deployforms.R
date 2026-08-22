## probe_a5_deployforms.R — 프로브 5단: 배포 후보 형태 3종 + 회전율 완충
## 4단 결론(형태별 신호 잔존): Z-합성은 A5 배분신호를 보존(paired +1.23~+1.43)하나 구조를 잃고,
##   내재비중 pi 는 구조를 보존(패리티 cor 1.0000)하나 신호를 잃는다(paired -0.02).
## → 배포 후보 = "Z-합성 선택 × cap-비례 가중"(구조+신호) + 회전율 완충.
## 자유도: 완충 밴드(hold-if-in-top-K)는 신규 1개. 사전등록 대상으로 명시.
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM); setDTthreads(4)
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
suppressMessages({library(sandwich);library(lmtest)})
OUT<-file.path(QM,"stage_artifacts/probe_a5_20260822")
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA_real_)
  m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA_real_);mean(x)/sd(x)*sqrt(12)}
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
mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),by=ym,
       .SDcols=c("Market",fac)]
setorder(mon,medate);NM<-nrow(mon);NAx<-1+length(fac)
S<-matrix(NA_real_,NM,length(fac));colnames(S)<-fac
for(fi in seq_along(fac)) for(m in 12:NM){w<-(m-11):m;S[m,fi]<-prod(1+mon[[fac[fi]]][w])/prod(1+mon$Market[w])-1}
Wapp<-matrix(NA_real_,NM,NAx);colnames(Wapp)<-c("Market",fac);wprev<-rep(1/NAx,NAx);wcur<-NULL
prI<-rep(NA_real_,NM);tov<-rep(NA_real_,NM)
for(m in 13:NM){d<-m-1
  if(is.null(wcur)||((m-13)%%3==0)){s<-S[d,];pos<-which(is.finite(s)&s>0);w<-rep(0,NAx)
    if(length(pos)==0)w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]);wcur<-w}
  Wapp[m,]<-wcur;ri<-unlist(mon[m,c("Market",fac),with=FALSE]);ri[!is.finite(ri)]<-0
  dlt<-sum(abs(wcur-wprev));tov[m]<-dlt;prI[m]<-sum(wcur*ri)-0.0015*dlt
  wd<-wcur*(1+ri);wprev<-wd/sum(wd);wcur<-wprev}
RAWD<-as.data.table(read_parquet(".cache/rawdata.parquet",
      col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAWD[,Date:=as.Date(Date)];RAWD<-RAWD[Date>=as.Date("2011-01-01")&Date<=as.Date("2026-07-31")]
alld<-sort(unique(RAWD$Date));rym<-format(alld,"%Y-%m");ME_all<-alld[!duplicated(rym,fromLast=TRUE)]
ME<-ME_all[format(ME_all,"%Y-%m")>="2011-07"&format(ME_all,"%Y-%m")<="2026-07"]
ADV20<-build_adv20_t1(RAWD[,.(Date,Ticker,Vol,Close)],at_dates=ME)
RAWME<-RAWD[Date %in% ME];rm(RAWD);invisible(gc())
fwd<-build_monthly_forward_returns(RAWME,ME,liq_daily=ADV20)
RET<-fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)]
BEN<-fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)]
LIQ<-fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
mkz<-function(wsrc){rows<-vector("list",nrow(DEC))
  for(i in seq_len(nrow(DEC))){d0<-DEC$d0[i];z<-ZP[[as.character(d0)]];if(is.null(z))next
    wv<-if(identical(wsrc,"EW"))setNames(rep(1/length(facn),length(facn)),facn) else setNames(Wapp[DEC$mrow[i],-1],facn)
    if(sum(wv)<=1e-12)next
    f<-z$f;tk<-z$uni$Ticker;capv<-setNames(z$uni$cap,z$uni$Ticker)
    sc<-setNames(rep(0,length(tk)),tk);hit<-setNames(rep(0,length(tk)),tk)
    for(nm in facn){wf<-wv[[nm]];if(!is.finite(wf)||wf<=0)next
      sub<-f[Factor_Name==FAC[[nm]]&is.finite(Z_Score_Aligned)];if(nrow(sub)<15)next
      v<-setNames(sub$Z_Score_Aligned,sub$Ticker);sc[names(v)]<-sc[names(v)]+wf*v;hit[names(v)]<-hit[names(v)]+wf}
    keep<-hit>0;if(!any(keep))next
    rows[[i]]<-data.table(Date=d0,Ticker=names(sc)[keep],score=as.numeric(sc[keep]),
                          cap=as.numeric(capv[names(sc)[keep]]))}
  rbindlist(rows)}
ZA<-mkz("A5"); ZE<-mkz("EW")
capw<-function(v,cap=0.20){w<-v/sum(v);for(k in 1:200){if(max(w)<=cap+1e-12)break
  ex<-pmax(w-cap,0);w<-pmin(w,cap);w<-w+sum(ex)*w/sum(w)};w/sum(w)}

## 선택기: 월간 / 분기동결 / 완충밴드(보유는 top-K 안이면 유지)
select_names<-function(Z, mode, K=40L, N=25L){
  ZZ<-merge(Z,LIQ,by=c("Date","Ticker"),all.x=TRUE)[is.na(adv)|adv>=2e8]
  setorderv(ZZ,c("Date","score"),c(1L,-1L))
  dts<-sort(unique(ZZ$Date)); held<-character(0); out<-vector("list",length(dts))
  for(i in seq_along(dts)){ d<-dts[i]; sub<-ZZ[Date==d]
    isdec <- DEC$is_dec[match(d, DEC$d0)]
    if(mode=="monthly"){ sel<-sub$Ticker[seq_len(min(N,nrow(sub)))]
    } else if(mode=="quarterly"){
      if(isTRUE(isdec)||!length(held)) sel<-sub$Ticker[seq_len(min(N,nrow(sub)))]
      else sel<-intersect(held, sub$Ticker)
    } else { # buffer
      rk<-setNames(seq_len(nrow(sub)),sub$Ticker)
      keep<-held[held %in% names(rk)]; keep<-keep[rk[keep]<=K]
      if(length(keep)>N) keep<-keep[order(rk[keep])][seq_len(N)]
      add<-setdiff(sub$Ticker,keep); sel<-c(keep, add[seq_len(max(0,N-length(keep)))])
      sel<-sel[!is.na(sel)] }
    held<-sel
    out[[i]]<-sub[Ticker %in% sel] }
  rbindlist(out) }
runf<-function(Z,mode,wmode,id,K=40L){
  s<-select_names(Z,mode,K)
  s[,w:=if(wmode=="EW")rep(1/.N,.N) else if(wmode=="CAP")capw(cap) else capw(pmax(score,0)),by=Date]
  ws<-weighted_screen_bt(s[,.(Date,Ticker,w)],RET,BEN,cost_bps_oneway=15,run_id=id,strategy_id=toupper(id))
  p<-as.data.table(ws$period_returns);act<-p$ret_net-p$benchmark_ret;yy<-format(p$date,"%Y")
  list(p=p,row=data.table(arm=id,n=ws$n_months,PORT_t=ws$portfolio_alpha_t_nw_lag3,
    IR=ws$information_ratio,active_ann=100*mean(act)*12,netSR=IRf(p$ret_net),TO=ws$turnover_annual,
    t_pre2017=nwt(act[yy<"2017"]),t_post2017=nwt(act[yy>="2017"]),
    n_names=mean(s[,.N,by=Date]$N)))}
CFG<-list(
  D1_Zcap_monthly = list(Z=ZA,mode="monthly",  w="CAP"),
  D2_Zcap_quarter = list(Z=ZA,mode="quarterly",w="CAP"),
  D3_Zcap_buffer40= list(Z=ZA,mode="buffer",   w="CAP"),
  D4_Zew_buffer40 = list(Z=ZA,mode="buffer",   w="EW"),
  X1_ctrl_Zcap_buf= list(Z=ZE,mode="buffer",   w="CAP"))
RES<-list();ROW<-list()
for(nm in names(CFG)){c1<-CFG[[nm]];r<-runf(c1$Z,c1$mode,c1$w,nm);RES[[nm]]<-r$p;ROW[[nm]]<-r$row}
tab<-rbindlist(ROW)
cat("\n== 프로브 5단 배포 후보 (2011-08~2026-07, 180개월, 25종목 long-only, 0.20 cap, 15bps, adv20>=2e8) ==\n")
print(tab,digits=3)
kw<-mon$ym>="2011-08"&mon$ym<="2026-07"&is.finite(prI);ia<-prI[kw]-mon$Market[kw]
cat(sprintf("\n[기준] 지수레벨 A5: PORT_t=%+.3f IR=%+.3f active=%+.2f%%p/yr TO=%.2f(지수-간만 과금)\n",
  nwt(ia),IRf(ia),100*mean(ia)*12,mean(tov[kw],na.rm=TRUE)*12))
for(nm in c("D3_Zcap_buffer40")){ a<-RES[[nm]];b<-RES[["X1_ctrl_Zcap_buf"]]
  m<-merge(a[,.(date,x=ret_net)],b[,.(date,y=ret_net)],by="date")
  cat(sprintf("[paired NW-t] %s − X1(w_f=1/21 대조군) = %+.3f (Δ %+.2f%%p/yr)\n",
    nm,nwt(m$x-m$y),100*mean(m$x-m$y)*12)) }
cat("\n[비용 민감도 — D3]\n")
for(b in c(5,15,25,40)){ s<-select_names(ZA,"buffer",40L); s[,w:=capw(cap),by=Date]
  ws<-weighted_screen_bt(s[,.(Date,Ticker,w)],RET,BEN,cost_bps_oneway=b,run_id="p5c",strategy_id="P5C")
  p<-as.data.table(ws$period_returns);act<-p$ret_net-p$benchmark_ret
  cat(sprintf("  %2dbps: PORT_t=%+.3f active=%+.2f%%p/yr\n",b,ws$portfolio_alpha_t_nw_lag3,100*mean(act)*12)) }
fwrite(tab,file.path(OUT,"probe_a5_deployforms_results.csv"))
saveRDS(list(tab=tab,RES=RES),file.path(OUT,"probe_a5_deployforms.rds"))
cat("\nPROBE_A5_DEPLOY_DONE\n")
