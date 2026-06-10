## Second uncertainty estimator: TIME-SERIES rolling SE of each stock's score_eff
## (Liao 2025 signal-level standard error). PIT: SE uses scores up to t-1 only.
## Also test: shrink-toward-EW within picks (uncertainty -> equalize) as alt mechanism.
suppressPackageStartupMessages({library(arrow);library(data.table);library(PerformanceAnalytics);library(xts)})
options(warn=1)
BASE <- "G:/Quant_Module_Moltbot"
PROD <- file.path(BASE,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe")
OUT  <- file.path(BASE,"stage_artifacts/alpha_search")

a <- as.data.table(read_parquet(file.path(PROD,"alpha_scores_str1715_268m.parquet")))
setkey(a, Ticker, Date)
# rolling SE of score_eff per ticker over trailing W months (shift to t-1 => PIT)
W <- 12L
a[, se_roll := {
  x <- score_eff
  n <- length(x)
  out <- rep(NA_real_, n)
  if(n>=3){
    for(j in seq_len(n)){
      lo <- max(1L, j-W); hi <- j-1L  # strictly trailing (PIT, excludes current)
      if(hi-lo+1 >= 3){
        v <- x[lo:hi]; v <- v[is.finite(v)]
        if(length(v)>=3) out[j] <- sd(v)
      }
    }
  }
  out
}, by=Ticker]
setkey(a, Date, Ticker)

raw <- as.data.table(read_parquet(file.path(BASE,".cache/rawdata.parquet"),
        col_select=c("Date","Ticker","Close","Vol","Ret")))
setkey(raw, Date, Ticker); raw[, TradingAmt := Close*Vol]
bm <- as.data.table(read_parquet(file.path(BASE,".cache/benchmark.parquet"))); bm[,Date:=as.Date(Date)]; setorder(bm,Date)
sig_dates <- sort(unique(a[!is.na(score_eff), Date]))

normalize_long_only <- function(w, lb=0, ub=0.20, target_sum=1, max_iter=50){
  w[!is.finite(w)]<-0; w[w<lb]<-lb; w[w>ub]<-ub; s<-sum(w)
  if(s<=1e-12){n<-length(w);return(rep(target_sum/n,n))}; w<-w*(target_sum/s)
  for(k in seq_len(max_iter)){over<-w>ub+1e-12;if(!any(over))break;ex<-sum(w[over]-ub);w[over]<-ub
    fr<-which(!over&w>lb+1e-12);if(length(fr)==0){w<-w*(target_sum/sum(w));break};w[fr]<-w[fr]+ex*(w[fr]/sum(w[fr]))}
  w/sum(w)*target_sum }
linear_tilt_qd <- function(alpha_t, lambda=1.0, lb=0, ub=0.20){
  N<-length(alpha_t);if(N<=1)return(rep(1,N));r<-rank(alpha_t,ties.method="average")
  ctr<-(r-mean(r))/(N-1);wr<-pmax(1+lambda*2*ctr,1e-6);w<-wr/sum(wr);normalize_long_only(w,lb=lb,ub=ub,target_sum=1)}
linear_tilt_to_penalty_qd <- function(alpha_t,lambda=1.5,w_prev=NULL,phi=3.0,lb=0,ub=0.20){
  wt<-linear_tilt_qd(alpha_t,lambda=lambda,lb=lb,ub=ub);names(wt)<-names(alpha_t)
  if(is.null(w_prev)||phi<=0)return(wt);wp<-numeric(length(wt));names(wp)<-names(wt)
  cm<-intersect(names(wt),names(w_prev));wp[cm]<-w_prev[cm];dr<-1-sum(wp);if(dr>0)wp<-wp+dr*wt
  if(sum(wp)>0)wp<-wp/sum(wp);bl<-phi/(1+phi);wo<-bl*wp+(1-bl)*wt;normalize_long_only(wo,lb=lb,ub=ub,target_sum=1)}

LIQ<-2e8;BPS<-15;MAXN<-20L;MINN<-15L;UB<-0.20;LAMBDA<-1.5;TOPHI<-3.0

run_wf <- function(mode="baseline", k=0){
  res<-vector("list",length(sig_dates)-1L);w_prev<-NULL
  for(i in seq_len(length(sig_dates)-1L)){
    sl<-sig_dates[i];nl<-sig_dates[i+1L]
    sd0<-suppressWarnings(min(raw[Date>=sl]$Date));if(!is.finite(sd0))next
    nx<-suppressWarnings(min(raw[Date>=nl]$Date));ed<-if(is.finite(nx))nx else max(raw$Date)
    panel<-a[Date==sl & !is.na(score_eff)];if(nrow(panel)==0L)next
    setorder(panel,-score_eff);Ne<-nrow(panel);Nt<-min(MAXN,Ne);if(Nt<MINN&&Ne>=MINN)Nt<-MINN;if(Nt<5L)next
    picks<-panel[seq_len(Nt)];tk<-picks$Ticker;alpha_t<-picks$score_eff;names(alpha_t)<-tk
    if(mode=="se_roll" && k>0){
      se<-picks$se_roll; se[!is.finite(se)]<-median(se,na.rm=TRUE); if(all(!is.finite(se)))se<-rep(0,length(se))
      sez<-se-mean(se,na.rm=TRUE);ss<-sd(se,na.rm=TRUE);if(is.finite(ss)&&ss>0)sez<-sez/ss else sez<-se*0
      alpha_t<-alpha_t-k*sez;names(alpha_t)<-tk
    }
    lw0<-sd0-30L;liq<-raw[Date>=lw0&Date<sd0,.(A=mean(TradingAmt,na.rm=TRUE)),by=Ticker]
    lqtk<-liq[A>=LIQ,Ticker];tkl<-intersect(tk,lqtk);if(length(tkl)<5L)tkl<-tk
    alpha_l<-alpha_t[tkl];if(length(alpha_l)<5L)next
    ## SE-shrink-to-EW variant operates on weights, not score:
    wr<-tryCatch(linear_tilt_to_penalty_qd(alpha_l,lambda=LAMBDA,w_prev=w_prev,phi=TOPHI,lb=0,ub=UB),
                 error=function(e)linear_tilt_qd(alpha_l,lambda=LAMBDA,lb=0,ub=UB))
    names(wr)<-names(alpha_l);w<-normalize_long_only(wr,lb=0,ub=UB,target_sum=1)
    if(mode=="shrink_ew" && k>0){
      # per-name shrink intensity grows with rolling SE (z) -> pull toward EW
      sub<-picks[match(names(w),picks$Ticker)]; se<-sub$se_roll; se[!is.finite(se)]<-median(se,na.rm=TRUE)
      if(all(!is.finite(se)))se<-rep(0,length(se)); sez<-se-mean(se,na.rm=TRUE);ss<-sd(se,na.rm=TRUE)
      if(is.finite(ss)&&ss>0)sez<-sez/ss else sez<-se*0
      ew<-rep(1/length(w),length(w)); lam_i<-pmin(pmax(k*0.1*sez,0),0.9) # shrink fraction per name
      w<-(1-lam_i)*w + lam_i*ew; w<-normalize_long_only(w,lb=0,ub=UB,target_sum=1)
    }
    pd<-raw[Date>sd0&Date<=ed,.(Date,Ticker,Ret)];if(nrow(pd)==0L)next
    sr<-pd[,.(sret=prod(1+Ret,na.rm=TRUE)-1),by=Ticker]
    mg<-merge(data.table(ticker=names(w),wt=as.numeric(w)),sr,by.x="ticker",by.y="Ticker",all.x=TRUE);mg[is.na(sret),sret:=0]
    pg<-sum(mg$wt*mg$sret,na.rm=TRUE)
    if(is.null(w_prev)||length(w_prev)==0L){to<-1.0}else{an<-union(names(w),names(w_prev))
      wa<-setNames(rep(0,length(an)),an);wpa<-setNames(rep(0,length(an)),an);wa[names(w)]<-w;wpa[names(w_prev)]<-w_prev;to<-sum(abs(wa-wpa))/2}
    cost<-(BPS/1e4)*to*2;pn<-pg-cost
    bsub<-bm[Date>sd0&Date<=ed];br<-if(nrow(bsub)>0)prod(1+bsub$BM_Ret,na.rm=TRUE)-1 else 0
    res[[i]]<-data.table(period_end=ed,port_net=pn,bm_ret=br,turnover=to,n=nrow(mg));w_prev<-w
  }
  out<-rbindlist(res,use.names=TRUE,fill=TRUE);out<-out[!is.na(port_net)];setorder(out,period_end);out }

met<-function(dt,lab){if(nrow(dt)<12)return(NULL);rx<-xts(dt$port_net,order.by=as.Date(dt$period_end))
  bx<-xts(dt$bm_ret,order.by=as.Date(dt$period_end));ax<-rx-bx
  list(label=lab,n=nrow(dt),sr_total=as.numeric(SharpeRatio.annualized(rx,Rf=0,scale=12)),
       sr_active=as.numeric(SharpeRatio.annualized(ax,Rf=0,scale=12)),
       cagr=as.numeric(Return.annualized(rx,scale=12)),mdd=as.numeric(maxDrawdown(rx)),
       ann_to=mean(dt$turnover,na.rm=TRUE)*12)}
rep1<-function(dt,nm){f<-met(dt,paste0(nm,"_FULL"));o<-met(dt[period_end>=as.Date("2010-01-01")&period_end<=as.Date("2023-12-31")],paste0(nm,"_OOS"))
  mid<-dt$period_end[ceiling(nrow(dt)/2)];e<-met(dt[period_end<=mid],"e");l<-met(dt[period_end>mid],"l")
  rt<-if(!is.null(e)&&!is.null(l)&&e$sr_active!=0)l$sr_active/e$sr_active else NA
  cat(sprintf("  %-22s FULL SR_tot=%.4f SR_act=%.4f MDD=%.4f TO=%.2f | OOS SR_tot=%.4f SR_act=%.4f | oos_ret(act)=%.4f\n",
      nm,f$sr_total,f$sr_active,f$mdd,f$ann_to,o$sr_total,o$sr_active,rt));invisible(list(f=f,o=o,rt=rt))}

cat("=== rolling-SE down-weight (score adj) ===\n")
b<-run_wf("baseline");rep1(b,"baseline")
for(k in c(0.5,1.0,2.0)){d<-run_wf("se_roll",k);rep1(d,sprintf("se_roll_k%.1f",k))}
cat("=== rolling-SE shrink-to-EW (weight adj) ===\n")
for(k in c(1.0,3.0,6.0)){d<-run_wf("shrink_ew",k);rep1(d,sprintf("shrink_ew_k%.1f",k))}
cat("[DONE2]\n")
