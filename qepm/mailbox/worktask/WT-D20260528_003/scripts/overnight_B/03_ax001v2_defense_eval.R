#==============================================================================
# WT-D20260528_003 Hypothesis B Step 3 — AX-001 v2 Defensive Evaluation
#
# Bali 2011 MAX is defensive (lower_better) per registry. Apply AX-001 v2 axes:
#   1. crisis_alpha: IC during crisis regime (VIX_Regime == "crisis" or Fin_Stress_Regime == "crisis")
#   2. Bad/Normal IC ratio ≥ 0.5 (defensive factor evaluation)
#   3. (Core 대비 MDD 완화) — defer to Optimizer (Alpha role boundary)
#
# Regime source: .cache/macro_regime.parquet (VIX_Regime, Fin_Stress_Regime, Buddha_Mode)
# PIT: macro regime lag-1 month (Cycle 51 — t-1 fwd reference)
#
# Output:
#   - outputs/overnight_B/m22_step3_ax001v2.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE)
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/overnight_B")

cat("[Step 3: AX-001 v2 Defensive Evaluation] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load Step 2 IC per-date + macro regime ----
ic_per_date <- as.data.table(read_parquet(file.path(OUT_DIR, "m22_ic_per_date.parquet")))
ic_per_date[, Date := as.Date(Date)]
cat("[1] IC per-date loaded:", nrow(ic_per_date), "rows\n")

mr <- as.data.table(read_parquet(file.path(BASE, ".cache/macro_regime.parquet")))
mr[, Date := as.Date(Date)]
cat("    Macro regime loaded:", nrow(mr), "rows | cols:",
    paste(intersect(c("VIX_Regime","Fin_Stress_Regime","Inflation_Regime","Buddha_Mode"),
                    names(mr)), collapse=", "), "\n")

# ---- 2. PIT lag: regime[t-1 month] available at decision date t ----
mr[, YM_match := format(Date, "%Y-%m")]
# Sort + lag by 1 month
setorder(mr, Date)
mr[, VIX_Regime_lag1 := shift(VIX_Regime, n = 1L, type = "lag")]
mr[, Fin_Stress_Regime_lag1 := shift(Fin_Stress_Regime, n = 1L, type = "lag")]
if ("Buddha_Mode" %in% names(mr)) {
  mr[, Buddha_Mode_lag1 := shift(Buddha_Mode, n = 1L, type = "lag")]
}

# ic_per_date Date is monthly sig_date. Match to nearest month-end in mr
ic_per_date[, YM := format(Date, "%Y-%m")]
mr[, YM := format(Date, "%Y-%m")]
mr_subset <- mr[, .(YM, VIX_Regime_lag1, Fin_Stress_Regime_lag1,
                     Buddha_Mode_lag1 = if ("Buddha_Mode_lag1" %in% names(mr)) Buddha_Mode_lag1 else NA)]

ic_with_regime <- merge(ic_per_date, mr_subset, by = "YM", all.x = TRUE)
cat("[2] PIT lag merge:", nrow(ic_with_regime), "rows |",
    sum(!is.na(ic_with_regime$VIX_Regime_lag1)), "with VIX_Regime\n")

# ---- 3. Crisis/Bad/Normal classification ----
# Bad regime: VIX_Regime == "crisis" OR Fin_Stress_Regime == "crisis"
# Normal: VIX_Regime == "normal" AND Fin_Stress_Regime == "normal"
# Elevated: in between
ic_with_regime[, regime_label := fcase(
  VIX_Regime_lag1 == "crisis" | Fin_Stress_Regime_lag1 == "crisis", "crisis",
  VIX_Regime_lag1 == "normal" & Fin_Stress_Regime_lag1 == "normal", "normal",
  default = "elevated"
)]

cat("[3] Regime distribution:\n")
print(table(ic_with_regime$regime_label, useNA = "ifany"))

# ---- 4. Per-regime IC (raw + neutral) ----
cat("\n[4] Per-regime IC ...\n")
regime_ic <- ic_with_regime[!is.na(regime_label) & regime_label != "NA", .(
  n = .N,
  raw_ic_mean = mean(rank_ic_raw, na.rm = TRUE),
  raw_ic_sd = sd(rank_ic_raw, na.rm = TRUE),
  neut_ic_mean = mean(rank_ic_neut, na.rm = TRUE),
  neut_ic_sd = sd(rank_ic_neut, na.rm = TRUE)
), by = regime_label]
regime_ic[, raw_icir := raw_ic_mean / raw_ic_sd]
regime_ic[, neut_icir := neut_ic_mean / neut_ic_sd]
print(regime_ic[order(regime_label)])

# Defensive factor expected pattern:
# - Bali MAX direction: lower_better → Z_aligned positive = LOW MAX = high alpha
# - In crisis: lottery preference UP, high MAX more punished → Z_aligned MORE positive IC
# - In normal: lottery preference moderate → moderate IC
# So crisis_alpha = neut_ic_mean[crisis] > neut_ic_mean[normal] (예상)

crisis_ic <- regime_ic[regime_label == "crisis", neut_ic_mean]
normal_ic <- regime_ic[regime_label == "normal", neut_ic_mean]
elevated_ic <- regime_ic[regime_label == "elevated", neut_ic_mean]

if (length(crisis_ic) == 1 && length(normal_ic) == 1 && !is.na(crisis_ic) && !is.na(normal_ic)) {
  cat("\n  AX-001 v2 crisis_alpha test:\n")
  cat("    crisis IC =", round(crisis_ic, 4), "\n")
  cat("    normal IC =", round(normal_ic, 4), "\n")
  cat("    crisis - normal =", round(crisis_ic - normal_ic, 4), "\n")

  # Defensive factor AX-001 v2: crisis_alpha ≥ 0 (Core 보호)
  ax_crisis_pass <- crisis_ic > 0
  cat("    AX-001 v2 crisis IC > 0 (defensive protection):", ax_crisis_pass, "\n")

  # Bad/Normal IC ratio ≥ 0.5
  if (abs(normal_ic) > 1e-6) {
    bad_normal_ratio <- crisis_ic / normal_ic
    cat("    Bad/Normal IC ratio (crisis/normal):", round(bad_normal_ratio, 3), "\n")
    cat("    AX-001 v2 bad/normal >= 0.5:", bad_normal_ratio >= 0.5, "\n")
  } else {
    bad_normal_ratio <- NA_real_
    cat("    Normal IC near zero, ratio undefined\n")
  }
} else {
  ax_crisis_pass <- NA
  bad_normal_ratio <- NA_real_
  cat("\n  Insufficient regime data for AX-001 v2 evaluation\n")
}

# ---- 5. Buddha_Mode 평가 (있으면) — crash detector ----
if ("Buddha_Mode_lag1" %in% names(ic_with_regime)) {
  bm_dist <- table(ic_with_regime$Buddha_Mode_lag1, useNA = "ifany")
  cat("\n[5] Buddha_Mode lag1 distribution:\n")
  print(bm_dist)
  if (any(!is.na(ic_with_regime$Buddha_Mode_lag1))) {
    bm_ic <- ic_with_regime[!is.na(Buddha_Mode_lag1), .(
      n = .N,
      neut_ic_mean = mean(rank_ic_neut, na.rm = TRUE),
      neut_icir = mean(rank_ic_neut, na.rm = TRUE) / sd(rank_ic_neut, na.rm = TRUE)
    ), by = Buddha_Mode_lag1]
    print(bm_ic)
  }
}

# ---- 6. Decile monotonicity test (raw + neutral) ----
cat("\n[6] Decile monotonicity test ...\n")
panel <- as.data.table(read_parquet(file.path(OUT_DIR, "m22_panel_sector_neutral.parquet")))
panel[, Date := as.Date(Date)]

# Per-Date decile + mean fwd_ret
decile_monotonicity <- function(zcol, label) {
  panel_dec <- panel[!is.na(get(zcol)) & !is.na(fwd_ret)]
  panel_dec[, decile := cut(get(zcol), breaks = quantile(get(zcol), probs = seq(0,1,0.1), na.rm=TRUE),
                            include.lowest = TRUE, labels = 1:10), by = Date]
  panel_dec[, decile := as.integer(decile)]
  dec_summary <- panel_dec[!is.na(decile), .(
    n = .N,
    mean_fwd_ret = mean(fwd_ret, na.rm = TRUE) * 100  # in pct
  ), by = decile][order(decile)]
  cat("  Decile mean fwd_ret (", label, ", monthly %):\n", sep="")
  print(dec_summary)
  # Monotonicity: Spearman rank correlation of decile vs mean fwd_ret
  if (nrow(dec_summary) >= 5) {
    mono <- cor(dec_summary$decile, dec_summary$mean_fwd_ret, method = "spearman")
    cat("  Monotonicity (decile vs fwd_ret Spearman):", round(mono, 3), "\n")
    # D10-D1 spread
    d10 <- dec_summary[decile == 10, mean_fwd_ret]
    d1 <- dec_summary[decile == 1, mean_fwd_ret]
    spread <- d10 - d1
    cat("  D10 - D1 spread:", round(spread, 3), "%/month\n")
    list(monotonicity = mono, d10_minus_d1 = spread, decile_returns = dec_summary)
  } else {
    list(monotonicity = NA_real_, d10_minus_d1 = NA_real_, decile_returns = NULL)
  }
}

mono_raw <- decile_monotonicity("Z_aligned", "RAW")
mono_neut <- decile_monotonicity("Z_neutral", "NEUT")

# ---- 7. Save ----
cat("\n[7] Save ...\n")
diag <- list(
  task_id = "WT-D20260528_003",
  hypothesis = "B",
  step = "03_ax001v2_defense_eval",
  regime_distribution = as.list(table(ic_with_regime$regime_label, useNA = "ifany")),
  regime_ic = lapply(seq_len(nrow(regime_ic)), function(i) as.list(regime_ic[i])),
  ax_001_v2 = list(
    crisis_ic = if (length(crisis_ic)==1) crisis_ic else NA_real_,
    normal_ic = if (length(normal_ic)==1) normal_ic else NA_real_,
    elevated_ic = if (length(elevated_ic)==1) elevated_ic else NA_real_,
    crisis_minus_normal = if (length(crisis_ic)==1 && length(normal_ic)==1)
                          crisis_ic - normal_ic else NA_real_,
    ax_crisis_pass = ax_crisis_pass,
    bad_normal_ratio = bad_normal_ratio,
    ax_bad_normal_pass = !is.na(bad_normal_ratio) && bad_normal_ratio >= 0.5
  ),
  monotonicity_raw = list(value = mono_raw$monotonicity, d10_d1 = mono_raw$d10_minus_d1),
  monotonicity_neut = list(value = mono_neut$monotonicity, d10_d1 = mono_neut$d10_minus_d1),
  decile_returns_raw = if (!is.null(mono_raw$decile_returns))
                       lapply(seq_len(nrow(mono_raw$decile_returns)),
                              function(i) as.list(mono_raw$decile_returns[i])) else NULL,
  decile_returns_neut = if (!is.null(mono_neut$decile_returns))
                        lapply(seq_len(nrow(mono_neut$decile_returns)),
                               function(i) as.list(mono_neut$decile_returns[i])) else NULL
)
write_json(diag, file.path(OUT_DIR, "m22_step3_ax001v2.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("  saved: m22_step3_ax001v2.json\n")

elapsed <- as.numeric(Sys.time() - t0, units = "secs")
cat("\n[Step 3] === DONE === elapsed:", round(elapsed, 1), "sec\n")
