#==============================================================================
# carhart_4factor.R -- Carhart 4-factor Performance Attribution
#
# 7 QEPM Modern Trends Phase 2.D
# Constitutional SOT: qvest_research_philosophy.md Principle 7
#
# carhart_4factor(portfolio_returns, factor_returns)
#   portfolio_returns: data.table(Date, port_excess_ret)  [over Rf]
#   factor_returns:    data.table(Date, MKT, SMB, HML, UMD)
#
# Returns: list(
#   alpha:        Jensen's alpha (intercept)
#   alpha_t:      NW(6) t-stat of alpha
#   betas:        named vec {MKT, SMB, HML, UMD}
#   beta_t:       named vec t-stats
#   r_squared:    in-sample R^2
#   adj_r2:       adjusted R^2
#   residuals:    per-Date residual returns
#   n:            number of observations
# )
#
# Newey-West HAC standard errors (lag 6, monthly).
#
# References:
#   Carhart M.M. (1997) "On Persistence in Mutual Fund Performance" JoF
#   Newey & West (1987) "A Simple, Positive Semi-Definite Heteroskedasticity
#                       and Autocorrelation Consistent Covariance Matrix"
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

# ---- Newey-West HAC variance (lag q) ----
.nw_var <- function(X, resid, lag = 6L) {
  n <- nrow(X)
  k <- ncol(X)
  XtX_inv <- solve(crossprod(X))
  S <- crossprod(X * resid)  # k x k base meat
  for (l in 1:lag) {
    w <- 1 - l / (lag + 1)
    gamma_l <- crossprod(X[(l + 1):n, , drop = FALSE] * resid[(l + 1):n],
                          X[1:(n - l), , drop = FALSE] * resid[1:(n - l)])
    S <- S + w * (gamma_l + t(gamma_l))
  }
  vcov <- XtX_inv %*% S %*% XtX_inv
  list(vcov = vcov, S = S, df = n - k)
}

carhart_4factor <- function(portfolio_returns,
                              factor_returns,
                              date_col = "Date",
                              ret_col = "port_excess_ret",
                              factor_cols = c("MKT", "SMB", "HML", "UMD"),
                              nw_lag = 6L) {

  pr <- as.data.table(portfolio_returns)
  fr <- as.data.table(factor_returns)
  setnames(pr, c(date_col, ret_col), c("Date", "port_excess_ret"), skip_absent = TRUE)
  setnames(fr, date_col, "Date", skip_absent = TRUE)
  pr[, Date := as.Date(Date)]
  fr[, Date := as.Date(Date)]

  merged <- merge(pr[, .(Date, port_excess_ret)],
                   fr[, c("Date", factor_cols), with = FALSE],
                   by = "Date")
  merged <- merged[complete.cases(merged)]
  n <- nrow(merged)
  if (n < 24L) {
    return(list(alpha = NA_real_, alpha_t = NA_real_,
                 betas = setNames(rep(NA_real_, length(factor_cols)), factor_cols),
                 beta_t = setNames(rep(NA_real_, length(factor_cols)), factor_cols),
                 r_squared = NA_real_, adj_r2 = NA_real_,
                 residuals = NULL, n = n,
                 note = "n < 24, insufficient for 4-factor + NW lag 6"))
  }

  # Design matrix: [1, MKT, SMB, HML, UMD]
  X <- cbind(1, as.matrix(merged[, factor_cols, with = FALSE]))
  colnames(X) <- c("alpha", factor_cols)
  y <- merged$port_excess_ret

  XtX_inv <- solve(crossprod(X))
  coef <- as.vector(XtX_inv %*% crossprod(X, y))
  names(coef) <- colnames(X)

  fitted <- as.vector(X %*% coef)
  resid <- y - fitted
  ss_res <- sum(resid^2)
  ss_tot <- sum((y - mean(y))^2)
  r2 <- 1 - ss_res / ss_tot
  k <- ncol(X)
  adj_r2 <- 1 - (1 - r2) * (n - 1) / max(n - k, 1)

  nw <- .nw_var(X, resid, lag = nw_lag)
  se_nw <- sqrt(diag(nw$vcov))
  t_nw <- coef / pmax(se_nw, 1e-12)

  list(
    alpha = unname(coef["alpha"]),
    alpha_t = unname(t_nw["alpha"]),
    alpha_annualized = unname(coef["alpha"] * 12),  # monthly → annualized
    betas = coef[factor_cols],
    beta_t = t_nw[factor_cols],
    r_squared = r2,
    adj_r2 = adj_r2,
    residuals = data.table(Date = merged$Date, resid = resid),
    n = n,
    nw_lag = nw_lag,
    sigma_residual_monthly = sqrt(ss_res / max(n - k, 1)),
    sigma_residual_annualized = sqrt(ss_res / max(n - k, 1)) * sqrt(12)
  )
}

#==============================================================================
# Combined: portfolio return decomposition = factor + selection + cost + residual
#==============================================================================
attribution_full_decomp <- function(portfolio_returns_gross,
                                      portfolio_returns_net,
                                      factor_returns,
                                      benchmark_returns,
                                      rf_returns = NULL,
                                      brinson_inputs = NULL) {

  # Construct excess returns over Rf if provided
  pr <- as.data.table(portfolio_returns_gross)
  if (!is.null(rf_returns)) {
    rf_dt <- as.data.table(rf_returns)
    setnames(rf_dt, "Rf", "Rf", skip_absent = TRUE)
    pr <- merge(pr, rf_dt, by = "Date")
    pr[, port_excess_ret := port_ret - Rf]
  } else {
    pr[, port_excess_ret := port_ret]
  }

  carhart <- carhart_4factor(pr, factor_returns)

  cost_drag <- NA_real_
  if (!is.null(portfolio_returns_net)) {
    pn <- as.data.table(portfolio_returns_net)
    merged_cost <- merge(pr[, .(Date, port_ret)], pn[, .(Date, port_ret_net)], by = "Date")
    cost_drag <- mean(merged_cost$port_ret - merged_cost$port_ret_net, na.rm = TRUE) * 12
  }

  brinson <- if (!is.null(brinson_inputs)) {
    brinson_decomp(brinson_inputs$portfolio_panel,
                    brinson_inputs$benchmark_panel,
                    brinson_inputs$returns_panel)
  } else NULL

  list(
    carhart = carhart,
    brinson = brinson,
    cost_drag_annualized = cost_drag,
    decomposition_summary = list(
      alpha_carhart = carhart$alpha_annualized,
      factor_exposures = carhart$betas,
      r_squared = carhart$r_squared,
      cost_drag_annualized = cost_drag,
      brinson_total_active = if (!is.null(brinson)) brinson$summary$cum_total_active else NA_real_,
      brinson_allocation = if (!is.null(brinson)) brinson$summary$cum_allocation else NA_real_,
      brinson_selection = if (!is.null(brinson)) brinson$summary$cum_selection else NA_real_
    )
  )
}
