#==============================================================================
# EIGEN-ENTRY cheap SCREEN — λ1-share (Absorption Ratio k=1) timing signal
# event-study around 4 canonical bear dates + RE_MRS incremental control
# SCREEN ONLY. read-only inputs. PIT: feature uses trailing window <= t (t-1 backward
# for decision use). lockbox strict 2023-12-22 for any "research" claim; here event-study
# anchors are historical bear dates all < lockbox so no lockbox issue for the lead-time test.
#==============================================================================
suppressPackageStartupMessages({library(arrow); library(data.table)})
PR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
set.seed(1)

LOOKBACK <- 60L          # trailing trading days for corr matrix (daily)
MIN_DAYS_PCT <- 0.80
MIN_STOCKS <- 50L
H <- 21L                 # forward horizon for label (matches bear_date_audit)
STEP <- 1L               # compute every trading day? -> too heavy; subsample below

# ---- load returns, restrict to KOSPI200 ∪ KOSDAQ150 universe ----
cat("[load] rawdata...\n")
raw <- as.data.table(read_parquet(file.path(PR,".cache/rawdata.parquet"),
        col_select=c("Date","Ticker","Ret","K200","KQ150")))
raw[,Date:=as.Date(Date)]
raw <- raw[!is.na(Ret) & !is.na(Ticker)]
# universe membership: K200==1 or KQ150==1 (PIT: these are point-in-time index flags in rawdata)
raw <- raw[ (K200==1 | KQ150==1) ]
setorder(raw, Date)
trading_dates <- sort(unique(raw$Date))
cat(sprintf("[load] %d rows, %d trading days, universe-filtered\n", nrow(raw), length(trading_dates)))

td_idx <- data.table(Date=trading_dates, idx=seq_along(trading_dates)); setkey(td_idx, Date)

# ---- benchmark for forward label ----
bm <- as.data.table(read_parquet(file.path(PR,".cache/benchmark.parquet")))
bm[,Date:=as.Date(Date)]; setorder(bm,Date)
bm <- unique(bm, by="Date")
# forward H-day return r(t,t+H) = BM[t+H]/BM[t]-1 ; CORRECT convention (shift lead +H)
bm[, fwd_H := shift(BM_Close, n=H, type="lead")/BM_Close - 1]

# ---- compute λ1-share daily (subsample every 1 day from 1995 to keep tractable) ----
# Cheap-but-dense: coarse grid every 5 trading days from 2007 (for regression/base rate)
# UNION dense daily in +/-100 calendar days around each of the 4 bear dates (for lead-time).
BEAR0 <- as.Date(c("2008-09-15","2011-08-08","2020-02-19","2022-09-26"))
base_grid <- trading_dates[trading_dates >= as.Date("2007-01-01")]
coarse <- base_grid[seq(1L, length(base_grid), by=5L)]
dense  <- base_grid[ Reduce(`|`, lapply(BEAR0, function(b) base_grid>=(b-100) & base_grid<=(b+40))) ]
calc_dates <- sort(unique(c(coarse, dense)))
cat(sprintf("[ar] computing λ1-share on %d days (coarse-5d + dense around bears)\n", length(calc_dates)))

compute_lambda1_share <- function(end_date) {
  avail <- td_idx[Date <= end_date]
  if (nrow(avail)==0) return(NA_real_)
  end_idx <- avail[.N, idx]
  if (end_idx < LOOKBACK) return(NA_real_)
  start_idx <- end_idx - LOOKBACK + 1L
  wdates <- trading_dates[start_idx:end_idx]
  wd <- raw[Date %in% wdates]
  if (nrow(wd)==0) return(NA_real_)
  min_days <- floor(length(wdates)*MIN_DAYS_PCT)
  sc <- wd[, .N, by=Ticker]
  valid <- sc[N>=min_days, Ticker]
  if (length(valid) < MIN_STOCKS) return(NA_real_)
  rw <- dcast(wd[Ticker %in% valid], Date ~ Ticker, value.var="Ret")
  m <- as.matrix(rw[,-1])
  cv <- apply(m,2,var,na.rm=TRUE)
  keep <- !is.na(cv) & cv>1e-10
  if (sum(keep) < MIN_STOCKS) return(NA_real_)
  m <- m[,keep]; m[is.na(m)] <- 0
  cm <- tryCatch(cor(m, use="pairwise.complete.obs"), error=function(e) NULL)
  if (is.null(cm)) return(NA_real_)
  cm[is.na(cm)] <- 0; diag(cm) <- 1
  eg <- tryCatch(eigen(cm, symmetric=TRUE, only.values=TRUE), error=function(e) NULL)
  if (is.null(eg)) return(NA_real_)
  lam <- pmax(0, eg$values); tot <- sum(lam)
  if (tot < 1e-10) return(NA_real_)
  max(lam)/tot   # λ1-share = AR(k=1) = 1st-eigenmode concentration
}

l1 <- vapply(calc_dates, compute_lambda1_share, numeric(1))
ar <- data.table(Date=calc_dates, lambda1_share=l1)
ar <- ar[!is.na(lambda1_share)]
cat(sprintf("[ar] computed %d valid days. λ1-share mean=%.3f sd=%.3f range=[%.3f,%.3f]\n",
    nrow(ar), mean(ar$lambda1_share), sd(ar$lambda1_share),
    min(ar$lambda1_share), max(ar$lambda1_share)))

# expanding z-score (PIT: use only past values, including current) for "spike" definition
ar[, l1_z := { v<-lambda1_share; out<-rep(NA_real_,.N)
  for(i in seq_len(.N)){ p<-v[1:i]; if(i>=60){ s<-sd(p); if(!is.na(s)&&s>1e-8) out[i]<-(v[i]-mean(p))/s } }; out }]

# attach RE_MRS control. regime_daily_v2.parquet has clean daily MRS from 2000-01-01.
ur <- as.data.table(read_parquet(file.path(PR,".cache/regime_daily_v2.parquet")))
ur[,Date:=as.Date(Date)]; ur <- ur[!is.na(MRS),.(Date, mrs=MRS)]
setorder(ur, Date)
# expanding z-score of MRS (PIT: past-only)
ur[, mrs_z := { v<-mrs; out<-rep(NA_real_,.N)
  for(i in seq_len(.N)){ p<-v[1:i]; if(i>=60){ s<-sd(p,na.rm=TRUE); if(!is.na(s)&&s>1e-8) out[i]<-(v[i]-mean(p,na.rm=TRUE))/s } }; out }]
setkey(ar,Date); setkey(ur,Date)
ar <- ur[ar, roll=TRUE]   # roll MRS forward to AR days; MRS as of <= Date (PIT)
setkey(bm,Date)
ar <- bm[,.(Date, fwd_H)][ar, on="Date"]

saveRDS(ar, file.path(PR,".cache/eigen_entry_ar.rds"))
cat("[ar] saved series.\n")

#==============================================================================
# EVENT STUDY: lead-time of λ1-share spike before 4 bear dates
#==============================================================================
BEAR <- as.Date(c("2008-09-15","2011-08-08","2020-02-19","2022-09-26"))
names(BEAR) <- c("Lehman","Euro","COVID","Stagflation")

# define "spike" threshold = l1_z >= 1.0 (1 sd above expanding mean)
SPIKE_Z <- 1.0

setorder(ar,Date)
ev <- list()
for (nm in names(BEAR)) {
  bd <- BEAR[nm]
  # nearest ar Date <= bear date
  pre <- ar[Date <= bd]
  if (nrow(pre)==0) { ev[[nm]] <- list(name=nm, status="no_data"); next }
  anchor_idx <- nrow(pre)
  # look back up to 90 calendar days; find first day (closest to bear) where l1_z crossed spike going forward into bear
  win <- ar[Date >= (bd-90) & Date <= bd]
  setorder(win, Date)
  # lead-time = days from first sustained spike (l1_z>=SPIKE_Z that persists to bear) to bear date
  above <- win[l1_z >= SPIKE_Z]
  lead_days <- NA_integer_
  if (nrow(above)>0) {
    # first crossing in the 90d pre-window
    first_cross <- min(above$Date)
    lead_days <- as.integer(bd - first_cross)
  }
  l1_at_bear <- win[Date==max(win$Date), lambda1_share]
  l1z_at_bear <- win[Date==max(win$Date), l1_z]
  mrs_at_bear <- win[Date==max(win$Date), mrs_z]
  ev[[nm]] <- list(name=nm, bear_date=as.character(bd),
                   lead_days_z1=lead_days,
                   l1_at_bear=round(l1_at_bear,3), l1z_at_bear=round(l1z_at_bear,2),
                   mrsz_at_bear=round(mrs_at_bear,2),
                   n_pre_window=nrow(win))
}
cat("\n=== EVENT STUDY (λ1-share spike lead before bear) ===\n")
for(nm in names(ev)) print(ev[[nm]])

#==============================================================================
# INCREMENTAL over RE_MRS: does l1_z predict forward bear return beyond mrs_z?
# Cross-sectional over TIME (full sample, all calc days) — regression fwd_H ~ mrs_z + l1_z
# This tells if λ1-share carries info orthogonal to RE_MRS for forward drawdown.
#==============================================================================
reg <- ar[!is.na(fwd_H) & !is.na(l1_z) & !is.na(mrs_z)]
cat(sprintf("\n[reg] n=%d obs for incremental regression\n", nrow(reg)))
# univariate
m_mrs <- lm(fwd_H ~ mrs_z, data=reg)
m_l1  <- lm(fwd_H ~ l1_z,  data=reg)
m_both<- lm(fwd_H ~ mrs_z + l1_z, data=reg)
s_mrs <- summary(m_mrs); s_l1 <- summary(m_l1); s_both <- summary(m_both)
cat(sprintf("[reg] univ mrs_z:  coef=%.5f t=%.2f R2=%.4f\n",
    coef(s_mrs)["mrs_z","Estimate"], coef(s_mrs)["mrs_z","t value"], s_mrs$r.squared))
cat(sprintf("[reg] univ l1_z:   coef=%.5f t=%.2f R2=%.4f\n",
    coef(s_l1)["l1_z","Estimate"], coef(s_l1)["l1_z","t value"], s_l1$r.squared))
cat(sprintf("[reg] both mrs_z:  coef=%.5f t=%.2f\n",
    coef(s_both)["mrs_z","Estimate"], coef(s_both)["mrs_z","t value"]))
cat(sprintf("[reg] both l1_z:   coef=%.5f t=%.2f (incremental over mrs)\n",
    coef(s_both)["l1_z","Estimate"], coef(s_both)["l1_z","t value"]))
cat(sprintf("[reg] R2 mrs-only=%.4f  both=%.4f  deltaR2=%.4f\n",
    s_mrs$r.squared, s_both$r.squared, s_both$r.squared - s_mrs$r.squared))
# orthogonality: correlation of l1_z and mrs_z
cat(sprintf("[reg] cor(l1_z, mrs_z)=%.3f\n", cor(reg$l1_z, reg$mrs_z)))

# residualize l1_z on mrs_z, re-run event-anchored: is residual elevated pre-bear?
reg[, l1_resid := residuals(lm(l1_z ~ mrs_z, data=reg))]
ar2 <- merge(ar, reg[,.(Date,l1_resid)], by="Date", all.x=TRUE)
cat("\n=== residual(l1_z|mrs_z) at bear dates ===\n")
for(nm in names(BEAR)){
  bd<-BEAR[nm]; r<-ar2[Date<=bd]; if(nrow(r)==0) next
  cat(sprintf("  %s %s: l1_resid=%.2f\n", nm, as.character(bd), tail(r$l1_resid,1)))
}

# save findings JSON
out <- list(
  screen="EIGEN-ENTRY", test_type="event_study + RE_MRS incremental regression",
  lookback_days=LOOKBACK, horizon_H=H, n_ar_days=nrow(ar),
  l1_mean=round(mean(ar$lambda1_share),4), l1_sd=round(sd(ar$lambda1_share),4),
  events=ev,
  reg_n=nrow(reg),
  mrs_univ_t=round(coef(s_mrs)["mrs_z","t value"],2),
  l1_univ_t=round(coef(s_l1)["l1_z","t value"],2),
  l1_incremental_t=round(coef(s_both)["l1_z","t value"],2),
  l1_incremental_coef=round(coef(s_both)["l1_z","Estimate"],6),
  deltaR2_l1_over_mrs=round(s_both$r.squared - s_mrs$r.squared,5),
  cor_l1_mrs=round(cor(reg$l1_z, reg$mrs_z),3)
)
jsonlite::write_json(out, file.path(PR,".cache/eigen_entry_findings.json"), auto_unbox=TRUE, pretty=TRUE)
cat("\n[done] findings written.\n")
