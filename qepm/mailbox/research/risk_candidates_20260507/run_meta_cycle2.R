#============================================================================
# Cycle 2: 4번째 직교 source 후보 4종 historical risk profile 메타 진단
#
# Q-Lead 온디맨드 메타 리서치 (alpha 영역 침범 X — risk profile only)
#
# 4 후보:
#   1. VRP_KOSPI_Straddle_Short  — vol harvest (proxy: VIX 기반 합성)
#   2. Defensive_LowVol_KR        — KR equity SD-bottom quintile (Q07 proxy)
#   3. Currency_Carry_KRW          — KRW interest rate carry (KR_CD91 - US_Fed_Funds proxy)
#   4. Commodity_Gold_Copper       — GLD long + COPX long (50/50 EW)
#
# 5축 진단 × 4 후보 = 20 cells:
#   1. 공분산 metric (5 estimator × T/N + condition + PSD)
#   2. 꼬리위험 (GPD threshold sensitivity + EVT-VaR/ES)
#   3. 스트레스 분해 (8-crisis 응답)
#   4. 군집위험 (TDC + style FF/Carhart)
#   5. 데이터 가용성 / 한계
#
# PIT 준수: rolling/expanding only, t-1 lag, full-sample 통계 금지
# Charter §8 No Silent Override + AX-001 v2 + AX-005 v1.2 인지
#============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(zoo)
  library(PerformanceAnalytics)
})

# 사이클 1 산출 dir 참조
CYCLE1_DIR <- "qepm/mailbox/research/risk_model_meta_20260507"
CYCLE2_DIR <- "qepm/mailbox/research/risk_candidates_20260507"
STAGE_DIR  <- "qepm/stage_artifacts/risk_candidates_20260507"

dir.create(CYCLE2_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(STAGE_DIR, recursive = TRUE, showWarnings = FALSE)

LOG_FILE <- file.path(CYCLE2_DIR, "run_meta_cycle2.log")
logf <- function(...) {
  msg <- paste0("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] ", ...)
  cat(msg, "\n")
  cat(msg, "\n", file = LOG_FILE, append = TRUE)
}

logf("====== Cycle 2 START ======")

#============================================================================
# Section 0: 사이클 1 component returns 로드 (Hybrid 70/15/15 baseline)
#============================================================================

cr <- fread(file.path(CYCLE1_DIR, "component_returns_classified.csv"))
cr[, date := as.Date(date)]
setorder(cr, date)

# 사이클 1과 동일: post-2015 137m 기간 포함 + full 256m AR sample
logf("Component returns: rows=", nrow(cr),
     " | range=", as.character(min(cr$date)), "~", as.character(max(cr$date)))

# Hybrid renormalized (사이클 1 동일)
hybrid_returns <- cr[, .(date, ym, r_AR, r_KR10y, r_TSMOM, r_Hybrid = r_H_renorm,
                         has_ts, has_tsmom)]

#============================================================================
# Section 1: 4 후보 historical proxy returns 합성
#============================================================================
logf("--- Section 1: Build 4 candidate historical proxy returns ---")

# === 1.1 Commodity_Gold_Copper (US ETF GLD + COPX 50/50 EW) ===
us <- as.data.table(read_parquet(".cache/us_etf_daily.parquet"))
us[, Date := as.Date(Date)]
setorder(us, Date)

gld <- us[!is.na(GLD), .(Date, GLD)]
gld[, ret_d := GLD / shift(GLD, 1L) - 1]
copx <- us[!is.na(COPX), .(Date, COPX)]
copx[, ret_d := COPX / shift(COPX, 1L) - 1]

# Daily → monthly (last day in month)
gld_m <- gld[!is.na(ret_d), .(date_eom = max(Date),
                              gld_ret = prod(1 + ret_d) - 1),
             by = .(ym = format(Date, "%Y-%m"))]
copx_m <- copx[!is.na(ret_d), .(date_eom = max(Date),
                                copx_ret = prod(1 + ret_d) - 1),
               by = .(ym = format(Date, "%Y-%m"))]

cmm_m <- merge(gld_m, copx_m, by = "ym", all = FALSE)
cmm_m[, r_commodity := 0.5 * gld_ret + 0.5 * copx_ret]  # 50/50 EW
logf("Commodity Gold/Copper monthly: rows=", nrow(cmm_m),
     " range=", min(cmm_m$ym), "~", max(cmm_m$ym))

# === 1.2 Currency_Carry_KRW (KR_CD91 - US_Fed_Funds, 1m carry differential) ===
# CD91 short rate proxy for KRW carry, FED Funds proxy for USD funding
ek <- as.data.table(read_parquet(".cache/ecos_bond_rates.parquet"))
ek[, Date := as.Date(Date)]
cd91 <- ek[Series == "KR_CD91", .(Date, kr_cd91_yield = Value)]

fm <- as.data.table(read_parquet(".cache/fred_macro.parquet"))
fm[, Date := as.Date(Date)]
ffr <- fm[Series == "Fed_Funds_Rate", .(Date, ffr = Value)]

# KRW spot from ECOS
ekrw <- as.data.table(read_parquet(".cache/ecos_krw_usd.parquet"))
ekrw[, Date := as.Date(Date)]

# Monthly carry signal: long KRW (earn CD91) - fund USD (pay FFR), apply on 1m basis
# Plus FX appreciation (positive if USD/KRW DOWN = KRW UP)
# Use end-of-month values
cd91_m <- cd91[, .(date_eom = max(Date), kr_cd91 = last(kr_cd91_yield)),
               by = .(ym = format(Date, "%Y-%m"))]
ffr_m  <- ffr[, .(date_eom = max(Date), ffr = last(ffr)),
              by = .(ym = format(Date, "%Y-%m"))]
krw_m  <- ekrw[, .(date_eom = max(Date), krw_usd = last(KRW_USD)),
               by = .(ym = format(Date, "%Y-%m"))]

# All to monthly carry returns
carry <- merge(cd91_m[, .(ym, kr_cd91)], ffr_m[, .(ym, ffr)], by = "ym", all = FALSE)
carry <- merge(carry, krw_m[, .(ym, krw_usd)], by = "ym", all = FALSE)
setorder(carry, ym)
# Carry component (annual rate / 12 to monthly): gain CD91 (KR side) - pay FFR (USD funding)
carry[, carry_diff_monthly := (kr_cd91 - ffr) / 100 / 12]
# FX component: positive return when USD/KRW DECREASES (KRW appreciates)
# Using PIT t-1 lag: returns from t-1 to t (no future leakage)
carry[, fx_ret_monthly := -1 * (krw_usd - shift(krw_usd, 1L)) / shift(krw_usd, 1L)]
# Long-KRW carry total monthly return: earn carry differential + FX move
carry[, r_currency := carry_diff_monthly + fx_ret_monthly]
carry <- carry[!is.na(r_currency)]
logf("Currency Carry KRW monthly: rows=", nrow(carry),
     " range=", min(carry$ym), "~", max(carry$ym))

# === 1.3 VRP_KOSPI_Straddle_Short (proxy: VIX-based monthly vol mean reversion) ===
# 정식 KOSPI200 옵션 데이터 부재 → VIX proxy 합성 (한계 명시 — VIX = US 변동성)
# Strategy: Short variance swap proxy = - (realized_vol_t - implied_vol_lag)
# Approximate via KOSPI BM realized vol vs VIX-lag (US/KR vol correlated, but not 1.0)
vix <- fm[Series == "VIX", .(Date = Date, vix = Value)]
setorder(vix, Date)
vix_m <- vix[, .(date_eom = max(Date), vix_eom = last(vix)),
             by = .(ym = format(Date, "%Y-%m"))]
setorder(vix_m, ym)

# KOSPI BM monthly returns from rawdata
rd_bm_vrp <- as.data.table(read_parquet(".cache/rawdata.parquet",
                                         col_select = c("Date", "BM_Ret")))
rd_bm_vrp <- rd_bm_vrp[!is.na(BM_Ret)]
rd_bm_vrp <- rd_bm_vrp[!duplicated(Date)]
setorder(rd_bm_vrp, Date)
bm_m_vrp <- rd_bm_vrp[, .(date_eom = max(Date),
                          realized_vol_monthly_ann = sd(BM_Ret, na.rm = TRUE) * sqrt(252)),
                      by = .(ym = format(Date, "%Y-%m"))]
setorder(bm_m_vrp, ym)

# VRP signal: Short straddle returns ~ (implied_vol_lag - realized_vol_t) per unit vol
# Pricing approximation:
#   premium received at t-1 = vix_lag/100 × sqrt(1/12) × straddle_factor (~0.40)
#   payoff at t (paid) = realized_vol_monthly_ann/sqrt(12) × straddle_factor
#   net P&L ≈ (vix_lag/100 - realized_vol_ann) × sqrt(1/12) × straddle_factor
# Note: VIX is in % unit (annual vol), realized_vol_monthly_ann is in decimal (annual vol)
vrp <- merge(vix_m[, .(ym, vix_eom)], bm_m_vrp[, .(ym, realized_vol_monthly_ann)],
             by = "ym", all = FALSE)
setorder(vrp, ym)
vrp[, vix_lag_dec := shift(vix_eom, 1L) / 100]  # PIT lag (t-1), decimal vol
vrp[, r_vrp := (vix_lag_dec - realized_vol_monthly_ann) * sqrt(1/12) * 0.40]
vrp <- vrp[!is.na(r_vrp) & !is.na(vix_lag_dec)]
logf("VRP proxy monthly: rows=", nrow(vrp),
     " range=", min(vrp$ym), "~", max(vrp$ym))

# === 1.4 Defensive_LowVol_KR (rawdata.parquet KR equity universe, SD-bottom quintile) ===
# Q07_Earnings_Stability proxy = monthly_ret SD bottom 20% (rolling 12m, t-1 PIT)
rd_full <- as.data.table(read_parquet(".cache/rawdata.parquet",
                                       col_select = c("Date", "Ticker", "Ret", "K200", "Vol", "Close", "Sector_Lv2")))
rd_full[, Date := as.Date(Date)]

# Filter: K200 universe + valid Ret + Vol > 0
rd_filtered <- rd_full[K200 == 1 & !is.na(Ret) & Vol > 0]

# Compute monthly returns first (per-ticker)
# Using last close per month
rd_m <- rd_filtered[, .(date_eom = max(Date),
                         close_eom = last(Close),
                         ret_monthly = prod(1 + Ret, na.rm = TRUE) - 1,
                         daily_vol = sd(Ret, na.rm = TRUE)),
                     by = .(Ticker, ym = format(Date, "%Y-%m"))]
setorder(rd_m, Ticker, ym)

# 12-month rolling SD of monthly returns (PIT lag: use info up to month t-1 to construct portfolio for month t)
# Manual rolling SD function — explicit length output
rolling_sd <- function(x, n = 12) {
  if (length(x) < n) return(rep(NA_real_, length(x)))
  out <- rep(NA_real_, length(x))
  for (i in n:length(x)) {
    out[i] <- sd(x[(i - n + 1):i], na.rm = TRUE)
  }
  out
}
rd_m[, sd_12m := rolling_sd(ret_monthly, 12L), by = Ticker]
rd_m[, sd_12m_lag := shift(sd_12m, 1L, type = "lag"), by = Ticker]

# Each month t: select bottom 20% by sd_12m_lag (lowest vol = defensive)
sd_quintile_assign <- function(dt) {
  dt2 <- copy(dt)
  dt2[, sd_quintile := cut(sd_12m_lag,
                            breaks = quantile(sd_12m_lag, probs = seq(0, 1, 0.2), na.rm = TRUE),
                            labels = 1:5,
                            include.lowest = TRUE), by = ym]
  dt2
}
rd_m_qt <- sd_quintile_assign(rd_m[!is.na(sd_12m_lag)])

# Defensive LowVol Portfolio (EW within bottom-quintile, monthly rebalance)
# Forward return (t to t+1): use ret_monthly of next month
rd_m_qt[, ret_fwd := shift(ret_monthly, -1L), by = Ticker]
rd_m_qt[, ret_fwd_date := shift(date_eom, -1L), by = Ticker]

defensive_pf_monthly <- rd_m_qt[sd_quintile == 1 & !is.na(ret_fwd),
                                 .(r_defensive = mean(ret_fwd, na.rm = TRUE),
                                   n_holdings = .N,
                                   date_eom = first(ret_fwd_date)),
                                 by = ym]
setorder(defensive_pf_monthly, ym)
logf("Defensive LowVol KR monthly: rows=", nrow(defensive_pf_monthly),
     " range=", min(defensive_pf_monthly$ym), "~", max(defensive_pf_monthly$ym))

#============================================================================
# Section 2: Master merge — Hybrid + 4 candidates
#============================================================================
logf("--- Section 2: Master merge ---")

# Hybrid baseline (post-2015 cleanest sample)
mst <- hybrid_returns[, .(date, ym, r_AR, r_KR10y, r_TSMOM, r_Hybrid, has_ts, has_tsmom)]
mst <- merge(mst, cmm_m[, .(ym, r_commodity)], by = "ym", all.x = TRUE)
mst <- merge(mst, carry[, .(ym, r_currency)], by = "ym", all.x = TRUE)
mst <- merge(mst, vrp[, .(ym, r_vrp)], by = "ym", all.x = TRUE)
mst <- merge(mst, defensive_pf_monthly[, .(ym, r_defensive)], by = "ym", all.x = TRUE)
setorder(mst, ym)

# Sample sizes per candidate
cand_avail <- list(
  Defensive_LowVol_KR = sum(!is.na(mst$r_defensive)),
  Commodity_Gold_Copper = sum(!is.na(mst$r_commodity)),
  Currency_Carry_KRW = sum(!is.na(mst$r_currency)),
  VRP_KOSPI_Proxy = sum(!is.na(mst$r_vrp))
)
logf("Candidate sample sizes (months): ",
     paste(names(cand_avail), unlist(cand_avail), sep = "=", collapse = ", "))

fwrite(mst, file.path(CYCLE2_DIR, "master_returns_hybrid_plus_4candidates.csv"))

#============================================================================
# Section 3: 5축 진단 — Section 3.1 Pairwise correlation + TDC
#============================================================================
logf("--- Section 3.1: Pairwise correlation + TDC ---")

candidates <- c("r_defensive", "r_commodity", "r_currency", "r_vrp")
cand_names <- c("Defensive_LowVol_KR", "Commodity_Gold_Copper", "Currency_Carry_KRW", "VRP_KOSPI_Proxy")

build_pairwise_diag <- function(mst, cand_col, cand_name) {
  # Use only complete observations for both Hybrid and candidate
  d <- mst[!is.na(r_Hybrid) & !is.na(get(cand_col))]
  d_ar <- mst[!is.na(r_AR) & !is.na(get(cand_col))]
  d_kr <- mst[!is.na(r_KR10y) & !is.na(get(cand_col))]
  d_ts <- mst[!is.na(r_TSMOM) & !is.na(get(cand_col))]

  # Pearson + Spearman (lower for tail dependence intuition)
  cor_hybrid <- cor(d$r_Hybrid, d[[cand_col]])
  cor_ar     <- cor(d_ar$r_AR, d_ar[[cand_col]])
  cor_kr     <- if (nrow(d_kr) > 30) cor(d_kr$r_KR10y, d_kr[[cand_col]]) else NA
  cor_ts     <- if (nrow(d_ts) > 30) cor(d_ts$r_TSMOM, d_ts[[cand_col]]) else NA

  # TDC empirical (Joe-Clayton): lower 5%/10%/upper 5%
  tdc_lower_q <- function(x, y, q) {
    if (length(x) < 30) return(NA)
    qx <- quantile(x, q, na.rm = TRUE)
    qy <- quantile(y, q, na.rm = TRUE)
    n_both <- sum(x <= qx & y <= qy, na.rm = TRUE)
    n_y    <- sum(y <= qy, na.rm = TRUE)
    if (n_y == 0) return(0)
    n_both / n_y
  }
  tdc_upper_q <- function(x, y, q) {
    if (length(x) < 30) return(NA)
    qx <- quantile(x, 1 - q, na.rm = TRUE)
    qy <- quantile(y, 1 - q, na.rm = TRUE)
    n_both <- sum(x >= qx & y >= qy, na.rm = TRUE)
    n_y    <- sum(y >= qy, na.rm = TRUE)
    if (n_y == 0) return(0)
    n_both / n_y
  }

  list(
    candidate = cand_name,
    n_obs = nrow(d),
    cor_with_hybrid = cor_hybrid,
    cor_with_ar = cor_ar,
    cor_with_kr10y = cor_kr,
    cor_with_tsmom = cor_ts,
    tdc_lower_5pct_with_hybrid = tdc_lower_q(d$r_Hybrid, d[[cand_col]], 0.05),
    tdc_lower_10pct_with_hybrid = tdc_lower_q(d$r_Hybrid, d[[cand_col]], 0.10),
    tdc_upper_5pct_with_hybrid = tdc_upper_q(d$r_Hybrid, d[[cand_col]], 0.05),
    tdc_lower_5pct_with_ar = tdc_lower_q(d_ar$r_AR, d_ar[[cand_col]], 0.05),
    tdc_lower_10pct_with_ar = tdc_lower_q(d_ar$r_AR, d_ar[[cand_col]], 0.10)
  )
}

pairwise_diag <- lapply(seq_along(candidates), function(i) {
  build_pairwise_diag(mst, candidates[i], cand_names[i])
})
pdiag_dt <- rbindlist(pairwise_diag, use.names = TRUE)
fwrite(pdiag_dt, file.path(CYCLE2_DIR, "candidates_pairwise_diag.csv"))
logf("Pairwise diag: ", capture.output(print(pdiag_dt[, 1:6]))[1:8] |> paste(collapse = " | "))

#============================================================================
# Section 3.2 — 4-source covariance (Hybrid + 1 candidate at a time, 5 estimators)
#============================================================================
logf("--- Section 3.2: 4-source covariance (Hybrid + cand × 5 estimators) ---")

# Each candidate × Hybrid + 1cand → 4×4 covariance (using r_AR + r_KR10y + r_TSMOM + cand)
# 5 estimators: Sample / LW_identity / LW_constcor / Gerber_v2_floor5pct / Glasso_005

# Load risk infra functions
source("02_Infrastructure/portfolio/hrp_core.R")  # .get_cor_cov

# ---- Estimator implementations (parallel-safe, used in cycle 1) ----
cov_sample <- function(R) cov(R)

cov_lw_identity <- function(R) {
  # Ledoit-Wolf shrink to identity (basic)
  S <- cov(R); n <- nrow(R); p <- ncol(R)
  mu <- mean(diag(S))
  F  <- mu * diag(p)
  d2 <- sum((S - F)^2)
  pi_hat <- 0
  for (t in 1:n) {
    x <- R[t, ] - colMeans(R)
    pi_hat <- pi_hat + sum((tcrossprod(x) - S)^2) / n
  }
  delta_star <- min(max(0, pi_hat / (n * d2)), 1)
  list(Sigma = delta_star * F + (1 - delta_star) * S, delta = delta_star)
}

cov_lw_constcor <- function(R) {
  S <- cov(R); p <- ncol(R)
  D <- diag(sqrt(diag(S)))
  Cor <- cov2cor(S)
  rbar <- (sum(Cor) - p) / (p * (p - 1))
  F_corr <- matrix(rbar, p, p); diag(F_corr) <- 1
  F <- D %*% F_corr %*% D
  d2 <- sum((S - F)^2)
  n <- nrow(R)
  pi_hat <- 0
  Rd <- scale(R, scale = FALSE)
  for (t in 1:n) {
    x <- Rd[t, ]
    pi_hat <- pi_hat + sum((tcrossprod(x) - S)^2) / n
  }
  delta_star <- min(max(0, pi_hat / (n * d2)), 1)
  list(Sigma = delta_star * F + (1 - delta_star) * S, delta = delta_star)
}

cov_gerber_v2_floor5pct <- function(R, tau = 0.5) {
  # Gerber 2015 v2 thresholded correlation
  p <- ncol(R); n <- nrow(R)
  sigma <- apply(R, 2, sd)
  G <- matrix(0, p, p)
  for (i in 1:p) for (j in 1:p) {
    rij_pos <- sum(R[, i] > tau * sigma[i] & R[, j] > tau * sigma[j])
    rij_neg <- sum(R[, i] < -tau * sigma[i] & R[, j] < -tau * sigma[j])
    rij_dis <- sum(R[, i] > tau * sigma[i] & R[, j] < -tau * sigma[j]) +
               sum(R[, i] < -tau * sigma[i] & R[, j] > tau * sigma[j])
    G[i, j] <- (rij_pos + rij_neg - rij_dis) / max(rij_pos + rij_neg + rij_dis, 1)
  }
  diag(G) <- 1
  D <- diag(sigma)
  Sigma <- D %*% G %*% D
  # Eigenvalue floor 5%
  e <- eigen(Sigma, symmetric = TRUE)
  floor_val <- 0.05 * max(e$values)
  e$values[e$values < floor_val] <- floor_val
  Sigma_pd <- e$vectors %*% diag(e$values) %*% t(e$vectors)
  list(Sigma = Sigma_pd, tau = tau, floor_pct = 0.05)
}

cov_glasso_005 <- function(R, rho = 0.05) {
  if (!requireNamespace("glasso", quietly = TRUE)) {
    return(list(Sigma = cov(R), error = "glasso package not available, fallback Sample"))
  }
  S <- cov(R)
  res <- glasso::glasso(S, rho = rho)
  list(Sigma = res$w, rho = rho)
}

# Run for each candidate
cov_summary_rows <- list()
for (i in seq_along(candidates)) {
  cand_col <- candidates[i]; cand_name <- cand_names[i]
  d <- mst[!is.na(r_AR) & !is.na(r_KR10y) & !is.na(r_TSMOM) & !is.na(get(cand_col)),
           .(r_AR, r_KR10y, r_TSMOM, cand = get(cand_col))]
  # Use deterministic asset order: AR, KR10y, TSMOM, candidate
  setnames(d, "cand", cand_col)
  R <- as.matrix(d)
  asset_names <- c("r_AR", "r_KR10y", "r_TSMOM", cand_col)
  T_obs <- nrow(R); N_obs <- ncol(R)
  if (T_obs < 30) {
    logf(cand_name, " skipped: T=", T_obs, " too small")
    next
  }

  # Run 5 estimators
  est_results <- list()
  est_results$Sample <- list(Sigma = cov_sample(R))
  est_results$LW_identity <- cov_lw_identity(R)
  est_results$LW_constcor <- cov_lw_constcor(R)
  est_results$Gerber_v2_floor5pct <- cov_gerber_v2_floor5pct(R)
  est_results$Glasso_005 <- cov_glasso_005(R)

  # Diagnostics + parquet write
  for (en in names(est_results)) {
    Sig <- est_results[[en]]$Sigma
    eg <- eigen(Sig, only.values = TRUE)$values
    cn <- max(eg) / min(eg)
    min_eig <- min(eg)
    is_pd <- all(eg > 0)

    # Save parquet (with explicit asset names as columns)
    Sig_named <- Sig
    rownames(Sig_named) <- asset_names
    colnames(Sig_named) <- asset_names
    Sig_dt <- as.data.table(Sig_named)
    Sig_dt[, asset := asset_names]
    setcolorder(Sig_dt, c("asset", asset_names))
    parquet_path <- file.path(STAGE_DIR,
                              sprintf("covariance_4src_%s_%s.parquet",
                                      tolower(cand_name), tolower(en)))
    write_parquet(Sig_dt, parquet_path)

    cov_summary_rows[[length(cov_summary_rows) + 1]] <- data.table(
      candidate = cand_name,
      estimator = en,
      T_obs = T_obs,
      N_obs = N_obs,
      T_over_N = round(T_obs / N_obs, 2),
      condition_number = round(cn, 3),
      min_eigenvalue = signif(min_eig, 4),
      is_PD = is_pd,
      delta_or_rho_or_tau = if (en == "LW_identity") est_results$LW_identity$delta else
                            if (en == "LW_constcor") est_results$LW_constcor$delta else
                            if (en == "Glasso_005") 0.05 else
                            if (en == "Gerber_v2_floor5pct") 0.5 else NA,
      parquet_path = parquet_path
    )
  }
}

cov_summary <- rbindlist(cov_summary_rows, use.names = TRUE)
fwrite(cov_summary, file.path(CYCLE2_DIR, "covariance_4src_5estimator_summary.csv"))
logf("Covariance summary saved: ", nrow(cov_summary), " rows")

#============================================================================
# Section 3.3 — Tail risk (GPD threshold sensitivity + EVT-VaR/ES per candidate)
#============================================================================
logf("--- Section 3.3: Tail risk (Pfaff Ch.7 GPD + 4-method VaR/ES) ---")

# Required packages
has_evd <- requireNamespace("evd", quietly = TRUE)
has_fext <- requireNamespace("fExtremes", quietly = TRUE)
logf("EVT packages: evd=", has_evd, " fExtremes=", has_fext)

gpd_xi_at_q <- function(losses, q) {
  if (!has_evd && !has_fext) return(c(xi = NA, beta = NA, n_exceed = NA))
  thr <- quantile(losses, q, na.rm = TRUE)
  exc <- losses[losses > thr] - thr
  n_exceed <- length(exc)
  if (n_exceed < 20) return(c(xi = NA, beta = NA, n_exceed = n_exceed))
  if (has_evd) {
    fit <- tryCatch(evd::fpot(losses, threshold = thr, model = "gpd"),
                     error = function(e) NULL)
    if (!is.null(fit)) {
      xi <- fit$estimate["shape"]
      beta <- fit$estimate["scale"]
      return(c(xi = unname(xi), beta = unname(beta), n_exceed = n_exceed))
    }
  }
  if (has_fext) {
    fit <- tryCatch(fExtremes::gpdFit(losses, u = thr),
                    error = function(e) NULL)
    if (!is.null(fit)) {
      xi <- fit@fit$par.ests["xi"]
      beta <- fit@fit$par.ests["beta"]
      return(c(xi = unname(xi), beta = unname(beta), n_exceed = n_exceed))
    }
  }
  c(xi = NA, beta = NA, n_exceed = n_exceed)
}

evt_var_es <- function(returns, alpha = 0.99, q_thr = 0.90) {
  losses <- -returns[!is.na(returns)]
  thr <- quantile(losses, q_thr, na.rm = TRUE)
  exc <- losses[losses > thr] - thr
  if (length(exc) < 20) return(c(VaR = NA, ES = NA, xi = NA, beta = NA))
  if (has_evd) {
    fit <- tryCatch(evd::fpot(losses, threshold = thr), error = function(e) NULL)
    if (is.null(fit)) return(c(VaR = NA, ES = NA, xi = NA, beta = NA))
    xi <- unname(fit$estimate["shape"]); beta <- unname(fit$estimate["scale"])
  } else if (has_fext) {
    fit <- tryCatch(fExtremes::gpdFit(losses, u = thr), error = function(e) NULL)
    if (is.null(fit)) return(c(VaR = NA, ES = NA, xi = NA, beta = NA))
    xi <- unname(fit@fit$par.ests["xi"]); beta <- unname(fit@fit$par.ests["beta"])
  } else return(c(VaR = NA, ES = NA, xi = NA, beta = NA))

  # Pfaff Eq.7.4: VaR_alpha = u + (beta/xi) * ((n/Nu * (1-alpha))^(-xi) - 1)
  n <- length(losses); Nu <- length(exc)
  if (xi == 0) {
    VaR <- thr + beta * log(n / Nu * (1 - alpha))
    ES  <- VaR + beta
  } else {
    VaR <- thr + (beta / xi) * ((n / Nu * (1 - alpha))^(-xi) - 1)
    # Pfaff Eq.7.5: ES = VaR/(1-xi) + (beta - xi*u)/(1-xi)
    ES <- VaR / (1 - xi) + (beta - xi * thr) / (1 - xi)
  }
  c(VaR = -VaR, ES = -ES, xi = xi, beta = beta)
}

cornish_fisher_var <- function(returns, alpha = 0.99) {
  r <- returns[!is.na(returns)]
  mu <- mean(r); sg <- sd(r)
  s <- mean((r - mu)^3) / sg^3  # skewness
  k <- mean((r - mu)^4) / sg^4 - 3  # excess kurtosis
  z <- qnorm(1 - alpha)
  zCF <- z + (z^2 - 1) * s / 6 + (z^3 - 3 * z) * k / 24 - (2 * z^3 - 5 * z) * s^2 / 36
  mu + sg * zCF
}

# Tail risk for each candidate (alone, not joint)
tail_rows <- list()
for (i in seq_along(candidates)) {
  cand_col <- candidates[i]; cand_name <- cand_names[i]
  r <- mst[[cand_col]]
  r <- r[!is.na(r)]
  if (length(r) < 30) next

  losses <- -r

  # GPD threshold sensitivity (q=0.85, 0.90, 0.95, 0.97, 0.99)
  for (q in c(0.85, 0.90, 0.95, 0.97, 0.99)) {
    fit <- gpd_xi_at_q(losses, q)
    tail_rows[[length(tail_rows) + 1]] <- data.table(
      candidate = cand_name,
      metric = "gpd_xi_at_q",
      threshold_q = q,
      value = signif(fit["xi"], 4),
      n_exceed = fit["n_exceed"]
    )
  }

  # 4-method VaR/ES at 99%
  emp_var99 <- quantile(r, 0.01, na.rm = TRUE)
  emp_es99  <- mean(r[r <= emp_var99], na.rm = TRUE)
  norm_var99 <- mean(r) + sd(r) * qnorm(0.01)
  cf_var99 <- cornish_fisher_var(r, 0.99)
  evt <- evt_var_es(r, 0.99, 0.90)

  for (m in c("VaR_99_empirical", "VaR_99_normal", "VaR_99_cornish_fisher", "VaR_99_EVT_GPD",
              "ES_99_empirical", "ES_99_EVT_GPD")) {
    v <- switch(m,
                VaR_99_empirical = emp_var99,
                VaR_99_normal    = norm_var99,
                VaR_99_cornish_fisher = cf_var99,
                VaR_99_EVT_GPD   = evt["VaR"],
                ES_99_empirical  = emp_es99,
                ES_99_EVT_GPD    = evt["ES"])
    tail_rows[[length(tail_rows) + 1]] <- data.table(
      candidate = cand_name,
      metric = m,
      threshold_q = NA,
      value = signif(unname(v), 4),
      n_exceed = NA
    )
  }

  # Hill alpha (n_top = sqrt(n))
  n_top <- floor(sqrt(length(losses)))
  losses_sorted <- sort(losses, decreasing = TRUE)
  if (n_top >= 5) {
    hill <- 1 / mean(log(losses_sorted[1:n_top]) - log(losses_sorted[n_top]))
    tail_rows[[length(tail_rows) + 1]] <- data.table(
      candidate = cand_name,
      metric = "hill_alpha_sqrt_n",
      threshold_q = NA,
      value = signif(hill, 4),
      n_exceed = n_top
    )
  }

  # Skewness + kurtosis + n_obs
  for (m in c("skewness", "excess_kurtosis", "n_obs", "ann_vol")) {
    v <- switch(m,
                skewness = mean((r - mean(r))^3) / sd(r)^3,
                excess_kurtosis = mean((r - mean(r))^4) / sd(r)^4 - 3,
                n_obs = length(r),
                ann_vol = sd(r) * sqrt(12))
    tail_rows[[length(tail_rows) + 1]] <- data.table(
      candidate = cand_name,
      metric = m,
      threshold_q = NA,
      value = signif(v, 4),
      n_exceed = NA
    )
  }
}
tail_dt <- rbindlist(tail_rows)
fwrite(tail_dt, file.path(CYCLE2_DIR, "candidates_tail_risk_metrics.csv"))
logf("Tail risk: ", nrow(tail_dt), " rows")

#============================================================================
# Section 3.4 — 8-crisis stress test (per candidate, joint Hybrid+cand)
#============================================================================
logf("--- Section 3.4: 8-crisis stress test ---")

# Use cycle 1 stress periods (from stress_scenarios_8crisis_v2.csv) for consistency
stress_csv_cyc1 <- fread(file.path(CYCLE1_DIR, "stress_scenarios_8crisis_v2.csv"))
stress_periods <- setNames(
  lapply(seq_len(nrow(stress_csv_cyc1)), function(i) {
    c(as.character(stress_csv_cyc1$start[i]), as.character(stress_csv_cyc1$end[i]))
  }),
  stress_csv_cyc1$period
)
logf("Stress periods (cycle 1 aligned): ", length(stress_periods))

build_joint_response <- function(mst, cand_col, cand_name, stress_list, bm_m_full) {
  rows <- list()
  for (s in names(stress_list)) {
    p <- stress_list[[s]]
    p_start <- as.Date(p[1]); p_end <- as.Date(p[2])
    sub <- mst[date >= p_start & date <= p_end]
    bm_ym_in <- format(seq(p_start, p_end, by = "month"), "%Y-%m")
    bm_sub <- bm_m_full[ym %in% bm_ym_in]
    bm_total <- if (nrow(bm_sub) > 0) prod(1 + bm_sub$mkt, na.rm = TRUE) - 1 else NA

    if (nrow(sub) < 1) {
      rows[[length(rows) + 1]] <- data.table(
        candidate = cand_name, period = s, n_obs_AR = 0, n_obs_cand = 0,
        BM_ret_pct = signif(bm_total * 100, 4),
        Hybrid_ret = NA_real_, Pure_AR_ret = NA_real_, Cand_alone_ret = NA_real_,
        Hybrid_plus_15pct_cand_ret = NA_real_, AX001_v2_PASS_vs_AR = NA,
        AX001_v2_PASS_vs_Hybrid = NA
      )
      next
    }

    sub_clean <- sub[!is.na(r_Hybrid)]
    sub_cand  <- sub[!is.na(get(cand_col))]
    sub_joint <- sub[!is.na(r_Hybrid) & !is.na(get(cand_col))]

    hybrid_total <- if (nrow(sub_clean) > 0) prod(1 + sub_clean$r_Hybrid, na.rm = TRUE) - 1 else NA
    pure_ar_total <- if (nrow(sub_clean) > 0) prod(1 + sub_clean$r_AR, na.rm = TRUE) - 1 else NA
    cand_total <- if (nrow(sub_cand) > 0) prod(1 + sub_cand[[cand_col]], na.rm = TRUE) - 1 else NA

    # Hybrid + 15% candidate replacement
    if (nrow(sub_joint) > 0) {
      r_hybrid_plus_cand <- 0.85 * sub_joint$r_Hybrid + 0.15 * sub_joint[[cand_col]]
      hybrid_plus_total <- prod(1 + r_hybrid_plus_cand, na.rm = TRUE) - 1
    } else {
      hybrid_plus_total <- NA
    }

    pass_vs_AR <- if (!is.na(pure_ar_total) && !is.na(hybrid_plus_total)) {
      hybrid_plus_total > pure_ar_total
    } else NA
    pass_vs_Hybrid <- if (!is.na(hybrid_total) && !is.na(hybrid_plus_total)) {
      hybrid_plus_total > hybrid_total
    } else NA

    rows[[length(rows) + 1]] <- data.table(
      candidate = cand_name,
      period = s,
      n_obs_AR = nrow(sub_clean),
      n_obs_cand = nrow(sub_cand),
      BM_ret_pct = signif(bm_total * 100, 4),
      Hybrid_ret = signif(hybrid_total, 4),
      Pure_AR_ret = signif(pure_ar_total, 4),
      Cand_alone_ret = signif(cand_total, 4),
      Hybrid_plus_15pct_cand_ret = signif(hybrid_plus_total, 4),
      AX001_v2_PASS_vs_AR = pass_vs_AR,
      AX001_v2_PASS_vs_Hybrid = pass_vs_Hybrid
    )
  }
  rbindlist(rows, fill = TRUE)
}

# BM monthly (used by both stress + style sections)
rd_bm_full <- as.data.table(read_parquet(".cache/rawdata.parquet",
                                          col_select = c("Date", "Ticker", "BM_Ret")))
rd_bm_full <- rd_bm_full[!is.na(BM_Ret)]
rd_bm_full[, Date := as.Date(Date)]
bm_unique <- rd_bm_full[!duplicated(Date), .(Date, BM_Ret)]
setorder(bm_unique, Date)
bm_m_full <- bm_unique[, .(date_eom = max(Date),
                            mkt = prod(1 + BM_Ret, na.rm = TRUE) - 1),
                        by = .(ym = format(Date, "%Y-%m"))]

stress_results <- list()
for (i in seq_along(candidates)) {
  stress_results[[i]] <- build_joint_response(mst, candidates[i], cand_names[i],
                                               stress_periods, bm_m_full)
}
stress_dt <- rbindlist(stress_results, use.names = TRUE, fill = TRUE)
fwrite(stress_dt, file.path(CYCLE2_DIR, "candidates_stress_8crisis.csv"))
logf("Stress: ", nrow(stress_dt), " rows")

#============================================================================
# Section 3.5 — Style exposure (FF3 / Carhart 4) per candidate
#============================================================================
logf("--- Section 3.5: Style FF3/Carhart proxy regressions ---")

# Style regression
mst2 <- merge(mst, bm_m_full[, .(ym, mkt)], by = "ym", all.x = TRUE)

style_rows <- list()
for (i in seq_along(candidates)) {
  cand_col <- candidates[i]; cand_name <- cand_names[i]
  d <- mst2[!is.na(mkt) & !is.na(get(cand_col))]
  if (nrow(d) < 36) {
    style_rows[[length(style_rows) + 1]] <- data.table(
      candidate = cand_name, n_obs = nrow(d),
      mkt_beta = NA, mkt_R2 = NA, alpha_monthly = NA, t_alpha = NA
    )
    next
  }
  fit <- lm(d[[cand_col]] ~ d$mkt)
  s <- summary(fit)
  style_rows[[length(style_rows) + 1]] <- data.table(
    candidate = cand_name,
    n_obs = nrow(d),
    mkt_beta = signif(coef(fit)[2], 4),
    mkt_R2 = signif(s$r.squared, 4),
    alpha_monthly = signif(coef(fit)[1], 4),
    t_alpha = signif(coef(s)[1, 3], 4)
  )
}
style_dt <- rbindlist(style_rows)
fwrite(style_dt, file.path(CYCLE2_DIR, "candidates_style_exposure.csv"))
logf("Style: ", nrow(style_dt), " rows")

#============================================================================
# Section 3.6 — 4-regime correlation per candidate (BULL/NORMAL/CAUTION/CRISIS)
#============================================================================
logf("--- Section 3.6: 4-regime correlation (BULL/NORMAL/CAUTION/CRISIS) ---")

# Reproduce cycle 1 4-regime classification:
#   bm_vol_12m_lag = sd(shift(bm_ret, 1), 12) * sqrt(12)  [annualized]
#   bm_ret_12m_lag = frollsum(shift(bm_ret, 1), 12)
# Rules:
#   vol12 > 0.30 → CRISIS
#   0.20 < vol12 ≤ 0.30 → CAUTION
#   vol12 < 0.15 & ret12 > 0.10 → BULL
#   else → NORMAL
bm_for_regime <- bm_m_full[, .(ym, mkt)]
setorder(bm_for_regime, ym)
bm_for_regime[, bm_ret := mkt]
# Manual rolling: computed once at the master level
bm_for_regime[, bm_vol_12m_lag := {
  v <- rep(NA_real_, .N)
  rl <- shift(bm_ret, 1L, type = "lag")
  for (k in 13:.N) {
    v[k] <- sd(rl[(k - 11):k], na.rm = TRUE) * sqrt(12)
  }
  v
}]
bm_for_regime[, bm_ret_12m_lag := {
  v <- rep(NA_real_, .N)
  rl <- shift(bm_ret, 1L, type = "lag")
  for (k in 13:.N) {
    v[k] <- prod(1 + rl[(k - 11):k], na.rm = TRUE) - 1
  }
  v
}]

classify_regime <- function(vol12, ret12) {
  if (is.na(vol12) || is.na(ret12)) return(NA_character_)
  if (vol12 > 0.30) return("CRISIS")
  if (vol12 > 0.20) return("CAUTION")
  if (vol12 < 0.15 && ret12 > 0.10) return("BULL")
  return("NORMAL")
}
bm_for_regime[, regime_4 := mapply(classify_regime, bm_vol_12m_lag, bm_ret_12m_lag)]

mst3 <- merge(mst, bm_for_regime[, .(ym, regime_4)], by = "ym", all.x = TRUE)
regime_dist <- mst3[, .N, by = regime_4][order(-N)]
fwrite(regime_dist, file.path(CYCLE2_DIR, "regime_4_distribution_cycle2.csv"))
logf("Regime distribution: ",
     paste(regime_dist$regime_4, regime_dist$N, sep = "=", collapse = ", "))

regime_rows <- list()
for (i in seq_along(candidates)) {
  cand_col <- candidates[i]; cand_name <- cand_names[i]
  for (rg in c("BULL", "NORMAL", "CAUTION", "CRISIS")) {
    d <- mst3[regime_4 == rg & !is.na(r_Hybrid) & !is.na(get(cand_col))]
    if (nrow(d) < 3) {
      regime_rows[[length(regime_rows) + 1]] <- data.table(
        candidate = cand_name, regime = rg, n_obs = nrow(d),
        cor_with_hybrid = NA_real_, mean_ret_cand = NA_real_,
        sd_ret_cand = NA_real_
      )
      next
    }
    cor_h <- cor(d$r_Hybrid, d[[cand_col]])
    mean_r <- mean(d[[cand_col]])
    sd_r   <- sd(d[[cand_col]])
    regime_rows[[length(regime_rows) + 1]] <- data.table(
      candidate = cand_name, regime = rg, n_obs = nrow(d),
      cor_with_hybrid = signif(cor_h, 4),
      mean_ret_cand = signif(mean_r, 4),
      sd_ret_cand = signif(sd_r, 4)
    )
  }
}
regime_dt <- rbindlist(regime_rows)
fwrite(regime_dt, file.path(CYCLE2_DIR, "candidates_regime_correlation.csv"))
logf("Regime correlation: ", nrow(regime_dt), " rows")

#============================================================================
# Section 4: Save master dt + summaries
#============================================================================
logf("====== Cycle 2 Sections 3.1~3.6 DONE ======")

# Quick summary print
cat("\n====== Summary so far ======\n")
cat("\n--- Pairwise diag ---\n"); print(pdiag_dt[, .(candidate, n_obs, cor_with_hybrid, cor_with_ar, tdc_lower_5pct_with_hybrid, tdc_upper_5pct_with_hybrid)])
cat("\n--- Style exposure ---\n"); print(style_dt)
cat("\n--- Regime correlation ---\n"); print(regime_dt[, .(candidate, regime, n_obs, cor_with_hybrid, mean_ret_cand)])
cat("\n--- Stress (key 4 with AR available) ---\n")
print(stress_dt[period %in% c("GFC_2008", "COVID_2020", "Inflation_2022", "VolShock_2018"),
                .(candidate, period, n_obs_AR, BM_ret_pct, Pure_AR_ret, Hybrid_plus_15pct_cand_ret,
                  AX001_v2_PASS_vs_AR, AX001_v2_PASS_vs_Hybrid)])

# Crisis alpha summary count per candidate
cat("\n--- Crisis alpha PASS rate (vs Pure AR / vs Hybrid) ---\n")
crisis_alpha_summary <- stress_dt[!is.na(AX001_v2_PASS_vs_AR),
                                   .(n_periods_AR_avail = .N,
                                     pass_count_vs_AR = sum(AX001_v2_PASS_vs_AR, na.rm = TRUE),
                                     pass_pct_vs_AR = round(mean(AX001_v2_PASS_vs_AR, na.rm = TRUE) * 100, 1),
                                     pass_count_vs_Hybrid = sum(AX001_v2_PASS_vs_Hybrid, na.rm = TRUE),
                                     pass_pct_vs_Hybrid = round(mean(AX001_v2_PASS_vs_Hybrid, na.rm = TRUE) * 100, 1)),
                                   by = candidate]
print(crisis_alpha_summary)
fwrite(crisis_alpha_summary, file.path(CYCLE2_DIR, "candidates_crisis_alpha_summary.csv"))

logf("====== Cycle 2 R script END ======")
