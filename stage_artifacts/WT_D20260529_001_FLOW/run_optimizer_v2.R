# =============================================================
# WT-D20260529_001 FLOW — Optimizer v2 (FORWARD-ALIGNED, bug-fixed)
# FIX: weights at sig_date t earn FORWARD month (t+1) return. (v1 used same-month -> IC -0.206)
# Verified: forward-month rank-IC = +0.0214 == alpha_package (correct alignment).
# Efficiency: select_names precomputed ONCE (method-independent) -> reused across methods.
# =============================================================
suppressMessages({library(data.table); library(arrow); library(quadprog); library(corpcor)})
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260529_001_FLOW"); set.seed(42)
LOCKBOX<-as.Date("2023-12-22"); COST_OW<-0.0015; MAX_NAMES<-20L; W_CAP<-0.20
LIQ_FLOOR<-2e8; N_DAYS_COV<-252L
source("02_Infrastructure/portfolio/hrp_core.R")
source("02_Infrastructure/portfolio/advanced_weights.R")
source("02_Infrastructure/portfolio/mean_variance_optimizer.R")
`%||%`<-function(a,b) if(is.null(a)) b else a

alpha <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))[Date<=LOCKBOX]
sig_dates <- sort(unique(alpha$Date))
rd <- as.data.table(read_parquet(".cache/rawdata.parquet"))[Date<=LOCKBOX,
        .(Date,Ticker,Ret,Close,Vol,AdminStock,TradingHalt,BM_Ret)]
rd[, TV:=Close*Vol]; rd[, ym:=format(Date,"%Y-%m")]; setkey(rd,Date,Ticker)
mret <- rd[!is.na(Ret), .(mret=prod(1+Ret)-1), by=.(Ticker,ym)]; setkey(mret,Ticker,ym)
bm_m <- unique(rd[!is.na(BM_Ret),.(Date,BM_Ret,ym)])[, .(bm=prod(1+BM_Ret)-1), by=ym]; setkey(bm_m,ym)
months_all <- sort(unique(rd$ym))
nextm <- function(m){i<-match(m,months_all); if(is.na(i)||i==length(months_all)) NA_character_ else months_all[i+1]}

# ---- ERC / MinVar helpers ----
erc_w<-function(Sig,tk){n<-ncol(Sig);x<-rep(1/n,n);for(i in 1:300){mrc<-as.numeric(Sig%*%x);rc<-x*mrc;t<-mean(rc);x<-x*(t/(rc+1e-12))^.5;x<-pmax(x,1e-8);x<-x/sum(x)};setNames(x,tk)}
minvar_w<-function(Sig,tk){n<-ncol(Sig);D<-Sig+diag(1e-8,n);A<-cbind(rep(1,n),diag(n),-diag(n));b<-c(1,rep(0,n),rep(-W_CAP,n));s<-tryCatch(solve.QP(D,rep(0,n),A,b,meq=1)$solution,error=function(e)rep(1/n,n));s<-pmax(s,0);setNames(s/sum(s),tk)}

build_ret_dt<-function(tk,d,n=N_DAYS_COV){s<-rd[Ticker%in%tk & Date<d];s<-s[order(Date)];kd<-tail(sort(unique(s$Date)),n);s[Date%in%kd & !is.na(Ret),.(Date,Ticker,Ret)]}

# ---- select_names: precompute ONCE per rebal date (method-independent) ----
select_names<-function(d){a<-alpha[Date==d,.(Ticker,alpha_score,confidence)];if(nrow(a)==0)return(NULL)
  liq<-rd[Date<d & Ticker%in%a$Ticker][order(Ticker,Date)]
  l20<-liq[,.(avgTV=mean(tail(TV,20),na.rm=T),admin=max(tail(AdminStock,1),0,na.rm=T),halt=max(tail(TradingHalt,1),0,na.rm=T)),by=Ticker]
  ok<-l20[avgTV>=LIQ_FLOOR & (is.na(admin)|admin==0)&(is.na(halt)|halt==0),Ticker]
  a<-a[Ticker%in%ok];if(nrow(a)<10)return(NULL);setorder(a,-alpha_score);head(a,MAX_NAMES)}

normw<-function(w){w<-w[!is.na(w)];if(length(w)==0||sum(w)<=0)return(NULL);w<-pmax(pmin(w,W_CAP),0);w<-w/sum(w)
  it<-0;while(any(w>W_CAP+1e-9)&&it<200){o<-w>W_CAP;e<-sum(w[o]-W_CAP);w[o]<-W_CAP;u<-!o&w>0;if(!any(u))break;w[u]<-w[u]+e*w[u]/sum(w[u]);w<-w/sum(w);it<-it+1};w/sum(w)}

get_weights<-function(method,nm,d){tk<-nm$Ticker;rdt<-build_ret_dt(tk,d);tk2<-intersect(tk,unique(rdt$Ticker));if(length(tk2)<5)return(NULL);a<-nm[Ticker%in%tk2]
  w<-switch(method,
    "EW"=setNames(rep(1/length(tk2),length(tk2)),tk2),
    "MVO"={rm<-dcast(rdt[Ticker%in%tk2],Date~Ticker,value.var="Ret");M<-as.matrix(rm[,-1]);M[is.na(M)]<-0;Sg<-tryCatch(cov.shrink(M,verbose=F),error=function(e)cov(M))*252;al<-setNames(a$alpha_score,a$Ticker)[colnames(M)];cf<-setNames(a$confidence,a$Ticker)[colnames(M)];ww<-tryCatch(mvo_weights(alpha=al,cov_matrix=Sg,confidence=cf,lambda=2,psi=.3,bounds=c(0,W_CAP),max_names=MAX_NAMES,min_names=15L,hhi_cap=.15,alpha_winsor=2),error=function(e)NULL);if(is.null(ww))return(NULL);v<-ww$weights%||%ww$target_weights%||%ww;if(is.list(v))v<-unlist(v);v},
    "HRP"=tryCatch(calc_hrp_weights(tk2,rdt,n_days=N_DAYS_COV,max_w=W_CAP),error=function(e)NULL),
    "ERC"={rm<-dcast(rdt[Ticker%in%tk2],Date~Ticker,value.var="Ret");M<-as.matrix(rm[,-1]);M[is.na(M)]<-0;Sg<-tryCatch(cov.shrink(M,verbose=F),error=function(e)cov(M));erc_w(Sg,colnames(M))},
    "CVaR"=tryCatch(calc_cvar_weights(tk2,rdt,n_days=N_DAYS_COV,max_w=W_CAP),error=function(e)NULL),
    "MinVar"={rm<-dcast(rdt[Ticker%in%tk2],Date~Ticker,value.var="Ret");M<-as.matrix(rm[,-1]);M[is.na(M)]<-0;Sg<-tryCatch(cov.shrink(M,verbose=F),error=function(e)cov(M));minvar_w(Sg,colnames(M))},
    NULL)
  normw(w)}

# quarterly rebal dates
q_dates<-sig_dates[as.integer(format(sig_dates,"%m"))%in%c(1,4,7,10)]
q_dates<-q_dates[q_dates>=(min(rd$Date)+400)]
cat(sprintf("[v2] %d quarterly rebal dates; FORWARD-aligned (sig t -> hold month t+1..)\n",length(q_dates)))

# precompute selections + per-method weights at rebal dates
methods<-c("EW","MVO","HRP","ERC","CVaR","MinVar")
sel_cache<-list(); for(d in as.character(q_dates)){nm<-select_names(as.Date(d));if(!is.null(nm))sel_cache[[d]]<-nm}
cat(sprintf("[v2] selections computed: %d/%d\n",length(sel_cache),length(q_dates)))
wcache<-list(); for(m in methods){wcache[[m]]<-list();for(d in names(sel_cache)){w<-get_weights(m,sel_cache[[d]],as.Date(d));if(!is.null(w))wcache[[m]][[d]]<-w};cat(sprintf("  %s weights: %d rebal sets\n",m,length(wcache[[m]])))}
saveRDS(list(sel_cache=sel_cache,wcache=wcache,q_dates=q_dates),file.path(OUT,"opt_wcache.rds"))

# ---- FORWARD-aligned monthly walk-forward ----
# rebal at q_date d (month=ym(d)); first HELD month = nextm(ym(d)); cost charged at first held month.
# weights held until next rebal's first held month; monthly drift renormalize.
run_wf<-function(method){
  wl<-wcache[[method]]
  rb_first_held<-sapply(names(wl), function(d) nextm(format(as.Date(d),"%Y-%m")))
  held<-data.table(start_month=rb_first_held, rebal=names(wl))
  held<-held[!is.na(start_month)][order(start_month)]
  out<-data.table(ym=character(),ret_gross=numeric(),ret_net=numeric(),turnover=numeric(),nnames=integer())
  prev_w<-NULL; cur_rb<-NA
  for(m in months_all){
    # active rebal = latest held block with start_month <= m
    cand<-held[start_month<=m]; if(nrow(cand)==0)next
    rb<-cand[.N,rebal]; w0<-wl[[rb]]; if(is.null(w0))next
    is_new<-!identical(rb,cur_rb)
    to<-0
    if(is_new){
      if(is.null(prev_w)) to<-sum(abs(w0)) else {al<-union(names(prev_w),names(w0));pw<-setNames(rep(0,length(al)),al);pw[names(prev_w)]<-prev_w;nw<-setNames(rep(0,length(al)),al);nw[names(w0)]<-w0;to<-sum(abs(nw-pw))}
      cur_rb<-rb; w<-w0
    } else w<-prev_w  # carry drifted weights
    gr<-mret[ym==m & Ticker%in%names(w)]; if(nrow(gr)==0)next
    wv<-w[gr$Ticker];wv[is.na(wv)]<-0
    rg<-sum(wv*gr$mret,na.rm=T); rn<-rg-to*COST_OW
    out<-rbind(out,data.table(ym=m,ret_gross=rg,ret_net=rn,turnover=to,nnames=length(w)))
    # drift weights for next month
    g<-setNames(gr$mret,gr$Ticker)[names(w)];g[is.na(g)]<-0;w<-w*(1+g);w<-w/sum(w);prev_w<-w
  }
  out
}
cat("[v2] running forward-aligned walk-forward...\n")
res<-list();for(m in methods){cat("  -",m,"\n");res[[m]]<-run_wf(m)}
saveRDS(res,file.path(OUT,"opt_wf_results_v2.rds"))

# ---- comparison ----
ss<-function(dt){dt<-merge(dt,bm_m,by="ym",all.x=T)[!is.na(bm)];dt[,ac:=ret_net-bm];rn<-dt$ret_net;ac<-dt$ac
  list(net_sr=mean(rn)/sd(rn)*sqrt(12),ir=mean(ac)/sd(ac)*sqrt(12),te=sd(ac)*sqrt(12),
       ann_ret=prod(1+rn)^(12/length(rn))-1,ann_vol=sd(rn)*sqrt(12),ann_to=sum(dt$turnover)/(length(rn)/12),n=length(rn))}
comp<-rbindlist(lapply(methods,function(m){s<-ss(res[[m]]);data.table(method=m,net_sr=round(s$net_sr,4),ir=round(s$ir,4),te=round(s$te,4),ann_ret=round(s$ann_ret,4),ann_vol=round(s$ann_vol,4),ann_to=round(s$ann_to,3),n=s$n)}))
setorder(comp,-net_sr)
cat("\n=== SLEEVE METHOD COMPARISON v2 (FORWARD-aligned, net 15bps, vs KOSPI200) ===\n");print(comp)
fwrite(comp,file.path(OUT,"method_comparison.csv"))
comp[,to_pass:=ann_to<=6.0]
elig<-comp[to_pass==TRUE]; if(nrow(elig)==0)elig<-comp
sel<-elig[which.max(net_sr),method]
ew_sr<-comp[method=="EW",net_sr]; sel_sr<-comp[method==sel,net_sr]
cat(sprintf("\n[select] net_sr-max among TO<=6.0: %s (net_sr=%.3f) | EW baseline net_sr=%.3f | sizing %s\n",
    sel,sel_sr,ew_sr, ifelse(sel_sr>ew_sr+0.03,"IMPROVES vs EW","NO material gain vs 1/N")))
saveRDS(list(comp=comp,sel_method=sel,res=res,bm_m=bm_m),file.path(OUT,"opt_stage2.rds"))
cat("\n[done v2]\n")
