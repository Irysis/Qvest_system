cat("=== Differentiable SR Optimization: 3-Sleeve Portfolio ===\n")
cat("## 핵심아이디어: softmax 투영 + L-BFGS-B gradient 최적화 (PyTorch 대등)\n")
cat("## PIT: Expanding Window OOS (C1 완전 준수)\n")
cat("## 슬리브: VDplus / Q07_Defense / STR_930_M3\n\n")

# =============================================================
# 0. 라이브러리
# =============================================================
suppressPackageStartupMessages({
  library(data.table)
})

# =============================================================
# 1. 데이터 로드 및 정합
# =============================================================
BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"

# 1-a. 4슬리브 월별 수익률 (VDplus, Q07_proxy, STR_930)
rets_raw <- fread(file.path(BASE, "04_Research/strategies/portfolio_sim_930/portfolio_4sleeve_monthly_rets.csv"))
rets_raw[, Date := as.Date(Date)]

# 1-b. Q07 실제 성과 (STR_1662a)
q07_raw <- fread(file.path(BASE, "04_Research/strategies/STR_1662_defense_D25_Q07/output/performance_STR_1662a.csv"))
q07_raw[, Date := as.Date(Date)]
# 무효 행 제거 (마지막 0값 행)
q07_raw <- q07_raw[!(port_ret == 0 & turnover == 0)]
q07_raw <- q07_raw[!is.na(port_ret)]
setnames(q07_raw, "port_ret", "ret_q07_actual")

# 1-c. 병합: VDplus, STR_930 (portfolio_4sleeve에서) + Q07 실제값
#   VDplus: ret_vdp 컬럼 사용
#   STR_930: ret_930 컬럼 (2007-05 이후 유효)
#   Q07: STR_1662a 실제 성과 사용 (portfolio_4sleeve의 ret_q07는 같은 출처이므로 동일)

df <- merge(
  rets_raw[, .(Date, ret_vdp, ret_930)],
  q07_raw[, .(Date, ret_q07_actual)],
  by = "Date"
)

# ret_930 유효 기간만 (2007-05 이후)
df <- df[ret_930 != 0]
df <- df[order(Date)]

cat(sprintf("공통 유효 기간: %s ~ %s (%d개월)\n",
            min(df$Date), max(df$Date), nrow(df)))
cat(sprintf("슬리브별 연율 CAGR (단순 산술 평균x12):\n"))
cat(sprintf("  VDplus:  %.2f%%\n", mean(df$ret_vdp) * 12 * 100))
cat(sprintf("  Q07:     %.2f%%\n", mean(df$ret_q07_actual) * 12 * 100))
cat(sprintf("  STR_930: %.2f%%\n", mean(df$ret_930) * 12 * 100))
cat(sprintf("슬리브별 SR:\n"))
cat(sprintf("  VDplus:  %.3f\n", mean(df$ret_vdp) / sd(df$ret_vdp) * sqrt(12)))
cat(sprintf("  Q07:     %.3f\n", mean(df$ret_q07_actual) / sd(df$ret_q07_actual) * sqrt(12)))
cat(sprintf("  STR_930: %.3f\n", mean(df$ret_930) / sd(df$ret_930) * sqrt(12)))
cat(sprintf("상관관계:\n"))
cor_mat <- cor(df[, .(ret_vdp, ret_q07_actual, ret_930)])
print(round(cor_mat, 3))
cat("\n")

# =============================================================
# 2. 도구 함수
# =============================================================

# softmax: raw 파라미터 → simplex (합=1, 모두 양수)
softmax <- function(x) {
  e <- exp(x - max(x))
  e / sum(e)
}

# softmax 편미분 (Jacobian)
softmax_jacobian <- function(x) {
  s <- softmax(x)
  n <- length(s)
  J <- matrix(0, n, n)
  for (i in seq_len(n)) {
    for (j in seq_len(n)) {
      J[i, j] <- if (i == j) s[i] * (1 - s[j]) else -s[i] * s[j]
    }
  }
  J
}

# 포트폴리오 SR 계산 (연율화)
port_sr <- function(w, rets_mat) {
  port <- rets_mat %*% w
  mu  <- mean(port)
  sig <- sd(port)
  if (sig < 1e-10) return(-99)
  mu / sig * sqrt(12)
}

# SR의 raw_w에 대한 해석적 gradient (연쇄법칙)
sr_gradient <- function(raw_w, rets_mat) {
  w <- softmax(raw_w)
  J <- softmax_jacobian(raw_w)          # dw/d(raw_w): (3x3)

  port  <- as.vector(rets_mat %*% w)
  T_    <- length(port)
  mu    <- mean(port)
  sig   <- sd(port)                     # sample std (df=T-1)

  # dSR/dw (analytical)
  dmu_dw  <- colMeans(rets_mat)         # (3,)
  sig_sq  <- var(port)
  dvar_dw <- 2 * t(rets_mat) %*% (port - mu) / (T_ - 1)  # (3,)

  sqrt12 <- sqrt(12)
  # SR = mu/sig * sqrt12  →  dSR/dw = sqrt12 * (sig*dmu_dw - mu*(1/(2*sig))*dvar_dw) / sig^2
  dSR_dw <- sqrt12 * (sig * dmu_dw - mu * (0.5 / sig) * as.vector(dvar_dw)) / sig_sq

  # 연쇄법칙: dSR/d(raw_w) = J^T %*% dSR_dw
  grad <- as.vector(t(J) %*% dSR_dw)
  grad
}

# MDD 계산
calc_mdd <- function(rets) {
  cumret <- cumprod(1 + rets)
  running_max <- cummax(cumret)
  dd <- (cumret - running_max) / running_max
  min(dd)
}

# Calmar 목적함수: SR - lambda * |MDD| (MDD 패널티)
calmar_objective <- function(raw_w, rets_mat, lambda = 1.0) {
  w    <- softmax(raw_w)
  port <- as.vector(rets_mat %*% w)
  sr   <- mean(port) / sd(port) * sqrt(12)
  mdd  <- abs(calc_mdd(port))
  sr - lambda * mdd
}

# =============================================================
# 3. 최적화 함수들
# =============================================================
rets_mat <- as.matrix(df[, .(ret_vdp, ret_q07_actual, ret_930)])

# --- 3-A: 제약 없는 SR 최대화 (full-sample — 참고용, C1 위반) ---
cat("=== [참고용 / C1 위반] Full-Sample SR 최대화 ===\n")
cat("  (이 결과는 미래참조이므로 실투에 사용 불가)\n\n")

# negative SR을 목적함수로 (최소화)
neg_sr_fn <- function(raw_w) -port_sr(raw_w, rets_mat)
neg_sr_gr <- function(raw_w) -sr_gradient(raw_w, rets_mat)

set.seed(42)
best_full <- NULL
for (trial in 1:10) {
  init_w <- runif(3) - 0.5
  opt <- optim(
    par    = init_w,
    fn     = neg_sr_fn,
    gr     = neg_sr_gr,
    method = "L-BFGS-B",
    control = list(maxit = 2000)
  )
  if (is.null(best_full) || opt$value < best_full$value) {
    best_full <- opt
  }
}
w_full <- softmax(best_full$par)
sr_full <- port_sr(best_full$par, rets_mat)
port_full <- rets_mat %*% w_full
mdd_full  <- calc_mdd(port_full)
cat(sprintf("  최적 가중: VDplus=%.1f%%, Q07=%.1f%%, STR_930=%.1f%%\n",
            w_full[1]*100, w_full[2]*100, w_full[3]*100))
cat(sprintf("  최적 SR: %.3f  (그리드 서치 대비 변화: %.3f)\n", sr_full, sr_full - 1.198))
cat(sprintf("  MDD: %.1f%%\n\n", mdd_full*100))

# --- 3-B: 제약 조건 추가 (최소 5%, 최대 70%) ---
cat("=== [참고용 / C1 위반] 제약 가중 SR 최대화 (5%~70%) ===\n")

# simplex + box 제약: log-barrier 방식
neg_sr_barrier <- function(raw_w, mu_barrier = 0.01) {
  w <- softmax(raw_w)
  # 제약: 각 슬리브 ∈ [0.05, 0.70]
  if (any(w < 0.05) || any(w > 0.70)) {
    # 제약 위반 페널티 (log-barrier)
    barrier_lo <- -mu_barrier * sum(log(pmax(w - 0.05, 1e-8)))
    barrier_hi <- -mu_barrier * sum(log(pmax(0.70 - w, 1e-8)))
    return(-port_sr(raw_w, rets_mat) + barrier_lo + barrier_hi)
  }
  -port_sr(raw_w, rets_mat)
}

best_constrained <- NULL
for (trial in 1:10) {
  init_w <- runif(3) - 0.5
  opt <- tryCatch(
    optim(par = init_w, fn = neg_sr_barrier, method = "L-BFGS-B",
          control = list(maxit = 2000)),
    error = function(e) list(value = Inf, par = init_w)
  )
  if (is.null(best_constrained) || opt$value < best_constrained$value) {
    best_constrained <- opt
  }
}
w_con <- softmax(best_constrained$par)
sr_con <- port_sr(best_constrained$par, rets_mat)
port_con <- rets_mat %*% w_con
mdd_con  <- calc_mdd(port_con)
cat(sprintf("  최적 가중: VDplus=%.1f%%, Q07=%.1f%%, STR_930=%.1f%%\n",
            w_con[1]*100, w_con[2]*100, w_con[3]*100))
cat(sprintf("  최적 SR: %.3f\n", sr_con))
cat(sprintf("  MDD: %.1f%%\n\n", mdd_con*100))

# --- 3-C: Calmar 목적함수 (SR - lambda*MDD) ---
cat("=== [참고용 / C1 위반] Calmar 목적함수 (lambda=2.0) ===\n")

best_calmar <- NULL
for (trial in 1:10) {
  init_w <- runif(3) - 0.5
  opt <- tryCatch(
    optim(par = init_w, fn = function(r) -calmar_objective(r, rets_mat, lambda = 2.0),
          method = "L-BFGS-B", control = list(maxit = 2000)),
    error = function(e) list(value = Inf, par = init_w)
  )
  if (is.null(best_calmar) || opt$value < best_calmar$value) {
    best_calmar <- opt
  }
}
w_cal <- softmax(best_calmar$par)
sr_cal <- port_sr(best_calmar$par, rets_mat)
port_cal <- rets_mat %*% w_cal
mdd_cal  <- calc_mdd(port_cal)
cagr_cal <- (prod(1 + as.vector(port_cal)))^(12/nrow(df)) - 1
cat(sprintf("  최적 가중: VDplus=%.1f%%, Q07=%.1f%%, STR_930=%.1f%%\n",
            w_cal[1]*100, w_cal[2]*100, w_cal[3]*100))
cat(sprintf("  SR: %.3f  MDD: %.1f%%  CAGR: %.1f%%\n\n",
            sr_cal, mdd_cal*100, cagr_cal*100))

# =============================================================
# 4. Expanding Window OOS (PIT C1 완전 준수)
# =============================================================
cat("=== [PIT 준수] Expanding Window OOS SR 최적화 ===\n")
cat("  규칙: 처음 N개월로 학습 → N+1번째 월 적용 (N=60부터 시작)\n")
cat("  그리드 서치 기준치: SR 1.198 (full-sample 학습)\n\n")

N <- nrow(df)
MIN_TRAIN <- 60   # 최소 훈련 기간 (5년)

oos_rets  <- rep(NA_real_, N)
oos_ws    <- matrix(NA_real_, nrow = N, ncol = 3)

cat("  OOS 진행 중")
for (t in MIN_TRAIN:(N - 1)) {
  # IS: 1 ~ t
  rets_is <- rets_mat[1:t, ]

  best_t <- NULL
  for (trial in 1:5) {
    init_w <- runif(3) - 0.5
    opt <- tryCatch(
      optim(par = init_w,
            fn  = function(r) -port_sr(r, rets_is),
            gr  = function(r) -sr_gradient(r, rets_is),
            method = "L-BFGS-B",
            control = list(maxit = 500)),
      error = function(e) list(value = Inf, par = init_w)
    )
    if (is.null(best_t) || opt$value < best_t$value) {
      best_t <- opt
    }
  }

  w_t <- softmax(best_t$par)
  # OOS: t+1번째 수익률 적용
  oos_rets[t + 1]   <- sum(rets_mat[t + 1, ] * w_t)
  oos_ws[t + 1, ]   <- w_t

  if ((t - MIN_TRAIN) %% 20 == 0) cat(".")
}
cat(" 완료\n\n")

# OOS 기간만 추출
oos_idx  <- which(!is.na(oos_rets))
oos_port <- oos_rets[oos_idx]
oos_dates <- df$Date[oos_idx]

oos_sr   <- mean(oos_port) / sd(oos_port) * sqrt(12)
oos_cagr <- (prod(1 + oos_port))^(12/length(oos_port)) - 1
oos_mdd  <- calc_mdd(oos_port)
oos_vol  <- sd(oos_port) * sqrt(12)

cat(sprintf("  OOS 기간: %s ~ %s (%d개월)\n",
            min(oos_dates), max(oos_dates), length(oos_idx)))
cat(sprintf("  OOS SR:   %.3f\n", oos_sr))
cat(sprintf("  OOS CAGR: %.1f%%\n", oos_cagr * 100))
cat(sprintf("  OOS MDD:  %.1f%%\n", oos_mdd * 100))
cat(sprintf("  OOS Vol:  %.1f%%\n", oos_vol * 100))
cat(sprintf("\n  그리드 서치 SR 1.198 대비 OOS SR: %.3f (%.1f%%p)\n",
            oos_sr, (oos_sr - 1.198) * 100))

# =============================================================
# 5. OOS 기간 평균 가중 분포 분석
# =============================================================
cat("\n=== OOS 평균 가중 배분 추이 ===\n")
ws_oos <- oos_ws[oos_idx, ]
cat(sprintf("  평균 가중: VDplus=%.1f%%, Q07=%.1f%%, STR_930=%.1f%%\n",
            mean(ws_oos[, 1]) * 100,
            mean(ws_oos[, 2]) * 100,
            mean(ws_oos[, 3]) * 100))
cat(sprintf("  가중 표준편차: VDplus=%.1f%%, Q07=%.1f%%, STR_930=%.1f%%\n",
            sd(ws_oos[, 1]) * 100,
            sd(ws_oos[, 2]) * 100,
            sd(ws_oos[, 3]) * 100))

# 시계열 5분위로 가중 변화 추이
n_oos <- nrow(ws_oos)
cat(sprintf("\n  초기(%s~%s): VDp=%.0f%% Q07=%.0f%% 930=%.0f%%\n",
            oos_dates[1], oos_dates[round(n_oos * 0.2)],
            mean(ws_oos[1:round(n_oos*0.2), 1]) * 100,
            mean(ws_oos[1:round(n_oos*0.2), 2]) * 100,
            mean(ws_oos[1:round(n_oos*0.2), 3]) * 100))
cat(sprintf("  중기(%s~%s): VDp=%.0f%% Q07=%.0f%% 930=%.0f%%\n",
            oos_dates[round(n_oos * 0.4)], oos_dates[round(n_oos * 0.6)],
            mean(ws_oos[round(n_oos*0.4):round(n_oos*0.6), 1]) * 100,
            mean(ws_oos[round(n_oos*0.4):round(n_oos*0.6), 2]) * 100,
            mean(ws_oos[round(n_oos*0.4):round(n_oos*0.6), 3]) * 100))
cat(sprintf("  후기(%s~%s): VDp=%.0f%% Q07=%.0f%% 930=%.0f%%\n",
            oos_dates[round(n_oos * 0.8)], tail(oos_dates, 1),
            mean(ws_oos[round(n_oos*0.8):n_oos, 1]) * 100,
            mean(ws_oos[round(n_oos*0.8):n_oos, 2]) * 100,
            mean(ws_oos[round(n_oos*0.8):n_oos, 3]) * 100))

# =============================================================
# 6. 비교 요약
# =============================================================
cat("\n")
cat("=================================================================\n")
cat("  최종 비교 요약\n")
cat("=================================================================\n")
cat(sprintf("  방법                | 가중 (VDp/Q07/930)    | SR     | MDD\n"))
cat(sprintf("  --------------------|----------------------|--------|--------\n"))
cat(sprintf("  그리드 서치         | 45%% / 30%% / 25%%      | 1.198  | -??\n"))
cat(sprintf("  Full SR 최대화*     | %2.0f%% / %2.0f%% / %2.0f%%      | %.3f  | %.1f%%\n",
            w_full[1]*100, w_full[2]*100, w_full[3]*100, sr_full, mdd_full*100))
cat(sprintf("  제약 SR 최대화*     | %2.0f%% / %2.0f%% / %2.0f%%      | %.3f  | %.1f%%\n",
            w_con[1]*100, w_con[2]*100, w_con[3]*100, sr_con, mdd_con*100))
cat(sprintf("  Calmar 목적(λ=2)*   | %2.0f%% / %2.0f%% / %2.0f%%      | %.3f  | %.1f%%\n",
            w_cal[1]*100, w_cal[2]*100, w_cal[3]*100, sr_cal, mdd_cal*100))
cat(sprintf("  Expanding OOS (PIT) | %2.0f%% / %2.0f%% / %2.0f%%      | %.3f  | %.1f%%\n",
            mean(ws_oos[, 1])*100, mean(ws_oos[, 2])*100, mean(ws_oos[, 3])*100,
            oos_sr, oos_mdd*100))
cat("  (* C1 위반 — 참고용만, 실투 사용 불가)\n")
cat("=================================================================\n\n")

# =============================================================
# 7. 결과 저장
# =============================================================
OUT_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/04_Research/strategies/portfolio_sim_930"

# OOS 수익률 시계열 저장
oos_result <- data.table(
  Date     = oos_dates,
  oos_ret  = oos_port,
  w_vdp    = ws_oos[, 1],
  w_q07    = ws_oos[, 2],
  w_930    = ws_oos[, 3]
)
fwrite(oos_result, file.path(OUT_DIR, "sr_optim_oos_rets.csv"))

# 요약 저장
summary_res <- list(
  method = "L-BFGS-B_softmax_expanding_oos",
  oos_period = c(as.character(min(oos_dates)), as.character(max(oos_dates))),
  oos_n_months = length(oos_port),
  oos_sr = round(oos_sr, 4),
  oos_cagr_pct = round(oos_cagr * 100, 2),
  oos_mdd_pct  = round(oos_mdd * 100, 2),
  oos_vol_pct  = round(oos_vol * 100, 2),
  avg_w_vdp    = round(mean(ws_oos[, 1]), 4),
  avg_w_q07    = round(mean(ws_oos[, 2]), 4),
  avg_w_930    = round(mean(ws_oos[, 3]), 4),
  grid_search_sr = 1.198,
  grid_search_w  = c(0.45, 0.30, 0.25),
  pit_compliant = TRUE
)
saveRDS(summary_res, file.path(OUT_DIR, "sr_optim_summary.rds"))
cat("결과 저장 완료:\n")
cat(sprintf("  - %s/sr_optim_oos_rets.csv\n", OUT_DIR))
cat(sprintf("  - %s/sr_optim_summary.rds\n", OUT_DIR))
cat("\n=== 완료 ===\n")
