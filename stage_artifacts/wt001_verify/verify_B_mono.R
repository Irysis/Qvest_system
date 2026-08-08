# Read-only reproduction of claim B: rank-IC vs quintile-mean inversion, monotonicity 0.25
suppressPackageStartupMessages({ library(data.table); library(arrow); library(sandwich); library(lmtest) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); IN9 <- file.path(ROOT,"stage_artifacts/WT_D20260802_009")
say <- function(fmt,...) cat(sprintf(paste0("[verB] ",fmt,"\n"),...))
FILT <- c("D03_EWMA","Q01_EB")
BASE  <- as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[, Date:=as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date:=as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Size","K200","KQ150")))[, Date:=as.Date(Date)]
RAW[, ym:=format(Date,"%Y-%m")]; MEND <- sort(RAW[,.(Date=max(Date)),by=ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE), .(Date,Ticker)]
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt   <- as.data.table(fwd$bench_dt)[,.(Date=as.Date(Date),BM_Ret)]
liq_dt     <- as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(NA_real_);f<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(f,vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}
score_of <- function(f){sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name==f,.(Date,Ticker,score=z)]
  else TUNED[Factor_Name==f,.(Date,Ticker,score=score)]; merge(sc[!is.na(score)],UNIV,by=c("Date","Ticker"))}
E <- merge(score_of("M01_PATHQ"), liq_dt, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]; setorder(E,Date,-score); E[, rk:=seq_len(.N), by=Date]
E <- E[Date %in% returns_dt$Date]
FZ <- rbindlist(lapply(FILT,function(f) score_of(f)[,.(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ, E[,.(Date,Ticker)], by=c("Date","Ticker")); FZ[, q_rank:=frank(fz)/.N, by=.(Date,F_)]

specs <- list(M01_PATHQ=E[,.(Date,Ticker,score)],
              Q01_EB=FZ[F_=="Q01_EB",.(Date,Ticker,score=fz)],
              D03_EWMA=FZ[F_=="D03_EWMA",.(Date,Ticker,score=fz)])

for (nm in names(specs)) {
  D <- merge(specs[[nm]], returns_dt, by=c("Date","Ticker"))
  D <- merge(D, bench_dt, by="Date")
  ic <- D[, if(.N>=10L && sd(score)>0 && sd(Ret_1m)>0) .(ic=cor(score,Ret_1m,method="spearman")) else .(ic=NA_real_), by=Date][is.finite(ic)]
  mono <- D[, { if (.N>=20L && sd(score)>0) {
      q <- cut(frank(score), breaks=5, labels=FALSE)
      .(q=1:5,
        mean_r = sapply(1:5, function(k) mean(Ret_1m[q==k],na.rm=TRUE)),
        med_r  = sapply(1:5, function(k) median(Ret_1m[q==k],na.rm=TRUE)),
        mean_a = sapply(1:5, function(k) mean(Ret_1m[q==k]-BM_Ret[q==k],na.rm=TRUE)),
        nk     = sapply(1:5, function(k) sum(q==k)),
        skw    = sapply(1:5, function(k) { z<-Ret_1m[q==k]; z<-z[is.finite(z)]
                   if(length(z)<5) NA_real_ else mean((z-mean(z))^3)/(sd(z)^3) }))
    } else .(q=1:5,mean_r=NA_real_,med_r=NA_real_,mean_a=NA_real_,nk=NA_integer_,skw=NA_real_) }, by=Date]
  agg <- mono[, .(mean_ann=100*12*mean(mean_r,na.rm=TRUE), med_ann=100*12*mean(med_r,na.rm=TRUE),
                  act_ann=100*12*mean(mean_a,na.rm=TRUE), nk=mean(nk,na.rm=TRUE),
                  skew=mean(skw,na.rm=TRUE)), by=q][order(q)]
  say("=== %s : rank_IC %+.4f  NWt(lag3) %+.2f  n_month=%d", nm, mean(ic$ic), nw_t(ic$ic), nrow(ic))
  say("    quintile size (avg names): %s", paste(sprintf("%.1f",agg$nk),collapse=" "))
  say("    MEAN   raw ann %%: %s   -> mono(step-frac)=%.2f  spearman(q,mean)=%+.2f",
      paste(sprintf("%+.2f",agg$mean_ann),collapse=" "), mean(diff(agg$mean_ann)>0),
      cor(1:5, agg$mean_ann, method="spearman"))
  say("    MEDIAN raw ann %%: %s   -> mono(step-frac)=%.2f  spearman=%+.2f",
      paste(sprintf("%+.2f",agg$med_ann),collapse=" "), mean(diff(agg$med_ann)>0),
      cor(1:5, agg$med_ann, method="spearman"))
  say("    MEAN  active ann %%: %s  -> mono(step-frac)=%.2f",
      paste(sprintf("%+.2f",agg$act_ann),collapse=" "), mean(diff(agg$act_ann)>0))
  say("    avg cross-sectional SKEW by quintile: %s", paste(sprintf("%+.2f",agg$skew),collapse=" "))
  # Q5-Q1 spread significance (monthly series, NW lag3)
  sp <- mono[q==5, .(Date, m5=mean_r)][mono[q==1, .(Date,m1=mean_r)], on="Date"][, d:=m5-m1]
  say("    Q5-Q1 MEAN spread: ann %+.2f%%  NW t %+.2f", 100*12*mean(sp$d,na.rm=TRUE), nw_t(sp$d))
  spm <- mono[q==5,.(Date,m5=med_r)][mono[q==1,.(Date,m1=med_r)],on="Date"][, d:=m5-m1]
  say("    Q5-Q1 MEDIAN spread: ann %+.2f%%  NW t %+.2f", 100*12*mean(spm$d,na.rm=TRUE), nw_t(spm$d))
  # subperiod decomposition of the quintile means for D03
  if (nm=="D03_EWMA") {
    mono[, p := fifelse(Date<as.Date("2015-01-01"),"P1",fifelse(Date<as.Date("2020-01-01"),"P2","P3"))]
    ag2 <- mono[, .(mean_ann=100*12*mean(mean_r,na.rm=TRUE)), by=.(p,q)][order(p,q)]
    for (pp in c("P1","P2","P3")) {
      v <- ag2[p==pp]$mean_ann
      say("    [%s] quintile MEAN ann %%: %s  -> mono=%.2f", pp, paste(sprintf("%+.2f",v),collapse=" "), mean(diff(v)>0))
    }
  }
}
say("done")
