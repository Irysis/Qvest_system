## R35 supplementary — lag1 PIT-stress + placebo on PURE SP EW-basis track (C-timing check)
suppressPackageStartupMessages({library(arrow); library(data.table); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260715_004"); R31 <- file.path(QM,"stage_artifacts/WT_D20260714_007")
B04 <- file.path(QM,"stage_artifacts/WT_D20260714_004")
source(file.path(QM,"02_Infrastructure/contracts/canonical_screen_bt.R"))
nw_t<-function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<8)return(NA_real_);fit<-lm(x~1)
  se<-sqrt(NeweyWest(fit,lag=lag,prewhite=FALSE)[1,1]);unname(coef(fit)[1]/se)}
SP7<-as.data.table(read_parquet(file.path(R31,"subaxis_panels.parquet")));SP7[,Date:=as.Date(Date)]
SI<-readRDS(file.path(B04,"screen_inputs.rds")); FR<-SI$fwd_ret[,.(Date,Ticker,Ret_1m)]; bench<-SI$bench; liqf<-SI$liqf
SPDT<-SP7[is.finite(SP),.(Date,Ticker,score=SP)]
ew_pt<-function(dt){r<-canonical_screen_bt(dt,FR,bench,top_n=25L,cost_bps_oneway=15,
  liq_dt=liqf[,.(Date,Ticker,adv)],liq_min=2e8,run_id="s",strategy_id="s",diag_dual_basis=TRUE)
  c(capw=r$portfolio_alpha_t_nw_lag3, ewuni=r$diag_ew_universe$portfolio_alpha_t_nw_lag3)}
base<-ew_pt(SPDT)
## lag1: use prior-month score (staler) — if signal collapses, we relied on fresh info (fine, PIT-safe);
##   if it INFLATES on fresher/same-month timing vs lag1, suspect leak. Report both.
dts<-sort(unique(SPDT$Date)); nxt<-data.table(Date=dts[-length(dts)],Date_use=dts[-1])
SPlag<-merge(SPDT,nxt,by="Date"); SPlag<-SPlag[,.(Date=Date_use,Ticker,score)]  # score of M applied at M+1
lag1<-ew_pt(SPlag)
cat(sprintf("[SP EW] base   cap-w=%.3f ew-uni=%.3f\n",base["capw"],base["ewuni"]))
cat(sprintf("[SP EW] lag1   cap-w=%.3f ew-uni=%.3f  (staler score; graceful decay=PIT-ok, no same-month inflation)\n",lag1["capw"],lag1["ewuni"]))
## placebo: shuffle scores within month, N=60
set.seed(35); null_ewuni<-numeric(60)
for(b in 1:60){SPp<-copy(SPDT)[,score:=sample(score),by=Date]; null_ewuni[b]<-ew_pt(SPp)["ewuni"]}
p_emp<-mean(null_ewuni>=base["ewuni"]); cat(sprintf("[SP EW] placebo(N=60 within-month shuffle): real ew-uni=%.3f null max=%.3f p_emp=%.3f\n",
  base["ewuni"],max(null_ewuni,na.rm=TRUE),p_emp))
saveRDS(list(base=base,lag1=lag1,placebo_p=p_emp,null_max=max(null_ewuni)),file.path(WT,"r35_pitstress.rds"))
cat("R35_PITSTRESS_DONE\n")
