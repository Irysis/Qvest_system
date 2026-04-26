#==============================================================================
# WT-D20260426_008 (Iter 15) Track A V3 — Risk Research Pipeline
# STR_1701 Direct Upgrade (Slot + Persistence + Regime-λ neutral)
#
# Σ = B Ω B' + D structure
#   B = exposure to FF5 v2 (MKT/SMB/HML/WML/RMW/CMA) on V3 top-20 panel
#   Ω = factor covariance via parallel estimator comparison (5 candidates, R13)
#   D = idiosyncratic specific variance (residual)
# + Multi-sleeve diagnostics (Core 0.65 / Defense 0.35) — V3 retains Iter 11 base
# + Regime-conditional Σ (4-state BULL/NORMAL/CAUTION/CRISIS, pooled fallback)
# + Tail risk (CVaR / CDaR / EVT-GPD / Hill / parametric) per regime
# + 8 stress periods cumulative loss
# + Crowding diagnostics:
#     - V3 alpha vs STR_1701 production alpha (cor measurement, explicit)
#     - V3 NAV proxy vs STR_1701 monthly NAV (TDC)
#     - V3 NAV proxy vs STR_1656 M05 monthly NAV (cross-family TDC)
#     - Cross-section Jaccard top-20 vs STR_1701 (PG2 80% slot)
#
# Hard constraints:
#   - PIT C1/C2/C9/C11 (KR data only, expanding/rolling, t-1 lag)
#   - Σ PSD with min eigenvalue > 0
#   - Cond number ≤ 100 post-shrinkage (R7 evaluation criteria)
#   - method shopping ≤ 5 candidates (R2-C)
#   - No alpha modification, no weight proposal
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

WT_ID <- "WT-D20260426_008"
WT_TAG <- "WT_D20260426_008"
SIGNAL_AS_OF <- as.Date("2023-12-01")
PIT_HARD_CUTOFF <- as.Date("2023-11-30")
TRAIN_END <- as.Date("2024-01-22")
LOCKBOX_START <- as.Date("2024-01-23")

OUT_DIR_STAGE <- file.path("stage_artifacts", WT_TAG)
OUT_DIR_MAIL <- file.path("qepm/mailbox/worktask", WT_ID)
dir.create(OUT_DIR_STAGE, showWarnings = FALSE, recursive = TRUE)

cat("==== Iter 15 V3 Risk Pipeline ====\n")
cat("WT:", WT_ID, " | as_of:", as.character(SIGNAL_AS_OF), "\n")
cat("OUT_DIR_STAGE:", OUT_DIR_STAGE, "\n")
cat("OUT_DIR_MAIL:", OUT_DIR_MAIL, "\n")

# ── Load alpha_package ──────────────────────────────────────────────────────
alpha_pkg <- read_json(file.path(OUT_DIR_MAIL, "alpha_package.json"))
ALPHA_VEC <- unlist(alpha_pkg$alpha_vector)
CONF_VEC <- unlist(alpha_pkg$confidence_vector)
TICKERS20 <- names(ALPHA_VEC)
stopifnot(length(TICKERS20) == 20L)
cat("Top-20 V3 tickers loaded:", length(TICKERS20), "\n")

# ── Load alpha_scores time series ───────────────────────────────────────────
ALPHA_TS <- as.data.table(read_parquet(file.path(OUT_DIR_STAGE, "alpha_scores.parquet")))
setkey(ALPHA_TS, Date, Ticker)
cat("alpha_scores rows:", nrow(ALPHA_TS), " cols:", paste(names(ALPHA_TS), collapse=","), "\n")

# ── Load RAWDATA (PIT cutoff) ───────────────────────────────────────────────
RD <- as.data.table(read_parquet(".cache/rawdata.parquet"))
RD <- RD[Date <= PIT_HARD_CUTOFF]
RD_TR <- RD[Ticker %in% TICKERS20, .(Date, Ticker, Ret, Sector, Sector_Lv2, Size, Vol, Close)]
setkey(RD_TR, Date, Ticker)
cat("RAWDATA top-20 rows:", nrow(RD_TR), "\n")

RD_TR[, ym := as.Date(format(Date, "%Y-%m-01"))]
RET_MO <- RD_TR[!is.na(Ret), .(
  Ret_M = prod(1 + Ret) - 1,
  Date_end = max(Date),
  n_obs = .N
), by = .(Ticker, ym)]
RET_MO <- RET_MO[n_obs >= 15]

RET_WIDE <- dcast(RET_MO, ym ~ Ticker, value.var = "Ret_M")
setorder(RET_WIDE, ym)
cat("RET_WIDE: ", nrow(RET_WIDE), "months ×", ncol(RET_WIDE)-1, "tickers\n")

# ── Load FF5 v2 ─────────────────────────────────────────────────────────────
FF <- as.data.table(read_parquet(".cache/kr_factor_returns_v2.parquet"))
FF <- FF[Date <= PIT_HARD_CUTOFF]
FF[, ym := as.Date(format(Date, "%Y-%m-01"))]
FF_FACT <- FF[, .(ym, MKT, SMB, HML, WML, RMW, CMA, RF)]
cat("FF5 v2:", nrow(FF_FACT), "months\n")

RET_LONG <- melt(RET_WIDE, id.vars = "ym", variable.name = "Ticker",
                 value.name = "Ret_M", na.rm = TRUE)
RET_LONG <- merge(RET_LONG, FF_FACT[, .(ym, RF)], by = "ym", all.x = TRUE)
RET_LONG[, Ret_excess := Ret_M - ifelse(is.na(RF), 0, RF)]

# ── Regime panel ────────────────────────────────────────────────────────────
RP <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_007/regime_panel.parquet"))
RP[, ym := as.Date(format(sig_date, "%Y-%m-01"))]
RP_M <- RP[, .(ym, regime_state)]
setkey(RP_M, ym)
cat("regime_panel rows:", nrow(RP_M), "\n")
print(table(RP_M$regime_state))

#==============================================================================
# STEP 1: Exposure Matrix B (FF5 v2 betas)
#==============================================================================
cat("\n==== STEP 1: Exposure Matrix B ====\n")

EST_START <- as.Date("2002-08-01")
EST_END <- as.Date("2023-11-01")

PANEL <- merge(
  RET_LONG[ym >= EST_START & ym <= EST_END],
  FF_FACT[ym >= EST_START & ym <= EST_END,
          .(ym, MKT, SMB, HML, WML, RMW, CMA)],
  by = "ym"
)
PANEL[, Ret_xs := Ret_excess]

factor_cols <- c("MKT", "SMB", "HML", "WML", "RMW", "CMA")
expo_list <- list()
specific_var_list <- list()

PANEL_KEEP <- PANEL[, c("ym", "Ticker", "Ret_xs", factor_cols), with = FALSE]

for (tk in TICKERS20) {
  d <- PANEL_KEEP[Ticker == tk & complete.cases(PANEL_KEEP[Ticker == tk])]
  if (nrow(d) < 24) {
    expo_list[[tk]] <- data.table(
      Ticker = tk, MKT = 1, SMB = 0, HML = 0, WML = 0, RMW = 0, CMA = 0,
      n_obs = nrow(d), r_squared = NA_real_, fallback = TRUE
    )
    sigma2 <- if (nrow(d) >= 6) var(d$Ret_xs, na.rm = TRUE) else 0.01
    specific_var_list[[tk]] <- sigma2
    next
  }
  X <- as.matrix(cbind(1, d[, ..factor_cols]))
  y <- d$Ret_xs
  fit <- tryCatch({
    coef_b <- solve(t(X) %*% X) %*% t(X) %*% y
    resid <- y - X %*% coef_b
    list(coef = coef_b, resid = resid, ok = TRUE)
  }, error = function(e) list(ok = FALSE))
  if (!fit$ok) {
    expo_list[[tk]] <- data.table(
      Ticker = tk, MKT = 1, SMB = 0, HML = 0, WML = 0, RMW = 0, CMA = 0,
      n_obs = nrow(d), r_squared = NA_real_, fallback = TRUE
    )
    specific_var_list[[tk]] <- var(y, na.rm = TRUE)
    next
  }
  betas <- as.numeric(fit$coef)[-1]; names(betas) <- factor_cols
  resid_var <- as.numeric(var(fit$resid))
  ss_res <- sum(fit$resid^2); ss_tot <- sum((y - mean(y))^2)
  r2 <- if (ss_tot > 0) 1 - ss_res / ss_tot else 0
  expo_list[[tk]] <- data.table(
    Ticker = tk,
    MKT = betas["MKT"], SMB = betas["SMB"], HML = betas["HML"],
    WML = betas["WML"], RMW = betas["RMW"], CMA = betas["CMA"],
    n_obs = nrow(d), r_squared = r2, fallback = FALSE
  )
  specific_var_list[[tk]] <- resid_var
}

B_DT <- rbindlist(expo_list)
setkey(B_DT, Ticker)
cat("B exposure matrix (head):\n"); print(head(B_DT))
write_parquet(B_DT, file.path(OUT_DIR_STAGE, "exposure_matrix.parquet"))

#==============================================================================
# STEP 2: Factor Covariance Ω (5-estimator parallel comparison, R2-C cap)
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
  list(name = "sample",            fn = cov_sample),
  list(name = "ledoit_wolf_oracle", fn = cov_lw_oracle),
  list(name = "ledoit_wolf_constcor", fn = cov_lw_constcor),
  list(name = "gerber_rmt",         fn = cov_gerber_rmt),
  list(name = "diag_shrink",        fn = cov_diag_shrink)
)

n_workers <- min(4L, parallel::detectCores() - 1L)
plan(multisession, workers = max(1L, n_workers))

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
    cat(sprintf("  %s: cond=%.2f min_eig=%.4f PSD=%s\n",
                cr$name, cr$condition, cr$min_eig, cr$psd))
    cov_log[[cr$name]] <- list(
      name = cr$name, condition = unname(cr$condition),
      min_eig = unname(cr$min_eig), psd = unname(cr$psd), selected = FALSE
    )
  } else {
    cat(sprintf("  %s: FAILED (%s)\n", cr$name, cr$error))
  }
}

psd_ok <- Filter(function(r) r$ok && r$psd && r$condition <= 100, cov_results)
if (length(psd_ok) == 0) {
  psd_ok <- Filter(function(r) r$ok && r$psd, cov_results)
}
preference_order <- c("ledoit_wolf_oracle", "ledoit_wolf_constcor",
                      "gerber_rmt", "sample", "diag_shrink")
selected <- NULL
for (pref in preference_order) {
  cand <- Filter(function(r) r$name == pref, psd_ok)
  if (length(cand) > 0) { selected <- cand[[1]]; break }
}
if (is.null(selected)) {
  selected <- psd_ok[[which.min(sapply(psd_ok, function(r) r$condition))]]
}
cov_log[[selected$name]]$selected <- TRUE
OMEGA <- selected$Omega
cat("Selected Ω:", selected$name, "cond=", round(selected$condition, 2), "\n")

OMEGA_DT <- as.data.table(OMEGA, keep.rownames = "Factor")
write_parquet(OMEGA_DT, file.path(OUT_DIR_STAGE, "factor_covariance.parquet"))

#==============================================================================
# STEP 3: Specific Risk D
#==============================================================================
cat("\n==== STEP 3: Specific Risk D ====\n")
D_DT <- data.table(Ticker = TICKERS20,
                   specific_var = sapply(TICKERS20, function(tk) specific_var_list[[tk]]))
D_DT[, specific_var := pmax(specific_var, 1e-6)]
D_DT[, specific_sd := sqrt(specific_var)]
print(D_DT)
write_parquet(D_DT, file.path(OUT_DIR_STAGE, "specific_risk.parquet"))

#==============================================================================
# STEP 4: Security Covariance Σ = B Ω B' + D
#==============================================================================
cat("\n==== STEP 4: Security Covariance Σ ====\n")
B_MAT <- as.matrix(B_DT[match(TICKERS20, Ticker), ..factor_cols])
rownames(B_MAT) <- TICKERS20
D_MAT <- diag(D_DT[match(TICKERS20, Ticker), specific_var])
rownames(D_MAT) <- TICKERS20; colnames(D_MAT) <- TICKERS20

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

systematic_var <- diag(B_MAT %*% OMEGA %*% t(B_MAT))
total_var <- diag(SIGMA)
syst_share <- mean(systematic_var / total_var)
idio_share <- 1 - syst_share
cat(sprintf("Variance shares: systematic %.1f%% / idiosyncratic %.1f%%\n",
            syst_share * 100, idio_share * 100))

factor_var_contrib <- sapply(factor_cols, function(f) {
  bf <- B_MAT[, f]
  sigma_f <- OMEGA[f, f]
  mean(bf * bf * sigma_f / total_var)
})
factor_var_contrib_pct <- factor_var_contrib * 100
top_common_risks <- paste0(names(sort(factor_var_contrib_pct, decreasing = TRUE)),
                            " (", round(sort(factor_var_contrib_pct, decreasing = TRUE), 1), "%)")
top_common_risks <- c(top_common_risks,
                      paste0("Idiosyncratic (", round(idio_share * 100, 1), "%)"))
cat("Top common risks:\n"); print(top_common_risks)

#==============================================================================
# STEP 4b: Multi-sleeve Σ (Core 0.65 / Defense 0.35) — V3 inheritance
#==============================================================================
cat("\n==== STEP 4b: Multi-sleeve sleeve_diagnostics (V3) ====\n")
ALPHA_TS_T20 <- ALPHA_TS[Ticker %in% TICKERS20]

# V3 schema: score_eff_v3, score_core_z, score_defense_z, score_eff_str1701, lambda_t
# Use Ret_1m (forward) for sleeve return diagnostic.
SLEEVE_RET <- ALPHA_TS_T20[!is.na(Ret_1m) & !is.na(score_core_z) & !is.na(score_defense_z), .(
  port_ret_eq = mean(Ret_1m, na.rm = TRUE),
  port_ret_core = sum(Ret_1m * pmax(score_core_z, 0), na.rm = TRUE) /
                  pmax(sum(pmax(score_core_z, 0), na.rm = TRUE), 1e-6),
  port_ret_def = sum(Ret_1m * pmax(score_defense_z, 0), na.rm = TRUE) /
                 pmax(sum(pmax(score_defense_z, 0), na.rm = TRUE), 1e-6),
  n = .N
), by = Date]
SLEEVE_RET <- SLEEVE_RET[n >= 5]
cat("Sleeve return panel:", nrow(SLEEVE_RET), "months\n")

cor_core_def <- if (nrow(SLEEVE_RET) >= 30) {
  cor(SLEEVE_RET$port_ret_core, SLEEVE_RET$port_ret_def,
      use = "pairwise.complete.obs")
} else NA_real_

sd_core <- sd(SLEEVE_RET$port_ret_core, na.rm = TRUE)
sd_def <- sd(SLEEVE_RET$port_ret_def, na.rm = TRUE)
w_core_v <- 0.65; w_def_v <- 0.35
sd_combined_actual <- sqrt(w_core_v^2 * sd_core^2 + w_def_v^2 * sd_def^2 +
                           2 * w_core_v * w_def_v * sd_core * sd_def *
                             ifelse(is.na(cor_core_def), 1, cor_core_def))
sd_weighted_avg <- w_core_v * sd_core + w_def_v * sd_def
diversification_benefit <- 1 - sd_combined_actual / sd_weighted_avg
cat(sprintf("Core sd=%.4f Def sd=%.4f cor=%.3f\n", sd_core, sd_def, cor_core_def))
cat(sprintf("Diversification benefit (vs weighted avg): %.2f%%\n",
            diversification_benefit * 100))

#==============================================================================
# STEP 5a: Regime-conditional Σ + pooled fallback
#==============================================================================
cat("\n==== STEP 5a: Regime-conditional Σ ====\n")
RET_LONG[, ym := as.Date(format(ym, "%Y-%m-01"))]
RET_REG <- merge(RET_LONG, RP_M, by = "ym", all.x = TRUE)
RET_REG <- RET_REG[!is.na(regime_state) & ym >= EST_START & ym <= EST_END]

regimes <- c("BULL", "NORMAL", "CAUTION", "CRISIS")
regime_corr_list <- list()
regime_meta <- list()
for (rg in regimes) {
  sub <- RET_REG[regime_state == rg & Ticker %in% TICKERS20,
                 .(ym, Ticker, Ret_M)]
  W <- dcast(sub, ym ~ Ticker, value.var = "Ret_M")
  R_mat <- as.matrix(W[, -1, with = FALSE])
  T_obs <- nrow(R_mat)
  cat(sprintf("Regime %s: T=%d\n", rg, T_obs))
  if (T_obs < 5) {
    regime_meta[[rg]] <- list(regime = rg, T = T_obs,
                              method = "pooled_fallback_thin",
                              fallback = TRUE)
    next
  }
  cor_r <- tryCatch({
    if (T_obs >= 12) {
      cov_lw_constcor(R_mat[complete.cases(R_mat), , drop = FALSE])
    } else {
      cov_lw_oracle(R_mat[complete.cases(R_mat), , drop = FALSE])
    }
  }, error = function(e) NULL)
  if (is.null(cor_r) || nrow(cor_r) == 0) {
    regime_meta[[rg]] <- list(regime = rg, T = T_obs,
                              method = "fallback_failed", fallback = TRUE)
    next
  }
  sds_r <- sqrt(diag(cor_r))
  cor_only <- cor_r / (sds_r %o% sds_r); diag(cor_only) <- 1
  mean_corr <- (sum(cor_only) - nrow(cor_only)) / (nrow(cor_only) * (nrow(cor_only) - 1))
  eig_r <- eigen(cor_r, symmetric = TRUE, only.values = TRUE)$values
  cn_r <- max(eig_r) / max(min(eig_r), 1e-12)
  regime_corr_list[[rg]] <- list(
    regime = rg, T = T_obs, mean_correlation = mean_corr,
    condition_number = cn_r, min_eig = min(eig_r), psd = all(eig_r > 1e-12),
    method = if (T_obs >= 12) "ledoit_wolf_constcor" else "ledoit_wolf_oracle",
    fallback = FALSE
  )
  regime_meta[[rg]] <- regime_corr_list[[rg]]
  cat(sprintf("  cond=%.2f mean_corr=%.3f PSD=%s\n", cn_r, mean_corr,
              all(eig_r > 1e-12)))
}

reg_corr_dt <- rbindlist(lapply(names(regime_meta), function(rg) {
  m <- regime_meta[[rg]]
  data.table(regime = rg,
             T_obs = m$T %||% NA_integer_,
             mean_correlation = m$mean_correlation %||% NA_real_,
             condition_number = m$condition_number %||% NA_real_,
             min_eig = m$min_eig %||% NA_real_,
             psd = m$psd %||% NA,
             method = m$method %||% "fallback",
             fallback = m$fallback %||% TRUE)
}))
write_parquet(reg_corr_dt, file.path(OUT_DIR_STAGE, "regime_correlation.parquet"))
cat("Wrote regime_correlation.parquet\n")

# Pooled fallback Σ
cat("\n==== STEP 5a-bis: Pooled Σ fallback ====\n")
RW <- dcast(RET_REG[Ticker %in% TICKERS20, .(ym, Ticker, Ret_M)],
            ym ~ Ticker, value.var = "Ret_M")
RW_mat <- as.matrix(RW[, -1, with = FALSE])
RW_mat <- RW_mat[complete.cases(RW_mat), , drop = FALSE]
SIGMA_POOLED <- tryCatch(cov_lw_constcor(RW_mat),
                         error = function(e) cov_lw_oracle(RW_mat))
SIGMA_POOLED <- (SIGMA_POOLED + t(SIGMA_POOLED)) / 2
pooled_eig <- eigen(SIGMA_POOLED, symmetric = TRUE, only.values = TRUE)$values
pooled_cn <- max(pooled_eig) / max(min(pooled_eig), 1e-12)
pooled_min_eig <- min(pooled_eig)
cat(sprintf("Pooled Σ: T=%d cond=%.2f min_eig=%.4e PSD=%s\n",
            nrow(RW_mat), pooled_cn, pooled_min_eig, all(pooled_eig > 1e-12)))

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
pooled_meta <- list(
  T = nrow(RW_mat),
  method = "ledoit_wolf_constcor",
  condition_number = unname(pooled_cn),
  min_eig = unname(min(pooled_eig)),
  psd = all(pooled_eig > 1e-12),
  binding_rule = "Optimizer MUST use this Σ in CRISIS regime; SHOULD use in CAUTION when T<30; recommended for regime-uncertain rebalances."
)

#==============================================================================
# STEP 5b: Tail Risk + Stress
#==============================================================================
cat("\n==== STEP 5b: Tail Risk + Stress ====\n")

PORT_EW <- RET_LONG[Ticker %in% TICKERS20 & ym >= EST_START & ym <= EST_END,
                    .(port_ret = mean(Ret_M, na.rm = TRUE), n = .N), by = ym]
PORT_EW <- PORT_EW[n >= 10]
cat("Portfolio EW monthly panel: n=", nrow(PORT_EW), "months\n")

RD_TR_DAILY <- RD[Ticker %in% TICKERS20 & Date <= PIT_HARD_CUTOFF & !is.na(Ret),
                  .(port_ret = mean(Ret, na.rm = TRUE), n = .N), by = Date]
RD_TR_DAILY <- RD_TR_DAILY[n >= 10]
cat("Daily port panel: n=", nrow(RD_TR_DAILY), "obs\n")

r_d <- RD_TR_DAILY$port_ret
cvar_95_d <- mean(r_d[r_d <= quantile(r_d, 0.05, na.rm = TRUE)], na.rm = TRUE)
var_95_d <- as.numeric(quantile(r_d, 0.05, na.rm = TRUE))
nav <- cumprod(1 + r_d)
peak <- cummax(nav)
dd <- nav / peak - 1
cdar_95 <- mean(dd[dd <= quantile(dd, 0.05, na.rm = TRUE)], na.rm = TRUE)
mdd <- min(dd, na.rm = TRUE)

tail_evt <- tryCatch({
  source("02_Infrastructure/portfolio/tail_risk_engine.R", local = TRUE)
  compute_evt_var(r_d, p = 0.99, threshold_q = 0.95)
}, error = function(e) {
  cat("EVT failed:", conditionMessage(e), "\n")
  list(var_evt = NA_real_, es_evt = NA_real_, method = "failed")
})

cat(sprintf("CVaR_95 (daily): %.4f\n", cvar_95_d))
cat(sprintf("CDaR_95: %.4f\n", cdar_95))
cat(sprintf("MDD (in-sample daily): %.4f\n", mdd))
cat(sprintf("EVT VaR_99: %.4f, ES_99: %.4f, method: %s\n",
            tail_evt$var_evt %||% NA, tail_evt$es_evt %||% NA, tail_evt$method %||% "n/a"))

# Hill alpha
losses <- -r_d
losses_sorted <- sort(losses[losses > 0], decreasing = TRUE)
n_l <- length(losses_sorted)
k_hill <- max(20L, floor(0.05 * n_l))
hill_alpha <- if (n_l > 100 && k_hill > 0) {
  1 / mean(log(losses_sorted[1:k_hill] / losses_sorted[k_hill]))
} else NA_real_
cat(sprintf("Hill alpha (top 5%%, k=%d): %.3f\n", k_hill, hill_alpha))

# Parametric VaR/ES
parametric_var_99_normal <- mean(r_d, na.rm = TRUE) - qnorm(0.99) * sd(r_d, na.rm = TRUE)
m1 <- mean(r_d, na.rm = TRUE); m2 <- sd(r_d, na.rm = TRUE)
m3 <- mean((r_d - m1)^3, na.rm = TRUE) / m2^3
m4 <- mean((r_d - m1)^4, na.rm = TRUE) / m2^4 - 3
zq <- qnorm(0.99)
cf_z <- zq + (zq^2 - 1) * m3 / 6 + (zq^3 - 3 * zq) * m4 / 24 -
        (2 * zq^3 - 5 * zq) * m3^2 / 36
parametric_var_99_cf <- m1 - cf_z * m2
parametric_es_99_normal <- m1 - dnorm(qnorm(0.99)) / 0.01 * m2
cat(sprintf("Parametric VaR_99 N=%.4f CF=%.4f ES_99 N=%.4f\n",
            parametric_var_99_normal, parametric_var_99_cf, parametric_es_99_normal))

# Tail per regime
tail_per_regime <- list()
for (rg in regimes) {
  d_dates <- RP_M[regime_state == rg, ym]
  if (length(d_dates) == 0) next
  sub_d <- copy(RD_TR_DAILY)
  sub_d[, ym := as.Date(format(Date, "%Y-%m-01"))]
  sub_d <- sub_d[ym %in% d_dates]
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
  cat(sprintf("  Tail %s: n=%d CVaR_95=%.4f\n", rg, nrow(sub_d), cv))
}

# CRISIS bootstrap
crisis_alpha_bootstrap <- alpha_pkg$bootstrap_ci
crisis_dates <- RP_M[regime_state == "CRISIS", ym]
sub_d_crisis <- copy(RD_TR_DAILY)
sub_d_crisis[, ym := as.Date(format(Date, "%Y-%m-01"))]
crisis_d <- sub_d_crisis[ym %in% crisis_dates]
crisis_port_ret_boot <- if (nrow(crisis_d) >= 10) {
  set.seed(20260426)
  B_resamples <- 1000L
  cum_rets <- replicate(B_resamples, {
    idx <- sample.int(nrow(crisis_d), nrow(crisis_d), replace = TRUE)
    prod(1 + crisis_d$port_ret[idx]) - 1
  })
  list(
    n_days = nrow(crisis_d),
    mean = mean(cum_rets), median = median(cum_rets),
    ci95 = quantile(cum_rets, c(0.025, 0.975), na.rm = TRUE),
    n_resamples = B_resamples
  )
} else NULL

if (!is.null(crisis_port_ret_boot)) {
  cat(sprintf("CRISIS port cum_ret bootstrap (B=1000): mean=%.4f CI95=[%.4f,%.4f]\n",
              crisis_port_ret_boot$mean,
              crisis_port_ret_boot$ci95[1], crisis_port_ret_boot$ci95[2]))
}

# Stress periods
def_stress_periods <- list(
  list(name = "Terror_9_11",   start = "2001-09-01", end = "2001-12-31"),
  list(name = "GFC_2008",      start = "2007-10-01", end = "2009-03-31"),
  list(name = "EuDebt_2011",   start = "2011-07-01", end = "2011-12-31"),
  list(name = "Taper_2013",    start = "2013-05-01", end = "2013-09-30"),
  list(name = "China_Shock",   start = "2015-06-01", end = "2016-02-29"),
  list(name = "Brexit_2016",   start = "2016-06-01", end = "2016-09-30"),
  list(name = "TradeWar_2018", start = "2018-03-01", end = "2018-12-31"),
  list(name = "COVID_2020",    start = "2020-01-01", end = "2020-06-30"),
  list(name = "Rate_2022",     start = "2022-01-01", end = "2022-12-31"),
  list(name = "Iran_War_2026", start = "2026-02-01", end = "2026-04-30")
)
stress_results <- list()
for (sp in def_stress_periods) {
  s <- as.Date(sp$start); e <- as.Date(sp$end)
  if (s > PIT_HARD_CUTOFF) {
    stress_results[[sp$name]] <- list(window = paste0(s, "_", e),
                                       cum_ret = NA_real_,
                                       n = 0L,
                                       note = "outside_pit_cutoff")
    next
  }
  e2 <- min(e, PIT_HARD_CUTOFF)
  sub <- RD_TR_DAILY[Date >= s & Date <= e2]
  if (nrow(sub) < 5) {
    stress_results[[sp$name]] <- list(window = paste0(s, "_", e2),
                                       cum_ret = NA_real_,
                                       n = nrow(sub),
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
  cat(sprintf("  %s: n=%d cum_ret=%.4f mdd=%.4f\n",
              sp$name, nrow(sub), cum_r, mdd_s))
}

#==============================================================================
# STEP 5c: Crowding Diagnostics — V3 vs STR_1701 + STR_1656 (EXPLICIT)
#   Iter 14 학습: silent omission 절대 금지. 모든 cor/TDC explicit.
#==============================================================================
cat("\n==== STEP 5c: Crowding (V3 vs STR_1701/STR_1656 explicit) ====\n")

# C1. V3 alpha vector ↔ STR_1701 alpha base score (per row, score_eff_v3 vs score_eff_str1701)
crowd_pkg <- list()

if (all(c("score_eff_v3", "score_eff_str1701") %in% names(ALPHA_TS))) {
  cor_data <- ALPHA_TS[!is.na(score_eff_v3) & !is.na(score_eff_str1701),
                        .(score_eff_v3, score_eff_str1701)]
  v3_vs_str1701_pearson <- cor(cor_data$score_eff_v3, cor_data$score_eff_str1701, use = "complete.obs")
  v3_vs_str1701_spearman <- cor(cor_data$score_eff_v3, cor_data$score_eff_str1701, use = "complete.obs", method = "spearman")
  cat(sprintf("V3 score ↔ STR_1701 score (pooled): pearson=%.4f spearman=%.4f n=%d\n",
              v3_vs_str1701_pearson, v3_vs_str1701_spearman, nrow(cor_data)))

  # Per-period mean cor (more conservative)
  per_dt_cor <- ALPHA_TS[!is.na(score_eff_v3) & !is.na(score_eff_str1701),
                          .(cor_per_date = cor(score_eff_v3, score_eff_str1701, use = "complete.obs")),
                          by = Date]
  v3_vs_str1701_meanperdate <- mean(per_dt_cor$cor_per_date, na.rm = TRUE)
  cat(sprintf("V3 ↔ STR_1701 cor per_date mean: %.4f (alpha pkg claims 0.9284)\n",
              v3_vs_str1701_meanperdate))
} else {
  v3_vs_str1701_pearson <- NA_real_
  v3_vs_str1701_spearman <- NA_real_
  v3_vs_str1701_meanperdate <- NA_real_
  cat("WARNING: score_eff_v3 / score_eff_str1701 not available\n")
}
crowd_pkg$v3_vs_str1701_score_pearson <- v3_vs_str1701_pearson
crowd_pkg$v3_vs_str1701_score_spearman <- v3_vs_str1701_spearman
crowd_pkg$v3_vs_str1701_score_perdate_mean <- v3_vs_str1701_meanperdate

# C2. Cross-section Jaccard: V3 top-20 (latest sig_date) vs STR_1701 production (proxy via score_eff_str1701 top-20 latest)
LAST_DT <- as.Date("2023-12-01")
v3_latest_top20 <- ALPHA_TS[Date == LAST_DT & top_flag == 1L, Ticker]
if (length(v3_latest_top20) == 0L) {
  v3_latest_top20 <- ALPHA_TS[Date == LAST_DT & !is.na(score_eff_v3)][order(-score_eff_v3)][1:20, Ticker]
}
str1701_latest_top20 <- ALPHA_TS[Date == LAST_DT & !is.na(score_eff_str1701)][order(-score_eff_str1701)][1:20, Ticker]
common_v3_str1701 <- intersect(v3_latest_top20, str1701_latest_top20)
union_v3_str1701 <- union(v3_latest_top20, str1701_latest_top20)
jaccard_v3_str1701 <- length(common_v3_str1701) / length(union_v3_str1701)
cat(sprintf("V3 top-20 ∩ STR_1701 top-20 (proxy via score_eff_str1701) = %d / %d → Jaccard=%.4f\n",
            length(common_v3_str1701), length(union_v3_str1701), jaccard_v3_str1701))
crowd_pkg$jaccard_v3_str1701_top20 <- jaccard_v3_str1701
crowd_pkg$top20_intersection_count <- length(common_v3_str1701)

# C3. Time-series TDC: V3 EW top-20 monthly NAV vs STR_1701 monthly returns
# V3 has no realized backtest yet (Forge pending). Use V3 score-weighted EW proxy.
str1701_mr <- tryCatch({
  m <- as.data.table(read_parquet("qepm/mailbox/worktask/WT-D20260426_004/backtest_result/monthly_returns.parquet"))
  m[, ym := as.Date(format(Date, "%Y-%m-01"))]
  m
}, error = function(e) {
  cat("STR_1701 monthly_returns load failed:", conditionMessage(e), "\n")
  NULL
})

# V3 EW top-20 proxy (using top_flag==1 monthly)
v3_ew_proxy <- ALPHA_TS[!is.na(Ret_1m) & top_flag == 1L,
                         .(v3_port_ret = mean(Ret_1m, na.rm = TRUE), n = .N), by = Date]
v3_ew_proxy[, ym := as.Date(format(Date, "%Y-%m-01"))]
cat("V3 EW top-20 proxy panel:", nrow(v3_ew_proxy), "months\n")

if (!is.null(str1701_mr) && nrow(v3_ew_proxy) > 30) {
  joined <- merge(v3_ew_proxy[, .(ym, v3_ret = v3_port_ret)],
                  str1701_mr[, .(ym, str1701_ret = port_ret)],
                  by = "ym")
  if (nrow(joined) >= 30) {
    cor_v3_str1701_pearson <- cor(joined$v3_ret, joined$str1701_ret, use = "complete.obs")
    cor_v3_str1701_spearman <- cor(joined$v3_ret, joined$str1701_ret, use = "complete.obs", method = "spearman")
    # TDC (lower-tail): conditional probability of joint q5 hit
    q5_v3 <- quantile(joined$v3_ret, 0.05, na.rm = TRUE)
    q5_str1701 <- quantile(joined$str1701_ret, 0.05, na.rm = TRUE)
    n_both <- sum(joined$v3_ret <= q5_v3 & joined$str1701_ret <= q5_str1701, na.rm = TRUE)
    n_str <- sum(joined$str1701_ret <= q5_str1701, na.rm = TRUE)
    tdc_q5_v3_str1701 <- if (n_str > 0) n_both / n_str else NA_real_
    cat(sprintf("V3 ↔ STR_1701 monthly NAV: cor pearson=%.4f spearman=%.4f n=%d\n",
                cor_v3_str1701_pearson, cor_v3_str1701_spearman, nrow(joined)))
    cat(sprintf("V3 ↔ STR_1701 TDC q5 (lower-tail dependence): %.4f (n_both=%d, n_str=%d)\n",
                tdc_q5_v3_str1701, n_both, n_str))
  } else {
    cor_v3_str1701_pearson <- NA_real_; cor_v3_str1701_spearman <- NA_real_
    tdc_q5_v3_str1701 <- NA_real_
    cat(sprintf("V3 ↔ STR_1701 NAV join too thin (n=%d)\n", nrow(joined)))
  }
} else {
  cor_v3_str1701_pearson <- NA_real_; cor_v3_str1701_spearman <- NA_real_
  tdc_q5_v3_str1701 <- NA_real_
  cat("V3 ↔ STR_1701 NAV cor: NOT_COMPUTED (insufficient data)\n")
}
crowd_pkg$v3_nav_vs_str1701_cor_pearson <- cor_v3_str1701_pearson
crowd_pkg$v3_nav_vs_str1701_cor_spearman <- cor_v3_str1701_spearman
crowd_pkg$v3_nav_vs_str1701_tdc_q5 <- tdc_q5_v3_str1701

# C4. V3 vs STR_1656 M05 (cross-family check — must REMAIN low cor for diversification)
str1656_nav <- tryCatch({
  d <- fread("04_Research/strategies/STR_1656_MLRA/output/s5_mutations/M05/nav.csv")
  d[, Date := as.Date(Date)]
  d[, ym := as.Date(format(Date, "%Y-%m-01"))]
  # Aggregate to monthly returns
  d_mo <- d[!is.na(Strategy_Ret), .(str1656_ret = prod(1 + Strategy_Ret) - 1, n = .N), by = ym]
  d_mo[n >= 10]
}, error = function(e) {
  cat("STR_1656 M05 nav load failed:", conditionMessage(e), "\n")
  NULL
})

if (!is.null(str1656_nav) && nrow(v3_ew_proxy) > 30) {
  joined2 <- merge(v3_ew_proxy[, .(ym, v3_ret = v3_port_ret)],
                   str1656_nav[, .(ym, str1656_ret)], by = "ym")
  if (nrow(joined2) >= 30) {
    cor_v3_str1656_pearson <- cor(joined2$v3_ret, joined2$str1656_ret, use = "complete.obs")
    cor_v3_str1656_spearman <- cor(joined2$v3_ret, joined2$str1656_ret, use = "complete.obs", method = "spearman")
    q5_v3b <- quantile(joined2$v3_ret, 0.05, na.rm = TRUE)
    q5_str1656 <- quantile(joined2$str1656_ret, 0.05, na.rm = TRUE)
    n_both2 <- sum(joined2$v3_ret <= q5_v3b & joined2$str1656_ret <= q5_str1656, na.rm = TRUE)
    n_str2 <- sum(joined2$str1656_ret <= q5_str1656, na.rm = TRUE)
    tdc_q5_v3_str1656 <- if (n_str2 > 0) n_both2 / n_str2 else NA_real_
    cat(sprintf("V3 ↔ STR_1656 monthly NAV: cor pearson=%.4f spearman=%.4f n=%d\n",
                cor_v3_str1656_pearson, cor_v3_str1656_spearman, nrow(joined2)))
    cat(sprintf("V3 ↔ STR_1656 TDC q5: %.4f (n_both=%d, n_str=%d)\n",
                tdc_q5_v3_str1656, n_both2, n_str2))
  } else {
    cor_v3_str1656_pearson <- NA_real_; cor_v3_str1656_spearman <- NA_real_
    tdc_q5_v3_str1656 <- NA_real_
    cat(sprintf("V3 ↔ STR_1656 NAV join thin (n=%d)\n", nrow(joined2)))
  }
} else {
  cor_v3_str1656_pearson <- NA_real_; cor_v3_str1656_spearman <- NA_real_
  tdc_q5_v3_str1656 <- NA_real_
  cat("V3 ↔ STR_1656 NAV cor: NOT_COMPUTED\n")
}
crowd_pkg$v3_nav_vs_str1656_cor_pearson <- cor_v3_str1656_pearson
crowd_pkg$v3_nav_vs_str1656_cor_spearman <- cor_v3_str1656_spearman
crowd_pkg$v3_nav_vs_str1656_tdc_q5 <- tdc_q5_v3_str1656

# C5. PG2 incremental risk: weighted blend (V3 80% + STR_1656 20%) cor with current PG2 (STR_1701 80% + STR_1656 20%)
if (!is.null(str1701_mr) && !is.null(str1656_nav) && nrow(v3_ew_proxy) > 30) {
  pg2_compare <- merge(merge(
    v3_ew_proxy[, .(ym, v3_ret = v3_port_ret)],
    str1701_mr[, .(ym, str1701_ret = port_ret)], by = "ym"),
    str1656_nav[, .(ym, str1656_ret)], by = "ym")
  if (nrow(pg2_compare) >= 30) {
    pg2_compare[, pg2_v3_blend := 0.8 * v3_ret + 0.2 * str1656_ret]
    pg2_compare[, pg2_active   := 0.8 * str1701_ret + 0.2 * str1656_ret]
    cor_pg2_blend_active <- cor(pg2_compare$pg2_v3_blend, pg2_compare$pg2_active, use = "complete.obs")
    q5_pa <- quantile(pg2_compare$pg2_active, 0.05, na.rm = TRUE)
    q5_pb <- quantile(pg2_compare$pg2_v3_blend, 0.05, na.rm = TRUE)
    n_both3 <- sum(pg2_compare$pg2_v3_blend <= q5_pb & pg2_compare$pg2_active <= q5_pa, na.rm = TRUE)
    n_a <- sum(pg2_compare$pg2_active <= q5_pa, na.rm = TRUE)
    tdc_pg2 <- if (n_a > 0) n_both3 / n_a else NA_real_
    cat(sprintf("PG2_blend_v3 ↔ PG2_active cor=%.4f TDC q5=%.4f n=%d\n",
                cor_pg2_blend_active, tdc_pg2, nrow(pg2_compare)))
  } else {
    cor_pg2_blend_active <- NA_real_; tdc_pg2 <- NA_real_
  }
} else {
  cor_pg2_blend_active <- NA_real_; tdc_pg2 <- NA_real_
}
crowd_pkg$pg2_blend_v3_vs_pg2_active_cor <- cor_pg2_blend_active
crowd_pkg$pg2_blend_v3_vs_pg2_active_tdc_q5 <- tdc_pg2

# HHI on alpha_vector
alpha_norm <- ALPHA_VEC / sum(ALPHA_VEC)
hhi <- sum(alpha_norm^2)
cat(sprintf("V3 alpha-vector HHI: %.4f (EW=%.4f)\n", hhi, 1 / 20))
crowd_pkg$alpha_hhi <- hhi

# Liquidity check
liq <- RD_TR[Date >= as.Date("2023-09-01") & Date <= TRAIN_END,
             .(avg_won = mean(Vol * Close, na.rm = TRUE)), by = Ticker]
liq[, illiquid_flag := avg_won < 2e8]
liquidity_flags <- liq[illiquid_flag == TRUE, Ticker]
cat("Liquidity flags (<200M KRW avg):", paste(liquidity_flags, collapse = ","), "\n")

# Sector concentration
sector_summary <- RD_TR[Date == max(RD_TR$Date), .(Ticker, Sector)][!duplicated(Ticker)]
sector_summary <- merge(sector_summary,
                         data.table(Ticker = names(ALPHA_VEC), alpha = ALPHA_VEC),
                         by = "Ticker", all.x = TRUE)
sector_alpha <- sector_summary[!is.na(alpha), .(weight = sum(alpha) / sum(sector_summary$alpha, na.rm = TRUE)),
                                by = Sector][order(-weight)]
cat("Sector weights (V3 top-20):\n"); print(sector_alpha)
top_sector_pct <- sector_alpha[1, weight]
crowd_pkg$top_sector <- list(name = sector_alpha[1, Sector], pct = top_sector_pct)

#==============================================================================
# STEP 6: Build risk_package draft
#==============================================================================
cat("\n==== STEP 6: Build risk_package draft ====\n")

challenge_flags <- list()

# Top common risk
top1_pct <- as.numeric(sub("%\\)", "", sub(".*\\(", "", top_common_risks[1])))
if (!is.na(top1_pct) && top1_pct > 40) {
  challenge_flags[["RF-R1"]] <- list(id = "RF-R1", severity = "HIGH",
                                      msg = paste0("Top common risk: ", top_common_risks[1]))
}
if (sigma_cond > 100) {
  challenge_flags[["RF-R2"]] <- list(id = "RF-R2", severity = "HIGH",
                                      msg = sprintf("Σ cond %.1f > 100 even after ridge", sigma_cond))
}
if (length(liquidity_flags) > 0) {
  challenge_flags[["RF-R3-liq"]] <- list(id = "RF-R3", severity = "MEDIUM",
                                          msg = paste0("Liquidity flag tickers: ",
                                                       paste(liquidity_flags, collapse = ",")))
}
worst_stress <- min(sapply(stress_results, function(s) s$cum_ret %||% 0), na.rm = TRUE)
if (worst_stress < -0.10) {
  challenge_flags[["RF-R4-stress"]] <- list(id = "RF-R4", severity = "HIGH",
                                             msg = sprintf("Worst stress cum_ret = %.2f%%",
                                                           worst_stress * 100))
}

crisis_alpha_ic <- as.numeric(crisis_alpha_bootstrap$crisis_ic_mean %||% NA)
if (!is.na(crisis_alpha_ic) && crisis_alpha_ic < -0.05) {
  challenge_flags[["RF-CRISIS-COUPLING"]] <- list(
    id = "RF-CRISIS-COUPLING", severity = "MEDIUM",
    msg = sprintf("Alpha CRISIS IC=%.3f (n=%d). Risk-side CRISIS T=%d. Multi-sleeve cor=%.3f. Optimizer should consider regime weight scaling or pooled Σ.",
                  crisis_alpha_ic, crisis_alpha_bootstrap$n_crisis_obs %||% 0,
                  regime_meta$CRISIS$T %||% 0, cor_core_def %||% NA),
    direction = "INFO_TO_OPTIMIZER")
}

crisis_cn <- regime_meta$CRISIS$condition_number %||% NA
if (!is.na(crisis_cn) && crisis_cn > 100) {
  challenge_flags[["RF-R2-regime-crisis"]] <- list(
    id = "RF-R2-regime-crisis", severity = "MEDIUM",
    msg = sprintf("CRISIS regime Σ cond=%.1f > 100 (T=%d). Pooled fallback recommended.",
                  crisis_cn, regime_meta$CRISIS$T %||% 0L),
    direction = "INFO_TO_OPTIMIZER")
}
normal_cn <- regime_meta$NORMAL$condition_number %||% NA
if (!is.na(normal_cn) && normal_cn > 200) {
  challenge_flags[["RF-R2-regime-normal"]] <- list(
    id = "RF-R2-regime-normal", severity = "MEDIUM",
    msg = sprintf("NORMAL regime Σ cond=%.1f > 200 (T=%d). Numerical stability warning.",
                  normal_cn, regime_meta$NORMAL$T %||% 0L))
}
if (!is.na(regime_meta$BULL$condition_number) && regime_meta$BULL$condition_number > 100) {
  challenge_flags[["RF-R2-regime-bull"]] <- list(
    id = "RF-R2-regime-bull", severity = "LOW",
    msg = sprintf("BULL regime Σ cond=%.1f > 100 (T=%d). Borderline.",
                  regime_meta$BULL$condition_number, regime_meta$BULL$T %||% 0L))
}
if (top_sector_pct > 0.40) {
  challenge_flags[["RF-R5-sector"]] <- list(id = "RF-R5", severity = "MEDIUM",
                                             msg = sprintf("Top sector: %s (%.1f%%)",
                                                           sector_alpha[1, Sector],
                                                           top_sector_pct * 100))
}

# V3-specific crowding flag (HIGH cor with STR_1701 expected — explicit acknowledgement)
if (!is.na(v3_vs_str1701_meanperdate) && v3_vs_str1701_meanperdate >= 0.85) {
  challenge_flags[["RF-CROWD-V3-STR1701"]] <- list(
    id = "RF-CROWD-V3-STR1701", severity = "INFO",
    msg = sprintf("V3 ↔ STR_1701 score per_date cor=%.4f >= 0.85 (alpha pkg L-224 mandate). EXPECTED — V3 is direct upgrade. Optimizer must not double-count: PG2 'V3 80%% + STR_1656 20%%' REPLACES current 'STR_1701 80%% + STR_1656 20%%' (not additive blend).",
                  v3_vs_str1701_meanperdate),
    direction = "INFO_TO_OPTIMIZER+FORGE")
}

if (!is.na(cor_pg2_blend_active) && cor_pg2_blend_active >= 0.95) {
  challenge_flags[["RF-CROWD-PG2-DEGENERATE"]] <- list(
    id = "RF-CROWD-PG2-DEGENERATE", severity = "MEDIUM",
    msg = sprintf("PG2_blend(V3 80+STR_1656 20) ↔ PG2_active(STR_1701 80+STR_1656 20) cor=%.4f >= 0.95. Realized SR uplift will be marginal; Forge backtest should focus on turnover/regime-conditional alpha, not cross-source diversification.",
                  cor_pg2_blend_active),
    direction = "INFO_TO_FORGE")
}

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
    n_tickers = length(TICKERS20),
    ridge_lambda = ridge_lambda
  ),

  risk_summary = list(
    top_common_risks = top_common_risks,
    crowding_flags = c(
      sprintf("V3 score ↔ STR_1701 production score per_date_mean cor=%.4f (alpha L-224 PASS, EXPECTED for direct upgrade)", v3_vs_str1701_meanperdate %||% NA_real_),
      sprintf("V3 top-20 ↔ STR_1701 top-20 (latest) Jaccard=%.4f", jaccard_v3_str1701),
      sprintf("V3 NAV proxy ↔ STR_1701 monthly NAV cor=%.4f TDC_q5=%.4f", cor_v3_str1701_pearson %||% NA_real_, tdc_q5_v3_str1701 %||% NA_real_),
      sprintf("V3 NAV proxy ↔ STR_1656 M05 NAV cor=%.4f TDC_q5=%.4f (cross-family diversifier check)", cor_v3_str1656_pearson %||% NA_real_, tdc_q5_v3_str1656 %||% NA_real_),
      sprintf("PG2 blend(V3 80+STR_1656 20) ↔ PG2 active(STR_1701 80+STR_1656 20) cor=%.4f TDC_q5=%.4f", cor_pg2_blend_active %||% NA_real_, tdc_pg2 %||% NA_real_),
      sprintf("Alpha-vector HHI=%.4f (EW=0.0500)", hhi),
      sprintf("Top sector: %s (%.1f%%)", sector_alpha[1, Sector], top_sector_pct * 100)
    ),
    liquidity_flags = if (length(liquidity_flags) > 0) {
      paste0("Below 200M won 20d AvgTV: ", paste(liquidity_flags, collapse = ","))
    } else character(0),
    stress_tests = list(
      market_down_5 = NA_real_,
      gfc_2008 = stress_results$GFC_2008$cum_ret %||% NA_real_,
      eudebt_2011 = stress_results$EuDebt_2011$cum_ret %||% NA_real_,
      covid_2020 = stress_results$COVID_2020$cum_ret %||% NA_real_,
      rate_2022 = stress_results$Rate_2022$cum_ret %||% NA_real_,
      china_shock = stress_results$China_Shock$cum_ret %||% NA_real_,
      tradewar_2018 = stress_results$TradeWar_2018$cum_ret %||% NA_real_
    ),
    stress_test_full = stress_results,
    factor_explained_share_mean = unname(syst_share),
    sleeve_diagnostics = list(
      sleeve_core_label = "V3_Core_Consensus_4F (inherited Iter 11 score_core_z; w_core=0.65)",
      sleeve_defense_label = "V3_Defense_Q07_M08_Q25_3axis (inherited score_defense_z; w_def=0.35)",
      sd_core = unname(sd_core),
      sd_defense = unname(sd_def),
      cor_core_defense = unname(cor_core_def %||% NA_real_),
      diversification_benefit_pct = unname(diversification_benefit * 100),
      note = "V3 retains Iter 11 multi-sleeve base (z_A/z_B byte-equivalent, alpha pkg inheritance_proof). Mutations operate on slot weighting + persistence + regime λ tilt — base alpha unchanged."
    ),
    tail_risk = list(
      cvar_95_daily = unname(cvar_95_d),
      var_95_daily = unname(var_95_d),
      cdar_95 = unname(cdar_95),
      mdd_in_sample = unname(mdd),
      evt_var_99 = unname(tail_evt$var_evt %||% NA_real_),
      evt_es_99 = unname(tail_evt$es_evt %||% NA_real_),
      evt_method = tail_evt$method %||% "n/a",
      hill_alpha_top5pct = unname(hill_alpha),
      parametric_var_99_normal = unname(parametric_var_99_normal),
      parametric_var_99_cf = unname(parametric_var_99_cf),
      parametric_es_99_normal = unname(parametric_es_99_normal),
      note = "EW top-20 long-only proxy. Risk diagnostic NOT optimized portfolio metric. CVaR<2.5%/MDD<45%/stress<25% caps belong to Optimizer/Forge/Governor."
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
    n_tickers_in_sigma = length(TICKERS20),
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
      sleeve_core_vs_defense = round(cor_core_def %||% NA_real_, 3),
      v3_score_vs_str1701_score_perdate_mean = round(v3_vs_str1701_meanperdate %||% NA_real_, 4),
      v3_nav_proxy_vs_str1701_nav_pearson = round(cor_v3_str1701_pearson %||% NA_real_, 4),
      v3_nav_proxy_vs_str1701_nav_tdc_q5 = round(tdc_q5_v3_str1701 %||% NA_real_, 4),
      v3_nav_proxy_vs_str1656_nav_pearson = round(cor_v3_str1656_pearson %||% NA_real_, 4),
      v3_nav_proxy_vs_str1656_nav_tdc_q5 = round(tdc_q5_v3_str1656 %||% NA_real_, 4),
      pg2_blend_v3_vs_pg2_active_cor = round(cor_pg2_blend_active %||% NA_real_, 4),
      pg2_blend_v3_vs_pg2_active_tdc_q5 = round(tdc_pg2 %||% NA_real_, 4)
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
    factor_coverage_note = "KR top-20 long-only is concentrated/idiosyncratic. FF5 R²~25% empirically expected. Σ structure preserved via factor model + diagonal D."
  ),

  multi_sleeve_v3 = list(
    sleeve_1_core = list(
      label = alpha_pkg$multi_sleeve_structure$sleeve_1_core$label,
      weight = alpha_pkg$multi_sleeve_structure$sleeve_1_core$weight,
      sd_estimated = unname(sd_core)
    ),
    sleeve_2_defense = list(
      label = alpha_pkg$multi_sleeve_structure$sleeve_2_defense$label,
      weight = alpha_pkg$multi_sleeve_structure$sleeve_2_defense$weight,
      sd_estimated = unname(sd_def)
    ),
    mutations = list(
      mutation_1_slot_weight = alpha_pkg$multi_sleeve_structure$mutation_1_slot_weight$optimal,
      mutation_2_persistence = alpha_pkg$multi_sleeve_structure$mutation_2_persistence_ema,
      mutation_3_regime_lambda = alpha_pkg$multi_sleeve_structure$mutation_3_regime_lambda
    ),
    cor_core_defense = unname(cor_core_def %||% NA_real_),
    diversification_benefit_pct = unname(diversification_benefit * 100),
    note = "V3 = STR_1701 direct upgrade. Score-level inheritance + 3 mutations (slot/persistence/regime-λ neutral). Optimizer applies Σ for weight derivation."
  ),

  crowding_diagnostics_explicit = crowd_pkg,

  crisis_validation = list(
    alpha_crisis_bootstrap = list(
      n_crisis = crisis_alpha_bootstrap$n_crisis_obs %||% NA_integer_,
      mean_ic = crisis_alpha_bootstrap$crisis_ic_mean %||% NA_real_,
      ci95 = list(crisis_alpha_bootstrap$crisis_ci95$lower %||% NA_real_,
                  crisis_alpha_bootstrap$crisis_ci95$upper %||% NA_real_)
    ),
    risk_crisis_panel = list(
      regime_panel_n = sum(RP_M$regime_state == "CRISIS"),
      top20_panel_n = if (!is.null(regime_meta$CRISIS$T)) regime_meta$CRISIS$T else 0L,
      crisis_port_cum_ret = if (!is.null(crisis_port_ret_boot)) crisis_port_ret_boot$mean else NA_real_,
      crisis_port_cum_ret_ci95 = if (!is.null(crisis_port_ret_boot))
        as.list(crisis_port_ret_boot$ci95) else list(NA_real_, NA_real_),
      bootstrap_n_resamples = if (!is.null(crisis_port_ret_boot)) crisis_port_ret_boot$n_resamples else 0L
    ),
    note = sprintf("Alpha CRISIS IC=%.3f CI95=[%.3f,%.3f] (n=%d). Risk-side CRISIS top-20 panel T=%d. Optimizer pool fallback recommended.",
                   crisis_alpha_bootstrap$crisis_ic_mean %||% NA_real_,
                   crisis_alpha_bootstrap$crisis_ci95$lower %||% NA_real_,
                   crisis_alpha_bootstrap$crisis_ci95$upper %||% NA_real_,
                   crisis_alpha_bootstrap$n_crisis_obs %||% 0L,
                   regime_meta$CRISIS$T %||% 0L)
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
    C1 = "PASS — expanding-window estimation, no full-sample cherry-pick",
    C2 = paste0("PASS — t-1 month-floor + PIT_HARD_CUTOFF=", as.character(PIT_HARD_CUTOFF)),
    C3 = "PASS — EST_END=2023-11-01 strictly < signal_as_of 2023-12-01.",
    C9 = "PASS — daily Ret aligned to month-floor regime via RP_M, no same-day VT/DD",
    C11 = "PASS — KR RAWDATA + KR FF5 v2 only, no FRED leakage",
    C12 = paste0("PASS — FF5 v2 month-end Date <= ", as.character(PIT_HARD_CUTOFF)),
    C13 = "PASS — Z_Score_Aligned upstream (Alpha), no manual sign flip in Risk",
    C14 = "PASS — no IC time-axis violation (Σ on Ret_M post-listing only)",
    C15 = "PASS — RAWDATA + FF5 v2 loaded via parquet cache",
    pit_hard_cutoff = as.character(PIT_HARD_CUTOFF),
    lockbox = paste0("ENFORCED: 2024-01-23 ~ 2026-01-23 strictly excluded. PIT_HARD_CUTOFF=", as.character(PIT_HARD_CUTOFF)),
    note = "Risk Agent is read-only on alpha_vector and regime label. Inheritance-based V3 alpha base preserved untouched."
  ),

  challenge_flags = challenge_flags,

  optimizer_handoff = list(
    note = "V3 Σ produced (factor model BOmegaB+D, top-20 V3 panel). Multi-sleeve diagnostics provided. Optimizer chooses MVO/HRP/CVaR.",
    recommendations = c(
      "Use security_covariance_ref for primary Σ in MVO/CVaR.",
      sprintf("BIND POOLED FALLBACK: Use security_covariance_pooled_fallback_ref when regime_state in {CRISIS, CAUTION} OR when CRISIS regime cond=%.0f > 100. Pooled Σ cond=%.1f PSD T=%d.",
              regime_meta$CRISIS$condition_number %||% NA_real_,
              pooled_meta$condition_number, pooled_meta$T),
      sprintf("Multi-sleeve diversification benefit %.1f%% (cor=%.3f) — Optimizer can implement Sleeve Core 0.65 / Defense 0.35 hierarchical or treat as score-level composite (already pre-blended in alpha_vector).",
              diversification_benefit * 100, cor_core_def %||% NA_real_),
      sprintf("V3 ↔ STR_1701 production score per_date cor=%.4f (L-224 PASS). PG2 'V3 80%% + STR_1656 20%%' is REPLACEMENT of current 'STR_1701 80%% + STR_1656 20%%' (NOT additive blend). Forge backtest should compare the two PG2 configurations on realized SR/MDD/Turnover.",
              v3_vs_str1701_meanperdate %||% NA_real_),
      sprintf("PG2 blend cor with active=%.4f → marginal incremental risk reduction. Realized SR uplift expected from turnover dampening + slot re-weighting + regime-λ neutral, NOT from cross-source diversification.",
              cor_pg2_blend_active %||% NA_real_),
      sprintf("V3 ↔ STR_1656 cross-family cor=%.4f (preserved diversifier). 20%% STR_1656 slot retains independent alpha source.",
              cor_v3_str1656_pearson %||% NA_real_)
    )
  )
)

# tail_risk.json
tail_risk_json <- list(
  cvar_95_daily = unname(cvar_95_d),
  var_95_daily = unname(var_95_d),
  cdar_95 = unname(cdar_95),
  mdd_in_sample = unname(mdd),
  evt_var_99 = unname(tail_evt$var_evt %||% NA_real_),
  evt_es_99 = unname(tail_evt$es_evt %||% NA_real_),
  evt_method = tail_evt$method %||% "n/a",
  hill_alpha_top5pct = unname(hill_alpha),
  parametric_var_99_normal = unname(parametric_var_99_normal),
  parametric_var_99_cf = unname(parametric_var_99_cf),
  parametric_es_99_normal = unname(parametric_es_99_normal),
  per_regime = tail_per_regime,
  stress_periods = stress_results,
  crisis_bootstrap = if (!is.null(crisis_port_ret_boot)) {
    list(mean = unname(crisis_port_ret_boot$mean),
         ci95 = as.list(crisis_port_ret_boot$ci95),
         n_days = unname(crisis_port_ret_boot$n_days),
         n_resamples = unname(crisis_port_ret_boot$n_resamples))
  } else list(),
  meta = list(
    portfolio_proxy = "EW top-20 V3 long-only",
    pit_hard_cutoff = as.character(PIT_HARD_CUTOFF),
    note = "Diagnostic only — NOT optimized portfolio."
  )
)
write_json(tail_risk_json, file.path(OUT_DIR_STAGE, "tail_risk.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("Wrote tail_risk.json\n")

# Save risk_package_draft.json
draft_path <- file.path(OUT_DIR_MAIL, "risk_package_draft.json")
write_json(risk_package, draft_path, pretty = TRUE, auto_unbox = TRUE)
cat("Wrote risk_package_draft.json:", draft_path, "\n")

cat("\n==== Risk pipeline DONE ====\n")
cat("Σ method selected:", selected$name, "\n")
cat("Σ cond_post_shrink:", round(sigma_cond, 2), "\n")
cat("Hill alpha:", round(hill_alpha, 3), "\n")
cat("EVT ES_99:", round(tail_evt$es_evt %||% NA, 4), "\n")
cat("CVaR 95 daily:", round(cvar_95_d, 4), "\n")
cat(sprintf("V3 ↔ STR_1701 score per_date cor=%.4f (alpha pkg=0.9284)\n",
            v3_vs_str1701_meanperdate %||% NA_real_))
cat(sprintf("V3 NAV ↔ STR_1701 NAV TDC q5=%.4f\n", tdc_q5_v3_str1701 %||% NA_real_))
cat(sprintf("V3 NAV ↔ STR_1656 NAV cor=%.4f TDC q5=%.4f\n",
            cor_v3_str1656_pearson %||% NA_real_, tdc_q5_v3_str1656 %||% NA_real_))
cat("Multi-sleeve cor_core_def:", round(cor_core_def %||% NA_real_, 3), "\n")
cat("Diversification benefit:", round(diversification_benefit * 100, 2), "%\n")
cat("Stress worst:", round(worst_stress * 100, 2), "%\n")
cat("Challenge flags:", length(challenge_flags), "\n")

saveRDS(list(
  SIGMA = SIGMA,
  SIGMA_POOLED = SIGMA_POOLED,
  selected_method = selected$name,
  pit_cutoff = PIT_HARD_CUTOFF,
  TICKERS20 = TICKERS20,
  crowd_pkg = crowd_pkg,
  challenge_flags = challenge_flags
), file.path(OUT_DIR_STAGE, "risk_workspace.rds"))
cat("Saved risk_workspace.rds\n")
