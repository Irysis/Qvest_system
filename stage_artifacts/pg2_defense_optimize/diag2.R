suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999); setDTthreads(1L)   # NO arrow io thread set (hangs)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/config.R"))
source(file.path(ROOT,"02_Infrastructure/factor_db/factor_db_connector.R"))
CUR_DEF <- c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
winsor_z <- function(x,s=2.5){m<-mean(x,na.rm=T);sd<-sd(x,na.rm=T);if(is.na(sd)||sd<1e-10)return(x);pmax(pmin(x,m+s*sd),m-s*sd)}
zc <- function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-10)x-m else (x-m)/s}
ap <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); ap[,Date:=as.Date(Date)]

diag_one <- function(SD, fym){
  tks <- ap[Date==SD, Ticker]
  f <- as.data.table(read_parquet(file.path(FACTOR_DB_DIR, sprintf("factor_db_%s.parquet",fym)),
       col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
  f <- f[Factor_Name %in% CUR_DEF & Coverage==TRUE & !is.na(Z_Score), .(Ticker,Factor_Name,Z_Score)]
  fa <- align_factor_direction(f, .load_registry(), sig_date=SD, min_ic_months=12L)
  if ("Z_Score_Aligned" %in% names(fa)) fa[, Z_Score:=Z_Score_Aligned]
  build <- function(scope_tks){
    fw <- dcast(fa[Ticker %in% scope_tks], Ticker~Factor_Name, value.var="Z_Score", fill=NA_real_)
    facp <- intersect(CUR_DEF, names(fw)); W<-rep(1/3,3);names(W)<-CUR_DEF;W<-W[facp];W<-W/sum(W)
    X<-as.matrix(fw[,..facp]);X<-apply(X,2,winsor_z);X[is.na(X)]<-0
    fw[,Sd:=as.numeric(X%*%W)];fw[,def_z:=zc(Sd)];fw[,.(Ticker,def_z)]
  }
  # scope A: alpha tickers only ; scope B: full factor-db universe then subset to alpha
  A <- build(tks)
  B_full <- build(unique(fa$Ticker))            # z over full univ
  cmpA <- merge(ap[Date==SD,.(Ticker,stored=score_defense_z)], A, by="Ticker", all.x=TRUE)
  cmpB <- merge(ap[Date==SD,.(Ticker,stored=score_defense_z)], B_full, by="Ticker", all.x=TRUE)
  cat(sprintf("[%s fym=%s] scopeALPHA maxdiff=%.4f cor=%.4f | scopeFULLUNIV maxdiff=%.4f cor=%.4f | n_alpha=%d n_fa=%d\n",
    as.character(SD), fym, max(abs(cmpA$def_z-cmpA$stored),na.rm=T), cor(cmpA$def_z,cmpA$stored,use="complete.obs"),
    max(abs(cmpB$def_z-cmpB$stored),na.rm=T), cor(cmpB$def_z,cmpB$stored,use="complete.obs"),
    length(tks), uniqueN(fa$Ticker)))
}
for (d in as.Date(c("2018-03-01","2022-09-01"))){
  diag_one(d, format(d,"%Y%m"))
  diag_one(d, format(seq(d,by="-1 month",length.out=2)[2],"%Y%m"))
}
