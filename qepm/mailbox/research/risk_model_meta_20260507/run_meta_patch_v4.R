#!/usr/bin/env Rscript
# ============================================================================
# Patch v4 — EVT-GPD VaR/ES at multiple alpha + Cornish-Fisher comparison
# Pfaff Ch.7 Eq.7.4 (EVT-VaR) + Eq.7.5 (EVT-ES) + Ch.6 (Cornish-Fisher)
#
# 비교 대상: empirical / parametric normal / Cornish-Fisher / EVT-GPD
# Series: AR_only / KR10y_only / TSMOM_only / Hybrid_70_15_15 (137m post-2015)
#
# 추가:
# - Pfaff Eq.7.4: EVT-VaR_p = u + (β/ξ) * ((n/n_u)*(1-p))^(-ξ) - 1)
# - Eq.7.5: EVT-ES_p = (VaR_p + β - ξ*u) / (1 - ξ)
# ============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(PerformanceAnalytics)
  library(fExtremes)
  library(xts)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/research/risk_model_meta_20260507")

LOG_FILE <- file.path(OUT_DIR, "meta_research_log.txt")
log_msg <- function(msg) {
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  line <- sprintf("[%s] [PATCH_V4] %s", ts, msg)
  cat(line, "\n")
  cat(line, "\n", file = LOG_FILE, append = TRUE)
}
log_msg("=== PATCH V4 START ===")

ret_file <- file.path(PROJECT_ROOT,
  "qepm/mailbox/worktask/WT-P20260505_001/architect_hybrid_returns_full256m.csv")
ret_dt <- fread(ret_file)
ret_dt[, date := as.Date(date)]
ret_dt[, has_tsmom := !is.na(r_TSMOM)]
ret_dt[, hybrid_70_15_15 := ifelse(has_tsmom,
                                    0.70 * r_AR + 0.15 * r_KR10y + 0.15 * r_TSMOM,
                                    (0.70 * r_AR + 0.20 * r_KR10y) / 0.90)]

# Pfaff Eq.7.4 / 7.5
evt_var_es_pfaff <- function(returns, p_seq = c(0.95, 0.99, 0.995),
                              threshold_q = 0.90, min_exceed = 30L) {
  losses <- -returns[!is.na(returns)]
  n <- length(losses)
  u <- as.numeric(quantile(losses, threshold_q))
  exceedances <- losses[losses > u]
  n_u <- length(exceedances)
  if (n_u < min_exceed) {
    return(data.table(method = "EVT_GPD_insufficient",
                      threshold_q = threshold_q,
                      n_obs = n, n_exceed = n_u, status = "INSUFFICIENT"))
  }
  fit <- tryCatch(fExtremes::gpdFit(losses, u = u),
                  error = function(e) NULL)
  if (is.null(fit)) {
    return(data.table(method = "EVT_GPD_fit_failed",
                      threshold_q = threshold_q,
                      n_obs = n, n_exceed = n_u, status = "FIT_FAILED"))
  }
  xi <- as.numeric(fit@fit$par.ests["xi"])
  beta <- as.numeric(fit@fit$par.ests["beta"])

  out <- list()
  for (p in p_seq) {
    # Pfaff Eq.7.4: VaR_p = u + (beta/xi) * ((n/n_u) * (1-p))^(-xi) - 1)
    if (abs(xi) > 1e-6) {
      var_p <- u + (beta / xi) * (((n / n_u) * (1 - p))^(-xi) - 1)
    } else {
      var_p <- u + beta * log((n / n_u) / (1 - p))  # xi -> 0 limit
    }
    # Pfaff Eq.7.5: ES_p = (VaR_p + beta - xi*u) / (1 - xi)
    if (xi < 1) {
      es_p <- (var_p + beta - xi * u) / (1 - xi)
    } else {
      es_p <- NA_real_
    }
    out[[length(out) + 1]] <- data.table(
      method = "EVT_GPD_pfaff", p = p,
      threshold_q = threshold_q, threshold_u = u,
      n_obs = n, n_exceed = n_u, xi = xi, beta = beta,
      VaR = -var_p,  # back to return convention
      ES = -es_p
    )
  }
  rbindlist(out, fill = TRUE)
}

# Cornish-Fisher VaR (Pfaff Ch.6)
cf_var <- function(returns, p_seq = c(0.95, 0.99, 0.995)) {
  r <- returns[!is.na(returns)]
  mu <- mean(r); sigma <- sd(r)
  skew <- mean((r - mu)^3) / sigma^3
  kurt <- mean((r - mu)^4) / sigma^4 - 3  # excess kurt

  out <- list()
  for (p in p_seq) {
    z <- qnorm(1 - p)  # standard normal lower-tail quantile (z < 0)
    # CF expansion (Pfaff Eq.6.4)
    z_cf <- z + (z^2 - 1) / 6 * skew + (z^3 - 3*z) / 24 * kurt -
            (2*z^3 - 5*z) / 36 * skew^2
    var_cf <- mu + sigma * z_cf
    out[[length(out) + 1]] <- data.table(
      method = "Cornish_Fisher", p = p, mu = mu, sigma = sigma,
      skew = skew, excess_kurt = kurt, z_cf = z_cf, VaR = var_cf,
      ES = NA_real_  # CF는 VaR만
    )
  }
  rbindlist(out, fill = TRUE)
}

# Empirical VaR/ES
emp_var_es <- function(returns, p_seq = c(0.95, 0.99, 0.995)) {
  r <- returns[!is.na(returns)]
  out <- list()
  for (p in p_seq) {
    var_e <- as.numeric(quantile(r, 1 - p))
    es_e <- mean(r[r <= var_e])
    out[[length(out) + 1]] <- data.table(
      method = "Empirical", p = p, n_obs = length(r),
      VaR = var_e, ES = es_e
    )
  }
  rbindlist(out, fill = TRUE)
}

# Parametric normal
norm_var_es <- function(returns, p_seq = c(0.95, 0.99, 0.995)) {
  r <- returns[!is.na(returns)]
  mu <- mean(r); sigma <- sd(r)
  out <- list()
  for (p in p_seq) {
    var_n <- mu + sigma * qnorm(1 - p)
    es_n <- mu - sigma * dnorm(qnorm(1 - p)) / (1 - p)
    out[[length(out) + 1]] <- data.table(
      method = "Normal", p = p, mu = mu, sigma = sigma,
      VaR = var_n, ES = es_n
    )
  }
  rbindlist(out, fill = TRUE)
}

# 4 series 적용 (137m post-2015 joint sample)
ret_3src <- ret_dt[has_tsmom == TRUE]
log_msg(sprintf("3-source joint sample: %d months", nrow(ret_3src)))

results_all <- list()
for (col in c("r_AR", "r_KR10y", "r_TSMOM", "hybrid_70_15_15")) {
  r <- ret_3src[[col]]
  log_msg(sprintf("--- VaR/ES comparison: %s (n=%d) ---", col, sum(!is.na(r))))

  emp <- emp_var_es(r); emp[, series := col]
  nrm <- norm_var_es(r); nrm[, series := col]
  cf <- cf_var(r); cf[, series := col]
  evt <- evt_var_es_pfaff(r, threshold_q = 0.90, min_exceed = 13L); evt[, series := col]

  combined <- rbindlist(list(emp, nrm, cf, evt), fill = TRUE)
  results_all[[col]] <- combined
}
results_dt <- rbindlist(results_all, fill = TRUE)
log_msg("=== VaR/ES Multi-Method Comparison ===")
print(results_dt[, .(series, method, p, VaR, ES, xi, beta)])
fwrite(results_dt, file.path(OUT_DIR, "var_es_multi_method_comparison.csv"))

# Method shopping log
log_msg("=== Method ranking (Hybrid VaR_99) ===")
hybrid_99 <- results_dt[series == "hybrid_70_15_15" & p == 0.99]
print(hybrid_99[, .(method, VaR, ES)])

# 256m full sample (AR + Hybrid only — TSMOM 가용 시기만 hybrid renorm)
log_msg("--- Full 256m sample comparison (AR vs Hybrid renorm) ---")
ar_full <- ret_dt$r_AR
hybrid_full <- ret_dt$hybrid_70_15_15

results_full <- rbindlist(list(
  cbind(emp_var_es(ar_full), series = "r_AR_full256m"),
  cbind(emp_var_es(hybrid_full), series = "hybrid_70_15_15_full256m"),
  cbind(cf_var(ar_full), series = "r_AR_full256m"),
  cbind(cf_var(hybrid_full), series = "hybrid_70_15_15_full256m"),
  cbind(evt_var_es_pfaff(ar_full, threshold_q = 0.90, min_exceed = 25L),
        series = "r_AR_full256m"),
  cbind(evt_var_es_pfaff(hybrid_full, threshold_q = 0.90, min_exceed = 25L),
        series = "hybrid_70_15_15_full256m")
), fill = TRUE)
log_msg("=== Full 256m VaR/ES comparison ===")
print(results_full[, .(series, method, p, VaR, ES)])
fwrite(results_full, file.path(OUT_DIR, "var_es_full256m_comparison.csv"))

log_msg("=== PATCH V4 COMPLETE ===")
