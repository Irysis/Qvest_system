suppressPackageStartupMessages({library(data.table);library(arrow);library(sandwich);library(lmtest)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
FAC<-c(Value="V12_Composite_Value",Issuance="V21_Composite_Equity_Issuance",Size="S01_Size",
 Momentum="M09_Composite_Mom",ResidMom="M08_Residual_Mom",Reversal="M11_ST_Reversal",
 Quality="Q08_Composite_Quality",GPA="Q01_GPA",EarnStab="Q07_Earnings_Stability",
 Growth="GR07_Composite_Growth",Investment="IN06_Investment_to_Assets",LowVol="D03_RealVol",
 LowBeta="D02_Beta",TailRisk="R05_Tail_Risk",Liquidity="L45_Composite_Liquidity",
 Accrual="AC18_Accrual_Quality",Consensus="C19_Composite_Earnings",SUE="C01_SUE",
 Crowding="CR07_Momentum_Crowding",ForeignFlow="INV01_Foreign_NetBuy_20d",SmartMoney="INV10_Smart_Money_Flow")
Z<-readRDS("stage_artifacts/probe_a5_20260822/adv_refute/adv_core.rds"); mon<-Z$mon; fac<-Z$fac; S<-Z$S12
NM<-nrow(mon); NAx<-1+length(fac); RET<-as.matrix(mon[,c("Market",fac),with=FALSE]); RET[!is.finite(RET)]<-0
arm<-function(freq){ W<-matrix(NA_real_,NM,NAx); wprev<-rep(1/NAx,NAx); wcur<-NULL
 for(m in 13:NM){ d<-m-1
  if(is.null(wcur)||((m-13)%%freq==0)){s<-S[d,];pos<-which(is.finite(s)&s>0);w<-rep(0,NAx)
   if(length(pos)==0)w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); wcur<-w}
  W[m,]<-wcur; ri<-RET[m,]; wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev}; W}
WA5<-arm(3); WC1<-arm(1); colnames(WA5)<-colnames(WC1)<-c("Market",fac)
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","Ret","Size","K200","KQ150")))
rd[,Date:=as.Date(Date)]; rd<-rd[Date>=as.Date("2005-01-01")&is.finite(Ret)&is.finite(Size)&Size>0]
rd[,inuniv:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)]; rd<-rd[inuniv==TRUE]
alld<-sort(unique(rd$Date)); ymv<-format(alld,"%Y-%m"); rebal<-alld[!duplicated(ymv,fromLast=TRUE)]
rebal<-rebal[rebal>=as.Date("2005-12-01")&rebal<=as.Date("2026-07-31")]
pick<-unlist(lapply(c(2008,2012,2016,2020,2024,2026),function(y){ix<-which(format(rebal,"%Y")==as.character(y));head(ix,4)}))
sel<-as.Date(rebal[sort(unique(pick))],origin="1970-01-01")
IW<-list()
for(sd in sel){ sd<-as.Date(sd,origin="1970-01-01"); uni<-rd[Date==sd,.(Ticker,Size)]
 f<-tryCatch(as.data.table(load_month_factors(sd,factor_names=unname(FAC))),error=function(e)NULL); if(is.null(f))next
 fm<-merge(f,uni,by="Ticker"); L<-list()
 for(nm in names(FAC)){ sub<-fm[Factor_Name==FAC[nm]]; if(nrow(sub)<15)next
  thr<-quantile(sub$Z_Score_Aligned,2/3,na.rm=TRUE); s2<-sub[Z_Score_Aligned>=thr]
  L[[nm]]<-data.table(Ticker=s2$Ticker,w=s2$Size/sum(s2$Size)) }
 L[["Market"]]<-data.table(Ticker=uni$Ticker,w=uni$Size/sum(uni$Size)); IW[[as.character(sd)]]<-L }
cat("built stock weights for",length(IW),"month-ends\n")
## A5/C1 factor weights at those month-ends (index-level weight applied in month m -> W[m,])
mi<-match(format(sel,"%Y-%m"),format(mon$medate,"%Y-%m"))
agg<-function(WMAT,dt,mrow){ L<-IW[[as.character(dt)]]; fw<-WMAT[mrow,]; out<-data.table(Ticker=character(),w=numeric())
 for(nm in names(L)){ if(is.na(fw[nm])||fw[nm]<=0)next; x<-copy(L[[nm]]); x[,w:=w*fw[nm]]; out<-rbind(out,x) }
 out[,.(w=sum(w)),by=Ticker] }
tover<-function(WMAT,lab){ res<-list()
 for(i in 2:length(sel)){ if(as.numeric(sel[i]-sel[i-1])>45)next
  if(is.na(mi[i])||is.na(mi[i-1])||!is.finite(WMAT[mi[i],1]))next
  a<-agg(WMAT,sel[i-1],mi[i-1]); b<-agg(WMAT,sel[i],mi[i])
  m<-merge(a,b,by="Ticker",all=TRUE,suffixes=c("a","b")); m[is.na(wa),wa:=0]; m[is.na(wb),wb:=0]
  res[[length(res)+1]]<-data.table(lab=lab,date=sel[i],ow=sum(abs(m$wb-m$wa))/2,nm=nrow(b)) }
 rbindlist(res) }
TA<-tover(WA5,"A5_stocklevel"); TC<-tover(WC1,"C1_stocklevel")
## market benchmark stock turnover
TM<-rbindlist(lapply(2:length(sel),function(i){ if(as.numeric(sel[i]-sel[i-1])>45)return(NULL)
 a<-IW[[as.character(sel[i-1])]][["Market"]]; b<-IW[[as.character(sel[i])]][["Market"]]
 m<-merge(a,b,by="Ticker",all=TRUE,suffixes=c("a","b")); m[is.na(wa),wa:=0]; m[is.na(wb),wb:=0]
 data.table(lab="Market",date=sel[i],ow=sum(abs(m$wb-m$wa))/2,nm=nrow(b))}))
R<-rbind(TA,TC,TM)[,.(mean_oneway_mo=mean(ow),n=.N,n_names=round(mean(nm))),by=lab]
R[,ann_cost_15bps:=mean_oneway_mo*2*0.0015*12]; print(R,digits=4)
cat("\n  NET stock-level drag on A5 active vs Market = ",
  round((R[lab=="A5_stocklevel",ann_cost_15bps]-R[lab=="Market",ann_cost_15bps])*100,3),"%/yr\n")
cat("  (A5 index-layer charged cost already in backtest = ",round(0.0015*mean(rowSums(abs(diff(WA5[13:NM,])))) *12*100,3),"%/yr approx)\n")
nwt<-function(x){x<-x[is.finite(x)];m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
drag<-(R[lab=="A5_stocklevel",ann_cost_15bps]-R[lab=="Market",ann_cost_15bps])/12
kA<-13:NM; act<-NA
Zc<-readRDS("stage_artifacts/probe_a5_20260822/adv_refute/adv_core.rds")
k<-is.finite(Zc$a5$pr); a0<-Zc$a5$pr[k]-mon$Market[k]
idxcost_already<-0.0015*Zc$a5$tov[k]
cat("\n  pt base=",round(nwt(a0),3),
    " | pt after replacing index-layer cost with measured STOCK-level cost = ",
    round(nwt(a0+idxcost_already-drag),3),"\n")
saveRDS(list(R=R,TA=TA,TC=TC,TM=TM),"stage_artifacts/probe_a5_20260822/adv_refute/stocklevel_turnover.rds")
