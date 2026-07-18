# =============================================================================
# FQ-057 NP4-P1 shared library — risk forecast accuracy diagnostic
#   metric_type = risk_forecast_accuracy_diagnostic
#   R4 P3 준수: selection_objective = estimation quality (QLIKE forecast loss).
#   NO SR/IR/alpha/return-performance metric anywhere in comparison/selection.
#
#   Structural Σ arms:
#     lw_linear   — hrp_core .get_cor_cov("ledoit_wolf")  [incumbent, p>n 퇴화]
#     lw_nls      — hrp_core .get_cor_cov("lw_nls")        [NP3 등재본]
#     ewma_struct — RiskMetrics 지수가중 다변량 공분산 (λ 고정)
#   Direct(univariate) baseline:
#     ewma_direct — 포트 자기 실현분산의 지수가중(⑧행 TE 기준선 EWMA 후보)
# =============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

ROOT_P1 <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"

# ---- hrp_core reuse (defines .get_cor_cov: ledoit_wolf / lw_nls) -------------
source(file.path(ROOT_P1, "02_Infrastructure/portfolio/hrp_core.R"))

# ---- structural Σ estimators -------------------------------------------------
# 입력 R: n x p 월간수익 행렬 (rows=oldest..newest, cols=Ticker). 반환: p x p cov.
est_lw_linear_p1 <- function(R) {
  # p>n 퇴화 경고는 정상(진단 대상). muffle 하여 로그만.
  withCallingHandlers(
    .get_cor_cov(R, "ledoit_wolf")$cov,
    warning = function(w) invokeRestart("muffleWarning"))
}
est_lw_nls_p1 <- function(R) {
  .get_cor_cov(R, "lw_nls")$cov
}

# RiskMetrics 지수가중 공분산 (zero-mean 관례, 가중합 정규화 형태).
#   Σ = Σ_s w_s r_s r_s',  w_s ∝ λ^{(n-s)}  (최신 관측 가중 최대), sum(w)=1.
#   p>n 이어도 계산은 되나 rank <= n 로 특이(구조적 EWMA도 대형 유니버스 TE엔 한계).
est_ewma_struct_p1 <- function(R, lambda = 0.94) {
  R <- as.matrix(R)
  n <- nrow(R); p <- ncol(R)
  # zero-mean RiskMetrics 관례 (demean 하지 않음)
  age <- (n - 1L):0L                      # 최신 관측 age=0
  w   <- (1 - lambda) * lambda^age
  w   <- w / sum(w)
  Rw  <- R * sqrt(w)                       # 각 행 스케일
  S   <- crossprod(Rw)                     # = sum_s w_s r_s r_s'
  S   <- (S + t(S)) / 2
  dimnames(S) <- list(colnames(R), colnames(R))
  S
}

# ---- 진단: cond number / PSD -------------------------------------------------
cond_psd_p1 <- function(Sig) {
  ev <- tryCatch(eigen(Sig, symmetric = TRUE, only.values = TRUE)$values,
                 error = function(e) NA_real_)
  if (all(is.na(ev))) return(list(cond = NA_real_, min_ev = NA_real_, psd = NA))
  mn <- min(ev); mx <- max(ev)
  list(cond = if (mn <= 0) Inf else mx / mn,
       min_ev = mn,
       psd = mn >= -1e-8 * max(1, mx))
}

# ---- 예측분산: 이차형식 w' Σ w (음수 방어) -----------------------------------
pred_var_qform <- function(wvec, Sig) {
  nm <- names(wvec)
  common <- intersect(nm, colnames(Sig))
  wv <- wvec[common]
  S  <- Sig[common, common, drop = FALSE]
  v  <- as.numeric(t(wv) %*% S %*% wv)
  max(v, 0)                                # 수치오차 음수 클립 (예측분산 >= 0)
}

# ---- 손실함수 ---------------------------------------------------------------
# QLIKE (Patton 2011, robust to noisy volatility proxy): RV/h - ln(RV/h) - 1.
#   h = 예측분산, RV = 실현분산 (둘 다 월간분산 스케일). >=0, h=RV 에서 최소 0.
qlike_loss <- function(realized_var, pred_var) {
  h  <- pmax(pred_var, .Machine$double.eps)
  rv <- pmax(realized_var, .Machine$double.eps)
  r  <- rv / h
  r - log(r) - 1
}
# 부차: 변동성(sd) 제곱오차 → RMSE(vol) 계산용 per-obs 오차
volsq_err <- function(realized_var, pred_var) {
  (sqrt(pmax(realized_var, 0)) - sqrt(pmax(pred_var, 0)))^2
}

# ---- paired Diebold-Mariano (NW HAC) on loss differences ---------------------
#   d = loss_A - loss_B (arm A vs B).  H0: E[d]=0.
#   음수 t → A 손실이 낮음(A 우월).  lag = NW HAC.
dm_nw <- function(loss_A, loss_B, lag = 3L) {
  d <- as.numeric(loss_A) - as.numeric(loss_B)
  ok <- is.finite(d); d <- d[ok]
  n <- length(d)
  if (n < 10L) return(list(mean_d = mean(d), t = NA_real_, n = n))
  fit <- lm(d ~ 1)
  vc  <- sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE)
  ct  <- lmtest::coeftest(fit, vcov. = vc)
  list(mean_d = unname(ct[1, 1]), t = unname(ct[1, 3]), n = n)
}

# ---- Mincer-Zarnowitz: RV ~ a + b*pred (calibration diagnostic) --------------
mz_reg <- function(realized_var, pred_var) {
  ok <- is.finite(realized_var) & is.finite(pred_var)
  rv <- realized_var[ok]; pv <- pred_var[ok]
  if (length(rv) < 10L) return(list(a = NA, b = NA, r2 = NA, n = length(rv)))
  fit <- lm(rv ~ pv)
  s <- summary(fit)
  list(a = unname(coef(fit)[1]), b = unname(coef(fit)[2]),
       r2 = s$r.squared, n = length(rv))
}

# ---- 평균 손실 요약 ----------------------------------------------------------
mean_qlike <- function(realized_var, pred_var) {
  l <- qlike_loss(realized_var, pred_var); mean(l[is.finite(l)])
}
rmse_vol_ann <- function(realized_var, pred_var, scale = 1) {
  # 월간분산 → 연율화 vol RMSE (scale=12 이면 연율). 여기선 월간 그대로(scale=1).
  e <- volsq_err(realized_var, pred_var); sqrt(mean(e[is.finite(e)])) * sqrt(scale)
}

cat("[p1_lib] loaded — estimators + QLIKE/DM/MZ helpers\n")
