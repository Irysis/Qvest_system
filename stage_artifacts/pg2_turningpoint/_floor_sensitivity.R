suppressPackageStartupMessages({library(data.table);library(arrow);library(PerformanceAnalytics);library(xts);library(lubridate)})
BASE<-Sys.getenv("CLAUDE_PROJECT_DIR"); OFF<-file.path(BASE,"stage_artifacts/pg2_offense_overlay")
COST<-0.0015; K_SLOW<-12L;K_FAST<-2L;UPDATE<-30L;MINOBS<-12L
bm<-as.data.table(read_parquet(file.path(OFF,"benchmark_pinned_20260702.parquet")))
bcol<-intersect(c("BM_Ret","Ret"),names(bm))[1];bm[,Date:=as.Date(Date)];bm<-bm[is.finite(get(bcol))];setorder(bm,Date)
mret<-apply.monthly(xts(bm[[bcol]],order.by=bm$Date),Return.cumulative)
mdt<-data.table(ym=format(index(mret),"%Y-%m"),r=as.numeric(mret));setorder(mdt,ym);nM<-nrow(mdt)
mdt[,x_slow:=frollmean(shift(r,1),K_SLOW)];mdt[,x_fast:=frollmean(shift(r,1),K_FAST)]
mk<-function(xs,xf)fifelse(!is.finite(xs)|!is.finite(xf),"NA",fifelse(xs>=0&xf>=0,"Bull",fifelse(xs>=0&xf<0,"Correction",fifelse(xs<0&xf<0,"Bear","Rebound"))))
mdt[,state:=mk(x_slow,x_fast)];st<-mdt$state;rr<-mdt$r
a_co<-rep(NA_real_,nM);a_re<-rep(NA_real_,nM)
est<-function(u){idx<-seq_len(u);s<-st[idx];x<-rr[idx];f<-is.finite(x)&s!="NA";s<-s[f];x<-x[f]
 g<-function(l)x[s==l];co<-g("Correction");re<-g("Rebound");bu<-g("Bull");be<-g("Bear")
 if(min(length(co),length(re),length(bu),length(be))<MINOBS)return(NULL)
 nbu<-length(bu);nbe<-length(be);nb<-nbu+nbe;a2<-mean(c(bu,be)^2)
 C<-(nbu/nb)*mean(bu)/a2-(nbe/nb)*mean(be)/a2;if(!is.finite(C)||abs(C)<1e-8)return(NULL)
 ac<-min(max(0.5*(1-(1/C)*mean(co)/mean(co^2)),0),1);ar<-min(max(0.5*(1-(1/C)*mean(re)/mean(re^2)),0),1);list(a_co=ac,a_re=ar)}
cur<-NULL;lu<--Inf
for(m in seq_len(nM)){pr<-m-1L;if(pr>=MINOBS){if(!is.finite(lu)||(pr-lu)>=UPDATE||is.null(cur)){e<-est(pr);if(!is.null(e)){cur<-e;lu<-pr}}};if(!is.null(cur)){a_co[m]<-cur$a_co;a_re[m]<-cur$a_re}}
mdt[,`:=`(a_co=a_co,a_re=a_re)]
pos<-with(mdt,fifelse(state=="Bull",1,fifelse(state=="Bear",-1,fifelse(state=="Correction",1-2*a_co,fifelse(state=="Rebound",2*a_re-1,NA_real_)))))
mdt[,pos:=pos];mdt[,ym_p2:=format(as.Date(paste0(ym,"-01"))%m+%months(2),"%Y-%m")]
p<-fread(file.path(BASE,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[,anchor_date:=as.Date(anchor_date)];setorder(p,realized_ym)
p<-merge(p,mdt[,.(realized_ym=ym_p2,pos_cl=pos)],by="realized_ym",all.x=TRUE);setorder(p,realized_ym)
base<-p$beta_R05*p$m4
nw<-function(d,lag=3){d<-d[is.finite(d)];n<-length(d);mu<-mean(d);e<-d-mu;s0<-sum(e^2)/n;for(L in 1:lag){w<-1-L/(lag+1);s0<-s0+2*w*sum(e[(L+1):n]*e[1:(n-L)])/n};mu/sqrt(s0/n)}
sr<-function(x)as.numeric(table.AnnualizedReturns(xts(x,order.by=p$anchor_date),scale=12)[3,1])
ro<-function(E){dE<-abs(E-shift(E,1,fill=1.0));E*p$ret_orig-dE*COST}
rb<-ro(base);cat("floor  SR     NWt_vs_NOL4  avg_expo\n")
for(fl in c(0.0,0.2,0.4,0.6,0.8,0.9)){
 beta<-fifelse(!is.finite(p$pos_cl),1.0,fl+(1-fl)*(p$pos_cl+1)/2);beta[!is.finite(beta)]<-1.0
 E<-base*beta;rt<-ro(E)
 cat(sprintf("%.1f  %.3f   %6.2f       %.3f\n",fl,sr(rt),nw(rt-rb),mean(E,na.rm=TRUE)))}
cat(sprintf("NOL4_base SR=%.3f\n",sr(rb)))
