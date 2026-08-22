suppressPackageStartupMessages({library(data.table);library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
FAC<-c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
  Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
  Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
  Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets",
  LowVol="D03_RealVol", LowBeta="D02_Beta", TailRisk="R05_Tail_Risk",
  Liquidity="L45_Composite_Liquidity", Accrual="AC18_Accrual_Quality",
  Consensus="C19_Composite_Earnings", SUE="C01_SUE", Crowding="CR07_Momentum_Crowding",
  ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","Ret","Size","K200","KQ150")))
rd[,Date:=as.Date(Date)]; rd<-rd[Date>=as.Date("2005-01-01")&is.finite(Ret)&is.finite(Size)&Size>0]
rd[,inuniv:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)]; rd<-rd[inuniv==TRUE]
alld<-sort(unique(rd$Date)); ymv<-format(alld,"%Y-%m"); rebal<-alld[!duplicated(ymv,fromLast=TRUE)]
rebal<-rebal[rebal>=as.Date("2005-12-01")&rebal<=as.Date("2026-07-31")]
## sample: 3 consecutive month-ends per year, 2008/2012/2016/2020/2024 + 2026 (consecutive pairs -> turnover)
pick<-unlist(lapply(c(2008,2012,2016,2020,2024,2026),function(y){ ix<-which(format(rebal,"%Y")==as.character(y)); head(ix,4)}))
sel<-rebal[sort(unique(pick))]
cat("sampling",length(sel),"month-ends\n"); t0<-Sys.time()
W<-list()
for(sd in sel){ sd<-as.Date(sd,origin="1970-01-01")
  uni<-rd[Date==sd,.(Ticker,Size)]; if(nrow(uni)<30)next
  f<-tryCatch(as.data.table(load_month_factors(sd,factor_names=unname(FAC))),error=function(e)NULL)
  if(is.null(f)||nrow(f)==0){cat("  no factors",as.character(sd),"\n");next}
  fm<-merge(f,uni,by="Ticker")
  for(nm in names(FAC)){ sub<-fm[Factor_Name==FAC[nm]]; if(nrow(sub)<15)next
    thr<-quantile(sub$Z_Score_Aligned,2/3,na.rm=TRUE); s2<-sub[Z_Score_Aligned>=thr]
    W[[nm]]<-rbind(W[[nm]],data.table(rebal=sd,Ticker=s2$Ticker,w=s2$Size/sum(s2$Size))) }
  W[["Market"]]<-rbind(W[["Market"]],data.table(rebal=sd,Ticker=uni$Ticker,w=uni$Size/sum(uni$Size)))
}
cat("elapsed",round(as.numeric(difftime(Sys.time(),t0,units="secs")),1),"s\n")
## one-way turnover between consecutive sampled month-ends (only adjacent pairs)
TO<-rbindlist(lapply(names(W),function(nm){ D<-W[[nm]]; ds<-sort(unique(D$rebal)); out<-list()
  for(i in 2:length(ds)){ if(as.numeric(ds[i]-ds[i-1])>45) next
    a<-D[rebal==ds[i-1],.(Ticker,wa=w)]; b<-D[rebal==ds[i],.(Ticker,wb=w)]
    m<-merge(a,b,by="Ticker",all=TRUE); m[is.na(wa),wa:=0]; m[is.na(wb),wb:=0]
    out[[length(out)+1]]<-data.table(idx=nm,date=ds[i],ow=sum(abs(m$wb-m$wa))/2,nhold=nrow(b)) }
  rbindlist(out) }))
S<-TO[,.(mean_oneway_monthly=mean(ow),n_pairs=.N,nhold=round(mean(nhold))),by=idx][order(-mean_oneway_monthly)]
S[,ann_cost_15bps:=mean_oneway_monthly*2*0.0015*12]   # buy+sell legs, 15bps each leg
print(S,digits=3)
saveRDS(list(TO=TO,S=S),"stage_artifacts/probe_a5_20260822/adv_refute/idx_turnover.rds")
cat("\nNOTE: 지수 자체의 월간 리밸 비용은 인덱스 수익률에 전혀 반영되어 있지 않음 (ramp_shumulvey_indices.R 비용 항 부재).\n")
