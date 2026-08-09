# Read-only verification A: beta-drag alternative explanations + quintile mean/median/skew
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
VER <- file.path(ROOT, "stage_artifacts/wt001_verify")
IN9 <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
say <- function(fmt, ...) cat(sprintf(paste0("[vA] ", fmt, "\n"), ...))

FILT <- c("D03_EWMA","Q01_EB")
BASE <- as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[, Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date := as.Date(Date)]
say("INPUT base_panel nrow=%d factors=%s", nrow(BASE), paste(unique(BASE$Factor_Name), collapse=","))
say("INPUT tuned_panel nrow=%d factors=%s", nrow(TUNED), paste(unique(TUNED$Factor_Name), collapse=","))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Size","Vol","Close","K200","KQ150","Sector")))[, Date:=as.Date(Date)]
say("INPUT RAWDATA nrow=%d unit=DAILY n_day=%d range %s~%s", nrow(RAW), uniqueN(RAW$Date),
    as.character(min(RAW$Date)), as.character(max(RAW$Date)))
RAW[, ym := format(Date,"%Y-%m")]
MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE), .(Date,Ticker)]
say("month-end rows=%d  univ rows=%d", nrow(RAWME), nrow(UNIV))

fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt   <- as.data.table(fwd$bench_dt)[, .(Date=as.Date(Date),BM_Ret)]
liq_dt     <- as.data.table(fwd$liq_dt)[, .(Date=as.Date(Date),Ticker,adv)]
say("INPUT returns_dt nrow=%d MONTHLY n_month=%d", nrow(returns_dt), uniqueN(returns_dt$Date))

nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(NA_real_);f<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(f,vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}

score_of <- function(f){sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name==f,.(Date,Ticker,score=z)]
  else TUNED[Factor_Name==f,.(Date,Ticker,score=score)]; merge(sc[!is.na(score)],UNIV,by=c("Date","Ticker"))}
E <- merge(score_of("M01_PATHQ"), liq_dt, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]; setorder(E,Date,-score); E[, rk:=seq_len(.N), by=Date]
E <- E[Date %in% returns_dt$Date]
say("eligible E nrow=%d n_month=%d avg_names=%.1f", nrow(E), uniqueN(E$Date), nrow(E)/uniqueN(E$Date))
FZ <- rbindlist(lapply(FILT,function(f) score_of(f)[,.(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ, E[,.(Date,Ticker)], by=c("Date","Ticker")); FZ[, q_rank:=frank(fz)/.N, by=.(Date,F_)]

# ---- BETA panel (exact replication of run_wt122_measure.R lines 246-262)
RM <- merge(returns_dt, bench_dt, by="Date")
dts <- sort(unique(E$Date))
beta_l <- vector("list", length(dts))
for (i in seq_along(dts)) {
  if (i <= 36L) next
  w <- RM[Date %in% dts[max(1L,i-60L):(i-1L)]]
  bb <- w[, {ok <- is.finite(Ret_1m)&is.finite(BM_Ret)
    if (sum(ok)>=24L && var(BM_Ret[ok])>0) .(beta=cov(Ret_1m[ok],BM_Ret[ok])/var(BM_Ret[ok]))
    else .(beta=NA_real_)}, by=Ticker][is.finite(beta)]
  bb[, Date := dts[i]]; beta_l[[i]] <- bb[,.(Date,Ticker,beta)]
}
BETA <- rbindlist(beta_l)
say("BETA panel rows=%d months=%d", nrow(BETA), uniqueN(BETA$Date))

res <- list()
say("===== TEST A1: HAC lag sensitivity of the beta-gap t-stat =====")
for (f in FILT) {
  D <- merge(FZ[F_==f,.(Date,Ticker,fz,q_rank)], BETA, by=c("Date","Ticker"))
  s <- D[, .(b_top=median(beta[q_rank>0.8]), b_med=median(beta)), by=Date]
  s <- s[is.finite(b_top)&is.finite(b_med)][order(Date)]
  g <- s$b_top - s$b_med
  ac <- acf(g, lag.max=72, plot=FALSE)$acf[-1]
  say("%s: n=%d  gap mean=%.4f  reported NW3 t=%.2f", f, length(g), mean(g), nw_t(g,3L))
  say("   acf lag1=%.3f lag6=%.3f lag12=%.3f lag24=%.3f lag36=%.3f lag60=%.3f lag72=%.3f",
      ac[1],ac[6],ac[12],ac[24],ac[36],ac[60],ac[72])
  for (L in c(3L,6L,12L,24L,36L,60L,72L,120L))
    say("   NW lag=%3d  t=%+.3f", L, nw_t(g,L))
  # effective independent obs proxy
  say("   sum(1+2*sum acf up to 60) variance inflation = %.2f  -> effective n = %.1f",
      1+2*sum(ac[1:60]), length(g)/(1+2*sum(ac[1:60])))
  res[[paste0("gap_",f)]] <- g
}

say("===== TEST A2: is beta-gap mechanically implied by the sort variable? =====")
for (f in FILT) {
  D <- merge(FZ[F_==f,.(Date,Ticker,fz)], BETA, by=c("Date","Ticker"))
  cc <- D[, .(sp=cor(fz,beta,method="spearman")), by=Date]
  say("%s: monthly Spearman(factor z, trailing beta) mean=%+.3f  median=%+.3f  share<0=%.3f",
      f, mean(cc$sp), median(cc$sp), mean(cc$sp<0))
}

say("===== TEST A3: Q01 beta-gap after conditioning on D03 (vol) =====")
W <- dcast(FZ[,.(Date,Ticker,F_,fz)], Date+Ticker~F_, value.var="fz")
setnames(W, c("D03_EWMA","Q01_EB"), c("d03","q01"))
W <- merge(W, BETA, by=c("Date","Ticker"))
W <- W[is.finite(d03)&is.finite(q01)&is.finite(beta)]
# double sort: within D03 quintile, Q01 top-quintile beta vs D03-quintile median beta
W[, d03_q := cut(frank(d03), breaks=5, labels=FALSE), by=Date]
W[, q01_r := frank(q01)/.N, by=.(Date,d03_q)]
ds <- W[, .(b_top=median(beta[q01_r>0.8]), b_med=median(beta)), by=.(Date,d03_q)]
ds <- ds[is.finite(b_top)&is.finite(b_med)]
agg <- ds[, .(gap=mean(b_top-b_med), t3=nw_t(b_top-b_med,3L), t60=nw_t(b_top-b_med,60L), n=.N), by=d03_q][order(d03_q)]
print(agg)
pooled <- ds[, .(gap=mean(b_top-b_med)), by=Date]
say("Q01 beta-gap conditional on D03 quintile (pooled over 5 buckets): mean=%.4f NW3 t=%.2f NW60 t=%.2f",
    mean(pooled$gap), nw_t(pooled$gap,3L), nw_t(pooled$gap,60L))
say("  (unconditional Q01 gap was -0.2489)")

say("===== TEST A4: sector composition of the top quintile (beta gap) =====")
SEC <- RAWME[, .(Date,Ticker,Sector)]
W2 <- merge(W, SEC, by=c("Date","Ticker"), all.x=TRUE)
W2[is.na(Sector), Sector:="UNKNOWN"]
for (f in c("d03","q01")) {
  W2[, qr := frank(get(f))/.N, by=Date]
  W2[, beta_sec_res := {ok<-is.finite(beta); r<-rep(NA_real_,.N)
      if (sum(ok)>=30L && uniqueN(Sector[ok])>=2L) r[ok] <- residuals(lm(beta[ok]~factor(Sector[ok]))); r}, by=Date]
  s2 <- W2[, .(g_raw = median(beta[qr>0.8])-median(beta),
               g_sec = median(beta_sec_res[qr>0.8],na.rm=TRUE)-median(beta_sec_res,na.rm=TRUE)), by=Date]
  s2 <- s2[is.finite(g_raw)&is.finite(g_sec)]
  say("%s: raw gap %.4f (NW3 t %.2f | NW60 t %.2f) -> sector-residual gap %.4f (NW3 t %.2f | NW60 t %.2f) retention %.2f",
      f, mean(s2$g_raw), nw_t(s2$g_raw,3L), nw_t(s2$g_raw,60L),
      mean(s2$g_sec), nw_t(s2$g_sec,3L), nw_t(s2$g_sec,60L), mean(s2$g_sec)/mean(s2$g_raw))
}

say("===== TEST B: D03 quintile mean vs median vs skewness (claim B) =====")
for (f in FILT) {
  D <- merge(FZ[F_==f,.(Date,Ticker,score=fz)], returns_dt, by=c("Date","Ticker"))
  mono <- D[, {
    if (.N>=20L && sd(score)>0) {
      q <- cut(frank(score), breaks=5, labels=FALSE)
      out <- list()
      for (k in 1:5) {
        rr <- Ret_1m[q==k]; rr <- rr[is.finite(rr)]
        m <- mean(rr); md <- median(rr); sdv <- sd(rr)
        sk <- if (length(rr)>2 && sdv>0) mean(((rr-m)/sdv)^3) else NA_real_
        out[[paste0("mean",k)]] <- m; out[[paste0("med",k)]] <- md
        out[[paste0("sk",k)]] <- sk; out[[paste0("sd",k)]] <- sdv
      }
      out
    } else NULL
  }, by=Date]
  say("-- %s --", f)
  mm <- sapply(1:5, function(k) mean(mono[[paste0("mean",k)]], na.rm=TRUE))
  md <- sapply(1:5, function(k) mean(mono[[paste0("med",k)]], na.rm=TRUE))
  sk <- sapply(1:5, function(k) mean(mono[[paste0("sk",k)]], na.rm=TRUE))
  sv <- sapply(1:5, function(k) mean(mono[[paste0("sd",k)]], na.rm=TRUE))
  say("  quintile ARITH mean ann%% Q1..Q5 : %s", paste(sprintf("%+.1f", 100*12*mm), collapse=" "))
  say("  quintile MEDIAN    ann%% Q1..Q5 : %s", paste(sprintf("%+.1f", 100*12*md), collapse=" "))
  say("  cross-sec SKEW (time-avg) Q1..Q5: %s", paste(sprintf("%+.2f", sk), collapse=" "))
  say("  cross-sec SD (monthly)   Q1..Q5 : %s", paste(sprintf("%.4f", sv), collapse=" "))
  say("  monotonicity(mean)=%.2f  monotonicity(median)=%.2f",
      mean(diff(mm)>0), mean(diff(md)>0))
  # variance-drag adjusted (diagnostic only, not a performance claim):
  # time-series of the equal-weighted quintile mean return
  qser <- sapply(1:5, function(k) mono[[paste0("mean",k)]])
  vdrag <- apply(qser, 2, function(x) 0.5*var(x, na.rm=TRUE))
  say("  quintile-portfolio monthly ts sd Q1..Q5 : %s", paste(sprintf("%.4f", apply(qser,2,sd,na.rm=TRUE)), collapse=" "))
  say("  variance-drag proxy (0.5*var, ann%%) Q1..Q5: %s", paste(sprintf("%.2f", 100*12*vdrag), collapse=" "))
  say("  arith minus drag proxy (ann%%) Q1..Q5    : %s", paste(sprintf("%+.1f", 100*12*(mm-vdrag)), collapse=" "))
}
say("=== vA done ===")
