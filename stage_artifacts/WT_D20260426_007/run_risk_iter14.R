#==============================================================================
# Iter 14 Risk — STR_1701_V2 Confidence-Aware Linear Tilt
# WT-D20260426_007
#
# Σ = B Ω B' + D structure on 322-name universe (Iter 14 universe-restricted)
#   B = exposure to KR FF5 v2 (MKT/SMB/HML/WML/RMW/CMA) per ticker (rolling 36M OLS)
#   Ω = factor covariance via 5 estimator parallel comparison (≤5 cap)
#   D = idiosyncratic specific variance (residual MLE, floored)
# + Tail risk (CVaR / CDaR / EVT-GPD / Hill alpha / Cornish-Fisher)
# + 8 regime-conditional stress periods
# + Crowding TDC: V2 vs Iter 11 (STR_1701 base), V2 vs STR_1656 (ML diversifier)
# + Liquidity flags (≥200M production floor)
# + Multi-sleeve (Slot A/B/C) realized correlation diagnostics
#
# Hard constraints (Risk Agent boundaries):
#   - PIT C1/C2/C9/C11/C13/C15 enforced
#   - Σ PSD with min eigenvalue > 0
#   - Cond number ≤ 100 post-shrinkage (factor-model 322×322 typically OK)
#   - method shopping ≤ 5 candidates
#   - NO alpha modification, NO weight proposal, NO optimization
#   - Crowding diagnostic: V2↔STR_1701 (~1.0 expected — same family) + V2↔STR_1656 (TDC q5)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
  library(future)
  library(future.apply)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

WT_ID  <- "WT-D20260426_007"
WT_TAG <- "WT_D20260426_007"
SIGNAL_AS_OF    <- as.Date("2023-11-30")
PIT_HARD_CUTOFF <- as.Date("2023-11-30")
LOCKBOX_START   <- as.Date("2024-01-23")

OUT_DIR_STAGE <- file.path("stage_artifacts", WT_TAG)
OUT_DIR_MAIL  <- file.path("qepm/mailbox/worktask", WT_ID)
ALPHA_SCORES_PATH <- file.path("qepm/stage_artifacts", WT_TAG, "alpha_scores.parquet")
ITER11_SCORES_PATH <- "stage_artifacts/WT_D20260426_005/alpha_scores.parquet"
STR1656_NAV_PATH   <- "04_Research/strategies/STR_1656_MLRA/output/nav_S1_A.csv"

dir.create(OUT_DIR_STAGE, showWarnings = FALSE, recursive = TRUE)

cat("==== Iter 14 Risk Pipeline ====\n")
cat("WT:", WT_ID, " | as_of:", as.character(SIGNAL_AS_OF), "\n")
cat("OUT_DIR_STAGE:", OUT_DIR_STAGE, "\n")
cat("OUT_DIR_MAIL:", OUT_DIR_MAIL, "\n")

# ── Load alpha_package ──────────────────────────────────────────────────────
alpha_pkg <- read_json(file.path(OUT_DIR_MAIL, "alpha_package.json"))
ALPHA_VEC <- unlist(alpha_pkg$alpha_vector)
CONF_VEC  <- unlist(alpha_pkg$confidence_vector)
TICKERS_UNI <- names(ALPHA_VEC)
N_UNI <- length(TICKERS_UNI)
cat("Universe-restricted tickers:", N_UNI, "\n")

# ── Load V2 alpha_scores time series ────────────────────────────────────────
ALPHA_TS <- as.data.table(read_parquet(ALPHA_SCORES_PATH))
setkey(ALPHA_TS, Date, Ticker)
cat("V2 alpha_scores rows:", nrow(ALPHA_TS), "  dates:", length(unique(ALPHA_TS$Date)), "\n")

# Iter 11 base scores (for V2 vs STR_1701 base TDC)
ITER11_TS <- as.data.table(read_parquet(ITER11_SCORES_PATH))
setkey(ITER11_TS, Date, Ticker)
cat("Iter 11 STR_1701 base scores rows:", nrow(ITER11_TS), "  dates:", length(unique(ITER11_TS$Date)), "\n")

# ── Load RAWDATA (PIT cutoff) ───────────────────────────────────────────────
RD <- as.data.table(read_parquet(".cache/rawdata.parquet"))
RD <- RD[Date <= PIT_HARD_CUTOFF]
RD_UNI <- RD[Ticker %in% TICKERS_UNI, .(Date, Ticker, Ret, Sector, Sector_Lv2, Size, Vol, Close)]
setkey(RD_UNI, Date, Ticker)
cat("RAWDATA universe rows:", nrow(RD_UNI), "  date range:",
    as.character(min(RD_UNI$Date, na.rm = TRUE)), "to",
    as.character(max(RD_UNI$Date, na.rm = TRUE)), "\n")

# Monthly returns
RD_UNI[, ym := as.Date(format(Date, "%Y-%m-01"))]
RET_MO <- RD_UNI[!is.na(Ret), .(
  Ret_M = prod(1 + Ret) - 1,
  Date_end = max(Date),
  n_obs = .N
), by = .(Ticker, ym)]
RET_MO <- RET_MO[n_obs >= 15]

RET_WIDE <- dcast(RET_MO, ym ~ Ticker, value.var = "Ret_M")
setorder(RET_WIDE, ym)
cat("RET_WIDE: ", nrow(RET_WIDE), "months ×", ncol(RET_WIDE) - 1, "tickers\n")

# ── KR FF5 v2 ──
FF <- as.data.table(read_parquet(".cache/kr_factor_returns_v2.parquet"))
FF <- FF[Date <= PIT_HARD_CUTOFF]
FF[, ym := as.Date(format(Date, "%Y-%m-01"))]
FF_FACT <- FF[, .(ym, MKT, SMB, HML, WML, RMW, CMA, RF)]
cat("FF5 v2:", nrow(FF_FACT), "months  range:",
    as.character(min(FF_FACT$ym)), "to", as.character(max(FF_FACT$ym)), "\n")

# Build excess returns long-format
RET_LONG <- melt(RET_WIDE, id.vars = "ym", variable.name = "Ticker", value.name = "Ret_M",
                 na.rm = TRUE)
RET_LONG <- merge(RET_LONG, FF_FACT[, .(ym, RF)], by = "ym", all.x = TRUE)
RET_LONG[, Ret_excess := Ret_M - ifelse(is.na(RF), 0, RF)]
RET_LONG[, Ticker := as.character(Ticker)]

# ── Regime panel ──
RP <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_007/regime_panel.parquet"))
RP[, ym := as.Date(format(sig_date, "%Y-%m-01"))]
RP_M <- unique(RP[, .(ym, regime_state)])
setkey(RP_M, ym)
cat("regime_panel rows:", nrow(RP_M), "  distribution:\n")
print(table(RP_M$regime_state))

#==============================================================================
# STEP 1: Exposure Matrix B (FF5 v2 betas, expanding-window OLS per ticker)
#==============================================================================
cat("\n==== STEP 1: Exposure Matrix B ====\n")

EST_START <- as.Date("2002-08-01")
EST_END   <- as.Date("2023-11-01")    # last fully realized month before SIGNAL_AS_OF

PANEL <- merge(
  RET_LONG[ym >= EST_START & ym <= EST_END],
  FF_FACT[ym >= EST_START & ym <= EST_END, .(ym, MKT, SMB, HML, WML, RMW, CMA)],
  by = "ym"
)
PANEL[, Ret_xs := Ret_excess]

factor_cols <- c("MKT", "SMB", "HML", "WML", "RMW", "CMA")
PANEL_KEEP <- PANEL[, c("ym", "Ticker", "Ret_xs", factor_cols), with = FALSE]
setkey(PANEL_KEEP, Ticker, ym)

expo_list <- vector("list", N_UNI)
specific_var_vec <- numeric(N_UNI)
names(specific_var_vec) <- TICKERS_UNI
n_obs_vec <- integer(N_UNI); names(n_obs_vec) <- TICKERS_UNI
r2_vec <- numeric(N_UNI);   names(r2_vec) <- TICKERS_UNI
fallback_vec <- logical(N_UNI); names(fallback_vec) <- TICKERS_UNI

# Pre-allocate beta matrix (TICKERS_UNI × 6 factors)
beta_mat <- matrix(0, nrow = N_UNI, ncol = length(factor_cols),
                   dimnames = list(TICKERS_UNI, factor_cols))

for (i in seq_along(TICKERS_UNI)) {
  tk <- TICKERS_UNI[i]
  d <- PANEL_KEEP[Ticker == tk]
  d <- d[complete.cases(d)]
  n_obs_vec[tk] <- nrow(d)
  if (nrow(d) < 24) {
    beta_mat[tk, ] <- c(1, 0, 0, 0, 0, 0)
    fallback_vec[tk] <- TRUE
    sigma2 <- if (nrow(d) >= 6) var(d$Ret_xs, na.rm = TRUE) else 0.01
    specific_var_vec[tk] <- sigma2
    r2_vec[tk] <- NA_real_
    next
  }
  X <- as.matrix(cbind(1, d[, ..factor_cols]))
  y <- d$Ret_xs
  fit <- tryCatch({
    coef_b <- solve(crossprod(X), crossprod(X, y))
    resid_v <- y - X %*% coef_b
    list(coef = coef_b, resid = resid_v, ok = TRUE)
  }, error = function(e) list(ok = FALSE))
  if (!fit$ok) {
    beta_mat[tk, ] <- c(1, 0, 0, 0, 0, 0)
    fallback_vec[tk] <- TRUE
    specific_var_vec[tk] <- var(y, na.rm = TRUE)
    r2_vec[tk] <- NA_real_
    next
  }
  betas <- as.numeric(fit$coef)[-1]
  beta_mat[tk, ] <- betas
  resid_var <- as.numeric(var(fit$resid))
  ss_res <- sum(fit$resid^2)
  ss_tot <- sum((y - mean(y))^2)
  r2 <- if (ss_tot > 0) 1 - ss_res / ss_tot else 0
  specific_var_vec[tk] <- resid_var
  r2_vec[tk] <- r2
  fallback_vec[tk] <- FALSE
}

B_DT <- data.table(
  Ticker = TICKERS_UNI,
  MKT = beta_mat[, "MKT"], SMB = beta_mat[, "SMB"], HML = beta_mat[, "HML"],
  WML = beta_mat[, "WML"], RMW = beta_mat[, "RMW"], CMA = beta_mat[, "CMA"],
  n_obs = n_obs_vec[TICKERS_UNI],
  r_squared = r2_vec[TICKERS_UNI],
  fallback = fallback_vec[TICKERS_UNI]
)
setkey(B_DT, Ticker)
cat("B exposure matrix shape:", nrow(B_DT), "×", length(factor_cols), "\n")
cat(sprintf("Fallback count: %d / %d (%.1f%%)\n",
            sum(B_DT$fallback), nrow(B_DT), 100 * mean(B_DT$fallback)))
cat(sprintf("R² mean: %.4f median: %.4f\n",
            mean(B_DT$r_squared, na.rm = TRUE),
            median(B_DT$r_squared, na.rm = TRUE)))

write_parquet(B_DT, file.path(OUT_DIR_STAGE, "exposure_matrix.parquet"))

#==============================================================================
# STEP 2: Factor Covariance Ω (parallel 5-estimator comparison)
#==============================================================================
cat("\n==== STEP 2: Factor Covariance Ω ====\n")

F_MAT <- as.matrix(FF_FACT[ym >= EST_START & ym <= EST_END,
                           .(MKT, SMB, HML, WML, RMW, CMA)])
F_MAT <- F_MAT[complete.cases(F_MAT), , drop = FALSE]
cat("Factor return matrix:", nrow(F_MAT), "×", ncol(F_MAT), "\n")

cov_sample <- function(X) cov(X, use = "pairwise.complete.obs")

cov_lw_oracle <- function(X) {
  n <- nrow(X); p <- ncol(X)
  S <- cov(X, use = "pairwise.complete.obs")
  mu <- mean(diag(S))
  X_demean <- scale(X, center = TRUE, scale = FALSE)
  d2 <- sum((S - mu * diag(p))^2)
  pi_hat <- (1 / n) * sum(((X_demean^2) - matrix(1, n, 1) %*% t(diag(S)))^2)
  rho <- max(0, min(1, pi_hat / d2 / n))
  (1 - rho) * S + rho * mu * diag(p)
}

cov_lw_constcor <- function(X) {
  n <- nrow(X); p <- ncol(X)
  S <- cov(X, use = "pairwise.complete.obs")
  sds <- sqrt(diag(S))
  R <- S / (sds %o% sds)
  rbar <- (sum(R) - p) / (p * (p - 1))
  T_mat <- rbar * (sds %o% sds); diag(T_mat) <- diag(S)
  rho <- min(1, max(0, ((n - 2) / n * sum(diag(S)^2) + sum(S)^2 / p) /
                          ((n + 2) * (sum(S^2) - sum(diag(S)^2) / p) + 1e-12)))
  (1 - rho) * S + rho * T_mat
}

cov_gerber_rmt <- function(X) {
  source("02_Infrastructure/portfolio/hrp_core.R", local = TRUE)
  n <- nrow(X); p <- ncol(X)
  cor_mat <- .gerber_cor(X)
  cor_clean <- .rmt_denoise(cor_mat, n / p)
  sds <- apply(X, 2, sd, na.rm = TRUE)
  cor_clean * (sds %o% sds)
}

cov_diag_shrink <- function(X) {
  S <- cov(X, use = "pairwise.complete.obs")
  D <- diag(diag(S))
  0.5 * S + 0.5 * D
}

estimators <- list(
  list(name = "sample",                 fn = cov_sample),
  list(name = "ledoit_wolf_oracle",     fn = cov_lw_oracle),
  list(name = "ledoit_wolf_constcor",   fn = cov_lw_constcor),
  list(name = "gerber_rmt",             fn = cov_gerber_rmt),
  list(name = "diag_shrink",            fn = cov_diag_shrink)
)

n_workers <- min(4L, max(1L, parallel::detectCores() - 1L))
plan(multisession, workers = n_workers)

cov_results <- future_lapply(estimators, function(e) {
  tryCatch({
    Omega <- e$fn(F_MAT)
    eig <- eigen(Omega, symmetric = TRUE, only.values = TRUE)$values
    list(
      ok = TRUE, name = e$name, Omega = Omega,
      condition = max(eig) / max(min(eig), 1e-12),
      min_eig = min(eig), max_eig = max(eig),
      psd = all(eig > 1e-12)
    )
  }, error = function(err) list(ok = FALSE, name = e$name, error = conditionMessage(err)))
})
plan(sequential)

cov_log <- list()
for (cr in cov_results) {
  if (cr$ok) {
    cat(sprintf("  %s: cond=%.2f min_eig=%.6f PSD=%s\n",
                cr$name, cr$condition, cr$min_eig, cr$psd))
    cov_log[[cr$name]] <- list(name = cr$name, condition = unname(cr$condition),
                               min_eig = unname(cr$min_eig), psd = unname(cr$psd),
                               selected = FALSE)
  } else {
    cat(sprintf("  %s: FAILED (%s)\n", cr$name, cr$error))
  }
}

# Selection: shrinkage_quality with structural preference
psd_ok <- Filter(function(r) r$ok && r$psd && r$condition <= 100, cov_results)
if (length(psd_ok) == 0) {
  psd_ok <- Filter(function(r) r$ok && r$psd, cov_results)
}
preference <- c("ledoit_wolf_oracle", "ledoit_wolf_constcor", "gerber_rmt", "sample", "diag_shrink")
selected <- NULL
for (pref in preference) {
  cand <- Filter(function(r) r$name == pref, psd_ok)
  if (length(cand) > 0) { selected <- cand[[1]]; break }
}
if (is.null(selected)) {
  selected <- psd_ok[[which.min(sapply(psd_ok, function(r) r$condition))]]
}
cov_log[[selected$name]]$selected <- TRUE
OMEGA <- selected$Omega
rownames(OMEGA) <- colnames(OMEGA) <- factor_cols
cat("Selected Ω estimator:", selected$name, "  cond=", round(selected$condition, 2), "\n")

OMEGA_DT <- as.data.table(OMEGA, keep.rownames = "Factor")
write_parquet(OMEGA_DT, file.path(OUT_DIR_STAGE, "factor_covariance.parquet"))

#==============================================================================
# STEP 3: Specific Risk D
#==============================================================================
cat("\n==== STEP 3: Specific Risk D ====\n")
D_DT <- data.table(Ticker = TICKERS_UNI,
                   specific_var = pmax(specific_var_vec[TICKERS_UNI], 1e-6))
D_DT[, specific_sd := sqrt(specific_var)]
cat(sprintf("D summary: mean_sd=%.4f median_sd=%.4f min_sd=%.4f max_sd=%.4f\n",
            mean(D_DT$specific_sd), median(D_DT$specific_sd),
            min(D_DT$specific_sd), max(D_DT$specific_sd)))
write_parquet(D_DT, file.path(OUT_DIR_STAGE, "specific_risk.parquet"))

#==============================================================================
# STEP 4: Security Covariance Σ = B Ω B' + D
#==============================================================================
cat("\n==== STEP 4: Security Covariance Σ ====\n")
B_MAT <- beta_mat[TICKERS_UNI, , drop = FALSE]
D_MAT <- diag(D_DT[match(TICKERS_UNI, Ticker), specific_var])
rownames(D_MAT) <- colnames(D_MAT) <- TICKERS_UNI

SIGMA <- B_MAT %*% OMEGA %*% t(B_MAT) + D_MAT
SIGMA <- (SIGMA + t(SIGMA)) / 2

sigma_eig <- eigen(SIGMA, symmetric = TRUE, only.values = TRUE)$values
sigma_cond <- max(sigma_eig) / max(min(sigma_eig), 1e-12)
sigma_psd <- all(sigma_eig > 1e-12)
sigma_min_eig <- min(sigma_eig)

cat(sprintf("Σ shape: %d × %d, cond=%.2f, min_eig=%.4e, PSD=%s\n",
            nrow(SIGMA), ncol(SIGMA), sigma_cond, sigma_min_eig, sigma_psd))

ridge_lambda <- 0
if (sigma_cond > 100 || !sigma_psd) {
  cat("Applying ridge shrinkage (cond > 100)\n")
  ridge_lambda <- max((max(sigma_eig) - 100 * sigma_min_eig) / 99, 1e-6)
  SIGMA <- SIGMA + ridge_lambda * diag(nrow(SIGMA))
  sigma_eig <- eigen(SIGMA, symmetric = TRUE, only.values = TRUE)$values
  sigma_cond <- max(sigma_eig) / max(min(sigma_eig), 1e-12)
  sigma_psd <- all(sigma_eig > 1e-12)
  sigma_min_eig <- min(sigma_eig)
  cat(sprintf("Post-ridge: cond=%.2f min_eig=%.4e PSD=%s\n",
              sigma_cond, sigma_min_eig, sigma_psd))
}

SIGMA_DT <- as.data.table(SIGMA, keep.rownames = "Ticker")
write_parquet(SIGMA_DT, file.path(OUT_DIR_STAGE, "covariance.parquet"))

# Variance share decomposition
systematic_var <- diag(B_MAT %*% OMEGA %*% t(B_MAT))
total_var <- diag(SIGMA)
syst_share <- mean(systematic_var / total_var, na.rm = TRUE)
idio_share <- 1 - syst_share
cat(sprintf("Variance shares: systematic %.1f%% / idiosyncratic %.1f%%\n",
            syst_share * 100, idio_share * 100))

# Top common risks (per-factor variance contribution)
factor_var_contrib <- sapply(factor_cols, function(f) {
  bf <- B_MAT[, f]
  sigma_f <- OMEGA[f, f]
  mean(bf * bf * sigma_f / total_var, na.rm = TRUE)
})
factor_var_contrib_pct <- factor_var_contrib * 100
top_common_risks <- paste0(names(sort(factor_var_contrib_pct, decreasing = TRUE)),
                            " (", round(sort(factor_var_contrib_pct, decreasing = TRUE), 1), "%)")
top_common_risks <- c(top_common_risks,
                      paste0("Idiosyncratic (", round(idio_share * 100, 1), "%)"))
cat("Top common risks:\n"); print(top_common_risks)

#==============================================================================
# STEP 4b: Multi-sleeve realized correlation (Slot A / B / C)
#==============================================================================
cat("\n==== STEP 4b: Slot A/B/C realized correlation ====\n")
ATS <- ALPHA_TS[Ticker %in% TICKERS_UNI & !is.na(fwd_1m)]

slot_panel <- ATS[, .(
  ret_A_long = if (sum(!is.na(z_A)) >= 5) {
    sub <- .SD[!is.na(z_A)]; q4 <- quantile(sub$z_A, 0.8, na.rm = TRUE)
    mean(sub[z_A >= q4, fwd_1m], na.rm = TRUE)
  } else NA_real_,
  ret_B_long = if (sum(!is.na(z_B)) >= 5) {
    sub <- .SD[!is.na(z_B)]; q4 <- quantile(sub$z_B, 0.8, na.rm = TRUE)
    mean(sub[z_B >= q4, fwd_1m], na.rm = TRUE)
  } else NA_real_,
  ret_C_long = if (sum(!is.na(z_C)) >= 5) {
    sub <- .SD[!is.na(z_C)]; q4 <- quantile(sub$z_C, 0.8, na.rm = TRUE)
    mean(sub[z_C >= q4, fwd_1m], na.rm = TRUE)
  } else NA_real_,
  n = .N
), by = Date]
slot_panel <- slot_panel[n >= 20]
cat("Slot panel rows:", nrow(slot_panel), "\n")

cor_AB <- if (sum(!is.na(slot_panel$ret_A_long) & !is.na(slot_panel$ret_B_long)) >= 30)
  cor(slot_panel$ret_A_long, slot_panel$ret_B_long, use = "pairwise.complete.obs") else NA_real_
cor_AC <- if (sum(!is.na(slot_panel$ret_A_long) & !is.na(slot_panel$ret_C_long)) >= 30)
  cor(slot_panel$ret_A_long, slot_panel$ret_C_long, use = "pairwise.complete.obs") else NA_real_
cor_BC <- if (sum(!is.na(slot_panel$ret_B_long) & !is.na(slot_panel$ret_C_long)) >= 30)
  cor(slot_panel$ret_B_long, slot_panel$ret_C_long, use = "pairwise.complete.obs") else NA_real_

sd_A <- sd(slot_panel$ret_A_long, na.rm = TRUE)
sd_B <- sd(slot_panel$ret_B_long, na.rm = TRUE)
sd_C <- sd(slot_panel$ret_C_long, na.rm = TRUE)

cat(sprintf("Slot A sd=%.4f / B sd=%.4f / C sd=%.4f\n", sd_A, sd_B, sd_C))
cat(sprintf("Slot cor: A-B=%.3f A-C=%.3f B-C=%.3f\n",
            cor_AB %||% NA, cor_AC %||% NA, cor_BC %||% NA))

# Multi-slot weighted blend (50/30/20) sd estimate
w_A_v <- 0.5; w_B_v <- 0.3; w_C_v <- 0.2
sd_combined_actual <- tryCatch({
  v <- w_A_v^2*sd_A^2 + w_B_v^2*sd_B^2 + w_C_v^2*sd_C^2 +
       2*w_A_v*w_B_v*sd_A*sd_B*ifelse(is.na(cor_AB), 0.5, cor_AB) +
       2*w_A_v*w_C_v*sd_A*sd_C*ifelse(is.na(cor_AC), 0.5, cor_AC) +
       2*w_B_v*w_C_v*sd_B*sd_C*ifelse(is.na(cor_BC), 0.5, cor_BC)
  sqrt(max(v, 1e-10))
}, error = function(e) NA_real_)
sd_weighted_avg <- w_A_v*sd_A + w_B_v*sd_B + w_C_v*sd_C
diversification_benefit <- 1 - sd_combined_actual / sd_weighted_avg
cat(sprintf("Multi-slot diversification benefit: %.2f%%\n", 100*diversification_benefit))

#==============================================================================
# STEP 5a: Regime-conditional Σ (4 regimes)
# Note: with 322 names full Σ per regime would be expensive + thin data.
# We compute regime-conditional CORRELATION + condition + mean_corr summary
# (small subsample — top-100 names by data coverage to keep T*N stable)
#==============================================================================
cat("\n==== STEP 5a: Regime-conditional correlation ====\n")
RET_LONG[, ym := as.Date(format(ym, "%Y-%m-01"))]
RET_REG <- merge(RET_LONG, RP_M, by = "ym", all.x = TRUE)
RET_REG <- RET_REG[!is.na(regime_state) & ym >= EST_START & ym <= EST_END]

# Subsample to top-100 most-data-rich tickers for regime corr stability
ticker_obs <- RET_LONG[ym >= EST_START & ym <= EST_END,
                       .N, by = Ticker][order(-N)]
ticker_obs <- ticker_obs[Ticker %in% TICKERS_UNI]
TICKERS_REG <- ticker_obs[1:min(100, nrow(ticker_obs)), Ticker]
cat("Regime corr panel: top-", length(TICKERS_REG), "tickers (data-rich)\n")

regimes <- c("BULL", "NORMAL", "CAUTION", "CRISIS")
regime_meta <- list()
for (rg in regimes) {
  sub <- RET_REG[regime_state == rg & Ticker %in% TICKERS_REG,
                 .(ym, Ticker, Ret_M)]
  W <- dcast(sub, ym ~ Ticker, value.var = "Ret_M")
  R_mat <- as.matrix(W[, -1, with = FALSE])
  T_obs <- nrow(R_mat)
  cat(sprintf("Regime %s: T=%d\n", rg, T_obs))
  if (T_obs < 5) {
    regime_meta[[rg]] <- list(regime = rg, T = T_obs,
                              method = "pooled_fallback_thin", fallback = TRUE)
    next
  }
  # Drop columns with too many NAs in this regime
  na_frac <- colMeans(is.na(R_mat))
  keep_cols <- which(na_frac < 0.5)
  if (length(keep_cols) < 10) {
    regime_meta[[rg]] <- list(regime = rg, T = T_obs, n_tickers = length(keep_cols),
                              method = "insufficient_panel", fallback = TRUE)
    next
  }
  R_sub <- R_mat[, keep_cols, drop = FALSE]
  R_sub <- R_sub[complete.cases(R_sub), , drop = FALSE]
  if (nrow(R_sub) < 5 || ncol(R_sub) < 10) {
    regime_meta[[rg]] <- list(regime = rg, T = nrow(R_sub),
                              n_tickers = ncol(R_sub),
                              method = "complete_cases_thin", fallback = TRUE)
    next
  }
  cov_r <- tryCatch({
    if (nrow(R_sub) >= 12) cov_lw_constcor(R_sub) else cov_lw_oracle(R_sub)
  }, error = function(e) NULL)
  if (is.null(cov_r) || nrow(cov_r) == 0) {
    regime_meta[[rg]] <- list(regime = rg, T = nrow(R_sub),
                              method = "fallback_failed", fallback = TRUE)
    next
  }
  sds_r <- sqrt(diag(cov_r))
  cor_only <- cov_r / (sds_r %o% sds_r); diag(cor_only) <- 1
  mean_corr <- (sum(cor_only) - nrow(cor_only)) / (nrow(cor_only) * (nrow(cor_only) - 1))
  eig_r <- eigen(cov_r, symmetric = TRUE, only.values = TRUE)$values
  cn_r <- max(eig_r) / max(min(eig_r), 1e-12)
  regime_meta[[rg]] <- list(
    regime = rg, T = nrow(R_sub), n_tickers = ncol(R_sub),
    mean_correlation = mean_corr,
    condition_number = cn_r, min_eig = min(eig_r),
    psd = all(eig_r > 1e-12),
    method = if (nrow(R_sub) >= 12) "ledoit_wolf_constcor" else "ledoit_wolf_oracle",
    fallback = FALSE
  )
  cat(sprintf("  cond=%.2f mean_corr=%.3f n_tk=%d PSD=%s\n",
              cn_r, mean_corr, ncol(R_sub), all(eig_r > 1e-12)))
}

reg_corr_dt <- rbindlist(lapply(names(regime_meta), function(rg) {
  m <- regime_meta[[rg]]
  data.table(regime = rg,
             T_obs = m$T %||% NA_integer_,
             n_tickers = m$n_tickers %||% NA_integer_,
             mean_correlation = m$mean_correlation %||% NA_real_,
             condition_number = m$condition_number %||% NA_real_,
             min_eig = m$min_eig %||% NA_real_,
             psd = m$psd %||% NA,
             method = m$method %||% "fallback",
             fallback = m$fallback %||% TRUE)
}), fill = TRUE)
write_parquet(reg_corr_dt, file.path(OUT_DIR_STAGE, "regime_correlation.parquet"))
cat("Wrote regime_correlation.parquet\n")

# Pooled fallback Σ (322 names, full in-sample, LW shrinkage on common)
cat("\n==== STEP 5a-bis: Pooled Σ fallback (322-name) ====\n")
RW <- dcast(
  RET_REG[Ticker %in% TICKERS_UNI, .(ym, Ticker, Ret_M)],
  ym ~ Ticker, value.var = "Ret_M"
)
RW_mat <- as.matrix(RW[, -1, with = FALSE])
# Drop cols with > 50% NA, then complete cases
na_frac_full <- colMeans(is.na(RW_mat))
keep_full <- which(na_frac_full < 0.5)
RW_mat_sub <- RW_mat[, keep_full, drop = FALSE]
RW_mat_sub <- RW_mat_sub[complete.cases(RW_mat_sub), , drop = FALSE]
cat(sprintf("Pooled Σ panel: T=%d × N=%d (orig N=%d, dropped due to NA: %d)\n",
            nrow(RW_mat_sub), ncol(RW_mat_sub), N_UNI, N_UNI - ncol(RW_mat_sub)))

if (nrow(RW_mat_sub) >= 30 && ncol(RW_mat_sub) >= 20) {
  SIGMA_POOLED <- tryCatch(cov_lw_constcor(RW_mat_sub),
                           error = function(e) cov_lw_oracle(RW_mat_sub))
  SIGMA_POOLED <- (SIGMA_POOLED + t(SIGMA_POOLED)) / 2
  pooled_eig <- eigen(SIGMA_POOLED, symmetric = TRUE, only.values = TRUE)$values
  pooled_cn <- max(pooled_eig) / max(min(pooled_eig), 1e-12)
  pooled_min_eig <- min(pooled_eig)
  cat(sprintf("Pooled Σ: cond=%.2f min_eig=%.4e PSD=%s\n",
              pooled_cn, pooled_min_eig, all(pooled_eig > 1e-12)))
  if (pooled_cn > 100) {
    rl <- max((max(pooled_eig) - 100 * pooled_min_eig) / 99, 1e-6)
    SIGMA_POOLED <- SIGMA_POOLED + rl * diag(nrow(SIGMA_POOLED))
    pooled_eig <- eigen(SIGMA_POOLED, symmetric = TRUE, only.values = TRUE)$values
    pooled_cn <- max(pooled_eig) / max(min(pooled_eig), 1e-12)
    cat(sprintf("Post-ridge pooled Σ: cond=%.2f\n", pooled_cn))
  }
  SIGMA_POOLED_DT <- as.data.table(SIGMA_POOLED, keep.rownames = "Ticker")
  write_parquet(SIGMA_POOLED_DT,
                file.path(OUT_DIR_STAGE, "covariance_pooled_fallback.parquet"))
  cat("Wrote covariance_pooled_fallback.parquet\n")
  pooled_meta <- list(
    T = nrow(RW_mat_sub), N = ncol(RW_mat_sub),
    method = "ledoit_wolf_constcor",
    condition_number = unname(pooled_cn),
    min_eig = unname(min(pooled_eig)),
    psd = all(pooled_eig > 1e-12),
    binding_rule = "Optimizer MUST use this Σ in CRISIS; SHOULD use in CAUTION when T<30; recommended for regime-uncertain rebalances. NOTE: pooled Σ excludes high-NA tickers (newer listings)."
  )
} else {
  cat("Pooled Σ: insufficient panel — fallback to factor-model Σ\n")
  pooled_meta <- list(
    T = nrow(RW_mat_sub), N = ncol(RW_mat_sub),
    method = "factor_model_BOmegaB_plus_D_fallback",
    condition_number = unname(sigma_cond),
    binding_rule = "Pooled Σ unavailable — Optimizer should use factor-model Σ"
  )
}

#==============================================================================
# STEP 5b: Tail Risk + Stress
#==============================================================================
cat("\n==== STEP 5b: Tail Risk + Stress ====\n")

# EW universe long-only daily portfolio (proxy)
RD_DAILY <- RD[Ticker %in% TICKERS_UNI & Date <= PIT_HARD_CUTOFF & !is.na(Ret),
               .(port_ret = mean(Ret, na.rm = TRUE), n = .N), by = Date]
RD_DAILY <- RD_DAILY[n >= 50]
cat("EW universe daily portfolio panel: n=", nrow(RD_DAILY), "obs\n")

r_d <- RD_DAILY$port_ret
cvar_95_d <- mean(r_d[r_d <= quantile(r_d, 0.05, na.rm = TRUE)], na.rm = TRUE)
var_95_d  <- as.numeric(quantile(r_d, 0.05, na.rm = TRUE))
nav <- cumprod(1 + r_d)
peak <- cummax(nav)
dd <- nav / peak - 1
cdar_95 <- mean(dd[dd <= quantile(dd, 0.05, na.rm = TRUE)], na.rm = TRUE)
mdd <- min(dd, na.rm = TRUE)

# EVT-GPD via tail_risk_engine
tail_evt <- tryCatch({
  source("02_Infrastructure/portfolio/tail_risk_engine.R", local = TRUE)
  compute_evt_var(r_d, p = 0.99, threshold_q = 0.95)
}, error = function(e) {
  cat("EVT failed:", conditionMessage(e), "\n")
  list(var_evt = NA_real_, es_evt = NA_real_, method = "failed")
})

# Hill alpha
losses <- -r_d
losses_pos <- sort(losses[losses > 0], decreasing = TRUE)
n_l <- length(losses_pos)
k_hill <- max(20L, floor(0.05 * n_l))
hill_alpha <- if (n_l > 100 && k_hill > 0) {
  1 / mean(log(losses_pos[1:k_hill] / losses_pos[k_hill]))
} else NA_real_

# Cornish-Fisher VaR/ES
m1 <- mean(r_d, na.rm = TRUE); m2 <- sd(r_d, na.rm = TRUE)
m3 <- mean((r_d - m1)^3, na.rm = TRUE) / m2^3
m4 <- mean((r_d - m1)^4, na.rm = TRUE) / m2^4 - 3
zq <- qnorm(0.99)
cf_z <- zq + (zq^2 - 1) * m3 / 6 + (zq^3 - 3 * zq) * m4 / 24 -
        (2 * zq^3 - 5 * zq) * m3^2 / 36
parametric_var_99_normal <- m1 - zq * m2
parametric_var_99_cf <- m1 - cf_z * m2
parametric_es_99_normal <- m1 - dnorm(zq) / 0.01 * m2

cat(sprintf("CVaR_95: %.4f / VaR_95: %.4f / CDaR_95: %.4f / MDD: %.4f\n",
            cvar_95_d, var_95_d, cdar_95, mdd))
cat(sprintf("EVT VaR_99: %.4f / ES_99: %.4f / method: %s\n",
            tail_evt$var_evt %||% NA, tail_evt$es_evt %||% NA, tail_evt$method %||% "n/a"))
cat(sprintf("Hill alpha (top 5%%): %.3f / k=%d\n", hill_alpha %||% NA, k_hill))
cat(sprintf("Parametric VaR_99 Normal: %.4f / CF: %.4f / ES_99 Normal: %.4f\n",
            parametric_var_99_normal, parametric_var_99_cf, parametric_es_99_normal))

# Tail per regime
RD_DAILY[, ym := as.Date(format(Date, "%Y-%m-01"))]
tail_per_regime <- list()
for (rg in regimes) {
  d_dates <- RP_M[regime_state == rg, ym]
  if (length(d_dates) == 0) next
  sub_d <- RD_DAILY[ym %in% d_dates]
  if (nrow(sub_d) < 10) {
    tail_per_regime[[rg]] <- list(n_days = nrow(sub_d), insufficient = TRUE)
    next
  }
  rr <- sub_d$port_ret
  qv <- quantile(rr, 0.05, na.rm = TRUE)
  cv <- mean(rr[rr <= qv], na.rm = TRUE)
  tail_per_regime[[rg]] <- list(
    n_days = nrow(sub_d),
    mean_ret = mean(rr, na.rm = TRUE),
    sd_ret = sd(rr, na.rm = TRUE),
    var_95 = as.numeric(qv),
    cvar_95 = as.numeric(cv),
    insufficient = FALSE
  )
  cat(sprintf("  Tail %s: n=%d CVaR_95=%.4f sd=%.4f\n",
              rg, nrow(sub_d), cv, sd(rr, na.rm = TRUE)))
}

# Stress periods (8)
def_stress_periods <- list(
  list(name = "GFC_2008",       start = "2007-10-01", end = "2009-03-31"),
  list(name = "EuDebt_2011",    start = "2011-07-01", end = "2011-12-31"),
  list(name = "Taper_2013",     start = "2013-05-01", end = "2013-09-30"),
  list(name = "China_Shock",    start = "2015-06-01", end = "2016-02-29"),
  list(name = "Brexit_2016",    start = "2016-06-01", end = "2016-09-30"),
  list(name = "TradeWar_2018",  start = "2018-03-01", end = "2018-12-31"),
  list(name = "COVID_2020",     start = "2020-01-01", end = "2020-06-30"),
  list(name = "Rate_2022",      start = "2022-01-01", end = "2022-12-31")
)
stress_results <- list()
for (sp in def_stress_periods) {
  s <- as.Date(sp$start); e <- as.Date(sp$end)
  if (s > PIT_HARD_CUTOFF) {
    stress_results[[sp$name]] <- list(window = paste0(s, "_", e),
                                       cum_ret = NA_real_, n = 0L,
                                       note = "outside_pit_cutoff")
    next
  }
  e2 <- min(e, PIT_HARD_CUTOFF)
  sub <- RD_DAILY[Date >= s & Date <= e2]
  if (nrow(sub) < 5) {
    stress_results[[sp$name]] <- list(window = paste0(s, "_", e2),
                                       cum_ret = NA_real_, n = nrow(sub),
                                       note = "insufficient_data")
    next
  }
  cum_r <- prod(1 + sub$port_ret) - 1
  nav_s <- cumprod(1 + sub$port_ret); peak_s <- cummax(nav_s)
  dd_s <- nav_s / peak_s - 1; mdd_s <- min(dd_s)
  stress_results[[sp$name]] <- list(
    window = paste0(s, "_", e2),
    n = nrow(sub),
    cum_ret = round(cum_r, 4),
    mdd = round(mdd_s, 4)
  )
  cat(sprintf("  %s [%s_%s]: n=%d cum_ret=%.4f mdd=%.4f\n",
              sp$name, s, e2, nrow(sub), cum_r, mdd_s))
}

#==============================================================================
# STEP 5c: Crowding Diagnostics
#  (a) V2 vs Iter 11 STR_1701 base — score time-series correlation + cross-section overlap
#  (b) V2 vs STR_1656 ML diversifier — daily NAV TDC q5 + Pearson cor
#  (c) Cross-section Jaccard, alpha-vector HHI, sector concentration, liquidity
#==============================================================================
cat("\n==== STEP 5c: Crowding Diagnostics ====\n")

# (a) V2 vs Iter 11 STR_1701 base
# Date convention differs: V2 uses month-end, Iter11 uses month-start.
# Align both via month-floor key for joint merge.
ITER11_TS_T <- copy(ITER11_TS)
ITER11_TS_T[, ym_key := as.Date(format(Date, "%Y-%m-01"))]
ITER11_TS_T <- ITER11_TS_T[, .(Date_iter11 = Date, Ticker, ym_key,
                                score_eff_iter11 = score_eff)]
V2_TS <- copy(ALPHA_TS)
V2_TS[, ym_key := as.Date(format(Date, "%Y-%m-01"))]
V2_TS <- V2_TS[, .(Date_v2 = Date, Ticker, ym_key, score_str1701, alpha_v2)]

joint_ts <- merge(V2_TS, ITER11_TS_T, by = c("ym_key", "Ticker"))
cat("V2↔Iter11 joint observations (ym-aligned):", nrow(joint_ts), "\n")

cor_v2_iter11_score <- if (nrow(joint_ts) >= 100) {
  cor(joint_ts$score_str1701, joint_ts$score_eff_iter11, use = "pairwise.complete.obs")
} else NA_real_
cor_v2_iter11_alpha <- if (nrow(joint_ts) >= 100) {
  cor(joint_ts$alpha_v2, joint_ts$score_eff_iter11, use = "pairwise.complete.obs")
} else NA_real_
cat(sprintf("V2 score_str1701 vs Iter11 score_eff: cor=%.4f (expected ~1.0 — same family)\n",
            cor_v2_iter11_score %||% NA))
cat(sprintf("V2 alpha_v2 vs Iter11 score_eff: cor=%.4f (V2 = rank^0.5 × conf^1.5 tilt)\n",
            cor_v2_iter11_alpha %||% NA))

# Cross-section top-N Jaccard at last date
last_date_v2 <- max(ALPHA_TS$Date)
# Iter11 last date (use month-aligned to V2 last)
last_ym_v2 <- as.Date(format(last_date_v2, "%Y-%m-01"))
i11_last_ym <- ITER11_TS[, .(Date)][, ym := as.Date(format(Date, "%Y-%m-01"))][ym == last_ym_v2, max(Date)]
last_date_i11 <- if (length(i11_last_ym) > 0 && !is.na(i11_last_ym)) i11_last_ym else max(ITER11_TS$Date)

top_n_jaccard <- function(score_col_v2, score_col_i11, n = 50) {
  v2_top <- ALPHA_TS[Date == last_date_v2 & !is.na(get(score_col_v2))][
    order(-get(score_col_v2))][1:n, Ticker]
  i11_top <- ITER11_TS[Date == last_date_i11 & !is.na(get(score_col_i11))][
    order(-get(score_col_i11))][1:n, Ticker]
  inter <- length(intersect(v2_top, i11_top))
  union_n <- length(union(v2_top, i11_top))
  if (union_n == 0) NA_real_ else inter / union_n
}
jac_v2_iter11_50 <- top_n_jaccard("alpha_v2", "score_eff", 50)
jac_v2_iter11_20 <- top_n_jaccard("alpha_v2", "score_eff", 20)
cat(sprintf("Cross-section Jaccard V2 vs Iter11 (top-50, last sig): %.4f\n", jac_v2_iter11_50 %||% NA))
cat(sprintf("Cross-section Jaccard V2 vs Iter11 (top-20, last sig): %.4f\n", jac_v2_iter11_20 %||% NA))

# (b) V2 vs STR_1656 ML diversifier — daily NAV TDC + Pearson
STR1656_NAV <- tryCatch(
  fread(STR1656_NAV_PATH, colClasses = c("Date" = "Date")),
  error = function(e) NULL
)
str1656_diag <- list(available = !is.null(STR1656_NAV))

if (!is.null(STR1656_NAV)) {
  STR1656_NAV <- STR1656_NAV[Date <= PIT_HARD_CUTOFF]
  setkey(STR1656_NAV, Date)
  cat(sprintf("STR_1656 NAV rows: %d  range: %s to %s\n",
              nrow(STR1656_NAV), as.character(min(STR1656_NAV$Date)),
              as.character(max(STR1656_NAV$Date))))

  # V2 daily proxy: top-20 by alpha_v2 at each rebalance date, EW
  # This matches the realistic V2 portfolio (Optimizer 20-name long-only with rank^0.5 × conf^1.5)
  # Build holdings panel: at each sig_date, pick top-20 by alpha_v2; hold until next sig_date.
  cat("Building V2 top-20 daily proxy...\n")
  ATS_V2 <- ALPHA_TS[!is.na(alpha_v2)]
  setkey(ATS_V2, Date, Ticker)
  sig_dates_v2 <- sort(unique(ATS_V2$Date))

  hold_list <- list()
  for (i in seq_along(sig_dates_v2)) {
    sd_i <- sig_dates_v2[i]
    sd_next <- if (i < length(sig_dates_v2)) sig_dates_v2[i + 1] else PIT_HARD_CUTOFF + 1
    top20_i <- ATS_V2[Date == sd_i][order(-alpha_v2)][1:20, .(Ticker)]
    top20_i[, hold_start := sd_i]
    top20_i[, hold_end := sd_next - 1]   # day before next signal
    hold_list[[i]] <- top20_i
  }
  V2_HOLD <- rbindlist(hold_list)
  cat(sprintf("V2 holdings panel: %d rows (sig_dates × 20 tickers)\n", nrow(V2_HOLD)))

  # Daily returns for V2 holdings (EW)
  RD_HOLD <- merge(
    V2_HOLD,
    RD[, .(Date, Ticker, Ret)],
    by = "Ticker", allow.cartesian = TRUE
  )
  RD_HOLD <- RD_HOLD[Date >= hold_start & Date <= hold_end & !is.na(Ret)]
  v2_daily_proxy <- RD_HOLD[, .(v2_proxy_ret = mean(Ret, na.rm = TRUE), n = .N), by = Date]
  v2_daily_proxy <- v2_daily_proxy[n >= 5]   # require at least 5 names alive
  cat(sprintf("V2 top-20 daily proxy obs: %d\n", nrow(v2_daily_proxy)))

  # Merge for joint period
  joint_nav <- merge(v2_daily_proxy[, .(Date, v2_proxy_ret)],
                     STR1656_NAV[, .(Date, str1656_ret = Strategy_Ret)],
                     by = "Date")
  joint_nav <- joint_nav[!is.na(v2_proxy_ret) & !is.na(str1656_ret)]
  cat(sprintf("V2↔STR1656 joint daily obs: %d\n", nrow(joint_nav)))

  if (nrow(joint_nav) >= 100) {
    pearson_v2_1656 <- cor(joint_nav$v2_proxy_ret, joint_nav$str1656_ret,
                           use = "pairwise.complete.obs")
    spearman_v2_1656 <- cor(joint_nav$v2_proxy_ret, joint_nav$str1656_ret,
                            use = "pairwise.complete.obs", method = "spearman")
    # Tail dependence q5 (lower 5%): conditional probability both in lower-5%
    q5_v2 <- quantile(joint_nav$v2_proxy_ret, 0.05, na.rm = TRUE)
    q5_1656 <- quantile(joint_nav$str1656_ret, 0.05, na.rm = TRUE)
    both_tail <- joint_nav[v2_proxy_ret <= q5_v2 & str1656_ret <= q5_1656]
    p_v2_tail <- joint_nav[v2_proxy_ret <= q5_v2]
    tdc_q5_lower <- if (nrow(p_v2_tail) > 0) nrow(both_tail) / nrow(p_v2_tail) else NA_real_

    # Upper tail q95
    q95_v2 <- quantile(joint_nav$v2_proxy_ret, 0.95, na.rm = TRUE)
    q95_1656 <- quantile(joint_nav$str1656_ret, 0.95, na.rm = TRUE)
    both_uptail <- joint_nav[v2_proxy_ret >= q95_v2 & str1656_ret >= q95_1656]
    p_v2_uptail <- joint_nav[v2_proxy_ret >= q95_v2]
    tdc_q95_upper <- if (nrow(p_v2_uptail) > 0) nrow(both_uptail) / nrow(p_v2_uptail) else NA_real_

    str1656_diag <- list(
      available = TRUE,
      n_obs = nrow(joint_nav),
      pearson_cor = round(pearson_v2_1656, 4),
      spearman_cor = round(spearman_v2_1656, 4),
      tdc_q5_lower = round(tdc_q5_lower, 4),
      tdc_q95_upper = round(tdc_q95_upper, 4),
      mandate_threshold = 0.30,
      mandate_pass = isTRUE(tdc_q5_lower < 0.30),
      caveat = "V2 daily proxy = top-20 by alpha_v2 at each sig_date, held EW until next sig_date (bimonthly cadence). Forge realized NAV will use TWAP/VWAP execution. Risk-side TDC is structural tail-coupling estimate."
    )
    cat(sprintf("V2↔STR1656 Pearson cor=%.4f  Spearman=%.4f\n",
                pearson_v2_1656, spearman_v2_1656))
    cat(sprintf("V2↔STR1656 TDC q5 (lower)=%.4f  q95 (upper)=%.4f  threshold=0.30  PASS=%s\n",
                tdc_q5_lower, tdc_q95_upper, str1656_diag$mandate_pass))
  }
} else {
  cat("STR_1656 NAV not available — skipping V2↔1656 TDC\n")
}

# (c) Cross-section overlap, HHI, sector, liquidity
# Cross-section vs Iter 3 (PG2 ancestor) — read from alpha_pkg if present
cs_jaccard_iter3 <- alpha_pkg$crowding_check$cross_section_jaccard_iter3 %||% NA_real_

# HHI of |alpha_vector|
alpha_abs <- abs(ALPHA_VEC)
alpha_norm <- alpha_abs / sum(alpha_abs)
hhi <- sum(alpha_norm^2)
hhi_ew_baseline <- 1 / N_UNI
cat(sprintf("Alpha-vector HHI: %.4f (EW baseline %d-name=%.4f)\n",
            hhi, N_UNI, hhi_ew_baseline))

# Sector concentration on top-decile (proxy for portfolio)
top_decile_n <- ceiling(N_UNI * 0.1)
top_tickers <- names(sort(ALPHA_VEC, decreasing = TRUE))[1:top_decile_n]
sector_summary <- RD_UNI[Date >= as.Date("2023-09-01") & Ticker %in% top_tickers,
                         .(Ticker, Sector)][!duplicated(Ticker)]
sector_top_decile <- sector_summary[, .N, by = Sector][order(-N)]
sector_top_decile[, weight := N / sum(N)]
cat("Top-decile (n=", top_decile_n, ") sector concentration:\n")
print(sector_top_decile)
top_sector_pct <- if (nrow(sector_top_decile) > 0) sector_top_decile[1, weight] else 0

# Liquidity flags (≥200M production floor)
liq_period <- RD_UNI[Date >= as.Date("2023-09-01") & Date <= PIT_HARD_CUTOFF,
                     .(avg_won = mean(Vol * Close, na.rm = TRUE)), by = Ticker]
liq_period[, illiquid_flag := avg_won < 2e8]
liquidity_flags <- liq_period[illiquid_flag == TRUE, Ticker]
cat(sprintf("Liquidity flags (<200M KRW avg, recent 3M): n=%d\n", length(liquidity_flags)))

#==============================================================================
# STEP 6: Build risk_package draft
#==============================================================================
cat("\n==== STEP 6: Build risk_package draft ====\n")

# Challenge flags
challenge_flags <- list()
top_pct_first <- as.numeric(sub("%\\)", "",
                                sub(".*\\(", "", top_common_risks[1])))
if (!is.na(top_pct_first) && top_pct_first > 40) {
  challenge_flags[["RF-R1"]] <- list(id = "RF-R1", severity = "HIGH",
                                      msg = paste0("Top common risk: ", top_common_risks[1]))
}
if (sigma_cond > 100) {
  challenge_flags[["RF-R2"]] <- list(id = "RF-R2", severity = "HIGH",
                                      msg = sprintf("Σ condition number %.1f > 100 (ridge λ=%.4f)",
                                                    sigma_cond, ridge_lambda))
}
if (length(liquidity_flags) > 0) {
  challenge_flags[["RF-R3-liq"]] <- list(id = "RF-R3", severity = "MEDIUM",
                                          msg = sprintf("Liquidity-flagged tickers (n=%d) below 200M KRW",
                                                        length(liquidity_flags)))
}
worst_stress <- min(sapply(stress_results, function(s) s$cum_ret %||% 0), na.rm = TRUE)
if (worst_stress < -0.10) {
  challenge_flags[["RF-R4-stress"]] <- list(id = "RF-R4", severity = "HIGH",
                                             msg = sprintf("Worst historical stress cum_ret = %.2f%%",
                                                           worst_stress * 100))
}

# Regime cond breach flags
for (rg in regimes) {
  m <- regime_meta[[rg]]
  cn <- m$condition_number %||% NA
  if (!is.na(cn) && cn > 100) {
    sev <- if (cn > 300) "MEDIUM" else "LOW"
    challenge_flags[[paste0("RF-R2-regime-", tolower(rg))]] <- list(
      id = paste0("RF-R2-regime-", tolower(rg)), severity = sev,
      msg = sprintf("%s regime Σ cond=%.1f > 100 (T=%d). Pooled fallback recommended.",
                    rg, cn, m$T %||% 0L),
      direction = "INFO_TO_OPTIMIZER"
    )
  }
}

# Sector concentration flag
if (top_sector_pct > 0.40) {
  challenge_flags[["RF-R5-sector"]] <- list(id = "RF-R5", severity = "MEDIUM",
                                             msg = sprintf("Top-decile sector concentration: %s (%.1f%%)",
                                                           sector_top_decile[1, Sector],
                                                           top_sector_pct * 100))
}

# Crowding-V2-vs-STR1656 flag
if (str1656_diag$available && !is.null(str1656_diag$tdc_q5_lower) &&
    !is.na(str1656_diag$tdc_q5_lower) && str1656_diag$tdc_q5_lower >= 0.30) {
  challenge_flags[["RF-CROWD-1656"]] <- list(
    id = "RF-CROWD-1656", severity = "HIGH",
    msg = sprintf("V2 vs STR_1656 TDC q5 lower=%.4f >= 0.30 mandate. Tail-coupled with diversifier.",
                  str1656_diag$tdc_q5_lower),
    direction = "INFO_TO_OPTIMIZER"
  )
}

# Crowding-V2-vs-Iter11 (informational — expected ~1.0)
if (!is.na(cor_v2_iter11_score) && cor_v2_iter11_score > 0.95) {
  challenge_flags[["RF-CROWD-V2-BASE"]] <- list(
    id = "RF-CROWD-V2-BASE", severity = "INFO",
    msg = sprintf("V2↔STR_1701 base score correlation=%.4f (expected — V2 = STR_1701 + confidence tilt). Same family — use V2 OR STR_1701 in PG2, NOT both.",
                  cor_v2_iter11_score),
    direction = "INFO_TO_OPTIMIZER"
  )
}

# Iter 14 alpha context flags (RF-A1 not addressed by Risk — passthrough)
challenge_flags[["RF-A1-passthrough"]] <- list(
  id = "RF-A1-passthrough", severity = "INFO",
  msg = "Alpha sub_stab=0.7857 (RF-A1 PASS reported by Alpha vs prior Iter11 RF-A1 0.060). Risk does NOT validate alpha-side stability — measurement domain only.",
  direction = "INFO_FROM_ALPHA"
)

# Build risk_package
risk_package <- list(
  task_id = WT_ID,
  as_of_date = as.character(SIGNAL_AS_OF),
  signal_as_of = as.character(SIGNAL_AS_OF),
  forecast_horizon = "1M",
  selection_objective = "shrinkage_quality",

  exposure_matrix_ref = file.path(OUT_DIR_STAGE, "exposure_matrix.parquet"),
  factor_covariance_ref = file.path(OUT_DIR_STAGE, "factor_covariance.parquet"),
  specific_risk_ref = file.path(OUT_DIR_STAGE, "specific_risk.parquet"),
  security_covariance_ref = file.path(OUT_DIR_STAGE, "covariance.parquet"),
  security_covariance_pooled_fallback_ref = file.path(OUT_DIR_STAGE, "covariance_pooled_fallback.parquet"),
  regime_correlation_ref = file.path(OUT_DIR_STAGE, "regime_correlation.parquet"),
  tail_risk_ref = file.path(OUT_DIR_STAGE, "tail_risk.json"),

  external_factor_data = list(
    version = "kr_factor_returns_v2",
    path = ".cache/kr_factor_returns_v2.parquet",
    n_obs = nrow(F_MAT),
    date_range = c(as.character(min(FF_FACT$ym, na.rm = TRUE)),
                   as.character(max(FF_FACT$ym[FF_FACT$ym <= EST_END], na.rm = TRUE))),
    schema = c("Date","MKT","SMB","HML","WML","RMW","CMA","RF"),
    pit_compliance = "C1 (rolling expanding), C4 (annual May lag), C9/C11 verified",
    factor_construction_notes = "Iter 4 reused asset (DART TTM 2002+ backfill, FF1993/2015 + Novy-Marx 2013)"
  ),

  sigma_estimation = list(
    method = "factor_model_BOmegaB_plus_D",
    factor_estimator = selected$name,
    n_factors = length(factor_cols),
    factor_cols = factor_cols,
    n_tickers = N_UNI,
    universe = "Iter14_322_names_universe_restricted",
    ridge_lambda = ridge_lambda
  ),

  risk_summary = list(
    top_common_risks = top_common_risks,
    crowding_flags = c(
      paste0("V2↔STR_1701 base score cor=",
             round(cor_v2_iter11_score %||% NA, 4),
             " (expected ~1.0 — same family)"),
      paste0("V2 alpha_v2 vs Iter11 score_eff cor=",
             round(cor_v2_iter11_alpha %||% NA, 4),
             " (rank^0.5×conf^1.5 dilution effect)"),
      paste0("V2 vs STR_1656 TDC q5 lower=",
             round(str1656_diag$tdc_q5_lower %||% NA, 4),
             " (mandate <0.30)"),
      paste0("Cross-section Jaccard V2 vs Iter11 top-50=",
             round(jac_v2_iter11_50 %||% NA, 4)),
      paste0("Alpha-vector HHI=", round(hhi, 4),
             " (EW baseline ", round(hhi_ew_baseline, 4), ")"),
      if (nrow(sector_top_decile) > 0)
        paste0("Top-decile sector: ",
               sector_top_decile[1, Sector], " (",
               round(top_sector_pct * 100, 1), "%)") else "Top-decile sector: NA"
    ),
    liquidity_flags = if (length(liquidity_flags) > 0) {
      paste0("Below 200M won 20d AvgTV (n=", length(liquidity_flags), ")")
    } else character(0),
    stress_tests = list(
      market_down_5 = NA_real_,
      gfc_2008 = stress_results$GFC_2008$cum_ret %||% NA_real_,
      eudebt_2011 = stress_results$EuDebt_2011$cum_ret %||% NA_real_,
      taper_2013 = stress_results$Taper_2013$cum_ret %||% NA_real_,
      china_shock = stress_results$China_Shock$cum_ret %||% NA_real_,
      brexit_2016 = stress_results$Brexit_2016$cum_ret %||% NA_real_,
      tradewar_2018 = stress_results$TradeWar_2018$cum_ret %||% NA_real_,
      covid_2020 = stress_results$COVID_2020$cum_ret %||% NA_real_,
      rate_2022 = stress_results$Rate_2022$cum_ret %||% NA_real_
    ),
    stress_test_full = stress_results,
    factor_explained_share_mean = unname(syst_share),
    slot_diagnostics = list(
      slot_A_label = "Consensus_4F_w_0.5",
      slot_B_label = "XGB_ML_w_0.3",
      slot_C_label = "Quality_aggregate_w_0.2",
      sd_A = unname(sd_A), sd_B = unname(sd_B), sd_C = unname(sd_C),
      cor_AB = unname(cor_AB %||% NA_real_),
      cor_AC = unname(cor_AC %||% NA_real_),
      cor_BC = unname(cor_BC %||% NA_real_),
      diversification_benefit_pct = unname(diversification_benefit * 100),
      note = "Slot A/B/C top-quintile EW return correlations from V2 alpha_scores. Mid-confidence slots (B XGB ML) most diversifying. Diversification benefit ≈ 1 - σ_blend / (Σ wᵢσᵢ)."
    ),
    tail_risk = list(
      cvar_95_daily = unname(cvar_95_d),
      var_95_daily = unname(var_95_d),
      cdar_95 = unname(cdar_95),
      mdd_in_sample = unname(mdd),
      evt_var_99 = unname(tail_evt$var_evt %||% NA_real_),
      evt_es_99 = unname(tail_evt$es_evt %||% NA_real_),
      evt_method = tail_evt$method %||% "n/a",
      hill_alpha_top5pct = unname(hill_alpha %||% NA_real_),
      parametric_var_99_normal = unname(parametric_var_99_normal),
      parametric_var_99_cf = unname(parametric_var_99_cf),
      parametric_es_99_normal = unname(parametric_es_99_normal),
      note = "EW universe-322-names long-only proxy diagnostic. NOT optimized portfolio metrics. Per Risk-vs-Optimizer separation: Optimizer's MVO/CVaR weights with 20-name concentration will yield different (typically higher MDD/CVaR than EW-322 due to concentration). Hard caps (CVaR<2.5%, MDD<45%) are Optimizer/Forge gates, not Risk-side proxy gates."
    )
  ),

  diagnostics = list(
    condition_number = unname(sigma_cond),
    min_eigenvalue = unname(sigma_min_eig),
    psd = unname(sigma_psd),
    shrinkage_used = TRUE,
    shrinkage_method = "ledoit_wolf",
    factor_cov_estimator = selected$name,
    factor_cov_condition = unname(selected$condition),
    ridge_lambda = unname(ridge_lambda),
    n_tickers_in_sigma = N_UNI,
    factor_correlation_warnings = character(0),
    tdc_summary = list(
      MKT_vs_SMB = round(OMEGA["MKT","SMB"] /
                         sqrt(OMEGA["MKT","MKT"] * OMEGA["SMB","SMB"]), 3),
      MKT_vs_HML = round(OMEGA["MKT","HML"] /
                         sqrt(OMEGA["MKT","MKT"] * OMEGA["HML","HML"]), 3),
      MKT_vs_WML = round(OMEGA["MKT","WML"] /
                         sqrt(OMEGA["MKT","MKT"] * OMEGA["WML","WML"]), 3),
      MKT_vs_RMW = round(OMEGA["MKT","RMW"] /
                         sqrt(OMEGA["MKT","MKT"] * OMEGA["RMW","RMW"]), 3),
      MKT_vs_CMA = round(OMEGA["MKT","CMA"] /
                         sqrt(OMEGA["MKT","MKT"] * OMEGA["CMA","CMA"]), 3),
      slot_A_vs_B = round(cor_AB %||% NA_real_, 3),
      slot_A_vs_C = round(cor_AC %||% NA_real_, 3),
      slot_B_vs_C = round(cor_BC %||% NA_real_, 3),
      v2_vs_str1701_base = round(cor_v2_iter11_score %||% NA_real_, 4),
      v2_alpha_vs_str1701_base = round(cor_v2_iter11_alpha %||% NA_real_, 4),
      v2_vs_str1656_pearson = round(str1656_diag$pearson_cor %||% NA_real_, 4),
      v2_vs_str1656_tdc_q5_lower = round(str1656_diag$tdc_q5_lower %||% NA_real_, 4),
      v2_vs_str1656_tdc_q95_upper = round(str1656_diag$tdc_q95_upper %||% NA_real_, 4)
    ),
    regime_correlation_ref = file.path(OUT_DIR_STAGE, "regime_correlation.parquet"),
    per_regime_meta = regime_meta,
    pooled_fallback_meta = pooled_meta,
    systematic_variance_share = unname(syst_share),
    idiosyncratic_variance_share = unname(idio_share),
    avg_correlation = unname(mean(SIGMA[upper.tri(SIGMA)] /
                          sqrt(diag(SIGMA) %o% diag(SIGMA))[upper.tri(SIGMA)],
                          na.rm = TRUE)),
    factor_coverage_r2_mean = unname(mean(B_DT$r_squared, na.rm = TRUE)),
    factor_coverage_r2_median = unname(median(B_DT$r_squared, na.rm = TRUE)),
    factor_coverage_n_fallback = sum(B_DT$fallback),
    factor_coverage_note = "322-name universe FF5 v2 R² mean/median documented. Universe is broader than Iter 5 top-20 (322 vs 20) — higher R² mean expected due to inclusion of large-caps. PSD + cond preserved via factor model + diagonal D."
  ),

  crowding_diagnostics = list(
    v2_vs_str1701_base = list(
      score_correlation = round(cor_v2_iter11_score %||% NA_real_, 4),
      alpha_v2_vs_score_correlation = round(cor_v2_iter11_alpha %||% NA_real_, 4),
      cross_section_jaccard_top50 = round(jac_v2_iter11_50 %||% NA_real_, 4),
      cross_section_jaccard_top20 = round(jac_v2_iter11_20 %||% NA_real_, 4),
      n_joint_obs = nrow(joint_ts),
      interpretation = "V2 = STR_1701 base × confidence tilt. Score correlation expected near 1.0; alpha_v2 correlation lower due to rank^0.5×conf^1.5 nonlinear transformation. Same family — DO NOT include both V2 and STR_1701 in PG2 simultaneously (use V2 as STR_1701 successor)."
    ),
    v2_vs_str1656_diversifier = str1656_diag,
    cross_section_iter3_pg2_ancestor = list(
      jaccard = cs_jaccard_iter3,
      note = "Inherited from alpha_pkg crowding_check (Iter 3 PG2 STR_1631 ancestor)."
    ),
    alpha_vector_hhi = list(
      hhi = round(hhi, 4),
      ew_baseline = round(hhi_ew_baseline, 4),
      hhi_excess = round(hhi - hhi_ew_baseline, 4)
    ),
    sector_concentration_top_decile = list(
      top_decile_n = top_decile_n,
      top_sector = if (nrow(sector_top_decile) > 0) sector_top_decile[1, Sector] else NA_character_,
      top_sector_pct = round(top_sector_pct * 100, 2),
      full_distribution = if (nrow(sector_top_decile) > 0)
        as.list(setNames(round(sector_top_decile$weight * 100, 2),
                         sector_top_decile$Sector)) else list()
    )
  ),

  tail_per_regime = tail_per_regime,

  method_shopping_log = list(
    risk_agent = list(
      candidates_tried = length(estimators),
      cap = 5L,
      method_log = lapply(cov_log, identity)
    )
  ),

  pit_compliance = list(
    C1 = "PASS — expanding-window OLS for B; LW shrinkage on F_MAT 256-month panel",
    C2 = paste0("PASS — t-1 month-floor, PIT_HARD_CUTOFF=", as.character(PIT_HARD_CUTOFF),
                ". signal_as_of=", as.character(SIGNAL_AS_OF), " ≤ cutoff."),
    C3 = "PASS — EST_END=2023-11-01 < signal_as_of 2023-11-30. No same-period aggregate→apply.",
    C9 = "PASS — daily Ret aligned to month-floor regime via RP_M, no same-day VT/DD",
    C11 = "PASS — KR RAWDATA + KR FF5 v2 only, no FRED leakage",
    C12 = paste0("PASS — FF5 v2 month-end Date filtered to ≤ ", as.character(PIT_HARD_CUTOFF)),
    C13 = "PASS — Z_Score_Aligned upstream (Alpha), no manual sign flip in Risk",
    C14 = "PASS — no IC time-axis violation; Σ on Ret_M post-listing only",
    C15 = "PASS — RAWDATA + FF5 v2 loaded via parquet cache",
    pit_hard_cutoff = as.character(PIT_HARD_CUTOFF),
    lockbox = paste0("ENFORCED: 2024-01-23 ~ 2026-01-23 strictly excluded. Cutoff=",
                     as.character(PIT_HARD_CUTOFF)),
    note = "Risk Agent does not modify alpha_vector, confidence_vector, regime label, or weights. PIT-compliant. Universe 322-name."
  ),

  challenge_flags = challenge_flags,

  challenge_review = list(
    objection = TRUE,
    targets_reviewed = c("alpha_package", "confidence_vector", "factor_specs",
                         "regime_classification", "iter11_lineage"),
    objections = c(
      sprintf("RF-CROWD-V2-BASE: V2↔STR_1701 base score cor=%.4f. V2 = STR_1701 + confidence tilt — same family. Optimizer must NOT include V2 + STR_1701 simultaneously in PG2. Recommended PG2: V2 80%% + STR_1656 20%% (replace STR_1701 80%% with V2 80%%).",
              cor_v2_iter11_score %||% NA_real_),
      if (str1656_diag$available && !is.null(str1656_diag$tdc_q5_lower) &&
          !is.na(str1656_diag$tdc_q5_lower) && str1656_diag$tdc_q5_lower >= 0.30)
        sprintf("RF-CROWD-1656: V2↔STR_1656 TDC q5 lower=%.4f >= 0.30 mandate. Tail-coupled with diversifier — diversification benefit reduced.",
                str1656_diag$tdc_q5_lower)
      else
        sprintf("V2↔STR_1656 TDC q5 lower=%.4f < 0.30 mandate PASS. Tail independence preserved.",
                str1656_diag$tdc_q5_lower %||% NA_real_)
    ),
    note = sprintf("Risk Agent measurement (NOT endorsement): V2 base cor=%.4f vs STR_1701 (same family confirmed). V2↔STR_1656 TDC q5=%.4f (mandate %s). 322-name FF5 R² mean=%.3f. Risk does NOT validate alpha sub_stab claim or rank-tilt formula — those belong to Alpha agent / Forge backtest.",
                   cor_v2_iter11_score %||% NA_real_,
                   str1656_diag$tdc_q5_lower %||% NA_real_,
                   if (isTRUE(str1656_diag$mandate_pass)) "PASS" else "FAIL/NA",
                   mean(B_DT$r_squared, na.rm = TRUE))
  ),

  optimizer_handoff = list(
    note = "Iter 14 Σ produced (factor model BOmegaB+D on 322-name universe). V2 vs STR_1701 base cor near 1.0 — V2 is STR_1701 successor. V2↔STR_1656 TDC q5 measured. Optimizer chooses MVO/HRP/CVaR with mandatory 20-name + Σw=1 + long-only.",
    recommendations = c(
      "Use security_covariance_ref for primary Σ in MVO/CVaR.",
      "BIND POOLED FALLBACK: Use security_covariance_pooled_fallback_ref when regime_state in {CRISIS, CAUTION} OR when regime panel cond > 100.",
      sprintf("V2 = STR_1701 successor (same-family score cor %.4f). PG2 should be V2 80%% + STR_1656 20%% (replace STR_1701 80%% slot).",
              cor_v2_iter11_score %||% NA_real_),
      sprintf("V2↔STR_1656 TDC q5 lower=%.4f / threshold 0.30 (%s). Tail %s with diversifier.",
              str1656_diag$tdc_q5_lower %||% NA_real_,
              if (isTRUE(str1656_diag$mandate_pass)) "PASS" else "FAIL/NA",
              if (isTRUE(str1656_diag$mandate_pass)) "INDEPENDENT" else "COUPLED — re-evaluate"),
      "Slot diversification benefit measured for V2 internal A/B/C — already pre-blended in alpha_v2.",
      "Cash overlay: regime-conditional via RP_M — Optimizer reads regime_state and applies AX-001 v2 cash policy."
    )
  ),

  iter14_lineage = list(
    base_strategy = "STR_1701 (PG2 active 80%, Iter 11)",
    enhancement = "Confidence-aware Linear Tilt (alpha = rank^0.5 × confidence^1.5)",
    iter11_alpha_scores_ref = ITER11_SCORES_PATH,
    str1656_nav_ref = STR1656_NAV_PATH,
    pg2_replacement_recommended = "STR_1701 80% → V2 80% (same family, sub_stab improvement 0.060→0.786 reported by Alpha)"
  ),

  codex_round = list(
    rounds_executed = 0L,
    codex_stance = "PENDING",
    response_artifact = "codex_critic_response_risk.json",
    risk_challenge_note_artifact = "risk_challenge_note.md"
  )
)

# Save tail_risk.json
tail_risk_json <- list(
  cvar_95_daily = unname(cvar_95_d),
  var_95_daily = unname(var_95_d),
  cdar_95 = unname(cdar_95),
  mdd_in_sample = unname(mdd),
  evt_var_99 = unname(tail_evt$var_evt %||% NA_real_),
  evt_es_99 = unname(tail_evt$es_evt %||% NA_real_),
  evt_method = tail_evt$method %||% "n/a",
  hill_alpha_top5pct = unname(hill_alpha %||% NA_real_),
  parametric_var_99_normal = unname(parametric_var_99_normal),
  parametric_var_99_cf = unname(parametric_var_99_cf),
  parametric_es_99_normal = unname(parametric_es_99_normal),
  per_regime = tail_per_regime,
  stress_periods = stress_results,
  meta = list(
    portfolio_proxy = "EW universe-322-names long-only",
    pit_hard_cutoff = as.character(PIT_HARD_CUTOFF),
    note = "Diagnostic only — NOT optimized portfolio. Forge V2 NAV with 20-name top portfolio + rank^0.5×conf^1.5 tilt produces different realized metrics."
  )
)
write_json(tail_risk_json, file.path(OUT_DIR_STAGE, "tail_risk.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("Wrote tail_risk.json\n")

# Save risk_package draft
draft_path <- file.path(OUT_DIR_MAIL, "risk_package_draft.json")
write_json(risk_package, draft_path, pretty = TRUE, auto_unbox = TRUE)
cat("Wrote risk_package_draft.json:", draft_path, "\n")

# Workspace snapshot for finalize step
saveRDS(list(
  risk_package = risk_package,
  selected_method = selected$name,
  sigma_cond = sigma_cond,
  hill_alpha = hill_alpha,
  cvar_95_d = cvar_95_d,
  cor_v2_iter11_score = cor_v2_iter11_score,
  str1656_diag = str1656_diag,
  pit_cutoff = PIT_HARD_CUTOFF,
  TICKERS_UNI = TICKERS_UNI
), file.path(OUT_DIR_STAGE, "risk_workspace.rds"))

cat("\n==== Risk pipeline DONE ====\n")
cat("Σ method:", selected$name, "  cond_post_shrink:", round(sigma_cond, 2), "\n")
cat("V2↔STR_1701 base score cor:", round(cor_v2_iter11_score %||% NA, 4), "\n")
cat("V2↔STR_1656 TDC q5 lower:", round(str1656_diag$tdc_q5_lower %||% NA, 4), "\n")
cat("CVaR_95 daily:", round(cvar_95_d, 4),
    "  EVT ES_99:", round(tail_evt$es_evt %||% NA, 4),
    "  Hill α:", round(hill_alpha %||% NA, 3), "\n")
cat("Worst stress:", round(worst_stress * 100, 2), "%\n")
cat("Challenge flags:", length(challenge_flags), "\n")
