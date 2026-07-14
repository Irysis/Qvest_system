## R28 recipe scan — find max-parity reconstruction recipe (challenge #1: is parity achievable?)
## Vary: factor_db month offset {-1(prod),0(same)} x re-winsor {yes,no}, stored theta.
suppressPackageStartupMessages({library(arrow); library(data.table); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source(file.path(QM,"02_Infrastructure/config.R"))
source(file.path(QM,"02_Infrastructure/factor_db/factor_db_connector.R"))
SLEEVE7 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
SLEEVE_DEF <- c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
W_CORE<-0.65; W_DEF<-0.35
winsor_z <- function(x,s=2.5){m<-mean(x,na.rm=T);sd<-sd(x,na.rm=T);if(is.na(sd)||sd<1e-10)return(x);pmax(pmin(x,m+s*sd),m-s*sd)}
zc <- function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-10)x-m else (x-m)/s}
reg <- .load_registry()
RAW <- as.data.table(read_parquet(file.path(QM,".cache/RAWDATA.parquet"),col_select=c("Ticker","Date","Close","Vol")))
RAW[,Date:=as.Date(Date)]; RAW[,TV:=Close*Vol]; setorder(RAW,Ticker,Date)
RAW[,A:=frollmean(TV,20L,align="right"),by=Ticker]; RAW[,AvgTV20:=shift(A,1L),by=Ticker]; RAW<-RAW[,.(Ticker,Date,AvgTV20)]
k2<-as.data.table(read_parquet(file.path(QM,".cache/universe_support/us_k200.parquet")));k2[,Date:=as.Date(Date)]
kq<-as.data.table(read_parquet(file.path(QM,".cache/universe_support/us_kq150.parquet")));kq[,Date:=as.Date(Date)]
bkp <- file.path(QM,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet")
bk <- as.data.table(read_parquet(bkp)); bk[,Date:=as.Date(Date)]
theta_map <- unique(bk[,.(Date, theta_core)])
get_theta <- function(d){ v<-unlist(fromJSON(theta_map[Date==d, theta_core][1])); v[SLEEVE7] }

library(lubridate)
build <- function(AS_OF, fdb_off, rewinsor){
  AS_OF<-as.Date(AS_OF); CUT<-AS_OF-1L
  ## fdb_off = months relative to (AS_OF-1)'s month. off=0 -> T-1 (production). off=+1 -> AS_OF's own month (same-month-end).
  base_month <- as.Date(paste0(format(AS_OF-1,"%Y-%m"),"-01"))
  m0 <- base_month %m+% months(fdb_off); ym <- format(m0,"%Y%m")
  fdp <- file.path(QM, sprintf(".cache/factor_db/factor_db_%s.parquet",ym))
  if(!file.exists(fdp)) return(NULL)
  tc <- get_theta(AS_OF); tc[!is.finite(tc)]<-0; tc<-if(sum(abs(tc))<=0) setNames(rep(1/4,4),SLEEVE7) else tc/sum(abs(tc))
  td <- setNames(rep(1/3,3),SLEEVE_DEF)
  rdf<-function(p,fac){f<-as.data.table(read_parquet(p,col_select=c("Ticker","Factor_Name","Z_Score","Coverage")));f[Factor_Name%in%fac&Coverage==TRUE&!is.na(Z_Score),.(Ticker,Factor_Name,Z_Score)]}
  fdb<-rbind(rdf(fdp,c(SLEEVE7,"Q07_Earnings_Stability","Q25_Ohlson_O")), rdf(fdp,"M08_Residual_Mom")); fdb[,sig_date:=AS_OF]
  if(length(setdiff(c(SLEEVE7,SLEEVE_DEF),unique(fdb$Factor_Name)))) return(NULL)
  fa<-align_factor_direction(fdb,reg,sig_date=AS_OF,min_ic_months=12L); if("Z_Score_Aligned"%in%names(fa))fa[,Z_Score:=Z_Score_Aligned]
  fw<-dcast(fa,sig_date+Ticker~Factor_Name,value.var="Z_Score",fill=NA_real_)
  pc<-RAW[Date<=CUT,max(Date)]; liq<-RAW[Date==pc&!is.na(AvgTV20)&AvgTV20>=2e8,.(Ticker)]; fw<-merge(fw,liq,by="Ticker")
  uni<-unique(c(k2[Date==k2[Date<=CUT,max(Date)]&K200==1,Ticker],kq[Date==kq[Date<=CUT,max(Date)]&KQ150==1,Ticker])); fw<-fw[Ticker%in%uni]
  if(nrow(fw)<25) return(NULL)
  agg<-function(df,fc,w){fc<-intersect(intersect(names(w),fc),names(df));W<-as.numeric(w[fc]);W<-W/sum(W);X<-as.matrix(df[,..fc]);if(rewinsor)X<-apply(X,2,winsor_z);X[is.na(X)]<-0;as.numeric(X%*%W)}
  fw[,Sc:=agg(.SD,SLEEVE7,tc)];fw[,Sd:=agg(.SD,SLEEVE_DEF,td)]
  fw[,Scz:=zc(Sc)];fw[,Sdz:=zc(Sd)];fw[,score_eff:=W_CORE*Scz+W_DEF*Sdz]
  fw[,.(Ticker,score_eff)]
}
test_dates<-as.Date(c("2010-06-01","2015-06-01","2020-01-01"))
cat(sprintf("%-12s %-6s %-8s %8s %8s\n","date","fdboff","rewinsor","cor","spearman"))
for(d in test_dates) for(off in c(0,1)) for(rw in c(TRUE,FALSE)){
  r<-build(d,off,rw); if(is.null(r)) {cat(sprintf("%s off=%d rw=%s NULL\n",d,off,rw));next}
  m<-merge(r,bk[Date==d,.(Ticker,se=score_eff)],by="Ticker"); m<-m[is.finite(score_eff)&is.finite(se)]
  cat(sprintf("%-12s %-6d %-8s %8.4f %8.4f\n",as.character(d),off,rw,cor(m$score_eff,m$se),cor(m$score_eff,m$se,method="spearman")))
}
cat("RECIPE_SCAN_DONE\n")
