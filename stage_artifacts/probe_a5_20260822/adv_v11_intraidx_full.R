QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
FAC<-c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
   Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
   Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
   Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets",
   LowVol="D03_RealVol", LowBeta="D02_Beta", TailRisk="R05_Tail_Risk",
   Liquidity="L45_Composite_Liquidity", Accrual="AC18_Accrual_Quality",
   Consensus="C19_Composite_Earnings", SUE="C01_SUE", Crowding="CR07_Momentum_Crowding",
   ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")
rd<-as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Size","K200","KQ150")))
rd[,Date:=as.Date(Date)]; rd<-rd[is.finite(Size)&Size>0]
rd[,inuniv:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)]; rd<-rd[inuniv==TRUE]
alld<-sort(unique(rd$Date)); ymv<-format(alld,"%Y-%m"); me<-alld[!duplicated(ymv,fromLast=TRUE)]
me<-me[me>=as.Date("2007-01-01") & me<=as.Date("2026-05-31")]
set.seed(11); anchors<-sort(sample(seq_along(me)[-length(me)], 12))
res<-list()
for(ai in anchors){ d1<-me[ai]; d2<-me[ai+1]
  u1<-rd[Date==d1,.(Ticker,Size)]; u2<-rd[Date==d2,.(Ticker,Size)]
  f1<-tryCatch(as.data.table(load_month_factors(d1,factor_names=unname(FAC))),error=function(e)NULL)
  f2<-tryCatch(as.data.table(load_month_factors(d2,factor_names=unname(FAC))),error=function(e)NULL)
  if(is.null(f1)||is.null(f2)) next
  m1<-merge(f1,u1,by="Ticker"); m2<-merge(f2,u2,by="Ticker")
  tw<-function(a,b){ wa<-a$Size/sum(a$Size); names(wa)<-a$Ticker; wb<-b$Size/sum(b$Size); names(wb)<-b$Ticker
    at<-union(names(wa),names(wb)); va<-wa[at]; vb<-wb[at]; va[is.na(va)]<-0; vb[is.na(vb)]<-0
    0.5*sum(abs(vb-va)) }
  for(nm in names(FAC)){ s1<-m1[Factor_Name==FAC[nm]]; s2<-m2[Factor_Name==FAC[nm]]
    if(nrow(s1)<15||nrow(s2)<15) next
    a<-s1[Z_Score_Aligned>=quantile(s1$Z_Score_Aligned,2/3,na.rm=TRUE)]
    b<-s2[Z_Score_Aligned>=quantile(s2$Z_Score_Aligned,2/3,na.rm=TRUE)]
    res[[length(res)+1]]<-data.table(d=d2,idx=nm,oneway=tw(a,b)) }
  res[[length(res)+1]]<-data.table(d=d2,idx="Market",oneway=tw(u1,u2))
  cat("."); flush.console() }
cat("\n")
R<-rbindlist(res); S<-R[,.(n=.N,mo=mean(oneway),ann=mean(oneway)*12,drag=mean(oneway)*12*0.0015*100),by=idx]
setorder(S,-mo); print(S,digits=4)
fwrite(S,"stage_artifacts/probe_a5_20260822/adv_intraindex_turnover_full.csv")
