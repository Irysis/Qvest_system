#==============================================================================
# R20 Step 02 — index reconstruction (base / ex-flagged / random x3) per universe,
#   tail-risk metric contrast + block-bootstrap CI + audit-quality gradient.
#   PerformanceAnalytics standard fns for all performance metrics. single-thread.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(xts); library(PerformanceAnalytics) })
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
set.seed(20260713)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260713_004")
pan  <- readRDS(file.path(OUT,"panel_r20.rds"))

ym2date <- function(ym) as.Date(sprintf("%d-%02d-01", ym%/%100L, ym%%100L))
DECILE <- 0.90; SEEDS <- c(101L,202L,303L)

# universe membership predicate on a monthly slice dt
u_members <- function(dt, U){
  switch(U,
    K200       = dt[K200_prev==1],
    KQ150      = dt[KQ150_prev==1],
    KOSPI_all  = dt[exch=="KOSPI"],
    KOSDAQ_all = dt[exch=="KOSDAQ"])
}

# build monthly return series for one universe over a set of months
build_series <- function(pan, U, months, ew=FALSE){
  base <- exfl <- numeric(length(months)); rands <- matrix(NA_real_, length(months), length(SEEDS))
  kvec <- integer(length(months)); nmem <- integer(length(months)); nsc <- integer(length(months))
  for(i in seq_along(months)){
    m <- months[i]; d <- u_members(pan[ym==m], U)
    d <- d[is.finite(ret_m) & is.finite(Size_prev) & Size_prev>0]
    n <- nrow(d); nmem[i] <- n
    if(n < 5L){ base[i]<-exfl[i]<-NA; rands[i,]<-NA; next }
    w <- if(ew) rep(1/n, n) else d$Size_prev/sum(d$Size_prev)
    base[i] <- sum(w * d$ret_m)
    sc <- which(is.finite(d$bf_raw)); nsc[i] <- length(sc)
    if(length(sc) >= 10L){
      thr <- quantile(d$bf_raw[sc], DECILE, na.rm=TRUE, names=FALSE)
      flag <- sc[ d$bf_raw[sc] >= thr ]; k <- length(flag); kvec[i] <- k
      keep <- setdiff(seq_len(n), flag)
      wk <- if(ew) rep(1/length(keep), length(keep)) else d$Size_prev[keep]/sum(d$Size_prev[keep])
      exfl[i] <- sum(wk * d$ret_m[keep])
      for(s in seq_along(SEEDS)){
        set.seed(SEEDS[s]*100000L + m)
        rm_i <- sample(seq_len(n), k)
        kp <- setdiff(seq_len(n), rm_i)
        wr <- if(ew) rep(1/length(kp), length(kp)) else d$Size_prev[kp]/sum(d$Size_prev[kp])
        rands[i,s] <- sum(wr * d$ret_m[kp])
      }
    } else { exfl[i] <- base[i]; rands[i,] <- base[i]; kvec[i] <- 0L }
  }
  ok <- is.finite(base) & is.finite(exfl) & apply(rands,1,function(x) all(is.finite(x)))
  list(months=months[ok], base=base[ok], exfl=exfl[ok],
       rand=rands[ok,,drop=FALSE], randmean=rowMeans(rands[ok,,drop=FALSE]),
       k=kvec[ok], nmem=nmem[ok], nsc=nsc[ok])
}

# risk metrics on a monthly return vector (PerformanceAnalytics standard)
rmetrics <- function(r, months){
  x <- xts(r, order.by=ym2date(months))
  ann_ret <- as.numeric(Return.annualized(x, scale=12, geometric=TRUE))
  ann_vol <- as.numeric(StdDev.annualized(x, scale=12))
  mdd     <- as.numeric(maxDrawdown(x))
  dd      <- as.numeric(DownsideDeviation(r, MAR=0))
  srt     <- sort(r)
  worst5  <- mean(srt[1:min(5,length(srt))])
  cvar20  <- mean(r[r <= quantile(r,0.20,na.rm=TRUE)])
  c(ann_ret=ann_ret, ann_vol=ann_vol, mdd=mdd, dd=dd, worst5=worst5, cvar20=cvar20)
}

# block bootstrap CI on metric DIFFERENCES (exfl-base, exfl-randmean)
boot_ci <- function(S, nsim=2000, block=12){
  N <- length(S$base); if(N < block+2) return(NULL)
  mets <- c("ann_ret","ann_vol","mdd","dd","worst5","cvar20")
  D_eb <- matrix(NA_real_, nsim, length(mets)); D_er <- matrix(NA_real_, nsim, length(mets))
  colnames(D_eb) <- colnames(D_er) <- mets
  nblk <- ceiling(N/block)
  for(b in 1:nsim){
    starts <- sample(1:(N-block+1), nblk, replace=TRUE)
    idx <- as.integer(unlist(lapply(starts, function(s) s:(s+block-1))))[1:N]
    mm <- S$months[idx]
    mb <- rmetrics(S$base[idx], mm); me <- rmetrics(S$exfl[idx], mm); mr <- rmetrics(S$randmean[idx], mm)
    D_eb[b,] <- me - mb; D_er[b,] <- me - mr
  }
  list(eb=apply(D_eb,2,quantile,c(.05,.5,.95),na.rm=TRUE),
       er=apply(D_er,2,quantile,c(.05,.5,.95),na.rm=TRUE))
}

run_universe <- function(pan, U, months, label){
  Sc <- build_series(pan, U, months, ew=FALSE)   # cap-w authoritative
  Se <- build_series(pan, U, months, ew=TRUE)    # EW diagnostic
  if(length(Sc$base) < 24) { cat("[skip]",label,"too few months\n"); return(NULL) }
  mb <- rmetrics(Sc$base, Sc$months); me <- rmetrics(Sc$exfl, Sc$months)
  mr <- rmetrics(Sc$randmean, Sc$months)
  mb_ew<-rmetrics(Se$base,Se$months); me_ew<-rmetrics(Se$exfl,Se$months); mr_ew<-rmetrics(Se$randmean,Se$months)
  ci <- boot_ci(Sc)
  list(universe=U, label=label, n_months=length(Sc$months),
       k_mean=mean(Sc$k), nmem_mean=mean(Sc$nmem), nsc_mean=mean(Sc$nsc),
       capw=list(base=mb, exfl=me, rand=mr), ew=list(base=mb_ew, exfl=me_ew, rand=mr_ew),
       ci=ci, series=Sc)
}

# ---- PRIMARY window: 2010-01 .. 2015-12 (all universes >=98% Benford coverage) ----
prim_months <- sort(unique(pan[ym>=201001 & ym<=201512]$ym))
cat("[02] PRIMARY window months:", length(prim_months),
    " range:", paste(range(prim_months),collapse=".."),"\n\n")
US <- c("K200","KQ150","KOSPI_all","KOSDAQ_all")
res <- lapply(US, function(U) run_universe(pan, U, prim_months, paste0(U,"_PRIMARY")))
names(res) <- US

# ---- SECONDARY: full-period K200 + KQ150 (large-cap-end longevity check) ----
full_months <- sort(unique(pan[ym>=201001 & ym<=202506]$ym))
res_full <- list(
  K200_full  = run_universe(pan, "K200",  full_months, "K200_FULL_2010_2025"),
  KQ150_full = run_universe(pan, "KQ150", full_months, "KQ150_FULL_2010_2025"))

saveRDS(list(primary=res, secondary=res_full, prim_months=prim_months), file.path(OUT,"measure_r20.rds"))

# ---- print summary ----
fmt <- function(v) sprintf("%.4f", v)
pr_row <- function(r){
  if(is.null(r)) return(invisible())
  cb<-r$capw$base; ce<-r$capw$exfl; cr<-r$capw$rand
  cat(sprintf("\n== %s (n=%d months, mean k=%.1f, mean members=%.0f, mean scored=%.0f) [cap-w] ==\n",
      r$label, r$n_months, r$k_mean, r$nmem_mean, r$nsc_mean))
  cat(sprintf("  %-9s  ann_ret  ann_vol   MDD      dd     worst5   cvar20\n",""))
  cat(sprintf("  base     %s %s %s %s %s %s\n", fmt(cb["ann_ret"]),fmt(cb["ann_vol"]),fmt(cb["mdd"]),fmt(cb["dd"]),fmt(cb["worst5"]),fmt(cb["cvar20"])))
  cat(sprintf("  ex-flag  %s %s %s %s %s %s\n", fmt(ce["ann_ret"]),fmt(ce["ann_vol"]),fmt(ce["mdd"]),fmt(ce["dd"]),fmt(ce["worst5"]),fmt(ce["cvar20"])))
  cat(sprintf("  random   %s %s %s %s %s %s\n", fmt(cr["ann_ret"]),fmt(cr["ann_vol"]),fmt(cr["mdd"]),fmt(cr["dd"]),fmt(cr["worst5"]),fmt(cr["cvar20"])))
  cat(sprintf("  drag(exfl-base) ann_ret=%+.4f | MDD(exfl-base)=%+.4f MDD(exfl-rand)=%+.4f\n",
      ce["ann_ret"]-cb["ann_ret"], ce["mdd"]-cb["mdd"], ce["mdd"]-cr["mdd"]))
  if(!is.null(r$ci)){
    cat(sprintf("  CI[exfl-rand] MDD  [%.4f, %.4f] (med %.4f)\n", r$ci$er[1,"mdd"], r$ci$er[3,"mdd"], r$ci$er[2,"mdd"]))
    cat(sprintf("  CI[exfl-rand] cvar20 [%.4f, %.4f] | dd [%.4f, %.4f] | worst5 [%.4f, %.4f]\n",
        r$ci$er[1,"cvar20"], r$ci$er[3,"cvar20"], r$ci$er[1,"dd"], r$ci$er[3,"dd"], r$ci$er[1,"worst5"], r$ci$er[3,"worst5"]))
  }
}
cat("\n########## PRIMARY 2010-2015 ##########\n")
for(U in US) pr_row(res[[U]])
cat("\n########## SECONDARY full-period ##########\n")
for(nm in names(res_full)) pr_row(res_full[[nm]])

# ---- GRADIENT: exfl-vs-random tail improvement across audit-quality order ----
cat("\n########## AUDIT-QUALITY GRADIENT (cap-w, exfl vs random, PRIMARY) ##########\n")
cat("effect = random_metric - exflag_metric  (POSITIVE = exflag lower risk than random)\n")
cat(sprintf("%-11s  MDD_impr   cvar20_impr  dd_impr   worst5_impr  ann_drag\n",""))
for(U in US){ r<-res[[U]]; if(is.null(r))next
  ce<-r$capw$exfl; cr<-r$capw$rand; cb<-r$capw$base
  cat(sprintf("%-11s  %+8.4f  %+8.4f  %+8.4f  %+8.4f  %+8.4f\n",
      U, cr["mdd"]-ce["mdd"], cr["cvar20"]-ce["cvar20"], cr["dd"]-ce["dd"], cr["worst5"]-ce["worst5"], ce["ann_ret"]-cb["ann_ret"]))
}
cat("\n[02] DONE\n")
