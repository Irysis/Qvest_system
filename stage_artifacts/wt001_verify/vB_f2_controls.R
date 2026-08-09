# Read-only verification B: claim D — is log(Size) a sufficient control?
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); IN9 <- file.path(ROOT,"stage_artifacts/WT_D20260802_009")
say <- function(fmt,...) cat(sprintf(paste0("[vB] ",fmt,"\n"),...))
FILT <- c("D03_EWMA","Q01_EB")
BASE <- as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[, Date:=as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date:=as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Size","Vol","Close","K200","KQ150")))[, Date:=as.Date(Date)]
RAW[, ym:=format(Date,"%Y-%m")]
# monthly traded value (turnover) from DAILY data — measured, not assumed
TV <- RAW[, .(tv = sum(as.numeric(Vol)*as.numeric(Close), na.rm=TRUE), ndays=.N), by=.(ym,Ticker)]
MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE), .(Date,Ticker)]
SIZE <- RAWME[, .(Date,Ticker,Size)]
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date),Ticker,Ret_1m)]
liq_dt <- as.data.table(fwd$liq_dt)[, .(Date=as.Date(Date),Ticker,adv)]
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(NA_real_);f<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(f,vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}
score_of <- function(f){sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name==f,.(Date,Ticker,score=z)]
  else TUNED[Factor_Name==f,.(Date,Ticker,score=score)]; merge(sc[!is.na(score)],UNIV,by=c("Date","Ticker"))}
E <- merge(score_of("M01_PATHQ"), liq_dt, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]; setorder(E,Date,-score); E[, rk:=seq_len(.N), by=Date]
E <- E[Date %in% returns_dt$Date]
FZ <- rbindlist(lapply(FILT,function(f) score_of(f)[,.(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ, E[,.(Date,Ticker)], by=c("Date","Ticker"))

readinv <- function(nm) {
  d <- as.data.table(read_parquet(sprintf(".cache/investor_stock/investor_%s.parquet", nm),
        col_select=c("Date","Ticker","NetBuy")))[, Date:=as.Date(Date)]
  say("INPUT investor_%s nrow=%d unit=DAILY n_day=%d %s~%s  NetBuy summary: min=%.3g med=%.3g max=%.3g",
      nm, nrow(d), uniqueN(d$Date), as.character(min(d$Date)), as.character(max(d$Date)),
      min(d$NetBuy,na.rm=TRUE), median(d$NetBuy,na.rm=TRUE), max(d$NetBuy,na.rm=TRUE))
  d[, ym:=format(Date,"%Y-%m")]
  d[, .(nb=sum(NetBuy,na.rm=TRUE)), by=.(ym,Ticker)]
}
SIGM <- data.table(Date=sort(unique(E$Date)))[, ym:=format(Date,"%Y-%m")]

run_reg <- function(nm) {
  INM <- readinv(nm)
  INM <- merge(INM, SIGM, by="ym")
  INM <- merge(INM, TV, by=c("ym","Ticker"), all.x=TRUE)[, ym:=NULL]
  INM <- merge(INM, SIZE, by=c("Date","Ticker"))[is.finite(Size)&Size>0]
  INM[, `:=`(nb_norm=nb/Size, lsz=log(Size), ltv=log(pmax(tv,1)), lturn=log(pmax(tv,1)/Size))]
  for (f in FILT) {
    D <- merge(FZ[F_==f,.(Date,Ticker,fz)], INM[,.(Date,Ticker,nb_norm,lsz,lturn)], by=c("Date","Ticker"))
    s <- D[, {
      ok <- is.finite(fz)&is.finite(nb_norm)&is.finite(lsz)&is.finite(lturn)
      if (sum(ok)>=30L && sd(fz[ok])>1e-8 && sd(nb_norm[ok])>1e-12) {
        z <- function(v) (v-mean(v))/sd(v)
        yz <- z(nb_norm[ok]); xz <- z(fz[ok]); sz <- z(lsz[ok]); tz <- z(lturn[ok])
        yr <- z(frank(nb_norm[ok])); xr <- z(frank(fz[ok])); sr <- z(frank(lsz[ok])); tr <- z(frank(lturn[ok]))
        .(b_raw   = unname(coef(lm(yz~xz))[2]),
          b_size  = unname(coef(lm(yz~xz+sz))[2]),
          b_turn  = unname(coef(lm(yz~xz+tz))[2]),
          b_both  = unname(coef(lm(yz~xz+sz+tz))[2]),
          b_rank  = unname(coef(lm(yr~xr+sr+tr))[2]),
          n=sum(ok))
      } else NULL
    }, by=Date]
    if (nrow(s)==0) next
    say("%-14s %-9s raw %+.4f (t%+.2f) | +size %+.4f (t%+.2f) | +turnover %+.4f (t%+.2f) | +both %+.4f (t%+.2f) ret%.2f | rank+both %+.4f (t%+.2f)  n_m=%d",
        nm, f, mean(s$b_raw), nw_t(s$b_raw), mean(s$b_size), nw_t(s$b_size),
        mean(s$b_turn), nw_t(s$b_turn), mean(s$b_both), nw_t(s$b_both),
        mean(s$b_both)/mean(s$b_raw), mean(s$b_rank), nw_t(s$b_rank), nrow(s))
  }
}
for (nm in c("individual","foreign","institutional")) run_reg(nm)
say("=== vB done ===")
