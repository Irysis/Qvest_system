## run_ramp_oos_probe_fwl.R — 도훈 '다른 여러 팩터에도 FWL 적용'. 각 팩터 raw vs FWL(size+sector 중립화) OOS 비교.
## 어떤 팩터가 size/sector 정화로 OOS 개선(=변장한 size/beta였음) vs 손해(=raw가 net기여)인지 판별.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE); QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R"); suppressMessages({library(sandwich);library(lmtest)})
nwt<-function(x){x<-as.numeric(x);x<-x[is.finite(x)];if(length(x)<10)return(NA);tryCatch(as.numeric(coeftest(lm(x~1),vcov=sandwich::NeweyWest(lm(x~1),lag=3,prewhite=FALSE))[1,3]),error=function(e)mean(x)/sd(x)*sqrt(length(x)))}
PROBE<-c("M05_Trended_Mom","M32_Composite_Mom_v2","M09_Composite_Mom","M13_VolAdj_Mom","M24_Sector_Rel_Mom","M01_Mom_12_1","M08_Residual_Mom","M26_Revenue_Mom","M10_Intermediate_Mom","M11_ST_Reversal",
 "C04_ESBR","C19_Composite_Earnings","C01_SUE","C16_EPS_Acceleration",
 "V01_BM","V02_EP","V12_Composite_Value","V14_EBIT_EV","V20_SP",
 "Q01_GPA","Q07_Earnings_Stability","Q08_Composite_Quality","Q17_ROIC","Q35_CashBased_OpProf",
 "D01_IdioVol","D03_RealVol","D05_MaxRet","D46_Sortino","GR07_Composite_Growth","Q21_Revenue_Growth","L45_Composite_Liquidity")
# size/liq 계열은 size-중립화 degenerate → 표기만
SIZELIKE<-c("S01_Size","S02_Float_Size","L45_Composite_Liquidity","L01_Amihud","L02_Turnover","L26_Log_MktCap")
L<-readRDS(".cache/_bo_fwdgic.rds");fwd_ret<-L$fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)];bench<-L$fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)];liq<-L$fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
fwd_dates<-sort(unique(fwd_ret$Date))
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","K200","KQ150","Size","Sector")));rd[,Date:=as.Date(Date)];rd<-rd[Date%in%fwd_dates]
rd[,inu:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)];UNI<-rd[inu==TRUE,.(Date,Ticker)];CTRL<-rd[,.(Date,Ticker,Size,Sector)]
ZL<-list();for(dk in as.character(fwd_dates)){d<-as.Date(dk);f<-tryCatch(as.data.table(load_month_factors(d,factor_names=PROBE)),error=function(e)NULL);if(is.null(f)||nrow(f)==0)next;ZL[[dk]]<-dcast(f,Ticker~Factor_Name,value.var="Z_Score_Aligned")}
cat(sprintf("z loaded %d months\n",length(ZL)))

## FWL 잔차 버전(전 팩터 size+sector 중립화)
ZLf<-list();for(dk in names(ZL)){fw<-ZL[[dk]];m<-merge(fw,CTRL[Date==as.Date(dk),.(Ticker,Size,Sector)],by="Ticker")
  if(nrow(m)<20){ZLf[[dk]]<-fw;next};X<-model.matrix(~log(pmax(Size,1))+factor(Sector),data=m);cols<-setdiff(names(fw),"Ticker")
  for(cc in cols){y<-m[[cc]];ok<-is.finite(y)&apply(X,1,function(r)all(is.finite(r)));if(sum(ok)<20)next;b<-tryCatch(qr.solve(X[ok,,drop=FALSE],y[ok]),error=function(e)NULL);if(is.null(b))next;res<-y;res[ok]<-y[ok]-as.numeric(X[ok,,drop=FALSE]%*%b);m[[cc]]<-res}
  ZLf[[dk]]<-m[,.SD,.SDcols=c("Ticker",cols)]}
cat("FWL residualized\n")

probe1<-function(Zx,id){rows<-list();for(dk in names(Zx)){fw<-Zx[[dk]];if(!id%in%names(fw))next;rows[[dk]]<-data.table(Date=as.Date(dk),Ticker=fw$Ticker,score=fw[[id]])}
  if(length(rows)==0)return(NA);SC<-rbindlist(rows);SC<-SC[is.finite(score)];SC<-merge(SC,UNI,by=c("Date","Ticker"));if(nrow(SC)<100)return(NA)
  cs<-tryCatch(canonical_screen_bt(SC[,.(Date,Ticker,score)],fwd_ret,bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="p",strategy_id=id),error=function(e)NULL)
  if(is.null(cs$period_returns))return(NA);pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr);k<-floor(n*0.6)
  c(full=nwt(act),oos=nwt(act[(k+1):n]))}
R<-rbindlist(lapply(PROBE,function(id){raw<-probe1(ZL,id);fwl<-probe1(ZLf,id)
  data.table(factor=id,raw_full=raw["full"],raw_oos=raw["oos"],fwl_full=fwl["full"],fwl_oos=fwl["oos"],d_oos=fwl["oos"]-raw["oos"],sizelike=id%in%SIZELIKE)}),fill=TRUE)
setorder(R,-d_oos)
cat("\n=== raw vs FWL(size+sector 중립화) OOS PORT_t — Δoos(FWL−raw) 정렬 ===\n")
cat(sprintf("  %-22s %8s %8s %8s %8s %8s\n","factor","raw_full","raw_oos","fwl_full","fwl_oos","Δoos"))
for(i in seq_len(nrow(R))){r<-R[i];cat(sprintf("  %-22s %8.2f %8.2f %8.2f %8.2f %+8.2f %s\n",r$factor,r$raw_full,r$raw_oos,r$fwl_full,r$fwl_oos,r$d_oos,ifelse(isTRUE(r$sizelike),"(size계열)",ifelse(!is.na(r$d_oos)&&r$d_oos>0.3,"← FWL개선",ifelse(!is.na(r$d_oos)&&r$d_oos< -0.3,"← FWL악화","")))))}
nb<-R[sizelike==FALSE];cat(sprintf("\nFWL 개선(Δoos>0.3): %d/%d | 악화(<−0.3): %d | 평균 Δoos(비-size): %+.2f\n",sum(nb$d_oos>0.3,na.rm=T),nrow(nb),sum(nb$d_oos< -0.3,na.rm=T),mean(nb$d_oos,na.rm=T)))
saveRDS(R,".cache/_oos_probe_fwl.rds");cat("FWLPROBE_DONE\n")
