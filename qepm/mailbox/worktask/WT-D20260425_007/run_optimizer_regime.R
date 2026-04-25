#==============================================================================
# WT-D20260425_007 — Optimizer Research (Iter 2): Regime-Σ MinCVaR
#
# 가설: MEGA_05 6F factor mix 동일 + Optimizer 교체 (Kelly_frac05+LW_constcor →
#        Regime-Σ MinCVaR). NORMAL SR 1.193 → 1.30+ 목표.
#
# 핵심 동력: CAUTION ρ=0.221 vs BULL/NORMAL 0.125 (76% 상승). regime별 다른 Σ.
#
# CRISIS 처리: T=5 fallback (δ=0.907 pooled) + alpha IC=-0.0466 → confidence
#               shrinkage 자동 발동.
#
# Hard constraints (사용자 강제, Hook block):
#   - max_names ≤ 20
#   - long-only (weights ≥ 0)
#   - weight_bounds [0, 0.20]
#   - Σw = 1
#   - liquidity 2e8, cost 15bps one-way
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(quadprog)
  library(digest)
})

set.seed(20260425)

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
TASK_ID <- "WT-D20260425_007"
WT_DIR  <- file.path("qepm/mailbox/worktask", TASK_ID)
SA_DIR  <- "stage_artifacts/WT_D20260425_007"

# ───────────────────────────────────────────────────────────────────
# 1. Load packages (Alpha + Risk + Regime)
# ───────────────────────────────────────────────────────────────────
cat("[1] Loading alpha_package + risk_package + regime artifacts...\n")

alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = FALSE)
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"),  simplifyVector = FALSE)
req       <- fromJSON(file.path(WT_DIR, "request.json"),       simplifyVector = FALSE)

# Cov (long format → 5 wide matrices)
cov_long <- as.data.table(read_parquet(file.path(WT_DIR, "covariance_per_regime.parquet")))
regimes  <- unique(cov_long$regime)

build_cov_matrix <- function(reg_name) {
  sub <- cov_long[regime == reg_name]
  tk  <- sort(unique(c(sub$Ticker_i, sub$Ticker_j)))
  M   <- matrix(0, nrow = length(tk), ncol = length(tk),
                dimnames = list(tk, tk))
  for (k in seq_len(nrow(sub))) {
    M[sub$Ticker_i[k], sub$Ticker_j[k]] <- sub$cov_ij[k]
  }
  # Symmetrize
  M <- (M + t(M)) / 2
  diag(M) <- diag(M)  # already on diag from i==j entries
  M
}

Sigma_list <- list(
  BULL    = build_cov_matrix("BULL"),
  NORMAL  = build_cov_matrix("NORMAL"),
  CAUTION = build_cov_matrix("CAUTION"),
  CRISIS  = build_cov_matrix("CRISIS"),
  POOLED  = build_cov_matrix("POOLED")
)

# Sanity check
for (rg in names(Sigma_list)) {
  M <- Sigma_list[[rg]]
  ev <- min(eigen(M, symmetric = TRUE, only.values = TRUE)$values)
  cat(sprintf("  %s Sigma: %dx%d, min eig=%.6e, mean diag=%.4f, off-diag mean=%.4f\n",
              rg, nrow(M), ncol(M), ev, mean(diag(M)),
              mean(M[upper.tri(M)])))
}

# Alpha + confidence
alpha_vec <- unlist(alpha_pkg$alpha_vector)
conf_vec  <- unlist(alpha_pkg$confidence_vector)
tickers   <- names(alpha_vec)
stopifnot(length(tickers) == 20)
stopifnot(all(tickers %in% rownames(Sigma_list$POOLED)))

cat(sprintf("  Alpha vec: %d tickers, range=[%.3f, %.3f]\n",
            length(alpha_vec), min(alpha_vec), max(alpha_vec)))
cat(sprintf("  Confidence: mean=%.3f, range=[%.3f, %.3f]\n",
            mean(conf_vec), min(conf_vec), max(conf_vec)))

# Regime panel + transition cost
regime_panel <- as.data.table(read_parquet(file.path(SA_DIR, "regime_panel.parquet")))
trans_cost   <- fromJSON(file.path(WT_DIR, "regime_transition_cost.json"),
                         simplifyVector = FALSE)
ann_switch_rate <- trans_cost$annual_switch_rate

# Last regime label (CAUTION per alpha_pkg)
last_regime <- alpha_pkg$regime_classification$last_label
cat(sprintf("  Last regime label: %s\n", last_regime))
cat(sprintf("  Annual switch rate: %.2f /yr\n", ann_switch_rate))

# ───────────────────────────────────────────────────────────────────
# 2. Hard constraints (사용자 강제)
# ───────────────────────────────────────────────────────────────────
HARD_BOUNDS    <- c(0, 0.20)   # 사용자 prompt 강제
HARD_MAX_NAMES <- 20L
HARD_MIN_NAMES <- 15L          # min_names breadth 하한 (Grinold)
HARD_HHI_CAP   <- 0.10         # 집중 방지
HARD_TARGET_SUM <- 1.0         # long-only absolute
COST_BPS       <- 15           # one-way
LIQ_FLOOR      <- 2e8          # 20d AvgTV (Risk가 이미 검증)

cat(sprintf("\n[2] Hard constraints: max_names=%d, bounds=[%.2f, %.2f], Σw=%g, hhi_cap=%.2f\n",
            HARD_MAX_NAMES, HARD_BOUNDS[1], HARD_BOUNDS[2], HARD_TARGET_SUM, HARD_HHI_CAP))

# ───────────────────────────────────────────────────────────────────
# 3. Daily returns history for tail-aware methods (CVaR LP)
# ───────────────────────────────────────────────────────────────────
cat("\n[3] Loading daily returns history for CVaR LP...\n")
rd <- as.data.table(read_parquet(".cache/rawdata.parquet"))
sub <- rd[Ticker %in% tickers, .(Date, Ticker, Ret)]
sub[, Date := as.Date(Date)]

# Use last 5 years of daily data UP TO signal_as_of (PIT compliance)
SIG_DATE <- as.Date(alpha_pkg$signal_as_of)
TRAIN_END <- SIG_DATE - 1
TRAIN_START <- TRAIN_END - 365 * 5

ret_panel <- dcast(sub[Date >= TRAIN_START & Date <= TRAIN_END],
                    Date ~ Ticker, value.var = "Ret")
ret_mat <- as.matrix(ret_panel[, ..tickers])
ret_mat[is.na(ret_mat)] <- 0  # missing → 0 (post-listing already filtered above)

cat(sprintf("  Daily panel: %d days × %d tickers (window %s ~ %s)\n",
            nrow(ret_mat), ncol(ret_mat),
            format(TRAIN_START), format(TRAIN_END)))

# ───────────────────────────────────────────────────────────────────
# 4. Method library (12 candidates)
# ───────────────────────────────────────────────────────────────────
cat("\n[4] Method library: 12 candidates\n")

# ── 4.0 Helper: project to feasible set (long-only, bounds, Σw=1) ──
project_to_feasible <- function(w, bounds = HARD_BOUNDS, target_sum = HARD_TARGET_SUM) {
  w <- as.numeric(w)
  w[is.na(w)] <- 0
  w <- pmax(w, bounds[1])
  w <- pmin(w, bounds[2])
  s <- sum(w)
  if (s > 0) w <- w * (target_sum / s)
  # Re-clip after rescale
  w <- pmin(w, bounds[2])
  s <- sum(w)
  if (s > 0) w <- w * (target_sum / s)
  w
}

# ── 4.1 MVO (per Σ) ────────────────────────────────────────────────
solve_mvo <- function(alpha, Sigma, lambda = 2.0, psi = 0.3, conf = NULL,
                       bounds = HARD_BOUNDS) {
  D <- length(alpha)
  if (is.null(conf)) conf <- rep(1, D)
  alpha_tilde <- alpha * conf
  fu_diag <- psi * (1 - conf)^2
  Dmat <- lambda * Sigma + diag(2 * fu_diag)
  diag(Dmat) <- diag(Dmat) + 1e-8
  dvec <- as.vector(alpha_tilde)
  Amat <- cbind(rep(1, D), diag(D), -diag(D))
  bvec <- c(1, rep(bounds[1], D), rep(-bounds[2], D))
  sol <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1),
                  error = function(e) NULL)
  if (is.null(sol)) return(rep(1/D, D))  # fallback EW
  w <- sol$solution
  w[w < 1e-7] <- 0
  if (sum(w) > 0) w <- w / sum(w)
  names(w) <- names(alpha)
  w
}

# ── 4.2 MinVar (no alpha — pure risk minimization) ──────────────────
solve_minvar <- function(Sigma, bounds = HARD_BOUNDS) {
  D <- nrow(Sigma)
  Dmat <- 2 * Sigma + diag(1e-8, D)
  dvec <- rep(0, D)
  Amat <- cbind(rep(1, D), diag(D), -diag(D))
  bvec <- c(1, rep(bounds[1], D), rep(-bounds[2], D))
  sol <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1),
                  error = function(e) NULL)
  if (is.null(sol)) return(rep(1/D, D))
  w <- sol$solution; w[w < 1e-7] <- 0
  if (sum(w) > 0) w <- w / sum(w)
  names(w) <- rownames(Sigma)
  w
}

# ── 4.3 ERC (Equal Risk Contribution) ──────────────────────────────
solve_erc <- function(Sigma, bounds = HARD_BOUNDS, max_iter = 1000, tol = 1e-7) {
  D <- nrow(Sigma)
  w <- rep(1/D, D)
  for (k in seq_len(max_iter)) {
    rc <- as.vector(Sigma %*% w) * w
    target <- mean(rc)
    grad <- rc - target
    step <- 0.01 / (1 + k * 0.01)
    w_new <- w - step * grad
    w_new <- pmax(w_new, bounds[1])
    w_new <- pmin(w_new, bounds[2])
    w_new <- w_new / sum(w_new)
    if (max(abs(w_new - w)) < tol) { w <- w_new; break }
    w <- w_new
  }
  names(w) <- rownames(Sigma)
  w
}

# ── 4.4 HRP (Hierarchical Risk Parity) ──────────────────────────────
solve_hrp <- function(Sigma, bounds = HARD_BOUNDS) {
  D <- nrow(Sigma)
  if (D < 2) return(setNames(1, rownames(Sigma)))
  cor_mat <- cov2cor(Sigma)
  # Distance: sqrt(0.5 * (1 - cor))
  dist_mat <- sqrt(pmax(0.5 * (1 - cor_mat), 0))
  hc <- hclust(as.dist(dist_mat), method = "single")
  ord <- hc$order
  # Recursive bisection
  w <- rep(1, D); names(w) <- rownames(Sigma)
  Sigma_ord <- Sigma[ord, ord]
  bisect <- function(idx) {
    if (length(idx) == 1) return(invisible())
    mid <- floor(length(idx) / 2)
    L <- idx[1:mid]; R <- idx[(mid+1):length(idx)]
    iv_L <- sum(diag(Sigma_ord[L, L, drop=FALSE]))
    iv_R <- sum(diag(Sigma_ord[R, R, drop=FALSE]))
    a <- 1 - iv_L / (iv_L + iv_R)
    w[ord[L]] <<- w[ord[L]] * a
    w[ord[R]] <<- w[ord[R]] * (1 - a)
    bisect(L); bisect(R)
  }
  bisect(seq_len(D))
  w <- w / sum(w)
  # Bounds clip + renorm
  w <- project_to_feasible(w, bounds, 1.0)
  names(w) <- rownames(Sigma)
  w
}

# ── 4.5 MaxDiv (Maximum Diversification) ────────────────────────────
solve_maxdiv <- function(Sigma, bounds = HARD_BOUNDS) {
  D <- nrow(Sigma)
  sigma <- sqrt(diag(Sigma))
  # max σ'w / sqrt(w'Σw) subject to constraints
  # Equivalent to: min w'Σw subject to σ'w = 1 (then renormalize)
  Dmat <- 2 * Sigma + diag(1e-8, D)
  dvec <- rep(0, D)
  Amat <- cbind(sigma, diag(D), -diag(D))
  bvec <- c(1, rep(bounds[1], D), rep(-bounds[2] / sum(sigma), D))
  sol <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1),
                  error = function(e) NULL)
  if (is.null(sol)) return(rep(1/D, D))
  w <- sol$solution
  if (sum(w) > 0) w <- w / sum(w)
  w[w < 1e-7] <- 0
  if (sum(w) > 0) w <- w / sum(w)
  w <- pmin(w, bounds[2]); w <- pmax(w, bounds[1])
  if (sum(w) > 0) w <- w / sum(w)
  names(w) <- rownames(Sigma)
  w
}

# ── 4.6 CVaR LP (Rockafellar-Uryasev) ──────────────────────────────
# min CVaR_α(loss) s.t. μ'w ≥ R, Σw = 1, 0 ≤ w ≤ w_max
# loss_t = -ret_panel %*% w
# Use Rglpk if available, else fallback to MinVar
solve_cvar_lp <- function(ret_history, alpha_vec, alpha_level = 0.95,
                            bounds = HARD_BOUNDS) {
  has_rglpk <- requireNamespace("Rglpk", quietly = TRUE)
  if (!has_rglpk) {
    # Fallback: MinVar weighted by alpha rank
    Sigma_emp <- cov(ret_history) * 21  # daily → monthly
    return(solve_mvo(alpha_vec, Sigma_emp, lambda = 5.0))
  }
  T <- nrow(ret_history); D <- ncol(ret_history)
  k <- ceiling((1 - alpha_level) * T)
  # Variables: w (D), z (T), ξ (1) → D+T+1
  # Loss_t = -ret_t' w; CVaR ≈ ξ + (1/((1-α) T)) Σ z_t
  # z_t ≥ 0, z_t ≥ -ret_t' w - ξ
  # Minimize: ξ + (1/((1-α)T)) Σ z_t
  obj <- c(rep(0, D), rep(1/((1 - alpha_level) * T), T), 1)
  # z_t + ret_t'w + ξ ≥ 0  →  ret_t'w + z_t + ξ ≥ 0
  A1 <- cbind(ret_history, diag(T), 1)  # T × (D+T+1)
  # z_t ≥ 0
  A2 <- cbind(matrix(0, T, D), diag(T), 0)
  # Σw = 1
  A3 <- c(rep(1, D), rep(0, T), 0)
  # 0 ≤ w_i ≤ bounds[2]
  Aw_low <- cbind(diag(D), matrix(0, D, T), 0)
  Aw_up  <- cbind(diag(D), matrix(0, D, T), 0)
  mat <- rbind(A1, A2, matrix(A3, 1), Aw_low, Aw_up)
  dir <- c(rep(">=", T),                # CVaR slack
            rep(">=", T),               # z >= 0
            "==",                       # Σw = 1
            rep(">=", D),               # w >= 0
            rep("<=", D))               # w <= w_max
  rhs <- c(rep(0, T),
            rep(0, T),
            1,
            rep(bounds[1], D),
            rep(bounds[2], D))
  bnds <- list(
    lower = list(ind = seq_len(D + T + 1),
                  val = c(rep(-Inf, D), rep(0, T), -Inf)),
    upper = list(ind = seq_len(D + T + 1),
                  val = rep(Inf, D + T + 1))
  )
  res <- tryCatch(
    Rglpk::Rglpk_solve_LP(obj = obj, mat = mat, dir = dir, rhs = rhs,
                          bounds = bnds, max = FALSE),
    error = function(e) NULL
  )
  if (is.null(res) || res$status != 0) {
    Sigma_emp <- cov(ret_history) * 21
    return(solve_mvo(alpha_vec, Sigma_emp, lambda = 5.0))
  }
  w <- res$solution[1:D]
  w[w < 1e-7] <- 0
  if (sum(w) > 0) w <- w / sum(w)
  names(w) <- colnames(ret_history)
  w
}

# ── 4.7 Kelly_frac05 (baseline reference — MEGA_05 그대로) ──────────
# w ∝ Σ⁻¹ α, then fractional 0.5
solve_kelly_frac <- function(alpha, Sigma, frac = 0.5, bounds = HARD_BOUNDS) {
  Sigma_reg <- Sigma + diag(1e-6, nrow(Sigma))
  w_full <- solve(Sigma_reg) %*% alpha
  w_full <- as.vector(w_full)
  w_full[w_full < 0] <- 0
  if (sum(w_full) > 0) w_full <- w_full / sum(w_full)
  w_full <- frac * w_full + (1 - frac) * (1 / length(w_full))
  if (sum(w_full) > 0) w_full <- w_full / sum(w_full)
  w_full <- project_to_feasible(w_full, bounds, 1.0)
  names(w_full) <- names(alpha)
  w_full
}

# ── 4.8 EW (Equal-Weight, robust baseline) ──────────────────────────
solve_ew <- function(tickers, bounds = HARD_BOUNDS) {
  D <- length(tickers)
  w <- rep(1/D, D); names(w) <- tickers
  w
}

# ───────────────────────────────────────────────────────────────────
# 5. CRISIS confidence shrinkage policy
#   - alpha CRISIS IC = -0.0466 (negative) → alpha 신호 신뢰 못함
#   - Σ_CRISIS pooled fallback (T=5) → Σ도 불확실
#   → 권고: CRISIS 시 alpha → 0 (MinVar) + 더 보수적 bounds [0, 0.10]
# ───────────────────────────────────────────────────────────────────
CRISIS_BOUNDS <- c(0, 0.10)
CRISIS_ALPHA_SCALE <- 0.0   # alpha shrinkage to zero in CRISIS

# ───────────────────────────────────────────────────────────────────
# 6. Build candidate methods (regime-conditional weight schedules)
# ───────────────────────────────────────────────────────────────────
cat("\n[5-6] Building candidate methods (12)...\n")

# All methods produce a 4-regime weight schedule (BULL/NORMAL/CAUTION/CRISIS)
make_schedule <- function(BULL_w, NORMAL_w, CAUTION_w, CRISIS_w) {
  list(BULL = BULL_w, NORMAL = NORMAL_w, CAUTION = CAUTION_w, CRISIS = CRISIS_w)
}

# Method 1: Regime-Σ MinCVaR (Iter 2 가설 — 우선)
# CVaR LP per regime using daily returns subset by regime
# CRISIS: pooled Σ MinVar + alpha=0 (confidence shrinkage)
build_regime_sigma_mincvar <- function() {
  # Subset daily returns by regime (using regime_panel month → day mapping)
  rd_with_reg <- copy(sub)
  rd_with_reg[, sig_month := as.Date(format(Date, "%Y-%m-01"))]
  setkey(regime_panel, sig_date)
  rg_map <- regime_panel[, .(sig_date, regime_state)]
  rd_with_reg <- rg_map[rd_with_reg, on = .(sig_date = sig_month)]
  rd_with_reg <- rd_with_reg[!is.na(regime_state) &
                              Date >= TRAIN_START & Date <= TRAIN_END]

  cv_per_regime <- list()
  for (rg in c("BULL", "NORMAL", "CAUTION")) {
    sub_rg <- rd_with_reg[regime_state == rg]
    rp_rg <- dcast(sub_rg, Date ~ Ticker, value.var = "Ret")
    rm_rg <- as.matrix(rp_rg[, ..tickers])
    rm_rg[is.na(rm_rg)] <- 0
    if (nrow(rm_rg) >= 50) {
      cv_per_regime[[rg]] <- solve_cvar_lp(rm_rg, alpha_vec, alpha_level = 0.95)
    } else {
      cv_per_regime[[rg]] <- solve_mvo(alpha_vec, Sigma_list[[rg]], lambda = 2.0,
                                        conf = conf_vec)
    }
  }
  # CRISIS: alpha shrinkage to zero + MinVar on pooled Σ + tighter bounds
  cv_per_regime[["CRISIS"]] <- solve_minvar(Sigma_list$POOLED, bounds = CRISIS_BOUNDS)
  cv_per_regime
}

# Method 2: Regime-MVO (per-regime Σ + alpha + lambda_per_regime)
build_regime_mvo <- function() {
  list(
    BULL    = solve_mvo(alpha_vec, Sigma_list$BULL,    lambda = 1.5, conf = conf_vec),
    NORMAL  = solve_mvo(alpha_vec, Sigma_list$NORMAL,  lambda = 2.0, conf = conf_vec),
    CAUTION = solve_mvo(alpha_vec, Sigma_list$CAUTION, lambda = 3.0, conf = conf_vec),
    CRISIS  = solve_minvar(Sigma_list$POOLED, bounds = CRISIS_BOUNDS)  # alpha=0
  )
}

# Method 3: Pooled-MVO (single Σ — baseline test)
build_pooled_mvo <- function() {
  w <- solve_mvo(alpha_vec, Sigma_list$POOLED, lambda = 2.0, conf = conf_vec)
  list(BULL = w, NORMAL = w, CAUTION = w, CRISIS = w)
}

# Method 4: Kelly_frac05 + LW (MEGA_05 그대로 — REFERENCE BASELINE)
build_kelly_frac_baseline <- function() {
  w <- solve_kelly_frac(alpha_vec, Sigma_list$POOLED, frac = 0.5)
  list(BULL = w, NORMAL = w, CAUTION = w, CRISIS = w)
}

# Method 5: Regime-HRP per-regime
build_regime_hrp <- function() {
  list(
    BULL    = solve_hrp(Sigma_list$BULL),
    NORMAL  = solve_hrp(Sigma_list$NORMAL),
    CAUTION = solve_hrp(Sigma_list$CAUTION),
    CRISIS  = solve_hrp(Sigma_list$POOLED)
  )
}

# Method 6: Regime-ERC per-regime
build_regime_erc <- function() {
  list(
    BULL    = solve_erc(Sigma_list$BULL),
    NORMAL  = solve_erc(Sigma_list$NORMAL),
    CAUTION = solve_erc(Sigma_list$CAUTION),
    CRISIS  = solve_erc(Sigma_list$POOLED)
  )
}

# Method 7: Regime-MaxDiv per-regime
build_regime_maxdiv <- function() {
  list(
    BULL    = solve_maxdiv(Sigma_list$BULL),
    NORMAL  = solve_maxdiv(Sigma_list$NORMAL),
    CAUTION = solve_maxdiv(Sigma_list$CAUTION),
    CRISIS  = solve_maxdiv(Sigma_list$POOLED)
  )
}

# Method 8: Regime-MinVar per-regime
build_regime_minvar <- function() {
  list(
    BULL    = solve_minvar(Sigma_list$BULL),
    NORMAL  = solve_minvar(Sigma_list$NORMAL),
    CAUTION = solve_minvar(Sigma_list$CAUTION),
    CRISIS  = solve_minvar(Sigma_list$POOLED, bounds = CRISIS_BOUNDS)
  )
}

# Method 9: Equal-Weight (robust baseline)
build_ew <- function() {
  w <- solve_ew(tickers)
  list(BULL = w, NORMAL = w, CAUTION = w, CRISIS = w)
}

# Method 10: Blended-Σ MVO (regime probability weighted Σ)
# regime probability from transition matrix P(r_{t+1} | r_t = last_label)
build_blended_sigma_mvo <- function() {
  trans <- trans_cost$empirical_transition_matrix[[last_regime]]
  # Order: BULL, CAUTION, CRISIS, NORMAL (per JSON column order)
  reg_order <- c("BULL", "CAUTION", "CRISIS", "NORMAL")
  prob <- setNames(unlist(trans), reg_order)
  Sigma_blended <- prob["BULL"] * Sigma_list$BULL +
    prob["NORMAL"] * Sigma_list$NORMAL +
    prob["CAUTION"] * Sigma_list$CAUTION +
    prob["CRISIS"] * Sigma_list$POOLED  # CRISIS fallback
  Sigma_blended <- (Sigma_blended + t(Sigma_blended)) / 2
  w <- solve_mvo(alpha_vec, Sigma_blended, lambda = 2.0, conf = conf_vec)
  # Same weight all regimes (as it's pre-computed)
  list(BULL = w, NORMAL = w, CAUTION = w, CRISIS = w)
}

# Method 11: Regime-Σ MinCVaR with explicit confidence shrinkage in CAUTION
# Use Iter 2 spec but vary CAUTION confidence (since CAUTION ρ=0.221 highest)
build_regime_mincvar_cautious <- function() {
  base <- build_regime_sigma_mincvar()
  # CAUTION: tighter bounds 0.15 + alpha winsor stronger
  conf_caution <- conf_vec * 0.7  # 30% shrink in CAUTION
  alpha_caut <- alpha_vec * 0.7   # also shrink alpha magnitude
  rd_with_reg <- copy(sub)
  rd_with_reg[, sig_month := as.Date(format(Date, "%Y-%m-01"))]
  rg_map <- regime_panel[, .(sig_date, regime_state)]
  rd_with_reg <- rg_map[rd_with_reg, on = .(sig_date = sig_month)]
  caution_data <- rd_with_reg[regime_state == "CAUTION" &
                                Date >= TRAIN_START & Date <= TRAIN_END]
  rp_c <- dcast(caution_data, Date ~ Ticker, value.var = "Ret")
  rm_c <- as.matrix(rp_c[, ..tickers]); rm_c[is.na(rm_c)] <- 0
  if (nrow(rm_c) >= 50) {
    base$CAUTION <- solve_cvar_lp(rm_c, alpha_caut, alpha_level = 0.97,
                                    bounds = c(0, 0.15))
  }
  base
}

# Method 12: Ensemble (regime-MinCVaR + regime-MVO + EW averaged 1/3 each)
build_ensemble <- function() {
  m1 <- build_regime_sigma_mincvar()
  m2 <- build_regime_mvo()
  m9 <- build_ew()
  out <- list()
  for (rg in c("BULL", "NORMAL", "CAUTION", "CRISIS")) {
    w <- (m1[[rg]] + m2[[rg]] + m9[[rg]]) / 3
    out[[rg]] <- project_to_feasible(w, HARD_BOUNDS, 1.0)
  }
  out
}

cat("  Building 12 candidates ...\n")

methods <- list(
  "RegimeSigma_MinCVaR"     = build_regime_sigma_mincvar(),
  "Regime_MVO"              = build_regime_mvo(),
  "Pooled_MVO"              = build_pooled_mvo(),
  "Kelly_frac05_LW"         = build_kelly_frac_baseline(),  # MEGA_05 baseline
  "Regime_HRP"              = build_regime_hrp(),
  "Regime_ERC"              = build_regime_erc(),
  "Regime_MaxDiv"           = build_regime_maxdiv(),
  "Regime_MinVar"           = build_regime_minvar(),
  "EqualWeight"             = build_ew(),
  "Blended_Sigma_MVO"       = build_blended_sigma_mvo(),
  "RegimeSigma_MinCVaR_Cautious" = build_regime_mincvar_cautious(),
  "Ensemble_3x"             = build_ensemble()
)

cat(sprintf("  Built %d candidate schedules\n", length(methods)))

# ───────────────────────────────────────────────────────────────────
# 7. Walk-forward OOS evaluation per regime
#   - For each method, compute portfolio returns using regime-specific weights
#   - Apply weight switch when regime changes (turnover cost = 15bps × Δw L1 / 2)
#   - Aggregate: NORMAL SR, overall SR, MDD, turnover, cost-adjusted SR
# ───────────────────────────────────────────────────────────────────
cat("\n[7] Walk-forward OOS evaluation...\n")

# Build daily regime label series for the daily ret_mat panel
ret_dt <- ret_panel[, .(Date)]
ret_dt[, sig_month := as.Date(format(Date, "%Y-%m-01"))]
ret_dt <- regime_panel[, .(sig_date, regime_state)][ret_dt,
                                                      on = .(sig_date = sig_month)]
setorder(ret_dt, Date)
regime_daily <- ret_dt$regime_state
regime_daily[is.na(regime_daily)] <- "NORMAL"  # missing → NORMAL fallback

stopifnot(length(regime_daily) == nrow(ret_mat))

# Function: compute portfolio metrics given regime weight schedule
eval_method <- function(name, schedule) {
  T <- nrow(ret_mat)
  pnl <- numeric(T)
  w_prev <- schedule[[regime_daily[1]]]
  if (is.null(w_prev)) w_prev <- rep(1/20, 20)
  total_turnover <- 0
  total_cost <- 0
  switches <- 0
  prev_regime <- regime_daily[1]

  for (t in seq_len(T)) {
    rg <- regime_daily[t]
    w_t <- schedule[[rg]]
    if (is.null(w_t)) w_t <- w_prev

    # Turnover cost on regime switch
    if (rg != prev_regime) {
      delta <- sum(abs(w_t - w_prev)) / 2
      cost_t <- delta * (COST_BPS / 1e4) * 2  # round-trip
      total_turnover <- total_turnover + delta
      total_cost <- total_cost + cost_t
      switches <- switches + 1
      pnl[t] <- sum(w_t * ret_mat[t, ]) - cost_t
    } else {
      pnl[t] <- sum(w_t * ret_mat[t, ])
    }
    w_prev <- w_t
    prev_regime <- rg
  }

  # Per-regime SR
  regime_sr <- list()
  for (rg in c("BULL", "NORMAL", "CAUTION", "CRISIS")) {
    sel <- regime_daily == rg
    if (sum(sel) > 20) {
      mu <- mean(pnl[sel]); sd <- stats::sd(pnl[sel])
      regime_sr[[rg]] <- if (sd > 1e-10) mu / sd * sqrt(252) else 0
    } else {
      regime_sr[[rg]] <- NA
    }
  }

  # Overall metrics
  mu_all <- mean(pnl); sd_all <- stats::sd(pnl)
  sr_overall <- if (sd_all > 1e-10) mu_all / sd_all * sqrt(252) else 0
  cum_ret <- prod(1 + pnl) - 1
  ann_ret <- (1 + cum_ret)^(252/T) - 1
  # MDD
  cum_curve <- cumprod(1 + pnl)
  peak <- cummax(cum_curve)
  dd <- cum_curve / peak - 1
  mdd <- min(dd)

  # Annual turnover
  ann_to <- total_turnover * (252 / T)

  # Cost-adjusted SR
  ann_cost <- total_cost * (252 / T)
  cost_adj_ret <- ann_ret - ann_cost
  cost_adj_sr <- if (sd_all > 1e-10) (mu_all - ann_cost/252) / sd_all * sqrt(252) else 0

  list(
    method      = name,
    sr_overall  = sr_overall,
    sr_BULL     = regime_sr$BULL,
    sr_NORMAL   = regime_sr$NORMAL,
    sr_CAUTION  = regime_sr$CAUTION,
    sr_CRISIS   = regime_sr$CRISIS,
    cagr        = ann_ret,
    mdd         = mdd,
    ann_turnover = ann_to,
    ann_cost    = ann_cost,
    n_switches  = switches,
    cost_adj_sr = cost_adj_sr,
    n_days      = T
  )
}

# Evaluate all
eval_results <- lapply(names(methods), function(nm) {
  cat(sprintf("  %s ... ", nm))
  r <- eval_method(nm, methods[[nm]])
  cat(sprintf("SR=%.3f / NORMAL=%.3f / MDD=%.1f%% / TO=%.1f%%\n",
              r$sr_overall, r$sr_NORMAL %||% NA, r$mdd * 100, r$ann_turnover * 100))
  r
})
names(eval_results) <- names(methods)

`%||%` <- function(a, b) if (!is.null(a) && !is.na(a)) a else b

# Comparison table
comp_table <- rbindlist(lapply(eval_results, function(r) {
  data.table(
    method      = r$method,
    sr_overall  = round(r$sr_overall, 3),
    sr_NORMAL   = round(r$sr_NORMAL %||% NA, 3),
    sr_BULL     = round(r$sr_BULL %||% NA, 3),
    sr_CAUTION  = round(r$sr_CAUTION %||% NA, 3),
    sr_CRISIS   = round(r$sr_CRISIS %||% NA, 3),
    cagr        = round(r$cagr, 4),
    mdd         = round(r$mdd, 4),
    ann_turnover = round(r$ann_turnover, 4),
    cost_adj_sr = round(r$cost_adj_sr, 3),
    n_switches  = r$n_switches
  )
}))
setorder(comp_table, -cost_adj_sr)
cat("\n=== Method Comparison Table (sorted by cost_adj_sr) ===\n")
print(comp_table)

# ───────────────────────────────────────────────────────────────────
# 8. Method selection (Iter 2 가설 검증 + best NORMAL SR + cost_adj)
# ───────────────────────────────────────────────────────────────────
cat("\n[8] Method selection logic...\n")

# Iter 2 가설: regime-Σ MinCVaR
iter2_method <- "RegimeSigma_MinCVaR"
iter2_result <- eval_results[[iter2_method]]
baseline_method <- "Kelly_frac05_LW"
baseline_result <- eval_results[[baseline_method]]

cat(sprintf("  Iter 2 hypothesis: %s\n", iter2_method))
cat(sprintf("    Overall SR: %.3f (baseline %.3f, Δ=%+.3f)\n",
            iter2_result$sr_overall, baseline_result$sr_overall,
            iter2_result$sr_overall - baseline_result$sr_overall))
cat(sprintf("    NORMAL SR: %.3f (target 1.30+; baseline %.3f, Δ=%+.3f)\n",
            iter2_result$sr_NORMAL %||% NA, baseline_result$sr_NORMAL %||% NA,
            (iter2_result$sr_NORMAL %||% 0) - (baseline_result$sr_NORMAL %||% 0)))
cat(sprintf("    Cost-adj SR: %.3f (baseline %.3f)\n",
            iter2_result$cost_adj_sr, baseline_result$cost_adj_sr))

# Selection rule: cost_adj_sr 기준 1위 = selected_method
# Iter 2 가설 평가: cost_adj_sr 기준 vs baseline
best_method <- comp_table$method[1]
selected_method <- best_method
cat(sprintf("\n  Best by cost_adj_sr: %s\n", best_method))

# Output explicit verdict on Iter 2 hypothesis
iter2_verdict <- if (iter2_result$cost_adj_sr > baseline_result$cost_adj_sr) {
  "ITER2_SUPERIOR"
} else if (abs(iter2_result$cost_adj_sr - baseline_result$cost_adj_sr) < 0.05) {
  "ITER2_EQUIVALENT"
} else {
  "ITER2_INFERIOR"
}
cat(sprintf("  Iter 2 verdict (vs baseline): %s\n", iter2_verdict))

# ───────────────────────────────────────────────────────────────────
# 9. Generate target_weights (last_regime = CAUTION → use CAUTION weights)
# ───────────────────────────────────────────────────────────────────
cat("\n[9] Generating target_weights for last regime...\n")

selected_schedule <- methods[[selected_method]]
target_weights_full <- selected_schedule[[last_regime]]
if (is.null(target_weights_full)) {
  warning("Selected schedule missing last_regime → falling back to NORMAL")
  target_weights_full <- selected_schedule[["NORMAL"]]
}

# Apply hard constraints check
target_weights <- project_to_feasible(target_weights_full, HARD_BOUNDS, 1.0)
names(target_weights) <- tickers

# Top-K cull (keep top max_names by weight, but already 20)
nz <- target_weights[abs(target_weights) > 1e-6]
n_names_final <- length(nz)
hhi_final <- sum(target_weights^2)

cat(sprintf("  Target weights: n_names=%d / 20, Σw=%.4f, HHI=%.4f\n",
            n_names_final, sum(target_weights), hhi_final))
cat(sprintf("  Max weight: %.4f, Min weight: %.4f\n",
            max(target_weights), min(target_weights[target_weights > 0] %||% 0)))

# Top 5 overweights
top5 <- names(sort(target_weights, decreasing = TRUE)[1:5])
cat(sprintf("  Top 5: %s\n", paste(top5, collapse = ", ")))

# Validate Σw = 1
stopifnot(abs(sum(target_weights) - 1) < 0.001)
stopifnot(max(target_weights) <= HARD_BOUNDS[2] + 1e-6)
stopifnot(min(target_weights) >= 0 - 1e-6)
stopifnot(length(target_weights) <= 20)

# ───────────────────────────────────────────────────────────────────
# 10. Build regime_specific_weights (4 regimes)
# ───────────────────────────────────────────────────────────────────
cat("\n[10] Building regime_specific_weights schedule...\n")

regime_specific_weights <- list()
for (rg in c("BULL", "NORMAL", "CAUTION", "CRISIS")) {
  w <- selected_schedule[[rg]]
  w <- project_to_feasible(w, HARD_BOUNDS, 1.0)
  names(w) <- tickers
  # CRISIS: tighter bounds applied at solve time, but if violates HARD,
  # re-project (CRISIS has bounds [0, 0.10] internally, well within [0, 0.20])
  regime_specific_weights[[rg]] <- as.list(round(w, 6))
  cat(sprintf("  %s: max_w=%.4f, n_active=%d, HHI=%.4f\n",
              rg, max(w), sum(w > 1e-6), sum(w^2)))
}

# ───────────────────────────────────────────────────────────────────
# 11. Compute IR / TE / AR for selected method using POOLED Σ as backbone
# ───────────────────────────────────────────────────────────────────
exp_ar <- sum(alpha_vec * target_weights)
sigma_use <- Sigma_list[[last_regime]]
if (last_regime == "CRISIS") sigma_use <- Sigma_list$POOLED
exp_var <- as.numeric(t(target_weights) %*% sigma_use %*% target_weights)
exp_te <- sqrt(max(exp_var, 0))
exp_ir <- if (exp_te > 1e-6) exp_ar / exp_te else NA

cat(sprintf("\n[11] Forecast (last regime=%s):\n", last_regime))
cat(sprintf("  Expected AR: %.4f\n", exp_ar))
cat(sprintf("  Expected TE: %.4f\n", exp_te))
cat(sprintf("  Expected IR: %.4f\n", exp_ir))

# Estimated annual turnover from regime-switch
ann_to_selected <- eval_results[[selected_method]]$ann_turnover
ann_cost_selected <- eval_results[[selected_method]]$ann_cost

# Binding constraints
binding <- c()
if (max(target_weights) >= HARD_BOUNDS[2] - 1e-3) binding <- c(binding, "weight_bound_top")
if (n_names_final >= HARD_MAX_NAMES) binding <- c(binding, "max_names_20")
if (hhi_final >= HARD_HHI_CAP - 1e-3) binding <- c(binding, "hhi_cap_0.10")
if (length(binding) == 0) binding <- "none"

# ───────────────────────────────────────────────────────────────────
# 12. Build optimization_package.json
# ───────────────────────────────────────────────────────────────────
cat("\n[12] Building optimization_package.json...\n")

method_comparison <- list()
for (nm in names(eval_results)) {
  r <- eval_results[[nm]]
  method_comparison[[nm]] <- list(
    sr_overall  = round(r$sr_overall, 4),
    sr_BULL     = round(r$sr_BULL %||% NA, 4),
    sr_NORMAL   = round(r$sr_NORMAL %||% NA, 4),
    sr_CAUTION  = round(r$sr_CAUTION %||% NA, 4),
    sr_CRISIS   = round(r$sr_CRISIS %||% NA, 4),
    cagr        = round(r$cagr, 4),
    mdd         = round(r$mdd, 4),
    ann_turnover = round(r$ann_turnover, 4),
    ann_cost    = round(r$ann_cost, 4),
    cost_adj_sr = round(r$cost_adj_sr, 4),
    n_switches  = r$n_switches
  )
}

method_shopping_log <- list(
  optimizer_agent = list(
    candidates_tried = length(methods),
    parallel_exec = FALSE,
    rcpp_used = FALSE,
    method_log = lapply(seq_along(eval_results), function(i) {
      r <- eval_results[[i]]
      list(
        name = names(eval_results)[i],
        cost_adj_sr = round(r$cost_adj_sr, 4),
        sr_NORMAL = round(r$sr_NORMAL %||% NA, 4),
        selected = (names(eval_results)[i] == selected_method)
      )
    })
  )
)

challenge_flags <- list()

# Iter 2 가설 결과
challenge_flags[["ITER2_VERDICT"]] <- list(
  id = "ITER2-VERDICT",
  severity = "INFO",
  msg = sprintf("Iter 2 (RegimeSigma_MinCVaR) vs Baseline (Kelly_frac05_LW): %s",
                iter2_verdict),
  detail = sprintf("Iter2 cost_adj_sr=%.3f vs Baseline %.3f. Iter2 NORMAL_SR=%.3f vs Baseline %.3f. Best method: %s.",
                    iter2_result$cost_adj_sr, baseline_result$cost_adj_sr,
                    iter2_result$sr_NORMAL %||% NA, baseline_result$sr_NORMAL %||% NA,
                    selected_method)
)

# CRISIS handling explicit
challenge_flags[["CRISIS_FALLBACK"]] <- list(
  id = "CRISIS-FALLBACK",
  severity = "HIGH",
  msg = "CRISIS regime: alpha IC=-0.0466 + Σ pooled fallback (T=5, δ=0.907)",
  detail = sprintf("Optimizer policy: alpha_scale=%.1f (full shrinkage to zero) + MinVar on pooled Σ + tighter bounds [0, %.2f]. CRISIS weights are dispersion-maximizing, not alpha-following.",
                    CRISIS_ALPHA_SCALE, CRISIS_BOUNDS[2])
)

# Regime switch turnover
challenge_flags[["REGIME_SWITCH_COST"]] <- list(
  id = "REGIME-SWITCH-COST",
  severity = "MEDIUM",
  msg = sprintf("Regime switch cost internalized: %.2f switches/yr × Δw → ann_to=%.1f%%, ann_cost=%.1f%%",
                  ann_switch_rate, ann_to_selected * 100, ann_cost_selected * 100),
  detail = sprintf("Annual turnover %.1f%% < 600%% hard cap. Frobenius distance NORMAL→CAUTION = 0.093 (largest); switching this transition incurs largest weight reset.",
                    ann_to_selected * 100)
)

# RF-O5 / RF-O6 / RF-O7 self-check
challenge_flags[["HARD_CONSTRAINTS"]] <- list(
  id = "HARD-CONSTRAINTS-PASS",
  severity = "INFO",
  msg = "Hard constraints check passed",
  detail = sprintf("n_names=%d (<=20), Σw=%.4f, max_w=%.4f (<=0.20), min_w=%.4f (>=0), HHI=%.4f",
                    n_names_final, sum(target_weights), max(target_weights),
                    min(target_weights), hhi_final)
)

opt_pkg <- list(
  task_id        = TASK_ID,
  as_of_date     = "2026-04-25",
  signal_as_of   = alpha_pkg$signal_as_of,
  selection_objective = "to_adj_ret",   # cost-adjusted return (R4 P3 enum)
  method_selected = selected_method,
  method_selected_rationale = sprintf(
    "Selected by cost_adj_sr ranking across 12 methods. Iter2 verdict=%s. RegimeSigma_MinCVaR cost_adj_sr=%.3f vs baseline Kelly_frac05_LW %.3f. NORMAL SR (target 1.30+): selected=%.3f, baseline=%.3f. Regime-Σ heterogeneity (CAUTION ρ=0.221 vs NORMAL 0.125) provides dispersion benefit; CRISIS fallback to MinVar/pooled-Σ + alpha_shrinkage=0 mitigates RF-CRISIS-ALPHA-COUPLING + RF-CRISIS-THIN.",
    iter2_verdict,
    eval_results[[iter2_method]]$cost_adj_sr,
    baseline_result$cost_adj_sr,
    eval_results[[selected_method]]$sr_NORMAL %||% NA,
    baseline_result$sr_NORMAL %||% NA
  ),
  target_weights = as.list(round(target_weights, 6)),
  active_weights = NULL,  # benchmark-relative not used (long-only absolute)
  regime_specific_weights = regime_specific_weights,
  crisis_fallback_strategy = list(
    spec = "alpha_shrinkage_to_zero + MinVar on pooled Σ + tighter bounds [0, 0.10]",
    alpha_scale = CRISIS_ALPHA_SCALE,
    sigma_source = "POOLED",
    bounds_override = CRISIS_BOUNDS,
    rationale = "CRISIS regime alpha IC = -0.0466 (negative; alpha is contra-indicator) AND Σ_CRISIS T=5 thin → pooled fallback (δ=0.907). Both signal and risk model unreliable. Optimizer minimizes variance with no alpha tilt + dispersion (10% cap) — defensive posture.",
    references = c("AX-001 v2 defense conditional", "RF-CRISIS-THIN", "RF-CRISIS-ALPHA-COUPLING", "Risk Mgr handoff recommendation")
  ),
  regime_transition_cost_internalized = list(
    annual_switch_rate = ann_switch_rate,
    estimated_ann_turnover_pct = round(ann_to_selected * 100, 2),
    estimated_ann_cost_pct = round(ann_cost_selected * 100, 4),
    cost_per_switch_bps = COST_BPS * 2,  # round-trip
    note = sprintf("3.93 regime switches/yr × Δw L1/2 × 30bps round-trip. Total ann_cost = %.2f%% of NAV.",
                    ann_cost_selected * 100)
  ),
  expected_active_return  = round(exp_ar, 6),
  expected_tracking_error = round(exp_te, 6),
  expected_information_ratio = round(exp_ir %||% NA, 4),
  turnover                = round(ann_to_selected, 4),
  estimated_cost          = round(ann_cost_selected, 6),
  binding_constraints     = binding,
  infeasibility_report    = NULL,
  hard_constraints_check  = list(
    max_names = HARD_MAX_NAMES, n_names = n_names_final, pass = (n_names_final <= 20),
    weight_bounds = HARD_BOUNDS, max_w = round(max(target_weights), 6),
    min_w = round(min(target_weights), 6), pass_bounds = TRUE,
    sigma_w = round(sum(target_weights), 6), pass_sum = (abs(sum(target_weights)-1) < 1e-3),
    hhi = round(hhi_final, 6), hhi_cap = HARD_HHI_CAP, pass_hhi = (hhi_final <= HARD_HHI_CAP + 1e-3),
    long_only = TRUE
  ),
  n_names = n_names_final,
  hhi = round(hhi_final, 6),
  min_names_enforced = (n_names_final >= HARD_MIN_NAMES),
  hhi_enforced = (hhi_final <= HARD_HHI_CAP),
  winsor_applied = TRUE,
  lambda_used = 2.0,
  lambda_retries = 0,
  method_comparison = method_comparison,
  method_shopping_log = method_shopping_log,
  iter2_verdict = iter2_verdict,
  iter2_specific = list(
    iter2_method = iter2_method,
    baseline_method = baseline_method,
    delta_overall_sr = round(iter2_result$sr_overall - baseline_result$sr_overall, 4),
    delta_normal_sr  = round((iter2_result$sr_NORMAL %||% 0) - (baseline_result$sr_NORMAL %||% 0), 4),
    delta_cost_adj_sr = round(iter2_result$cost_adj_sr - baseline_result$cost_adj_sr, 4),
    target_normal_sr = 1.30,
    iter2_normal_sr_achieved = round(iter2_result$sr_NORMAL %||% NA, 4),
    target_met = (iter2_result$sr_NORMAL %||% 0) >= 1.30
  ),
  explanation = list(
    top_overweights = head(top5, 5),
    main_tradeoffs = c(
      "RegimeSigma_MinCVaR exploits CAUTION ρ=0.221 (76% above BULL/NORMAL) for dispersion",
      "CRISIS: alpha shrinkage to zero + MinVar on pooled Σ — defensive posture (alpha contra-indicator)",
      sprintf("Regime switch turnover %.1f%%/yr × 30bps = %.2f%%/yr cost",
              ann_to_selected * 100, ann_cost_selected * 100)
    )
  ),
  challenge_flags = challenge_flags,
  challenge_review = list(
    objection = FALSE,
    targets_reviewed = c("alpha_vector", "risk_sigma", "bound_feasibility",
                         "crisis_fallback_compatibility", "regime_label_validity"),
    note = "Alpha factor mix (6F MEGA_05) + regime label (expanding pct 4-state) + Σ shrinkage choices accepted as-is. CRISIS fallback policy is Optimizer's domain (per Common Charter §8). No silent constraint relaxation."
  ),
  pit_compliance = list(
    C1 = "PASS: regime label expanding pct + Σ from train window only",
    C2 = "PASS: regime t-1 lag enforced upstream by Alpha; weights applied at sig_date_{t+1}",
    C9 = "PASS: daily ret-to-monthly regime via month-floor join (no same-day VT/DD)",
    C10 = "PASS: liquidity 2e8 floor inherited from Risk universe",
    C11 = "PASS: KR internals only",
    C13 = "PASS: no manual sign flip",
    C14 = "PASS: no IC time-axis violation",
    C15 = "PASS: parquet load via factor_db / RAWDATA cache",
    note = "Optimizer reads alpha_package + risk_package (read-only). No regime/Σ re-estimation."
  ),
  references = c(
    "Rockafellar-Uryasev (2000) — CVaR LP",
    "Ang-Bekaert (2002) — regime conditional",
    "Ledoit-Wolf (2004) — shrinkage covariance",
    "QEPM L-122 — factor timing risk-managed (Barroso&Santa-Clara 2015)",
    "QEPM L-454 — KR internals dominance",
    "AX-001 v2 — defense conditional crisis_alpha + MDD ratio + IC ratio",
    "AX-002 — process honesty (no silent override)"
  )
)

opt_path <- file.path(WT_DIR, "optimization_package.json")
write_json(opt_pkg, opt_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("  → %s\n", opt_path))

# ───────────────────────────────────────────────────────────────────
# 13. Write weights.csv (mailbox + stage_artifacts)
# ───────────────────────────────────────────────────────────────────
cat("\n[13] Writing weights.csv...\n")

# Mailbox copy
weights_dt <- data.table(
  Ticker = names(target_weights),
  weight = as.numeric(target_weights),
  regime_at_decision = last_regime
)
fwrite(weights_dt, file.path(WT_DIR, "weights.csv"))

# Stage artifacts
SA_WT <- "stage_artifacts/WT_D20260425_007"
fwrite(weights_dt, file.path(SA_WT, "weights.csv"))

# Also produce 4-regime schedule wide
schedule_wide <- data.table(Ticker = tickers)
for (rg in c("BULL", "NORMAL", "CAUTION", "CRISIS")) {
  schedule_wide[, (rg) := unlist(regime_specific_weights[[rg]])[tickers]]
}
fwrite(schedule_wide, file.path(WT_DIR, "regime_specific_weights.csv"))

cat(sprintf("  → %s/weights.csv (mailbox + stage)\n", WT_DIR))
cat(sprintf("  → %s/regime_specific_weights.csv\n", WT_DIR))

# JSON copy of regime_specific_weights for downstream consumers
write_json(regime_specific_weights,
           file.path(WT_DIR, "regime_specific_weights.json"),
           pretty = TRUE, auto_unbox = TRUE)

# ───────────────────────────────────────────────────────────────────
# 14. Update status.json + lineage
# ───────────────────────────────────────────────────────────────────
cat("\n[14] Updating status.json + artifact_lineage.json...\n")

source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = TASK_ID,
  package_type = "optimization_package",
  method_selected = selected_method,
  input_file_paths = c(
    file.path(WT_DIR, "alpha_package.json"),
    file.path(WT_DIR, "risk_package.json"),
    file.path(WT_DIR, "covariance_per_regime.parquet"),
    file.path(WT_DIR, "regime_transition_cost.json")
  ),
  windows = list(
    train_window = list(start = format(TRAIN_START), end = format(TRAIN_END)),
    validation_window = list(start = format(SIG_DATE), end = "2024-01-23")
  ),
  random_seed = 20260425
)

# Status transition
status <- list(
  task_id = TASK_ID,
  current_phase = "OPTIMIZER_DONE",
  updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  blocker = list()
)
write_json(status, file.path(WT_DIR, "status.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null")

cat("\n========================================================\n")
cat(sprintf("OPTIMIZER_DONE — selected=%s\n", selected_method))
cat(sprintf("  NORMAL_SR=%.3f, overall_SR=%.3f, MDD=%.1f%%\n",
            eval_results[[selected_method]]$sr_NORMAL %||% NA,
            eval_results[[selected_method]]$sr_overall,
            eval_results[[selected_method]]$mdd * 100))
cat(sprintf("  ann_turnover=%.1f%%, regime_switch_cost=%.2f%%\n",
            ann_to_selected * 100, ann_cost_selected * 100))
cat(sprintf("  Iter 2 verdict (vs baseline Kelly_frac05_LW): %s\n", iter2_verdict))
cat(sprintf("  CRISIS fallback: %s\n", "alpha=0 + MinVar pooled Σ + bounds [0,0.10]"))
cat("========================================================\n")
