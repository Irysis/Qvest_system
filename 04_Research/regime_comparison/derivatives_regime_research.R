#==============================================================================
# Derivatives Regime Engine Research
# KRX 파생시장 데이터 기반 국면엔진 강화 리서치
#
# 목적:
# 1. KRX API 파생 지표 수집 (VKOSPI, Futures Basis, PCR, IV Skew)
# 2. 파생 국면 지표 산출 (VRP, Basis Zscore, PCR Signal)
# 3. 신규 KPI 기반 기존 모델 + 파생 모델 비교
#    - KPI-A: 다음달 하락 예측력 (Precision, Recall, Brier Score)
#    - KPI-B: 전기간 하방 리스크 방어율 (DD Avoided, CVaR Reduction)
# 4. 앙상블 가능성 (FRED + MSM + Derivatives)
#
# Refs: D-01~D-50 (DERIVATIVES_REGIME_DETECTION_RESEARCH.md)
#==============================================================================
cat("[derivatives_regime] Starting research...\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(ggplot2)
})

# ── Config ──
SCRIPT_DIR <- tryCatch({
  d <- dirname(sys.frame(1)$ofile)
  if (d == ".") getwd() else d
}, error = function(e) getwd())

INFRA_DIR <- file.path(dirname(dirname(SCRIPT_DIR)), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(DATA_DIR, "krx_data_collector.R"))
source(file.path(DATA_DIR, "krx_derivatives_collector.R"))

OUT_DIR <- file.path(SCRIPT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# ── Load benchmark data ──
data_list <- load_rawdata()
RAWDATA <- data_list$RAWDATA
BM_DT   <- data_list$BM_DT
bm_daily <- BM_DT[, list(Date, BM_Ret = as.numeric(BM_Ret))]
bm_daily <- bm_daily[!is.na(BM_Ret)]
setkey(bm_daily, Date)

# Monthly BM returns
bm_daily[, YM := format(Date, "%Y-%m")]
monthly_bm <- bm_daily[, list(
  BM_Ret_M    = prod(1 + BM_Ret, na.rm = TRUE) - 1,
  BM_Vol_M    = sd(BM_Ret, na.rm = TRUE) * sqrt(252),
  BM_MinRet_M = min(BM_Ret, na.rm = TRUE),
  N_Days      = .N
), by = YM]
setorder(monthly_bm, YM)
monthly_bm[, Fwd_BM_Ret := shift(BM_Ret_M, -1, type = "lead")]

# Cumulative BM for drawdown
bm_daily[, BM_Cum := cumprod(1 + BM_Ret)]
bm_daily[, BM_Peak := cummax(BM_Cum)]
bm_daily[, BM_DD := BM_Cum / BM_Peak - 1]

cat(sprintf("[derivatives_regime] BM data: %d days, %d months\n",
            nrow(bm_daily), nrow(monthly_bm)))

#==============================================================================
# PART 1: Load Existing Regime Models
#==============================================================================
cat("\n=== PART 1: Load existing regime models ===\n")

# FRED Regime
fred_dt <- as.data.table(read_parquet(FRED_REGIME_CACHE))
fred_dt[, Date := as.Date(Date)]
fred_dt[, YM := format(Date, "%Y-%m")]
fred_dt[, FRED_Alert := (Macro_Risk_Score >= 30) |
          (Buddha_Mode == TRUE) |
          (VIX_Regime %in% c("extreme", "crisis"))]
setkey(fred_dt, YM)
cat(sprintf("  FRED: %d months, %d alerts\n", nrow(fred_dt), sum(fred_dt$FRED_Alert, na.rm = TRUE)))

# MSM Regime — Load from updated parquet cache first, fallback to .RData
msm_parquet <- file.path(PROJECT_ROOT, ".cache", "msm_hybrid_latest.parquet")
msm_dt <- data.table()
if (file.exists(msm_parquet)) {
  msm_dt <- as.data.table(arrow::read_parquet(msm_parquet))
  cat(sprintf("  MSM loaded from cache: %s\n", msm_parquet))
} else {
  msm_path <- list.files(
    file.path(PROJECT_ROOT, "05_Production/1.Regime_Def_Model/1-1.MSM"),
    pattern = "MSM\\.RData$", full.names = TRUE
  )
  if (length(msm_path) > 0) {
    suppressPackageStartupMessages(library(xts))
    env <- new.env()
    load(msm_path[length(msm_path)], envir = env)
  }
}

if (nrow(msm_dt) > 0 || (exists("env") && !is.null(env$df_hybrid))) {
  if (nrow(msm_dt) == 0 && exists("env") && !is.null(env$df_hybrid)) {
    msm_dt <- as.data.table(env$df_hybrid)
  }
  if (nrow(msm_dt) > 0 && "Avg_Prob" %in% names(msm_dt)) {
    msm_dt[, Date := as.Date(Date)]
    msm_dt[, YM := format(Date, "%Y-%m")]
    msm_dt[, MSM_Crisis_Prob := Avg_Prob]
    msm_dt[, MSM_Hybrid_Regime := Regime]
    msm_dt[, MSM_Alert := Regime != "Stable"]
    msm_dt[, MSM_Crisis_Only := Regime == "Crisis"]
    msm_dt[, MSM_Weight := Target_Weight]
    setkey(msm_dt, YM)
    cat(sprintf("  MSM Hybrid (df_hybrid): %d months (%s ~ %s)\n",
                nrow(msm_dt), min(msm_dt$Date), max(msm_dt$Date)))
    cat(sprintf("  Regime counts: Crisis=%d, Caution=%d, Stable=%d\n",
                sum(msm_dt$Regime == "Crisis", na.rm = TRUE),
                sum(grepl("Caution", msm_dt$Regime), na.rm = TRUE),
                sum(msm_dt$Regime == "Stable", na.rm = TRUE)))
    cat(sprintf("  MSM: %d alerts (non-Stable)\n", sum(msm_dt$MSM_Alert, na.rm = TRUE)))
  } else if (exists("env") && !is.null(env$monthly_prob)) {
    # Fallback: raw monthly_prob (without hybrid)
    mp <- env$monthly_prob
    msm_dt <- data.table(
      Date = as.Date(index(mp)),
      MSM_Crisis_Prob = as.numeric(coredata(mp))
    )
    msm_dt[, YM := format(Date, "%Y-%m")]
    msm_dt[, MSM_Alert := MSM_Crisis_Prob >= 0.5]
    setkey(msm_dt, YM)
    cat(sprintf("  MSM (raw prob): %d months, %d alerts\n",
                nrow(msm_dt), sum(msm_dt$MSM_Alert, na.rm = TRUE)))
  }
} else {
  cat("  MSM: NOT FOUND (skip)\n")
}

#==============================================================================
# PART 2: Collect KRX Derivatives Data (recent period)
#==============================================================================
cat("\n=== PART 2: Collect KRX derivatives data ===\n")

# Check existing cache
drv_files <- list.files(DRV_CACHE_DIR, pattern = "^drv_.*\\.parquet$")
if (length(drv_files) > 0) {
  cat(sprintf("  Existing cache: %d days\n", length(drv_files)))
}

# Collect recent period if needed (last 60 business days for quick test)
# For full history, we'd need to go back further
latest_bm_date <- max(bm_daily$Date)
collect_start <- format(latest_bm_date - 90, "%Y%m%d")  # ~60 biz days
collect_end   <- format(Sys.Date(), "%Y%m%d")

# Only collect if we have < 30 days cached
if (length(drv_files) < 30) {
  cat(sprintf("  Collecting derivatives: %s ~ %s\n", collect_start, collect_end))
  tryCatch(
    krx_collect_derivatives_range(collect_start, collect_end),
    error = function(e) cat(sprintf("  Collection error: %s\n", e$message))
  )
}

# Load derivatives data
drv_dt <- krx_load_derivatives()

#==============================================================================
# PART 3: Compute Derivative Regime Indicators
#==============================================================================
cat("\n=== PART 3: Compute derivative regime indicators ===\n")

if (nrow(drv_dt) > 0) {
  drv_dt[, YM := format(Date, "%Y-%m")]

  # 3a. VKOSPI-based signals
  if ("VKOSPI" %in% names(drv_dt)) {
    drv_dt[, VKOSPI_MA20 := frollmean(VKOSPI, 20, align = "right")]
    drv_dt[, VKOSPI_Zscore := {
      m <- frollmean(VKOSPI, 60, align = "right")
      s <- frollapply(VKOSPI, 60, sd, align = "right")
      (VKOSPI - m) / pmax(s, 0.01)
    }]
    drv_dt[, VKOSPI_Alert := VKOSPI > 25]  # elevated
    drv_dt[, VKOSPI_Crisis := VKOSPI > 35] # crisis
    cat(sprintf("  VKOSPI: range [%.1f, %.1f], alerts=%d, crises=%d\n",
                min(drv_dt$VKOSPI, na.rm = TRUE), max(drv_dt$VKOSPI, na.rm = TRUE),
                sum(drv_dt$VKOSPI_Alert, na.rm = TRUE),
                sum(drv_dt$VKOSPI_Crisis, na.rm = TRUE)))
  }

  # 3b. VRP (Variance Risk Premium)
  # VRP = VKOSPI^2/10000 - Realized Variance (annualized)
  if ("VKOSPI" %in% names(drv_dt)) {
    bm_merged <- merge(drv_dt, bm_daily[, list(Date, BM_Ret)], by = "Date", all.x = TRUE)
    bm_merged[, RV_22d := frollapply(BM_Ret, 22, function(x) var(x, na.rm = TRUE) * 252, align = "right")]
    bm_merged[, IV_annualized := (VKOSPI / 100)^2]
    bm_merged[, VRP := IV_annualized - RV_22d]
    bm_merged[, VRP_Zscore := {
      m <- frollmean(VRP, 60, align = "right")
      s <- frollapply(VRP, 60, sd, align = "right")
      (VRP - m) / pmax(s, 0.001)
    }]
    bm_merged[, VRP_Alert := VRP_Zscore > 1.5]  # high VRP = fear exceeds reality
    drv_dt <- merge(drv_dt, bm_merged[, list(Date, RV_22d, VRP, VRP_Zscore, VRP_Alert)],
                    by = "Date", all.x = TRUE)
    cat(sprintf("  VRP: range [%.4f, %.4f]\n",
                min(drv_dt$VRP, na.rm = TRUE), max(drv_dt$VRP, na.rm = TRUE)))
  }

  # 3c. Futures Basis Signal
  if ("K200_Basis_Pct" %in% names(drv_dt)) {
    drv_dt[, Basis_MA20 := frollmean(K200_Basis_Pct, 20, align = "right")]
    drv_dt[, Basis_Zscore := {
      m <- frollmean(K200_Basis_Pct, 60, align = "right")
      s <- frollapply(K200_Basis_Pct, 60, sd, align = "right")
      (K200_Basis_Pct - m) / pmax(s, 0.001)
    }]
    drv_dt[, Basis_Alert := K200_Basis_Pct < -0.5]  # deep backwardation = stress
    cat(sprintf("  Basis: range [%.2f%%, %.2f%%]\n",
                min(drv_dt$K200_Basis_Pct, na.rm = TRUE),
                max(drv_dt$K200_Basis_Pct, na.rm = TRUE)))
  }

  # 3d. Put-Call Ratio Signal
  if ("PCR_OI" %in% names(drv_dt)) {
    drv_dt[, PCR_MA5 := frollmean(PCR_OI, 5, align = "right")]
    drv_dt[, PCR_Alert := PCR_OI > 1.3]  # high put demand = fear
    cat(sprintf("  PCR (OI): range [%.2f, %.2f], alerts=%d\n",
                min(drv_dt$PCR_OI, na.rm = TRUE), max(drv_dt$PCR_OI, na.rm = TRUE),
                sum(drv_dt$PCR_Alert, na.rm = TRUE)))
  }

  # 3e. IV Skew Signal
  if ("IV_Skew" %in% names(drv_dt)) {
    drv_dt[, Skew_MA5 := frollmean(IV_Skew, 5, align = "right")]
    drv_dt[, Skew_Alert := IV_Skew > 0.15]  # Put IV >> Call IV = crash fear
    cat(sprintf("  IV Skew: range [%.3f, %.3f]\n",
                min(drv_dt$IV_Skew, na.rm = TRUE), max(drv_dt$IV_Skew, na.rm = TRUE)))
  }

  # 3f. Composite Derivatives Score (0-100)
  drv_dt[, DRV_Score := 0]
  if ("VKOSPI_Zscore" %in% names(drv_dt))
    drv_dt[, DRV_Score := DRV_Score + pmin(pmax(fifelse(is.na(VKOSPI_Zscore), 0, VKOSPI_Zscore) * 15, 0), 30)]
  if ("VRP_Zscore" %in% names(drv_dt))
    drv_dt[, DRV_Score := DRV_Score + pmin(pmax(fifelse(is.na(VRP_Zscore), 0, VRP_Zscore) * 10, 0), 25)]
  if ("Basis_Zscore" %in% names(drv_dt))
    drv_dt[, DRV_Score := DRV_Score + pmin(pmax(-fifelse(is.na(Basis_Zscore), 0, Basis_Zscore) * 10, 0), 20)]
  if ("PCR_OI" %in% names(drv_dt))
    drv_dt[, DRV_Score := DRV_Score + pmin(pmax((fifelse(is.na(PCR_OI), 0.8, PCR_OI) - 0.8) * 25, 0), 15)]
  if ("IV_Skew" %in% names(drv_dt))
    drv_dt[, DRV_Score := DRV_Score + pmin(pmax(fifelse(is.na(IV_Skew), 0, IV_Skew) * 50, 0), 10)]
  drv_dt[, DRV_Score := pmin(DRV_Score, 100)]
  drv_dt[, DRV_Alert := DRV_Score >= 40]
  cat(sprintf("  DRV Score: range [%.1f, %.1f], alerts=%d\n",
              min(drv_dt$DRV_Score, na.rm = TRUE), max(drv_dt$DRV_Score, na.rm = TRUE),
              sum(drv_dt$DRV_Alert, na.rm = TRUE)))

  # Monthly aggregation
  drv_monthly <- drv_dt[, list(
    VKOSPI_M     = mean(VKOSPI, na.rm = TRUE),
    VRP_M        = mean(VRP, na.rm = TRUE),
    Basis_Pct_M  = mean(K200_Basis_Pct, na.rm = TRUE),
    PCR_OI_M     = mean(PCR_OI, na.rm = TRUE),
    IV_Skew_M    = mean(IV_Skew, na.rm = TRUE),
    DRV_Score_M  = mean(DRV_Score, na.rm = TRUE),
    DRV_Alert_M  = as.numeric(mean(DRV_Alert, na.rm = TRUE) > 0.5)
  ), by = YM]
  setkey(drv_monthly, YM)
  cat(sprintf("  Monthly derivatives: %d months\n", nrow(drv_monthly)))
}

#==============================================================================
# PART 4: Unified Monthly Dataset
#==============================================================================
cat("\n=== PART 4: Build unified monthly dataset ===\n")

# Base: monthly BM returns
unified <- copy(monthly_bm)
unified[, Fwd_BM_Ret := shift(BM_Ret_M, -1, type = "lead")]
unified[, Bad_Month := Fwd_BM_Ret < -0.03]  # >3% decline
unified[, Severe_Month := Fwd_BM_Ret < -0.05]  # >5% decline

# Merge FRED
if (nrow(fred_dt) > 0) {
  unified <- merge(unified, fred_dt[, list(YM, Macro_Risk_Score, FRED_Alert)],
                   by = "YM", all.x = TRUE)
}

# Merge MSM
if (nrow(msm_dt) > 0) {
  unified <- merge(unified, msm_dt[, list(YM, MSM_Crisis_Prob, MSM_Alert)],
                   by = "YM", all.x = TRUE)
}

# Merge Derivatives
if (nrow(drv_dt) > 0 && exists("drv_monthly")) {
  unified <- merge(unified, drv_monthly, by = "YM", all.x = TRUE)
}

# Fill NA alerts
if ("FRED_Alert" %in% names(unified)) unified[is.na(FRED_Alert), FRED_Alert := FALSE]
if ("MSM_Alert" %in% names(unified))  unified[is.na(MSM_Alert), MSM_Alert := FALSE]

# Combined OR-gate (FRED | MSM)
if ("FRED_Alert" %in% names(unified) && "MSM_Alert" %in% names(unified)) {
  unified[, Combined_OR := (FRED_Alert == TRUE) | (MSM_Alert == TRUE)]
  # AND-gate: both must agree
  unified[, Combined_AND := (FRED_Alert == TRUE) & (MSM_Alert == TRUE)]
  # Weighted vote: FRED(0.6) + MSM(0.4) > 0.5
  if ("Macro_Risk_Score" %in% names(unified) && "MSM_Crisis_Prob" %in% names(unified)) {
    unified[, Combined_Weighted := {
      fred_score <- fifelse(is.na(Macro_Risk_Score), 0, pmin(Macro_Risk_Score / 100, 1))
      msm_score  <- fifelse(is.na(MSM_Crisis_Prob), 0, MSM_Crisis_Prob)
      (0.5 * fred_score + 0.5 * msm_score) > 0.3
    }]
  }
} else if ("FRED_Alert" %in% names(unified)) {
  unified[, Combined_OR := FRED_Alert]
  unified[, Combined_AND := FRED_Alert]
}
# Legacy alias
if ("Combined_OR" %in% names(unified)) unified[, Combined_Alert := Combined_OR]

# Combined with Derivatives (FRED | MSM | DRV)
if ("DRV_Alert_M" %in% names(unified)) {
  unified[is.na(DRV_Alert_M), DRV_Alert_M := 0]
  if ("MSM_Alert" %in% names(unified)) {
    unified[, Tri_Alert := (FRED_Alert == TRUE) | (MSM_Alert == TRUE) | (DRV_Alert_M == 1)]
  } else {
    unified[, Tri_Alert := (FRED_Alert == TRUE) | (DRV_Alert_M == 1)]
  }

  # Additional ensemble variants with DRV
  if ("FRED_Alert" %in% names(unified)) {
    unified[, FRED_DRV_AND := (FRED_Alert == TRUE) & (DRV_Alert_M == 1)]
    unified[, FRED_DRV_OR  := (FRED_Alert == TRUE) | (DRV_Alert_M == 1)]
  }
  if ("MSM_Alert" %in% names(unified)) {
    unified[, MSM_DRV_AND := (MSM_Alert == TRUE) & (DRV_Alert_M == 1)]
    unified[, MSM_DRV_OR  := (MSM_Alert == TRUE) | (DRV_Alert_M == 1)]
  }

  # Weighted triple: FRED(0.4) + MSM(0.3) + DRV(0.3) > threshold
  if ("Macro_Risk_Score" %in% names(unified) && "MSM_Crisis_Prob" %in% names(unified) &&
      "DRV_Score_M" %in% names(unified)) {
    unified[, Tri_Weighted := {
      fred_s <- fifelse(is.na(Macro_Risk_Score), 0, pmin(Macro_Risk_Score / 100, 1))
      msm_s  <- fifelse(is.na(MSM_Crisis_Prob), 0, MSM_Crisis_Prob)
      drv_s  <- fifelse(is.na(DRV_Score_M), 0, pmin(DRV_Score_M / 100, 1))
      (0.4 * fred_s + 0.3 * msm_s + 0.3 * drv_s) > 0.3
    }]

    # Majority vote: 2/3 must agree
    unified[, Tri_Majority := {
      n_agree <- as.integer(FRED_Alert == TRUE) +
                 as.integer(MSM_Alert == TRUE) +
                 as.integer(DRV_Alert_M == 1)
      n_agree >= 2
    }]
  }
}

setorder(unified, YM)
cat(sprintf("  Unified: %d months, Bad=%d, Severe=%d\n",
            nrow(unified), sum(unified$Bad_Month, na.rm = TRUE),
            sum(unified$Severe_Month, na.rm = TRUE)))

#==============================================================================
# PART 5: NEW KPI EVALUATION
#==============================================================================
cat("\n=== PART 5: New KPI Evaluation ===\n")

# ── KPI-A: 다음달 하락 예측력 ──
kpi_a_evaluate <- function(signal, fwd_ret, bad_flag, model_name, prob = NULL) {
  valid <- !is.na(signal) & !is.na(fwd_ret) & !is.na(bad_flag)
  sig <- signal[valid]; fwd <- fwd_ret[valid]; bad <- bad_flag[valid]

  # Confusion matrix
  tp <- sum(sig & bad, na.rm = TRUE)
  fp <- sum(sig & !bad, na.rm = TRUE)
  fn <- sum(!sig & bad, na.rm = TRUE)
  tn <- sum(!sig & !bad, na.rm = TRUE)

  precision   <- tp / max(tp + fp, 1)
  recall      <- tp / max(tp + fn, 1)  # = hit rate
  specificity <- tn / max(tn + fp, 1)
  f1          <- if (precision + recall > 0) 2 * precision * recall / (precision + recall) else 0
  false_alarm <- fp / max(fp + tn, 1)

  # Brier Score (if probability available, use it; otherwise use binary)
  if (!is.null(prob)) {
    p <- prob[valid]
    brier <- mean((p - as.numeric(bad))^2, na.rm = TRUE)
  } else {
    brier <- mean((as.numeric(sig) - as.numeric(bad))^2, na.rm = TRUE)
  }

  # Conditional returns
  ret_signal   <- mean(fwd[sig], na.rm = TRUE)
  ret_nosignal <- mean(fwd[!sig], na.rm = TRUE)
  value_add    <- ret_nosignal - ret_signal

  # Signal frequency
  sig_freq <- mean(sig, na.rm = TRUE)

  data.table(
    Model       = model_name,
    Precision   = round(precision, 3),
    Recall      = round(recall, 3),  # Hit Rate
    Specificity = round(specificity, 3),
    F1          = round(f1, 3),
    False_Alarm = round(false_alarm, 3),
    Brier_Score = round(brier, 4),
    Ret_Signal  = round(ret_signal * 100, 2),
    Ret_NoSig   = round(ret_nosignal * 100, 2),
    Value_Add_bps = round(value_add * 10000, 1),
    Sig_Freq    = round(sig_freq * 100, 1),
    N_Signals   = sum(sig),
    N_Total     = length(sig)
  )
}

# ── KPI-B: 전기간 하방 리스크 방어율 ──
kpi_b_evaluate <- function(signal_monthly, bm_daily_dt, model_name) {
  # Merge monthly signal to daily data
  bd <- copy(bm_daily_dt)
  bd[, YM := format(Date, "%Y-%m")]

  if (is.data.table(signal_monthly)) {
    sig_map <- signal_monthly
  } else {
    sig_map <- data.table(YM = unified$YM, Signal = as.logical(signal_monthly))
  }
  bd <- merge(bd, sig_map, by = "YM", all.x = TRUE)
  bd[is.na(Signal), Signal := FALSE]

  # Strategy: cash when signal, invested when no signal
  bd[, Strat_Ret := fifelse(Signal, 0, BM_Ret)]
  bd[, Strat_Cum := cumprod(1 + Strat_Ret)]
  bd[, BH_Cum := cumprod(1 + BM_Ret)]

  # MDD comparison
  bd[, Strat_Peak := cummax(Strat_Cum)]
  bd[, Strat_DD := Strat_Cum / Strat_Peak - 1]
  bd[, BH_Peak := cummax(BH_Cum)]
  bd[, BH_DD := BH_Cum / BH_Peak - 1]

  strat_mdd <- min(bd$Strat_DD, na.rm = TRUE)
  bh_mdd    <- min(bd$BH_DD, na.rm = TRUE)
  dd_avoided <- 1 - (strat_mdd / bh_mdd)  # % of BH drawdown avoided

  # CVaR comparison (5th percentile)
  bh_monthly_rets <- monthly_bm$BM_Ret_M[!is.na(monthly_bm$BM_Ret_M)]
  strat_monthly <- unified[, list(YM, BM_Ret_M)]
  strat_monthly <- merge(strat_monthly, sig_map, by = "YM", all.x = TRUE)
  strat_monthly[is.na(Signal), Signal := FALSE]
  strat_monthly[, Strat_Ret_M := fifelse(Signal, 0, BM_Ret_M)]

  bh_cvar_5   <- mean(sort(bh_monthly_rets)[1:max(1, floor(length(bh_monthly_rets) * 0.05))])
  strat_rets  <- strat_monthly$Strat_Ret_M[!is.na(strat_monthly$Strat_Ret_M)]
  strat_cvar_5 <- mean(sort(strat_rets)[1:max(1, floor(length(strat_rets) * 0.05))])
  cvar_reduction <- 1 - (strat_cvar_5 / bh_cvar_5)

  # Downside capture ratio
  neg_months <- which(bh_monthly_rets < 0)
  if (length(neg_months) > 0) {
    bh_neg_sum <- sum(bh_monthly_rets[neg_months])
    strat_neg_sum <- sum(strat_rets[neg_months])
    down_capture <- strat_neg_sum / bh_neg_sum
  } else {
    down_capture <- NA_real_
  }

  # Ulcer Index (daily)
  ulcer_bh    <- sqrt(mean(bd$BH_DD^2, na.rm = TRUE))
  ulcer_strat <- sqrt(mean(bd$Strat_DD^2, na.rm = TRUE))
  ulcer_ratio <- ulcer_strat / ulcer_bh

  # CAGR comparison
  n_years <- as.numeric(max(bd$Date) - min(bd$Date)) / 365.25
  cagr_bh    <- (tail(bd$BH_Cum, 1))^(1/n_years) - 1
  cagr_strat <- (tail(bd$Strat_Cum, 1))^(1/n_years) - 1

  # Sharpe comparison
  sharpe_bh    <- mean(bd$BM_Ret, na.rm = TRUE) / sd(bd$BM_Ret, na.rm = TRUE) * sqrt(252)
  sharpe_strat <- mean(bd$Strat_Ret, na.rm = TRUE) / sd(bd$Strat_Ret[bd$Strat_Ret != 0], na.rm = TRUE) * sqrt(252)

  # Cash ratio (how much time in cash)
  cash_pct <- mean(bd$Signal, na.rm = TRUE) * 100

  data.table(
    Model          = model_name,
    BH_MDD         = round(bh_mdd * 100, 1),
    Strat_MDD      = round(strat_mdd * 100, 1),
    DD_Avoided_Pct = round(dd_avoided * 100, 1),
    BH_CVaR5       = round(bh_cvar_5 * 100, 2),
    Strat_CVaR5    = round(strat_cvar_5 * 100, 2),
    CVaR_Reduction = round(cvar_reduction * 100, 1),
    Down_Capture   = round(down_capture * 100, 1),
    Ulcer_BH       = round(ulcer_bh * 100, 2),
    Ulcer_Strat    = round(ulcer_strat * 100, 2),
    Ulcer_Ratio    = round(ulcer_ratio, 3),
    CAGR_BH        = round(cagr_bh * 100, 1),
    CAGR_Strat     = round(cagr_strat * 100, 1),
    CAGR_Diff      = round((cagr_strat - cagr_bh) * 100, 2),
    Sharpe_BH      = round(sharpe_bh, 3),
    Sharpe_Strat   = round(sharpe_strat, 3),
    Cash_Pct       = round(cash_pct, 1)
  )
}

# ── Run KPI-A: 다음달 하락 예측력 ──
cat("\n--- KPI-A: Next-Month Decline Prediction ---\n")
eval_data <- unified[!is.na(Fwd_BM_Ret) & !is.na(Bad_Month)]

kpi_a_results <- list()

# FRED model
if ("FRED_Alert" %in% names(eval_data)) {
  kpi_a_results[["FRED"]] <- kpi_a_evaluate(
    eval_data$FRED_Alert, eval_data$Fwd_BM_Ret, eval_data$Bad_Month, "FRED (MRS>=30)"
  )
}

# MSM model
if ("MSM_Alert" %in% names(eval_data) && sum(!is.na(eval_data$MSM_Alert)) > 10) {
  kpi_a_results[["MSM"]] <- kpi_a_evaluate(
    eval_data$MSM_Alert, eval_data$Fwd_BM_Ret, eval_data$Bad_Month, "MSM (Crisis>=0.5)",
    prob = eval_data$MSM_Crisis_Prob
  )
}

# Combined (FRED | MSM)
if ("Combined_Alert" %in% names(eval_data)) {
  kpi_a_results[["Combined"]] <- kpi_a_evaluate(
    eval_data$Combined_Alert, eval_data$Fwd_BM_Ret, eval_data$Bad_Month, "FRED|MSM OR-gate"
  )
}

# Derivatives model (if available)
if ("DRV_Alert_M" %in% names(eval_data) && sum(!is.na(eval_data$DRV_Alert_M)) > 5) {
  kpi_a_results[["DRV"]] <- kpi_a_evaluate(
    eval_data$DRV_Alert_M == 1, eval_data$Fwd_BM_Ret, eval_data$Bad_Month, "Derivatives Score"
  )
}

# AND-gate (FRED & MSM)
if ("Combined_AND" %in% names(eval_data)) {
  kpi_a_results[["AND"]] <- kpi_a_evaluate(
    eval_data$Combined_AND, eval_data$Fwd_BM_Ret, eval_data$Bad_Month, "FRED&MSM AND-gate"
  )
}

# Weighted ensemble (0.5×FRED + 0.5×MSM > 0.3)
if ("Combined_Weighted" %in% names(eval_data)) {
  kpi_a_results[["Weighted"]] <- kpi_a_evaluate(
    eval_data$Combined_Weighted, eval_data$Fwd_BM_Ret, eval_data$Bad_Month, "FRED+MSM Weighted"
  )
}

# Triple ensemble (FRED | MSM | DRV)
if ("Tri_Alert" %in% names(eval_data) && sum(!is.na(eval_data$Tri_Alert)) > 5) {
  kpi_a_results[["Triple"]] <- kpi_a_evaluate(
    eval_data$Tri_Alert, eval_data$Fwd_BM_Ret, eval_data$Bad_Month, "FRED|MSM|DRV Triple"
  )
}

# FRED & DRV (AND-gate)
if ("FRED_DRV_AND" %in% names(eval_data) && sum(!is.na(eval_data$FRED_DRV_AND)) > 5) {
  kpi_a_results[["FRED_DRV_AND"]] <- kpi_a_evaluate(
    eval_data$FRED_DRV_AND, eval_data$Fwd_BM_Ret, eval_data$Bad_Month, "FRED&DRV AND"
  )
}

# MSM & DRV (AND-gate)
if ("MSM_DRV_AND" %in% names(eval_data) && sum(!is.na(eval_data$MSM_DRV_AND)) > 5) {
  kpi_a_results[["MSM_DRV_AND"]] <- kpi_a_evaluate(
    eval_data$MSM_DRV_AND, eval_data$Fwd_BM_Ret, eval_data$Bad_Month, "MSM&DRV AND"
  )
}

# Weighted triple
if ("Tri_Weighted" %in% names(eval_data) && sum(!is.na(eval_data$Tri_Weighted)) > 5) {
  kpi_a_results[["Tri_Weighted"]] <- kpi_a_evaluate(
    eval_data$Tri_Weighted, eval_data$Fwd_BM_Ret, eval_data$Bad_Month, "Triple Weighted"
  )
}

# Majority vote (2/3)
if ("Tri_Majority" %in% names(eval_data) && sum(!is.na(eval_data$Tri_Majority)) > 5) {
  kpi_a_results[["Tri_Majority"]] <- kpi_a_evaluate(
    eval_data$Tri_Majority, eval_data$Fwd_BM_Ret, eval_data$Bad_Month, "Triple Majority(2/3)"
  )
}

kpi_a_dt <- rbindlist(kpi_a_results)
cat("\n  ┌────────── KPI-A: Next-Month Decline Prediction ──────────┐\n")
print(kpi_a_dt)
cat("  └──────────────────────────────────────────────────────────┘\n")

# ── Run KPI-B: 하방 리스크 방어율 ──
cat("\n--- KPI-B: Full-Period Downside Risk Defense ---\n")
kpi_b_results <- list()

# Build signal maps for each model
make_signal_map <- function(col_name) {
  dt <- unified[, list(YM)]
  dt[, Signal := unified[[col_name]]]
  dt[is.na(Signal), Signal := FALSE]
  dt
}

if ("FRED_Alert" %in% names(unified)) {
  kpi_b_results[["FRED"]] <- kpi_b_evaluate(make_signal_map("FRED_Alert"), bm_daily, "FRED (MRS>=30)")
}
if ("MSM_Alert" %in% names(unified) && sum(!is.na(unified$MSM_Alert)) > 10) {
  kpi_b_results[["MSM"]] <- kpi_b_evaluate(make_signal_map("MSM_Alert"), bm_daily, "MSM (Crisis>=0.5)")
}
if ("Combined_Alert" %in% names(unified)) {
  kpi_b_results[["Combined"]] <- kpi_b_evaluate(make_signal_map("Combined_Alert"), bm_daily, "FRED|MSM OR-gate")
}
if ("DRV_Alert_M" %in% names(unified) && sum(!is.na(unified$DRV_Alert_M)) > 5) {
  sig_map <- unified[, list(YM, Signal = DRV_Alert_M == 1)]
  sig_map[is.na(Signal), Signal := FALSE]
  kpi_b_results[["DRV"]] <- kpi_b_evaluate(sig_map, bm_daily, "Derivatives Score")
}
if ("Combined_AND" %in% names(unified)) {
  kpi_b_results[["AND"]] <- kpi_b_evaluate(make_signal_map("Combined_AND"), bm_daily, "FRED&MSM AND-gate")
}
if ("Combined_Weighted" %in% names(unified)) {
  kpi_b_results[["Weighted"]] <- kpi_b_evaluate(make_signal_map("Combined_Weighted"), bm_daily, "FRED+MSM Weighted")
}
if ("Tri_Alert" %in% names(unified) && sum(!is.na(unified$Tri_Alert)) > 5) {
  kpi_b_results[["Triple"]] <- kpi_b_evaluate(make_signal_map("Tri_Alert"), bm_daily, "FRED|MSM|DRV Triple")
}
if ("FRED_DRV_AND" %in% names(unified) && sum(!is.na(unified$FRED_DRV_AND)) > 5) {
  kpi_b_results[["FRED_DRV_AND"]] <- kpi_b_evaluate(make_signal_map("FRED_DRV_AND"), bm_daily, "FRED&DRV AND")
}
if ("MSM_DRV_AND" %in% names(unified) && sum(!is.na(unified$MSM_DRV_AND)) > 5) {
  kpi_b_results[["MSM_DRV_AND"]] <- kpi_b_evaluate(make_signal_map("MSM_DRV_AND"), bm_daily, "MSM&DRV AND")
}
if ("Tri_Weighted" %in% names(unified) && sum(!is.na(unified$Tri_Weighted)) > 5) {
  kpi_b_results[["Tri_Weighted"]] <- kpi_b_evaluate(make_signal_map("Tri_Weighted"), bm_daily, "Triple Weighted")
}
if ("Tri_Majority" %in% names(unified) && sum(!is.na(unified$Tri_Majority)) > 5) {
  kpi_b_results[["Tri_Majority"]] <- kpi_b_evaluate(make_signal_map("Tri_Majority"), bm_daily, "Triple Majority(2/3)")
}

kpi_b_dt <- rbindlist(kpi_b_results)
cat("\n  ┌────────── KPI-B: Downside Risk Defense ──────────┐\n")
print(kpi_b_dt)
cat("  └──────────────────────────────────────────────────┘\n")

#==============================================================================
# PART 6: Sensitivity Analysis — Threshold Sweep
#==============================================================================
cat("\n=== PART 6: Sensitivity analysis ===\n")

# FRED MRS threshold sweep
if ("Macro_Risk_Score" %in% names(unified)) {
  thresholds <- c(15, 20, 25, 30, 35, 40, 50)
  sweep_results <- list()
  for (th in thresholds) {
    sig <- unified$Macro_Risk_Score >= th
    sig[is.na(sig)] <- FALSE
    r <- kpi_a_evaluate(sig, unified$Fwd_BM_Ret, unified$Bad_Month, sprintf("FRED MRS>=%d", th))
    sweep_results[[as.character(th)]] <- r
  }
  sweep_dt <- rbindlist(sweep_results)
  cat("\n  FRED MRS Threshold Sweep:\n")
  print(sweep_dt[, list(Model, Precision, Recall, F1, Value_Add_bps, Sig_Freq)])
}

# MSM Crisis_Prob threshold sweep
if ("MSM_Crisis_Prob" %in% names(unified)) {
  msm_thresholds <- c(0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8)
  msm_sweep <- list()
  for (th in msm_thresholds) {
    sig <- unified$MSM_Crisis_Prob >= th
    sig[is.na(sig)] <- FALSE
    msm_sweep[[as.character(th)]] <- kpi_a_evaluate(
      sig, unified$Fwd_BM_Ret, unified$Bad_Month, sprintf("MSM Prob>=%.1f", th)
    )
  }
  msm_sweep_dt <- rbindlist(msm_sweep)
  cat("\n  MSM Crisis_Prob Threshold Sweep:\n")
  print(msm_sweep_dt[, list(Model, Precision, Recall, F1, Value_Add_bps, Sig_Freq)])
  write.csv(msm_sweep_dt, file.path(OUT_DIR, "msm_threshold_sweep.csv"), row.names = FALSE)
}

# DRV Score threshold sweep (only if DRV has enough data)
if ("DRV_Score_M" %in% names(unified) && sum(!is.na(unified$DRV_Score_M)) > 30) {
  drv_thresholds <- c(20, 30, 40, 50, 60, 70)
  drv_sweep <- list()
  for (th in drv_thresholds) {
    sig <- unified$DRV_Score_M >= th
    sig[is.na(sig)] <- FALSE
    if (sum(sig) >= 3) {
      drv_sweep[[as.character(th)]] <- kpi_a_evaluate(
        sig, unified$Fwd_BM_Ret, unified$Bad_Month, sprintf("DRV Score>=%d", th)
      )
    }
  }
  if (length(drv_sweep) > 0) {
    drv_sweep_dt <- rbindlist(drv_sweep)
    cat("\n  DRV Score Threshold Sweep:\n")
    print(drv_sweep_dt[, list(Model, Precision, Recall, F1, Value_Add_bps, Sig_Freq)])
    write.csv(drv_sweep_dt, file.path(OUT_DIR, "drv_threshold_sweep.csv"), row.names = FALSE)
  }
}

# Optimal AND-gate threshold search: FRED MRS × MSM Prob combination
if ("Macro_Risk_Score" %in% names(unified) && "MSM_Crisis_Prob" %in% names(unified)) {
  and_grid <- expand.grid(fred_th = c(20, 25, 30, 35), msm_th = c(0.3, 0.4, 0.5, 0.6))
  and_sweep <- list()
  for (i in 1:nrow(and_grid)) {
    f_th <- and_grid$fred_th[i]; m_th <- and_grid$msm_th[i]
    sig <- (unified$Macro_Risk_Score >= f_th) & (unified$MSM_Crisis_Prob >= m_th)
    sig[is.na(sig)] <- FALSE
    if (sum(sig) >= 3) {
      and_sweep[[paste(f_th, m_th)]] <- kpi_a_evaluate(
        sig, unified$Fwd_BM_Ret, unified$Bad_Month,
        sprintf("AND(FRED>=%d,MSM>=%.1f)", f_th, m_th)
      )
    }
  }
  if (length(and_sweep) > 0) {
    and_sweep_dt <- rbindlist(and_sweep)
    cat("\n  FRED × MSM AND-gate Grid Search:\n")
    print(and_sweep_dt[, list(Model, Precision, Recall, F1, Value_Add_bps, Sig_Freq)])
    write.csv(and_sweep_dt, file.path(OUT_DIR, "and_gate_grid_search.csv"), row.names = FALSE)
  }
}

#==============================================================================
# PART 7: Visualization
#==============================================================================
cat("\n=== PART 7: Visualization ===\n")

# 7a. KPI-A comparison bar chart
if (nrow(kpi_a_dt) > 1) {
  p_kpi_a <- ggplot(kpi_a_dt, aes(x = reorder(Model, -F1), y = F1, fill = Model)) +
    geom_col(alpha = 0.8) +
    geom_text(aes(label = sprintf("%.3f", F1)), vjust = -0.5, size = 3.5) +
    labs(title = "KPI-A: Next-Month Decline Prediction (F1 Score)",
         x = NULL, y = "F1 Score") +
    theme_minimal(base_size = 12) +
    theme(legend.position = "none", axis.text.x = element_text(angle = 15, hjust = 1))
  ggsave(file.path(OUT_DIR, "kpi_a_f1_comparison.png"), p_kpi_a, width = 10, height = 6, dpi = 130)
  cat("  Saved: kpi_a_f1_comparison.png\n")
}

# 7b. KPI-B: DD Avoided + CVaR Reduction
if (nrow(kpi_b_dt) > 1) {
  kpi_b_long <- melt(kpi_b_dt[, list(Model, DD_Avoided_Pct, CVaR_Reduction)],
                     id.vars = "Model", variable.name = "Metric", value.name = "Value")
  p_kpi_b <- ggplot(kpi_b_long, aes(x = reorder(Model, -Value), y = Value, fill = Metric)) +
    geom_col(position = "dodge", alpha = 0.8) +
    labs(title = "KPI-B: Downside Risk Defense (Higher = Better)",
         x = NULL, y = "Percentage (%)") +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_text(angle = 15, hjust = 1))
  ggsave(file.path(OUT_DIR, "kpi_b_defense_comparison.png"), p_kpi_b, width = 10, height = 6, dpi = 130)
  cat("  Saved: kpi_b_defense_comparison.png\n")
}

# 7c. Derivatives signals time series (if available)
if (nrow(drv_dt) > 0 && "DRV_Score" %in% names(drv_dt)) {
  p_drv <- ggplot(drv_dt[!is.na(DRV_Score)], aes(x = Date, y = DRV_Score)) +
    geom_line(color = "#d62728", linewidth = 0.8) +
    geom_hline(yintercept = 40, linetype = "dashed", color = "orange") +
    geom_hline(yintercept = 60, linetype = "dashed", color = "red") +
    labs(title = "Derivatives Regime Score (0-100)", x = NULL, y = "DRV Score") +
    theme_minimal(base_size = 12)
  ggsave(file.path(OUT_DIR, "drv_score_timeseries.png"), p_drv, width = 11, height = 5, dpi = 130)
  cat("  Saved: drv_score_timeseries.png\n")
}

# 7d. Multi-model signal overlay
if (nrow(unified) > 30) {
  plot_dt <- unified[!is.na(BM_Ret_M)]
  plot_dt[, BM_Cum := cumprod(1 + BM_Ret_M)]
  plot_dt[, Date := as.Date(paste0(YM, "-15"))]

  p_overlay <- ggplot(plot_dt, aes(x = Date)) +
    geom_line(aes(y = BM_Cum), color = "black", linewidth = 0.6) +
    labs(title = "Benchmark + Regime Alerts Overlay", x = NULL, y = "Cumulative Return") +
    theme_minimal(base_size = 11)

  if ("FRED_Alert" %in% names(plot_dt)) {
    fred_shades <- plot_dt[FRED_Alert == TRUE]
    if (nrow(fred_shades) > 0) {
      p_overlay <- p_overlay +
        geom_point(data = fred_shades, aes(y = BM_Cum), color = "red", shape = 4, size = 2, alpha = 0.6)
    }
  }
  if ("MSM_Alert" %in% names(plot_dt)) {
    msm_shades <- plot_dt[MSM_Alert == TRUE]
    if (nrow(msm_shades) > 0) {
      p_overlay <- p_overlay +
        geom_point(data = msm_shades, aes(y = BM_Cum), color = "blue", shape = 1, size = 2, alpha = 0.6)
    }
  }

  ggsave(file.path(OUT_DIR, "multi_model_overlay.png"), p_overlay, width = 12, height = 6, dpi = 130)
  cat("  Saved: multi_model_overlay.png\n")
}

#==============================================================================
# PART 8: Save Results
#==============================================================================
cat("\n=== PART 8: Save results ===\n")

# Save KPI tables
write.csv(kpi_a_dt, file.path(OUT_DIR, "kpi_a_decline_prediction.csv"), row.names = FALSE)
write.csv(kpi_b_dt, file.path(OUT_DIR, "kpi_b_downside_defense.csv"), row.names = FALSE)
if (exists("sweep_dt")) {
  write.csv(sweep_dt, file.path(OUT_DIR, "fred_threshold_sweep.csv"), row.names = FALSE)
}

# Save unified monthly data
write_parquet(unified, file.path(OUT_DIR, "unified_regime_monthly.parquet"))

# Save derivatives daily data
if (nrow(drv_dt) > 0) {
  write_parquet(drv_dt, file.path(OUT_DIR, "derivatives_indicators_daily.parquet"))
}

cat("\n=== Summary ===\n")
cat(sprintf("KPI-A results: %d models evaluated\n", nrow(kpi_a_dt)))
cat(sprintf("KPI-B results: %d models evaluated\n", nrow(kpi_b_dt)))
if (nrow(drv_dt) > 0) {
  cat(sprintf("Derivatives data: %d days (%s ~ %s)\n",
              nrow(drv_dt), min(drv_dt$Date), max(drv_dt$Date)))
}
cat(sprintf("Output: %s\n", OUT_DIR))
cat("[derivatives_regime] Research complete.\n")
