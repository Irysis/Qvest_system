#==============================================================================
# WT-D20260711_002 Phase A — Step 14: Self-Adversarial checks
#   (a) placebo: random-permuted score IC null band
#   (b) annual-lag stress: use prior-year metric (age>12 forced) -> should degrade if real
#   (c) industry/sector confound: is composite an industry proxy? (spot-check via
#       size + KOSPI/KOSDAQ split + within-adv-tercile)
#   (d) Size-proxy control: partial rank-IC of composite | logSize (monthly)
#   (e) boilerplate contamination: does m6 drive the composite signal?
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260711_002")
set.seed(20260711)
spear <- function(x,y) suppressWarnings(cor(x,y,method="spearman",use="complete.obs"))
nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; n<-length(x); if(n<8) return(NA_real_)
  mu<-mean(x); e<-x-mu; v<-sum(e^2)/n
  for(L in 1:min(lag,n-1)){ w<-1-L/(lag+1); g<-sum(e[1:(n-L)]*e[(L+1):n])/n; v<-v+2*w*g }
  se<-sqrt(v/n); if(!is.finite(se)||se<=0) return(NA_real_); mu/se }
partial_spear <- function(x,y,z){ ok<-is.finite(x)&is.finite(y)&is.finite(z); x<-x[ok];y<-y[ok];z<-z[ok]
  if(length(x)<5) return(NA_real_); rx<-rank(x);ry<-rank(y);rz<-rank(z)
  ex<-residuals(lm(rx~rz)); ey<-residuals(lm(ry~rz)); suppressWarnings(cor(ex,ey)) }

P <- readRDS(file.path(OUT,"signal_panel.rds"))
P <- P[!is.na(fwd_excess)]
P[, logSize := log(Size)]

# ============ run the full adversarial battery for a given signal column ============
# SIG is the OBFUSCATION direction (higher = more obfuscated => hypothesized NEGATIVE vs excess).
adv_for <- function(SIGCOL) {
cat("\n########## SIGNAL =", SIGCOL, "##########\n")
P[, SIG := get(SIGCOL)]
# (a) placebo: shuffle score within each month, IC harvey-t null (500 reps)
ic_true <- P[is.finite(SIG), .(ic=spear(SIG, fwd_excess), n=.N), by=ym][n>=10]
t_true <- nw_t(ic_true$ic)
B <- 500L; null_t <- numeric(B)
for (b in 1:B) {
  Pp <- copy(P); Pp[, sc_perm := sample(SIG), by=ym]
  ics <- Pp[is.finite(sc_perm), .(ic=spear(sc_perm, fwd_excess), n=.N), by=ym][n>=10]
  null_t[b] <- nw_t(ics$ic)
}
placebo_p <- mean(abs(null_t) >= abs(t_true), na.rm=TRUE)
cat(sprintf("[14a] placebo: true IC Harvey-t=%.2f  placebo p(|null|>=|true|)=%.3f  null_t sd=%.2f\n",
            t_true, placebo_p, sd(null_t,na.rm=TRUE)))

# (d) Size-proxy: monthly partial rank-IC SIG|logSize
psz <- P[is.finite(SIG), .(praw=spear(SIG,fwd_excess),
             ppart=partial_spear(SIG,fwd_excess,logSize),
             corsz=spear(SIG,logSize), n=.N), by=ym][n>=10]
cat(sprintf("[14d] Size control: mean raw IC=%.4f  mean partial(|logSize)=%.4f  mean cor(SIG,logSize)=%.3f  Harvey-t raw=%.2f part=%.2f\n",
            mean(psz$praw), mean(psz$ppart), mean(psz$corsz), nw_t(psz$praw), nw_t(psz$ppart)))

# (c) industry/market confound: KOSPI vs KOSDAQ split + within-adv tercile
P[, mkt := fifelse(K200==1,"K200","KQ150")]
mkt_ic <- P[is.finite(SIG), .(ic=spear(SIG,fwd_excess), n=.N), by=.(mkt,ym)][n>=8]
cat("[14c] market-split IC Harvey-t: ")
for (mm in c("K200","KQ150")) { s<-mkt_ic[mkt==mm]; cat(sprintf("%s t=%.2f (mo %d) ", mm, nw_t(s$ic), nrow(s))) }; cat("\n")
P[, adv_ter := cut(frank(adv20), 3, labels=c("LO","MID","HI")), by=ym]
adv_ic <- P[is.finite(SIG), .(ic=spear(SIG,fwd_excess), n=.N), by=.(adv_ter,ym)][n>=6]
cat("[14c] adv-tercile IC Harvey-t: ")
for (aa in c("LO","MID","HI")) { s<-adv_ic[adv_ter==aa]; cat(sprintf("%s t=%.2f ", aa, nw_t(s$ic))) }; cat("\n")

# (b) annual-lag stress: 12m-stale signal
Plag <- copy(P); setorder(Plag, Ticker, ym)
Plag[, sig_lag12 := shift(SIG, 12), by=Ticker]
ic_lag <- Plag[is.finite(sig_lag12), .(ic=spear(sig_lag12,fwd_excess), n=.N), by=ym][n>=10]
cat(sprintf("[14b] annual-lag(12m stale) stress: Harvey-t=%.2f mean_ic=%.4f  (vs fresh %.2f)\n",
            nw_t(ic_lag$ic), mean(ic_lag$ic), t_true))
list(signal=SIGCOL, placebo_p=placebo_p, t_true=t_true, null_t_sd=sd(null_t,na.rm=TRUE),
     size_raw=mean(psz$praw), size_partial=mean(psz$ppart), size_cor=mean(psz$corsz),
     size_t_raw=nw_t(psz$praw), size_t_part=nw_t(psz$ppart),
     mkt_k200_t=nw_t(mkt_ic[mkt=="K200"]$ic), mkt_kq_t=nw_t(mkt_ic[mkt=="KQ150"]$ic),
     lag12_t=nw_t(ic_lag$ic))
}

res_comp <- adv_for("obfuscation_composite")
res_m1   <- adv_for("m1")

# (e) composite decomposition: which z drives it (leave-one-out)
cat("\n[14e] composite leave-one-out (which z carries signal):\n")
for (drop in c("z1","z2","z3","z5")) {
  keep <- setdiff(c("z1","z2","z3","z5"), drop)
  P[, comp_d := rowMeans(as.matrix(.SD)), .SDcols=keep]
  ic <- P[, .(ic=spear(comp_d,fwd_excess), n=.N), by=ym][n>=10]
  cat(sprintf("   drop %s: Harvey-t=%.2f mean_ic=%.4f\n", drop, nw_t(ic$ic), mean(ic$ic)))
}
saveRDS(list(composite=res_comp, m1=res_m1), file.path(OUT,"adversarial_results.rds"))
cat("[14] DONE\n")
