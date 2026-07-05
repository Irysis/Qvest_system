suppressMessages({library(data.table);library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/factor_rotation/fof_first_slice")
me<-function(ym){d<-as.Date(paste0(ym,"-01"));as.Date(format(d+32,"%Y-%m-01"))-1}
M<-as.data.table(read_parquet("kns_master_panel.parquet",col_select=c("ym","Ticker","adv","K200f","KQ150f")))
M[,Date:=me(ym)];Mc<-M[(K200f|KQ150f)]
ens<-as.data.table(read_parquet("scores_XATTN_canonical_ENS.parquet"));ens[,Date:=as.Date(Date)]
al<-readRDS("_wt_alpha.rds")
d6<-max(ens$Date);cat("latest signal Date:",as.character(d6),"\n")
D6<-merge(ens[Date==d6,.(Date,Ticker,score)],Mc[Date==d6,.(Date,Ticker,adv)],by=c("Date","Ticker"))
cat("merged rows:",nrow(D6),"\n")
if(nrow(D6)>0){
  D6[,zscore:=(score-mean(score))/sd(score)]
  D6[,alpha_active_hat:=al$beta_lb*zscore]
  setorder(D6,-alpha_active_hat)
  cat("as-of 2026-06 top-15 (Ticker alpha adv_bil):\n")
  print(head(D6[,.(Ticker,alpha=round(alpha_active_hat,4),adv_bil=round(adv/1e8,1))],15))
  cat("N:",nrow(D6),"top25 min adv bil:",round(sort(head(D6,25)$adv)[1]/1e8,2),"\n")
  saveRDS(D6,"_wt_asof06.rds")
}
