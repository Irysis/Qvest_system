# probe_adversarial.R — Self-Adversarial Challenge 검증 (주장 아닌 실측)
#  C-A: W3(tilt20) 양(+) vs W4(EW20) 음(−) 부호 갈림의 기전 — 제외 종목의 base 내 비중/순위
#  C-B: 플라시보 시드 8 → 24 확대 (Q01 W3 '분포 밖' 주장의 취약성)
suppressPackageStartupMessages({library(data.table);library(arrow);library(sandwich);library(lmtest);library(lubridate)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- "stage_artifacts/WT_D20260808_001"
say <- function(f,...) cat(sprintf(paste0("[adv] ",f,"\n"),...))
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(NA_real_);fit<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(fit,vcov.=sandwich::NeweyWest(fit,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}
ir_v <- function(a) mean(a)/sd(a)*sqrt(12)

alpha_scores <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))
alpha_scores[,Date:=as.Date(Date)]
raw <- as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","Close","Vol","Ret","Size")))
raw[,Date:=as.Date(Date)];raw[,TradingAmt:=Close*Vol]
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"));bm[,Date:=as.Date(Date)];bm<-bm[is.finite(BM_Ret)];setorder(bm,Date)
TUNED <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/tuned_panel.parquet"));TUNED[,Date:=as.Date(Date)]
TW <- dcast(TUNED[Factor_Name %in% c("D03_EWMA","Q01_EB")],Date+Ticker~Factor_Name,value.var="score")
TW[,sig_ym:=format(as.Date(format(Date,"%Y-%m-01")) %m+% months(1),"%Y-%m")]

normalize_long_only <- function(w,lb=0,ub=0.20,target_sum=1,max_iter=50){w[!is.finite(w)]<-0;w[w<lb]<-lb;w[w>ub]<-ub
  s<-sum(w);if(s<=1e-12)return(rep(target_sum/length(w),length(w)));w<-w*(target_sum/s)
  for(k in seq_len(max_iter)){over<-w>ub+1e-12;if(!any(over))break;ex<-sum(w[over]-ub);w[over]<-ub
    fr<-which(!over&w>lb+1e-12);if(!length(fr)){w<-w*(target_sum/sum(w));break};w[fr]<-w[fr]+ex*(w[fr]/sum(w[fr]))}
  w/sum(w)*target_sum}
linear_tilt_qd <- function(a,lambda=1.0,lb=0,ub=0.20){N<-length(a);if(N<=1)return(rep(1,N))
  r<-rank(a,ties.method="average");c0<-(r-mean(r))/(N-1);wr<-pmax(1+lambda*2*c0,1e-6);normalize_long_only(wr/sum(wr),lb,ub,1)}
linear_tilt_to_penalty_qd <- function(a,lambda=1.5,w_prev=NULL,phi=3.0,lb=0,ub=0.20){
  wt<-linear_tilt_qd(a,lambda,lb,ub);names(wt)<-names(a);if(is.null(w_prev)||phi<=0)return(wt)
  wp<-setNames(numeric(length(wt)),names(wt));cm<-intersect(names(wt),names(w_prev));wp[cm]<-w_prev[cm]
  dr<-1-sum(wp);if(dr>0)wp<-wp+dr*wt;if(sum(wp)>0)wp<-wp/sum(wp);bl<-phi/(1+phi)
  normalize_long_only(bl*wp+(1-bl)*wt,lb,ub,1)}
LIQ<-2e8;CBPS<-15;MAXN<-20L;MINN<-15L;UB<-0.20
sig_dates<-sort(unique(alpha_scores[!is.na(score_eff),Date]));raw_dates<-sort(unique(raw$Date));n_iter<-length(sig_dates)-1L
cache<-vector("list",n_iter)
for(i in seq_len(n_iter)){sl<-sig_dates[i];nx<-sig_dates[i+1L];is_<-findInterval(sl-1,raw_dates)+1L
  if(is_>length(raw_dates))next;sd_<-raw_dates[is_];ie<-findInterval(nx-1,raw_dates)+1L
  ed<-if(ie>length(raw_dates))max(raw_dates) else raw_dates[ie];pt<-alpha_scores[Date==sl&!is.na(score_eff)];if(!nrow(pt))next
  liq<-raw[Date>=sd_-30L&Date<sd_,.(A=mean(TradingAmt,na.rm=TRUE)),by=Ticker][A>=LIQ,Ticker]
  sr<-raw[Date>sd_&Date<=ed,.(stock_ret=prod(1+Ret,na.rm=TRUE)-1),by=Ticker]
  cache[[i]]<-list(sig_label=sl,start_d=sd_,end_d=ed,panel_t=pt,liquid=liq,stock_rets=sr)}
build_excl<-function(fac,q=0.20){e<-new.env(parent=emptyenv())
  for(i in seq_len(n_iter)){cc<-cache[[i]];if(is.null(cc))next;ym<-format(cc$sig_label,"%Y-%m")
    f5<-TW[sig_ym==ym&is.finite(get(fac)),.(Ticker,v=get(fac))];if(!nrow(f5))next
    cand<-merge(cc$panel_t[,.(Ticker)],f5,by="Ticker",all.x=TRUE);v<-cand$v[is.finite(cand$v)];if(length(v)<30L)next
    thr<-quantile(v,q,type=7,names=FALSE);ex<-cand[is.finite(v)&v<=thr,Ticker];if(length(ex))assign(as.character(cc$sig_label),ex,envir=e)}
  e}
run_prod<-function(excl=NULL,ew=FALSE,collect=FALSE){rows<-vector("list",n_iter);wl<-vector("list",n_iter);wprev<-NULL
  for(i in seq_len(n_iter)){cc<-cache[[i]];if(is.null(cc))next;pt<-copy(cc$panel_t);reg<-pt$regime_state[1L]
    if(!is.null(excl)){k<-as.character(cc$sig_label);if(exists(k,envir=excl,inherits=FALSE))pt<-pt[!Ticker%in%get(k,envir=excl)]}
    setorder(pt,-score_eff);ne<-nrow(pt);nt<-min(MAXN,ne);if(nt<MINN&&ne>=MINN)nt<-MINN;if(nt<5L)next
    pk<-pt[seq_len(nt)];a<-setNames(pk$score_eff,pk$Ticker);tl<-intersect(names(a),cc$liquid)
    if(length(tl)<5L)tl<-names(a);a<-a[tl];if(length(a)<5L)next
    ubu<-if(identical(reg,"CRISIS"))min(UB,0.10) else UB
    if(ew)w<-setNames(rep(1/length(a),length(a)),names(a)) else {
      w<-tryCatch(linear_tilt_to_penalty_qd(a,1.5,wprev,3,0,ubu),error=function(e)linear_tilt_qd(a,1.5,0,ubu))
      names(w)<-names(a);w<-normalize_long_only(w,0,ubu,1)}
    if(is.null(cc$stock_rets)||!nrow(cc$stock_rets))next
    mr<-merge(data.table(ticker=names(w),wv=as.numeric(w)),cc$stock_rets,by.x="ticker",by.y="Ticker",all.x=TRUE)
    mr[is.na(stock_ret),stock_ret:=0];gross<-sum(mr$wv*mr$stock_ret)
    to<-if(is.null(wprev)||!length(wprev))1.0 else {an<-union(names(w),names(wprev));w1<-setNames(rep(0,length(an)),an);w0<-w1
      w1[names(w)]<-w;w0[names(wprev)]<-wprev;sum(abs(w1-w0))/2}
    rows[[i]]<-data.table(period_end=cc$end_d,ret_net=gross-(CBPS/1e4)*to*2)
    if(collect)wl[[i]]<-data.table(sig_label=cc$sig_label,Ticker=names(w),w=as.numeric(w),
        rank_in_top=match(names(w),pk$Ticker))
    wprev<-setNames(as.numeric(w),names(w))}
  out<-rbindlist(rows[!sapply(rows,is.null)]);setorder(out,period_end)
  if(collect)list(bt=out,w=rbindlist(wl[!sapply(wl,is.null)])) else out}
bmx<-bm[,.(Date,BM_Ret)]
mk_bmw<-function(an){o<-rep(NA_real_,length(an));for(i in 2:length(an)){s<-bmx[Date>an[i-1]&Date<=an[i],BM_Ret];if(length(s))o[i]<-prod(1+s)-1};data.table(period_end=an,bmw=o)}
b3<-run_prod(NULL,FALSE,collect=TRUE);BW<-mk_bmw(b3$bt$period_end)
pairedd<-function(b,f){D<-merge(merge(b[,.(period_end,rb=ret_net)],f[,.(period_end,rf=ret_net)],by="period_end"),BW,by="period_end")[is.finite(bmw)]
  d<-(D$rf-D$bmw)-(D$rb-D$bmw);list(d_ann=100*12*mean(d),t=nw_t(d),dir=ir_v(D$rf-D$bmw)-ir_v(D$rb-D$bmw))}

# ── C-A: 제외 대상 종목이 base 안에서 갖는 비중·순위 (tilt vs EW) ────────────
say("C-A: 제외 대상의 base 내 비중/순위 (부호 갈림 기전)")
WB<-b3$w
for(fac in c("D03_EWMA","Q01_EB")){
  e<-build_excl(fac,0.20)
  ex<-rbindlist(lapply(ls(e),function(k)data.table(sig_label=as.Date(k),Ticker=get(k,envir=e))))
  M<-merge(WB,ex,by=c("sig_label","Ticker"))
  say("  %s: base 보유 중 제외대상 %d건 · 평균 tilt 비중 %.4f (동일가중 기준 %.4f) · 평균 top내 순위 %.1f/20",
      fac,nrow(M),mean(M$w),1/20,mean(M$rank_in_top,na.rm=TRUE))
  say("     → tilt 비중/EW 비중 = %.3f  (1보다 작으면 tilt 가 그 종목을 이미 덜 들고 있음)",mean(M$w)/(1/20))
}
# ── C-B: 플라시보 24 시드 ────────────────────────────────────────────────────
say("C-B: 플라시보 24 시드 (Q01 W3 '분포 밖' 재검)")
set.seed(424242L)
for(fac in c("Q01_EB","D03_EWMA")){
  e<-build_excl(fac,0.20);km<-sapply(ls(e),function(k)length(get(k,envir=e)))
  real<-pairedd(b3$bt,run_prod(e,FALSE))$d_ann;ds<-numeric(0)
  for(s in 1:24){er<-new.env(parent=emptyenv())
    for(i in seq_len(n_iter)){cc<-cache[[i]];if(is.null(cc))next;k<-as.character(cc$sig_label);kk<-km[k]
      if(is.na(kk)||kk<1)next;pool<-cc$panel_t$Ticker;if(length(pool)>kk)assign(k,sample(pool,kk),envir=er)}
    ds<-c(ds,pairedd(b3$bt,run_prod(er,FALSE))$d_ann)}
  pv<-mean(ds>=real);say("  %s real %+.2f%%/yr | placebo mean %+.2f sd %.2f range [%+.2f,%+.2f] | 우측 p=%.3f",
      fac,real,mean(ds),sd(ds),min(ds),max(ds),pv)
}
say("완료")
