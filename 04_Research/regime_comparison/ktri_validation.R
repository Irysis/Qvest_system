#==============================================================================
# KTRI Quantitative Validation & Reinforcement
# KPI-A (Decline Prediction) + KPI-B (Downside Defense) + Stress Period Analysis
# Comparable framework to FRED/MSM evaluation
#==============================================================================
cat("[KTRI Validation] Starting...\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(zoo)
  library(dplyr)
  library(ggplot2)
})

# ── Paths ──
PROJECT_ROOT <- tryCatch({
  d <- dirname(sys.frame(1)$ofile)
  dirname(dirname(d))
}, error = function(e) getwd())

out_dir <- file.path(PROJECT_ROOT, "outputs", "regime", "output")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

#==============================================================================
# PART 1: Load KTRI signals + BM data
#==============================================================================
cat("[KTRI Validation] Loading data...\n")

# KTRI daily signals
ktri_csv <- file.path(PROJECT_ROOT, "04_Research_Log", "output", "ktri_v1_signals.csv")
ktri_dt <- fread(ktri_csv)
ktri_dt[, DATE := as.Date(DATE)]
setorder(ktri_dt, DATE)

cat(sprintf("  KTRI signals: %d rows (%s ~ %s)\n",
            nrow(ktri_dt), min(ktri_dt$DATE), max(ktri_dt$DATE)))

# BM data for forward return calculation
bm_cache <- file.path(PROJECT_ROOT, ".cache", "benchmark.parquet")
if (file.exists(bm_cache)) {
  BM_DT <- as.data.table(arrow::read_parquet(bm_cache))
} else {
  # Fallback: use IKS200 from KTRI itself
  BM_DT <- ktri_dt[, .(Date = DATE, BM_Close = IKS200)]
}
if (!"Date" %in% names(BM_DT) && "DATE" %in% names(BM_DT)) setnames(BM_DT, "DATE", "Date")
BM_DT <- BM_DT[!is.na(BM_Close) & BM_Close > 0][order(Date)]
BM_DT[, BM_Ret := c(NA, diff(log(BM_Close)))]

# Merge KTRI with BM
merged <- merge(ktri_dt, BM_DT[, .(Date, BM_Close, BM_Ret)],
                by.x = "DATE", by.y = "Date", all.x = TRUE)
setorder(merged, DATE)

# Forward returns (1M = 21 days, 3M = 63 days)
merged[, Fwd_21d := shift(zoo::rollsum(BM_Ret, 21, align = "left", fill = NA), n = 0, type = "lead")]
merged[, Fwd_63d := shift(zoo::rollsum(BM_Ret, 63, align = "left", fill = NA), n = 0, type = "lead")]
# Simple forward return (for compatibility)
merged[, `:=`(
  Fwd_1M_Ret = shift(BM_Close, -21) / BM_Close - 1,
  Fwd_3M_Ret = shift(BM_Close, -63) / BM_Close - 1
)]

cat(sprintf("  Merged: %d rows with BM data\n", sum(!is.na(merged$BM_Ret))))

#==============================================================================
# PART 2: Define KTRI regime signals (daily → multiple variants)
#==============================================================================
cat("[KTRI Validation] Defining signal variants...\n")

# Variant 1: KTRI level-based (simple)
merged[, KTRI_Low := !is.na(KTRI) & KTRI <= 40]
merged[, KTRI_VeryLow := !is.na(KTRI) & KTRI <= 30]

# Variant 2: VEA level-based
merged[, VEA_High := !is.na(VEA) & VEA >= 70]
merged[, VEA_VeryHigh := !is.na(VEA) & VEA >= 80]

# Variant 3: Action-based
merged[, HEDGE_Signal := Action == "HEDGE"]

# Variant 4: Combined (KTRI low OR VEA high)
merged[, KTRI_OR_VEA := KTRI_Low | VEA_High]

# Variant 5: Strict (KTRI low AND VEA high)
merged[, KTRI_AND_VEA := KTRI_Low & VEA_High]

# Variant 6: Delta-based (momentum deteriorating)
merged[, Delta_Neg := !is.na(Delta_KTRI) & Delta_KTRI < -1]

# Variant 7: Multi-condition (KTRI<40 AND Delta<0)
merged[, KTRI_Delta := KTRI_Low & Delta_Neg]

# Variant 8: VEA rising + KTRI falling
merged[, VEA_Rising := !is.na(VEA) & !is.na(shift(VEA, 5)) & VEA > shift(VEA, 5) + 3]
merged[, Divergence := VEA_Rising & KTRI_Low]

cat("  Defined 8 signal variants\n")

#==============================================================================
# PART 3: Monthly aggregation (for KPI-A/B comparison with FRED/MSM)
#==============================================================================
cat("[KTRI Validation] Monthly aggregation...\n")

merged[, YM := format(DATE, "%Y-%m")]

monthly <- merged[!is.na(KTRI), .(
  KTRI_Avg    = mean(KTRI, na.rm = TRUE),
  KTRI_Min    = min(KTRI, na.rm = TRUE),
  VEA_Avg     = mean(VEA, na.rm = TRUE),
  VEA_Max     = max(VEA, na.rm = TRUE),
  Delta_Avg   = mean(Delta_KTRI, na.rm = TRUE),
  N_Hedge     = sum(Action == "HEDGE", na.rm = TRUE),
  N_Days      = .N,
  Hedge_Pct   = sum(Action == "HEDGE", na.rm = TRUE) / .N,
  BM_Close    = tail(BM_Close[!is.na(BM_Close)], 1),
  Date        = max(DATE)
), by = YM]
setorder(monthly, YM)

# Forward monthly return
monthly[, Fwd_BM_Ret := shift(BM_Close, -1) / BM_Close - 1]
monthly[, Bad_Month := Fwd_BM_Ret < -0.03]       # >3% decline
monthly[, Severe_Month := Fwd_BM_Ret < -0.05]     # >5% decline

# Monthly signal variants
monthly[, `:=`(
  Sig_KTRI_Low      = KTRI_Avg <= 40,
  Sig_KTRI_VeryLow  = KTRI_Avg <= 30,
  Sig_VEA_High      = VEA_Avg >= 70,
  Sig_VEA_VeryHigh  = VEA_Avg >= 80,
  Sig_Hedge_Dom     = Hedge_Pct >= 0.5,     # >50% days HEDGE
  Sig_Hedge_Any     = Hedge_Pct >= 0.3,     # >30% days HEDGE
  Sig_KTRI_OR_VEA   = KTRI_Avg <= 40 | VEA_Avg >= 70,
  Sig_KTRI_AND_VEA  = KTRI_Avg <= 40 & VEA_Avg >= 70,
  Sig_Delta_Neg     = Delta_Avg < -0.5,
  Sig_Min_Low       = KTRI_Min <= 30        # Any day touched <=30
)]

cat(sprintf("  Monthly data: %d months, Bad months: %d (%.1f%%)\n",
            nrow(monthly),
            sum(monthly$Bad_Month, na.rm = TRUE),
            100 * mean(monthly$Bad_Month, na.rm = TRUE)))

#==============================================================================
# PART 4: KPI-A — Decline Prediction Power
#==============================================================================
cat("[KTRI Validation] KPI-A: Decline prediction...\n")

kpi_a_evaluate <- function(signal, fwd_ret, bad_flag, model_name) {
  valid <- !is.na(signal) & !is.na(fwd_ret) & !is.na(bad_flag)
  sig <- signal[valid]
  bad <- bad_flag[valid]
  ret <- fwd_ret[valid]

  TP <- sum(sig & bad)
  FP <- sum(sig & !bad)
  FN <- sum(!sig & bad)
  TN <- sum(!sig & !bad)

  precision  <- ifelse(TP + FP > 0, TP / (TP + FP), NA)
  recall     <- ifelse(TP + FN > 0, TP / (TP + FN), NA)
  specificity <- ifelse(TN + FP > 0, TN / (TN + FP), NA)
  f1         <- ifelse(!is.na(precision) & !is.na(recall) & (precision + recall) > 0,
                       2 * precision * recall / (precision + recall), NA)
  false_alarm <- ifelse(TN + FP > 0, FP / (TN + FP), NA)

  ret_signal <- mean(ret[sig], na.rm = TRUE)
  ret_nosig  <- mean(ret[!sig], na.rm = TRUE)
  value_add  <- ifelse(!is.na(ret_nosig) & !is.na(ret_signal),
                       (ret_nosig - ret_signal) * 10000, NA)

  data.table(
    Model       = model_name,
    N_Total     = sum(valid),
    N_Signal    = sum(sig),
    Sig_Freq    = round(mean(sig), 3),
    TP = TP, FP = FP, FN = FN, TN = TN,
    Precision   = round(precision, 3),
    Recall      = round(recall, 3),
    Specificity = round(specificity, 3),
    F1          = round(f1, 3),
    False_Alarm = round(false_alarm, 3),
    Ret_Signal  = round(ret_signal, 4),
    Ret_NoSig   = round(ret_nosig, 4),
    Value_Add_bps = round(value_add, 0)
  )
}

# Run KPI-A for all KTRI variants
kpi_a_models <- list(
  c("Sig_KTRI_Low",      "KTRI<=40 (Avg)"),
  c("Sig_KTRI_VeryLow",  "KTRI<=30 (Avg)"),
  c("Sig_VEA_High",      "VEA>=70 (Avg)"),
  c("Sig_VEA_VeryHigh",  "VEA>=80 (Avg)"),
  c("Sig_Hedge_Dom",     "HEDGE>=50% days"),
  c("Sig_Hedge_Any",     "HEDGE>=30% days"),
  c("Sig_KTRI_OR_VEA",   "KTRI<=40 OR VEA>=70"),
  c("Sig_KTRI_AND_VEA",  "KTRI<=40 AND VEA>=70"),
  c("Sig_Delta_Neg",     "Delta_KTRI<-0.5"),
  c("Sig_Min_Low",       "KTRI_Min<=30 (Any Day)")
)

kpi_a_results <- rbindlist(lapply(kpi_a_models, function(m) {
  kpi_a_evaluate(monthly[[m[1]]], monthly$Fwd_BM_Ret, monthly$Bad_Month, m[2])
}))

# Also load existing FRED/MSM results for comparison
existing_kpi <- file.path(out_dir, "kpi_a_decline_prediction.csv")
if (file.exists(existing_kpi)) {
  ref_kpi <- fread(existing_kpi)
  kpi_a_combined <- rbind(ref_kpi, kpi_a_results, fill = TRUE)
} else {
  kpi_a_combined <- kpi_a_results
}

fwrite(kpi_a_combined, file.path(out_dir, "kpi_a_ktri_comparison.csv"))
cat("\n=== KPI-A: KTRI Decline Prediction (>3% monthly loss) ===\n")
print(kpi_a_results[order(-F1)], nrow = 20)

#==============================================================================
# PART 5: KPI-B — Downside Defense (Cash-out strategy)
#==============================================================================
cat("\n[KTRI Validation] KPI-B: Downside defense...\n")

kpi_b_evaluate <- function(dt_daily, signal_col, model_name) {
  d <- copy(dt_daily[!is.na(BM_Ret)])
  d[, Signal := get(signal_col)]
  d[, Signal := fifelse(is.na(Signal), FALSE, Signal)]

  # Strategy: hold cash when Signal=TRUE
  d[, Strat_Ret := fifelse(Signal, 0, BM_Ret)]

  # Cumulative returns
  d[, BH_Cum := cumprod(1 + BM_Ret)]
  d[, Strat_Cum := cumprod(1 + Strat_Ret)]

  # Drawdowns
  d[, BH_Peak := cummax(BH_Cum)]
  d[, BH_DD := BH_Cum / BH_Peak - 1]
  d[, Strat_Peak := cummax(Strat_Cum)]
  d[, Strat_DD := Strat_Cum / Strat_Peak - 1]

  bh_mdd <- min(d$BH_DD, na.rm = TRUE)
  strat_mdd <- min(d$Strat_DD, na.rm = TRUE)

  # CAGR
  n_years <- as.numeric(diff(range(d$DATE))) / 365.25
  bh_cagr <- (tail(d$BH_Cum, 1))^(1/n_years) - 1
  strat_cagr <- (tail(d$Strat_Cum, 1))^(1/n_years) - 1

  # CVaR 5%
  bh_cvar <- mean(sort(d$BM_Ret)[1:max(1, floor(nrow(d) * 0.05))])
  strat_cvar <- mean(sort(d$Strat_Ret)[1:max(1, floor(nrow(d) * 0.05))])

  # Downside capture
  neg_months <- d[BM_Ret < 0]
  down_capture <- ifelse(nrow(neg_months) > 0,
                         sum(neg_months$Strat_Ret) / sum(neg_months$BM_Ret), NA)

  # Sharpe ratio
  strat_sharpe <- mean(d$Strat_Ret, na.rm = TRUE) / sd(d$Strat_Ret, na.rm = TRUE) * sqrt(252)

  data.table(
    Model            = model_name,
    BH_CAGR          = round(bh_cagr * 100, 2),
    Strat_CAGR       = round(strat_cagr * 100, 2),
    CAGR_Diff_pp     = round((strat_cagr - bh_cagr) * 100, 2),
    BH_MDD           = round(bh_mdd * 100, 1),
    Strat_MDD        = round(strat_mdd * 100, 1),
    DD_Avoided_Pct   = round((1 - strat_mdd / bh_mdd) * 100, 1),
    BH_CVaR5         = round(bh_cvar * 100, 2),
    Strat_CVaR5      = round(strat_cvar * 100, 2),
    CVaR_Reduction   = round((1 - strat_cvar / bh_cvar) * 100, 1),
    Down_Capture     = round(down_capture * 100, 1),
    Strat_Sharpe     = round(strat_sharpe, 3),
    Cash_Pct         = round(mean(d$Signal) * 100, 1)
  )
}

# Run KPI-B for daily signal variants
kpi_b_models <- list(
  c("KTRI_Low",     "KTRI<=40"),
  c("KTRI_VeryLow", "KTRI<=30"),
  c("VEA_High",     "VEA>=70"),
  c("VEA_VeryHigh", "VEA>=80"),
  c("HEDGE_Signal", "Action==HEDGE"),
  c("KTRI_OR_VEA",  "KTRI<=40 OR VEA>=70"),
  c("KTRI_AND_VEA", "KTRI<=40 AND VEA>=70"),
  c("Delta_Neg",    "Delta<-1"),
  c("KTRI_Delta",   "KTRI<=40 AND Delta<-1"),
  c("Divergence",   "VEA Rising AND KTRI<=40")
)

kpi_b_results <- rbindlist(lapply(kpi_b_models, function(m) {
  kpi_b_evaluate(merged, m[1], m[2])
}))

fwrite(kpi_b_results, file.path(out_dir, "kpi_b_ktri_defense.csv"))
cat("\n=== KPI-B: KTRI Downside Defense ===\n")
print(kpi_b_results[order(-DD_Avoided_Pct)], nrow = 15)

#==============================================================================
# PART 6: Stress Period Analysis (Timeliness)
#==============================================================================
cat("\n[KTRI Validation] Stress period analysis...\n")

stress_periods <- list(
  GFC       = list(start = as.Date("2008-09-01"), end = as.Date("2009-03-31"),
                   peak = as.Date("2008-05-19"), trough = as.Date("2008-10-24")),
  COVID     = list(start = as.Date("2020-01-20"), end = as.Date("2020-04-30"),
                   peak = as.Date("2020-01-20"), trough = as.Date("2020-03-19")),
  RateShock = list(start = as.Date("2022-01-03"), end = as.Date("2022-10-31"),
                   peak = as.Date("2021-06-25"), trough = as.Date("2022-09-26"))
)

stress_analysis <- rbindlist(lapply(names(stress_periods), function(sp_name) {
  sp <- stress_periods[[sp_name]]

  # Window: 2 months before start to 1 month after end
  window <- merged[DATE >= (sp$start - 60) & DATE <= (sp$end + 30)]
  if (nrow(window) == 0) return(NULL)

  # Find first HEDGE signal date
  first_hedge <- window[Action == "HEDGE" & DATE >= (sp$start - 60), min(DATE)]
  if (is.infinite(first_hedge)) first_hedge <- NA

  # Find first KTRI<=40 date
  first_ktri_low <- window[KTRI_Low == TRUE & DATE >= (sp$start - 60), min(DATE)]
  if (is.infinite(first_ktri_low)) first_ktri_low <- NA

  # Find first VEA>=70 date
  first_vea_high <- window[VEA_High == TRUE & DATE >= (sp$start - 60), min(DATE)]
  if (is.infinite(first_vea_high)) first_vea_high <- NA

  # Lead/lag vs peak (negative = leading, positive = lagging)
  hedge_lead <- as.numeric(first_hedge - sp$peak)
  ktri_lead <- as.numeric(first_ktri_low - sp$peak)
  vea_lead <- as.numeric(first_vea_high - sp$peak)

  # KTRI at key dates
  ktri_at_peak <- window[DATE == sp$peak, KTRI]
  ktri_at_trough <- window[DATE == sp$trough, KTRI]
  vea_at_peak <- window[DATE == sp$peak, VEA]
  vea_at_trough <- window[DATE == sp$trough, VEA]

  # BM drawdown in this period
  window_px <- window[!is.na(BM_Close)]
  if (nrow(window_px) > 0) {
    bm_dd <- min(window_px$BM_Close / cummax(window_px$BM_Close) - 1)
  } else bm_dd <- NA

  data.table(
    Period         = sp_name,
    BM_DD          = round(bm_dd * 100, 1),
    Peak_Date      = sp$peak,
    Trough_Date    = sp$trough,
    First_HEDGE    = first_hedge,
    HEDGE_Lead_d   = hedge_lead,
    First_KTRI_Low = first_ktri_low,
    KTRI_Lead_d    = ktri_lead,
    First_VEA_High = first_vea_high,
    VEA_Lead_d     = vea_lead,
    KTRI_at_Peak   = ifelse(length(ktri_at_peak) > 0, round(ktri_at_peak, 1), NA),
    KTRI_at_Trough = ifelse(length(ktri_at_trough) > 0, round(ktri_at_trough, 1), NA),
    VEA_at_Peak    = ifelse(length(vea_at_peak) > 0, round(vea_at_peak, 1), NA),
    VEA_at_Trough  = ifelse(length(vea_at_trough) > 0, round(vea_at_trough, 1), NA)
  )
}))

fwrite(stress_analysis, file.path(out_dir, "ktri_stress_timing.csv"))
cat("\n=== Stress Period Timing ===\n")
print(stress_analysis)

#==============================================================================
# PART 7: Signal Stability (Whipsaw Analysis)
#==============================================================================
cat("\n[KTRI Validation] Whipsaw analysis...\n")

# Count regime transitions per year
merged[, Year := format(DATE, "%Y")]
transitions <- merged[!is.na(Action), .(
  N_Days = .N,
  N_Transitions = sum(Action != shift(Action, 1), na.rm = TRUE),
  Pct_HEDGE = round(sum(Action == "HEDGE") / .N * 100, 1),
  Pct_ADD = round(sum(Action == "ADD") / .N * 100, 1),
  Pct_NEUTRAL = round(sum(Action == "NEUTRAL") / .N * 100, 1)
), by = Year]
transitions[, Transitions_Per_Month := round(N_Transitions / (N_Days / 21), 1)]

cat("\n=== Action Transitions by Year ===\n")
print(transitions[order(Year)])

avg_whipsaw <- mean(transitions$Transitions_Per_Month, na.rm = TRUE)
cat(sprintf("\n  Average transitions per month: %.1f\n", avg_whipsaw))

#==============================================================================
# PART 8: KTRI Threshold Sweep (Optimization)
#==============================================================================
cat("\n[KTRI Validation] KTRI threshold sweep...\n")

ktri_thresholds <- seq(25, 55, by = 5)
ktri_sweep <- rbindlist(lapply(ktri_thresholds, function(th) {
  monthly[, sig_temp := KTRI_Avg <= th]
  kpi_a_evaluate(monthly$sig_temp, monthly$Fwd_BM_Ret, monthly$Bad_Month,
                 sprintf("KTRI<=%d", th))
}))

vea_thresholds <- seq(55, 90, by = 5)
vea_sweep <- rbindlist(lapply(vea_thresholds, function(th) {
  monthly[, sig_temp := VEA_Avg >= th]
  kpi_a_evaluate(monthly$sig_temp, monthly$Fwd_BM_Ret, monthly$Bad_Month,
                 sprintf("VEA>=%d", th))
}))

sweep_combined <- rbind(ktri_sweep, vea_sweep)
fwrite(sweep_combined, file.path(out_dir, "ktri_threshold_sweep.csv"))

cat("\n=== KTRI Threshold Sweep ===\n")
print(ktri_sweep[order(-F1)])
cat("\n=== VEA Threshold Sweep ===\n")
print(vea_sweep[order(-F1)])

#==============================================================================
# PART 9: KTRI vs FRED/MSM Head-to-Head
#==============================================================================
cat("\n[KTRI Validation] Head-to-head comparison...\n")

# Load unified monthly regime data (has FRED/MSM)
unified_path <- file.path(out_dir, "unified_regime_monthly.parquet")
if (file.exists(unified_path)) {
  unified <- as.data.table(arrow::read_parquet(unified_path))

  # Merge KTRI monthly into unified
  monthly_slim <- monthly[, .(YM, KTRI_Avg, KTRI_Min, VEA_Avg, VEA_Max,
                               Delta_Avg, Hedge_Pct)]
  unified_ktri <- merge(unified, monthly_slim, by = "YM", all.x = TRUE)

  # Define KTRI signals on unified timeframe
  unified_ktri[, KTRI_Alert := !is.na(KTRI_Avg) & KTRI_Avg <= 40]
  unified_ktri[, VEA_Alert := !is.na(VEA_Avg) & VEA_Avg >= 70]
  unified_ktri[, KTRI_OR_VEA_Alert := KTRI_Alert | VEA_Alert]

  # New ensemble: FRED & KTRI AND-gate
  if ("FRED_Alert" %in% names(unified_ktri)) {
    unified_ktri[, FRED_KTRI_AND := FRED_Alert == TRUE & KTRI_Alert == TRUE]
    unified_ktri[, FRED_KTRI_OR := FRED_Alert == TRUE | KTRI_Alert == TRUE]
    unified_ktri[, FRED_VEA_AND := FRED_Alert == TRUE & VEA_Alert == TRUE]
    unified_ktri[, FRED_VEA_OR := FRED_Alert == TRUE | VEA_Alert == TRUE]
  }

  # MSM & KTRI ensembles
  if ("MSM_Alert" %in% names(unified_ktri)) {
    unified_ktri[, MSM_KTRI_AND := MSM_Alert == TRUE & KTRI_Alert == TRUE]
    unified_ktri[, MSM_KTRI_OR := MSM_Alert == TRUE | KTRI_Alert == TRUE]
    unified_ktri[, MSM_VEA_AND := MSM_Alert == TRUE & VEA_Alert == TRUE]
    unified_ktri[, MSM_VEA_OR := MSM_Alert == TRUE | VEA_Alert == TRUE]
  }

  # Triple ensemble: FRED & MSM & KTRI
  if (all(c("FRED_Alert", "MSM_Alert") %in% names(unified_ktri))) {
    unified_ktri[, Triple_Majority := {
      n <- as.integer(FRED_Alert == TRUE) +
           as.integer(MSM_Alert == TRUE) +
           as.integer(KTRI_OR_VEA_Alert == TRUE)
      n >= 2
    }]
    unified_ktri[, Triple_All := FRED_Alert == TRUE & MSM_Alert == TRUE & KTRI_OR_VEA_Alert == TRUE]
  }

  # Evaluate all head-to-head models
  if ("Fwd_BM_Ret" %in% names(unified_ktri)) {
    unified_ktri[, Bad_M := !is.na(Fwd_BM_Ret) & Fwd_BM_Ret < -0.03]

    h2h_models <- list(
      c("FRED_Alert",      "FRED (MRS>=30)"),
      c("MSM_Alert",       "MSM (Crisis>=0.5)"),
      c("KTRI_Alert",      "KTRI (<=40)"),
      c("VEA_Alert",       "VEA (>=70)"),
      c("KTRI_OR_VEA_Alert", "KTRI<=40 OR VEA>=70"),
      c("FRED_KTRI_AND",   "FRED & KTRI AND"),
      c("FRED_KTRI_OR",    "FRED | KTRI OR"),
      c("FRED_VEA_AND",    "FRED & VEA AND"),
      c("FRED_VEA_OR",     "FRED | VEA OR"),
      c("MSM_KTRI_AND",    "MSM & KTRI AND"),
      c("MSM_KTRI_OR",     "MSM | KTRI OR"),
      c("MSM_VEA_AND",     "MSM & VEA AND"),
      c("MSM_VEA_OR",      "MSM | VEA OR"),
      c("Triple_Majority", "Triple Majority (2/3)"),
      c("Triple_All",      "Triple ALL (3/3)")
    )

    # Filter to existing columns
    h2h_models <- h2h_models[sapply(h2h_models, function(m) m[1] %in% names(unified_ktri))]

    h2h_results <- rbindlist(lapply(h2h_models, function(m) {
      kpi_a_evaluate(unified_ktri[[m[1]]], unified_ktri$Fwd_BM_Ret,
                     unified_ktri$Bad_M, m[2])
    }))

    fwrite(h2h_results, file.path(out_dir, "ktri_head_to_head.csv"))
    cat("\n=== Head-to-Head: KPI-A Comparison ===\n")
    print(h2h_results[order(-F1)])
  }

  # Save extended unified for future use
  arrow::write_parquet(unified_ktri, file.path(out_dir, "unified_regime_with_ktri.parquet"))
  cat(sprintf("  Saved unified with KTRI: %d months\n", nrow(unified_ktri)))
}

#==============================================================================
# PART 10: Diagnostic Weaknesses Report
#==============================================================================
cat("\n\n")
cat("================================================================\n")
cat("  KTRI VALIDATION REPORT\n")
cat("================================================================\n\n")

# Summary statistics
valid_ktri <- merged[!is.na(KTRI)]
cat(sprintf("Data Coverage: %d days (%s ~ %s)\n",
            nrow(valid_ktri), min(valid_ktri$DATE), max(valid_ktri$DATE)))
cat(sprintf("KTRI range: %.1f ~ %.1f (mean=%.1f, median=%.1f)\n",
            min(valid_ktri$KTRI), max(valid_ktri$KTRI),
            mean(valid_ktri$KTRI), median(valid_ktri$KTRI)))
cat(sprintf("VEA range: %.1f ~ %.1f (mean=%.1f, median=%.1f)\n",
            min(valid_ktri$VEA), max(valid_ktri$VEA),
            mean(valid_ktri$VEA), median(valid_ktri$VEA)))

cat("\n--- Known Weaknesses ---\n")
cat("1. IKS221 (VKOSPI) NA pre-2003: ZD=NA, uses ZA+ZB+ZC only\n")
cat(sprintf("   IKS221 NA rows: %d / %d (%.1f%%)\n",
            sum(is.na(merged$IKS221)), nrow(merged),
            100 * sum(is.na(merged$IKS221)) / nrow(merged)))

cat("\n2. Breadth proxy (v1): 10 indices, not actual K200 constituents\n")

cat("\n3. Dynamic quantiles: Uses full-sample → lookahead bias\n")
cat("   Fix: Use expanding window or fixed thresholds\n")

cat("\n4. 5-day min hold: Delays regime switch during fast crashes\n")
cat(sprintf("   Avg regime transitions per month: %.1f\n", avg_whipsaw))

cat("\n5. Action distribution asymmetry:\n")
cat(sprintf("   HEDGE: %.1f%%, NEUTRAL: %.1f%%, ADD: %.1f%%\n",
            100 * sum(valid_ktri$Action == "HEDGE") / nrow(valid_ktri),
            100 * sum(valid_ktri$Action == "NEUTRAL") / nrow(valid_ktri),
            100 * sum(valid_ktri$Action == "ADD") / nrow(valid_ktri)))
cat("   HEDGE dominates → model is structurally bearish\n")

cat("\n--- Reinforcement Recommendations ---\n")
cat("R1. Replace IKS221 NA with RV20 proxy (realized vol as IV substitute)\n")
cat("R2. Use KTRI_breadth_v2 (actual constituents) for B1/B2\n")
cat("R3. Fix lookahead: Use expanding-window quantiles (min 756 days)\n")
cat("R4. Add KRX derivatives (VKOSPI, VRP, PCR) as D-axis enhancement\n")
cat("R5. Calibrate thresholds to historical stress events (not quantiles)\n")
cat("R6. Consider KTRI as continuous signal (not ADD/HEDGE/NEUTRAL)\n")
cat("R7. Ensemble with FRED/MSM for production use\n")

cat("\n================================================================\n")
cat("[KTRI Validation] Complete.\n")
