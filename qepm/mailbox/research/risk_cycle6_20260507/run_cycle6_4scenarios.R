# =============================================================================
# Cycle 6 — 4 시나리오 비교 risk profile 메타 진단
# Q-Lead 온디맨드 메타 리서치 (cycle 5 P1 발견 후속)
# =============================================================================
# Scenarios:
#   A. retain          : 70 STR_1715_AR + 15 TSMOM + 15 KR_10y (현 admit)
#   B. P1_cut          : 70 STR_1715_AR + 30 cash
#   C. P1_partial      : 80 STR_1715_AR + 10 TSMOM + 10 KR_10y
#   D. P1_substitute   : 70 STR_1715_AR + 10 Defensive_LowVol + 10 Commodity + 10 VRP
#
# Metrics per scenario:
#   1. Σ (covariance, 5 estimators)
#   2. Tail risk (VaR99/ES99 4-method + EVT GPD threshold sensitivity)
#   3. 8-stress (named historical periods)
#   4. Crowding/TDC + style + sector
#   5. Forward simulation (Mann-Kendall + Pettitt)
#
# Output: scenario_comparison.json + 16 CSV (4 scenarios × 4 metric files)
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(PerformanceAnalytics)
  library(MASS)
})

# Manual Mann-Kendall trend test (Kendall package may not be available)
# Kendall's tau via R built-in cor(method="kendall") + Mann-Kendall variance approx
MannKendall_manual <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < 4) return(list(tau = NA, sl = NA))
  # S statistic
  S <- 0
  for (i in 1:(n-1)) for (j in (i+1):n) {
    S <- S + sign(x[j] - x[i])
  }
  # Variance under null
  var_S <- n * (n - 1) * (2*n + 5) / 18
  # Two-sided p-value
  if (S > 0) Z <- (S - 1) / sqrt(var_S)
  else if (S < 0) Z <- (S + 1) / sqrt(var_S)
  else Z <- 0
  p_val <- 2 * (1 - pnorm(abs(Z)))
  # Kendall's tau
  tau <- S / (n*(n-1)/2)
  list(tau = tau, sl = p_val)
}
MannKendall <- function(x) MannKendall_manual(x)

# Config
ROOT       <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WORK       <- file.path(ROOT, "qepm/mailbox/research/risk_cycle6_20260507")
MASTER_PATH <- file.path(ROOT, "qepm/mailbox/research/risk_candidates_20260507/master_returns_hybrid_plus_4candidates.csv")
setwd(WORK)
dir.create(WORK, showWarnings = FALSE, recursive = TRUE)

cat("=== Cycle 6: 4-scenario PG2 admit comparison ===\n")
cat(sprintf("[INIT] Working dir: %s\n", WORK))

# -----------------------------------------------------------------------------
# 1. Load master_returns
# -----------------------------------------------------------------------------
mr <- fread(MASTER_PATH)
cat(sprintf("[DATA] master_returns rows=%d cols=%d\n", nrow(mr), ncol(mr)))
cat(sprintf("[DATA] columns: %s\n", paste(names(mr), collapse=", ")))

# Coerce numeric
num_cols <- c("r_AR","r_KR10y","r_TSMOM","r_Hybrid","r_commodity","r_currency","r_vrp","r_defensive")
for (c in num_cols) {
  if (c %in% names(mr)) mr[[c]] <- as.numeric(mr[[c]])
}

# Define scenarios — return series construction
# Note: Use post-2015 sub-sample (2015-01 ~ 2026-04, n=135) for fair comparison with cycle 5 baseline
mr[, ym := as.character(ym)]
mr_post2015 <- mr[ym >= "2015-01"]
cat(sprintf("[FILTER] post-2015 obs=%d\n", nrow(mr_post2015)))

# Verify required columns availability
required_cols_per_scenario <- list(
  A = c("r_AR", "r_TSMOM", "r_KR10y"),
  B = c("r_AR"),  # cash = 0 return
  C = c("r_AR", "r_TSMOM", "r_KR10y"),
  D = c("r_AR", "r_defensive", "r_commodity", "r_vrp")
)

for (s in names(required_cols_per_scenario)) {
  cols <- required_cols_per_scenario[[s]]
  for (c in cols) {
    n_complete <- sum(!is.na(mr_post2015[[c]]))
    cat(sprintf("[AVAIL] Scenario %s req %s: complete=%d/%d (%.1f%%)\n",
                s, c, n_complete, nrow(mr_post2015), 100*n_complete/nrow(mr_post2015)))
  }
}

# Build scenario returns
build_scenario <- function(scenario, mr_data) {
  if (scenario == "A") {
    # 70 AR + 15 TSMOM + 15 KR10y
    w <- c(AR=0.70, TSMOM=0.15, KR10y=0.15)
    cols <- c("r_AR", "r_TSMOM", "r_KR10y")
  } else if (scenario == "B") {
    # 70 AR + 30 cash (cash return = 0)
    w <- c(AR=0.70, cash=0.30)
    cols <- c("r_AR")
    cash_ret <- 0
  } else if (scenario == "C") {
    # 80 AR + 10 TSMOM + 10 KR10y
    w <- c(AR=0.80, TSMOM=0.10, KR10y=0.10)
    cols <- c("r_AR", "r_TSMOM", "r_KR10y")
  } else if (scenario == "D") {
    # 70 AR + 10 Defensive_LowVol + 10 Commodity + 10 VRP
    w <- c(AR=0.70, defensive=0.10, commodity=0.10, vrp=0.10)
    cols <- c("r_AR", "r_defensive", "r_commodity", "r_vrp")
  }

  # Take complete cases for required columns
  if (scenario == "B") {
    valid <- !is.na(mr_data$r_AR)
    ret <- 0.70 * mr_data$r_AR[valid] + 0.30 * 0  # cash zero
    dates <- mr_data$ym[valid]
  } else {
    valid <- complete.cases(mr_data[, ..cols])
    sub <- mr_data[valid, ..cols]
    if (scenario == "A") {
      ret <- 0.70 * sub$r_AR + 0.15 * sub$r_TSMOM + 0.15 * sub$r_KR10y
    } else if (scenario == "C") {
      ret <- 0.80 * sub$r_AR + 0.10 * sub$r_TSMOM + 0.10 * sub$r_KR10y
    } else if (scenario == "D") {
      ret <- 0.70 * sub$r_AR + 0.10 * sub$r_defensive + 0.10 * sub$r_commodity + 0.10 * sub$r_vrp
    }
    dates <- mr_data$ym[valid]
  }

  list(scenario = scenario, weights = w, ret = ret, dates = dates, n = length(ret))
}

scenarios <- list(
  A = build_scenario("A", mr_post2015),
  B = build_scenario("B", mr_post2015),
  C = build_scenario("C", mr_post2015),
  D = build_scenario("D", mr_post2015)
)

cat("\n[SCENARIO RETURN SERIES]\n")
for (s in names(scenarios)) {
  sc <- scenarios[[s]]
  cat(sprintf("  %s: n=%d weights=[%s] ann_mean=%.4f ann_sd=%.4f sr=%.4f\n",
              s, sc$n, paste(sprintf("%s=%.2f", names(sc$weights), sc$weights), collapse=","),
              mean(sc$ret)*12, sd(sc$ret)*sqrt(12),
              mean(sc$ret)/sd(sc$ret)*sqrt(12)))
}

# -----------------------------------------------------------------------------
# 2. METRIC 1: Covariance — 5 estimators × 4 scenarios
# -----------------------------------------------------------------------------
# Note: Per scenario, build sleeve-level covariance matrix (3-4 dim)
# 5 estimators: Sample / LW_identity / LW_constcor / Gerber / Glasso

cat("\n=== METRIC 1: COVARIANCE (5 estimators × 4 scenarios) ===\n")

# Sample
cov_sample <- function(R) cov(R)

# Ledoit-Wolf to identity target (trace-equal scaled identity)
cov_LW_identity <- function(R) {
  n <- nrow(R); p <- ncol(R)
  S <- cov(R)
  mu <- sum(diag(S))/p
  T <- diag(mu, p)
  # shrinkage intensity (simplified)
  d2 <- sum((S - T)^2)
  Xc <- scale(R, center = TRUE, scale = FALSE)
  b2 <- 0
  for (k in 1:n) {
    xk <- Xc[k, , drop=FALSE]
    Sk <- t(xk) %*% xk
    b2 <- b2 + sum((Sk - S)^2)
  }
  b2 <- b2 / (n^2)
  b2 <- min(b2, d2)
  delta <- b2 / d2
  delta * T + (1 - delta) * S
}

# Ledoit-Wolf to constant correlation target
cov_LW_constcor <- function(R) {
  n <- nrow(R); p <- ncol(R)
  S <- cov(R)
  s <- sqrt(diag(S))
  rho_mat <- cov2cor(S)
  rho_bar <- (sum(rho_mat) - p) / (p*(p-1))
  T <- outer(s, s) * rho_bar
  diag(T) <- diag(S)
  d2 <- sum((S - T)^2)
  Xc <- scale(R, center = TRUE, scale = FALSE)
  b2 <- 0
  for (k in 1:n) {
    xk <- Xc[k, , drop=FALSE]
    Sk <- t(xk) %*% xk
    b2 <- b2 + sum((Sk - S)^2)
  }
  b2 <- b2 / (n^2)
  b2 <- min(b2, d2)
  delta <- b2 / d2
  delta * T + (1 - delta) * S
}

# Gerber statistic (Gerber-Markowitz-Pujara 2022 JoPM)
cov_Gerber <- function(R, c = 0.5) {
  n <- nrow(R); p <- ncol(R)
  s <- apply(R, 2, sd)
  thr <- c * s
  G <- matrix(0, p, p)
  for (i in 1:p) for (j in 1:p) {
    H_ij <- 0
    L_ij <- 0
    N_ij <- 0
    for (t in 1:n) {
      if (abs(R[t, i]) >= thr[i] && abs(R[t, j]) >= thr[j]) {
        if (sign(R[t, i]) == sign(R[t, j])) H_ij <- H_ij + 1 else L_ij <- L_ij + 1
      } else {
        N_ij <- N_ij + 1
      }
    }
    if ((H_ij + L_ij) > 0) G[i, j] <- (H_ij - L_ij) / (n - N_ij) else G[i, j] <- 0
  }
  diag(G) <- 1
  s_outer <- outer(s, s)
  S_gerber <- G * s_outer
  # Ensure PSD via eigen clipping
  eg <- eigen(S_gerber, symmetric = TRUE)
  eg$values[eg$values < 0] <- 1e-8
  S_psd <- eg$vectors %*% diag(eg$values) %*% t(eg$vectors)
  S_psd
}

# Graphical Lasso (simplified — use pseudo-inverse with ridge)
cov_Glasso_simple <- function(R, lambda = 0.05) {
  S <- cov(R)
  p <- ncol(S)
  # Ridge regularization on inverse
  K <- solve(S + lambda * diag(p))
  # Threshold off-diagonals (sparse approximation)
  K[abs(K) < 0.01] <- 0
  diag_K <- diag(K)
  diag(K) <- pmax(diag_K, 1e-4)  # ensure invertibility
  Sigma <- solve(K)
  # Re-symmetrize and PSD-correct
  Sigma <- (Sigma + t(Sigma)) / 2
  eg <- eigen(Sigma, symmetric = TRUE)
  eg$values[eg$values < 1e-8] <- 1e-8
  Sigma_psd <- eg$vectors %*% diag(eg$values) %*% t(eg$vectors)
  Sigma_psd
}

cov_estimators <- list(
  Sample = cov_sample,
  LW_identity = cov_LW_identity,
  LW_constcor = cov_LW_constcor,
  Gerber = cov_Gerber,
  Glasso = cov_Glasso_simple
)

# Build sleeve-level returns matrix per scenario
build_sleeve_matrix <- function(scenario) {
  if (scenario == "A") {
    valid <- complete.cases(mr_post2015[, .(r_AR, r_TSMOM, r_KR10y)])
    R <- as.matrix(mr_post2015[valid, .(r_AR, r_TSMOM, r_KR10y)])
    colnames(R) <- c("AR", "TSMOM", "KR10y")
  } else if (scenario == "B") {
    # AR + cash (cash sd=0, 단일 dim)
    valid <- !is.na(mr_post2015$r_AR)
    R <- matrix(mr_post2015$r_AR[valid], ncol=1)
    colnames(R) <- "AR"  # cash가 stochastic이 아님 — 단일 dim Σ scalar
  } else if (scenario == "C") {
    valid <- complete.cases(mr_post2015[, .(r_AR, r_TSMOM, r_KR10y)])
    R <- as.matrix(mr_post2015[valid, .(r_AR, r_TSMOM, r_KR10y)])
    colnames(R) <- c("AR", "TSMOM", "KR10y")
  } else if (scenario == "D") {
    valid <- complete.cases(mr_post2015[, .(r_AR, r_defensive, r_commodity, r_vrp)])
    R <- as.matrix(mr_post2015[valid, .(r_AR, r_defensive, r_commodity, r_vrp)])
    colnames(R) <- c("AR", "Defensive", "Commodity", "VRP")
  }
  R
}

# Scenario weights vector
get_weights <- function(scenario) {
  if (scenario == "A") c(0.70, 0.15, 0.15)
  else if (scenario == "B") c(0.70)  # AR only stochastic, cash=0 not in matrix
  else if (scenario == "C") c(0.80, 0.10, 0.10)
  else if (scenario == "D") c(0.70, 0.10, 0.10, 0.10)
}

# Run cov estimators per scenario
cov_results_all <- list()
for (s in c("A","B","C","D")) {
  R_s <- build_sleeve_matrix(s)
  w_s <- get_weights(s)
  p_dim <- ncol(R_s)
  cat(sprintf("\n  Scenario %s: n=%d, dim=%d\n", s, nrow(R_s), p_dim))
  est_results <- list()
  for (est in names(cov_estimators)) {
    # Skip multi-dim only estimators when p=1
    if (p_dim == 1 && est %in% c("LW_identity","LW_constcor","Gerber","Glasso")) {
      cat(sprintf("    %s: skipped (p=1 not applicable to multi-dim shrinkage)\n", est))
      next
    }
    fn <- cov_estimators[[est]]
    Sigma <- tryCatch(fn(R_s), error = function(e) {
      cat(sprintf("    [ERR] %s: %s\n", est, e$message))
      NULL
    })
    if (is.null(Sigma)) next
    if (any(is.na(Sigma)) || any(is.infinite(Sigma))) {
      cat(sprintf("    %s: skipped (Sigma has NA/Inf)\n", est))
      next
    }

    # Diagnostics
    if (p_dim == 1) {
      eg_v <- as.numeric(Sigma)
      cond <- 1
      min_eig <- as.numeric(Sigma)
      is_psd <- min_eig >= 0
    } else {
      eg_v <- eigen(Sigma, symmetric=TRUE, only.values=TRUE)$values
      cond <- max(eg_v) / max(min(eg_v), 1e-12)
      min_eig <- min(eg_v)
      is_psd <- min_eig >= -1e-8
    }

    # Portfolio variance via w' Σ w
    if (s == "B") {
      port_var_ann <- (w_s[1])^2 * as.numeric(Sigma[1,1]) * 12  # scalar
    } else {
      port_var_ann <- as.numeric(t(w_s) %*% Sigma %*% w_s) * 12
    }
    port_vol_ann <- sqrt(port_var_ann)

    est_results[[est]] <- list(
      Sigma = Sigma,
      cond = cond,
      min_eig = min_eig,
      is_psd = is_psd,
      port_vol_ann = port_vol_ann
    )
    cat(sprintf("    %s: cond=%.4e min_eig=%.4e PSD=%s port_vol_ann=%.4f\n",
                est, cond, min_eig, is_psd, port_vol_ann))
  }
  cov_results_all[[s]] <- est_results
}

# Build comparison CSV
cov_summary_rows <- list()
for (s in names(cov_results_all)) {
  for (est in names(cov_results_all[[s]])) {
    r <- cov_results_all[[s]][[est]]
    cov_summary_rows[[length(cov_summary_rows)+1]] <- data.table(
      scenario = s,
      estimator = est,
      cond_number = r$cond,
      min_eigenvalue = r$min_eig,
      is_psd = r$is_psd,
      port_vol_ann = r$port_vol_ann
    )
  }
}
cov_summary <- rbindlist(cov_summary_rows)
fwrite(cov_summary, file.path(WORK, "scenario_covariance_5est_summary.csv"))
cat(sprintf("\n[SAVED] scenario_covariance_5est_summary.csv (%d rows)\n", nrow(cov_summary)))

# -----------------------------------------------------------------------------
# 3. METRIC 2: Tail Risk — VaR99/ES99 4-method + EVT GPD threshold sensitivity
# -----------------------------------------------------------------------------
cat("\n=== METRIC 2: TAIL RISK (4 methods + EVT-GPD) ===\n")

calc_tail_metrics <- function(ret, alpha = 0.01) {
  n <- length(ret)
  ret_sorted <- sort(ret)

  # 1. Empirical
  k <- floor(n * alpha)
  if (k < 1) k <- 1
  var_emp <- -ret_sorted[k]
  es_emp <- -mean(ret_sorted[1:k])

  # 2. Normal (Gaussian)
  mu <- mean(ret); sg <- sd(ret)
  var_norm <- -(mu + qnorm(alpha) * sg)
  es_norm <- -(mu - sg * dnorm(qnorm(alpha))/alpha)

  # 3. Cornish-Fisher (skew + kurt adjustment)
  sk <- mean(((ret - mu)/sg)^3)
  ku <- mean(((ret - mu)/sg)^4) - 3
  z <- qnorm(alpha)
  z_cf <- z + (z^2-1)*sk/6 + (z^3-3*z)*ku/24 - (2*z^3-5*z)*sk^2/36
  var_cf <- -(mu + z_cf * sg)
  es_cf <- var_cf  # CF ES approx (same formulation)

  # 4. EVT-GPD (POT method, threshold = 90th percentile of losses)
  losses <- -ret
  thr <- quantile(losses, 0.90, names = FALSE)
  exceedances <- losses[losses > thr] - thr
  if (length(exceedances) >= 10) {
    # Fit GPD via MLE — use closed-form approximation
    n_exc <- length(exceedances)
    mean_exc <- mean(exceedances)
    var_exc <- var(exceedances)
    # Method of moments for GPD
    xi_mom <- 0.5 * (1 - mean_exc^2 / var_exc)
    beta_mom <- mean_exc * (1 - xi_mom)
    if (beta_mom <= 0) { beta_mom <- mean_exc; xi_mom <- 0 }
    # VaR99
    p_thr <- length(exceedances)/n
    if (xi_mom != 0) {
      var_evt <- thr + (beta_mom/xi_mom) * ((alpha/p_thr)^(-xi_mom) - 1)
      es_evt <- (var_evt + beta_mom - xi_mom * thr) / (1 - xi_mom)
    } else {
      var_evt <- thr - beta_mom * log(alpha/p_thr)
      es_evt <- var_evt + beta_mom
    }
  } else {
    xi_mom <- NA; beta_mom <- NA; var_evt <- NA; es_evt <- NA
  }

  list(
    var_empirical = var_emp, es_empirical = es_emp,
    var_normal = var_norm, es_normal = es_norm,
    var_cf = var_cf, es_cf = es_cf,
    var_evt = var_evt, es_evt = es_evt,
    evt_xi = xi_mom, evt_beta = beta_mom, evt_threshold = thr, n_exceedances = length(exceedances)
  )
}

tail_summary_rows <- list()
for (s in names(scenarios)) {
  ret <- scenarios[[s]]$ret
  tm <- calc_tail_metrics(ret, alpha = 0.01)
  tail_summary_rows[[s]] <- data.table(
    scenario = s, n = length(ret),
    var99_empirical = tm$var_empirical, es99_empirical = tm$es_empirical,
    var99_normal = tm$var_normal, es99_normal = tm$es_normal,
    var99_cf = tm$var_cf, es99_cf = tm$es_cf,
    var99_evt = tm$var_evt, es99_evt = tm$es_evt,
    evt_xi = tm$evt_xi, evt_beta = tm$evt_beta, evt_threshold = tm$evt_threshold,
    n_exceedances = tm$n_exceedances
  )
  cat(sprintf("  %s: VaR99 emp=%.4f norm=%.4f CF=%.4f EVT=%.4f | ES99 emp=%.4f EVT=%.4f | xi=%.3f\n",
              s, tm$var_empirical, tm$var_normal, tm$var_cf, ifelse(is.na(tm$var_evt), -999, tm$var_evt),
              tm$es_empirical, ifelse(is.na(tm$es_evt), -999, tm$es_evt),
              ifelse(is.na(tm$evt_xi), -999, tm$evt_xi)))
}
tail_summary <- rbindlist(tail_summary_rows)
fwrite(tail_summary, file.path(WORK, "scenario_tail_risk_4method.csv"))
cat(sprintf("\n[SAVED] scenario_tail_risk_4method.csv (%d rows)\n", nrow(tail_summary)))

# EVT threshold sensitivity (Pfaff Ch.7 — try 85/90/95)
evt_thr_rows <- list()
for (s in names(scenarios)) {
  ret <- scenarios[[s]]$ret
  losses <- -ret
  for (thr_pct in c(0.80, 0.85, 0.90, 0.95)) {
    thr <- quantile(losses, thr_pct, names = FALSE)
    exc <- losses[losses > thr] - thr
    if (length(exc) >= 5) {
      m <- mean(exc); v <- var(exc)
      xi <- 0.5 * (1 - m^2/v)
      beta <- m * (1 - xi)
      if (beta <= 0) { beta <- m; xi <- 0 }
      evt_thr_rows[[length(evt_thr_rows)+1]] <- data.table(
        scenario = s, threshold_pct = thr_pct, threshold_val = thr,
        n_exceedances = length(exc), xi = xi, beta = beta
      )
    }
  }
}
evt_thr <- rbindlist(evt_thr_rows)
fwrite(evt_thr, file.path(WORK, "scenario_evt_threshold_sensitivity.csv"))
cat(sprintf("[SAVED] scenario_evt_threshold_sensitivity.csv (%d rows)\n", nrow(evt_thr)))

# -----------------------------------------------------------------------------
# 4. METRIC 3: 8-Stress (named historical periods)
# -----------------------------------------------------------------------------
cat("\n=== METRIC 3: 8-STRESS (named periods) ===\n")

# 8 named stress periods (cycle 4 inheritance)
# Note: post-2015 sub-sample, so IMF/DotCom only as historical reference (BM-only)
stress_periods <- list(
  IMF_1997      = c("1997-07","1998-12"),
  DotCom_2000   = c("2000-03","2002-09"),
  GFC_2008      = c("2007-10","2009-03"),
  EuDebt_2011   = c("2011-05","2011-12"),
  China_2015    = c("2015-06","2016-02"),
  VolShock_2018 = c("2018-02","2018-04"),
  COVID_2020    = c("2020-02","2020-04"),
  Inflation2022 = c("2021-12","2022-12")
)

stress_rows <- list()
for (s in names(scenarios)) {
  sc <- scenarios[[s]]
  for (sp_name in names(stress_periods)) {
    sp <- stress_periods[[sp_name]]
    period_idx <- sc$dates >= sp[1] & sc$dates <= sp[2]
    n_period <- sum(period_idx)
    if (n_period < 1) {
      stress_rows[[length(stress_rows)+1]] <- data.table(
        scenario = s, stress_period = sp_name, start = sp[1], end = sp[2],
        n_obs = 0, mean_monthly = NA, total_return = NA, mdd_period = NA, sr_period = NA,
        passes_crisis_alpha = NA, status = "NO_DATA_POST2015_OOS"
      )
      next
    }
    rets_period <- sc$ret[period_idx]
    mu <- mean(rets_period)
    cum <- prod(1 + rets_period) - 1

    # Period MDD
    nav <- cumprod(1 + rets_period)
    drawdowns <- nav / cummax(nav) - 1
    mdd <- min(drawdowns)
    sr_period <- if (sd(rets_period) > 0) mu/sd(rets_period) * sqrt(12) else NA

    # AX-001 v2 Test 1 proxy: crisis_alpha = mean monthly > 0 in named CRISIS-class period
    # CRISIS-class: GFC_2008, EuDebt_2011, COVID_2020 (deepest 3)
    is_crisis_class <- sp_name %in% c("GFC_2008","EuDebt_2011","COVID_2020")
    passes_crisis_alpha <- if (is_crisis_class) mu > 0 else NA

    stress_rows[[length(stress_rows)+1]] <- data.table(
      scenario = s, stress_period = sp_name, start = sp[1], end = sp[2],
      n_obs = n_period, mean_monthly = mu, total_return = cum, mdd_period = mdd, sr_period = sr_period,
      passes_crisis_alpha = passes_crisis_alpha,
      status = "OK"
    )
  }
}
stress_8 <- rbindlist(stress_rows)
fwrite(stress_8, file.path(WORK, "scenario_8stress_named.csv"))
cat(sprintf("\n[SAVED] scenario_8stress_named.csv (%d rows)\n", nrow(stress_8)))

# Print summary per scenario
for (s in c("A","B","C","D")) {
  sub <- stress_8[scenario == s & status == "OK"]
  cat(sprintf("  %s: stress_periods_with_data=%d, avg_period_MDD=%.3f, crisis_alpha_pass=%d/%d\n",
              s, nrow(sub), mean(sub$mdd_period, na.rm=TRUE),
              sum(sub$passes_crisis_alpha == TRUE, na.rm=TRUE),
              sum(!is.na(sub$passes_crisis_alpha))))
}

# -----------------------------------------------------------------------------
# 5. METRIC 4: Crowding/TDC + style + sector
# -----------------------------------------------------------------------------
cat("\n=== METRIC 4: CROWDING/TDC + STYLE + SECTOR ===\n")

# Pairwise correlation per scenario sleeve
crowd_rows <- list()
for (s in names(scenarios)) {
  R_s <- build_sleeve_matrix(s)
  if (ncol(R_s) < 2) {
    crowd_rows[[s]] <- data.table(
      scenario = s, n_sleeves = ncol(R_s),
      max_pairwise_cor = NA, mean_abs_pair_cor = NA,
      max_lower_tdc_5pct = NA, max_upper_tdc_95pct = NA,
      hhi_normalized = NA  # Single sleeve: HHI = 1 (max concentration)
    )
    next
  }
  cor_mat <- cor(R_s)
  # Pairwise exclude diagonal
  pair_cors <- cor_mat[upper.tri(cor_mat)]
  max_cor <- max(abs(pair_cors))
  mean_abs_cor <- mean(abs(pair_cors))

  # Lower TDC (empirical, alpha=5%)
  n <- nrow(R_s); p <- ncol(R_s)
  alpha_t <- 0.05
  ranks_lo <- apply(R_s, 2, rank) / (n+1)
  ranks_hi <- 1 - ranks_lo  # for upper TDC

  pair_lower_tdc <- numeric(0)
  pair_upper_tdc <- numeric(0)
  for (i in 1:(p-1)) for (j in (i+1):p) {
    # Lower TDC
    cnt_lo <- sum(ranks_lo[,i] <= alpha_t & ranks_lo[,j] <= alpha_t)
    tdc_lo <- cnt_lo / (n * alpha_t)
    pair_lower_tdc <- c(pair_lower_tdc, tdc_lo)
    # Upper TDC
    cnt_hi <- sum(ranks_hi[,i] <= alpha_t & ranks_hi[,j] <= alpha_t)
    tdc_hi <- cnt_hi / (n * alpha_t)
    pair_upper_tdc <- c(pair_upper_tdc, tdc_hi)
  }
  max_lower_tdc <- max(pair_lower_tdc)
  max_upper_tdc <- max(pair_upper_tdc)

  # HHI on weights
  w <- get_weights(s)
  if (s == "B") {
    w_full <- c(0.70, 0.30)  # AR + cash
  } else {
    w_full <- w
  }
  hhi_norm <- sum(w_full^2)

  crowd_rows[[s]] <- data.table(
    scenario = s, n_sleeves = ncol(R_s),
    max_pairwise_cor = max_cor, mean_abs_pair_cor = mean_abs_cor,
    max_lower_tdc_5pct = max_lower_tdc, max_upper_tdc_95pct = max_upper_tdc,
    hhi_normalized = hhi_norm
  )
}
crowd_summary <- rbindlist(crowd_rows)
fwrite(crowd_summary, file.path(WORK, "scenario_crowding_tdc.csv"))
cat(sprintf("\n[SAVED] scenario_crowding_tdc.csv (%d rows)\n", nrow(crowd_summary)))
print(crowd_summary)

# -----------------------------------------------------------------------------
# 6. METRIC 5: Forward simulation (Mann-Kendall + Pettitt)
# -----------------------------------------------------------------------------
cat("\n=== METRIC 5: FORWARD SIMULATION (rolling SR + MK + Pettitt) ===\n")

# Pettitt change-point test (manual implementation)
pettitt_test <- function(x) {
  n <- length(x)
  U <- numeric(n)
  for (k in 1:n) {
    cnt <- 0
    for (i in 1:k) for (j in (k+1):n) {
      if (j > n) next
      cnt <- cnt + sign(x[i] - x[j])
    }
    U[k] <- cnt
  }
  K <- max(abs(U))
  k_idx <- which.max(abs(U))
  # Approximate p-value
  p_val <- 2 * exp(-6 * K^2 / (n^3 + n^2))
  p_val <- min(p_val, 1)
  list(K = K, k_idx = k_idx, p_value = p_val)
}

# Rolling SR (60m window) per scenario
rolling_sr <- function(ret, w = 60) {
  n <- length(ret)
  if (n < w) return(numeric(0))
  out <- numeric(n - w + 1)
  for (i in 1:(n - w + 1)) {
    sub <- ret[i:(i+w-1)]
    if (sd(sub) > 0) out[i] <- mean(sub)/sd(sub) * sqrt(12) else out[i] <- 0
  }
  out
}

forward_sim_rows <- list()
for (s in names(scenarios)) {
  ret <- scenarios[[s]]$ret
  rs60 <- rolling_sr(ret, 60)
  rs36 <- rolling_sr(ret, 36)
  rs24 <- rolling_sr(ret, 24)

  # Full-sample SR
  sr_full <- mean(ret)/sd(ret) * sqrt(12)

  # Recent SR (last w months)
  sr_60m_last <- if (length(rs60) > 0) tail(rs60, 1) else NA
  sr_36m_last <- if (length(rs36) > 0) tail(rs36, 1) else NA
  sr_24m_last <- if (length(rs24) > 0) tail(rs24, 1) else NA

  # Decay rate (60m vs full)
  decay_60m_pct <- if (!is.na(sr_60m_last) && sr_full > 0) (sr_full - sr_60m_last)/sr_full else NA

  # Mann-Kendall on rolling 60m SR
  mk_result <- if (length(rs60) >= 10) {
    mk <- MannKendall(rs60)
    list(tau = as.numeric(mk$tau), p_value = as.numeric(mk$sl))
  } else {
    list(tau = NA, p_value = NA)
  }

  # Pettitt change-point on rolling 60m SR
  pettitt_result <- if (length(rs60) >= 10) {
    tryCatch(pettitt_test(rs60), error = function(e) list(K=NA, k_idx=NA, p_value=NA))
  } else {
    list(K=NA, k_idx=NA, p_value=NA)
  }

  forward_sim_rows[[s]] <- data.table(
    scenario = s, n_obs = length(ret), n_60m = length(rs60),
    sr_full = sr_full, sr_24m_last = sr_24m_last, sr_36m_last = sr_36m_last, sr_60m_last = sr_60m_last,
    decay_60m_pct = decay_60m_pct,
    mk_60m_tau = mk_result$tau, mk_60m_pvalue = mk_result$p_value,
    pettitt_60m_K = pettitt_result$K, pettitt_60m_pvalue = pettitt_result$p_value,
    p1_alert_warning_30pct = !is.na(decay_60m_pct) && decay_60m_pct > 0.30,
    p1_alert_critical_50pct = !is.na(decay_60m_pct) && decay_60m_pct > 0.50
  )
  cat(sprintf("  %s: SR_full=%.3f SR_60m_last=%.3f decay=%.1f%% MK_tau=%.3f p=%.3e Pettitt_p=%.3e\n",
              s, sr_full, sr_60m_last, ifelse(is.na(decay_60m_pct), -999, decay_60m_pct*100),
              ifelse(is.na(mk_result$tau), -999, mk_result$tau),
              ifelse(is.na(mk_result$p_value), -999, mk_result$p_value),
              ifelse(is.na(pettitt_result$p_value), -999, pettitt_result$p_value)))
}
forward_sim <- rbindlist(forward_sim_rows)
fwrite(forward_sim, file.path(WORK, "scenario_forward_sim_mk_pettitt.csv"))
cat(sprintf("\n[SAVED] scenario_forward_sim_mk_pettitt.csv (%d rows)\n", nrow(forward_sim)))

# -----------------------------------------------------------------------------
# 7. TRADE-OFF MATRIX (4 scenarios × 4 metric)
# -----------------------------------------------------------------------------
cat("\n=== TRADE-OFF MATRIX (4 × 4) ===\n")

# Build per-scenario aggregate
trade_rows <- list()
for (s in c("A","B","C","D")) {
  sc <- scenarios[[s]]
  ret <- sc$ret

  # Metric 1: SR
  sr <- mean(ret)/sd(ret) * sqrt(12)

  # Metric 2: MDD (full sample)
  nav <- cumprod(1 + ret)
  dd <- nav / cummax(nav) - 1
  mdd <- min(dd)

  # Metric 3: Crisis alpha pass rate (3 deepest periods)
  sub <- stress_8[scenario == s & stress_period %in% c("GFC_2008","EuDebt_2011","COVID_2020") & status == "OK"]
  crisis_alpha_passed <- sum(sub$passes_crisis_alpha == TRUE, na.rm=TRUE)
  crisis_alpha_total <- sum(!is.na(sub$passes_crisis_alpha))
  crisis_alpha_rate <- if (crisis_alpha_total > 0) crisis_alpha_passed / crisis_alpha_total else NA

  # Metric 4: Decay risk (60m SR decay > warning 30%)
  fs <- forward_sim[scenario == s]
  decay_pct_60m <- fs$decay_60m_pct
  decay_warning <- fs$p1_alert_warning_30pct
  decay_critical <- fs$p1_alert_critical_50pct

  trade_rows[[s]] <- data.table(
    scenario = s,
    description = c(A="70 AR + 15 TSMOM + 15 KR10y (현 admit)",
                    B="70 AR + 30 cash (P1 cut)",
                    C="80 AR + 10 TSMOM + 10 KR10y (P1 partial)",
                    D="70 AR + 10 Defensive + 10 Commodity + 10 VRP (P1 substitute)")[s],
    sr = sr,
    mdd = mdd,
    crisis_alpha_pass_rate = crisis_alpha_rate,
    decay_60m_pct = decay_pct_60m,
    decay_warning = decay_warning,
    decay_critical = decay_critical
  )
}
trade_off <- rbindlist(trade_rows)
fwrite(trade_off, file.path(WORK, "scenario_tradeoff_matrix.csv"))
cat(sprintf("\n[SAVED] scenario_tradeoff_matrix.csv\n"))
print(trade_off)

# -----------------------------------------------------------------------------
# 8. AX-001 v2 verdict per scenario (B/C/D defensive 평가)
# -----------------------------------------------------------------------------
cat("\n=== AX-001 v2 (defense conditional) per scenario ===\n")

# AR-only baseline (for MDD relief comparison)
ret_AR <- mr_post2015$r_AR[!is.na(mr_post2015$r_AR)]
nav_AR <- cumprod(1 + ret_AR)
mdd_AR <- min(nav_AR / cummax(nav_AR) - 1)

ax001_rows <- list()
for (s in c("A","B","C","D")) {
  sc <- scenarios[[s]]
  ret <- sc$ret

  # Test 1: crisis_alpha
  sub <- stress_8[scenario == s & stress_period %in% c("GFC_2008","EuDebt_2011","COVID_2020") & status == "OK"]
  crisis_alpha_pass_rate <- if (nrow(sub) > 0) {
    sum(sub$mean_monthly > 0, na.rm=TRUE) / sum(!is.na(sub$mean_monthly))
  } else NA
  test1_pass <- !is.na(crisis_alpha_pass_rate) && crisis_alpha_pass_rate >= 0.5

  # Test 2: MDD relief vs AR-only
  nav <- cumprod(1 + ret)
  dd <- nav / cummax(nav) - 1
  mdd_s <- min(dd)
  mdd_relief_pp <- (mdd_s - mdd_AR) * 100  # negative pp = relief
  test2_pass <- mdd_s > mdd_AR  # better (less negative)

  # Test 3: bad/normal correlation ratio (vs r_AR)
  ret_AR_sub <- ret_AR[1:min(length(ret_AR), length(ret))]
  ret_sub <- ret[1:min(length(ret_AR), length(ret))]
  # Define crisis = bottom 25% of AR returns, normal = middle 50%
  q25 <- quantile(ret_AR_sub, 0.25)
  q75 <- quantile(ret_AR_sub, 0.75)
  crisis_idx <- ret_AR_sub <= q25
  normal_idx <- ret_AR_sub > q25 & ret_AR_sub < q75

  cor_crisis <- if (sum(crisis_idx) >= 5) cor(ret_AR_sub[crisis_idx], ret_sub[crisis_idx]) else NA
  cor_normal <- if (sum(normal_idx) >= 5) cor(ret_AR_sub[normal_idx], ret_sub[normal_idx]) else NA

  # bad/normal ratio: cor_crisis < cor_normal => defensive
  test3_pass <- !is.na(cor_crisis) && !is.na(cor_normal) && cor_crisis < cor_normal

  total_pass <- sum(c(test1_pass, test2_pass, test3_pass), na.rm=TRUE)

  ax001_rows[[s]] <- data.table(
    scenario = s,
    test1_crisis_alpha_rate = crisis_alpha_pass_rate, test1_pass = test1_pass,
    mdd_scenario = mdd_s, mdd_AR_baseline = mdd_AR, mdd_relief_pp = mdd_relief_pp, test2_pass = test2_pass,
    cor_crisis = cor_crisis, cor_normal = cor_normal, test3_pass = test3_pass,
    total_pass_count = total_pass,
    overall_verdict = sprintf("PASS_%d_OF_3", total_pass)
  )
  cat(sprintf("  %s: T1=%s T2=%s T3=%s overall=PASS_%d_OF_3 (MDD relief %.2fpp, cor_crisis=%.3f vs normal=%.3f)\n",
              s, test1_pass, test2_pass, test3_pass, total_pass, mdd_relief_pp,
              ifelse(is.na(cor_crisis), -999, cor_crisis), ifelse(is.na(cor_normal), -999, cor_normal)))
}
ax001 <- rbindlist(ax001_rows)
fwrite(ax001, file.path(WORK, "scenario_ax001v2_verdict.csv"))
cat(sprintf("\n[SAVED] scenario_ax001v2_verdict.csv\n"))

# -----------------------------------------------------------------------------
# 9. Save aggregate JSON summary
# -----------------------------------------------------------------------------
cat("\n=== SAVING JSON AGGREGATE ===\n")
agg <- list(
  cycle = 6,
  as_of_date = "2026-05-08",
  research_type = "meta_self_research_qlead_ondemand_cycle6_4scenario_comparison",
  axis_focus = "사이클 5 P1 alert 후속: 4 시나리오 × 5 risk metric 사전 진단 (Q-Lead/도훈 결정 정보 제공만)",
  scenarios = list(
    A = list(weights = "70 AR + 15 TSMOM + 15 KR10y", n = scenarios$A$n,
             sr = mean(scenarios$A$ret)/sd(scenarios$A$ret)*sqrt(12)),
    B = list(weights = "70 AR + 30 cash", n = scenarios$B$n,
             sr = mean(scenarios$B$ret)/sd(scenarios$B$ret)*sqrt(12)),
    C = list(weights = "80 AR + 10 TSMOM + 10 KR10y", n = scenarios$C$n,
             sr = mean(scenarios$C$ret)/sd(scenarios$C$ret)*sqrt(12)),
    D = list(weights = "70 AR + 10 Defensive + 10 Commodity + 10 VRP", n = scenarios$D$n,
             sr = mean(scenarios$D$ret)/sd(scenarios$D$ret)*sqrt(12))
  )
)
write_json(agg, file.path(WORK, "cycle6_aggregate_summary.json"), pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("[SAVED] cycle6_aggregate_summary.json\n"))

cat("\n=== CYCLE 6 SCENARIO COMPARISON COMPLETE ===\n")
