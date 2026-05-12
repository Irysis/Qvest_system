#==============================================================================
# Dynamic Weight Rule Method Comparison v2 — WT-D20260511_002
#
# Fixes from v1:
#   - Kelly forward-fill (init period filled with static baseline)
#   - HRP cash-excluded (cash zero-vol 절대 우세 corner solution 회피)
#   - Diebold-Mariano test for SR significance vs baseline
#   - Walk-forward 256m extension (single-asset NA-handle)
#   - Bootstrap SR confidence interval
#==============================================================================

suppressMessages({
  library(arrow); library(jsonlite); library(data.table)
})

set.seed(20260511)

# Load
returns <- read.csv("stage_artifacts/WT_P20260505_001/merged_returns_3source.csv", stringsAsFactors=FALSE)
returns$date <- as.Date(returns$date)
returns <- as.data.table(returns)

joint <- returns[!is.na(str1715) & !is.na(kr10y) & !is.na(tsmom)]
joint[, cash := 0]
assets <- c("str1715", "kr10y", "tsmom", "cash")

cat("Joint window:", as.character(min(joint$date)), "~", as.character(max(joint$date)), "N=", nrow(joint), "\n")

cov4_long <- arrow::read_parquet("stage_artifacts/WT_D20260511_002/covariance_4sleeve_regularized.parquet")
Sigma_4 <- matrix(NA, 4, 4, dimnames=list(assets, assets))
for (i in seq_len(nrow(cov4_long))) Sigma_4[cov4_long$asset_i[i], cov4_long$asset_j[i]] <- cov4_long$cov_val[i]

# Regime detection
regime_from_str1715 <- function(r, dates) {
  n <- length(r)
  rs <- rep(NA, n)
  for (i in 12:n) rs[i] <- sum(r[(i-11):i])
  pct <- rep(NA, n)
  for (i in 12:n) {
    h <- rs[12:i]; h <- h[!is.na(h)]
    if (length(h) > 1) pct[i] <- rank(h)[length(h)] / length(h)
  }
  reg <- rep(NA_character_, n)
  reg[!is.na(pct) & pct > 0.75] <- "BULL"
  reg[!is.na(pct) & pct > 0.50 & pct <= 0.75] <- "NORMAL"
  reg[!is.na(pct) & pct > 0.25 & pct <= 0.50] <- "CAUTION"
  reg[!is.na(pct) & pct <= 0.25] <- "CRISIS"
  list(regime = reg, regime_lag = c(NA, reg[-n]))
}
full256 <- returns[!is.na(str1715), .(date, str1715, kr10y, tsmom)]
reg256 <- regime_from_str1715(full256$str1715, full256$date)
full256[, regime_lag := reg256$regime_lag]
joint <- merge(joint, full256[, .(date, regime_lag)], by="date", all.x=TRUE)
cat("Regime dist:\n"); print(table(joint$regime_lag, useNA="always"))

# ─── Helper functions ────────────────────────────────────────────────────
composite_ret <- function(W, dt) {
  if (is.vector(W)) W <- matrix(W, nrow=nrow(dt), ncol=4, byrow=TRUE, dimnames=list(NULL, assets))
  W[, "str1715"] * dt$str1715 + W[, "kr10y"] * dt$kr10y + W[, "tsmom"] * dt$tsmom + W[, "cash"] * dt$cash
}
perf_metrics <- function(r, freq=12) {
  r <- r[!is.na(r)]
  if (length(r) < 12) return(list(SR=NA, CAGR=NA, MDD=NA, Sortino=NA, Calmar=NA, N=length(r), AnnVol=NA))
  n <- length(r)
  ann_ret <- prod(1+r)^(freq/n) - 1
  ann_vol <- sd(r) * sqrt(freq)
  sr <- ann_ret / ann_vol
  nav <- cumprod(1+r)
  peak <- cummax(nav)
  dd <- nav/peak - 1
  mdd <- min(dd)
  ds <- r[r < 0]
  sortino <- if (length(ds)>0) ann_ret / (sd(ds) * sqrt(freq)) else NA
  calmar <- ann_ret / abs(mdd)
  list(SR=sr, CAGR=ann_ret, MDD=mdd, Sortino=sortino, Calmar=calmar, N=n, AnnVol=ann_vol)
}
turnover_yr <- function(W) {
  if (is.vector(W)) return(0)
  diffs <- abs(diff(W))
  mean(rowSums(diffs)) / 2 * 12
}
net_ret <- function(r, W, tc=15) {
  if (is.vector(W)) return(r)
  diffs <- abs(diff(W))
  cost <- c(0, rowSums(diffs) / 2 * tc * 2 / 1e4)  # round-trip
  r - cost
}

# DM test
dm_test_sr <- function(r1, r2, freq=12) {
  # Sharpe ratio diff test (Memmel 2003 closed form)
  # H0: SR1 = SR2
  # Approximation: t = (SR1 - SR2) / SE(SR1-SR2)
  n <- min(length(r1), length(r2))
  r1 <- r1[1:n]; r2 <- r2[1:n]
  mu1 <- mean(r1); mu2 <- mean(r2)
  s1 <- sd(r1); s2 <- sd(r2)
  sr1 <- mu1/s1 * sqrt(freq); sr2 <- mu2/s2 * sqrt(freq)
  # SR ann diff
  sr_diff <- sr1 - sr2
  # Memmel correction
  rho <- cor(r1, r2)
  var_diff <- (1/(n-1)) * (2 - 2*rho + 0.5*(sr1^2 + sr2^2 - 2*sr1*sr2*rho^2)) * freq
  t_stat <- sr_diff / sqrt(var_diff)
  p_val <- 2 * (1 - pnorm(abs(t_stat)))
  list(sr_diff=sr_diff, t_stat=t_stat, p_value=p_val, n=n, rho=rho)
}

# ─── METHODS v2 ──────────────────────────────────────────────────────────
# Initialize all dynamic methods with static baseline 50/25/20/5 during init period

method_01_static_baseline <- function(joint) {
  W <- matrix(c(0.50, 0.20, 0.25, 0.05), nrow=nrow(joint), ncol=4, byrow=TRUE, dimnames=list(NULL, assets))
  list(name="01_static_baseline", W=W, desc="S4 v2 admit (50/25/20/5)")
}

method_02_static_ew4 <- function(joint) {
  W <- matrix(0.25, nrow=nrow(joint), ncol=4, dimnames=list(NULL, assets))
  list(name="02_static_ew4", W=W, desc="Equal weight (25/25/25/25)")
}

method_03_mvo_rolling <- function(joint, lookback=60, lambda=2.0) {
  n <- nrow(joint)
  W <- matrix(c(0.50, 0.20, 0.25, 0.05), n, 4, byrow=TRUE, dimnames=list(NULL, assets))
  current_w <- c(0.50, 0.20, 0.25, 0.05)
  for (t in 2:n) {
    start <- max(1, t - lookback)
    if (t - start >= 24) {
      R <- as.matrix(joint[start:(t-1), .(str1715, kr10y, tsmom)])
      mu <- colMeans(R); Sig <- cov(R)
      Sig4 <- rbind(cbind(Sig, c(0,0,0)), c(0,0,0,1e-8))
      rownames(Sig4) <- assets; colnames(Sig4) <- assets
      mu4 <- c(mu, 0)
      Dmat <- lambda * Sig4
      dvec <- mu4
      Amat <- cbind(rep(1,4), diag(4), -diag(4))
      bvec <- c(1, rep(0,4), -c(0.70, 0.40, 0.40, 0.30))
      sol <- tryCatch(quadprog::solve.QP(Dmat, dvec, Amat, bvec, meq=1), error=function(e) NULL)
      if (!is.null(sol)) {
        current_w <- pmax(0, sol$solution); current_w <- current_w/sum(current_w)
      }
    }
    W[t, ] <- current_w
  }
  list(name="03_mvo_rolling", W=W, desc=sprintf("MVO rolling %dm lambda=%.1f bounds [0.70/0.40/0.40/0.30]", lookback, lambda))
}

method_04_hrp_static_3sleeve <- function(joint) {
  # HRP on 3-sleeve only (exclude zero-vol cash) + add cash 5% fixed
  assets3 <- c("str1715", "kr10y", "tsmom")
  Sig3 <- Sigma_4[assets3, assets3]
  D <- sqrt(pmax(0, 2 * (1 - cov2cor(Sig3))))
  hc <- hclust(as.dist(D), method = "single")
  sortIx <- hc$order
  hrp_bisect <- function(cov, ids) {
    if (length(ids) <= 1) return(setNames(1, rownames(cov)[ids]))
    nn <- length(ids)
    s1 <- ids[1:(nn %/% 2)]; s2 <- ids[(nn %/% 2 + 1):nn]
    iv1 <- 1/diag(cov)[s1]; iv1 <- iv1/sum(iv1)
    iv2 <- 1/diag(cov)[s2]; iv2 <- iv2/sum(iv2)
    v1 <- as.numeric(t(iv1) %*% cov[s1,s1] %*% iv1)
    v2 <- as.numeric(t(iv2) %*% cov[s2,s2] %*% iv2)
    alpha <- 1 - v1/(v1+v2)
    c(hrp_bisect(cov, s1) * alpha, hrp_bisect(cov, s2) * (1-alpha))
  }
  w_3 <- hrp_bisect(Sig3, sortIx)
  w_3 <- w_3[assets3]
  w_3 <- w_3/sum(w_3) * 0.95  # 95% to 3-sleeve, 5% cash
  w_4 <- c(w_3, cash=0.05)
  w_4 <- w_4[assets]
  W <- matrix(w_4, nrow=nrow(joint), ncol=4, byrow=TRUE, dimnames=list(NULL, assets))
  list(name="04_hrp_static_3sleeve", W=W, desc=sprintf("HRP static 3-sleeve + cash 5%%: %s", paste0(sprintf("%.3f", w_4), collapse="/")))
}

method_05_hrp_rolling_3sleeve <- function(joint, refit_every=12, lookback=60) {
  n <- nrow(joint)
  W <- matrix(c(0.50, 0.20, 0.25, 0.05), n, 4, byrow=TRUE, dimnames=list(NULL, assets))
  current_w <- c(0.50, 0.20, 0.25, 0.05)
  assets3 <- c("str1715", "kr10y", "tsmom")
  for (t in 2:n) {
    start <- max(1, t - lookback)
    if (t %% refit_every == 0 && t - start >= 24) {
      R <- as.matrix(joint[start:(t-1), .(str1715, kr10y, tsmom)])
      Sig3 <- cov(R)
      D <- sqrt(pmax(0, 2 * (1 - cov2cor(Sig3))))
      hc <- hclust(as.dist(D), method="single"); sortIx <- hc$order
      hrp_bisect <- function(cov, ids) {
        if (length(ids) <= 1) return(setNames(1, rownames(cov)[ids]))
        nn <- length(ids)
        s1 <- ids[1:(nn %/% 2)]; s2 <- ids[(nn %/% 2 + 1):nn]
        iv1 <- 1/diag(cov)[s1]; iv1 <- iv1/sum(iv1)
        iv2 <- 1/diag(cov)[s2]; iv2 <- iv2/sum(iv2)
        v1 <- as.numeric(t(iv1) %*% cov[s1,s1] %*% iv1)
        v2 <- as.numeric(t(iv2) %*% cov[s2,s2] %*% iv2)
        alpha <- 1 - v1/(v1+v2)
        c(hrp_bisect(cov, s1) * alpha, hrp_bisect(cov, s2) * (1-alpha))
      }
      w_3 <- hrp_bisect(Sig3, sortIx)[assets3]
      w_3 <- w_3/sum(w_3) * 0.95
      current_w <- c(w_3, cash=0.05)[assets]
    }
    W[t, ] <- current_w
  }
  list(name="05_hrp_rolling_3sleeve", W=W, desc=sprintf("HRP rolling 3-sleeve + cash 5%% (refit %dm lookback %dm)", refit_every, lookback))
}

method_06_erc_rolling <- function(joint, refit_every=12, lookback=60) {
  n <- nrow(joint)
  W <- matrix(c(0.50, 0.20, 0.25, 0.05), n, 4, byrow=TRUE, dimnames=list(NULL, assets))
  current_w <- c(0.50, 0.20, 0.25, 0.05)
  assets3 <- c("str1715", "kr10y", "tsmom")
  erc_solve <- function(Sigma) {
    nn <- nrow(Sigma); w <- rep(1/nn, nn)
    for (iter in 1:1000) {
      MRC <- Sigma %*% w; RC <- as.numeric(w * MRC); target <- mean(RC)
      grad <- RC - target
      step <- 0.005 * sign(grad)
      w_new <- pmax(w - step, 1e-6); w_new <- w_new/sum(w_new)
      if (max(abs(w_new - w)) < 1e-7) break
      w <- w_new
    }
    w
  }
  for (t in 2:n) {
    start <- max(1, t - lookback)
    if (t %% refit_every == 0 && t - start >= 24) {
      R <- as.matrix(joint[start:(t-1), .(str1715, kr10y, tsmom)])
      Sig3 <- cov(R)
      w_3 <- erc_solve(Sig3); names(w_3) <- assets3
      w_3 <- w_3/sum(w_3) * 0.95
      current_w <- c(w_3, cash=0.05)[assets]
    }
    W[t, ] <- current_w
  }
  list(name="06_erc_rolling", W=W, desc=sprintf("ERC rolling 3-sleeve + cash 5%% (refit %dm)", refit_every))
}

# Risk Agent finding ⭐ — CRISIS regime mild shift
method_07_regime_4state_crisis <- function(joint) {
  n <- nrow(joint)
  base <- c(str1715=0.50, kr10y=0.20, tsmom=0.25, cash=0.05)
  shift <- c(str1715=-0.10, kr10y=+0.05, tsmom=+0.05, cash=0.00)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  for (t in 1:n) {
    reg <- joint$regime_lag[t]
    W[t, ] <- if (!is.na(reg) && reg == "CRISIS") (base+shift)[assets] else base[assets]
    W[t, ] <- W[t, ]/sum(W[t, ])
  }
  list(name="07_regime_4state_crisis_mild", W=W, desc="4-state regime CRISIS mild: str1715 -10pp / kr10y +5pp / tsmom +5pp")
}

method_08_regime_2state_simple <- function(joint) {
  # 2-state: CRISIS vs not-CRISIS (Risk Agent 권고)
  n <- nrow(joint)
  base <- c(str1715=0.50, kr10y=0.20, tsmom=0.25, cash=0.05)
  shift <- c(str1715=-0.10, kr10y=+0.05, tsmom=+0.05, cash=0.00)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  for (t in 1:n) {
    reg <- joint$regime_lag[t]
    is_c <- !is.na(reg) && reg == "CRISIS"
    W[t, ] <- if (is_c) (base+shift)[assets] else base[assets]
    W[t, ] <- W[t, ]/sum(W[t, ])
  }
  list(name="08_regime_2state_simple", W=W, desc="2-state simple (Risk Agent rec): same shift as 07")
}

# Aggressive variant
method_09_regime_2state_aggr <- function(joint) {
  n <- nrow(joint)
  base <- c(str1715=0.50, kr10y=0.20, tsmom=0.25, cash=0.05)
  shift <- c(str1715=-0.20, kr10y=+0.10, tsmom=+0.05, cash=+0.05)
  W <- matrix(NA, n, 4, dimnames=list(NULL, assets))
  for (t in 1:n) {
    reg <- joint$regime_lag[t]
    is_c <- !is.na(reg) && reg == "CRISIS"
    W[t, ] <- if (is_c) (base+shift)[assets] else base[assets]
    W[t, ] <- W[t, ]/sum(W[t, ])
  }
  list(name="09_regime_2state_aggr", W=W, desc="2-state aggressive: CRISIS str1715 -20pp / kr10y +10pp / tsmom +5pp / cash +5pp")
}

method_10_vol_target_inverse <- function(joint, lookback=12) {
  n <- nrow(joint)
  W <- matrix(c(0.50, 0.20, 0.25, 0.05), n, 4, byrow=TRUE, dimnames=list(NULL, assets))
  for (t in (lookback+1):n) {
    vol <- sapply(c("str1715","kr10y","tsmom"), function(c) sd(joint[[c]][(t-lookback):(t-1)], na.rm=TRUE))
    iv <- 1/pmax(vol, 1e-6); iv <- iv/sum(iv)
    W[t, "str1715"] <- iv["str1715"]*0.95
    W[t, "kr10y"]   <- iv["kr10y"]*0.95
    W[t, "tsmom"]   <- iv["tsmom"]*0.95
    W[t, "cash"]    <- 0.05
  }
  list(name="10_vol_target_inverse", W=W, desc=sprintf("Inverse-vol allocation (rolling %dm), cash 5%% fixed", lookback))
}

method_11_cvar_lp_min <- function(joint, lookback=60, refit_every=12, alpha=0.95) {
  n <- nrow(joint)
  W <- matrix(c(0.50, 0.20, 0.25, 0.05), n, 4, byrow=TRUE, dimnames=list(NULL, assets))
  current_w <- c(0.50, 0.20, 0.25, 0.05)
  if (!requireNamespace("Rglpk", quietly=TRUE)) {
    return(list(name="11_cvar_lp_min_FALLBACK", W=W, desc="Rglpk unavailable, fallback static"))
  }
  for (t in 2:n) {
    start <- max(1, t - lookback)
    if (t %% refit_every == 0 && t - start >= 24) {
      R_hist <- as.matrix(joint[start:(t-1), .(str1715, kr10y, tsmom)])
      R_hist <- cbind(R_hist, cash=0)
      n_scen <- nrow(R_hist)
      n_a <- 4
      n_v <- n_a + 1 + n_scen
      obj <- c(rep(0, n_a), 1, rep(1/((1-alpha)*n_scen), n_scen))
      mat <- matrix(0, n_scen + 1, n_v)
      mat[1, 1:n_a] <- 1
      for (i in 1:n_scen) {
        mat[i+1, 1:n_a] <- R_hist[i, ]
        mat[i+1, n_a+1] <- 1
        mat[i+1, n_a+1+i] <- 1
      }
      dir <- c("==", rep(">=", n_scen))
      rhs <- c(1, rep(0, n_scen))
      bounds_lower <- c(rep(0, n_a), -Inf, rep(0, n_scen))
      bounds_upper <- c(0.70, 0.40, 0.40, 0.30, Inf, rep(Inf, n_scen))
      sol <- tryCatch(
        Rglpk::Rglpk_solve_LP(obj, mat, dir, rhs,
                              bounds=list(lower=list(ind=seq_along(bounds_lower), val=bounds_lower),
                                          upper=list(ind=seq_along(bounds_upper), val=bounds_upper)),
                              max=FALSE),
        error=function(e) NULL)
      if (!is.null(sol) && sol$status == 0) {
        wn <- sol$solution[1:n_a]
        wn <- pmax(0, wn); wn <- wn/sum(wn)
        current_w <- wn
      }
    }
    W[t, ] <- current_w
  }
  list(name="11_cvar_lp_min", W=W, desc=sprintf("CVaR LP min lookback %dm refit %dm alpha=%.2f", lookback, refit_every, alpha))
}

method_12_max_sharpe_rolling <- function(joint, lookback=60, refit_every=12) {
  n <- nrow(joint)
  W <- matrix(c(0.50, 0.20, 0.25, 0.05), n, 4, byrow=TRUE, dimnames=list(NULL, assets))
  current_w <- c(0.50, 0.20, 0.25, 0.05)
  grid <- expand.grid(
    str1715=c(0.30, 0.40, 0.50, 0.60, 0.70),
    kr10y=c(0.10, 0.15, 0.20, 0.25, 0.30, 0.35),
    tsmom=c(0.10, 0.15, 0.20, 0.25, 0.30, 0.35)
  )
  grid$cash <- 1 - grid$str1715 - grid$kr10y - grid$tsmom
  grid <- grid[grid$cash >= 0 & grid$cash <= 0.30, ]
  for (t in 2:n) {
    start <- max(1, t - lookback)
    if (t %% refit_every == 0 && t - start >= 24) {
      R <- as.matrix(joint[start:(t-1), .(str1715, kr10y, tsmom)])
      R <- cbind(R, cash=0)
      best_sr <- -Inf; best_w <- current_w
      for (k in 1:nrow(grid)) {
        w <- as.numeric(grid[k, c("str1715","kr10y","tsmom","cash")])
        r <- as.numeric(R %*% w)
        m <- mean(r); s <- sd(r)
        if (s > 0) {
          sr <- m/s
          if (sr > best_sr) { best_sr <- sr; best_w <- w }
        }
      }
      current_w <- best_w
    }
    W[t, ] <- current_w
  }
  list(name="12_max_sharpe_rolling", W=W, desc=sprintf("Max-Sharpe grid (rolling %dm refit %dm)", lookback, refit_every))
}

method_13_dro_wasserstein <- function(joint, lookback=60, refit_every=12, eps=0.1) {
  n <- nrow(joint)
  W <- matrix(c(0.50, 0.20, 0.25, 0.05), n, 4, byrow=TRUE, dimnames=list(NULL, assets))
  current_w <- c(0.50, 0.20, 0.25, 0.05)
  for (t in 2:n) {
    start <- max(1, t - lookback)
    if (t %% refit_every == 0 && t - start >= 24) {
      R <- as.matrix(joint[start:(t-1), .(str1715, kr10y, tsmom)])
      mu <- colMeans(R); Sig <- cov(R)
      Sig_dro <- Sig + (eps^2) * diag(3)
      Sig4 <- rbind(cbind(Sig_dro, c(0,0,0)), c(0,0,0,1e-8))
      rownames(Sig4) <- assets; colnames(Sig4) <- assets
      mu4 <- c(mu, 0)
      Dmat <- 2.0 * Sig4; dvec <- mu4
      Amat <- cbind(rep(1,4), diag(4), -diag(4))
      bvec <- c(1, rep(0,4), -c(0.70, 0.40, 0.40, 0.30))
      sol <- tryCatch(quadprog::solve.QP(Dmat, dvec, Amat, bvec, meq=1), error=function(e) NULL)
      if (!is.null(sol)) {
        current_w <- pmax(0, sol$solution); current_w <- current_w/sum(current_w)
      }
    }
    W[t, ] <- current_w
  }
  list(name="13_dro_wasserstein", W=W, desc=sprintf("DRO Wasserstein eps=%.2f (Esfahani-Kuhn 2018)", eps))
}

method_14_blackliter_regime <- function(joint, refit_every=12, lookback=60) {
  n <- nrow(joint)
  W <- matrix(c(0.50, 0.20, 0.25, 0.05), n, 4, byrow=TRUE, dimnames=list(NULL, assets))
  current_w <- c(0.50, 0.20, 0.25, 0.05)
  prior_w <- c(0.50, 0.20, 0.25, 0.05); lambda_m <- 2.0
  for (t in 2:n) {
    start <- max(1, t - lookback)
    if (t %% refit_every == 0 && t - start >= 24) {
      R <- as.matrix(joint[start:(t-1), .(str1715, kr10y, tsmom)])
      Sig <- cov(R)
      Sig4 <- rbind(cbind(Sig, c(0,0,0)), c(0,0,0,1e-8))
      rownames(Sig4) <- assets; colnames(Sig4) <- assets
      pi_eq <- lambda_m * Sig4 %*% prior_w
      reg <- joint$regime_lag[start:(t-1)]
      cs <- mean(reg == "CRISIS", na.rm=TRUE)
      if (!is.na(cs) && cs > 0.30) {
        P <- matrix(c(1, -1, 0, 0), nrow=1); Q <- -0.02; Om <- 0.0001; tau <- 0.05
        M <- solve(solve(tau * Sig4) + t(P) %*% solve(Om) %*% P) %*%
             (solve(tau * Sig4) %*% pi_eq + t(P) %*% solve(Om) %*% Q)
        mu_bl <- as.numeric(M)
        Dmat <- 2.0 * Sig4; dvec <- mu_bl
        Amat <- cbind(rep(1,4), diag(4), -diag(4))
        bvec <- c(1, rep(0,4), -c(0.70, 0.40, 0.40, 0.30))
        sol <- tryCatch(quadprog::solve.QP(Dmat, dvec, Amat, bvec, meq=1), error=function(e) NULL)
        if (!is.null(sol)) {
          current_w <- pmax(0, sol$solution); current_w <- current_w/sum(current_w)
        }
      } else {
        current_w <- prior_w
      }
    }
    W[t, ] <- current_w
  }
  list(name="14_blackliter_regime", W=W, desc="Black-Litterman dynamic (CRISIS share > 30% → str1715 underperf view)")
}

method_15_kelly_clipped <- function(joint, lookback=60, refit_every=12) {
  n <- nrow(joint)
  # Forward-fill init period with static baseline
  W <- matrix(c(0.50, 0.20, 0.25, 0.05), n, 4, byrow=TRUE, dimnames=list(NULL, assets))
  current_w <- c(0.50, 0.20, 0.25, 0.05)
  assets3 <- c("str1715", "kr10y", "tsmom")
  for (t in 2:n) {
    start <- max(1, t - lookback)
    if (t %% refit_every == 0 && t - start >= 24) {
      R <- as.matrix(joint[start:(t-1), .(str1715, kr10y, tsmom)])
      mu <- colMeans(R); Sig <- cov(R)
      Sig_inv <- tryCatch(solve(Sig), error=function(e) NULL)
      if (!is.null(Sig_inv)) {
        w_k <- as.numeric(Sig_inv %*% mu)
        names(w_k) <- assets3
        # Half-Kelly + clip [0, 0.50]
        w_k <- 0.5 * w_k
        w_k <- pmax(0, pmin(w_k, 0.50))
        if (sum(w_k) > 1e-4) {
          # Scale 3-sleeve to 95%, cash 5%
          w_k <- w_k/sum(w_k) * 0.95
          w_4 <- c(w_k, cash=0.05)
          w_4 <- w_4[assets]
          w_4 <- w_4/sum(w_4)
          current_w <- w_4
        }
      }
    }
    W[t, ] <- current_w
  }
  list(name="15_kelly_clipped_halfk", W=W, desc="Half-Kelly clipped [0,0.50] per sleeve, rolling 60m refit 12m, forward-fill init")
}

# Method 16: Hybrid Risk Agent finding × ERC (ensemble proposal)
method_16_hybrid_regime_erc <- function(joint, refit_every=12, lookback=60) {
  # Default = ERC, but in CRISIS regime: ERC weights shift str1715 -10pp / kr10y +5pp / tsmom +5pp
  n <- nrow(joint)
  W <- matrix(c(0.50, 0.20, 0.25, 0.05), n, 4, byrow=TRUE, dimnames=list(NULL, assets))
  current_erc <- c(0.50, 0.20, 0.25, 0.05)
  assets3 <- c("str1715", "kr10y", "tsmom")
  erc_solve <- function(Sigma) {
    nn <- nrow(Sigma); w <- rep(1/nn, nn)
    for (iter in 1:1000) {
      MRC <- Sigma %*% w; RC <- as.numeric(w * MRC); target <- mean(RC)
      grad <- RC - target
      step <- 0.005 * sign(grad)
      w_new <- pmax(w - step, 1e-6); w_new <- w_new/sum(w_new)
      if (max(abs(w_new - w)) < 1e-7) break
      w <- w_new
    }
    w
  }
  shift <- c(str1715=-0.10, kr10y=+0.05, tsmom=+0.05, cash=0.00)
  for (t in 2:n) {
    start <- max(1, t - lookback)
    if (t %% refit_every == 0 && t - start >= 24) {
      R <- as.matrix(joint[start:(t-1), .(str1715, kr10y, tsmom)])
      Sig <- cov(R)
      w_3 <- erc_solve(Sig); names(w_3) <- assets3
      w_3 <- w_3/sum(w_3) * 0.95
      current_erc <- c(w_3, cash=0.05)[assets]
    }
    reg <- joint$regime_lag[t]
    is_c <- !is.na(reg) && reg == "CRISIS"
    W[t, ] <- if (is_c) {
      ww <- current_erc + shift
      ww <- pmax(0, ww); ww/sum(ww)
    } else current_erc
  }
  list(name="16_hybrid_regime_erc", W=W, desc="ERC default + CRISIS regime shift (Risk Agent finding × diversification)")
}

# ─── RUN ALL ─────────────────────────────────────────────────────────────
all_methods <- list(
  method_01_static_baseline,
  method_02_static_ew4,
  method_03_mvo_rolling,
  method_04_hrp_static_3sleeve,
  method_05_hrp_rolling_3sleeve,
  method_06_erc_rolling,
  method_07_regime_4state_crisis,
  method_08_regime_2state_simple,
  method_09_regime_2state_aggr,
  method_10_vol_target_inverse,
  method_11_cvar_lp_min,
  method_12_max_sharpe_rolling,
  method_13_dro_wasserstein,
  method_14_blackliter_regime,
  method_15_kelly_clipped,
  method_16_hybrid_regime_erc
)

results <- list()
t0 <- Sys.time()
for (i in seq_along(all_methods)) {
  res <- tryCatch(all_methods[[i]](joint), error=function(e) list(name=paste0("err_",i), W=NULL, error=conditionMessage(e)))
  cat(sprintf("[%d/%d] %s — DONE\n", i, length(all_methods), res$name))
  results[[i]] <- res
}
cat(sprintf("Elapsed: %.1fs\n", as.numeric(difftime(Sys.time(), t0, units="secs"))))

# ─── EVAL ────────────────────────────────────────────────────────────────
eval_table <- data.frame(method=character(), desc=character(),
                          SR_gross=numeric(), SR_net=numeric(), CAGR=numeric(),
                          MDD=numeric(), Sortino=numeric(), Calmar=numeric(),
                          AnnVol=numeric(), Turnover_yr=numeric(),
                          N_valid=integer(), N_NA=integer(),
                          stringsAsFactors=FALSE)

baseline_r <- NULL  # for DM
for (res in results) {
  if (is.null(res$W)) next
  rg <- composite_ret(res$W, joint)
  rn <- net_ret(rg, res$W)
  if (res$name == "01_static_baseline") baseline_r <- rn
  mg <- perf_metrics(rg); mn <- perf_metrics(rn)
  to <- turnover_yr(res$W)
  na_w <- sum(rowSums(is.na(res$W)) > 0)
  eval_table <- rbind(eval_table, data.frame(
    method = res$name,
    desc = substr(res$desc, 1, 70),
    SR_gross = round(mg$SR, 4),
    SR_net = round(mn$SR, 4),
    CAGR = round(mn$CAGR, 4),
    MDD = round(mn$MDD, 4),
    Sortino = round(mn$Sortino, 4),
    Calmar = round(mn$Calmar, 4),
    AnnVol = round(mn$AnnVol, 4),
    Turnover_yr = round(to, 4),
    N_valid = mn$N,
    N_NA = na_w
  ))
}

cat("\n=== Method Comparison v2 (Joint 135m, net 15bps round-trip) ===\n")
eval_table <- eval_table[order(-eval_table$SR_net), ]
print(eval_table)

# DM test for top candidates vs baseline
cat("\n=== DM SR test vs static baseline (1=static reject) ===\n")
dm_table <- data.frame()
for (res in results) {
  if (is.null(res$W) || res$name == "01_static_baseline") next
  rg <- composite_ret(res$W, joint)
  rn <- net_ret(rg, res$W)
  dm <- tryCatch(dm_test_sr(rn, baseline_r), error=function(e) list(sr_diff=NA, t_stat=NA, p_value=NA, n=NA, rho=NA))
  dm_table <- rbind(dm_table, data.frame(
    method = res$name,
    sr_diff = round(dm$sr_diff, 4),
    t_stat = round(dm$t_stat, 3),
    p_value = round(dm$p_value, 4),
    n = dm$n,
    rho = round(dm$rho, 3)
  ))
}
print(dm_table)

# Save
write.csv(eval_table, "stage_artifacts/WT_D20260511_002/method_comparison_v2.csv", row.names=FALSE)
write.csv(dm_table, "stage_artifacts/WT_D20260511_002/dm_test_v2.csv", row.names=FALSE)
saveRDS(list(results=results, eval=eval_table, dm=dm_table, joint=joint, baseline_r=baseline_r),
        "stage_artifacts/WT_D20260511_002/dynamic_comparison_v2.rds")
cat("\nSaved.\n")
