# =============================================================================
# FQ-108 shared library — 대각(specific variance) 처치 + 위험예측 정확도 도구
#   metric_type = risk_forecast_accuracy_diagnostic
#   R4 P3: selection_objective = estimation quality (QLIKE). SR/IR/alpha 미사용.
#   P1 lib(QLIKE/DM/MZ/est_*)을 상속하고 대각 처치만 신설.
# =============================================================================
suppressPackageStartupMessages({ library(data.table) })

ROOT_108 <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT_108, "04_Research/method_frontier/fq057_p1_risk_accuracy/p1_lib.R"))

# ---- 상관행렬 추출 (대각 처치는 상관구조를 건드리지 않음) --------------------
cor_from_cov_108 <- function(Sig) {
  sds <- sqrt(pmax(diag(Sig), .Machine$double.eps))
  C <- Sig / outer(sds, sds)
  diag(C) <- 1
  C[!is.finite(C)] <- 0
  list(C = C, sd = sds)
}

# ---- 예측분산 = w' D^(1/2) C D^(1/2) w  (Σ 재조립 없이 이차형식) -------------
#   wvec: named. Cmat/ sd_new: elig 순서 정렬 필수.
pred_var_scaled <- function(wvec, Cmat, sd_new) {
  nm <- colnames(Cmat)
  w <- numeric(length(nm)); names(w) <- nm
  common <- intersect(names(wvec), nm)
  w[common] <- as.numeric(wvec[common])
  u <- w * sd_new
  v <- as.numeric(crossprod(u, Cmat %*% u))
  max(v, 0)
}

# ---- 횡단면 z (sd=0 방어) ----------------------------------------------------
cs_z <- function(v) {
  ok <- is.finite(v)
  if (sum(ok) < 3L) return(rep(0, length(v)))
  m <- mean(v[ok]); s <- sd(v[ok])
  out <- rep(0, length(v))
  if (!is.finite(s) || s < 1e-12) return(out)
  out[ok] <- (v[ok] - m) / s
  out
}

# ---- winsorize (고정 규칙, 전 arm 동일 적용) --------------------------------
wins <- function(v, p = 0.005) {
  q <- quantile(v, c(p, 1 - p), na.rm = TRUE)
  pmin(pmax(v, q[1]), q[2])
}

# ---- 확장창 횡단면 회귀 적합 + 예측 -----------------------------------------
#   train: data.table with y + 회귀변수 컬럼들. newd: 예측용 (동일 컬럼).
#   반환: 예측 분산 v̂ = exp(ŷ + s²/2)  (로그정규 Jensen 보정)
fit_predict_logvar <- function(train, newd, vars) {
  cn <- c("(int)", vars)
  y <- wins(train$y)
  Xtr <- cbind(1, as.matrix(train[, ..vars])); colnames(Xtr) <- cn
  ok <- is.finite(y) & rowSums(!is.finite(Xtr)) == 0
  y <- y[ok]; Xtr <- Xtr[ok, , drop = FALSE]
  if (length(y) < 200L) return(NULL)
  # rank-deficient 방어 (예: lw_linear p>n 퇴화로 x 가 사실상 상수)
  qrf <- qr(Xtr)
  full_rank <- (qrf$rank == ncol(Xtr))
  if (!full_rank) {
    keep <- sort(qrf$pivot[seq_len(qrf$rank)])
    Xtr <- Xtr[, keep, drop = FALSE]
  }
  vars_used <- colnames(Xtr)
  fit <- .lm.fit(Xtr, y)
  b <- fit$coefficients
  s2 <- sum(fit$residuals^2) / max(1L, (length(y) - length(b)))
  Xne <- cbind(1, as.matrix(newd[, ..vars])); colnames(Xne) <- cn
  Xne <- Xne[, vars_used, drop = FALSE]
  Xne[!is.finite(Xne)] <- 0
  yhat <- as.numeric(Xne %*% b)
  list(v = exp(yhat + s2 / 2), coef = setNames(as.numeric(b), vars_used),
       s2 = s2, n_train = length(y), rank_ok = full_rank)
}

# ---- Fama-MacBeth NW t (월별 계수 시계열) -----------------------------------
fm_nw_t <- function(coefs, lag = 3L) {
  v <- coefs[is.finite(coefs)]
  if (length(v) < 10L) return(list(mean = mean(v), t = NA_real_, n = length(v)))
  fit <- lm(v ~ 1)
  vc <- sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE)
  ct <- lmtest::coeftest(fit, vcov. = vc)
  list(mean = unname(ct[1, 1]), t = unname(ct[1, 3]), n = length(v))
}

cat("[fq108_lib] loaded — diagonal treatment + scaled qform + FM-NW\n")
