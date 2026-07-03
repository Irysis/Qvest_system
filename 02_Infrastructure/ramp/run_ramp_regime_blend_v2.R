## run_ramp_regime_blend_v2.R — 국면조건부 블렌딩 강화: ②FWL중립화 + ①2D국면 + ③shrinkage.
## 데이터 1회 로드 → {raw,FWL} z × {1D Cascade, 2D 시장×변동성} × {shrink} 내부 매트릭스. 각 레버 기여 분리.
## 모두 K200∪KQ150 top-25 EW 15bps canonical 실측. vs 기준 regime_blend(Cascade·raw·noshrink) pt 2.79.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE); QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R"); suppressMessages({library(sandwich);library(lmtest)})
nwt<-function(x){x<-as.numeric(x);x<-x[is.finite(x)];if(length(x)<10)return(NA);tryCatch(as.numeric(coeftest(lm(x~1),vcov=sandwich::NeweyWest(lm(x~1),lag=3,prewhite=FALSE))[1,3]),error=function(e)mean(x)/sd(x)*sqrt(length(x)))}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
expz<-function(v){z<-rep(0,length(v));for(i in seq_along(v)){p<-v[1:i];p<-p[is.finite(p)];if(length(p)>=12){s<-sd(p);if(!is.na(s)&&s>1e-8)z[i]<-(v[i]-mean(p))/s}};z}
FAC<-c(Mom="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal", Value="V12_Composite_Value", Quality="Q08_Composite_Quality",
  LowVol="D03_RealVol", Size="S01_Size", Cons="C19_Composite_Earnings", SUE="C01_SUE", Growth="GR07_Composite_Growth"); FN<-names(FAC)

L<-readRDS(".cache/_bo_fwdgic.rds");fwd_ret<-L$fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)];bench<-L$fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)];liq<-L$fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
fwd_dates<-sort(unique(fwd_ret$Date))
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","K200","KQ150","Size","Sector")));rd[,Date:=as.Date(Date)];rd<-rd[Date%in%fwd_dates]
rd[,inu:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)];UNI<-rd[inu==TRUE,.(Date,Ticker)];CTRL<-rd[,.(Date,Ticker,Size,Sector)]
ZL<-list();for(dk in as.character(fwd_dates)){d<-as.Date(dk);f<-tryCatch(as.data.table(load_month_factors(d,factor_names=unname(FAC))),error=function(e)NULL);if(is.null(f)||nrow(f)==0)next;ZL[[dk]]<-dcast(f,Ticker~Factor_Name,value.var="Z_Score_Aligned")}
cat(sprintf("z loaded %d months\n",length(ZL)))

## ②FWL: 각 월 z를 [1, log(size), sector더미]에 횡단면회귀 → 잔차. raw + FWL 두 버전 보관.
FWL_SKIP<-c(FAC["Size"])  # selective FWL: Size는 통제이자 팩터라 중립화 제외(raw 유지)
fwl_month<-function(fw,d){m<-merge(fw,CTRL[Date==d,.(Ticker,Size,Sector)],by="Ticker");if(nrow(m)<20)return(fw)
  X<-model.matrix(~ log(pmax(Size,1)) + factor(Sector), data=m); cols<-setdiff(FAC[FAC%in%names(m)],FWL_SKIP)
  for(cc in cols){y<-m[[cc]];ok<-is.finite(y)&apply(X,1,function(r)all(is.finite(r)));if(sum(ok)<20){next}
    b<-tryCatch(qr.solve(X[ok,,drop=FALSE],y[ok]),error=function(e)NULL);if(is.null(b))next;res<-y;res[ok]<-y[ok]-as.numeric(X[ok,,drop=FALSE]%*%b);m[[cc]]<-res}
  m[,.SD,.SDcols=c("Ticker",names(fw)[names(fw)!="Ticker"])]}
ZLfwl<-list();for(dk in names(ZL))ZLfwl[[dk]]<-fwl_month(ZL[[dk]],as.Date(dk))
cat("FWL residualized\n")
dts<-as.Date(names(ZL)); ND<-length(dts)

## ①국면축: 시장(Cascade) + 변동성(시장 실현변동성). soft membership.
uni<-as.data.table(read_parquet(".cache/unified_regime_signal_daily.parquet"));uni[,Date:=as.Date(Date)];uni<-uni[!is.na(Date)];uni[,ym:=format(Date,"%Y-%m")]
um<-uni[,.(rs=last(Regime_Score_smooth)),by=ym];RM<-data.table(ym=format(dts,"%Y-%m"));RM<-merge(RM,um,by="ym",all.x=TRUE);RM[,rsz:=expz(rs)];RM[is.na(rsz),rsz:=0]
bmv<-merge(data.table(Date=dts),bench,by="Date",all.x=TRUE)$BM_Ret;vol<-rep(NA_real_,ND);for(i in 7:ND)vol[i]<-sd(bmv[max(1,i-5):i],na.rm=T);volz<-expz(vol)
M_mkt<-t(sapply(RM$rsz,function(z){e<-exp(c(-1,0,1)*z);e/sum(e)}))            # 3-state 시장
M_vol<-t(sapply(volz,function(z){e<-exp(c(-1,1)*z);e/sum(e)}))                # 2-state 변동성
# 1D = 시장 3-state; 2D = 시장×변동성 6-state (outer product)
MEM1D<-M_mkt; MEM2D<-matrix(0,ND,6);for(i in 1:ND){MEM2D[i,]<-as.numeric(outer(M_mkt[i,],M_vol[i,]))}

## 팩터 월간 active 수익 (z 버전별 top-tercile EW − BM)
build_act<-function(ZLx){A<-matrix(NA_real_,ND,length(FN),dimnames=list(NULL,FN))
  for(j in seq_along(FN)){id<-FAC[FN[j]];for(i in seq_len(ND)){dk<-names(ZLx)[i];fw<-ZLx[[dk]];if(!id%in%names(fw))next
    sub<-merge(data.table(Ticker=fw$Ticker,z=fw[[id]])[is.finite(z)],UNI[Date==dts[i]],by="Ticker");if(nrow(sub)<15)next
    sel<-sub[z>=quantile(z,2/3,na.rm=T)]$Ticker;fr<-fwd_ret[Date==dts[i]&Ticker%in%sel,Ret_1m];br<-bench[Date==dts[i],BM_Ret];if(length(fr)>=5)A[i,j]<-mean(fr,na.rm=T)-ifelse(length(br),br,0)}};A}
ACT_raw<-build_act(ZL); ACT_fwl<-build_act(ZLfwl); cat("factor active built\n")

## 국면조건부 가중 (shrinkage): C_state shrunk→C_full, W=Σ M·max(C_shrunk,0)
build_W<-function(MEM,ACT,shrink,mb){NS<-ncol(MEM);Wm<-matrix(0,ND,length(FN),dimnames=list(NULL,FN))
  for(i in seq_len(ND)){if(i<37){Wm[i,]<-1;next}
    for(j in seq_along(FN)){av<-ACT[1:(i-1),j];cf<-mean(av,na.rm=T);if(!is.finite(cf))cf<-0;tot<-0
      for(s in 1:NS){w<-MEM[1:(i-1),s];ok<-is.finite(av)&is.finite(w);neff<-sum(w[ok]);cs<-if(neff>1e-6)sum(av[ok]*w[ok])/neff else cf
        lam<-shrink/(neff+shrink);csh<-(1-lam)*cs+lam*cf;tot<-tot+MEM[i,s]*max(csh,0)}
      Wm[i,j]<-tot}
    if(all(Wm[i,]<1e-9))Wm[i,]<-1}
  if(mb>0){base<-apply(Wm,1,function(r)max(sum(r),1e-9));Wm[,"Mom"]<-Wm[,"Mom"]+mb*base;Wm[,"ResidMom"]<-Wm[,"ResidMom"]+0.5*mb*base};Wm}

run<-function(ZLx,Wm,lab){rows<-list()
  for(i in seq_len(ND)){dk<-names(ZLx)[i];fw<-ZLx[[dk]];wf<-Wm[i,];if(sum(wf)<1e-9)wf<-rep(1,length(FN));wf<-wf/sum(wf)
    sc<-rep(0,nrow(fw));for(j in seq_along(FN)){id<-FAC[FN[j]];if(id%in%names(fw)){z<-zc(fw[[id]]);z[!is.finite(z)]<-0;sc<-sc+wf[j]*z}}
    rows[[dk]]<-data.table(Date=dts[i],Ticker=fw$Ticker,score=sc)}
  SC<-merge(rbindlist(rows),UNI,by=c("Date","Ticker"))
  cs<-tryCatch(canonical_screen_bt(SC[,.(Date,Ticker,score)],fwd_ret,bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="v2",strategy_id=lab),error=function(e)NULL)
  if(is.null(cs$period_returns))return(NULL);pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr);k<-floor(n*0.6);nav<-cumprod(1+pr$ret_net);mdd<-min(nav/cummax(nav)-1);cagr<-prod(1+pr$ret_net)^(12/n)-1
  oret<-median(sapply(c(.55,.65,.75),function(fr){kk<-floor(n*fr);if(kk<12||(n-kk)<6)return(NA);is<-IRf(act[1:kk]);oo<-IRf(act[(kk+1):n]);if(!is.na(is)&&is>0)oo/is else NA}),na.rm=TRUE)
  data.table(strategy=lab,n=n,pt_full=nwt(act),pt_OOS=nwt(act[(k+1):n]),oos_ret=oret,calmar=cagr/abs(mdd),absSR=IRf(pr$ret_net),TO=cs$turnover_annual)}

cells<-list(
  list(z="raw",ZL=ZL, ACT=ACT_raw, MEM=MEM1D,sh=0,  mb=0,  lab="①기준 raw·1D·noshrink"),
  list(z="fwl",ZL=ZLfwl,ACT=ACT_fwl,MEM=MEM1D,sh=0,  mb=0,  lab="②+FWL"),
  list(z="fwl",ZL=ZLfwl,ACT=ACT_fwl,MEM=MEM1D,sh=8,  mb=0,  lab="②+FWL +③shrink"),
  list(z="fwl",ZL=ZLfwl,ACT=ACT_fwl,MEM=MEM2D,sh=8,  mb=0,  lab="②FWL +①2D +③shrink"),
  list(z="fwl",ZL=ZLfwl,ACT=ACT_fwl,MEM=MEM2D,sh=8,  mb=0.4,lab="full +mombase0.4")
)
R<-rbindlist(Filter(Negate(is.null),lapply(cells,function(c){W<-build_W(c$MEM,c$ACT,c$sh,c$mb);run(c$ZL,W,c$lab)})),fill=TRUE)
cat("\n=== 국면조건부 강화 (②FWL ①2D ③shrink) — gate pt2.95·oos_ret0.7(밴드0.5)·cal0.64 ===\n")
cat(sprintf("  %-26s %4s %8s %8s %8s %7s %6s %5s\n","strategy","n","pt_full","pt_OOS","oos_ret","calmar","absSR","TO"))
for(i in seq_len(nrow(R))){r<-R[i];cat(sprintf("  %-26s %4d %8.2f %8.2f %8.2f %7.2f %6.2f %5.1f [pt%s oos%s cal%s]\n",r$strategy,r$n,r$pt_full,r$pt_OOS,r$oos_ret,r$calmar,r$absSR,r$TO,ifelse(r$pt_full>=2.95,"P","F"),ifelse(!is.na(r$oos_ret)&&r$oos_ret>=0.7,"P",ifelse(!is.na(r$oos_ret)&&r$oos_ret>=0.5,"o","F")),ifelse(r$calmar>=0.64,"P","F")))}
saveRDS(R,".cache/_rb_v2.rds");cat("RBV2_DONE\n")
