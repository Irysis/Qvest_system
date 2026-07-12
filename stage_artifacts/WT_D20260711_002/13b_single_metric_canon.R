#==============================================================================
# WT-D20260711_002 Phase A — Step 13b: canonical for each single metric (family)
# n_trials accounting: 7-metric family (preregistered). PRIMARY = composite (13).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260711_002")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
ym2date <- function(ym) as.Date(sprintf("%d-%02d-01", ym%/%100L, ym%%100L))
ym_add <- function(ym, k){ y<-ym%/%100L; m<-ym%%100L; t<-(y*12L+(m-1L))+k; (t%/%12L)*100L+(t%%12L)+1L }

P <- readRDS(file.path(OUT,"signal_panel.rds"))
mp <- readRDS(file.path(OUT,"monthly_panel.rds")); me<-mp$me; bench<-mp$bench_m
ret_at_t  <- me[, .(Ticker, ym=ym_add(ym,-1L), Ret_1m=mret)]
bench_at_t<- bench[, .(ym=ym_add(ym,-1L), BM_Ret=bench_mret)]
returns_all <- ret_at_t[, .(Date=ym2date(ym), Ticker, Ret_1m)]
bench_all   <- bench_at_t[, .(Date=ym2date(ym), BM_Ret)]
size_all <- me[, .(Date=ym2date(ym), Ticker, Size)]
liq_all  <- me[, .(Date=ym2date(ym), Ticker, adv=adv20)]

# per-month cross-sectional z for each metric, score = -z (higher metric = more obfuscated = short)
zc <- function(v){ s<-sd(v,na.rm=TRUE); if(!is.finite(s)||s<=0) return(rep(0,length(v))); (v-mean(v,na.rm=TRUE))/s }
run_metric <- function(mcol, tag, dsub){
  Q <- P[is.finite(get(mcol))]
  Q[, z := zc(get(mcol)), by=ym]
  sc <- Q[, .(Date=ym2date(ym), Ticker, score=-z)]
  sc <- sc[Date %in% dsub]
  canonical_screen_bt(sc, returns_all, bench_all, top_n=25L, cost_bps_oneway=15,
    liq_dt=liq_all, liq_min=2e8, size_dt=size_all, diag_dual_basis=TRUE,
    run_id=paste0("wt002_",mcol,"_",tag), strategy_id=paste0(mcol,"_",tag))
}
alldates <- sort(unique(ym2date(P$ym)))
is_d  <- alldates[alldates <  as.Date("2019-01-01")]
oos_d <- alldates[alldates >= as.Date("2019-01-01")]
metrics <- c("m1","m2","m3","m4","m5","m6")
tab <- rbindlist(lapply(metrics, function(mm){
  cf<-run_metric(mm,"full",alldates); ci<-run_metric(mm,"IS",is_d); co<-run_metric(mm,"OOS",oos_d)
  data.table(metric=mm,
    port_t_full=cf$portfolio_alpha_t_nw_lag3, ir_full=cf$information_ratio, sr_full=cf$net_sr,
    turn_full=cf$turnover_annual, ew_t_full=cf$diag_ew_universe$portfolio_alpha_t_nw_lag3,
    ew_post2017=cf$diag_ew_universe$post2017_t_nw_lag3,
    port_t_IS=ci$portfolio_alpha_t_nw_lag3, port_t_OOS=co$portfolio_alpha_t_nw_lag3,
    mega_w=cf$diag_cap_tier$weight_share_avg$MEGA, mid_w=cf$diag_cap_tier$weight_share_avg$MID,
    other_w=cf$diag_cap_tier$weight_share_avg$OTHER)
}))
cat("[13b] === single-metric canonical (score=-metric, top25 EW 15bps liq2e8, cap-w authoritative) ===\n")
print(tab, digits=3)
saveRDS(tab, file.path(OUT,"single_metric_canon.rds"))
# also m1 canonical full object for charts (best single)
m1_full <- run_metric("m1","full",alldates)
saveRDS(m1_full, file.path(OUT,"canon_m1_full.rds"))
cat("[13b] DONE\n")
