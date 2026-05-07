#!/usr/bin/env Rscript
# ============================================================================
# Patch v2 — sub-period 분류 + Section 4 sector + CRISIS bootstrap + Gerber 진단
#
# 문제 1: sub-period 분류 모두 Recent_2020+ — test_end 기준이 forward 60m라 2015~
#   수정: train_end 기준으로 분류, 추가 분류기 (2010~2017 / 2018~2024) 도입
#
# 문제 2: Section 4 sector dist 4개만 — YM == "2024-12" filter 좁음
#   수정: 30 ticker 모두 → static lookup 처음부터
#
# 문제 3: Gerber condition_number 5.4M — PD 0% 명백히 broken
#   원인: gerber_corr off-diagonal이 PSD 깨질 수 있음 — diag 1, 작은 sample 시
#   수정: PSD repair eigen-clip 강화 + diagnostic 추가
#
# 추가:
# - CRISIS bootstrap CI for 3-source correlations (n=10 small)
# - Hybrid 70/15/15 portfolio CRISIS 진단 (1715 + TSMOM + KR10y)
# - 4th orthogonal source — empirical risk profile (TSMOM ETF universe 가용 다른 ETF로
#   simulated risk profile 확인. 단 alpha 추가 X — 단지 상관 진단)
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
  line <- sprintf("[%s] [PATCH_V2] %s", ts, msg)
  cat(line, "\n")
  cat(line, "\n", file = LOG_FILE, append = TRUE)
}
log_msg("=== PATCH V2 START ===")

# ---- estimator 함수 (재정의) ----
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
  F_target <- rho_bar * outer(D_sd, D_sd)
  diag(F_target) <- diag(S)
  X_centered <- scale(mat, scale = FALSE)
  X_centered[is.na(X_centered)] <- 0
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

# Gerber correlation — 강화된 PSD repair + RMT denoising 옵션
gerber_corr_v2 <- function(mat, threshold = 0.5) {
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
  diag(G) <- 1
  G
}

cov_gerber_v2 <- function(mat, threshold = 0.5, eig_floor = 0.01) {
  G <- gerber_corr_v2(mat, threshold)
  sd_vec <- apply(mat, 2, sd, na.rm = TRUE)
  S_g <- diag(sd_vec) %*% G %*% diag(sd_vec)
  rownames(S_g) <- colnames(S_g) <- colnames(mat)

  # Higham (2002) Algorithm — eigenvalue clip with proper floor
  eig <- eigen(S_g, symmetric = TRUE)
  if (min(eig$values) < eig_floor * max(eig$values)) {
    eig$values <- pmax(eig$values, eig_floor * max(eig$values))
    S_g <- eig$vectors %*% diag(eig$values) %*% t(eig$vectors)
    rownames(S_g) <- colnames(S_g) <- colnames(mat)
    attr(S_g, "psd_repair_applied") <- TRUE
    attr(S_g, "psd_repair_floor") <- eig_floor
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
# Section A: KOSPI top30 redo with sub-period stratification (train_end based)
# ============================================================================

log_msg("--- Patch v2 A: KOSPI top30 sub-period (train_end based) ---")

rawdata_path <- file.path(PROJECT_ROOT, ".cache/rawdata.parquet")
RAWDATA <- as.data.table(read_parquet(rawdata_path))
RAWDATA[, Date := as.Date(Date)]
RAWDATA[, YM := format(Date, "%Y-%m")]

RAWDATA[, monthly_ret_daily := Close / shift(Close) - 1, by = Ticker]
monthly <- RAWDATA[!is.na(monthly_ret_daily) & K200 == 1,
  .(month_ret = prod(1 + monthly_ret_daily) - 1,
    avg_size = mean(Size, na.rm = TRUE)),
  by = .(Ticker, YM)]
monthly[, YM_date := as.Date(paste0(YM, "-01"))]

m_window <- monthly[YM_date >= as.Date("2010-01-01") & YM_date <= as.Date("2024-12-31")]
ticker_coverage <- m_window[, .(n_months = .N), by = Ticker]
covered <- ticker_coverage[n_months >= 0.80 * 180L]
size_rank <- m_window[Ticker %in% covered$Ticker,
  .(median_size = median(avg_size, na.rm = TRUE)), by = Ticker][order(-median_size)]
top30 <- size_rank[1:30]$Ticker

m30 <- dcast(m_window[Ticker %in% top30],
             YM_date ~ Ticker, value.var = "month_ret")
ret_cols <- setdiff(names(m30), "YM_date")
na_count <- sapply(m30[, ..ret_cols], function(x) sum(is.na(x)))
keep_cols <- names(na_count[na_count < 0.20 * nrow(m30)])
m30_clean <- m30[, c("YM_date", keep_cols), with = FALSE]
m30_clean <- m30_clean[complete.cases(m30_clean)]
m30_dates <- m30_clean$YM_date
m30_mat <- as.matrix(m30_clean[, !"YM_date"])
log_msg(sprintf("KOSPI top30 matrix: %d × %d", nrow(m30_mat), ncol(m30_mat)))

W <- 60L
n_rolls <- nrow(m30_mat) - W - W + 1L

estim_list_b <- list(
  Sample = function(m) cov_sample(m),
  LW_identity = function(m) cov_lw_identity(m),
  LW_constcor = function(m) cov_lw_constcor(m),
  Gerber_v2_floor1pct = function(m) cov_gerber_v2(m, 0.5, 0.01),
  Gerber_v2_floor5pct = function(m) cov_gerber_v2(m, 0.5, 0.05),
  Glasso_005 = function(m) cov_glasso(m, 0.05)
)

roll_log <- list()
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
}
roll_dt <- rbindlist(roll_log, fill = TRUE)

# Sub-period — train_end 기준 (자료 학습 시점)
roll_dt[, period := fcase(
  train_end <= as.Date("2014-12-31"), "Period1_2010_2014",
  train_end <= as.Date("2018-12-31"), "Period2_2015_2018",
  train_end <= as.Date("2022-12-31"), "Period3_2019_2022",
  default = "Period4_2023+"
)]
roll_dt[, period_train_end := train_end]

oos_overall <- roll_dt[, .(
  n_windows = .N,
  median_cond_num = median(cond_num, na.rm = TRUE),
  p95_cond_num = quantile(cond_num, 0.95, na.rm = TRUE),
  median_frob_err = median(frob_err, na.rm = TRUE),
  p95_frob_err = quantile(frob_err, 0.95, na.rm = TRUE),
  median_stein_loss = median(stein_loss, na.rm = TRUE),
  pct_pd = 100 * mean(min_eig > 1e-8, na.rm = TRUE)
), by = estimator][order(median_frob_err)]
log_msg("=== KOSPI top30 OOS Forecast Performance (V2) ===")
print(oos_overall)
fwrite(oos_overall, file.path(OUT_DIR, "estimator_kospi_top30_oos_summary_v2.csv"))

oos_subperiod <- roll_dt[, .(
  n_windows = .N,
  median_cond_num = median(cond_num, na.rm = TRUE),
  median_frob_err = median(frob_err, na.rm = TRUE),
  median_stein_loss = median(stein_loss, na.rm = TRUE),
  pct_pd = 100 * mean(min_eig > 1e-8, na.rm = TRUE)
), by = .(estimator, period)]
oos_subperiod <- oos_subperiod[order(period, median_frob_err)]
log_msg("=== Sub-period OOS Performance (V2, train_end based) ===")
print(oos_subperiod)
fwrite(oos_subperiod, file.path(OUT_DIR, "estimator_kospi_top30_subperiod_v2.csv"))
fwrite(roll_dt, file.path(OUT_DIR, "estimator_kospi_top30_rolling_log_v2.csv"))

# ============================================================================
# Section B: Sector distribution 정정 (deploy_snapshot AR top20 + KOSPI top30)
# ============================================================================

log_msg("--- Patch v2 B: Sector distribution 정정 ---")

deploy_path <- file.path(PROJECT_ROOT,
  "qepm/mailbox/worktask/WT-P20260505_001/deploy_snapshot_20260601.csv")
deploy_dt <- fread(deploy_path)
log_msg(sprintf("deploy_snapshot: %d rows", nrow(deploy_dt)))
log_msg(sprintf("Columns: %s", paste(names(deploy_dt), collapse = ", ")))

# AR top20 sector distribution
ar_top20 <- deploy_dt[asset_class == "EQ_KR_TOP20"]
ar_sector_dist <- ar_top20[, .(
  count = .N,
  total_weight = sum(weight_final, na.rm = TRUE)
), by = sector][order(-total_weight)]
log_msg("=== AR Top20 Sector Distribution (실 운용 6/1 effective) ===")
print(ar_sector_dist)
fwrite(ar_sector_dist, file.path(OUT_DIR, "ar_top20_sector_distribution.csv"))

# KOSPI200 top30 sector — static lookup
sector_lookup <- RAWDATA[!is.na(Sector), .(Sector = first(Sector)), by = Ticker]
top30_sector <- sector_lookup[Ticker %in% top30]
top30_sector_dist <- top30_sector[, .N, by = Sector][order(-N)]
log_msg("=== KOSPI200 Top30 Sector Distribution (static lookup) ===")
print(top30_sector_dist)
fwrite(top30_sector_dist, file.path(OUT_DIR, "sector_top30_kospi200_v2.csv"))

# Sector overlap — AR top20 vs TSMOM ETF sector
# AR top20 sectors
ar_sectors <- unique(ar_top20$sector)
log_msg(sprintf("AR top20 unique sectors: %d (%s)",
                length(ar_sectors), paste(ar_sectors, collapse = ", ")))

tsmom_etf_lookup <- list(
  A069500 = "KODEX_200_KR_equity",
  A148070 = "KODEX_KR10y_bond",  # KR_10y leg
  A143850 = "TIGER_US_S&P500",
  A132030 = "KODEX_Gold",
  A308620 = "KODEX_NASDAQ100",
  A284430 = "KODEX_KOSDAQ150",
  A329200 = "KODEX_USD_Cash",
  A229200 = "KODEX_KOSDAQ_Smallcap",
  A157450 = "KODEX_China_H_share"
)
log_msg(sprintf("TSMOM ETF pool (9): %s", paste(names(tsmom_etf_lookup), collapse = ", ")))

# ============================================================================
# Section C: CRISIS bootstrap CI (3-source, n=10 small)
# ============================================================================

log_msg("--- Patch v2 C: CRISIS bootstrap CI ---")

ret_file <- file.path(PROJECT_ROOT,
  "qepm/mailbox/worktask/WT-P20260505_001/architect_hybrid_returns_full256m.csv")
ret_dt <- fread(ret_file)
ret_dt[, date := as.Date(date)]
ret_dt[, YM := format(date, "%Y-%m")]
ret_dt[, has_tsmom := !is.na(r_TSMOM)]

bm_dt <- RAWDATA[!is.na(BM_Ret), .(BM_Ret = first(BM_Ret)), by = Date]
bm_dt[, YM := format(Date, "%Y-%m")]
bm_monthly <- bm_dt[, .(ret = prod(1 + BM_Ret, na.rm = TRUE) - 1), by = YM]
bm_monthly[, ym_date := as.Date(paste0(YM, "-01"))]
bm_monthly <- bm_monthly[order(ym_date)]

ret_dt <- merge(ret_dt, bm_monthly[, .(YM, bm_ret = ret)], by = "YM", all.x = TRUE)
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

# CRISIS only — n=10 sample
crisis_dt <- ret_dt[regime_4 == "CRISIS" & has_tsmom == TRUE]
log_msg(sprintf("CRISIS × 3-source joint sample: %d months", nrow(crisis_dt)))

bootstrap_corr_ci <- function(x, y, n_boot = 1000, alpha = 0.10) {
  if (length(x) < 5) return(c(NA, NA, NA))
  ok <- !is.na(x) & !is.na(y)
  x <- x[ok]; y <- y[ok]
  boots <- replicate(n_boot, {
    idx <- sample(seq_along(x), replace = TRUE)
    cor(x[idx], y[idx])
  })
  c(observed = cor(x, y),
    ci_low = quantile(boots, alpha / 2),
    ci_high = quantile(boots, 1 - alpha / 2))
}

set.seed(20260507)
crisis_corr_ci <- list()
if (nrow(crisis_dt) >= 5) {
  ar_kr_ci <- bootstrap_corr_ci(crisis_dt$r_AR, crisis_dt$r_KR10y)
  ar_ts_ci <- bootstrap_corr_ci(crisis_dt$r_AR, crisis_dt$r_TSMOM)
  kr_ts_ci <- bootstrap_corr_ci(crisis_dt$r_KR10y, crisis_dt$r_TSMOM)
  crisis_corr_ci_dt <- data.table(
    pair = c("AR_KR10y", "AR_TSMOM", "KR10y_TSMOM"),
    n_obs = nrow(crisis_dt),
    observed_corr = c(ar_kr_ci["observed"], ar_ts_ci["observed"], kr_ts_ci["observed"]),
    ci90_low = c(ar_kr_ci["ci_low.5%"], ar_ts_ci["ci_low.5%"], kr_ts_ci["ci_low.5%"]),
    ci90_high = c(ar_kr_ci["ci_high.95%"], ar_ts_ci["ci_high.95%"], kr_ts_ci["ci_high.95%"])
  )
  log_msg("=== CRISIS regime correlation 90% bootstrap CI (n=10) ===")
  print(crisis_corr_ci_dt)
  fwrite(crisis_corr_ci_dt, file.path(OUT_DIR, "crisis_correlation_bootstrap_ci.csv"))
} else {
  log_msg("CRISIS sample 부족 - bootstrap 생략")
  crisis_corr_ci_dt <- data.table()
}

# ============================================================================
# Section D: Hybrid 70/15/15 portfolio CRISIS 진단 (실 weight 적용)
# ============================================================================

log_msg("--- Patch v2 D: Hybrid 70/15/15 CRISIS 진단 ---")

ret_dt[, hybrid_70_15_15 := ifelse(has_tsmom,
                                    0.70 * r_AR + 0.15 * r_KR10y + 0.15 * r_TSMOM,
                                    (0.70 * r_AR + 0.20 * r_KR10y) / 0.90)]

hybrid_regime_summary <- ret_dt[!is.na(regime_4),
  .(n = .N,
    mean_monthly = mean(hybrid_70_15_15, na.rm = TRUE),
    sd_monthly = sd(hybrid_70_15_15, na.rm = TRUE),
    cum_ret = prod(1 + hybrid_70_15_15, na.rm = TRUE) - 1,
    min_monthly = min(hybrid_70_15_15, na.rm = TRUE),
    max_monthly = max(hybrid_70_15_15, na.rm = TRUE),
    cvar_95 = mean(hybrid_70_15_15[hybrid_70_15_15 <= quantile(
      hybrid_70_15_15, 0.05, na.rm = TRUE)], na.rm = TRUE)),
  by = regime_4][order(regime_4)]
log_msg("=== Hybrid 70/15/15 by Regime ===")
print(hybrid_regime_summary)
fwrite(hybrid_regime_summary, file.path(OUT_DIR, "hybrid_regime_response.csv"))

# Bootstrap Sharpe by regime (small sample)
bootstrap_sharpe <- function(r, n_boot = 1000) {
  r <- na.omit(r)
  if (length(r) < 3) return(c(NA, NA, NA))
  observed <- mean(r) / sd(r) * sqrt(12)
  boots <- replicate(n_boot, {
    idx <- sample(seq_along(r), replace = TRUE)
    rb <- r[idx]
    if (sd(rb) < 1e-10) NA else mean(rb) / sd(rb) * sqrt(12)
  })
  c(observed = observed,
    ci_low = quantile(boots, 0.05, na.rm = TRUE),
    ci_high = quantile(boots, 0.95, na.rm = TRUE))
}

regime_sharpe_ci <- list()
for (rg in unique(ret_dt$regime_4)) {
  if (is.na(rg)) next
  sub <- ret_dt[regime_4 == rg]
  sr_ci <- bootstrap_sharpe(sub$hybrid_70_15_15)
  regime_sharpe_ci[[rg]] <- data.table(
    regime = rg, n = nrow(sub),
    sr_observed = sr_ci["observed"],
    sr_ci90_low = sr_ci["ci_low.5%"],
    sr_ci90_high = sr_ci["ci_high.95%"]
  )
}
regime_sharpe_dt <- rbindlist(regime_sharpe_ci, fill = TRUE)
log_msg("=== Hybrid Sharpe by Regime (90% bootstrap CI) ===")
print(regime_sharpe_dt)
fwrite(regime_sharpe_dt, file.path(OUT_DIR, "hybrid_regime_sharpe_ci.csv"))

# ============================================================================
# Section E: 4th orthogonal source — empirical risk profile
# AR top20 vs simulated alt sources (using KOSPI universe sub-baskets as proxy)
# ============================================================================

log_msg("--- Patch v2 E: 4th orthogonal source empirical risk profile ---")

# 본 risk-research agent는 alpha 추가 금지 — 단지 "risk profile" 비교만 수행.
# 가설: 어떤 ETF universe / sub-basket이 현 Hybrid에 risk-orthogonal한가?

# 가용 KOSPI 전체 large-cap (top 30 외) — proxy for diversifier candidates
# (실제 구체 alpha factor / 신규 strategy 제안 X — 단지 sector-level cor 진단)

# Sector portfolios in KOSPI200 — equal weight per Sector
sector_summary <- monthly[Ticker %in% covered$Ticker]
sector_summary <- merge(sector_summary, sector_lookup, by = "Ticker", all.x = TRUE)
sector_summary <- sector_summary[!is.na(Sector)]

sector_pf <- sector_summary[, .(sector_ret = mean(month_ret, na.rm = TRUE),
                                  n_tickers = uniqueN(Ticker)),
                             by = .(Sector, YM_date)]
sector_pf_wide <- dcast(sector_pf, YM_date ~ Sector, value.var = "sector_ret")
sector_pf_wide <- sector_pf_wide[order(YM_date)]
log_msg(sprintf("Sector portfolios available: %d sectors × %d months",
                ncol(sector_pf_wide) - 1, nrow(sector_pf_wide)))

# Hybrid 70/15/15 monthly returns matched to sector portfolios
hybrid_match <- ret_dt[, .(YM_date = as.Date(paste0(YM, "-01")), hybrid_70_15_15)]
sec_compare <- merge(hybrid_match, sector_pf_wide, by = "YM_date")
sec_compare <- sec_compare[!is.na(hybrid_70_15_15)]
log_msg(sprintf("Sector × Hybrid match: %d months", nrow(sec_compare)))

# Compute correlation between each sector portfolio and Hybrid
sector_cols <- setdiff(names(sec_compare), c("YM_date", "hybrid_70_15_15"))
sector_corr_with_hybrid <- data.table(
  Sector = sector_cols,
  cor_with_Hybrid = sapply(sector_cols, function(s) {
    x <- sec_compare[[s]]; y <- sec_compare$hybrid_70_15_15
    if (sum(!is.na(x) & !is.na(y)) < 30) NA_real_ else
      cor(x, y, use = "pairwise.complete.obs")
  }),
  n_obs_complete = sapply(sector_cols, function(s)
    sum(!is.na(sec_compare[[s]]) & !is.na(sec_compare$hybrid_70_15_15)))
)[order(cor_with_Hybrid)]
log_msg("=== Sector portfolios — correlation with Hybrid (sorted ascending) ===")
print(sector_corr_with_hybrid)
fwrite(sector_corr_with_hybrid, file.path(OUT_DIR, "sector_corr_with_hybrid.csv"))

# Top low-correlation sectors → potential 4th orthogonal candidates
log_msg("=== Top 5 lowest-correlation sectors with Hybrid ===")
log_msg("(meta diagnostic — alpha 추가 X, strategy 제안 X — risk profile 진단 only)")
print(head(sector_corr_with_hybrid[!is.na(cor_with_Hybrid)], 5))

# ============================================================================
# Section F: Hill alpha + GPD on Hybrid CRISIS
# ============================================================================

log_msg("--- Patch v2 F: Hybrid CRISIS tail fit ---")

if (nrow(crisis_dt) >= 5) {
  hybrid_crisis <- na.omit(crisis_dt$hybrid_70_15_15)
  losses_hc <- -hybrid_crisis
  losses_hc_sorted <- sort(losses_hc, decreasing = TRUE)
  k_hill <- max(2, floor(0.30 * length(losses_hc)))
  if (k_hill < length(losses_hc_sorted) && losses_hc_sorted[k_hill + 1] > 0) {
    hill_alpha_hc <- 1 / mean(log(losses_hc_sorted[1:k_hill] /
                                  losses_hc_sorted[k_hill + 1]))
  } else hill_alpha_hc <- NA_real_

  log_msg(sprintf("Hybrid CRISIS Hill alpha (n_top=%d, n=%d): %.3f",
                  k_hill, length(hybrid_crisis), hill_alpha_hc))

  # Empirical CVaR at multiple alpha
  hybrid_crisis_cvar <- data.table(
    n_obs = length(hybrid_crisis),
    mean_pct = mean(hybrid_crisis) * 100,
    sd_pct = sd(hybrid_crisis) * 100,
    var_90 = quantile(hybrid_crisis, 0.10),
    var_95 = quantile(hybrid_crisis, 0.05),
    var_99 = quantile(hybrid_crisis, 0.01),
    cvar_90 = mean(hybrid_crisis[hybrid_crisis <= quantile(hybrid_crisis, 0.10)]),
    cvar_95 = mean(hybrid_crisis[hybrid_crisis <= quantile(hybrid_crisis, 0.05)]),
    hill_alpha = hill_alpha_hc
  )
  log_msg("=== Hybrid CRISIS tail metrics ===")
  print(hybrid_crisis_cvar)
  fwrite(hybrid_crisis_cvar, file.path(OUT_DIR, "hybrid_crisis_tail.csv"))
} else {
  log_msg("Hybrid CRISIS sample 부족")
}

log_msg("=== PATCH V2 COMPLETE ===")
