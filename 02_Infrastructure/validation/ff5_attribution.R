# v53 Sprint 2 S2.10/S2.9: FF5a Attribution — Fama-French 5-factor alpha 검증
# 한국 시장 FF5 팩터 회귀 + Newey-West 보정 + alpha t-stat.
# Grade A gate 후보는 |t_alpha| > 3.0 (Harvey, Liu & Zhu 2016) 강제.
#
# 현재 구현 (v53 S2.9 통합 — 2026-04-17):
#   - v1 soft penalty (hurdle_gate.R D074로 연결, -10~0점)
#   - Grade A hard gate: strict_mode 기본 TRUE — run_hurdle_gate(ff5_result=...) 주입 시
#     |t_alpha| < 3.0 이면 Grade A → B 강등 (hurdle_gate.R D074 블록)
#   - QVEST_STRICT_MODE=FALSE 환경변수로 opt-out 가능
#
# Usage:
#   source("02_Infrastructure/validation/ff5_attribution.R")
#   r <- compute_ff5_alpha(strat_ret_xts, ff_factors_xts, nw_lags = 4)

suppressPackageStartupMessages({
  library(data.table)
})

.ff5_root <- function() {
  cands <- c(
    "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
    "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
    Sys.getenv("PROJECT_ROOT", ""),
    getwd()
  )
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}

# ── Newey-West 표준오차 (핸드롤) ──────────────────────────────────────
.newey_west_se <- function(lm_model, lags = 4L) {
  e <- residuals(lm_model)
  X <- model.matrix(lm_model)
  n <- nrow(X)
  k <- ncol(X)

  XtX_inv <- solve(crossprod(X))
  S0 <- crossprod(X * e)

  S <- S0
  for (l in seq_len(lags)) {
    w_l <- 1 - l / (lags + 1)
    X_l <- X[(l + 1):n, , drop = FALSE]
    e_l <- e[(l + 1):n]
    X_m <- X[1:(n - l), , drop = FALSE]
    e_m <- e[1:(n - l)]
    Gamma <- crossprod(X_l * e_l, X_m * e_m)
    S <- S + w_l * (Gamma + t(Gamma))
  }
  cov_nw <- XtX_inv %*% S %*% XtX_inv
  sqrt(diag(cov_nw))
}

# ── FF5 회귀 ──────────────────────────────────────────────────────────
# strat_ret: numeric vector (일간 또는 월간, ff_factors 와 빈도 동일)
# ff_factors: data.table with columns c("Date", "Mkt.RF", "SMB", "HML", "RMW", "CMA", "RF")
compute_ff5_alpha <- function(strat_ret, ff_factors, dates = NULL,
                               nw_lags = 4L) {
  if (is.null(dates)) {
    if (!is.null(attr(strat_ret, "dates"))) dates <- attr(strat_ret, "dates")
  }
  dt <- data.table(Date = dates, Ret = as.numeric(strat_ret))
  ff <- as.data.table(ff_factors)
  setnames(ff, old = names(ff), new = gsub("-", ".", names(ff)))
  merged <- merge(dt, ff, by = "Date", all.x = FALSE)
  if (nrow(merged) < 36L) {
    return(list(
      converged = FALSE,
      reason = sprintf("n=%d < 36 (최소 3년 월간)", nrow(merged)),
      n_obs = nrow(merged)
    ))
  }
  merged[, Ex_Ret := Ret - RF]
  fit <- lm(Ex_Ret ~ Mkt.RF + SMB + HML + RMW + CMA, data = merged)
  coefs <- coef(fit)
  ses <- tryCatch(.newey_west_se(fit, lags = nw_lags),
                  error = function(e) sqrt(diag(vcov(fit))))
  t_vals <- coefs / ses
  p_vals <- 2 * pt(-abs(t_vals), df = fit$df.residual)

  list(
    converged = TRUE,
    n_obs = nrow(merged),
    alpha = coefs[["(Intercept)"]],
    alpha_t = t_vals[["(Intercept)"]],
    alpha_p = p_vals[["(Intercept)"]],
    alpha_annualized = coefs[["(Intercept)"]] * 12,
    betas = list(
      mkt = list(coef = coefs[["Mkt.RF"]], t = t_vals[["Mkt.RF"]]),
      smb = list(coef = coefs[["SMB"]], t = t_vals[["SMB"]]),
      hml = list(coef = coefs[["HML"]], t = t_vals[["HML"]]),
      rmw = list(coef = coefs[["RMW"]], t = t_vals[["RMW"]]),
      cma = list(coef = coefs[["CMA"]], t = t_vals[["CMA"]])
    ),
    r_squared = summary(fit)$r.squared,
    adj_r_squared = summary(fit)$adj.r.squared,
    nw_lags = nw_lags
  )
}

# ── Harvey 2016 threshold 판정 ────────────────────────────────────────
ff5_verdict <- function(ff5_result, t_thresh_A = 3.0, t_thresh_B = 2.5) {
  if (!isTRUE(ff5_result$converged)) {
    return(list(pass_A = FALSE, pass_B = FALSE,
                reason = ff5_result$reason %||% "not converged"))
  }
  t_abs <- abs(ff5_result$alpha_t)
  list(
    alpha_t = ff5_result$alpha_t,
    alpha_t_abs = t_abs,
    pass_A = t_abs >= t_thresh_A,
    pass_B = t_abs >= t_thresh_B,
    harvey_2016 = t_abs >= 3.0,
    verdict = if (t_abs >= t_thresh_A) "Grade A eligible"
              else if (t_abs >= t_thresh_B) "Grade B eligible"
              else "Below threshold"
  )
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 ||
                             (length(a) == 1 && is.na(a))) b else a

cat("[ff5_attribution] Loaded. Functions: compute_ff5_alpha / ff5_verdict\n")
