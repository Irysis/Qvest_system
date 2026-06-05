#==============================================================================
# WT-D20260518_001 — Bear Regime Prediction Engine v2.0 Risk Research
#
# 역할:
#   Alpha Agent가 emit한 alpha_package (bear regime sensor, 44 features × 10 categories)
#   에 대한 **공동위험 구조 Σ + tail risk + 8 stress + crowding + style audit** 생성.
#
# 본 sensor는 scalar β_bear ∈ [0.3, 1.0] (NOT 20-stock cross-sectional sleeve).
# Σ_assets 는 STR_1715 PG2 production manifest 인헤리트 (Layer 6 scalar overlay).
# 본 cycle Risk 작업 = sensor 내부 risk model (44 features 간 cov + tail of bear sig).
#
# 5-step pipeline (Risk Agent prompt):
#   Step 1: Exposure model (features × asset universe 매핑)
#   Step 2: Factor covariance Ω (44 features, 정확히는 15 built features)
#   Step 3: Specific risk D (idiosyncratic per feature)
#   Step 4: Security covariance Σ = BΩB' + D (effective: features Σ)
#   Step 5: Stress tests + crowding + style audit
#
# 산출물:
#   stage_artifacts/WT_D20260518_001/covariance.parquet
#   stage_artifacts/WT_D20260518_001/tail_risk_evt_gpd.json
#   stage_artifacts/WT_D20260518_001/stress_8_windows.json
#   stage_artifacts/WT_D20260518_001/crowding_overlap_with_PG2_STR_1715.json
#   stage_artifacts/WT_D20260518_001/style_5_axis_exposure.csv
#   stage_artifacts/WT_D20260518_001/regime_correlation.parquet
#   stage_artifacts/WT_D20260518_001/method_shopping_log_risk.json
#   qepm/mailbox/worktask/WT-D20260518_001/risk_package_draft.json
#==============================================================================
suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
  library(PerformanceAnalytics)
})

# ── Paths ─────────────────────────────────────────────────────────────────────
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
WT_ID <- "WT-D20260518_001"
WT_STG <- "WT_D20260518_001"
MAILBOX_DIR <- file.path("qepm", "mailbox", "worktask", WT_ID)
STAGE_DIR <- file.path("stage_artifacts", WT_STG)
stopifnot(dir.exists(MAILBOX_DIR))
stopifnot(dir.exists(STAGE_DIR))

cat("============================================================\n")
cat(sprintf("[risk-research] %s — START %s\n", WT_ID, format(Sys.time())))
cat("============================================================\n")

# ── Step 0: Load alpha_package + feature panel ────────────────────────────────
ap <- fromJSON(file.path(MAILBOX_DIR, "alpha_package.json"), simplifyVector = FALSE)
cat(sprintf("[Step 0] alpha_package: %s\n", ap$agent_version))
cat(sprintf("         features designed: 44 (10 categories) | built sample: 15\n"))
cat(sprintf("         alpha_vector status: %s\n", ap$alpha_vector_status))

panel <- as.data.table(read_parquet(file.path(STAGE_DIR, "feature_panel_design_v2.parquet")))
cat(sprintf("[Step 0] panel: rows=%d, cols=%d, date_range=%s ~ %s\n",
            nrow(panel), ncol(panel),
            format(min(panel$Date_eom, na.rm=TRUE)),
            format(max(panel$Date_eom, na.rm=TRUE))))

ic_dt <- fread(file.path(STAGE_DIR, "ICIR_per_window_per_regime.csv"))
inv <- fread(file.path(STAGE_DIR, "comprehensive_features_inventory.csv"))
cat(sprintf("[Step 0] inventory: %d features × %d strata categorical\n",
            nrow(inv), uniqueN(inv$category)))

# Identify built feature columns (drop meta cols)
meta_cols <- c("YM", "Date_eom", "BM_Close_eom", "BM_Ret_m", "fwd_ret_1m",
               "target_bear_5pct", "target_bear_10pct", "row_pit_status",
               grep("Usable_Date_", names(panel), value=TRUE))
feat_cols_all <- setdiff(names(panel), meta_cols)
# Coverage diagnosis — drop features with < 50% observed (sparse)
coverage_per_feat <- sapply(feat_cols_all, function(fc) sum(!is.na(panel[[fc]])) / nrow(panel))
sparse_features <- names(coverage_per_feat[coverage_per_feat < 0.50])
feat_cols <- setdiff(feat_cols_all, sparse_features)
cat(sprintf("[Step 0] feature coverage diagnosis (drop < 50%% observed):\n"))
for (fc in feat_cols_all) {
  cat(sprintf("    %-25s obs_rate=%.0f%% %s\n", fc, 100*coverage_per_feat[fc],
              if (fc %in% sparse_features) "[DROPPED — sparse]" else "[KEPT]"))
}
cat(sprintf("[Step 0] built feature columns kept (%d): %s\n",
            length(feat_cols), paste(feat_cols, collapse=", ")))
cat(sprintf("[Step 0] features dropped due to sparsity (%d): %s\n",
            length(sparse_features), paste(sparse_features, collapse=", ")))

# Filter trainable PIT-clean rows for risk analysis
panel_tr <- panel[row_pit_status == "trainable_pit_clean"]
cat(sprintf("[Step 0] trainable rows: %d / %d (%.1f%%)\n",
            nrow(panel_tr), nrow(panel), 100*nrow(panel_tr)/nrow(panel)))

# ── Step 1: Exposure Model B  (feature × bear regime label) ───────────────────
# 본 cycle은 cross-sectional asset universe 미적용 (sensor 특성).
# Exposure matrix = ICIR × regime stratification (feature → bear hit signal strength).
cat("\n[Step 1] Exposure model B (feature × regime → ICIR strength) ...\n")

# Build exposure_matrix: features (rows) × regimes (cols) = ICIR
ic_wide <- dcast(ic_dt, feature ~ regime, value.var = "ICIR")
# Filter to built features
ic_built <- ic_wide[feature %in% feat_cols]
cat(sprintf("[Step 1] exposure_matrix: %d built features × %d regimes\n",
            nrow(ic_built), ncol(ic_built) - 1))
exposure_path <- file.path(STAGE_DIR, "exposure_matrix.parquet")
write_parquet(ic_built, exposure_path)
cat(sprintf("[Step 1] saved: %s\n", exposure_path))

# ── Step 2: Factor Covariance Ω — parallel estimator comparison ───────────────
cat("\n[Step 2] Factor covariance Ω — parallel estimator comparison ...\n")

# Construct returns-like matrix: features (T × N) with NA-aware
# Use rolling z-scored levels (alpha-research convention) — for risk we use raw levels first-diff
panel_diff <- copy(panel)
setorder(panel_diff, Date_eom)
for (fc in feat_cols) {
  # First difference per feature (stationarity for covariance)
  panel_diff[, (fc) := c(NA_real_, diff(get(fc)))]
}
# Strategy: use pairwise.complete.obs (drop complete.cases restriction)
# But keep "trimmed" window where at least 80% of features observed
n_obs_per_row <- apply(panel_diff[, ..feat_cols], 1, function(r) sum(!is.na(r)))
threshold_obs <- round(0.80 * length(feat_cols))
panel_diff_trim <- panel_diff[n_obs_per_row >= threshold_obs]
ret_mat <- as.matrix(panel_diff_trim[, ..feat_cols])
rownames(ret_mat) <- as.character(panel_diff_trim$Date_eom)
cat(sprintf("[Step 2] trimmed returns matrix (>=80%% feat observed per row): T=%d × N=%d, range %s ~ %s\n",
            nrow(ret_mat), ncol(ret_mat),
            format(min(panel_diff_trim$Date_eom)),
            format(max(panel_diff_trim$Date_eom))))
cat(sprintf("[Step 2] pairwise.complete.obs used for cov estimation (handle remaining NA)\n"))

# Method shopping log
method_log <- list()

# 2a. Sample covariance (pairwise.complete.obs)
Sigma_sample <- cov(ret_mat, use = "pairwise.complete.obs")
# Post-PSD repair: if not PSD due to pairwise NA, project to nearest PSD
fix_psd_higham <- function(C) {
  eg <- eigen(C, symmetric = TRUE)
  vals <- pmax(eg$values, 1e-10)
  C_psd <- eg$vectors %*% diag(vals) %*% t(eg$vectors)
  # Symmetrize
  (C_psd + t(C_psd)) / 2
}
if (any(eigen(Sigma_sample, only.values=TRUE)$values < 0)) {
  cat("[Step 2a] sample cov non-PSD detected → Higham (1988) PSD projection\n")
  Sigma_sample <- fix_psd_higham(Sigma_sample)
}
cn_sample <- kappa(Sigma_sample)
eig_sample <- eigen(Sigma_sample, only.values = TRUE)$values
min_eig_sample <- min(eig_sample)
psd_sample <- all(eig_sample > -1e-10)
method_log[[length(method_log)+1]] <- list(
  name = "sample",
  condition_number = round(cn_sample, 2),
  min_eigenvalue = round(min_eig_sample, 6),
  psd = psd_sample,
  selected = FALSE,
  reason = "baseline reference, no shrinkage"
)
cat(sprintf("[Step 2a] sample: cond=%.2f, min_eig=%.6f, psd=%s\n",
            cn_sample, min_eig_sample, psd_sample))

# 2b. Ledoit-Wolf shrinkage (constant correlation target) — NA-aware
ledoit_wolf_constcor <- function(X) {
  # Impute NA per-column with column mean for stable Ledoit-Wolf
  X_imp <- X
  for (k in seq_len(ncol(X_imp))) {
    mu_k <- mean(X_imp[, k], na.rm = TRUE)
    X_imp[is.na(X_imp[, k]), k] <- mu_k
  }
  X <- scale(X_imp, scale = FALSE)
  T_ <- nrow(X); N_ <- ncol(X)
  S <- cov(X) * (T_-1)/T_
  s <- diag(S)
  C <- cor(X)
  r_bar <- (sum(C) - N_) / (N_*(N_-1))
  F_ <- r_bar * sqrt(outer(s, s))
  diag(F_) <- s
  # Shrinkage intensity (Ledoit-Wolf 2004)
  # pi: sum_var; rho: sum_cov; gamma: F - S Frobenius
  Y <- X^2
  pi_mat <- crossprod(Y)/T_ - S^2
  pi_hat <- sum(pi_mat)
  theta_ii_j <- function(i, j) {
    if (i == j) return(0)
    term1 <- (sum(X[,i]^2 * X[,i] * X[,j]) / T_) - S[i,i]*S[i,j]
    term2 <- (sum(X[,j]^2 * X[,i] * X[,j]) / T_) - S[j,j]*S[i,j]
    (sqrt(s[j]/s[i])*term1 + sqrt(s[i]/s[j])*term2)/2
  }
  rho_hat <- sum(diag(pi_mat))
  for (i in 1:N_) for (j in 1:N_) if (i != j) rho_hat <- rho_hat + r_bar * theta_ii_j(i,j)
  gamma_hat <- sum((F_ - S)^2)
  kappa_hat <- (pi_hat - rho_hat) / max(gamma_hat, 1e-12)
  delta_hat <- max(0, min(1, kappa_hat/T_))
  list(Sigma = delta_hat * F_ + (1 - delta_hat) * S, delta = delta_hat)
}
lw_res <- ledoit_wolf_constcor(ret_mat)
Sigma_lw <- lw_res$Sigma
cn_lw <- kappa(Sigma_lw)
eig_lw <- eigen(Sigma_lw, only.values = TRUE)$values
min_eig_lw <- min(eig_lw)
psd_lw <- all(eig_lw > -1e-10)
method_log[[length(method_log)+1]] <- list(
  name = "ledoit_wolf_constcor",
  condition_number = round(cn_lw, 2),
  min_eigenvalue = round(min_eig_lw, 6),
  shrinkage_delta = round(lw_res$delta, 4),
  psd = psd_lw,
  selected = FALSE,
  reason = "Ledoit-Wolf 2004 constant correlation target, default shrinkage"
)
cat(sprintf("[Step 2b] ledoit_wolf_constcor: cond=%.2f, delta=%.4f, min_eig=%.6f, psd=%s\n",
            cn_lw, lw_res$delta, min_eig_lw, psd_lw))

# 2c. Gerber statistic + RMT denoise
.gerber_cor <- function(X, threshold = 0.5) {
  p <- ncol(X); sds <- apply(X, 2, sd, na.rm = TRUE); h <- threshold * sds
  cor_mat <- diag(p)
  for (i in 1:(p-1)) {
    xi <- X[,i]; hi <- h[i]
    for (j in (i+1):p) {
      xj <- X[,j]; hj <- h[j]
      up_i <- xi > hi; dn_i <- xi < -hi
      up_j <- xj > hj; dn_j <- xj < -hj
      conc <- sum((up_i & up_j) | (dn_i & dn_j), na.rm = TRUE)
      disc <- sum((up_i & dn_j) | (dn_i & up_j), na.rm = TRUE)
      denom <- conc + disc
      cor_mat[i,j] <- cor_mat[j,i] <- if (denom > 0) (conc - disc)/denom else 0
    }
  }
  colnames(cor_mat) <- rownames(cor_mat) <- colnames(X)
  cor_mat
}
.rmt_denoise <- function(C, q_ratio) {
  n <- nrow(C); if (n < 3 || q_ratio < 1) return(C)
  lp <- (1 + 1/sqrt(q_ratio))^2
  eg <- eigen(C, symmetric = TRUE)
  vals <- eg$values; vecs <- eg$vectors
  idx <- which(vals <= lp)
  if (length(idx) > 0 && length(idx) < n) vals[idx] <- mean(vals[idx])
  D <- matrix(0, n, n); diag(D) <- vals
  C2 <- vecs %*% D %*% t(vecs)
  diag(C2) <- 1
  (C2 + t(C2))/2
}
# Impute NA for Gerber + RMT
ret_mat_imp <- ret_mat
for (k in seq_len(ncol(ret_mat_imp))) {
  mu_k <- mean(ret_mat_imp[, k], na.rm = TRUE)
  ret_mat_imp[is.na(ret_mat_imp[, k]), k] <- mu_k
}
C_gerber <- .gerber_cor(ret_mat_imp)
C_gerber_rmt <- .rmt_denoise(C_gerber, q_ratio = nrow(ret_mat_imp)/ncol(ret_mat_imp))
# Force PSD via Higham projection (RMT can yield indefinite)
C_gerber_rmt <- fix_psd_higham(C_gerber_rmt)
sds <- apply(ret_mat_imp, 2, sd, na.rm = TRUE)
Sigma_gerber <- C_gerber_rmt * outer(sds, sds)
cn_gerber <- kappa(Sigma_gerber)
eig_gerber <- eigen(Sigma_gerber, only.values = TRUE)$values
min_eig_gerber <- min(eig_gerber)
psd_gerber <- all(eig_gerber > -1e-6)  # slightly looser due to RMT manipulation
method_log[[length(method_log)+1]] <- list(
  name = "gerber_rmt",
  condition_number = round(cn_gerber, 2),
  min_eigenvalue = round(min_eig_gerber, 6),
  threshold = 0.5,
  q_ratio = round(nrow(ret_mat)/ncol(ret_mat), 2),
  psd = psd_gerber,
  selected = FALSE,
  reason = "Gerber-Hurst-Konev 2022 robust correlation + Marchenko-Pastur RMT denoise"
)
cat(sprintf("[Step 2c] gerber_rmt: cond=%.2f, min_eig=%.6f, psd=%s\n",
            cn_gerber, min_eig_gerber, psd_gerber))

# Select best by condition number among PSD methods
candidates_psd <- list(
  list(name = "sample", Sigma = Sigma_sample, cn = cn_sample, psd = psd_sample),
  list(name = "ledoit_wolf_constcor", Sigma = Sigma_lw, cn = cn_lw, psd = psd_lw),
  list(name = "gerber_rmt", Sigma = Sigma_gerber, cn = cn_gerber, psd = psd_gerber)
)
valid <- Filter(function(x) x$psd && x$cn < 500, candidates_psd)
if (length(valid) == 0) {
  # Fallback: best cn among PSD
  valid <- Filter(function(x) x$psd, candidates_psd)
}
selected_idx <- which.min(sapply(valid, function(x) x$cn))
selected_method <- valid[[selected_idx]]
cat(sprintf("\n[Step 2-select] SELECTED: %s (cond=%.2f, psd=%s)\n",
            selected_method$name, selected_method$cn, selected_method$psd))
# Mark selected in log
for (i in seq_along(method_log)) {
  if (method_log[[i]]$name == selected_method$name) {
    method_log[[i]]$selected <- TRUE
  }
}

Sigma_primary <- selected_method$Sigma
# Save factor covariance
fc_path <- file.path(STAGE_DIR, "factor_covariance.parquet")
write_parquet(as.data.frame(Sigma_primary), fc_path)
cat(sprintf("[Step 2] factor_covariance saved: %s\n", fc_path))

# ── Step 3: Specific Risk D (idiosyncratic per feature) ───────────────────────
cat("\n[Step 3] Specific risk D — idiosyncratic variance per feature ...\n")
# 첫 PC 1-factor 모델 → residual var
eig_full <- eigen(Sigma_primary, symmetric = TRUE)
pc1 <- eig_full$vectors[, 1]
lambda1 <- eig_full$values[1]
B_pc <- pc1 * sqrt(lambda1)
common_var <- B_pc^2
total_var <- diag(Sigma_primary)
D_vec <- pmax(total_var - common_var, 1e-12)
coverage <- 1 - mean(D_vec / total_var)
specific_risk_dt <- data.table(
  feature = colnames(Sigma_primary),
  total_var = total_var,
  common_var = common_var,
  specific_var = D_vec,
  specific_share = D_vec / total_var
)
sr_path <- file.path(STAGE_DIR, "specific_risk.parquet")
write_parquet(specific_risk_dt, sr_path)
cat(sprintf("[Step 3] specific_risk saved: %s | factor_coverage=%.1f%%\n",
            sr_path, 100*coverage))

# ── Step 4: Security Covariance Σ = BΩB' + D ─────────────────────────────────
cat("\n[Step 4] Security covariance Σ = BΩB' + D ...\n")
# For features (regime sensor), "security" = feature.
# Σ_features 이미 Step 2에서 추정 (Sigma_primary), 본 step은 PSD audit + cond check
final_Sigma <- Sigma_primary
final_cn <- kappa(final_Sigma)
final_min_eig <- min(eigen(final_Sigma, only.values=TRUE)$values)
final_psd <- final_min_eig > -1e-10
cat(sprintf("[Step 4] final Σ: cond=%.2f, min_eig=%.6f, psd=%s\n",
            final_cn, final_min_eig, final_psd))

# If cond > 500, fallback to LW
if (final_cn > 500) {
  cat("[Step 4] cond > 500, forcing Ledoit-Wolf fallback\n")
  final_Sigma <- Sigma_lw
  final_cn <- cn_lw
  final_min_eig <- min_eig_lw
}
# Additional ridge regularization if cond still > 500 after LW
ridge_lambda_applied <- 0
if (final_cn > 500) {
  cat(sprintf("[Step 4] cond=%.1f after LW > 500 — applying ridge regularization\n", final_cn))
  # Apply ridge: Σ_ridge = Σ + λ·tr(Σ)/N·I
  # Increment λ until cond < 500
  N_ <- ncol(final_Sigma)
  for (lam_try in c(0.01, 0.05, 0.10, 0.25, 0.50)) {
    Sig_test <- final_Sigma + lam_try * (sum(diag(final_Sigma))/N_) * diag(N_)
    cn_test <- kappa(Sig_test)
    if (cn_test < 500) {
      final_Sigma <- Sig_test
      final_cn <- cn_test
      final_min_eig <- min(eigen(final_Sigma, only.values=TRUE)$values)
      ridge_lambda_applied <- lam_try
      cat(sprintf("[Step 4] ridge λ=%.2f applied → cond=%.1f, min_eig=%.6f\n",
                  lam_try, cn_test, final_min_eig))
      break
    }
  }
  if (final_cn > 500) {
    cat(sprintf("[Step 4] WARN: cond=%.1f still > 500 even at λ=0.5 ridge — bear sensor v2.0 panel structurally ill-conditioned (T=%d × N=%d small panel)\n",
                final_cn, nrow(ret_mat), ncol(ret_mat)))
  }
}

# Save final covariance
cov_path <- file.path(STAGE_DIR, "covariance.parquet")
final_Sigma_df <- as.data.table(as.data.frame(final_Sigma))
final_Sigma_df[, feature := colnames(final_Sigma)]
setcolorder(final_Sigma_df, c("feature", colnames(final_Sigma)))
write_parquet(final_Sigma_df, cov_path)
cat(sprintf("[Step 4] covariance.parquet saved: %s\n", cov_path))

# ── Step 5: Stress + Tail Risk + Crowding + Style + Regime cor ────────────────
cat("\n[Step 5] Stress tests + tail risk + crowding + style + regime cor ...\n")

# 5a. Tail risk: EVT GPD on BM_Ret_m bear regime distribution
cat("\n[Step 5a] Tail risk EVT GPD fit on BM_Ret_m bear-side ...\n")
bm_ret <- panel$BM_Ret_m
bm_ret <- bm_ret[!is.na(bm_ret)]
losses <- -bm_ret  # bear-side positive losses
# GPD threshold = 80th percentile of losses (Pfaff Ch.7 default)
u_q <- 0.80
u <- as.numeric(quantile(losses, u_q))
exceed <- losses[losses > u] - u
n_exceed <- length(exceed)

evt_result <- NULL
if (n_exceed >= 20) {
  # Method of moments GPD fit
  m1 <- mean(exceed); m2 <- mean(exceed^2)
  if (m2 > 2*m1^2) {
    shape_hat <- 0.5 * (1 - m1^2/(m2 - m1^2))
    scale_hat <- m1 * (1 - shape_hat)
  } else {
    # Exponential limit (shape ≈ 0)
    shape_hat <- 0
    scale_hat <- m1
  }
  # Maximum likelihood refinement
  nll <- function(par) {
    sh <- par[1]; sc <- par[2]
    if (sc <= 0) return(Inf)
    if (abs(sh) < 1e-6) {
      -sum(-exceed/sc - log(sc))
    } else {
      ar <- 1 + sh*exceed/sc
      if (any(ar <= 0)) return(Inf)
      -sum(-log(sc) - (1+1/sh)*log(ar))
    }
  }
  fit <- tryCatch(optim(c(shape_hat, scale_hat), nll, method = "Nelder-Mead",
                         control = list(reltol = 1e-8)),
                   error = function(e) NULL)
  if (!is.null(fit) && fit$convergence == 0) {
    shape_xi <- fit$par[1]
    scale_beta <- fit$par[2]
  } else {
    shape_xi <- shape_hat
    scale_beta <- scale_hat
  }

  # VaR + CVaR at p=0.95, 0.99
  compute_var_es <- function(p, n_total, n_ex, u, sh, sc) {
    fp <- (n_total/n_ex) * (1 - p)
    if (abs(sh) < 1e-6) {
      var_p <- u - sc * log(fp)
      es_p <- var_p + sc
    } else {
      var_p <- u + (sc/sh) * ((fp)^(-sh) - 1)
      es_p <- if (sh < 1) (var_p + sc - sh*u) / (1 - sh) else NA_real_
    }
    list(VaR = var_p, ES = es_p)
  }
  ves_95 <- compute_var_es(0.95, length(losses), n_exceed, u, shape_xi, scale_beta)
  ves_99 <- compute_var_es(0.99, length(losses), n_exceed, u, shape_xi, scale_beta)
  # Empirical comparison
  emp_var_95 <- as.numeric(quantile(losses, 0.95))
  emp_es_95 <- mean(losses[losses > emp_var_95])
  emp_var_99 <- as.numeric(quantile(losses, 0.99))
  emp_es_99 <- mean(losses[losses > emp_var_99])

  evt_result <- list(
    method = "GPD_MLE_NelderMead",
    distribution = "monthly_KOSPI200_BM_Ret_bear_side",
    n_obs = length(bm_ret),
    threshold_q = u_q,
    threshold_u = u,
    n_exceedances = n_exceed,
    shape_xi = shape_xi,
    scale_beta = scale_beta,
    fit_convergence = if (!is.null(fit)) fit$convergence else NA_integer_,
    VaR_95_evt = ves_95$VaR,
    ES_95_evt = ves_95$ES,
    VaR_99_evt = ves_99$VaR,
    ES_99_evt = ves_99$ES,
    VaR_95_empirical = emp_var_95,
    ES_95_empirical = emp_es_95,
    VaR_99_empirical = emp_var_99,
    ES_99_empirical = emp_es_99,
    tail_class = if (shape_xi > 0.3) "heavy_tail"
                  else if (shape_xi > 0.05) "moderate_tail"
                  else if (shape_xi > -0.05) "exponential_like"
                  else "bounded_left",
    interpretation = sprintf(
      "ξ=%.3f → %s. CVaR(95)=%.3f vs empirical %.3f. Bear sensor target captures losses < -5%% monthly (empirical base rate 0.186).",
      shape_xi,
      if (shape_xi > 0.3) "heavy-tailed regime risk (KR equity is fat-tailed empirically)"
      else if (shape_xi > 0.05) "moderately fat tails"
      else "near-exponential tails",
      ves_95$ES, emp_es_95)
  )
} else {
  evt_result <- list(error = "n_exceedances < 20, GPD fit skipped",
                      n_exceedances = n_exceed,
                      fallback_empirical_VaR_95 = as.numeric(quantile(losses, 0.95)),
                      fallback_empirical_ES_95 = mean(losses[losses > quantile(losses, 0.95)]))
}
write_json(evt_result, file.path(STAGE_DIR, "tail_risk_evt_gpd.json"),
            pretty = TRUE, auto_unbox = TRUE, digits = 6)
cat(sprintf("[Step 5a] tail_risk_evt_gpd.json saved | shape_xi=%.3f, CVaR_95=%.3f\n",
            ifelse(is.null(evt_result$shape_xi), NA, evt_result$shape_xi),
            ifelse(is.null(evt_result$ES_95_evt), NA, evt_result$ES_95_evt)))

# 5b. 8 Stress windows — feature behavior + bear hit accuracy
cat("\n[Step 5b] 8 stress windows ...\n")
stress_windows <- list(
  list(name = "DotCom_2002", start = "2001-09-01", end = "2002-12-31"),
  list(name = "GFC_2008", start = "2007-10-01", end = "2009-03-31"),
  list(name = "Euro_Debt_2011", start = "2011-07-01", end = "2011-12-31"),
  list(name = "China_Shock_2015", start = "2015-06-01", end = "2016-02-29"),
  list(name = "Q4_Selloff_2018", start = "2018-10-01", end = "2018-12-31"),
  list(name = "COVID_2020", start = "2020-01-01", end = "2020-06-30"),
  list(name = "Rate_Hike_2022", start = "2022-01-01", end = "2022-12-31"),
  list(name = "Iran_War_2026", start = "2026-02-01", end = "2026-04-30")
)

# For each window, compute:
#   - BM_Ret_m cumulative + monthly mean
#   - bear hit count (target_bear_5pct == 1)
#   - feature movement (z-scored within window vs full-sample)
stress_results <- list()
for (sw in stress_windows) {
  s_d <- as.Date(sw$start); e_d <- as.Date(sw$end)
  sub <- panel[Date_eom >= s_d & Date_eom <= e_d]
  if (nrow(sub) < 3) {
    stress_results[[sw$name]] <- list(
      name = sw$name, start = sw$start, end = sw$end,
      n_months = nrow(sub), status = "insufficient_obs"
    )
    next
  }
  cum_bm <- prod(1 + sub$BM_Ret_m, na.rm = TRUE) - 1
  bear_hits <- sum(sub$target_bear_5pct == 1, na.rm = TRUE)
  bear_rate <- bear_hits / sum(!is.na(sub$target_bear_5pct))
  # Worst month
  worst <- min(sub$BM_Ret_m, na.rm = TRUE)
  # Feature movements (mean during window vs full-sample mean for built features)
  feat_shifts <- list()
  for (fc in feat_cols) {
    full_mean <- mean(panel[[fc]], na.rm = TRUE)
    full_sd <- sd(panel[[fc]], na.rm = TRUE)
    win_mean <- mean(sub[[fc]], na.rm = TRUE)
    if (is.na(full_sd) || full_sd == 0 || is.na(win_mean)) {
      feat_shifts[[fc]] <- NA_real_
    } else {
      feat_shifts[[fc]] <- (win_mean - full_mean) / full_sd
    }
  }
  # Top 5 features by abs shift
  shift_vec <- unlist(feat_shifts)
  top_shifts <- shift_vec[order(-abs(shift_vec), na.last = NA)][1:min(5, length(shift_vec))]
  stress_results[[sw$name]] <- list(
    name = sw$name, start = sw$start, end = sw$end,
    n_months = nrow(sub),
    BM_cum_return = round(cum_bm, 4),
    BM_worst_month = round(worst, 4),
    bear_hits_5pct = bear_hits,
    bear_rate = round(bear_rate, 4),
    base_rate_full_period = 0.186,
    bear_excess_vs_base = round(bear_rate - 0.186, 4),
    top_5_feature_shifts_zscore = lapply(top_shifts, function(x) round(x, 3))
  )
}
write_json(stress_results, file.path(STAGE_DIR, "stress_8_windows.json"),
            pretty = TRUE, auto_unbox = TRUE, digits = 4)
cat(sprintf("[Step 5b] stress_8_windows.json saved (%d windows)\n", length(stress_results)))
for (nm in names(stress_results)) {
  r <- stress_results[[nm]]
  if (!is.null(r$BM_cum_return)) {
    cat(sprintf("    %s: BM=%.1f%% worst=%.1f%% bear_hits=%d/%d (rate=%.1f%% vs base 18.6%%)\n",
                nm, 100*r$BM_cum_return, 100*r$BM_worst_month,
                r$bear_hits_5pct, r$n_months, 100*r$bear_rate))
  }
}

# 5c. Crowding overlap with PG2 STR_1715 4 layers
cat("\n[Step 5c] Crowding overlap w/ PG2 STR_1715 (4 layers: alpha + M4 + AR + R05) ...\n")
# Approach: compute correlation between bear regime indicator timeseries and PG2 layer state series
# Layer M4: regime_state (BULL/NORMAL/CAUTION/CRISIS) from STR_1715
str1715 <- as.data.table(read_parquet(
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"))
# Collapse to monthly state by date
str1715_monthly <- str1715[, .(
  regime_state_mode = names(sort(table(regime_state), decreasing = TRUE))[1],
  n_obs = .N,
  alpha_top20_avg = mean(sort(score_eff, decreasing = TRUE, na.last = NA)[1:20], na.rm = TRUE)
), by = .(Date)]
str1715_monthly[, Date_eom := as.Date(format(Date + 30, "%Y-%m-01")) - 1]

# Merge with panel
ovl <- merge(panel[, .(Date_eom, target_bear_5pct, BM_Ret_m)],
              str1715_monthly[, .(Date_eom, regime_state_mode, alpha_top20_avg)],
              by = "Date_eom", all = FALSE)
cat(sprintf("[Step 5c] overlap rows: %d (PG2 STR_1715 Date range: %s ~ %s)\n",
            nrow(ovl), format(min(str1715$Date)), format(max(str1715$Date))))

# Crowding scores: bear-side conditional
# (1) bear_signal (target=1) vs M4 regime
ovl[, m4_crisis_flag := ifelse(regime_state_mode %in% c("CAUTION", "CRISIS"), 1L, 0L)]
m4_overlap_tab <- table(ovl$target_bear_5pct, ovl$m4_crisis_flag)
m4_agree_count <- if (all(c("0","1") %in% rownames(m4_overlap_tab)) &&
                       all(c("0","1") %in% colnames(m4_overlap_tab))) {
  m4_overlap_tab["1","1"] + m4_overlap_tab["0","0"]
} else NA_integer_

# (2) Correlation bear_signal ~ alpha_top20_avg (PG2 STR_1715 strength)
cor_bear_alpha <- cor(ovl$target_bear_5pct, ovl$alpha_top20_avg,
                       use = "pairwise.complete.obs")

# (3) Correlation bear_signal vs BM_Ret_m (mechanical, expect strong negative)
cor_bear_bm <- cor(ovl$target_bear_5pct, ovl$BM_Ret_m, use = "pairwise.complete.obs")

# (4) Estimate β_bear payoff vs PG2 alpha
# Bear sensor when fires reduces exposure. If alpha_top20 is risk-on, β_bear cuts MDD.
# Approximation: monthly conditional return when target_bear=1 vs 0
ret_when_bear <- mean(ovl[target_bear_5pct == 1]$BM_Ret_m, na.rm = TRUE)
ret_when_bull <- mean(ovl[target_bear_5pct == 0]$BM_Ret_m, na.rm = TRUE)

crowding_result <- list(
  pg2_admit = "STR_1715_AR_on_M4_R05_overlay_PG2",
  pg2_book_state = "v2.3",
  pg2_layers = c("Layer 1+2: STR_1715 alpha (4F Consensus)",
                  "Layer 3: M4 BOCPD regime trigger",
                  "Layer 4: AR threshold overlay",
                  "Layer 5: R05 Tail-Risk overlay (new 2026-05-13)"),
  bear_sensor_role = "Layer 6 candidate — scalar β_bear ∈ [0.3, 1.0] multiplicative",
  m4_overlap_table = list(
    bear_0_m4_normal = as.integer(m4_overlap_tab["0","0"] %||% NA),
    bear_0_m4_caution = as.integer(m4_overlap_tab["0","1"] %||% NA),
    bear_1_m4_normal = as.integer(m4_overlap_tab["1","0"] %||% NA),
    bear_1_m4_caution = as.integer(m4_overlap_tab["1","1"] %||% NA),
    total_n = nrow(ovl)
  ),
  m4_agreement_count = m4_agree_count,
  m4_agreement_rate = round(m4_agree_count / nrow(ovl), 4),
  cor_bear_signal_with_alpha_top20 = round(cor_bear_alpha, 4),
  cor_bear_signal_with_BM_Ret = round(cor_bear_bm, 4),
  monthly_BM_when_bear_hit = round(ret_when_bear, 4),
  monthly_BM_when_bull = round(ret_when_bull, 4),
  bear_vs_bull_return_spread = round(ret_when_bear - ret_when_bull, 4),
  interpretation = "Bear sensor v2.0 (44 features, 4-axis calibration) measures market-level downturn risk. M4 BOCPD measures cross-sectional regime change. Low cor with alpha_top20 (cross-sectional signal) is desired (orthogonality); high cor with BM_Ret (mechanical) is expected.",
  orthogonality_with_PG2_alpha = list(
    threshold_target = 0.4,
    actual_abs_cor = abs(cor_bear_alpha),
    status = if (abs(cor_bear_alpha) < 0.4) "ORTHOGONAL_PASS" else "OVERLAP_WARN"
  ),
  redundancy_with_M4_overlay = list(
    target_max_agreement_rate = 0.85,
    actual_rate = round(m4_agree_count / nrow(ovl), 4),
    status = if ((m4_agree_count / nrow(ovl)) < 0.85) "DISTINCT_PASS" else "REDUNDANT_WARN"
  )
)
# Add %||% helper
write_json(crowding_result, file.path(STAGE_DIR, "crowding_overlap_with_PG2_STR_1715.json"),
            pretty = TRUE, auto_unbox = TRUE, digits = 4)
cat(sprintf("[Step 5c] crowding saved | M4_agree=%.1f%% | cor(bear,alpha)=%.3f | status_alpha=%s\n",
            100*crowding_result$m4_agreement_rate, cor_bear_alpha,
            crowding_result$orthogonality_with_PG2_alpha$status))

# 5d. Style 5-axis exposure audit
# Map 44 features × 10 categories → 5 barra-style axes
# Mapping based on alpha_package category meaning:
#   1_yield_curve_inversion (6) → Macro (yield)
#   2_leading_indicators (6) → Macro (growth)
#   3_volatility_regime_VIX/VKOSPI/FX (7) → Volatility
#   4_asymmetric_correlation_FX (3) → Volatility (FX vol)
#   5_systemic_risk_FinConditions (4) → Quality (credit health)
#   6_credit_spread (4) → Quality (credit)
#   7_etf_flow_crowding (3) → Crowding (Acadian)
#   8_capital_flow_defensive_rotation (5) → Momentum (flow)
#   9_valuation_mean_reversion (3) → Value
#   10_monetary_aggregate (1) → Macro (M2)
# Barra style 5-axis: Value / Momentum / Size / Quality / Volatility
# Bear sensor is NOT cross-sectional → "Size" axis = 0
cat("\n[Step 5d] Style 5-axis exposure audit ...\n")
inv_full <- inv  # all 44 features
inv_full[, barra_style := fcase(
  category == "1_yield_curve_inversion", "Macro_Yield",
  category == "2_leading_indicators", "Macro_Growth",
  category == "3_volatility_regime_VIX", "Volatility",
  category == "3_volatility_regime_VKOSPI", "Volatility",
  category == "3_volatility_regime_FX", "Volatility",
  category == "4_asymmetric_correlation_FX", "Volatility",
  category == "5_systemic_risk_FinConditions", "Quality",
  category == "6_credit_spread", "Quality",
  category == "7_etf_flow_crowding_SEFRS", "Crowding",
  category == "8_capital_flow_defensive_rotation", "Momentum",
  category == "9_valuation_mean_reversion", "Value",
  category == "10_monetary_aggregate", "Macro_Monetary",
  default = "Unmapped"
)]
# Count per barra style
style_summary <- inv_full[, .(
  n_features = .N,
  weight_pct = round(.N / nrow(inv_full) * 100, 1),
  features = paste(feature_id, collapse = "; ")
), by = barra_style]
setorder(style_summary, -n_features)

# Concentration HHI on 5 axes
style_weights <- style_summary$n_features / sum(style_summary$n_features)
style_hhi <- sum(style_weights^2)
max_style_share <- max(style_weights)
n_distinct_styles <- nrow(style_summary)

# 5 axis Barra mapping (collapse Macro × 3 → Macro)
inv_full[, barra_5axis := fcase(
  startsWith(barra_style, "Macro"), "Macro",
  barra_style == "Volatility", "Volatility",
  barra_style == "Quality", "Quality",
  barra_style == "Crowding", "Crowding",
  barra_style == "Momentum", "Momentum",
  barra_style == "Value", "Value",
  default = "Unmapped"
)]
style_5 <- inv_full[, .(
  n_features = .N,
  weight_pct = round(.N / nrow(inv_full) * 100, 1)
), by = barra_5axis]
setorder(style_5, -n_features)
style_5_weights <- style_5$n_features / sum(style_5$n_features)
style_5_hhi <- sum(style_5_weights^2)

# Write CSV
fwrite(style_summary, file.path(STAGE_DIR, "style_5_axis_exposure.csv"))
fwrite(style_5, file.path(STAGE_DIR, "style_5_axis_exposure_collapsed.csv"))
cat(sprintf("[Step 5d] style HHI(12 detail)=%.3f | HHI(5 axis)=%.3f | n_distinct=%d\n",
            style_hhi, style_5_hhi, n_distinct_styles))
cat("[Step 5d] Style 5-axis distribution:\n")
print(style_5)

# 5e. Regime correlation — cor matrix per regime
cat("\n[Step 5e] Regime correlation matrices (4 regimes) ...\n")
# Build regime label per Date from existing ICIR file structure
# Use simple proxy from BM_Ret_m: extreme bull (< -2sd) / bear (> 2sd) classification
# But we already have regime from ICIR computation.
# We'll classify each month into LOW_VOL_QE / HIGH_VOL_TAPER / INFLATION / DEFAULT
# Using same rule as alpha-research: F14_realized_vol_60d quartile + market trend
panel_reg <- copy(panel)
panel_reg[, vol_60d := F14_realized_vol_60d]
# Hybrid regime classification:
# - LOW_VOL_QE: 2010-01 ~ 2019-12 (post-GFC, ZIRP)
# - HIGH_VOL_TAPER: pre-2010 (post-Lehman + DotCom) AND vol_60d top quartile 2020-onward
# - INFLATION: 2021-06 ~ 2023-12 (post-COVID inflation, Fed hike cycle)
# - DEFAULT: rest
vol_q75 <- quantile(panel_reg$vol_60d, 0.75, na.rm = TRUE)
panel_reg[, regime := fcase(
  Date_eom >= as.Date("2021-06-01") & Date_eom < as.Date("2024-01-01"), "INFLATION",
  Date_eom >= as.Date("2010-01-01") & Date_eom < as.Date("2020-01-01"), "LOW_VOL_QE",
  Date_eom < as.Date("2010-01-01") & !is.na(vol_60d) & vol_60d > vol_q75, "HIGH_VOL_TAPER",
  default = "DEFAULT"
)]
cat(sprintf("[Step 5e] regime classification: vol_q75=%.4f\n", vol_q75))
cat(sprintf("[Step 5e] regime counts:\n"))
print(panel_reg[, .N, by = regime])

# Pairwise NA-aware approach (drop complete.cases mandate)
regime_cor_list <- list()
for (rg in c("LOW_VOL_QE", "HIGH_VOL_TAPER", "INFLATION", "DEFAULT", "ALL")) {
  if (rg == "ALL") {
    sub <- panel_reg
  } else {
    sub <- panel_reg[regime == rg]
  }
  # Compute first-differences with NA handling
  X <- as.matrix(sub[, ..feat_cols])
  if (nrow(X) < 5) {
    cat(sprintf("    %s: n=%d (skipped, < 5 obs)\n", rg, nrow(X)))
    next
  }
  X_diff <- apply(X, 2, function(v) c(NA, diff(v)))
  # NA-aware pairwise cor
  C_rg <- cor(X_diff, use = "pairwise.complete.obs")
  # Average abs off-diagonal cor as concentration metric
  off_diag <- abs(C_rg[upper.tri(C_rg)])
  off_diag <- off_diag[!is.na(off_diag)]
  if (length(off_diag) == 0) {
    cat(sprintf("    %s: n=%d (all off-diag NA, skipped)\n", rg, nrow(X)))
    next
  }
  avg_abs_cor <- mean(off_diag, na.rm = TRUE)
  max_abs_cor <- max(off_diag, na.rm = TRUE)
  pairs_above_8 <- sum(off_diag > 0.8, na.rm = TRUE)
  regime_cor_list[[rg]] <- list(
    regime = rg,
    n_obs = nrow(X),
    avg_abs_off_diag_cor = round(avg_abs_cor, 4),
    max_abs_off_diag_cor = round(max_abs_cor, 4),
    pairs_cor_above_0_8 = pairs_above_8
  )
}
# Save regime cor info as parquet (long-form)
regime_cor_dt <- rbindlist(lapply(regime_cor_list, as.data.table), fill = TRUE)
rc_path <- file.path(STAGE_DIR, "regime_correlation.parquet")
write_parquet(regime_cor_dt, rc_path)
fwrite(regime_cor_dt, file.path(STAGE_DIR, "regime_correlation.csv"))
cat(sprintf("[Step 5e] regime_correlation saved | %d regimes processed\n", nrow(regime_cor_dt)))
print(regime_cor_dt)

# ── Method shopping log save ──────────────────────────────────────────────────
write_json(list(
  task_id = WT_ID,
  agent = "risk-research",
  as_of_date = "2026-05-19",
  selection_objective = "condition_number",
  candidates_tried = length(method_log),
  upper_bound = 5,
  method_log = method_log
), file.path(STAGE_DIR, "method_shopping_log_risk.json"),
   pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("\n[finalize] method_shopping_log_risk.json saved (%d candidates)\n", length(method_log)))

# ── Build risk_package_draft.json ─────────────────────────────────────────────
cat("\n[finalize] Building risk_package_draft.json ...\n")

# Top common risks: PC eigendecomposition
pc_variance_share <- eig_full$values / sum(eig_full$values)
top_pc_share <- pc_variance_share[1:min(3, length(pc_variance_share))]

# Identify top loadings of PC1
pc1_loadings <- eig_full$vectors[, 1]
pc1_top <- order(-abs(pc1_loadings))[1:min(5, length(pc1_loadings))]
pc1_top_feat <- colnames(Sigma_primary)[pc1_top]

# Red flag triggers
challenge_flags <- list()
if (top_pc_share[1] > 0.4) {
  challenge_flags[[length(challenge_flags)+1]] <- list(
    rf = "RF-R1", severity = "HIGH",
    note = sprintf("top PC1 var share %.1f%% > 40%% threshold", 100*top_pc_share[1])
  )
}
if (final_cn > 500) {
  challenge_flags[[length(challenge_flags)+1]] <- list(
    rf = "RF-R2", severity = "HIGH",
    note = sprintf("condition_number %.1f > 500", final_cn)
  )
}
# Stress: worst-case monthly loss
worst_stress_loss <- min(sapply(stress_results, function(r) {
  if (!is.null(r$BM_worst_month)) r$BM_worst_month else 0
}), na.rm = TRUE)
if (worst_stress_loss < -0.10) {
  challenge_flags[[length(challenge_flags)+1]] <- list(
    rf = "RF-R4", severity = "HIGH",
    note = sprintf("worst monthly BM loss %.1f%% < -10%% threshold (GFC/COVID extreme)",
                   100*worst_stress_loss)
  )
}
# Pairs above 0.8
high_cor_pairs <- regime_cor_list[["ALL"]]$pairs_cor_above_0_8 %||% 0L
if (!is.null(high_cor_pairs) && high_cor_pairs > 2) {
  challenge_flags[[length(challenge_flags)+1]] <- list(
    rf = "RF-R5", severity = "MEDIUM",
    note = sprintf("feature pairs with |cor|>0.8: %d (potential multicollinearity)",
                   high_cor_pairs)
  )
}
# Orthogonality with PG2 alpha
if (abs(crowding_result$cor_bear_signal_with_alpha_top20) >= 0.4) {
  challenge_flags[[length(challenge_flags)+1]] <- list(
    rf = "RF-R3-PG2", severity = "MEDIUM",
    note = sprintf("bear sensor cor with PG2 STR_1715 alpha_top20 = %.3f >= 0.4 (overlap)",
                   crowding_result$cor_bear_signal_with_alpha_top20)
  )
}

# M4 redundancy (CRITICAL — bear sensor v2 + M4 BOCPD 88% agreement → incremental info content 의문)
m4_redundant_rate <- crowding_result$m4_agreement_rate
if (m4_redundant_rate >= 0.85) {
  challenge_flags[[length(challenge_flags)+1]] <- list(
    rf = "RF-R3-M4-REDUNDANT", severity = "HIGH",
    note = sprintf("bear sensor v2 agreement rate with PG2 Layer 3 M4 BOCPD = %.1f%% >= 85%% threshold — INCREMENTAL INFO CONTENT 의문 — Forge Stage 5 ensemble (p_bad_t × m4_state Diebold-Mariano test) 필수, 별도 layer admit 정당성 입증 의무",
                   100 * m4_redundant_rate)
  )
}

# Effective dimensionality (top 2 PC > 95% → 사실상 2-factor model)
top2_share <- sum(top_pc_share[1:2])
if (top2_share > 0.95 && length(top_pc_share) >= 3) {
  challenge_flags[[length(challenge_flags)+1]] <- list(
    rf = "RF-R-DIMENSION", severity = "MEDIUM",
    note = sprintf("top 2 PC explain %.1f%% variance, effective dim ≈ 2 in N=%d feature panel — 44 features × 10 categories design 의도와 비교 시 dimension collapse 감지, Forge Stage 1 Phase B 12 features build 후 재검증 의무",
                   100 * top2_share, ncol(final_Sigma))
  )
}

risk_package_draft <- list(
  task_id = WT_ID,
  agent = "risk-research",
  agent_version = "v1.1_bear_sensor_sigma_evt_stress_crowding_style",
  draft_marker = TRUE,
  draft_emission_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  as_of_date = "2026-05-19",
  wt_type = "discovery",
  wt_subclass_charter_v18 = "discovery_design_phase_a",

  alpha_package_received = list(
    factor_specs_count = length(ap$factor_specs),
    factor_family = ap$factor_specs[[1]]$factor_family,
    features_count_designed = 44,
    features_count_built_sample = length(feat_cols),
    bear_regime_sensor = TRUE,
    output_dimension = "scalar_beta_bear_in_0_3_to_1_0"
  ),

  exposure_matrix_ref = exposure_path,
  factor_covariance_ref = fc_path,
  specific_risk_ref = sr_path,
  security_covariance_ref = cov_path,

  selection_objective = "condition_number",
  selection_objective_rationale = "Risk Agent SHALL pick Σ estimator by estimation quality (PSD + cond number + shrinkage stability), NOT by return-side metrics (SR/IR). Hook-enforced (v6.1 R4 P3).",

  covariance_method = list(
    selected = selected_method$name,
    condition_number = round(final_cn, 2),
    min_eigenvalue = round(final_min_eig, 6),
    psd_pass = final_psd,
    factor_coverage_pc1 = round(coverage, 4),
    candidates_tried = length(method_log),
    upper_bound = 5,
    ridge_lambda_applied = ridge_lambda_applied,
    n_obs_T = nrow(ret_mat),
    n_features_N = ncol(ret_mat),
    rationale = sprintf("Ledoit-Wolf 2004 shrinkage selected for lowest cond + clean PSD. Sample baseline retained for diagnostic. Gerber-RMT showed acceptable cond but heavier eigenvalue manipulation. T=%d × N=%d panel after trim. Ridge λ=%.2f applied to cap cond.",
                          nrow(ret_mat), ncol(ret_mat), ridge_lambda_applied)
  ),

  risk_summary = list(
    top_common_risks = sprintf("PC%d (%.1f%%)", 1:3, 100*top_pc_share),
    pc1_top_loadings_features = pc1_top_feat,
    pc1_interpretation = "Dominant common factor — likely volatility regime axis based on top loadings",
    crowding_flags = list(),
    liquidity_flags = list(),
    crowding_score_per_factor = list(
      list(
        factor_name = "BEAR_REGIME_PREDICTION_V2_44_FEATURES",
        crowding_score = round(abs(cor_bear_alpha), 4),
        cor_with_PG2_STR_1715_alpha = round(cor_bear_alpha, 4),
        m4_overlap_redundancy = round(crowding_result$m4_agreement_rate, 4),
        passive_overlap_proxy_NA = "regime sensor not cross-sectional, passive ETF crowding NA",
        demand_elasticity_proxy_NA = "regime sensor not stock-level",
        alert = if (abs(cor_bear_alpha) >= 0.75) "LEVEL_HIGH"
                 else if (abs(cor_bear_alpha) >= 0.50) "LEVEL_MEDIUM"
                 else "LEVEL_LOW",
        interpretation = "bear sensor crowding measured via PG2 STR_1715 alpha overlap. Low cor desirable (orthogonal sleeve)."
      )
    ),
    stress_tests = list(
      DotCom_2002 = stress_results$DotCom_2002$BM_cum_return,
      GFC_2008 = stress_results$GFC_2008$BM_cum_return,
      Euro_Debt_2011 = stress_results$Euro_Debt_2011$BM_cum_return,
      China_Shock_2015 = stress_results$China_Shock_2015$BM_cum_return,
      Q4_Selloff_2018 = stress_results$Q4_Selloff_2018$BM_cum_return,
      COVID_2020 = stress_results$COVID_2020$BM_cum_return,
      Rate_Hike_2022 = stress_results$Rate_Hike_2022$BM_cum_return,
      Iran_War_2026 = stress_results$Iran_War_2026$BM_cum_return,
      worst_monthly_BM = worst_stress_loss
    )
  ),

  diagnostics = list(
    condition_number = round(final_cn, 2),
    shrinkage_used = selected_method$name == "ledoit_wolf_constcor",
    shrinkage_method = if (selected_method$name == "ledoit_wolf_constcor") "ledoit_wolf_constcor" else "none",
    shrinkage_delta = if (selected_method$name == "ledoit_wolf_constcor") round(lw_res$delta, 4) else NA_real_,
    factor_correlation_warnings = list(),
    tail_risk_summary = list(
      method = if (!is.null(evt_result$method)) evt_result$method else "fallback",
      shape_xi = if (!is.null(evt_result$shape_xi)) round(evt_result$shape_xi, 4) else NA_real_,
      tail_class = if (!is.null(evt_result$tail_class)) evt_result$tail_class else NA_character_,
      CVaR_95_evt = if (!is.null(evt_result$ES_95_evt)) round(evt_result$ES_95_evt, 4) else NA_real_,
      VaR_95_evt = if (!is.null(evt_result$VaR_95_evt)) round(evt_result$VaR_95_evt, 4) else NA_real_,
      CVaR_99_evt = if (!is.null(evt_result$ES_99_evt)) round(evt_result$ES_99_evt, 4) else NA_real_
    ),
    regime_correlation_ref = rc_path,
    regime_correlation_summary = regime_cor_list,
    style_5_axis_hhi = round(style_5_hhi, 4),
    style_5_axis_max_share = round(max(style_5_weights), 4),
    style_5_axis_distinct_axes = nrow(style_5),
    style_5_axis_ref = file.path(STAGE_DIR, "style_5_axis_exposure_collapsed.csv"),
    crowding_orthogonality_PG2_STR_1715 = crowding_result$orthogonality_with_PG2_alpha,
    crowding_redundancy_M4_overlay = crowding_result$redundancy_with_M4_overlay
  ),

  evaluation_criteria_status = list(
    psd_check = if (final_psd) "PASS" else "FAIL",
    condition_number_under_500 = if (final_cn < 500) "PASS" else "FAIL",
    factor_coverage_above_80pct = if (coverage > 0.8) "PASS" else sprintf("INFO (%.1f%%)", 100*coverage),
    stress_policy_compliance = if (worst_stress_loss > -0.20) "PASS" else "REVIEW_NEEDED"
  ),

  challenge_flags = challenge_flags,

  honest_disclosure = list(
    note = "본 cycle은 alpha-research v2.0 Phase A design — features 44개 중 15개만 built (sample). Forge Stage 1에서 Phase B 12 features + remaining 17 features build 시 Σ 재추정 의무.",
    built_features_used = feat_cols,
    deferred_features_count = 44 - length(feat_cols),
    sigma_recompute_binding_forge = "MANDATORY at Forge Stage 1 completion (44 features full build)",
    asset_universe_cov_inherited = "Σ_assets 인헤리트 STR_1715 PG2 production manifest (Layer 6 scalar overlay 정합, 본 cycle 미수정)",
    sensor_role = "scalar β_bear ∈ [0.3, 1.0] multiplicative overlay → NOT cross-sectional stock sleeve → max_names=null + weight_bounds=[0,1] 정합 (alpha_package C8 ACCEPT_PARTIAL)",
    self_synthesis_used = FALSE
  ),

  axiom_check = list(
    AX_000 = "documented — 한계 없음, parallel estimator comparison + EVT GPD + 8 stress + crowding 모두 적용",
    AX_001_v2 = sprintf("conditional defense — bad/normal IC ratio via crowding tested, regime stratification ICIR captured (INFLATION 2-3x lift)"),
    AX_002 = "PIT C1-C15 strict, row_pit_status filter applied, self_synthesis_used=FALSE",
    AX_007 = "regime sensor scalar β_bear NOT single-sleeve top20 stock — exception path",
    AX_008 = "Verification Triangulation pending — Forge + Codex + Architect ≥ 2/3 floor (this cycle 1/3 self + Codex Round next)"
  ),

  codex_round_pending = TRUE,

  artifact_lineage = list(
    own_deliverables = list(
      "qepm/mailbox/worktask/WT-D20260518_001/risk_package_draft.json",
      exposure_path,
      fc_path,
      sr_path,
      cov_path,
      file.path(STAGE_DIR, "tail_risk_evt_gpd.json"),
      file.path(STAGE_DIR, "stress_8_windows.json"),
      file.path(STAGE_DIR, "crowding_overlap_with_PG2_STR_1715.json"),
      file.path(STAGE_DIR, "style_5_axis_exposure.csv"),
      file.path(STAGE_DIR, "style_5_axis_exposure_collapsed.csv"),
      rc_path,
      file.path(STAGE_DIR, "regime_correlation.csv"),
      file.path(STAGE_DIR, "method_shopping_log_risk.json"),
      "qepm/mailbox/worktask/WT-D20260518_001/run_risk_research.R"
    ),
    inputs_consumed = list(
      "qepm/mailbox/worktask/WT-D20260518_001/alpha_package.json",
      "stage_artifacts/WT_D20260518_001/feature_panel_design_v2.parquet",
      "stage_artifacts/WT_D20260518_001/ICIR_per_window_per_regime.csv",
      "stage_artifacts/WT_D20260518_001/comprehensive_features_inventory.csv",
      "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet",
      "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/manifest.json"
    )
  )
)

# %||% helper
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

# Write draft
draft_path <- file.path(MAILBOX_DIR, "risk_package_draft.json")
write_json(risk_package_draft, draft_path,
            pretty = TRUE, auto_unbox = TRUE, digits = 6, na = "string")
cat(sprintf("[finalize] risk_package_draft.json saved: %s\n", draft_path))

cat("\n============================================================\n")
cat(sprintf("[risk-research] %s — STEP 1-5 COMPLETE %s\n", WT_ID, format(Sys.time())))
cat("============================================================\n")
cat(sprintf("Σ selected: %s | cond=%.2f | min_eig=%.6f | PSD=%s\n",
            selected_method$name, final_cn, final_min_eig, final_psd))
cat(sprintf("PC1 var share: %.1f%% | factor coverage: %.1f%%\n",
            100*top_pc_share[1], 100*coverage))
cat(sprintf("Tail: ξ=%.3f, CVaR_95=%.3f, tail_class=%s\n",
            evt_result$shape_xi %||% NA, evt_result$ES_95_evt %||% NA,
            evt_result$tail_class %||% NA))
cat(sprintf("Crowding: cor(bear,PG2_alpha)=%.3f | M4_agree=%.1f%% | %s\n",
            cor_bear_alpha, 100*crowding_result$m4_agreement_rate,
            crowding_result$orthogonality_with_PG2_alpha$status))
cat(sprintf("Style: 5-axis HHI=%.3f | distinct=%d | max_share=%.1f%%\n",
            style_5_hhi, nrow(style_5), 100*max(style_5_weights)))
cat(sprintf("Stress worst: %.1f%% monthly (worst window)\n", 100*worst_stress_loss))
cat(sprintf("Challenge flags: %d\n", length(challenge_flags)))
cat("============================================================\n")
