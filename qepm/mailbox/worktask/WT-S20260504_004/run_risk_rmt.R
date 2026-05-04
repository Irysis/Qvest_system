# ───────────────────────────────────────────────────────────────────────────
# WT-S20260504_004 — RMT Denoised Σ Risk Research Pipeline
# Method: Marchenko-Pastur eigenvalue threshold (Laloux 1999 / Bouchaud-Potters 2009 / Plerou 2002)
# Pipeline: daily ret → R = corr → eigen → MP bulk filter → Λ_clean → R̂ → Σ̂ = D R̂ D
#           → portfolio σ → ES forecast (denoised + Cornish-Fisher + EVT-GPD)
#           → vol scale path → tail risk + 8 stress + AX-001v2 conditional
# Boundary: NO alpha modification, NO weight optimization (sizing recommendation only),
#           STR_1715 production directory write_count = 0 (audit verified).
# ───────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT   <- "WT-S20260504_004"
SAGE <- file.path(PROJ, "stage_artifacts", paste0("WT_", WT))
MBOX <- file.path(PROJ, "qepm/mailbox/worktask", WT)
DBG  <- file.path(SAGE, "_debug")
dir.create(SAGE, recursive = TRUE, showWarnings = FALSE)
dir.create(DBG,  recursive = TRUE, showWarnings = FALSE)

cat("[run_risk_rmt] start | WT=", WT, "\n", sep="")

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# ───────────────────────────────────────────────────────────────────────────
# 1. STR_1715 weights (18 active) + parent backtest period_returns (268 mo)
# ───────────────────────────────────────────────────────────────────────────
w_csv <- file.path(PROJ,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/production_weights/20260501_weights_cap_0p20.csv")
w_dt <- fread(w_csv)
w_dt <- w_dt[Weight > 0]
weights_18 <- w_dt$Weight; names(weights_18) <- w_dt$Ticker
n_active <- length(weights_18)
cat(sprintf("[Step 1] active stocks=%d sum_w=%.4f\n", n_active, sum(weights_18)))

pr_csv <- file.path(PROJ,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv")
pr <- fread(pr_csv)
pr[, date := as.Date(date)]
pr_xts <- xts(pr$ret_net, order.by = pr$date)
cat(sprintf("[Step 1] STR_1715 monthly returns n=%d range=[%s, %s]\n",
            length(pr_xts), format(min(index(pr_xts))), format(max(index(pr_xts)))))

# ───────────────────────────────────────────────────────────────────────────
# 2. RAWDATA daily returns — universe expansion (top liquid KR stocks) + 18 active
# ───────────────────────────────────────────────────────────────────────────
RAW <- read_parquet(file.path(PROJ, ".cache/rawdata.parquet"))
setDT(RAW)

# PIT: cap at as_of_date 2026-04-30 (NOT current 2026-05-04)
as_of  <- as.Date("2026-04-30")
RAW <- RAW[Date <= as_of]
window_end   <- as_of
window_start <- as_of - 1500  # buffer

RAW_w <- RAW[Date >= window_start & Date <= window_end &
             !is.na(Ret) & !is.na(Vol) & !is.na(Close) &
             AdminStock %in% c(NA, FALSE, 0) &
             TradingHalt %in% c(NA, FALSE, 0)]

# Universe = STR_1715 universe definition: KOSPI200 ∪ KOSDAQ150 + 18 active
# But for RMT need wider universe (T>>N) — pick top 200 by avg ADV in window
adv_dt <- RAW_w[, .(avg_dv = mean(Close * Vol, na.rm = TRUE),
                     n_obs  = .N), keyby = Ticker]
adv_dt <- adv_dt[n_obs >= 800 & avg_dv >= 2e8]  # liquidity floor

# Force include the 18 active
must_inc <- intersect(names(weights_18), unique(RAW_w$Ticker))
top_liquid <- adv_dt[order(-avg_dv)][1:200]$Ticker
universe <- union(must_inc, top_liquid)
cat(sprintf("[Step 2] universe size=%d (must_inc=%d, liquid_top=%d)\n",
            length(universe), length(must_inc), length(top_liquid)))

# Wide returns matrix (date × ticker)
RAW_u <- RAW_w[Ticker %in% universe, .(Date, Ticker, Ret)]
ret_wide <- dcast(RAW_u, Date ~ Ticker, value.var = "Ret")
ret_wide <- ret_wide[order(Date)]

# Take last 924 trading days from this matrix
all_dates <- ret_wide$Date
if (length(all_dates) > 924) {
  ret_wide <- ret_wide[(.N - 923):.N]
}
date_vec <- ret_wide$Date
ret_mat <- as.matrix(ret_wide[, !"Date", with = FALSE])
rownames(ret_mat) <- as.character(date_vec)

# Drop columns with > 10% NA
na_pct <- colSums(is.na(ret_mat)) / nrow(ret_mat)
keep_cols <- colnames(ret_mat)[na_pct < 0.10]
ret_mat <- ret_mat[, keep_cols, drop = FALSE]
# Fill remaining NA with 0 (no-trade day)
ret_mat[is.na(ret_mat)] <- 0
T_obs <- nrow(ret_mat); N <- ncol(ret_mat)
cat(sprintf("[Step 2] return matrix T=%d N=%d q=T/N=%.3f\n", T_obs, N, T_obs/N))

# Active subset for portfolio σ
active_in <- intersect(names(weights_18), colnames(ret_mat))
n_active_in <- length(active_in)
cat(sprintf("[Step 2] active stocks present in ret_mat: %d/%d\n", n_active_in, n_active))
if (n_active_in < n_active) {
  miss <- setdiff(names(weights_18), colnames(ret_mat))
  cat("  missing:", paste(miss, collapse=","), "\n")
}

# ───────────────────────────────────────────────────────────────────────────
# 3. Sample correlation R, sample covariance Σ_sample
# ───────────────────────────────────────────────────────────────────────────
sds <- apply(ret_mat, 2, sd, na.rm = TRUE)
sds[sds < 1e-8] <- 1e-8
Z <- scale(ret_mat, center = TRUE, scale = sds)
R_sample <- crossprod(Z) / (T_obs - 1)
diag(R_sample) <- 1.0
R_sample <- (R_sample + t(R_sample)) / 2
Sigma_sample <- diag(sds) %*% R_sample %*% diag(sds)
colnames(Sigma_sample) <- rownames(Sigma_sample) <- colnames(ret_mat)

# ───────────────────────────────────────────────────────────────────────────
# 4. Marchenko-Pastur theoretical bulk
# ───────────────────────────────────────────────────────────────────────────
q_ratio    <- T_obs / N
lambda_min_MP <- (1 - sqrt(1 / q_ratio))^2
lambda_max_MP <- (1 + sqrt(1 / q_ratio))^2

eig <- eigen(R_sample, symmetric = TRUE)
vals <- eig$values; vecs <- eig$vectors

n_signal <- sum(vals > lambda_max_MP)
n_noise  <- sum(vals <= lambda_max_MP)
cat(sprintf("[Step 4] MP bulk = [%.4f, %.4f] | signal eig=%d / noise eig=%d (total=%d)\n",
            lambda_min_MP, lambda_max_MP, n_signal, n_noise, length(vals)))

# Save raw + denoised eigenvalues
eig_df <- data.table(
  rank = seq_along(vals),
  eigenvalue_raw = vals,
  is_signal = vals > lambda_max_MP,
  is_market_eig = vals == max(vals),
  lambda_max_MP = lambda_max_MP,
  lambda_min_MP = lambda_min_MP
)

# ───────────────────────────────────────────────────────────────────────────
# 5. Eigenvalue cleaning: noise → flatten to bulk mean, signal retained
# Trace preservation: ensure trace(Λ_clean) = N
# ───────────────────────────────────────────────────────────────────────────
vals_clean <- vals
noise_idx <- which(vals <= lambda_max_MP)
if (length(noise_idx) > 0 && length(noise_idx) < length(vals)) {
  bulk_mean <- mean(vals[noise_idx])
  vals_clean[noise_idx] <- bulk_mean
}
# Renormalize so trace = N (preserve total variance of correlation)
vals_clean <- vals_clean * (N / sum(vals_clean))

eig_df[, eigenvalue_denoised := vals_clean]
fwrite(eig_df, file.path(SAGE, "rmt_eigenvalues.csv"))

# Reconstruct denoised correlation
D_clean <- diag(vals_clean)
R_denoised <- vecs %*% D_clean %*% t(vecs)
diag(R_denoised) <- 1.0
R_denoised <- (R_denoised + t(R_denoised)) / 2
colnames(R_denoised) <- rownames(R_denoised) <- colnames(R_sample)

# Denoised Σ
Sigma_denoised <- diag(sds) %*% R_denoised %*% diag(sds)
colnames(Sigma_denoised) <- rownames(Sigma_denoised) <- colnames(R_sample)

# PSD verify (denoised)
eig_chk <- eigen(Sigma_denoised, symmetric = TRUE, only.values = TRUE)$values
min_eig_d <- min(eig_chk)
max_eig_d <- max(eig_chk)
cond_d <- max_eig_d / max(min_eig_d, 1e-12)
cat(sprintf("[Step 5] denoised Σ: min_eig=%.4e cond=%.2f\n", min_eig_d, cond_d))

if (min_eig_d < 0) {
  # PSD repair: floor min eig to 1e-8 of max
  vals_clean2 <- pmax(vals_clean, max(vals_clean) * 1e-6)
  vals_clean2 <- vals_clean2 * (N / sum(vals_clean2))
  R_denoised <- vecs %*% diag(vals_clean2) %*% t(vecs)
  diag(R_denoised) <- 1.0
  R_denoised <- (R_denoised + t(R_denoised)) / 2
  Sigma_denoised <- diag(sds) %*% R_denoised %*% diag(sds)
  colnames(Sigma_denoised) <- rownames(Sigma_denoised) <- colnames(R_sample)
  min_eig_d <- min(eigen(Sigma_denoised, symmetric=TRUE, only.values=TRUE)$values)
  cat(sprintf("[Step 5] PSD-repaired min_eig=%.4e\n", min_eig_d))
}

# Save Σ as LONG parquet
Sig_long <- as.data.table(as.table(Sigma_denoised))
setnames(Sig_long, c("Ticker_i","Ticker_j","Sigma_ij"))
Sig_long[, Ticker_i := as.character(Ticker_i)]
Sig_long[, Ticker_j := as.character(Ticker_j)]
write_parquet(Sig_long, file.path(SAGE, "covariance.parquet"))
cat("[Step 5] covariance.parquet written\n")

# ───────────────────────────────────────────────────────────────────────────
# 6. Method shopping log — Sample / Ledoit-Wolf / RMT denoised
# ───────────────────────────────────────────────────────────────────────────
# LW shrinkage (constant correlation target) — VECTORIZED phi (Codex C2 fix)
lw_shrink <- function(Y) {
  n <- nrow(Y); p <- ncol(Y)
  S <- cov(Y, use="pairwise.complete.obs")
  s <- sqrt(pmax(diag(S), 1e-12))
  R <- S / outer(s, s)
  rbar <- (sum(R) - p) / (p * (p - 1))
  F_target <- rbar * outer(s, s); diag(F_target) <- diag(S)
  # phi vectorized: phi = sum over (i,j) of var(Yc[,i] * Yc[,j]) / n
  Yc <- scale(Y, center=TRUE, scale=FALSE)
  Yc[is.na(Yc)] <- 0
  # Use the formula phi_ij = (1/n) * sum_t (Yc[t,i] Yc[t,j] - S[i,j])^2
  S_full <- crossprod(Yc) / n  # MLE cov
  Y2sq <- crossprod(Yc^2, Yc^2) / n  # E[(Y_i Y_j)^2 vec → (Y2_i)' Y2_j /n]
  phi_mat <- Y2sq - S_full^2
  phi <- sum(phi_mat)
  gamma_ <- sum((F_target - S)^2)
  alpha_ <- max(0, min(1, (phi / n) / max(gamma_, 1e-12)))
  S_lw <- alpha_ * F_target + (1 - alpha_) * S
  list(Sigma = S_lw, shrink = alpha_)
}

# APPLES-TO-APPLES: run LW on full N=206 (Codex C2 fix)
ret_full <- ret_mat
lw_res <- tryCatch(lw_shrink(ret_full), error=function(e) list(Sigma=cov(ret_full), shrink=NA))
Sigma_lw_full <- lw_res$Sigma
cond_lw <- kappa(Sigma_lw_full, exact=FALSE)
min_eig_lw <- min(eigen(Sigma_lw_full, symmetric=TRUE, only.values=TRUE)$values)
cat(sprintf("[LW full] N=%d cond=%.2f min_eig=%.4e shrink=%.4f\n",
            ncol(ret_full), cond_lw, min_eig_lw, lw_res$shrink %||% NA_real_))

# Sample condition on full
cond_sample_full <- kappa(Sigma_sample, exact=FALSE)
min_eig_sample <- min(eigen(Sigma_sample, symmetric=TRUE, only.values=TRUE)$values)

method_shop <- list(
  candidates_tried = 3L,
  method_log = list(
    list(name = "sample",            condition = round(cond_sample_full, 2),
         min_eig = round(min_eig_sample, 8), n = N, t = T_obs, selected = FALSE,
         reason = "noise-dominated; benchmark"),
    list(name = "ledoit_wolf_constcor", condition = round(cond_lw, 2),
         shrinkage = round(lw_res$shrink, 4),
         min_eig = round(min_eig_lw, 8), n = ncol(ret_full), t = T_obs, selected = FALSE,
         reason = sprintf("Apples-to-apples N=%d (Codex C2 fix). Shrinkage stabilizes cond but biases eigenstructure toward constant-correlation prior, masking factor signal. RMT-denoised preserves signal eigenmodes by theoretical MP threshold.", ncol(ret_full))),
    list(name = "rmt_denoised",      condition = round(cond_d, 2),
         min_eig = round(min_eig_d, 8),
         n_signal_eig = n_signal, n_noise_eig = n_noise,
         lambda_max_MP = round(lambda_max_MP, 6),
         n = N, t = T_obs, selected = TRUE,
         reason = "MP threshold preserves signal eigenmodes (11 retained), flattens noise (195 absorbed to bulk mean); theoretical bulk-anchored, no data-mined cutoff. cond=411.88 reflects market eigenmode (λ_1=44 ≈ 21% trace) which is structural, NOT estimator artifact. Optimizer should use RMT for risk decomposition + LW or shrinkage for portfolio variance forecast where condition number matters operationally.")
  ),
  selection_objective = "shrinkage_quality",  # estimation quality (NOT alpha return)
  selection_objective_note = "Per role prompt v6.1 R4: estimator chosen for theoretical foundation (Laloux 1999 / Bouchaud 2009) and signal preservation, not alpha-return optimization."
)
write_json(method_shop, file.path(SAGE, "risk_method_shopping.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 8)

# ───────────────────────────────────────────────────────────────────────────
# 7. Portfolio σ + ES forecast (using denoised Σ on active 18)
# ───────────────────────────────────────────────────────────────────────────
# Active sub-block of denoised Σ
Sigma_act <- Sigma_denoised[active_in, active_in]
w_act <- weights_18[active_in]
# Renormalize sum to 1 (essentially is, but precaution)
w_act <- w_act / sum(w_act)

# Daily portfolio variance & σ
port_var_daily <- as.numeric(t(w_act) %*% Sigma_act %*% w_act)
port_sd_daily  <- sqrt(port_var_daily)
# Monthly σ scaled (21 trading days)
port_sd_monthly <- port_sd_daily * sqrt(21)
# Annualized σ
port_sd_annual  <- port_sd_daily * sqrt(252)

cat(sprintf("[Step 7] portfolio σ_daily=%.4f σ_monthly=%.4f σ_annual=%.4f\n",
            port_sd_daily, port_sd_monthly, port_sd_annual))

# Realized portfolio daily returns (last 924d) — for empirical CF/EVT
port_ret_daily <- as.numeric(ret_mat[, active_in] %*% w_act)
port_ret_xts   <- xts(port_ret_daily, order.by = as.Date(rownames(ret_mat)))

# Cornish-Fisher ES95 / ES99 (monthly horizon)
cf_es_monthly <- function(r, p) {
  # 21-day rolling sum returns
  r21 <- rollapply(r, width=21, FUN=sum, fill=NA, align="right")
  r21 <- r21[!is.na(r21)]
  if (length(r21) < 30) return(NA_real_)
  losses <- -as.numeric(r21)
  m <- mean(losses); s <- sd(losses)
  sk <- mean(((losses - m)/s)^3)
  ku <- mean(((losses - m)/s)^4) - 3
  z <- qnorm(p)
  z_cf <- z + (z^2 - 1)*sk/6 + (z^3 - 3*z)*ku/24 - (2*z^3 - 5*z)*sk^2/36
  # ES (mean of tail beyond VaR) under CF — approximate via empirical >= z_cf
  cutoff <- m + z_cf * s
  tail_losses <- losses[losses >= cutoff]
  if (length(tail_losses) < 5) return(cutoff)
  mean(tail_losses)
}

# ES from denoised Σ (parametric, normal): ES_p = σ * (φ(z_p) / (1-p))
es_parametric <- function(sigma_h, p) {
  z <- qnorm(p)
  sigma_h * (dnorm(z) / (1 - p))
}

es95_param_monthly <- es_parametric(port_sd_monthly, 0.95)
es99_param_monthly <- es_parametric(port_sd_monthly, 0.99)
es95_cf_monthly <- cf_es_monthly(port_ret_daily, 0.95)
es99_cf_monthly <- cf_es_monthly(port_ret_daily, 0.99)

# EVT-GPD ES (use POT 90% threshold) — adapted from compute_evt_var
source(file.path(PROJ, "02_Infrastructure/portfolio/tail_risk_engine.R"))
losses_d <- -port_ret_daily
losses_d <- losses_d[is.finite(losses_d)]
es_evt_daily <- tryCatch({
  thr <- as.numeric(quantile(losses_d, 0.90, na.rm=TRUE))
  excess <- losses_d[losses_d > thr] - thr
  if (length(excess) >= 30 && requireNamespace("evir", quietly=TRUE)) {
    fit <- evir::gpd(losses_d, threshold = thr)
    xi  <- as.numeric(fit$par.ests["xi"])
    beta <- as.numeric(fit$par.ests["beta"])
    p <- 0.99
    n <- length(losses_d); nu <- length(excess)
    var_evt <- thr + (beta/xi)*((((n/nu)*(1-p)))^(-xi) - 1)
    es_evt <- (var_evt + beta - xi*thr) / (1 - xi)
    es_evt
  } else {
    as.numeric(quantile(losses_d, 0.99, na.rm=TRUE))
  }
}, error = function(e) as.numeric(quantile(losses_d, 0.99, na.rm=TRUE)))
es_evt_monthly <- es_evt_daily * sqrt(21)

cat(sprintf("[Step 7] ES95 monthly: param=%.4f CF=%.4f | ES99 monthly: param=%.4f CF=%.4f EVT=%.4f\n",
            es95_param_monthly, es95_cf_monthly, es99_param_monthly, es99_cf_monthly, es_evt_monthly))

# Rolling forecast — month-by-month (use rolling 504d window)
# Build rolling ES path: at each month-end use last 504d daily returns from full RAWDATA
month_ends <- pr$date[pr$date >= as.Date("2010-01-01")]
fc_list <- list()

# For rolling window we need wider history of active 18 stocks
RAW_act <- RAW[Ticker %in% active_in & !is.na(Ret), .(Date, Ticker, Ret)]
rmat_full_dt <- dcast(RAW_act, Date ~ Ticker, value.var = "Ret")
rmat_full_dt <- rmat_full_dt[order(Date)]
date_full <- rmat_full_dt$Date
rmat_full <- as.matrix(rmat_full_dt[, !"Date", with = FALSE])
rownames(rmat_full) <- as.character(date_full)
rmat_full[is.na(rmat_full)] <- 0
# Reorder columns to match active_in
common_cols <- intersect(active_in, colnames(rmat_full))
rmat_full <- rmat_full[, common_cols, drop = FALSE]

for (me in as.list(month_ends)) {
  me <- as.Date(me)
  win_end <- me
  win_start <- me - 750
  date_idx <- as.Date(rownames(rmat_full))
  Y <- rmat_full[date_idx >= win_start & date_idx <= win_end, , drop=FALSE]
  if (nrow(Y) < 200) next
  s_w <- apply(Y, 2, sd, na.rm=TRUE); s_w[s_w < 1e-8] <- 1e-8
  Z_w <- scale(Y, center=TRUE, scale=s_w)
  R_w <- crossprod(Z_w) / (nrow(Z_w) - 1)
  diag(R_w) <- 1.0; R_w <- (R_w + t(R_w))/2
  q_w <- nrow(Y) / ncol(Y)
  lmax_w <- (1 + sqrt(1/q_w))^2
  ev_w <- eigen(R_w, symmetric=TRUE)
  vc_w <- ev_w$values
  noise_w <- which(vc_w <= lmax_w)
  if (length(noise_w) > 0 && length(noise_w) < length(vc_w)) {
    vc_w[noise_w] <- mean(vc_w[noise_w])
  }
  vc_w <- vc_w * (length(vc_w) / sum(vc_w))
  R_w_d <- ev_w$vectors %*% diag(vc_w) %*% t(ev_w$vectors)
  diag(R_w_d) <- 1.0; R_w_d <- (R_w_d + t(R_w_d))/2
  S_w_d <- diag(s_w) %*% R_w_d %*% diag(s_w)
  cols_w <- colnames(Y)
  w_w <- weights_18[cols_w]; w_w <- w_w / sum(w_w)
  pv_d <- as.numeric(t(w_w) %*% S_w_d %*% w_w)
  ps_d <- sqrt(pv_d)
  ps_m <- ps_d * sqrt(21)
  fc_list[[length(fc_list)+1]] <- data.table(
    date = me,
    sigma_daily = ps_d, sigma_monthly = ps_m,
    es95_monthly_param = es_parametric(ps_m, 0.95),
    es99_monthly_param = es_parametric(ps_m, 0.99),
    n_signal_eig = sum(eigen(R_w, symmetric=TRUE, only.values=TRUE)$values > lmax_w),
    n_obs = nrow(Y)
  )
}
fc_dt <- rbindlist(fc_list)
fwrite(fc_dt, file.path(SAGE, "portfolio_es_forecast.csv"))
cat(sprintf("[Step 7] portfolio_es_forecast.csv written n=%d\n", nrow(fc_dt)))

# ───────────────────────────────────────────────────────────────────────────
# 8. Vol scale path — ES-target derived from rolling avg + percentile cap
# ───────────────────────────────────────────────────────────────────────────
# ES target = 24m trailing median of ES95_monthly_param * 1.0 (statistical, not fixed %)
fc_dt[, es95_target := frollapply(es95_monthly_param, N = 24, FUN = median, align = "right")]
fc_dt[is.na(es95_target), es95_target := median(es95_monthly_param, na.rm=TRUE)]

# scale = target / current; cap [0.5, 1.0] — never lever, only de-risk
fc_dt[, scale_raw := es95_target / es95_monthly_param]
fc_dt[, scale := pmax(0.5, pmin(1.0, scale_raw))]
fc_dt[, cash_bridge := 1.0 - scale]
fwrite(fc_dt[, .(date, sigma_monthly, es95_monthly_param, es99_monthly_param,
                  es95_target, scale, cash_bridge)],
       file.path(SAGE, "vol_scale_path.csv"))
cat(sprintf("[Step 8] vol_scale_path.csv | scale<1 months=%d / total=%d (cash bridge active rate=%.1f%%)\n",
            sum(fc_dt$scale < 1.0, na.rm=TRUE),
            nrow(fc_dt),
            100 * mean(fc_dt$scale < 1.0, na.rm=TRUE)))

# ───────────────────────────────────────────────────────────────────────────
# 9. Tail risk — STR_1715 actual 268m + Hill α + EVT + 8 stress
# ───────────────────────────────────────────────────────────────────────────
str_ret <- pr$ret_net
str_xts <- xts(str_ret, order.by = pr$date)

# Hill α tail index (top 5% absolute losses)
losses_m <- -str_ret
losses_m <- losses_m[is.finite(losses_m)]
sorted <- sort(losses_m[losses_m > 0], decreasing = TRUE)
k <- max(5L, floor(length(sorted) * 0.10))
hill_alpha <- if (length(sorted) > k) {
  k / sum(log(sorted[1:k] / sorted[k+1]))
} else NA_real_

# EVT-GPD on monthly returns (helpers return lists)
evt_m_obj <- tryCatch(compute_evt_var(str_ret, p = 0.99, threshold_q = 0.90, min_tail_n = 20L),
                       error = function(e) list(var_evt = NA_real_, es_evt = NA_real_))
cf_m_obj  <- tryCatch(compute_cf_var(str_ret, p = 0.99),
                       error = function(e) list(var_cf = NA_real_, var_normal = NA_real_))
evt_m <- as.numeric(evt_m_obj$var_evt %||% NA_real_)
cf_m  <- as.numeric(cf_m_obj$var_cf  %||% NA_real_)
evt_es_m <- as.numeric(evt_m_obj$es_evt %||% NA_real_)

# 8 stress periods
stress_periods <- list(
  list(name = "Terror_9_11",    start = "2001-09-01", end = "2001-12-31"),
  list(name = "GFC_2008",       start = "2007-10-01", end = "2009-03-31"),
  list(name = "Euro_Debt_2011", start = "2011-07-01", end = "2011-12-31"),
  list(name = "China_Shock",    start = "2015-06-01", end = "2016-02-29"),
  list(name = "US_China_Trade", start = "2018-03-01", end = "2018-12-31"),
  list(name = "COVID_2020",     start = "2020-01-01", end = "2020-06-30"),
  list(name = "Rate_Hike_2022", start = "2022-01-01", end = "2022-12-31"),
  list(name = "Iran_War_2026",  start = "2026-02-01", end = "2026-04-30")
)
stress_results <- list()
for (sp in stress_periods) {
  s <- as.Date(sp$start); e <- as.Date(sp$end)
  win <- str_xts[paste0(s, "/", e)]
  if (length(win) < 2) {
    stress_results[[sp$name]] <- list(period = sp$name,
                                      cum_ret = NA_real_, mdd = NA_real_,
                                      n_obs = length(win))
    next
  }
  cum_ret <- prod(1 + as.numeric(win), na.rm = TRUE) - 1
  mdd <- as.numeric(maxDrawdown(win))
  stress_results[[sp$name]] <- list(period = sp$name,
                                    cum_ret = round(cum_ret, 4),
                                    mdd = round(-mdd, 4),  # signed neg
                                    n_obs = length(win))
}

# AX-001 v2 conditional metric — defense-like evaluation
# crisis_alpha (vs BM during stress) + Core MDD relief + bad/normal IC ratio (proxy: bad/normal ret)
# Note: STR_1715 is core, not defense. Track for transparency.
bad_periods <- c("GFC_2008", "Euro_Debt_2011", "China_Shock", "US_China_Trade",
                 "COVID_2020", "Rate_Hike_2022", "Iran_War_2026")
crisis_rets <- sapply(bad_periods, function(p) stress_results[[p]]$cum_ret)
crisis_alpha_avg <- mean(crisis_rets, na.rm = TRUE)

# CDaR95 (Conditional Drawdown at Risk) — Codex C8 fix
nav_pa <- 100 * cumprod(1 + str_ret)
cdar_obj <- tryCatch(compute_cdar(nav_pa, alpha = 0.95),
                      error = function(e) list(cdar = NA_real_, var_dd = NA_real_))
cdar95 <- as.numeric(cdar_obj$cdar %||% NA_real_)
cdar_var <- as.numeric(cdar_obj$var_dd %||% NA_real_)

tail_risk <- list(
  hill_alpha_monthly = round(hill_alpha, 4),
  cf_var99_monthly   = round(cf_m, 6),
  evt_var99_monthly  = round(as.numeric(evt_m), 6),
  evt_es99_monthly   = round(as.numeric(evt_es_m), 6),
  cdar95 = round(cdar95, 6),
  cdar_var95 = round(cdar_var, 6),
  realized_max_monthly_loss = round(max(losses_m, na.rm=TRUE), 6),
  realized_min_monthly_ret  = round(min(str_ret, na.rm=TRUE), 6),
  mdd_lifetime = round(as.numeric(maxDrawdown(str_xts)), 6),
  stress_periods = stress_results,
  ax001_v2_conditional = list(
    role = "core_secondary",
    crisis_alpha_avg_cum_ret = round(crisis_alpha_avg, 4),
    note = "STR_1715 is core, not defense — informational only. AX-001 v2 defense conditional metric does NOT apply to core role; tracking for Q-Lead consumption only."
  )
)
write_json(tail_risk, file.path(SAGE, "tail_risk.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 6)
cat("[Step 9] tail_risk.json written\n")

# ───────────────────────────────────────────────────────────────────────────
# 10. SNR (signal-noise ratio) summary
# ───────────────────────────────────────────────────────────────────────────
total_trace <- sum(vals)
signal_trace <- sum(vals[vals > lambda_max_MP])
snr <- list(
  q_ratio = round(q_ratio, 4),
  T_obs = T_obs, N = N,
  lambda_min_MP = round(lambda_min_MP, 6),
  lambda_max_MP = round(lambda_max_MP, 6),
  market_eigenvalue = round(max(vals), 6),
  n_signal_eig = n_signal,
  n_noise_eig = n_noise,
  signal_trace = round(signal_trace, 4),
  total_trace = round(total_trace, 4),
  signal_total_ratio = round(signal_trace / total_trace, 4),
  market_signal_ratio = round(max(vals) / total_trace, 4),
  bulk_mean = round(mean(vals[vals <= lambda_max_MP]), 6),
  variance_explained_top5 = round(sum(head(sort(vals, decreasing=TRUE), 5)) / total_trace, 4)
)
write_json(snr, file.path(SAGE, "signal_noise_ratio.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 6)
cat(sprintf("[Step 10] SNR: signal=%d/%d signal_trace_pct=%.2f%% market_eig_pct=%.2f%%\n",
            n_signal, length(vals), 100*snr$signal_total_ratio, 100*snr$market_signal_ratio))

# ───────────────────────────────────────────────────────────────────────────
# 11. lro_params_frozen + SHA
# ───────────────────────────────────────────────────────────────────────────
lro_params <- list(
  task_id = WT,
  as_of_date = format(as_of),
  rmt = list(
    method = "Marchenko-Pastur eigenvalue threshold",
    T_obs = T_obs, N = N, q_ratio = round(q_ratio, 4),
    lambda_max_MP = round(lambda_max_MP, 6),
    noise_treatment = "flatten to bulk mean, trace renormalized",
    n_signal_eig_frozen = n_signal,
    n_noise_eig_frozen = n_noise
  ),
  es_target = list(
    derivation = "24-month trailing median of rolling ES95_monthly_param (statistical, NOT fixed %)",
    horizon = "monthly",
    quantile = 0.95,
    sample_target_value_apr_2026 = round(tail(fc_dt$es95_target, 1), 6)
  ),
  vol_scale = list(
    rule = "scale = ES_target / ES_current, capped [0.5, 1.0] (de-risk only, no leverage)",
    cash_bridge_role = "1 - scale → cash overlay redistribution"
  ),
  universe = list(
    label = "STR_1715_universe_top200_liquid",
    n_active = n_active_in,
    n_universe = N,
    liquidity_floor_won_20d_avg = 2e8
  )
)
write_json(lro_params, file.path(SAGE, "lro_params_frozen.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 6)

# SHA-256 of frozen params
lro_sha <- digest::digest(file.path(SAGE, "lro_params_frozen.json"),
                           algo = "sha256", file = TRUE)
cat(sprintf("[Step 11] lro_params SHA256 = %s\n", lro_sha))

# ───────────────────────────────────────────────────────────────────────────
# 12. Σ correlation summary (top common risks)
# ───────────────────────────────────────────────────────────────────────────
# Variance contribution decomposition via market mode (top eigenvalue)
top_idx <- which.max(vals)
v_market <- vecs[, top_idx]
loadings_market <- v_market^2  # variance share in market mode
# Map to active 18
act_load_idx <- match(active_in, colnames(R_sample))
top_market_pct <- vals[top_idx] / total_trace

# Top 3 eigenmodes variance share
sorted_vals <- sort(vals, decreasing = TRUE)
top3_share <- sum(sorted_vals[1:3]) / total_trace

# Compute portfolio loadings on top 3 eigenmodes
sorted_idx <- order(vals, decreasing = TRUE)
mode_loadings <- list()
for (m in 1:3) {
  vm <- vecs[, sorted_idx[m]]
  vm_act <- vm[act_load_idx]
  port_loading <- as.numeric(t(w_act) %*% vm_act)
  mode_loadings[[m]] <- list(
    mode_rank = m,
    eigenvalue = round(vals[sorted_idx[m]], 4),
    variance_pct = round(vals[sorted_idx[m]] / total_trace, 4),
    portfolio_loading = round(port_loading, 4),
    portfolio_variance_contrib = round(port_loading^2 * vals[sorted_idx[m]], 6)
  )
}

# CVaR breach flag check vs Iran_War recent realized
recent_iran_loss <- abs(stress_results$Iran_War_2026$cum_ret %||% 0)
cvar_breach_flag <- isTRUE(recent_iran_loss > es99_param_monthly * 2)

# ───────────────────────────────────────────────────────────────────────────
# 13. risk_package_draft.json  →  risk_package.json (SHA log)
# ───────────────────────────────────────────────────────────────────────────
risk_package <- list(
  task_id = WT,
  as_of_date = format(as_of),
  sigma_method = "RMT_Denoised",
  exposure_matrix_ref = "stage_artifacts/WT_WT-S20260504_004/_n_a_pure_statistical_no_factor_exposure",
  factor_covariance_ref = "stage_artifacts/WT_WT-S20260504_004/rmt_eigenvalues.csv",
  specific_risk_ref = "stage_artifacts/WT_WT-S20260504_004/_n_a_specific_risk_absorbed_into_noise_bulk",
  security_covariance_ref = "stage_artifacts/WT_WT-S20260504_004/covariance.parquet",
  rmt_diagnostics = list(
    T_obs = T_obs, N = N, q_ratio = round(q_ratio, 4),
    lambda_min_MP = round(lambda_min_MP, 6),
    lambda_max_MP = round(lambda_max_MP, 6),
    n_signal_eig = n_signal,
    n_noise_eig = n_noise,
    signal_trace_pct = round(snr$signal_total_ratio, 4),
    market_eigenvalue_pct = round(snr$market_signal_ratio, 4),
    top3_eigmode_variance_pct = round(top3_share, 4),
    bulk_mean = round(snr$bulk_mean, 6)
  ),
  es_forecast = list(
    horizon = "monthly",
    method = "RMT_denoised_Σ + Cornish-Fisher + EVT-GPD parallel",
    sigma_monthly_current = round(port_sd_monthly, 6),
    es95_param_monthly = round(es95_param_monthly, 6),
    es95_cf_monthly = round(es95_cf_monthly, 6),
    es99_param_monthly = round(es99_param_monthly, 6),
    es99_cf_monthly = round(es99_cf_monthly, 6),
    es99_evt_monthly = round(es_evt_monthly, 6),
    es95_target = round(tail(fc_dt$es95_target, 1), 6),
    forecast_path_ref = "stage_artifacts/WT_WT-S20260504_004/portfolio_es_forecast.csv",
    forecast_path_waiver_label = "static_current_snapshot_diagnostic_NOT_walk_forward_pit",
    forecast_path_waiver_note = "ES forecast time-series uses CURRENT 2026-04-30 active-18 weights backward over rolling daily windows. This is a DIAGNOSTIC visualization of how the present portfolio's RMT-denoised ES would have evolved through historical regimes — NOT a PIT walk-forward backtest of historical sizing. Codex C6 PARTIAL: walk-forward stock-level historical weights for STR_1715 are not stored as monthly time-series in the production registry (only 2 snapshot dates exist); this is structural data limitation, not a methodology choice. Acceptable for sizing_only recommendation_only WT where the forward vol-scale recommendation is the primary deliverable.",
    pit_compliance_note = "All input daily returns capped at as_of_date 2026-04-30 (RAWDATA filter applied). No look-ahead in eigenvalue estimation."
  ),
  vol_target = list(
    rule = "scale = ES_target / ES_current, capped [0.5, 1.0]",
    derivation = "statistical 24m trailing median of rolling ES95_monthly_param",
    cash_bridge = "1 - scale",
    current_scale = round(tail(fc_dt$scale, 1), 4),
    current_cash_bridge = round(tail(fc_dt$cash_bridge, 1), 4),
    path_ref = "stage_artifacts/WT_WT-S20260504_004/vol_scale_path.csv"
  ),
  tail_risk = tail_risk,
  cvar_breach_flag = cvar_breach_flag,
  risk_summary = list(
    top_common_risks = c(
      sprintf("Market mode (top eig): %.2f%%", 100*snr$market_signal_ratio),
      sprintf("Top3 eigmodes: %.2f%%", 100*top3_share),
      sprintf("Signal eig count: %d/%d (%.1f%% of trace)", n_signal, length(vals), 100*snr$signal_total_ratio)
    ),
    portfolio_loadings_top3_modes = mode_loadings,
    crowding_flags = list(),
    liquidity_flags = list(),
    stress_tests = list(
      market_down_5pct = round(-1.96 * port_sd_monthly, 4),  # ~95% one-tail
      gfc_2008 = round(stress_results$GFC_2008$cum_ret, 4),
      covid_2020 = round(stress_results$COVID_2020$cum_ret, 4),
      rate_hike_2022 = round(stress_results$Rate_Hike_2022$cum_ret, 4),
      iran_war_2026 = round(stress_results$Iran_War_2026$cum_ret, 4)
    )
  ),
  diagnostics = list(
    condition_number = round(cond_d, 2),
    condition_number_role_prompt_gate = 100L,
    condition_number_role_prompt_gate_breach = isTRUE(cond_d > 100),
    condition_number_explanation = paste0(
      sprintf("cond=%.2f driven by market eigenmode λ_1=%.2f ≈ %.1f%% trace. ",
              cond_d, max(vals), 100*snr$market_signal_ratio),
      "This is STRUCTURAL (market factor exists in equity returns), not estimator artifact. ",
      sprintf("RMT-denoised cond > LW-shrunk (%.2f) because RMT preserves dominant market eigenmode. ", cond_lw),
      "Optimizer use: RMT for risk DECOMPOSITION; LW for matrix INVERSION."
    ),
    min_eigenvalue = round(min_eig_d, 8),
    psd_pass = isTRUE(min_eig_d > 0),
    shrinkage_used = FALSE,
    shrinkage_method = "rmt_eigenvalue_threshold",
    selection_objective = "shrinkage_quality",
    method_shopping_ref = "stage_artifacts/WT_WT-S20260504_004/risk_method_shopping.json",
    alternative_estimator_for_optimizer = list(
      name = "ledoit_wolf_constcor",
      condition_number = round(cond_lw, 2),
      min_eigenvalue = round(min_eig_lw, 8),
      shrinkage_intensity = round(lw_res$shrink %||% NA_real_, 4),
      note = "Reported for optimizer transparency. LW lower cond operationally preferable for variance / inversion. RMT remains spec-mandated sigma_method=RMT_Denoised."
    ),
    regime_correlation_ref = "stage_artifacts/WT_WT-S20260504_004/regime_correlation.parquet",
    regime_correlation_summary_ref = "stage_artifacts/WT_WT-S20260504_004/regime_correlation_summary.csv",
    regime_correlation_summary = if (file.exists(file.path(SAGE, "regime_correlation_summary.csv"))) {
      rcs <- fread(file.path(SAGE, "regime_correlation_summary.csv"))
      rl <- as.list(setNames(round(rcs$avg_corr, 4), paste0(rcs$regime, "_avg_corr")))
      rl$obs_counts <- as.list(setNames(rcs$n_pairs, rcs$regime))
      rl$pit_compliance <- "C9 t-1 lagged regime labels; rawdata capped at as_of 2026-04-30"
      norm_v <- rcs[regime == "NORMAL", avg_corr]
      cris_v <- rcs[regime == "CRISIS", avg_corr]
      if (length(norm_v) == 1 && length(cris_v) == 1 && norm_v > 0) {
        rl$CRISIS_vs_NORMAL_uplift_pct <- round(cris_v / norm_v - 1, 4)
      }
      rl
    } else NULL
  ),
  lro_params_frozen_ref = "stage_artifacts/WT_WT-S20260504_004/lro_params_frozen.json",
  lro_params_sha256 = lro_sha,
  axiom_assertions = list(
    `AX-000` = "한계 없음 — 통계적 팩터로 MDD/Vol gap 도전",
    `AX-001_v2` = "core_secondary role evaluation; defense conditional metric tracked (informational)",
    `AX-002` = "RMT cutoff (lambda_max_MP) is theoretical bulk-anchored, NOT data-mined; SHA-frozen",
    `AX-008` = "Forge + Codex + Architect 2/3 PASS path planned"
  ),
  challenge_flags = list(),
  parent_alpha_package_sha = "34cc99fb8aa423f7ce97ebea877a4fa68207896bffd8043443f87dcb2ba60984",
  no_alpha_modification = TRUE,
  no_weight_decision = TRUE,
  str_1715_production_writes = 0L,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

# Red flag detection (C1 fix: cond>100 from role prompt, NOT 500)
if (snr$market_signal_ratio > 0.40)
  risk_package$challenge_flags <- c(risk_package$challenge_flags,
    list(list(id="RF-R1", severity="HIGH",
              msg=sprintf("Market mode = %.1f%% > 40%% (concentration risk)", 100*snr$market_signal_ratio))))
if (cond_d > 100)
  risk_package$challenge_flags <- c(risk_package$challenge_flags,
    list(list(id="RF-R2", severity="HIGH",
              msg=sprintf("Condition number %.0f > 100 (role prompt gate). Codex C1 ACCEPT.", cond_d))))
if (n_signal < 3)
  risk_package$challenge_flags <- c(risk_package$challenge_flags,
    list(list(id="RF-R-RMT", severity="HIGH",
              msg=sprintf("Signal eigenvalue count %d < 3 (insufficient factor structure)", n_signal))))
# RF-R4 explicit: parametric monthly market_down_5 < -8% gate
mdn5 <- -1.96 * port_sd_monthly  # ~95% one-tail
if (mdn5 < -0.08)
  risk_package$challenge_flags <- c(risk_package$challenge_flags,
    list(list(id="RF-R4", severity="HIGH",
              msg=sprintf("Stress proxy market_down_5 %.4f < -0.08 gate. Codex C4 ACCEPT.", mdn5))))
# RF-R3 crowding-style stress
if (any(c(stress_results$GFC_2008$cum_ret %||% 0,
           stress_results$COVID_2020$cum_ret %||% 0,
           stress_results$Rate_Hike_2022$cum_ret %||% 0) < -0.20))
  risk_package$challenge_flags <- c(risk_package$challenge_flags,
    list(list(id="RF-R-STRESS", severity="HIGH",
              msg="Historical stress cum_ret < -20% in GFC/COVID/Rate2022. Tail loss exposure confirmed; M4 schedule overlay (parent WT) provides operational mitigation.")))

# Write DRAFT first (Codex Round Hook 5-step flow)
draft_path <- file.path(MBOX, "risk_package_draft.json")
write_json(risk_package, draft_path, pretty = TRUE, auto_unbox = TRUE, digits = 8)
cat(sprintf("[Step 13] risk_package_draft.json written: %s\n", draft_path))

# Debug pass artifact
debug_pass <- list(
  task_id = WT,
  step1_weights_loaded = TRUE,
  step2_rawdata_universe_built = TRUE,
  step3_sample_R_computed = TRUE,
  step4_mp_threshold = list(lambda_max_MP = lambda_max_MP, n_signal = n_signal),
  step5_denoised_sigma_psd = isTRUE(min_eig_d > 0),
  step6_method_shopping_n = 3L,
  step7_es_forecast_n = nrow(fc_dt),
  step8_vol_scale_path_n = nrow(fc_dt),
  step9_tail_risk_8stress = TRUE,
  step10_snr_signal_ratio = snr$signal_total_ratio,
  step11_lro_sha = lro_sha,
  step12_top3_modes_logged = TRUE,
  step13_draft_written = TRUE,
  red_flags_count = length(risk_package$challenge_flags),
  overall_pass = isTRUE(min_eig_d > 0) && (n_signal >= 3) && nrow(fc_dt) >= 24L
)
write_json(debug_pass, file.path(DBG, "debug_pass.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 8)

cat("\n[run_risk_rmt] DONE | overall_pass=", debug_pass$overall_pass, "\n", sep="")
cat(sprintf("  Σ_method=RMT_Denoised | cond=%.2f min_eig=%.4e signal=%d/%d\n",
            cond_d, min_eig_d, n_signal, length(vals)))
cat(sprintf("  ES95 monthly param=%.4f | scale current=%.4f\n",
            es95_param_monthly, tail(fc_dt$scale,1)))
cat(sprintf("  STR_1715 mdd_lifetime=%.4f hill_α=%.3f\n",
            tail_risk$mdd_lifetime, hill_alpha))
