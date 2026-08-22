## probe_a5_longwin.R — 프로브 3단: 창 확장 (2011-08~2026-07, 180개월)
## 이유: 2단에서 5년 창의 cap-w 벤치 +19.8%/yr vs EW-유니버스 +5.0%/yr (cap-tier 스프레드
##       14.8%p/yr) = 극단적 mega-cap 창. EW 팔의 음수 부호가 창 아티팩트인지 분리 필요.
## 자유도 통제: 팔 정의·규칙은 1·2단과 **동일**(사후 변경 없음). 창만 확장 + 시대 분해 병기.
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM); setDTthreads(4)
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
suppressMessages({library(sandwich); library(lmtest)})
OUT <- file.path(QM,"stage_artifacts/probe_a5_20260822")
nwt <- function(x){x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3])}
IRf <- function(x){x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); mean(x)/sd(x)*sqrt(12)}
FAC <- c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
         Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
         Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
         Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets",
         LowVol="D03_RealVol", LowBeta="D02_Beta", TailRisk="R05_Tail_Risk",
         Liquidity="L45_Composite_Liquidity", Accrual="AC18_Accrual_Quality",
         Consensus="C19_Composite_Earnings", SUE="C01_SUE", Crowding="CR07_Momentum_Crowding",
         ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")
facn <- names(FAC)
WIN_F <- "2011-08"; WIN_L <- "2026-07"; RAW_FROM <- "2011-01-01"

## 1) A5 지수레벨 (위상 보존 — 전 구간)
R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market")); R[,ym:=format(Date,"%Y-%m")]
mon <- R[, c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1), .(medate=max(Date))),
         by=ym, .SDcols=c("Market",fac)]
setorder(mon,medate); NM<-nrow(mon); NAx<-1+length(fac)
S <- matrix(NA_real_,NM,length(fac)); colnames(S)<-fac
for(fi in seq_along(fac)) for(m in 12:NM){ w<-(m-11):m
  S[m,fi] <- prod(1+mon[[fac[fi]]][w])/prod(1+mon$Market[w])-1 }
Wapp <- matrix(NA_real_,NM,NAx); colnames(Wapp)<-c("Market",fac)
isdec <- rep(FALSE,NM); pr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM)
wprev<-rep(1/NAx,NAx); wcur<-NULL
for(m in 13:NM){ d<-m-1
  if(is.null(wcur) || ((m-13)%%3==0)){ s<-S[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
    if(length(pos)==0) w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); wcur<-w; isdec[m]<-TRUE }
  Wapp[m,]<-wcur
  ri<-unlist(mon[m,c("Market",fac),with=FALSE]); ri[!is.finite(ri)]<-0
  dlt<-sum(abs(wcur-wprev)); tov[m]<-dlt; pr[m]<-sum(wcur*ri)-0.0015*dlt
  wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev }

## 2) 데이터
RAWD <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAWD[,Date:=as.Date(Date)]
RAWD <- RAWD[Date>=as.Date(RAW_FROM) & Date<=as.Date("2026-07-31")]
alld<-sort(unique(RAWD$Date)); rym<-format(alld,"%Y-%m"); ME_all<-alld[!duplicated(rym,fromLast=TRUE)]
ME <- ME_all[format(ME_all,"%Y-%m") >= format(as.Date(paste0(WIN_F,"-01"))-1, "%Y-%m") &
             format(ME_all,"%Y-%m") <= WIN_L]
ADV20 <- build_adv20_t1(RAWD[,.(Date,Ticker,Vol,Close)], at_dates=ME)
RAWME <- RAWD[Date %in% ME]; rm(RAWD); invisible(gc())
fwd <- build_monthly_forward_returns(RAWME, ME, liq_daily=ADV20)
RET <- fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)]
BEN <- fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)]
LIQ <- fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
DEC <- data.table(d0=ME[-length(ME)]); DEC[,fwd_ym:=format(ME[-1],"%Y-%m")]
DEC <- DEC[fwd_ym>=WIN_F & fwd_ym<=WIN_L]; DEC[,mrow:=match(fwd_ym,mon$ym)]
DEC[,is_dec:=isdec[mrow]]
cat(sprintf("[long] 결정일 %d개 (%s ~ %s)\n", nrow(DEC), as.character(min(DEC$d0)), as.character(max(DEC$d0))))

## 3) Z 패널 (증분 캐시)
ZC <- file.path(OUT,"_zpanel_long.rds")
ZP <- if(file.exists(ZC)) readRDS(ZC) else
      if(file.exists(file.path(OUT,"_zpanel.rds"))) readRDS(file.path(OUT,"_zpanel.rds")) else list()
miss <- setdiff(as.character(DEC$d0), names(ZP))
cat(sprintf("[long] Z 패널 캐시 %d / 신규 %d\n", length(ZP), length(miss)))
if(length(miss)){ for(k in seq_along(miss)){ d0<-as.Date(miss[k])
  uni <- RAWME[Date==d0 & ((!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)) & is.finite(Size)&Size>0,
               .(Ticker, cap=Size)]
  if(!nrow(uni)) next
  f0 <- tryCatch(load_month_factors(d0, factor_names=unname(FAC)), error=function(e) NULL)
  if(is.null(f0)||!nrow(f0)) next
  ZP[[miss[k]]] <- list(f=merge(as.data.table(f0),uni,by="Ticker"), uni=uni,
                        asof=attr(f0,"factor_db_asof_date",exact=TRUE))
  if(k%%20==0) cat(sprintf("    +%d/%d (%s)\n",k,length(miss),miss[k])) }
  saveRDS(ZP, ZC) }

## 4) 스코어 (1·2단과 동일 규칙)
mk <- function(mode, wsrc){ rows<-vector("list",nrow(DEC))
  for(i in seq_len(nrow(DEC))){ d0<-DEC$d0[i]; z<-ZP[[as.character(d0)]]; if(is.null(z)) next
    wv <- if(identical(wsrc,"EW")) setNames(rep(1/length(facn),length(facn)),facn)
          else setNames(Wapp[DEC$mrow[i],-1],facn)
    if(sum(wv)<=1e-12) next
    f<-z$f; tk<-z$uni$Ticker; capv<-setNames(z$uni$cap,z$uni$Ticker)
    sc<-setNames(rep(0,length(tk)),tk); hit<-setNames(rep(0,length(tk)),tk)
    for(nm in facn){ wf<-wv[[nm]]; if(!is.finite(wf)||wf<=0) next
      sub<-f[Factor_Name==FAC[[nm]] & is.finite(Z_Score_Aligned)]; if(nrow(sub)<15) next
      if(mode=="B1"){ v<-setNames(sub$Z_Score_Aligned,sub$Ticker)
        sc[names(v)]<-sc[names(v)]+wf*v; hit[names(v)]<-hit[names(v)]+wf
      } else { thr<-quantile(sub$Z_Score_Aligned,2/3,na.rm=TRUE); H<-sub[Z_Score_Aligned>=thr,Ticker]
        if(!length(H)) next; cw<-capv[H]; sc[H]<-sc[H]+wf*cw/sum(cw); hit[H]<-hit[H]+wf } }
    keep<-hit>0; if(!any(keep)) next
    rows[[i]]<-data.table(Date=d0,Ticker=names(sc)[keep],score=as.numeric(sc[keep]),
                          cap=as.numeric(capv[names(sc)[keep]])) }
  rbindlist(rows) }
SB1<-mk("B1","A5"); SB3<-mk("B3","A5"); SE3<-mk("B3","EW"); SC0<-mk("B1","EW")
CAPALL <- rbindlist(lapply(seq_len(nrow(DEC)),function(i){d0<-DEC$d0[i];z<-ZP[[as.character(d0)]]
  if(is.null(z)) return(NULL); data.table(Date=d0,Ticker=z$uni$Ticker,score=z$uni$cap,cap=z$uni$cap)}))
capw<-function(v,cap=0.20){w<-v/sum(v); for(k in 1:200){ if(max(w)<=cap+1e-12) break
  ex<-pmax(w-cap,0); w<-pmin(w,cap); w<-w+sum(ex)*w/sum(w)}; w/sum(w)}
build_w<-function(S,wmode){ s<-merge(S[is.finite(score)&score>0],LIQ,by=c("Date","Ticker"),all.x=TRUE)
  s<-s[is.na(adv)|adv>=2e8]; setorder(s,Date,-score); s<-s[,head(.SD,25L),by=Date]
  s[,w:=switch(wmode, EW=rep(1/.N,.N), CAP=capw(cap), PI=capw(score)),by=Date]; s }
ARMS<-list(E1_capw_passive=list(S=CAPALL,wm="CAP"), E2_B1sel_capw=list(S=SB1,wm="CAP"),
           E3_piEW_ctrl=list(S=SE3,wm="PI"), B3w_A5=list(S=SB3,wm="PI"),
           B3_EW=list(S=SB3,wm="EW"), B1_EW=list(S=SB1,wm="EW"), C0_EW=list(S=SC0,wm="EW"))
UNIV<-rbindlist(lapply(seq_len(nrow(DEC)),function(i){d0<-DEC$d0[i];z<-ZP[[as.character(d0)]]
  if(is.null(z)) return(NULL); data.table(Date=d0,Ticker=z$uni$Ticker)}))
EWB<-merge(UNIV,RET,by=c("Date","Ticker"))[,.(EW_Ret=mean(Ret_1m)),by=Date]
PRL<-list()
res<-rbindlist(lapply(names(ARMS),function(nm){ a<-ARMS[[nm]]; W<-build_w(a$S,a$wm)
  ws<-weighted_screen_bt(W[,.(Date,Ticker,w)],RET,BEN,cost_bps_oneway=15,
      run_id=paste0("p3_",tolower(nm)),strategy_id=paste0("P3_",nm))
  p<-as.data.table(ws$period_returns); PRL[[nm]]<<-p; act<-p$ret_net-p$benchmark_ret
  pe<-merge(p,EWB,by.x="date",by.y="Date"); acte<-pe$ret_net-pe$EW_Ret
  conc<-W[,.(top1=max(w),eff_n=1/sum(w^2)),by=Date]
  yy<-format(p$date,"%Y")
  data.table(arm=nm,n=ws$n_months,PORT_t=ws$portfolio_alpha_t_nw_lag3,IR=ws$information_ratio,
    active_ann=100*mean(act)*12, netSR=IRf(p$ret_net), TO=ws$turnover_annual,
    ewuni_t=nwt(acte), ewuni_active_ann=100*mean(acte)*12,
    t_pre2017=nwt(act[yy<"2017"]), t_post2017=nwt(act[yy>="2017"]),
    top1_w=mean(conc$top1), eff_n=mean(conc$eff_n)) }))
cat(sprintf("\n== 프로브 3단 창 확장 (%s~%s, %d개월, top-25 long-only, 15bps, adv20>=2e8) ==\n",
  WIN_F,WIN_L,nrow(BEN[Date %in% DEC$d0])))
print(res,digits=3)
kw <- mon$ym>=WIN_F & mon$ym<=WIN_L & is.finite(pr)
a5act <- pr[kw]-mon$Market[kw]
cat(sprintf("\n[기준] 창-정합 지수레벨 A5: PORT_t=%+.3f IR=%+.3f 연평균active=%+.2f%%p TO=%.2f (n=%d)\n",
  nwt(a5act), IRf(a5act), 100*mean(a5act)*12, mean(tov[kw],na.rm=TRUE)*12, sum(kw)))
mk2<-BEN[Date %in% DEC$d0]
cat(sprintf("[기준] cap-w 벤치 연평균 %+.2f%% | EW-유니버스 연평균 %+.2f%%\n",
  100*mean(mk2$BM_Ret)*12, 100*mean(EWB$EW_Ret)*12))
p1<-PRL[["B3w_A5"]]; p2<-PRL[["E3_piEW_ctrl"]]; p3<-PRL[["E1_capw_passive"]]
m1<-merge(p1[,.(date,a=ret_net)],p2[,.(date,c=ret_net)],by="date")
m2<-merge(p1[,.(date,a=ret_net)],p3[,.(date,p=ret_net)],by="date")
cat(sprintf("[paired NW-t] B3w_A5 − E3(w_f=1/21) = %+.3f (Δ연평균 %+.2f%%p)\n",nwt(m1$a-m1$c),100*mean(m1$a-m1$c)*12))
cat(sprintf("[paired NW-t] B3w_A5 − E1(패시브)   = %+.3f (Δ연평균 %+.2f%%p)\n",nwt(m2$a-m2$p),100*mean(m2$a-m2$p)*12))
fwrite(res, file.path(OUT,"probe_a5_longwin_results.csv"))
saveRDS(list(res=res,PRL=PRL,EWB=EWB,DEC=DEC), file.path(OUT,"probe_a5_longwin.rds"))
cat("\nPROBE_A5_LONG_DONE\n")
