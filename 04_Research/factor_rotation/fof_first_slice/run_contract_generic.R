## run_contract_generic.R <score_basename> <MODE> [tag] — 임의 슈퍼팩터 점수의 계약등급 검증.
## score parquet(Date,Ticker,score) + kns_ret_{MODE}/kns_liq_{MODE} + kns_master_bench. firewall(holdout·placebo·subperiod·graduation).
suppressPackageStartupMessages({library(data.table);library(arrow);library(sandwich);library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT<-"04_Research/factor_rotation/fof_first_slice"
a<-commandArgs(trailingOnly=TRUE); SCORE<-a[1]; MODE<-a[2]; TAG<-ifelse(length(a)>=3,a[3],SCORE)
ret_dt<-as.data.table(read_parquet(file.path(OUT,paste0("kns_ret_",MODE,".parquet"))))[,.(Date=as.Date(Date),Ticker,Ret_1m)][is.finite(Ret_1m)]
bench_dt<-as.data.table(read_parquet(file.path(OUT,"kns_master_bench.parquet")))[,.(Date=as.Date(Date),BM_Ret)][is.finite(BM_Ret)][Date %in% ret_dt$Date]
liq_dt<-as.data.table(read_parquet(file.path(OUT,paste0("kns_liq_",MODE,".parquet"))))[,.(Date=as.Date(Date),Ticker,adv)][is.finite(adv)]
MAXR<-max(ret_dt$Date)
sr<-function(x){x<-x[is.finite(x)]; if(length(x)>2&&sd(x)>0) mean(x)/sd(x)*sqrt(12) else NA_real_}
nwt<-function(v){v<-v[is.finite(v)]; if(length(v)<8) return(NA_real_); f<-lm(v~1); as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=FALSE))[1,3])}
sf<-as.data.table(read_parquet(file.path(OUT,SCORE)))[,.(Date=as.Date(Date),Ticker,score)]
supr<-sf[Date<=MAXR & is.finite(score)]
cs<-canonical_screen_bt(scores_dt=supr,returns_dt=ret_dt,bench_dt=bench_dt,top_n=25L,cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8,run_id=TAG,strategy_id=TAG)
pr<-as.data.table(cs$period_returns); pr[,date:=as.Date(date)]; setorder(pr,date); pr[,act:=ret_net-benchmark_ret]
port_t<-cs$portfolio_alpha_t_nw_lag3; net_sr<-cs$net_sr
p18<-nwt(pr[date>=as.Date("2018-01-01")]$act); ppre<-nwt(pr[date<as.Date("2018-01-01")]$act); p22<-nwt(pr[date>=as.Date("2022-01-01")]$act)
nav<-cumprod(1+pr$ret_net); dd<-1-nav/cummax(nav); mdd<-max(dd); cg<-prod(1+pr$ret_net)^(12/nrow(pr))-1; calmar<-cg/mdd
n<-nrow(pr); cut<-floor(n*0.8); reten<-sr(pr[(cut+1):n]$act)/sr(pr[1:cut]$act)
set.seed(7); pl<-c()
for(i in 1:80){ sp<-copy(supr); sp[,score:=sample(score),by=Date]
  csp<-tryCatch(canonical_screen_bt(scores_dt=sp,returns_dt=ret_dt,bench_dt=bench_dt,top_n=25L,cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8,run_id="pl",strategy_id="pl"),error=function(e) NULL)
  if(!is.null(csp)) pl<-c(pl,csp$portfolio_alpha_t_nw_lag3) }
pct<-100*mean(pl<port_t,na.rm=TRUE)
g1<-!is.na(port_t)&&port_t>=2.95; g2<-!is.na(reten)&&reten>=0.7; g3<-!is.na(calmar)&&calmar>=0.64
cat(sprintf("%s | %s | %d월 %s..%s\n",TAG,MODE,nrow(pr),as.character(min(pr$date)),as.character(max(pr$date))))
cat(sprintf("  port_t=%+.2f net_SR=%.2f CAGR=%.1f%% MDD=%.1f%% calmar=%.2f | pre2018=%+.2f 2018+=%+.2f 2022+=%+.2f | holdout_reten=%.2f | placebo=%.0f%%ile\n",
  port_t,net_sr,100*cg,100*mdd,calmar,ppre,p18,p22,reten,pct))
cat(sprintf("  ★GRAD HARD3: PORT_t≥2.95[%s] oos_reten≥0.7[%s] calmar≥0.64[%s] → %s\n",
  ifelse(g1,"PASS","FAIL"),ifelse(g2,"PASS","FAIL"),ifelse(g3,"PASS","FAIL"),ifelse(g1&&g2&&g3,"GRADUATION","screen-tier")))
