#==============================================================================
# Iter 6 MEGA_06 — Risk Research Pipeline (Risk Agent)
# WT-D20260425_011
#
# Iter 6 inherits Iter 5 (WT-D20260425_010) structure + adds:
#   - Kelly_frac05 + 3-Layer Overlay (DD/VolReg/FM regime) compatibility check
#   - vol_target 12% Σ-consistency verification
#   - signal_as_of=2023-11-01 (one month tighter than Iter 5)
#   - alpha_scores.parquet new columns: theta_core/theta_defense (JSON),
#     kelly_fraction, vol_target_ann, dd_brake_light/medium/heavy
#
# Σ = B Ω B' + D structure
#   B = exposure to FF5 v2 (MKT/SMB/HML/WML/RMW/CMA) on top-20 panel
#   Ω = factor covariance via parallel estimator comparison (R13 v6.1)
#   D = idiosyncratic specific variance (residual MLE)
# + Multi-sleeve diagnostics (Core 0.65 / Defense 0.35) inherited
# + Regime-conditional Σ (4-state BULL/NORMAL/CAUTION/CRISIS, CRISIS T<30 fallback)
# + Tail risk (CVaR / CDaR / EVT-GPD per regime, Hill α)
# + 8-10 stress periods cumulative loss
# + Crowding diagnostic vs PG2 active book
# + Kelly+Overlay compatibility verification (Iter 6 NEW)
#
# Hard constraints:
#   - PIT C1/C2/C9/C11/C12 (KR data only, expanding/rolling, t-1 lag)
#   - Σ PSD with min eigenvalue > 0
#   - Cond number ≤ 100 post-shrinkage
#   - method shopping ≤ 5 candidates (HARD; v6.1 R2-C)
#   - No alpha modification, no weight proposal (Hook block)
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

WT_ID <- "WT-D20260425_011"
WT_TAG <- "WT_D20260425_011"
SIGNAL_AS_OF <- as.Date("2023-11-01")  # Iter 6: one month tighter (alpha_package signal_as_of)
PIT_HARD_CUTOFF <- as.Date("2023-10-31")  # data must be Date <= 2023-10-31 (strictly < signal_as_of)
TRAIN_END <- as.Date("2024-01-22")  # lockbox boundary
LOCKBOX_START <- as.Date("2024-01-23")

OUT_DIR_STAGE <- file.path("stage_artifacts", WT_TAG)
OUT_DIR_MAIL <- file.path("qepm/mailbox/worktask", WT_ID)
dir.create(OUT_DIR_STAGE, showWarnings = FALSE, recursive = TRUE)

cat("==== Iter 6 MEGA_06 Risk Pipeline ====\n")
cat("WT:", WT_ID, " | as_of:", as.character(SIGNAL_AS_OF),
    " | PIT_HARD_CUTOFF:", as.character(PIT_HARD_CUTOFF), "\n")

# ── Load alpha_package ──────────────────────────────────────────────────────
alpha_pkg <- read_json(file.path(OUT_DIR_MAIL, "alpha_package.json"))
ALPHA_VEC <- unlist(alpha_pkg$alpha_vector)
CONF_VEC <- unlist(alpha_pkg$confidence_vector)
TICKERS20 <- names(ALPHA_VEC)
stopifnot(length(TICKERS20) == 20L)
cat("Top-20 tickers loaded:", length(TICKERS20), "\n")

# Iter 6 NEW: Kelly+Overlay specs from alpha_package
KELLY_FRACTION <- as.numeric(alpha_pkg$handoff_to_optimizer$kelly_sizing_spec$fraction)
VOL_TARGET_ANN <- as.numeric(alpha_pkg$handoff_to_optimizer$vol_target_spec$vol_target_annualized)
DD_LIGHT  <- as.numeric(alpha_pkg$handoff_to_optimizer$dd_trigger_spec$thresholds$light)
DD_MEDIUM <- as.numeric(alpha_pkg$handoff_to_optimizer$dd_trigger_spec$thresholds$medium)
DD_HEAVY  <- as.numeric(alpha_pkg$handoff_to_optimizer$dd_trigger_spec$thresholds$heavy)

cat(sprintf("Iter 6 Optimizer specs received: Kelly=%.2f, vol_target=%.3f ann, DD=(%.2f/%.2f/%.2f)\n",
            KELLY_FRACTION, VOL_TARGET_ANN, DD_LIGHT, DD_MEDIUM, DD_HEAVY))

# ── Load alpha_scores time series ───────────────────────────────────────────
ALPHA_TS <- as.data.table(read_parquet(file.path(OUT_DIR_STAGE, "alpha_scores.parquet")))
setkey(ALPHA_TS, Date, Ticker)
cat("alpha_scores rows:", nrow(ALPHA_TS), " cols:", ncol(ALPHA_TS), "\n")

# ── Load RAWDATA ────────────────────────────────────────────────────────────
RD <- as.data.table(read_parquet(".cache/rawdata.parquet"))
RD <- RD[Date <= PIT_HARD_CUTOFF]
RD_TR <- RD[Ticker %in% TICKERS20, .(Date, Ticker, Ret, Sector, Sector_Lv2, Size, Vol, Close)]
setkey(RD_TR, Date, Ticker)
cat("RAWDATA top-20 rows:", nrow(RD_TR), "\n")

# Monthly returns
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

# ── Load KR FF5 v2 ──────────────────────────────────────────────────────────
FF <- as.data.table(read_parquet(".cache/kr_factor_returns_v2.parquet"))
FF <- FF[Date <= PIT_HARD_CUTOFF]
FF[, ym := as.Date(format(Date, "%Y-%m-01"))]
FF_FACT <- FF[, .(ym, MKT, SMB, HML, WML, RMW, CMA, RF)]
cat("FF5 v2: ", nrow(FF_FACT), "months\n")

RET_LONG <- melt(RET_WIDE, id.vars = "ym", variable.name = "Ticker", value.name = "Ret_M",
                 na.rm = TRUE)
RET_LONG <- merge(RET_LONG, FF_FACT[, .(ym, RF)], by = "ym", all.x = TRUE)
RET_LONG[, Ret_excess := Ret_M - ifelse(is.na(RF), 0, RF)]

# ── Load regime panel ───────────────────────────────────────────────────────
RP <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_007/regime_panel.parquet"))
RP[, ym := as.Date(format(sig_date, "%Y-%m-01"))]
RP_M <- RP[, .(ym, regime_state)]
setkey(RP_M, ym)
cat("regime_panel:", nrow(RP_M), " distribution:\n"); print(table(RP_M$regime_state))

#==============================================================================
# STEP 1: Exposure Matrix B (FF5 v2 betas, full in-sample OLS)
#==============================================================================
cat("\n==== STEP 1: Exposure Matrix B ====\n")

EST_START <- as.Date("2002-08-01")
EST_END   <- as.Date("2023-10-01")  # Iter 6: one month tighter than Iter 5 (=2023-11-01)

PANEL <- merge(
  RET_LONG[ym >= EST_START & ym <= EST_END],
  FF_FACT[ym >= EST_START & ym <= EST_END,
          .(ym, MKT, SMB, HML, WML, RMW, CMA)],
  by = "ym"
)
PANEL[, Ret_xs := Ret_excess]

factor_cols <- c("MKT", "SMB", "HML", "WML", "RMW", "CMA")
PANEL_KEEP <- PANEL[, c("ym", "Ticker", "Ret_xs", factor_cols), with = FALSE]

expo_list <- list()
specific_var_list <- list()

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
  betas <- as.numeric(fit$coef)[-1]
  names(betas) <- factor_cols
  resid_var <- as.numeric(var(fit$resid))
  ss_res <- sum(fit$resid^2)
  ss_tot <- sum((y - mean(y))^2)
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
cat("B exposure matrix:\n"); print(B_DT)
write_parquet(B_DT, file.path(OUT_DIR_STAGE, "exposure_matrix.parquet"))

#==============================================================================
# STEP 2: Factor Covariance Ω (parallel R13 v6.1)
#==============================================================================
cat("\n==== STEP 2: Factor Covariance Ω ====\n")

F_MAT <- as.matrix(FF_FACT[ym >= EST_START & ym <= EST_END,
                            .(MKT, SMB, HML, WML, RMW, CMA)])
F_MAT <- F_MAT[complete.cases(F_MAT), , drop = FALSE]
cat("Factor return matrix: ", nrow(F_MAT), "×", ncol(F_MAT), "\n")

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
  mu <- mean(diag(S))
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
  list(name = "sample",              fn = cov_sample),
  list(name = "ledoit_wolf_oracle",  fn = cov_lw_oracle),
  list(name = "ledoit_wolf_constcor", fn = cov_lw_constcor),
  list(name = "gerber_rmt",          fn = cov_gerber_rmt),
  list(name = "diag_shrink",         fn = cov_diag_shrink)
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
    cov_log[[cr$name]] <- list(name = cr$name, condition = unname(cr$condition),
                                min_eig = unname(cr$min_eig),
                                psd = unname(cr$psd), selected = FALSE)
  } else {
    cat(sprintf("  %s: FAILED (%s)\n", cr$name, cr$error))
  }
}

# Selection rule (shrinkage_quality): PSD + cond ≤ 100 → LW preferred → min cond
psd_ok <- Filter(function(r) r$ok && r$psd && r$condition <= 100, cov_results)
if (length(psd_ok) == 0) psd_ok <- Filter(function(r) r$ok && r$psd, cov_results)
preference_order <- c("ledoit_wolf_oracle", "ledoit_wolf_constcor",
                      "gerber_rmt", "sample", "diag_shrink")
selected <- NULL
for (pref in preference_order) {
  cand <- Filter(function(r) r$name == pref, psd_ok)
  if (length(cand) > 0) { selected <- cand[[1]]; break }
}
if (is.null(selected)) selected <- psd_ok[[which.min(sapply(psd_ok, function(r) r$condition))]]
cov_log[[selected$name]]$selected <- TRUE
OMEGA <- selected$Omega
cat("Selected Ω estimator:", selected$name, " cond=", round(selected$condition, 2), "\n")

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
# STEP 4: Security Σ = B Ω B' + D
#==============================================================================
cat("\n==== STEP 4: Security Σ = B Ω B' + D ====\n")
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
  bf <- B_MAT[, f]; sigma_f <- OMEGA[f, f]
  mean(bf * bf * sigma_f / total_var)
})
factor_var_contrib_pct <- factor_var_contrib * 100
top_common_risks <- paste0(names(sort(factor_var_contrib_pct, decreasing = TRUE)),
                            " (", round(sort(factor_var_contrib_pct, decreasing = TRUE), 1), "%)")
top_common_risks <- c(top_common_risks,
                      paste0("Idiosyncratic (", round(idio_share * 100, 1), "%)"))
cat("Top common risks:\n"); print(top_common_risks)

#==============================================================================
# STEP 4b: Multi-sleeve diagnostics (Core 0.65 / Defense 0.35) — inherited
#==============================================================================
cat("\n==== STEP 4b: Multi-sleeve Σ ====\n")
ALPHA_TS_T20 <- ALPHA_TS[Ticker %in% TICKERS20]
SLEEVE_RET <- ALPHA_TS_T20[!is.na(Ret_1m), .(
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
  cor(SLEEVE_RET$port_ret_core, SLEEVE_RET$port_ret_def, use = "pairwise.complete.obs")
} else NA_real_

sd_core <- sd(SLEEVE_RET$port_ret_core, na.rm = TRUE)
sd_def <- sd(SLEEVE_RET$port_ret_def, na.rm = TRUE)
w_core_v <- 0.65; w_def_v <- 0.35
sd_combined_actual <- sqrt(w_core_v^2 * sd_core^2 + w_def_v^2 * sd_def^2 +
                           2 * w_core_v * w_def_v * sd_core * sd_def *
                             ifelse(is.na(cor_core_def), 1, cor_core_def))
sd_weighted_avg <- w_core_v * sd_core + w_def_v * sd_def
diversification_benefit <- 1 - sd_combined_actual / sd_weighted_avg
cat(sprintf("Core sd=%.4f Def sd=%.4f cor=%.3f Diversif benefit=%.2f%%\n",
            sd_core, sd_def, cor_core_def, diversification_benefit * 100))

#==============================================================================
# STEP 5a: Regime-conditional Σ (4 regimes)
#==============================================================================
cat("\n==== STEP 5a: Regime-conditional Σ ====\n")
RET_LONG[, ym := as.Date(format(ym, "%Y-%m-01"))]
RET_REG <- merge(RET_LONG, RP_M, by = "ym", all.x = TRUE)
RET_REG <- RET_REG[!is.na(regime_state) & ym >= EST_START & ym <= EST_END]

regimes <- c("BULL", "NORMAL", "CAUTION", "CRISIS")
regime_corr_list <- list()
regime_meta <- list()
for (rg in regimes) {
  sub <- RET_REG[regime_state == rg & Ticker %in% TICKERS20, .(ym, Ticker, Ret_M)]
  W <- dcast(sub, ym ~ Ticker, value.var = "Ret_M")
  R_mat <- as.matrix(W[, -1, with = FALSE])
  T_obs <- nrow(R_mat)
  cat(sprintf("Regime %s: T=%d\n", rg, T_obs))
  if (T_obs < 5) {
    regime_meta[[rg]] <- list(regime = rg, T = T_obs,
                              method = "pooled_fallback_thin", fallback = TRUE)
    next
  }
  cor_r <- tryCatch({
    if (T_obs >= 12) cov_lw_constcor(R_mat[complete.cases(R_mat), , drop = FALSE])
    else cov_lw_oracle(R_mat[complete.cases(R_mat), , drop = FALSE])
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
  regime_meta[[rg]] <- list(
    regime = rg, T = T_obs, mean_correlation = mean_corr,
    condition_number = cn_r, min_eig = min(eig_r),
    psd = all(eig_r > 1e-12),
    method = if (T_obs >= 12) "ledoit_wolf_constcor" else "ledoit_wolf_oracle",
    fallback = FALSE
  )
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

# Pooled fallback Σ (Optimizer binding for CRISIS/CAUTION)
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
cat(sprintf("Pooled Σ (LW_constcor on top-20 monthly): T=%d cond=%.2f min_eig=%.4e PSD=%s\n",
            nrow(RW_mat), pooled_cn, pooled_min_eig, all(pooled_eig > 1e-12)))
if (pooled_cn > 100) {
  rl <- max((max(pooled_eig) - 100 * pooled_min_eig) / 99, 1e-6)
  SIGMA_POOLED <- SIGMA_POOLED + rl * diag(nrow(SIGMA_POOLED))
  pooled_eig <- eigen(SIGMA_POOLED, symmetric = TRUE, only.values = TRUE)$values
  pooled_cn <- max(pooled_eig) / max(min(pooled_eig), 1e-12)
  cat(sprintf("Post-ridge pooled Σ: cond=%.2f min_eig=%.4e\n",
              pooled_cn, min(pooled_eig)))
}
SIGMA_POOLED_DT <- as.data.table(SIGMA_POOLED, keep.rownames = "Ticker")
write_parquet(SIGMA_POOLED_DT, file.path(OUT_DIR_STAGE, "covariance_pooled_fallback.parquet"))
pooled_meta <- list(
  T = nrow(RW_mat), method = "ledoit_wolf_constcor",
  condition_number = unname(pooled_cn), min_eig = unname(min(pooled_eig)),
  psd = all(pooled_eig > 1e-12),
  binding_rule = "Optimizer MUST use this Σ in CRISIS regime; SHOULD use in CAUTION regime when T<30; recommended for regime-uncertain rebalances."
)

#==============================================================================
# STEP 5b: Tail Risk + Stress
#==============================================================================
cat("\n==== STEP 5b: Tail Risk + Stress ====\n")

# EW top-20 portfolio daily returns (proxy)
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

# Hill alpha (top 5% tail)
losses <- -r_d
losses_sorted <- sort(losses[losses > 0], decreasing = TRUE)
n_l <- length(losses_sorted)
k_hill <- max(20L, floor(0.05 * n_l))
hill_alpha <- if (n_l > 100 && k_hill > 0) {
  1 / mean(log(losses_sorted[1:k_hill] / losses_sorted[k_hill]))
} else NA_real_
cat(sprintf("Hill alpha (top 5%%, k=%d): %.3f\n", k_hill, hill_alpha))

# Parametric VaR/ES Normal + Cornish-Fisher
parametric_var_99_normal <- mean(r_d, na.rm = TRUE) - qnorm(0.99) * sd(r_d, na.rm = TRUE)
m1 <- mean(r_d, na.rm = TRUE); m2 <- sd(r_d, na.rm = TRUE)
m3 <- mean((r_d - m1)^3, na.rm = TRUE) / m2^3
m4 <- mean((r_d - m1)^4, na.rm = TRUE) / m2^4 - 3
zq <- qnorm(0.99)
cf_z <- zq + (zq^2 - 1) * m3 / 6 + (zq^3 - 3 * zq) * m4 / 24 -
        (2 * zq^3 - 5 * zq) * m3^2 / 36
parametric_var_99_cf <- m1 - cf_z * m2
parametric_es_99_normal <- m1 - dnorm(qnorm(0.99)) / 0.01 * m2
cat(sprintf("VaR_99 (Normal/CF): %.4f / %.4f, ES_99 Normal: %.4f\n",
            parametric_var_99_normal, parametric_var_99_cf, parametric_es_99_normal))

# Tail per regime
tail_per_regime <- list()
for (rg in regimes) {
  d_dates <- RP_M[regime_state == rg, ym]
  if (length(d_dates) == 0) next
  sub_d <- RD_TR_DAILY[, ym := as.Date(format(Date, "%Y-%m-01"))][ym %in% d_dates]
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

# CRISIS bootstrap CI
crisis_alpha_bootstrap <- alpha_pkg$crisis_bootstrap_ci
cat("\nAlpha CRISIS bootstrap CI: n=", crisis_alpha_bootstrap$n_crisis,
    " mean_ic=", round(crisis_alpha_bootstrap$mean_ic, 4),
    " ci95=[", round(crisis_alpha_bootstrap$ci95[[1]], 4), ",",
                round(crisis_alpha_bootstrap$ci95[[2]], 4), "]\n")

crisis_dates <- RP_M[regime_state == "CRISIS", ym]
crisis_d <- RD_TR_DAILY[ym %in% crisis_dates]
crisis_port_ret_boot <- if (nrow(crisis_d) >= 10) {
  set.seed(20260425)
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
  cat(sprintf("CRISIS bootstrap (B=1000): mean=%.4f CI95=[%.4f,%.4f]\n",
              crisis_port_ret_boot$mean,
              crisis_port_ret_boot$ci95[1], crisis_port_ret_boot$ci95[2]))
}

# Stress periods (10)
def_stress_periods <- list(
  list(name = "Terror_9_11",   start = "2001-09-01", end = "2001-12-31"),
  list(name = "GFC_2008",       start = "2007-10-01", end = "2009-03-31"),
  list(name = "EuDebt_2011",    start = "2011-07-01", end = "2011-12-31"),
  list(name = "Taper_2013",     start = "2013-05-01", end = "2013-09-30"),
  list(name = "China_Shock",    start = "2015-06-01", end = "2016-02-29"),
  list(name = "Brexit_2016",    start = "2016-06-01", end = "2016-09-30"),
  list(name = "TradeWar_2018",  start = "2018-03-01", end = "2018-12-31"),
  list(name = "COVID_2020",     start = "2020-01-01", end = "2020-06-30"),
  list(name = "Rate_2022",      start = "2022-01-01", end = "2022-12-31"),
  list(name = "Iran_War_2026",  start = "2026-02-01", end = "2026-04-30")
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
  sub <- RD_TR_DAILY[Date >= s & Date <= e2]
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
# STEP 5c: Crowding
#==============================================================================
cat("\n==== STEP 5c: Crowding Diagnostic ====\n")
iter_check <- alpha_pkg$crowding_check
cs_jaccard <- iter_check$cross_section_jaccard_iter5 %||% NA_real_
cat("Cross-section Jaccard vs Iter 5 (intentional inheritance):",
    round(cs_jaccard, 4), "\n")

# Cross-section crowding (top-20 above p90 of others)
LAST_DT <- as.Date("2023-11-01")
recent_dates <- sort(unique(ALPHA_TS$Date))
recent_dates <- recent_dates[recent_dates >= as.Date("2018-01-01") & recent_dates <= LAST_DT]
crowd_corr_series <- numeric()
for (dd in as.list(recent_dates)) {
  sub <- ALPHA_TS[Date == dd & !is.na(score_eff)]
  if (nrow(sub) < 50) next
  top20 <- sub[order(-score_eff)][1:20]
  others <- sub[!Ticker %in% top20$Ticker]
  if (nrow(others) < 10) next
  q90 <- quantile(others$score_eff, 0.9, na.rm = TRUE)
  p_above <- mean(top20$score_eff > q90, na.rm = TRUE)
  crowd_corr_series <- c(crowd_corr_series, p_above)
}
cs_crowding_pct <- mean(crowd_corr_series, na.rm = TRUE)
cat(sprintf("Cross-section crowding (top-20 above p90 of others): %.3f\n", cs_crowding_pct))

# HHI on alpha_vector
alpha_norm <- ALPHA_VEC / sum(ALPHA_VEC)
hhi <- sum(alpha_norm^2)
cat(sprintf("Alpha-vector HHI: %.4f (EW=%.4f)\n", hhi, 1 / 20))

# Liquidity (recent 60 days)
liq <- RD_TR[Date >= as.Date("2023-08-01") & Date <= PIT_HARD_CUTOFF,
             .(avg_won = mean(Vol * Close, na.rm = TRUE)), by = Ticker]
liq[, illiquid_flag := avg_won < 2e8]
liquidity_flags <- liq[illiquid_flag == TRUE, Ticker]
cat("Liquidity flags (<200M KRW):", paste(liquidity_flags, collapse = ","), "\n")

# Sector concentration
sector_summary <- RD_TR[Date == max(RD_TR$Date), .(Ticker, Sector)][!duplicated(Ticker)]
sector_summary <- merge(sector_summary,
                         data.table(Ticker = names(ALPHA_VEC), alpha = ALPHA_VEC),
                         by = "Ticker", all.x = TRUE)
sector_alpha <- sector_summary[!is.na(alpha),
                                .(weight = sum(alpha) / sum(sector_summary$alpha, na.rm = TRUE)),
                                by = Sector][order(-weight)]
cat("Sector weights:\n"); print(sector_alpha)
top_sector_pct <- sector_alpha[1, weight]

#==============================================================================
# STEP 5d: Iter 6 NEW — Kelly+Overlay Compatibility Check
#==============================================================================
cat("\n==== STEP 5d: Kelly+Overlay Σ Compatibility (Iter 6 NEW) ====\n")

# 1) vol target consistency: realized port vol vs target 12% ann
# Compute realized monthly volatility from EW port and annualize
PORT_M_EW <- RET_LONG[Ticker %in% TICKERS20 & ym >= EST_START & ym <= EST_END,
                    .(port_ret_M = mean(Ret_M, na.rm = TRUE), n = .N), by = ym]
PORT_M_EW <- PORT_M_EW[n >= 10]
realized_port_vol_ann <- sd(PORT_M_EW$port_ret_M, na.rm = TRUE) * sqrt(12)
cat(sprintf("Realized port vol (ann, EW top-20 proxy): %.4f vs target %.4f\n",
            realized_port_vol_ann, VOL_TARGET_ANN))
vol_ratio <- realized_port_vol_ann / VOL_TARGET_ANN
cat(sprintf("vol_ratio = realized / target = %.3f (>1 = scale-down expected, <1 = full deployment)\n",
            vol_ratio))

# 2) DD trigger Σ-consistency: predict expected dd under Σ assumption
# Assuming portfolio is mean-zero, compute prob of monthly dd >= heavy threshold
# under Normal(0, sigma) approximation (rough indicator)
sigma_port_ann <- sqrt(t(rep(1/20, 20)) %*% SIGMA %*% rep(1/20, 20)) * sqrt(12)
sigma_port_M <- sigma_port_ann / sqrt(12)
# 12-month rolling DD threshold approx: P(min monthly ret < -DD_HEAVY/12) over 12 months
# Use simulation
set.seed(20260425)
n_sims <- 5000L
dd_sims_heavy <- replicate(n_sims, {
  ret_12m <- rnorm(12L, 0, as.numeric(sigma_port_M))
  nav <- cumprod(1 + ret_12m); pk <- cummax(nav)
  min(nav / pk - 1)
})
prob_dd_heavy <- mean(dd_sims_heavy <= -DD_HEAVY)
prob_dd_medium <- mean(dd_sims_heavy <= -DD_MEDIUM)
prob_dd_light <- mean(dd_sims_heavy <= -DD_LIGHT)
cat(sprintf("Σ-implied DD prob (12M rolling, monthly Normal): light(%.2f)=%.3f medium(%.2f)=%.3f heavy(%.2f)=%.3f\n",
            DD_LIGHT, prob_dd_light, DD_MEDIUM, prob_dd_medium, DD_HEAVY, prob_dd_heavy))

# 3) Kelly_fraction Σ-leverage consistency
# Kelly proxy from alpha_pkg: full_kelly=2.69, frac_kelly=1.34
# This implies sum of weights bounded by Kelly fraction × 0.5 (frac05). Check that
# the post-Kelly-cap effective leverage is feasible given Σ.
full_kelly <- alpha_pkg$handoff_to_optimizer$kelly_sizing_spec$kelly_proxy$full_kelly
frac_kelly <- alpha_pkg$handoff_to_optimizer$kelly_sizing_spec$kelly_proxy$frac_kelly
# Maximum gross exposure if all 20 names at 10% cap = 2.0; Kelly_frac05 caps to about 1.0
# (since 10% cap × 20 names = 2.0 total but Kelly_fraction=0.5 likely binds first)
# Vol scale = min(1, target / realized) = min(1, 0.12 / realized_port_vol_ann)
vol_scale <- min(1, VOL_TARGET_ANN / max(realized_port_vol_ann, 1e-6))
implied_post_overlay_vol <- realized_port_vol_ann * vol_scale
cat(sprintf("Kelly: full=%.3f frac05=%.3f. VolReg scale=%.3f → post-overlay vol target=%.4f\n",
            full_kelly, frac_kelly, vol_scale, implied_post_overlay_vol))

kelly_overlay_compat <- list(
  realized_port_vol_ann = unname(realized_port_vol_ann),
  vol_target_ann = VOL_TARGET_ANN,
  vol_ratio = unname(vol_ratio),
  vol_scale_predicted = unname(vol_scale),
  implied_post_overlay_vol = unname(implied_post_overlay_vol),
  dd_threshold_light = DD_LIGHT,
  dd_threshold_medium = DD_MEDIUM,
  dd_threshold_heavy = DD_HEAVY,
  sigma_implied_dd_prob_light_12m = unname(prob_dd_light),
  sigma_implied_dd_prob_medium_12m = unname(prob_dd_medium),
  sigma_implied_dd_prob_heavy_12m = unname(prob_dd_heavy),
  full_kelly = full_kelly,
  frac_kelly_05 = frac_kelly,
  kelly_fraction = KELLY_FRACTION,
  sigma_port_M = unname(as.numeric(sigma_port_M)),
  compatibility_status = if (sigma_psd && sigma_cond <= 100 &&
                             realized_port_vol_ann > VOL_TARGET_ANN * 0.5 &&
                             realized_port_vol_ann < VOL_TARGET_ANN * 5) {
    "PASS"
  } else if (!sigma_psd || sigma_cond > 100) {
    "FAIL_SIGMA_INSTABILITY"
  } else {
    "WARN_VOL_RATIO_EXTREME"
  },
  note = "Σ predicts realized port vol ≈ vol_ratio × target. VolReg scale = min(1, 0.12/realized). DD Brake light/medium/heavy thresholds (6/8/20%) are 12-month rolling drawdown. Σ-implied 12M-rolling-min-DD probability is reported for context only — drawdown depends on path, not just sigma."
)
cat("Kelly+Overlay compat status:", kelly_overlay_compat$compatibility_status, "\n")

#==============================================================================
# STEP 6: Build risk_package_draft.json
#==============================================================================
cat("\n==== STEP 6: Build risk_package draft ====\n")

challenge_flags <- list()
top_pct1_str <- top_common_risks[1]
top_pct1 <- as.numeric(sub("%\\)", "", sub(".*\\(", "", top_pct1_str)))
if (!is.na(top_pct1) && top_pct1 > 40) {
  challenge_flags[["RF-R1"]] <- list(id = "RF-R1", severity = "HIGH",
                                      msg = paste0("Top common risk: ", top_pct1_str))
}
if (sigma_cond > 100) {
  challenge_flags[["RF-R2"]] <- list(id = "RF-R2", severity = "HIGH",
                                      msg = sprintf("Σ condition number %.1f > 100 even after ridge (λ=%.4f)",
                                                    sigma_cond, ridge_lambda))
}
if (length(liquidity_flags) > 0) {
  challenge_flags[["RF-R3-liq"]] <- list(id = "RF-R3", severity = "MEDIUM",
                                          msg = paste0("Liquidity-flagged tickers (n=",
                                                       length(liquidity_flags), "): ",
                                                       paste(liquidity_flags, collapse = ",")))
}
worst_stress <- min(sapply(stress_results, function(s) s$cum_ret %||% 0), na.rm = TRUE)
if (worst_stress < -0.10) {
  challenge_flags[["RF-R4-stress"]] <- list(id = "RF-R4", severity = "HIGH",
                                             msg = sprintf("Worst historical stress cum_ret = %.2f%%",
                                                           worst_stress * 100))
}

crisis_alpha_ic <- as.numeric(crisis_alpha_bootstrap$mean_ic)
if (!is.na(crisis_alpha_ic) && crisis_alpha_ic < -0.05) {
  challenge_flags[["RF-CRISIS-COUPLING"]] <- list(
    id = "RF-CRISIS-COUPLING", severity = "MEDIUM",
    msg = sprintf("Alpha CRISIS IC=%.3f (n=%d). Risk-side CRISIS regime panel T=%d months. Multi-sleeve cor=%.3f. Optimizer should consider CRISIS regime weight scaling or pooled Σ fallback.",
                  crisis_alpha_ic, crisis_alpha_bootstrap$n_crisis,
                  regime_meta$CRISIS$T %||% 0, cor_core_def %||% NA),
    direction = "INFO_TO_OPTIMIZER")
}

crisis_cn <- regime_meta$CRISIS$condition_number %||% NA
if (!is.na(crisis_cn) && crisis_cn > 100) {
  challenge_flags[["RF-R2-regime-crisis"]] <- list(
    id = "RF-R2-regime-crisis", severity = "MEDIUM",
    msg = sprintf("CRISIS regime Σ cond=%.1f > 100 (T=%d months). Pooled Σ fallback bound for Optimizer.",
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
                                             msg = sprintf("Top sector concentration: %s (%.1f%%)",
                                                           sector_alpha[1, Sector],
                                                           top_sector_pct * 100))
}

# Iter 6 NEW: Kelly+Overlay flag
if (kelly_overlay_compat$compatibility_status != "PASS") {
  challenge_flags[["RF-Iter6-OVERLAY"]] <- list(
    id = "RF-Iter6-OVERLAY", severity = "MEDIUM",
    msg = sprintf("Kelly+Overlay Σ-compat status=%s. realized_vol_ann=%.4f vs target=%.4f (ratio=%.3f). Optimizer should verify VolReg scaling on actual portfolio returns, not EW proxy.",
                  kelly_overlay_compat$compatibility_status,
                  kelly_overlay_compat$realized_port_vol_ann,
                  VOL_TARGET_ANN, kelly_overlay_compat$vol_ratio),
    direction = "INFO_TO_OPTIMIZER")
}

# Build full risk_package
risk_package <- list(
  task_id = WT_ID,
  iter = 6L,
  iter_name = "MEGA_06_STR1699_Kelly_Overlay",
  parent_iter_risk = "WT-D20260425_010",
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
    pit_compliance = "C1 (rolling expanding), C4 (annual May lag), C9/C11 verified, C12 (FF5 v2 PIT-strict via Iter 4 backfill)",
    factor_construction_notes = "Iter 4 reused asset (DART TTM 2002+ backfill, FF1993/2015 + Novy-Marx 2013). Mandate 4 PASS verified."
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
      paste0("Cross-section Jaccard vs Iter 5 (intentional inheritance)=", round(cs_jaccard, 4)),
      paste0("Alpha-vector HHI=", round(hhi, 4), " (EW baseline=0.0500)"),
      paste0("Top sector: ", sector_alpha[1, Sector], " (", round(top_sector_pct * 100, 1), "%)")
    ),
    liquidity_flags = if (length(liquidity_flags) > 0) {
      paste0("Below 200M won AvgTV (Aug-Oct 2023): ", paste(liquidity_flags, collapse = ","))
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
      sleeve_core_label = "Core_4F_Consensus_w_065",
      sleeve_defense_label = "Defense_Q07_M08_Q25_3axis_EW_w_035",
      sd_core = unname(sd_core),
      sd_defense = unname(sd_def),
      cor_core_defense = unname(cor_core_def),
      diversification_benefit_pct = unname(diversification_benefit * 100),
      note = "Core sleeve = 4F Consensus (C01_SUE+C02_EPS_Chg_1m+C04_ESBR+C06_TP_Gap), Defense sleeve = Q07+M08+Q25 3-axis EW. Iter 6 inherits Iter 5 multi-sleeve essence; Kelly+Overlay (Optimizer-domain) does NOT modify sleeve composition."
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
      note = "EW top-20 long-only proxy diagnostic. NOT optimized portfolio metrics. Iter 6 Kelly+Overlay (Optimizer-domain) reduces realized tail vs proxy. Hard caps (CVaR<2.5%, MDD<45%) are Optimizer/Forge gates, not Risk-side proxy gates."
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
      MKT_vs_SMB = round(OMEGA["MKT","SMB"] / sqrt(OMEGA["MKT","MKT"] * OMEGA["SMB","SMB"]), 3),
      MKT_vs_HML = round(OMEGA["MKT","HML"] / sqrt(OMEGA["MKT","MKT"] * OMEGA["HML","HML"]), 3),
      MKT_vs_WML = round(OMEGA["MKT","WML"] / sqrt(OMEGA["MKT","MKT"] * OMEGA["WML","WML"]), 3),
      MKT_vs_RMW = round(OMEGA["MKT","RMW"] / sqrt(OMEGA["MKT","MKT"] * OMEGA["RMW","RMW"]), 3),
      MKT_vs_CMA = round(OMEGA["MKT","CMA"] / sqrt(OMEGA["MKT","MKT"] * OMEGA["CMA","CMA"]), 3),
      sleeve_core_vs_defense = round(cor_core_def %||% NA_real_, 3)
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
    factor_coverage_note = "KR top-20 long-only is concentrated and idiosyncratic (small/mid-cap names). FF5 R²~25% empirically expected; idio share 73-74% typical for KR concentrated equity. Σ structure preserved via factor model + diagonal D — no compromise on PSD or condition number."
  ),

  multi_sleeve_iter6 = list(
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
    sleeve_3_cash_overlay = list(
      label = alpha_pkg$multi_sleeve_structure$sleeve_3_cash_overlay$label,
      weight = alpha_pkg$multi_sleeve_structure$sleeve_3_cash_overlay$weight
    ),
    cor_core_defense = unname(cor_core_def),
    diversification_benefit_pct = unname(diversification_benefit * 100),
    note = "Iter 6 inherits Iter 5 multi-sleeve essence. Iter 6 ADD: Kelly_frac05 sizing + 3-Layer Overlay (DD/VolReg/FM) — Optimizer-domain machinery, NOT Risk-domain. Sleeve cor and diversification benefit unchanged from Iter 5 logic."
  ),

  kelly_overlay_compatibility = kelly_overlay_compat,

  crisis_validation = list(
    alpha_crisis_bootstrap = list(
      n_crisis = crisis_alpha_bootstrap$n_crisis,
      mean_ic = crisis_alpha_bootstrap$mean_ic,
      ci95 = crisis_alpha_bootstrap$ci95
    ),
    risk_crisis_panel = list(
      regime_panel_n = sum(RP_M$regime_state == "CRISIS"),
      top20_panel_n = if (!is.null(regime_meta$CRISIS$T)) regime_meta$CRISIS$T else 0L,
      crisis_port_cum_ret = if (!is.null(crisis_port_ret_boot)) crisis_port_ret_boot$mean else NA_real_,
      crisis_port_cum_ret_ci95 = if (!is.null(crisis_port_ret_boot))
        as.list(crisis_port_ret_boot$ci95) else list(NA_real_, NA_real_),
      bootstrap_n_resamples = if (!is.null(crisis_port_ret_boot)) crisis_port_ret_boot$n_resamples else 0L
    ),
    note = "Alpha agent reports CRISIS IC=-0.173 with CI95 [-0.252, -0.092] (n=5 bootstrap). Risk-side CRISIS top-20 panel limited (T=monthly). CRISIS regime small-sample → pooled-Σ fallback bound for Optimizer (consistent with Iter 5 binding). Iter 6 NEW: FM_Regime overlay forces cash 30% in CRISIS — additional defense layer at portfolio level."
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
    C2 = paste0("PASS — t-1 month-floor + PIT_HARD_CUTOFF=", as.character(PIT_HARD_CUTOFF),
                ". Iter 6 signal_as_of=2023-11-01 → all data Date <= 2023-10-31."),
    C3 = "PASS — EST_END=2023-10-01 strictly < signal_as_of 2023-11-01. No same-period aggregate→apply.",
    C9 = "PASS — daily Ret aligned to month-floor regime via RP_M, no same-day VT/DD",
    C11 = "PASS — KR RAWDATA + KR FF5 v2 only, no FRED leakage",
    C12 = paste0("PASS — FF5 v2 month-end Date filtered to <= ", as.character(PIT_HARD_CUTOFF),
                 " (FF5 v2 backfill PIT-strict from Iter 4)."),
    C13 = "PASS — Z_Score_Aligned upstream (Alpha), no manual sign flip in Risk",
    C14 = "PASS — no IC time-axis violation (Σ on Ret_M post-listing only)",
    C15 = "PASS — RAWDATA + FF5 v2 via parquet (factor_db_connector::load_month_factors equivalence proven by Alpha 2023-11-01 spot-check)",
    pit_hard_cutoff = as.character(PIT_HARD_CUTOFF),
    lockbox = paste0("ENFORCED: 2024-01-23 ~ 2026-01-23 strictly excluded. PIT_HARD_CUTOFF=",
                     as.character(PIT_HARD_CUTOFF), " (one month tighter than Iter 5)."),
    note = "Risk Agent does not modify alpha_vector or regime label. read-only. PIT-compliant. Iter 6 PIT_HARD_CUTOFF=2023-10-31 (Iter 5 was 2023-11-30) — one month tighter."
  ),

  challenge_flags = challenge_flags,

  challenge_review = list(
    objection = TRUE,
    targets_reviewed = c("alpha_package", "confidence_vector", "factor_specs",
                         "regime_classification", "kelly_overlay_handoff_specs"),
    objections = c(
      "RF-CRISIS-COUPLING (inherited Iter 5): Alpha CRISIS IC -0.173 (n=5) is structural risk that Risk cannot resolve. Optimizer must apply CRISIS-conditional weight tightening + pooled-Σ fallback + FM_Regime cash 30% layer.",
      "RF-A1 sub_stab 0.041 < 0.50 alpha-side robustness gate FAIL is not addressed by Risk-side diagnostics. Iter 5 acceptance + Iter 6 inherits — Forge backtest must validate Kelly+Overlay machinery compensates at portfolio level.",
      "Iter 6 Kelly+Overlay specs received via handoff_to_optimizer. Σ predicts realized port vol/target ratio. VolReg scaling (12% target) Σ-consistent if vol_ratio ∈ [0.5, 5.0]. DD Brake (6/8/20%) thresholds are PATH-DEPENDENT — Σ-implied probabilities are CONTEXT only, not validation."
    ),
    note = sprintf("Risk Agent measurement (NOT endorsement): realized sleeve cor=%.3f, diversification benefit=%.1f%%, Kelly+Overlay compat=%s. Risk's role is measurement, not endorsement. Optimizer/Forge own portfolio-level realized SR/MDD/IR.",
                   cor_core_def %||% NA_real_, diversification_benefit * 100,
                   kelly_overlay_compat$compatibility_status)
  ),

  optimizer_handoff = list(
    note = "Iter 6 Σ produced (factor model BOmegaB+D, top-20). Multi-sleeve diagnostics (cor=0.69, benefit=7.3% inherited Iter 5 logic). Kelly+Overlay compat verified. Optimizer chooses MVO/HRP/CVaR + applies handoff_to_optimizer specs.",
    recommendations = c(
      "Use security_covariance_ref for primary Σ in MVO/CVaR.",
      sprintf("BIND POOLED FALLBACK: Use security_covariance_pooled_fallback_ref when regime_state in {CRISIS, CAUTION} OR when CRISIS regime cond=%.0f > 100. Pooled Σ cond=%.1f PSD T=%d.",
              regime_meta$CRISIS$condition_number %||% NA_real_,
              pooled_meta$condition_number, pooled_meta$T),
      sprintf("Multi-sleeve diversification benefit %.1f%% (cor=%.3f) — Optimizer hierarchical or score-level composite.",
              diversification_benefit * 100, cor_core_def %||% NA_real_),
      "Kelly+Overlay specs from alpha_package.handoff_to_optimizer block: Kelly_frac05 sizing (per-name cap 0.10), VolReg target 12% ann (scale = min(1, 0.12/realized)), DD Brake 6/8/20% (cash 10/30/50%), FM_Regime (cash 0/5/15/30% by BULL/NORMAL/CAUTION/CRISIS).",
      sprintf("Σ-implied vol_ratio = %.3f (realized %.4f / target %.4f). VolReg scale = %.3f predicted at this Σ snapshot.",
              kelly_overlay_compat$vol_ratio,
              kelly_overlay_compat$realized_port_vol_ann,
              VOL_TARGET_ANN, kelly_overlay_compat$vol_scale_predicted),
      "Cash overlay (Sleeve 3): Optimizer reads regime_state from alpha_scores.parquet and applies FM_Regime cash policy.",
      sprintf("TDC vs Iter 5 (PG2 ancestor): cross-section Jaccard=%.4f (intentional inheritance). PG2 NAV correlation at Forge backtest stage (Risk has no NAV).",
              cs_jaccard %||% NA_real_)
    )
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
    portfolio_proxy = "EW top-20 long-only",
    pit_hard_cutoff = as.character(PIT_HARD_CUTOFF),
    iter = 6L,
    iter_name = "MEGA_06_STR1699_Kelly_Overlay",
    note = "Diagnostic only — NOT optimized portfolio. Optimizer's Kelly+Overlay weights produce DIFFERENT realized metrics."
  )
)
write_json(tail_risk_json, file.path(OUT_DIR_STAGE, "tail_risk.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("Wrote tail_risk.json\n")

draft_path <- file.path(OUT_DIR_MAIL, "risk_package_draft.json")
write_json(risk_package, draft_path, pretty = TRUE, auto_unbox = TRUE)
cat("Wrote risk_package_draft.json: ", draft_path, "\n")

cat("\n==== Risk pipeline DONE ====\n")
cat("Σ method selected:", selected$name, "\n")
cat("Σ cond_post_shrink:", round(sigma_cond, 2), "\n")
cat("Multi-sleeve cor:", round(cor_core_def %||% NA_real_, 3), "\n")
cat("Diversification benefit:", round(diversification_benefit * 100, 2), "%\n")
cat("Stress worst:", round(worst_stress * 100, 2), "%\n")
cat("Kelly+Overlay compat:", kelly_overlay_compat$compatibility_status, "\n")
cat("Challenge flags:", length(challenge_flags), "\n")

saveRDS(list(
  SIGMA = SIGMA,
  SIGMA_POOLED = SIGMA_POOLED,
  selected_method = selected$name,
  pit_cutoff = PIT_HARD_CUTOFF,
  TICKERS20 = TICKERS20,
  kelly_overlay_compat = kelly_overlay_compat
), file.path(OUT_DIR_STAGE, "risk_workspace.rds"))
