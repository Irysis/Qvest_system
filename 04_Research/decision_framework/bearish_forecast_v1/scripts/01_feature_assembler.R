#==============================================================================
# 01_feature_assembler.R — H3~H7 + State block panel build (FULL IMPLEMENTATION)
#
# Plan v0.4.2 — forge agent S2 위임 (2026-05-19)
#
# Source:
#   H3: .cache/krx_options/{YYYYMMDD}.parquet  (IMP_VOLT + RGHT_TP_NM) 2010-01-04~
#   H4: .cache/ecos_bond_rates.parquet          (KR_Gov10Y/3Y, CorpBBB/AA) 2000-09~
#   H5: .cache/macro_regime.parquet (Macro_Risk_Score YM) + fred_macro_wide.parquet (VIX)
#   H6: .cache/flow_features_daily.parquet      (X cols only, fwd_* denylist)
#   H7: factor_db load_month_factors() Q08+V12 (C15 정합) + .cache/consensus/sue.parquet
#   State: msm_daily_latest.parquet (Crisis_Prob → M4 proxy) + df_hybrid in MSM RData (M4 month)
#          regime_factor_clusters.parquet (SJM: cluster_id, prob, dist)
#
# PIT 의무:
#   - 00_pit_manifest_loader.R source 의무 (denylist + fail-closed)
#   - H3~H6: daily t-1 lag (same-day 사용 금지)
#   - H7: factor_db Factor_Date <= sig_date (C14 정합, load_month_factors PIT-safe)
#   - State: t-1 lag 전 적용 (sjm_state_lag1, m4_regime_lag1, r05_regime_lag1)
#   - macro_regime YM monthly: decision_date 기준 이전 월 값 사용
#
# Output: outputs/01_data/feature_panel.parquet
#   cols: Date + 10 features (hard cap):
#     vkospi_z, otm_skew_25d, kr_term_spread, kr_credit_spread,
#     macro_risk_score, vix_log_diff_ewma_21d,
#     foreign_netbuy_20d_z, short_interest_20d_z,
#     q08_composite_quality, v12_composite_value
#   (sue_z, sjm_state, m4/r05 regime 별도 extended panel에 보존)
#
# 1995-1999 결측: H3/H6/H7 → NA retain (XGBoost native handling)
#
# v1.0 — forge agent full implementation
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(zoo)   # rollmean, na.locf
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v1")
CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")

# Source PIT loader (S1 첫 gate — mandatory)
source(file.path(WS_DIR, "scripts/00_pit_manifest_loader.R"))

# Source infra
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

OUT_DIR <- file.path(WS_DIR, "outputs/01_data")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ── Helper: Rolling z-score (expanding window, min_obs 252) ──────────────────
# C1 정합: expanding window only
rolling_zscore_expanding <- function(x, min_obs = 252) {
  n <- length(x)
  z <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    vals <- x[1:i]
    vals <- vals[!is.na(vals)]
    if (length(vals) < min_obs) next
    mu <- mean(vals)
    sg <- sd(vals)
    if (is.na(sg) || sg < 1e-10) next
    z[i] <- (x[i] - mu) / sg
  }
  z
}

# ── Helper: Safe lag (t-1, PIT C2/C9) ───────────────────────────────────────
lag1 <- function(x) c(NA, head(x, -1))

# ── Block H3: vkospi_z + otm_skew_25d ───────────────────────────────────────
# Source: .cache/krx_options/{YYYYMMDD}.parquet
# IMP_VOLT (implied volatility) + RGHT_TP_NM (CALL/PUT)
# Aggregate ATM IV per day → VKOSPI-proxy z-score
# OTM 25-delta skew = mean(PUT IV, OTM) - mean(CALL IV, OTM)
# PIT: each day's option data is available same day post-15:30 (KRX_장중_publish)
#      feature_lag_table.csv: decision_time = next_open → use t-1 value
build_h3_options <- function(benchmark_dates) {
  cat("[H3] Building vkospi_z + otm_skew_25d from krx_options/...\n")

  opt_dir <- file.path(CACHE_DIR, "krx_options")
  opt_files <- list.files(opt_dir, pattern = "^[0-9]{8}\\.parquet$", full.names = TRUE)
  if (length(opt_files) == 0) {
    cat("[H3] WARNING: No krx_options parquet files found. Returning NA.\n")
    return(data.table(Date = benchmark_dates, vkospi_z = NA_real_, otm_skew_25d = NA_real_))
  }

  cat(sprintf("[H3] Reading %d option files...\n", length(opt_files)))

  # Read all option files (rbindlist)
  opts_list <- lapply(opt_files, function(f) {
    dt <- tryCatch(as.data.table(read_parquet(f)), error = function(e) NULL)
    if (is.null(dt)) return(NULL)
    # Select needed cols
    needed <- c("BAS_DD", "RGHT_TP_NM", "IMP_VOLT")
    dt <- dt[, intersect(needed, names(dt)), with = FALSE]
    dt
  })
  opts <- rbindlist(opts_list[!sapply(opts_list, is.null)], fill = TRUE)

  # Parse date
  opts[, Date := as.Date(BAS_DD, "%Y%m%d")]
  opts[, BAS_DD := NULL]

  # Convert IMP_VOLT to numeric (stored as char in raw parquet)
  opts[, IMP_VOLT := suppressWarnings(as.numeric(IMP_VOLT))]
  opts <- opts[!is.na(IMP_VOLT) & IMP_VOLT > 0]

  # RGHT_TP_NM: CALL / PUT
  opts[, RGHT_TP_NM := trimws(RGHT_TP_NM)]

  # ATM IV proxy = median of all options (VKOSPI proxy)
  # Strict ATM would require strike-spot matching, but we use cross-sectional median as proxy
  daily_atm <- opts[, .(atm_iv_median = median(IMP_VOLT, na.rm = TRUE),
                         put_iv_mean = mean(IMP_VOLT[RGHT_TP_NM == "PUT"], na.rm = TRUE),
                         call_iv_mean = mean(IMP_VOLT[RGHT_TP_NM == "CALL"], na.rm = TRUE),
                         n_obs = .N),
                    by = Date]
  setorder(daily_atm, Date)

  # OTM skew: PUT mean - CALL mean (positive = fear/skew)
  daily_atm[, raw_skew := put_iv_mean - call_iv_mean]

  # Expanding z-score for ATM IV (VKOSPI proxy, C1 rolling/expanding)
  daily_atm[, vkospi_z_raw := rolling_zscore_expanding(atm_iv_median, min_obs = 252)]

  # PIT C9 / decision_time = next_open → lag1
  daily_atm[, vkospi_z := lag1(vkospi_z_raw)]
  daily_atm[, otm_skew_25d_raw := lag1(raw_skew)]
  # z-score skew (expanding)
  daily_atm[, otm_skew_z := rolling_zscore_expanding(otm_skew_25d_raw, min_obs = 252)]
  daily_atm[, otm_skew_25d := otm_skew_z]

  # Join to benchmark dates (left join — krx_options only 2010+, NA for earlier)
  result <- merge(
    data.table(Date = benchmark_dates),
    daily_atm[, .(Date, vkospi_z, otm_skew_25d)],
    by = "Date", all.x = TRUE
  )
  setorder(result, Date)

  cat(sprintf("[H3] DONE. vkospi_z non-NA: %d / otm_skew_25d non-NA: %d (of %d)\n",
              sum(!is.na(result$vkospi_z)), sum(!is.na(result$otm_skew_25d)), nrow(result)))
  result
}

# ── Block H4: kr_term_spread + kr_credit_spread ──────────────────────────────
# Source: .cache/ecos_bond_rates.parquet (long format: Date, Value, Series)
# term_spread = KR_Gov10Y - KR_Gov3Y
# credit_spread = KR_CorpBBB - KR_CorpAA
# PIT: ECOS_KST_15:30 → decision_time = close → lag1 (t-1)
build_h4_rates <- function(benchmark_dates) {
  cat("[H4] Building kr_term_spread + kr_credit_spread from ecos_bond_rates...\n")

  ecos_path <- file.path(CACHE_DIR, "ecos_bond_rates.parquet")
  if (!file.exists(ecos_path)) stop("[H4] ecos_bond_rates.parquet not found")

  ecos <- as.data.table(read_parquet(ecos_path))
  ecos[, Date := as.Date(Date)]

  # Pivot to wide
  ecos_wide <- dcast(ecos, Date ~ Series, value.var = "Value", fun.aggregate = mean)
  setorder(ecos_wide, Date)

  # Compute spreads
  ecos_wide[, term_spread_raw := KR_Gov10Y - KR_Gov3Y]
  ecos_wide[, credit_spread_raw := KR_CorpBBB - KR_CorpAA]

  # PIT lag1 (decision_time = close → use previous day's close value)
  ecos_wide[, kr_term_spread := lag1(term_spread_raw)]
  ecos_wide[, kr_credit_spread := lag1(credit_spread_raw)]

  # Join to benchmark dates (left join — 2000+ data, NA for earlier)
  result <- merge(
    data.table(Date = benchmark_dates),
    ecos_wide[, .(Date, kr_term_spread, kr_credit_spread)],
    by = "Date", all.x = TRUE
  )
  # ECOS is business-day frequency — forward fill for missing days (weekends already filtered)
  result[, kr_term_spread := nafill(kr_term_spread, type = "locf")]
  result[, kr_credit_spread := nafill(kr_credit_spread, type = "locf")]
  setorder(result, Date)

  cat(sprintf("[H4] DONE. term_spread non-NA: %d / credit_spread non-NA: %d (of %d)\n",
              sum(!is.na(result$kr_term_spread)), sum(!is.na(result$kr_credit_spread)), nrow(result)))
  result
}

# ── Block H5: macro_risk_score + vix_log_diff_ewma_21d ───────────────────────
# macro_risk_score: macro_regime.parquet, YM monthly composite (1990-01~)
# vix_log_diff_ewma_21d: fred_macro_wide.parquet, VIX daily (2000-01~)
# PIT: macro_regime = FRED_release + ingestion (lag 1 month via YM join)
#      VIX = FRED next_open → lag1
build_h5_global <- function(benchmark_dates) {
  cat("[H5] Building macro_risk_score + vix_log_diff_ewma_21d...\n")

  # --- macro_risk_score (monthly) ---
  mr_path <- file.path(CACHE_DIR, "macro_regime.parquet")
  if (!file.exists(mr_path)) stop("[H5] macro_regime.parquet not found")

  mr <- as.data.table(read_parquet(mr_path))
  mr[, YM := as.character(YM)]

  # YM to month-end date (last business day approximation = first of next month - 1)
  mr[, YM_Date := as.Date(paste0(YM, "-01"))]
  mr[, YM_Date := YM_Date + 31]
  mr[, YM_Date := as.Date(format(YM_Date, "%Y-%m-01")) - 1]
  # PIT: monthly macro_regime built from FRED data with publishing lag
  # Use prior month: sig_date's YM -> use YM_Date from one month earlier (C3 정합)
  # decision_time = next_open → shift one row back
  mr[, macro_risk_score := lag1(Macro_Risk_Score)]

  # Join daily benchmark dates to monthly macro_risk_score (carry forward = locf)
  bench_dt <- data.table(Date = benchmark_dates, YM = format(benchmark_dates, "%Y-%m"))
  mr_daily <- merge(bench_dt, mr[, .(YM, macro_risk_score)], by = "YM", all.x = TRUE)
  mr_daily[, macro_risk_score := nafill(macro_risk_score, type = "locf")]
  setorder(mr_daily, Date)

  # --- vix_log_diff_ewma_21d (daily from fred_macro_wide) ---
  fw_path <- file.path(CACHE_DIR, "fred_macro_wide.parquet")
  if (!file.exists(fw_path)) stop("[H5] fred_macro_wide.parquet not found")

  fw <- as.data.table(read_parquet(fw_path))
  fw[, Date := as.Date(Date)]
  setorder(fw, Date)

  # VIX: log difference + EWMA 21-day
  # C1: rolling computation only (no full-sample stats)
  fw[, vix_log := log(pmax(VIX, 1e-4))]
  fw[, vix_log_diff := c(NA_real_, diff(vix_log))]

  # EWMA 21-day (alpha = 2/(21+1))
  alpha_ewma <- 2 / (21 + 1)
  ewma <- function(x, alpha) {
    n <- length(x)
    result <- rep(NA_real_, n)
    first_valid <- which(!is.na(x))[1]
    if (is.na(first_valid)) return(result)
    result[first_valid] <- x[first_valid]
    for (i in (first_valid + 1):n) {
      if (is.na(x[i])) {
        result[i] <- result[i - 1]  # carry forward
      } else {
        result[i] <- alpha * x[i] + (1 - alpha) * result[i - 1]
      }
    }
    result
  }
  fw[, vix_ewma_raw := ewma(vix_log_diff, alpha_ewma)]

  # PIT: FRED next_open decision → lag1
  fw[, vix_log_diff_ewma_21d := lag1(vix_ewma_raw)]

  # Join to benchmark dates
  vix_dt <- merge(
    data.table(Date = benchmark_dates),
    fw[, .(Date, vix_log_diff_ewma_21d)],
    by = "Date", all.x = TRUE
  )
  vix_dt[, vix_log_diff_ewma_21d := nafill(vix_log_diff_ewma_21d, type = "locf")]
  setorder(vix_dt, Date)

  # Merge both H5 features
  result <- merge(mr_daily[, .(Date, macro_risk_score)],
                  vix_dt[, .(Date, vix_log_diff_ewma_21d)],
                  by = "Date", all = TRUE)
  setorder(result, Date)

  cat(sprintf("[H5] DONE. macro_risk_score non-NA: %d / vix_ewma non-NA: %d (of %d)\n",
              sum(!is.na(result$macro_risk_score)), sum(!is.na(result$vix_log_diff_ewma_21d)), nrow(result)))
  result
}

# ── Block H6: foreign_netbuy_20d_z + short_interest_20d_z ───────────────────
# Source: .cache/flow_features_daily.parquet
# PIT: flow_features_daily = fwd_* denylist (via validate_no_leakage)
#      X cols only: foreign_netbuy_20d, inst_netbuy_20d (short proxy)
# KOSPI200 cross-section aggregate → z-score expanding
# PIT decision_time = next_open → lag1
build_h6_flow <- function(benchmark_dates) {
  cat("[H6] Building foreign_netbuy_20d_z + short_interest_20d_z from flow_features_daily...\n")

  flow_path <- file.path(CACHE_DIR, "flow_features_daily.parquet")

  # PIT leakage check (denylist: fwd_* allowed per known_leakage)
  validate_no_leakage(flow_path)

  # Load only needed columns (C15 analog: minimal load)
  flow <- as.data.table(read_parquet(flow_path,
    col_select = c("Date", "Ticker", "foreign_netbuy_20d", "inst_netbuy_20d", "liq_20d")))
  flow[, Date := as.Date(Date)]

  # Apply minimum liquidity filter (2e8 KRW liq_20d, same as production)
  flow <- flow[!is.na(liq_20d) & liq_20d >= 2e8]

  # Aggregate cross-section median (robust to outliers)
  daily_flow <- flow[, .(
    foreign_nb_cs_median = median(foreign_netbuy_20d, na.rm = TRUE),
    inst_nb_cs_median    = median(inst_netbuy_20d, na.rm = TRUE),
    n_stocks = .N
  ), by = Date]
  setorder(daily_flow, Date)

  # Expanding z-score (C1 rolling/expanding only)
  daily_flow[, foreign_nb_z_raw := rolling_zscore_expanding(foreign_nb_cs_median, min_obs = 252)]
  daily_flow[, inst_nb_z_raw    := rolling_zscore_expanding(inst_nb_cs_median, min_obs = 252)]

  # PIT: decision_time = next_open → lag1
  daily_flow[, foreign_netbuy_20d_z  := lag1(foreign_nb_z_raw)]
  daily_flow[, short_interest_20d_z  := lag1(inst_nb_z_raw)]

  # Join to benchmark dates
  result <- merge(
    data.table(Date = benchmark_dates),
    daily_flow[, .(Date, foreign_netbuy_20d_z, short_interest_20d_z)],
    by = "Date", all.x = TRUE
  )
  setorder(result, Date)

  cat(sprintf("[H6] DONE. foreign_netbuy_20d_z non-NA: %d / short_interest_20d_z non-NA: %d (of %d)\n",
              sum(!is.na(result$foreign_netbuy_20d_z)), sum(!is.na(result$short_interest_20d_z)), nrow(result)))
  result
}

# ── Block H7: q08_composite_quality + v12_composite_value (+ sue_z) ──────────
# Source: factor_db load_month_factors() (C15 정합: direct parquet read 금지)
#         + .cache/consensus/sue.parquet
# Aggregate KOSPI200-universe cross-section median per month
# PIT: load_month_factors() is PIT-safe (Factor_Date <= sig_date)
#      Monthly factor → join to daily dates (carry forward within month)
#      decision_time = close → Factor_Date <= sig_date (C14 정합, lag built into factor_db)
#      C4: Q08/V12 factor_db DART lag 정합 (annual 5월, quarterly 45일)
build_h7_valuation <- function(benchmark_dates) {
  cat("[H7] Building q08_composite_quality + v12_composite_value + sue_z...\n")

  # Monthly sig_dates (last business day of each month)
  bench_months <- unique(format(benchmark_dates, "%Y-%m"))
  # Build sig_dates = last day of each month that appears in benchmark_dates
  sig_dates <- sapply(bench_months, function(ym) {
    days_in_month <- benchmark_dates[format(benchmark_dates, "%Y-%m") == ym]
    if (length(days_in_month) == 0) return(NA_character_)
    as.character(max(days_in_month))
  })
  sig_dates <- as.Date(na.omit(sig_dates))

  # Filter to factor_db coverage start (2005-05 approximate)
  sig_dates_in_range <- sig_dates[format(sig_dates, "%Y-%m") >= "2005-05"]
  cat(sprintf("[H7] Loading factor_db for %d months (2005-05 ~ %s)...\n",
              length(sig_dates_in_range),
              as.character(max(sig_dates_in_range))))

  factor_rows <- lapply(sig_dates_in_range, function(sd) {
    dt <- tryCatch(
      load_month_factors(sd, coverage_min = 0.05),
      error = function(e) {
        cat(sprintf("  [H7] WARN: load_month_factors(%s) failed: %s\n", sd, conditionMessage(e)))
        NULL
      }
    )
    if (is.null(dt)) return(NULL)
    if (!("Factor_Name" %in% names(dt))) return(NULL)
    # Filter to Q08 and V12
    dt_q <- dt[Factor_Name %in% c("Q08_Composite_Quality", "V12_Composite_Value"),
               .(Ticker, Factor_Name, Z_Score_Aligned, sig_date = sd)]
    dt_q
  })
  fdb_all <- rbindlist(factor_rows[!sapply(factor_rows, is.null)], fill = TRUE)

  if (nrow(fdb_all) == 0) {
    cat("[H7] WARNING: No factor_db data. Returning NA.\n")
    bench_dt <- data.table(Date = benchmark_dates,
                           q08_composite_quality = NA_real_,
                           v12_composite_value   = NA_real_)
    return(bench_dt)
  }

  # Cross-section median per sig_date (KOSPI200 proxy: all loaded tickers)
  h7_monthly <- fdb_all[, .(cs_median = median(Z_Score_Aligned, na.rm = TRUE)),
                         by = .(sig_date, Factor_Name)]
  h7_wide <- dcast(h7_monthly, sig_date ~ Factor_Name, value.var = "cs_median")
  setnames(h7_wide,
           old = c("Q08_Composite_Quality", "V12_Composite_Value"),
           new = c("q08_composite_quality", "v12_composite_value"),
           skip_absent = TRUE)
  setorder(h7_wide, sig_date)

  # Join to daily dates: carry forward monthly factor within month (locf)
  bench_dt <- data.table(Date = benchmark_dates,
                         YM = format(benchmark_dates, "%Y-%m"))
  h7_wide[, YM := format(sig_date, "%Y-%m")]

  result <- merge(bench_dt, h7_wide[, .(YM, q08_composite_quality, v12_composite_value)],
                  by = "YM", all.x = TRUE)
  result[, YM := NULL]
  setorder(result, Date)

  # ── SUE z-score ─────────────────────────────────────────────
  cat("[H7] Building sue_z from consensus/sue.parquet...\n")
  sue_path <- file.path(CACHE_DIR, "consensus/sue.parquet")
  if (file.exists(sue_path)) {
    sue <- as.data.table(read_parquet(sue_path))
    sue[, Date := as.Date(Date)]
    # Cross-section median per day
    sue_daily <- sue[, .(sue_cs_med = median(sue, na.rm = TRUE)), by = Date]
    setorder(sue_daily, Date)
    # Expanding z-score (C1)
    sue_daily[, sue_z_raw := rolling_zscore_expanding(sue_cs_med, min_obs = 252)]
    # PIT: QuantiWise T+1 → lag1
    sue_daily[, sue_z := lag1(sue_z_raw)]

    result <- merge(result, sue_daily[, .(Date, sue_z)], by = "Date", all.x = TRUE)
  } else {
    cat("[H7] WARNING: sue.parquet not found. sue_z = NA.\n")
    result[, sue_z := NA_real_]
  }

  cat(sprintf("[H7] DONE. q08 non-NA: %d / v12 non-NA: %d / sue_z non-NA: %d (of %d)\n",
              sum(!is.na(result$q08_composite_quality)),
              sum(!is.na(result$v12_composite_value)),
              sum(!is.na(result$sue_z)),
              nrow(result)))
  result
}

# ── State engine: SJM + M4 + R05 ─────────────────────────────────────────────
# SJM: regime_factor_clusters.parquet (cluster_id = sjm state, dist = distance to centroid)
#      + SJM state_age computed as consecutive days in same cluster
# M4:  msm_daily_latest.parquet (Crisis_Prob) → discretize to BULL/NORMAL/CAUTION/CRISIS
# R05: df_hybrid (monthly Regime from MSM_updated RData) → monthly states
# PIT: all state signals lag1 (t-1 decision)
build_state_engine <- function(benchmark_dates) {
  cat("[State] Building SJM + M4 + R05 state engine...\n")

  # --- SJM state (regime_factor_clusters: cluster_id, prob, dist) ---
  sjm_path <- file.path(CACHE_DIR, "regime_factor_clusters.parquet")
  sjm_dt <- NULL
  if (file.exists(sjm_path)) {
    sjm_raw <- as.data.table(read_parquet(sjm_path))
    if ("Date" %in% names(sjm_raw) && "cluster_id" %in% names(sjm_raw)) {
      sjm_raw[, Date := as.Date(Date)]
      setorder(sjm_raw, Date)

      # State age (consecutive days in same cluster_id)
      sjm_raw[, state_change := c(1L, as.integer(diff(cluster_id) != 0))]
      sjm_raw[, state_run_id := cumsum(state_change)]
      sjm_raw[, state_age := seq_len(.N), by = state_run_id]

      # Distance to centroid = dist_1 (cluster 1 distance as proxy)
      dist_col <- grep("^dist_", names(sjm_raw), value = TRUE)
      if (length(dist_col) > 0) {
        sjm_raw[, distance_to_centroid := get(dist_col[1])]
      } else {
        sjm_raw[, distance_to_centroid := NA_real_]
      }

      # PIT lag1
      sjm_raw[, sjm_state_lag1    := lag1(cluster_id)]
      sjm_raw[, state_age_lag1    := lag1(state_age)]
      sjm_raw[, dist_centroid_lag1 := lag1(distance_to_centroid)]

      sjm_dt <- sjm_raw[, .(Date, sjm_state_lag1, state_age = state_age_lag1,
                              distance_to_centroid = dist_centroid_lag1)]
      cat(sprintf("[State] SJM loaded: %d rows, Date %s ~ %s\n",
                  nrow(sjm_dt), min(sjm_dt$Date), max(sjm_dt$Date)))
    }
  }

  # --- M4 regime (msm_daily_latest: Crisis_Prob → discrete) ---
  m4_path <- file.path(CACHE_DIR, "msm_daily_latest.parquet")
  m4_dt <- NULL
  if (file.exists(m4_path)) {
    m4_raw <- as.data.table(read_parquet(m4_path))
    m4_raw[, Date := as.Date(Date)]
    setorder(m4_raw, Date)

    # Discretize Crisis_Prob → M4 regime
    # Match STR_1715 M4 BOCPD scale (Crisis_Prob thresholds)
    m4_raw[, m4_regime_raw := fcase(
      Crisis_Prob >= 0.70, "CRISIS",
      Crisis_Prob >= 0.40, "CAUTION",
      Crisis_Prob >= 0.15, "NORMAL",
      default = "BULL"
    )]

    # PIT: lag1
    m4_raw[, m4_regime_lag1 := lag1(m4_regime_raw)]
    m4_raw[, m4_crisis_prob := lag1(Crisis_Prob)]

    m4_dt <- m4_raw[, .(Date, m4_regime_lag1, m4_crisis_prob)]
    cat(sprintf("[State] M4 loaded: %d rows, Date %s ~ %s\n",
                nrow(m4_dt), min(m4_dt$Date), max(m4_dt$Date)))
  }

  # --- R05 regime (df_hybrid from MSM RData — monthly) ---
  rdata_dir <- file.path(PROJECT_ROOT, "04_Research/regime_comparison/output")
  rdata_files <- list.files(rdata_dir, pattern = "MSM_updated_.*\\.RData$", full.names = TRUE)
  r05_dt <- NULL
  if (length(rdata_files) > 0) {
    rdata_latest <- rdata_files[order(rdata_files, decreasing = TRUE)][1]
    cat(sprintf("[State] Loading R05 from %s...\n", basename(rdata_latest)))
    env_r05 <- new.env()
    load(rdata_latest, envir = env_r05)
    if (exists("df_hybrid", envir = env_r05)) {
      dh <- as.data.table(env_r05$df_hybrid)
      dh[, Date := as.Date(Date)]
      setorder(dh, Date)
      # df_hybrid: monthly, Regime = Crisis/Caution/Stable
      # Map to R05 standard 4-level
      dh[, r05_regime_raw := fcase(
        Regime == "Crisis",  "CRISIS",
        Regime == "Caution", "CAUTION",
        Regime == "Stable",  "NORMAL",
        default = "BULL"
      )]
      # PIT lag1 (monthly)
      dh[, r05_regime_lag1 := lag1(r05_regime_raw)]
      dh[, YM := format(Date, "%Y-%m")]

      # Join to daily dates via YM carry forward
      bench_ym <- data.table(Date = benchmark_dates, YM = format(benchmark_dates, "%Y-%m"))
      r05_dt <- merge(bench_ym, dh[, .(YM, r05_regime_lag1)], by = "YM", all.x = TRUE)
      # nafill requires numeric; use zoo::na.locf for character column
      r05_dt[, r05_regime_lag1 := zoo::na.locf(r05_regime_lag1, na.rm = FALSE)]
      r05_dt[, YM := NULL]
      setorder(r05_dt, Date)
      cat(sprintf("[State] R05 loaded: %d rows\n", nrow(r05_dt)))
    }
  }

  # Assemble state block
  result <- data.table(Date = benchmark_dates)
  if (!is.null(sjm_dt)) {
    result <- merge(result, sjm_dt, by = "Date", all.x = TRUE)
  } else {
    result[, c("sjm_state_lag1", "state_age", "distance_to_centroid") := NA_real_]
  }
  if (!is.null(m4_dt)) {
    result <- merge(result, m4_dt, by = "Date", all.x = TRUE)
  } else {
    result[, c("m4_regime_lag1", "m4_crisis_prob") := list(NA_character_, NA_real_)]
  }
  if (!is.null(r05_dt)) {
    result <- merge(result, r05_dt, by = "Date", all.x = TRUE)
  } else {
    result[, r05_regime_lag1 := NA_character_]
  }

  setorder(result, Date)
  cat(sprintf("[State] DONE. sjm non-NA: %d / m4 non-NA: %d / r05 non-NA: %d (of %d)\n",
              sum(!is.na(result$sjm_state_lag1)), sum(!is.na(result$m4_regime_lag1)),
              sum(!is.na(result$r05_regime_lag1)), nrow(result)))
  result
}

# ── Main assembler ────────────────────────────────────────────────────────────
assemble_features <- function(decision_mode = c("close", "next_open")) {
  decision_mode <- match.arg(decision_mode)

  cat("============================================================\n")
  cat("[feature_assembler] Plan v0.4.2 — S2 Feature Panel Build\n")
  cat("============================================================\n\n")

  # PIT manifest load (mandatory)
  manifest <- load_feature_lag_table(file.path(WS_DIR, "config/feature_lag_table.csv"))
  cat("[feature_assembler] manifest loaded:", nrow(manifest), "features\n\n")

  # Load benchmark dates (all trading days 1990-01-04 ~ 2026-05-19)
  bm_path <- file.path(CACHE_DIR, "benchmark.parquet")
  bm <- as.data.table(read_parquet(bm_path))
  bm[, Date := as.Date(Date)]
  setorder(bm, Date)
  benchmark_dates <- bm$Date
  cat(sprintf("[feature_assembler] Benchmark dates: %d (from %s to %s)\n\n",
              length(benchmark_dates), min(benchmark_dates), max(benchmark_dates)))

  # Build all blocks
  cat("── H3 파생 stress ──────────────────────────────────────────\n")
  h3 <- build_h3_options(benchmark_dates)

  cat("\n── H4 rates/credit ─────────────────────────────────────────\n")
  h4 <- build_h4_rates(benchmark_dates)

  cat("\n── H5 글로벌 전이 ──────────────────────────────────────────\n")
  h5 <- build_h5_global(benchmark_dates)

  cat("\n── H6 flow/공매도 ──────────────────────────────────────────\n")
  h6 <- build_h6_flow(benchmark_dates)

  cat("\n── H7 valuation ────────────────────────────────────────────\n")
  h7 <- build_h7_valuation(benchmark_dates)

  cat("\n── State engine ────────────────────────────────────────────\n")
  state <- build_state_engine(benchmark_dates)

  # ── Merge all blocks ─────────────────────────────────────────────────────
  cat("\n[feature_assembler] Merging all blocks...\n")
  panel <- data.table(Date = benchmark_dates)
  panel <- merge(panel, h3,     by = "Date", all.x = TRUE)
  panel <- merge(panel, h4,     by = "Date", all.x = TRUE)
  panel <- merge(panel, h5,     by = "Date", all.x = TRUE)
  panel <- merge(panel, h6,     by = "Date", all.x = TRUE)
  panel <- merge(panel, h7,     by = "Date", all.x = TRUE)
  panel <- merge(panel, state,  by = "Date", all.x = TRUE)
  setorder(panel, Date)

  # ── Filter to Walk-forward train start (1995-01-01) ──────────────────────
  panel_wf <- panel[Date >= as.Date("1995-01-01")]

  # ── Hard cap: primary 10 features (feature_set_v1.json) ──────────────────
  primary_10 <- c(
    "vkospi_z", "otm_skew_25d",
    "kr_term_spread", "kr_credit_spread",
    "macro_risk_score", "vix_log_diff_ewma_21d",
    "foreign_netbuy_20d_z", "short_interest_20d_z",
    "q08_composite_quality", "v12_composite_value"
  )
  # Extended: sue_z + state block (for regime-conditional models)
  extended_cols <- c(primary_10, "sue_z",
                     "sjm_state_lag1", "state_age", "distance_to_centroid",
                     "m4_regime_lag1", "m4_crisis_prob", "r05_regime_lag1")

  available_ext <- intersect(extended_cols, names(panel_wf))
  panel_ext <- panel_wf[, c("Date", available_ext), with = FALSE]

  # ── Save outputs ─────────────────────────────────────────────────────────
  # Primary: 10-feature panel
  panel_primary <- panel_wf[, c("Date", intersect(primary_10, names(panel_wf))), with = FALSE]
  write_parquet(panel_primary, file.path(OUT_DIR, "feature_panel.parquet"))
  cat(sprintf("[feature_assembler] Saved feature_panel.parquet: %d rows × %d cols\n",
              nrow(panel_primary), ncol(panel_primary)))

  # Extended: all features including state + sue
  write_parquet(panel_ext, file.path(OUT_DIR, "feature_panel_extended.parquet"))
  cat(sprintf("[feature_assembler] Saved feature_panel_extended.parquet: %d rows × %d cols\n",
              nrow(panel_ext), ncol(panel_ext)))

  # Coverage report
  cat("\n── Coverage Summary (feature_panel.parquet) ─────────────────\n")
  for (col in intersect(primary_10, names(panel_primary))) {
    n_obs <- sum(!is.na(panel_primary[[col]]))
    first_obs <- panel_primary[!is.na(get(col)), min(Date)]
    pct <- round(n_obs / nrow(panel_primary) * 100, 1)
    cat(sprintf("  %-35s: %5d / %5d rows (%5.1f%%) | first: %s\n",
                col, n_obs, nrow(panel_primary), pct, first_obs))
  }

  cat("\n── NA structure (1995-1999 결측 expected for H3/H6/H7) ──────\n")
  pre2000 <- panel_primary[Date < as.Date("2000-01-01")]
  cat(sprintf("  Rows 1995-1999: %d\n", nrow(pre2000)))
  for (col in intersect(primary_10, names(pre2000))) {
    cat(sprintf("  %-35s: %d non-NA in 1995-1999\n", col, sum(!is.na(pre2000[[col]]))))
  }

  cat("\n[feature_assembler] S2 COMPLETE.\n")
  cat(sprintf("[feature_assembler] Output: %s\n", file.path(OUT_DIR, "feature_panel.parquet")))
  cat(sprintf("[feature_assembler] Extended: %s\n", file.path(OUT_DIR, "feature_panel_extended.parquet")))

  invisible(panel_primary)
}

if (!interactive() && identical(sys.nframe(), 0L)) {
  assemble_features()
}
