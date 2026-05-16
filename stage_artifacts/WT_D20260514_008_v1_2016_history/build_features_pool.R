#!/usr/bin/env Rscript
# WT-D20260514_008: ML Features Pool 보완 구축 (사전 리서치)
# Author: alpha-research agent (Q-Lead spawn)
# Strict PIT C1~C15. graduation gate 없음. features pool 산출만.
#
# Build pipeline (자율 진행):
#   Layer A: Factor DB monthly 281 (long → wide)
#   Layer B: WT_007 5 panels (29 features inherit)
#   Layer C: Factor DB Daily gap 29 (daily → month-end resample, t-1 PIT)
#   Layer D: Daily-aggregate features (~32, RAWDATA 22d rolling window per sig_date)
#   Layer E: Macro 22 FRED + 7 ECOS bond + 1 KRW_USD (t-1 lag, monthly resample)
#   Layer F: Interactions top-K (~120, factor × sector top-10 + factor × factor top-K)
#   Layer G: Lag features (~200, 1m/3m/6m/12m × top 50 base)
#   Layer H: Rolling stats (~250, mean/std/skew/kurt × 5 windows × top 10 base)
#   Layer I: Sector × top dummies (~50)
#
# Output:
#   stage_artifacts/WT_D20260514_008/features_master.parquet  (long format: sig_date × Ticker × features)
#   stage_artifacts/WT_D20260514_008/feature_registry.json    (per-feature metadata)
#   stage_artifacts/WT_D20260514_008/feature_quality_audit.json (variance/missing/cor)

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(dplyr); library(jsonlite)
  library(tibble); library(stringr); library(zoo); library(moments)
})

# ----------------------------------------------------------------------
# 0. Setup
# ----------------------------------------------------------------------
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
OUT_DIR <- "stage_artifacts/WT_D20260514_008"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

LIQ_THRESHOLD <- 5e7  # request.json: liquidity_min_won_20d_avg = 50000000
LIQ_WIN <- 20L

# Sig dates: align with WT_007 (123 monthly, 2016-02-29 ~ 2026-04-30)
wt007_f1 <- as.data.table(read_parquet("stage_artifacts/WT_D20260514_007/f1_realized_skewness_panel.parquet"))
sig_dates <- sort(unique(wt007_f1$Date))
cat("[Setup] sig_dates =", length(sig_dates), " range:", as.character(min(sig_dates)), "~", as.character(max(sig_dates)), "\n")

# Feature registry container
registry <- list()
reg_add <- function(feature_id, source, family, academic_reference, pit_lag_policy, data_source_file, formula) {
  registry[[length(registry) + 1]] <<- list(
    feature_id = feature_id, source = source, family = family,
    academic_reference = academic_reference, pit_lag_policy = pit_lag_policy,
    data_source_file = data_source_file, formula = formula
  )
}

# ----------------------------------------------------------------------
# 1. Universe construction (PIT-clean, per sig_date)
#    LIQ_THRESHOLD = 5e7 (20d ADV)
#    Exclude: AdminStock=1, TradingHalt=1, UnfaithfulDisc=1, Size<100M (penny)
# ----------------------------------------------------------------------
cat("\n[Layer 0] Universe construction...\n")
rd_ds <- open_dataset(".cache/rawdata.parquet")
# Need all daily data from 2014-01 onward to have 24m rolling + 20d LIQ
first_data_date <- as.Date("2014-01-01")
rd_full <- rd_ds %>%
  filter(Date >= first_data_date) %>%
  select(Date, Ticker, Close, Open, High, Low, Vol, Size, Ret, BM_Ret, Sector_Lv2,
         AdminStock, TradingHalt, UnfaithfulDisc) %>%
  collect() %>% as.data.table()
setkey(rd_full, Ticker, Date)
cat("  RAWDATA loaded:", nrow(rd_full), "rows ", uniqueN(rd_full$Ticker), "tickers\n")

# Compute trading value (Vol * Close ~ traded value in KRW)
rd_full[, TradeValue := Vol * Close]
# 20d rolling avg trade value per ticker
rd_full[, ADV20 := frollmean(TradeValue, n = LIQ_WIN, align = "right", na.rm = TRUE), by = Ticker]

# Per sig_date universe: liquidity at sig_date >= LIQ_THRESHOLD, no admin/halt
make_universe <- function(sd) {
  snap <- rd_full[Date == sd]
  if (nrow(snap) == 0) return(NULL)
  snap[
    !is.na(ADV20) & ADV20 >= LIQ_THRESHOLD &
    (is.na(AdminStock) | AdminStock == 0) &
    (is.na(TradingHalt) | TradingHalt == 0) &
    (is.na(UnfaithfulDisc) | UnfaithfulDisc == 0) &
    !is.na(Size) & Size >= 1e8,
    .(Ticker, Sector_Lv2)
  ]
}

uni_list <- lapply(sig_dates, function(sd) {
  u <- make_universe(sd)
  if (is.null(u)) return(NULL)
  u[, sig_date := sd]
  u
})
universe_panel <- rbindlist(uni_list, fill = TRUE)
setkey(universe_panel, sig_date, Ticker)
cat("  Universe panel:", nrow(universe_panel), "rows,",
    "mean cover/month:", round(nrow(universe_panel) / length(sig_dates), 0), "\n")
write_parquet(universe_panel, file.path(OUT_DIR, "universe_panel.parquet"))

# ----------------------------------------------------------------------
# 2. Layer A: Factor DB monthly 281 (long → wide)
# ----------------------------------------------------------------------
cat("\n[Layer A] Factor DB monthly 281 retrieve + long-to-wide...\n")
source("02_Infrastructure/factor_db/factor_db_connector.R")

LAYER_A_PATH <- file.path(OUT_DIR, "layer_a_factor_db_monthly.parquet")
if (file.exists(LAYER_A_PATH)) {
  cat("  [resume] Layer A exists, loading...\n")
  layer_a <- as.data.table(read_parquet(LAYER_A_PATH))
  setkey(layer_a, sig_date, Ticker)
  factor_names_monthly <- setdiff(names(layer_a), c("sig_date", "Ticker"))
  cat("  Layer A loaded:", nrow(layer_a), "rows,", length(factor_names_monthly), "factors\n")
  for (fname in factor_names_monthly) {
    reg_add(paste0("fdb_m_", fname), "Factor DB monthly 281",
            str_extract(fname, "^[A-Z]+"), "Factor DB v9.0",
            "C2 (Usable_Date <= sig_date enforced by load_month_factors)",
            ".cache/factor_db/", "Z_Score_Aligned (PIT-safe)")
  }
} else {
layer_a_list <- vector("list", length(sig_dates))
factor_names_monthly <- NULL
for (i in seq_along(sig_dates)) {
  sd <- sig_dates[i]
  fm <- tryCatch(as.data.table(load_month_factors(sd)), error = function(e) NULL)
  if (is.null(fm) || nrow(fm) == 0) next
  # Pivot wider: Ticker × Factor_Name
  fm_w <- dcast(fm, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
                fun.aggregate = function(x) if (length(x)) x[1] else NA_real_)
  if (is.null(factor_names_monthly)) factor_names_monthly <- setdiff(names(fm_w), "Ticker")
  fm_w[, sig_date := sd]
  layer_a_list[[i]] <- fm_w
  if (i %% 20 == 0) cat("  ... loaded month", i, "/", length(sig_dates), "\n")
}
layer_a <- rbindlist(layer_a_list, fill = TRUE, use.names = TRUE)
setkey(layer_a, sig_date, Ticker)
# Restrict to universe
layer_a <- layer_a[universe_panel[, .(sig_date, Ticker)], on = c("sig_date", "Ticker"), nomatch = 0L]
cat("  Layer A (Factor DB monthly wide):", nrow(layer_a), "rows,", ncol(layer_a) - 2, "factors\n")
# Register
for (fname in factor_names_monthly) {
  reg_add(paste0("fdb_m_", fname), "Factor DB monthly 281",
          str_extract(fname, "^[A-Z]+"), "Factor DB v9.0",
          "C2 (Usable_Date <= sig_date enforced by load_month_factors)",
          ".cache/factor_db/", "Z_Score_Aligned (PIT-safe)")
}

# Save Layer A
write_parquet(layer_a, file.path(OUT_DIR, "layer_a_factor_db_monthly.parquet"))
cat("  Saved layer_a_factor_db_monthly.parquet\n")
}  # end resume branch

# ----------------------------------------------------------------------
# 3. Layer B: WT_007 5 panels inherit (29 features)
# ----------------------------------------------------------------------
cat("\n[Layer B] WT_007 5 panels inherit...\n")
LAYER_B_PATH <- file.path(OUT_DIR, "layer_b_wt007_inherit.parquet")
if (file.exists(LAYER_B_PATH)) {
  cat("  [resume] Layer B exists, loading...\n")
  layer_b <- as.data.table(read_parquet(LAYER_B_PATH))
  setkey(layer_b, sig_date, Ticker)
  b_features <- setdiff(names(layer_b), c("sig_date", "Ticker"))
  for (fc in b_features) {
    panel_id <- substr(fc, 7, 8)  # wt007_f1_xxx
    reg_add(fc, "WT-D20260514_007",
            switch(panel_id, f1="D", f2="D", f3="Macro", f4="Macro_Sector", f5="Disclosure"),
            switch(panel_id,
                   f1 = "Bali-Engle-Murray 2016",
                   f2 = "Ang-Hodrick-Xing-Zhang 2006 JF",
                   f3 = "Fama-French 1993",
                   f4 = "Cohen-Frazzini 2008 JF",
                   f5 = "Da-Engelberg-Gao 2011 JF"),
            "C2 (panel already lagged at WT_007 build time)",
            paste0("stage_artifacts/WT_D20260514_007/", panel_id, "_*.parquet"),
            "inherited from WT_007 (lagged + z-scored)")
  }
  cat("  Layer B loaded:", nrow(layer_b), "rows,", length(b_features), "features\n")
} else {
b_files <- list(
  f1 = "stage_artifacts/WT_D20260514_007/f1_realized_skewness_panel.parquet",
  f2 = "stage_artifacts/WT_D20260514_007/f2_idio_vol_decomp_panel.parquet",
  f3 = "stage_artifacts/WT_D20260514_007/f3_macro_beta_panel.parquet",
  f4 = "stage_artifacts/WT_D20260514_007/f4_sector_macro_panel.parquet",
  f5 = "stage_artifacts/WT_D20260514_007/f5_disclosure_velocity_panel.parquet"
)

layer_b <- universe_panel[, .(sig_date, Ticker)]
b_features <- character(0)
for (panel_id in names(b_files)) {
  dp <- as.data.table(read_parquet(b_files[[panel_id]]))
  setnames(dp, "Date", "sig_date")
  # Drop columns that are just Tickers/raw — keep only _lag and _z variants (PIT-safe)
  keep_cols <- c("sig_date", "Ticker", grep("_lag$|_z$|f4_signal|disc_velocity", names(dp), value = TRUE))
  keep_cols <- intersect(keep_cols, names(dp))
  dp <- dp[, ..keep_cols]
  # Rename feature cols with panel prefix
  feature_cols <- setdiff(keep_cols, c("sig_date", "Ticker", "Sector_Lv2"))
  for (fc in feature_cols) {
    new_name <- paste0("wt007_", panel_id, "_", fc)
    setnames(dp, fc, new_name)
    b_features <- c(b_features, new_name)
    reg_add(new_name, "WT-D20260514_007",
            switch(panel_id, f1="D", f2="D", f3="Macro", f4="Macro_Sector", f5="Disclosure"),
            switch(panel_id,
                   f1 = "Bali-Engle-Murray 2016; Amaya-Christoffersen-Jacobs-Vasquez 2015 JFE",
                   f2 = "Ang-Hodrick-Xing-Zhang 2006 JF",
                   f3 = "Fama-French 1993; Adrian-Etula-Muir 2014 JF",
                   f4 = "Cohen-Frazzini 2008 JF (customer-supplier)",
                   f5 = "Da-Engelberg-Gao 2011 JF (attention proxy via DART)"),
            "C2 (panel already lagged at WT_007 build time)",
            b_files[[panel_id]], "inherited from WT_007 (lagged + z-scored)")
  }
  if ("Sector_Lv2" %in% names(dp)) dp[, Sector_Lv2 := NULL]
  layer_b <- merge(layer_b, dp, by = c("sig_date", "Ticker"), all.x = TRUE)
}
cat("  Layer B:", nrow(layer_b), "rows,", length(b_features), "features\n")
write_parquet(layer_b, file.path(OUT_DIR, "layer_b_wt007_inherit.parquet"))
}  # end Layer B resume branch

# ----------------------------------------------------------------------
# 4. Layer C: Factor DB Daily gap 29 (daily → month-end snapshot)
# ----------------------------------------------------------------------
cat("\n[Layer C] Factor DB Daily gap 29 monthly aggregate...\n")
LAYER_C_PATH <- file.path(OUT_DIR, "layer_c_factor_db_daily_gap.parquet")
if (file.exists(LAYER_C_PATH)) {
  cat("  [resume] Layer C exists, loading...\n")
  layer_c <- as.data.table(read_parquet(LAYER_C_PATH))
  setkey(layer_c, sig_date, Ticker)
  c_features <- setdiff(names(layer_c), c("sig_date", "Ticker"))
  for (fname in c_features) {
    orig <- str_replace(fname, "^fdb_d_", "")
    reg_add(fname, "Factor DB Daily 309 (gap retrieve)",
            str_extract(orig, "^[A-Z]+|^[a-z]+"), "Factor DB Daily v10.0",
            "C2 (last day <= sig_date snapshot)",
            ".cache/factor_db_daily/", paste0("daily ", orig, " month-end snapshot"))
  }
  cat("  Layer C loaded:", nrow(layer_c), "rows,", length(c_features), "features\n")
} else {
reg_daily <- fromJSON(".cache/factor_db_daily/factor_db_daily_registry.json")
monthly_factors <- factor_names_monthly
daily_gap <- setdiff(reg_daily$factor_list, monthly_factors)
cat("  Daily-only gap factors:", length(daily_gap), "\n")

# Per sig_date: read daily parquet for that month, take last available day <= sig_date, t-1 lag
layer_c_list <- vector("list", length(sig_dates))
sig_months <- format(sig_dates, "%Y%m")
unique_months <- unique(sig_months)

# Pre-load daily parquets per month (cache once)
for (i in seq_along(sig_dates)) {
  sd <- sig_dates[i]
  ym <- format(sd, "%Y%m")
  dp_file <- sprintf(".cache/factor_db_daily/fdb_daily_%s.parquet", ym)
  if (!file.exists(dp_file)) next
  dp <- as.data.table(read_parquet(dp_file))
  # Pick last available date <= sd (t-1 PIT — use latest day strictly < sd+1, i.e., <= sd close)
  dp_lag <- dp[Date <= sd]
  if (nrow(dp_lag) == 0) next
  setorder(dp_lag, Ticker, Date)
  # For each Ticker take the last row <= sd
  dp_snap <- dp_lag[, .SD[.N], by = Ticker]
  # Keep only gap factors that exist
  daily_gap_avail <- intersect(daily_gap, names(dp_snap))
  if (length(daily_gap_avail) == 0) next
  dp_snap <- dp_snap[, c("Ticker", daily_gap_avail), with = FALSE]
  # Rename with fdb_d_ prefix
  for (fc in daily_gap_avail) setnames(dp_snap, fc, paste0("fdb_d_", fc))
  dp_snap[, sig_date := sd]
  layer_c_list[[i]] <- dp_snap
  if (i %% 20 == 0) cat("  ... daily month", i, "/", length(sig_dates), "\n")
}
layer_c <- rbindlist(layer_c_list, fill = TRUE, use.names = TRUE)
if (nrow(layer_c) > 0) {
  setkey(layer_c, sig_date, Ticker)
  layer_c <- layer_c[universe_panel[, .(sig_date, Ticker)], on = c("sig_date", "Ticker"), nomatch = 0L]
}
cat("  Layer C:", nrow(layer_c), "rows,", ncol(layer_c) - 2, "features\n")
# Register
c_features <- setdiff(names(layer_c), c("sig_date", "Ticker"))
for (fname in c_features) {
  orig <- str_replace(fname, "^fdb_d_", "")
  reg_add(fname, "Factor DB Daily 309 (gap retrieve)",
          str_extract(orig, "^[A-Z]+|^[a-z]+"), "Factor DB Daily v10.0",
          "C2 (last day <= sig_date snapshot)",
          ".cache/factor_db_daily/", paste0("daily ", orig, " month-end snapshot"))
}
write_parquet(layer_c, file.path(OUT_DIR, "layer_c_factor_db_daily_gap.parquet"))
cat("  Saved layer_c_factor_db_daily_gap.parquet\n")
}  # end Layer C resume branch

# ----------------------------------------------------------------------
# 5. Layer D: Daily-aggregate features (~32) from RAWDATA
# ----------------------------------------------------------------------
cat("\n[Layer D] Daily-aggregate features...\n")
LAYER_D_PATH <- file.path(OUT_DIR, "layer_d_daily_aggregate.parquet")
if (file.exists(LAYER_D_PATH)) {
  cat("  [resume] Layer D exists, loading...\n")
  layer_d <- as.data.table(read_parquet(LAYER_D_PATH))
  setkey(layer_d, sig_date, Ticker)
  d_features <- setdiff(names(layer_d), c("sig_date", "Ticker"))
  cat("  Layer D loaded:", nrow(layer_d), "rows,", length(d_features), "features\n")
} else {
# For each sig_date, look back 22 days (1 month trading) — compute realized stats per Ticker
# Strict PIT: features computed from Date <= sig_date only

compute_daily_aggregate <- function(sd) {
  # Window: 22 trading days, 66 trading days, 132 trading days
  win22 <- rd_full[Date <= sd & Date >= sd - 35, ]
  if (nrow(win22) == 0) return(NULL)
  setorder(win22, Ticker, Date)
  # Take last 22 days per Ticker
  win22 <- win22[, .SD[.N >= 22, tail(.SD, 22), .SDcols = c("Date","Close","High","Low","Vol","Ret","BM_Ret")], by = Ticker]
  if (nrow(win22) == 0) return(NULL)

  safe_num <- function(x) {
    if (length(x) == 0) return(NA_real_)
    v <- suppressWarnings(as.numeric(x))
    if (length(v) == 0 || !is.finite(v[1])) return(NA_real_)
    v[1]
  }
  agg <- win22[, .(
    # Realized vol/skew/kurt (Andersen-Bollerslev-Diebold-Labys 2003 RFS)
    d_rv_22d         = safe_num(sqrt(sum(Ret^2, na.rm = TRUE))),
    d_rskew_22d      = safe_num(if (sum(!is.na(Ret)) >= 10) moments::skewness(Ret, na.rm = TRUE) else NA_real_),
    d_rkurt_22d      = safe_num(if (sum(!is.na(Ret)) >= 10) moments::kurtosis(Ret, na.rm = TRUE) else NA_real_),
    # Amihud illiquidity (Amihud 2002 JFM)
    d_amihud_22d     = safe_num(mean(abs(Ret) / (Vol * Close + 1), na.rm = TRUE)),
    # Max DD within window (path-dependent intra-month)
    d_mdd_22d        = safe_num({
      cum <- cumprod(1 + ifelse(is.na(Ret), 0, Ret))
      runmax <- cummax(cum)
      mindd <- min((cum / runmax) - 1, na.rm = TRUE)
      mindd
    }),
    # Winning days ratio
    d_winrate_22d    = safe_num(mean(Ret > 0, na.rm = TRUE)),
    # Daily autocorr AR1
    d_ar1_22d        = safe_num(if (sum(!is.na(Ret)) >= 10) suppressWarnings(cor(Ret[-length(Ret)], Ret[-1], use = "complete.obs")) else NA_real_),
    # Max return (Bali-Cakici-Whitelaw 2011 JFE)
    d_maxret_22d     = safe_num(max(Ret, na.rm = TRUE)),
    # Min return (downside)
    d_minret_22d     = safe_num(min(Ret, na.rm = TRUE)),
    # 52-week high distance (252d high)
    d_close          = safe_num(tail(Close, 1)),
    # Turnover variance
    d_turnover_var   = safe_num(sd(Vol * Close, na.rm = TRUE)),
    d_turnover_mean  = safe_num(mean(Vol * Close, na.rm = TRUE)),
    # HL range mean
    d_hl_range_22d   = safe_num(mean((High - Low) / Close, na.rm = TRUE)),
    # Run-length: longest consecutive up days
    d_run_up_22d     = safe_num({
      r <- rle(Ret > 0)
      ups <- r$lengths[!is.na(r$values) & r$values]
      if (length(ups) == 0) 0.0 else max(ups)
    }),
    # Beta to market (rough OLS, 22d window)
    d_beta_local_22d = safe_num(if (sum(!is.na(Ret) & !is.na(BM_Ret)) >= 15) {
        suppressWarnings(cov(Ret, BM_Ret, use = "complete.obs") / max(var(BM_Ret, na.rm = TRUE), 1e-12))
      } else NA_real_)
  ), by = Ticker]

  # 52-week high distance (need 252-day window)
  win252 <- rd_full[Date <= sd & Date >= sd - 380]
  setorder(win252, Ticker, Date)
  win252_max <- win252[, .(d_52w_high = max(Close, na.rm = TRUE)), by = Ticker]
  agg <- merge(agg, win252_max, by = "Ticker", all.x = TRUE)
  agg[, d_dist_52w_high := (d_close / d_52w_high) - 1]
  agg[, d_52w_high := NULL]
  agg[, d_close := NULL]

  agg[, sig_date := sd]
  agg
}

layer_d_list <- vector("list", length(sig_dates))
for (i in seq_along(sig_dates)) {
  layer_d_list[[i]] <- compute_daily_aggregate(sig_dates[i])
  if (i %% 20 == 0) cat("  ... daily-agg month", i, "/", length(sig_dates), "\n")
}
layer_d <- rbindlist(layer_d_list, fill = TRUE, use.names = TRUE)
if (nrow(layer_d) > 0) {
  setkey(layer_d, sig_date, Ticker)
  layer_d <- layer_d[universe_panel[, .(sig_date, Ticker)], on = c("sig_date", "Ticker"), nomatch = 0L]
}
cat("  Layer D:", nrow(layer_d), "rows,", ncol(layer_d) - 2, "features\n")
d_features <- setdiff(names(layer_d), c("sig_date", "Ticker"))
write_parquet(layer_d, file.path(OUT_DIR, "layer_d_daily_aggregate.parquet"))
}  # end Layer D resume
d_features <- setdiff(names(layer_d), c("sig_date", "Ticker"))

# Always register D
for (fname in d_features) {
  reg_add(fname, "Daily aggregate from RAWDATA",
          "D_daily_realized",
          switch(fname,
                 d_rv_22d = "Andersen-Bollerslev-Diebold-Labys 2003 RFS",
                 d_rskew_22d = "Amaya-Christoffersen-Jacobs-Vasquez 2015 JFE",
                 d_rkurt_22d = "Bali-Engle-Murray 2016",
                 d_amihud_22d = "Amihud 2002 JFM",
                 d_mdd_22d = "Daniel-Moskowitz 2016 JFE",
                 d_winrate_22d = "Ang-Chen-Xing 2006 RFS",
                 d_ar1_22d = "Lo-MacKinlay 1990 RFS",
                 d_maxret_22d = "Bali-Cakici-Whitelaw 2011 JFE",
                 d_minret_22d = "Bali-Cakici-Whitelaw 2011 JFE (downside)",
                 d_turnover_var = "Chordia-Subrahmanyam 2004",
                 d_turnover_mean = "Lee-Swaminathan 2000 JF",
                 d_hl_range_22d = "Parkinson 1980",
                 d_run_up_22d = "Conrad-Kaul 1998 RFS",
                 d_beta_local_22d = "Frazzini-Pedersen 2014 JFE",
                 d_dist_52w_high = "George-Hwang 2004 JF (52w high)"),
          "C2 (22d trailing window ending at sig_date close)",
          ".cache/rawdata.parquet", paste0(fname, " from 22d RAWDATA window"))
}

# ----------------------------------------------------------------------
# 6. Layer E: Macro 22 FRED + ECOS (t-1 lag, monthly resample)
#    + Per-Ticker macro beta (60m rolling regression top 5 macros)
# ----------------------------------------------------------------------
cat("\n[Layer E] Macro features (FRED + ECOS)...\n")
LAYER_E_PATH <- file.path(OUT_DIR, "layer_e_macro.parquet")
if (file.exists(LAYER_E_PATH)) {
  cat("  [resume] Layer E exists, loading...\n")
  layer_e <- as.data.table(read_parquet(LAYER_E_PATH))
  setkey(layer_e, sig_date, Ticker)
  e_features <- setdiff(names(layer_e), c("sig_date", "Ticker"))
  cat("  Layer E loaded:", nrow(layer_e), "rows,", length(e_features), "features\n")
} else {
fred <- as.data.table(read_parquet(".cache/fred_macro.parquet"))
fred[, Date := as.Date(Date)]
setorder(fred, Series_ID, Date)
# Pivot fred wider: Date × Series_ID
fred_w <- dcast(fred, Date ~ Series_ID, value.var = "Value", fun.aggregate = mean, na.rm = TRUE)
setkey(fred_w, Date)
# Forward fill NA
for (col in setdiff(names(fred_w), "Date")) {
  fred_w[, (col) := zoo::na.locf(get(col), na.rm = FALSE)]
}

# ECOS bond rates (wide)
eb <- as.data.table(read_parquet(".cache/ecos_bond_rates.parquet"))
eb[, Date := as.Date(Date)]
eb_w <- dcast(eb, Date ~ Series, value.var = "Value", fun.aggregate = mean, na.rm = TRUE)
setkey(eb_w, Date)
for (col in setdiff(names(eb_w), "Date")) {
  eb_w[, (col) := zoo::na.locf(get(col), na.rm = FALSE)]
}

# ECOS KRW_USD
ek <- as.data.table(read_parquet(".cache/ecos_krw_usd.parquet"))
ek[, Date := as.Date(Date)]
setkey(ek, Date)
ek[, KRW_USD := zoo::na.locf(KRW_USD, na.rm = FALSE)]

# Per sig_date: snapshot macro at sd - 1 day (t-1 PIT)
layer_e_list <- vector("list", length(sig_dates))
fred_cols <- setdiff(names(fred_w), "Date")
eb_cols <- setdiff(names(eb_w), "Date")
for (i in seq_along(sig_dates)) {
  sd <- sig_dates[i]
  sd_lag <- sd - 1L  # t-1 PIT
  # Last available <= sd_lag
  fred_snap <- fred_w[Date <= sd_lag][.N]
  eb_snap <- eb_w[Date <= sd_lag][.N]
  ek_snap <- ek[Date <= sd_lag][.N]
  # 1-month change for diff features (sd_lag - 30 vs sd_lag)
  fred_snap_m1 <- fred_w[Date <= sd_lag - 28][.N]
  eb_snap_m1 <- eb_w[Date <= sd_lag - 28][.N]
  ek_snap_m1 <- ek[Date <= sd_lag - 28][.N]

  row <- list(sig_date = sd)
  for (col in fred_cols) {
    v_now <- fred_snap[[col]]
    v_m1  <- fred_snap_m1[[col]]
    row[[paste0("macro_fred_", col)]] <- v_now
    row[[paste0("macro_fred_", col, "_chg1m")]] <- if (!is.na(v_now) && !is.na(v_m1) && v_m1 != 0) v_now - v_m1 else NA_real_
  }
  for (col in eb_cols) {
    v_now <- eb_snap[[col]]
    v_m1  <- eb_snap_m1[[col]]
    row[[paste0("macro_ecos_", col)]] <- v_now
    row[[paste0("macro_ecos_", col, "_chg1m")]] <- if (!is.na(v_now) && !is.na(v_m1) && v_m1 != 0) v_now - v_m1 else NA_real_
  }
  v_now <- ek_snap$KRW_USD
  v_m1  <- ek_snap_m1$KRW_USD
  row[["macro_ecos_KRW_USD"]] <- v_now
  row[["macro_ecos_KRW_USD_chg1m"]] <- if (!is.na(v_now) && !is.na(v_m1) && v_m1 != 0) (v_now / v_m1) - 1 else NA_real_

  layer_e_list[[i]] <- as.data.table(row)
}
layer_e_macro <- rbindlist(layer_e_list, fill = TRUE, use.names = TRUE)
cat("  Layer E (macro panel):", nrow(layer_e_macro), "sig_date rows,", ncol(layer_e_macro) - 1, "macro features\n")

# Cross-join with universe (broadcast macro to all tickers)
layer_e <- universe_panel[, .(sig_date, Ticker)][layer_e_macro, on = "sig_date", nomatch = 0L]
setkey(layer_e, sig_date, Ticker)
cat("  Layer E broadcast:", nrow(layer_e), "rows,", ncol(layer_e) - 2, "features\n")
write_parquet(layer_e, file.path(OUT_DIR, "layer_e_macro.parquet"))
}  # end Layer E resume
e_features <- setdiff(names(layer_e), c("sig_date", "Ticker"))

# Always register E
for (fname in e_features) {
  reg_add(fname, "Macro (FRED + ECOS)",
          "Macro",
          if (grepl("VIXCLS", fname)) "Whaley 2000 (VIX)"
          else if (grepl("T10Y2Y", fname)) "Estrella-Hardouvelis 1991 JF (term spread)"
          else if (grepl("DGS", fname)) "Federal Reserve H.15"
          else if (grepl("BAML", fname)) "Adrian-Etula-Muir 2014 JF (credit spread)"
          else if (grepl("UNRATE", fname)) "BLS Employment Situation"
          else if (grepl("CPIAUCSL", fname)) "BLS CPI"
          else if (grepl("ecos_", fname)) "BOK ECOS"
          else "FRED/ECOS macro snapshot",
          "C2/C11 (t-1 day lag, last available <= sig_date - 1)",
          ".cache/fred_macro.parquet / .cache/ecos_*",
          paste0(fname, " t-1 snapshot or 1m diff"))
}

# ----------------------------------------------------------------------
# Save intermediate so we can resume from here
# ----------------------------------------------------------------------
cat("\n[Checkpoint 1] Saving registry so far... features so far:", length(registry), "\n")
saveRDS(registry, file.path(OUT_DIR, "_registry_checkpoint1.rds"))

cat("\n[Build script Part 1 complete]\n")
cat("Layer A (Factor DB monthly):", length(factor_names_monthly), "\n")
cat("Layer B (WT_007 inherit):", length(b_features), "\n")
cat("Layer C (Factor DB daily gap):", length(c_features), "\n")
cat("Layer D (daily aggregate):", length(d_features), "\n")
cat("Layer E (macro):", length(e_features), "\n")
cat("Total base features so far:", length(registry), "\n")

# ----------------------------------------------------------------------
# 7. Assemble base panel (A + B + C + D + E join)
# ----------------------------------------------------------------------
cat("\n[Assembly] Merging Layers A-E base panel...\n")
base_panel <- universe_panel[, .(sig_date, Ticker, Sector_Lv2)]
# Rename Layer A factor cols with fdb_m_ prefix
la <- copy(layer_a)
for (fn in factor_names_monthly) setnames(la, fn, paste0("fdb_m_", fn))
base_panel <- merge(base_panel, la, by = c("sig_date", "Ticker"), all.x = TRUE)
base_panel <- merge(base_panel, layer_b, by = c("sig_date", "Ticker"), all.x = TRUE)
base_panel <- merge(base_panel, layer_c, by = c("sig_date", "Ticker"), all.x = TRUE)
base_panel <- merge(base_panel, layer_d, by = c("sig_date", "Ticker"), all.x = TRUE)
base_panel <- merge(base_panel, layer_e, by = c("sig_date", "Ticker"), all.x = TRUE)
setkey(base_panel, sig_date, Ticker)
cat("  Base panel:", nrow(base_panel), "rows,", ncol(base_panel) - 3, "base features\n")

base_cols <- setdiff(names(base_panel), c("sig_date", "Ticker", "Sector_Lv2"))
cat("  Total registered base features:", length(registry), "  base_cols (actual):", length(base_cols), "\n")

# ----------------------------------------------------------------------
# 8. Layer F: Interaction terms top-K (Kelly-Malamud-Zhou 2024 JoF)
#    Strategy: top 10 base × top 10 base (pairwise products) ~ 45 unique pairs
#           + top 10 base × 10 sectors (one-hot encoded) ~ 100
#           = ~145 interaction features
# ----------------------------------------------------------------------
cat("\n[Layer F] Interactions (top-K factor × factor + factor × sector)...\n")

# Choose top 10 base features by lowest missing rate within universe + high cross-sectional variance
# (NOT IC — IC uses future returns, so use only variance/coverage as proxy for "informative")
sample_idx <- sample(nrow(base_panel), min(50000L, nrow(base_panel)))
base_sample <- base_panel[sample_idx, .SD, .SDcols = c("sig_date", "Ticker", base_cols)]
feat_stats <- data.table(
  feature = base_cols,
  miss_rate = sapply(base_cols, function(c) mean(is.na(base_sample[[c]]))),
  variance  = sapply(base_cols, function(c) {
    v <- suppressWarnings(var(base_sample[[c]], na.rm = TRUE))
    if (!is.finite(v)) NA_real_ else v
  })
)
# Filter: missing < 30%, variance > 1e-12
feat_stats <- feat_stats[miss_rate < 0.3 & variance > 1e-12 & !is.na(variance)]
# Score: variance / (1 + missing) — prefer high variance + low missing
feat_stats[, score := variance / (1 + miss_rate)]
setorder(feat_stats, -score)
# Strongly prefer Factor DB monthly (fdb_m_) z-scored features for interactions (already standardized)
feat_stats[, is_z := grepl("^fdb_m_", feature) | grepl("_z$", feature)]
top_for_interact <- head(feat_stats[is_z == TRUE, feature], 12)
cat("  Top 12 base features for interactions:\n  ", paste(top_for_interact, collapse=", "), "\n")

# F.1: Factor × Factor pairwise interactions (12 × 11 / 2 = 66 unique products)
f_interact_factor <- data.table(sig_date = base_panel$sig_date, Ticker = base_panel$Ticker)
pairs <- combn(top_for_interact, 2, simplify = FALSE)
for (pi in seq_along(pairs)) {
  pp <- pairs[[pi]]
  # Use compact suffix + index to guarantee uniqueness
  p1_short <- gsub("^fdb_m_", "", pp[1])
  p2_short <- gsub("^fdb_m_", "", pp[2])
  fname <- paste0("ix_", substr(p1_short, 1, 25), "_X_", substr(p2_short, 1, 25), "_", sprintf("%02d", pi))
  f_interact_factor[, (fname) := base_panel[[pp[1]]] * base_panel[[pp[2]]]]
  reg_add(fname, "Interaction (factor × factor)", "Interaction",
          "Kelly-Malamud-Zhou 2024 JoF (Virtue of Complexity)",
          "C2 inherited from base factors", "(constructed)", paste0(pp[1], " * ", pp[2]))
}
cat("  F.1 (factor × factor):", length(pairs), "pairs\n")

# F.2: Factor × Sector (top 10 sectors one-hot × top 8 base = 80)
top_sectors <- names(sort(table(base_panel$Sector_Lv2), decreasing = TRUE))[1:10]
top_for_sector_ix <- head(top_for_interact, 8)
sec_idx <- 0L
for (si in seq_along(top_sectors)) {
  sec <- top_sectors[si]
  for (fi in seq_along(top_for_sector_ix)) {
    fb <- top_for_sector_ix[fi]
    sec_short <- gsub("[^A-Za-z0-9]", "", sec)
    if (nchar(sec_short) == 0) sec_short <- "OTHER"
    sec_short <- substr(sec_short, 1, 12)
    fbs <- gsub("^fdb_m_", "", fb)
    fbs <- substr(fbs, 1, 25)
    sec_idx <- sec_idx + 1L
    fname <- paste0("ixsec_", sec_short, "_X_", fbs, "_", sprintf("%03d", sec_idx))
    f_interact_factor[, (fname) := ifelse(base_panel$Sector_Lv2 == sec, base_panel[[fb]], 0)]
    reg_add(fname, "Interaction (factor × sector)", "Interaction",
            "Cohen-Frazzini-Pollet 2010 JFE (industry segmentation)",
            "C2 inherited", "(constructed)",
            paste0("indicator(Sector_Lv2==", sec, ") * ", fb))
  }
}
cat("  F.2 (factor × top 10 sector × top 8 factor):", length(top_sectors)*length(top_for_sector_ix), "\n")

setkey(f_interact_factor, sig_date, Ticker)
write_parquet(f_interact_factor, file.path(OUT_DIR, "layer_f_interactions.parquet"))
f_features <- setdiff(names(f_interact_factor), c("sig_date", "Ticker"))
cat("  Layer F total:", length(f_features), "interaction features\n")

# ----------------------------------------------------------------------
# 9. Layer G: Lag features (1m / 3m / 6m / 12m × top 50 base)
# ----------------------------------------------------------------------
cat("\n[Layer G] Lag features (1/3/6/12m × top 50 base)...\n")
# Pick top 50 from feat_stats (high score, low missing, z-scored or numerical features)
top_for_lag <- head(feat_stats$feature, 50)
cat("  Top 50 base for lag selected\n")

# Compute lag features: group by Ticker, sort by sig_date, shift
g_panel <- base_panel[, c("sig_date", "Ticker", top_for_lag), with = FALSE]
setkey(g_panel, Ticker, sig_date)
lag_horizons <- c(1L, 3L, 6L, 12L)
for (lh in lag_horizons) {
  for (bf in top_for_lag) {
    fname <- paste0(substr(bf, 1, 40), "_lag", lh, "m")
    # data.table shift by Ticker
    g_panel[, (fname) := shift(get(bf), n = lh, type = "lag"), by = Ticker]
    reg_add(fname, paste0("Lag (", lh, "m)"), "Lag",
            "Lo-MacKinlay 1990 RFS (autocorrelation features)",
            paste0("C2 (lag ", lh, " months from base sig_date)"),
            "(constructed)", paste0(bf, " shifted by ", lh, " months per Ticker"))
  }
  cat("  ... lag ", lh, "m done\n")
}
g_features <- setdiff(names(g_panel), c("sig_date", "Ticker", top_for_lag))
cat("  Layer G total:", length(g_features), "lag features\n")
# Save without base cols (keep only lag features + keys)
g_panel_save <- g_panel[, c("sig_date", "Ticker", g_features), with = FALSE]
setkey(g_panel_save, sig_date, Ticker)
write_parquet(g_panel_save, file.path(OUT_DIR, "layer_g_lags.parquet"))

# ----------------------------------------------------------------------
# 10. Layer H: Rolling statistics (mean/std/skew × 5 windows × top 15 base)
#     5 windows: 3m, 6m, 12m, 24m, 36m
#     3 stats × 5 windows × 15 base = 225 features
# ----------------------------------------------------------------------
cat("\n[Layer H] Rolling statistics (3 stats × 5 windows × top 15 base)...\n")
top_for_roll <- head(top_for_lag, 15)
roll_windows <- c(3L, 6L, 12L, 24L, 36L)
h_panel <- base_panel[, c("sig_date", "Ticker", top_for_roll), with = FALSE]
setkey(h_panel, Ticker, sig_date)

safe_sd_scalar <- function(x) {
  v <- suppressWarnings(sd(x, na.rm = TRUE))
  if (length(v) == 0 || !is.finite(v[1])) return(NA_real_)
  as.numeric(v[1])
}
safe_skew_scalar <- function(x) {
  x2 <- x[!is.na(x)]
  if (length(x2) < 3) return(NA_real_)
  v <- suppressWarnings(moments::skewness(x2))
  if (length(v) == 0 || !is.finite(v[1])) return(NA_real_)
  as.numeric(v[1])
}

# Per-Ticker rolling apply using a manual loop (avoids frollapply group-size issue)
manual_roll <- function(x, w, FUN) {
  n <- length(x)
  out <- rep(NA_real_, n)
  if (n >= w) {
    for (i in w:n) {
      out[i] <- FUN(x[(i - w + 1):i])
    }
  }
  out
}

for (bf in top_for_roll) {
  bfs <- substr(bf, 1, 30)
  for (w in roll_windows) {
    fname_mean <- paste0(bfs, "_rmean", w, "m")
    fname_sd   <- paste0(bfs, "_rsd", w, "m")
    fname_skew <- paste0(bfs, "_rskew", w, "m")
    # mean — frollmean is safe (always returns same length)
    h_panel[, (fname_mean) := frollmean(get(bf), n = w, align = "right", na.rm = TRUE), by = Ticker]
    # sd and skew via manual_roll (guaranteed same-length return)
    h_panel[, (fname_sd)   := manual_roll(get(bf), w, safe_sd_scalar), by = Ticker]
    h_panel[, (fname_skew) := manual_roll(get(bf), w, safe_skew_scalar), by = Ticker]
    for (fn in c(fname_mean, fname_sd, fname_skew)) {
      stat_type <- if (grepl("rmean", fn)) "mean" else if (grepl("rsd", fn)) "sd" else "skew"
      reg_add(fn, paste0("Rolling (", w, "m, ", stat_type, ")"), "Rolling",
              "Asness-Frazzini-Pedersen 2019 RFS (time-varying factor exposure)",
              paste0("C1 rolling ", w, "m window ending at sig_date"),
              "(constructed)", paste0(stat_type, "(", bf, ") rolling ", w, "m"))
    }
  }
  cat("  ... rolling base", which(top_for_roll == bf), "/", length(top_for_roll), "done\n")
}
h_features <- setdiff(names(h_panel), c("sig_date", "Ticker", top_for_roll))
cat("  Layer H total:", length(h_features), "rolling features\n")
h_panel_save <- h_panel[, c("sig_date", "Ticker", h_features), with = FALSE]
setkey(h_panel_save, sig_date, Ticker)
write_parquet(h_panel_save, file.path(OUT_DIR, "layer_h_rolling.parquet"))

# ----------------------------------------------------------------------
# 11. Layer I: Sector × top 5 base dummies + Regime dummies
#     10 sectors × 5 base = 50 dummies (orthogonal to Layer F)
#     4 regimes (BULL/NORMAL/CAUTION/CRISIS) × top 5 = 20
#     Total = 70
# ----------------------------------------------------------------------
cat("\n[Layer I] Sector × top 5 + Regime × top 5 dummies...\n")
i_panel <- base_panel[, .(sig_date, Ticker, Sector_Lv2)]
top_for_dummy <- head(top_for_interact, 5)

# Sector dummies (top 10 sectors)
for (sec in top_sectors) {
  sec_short <- substr(gsub("[^A-Za-z0-9]", "", sec), 1, 15)
  if (nchar(sec_short) == 0) sec_short <- "OTHER"
  dname <- paste0("sec_", sec_short, "_dummy")
  i_panel[, (dname) := as.integer(Sector_Lv2 == sec)]
  reg_add(dname, "Sector dummy", "Dummy",
          "Cohen-Frazzini-Pollet 2010 JFE",
          "C2 (sector at sig_date from RAWDATA Sector_Lv2)",
          ".cache/rawdata.parquet", paste0("I(Sector_Lv2 == ", sec, ")"))
}

# Sector-conditional top 5 features
sd_idx <- 0L
for (si in seq_along(head(top_sectors, 8))) {
  sec <- top_sectors[si]
  sec_short <- substr(gsub("[^A-Za-z0-9]", "", sec), 1, 12)
  if (nchar(sec_short) == 0) sec_short <- "OTHER"
  for (fi in seq_along(top_for_dummy)) {
    fb <- top_for_dummy[fi]
    fbs <- gsub("^fdb_m_", "", fb)
    fbs <- substr(fbs, 1, 22)
    sd_idx <- sd_idx + 1L
    fname <- paste0("secdum_", sec_short, "_", fbs, "_", sprintf("%03d", sd_idx))
    i_panel[, (fname) := ifelse(base_panel$Sector_Lv2 == sec, base_panel[[fb]], 0)]
    reg_add(fname, "Sector-conditional feature", "Dummy",
            "Cohen-Frazzini-Pollet 2010 JFE",
            "C2 inherited", "(constructed)",
            paste0("I(Sector_Lv2==", sec, ") * ", fb, " (else 0)"))
  }
}

# Regime dummies from FRED VIX (using same sig_date macro snapshot)
# 4 regimes: VIX < 15 (BULL), 15-22 (NORMAL), 22-30 (CAUTION), >=30 (CRISIS)
vix_col <- "macro_fred_VIXCLS"
if (vix_col %in% names(base_panel)) {
  vix_vals <- base_panel[[vix_col]]
  i_panel[, regime_bull    := as.integer(!is.na(vix_vals) & vix_vals < 15)]
  i_panel[, regime_normal  := as.integer(!is.na(vix_vals) & vix_vals >= 15 & vix_vals < 22)]
  i_panel[, regime_caution := as.integer(!is.na(vix_vals) & vix_vals >= 22 & vix_vals < 30)]
  i_panel[, regime_crisis  := as.integer(!is.na(vix_vals) & vix_vals >= 30)]
  for (r in c("regime_bull", "regime_normal", "regime_caution", "regime_crisis")) {
    reg_add(r, "Regime dummy (VIX-based)", "Dummy_Regime",
            "Ang-Bekaert 2002 RFS (regime-conditional)",
            "C2/C11 (FRED VIX t-1 lag)", ".cache/fred_macro.parquet",
            paste0("I(VIX_t-1 in [", r, "] bucket)"))
  }
  # Regime × top 5 base (4 × 5 = 20)
  rd_idx <- 0L
  for (rname in c("regime_bull", "regime_normal", "regime_caution", "regime_crisis")) {
    for (fi in seq_along(top_for_dummy)) {
      fb <- top_for_dummy[fi]
      fbs <- gsub("^fdb_m_", "", fb)
      fbs <- substr(fbs, 1, 22)
      rd_idx <- rd_idx + 1L
      fname <- paste0("regdum_", str_replace(rname, "regime_", ""), "_", fbs, "_", sprintf("%03d", rd_idx))
      i_panel[, (fname) := i_panel[[rname]] * base_panel[[fb]]]
      reg_add(fname, "Regime-conditional feature", "Dummy_Regime",
              "Ang-Bekaert 2002 RFS",
              "C2/C11 inherited", "(constructed)",
              paste0(rname, " * ", fb))
    }
  }
}

i_features <- setdiff(names(i_panel), c("sig_date", "Ticker", "Sector_Lv2"))
cat("  Layer I total:", length(i_features), "dummy features\n")
i_panel_save <- i_panel[, c("sig_date", "Ticker", i_features), with = FALSE]
setkey(i_panel_save, sig_date, Ticker)
write_parquet(i_panel_save, file.path(OUT_DIR, "layer_i_dummies.parquet"))

# ----------------------------------------------------------------------
# 12. Final assembly: features_master.parquet
# ----------------------------------------------------------------------
cat("\n[Final Assembly] features_master.parquet...\n")
fm <- base_panel
fm <- merge(fm, f_interact_factor, by = c("sig_date", "Ticker"), all.x = TRUE)
fm <- merge(fm, g_panel_save, by = c("sig_date", "Ticker"), all.x = TRUE)
fm <- merge(fm, h_panel_save, by = c("sig_date", "Ticker"), all.x = TRUE)
fm <- merge(fm, i_panel_save, by = c("sig_date", "Ticker"), all.x = TRUE)
setkey(fm, sig_date, Ticker)

n_features <- ncol(fm) - 3
cat("  features_master:", nrow(fm), "rows,", n_features, "features\n")
write_parquet(fm, file.path(OUT_DIR, "features_master.parquet"))

# ----------------------------------------------------------------------
# 13. feature_registry.json
# ----------------------------------------------------------------------
cat("\n[Output] feature_registry.json (", length(registry), "entries)...\n")
write_json(registry, file.path(OUT_DIR, "feature_registry.json"), pretty = TRUE, auto_unbox = TRUE)

# ----------------------------------------------------------------------
# 14. feature_quality_audit.json (variance / missing / cor cluster)
# ----------------------------------------------------------------------
cat("\n[Output] feature_quality_audit.json...\n")
all_features <- setdiff(names(fm), c("sig_date", "Ticker", "Sector_Lv2"))

# Sample for audit (50k rows max)
audit_idx <- sample(nrow(fm), min(50000L, nrow(fm)))
audit_sample <- fm[audit_idx, .SD, .SDcols = c("sig_date", "Ticker", all_features)]

quality_list <- list()
for (i in seq_along(all_features)) {
  fn <- all_features[i]
  x <- audit_sample[[fn]]
  v <- suppressWarnings(sd(x, na.rm = TRUE))
  if (!is.finite(v)) v <- NA_real_
  mr <- mean(is.na(x))
  q <- list(
    feature_id = fn,
    variance_sd = round(as.numeric(v), 6),
    missing_rate = round(as.numeric(mr), 4),
    n_obs = sum(!is.na(x))
  )
  # Screening recommendation
  if (is.na(v) || v < 1e-10) {
    q$screening_recommendation <- "DROP_zero_variance"
  } else if (mr > 0.5) {
    q$screening_recommendation <- "DROP_high_missing"
  } else if (mr > 0.3) {
    q$screening_recommendation <- "VARIANT_check_pit"
  } else {
    q$screening_recommendation <- "KEEP"
  }
  quality_list[[i]] <- q
  if (i %% 200 == 0) cat("  ... audited feature", i, "/", length(all_features), "\n")
}

# Pairwise cor cluster head detection (sample top 200 high-variance features only — too expensive for all)
cat("  Computing pairwise correlation for top 200 features (cluster head detection)...\n")
qdt <- as.data.table(do.call(rbind, lapply(quality_list, as.data.table)))
qdt_kept <- qdt[screening_recommendation %in% c("KEEP", "VARIANT_check_pit")]
setorder(qdt_kept, -variance_sd)
top200 <- head(qdt_kept$feature_id, 200)

cor_mat <- tryCatch({
  m <- as.matrix(audit_sample[, ..top200])
  cor(m, use = "pairwise.complete.obs")
}, error = function(e) {
  cat("  cor matrix failed:", conditionMessage(e), "\n")
  NULL
})

cluster_heads <- character(0)
if (!is.null(cor_mat)) {
  # Greedy cluster head: walk through features in variance order, mark as head if no high cor to existing head
  for (f in top200) {
    is_dup <- FALSE
    for (h in cluster_heads) {
      cc <- cor_mat[f, h]
      if (!is.na(cc) && abs(cc) > 0.99) {
        is_dup <- TRUE
        break
      }
    }
    if (!is_dup) cluster_heads <- c(cluster_heads, f)
  }
  cat("  Cluster heads (cor<0.99 unique among top 200):", length(cluster_heads), "/ 200\n")
}

# Add cluster_head flag to quality_list
ch_set <- cluster_heads
quality_list <- lapply(quality_list, function(q) {
  if (q$feature_id %in% top200) {
    q$cluster_head_top200 <- q$feature_id %in% ch_set
  }
  q
})

# Summary
n_keep    <- sum(sapply(quality_list, function(q) q$screening_recommendation == "KEEP"))
n_variant <- sum(sapply(quality_list, function(q) q$screening_recommendation == "VARIANT_check_pit"))
n_drop_zv <- sum(sapply(quality_list, function(q) q$screening_recommendation == "DROP_zero_variance"))
n_drop_mr <- sum(sapply(quality_list, function(q) q$screening_recommendation == "DROP_high_missing"))

audit_summary <- list(
  task_id = "WT-D20260514_008",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  total_features = length(all_features),
  n_sig_dates = length(sig_dates),
  n_tickers_avg = round(nrow(universe_panel) / length(sig_dates), 0),
  n_rows_master = nrow(fm),
  screening_summary = list(
    KEEP = n_keep,
    VARIANT_check_pit = n_variant,
    DROP_zero_variance = n_drop_zv,
    DROP_high_missing = n_drop_mr
  ),
  cluster_heads_top200 = length(cluster_heads),
  layer_counts = list(
    A_factor_db_monthly = length(factor_names_monthly),
    B_wt007_inherit = length(b_features),
    C_factor_db_daily_gap = length(c_features),
    D_daily_aggregate = length(d_features),
    E_macro = length(e_features),
    F_interactions = length(f_features),
    G_lags = length(g_features),
    H_rolling = length(h_features),
    I_dummies = length(i_features)
  ),
  features = quality_list
)

write_json(audit_summary, file.path(OUT_DIR, "feature_quality_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

cat("\n========================================\n")
cat("WT-D20260514_008 features pool 보완 구축 완료\n")
cat("========================================\n")
cat("Total features:", n_features, "\n")
cat("  Layer A (Factor DB monthly):", length(factor_names_monthly), "\n")
cat("  Layer B (WT_007 inherit):", length(b_features), "\n")
cat("  Layer C (Factor DB daily gap):", length(c_features), "\n")
cat("  Layer D (daily aggregate):", length(d_features), "\n")
cat("  Layer E (macro):", length(e_features), "\n")
cat("  Layer F (interactions):", length(f_features), "\n")
cat("  Layer G (lags):", length(g_features), "\n")
cat("  Layer H (rolling):", length(h_features), "\n")
cat("  Layer I (dummies):", length(i_features), "\n")
cat("\nQuality audit:\n")
cat("  KEEP:", n_keep, "\n")
cat("  VARIANT_check_pit:", n_variant, "\n")
cat("  DROP_zero_variance:", n_drop_zv, "\n")
cat("  DROP_high_missing:", n_drop_mr, "\n")
cat("  Cluster heads (top 200 cor<0.99):", length(cluster_heads), "\n")
cat("\nOutput files:\n")
cat("  ", file.path(OUT_DIR, "features_master.parquet"), "\n")
cat("  ", file.path(OUT_DIR, "feature_registry.json"), "\n")
cat("  ", file.path(OUT_DIR, "feature_quality_audit.json"), "\n")
cat("\n[Build complete]\n")
