# Read-only reproduction of claim D: individual net-buy concentration, size control
suppressPackageStartupMessages({ library(data.table); library(arrow); library(sandwich); library(lmtest) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); IN9 <- file.path(ROOT,"stage_artifacts/WT_D20260802_009")
say <- function(fmt,...) cat(sprintf(paste0("[verD] ",fmt,"\n"),...))
FILT <- c("D03_EWMA","Q01_EB")

sch <- arrow::open_dataset(".cache/investor_stock/investor_individual.parquet")$schema
say("investor_individual SCHEMA: %s", paste(names(sch), sapply(names(sch), function(n) sch[[n]]$type$ToString()), sep="=", collapse=" | "))

BASE  <- as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[, Date:=as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date:=as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Size","K200","KQ150")))[, Date:=as.Date(Date)]
RAW[, ym:=format(Date,"%Y-%m")]; MEND <- sort(RAW[,.(Date=max(Date)),by=ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE), .(Date,Ticker)]; SIZE <- RAWME[,.(Date,Ticker,Size)]
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]
liq_dt <- as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(NA_real_);f<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(f,vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}
score_of <- function(f){sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name==f,.(Date,Ticker,score=z)]
  else TUNED[Factor_Name==f,.(Date,Ticker,score=score)]; merge(sc[!is.na(score)],UNIV,by=c("Date","Ticker"))}
E <- merge(score_of("M01_PATHQ"), liq_dt, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]; setorder(E,Date,-score); E[, rk:=seq_len(.N), by=Date]
E <- E[Date %in% returns_dt$Date]
FZ <- rbindlist(lapply(FILT,function(f) score_of(f)[,.(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ, E[,.(Date,Ticker)], by=c("Date","Ticker")); FZ[, q_rank:=frank(fz)/.N, by=.(Date,F_)]

IND <- as.data.table(read_parquet(".cache/investor_stock/investor_individual.parquet",
        col_select=c("Date","Ticker","NetBuy")))[, Date:=as.Date(Date)]
say("INPUT investor_individual nrow=%d DAILY n_day=%d %s~%s", nrow(IND), uniqueN(IND$Date), min(IND$Date), max(IND$Date))
say("NetBuy quantiles: %s", paste(sprintf("%.3g", quantile(IND$NetBuy, c(.01,.25,.5,.75,.99), na.rm=TRUE)), collapse=" "))
IND[, ym:=format(Date,"%Y-%m")]
INM <- IND[, .(nb=sum(NetBuy,na.rm=TRUE)), by=.(ym,Ticker)]; rm(IND); gc(verbose=FALSE)
SIGM <- data.table(Date=sort(unique(E$Date)))[, ym:=format(Date,"%Y-%m")]
INM <- merge(INM, SIGM, by="ym")[, ym:=NULL]
INM <- merge(INM, SIZE, by=c("Date","Ticker"))[is.finite(Size)&Size>0]
INM[, `:=`(nb_norm=nb/Size, lsz=log(Size))]
say("Size quantiles: %s", paste(sprintf("%.3g", quantile(INM$Size, c(.01,.5,.99), na.rm=TRUE)), collapse=" "))
say("nb/Size quantiles: %s", paste(sprintf("%.4g", quantile(INM$nb_norm, c(.01,.25,.5,.75,.99), na.rm=TRUE)), collapse=" "))

for (f in FILT) {
  D <- merge(FZ[F_==f,.(Date,Ticker,fz)], INM[,.(Date,Ticker,nb_norm,lsz)], by=c("Date","Ticker"))
  s <- D[, { ok <- is.finite(fz)&is.finite(nb_norm)&is.finite(lsz)
    if (sum(ok)>=30L && sd(fz[ok])>1e-8 && sd(nb_norm[ok])>1e-12 && sd(lsz[ok])>1e-8) {
      yz<-(nb_norm[ok]-mean(nb_norm[ok]))/sd(nb_norm[ok]); xz<-(fz[ok]-mean(fz[ok]))/sd(fz[ok])
      sz<-(lsz[ok]-mean(lsz[ok]))/sd(lsz[ok])
      # rank-based robustness: same regression on cross-sectional ranks
      yr<-scale(frank(nb_norm[ok]))[,1]; xr<-scale(frank(fz[ok]))[,1]; sr<-scale(frank(lsz[ok]))[,1]
      cf<-coef(lm(yz~xz+sz)); cf1<-coef(lm(yz~xz)); cfr<-coef(lm(yr~xr+sr))
      .(b_ctl=unname(cf[2]), b_raw=unname(cf1[2]), b_rank=unname(cfr[2]), n=sum(ok))
    } else .(b_ctl=NA_real_,b_raw=NA_real_,b_rank=NA_real_,n=sum(ok)) }, by=Date][is.finite(b_ctl)]
  say("=== %s  n_month=%d avg_n=%.0f", f, nrow(s), mean(s$n))
  say("    raw    b %+.4f  NWt(3) %+.2f", mean(s$b_raw), nw_t(s$b_raw))
  say("    +logSz b %+.4f  NWt(3) %+.2f  [reported -4.29 / -4.33]", mean(s$b_ctl), nw_t(s$b_ctl))
  say("    NW lag sensitivity on b_ctl: L0 %+.2f L3 %+.2f L6 %+.2f L12 %+.2f L24 %+.2f",
      nw_t(s$b_ctl,0L), nw_t(s$b_ctl,3L), nw_t(s$b_ctl,6L), nw_t(s$b_ctl,12L), nw_t(s$b_ctl,24L))
  ac <- acf(s$b_ctl, lag.max=24, plot=FALSE)$acf[-1]
  say("    b_ctl ACF r1 %.3f r3 %.3f r6 %.3f r12 %.3f", ac[1],ac[3],ac[6],ac[12])
  say("    RANK-based (winsor-free) b %+.4f  NWt %+.2f  <- level-outlier robustness", mean(s$b_rank), nw_t(s$b_rank))
  say("    monthly sign: negative in %d/%d (%.1f%%)", sum(s$b_ctl<0), nrow(s), 100*mean(s$b_ctl<0))
}
say("done")
