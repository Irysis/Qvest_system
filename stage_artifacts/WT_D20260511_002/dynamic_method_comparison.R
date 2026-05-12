#==============================================================================
# Dynamic Weight Rule Method Comparison — WT-D20260511_002
#
# Mission: 4-sleeve aggregate weight rule (sizing_only). alpha source frozen.
# Baseline: static 50/25/20/5 (S4 v2 admit, paradigm-free DRO convergence point).
# Strict improve criterion: SR > 1.665 + ΔSR DM t > 2, MDD <= -16.6% + Δ ≤ 2pp,
#                          turnover ≤ 30%/yr, walk-forward 256m + joint OOS.
#
# Risk Agent finding (input):
#   - CRISIS regime str1715-tsmom = +0.234 [+0.028, +0.433] (only stat sig shift)
#   - kr10y stagflation flight-to-quality (str1715-kr10y = -0.483 in stagflation)
#   - TDC_lower (str1715-kr10y/tsmom) = 0 (true lower-tail diversifiers)
#   - 2-state simplification 권고 (NORMAL ∪ CAUTION vs CRISIS)
#
# Methods compared (10+ candidates, future_lapply 병렬):
#   01_static_baseline:      50/25/20/5 (S4 v2 admit, NOT a candidate, BENCHMARK)
#   02_static_ew4:           25/25/25/25 (uniform sleeve comparison)
#   03_mvo_rolling:          Markowitz rolling MVO (Σ=trailing 60m, λ=2)
#   04_hrp_static:           López de Prado 2016 HRP on full 135m Σ
#   05_hrp_rolling:          HRP recomputed every 12m (rolling Σ)
#   06_erc_rolling:          Equal Risk Contribution rolling Σ
#   07_regime_4state_crisis: 4-state MRS, CRISIS regime str1715 -10pp / kr10y +5pp / tsmom +5pp / cash same
#   08_regime_2state_simple: 2-state (CRISIS vs NORMAL), CRISIS str1715 -10pp / kr10y +5pp
#   09_regime_2state_aggr:   2-state aggressive (CRISIS str1715 -20pp / kr10y +10pp / tsmom +5pp / cash +5pp)
#   10_vol_target_inverse:   Inverse vol allocation (sleeve weight ∝ 1/vol_t)
#   11_cvar_lp_minimize:     CVaR LP (Rockafellar-Uryasev 2000), min CVaR_95 s.t. constraints
#   12_max_sharpe_rolling:   Max Sharpe via grid search (rolling 60m Σ + 60m μ_hat)
#   13_dro_wasserstein:      DRO Wasserstein (Esfahani-Kuhn 2018), ε=0.1
#   14_blackliter_dynamic:   Black-Litterman dynamic posterior (regime view)
#   15_kelly_clipped:        Kelly criterion clipped to [0, 0.50] per sleeve
#
# 도훈 결정 적용:
#   C2: covariance_4sleeve_regularized.parquet (cash eps=1e-8) 사용
#   C3: CVaR cap waiver (S4 v2 admit precedent, dynamic rule이 strict improve 목표)
#==============================================================================

suppressMessages({
  library(arrow)
  library(jsonlite)
  library(data.table)
  library(future)
  library(future.apply)
})

set.seed(20260511)

# ─── Load input ──────────────────────────────────────────────────────────
returns <- read.csv("stage_artifacts/WT_P20260505_001/merged_returns_3source.csv",
                    stringsAsFactors = FALSE)
returns$date <- as.Date(returns$date)
returns <- as.data.table(returns)

# Joint window where all 3 sleeves available
joint <- returns[!is.na(str1715) & !is.na(kr10y) & !is.na(tsmom)]
cat(sprintf("Joint window: %s ~ %s, N=%d\n",
            min(joint$date), max(joint$date), nrow(joint)))

# Cash sleeve = 0 (zero-vol KRW)
joint[, cash := 0]

# Σ-related: regularized 4-sleeve from Risk Agent
cov4_long <- arrow::read_parquet("stage_artifacts/WT_D20260511_002/covariance_4sleeve_regularized.parquet")
assets <- c("str1715", "kr10y", "tsmom", "cash")
Sigma_4 <- matrix(NA, 4, 4, dimnames=list(assets, assets))
for (i in seq_len(nrow(cov4_long))) {
  Sigma_4[cov4_long$asset_i[i], cov4_long$asset_j[i]] <- cov4_long$cov_val[i]
}
cat("Sigma_4 (regularized):\n"); print(round(Sigma_4*1e4, 4))

# 3-sleeve primary Σ (cash excluded)
cov3_long <- arrow::read_parquet("stage_artifacts/WT_D20260511_002/covariance.parquet")
assets3 <- c("str1715", "kr10y", "tsmom")
Sigma_3 <- matrix(NA, 3, 3, dimnames=list(assets3, assets3))
for (i in seq_len(nrow(cov3_long))) {
  Sigma_3[cov3_long$asset_i[i], cov3_long$asset_j[i]] <- cov3_long$cov_val[i]
}

# Regime correlation
regime_cor <- as.data.table(arrow::read_parquet("stage_artifacts/WT_D20260511_002/regime_correlation.parquet"))

# ─── Regime classifier reconstruction (MRS_Expanding_Percentile_4_State) ─
# Risk Agent design: 1715 backbone 12m rolling sum, expanding percentile, 4 quartiles
# PIT lag t-1 (C9) — regime at t known only from t-1 information
regime_from_str1715 <- function(r_str1715, dates) {
  n <- length(r_str1715)
  rollsum_12m <- rep(NA, n)
  for (i in 12:n) rollsum_12m[i] <- sum(r_str1715[(i-11):i], na.rm=FALSE)
  # Expanding percentile (PIT)
  pct <- rep(NA, n)
  for (i in 12:n) {
    hist <- rollsum_12m[12:i]
    hist <- hist[!is.na(hist)]
    if (length(hist) > 1) pct[i] <- rank(hist)[length(hist)] / length(hist)
  }
  # 4 states
  regime <- rep(NA_character_, n)
  regime[!is.na(pct) & pct > 0.75] <- "BULL"
  regime[!is.na(pct) & pct > 0.50 & pct <= 0.75] <- "NORMAL"
  regime[!is.na(pct) & pct > 0.25 & pct <= 0.50] <- "CAUTION"
  regime[!is.na(pct) & pct <= 0.25] <- "CRISIS"
  # PIT lag: regime at t known from t-1
  regime_lag <- c(NA, regime[-n])
  list(regime = regime, regime_lag = regime_lag, rollsum_12m = rollsum_12m, pct = pct)
}

# Compute regime on full 256m str1715 (TSMOM-independent regime, str1715 backbone)
full256 <- returns[!is.na(str1715), .(date, str1715, kr10y, tsmom)]
full256_regime <- regime_from_str1715(full256$str1715, full256$date)
full256[, regime_lag := full256_regime$regime_lag]
# Merge regime_lag to joint
joint <- merge(joint, full256[, .(date, regime_lag)], by="date", all.x=TRUE)

cat("\nJoint regime distribution (lagged t-1):\n")
print(table(joint$regime_lag, useNA="always"))

# ─── Build composite return given weights ─────────────────────────────────
composite_ret <- function(W, returns_dt) {
  # W: (n × 4 matrix or named vector) sleeve weights at each month
  # returns_dt: data.table with str1715/kr10y/tsmom/cash columns
  if (is.vector(W)) {
    # constant weights → broadcast
    W <- matrix(W, nrow=nrow(returns_dt), ncol=4, byrow=TRUE)
    colnames(W) <- assets
  }
  ret <- W[, "str1715"] * returns_dt$str1715 +
         W[, "kr10y"]   * returns_dt$kr10y   +
         W[, "tsmom"]   * returns_dt$tsmom   +
         W[, "cash"]    * returns_dt$cash
  ret
}

# Performance metric (PerformanceAnalytics convention)
perf_metrics <- function(r, freq=12) {
  r <- r[!is.na(r)]
  n <- length(r)
  ann_ret <- prod(1+r)^(freq/n) - 1
  ann_vol <- sd(r) * sqrt(freq)
  sr <- ann_ret / ann_vol
  # MDD
  nav <- cumprod(1+r)
  peak <- cummax(nav)
  dd <- nav/peak - 1
  mdd <- min(dd)
  # Sortino
  downside <- r[r < 0]
  sortino <- ann_ret / (sd(downside) * sqrt(freq))
  # Calmar
  calmar <- ann_ret / abs(mdd)
  list(SR=sr, CAGR=ann_ret, MDD=mdd, Sortino=sortino, Calmar=calmar,
       N=n, AnnVol=ann_vol)
}

# Turnover (sum of absolute weight changes / 2 per period, annualized)
turnover_calc <- function(W) {
  if (is.vector(W)) return(0)
  diffs <- abs(diff(W))
  mean_to <- mean(rowSums(diffs)) / 2 * 12
  mean_to
}

# Net return after turnover cost (15bps one-way × 2 way)
net_ret_after_cost <- function(r, W, tc_bps=15) {
  if (is.vector(W)) return(r)  # No turnover for static
  diffs <- abs(diff(W))
  to_per_period <- rowSums(diffs) / 2  # one-side
  cost_per_period <- c(0, to_per_period * tc_bps * 2 / 1e4)  # round-trip
  r - cost_per_period
}

# ─── METHOD IMPLEMENTATIONS ──────────────────────────────────────────────

# 01. Static baseline 50/25/20/5
method_01_static_baseline <- function(joint) {
  W <- matrix(c(0.50, 0.20, 0.25, 0.05), nrow=nrow(joint), ncol=4, byrow=TRUE)
  colnames(W) <- assets
  list(name = "01_static_baseline", W = W,
       desc = "S4 v2 admit (50/25/20/5)")
}

# 02. EW 4-sleeve
method_02_static_ew4 <- function(joint) {
  W <- matrix(0.25, nrow=nrow(joint), ncol=4)
  colnames(W) <- assets
  list(name = "02_static_ew4", W = W,
       desc = "Equal weight 4 sleeves (25/25/25/25)")
}

# 03. MVO rolling
method_03_mvo_rolling <- function(joint, lookback=60, lambda=2.0) {
  n <- nrow(joint)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  # initial: 50/25/20/5
  W[1, ] <- c(0.50, 0.20, 0.25, 0.05)
  for (t in 2:n) {
    start <- max(1, t - lookback)
    if (t - start < 12) {
      W[t, ] <- W[t-1, ]
      next
    }
    R_hist <- as.matrix(joint[start:(t-1), .(str1715, kr10y, tsmom)])
    mu_hat <- colMeans(R_hist, na.rm=TRUE)
    Sigma_hat <- cov(R_hist, use="pairwise.complete.obs")
    # add cash (zero-vol)
    mu_4 <- c(mu_hat, 0)
    Sigma_4t <- rbind(cbind(Sigma_hat, c(0,0,0)), c(0,0,0,1e-8))
    rownames(Sigma_4t) <- assets; colnames(Sigma_4t) <- assets
    # MVO: max w'mu - lambda/2 w'Σw  s.t. sum=1, w∈[0,0.70] str1715, [0,0.40] others, [0,0.30] cash
    # Use quadprog
    if (requireNamespace("quadprog", quietly = TRUE)) {
      Dmat <- lambda * Sigma_4t
      dvec <- mu_4
      # constraints
      Amat <- cbind(rep(1,4),         # sum=1
                    diag(4),           # w_i >= 0
                    -diag(4))          # w_i <= upper
      bvec <- c(1, rep(0,4), -c(0.70, 0.40, 0.40, 0.30))
      meq <- 1
      sol <- tryCatch(quadprog::solve.QP(Dmat, dvec, Amat, bvec, meq=meq),
                      error=function(e) NULL)
      if (!is.null(sol)) W[t, ] <- pmax(0, sol$solution)
      else W[t, ] <- W[t-1, ]
      # renormalize
      W[t, ] <- W[t, ] / sum(W[t, ])
    } else {
      W[t, ] <- W[t-1, ]
    }
  }
  list(name = "03_mvo_rolling", W = W,
       desc = sprintf("MVO rolling lookback=%dm lambda=%.1f, sleeve caps [0.70, 0.40, 0.40, 0.30]", lookback, lambda))
}

# 04. HRP static (full 135m)
method_04_hrp_static <- function(joint) {
  # HRP on Sigma_4 (regularized)
  # Use built-in approach: tree allocation via correlation distance
  D <- sqrt(2 * (1 - cov2cor(Sigma_4)))
  D[is.na(D)] <- 0
  hc <- hclust(as.dist(D), method = "single")
  # Recursive bisection (López de Prado 2016)
  sortIx <- hc$order
  w <- rep(1, 4); names(w) <- assets
  hrp_bisect <- function(cov, ids) {
    if (length(ids) <= 1) return(setNames(1, assets[ids]))
    n <- length(ids)
    split1 <- ids[1:(n %/% 2)]
    split2 <- ids[(n %/% 2 + 1):n]
    # Inverse-variance for each cluster
    iv1 <- 1 / diag(cov)[split1]; iv1 <- iv1 / sum(iv1)
    iv2 <- 1 / diag(cov)[split2]; iv2 <- iv2 / sum(iv2)
    var1 <- as.numeric(t(iv1) %*% cov[split1, split1] %*% iv1)
    var2 <- as.numeric(t(iv2) %*% cov[split2, split2] %*% iv2)
    alpha <- 1 - var1 / (var1 + var2)
    w_left <- hrp_bisect(cov, split1) * alpha
    w_right <- hrp_bisect(cov, split2) * (1 - alpha)
    c(w_left, w_right)
  }
  w_hrp <- hrp_bisect(Sigma_4, sortIx)
  w_hrp <- w_hrp[assets]
  w_hrp <- w_hrp / sum(w_hrp)
  W <- matrix(w_hrp, nrow=nrow(joint), ncol=4, byrow=TRUE)
  colnames(W) <- assets
  list(name = "04_hrp_static", W = W,
       desc = sprintf("HRP static (López de Prado 2016): %s", paste0(sprintf("%.3f", w_hrp), collapse="/")))
}

# 05. HRP rolling (12m recompute)
method_05_hrp_rolling <- function(joint, refit_every=12) {
  n <- nrow(joint)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  W[1, ] <- c(0.50, 0.20, 0.25, 0.05)
  current_w <- W[1, ]
  for (t in 2:n) {
    start <- max(1, t - 60)
    if (t %% refit_every == 0 && t - start >= 24) {
      R_hist <- as.matrix(joint[start:(t-1), .(str1715, kr10y, tsmom)])
      Sigma_hat <- cov(R_hist, use="pairwise.complete.obs")
      Sigma_4t <- rbind(cbind(Sigma_hat, c(0,0,0)), c(0,0,0,1e-8))
      rownames(Sigma_4t) <- assets; colnames(Sigma_4t) <- assets
      D <- sqrt(pmax(0, 2 * (1 - cov2cor(Sigma_4t))))
      D[is.na(D)] <- 0
      hc <- hclust(as.dist(D), method = "single")
      sortIx <- hc$order
      hrp_bisect <- function(cov, ids) {
        if (length(ids) <= 1) return(setNames(1, assets[ids]))
        nn <- length(ids)
        split1 <- ids[1:(nn %/% 2)]
        split2 <- ids[(nn %/% 2 + 1):nn]
        iv1 <- 1 / diag(cov)[split1]; iv1 <- iv1 / sum(iv1)
        iv2 <- 1 / diag(cov)[split2]; iv2 <- iv2 / sum(iv2)
        var1 <- as.numeric(t(iv1) %*% cov[split1, split1] %*% iv1)
        var2 <- as.numeric(t(iv2) %*% cov[split2, split2] %*% iv2)
        alpha <- 1 - var1 / (var1 + var2)
        w_left <- hrp_bisect(cov, split1) * alpha
        w_right <- hrp_bisect(cov, split2) * (1 - alpha)
        c(w_left, w_right)
      }
      w_hrp <- hrp_bisect(Sigma_4t, sortIx)
      w_hrp <- w_hrp[assets]
      w_hrp <- w_hrp / sum(w_hrp)
      current_w <- w_hrp
    }
    W[t, ] <- current_w
  }
  list(name = "05_hrp_rolling", W = W,
       desc = sprintf("HRP rolling (refit every %dm, lookback 60m)", refit_every))
}

# 06. ERC rolling (Equal Risk Contribution)
method_06_erc_rolling <- function(joint, refit_every=12, lookback=60) {
  n <- nrow(joint)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  W[1, ] <- c(0.50, 0.20, 0.25, 0.05)
  current_w <- W[1, ]
  erc_solve <- function(Sigma) {
    # iterative algorithm (Maillard et al. 2010)
    n <- nrow(Sigma)
    w <- rep(1/n, n)
    for (iter in 1:1000) {
      MRC <- Sigma %*% w
      RC <- as.numeric(w * MRC)
      target <- mean(RC)
      grad <- RC - target
      w_new <- w - 0.01 * grad / abs(grad)
      w_new <- pmax(w_new, 1e-6)
      w_new <- w_new / sum(w_new)
      if (max(abs(w_new - w)) < 1e-6) break
      w <- w_new
    }
    w
  }
  for (t in 2:n) {
    start <- max(1, t - lookback)
    if (t %% refit_every == 0 && t - start >= 24) {
      R_hist <- as.matrix(joint[start:(t-1), .(str1715, kr10y, tsmom)])
      Sigma_hat <- cov(R_hist, use="pairwise.complete.obs")
      # cash 제외 (zero vol → ERC undefined for zero-vol asset)
      # Solve ERC on 3-sleeve, then add cash=0
      w_3 <- erc_solve(Sigma_hat)
      names(w_3) <- assets3
      w_4 <- c(w_3, cash=0.05)
      w_4["str1715"] <- w_4["str1715"] * 0.95
      w_4["kr10y"] <- w_4["kr10y"] * 0.95
      w_4["tsmom"] <- w_4["tsmom"] * 0.95
      w_4 <- w_4 / sum(w_4)
      current_w <- w_4[assets]
    }
    W[t, ] <- current_w
  }
  list(name = "06_erc_rolling", W = W,
       desc = sprintf("ERC rolling (refit %dm, lookback %dm, 3-sleeve ERC + cash 5%%)", refit_every, lookback))
}

# 07. Regime 4-state (CRISIS shift)
method_07_regime_4state_crisis <- function(joint) {
  n <- nrow(joint)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  base <- c(str1715=0.50, kr10y=0.20, tsmom=0.25, cash=0.05)
  crisis_shift <- c(str1715=-0.10, kr10y=+0.05, tsmom=+0.05, cash=0.00)
  for (t in 1:n) {
    reg <- joint$regime_lag[t]
    if (is.na(reg) || reg != "CRISIS") {
      W[t, ] <- base[assets]
    } else {
      W[t, ] <- (base + crisis_shift)[assets]
    }
    W[t, ] <- W[t, ] / sum(W[t, ])
  }
  list(name = "07_regime_4state_crisis", W = W,
       desc = "4-state regime. CRISIS: str1715 -10pp / kr10y +5pp / tsmom +5pp (Risk Agent finding ⭐)")
}

# 08. Regime 2-state simple (CRISIS vs NOT-CRISIS)
method_08_regime_2state_simple <- function(joint) {
  n <- nrow(joint)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  base <- c(str1715=0.50, kr10y=0.20, tsmom=0.25, cash=0.05)
  crisis_shift <- c(str1715=-0.10, kr10y=+0.05, tsmom=+0.05, cash=0.00)
  for (t in 1:n) {
    reg <- joint$regime_lag[t]
    is_crisis <- !is.na(reg) && reg == "CRISIS"
    if (is_crisis) W[t, ] <- (base + crisis_shift)[assets]
    else W[t, ] <- base[assets]
    W[t, ] <- W[t, ] / sum(W[t, ])
  }
  list(name = "08_regime_2state_simple", W = W,
       desc = "2-state simple: CRISIS vs not-CRISIS, same shift as 07")
}

# 09. Regime 2-state aggressive
method_09_regime_2state_aggr <- function(joint) {
  n <- nrow(joint)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  base <- c(str1715=0.50, kr10y=0.20, tsmom=0.25, cash=0.05)
  crisis_shift <- c(str1715=-0.20, kr10y=+0.10, tsmom=+0.05, cash=+0.05)
  for (t in 1:n) {
    reg <- joint$regime_lag[t]
    is_crisis <- !is.na(reg) && reg == "CRISIS"
    if (is_crisis) W[t, ] <- (base + crisis_shift)[assets]
    else W[t, ] <- base[assets]
    W[t, ] <- W[t, ] / sum(W[t, ])
  }
  list(name = "09_regime_2state_aggr", W = W,
       desc = "2-state aggressive: CRISIS str1715 -20pp / kr10y +10pp / tsmom +5pp / cash +5pp")
}

# 10. Inverse vol allocation (rolling 12m)
method_10_vol_target_inverse <- function(joint, lookback=12) {
  n <- nrow(joint)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  W[1, ] <- c(0.50, 0.20, 0.25, 0.05)
  for (t in 2:n) {
    if (t > lookback) {
      vol_hist <- sapply(c("str1715","kr10y","tsmom"), function(c) {
        sd(joint[[c]][(t-lookback):(t-1)], na.rm=TRUE)
      })
      iv <- 1 / pmax(vol_hist, 1e-6)
      iv <- iv / sum(iv)
      # Scale to 95% (cash 5% fixed)
      W[t, "str1715"] <- iv["str1715"] * 0.95
      W[t, "kr10y"]   <- iv["kr10y"]   * 0.95
      W[t, "tsmom"]   <- iv["tsmom"]   * 0.95
      W[t, "cash"]    <- 0.05
    } else {
      W[t, ] <- W[t-1, ]
    }
  }
  list(name = "10_vol_target_inverse", W = W,
       desc = sprintf("Inverse-vol allocation (rolling %dm), cash 5%% fixed", lookback))
}

# 11. CVaR LP minimize (rolling 60m)
method_11_cvar_lp_min <- function(joint, lookback=60, refit_every=12, alpha=0.95) {
  n <- nrow(joint)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  W[1, ] <- c(0.50, 0.20, 0.25, 0.05)
  current_w <- W[1, ]
  if (!requireNamespace("Rglpk", quietly = TRUE)) {
    cat("Rglpk not available, using fallback\n")
    for (t in 1:n) W[t, ] <- c(0.50, 0.20, 0.25, 0.05)
    return(list(name="11_cvar_lp_min", W=W, desc="Rglpk unavailable, fallback static"))
  }
  for (t in 2:n) {
    start <- max(1, t - lookback)
    if (t %% refit_every == 0 && t - start >= 24) {
      R_hist <- as.matrix(joint[start:(t-1), .(str1715, kr10y, tsmom)])
      # Add cash column (zero return)
      R_hist <- cbind(R_hist, cash = 0)
      n_scen <- nrow(R_hist)
      # LP: min VaR + 1/(1-alpha)/n * sum(z)
      # vars: [w1, w2, w3, w4, VaR, z1, ..., zT]
      n_assets <- 4
      n_vars <- n_assets + 1 + n_scen
      # obj: VaR + 1/((1-alpha)*n) * sum(z)
      obj <- c(rep(0, n_assets), 1, rep(1/((1-alpha)*n_scen), n_scen))
      # constraints:
      # 1. sum(w) = 1
      # 2. z_i >= -r_i'w - VaR for each scenario
      # 3. w_i >= 0, w_i <= bounds
      # 4. expected return >= 0 (loose constraint)
      mat <- matrix(0, n_scen + 1, n_vars)
      mat[1, 1:n_assets] <- 1  # sum constraint
      for (i in 1:n_scen) {
        mat[i+1, 1:n_assets] <- R_hist[i, ]   # r_i'w
        mat[i+1, n_assets + 1] <- 1            # VaR coef
        mat[i+1, n_assets + 1 + i] <- 1        # z_i coef
      }
      dir <- c("==", rep(">=", n_scen))
      rhs <- c(1, rep(0, n_scen))
      bounds_lower <- c(rep(0, n_assets), -Inf, rep(0, n_scen))
      bounds_upper <- c(0.70, 0.40, 0.40, 0.30, Inf, rep(Inf, n_scen))
      sol <- tryCatch(
        Rglpk::Rglpk_solve_LP(obj=obj, mat=mat, dir=dir, rhs=rhs,
                              bounds=list(lower=list(ind=seq_along(bounds_lower), val=bounds_lower),
                                          upper=list(ind=seq_along(bounds_upper), val=bounds_upper)),
                              max=FALSE),
        error=function(e) NULL)
      if (!is.null(sol) && sol$status == 0) {
        w_new <- sol$solution[1:n_assets]
        w_new <- pmax(0, w_new)
        w_new <- w_new / sum(w_new)
        current_w <- w_new
      }
    }
    W[t, ] <- current_w
  }
  list(name = "11_cvar_lp_min", W = W,
       desc = sprintf("CVaR LP min (Rockafellar-Uryasev 2000), lookback %dm, refit %dm, alpha=%.2f", lookback, refit_every, alpha))
}

# 12. Max-Sharpe grid search (rolling)
method_12_max_sharpe_rolling <- function(joint, lookback=60, refit_every=12) {
  n <- nrow(joint)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  W[1, ] <- c(0.50, 0.20, 0.25, 0.05)
  current_w <- W[1, ]
  # Grid: w_str1715 ∈ {0.30, 0.40, 0.50, 0.60, 0.70}
  #       w_kr10y ∈ {0.10, 0.15, 0.20, 0.25, 0.30, 0.35}
  #       w_tsmom ∈ {0.10, 0.15, 0.20, 0.25, 0.30, 0.35}
  #       w_cash = 1 - rest
  grid <- expand.grid(
    str1715 = c(0.30, 0.40, 0.50, 0.60, 0.70),
    kr10y = c(0.10, 0.15, 0.20, 0.25, 0.30, 0.35),
    tsmom = c(0.10, 0.15, 0.20, 0.25, 0.30, 0.35)
  )
  grid$cash <- 1 - grid$str1715 - grid$kr10y - grid$tsmom
  grid <- grid[grid$cash >= 0 & grid$cash <= 0.30, ]
  for (t in 2:n) {
    start <- max(1, t - lookback)
    if (t %% refit_every == 0 && t - start >= 24) {
      R_hist <- as.matrix(joint[start:(t-1), .(str1715, kr10y, tsmom)])
      R_hist <- cbind(R_hist, cash = 0)
      best_sr <- -Inf
      best_w <- current_w
      for (k in 1:nrow(grid)) {
        w <- as.numeric(grid[k, c("str1715","kr10y","tsmom","cash")])
        r_port <- as.numeric(R_hist %*% w)
        m <- mean(r_port); s <- sd(r_port)
        if (s > 0) {
          sr <- m / s
          if (sr > best_sr) { best_sr <- sr; best_w <- w }
        }
      }
      current_w <- best_w
    }
    W[t, ] <- current_w
  }
  list(name = "12_max_sharpe_rolling", W = W,
       desc = sprintf("Max-Sharpe grid search (rolling, lookback %dm refit %dm)", lookback, refit_every))
}

# 13. DRO Wasserstein (Esfahani-Kuhn 2018)
# DRO max-min: min over Σ ∈ B_eps(Σ_hat) of max-Sharpe portfolio.
# Implementation: regularize Σ_hat by adding eps^2 * I (Esfahani-Kuhn shows this is the Wasserstein DRO solution for quadratic risk)
method_13_dro_wasserstein <- function(joint, lookback=60, refit_every=12, eps=0.1) {
  n <- nrow(joint)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  W[1, ] <- c(0.50, 0.20, 0.25, 0.05)
  current_w <- W[1, ]
  for (t in 2:n) {
    start <- max(1, t - lookback)
    if (t %% refit_every == 0 && t - start >= 24) {
      R_hist <- as.matrix(joint[start:(t-1), .(str1715, kr10y, tsmom)])
      mu_hat <- colMeans(R_hist)
      Sigma_hat <- cov(R_hist)
      # DRO regularization: Σ_DRO = Σ + eps^2 * I
      Sigma_dro <- Sigma_hat + (eps^2) * diag(3)
      mu_4 <- c(mu_hat, 0)
      Sigma_4t <- rbind(cbind(Sigma_dro, c(0,0,0)), c(0,0,0,1e-8))
      rownames(Sigma_4t) <- assets; colnames(Sigma_4t) <- assets
      # MVO solve
      if (requireNamespace("quadprog", quietly = TRUE)) {
        Dmat <- 2.0 * Sigma_4t  # lambda=2
        dvec <- mu_4
        Amat <- cbind(rep(1,4), diag(4), -diag(4))
        bvec <- c(1, rep(0,4), -c(0.70, 0.40, 0.40, 0.30))
        sol <- tryCatch(quadprog::solve.QP(Dmat, dvec, Amat, bvec, meq=1),
                        error=function(e) NULL)
        if (!is.null(sol)) {
          current_w <- pmax(0, sol$solution)
          current_w <- current_w / sum(current_w)
        }
      }
    }
    W[t, ] <- current_w
  }
  list(name = "13_dro_wasserstein", W = W,
       desc = sprintf("DRO Wasserstein eps=%.2f (Esfahani-Kuhn 2018, eps^2*I regularization)", eps))
}

# 14. Black-Litterman dynamic (regime view)
# Prior: market-cap-implied or static admit. View: CRISIS regime str1715 underperform.
method_14_blackliter_regime <- function(joint, refit_every=12, lookback=60) {
  n <- nrow(joint)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  W[1, ] <- c(0.50, 0.20, 0.25, 0.05)
  current_w <- W[1, ]
  prior_w <- c(0.50, 0.20, 0.25, 0.05)  # equilibrium
  lambda_market <- 2.0
  for (t in 2:n) {
    start <- max(1, t - lookback)
    if (t %% refit_every == 0 && t - start >= 24) {
      R_hist <- as.matrix(joint[start:(t-1), .(str1715, kr10y, tsmom)])
      Sigma_hat <- cov(R_hist)
      # Equilibrium return: pi = lambda * Σ * w_eq (3-sleeve only, cash 0)
      Sigma_4t <- rbind(cbind(Sigma_hat, c(0,0,0)), c(0,0,0,1e-8))
      rownames(Sigma_4t) <- assets; colnames(Sigma_4t) <- assets
      pi_eq <- lambda_market * Sigma_4t %*% prior_w
      # Regime view: if recent regime = CRISIS more frequent than baseline → view says str1715 underperform kr10y by 2%/m
      reg_lag <- joint$regime_lag[start:(t-1)]
      crisis_share <- mean(reg_lag == "CRISIS", na.rm=TRUE)
      if (!is.na(crisis_share) && crisis_share > 0.30) {
        # View P: w_str1715 - w_kr10y, Q: -0.02 (2% underperformance), confidence Ω: tight
        P <- matrix(c(1, -1, 0, 0), nrow=1)
        Q <- -0.02
        Omega <- 0.0001  # high confidence
        tau <- 0.05
        # BL posterior
        M <- solve(solve(tau * Sigma_4t) + t(P) %*% solve(Omega) %*% P) %*%
             (solve(tau * Sigma_4t) %*% pi_eq + t(P) %*% solve(Omega) %*% Q)
        mu_bl <- as.numeric(M)
        # MVO with mu_bl
        if (requireNamespace("quadprog", quietly = TRUE)) {
          Dmat <- 2.0 * Sigma_4t
          dvec <- mu_bl
          Amat <- cbind(rep(1,4), diag(4), -diag(4))
          bvec <- c(1, rep(0,4), -c(0.70, 0.40, 0.40, 0.30))
          sol <- tryCatch(quadprog::solve.QP(Dmat, dvec, Amat, bvec, meq=1),
                          error=function(e) NULL)
          if (!is.null(sol)) {
            current_w <- pmax(0, sol$solution)
            current_w <- current_w / sum(current_w)
          }
        }
      } else {
        # No strong view, stay with prior
        current_w <- prior_w
      }
    }
    W[t, ] <- current_w
  }
  list(name = "14_blackliter_regime", W = W,
       desc = "Black-Litterman dynamic regime view (CRISIS share > 30% → str1715 underperform view)")
}

# 15. Kelly criterion clipped
method_15_kelly_clipped <- function(joint, lookback=60, refit_every=12) {
  n <- nrow(joint)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  W[1, ] <- c(0.50, 0.20, 0.25, 0.05)
  current_w <- W[1, ]
  for (t in 2:n) {
    start <- max(1, t - lookback)
    if (t %% refit_every == 0 && t - start >= 24) {
      R_hist <- as.matrix(joint[start:(t-1), .(str1715, kr10y, tsmom)])
      mu_hat <- colMeans(R_hist)
      Sigma_hat <- cov(R_hist)
      # Kelly: w = Σ^(-1) * μ
      Sigma_inv <- tryCatch(solve(Sigma_hat), error=function(e) NULL)
      if (!is.null(Sigma_inv)) {
        w_kelly <- as.numeric(Sigma_inv %*% mu_hat)
        names(w_kelly) <- assets3
        # Clip [0, 0.50]
        w_kelly <- pmax(0, pmin(w_kelly, 0.50))
        # Add cash 5%, renormalize 3-sleeve to 95%
        if (sum(w_kelly) > 0) w_kelly <- w_kelly / sum(w_kelly) * 0.95
        else w_kelly <- c(str1715=0.50, kr10y=0.20, tsmom=0.25) / sum(c(0.50, 0.20, 0.25)) * 0.95
        w_4 <- c(w_kelly, cash=0.05)
        w_4 <- w_4[assets]
        w_4 <- w_4 / sum(w_4)
        current_w <- w_4
      }
    }
    W[t, ] <- current_w
  }
  list(name = "15_kelly_clipped", W = W,
       desc = "Kelly criterion clipped [0, 0.50] per sleeve, rolling 60m")
}

# ─── PARALLEL EXECUTION ──────────────────────────────────────────────────
methods <- list(
  method_01_static_baseline,
  method_02_static_ew4,
  method_03_mvo_rolling,
  method_04_hrp_static,
  method_05_hrp_rolling,
  method_06_erc_rolling,
  method_07_regime_4state_crisis,
  method_08_regime_2state_simple,
  method_09_regime_2state_aggr,
  method_10_vol_target_inverse,
  method_11_cvar_lp_min,
  method_12_max_sharpe_rolling,
  method_13_dro_wasserstein,
  method_14_blackliter_regime,
  method_15_kelly_clipped
)

cat("\n=== Running method comparison (sequential for reproducibility) ===\n")
results <- list()
t0 <- Sys.time()
for (i in seq_along(methods)) {
  cat(sprintf("[%d/%d] %s\n", i, length(methods), as.character(substitute(methods[[i]]))))
  fn <- methods[[i]]
  res <- tryCatch(fn(joint), error = function(e) list(name=paste0("err_",i), W=NULL, error=conditionMessage(e)))
  results[[i]] <- res
}
t1 <- Sys.time()
cat(sprintf("\nTotal elapsed: %.1f seconds\n", as.numeric(difftime(t1, t0, units="secs"))))

# ─── EVALUATE ────────────────────────────────────────────────────────────
eval_table <- data.frame(
  method = character(),
  desc = character(),
  SR_gross = numeric(),
  SR_net = numeric(),
  CAGR = numeric(),
  MDD = numeric(),
  Sortino = numeric(),
  Calmar = numeric(),
  AnnVol = numeric(),
  Turnover_yr = numeric(),
  stringsAsFactors = FALSE
)

for (res in results) {
  if (is.null(res$W)) next
  r_gross <- composite_ret(res$W, joint)
  r_net <- net_ret_after_cost(r_gross, res$W)
  m_gross <- perf_metrics(r_gross)
  m_net <- perf_metrics(r_net)
  to <- turnover_calc(res$W)
  eval_table <- rbind(eval_table, data.frame(
    method = res$name,
    desc = substr(res$desc, 1, 80),
    SR_gross = round(m_gross$SR, 4),
    SR_net = round(m_net$SR, 4),
    CAGR = round(m_net$CAGR, 4),
    MDD = round(m_net$MDD, 4),
    Sortino = round(m_net$Sortino, 4),
    Calmar = round(m_net$Calmar, 4),
    AnnVol = round(m_net$AnnVol, 4),
    Turnover_yr = round(to, 4),
    stringsAsFactors = FALSE
  ))
}

cat("\n=== Method Comparison Table (Joint 135m, net 15bps) ===\n")
eval_table <- eval_table[order(-eval_table$SR_net), ]
print(eval_table)

write.csv(eval_table, "stage_artifacts/WT_D20260511_002/method_comparison_table.csv", row.names=FALSE)
saveRDS(list(results=results, eval_table=eval_table, joint=joint),
        "stage_artifacts/WT_D20260511_002/dynamic_comparison_results.rds")

cat("\nSaved: stage_artifacts/WT_D20260511_002/method_comparison_table.csv\n")
cat("Saved: stage_artifacts/WT_D20260511_002/dynamic_comparison_results.rds\n")
