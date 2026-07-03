## run_ramp_oos_probe_broad.R — 넓은 단일팩터 OOS 탐침 (도훈 '다른 여러 팩터 찾아봐').
## ~59팩터(모멘텀 전변종+기술적+유동성+각 패밀리 대표) 단일 top-25(K200∪KQ150 EW 15bps) full/IS/OOS PORT_t.
## 목표: 현 10팩터 밖에서 *OOS 양수 생존 알파* 발굴 → 블렌드 보강.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE); QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R"); suppressMessages({library(sandwich);library(lmtest)})
nwt<-function(x){x<-as.numeric(x);x<-x[is.finite(x)];if(length(x)<10)return(NA);tryCatch(as.numeric(coeftest(lm(x~1),vcov=sandwich::NeweyWest(lm(x~1),lag=3,prewhite=FALSE))[1,3]),error=function(e)mean(x)/sd(x)*sqrt(length(x)))}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
PROBE<-c(
 "M01_Mom_12_1","M02_Mom_6_1","M03_Mom_3_1","M05_Trended_Mom","M06_High_52w","M07_IndMom","M08_Residual_Mom","M09_Composite_Mom","M10_Intermediate_Mom","M11_ST_Reversal","M13_VolAdj_Mom","M14_RiskAdj_Mom","M16_Trend_Factor","M20_Keller_Mom","M22_Max_Return","M23_Acceleration","M24_Sector_Rel_Mom","M25_Earnings_Mom_Streak","M26_Revenue_Mom","M27_Analyst_Rev_Mom","M31_Breadth_Mom","M32_Composite_Mom_v2",
 "T01_RSI14","T05_MFI14","T06_PMA5","T07_PMA20","T08_PMA60","T13_Gap","T14_HLRange",
 "V01_BM","V02_EP","V10_FCF_Yield","V12_Composite_Value","V14_EBIT_EV","V20_SP",
 "Q01_GPA","Q07_Earnings_Stability","Q08_Composite_Quality","Q17_ROIC","Q35_CashBased_OpProf",
 "D01_IdioVol","D02_Beta","D03_RealVol","D05_MaxRet","D18_BAB_Rank","D46_Sortino",
 "L01_Amihud","L02_Turnover","L15_Turnover_252d","L45_Composite_Liquidity",
 "C01_SUE","C04_ESBR","C16_EPS_Acceleration","C19_Composite_Earnings",
 "GR07_Composite_Growth","Q21_Revenue_Growth","CR07_Momentum_Crowding","INV01_Foreign_NetBuy_20d","INV10_Smart_Money_Flow")
famof<-function(id){p<-substr(id,1,1);if(grepl("^M",id))"mom" else if(grepl("^T",id))"tech" else if(grepl("^V",id))"value" else if(grepl("^Q",id))"qual" else if(grepl("^D",id))"defense" else if(grepl("^L",id))"liq" else if(grepl("^C0|^C1",id))"cons" else if(grepl("^GR",id))"growth" else if(grepl("^CR",id))"crowd" else if(grepl("^INV",id))"flow" else "?"}

L<-readRDS(".cache/_bo_fwdgic.rds");fwd_ret<-L$fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)];bench<-L$fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)];liq<-L$fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
fwd_dates<-sort(unique(fwd_ret$Date))
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","K200","KQ150")));rd[,Date:=as.Date(Date)];rd<-rd[Date%in%fwd_dates];rd[,inu:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)];UNI<-rd[inu==TRUE,.(Date,Ticker)]
ZL<-list();for(dk in as.character(fwd_dates)){d<-as.Date(dk);f<-tryCatch(as.data.table(load_month_factors(d,factor_names=PROBE)),error=function(e)NULL);if(is.null(f)||nrow(f)==0)next;ZL[[dk]]<-dcast(f,Ticker~Factor_Name,value.var="Z_Score_Aligned")}
cat(sprintf("z loaded %d months\n",length(ZL)))

probe1<-function(id){rows<-list();for(dk in names(ZL)){fw<-ZL[[dk]];if(!id%in%names(fw))next;rows[[dk]]<-data.table(Date=as.Date(dk),Ticker=fw$Ticker,score=fw[[id]])}
  if(length(rows)==0)return(NULL);SC<-rbindlist(rows);SC<-SC[is.finite(score)];SC<-merge(SC,UNI,by=c("Date","Ticker"));if(nrow(SC)<100)return(NULL)
  cs<-tryCatch(canonical_screen_bt(SC[,.(Date,Ticker,score)],fwd_ret,bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="p",strategy_id=id),error=function(e)NULL)
  if(is.null(cs$period_returns))return(NULL);pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr);k<-floor(n*0.6)
  data.table(factor=id,fam=famof(id),n=n,pt_full=nwt(act),pt_IS=nwt(act[1:k]),pt_OOS=nwt(act[(k+1):n]),IR_full=IRf(act),TO=cs$turnover_annual)}
R<-rbindlist(Filter(Negate(is.null),lapply(PROBE,probe1)),fill=TRUE);setorder(R,-pt_OOS)
cat(sprintf("\n=== 넓은 단일팩터 OOS 탐침 (%d팩터 측정) — OOS PORT_t 상위 ===\n",nrow(R)))
cat(sprintf("  %-22s %-7s %4s %8s %7s %8s %7s %5s\n","factor","fam","n","pt_full","pt_IS","pt_OOS","IR_full","TO"))
for(i in seq_len(min(30,nrow(R)))){r<-R[i];cat(sprintf("  %-22s %-7s %4d %8.2f %7.2f %8.2f %7.2f %5.1f %s\n",r$factor,r$fam,r$n,r$pt_full,r$pt_IS,r$pt_OOS,r$IR_full,r$TO,ifelse(!is.na(r$pt_OOS)&&r$pt_OOS>0.5,"★",ifelse(!is.na(r$pt_OOS)&&r$pt_OOS>0,"+",""))))}
cat(sprintf("\nOOS>0.5 생존자(%d): %s\n",sum(R$pt_OOS>0.5,na.rm=T),paste(R[pt_OOS>0.5,factor],collapse=", ")))
cat(sprintf("OOS>0 (%d): %s\n",sum(R$pt_OOS>0,na.rm=T),paste(R[pt_OOS>0,factor],collapse=", ")))
cat("\n패밀리별 평균 OOS PORT_t:\n");fs<-R[,.(mean_oos=round(mean(pt_OOS,na.rm=T),2),max_oos=round(max(pt_OOS,na.rm=T),2),n=.N),by=fam][order(-mean_oos)];for(i in seq_len(nrow(fs)))cat(sprintf("  %-8s mean %+.2f  max %+.2f  (n=%d)\n",fs$fam[i],fs$mean_oos[i],fs$max_oos[i],fs$n[i]))
saveRDS(R,".cache/_oos_probe_broad.rds");cat("BROADPROBE_DONE\n")
