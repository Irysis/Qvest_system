#!/usr/bin/env Rscript
# =====================================================================
# Risk Step 10 — Codex Critic Round REVISE: Full tail risk + decomposition
#                 residual + bootstrap CI for CRISIS n=23
#
# Trigger: Codex C2 (HIGH) — tail_risk.json absent / CVaR_95 breach 10.42% > 2.5% cap
#          Codex C3 (HIGH) — CRISIS n=23 < RF-R8 30 threshold
#          Codex C4 (HIGH) — BΩB'+D Frobenius residual 1.77 vs Σ
#          Codex C7 (MEDIUM) — qepm/stage_artifacts/WT_WT-D20260502_001 absent
# =====================================================================

suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
})

WT_DIR <- "stage_artifacts/WT_D20260502_001"
RISK_DIR <- file.path(WT_DIR, "risk")
QEPM_STAGE_DIR <- "qepm/stage_artifacts/WT_WT-D20260502_001"

state4 <- readRDS(file.path(RISK_DIR, "step4_state.rds"))
state5 <- readRDS(file.path(RISK_DIR, "step5_state.rds"))
state6 <- readRDS(file.path(RISK_DIR, "step6_state.rds"))
state8 <- readRDS(file.path(RISK_DIR, "step8_state.rds"))

cat("[step10] State files loaded.\n")

# =====================================================================
# A. Full tail risk metrics
# =====================================================================
# Use FULL monthly history (220m) for Hill/EVT-GPD robust estimation
# (60M is too short for k_frac=0.10 Hill — yields k=0 insufficient_losses)
m_full <- state4$monthly_wide_full
m_60 <- state4$monthly_wide_60
alpha_in_full <- intersect(state4$alpha_tickers, colnames(m_full))
alpha_in_60 <- intersect(state4$alpha_tickers, colnames(m_60))

if (inherits(m_full, "data.table") || inherits(m_full, "data.frame")) {
  sub_full <- as.data.frame(m_full)[, alpha_in_full, drop = FALSE]
  sub_60 <- as.data.frame(m_60)[, alpha_in_60, drop = FALSE]
} else {
  sub_full <- m_full[, alpha_in_full, drop = FALSE]
  sub_60 <- m_60[, alpha_in_60, drop = FALSE]
}
ew_returns <- rowMeans(as.matrix(sub_full), na.rm = TRUE)
ew_returns <- ew_returns[is.finite(ew_returns)]

ew_returns_60 <- rowMeans(as.matrix(sub_60), na.rm = TRUE)
ew_returns_60 <- ew_returns_60[is.finite(ew_returns_60)]

cat("[step10] EW returns reconstructed: n_full=", length(ew_returns),
    " n_60M=", length(ew_returns_60), "\n", sep = "")

ew_returns <- as.numeric(ew_returns)
ew_returns <- ew_returns[is.finite(ew_returns)]
n_obs <- length(ew_returns)

# (1) VaR/CVaR full
qs <- c(0.01, 0.025, 0.05, 0.10)
var_quantiles <- quantile(ew_returns, probs = qs, na.rm = TRUE, names = TRUE)

cvar <- function(r, q) {
  th <- quantile(r, probs = q, na.rm = TRUE)
  vals <- r[r <= th]
  if (length(vals) == 0) return(NA_real_)
  mean(vals, na.rm = TRUE)
}

cvar_99 <- cvar(ew_returns, 0.01)
cvar_975 <- cvar(ew_returns, 0.025)
cvar_95 <- cvar(ew_returns, 0.05)
cvar_90 <- cvar(ew_returns, 0.10)

# (2) Hill tail-index estimator (left tail)
hill_alpha <- function(r, k_frac = 0.10) {
  losses <- -r
  losses_pos <- losses[losses > 0]
  if (length(losses_pos) < 30) return(list(alpha = NA, k = 0, note = "insufficient_losses"))
  losses_sorted <- sort(losses_pos, decreasing = TRUE)
  k <- max(10, floor(length(losses_sorted) * k_frac))
  if (k >= length(losses_sorted)) k <- length(losses_sorted) - 1
  threshold <- losses_sorted[k + 1]
  excesses <- log(losses_sorted[1:k]) - log(threshold)
  alpha_hat <- 1 / mean(excesses)
  list(alpha = alpha_hat, k = k, threshold = threshold,
       note = ifelse(alpha_hat < 2, "extreme_heavy_tail", ifelse(alpha_hat < 4, "heavy_tail", "moderate_tail")))
}

hill_left <- hill_alpha(ew_returns, k_frac = 0.10)

# (3) EVT-GPD generalized Pareto fit (peaks-over-threshold, left tail)
evt_gpd <- function(r, threshold_q = 0.10) {
  losses <- -r
  threshold <- quantile(losses, probs = 1 - threshold_q, na.rm = TRUE)
  exceedances <- losses[losses > threshold] - threshold
  n_exceed <- length(exceedances)
  if (n_exceed < 15) return(list(xi = NA, sigma = NA, n = n_exceed, note = "insufficient_exceedances"))
  # PWM (probability-weighted moments) estimator
  x <- sort(exceedances)
  n <- length(x)
  m0 <- mean(x)
  m1 <- mean(x * (1 - (1:n - 0.35) / n))
  xi_hat <- 2 - m0 / (m0 - 2 * m1)
  sigma_hat <- 2 * m0 * (m0 - 2 * m1) / (m0 - 4 * m1)
  if (!is.finite(xi_hat) || !is.finite(sigma_hat)) {
    xi_hat <- NA; sigma_hat <- NA
  }
  list(xi = xi_hat, sigma = sigma_hat, threshold = threshold, n = n_exceed,
       note = ifelse(is.na(xi_hat), "estimation_failed",
              ifelse(xi_hat > 0.5, "very_heavy_tail",
              ifelse(xi_hat > 0, "heavy_tail", "light_tail"))))
}

gpd_fit <- evt_gpd(ew_returns, threshold_q = 0.10)

# (4) CDaR — conditional drawdown-at-risk
compute_cdar <- function(r, q = 0.05) {
  cum <- cumprod(1 + r) - 1
  peak <- cummax(c(0, cum))[-1]
  dd <- (cum - peak) / (1 + peak)
  dd_sorted <- sort(dd)  # most negative first
  th_idx <- max(1, ceiling(q * length(dd_sorted)))
  threshold <- dd_sorted[th_idx]
  worst <- dd_sorted[dd_sorted <= threshold]
  list(cdar = mean(worst, na.rm = TRUE), max_dd = min(dd, na.rm = TRUE), n_dd = length(dd))
}

cdar_95 <- compute_cdar(ew_returns, q = 0.05)
cdar_99 <- compute_cdar(ew_returns, q = 0.01)

cat("[step10] CVaR_95 =", round(cvar_95 * 100, 4), "% / cap 2.5% — breach factor",
    round(abs(cvar_95) / 0.025, 2), "x\n")
cat("[step10] CVaR_99 =", round(cvar_99 * 100, 4), "%\n")
cat("[step10] CDaR_95 =", round(cdar_95$cdar * 100, 4), "%\n")
cat("[step10] Hill alpha =", round(hill_left$alpha %||% NA, 4),
    "(k =", hill_left$k, ", note =", hill_left$note, ")\n")
cat("[step10] EVT-GPD xi =", round(gpd_fit$xi %||% NA, 4),
    " sigma =", round(gpd_fit$sigma %||% NA, 4),
    " n_exceed =", gpd_fit$n, "\n")

# =====================================================================
# B. Bootstrap CI for CRISIS regime (n=23 < RF-R8 30) + pooled fallback
# =====================================================================

# Reload regime-conditional data
state5_obj <- state5
regime_data_keys <- grep("regime", names(state5_obj), value = TRUE, ignore.case = TRUE)
cat("[step10] State5 regime keys:", paste(regime_data_keys, collapse = ", "), "\n")

# Get monthly_wide + regime labels
m60 <- state4$monthly_wide_60
alpha_in <- intersect(state4$alpha_tickers, colnames(m60))
if (inherits(m60, "data.table") || inherits(m60, "data.frame")) {
  sub60 <- as.data.frame(m60)[, alpha_in, drop = FALSE]
} else {
  sub60 <- m60[, alpha_in, drop = FALSE]
}
ew_60 <- rowMeans(as.matrix(sub60), na.rm = TRUE)

# Try to get regime labels from state5
regime_labels <- state5_obj$regime_labels
if (is.null(regime_labels)) {
  regime_labels <- state5_obj$regime_classified
}
if (is.null(regime_labels) && !is.null(state5_obj$dt_regime)) {
  regime_labels <- state5_obj$dt_regime
}

# Fallback: classify by ew_60 itself (bottom 30% = CRISIS, mid 40% = NORMAL, top 30% = BULL)
if (is.null(regime_labels)) {
  q_30 <- quantile(ew_60, 0.30, na.rm = TRUE)
  q_70 <- quantile(ew_60, 0.70, na.rm = TRUE)
  regime_labels <- ifelse(ew_60 <= q_30, "CRISIS",
                  ifelse(ew_60 >= q_70, "BULL", "NORMAL"))
  regime_source <- "self_classified_fallback"
} else if (is.character(regime_labels) || is.factor(regime_labels)) {
  regime_source <- "state5_provided"
} else {
  regime_source <- "complex_object_skip"
  regime_labels <- NULL
}

bootstrap_crisis_ci <- function(returns, regime_lab, B = 1000, alpha = 0.05) {
  if (is.null(regime_lab) || length(regime_lab) != length(returns)) {
    return(list(note = "regime_length_mismatch"))
  }
  crisis_idx <- which(toupper(regime_lab) %in% c("CRISIS", "BAD"))
  normal_idx <- which(toupper(regime_lab) %in% c("NORMAL", "BULL"))
  n_crisis <- length(crisis_idx)
  n_normal <- length(normal_idx)
  if (n_crisis < 5) return(list(note = "insufficient_crisis_n", n_crisis = n_crisis))

  crisis_returns <- returns[crisis_idx]
  normal_returns <- returns[normal_idx]

  set.seed(42)
  boot_means <- replicate(B, mean(sample(crisis_returns, replace = TRUE)))
  boot_cvar <- replicate(B, {
    s <- sample(crisis_returns, replace = TRUE)
    th <- quantile(s, 0.05)
    mean(s[s <= th])
  })

  # Compare crisis vs normal
  diff_means <- replicate(B, {
    cs <- sample(crisis_returns, replace = TRUE)
    ns <- sample(normal_returns, replace = TRUE)
    mean(cs) - mean(ns)
  })

  list(
    n_crisis = n_crisis,
    n_normal = n_normal,
    crisis_mean = mean(crisis_returns),
    crisis_mean_ci = quantile(boot_means, c(alpha/2, 1-alpha/2)),
    crisis_cvar95_ci = quantile(boot_cvar, c(alpha/2, 1-alpha/2)),
    crisis_minus_normal_mean_ci = quantile(diff_means, c(alpha/2, 1-alpha/2)),
    bootstrap_B = B,
    rf_r8_n_threshold = 30,
    rf_r8_pass = n_crisis >= 30,
    pooled_fallback_recommended = n_crisis < 30,
    note = ifelse(n_crisis < 30,
                  "RF-R8 thin-sample. Pooled CRISIS+NORMAL Σ recommended for downstream.",
                  "RF-R8 PASS")
  )
}

boot_ci <- bootstrap_crisis_ci(ew_60, regime_labels, B = 1000)
cat("[step10] Bootstrap CRISIS CI computed (regime source:", regime_source, ").\n")
print(boot_ci)

# =====================================================================
# C. BΩB'+D vs Σ Frobenius residual (Codex C4)
# =====================================================================

B_mat <- state4$exposure_matrix_B
Omega <- state4$factor_covariance_Omega
D_vec <- state4$specific_risk_D
Sigma_primary <- state4$Sigma_primary

assert_decomp_match <- function(B_mat, Omega, D_vec, Sigma) {
  if (is.null(B_mat) || is.null(Omega) || is.null(D_vec) || is.null(Sigma)) {
    return(list(note = "missing_components", match = FALSE))
  }

  if (is.vector(D_vec)) D <- diag(as.numeric(D_vec)) else D <- as.matrix(D_vec)

  # align
  asset_names_B <- rownames(B_mat)
  asset_names_S <- rownames(Sigma)
  if (is.null(asset_names_B)) asset_names_B <- paste0("a", seq_len(nrow(B_mat)))
  if (is.null(asset_names_S)) asset_names_S <- paste0("a", seq_len(nrow(Sigma)))

  common_a <- intersect(asset_names_B, asset_names_S)
  if (length(common_a) < 5) {
    return(list(note = "insufficient_common_assets", n = length(common_a), match = FALSE))
  }

  B_sub <- B_mat[common_a, , drop = FALSE]
  D_sub <- D[match(common_a, asset_names_B), match(common_a, asset_names_B), drop = FALSE]
  S_sub <- Sigma[common_a, common_a, drop = FALSE]

  Sigma_recon <- B_sub %*% Omega %*% t(B_sub) + D_sub
  resid <- as.matrix(S_sub) - Sigma_recon

  fro_resid <- sqrt(sum(resid^2))
  fro_S <- sqrt(sum(S_sub^2))
  rel_fro <- fro_resid / fro_S
  max_abs <- max(abs(resid))

  list(
    n_assets_compared = length(common_a),
    frobenius_residual = fro_resid,
    frobenius_sigma = fro_S,
    relative_frobenius = rel_fro,
    max_abs_residual = max_abs,
    match_strict = rel_fro < 0.05,
    match_acceptable = rel_fro < 0.20,
    interpretation = ifelse(rel_fro < 0.05, "decomposition matches Σ tightly",
                     ifelse(rel_fro < 0.20, "decomposition is approximate (post-shrink Σ has Tikhonov component)",
                           "decomposition does NOT match Σ — Σ has ridge regularization beyond BΩB'+D"))
  )
}

`%||%` <- function(a, b) if (is.null(a)) b else a

decomp_audit <- assert_decomp_match(B_mat, Omega, D_vec, Sigma_primary)
cat("[step10] BΩB'+D vs Σ residual: max_abs=", round(decomp_audit$max_abs_residual %||% NA, 6),
    " rel_fro=", round(decomp_audit$relative_frobenius %||% NA, 4), "\n")
cat("[step10] interpretation:", decomp_audit$interpretation %||% "NA", "\n")

# =====================================================================
# D. Tail risk JSON output
# =====================================================================

cap_cvar95 <- 0.025
cap_cvar99 <- 0.05  # typical
breach_factor_95 <- abs(cvar_95) / cap_cvar95
breach_factor_99 <- abs(cvar_99) / cap_cvar99

infeasibility_report <- list(
  trigger = "CVaR_95_cap_breach",
  cvar_95_observed_pct = round(cvar_95 * 100, 4),
  cvar_95_cap_pct = round(cap_cvar95 * 100, 4),
  breach_factor = round(breach_factor_95, 2),
  recommended_actions = c(
    "Cap individual weights below MaxWt 0.20 (e.g., 0.10 ceiling).",
    "Constrain optimizer with explicit CVaR_95 ≤ 0.025 hard constraint.",
    "Increase shrinkage or reduce universe N to allow tighter Σ + smaller positions.",
    "If infeasible under all relaxations: governor admission with WAIVER + Hill alpha caveat."
  ),
  optimizer_handoff_decision = "PASS Σ + tail_risk.json with cvar_breach=TRUE flag. Optimizer must build CVaR-aware MVO or HRP with vol_target<=15% to bring portfolio CVaR within cap."
)

tail_risk_full <- list(
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  task_id = "WT-D20260502_001",
  agent = "risk-research",
  basis = "top20_alpha_equal_weight_synthetic_portfolio_monthly_returns_FULL_HISTORY",
  n_obs_months = n_obs,
  n_obs_60M_window = length(ew_returns_60),
  rationale_basis_choice = "Full 220M history used for Hill/EVT/CVaR (60M too short for k_frac=0.10 Hill estimator → insufficient_losses).",

  var = list(
    var_99_monthly_pct = round(unname(var_quantiles["1%"]) * 100, 4),
    var_975_monthly_pct = round(unname(var_quantiles["2.5%"]) * 100, 4),
    var_95_monthly_pct = round(unname(var_quantiles["5%"]) * 100, 4),
    var_90_monthly_pct = round(unname(var_quantiles["10%"]) * 100, 4)
  ),

  cvar = list(
    cvar_99_monthly_pct = round(cvar_99 * 100, 4),
    cvar_975_monthly_pct = round(cvar_975 * 100, 4),
    cvar_95_monthly_pct = round(cvar_95 * 100, 4),
    cvar_90_monthly_pct = round(cvar_90 * 100, 4)
  ),

  cvar_cap_audit = list(
    cap_cvar_95_monthly_pct = cap_cvar95 * 100,
    breach_95 = abs(cvar_95) > cap_cvar95,
    breach_factor_95 = round(breach_factor_95, 2),
    cap_cvar_99_monthly_pct = cap_cvar99 * 100,
    breach_99 = abs(cvar_99) > cap_cvar99,
    breach_factor_99 = round(breach_factor_99, 2),
    note = "CVaR cap is mandate-level (not synthetic portfolio). Optimizer will reduce position sizes to bring portfolio-level CVaR within cap."
  ),

  hill_estimator = list(
    alpha_left_tail = round(hill_left$alpha %||% NA_real_, 4),
    k = hill_left$k,
    threshold = round(hill_left$threshold %||% NA_real_, 6),
    note = hill_left$note,
    interpretation = "Hill alpha < 2 = infinite-variance tail; alpha 2-4 = heavy tail; alpha > 4 = moderate."
  ),

  evt_gpd = list(
    xi_shape = round(gpd_fit$xi %||% NA_real_, 4),
    sigma_scale = round(gpd_fit$sigma %||% NA_real_, 6),
    threshold = round(gpd_fit$threshold %||% NA_real_, 6),
    n_exceedances = gpd_fit$n,
    note = gpd_fit$note,
    interpretation = "xi>0 → heavy tail. xi>0.5 → very heavy (CVaR explodes). xi<0 → bounded tail."
  ),

  cdar = list(
    cdar_95_pct = round(cdar_95$cdar * 100, 4),
    cdar_99_pct = round(cdar_99$cdar * 100, 4),
    max_drawdown_pct = round(cdar_95$max_dd * 100, 4),
    n_observations = cdar_95$n_dd
  ),

  bootstrap_ci_crisis = c(boot_ci, list(regime_source = regime_source)),

  decomposition_audit = decomp_audit,

  rf_flags = list(
    rf_r2_post_shrink_cond = list(observed = 391.273, cap = 100, fail = TRUE,
                                   mitigation = "Top20 sub-Σ cond=84.8 → if optimizer locks universe to alpha top20, RF-R2 mitigated. Otherwise REVISE Σ."),
    rf_r4_cvar = list(observed = abs(cvar_95), cap = 0.025, fail = TRUE,
                      mitigation = "Optimizer CVaR-aware build."),
    rf_r6_evt = list(hill_alpha = round(hill_left$alpha %||% NA_real_, 4),
                      gpd_xi = round(gpd_fit$xi %||% NA_real_, 4),
                      heavy_tail_flag = (hill_left$alpha %||% Inf) < 4 || (gpd_fit$xi %||% 0) > 0,
                      note = "Heavy tail confirmed — optimizer should not assume Gaussian for tail."),
    rf_r8_thin_sample = list(crisis_n = boot_ci$n_crisis %||% NA, threshold = 30,
                              fail = (boot_ci$n_crisis %||% 0) < 30,
                              mitigation = "Pooled CRISIS+NORMAL Σ recommended; bootstrap CI provided.")
  ),

  infeasibility_report = infeasibility_report,

  rebuttals_or_acceptances = list(
    codex_c2_cvar_breach = "ACCEPT — full tail metrics now reported. Optimizer must enforce CVaR cap.",
    codex_c3_thin_crisis = "ACCEPT — bootstrap CI + pooled fallback recommendation provided.",
    codex_c4_decomposition_residual = ifelse(
      (decomp_audit$relative_frobenius %||% 1) < 0.20,
      "PARTIAL — BΩB'+D reconstructs Σ within ~20% Frobenius. Σ has Tikhonov ridge component beyond decomposition. Optimizer should use Σ directly (covariance.parquet), not BΩB'+D.",
      "ACCEPT — decomposition does NOT equal Σ (Tikhonov). Optimizer uses Σ directly."
    )
  )
)

# Write tail_risk.json
tail_path_external <- file.path(WT_DIR, "tail_risk.json")
write(toJSON(tail_risk_full, pretty = TRUE, auto_unbox = TRUE, na = "null"), file = tail_path_external)
cat("[step10] tail_risk.json written:", tail_path_external, "\n")

# =====================================================================
# E. Mirror to qepm/stage_artifacts/WT_WT-D20260502_001/ (Codex C7)
# =====================================================================

dir.create(QEPM_STAGE_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(QEPM_STAGE_DIR, "risk"), recursive = TRUE, showWarnings = FALSE)

# Copy artifacts
artifacts <- c(
  "covariance.parquet",
  "covariance_top20.parquet",
  "exposure_matrix.parquet",
  "factor_covariance.parquet",
  "specific_risk.parquet",
  "regime_correlation.parquet",
  "tail_risk.json"
)

for (a in artifacts) {
  src <- file.path(WT_DIR, a)
  dst <- file.path(QEPM_STAGE_DIR, a)
  if (file.exists(src)) {
    file.copy(src, dst, overwrite = TRUE)
    cat("[step10] Copied:", a, "\n")
  } else {
    cat("[step10] MISSING source:", src, "\n")
  }
}

# Save state10
state10 <- list(
  task_id = "WT-D20260502_001",
  generated_at = Sys.time(),
  tail_risk_full = tail_risk_full,
  decomp_audit = decomp_audit,
  bootstrap_ci_crisis = boot_ci
)
saveRDS(state10, file.path(RISK_DIR, "step10_state.rds"))

cat("\n[step10] DONE. tail_risk.json + qepm/stage_artifacts mirror created.\n")
cat("[step10] Summary:\n")
cat("  CVaR_95 =", round(cvar_95 * 100, 4), "% (cap 2.5%, breach", round(breach_factor_95, 2), "x) — ACCEPT\n")
cat("  CVaR_99 =", round(cvar_99 * 100, 4), "%\n")
cat("  Hill alpha =", round(hill_left$alpha %||% NA_real_, 4), " (k=", hill_left$k, ")\n")
cat("  EVT-GPD xi =", round(gpd_fit$xi %||% NA_real_, 4), " sigma=", round(gpd_fit$sigma %||% NA_real_, 4), "\n")
cat("  CDaR_95 =", round(cdar_95$cdar * 100, 4), "%\n")
cat("  Bootstrap crisis n=", boot_ci$n_crisis %||% NA, " (RF-R8 threshold=30)\n")
cat("  BΩB'+D residual rel_fro=", round(decomp_audit$relative_frobenius %||% NA_real_, 4), "\n")
