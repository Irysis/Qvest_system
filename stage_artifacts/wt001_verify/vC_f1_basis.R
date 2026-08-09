# Read-only verification C: F1 verdict basis-dependence (mean vs median cross-section)
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); IN9 <- file.path(ROOT,"stage_artifacts/WT_D20260802_009")
say <- function(fmt,...) cat(sprintf(paste0("[vC] ",fmt,"\n"),...))
FILT <- c("D03_EWMA","Q01_EB")
BASE <- as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[, Date:=as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date:=as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","K200","KQ150")))[, Date:=as.Date(Date)]
RAW[, ym:=format(Date,"%Y-%m")]
MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
UNIV <- RAW[Date %in% MEND & (K200==TRUE|KQ150==TRUE), .(Date,Ticker)]; rm(RAW); gc(verbose=FALSE)
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt <- as.data.table(fwd$bench_dt)[, .(Date=as.Date(Date),BM_Ret)]
liq_dt <- as.data.table(fwd$liq_dt)[, .(Date=as.Date(Date),Ticker,adv)]
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(NA_real_);f<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(f,vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}
score_of <- function(f){sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name==f,.(Date,Ticker,score=z)]
  else TUNED[Factor_Name==f,.(Date,Ticker,score=score)]; merge(sc[!is.na(score)],UNIV,by=c("Date","Ticker"))}
E <- merge(score_of("M01_PATHQ"), liq_dt, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]; E <- E[Date %in% returns_dt$Date]
FZ <- rbindlist(lapply(FILT,function(f) score_of(f)[,.(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ, E[,.(Date,Ticker)], by=c("Date","Ticker"))
D <- merge(FZ, returns_dt, by=c("Date","Ticker"))
D <- merge(D, bench_dt, by="Date"); D[, act := Ret_1m - BM_Ret]
D[, q_rank := frank(fz)/.N, by=.(Date,F_)]
D[, qb := cut(q_rank, breaks=c(0,.2,.4,.6,.8,1), labels=FALSE, include.lowest=TRUE)]
for (f in FILT) {
  s <- D[F_==f, .(m1=mean(act[qb==1]), m3=mean(act[qb==3]), m5=mean(act[qb==5]),
                  d1=median(act[qb==1]), d3=median(act[qb==3]), d5=median(act[qb==5])), by=Date]
  s <- s[is.finite(m1)&is.finite(m3)&is.finite(m5)]
  say("-- %s (n=%d months) --", f, nrow(s))
  say("   MEAN   basis: Q1-Q3 = %+.2f%%/yr (NW t %+.2f) | Q5-Q3 = %+.2f%%/yr (NW t %+.2f)",
      100*12*mean(s$m1-s$m3), nw_t(s$m1-s$m3), 100*12*mean(s$m5-s$m3), nw_t(s$m5-s$m3))
  say("   MEDIAN basis: Q1-Q3 = %+.2f%%/yr (NW t %+.2f) | Q5-Q3 = %+.2f%%/yr (NW t %+.2f)",
      100*12*mean(s$d1-s$d3), nw_t(s$d1-s$d3), 100*12*mean(s$d5-s$d3), nw_t(s$d5-s$d3))
}
say("=== vC done ===")
