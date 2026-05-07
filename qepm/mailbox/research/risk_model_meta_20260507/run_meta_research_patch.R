#!/usr/bin/env Rscript
# ============================================================================
# Patch run — Section 1B KOSPI top30 universe 재선정 + Section 3 regime fix
#
# 문제 1: Section 1B 28 ticker 중 complete_case 0
#   원인: A373220 (LG에솔, 2022 상장) 등 신규 종목 결측
#   수정: 2010~2024 expanded universe → top 50 후 in-sample n_obs >= 80% 필터
#
# 문제 2: regime_4 분류 NA 254
#   원인: bm_monthly$ym_date (month-01) vs ret_dt$date (varies 1~5)
#   수정: YM key (year-month string)로 merge
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

LOG_FILE <- file.path(OUT_DIR, "meta_research_log.txt")
log_msg <- function(msg) {
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  line <- sprintf("[%s] [PATCH] %s", ts, msg)
  cat(line, "\n")
  cat(line, "\n", file = LOG_FILE, append = TRUE)
}
log_msg("=== PATCH RUN START ===")

# ---- estimator 함수 (재정의 - 본 patch 내부) ----
cov_sample <- function(mat) cov(mat, use = "pairwise.complete.obs")

cov_lw_identity <- function(mat) {
  T_n <- nrow(mat); N <- ncol(mat)
  S <- cov(mat, use = "pairwise.complete.obs")
  mu_target <- mean(diag(S))
  F_target <- mu_target * diag(N)
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
  S_shrunk
}

cov_lw_constcor <- function(mat) {
  T_n <- nrow(mat); N <- ncol(mat)
  S <- cov(mat, use = "pairwise.complete.obs")
  R <- cor(mat, use = "pairwise.complete.obs")
  if (N == 1) return(S)
  rho_bar <- (sum(R) - N) / (N * (N - 1))
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

cov_gerber <- function(mat, threshold = 0.5) {
  G <- gerber_corr(mat, threshold)
  sd_vec <- apply(mat, 2, sd, na.rm = TRUE)
  S_g <- diag(sd_vec) %*% G %*% diag(sd_vec)
  rownames(S_g) <- colnames(S_g) <- colnames(mat)
  eig <- eigen(S_g, symmetric = TRUE)
  if (min(eig$values) < 1e-8) {
    eig$values[eig$values < 1e-8] <- 1e-8
    S_g <- eig$vectors %*% diag(eig$values) %*% t(eig$vectors)
    rownames(S_g) <- colnames(S_g) <- colnames(mat)
  }
  S_g
}

cov_glasso <- function(mat, rho = 0.05) {
  S <- cov(mat, use = "pairwise.complete.obs")
  fit <- tryCatch(
    glasso::glasso(s = S, rho = rho, penalize.diagonal = FALSE),
    error = function(e) NULL)
  if (is.null(fit)) return(S)
  S_g <- fit$w
  rownames(S_g) <- colnames(S_g) <- colnames(mat)
  attr(S_g, "rho") <- rho
  S_g
}

# ============================================================================
# Patch Section 1B: KOSPI top30 universe 재선정
# ============================================================================

log_msg("--- Patch 1B: KOSPI top30 universe 재선정 ---")

rawdata_path <- file.path(PROJECT_ROOT, ".cache/rawdata.parquet")
RAWDATA <- as.data.table(read_parquet(rawdata_path))
RAWDATA[, Date := as.Date(Date)]
RAWDATA[, YM := format(Date, "%Y-%m")]

# K200 universe filter — 명시적으로 K200=1 종목만
log_msg(sprintf("RAWDATA total rows: %d", nrow(RAWDATA)))
log_msg(sprintf("K200=1 rows: %d", sum(RAWDATA$K200 == 1, na.rm = TRUE)))

# 월간 수익률 (Close-to-close monthly)
RAWDATA[, monthly_ret_daily := Close / shift(Close) - 1, by = Ticker]
monthly <- RAWDATA[!is.na(monthly_ret_daily) & K200 == 1,
  .(month_ret = prod(1 + monthly_ret_daily) - 1,
    avg_size = mean(Size, na.rm = TRUE),
    n_days = .N),
  by = .(Ticker, YM)]
monthly[, YM_date := as.Date(paste0(YM, "-01"))]

# Window 2010-01 ~ 2024-12 (180 months)
m_window <- monthly[YM_date >= as.Date("2010-01-01") & YM_date <= as.Date("2024-12-31")]
log_msg(sprintf("K200 monthly window 2010~2024: %d rows", nrow(m_window)))

# Coverage filter — 80% 이상 in-sample 종목만
ticker_coverage <- m_window[, .(n_months = .N), by = Ticker]
target_n <- 180L  # 2010-01 to 2024-12 = 180 months
covered <- ticker_coverage[n_months >= 0.80 * target_n]
log_msg(sprintf("Tickers with >=80%% coverage: %d", nrow(covered)))

# Top 30 by median size among covered
size_rank <- m_window[Ticker %in% covered$Ticker,
  .(median_size = median(avg_size, na.rm = TRUE)), by = Ticker][order(-median_size)]
top30 <- size_rank[1:30]$Ticker
log_msg(sprintf("Top 30 large-cap covered: %s ...", paste(top30[1:5], collapse = ", ")))

# Reshape to YM_date × Ticker matrix — 결측 forward fill 안 함, NA 명시
m30 <- dcast(m_window[Ticker %in% top30],
             YM_date ~ Ticker, value.var = "month_ret")
log_msg(sprintf("KOSPI top30 monthly matrix raw: %d × %d", nrow(m30), ncol(m30) - 1))

# Drop columns with too many NA (>20% missing)
ret_cols <- setdiff(names(m30), "YM_date")
na_count <- sapply(m30[, ..ret_cols], function(x) sum(is.na(x)))
keep_cols <- names(na_count[na_count < 0.20 * nrow(m30)])
log_msg(sprintf("Tickers passing 80%% non-NA: %d", length(keep_cols)))
m30_clean <- m30[, c("YM_date", keep_cols), with = FALSE]
m30_clean <- m30_clean[complete.cases(m30_clean)]
log_msg(sprintf("After complete-case (rows × cols): %d × %d",
                nrow(m30_clean), ncol(m30_clean) - 1))

m30_dates <- m30_clean$YM_date
m30_mat <- as.matrix(m30_clean[, !"YM_date"])

# Rolling 60m × 60m OOS
W <- 60L
n_rolls <- nrow(m30_mat) - W - W + 1L
log_msg(sprintf("Rolling windows possible: %d (need >= 5)", n_rolls))

if (n_rolls > 5) {
  estim_list_b <- list(
    Sample = function(m) cov_sample(m),
    LW_identity = function(m) cov_lw_identity(m),
    LW_constcor = function(m) cov_lw_constcor(m),
    Gerber_05 = function(m) cov_gerber(m, 0.5),
    Glasso_005 = function(m) cov_glasso(m, 0.05)
  )

  roll_log <- list()
  roll_step <- max(1, floor(n_rolls / 10))
  pb_t0 <- Sys.time()

  for (k in seq_len(n_rolls)) {
    train <- m30_mat[k:(k + W - 1L), ]
    test  <- m30_mat[(k + W):(k + 2L * W - 1L), ]
    Sigma_actual <- cov_sample(test)

    for (en in names(estim_list_b)) {
      Sigma_hat <- tryCatch(estim_list_b[[en]](train), error = function(e) NULL)
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
      roll_log[[length(roll_log) + 1L]] <- data.table(
        window_start = m30_dates[k],
        train_end = m30_dates[k + W - 1L],
        test_end = m30_dates[k + 2L * W - 1L],
        estimator = en, cond_num = cn,
        frob_err = frob_err, stein_loss = as.numeric(stein_loss),
        min_eig = min(eig)
      )
    }
    if (k %% roll_step == 0) {
      elapsed <- as.numeric(difftime(Sys.time(), pb_t0, units = "secs"))
      log_msg(sprintf("  rolling %d/%d (%.0f%%) elapsed %.1fs",
                      k, n_rolls, 100 * k / n_rolls, elapsed))
    }
  }
  roll_dt <- rbindlist(roll_log, fill = TRUE)

  oos_summary <- roll_dt[, .(
    n_windows = .N,
    median_cond_num = median(cond_num, na.rm = TRUE),
    p95_cond_num = quantile(cond_num, 0.95, na.rm = TRUE),
    median_frob_err = median(frob_err, na.rm = TRUE),
    p95_frob_err = quantile(frob_err, 0.95, na.rm = TRUE),
    median_stein_loss = median(stein_loss, na.rm = TRUE),
    pct_pd = 100 * mean(min_eig > 1e-8, na.rm = TRUE)
  ), by = estimator]
  oos_summary <- oos_summary[order(median_frob_err)]
  log_msg("=== KOSPI top30 OOS Forecast Performance (PATCHED) ===")
  print(oos_summary)
  fwrite(oos_summary, file.path(OUT_DIR, "estimator_kospi_top30_oos_summary.csv"))
  fwrite(roll_dt, file.path(OUT_DIR, "estimator_kospi_top30_rolling_log.csv"))

  # Sub-period 추정 — 정상 (2010~2019) vs 위기 (2020 covid + 2022 inflation)
  log_msg("--- Sub-period stratification ---")
  roll_dt[, period := ifelse(test_end <= as.Date("2019-12-31"), "Normal_2010s", "Recent_2020+")]
  oos_subperiod <- roll_dt[, .(
    n_windows = .N,
    median_cond_num = median(cond_num, na.rm = TRUE),
    median_frob_err = median(frob_err, na.rm = TRUE),
    median_stein_loss = median(stein_loss, na.rm = TRUE)
  ), by = .(estimator, period)]
  log_msg("=== Sub-period OOS Performance ===")
  print(oos_subperiod[order(period, median_frob_err)])
  fwrite(oos_subperiod, file.path(OUT_DIR, "estimator_kospi_top30_subperiod.csv"))
} else {
  log_msg("Patch 1B still failed — n_rolls insufficient")
  oos_summary <- data.table()
}

# ============================================================================
# Patch Section 3: regime_4 분류 fix (YM key merge)
# ============================================================================

log_msg("--- Patch 3: regime_4 fix via YM key ---")

ret_file <- file.path(PROJECT_ROOT,
  "qepm/mailbox/worktask/WT-P20260505_001/architect_hybrid_returns_full256m.csv")
ret_dt <- fread(ret_file)
ret_dt[, date := as.Date(date)]
ret_dt[, YM := format(date, "%Y-%m")]
ret_dt[, has_tsmom := !is.na(r_TSMOM)]

# BM monthly with YM key
bm_dt <- RAWDATA[!is.na(BM_Ret), .(BM_Ret = first(BM_Ret)), by = Date]
bm_dt[, YM := format(Date, "%Y-%m")]
bm_monthly <- bm_dt[, .(ret = prod(1 + BM_Ret, na.rm = TRUE) - 1), by = YM]
bm_monthly[, ym_date := as.Date(paste0(YM, "-01"))]
bm_monthly <- bm_monthly[order(ym_date)]
log_msg(sprintf("BM monthly: %d obs", nrow(bm_monthly)))

# Merge by YM (string key)
ret_dt <- merge(ret_dt, bm_monthly[, .(YM, bm_ret = ret)], by = "YM", all.x = TRUE)
log_msg(sprintf("ret_dt with bm_ret: %d obs (non-NA bm_ret: %d)",
                nrow(ret_dt), sum(!is.na(ret_dt$bm_ret))))

# Rolling 12m vol annualized — t-1 lag (PIT)
ret_dt <- ret_dt[order(date)]
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
regime_dist <- ret_dt[, .N, by = regime_4][order(-N)]
log_msg("=== 4-Regime distribution (PATCHED) ===")
print(regime_dist)
fwrite(regime_dist, file.path(OUT_DIR, "regime_4_distribution.csv"))

# Conditional correlation — 3-source post-2015
ret_3src_reg <- ret_dt[has_tsmom == TRUE & !is.na(regime_4)]
log_msg(sprintf("3-source × regime sample: %d months", nrow(ret_3src_reg)))

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
log_msg("=== Regime-conditional correlation (3-source, PATCHED) ===")
print(regime_corr_dt)
fwrite(regime_corr_dt, file.path(OUT_DIR, "regime_correlation_4regime.csv"))

# ============================================================================
# Patch Section 4: Crowding 보강 — RAWDATA Sector 활용
# ============================================================================

log_msg("--- Patch 4: Crowding 보강 (Sector-level) ---")

# STR_1715 5월 운용 top20 종목 — book_state 참조 자료
# 정확한 종목 list는 deploy_snapshot.csv 참조 (없으면 본 메타에선 sector 분포 일반화)
deploy_path <- file.path(PROJECT_ROOT,
  "qepm/mailbox/worktask/WT-P20260505_001/deploy_snapshot_20260601.csv")
if (file.exists(deploy_path)) {
  deploy_dt <- fread(deploy_path)
  log_msg(sprintf("deploy_snapshot 가용: %d rows, columns: %s",
                  nrow(deploy_dt), paste(names(deploy_dt), collapse = ",")))
  print(head(deploy_dt, 3))
} else {
  log_msg("deploy_snapshot 없음 — 본 patch에서 일반 stock universe sector 분포로 대체")
  deploy_dt <- NULL
}

# Top 30 KOSPI by Sector distribution
sector_dist <- monthly[Ticker %in% top30 & YM == "2024-12",
                        .(Ticker, YM, avg_size)]
# Sector 정보 추가 from RAWDATA
sector_lookup <- RAWDATA[, .(Sector = first(Sector)), by = Ticker]
sector_dist <- merge(sector_dist, sector_lookup, by = "Ticker", all.x = TRUE)
sector_top30_summary <- sector_dist[!is.na(Sector), .N, by = Sector][order(-N)]
log_msg("=== Top 30 KOSPI200 Sector distribution ===")
print(sector_top30_summary)
fwrite(sector_top30_summary, file.path(OUT_DIR, "sector_top30_kospi200.csv"))

# Crowding heuristic 보강
crowd_summary <- list(
  has_sector_col = TRUE,
  rawdata_columns_count = ncol(RAWDATA),
  STR_1715_top20_max_pct = 0.14,
  TSMOM_max_etf_pct = 0.30,
  TSMOM_etf_pool_size = 9L,
  KR10y_passive_carry = TRUE,
  hybrid_global_max_post_overlay = 0.1768,
  unique_nonzero_tickers = 27L,
  top30_kospi200_top_sector = sector_top30_summary$Sector[1],
  top30_kospi200_top_sector_count = sector_top30_summary$N[1],
  top30_kospi200_n_unique_sectors = nrow(sector_top30_summary),
  notes = "STR_1715 정확한 5월 운용 종목 list는 governor admission snapshot 의존; 본 patch는 KOSPI200 top30 sector 분포 메타"
)
fwrite(as.data.table(crowd_summary), file.path(OUT_DIR, "crowding_heuristic.csv"))

log_msg("=== PATCH RUN COMPLETE ===")
