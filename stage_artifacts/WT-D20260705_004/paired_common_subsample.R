# paired_common_subsample.R — like-for-like ΔPORT_t on COMMON months.
# Risk-based methods run only where trailing cov exists (172m); EW runs 196m.
# For a fair paired A/B, restrict EW (and all) to the common date set of each design,
# and recompute PORT_t. This removes the "EW gets 24 extra early months" confound.
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1)
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; SA<-file.path(ROOT,"stage_artifacts","WT-D20260705_004")
source(file.path(ROOT,"02_Infrastructure","contracts","backtest_result_contract.R"))
source(file.path(ROOT,"02_Infrastructure","contracts","weighted_screen_bt.R"))

pan<-as.data.table(read_parquet(file.path(SA,"alpha_scores.parquet"))); yms<-sort(unique(pan$ym))
bm<-as.data.table(read_parquet(file.path(ROOT,".cache","benchmark.parquet")))
bm[,ym:=format(as.Date(Date),"%Y-%m")]; bm<-bm[!is.na(BM_Ret)]
bm_lr<-bm[,.(lr=sum(log1p(BM_Ret))),by=ym][order(ym)]; bm_lr[,bm_fwd:=expm1(shift(lr,type="lead",n=1L))]
ym2date<-function(y) as.Date(paste0(y,"-01"))
benchdt<-bm_lr[!is.na(bm_fwd),.(Date=ym2date(ym),BM_Ret=bm_fwd)]
rets<-pan[,.(Date=ym2date(ym),Ticker,Ret_1m=F1)]

wls<-readRDS(file.path(SA,"weights_lists.rds"))
methods<-c("EW","MVO","HRP","ERC","MINVAR","ROBUST_BOX","EST_PENALTY","BL_SHRINK","RESAMPLED")
blind<-c("EW","MVO","HRP","ERC","MINVAR")
RECENT_LO<-as.Date("2017-01-01")

eval_common <- function(wl, tag){
  wds<-setNames(lapply(methods,function(mm) rbindlist(wl[[mm]])), methods)
  # common dates = intersection of all non-empty methods' dates
  ds<-Reduce(intersect, lapply(wds[sapply(wds,nrow)>0], function(x) as.character(unique(x$Date))))
  common<-as.Date(ds)
  ev<-function(mm){ wd<-wds[[mm]][Date %in% common]; if(nrow(wd)==0) return(NULL)
    f<-weighted_screen_bt(wd,rets,benchdt,cost_bps_oneway=15,run_id=paste0(tag,mm,"c"),strategy_id=paste0(tag,mm,"c"))
    r<-weighted_screen_bt(wd[Date>=RECENT_LO],rets,benchdt,cost_bps_oneway=15,run_id=paste0(tag,mm,"cr"),strategy_id=paste0(tag,mm,"cr"))
    data.table(method=mm,group=ifelse(mm%in%blind,"BLIND","AWARE"),
               full_port_t=f$portfolio_alpha_t_nw_lag3, full_net_sr=f$net_sr, full_turnover=f$turnover_annual,
               recent_port_t=r$portfolio_alpha_t_nw_lag3, full_n=f$n_months) }
  res<-rbindlist(lapply(methods,ev)); setorder(res,-full_port_t)
  cat(sprintf("\n=== %s COMMON %d months ===\n", tag, length(common)))
  print(res[,.(method,group,full_port_t=round(full_port_t,4),full_net_sr=round(full_net_sr,4),
               full_turnover=round(full_turnover,2),recent_port_t=round(recent_port_t,4),full_n)])
  bb<-res[group=="BLIND"][which.max(full_port_t)]; ab<-res[group=="AWARE"][which.max(full_port_t)]
  cat(sprintf("[%s] BLIND best=%s(%.4f) AWARE best=%s(%.4f) dPORT_t full=%.4f recent=%.4f => %s\n",
      tag,bb$method,bb$full_port_t,ab$method,ab$full_port_t,
      ab$full_port_t-bb$full_port_t, ab$recent_port_t-bb$recent_port_t,
      ifelse(ab$full_port_t-bb$full_port_t>0,"AWARE wins","AWARE does NOT win")))
  list(res=res, blind_best=as.list(bb), aware_best=as.list(ab),
       delta_full=ab$full_port_t-bb$full_port_t, delta_recent=ab$recent_port_t-bb$recent_port_t,
       n_common=length(common))
}
c1<-eval_common(wls$d1, "D1_sizing")
c2<-eval_common(wls$d2, "D2_selsize")
write_json(list(D1_sizing_common=c1[c("blind_best","aware_best","delta_full","delta_recent","n_common")],
                D2_selsize_common=c2[c("blind_best","aware_best","delta_full","delta_recent","n_common")]),
           file.path(SA,"paired_common_summary.json"), auto_unbox=TRUE, na="null")
fwrite(rbind(c1$res[,design:="D1_common"], c2$res[,design:="D2_common"]), file.path(SA,"paired_common_results.csv"))
cat("\n[saved] paired_common_results.csv + paired_common_summary.json\n")
