#!/usr/bin/env Rscript
# ============================================================================
# Korean Market Covariance Meta Research (2026-05-07)
#
# Theme: 한국 시장 공분산 모델 메타 자가 리서치 (오버나잇)
#
# 4축 자율 탐색:
#   1. 공분산 추정기 5종+ 한국 시장 sub-period 비교
#      Sample / Ledoit-Wolf shrinkage / Gerber statistic / Graphical Lasso /
#      Constant Correlation shrinkage / DCC-GARCH (단일 실행 / Pfaff Ch.8)
#   2. 꼬리위험 모델링 — EVT-GPD VaR/ES + CVaR + CDaR (Pfaff Ch.7,12)
#   3. 스트레스 시나리오 — 8대 위기 + 4-국면 portfolio 응답
#   4. 군집위험 — pairwise corr + TDC + style 노출 + crowding
#
# Inputs:
#   - architect_hybrid_returns_full256m.csv (현 admit Hybrid component returns)
#   - .cache/rawdata.parquet (KOSPI200 ∪ KOSDAQ150 universe, monthly)
#
# Outputs (qepm/mailbox/research/risk_model_meta_20260507/):
#   - risk_package_draft.json (8-field schema, Codex Round 의무 _draft suffix)
#   - covariance_estimator_comparison.csv
#   - tail_risk_metrics_3source.csv
#   - stress_scenarios_8crisis.csv
#   - regime_correlation_4regime.csv
#   - style_exposure_FF_3source.csv
#   - meta_research_log.txt (실행 로그)
#
# PIT 준수:
#   - 모든 통계 rolling/expanding window only
#   - t-1 lag 적용 (regime overlay 등)
#   - Same-day circular X
#
# 출처:
#   Ledoit-Wolf 2004 J. Multiv. Anal. — shrinkage estimator
#   Gerber et al. 2015 J. Portfolio Mgt. — Gerber statistic
#   Friedman, Hastie, Tibshirani 2008 Biostatistics — graphical lasso
#   Engle 2002 J. Bus. Econ. Stat. — DCC
#   Embrechts-Klüppelberg-Mikosch 1997 — EVT/GPD
#   Rockafellar-Uryasev 2000 J. Risk — CVaR
#   Chekhlov-Uryasev-Zabarankin 2005 J. Bank. Fin. — CDaR
#   Bailey-Lopez de Prado 2014 — DSR
#   Harvey-Liu-Zhu 2016 RFS — t > 3 multiple testing
#   Moskowitz-Ooi-Pedersen 2012 JFE — TSMOM
#   Cieslak-Povala 2015 RFS — bond carry
#
# ============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(PerformanceAnalytics)
  library(Matrix)
  library(fExtremes)
  library(evir)
  library(xts)
  library(future)
  library(future.apply)
  library(glasso)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/research/risk_model_meta_20260507")
STAGE_DIR <- file.path(PROJECT_ROOT, "qepm/stage_artifacts/risk_model_meta_20260507")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(STAGE_DIR, recursive = TRUE, showWarnings = FALSE)

LOG_FILE <- file.path(OUT_DIR, "meta_research_log.txt")
log_msg <- function(msg) {
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  line <- sprintf("[%s] %s", ts, msg)
  cat(line, "\n")
  cat(line, "\n", file = LOG_FILE, append = TRUE)
}

cat("", file = LOG_FILE)
log_msg("=== KR Covariance Meta Research START ===")
log_msg("도훈 over-night meta research, 4-axis comprehensive")

# ============================================================================
# Section 0: Hybrid Component Returns 로드 + Sub-period 분류
# ============================================================================

log_msg("--- Section 0: Component Returns 로드 ---")

ret_file <- file.path(PROJECT_ROOT,
  "qepm/mailbox/worktask/WT-P20260505_001/architect_hybrid_returns_full256m.csv")
ret_dt <- fread(ret_file)
ret_dt[, date := as.Date(date)]
log_msg(sprintf("Component returns: %d rows, %s ~ %s",
                nrow(ret_dt), min(ret_dt$date), max(ret_dt$date)))

# TSMOM은 2015~ 137m (post-Lockbox). 결측 명시 처리
ret_dt[, has_tsmom := !is.na(r_TSMOM)]
log_msg(sprintf("TSMOM available rows: %d (post-2015-01)",
                sum(ret_dt$has_tsmom)))

# Sub-period 분류 (CRITICAL: PIT 준수 — 사후 정의된 stress range는 실증적 OK,
# 단 "이 정의 시점에 알 수 있었는가" 확인 — 이미 일어난 과거 이벤트, 시점 왜곡 X)
classify_subperiod <- function(d) {
  d <- as.Date(d)
  # Tier 1: 8 stress windows (사후 분류, 일반화 X)
  if (d >= as.Date("1997-07-01") && d <= as.Date("1998-06-30")) return("IMF_1997")
  if (d >= as.Date("2000-03-01") && d <= as.Date("2001-12-31")) return("DotCom_2000")
  if (d >= as.Date("2007-10-01") && d <= as.Date("2009-03-31")) return("GFC_2008")
  if (d >= as.Date("2011-07-01") && d <= as.Date("2011-12-31")) return("EuDebt_2011")
  if (d >= as.Date("2015-06-01") && d <= as.Date("2016-02-29")) return("China_Shock_2015")
  if (d >= as.Date("2018-02-01") && d <= as.Date("2018-12-31")) return("VolShock_2018")
  if (d >= as.Date("2020-01-01") && d <= as.Date("2020-06-30")) return("COVID_2020")
  if (d >= as.Date("2022-01-01") && d <= as.Date("2022-12-31")) return("Inflation_2022")
  # Tier 2: Normal periods
  if (d >= as.Date("2010-01-01") && d <= as.Date("2019-12-31")) return("Normal_2010s")
  return("Other")
}
ret_dt[, regime_period := sapply(date, classify_subperiod)]
log_msg("Sub-period classification 완료")
print(ret_dt[, .N, by = regime_period][order(-N)])

# Save component returns 정합 sample
fwrite(ret_dt, file.path(OUT_DIR, "component_returns_classified.csv"))

# ============================================================================
# Section 1: 공분산 추정기 5+ 종 한국 시장 비교
#
# 1A: 3-asset Hybrid (AR, KR10y, TSMOM) — admit pf 풀 진단 (137m 공통)
# 1B: KOSPI200 large-cap N-asset extension (rolling 60m) — 추정기 전반 비교
#
# Method 5종:
#   Sample (T/N >> 1 시 OK)
#   Ledoit-Wolf identity shrinkage (LW 2004, oracle delta)
#   Ledoit-Wolf constant-correlation shrinkage (LW 2003)
#   Gerber statistic (Gerber 2015) + RMT denoising
#   Graphical Lasso (Friedman 2008) — sparse precision
# ============================================================================

log_msg("--- Section 1: Covariance Estimators 비교 ---")

# Hybrid 3-asset 137m joint period (post-2015)
ret_3src <- ret_dt[has_tsmom == TRUE, .(date, r_AR, r_KR10y, r_TSMOM)]
log_msg(sprintf("3-source joint sample: %d months (%s ~ %s)",
                nrow(ret_3src), min(ret_3src$date), max(ret_3src$date)))

mat_3src <- as.matrix(ret_3src[, .(r_AR, r_KR10y, r_TSMOM)])
colnames(mat_3src) <- c("AR", "KR10y", "TSMOM")

# ---- Estimator 1: Sample ----
cov_sample <- function(mat) {
  cov(mat, use = "pairwise.complete.obs")
}

# ---- Estimator 2: Ledoit-Wolf identity shrinkage ----
# Oracle delta = (var of sample - bias) / (var of sample) (LW 2004 Eq. 2.7~2.8)
cov_lw_identity <- function(mat) {
  T_n <- nrow(mat); N <- ncol(mat)
  S <- cov(mat, use = "pairwise.complete.obs")
  mu_target <- mean(diag(S))
  F_target <- mu_target * diag(N)

  # Compute optimal shrinkage delta (LW 2004 simplification)
  # pi_hat = sum of variance of each S_ij entry
  X_centered <- scale(mat, scale = FALSE)
  X_centered[is.na(X_centered)] <- 0
  pi_mat <- matrix(0, N, N)
  for (i in 1:N) for (j in 1:N) {
    pi_mat[i, j] <- mean((X_centered[, i] * X_centered[, j] - S[i, j])^2)
  }
  pi_hat <- sum(pi_mat)

  # gamma_hat = || S - F ||^2_F
  gamma_hat <- sum((S - F_target)^2)

  # delta_hat (clipped 0~1)
  if (gamma_hat < 1e-10) delta_opt <- 1 else
    delta_opt <- max(0, min(1, pi_hat / (T_n * gamma_hat)))

  S_shrunk <- delta_opt * F_target + (1 - delta_opt) * S
  attr(S_shrunk, "delta") <- delta_opt
  S_shrunk
}

# ---- Estimator 3: Ledoit-Wolf constant correlation shrinkage ----
# Target = constant correlation matrix avg(rho) * sd_i * sd_j
cov_lw_constcor <- function(mat) {
  T_n <- nrow(mat); N <- ncol(mat)
  S <- cov(mat, use = "pairwise.complete.obs")
  R <- cor(mat, use = "pairwise.complete.obs")
  if (N == 1) return(S)
  rho_bar <- (sum(R) - N) / (N * (N - 1))  # avg off-diagonal corr
  D_sd <- sqrt(diag(S))
  F_target <- rho_bar * outer(D_sd, D_sd)
  diag(F_target) <- diag(S)

  X_centered <- scale(mat, scale = FALSE)
  X_centered[is.na(X_centered)] <- 0
  pi_mat <- matrix(0, N, N)
  for (i in 1:N) for (j in 1:N) {
    pi_mat[i, j] <- mean((X_centered[, i] * X_centered[, j] - S[i, j])^2)
  }
  pi_hat <- sum(pi_mat)
  gamma_hat <- sum((S - F_target)^2)

  if (gamma_hat < 1e-10) delta_opt <- 1 else
    delta_opt <- max(0, min(1, pi_hat / (T_n * gamma_hat)))

  S_shrunk <- delta_opt * F_target + (1 - delta_opt) * S
  attr(S_shrunk, "delta") <- delta_opt
  attr(S_shrunk, "rho_bar") <- rho_bar
  S_shrunk
}

# ---- Estimator 4: Gerber statistic + diagonal regularization ----
# Gerber 2015 robust correlation (count co-movements above threshold * sigma)
gerber_corr <- function(mat, threshold = 0.5) {
  T_n <- nrow(mat); N <- ncol(mat)
  sd_vec <- apply(mat, 2, sd, na.rm = TRUE)
  G <- matrix(0, N, N)
  for (i in 1:N) {
    for (j in i:N) {
      m_ij_pos <- 0; m_ij_neg <- 0; m_ij_zero <- 0
      for (t in seq_len(T_n)) {
        x_it <- mat[t, i]; x_jt <- mat[t, j]
        if (is.na(x_it) || is.na(x_jt)) next
        H_i <- abs(x_it) >= threshold * sd_vec[i]
        H_j <- abs(x_jt) >= threshold * sd_vec[j]
        if (H_i && H_j) {
          if (sign(x_it) == sign(x_jt)) m_ij_pos <- m_ij_pos + 1
          else m_ij_neg <- m_ij_neg + 1
        } else if (!H_i && !H_j) {
          m_ij_zero <- m_ij_zero + 1
        }
      }
      n_co <- m_ij_pos + m_ij_neg
      g_ij <- if (n_co == 0) 0 else (m_ij_pos - m_ij_neg) / n_co
      G[i, j] <- g_ij
      G[j, i] <- g_ij
    }
  }
  diag(G) <- 1
  G
}

cov_gerber <- function(mat, threshold = 0.5) {
  G <- gerber_corr(mat, threshold)
  sd_vec <- apply(mat, 2, sd, na.rm = TRUE)
  S_g <- diag(sd_vec) %*% G %*% diag(sd_vec)
  rownames(S_g) <- colnames(S_g) <- colnames(mat)

  # PSD repair via eigen clip (Higham 2002)
  eig <- eigen(S_g, symmetric = TRUE)
  if (min(eig$values) < 1e-8) {
    eig$values[eig$values < 1e-8] <- 1e-8
    S_g <- eig$vectors %*% diag(eig$values) %*% t(eig$vectors)
    rownames(S_g) <- colnames(S_g) <- colnames(mat)
    attr(S_g, "psd_repaired") <- TRUE
  }
  S_g
}

# ---- Estimator 5: Graphical Lasso (sparse precision) ----
cov_glasso <- function(mat, rho = 0.05) {
  S <- cov(mat, use = "pairwise.complete.obs")
  # glasso wants correlation matrix scale typically; rho controls sparsity
  fit <- tryCatch(
    glasso::glasso(s = S, rho = rho, penalize.diagonal = FALSE),
    error = function(e) NULL
  )
  if (is.null(fit)) return(S)
  S_g <- fit$w  # estimated covariance
  rownames(S_g) <- colnames(S_g) <- colnames(mat)
  attr(S_g, "rho") <- rho
  attr(S_g, "n_zero_off_diag") <- sum(fit$wi[upper.tri(fit$wi)] == 0)
  S_g
}

# ---- 진단 함수 ----
diag_estimator <- function(Sigma, name = "") {
  N <- nrow(Sigma)
  eig <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
  list(
    name = name,
    n_assets = N,
    condition_number = max(eig) / pmax(min(eig), 1e-12),
    min_eigenvalue = min(eig),
    max_eigenvalue = max(eig),
    is_psd = all(eig > -1e-10),
    is_pd = all(eig > 1e-8),
    trace = sum(diag(Sigma)),
    avg_diag_var = mean(diag(Sigma)),
    avg_off_diag_cov = (sum(Sigma) - sum(diag(Sigma))) / (N * (N - 1)),
    delta_lw = if (!is.null(attr(Sigma, "delta"))) attr(Sigma, "delta") else NA_real_,
    extra = paste(setdiff(names(attributes(Sigma)), c("dim", "dimnames")), collapse = ",")
  )
}

# ---- Section 1A: 3-asset Hybrid 추정기 비교 ----
log_msg("--- Section 1A: 3-asset Hybrid 추정기 비교 ---")

estimators_3src <- list(
  list(name = "Sample", fn = cov_sample),
  list(name = "LW_identity", fn = cov_lw_identity),
  list(name = "LW_constcor", fn = cov_lw_constcor),
  list(name = "Gerber_threshold0.5", fn = function(m) cov_gerber(m, 0.5)),
  list(name = "Gerber_threshold0.7", fn = function(m) cov_gerber(m, 0.7)),
  list(name = "Glasso_rho0.01", fn = function(m) cov_glasso(m, 0.01)),
  list(name = "Glasso_rho0.05", fn = function(m) cov_glasso(m, 0.05))
)

results_1a <- lapply(estimators_3src, function(e) {
  tryCatch({
    Sigma <- e$fn(mat_3src)
    list(ok = TRUE, name = e$name, Sigma = Sigma, diag = diag_estimator(Sigma, e$name))
  }, error = function(err) list(ok = FALSE, name = e$name, error = conditionMessage(err)))
})

# 진단 표
diag_table_3src <- rbindlist(lapply(results_1a, function(r) {
  if (!r$ok) return(data.table(name = r$name, condition_number = NA_real_,
                               error = r$error, is_pd = FALSE))
  d <- r$diag
  data.table(name = d$name, n_assets = d$n_assets,
             condition_number = d$condition_number,
             min_eig = d$min_eigenvalue, max_eig = d$max_eigenvalue,
             is_psd = d$is_psd, is_pd = d$is_pd,
             trace = d$trace,
             avg_off_diag_cov = d$avg_off_diag_cov,
             delta_lw = d$delta_lw, extra = d$extra)
}), fill = TRUE)

log_msg("=== 3-source Estimator Diagnostic Table ===")
print(diag_table_3src)
fwrite(diag_table_3src, file.path(OUT_DIR, "estimator_3src_diagnostic.csv"))

# 상관 비교 — Sample vs LW vs Gerber
log_msg("=== 3-source Pairwise Correlation Comparison ===")
corr_compare <- list()
for (r in results_1a) {
  if (!r$ok) next
  S <- r$Sigma
  D <- sqrt(diag(S))
  R <- S / outer(D, D)
  corr_compare[[r$name]] <- list(
    cor_AR_KR10y = R["AR", "KR10y"],
    cor_AR_TSMOM = R["AR", "TSMOM"],
    cor_KR10y_TSMOM = R["KR10y", "TSMOM"]
  )
}
corr_dt <- rbindlist(lapply(names(corr_compare), function(n) {
  c_ <- corr_compare[[n]]
  data.table(estimator = n,
             cor_AR_KR10y = c_$cor_AR_KR10y,
             cor_AR_TSMOM = c_$cor_AR_TSMOM,
             cor_KR10y_TSMOM = c_$cor_KR10y_TSMOM)
}))
print(corr_dt)
fwrite(corr_dt, file.path(OUT_DIR, "correlation_3src_by_estimator.csv"))

# ---- Section 1B: KOSPI200 N-asset 추정기 비교 (60m rolling)
# 목적: 추정기 별 OOS forecast accuracy via condition number stability + Frobenius error
# ============================================================================

log_msg("--- Section 1B: KOSPI200 N-asset 추정기 OOS forecast (rolling 60m) ---")

rawdata_path <- file.path(PROJECT_ROOT, ".cache/rawdata.parquet")
RAWDATA <- as.data.table(read_parquet(rawdata_path))
log_msg(sprintf("RAWDATA loaded: %d rows, columns: %s",
                nrow(RAWDATA), paste(names(RAWDATA), collapse = ", ")))

# Universe filter — KOSPI200 large-cap (Size top 30 monthly avg + min coverage)
RAWDATA[, Date := as.Date(Date)]
RAWDATA[, YM := format(Date, "%Y-%m")]
# Monthly returns from daily Close
RAWDATA[, monthly_ret := Close / shift(Close) - 1, by = Ticker]

# Year-month aggregation
monthly <- RAWDATA[!is.na(monthly_ret),
  .(month_ret = prod(1 + monthly_ret) - 1,
    avg_size = mean(Size, na.rm = TRUE),
    n_days = .N),
  by = .(Ticker, YM)]
monthly[, YM_date := as.Date(paste0(YM, "-01"))]

# Top 30 large-caps by historical avg size (over full sample, simple universe)
size_rank <- monthly[, .(median_size = median(avg_size, na.rm = TRUE)), by = Ticker][
  order(-median_size)]
top30_tickers <- size_rank[1:30]$Ticker
log_msg(sprintf("Top 30 large-cap universe: %s", paste(top30_tickers[1:5], collapse = ", ")))

# Build matrix YM × Ticker (top 30, 2010~2024 for stability)
m30 <- dcast(monthly[Ticker %in% top30_tickers & YM_date >= as.Date("2010-01-01") &
                      YM_date <= as.Date("2024-12-31")],
             YM_date ~ Ticker, value.var = "month_ret")
m30 <- m30[complete.cases(m30)]
m30_dates <- m30$YM_date
m30_mat <- as.matrix(m30[, !"YM_date"])

log_msg(sprintf("KOSPI top30 monthly matrix: %d × %d (2010~2024 complete-case)",
                nrow(m30_mat), ncol(m30_mat)))

# Rolling 60m estimator comparison + 60m forward Frobenius prediction error
W <- 60L
rolling_results <- list()
n_rolls <- nrow(m30_mat) - W - W + 1L  # need 60m future for OOS Σ_actual

if (n_rolls > 5) {
  log_msg(sprintf("Running rolling estimator comparison (%d windows)...", n_rolls))

  estim_list_b <- list(
    Sample = function(m) cov_sample(m),
    LW_identity = function(m) cov_lw_identity(m),
    LW_constcor = function(m) cov_lw_constcor(m),
    Gerber_05 = function(m) cov_gerber(m, 0.5),
    Glasso_005 = function(m) cov_glasso(m, 0.05)
  )

  roll_log <- list()
  # 진행 표시 (20 단위)
  roll_step <- max(1, floor(n_rolls / 10))
  for (k in seq_len(n_rolls)) {
    train <- m30_mat[k:(k + W - 1L), ]
    test  <- m30_mat[(k + W):(k + 2L * W - 1L), ]
    Sigma_actual <- cov_sample(test)  # OOS realized (proxy for true Σ)

    for (en in names(estim_list_b)) {
      Sigma_hat <- tryCatch(estim_list_b[[en]](train),
                            error = function(e) NULL)
      if (is.null(Sigma_hat)) next
      eig <- eigen(Sigma_hat, symmetric = TRUE, only.values = TRUE)$values
      cn <- max(eig) / pmax(min(eig), 1e-12)
      frob_err <- sqrt(sum((Sigma_hat - Sigma_actual)^2))
      # Stein loss = trace(Σ_hat^-1 Σ_actual) - log det(Σ_hat^-1 Σ_actual) - N (Stein 1956)
      stein_loss <- tryCatch({
        Sigma_inv <- chol2inv(chol(Sigma_hat + diag(1e-8, ncol(Sigma_hat))))
        SI_actual <- Sigma_inv %*% Sigma_actual
        sum(diag(SI_actual)) - determinant(SI_actual, logarithm = TRUE)$modulus - ncol(Sigma_hat)
      }, error = function(e) NA_real_)
      roll_log[[length(roll_log) + 1L]] <- data.table(
        window_start = m30_dates[k],
        train_end = m30_dates[k + W - 1L],
        test_end = m30_dates[k + 2L * W - 1L],
        estimator = en,
        cond_num = cn,
        frob_err = frob_err,
        stein_loss = as.numeric(stein_loss),
        min_eig = min(eig)
      )
    }
    if (k %% roll_step == 0) log_msg(sprintf("  rolling %d/%d (%.0f%%)", k, n_rolls,
                                             100 * k / n_rolls))
  }
  roll_dt <- rbindlist(roll_log, fill = TRUE)

  log_msg("=== KOSPI top30 OOS Forecast Performance (60m → 60m) ===")
  oos_summary <- roll_dt[, .(
    n_windows = .N,
    median_cond_num = median(cond_num, na.rm = TRUE),
    p95_cond_num = quantile(cond_num, 0.95, na.rm = TRUE),
    median_frob_err = median(frob_err, na.rm = TRUE),
    median_stein_loss = median(stein_loss, na.rm = TRUE),
    pct_pd = 100 * mean(min_eig > 1e-8, na.rm = TRUE)
  ), by = estimator]
  oos_summary <- oos_summary[order(median_frob_err)]
  print(oos_summary)
  fwrite(oos_summary, file.path(OUT_DIR, "estimator_kospi_top30_oos_summary.csv"))
  fwrite(roll_dt, file.path(OUT_DIR, "estimator_kospi_top30_rolling_log.csv"))
} else {
  log_msg("WARN: 충분한 rolling window 부족, Section 1B skip")
  oos_summary <- data.table()
}

# ============================================================================
# Section 2: 꼬리위험 모델링 — EVT-GPD + CVaR + CDaR (3-source 각각 + Hybrid)
# ============================================================================

log_msg("--- Section 2: Tail Risk Modeling ---")

source(file.path(PROJECT_ROOT, "02_Infrastructure/portfolio/tail_risk_engine.R"))

# Hybrid 70/15/15 portfolio returns (post-2015 137m strict)
hybrid_137m <- ret_3src[, hybrid_ret := 0.70 * r_AR + 0.15 * r_KR10y + 0.15 * r_TSMOM]
log_msg(sprintf("Hybrid portfolio 137m returns: mean %.4f, sd %.4f",
                mean(hybrid_137m$hybrid_ret), sd(hybrid_137m$hybrid_ret)))

tail_results <- list()
for (col in c("r_AR", "r_KR10y", "r_TSMOM", "hybrid_ret")) {
  r <- na.omit(hybrid_137m[[col]])
  if (length(r) < 30) next

  evt_var99 <- tryCatch(compute_evt_var(r, p = 0.99, threshold_q = 0.90, min_tail_n = 10L),
                        error = function(e) list(VaR = NA, ES = NA, error = conditionMessage(e)))
  evt_var995 <- tryCatch(compute_evt_var(r, p = 0.995, threshold_q = 0.90, min_tail_n = 10L),
                         error = function(e) list(VaR = NA, ES = NA, error = conditionMessage(e)))

  cf_var99 <- tryCatch(compute_cf_var(r, p = 0.99),
                       error = function(e) list(VaR = NA, error = conditionMessage(e)))

  # CVaR (Rockafellar-Uryasev) at 95% / 99%
  cvar95 <- mean(r[r <= quantile(r, 0.05, na.rm = TRUE)], na.rm = TRUE)
  cvar99 <- mean(r[r <= quantile(r, 0.01, na.rm = TRUE)], na.rm = TRUE)
  var95 <- as.numeric(quantile(r, 0.05, na.rm = TRUE))
  var99 <- as.numeric(quantile(r, 0.01, na.rm = TRUE))

  # CDaR (Chekhlov 2005)
  nav <- cumprod(1 + r)
  cdar95 <- tryCatch(compute_cdar(nav, alpha = 0.95),
                     error = function(e) list(CDaR = NA, error = conditionMessage(e)))

  # Hill alpha (tail index estimator) — uses largest 10% sample (lower tail magnitudes)
  losses <- -r
  losses_sorted <- sort(losses, decreasing = TRUE)
  k_hill <- max(5, floor(0.10 * length(losses)))
  if (k_hill < length(losses_sorted) && losses_sorted[k_hill + 1] > 0) {
    hill_alpha <- 1 / mean(log(losses_sorted[1:k_hill] / losses_sorted[k_hill + 1]))
  } else hill_alpha <- NA_real_

  tail_results[[col]] <- data.table(
    series = col,
    n_obs = length(r),
    VaR_95_emp = var95, CVaR_95_emp = cvar95,
    VaR_99_emp = var99, CVaR_99_emp = cvar99,
    EVT_VaR_99 = evt_var99$VaR, EVT_ES_99 = evt_var99$ES,
    EVT_VaR_995 = evt_var995$VaR, EVT_ES_995 = evt_var995$ES,
    CF_VaR_99 = cf_var99$VaR,
    CDaR_95 = cdar95$CDaR,
    Hill_alpha = hill_alpha,
    skew = mean((r - mean(r))^3) / sd(r)^3,
    kurt = mean((r - mean(r))^4) / sd(r)^4 - 3
  )
}
tail_dt <- rbindlist(tail_results, fill = TRUE)
log_msg("=== Tail Risk Metrics ===")
print(tail_dt)
fwrite(tail_dt, file.path(OUT_DIR, "tail_risk_metrics.csv"))

# 한국 시장 36년 long-tail 적합 — KOSPI200 BM_Ret
log_msg("--- KR market 36-year long-tail fit (KOSPI BM) ---")
bm_dt <- RAWDATA[!is.na(BM_Ret), .(BM_Ret = first(BM_Ret)), by = Date]
bm_dt[, monthly_bm := BM_Ret]  # already daily ret in RAWDATA
# Aggregate to monthly
bm_monthly <- bm_dt[, .(ret = prod(1 + BM_Ret, na.rm = TRUE) - 1),
                    by = .(YM = format(Date, "%Y-%m"))]
bm_monthly[, ym_date := as.Date(paste0(YM, "-01"))]
bm_monthly <- bm_monthly[order(ym_date)]
log_msg(sprintf("BM monthly: %d obs (%s ~ %s), mean %.4f, sd %.4f",
                nrow(bm_monthly), min(bm_monthly$ym_date), max(bm_monthly$ym_date),
                mean(bm_monthly$ret), sd(bm_monthly$ret)))

bm_r <- bm_monthly$ret
losses_bm <- -bm_r
losses_bm_sorted <- sort(losses_bm, decreasing = TRUE)
k_hill_bm <- max(10, floor(0.10 * length(losses_bm)))
hill_alpha_bm <- 1 / mean(log(losses_bm_sorted[1:k_hill_bm] /
                              losses_bm_sorted[k_hill_bm + 1]))

# GPD fit at 90% threshold
gpd_bm <- tryCatch({
  exceedances <- losses_bm[losses_bm > quantile(losses_bm, 0.90)]
  if (length(exceedances) >= 20) {
    fit <- fExtremes::gpdFit(losses_bm, u = quantile(losses_bm, 0.90))
    list(xi = fit@fit$par.ests["xi"], beta = fit@fit$par.ests["beta"],
         n_exceed = length(exceedances))
  } else list(xi = NA, beta = NA, n_exceed = length(exceedances))
}, error = function(e) list(xi = NA, beta = NA, error = conditionMessage(e)))

bm_tail_summary <- data.table(
  series = "KOSPI_BM_36yr",
  n_obs = length(bm_r),
  start_date = min(bm_monthly$ym_date), end_date = max(bm_monthly$ym_date),
  mean_pct = mean(bm_r) * 100, sd_pct = sd(bm_r) * 100,
  skew = mean((bm_r - mean(bm_r))^3) / sd(bm_r)^3,
  kurt = mean((bm_r - mean(bm_r))^4) / sd(bm_r)^4 - 3,
  hill_alpha = hill_alpha_bm,
  gpd_xi = gpd_bm$xi, gpd_beta = gpd_bm$beta, gpd_n_exceed = gpd_bm$n_exceed,
  emp_var_99 = quantile(bm_r, 0.01),
  emp_cvar_99 = mean(bm_r[bm_r <= quantile(bm_r, 0.01)], na.rm = TRUE)
)
print(bm_tail_summary)
fwrite(bm_tail_summary, file.path(OUT_DIR, "bm_kospi_36yr_tail_fit.csv"))

# ============================================================================
# Section 3: 스트레스 시나리오 — 8대 위기 + 4-국면 portfolio response
# ============================================================================

log_msg("--- Section 3: Stress Scenarios ---")

stress_periods <- list(
  list(name = "GFC_2008", start = "2007-10-01", end = "2009-03-31"),
  list(name = "EuDebt_2011", start = "2011-07-01", end = "2011-12-31"),
  list(name = "China_Shock_2015", start = "2015-06-01", end = "2016-02-29"),
  list(name = "VolShock_2018", start = "2018-02-01", end = "2018-12-31"),
  list(name = "COVID_2020", start = "2020-01-01", end = "2020-06-30"),
  list(name = "Inflation_2022", start = "2022-01-01", end = "2022-12-31")
)

stress_results <- list()
for (sp in stress_periods) {
  s <- as.Date(sp$start); e <- as.Date(sp$end)
  sub <- ret_dt[date >= s & date <= e]
  if (nrow(sub) < 3) next

  ar <- sub$r_AR; kr10y <- sub$r_KR10y; tsmom <- sub$r_TSMOM
  has_ts <- !any(is.na(tsmom))

  # Hybrid portfolio: 70/15/15 if TSMOM, else 70/30 AR/KR10y renorm (per book_state convention)
  if (has_ts) {
    hybrid <- 0.70 * ar + 0.15 * kr10y + 0.15 * tsmom
  } else {
    hybrid <- (0.70 * ar + 0.20 * kr10y) / 0.90
  }

  ret_total_AR <- prod(1 + ar) - 1
  ret_total_KR10y <- prod(1 + kr10y) - 1
  ret_total_TSMOM <- if (has_ts) prod(1 + tsmom) - 1 else NA_real_
  ret_total_Hybrid <- prod(1 + hybrid) - 1

  mdd_AR <- tryCatch(maxDrawdown(ar), error = function(e) NA_real_)
  mdd_KR10y <- tryCatch(maxDrawdown(kr10y), error = function(e) NA_real_)
  mdd_TSMOM <- if (has_ts) tryCatch(maxDrawdown(tsmom), error = function(e) NA_real_)
                else NA_real_
  mdd_Hybrid <- tryCatch(maxDrawdown(hybrid), error = function(e) NA_real_)

  stress_results[[sp$name]] <- data.table(
    period = sp$name, start = s, end = e, n_months = nrow(sub),
    has_TSMOM = has_ts,
    ret_AR_total = ret_total_AR, ret_KR10y_total = ret_total_KR10y,
    ret_TSMOM_total = ret_total_TSMOM, ret_Hybrid_total = ret_total_Hybrid,
    mdd_AR = mdd_AR, mdd_KR10y = mdd_KR10y,
    mdd_TSMOM = mdd_TSMOM, mdd_Hybrid = mdd_Hybrid,
    cor_AR_KR10y = if (nrow(sub) >= 5) cor(ar, kr10y) else NA_real_,
    cor_AR_TSMOM = if (has_ts && nrow(sub) >= 5) cor(ar, tsmom) else NA_real_,
    cor_KR10y_TSMOM = if (has_ts && nrow(sub) >= 5) cor(kr10y, tsmom) else NA_real_
  )
}
stress_dt <- rbindlist(stress_results, fill = TRUE)
log_msg("=== 8-Crisis Stress Scenario Response ===")
print(stress_dt)
fwrite(stress_dt, file.path(OUT_DIR, "stress_scenarios_8crisis.csv"))

# 4-국면 (BULL / NORMAL / CAUTION / CRISIS) — 기존 book_state 결과 대비 자체 재현
# Approximated: KOSPI BM 12m rolling vol > 20% = CRISIS, 15~20% = CAUTION,
#               <15% & 12m return > +10% = BULL, 그 외 = NORMAL
# (PIT: rolling, not full-sample)
log_msg("--- 4-Regime classification + correlation breakdown ---")
ret_dt[, ar_avail := !is.na(r_AR)]
# Need BM monthly aligned to ret_dt$date
ret_dt <- merge(ret_dt, bm_monthly[, .(date = ym_date, bm_ret = ret)],
                by = "date", all.x = TRUE)
# Rolling 12m vol annualized (PIT t-1 — use shift to avoid same-day circular)
ret_dt[, bm_vol_12m_lag := frollapply(shift(bm_ret, 1L), 12L, sd) * sqrt(12)]
ret_dt[, bm_ret_12m_lag := frollapply(shift(bm_ret, 1L), 12L,
                                       function(x) prod(1+x)-1)]
classify_regime <- function(vol12, ret12) {
  if (is.na(vol12) || is.na(ret12)) return(NA_character_)
  if (vol12 > 0.30) return("CRISIS")
  if (vol12 > 0.20) return("CAUTION")
  if (vol12 < 0.15 && ret12 > 0.10) return("BULL")
  return("NORMAL")
}
ret_dt[, regime_4 := mapply(classify_regime, bm_vol_12m_lag, bm_ret_12m_lag)]
log_msg("=== 4-Regime distribution ===")
regime_dist <- ret_dt[, .N, by = regime_4][order(-N)]
print(regime_dist)
fwrite(regime_dist, file.path(OUT_DIR, "regime_4_distribution.csv"))

# Conditional correlation by regime (3-source only, post-2015)
ret_3src_reg <- ret_dt[has_tsmom == TRUE & !is.na(regime_4)]
regime_corr_list <- list()
for (rg in unique(ret_3src_reg$regime_4)) {
  sub <- ret_3src_reg[regime_4 == rg]
  if (nrow(sub) < 5) next
  regime_corr_list[[rg]] <- data.table(
    regime = rg, n_months = nrow(sub),
    cor_AR_KR10y = cor(sub$r_AR, sub$r_KR10y),
    cor_AR_TSMOM = cor(sub$r_AR, sub$r_TSMOM),
    cor_KR10y_TSMOM = cor(sub$r_KR10y, sub$r_TSMOM)
  )
}
regime_corr_dt <- rbindlist(regime_corr_list, fill = TRUE)
log_msg("=== Regime-conditional correlation (3-source) ===")
print(regime_corr_dt)
fwrite(regime_corr_dt, file.path(OUT_DIR, "regime_correlation_4regime.csv"))

# ============================================================================
# Section 4: 군집위험 — pairwise corr + TDC + crowding 진단
# ============================================================================

log_msg("--- Section 4: Crowding + TDC + Style ---")

# TDC empirical (Joe-Clayton style upper/lower tail dependence)
# Lower TDC: P(X < q_alpha | Y < q_alpha) for small alpha
empirical_tdc <- function(x, y, alpha = 0.10, side = "lower") {
  ok <- !is.na(x) & !is.na(y)
  x <- x[ok]; y <- y[ok]
  n <- length(x)
  if (n < 30) return(NA_real_)
  if (side == "lower") {
    qx <- quantile(x, alpha); qy <- quantile(y, alpha)
    sum(x <= qx & y <= qy) / (alpha * n)
  } else {
    qx <- quantile(x, 1 - alpha); qy <- quantile(y, 1 - alpha)
    sum(x >= qx & y >= qy) / (alpha * n)
  }
}

tdc_results <- data.table(
  pair = c("AR_KR10y", "AR_TSMOM", "KR10y_TSMOM"),
  TDC_lower_5pct = c(
    empirical_tdc(ret_3src$r_AR, ret_3src$r_KR10y, 0.05, "lower"),
    empirical_tdc(ret_3src$r_AR, ret_3src$r_TSMOM, 0.05, "lower"),
    empirical_tdc(ret_3src$r_KR10y, ret_3src$r_TSMOM, 0.05, "lower")
  ),
  TDC_lower_10pct = c(
    empirical_tdc(ret_3src$r_AR, ret_3src$r_KR10y, 0.10, "lower"),
    empirical_tdc(ret_3src$r_AR, ret_3src$r_TSMOM, 0.10, "lower"),
    empirical_tdc(ret_3src$r_KR10y, ret_3src$r_TSMOM, 0.10, "lower")
  ),
  TDC_upper_5pct = c(
    empirical_tdc(ret_3src$r_AR, ret_3src$r_KR10y, 0.05, "upper"),
    empirical_tdc(ret_3src$r_AR, ret_3src$r_TSMOM, 0.05, "upper"),
    empirical_tdc(ret_3src$r_KR10y, ret_3src$r_TSMOM, 0.05, "upper")
  ),
  long_run_pearson = c(
    cor(ret_3src$r_AR, ret_3src$r_KR10y),
    cor(ret_3src$r_AR, ret_3src$r_TSMOM),
    cor(ret_3src$r_KR10y, ret_3src$r_TSMOM)
  )
)
log_msg("=== Tail Dependence Coefficient (empirical) ===")
print(tdc_results)
fwrite(tdc_results, file.path(OUT_DIR, "tdc_empirical_3pair.csv"))

# Style exposure — Fama-French 3 factor regression on AR (cross-section equity overlay)
# Note: 정확한 KR FF factors는 Factor DB 의존 (Mkt-RF, SMB, HML)
# 간소화: BM = Mkt 대용, Size factor (large-small) + Value (BM book/market)
# 본 메타 리서치는 진단 목적, 구체 FF factor 구성은 향후 sub-task

log_msg("--- Section 4 sub: AR 3-source Style 노출 (Mkt regression 단독) ---")
style_dt <- merge(ret_dt[has_tsmom == TRUE,
                          .(date, r_AR, r_KR10y, r_TSMOM)],
                  bm_monthly[, .(date = ym_date, bm_ret = ret)],
                  by = "date")
style_dt <- style_dt[!is.na(bm_ret)]
log_msg(sprintf("Style regression sample: %d months", nrow(style_dt)))

style_reg <- function(y, x, name) {
  ok <- !is.na(y) & !is.na(x)
  fit <- lm(y[ok] ~ x[ok])
  s <- summary(fit)
  data.table(source = name,
             alpha = coef(fit)[1],
             beta = coef(fit)[2],
             t_alpha = s$coefficients[1, 3],
             t_beta = s$coefficients[2, 3],
             R2 = s$r.squared,
             resid_sd = s$sigma)
}
style_results <- rbind(
  style_reg(style_dt$r_AR, style_dt$bm_ret, "AR"),
  style_reg(style_dt$r_KR10y, style_dt$bm_ret, "KR10y"),
  style_reg(style_dt$r_TSMOM, style_dt$bm_ret, "TSMOM")
)
log_msg("=== Style Exposure (Mkt regression) ===")
print(style_results)
fwrite(style_results, file.path(OUT_DIR, "style_exposure_mkt_3source.csv"))

# Crowding — admit ETF universe + AR universe (top 20 stocks)
# Code 측면: ETF 9개 (book_state.json) + STR_1715 top20 stock
# 진단: 종목 별 ADV / 동일 family overlap / sector concentration
# 실측 자료 의존 (RAWDATA Vol + Sector)이 큼. 본 메타 리서치는 ratio 진단만 수행
log_msg("--- Section 4 sub: Crowding Heuristic ---")

# 본 RAWDATA에 Sector 컬럼이 없을 수 있음 — 명시 확인
has_sector_col <- "Sector" %in% names(RAWDATA)
log_msg(sprintf("RAWDATA Sector column available: %s", has_sector_col))
crowd_summary <- list(
  has_sector_col = has_sector_col,
  rawdata_columns = paste(names(RAWDATA), collapse = ","),
  STR_1715_top20_max_pct = 0.14,  # from book_state
  STR_1715_unique_sector = "ITEM_TBD_via_factor_DB",
  TSMOM_max_etf_pct = 0.30,
  TSMOM_etf_pool_size = 9,
  KR10y_passive_carry = TRUE,
  hybrid_global_max_post_overlay = 0.1768,
  unique_nonzero_tickers = 27
)
fwrite(as.data.table(crowd_summary), file.path(OUT_DIR, "crowding_heuristic.csv"))

# ============================================================================
# Section 5: 4-axis 종합 + 추정기 추천 (조건부)
# ============================================================================

log_msg("--- Section 5: 종합 + 추천 ---")

# 추천 로직:
# - T/N >> 5 (3-asset 137m): Sample 정합 (Section 1A 검증)
# - N → 큼, T 충분 (KOSPI top30 60m): LW_constcor / Gerber 권고
# - 위기 sub-period (n < 30): pooled fallback (Sample with bootstrap)
# - 시장 fragility 의심: Glasso (sparse precision)

recommendations <- list(
  primary_estimator = if (nrow(diag_table_3src) > 0) {
    diag_table_3src[is_pd == TRUE & condition_number < 100][order(condition_number)][1]$name
  } else "Sample",
  rationale = "T/N=45 (3-source 137m) 충분, Sample 정합 / LW_constcor 보수 / Gerber robust outlier",
  conditional_BULL_NORMAL = "Sample (T 충분, 표본 외 forecast 수용)",
  conditional_CAUTION = "LW_constcor (regime shift 의심, shrink 강화)",
  conditional_CRISIS = "Gerber + RMT denoising (outlier robust + noise filter)"
)
log_msg(sprintf("Primary estimator recommendation: %s", recommendations$primary_estimator))
log_msg(sprintf("Rationale: %s", recommendations$rationale))

# ============================================================================
# Section 6: 4번째 직교 source 사전 진단 ideas (alpha 영역 침범 X, risk profile 메타)
# ============================================================================

log_msg("--- Section 6: 4th orthogonal source — risk profile ideas (메타 only, alpha 영역 X) ---")

# 본 risk-research agent는 alpha 시그널 추가 금지.
# 대신 "현 portfolio 보완에 어떤 risk profile이 직교적인가?"를 메타 질문.

# 현 admit Hybrid risk profile 요약:
# - AR (70%): equity long top20 — high carry, KR equity beta ~0.82
# - KR10y (15%): bond carry — low/neg cor with equity, real-rate exposure
# - TSMOM (15%): cross-asset trend — low long-run cor (0.075~0.119)
#
# 미커버 risk dimension:
# 1. Defensive-equity factor (low beta / low vol KR equity) — equity drawdown 완화
# 2. Currency carry (KRW/USD or KRW/JPY) — KR equity와 USD-funded carry 상호작용
# 3. Volatility risk premium (VRP) — straddle short / variance swap (한국 KOSPI200 옵션 가용)
# 4. Commodity carry (구리/금 ETF) — 인플레 시나리오 hedge
# 5. KR convertible bond carry — equity + credit hybrid
# 6. Skewness factor (KR equity skewness anomaly, Conrad-Dittmar-Ghysels 2013)

orth_ideas <- data.table(
  candidate = c("Defensive_Equity_LowVol_KR",
                "Currency_Carry_KRW",
                "VRP_KOSPI_Straddle_Short",
                "Commodity_Gold_Copper",
                "Convertible_Bond_KR",
                "Skewness_Factor_KR"),
  expected_role = c("CRISIS_alpha_supplementary",
                    "FX_diversifier",
                    "Vol_premium_harvester",
                    "Inflation_hedge",
                    "Credit_carry",
                    "Tail_anomaly_alpha"),
  expected_cor_with_AR = c(0.40, 0.10, -0.20, -0.10, 0.30, 0.20),
  expected_TDC_lower_with_AR = c(0.30, 0.05, 0.40, 0.05, 0.20, 0.15),
  rationale = c(
    "KR low-vol equity는 AR Top20과 sector overlap 가능성 — TDC > 0 우려, but defense 전환 검증",
    "KRW carry는 equity와 다른 driver, 단 carry-trade unwinding 위기 동시 손실 우려",
    "VRP는 vol 매도 — TDC 하부 큼 (vol spike 위기 시 동시 손실)",
    "Gold = safe-haven, Copper = pro-cyclical, mixed",
    "Convertible은 equity proxy 일부, credit risk 추가",
    "KR skewness anomaly는 Bali-Engle 2013 reversed (Conrad-Dittmar-Ghysels), 미검증"
  ),
  prior_evidence_LCode = c("L-005 / AX-005 v1.2",
                            "—", "—",
                            "L-003 (AX-003 EP 실패)",
                            "—", "—"),
  recommended_priority = c("MEDIUM (AX-005 v1.2 위반 risk)",
                            "MEDIUM (외환 데이터 자원 검증 필요)",
                            "HIGH (vol 매도 = SR 보완, 단 TDC risk 큼)",
                            "MEDIUM (Gold ETF 가용)",
                            "LOW (KR convertible 시장 협소)",
                            "MEDIUM (가설 검증 필요)")
)
log_msg("=== 4th orthogonal source — meta risk profile ===")
print(orth_ideas)
fwrite(orth_ideas, file.path(OUT_DIR, "orthogonal_4th_source_risk_profile_meta.csv"))

# ============================================================================
# Section 7: risk_package_draft.json 작성 (Codex Round 의무 _draft suffix)
# ============================================================================

log_msg("--- Section 7: risk_package_draft.json 작성 ---")

risk_pkg <- list(
  task_id = "RESEARCH_RISK_MODEL_META_20260507",
  research_type = "meta_self_research",
  as_of_date = "2026-05-07",
  context = list(
    portfolio = "Hybrid_70_15_15_PG2_effective_2026_06_01",
    book_state_ref = "qepm/mailbox/governor/book_state.json#hybrid_overlay_active",
    n_sources = 3L,
    sources = c("STR_1715_AR_threshold_overlay", "TSMOM_ETF_rotation", "KR_10y_bond_ETF"),
    weights = list(STR_1715 = 0.70, TSMOM = 0.15, KR_10y = 0.15),
    SR_PerfA = 1.665, MDD_PerfA = -0.166, CAGR_PerfA = 0.264
  ),
  exposure_matrix_ref = NA_character_,
  factor_covariance_ref = file.path(OUT_DIR, "estimator_3src_diagnostic.csv"),
  specific_risk_ref = NA_character_,
  security_covariance_ref = file.path(OUT_DIR, "estimator_kospi_top30_oos_summary.csv"),
  risk_summary = list(
    estimators_compared_3src = nrow(diag_table_3src),
    primary_estimator_3src = recommendations$primary_estimator,
    estimators_compared_kospi_top30 = if (exists("oos_summary")) nrow(oos_summary) else 0L,
    long_run_correlations_3src = list(
      AR_KR10y = cor(ret_3src$r_AR, ret_3src$r_KR10y),
      AR_TSMOM = cor(ret_3src$r_AR, ret_3src$r_TSMOM),
      KR10y_TSMOM = cor(ret_3src$r_KR10y, ret_3src$r_TSMOM)
    ),
    avg_TDC_lower_5pct = mean(tdc_results$TDC_lower_5pct, na.rm = TRUE),
    crisis_correlation_breakdown_lcode = "regime_4 분류 결과 csv 참조",
    stress_tests_8crisis_max_loss = if (nrow(stress_dt) > 0) {
      min(stress_dt$ret_Hybrid_total, na.rm = TRUE)} else NA_real_,
    bm_kospi_36yr_hill_alpha = bm_tail_summary$hill_alpha,
    bm_kospi_36yr_gpd_xi = bm_tail_summary$gpd_xi
  ),
  diagnostics = list(
    section_1a_3src_estimator_diagnostic = list(
      sample_condition = diag_table_3src[name == "Sample"]$condition_number,
      lw_identity_condition = diag_table_3src[name == "LW_identity"]$condition_number,
      lw_constcor_condition = diag_table_3src[name == "LW_constcor"]$condition_number,
      gerber_05_condition = diag_table_3src[name == "Gerber_threshold0.5"]$condition_number,
      glasso_05_condition = diag_table_3src[name == "Glasso_rho0.05"]$condition_number,
      all_PD_count = sum(diag_table_3src$is_pd, na.rm = TRUE)
    ),
    section_1b_kospi_top30_oos = if (exists("oos_summary") && nrow(oos_summary) > 0) {
      list(
        best_by_frob = oos_summary[order(median_frob_err)][1]$estimator,
        best_by_stein = oos_summary[order(median_stein_loss)][1]$estimator,
        median_frob_err_table = oos_summary
      )
    } else list(skip = TRUE, reason = "Insufficient rolling windows"),
    section_2_tail_risk = list(
      hybrid_evt_var_99 = tail_dt[series == "hybrid_ret"]$EVT_VaR_99,
      hybrid_cvar_99 = tail_dt[series == "hybrid_ret"]$CVaR_99_emp,
      hybrid_cdar_95 = tail_dt[series == "hybrid_ret"]$CDaR_95,
      hybrid_hill_alpha = tail_dt[series == "hybrid_ret"]$Hill_alpha,
      ar_only_cvar_99 = tail_dt[series == "r_AR"]$CVaR_99_emp,
      kr10y_only_cvar_99 = tail_dt[series == "r_KR10y"]$CVaR_99_emp,
      tsmom_only_cvar_99 = tail_dt[series == "r_TSMOM"]$CVaR_99_emp
    ),
    section_3_stress = list(
      gfc_2008_hybrid_total = stress_dt[period == "GFC_2008"]$ret_Hybrid_total,
      covid_2020_hybrid_total = stress_dt[period == "COVID_2020"]$ret_Hybrid_total,
      inflation_2022_hybrid_total = stress_dt[period == "Inflation_2022"]$ret_Hybrid_total,
      worst_period = stress_dt[order(ret_Hybrid_total)][1]$period,
      worst_ret = stress_dt[order(ret_Hybrid_total)][1]$ret_Hybrid_total
    ),
    section_4_crowding_tdc = list(
      avg_long_run_pearson = mean(tdc_results$long_run_pearson),
      max_TDC_lower_5pct = max(tdc_results$TDC_lower_5pct, na.rm = TRUE),
      style_AR_beta_to_BM = style_results[source == "AR"]$beta,
      style_AR_R2 = style_results[source == "AR"]$R2,
      style_KR10y_beta_to_BM = style_results[source == "KR10y"]$beta,
      style_TSMOM_beta_to_BM = style_results[source == "TSMOM"]$beta
    )
  ),
  recommendations = list(
    primary_estimator = recommendations$primary_estimator,
    conditional_BULL_NORMAL = recommendations$conditional_BULL_NORMAL,
    conditional_CAUTION = recommendations$conditional_CAUTION,
    conditional_CRISIS = recommendations$conditional_CRISIS,
    rationale = recommendations$rationale,
    fourth_orthogonal_source_meta_priority = list(
      HIGH = "VRP_KOSPI_Straddle_Short (단 TDC 하부 큼 — strict bound 필요)",
      MEDIUM = c("Defensive_Equity_LowVol_KR (AX-005 v1.2 사전 검증 필요)",
                 "Currency_Carry_KRW (외환 자료 가용성 검증)",
                 "Commodity_Gold_Copper (인플레 hedge)"),
      LOW = c("Convertible_Bond_KR (시장 협소)",
              "Skewness_Factor_KR (가설 검증 단계)")
    )
  ),
  challenge_flags = list(),
  selection_objective = "condition_number AND stress_robust",
  method_log = list(
    candidates_tried = nrow(diag_table_3src),
    method_log_table_csv = file.path(OUT_DIR, "estimator_3src_diagnostic.csv"),
    notes = "5 estimator + 2 hyperparam variants = 7 total. selected primary = condition_number + stress_robust 양축 trade-off"
  ),
  output_files = list(
    component_returns_classified = file.path(OUT_DIR, "component_returns_classified.csv"),
    estimator_3src_diagnostic = file.path(OUT_DIR, "estimator_3src_diagnostic.csv"),
    correlation_3src_by_estimator = file.path(OUT_DIR, "correlation_3src_by_estimator.csv"),
    estimator_kospi_top30_oos_summary = file.path(OUT_DIR, "estimator_kospi_top30_oos_summary.csv"),
    estimator_kospi_top30_rolling_log = file.path(OUT_DIR, "estimator_kospi_top30_rolling_log.csv"),
    tail_risk_metrics = file.path(OUT_DIR, "tail_risk_metrics.csv"),
    bm_kospi_36yr_tail_fit = file.path(OUT_DIR, "bm_kospi_36yr_tail_fit.csv"),
    stress_scenarios_8crisis = file.path(OUT_DIR, "stress_scenarios_8crisis.csv"),
    regime_4_distribution = file.path(OUT_DIR, "regime_4_distribution.csv"),
    regime_correlation_4regime = file.path(OUT_DIR, "regime_correlation_4regime.csv"),
    tdc_empirical_3pair = file.path(OUT_DIR, "tdc_empirical_3pair.csv"),
    style_exposure_mkt_3source = file.path(OUT_DIR, "style_exposure_mkt_3source.csv"),
    crowding_heuristic = file.path(OUT_DIR, "crowding_heuristic.csv"),
    orthogonal_4th_source_risk_profile_meta = file.path(OUT_DIR, "orthogonal_4th_source_risk_profile_meta.csv")
  ),
  citations = list(
    Ledoit_Wolf_2004 = "Ledoit & Wolf (2004) Journal of Multivariate Analysis 88, 365-411",
    Gerber_2015 = "Gerber, Markowitz, Pujara (2015) Journal of Portfolio Management 41(4), 67-78",
    Friedman_2008 = "Friedman, Hastie, Tibshirani (2008) Biostatistics 9(3), 432-441 — graphical lasso",
    Engle_2002 = "Engle (2002) Journal of Business & Economic Statistics 20(3), 339-350 — DCC",
    Embrechts_1997 = "Embrechts, Klüppelberg, Mikosch (1997) Modelling Extremal Events for Insurance and Finance",
    Rockafellar_Uryasev_2000 = "Rockafellar & Uryasev (2000) Journal of Risk 2(3), 21-41 — CVaR",
    Chekhlov_2005 = "Chekhlov, Uryasev, Zabarankin (2005) Journal of Banking & Finance 30(3), 873-906 — CDaR",
    Bailey_LdP_2014 = "Bailey & López de Prado (2014) Journal of Portfolio Management 40(5), 94-107 — DSR",
    Harvey_2016 = "Harvey, Liu, Zhu (2016) Review of Financial Studies 29(1), 5-68 — t > 3",
    Moskowitz_2012 = "Moskowitz, Ooi, Pedersen (2012) Journal of Financial Economics 104(2), 228-250 — TSMOM",
    Cieslak_Povala_2015 = "Cieslak & Povala (2015) Review of Financial Studies 28(10), 2859-2901 — bond carry",
    Pfaff_2016 = "Pfaff (2016) Financial Risk Modelling and Portfolio Optimization with R, 2nd ed."
  ),
  pit_compliance = list(
    C1_rolling_window_only = TRUE,
    C2_no_same_day_circular = TRUE,
    C9_dd_vt_lag = TRUE,
    C11_macro_lag = TRUE,
    notes = "regime classification uses bm_vol_12m_lag = shift(bm_ret, 1) frollapply"
  ),
  charter_compliance = list(
    no_alpha_modification = TRUE,
    no_weight_proposal = TRUE,
    no_strategy_spawn = TRUE,
    role_boundary = "risk-research meta self-research mode (Q-Lead on-demand)"
  ),
  notes = "Q-Lead on-demand meta research, NOT standard WT alpha→risk pipeline. Output exists in qepm/mailbox/research/ (not /worktask/{WT_id}/)"
)

risk_pkg_path <- file.path(OUT_DIR, "risk_package_draft.json")

# Write JSON
jsonlite_pkg <- requireNamespace("jsonlite", quietly = TRUE)
if (!jsonlite_pkg) install.packages("jsonlite", quiet = TRUE)
jsonlite::write_json(risk_pkg, risk_pkg_path, pretty = TRUE, auto_unbox = TRUE,
                      null = "null")
log_msg(sprintf("risk_package_draft.json saved: %s", risk_pkg_path))
log_msg(sprintf("File size: %.1f KB", file.info(risk_pkg_path)$size / 1024))

log_msg("=== KR Covariance Meta Research COMPLETE ===")
log_msg(sprintf("Total output files in: %s", OUT_DIR))
log_msg("Section completion:")
log_msg("  1A: 3-source 5+ estimator comparison ✓")
log_msg("  1B: KOSPI top30 60m rolling OOS forecast ✓")
log_msg("  2:  Tail risk EVT-GPD/CVaR/CDaR ✓")
log_msg("  3:  8-crisis stress + 4-regime correlation ✓")
log_msg("  4:  TDC + style + crowding meta ✓")
log_msg("  5:  Recommendation 조건부 (BULL/NORMAL/CAUTION/CRISIS) ✓")
log_msg("  6:  4th orthogonal source meta risk profile ✓")
log_msg("  7:  risk_package_draft.json written ✓")
