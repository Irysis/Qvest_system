## R28 — frozen score_eff reconstruction builder (verbatim port of
## 05_Production/.../2-3.../_recompute_alpha_asof.R lines 39-66, parameterized by SLEEVE_CORE).
## READ-ONLY vs production: this is a stage_artifacts copy/derivation (task-permitted).
## Regime block SKIPPED (regime_state does not enter score_eff — only labels it).
suppressPackageStartupMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source(file.path(QM,"02_Infrastructure/config.R"))
source(file.path(QM,"02_Infrastructure/factor_db/factor_db_connector.R"))

SLEEVE_DEF <- c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
W_CORE <- 0.65; W_DEF <- 0.35
winsor_z <- function(x,s=2.5){m<-mean(x,na.rm=T);sd<-sd(x,na.rm=T);if(is.na(sd)||sd<1e-10)return(x);pmax(pmin(x,m+s*sd),m-s*sd)}
zc <- function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-10)x-m else (x-m)/s}

## --- shared inputs (load once) ---
.RECON_ENV <- new.env()
recon_init <- function(){
  ic <- as.data.table(read_parquet(file.path(QM,".cache/factor_db/factor_ic_monthly.parquet")))
  ic[,Date:=as.Date(Date)]; ic[,Usable_Date:=as.Date(Usable_Date)]
  .RECON_ENV$ic <- ic
  .RECON_ENV$reg <- .load_registry()
  ## RAWDATA — AvgTV20 (20d rolling mean of Close*Vol, shifted 1) per ticker
  RAW <- as.data.table(read_parquet(file.path(QM,".cache/RAWDATA.parquet"),
           col_select=c("Ticker","Date","Close","Vol")))
  RAW[,Date:=as.Date(Date)]
  RAW[,TV:=Close*Vol]
  setorder(RAW, Ticker, Date)
  RAW[,A:=frollmean(TV,20L,align="right"),by=Ticker]
  RAW[,AvgTV20:=shift(A,1L),by=Ticker]
  .RECON_ENV$RAW <- RAW[,.(Ticker,Date,AvgTV20)]
  ## universe support
  k2 <- as.data.table(read_parquet(file.path(QM,".cache/universe_support/us_k200.parquet"))); k2[,Date:=as.Date(Date)]
  kq <- as.data.table(read_parquet(file.path(QM,".cache/universe_support/us_kq150.parquet"))); kq[,Date:=as.Date(Date)]
  .RECON_ENV$k2 <- k2; .RECON_ENV$kq <- kq
  invisible(TRUE)
}

## build score_eff for one AS_OF (first-of-month label), given SLEEVE_CORE vector
## theta_mode: "ic" = recompute theta from factor_ic_monthly (production path);
##             "stored" = use theta_override (named numeric over SLEEVE_CORE), renormalized.
build_month_score <- function(AS_OF, SLEEVE_CORE, theta_mode="ic", theta_override=NULL){
  AS_OF <- as.Date(AS_OF); CUT <- AS_OF-1L
  ym <- format(AS_OF-1,"%Y%m")
  fdp <- file.path(QM, sprintf(".cache/factor_db/factor_db_%s.parquet",ym))
  if(!file.exists(fdp)) return(NULL)
  ic <- .RECON_ENV$ic
  Kc <- length(SLEEVE_CORE)
  if(theta_mode=="stored"){
    if(is.null(theta_override)) return(list(err="stored theta_mode but no theta_override"))
    tc <- theta_override[SLEEVE_CORE]
    tc[!is.finite(tc)] <- 0
    if(sum(abs(tc))<=0) tc <- setNames(rep(1/Kc,Kc),SLEEVE_CORE) else tc <- tc/sum(abs(tc))
    names(tc) <- SLEEVE_CORE
  } else {
    icm <- ic[Usable_Date<AS_OF & !is.na(IC) & Factor_Name %in% SLEEVE_CORE,.(m=mean(IC,na.rm=T)),by=Factor_Name]
    tc <- setNames(rep(0,Kc),SLEEVE_CORE)
    for(f in icm$Factor_Name) tc[f] <- max(icm[Factor_Name==f,m],0)
    if(sum(abs(tc))<=0) tc <- setNames(rep(1/Kc,Kc),SLEEVE_CORE) else tc <- tc/sum(abs(tc))
  }
  td <- setNames(rep(1/3,3),SLEEVE_DEF)
  rdf <- function(p,fac){f<-as.data.table(read_parquet(p,col_select=c("Ticker","Factor_Name","Z_Score","Coverage")));
    f[Factor_Name%in%fac & Coverage==TRUE & !is.na(Z_Score),.(Ticker,Factor_Name,Z_Score)]}
  base <- rdf(fdp,c(SLEEVE_CORE,"Q07_Earnings_Stability","Q25_Ohlson_O"))
  m08 <- rdf(fdp,"M08_Residual_Mom")
  fdb <- rbind(base,m08); fdb[,sig_date:=AS_OF]
  .missing <- setdiff(c(SLEEVE_CORE,SLEEVE_DEF), unique(fdb$Factor_Name))
  if(length(.missing)) return(list(err=sprintf("missing %s @ %s", paste(.missing,collapse=","), ym)))
  fa <- align_factor_direction(fdb, .RECON_ENV$reg, sig_date=AS_OF, min_ic_months=12L)
  if("Z_Score_Aligned"%in%names(fa)) fa[,Z_Score:=Z_Score_Aligned]
  fw <- dcast(fa, sig_date+Ticker~Factor_Name, value.var="Z_Score", fill=NA_real_)
  ## liq filter (AvgTV20 at pc = max Date<=CUT) >= 2e8
  RAW <- .RECON_ENV$RAW
  pc <- RAW[Date<=CUT, max(Date)]
  liq <- RAW[Date==pc & !is.na(AvgTV20) & AvgTV20>=2e8, .(Ticker)]
  fw <- merge(fw, liq, by="Ticker")
  ## universe K200 ∪ KQ150 at latest date<=CUT
  k2 <- .RECON_ENV$k2; kq <- .RECON_ENV$kq
  uni <- unique(c(k2[Date==k2[Date<=CUT,max(Date)] & K200==1, Ticker],
                  kq[Date==kq[Date<=CUT,max(Date)] & KQ150==1, Ticker]))
  fw <- fw[Ticker%in%uni]
  if(nrow(fw)<25) return(list(err=sprintf("universe<25 @ %s", ym)))
  agg <- function(df,fc,w){fc<-intersect(intersect(names(w),fc),names(df)); W<-as.numeric(w[fc]); W<-W/sum(W)
    X<-as.matrix(df[,..fc]); X<-apply(X,2,winsor_z); X[is.na(X)]<-0; as.numeric(X%*%W)}
  fw[,Sc:=agg(.SD,SLEEVE_CORE,tc)]; fw[,Sd:=agg(.SD,SLEEVE_DEF,td)]
  fw[,Scz:=zc(Sc)]; fw[,Sdz:=zc(Sd)]; fw[,score_eff:=W_CORE*Scz+W_DEF*Sdz]
  list(dt=fw[,.(Date=AS_OF,Ticker,score_eff,score_core_z=Scz,score_defense_z=Sdz)],
       theta_core=tc)
}
cat("[_build_score.R] loaded — recon_init() + build_month_score(AS_OF, SLEEVE_CORE)\n")
