## run_ramp_shumulvey_stock25x.R — RAMP_02 25종목 변환 *접근 탐색* (도훈 25종목 + Ultracode 병렬).
## naive(전체시장·EW) pt -3 실패 → 변환 레버: SMV_UNIV(all|index) × SMV_WEIGHT(ew|cap) × SMV_TESTFROM.
## env: SMV_KEY / SMV_UNIV / SMV_WEIGHT / SMV_TESTFROM / SMV_XKEY. JSON 출력(collision-free).
suppressPackageStartupMessages({library(data.table); library(arrow); library(quadprog); library(jsonlite)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE); QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R"); source("02_Infrastructure/contracts/weighted_screen_bt.R"); suppressMessages({library(sandwich);library(lmtest)})
KEY<-Sys.getenv("SMV_KEY","broad_m5_roll"); UNIV<-Sys.getenv("SMV_UNIV","index"); WEIGHT<-Sys.getenv("SMV_WEIGHT","cap")
TESTFROM<-Sys.getenv("SMV_TESTFROM","2009-01-01"); XKEY<-Sys.getenv("SMV_XKEY","x"); PER<-252
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
oos_ret<-function(act){n<-length(act);md<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA});median(md,na.rm=TRUE)}
FACMAP<-c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size", Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
  Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability", Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets",
  LowVol="D03_RealVol", LowBeta="D02_Beta", TailRisk="R05_Tail_Risk", Liquidity="L45_Composite_Liquidity", Accrual="AC18_Accrual_Quality",
  Consensus="C19_Composite_Earnings", SUE="C01_SUE", Crowding="CR07_Momentum_Crowding", ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")

## BL W 재구성 (v4 regime)
G<-readRDS(sprintf(".cache/_smv4_regime_%s.rds",KEY)); view<-G$view; medates<-G$medates; meix<-G$meix; FACN<-G$FACN; N<-length(FACN)
R<-as.data.table(read_parquet(G$idxfile));R[,Date:=as.Date(Date)];setorder(R,Date);IDX<-c("Market",FACN)
for(c in IDX)R[[c]][!is.finite(R[[c]])]<-NA;R<-R[is.finite(Market)]
RmatAll<-as.matrix(R[,..IDX]);RmatAll[!is.finite(RmatAll)]<-0;a126<-1-exp(log(0.5)/126);Sacc<-matrix(0,N+1,N+1);Sig_list<-vector("list",length(medates));.mi<-1L
for(t in 1:nrow(RmatAll)){x<-RmatAll[t,];Sacc<-a126*tcrossprod(x)+(1-a126)*Sacc;if(.mi<=length(meix)&&t==meix[.mi]){if(t>=130)Sig_list[[.mi]]<-Sacc*PER;.mi<-.mi+1L}}
delta<-2.5;w_ew<-rep(1/(N+1),N+1);Pf<-matrix(0,N,N+1);for(j in 1:N)Pf[j,1+j]<-1;Pf[,1]<- -1;VIEW0<-as.matrix(view[,..FACN])
solveMVO<-function(muv,Sig){D<-delta*Sig+diag(1e-5,N+1);A<-cbind(rep(1,N+1),diag(N+1));b0<-c(1,rep(0,N+1));r<-tryCatch(solve.QP(D,muv,A,b0,meq=1),error=function(e)NULL);if(is.null(r))return(w_ew);ww<-pmax(r$solution,0);if(sum(ww)<1e-9)return(w_ew);ww/sum(ww)}
build_W<-function(cc){Wt<-matrix(NA_real_,length(medates),N+1);for(mi in seq_along(medates)){Sig<-Sig_list[[mi]];if(is.null(Sig))next;vv<-VIEW0[mi,];av<-which(is.finite(vv));if(length(av)<2){Wt[mi,]<-w_ew;next}
  Pa<-Pf[av,,drop=FALSE];va<-vv[av];pri<-delta*as.numeric(Sig%*%w_ew);M<-Pa%*%Sig%*%t(Pa);Om<-cc*diag(diag(M),length(av));muBL<-pri+as.numeric(Sig%*%t(Pa)%*%solve(M+Om,(va-as.numeric(Pa%*%pri))));Wt[mi,]<-solveMVO(muBL,Sig)};Wt}
calib_c<-function(target){lo<-1e-3;hi<-50;for(b in 1:20){mid<-sqrt(lo*hi);W<-build_W(mid);tev<-c();for(mi in seq_along(medates)){Sig<-Sig_list[[mi]];if(is.null(Sig)||any(!is.finite(W[mi,])))next;tev<-c(tev,sqrt(as.numeric(t(W[mi,]-w_ew)%*%Sig%*%(W[mi,]-w_ew))))};mte<-mean(tev,na.rm=TRUE);if(!is.finite(mte)){hi<-mid;next};if(mte>target)lo<-mid else hi<-mid};sqrt(lo*hi)}
cc<-calib_c(0.03); W<-build_W(cc)

## fwd + universe/cap (rawdata 월말 K200∪KQ150 + Size)
L<-readRDS(".cache/_bo_fwdgic.rds");fwd_ret<-L$fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)];bench<-L$fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)];liq<-L$fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
fwd_dates<-sort(unique(fwd_ret$Date));fwd_ym<-data.table(Date=fwd_dates,ym=format(fwd_dates,"%Y-%m"))
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","K200","KQ150","Size")));rd[,Date:=as.Date(Date)]
rd<-rd[Date%in%fwd_dates];rd[,inuniv:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)];UNI<-rd[,.(Date,Ticker,inuniv,Size)]

## 종목 스코어 (정규화 팩터비중 × z)
scores<-list()
for(mi in seq_along(medates)){md<-medates[mi];wf<-W[mi,2:(N+1)];if(any(!is.finite(wf)))next;sw<-sum(wf);wfn<-if(sw<1e-9)rep(1/N,N) else wf/sw
  ids<-unname(FACMAP[FACN]);f<-tryCatch(as.data.table(load_month_factors(md,factor_names=ids)),error=function(e)NULL);if(is.null(f)||nrow(f)==0)next
  fw<-dcast(f,Ticker~Factor_Name,value.var="Z_Score_Aligned");sc<-rep(0,nrow(fw));for(k in seq_len(N)){col<-FACMAP[FACN[k]];if(col%in%names(fw)){z<-fw[[col]];z[!is.finite(z)]<-0;sc<-sc+wfn[k]*z}}
  fd<-fwd_ym[ym==format(md,"%Y-%m")]$Date;if(length(fd)==0)next;scores[[as.character(md)]]<-data.table(Date=fd[1],Ticker=fw$Ticker,score=sc)}
SC<-rbindlist(scores);SC<-SC[Date>=as.Date(TESTFROM)]
## 유니버스 필터
SC<-merge(SC,UNI,by=c("Date","Ticker"),all.x=TRUE)
if(UNIV=="index")SC<-SC[inuniv==TRUE]

## 측정: EW=canonical / cap=weighted
if(WEIGHT=="ew"){
  cs<-canonical_screen_bt(SC[,.(Date,Ticker,score)],fwd_ret,bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="x",strategy_id=XKEY)
  pr<-as.data.table(cs$period_returns);TO<-cs$turnover_annual
}else{ # cap-weighted top-25 (유동성 필터 후 score 상위25, Size 비중, [0,0.20] 캡)
  S2<-merge(SC,liq,by=c("Date","Ticker"),all.x=TRUE)[is.na(adv)|adv>=2e8]
  W25<-S2[order(Date,-score),head(.SD,25),by=Date]
  W25[,w:=Size/sum(Size),by=Date];W25[w>0.20,w:=0.20];W25[,w:=w/sum(w),by=Date]
  r<-weighted_screen_bt(W25[,.(Date,Ticker,w)],fwd_ret,bench,cost_bps_oneway=15,run_id="x",strategy_id=XKEY)
  pr<-as.data.table(r$period_returns);TO<-r$turnover_annual
}
setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr);nav<-cumprod(1+pr$ret_net);mdd<-min(nav/cummax(nav)-1);cagr<-prod(1+pr$ret_net)^(12/n)-1;cal<-cagr/abs(mdd)
res<-list(xkey=XKEY,key=KEY,univ=UNIV,weight=WEIGHT,testfrom=TESTFROM,n_mo=n,test_start=as.character(min(pr$date)),
  pt=round(nwt(act),2),IR=round(IRf(act),2),calmar=round(cal,2),oos=round(oos_ret(act),2),absSR=round(IRf(pr$ret_net),2),TO=round(TO,1))
cat(sprintf("=== 25stock-x [%s] univ=%s weight=%s from=%s ===\n",XKEY,UNIV,WEIGHT,TESTFROM))
cat(sprintf("  n=%d test=%s pt=%.2f IR=%.2f calmar=%.2f oos=%.2f absSR=%.2f TO=%.1f [pt%s cal%s oos%s]\n",
  n,res$test_start,res$pt,res$IR,res$calmar,res$oos,res$absSR,res$TO,ifelse(res$pt>=2.95,"P","F"),ifelse(res$calmar>=0.64,"P","F"),ifelse(!is.na(res$oos)&&res$oos>=0.7,"P",ifelse(!is.na(res$oos)&&res$oos>=0.5,"o","F"))))
write_json(res,sprintf(".cache/_smv25x_%s.json",XKEY),auto_unbox=TRUE)
cat(sprintf("X25_DONE %s\n",XKEY))
