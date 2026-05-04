#==============================================================================
# WT-S20260504_002 — Step 2: Fit Univariate GARCH(1,1) Gaussian per stock
# + DCC(1,1) joint (Engle 2002 two-step QML)
#
# Inputs : returns_daily_18.parquet (T=928, K=18)
# Outputs: dcc_params.json + covariance.parquet (LONG) + dcc_diagnostics.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(rugarch); library(rmgarch)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-S20260504_002"
SA <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID))
DIR_DBG <- file.path(SA, "_debug")

cat("[Step 2] DCC-GARCH fit — START\n")

# ─── Load returns ─────────────────────────────────────────────────────────
ret_dt <- as.data.table(read_parquet(file.path(SA, "returns_daily_18.parquet")))
stk_cols <- setdiff(names(ret_dt), "Date")
stopifnot(length(stk_cols) == 18L)
ret_mat <- as.matrix(ret_dt[, ..stk_cols])
rownames(ret_mat) <- as.character(ret_dt$Date)
T <- nrow(ret_mat); K <- ncol(ret_mat)
cat(sprintf("[Step 2] T=%d, K=%d\n", T, K))

# ─── Univariate GARCH(1,1) Gaussian spec (per stock) ──────────────────────
# Spec exactly as user directed: GARCH(1,1) Gaussian, min_obs 252
stopifnot(T >= 252L)

uspec <- ugarchspec(
  variance.model = list(model = "sGARCH", garchOrder = c(1L, 1L)),
  mean.model     = list(armaOrder = c(0L, 0L), include.mean = TRUE),
  distribution.model = "norm"  # Gaussian per user spec
)
multi_spec <- multispec(replicate(K, uspec))

# ─── Stage 1: univariate fit per stock (for diagnostics + fallback) ──────
uni_fits <- vector("list", K)
uni_params <- vector("list", K)
uni_diag <- data.table(stock = stk_cols, omega = NA_real_, alpha = NA_real_,
                       beta = NA_real_, mu = NA_real_, persistence = NA_real_,
                       LL = NA_real_, AIC = NA_real_, BIC = NA_real_,
                       converged = FALSE, half_life_days = NA_real_)
for (i in seq_len(K)) {
  fit_i <- tryCatch(
    ugarchfit(spec = uspec, data = ret_mat[, i], solver = "hybrid"),
    error = function(e) NULL
  )
  uni_fits[[i]] <- fit_i
  if (!is.null(fit_i) && fit_i@fit$convergence == 0) {
    cf <- coef(fit_i)
    pers <- as.numeric(cf["alpha1"]) + as.numeric(cf["beta1"])
    hl <- if (pers < 1 && pers > 0) log(0.5)/log(pers) else NA_real_
    uni_diag[i, `:=`(
      omega = as.numeric(cf["omega"]),
      alpha = as.numeric(cf["alpha1"]),
      beta = as.numeric(cf["beta1"]),
      mu = as.numeric(cf["mu"]),
      persistence = pers,
      LL = as.numeric(likelihood(fit_i)),
      AIC = as.numeric(infocriteria(fit_i)["Akaike", 1]),
      BIC = as.numeric(infocriteria(fit_i)["Bayes", 1]),
      converged = TRUE,
      half_life_days = hl
    )]
    uni_params[[i]] <- list(stock = stk_cols[i],
                            omega = as.numeric(cf["omega"]),
                            alpha = as.numeric(cf["alpha1"]),
                            beta = as.numeric(cf["beta1"]),
                            mu = as.numeric(cf["mu"]),
                            persistence = pers,
                            LL = as.numeric(likelihood(fit_i)))
  } else {
    uni_params[[i]] <- list(stock = stk_cols[i],
                            converged = FALSE,
                            note = "GARCH did not converge — DCC may still recover via two-step")
  }
}

n_conv <- sum(uni_diag$converged)
cat(sprintf("[Step 2] Univariate GARCH converged: %d/%d\n", n_conv, K))
cat(sprintf("[Step 2] Univariate persistence range: %.4f to %.4f\n",
            min(uni_diag$persistence, na.rm=TRUE),
            max(uni_diag$persistence, na.rm=TRUE)))

# ─── Stage 2: DCC(1,1) joint two-step QML (Engle 2002) ────────────────────
dcc_spec <- dccspec(uspec = multi_spec, dccOrder = c(1L, 1L),
                    distribution = "mvnorm")
cat("[Step 2] DCC fit running...\n")
dcc_fit <- tryCatch(
  dccfit(dcc_spec, data = ret_mat, fit.control = list(eval.se = FALSE)),
  error = function(e) {
    cat(sprintf("[Step 2] dccfit error: %s\n", conditionMessage(e)))
    NULL
  }
)

if (is.null(dcc_fit)) {
  stop("[Step 2] DCC fit FAILED — abort. Statistical fallback to EWMA spec required.")
}

# DCC params extraction
dcc_coef <- coef(dcc_fit)
# In rmgarch, last 2 params named "[Joint]dcca1" and "[Joint]dccb1"
dcc_a <- as.numeric(dcc_coef[grep("dcca", names(dcc_coef))])
dcc_b <- as.numeric(dcc_coef[grep("dccb", names(dcc_coef))])
dcc_persistence <- dcc_a + dcc_b
cat(sprintf("[Step 2] DCC parameters: alpha=%.4f, beta=%.4f, alpha+beta=%.4f\n",
            dcc_a, dcc_b, dcc_persistence))

# Stationarity hard constraint
dcc_stationary <- dcc_persistence < 1.0
if (!dcc_stationary) {
  warning("[Step 2] DCC NON-STATIONARY (alpha+beta >= 1). EWMA fallback may be needed.")
}

# ─── Engle-Sheppard test for DCC vs constant correlation (LRT proxy) ─────
# Use likelihood ratio against multivariate normal with constant cov
# (rmgarch does not expose Engle-Sheppard directly; we approximate via LR)
ll_dcc <- as.numeric(likelihood(dcc_fit))
# Engle-Sheppard (2001) test for constant-conditional-correlation null:
# Under H0 (CCC), standardized residual cross-products z_i,t × z_j,t should be iid.
# Box-Pierce portmanteau test on each pair's cross-product series
# (lag=5), Bonferroni-aggregated.
raw_res <- as.matrix(residuals(dcc_fit))
sigma_uni <- as.matrix(sigma(dcc_fit))
std_res <- raw_res / sigma_uni

n_pairs <- K * (K - 1L) / 2L
LB_stats <- numeric(n_pairs)
LB_pvals <- numeric(n_pairs)
idx <- 0L
for (i in seq_len(K - 1L)) {
  for (j in seq.int(i + 1L, K)) {
    idx <- idx + 1L
    cross <- std_res[, i] * std_res[, j]
    bt <- tryCatch(Box.test(cross, lag = 5L, type = "Box-Pierce"),
                   error = function(e) NULL)
    if (!is.null(bt)) {
      LB_stats[idx] <- as.numeric(bt$statistic)
      LB_pvals[idx] <- as.numeric(bt$p.value)
    } else {
      LB_pvals[idx] <- NA_real_
    }
  }
}
pct_pairs_sig <- mean(LB_pvals < 0.05, na.rm = TRUE)
median_LB <- median(LB_stats, na.rm = TRUE)
es_decision <- if (pct_pairs_sig > 0.20) "DCC_preferred_over_CCC" else "CCC_acceptable"
cat(sprintf("[Step 2] Engle-Sheppard portmanteau (cross-products, lag=5): %.1f%% pairs reject CCC at 5%%, median Q=%.2f -> %s\n",
            pct_pairs_sig * 100, median_LB, es_decision))

# ─── Time-varying covariance Σ_t ──────────────────────────────────────────
H_array <- rcov(dcc_fit)  # K x K x T
stopifnot(dim(H_array)[3] == T)

# LONG format Σ_t (Date, Ticker_i, Ticker_j, Cov_ij) — upper triangle (incl diag)
cat("[Step 2] Building Σ_t LONG format...\n")
build_long_cov <- function(H_array, dates, stk_cols) {
  T <- dim(H_array)[3]; K <- length(stk_cols)
  pairs <- expand.grid(i = seq_len(K), j = seq_len(K))
  pairs <- pairs[pairs$i <= pairs$j, ]
  rows_per_t <- nrow(pairs)
  out_rows <- T * rows_per_t
  date_vec <- rep(dates, each = rows_per_t)
  i_vec <- rep(pairs$i, T)
  j_vec <- rep(pairs$j, T)
  cov_vec <- numeric(out_rows)
  for (t in seq_len(T)) {
    H_t <- H_array[, , t]
    cov_vec[((t - 1) * rows_per_t + 1):(t * rows_per_t)] <- H_t[as.matrix(pairs)]
  }
  data.table(
    Date = as.Date(date_vec),
    Ticker_i = stk_cols[i_vec],
    Ticker_j = stk_cols[j_vec],
    Cov_ij = cov_vec
  )
}
cov_long <- build_long_cov(H_array, ret_dt$Date, stk_cols)
cat(sprintf("[Step 2] Σ_t LONG rows: %d (%d dates × %d unique pairs)\n",
            nrow(cov_long), T, K * (K + 1) / 2))

# Min-eig PSD check (each Σ_t must be PSD)
psd_min_eig <- numeric(T)
for (t in seq_len(T)) {
  ev <- eigen(H_array[, , t], only.values = TRUE, symmetric = TRUE)$values
  psd_min_eig[t] <- min(ev)
}
psd_pass <- all(psd_min_eig > -1e-10)
cat(sprintf("[Step 2] PSD check: min_eig range %.6e to %.6e | PSD_pass=%s\n",
            min(psd_min_eig), max(psd_min_eig), psd_pass))

# ─── Save ─────────────────────────────────────────────────────────────────
write_parquet(cov_long, file.path(SA, "covariance.parquet"))

# Conditional volatility per stock per day (sqrt of diag(Σ_t))
cond_vol_dt <- as.data.table(sigma(dcc_fit))
cond_vol_dt[, Date := ret_dt$Date]
setcolorder(cond_vol_dt, "Date")
write_parquet(cond_vol_dt, file.path(SA, "conditional_vol_daily.parquet"))

# Save DCC fit object for downstream forecasting
saveRDS(dcc_fit, file.path(SA, "dcc_fit_object.rds"))

# DCC params + univariate diag
write_json(uni_diag, file.path(SA, "univariate_garch_diag.json"),
           pretty = TRUE, auto_unbox = FALSE)

dcc_params <- list(
  spec = list(
    univariate = "GARCH(1,1) Gaussian sGARCH ARMA(0,0)+const",
    multivariate = "DCC(1,1) two-step QML",
    distribution = "mvnorm"
  ),
  univariate_garch_per_stock = lapply(uni_params, function(x) x),
  dcc_alpha = dcc_a,
  dcc_beta = dcc_b,
  dcc_alpha_plus_beta = dcc_persistence,
  dcc_stationary = dcc_stationary,
  T = T, K = K,
  fit_date_first = as.character(min(ret_dt$Date)),
  fit_date_last  = as.character(max(ret_dt$Date)),
  estimation_method = "two_step_QML_Engle_2002",
  software = sprintf("rmgarch %s, rugarch %s",
                    as.character(packageVersion("rmgarch")),
                    as.character(packageVersion("rugarch")))
)
write_json(dcc_params, file.path(SA, "dcc_params.json"),
           pretty = TRUE, auto_unbox = TRUE)

dcc_diag <- list(
  log_lik = as.numeric(ll_dcc),
  AIC = as.numeric(-2 * ll_dcc + 2 * length(dcc_coef)),
  BIC = as.numeric(-2 * ll_dcc + log(T) * length(dcc_coef)),
  engle_sheppard_test = list(
    method = "Box-Pierce portmanteau on z_i × z_j cross-products, lag=5",
    n_pairs = n_pairs,
    pct_pairs_reject_CCC_at_5pct = as.numeric(pct_pairs_sig),
    median_Q_stat = as.numeric(median_LB),
    decision = es_decision,
    interpretation = "If >20% of pairs reject CCC, dynamic correlation is preferred (DCC justified)."
  ),
  dcc_alpha_plus_beta = dcc_persistence,
  stationarity_pass = dcc_stationary,
  psd_pass = psd_pass,
  psd_min_eig_global_min = as.numeric(min(psd_min_eig)),
  psd_min_eig_global_max = as.numeric(max(psd_min_eig)),
  univariate_convergence = sprintf("%d/%d", n_conv, K),
  fallback_strategy = "EWMA(lambda=0.94) if alpha+beta >= 1 OR PSD violation"
)
write_json(dcc_diag, file.path(SA, "dcc_diagnostics.json"),
           pretty = TRUE, auto_unbox = TRUE)

# Step debug
write_json(list(
  step = "02_fit_dcc_garch",
  status = if (dcc_stationary && psd_pass && n_conv >= 17L) "PASS" else "WARN",
  T = T, K = K,
  dcc_alpha = dcc_a, dcc_beta = dcc_b, dcc_persistence = dcc_persistence,
  dcc_stationary = dcc_stationary,
  psd_pass = psd_pass,
  univariate_converged = n_conv,
  log_lik = as.numeric(ll_dcc),
  notes = "Daily 18-stock DCC. T=928 ample for both univariate GARCH(1,1) and DCC(1,1). Newest stock A403870 listed 2022-07-18 sets common-date floor."
), file.path(DIR_DBG, "step02_dcc_fit.json"),
   pretty = TRUE, auto_unbox = TRUE)

cat("[Step 2] DONE\n")
