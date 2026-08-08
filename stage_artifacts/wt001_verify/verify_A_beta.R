# Read-only reproduction of WT-D20260808_001 F3 (beta-drag, claim A)
# + autocorrelation diagnostics on the monthly gap series (overlapping 60m windows)
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest)
})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
IN9 <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
say <- function(fmt, ...) cat(sprintf(paste0("[verA] ", fmt, "\n"), ...))

FILT <- c("D03_EWMA","Q01_EB")
BASE  <- as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[, Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date := as.Date(Date)]
say("INPUT base_panel nrow=%d n_month=%d %s~%s", nrow(BASE), uniqueN(BASE$Date), min(BASE$Date), max(BASE$Date))
say("INPUT tuned_panel nrow=%d n_month=%d %s~%s", nrow(TUNED), uniqueN(TUNED$Date), min(TUNED$Date), max(TUNED$Date))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Size","K200","KQ150")))[, Date := as.Date(Date)]
say("INPUT RAWDATA nrow=%d n_day=%d %s~%s (DAILY - measured, not assumed)",
    nrow(RAW), uniqueN(RAW$Date), min(RAW$Date), max(RAW$Date))
RAW[, ym := format(Date,"%Y-%m")]
MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE), .(Date,Ticker)]

fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt   <- as.data.table(fwd$bench_dt)[,   .(Date=as.Date(Date),BM_Ret)]
liq_dt     <- as.data.table(fwd$liq_dt)[,     .(Date=as.Date(Date),Ticker,adv)]
say("INPUT fwd returns nrow=%d n_month=%d %s~%s", nrow(returns_dt), uniqueN(returns_dt$Date),
    min(returns_dt$Date), max(returns_dt$Date))

nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; if(length(x)<12L) return(NA_real_)
  f<-lm(x~1); tryCatch(as.numeric(lmtest::coeftest(f, vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]),
  error=function(e) NA_real_) }
nw_se <- function(x, lag=3L){ x<-x[is.finite(x)]; f<-lm(x~1)
  tryCatch(sqrt(sandwich::NeweyWest(f,lag=lag,prewhite=FALSE)[1,1]), error=function(e) NA_real_) }

score_of <- function(f){ sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name==f,.(Date,Ticker,score=z)]
  else TUNED[Factor_Name==f,.(Date,Ticker,score=score)]; merge(sc[!is.na(score)],UNIV,by=c("Date","Ticker")) }

E <- merge(score_of("M01_PATHQ"), liq_dt, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]; setorder(E,Date,-score); E[, rk:=seq_len(.N), by=Date]
E <- E[Date %in% returns_dt$Date]
FZ <- rbindlist(lapply(FILT, function(f) score_of(f)[,.(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ, E[,.(Date,Ticker)], by=c("Date","Ticker")); FZ[, q_rank := frank(fz)/.N, by=.(Date,F_)]
say("eligible %d rows / %d months / avg %.1f names", nrow(E), uniqueN(E$Date), E[,.N,by=Date][,mean(N)])

# ---- reproduce beta panel exactly as run_wt122_measure.R lines 245-277 -----
RM <- merge(returns_dt, bench_dt, by="Date")
dts <- sort(unique(E$Date))
beta_l <- vector("list", length(dts))
for (i in seq_along(dts)) {
  if (i <= 36L) next
  w <- RM[Date %in% dts[max(1L, i-60L):(i-1L)]]
  bb <- w[, { ok <- is.finite(Ret_1m)&is.finite(BM_Ret)
    if (sum(ok)>=24L && var(BM_Ret[ok])>0) .(beta=cov(Ret_1m[ok],BM_Ret[ok])/var(BM_Ret[ok]))
    else .(beta=NA_real_) }, by=Ticker][is.finite(beta)]
  bb[, Date := dts[i]]; beta_l[[i]] <- bb[, .(Date,Ticker,beta)]
}
BETA <- rbindlist(beta_l)
say("beta panel %d rows / %d months (trailing 60m, min 24 obs, current month excluded)",
    nrow(BETA), uniqueN(BETA$Date))

for (f in FILT) {
  D <- merge(FZ[F_==f,.(Date,Ticker,fz,q_rank)], BETA, by=c("Date","Ticker"))
  s <- D[, .(b_top=median(beta[q_rank>0.8]), b_med=median(beta), b_bot=median(beta[q_rank<=0.2])), by=Date]
  s <- s[is.finite(b_top)&is.finite(b_med)][order(Date)]
  g <- s$b_top - s$b_med
  say("--- %s : top %.3f  univ %.3f  gap %+.3f  n_month=%d", f, mean(s$b_top), mean(s$b_med), mean(g), nrow(s))
  say("    NW t by lag: L0(OLS) %+.2f | L3 %+.2f | L6 %+.2f | L12 %+.2f | L24 %+.2f | L36 %+.2f | L60 %+.2f",
      nw_t(g,0L), nw_t(g,3L), nw_t(g,6L), nw_t(g,12L), nw_t(g,24L), nw_t(g,36L), nw_t(g,60L))
  ac <- acf(g, lag.max=72, plot=FALSE)$acf[-1]
  say("    gap ACF: r1 %.3f r3 %.3f r6 %.3f r12 %.3f r24 %.3f r36 %.3f r48 %.3f r60 %.3f r72 %.3f",
      ac[1],ac[3],ac[6],ac[12],ac[24],ac[36],ac[48],ac[60],ac[72])
  # effective sample size under AR structure
  n <- length(g); ess <- n / (1 + 2*sum(ac[1:min(60,length(ac))]*(1-(1:min(60,length(ac)))/n)))
  say("    n=%d  crude ESS(Bartlett,60) = %.1f  -> naive-vs-ESS t shrink factor %.2f",
      n, ess, sqrt(max(ess,1)/n))
  say("    sign of monthly gap: negative in %d/%d months (%.1f%%)  min %+.3f max %+.3f",
      sum(g<0), length(g), 100*mean(g<0), min(g), max(g))
  # non-overlapping subsample: every 60th month
  for (off in 1:3) {
    idx <- seq(off, length(g), by=60L)
    say("    non-overlap stride60 offset=%d: n=%d mean %+.3f  t(OLS) %+.2f",
        off, length(idx), mean(g[idx]), if(length(idx)>2) mean(g[idx])/(sd(g[idx])/sqrt(length(idx))) else NA_real_)
  }
}
saveRDS(list(BETA=BETA), file.path(ROOT,"stage_artifacts/wt001_verify/betaA.rds"))
say("done")
