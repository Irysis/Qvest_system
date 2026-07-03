# WT-D20260621_011 — C29  Holdout (2017+) + full-period + placebo for the IS-selected config
suppressMessages({library(arrow); library(data.table)})
arrow::set_cpu_count(1L); setDTthreads(1L); set.seed(20260621)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT-D20260621_011")
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
X <- readRDS(file.path(OUT,"scored.rds"))
S<-X$S; returns_dt<-X$returns_dt; bench_dt<-X$bench_dt; liq_dt<-X$liq_dt; best<-X$best
build_scores<-X$build_scores

runp <- function(sc,d0,d1,tn){
  sc<-as.data.table(sc); setkey(sc,NULL); sc<-sc[Date>=as.Date(d0)&Date<=as.Date(d1)]
  r<-returns_dt[Date>=as.Date(d0)&Date<=as.Date(d1)]; b<-bench_dt[Date>=as.Date(d0)&Date<=as.Date(d1)]
  canonical_screen_bt(sc,r,b,top_n=tn,cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8)
}
sc_best <- build_scores(S,best$A_lag,best$A_max,best$tau,best$lambda)
cat("=== IS-selected config:",sprintf("A_lag=%d A_max=%d tau=%g lambda=%g top_n=%d",
    best$A_lag,best$A_max,best$tau,best$lambda,best$top_n),"===\n")
is_r  <- runp(sc_best,"2005-01-01","2016-12-31",best$top_n)
ho_r  <- runp(sc_best,"2017-01-01","2026-06-30",best$top_n)
full_r<- runp(sc_best,"2005-01-01","2026-06-30",best$top_n)
fmt <- function(r,lab) cat(sprintf("%-10s n=%3d  pt_nw=%.3f  net_sr=%.3f  IR=%.3f  alpha_ann=%.4f  turn=%.2f\n",
    lab, r$n_months%||%NA, r$portfolio_alpha_t_nw_lag3%||%NA, r$net_sr%||%NA,
    r$information_ratio%||%NA, r$alpha_annualized%||%NA, r$turnover_annual%||%NA))
fmt(is_r,"IS 05-16"); fmt(ho_r,"HOLDOUT17+"); fmt(full_r,"FULL 05-26")
# oos_retention = holdout net_sr / IS net_sr (both negative -> retention meaningless; report raw)
cat("oos_retention (HO_sr/IS_sr):", round((ho_r$net_sr%||%NA)/(is_r$net_sr%||%NA),3),
    " [both signs:", sign(is_r$net_sr%||%0), sign(ho_r$net_sr%||%0),"]\n")

# placebo: shift inclusion months by +6 (fake inclusion) -> rebuild age and rerun full
cat("\n=== PLACEBO (inclusion months shifted +6, fake events) ===\n")
Sp <- copy(S); Sp[, age := age - 6L]   # shift fake inclusion 6 months earlier -> ages offset
sc_pl <- build_scores(Sp,best$A_lag,best$A_max,best$tau,best$lambda)
pl_r <- runp(sc_pl,"2005-01-01","2026-06-30",best$top_n)
fmt(pl_r,"PLACEBO")
cat("(true alpha would have real config different from placebo; here both negative = no catalyst signal)\n")

res <- list(is=is_r,holdout=ho_r,full=full_r,placebo=pl_r)
saveRDS(res, file.path(OUT,"holdout.rds"))

# calmar for full (approx from net_sr not enough; compute from active series)
# Build full net active series and compute calmar = CAGR/MDD on net portfolio NAV
sc<-as.data.table(sc_best); setkey(sc,NULL); sc<-sc[Date>=as.Date("2005-01-01")]
setorder(sc,Date,-score)
W<-sc[, {n<-min(best$top_n,.N); .(Ticker=Ticker[seq_len(n)],w=1/n)}, by="Date"]
W<-merge(W,liq_dt[,.(Date,Ticker,adv)],by=c("Date","Ticker"),all.x=TRUE); W<-W[is.na(adv)|adv>=2e8]
WR<-merge(W,returns_dt,by=c("Date","Ticker"),all.x=TRUE); WR[is.na(Ret_1m),Ret_1m:=0]
# traded for cost
dts<-sort(unique(W$Date)); traded<-numeric(length(dts)); names(traded)<-as.character(dts); prev<-W[0,.(Ticker,w)]
for(i in seq_along(dts)){cur<-W[Date==dts[i],.(Ticker,w)];m<-merge(cur,prev,by="Ticker",all=TRUE);
  m[is.na(w.x),w.x:=0];m[is.na(w.y),w.y:=0];traded[i]<-sum(abs(m$w.x-m$w.y));prev<-cur}
p<-WR[, .(pg=sum(w*Ret_1m)),by="Date"]; p[,cost:=traded[as.character(Date)]*15/1e4]; p[,rn:=pg-cost]
nav<-cumprod(1+p$rn); cagr<-tail(nav,1)^(12/nrow(p))-1
peak<-cummax(nav); mdd<-max(1-nav/peak)
cat(sprintf("\nFULL net portfolio: CAGR=%.3f MDD=%.3f calmar=%.3f  (calmar gate 0.64)\n",cagr,mdd,cagr/mdd))
saveRDS(list(cagr=cagr,mdd=mdd,calmar=cagr/mdd), file.path(OUT,"calmar.rds"))
cat("DONE holdout.R\n")
