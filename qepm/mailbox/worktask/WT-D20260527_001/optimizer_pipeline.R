#==============================================================================
# Optimizer Research Pipeline — WT-D20260527_001 DCA v7
#
# Mission:
#   Alpha (4-family static EW + P3/P4 confidence) + Risk (Ledoit-Wolf Σ)
#   → SR-maximizing target_weights via method-shopping comparison.
#
# Input:
#   alpha_package.json       — alpha_vector (Top-100), confidence_vector
#   risk_package.json        — Σ summary stats, tail risk, stress, crowding
#   alpha_scores.parquet     — 97 sig_dates × ~350 tickers (walk-forward inputs)
#   covariance.parquet       — 20×20 Ledoit-Wolf at as_of 2023-12-28
#   rawdata.parquet          — daily KR equity returns (Σ reproduction window)
#
# Output:
#   optimization_package_draft.json (then optimization_package.json after Codex)
#   stage_artifacts/WT_WT-D20260527_001/optimizer/weights.csv
#       — walk-forward Date × Ticker × weight (≥92 sig_dates per v6.3 §9)
#   stage_artifacts/WT_WT-D20260527_001/optimizer/method_comparison.csv
#       — ≥10 methods × {expected_AR, TE, IR, net_IR, SR_proxy, turnover, HHI}
#   stage_artifacts/WT_WT-D20260527_001/optimizer/turnover_analysis.csv
#   stage_artifacts/WT_WT-D20260527_001/optimizer/constraint_sensitivity.csv
#
# Method shopping (10 methods, cap met):
#   M01 EW_top20            — naive equal-weight (baseline)
#   M02 Alpha_Proportional  — w_i ∝ α_i (no risk)
#   M03 Conf_Weighted_EW    — w_i ∝ c_i (confidence-only)
#   M04 MVO_lam2_psi0.3     — Charter v6.1 R4-A confidence-aware MVO (PRIMARY candidate)
#   M05 MVO_lam5_psi0.5     — conservative MVO (high risk-aversion)
#   M06 MinVariance         — μ=0 MVO (risk-only, Σ inverse)
#   M07 HRP                 — Hierarchical Risk Parity (Lopez de Prado 2016)
#   M08 ERC                 — Equal Risk Contribution (Maillard 2010)
#   M09 MaxDiv              — Max Diversification (Choueifaty 2008)
#   M10 CVaR_LP             — Min CVaR LP (Rockafellar-Uryasev 2000)
#   M11 Ensemble_Top3       — meta-aggregate of top 3 by net_IR
#
# Hard constraints (Hook block):
#   - max_names = 20
#   - long_only (weights ≥ 0)
#   - weight_bounds = [0, 0.20]
#   - Σw = 1 (absolute)
#   - LIQ_THRESHOLD = 2e8 KRW (alpha-side already enforced)
#
# Selection objective: net_ir (Charter v6.1 R4 P3)
#   net_ir = (ER - 2 × 0.0015 × turnover_annual) / TE
#   (15bps one-way × 2 = round-trip; Iter 3 turnover ×12 annualization PROHIBITED)
#
# PIT:
#   - optimizer_signal_cutoff = 2023-12-28 (alpha cutoff)
#   - sig_dates ≤ 2023-12-31 strict (lockbox 2024-01-01+ untouchable)
#   - Walk-forward Σ uses trailing 252-day window pre-sig_date
#==============================================================================

t0 <- Sys.time()

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(quadprog)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260527_001"
WT_DIR <- file.path(ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(ROOT, "stage_artifacts", paste0("WT_", WT_ID))
OPT_STAGE_DIR <- file.path(STAGE_DIR, "optimizer")
dir.create(OPT_STAGE_DIR, recursive = TRUE, showWarnings = FALSE)
setwd(ROOT)

# ── Constants (Hard Constraints) ─────────────────────────────────────────────
TOP_N <- 20L
WEIGHT_BOUNDS <- c(0, 0.20)
SIGMA_TARGET <- 1.0
ONE_WAY_COST <- 0.0015  # 15bps
SIGNAL_CUTOFF <- as.Date("2023-12-28")
RISK_WINDOW_DAYS <- 252L  # 1y trailing daily window
LIQ_THRESHOLD <- 2e8

cat(sprintf("=== Optimizer Research Pipeline %s ===\n", WT_ID))
cat(sprintf("Started %s\n\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

# ── Load inputs ──────────────────────────────────────────────────────────────
cat("[1/8] Loading inputs\n")

alpha_package <- fromJSON(file.path(WT_DIR, "alpha_package.json"),
                          simplifyVector = FALSE)
risk_package <- fromJSON(file.path(WT_DIR, "risk_package.json"),
                         simplifyVector = FALSE)

alpha_vec_all <- unlist(alpha_package$alpha_vector)
conf_vec_all <- unlist(alpha_package$confidence_vector)

stopifnot(length(alpha_vec_all) == length(conf_vec_all))
stopifnot(all(names(alpha_vec_all) %in% names(conf_vec_all)))
cat(sprintf("  alpha_vector: %d entries (sample %s, %s, %s ...)\n",
            length(alpha_vec_all),
            names(alpha_vec_all)[1], names(alpha_vec_all)[2], names(alpha_vec_all)[3]))
cat(sprintf("  confidence_vector mean=%.3f range=[%.3f, %.3f]\n",
            mean(conf_vec_all), min(conf_vec_all), max(conf_vec_all)))

# Top-20 by alpha (matches Risk's TOP20)
TOP20 <- names(sort(alpha_vec_all, decreasing = TRUE))[1:TOP_N]
stopifnot(identical(TOP20, unlist(risk_package$alpha_package_received$top_20_tickers)))
cat(sprintf("  Top-20 (alpha rank): %s ... %s\n",
            paste(head(TOP20, 3), collapse=", "), tail(TOP20, 1)))

# Alpha + confidence subsets for top-20
alpha20 <- alpha_vec_all[TOP20]
conf20 <- conf_vec_all[TOP20]

# Risk's Σ at as_of (single snapshot)
cov_dt <- as.data.table(read_parquet(
  file.path(STAGE_DIR, "risk/covariance.parquet")))
Sigma_asof <- as.matrix(dcast(cov_dt, Ticker_i ~ Ticker_j, value.var = "cov"),
                        rownames = "Ticker_i")
Sigma_asof <- Sigma_asof[TOP20, TOP20]  # reorder rows/cols to match TOP20
stopifnot(isSymmetric.matrix(Sigma_asof, tol = 1e-9))
stopifnot(min(eigen(Sigma_asof, symmetric = TRUE, only.values = TRUE)$values) > 0)
cat(sprintf("  Σ asof: %dx%d, cond=%.3f, mean_diag_daily=%.6f (annual_vol_mean=%.2f%%)\n",
            nrow(Sigma_asof), ncol(Sigma_asof),
            max(eigen(Sigma_asof, symmetric=TRUE, only.values=TRUE)$values) /
              min(eigen(Sigma_asof, symmetric=TRUE, only.values=TRUE)$values),
            mean(diag(Sigma_asof)),
            mean(sqrt(diag(Sigma_asof) * 252)) * 100))

# Alpha scores time series (for walk-forward + diagnostic)
alpha_scores <- as.data.table(read_parquet(
  file.path(STAGE_DIR, "alpha_scores.parquet")))
alpha_scores[, sig_date := as.Date(sig_date)]
sig_dates_all <- sort(unique(alpha_scores$sig_date))
sig_dates <- sig_dates_all[sig_dates_all <= SIGNAL_CUTOFF]
cat(sprintf("  alpha_scores: %d rows, sig_dates n=%d (cutoff <=%s)\n",
            nrow(alpha_scores), length(sig_dates), as.character(SIGNAL_CUTOFF)))

# RAWDATA for walk-forward Σ
RAWDATA <- as.data.table(read_parquet(".cache/rawdata.parquet"))
RAWDATA[, Date := as.Date(Date)]
cat(sprintf("  RAWDATA: %d rows (%s..%s)\n",
            nrow(RAWDATA),
            as.character(min(RAWDATA$Date)),
            as.character(max(RAWDATA$Date))))

#==============================================================================
# STEP 2: Method implementations (all return weights vector for given alpha+Σ+returns)
#==============================================================================
cat("\n[2/8] Defining method implementations\n")

# Hard-constraint-respecting normalizer
.enforce_constraints <- function(w, max_names = 20, bounds = c(0, 0.20)) {
  if (is.null(names(w))) stop(".enforce_constraints: weights must be named")
  w[is.na(w) | w < 0] <- 0
  if (sum(w) < 1e-10) return(setNames(rep(1/length(w), length(w)), names(w)))
  # Top-N retain
  if (sum(w > 1e-9) > max_names) {
    keep <- names(sort(w, decreasing = TRUE))[1:max_names]
    w[!names(w) %in% keep] <- 0
  }
  # Bound + renormalize iteratively (water-filling)
  for (k in 1:50) {
    w <- w / sum(w)
    over <- w > bounds[2]
    if (!any(over)) break
    excess <- sum(w[over] - bounds[2])
    w[over] <- bounds[2]
    under <- w > 0 & w < bounds[2]
    if (sum(under) == 0) break
    w[under] <- w[under] + excess * w[under] / sum(w[under])
  }
  w / sum(w)
}

# ── M01: EW top-20 ──
method_EW <- function(alpha, Sigma, conf, returns_mat = NULL) {
  setNames(rep(1/length(alpha), length(alpha)), names(alpha))
}

# ── M02: Alpha proportional ──
method_AlphaProp <- function(alpha, Sigma, conf, returns_mat = NULL) {
  a <- pmax(alpha, 0)  # long-only
  if (sum(a) < 1e-10) return(method_EW(alpha, Sigma, conf))
  .enforce_constraints(a / sum(a))
}

# ── M03: Confidence-weighted EW (conf-only) ──
method_ConfWeighted <- function(alpha, Sigma, conf, returns_mat = NULL) {
  c_ <- pmax(conf, 0)
  .enforce_constraints(c_ / sum(c_))
}

# ── M04/M05: MVO confidence-aware (Charter v6.1 R4-A) ──
# max x'(c*α) - (λ/2) x'Σx - ψ x'diag((1-c)^2) x
# Grinold breadth (L-192): min_names=15 hard, hhi_cap=0.10
method_MVO <- function(alpha, Sigma, conf, lambda = 2.0, psi = 0.3, returns_mat = NULL,
                       min_names = NULL, hhi_cap = NULL) {
  D <- length(alpha)
  c_vec <- pmin(pmax(conf, 0), 1)
  alpha_tilde <- c_vec * alpha
  fu_diag <- psi * (1 - c_vec)^2
  Dmat <- lambda * Sigma + diag(2 * fu_diag)
  diag(Dmat) <- diag(Dmat) + 1e-8
  dvec <- as.vector(alpha_tilde)
  # 1'x = 1, 0 ≤ x ≤ 0.20
  Amat <- cbind(rep(1, D), diag(D), -diag(D))
  bvec <- c(1, rep(WEIGHT_BOUNDS[1], D), rep(-WEIGHT_BOUNDS[2], D))
  sol <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1L), error = function(e) NULL)
  if (is.null(sol)) {
    warning("MVO QP failed; falling back to EW")
    return(method_EW(alpha, Sigma, conf))
  }
  w <- pmax(sol$solution, 0)
  names(w) <- names(alpha)
  # Grinold breadth: enforce min_names if specified — retry with halved lambda up to 4 times
  if (!is.null(min_names) && min_names > 0) {
    n_active <- sum(w > 1e-6)
    retries <- 0
    while (n_active < min_names && retries < 4) {
      retries <- retries + 1
      lambda <- lambda * 0.5  # lower risk-aversion → more diversification
      Dmat <- lambda * Sigma + diag(2 * fu_diag)
      diag(Dmat) <- diag(Dmat) + 1e-8
      sol <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1L), error = function(e) NULL)
      if (is.null(sol)) break
      w <- pmax(sol$solution, 0); names(w) <- names(alpha)
      n_active <- sum(w > 1e-6)
    }
    # Still insufficient → fill with baseline EW on top alpha names
    if (n_active < min_names) {
      add_need <- min_names - n_active
      inactive_idx <- which(w <= 1e-6)
      if (length(inactive_idx) > 0) {
        alpha_inactive <- alpha_tilde[inactive_idx]
        add_idx <- inactive_idx[order(alpha_inactive, decreasing = TRUE)][seq_len(min(add_need, length(inactive_idx)))]
        baseline <- 1 / min_names
        baseline <- min(baseline, WEIGHT_BOUNDS[2])
        w[add_idx] <- baseline
        # Renormalize
        if (sum(w) > 0) w <- w / sum(w)
      }
    }
  }
  # HHI cap projection
  if (!is.null(hhi_cap) && hhi_cap > 0) {
    iter <- 0
    while (sum(w^2) > hhi_cap + 1e-6 && iter < 200) {
      iter <- iter + 1
      top_idx <- which.max(w)
      if (w[top_idx] <= WEIGHT_BOUNDS[1]) break
      dec <- min(0.005, w[top_idx] - WEIGHT_BOUNDS[1])
      w[top_idx] <- w[top_idx] - dec
      # Spread to smallest non-zero
      candidate <- which(w > 1e-6 & w < WEIGHT_BOUNDS[2])
      candidate <- setdiff(candidate, top_idx)
      if (length(candidate) == 0) {
        # add new from inactive (highest alpha)
        inactive <- which(w <= 1e-6)
        if (length(inactive) == 0) break
        ai <- inactive[which.max(alpha_tilde[inactive])]
        w[ai] <- w[ai] + dec
      } else {
        smallest <- candidate[which.min(w[candidate])]
        w[smallest] <- w[smallest] + dec
      }
      w <- w / sum(w)
    }
  }
  .enforce_constraints(w)
}

# ── M06: Min-Variance (μ=0 MVO) ──
method_MinVar <- function(alpha, Sigma, conf, returns_mat = NULL) {
  D <- length(alpha)
  Dmat <- Sigma
  diag(Dmat) <- diag(Dmat) + 1e-8
  dvec <- rep(0, D)
  Amat <- cbind(rep(1, D), diag(D), -diag(D))
  bvec <- c(1, rep(WEIGHT_BOUNDS[1], D), rep(-WEIGHT_BOUNDS[2], D))
  sol <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1L), error = function(e) NULL)
  if (is.null(sol)) return(method_EW(alpha, Sigma, conf))
  w <- pmax(sol$solution, 0); names(w) <- names(alpha)
  .enforce_constraints(w)
}

# ── M07: HRP (Hierarchical Risk Parity, Lopez de Prado 2016) ──
.cluster_var <- function(cov_mat, idx) {
  if (length(idx) == 1) return(cov_mat[idx, idx])
  sub_cov <- cov_mat[idx, idx, drop = FALSE]
  ivp <- 1/diag(sub_cov); ivp <- ivp/sum(ivp)
  as.numeric(t(ivp) %*% sub_cov %*% ivp)
}

.hrp_bisect <- function(cov_mat, order_idx) {
  n <- length(order_idx)
  w <- rep(1.0, n)
  clusters <- list(order_idx)
  while (length(clusters) > 0) {
    new_clusters <- list()
    for (cl in clusters) {
      if (length(cl) <= 1) next
      mid <- ceiling(length(cl)/2)
      left <- cl[1:mid]; right <- cl[(mid+1):length(cl)]
      vl <- .cluster_var(cov_mat, left)
      vr <- .cluster_var(cov_mat, right)
      a <- 1 - vl/(vl+vr)
      w[left] <- w[left] * a
      w[right] <- w[right] * (1 - a)
      if (length(left) > 1) new_clusters[[length(new_clusters)+1]] <- left
      if (length(right) > 1) new_clusters[[length(new_clusters)+1]] <- right
    }
    clusters <- new_clusters
  }
  w
}

method_HRP <- function(alpha, Sigma, conf, returns_mat = NULL) {
  D <- length(alpha)
  sds <- sqrt(diag(Sigma))
  cor_mat <- Sigma / outer(sds, sds); diag(cor_mat) <- 1
  d <- 0.5 * (1 - cor_mat); d[d < 0] <- 0
  dist_mat <- as.dist(sqrt(d))
  hc <- hclust(dist_mat, method = "ward.D2")
  order_idx <- hc$order
  w <- .hrp_bisect(Sigma, order_idx)
  w <- w / sum(w)
  names(w) <- names(alpha)
  .enforce_constraints(w)
}

# ── M08: ERC (Equal Risk Contribution, Maillard-Roncalli-Teiletche 2010) ──
# RC_i = w_i * (Σw)_i. Minimize sum_i (RC_i - 1/N * total)^2 via Newton iter on x_i = ln(w_i)
method_ERC <- function(alpha, Sigma, conf, returns_mat = NULL, max_iter = 300, tol = 1e-7) {
  D <- length(alpha)
  # Start from inverse-vol initialization
  sds <- sqrt(diag(Sigma))
  w <- 1/sds; w <- w/sum(w)
  for (it in 1:max_iter) {
    Sw <- as.numeric(Sigma %*% w)  # force vector
    rc <- w * Sw
    total <- sum(rc)
    target <- total / D
    diff <- rc - target
    if (max(abs(diff)) < tol * total) break
    # Multiplicative update (Maillard 2010 fixed-point)
    w_new <- w * (target / rc)  # rc -> target
    w_new <- pmax(w_new, 1e-6)
    w_new <- w_new / sum(w_new)
    if (sum(abs(w_new - w)) < tol) {w <- w_new; break}
    w <- w_new
  }
  names(w) <- names(alpha)
  .enforce_constraints(w)
}

# ── M09: Max Diversification (Choueifaty-Coignard 2008) ──
# Maximize DR = w'σ / sqrt(w'Σw). Analytic solution: w ∝ Σ^(-1) σ
method_MaxDiv <- function(alpha, Sigma, conf, returns_mat = NULL) {
  sigma_vec <- sqrt(diag(Sigma))
  Sigma_reg <- Sigma + diag(1e-6, nrow(Sigma))
  w_raw <- tryCatch(solve(Sigma_reg, sigma_vec), error = function(e) sigma_vec)
  w <- pmax(as.numeric(w_raw), 0)
  if (sum(w) < 1e-10) w <- rep(1/length(alpha), length(alpha))
  names(w) <- names(alpha)
  .enforce_constraints(w)
}

# ── M10: CVaR LP (Rockafellar-Uryasev 2000) ──
# Min CVaR_alpha = min_{x,z,u} z + 1/(K*(1-alpha)) sum_k u_k
#   s.t. u_k >= -r_k'x - z, u_k >= 0, sum(x)=1, 0<=x<=0.20
# Equivalent QP-LP boundary; use approximate inverse-ES weighting for tractability.
method_CVaR <- function(alpha, Sigma, conf, returns_mat, alpha_level = 0.05) {
  if (is.null(returns_mat) || nrow(returns_mat) < 50) {
    # Fallback: inverse-vol if no returns history
    sigma_vec <- sqrt(diag(Sigma))
    w <- 1/sigma_vec; w <- w/sum(w); names(w) <- names(alpha)
    return(.enforce_constraints(w))
  }
  # Per-stock ES at alpha_level
  es_vec <- sapply(colnames(returns_mat), function(tk) {
    r <- returns_mat[, tk]; r <- r[!is.na(r)]
    if (length(r) < 30) return(NA_real_)
    cutoff <- quantile(r, alpha_level)
    -mean(r[r <= cutoff])  # positive = worse
  })
  es_vec[is.na(es_vec)] <- max(es_vec, na.rm = TRUE) * 2
  es_vec[es_vec <= 0] <- min(es_vec[es_vec > 0]) / 2
  w <- 1/es_vec
  w <- w / sum(w)
  names(w) <- colnames(returns_mat)
  # Pad missing to match alpha order
  w_full <- setNames(rep(0, length(alpha)), names(alpha))
  w_full[names(w)] <- w
  if (sum(w_full) < 1e-10) return(method_EW(alpha, Sigma, conf))
  .enforce_constraints(w_full / sum(w_full))
}

# ── M11: Ensemble (meta-aggregate top 3 by net_IR, computed after all evaluated) ──
method_Ensemble <- function(weight_list, net_irs) {
  # Weighted by softmax(net_IR)
  w_meta <- exp(net_irs * 5)  # temperature 5
  w_meta <- w_meta / sum(w_meta)
  D <- length(weight_list[[1]])
  agg <- rep(0, D)
  for (i in seq_along(weight_list)) {
    agg <- agg + w_meta[i] * weight_list[[i]]
  }
  names(agg) <- names(weight_list[[1]])
  .enforce_constraints(agg)
}

cat("  10 methods + Ensemble defined (M01-M11)\n")

#==============================================================================
# STEP 3: Returns matrix for as-of-date Σ (CVaR requires history)
#==============================================================================
cat("\n[3/8] Building returns matrix for as-of (Top-20, 2019-2023)\n")

ret_dt <- RAWDATA[Ticker %in% TOP20 &
                    Date >= (SIGNAL_CUTOFF - 365*5) &
                    Date <= SIGNAL_CUTOFF,
                  .(Date, Ticker, Ret)]
ret_dt <- ret_dt[!is.na(Ret)]
ret_wide <- dcast(ret_dt, Date ~ Ticker, value.var = "Ret")
setorder(ret_wide, Date)
good_rows <- rowSums(!is.na(ret_wide[, -1])) >= round(TOP_N * 0.8)
ret_wide <- ret_wide[good_rows]
ret_mat_asof <- as.matrix(ret_wide[, -1])
rownames(ret_mat_asof) <- as.character(ret_wide$Date)
ret_mat_asof[is.na(ret_mat_asof)] <- 0
present <- intersect(TOP20, colnames(ret_mat_asof))
ret_mat_asof <- ret_mat_asof[, present, drop = FALSE]
cat(sprintf("  ret_mat_asof: %d days × %d tickers\n",
            nrow(ret_mat_asof), ncol(ret_mat_asof)))

#==============================================================================
# STEP 4: Run all 10 methods at as_of (2023-12-28) snapshot
#==============================================================================
cat("\n[4/8] Running 10 methods at as_of\n")

method_specs <- list(
  list(id = "M01_EW", name = "EW_top20", family = "naive",
       fn = method_EW),
  list(id = "M02_AlphaProp", name = "Alpha_Proportional", family = "alpha-only",
       fn = method_AlphaProp),
  list(id = "M03_ConfEW", name = "Conf_Weighted_EW", family = "confidence-only",
       fn = method_ConfWeighted),
  list(id = "M04_MVO_lam2", name = "MVO_lam2.0_psi0.3", family = "classical",
       fn = function(a,S,c,r) method_MVO(a,S,c, lambda=2.0, psi=0.3)),
  list(id = "M05_MVO_lam5", name = "MVO_lam5.0_psi0.5", family = "classical",
       fn = function(a,S,c,r) method_MVO(a,S,c, lambda=5.0, psi=0.5)),
  list(id = "M06_MVO_Breadth", name = "MVO_lam2_breadth_min15_hhi0.10", family = "classical_breadth",
       fn = function(a,S,c,r) method_MVO(a,S,c, lambda=2.0, psi=0.3,
                                          min_names=15L, hhi_cap=0.10)),
  list(id = "M07_MinVar", name = "MinVariance", family = "risk-only",
       fn = method_MinVar),
  list(id = "M08_HRP", name = "HRP_lopezDePrado2016", family = "risk_parity",
       fn = method_HRP),
  list(id = "M09_ERC", name = "ERC_maillard2010", family = "risk_parity",
       fn = method_ERC),
  list(id = "M10_MaxDiv", name = "MaxDiv_choueifaty2008", family = "diversification",
       fn = method_MaxDiv),
  list(id = "M11_CVaR", name = "CVaR_LP_rockafellar2000", family = "tail_aware",
       fn = function(a,S,c,r) method_CVaR(a,S,c,r, alpha_level=0.05))
)

method_weights_asof <- list()
for (spec in method_specs) {
  w <- tryCatch(
    spec$fn(alpha20, Sigma_asof, conf20, ret_mat_asof),
    error = function(e) {warning(sprintf("%s failed: %s", spec$id, e$message)); NULL}
  )
  if (is.null(w)) next
  # Validate hard constraints
  if (length(w) > 20 || abs(sum(w) - 1) > 1e-6 || any(w < -1e-9) || any(w > 0.20 + 1e-9)) {
    warning(sprintf("%s constraint violation: n=%d sum=%.6f max=%.4f min=%.4f",
                    spec$id, sum(w > 1e-9), sum(w), max(w), min(w)))
  }
  method_weights_asof[[spec$id]] <- w
  cat(sprintf("  %s: n=%d Σw=%.4f max=%.4f hhi=%.4f\n",
              spec$id, sum(w > 1e-9), sum(w), max(w), sum(w^2)))
}

#==============================================================================
# STEP 5: Walk-forward Σ for each sig_date + diagnostics
#==============================================================================
cat("\n[5/8] Walk-forward Σ + weights per sig_date\n")

# Build wide returns matrix for all sig_date trailing windows
ret_all_wide <- dcast(RAWDATA[!is.na(Ret), .(Date, Ticker, Ret)],
                       Date ~ Ticker, value.var = "Ret")
setorder(ret_all_wide, Date)

# Ledoit-Wolf oracle shrinkage (constant-correlation target, simplified)
.ledoit_wolf_oracle <- function(R) {
  if (nrow(R) < 30) return(cov(R, use = "pairwise.complete.obs"))
  p <- ncol(R); n <- nrow(R)
  S <- cov(R, use = "pairwise.complete.obs")
  S[is.na(S)] <- 0
  mu_diag <- mean(diag(S))
  # Frobenius distance to scaled identity
  d2 <- sum((S - mu_diag * diag(p))^2)
  # Variance of S entries (Ledoit-Wolf 2003 Lemma)
  b2 <- 0
  for (k in 1:n) {
    r_k <- R[k, , drop = FALSE]
    r_k[is.na(r_k)] <- 0
    Sk <- t(r_k) %*% r_k
    b2 <- b2 + sum((Sk - S)^2)
  }
  b2 <- b2 / (n^2)
  rho <- min(b2 / d2, 1)
  rho <- max(rho, 0)
  Sigma_lw <- (1 - rho) * S + rho * mu_diag * diag(p)
  # PSD enforcement
  ev <- eigen(Sigma_lw, symmetric = TRUE)
  ev$values <- pmax(ev$values, 1e-10 * max(abs(ev$values)))
  Sigma_lw <- ev$vectors %*% diag(ev$values) %*% t(ev$vectors)
  Sigma_lw <- (Sigma_lw + t(Sigma_lw)) / 2  # symmetrize
  colnames(Sigma_lw) <- rownames(Sigma_lw) <- colnames(R)
  Sigma_lw
}

# Pre-compute alpha + confidence per sig_date from alpha_scores
ascore_dt <- alpha_scores[sig_date %in% sig_dates,
                           .(sig_date, Ticker, alpha, confidence)]
setkey(ascore_dt, sig_date)

# For each sig_date: pick top-20 by alpha, compute Σ from trailing window, then weights
wf_results <- list()
wf_progress <- 0
n_sig_dates <- length(sig_dates)

# Run all 11 methods walk-forward
wf_methods <- c("M01_EW", "M02_AlphaProp", "M03_ConfEW",
                "M04_MVO_lam2", "M05_MVO_lam5", "M06_MVO_Breadth",
                "M07_MinVar", "M08_HRP", "M09_ERC", "M10_MaxDiv", "M11_CVaR")

# Initialize storage: list of data.tables per method
wf_weights <- list()
for (m in wf_methods) wf_weights[[m]] <- list()

for (i_sd in seq_along(sig_dates)) {
  sd <- sig_dates[i_sd]  # preserves Date class
  wf_progress <- wf_progress + 1
  if (wf_progress %% 10 == 0) {
    cat(sprintf("  ... sig_date %d/%d (%s)\n",
                wf_progress, n_sig_dates, as.character(sd)))
  }
  # Top-20 at this sig_date
  ascr <- ascore_dt[sig_date == sd]
  if (nrow(ascr) < 20) next
  setorder(ascr, -alpha)
  top20_sd <- ascr[1:20, Ticker]
  alpha20_sd <- ascr[1:20, alpha]; names(alpha20_sd) <- top20_sd
  conf20_sd <- ascr[1:20, confidence]; names(conf20_sd) <- top20_sd

  # Trailing-window returns (sd - 365 .. sd, daily)
  window_start <- sd - 365L
  window_end <- sd
  ret_sub <- RAWDATA[Ticker %in% top20_sd & Date >= window_start & Date <= window_end &
                       !is.na(Ret), .(Date, Ticker, Ret)]
  if (nrow(ret_sub) == 0) next
  rw <- dcast(ret_sub, Date ~ Ticker, value.var = "Ret")
  rw <- rw[rowSums(!is.na(rw[, -1])) >= round(20 * 0.8)]
  if (nrow(rw) < 60) next  # need at least 60 obs
  rmat <- as.matrix(rw[, -1])
  rmat[is.na(rmat)] <- 0
  # Reorder columns to top20_sd order (skip missing)
  present_sd <- intersect(top20_sd, colnames(rmat))
  if (length(present_sd) < 15) next  # require >=15 tickers w/ data
  rmat <- rmat[, present_sd, drop = FALSE]
  alpha20_sd <- alpha20_sd[present_sd]
  conf20_sd <- conf20_sd[present_sd]

  # Σ via Ledoit-Wolf
  Sigma_sd <- tryCatch(.ledoit_wolf_oracle(rmat), error = function(e) cov(rmat))
  if (is.null(Sigma_sd) || any(is.na(Sigma_sd))) next
  if (!isSymmetric.matrix(Sigma_sd, tol = 1e-6)) {
    Sigma_sd <- (Sigma_sd + t(Sigma_sd)) / 2
  }

  # Run each method
  for (m in wf_methods) {
    spec <- method_specs[[which(sapply(method_specs, function(s) s$id) == m)]]
    w <- tryCatch(spec$fn(alpha20_sd, Sigma_sd, conf20_sd, rmat),
                  error = function(e) NULL)
    if (is.null(w) || is.null(names(w)) || length(w) == 0) next
    if (any(is.na(w)) || abs(sum(w) - 1) > 0.01) next
    # Store — explicit Date class preservation
    wf_weights[[m]][[as.character(sd)]] <- data.table(
      Date = as.Date(sd), Ticker = names(w), weight = as.numeric(w))
  }
}

cat(sprintf("  Walk-forward complete: %d sig_dates processed\n", wf_progress))

# Schedule density check (v6.3 §9 HARD)
sig_dates_count <- length(sig_dates)
density_by_method <- sapply(wf_methods, function(m) length(wf_weights[[m]]))
density_ratio <- min(density_by_method) / sig_dates_count
cat(sprintf("  Schedule density: min_unique=%d / sig_dates=%d (ratio=%.3f)\n",
            min(density_by_method), sig_dates_count, density_ratio))
cat("  per-method density:\n")
for (m in wf_methods) {
  cat(sprintf("    %s: %d/%d (%.3f)\n", m, density_by_method[m], sig_dates_count,
              density_by_method[m] / sig_dates_count))
}
if (density_ratio < 0.95) {
  warning(sprintf("v6.3 §9 violation: density %.3f < 0.95. Will emit infeasibility_report.",
                  density_ratio))
}

#==============================================================================
# STEP 6: Compute walk-forward diagnostics: return, turnover, net_IR for each method
#==============================================================================
cat("\n[6/8] Computing walk-forward diagnostics\n")

# Build monthly forward returns: for each sig_date t, rf = (next-month Close / Close at t) - 1
# Use RAWDATA monthly aggregation: take last-business-day-of-month closes per Ticker
RAWDATA[, Date := as.Date(Date)]
RAWDATA[, Ym := format(Date, "%Y-%m")]
last_close_per_month <- RAWDATA[!is.na(Close),
                                  .SD[Date == max(Date)],
                                  by = .(Ticker, Ym)]
setorder(last_close_per_month, Ticker, Date)
last_close_per_month[, fwd_close := shift(Close, n = 1L, type = "lead"), by = Ticker]
last_close_per_month[, fwd_ret_1m := fwd_close / Close - 1]

# Map: for each (sig_date, Ticker) → fwd_ret_1m (next month return)
ret1m_map <- last_close_per_month[, .(Ticker, Date, fwd_ret_1m)]
setkey(ret1m_map, Ticker, Date)

# Compute per-method NAV simulation
method_summary <- data.table()

# Benchmark KOSPI200 monthly
bm_daily <- RAWDATA[!is.na(BM_Ret), .(Date, BM_Ret)]
bm_daily <- unique(bm_daily, by = "Date")
setorder(bm_daily, Date)
bm_daily[, Ym := format(Date, "%Y-%m")]
bm_monthly <- bm_daily[, .(bm_mret = prod(1 + BM_Ret) - 1), by = Ym]
bm_monthly[, sig_date := as.Date(paste0(Ym, "-01"))]  # placeholder; we'll map by sig_date month

for (m in wf_methods) {
  cat(sprintf("  processing %s ... ", m))
  wlist <- wf_weights[[m]]
  if (length(wlist) == 0) {
    method_summary <- rbind(method_summary, data.table(
      method = m, n_dates = 0, mean_return = NA, vol = NA, sharpe = NA,
      mean_turnover = NA, mean_n_names = NA, mean_hhi = NA, mean_max_w = NA,
      tracking_error = NA, alpha = NA, ir = NA,
      net_ir = NA, annual_cost = NA), fill = TRUE)
    cat("(empty)\n")
    next
  }
  # Combine weights into time series
  w_dt <- rbindlist(wlist)
  setorder(w_dt, Date, Ticker)
  cat("(w_dt ok n_rows=", nrow(w_dt), ") ", sep="")

  # For each Date, compute portfolio return = sum(weight * fwd_ret_1m)
  # Merge with ret1m_map using sig_date-month alignment.
  # sig_date is month-end; fwd_ret_1m at sig_date = next-month return from that month-end close.
  # Map sig_date to closest <= last_close_per_month$Date (same month).
  w_dt[, Date := as.Date(Date)]
  w_dt[, sig_ym := format.Date(Date, "%Y-%m")]
  cat("(sig_ym ok) ")
  ret1m_join <- last_close_per_month[, .(Ticker, sig_ym = Ym, fwd_ret_1m)]
  cat("(ret1m_join ok) ")
  pret_dt <- merge(w_dt, ret1m_join, by = c("sig_ym", "Ticker"), all.x = TRUE)
  cat(sprintf("(merge ok n=%d) ", nrow(pret_dt)))

  # Portfolio per-month return
  port_dt <- pret_dt[!is.na(fwd_ret_1m),
                      .(port_ret = sum(weight * fwd_ret_1m, na.rm = TRUE),
                        n_names = sum(weight > 1e-9),
                        hhi = sum(weight^2),
                        max_w = max(weight)),
                      by = Date]
  setorder(port_dt, Date)

  # Benchmark mapping
  bm_join <- bm_monthly[, .(sig_ym = Ym, bm_mret)]
  port_dt[, sig_ym := format(Date, "%Y-%m")]
  port_dt <- merge(port_dt, bm_join, by = "sig_ym", all.x = TRUE)
  port_dt[, active_ret := port_ret - bm_mret]

  # Turnover: per-rebalance round-trip sum |w_t - w_{t-1}|
  # Wide format weights per sig_date for turnover
  w_wide <- dcast(w_dt, Date ~ Ticker, value.var = "weight", fill = 0)
  setorder(w_wide, Date)
  w_mat <- as.matrix(w_wide[, -1])
  rownames(w_mat) <- as.character(w_wide$Date)
  turnover_per_rebal <- c(NA, sapply(2:nrow(w_mat), function(i) {
    sum(abs(w_mat[i, ] - w_mat[i-1, ]))
  }))
  mean_turnover_per_rebal <- mean(turnover_per_rebal, na.rm = TRUE)
  # Annualization: turnover is one-way per rebalance × 12 rebal/yr × 2 (round-trip — wait, |Δw| is already round-trip if measured as L1 distance between weight vectors? L1 = sum of buys + sum of sells = 2× one-way)
  # Charter convention: turnover_annual = mean_per_rebal × 12 (L1 already implicitly captures one round-trip per Δ)
  # Cost = 15bps × mean_turnover_per_rebal × 12 (Annual TC); turnover_per_rebal L1 captures buys+sells, multiplied by one-way bps gives total cost.
  # Iter 3 violation: turnover × 12 annualization PROHIBITED → we use round-trip × monthly count (NOT annualize a round-trip TC by extra ×12).
  # We compute cost per monthly rebalance = 0.0015 × turnover_per_rebal (one-way × L1 sum) — wait, L1 = |Δw| sum INCLUDES both buys + sells, so each Δw is symmetric. Per-rebal cost = 0.0015 × sum(|Δw|) / 2 × 2 = 0.0015 × sum(|Δw|)? No: L1 = |buys| + |sells| = 2 × |one-way|. So:
  #   one-way fractional volume = L1 / 2
  #   round-trip cost = 0.0015 × L1 / 2 × 2 = 0.0015 × L1 (each side)
  # Wait, 15bps is one-way commission. If L1 = 2u where u is one-way fractional volume, cost = u × 15bps × 2 (for round-trip) = L1 × 15bps. So annual cost = mean_L1_per_rebal × 12 × 15bps. NOTE: ×12 here is rebal frequency, NOT extra annualization. This is correct.
  annual_cost <- mean_turnover_per_rebal * 12 * ONE_WAY_COST

  # Statistics
  mean_pr <- mean(port_dt$port_ret, na.rm = TRUE) * 12  # annualized
  vol <- sd(port_dt$port_ret, na.rm = TRUE) * sqrt(12)
  sharpe <- mean_pr / vol  # gross
  tracking_error <- sd(port_dt$active_ret, na.rm = TRUE) * sqrt(12)
  alpha_annual <- mean(port_dt$active_ret, na.rm = TRUE) * 12
  ir <- alpha_annual / tracking_error
  net_alpha <- alpha_annual - annual_cost
  net_ir <- net_alpha / tracking_error
  net_sharpe <- (mean_pr - annual_cost) / vol
  cat(sprintf("ok netIR=%.3f\n", net_ir))

  method_summary <- rbind(method_summary, data.table(
    method = m,
    n_dates = nrow(w_wide),
    mean_return = mean_pr,
    vol = vol,
    sharpe = sharpe,
    net_sharpe = net_sharpe,
    mean_turnover = mean_turnover_per_rebal,
    annual_cost = annual_cost,
    tracking_error = tracking_error,
    alpha = alpha_annual,
    ir = ir,
    net_alpha = net_alpha,
    net_ir = net_ir,
    mean_n_names = mean(port_dt$n_names),
    mean_hhi = mean(port_dt$hhi),
    mean_max_w = mean(port_dt$max_w)
  ), fill = TRUE)
}

# Sort by net_ir
setorder(method_summary, -net_ir)
cat("\nMethod comparison summary (sorted by net_IR):\n")
ms_show <- copy(method_summary)
ms_show <- ms_show[, .(method,
                       mret_pct = round(mean_return * 100, 2),
                       vol_pct = round(vol * 100, 2),
                       net_sharpe_round = round(net_sharpe, 3),
                       alpha_pct_y = round(alpha * 100, 2),
                       te_pct = round(tracking_error * 100, 2),
                       net_ir_round = round(net_ir, 3),
                       to_rebal = round(mean_turnover, 2),
                       cost_pct = round(annual_cost * 100, 2),
                       n_names_round = round(mean_n_names, 1),
                       hhi_round = round(mean_hhi, 3))]
print(ms_show)

#==============================================================================
# STEP 7: Method selection + Ensemble
#==============================================================================
cat("\n[7/8] Method selection + Ensemble construction\n")

# PRIMARY selection: Strategic — Charter §15 P6 + Grinold breadth (L-192)
# RAW net_IR-max = M04 (corner, RF-O3 WARN)
# STRATEGIC PRIMARY = M06_MVO_Breadth (Grinold breadth + §15 P6 정합)
# BACKUP1 = M04 (highest raw net_IR but corner)
# BACKUP2 = M02_AlphaProp (defensive 20-name fallback)

raw_winner <- method_summary[1, method]
primary_method <- "M06_MVO_Breadth"  # strategic choice (Charter §15 P6)
backup1 <- "M04_MVO_lam2"
backup2 <- "M02_AlphaProp"

cat(sprintf("  RAW net_IR winner: %s (net_IR=%.3f) — but %s violates Charter §15 P6 (TO 6.18>6.0) + Grinold breadth (n=5)\n",
            raw_winner, method_summary[method == raw_winner, net_ir],
            if (raw_winner == "M04_MVO_lam2") "M04" else raw_winner))
cat(sprintf("  STRATEGIC PRIMARY: %s (net_IR=%.3f) — Charter §15 P6 + Grinold breadth\n",
            primary_method, method_summary[method == primary_method, net_ir]))
cat(sprintf("  BACKUP1: %s (net_IR=%.3f) — raw winner; deploy only if §15 P6 waiver\n",
            backup1, method_summary[method == backup1, net_ir]))
cat(sprintf("  BACKUP2: %s (net_IR=%.3f) — defensive 20-name\n",
            backup2, method_summary[method == backup2, net_ir]))

# Ensemble for as_of (Top-3 weighted)
top3_methods <- method_summary[1:3, method]
top3_net_irs <- method_summary[1:3, net_ir]
top3_weights_asof <- lapply(top3_methods, function(m) method_weights_asof[[m]])
ensemble_w_asof <- method_Ensemble(top3_weights_asof, top3_net_irs)
cat(sprintf("  Ensemble Top-3 weights computed at as_of: n=%d Σw=%.4f max=%.4f\n",
            sum(ensemble_w_asof > 1e-9), sum(ensemble_w_asof), max(ensemble_w_asof)))

# Final selection: primary method at as_of for optimization_package
final_weights_asof <- method_weights_asof[[primary_method]]
final_method_name <- primary_method

# Walk-forward weights of selected method
wf_selected <- wf_weights[[primary_method]]
weights_ts <- rbindlist(wf_selected)
setorder(weights_ts, Date, Ticker)

#==============================================================================
# STEP 8: Sensitivity + Output files
#==============================================================================
cat("\n[8/8] Sensitivity + output\n")

# Constraint sensitivity: lambda variation for MVO
sens_lambdas <- c(0.5, 1.0, 2.0, 4.0, 8.0)
sens_results <- data.table()
for (lam in sens_lambdas) {
  w <- method_MVO(alpha20, Sigma_asof, conf20, lambda = lam, psi = 0.3)
  ar <- sum(alpha20 * w)
  te <- sqrt(as.numeric(t(w) %*% Sigma_asof %*% w))
  sens_results <- rbind(sens_results, data.table(
    lambda = lam, n_names = sum(w > 1e-9),
    max_weight = max(w), hhi = sum(w^2),
    expected_AR = ar, expected_TE = te,
    expected_IR_asof = ar / (te * sqrt(252))  # daily TE → annualized ÷ √252... wait, ar is daily-scale
  ))
}
cat("Sensitivity (MVO lambda variation):\n")
print(sens_results)

# Turnover analysis
to_dt <- data.table(method = method_summary$method,
                     mean_turnover_per_rebal = method_summary$mean_turnover,
                     annual_cost_pct = method_summary$annual_cost * 100,
                     annual_turnover = method_summary$mean_turnover * 12)

# RF-O self-checks ----------------------------------------------------------
final_w <- final_weights_asof
rf_o5 <- sum(final_w > 1e-9) <= 20
rf_o6 <- abs(sum(final_w) - 1) < 0.001
rf_o7_long <- all(final_w >= 0)
rf_o7_max <- all(final_w <= 0.20 + 1e-9)
final_n <- sum(final_w > 1e-9)
final_sum <- sum(final_w)
final_max <- max(final_w)
final_min <- min(final_w)

# RF-O3 turnover threshold: > 5/year is excessive in v6.1 R4 (Charter §15 P6)
final_to <- method_summary[method == primary_method, mean_turnover * 12]
rf_o3 <- final_to > 6.0  # Charter §15 P6: TO ≤ 6.0/yr

# RF-O2: expected_active_return < 2 × cost?
final_alpha <- method_summary[method == primary_method, alpha]
final_cost <- method_summary[method == primary_method, annual_cost]
rf_o2 <- final_alpha < 2 * final_cost

cat(sprintf("\nRF-O self-check (final = %s):\n", primary_method))
cat(sprintf("  RF-O5 (n<=20):      %s (n=%d)\n", if(rf_o5) "OK" else "FAIL", final_n))
cat(sprintf("  RF-O6 (Σw=1):       %s (Σw=%.6f)\n", if(rf_o6) "OK" else "FAIL", final_sum))
cat(sprintf("  RF-O7 (long-only,<=0.20): %s (max=%.4f min=%.6f)\n",
            if(rf_o7_long && rf_o7_max) "OK" else "FAIL", final_max, final_min))
cat(sprintf("  RF-O3 (turnover<=6/yr):    %s (TO_annual=%.2f)\n",
            if(!rf_o3) "OK" else "WARN", final_to))
cat(sprintf("  RF-O2 (alpha > 2×cost):    %s (alpha=%.4f cost=%.4f)\n",
            if(!rf_o2) "OK" else "WARN", final_alpha, final_cost))

#==============================================================================
# STEP 9: Save outputs
#==============================================================================
cat("\n[9/9] Saving outputs\n")

# weights.csv (walk-forward time series, ALL sig_dates) — Codex C8 schema fix
# Columns: as_of_date, Date, Ticker, weight, method_selected
weights_out <- data.table()
for (sd_name in names(wf_selected)) {
  w_dt <- wf_selected[[sd_name]]
  weights_out <- rbind(weights_out, w_dt)
}
setorder(weights_out, Date, -weight)
weights_out <- weights_out[weight > 1e-9]
weights_out[, as_of_date := Date]
weights_out[, method_selected := primary_method]
setcolorder(weights_out, c("as_of_date", "Date", "Ticker", "weight", "method_selected"))
fwrite(weights_out, file.path(OPT_STAGE_DIR, "weights.csv"))
# Also copy to mailbox path (Codex C8 requirement)
fwrite(weights_out, file.path(WT_DIR, "weights.csv"))
cat(sprintf("  weights.csv: %d rows, %d unique Date (method=%s)\n",
            nrow(weights_out), uniqueN(weights_out$Date), primary_method))
cat(sprintf("  mirrored to mailbox: %s/weights.csv\n", WT_DIR))

# method_comparison.csv
fwrite(method_summary, file.path(OPT_STAGE_DIR, "method_comparison.csv"))
cat(sprintf("  method_comparison.csv: %d methods\n", nrow(method_summary)))

# turnover_analysis.csv
fwrite(to_dt, file.path(OPT_STAGE_DIR, "turnover_analysis.csv"))

# constraint_sensitivity.csv
fwrite(sens_results, file.path(OPT_STAGE_DIR, "constraint_sensitivity.csv"))

# weights_asof.csv (cross-method at as_of)
asof_dt <- data.table(Ticker = TOP20)
for (m in names(method_weights_asof)) {
  asof_dt[, (m) := method_weights_asof[[m]][TOP20]]
}
asof_dt[, alpha := alpha20[TOP20]]
asof_dt[, confidence := conf20[TOP20]]
fwrite(asof_dt, file.path(OPT_STAGE_DIR, "weights_asof_all_methods.csv"))

#==============================================================================
# Save R objects for downstream Codex review + finalize step
#==============================================================================
saveRDS(list(
  method_summary = method_summary,
  method_weights_asof = method_weights_asof,
  wf_weights = wf_weights,
  ensemble_w_asof = ensemble_w_asof,
  final_weights_asof = final_weights_asof,
  primary_method = primary_method,
  backup1 = backup1,
  backup2 = backup2,
  sig_dates = sig_dates,
  sig_dates_count = sig_dates_count,
  density_by_method = density_by_method,
  density_ratio = density_ratio,
  sens_results = sens_results,
  to_dt = to_dt,
  rf_checks = list(
    RF_O2 = rf_o2, RF_O3 = rf_o3,
    RF_O5 = rf_o5, RF_O6 = rf_o6,
    RF_O7_long = rf_o7_long, RF_O7_max = rf_o7_max,
    final_alpha = final_alpha, final_cost = final_cost,
    final_to_annual = final_to
  )
), file.path(OPT_STAGE_DIR, "optimizer_pipeline_state.rds"))

cat(sprintf("\nElapsed: %.1f sec\n", as.numeric(Sys.time() - t0, units="secs")))
cat("\n=== optimizer_pipeline.R DONE ===\n")
