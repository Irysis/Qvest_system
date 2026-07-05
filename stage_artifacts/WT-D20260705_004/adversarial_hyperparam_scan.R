# adversarial_hyperparam_scan.R — self-adversarial robustness.
# Concern: AWARE loses only because of a single bad hyperparameter (lambda/kappa/gamma),
#   OR BLIND EW wins trivially because risk-based methods are mis-tuned.
# Test: scan lambda in {2,5,10,20}, kappa in {0.5,1,2} for robust-box, gamma for est-penalty.
#   Design 1 fixed top-25 name set (SIZING isolation), full 172-common months.
# If AWARE best across ALL hyperparams still < BLIND EW, null is robust to tuning.
# NOTE: this scan is a robustness DIAGNOSTIC (self-adversarial), reported separately;
#   the primary verdict uses the pre-registered single lambda=5,kappa=1 (no cherry-pick).
suppressMessages({library(arrow); library(data.table); library(jsonlite); library(quadprog)})
setDTthreads(1); set.seed(20260705L)
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; SA<-file.path(ROOT,"stage_artifacts","WT-D20260705_004")
source(file.path(ROOT,"02_Infrastructure","contracts","backtest_result_contract.R"))
source(file.path(ROOT,"02_Infrastructure","contracts","weighted_screen_bt.R"))
MAX_W<-0.20; N<-25L; COVMIN<-24L; COVWIN<-120L; LWD<-0.3
pan<-as.data.table(read_parquet(file.path(SA,"alpha_scores.parquet"))); yms<-sort(unique(pan$ym))
bm<-as.data.table(read_parquet(file.path(ROOT,".cache","benchmark.parquet")))
bm[,ym:=format(as.Date(Date),"%Y-%m")]; bm<-bm[!is.na(BM_Ret)]
bml<-bm[,.(lr=sum(log1p(BM_Ret))),by=ym][order(ym)]; bml[,bf:=expm1(shift(lr,type="lead",n=1L))]
ym2date<-function(y) as.Date(paste0(y,"-01"))
benchdt<-bml[!is.na(bf),.(Date=ym2date(ym),BM_Ret=bf)]; rets<-pan[,.(Date=ym2date(ym),Ticker,Ret_1m=F1)]
qp<-function(m,Q,lam,ub=MAX_W){p<-length(m);Q<-(Q+t(Q))/2
  emin<-min(eigen(Q,symmetric=TRUE,only.values=TRUE)$values); if(emin<=1e-10)Q<-Q+(1e-8-min(emin,0))*diag(p)
  s<-tryCatch(solve.QP(lam*Q,as.numeric(m),cbind(rep(1,p),diag(p),-diag(p)),c(1,rep(0,p),rep(-ub,p)),meq=1),error=function(e)NULL)
  if(is.null(s))return(NULL); w<-pmin(pmax(s$solution,0),ub); if(sum(w)<1e-10)return(NULL); w/sum(w)}
tcov<-function(tks,ym_t){h<-yms[yms<ym_t]; if(length(h)>COVWIN)h<-tail(h,COVWIN); if(length(h)<COVMIN)return(NULL)
  hp<-pan[ym%in%h&Ticker%in%tks,.(ym,Ticker,F1)]; if(nrow(hp)==0)return(NULL)
  hw<-dcast(hp,ym~Ticker,value.var="F1"); mat<-as.matrix(hw[,-1,with=FALSE]); ok<-colSums(!is.na(mat))>=COVMIN
  if(sum(ok)<2)return(NULL); mk<-mat[,ok,drop=FALSE]; S<-cov(mk,use="pairwise.complete.obs"); S[!is.finite(S)]<-0
  sd_<-sqrt(pmax(diag(S),1e-10)); cc<-S/(sd_%o%sd_); cc[!is.finite(cc)]<-0; diag(cc)<-1
  rb<-mean(cc[upper.tri(cc)],na.rm=TRUE); Ft<-rb*(sd_%o%sd_); diag(Ft)<-diag(S); Ss<-(1-LWD)*S+LWD*Ft
  em<-min(eigen((Ss+t(Ss))/2,symmetric=TRUE,only.values=TRUE)$values); if(em<=1e-8)Ss<-Ss+(1e-6-min(em,0))*diag(ncol(Ss))
  dimnames(Ss)<-list(colnames(mk),colnames(mk)); Ss}
panby<-split(pan[order(ym,-mu_hat)],by="ym")
# common date set (where cov exists for top-25) — reuse: months with tcov over top-25 non-null
build_weights<-function(fn){ wl<-vector("list",length(yms))
  for(ti in seq_along(yms)){ ym_t<-yms[ti]; cur<-panby[[ym_t]]; if(is.null(cur)||nrow(cur)<N)next
    pool<-head(cur,N); Q<-tcov(pool$Ticker,ym_t); if(is.null(Q))next
    cm<-match(colnames(Q),pool$Ticker); m<-pool$mu_hat[cm]; sig<-pool$sigma_hat[cm]; tk<-pool$Ticker[cm]
    w<-fn(m,sig,Q); if(is.null(w)||any(!is.finite(w)))next
    wl[[ti]]<-data.table(Date=ym2date(ym_t),Ticker=tk,w=w/sum(w)) }
  rbindlist(wl) }
score<-function(wd,common){ wd<-wd[Date%in%common]; if(nrow(wd)==0)return(c(NA,NA))
  f<-weighted_screen_bt(wd,rets,benchdt,cost_bps_oneway=15,run_id="scan",strategy_id="scan")
  r<-weighted_screen_bt(wd[Date>=as.Date("2017-01-01")],rets,benchdt,cost_bps_oneway=15,run_id="scanr",strategy_id="scanr")
  c(f$portfolio_alpha_t_nw_lag3, r$portfolio_alpha_t_nw_lag3) }
# establish common dates via MVO(lam5) presence
ref<-build_weights(function(m,sig,Q) qp(m,Q,5)); common<-unique(ref$Date)
ew<-build_weights(function(m,sig,Q) rep(1/length(m),length(m)))  # EW over same covered names
ew_s<-score(ew,common)
cat(sprintf("BLIND EW (covered names, %d common m): full=%.4f recent=%.4f\n", length(common), ew_s[1], ew_s[2]))
grid<-data.table()
for(lam in c(2,5,10,20)){
  # BLIND MVO
  s<-score(build_weights(function(m,sig,Q) qp(m,Q,lam)),common)
  grid<-rbind(grid,data.table(method="MVO",group="BLIND",param=sprintf("lam=%g",lam),full=s[1],recent=s[2]))
  # AWARE robust-box kappa
  for(k in c(0.5,1,2)){
    s<-score(build_weights(function(m,sig,Q) qp(m-k*sig,Q,lam)),common)
    grid<-rbind(grid,data.table(method="ROBUST_BOX",group="AWARE",param=sprintf("lam=%g,k=%g",lam,k),full=s[1],recent=s[2]))
  }
  # AWARE est-penalty gamma=lam and 2*lam
  for(g in c(lam,2*lam)){
    s<-score(build_weights(function(m,sig,Q) qp(m,Q+(g/lam)*diag(sig^2),lam)),common)
    grid<-rbind(grid,data.table(method="EST_PENALTY",group="AWARE",param=sprintf("lam=%g,g=%g",lam,g),full=s[1],recent=s[2]))
  }
}
setorder(grid,-full)
cat("\n=== hyperparam scan (Design 1 sizing, common months) ===\n")
print(grid[,.(method,group,param,full=round(full,4),recent=round(recent,4))])
aware_max<-max(grid[group=="AWARE"]$full,na.rm=TRUE)
blind_max<-max(c(ew_s[1], grid[group=="BLIND"]$full),na.rm=TRUE)
cat(sprintf("\nAWARE best over ALL hyperparams = %.4f ; BLIND best (incl EW) = %.4f => %s\n",
    aware_max, blind_max, ifelse(aware_max>blind_max,"AWARE wins somewhere","AWARE never wins")))
write_json(list(ew_full=ew_s[1],ew_recent=ew_s[2],aware_max_full=aware_max,blind_max_full=blind_max,
                n_common=length(common), grid=grid), file.path(SA,"adversarial_scan.json"), auto_unbox=TRUE, na="null")
cat("[saved] adversarial_scan.json\n")
