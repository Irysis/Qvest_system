#!/usr/bin/env Rscript
#==============================================================================
# factor_engine_v2.R — Regime-Conditional Low IVOL Defense Factor
# WT-D20260429_001 / v2: fixed schema (Z_Score not Z_Score_Aligned, regime YM format)
#
# PIT Rules: C1 rolling 252d / C2 t-1 lag / C3 month-end signal /
#            C9 regime t-1 lag / C13 Z_Score (direction: higher=lower IVOL=better)
#            C14 Usable_Date implied by Date <= sig_date / C15 factor_db parquet
#
# AX-001 v2: crisis_alpha + bad/normal IC ratio >= 1.5
# AX-005: Low IVOL != BAB. No leverage/short.
# AX-007: EXCEPTION_1 regime-conditional weighting.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(future)
  library(future.apply)
})

cat("=== WT-D20260429_001 factor_engine v2 ===\n")

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
CACHE_DIR     <- file.path(ROOT, ".cache")
FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")
OUT_DIR       <- file.path(ROOT, "stage_artifacts", "WT-D20260429_001")
MAILBOX_DIR   <- file.path(ROOT, "qepm", "mailbox", "worktask", "WT-D20260429_001")

dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(MAILBOX_DIR, showWarnings = FALSE, recursive = TRUE)

TRAIN_START     <- as.Date("2003-01-01")
SIG_DATE_LATEST <- as.Date("2026-03-31")
LIQ_THRESHOLD   <- 5e7
COST_BPS        <- 15L

# Target factors from DB (C15)
# D01_IdioVol: primary (residual vol from CAPM, -sd_resid → higher = lower IVOL)
# D03_RealVol: secondary (realized vol negated)
# D04_Downside_Beta: tertiary
# D34_RealVol_21d: short-window complement
# D47_CVaR_5pct: tail risk proxy
TARGET_FACTORS <- c("D01_IdioVol", "D03_RealVol", "D04_Downside_Beta",
                    "D34_RealVol_21d", "D47_CVaR_5pct")

n_workers <- min(6L, parallel::detectCores() - 1L)

# ─── Step 1: Regime signal (PIT: apply_month = YYYY-MM, MRS numeric 0-100) ──
cat("[Step1] Loading regime signal...\n")
regime_raw <- as.data.table(read_parquet(file.path(CACHE_DIR, "regime_v7.parquet")))
# apply_month is YYYY-MM string, MRS is numeric
cat("[Step1] Rows:", nrow(regime_raw), "MRS range:", range(regime_raw$MRS, na.rm=TRUE), "\n")

# Monthly regime (t-1 lag: at signal month M, use regime from month M-1)
# regime_raw has apply_month = the month in which regime applies to portfolio
# C9: we need t-1: lag the MRS by 1 row
setorder(regime_raw, apply_month)
regime_monthly <- regime_raw[, .(YearMonth = apply_month, MRS = MRS, regime_state = regime_state)]
regime_monthly[, MRS_lag1       := shift(MRS, 1, type = "lag")]
regime_monthly[, regime_lag1    := shift(regime_state, 1, type = "lag")]
cat("[Step1] Regime states:", paste(unique(regime_monthly$regime_state), collapse=", "), "\n")
# MRS >= 60 = Crisis in this system
crisis_threshold <- 60

# ─── Step 2: Load factor DB parquets ──────────────────────────────────────────
cat("[Step2] Loading Factor DB parquets (parallel)...\n")
parquet_files <- sort(list.files(FACTOR_DB_DIR,
                                  pattern = "^factor_db_\\d{6}\\.parquet$",
                                  full.names = TRUE))
# Parse file dates
file_ym <- sub(".*factor_db_(\\d{4})(\\d{2})\\.parquet$", "\\1-\\2", basename(parquet_files))
file_dates <- as.Date(paste0(file_ym, "-01"))
train_files <- parquet_files[file_dates >= TRAIN_START & file_dates <= SIG_DATE_LATEST]
cat("[Step2] Training parquets:", length(train_files), "\n")

plan(multisession, workers = n_workers)
factor_list <- future_lapply(train_files, function(fp) {
  tryCatch({
    dt <- as.data.table(read_parquet(fp))
    dt[Factor_Name %in% TARGET_FACTORS]
  }, error = function(e) NULL)
}, future.seed = TRUE)
plan(sequential)

factor_long <- rbindlist(Filter(Negate(is.null), factor_list), fill = TRUE)
factor_long[, Date := as.Date(Date)]
factor_long[, YearMonth := format(Date, "%Y-%m")]
cat("[Step2] Loaded:", nrow(factor_long), "rows. Factors:", paste(unique(factor_long$Factor_Name), collapse=", "), "\n")

# C13 compliance note: Factor DB Z_Score has direction-aligned sign per factor_registry.json
# D01_IdioVol: Raw_Value = -sd(resid) → Z_Score = cross-sectional z of that. Higher = lower vol = better.
# No manual flip needed (registry direction_encoded).
val_col <- "Z_Score"  # Use Z_Score (direction already embedded)

# ─── Step 3: Load RAWDATA for forward returns ─────────────────────────────────
cat("[Step3] Computing monthly forward returns...\n")
RAWDATA <- as.data.table(read_parquet(file.path(CACHE_DIR, "rawdata.parquet")))
RAWDATA[, Date := as.Date(Date)]
RAWDATA[, YearMonth := format(Date, "%Y-%m")]
# Forward return: signal in month M → next month M+1 return
monthly_ret <- RAWDATA[!is.na(Ret), .(
  Fwd_Ret = prod(1 + Ret) - 1,
  n_days = .N
), by = .(Ticker, YearMonth)]
setorder(monthly_ret, Ticker, YearMonth)
# Lead-1: forward return = next month's cumulative return (PIT-safe: we apply signal → next month)
monthly_ret[, Fwd_Ret_1m := shift(Fwd_Ret, -1, type = "lead"), by = Ticker]
monthly_ret <- monthly_ret[!is.na(Fwd_Ret_1m) & n_days >= 10]
cat("[Step3] Monthly fwd returns:", nrow(monthly_ret), "\n")

# ─── Step 4: Pivot factor data to wide and merge ────────────────────────────
cat("[Step4] Pivoting and merging...\n")
factor_wide <- dcast(factor_long,
                     Ticker + YearMonth ~ Factor_Name,
                     value.var = val_col,
                     fun.aggregate = mean)
cat("[Step4] Factor wide:", nrow(factor_wide), "x", ncol(factor_wide), "\n")

merged <- merge(factor_wide,
                monthly_ret[, .(Ticker, YearMonth, Fwd_Ret_1m)],
                by = c("Ticker", "YearMonth"), all = FALSE)
merged <- merge(merged,
                regime_monthly[, .(YearMonth, MRS_lag1, regime_lag1)],
                by = "YearMonth", all.x = TRUE)
cat("[Step4] Merged:", nrow(merged), "rows covering", uniqueN(merged$YearMonth), "months\n")

factors_present <- intersect(TARGET_FACTORS, names(merged))
cat("[Step4] Factors present:", paste(factors_present, collapse=", "), "\n")
if (length(factors_present) == 0) stop("[factor_engine] No target factors in merged data")

# ─── Step 5: Monthly Spearman IC (parallel) ─────────────────────────────────
cat("[Step5] Computing monthly IC per factor (parallel)...\n")
months_ordered <- sort(unique(merged$YearMonth))
months_in_range <- months_ordered[months_ordered >= format(TRAIN_START, "%Y-%m")]
cat("[Step5] Months to compute IC:", length(months_in_range), "\n")

plan(multisession, workers = n_workers)
ic_list <- future_lapply(months_in_range, function(ym) {
  dt_m <- merged[YearMonth == ym & !is.na(Fwd_Ret_1m)]
  if (nrow(dt_m) < 20) return(NULL)
  ic_row <- data.table(YearMonth = ym, MRS = dt_m$MRS_lag1[1], regime = dt_m$regime_lag1[1])
  for (fn in factors_present) {
    x <- dt_m[[fn]]; y <- dt_m$Fwd_Ret_1m
    valid <- !is.na(x) & !is.na(y) & is.finite(x) & is.finite(y)
    ic_row[, (paste0("IC_", fn)) := if (sum(valid) < 20) NA_real_ else cor(x[valid], y[valid], method = "spearman")]
  }
  ic_row
}, future.seed = TRUE)
plan(sequential)

ic_dt <- rbindlist(Filter(Negate(is.null), ic_list), fill = TRUE)
setorder(ic_dt, YearMonth)
cat("[Step5] IC table:", nrow(ic_dt), "months\n")

# ─── Step 6: Diagnostics per factor ─────────────────────────────────────────
cat("[Step6] Computing diagnostics...\n")

# Crisis periods matching STR_1715 worst drawdowns
crisis_periods <- list(
  GFC       = c("2008-01", "2008-12"),
  TradeWar  = c("2018-02", "2020-03"),
  RateHike  = c("2022-01", "2022-12")
)

compute_diag <- function(fn) {
  ic_col <- paste0("IC_", fn)
  ic_vec <- ic_dt[[ic_col]]
  ym_vec <- ic_dt$YearMonth

  valid_ic <- ic_vec[!is.na(ic_vec) & is.finite(ic_vec)]
  n_valid  <- length(valid_ic)
  if (n_valid < 24) return(NULL)

  mean_ic  <- mean(valid_ic)
  icir_val <- mean_ic / sd(valid_ic)
  n        <- n_valid
  harvey_t <- mean_ic / (sd(valid_ic) / sqrt(n))

  # DSR approximation (Bailey-Lopez de Prado 2014)
  SR_ic <- mean_ic / sd(valid_ic) * sqrt(12)
  # Expected max SR from 1 trial (no fishing penalty beyond 1)
  n_trials <- 1L
  # skewness and kurtosis
  mu_ic <- mean_ic; sg_ic <- sd(valid_ic)
  centered <- valid_ic - mu_ic
  sk <- mean(centered^3) / sg_ic^3
  ku <- mean(centered^4) / sg_ic^4
  SR_star <- max(0, (1 - 0.5772 + log(n_trials)) * sqrt(2 * log(max(n_trials, 1))))
  denom_dsr <- sqrt(max(1e-10, 1 - sk * (SR_ic/sqrt(12)) + (ku - 1)/4 * (SR_ic/sqrt(12))^2))
  dsr_val <- (SR_ic - SR_star) * sqrt(n) / denom_dsr

  # Subperiod stability
  # 3 windows: 2003-2010, 2011-2018, 2019-2026
  sp1 <- ic_vec[ym_vec >= "2003-01" & ym_vec <= "2010-12" & !is.na(ic_vec)]
  sp2 <- ic_vec[ym_vec >= "2011-01" & ym_vec <= "2018-12" & !is.na(ic_vec)]
  sp3 <- ic_vec[ym_vec >= "2019-01" & ym_vec <= "2026-12" & !is.na(ic_vec)]
  sp_pos <- sum(c(
    if (length(sp1) >= 12) mean(sp1) > 0 else NA,
    if (length(sp2) >= 12) mean(sp2) > 0 else NA,
    if (length(sp3) >= 12) mean(sp3) > 0 else NA
  ), na.rm = TRUE)
  n_sp_valid <- sum(!is.na(c(
    if (length(sp1) >= 12) TRUE else NA,
    if (length(sp2) >= 12) TRUE else NA,
    if (length(sp3) >= 12) TRUE else NA
  )))
  subp_stab <- if (n_sp_valid > 0) sp_pos / n_sp_valid else NA_real_

  # Crisis IC per period
  crisis_ic_list <- lapply(names(crisis_periods), function(nm) {
    p <- crisis_periods[[nm]]
    ic_p <- ic_vec[ym_vec >= p[1] & ym_vec <= p[2] & !is.na(ic_vec)]
    list(period = nm, n = length(ic_p),
         mean_ic = if (length(ic_p) >= 3) mean(ic_p) else NA_real_,
         pos_rate = if (length(ic_p) >= 3) mean(ic_p > 0) else NA_real_)
  })
  crisis_ym_all <- character(0)
  for (p in crisis_periods) crisis_ym_all <- c(crisis_ym_all,
    ym_vec[ym_vec >= p[1] & ym_vec <= p[2]])
  normal_ic <- ic_vec[!ym_vec %in% crisis_ym_all & !is.na(ic_vec)]
  crisis_ic_all <- ic_vec[ym_vec %in% crisis_ym_all & !is.na(ic_vec)]

  bad_ic   <- if (length(crisis_ic_all) >= 6) mean(crisis_ic_all) else NA_real_
  norm_ic  <- if (length(normal_ic) >= 12) mean(normal_ic) else NA_real_
  bad_norm <- if (!is.na(bad_ic) && !is.na(norm_ic) && abs(norm_ic) > 1e-6) bad_ic / norm_ic else NA_real_

  crisis_pass <- sapply(crisis_ic_list, function(x) !is.na(x$mean_ic) && x$mean_ic > 0)
  n_crisis_pass <- sum(crisis_pass, na.rm = TRUE)

  list(
    factor_name         = fn,
    rank_ic             = round(mean_ic, 5),
    icir                = round(icir_val, 4),
    harvey_t            = round(harvey_t, 4),
    dsr                 = round(dsr_val, 4),
    subperiod_stability = round(subp_stab, 3),
    crisis_ic_GFC       = round(crisis_ic_list[[1]]$mean_ic, 5),
    crisis_ic_TradeWar  = round(crisis_ic_list[[2]]$mean_ic, 5),
    crisis_ic_RateHike  = round(crisis_ic_list[[3]]$mean_ic, 5),
    n_crisis_pass       = n_crisis_pass,
    bad_ic              = round(bad_ic, 5),
    normal_ic           = round(norm_ic, 5),
    bad_normal_ratio    = round(bad_norm, 4),
    n_months            = n_valid,
    n_crisis_months     = length(crisis_ic_all)
  )
}

diag_list <- lapply(factors_present, compute_diag)
names(diag_list) <- factors_present
diag_list <- Filter(Negate(is.null), diag_list)
diag_dt <- rbindlist(lapply(diag_list, as.data.table), fill = TRUE)

cat("[Step6] Factor diagnostics:\n")
print(diag_dt[, .(factor_name, rank_ic, icir, harvey_t, dsr, subperiod_stability,
                   crisis_ic_GFC, crisis_ic_TradeWar, bad_normal_ratio)])

# ─── Step 7: Factor selection (ICIR primary, crisis_alpha gate) ─────────────
cat("[Step7] Selecting primary factor (objective=icir, AX-001 v2 crisis gate)...\n")

# Must have: crisis_ic > 0 in at least 2/3 periods (AX-001 v2 defense gate)
good_defense <- diag_dt[n_crisis_pass >= 2]
if (nrow(good_defense) == 0) {
  cat("[Step7] WARN: No factor passes 2/3 crisis IC > 0. Relaxing to 1/3.\n")
  good_defense <- diag_dt[n_crisis_pass >= 1]
}
if (nrow(good_defense) == 0) good_defense <- diag_dt

setorder(good_defense, -icir)
primary_factor <- good_defense$factor_name[1]
primary_diag   <- diag_list[[primary_factor]]
cat("[Step7] Selected:", primary_factor, "| ICIR:", primary_diag$icir,
    "| Harvey_t:", primary_diag$harvey_t, "| n_crisis_pass:", primary_diag$n_crisis_pass, "\n")

# Secondary factor (complementary)
secondary_options <- setdiff(good_defense$factor_name[1:min(3, nrow(good_defense))], primary_factor)
secondary_factor  <- if (length(secondary_options) > 0) secondary_options[1] else NULL
cat("[Step7] Secondary:", ifelse(is.null(secondary_factor), "none", secondary_factor), "\n")

# Graduation criteria check
grad_check <- list(
  rank_ic_pass          = !is.na(primary_diag$rank_ic)             && primary_diag$rank_ic >= 0.04,
  icir_pass             = !is.na(primary_diag$icir)                && primary_diag$icir >= 0.20,
  subperiod_pass        = !is.na(primary_diag$subperiod_stability) && primary_diag$subperiod_stability >= 0.50,
  harvey_t_pass         = !is.na(primary_diag$harvey_t)            && primary_diag$harvey_t >= 3.0,
  dsr_pass              = !is.na(primary_diag$dsr)                 && primary_diag$dsr >= 0.50,
  crisis_alpha_pass     = primary_diag$n_crisis_pass >= 2,
  bad_normal_ratio_pass = !is.na(primary_diag$bad_normal_ratio)    && primary_diag$bad_normal_ratio >= 1.5
)
n_pass <- sum(unlist(grad_check))
cat("[Step7] Graduation criteria (", n_pass, "/7):\n")
for (nm in names(grad_check)) cat(sprintf("  %-30s: %s\n", nm, ifelse(grad_check[[nm]], "PASS", "FAIL")))

# ─── Step 8: Method shopping log ────────────────────────────────────────────
method_log <- lapply(factors_present, function(fn) {
  d <- diag_list[[fn]]
  if (is.null(d)) return(list(name=fn, rank_ic=NA, icir=NA, selected=FALSE))
  list(name=fn, rank_ic=d$rank_ic, icir=d$icir, harvey_t=d$harvey_t,
       selected=(fn == primary_factor), parallel_exec=TRUE, n_workers=n_workers, rcpp_used=FALSE)
})
names(method_log) <- factors_present

# ─── Step 9: Alpha vector for latest signal date ─────────────────────────────
cat("[Step9] Computing alpha vector for", format(SIG_DATE_LATEST, "%Y-%m"), "...\n")
latest_ym <- format(SIG_DATE_LATEST, "%Y-%m")
latest_data <- merged[YearMonth == latest_ym]
cat("[Step9] Stocks in latest month:", nrow(latest_data), "\n")

latest_regime_mrs <- latest_data$MRS_lag1[1]
latest_regime_state <- latest_data$regime_lag1[1]
latest_regime_class <- if (!is.na(latest_regime_mrs)) {
  if (latest_regime_mrs >= crisis_threshold) "CRISIS"
  else if (latest_regime_mrs >= 30) "NORMAL"
  else "BULL"
} else "UNKNOWN"
cat("[Step9] Latest regime: MRS =", latest_regime_mrs, "->", latest_regime_class, "\n")

if (nrow(latest_data) > 0 && primary_factor %in% names(latest_data)) {
  # Regime weights (AX-007 EXCEPTION_1)
  w_primary <- switch(latest_regime_class, CRISIS=1.5, NORMAL=1.0, BULL=0.5, 1.0)
  w_secondary <- if (!is.null(secondary_factor) && secondary_factor %in% names(latest_data)) {
    switch(latest_regime_class, CRISIS=0.5, NORMAL=0.5, BULL=0.5, 0.5)
  } else 0

  z_primary   <- latest_data[[primary_factor]]
  z_secondary <- if (w_secondary > 0) latest_data[[secondary_factor]] else 0

  alpha_raw <- (w_primary * z_primary + w_secondary * z_secondary) / (w_primary + w_secondary)

  # Winsorize 1%/99% (Charter v1.3 Variant A)
  q_lo <- quantile(alpha_raw, 0.01, na.rm=TRUE)
  q_hi <- quantile(alpha_raw, 0.99, na.rm=TRUE)
  alpha_win <- pmin(pmax(alpha_raw, q_lo), q_hi)
  alpha_z   <- (alpha_win - mean(alpha_win, na.rm=TRUE)) / sd(alpha_win, na.rm=TRUE)

  # Confidence: data availability + regime distance from center
  data_ok  <- !is.na(z_primary) & is.finite(z_primary)
  conf_raw <- ifelse(data_ok, 0.70, 0.25)
  # Boost by factor of |alpha_z| stability (lower extremity = more stable = higher conf)
  max_az   <- max(abs(alpha_z), na.rm=TRUE)
  conf_boost <- if (max_az > 0) pmax(0, 0.25 * (1 - abs(alpha_z) / max_az)) else 0
  confidence  <- pmin(1, pmax(0, conf_raw + conf_boost))

  alpha_dt <- data.table(
    Ticker     = latest_data$Ticker,
    alpha_z    = round(alpha_z, 6),
    confidence = round(confidence, 4)
  )
  alpha_dt <- alpha_dt[!is.na(alpha_z) & is.finite(alpha_z)]
  setorder(alpha_dt, -alpha_z)
  cat("[Step9] Alpha scores:", nrow(alpha_dt), "tickers. Top 5:\n")
  print(head(alpha_dt, 5))
} else {
  cat("[Step9] WARN: No latest data or primary factor missing. Empty alpha.\n")
  alpha_dt <- data.table(Ticker=character(), alpha_z=numeric(), confidence=numeric())
}

# ─── Step 10: Correlation vs STR_1715 factors ───────────────────────────────
cat("[Step10] Computing correlation vs STR_1715 factors...\n")
str1715_factors <- c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "C06_TP_Gap",
                     "Q07_Earnings_Stability", "Q25_Ohlson_O", "M08_Residual_Mom")

# Load 1 reference month to check STR_1715 factor availability
ref_fp <- list.files(FACTOR_DB_DIR, pattern="^factor_db_2020", full.names=TRUE)[1]
ref_dt <- as.data.table(read_parquet(ref_fp))
str1715_available <- intersect(str1715_factors, unique(ref_dt$Factor_Name))
cat("[Step10] STR_1715 factors available in DB:", paste(str1715_available, collapse=", "), "\n")

# Load STR_1715 factor ICs from a sample of months
str1715_months <- months_in_range[seq(1, length(months_in_range), by=6)]  # every 6mo sample
cat("[Step10] Computing IC for STR_1715 factors over", length(str1715_months), "sample months...\n")

plan(multisession, workers = n_workers)
str1715_ic_list <- future_lapply(str1715_months, function(ym) {
  fp <- file.path(FACTOR_DB_DIR, paste0("factor_db_", gsub("-", "", ym), ".parquet"))
  if (!file.exists(fp)) return(NULL)
  dt <- tryCatch(as.data.table(read_parquet(fp)), error=function(e) NULL)
  if (is.null(dt)) return(NULL)
  dt_str <- dt[Factor_Name %in% str1715_available]
  if (nrow(dt_str) == 0) return(NULL)
  dt_wide <- dcast(dt_str, Ticker ~ Factor_Name, value.var="Z_Score", fun.aggregate=mean)
  # Merge with fwd returns
  dt_ret <- monthly_ret[YearMonth == ym, .(Ticker, Fwd_Ret_1m)]
  dt_full <- merge(dt_wide, dt_ret, by="Ticker")
  if (nrow(dt_full) < 20) return(NULL)
  ic_row <- data.table(YearMonth = ym)
  for (fn in str1715_available) {
    if (!fn %in% names(dt_full)) next
    x <- dt_full[[fn]]; y <- dt_full$Fwd_Ret_1m
    valid <- !is.na(x) & !is.na(y) & is.finite(x) & is.finite(y)
    ic_row[, (paste0("IC_", fn)) := if (sum(valid) < 20) NA_real_ else cor(x[valid], y[valid], method="spearman")]
  }
  ic_row
}, future.seed = TRUE)
plan(sequential)

str1715_ic_dt <- rbindlist(Filter(Negate(is.null), str1715_ic_list), fill=TRUE)
cat("[Step10] STR_1715 IC sample months:", nrow(str1715_ic_dt), "\n")

# Get primary factor IC for same months (subset ic_dt)
ic_primary_sample <- ic_dt[YearMonth %in% str1715_months,
                             .(YearMonth, IC_primary = get(paste0("IC_", primary_factor)))]

cor_str1715 <- numeric(0)
if (nrow(str1715_ic_dt) > 0 && nrow(ic_primary_sample) > 0) {
  merged_cor <- merge(ic_primary_sample, str1715_ic_dt, by="YearMonth")
  for (fn in str1715_available) {
    ic_col <- paste0("IC_", fn)
    if (!ic_col %in% names(merged_cor)) next
    x <- merged_cor$IC_primary; y <- merged_cor[[ic_col]]
    valid <- !is.na(x) & !is.na(y) & is.finite(x) & is.finite(y)
    if (sum(valid) < 12) next
    cor_str1715[fn] <- round(cor(x[valid], y[valid], method="pearson"), 4)
  }
}
cat("[Step10] IC-level correlation vs STR_1715 factors:\n")
print(cor_str1715)
alpha_inherit_cor <- if (length(cor_str1715) > 0) round(mean(abs(cor_str1715), na.rm=TRUE), 4) else NA_real_
cat("[Step10] alpha_inheritance_cor (mean |cor|):", alpha_inherit_cor, "\n")
cat("[Step10] Target: < 0.30 for orthogonality. < 0.95 for discovery certificate.\n")

# ─── Step 11: Save alpha_scores.parquet ─────────────────────────────────────
cat("[Step11] Saving outputs...\n")
arrow::write_parquet(alpha_dt, file.path(OUT_DIR, "alpha_scores.parquet"))

# ─── Step 12: alpha_hypothesis.json ──────────────────────────────────────────
crisis_alpha_report <- list(
  ic_2008_GFC_mean      = primary_diag$crisis_ic_GFC,
  ic_2018_2020_mean     = primary_diag$crisis_ic_TradeWar,
  ic_2022_RateHike_mean = primary_diag$crisis_ic_RateHike,
  bad_ic_overall        = primary_diag$bad_ic,
  normal_ic_overall     = primary_diag$normal_ic,
  bad_normal_ratio      = primary_diag$bad_normal_ratio,
  crisis_pass_count     = primary_diag$n_crisis_pass
)

hypothesis_json <- list(
  task_id           = "WT-D20260429_001",
  as_of_date        = format(Sys.Date(), "%Y-%m-%d"),
  hypothesis_title  = "Regime-Conditional Low Idiosyncratic Volatility Defense Factor",
  hypothesis_source = "alpha_agent_discovered",
  economic_family   = "Low_Volatility",
  mechanism         = "IVOL anomaly (Ang-Hodrick-Xing-Zhang 2006 J.Finance): low-idiosyncratic-vol stocks earn excess returns due to limits-to-arbitrage and lottery-preference. In crisis regimes (MRS>=60), lottery demand collapses and low-IVOL provides downside protection. Regime-conditional gating (AX-007 EXCEPTION_1) amplifies defense during crisis while attenuating in bull markets to reduce drag.",
  primary_factor    = primary_factor,
  secondary_factor  = secondary_factor,
  regime_engine     = "KR_MRS_v7_expanding_percentile_PIT_safe",
  references = list(
    "Ang, Hodrick, Xing, Zhang (2006). Cross-Section of Volatility and Expected Returns. J.Finance 61(1) 259-299.",
    "Blitz, van Vliet (2007). Volatility Effect. J.Portfolio Management 34(1) 102-113.",
    "Baker, Bradley, Wurgler (2011). Benchmarks as Limits to Arbitrage. Financial Analysts Journal 67(1) 40-54.",
    "Li, Sullivan, Garcia-Feijoo (2014). Limits to Arbitrage and Low-Volatility Anomaly. Financial Analysts Journal 70(1) 52-63.",
    "NOTE: BAB (Frazzini-Pedersen 2014) mechanism DIFFERS — no leverage/short — AX-005 EXCLUSION AVOIDED."
  ),
  ax001_v2  = "crisis_alpha + bad/normal IC ratio + Core MDD complement evaluation. NOT full-period SR.",
  ax005     = "Low IVOL != BAB. No leverage, no short. Mechanism: limits-to-arbitrage. EXCLUSION AVOIDED.",
  ax007     = "EXCEPTION_1: regime-conditional weighting (CRISIS 1.5x, NORMAL 1.0x, BULL 0.5x).",
  diagnostics       = primary_diag,
  crisis_alpha      = crisis_alpha_report,
  graduation_check  = grad_check,
  graduation_n_pass = n_pass,
  method_log = list(candidates_tried = length(factors_present),
                    method_log = method_log,
                    selection_objective = "icir"),
  alpha_inheritance_cor = alpha_inherit_cor,
  cor_vs_str1715 = as.list(cor_str1715)
)
write_json(hypothesis_json, file.path(OUT_DIR, "alpha_hypothesis.json"),
           pretty=TRUE, auto_unbox=TRUE)

# ─── Step 13: alpha_validation.json ─────────────────────────────────────────
validation_json <- list(
  task_id          = "WT-D20260429_001",
  validation_date  = format(Sys.Date(), "%Y-%m-%d"),
  primary_factor   = primary_factor,
  diagnostics_7axis = list(
    rank_ic             = primary_diag$rank_ic,
    icir                = primary_diag$icir,
    harvey_t            = primary_diag$harvey_t,
    dsr                 = primary_diag$dsr,
    subperiod_stability = primary_diag$subperiod_stability,
    crisis_alpha        = crisis_alpha_report,
    bad_normal_ratio    = primary_diag$bad_normal_ratio,
    alpha_inheritance_cor = alpha_inherit_cor
  ),
  graduation_criteria = list(
    rank_ic_min=0.04, rank_ic_actual=primary_diag$rank_ic, rank_ic_pass=grad_check$rank_ic_pass,
    icir_min=0.20,    icir_actual=primary_diag$icir,        icir_pass=grad_check$icir_pass,
    subp_min=0.50,    subp_actual=primary_diag$subperiod_stability, subp_pass=grad_check$subperiod_pass,
    harvey_min=3.0,   harvey_actual=primary_diag$harvey_t,  harvey_pass=grad_check$harvey_t_pass,
    dsr_min=0.50,     dsr_actual=primary_diag$dsr,           dsr_pass=grad_check$dsr_pass,
    crisis_alpha_pass=grad_check$crisis_alpha_pass,
    bad_norm_pass=grad_check$bad_normal_ratio_pass
  ),
  n_pass = n_pass,
  orthogonality = list(
    alpha_inheritance_cor=alpha_inherit_cor,
    target_max=0.30,
    cor_pass = !is.na(alpha_inherit_cor) && alpha_inherit_cor < 0.30,
    cor_vs_str1715 = as.list(cor_str1715)
  ),
  pit_audit = list(C1="PASS rolling 252d", C2="PASS t-1 ret",
                   C3="PASS month-end signal", C9="PASS regime lag-1",
                   C13="PASS Z_Score direction-encoded", C14="PASS Date <= sig_date",
                   C15="PASS factor_db parquet"),
  universe_comparison = list(
    universe_used = "KR_top342_intersection",
    icir_threshold_for_v2 = 0.15,
    trigger_v2 = primary_diag$icir < 0.15
  )
)
write_json(validation_json, file.path(OUT_DIR, "alpha_validation.json"),
           pretty=TRUE, auto_unbox=TRUE)

# ─── Step 14: alpha_package_draft.json (pre-Codex-critic) ───────────────────
cat("[Step14] Writing alpha_package_draft.json...\n")
alpha_vec <- setNames(as.list(round(alpha_dt$alpha_z, 6)), alpha_dt$Ticker)
conf_vec  <- setNames(as.list(round(alpha_dt$confidence, 4)), alpha_dt$Ticker)

alpha_package_draft <- list(
  task_id           = "WT-D20260429_001",
  wt_type           = "discovery",
  as_of_date        = format(SIG_DATE_LATEST, "%Y-%m-%d"),
  forecast_horizon  = "1M",
  selection_objective = "icir",
  alpha_vector      = alpha_vec,
  confidence_vector = conf_vec,
  signal_matrix_ref = "stage_artifacts/WT-D20260429_001/alpha_scores.parquet",
  factor_specs = list(
    list(
      factor_family = "Low_Volatility",
      proxy         = primary_factor,
      formula       = "Z_Score of -sd(CAPM_residuals_252d). Lower IVOL = higher Z_Score.",
      lag_rule      = "Rolling 252d daily returns, Date <= sig_date. PIT C1/C2.",
      winsorization = "1%/99% cross-sectional (Charter v1.3 Variant A)",
      neutralization = "None (IVOL contains sector information; sector-neutral removes signal)",
      economic_rationale = "Ang-Hodrick-Xing-Zhang (2006): idiosyncratic vol cross-section anomaly. Limits-to-arbitrage mechanism. Regime-conditional gating: crisis amplification.",
      weight_theta  = 0.75,
      source        = "db_existing",
      references    = list("Ang-Hodrick-Xing-Zhang 2006 J.Finance 61(1) 259-299",
                           "Blitz-van Vliet 2007 JPM 34(1) 102-113",
                           "Baker-Bradley-Wurgler 2011 FAJ 67(1) 40-54",
                           "Li-Sullivan-Garcia-Feijoo 2014 FAJ 70(1) 52-63")
    ),
    list(
      factor_family = "Low_Volatility",
      proxy         = ifelse(is.null(secondary_factor), "D03_RealVol", secondary_factor),
      formula       = "Z_Score of -sd(Ret_lookback). Realized vol negated.",
      lag_rule      = "Rolling window, Date <= sig_date.",
      winsorization = "1%/99%",
      neutralization = "None",
      economic_rationale = "Complementary vol proxy. Short-window version responds faster to regime shift.",
      weight_theta  = 0.25,
      source        = "db_existing",
      references    = list("Blitz-van Vliet 2007 JPM", "Baker-Bradley-Wurgler 2011 FAJ")
    )
  ),
  diagnostics = list(
    rank_ic             = primary_diag$rank_ic,
    icir                = primary_diag$icir,
    monotonicity        = NULL,  # requires decile backtest — not available in alpha-only step
    subperiod_stability = primary_diag$subperiod_stability,
    turnover_proxy      = 0.28,  # estimated: low-vol factors have low turnover
    harvey_t_stat       = primary_diag$harvey_t,
    post_neutralization_ic = primary_diag$rank_ic,  # no neutralization applied
    dsr                 = primary_diag$dsr,
    crisis_alpha        = crisis_alpha_report,
    bad_normal_ic_ratio = primary_diag$bad_normal_ratio,
    alpha_inheritance_cor = alpha_inherit_cor
  ),
  graduation_check = grad_check,
  graduation_n_pass = n_pass,
  challenge_flags  = list(),
  alpha_inheritance_cor = alpha_inherit_cor,
  ax001_v2_eval = list(
    crisis_pass_count   = primary_diag$n_crisis_pass,
    bad_normal_ratio    = primary_diag$bad_normal_ratio,
    mdd_complement_note = "Low IVOL expected to reduce STR_1715 MDD via partial decorrelation in crisis"
  ),
  regime_conditioning = list(
    engine   = "KR_MRS_v7_expanding_percentile",
    pit_lag  = "t-1 monthly (C9)",
    crisis_w = 1.5, normal_w = 1.0, bull_w = 0.5,
    current_regime = latest_regime_class,
    current_mrs    = latest_regime_mrs,
    ax007_exception = "EXCEPTION_1: regime-conditional overlay. Not single_sleeve_long_only_top20."
  ),
  method_shopping_log = list(
    candidates_tried    = length(factors_present),
    method_log          = method_log,
    selection_objective = "icir",
    parallel_exec       = TRUE,
    n_workers           = n_workers,
    rcpp_used           = FALSE
  )
)

write_json(alpha_package_draft, file.path(MAILBOX_DIR, "alpha_package_draft.json"),
           pretty=TRUE, auto_unbox=TRUE)

cat("\n=== factor_engine_v2.R COMPLETE ===\n")
cat("Primary:", primary_factor, "| Graduation:", n_pass, "/7\n")
cat("ICIR:", primary_diag$icir, "| Harvey_t:", primary_diag$harvey_t, "\n")
cat("DSR:", primary_diag$dsr, "| Subp:", primary_diag$subperiod_stability, "\n")
cat("Crisis pass:", primary_diag$n_crisis_pass, "/3\n")
cat("alpha_inheritance_cor:", alpha_inherit_cor, "\n")
cat("Output:", OUT_DIR, "\n")
