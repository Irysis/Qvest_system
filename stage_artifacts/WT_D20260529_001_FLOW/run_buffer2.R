# =============================================================
# Buffer v2 — CORRECT hysteresis using FULL liquid-universe alpha ranks.
# A held name is RETAINED if its full-universe liquid rank <= entry_n (even if not in top-20 today).
# New names added from top-keep_n. This genuinely reduces name rotation.
# Recomputes liquid universe ranks per rebal date (full universe, not just top-20).
# =============================================================
suppressMessages({library(data.table); library(arrow); library(quadprog); library(corpcor)})
ROOT<-"/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
OUT<-file.path(ROOT,"stage_artifacts/WT_D20260529_001_FLOW")
LOCKBOX<-as.Date("2023-12-22");COST_OW<-0.0015;MAX_NAMES<-20L;W_CAP<-0.20;LIQ_FLOOR<-2e8;N_DAYS_COV<-252L
source("02_Infrastructure/portfolio/mean_variance_optimizer.R")
`%||%`<-function(a,b) if(is.null(a)) b else a

alpha<-as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))[Date<=LOCKBOX]
rd<-as.data.table(read_parquet(".cache/rawdata.parquet"))[Date<=LOCKBOX,.(Date,Ticker,Ret,Close,Vol,AdminStock,TradingHalt,BM_Ret)]
rd[,TV:=Close*Vol];rd[,ym:=format(Date,"%Y-%m")];setkey(rd,Date,Ticker)
mret<-rd[!is.na(Ret),.(mret=prod(1+Ret)-1),by=.(Ticker,ym)];setkey(mret,Ticker,ym)
bm_m<-unique(rd[!is.na(BM_Ret),.(Date,BM_Ret,ym)])[,.(bm=prod(1+BM_Ret)-1),by=ym];setkey(bm_m,ym)
months_all<-sort(unique(rd$ym));nextm<-function(m){i<-match(m,months_all);if(is.na(i)||i==length(months_all))NA_character_ else months_all[i+1]}
wc<-readRDS(file.path(OUT,"opt_wcache.rds"));q_dates<-wc$q_dates

# full liquid-universe ranked candidate list per rebal date
liq_rank<-list()
for(d in as.character(q_dates)){dd<-as.Date(d)
  a<-alpha[Date==dd,.(Ticker,alpha_score,confidence)];if(nrow(a)==0)next
  liq<-rd[Date<dd & Ticker%in%a$Ticker][order(Ticker,Date)]
  l20<-liq[,.(avgTV=mean(tail(TV,20),na.rm=T),admin=max(tail(AdminStock,1),0,na.rm=T),halt=max(tail(TradingHalt,1),0,na.rm=T)),by=Ticker]
  ok<-l20[avgTV>=LIQ_FLOOR & (is.na(admin)|admin==0)&(is.na(halt)|halt==0),Ticker]
  a<-a[Ticker%in%ok][order(-alpha_score)];a[,lrk:=.I];liq_rank[[d]]<-a}
cat(sprintf("[buf2] liquid ranks computed: %d dates\n",length(liq_rank)))
saveRDS(liq_rank,file.path(OUT,"liq_rank.rds"))

build_ret_dt<-function(tk,d,n=N_DAYS_COV){s<-rd[Ticker%in%tk & Date<d][order(Date)];kd<-tail(sort(unique(s$Date)),n);s[Date%in%kd & !is.na(Ret),.(Date,Ticker,Ret)]}
normw<-function(w){w<-w[!is.na(w)];if(length(w)==0||sum(w)<=0)return(NULL);w<-pmax(pmin(w,W_CAP),0);w<-w/sum(w);it<-0;while(any(w>W_CAP+1e-9)&&it<200){o<-w>W_CAP;e<-sum(w[o]-W_CAP);w[o]<-W_CAP;u<-!o&w>0;if(!any(u))break;w[u]<-w[u]+e*w[u]/sum(w[u]);w<-w/sum(w);it<-it+1};w/sum(w)}
get_w<-function(method,a,d){tk<-a$Ticker;rdt<-build_ret_dt(tk,d);tk2<-intersect(tk,unique(rdt$Ticker));if(length(tk2)<5)return(NULL);a<-a[Ticker%in%tk2]
  w<-switch(method,
    "EW"=setNames(rep(1/length(tk2),length(tk2)),tk2),
    "MVO"={rm<-dcast(rdt[Ticker%in%tk2],Date~Ticker,value.var="Ret");M<-as.matrix(rm[,-1]);M[is.na(M)]<-0;Sg<-tryCatch(cov.shrink(M,verbose=F),error=function(e)cov(M))*252;al<-setNames(a$alpha_score,a$Ticker)[colnames(M)];cf<-setNames(a$confidence,a$Ticker)[colnames(M)];ww<-tryCatch(mvo_weights(alpha=al,cov_matrix=Sg,confidence=cf,lambda=2,psi=.3,bounds=c(0,W_CAP),max_names=MAX_NAMES,min_names=15L,hhi_cap=.15,alpha_winsor=2),error=function(e)NULL);if(is.null(ww))return(NULL);v<-ww$weights%||%ww$target_weights%||%ww;if(is.list(v))v<-unlist(v);v},
    NULL);normw(w)}

buffered<-function(entry_n){held<-character(0);out<-list()
  for(d in as.character(q_dates)){a<-liq_rank[[d]];if(is.null(a))next
    keep<-intersect(held, a[lrk<=entry_n,Ticker])          # retain held while rank<=entry_n
    need<-MAX_NAMES-length(keep)
    add<-a[!(Ticker%in%keep)][order(lrk)][seq_len(min(need,.N)),Ticker]
    newset<-c(keep,add)[seq_len(min(MAX_NAMES,length(c(keep,add))))]
    out[[d]]<-a[Ticker%in%newset];held<-newset}
  out}

run_wf<-function(method,bn){
  wl<-list();for(d in names(bn)){w<-get_w(method,bn[[d]],as.Date(d));if(!is.null(w))wl[[d]]<-w}
  rb<-data.table(rebal=names(wl),start_month=sapply(names(wl),function(d)nextm(format(as.Date(d),"%Y-%m"))))[!is.na(start_month)][order(start_month)]
  out<-data.table(ym=character(),ret_net=numeric(),turnover=numeric());prev_w<-NULL;cur<-NA
  for(m in months_all){cand<-rb[start_month<=m];if(nrow(cand)==0)next;r<-cand[.N,rebal];w0<-wl[[r]];if(is.null(w0))next
    isnew<-!identical(r,cur);to<-0
    if(isnew){if(is.null(prev_w))to<-sum(abs(w0)) else{al<-union(names(prev_w),names(w0));pw<-setNames(rep(0,length(al)),al);pw[names(prev_w)]<-prev_w;nw<-setNames(rep(0,length(al)),al);nw[names(w0)]<-w0;to<-sum(abs(nw-pw))};cur<-r;w<-w0}else w<-prev_w
    gr<-mret[ym==m & Ticker%in%names(w)];if(nrow(gr)==0)next;wv<-w[gr$Ticker];wv[is.na(wv)]<-0;rg<-sum(wv*gr$mret,na.rm=T);rn<-rg-to*COST_OW
    out<-rbind(out,data.table(ym=m,ret_net=rn,turnover=to))
    g<-setNames(gr$mret,gr$Ticker)[names(w)];g[is.na(g)]<-0;w<-w*(1+g);w<-w/sum(w);prev_w<-w}
  list(wl=wl,port=out)}
st<-function(dt){dt<-merge(dt,bm_m,by="ym",all.x=T)[!is.na(bm)];rn<-dt$ret_net;ac<-rn-dt$bm;ny<-nrow(dt)/12
  list(net_sr=mean(rn)/sd(rn)*sqrt(12),ir=mean(ac)/sd(ac)*sqrt(12),ann_ret=prod(1+rn)^(12/length(rn))-1,rt_to=sum(dt$turnover)/ny,n=nrow(dt))}

cat("=== CORRECT BUFFER SWEEP (full-universe hysteresis) ===\n")
grid<-list();best_wl<-list()
for(en in c(20,30,40,50,60)){bn<-buffered(en)
  # avg name rotation
  rot<-mean(sapply(2:length(bn),function(i){a<-bn[[i-1]]$Ticker;b<-bn[[i]]$Ticker;length(setdiff(b,a))/length(b)}))
  for(mth in c("EW","MVO")){rr<-run_wf(mth,bn);s<-st(rr$port)
    grid[[paste(mth,en)]]<-data.table(method=mth,entry_n=en,rotation=round(rot,3),net_sr=round(s$net_sr,4),ir=round(s$ir,4),ann_ret=round(s$ann_ret,4),rt_to_yr=round(s$rt_to,3),to_pass=s$rt_to<=6.0)
    best_wl[[paste(mth,en)]]<-rr$wl
    cat(sprintf("  %s en=%d: rot=%.2f netSR=%.3f IR=%.3f annRet=%.1f%% RT-TO=%.2f PASS=%s\n",mth,en,rot,s$net_sr,s$ir,s$ann_ret*100,s$rt_to,s$rt_to<=6.0))}}
G<-rbindlist(grid);setorder(G,-net_sr);print(G);fwrite(G,file.path(OUT,"buffer2_sweep.csv"))
saveRDS(list(G=G,best_wl=best_wl,buffered=buffered,liq_rank=liq_rank),file.path(OUT,"opt_buffer2.rds"))
cat("\n[done buffer2]\n")
