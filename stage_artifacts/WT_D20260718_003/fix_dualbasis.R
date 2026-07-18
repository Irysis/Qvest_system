## Re-extract dual-basis (EW-uni + cap-tier) with correct field names — ENS @ 2e8.
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT<-"04_Research/factor_rotation/fof_first_slice"; STG<-"stage_artifacts/WT_D20260718_003"
ret_dt<-as.data.table(read_parquet(file.path(OUT,"kns_ret_canonical.parquet")))[,.(Date=as.Date(Date),Ticker,Ret_1m)][is.finite(Ret_1m)]
bench_dt<-as.data.table(read_parquet(file.path(OUT,"kns_master_bench.parquet")))[,.(Date=as.Date(Date),BM_Ret)][is.finite(BM_Ret)][Date %in% ret_dt$Date]
liq_dt<-as.data.table(read_parquet(file.path(OUT,"kns_liq_canonical.parquet")))[,.(Date=as.Date(Date),Ticker,adv)][is.finite(adv)]
mp<-as.data.table(read_parquet(file.path(OUT,"kns_master_panel.parquet"),col_select=c("ym","Ticker","L26_Log_MktCap","K200f","KQ150f")))
setnames(mp,"L26_Log_MktCap","Size"); mp<-mp[(K200f|KQ150f)]
mp[,d1:=as.Date(paste0(ym,"-01"))]; mp[,Date:=as.Date(format(d1+31,"%Y-%m-01"))-1]
size_dt<-mp[is.finite(Size),.(Date,Ticker,Size)]
MAXR<-max(ret_dt$Date)
sf<-as.data.table(read_parquet(file.path(OUT,"scores_XATTN_canonical_ENS.parquet")))[,.(Date=as.Date(Date),Ticker,score)][Date<=MAXR&is.finite(score)]
cs<-canonical_screen_bt(scores_dt=sf,returns_dt=ret_dt,bench_dt=bench_dt,top_n=25L,cost_bps_oneway=15,
     liq_dt=liq_dt,liq_min=2e8,run_id="ENS_db",strategy_id="ENS_db",diag_dual_basis=TRUE,size_dt=size_dt)
ew<-cs$diag_ew_universe; ct<-cs$diag_cap_tier
cat(sprintf("cap-w PORT_t = %+.2f\n", cs$portfolio_alpha_t_nw_lag3))
cat("--- EW-universe diag ---\n")
cat(sprintf("  available? port_t=%s  post2017_t=%s  net_sr=%s  oos_approx=%s  IR=%s\n",
  ew$portfolio_alpha_t_nw_lag3, ew$post2017_t_nw_lag3, round(ew$net_sr,3), round(ew$oos_retention_approx,3), round(ew$information_ratio,3)))
cat("--- cap-tier weight share (avg) ---\n"); print(unlist(ct$weight_share_avg))
cat("--- cap-tier contrib gross annualized ---\n"); print(unlist(ct$contrib_gross_annualized))
write_json(list(
  cap_w_port_t=cs$portfolio_alpha_t_nw_lag3,
  ew_universe=list(port_t=ew$portfolio_alpha_t_nw_lag3, post2017_t=ew$post2017_t_nw_lag3,
                   net_sr=ew$net_sr, oos_retention_approx=ew$oos_retention_approx, ir=ew$information_ratio),
  cap_tier=list(weight_share_avg=ct$weight_share_avg, contrib_gross_annualized=ct$contrib_gross_annualized)),
  file.path(STG,"dual_basis.json"), pretty=TRUE, auto_unbox=TRUE, na="null")
cat("[SAVED] dual_basis.json\n")
