suppressMessages({library(data.table);library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/factor_rotation/fof_first_slice")
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/contracts/canonical_screen_bt.R")
me<-function(ym){d<-as.Date(paste0(ym,"-01"));as.Date(format(d+32,"%Y-%m-01"))-1}
M<-as.data.table(read_parquet("kns_master_panel.parquet",col_select=c("ym","Ticker","F1","adv","K200f","KQ150f","bad","nret")))
M[,Date:=me(ym)]
cb<-as.data.table(read_parquet("C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/benchmark.parquet"))
cb[,ym:=format(as.Date(Date),"%Y-%m")]
bm_real<-cb[,.(BM_real=prod(1+BM_Ret)-1),by=ym];setorder(bm_real,ym)
bm_real[,ym_signal:=format(as.Date(paste0(ym,"-01"))-1,"%Y-%m")]
bench_dt<-bm_real[,.(Date=me(ym_signal),BM_Ret=BM_real)]
returns_dt<-M[!is.na(F1),.(Date,Ticker,Ret_1m=F1)];liq_dt<-M[,.(Date,Ticker,adv)]

## ADVERSARIAL CHECK 1: ensemble variance-reduction artifact?
## Compare ensemble port_t vs (a) mean of per-seed port_t, (b) single-seed avg active SERIES then t.
## If ensemble t >> because averaging kills idiosyncratic-active variance (not adding alpha), the
## mean-active should be ~unchanged but sd drops. Report mean-active & sd for canonical.
Mc<-M[(K200f|KQ150f)]
seeds<-c("scores_XATTN_canonical.parquet",Sys.glob("scores_XATTN_canonical_s*.parquet"))
ens<-as.data.table(read_parquet("scores_XATTN_canonical_ENS.parquet"));ens[,Date:=as.Date(Date)]
getactive<-function(S){
  S<-as.data.table(S);S[,Date:=as.Date(Date)]
  r<-canonical_screen_bt(S[,.(Date,Ticker,score)],returns_dt,bench_dt,top_n=25L,cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8)
  pr<-as.data.table(r$period_returns);pr[,active:=ret_net-benchmark_ret];pr
}
ma<-numeric();sa<-numeric()
for(sf in seeds){pr<-getactive(read_parquet(sf));ma<-c(ma,mean(pr$active));sa<-c(sa,sd(pr$active))}
pre<-getactive(ens)
cat(sprintf("ADV1 canonical: per-seed mean-active=%.5f (avg) sd-active=%.5f (avg)\n",mean(ma),mean(sa)))
cat(sprintf("ADV1 canonical: ENSEMBLE mean-active=%.5f sd-active=%.5f (n=%d)\n",mean(pre$active),sd(pre$active),nrow(pre)))
cat(sprintf("ADV1: ensemble mean-active / per-seed avg mean = %.2f  (>1 => ensemble adds signal, ~1 => pure var-reduction)\n",mean(pre$active)/mean(ma)))

## ADVERSARIAL CHECK 2: look-ahead sanity via benchmark offset toggle.
## Re-run canonical ensemble with WRONG (concurrent, lag0) bench alignment. If port_t barely moves,
## the benchmark isn't binding. If it inflates massively at wrong lag, confirms our fix matters.
bench_wrong<-bm_real[,.(Date=me(ym),BM_Ret=BM_real)]  # concurrent (realized-month labeled = wrong for signal)
r_wrong<-canonical_screen_bt(ens[,.(Date,Ticker,score)],returns_dt,bench_wrong,top_n=25L,cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8)
cat(sprintf("ADV2 canonical ens: CORRECT-bench port_t=%.2f  vs WRONG(lag0)-bench port_t=%.2f\n",
            NA,r_wrong$portfolio_alpha_t_nw_lag3))
