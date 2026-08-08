suppressPackageStartupMessages({library(data.table);library(arrow);library(sandwich);library(lmtest)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
IN9 <- "stage_artifacts/WT_D20260802_009"; OUT <- "stage_artifacts/WT_D20260808_001"
say <- function(fmt,...) cat(sprintf(paste0("[v] ",fmt,"\n"),...))
BASE <- as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[, Date := as.Date(Date)]
TUNED<- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date := as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))[, Date := as.Date(Date)]
say("RAWDATA nrow=%d n_day=%d %s~%s", nrow(RAW), uniqueN(RAW$Date), min(RAW$Date), max(RAW$Date))
RAW[, ym := format(Date,"%Y-%m")]
MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE), .(Date,Ticker)]
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt   <- as.data.table(fwd$bench_dt)[, .(Date=as.Date(Date),BM_Ret)]
liq_dt     <- as.data.table(fwd$liq_dt)[, .(Date=as.Date(Date),Ticker,adv)]
say("returns nrow=%d n_month=%d %s~%s | bench n=%d", nrow(returns_dt), uniqueN(returns_dt$Date),
    min(returns_dt$Date), max(returns_dt$Date), nrow(bench_dt))
score_of <- function(f){ sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name==f,.(Date,Ticker,score=z)] else TUNED[Factor_Name==f,.(Date,Ticker,score=score)]
  merge(sc[!is.na(score)],UNIV,by=c("Date","Ticker")) }
FILT <- c("D03_EWMA","Q01_EB")
SC_M01 <- score_of("M01_PATHQ")
E <- merge(SC_M01, liq_dt, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]
setorder(E,Date,-score); E[, rk:=seq_len(.N), by=Date]; E <- E[Date %in% returns_dt$Date]
FZ <- rbindlist(lapply(FILT,function(f) score_of(f)[,.(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ, E[,.(Date,Ticker)], by=c("Date","Ticker"))
FZ[, q_rank := frank(fz)/.N, by=.(Date,F_)]
say("eligible %d행 / %d개월", nrow(E), uniqueN(E$Date))

RM <- merge(returns_dt, bench_dt, by="Date")
dts <- sort(unique(E$Date))
beta_l <- vector("list", length(dts))
for (i in seq_along(dts)) {
  if (i <= 36L) next
  w <- RM[Date %in% dts[max(1L,i-60L):(i-1L)]]
  bb <- w[, { ok <- is.finite(Ret_1m)&is.finite(BM_Ret)
    if (sum(ok)>=24L && var(BM_Ret[ok])>0) .(beta=cov(Ret_1m[ok],BM_Ret[ok])/var(BM_Ret[ok]),nb=sum(ok))
    else .(beta=NA_real_,nb=sum(ok)) }, by=Ticker][is.finite(beta)]
  bb[, Date := dts[i]]; beta_l[[i]] <- bb[,.(Date,Ticker,beta)]
}
BETA <- rbindlist(beta_l)
say("BETA panel %d행 / %d개월", nrow(BETA), uniqueN(BETA$Date))
saveRDS(BETA, "stage_artifacts/wt001_verify/BETA.rds")

nw_t <- function(x,lag=3L){x<-x[is.finite(x)];fit<-lm(x~1)
  as.numeric(lmtest::coeftest(fit,vcov.=sandwich::NeweyWest(fit,lag=lag,prewhite=FALSE))[1,3])}
res <- list()
for (f in FILT) {
  D <- merge(FZ[F_==f,.(Date,Ticker,fz,q_rank)], BETA, by=c("Date","Ticker"))
  s <- D[, .(b_top=median(beta[q_rank>0.8]), b_med=median(beta), b_bot=median(beta[q_rank<=0.2])), by=Date]
  s <- s[is.finite(b_top)&is.finite(b_med)][order(Date)]
  d <- s$b_top - s$b_med
  say("%s: n=%d  mean(diff)=%+.4f  top=%.4f  univ=%.4f  NWlag3 t=%+.2f", f, length(d), mean(d),
      mean(s$b_top), mean(s$b_med), nw_t(d,3L))
  ac <- acf(d, lag.max=72, plot=FALSE)$acf[,,1]
  say("  ACF rho1=%.3f rho3=%.3f rho6=%.3f rho12=%.3f rho24=%.3f rho36=%.3f rho60=%.3f rho72=%.3f",
      ac[2],ac[4],ac[7],ac[13],ac[25],ac[37],ac[61],ac[73])
  for (L in c(0,3,6,12,24,36,48,60,72)) say("  NW lag=%2d -> t=%+.2f", L, nw_t(d,L))
  bw <- bwAndrews(lm(d~1), kernel="Bartlett", approx="AR(1)")
  say("  Andrews auto bandwidth (Bartlett) = %.1f", bw)
  fit <- lm(d~1)
  tA <- as.numeric(coeftest(fit, vcov.=sandwich::kernHAC(fit, kernel="Bartlett", bw=bwAndrews, prewhite=FALSE))[1,3])
  tNWauto <- as.numeric(coeftest(fit, vcov.=sandwich::NeweyWest(fit, prewhite=FALSE))[1,3])
  say("  t(Andrews auto)=%+.2f   t(NeweyWest auto bw)=%+.2f", tA, tNWauto)
  # non-overlapping: every 60th obs
  for (off in 1:3) { idx <- seq(off, length(d), by=60L); say("  non-overlap step60 off=%d n=%d mean=%+.4f t=%+.2f",
      off, length(idx), mean(d[idx]), mean(d[idx])/(sd(d[idx])/sqrt(length(idx)))) }
  res[[f]] <- list(d=d, dates=s$Date)
}
saveRDS(res, "stage_artifacts/wt001_verify/beta_diff_series.rds")
