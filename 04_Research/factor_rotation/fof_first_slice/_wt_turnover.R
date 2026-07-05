suppressMessages({library(data.table);library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/factor_rotation/fof_first_slice")
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/contracts/canonical_screen_bt.R")
me<-function(ym){d<-as.Date(paste0(ym,"-01"));as.Date(format(d+32,"%Y-%m-01"))-1}
M<-as.data.table(read_parquet("kns_master_panel.parquet",col_select=c("ym","Ticker","F1","adv","K200f","KQ150f")))
M[,Date:=me(ym)]
cb<-as.data.table(read_parquet("C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/benchmark.parquet"));cb[,ym:=format(as.Date(Date),"%Y-%m")]
bm<-cb[,.(BM_real=prod(1+BM_Ret)-1),by=ym];setorder(bm,ym);bm[,ym_signal:=format(as.Date(paste0(ym,"-01"))-1,"%Y-%m")]
bench_dt<-bm[,.(Date=me(ym_signal),BM_Ret=BM_real)]
returns_dt<-M[!is.na(F1),.(Date,Ticker,Ret_1m=F1)];liq_dt<-M[,.(Date,Ticker,adv)]
# smoothed score: 3-month EMA of ensemble to cut turnover
for(MODE in c("canonical","allliq")){
  ens<-as.data.table(read_parquet(sprintf("scores_XATTN_%s_ENS.parquet",MODE)));ens[,Date:=as.Date(Date)]
  setorder(ens,Ticker,Date)
  ens[,score_sm:=frollmean(score,3,align="right",na.rm=TRUE),by=Ticker];ens[is.na(score_sm),score_sm:=score]
  r0<-canonical_screen_bt(ens[,.(Date,Ticker,score)],returns_dt,bench_dt,25L,15,liq_dt,2e8)
  r1<-canonical_screen_bt(ens[,.(Date,Ticker,score=score_sm)],returns_dt,bench_dt,25L,15,liq_dt,2e8)
  cat(sprintf("%s raw: port_t=%.2f turn=%.0f%%  | 3M-smoothed: port_t=%.2f turn=%.0f%%\n",
      MODE,r0$portfolio_alpha_t_nw_lag3,100*r0$turnover_annual,r1$portfolio_alpha_t_nw_lag3,100*r1$turnover_annual))
}
