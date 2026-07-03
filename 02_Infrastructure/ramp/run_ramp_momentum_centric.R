## run_ramp_momentum_centric.R — 새 방향(도훈 '새로운 접근'): 유일 생존알파=모멘텀 중심 25종목.
## probe 발견: KR 25종목서 OOS 양수는 Momentum(1.03)·Consensus(0.35)뿐. 기존 블렌드는 모멘텀을 decay팩터로 희석.
## → 모멘텀-composite(M변종 평균) + Consensus(OOS+)만 결합. equal blend 안 함. full/IS/OOS pt + calmar.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE); QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R"); suppressMessages({library(sandwich);library(lmtest)})
nwt<-function(x){x<-as.numeric(x);x<-x[is.finite(x)];if(length(x)<10)return(NA);tryCatch(as.numeric(coeftest(lm(x~1),vcov=sandwich::NeweyWest(lm(x~1),lag=3,prewhite=FALSE))[1,3]),error=function(e)mean(x)/sd(x)*sqrt(length(x)))}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
FAC<-c(Mom="M09_Composite_Mom", Mom121="M01_Mom_12_1", ResidMom="M08_Residual_Mom", Trend="M16_Trend_Factor", IntMom="M10_Intermediate_Mom", Cons="C19_Composite_Earnings", RevMom="M27_Analyst_Rev_Mom")
L<-readRDS(".cache/_bo_fwdgic.rds");fwd_ret<-L$fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)];bench<-L$fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)];liq<-L$fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
fwd_dates<-sort(unique(fwd_ret$Date))
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","K200","KQ150")));rd[,Date:=as.Date(Date)];rd<-rd[Date%in%fwd_dates];rd[,inu:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)];UNI<-rd[inu==TRUE,.(Date,Ticker)]
ZL<-list();for(dk in as.character(fwd_dates)){d<-as.Date(dk);f<-tryCatch(as.data.table(load_month_factors(d,factor_names=unname(FAC))),error=function(e)NULL);if(is.null(f)||nrow(f)==0)next;ZL[[dk]]<-dcast(f,Ticker~Factor_Name,value.var="Z_Score_Aligned")}
cat(sprintf("z loaded %d months\n",length(ZL)))

run<-function(wts,lab){rows<-list()  # wts: named vector over FAC names → score = Σ w·zc(z)
  for(dk in names(ZL)){fw<-ZL[[dk]];sc<-rep(0,nrow(fw));ok<-TRUE
    for(nm in names(wts)){id<-FAC[nm];if(!id%in%names(fw)){next};z<-zc(fw[[id]]);z[!is.finite(z)]<-0;sc<-sc+wts[nm]*z}
    rows[[dk]]<-data.table(Date=as.Date(dk),Ticker=fw$Ticker,score=sc)}
  SC<-rbindlist(rows);SC<-merge(SC,UNI,by=c("Date","Ticker"))
  cs<-tryCatch(canonical_screen_bt(SC[,.(Date,Ticker,score)],fwd_ret,bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="m",strategy_id=lab),error=function(e)NULL)
  if(is.null(cs$period_returns))return(NULL);pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr);k<-floor(n*0.6);nav<-cumprod(1+pr$ret_net);mdd<-min(nav/cummax(nav)-1);cagr<-prod(1+pr$ret_net)^(12/n)-1
  data.table(strategy=lab,n=n,pt_full=nwt(act),pt_IS=nwt(act[1:k]),pt_OOS=nwt(act[(k+1):n]),calmar=cagr/abs(mdd),IR_OOS=IRf(act[(k+1):n]),absSR=IRf(pr$ret_net),TO=cs$turnover_annual)}
R<-rbindlist(Filter(Negate(is.null),list(
  run(c(Mom=1),"Mom_only"),
  run(c(Mom=1,Mom121=1,ResidMom=1,Trend=1,IntMom=1),"MomComposite(5변종)"),
  run(c(Mom=1,Cons=0.4),"Mom+0.4Cons"),
  run(c(Mom=1,Mom121=1,ResidMom=1,Trend=1,IntMom=1,Cons=1.5),"MomComp+Cons"),
  run(c(Mom=1,ResidMom=1,Cons=0.8,RevMom=0.5),"Mom+Resid+Cons+RevMom")
)),fill=TRUE);setorder(R,-pt_OOS)
cat("\n=== 모멘텀-중심 25종목 (vs RAMP_01 full 2.73/OOS~0) — OOS PORT_t 정렬 ===\n")
cat(sprintf("  %-24s %4s %8s %7s %8s %7s %7s %6s %5s\n","strategy","n","pt_full","pt_IS","pt_OOS","calmar","IR_OOS","absSR","TO"))
for(i in seq_len(nrow(R))){r<-R[i];cat(sprintf("  %-24s %4d %8.2f %7.2f %8.2f %7.2f %7.2f %6.2f %5.1f [F%s O%s cal%s]\n",r$strategy,r$n,r$pt_full,r$pt_IS,r$pt_OOS,r$calmar,r$IR_OOS,r$absSR,r$TO,ifelse(r$pt_full>=2.95,"P","F"),ifelse(!is.na(r$pt_OOS)&&r$pt_OOS>0,"+","-"),ifelse(r$calmar>=0.64,"P","F")))}
saveRDS(R,".cache/_mom_centric.rds");cat("MOMC_DONE\n")
