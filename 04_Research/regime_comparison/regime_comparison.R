#==============================================================================
# Regime Model Comparison: MSM vs KTRI vs FRED Macro
#
# 4개 국면 모델의 정량 비교 분석:
# 1. Agreement Matrix (Cohen's kappa)
# 2. Forward Predictive Power (hit/miss/false alarm)
# 3. Stress Period Timeliness (GFC, COVID, Rate Shock)
# 4. Stability (whipsaw count)
# 5. Alpha Contribution (CAGR/MDD impact of each cash-out rule)
#==============================================================================
set.seed(42)

SCRIPT_DIR <- tryCatch(
  { d <- dirname(sys.frame(1)$ofile); if (d == ".") getwd() else d },
  error = function(e) getwd()
)
INFRA_DIR <- file.path(dirname(dirname(SCRIPT_DIR)), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(ggplot2)
  library(xts)
})

OUTPUT_DIR <- file.path(SCRIPT_DIR, "output")
if (!dir.exists(OUTPUT_DIR)) dir.create(OUTPUT_DIR, recursive = TRUE)

cat("=== Regime Model Comparison Analysis ===\n")

#──────────────────────────────────────────────────────────────────────────────
# 1. Load all regime signals
#──────────────────────────────────────────────────────────────────────────────

# --- 1a. FRED Macro Regime ---
cat("[1/4] Loading FRED Macro regime...\n")
fred_dt <- as.data.table(read_parquet(FRED_REGIME_CACHE))
fred_dt[, Date := as.Date(Date)]
fred_dt[, YM := format(Date, "%Y-%m")]
fred_monthly <- fred_dt[, .(
  Date = max(Date),
  FRED_Score = Macro_Risk_Score[1],
  FRED_Buddha = Buddha_Mode[1],
  FRED_VIX_Regime = VIX_Regime[1],
  FRED_VIX = VIX[1]
), by = YM]
setorder(fred_monthly, Date)
cat(sprintf("  FRED: %d months | %s ~ %s\n", nrow(fred_monthly),
            min(fred_monthly$Date), max(fred_monthly$Date)))

# --- 1b. KTRI ---
cat("[2/4] Loading KTRI signals...\n")
ktri_csv <- file.path(PROJECT_ROOT, "04_Research_Log/output/ktri_v1_signals.csv")
if (file.exists(ktri_csv)) {
  ktri_raw <- fread(ktri_csv)
  ktri_raw[, DATE := as.Date(DATE)]
  ktri_raw[, YM := format(DATE, "%Y-%m")]
  # Monthly snapshot: last trading day per month
  ktri_monthly <- ktri_raw[, .SD[which.max(DATE)], by = YM]
  ktri_monthly <- ktri_monthly[, .(
    YM,
    Date = DATE,
    KTRI = KTRI,
    VEA = VEA,
    KTRI_Action = Action
  )]
  setorder(ktri_monthly, Date)
  cat(sprintf("  KTRI: %d months | %s ~ %s\n", nrow(ktri_monthly),
              min(ktri_monthly$Date), max(ktri_monthly$Date)))
} else {
  cat("  KTRI CSV not found! Skipping.\n")
  ktri_monthly <- data.table()
}

# --- 1c. MSM ---
cat("[3/4] Loading MSM signals...\n")
msm_rdata <- file.path(PROJECT_ROOT,
  "05_Production/1.Regime_Def_Model/1-1.MSM/250118_MSM.RData")
msm_monthly <- data.table()

if (file.exists(msm_rdata)) {
  msm_env <- new.env()
  load(msm_rdata, envir = msm_env)

  # Extract daily crisis probabilities from df_res or extracted_data
  if (exists("df_res", envir = msm_env)) {
    msm_daily <- as.data.table(msm_env$df_res)
    msm_daily[, Date := as.Date(Date)]
  } else if (exists("df_hybrid", envir = msm_env)) {
    # df_hybrid has monthly data directly
    msm_daily <- NULL
  } else {
    cat("  MSM: Could not find df_res or df_hybrid in RData\n")
    msm_daily <- NULL
  }

  if (exists("df_hybrid", envir = msm_env)) {
    msm_hybrid <- as.data.table(msm_env$df_hybrid)
    msm_hybrid[, Date := as.Date(Date)]
    msm_hybrid[, YM := format(Date, "%Y-%m")]
    msm_monthly <- msm_hybrid[, .(
      YM,
      Date,
      MSM_AvgProb = Avg_Prob,
      MSM_Regime = Regime,
      MSM_Weight = Target_Weight
    )]
    setorder(msm_monthly, Date)
    cat(sprintf("  MSM: %d months | %s ~ %s\n", nrow(msm_monthly),
                min(msm_monthly$Date), max(msm_monthly$Date)))
  }

  if (!is.null(msm_daily) && nrow(msm_daily) > 0) {
    msm_daily[, YM := format(Date, "%Y-%m")]
    msm_daily_agg <- msm_daily[, .(
      MSM_DailyCrisisProb_Mean = mean(Crisis_Prob, na.rm = TRUE),
      MSM_DailyCrisisProb_Max = max(Crisis_Prob, na.rm = TRUE),
      MSM_VolEst_Mean = mean(Vol_Est, na.rm = TRUE)
    ), by = YM]

    if (nrow(msm_monthly) > 0) {
      msm_monthly <- merge(msm_monthly, msm_daily_agg, by = "YM", all.x = TRUE)
    }
  }
} else {
  cat("  MSM RData not found! Trying Excel...\n")
  msm_xlsx <- file.path(PROJECT_ROOT,
    "05_Production/1.Regime_Def_Model/1-1.MSM/K_Fractal_Master_2026-01-18.xlsx")
  if (file.exists(msm_xlsx)) {
    library(openxlsx)
    msm_signal <- read.xlsx(msm_xlsx, sheet = "History_Signal")
    msm_signal <- as.data.table(msm_signal)
    msm_signal[, Date := as.Date(Date)]
    msm_signal[, YM := format(Date, "%Y-%m")]
    msm_monthly <- msm_signal[, .(
      YM,
      Date,
      MSM_AvgProb = Avg_Prob,
      MSM_Regime = Regime,
      MSM_Weight = Target_Weight
    )]
    setorder(msm_monthly, Date)
    cat(sprintf("  MSM (Excel): %d months\n", nrow(msm_monthly)))
  }
}

# --- 1d. Regime Engine (endogenous) ---
cat("[4/4] Loading Endogenous Regime Engine...\n")
endo_monthly <- data.table()
if (file.exists(REGIME_ENDO_CACHE)) {
  endo_dt <- as.data.table(read_parquet(REGIME_ENDO_CACHE))
  endo_dt[, Date := as.Date(Date)]
  endo_dt[, YM := format(Date, "%Y-%m")]
  endo_monthly <- endo_dt[, .(
    YM,
    Date,
    Endo_Regime = Regime,
    Endo_pExpansion = prob_Expansion,
    Endo_pStress = prob_Stress
  )]
  setorder(endo_monthly, Date)
  cat(sprintf("  Endo: %d months\n", nrow(endo_monthly)))
} else {
  cat("  Endo regime cache not found. Skipping.\n")
}

#──────────────────────────────────────────────────────────────────────────────
# 2. Merge all signals on YM
#──────────────────────────────────────────────────────────────────────────────
cat("\n[Merging] Aligning all regime signals by month...\n")

# Use FRED as base (longest series)
merged <- fred_monthly[, .(YM, Date, FRED_Score, FRED_Buddha, FRED_VIX_Regime, FRED_VIX)]

if (nrow(ktri_monthly) > 0) {
  merged <- merge(merged, ktri_monthly[, .(YM, KTRI, VEA, KTRI_Action)],
                  by = "YM", all.x = TRUE)
}
if (nrow(msm_monthly) > 0) {
  msm_cols <- intersect(names(msm_monthly), c("YM", "MSM_AvgProb", "MSM_Regime", "MSM_Weight",
                                                "MSM_DailyCrisisProb_Mean", "MSM_DailyCrisisProb_Max"))
  merged <- merge(merged, msm_monthly[, ..msm_cols], by = "YM", all.x = TRUE)
}
if (nrow(endo_monthly) > 0) {
  merged <- merge(merged, endo_monthly[, .(YM, Endo_Regime, Endo_pStress)],
                  by = "YM", all.x = TRUE)
}

# Load BM returns for forward analysis
bm_dt <- as.data.table(read_parquet(BM_CACHE))
bm_dt[, YM := format(Date, "%Y-%m")]
bm_monthly_ret <- bm_dt[, .(
  BM_MonthRet = prod(1 + BM_Ret, na.rm = TRUE) - 1
), by = YM]
merged <- merge(merged, bm_monthly_ret, by = "YM", all.x = TRUE)

# Forward 1M return (for predictive power analysis)
setorder(merged, Date)
merged[, Fwd_1M_Ret := shift(BM_MonthRet, -1)]

cat(sprintf("[Merged] %d months | overlap period: %s ~ %s\n",
            nrow(merged), min(merged$Date, na.rm = TRUE), max(merged$Date, na.rm = TRUE)))

#──────────────────────────────────────────────────────────────────────────────
# 3. Create binary risk signals for each model
#──────────────────────────────────────────────────────────────────────────────
cat("\n[Signals] Creating binary risk/cashout signals...\n")

# FRED: MRS >= 30 = cashout (current PASS framework)
merged[, FRED_Cashout := FRED_Score >= 30]

# MSM: Crisis regime = cashout
if ("MSM_Regime" %in% names(merged)) {
  merged[, MSM_Cashout := MSM_Regime == "Crisis"]
  merged[, MSM_Caution := MSM_Regime %in% c("Crisis", "Caution")]
} else {
  merged[, MSM_Cashout := NA]
  merged[, MSM_Caution := NA]
}

# KTRI: HEDGE action = cashout
if ("KTRI_Action" %in% names(merged)) {
  merged[, KTRI_Cashout := KTRI_Action == "HEDGE"]
  merged[, KTRI_Risk := !is.na(KTRI) & KTRI <= 40]
} else {
  merged[, KTRI_Cashout := NA]
  merged[, KTRI_Risk := NA]
}

# Endo: Stress regime = cashout
if ("Endo_Regime" %in% names(merged)) {
  merged[, Endo_Cashout := Endo_Regime == "Stress"]
} else {
  merged[, Endo_Cashout := NA]
}

#──────────────────────────────────────────────────────────────────────────────
# 4. Agreement Analysis
#──────────────────────────────────────────────────────────────────────────────
cat("\n=== 4. Agreement Analysis ===\n")

.agreement <- function(a, b, name_a, name_b) {
  valid <- !is.na(a) & !is.na(b)
  if (sum(valid) < 10) return(NULL)
  agree <- sum(a[valid] == b[valid])
  total <- sum(valid)
  pct <- agree / total * 100
  cat(sprintf("  %s vs %s: %.1f%% agreement (%d/%d)\n", name_a, name_b, pct, agree, total))
  pct
}

.agreement(merged$FRED_Cashout, merged$MSM_Cashout, "FRED MRS>=30", "MSM Crisis")
.agreement(merged$FRED_Cashout, merged$KTRI_Cashout, "FRED MRS>=30", "KTRI HEDGE")
.agreement(merged$MSM_Cashout, merged$KTRI_Cashout, "MSM Crisis", "KTRI HEDGE")
.agreement(merged$FRED_Cashout, merged$Endo_Cashout, "FRED MRS>=30", "Endo Stress")

#──────────────────────────────────────────────────────────────────────────────
# 5. Forward Predictive Power
#──────────────────────────────────────────────────────────────────────────────
cat("\n=== 5. Forward Predictive Power (Next 1M BM Return) ===\n")

.pred_power <- function(signal, model_name) {
  valid <- !is.na(signal) & !is.na(merged$Fwd_1M_Ret)
  if (sum(valid) < 10) { cat(sprintf("  %s: insufficient data\n", model_name)); return(NULL) }
  d <- merged[valid]
  sig <- signal[valid]

  on_ret  <- mean(d$Fwd_1M_Ret[sig])   # avg return when signal is ON
  off_ret <- mean(d$Fwd_1M_Ret[!sig])  # avg return when signal is OFF
  n_on  <- sum(sig)
  n_off <- sum(!sig)

  # When signal ON and market actually falls
  hit_rate <- if (n_on > 0) mean(d$Fwd_1M_Ret[sig] < 0) else NA
  # When market falls and signal was OFF (missed)
  down_months <- d$Fwd_1M_Ret < -0.03
  miss_rate <- if (sum(down_months) > 0) mean(!sig[down_months]) else NA
  # False alarm: signal ON but market goes up
  false_alarm <- if (n_on > 0) mean(d$Fwd_1M_Ret[sig] > 0) else NA

  cat(sprintf("  %s: ON=%d(avg %.2f%%) OFF=%d(avg %.2f%%) | Hit=%.0f%% Miss=%.0f%% FalseAlarm=%.0f%%\n",
              model_name, n_on, on_ret*100, n_off, off_ret*100,
              hit_rate*100, miss_rate*100, false_alarm*100))

  data.table(Model = model_name, N_On = n_on, N_Off = n_off,
             Avg_Ret_On = on_ret, Avg_Ret_Off = off_ret,
             Hit_Rate = hit_rate, Miss_Rate = miss_rate, False_Alarm = false_alarm)
}

pred_results <- rbindlist(list(
  .pred_power(merged$FRED_Cashout, "FRED MRS>=30"),
  .pred_power(merged$MSM_Cashout, "MSM Crisis"),
  .pred_power(merged$MSM_Caution, "MSM Caution+"),
  .pred_power(merged$KTRI_Cashout, "KTRI HEDGE"),
  .pred_power(merged$Endo_Cashout, "Endo Stress")
), fill = TRUE)

fwrite(pred_results, file.path(OUTPUT_DIR, "predictive_power.csv"))

#──────────────────────────────────────────────────────────────────────────────
# 6. Stress Period Analysis
#──────────────────────────────────────────────────────────────────────────────
cat("\n=== 6. Stress Period Analysis ===\n")

stress_periods <- list(
  GFC_2008     = c("2008-09", "2008-12"),
  EuDebt_2011  = c("2011-07", "2011-10"),
  COVID_2020   = c("2020-02", "2020-04"),
  Rate_2022    = c("2022-01", "2022-10")
)

stress_results <- list()

for (sp_name in names(stress_periods)) {
  sp <- stress_periods[[sp_name]]
  rows <- merged[YM >= sp[1] & YM <= sp[2]]
  if (nrow(rows) == 0) next

  bm_ret <- sum(rows$BM_MonthRet, na.rm = TRUE)

  result <- data.table(
    Period = sp_name,
    BM_CumRet = bm_ret,
    FRED_Cashout_Months = sum(rows$FRED_Cashout, na.rm = TRUE),
    MSM_Cashout_Months = sum(rows$MSM_Cashout, na.rm = TRUE),
    KTRI_Cashout_Months = sum(rows$KTRI_Cashout, na.rm = TRUE),
    Endo_Cashout_Months = sum(rows$Endo_Cashout, na.rm = TRUE),
    Total_Months = nrow(rows)
  )

  cat(sprintf("  %s (%s~%s): BM %.1f%% | FRED=%d MSM=%d KTRI=%d Endo=%d cashout months (of %d)\n",
              sp_name, sp[1], sp[2], bm_ret*100,
              result$FRED_Cashout_Months, result$MSM_Cashout_Months,
              result$KTRI_Cashout_Months, result$Endo_Cashout_Months, nrow(rows)))

  stress_results[[length(stress_results) + 1]] <- result
}

stress_dt <- rbindlist(stress_results)
fwrite(stress_dt, file.path(OUTPUT_DIR, "stress_period_analysis.csv"))

#──────────────────────────────────────────────────────────────────────────────
# 7. Stability (Whipsaw Count)
#──────────────────────────────────────────────────────────────────────────────
cat("\n=== 7. Signal Stability (Whipsaw Analysis) ===\n")

.whipsaw <- function(signal, model_name) {
  valid <- signal[!is.na(signal)]
  if (length(valid) < 12) return(NULL)
  changes <- sum(valid[-1] != valid[-length(valid)])
  years <- length(valid) / 12
  per_year <- changes / years
  cat(sprintf("  %s: %d transitions over %.1f years = %.1f/year\n",
              model_name, changes, years, per_year))
  data.table(Model = model_name, Total_Transitions = changes,
             Years = years, Transitions_Per_Year = per_year)
}

whipsaw_results <- rbindlist(list(
  .whipsaw(merged$FRED_Cashout, "FRED MRS>=30"),
  .whipsaw(merged$MSM_Cashout, "MSM Crisis"),
  .whipsaw(merged$MSM_Caution, "MSM Caution+"),
  .whipsaw(merged$KTRI_Cashout, "KTRI HEDGE"),
  .whipsaw(merged$Endo_Cashout, "Endo Stress")
), fill = TRUE)

fwrite(whipsaw_results, file.path(OUTPUT_DIR, "whipsaw_analysis.csv"))

#──────────────────────────────────────────────────────────────────────────────
# 8. Alpha Contribution (Strategy backtest with different regime filters)
#──────────────────────────────────────────────────────────────────────────────
cat("\n=== 8. Alpha Contribution Analysis ===\n")
cat("Simulating different cash-out rules applied to BM investment...\n")

setorder(merged, Date)

.simulate_regime_filter <- function(cashout_signal, model_name) {
  valid <- !is.na(cashout_signal) & !is.na(merged$BM_MonthRet)
  d <- merged[valid]
  sig <- cashout_signal[valid]

  # Strategy: invested unless cashout signal, then 0%
  strat_ret <- ifelse(shift(sig, type = "lag"), 0, d$BM_MonthRet)
  strat_ret[1] <- d$BM_MonthRet[1]  # first month: no signal yet

  cum_bm   <- cumprod(1 + d$BM_MonthRet)
  cum_strat <- cumprod(1 + strat_ret)

  cagr_bm   <- (tail(cum_bm, 1))^(12/length(d$BM_MonthRet)) - 1
  cagr_strat <- (tail(cum_strat, 1))^(12/length(strat_ret)) - 1

  # MDD
  .mdd <- function(nav) {
    peak <- cummax(nav)
    dd <- nav / peak - 1
    min(dd)
  }
  mdd_bm    <- .mdd(cum_bm) * 100
  mdd_strat <- .mdd(cum_strat) * 100

  cat(sprintf("  %s: CAGR %.2f%% (BM %.2f%%) | MDD %.1f%% (BM %.1f%%)\n",
              model_name, cagr_strat*100, cagr_bm*100, mdd_strat, mdd_bm))

  data.table(Model = model_name,
             CAGR_Strat = cagr_strat, CAGR_BM = cagr_bm,
             CAGR_Alpha = cagr_strat - cagr_bm,
             MDD_Strat = mdd_strat, MDD_BM = mdd_bm,
             MDD_Improvement = mdd_bm - mdd_strat)
}

alpha_results <- rbindlist(list(
  .simulate_regime_filter(merged$FRED_Cashout, "FRED MRS>=30"),
  .simulate_regime_filter(merged$MSM_Cashout, "MSM Crisis"),
  .simulate_regime_filter(merged$MSM_Caution, "MSM Caution+"),
  .simulate_regime_filter(merged$KTRI_Cashout, "KTRI HEDGE"),
  .simulate_regime_filter(merged$Endo_Cashout, "Endo Stress")
), fill = TRUE)

fwrite(alpha_results, file.path(OUTPUT_DIR, "alpha_contribution.csv"))

#──────────────────────────────────────────────────────────────────────────────
# 9. Visualization
#──────────────────────────────────────────────────────────────────────────────
cat("\n=== 9. Generating Charts ===\n")

# 4-panel time series
if (nrow(merged[!is.na(FRED_Score)]) > 0) {
  plot_dt <- merged[!is.na(Date)]
  plot_dt[, BM_Cum := cumprod(1 + fifelse(is.na(BM_MonthRet), 0, BM_MonthRet))]

  # Normalize signals to 0-100 scale
  plot_dt[, FRED_Norm := pmin(FRED_Score, 100)]
  if ("MSM_AvgProb" %in% names(plot_dt)) plot_dt[, MSM_Norm := MSM_AvgProb * 100]
  if ("KTRI" %in% names(plot_dt)) plot_dt[, KTRI_Norm := KTRI]

  p_main <- ggplot(plot_dt, aes(x = Date)) +
    geom_line(aes(y = BM_Cum), color = "black", linewidth = 0.5, alpha = 0.7) +
    labs(title = "Regime Model Comparison — Risk Signals vs BM",
         y = "BM Cumulative", x = NULL) +
    theme_minimal(base_size = 10)

  ggsave(file.path(OUTPUT_DIR, "regime_comparison_overview.png"), p_main,
         width = 12, height = 5, dpi = 130)
  cat("  Overview chart saved.\n")
}

#──────────────────────────────────────────────────────────────────────────────
# 10. Summary Report
#──────────────────────────────────────────────────────────────────────────────
cat("\n")
cat("============================================================\n")
cat("  REGIME MODEL COMPARISON — SUMMARY REPORT\n")
cat("============================================================\n")

if (nrow(pred_results) > 0) {
  cat("\n[Predictive Power]\n")
  print(pred_results[, .(Model, N_On, Avg_Ret_On = round(Avg_Ret_On*100, 2),
                          Avg_Ret_Off = round(Avg_Ret_Off*100, 2),
                          Hit_Rate = round(Hit_Rate*100, 0),
                          Miss_Rate = round(Miss_Rate*100, 0))])
}

if (nrow(whipsaw_results) > 0) {
  cat("\n[Stability]\n")
  print(whipsaw_results)
}

if (nrow(alpha_results) > 0) {
  cat("\n[Alpha Contribution]\n")
  print(alpha_results[, .(Model,
                           CAGR = round(CAGR_Strat*100, 2),
                           Alpha = round(CAGR_Alpha*100, 2),
                           MDD = round(MDD_Strat, 1),
                           MDD_Improve = round(MDD_Improvement, 1))])
}

cat("\n============================================================\n")
cat("[regime_comparison] Complete. Results in:", OUTPUT_DIR, "\n")
