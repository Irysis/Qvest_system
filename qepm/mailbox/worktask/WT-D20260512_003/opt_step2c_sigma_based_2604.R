#==============================================================================
# WT-D20260512_003 Optimizer Step 2c — Σ-based methods cross-section 2026-04-01
#
# Σ-based methods (MVO/HRP/ERC/MaxDiv) at risk_package as-of date single-snapshot.
# 268m walk-forward은 alpha-rank-only 4 methods (Step 2b)이 cover.
# 본 Step은 risk_package factor_model_8F Σ로 final live weight cross-section 결정.
#
# Σ basis: factor_model_8F (estimation_window 2021-05~2026-04)
# Alpha basis: z_blend_composite at sig_date 2026-04-01 (regime=NORMAL, w_new=0.05)
# Universe: alpha top 20 by z_blend at 2026-04-01 (liquidity 5e7 filter retained)
#
# Methods:
#   1. MVO_lam1p0_psi0p3_2604 (confidence-aware, ub=0.20)
#   2. MVO_lam2p0_psi0p3_2604 (higher λ)
#   3. HRP_ward_2604 (risk_package Σ 기반 cor)
#   4. ERC_2604 (Σ-based equal risk contribution)
#   5. MaxDiv_2604 (Choueifaty-Coignard 2008 diversification ratio max)
#
# 본 Step은 cross-section single-snapshot. 268m schedule 산출은 Step 2b alpha-rank 결과.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(quadprog)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE_DIR)

cat("============================================================\n")
cat("[OPT-Step2c] Σ-based methods cross-section 2026-04-01\n")
cat("============================================================\n\n")

WT <- "WT-D20260512_003"
stage <- file.path("stage_artifacts", "WT_D20260512_003")
mailbox <- file.path("qepm/mailbox/worktask", WT)

# ─── Load Σ (factor_model_8F, 2026-04-01 as-of) ───────────────
cov_long <- as.data.table(read_parquet(file.path(stage, "covariance.parquet")))
cov_long_full <- rbind(cov_long, cov_long[i != j, .(i = j, j = i, sigma_ij, estimator)])
cov_long_full <- unique(cov_long_full, by = c("i", "j"))
Sigma_full <- dcast(cov_long_full, i ~ j, value.var = "sigma_ij", fill = 0)
ix_rn <- Sigma_full$i
Sigma_full <- as.matrix(Sigma_full[, -1])
rownames(Sigma_full) <- ix_rn
risk_universe <- sort(unique(cov_long$i))
Sigma_full <- Sigma_full[risk_universe, risk_universe]
cat(sprintf("Sigma loaded: %d × %d | cond=%.2f\n",
            nrow(Sigma_full), ncol(Sigma_full), kappa(Sigma_full)))

emat <- as.data.table(read_parquet(file.path(stage, "exposure_matrix.parquet")))
setkey(emat, Ticker)

# ─── Load alpha @ 2026-04-01 ────────────────────────────────────
ae <- readRDS(file.path(stage, "alpha_emission.rds"))
asc <- ae$alpha_scores[!is.na(z_blend_composite)]
as_of <- as.Date("2026-04-01")
panel_t <- asc[Date == as_of]
cat(sprintf("alpha panel @ 2026-04-01: %d tickers\n", nrow(panel_t)))

# Liquidity filter
raw <- as.data.table(read_parquet(".cache/rawdata.parquet",
                                   col_select = c("Date", "Ticker", "Close", "Vol")))
raw[, TradingAmt := Close * Vol]
LIQ_THRESHOLD <- 5e7
liq_data <- raw[Date >= (as_of - 30L) & Date < as_of,
                 .(AvgTA = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
liquid_tk <- liq_data[AvgTA >= LIQ_THRESHOLD, Ticker]

# Top 20 by z_blend (post liquidity filter, only tickers in risk universe)
panel_t <- panel_t[Ticker %in% liquid_tk & Ticker %in% risk_universe]
setorder(panel_t, -z_blend_composite)
top20 <- panel_t[seq_len(min(20L, .N))]
cat(sprintf("Top 20 alpha by z_blend (post liquid+risk filter): %d tickers\n",
            nrow(top20)))
print(top20[, .(Ticker, z_blend = round(z_blend_composite, 4),
                 score_eff = round(score_eff, 4),
                 R05 = round(R05_Tail_Risk_Z, 4),
                 regime = regime_state)])

alpha_t <- top20$z_blend_composite
names(alpha_t) <- top20$Ticker
confidence_t <- top20$confidence
names(confidence_t) <- top20$Ticker

# Σ sub-matrix
Sigma_sub <- Sigma_full[names(alpha_t), names(alpha_t)]
cat(sprintf("Σ_sub: %d × %d | min(diag(σ²))=%.6f | cond=%.2f\n",
            nrow(Sigma_sub), ncol(Sigma_sub),
            min(diag(Sigma_sub)), kappa(Sigma_sub)))

# ─── Helpers ────────────────────────────────────────────────────
UB <- 0.20; LB <- 0.0; TARGET_SUM <- 1.0

normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1) {
  w[is.na(w)] <- 0
  w[w < lb] <- lb
  if (sum(w) == 0) {
    w <- rep(target_sum / length(w), length(w))
    return(w)
  }
  w <- w / sum(w) * target_sum
  iter <- 0
  while (any(w > ub + 1e-12) && sum(w) > 0 && iter < 100) {
    excess_idx <- which(w > ub)
    excess <- sum(w[excess_idx]) - length(excess_idx) * ub
    w[excess_idx] <- ub
    free <- setdiff(seq_along(w), excess_idx)
    if (length(free) == 0) break
    if (sum(w[free]) == 0) w[free] <- excess / length(free)
    else w[free] <- w[free] + excess * (w[free] / sum(w[free]))
    w <- w / sum(w) * target_sum
    iter <- iter + 1
  }
  w
}

mvo_solve <- function(alpha_t, Sigma_sub, lambda = 2.0, psi = 0.3,
                       confidence = NULL, lb = 0, ub = 0.20, target_sum = 1) {
  D <- length(alpha_t)
  if (is.null(confidence)) confidence <- rep(1.0, D)
  fu_diag <- psi * (1 - confidence)^2
  Dmat <- lambda * Sigma_sub + diag(2 * fu_diag)
  diag(Dmat) <- diag(Dmat) + 1e-6
  dvec <- as.vector(alpha_t)
  Amat <- cbind(rep(1, D), diag(D), -diag(D))
  bvec <- c(target_sum, rep(lb, D), rep(-ub, D))
  res <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1),
                  error = function(e) NULL)
  if (is.null(res)) return(normalize_long_only(rep(1/D, D), lb=lb, ub=ub, target_sum=target_sum))
  w <- res$solution
  names(w) <- names(alpha_t)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = target_sum)
}

hrp_ward <- function(Sigma_sub, lb = 0, ub = 0.20) {
  cor_s <- cov2cor(Sigma_sub)
  cor_s <- pmin(pmax(cor_s, -0.999), 0.999)
  d <- 0.5 * (1 - cor_s); d[d < 0] <- 0; diag(d) <- 0
  dist_mat <- as.dist(sqrt(d))
  hc <- hclust(dist_mat, method = "ward.D2")
  ord <- hc$order
  common <- rownames(Sigma_sub)[ord]

  rb <- function(idx, w_alloc = 1) {
    if (length(idx) == 1L) return(setNames(w_alloc, idx))
    h <- ceiling(length(idx) / 2)
    L <- idx[1:h]; R <- idx[(h+1):length(idx)]
    vL <- sum(diag(Sigma_sub[L, L, drop=FALSE]))
    vR <- sum(diag(Sigma_sub[R, R, drop=FALSE]))
    aL <- vR / (vL + vR + 1e-12)
    aR <- 1 - aL
    c(rb(L, w_alloc * aL), rb(R, w_alloc * aR))
  }
  w <- rb(common)
  w_full <- setNames(rep(0, nrow(Sigma_sub)), rownames(Sigma_sub))
  w_full[names(w)] <- w
  if (sum(w_full) > 0) w_full <- w_full / sum(w_full)
  normalize_long_only(w_full, lb = lb, ub = ub, target_sum = 1)
}

erc_solve <- function(Sigma_sub, lb = 0, ub = 0.20, target_sum = 1,
                       n_iter = 200, tol = 1e-7) {
  D <- nrow(Sigma_sub)
  w <- rep(target_sum/D, D)
  names(w) <- rownames(Sigma_sub)
  for (k in seq_len(n_iter)) {
    mrc <- as.vector(Sigma_sub %*% w)
    rc <- w * mrc
    target_rc <- mean(rc)
    grad <- mrc - target_rc / pmax(w, 1e-8)
    w_new <- w - 0.003 * grad
    w_new <- pmax(w_new, 1e-8)
    w_new <- w_new / sum(w_new) * target_sum
    if (max(abs(w_new - w)) < tol) break
    w <- w_new
  }
  normalize_long_only(w, lb = lb, ub = ub, target_sum = target_sum)
}

maxdiv_solve <- function(Sigma_sub, lb = 0, ub = 0.20, target_sum = 1) {
  # Choueifaty-Coignard 2008: maximize diversification ratio
  # DR = (w' σ) / sqrt(w' Σ w)
  # Approximated via QP: max w'σ - λ w'Σw with high λ; or w ∝ Σ^-1 σ (long-only proj)
  vol <- sqrt(diag(Sigma_sub))
  D <- length(vol)
  # QP form: min (1/2) w'(λΣ)w - σ'w  subject to Σw=1, 0 ≤ w ≤ ub
  lambda_md <- 5.0
  Dmat <- lambda_md * Sigma_sub
  diag(Dmat) <- diag(Dmat) + 1e-6
  dvec <- as.vector(vol)
  Amat <- cbind(rep(1, D), diag(D), -diag(D))
  bvec <- c(target_sum, rep(lb, D), rep(-ub, D))
  res <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1),
                  error = function(e) NULL)
  if (is.null(res)) {
    # Fallback: w ∝ vol / Σ.diag (volatility-tilt)
    w <- vol / sum(vol) * target_sum
    names(w) <- rownames(Sigma_sub)
    return(normalize_long_only(w, lb = lb, ub = ub, target_sum = target_sum))
  }
  w <- res$solution
  w[w < 0] <- 0
  names(w) <- rownames(Sigma_sub)
  if (sum(w) > 0) w <- w / sum(w) * target_sum
  normalize_long_only(w, lb = lb, ub = ub, target_sum = target_sum)
}

# ─── 2026-04 single-snapshot 6 method comparison ───────────────
methods_2604 <- list(
  Iter31_LinearTilt_2604 = function() {
    # Iter31 linear_tilt λ=1.5 + TOphi=3 (w_prev=NULL since single-snap)
    N <- length(alpha_t)
    r <- rank(alpha_t, ties.method = "average")
    centered <- (r - mean(r)) / (N - 1)
    w_raw <- pmax(1 + 1.5 * 2 * centered, 1e-6)
    w <- w_raw / sum(w_raw)
    names(w) <- names(alpha_t)
    normalize_long_only(w, lb = LB, ub = UB, target_sum = 1)
  },
  MVO_lam1_psi0p3_2604 = function() {
    mvo_solve(alpha_t, Sigma_sub, lambda = 1.0, psi = 0.3,
              confidence = confidence_t, lb = LB, ub = UB)
  },
  MVO_lam2_psi0p3_2604 = function() {
    mvo_solve(alpha_t, Sigma_sub, lambda = 2.0, psi = 0.3,
              confidence = confidence_t, lb = LB, ub = UB)
  },
  HRP_ward_2604 = function() {
    w <- hrp_ward(Sigma_sub, lb = LB, ub = UB)
    w[names(alpha_t)]
  },
  ERC_2604 = function() {
    w <- erc_solve(Sigma_sub, lb = LB, ub = UB)
    w[names(alpha_t)]
  },
  MaxDiv_2604 = function() {
    w <- maxdiv_solve(Sigma_sub, lb = LB, ub = UB)
    w[names(alpha_t)]
  }
)

# Run
weights_2604 <- list()
for (m in names(methods_2604)) {
  cat(sprintf("\n[%s]\n", m))
  w <- methods_2604[[m]]()
  weights_2604[[m]] <- w
  cat(sprintf("  Σw=%.6f | max(w)=%.4f | min(w)=%.4f | n_active=%d\n",
              sum(w), max(w), min(w[w>0]), sum(w > 1e-4)))

  # Portfolio risk
  port_var_m <- as.numeric(t(w) %*% Sigma_sub %*% w)
  port_vol_ann <- sqrt(port_var_m * 12)
  ex_ret_z <- sum(w * alpha_t)
  # B' w factor loading
  B_sub <- as.matrix(emat[Ticker %in% names(w),
                            .(RM_KR, F_SIZE, F_VAL, F_MOM, F_QMJ, F_BAB, F_LIQ, F_TAIL)])
  # Re-order B_sub to match w
  B_sub <- as.matrix(emat[Ticker %in% names(w)][match(names(w), Ticker),
                            .(RM_KR, F_SIZE, F_VAL, F_MOM, F_QMJ, F_BAB, F_LIQ, F_TAIL)])
  factor_loading <- as.numeric(t(B_sub) %*% w)
  names(factor_loading) <- c("RM_KR", "F_SIZE", "F_VAL", "F_MOM", "F_QMJ", "F_BAB", "F_LIQ", "F_TAIL")
  hhi <- sum(w^2)
  cat(sprintf("  port_vol_ann=%.4f | ex_ret_z=%.4f | HHI=%.4f | F_QMJ=%.4f | F_TAIL=%.4f\n",
              port_vol_ann, ex_ret_z, hhi, factor_loading["F_QMJ"], factor_loading["F_TAIL"]))
}

# ─── Build comparison DT ────────────────────────────────────────
build_row <- function(m, w) {
  port_var_m <- as.numeric(t(w) %*% Sigma_sub %*% w)
  port_vol_ann <- sqrt(port_var_m * 12)
  ex_ret_z <- sum(w * alpha_t)
  B_sub <- as.matrix(emat[Ticker %in% names(w)][match(names(w), Ticker),
                            .(RM_KR, F_SIZE, F_VAL, F_MOM, F_QMJ, F_BAB, F_LIQ, F_TAIL)])
  fl <- as.numeric(t(B_sub) %*% w)
  hhi <- sum(w^2)
  data.table(
    method = m,
    sum_w = sum(w),
    max_w = max(w),
    min_w_active = if (sum(w > 1e-4) > 0) min(w[w > 1e-4]) else 0,
    n_active = sum(w > 1e-4),
    port_vol_ann = port_vol_ann,
    ex_ret_z = ex_ret_z,
    hhi = hhi,
    RM_KR = fl[1], F_SIZE = fl[2], F_VAL = fl[3], F_MOM = fl[4],
    F_QMJ = fl[5], F_BAB = fl[6], F_LIQ = fl[7], F_TAIL = fl[8]
  )
}

comparison <- rbindlist(lapply(names(weights_2604),
                                function(m) build_row(m, weights_2604[[m]])))
cat("\n[Single-snapshot 2026-04-01 cross-section comparison]\n")
print(comparison[, .(method,
                     sum_w = round(sum_w, 4),
                     max_w = round(max_w, 4),
                     n_active,
                     port_vol_ann = round(port_vol_ann, 4),
                     ex_ret_z = round(ex_ret_z, 4),
                     hhi = round(hhi, 4),
                     F_QMJ = round(F_QMJ, 3),
                     F_TAIL = round(F_TAIL, 3))])

# ─── Save ───────────────────────────────────────────────────────
fwrite(comparison, file.path(stage, "opt_sigma_based_2604_comparison.csv"))
saveRDS(weights_2604, file.path(stage, "opt_sigma_based_2604_weights.rds"))
cat(sprintf("\nSaved: %s + %s\n",
            file.path(stage, "opt_sigma_based_2604_comparison.csv"),
            file.path(stage, "opt_sigma_based_2604_weights.rds")))

cat("[OPT-Step2c] DONE\n")
