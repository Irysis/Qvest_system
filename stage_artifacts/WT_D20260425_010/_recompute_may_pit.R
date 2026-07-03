## 05-01 alpha PIT-clean 재산출 — factor_db_202604(end-April) 단일소스 (5월 결정=4월말 데이터)
## 이전 _recompute_may_refresh.R가 factor_db_202605(end-May)를 써 lookahead 혼입 → 수리.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999); Sys.setenv(TZ="Asia/Seoul")
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT,"02_Infrastructure/config.R")); source(file.path(ROOT,"02_Infrastructure/factor_db/factor_db_connector.R"))
SLEEVE_CORE<-c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
SLEEVE_DEF<-c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
SIG<-as.Date("2026-05-01"); PIT_REF<-as.Date("2026-04-30"); REGIME<-"CAUTION"; W_CORE<-0.65; W_DEF<-0.35
winsor_z<-function(x,s=2.5){m<-mean(x,na.rm=T);sd<-sd(x,na.rm=T);if(is.na(sd)||sd<1e-10)return(x);pmax(pmin(x,m+s*sd),m-s*sd)}
ic<-as.data.table(read_parquet(file.path(ROOT,".cache/factor_db/factor_ic_monthly.parquet")))
ic[,Date:=as.Date(Date)];ic[,Usable_Date:=as.Date(Usable_Date)]
icm<-ic[Usable_Date<SIG & !is.na(IC) & Factor_Name %in% SLEEVE_CORE,.(m=mean(IC,na.rm=T)),by=Factor_Name]
tc<-setNames(rep(0,4),SLEEVE_CORE);for(f in icm$Factor_Name)tc[f]<-max(icm[Factor_Name==f,m],0);tc<-tc/sum(abs(tc))
td<-setNames(rep(1/3,3),SLEEVE_DEF)
cat("[theta] Core(Usable<05-01):\n");print(round(tc,4))
# 전 팩터 202604 (end-April) — PIT-clean for 05-01
f4<-as.data.table(read_parquet(file.path(ROOT,".cache/factor_db/factor_db_202604.parquet"),col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
need<-c(SLEEVE_CORE,SLEEVE_DEF)
fdb<-f4[Factor_Name %in% need & Coverage==TRUE & !is.na(Z_Score),.(Ticker,Factor_Name,Z_Score)];fdb[,sig_date:=SIG]
cat(sprintf("[202604] %d rows | %s\n",nrow(fdb),paste(sort(unique(fdb$Factor_Name)),collapse=",")))
fa<-align_factor_direction(fdb,.load_registry(),sig_date=SIG,min_ic_months=12L)
if("Z_Score_Aligned"%in%names(fa)){fa[,Z_Score:=Z_Score_Aligned]}
fw<-dcast(fa,sig_date+Ticker~Factor_Name,value.var="Z_Score",fill=NA_real_)
raw<-as.data.table(read_parquet(file.path(ROOT,".cache/rawdata.parquet"),col_select=c("Date","Ticker","Close","Vol")))
raw[,Date:=as.Date(Date)];raw[,TV:=Close*Vol]
raw[order(Date),A:=frollmean(TV,20L,align="right"),by=Ticker];raw[order(Date),AvgTV20:=shift(A,1L),by=Ticker]
pc<-raw[Date<=PIT_REF,max(Date)];liq<-raw[Date==pc & !is.na(AvgTV20) & AvgTV20>=2e8,.(Ticker)]
fw<-merge(fw,liq,by="Ticker")
k2<-as.data.table(read_parquet(file.path(ROOT,".cache/universe_support/us_k200.parquet")));k2[,Date:=as.Date(Date)]
kq<-as.data.table(read_parquet(file.path(ROOT,".cache/universe_support/us_kq150.parquet")));kq[,Date:=as.Date(Date)]
uni<-unique(c(k2[Date==k2[Date<=PIT_REF,max(Date)] & K200==1,Ticker],kq[Date==kq[Date<=PIT_REF,max(Date)] & KQ150==1,Ticker]))
fw<-fw[Ticker %in% uni]
agg<-function(df,fc,w){fc<-intersect(intersect(names(w),fc),names(df));W<-as.numeric(w[fc]);W<-W/sum(W);X<-as.matrix(df[,..fc]);X<-apply(X,2,winsor_z);X[is.na(X)]<-0;as.numeric(X%*%W)}
fw[,Sc:=agg(.SD,SLEEVE_CORE,tc)];fw[,Sd:=agg(.SD,SLEEVE_DEF,td)]
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-10)x-m else (x-m)/s}
fw[,Scz:=zc(Sc)];fw[,Sdz:=zc(Sd)];fw[,score_eff:=W_CORE*Scz+W_DEF*Sdz]
ma<-fw[,.(Date=sig_date,Ticker,score_eff,score_core_z=Scz,score_defense_z=Sdz,Ret_1m=NA_real_,regime_state=REGIME,
  theta_core=toJSON(as.list(round(tc,4)),auto_unbox=T),theta_defense=toJSON(as.list(round(td,4)),auto_unbox=T))]
cat(sprintf("[may_pit] %d rows. Top5: %s\n",nrow(ma),paste(ma[order(-score_eff)][1:5,Ticker],collapse=",")))
ap<-file.path(ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet")
ex<-as.data.table(read_parquet(ap));ex[,Date:=as.Date(Date)];ex[,theta_core:=as.character(theta_core)];ex[,theta_defense:=as.character(theta_defense)]
ma[,theta_core:=as.character(theta_core)];ma[,theta_defense:=as.character(theta_defense)]
mg<-rbind(ex[Date!=SIG],ma,use.names=T,fill=T);setkey(mg,Date,Ticker)
.t<-paste0(ap,".tmp");write_parquet(mg,.t);if(file.exists(ap))file.remove(ap);file.rename(.t,ap)
cat(sprintf("[write] alpha 05-01 PIT-clean(202604) 교체. %s~%s sig_dates=%d\n",min(mg$Date),max(mg$Date),uniqueN(mg$Date)))
