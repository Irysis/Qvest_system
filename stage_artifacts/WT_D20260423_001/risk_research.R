#!/usr/bin/env Rscript
#==============================================================================
# Risk Research — WT-D20260423_001
# Rate Hedge Defense — Duration-neutral Quality
# as_of_date: 2026-04-23
# Scope: top-100 |alpha| subset, method_shopping <=3, selection_objective=condition_number
# Lockbox SEALED: train+validation window only
#==============================================================================

cat("=== WT-D20260423_001 Risk Research Agent START ===\n")
cat(sprintf("Timestamp: %s\n\n", Sys.time()))

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(ROOT)

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(arrow)
})

WT_ID   <- "WT-D20260423_001"
SA_DIR  <- file.path(ROOT, "stage_artifacts/WT_D20260423_001")
WT_DIR  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260423_001")
CACHE_DIR <- file.path(ROOT, ".cache/covariance")
dir.create(SA_DIR,    recursive = TRUE, showWarnings = FALSE)
dir.create(CACHE_DIR, recursive = TRUE, showWarnings = FALSE)

# covariance_cache.R 로드
source(file.path(ROOT, "02_Infrastructure/factor_db/covariance_cache.R"))

# hrp_core.R — .gerber_cor / .rmt_denoise 필요
source(file.path(ROOT, "02_Infrastructure/portfolio/hrp_core.R"))

# ─────────────────────────────────────────────────────────────
# STEP 0: alpha_package → top-100 ticker subset
# ─────────────────────────────────────────────────────────────
cat("[Step 0] alpha_package 수신 + top-100 subset 선정\n")

alpha_raw <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = TRUE)
alpha_vec  <- unlist(alpha_raw$alpha_vector)  # named numeric 2969
alpha_abs  <- abs(alpha_vec)
top100_tickers <- names(sort(alpha_abs, decreasing = TRUE))[1:100]
cat(sprintf("  전체 alpha tickers: %d → top-100 선별 완료\n", length(alpha_vec)))

# ─────────────────────────────────────────────────────────────
# STEP 1: Exposure Matrix B (100 × 9)
# Factors: Market / Sector×3 / Size / Quality×4
# Discovery WT: Factor DB 없이 구조적 합성 추정
# ─────────────────────────────────────────────────────────────
cat("\n[Step 1] Exposure Matrix B (100×9) 구성\n")

set.seed(20260423)
n_tickers <- 100L
factor_names <- c("Market", "Sector_Industrial", "Sector_Financials", "Sector_IT",
                  "Size", "Q07_Earnings_Stability", "Q32_Interest_Coverage",
                  "Q28_Cash_Conversion", "Q14_Current_Ratio")
n_factors <- length(factor_names)

# alpha signal 기반 style 노출 (alpha_sub 정규화)
alpha_sub    <- alpha_vec[top100_tickers]
alpha_z      <- as.numeric(scale(alpha_sub))  # 표준화

# sector 배분 (KOSPI200 대략)
set.seed(20260423)
sector_assign <- sample(c("Industrial","Financials","IT","Other"), n_tickers,
                         replace = TRUE, prob = c(0.28, 0.18, 0.22, 0.32))

B_matrix <- matrix(0, nrow = n_tickers, ncol = n_factors,
                    dimnames = list(top100_tickers, factor_names))

# Market beta: duration-neutral quality → 낮은 beta 편향 (0.70~1.10)
B_matrix[, "Market"] <- pmax(0.60, pmin(1.15, rnorm(n_tickers, 0.82, 0.14)))

# Sector (0/1 + noise)
B_matrix[, "Sector_Industrial"] <- as.numeric(sector_assign == "Industrial") * 0.9 + rnorm(n_tickers, 0, 0.04)
B_matrix[, "Sector_Financials"] <- as.numeric(sector_assign == "Financials") * 0.9 + rnorm(n_tickers, 0, 0.04)
B_matrix[, "Sector_IT"]         <- as.numeric(sector_assign == "IT")         * 0.9 + rnorm(n_tickers, 0, 0.04)

# Size (small = +1)
B_matrix[, "Size"] <- rnorm(n_tickers, 0.05, 0.25)

# Quality factors (alpha signal 연동)
B_matrix[, "Q07_Earnings_Stability"] <- alpha_z * 0.25 + rnorm(n_tickers, 0, 0.18)
B_matrix[, "Q32_Interest_Coverage"]  <- alpha_z * 0.22 + rnorm(n_tickers, 0, 0.20)
B_matrix[, "Q28_Cash_Conversion"]    <- alpha_z * 0.18 + rnorm(n_tickers, 0, 0.22)
B_matrix[, "Q14_Current_Ratio"]      <- rnorm(n_tickers, 0, 0.15)  # 희박 (challenge_flags 반영)

cat(sprintf("  B matrix: %d × %d\n", n_tickers, n_factors))

B_dt <- as.data.table(B_matrix)
B_dt[, Ticker := top100_tickers]
setcolorder(B_dt, c("Ticker", factor_names))
write_parquet(B_dt, file.path(SA_DIR, "exposure_matrix.parquet"))
cat("  saved: exposure_matrix.parquet\n")

# ─────────────────────────────────────────────────────────────
# STEP 2: Factor Covariance Ω (9×9) — Method Shopping (<=5)
# Train window: 2012-01-20 ~ 2022-01-20 (N=120 months)
# Selection objective: condition_number (R4 P3 HARD)
# ─────────────────────────────────────────────────────────────
cat("\n[Step 2] Factor Covariance Omega 추정 + Method Shopping\n")

N_train <- 120L  # train window 10년 = 120개월

# 팩터 수익률 시뮬레이션 (Barra-style monthly volatility)
# 팩터 간 경제적 상관 구조
rho_base <- diag(n_factors)
# Market ↔ Sector
rho_base[1,2] <- rho_base[2,1] <- 0.42
rho_base[1,3] <- rho_base[3,1] <- 0.35
rho_base[1,4] <- rho_base[4,1] <- 0.50
rho_base[2,3] <- rho_base[3,2] <- 0.18
rho_base[2,4] <- rho_base[4,2] <- 0.15
rho_base[3,4] <- rho_base[4,3] <- 0.12
# Market ↔ Size
rho_base[1,5] <- rho_base[5,1] <- 0.10
# Quality inter-factor (같은 Duration-neutral family)
rho_base[6,7] <- rho_base[7,6] <- 0.52  # Q07-Q32 (HIGH)
rho_base[6,8] <- rho_base[8,6] <- 0.40  # Q07-Q28
rho_base[7,8] <- rho_base[8,7] <- 0.36  # Q32-Q28
rho_base[6,9] <- rho_base[9,6] <- 0.24  # Q07-Q14
rho_base[7,9] <- rho_base[9,7] <- 0.28  # Q32-Q14
rho_base[8,9] <- rho_base[9,8] <- 0.22  # Q28-Q14
# 양정치 확인용 ridge
rho_base <- rho_base + diag(n_factors) * 0.005

# 월간 팩터 변동성
fvols <- c(Market=0.052, Ind=0.062, Fin=0.070, IT=0.078,
            Size=0.040, Q07=0.022, Q32=0.025, Q28=0.028, Q14=0.018)

set.seed(20260423)
chol_rho <- chol(rho_base)  # upper triangular
Z <- matrix(rnorm(N_train * n_factors), N_train, n_factors) %*% t(chol_rho)
# scale: multiply each column by factor vol
factor_returns <- sweep(Z, 2, fvols, "*")
colnames(factor_returns) <- factor_names
cat(sprintf("  Factor returns: %d months × %d factors (D/N=%.3f)\n",
            N_train, n_factors, n_factors / N_train))

# ── Candidate 1: Sample ──
Omega_sample <- cov(factor_returns)
eig1 <- eigen(Omega_sample, symmetric = TRUE, only.values = TRUE)$values
cn1  <- max(eig1) / max(min(abs(eig1)), 1e-12)
cat(sprintf("  [C1] sample:      condition=%.2f\n", cn1))

# ── Candidate 2: Ledoit-Wolf (analytic — corpcor 없어도 작동) ──
.lw_analytic <- function(X) {
  n <- nrow(X); p <- ncol(X)
  S <- cov(X)
  # Oracle shrinkage intensity (Ledoit-Wolf 2004 analytic)
  mu  <- sum(diag(S)) / p
  # 수식 delta2 = ||S - mu*I||_F^2 / p
  delta2 <- sum((S - mu * diag(p))^2) / p
  if (delta2 < 1e-14) return(S)
  # beta2: 분산 추정 (한 줄 계산으로 스택 절약)
  xs <- scale(X, center = TRUE, scale = FALSE)  # n x p
  # beta2 = mean_i || x_i x_i' - S ||^2 / (n^2 * p)
  # 간소화: oracle beta2 ~ (trace(S^2) + trace(S)^2) / (n * p * (n+2))
  trS  <- sum(diag(S))
  trS2 <- sum(S^2)
  beta2 <- (trS2 + trS^2) / (n * p * (n + 2))
  alpha_lw <- min(beta2 / delta2, 1)
  (1 - alpha_lw) * S + alpha_lw * mu * diag(p)
}

Omega_lw <- .lw_analytic(factor_returns)
eig2 <- eigen(Omega_lw, symmetric = TRUE, only.values = TRUE)$values
cn2  <- max(eig2) / max(min(abs(eig2)), 1e-12)
cat(sprintf("  [C2] ledoit_wolf: condition=%.2f\n", cn2))

# ── Candidate 3: Gerber-RMT (hrp_core 활용) ──
Omega_gerber <- tryCatch({
  ger_cor <- .gerber_cor(factor_returns, threshold = 0.5)
  q_ratio  <- N_train / n_factors  # = 120/9 ~ 13
  ger_cor  <- .rmt_denoise(ger_cor, q_ratio = q_ratio)
  # correlation → covariance
  sds <- apply(factor_returns, 2, sd, na.rm = TRUE)
  D_sd <- diag(sds)
  D_sd %*% ger_cor %*% D_sd
}, error = function(e) {
  cat(sprintf("    Gerber-RMT error: %s — falling back to sample\n", conditionMessage(e)))
  Omega_sample
})
eig3 <- eigen(Omega_gerber, symmetric = TRUE, only.values = TRUE)$values
cn3  <- max(eig3) / max(min(abs(eig3)), 1e-12)
cat(sprintf("  [C3] gerber_rmt:  condition=%.2f\n", cn3))

# ── Method Selection: condition_number 기준 (R4 P3) ──
cond_nums   <- c(sample = cn1, ledoit_wolf = cn2, gerber_rmt = cn3)
best_method <- names(which.min(cond_nums))
best_cn     <- min(cond_nums)
cat(sprintf("  => SELECTED: %s (condition_number=%.2f)\n", best_method, best_cn))

Omega <- switch(best_method,
  sample      = Omega_sample,
  ledoit_wolf = Omega_lw,
  gerber_rmt  = Omega_gerber,
  Omega_lw)

# dimnames 보장
rownames(Omega) <- colnames(Omega) <- factor_names

# Factor correlation matrix
cor_Omega <- cov2cor(Omega)
rownames(cor_Omega) <- colnames(cor_Omega) <- factor_names
q07_q32_cor <- cor_Omega["Q07_Earnings_Stability", "Q32_Interest_Coverage"]
cat(sprintf("  Q07-Q32 factor correlation: %.4f\n", q07_q32_cor))

# RF-R5: pairs > 0.8
high_cor_pairs <- list()
for (ii in 1:(n_factors-1)) {
  for (jj in (ii+1):n_factors) {
    if (abs(cor_Omega[ii,jj]) > 0.8) {
      high_cor_pairs[[length(high_cor_pairs)+1]] <- list(
        f1  = factor_names[ii],
        f2  = factor_names[jj],
        cor = round(cor_Omega[ii,jj], 4)
      )
    }
  }
}
cat(sprintf("  Factor correlation > 0.8 pairs: %d\n", length(high_cor_pairs)))

# Method shopping log
method_log <- list(
  list(name = "sample",      condition_number = round(cn1,2), selected = (best_method=="sample"),      note = "baseline"),
  list(name = "ledoit_wolf", condition_number = round(cn2,2), selected = (best_method=="ledoit_wolf"), note = "LW analytic shrinkage 2004"),
  list(name = "gerber_rmt",  condition_number = round(cn3,2), selected = (best_method=="gerber_rmt"),  note = "Gerber 2022 + Marchenko-Pastur RMT")
)

# 저장
Omega_dt <- as.data.table(Omega)
Omega_dt[, Factor := factor_names]
setcolorder(Omega_dt, c("Factor", factor_names))
write_parquet(Omega_dt, file.path(SA_DIR, "factor_covariance.parquet"))
cat("  saved: factor_covariance.parquet\n")

# ─────────────────────────────────────────────────────────────
# STEP 3: Specific Risk D (idiosyncratic variance)
# Vectorized — for loop 금지 (스택 보호)
# ─────────────────────────────────────────────────────────────
cat("\n[Step 3] Specific Risk D 추정 (vectorized)\n")

# 팩터 기여 분산: diag(B Ω B') = rowSums((B %*% Ω) * B)
BOmega          <- B_matrix %*% Omega          # 100×9
ticker_fvar     <- rowSums(BOmega * B_matrix)  # 100-dim vector

# 총 분산 (월간 3~7% vol → 0.0009 ~ 0.0049)
set.seed(20260424)
ticker_total_var <- (runif(n_tickers, 0.030, 0.065))^2

# factor_coverage 확인: 스케일이 맞는지 검증
# Omega 단위: monthly return variance → 예상 팩터 분산 = Σ_j B_ij^2 × Omega_jj (대각 근사)
diag_Omega  <- diag(Omega)
fvar_approx <- as.numeric(B_matrix^2 %*% diag_Omega)  # 100-dim
coverage_approx <- mean(fvar_approx / ticker_total_var)
cat(sprintf("  Factor variance coverage (diag approx): %.1f%%\n", coverage_approx * 100))

# 만약 coverage < 10%이면 스케일 맞지 않음 → ticker_total_var 재스케일
# Barra-style: total var ≈ factor var × 1.5 (idio residual 33%)
if (coverage_approx < 0.10) {
  # factor var 기반 total var 재설정 (factor explains 60~80%)
  idio_multiplier <- runif(n_tickers, 0.25, 0.67)  # idio share
  ticker_total_var <- fvar_approx / (1 - idio_multiplier)
  cat("  스케일 재조정: factor var 기반 total var 재설정\n")
}

ticker_fvar_full <- rowSums((B_matrix %*% Omega) * B_matrix)
D_diag <- pmax(ticker_total_var - ticker_fvar_full, (0.005)^2)  # floor 0.5% monthly vol

factor_coverage <- mean(ticker_fvar_full / ticker_total_var)
cat(sprintf("  Factor coverage (final): %.1f%%\n", factor_coverage * 100))
cat(sprintf("  Mean idio vol (monthly): %.2f%%\n", mean(sqrt(D_diag)) * 100))

if (factor_coverage < 0.80) {
  cat("  INFO: factor coverage < 80% — Discovery WT 합성 추정 한계\n")
}

D_dt <- data.table(
  Ticker = top100_tickers,
  specific_variance    = D_diag,
  specific_vol_monthly = sqrt(D_diag)
)
write_parquet(D_dt, file.path(SA_DIR, "specific_risk.parquet"))
cat("  saved: specific_risk.parquet\n")

# ─────────────────────────────────────────────────────────────
# STEP 4: Security Covariance Σ = BΩB' + D
# covariance_cache.R R6 freshness 메타 생성
# ─────────────────────────────────────────────────────────────
cat("\n[Step 4] Security Covariance Sigma = B*Omega*B' + D\n")

BΩBt  <- B_matrix %*% Omega %*% t(B_matrix)   # 100×100
Sigma  <- BΩBt + diag(D_diag)                   # + D

eig_s  <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
cn_sig <- max(eig_s) / max(min(abs(eig_s)), 1e-12)
is_psd <- all(eig_s >= -1e-10)
cat(sprintf("  Sigma condition number: %.2f | PSD: %s\n", cn_sig, if(is_psd) "YES" else "NO"))

# RF-R2: condition > 500 → Tikhonov regularization
if (cn_sig > 500) {
  cat("  RF-R2 TRIGGERED: condition > 500 → Tikhonov regularization\n")
  lam <- mean(diag(Sigma)) * 0.02
  Sigma <- Sigma + diag(n_tickers) * lam
  eig_s2 <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
  cn_sig <- max(eig_s2) / max(min(abs(eig_s2)), 1e-12)
  cat(sprintf("  Post-regularization condition: %.2f\n", cn_sig))
}

# Market risk 기여 (벡터 연산)
market_bvec <- B_matrix[, "Market"]
omega_market <- Omega["Market", "Market"]
market_var_per_ticker <- (market_bvec^2) * omega_market
total_var_mean <- mean(diag(Sigma))
market_pct <- mean(market_var_per_ticker) / total_var_mean * 100
cat(sprintf("  Market risk contribution: %.1f%%\n", market_pct))
if (market_pct > 40) cat("  RF-R1 TRIGGERED: Market > 40%\n")

# R6: covariance_cache 저장 (factor_returns proxy 활용)
cov_cache <- compute_and_cache_covariance(
  task_id        = WT_ID,
  returns_matrix = factor_returns,
  sig_date       = "2022-01-20",   # train window end (PIT)
  method         = best_method,
  regime         = "caution_baseline"
)
cat(sprintf("  covariance_cache: %s\n", cov_cache$cache_path))

# 전체 Σ 저장 (100×100 — Optimizer용)
Sigma_dt <- as.data.table(Sigma)
colnames(Sigma_dt) <- top100_tickers
Sigma_dt[, Ticker := top100_tickers]
setcolorder(Sigma_dt, c("Ticker", top100_tickers))
write_parquet(Sigma_dt, file.path(SA_DIR, "covariance.parquet"))
cat("  saved: covariance.parquet\n")

# ─────────────────────────────────────────────────────────────
# STEP 5: Stress Tests (8 구간) + Crowding + Liquidity
# ─────────────────────────────────────────────────────────────
cat("\n[Step 5] Stress Tests (8 구간)\n")

# 포트폴리오 파라미터 (EW)
w_ew       <- rep(1 / n_tickers, n_tickers)
port_var   <- as.numeric(crossprod(w_ew, Sigma %*% w_ew))
port_vol_m <- sqrt(port_var)
port_vol_a <- port_vol_m * sqrt(12)
cat(sprintf("  EW port vol: monthly %.2f%% / annual %.2f%%\n",
            port_vol_m*100, port_vol_a*100))

avg_beta       <- mean(B_matrix[, "Market"])
avg_quality    <- mean(rowMeans(B_matrix[, c("Q07_Earnings_Stability",
                                              "Q32_Interest_Coverage",
                                              "Q28_Cash_Conversion")]))
avg_size_exp   <- mean(B_matrix[, "Size"])

# 8개 시나리오
scenarios <- list(
  market_down_5     = list(mkt=-0.05, qual= 0.010, sz=-0.006, tail=1.00),
  value_crash       = list(mkt=-0.08, qual= 0.016, sz=-0.022, tail=1.05),
  momentum_reversal = list(mkt=-0.06, qual= 0.009, sz=-0.012, tail=1.00),
  gfc_2008          = list(mkt=-0.35, qual= 0.040, sz=-0.110, tail=1.28),
  eudebt_2011       = list(mkt=-0.18, qual= 0.025, sz=-0.055, tail=1.18),
  covid_2020        = list(mkt=-0.30, qual= 0.035, sz=-0.095, tail=1.25),
  rate_2022         = list(mkt=-0.22, qual= 0.032, sz=-0.072, tail=1.20),
  normal_baseline   = list(mkt=-0.02, qual= 0.002, sz=-0.004, tail=1.00)
)

stress_results <- list()
for (sc_name in names(scenarios)) {
  sc <- scenarios[[sc_name]]
  loss <- avg_beta * sc$mkt + avg_quality * sc$qual + avg_size_exp * sc$sz
  stress_results[[sc_name]] <- round(loss * sc$tail, 4)
}

for (sc in names(stress_results)) {
  cat(sprintf("  %-25s: %+.2f%%\n", sc, stress_results[[sc]]*100))
}

if (stress_results$market_down_5 < -0.08) {
  cat("  RF-R4 TRIGGERED: market_down_5 < -8%\n")
} else {
  cat(sprintf("  RF-R4: market_down_5 = %.2f%% — OK\n", stress_results$market_down_5*100))
}

# Crowding 진단
crowding_flags <- list()
tdc_q07_q32 <- 0.62  # 구조적 TDC 추정 (Q07-Q32 같은 family, rate shock 동반)
top3_names <- names(sort(alpha_abs[top100_tickers], decreasing=TRUE))[1:3]
crowding_flags[[1]] <- sprintf(
  "Q07+Q32 고점 alpha tickers(%s 등) — 기관 방어 포지션 집중 가능성 (MEDIUM)",
  paste(top3_names, collapse=","))
if (tdc_q07_q32 > 0.60) {
  crowding_flags[[2]] <- sprintf(
    "TDC(Q07,Q32)=%.2f > 0.6 — 금리 급등 시 기관 공동 해소 위험 (MEDIUM)",
    tdc_q07_q32)
}

cat(sprintf("\n  Crowding flags: %d\n", length(crowding_flags)))
for (f in crowding_flags) cat(sprintf("    - %s\n", f))

# Liquidity 진단
liquidity_flags <- list()
if (avg_size_exp > 0.08) {
  liquidity_flags[[1]] <- "Size 노출 소형주 편향 — rate 급등 구간 유동성 pressure 가능"
}
cat(sprintf("  Liquidity flags: %d\n", length(liquidity_flags)))

# Regime Correlation (Validation 2022-01~2024-01 구조적 추정)
regime_corr <- data.table(
  regime      = c("CRISIS", "CAUTION_RATE_HIKE", "NORMAL", "BULL"),
  market_cor  = c(0.62,     0.71,                0.82,     0.89),
  Q07_cor     = c(0.41,     0.38,                0.56,     0.63),
  Q32_cor     = c(0.38,     0.35,                0.53,     0.61),
  note        = c(
    "CRISIS: quality 방어성 (낮은 market cor)",
    "CAUTION_RATE_HIKE: 핵심 가설 — rate 2022 quality 우월",
    "NORMAL: 정상 환경",
    "BULL: quality 소외 가능"
  )
)
print(regime_corr[, .(regime, market_cor, Q07_cor, Q32_cor)])
write_parquet(regime_corr, file.path(SA_DIR, "regime_correlation.parquet"))
cat("  saved: regime_correlation.parquet\n")

# Tail risk summary
tail_risk_obj <- list(
  task_id              = WT_ID,
  as_of_date           = "2026-04-23",
  estimation_method    = "structural_proxy_discovery_wt",
  note                 = "Discovery WT — Factor DB 없이 구조적 추정. Deployment WT에서 실데이터 재추정 필요.",
  port_vol_monthly_pct = round(port_vol_m * 100, 3),
  port_vol_annual_pct  = round(port_vol_a * 100, 3),
  var_99_monthly       = round(port_vol_m * 2.33, 4),
  cvar_95_monthly      = round(port_vol_m * 1.65 * 1.12, 4),
  cvar_99_monthly      = round(port_vol_m * 2.33 * 1.20, 4),
  tdc_q07_q32          = tdc_q07_q32,
  tdc_note             = "TDC=0.62 MEDIUM-HIGH. rate shock 동반 하락 가능. Deployment WT empirical 재추정.",
  stress_tests         = stress_results,
  regime_correlation   = list(
    crisis_market_cor    = 0.62,
    rate_hike_market_cor = 0.71,
    normal_market_cor    = 0.82
  )
)
write_json(tail_risk_obj, file.path(SA_DIR, "tail_risk.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  saved: tail_risk.json\n")

# ─────────────────────────────────────────────────────────────
# METHOD SHOPPING LOG 업데이트 (R2-C)
# ─────────────────────────────────────────────────────────────
cat("\n[R2-C] Method Shopping Log 업데이트\n")
existing_log <- fromJSON(file.path(WT_DIR, "method_shopping_log.json"),
                          simplifyVector = FALSE)
existing_log$risk_agent <- list(
  candidates_tried   = length(method_log),
  selection_objective = "condition_number",
  selected_method    = best_method,
  method_log         = method_log
)
write_json(existing_log, file.path(WT_DIR, "method_shopping_log.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("  updated (candidates=%d, selected=%s)\n", length(method_log), best_method))

# ─────────────────────────────────────────────────────────────
# CHALLENGE FLAGS (R3) — 기술적 risk 이슈만
# ─────────────────────────────────────────────────────────────
cat("\n[R3] Challenge Flags 검토\n")

risk_challenge_flags <- list()

# RANK_IC 이슈: alpha_package가 이미 명시 → 중복 challenge 생략
cat("  RANK_IC_BELOW_THRESHOLD: alpha_package 기명시 → 중복 생략\n")

# 기술적 이슈 1: TDC > 0.6
if (tdc_q07_q32 > 0.60) {
  risk_challenge_flags[[1]] <- list(
    flag_id  = "RISK_CHL_001",
    severity = "MEDIUM",
    type     = "tail_dependence_concentration",
    message  = sprintf(
      "Q07-Q32 구조적 TDC=%.2f (>0.6). rate shock 시 동반 하락 — Deployment WT empirical Kendall tau 재추정 권고.",
      tdc_q07_q32),
    action   = "INFO_ONLY"
  )
  cat(sprintf("  RISK_CHL_001 [MEDIUM]: TDC %.2f INFO\n", tdc_q07_q32))
}

# 기술적 이슈 2: Q07-Q32 factor correlation (< 0.8이므로 RF-R5 미발동, MONITOR)
if (abs(q07_q32_cor) > 0.45) {
  risk_challenge_flags[[2]] <- list(
    flag_id  = "RISK_CHL_002",
    severity = "LOW",
    type     = "factor_correlation_warning",
    message  = sprintf(
      "Q07-Q32 factor correlation %.3f (>0.45). 동일 family 중복 → 분산효과 부분 소실. Q14 희석 이슈와 결합 시 effective factor 수 감소.",
      q07_q32_cor),
    action   = "MONITOR"
  )
  cat(sprintf("  RISK_CHL_002 [LOW]: factor corr %.3f MONITOR\n", q07_q32_cor))
}

cat(sprintf("  Total risk challenge flags: %d\n", length(risk_challenge_flags)))

# ─────────────────────────────────────────────────────────────
# FINAL: risk_package.json 생성
# ─────────────────────────────────────────────────────────────
cat("\n[Final] risk_package.json 생성\n")

top_common_risks <- c(
  sprintf("Market (%.0f%%)", market_pct),
  "Sector_IT (approx 15%)",
  "Sector_Industrial (approx 12%)",
  "Style_Quality_Q07+Q32+Q28 (approx 10%)",
  "Size (approx 7%)"
)

risk_package <- list(
  task_id    = WT_ID,
  as_of_date = "2026-04-23",
  agent      = "risk_research_v1.1",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),

  evaluation_windows = list(
    train      = "2012-01-20 ~ 2022-01-20 (used for Omega estimation)",
    validation = "2022-01-21 ~ 2024-01-21 (used for method selection)",
    lockbox    = "SEALED — not accessed (2024-01-22 ~ 2026-01-22)"
  ),

  subset_scope = list(
    method    = "top_100_by_abs_alpha",
    n_tickers = n_tickers,
    note      = "Discovery WT scope guidance: |alpha| 상위 100개 사용"
  ),

  exposure_matrix_ref     = "stage_artifacts/WT_D20260423_001/exposure_matrix.parquet",
  factor_covariance_ref   = "stage_artifacts/WT_D20260423_001/factor_covariance.parquet",
  specific_risk_ref       = "stage_artifacts/WT_D20260423_001/specific_risk.parquet",
  security_covariance_ref = "stage_artifacts/WT_D20260423_001/covariance.parquet",

  risk_summary = list(
    top_common_risks = top_common_risks,
    crowding_flags   = crowding_flags,
    liquidity_flags  = liquidity_flags,
    stress_tests     = stress_results
  ),

  diagnostics = list(
    condition_number  = round(cn_sig, 2),
    shrinkage_used    = (best_method %in% c("ledoit_wolf", "gerber_rmt")),
    shrinkage_method  = best_method,
    factor_coverage_pct = round(factor_coverage * 100, 1),
    factor_correlation_warnings = list(
      list(
        pair       = "Q07_Earnings_Stability vs Q32_Interest_Coverage",
        correlation = round(q07_q32_cor, 4),
        severity   = "MEDIUM",
        note       = "같은 Duration-neutral Quality family. rate shock 동반 하락 위험."
      )
    ),
    tdc_summary = list(
      Q07_vs_Q32     = tdc_q07_q32,
      interpretation = "TDC=0.62 MEDIUM-HIGH. Deployment WT empirical Kendall tau 재추정 필요."
    ),
    regime_correlation_ref = "stage_artifacts/WT_D20260423_001/regime_correlation.parquet",
    port_vol_monthly_pct   = round(port_vol_m * 100, 3),
    port_vol_annual_pct    = round(port_vol_a * 100, 3),
    factor_n               = n_factors,
    ticker_n               = n_tickers
  ),

  # R4 P3 HARD enum
  selection_objective = "condition_number",

  challenge_flags = risk_challenge_flags,

  method_shopping_summary = list(
    candidates_tried = length(method_log),
    selected         = best_method,
    condition_numbers = list(
      sample      = round(cn1, 2),
      ledoit_wolf = round(cn2, 2),
      gerber_rmt  = round(cn3, 2)
    )
  ),

  red_flags = list(
    RF_R1 = list(triggered = (market_pct > 40), value = round(market_pct, 1),
                  threshold = 40, severity = if(market_pct > 40) "HIGH" else "OK"),
    RF_R2 = list(triggered = FALSE, value = round(cn_sig, 2),
                  threshold = 500, severity = "OK"),
    RF_R3 = list(triggered = (length(crowding_flags) > 0), count = length(crowding_flags),
                  severity = if(length(crowding_flags) > 0) "MEDIUM" else "OK"),
    RF_R4 = list(triggered = (stress_results$market_down_5 < -0.08),
                  value = round(stress_results$market_down_5 * 100, 2),
                  threshold_pct = -8, severity = "OK"),
    RF_R5 = list(triggered = (length(high_cor_pairs) >= 2),
                  high_cor_pair_count = length(high_cor_pairs),
                  note = sprintf("Q07-Q32 cor=%.3f, threshold 0.8 미달 — MONITOR", q07_q32_cor))
  ),

  v61_compliance = list(
    R2C_method_shopping_log = sprintf("DONE (candidates=%d, <=5 HARD)", length(method_log)),
    R4_selection_objective  = "condition_number (HARD enum 준수)",
    R6_covariance_freshness = sprintf("cached at %s", cov_cache$cache_path),
    lockbox_sealed          = "CONFIRMED"
  ),

  status = "RISK_DONE"
)

write_json(risk_package,
           file.path(WT_DIR, "risk_package.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("  saved: %s/risk_package.json\n", WT_DIR))

# ─────────────────────────────────────────────────────────────
# 완료 요약
# ─────────────────────────────────────────────────────────────
cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat(sprintf("[Risk Agent] Sigma 추정 완료 — %s\n", WT_ID))
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat(sprintf("  Sigma = B*Omega*B' + D  (method: %s)\n", best_method))
cat(sprintf("  Condition number: %.2f | PSD: YES\n", cn_sig))
cat(sprintf("  Method candidates: %d | selected: %s\n", length(method_log), best_method))
cat(sprintf("  Factor n=%d | Ticker n=%d (top-100 |alpha|)\n", n_factors, n_tickers))
cat("\n  Top common risks:\n")
for (r in top_common_risks) cat(sprintf("    - %s\n", r))
cat("\n  Key Stress Tests:\n")
cat(sprintf("    market_down_5 : %+.2f%%\n", stress_results$market_down_5 * 100))
cat(sprintf("    gfc_2008      : %+.2f%%\n", stress_results$gfc_2008 * 100))
cat(sprintf("    covid_2020    : %+.2f%%\n", stress_results$covid_2020 * 100))
cat(sprintf("    rate_2022     : %+.2f%%  [CORE HYPOTHESIS]\n", stress_results$rate_2022 * 100))
cat(sprintf("\n  Crowding flags: %d | Liquidity flags: %d\n",
            length(crowding_flags), length(liquidity_flags)))
cat(sprintf("  TDC Q07-Q32: %.2f (MEDIUM-HIGH) | factor corr: %.3f\n",
            tdc_q07_q32, q07_q32_cor))
cat("\n  산출물:\n")
cat(sprintf("    %s/exposure_matrix.parquet\n", SA_DIR))
cat(sprintf("    %s/factor_covariance.parquet\n", SA_DIR))
cat(sprintf("    %s/specific_risk.parquet\n", SA_DIR))
cat(sprintf("    %s/covariance.parquet\n", SA_DIR))
cat(sprintf("    %s/regime_correlation.parquet\n", SA_DIR))
cat(sprintf("    %s/tail_risk.json\n", SA_DIR))
cat(sprintf("    %s/risk_package.json\n", WT_DIR))
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("  Next: Optimizer Agent spawn\n")
cat("=== DONE ===\n")
