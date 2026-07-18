## WT-D20260718_003 Alpha — XATTN canonical measurement (angle ②: liq-robust + orthogonality)
## Deployment universe (K200∪KQ150 = "canonical"). Reuses frozen XATTN 5-seed scores (Jul 5).
## Outputs: per-seed PORT_t, liq-sweep {2e8,1e9,5e9}, dual-basis, cap-tier, ENS active returns.
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT<-"04_Research/factor_rotation/fof_first_slice"
STG<-"stage_artifacts/WT_D20260718_003"
sr<-function(x){x<-x[is.finite(x)]; if(length(x)>2&&sd(x)>0) mean(x)/sd(x)*sqrt(12) else NA_real_}
irf<-function(a){a<-a[is.finite(a)]; if(length(a)>2&&sd(a)>0) mean(a)/sd(a)*sqrt(12) else NA_real_}

ret_dt<-as.data.table(read_parquet(file.path(OUT,"kns_ret_canonical.parquet")))[,.(Date=as.Date(Date),Ticker,Ret_1m)][is.finite(Ret_1m)]
bench_dt<-as.data.table(read_parquet(file.path(OUT,"kns_master_bench.parquet")))[,.(Date=as.Date(Date),BM_Ret)][is.finite(BM_Ret)][Date %in% ret_dt$Date]
liq_dt<-as.data.table(read_parquet(file.path(OUT,"kns_liq_canonical.parquet")))[,.(Date=as.Date(Date),Ticker,adv)][is.finite(adv)]
MAXR<-max(ret_dt$Date)

# size_dt from master panel (ym->month-end Date), canonical universe
mp<-as.data.table(read_parquet(file.path(OUT,"kns_master_panel.parquet"),
     col_select=c("ym","Ticker","L26_Log_MktCap","K200f","KQ150f")))
setnames(mp,"L26_Log_MktCap","Size")
mp<-mp[(K200f|KQ150f)]
# convert ym (YYYY-MM) to month-end Date to match scores (2010-01-31 style)
mp[,d1:=as.Date(paste0(ym,"-01"))]
mp[,Date:=as.Date(format(d1+31,"%Y-%m-01"))-1]
size_dt<-mp[is.finite(Size),.(Date,Ticker,Size)]

run_one<-function(scorefile, liq_min, tag, dual=TRUE){
  sf<-as.data.table(read_parquet(file.path(OUT,scorefile)))[,.(Date=as.Date(Date),Ticker,score)]
  supr<-sf[Date<=MAXR & is.finite(score)]
  cs<-canonical_screen_bt(scores_dt=supr,returns_dt=ret_dt,bench_dt=bench_dt,top_n=25L,
        cost_bps_oneway=15,liq_dt=liq_dt,liq_min=liq_min,run_id=tag,strategy_id=tag,
        diag_dual_basis=dual,size_dt=if(dual) size_dt else NULL)
  pr<-as.data.table(cs$period_returns); pr[,date:=as.Date(date)]; setorder(pr,date); pr[,act:=ret_net-benchmark_ret]
  nav<-cumprod(1+pr$ret_net); dd<-1-nav/cummax(nav); mdd<-max(dd)
  cg<-prod(1+pr$ret_net)^(12/nrow(pr))-1; calmar<-cg/mdd
  n<-nrow(pr); cut<-floor(n*0.8); reten<-sr(pr[(cut+1):n]$act)/sr(pr[1:cut]$act)
  list(cs=cs, pr=pr, port_t=cs$portfolio_alpha_t_nw_lag3, net_sr=cs$net_sr,
       cagr=cg, mdd=mdd, calmar=calmar, reten=reten, nmonths=n,
       p18=irf(pr[date>=as.Date("2018-01-01")]$act)*1, # placeholder
       diag_ew=cs$diag_ew_universe, diag_cap=cs$diag_cap_tier)
}

cat("=== A) LIQ-THRESHOLD SWEEP — XATTN ensemble (deployment universe) ===\n")
sweep<-list()
for(lm in c(2e8,1e9,5e9)){
  r<-run_one("scores_XATTN_canonical_ENS.parquet", lm, sprintf("XATTN_ENS_liq%.0e",lm))
  sweep[[as.character(lm)]]<-r
  ew_pt<-if(!is.null(r$diag_ew) && isTRUE(r$diag_ew$available)) r$diag_ew$port_t_nw_lag3 else NA
  ew_p17<-if(!is.null(r$diag_ew) && isTRUE(r$diag_ew$available)) r$diag_ew$post2017_t_nw_lag3 else NA
  cat(sprintf("  liq_min=%.0e | port_t(cap-w)=%+.2f net_SR=%.2f CAGR=%.1f%% MDD=%.1f%% calmar=%.2f oos=%.2f n=%d | EW-uni port_t=%+.2f post2017=%+.2f\n",
      lm, r$port_t, r$net_sr, 100*r$cagr, 100*r$mdd, r$calmar, r$reten, r$nmonths, ew_pt, ew_p17))
}

cat("\n=== B) SEED DISCIPLINE — 5 seeds @ liq 2e8 (cap-w PORT_t) ===\n")
seedfiles<-c(s0="scores_XATTN_canonical.parquet",s1="scores_XATTN_canonical_s1.parquet",
             s2="scores_XATTN_canonical_s2.parquet",s3="scores_XATTN_canonical_s3.parquet",
             s4="scores_XATTN_canonical_s4.parquet")
seedres<-list()
for(nm in names(seedfiles)){
  r<-run_one(seedfiles[[nm]], 2e8, paste0("XATTN_",nm), dual=FALSE)
  seedres[[nm]]<-c(port_t=r$port_t, oos=r$reten, calmar=r$calmar,
                   p2022=irf(r$pr[date>=as.Date("2022-01-01")]$act))
  cat(sprintf("  %s | port_t=%+.2f oos=%.2f calmar=%.2f 2022+active_IR=%+.2f\n",
      nm, r$port_t, r$reten, r$calmar, irf(r$pr[date>=as.Date("2022-01-01")]$act)))
}
pt_vec<-sapply(seedres,function(x)x["port_t"])
cat(sprintf("  >> seed PORT_t: mean=%+.2f sd=%.2f min=%+.2f max=%+.2f (mean judgment)\n",
    mean(pt_vec),sd(pt_vec),min(pt_vec),max(pt_vec)))

cat("\n=== C) CAP-TIER decomposition (ENS @ 2e8) ===\n")
dc<-sweep[["2e+08"]]$diag_cap
if(!is.null(dc) && isTRUE(dc$available)){
  print(dc$tier_share_of_holdings)
  cat("  contrib gross annualized by tier:\n"); print(dc$contrib_gross_annualized)
} else cat("  cap-tier unavailable:", if(!is.null(dc)) dc$note else "NULL","\n")

# Save ENS active returns for orthogonality
ens_pr<-sweep[["2e+08"]]$pr[,.(date, ret_net, benchmark_ret, act)]
fwrite(ens_pr, file.path(STG,"xattn_ens_active_returns.csv"))

# Save summary json
summ<-list(
  pin_inputs="XATTN_scores_Jul5 + kns_ret/liq/bench_Jul3 (frozen)",
  liq_sweep=lapply(names(sweep),function(k){r<-sweep[[k]];list(
     liq_min=k, port_t_capw=r$port_t, net_sr=r$net_sr, cagr=r$cagr, mdd=r$mdd,
     calmar=r$calmar, oos_retention=r$reten, n_months=r$nmonths,
     ew_uni_port_t=if(!is.null(r$diag_ew)&&isTRUE(r$diag_ew$available)) r$diag_ew$port_t_nw_lag3 else NA,
     ew_uni_post2017_t=if(!is.null(r$diag_ew)&&isTRUE(r$diag_ew$available)) r$diag_ew$post2017_t_nw_lag3 else NA)}),
  seed_port_t=as.list(round(pt_vec,3)),
  seed_port_t_mean=mean(pt_vec), seed_port_t_sd=sd(pt_vec),
  cap_tier=if(!is.null(dc)&&isTRUE(dc$available)) dc$tier_share_of_holdings else "unavailable"
)
write_json(summ, file.path(STG,"canonical_measurement.json"), pretty=TRUE, auto_unbox=TRUE, na="null")
cat("\n[SAVED] canonical_measurement.json + xattn_ens_active_returns.csv\n")
