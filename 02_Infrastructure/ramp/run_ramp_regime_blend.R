## run_ramp_regime_blend.R — 도훈 교정: 국면조건부 다차원 블렌딩 (동일가중/단일팩터 아님).
## OOS-probe는 *무조건부* OOS만 봤음 — Value는 평균 decay지 특정국면선 살아있음. 국면조건부 가중이 각 팩터를
## *작동 국면*에서 살림. 모멘텀(국면무관 robust) base + 나머지 국면조건부. vs 정적 Mom+0.4Cons(2.21/OOS+1.07)·RAMP_01(2.73/OOS~0).
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE); QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R"); suppressMessages({library(sandwich);library(lmtest)})
nwt<-function(x){x<-as.numeric(x);x<-x[is.finite(x)];if(length(x)<10)return(NA);tryCatch(as.numeric(coeftest(lm(x~1),vcov=sandwich::NeweyWest(lm(x~1),lag=3,prewhite=FALSE))[1,3]),error=function(e)mean(x)/sd(x)*sqrt(length(x)))}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
expz<-function(v){z<-rep(0,length(v));for(i in seq_along(v)){p<-v[1:i];p<-p[is.finite(p)];if(length(p)>=12){s<-sd(p);if(!is.na(s)&&s>1e-8)z[i]<-(v[i]-mean(p))/s}};z}
## 다차원 팩터셋: 10(기본) 또는 21(RAMP_02 breadth 계승). CONDWIN=국면조건부 추정 최근윈도(0=full).
FACSET<-Sys.getenv("SMV_FACSET","f10"); CONDWIN<-as.integer(Sys.getenv("SMV_CONDWIN","0"))
if(FACSET=="f21"){ FAC<-c(Mom="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal", Value="V12_Composite_Value", Quality="Q08_Composite_Quality",
  LowVol="D03_RealVol", LowBeta="D02_Beta", Size="S01_Size", Cons="C19_Composite_Earnings", SUE="C01_SUE", Growth="GR07_Composite_Growth",
  Issuance="V21_Composite_Equity_Issuance", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability", Investment="IN06_Investment_to_Assets",
  TailRisk="R05_Tail_Risk", Liquidity="L45_Composite_Liquidity", Accrual="AC18_Accrual_Quality", Crowding="CR07_Momentum_Crowding",
  ForeignFlow="INV01_Foreign_NetBuy_20d", IntMom="M10_Intermediate_Mom")
}else{ FAC<-c(Mom="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal", Value="V12_Composite_Value", Quality="Q08_Composite_Quality",
  LowVol="D03_RealVol", Size="S01_Size", Cons="C19_Composite_Earnings", SUE="C01_SUE", Growth="GR07_Composite_Growth") }
FN<-names(FAC)
L<-readRDS(".cache/_bo_fwdgic.rds");fwd_ret<-L$fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)];bench<-L$fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)];liq<-L$fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
fwd_dates<-sort(unique(fwd_ret$Date))
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","K200","KQ150")));rd[,Date:=as.Date(Date)];rd<-rd[Date%in%fwd_dates];rd[,inu:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)];UNI<-rd[inu==TRUE,.(Date,Ticker)]
ZL<-list();for(dk in as.character(fwd_dates)){d<-as.Date(dk);f<-tryCatch(as.data.table(load_month_factors(d,factor_names=unname(FAC))),error=function(e)NULL);if(is.null(f)||nrow(f)==0)next;ZL[[dk]]<-dcast(f,Ticker~Factor_Name,value.var="Z_Score_Aligned")}
cat(sprintf("z loaded %d months\n",length(ZL)))

## 각 팩터 월간 active 수익 (top-tercile EW − BM) — 국면조건부 가중 추정용
dts<-as.Date(names(ZL)); ND<-length(dts)
ACT<-matrix(NA_real_,ND,length(FN),dimnames=list(NULL,FN))
for(j in seq_along(FN)){id<-FAC[FN[j]]
  for(i in seq_len(ND)){dk<-names(ZL)[i];fw<-ZL[[dk]];if(!id%in%names(fw))next;sub<-data.table(Ticker=fw$Ticker,z=fw[[id]])[is.finite(z)]
    sub<-merge(sub,UNI[Date==dts[i]],by="Ticker");if(nrow(sub)<15)next;thr<-quantile(sub$z,2/3,na.rm=T);sel<-sub[z>=thr]$Ticker
    fr<-fwd_ret[Date==dts[i]&Ticker%in%sel,Ret_1m];br<-bench[Date==dts[i],BM_Ret];if(length(fr)>=5)ACT[i,j]<-mean(fr,na.rm=T)-ifelse(length(br),br,0)}}
cat("factor active built\n")

## 국면: Cascade(unified_regime_signal_daily) → 월말 soft 3-state membership
uni<-as.data.table(read_parquet(".cache/unified_regime_signal_daily.parquet"));uni[,Date:=as.Date(Date)];uni<-uni[!is.na(Date)];uni[,ym:=format(Date,"%Y-%m")]
um<-uni[,.(rs=last(Regime_Score_smooth)),by=ym];um[,ymd:=as.Date(paste0(ym,"-01"))]
RM<-data.table(ym=format(dts,"%Y-%m"));RM<-merge(RM,um[,.(ym,rs)],by="ym",all.x=TRUE);RM[,rsz:=expz(rs)];RM[is.na(rsz),rsz:=0]
anc<-c(-1,0,1);MEM<-t(sapply(RM$rsz,function(z){e<-exp(anc*z);e/sum(e)}))  # risk_on/neutral/crisis soft

## 국면조건부 팩터가중 w_f(t) = Σ_s mem_s(t)·max(trailing regime-s 평균active_f, 0), PIT (모멘텀 base floor)
Wmat<-matrix(0,ND,length(FN),dimnames=list(NULL,FN))
for(i in seq_len(ND)){ if(i<37){Wmat[i,]<-1;next}  # 초기 균등
  lo<-if(CONDWIN>0)max(1,i-CONDWIN) else 1   # 국면조건부 추정 윈도(최근 CONDWIN개월 or full)
  for(j in seq_along(FN)){ cps<-numeric(3)
    for(s in 1:3){ wts<-MEM[lo:(i-1),s];av<-ACT[lo:(i-1),j];ok<-is.finite(av)&is.finite(wts);if(sum(wts[ok])>1e-6)cps[s]<-sum(av[ok]*wts[ok])/sum(wts[ok]) else cps[s]<-0 }
    Wmat[i,j]<-sum(MEM[i,]*pmax(cps,0)) }
  if(all(Wmat[i,]<1e-9))Wmat[i,]<-1 }
MOMBASE<-Sys.getenv("SMV_MOMBASE","0.0"); mb<-as.numeric(MOMBASE)  # 모멘텀 base floor (robust 보장)
if(mb>0){Wmat[,"Mom"]<-Wmat[,"Mom"]+mb*apply(Wmat,1,function(r)max(sum(r),1e-9)); Wmat[,"ResidMom"]<-Wmat[,"ResidMom"]+0.5*mb*apply(Wmat,1,function(r)max(sum(r),1e-9))}

## 스코어 + top-25
run<-function(Wm,lab){rows<-list()
  for(i in seq_len(ND)){dk<-names(ZL)[i];fw<-ZL[[dk]];wf<-Wm[i,];if(sum(wf)<1e-9)wf<-rep(1,length(FN));wf<-wf/sum(wf)
    sc<-rep(0,nrow(fw));for(j in seq_along(FN)){id<-FAC[FN[j]];if(id%in%names(fw)){z<-zc(fw[[id]]);z[!is.finite(z)]<-0;sc<-sc+wf[j]*z}}
    rows[[dk]]<-data.table(Date=dts[i],Ticker=fw$Ticker,score=sc)}
  SC<-rbindlist(rows);SC<-merge(SC,UNI,by=c("Date","Ticker"))
  cs<-tryCatch(canonical_screen_bt(SC[,.(Date,Ticker,score)],fwd_ret,bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="rb",strategy_id=lab),error=function(e)NULL)
  if(is.null(cs$period_returns))return(NULL);pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr);k<-floor(n*0.6);nav<-cumprod(1+pr$ret_net);mdd<-min(nav/cummax(nav)-1);cagr<-prod(1+pr$ret_net)^(12/n)-1
  oret<-median(sapply(c(.55,.65,.75),function(fr){kk<-floor(n*fr);if(kk<12||(n-kk)<6)return(NA);is<-IRf(act[1:kk]);oo<-IRf(act[(kk+1):n]);if(!is.na(is)&&is>0)oo/is else NA}),na.rm=TRUE)
  data.table(strategy=lab,n=n,pt_full=nwt(act),pt_OOS=nwt(act[(k+1):n]),oos_ret=oret,calmar=cagr/abs(mdd),absSR=IRf(pr$ret_net),TO=cs$turnover_annual)}
# 정적 균등(참조) vs 국면조건부 vs 국면조건부+모멘텀base
Wstat<-matrix(1,ND,length(FN))
R<-rbindlist(Filter(Negate(is.null),list(
  run(Wstat,"static_equal(10팩터)"),
  run(Wmat,sprintf("regime_blend(mombase=%.1f)",mb))
)),fill=TRUE);setorder(R,-pt_full)
cat(sprintf("\n=== 국면조건부 블렌딩 (FACSET=%s CONDWIN=%d mombase=%.1f) — gate pt2.95·oos_ret0.7(밴드0.5)·cal0.64 ===\n",FACSET,CONDWIN,mb))
cat(sprintf("  %-26s %4s %8s %8s %8s %7s %6s %5s\n","strategy","n","pt_full","pt_OOS","oos_ret","calmar","absSR","TO"))
for(i in seq_len(nrow(R))){r<-R[i];cat(sprintf("  %-26s %4d %8.2f %8.2f %8.2f %7.2f %6.2f %5.1f [pt%s oos%s cal%s]\n",r$strategy,r$n,r$pt_full,r$pt_OOS,r$oos_ret,r$calmar,r$absSR,r$TO,ifelse(r$pt_full>=2.95,"P","F"),ifelse(!is.na(r$oos_ret)&&r$oos_ret>=0.7,"P",ifelse(!is.na(r$oos_ret)&&r$oos_ret>=0.5,"o","F")),ifelse(r$calmar>=0.64,"P","F")))}
# 최근 국면별 평균 팩터가중 (해석)
cat("\n최근(마지막 60m) 평균 국면조건부 팩터가중(정규화):\n");wl<-colMeans(Wmat[(ND-59):ND,]);wl<-wl/sum(wl);for(j in seq_along(FN))cat(sprintf("  %-10s %.3f\n",FN[j],wl[j]))
saveRDS(list(R=R,Wmat=Wmat),".cache/_regime_blend.rds");cat("RBLEND_DONE\n")
