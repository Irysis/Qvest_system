# =============================================================
# Band-buffer (hysteresis) turnover reduction + re-measure SR/TO.
# keep_n=20 (target), entry_n: a held name kept until rank > entry_n; add new only if rank <= keep_n.
# Re-run forward-aligned walk-forward with buffered name set per method.
# Round-trip TO/yr = mean(per-quarter sum|dw|) * 4  (sum|dw| = buys+sells = round-trip).
# =============================================================
suppressMessages({library(data.table); library(arrow); library(quadprog); library(corpcor)})
ROOT<-"/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
OUT<-file.path(ROOT,"stage_artifacts/WT_D20260529_001_FLOW")
LOCKBOX<-as.Date("2023-12-22");COST_OW<-0.0015;MAX_NAMES<-20L;W_CAP<-0.20;LIQ_FLOOR<-2e8;N_DAYS_COV<-252L
source("02_Infrastructure/portfolio/hrp_core.R");source("02_Infrastructure/portfolio/advanced_weights.R");source("02_Infrastructure/portfolio/mean_variance_optimizer.R")
`%||%`<-function(a,b) if(is.null(a)) b else a

alpha<-as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))[Date<=LOCKBOX]
sig_dates<-sort(unique(alpha$Date))
rd<-as.data.table(read_parquet(".cache/rawdata.parquet"))[Date<=LOCKBOX,.(Date,Ticker,Ret,Close,Vol,AdminStock,TradingHalt,BM_Ret)]
rd[,TV:=Close*Vol];rd[,ym:=format(Date,"%Y-%m")];setkey(rd,Date,Ticker)
mret<-rd[!is.na(Ret),.(mret=prod(1+Ret)-1),by=.(Ticker,ym)];setkey(mret,Ticker,ym)
bm_m<-unique(rd[!is.na(BM_Ret),.(Date,BM_Ret,ym)])[,.(bm=prod(1+BM_Ret)-1),by=ym];setkey(bm_m,ym)
months_all<-sort(unique(rd$ym));nextm<-function(m){i<-match(m,months_all);if(is.na(i)||i==length(months_all))NA_character_ else months_all[i+1]}
wc<-readRDS(file.path(OUT,"opt_wcache.rds")); sel_cache<-wc$sel_cache; q_dates<-wc$q_dates

erc_w<-function(Sig,tk){n<-ncol(Sig);x<-rep(1/n,n);for(i in 1:300){mrc<-as.numeric(Sig%*%x);rc<-x*mrc;t<-mean(rc);x<-x*(t/(rc+1e-12))^.5;x<-pmax(x,1e-8);x<-x/sum(x)};setNames(x,tk)}
minvar_w<-function(Sig,tk){n<-ncol(Sig);D<-Sig+diag(1e-8,n);A<-cbind(rep(1,n),diag(n),-diag(n));b<-c(1,rep(0,n),rep(-W_CAP,n));s<-tryCatch(solve.QP(D,rep(0,n),A,b,meq=1)$solution,error=function(e)rep(1/n,n));s<-pmax(s,0);setNames(s/sum(s),tk)}
build_ret_dt<-function(tk,d,n=N_DAYS_COV){s<-rd[Ticker%in%tk & Date<d][order(Date)];kd<-tail(sort(unique(s$Date)),n);s[Date%in%kd & !is.na(Ret),.(Date,Ticker,Ret)]}
normw<-function(w){w<-w[!is.na(w)];if(length(w)==0||sum(w)<=0)return(NULL);w<-pmax(pmin(w,W_CAP),0);w<-w/sum(w);it<-0;while(any(w>W_CAP+1e-9)&&it<200){o<-w>W_CAP;e<-sum(w[o]-W_CAP);w[o]<-W_CAP;u<-!o&w>0;if(!any(u))break;w[u]<-w[u]+e*w[u]/sum(w[u]);w<-w/sum(w);it<-it+1};w/sum(w)}

# alpha rank per date (full universe, liquid only via sel_cache extends -> use full alpha rank)
alpha[,rk:=frank(-alpha_score,ties.method="first"),by=Date]

# buffered name selection: keep held names while rank<=entry_n; add top names up to keep_n
buffered_names<-function(entry_n){
  held<-character(0); out<-list()
  for(d in as.character(q_dates)){
    nm<-sel_cache[[d]]; if(is.null(nm)) next
    dd<-as.Date(d)
    ar<-alpha[Date==dd & Ticker%in%nm$Ticker]  # liquid candidates with rank within full universe
    # restrict ranks to liquid set then re-rank
    ar<-ar[order(-alpha_score)]; ar[,lrk:=.I]
    rankmap<-setNames(ar$lrk,ar$Ticker)
    cand_top<-ar$Ticker  # liquid sorted
    # keep prior held that still in liquid set and lrk<=entry_n
    keep<-intersect(held, ar[lrk<=entry_n,Ticker])
    # fill remaining from top by rank not already kept
    need<-MAX_NAMES-length(keep)
    add<-setdiff(cand_top, keep); add<-add[seq_len(min(need,length(add)))]
    newset<-c(keep,add); newset<-newset[seq_len(min(MAX_NAMES,length(newset)))]
    out[[d]]<-nm[Ticker%in%newset]
    held<-newset
  }
  out
}

get_weights<-function(method,nm,d){tk<-nm$Ticker;rdt<-build_ret_dt(tk,d);tk2<-intersect(tk,unique(rdt$Ticker));if(length(tk2)<5)return(NULL);a<-nm[Ticker%in%tk2]
  w<-switch(method,
    "EW"=setNames(rep(1/length(tk2),length(tk2)),tk2),
    "MVO"={rm<-dcast(rdt[Ticker%in%tk2],Date~Ticker,value.var="Ret");M<-as.matrix(rm[,-1]);M[is.na(M)]<-0;Sg<-tryCatch(cov.shrink(M,verbose=F),error=function(e)cov(M))*252;al<-setNames(a$alpha_score,a$Ticker)[colnames(M)];cf<-setNames(a$confidence,a$Ticker)[colnames(M)];ww<-tryCatch(mvo_weights(alpha=al,cov_matrix=Sg,confidence=cf,lambda=2,psi=.3,bounds=c(0,W_CAP),max_names=MAX_NAMES,min_names=15L,hhi_cap=.15,alpha_winsor=2),error=function(e)NULL);if(is.null(ww))return(NULL);v<-ww$weights%||%ww$target_weights%||%ww;if(is.list(v))v<-unlist(v);v},
    "ERC"={rm<-dcast(rdt[Ticker%in%tk2],Date~Ticker,value.var="Ret");M<-as.matrix(rm[,-1]);M[is.na(M)]<-0;Sg<-tryCatch(cov.shrink(M,verbose=F),error=function(e)cov(M));erc_w(Sg,colnames(M))},
    NULL); normw(w)}

run_wf<-function(wl){
  rb<-data.table(rebal=names(wl),start_month=sapply(names(wl),function(d)nextm(format(as.Date(d),"%Y-%m"))))[!is.na(start_month)][order(start_month)]
  out<-data.table(ym=character(),ret_net=numeric(),turnover=numeric());prev_w<-NULL;cur<-NA
  for(m in months_all){cand<-rb[start_month<=m];if(nrow(cand)==0)next;r<-cand[.N,rebal];w0<-wl[[r]];if(is.null(w0))next
    isnew<-!identical(r,cur);to<-0
    if(isnew){if(is.null(prev_w))to<-sum(abs(w0)) else{al<-union(names(prev_w),names(w0));pw<-setNames(rep(0,length(al)),al);pw[names(prev_w)]<-prev_w;nw<-setNames(rep(0,length(al)),al);nw[names(w0)]<-w0;to<-sum(abs(nw-pw))};cur<-r;w<-w0}else w<-prev_w
    gr<-mret[ym==m & Ticker%in%names(w)];if(nrow(gr)==0)next;wv<-w[gr$Ticker];wv[is.na(wv)]<-0;rg<-sum(wv*gr$mret,na.rm=T);rn<-rg-to*COST_OW
    out<-rbind(out,data.table(ym=m,ret_net=rn,turnover=to))
    g<-setNames(gr$mret,gr$Ticker)[names(w)];g[is.na(g)]<-0;w<-w*(1+g);w<-w/sum(w);prev_w<-w}
  out}
stats<-function(dt){dt<-merge(dt,bm_m,by="ym",all.x=T)[!is.na(bm)];rn<-dt$ret_net;ac<-rn-dt$bm
  ny<-nrow(dt)/12;rt_to<-sum(dt$turnover)/ny  # sum|dw| per yr = round-trip
  list(net_sr=mean(rn)/sd(rn)*sqrt(12),ir=mean(ac)/sd(ac)*sqrt(12),ann_ret=prod(1+rn)^(12/length(rn))-1,rt_to=rt_to,n=nrow(dt))}

cat("=== BUFFER (hysteresis) TURNOVER SWEEP — method=EW & MVO ===\n")
res_grid<-list()
for(en in c(20,25,30,35,40)){
  bn<-buffered_names(en)
  for(mth in c("EW","MVO","ERC")){
    wl<-list();for(d in names(bn)){w<-get_weights(mth,bn[[d]],as.Date(d));if(!is.null(w))wl[[d]]<-w}
    s<-stats(run_wf(wl))
    res_grid[[paste(mth,en)]]<-data.table(method=mth,entry_n=en,net_sr=round(s$net_sr,4),ir=round(s$ir,4),ann_ret=round(s$ann_ret,4),rt_to_yr=round(s$rt_to,3),to_pass=s$rt_to<=6.0)
    cat(sprintf("  %s entry_n=%d: netSR=%.3f IR=%.3f annRet=%.1f%% RT-TO=%.2f/yr PASS=%s\n",mth,en,s$net_sr,s$ir,s$ann_ret*100,s$rt_to,s$rt_to<=6.0))
  }
}
G<-rbindlist(res_grid);fwrite(G,file.path(OUT,"buffer_to_sweep.csv"))
saveRDS(list(G=G,buffered_names=buffered_names),file.path(OUT,"opt_buffer.rds"))
cat("\n[done buffer]\n")
