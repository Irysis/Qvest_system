## run_ramp_alpha_oos_probe.R — 결정적 질문: KR 25종목서 *OOS 양수* 알파원이 있나?
## 정보/이벤트 팩터(갱신=decay덜함: Consensus·SUE·리비전·외국인플로우·어닝모멘텀) vs characteristic(value/quality/mom, decay).
## 각 단일팩터 top-25(K200∪KQ150 EW 15bps canonical) → full/IS(첫60%)/OOS(끝40%) PORT_t. decay 안 한 seed 탐색.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE); QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R"); suppressMessages({library(sandwich);library(lmtest)})
nwt<-function(x){x<-as.numeric(x);x<-x[is.finite(x)];if(length(x)<10)return(NA);tryCatch(as.numeric(coeftest(lm(x~1),vcov=sandwich::NeweyWest(lm(x~1),lag=3,prewhite=FALSE))[1,3]),error=function(e)mean(x)/sd(x)*sqrt(length(x)))}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
## 정보/이벤트(refresh) vs characteristic(decay) — 부호 라벨
PROBE<-c(Consensus="C19_Composite_Earnings", SUE="C01_SUE", RevBreadth="C13_Revision_Breadth_3m", OPRev="C17_OP_Revision",
  ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow", EarnMomStreak="M25_Earnings_Mom_Streak",
  AnalystRevMom="M27_Analyst_Rev_Mom", Value="V12_Composite_Value", Quality="Q08_Composite_Quality", Momentum="M09_Composite_Mom")
KIND<-c(Consensus="info",SUE="info",RevBreadth="info",OPRev="info",ForeignFlow="info",SmartMoney="info",EarnMomStreak="info",AnalystRevMom="info",Value="char",Quality="char",Momentum="char")

L<-readRDS(".cache/_bo_fwdgic.rds");fwd_ret<-L$fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)];bench<-L$fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)];liq<-L$fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
fwd_dates<-sort(unique(fwd_ret$Date));fwd_ym<-data.table(Date=fwd_dates,ym=format(fwd_dates,"%Y-%m"))
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","K200","KQ150")));rd[,Date:=as.Date(Date)];rd<-rd[Date%in%fwd_dates];rd[,inu:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)];UNI<-rd[inu==TRUE,.(Date,Ticker)]

## z 1회 로드 (월별)
ZL<-list()
for(dk in as.character(fwd_dates)){ d<-as.Date(dk); f<-tryCatch(as.data.table(load_month_factors(d,factor_names=unname(PROBE))),error=function(e)NULL);if(is.null(f)||nrow(f)==0)next
  ZL[[dk]]<-dcast(f,Ticker~Factor_Name,value.var="Z_Score_Aligned") }
cat(sprintf("z loaded %d months\n",length(ZL)))

probe1<-function(nm){id<-PROBE[nm];rows<-list()
  for(dk in names(ZL)){fw<-ZL[[dk]];if(!id%in%names(fw))next;rows[[dk]]<-data.table(Date=as.Date(dk),Ticker=fw$Ticker,score=fw[[id]])}
  if(length(rows)==0){cat("  no coverage:",nm,"\n");return(NULL)}
  SC<-rbindlist(rows);SC<-SC[is.finite(score)];SC<-merge(SC,UNI,by=c("Date","Ticker"));if(nrow(SC)<100)return(NULL)
  cs<-tryCatch(canonical_screen_bt(SC[,.(Date,Ticker,score)],fwd_ret,bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="p",strategy_id=nm),error=function(e)NULL)
  if(is.null(cs$period_returns))return(NULL);pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr);k<-floor(n*0.6)
  data.table(factor=nm,kind=KIND[nm],n=n,pt_full=nwt(act),pt_IS=nwt(act[1:k]),pt_OOS=nwt(act[(k+1):n]),IR_full=IRf(act),IR_OOS=IRf(act[(k+1):n]),TO=cs$turnover_annual)}
R<-rbindlist(Filter(Negate(is.null),lapply(names(PROBE),probe1)),fill=TRUE);setorder(R,-pt_OOS)
cat("\n=== KR 25종목 단일팩터 OOS 탐침 (decay 안 한 알파원?) — OOS PORT_t 정렬 ===\n")
cat(sprintf("  %-15s %-5s %4s %8s %7s %8s %7s %8s %5s\n","factor","kind","n","pt_full","pt_IS","pt_OOS","IR_full","IR_OOS","TO"))
for(i in seq_len(nrow(R))){r<-R[i];cat(sprintf("  %-15s %-5s %4d %8.2f %7.2f %8.2f %7.2f %8.2f %5.1f %s\n",r$factor,r$kind,r$n,r$pt_full,r$pt_IS,r$pt_OOS,r$IR_full,r$IR_OOS,r$TO,ifelse(!is.na(r$pt_OOS)&&r$pt_OOS>0,"← OOS+","")))}
info_oos<-R[kind=="info",mean(pt_OOS,na.rm=T)];char_oos<-R[kind=="char",mean(pt_OOS,na.rm=T)]
cat(sprintf("\n평균 OOS PORT_t: 정보팩터 %.2f vs characteristic %.2f\n",info_oos,char_oos))
cat(sprintf("OOS 양수 팩터: %d/%d\n",sum(R$pt_OOS>0,na.rm=T),nrow(R)))
saveRDS(R,".cache/_alpha_oos_probe.rds");cat("PROBE_DONE\n")
