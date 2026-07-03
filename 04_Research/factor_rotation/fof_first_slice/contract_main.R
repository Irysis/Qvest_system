suppressPackageStartupMessages({library(data.table);library(arrow);library(sandwich);library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM); source("02_Infrastructure/contracts/canonical_screen_bt.R")
O<-"04_Research/factor_rotation/fof_first_slice"; a<-commandArgs(trailingOnly=TRUE); SCORE<-a[1]; M<-a[2]; TAG<-a[3]
sr<-function(x){x<-x[is.finite(x)]; if(length(x)>2&&sd(x)>0) mean(x)/sd(x)*sqrt(12) else NA_real_}
nwt<-function(v){v<-v[is.finite(v)]; if(length(v)<8) return(NA_real_); f<-lm(v~1); as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=FALSE))[1,3])}
sf<-as.data.table(read_parquet(file.path(O,SCORE)))[,.(Date=as.Date(Date),Ticker,score)]
ret<-as.data.table(read_parquet(file.path(O,paste0("kns_ret_",M,".parquet"))))[,.(Date=as.Date(Date),Ticker,Ret_1m)][is.finite(Ret_1m)]
bench<-as.data.table(read_parquet(file.path(O,"kns_master_bench.parquet")))[,.(Date=as.Date(Date),BM_Ret)][is.finite(BM_Ret)][Date %in% ret$Date]
liq<-as.data.table(read_parquet(file.path(O,paste0("kns_liq_",M,".parquet"))))[,.(Date=as.Date(Date),Ticker,adv)][is.finite(adv)]
supr<-sf[Date<=max(ret$Date)&is.finite(score)]
cs<-canonical_screen_bt(scores_dt=supr,returns_dt=ret,bench_dt=bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="x",strategy_id="x")
pr<-as.data.table(cs$period_returns); pr[,date:=as.Date(date)]; setorder(pr,date); pr[,act:=ret_net-benchmark_ret]
nav<-cumprod(1+pr$ret_net); dd<-1-nav/cummax(nav); mdd<-max(dd); cg<-prod(1+pr$ret_net)^(12/nrow(pr))-1; calmar<-cg/mdd
n<-nrow(pr); cut<-floor(n*0.8); reten<-sr(pr[(cut+1):n]$act)/sr(pr[1:cut]$act)
g1<-cs$portfolio_alpha_t_nw_lag3>=2.95; g3<-!is.na(calmar)&&calmar>=0.64; g2<-!is.na(reten)&&reten>=0.7
cat(sprintf("%-16s %-9s | port_t=%+.2f net_SR=%.2f CAGR=%.1f%% MDD=%.1f%% calmar=%.2f | pre2018=%+.2f 2018+=%+.2f 2022+=%+.2f | oos=%.2f | GRAD[%s%s%s]->%s\n",
  TAG,M,cs$portfolio_alpha_t_nw_lag3,cs$net_sr,100*cg,100*mdd,calmar,
  nwt(pr[date<as.Date("2018-01-01")]$act),nwt(pr[date>=as.Date("2018-01-01")]$act),nwt(pr[date>=as.Date("2022-01-01")]$act),
  reten,ifelse(g1,"P","F"),ifelse(g2,"P","F"),ifelse(g3,"P","F"),ifelse(g1&&g2&&g3,"GRAD","screen")))
