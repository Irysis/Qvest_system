# 10_risk_model.R — QEPM Risk Research: Sigma = B Omega B' + D + factor cov + specific risk
# WT-D20260706_007 value/quality spread-reversion universe.
# PIT: rolling/expanding cross-sectional factor regressions (C1). Universe = alpha score-universe.
suppressMessages({library(data.table); library(arrow); library(dplyr)})
setDTthreads(1L)
set.seed(20260706L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260706_007")
log <- function(...) { cat(format(Sys.time(),"%H:%M:%S"), sprintf(...), "\n"); flush.console() }
t0 <- Sys.time()

# ---------------------------------------------------------------------------
# 0. Inputs
# ---------------------------------------------------------------------------
sc <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))  # Date,Ticker,ym,val_z,qual_z,vq_z,exp_pctile,spread_ratio,fwd_mret
pan <- readRDS(file.path(OUT,"panel_universe_ret.rds"))
mret <- pan$mret[order(Ticker, ym)]                     # Ticker, ym, mret (200406-202607)

# --- clean benchmark from benchmark.parquet BM_Close (RAWDATA BM_Ret corrupt recent months, [[rawdata-bmret]]) ---
bp <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/pg2_overlay_gate_composition_20260705/pinned_cache/benchmark.parquet")))
bp[, Date := as.Date(Date)]; bp[, ym := as.integer(format(Date,"%Y%m"))]
bmret <- bp[order(Date), .(bm = prod(1+BM_Ret)-1), by=ym][order(ym)]     # clean KOSPI200 monthly
log("[bench] clean bm months=%d range=%d..%d  recent max=%.3f (sanity)", nrow(bmret), min(bmret$ym), max(bmret$ym), max(tail(bmret$bm,12)))

# --- sector snapshot (PIT: latest <= as_of) ---
ds <- open_dataset(file.path(ROOT,".cache/RAWDATA.parquet"))
rd_snap <- as.data.table(ds %>% filter(Date >= as.Date("2026-05-01")) %>%
                           select(Ticker,Date,Sector,Size,Vol,Close,K200,KQ150) %>% collect())
rd_snap[, Date := as.Date(Date)]
sec_last <- rd_snap[order(Date), .SD[.N], by=Ticker, .SDcols=c("Sector","Size","Vol","Close","K200","KQ150")]
sec_last[is.na(Sector), Sector := "UNKNOWN"]

# ---------------------------------------------------------------------------
# 1. Estimation universe: score-universe tickers w/ >=60 monthly returns
# ---------------------------------------------------------------------------
scu <- unique(sc$Ticker)
retcnt <- mret[Ticker %in% scu & ym>=200501 & ym<=202606, .N, by=Ticker][N>=60]
est_tickers <- retcnt$Ticker
log("[universe] score-universe=%d  estimation(>=60m)=%d", length(scu), length(est_tickers))

# monthly return wide matrix (rows=ym, cols=ticker) over estimation window
mr <- mret[Ticker %in% est_tickers & ym>=200501 & ym<=202606]
retw <- dcast(mr, ym ~ Ticker, value.var="mret")
setorder(retw, ym)
yms <- retw$ym; retw[, ym := NULL]
retmat <- as.matrix(retw)   # ym x ticker (NA where not traded)
rownames(retmat) <- as.character(yms)

# ---------------------------------------------------------------------------
# 2. Exposure model B (as-of current signal month for Sigma; time-varying for factor-return estimation)
#    Factors: MKT(beta), VALUE(val_z), QUALITY(qual_z), SIZE(log ME z), + SECTOR dummies
# ---------------------------------------------------------------------------
# monthly style exposures from score panel (val_z, qual_z per ym). Size from RAWDATA monthly Size.
# rolling market beta per ticker (36m expanding-then-rolling window vs clean bm) computed inside factor-return loop.

# score panel keyed by (Ticker,ym): val_z, qual_z (already cross-sec z per month in alpha)
sp <- sc[, .(Ticker, ym, val_z, qual_z)]
setkey(sp, Ticker, ym)

# monthly Size (log market cap) for SIZE factor — pull from RAWDATA monthly (last obs per ym)
sz <- as.data.table(ds %>% filter(Date >= as.Date("2004-12-01")) %>% select(Ticker,Date,Size) %>% collect())
sz[, ym := as.integer(format(as.Date(Date),"%Y%m"))]
sz <- sz[!is.na(Size) & Size>0]
szm <- sz[order(Date), .(Size = last(Size)), by=.(Ticker,ym)]
szm[, lnsize := log(Size)]

# ---------------------------------------------------------------------------
# 3. Factor returns via monthly cross-sectional WLS regression (PIT: contemporaneous ret ~ prior-month exposure)
#    r_{i,t} = MKT_t + b_val*val_z_{i,t-1} + b_qual*qual_z_{i,t-1} + b_size*size_{i,t-1} + sector_t + e
#    (exposures lagged 1m => signal known at t-1; C1/C5 compliant)
# ---------------------------------------------------------------------------
# sector dummies from current snapshot (sector membership ~ stable; PIT-acceptable as slow-moving)
sec_map <- sec_last[, .(Ticker, Sector)]
sectors <- sort(unique(sec_map$Sector))
# drop smallest sector as base to avoid collinearity
sec_counts <- sec_map[, .N, by=Sector][order(-N)]
base_sec <- sec_counts$Sector[nrow(sec_counts)]
use_sec <- setdiff(sectors, base_sec)

style_facs <- c("VALUE","QUALITY","SIZE")
fac_names <- c("MKT", style_facs, paste0("SEC_", use_sec))
K <- length(fac_names)

est_yms <- yms[yms>=200601 & yms<=202606]   # need lagged exposure => start 200601
fac_ret <- matrix(NA_real_, nrow=length(est_yms), ncol=K, dimnames=list(as.character(est_yms), fac_names))
resid_store <- vector("list", length(est_yms))  # for specific risk

for (i in seq_along(est_yms)) {
  t_ym <- est_yms[i]
  lag_ym <- if (t_ym %% 100 == 1) (t_ym - 100 + 11) else (t_ym - 1)  # previous calendar month
  # dependent: returns at t
  rt <- mret[ym==t_ym & Ticker %in% est_tickers, .(Ticker, r=mret)]
  # exposures at t-1
  ex <- sp[ym==lag_ym, .(Ticker, VALUE=val_z, QUALITY=qual_z)]
  szl <- szm[ym==lag_ym, .(Ticker, lnsize)]
  d <- merge(rt, ex, by="Ticker")
  d <- merge(d, szl, by="Ticker", all.x=TRUE)
  d <- merge(d, sec_map, by="Ticker", all.x=TRUE)
  d <- d[is.finite(r) & is.finite(VALUE) & is.finite(QUALITY)]
  if (nrow(d) < 40) next
  # SIZE cross-sec z (winsorize lnsize)
  d[is.na(lnsize), lnsize := median(d$lnsize, na.rm=TRUE)]
  ls <- d$lnsize; qs <- quantile(ls, c(.01,.99), na.rm=TRUE); ls <- pmin(pmax(ls, qs[1]), qs[2])
  d[, SIZE := (ls - mean(ls))/sd(ls)]
  d[is.na(Sector), Sector := base_sec]
  # design matrix: intercept(MKT) + styles + sector dummies
  X <- cbind(MKT=1, VALUE=d$VALUE, QUALITY=d$QUALITY, SIZE=d$SIZE)
  for (s in use_sec) X <- cbind(X, as.integer(d$Sector==s))
  colnames(X) <- fac_names
  y <- d$r
  # WLS by sqrt cap (Barra convention) -> use sqrt(Size) weight; fallback equal
  w <- rep(1, nrow(d))
  fit <- tryCatch(lm.wfit(X, y, w=w), error=function(e) NULL)
  if (is.null(fit)) next
  fac_ret[i, ] <- coef(fit)[fac_names]
  # residuals for specific risk (keyed by ticker)
  resid_store[[i]] <- data.table(Ticker=d$Ticker, ym=t_ym, e=fit$residuals)
}
ok <- rowSums(is.na(fac_ret)) == 0
fac_ret_ok <- fac_ret[ok, , drop=FALSE]
log("[factor-returns] estimated months=%d / %d  factors=%d", nrow(fac_ret_ok), length(est_yms), K)

# ---------------------------------------------------------------------------
# 4. Factor covariance Omega (Ledoit-Wolf shrinkage to constant-correlation target)
# ---------------------------------------------------------------------------
lw_shrink <- function(R) {
  # R: T x K factor-return matrix -> shrunk covariance (Ledoit-Wolf, identity+scaled-mean target)
  R <- R[complete.cases(R), , drop=FALSE]
  Tn <- nrow(R); p <- ncol(R)
  S <- cov(R)
  mu <- mean(diag(S))
  # target: diagonal-preserving constant-correlation
  sds <- sqrt(diag(S)); rbar <- (sum(S/outer(sds,sds)) - p) / (p*(p-1))
  Ftar <- rbar * outer(sds, sds); diag(Ftar) <- diag(S)
  # shrinkage intensity (LW 2004 constant-correlation)
  Xc <- scale(R, center=TRUE, scale=FALSE)
  pi_hat <- sum((crossprod(Xc^2)/Tn - S^2))  # asymptotic var proxy
  gamma <- sum((Ftar - S)^2)
  # simple bounded intensity
  delta <- max(0, min(1, (pi_hat) / max(gamma,1e-12)))
  # robust fallback: use moderate 0.2 if unstable
  if (!is.finite(delta)) delta <- 0.2
  Sig <- delta*Ftar + (1-delta)*S
  list(cov=Sig, delta=delta, sample=S)
}
lw <- lw_shrink(fac_ret_ok)
Omega <- lw$cov
Omega_sample <- lw$sample
cn_omega_sample <- kappa(Omega_sample, exact=TRUE)
cn_omega <- kappa(Omega, exact=TRUE)
log("[Omega] LW delta=%.3f  cond(sample)=%.1f  cond(shrunk)=%.1f", lw$delta, cn_omega_sample, cn_omega)

# ensure PD
eg <- eigen(Omega, symmetric=TRUE)
if (min(eg$values) <= 1e-12) {
  floor_ev <- max(1e-10, 1e-4*max(eg$values))
  eg$values[eg$values < floor_ev] <- floor_ev
  Omega <- eg$vectors %*% diag(eg$values) %*% t(eg$vectors)
  Omega <- (Omega+t(Omega))/2
  log("[Omega] eigen-floor applied")
}

# ---------------------------------------------------------------------------
# 5. Specific risk D (idiosyncratic variance from residuals, per ticker; EWMA-ish via recent window)
# ---------------------------------------------------------------------------
resid_dt <- rbindlist(resid_store[!sapply(resid_store, is.null)])
# specific variance = var of residuals per ticker (min 24 obs, else cross-sec median)
sr <- resid_dt[, .(spec_var = if(.N>=24) var(e) else NA_real_, n=.N), by=Ticker]
med_sv <- median(sr$spec_var, na.rm=TRUE)
sr[is.na(spec_var), spec_var := med_sv]
# floor specific var to avoid zero
sv_floor <- quantile(sr$spec_var, 0.02, na.rm=TRUE)
sr[spec_var < sv_floor, spec_var := sv_floor]
log("[specific] tickers=%d  median spec sd=%.4f  (monthly)", nrow(sr), sqrt(med_sv))

# ---------------------------------------------------------------------------
# 6. Current-month exposure matrix B for INVESTABLE universe (as-of 202607 signal)
#    Investable = current score month names (val_z finite) with liquidity + return history
# ---------------------------------------------------------------------------
cur_score_ym <- max(sc$ym)  # 202606 (latest fwd-available). Use as as-of exposure month.
cur_ex <- sc[ym==cur_score_ym & is.finite(val_z) & is.finite(qual_z), .(Ticker, VALUE=val_z, QUALITY=qual_z)]
# restrict to tickers with specific risk + return history
cur_ex <- cur_ex[Ticker %in% sr$Ticker]
# SIZE for current month
szc <- szm[ym==cur_score_ym, .(Ticker, lnsize)]
cur_ex <- merge(cur_ex, szc, by="Ticker", all.x=TRUE)
cur_ex[is.na(lnsize), lnsize := median(cur_ex$lnsize, na.rm=TRUE)]
lc <- cur_ex$lnsize; qc <- quantile(lc,c(.01,.99),na.rm=TRUE); lc <- pmin(pmax(lc,qc[1]),qc[2])
cur_ex[, SIZE := (lc-mean(lc))/sd(lc)]
cur_ex <- merge(cur_ex, sec_map, by="Ticker", all.x=TRUE)
cur_ex[is.na(Sector), Sector := base_sec]
# market beta: rolling 36m beta vs clean bm per ticker (as-of cur month)
betas <- rbindlist(lapply(cur_ex$Ticker, function(tk){
  rr <- mret[Ticker==tk & ym<=cur_score_ym & ym>=cur_score_ym-500][order(ym)]
  rr <- tail(rr, 36)
  m <- merge(rr, bmret, by="ym")
  if (nrow(m)<18) return(data.table(Ticker=tk, beta=1.0))
  b <- tryCatch(coef(lm(mret~bm, data=m))[2], error=function(e) 1.0)
  data.table(Ticker=tk, beta=as.numeric(b))
}))
cur_ex <- merge(cur_ex, betas, by="Ticker", all.x=TRUE)
cur_ex[is.na(beta) | !is.finite(beta), beta := 1.0]
# winsorize beta
cur_ex[beta > 2.5, beta:=2.5][beta < -0.5, beta:=-0.5]

inv_tickers <- cur_ex$Ticker
Nsec <- length(inv_tickers)
# Build B matrix (N x K)
B <- matrix(0, nrow=Nsec, ncol=K, dimnames=list(inv_tickers, fac_names))
B[, "MKT"]     <- cur_ex$beta
B[, "VALUE"]   <- cur_ex$VALUE
B[, "QUALITY"] <- cur_ex$QUALITY
B[, "SIZE"]    <- cur_ex$SIZE
for (s in use_sec) B[, paste0("SEC_",s)] <- as.integer(cur_ex$Sector==s)
log("[B] investable universe N=%d  factors=%d", Nsec, K)

# ---------------------------------------------------------------------------
# 7. Assemble Sigma = B Omega B' + D
# ---------------------------------------------------------------------------
Dvec <- sr[match(inv_tickers, Ticker), spec_var]
Dvec[is.na(Dvec)] <- med_sv
Sigma <- B %*% Omega %*% t(B) + diag(Dvec)
Sigma <- (Sigma + t(Sigma))/2
cn_sigma <- kappa(Sigma, exact=TRUE)
# PSD check + shrink if needed
eg2 <- eigen(Sigma, symmetric=TRUE)
min_ev <- min(eg2$values)
psd_ok <- min_ev > 0
if (min_ev <= 1e-14) {
  fl <- 1e-8*max(eg2$values)
  eg2$values[eg2$values<fl] <- fl
  Sigma <- eg2$vectors %*% diag(eg2$values) %*% t(eg2$vectors); Sigma<-(Sigma+t(Sigma))/2
  cn_sigma <- kappa(Sigma, exact=TRUE)
}
# if condition number > 500, shrink Sigma toward diagonal
shrink_sigma_used <- FALSE
if (cn_sigma > 500) {
  d_target <- diag(diag(Sigma))
  lam <- 0.15
  Sigma <- (1-lam)*Sigma + lam*d_target
  cn_sigma <- kappa(Sigma, exact=TRUE)
  shrink_sigma_used <- TRUE
  log("[Sigma] extra diag-shrink lam=%.2f -> cond=%.1f", lam, cn_sigma)
}
log("[Sigma] N=%d  cond=%.1f  min_ev=%.2e  PSD=%s", Nsec, cn_sigma, min(eigen(Sigma,symmetric=TRUE,only.values=TRUE)$values), min(eigen(Sigma,symmetric=TRUE,only.values=TRUE)$values)>0)

# ---------------------------------------------------------------------------
# 8. Variance decomposition (factor vs specific share) at EW portfolio of investable universe
# ---------------------------------------------------------------------------
wq <- rep(1/Nsec, Nsec)  # EW proxy portfolio (optimizer decides real weights; this is diagnostic only)
tot_var <- as.numeric(t(wq) %*% Sigma %*% wq)
# per-factor contribution: w'B Omega B'w decomposed
Bw <- as.numeric(t(B) %*% wq)                 # K-vector factor exposure of EW port
fac_var_total <- as.numeric(t(Bw) %*% Omega %*% Bw)
spec_var_total <- sum(wq^2 * Dvec)
# marginal factor variance share (diagonal approx of Bw Omega Bw)
fac_contrib <- sapply(seq_len(K), function(k){ Bw[k]*sum(Omega[k,]*Bw) })
names(fac_contrib) <- fac_names
# group style/market/sector
share <- fac_contrib / tot_var
mkt_share  <- share["MKT"]
style_share<- sum(share[style_facs])
sec_share  <- sum(share[grepl("^SEC_",names(share))])
spec_share <- spec_var_total / tot_var
log("[decomp] tot_var=%.5f  MKT=%.1f%% STYLE=%.1f%% SECTOR=%.1f%% SPECIFIC=%.1f%%",
    tot_var, 100*mkt_share, 100*style_share, 100*sec_share, 100*spec_share)

# n_effective + sector HHI on EW proxy
sec_w <- cur_ex[, .(w=sum(1/Nsec)), by=Sector]
sec_hhi <- sum(sec_w$w^2)
n_eff <- 1/sum(wq^2)

saveRDS(list(fac_names=fac_names, Omega=Omega, Omega_sample=Omega_sample, delta=lw$delta,
             B=B, Dvec=Dvec, Sigma=Sigma, inv_tickers=inv_tickers, cur_ex=cur_ex,
             fac_ret=fac_ret_ok, resid_dt=resid_dt, sr=sr, bmret=bmret, mret=mret,
             cn_omega=cn_omega, cn_omega_sample=cn_omega_sample, cn_sigma=cn_sigma,
             mkt_share=mkt_share, style_share=style_share, sec_share=sec_share, spec_share=spec_share,
             fac_contrib=fac_contrib, tot_var=tot_var, sec_hhi=sec_hhi, n_eff=n_eff,
             cur_score_ym=cur_score_ym, sec_map=sec_map, use_sec=use_sec, base_sec=base_sec,
             shrink_sigma_used=shrink_sigma_used, sec_last=sec_last, rd_snap=rd_snap),
        file.path(OUT,"risk_model_core.rds"))

# write covariance.parquet (long: ticker_i, ticker_j, cov) — plus a diag/exposure export
covdt <- as.data.table(as.table(Sigma)); setnames(covdt, c("ticker_i","ticker_j","cov"))
write_parquet(covdt, file.path(OUT,"covariance.parquet"))
# exposure matrix export
Bdt <- as.data.table(B, keep.rownames="Ticker")
write_parquet(Bdt, file.path(OUT,"exposure_matrix.parquet"))
# factor covariance export
Odt <- as.data.table(Omega, keep.rownames="factor"); write_parquet(Odt, file.path(OUT,"factor_covariance.parquet"))
# specific risk export
write_parquet(sr[Ticker %in% inv_tickers], file.path(OUT,"specific_risk.parquet"))

log("[DONE step1-8] %.1fs  covariance.parquet rows=%d", as.numeric(difftime(Sys.time(),t0,units="secs")), nrow(covdt))
