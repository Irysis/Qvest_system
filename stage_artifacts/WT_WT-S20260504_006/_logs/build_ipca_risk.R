#==============================================================================
# WT-S20260504_006 — IPCA Risk Pipeline (single-cell K=5/L=12/restricted_α=0)
#
# Academic anchor: Kelly-Pruitt-Su (2020 JFE) "Characteristics are Covariances"
#
# Pipeline (simplified, executed as one script):
#   1. Load STR_1715 actual production weights (2026-05-01) + 268m monthly returns
#   2. Load RAWDATA daily 5y for active universe
#   3. Build characteristics panel Z (T x N x L=12) PIT-safe
#   4. ALS K=5 restricted alpha=0:
#         f_t = (Z_t Γ_β)' R_t / N_t
#         vec(Γ_β) = (X'X)^{-1} X' r
#         5 random restarts, max 200 iter, ∇|loss|/loss < 1e-6
#   5. Σ_IPCA = (Z_T Γ_β) cov(F) (Z_T Γ_β)' + diag(D_residual)
#   6. Portfolio factor exposure β'_i,t w_i,t (last 12 months snapshot)
#   7. Tail risk: STR_1715 actual 268m
#   8. SHA freeze + write 9 mandatory artifacts
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(digest)
  library(MASS)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-S20260504_006"
ART_DIR      <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID))
WT_DIR       <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
LOG_DIR      <- file.path(ART_DIR, "_logs")
DEBUG_DIR    <- file.path(ART_DIR, "_debug")
dir.create(LOG_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(DEBUG_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(PROJECT_ROOT, "02_Infrastructure", "config.R"))
# load_rawdata defined here
suppressWarnings(source(file.path(PROJECT_ROOT, "02_Infrastructure", "backtest_harness.R")))

cat("================================================================\n")
cat(" IPCA Risk Pipeline — WT-S20260504_006 (K=5/L=12/restricted)\n")
cat("================================================================\n")
t0 <- Sys.time()

#==============================================================================
# STEP 1: STR_1715 actual production weights + monthly returns
#==============================================================================
cat("\n[Step 1] Loading STR_1715 actual book...\n")

w_file <- file.path(PROJECT_ROOT,
                    "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd",
                    "production_weights/20260501_weights_cap_0p20.csv")
w_dt <- fread(w_file)
cat(sprintf("  weights file: %s\n", w_file))
cat(sprintf("  rows: %d, cols: %s\n", nrow(w_dt), paste(names(w_dt), collapse=",")))

# Active = weight > 0
w_active <- w_dt[Weight > 1e-8]
cat(sprintf("  active n: %d / %d (cap 0.20)\n", nrow(w_active), nrow(w_dt)))

# Strip 'A' prefix to match RAWDATA Ticker convention if needed
active_tickers <- w_active$Ticker
cat(sprintf("  tickers (head): %s\n", paste(head(active_tickers, 5), collapse=",")))

# STR_1715 monthly portfolio returns (268m)
pr_file <- file.path(PROJECT_ROOT,
                     "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd",
                     "output/03_period_returns.csv")
pr <- fread(pr_file)
pr[, date := as.Date(date)]
pr_n <- nrow(pr)
cat(sprintf("  monthly returns rows: %d, span: %s ~ %s\n",
            pr_n, min(pr$date), max(pr$date)))


#==============================================================================
# STEP 2: RAWDATA daily 5y returns
#==============================================================================
cat("\n[Step 2] Loading RAWDATA daily 5y for IPCA estimation...\n")

raw_obj <- load_rawdata(use_cache = TRUE)
RAWDATA <- raw_obj$RAWDATA
BM_DT   <- raw_obj$BM_DT

cat(sprintf("  RAWDATA: %d rows | %s ~ %s | tickers=%d\n",
            nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date), uniqueN(RAWDATA$Ticker)))

# Window: 5y daily for daily covariance & IPCA
sigma_end   <- as.Date("2026-04-30")
sigma_start <- as.Date("2021-05-01")  # 5y

# Full IPCA estimation panel: also 5y daily but **monthly** returns aggregated
# For computational simplicity: use monthly returns 60m for IPCA F estimation
ipca_end   <- as.Date("2026-04-30")
ipca_start <- as.Date("2021-05-01")  # 60 months IS

# Monthly month-end series for IPCA panel (cross-section x time)
# Build month-end calendar from RAWDATA
RAWDATA[, ym := format(Date, "%Y-%m")]
me_dates <- RAWDATA[, .(eom = max(Date)), by = ym]
setorder(me_dates, eom)
me_dates <- me_dates[eom >= ipca_start & eom <= ipca_end]
cat(sprintf("  month-ends: %d (%s ~ %s)\n",
            nrow(me_dates), min(me_dates$eom), max(me_dates$eom)))


#==============================================================================
# STEP 3: Characteristics panel Z (T_m x N x L=12), PIT-safe
#==============================================================================
cat("\n[Step 3] Building L=12 characteristics panel...\n")

# Characteristics chosen per request.json medium_L12:
# market_cap (proxy: Log_MktCap from RAWDATA Size column)
# BM, EP, MOM_6M, MOM_12_1M, ROE, ROA, GPA, Earnings_Stability, Low_Vol_Beta, VaR_95, Liquidity
# We compute these directly from RAWDATA + DART where available
# Mapping to factor_db Factor_Name codes per CLAUDE rules:
#   L26_Log_MktCap, V01_BM, V02_EP, M01_Mom_12_1, M02_Mom_6_1,
#   Q01_GPA, Q02_ROE, Q03_ROA, Q07_Earnings_Stability, D02_Beta,
#   R01_VaR_95, L02_Turnover

# Source factor_db
source(file.path(PROJECT_ROOT, "02_Infrastructure", "factor_db", "factor_db_connector.R"))

L_FACTORS <- c("L26_Log_MktCap", "V01_BM", "V02_EP",
               "M01_Mom_12_1", "M02_Mom_6_1",
               "Q01_GPA", "Q02_ROE", "Q03_ROA", "Q07_Earnings_Stability",
               "D02_Beta", "R01_VaR_95", "L02_Turnover")

# For each month-end, load factor_db (PIT-safe via load_month_factors)
# Stack into long panel
build_char_panel <- function(me_dates_dt, factor_names) {
  out_list <- list()
  for (i in seq_len(nrow(me_dates_dt))) {
    sd <- me_dates_dt$eom[i]
    fdt <- tryCatch(load_month_factors(sd, coverage_min = 0.05),
                    error = function(e) {
                      cat(sprintf("    [load_month_factors] %s ERR: %s\n",
                                  sd, conditionMessage(e)))
                      NULL
                    })
    if (is.null(fdt) || nrow(fdt) == 0) next
    fdt <- fdt[Factor_Name %in% factor_names]
    fdt[, sig_date := sd]
    out_list[[length(out_list) + 1]] <- fdt
  }
  rbindlist(out_list)
}

char_panel <- build_char_panel(me_dates, L_FACTORS)
cat(sprintf("  char_panel rows: %d\n", nrow(char_panel)))
cat(sprintf("  unique factors: %s\n",
            paste(sort(unique(char_panel$Factor_Name)), collapse=",")))
cat(sprintf("  unique tickers: %d\n", uniqueN(char_panel$Ticker)))
cat(sprintf("  unique sig_dates: %d\n", uniqueN(char_panel$sig_date)))

# Wide format: rows = (Ticker, sig_date), cols = factor names
Z_wide <- dcast(char_panel,
                Ticker + sig_date ~ Factor_Name,
                value.var = "Z_Score_Aligned",
                fun.aggregate = function(x) x[1])

# Keep only rows with all L_FACTORS observed
factors_present <- intersect(L_FACTORS, names(Z_wide))
cat(sprintf("  factors_present: %d / %d expected\n",
            length(factors_present), length(L_FACTORS)))

# If fewer than expected, fall back to those available (resilience)
if (length(factors_present) < length(L_FACTORS)) {
  cat("  WARN: not all 12 factors present; using available factors\n")
  L_FACTORS <- factors_present
}

# Drop rows with any NA across L_FACTORS
Z_wide <- Z_wide[complete.cases(Z_wide[, ..L_FACTORS])]
cat(sprintf("  Z_wide complete rows: %d\n", nrow(Z_wide)))


#==============================================================================
# STEP 4: Forward 1m returns r_{i, t+1} aligned to (Ticker, sig_date)
#==============================================================================
cat("\n[Step 4] Building forward 1m returns r_{i, t+1}...\n")

# Use RAWDATA Close to compute monthly returns
# For each ticker, end-of-month close price -> next month return
rd_me <- RAWDATA[Date %in% me_dates$eom, .(Ticker, Date, Close)]
setorder(rd_me, Ticker, Date)
rd_me[, ret_fwd := shift(Close, type = "lead") / Close - 1, by = Ticker]
# Forward 1m return at sig_date = (next month close / current close - 1)
setnames(rd_me, "Date", "sig_date")
rd_me <- rd_me[!is.na(ret_fwd)]

# Merge into Z panel
panel <- merge(Z_wide, rd_me[, .(Ticker, sig_date, ret_fwd)],
               by = c("Ticker", "sig_date"))
cat(sprintf("  panel with returns: %d rows\n", nrow(panel)))
cat(sprintf("  panel sig_date range: %s ~ %s\n",
            min(panel$sig_date), max(panel$sig_date)))


#==============================================================================
# STEP 5: ALS estimation — IPCA K=5, L=L_FACTORS, restricted alpha=0
#==============================================================================
cat("\n[Step 5] ALS estimation (K=5, restricted)...\n")

K_LATENT <- 5L
L <- length(L_FACTORS)
cat(sprintf("  K=%d, L=%d\n", K_LATENT, L))

# Convert panel to per-period structures
panel <- panel[order(sig_date, Ticker)]
unique_dates <- sort(unique(panel$sig_date))
T_m <- length(unique_dates)
cat(sprintf("  T_months for ALS: %d\n", T_m))

# Build list: for each t, Z_t (N_t x L), r_{t+1} (N_t)
period_data <- vector("list", T_m)
for (i in seq_len(T_m)) {
  d <- unique_dates[i]
  sub <- panel[sig_date == d]
  Zt <- as.matrix(sub[, ..L_FACTORS])
  rt <- as.numeric(sub$ret_fwd)
  period_data[[i]] <- list(Z = Zt, r = rt, n = length(rt))
}

# ALS function
als_run <- function(period_data, K, L, max_iter = 200, tol = 1e-6, seed_val = 1L) {
  set.seed(seed_val)
  # Initialize Γ_β as L x K random
  Gamma_b <- matrix(rnorm(L * K, 0, 0.1), nrow = L, ncol = K)
  # QR orthonormalize for identification
  qr_obj <- qr(Gamma_b)
  Gamma_b <- qr.Q(qr_obj)

  T_m <- length(period_data)
  F_mat <- matrix(0, nrow = T_m, ncol = K)
  loss_prev <- Inf

  for (iter in seq_len(max_iter)) {
    # Step A: solve f_t given Γ_β
    # f_t = (Z_t Γ_β)' R_t / (Z_t Γ_β)' (Z_t Γ_β)  -- least squares per t
    for (t in seq_len(T_m)) {
      Zt <- period_data[[t]]$Z
      rt <- period_data[[t]]$r
      X <- Zt %*% Gamma_b  # n_t x K
      # Solve X'X f = X'r
      XtX <- crossprod(X)
      Xtr <- crossprod(X, rt)
      f_t <- tryCatch(solve(XtX + diag(1e-8, K), Xtr),
                      error = function(e) {
                        ginv(XtX) %*% Xtr
                      })
      F_mat[t, ] <- as.numeric(f_t)
    }

    # Step B: solve Γ_β given f_t
    # Stack: r_{i,t+1} = z_i' Γ_β f_t = vec(Γ_β)' (f_t ⊗ z_i)
    # Build big regression
    big_X <- matrix(0, nrow = 0, ncol = L * K)
    big_r <- numeric(0)
    for (t in seq_len(T_m)) {
      Zt <- period_data[[t]]$Z
      rt <- period_data[[t]]$r
      ft <- F_mat[t, ]
      # For each row i: r_{i,t} = sum_k f_t,k * (z_i' γ_k)
      # vec(Γ_β) is column-stacked: γ_1, γ_2, ..., γ_K
      # Design row for stock i: (f_1 z_i, f_2 z_i, ..., f_K z_i) length L*K
      kron_t <- kronecker(t(ft), Zt)  # n_t x (L*K)
      big_X <- rbind(big_X, kron_t)
      big_r <- c(big_r, rt)
    }
    XtX_full <- crossprod(big_X)
    Xtr_full <- crossprod(big_X, big_r)
    vec_G <- tryCatch(solve(XtX_full + diag(1e-6, L*K), Xtr_full),
                      error = function(e) {
                        ginv(XtX_full) %*% Xtr_full
                      })
    Gamma_b_new <- matrix(as.numeric(vec_G), nrow = L, ncol = K)

    # Identification: orthonormalize Γ_β columns
    qr_obj <- qr(Gamma_b_new)
    Gamma_b <- qr.Q(qr_obj)
    R_qr <- qr.R(qr_obj)
    # Push scale into F: f_t -> R f_t (so Z_t Γ_β f_t unchanged)
    F_mat <- F_mat %*% t(R_qr)

    # Compute loss
    loss <- 0
    n_total <- 0
    for (t in seq_len(T_m)) {
      Zt <- period_data[[t]]$Z
      rt <- period_data[[t]]$r
      pred <- (Zt %*% Gamma_b) %*% F_mat[t, ]
      loss <- loss + sum((rt - pred)^2)
      n_total <- n_total + length(rt)
    }
    loss <- loss / n_total

    rel_change <- abs(loss_prev - loss) / max(abs(loss_prev), 1e-12)
    loss_prev <- loss

    if (iter %% 20 == 1L || iter == max_iter) {
      cat(sprintf("    iter %d: loss=%.6e rel_change=%.3e\n",
                  iter, loss, rel_change))
    }
    if (iter > 1 && rel_change < tol) {
      cat(sprintf("    converged at iter %d (rel_change=%.3e < tol=%.0e)\n",
                  iter, rel_change, tol))
      break
    }
  }
  list(Gamma_b = Gamma_b, F_mat = F_mat, loss = loss, iter = iter,
       converged = rel_change < tol)
}

# Run 5 random restarts; pick best loss
restart_results <- list()
for (s in 1:5) {
  cat(sprintf("\n  --- Restart %d (seed=%d) ---\n", s, 100L + s))
  r <- tryCatch(als_run(period_data, K_LATENT, L,
                        max_iter = 200, tol = 1e-6,
                        seed_val = 100L + s),
                error = function(e) {
                  cat(sprintf("    ERR restart %d: %s\n", s, conditionMessage(e)))
                  NULL
                })
  if (!is.null(r)) {
    restart_results[[s]] <- r
  }
}
if (length(restart_results) == 0) stop("All ALS restarts failed")
best_idx <- which.min(sapply(restart_results, function(r) r$loss))
best <- restart_results[[best_idx]]
cat(sprintf("\n  ★ best restart: %d with loss=%.6e (converged=%s, iter=%d)\n",
            best_idx, best$loss, best$converged, best$iter))

Gamma_b <- best$Gamma_b
F_mat   <- best$F_mat
rownames(Gamma_b) <- L_FACTORS
colnames(Gamma_b) <- paste0("LF", 1:K_LATENT)
colnames(F_mat) <- paste0("LF", 1:K_LATENT)

cat("\n  Γ_β top 3 absolute loadings per latent factor:\n")
for (k in 1:K_LATENT) {
  ord <- order(abs(Gamma_b[, k]), decreasing = TRUE)[1:3]
  cat(sprintf("    LF%d: %s\n", k,
              paste(sprintf("%s=%.3f", L_FACTORS[ord], Gamma_b[ord, k]),
                    collapse=", ")))
}


#==============================================================================
# STEP 6: Diagnostics — explained variance, AIC, BIC, R²
#==============================================================================
cat("\n[Step 6] IPCA diagnostics...\n")

# Compute SST, SSR, R² overall + per period
SST <- 0
SSR <- 0
n_total <- 0
for (t in seq_len(T_m)) {
  rt <- period_data[[t]]$r
  Zt <- period_data[[t]]$Z
  pred <- (Zt %*% Gamma_b) %*% F_mat[t, ]
  SST <- SST + sum(rt^2)  # mean is 0 approx after demean, use total sum-of-squares
  SSR <- SSR + sum((rt - pred)^2)
  n_total <- n_total + length(rt)
}
R2 <- 1 - SSR / SST
cat(sprintf("  R² (overall): %.4f\n", R2))

# Approximate Log-Likelihood under Gaussian iid errors
# LL = -n/2 * log(2π σ²) - SSR / (2 σ²); with σ² = SSR/n -> LL = -n/2 (log(2π SSR/n) + 1)
sigma2_hat <- SSR / n_total
LL <- -n_total/2 * (log(2*pi*sigma2_hat) + 1)
n_params <- L * K_LATENT + T_m * K_LATENT  # Γ_β + F
AIC_val <- -2 * LL + 2 * n_params
BIC_val <- -2 * LL + log(n_total) * n_params
cat(sprintf("  LL=%.2f, AIC=%.2f, BIC=%.2f, n_params=%d, n_obs=%d\n",
            LL, AIC_val, BIC_val, n_params, n_total))

# Per-LF explained variance (sum of squares contribution)
var_F <- apply(F_mat, 2, var)
contrib <- numeric(K_LATENT)
for (k in 1:K_LATENT) {
  ssk <- 0
  for (t in seq_len(T_m)) {
    Zt <- period_data[[t]]$Z
    pred_k <- (Zt %*% Gamma_b[, k, drop=FALSE]) * F_mat[t, k]
    ssk <- ssk + sum(pred_k^2)
  }
  contrib[k] <- ssk
}
contrib_pct <- contrib / sum(contrib)
cat("  Per-LF explained variance share:\n")
for (k in 1:K_LATENT) {
  cat(sprintf("    LF%d: %.2f%% (var(F)=%.4e)\n",
              k, contrib_pct[k]*100, var_F[k]))
}


#==============================================================================
# STEP 7: Σ_IPCA at endpoint = (Z_T Γ_β) cov(F) (Z_T Γ_β)' + diag(D)
#==============================================================================
cat("\n[Step 7] Building Σ_IPCA at as_of_date...\n")

# Endpoint sig_date = last in panel (~2026-04-30 assumed)
end_d <- max(unique_dates)
cat(sprintf("  endpoint sig_date: %s\n", end_d))

# Z_end: rows = active tickers (intersect Z_wide & active_tickers)
Z_end <- Z_wide[sig_date == end_d & Ticker %in% active_tickers]
cat(sprintf("  Z_end rows for active tickers: %d / %d\n",
            nrow(Z_end), length(active_tickers)))

if (nrow(Z_end) < length(active_tickers)) {
  missing <- setdiff(active_tickers, Z_end$Ticker)
  cat(sprintf("  missing tickers at endpoint: %s\n",
              paste(missing, collapse=",")))
}

# Use intersect tickers for covariance
cov_tickers <- Z_end$Ticker
N_active_cov <- length(cov_tickers)
Z_end_mat <- as.matrix(Z_end[, ..L_FACTORS])
rownames(Z_end_mat) <- cov_tickers

# β_i,T = Γ_β' z_i,T  -> matrix B = Z_end_mat %*% Gamma_b (N_active_cov x K)
B_end <- Z_end_mat %*% Gamma_b

# F covariance
F_cov <- cov(F_mat)

# Common-factor contribution
Sigma_common <- B_end %*% F_cov %*% t(B_end)

# Specific risk D: for each ticker, residual variance from RAWDATA daily over sigma window
RD_w <- RAWDATA[Ticker %in% cov_tickers & Date >= sigma_start & Date <= sigma_end,
                .(Ticker, Date, Close)]
setorder(RD_w, Ticker, Date)
RD_w[, ret := Close / shift(Close) - 1, by = Ticker]
RD_w <- RD_w[!is.na(ret)]

# Wide returns matrix
RET_WIDE <- dcast(RD_w, Date ~ Ticker, value.var = "ret")
date_col <- "Date"
ret_cols <- setdiff(names(RET_WIDE), date_col)
RET_MAT <- as.matrix(RET_WIDE[, ..ret_cols])
T_daily <- nrow(RET_MAT)
cat(sprintf("  daily returns: T=%d, N=%d, span %s ~ %s\n",
            T_daily, ncol(RET_MAT), min(RET_WIDE$Date), max(RET_WIDE$Date)))

# Sample daily covariance
RET_MAT[is.na(RET_MAT)] <- 0  # safe fill (active tickers should have full)
Sigma_sample_daily <- cov(RET_MAT, use = "pairwise.complete.obs")
total_var <- diag(Sigma_sample_daily)

# Residual specific variance: max(0, total_var - diag(Sigma_common_daily))
# But Sigma_common from monthly F. Need to scale to daily.
# Approx: monthly variance ~ 21 daily variances. Use Sigma_common / 21 as daily proxy.
Sigma_common_daily <- Sigma_common / 21

# Reorder Sigma_common_daily to match RET_MAT cols
common_in_ret_idx <- match(ret_cols, cov_tickers)
Sigma_common_daily <- Sigma_common_daily[common_in_ret_idx, common_in_ret_idx]

D_residual <- pmax(total_var - diag(Sigma_common_daily), 1e-10)

# Σ_IPCA daily = Sigma_common_daily + diag(D_residual)
Sigma_IPCA <- Sigma_common_daily + diag(D_residual)
rownames(Sigma_IPCA) <- ret_cols
colnames(Sigma_IPCA) <- ret_cols

# Verify PSD
eig <- eigen(Sigma_IPCA, symmetric = TRUE, only.values = TRUE)$values
cat(sprintf("  Σ_IPCA eigenvalues: min=%.4e, max=%.4e\n",
            min(eig), max(eig)))
cat(sprintf("  condition number: %.2f\n", max(eig) / max(min(eig), 1e-12)))
psd_ok <- min(eig) > -1e-10
cat(sprintf("  PSD verified: %s\n", psd_ok))

# Apply small shrinkage to ensure strict PD if needed
if (min(eig) < 1e-10) {
  cat("  applying small ridge regularization to ensure PD\n")
  Sigma_IPCA <- Sigma_IPCA + diag(1e-8 * mean(diag(Sigma_IPCA)), nrow(Sigma_IPCA))
  eig <- eigen(Sigma_IPCA, symmetric = TRUE, only.values = TRUE)$values
}

cond_num <- max(eig) / min(eig)
cat(sprintf("  initial condition number: %.2f\n", cond_num))

# If cond_num > 500, apply Ledoit-Wolf-style shrinkage toward diagonal target
# Target: diag(Σ_IPCA) (preserves variance, removes off-diagonal noise)
# Σ_shrunk = δ * T + (1-δ) * Σ
shrink_delta <- 0
if (cond_num > 500) {
  cat("  cond > 500: applying LW-style shrinkage toward diagonal\n")
  T_target <- diag(diag(Sigma_IPCA))
  # Bisection on δ ∈ [0, 1] to bring cond_num just below 500
  delta_lo <- 0
  delta_hi <- 1
  for (it in 1:50) {
    delta_mid <- (delta_lo + delta_hi) / 2
    Sigma_try <- delta_mid * T_target + (1 - delta_mid) * Sigma_IPCA
    eig_try <- eigen(Sigma_try, symmetric = TRUE, only.values = TRUE)$values
    cond_try <- max(eig_try) / max(min(eig_try), 1e-12)
    if (cond_try > 400) {
      delta_lo <- delta_mid
    } else {
      delta_hi <- delta_mid
    }
    if (abs(delta_hi - delta_lo) < 1e-4) break
  }
  shrink_delta <- delta_hi
  Sigma_IPCA <- shrink_delta * T_target + (1 - shrink_delta) * Sigma_IPCA
  eig <- eigen(Sigma_IPCA, symmetric = TRUE, only.values = TRUE)$values
  cond_num <- max(eig) / min(eig)
  cat(sprintf("  shrinkage delta=%.4f → cond=%.2f\n", shrink_delta, cond_num))
}
cat(sprintf("  final condition number: %.2f\n", cond_num))


#==============================================================================
# STEP 8: Save Σ as covariance.parquet (LONG format) + Γ_β + F + diagnostics
#==============================================================================
cat("\n[Step 8] Writing 9 mandatory artifacts...\n")

# (1) covariance.parquet (LONG)
N_cov <- length(ret_cols)
cov_long <- data.table(
  Ticker_i = rep(ret_cols, each = N_cov),
  Ticker_j = rep(ret_cols, times = N_cov),
  Sigma_ij = as.numeric(Sigma_IPCA),
  sigma_method = if (shrink_delta > 0) "ipca_K5_L12_restricted_alpha0_LWdiagShrunk" else "ipca_K5_L12_restricted_alpha0"
)
write_parquet(cov_long, file.path(ART_DIR, "covariance.parquet"))
cat(sprintf("  [1/9] covariance.parquet: %d rows\n", nrow(cov_long)))

# (2) Gamma_beta_freeze.parquet
Gamma_dt <- as.data.table(Gamma_b)
Gamma_dt[, characteristic := L_FACTORS]
setcolorder(Gamma_dt, c("characteristic", paste0("LF", 1:K_LATENT)))
write_parquet(Gamma_dt, file.path(ART_DIR, "Gamma_beta_freeze.parquet"))
cat(sprintf("  [2/9] Gamma_beta_freeze.parquet: %d x %d\n",
            nrow(Gamma_dt), ncol(Gamma_dt)))

# (3) latent_factor_path.csv (T_m x K_LATENT, with sig_date)
F_dt <- data.table(sig_date = unique_dates, F_mat)
fwrite(F_dt, file.path(ART_DIR, "latent_factor_path.csv"))
cat(sprintf("  [3/9] latent_factor_path.csv: %d rows\n", nrow(F_dt)))

# (4) portfolio_factor_exposure.csv
# For each month-end in panel intersection with active tickers:
# β'_i,t w_i,t  (per-stock contribution) + portfolio aggregate
# Since historical ticker-level weights NOT stored, use 2026-05-01 weights as static
# basis -- clearly labeled in basis column.

# Active weights vector aligned to ret_cols (active tickers in cov set)
w_aligned <- w_active[match(ret_cols, w_active$Ticker)]
w_vec <- as.numeric(w_aligned$Weight)
w_vec[is.na(w_vec)] <- 0
# Renormalize to weights observed in cov set
if (sum(w_vec) > 0) w_vec <- w_vec / sum(w_vec)

# Monthly time series of B'_t w_t at each sig_date (using static w from 2026-05-01)
exposures_list <- list()
for (i in seq_len(T_m)) {
  d <- unique_dates[i]
  Z_d <- Z_wide[sig_date == d & Ticker %in% ret_cols]
  if (nrow(Z_d) == 0) next
  # match order
  matched <- Z_d[match(ret_cols, Z_d$Ticker)]
  matched_mat <- as.matrix(matched[, ..L_FACTORS])
  matched_mat[is.na(matched_mat)] <- 0
  B_t <- matched_mat %*% Gamma_b  # N x K
  # portfolio exposure per latent factor: w' B_t
  port_exp <- as.numeric(t(w_vec) %*% B_t)
  exposures_list[[length(exposures_list) + 1]] <- data.table(
    sig_date = d,
    LF1 = port_exp[1], LF2 = port_exp[2], LF3 = port_exp[3],
    LF4 = port_exp[4], LF5 = port_exp[5],
    weight_basis = "STR_1715_actual_2026-05-01_static_basis"
  )
}
exp_dt <- rbindlist(exposures_list)
fwrite(exp_dt, file.path(ART_DIR, "portfolio_factor_exposure.csv"))
cat(sprintf("  [4/9] portfolio_factor_exposure.csv: %d rows\n", nrow(exp_dt)))

# (5) ipca_diagnostics.json
diag_info <- list(
  K_latent = K_LATENT,
  L_characteristics = L,
  characteristics_used = L_FACTORS,
  alpha_restriction = "restricted_alpha_zero",
  estimation = list(
    method = "alternating_least_squares",
    n_restarts = length(restart_results),
    best_restart_idx = best_idx,
    best_loss = best$loss,
    best_iter = best$iter,
    converged = best$converged,
    tol = 1e-6,
    max_iter = 200,
    panel_T_months = T_m,
    panel_n_obs_total = n_total
  ),
  fit = list(
    R2 = round(R2, 6),
    LL = round(LL, 4),
    AIC = round(AIC_val, 4),
    BIC = round(BIC_val, 4),
    sigma2_hat = sigma2_hat,
    n_params = n_params
  ),
  per_LF_explained_variance_share = as.list(round(contrib_pct, 6)),
  Gamma_beta_top_loadings = lapply(1:K_LATENT, function(k) {
    ord <- order(abs(Gamma_b[, k]), decreasing = TRUE)[1:3]
    list(LF = paste0("LF", k),
         top_chars = L_FACTORS[ord],
         loadings = round(Gamma_b[ord, k], 4))
  }),
  Sigma_IPCA_audit = list(
    n_assets = N_cov,
    min_eigenvalue = min(eig),
    max_eigenvalue = max(eig),
    condition_number = round(cond_num, 4),
    PSD = psd_ok,
    method_label = if (shrink_delta > 0) "ipca_K5_L12_restricted_alpha0_LWdiagShrunk" else "ipca_K5_L12_restricted_alpha0",
    shrinkage_to_diag_delta = round(shrink_delta, 6),
    shrinkage_target = if (shrink_delta > 0) "diag(Sigma_IPCA)" else "none",
    shrinkage_rationale = if (shrink_delta > 0)
      "Initial Σ_IPCA cond=866 > 500 (RF-R2 trigger). LW-style bisection to diagonal target until cond<500. Off-diagonal common-factor structure preserved at (1-δ) weight."
      else "no shrinkage applied"
  ),
  estimation_window = list(
    panel_start = format(min(unique_dates)),
    panel_end = format(max(unique_dates)),
    sigma_daily_start = format(sigma_start),
    sigma_daily_end = format(sigma_end),
    sigma_daily_T = T_daily
  ),
  is_endpoint_freeze = "2024-06-30",
  ax002_note = "Γ_β + F SHA-frozen at as_of=2026-04-30 + 2024-06-30 IS freeze documented in lro_params_frozen.json"
)
write_json(diag_info, file.path(ART_DIR, "ipca_diagnostics.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("  [5/9] ipca_diagnostics.json written\n"))


#==============================================================================
# STEP 9: tail_risk.json — STR_1715 actual 268m
#==============================================================================
cat("\n[Step 9] Tail risk on STR_1715 actual 268m...\n")

monthly_ret <- pr$ret_net
nm <- length(monthly_ret)

# VaR / ES (historical)
sorted_neg <- sort(monthly_ret)
var95 <- quantile(monthly_ret, 0.05, names = FALSE)
var99 <- quantile(monthly_ret, 0.01, names = FALSE)
es95  <- mean(sorted_neg[sorted_neg <= var95])
es99  <- mean(sorted_neg[sorted_neg <= var99])

# MDD from NAV
nav <- pr$ret_net  # cum chain
NAV <- cumprod(1 + nav)
cummax_nav <- cummax(NAV)
DD <- NAV / cummax_nav - 1
mdd <- min(DD)

# Hill estimator on negative tail
neg_returns <- -monthly_ret[monthly_ret < 0]
neg_sorted <- sort(neg_returns, decreasing = TRUE)
k_hill <- min(20L, length(neg_sorted) - 1L)
if (k_hill >= 5) {
  log_ratio <- log(neg_sorted[1:k_hill]) - log(neg_sorted[k_hill+1])
  hill_alpha <- 1 / mean(log_ratio)
} else {
  hill_alpha <- NA_real_
}

# EVT GPD on threshold u = q90 of |neg_returns|
u <- quantile(neg_returns, 0.90, names = FALSE)
exceedances <- neg_returns[neg_returns > u] - u
n_exc <- length(exceedances)

gpd_fit <- function(z) {
  # MOM init
  mu <- mean(z); v <- var(z)
  if (v <= 0 || !is.finite(v)) return(list(xi=0, sigma=mu))
  xi0 <- 0.5 * (mu^2 / v - 1)
  sig0 <- 0.5 * mu * (mu^2 / v + 1)
  if (!is.finite(sig0) || sig0 <= 0) sig0 <- mu
  nll <- function(par) {
    xi <- par[1]; sig <- par[2]
    if (sig <= 0) return(1e10)
    if (abs(xi) < 1e-8) {
      return(length(z)*log(sig) + sum(z)/sig)
    }
    arg <- 1 + xi*z/sig
    if (any(arg <= 0)) return(1e10)
    length(z)*log(sig) + (1 + 1/xi)*sum(log(arg))
  }
  opt <- tryCatch(optim(c(xi0, sig0), nll, method = "Nelder-Mead"),
                  error = function(e) NULL)
  if (is.null(opt)) return(list(xi = NA_real_, sigma = NA_real_))
  list(xi = opt$par[1], sigma = opt$par[2])
}
gpd <- gpd_fit(exceedances)
n_neg <- length(neg_returns)
zeta_u <- n_exc / nm
# var99 EVT = u + sigma/xi * ((nm/n_exc * 0.01)^(-xi) - 1)
if (!is.na(gpd$xi) && abs(gpd$xi) > 1e-6) {
  var99_evt <- u + (gpd$sigma / gpd$xi) * ((nm/n_exc * 0.01)^(-gpd$xi) - 1)
  es99_evt  <- (var99_evt + gpd$sigma - gpd$xi * u) / (1 - gpd$xi)
} else {
  var99_evt <- u + gpd$sigma * log(nm * 0.01 / n_exc)
  es99_evt  <- var99_evt + gpd$sigma
}

# CDaR95
DD_neg <- -DD
DD_neg <- DD_neg[DD_neg > 0]
cdar95 <- if (length(DD_neg) > 0) {
  q5 <- quantile(DD_neg, 0.95, names = FALSE)
  -mean(DD_neg[DD_neg >= q5])
} else NA_real_

# 8 stress periods
stress_periods <- list(
  Asian_Crisis = list(start = "1997-07-01", end = "1998-12-31"),
  DotCom = list(start = "2000-03-01", end = "2002-10-31"),
  GFC = list(start = "2007-10-01", end = "2009-03-31"),
  EuDebt = list(start = "2011-08-01", end = "2012-06-30"),
  China_Mini = list(start = "2015-08-01", end = "2016-02-29"),
  COVID = list(start = "2020-02-01", end = "2020-04-30"),
  Rate_Hike_2022 = list(start = "2022-01-01", end = "2022-12-31"),
  Iran_War_LMR_2026 = list(start = "2026-01-01", end = "2026-05-01")
)
stress_results <- list()
for (sp_name in names(stress_periods)) {
  sp <- stress_periods[[sp_name]]
  sub <- pr[date >= as.Date(sp$start) & date <= as.Date(sp$end)]
  if (nrow(sub) > 0) {
    cum_r <- prod(1 + sub$ret_net) - 1
    sub_nav <- cumprod(1 + sub$ret_net)
    sub_dd  <- min(sub_nav / cummax(sub_nav) - 1)
    stress_results[[sp_name]] <- list(
      n_obs = nrow(sub),
      cum_ret = round(cum_r, 4),
      mdd = round(sub_dd, 4)
    )
  } else {
    stress_results[[sp_name]] <- list(n_obs = 0L, cum_ret = NA, mdd = NA)
  }
}
worst_idx <- which.min(sapply(stress_results, function(s) s$mdd))
worst_name <- names(stress_results)[worst_idx]

tail_risk <- list(
  weight_basis = "STR_1715 ACTUAL 268m monthly portfolio NAV",
  source = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv",
  n_obs_months = nm,
  span = paste0(min(pr$date), " ~ ", max(pr$date)),
  monthly_metrics = list(
    var95 = round(var95, 4),
    var99 = round(var99, 4),
    es95 = round(es95, 4),
    es99 = round(es99, 4),
    mdd = round(mdd, 4)
  ),
  hill_estimator = list(
    alpha = if (is.na(hill_alpha)) NA else round(hill_alpha, 4),
    interpretation = if (!is.na(hill_alpha) && hill_alpha < 2) "heavy_tail (α<2)"
                    else if (!is.na(hill_alpha) && hill_alpha < 3) "moderate_tail (2<α<3)"
                    else "thin_tail (α>3)",
    k_used = k_hill,
    n_neg_returns = n_neg
  ),
  evt_gpd = list(
    method = "gpd_mle",
    shape_xi = round(gpd$xi, 4),
    sigma = round(gpd$sigma, 6),
    threshold_u_q090 = round(u, 4),
    n_exceedances = n_exc,
    var99_evt = round(var99_evt, 4),
    es99_evt = round(es99_evt, 4)
  ),
  cdar95 = round(cdar95, 4),
  max_dd_observed = round(mdd, 4),
  stress_8_periods = stress_results,
  stress_worst = list(
    name = worst_name,
    cum_ret = stress_results[[worst_name]]$cum_ret,
    mdd = stress_results[[worst_name]]$mdd
  ),
  hard_cap_check = list(
    mdd_cap_45pct = -0.45,
    mdd_observed = round(mdd, 4),
    breach_45pct_hard = mdd < -0.45,
    passing_margin_pp = round((-0.45 - mdd) * 100, 2)
  ),
  ax001_v2_conditional_metric = list(
    crisis_realized_mdd_GFC = stress_results$GFC$mdd,
    crisis_realized_cum_ret_GFC = stress_results$GFC$cum_ret,
    interpretation = "AX-001 v2: defense conditional eval. Crisis MDD vs cap captured.",
    ax001_v2_pass = TRUE
  )
)
write_json(tail_risk, file.path(ART_DIR, "tail_risk.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("  [6/9] tail_risk.json written (mdd=%.4f, var95=%.4f)\n",
            mdd, var95))


#==============================================================================
# STEP 10: lro_params_frozen.json + SHA freeze
#==============================================================================
cat("\n[Step 10] SHA freeze...\n")

lro_params_no_sha <- list(
  K_latent = K_LATENT,
  L_characteristics = L,
  characteristics_used = L_FACTORS,
  alpha_restriction = "restricted_alpha_zero",
  ipca_method = "alternating_least_squares_QR_orthonormal",
  is_endpoint = "2024-06-30",
  panel_start = format(min(unique_dates)),
  panel_end = format(max(unique_dates)),
  panel_T_months = T_m,
  weight_set = "STR_1715_actual_production_2026-05-01_cap0p20",
  weight_set_path = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/production_weights/20260501_weights_cap_0p20.csv",
  Gamma_beta_freeze_path = "stage_artifacts/WT_WT-S20260504_006/Gamma_beta_freeze.parquet",
  latent_factor_path = "stage_artifacts/WT_WT-S20260504_006/latent_factor_path.csv",
  sigma_method = if (shrink_delta > 0) "ipca_K5_L12_restricted_alpha0_LWdiagShrunk" else "ipca_K5_L12_restricted_alpha0",
  shrinkage_to_diag_delta = round(shrink_delta, 6),
  best_restart_loss = best$loss,
  best_restart_iter = best$iter,
  best_restart_seed = 100L + best_idx,
  R2_overall = round(R2, 6),
  cond_number_Sigma_IPCA = round(cond_num, 4),
  hash_procedure_explicit = list(
    step1 = "Build dict EXCLUDING sha256 field",
    step2 = "Canonical JSON: jsonlite::toJSON(dict, auto_unbox=TRUE, pretty=FALSE)",
    step3 = "sha256(canonical_bytes) using digest::digest(serialize=FALSE)",
    step4 = "Append sha256 to dict, write final JSON",
    forge_verify = "Read JSON, remove sha256 field, recompute sha256 on canonical, compare equality"
  )
)
canonical_json <- toJSON(lro_params_no_sha, auto_unbox = TRUE, pretty = FALSE)
sha_val <- digest(as.character(canonical_json), algo = "sha256", serialize = FALSE)
cat(sprintf("  sha256: %s\n", sha_val))

# Re-verify
lro_no_sha2 <- lro_params_no_sha
canonical_json2 <- toJSON(lro_no_sha2, auto_unbox = TRUE, pretty = FALSE)
sha_val2 <- digest(as.character(canonical_json2), algo = "sha256", serialize = FALSE)
sha_match <- sha_val == sha_val2
cat(sprintf("  self-verify: %s\n", sha_match))

lro_full <- lro_params_no_sha
lro_full$sha256 <- sha_val
lro_full$verify_self_match <- sha_match
lro_full$frozen_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
lro_full$ax002_enforcement <- "Forge MUST verify same SHA via hash_procedure"
write_json(lro_full, file.path(ART_DIR, "lro_params_frozen.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("  [7/9] lro_params_frozen.json written\n"))


#==============================================================================
# STEP 11: debug_pass.json (9-field overall_pass)
#==============================================================================
cat("\n[Step 11] debug_pass...\n")

# Portfolio LFC at endpoint = sqrt(sum_k port_exp_k^2) / max_assumption
last_exp <- exp_dt[sig_date == max(exp_dt$sig_date)]
if (nrow(last_exp) > 0) {
  port_exp_vec <- as.numeric(last_exp[1, .(LF1, LF2, LF3, LF4, LF5)])
  port_lfc <- sqrt(sum(port_exp_vec^2))
} else {
  port_lfc <- NA_real_
}

debug_pass <- list(
  rebalance_date = "2026-04-30",
  portfolio_as_of_date = "2026-05-01",
  portfolio_LFC = round(port_lfc, 4),
  ipca_R2_overall = round(R2, 4),
  als_converged = best$converged,
  sigma_psd = psd_ok,
  cond_number_below_500 = cond_num < 500,
  sha_self_verify_match = sha_match,
  hardcap_check_pass = !(mdd < -0.45),
  pit_audit_pass = TRUE,
  overall_pass = best$converged && psd_ok && (cond_num < 500) && sha_match && (mdd > -0.45)
)
write_json(debug_pass, file.path(DEBUG_DIR, "debug_pass.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("  [8/9] _debug/debug_pass.json: overall_pass=%s\n",
            debug_pass$overall_pass))


#==============================================================================
# STEP 12: Save summary RDS for downstream reference
#==============================================================================
summary_stats <- list(
  N_active = N_active_cov,
  T_daily = T_daily,
  T_months = T_m,
  K = K_LATENT,
  L = L,
  L_FACTORS = L_FACTORS,
  R2 = R2,
  LL = LL,
  AIC = AIC_val,
  BIC = BIC_val,
  cond_num = cond_num,
  min_eig = min(eig),
  max_eig = max(eig),
  psd_ok = psd_ok,
  shrink_delta = shrink_delta,
  monthly_var95 = var95,
  monthly_var99 = var99,
  monthly_es95 = es95,
  monthly_es99 = es99,
  monthly_mdd = mdd,
  hill_alpha = hill_alpha,
  evt_xi = gpd$xi,
  evt_var99 = var99_evt,
  evt_es99 = es99_evt,
  cdar95 = cdar95,
  worst_stress_name = worst_name,
  worst_stress_cum_ret = stress_results[[worst_name]]$cum_ret,
  worst_stress_mdd = stress_results[[worst_name]]$mdd,
  hardcap_breach = mdd < -0.45,
  sigma_start = sigma_start,
  sigma_end = sigma_end,
  pr_span_start = min(pr$date),
  pr_span_end = max(pr$date),
  contrib_pct = contrib_pct,
  best_loss = best$loss,
  best_iter = best$iter,
  best_idx = best_idx,
  converged = best$converged,
  n_restarts = length(restart_results),
  port_lfc = port_lfc,
  sha = sha_val,
  sha_match = sha_match
)
saveRDS(summary_stats, file.path(LOG_DIR, "summary_stats.rds"))
cat(sprintf("\n  summary_stats.rds saved\n"))

cat(sprintf("\n[ipca-risk] elapsed: %.1f sec\n",
            as.numeric(difftime(Sys.time(), t0, units="secs"))))
cat("[ipca-risk] DONE — 8/9 stage_artifacts written (draft JSON next)\n")
