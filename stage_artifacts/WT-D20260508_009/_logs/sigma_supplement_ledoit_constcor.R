#==============================================================================
# WT-D20260508_009 — Σ Supplement: Ledoit-Wolf Constant-Correlation Target
#
# Background (Codex critic 진단 정합):
#   - hrp_core.R `.get_cor_cov(cov_method = "ledoit_wolf")` 공식이 OAS 변형.
#   - n_obs ≈ p (252 ≈ 241) high-dim 환경에서 rho_raw=159 → rho_capped=1.0.
#   - 결과: σ ≈ μ × I (isotropic). off-diag mean = 0. 정보 wipe.
#
# 보강: Ledoit-Wolf 2004 JPM "Honey, I Shrunk the Sample Covariance" —
#   Target T = constant-correlation matrix
#     T_ij = sqrt(s_ii × s_jj) × ρ_bar  (i≠j); T_ii = s_ii
#     ρ_bar = mean off-diag of correlation matrix
#   Shrinkage: Σ_LW = δ × T + (1-δ) × S
#   δ formula: Ledoit-Wolf 2003/2004 공식 직접 (R 패키지 cvCovEst::cvCovEst::ledoitWolf 무참조)
#
# 추가:
#   - Eigenvalue floor PSD projection 검증 (sample S에 적용 시 PSD 충족 확인)
#   - DIM cap(d): d=2 (tr(S²)) / d=1 (tr(S)) ratio
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID     <- "WT-D20260508_009"
WT_DIR    <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
SA_DIR    <- file.path(PROJ_ROOT, "stage_artifacts", WT_ID)
LOG_DIR   <- file.path(SA_DIR, "_logs")

cat("\n============================================\n")
cat("Σ Supplement: LW constant-correlation target + eigenvalue floor\n")
cat("============================================\n\n")

# Load alpha_fwd universe + RAWDATA
alpha_fwd <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores.parquet")))
RAW <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/rawdata.parquet")))
setkey(RAW, Date, Ticker)

sig_date <- as.Date("2026-04-30")
risk_universe <- alpha_fwd$Ticker
ret_panel <- RAW[Date < sig_date & Ticker %in% risk_universe, .(Date, Ticker, Ret)]
last_dates <- tail(sort(unique(ret_panel$Date)), 252)
ret_panel <- ret_panel[Date %in% last_dates]
wide <- dcast(ret_panel, Date ~ Ticker, value.var = "Ret")
ret_mat <- as.matrix(wide[, -1, drop = FALSE])
keep_cols <- colSums(!is.na(ret_mat)) >= 200
ret_mat <- ret_mat[, keep_cols, drop = FALSE]
keep_rows <- rowSums(!is.na(ret_mat)) >= ncol(ret_mat) * 0.5
ret_mat <- ret_mat[keep_rows, , drop = FALSE]
ret_mat[is.na(ret_mat)] <- 0
N <- ncol(ret_mat); T_d <- nrow(ret_mat)
cat(sprintf("Universe: %d × %d (T × N)\n\n", T_d, N))

#===============================================
# Method A: Sample S
#===============================================
S <- cov(ret_mat, use = "pairwise.complete.obs")
diag_S <- diag(S)
sds <- sqrt(diag_S)
cor_S <- S / outer(sds, sds); diag(cor_S) <- 1
cn_S <- kappa(S)
eig_S <- eigen(S, symmetric = TRUE, only.values = TRUE)$values
cat(sprintf("[A] Sample S      : κ=%.0f | min_eig=%.3e | PSD=%s\n",
            cn_S, min(eig_S), min(eig_S) > -1e-12))

#===============================================
# Method B: Ledoit-Wolf 2004 Constant-Correlation Target (정통 공식)
# T = D^{1/2} R̄ D^{1/2}, R̄_ij = ρ_bar (i≠j), R̄_ii = 1
# δ formula:
#   π̂ = sum_{i,j} Var(s_ij)            (asymptotic variance of S elements)
#   ρ̂ = sum_i Var(s_ii) +
#         sum_{i≠j} (1/2)(sqrt(s_jj/s_ii) AsyCov(s_ii, s_ij) + sqrt(s_ii/s_jj) AsyCov(s_jj, s_ij))
#   γ̂ = sum_{i,j} (T_ij - s_ij)^2
#   δ = (π̂ - ρ̂) / γ̂ / T_d
#===============================================
# Compute ρ̄
upper <- upper.tri(cor_S)
rho_bar <- mean(cor_S[upper], na.rm = TRUE)
# Target T
T_mat <- outer(sds, sds) * rho_bar
diag(T_mat) <- diag_S

# Empirical asymptotic variance of S elements
# Demean returns
mu_vec <- colMeans(ret_mat)
X <- sweep(ret_mat, 2, mu_vec, "-")  # T × N centered

# π̂ = sum_{i,j} (1/T) sum_t (X_t,i × X_t,j - S_ij)^2
# vectorized: pi_hat = sum_{i,j} (mean over t of (X_ti X_tj)^2) - S_ij^2
# Using sum: M2_ij = (1/T) sum_t X_ti^2 X_tj^2
# Easier: compute sum element-wise
M2 <- (t(X^2) %*% X^2) / T_d  # E[X_i^2 X_j^2]
pi_mat <- M2 - S^2
pi_hat <- sum(pi_mat)

# γ̂
gamma_hat <- sum((T_mat - S)^2)

# ρ̂ — diagonal terms + off-diagonal
# Diagonal: sum_i Var(s_ii) = sum_i (1/T)(E[X_i^4] - s_ii^2)
diag_var <- diag(pi_mat)
rho_diag <- sum(diag_var)

# Off-diagonal (Ledoit-Wolf 2004 Honey JPM eq A1): more involved.
# For simplicity (well-validated approximation):
#   ρ̂ ≈ rho_diag + ρ̄ × sum_{i≠j} (sqrt(s_jj/s_ii) + sqrt(s_ii/s_jj))/2 × AsyCov(s_ii, s_ij)
#
# Using cross-covariance formula:
# ψ_ij_diag = (1/T) sum_t [(X_ti^2 - s_ii)(X_ti X_tj - s_ij)]
# Pre-compute: for each i, (X_i^2 - s_ii) ⊙ (X cross X_i - s_i,*)
rho_offdiag <- 0
# Loop (small N ok)
for (i in 1:N) {
  Xi2 <- X[, i]^2 - diag_S[i]
  Xi  <- X[, i]
  for (j in 1:N) {
    if (i == j) next
    s_ij <- S[i, j]
    Xj  <- X[, j]
    psi_iij <- mean(Xi2 * (Xi * Xj - s_ij))
    psi_jji <- mean((X[, j]^2 - diag_S[j]) * (Xi * Xj - s_ij))
    coef_iij <- 0.5 * sqrt(diag_S[j] / max(diag_S[i], 1e-12)) * rho_bar
    coef_jji <- 0.5 * sqrt(diag_S[i] / max(diag_S[j], 1e-12)) * rho_bar
    rho_offdiag <- rho_offdiag + coef_iij * psi_iij + coef_jji * psi_jji
  }
}
rho_hat <- rho_diag + rho_offdiag

# δ
delta_raw <- (pi_hat - rho_hat) / gamma_hat / T_d
delta <- max(0, min(1, delta_raw))
cat(sprintf("[B] LW const-cor : π̂=%.4e  ρ̂=%.4e  γ̂=%.4e  δ_raw=%.4f  δ=%.4f\n",
            pi_hat, rho_hat, gamma_hat, delta_raw, delta))

cov_LW_cc <- delta * T_mat + (1 - delta) * S
# Ensure symmetry
cov_LW_cc <- (cov_LW_cc + t(cov_LW_cc)) / 2
cn_lwcc <- kappa(cov_LW_cc)
eig_lwcc <- eigen(cov_LW_cc, symmetric = TRUE, only.values = TRUE)$values
psd_lwcc <- min(eig_lwcc) > -1e-12
sds_lwcc <- sqrt(diag(cov_LW_cc))
cor_lwcc <- cov_LW_cc / outer(sds_lwcc, sds_lwcc); diag(cor_lwcc) <- 1
offdiag_mean_abs <- mean(abs(cor_lwcc[upper]), na.rm = TRUE)
cat(sprintf("    cov_LW_cc    : κ=%.2f | min_eig=%.3e | PSD=%s | off-diag |cor| mean=%.4f\n",
            cn_lwcc, min(eig_lwcc), psd_lwcc, offdiag_mean_abs))

#===============================================
# Method C: Eigenvalue Floor PSD projection on Sample
#===============================================
eig_decomp <- eigen(S, symmetric = TRUE)
eig_vals_C <- eig_decomp$values
eig_floor <- max(eig_vals_C) * 1e-4  # 1e-4 of max eigenvalue
eig_vals_floored <- pmax(eig_vals_C, eig_floor)
cov_C <- eig_decomp$vectors %*% diag(eig_vals_floored) %*% t(eig_decomp$vectors)
cov_C <- (cov_C + t(cov_C)) / 2
cn_C <- kappa(cov_C)
eig_C <- eigen(cov_C, symmetric = TRUE, only.values = TRUE)$values
psd_C <- min(eig_C) > -1e-12
sds_C <- sqrt(diag(cov_C))
cor_C <- cov_C / outer(sds_C, sds_C); diag(cor_C) <- 1
offdiag_mean_abs_C <- mean(abs(cor_C[upper]), na.rm = TRUE)
cat(sprintf("[C] EigFloor S   : κ=%.2f | min_eig=%.3e | PSD=%s | off-diag |cor| mean=%.4f\n",
            cn_C, min(eig_C), psd_C, offdiag_mean_abs_C))

#===============================================
# Method D: 본래 hrp_core LW (OAS 변형) — diagnose
#===============================================
mu_S <- mean(diag(S))
rho_OAS_raw <- ((T_d - 2) / T_d * sum(diag(S)^2) + sum(S)^2) /
                ((T_d + 2) * (sum(S^2) - sum(diag(S)^2) / N))
rho_OAS <- min(rho_OAS_raw, 1)
cov_OAS <- (1 - rho_OAS) * S + rho_OAS * mu_S * diag(N)
cn_OAS <- kappa(cov_OAS)
eig_OAS <- eigen(cov_OAS, symmetric = TRUE, only.values = TRUE)$values
sds_OAS <- sqrt(diag(cov_OAS))
cor_OAS <- cov_OAS / outer(sds_OAS, sds_OAS); diag(cor_OAS) <- 1
offdiag_mean_abs_D <- mean(abs(cor_OAS[upper]), na.rm = TRUE)
cat(sprintf("[D] LW OAS (hrp) : κ=%.2f | min_eig=%.3e | PSD=%s | off-diag |cor| mean=%.4f | rho=%.4f\n",
            cn_OAS, min(eig_OAS), min(eig_OAS) > -1e-12, offdiag_mean_abs_D, rho_OAS))

#===============================================
# Selection comparison — finalize
#===============================================
methods_compare <- list(
  list(name = "sample",          condition = cn_S,    min_eig = min(eig_S),
       psd = min(eig_S) > -1e-12, offdiag_cor = mean(abs(cor_S[upper]), na.rm=TRUE),
       interpretation = "high κ but information preserved (offdiag intact)"),
  list(name = "ledoit_wolf_constcor", condition = cn_lwcc, min_eig = min(eig_lwcc),
       psd = psd_lwcc, offdiag_cor = offdiag_mean_abs,
       interpretation = sprintf("LW2004 정통 const-corr target shrinkage δ=%.3f", delta),
       delta = delta),
  list(name = "eigfloor_sample", condition = cn_C, min_eig = min(eig_C),
       psd = psd_C, offdiag_cor = offdiag_mean_abs_C,
       interpretation = "PSD-projected sample (eigenvalue floor at max × 1e-4)"),
  list(name = "ledoit_wolf_oas_hrp", condition = cn_OAS, min_eig = min(eig_OAS),
       psd = min(eig_OAS) > -1e-12, offdiag_cor = offdiag_mean_abs_D,
       interpretation = "hrp_core current OAS variant — n≈p에서 isotropic strong",
       rho_capped = rho_OAS)
)

cat("\n=== Summary ===\n")
for (m in methods_compare) {
  cat(sprintf("  %-25s κ=%-12.0f offdiag|cor|=%.4f PSD=%s\n",
              m$name, m$condition, m$offdiag_cor, m$psd))
}

# Selection rule revised:
#   - PSD 충족 + offdiag information 보존 (offdiag |cor| > 0.05 reasonable)
#   - condition_number 보조 (ill-cond 방지)
#   - 기존 OAS는 정보 wipe 위험으로 기각
candidates <- methods_compare
candidates_ok <- Filter(function(m) m$psd && m$offdiag_cor > 0.05, candidates)
if (length(candidates_ok) == 0) {
  selected <- "ledoit_wolf_constcor"  # fallback
} else {
  conds <- sapply(candidates_ok, function(m) m$condition)
  selected <- candidates_ok[[which.min(conds)]]$name
}
cat(sprintf("\n→ SELECTED (revised): %s\n", selected))

# Save selected covariance
if (selected == "ledoit_wolf_constcor") {
  selected_cov <- cov_LW_cc
} else if (selected == "eigfloor_sample") {
  selected_cov <- cov_C
} else if (selected == "ledoit_wolf_oas_hrp") {
  selected_cov <- cov_OAS
} else {
  selected_cov <- S
}
sel_cn <- kappa(selected_cov)
sel_min_eig <- min(eigen(selected_cov, symmetric = TRUE, only.values = TRUE)$values)

# Save supplement
supplement <- list(
  task_id = WT_ID,
  context = "Σ supplement: Codex critic 진단 정합 (LW OAS isotropic 결함 발견 → constant-correlation target 추가)",
  ledoit_wolf_oas_diagnostic = list(
    rho_raw = rho_OAS_raw,
    rho_capped = rho_OAS,
    interpretation = "n_obs(252) ≈ p(241) high-dim → rho_raw=159, capped 1.0 → cov ≈ μ × I",
    offdiag_cor_mean_abs = offdiag_mean_abs_D,
    information_preserved = offdiag_mean_abs_D > 0.05
  ),
  ledoit_wolf_constcor = list(
    rho_bar = rho_bar,
    delta_raw = delta_raw,
    delta_capped = delta,
    pi_hat = pi_hat,
    rho_hat = rho_hat,
    gamma_hat = gamma_hat,
    condition_number = cn_lwcc,
    min_eig = min(eig_lwcc),
    psd = psd_lwcc,
    offdiag_cor_mean_abs = offdiag_mean_abs,
    interpretation = "LW2004 JPM Honey 정통 공식. n_obs≈p 에서 information 보존."
  ),
  eigfloor_sample = list(
    eig_floor = eig_floor,
    condition_number = cn_C,
    min_eig = min(eig_C),
    psd = psd_C,
    offdiag_cor_mean_abs = offdiag_mean_abs_C
  ),
  sample = list(
    condition_number = cn_S,
    min_eig = min(eig_S),
    psd = min(eig_S) > -1e-12,
    offdiag_cor_mean_abs = mean(abs(cor_S[upper]), na.rm=TRUE)
  ),
  comparison_table = methods_compare,
  selection_revised = list(
    selected_method = selected,
    selection_objective = "condition_number with offdiag information preservation",
    rationale = "OAS 변형은 κ=1.00이지만 offdiag wipe (information 0). LW const-corr 또는 eigfloor sample이 정보 보존 시 우월.",
    selected_condition = sel_cn,
    selected_min_eig = sel_min_eig
  )
)
write_json(supplement, file.path(WT_DIR, "sigma_supplement_ledoit_wolf_constcor.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# Save selected covariance (overwriting prior)
cov_dt <- as.data.table(selected_cov)
cov_dt[, Ticker := colnames(selected_cov)]
setcolorder(cov_dt, c("Ticker", colnames(selected_cov)))
write_parquet(cov_dt, file.path(SA_DIR, "covariance.parquet"))

cat(sprintf("\nSaved: covariance.parquet (%s) | sigma_supplement.json\n",
            selected))
cat(sprintf("κ(Σ_selected)=%.2f | min_eig=%.3e | offdiag |cor|=",
            sel_cn, sel_min_eig))
sel_offdiag <- {
  if (selected == "ledoit_wolf_constcor") offdiag_mean_abs
  else if (selected == "eigfloor_sample") offdiag_mean_abs_C
  else if (selected == "ledoit_wolf_oas_hrp") offdiag_mean_abs_D
  else mean(abs(cor_S[upper]), na.rm = TRUE)
}
cat(sprintf("%.4f\n", sel_offdiag))
