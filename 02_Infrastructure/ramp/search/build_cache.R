## build_cache.R — 8-구성요소 탐색 공유캐시 (도훈 goal). 1회 로드 → 수천 config 평가에 재사용.
## 24팩터 z(raw) + 팩터별 월간 active·rank-IC + 국면신호 5종 + fwd/bench/liq/universe + book월수익. → .cache/_search_cache.rds
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE); QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
expz<-function(v){z<-rep(0,length(v));for(i in seq_along(v)){p<-v[1:i];p<-p[is.finite(p)];if(length(p)>=12){s<-sd(p);if(!is.na(s)&&s>1e-8)z[i]<-(v[i]-mean(p))/s}};z}
to_m<-function(dt,dc,vc){d<-copy(as.data.table(dt));d[,D:=as.Date(get(dc))];d<-d[!is.na(D)];d[,ym:=format(D,"%Y-%m")];d[,.(v=last(get(vc))),by=ym]}

FAC<-c(M05_Trended_Mom="M05_Trended_Mom",M32_CompMomV2="M32_Composite_Mom_v2",M09_CompMom="M09_Composite_Mom",M13_VolAdjMom="M13_VolAdj_Mom",M24_SectorRelMom="M24_Sector_Rel_Mom",
  M01_Mom121="M01_Mom_12_1",M08_ResidMom="M08_Residual_Mom",M16_Trend="M16_Trend_Factor",M26_RevMom="M26_Revenue_Mom",M10_IntMom="M10_Intermediate_Mom",M14_RiskAdjMom="M14_RiskAdj_Mom",
  M11_Reversal="M11_ST_Reversal",C04_ESBR="C04_ESBR",C19_CompEarn="C19_Composite_Earnings",C01_SUE="C01_SUE",
  V12_Value="V12_Composite_Value",V02_EP="V02_EP",Q08_Quality="Q08_Composite_Quality",Q07_EarnStab="Q07_Earnings_Stability",
  D03_RealVol="D03_RealVol",D02_Beta="D02_Beta",S01_Size="S01_Size",GR07_Growth="GR07_Composite_Growth",L45_Liq="L45_Composite_Liquidity")
FN<-names(FAC)
L<-readRDS(".cache/_bo_fwdgic.rds");fwd_ret<-as.data.table(L$fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)];bench<-as.data.table(L$fwd$bench_dt)[,.(Date=as.Date(Date),BM_Ret)];liq<-as.data.table(L$fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]
fwd_dates<-sort(unique(fwd_ret$Date))
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","K200","KQ150","Size","Sector")));rd[,Date:=as.Date(Date)];rd<-rd[Date%in%fwd_dates]
rd[,inu:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)];UNI<-rd[inu==TRUE,.(Date,Ticker)];CTRL<-rd[,.(Date,Ticker,Size,Sector)]
cat("loading z...\n")
ZL<-list();for(dk in as.character(fwd_dates)){d<-as.Date(dk);f<-tryCatch(as.data.table(load_month_factors(d,factor_names=unname(FAC))),error=function(e)NULL);if(is.null(f)||nrow(f)==0)next;ZL[[dk]]<-dcast(f,Ticker~Factor_Name,value.var="Z_Score_Aligned")}
dts<-as.Date(names(ZL)); ND<-length(dts); cat(sprintf("z loaded %d months\n",ND))

## 팩터별 월간 active(top-tercile EW − BM) + rank-IC (universe 내)
ACT<-matrix(NA_real_,ND,length(FN),dimnames=list(NULL,FN)); IC<-matrix(NA_real_,ND,length(FN),dimnames=list(NULL,FN))
for(i in seq_len(ND)){dk<-names(ZL)[i];fw<-ZL[[dk]];uni<-UNI[Date==dts[i]]$Ticker;fr<-fwd_ret[Date==dts[i]]
  for(j in seq_along(FN)){id<-FAC[FN[j]];if(!id%in%names(fw))next;sub<-data.table(Ticker=fw$Ticker,z=fw[[id]])[is.finite(z)&Ticker%in%uni]
    sub<-merge(sub,fr[,.(Ticker,Ret_1m)],by="Ticker");if(nrow(sub)<15)next
    sel<-sub[z>=quantile(z,2/3,na.rm=T)]$Ticker;rsel<-sub[Ticker%in%sel,Ret_1m];br<-bench[Date==dts[i],BM_Ret]
    if(length(rsel)>=5)ACT[i,j]<-mean(rsel,na.rm=T)-ifelse(length(br),br,0)
    if(nrow(sub)>=20&&sd(sub$z)>0&&sd(sub$Ret_1m)>0)IC[i,j]<-cor(sub$z,sub$Ret_1m,method="spearman")}}
cat("factor active + IC built\n")

## 국면신호 5종 → 월간 expanding-z (membership 재료)
SIG<-data.table(Date=dts)
gg<-function(file,col){m<-tryCatch(to_m(read_parquet(file),"Date",col),error=function(e)NULL);if(is.null(m))return(rep(0,ND));mm<-merge(data.table(ym=format(dts,"%Y-%m")),m,by="ym",all.x=TRUE);expz(mm$v)}
SIG[,cascade:=gg(".cache/unified_regime_signal_daily.parquet","Regime_Score_smooth")]
SIG[,msm:=gg(".cache/msm_daily_latest.parquet","Crisis_Prob")]
SIG[,mrs9:=gg(".cache/regime_daily_v2.parquet","MRS")]
bmv<-merge(data.table(Date=dts),bench,by="Date",all.x=TRUE)$BM_Ret;vol<-rep(NA_real_,ND);for(i in 7:ND)vol[i]<-sd(bmv[max(1,i-5):i],na.rm=T);SIG[,vol:=expz(vol)]
tr<-rep(0,ND);for(i in 13:ND)tr[i]<-mean(bmv[(i-12):(i-1)],na.rm=T);SIG[,trend:=expz(tr)]
cat("regime signals built\n")

## book 월간 (target + book-marginal)
b<-fread("06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2_monthly.csv");b[,ym:=format(as.Date(eval_date),"%Y-%m")]
bm<-merge(data.table(ym=format(dts,"%Y-%m"),Date=dts),b[,.(ym,book=port_ret_gross_recon)],by="ym",all.x=TRUE)

saveRDS(list(FAC=FAC,FN=FN,dts=dts,ND=ND,ZL=ZL,ACT=ACT,IC=IC,SIG=SIG,fwd_ret=fwd_ret,bench=bench,liq=liq,UNI=UNI,CTRL=CTRL,book=bm$book),
  ".cache/_search_cache.rds")
cat(sprintf("CACHE_DONE  factors=%d months=%d (%s~%s)\n",length(FN),ND,as.character(min(dts)),as.character(max(dts))))
