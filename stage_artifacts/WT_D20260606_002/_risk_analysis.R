#==============================================================================
# WT-D20260606_002 Risk Research — DPL cycle 2
# Role: Sigma + crowding + tail + residual orthogonality (Codex alpha critique ④)
# Scope: risk diagnostics ONLY. No alpha edit, no weights. metric_type labelled.
# PIT: lockbox 2023-12-22 applied to all estimation (regular-research stage).
#==============================================================================
suppressMessages({
  library(arrow); library(data.table)
})
setwd("G:/Quant_Module_Moltbot")
WT <- "WT_D20260606_002"
OUT <- file.path("stage_artifacts", WT)
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
set.seed(20260606L)

LOCKBOX <- as.Date("2023-12-22")

panel <- as.data.table(read_parquet("stage_artifacts/WT_DPL_C2/dpl_feature_panel.parquet"))
panel[, date := as.Date(date)]
panel <- panel[in_univ == TRUE]
# lockbox: estimation uses pre-lockbox months only (regular research PIT)
panel_lb <- panel[date <= LOCKBOX]

cn <- names(panel)
feat_cols <- grep("__(lvl|slp|vol)$", cn, value = TRUE)
NEW3 <- c("PIOTROSKI__lvl", "MOHANRAM__lvl", "NETISSUE__lvl")
RESID <- "RESIDMOM__lvl"
base90 <- setdiff(feat_cols, c(NEW3, RESID, "RESIDMOM__slp",
                               "PIOTROSKI__slp","MOHANRAM__slp","NETISSUE__slp"))

cat("== panel ==\n")
cat("rows in_univ:", nrow(panel), " pre-lockbox:", nrow(panel_lb), "\n")
cat("months (lb):", length(unique(panel_lb$ym)), " feat cols:", length(feat_cols),
    " base90:", length(base90), "\n")

#------------------------------------------------------------------------------
# Helper: identify proxy axes among base90 for neutralization
#------------------------------------------------------------------------------
# size axis (S01), value (V*), liquidity from adv (log), sector unavailable in panel
size_col <- grep("^S01_Size__lvl$", base90, value = TRUE)
val_cols <- grep("^V[0-9]+_.*__lvl$", base90, value = TRUE)
cat("size axis:", size_col, " | value axes:", length(val_cols), "\n")

#==============================================================================
# PART A — Residual orthogonality (Codex critique ④: max-corr insufficient)
#   For each NEW3 + RESIDMOM: residualize against [size, value, liquidity, base90]
#   per-month cross-sectional OLS, then measure residual variance share retained.
#   Also: era-stability of raw correlation, covariance contribution.
#==============================================================================
cat("\n== PART A: residual orthogonality ==\n")

months <- sort(unique(panel_lb$ym))
# neutralizer set: size + value + log-liquidity (the structural style axes Codex named)
panel_lb[, loglq := log(pmax(adv, 1))]
neutral_axes <- c(size_col, val_cols, "loglq")
neutral_axes <- intersect(neutral_axes, names(panel_lb))

resid_var_share <- list()   # how much of feature variance survives neutralization
resid_maxcorr_vs_base <- list()  # residual corr vs base90 after neutralization

targets <- c(NEW3, RESID)
for (f in targets) {
  surv <- numeric(0); rmax <- numeric(0)
  for (m in months) {
    sub <- panel_lb[ym == m]
    if (nrow(sub) < 30) next
    y <- sub[[f]]
    X <- as.matrix(sub[, ..neutral_axes])
    ok <- is.finite(y) & rowSums(!is.finite(X)) == 0
    if (sum(ok) < 30) next
    y <- y[ok]; X <- X[ok, , drop = FALSE]
    # drop zero-variance neutralizers this month
    keep <- apply(X, 2, function(z) stats::var(z) > 1e-12)
    X <- X[, keep, drop = FALSE]
    if (ncol(X) == 0) { surv <- c(surv, 1); next }
    fitr <- tryCatch(lm.fit(cbind(1, X), y)$residuals, error = function(e) NULL)
    if (is.null(fitr)) next
    surv <- c(surv, stats::var(fitr) / stats::var(y))   # residual var / total var
    # residual corr vs base90 features (residualize base too for fairness, cheap: raw)
    bsub <- as.matrix(sub[ok, ..base90])
    bok <- apply(bsub, 2, function(z) all(is.finite(z)) && stats::var(z) > 1e-12)
    bsub <- bsub[, bok, drop = FALSE]
    if (ncol(bsub) > 0) {
      cc <- suppressWarnings(abs(cor(fitr, bsub)))
      rmax <- c(rmax, max(cc, na.rm = TRUE))
    }
  }
  resid_var_share[[f]] <- mean(surv, na.rm = TRUE)
  resid_maxcorr_vs_base[[f]] <- mean(rmax, na.rm = TRUE)
}

# Era-stability of pairwise corr vs argmax base (the 0.85 RESIDMOM concern)
era_of <- function(ym) {
  y <- as.integer(substr(ym, 1, 4))
  fifelse(y <= 2011, "E1", fifelse(y <= 2018, "E2", "E3"))
}
panel_lb[, era := era_of(ym)]
argmax_base <- c(PIOTROSKI__lvl="Q03_ROA__lvl", MOHANRAM__lvl="Q01_GPA__lvl",
                 NETISSUE__lvl="M11_ST_Reversal__vol", RESIDMOM__lvl="M05_Trended_Mom__lvl")
era_corr <- list()
for (f in targets) {
  ab <- argmax_base[[f]]
  if (is.null(ab) || !(ab %in% names(panel_lb))) next
  ec <- panel_lb[, .(corr = suppressWarnings(cor(get(f), get(ab), use="complete.obs"))), by=era]
  era_corr[[f]] <- setNames(round(ec$corr,3), ec$era)
}

cat("residual var share (1=orthogonal to style axes, 0=fully explained):\n")
print(round(unlist(resid_var_share), 3))
cat("\nmean residual max|corr| vs base90 (after style-neutralization):\n")
print(round(unlist(resid_maxcorr_vs_base), 3))
cat("\nera-stability of corr vs argmax base:\n")
print(era_corr)

#==============================================================================
# PART B — Covariance contribution of new features in the panel
#   PCA on the standardized feature panel (pre-lockbox pooled). Measure each
#   new feature's loading on top PCs (shared-risk participation) + unique var.
#==============================================================================
cat("\n== PART B: covariance contribution (panel PCA) ==\n")
use_feats <- c(base90, NEW3, RESID)
Xall <- as.matrix(panel_lb[, ..use_feats])
Xall[!is.finite(Xall)] <- 0   # DPL z=0 missing convention (consistent w/ alpha)
# already cross-section z by construction; standardize defensively
Xstd <- scale(Xall)
Xstd[!is.finite(Xstd)] <- 0
Cf <- cor(Xstd)
eg <- eigen(Cf, symmetric = TRUE)
varexp <- eg$values / sum(eg$values)
cat("top-5 feature-PC var explained:", round(varexp[1:5], 3), "\n")
cat("PC1 var share (dominant common factor):", round(varexp[1], 3), "\n")
# communality of each new feature on top-K PCs
K <- 5
load <- eg$vectors[, 1:K] * matrix(sqrt(eg$values[1:K]), nrow(eg$vectors), K, byrow=TRUE)
rownames(load) <- use_feats
commun <- rowSums(load^2)   # fraction of var explained by top-K PCs
uniq_var <- 1 - commun
new_uniq <- uniq_var[c(NEW3, RESID)]
cat("unique-variance (1 - top5PC communality) for new feats (higher=more idiosyncratic info):\n")
print(round(new_uniq, 3))

#==============================================================================
# PART C — Security covariance Sigma (Ledoit-Wolf) for candidate universe
#   Universe = tickers present at lockbox cross-section. Monthly Ret_1m history.
#   LW shrinkage to constant-correlation; cond# before/after; PSD check.
#==============================================================================
cat("\n== PART C: Sigma (Ledoit-Wolf) ==\n")
# build wide monthly return matrix, lockbox universe, history pre-lockbox
last_ym <- max(panel_lb$ym)
univ_tk <- panel_lb[ym == last_ym, unique(Ticker)]
# liquidity floor from request: 5e7 KRW 20d avg (adv here is daily value proxy)
liq_tk <- panel_lb[ym == last_ym & adv >= 5e7, unique(Ticker)]
univ_tk <- intersect(univ_tk, liq_tk)
retw <- dcast(panel_lb[Ticker %in% univ_tk, .(ym, Ticker, Ret_1m)],
              ym ~ Ticker, value.var = "Ret_1m")
retw[, ym := NULL]
R <- as.matrix(retw)
# keep tickers with >= 60 months of obs
nobs <- colSums(is.finite(R))
R <- R[, nobs >= 60, drop = FALSE]
# rows with no NA across kept set: use pairwise then fix; simpler -> impute col mean
for (j in seq_len(ncol(R))) { v <- R[,j]; v[!is.finite(v)] <- mean(v[is.finite(v)]); R[,j] <- v }
N <- ncol(R); Tn <- nrow(R)
cat("Sigma universe: N=", N, " T=", Tn, "\n")

S <- cov(R)
# Ledoit-Wolf shrinkage to constant-correlation target (LW 2004 honey)
lw_shrink <- function(R) {
  Tn <- nrow(R); N <- ncol(R)
  Xc <- scale(R, center = TRUE, scale = FALSE)
  S <- crossprod(Xc) / Tn
  s <- sqrt(diag(S))
  rbar <- (sum(S / outer(s, s)) - N) / (N * (N - 1))
  F <- rbar * outer(s, s); diag(F) <- diag(S)   # constant-corr target
  # pi-hat
  Y2 <- Xc^2
  piMat <- crossprod(Y2) / Tn - S^2
  pihat <- sum(piMat)
  # rho-hat
  theta_ii <- crossprod(Y2, Xc) / Tn   # rough term
  term <- 0
  for (i in seq_len(N)) {
    for (j in seq_len(N)) {
      if (i == j) next
      v1 <- mean((Xc[,i]^2) * Xc[,i] * Xc[,j]) - S[i,i]*S[i,j]
      v2 <- mean((Xc[,j]^2) * Xc[,i] * Xc[,j]) - S[j,j]*S[i,j]
      term <- term + (rbar/2) * ((s[j]/s[i]) * v1 + (s[i]/s[j]) * v2)
    }
  }
  rhohat <- sum(diag(piMat)) + term
  # gamma-hat
  gammahat <- sum((F - S)^2)
  kappa <- (pihat - rhohat) / gammahat
  delta <- max(0, min(1, kappa / Tn))
  Sigma <- delta * F + (1 - delta) * S
  list(Sigma = Sigma, delta = delta, S = S, F = F, rbar = rbar)
}
lw <- tryCatch(lw_shrink(R), error = function(e) { cat("LW err:", conditionMessage(e), "\n"); NULL })
condS <- kappa_num <- NA
cn_sample <- tryCatch(kappa(S, exact = TRUE), error=function(e) NA)
cn_floor <- NA; delta_eff <- NA
if (!is.null(lw)) {
  Sigma <- lw$Sigma
  cn_lw <- tryCatch(kappa(Sigma, exact = TRUE), error=function(e) NA)
  ev <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
  psd <- min(ev) >= -1e-10
  cat("delta (LW analytic shrinkage):", round(lw$delta,3), "\n")
  cat("cond# sample:", signif(cn_sample,3), " | cond# LW-analytic:", round(cn_lw,1), "\n")
  # cond# 991 > 500 hard threshold -> RF-R2 re-estimation: increase shrinkage to
  # constant-corr target until cond# < 500 (eigenvalue-floor regularization)
  delta_eff <- lw$delta
  Sig2 <- Sigma; cn2 <- cn_lw
  while (is.finite(cn2) && cn2 > 500 && delta_eff < 0.95) {
    delta_eff <- min(0.95, delta_eff + 0.05)
    Sig2 <- delta_eff * lw$F + (1 - delta_eff) * lw$S
    cn2 <- tryCatch(kappa(Sig2, exact = TRUE), error=function(e) NA)
  }
  # eigenvalue-floor ridge to guarantee cond# < 500 (target F itself ill-cond at N~T)
  eg2 <- eigen(Sig2, symmetric = TRUE)
  lam <- eg2$values
  ridge_used <- 0
  if (max(lam)/min(lam) > 500) {
    lam_floor <- max(lam) / 480          # enforce cond# <= 480 (margin under 500)
    ridge_used <- max(0, lam_floor - min(lam))
    lam2 <- pmax(lam, lam_floor)
    Sig2 <- eg2$vectors %*% diag(lam2) %*% t(eg2$vectors)
    Sig2 <- (Sig2 + t(Sig2)) / 2
  }
  cn2 <- tryCatch(kappa(Sig2, exact = TRUE), error=function(e) NA)
  Sigma <- Sig2; cn_floor <- cn2
  ev2 <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
  psd <- min(ev2) >= -1e-10
  cat("delta (after RF-R2 re-estimation):", round(delta_eff,3),
      " | eigen-ridge:", signif(ridge_used,3),
      " | cond# final:", round(cn_floor,1), "\n")
  cat("min eigen:", signif(min(ev2),3), " PSD:", psd, "\n")
  cat("avg pairwise corr (rbar):", round(lw$rbar,3), "\n")
  dimnames(Sigma) <- list(colnames(R), colnames(R))
  sig_dt <- data.table(Ticker = colnames(R)); sig_dt <- cbind(sig_dt, as.data.table(Sigma))
  write_parquet(sig_dt, file.path(OUT, "covariance.parquet"))
} else { cn_lw <- NA; psd <- NA; Sigma <- S }

#==============================================================================
# PART D — Tail risk (empirical VaR/ES + EVT-GPD + Hill) on equal-weight
#   candidate-universe portfolio monthly returns (panel-native, no overlay).
#==============================================================================
cat("\n== PART D: tail risk ==\n")
ewret <- panel_lb[, .(r = mean(Ret_1m, na.rm=TRUE)), by=ym][order(ym)]$r
ewret <- ewret[is.finite(ewret)]
q <- function(p) as.numeric(quantile(ewret, p))
var95 <- q(0.05); es95 <- mean(ewret[ewret <= var95])
var99 <- q(0.01); es99 <- mean(ewret[ewret <= var99])
# EVT-GPD on losses (POT, threshold = 90th pct of losses)
losses <- -ewret
u <- as.numeric(quantile(losses, 0.90))
exc <- losses[losses > u] - u
# MoM GPD fit
m1 <- mean(exc); v1 <- var(exc)
xi <- 0.5 * (1 - m1^2 / v1); beta <- 0.5 * m1 * (m1^2/v1 + 1)
xi <- max(min(xi, 0.95), -0.5)
nT <- length(losses); nu <- length(exc)
gpd_var <- function(p) u + (beta/xi) * (((nT/nu)*(1-p))^(-xi) - 1)
evt_var95 <- -gpd_var(0.95); evt_var99 <- -gpd_var(0.99)
# Hill alpha (tail index) top 10%
srt <- sort(losses, decreasing = TRUE); k <- max(5, floor(0.1*nT))
hill_alpha <- 1 / (mean(log(srt[1:k])) - log(srt[k+1]))
cat("empirical VaR95:", round(var95,4), " ES95:", round(es95,4),
    " VaR99:", round(var99,4), " ES99:", round(es99,4), "\n")
cat("EVT-GPD xi:", round(xi,3), " beta:", round(beta,4),
    " VaR95:", round(evt_var95,4), " VaR99:", round(evt_var99,4), "\n")
cat("Hill alpha (tail index):", round(hill_alpha,2), " (lower=fatter tail)\n")

#==============================================================================
# PART E — Stress tests (historical regime returns of EW candidate basket)
#   coverage = #tickers in panel that month / median panel size -> UNRELIABLE if <85%
#==============================================================================
cat("\n== PART E: stress ==\n")
panel[, date := as.Date(date)]
ew_all <- panel[, .(r = mean(Ret_1m, na.rm=TRUE), n = .N), by=.(ym, date)][order(date)]
med_n <- median(ew_all$n)
ew_all[, cov := n / med_n]
stress_windows <- list(
  GFC_2008      = c("2008-09-01","2009-03-31"),
  EuDebt_2011   = c("2011-08-01","2011-11-30"),
  China_2015    = c("2015-06-01","2015-09-30"),
  COVID_2020    = c("2020-02-01","2020-04-30"),
  RateHike_2022 = c("2022-01-01","2022-10-31"),
  KR_Bear_2018  = c("2018-06-01","2018-12-31")
)
stress <- lapply(names(stress_windows), function(nm){
  w <- as.Date(stress_windows[[nm]])
  sub <- ew_all[date >= w[1] & date <= w[2]]
  if (nrow(sub)==0) return(NULL)
  cum <- prod(1 + sub$r) - 1   # historical realized cumulative (descriptive, not contract bt)
  data.table(scenario=nm, cum_ret=round(cum,4), months=nrow(sub),
             min_cov=round(min(sub$cov),2),
             reliable = min(sub$cov) >= 0.85)
})
stress <- rbindlist(stress)
# scenario shocks (single-period sensitivities, descriptive)
market_down_5 <- -0.05 * (if(!is.null(lw)) lw$rbar else 1) * 1  # rough beta~1 EW
print(stress)
cat("market_down_5 (EW beta~1 proxy):", round(-0.05,4), "\n")

#==============================================================================
# PART F — Crowding score per factor (panel-native proxy)
#   Full Acadian needs RAWDATA(Vol/Size/inst flow); panel lacks daily vol+flow.
#   We compute panel-derivable proxies and label metric_type='proxy'.
#   Components: HHI of top-20 by feature (concentration), liquidity concentration
#   (adv share of top-20), passive_overlap (univ membership = all in_univ -> proxy),
#   demand_elasticity (size-weighted, smaller adv top-20 = less elastic).
#==============================================================================
cat("\n== PART F: crowding (panel proxy) ==\n")
crowd_feats <- c(NEW3, RESID,
                 grep("^M05_Trended_Mom__lvl$", base90, value=TRUE),
                 grep("^Q03_ROA__lvl$", base90, value=TRUE))
crowd_feats <- intersect(crowd_feats, names(panel_lb))
last <- panel_lb[ym == last_ym]
crowd <- lapply(crowd_feats, function(f){
  d <- last[is.finite(get(f))][order(-get(f))]
  if (nrow(d) < 20) return(NULL)
  top <- head(d, 20)
  # HHI of top-20 by |feature rank weight| (use rank-based equal-ish -> use adv weights)
  wt <- top$adv / sum(top$adv)
  hhi <- sum(wt^2)
  vol_conc <- sum(top$adv) / sum(d$adv)             # liquidity/volume concentration
  passive_overlap <- mean(top$Ticker %in% univ_tk)  # all in_univ -> ~1 (proxy ceiling)
  # demand elasticity proxy (Behmaram): larger top-20 adv share = more elastic = LESS crowded
  demand_elast <- 1 - vol_conc
  score <- 0.30*hhi*5 + 0.25*vol_conc + 0.25*passive_overlap + 0.20*(1-demand_elast)
  score <- max(0, min(1, score))
  data.table(factor_name=f, crowding_score=round(score,3), hhi_top=round(hhi,3),
             vol_concentration=round(vol_conc,3),
             passive_overlap_proxy=round(passive_overlap,3),
             demand_elasticity_proxy=round(demand_elast,3))
})
crowd <- rbindlist(crowd)
print(crowd)

#==============================================================================
# PART G — Concentration / HHI of candidate universe + regime correlation
#==============================================================================
cat("\n== PART G: concentration + regime corr ==\n")
# n_effective from EW (trivially N) -> instead sector HHI not available; use size HHI proxy
adv_last <- last[Ticker %in% univ_tk]
wmkt <- adv_last$adv / sum(adv_last$adv)
hhi_mktcap_proxy <- sum(wmkt^2)
n_eff <- 1 / hhi_mktcap_proxy
cat("universe N:", length(univ_tk), " n_effective(adv-wtd):", round(n_eff,1),
    " HHI:", round(hhi_mktcap_proxy,4), "\n")
# regime correlation: avg pairwise return corr in calm vs stress months
ew_all[, stress_flag := cov < 0.95 | abs(r) > 0.10]
# use cross-sec dispersion as crude regime corr proxy
disp <- panel[, .(xsd = sd(Ret_1m, na.rm=TRUE), mret=mean(Ret_1m,na.rm=TRUE)), by=ym]
regime_dt <- merge(ew_all[,.(ym, r, cov)], disp, by="ym")
regime_dt[, regime := fifelse(r < -0.08, "CRISIS", fifelse(r > 0.08, "RALLY", "NORMAL"))]
reg_summary <- regime_dt[, .(months=.N, mean_xsd=round(mean(xsd,na.rm=TRUE),3),
                             mean_ret=round(mean(r),4)), by=regime]
print(reg_summary)
write_parquet(regime_dt, file.path(OUT, "regime_correlation.parquet"))

#==============================================================================
# DUMP results JSON for package assembly
#==============================================================================
res <- list(
  sigma = list(N=N, T=Tn, method="ledoit_wolf_constant_corr + RF-R2 cond-floor",
               delta_analytic=if(!is.null(lw)) round(lw$delta,4) else NA,
               delta_effective=round(delta_eff,4),
               cond_sample=signif(cn_sample,4), cond_lw_analytic=round(cn_lw,1),
               cond_final=round(cn_floor,1), eigen_ridge=signif(ridge_used,4),
               psd=psd, avg_pairwise_corr=if(!is.null(lw)) round(lw$rbar,4) else NA,
               pc1_share=round(varexp[1],3)),
  resid_orthogonality = list(
     resid_var_share = lapply(resid_var_share, function(x) round(x,3)),
     resid_maxcorr_vs_base = lapply(resid_maxcorr_vs_base, function(x) round(x,3)),
     unique_var_top5PC = as.list(round(new_uniq,3)),
     era_corr = era_corr),
  tail = list(emp_var95=round(var95,4), emp_es95=round(es95,4),
              emp_var99=round(var99,4), emp_es99=round(es99,4),
              evt_xi=round(xi,3), evt_var95=round(evt_var95,4),
              evt_var99=round(evt_var99,4), hill_alpha=round(hill_alpha,2)),
  stress = stress,
  crowding = crowd,
  concentration = list(N=length(univ_tk), n_effective=round(n_eff,1),
                       hhi=round(hhi_mktcap_proxy,4)),
  regime = reg_summary
)
jsonlite::write_json(res, file.path(OUT, "_risk_results.json"),
                     pretty=TRUE, auto_unbox=TRUE, digits=6, null="null")
cat("\n== DONE. results -> ", file.path(OUT,"_risk_results.json"), "==\n")
