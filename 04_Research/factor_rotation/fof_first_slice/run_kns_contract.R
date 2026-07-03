## run_kns_contract.R MODE — 모드 유니버스 KNS 슈퍼팩터 계약등급 검증(canonical_screen_bt top-25 long-only).
## 입력: kns_scores_{L2,PCsparse}_{MODE}.parquet + kns_ret_{MODE}/kns_liq_{MODE} + kns_master_bench. firewall(holdout·placebo·subperiod·graduation).
suppressPackageStartupMessages({library(data.table);library(arrow);library(sandwich);library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT<-"04_Research/factor_rotation/fof_first_slice"
MODE<-commandArgs(trailingOnly=TRUE)[1]; if(is.na(MODE)) MODE<-"allclean"
con<-file(file.path(OUT,paste0("_kns_contract_",MODE,".txt")),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
w(sprintf("======== KNS 계약등급 [%s] (전종목 실험, 2005-2026.06) ========  %s",MODE,as.character(Sys.time())))
ret_dt<-as.data.table(read_parquet(file.path(OUT,paste0("kns_ret_",MODE,".parquet"))))[,.(Date=as.Date(Date),Ticker,Ret_1m)][is.finite(Ret_1m)]
bench_dt<-as.data.table(read_parquet(file.path(OUT,"kns_master_bench.parquet")))[,.(Date=as.Date(Date),BM_Ret)][is.finite(BM_Ret)][Date %in% ret_dt$Date]
liq_dt<-as.data.table(read_parquet(file.path(OUT,paste0("kns_liq_",MODE,".parquet"))))[,.(Date=as.Date(Date),Ticker,adv)][is.finite(adv)]
MAXR<-max(ret_dt$Date)
sr<-function(a){a<-a[is.finite(a)]; if(length(a)>2&&sd(a)>0) mean(a)/sd(a)*sqrt(12) else NA_real_}
nwt<-function(v){v<-v[is.finite(v)]; if(length(v)<8) return(NA_real_); f<-lm(v~1); as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=FALSE))[1,3])}
run_one<-function(tag,fn){
  sf<-as.data.table(read_parquet(file.path(OUT,fn)))[,.(Date=as.Date(Date),Ticker,score)]
  supr<-sf[Date<=MAXR & is.finite(score)]
  cs<-canonical_screen_bt(scores_dt=supr,returns_dt=ret_dt,bench_dt=bench_dt,top_n=25L,cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8,run_id=paste0("KNS_",MODE,"_",tag),strategy_id=paste0("KNS_",MODE,"_",tag))
  pr<-as.data.table(cs$period_returns); pr[,date:=as.Date(date)]; setorder(pr,date); pr[,act:=ret_net-benchmark_ret]
  port_t<-cs$portfolio_alpha_t_nw_lag3; net_sr<-cs$net_sr
  p18<-nwt(pr[date>=as.Date("2018-01-01")]$act); ppre<-nwt(pr[date<as.Date("2018-01-01")]$act)
  nav<-cumprod(1+pr$ret_net); dd<-1-nav/cummax(nav); mdd<-max(dd); cg<-prod(1+pr$ret_net)^(12/nrow(pr))-1; calmar<-cg/mdd
  n<-nrow(pr); cut<-floor(n*0.8); isv<-pr[1:cut]; ho<-pr[(cut+1):n]; reten<-sr(ho$act)/sr(isv$act)
  set.seed(7); pl<-c()
  for(i in 1:80){ sp<-copy(supr); sp[,score:=sample(score),by=Date]
    csp<-tryCatch(canonical_screen_bt(scores_dt=sp,returns_dt=ret_dt,bench_dt=bench_dt,top_n=25L,cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8,run_id="pl",strategy_id="pl"),error=function(e) NULL)
    if(!is.null(csp)) pl<-c(pl,csp$portfolio_alpha_t_nw_lag3) }
  pct<-100*mean(pl<port_t,na.rm=TRUE)
  g1<-!is.na(port_t)&&port_t>=2.95; g2<-!is.na(reten)&&reten>=0.7; g3<-!is.na(calmar)&&calmar>=0.64
  w(sprintf("\n===== [%s|%s] top-25 EW long-only (%d월 %s..%s) =====",MODE,tag,nrow(pr),as.character(min(pr$date)),as.character(max(pr$date))))
  w(sprintf("  port_t=%+.2f net_SR=%.2f CAGR=%.1f%% MDD=%.1f%% calmar=%.2f | pre2018 t=%+.2f 2018+ t=%+.2f | holdout reten=%.2f | placebo %.0f%%ile | GRAD[PORTt %s|oos %s|calmar %s]=%s",
    port_t,net_sr,100*cg,100*mdd,calmar,ppre,p18,reten,pct,ifelse(g1,"P","F"),ifelse(g2,"P","F"),ifelse(g3,"P","F"),ifelse(g1&&g2&&g3,"GRAD","screen")))
  cat(sprintf("%s|%s port_t=%.2f net_SR=%.2f calmar=%.2f reten=%.2f p18=%.2f placebo=%.0f MDD=%.1f\n",MODE,tag,port_t,net_sr,calmar,reten,p18,pct,100*mdd))
  list(port_t=port_t,supr=sf,pr=pr)
}
rL2<-run_one("L2",paste0("kns_scores_L2_",MODE,".parquet"))
rPC<-run_one("PCsparse",paste0("kns_scores_PCsparse_",MODE,".parquet"))
best<-if(!is.na(rL2$port_t)&&(is.na(rPC$port_t)||rL2$port_t>=rPC$port_t)) rL2 else rPC
btag<-if(identical(best,rL2))"L2" else "PCsparse"
jun<-best$supr[Date==max(Date)][order(-score)][1:25]
jun<-merge(jun,liq_dt[Date==max(liq_dt$Date),.(Ticker,adv)],by="Ticker",all.x=TRUE)[order(-score)]
w(sprintf("\n2026-06 top-25 (%s, EW): %s",btag,paste(head(jun$Ticker,25),collapse=" ")))
close(con); cat("KNS_CONTRACT_DONE_",MODE,"\n",sep="")
