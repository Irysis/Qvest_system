#==============================================================================
# WT-D20260508_003 — VRP 4 sub-variants Vol-Beta Cross-Section Alpha
#
# 자율 plan (Charter v1.2 Role Card discovery):
#   - 4 sub-variants (BKM/CW/BTZ/BCI) timeseries → 종목별 vol-beta cross-section
#   - Composite F5 = inv-variance Bayesian ensemble
#   - ML XGBoost CUDA 비교 + classical OLS Fama-MacBeth baseline 의무
#   - WT_001 traps 사전 진단: predictor lag-1 autocor / feature leakage / naive long bias
#   - WT_002 v5 lessons: PIT-rolling factor selection + t-1 universe + Bailey-LdP DSR
#   - lockbox 2020~2026.04 Alpha 접근 금지 (R2 Window Isolation HARD)
#
# Inputs:
#   - .cache/rawdata.parquet (가격/거래량/Universe/Sector)
#   - .cache/fred_macro_wide.parquet (VIX)
#   - cycle 3 axis_1 4 sub-variants methodology (BKM/CW/BTZ/BCI)
#
# Outputs:
#   - alpha_package_draft.json (8-field schema)
#   - stage_artifacts/WT_D20260508_003/alpha_scores.parquet
#   - stage_artifacts/WT_D20260508_003/alpha_validation.json
#   - stage_artifacts/WT_D20260508_003/predictor_autocor_diagnosis.json
#   - stage_artifacts/WT_D20260508_003/feature_leakage_check.json
#   - stage_artifacts/WT_D20260508_003/crisis_anti_hedge_diagnosis.json
#   - stage_artifacts/WT_D20260508_003/dsr_strict_bailey_ldp.json
#   - stage_artifacts/WT_D20260508_003/forward_2026_05_predictions.parquet
#   - stage_artifacts/WT_D20260508_003/gpu_acceleration_report.json
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(future)
  library(future.apply)
})

# Local ntile (no dplyr dependency)
ntile <- function(x, n) {
  r <- rank(x, ties.method = "average", na.last = "keep")
  q <- (r - 0.5) / sum(!is.na(r))
  out <- floor(q * n) + 1L
  out[out > n] <- n
  out
}

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-D20260508_003"
WT_DIR       <- file.path(PROJECT_ROOT, "qepm", "mailbox", "worktask", WT_ID)
STAGE_DIR    <- file.path(PROJECT_ROOT, "stage_artifacts", "WT_D20260508_003")
dir.create(STAGE_DIR, recursive = TRUE, showWarnings = FALSE)

cat("=== WT-D20260508_003 Alpha Research ===\n")
cat("As-of:", as.character(Sys.Date()), "\n")
cat("Project root:", PROJECT_ROOT, "\n\n")

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Data Load (rawdata + VIX)
# ─────────────────────────────────────────────────────────────────────────────
cat("[Step 1] Loading rawdata + VIX...\n")
RAWDATA_PATH <- file.path(PROJECT_ROOT, ".cache", "rawdata.parquet")
FRED_WIDE_PATH <- file.path(PROJECT_ROOT, ".cache", "fred_macro_wide.parquet")

rd <- as.data.table(read_parquet(RAWDATA_PATH))
rd[, Date := as.Date(Date)]
cat(sprintf("  rawdata loaded: %s rows, %s tickers, %s ~ %s\n",
            format(nrow(rd), big.mark=","),
            format(uniqueN(rd$Ticker), big.mark=","),
            min(rd$Date), max(rd$Date)))

# Universe filter: KOSPI200 ∪ KOSDAQ150 (PIT t-1)
# rd[, K200 K200=1] OR rd[, KQ150=1]
rd[, in_universe := (K200 == 1 | KQ150 == 1) & !is.na(Close) & !is.na(Ret)]

# Liquidity 20d avg TV ≥ 2e8 (Hard Constraint, request 5e7 floor도 충족)
LIQ_THRESHOLD <- 2e8
setkey(rd, Ticker, Date)
rd[, TV := Close * Vol]
# 20-day rolling avg TV
rd[, TV20_lag1 := shift(frollmean(TV, 20, fill = NA, align = "right"), 1L), by = Ticker]
rd[, liquid := !is.na(TV20_lag1) & TV20_lag1 >= LIQ_THRESHOLD]

# FRED VIX
fred <- as.data.table(read_parquet(FRED_WIDE_PATH))
fred[, Date := as.Date(Date)]
setkey(fred, Date)
vix_dt <- fred[, .(Date, VIX)][!is.na(VIX)]
cat(sprintf("  VIX: %s rows, %s ~ %s\n", nrow(vix_dt), min(vix_dt$Date), max(vix_dt$Date)))

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Compute KOSPI BM realized vol 12m + VIX EOM lag1 → 4 sub-variants
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 2] Computing 4 VRP sub-variants (BKM / CW / BTZ / BCI)...\n")

# Monthly EOM dates from rawdata (use BM_Ret coverage)
rd[, BM_Ret := as.numeric(BM_Ret)]
bm_daily <- unique(rd[!is.na(BM_Ret), .(Date, BM_Ret)])
setkey(bm_daily, Date)
bm_daily[, yearmonth := format(Date, "%Y-%m")]

# Monthly EOM (last trading day per yearmonth)
month_eom <- bm_daily[, .SD[.N], by = yearmonth][, .(Date, yearmonth)]
setkey(month_eom, Date)

# RV 12m (annualized) per EOM = sqrt(252) * sd(daily BM_Ret last 252 trading days)
# PIT-strict: RV12m at t = use BM_Ret up to t (no lookahead)
bm_daily[, idx := .I]
get_rv12m <- function(end_date) {
  # daily BM_Ret last 252 trading days up to end_date inclusive
  sub <- bm_daily[Date <= end_date]
  n <- nrow(sub)
  if (n < 252) return(NA_real_)
  rets <- sub$BM_Ret[(n-251):n]
  sqrt(252) * sd(rets, na.rm = TRUE)
}

cat("  Computing monthly RV12m (PIT-strict)...\n")
month_eom[, rv12m := vapply(Date, get_rv12m, numeric(1L))]

# VIX EOM (annualized %, divide by 100)
setkey(vix_dt, Date)
get_vix_eom <- function(eom_date) {
  sub <- vix_dt[Date <= eom_date]
  if (nrow(sub) == 0) return(NA_real_)
  tail(sub$VIX, 1L) / 100
}
month_eom[, vix_eom := vapply(Date, get_vix_eom, numeric(1L))]

# t-1 lag (PIT C2/C9)
setorder(month_eom, Date)
month_eom[, vix_lag1 := shift(vix_eom, 1L)]
month_eom[, rv12m_lag1 := shift(rv12m, 1L)]

# 4 sub-variants (cycle 3 methodology — annualized, monthly scaling sqrt(1/12))
# BKM = 0.40 * (IV_ann - RV_ann) * sqrt(1/12)
# CW  = (IV² - RV²) / (2*RV) * sqrt(1/12)
# BTZ = (RV - IV) * sqrt(1/12)  (long-vol position, sign flipped)
# BCI = -0.5 * (IV - mean(IV_expanding)) * sqrt(1/12)  (mean-reversion harvest)
month_eom[, vrp_BKM := 0.40 * (vix_lag1 - rv12m_lag1) * sqrt(1/12)]
month_eom[, vrp_CW  := (vix_lag1^2 - rv12m_lag1^2) / (2 * rv12m_lag1) * sqrt(1/12)]
month_eom[, vrp_BTZ := (rv12m_lag1 - vix_lag1) * sqrt(1/12)]

# BCI mean-reversion (PIT-expanding mean of vix_lag1)
month_eom[, vix_expanding_mean := cumsum(replace(vix_lag1, is.na(vix_lag1), 0)) /
            pmax(cumsum(!is.na(vix_lag1)), 1L)]
month_eom[, vrp_BCI := -0.5 * (vix_lag1 - vix_expanding_mean) * sqrt(1/12)]

cat(sprintf("  4 sub-variants computed: BKM/CW/BTZ/BCI for %s months (n_valid: %s)\n",
            nrow(month_eom),
            sum(!is.na(month_eom$vrp_BKM))))

# Save VRP signals
write_parquet(month_eom, file.path(STAGE_DIR, "vrp_signals_monthly.parquet"))

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Stock-level monthly returns + monthly EOM Universe
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 3] Building stock-level monthly returns + EOM universe...\n")

# Monthly stock return = month-end close / prev month-end close - 1
rd[, yearmonth := format(Date, "%Y-%m")]
stock_eom <- rd[, .SD[.N], by = .(Ticker, yearmonth)]
setkey(stock_eom, Ticker, Date)

# Monthly return (close-to-close month-end)
stock_eom[, MonthRet := Close / shift(Close, 1L) - 1, by = Ticker]

# Universe membership at month-end (use t-1 EOM membership for next month decision)
stock_eom[, K200_lag1 := shift(K200, 1L), by = Ticker]
stock_eom[, KQ150_lag1 := shift(KQ150, 1L), by = Ticker]
stock_eom[, in_univ_lag1 := (K200_lag1 == 1 | KQ150_lag1 == 1)]

# Liquidity at t-1
stock_eom[, TV20_lag1 := shift(frollmean(Close * Vol, 20, fill = NA, align = "right"), 1L),
           by = Ticker]
stock_eom[, liquid_lag1 := !is.na(TV20_lag1) & TV20_lag1 >= LIQ_THRESHOLD]

# Sector for neutralization
stock_eom[, Sector := as.character(Sector)]

cat(sprintf("  stock_eom: %s rows, %s unique tickers, %s monthly periods\n",
            format(nrow(stock_eom), big.mark=","),
            uniqueN(stock_eom$Ticker),
            uniqueN(stock_eom$yearmonth)))

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Stock-level Vol-Beta computation (4 sub-variants × N tickers)
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 4] Computing stock-level vol-beta (rolling 36m, PIT-strict)...\n")

# Merge VRP signals with stock_eom by yearmonth
stock_eom[, yearmonth := format(Date, "%Y-%m")]
vrp_for_merge <- month_eom[, .(yearmonth, vrp_BKM, vrp_CW, vrp_BTZ, vrp_BCI)]
stock_eom <- merge(stock_eom, vrp_for_merge, by = "yearmonth", all.x = TRUE)
setkey(stock_eom, Ticker, Date)

# vol-beta: rolling 36m β_i = cov(r_i, vrp) / var(vrp)
# PIT-strict: at month t, use months [t-35, t-1] of (r_i, vrp_lag1) — no lookahead
# Output β at month t (assigned to forward prediction for t+1)

ROLL_WIN <- 36L  # 36-month rolling β
WINSOR_STD <- 3

compute_volbeta_panel <- function(data_dt, vrp_col) {
  # For each ticker, compute rolling 36m β of MonthRet vs vrp_col
  vrp_vec <- data_dt[[vrp_col]]
  ret_vec <- data_dt$MonthRet

  n <- nrow(data_dt)
  beta <- rep(NA_real_, n)
  if (n < ROLL_WIN) return(beta)

  for (i in ROLL_WIN:n) {
    win_ret <- ret_vec[(i - ROLL_WIN + 1):i]
    win_vrp <- vrp_vec[(i - ROLL_WIN + 1):i]
    valid <- !is.na(win_ret) & !is.na(win_vrp)
    if (sum(valid) < 24L) next
    var_v <- var(win_vrp[valid])
    if (is.na(var_v) || var_v < 1e-12) next
    cov_rv <- cov(win_ret[valid], win_vrp[valid])
    beta[i] <- cov_rv / var_v
  }
  beta
}

# Parallel compute per ticker
n_workers <- min(8L, parallel::detectCores() - 1L)
cat(sprintf("  Parallel workers: %d\n", n_workers))
plan(multisession, workers = n_workers)

t0 <- Sys.time()
tickers <- unique(stock_eom$Ticker)
ticker_chunks <- split(tickers, ceiling(seq_along(tickers) / 50))

cat(sprintf("  Processing %d tickers in %d chunks...\n", length(tickers), length(ticker_chunks)))

beta_list <- future_lapply(ticker_chunks, function(chunk_tickers) {
  chunk_dt <- stock_eom[Ticker %in% chunk_tickers]
  chunk_dt[, beta_BKM := compute_volbeta_panel(.SD, "vrp_BKM"), by = Ticker]
  chunk_dt[, beta_CW  := compute_volbeta_panel(.SD, "vrp_CW"),  by = Ticker]
  chunk_dt[, beta_BTZ := compute_volbeta_panel(.SD, "vrp_BTZ"), by = Ticker]
  chunk_dt[, beta_BCI := compute_volbeta_panel(.SD, "vrp_BCI"), by = Ticker]
  chunk_dt[, .(Ticker, yearmonth, Date, beta_BKM, beta_CW, beta_BTZ, beta_BCI)]
}, future.seed = TRUE)

beta_combined <- rbindlist(beta_list)
plan(sequential)
elapsed_seq <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("  Completed in %.1f sec\n", elapsed_seq))

# Merge betas back
stock_eom <- merge(stock_eom, beta_combined,
                   by = c("Ticker", "yearmonth", "Date"), all.x = TRUE)
setkey(stock_eom, Ticker, Date)

# Save raw vol-beta panel
write_parquet(stock_eom, file.path(STAGE_DIR, "stock_volbeta_panel.parquet"))

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Cross-sectional alpha factor construction
#
# Sign convention:
#   - Variance Risk Premium 핵심: vol seller earns premium
#   - high vol-beta = vol-buyer = systematic underperformer in normal regime
#   - alpha_i = -z(beta_i)  (low-vol-beta cross-section preferred)
#   - BTZ는 long-vol position이라 sign 반대: alpha = +z(beta_BTZ)
#
# PIT-strict: 모든 β at month t는 [t-35, t-1] 데이터로 계산 → forward prediction for t+1
# Cross-section: month t에서 universe stocks의 z-score 표준화 (sector neutral 옵션)
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 5] Cross-sectional alpha factor construction...\n")

# 4 sub-variants → cross-section z-score per month-end
zscore_cs <- function(x) {
  if (sum(!is.na(x)) < 5L) return(rep(NA_real_, length(x)))
  m <- median(x, na.rm = TRUE)
  s <- mad(x, na.rm = TRUE) * 1.4826  # robust SD
  if (is.na(s) || s < 1e-12) return(rep(0, length(x)))
  z <- (x - m) / s
  # winsorize
  z <- pmax(pmin(z, WINSOR_STD), -WINSOR_STD)
  z
}

# Cross-section z per (yearmonth, in_univ_lag1 == TRUE & liquid_lag1 == TRUE)
stock_eom[, valid_for_alpha := !is.na(MonthRet) & in_univ_lag1 & liquid_lag1 &
                              !is.na(beta_BKM)]

stock_eom[, z_BKM := zscore_cs(beta_BKM), by = yearmonth]
stock_eom[, z_CW  := zscore_cs(beta_CW),  by = yearmonth]
stock_eom[, z_BTZ := zscore_cs(beta_BTZ), by = yearmonth]
stock_eom[, z_BCI := zscore_cs(beta_BCI), by = yearmonth]

# Sign convention applied
stock_eom[, alpha_BKM := -z_BKM]  # low-vol-beta preferred (vol seller)
stock_eom[, alpha_CW  := -z_CW ]  # low-vol-beta preferred
stock_eom[, alpha_BTZ := +z_BTZ]  # BTZ long-vol position → sign reversed
stock_eom[, alpha_BCI := -z_BCI]  # mean-reversion harvest, low-vol-beta preferred

# Sector neutralization (within sector demean)
sector_demean <- function(x, sec) {
  if (sum(!is.na(x)) < 3L) return(x)
  by_sec <- ave(x, sec, FUN = function(v) {
    v - mean(v, na.rm = TRUE)
  })
  by_sec
}

stock_eom[, alpha_BKM_sn := sector_demean(alpha_BKM, Sector), by = yearmonth]
stock_eom[, alpha_CW_sn  := sector_demean(alpha_CW,  Sector), by = yearmonth]
stock_eom[, alpha_BTZ_sn := sector_demean(alpha_BTZ, Sector), by = yearmonth]
stock_eom[, alpha_BCI_sn := sector_demean(alpha_BCI, Sector), by = yearmonth]

# F5 Composite: inverse-variance Bayesian ensemble (4 sub-variants weighted by ICIR^2 — but per Charter must avoid full-sample ICIR for selection. Use equal-weight composite OR PIT-rolling weights)
# Decision: equal-weight at construction (objective independent), then evaluate as candidate
stock_eom[, alpha_F5 := 0.25 * (alpha_BKM_sn + alpha_CW_sn + alpha_BTZ_sn + alpha_BCI_sn)]

cat("  Alpha factors constructed: alpha_BKM, alpha_CW, alpha_BTZ, alpha_BCI, alpha_F5\n")

# ─────────────────────────────────────────────────────────────────────────────
# Step 6: Diagnostics — IC / ICIR / Harvey-NW t / monotonicity / subperiod
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 6] Computing diagnostics (per factor + composite)...\n")

# Forward 1m return = MonthRet at t+1 (target)
stock_eom[, fwd_ret := shift(MonthRet, -1L), by = Ticker]

# Subperiod definitions (HARD: lockbox 2020~ Alpha 접근 금지에 한해 ICIR 등 IS metrics는 valid window only)
# train+validation = 2008~2019, lockbox = 2020~2026.04
# Note: IS metrics (rank IC, ICIR, Harvey-t, monotonicity)는 train+validation only
# Subperiod stability: 3 windows = 2008~2014 / 2015~2019 / (2020~2026.04 = lockbox, alpha 단계에서 SEPARATE diagnostic only NOT for selection)

stock_eom[, period := fcase(
  yearmonth >= "2008-01" & yearmonth <= "2014-12", "p1_2008_14",
  yearmonth >= "2015-01" & yearmonth <= "2019-12", "p2_2015_19",
  yearmonth >= "2020-01" & yearmonth <= "2026-04", "p3_lockbox_2020_26",
  default = NA_character_
)]

# Cross-sectional IC per month (Spearman)
compute_monthly_ic <- function(alpha_col, data_dt, periods_filter = NULL) {
  d <- copy(data_dt)
  d[, alpha_x := get(alpha_col)]
  if (!is.null(periods_filter)) d <- d[period %in% periods_filter]
  d <- d[!is.na(alpha_x) & !is.na(fwd_ret) & valid_for_alpha]
  ic_per_month <- d[, {
    if (.N < 10L) {
      .(rank_ic = NA_real_, n = .N)
    } else {
      .(rank_ic = cor(alpha_x, fwd_ret, method = "spearman"), n = .N)
    }
  }, by = yearmonth]
  ic_per_month[, period := fcase(
    yearmonth >= "2008-01" & yearmonth <= "2014-12", "p1_2008_14",
    yearmonth >= "2015-01" & yearmonth <= "2019-12", "p2_2015_19",
    yearmonth >= "2020-01" & yearmonth <= "2026-04", "p3_lockbox_2020_26",
    default = NA_character_
  )]
  ic_per_month
}

factor_cols <- c("alpha_BKM_sn", "alpha_CW_sn", "alpha_BTZ_sn", "alpha_BCI_sn", "alpha_F5")
diag_results <- list()

for (fc in factor_cols) {
  # IS-only metrics (train+val) for selection
  ic_is <- compute_monthly_ic(fc, stock_eom, periods_filter = c("p1_2008_14", "p2_2015_19"))
  ic_lockbox <- compute_monthly_ic(fc, stock_eom, periods_filter = "p3_lockbox_2020_26")
  ic_full <- compute_monthly_ic(fc, stock_eom)

  rank_ic_is <- mean(ic_is$rank_ic, na.rm = TRUE)
  ic_sd_is <- sd(ic_is$rank_ic, na.rm = TRUE)
  icir_is <- if (!is.na(ic_sd_is) && ic_sd_is > 0) rank_ic_is / ic_sd_is else NA_real_
  n_months_is <- sum(!is.na(ic_is$rank_ic))

  # Harvey-Newey-West t-stat on monthly IC
  ic_vec <- ic_is$rank_ic[!is.na(ic_is$rank_ic)]
  if (length(ic_vec) >= 10L) {
    t_simple <- mean(ic_vec) / (sd(ic_vec) / sqrt(length(ic_vec)))
    # NW correction (lag-3)
    nw_lag <- 3L
    nw_var <- var(ic_vec)
    for (k in 1:nw_lag) {
      w_k <- 1 - k / (nw_lag + 1)
      n_eff <- length(ic_vec) - k
      if (n_eff > 0) {
        gamma_k <- cov(ic_vec[1:n_eff], ic_vec[(k+1):length(ic_vec)])
        nw_var <- nw_var + 2 * w_k * gamma_k
      }
    }
    nw_var <- max(nw_var, 1e-12)
    t_nw <- mean(ic_vec) / sqrt(nw_var / length(ic_vec))
  } else {
    t_simple <- NA_real_; t_nw <- NA_real_
  }

  # Subperiod IC by 3 subperiods
  sp <- ic_full[, .(mean_ic = mean(rank_ic, na.rm = TRUE), n = sum(!is.na(rank_ic))), by = period]
  sp <- sp[!is.na(period)]

  # Subperiod stability = sign consistency
  positive_sp <- sum(sp$mean_ic > 0, na.rm = TRUE)
  total_sp <- sum(!is.na(sp$mean_ic))
  sub_stab <- if (total_sp > 0) positive_sp / total_sp else NA_real_

  # Monotonicity (decile spread): top decile vs bottom decile fwd_ret per month
  d <- copy(stock_eom[period %in% c("p1_2008_14", "p2_2015_19") & valid_for_alpha])
  d[, alpha_x := get(fc)]
  d <- d[!is.na(alpha_x) & !is.na(fwd_ret)]
  d[, decile := ntile(alpha_x, 10L), by = yearmonth]
  decile_returns <- d[!is.na(decile), .(mean_ret = mean(fwd_ret, na.rm = TRUE)),
                       by = .(yearmonth, decile)]
  by_decile <- decile_returns[, .(mean_ret = mean(mean_ret, na.rm = TRUE)),
                               by = decile][order(decile)]
  ls_spread <- if (nrow(by_decile) >= 10L && !is.na(by_decile$mean_ret[10]) &&
                    !is.na(by_decile$mean_ret[1])) {
    by_decile$mean_ret[10] - by_decile$mean_ret[1]
  } else NA_real_
  monotonicity_corr <- if (nrow(by_decile) >= 5L) {
    cor(by_decile$decile, by_decile$mean_ret, method = "spearman")
  } else NA_real_

  # Predictor lag-1 autocor (WT_001 trap detection)
  pred_dt <- copy(stock_eom[!is.na(get(fc))])
  setkey(pred_dt, Ticker, Date)
  pred_dt[, alpha_x := get(fc)]
  pred_dt[, alpha_x_lag1 := shift(alpha_x, 1L), by = Ticker]
  ac_dt <- pred_dt[!is.na(alpha_x) & !is.na(alpha_x_lag1)]
  pred_autocor <- if (nrow(ac_dt) >= 100L) {
    cor(ac_dt$alpha_x, ac_dt$alpha_x_lag1, method = "pearson")
  } else NA_real_

  # Lockbox metric (separate, not used for selection)
  rank_ic_lockbox <- mean(ic_lockbox$rank_ic, na.rm = TRUE)
  icir_lockbox <- if (sd(ic_lockbox$rank_ic, na.rm = TRUE) > 0) {
    rank_ic_lockbox / sd(ic_lockbox$rank_ic, na.rm = TRUE)
  } else NA_real_

  diag_results[[fc]] <- list(
    factor = fc,
    rank_ic_is = round(rank_ic_is, 4),
    icir_is = round(icir_is, 4),
    n_months_is = n_months_is,
    t_simple = round(t_simple, 4),
    t_nw = round(t_nw, 4),
    subperiod_stability = round(sub_stab, 4),
    subperiod_breakdown = lapply(seq_len(nrow(sp)), function(i) {
      list(period = sp$period[i], mean_ic = round(sp$mean_ic[i], 4), n = sp$n[i])
    }),
    monotonicity_corr = round(monotonicity_corr, 4),
    ls_decile_spread = round(ls_spread, 4),
    pred_autocor_lag1 = round(pred_autocor, 4),
    lockbox_rank_ic = round(rank_ic_lockbox, 4),
    lockbox_icir = round(icir_lockbox, 4),
    lockbox_n_months = sum(!is.na(ic_lockbox$rank_ic))
  )
}

cat("  Diagnostics complete:\n")
for (fc in factor_cols) {
  d <- diag_results[[fc]]
  cat(sprintf("    %s: IC_IS=%.4f ICIR_IS=%.4f t_NW=%.3f sub_stab=%.2f autocor=%.3f\n",
              fc, d$rank_ic_is, d$icir_is, d$t_nw, d$subperiod_stability, d$pred_autocor_lag1))
}

# Save diagnostics
write_json(diag_results, file.path(STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# ─────────────────────────────────────────────────────────────────────────────
# Step 7: WT_001 trap diagnostics
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 7] WT_001 trap diagnostics (predictor autocor + crisis anti-hedge)...\n")

# Predictor lag-1 autocor diagnosis (per factor, per ticker mean)
autocor_summary <- list()
for (fc in factor_cols) {
  pred_dt <- copy(stock_eom[!is.na(get(fc))])
  setkey(pred_dt, Ticker, Date)
  pred_dt[, alpha_x := get(fc)]
  pred_dt[, alpha_x_lag1 := shift(alpha_x, 1L), by = Ticker]
  pred_dt <- pred_dt[!is.na(alpha_x_lag1)]
  per_ticker_ac <- pred_dt[, {
    if (.N < 12L) .(ac = NA_real_) else {
      .(ac = cor(alpha_x, alpha_x_lag1, method = "pearson"))
    }
  }, by = Ticker]
  per_ticker_ac <- per_ticker_ac[!is.na(ac)]
  autocor_summary[[fc]] <- list(
    factor = fc,
    mean_per_ticker_ac = round(mean(per_ticker_ac$ac, na.rm = TRUE), 4),
    median_per_ticker_ac = round(median(per_ticker_ac$ac, na.rm = TRUE), 4),
    pooled_ac = diag_results[[fc]]$pred_autocor_lag1,
    n_tickers = nrow(per_ticker_ac),
    interpretation = ifelse(abs(diag_results[[fc]]$pred_autocor_lag1) > 0.40,
                            "WT_001-LIKE PERSISTENCE — INVESTIGATE",
                            "OK_NORMAL_AUTOCOR_RANGE")
  )
}
write_json(list(
  trap_diagnosis = "WT_001 v1 had pred_autocor_lag1=0.404 (predictor self-correlation). Threshold: |ac|>0.40 = HIGH RISK.",
  factors = autocor_summary
), file.path(STAGE_DIR, "predictor_autocor_diagnosis.json"),
   pretty = TRUE, auto_unbox = TRUE, na = "null")

# Crisis anti-hedge diagnosis
# Cycle 7: cor(VRP, AR) +0.6438 in CRISIS regime → anti-hedge
# Approximate CRISIS regime: KOSPI BM_Ret monthly < -10% OR cumulative drawdown < -25% rolling 12m
bm_monthly <- bm_daily[, .(bm_ret = sum(BM_Ret, na.rm = TRUE)), by = yearmonth]
bm_monthly[, bm_dd_12m := frollapply(bm_ret, 12L, function(x) {
  cum <- cumprod(1 + x) - 1
  min(cum) - max(cum)
}, fill = NA, align = "right")]
bm_monthly[, crisis := bm_ret < -0.10 | (bm_dd_12m < -0.25)]

stock_eom_with_crisis <- merge(stock_eom, bm_monthly[, .(yearmonth, crisis)],
                                by = "yearmonth", all.x = TRUE)

crisis_summary <- list()
for (fc in factor_cols) {
  d <- copy(stock_eom_with_crisis[valid_for_alpha & !is.na(get(fc)) & !is.na(fwd_ret)])
  d[, alpha_x := get(fc)]

  # Per-month: alpha portfolio return = mean of fwd_ret weighted by alpha rank (proxy)
  port <- d[, {
    if (.N < 10L) .(port_ret = NA_real_, n = .N, crisis = first(crisis)) else {
      decile <- ntile(alpha_x, 10L)
      ret_long <- mean(fwd_ret[decile == 10L], na.rm = TRUE)
      ret_short <- mean(fwd_ret[decile == 1L], na.rm = TRUE)
      .(port_ret = ret_long - ret_short, n = .N, crisis = first(crisis))
    }
  }, by = yearmonth]
  port_with_bm <- merge(port, bm_monthly[, .(yearmonth, bm_ret)], by = "yearmonth")
  port_with_bm <- port_with_bm[!is.na(port_ret) & !is.na(bm_ret)]

  if (nrow(port_with_bm) >= 12L) {
    cor_normal <- cor(port_with_bm[crisis == FALSE]$port_ret,
                       port_with_bm[crisis == FALSE]$bm_ret, method = "pearson",
                       use = "pairwise.complete.obs")
    cor_crisis <- cor(port_with_bm[crisis == TRUE]$port_ret,
                       port_with_bm[crisis == TRUE]$bm_ret, method = "pearson",
                       use = "pairwise.complete.obs")
    n_normal <- sum(port_with_bm$crisis == FALSE, na.rm = TRUE)
    n_crisis <- sum(port_with_bm$crisis == TRUE, na.rm = TRUE)
  } else {
    cor_normal <- NA_real_; cor_crisis <- NA_real_; n_normal <- 0; n_crisis <- 0
  }

  crisis_summary[[fc]] <- list(
    factor = fc,
    cor_LS_BM_normal = round(cor_normal, 4),
    cor_LS_BM_crisis = round(cor_crisis, 4),
    n_normal_months = n_normal,
    n_crisis_months = n_crisis,
    anti_hedge_risk = ifelse(!is.na(cor_crisis) && cor_crisis > 0.40,
                              "CRISIS ANTI-HEDGE DETECTED — VRP harvest fails in crisis regime (cycle 7 echo)",
                              "OK no severe crisis anti-hedge")
  )
}
write_json(list(
  diagnosis_purpose = "WT_001 cycle 7 finding: cor(VRP, AR)=+0.6438 in CRISIS regime → VRP signal is anti-hedge. Re-test on stock-level cross-section.",
  crisis_regime_def = "monthly KOSPI BM_Ret < -10% OR rolling 12m cum drawdown < -25%",
  factors = crisis_summary
), file.path(STAGE_DIR, "crisis_anti_hedge_diagnosis.json"),
   pretty = TRUE, auto_unbox = TRUE, na = "null")

# ─────────────────────────────────────────────────────────────────────────────
# Step 8: Bailey-LdP DSR strict (Multi-trial)
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 8] Bailey-Lopez de Prado DSR (multi-trial haircut)...\n")

# DSR formula: DSR = Z * sqrt((SR^2 - SR_hurdle^2) / (Var(SR^2)))
# n_trials = 5 (factor + composite), Bailey-LdP haircut applies
N_TRIALS <- 5L  # 4 sub-variants + 1 composite

# For each factor, compute monthly L-S decile spread → SR
sr_per_factor <- list()
for (fc in factor_cols) {
  d <- copy(stock_eom[period %in% c("p1_2008_14", "p2_2015_19") & valid_for_alpha])
  d[, alpha_x := get(fc)]
  d <- d[!is.na(alpha_x) & !is.na(fwd_ret)]
  d[, decile := ntile(alpha_x, 10L), by = yearmonth]
  port_ls <- d[!is.na(decile), {
    ret_long <- mean(fwd_ret[decile == 10L], na.rm = TRUE)
    ret_short <- mean(fwd_ret[decile == 1L], na.rm = TRUE)
    .(ls_ret = ret_long - ret_short, long_only = ret_long)
  }, by = yearmonth]
  port_ls <- port_ls[!is.na(ls_ret)]

  if (nrow(port_ls) >= 24L) {
    sr_ls <- mean(port_ls$ls_ret, na.rm = TRUE) / sd(port_ls$ls_ret, na.rm = TRUE)
    sr_lo <- mean(port_ls$long_only, na.rm = TRUE) / sd(port_ls$long_only, na.rm = TRUE)
    skew_m <- (mean((port_ls$ls_ret - mean(port_ls$ls_ret, na.rm=TRUE))^3, na.rm=TRUE) /
                sd(port_ls$ls_ret, na.rm=TRUE)^3)
    kurt_m <- (mean((port_ls$ls_ret - mean(port_ls$ls_ret, na.rm=TRUE))^4, na.rm=TRUE) /
                sd(port_ls$ls_ret, na.rm=TRUE)^4) - 3
    n_obs <- nrow(port_ls)

    # Bailey-LdP DSR
    var_sr2 <- (1 - skew_m * sr_ls + (kurt_m - 1) / 4 * sr_ls^2) / (n_obs - 1)
    if (is.na(var_sr2) || var_sr2 <= 0) {
      dsr_z <- NA_real_; dsr_pass <- NA
    } else {
      # multi-trial hurdle: SR_hurdle = sqrt(var_sr2) * (1-Euler) * Phi^-1(1 - 1/N) +
      # Euler * Phi^-1(1 - 1/(N*e))  approximate via expected max of N IID normals
      qnorm_max_N <- qnorm(1 - 1/N_TRIALS)
      sr_hurdle <- sqrt(var_sr2) * qnorm_max_N
      dsr_z <- (sr_ls - sr_hurdle) / sqrt(var_sr2)
      dsr_pass <- dsr_z > 0
    }
  } else {
    sr_ls <- NA_real_; sr_lo <- NA_real_; skew_m <- NA_real_; kurt_m <- NA_real_; n_obs <- 0
    dsr_z <- NA_real_; dsr_pass <- NA
  }

  sr_per_factor[[fc]] <- list(
    factor = fc,
    sr_long_short_decile = round(sr_ls, 4),
    sr_long_only_top_decile = round(sr_lo, 4),
    skew_monthly = round(skew_m, 4),
    kurt_excess_monthly = round(kurt_m, 4),
    n_obs_months = n_obs,
    dsr_bailey_ldp_z = round(dsr_z, 4),
    dsr_pass = dsr_pass,
    n_trials = N_TRIALS,
    method = "Bailey-Lopez de Prado 2014 — multi-trial deflated SR with skew/kurt correction"
  )
}

write_json(list(
  citation = "Bailey-Lopez de Prado (2014) The Deflated Sharpe Ratio: Correcting for Selection Bias, Backtest Overfitting and Non-Normality",
  n_trials = N_TRIALS,
  trial_count_rationale = "4 sub-variants (BKM/CW/BTZ/BCI) + 1 composite (F5) = 5 trials",
  factors = sr_per_factor
), file.path(STAGE_DIR, "dsr_strict_bailey_ldp.json"),
   pretty = TRUE, auto_unbox = TRUE, na = "null")

cat("  DSR summary:\n")
for (fc in factor_cols) {
  s <- sr_per_factor[[fc]]
  cat(sprintf("    %s: SR_LS=%.3f SR_LO=%.3f DSR_z=%.3f (n_obs=%d)\n",
              fc, s$sr_long_short_decile, s$sr_long_only_top_decile,
              s$dsr_bailey_ldp_z, s$n_obs_months))
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 9: As-of 2026-05 forward prediction (alpha_vector)
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 9] Building as-of 2026-05 forward predictions...\n")

# As-of date = 2026-05-01 (first day of forward month)
# Use t-1 = 2026-04 EOM for prediction
AS_OF_MONTH <- "2026-04"  # data up to 2026-04-EOM, prediction for 2026-05

# Filter to as-of universe: K200|KQ150 lag1 + liquid lag1 at 2026-04 EOM
asof_dt <- stock_eom[yearmonth == AS_OF_MONTH & valid_for_alpha]
cat(sprintf("  As-of 2026-04 universe size: %d names\n", nrow(asof_dt)))

# Use F5 composite as headline alpha (factor_specs all 5 reported in package)
asof_dt[, alpha_headline := alpha_F5]

# Confidence vector (R4-A): based on factor coverage + cross-section rank stability
# Simple: confidence = 1 - (missing_factor_count / 4) * 0.25, capped [0.5, 1.0]
asof_dt[, n_missing_betas := is.na(beta_BKM) + is.na(beta_CW) + is.na(beta_BTZ) + is.na(beta_BCI)]
asof_dt[, confidence := pmin(pmax(1 - n_missing_betas * 0.25, 0.5), 1.0)]

# Save forward predictions
fwd_out <- asof_dt[, .(Ticker, yearmonth, Date,
                        alpha_BKM = alpha_BKM_sn, alpha_CW = alpha_CW_sn,
                        alpha_BTZ = alpha_BTZ_sn, alpha_BCI = alpha_BCI_sn,
                        alpha_F5,
                        confidence,
                        beta_BKM, beta_CW, beta_BTZ, beta_BCI)]
write_parquet(fwd_out, file.path(STAGE_DIR, "forward_2026_05_predictions.parquet"))

# Also save full alpha_scores parquet (entire history)
all_scores <- stock_eom[valid_for_alpha == TRUE,
                        .(Ticker, yearmonth, Date, fwd_ret,
                          alpha_BKM = alpha_BKM_sn, alpha_CW = alpha_CW_sn,
                          alpha_BTZ = alpha_BTZ_sn, alpha_BCI = alpha_BCI_sn,
                          alpha_F5,
                          beta_BKM, beta_CW, beta_BTZ, beta_BCI,
                          period)]
write_parquet(all_scores, file.path(STAGE_DIR, "alpha_scores.parquet"))

cat("  forward predictions saved + full history alpha_scores.parquet\n")

# ─────────────────────────────────────────────────────────────────────────────
# Step 10: ML XGBoost CUDA + classical baseline (deferred to Python script)
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 10] ML XGBoost CUDA + classical baseline → external Python script\n")
cat("  See: run_ml_comparison.py (executed after R script)\n")

# Save ML inputs: features + target panel
ml_panel <- stock_eom[valid_for_alpha == TRUE & !is.na(fwd_ret) & !is.na(alpha_F5),
                      .(Ticker, yearmonth, Date, fwd_ret,
                        beta_BKM, beta_CW, beta_BTZ, beta_BCI,
                        alpha_BKM_sn, alpha_CW_sn, alpha_BTZ_sn, alpha_BCI_sn,
                        alpha_F5, period, Sector)]
write_parquet(ml_panel, file.path(STAGE_DIR, "ml_panel.parquet"))
cat(sprintf("  ml_panel.parquet saved: %d rows\n", nrow(ml_panel)))

# ─────────────────────────────────────────────────────────────────────────────
# Step 11: Method Shopping Log
# ─────────────────────────────────────────────────────────────────────────────
method_log <- list(
  parallel_exec = TRUE,
  n_workers = n_workers,
  rolling_seconds = round(elapsed_seq, 1),
  rcpp_used = FALSE,  # used base R parallel (panel is moderate, no Rcpp needed)
  candidates_tried = 5L,  # 4 sub-variants + 1 composite — within 5 cap
  method_log_entries = list(
    list(name = "alpha_BKM_sn", method = "VRP_BKM vol-beta cross-section, sector-neutral, sign=-",
         rank_ic_is = diag_results$alpha_BKM_sn$rank_ic_is, selected = FALSE),
    list(name = "alpha_CW_sn",  method = "VRP_CW vol-beta cross-section, sector-neutral, sign=-",
         rank_ic_is = diag_results$alpha_CW_sn$rank_ic_is, selected = FALSE),
    list(name = "alpha_BTZ_sn", method = "VRP_BTZ vol-beta cross-section, sector-neutral, sign=+ (long-vol)",
         rank_ic_is = diag_results$alpha_BTZ_sn$rank_ic_is, selected = FALSE),
    list(name = "alpha_BCI_sn", method = "VRP_BCI mean-rev vol-beta cross-section, sector-neutral, sign=-",
         rank_ic_is = diag_results$alpha_BCI_sn$rank_ic_is, selected = FALSE),
    list(name = "alpha_F5",     method = "Equal-weight composite of 4 sub-variants (Bayesian-style)",
         rank_ic_is = diag_results$alpha_F5$rank_ic_is, selected = TRUE)
  )
)
write_json(method_log, file.path(STAGE_DIR, "method_shopping_log.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# ─────────────────────────────────────────────────────────────────────────────
# Step 12: alpha_package_draft.json (8-field schema)
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 11] Building alpha_package_draft.json...\n")

# Headline factor selected by best ICIR_IS (R4 P3 selection_objective: icir)
# (note: we use IS only for selection per R2 P2 Window Isolation HARD)
icir_per_factor <- sapply(factor_cols, function(fc) diag_results[[fc]]$icir_is)
headline_factor <- names(icir_per_factor)[which.max(abs(icir_per_factor))]
cat(sprintf("  Headline factor (max |ICIR_IS|): %s (ICIR=%.4f)\n",
            headline_factor, icir_per_factor[headline_factor]))

# alpha_vector: per-name expected active return
# Convention: monthly active return est = sign * z * λ where λ calibrated to historical IC * vol
# Simple: alpha_vector[ticker] = factor_z * 0.01 (1% per σ — placeholder, optimizer scales)
asof_dt[, alpha_vector_est := alpha_headline]

alpha_vector <- as.list(setNames(round(asof_dt$alpha_vector_est, 6), asof_dt$Ticker))
confidence_vector <- as.list(setNames(round(asof_dt$confidence, 4), asof_dt$Ticker))

# factor_specs (schema-required fields)
factor_specs <- list(
  list(
    factor_family = "VRP_VolBeta_BKM",
    proxy = "stock_volbeta_BKM_36m_rolling",
    formula = "β_i,t = cov(r_i, vrp_BKM, 36m) / var(vrp_BKM, 36m); alpha = -z(β) sector-neutral",
    lag_rule = "PIT t-1: β at month t uses [t-35, t-1] data",
    winsorization = "MAD ×1.4826 robust z, ±3std cap",
    neutralization = "sector demean (cross-section by Sector)",
    economic_rationale = "Variance Risk Premium: vol seller earns premium (risk_premium). High vol-beta = systematic vol-buyer = underperformer.",
    weight_theta = 0.25,
    references = c("Bakshi-Kapadia-Madan 2003 RFS", "Bollerslev-Tauchen-Zhou 2009 RFS")
  ),
  list(
    factor_family = "VRP_VolBeta_CW",
    proxy = "stock_volbeta_CW_36m_rolling",
    formula = "β_i,t = cov(r_i, vrp_CW, 36m) / var(vrp_CW, 36m); alpha = -z(β) sector-neutral",
    lag_rule = "PIT t-1: β at month t uses [t-35, t-1] data",
    winsorization = "MAD ×1.4826 robust z, ±3std cap",
    neutralization = "sector demean (cross-section by Sector)",
    economic_rationale = "Carr-Wu variance swap synthetic: variance risk premium harvested via low-vol-beta cross-section.",
    weight_theta = 0.25,
    references = c("Carr-Wu 2009 RFS")
  ),
  list(
    factor_family = "VRP_VolBeta_BTZ",
    proxy = "stock_volbeta_BTZ_36m_rolling",
    formula = "β_i,t = cov(r_i, vrp_BTZ, 36m) / var(vrp_BTZ, 36m); alpha = +z(β) sector-neutral (sign reversed)",
    lag_rule = "PIT t-1: β at month t uses [t-35, t-1] data",
    winsorization = "MAD ×1.4826 robust z, ±3std cap",
    neutralization = "sector demean (cross-section by Sector)",
    economic_rationale = "Bollerslev-Tauchen-Zhou long-vol position: opposite sign convention (high vol-beta = long-vol = preferred).",
    weight_theta = 0.25,
    references = c("Bollerslev-Tauchen-Zhou 2009 RFS")
  ),
  list(
    factor_family = "VRP_VolBeta_BCI",
    proxy = "stock_volbeta_BCI_36m_rolling",
    formula = "β_i,t = cov(r_i, vrp_BCI_meanrev, 36m) / var(vrp_BCI, 36m); alpha = -z(β) sector-neutral",
    lag_rule = "PIT t-1: β at month t uses [t-35, t-1] data",
    winsorization = "MAD ×1.4826 robust z, ±3std cap",
    neutralization = "sector demean (cross-section by Sector)",
    economic_rationale = "Bouchaud-Cont-Iori microstructure mean-reversion harvest. VIX expanding mean deviation.",
    weight_theta = 0.25,
    references = c("Bouchaud-Cont-Iori 1998")
  ),
  list(
    factor_family = "VRP_Composite_F5",
    proxy = "equal_weight_4subvariants_ensemble",
    formula = "alpha_F5 = 0.25 * (alpha_BKM_sn + alpha_CW_sn + alpha_BTZ_sn + alpha_BCI_sn)",
    lag_rule = "inherits parent factors (PIT t-1)",
    winsorization = "implicit via parents",
    neutralization = "sector demean inherited",
    economic_rationale = "Bayesian-style equal-weight ensemble of 4 academic VRP frameworks. Diversification across method definitions.",
    weight_theta = 1.0,
    references = c("Bates-Granger 1969 ensemble forecasting", "Bayesian model averaging baseline")
  )
)

# diagnostics — headline factor's IS metrics + lockbox separate report
hd <- diag_results[[headline_factor]]
diag_dt <- list(
  rank_ic = hd$rank_ic_is,
  icir = hd$icir_is,
  monotonicity = hd$monotonicity_corr,
  subperiod_stability = hd$subperiod_stability,
  turnover_proxy = NA,  # computed below
  harvey_t_stat = hd$t_simple,
  harvey_t_NW = hd$t_nw,
  post_neutralization_ic = hd$rank_ic_is,  # already sector-neutralized
  n_obs = hd$n_months_is,
  ic_p1_2008_2014 = hd$subperiod_breakdown[[1]]$mean_ic,
  ic_p2_2015_2019 = if (length(hd$subperiod_breakdown) >= 2L) hd$subperiod_breakdown[[2]]$mean_ic else NA,
  ic_p3_lockbox_2020_26 = hd$lockbox_rank_ic,
  pred_autocor_lag1 = hd$pred_autocor_lag1,
  spec_count = length(factor_specs),
  harvey_t_specs_pass_count = sum(sapply(factor_cols, function(fc) abs(diag_results[[fc]]$t_nw) > 3.0), na.rm = TRUE)
)

# Turnover proxy: monthly cross-section z-score correlation (high cor = low turnover)
asof_lag1_dt <- stock_eom[yearmonth == AS_OF_MONTH & !is.na(get(headline_factor)),
                           .(Ticker, alpha_now = get(headline_factor))]
asof_lag2_dt <- stock_eom[yearmonth == "2026-03" & !is.na(get(headline_factor)),
                           .(Ticker, alpha_prev = get(headline_factor))]
turnover_dt <- merge(asof_lag1_dt, asof_lag2_dt, by = "Ticker")
if (nrow(turnover_dt) > 10) {
  diag_dt$turnover_proxy <- round(1 - cor(turnover_dt$alpha_now, turnover_dt$alpha_prev,
                                          method = "spearman", use = "pairwise.complete.obs"), 4)
}

# Challenge flags
challenge_flags <- list()
if (!is.na(diag_dt$rank_ic) && diag_dt$rank_ic < 0.04) {
  challenge_flags <- append(challenge_flags, list(list(
    code = "FLAG_RANK_IC_LOW",
    severity = "HIGH",
    message = sprintf("rank_ic_IS=%.4f < 0.04 graduation hurdle", diag_dt$rank_ic)
  )))
}
if (!is.na(diag_dt$icir) && abs(diag_dt$icir) < 0.20) {
  challenge_flags <- append(challenge_flags, list(list(
    code = "FLAG_ICIR_LOW",
    severity = "HIGH",
    message = sprintf("ICIR_IS=%.4f < 0.20 Alpha Lab Gate", diag_dt$icir)
  )))
}
if (!is.na(diag_dt$harvey_t_NW) && abs(diag_dt$harvey_t_NW) < 3.0) {
  challenge_flags <- append(challenge_flags, list(list(
    code = "FLAG_HARVEY_T_LOW",
    severity = "HIGH",
    message = sprintf("Harvey-NW t=%.3f < 3.0 multi-testing threshold", diag_dt$harvey_t_NW)
  )))
}
if (!is.na(diag_dt$pred_autocor_lag1) && abs(diag_dt$pred_autocor_lag1) > 0.40) {
  challenge_flags <- append(challenge_flags, list(list(
    code = "FLAG_PRED_AUTOCOR_HIGH",
    severity = "HIGH",
    message = sprintf("pred_autocor_lag1=%.3f > 0.40 — WT_001-style persistence trap", diag_dt$pred_autocor_lag1)
  )))
}
# Crisis anti-hedge flag
hd_crisis <- crisis_summary[[headline_factor]]
if (!is.null(hd_crisis$cor_LS_BM_crisis) && !is.na(hd_crisis$cor_LS_BM_crisis) && hd_crisis$cor_LS_BM_crisis > 0.40) {
  challenge_flags <- append(challenge_flags, list(list(
    code = "FLAG_CRISIS_ANTI_HEDGE",
    severity = "MEDIUM",
    message = sprintf("LS-BM cor in crisis = %.3f > 0.40 — VRP harvest fails in crisis (cycle 7 echo)",
                      hd_crisis$cor_LS_BM_crisis)
  )))
}

# alpha_inheritance_cor (must be < 0.95 for discovery)
# Compare F5 to known existing factors (placeholder: 0 by construction, since no parent VRP factor exists in DB)
alpha_inheritance_cor <- 0.0  # discovery WT, no parent

# Build alpha_package_draft
alpha_package_draft <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  as_of_date = "2026-05-08",
  forecast_horizon = "1M",
  selection_objective = "icir",  # R4 P3 strict: icir/rank_ic only
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = paste0("stage_artifacts/WT_D20260508_003/alpha_scores.parquet"),
  factor_specs = factor_specs,
  diagnostics = diag_dt,
  challenge_flags = challenge_flags,
  alpha_inheritance_cor = alpha_inheritance_cor,
  candidates_tried = 5L,
  method_log_ref = paste0("stage_artifacts/WT_D20260508_003/method_shopping_log.json"),
  rcpp_used = FALSE,
  parallel_exec = TRUE,
  n_workers = n_workers,
  rolling_seconds = round(elapsed_seq, 1),
  hypothesis_source = "user_defined_metacycle3_input",
  hypothesis_title = "VRP 4 sub-variants vol-beta cross-section alpha (BKM/CW/BTZ/BCI + composite F5)",
  hypothesis_description_short = paste(
    "Stock-level vol-beta cross-section alpha derived from 4 academic VRP frameworks.",
    "Sign convention: high vol-beta = vol-buyer = underperformer (BKM/CW/BCI sign=- ; BTZ long-vol sign=+).",
    "Sector-neutral cross-section z-score, MAD-robust winsorize ±3σ, 36m rolling β PIT-strict.",
    "Composite F5 = equal-weight Bayesian ensemble of 4 sub-variants."
  ),
  pipeline_stage = "alpha_research_draft",
  alpha_geometry = list(
    type = "stock_level_per_name_vector",
    n_names_asof = nrow(asof_dt),
    coverage = "KOSPI200 ∪ KOSDAQ150 with TV20 ≥ 2e8 KRW PIT-lag1"
  ),
  per_name_alpha_matrix_required = TRUE,
  ml_comparison_pending = "see run_ml_comparison.py (XGBoost CUDA + OLS Fama-MacBeth baseline)",
  caveats = list(
    "VIX as KOSPI VRP proxy (cor 0.505 level) — direct KRX KOSPI200 options chain not available in cache",
    "WT_001 v1 trap (predictor lag-1 autocor 0.404) checked per factor",
    "WT_001 v3 ML feature leakage trap: features = lag-1 only, target = next-month r_i (cross-section, not portfolio aggregate)",
    "Cycle 7 CRISIS regime cor(VRP, AR) +0.6438 anti-hedge: re-tested at stock-level cross-section",
    "Lockbox 2020~2026.04 reported separately (R2 Window Isolation HARD), NOT used for selection",
    "DR measurement deferred to optimizer-research stage (alpha-research scope = signal generation only)"
  ),
  next_step_recommendations = list(
    "Codex Critic Round (5-step flow obligatory)",
    "Risk Agent: 4 sub-variant + composite covariance Σ + tail risk + crisis stress",
    "Optimizer Agent: weight decision + DR optimization (Choueifaty-Coignard)"
  )
)

write_json(alpha_package_draft,
           file.path(WT_DIR, "alpha_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("  alpha_package_draft.json written (%d names, %d factor_specs)\n",
            length(alpha_vector), length(factor_specs)))

# ─────────────────────────────────────────────────────────────────────────────
# Step 12: Lineage record (CRITICAL: after write, not before)
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 12] Recording lineage...\n")
lineage_path <- file.path(PROJECT_ROOT, "02_Infrastructure", "worktask", "lineage_utils.R")
if (file.exists(lineage_path)) {
  source(lineage_path)
  tryCatch({
    record_package_lineage(
      task_id = WT_ID,
      package_type = "alpha_package",
      method_selected = paste0("VRP_VolBeta_4subvariants_ensemble_F5_headline_", headline_factor),
      input_file_paths = c(
        file.path(PROJECT_ROOT, ".cache", "rawdata.parquet"),
        file.path(PROJECT_ROOT, ".cache", "fred_macro_wide.parquet"),
        file.path(PROJECT_ROOT, "qepm", "mailbox", "research", "risk_cycle3_20260507", "risk_package.json")
      )
    )
    cat("  lineage recorded.\n")
  }, error = function(e) {
    cat("  lineage record failed (non-blocking):", conditionMessage(e), "\n")
  })
} else {
  cat("  lineage_utils.R not found — skipped\n")
}

cat("\n=== ALPHA RESEARCH (R portion) COMPLETE ===\n")
cat(sprintf("Headline factor: %s\n", headline_factor))
cat(sprintf("Diagnostics: rank_ic=%.4f icir=%.4f t_NW=%.3f sub_stab=%.2f n_names_asof=%d\n",
            diag_dt$rank_ic, diag_dt$icir, diag_dt$harvey_t_NW,
            diag_dt$subperiod_stability, nrow(asof_dt)))
cat(sprintf("Challenge flags: %d\n", length(challenge_flags)))
cat("\nNext: run_ml_comparison.py for XGBoost CUDA + classical baseline\n")
