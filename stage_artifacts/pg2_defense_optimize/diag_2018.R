suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999); setDTthreads(1L); try(arrow::set_io_thread_count(1L), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/config.R"))
source(file.path(ROOT,"02_Infrastructure/factor_db/factor_db_connector.R"))
`%||%` <- function(a,b) if(is.null(a)) b else a
CUR_DEF <- c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
winsor_z <- function(x,s=2.5){m<-mean(x,na.rm=T);sd<-sd(x,na.rm=T);if(is.na(sd)||sd<1e-10)return(x);pmax(pmin(x,m+s*sd),m-s*sd)}
zc <- function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-10)x-m else (x-m)/s}
ap <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); ap[,Date:=as.Date(Date)]
SD <- as.Date("2018-03-01")
tks <- ap[Date==SD, Ticker]
cat("alpha tickers @2018-03:", length(tks), "\n")

# use load_month_factors (connector, same-month) to get aligned Z for these 3
lm <- load_month_factors(SD, coverage_min=0.05, factor_names=CUR_DEF)
cat("load_month_factors rows:", nrow(lm), "| factors:", paste(unique(lm$Factor_Name),collapse=","), "\n")
lmw <- dcast(lm[Ticker %in% tks], Ticker ~ Factor_Name, value.var="Z_Score_Aligned", fill=NA_real_)
facp <- intersect(CUR_DEF, names(lmw))
W <- rep(1/3,3); names(W)<-CUR_DEF; W<-W[facp]; W<-W/sum(W)
X <- as.matrix(lmw[,..facp]); X<-apply(X,2,winsor_z); X[is.na(X)]<-0
lmw[, Sd:=as.numeric(X%*%W)]; lmw[, def_z:=zc(Sd)]
cmp <- merge(ap[Date==SD,.(Ticker,stored=score_defense_z)], lmw[,.(Ticker,def_z)], by="Ticker", all.x=TRUE)
cat("via load_month_factors same-month: max|diff|=", max(abs(cmp$def_z-cmp$stored),na.rm=T),
    "| cor=", cor(cmp$def_z, cmp$stored, use="complete.obs"), "| n=", sum(!is.na(cmp$def_z)), "\n")

# Check: does stored score_defense_z correlate perfectly with a SINGLE factor recon?
# maybe historical build used raw Z_Score (not aligned) or different winsor scope
# Show per-factor coverage
for (f in CUR_DEF){
  cat(sprintf("  %s: present in same-month=%s (n=%d)\n", f, f %in% names(lmw), sum(!is.na(lmw[[f]] %||% NA))))
}
# raw z (no align) test
f <- as.data.table(read_parquet(file.path(FACTOR_DB_DIR,"factor_db_201803.parquet"),
  col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
f <- f[Factor_Name %in% CUR_DEF & Coverage==TRUE & !is.na(Z_Score) & Ticker %in% tks]
rw <- dcast(f, Ticker~Factor_Name, value.var="Z_Score", fill=NA_real_)
facp2 <- intersect(CUR_DEF, names(rw))
X2 <- as.matrix(rw[,..facp2]); X2<-apply(X2,2,winsor_z); X2[is.na(X2)]<-0
W2 <- rep(1/3,3); names(W2)<-CUR_DEF; W2<-W2[facp2]; W2<-W2/sum(W2)
rw[, Sd:=as.numeric(X2%*%W2)]; rw[, def_z:=zc(Sd)]
cmp2 <- merge(ap[Date==SD,.(Ticker,stored=score_defense_z)], rw[,.(Ticker,def_z)], by="Ticker", all.x=TRUE)
cat("via RAW Z (no align) same-month: max|diff|=", max(abs(cmp2$def_z-cmp2$stored),na.rm=T),
    "| cor=", cor(cmp2$def_z, cmp2$stored, use="complete.obs"), "\n")

# correlation with each single aligned factor (to detect sign/scope)
for (f in facp){
  cc <- cor(lmw[[f]], cmp$stored[match(lmw$Ticker, cmp$Ticker)], use="complete.obs")
  cat(sprintf("  cor(stored, aligned %s)=%.3f\n", f, cc))
}
