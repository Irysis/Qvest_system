# =============================================================================
# WT-D20260606_001 Risk Research — residual-mom sleeve co-risk vs R05
# Role: risk-research. Σ = BΩB' + D + co-risk(R05) + tail + stress + crowding.
# NO alpha edit / NO weight proposal. measurement-graduation §1 real-computation.
# =============================================================================
suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts)
})
options(stringsAsFactors = FALSE)
ROOT <- "G:/Quant_Module_Moltbot"
setwd(ROOT)
WT <- "WT-D20260606_001"
OUT <- file.path(ROOT, "stage_artifacts", "WT_D20260606_001")  # canonical (NOT WT_WT-)
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||all(is.na(a))) b else a

# ---- infra ----
source("02_Infrastructure/portfolio/hrp_core.R")
source("02_Infrastructure/factor_db/crowding_score_per_factor.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

# --- inline EVT-GPD (POT, MLE) — fExtremes/evir absent in this env ---
# Peaks-over-threshold Generalized Pareto fit on losses (-returns). Standard estimator.
compute_evt_var <- function(r, p = 0.99, threshold_q = 0.95, min_tail_n = 30L) {
  r <- r[is.finite(r)]; losses <- -r
  u <- as.numeric(quantile(losses, threshold_q))
  exc <- losses[losses > u] - u
  if (length(exc) < min_tail_n) {
    threshold_q <- 0.90; u <- as.numeric(quantile(losses, threshold_q)); exc <- losses[losses>u]-u
  }
  if (length(exc) < 15L) {  # fallback normal
    s <- sd(r); var_n <- as.numeric(quantile(losses, p))
    return(list(var_evt=var_n, es_evt=mean(losses[losses>var_n]), xi=NA, beta=NA,
                n_exceed=length(exc), method="normal_fallback"))
  }
  # GPD negative log-likelihood
  nll <- function(par) {
    xi <- par[1]; b <- par[2]
    if (b <= 0) return(1e10)
    z <- 1 + xi*exc/b
    if (any(z <= 0)) return(1e10)
    sum(log(b) + (1/xi + 1)*log(z))
  }
  fit <- tryCatch(optim(c(0.1, mean(exc)), nll, method="Nelder-Mead"),
                  error=function(e) NULL)
  if (is.null(fit) || fit$convergence != 0) {
    s <- sd(r); var_n <- as.numeric(quantile(losses,p))
    return(list(var_evt=var_n, es_evt=mean(losses[losses>var_n]), xi=NA, beta=NA,
                n_exceed=length(exc), method="normal_fallback"))
  }
  xi <- fit$par[1]; b <- fit$par[2]
  nu <- length(losses); nexc <- length(exc)
  # GPD VaR (POT formula): u + (b/xi)*((n/Nexc*(1-p))^(-xi) - 1)
  var_gpd <- u + (b/xi)*(( (nu/nexc)*(1-p) )^(-xi) - 1)
  es_gpd  <- (var_gpd + b - xi*u) / (1 - xi)
  list(var_evt=var_gpd, es_evt=es_gpd, xi=xi, beta=b, n_exceed=nexc, threshold=u, method="gpd_mle")
}

# ---- inputs ----
ap <- fromJSON("qepm/mailbox/worktask/WT-D20260606_001/alpha_package.json", simplifyVector = FALSE)
scores <- as.data.table(read_parquet("stage_artifacts/WT_WT-D20260606_001/alpha_scores.parquet"))
scores[, Date := as.Date(Date)]
r05 <- as.data.table(read_parquet("qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"))
r05 <- unique(r05[!is.na(ret_net), .(Date = as.Date(Date), r05_net = ret_net)])
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet"))
RAW[, Date := as.Date(Date)]
RAW[, ym := format(Date, "%Y-%m")]
# Benchmark: dedupe daily BM_Ret to ONE value/date, compound to monthly, then FORWARD-shift
# (sleeve return for score-month ym = realized over ym+1, so benchmark must be forward month too)
bm_daily <- unique(RAW[!is.na(BM_Ret), .(Date, ym, BM_Ret)])
bm_m <- bm_daily[, .(bm_ret = prod(1 + BM_Ret) - 1), by = ym]
setorder(bm_m, ym)
bm_m[, ymn := as.integer(substr(ym,1,4))*12 + as.integer(substr(ym,6,7))]
bm_m[, bm_fwd := shift(bm_ret, 1L, type = "lead")]   # forward month compounded BM

cat("[load] scores", nrow(scores), "| r05", nrow(r05), "months | RAW", nrow(RAW), "\n")

# =============================================================================
# STEP A: residual-mom SLEEVE monthly net series (canonical top-20 EW, contract path)
# =============================================================================
# Build forward 1M returns per ticker (PIT: score at month-end t -> realized t..t+1)
RAW[, ym := format(Date, "%Y-%m")]
# month-end close per ticker
me <- RAW[!is.na(Close), .SD[.N], by = .(Ticker, ym), .SDcols = c("Date","Close")]
setorder(me, Ticker, Date)
me[, fwd_ret := shift(Close, 1L, type = "lead") / Close - 1, by = Ticker]   # FORWARD 1M
# DATA SANITY (replicate alpha_validation.json): drop <-99% / >900% corp-action/penny artifacts
me <- me[is.na(fwd_ret) | (fwd_ret > -0.99 & fwd_ret < 9.0)]
# align: score date = month-end -> use month-end fwd_ret
scores[, ym := format(Date, "%Y-%m")]
me[, ym := format(Date, "%Y-%m")]
# per-month 1/99 winsorize (Charter v1.3 Variant A — matches alpha)
me[!is.na(fwd_ret), fwd_ret := {
  lo <- quantile(fwd_ret, 0.01, na.rm=TRUE); hi <- quantile(fwd_ret, 0.99, na.rm=TRUE)
  pmin(pmax(fwd_ret, lo), hi)
}, by = ym]
ret1m <- me[, .(Ticker, ym, Ret_1m = fwd_ret)]

# liquidity (t-1 20d ADV proxy = Close*Vol mean over prior 20 trading days, at score month-end)
RAW[, dvol := Close * Vol]
setorder(RAW, Ticker, Date)
RAW[, adv20 := frollmean(shift(dvol,1L), 20L), by = Ticker]   # t-1 PIT
adv_me <- RAW[!is.na(Close), .SD[.N], by = .(Ticker, ym), .SDcols = c("Date","adv20")]
adv_me <- adv_me[, .(Ticker, ym, adv = adv20)]

# canonical screen scores_dt needs Date,Ticker,score ; returns Date,Ticker,Ret_1m ; bench Date,BM_Ret
sc <- scores[, .(Date, Ticker, score = alpha_score, ym)]
sc <- merge(sc, adv_me, by = c("Ticker","ym"), all.x = TRUE)
ret1m_d <- merge(ret1m, unique(scores[, .(ym, Date)]), by = "ym")  # map ym -> score Date
ret1m_d <- ret1m_d[, .(Date, Ticker, Ret_1m)]
liq_d <- sc[, .(Date, Ticker, adv)]

# bench_dt: score-Date -> FORWARD-month compounded BM (aligns with forward Ret_1m)
score_ym <- unique(scores[, .(ym, Date)])
bench_fwd <- merge(score_ym, bm_m[, .(ym, BM_Ret = bm_fwd)], by = "ym")[!is.na(BM_Ret), .(Date, BM_Ret)]

csb <- canonical_screen_bt(
  scores_dt = sc[, .(Date, Ticker, score)],
  returns_dt = ret1m_d,
  bench_dt = bench_fwd,
  top_n = 20L, cost_bps_oneway = 15,
  liq_dt = liq_d, liq_min = 2e8,
  run_id = "residmom_risk", strategy_id = "residmom_sleeve"
)
cat("[canonical_screen] n_months", csb$n_months, "| port_alpha_t", round(csb$portfolio_alpha_t_nw_lag3,3),
    "| IR", round(csb$information_ratio,3), "| net_sr", round(csb$net_sr,3), "\n")

# --- reconstruct sleeve net monthly series via SAME top-20 EW weights + Return.portfolio (contract constructor) ---
S <- sc[!is.na(score)]
S <- merge(S, liq_d, by = c("Date","Ticker"), all.x = TRUE, suffixes=c("",".l"))
S <- S[is.na(adv) | adv >= 2e8]
setorder(S, Date, -score)
W <- S[, { n <- min(20L,.N); .(Ticker = Ticker[seq_len(n)], w = rep(1/n,n)) }, by = Date]
WR <- merge(W, ret1m_d, by = c("Date","Ticker"), all.x = TRUE)
WR[is.na(Ret_1m), Ret_1m := 0]
# turnover cost (same as canonical) for net series
dts <- sort(unique(W$Date)); traded <- numeric(length(dts)); names(traded) <- as.character(dts)
prev <- data.table(Ticker=character(0), w=numeric(0))
for (i in seq_along(dts)) {
  cur <- W[Date==dts[i], .(Ticker,w)]
  m <- merge(cur, prev, by="Ticker", all=TRUE, suffixes=c("_c","_p"))
  m[is.na(w_c),w_c:=0]; m[is.na(w_p),w_p:=0]
  traded[i] <- sum(abs(m$w_c - m$w_p)); prev <- cur
}
port <- WR[, .(gross = sum(w*Ret_1m), n_valid = sum(!is.na(Ret_1m) & Ret_1m!=0)), by = Date]
port[, cost := traded[as.character(Date)] * 15/1e4]
port[, sleeve_net := gross - cost]
# drop terminal score-month with no realized forward return (bench_fwd NA)
valid_dates <- bench_fwd$Date
sleeve <- port[Date %in% valid_dates, .(Date, sleeve_net)]
sleeve <- sleeve[is.finite(sleeve_net)]
cat("[sleeve] months", nrow(sleeve), "| mean", round(mean(sleeve$sleeve_net),4),
    "| sd", round(sd(sleeve$sleeve_net),4), "\n")

# =============================================================================
# STEP B: R05 CO-RISK (CORE deliverable — optimizer ΔIR input; risk only, no ΔIR/weight)
# =============================================================================
# align month-keys (both month-end-ish; join on year-month)
sleeve[, ym := format(Date,"%Y-%m")]
r05[, ym := format(Date,"%Y-%m")]
J <- merge(sleeve[, .(ym, sleeve_net)], r05[, .(ym, r05_net)], by = "ym")
J <- J[is.finite(sleeve_net) & is.finite(r05_net)]
cat("[co-risk] overlap months", nrow(J), "\n")

s <- J$sleeve_net; r <- J$r05_net
cov_sr <- cov(s, r); var_r <- var(r); var_s <- var(s)
full_cor <- cor(s, r)
beta_vs_r05 <- cov_sr / var_r                      # sleeve sensitivity to R05
# downside beta: condition on R05 < 0 (and < median)
dn <- r < 0
beta_down <- if (sum(dn) >= 8) cov(s[dn], r[dn]) / var(r[dn]) else NA_real_
up <- r > 0
beta_up <- if (sum(up) >= 8) cov(s[up], r[up]) / var(r[up]) else NA_real_
# covariance contribution (annualized covariance, monthly*12)
cov_contrib_ann <- cov_sr * 12
# correlation of the two sleeves' annualized vols
ann_vol_sleeve <- sd(s) * sqrt(12); ann_vol_r05 <- sd(r) * sqrt(12)

# tail co-movement: joint left-tail (both in worst quintile)
q_s <- quantile(s, 0.20); q_r <- quantile(r, 0.20)
joint_left <- mean(s <= q_s & r <= q_r) / 0.20   # lambda_L empirical lower TDC proxy (>1 = clustering)
# crisis-window co-movement
cr_windows <- list(GFC=c("2007-10","2009-03"), Euro=c("2011-07","2011-12"),
                   COVID=c("2020-01","2020-06"), Rate=c("2022-01","2022-12"))
crisis_cor <- list()
for (nm in names(cr_windows)) {
  w <- cr_windows[[nm]]
  sub <- J[ym >= w[1] & ym <= w[2]]
  crisis_cor[[nm]] <- if (nrow(sub) >= 3) list(n=nrow(sub),
      cor = cor(sub$sleeve_net, sub$r05_net),
      sleeve_mean = mean(sub$sleeve_net), r05_mean = mean(sub$r05_net)) else list(n=nrow(sub), cor=NA)
}
# rolling 36m correlation
setorder(J, ym)
J[, idx := .I]
roll_cor <- sapply(36:nrow(J), function(i) cor(J$sleeve_net[(i-35):i], J$r05_net[(i-35):i]))
cat("[co-risk] full_cor", round(full_cor,3), "| beta_vs_R05", round(beta_vs_r05,3),
    "| beta_down", round(beta_down %||% NA,3), "| cov_contrib_ann", signif(cov_contrib_ann,3),
    "| joint_left_TDC", round(joint_left,2), "\n")

# 2-sleeve diversification ratio at illustrative 50/50 (DIAGNOSTIC ONLY — not weight proposal)
w50 <- 0.5
var_eq <- w50^2*var_s + (1-w50)^2*var_r + 2*w50*(1-w50)*cov_sr
vol_eq <- sqrt(var_eq*12)
wavg_vol <- w50*ann_vol_sleeve + (1-w50)*ann_vol_r05
div_ratio_5050 <- wavg_vol / vol_eq   # >1 = diversification benefit

# =============================================================================
# STEP C: Σ = BΩB' + D over current top-50 alpha_vector universe (daily 252d)
# =============================================================================
uni <- names(ap$alpha_vector)
asof <- as.Date(ap$as_of_date)
dret <- RAW[Ticker %in% uni & Date <= asof, .(Date, Ticker, Ret, Sector, Size)]
last_dates <- tail(sort(unique(dret$Date)), 252L)
dret <- dret[Date %in% last_dates]
wideR <- dcast(dret, Date ~ Ticker, value.var = "Ret")
matR <- as.matrix(wideR[, -1]);
keep <- colSums(!is.na(matR)) >= 200L
matR <- matR[, keep, drop=FALSE]
uni_keep <- colnames(matR)
matR[is.na(matR)] <- 0
n_uni <- ncol(matR)
cat("[Sigma] universe kept", n_uni, "of", length(uni), "| days", nrow(matR), "\n")

# market factor = cross-sectional EW return per day; size & sector via daily betas
mkt <- rowMeans(matR)
# B: rolling-window betas of each stock to market (single market factor) + sector dummy exposures
beta_mkt <- apply(matR, 2, function(x) coef(lm(x ~ mkt))[2])
# sector exposures (one-hot from latest snapshot)
sec_snap <- unique(dret[Ticker %in% uni_keep, .SD[.N], by=Ticker, .SDcols="Sector"])
sec_snap <- sec_snap[match(uni_keep, Ticker)]
sec_snap[is.na(Sector), Sector := "UNK"]
sectors <- sort(unique(sec_snap$Sector))
Bsec <- model.matrix(~ Sector - 1, data = sec_snap)  # n x n_sec
colnames(Bsec) <- gsub("Sector","SEC_", colnames(Bsec))
# size factor exposure = standardized log size
sz_snap <- unique(dret[Ticker %in% uni_keep, .SD[.N], by=Ticker, .SDcols="Size"])
sz_snap <- sz_snap[match(uni_keep, Ticker)]
size_exp <- scale(log(pmax(sz_snap$Size, 1)))[,1]; size_exp[is.na(size_exp)] <- 0

# Factor return time series: market = mkt; size = daily return spread (regress cross-section each day onto size_exp);
# sector returns = EW sector index daily returns
fac_size <- apply(matR, 1, function(day) {
  fit <- lm(day ~ size_exp); coef(fit)[2]
})
sec_ret_list <- lapply(sectors, function(sc2) {
  cols <- which(sec_snap$Sector == sc2)
  if (length(cols)==0) rep(0,nrow(matR)) else rowMeans(matR[,cols,drop=FALSE]) - mkt
})
names(sec_ret_list) <- paste0("SEC_", sectors)
facMat <- cbind(MKT = mkt, SIZE = fac_size, do.call(cbind, sec_ret_list))
# drop zero-variance factors
fvar <- apply(facMat, 2, var); facMat <- facMat[, fvar > 1e-12, drop=FALSE]

# B matrix: exposures n_uni x n_factor. MKT=beta_mkt, SIZE=size_exp, SEC_*=one-hot
Bmat <- matrix(0, nrow=n_uni, ncol=ncol(facMat), dimnames=list(uni_keep, colnames(facMat)))
if ("MKT" %in% colnames(facMat)) Bmat[,"MKT"] <- beta_mkt
if ("SIZE" %in% colnames(facMat)) Bmat[,"SIZE"] <- size_exp
for (sc2 in colnames(Bsec)) if (sc2 %in% colnames(facMat)) Bmat[, sc2] <- Bsec[, sc2]

# Omega: factor covariance via Ledoit-Wolf (hrp_core .get_cor_cov)
Omega <- .get_cor_cov(facMat, "ledoit_wolf")$cov
# D: specific (idio) variance = residual var of stock on its factor exposures' factor returns
fitted_sys <- facMat %*% t(Bmat)           # days x n_uni systematic returns
resid <- matR - fitted_sys
Dvar <- apply(resid, 2, var)
# floor D at small positive
Dvar <- pmax(Dvar, 1e-8)
Dmat <- diag(Dvar)

Sigma_struct <- Bmat %*% Omega %*% t(Bmat) + Dmat   # structural Σ (daily)
# annualize (×252)
Sigma_ann <- Sigma_struct * 252
# also direct LW sample Σ for comparison
Sigma_lw <- .get_cor_cov(matR, "ledoit_wolf")$cov * 252
Sigma_sample <- cov(matR) * 252

cond_struct <- kappa(Sigma_struct, exact = TRUE)
cond_lw <- kappa(Sigma_lw, exact = TRUE)
cond_sample <- kappa(Sigma_sample, exact = TRUE)
ev <- eigen(Sigma_struct, symmetric = TRUE, only.values = TRUE)$values
psd_struct <- min(ev) >= -1e-10
ev_lw <- eigen(Sigma_lw, symmetric=TRUE, only.values=TRUE)$values
# factor vs specific variance share (portfolio EW of universe as reference)
w_ref <- rep(1/n_uni, n_uni)
sys_var <- as.numeric(t(w_ref) %*% (Bmat %*% Omega %*% t(Bmat)) %*% w_ref)
spec_var <- as.numeric(t(w_ref) %*% Dmat %*% w_ref)
factor_share <- sys_var / (sys_var + spec_var)
# top common risk decomposition: variance contribution per factor (EW ref portfolio)
fac_contrib <- sapply(colnames(facMat), function(f) {
  bvec <- Bmat[,f]
  as.numeric((t(w_ref) %*% outer(bvec,bvec) %*% w_ref) * Omega[f,f])
})
fac_contrib_pct <- fac_contrib / (sys_var + spec_var)
fac_contrib_pct <- sort(fac_contrib_pct, decreasing = TRUE)
cat("[Sigma] cond struct", round(cond_struct,1), "| LW", round(cond_lw,1),
    "| sample", round(cond_sample,1), "| PSD", psd_struct, "| factor_share", round(factor_share,3), "\n")
cat("[Sigma] top common risk:", paste(sprintf("%s %.1f%%", names(fac_contrib_pct)[1:min(4,length(fac_contrib_pct))],
    100*fac_contrib_pct[1:min(4,length(fac_contrib_pct))]), collapse=" | "), "\n")

# concentration metrics
# sector HHI of the top-20 current names
top20 <- names(sort(unlist(ap$alpha_vector), decreasing=TRUE))[1:20]
sec20 <- unique(RAW[Ticker %in% top20 & Date <= asof, .SD[.N], by=Ticker, .SDcols="Sector"])
sec_w <- sec20[, .N, by=Sector][, share := N/sum(N)]
sector_hhi <- sum(sec_w$share^2)
n_eff <- 1/sum(w_ref^2)  # trivially 50 for EW; report top20 HHI instead

# =============================================================================
# STEP D: TAIL (EVT-GPD on sleeve daily-equivalent; use monthly sleeve + R05)
# =============================================================================
# sleeve daily series: build EW daily return of current top-20 (252d) for EVT (enough obs)
dmat20 <- matR[, colnames(matR) %in% top20, drop=FALSE]
sleeve_daily <- rowMeans(dmat20)
evt <- tryCatch(compute_evt_var(sleeve_daily, p = 0.99, threshold_q = 0.95), error=function(e) list(error=conditionMessage(e)))
evt95 <- tryCatch(compute_evt_var(sleeve_daily, p = 0.95, threshold_q = 0.90), error=function(e) list(error=conditionMessage(e)))
# Hill alpha
losses <- sort(-sleeve_daily[sleeve_daily<0], decreasing=TRUE)
k <- max(10, floor(0.1*length(losses)))
hill_alpha <- if (length(losses)>k) 1/mean(log(losses[1:k]/losses[k])) else NA_real_
# monthly CVaR/VaR of sleeve (historical)
var95_m <- quantile(sleeve$sleeve_net, 0.05)
cvar95_m <- mean(sleeve$sleeve_net[sleeve$sleeve_net <= var95_m])
var99_m <- quantile(sleeve$sleeve_net, 0.01)
cvar99_m <- mean(sleeve$sleeve_net[sleeve$sleeve_net <= var99_m])
cat("[tail] EVT VaR99(d)", round(evt$var_evt %||% NA,4), "| Hill_alpha", round(hill_alpha,2),
    "| CVaR95(m)", round(cvar95_m,4), "\n")

# =============================================================================
# STEP E: STRESS (8 historical windows on sleeve monthly + R05) + 2-sleeve illustrative
# =============================================================================
stress_def <- list(
  list(name="GFC_2008", s="2007-10", e="2009-03"),
  list(name="Euro_2011", s="2011-07", e="2011-12"),
  list(name="China_2015", s="2015-06", e="2016-02"),
  list(name="USChina_2018", s="2018-03", e="2018-12"),
  list(name="COVID_2020", s="2020-01", e="2020-06"),
  list(name="RateHike_2022", s="2022-01", e="2022-12"),
  list(name="Iran_2026", s="2026-02", e="2026-04")
)
stress <- list()
sleeve_cov_pct <- list()
for (sp in stress_def) {
  sub_s <- sleeve[ym >= sp$s & ym <= sp$e]
  sub_j <- J[ym >= sp$s & ym <= sp$e]
  cum_sleeve <- if (nrow(sub_s)>0) prod(1+sub_s$sleeve_net)-1 else NA_real_
  cum_r05 <- if (nrow(sub_j)>0) prod(1+sub_j$r05_net)-1 else NA_real_
  # coverage: fraction of universe with non-NA price during window (book coverage proxy)
  cov_win <- nrow(sub_s) / (as.integer(substr(sp$e,1,4))*12+as.integer(substr(sp$e,6,7)) -
                            (as.integer(substr(sp$s,1,4))*12+as.integer(substr(sp$s,6,7))) + 1)
  stress[[sp$name]] <- list(n_months=nrow(sub_s), sleeve_cum=cum_sleeve, r05_cum=cum_r05,
                            coverage=cov_win, reliable = cov_win >= 0.85)
}
# scenario stress (parametric, monthly): market -5% one-month shock via sleeve beta to BM
# sleeve return for score-month ym realized over ym+1 -> pair with forward-month BM
sleeve_bm <- merge(sleeve[,.(ym,sleeve_net)], bm_m[, .(ym, BM_Ret = bm_fwd)], by="ym")
sleeve_bm <- sleeve_bm[is.finite(sleeve_net) & is.finite(BM_Ret)]
beta_bm <- cov(sleeve_bm$sleeve_net, sleeve_bm$BM_Ret)/var(sleeve_bm$BM_Ret)
alpha_bm <- mean(sleeve_bm$sleeve_net) - beta_bm*mean(sleeve_bm$BM_Ret)
mkt_down5 <- alpha_bm + beta_bm*(-0.05)
cat("[stress] sleeve beta_BM", round(beta_bm,3), "| market_down_5 sleeve", round(mkt_down5,4), "\n")

# =============================================================================
# STEP F: CROWDING (crowding_score_per_factor; CR07 momentum crowding incl.)
# =============================================================================
# build factor_exposures long: residual-mom composite exposure = latest alpha_score
fe_resid <- scores[Date == max(Date), .(Ticker, factor_name = "ResidMom_M08_M14", exposure = alpha_score)]
# CR07 proxy: raw 12-1m momentum exposure (crowding-conditional defensive proxy = momentum crowding)
RAW[, ym := format(Date,"%Y-%m")]
mom_panel <- me[, .(Ticker, ym, Close)]
setorder(mom_panel, Ticker, ym)
mom_panel[, mom12_1 := shift(Close,1L)/shift(Close,12L) - 1, by=Ticker]  # 12-1m (lagged 1m)
mom_last <- mom_panel[ym == format(max(scores$Date),"%Y-%m"), .(Ticker, factor_name="CR07_Momentum_Crowding", exposure=mom12_1)]
fe_all <- rbind(fe_resid, mom_last[!is.na(exposure)])
crowd <- tryCatch(
  crowding_score_per_factor(fe_all, sig_date = max(scores$Date), RAWDATA = RAW, top_n = 20L),
  error = function(e) data.table(factor_name=unique(fe_all$factor_name), crowding_score=NA, err=conditionMessage(e)))
crowd <- as.data.table(crowd)
print(crowd)

# =============================================================================
# SAVE artifacts
# =============================================================================
write_parquet(as.data.table(as.data.frame(Sigma_ann)), file.path(OUT,"covariance.parquet"))
fwrite(as.data.table(Sigma_ann, keep.rownames="Ticker"), file.path(OUT,"covariance_named.csv"))
# regime correlation parquet
regdt <- rbindlist(lapply(names(crisis_cor), function(nm) data.table(
  regime=nm, n=crisis_cor[[nm]]$n, cor_sleeve_r05=crisis_cor[[nm]]$cor %||% NA_real_)), fill=TRUE)
regdt <- rbind(regdt, data.table(regime="FULL", n=nrow(J), cor_sleeve_r05=full_cor),
               data.table(regime="ROLL36M_mean", n=length(roll_cor), cor_sleeve_r05=mean(roll_cor)), fill=TRUE)
write_parquet(regdt, file.path(OUT,"regime_correlation.parquet"))

tail_json <- list(
  evt_var99_daily = evt$var_evt %||% NA, evt_es99_daily = evt$es_evt %||% NA,
  evt_var95_daily = evt95$var_evt %||% NA, evt_es95_daily = evt95$es_evt %||% NA,
  hill_alpha = hill_alpha,
  hist_var95_monthly = as.numeric(var95_m), hist_cvar95_monthly = as.numeric(cvar95_m),
  hist_var99_monthly = as.numeric(var99_m), hist_cvar99_monthly = as.numeric(cvar99_m),
  n_daily_obs = length(sleeve_daily), n_monthly_obs = nrow(sleeve))
write_json(tail_json, file.path(OUT,"tail_risk.json"), pretty=TRUE, auto_unbox=TRUE)

# co-risk artifact (optimizer ΔIR input)
corisk <- list(
  overlap_months = nrow(J),
  full_correlation = full_cor,
  beta_vs_R05 = beta_vs_r05, beta_down_R05 = beta_down %||% NA, beta_up_R05 = beta_up %||% NA,
  cov_monthly = cov_sr, cov_contribution_annualized = cov_contrib_ann,
  ann_vol_sleeve = ann_vol_sleeve, ann_vol_R05 = ann_vol_r05,
  joint_left_tail_TDC_proxy = joint_left,
  diversification_ratio_5050_diagnostic = div_ratio_5050,
  rolling36m_cor_mean = mean(roll_cor), rolling36m_cor_min = min(roll_cor), rolling36m_cor_max = max(roll_cor),
  crisis_cor = crisis_cor,
  note = "covariance contribution + downside beta for optimizer book-marginal ΔIR. risk does NOT compute ΔIR/weights.")
write_json(corisk, file.path(OUT,"corisk_R05.json"), pretty=TRUE, auto_unbox=TRUE)

# summary object for draft assembly
summ <- list(
  canonical_screen = list(n_months=csb$n_months, port_alpha_t=csb$portfolio_alpha_t_nw_lag3,
                          IR=csb$information_ratio, net_sr=csb$net_sr, turnover=csb$turnover_annual),
  sigma = list(n_universe=n_uni, cond_struct=cond_struct, cond_lw=cond_lw, cond_sample=cond_sample,
               psd=psd_struct, factor_share=factor_share, min_eig=min(ev),
               top_common_risk=as.list(round(100*fac_contrib_pct[1:min(5,length(fac_contrib_pct))],2)),
               sector_hhi_top20=sector_hhi),
  corisk = corisk,
  tail = tail_json,
  stress = stress, market_down_5_sleeve = mkt_down5, sleeve_beta_BM = beta_bm,
  crowding = crowd)
write_json(summ, file.path(OUT,"risk_summary_raw.json"), pretty=TRUE, auto_unbox=TRUE)
cat("\n[DONE] artifacts written to", OUT, "\n")
