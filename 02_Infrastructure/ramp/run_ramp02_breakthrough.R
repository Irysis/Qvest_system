## run_ramp02_breakthrough.R — RAMP_02 로직 25종목 돌파 *최대추론* 테스트 (도훈).
## 가설: composite top-25 실패(corner bet) → regime이 지목한 *집중*(sharpened/single-best)이 단일 강팩터를 잡아 살린다.
## 21팩터 per-factor view(v4 regime) → score = Σ_f softmax(view_f/τ)·z_f, τ로 composite↔single 스펙트럼.
## K200∪KQ150·top-25 EW 15bps·canonical_screen_bt 실측. z 1회 로드 후 전 모드 채점.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE); QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R"); suppressMessages({library(sandwich);library(lmtest)})
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-as.numeric(x);x<-x[is.finite(x)];if(length(x)<12)return(NA);tryCatch(as.numeric(coeftest(lm(x~1),vcov=sandwich::NeweyWest(lm(x~1),lag=3,prewhite=FALSE))[1,3]),error=function(e)mean(x)/sd(x)*sqrt(length(x)))}
oos_ret<-function(act){n<-length(act);md<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA});median(md,na.rm=TRUE)}
FACMAP<-c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size", Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
  Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability", Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets",
  LowVol="D03_RealVol", LowBeta="D02_Beta", TailRisk="R05_Tail_Risk", Liquidity="L45_Composite_Liquidity", Accrual="AC18_Accrual_Quality",
  Consensus="C19_Composite_Earnings", SUE="C01_SUE", Crowding="CR07_Momentum_Crowding", ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")

G<-readRDS(".cache/_smv4_regime_broad_m5_roll.rds"); view<-G$view; medates<-G$medates; FACN<-G$FACN; N<-length(FACN); VIEW0<-as.matrix(view[,..FACN])
L<-readRDS(".cache/_bo_fwdgic.rds");fwd_ret<-L$fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)];bench<-L$fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)];liq<-L$fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
fwd_dates<-sort(unique(fwd_ret$Date));fwd_ym<-data.table(Date=fwd_dates,ym=format(fwd_dates,"%Y-%m"))
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","K200","KQ150")));rd[,Date:=as.Date(Date)];rd<-rd[Date%in%fwd_dates];rd[,inuniv:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)];UNI<-rd[inuniv==TRUE,.(Date,Ticker)]

## z 1회 로드 (월별 ticker×factor) + view 정렬
ZL<-list()  # fwdDate -> data.table(Ticker, z columns by FACN)
for(mi in seq_along(medates)){md<-medates[mi];fd<-fwd_ym[ym==format(md,"%Y-%m")]$Date;if(length(fd)==0)next;fd<-fd[1]
  if(fd<as.Date("2009-01-01"))next; f<-tryCatch(as.data.table(load_month_factors(md,factor_names=unname(FACMAP[FACN]))),error=function(e)NULL);if(is.null(f)||nrow(f)==0)next
  fw<-dcast(f,Ticker~Factor_Name,value.var="Z_Score_Aligned");ZL[[as.character(fd)]]<-list(fd=fd,mi=mi,fw=fw)}
cat(sprintf("z loaded for %d months\n",length(ZL)))

## 모드별 스코어 → canonical
score_mode<-function(mode,tau){rows<-list()
  for(nm in names(ZL)){e<-ZL[[nm]];fw<-e$fw;v<-VIEW0[e$mi,];if(all(!is.finite(v)))next;v[!is.finite(v)]<-0
    if(mode=="composite"){a<-pmax(v,0);if(sum(a)<1e-9)a<-rep(1,N);a<-a/sum(a)}
    else if(mode=="sharp"){e2<-exp((v-max(v))/tau);a<-e2/sum(e2)}  # softmax(view/τ)
    else if(mode=="single"){a<-rep(0,N);a[which.max(v)]<-1}
    sc<-rep(0,nrow(fw));for(k in seq_len(N)){col<-FACMAP[FACN[k]];if(col%in%names(fw)){z<-fw[[col]];z[!is.finite(z)]<-0;sc<-sc+a[k]*z}}
    rows[[nm]]<-data.table(Date=e$fd,Ticker=fw$Ticker,score=sc)}
  SC<-rbindlist(rows);SC<-merge(SC,UNI,by=c("Date","Ticker"));   # K200∪KQ150
  cs<-tryCatch(canonical_screen_bt(SC[,.(Date,Ticker,score)],fwd_ret,bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="bt",strategy_id=paste0(mode,tau)),error=function(e){cat("ERR",mode,conditionMessage(e),"\n");NULL})
  if(is.null(cs$period_returns))return(NULL);pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr);nav<-cumprod(1+pr$ret_net);mdd<-min(nav/cummax(nav)-1);cagr<-prod(1+pr$ret_net)^(12/n)-1
  data.table(mode=sprintf("%s%s",mode,ifelse(mode=="sharp",sprintf("_t%.3g",tau),"")),n=n,pt=nwt(act),IR=IRf(act),calmar=cagr/abs(mdd),oos=oos_ret(act),absSR=IRf(pr$ret_net),TO=cs$turnover_annual)}
R<-rbindlist(Filter(Negate(is.null),list(
  score_mode("composite",NA), score_mode("sharp",0.1), score_mode("sharp",0.02), score_mode("sharp",0.005), score_mode("single",NA)
)),fill=TRUE)
cat("\n=== RAMP_02 돌파 (집중 스펙트럼, K200∪KQ150 top-25, vs RAMP_01 2.73 / 인덱스배분 8.91) ===\n")
cat(sprintf("  %-16s %4s %7s %6s %7s %6s %6s %5s\n","mode","n","PORT_t","IR","calmar","oos","absSR","TO"))
for(i in seq_len(nrow(R))){r<-R[i];cat(sprintf("  %-16s %4d %7.2f %6.2f %7.2f %6.2f %6.2f %5.1f [pt%s cal%s oos%s]\n",r$mode,r$n,r$pt,r$IR,r$calmar,r$oos,r$absSR,r$TO,ifelse(r$pt>=2.95,"P","F"),ifelse(r$calmar>=0.64,"P","F"),ifelse(!is.na(r$oos)&&r$oos>=0.7,"P",ifelse(!is.na(r$oos)&&r$oos>=0.5,"o","F"))))}
saveRDS(R,".cache/_bt_break.rds");cat("BREAK_DONE\n")
