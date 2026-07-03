## run_ramp01_enhance.R — Direction1: Shu-Mulvey 국면방법(SJM)을 RAMP_01의 11 pure그룹에 적용해 25종목 강화.
## 25종목 실패교훈: raw-z 합성=소형/베타 틸트로 역행. RAMP_01(+2.73)은 FWL-중립 pure그룹+국면IC라 작동.
## → 그룹 월간 active수익(top-tercile EW − market)에 multi-feature 2-state SJM → per-group view → w_group=max(view,0)
##    → stock score = Σ_g w_g·group_z → top-25 EW long-only 15bps (canonical_screen_bt 실측). vs RAMP_01 2.73.
suppressPackageStartupMessages({library(data.table); library(arrow); library(Rcpp)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE); QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R"); suppressMessages({library(sandwich);library(lmtest)})
PER<-12  # 월간
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-as.numeric(x);x<-x[is.finite(x)];if(length(x)<12)return(NA);tryCatch({m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3])},error=function(e)mean(x)/sd(x)*sqrt(length(x)))}
oos_ret<-function(act){n<-length(act);md<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA});median(md,na.rm=TRUE)}
ewm<-function(x,hl){a<-1-exp(log(0.5)/hl);y<-numeric(length(x));acc<-NA_real_;for(i in seq_along(x)){xi<-x[i];if(is.na(xi)){y[i]<-acc;next};acc<-if(is.na(acc))xi else a*xi+(1-a)*acc;y[i]<-acc};y}
cppFunction('IntegerVector jumpDP(NumericMatrix C,double lam){int n=C.nrow();NumericMatrix D(n,2);IntegerMatrix B(n,2);D(0,0)=C(0,0);D(0,1)=C(0,1);for(int t=1;t<n;t++){for(int k=0;k<2;k++){double st=D(t-1,k);double sw=D(t-1,1-k)+lam;if(st<=sw){D(t,k)=C(t,k)+st;B(t,k)=k;}else{D(t,k)=C(t,k)+sw;B(t,k)=1-k;}}}IntegerVector s(n);s[n-1]=D(n-1,0)<=D(n-1,1)?0:1;for(int t=n-2;t>=0;t--)s[t]=B(t+1,s[t+1]);return s+1;}')
sparse_jm<-function(X,lam,kappa,outer=8,inner=10){X<-as.matrix(X);T<-nrow(X);p<-ncol(X);wj<-rep(1/sqrt(p),p);s<-as.integer(X[,1]>median(X[,1]))+1L;soft<-function(a,d)sign(a)*pmax(abs(a)-d,0)
  for(o in 1:outer){for(it in 1:inner){th<-matrix(0,2,p);for(k in 1:2){idx<-which(s==k);th[k,]<-if(length(idx)>0)colMeans(X[idx,,drop=FALSE])else colMeans(X)};C<-matrix(0,T,2);for(k in 1:2){d2<-sweep(X,2,th[k,],"-")^2;C[,k]<-as.numeric(d2%*%wj)};ns<-jumpDP(C,lam);if(all(ns==s))break;s<-ns}
    th<-matrix(0,2,p);for(k in 1:2){idx<-which(s==k);th[k,]<-if(length(idx)>0)colMeans(X[idx,,drop=FALSE])else colMeans(X)};gm<-colMeans(X);TSS<-colSums(sweep(X,2,gm,"-")^2);WCSS<-rep(0,p);for(k in 1:2){idx<-which(s==k);if(length(idx)>0)WCSS<-WCSS+colSums(sweep(X[idx,,drop=FALSE],2,th[k,],"-")^2)};a<-pmax(TSS-WCSS,0)
    f<-function(d){sw<-soft(a,d);nm<-sqrt(sum(sw^2));if(nm<1e-12)return(0);sum(abs(sw/nm))};if(f(0)<=kappa){d<-0}else{lo<-0;hi<-max(a);for(b in 1:50){mid<-(lo+hi)/2;if(f(mid)>kappa)lo<-mid else hi<-mid};d<-hi};sw<-soft(a,d);nm<-sqrt(sum(sw^2));wnew<-if(nm<1e-12)rep(1/sqrt(p),p)else sw/nm;if(max(abs(wnew-wj))<1e-4){wj<-wnew;break};wj<-wnew}
  list(s=s,th=th)}
mfeat<-function(a){n<-length(a);L<-cumprod(1+ifelse(is.finite(a),a,0));dd<-L/cummax(L)-1
  data.table(e3=ewm(a,3),e6=ewm(a,6),e12=ewm(a,12),mom12=ewm(a,12)-ewm(a,1),dn=sqrt(ewm(pmin(a,0)^2,6)),ddv=dd,lvl=(ewm(L,3)-ewm(L,12))/L)}

## --- 데이터: pure 그룹 + fwd ---
g<-as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet"));g[,signal_date:=as.Date(signal_date)]
gw<-dcast(g,signal_date+security_id~family,value.var="group_z");GRP<-setdiff(names(gw),c("signal_date","security_id"))
sig_dates<-sort(unique(g$signal_date))
L<-readRDS(".cache/_bo_fwdgic.rds");fwd_ret<-L$fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)];bench<-L$fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)];liq<-L$fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
bm<-merge(data.table(signal_date=sig_dates),bench[,.(signal_date=Date,BM_Ret)],by="signal_date",all.x=TRUE)
cat(sprintf("groups=%d months=%d\n",length(GRP),length(sig_dates)))

## --- 그룹 월간 active 수익: top-tercile EW(group_z) 다음달 수익 − BM ---
gact<-data.table(signal_date=sig_dates)
for(fm in GRP){ ar<-rep(NA_real_,length(sig_dates))
  for(i in seq_along(sig_dates)){d<-sig_dates[i];sub<-gw[signal_date==d,.(security_id,z=get(fm))];sub<-sub[is.finite(z)];if(nrow(sub)<15)next
    thr<-quantile(sub$z,2/3,na.rm=T);sel<-sub[z>=thr]$security_id
    fr<-fwd_ret[Date==d & Ticker%in%sel,Ret_1m];if(length(fr)<5)next;br<-bm[signal_date==d,BM_Ret];ar[i]<-mean(fr,na.rm=T)-ifelse(length(br)&&is.finite(br),br,0)}
  gact[[fm]]<-ar }
cat("group active built\n")

## --- per-group 월간 SJM(rolling re-tune 12m/6y) → view; + 정적 trailing-IC ---
GRIDl<-c(2,5,10);GRIDk<-c(4,6); MINM<-60  # 최소 5y
view<-data.table(signal_date=sig_dates); tic<-data.table(signal_date=sig_dates)
for(fm in GRP){ a<-gact[[fm]];F<-mfeat(a);vw<-rep(NA_real_,length(sig_dates));ti<-rep(NA_real_,length(sig_dates));cur<-c(5,6);lt<- -99
  for(i in seq_along(sig_dates)){ if(i<MINM)next;tr<-1:(i-1);Xt<-as.matrix(F[tr]);at<-a[tr];ok<-which(apply(Xt,1,function(r)all(is.finite(r)))&is.finite(at));if(length(ok)<MINM)next
    Xo<-Xt[ok,,drop=FALSE];ao<-at[ok];mu<-colMeans(Xo);sg<-apply(Xo,2,sd);sg[!is.finite(sg)|sg<1e-9]<-1;Xs<-sweep(sweep(Xo,2,mu,"-"),2,sg,"/")
    if(i-lt>=12){best<-list(sh=-Inf,l=5,k=6);for(ll in GRIDl)for(kk in GRIDk){ft<-tryCatch(sparse_jm(Xs,ll,sqrt(kk)),error=function(e)NULL);if(is.null(ft))next;s<-ft$s;bull<-which.max(c(mean(ao[s==1]),mean(ao[s==2])));pos<-ifelse(s==bull,1,-1);nt<-pos*ao;sh<-if(sd(nt)>1e-9)mean(nt)/sd(nt)*sqrt(12)else -9;if(is.finite(sh)&&sh>best$sh)best<-list(sh=sh,l=ll,k=kk)};cur<-c(best$l,best$k);lt<-i}
    ft<-tryCatch(sparse_jm(Xs,cur[1],sqrt(cur[2])),error=function(e)NULL);if(!is.null(ft)){s<-ft$s;cs<-s[length(s)];vw[i]<-mean(ao[s==cs])*12}
    ic<-ao;ti[i]<-max(mean(ic),0) }   # trailing mean active (정적 alt)
  view[[fm]]<-vw;tic[[fm]]<-ti;cat(sprintf("  SJM %s (nn=%d)\n",fm,sum(!is.na(vw)))) }

## --- 25종목 측정: stock score = Σ_g w_g·group_z, w_g per approach ---
score_bt<-function(Wfun,lab){rows<-list()
  for(i in seq_along(sig_dates)){d<-sig_dates[i];wg<-Wfun(i);if(all(!is.finite(wg))||sum(abs(wg),na.rm=T)<1e-9)next;wg[!is.finite(wg)]<-0
    sub<-gw[signal_date==d];X<-as.matrix(sub[,..GRP]);X[is.na(X)]<-0;sc<-as.numeric(X%*%wg);rows[[as.character(d)]]<-data.table(Date=d,Ticker=sub$security_id,score=sc)}
  SC<-rbindlist(rows);cs<-tryCatch(canonical_screen_bt(SC[,.(Date,Ticker,score)],fwd_ret[,.(Date,Ticker,Ret_1m)],bench[,.(Date,BM_Ret)],top_n=25L,cost_bps_oneway=15,liq_dt=liq[,.(Date,Ticker,adv)],liq_min=2e8,run_id="e",strategy_id=lab),error=function(e){cat("ERR",lab,conditionMessage(e),"\n");NULL})
  if(is.null(cs$period_returns))return(NULL);pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr);nav<-cumprod(1+pr$ret_net);mdd<-min(nav/cummax(nav)-1);cagr<-prod(1+pr$ret_net)^(12/n)-1
  data.table(approach=lab,n=n,pt=nwt(act),IR=IRf(act),calmar=cagr/abs(mdd),oos=oos_ret(act),absSR=IRf(pr$ret_net),TO=cs$turnover_annual)}
Vm<-as.matrix(view[,..GRP]); Tm<-as.matrix(tic[,..GRP])
R<-rbindlist(Filter(Negate(is.null),list(
  score_bt(function(i)pmax(Tm[i,],0),"static_trailIC(ref)"),
  score_bt(function(i)pmax(Vm[i,],0),"D1_shumulvey_group"),
  score_bt(function(i){v<-pmax(Vm[i,],0);t<-pmax(Tm[i,],0);0.5*v/max(sum(v),1e-9)+0.5*t/max(sum(t),1e-9)},"D1_blend_SJM+IC")
)),fill=TRUE)
cat("\n=== Direction1: Shu-Mulvey 그룹국면 → 25종목 강화 (vs RAMP_01 AR+MSM 2.73) ===\n")
cat(sprintf("  %-22s %4s %7s %6s %7s %6s %6s %5s\n","approach","n","PORT_t","IR","calmar","oos","absSR","TO"))
for(i in seq_len(nrow(R))){r<-R[i];cat(sprintf("  %-22s %4d %7.2f %6.2f %7.2f %6.2f %6.2f %5.1f [pt%s cal%s oos%s]\n",r$approach,r$n,r$pt,r$IR,r$calmar,r$oos,r$absSR,r$TO,ifelse(r$pt>=2.95,"P","F"),ifelse(r$calmar>=0.64,"P","F"),ifelse(!is.na(r$oos)&&r$oos>=0.7,"P",ifelse(!is.na(r$oos)&&r$oos>=0.5,"o","F"))))}
saveRDS(list(R=R,view=view,tic=tic),".cache/_ramp01_enh.rds");cat("ENH_DONE\n")
