#!/usr/bin/env Rscript
# ============================================================================
# Patch v5 — Codex Critic Round disposition fix
#
# C5 fix: IMF 1997 + DotCom 2000 BM-only stress 응답 추가
# C7 fix: KOSPI top30 universe PIT-strict re-selection (each train_end)
# C1 fix: covariance_*.parquet 5-estimator 저장 (3-source 137m)
# ============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(PerformanceAnalytics)
  library(Matrix)
  library(fExtremes)
  library(xts)
  library(glasso)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/research/risk_model_meta_20260507")
STAGE_DIR <- file.path(PROJECT_ROOT, "qepm/stage_artifacts/risk_model_meta_20260507")
dir.create(STAGE_DIR, recursive = TRUE, showWarnings = FALSE)

LOG_FILE <- file.path(OUT_DIR, "meta_research_log.txt")
log_msg <- function(msg) {
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  line <- sprintf("[%s] [PATCH_V5] %s", ts, msg)
  cat(line, "\n")
  cat(line, "\n", file = LOG_FILE, append = TRUE)
}
log_msg("=== PATCH V5 (Codex disposition fix) START ===")

# Estimator 함수 재정의
cov_sample <- function(mat) cov(mat, use = "pairwise.complete.obs")

cov_lw_identity <- function(mat) {
  T_n <- nrow(mat); N <- ncol(mat)
  S <- cov(mat, use = "pairwise.complete.obs")
  mu_target <- mean(diag(S)); F_target <- mu_target * diag(N)
  X_centered <- scale(mat, scale = FALSE); X_centered[is.na(X_centered)] <- 0
  pi_mat <- matrix(0, N, N)
  for (i in 1:N) for (j in 1:N) {
    pi_mat[i, j] <- mean((X_centered[, i] * X_centered[, j] - S[i, j])^2)
  }
  pi_hat <- sum(pi_mat); gamma_hat <- sum((S - F_target)^2)
  if (gamma_hat < 1e-10) delta_opt <- 1 else
    delta_opt <- max(0, min(1, pi_hat / (T_n * gamma_hat)))
  S_shrunk <- delta_opt * F_target + (1 - delta_opt) * S
  attr(S_shrunk, "delta") <- delta_opt
  S_shrunk
}

cov_lw_constcor <- function(mat) {
  T_n <- nrow(mat); N <- ncol(mat)
  S <- cov(mat, use = "pairwise.complete.obs")
  R <- cor(mat, use = "pairwise.complete.obs")
  if (N == 1) return(S)
  rho_bar <- (sum(R) - N) / (N * (N - 1))
  D_sd <- sqrt(diag(S))
  F_target <- rho_bar * outer(D_sd, D_sd); diag(F_target) <- diag(S)
  X_centered <- scale(mat, scale = FALSE); X_centered[is.na(X_centered)] <- 0
  pi_mat <- matrix(0, N, N)
  for (i in 1:N) for (j in 1:N) {
    pi_mat[i, j] <- mean((X_centered[, i] * X_centered[, j] - S[i, j])^2)
  }
  pi_hat <- sum(pi_mat); gamma_hat <- sum((S - F_target)^2)
  if (gamma_hat < 1e-10) delta_opt <- 1 else
    delta_opt <- max(0, min(1, pi_hat / (T_n * gamma_hat)))
  S_shrunk <- delta_opt * F_target + (1 - delta_opt) * S
  attr(S_shrunk, "delta") <- delta_opt
  S_shrunk
}

gerber_corr <- function(mat, threshold = 0.5) {
  T_n <- nrow(mat); N <- ncol(mat)
  sd_vec <- apply(mat, 2, sd, na.rm = TRUE)
  G <- matrix(0, N, N)
  for (i in 1:N) {
    for (j in i:N) {
      m_ij_pos <- 0; m_ij_neg <- 0
      for (t in seq_len(T_n)) {
        x_it <- mat[t, i]; x_jt <- mat[t, j]
        if (is.na(x_it) || is.na(x_jt)) next
        H_i <- abs(x_it) >= threshold * sd_vec[i]
        H_j <- abs(x_jt) >= threshold * sd_vec[j]
        if (H_i && H_j) {
          if (sign(x_it) == sign(x_jt)) m_ij_pos <- m_ij_pos + 1
          else m_ij_neg <- m_ij_neg + 1
        }
      }
      n_co <- m_ij_pos + m_ij_neg
      g_ij <- if (n_co == 0) 0 else (m_ij_pos - m_ij_neg) / n_co
      G[i, j] <- g_ij; G[j, i] <- g_ij
    }
  }
  diag(G) <- 1; G
}

cov_gerber <- function(mat, threshold = 0.5, eig_floor = 0.05) {
  G <- gerber_corr(mat, threshold)
  sd_vec <- apply(mat, 2, sd, na.rm = TRUE)
  S_g <- diag(sd_vec) %*% G %*% diag(sd_vec)
  rownames(S_g) <- colnames(S_g) <- colnames(mat)
  eig <- eigen(S_g, symmetric = TRUE)
  if (min(eig$values) < eig_floor * max(eig$values)) {
    eig$values <- pmax(eig$values, eig_floor * max(eig$values))
    S_g <- eig$vectors %*% diag(eig$values) %*% t(eig$vectors)
    rownames(S_g) <- colnames(S_g) <- colnames(mat)
  }
  S_g
}

cov_glasso <- function(mat, rho = 0.05) {
  S <- cov(mat, use = "pairwise.complete.obs")
  fit <- tryCatch(glasso::glasso(s = S, rho = rho, penalize.diagonal = FALSE),
                  error = function(e) NULL)
  if (is.null(fit)) return(S)
  S_g <- fit$w
  rownames(S_g) <- colnames(S_g) <- colnames(mat)
  S_g
}

# ============================================================================
# C1 fix: 5-estimator covariance.parquet 저장 (3-source 137m)
# ============================================================================

log_msg("--- C1 fix: 5-estimator covariance .parquet 저장 ---")

ret_file <- file.path(PROJECT_ROOT,
  "qepm/mailbox/worktask/WT-P20260505_001/architect_hybrid_returns_full256m.csv")
ret_dt <- fread(ret_file)
ret_dt[, date := as.Date(date)]
ret_dt[, has_tsmom := !is.na(r_TSMOM)]
ret_3src <- ret_dt[has_tsmom == TRUE, .(date, r_AR, r_KR10y, r_TSMOM)]
mat_3src <- as.matrix(ret_3src[, .(r_AR, r_KR10y, r_TSMOM)])
colnames(mat_3src) <- c("AR", "KR10y", "TSMOM")

estimators <- list(
  list(name = "Sample", fn = cov_sample),
  list(name = "LW_identity", fn = cov_lw_identity),
  list(name = "LW_constcor", fn = cov_lw_constcor),
  list(name = "Gerber_v2_floor5pct", fn = function(m) cov_gerber(m, 0.5, 0.05)),
  list(name = "Glasso_005", fn = function(m) cov_glasso(m, 0.05))
)

cov_storage <- list()
for (e in estimators) {
  S <- e$fn(mat_3src)
  eig <- eigen(S, symmetric = TRUE, only.values = TRUE)$values
  cov_storage[[e$name]] <- list(
    estimator = e$name,
    n_obs = nrow(mat_3src),
    n_assets = 3L,
    sigma_AR_AR = S["AR", "AR"], sigma_AR_KR10y = S["AR", "KR10y"], sigma_AR_TSMOM = S["AR", "TSMOM"],
    sigma_KR10y_KR10y = S["KR10y", "KR10y"], sigma_KR10y_TSMOM = S["KR10y", "TSMOM"],
    sigma_TSMOM_TSMOM = S["TSMOM", "TSMOM"],
    cond_num = max(eig) / pmax(min(eig), 1e-12),
    min_eig = min(eig), max_eig = max(eig),
    is_pd = all(eig > 1e-8),
    is_psd = all(eig > -1e-10),
    delta_lw = if (!is.null(attr(S, "delta"))) attr(S, "delta") else NA_real_,
    sample_period = sprintf("%s ~ %s",
                            min(ret_3src$date), max(ret_3src$date))
  )

  # Save individual covariance matrix as parquet
  cov_dt <- as.data.table(S, keep.rownames = "asset")
  parquet_path <- file.path(STAGE_DIR, sprintf("covariance_3src_%s.parquet",
                                                tolower(e$name)))
  write_parquet(cov_dt, parquet_path)
  log_msg(sprintf("Saved: %s (%.1f KB)", parquet_path, file.info(parquet_path)$size / 1024))
}

cov_summary_dt <- rbindlist(lapply(cov_storage, as.data.table), fill = TRUE)
log_msg("=== Covariance 5-estimator summary (3-source 137m) ===")
print(cov_summary_dt[, .(estimator, cond_num, min_eig, is_pd, delta_lw)])
fwrite(cov_summary_dt, file.path(OUT_DIR, "covariance_3src_5estimator_summary.csv"))

# Primary recommendation = Sample (T/N=45 충분)
S_primary <- cov_sample(mat_3src)
S_primary_dt <- as.data.table(S_primary, keep.rownames = "asset")
write_parquet(S_primary_dt, file.path(STAGE_DIR, "covariance_primary.parquet"))
log_msg(sprintf("Primary covariance saved: %s/covariance_primary.parquet", STAGE_DIR))

# ============================================================================
# C5 fix: IMF 1997 + DotCom 2000 BM-only stress 응답
# ============================================================================

log_msg("--- C5 fix: IMF 1997 + DotCom 2000 BM-only stress ---")

rawdata_path <- file.path(PROJECT_ROOT, ".cache/rawdata.parquet")
RAWDATA <- as.data.table(read_parquet(rawdata_path))
RAWDATA[, Date := as.Date(Date)]

bm_dt <- RAWDATA[!is.na(BM_Ret), .(BM_Ret = first(BM_Ret)), by = Date]
bm_dt[, YM := format(Date, "%Y-%m")]
bm_monthly <- bm_dt[, .(ret = prod(1 + BM_Ret, na.rm = TRUE) - 1), by = YM]
bm_monthly[, ym_date := as.Date(paste0(YM, "-01"))]
bm_monthly <- bm_monthly[order(ym_date)]

# 8 stress periods (도훈 spec)
stress_8 <- list(
  list(name = "IMF_1997", start = "1997-07-01", end = "1998-06-30"),
  list(name = "DotCom_2000", start = "2000-03-01", end = "2001-12-31"),
  list(name = "GFC_2008", start = "2007-10-01", end = "2009-03-31"),
  list(name = "EuDebt_2011", start = "2011-07-01", end = "2011-12-31"),
  list(name = "China_Shock_2015", start = "2015-06-01", end = "2016-02-29"),
  list(name = "VolShock_2018", start = "2018-02-01", end = "2018-12-31"),
  list(name = "COVID_2020", start = "2020-01-01", end = "2020-06-30"),
  list(name = "Inflation_2022", start = "2022-01-01", end = "2022-12-31")
)

# AR sample 시작 2005-02 → IMF/DotCom AR 미가용 → BM-only 응답
ret_dt[, hybrid_70_15_15 := ifelse(has_tsmom,
                                    0.70 * r_AR + 0.15 * r_KR10y + 0.15 * r_TSMOM,
                                    (0.70 * r_AR + 0.20 * r_KR10y) / 0.90)]

stress_8_results <- list()
for (sp in stress_8) {
  s <- as.Date(sp$start); e <- as.Date(sp$end)

  # BM monthly response (always available 1990~)
  bm_sub <- bm_monthly[ym_date >= s & ym_date <= e]
  bm_total <- if (nrow(bm_sub) > 0) prod(1 + bm_sub$ret) - 1 else NA_real_
  bm_mdd <- if (nrow(bm_sub) >= 3) tryCatch(maxDrawdown(bm_sub$ret),
                                              error = function(e) NA_real_) else NA_real_

  # AR/Hybrid response (가용 시기만)
  ar_avail <- s >= as.Date("2005-02-01")
  if (ar_avail) {
    ar_sub <- ret_dt[date >= s & date <= e]
    if (nrow(ar_sub) >= 3) {
      ar_total <- prod(1 + ar_sub$r_AR, na.rm = TRUE) - 1
      hybrid_total <- prod(1 + ar_sub$hybrid_70_15_15, na.rm = TRUE) - 1
      ar_mdd <- tryCatch(maxDrawdown(ar_sub$r_AR), error = function(e) NA_real_)
      hybrid_mdd <- tryCatch(maxDrawdown(ar_sub$hybrid_70_15_15),
                              error = function(e) NA_real_)
    } else { ar_total <- hybrid_total <- ar_mdd <- hybrid_mdd <- NA_real_ }
  } else {
    ar_total <- hybrid_total <- ar_mdd <- hybrid_mdd <- NA_real_
  }

  stress_8_results[[sp$name]] <- data.table(
    period = sp$name, start = s, end = e,
    n_months_bm = nrow(bm_sub),
    bm_total_pct = bm_total * 100,
    bm_mdd_pct = bm_mdd * 100,
    ar_available = ar_avail,
    ar_total_pct = ar_total * 100,
    hybrid_total_pct = hybrid_total * 100,
    ar_mdd_pct = ar_mdd * 100,
    hybrid_mdd_pct = hybrid_mdd * 100,
    crisis_alpha_pp = (hybrid_total - ar_total) * 100  # Hybrid - AR (positive = defense PASS)
  )
}
stress_8_dt <- rbindlist(stress_8_results, fill = TRUE)
log_msg("=== 8-Crisis Stress Scenario (BM + AR + Hybrid) ===")
print(stress_8_dt)
fwrite(stress_8_dt, file.path(OUT_DIR, "stress_scenarios_8crisis_v2.csv"))

# ============================================================================
# C7 fix: KOSPI top30 universe PIT-strict re-selection (each train_end)
# ============================================================================

log_msg("--- C7 fix: PIT-strict universe re-selection ---")

RAWDATA[, YM := format(Date, "%Y-%m")]
RAWDATA[, monthly_ret_daily := Close / shift(Close) - 1, by = Ticker]
monthly <- RAWDATA[!is.na(monthly_ret_daily) & K200 == 1,
  .(month_ret = prod(1 + monthly_ret_daily) - 1,
    avg_size = mean(Size, na.rm = TRUE)),
  by = .(Ticker, YM)]
monthly[, YM_date := as.Date(paste0(YM, "-01"))]

# Each train_end k에서 직전 60m universe 재선정
W <- 60L  # train window
W_test <- 60L  # OOS test window

# Available train_end candidates: from 2014-12 (60m back to 2010-01) to 2024-12-W_test+W=2019-12
train_end_seq <- seq(as.Date("2014-12-01"), as.Date("2019-12-01"), by = "1 month")
log_msg(sprintf("Number of PIT train_end candidates: %d", length(train_end_seq)))

estim_list <- list(
  Sample = function(m) cov_sample(m),
  LW_identity = function(m) cov_lw_identity(m),
  LW_constcor = function(m) cov_lw_constcor(m),
  Gerber_v2_floor5pct = function(m) cov_gerber(m, 0.5, 0.05),
  Glasso_005 = function(m) cov_glasso(m, 0.05)
)

roll_pit_log <- list()
months_back <- function(d, n) seq(d, length = 2, by = sprintf("-%d months", n))[2]
months_fwd  <- function(d, n) seq(d, length = 2, by = sprintf("%d months", n))[2]

for (te in train_end_seq) {
  te <- as.Date(te)
  train_start <- months_back(te, W - 1L)
  test_end <- months_fwd(te, W_test)

  # PIT: train_end 시점까지의 자료만 사용해 universe 재선정
  m_train <- monthly[YM_date >= train_start & YM_date <= te]

  # Coverage filter: train window 60m 중 50개월 이상 (>=83%)
  ticker_cov <- m_train[, .(n_months = .N), by = Ticker]
  covered <- ticker_cov[n_months >= 50L]

  # Size filter: train_end 시점 자료만 사용해 top30 size
  if (nrow(covered) < 30) next
  size_at_te <- m_train[Ticker %in% covered$Ticker & YM_date == te,
                         .(Ticker, avg_size)][order(-avg_size)]
  if (nrow(size_at_te) < 30) {
    # Use last 12m avg size
    size_at_te <- m_train[Ticker %in% covered$Ticker &
                          YM_date >= months_back(te, 11L) & YM_date <= te,
                          .(median_size = median(avg_size, na.rm = TRUE)),
                          by = Ticker][order(-median_size)]
  }
  top30_pit <- size_at_te[1:30]$Ticker

  # Build train matrix (PIT)
  m_train_30 <- dcast(m_train[Ticker %in% top30_pit],
                      YM_date ~ Ticker, value.var = "month_ret")
  ret_cols <- setdiff(names(m_train_30), "YM_date")
  na_count <- sapply(m_train_30[, ..ret_cols], function(x) sum(is.na(x)))
  keep_cols <- names(na_count[na_count < 0.20 * nrow(m_train_30)])
  m_train_clean <- m_train_30[, c("YM_date", keep_cols), with = FALSE]
  m_train_clean <- m_train_clean[complete.cases(m_train_clean)]
  if (nrow(m_train_clean) < 40 || ncol(m_train_clean) - 1 < 15) next

  train_mat <- as.matrix(m_train_clean[, !"YM_date"])

  # Test matrix — same tickers (selected at train_end), test window
  m_test_30 <- dcast(monthly[Ticker %in% keep_cols &
                              YM_date > te & YM_date <= test_end],
                     YM_date ~ Ticker, value.var = "month_ret")
  if (nrow(m_test_30) < 40) next
  test_cols_avail <- intersect(keep_cols, names(m_test_30))
  m_test_clean <- m_test_30[, c("YM_date", test_cols_avail), with = FALSE]
  m_test_clean <- m_test_clean[complete.cases(m_test_clean)]
  if (nrow(m_test_clean) < 40 || ncol(m_test_clean) - 1 < 15) next

  # Align train cols to test cols
  common_cols <- intersect(keep_cols, test_cols_avail)
  if (length(common_cols) < 15) next
  train_mat <- train_mat[, common_cols, drop = FALSE]
  test_mat <- as.matrix(m_test_clean[, common_cols, with = FALSE])

  Sigma_actual <- cov_sample(test_mat)

  for (en in names(estim_list)) {
    Sigma_hat <- tryCatch(estim_list[[en]](train_mat), error = function(e) NULL)
    if (is.null(Sigma_hat)) next
    eig <- eigen(Sigma_hat, symmetric = TRUE, only.values = TRUE)$values
    cn <- max(eig) / pmax(min(eig), 1e-12)
    frob_err <- sqrt(sum((Sigma_hat - Sigma_actual)^2))
    stein_loss <- tryCatch({
      Sigma_inv <- chol2inv(chol(Sigma_hat + diag(1e-8, ncol(Sigma_hat))))
      SI_actual <- Sigma_inv %*% Sigma_actual
      sum(diag(SI_actual)) - determinant(SI_actual, logarithm = TRUE)$modulus -
        ncol(Sigma_hat)
    }, error = function(e) NA_real_)
    roll_pit_log[[length(roll_pit_log) + 1L]] <- data.table(
      train_end = te, test_end = test_end,
      n_train = nrow(train_mat), n_test = nrow(test_mat),
      n_assets = ncol(train_mat),
      estimator = en, cond_num = cn,
      frob_err = frob_err, stein_loss = as.numeric(stein_loss),
      min_eig = min(eig)
    )
  }
}

roll_pit_dt <- rbindlist(roll_pit_log, fill = TRUE)
log_msg(sprintf("PIT-strict rolling windows total observations: %d", nrow(roll_pit_dt)))

if (nrow(roll_pit_dt) > 0) {
  oos_pit_summary <- roll_pit_dt[, .(
    n_windows = .N,
    median_cond_num = median(cond_num, na.rm = TRUE),
    p95_cond_num = quantile(cond_num, 0.95, na.rm = TRUE),
    median_frob_err = median(frob_err, na.rm = TRUE),
    p95_frob_err = quantile(frob_err, 0.95, na.rm = TRUE),
    median_stein_loss = median(stein_loss, na.rm = TRUE),
    pct_pd = 100 * mean(min_eig > 1e-8, na.rm = TRUE)
  ), by = estimator][order(median_frob_err)]

  log_msg("=== KOSPI top30 OOS Forecast Performance (PIT-strict, V5) ===")
  print(oos_pit_summary)
  fwrite(oos_pit_summary, file.path(OUT_DIR, "estimator_kospi_top30_oos_pit_strict_v5.csv"))
  fwrite(roll_pit_dt, file.path(OUT_DIR, "estimator_kospi_top30_rolling_pit_strict_v5.csv"))
} else {
  log_msg("PIT-strict windows 부족 - C7 fix 결과 없음")
}

log_msg("=== PATCH V5 (Codex disposition fix) COMPLETE ===")
