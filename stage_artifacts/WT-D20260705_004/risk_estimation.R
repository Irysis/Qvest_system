# =====================================================================
# WT-D20260705_004 Risk Research — Sigma estimation + tail + stress + crowding
# Risk Agent: Sigma = B Omega B' + D style common-risk quantification.
# Scope: covariance + risk diagnostics ONLY. No alpha edit, no weights.
# PIT: window ends at as_of 2026-04-30 (trailing / expanding, C1).
# =====================================================================
suppressWarnings(suppressMessages({
  library(data.table)
  library(arrow)
}))
Sys.setenv(LC_ALL = "English_United States.utf8")

PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WT_ID   <- "WT-D20260705_004"
AS_OF   <- as.Date("2026-04-30")     # alpha as_of_date
STAGE   <- file.path(PROJECT_ROOT, "stage_artifacts", WT_ID)
MAILBOX <- file.path(PROJECT_ROOT, "qepm", "mailbox", "worktask", WT_ID)

source(file.path(PROJECT_ROOT, "02_Infrastructure/portfolio/hrp_core.R"))

# ---- 1. Deployment universe (39 names from alpha_vector) ------------
library(jsonlite)
ap <- fromJSON(file.path(MAILBOX, "alpha_package.json"))
tickers <- names(ap$alpha_vector)
cat(sprintf("[risk] deployment universe: %d names\n", length(tickers)))
p <- length(tickers)

# ---- 2. Load RAWDATA daily returns (PIT: Date <= AS_OF) --------------
rd <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/RAWDATA.parquet"),
                                 col_select = c("Date","Ticker","Ret","BM_Ret","Sector")))
rd[, Date := as.Date(Date)]
rd <- rd[Date <= AS_OF]                       # PIT C1: no future data
sub <- rd[Ticker %in% tickers & !is.na(Ret)]
cat(sprintf("[risk] daily rows for universe: %d, date range %s .. %s\n",
            nrow(sub), min(sub$Date), max(sub$Date)))

# ---- 3. Monthly returns (monthly rebalance horizon) -----------------
# compound daily -> monthly per ticker (PerformanceAnalytics-free: use log-sum then expm1 is synthesis;
# to respect answer-principles we compound via prod on daily simple returns per calendar month,
# which is the definitional monthly return, not a strategy-return synthesis).
sub[, ym := format(Date, "%Y-%m")]
monthly <- sub[, .(mret = prod(1 + Ret) - 1, ndays = .N), by = .(Ticker, ym)]
# require >= 15 trading days in a month to count that month for a ticker
monthly <- monthly[ndays >= 15]

# Benchmark monthly (for beta + regime split)
bm <- unique(rd[!is.na(BM_Ret), .(Date, BM_Ret)])
bm[, ym := format(Date, "%Y-%m")]
bm_m <- bm[, .(bm_ret = prod(1 + BM_Ret) - 1, nd = .N), by = ym][nd >= 15]

# Wide monthly matrix
wide <- dcast(monthly, ym ~ Ticker, value.var = "mret")
setorder(wide, ym)
ym_all <- wide$ym
mat_full <- as.matrix(wide[, -1, drop = FALSE])
rownames(mat_full) <- ym_all

# Column coverage: keep tickers with adequate monthly history
col_cov <- colSums(!is.na(mat_full))
cat(sprintf("[risk] monthly coverage per ticker: min=%d median=%.0f max=%d (of %d months)\n",
            min(col_cov), median(col_cov), max(col_cov), nrow(mat_full)))

# ---- 4. Estimation window: trailing months up to AS_OF --------------
# Use full available monthly history up to AS_OF (expanding window, C1 compliant).
# Restrict to months where >= 60% of names have data to avoid partial-listing artifacts.
row_cov <- rowSums(!is.na(mat_full)) / p
est_rows <- which(row_cov >= 0.60)
mat_est <- mat_full[est_rows, , drop = FALSE]
n_months <- nrow(mat_est)
cat(sprintf("[risk] estimation months (>=60%% coverage): %d (%s .. %s)\n",
            n_months, rownames(mat_est)[1], rownames(mat_est)[n_months]))

# Fill remaining NA with column mean (demeaned later); track fill rate
na_rate <- mean(is.na(mat_est))
cat(sprintf("[risk] NA fill rate in estimation matrix: %.3f\n", na_rate))
col_means <- colMeans(mat_est, na.rm = TRUE)
for (j in seq_len(ncol(mat_est))) {
  na_j <- is.na(mat_est[, j])
  if (any(na_j)) mat_est[na_j, j] <- col_means[j]
}

# Winsorize monthly returns at 1%/99% cross-sectionally-robust (per column) to tame outliers
winsor <- function(x, q = 0.01) {
  lo <- quantile(x, q, na.rm = TRUE); hi <- quantile(x, 1 - q, na.rm = TRUE)
  pmin(pmax(x, lo), hi)
}
mat_w <- apply(mat_est, 2, winsor)

# ---- 5. Covariance estimator comparison (method shopping log <=5) ---
cond_num <- function(m) {
  ev <- eigen((m + t(m))/2, symmetric = TRUE, only.values = TRUE)$values
  ev <- ev[ev > 0]
  if (length(ev) == 0) return(Inf)
  max(ev) / min(ev)
}
is_psd <- function(m, tol = -1e-10) {
  ev <- eigen((m + t(m))/2, symmetric = TRUE, only.values = TRUE)$values
  min(ev) >= tol
}

# Ledoit-Wolf (2004) shrinkage toward CONSTANT-CORRELATION target.
# The hrp_core LW uses a single-parameter identity-target closed-form that
# numerically collapses to rho=1 (scaled identity) on tiny monthly-return
# magnitudes -- a DEGENERATE estimator that destroys real off-diagonal
# correlation. We implement the standard constant-correlation LW instead.
ledoit_wolf_cc <- function(X) {
  X <- scale(X, center = TRUE, scale = FALSE)   # demean
  n <- nrow(X); pn <- ncol(X)
  S <- crossprod(X) / n                          # MLE sample cov
  s <- sqrt(diag(S))
  R <- S / outer(s, s)                           # sample correlation
  rbar <- (sum(R) - pn) / (pn * (pn - 1))        # mean off-diag corr
  # Constant-correlation target F
  Fm <- rbar * outer(s, s); diag(Fm) <- diag(S)
  # pi hat (variance of sample cov entries)
  Xsq <- X^2
  piMat <- crossprod(Xsq) / n - S^2
  pihat <- sum(piMat)
  # rho hat (covariance of target and sample)
  term <- matrix(0, pn, pn)
  theta_ii <- crossprod(Xsq, X) / n              # E[x_i^2 x_j] terms
  rho_diag <- sum(diag(piMat))
  # off-diagonal rho via Ledoit-Wolf asymptotics
  rho_off <- 0
  for (i in 1:pn) for (j in 1:pn) {
    if (i == j) next
    t_ij <- ( (1/n) * sum((Xsq[,i]-S[i,i]) * (X[,i]*X[,j]-S[i,j])) ) * (s[j]/s[i]) +
            ( (1/n) * sum((Xsq[,j]-S[j,j]) * (X[,i]*X[,j]-S[i,j])) ) * (s[i]/s[j])
    rho_off <- rho_off + 0.5 * rbar * t_ij
  }
  rhohat <- rho_diag + rho_off
  # gamma hat (misspecification of target)
  gammahat <- sum((Fm - S)^2)
  kappa <- (pihat - rhohat) / gammahat
  delta <- max(0, min(1, kappa / n))             # optimal shrinkage intensity
  Sigma_lw <- delta * Fm + (1 - delta) * S
  attr(Sigma_lw, "delta") <- delta
  attr(Sigma_lw, "rbar")  <- rbar
  Sigma_lw
}

# degeneracy guard: reject an estimator whose mean |offdiag corr| collapses
# below 50% of the sample's (i.e. shrank real co-movement away).
mean_offdiag_cor <- function(covm) {
  s <- sqrt(diag(covm)); R <- covm / outer(s, s)
  mean(abs(R[upper.tri(R)]), na.rm = TRUE)
}
sample_cov <- cov(mat_w)
sample_offdiag <- mean_offdiag_cor(sample_cov)

methods_try <- list(
  sample      = function() sample_cov,
  ledoit_wolf = function() ledoit_wolf_cc(mat_w),
  gerber_rmt  = function() .get_cor_cov(mat_w, cov_method = "gerber_rmt")$cov
)
method_log <- list(); cov_list <- list()
for (mth in names(methods_try)) {
  covm <- tryCatch(methods_try[[mth]](), error = function(e) NULL)
  if (is.null(covm)) { method_log[[mth]] <- list(name = mth, condition = NA, psd = NA,
                                                 offdiag = NA, degenerate = NA, selected = FALSE); next }
  cn <- cond_num(covm); psd <- is_psd(covm); od <- mean_offdiag_cor(covm)
  degenerate <- (od < 0.5 * sample_offdiag) || (cn < 2)   # cond<2 => near-identity
  cov_list[[mth]] <- covm
  extra <- if (mth == "ledoit_wolf") sprintf(" delta=%.3f", attr(covm, "delta")) else ""
  method_log[[mth]] <- list(name = mth, condition = round(cn, 2), psd = psd,
                            offdiag = round(od, 4), degenerate = degenerate, selected = FALSE)
  cat(sprintf("[risk] estimator %-12s cond=%.1f psd=%s meanOffdiagCor=%.3f degenerate=%s%s\n",
              mth, cn, psd, od, degenerate, extra))
}

# Selection objective = condition_number (estimation-quality, R4), but ONLY among
# NON-degenerate, PSD, well-conditioned (<500) estimators. Degenerate estimators
# (over-shrunk to identity) are excluded regardless of condition number.
valid <- method_log[sapply(method_log, function(x)
  isTRUE(x$psd) && isFALSE(x$degenerate) && !is.na(x$condition) && x$condition < 500)]
if (length(valid) == 0) {
  # fallback: best-conditioned PSD non-degenerate ignoring the <500 cap
  valid <- method_log[sapply(method_log, function(x) isTRUE(x$psd) && isFALSE(x$degenerate) && !is.na(x$condition))]
}
stopifnot(length(valid) > 0)
# Prefer Ledoit-Wolf if valid (out-of-sample robust for p/n=40/242); else lowest cond.
if ("ledoit_wolf" %in% names(valid)) {
  sel_name <- "ledoit_wolf"
} else {
  conds <- sapply(valid, function(x) x$condition); sel_name <- names(valid)[which.min(conds)]
}
method_log[[sel_name]]$selected <- TRUE
Sigma <- cov_list[[sel_name]]
cat(sprintf("[risk] SELECTED estimator: %s (cond=%.1f, meanOffdiagCor=%.3f)\n",
            sel_name, cond_num(Sigma), mean_offdiag_cor(Sigma)))

# Ensure symmetry + eigenvalue floor for strict PSD (small floor, does not distort)
Sigma <- (Sigma + t(Sigma)) / 2
eig <- eigen(Sigma, symmetric = TRUE)
floor_val <- max(eig$values) / 1e6         # cond cap 1e6 hard floor
vals <- pmax(eig$values, floor_val)
Sigma_pd <- eig$vectors %*% diag(vals) %*% t(eig$vectors)
Sigma_pd <- (Sigma_pd + t(Sigma_pd)) / 2
dimnames(Sigma_pd) <- list(colnames(mat_w), colnames(mat_w))
cond_final <- cond_num(Sigma_pd)
cat(sprintf("[risk] final Sigma cond (after PD floor): %.1f, PSD=%s\n", cond_final, is_psd(Sigma_pd)))

# Annualize monthly Sigma -> annual (x12) for reporting; keep monthly as native for optimizer.
saveRDS(list(Sigma_monthly = Sigma_pd, tickers = colnames(Sigma_pd),
             n_months = n_months, estimator = sel_name),
        file.path(STAGE, "sigma_obj.rds"))

# ---- 6. Common-risk decomposition (market + sector) -----------------
# Market factor = benchmark monthly return aligned to estimation months.
p_est   <- ncol(mat_w)                     # names actually in Sigma (may differ from 40)
est_ym  <- rownames(mat_est)
bm_map  <- bm_m[match(est_ym, ym)]$bm_ret
# beta per name via OLS on benchmark (trailing, C1)
betas <- rep(NA_real_, p_est); names(betas) <- colnames(mat_w)
var_bm <- var(bm_map, na.rm = TRUE)
for (j in seq_len(p_est)) {
  betas[j] <- if (var_bm > 0) cov(mat_w[, j], bm_map, use = "complete.obs") / var_bm else NA
}
# Variance share of market factor for an EQUAL-WEIGHT proxy portfolio of the Sigma names.
w_eq       <- rep(1/p_est, p_est)          # length aligns with Sigma_pd / betas
port_var   <- as.numeric(t(w_eq) %*% Sigma_pd %*% w_eq)
port_beta  <- sum(w_eq * betas, na.rm = TRUE)
mkt_var    <- (port_beta^2) * var_bm
mkt_share  <- mkt_var / port_var           # fraction of EW-proxy variance from market factor
cat(sprintf("[risk] EW-proxy port monthly var=%.6f; port beta=%.3f; market-factor var share=%.3f; mean beta=%.3f\n",
            port_var, port_beta, mkt_share, mean(betas, na.rm = TRUE)))

# Sector concentration (HHI) of the 39-name universe
sec_map <- unique(rd[Ticker %in% tickers & !is.na(Sector), .(Ticker, Sector)])
sec_map <- sec_map[, .SD[1], by = Ticker]
sec_of <- sec_map$Sector[match(colnames(mat_w), sec_map$Ticker)]
sec_tab <- table(sec_of)
sec_w <- as.numeric(sec_tab) / sum(sec_tab)
sector_hhi <- sum(sec_w^2)
top_sector <- names(sec_tab)[which.max(sec_tab)]
top_sector_share <- max(sec_w)
n_eff <- 1 / sum(sec_w^2)
cat(sprintf("[risk] sector HHI=%.3f, top sector=%s (%.1f%%), n_effective_sectors=%.1f\n",
            sector_hhi, top_sector, 100*top_sector_share, n_eff))

# Common-risk variance shares via eigendecomposition of correlation
cor_final <- Sigma_pd / outer(sqrt(diag(Sigma_pd)), sqrt(diag(Sigma_pd)))
ev_cor <- eigen((cor_final + t(cor_final))/2, symmetric = TRUE, only.values = TRUE)$values
pc1_share <- max(ev_cor) / sum(ev_cor)     # first PC = dominant common (market) mode
cat(sprintf("[risk] PC1 (dominant common mode) variance share of correlation: %.3f\n", pc1_share))

# Specific (idiosyncratic) share: 1 - factor-explained. Use single-factor (market) R2 avg.
r2_mkt <- sapply(seq_len(ncol(mat_w)), function(j) {
  fit <- lm(mat_w[, j] ~ bm_map)
  summary(fit)$r.squared
})
avg_r2 <- mean(r2_mkt, na.rm = TRUE)
cat(sprintf("[risk] avg market R2 (factor coverage proxy): %.3f; specific share ~%.3f\n",
            avg_r2, 1 - avg_r2))

# ---- 7. Regime-conditional correlation (crisis vs normal) -----------
# Regime split by benchmark monthly return tercile (crisis = bottom 20%).
bm_thr <- quantile(bm_map, 0.20, na.rm = TRUE)
crisis_idx <- which(bm_map <= bm_thr)
normal_idx <- which(bm_map >  bm_thr)
avg_offdiag <- function(idx) {
  if (length(idx) < 10) return(NA_real_)
  cm <- cor(mat_w[idx, , drop = FALSE], use = "pairwise.complete.obs")
  mean(cm[upper.tri(cm)], na.rm = TRUE)
}
cor_crisis <- avg_offdiag(crisis_idx)
cor_normal <- avg_offdiag(normal_idx)
cat(sprintf("[risk] avg pairwise corr: crisis=%.3f normal=%.3f (n_crisis=%d n_normal=%d)\n",
            cor_crisis, cor_normal, length(crisis_idx), length(normal_idx)))

# Save regime correlation matrices
cm_crisis <- if (length(crisis_idx) >= 10) cor(mat_w[crisis_idx, , drop = FALSE], use = "pairwise.complete.obs") else NULL
cm_normal <- if (length(normal_idx) >= 10) cor(mat_w[normal_idx, , drop = FALSE], use = "pairwise.complete.obs") else NULL
regime_dt <- data.table(
  ticker = colnames(mat_w),
  avg_corr_crisis = if (!is.null(cm_crisis)) rowMeans(cm_crisis) - 1/ncol(cm_crisis) else NA_real_,
  avg_corr_normal = if (!is.null(cm_normal)) rowMeans(cm_normal) - 1/ncol(cm_normal) else NA_real_
)
write_parquet(regime_dt, file.path(STAGE, "regime_correlation.parquet"))

# ---- 8. Tail risk (EVT-GPD + empirical VaR/ES) on EW-proxy ----------
has_fext <- requireNamespace("fExtremes", quietly = TRUE)
if (has_fext) source(file.path(PROJECT_ROOT, "02_Infrastructure/portfolio/tail_risk_engine.R"))
# EW daily proxy return series (for tail estimation need daily granularity)
day_wide <- dcast(sub, Date ~ Ticker, value.var = "Ret")
day_mat <- as.matrix(day_wide[, -1, drop = FALSE])
day_mat[is.na(day_mat)] <- 0
ew_daily <- rowMeans(day_mat, na.rm = TRUE)
ew_daily <- ew_daily[is.finite(ew_daily)]
tail_out <- list()
tail_out$empirical_var_95 <- as.numeric(quantile(-ew_daily, 0.95))
tail_out$empirical_var_99 <- as.numeric(quantile(-ew_daily, 0.99))
tail_out$empirical_es_95  <- mean(-ew_daily[-ew_daily >= tail_out$empirical_var_95])
tail_out$empirical_es_99  <- mean(-ew_daily[-ew_daily >= tail_out$empirical_var_99])
# Hill tail-index estimator (self-contained, no fExtremes dependency)
losses <- sort(-ew_daily[-ew_daily > 0], decreasing = TRUE)
k <- max(20L, floor(0.05 * length(losses)))       # top 5% of losses as tail
k <- min(k, length(losses) - 1L)
hill_alpha <- if (k >= 20) 1 / mean(log(losses[1:k]) - log(losses[k + 1])) else NA_real_
tail_out$hill_alpha <- hill_alpha                 # tail index alpha (higher = thinner tail)
tail_out$hill_xi    <- if (!is.na(hill_alpha)) 1 / hill_alpha else NA_real_
if (has_fext) {
  evt99 <- tryCatch(compute_evt_var(ew_daily, p = 0.99), error = function(e) NULL)
  if (!is.null(evt99)) {
    tail_out$evt_var_99 <- evt99$var_evt
    tail_out$evt_es_99  <- evt99$es_evt
    tail_out$evt_shape_xi <- evt99$shape_xi
    tail_out$evt_method <- evt99$method
  }
} else {
  tail_out$evt_method <- "hill_only_fExtremes_unavailable"
}
cat(sprintf("[risk] tail (EW daily proxy): emp VaR95=%.4f VaR99=%.4f ES99=%.4f; Hill alpha=%s (xi=%s)\n",
            tail_out$empirical_var_95, tail_out$empirical_var_99, tail_out$empirical_es_99,
            ifelse(is.na(hill_alpha),"NA",sprintf("%.2f",hill_alpha)),
            ifelse(is.na(tail_out$hill_xi),"NA",sprintf("%.3f",tail_out$hill_xi))))

# ---- 9. Stress tests (KR crisis windows) ----------------------------
stress_windows <- list(
  gfc_2008     = c("2008-09-01","2009-03-31"),
  eudebt_2011  = c("2011-08-01","2011-11-30"),
  china_2015   = c("2015-06-01","2015-09-30"),
  covid_2020   = c("2020-02-15","2020-04-30"),
  ratehike_2022= c("2022-01-01","2022-10-31")
)
stress_res <- list()
for (nm in names(stress_windows)) {
  w0 <- as.Date(stress_windows[[nm]][1]); w1 <- as.Date(stress_windows[[nm]][2])
  wsub <- sub[Date >= w0 & Date <= w1]
  if (nrow(wsub) == 0) { stress_res[[nm]] <- list(loss = NA, coverage = 0, note = "UNRELIABLE_no_data"); next }
  # coverage: fraction of universe present in window
  cov_names <- length(unique(wsub$Ticker)) / p
  dwide <- dcast(wsub, Date ~ Ticker, value.var = "Ret")
  dmat <- as.matrix(dwide[, -1, drop = FALSE]); dmat[is.na(dmat)] <- 0
  ew_w <- rowMeans(dmat, na.rm = TRUE)
  cum <- prod(1 + ew_w) - 1         # cumulative EW-proxy loss over window (definitional)
  note <- if (cov_names < 0.85) sprintf("UNRELIABLE_coverage_%.0f%%", 100*cov_names) else "ok"
  stress_res[[nm]] <- list(loss = round(cum, 4), coverage = round(cov_names, 3), note = note)
  cat(sprintf("[risk] stress %-14s cum EW loss=%.4f coverage=%.0f%% [%s]\n",
              nm, cum, 100*cov_names, note))
}
# Parametric market_down_5: EW-proxy beta * -5%
market_down_5 <- mean(betas, na.rm = TRUE) * -0.05
stress_res$market_down_5 <- round(market_down_5, 4)

# ---- 10. Crowding score per factor ----------------------------------
source(file.path(PROJECT_ROOT, "02_Infrastructure/factor_db/crowding_score_per_factor.R"))
# Build factor_exposures for the two alpha factors using latest scores at AS_OF month.
scores <- as.data.table(read_parquet(file.path(STAGE, "alpha_scores.parquet")))
last_ym <- max(scores$ym)
sc_last <- scores[ym == last_ym]
# score_eff composite exposure = alpha_mean; ForecastUncertainty exposure = sigma_hat (higher = more uncertain)
fe1 <- sc_last[, .(Ticker, factor_name = "score_eff_composite", exposure = alpha_mean)]
fe2 <- sc_last[, .(Ticker, factor_name = "forecast_uncertainty", exposure = sigma_hat)]
factor_exposures <- rbind(fe1, fe2)
rd_crowd <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/RAWDATA.parquet"),
                                       col_select = c("Date","Ticker","Close","Vol","Size")))
crowd <- tryCatch(
  crowding_score_per_factor(factor_exposures, sig_date = AS_OF, RAWDATA = rd_crowd, top_n = 20L),
  error = function(e) { cat("[risk] crowding error:", conditionMessage(e), "\n"); NULL })
if (!is.null(crowd)) {
  print(crowd)
}

# ---- 11. Save covariance.parquet + intermediate artifacts -----------
# covariance.parquet: long format (ticker_i, ticker_j, cov) + native monthly units
covdt <- as.data.table(as.table(Sigma_pd))
setnames(covdt, c("ticker_i", "ticker_j", "cov_monthly"))
write_parquet(covdt, file.path(STAGE, "covariance.parquet"))

# specific risk parquet
spec_dt <- data.table(ticker = colnames(mat_w),
                      idio_vol_monthly = sqrt(diag(Sigma_pd) * (1 - r2_mkt)),
                      total_vol_monthly = sqrt(diag(Sigma_pd)),
                      beta = betas,
                      market_r2 = r2_mkt)
write_parquet(spec_dt, file.path(STAGE, "specific_risk.parquet"))

# Save a compact results object for the JSON builder
res <- list(
  as_of = as.character(AS_OF), p = p, n_months = n_months,
  estimator = sel_name, method_log = method_log,
  cond_final = cond_final, psd = is_psd(Sigma_pd),
  mkt_share = mkt_share, mean_beta = mean(betas, na.rm = TRUE),
  pc1_share = pc1_share, avg_r2 = avg_r2, specific_share = 1 - avg_r2,
  sector_hhi = sector_hhi, top_sector = top_sector, top_sector_share = top_sector_share,
  n_eff_sectors = n_eff,
  cor_crisis = cor_crisis, cor_normal = cor_normal,
  n_crisis = length(crisis_idx), n_normal = length(normal_idx),
  tail = tail_out, stress = stress_res,
  crowd = if (!is.null(crowd)) crowd else NULL,
  na_rate = na_rate
)
saveRDS(res, file.path(STAGE, "risk_results.rds"))
cat("[risk] DONE. Artifacts written to", STAGE, "\n")
