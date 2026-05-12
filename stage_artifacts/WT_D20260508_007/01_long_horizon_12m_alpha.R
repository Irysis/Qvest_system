#==============================================================================
# WT-D20260508_007 — Step 1: 12M long-horizon single-macro alpha (formal validation)
#
# Inheritance: WT-D20260508_005 alpha_panel_single.parquet (PIT-strict, 24M
# rolling β KR_TermSpread_d, expanding sign 12m burn-in, EMA3/6/12 variants).
#
# Hypothesis: KR_TermSpread β cross-section signal is **12M long-horizon**:
#   - WT_005 1M ICIR 0.183 (Harvey-NW 2.14 < 3.0 fail)
#   - WT_005 12M ICIR 0.310 (Harvey-NW 1.90 < 3.0 fail) ← formal validation target
# Macro shocks propagate slowly through firm fundamentals → 12M aggregation
# captures full effect (Cooper-Gulen-Schill 2008 / Asness-Moskowitz-Pedersen
# 2013 paradigm).
#
# Design changes vs WT_005:
#   - Primary forecast_horizon = 12M (not 1M)
#   - Smoothing variant focus: ema12 + raw_signed (long horizon → mild EMA12
#     conceptually consistent with 12M reading; raw_signed = no smoothing
#     unbiased baseline)
#   - Newey-West HAC lag = 12 (12M overlapping returns Hansen-Hodrick correction)
#   - Bailey-LdP DSR strict, N_trials = 20 (conservative)
#   - Subperiod stability post-2013 (3 windows)
#   - Turnover: 12M rebalance assumption
#   - PIT C13: Z_Score_Aligned compatible (data-driven sign, not manual flip)
#   - PIT C15: c15_infeasibility_report.json inheritable from WT_005
#
# Outputs:
#   - alpha_panel_12m.parquet (subset with FwdRet_12M usable for primary)
#   - per_period_ic_12m_*.csv (per variant)
#   - ic_12m_summary.csv
#   - predictor_autocor_12m.json
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(zoo); library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
SRC  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_005")
OUT  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_007")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

cat("[01] WT-D20260508_007 — 12M long-horizon single-macro alpha\n")
cat("[01] inheriting from WT_005 alpha_panel_single.parquet\n")

panel <- as.data.table(read_parquet(file.path(SRC, "alpha_panel_single.parquet")))
cat("[01] inherited rows:", nrow(panel), "/ tickers:", uniqueN(panel$Ticker),
    "/ months:", uniqueN(panel$ym), "\n")

# Eligibility (already filtered in WT_005 Step 1) + FwdRet_12M non-NA
mm <- panel[eligible == TRUE & !is.na(FwdRet_12M)]
cat("[01] usable rows (eligible + FwdRet_12M):", nrow(mm),
    "/ months with target:", uniqueN(mm$ym), "\n")

# Primary universe: post-2013 (burn-in past 36m as in WT_005)
mm <- mm[ym >= "2013-01"]
cat("[01] post-2013 rows:", nrow(mm), "/ months:", uniqueN(mm$ym), "\n")

# Save 12M-focused panel for downstream
write_parquet(mm, file.path(OUT, "alpha_panel_12m.parquet"))

# ---- Per-period IC for 12M target across variants ----
variants <- list(
  raw_signed   = "alpha_signed_z",
  ema3         = "alpha_ema3_z",
  ema6         = "alpha_ema6_z",
  ema12        = "alpha_ema12_z",
  sector_neut  = "alpha_sn"
)

ic_summary <- list()
ic_period_store <- list()
for (vn in names(variants)) {
  vc <- variants[[vn]]
  sub <- mm[!is.na(get(vc)) & !is.na(FwdRet_12M)]
  ic_v <- sub[, .(rank_ic = cor(get(vc), FwdRet_12M, method = "spearman", use = "complete.obs"),
                  n = .N), by = ym]
  setorder(ic_v, ym)
  if (nrow(ic_v) > 0) {
    ic_period_store[[vn]] <- ic_v
    fwrite(ic_v, file.path(OUT, sprintf("per_period_ic_12m_%s.csv", vn)))
    icir_v <- mean(ic_v$rank_ic, na.rm = TRUE) / sd(ic_v$rank_ic, na.rm = TRUE)
    t_simple <- mean(ic_v$rank_ic, na.rm = TRUE) /
                  (sd(ic_v$rank_ic, na.rm = TRUE) / sqrt(nrow(ic_v)))
    ic_summary[[vn]] <- data.table(
      variant = vn,
      ic_mean = mean(ic_v$rank_ic, na.rm = TRUE),
      ic_sd   = sd(ic_v$rank_ic, na.rm = TRUE),
      icir    = icir_v,
      t_simple = t_simple,
      n_periods = nrow(ic_v),
      hit_pos = mean(ic_v$rank_ic > 0, na.rm = TRUE)
    )
  }
}
ic_summary <- rbindlist(ic_summary, fill = TRUE)
fwrite(ic_summary, file.path(OUT, "ic_12m_summary.csv"))
cat("\n[01] 12M IC summary across variants (post-2013):\n")
print(ic_summary)

# Select PRIMARY variant by 12M ICIR
setorder(ic_summary, -icir)
PRIMARY <- ic_summary$variant[1]
PRIMARY_COL <- variants[[PRIMARY]]
cat(sprintf("\n[01] PRIMARY variant (12M ICIR-best): %s (col=%s, ICIR=%.3f, t=%.3f)\n",
            PRIMARY, PRIMARY_COL, ic_summary$icir[1], ic_summary$t_simple[1]))

# ---- Predictor lag-1 autocor (per-ticker, 12M horizon design comment) ----
acf_dt <- mm[!is.na(get(PRIMARY_COL)), .(Ticker, ym, val = get(PRIMARY_COL))]
setorder(acf_dt, Ticker, ym)
acf_dt[, val_lag1 := shift(val, 1L), by = Ticker]
acf_dt[, ym_num := as.integer(gsub("-", "", ym))]
acf_dt[, ym_lag := shift(ym_num, 1L), by = Ticker]
acf_dt[, gap_ok := (ym_num - ym_lag) %in% c(1, 89)]
acf_calc <- acf_dt[gap_ok == TRUE & !is.na(val) & !is.na(val_lag1)]
ac1 <- if (nrow(acf_calc) >= 100) cor(acf_calc$val, acf_calc$val_lag1) else NA_real_

# Status: long-horizon (12M) reads naturally tolerate higher autocor (predictor
# is rolling 24M β + EMA smoothing + 12M target reading)
ac_status <- if (is.na(ac1)) {
  "INSUFFICIENT_DATA"
} else if (ac1 > 0.95) {
  "WARN_HIGH_AUTOCOR"
} else if (ac1 > 0.85) {
  "MID_HIGH_NORMAL_FOR_12M_HORIZON"
} else {
  "OK"
}

ac_diag <- list(
  primary_variant = PRIMARY,
  primary_col = PRIMARY_COL,
  predictor_lag1_autocor = if (is.na(ac1)) NA else round(ac1, 4),
  status = ac_status,
  rationale = paste("12M long-horizon design: predictor = 24M rolling β.",
                    "lag-1 autocor reflects β persistence (intentional).",
                    "Critical threshold for spurious lag-1 IC = 0.95 (WT_001 lesson)."),
  threshold_warn = 0.95,
  n_pairs = nrow(acf_calc),
  pit_check = "predictor uses β at t-1 (lag-1) — no current-month leak"
)
write_json(ac_diag, file.path(OUT, "predictor_autocor_12m.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[01] Predictor (%s) lag-1 autocor = %.3f → %s\n",
            PRIMARY, ac1, ac_status))

cat("\n[01] DONE. Step 2 will run strict diagnostics with NW-lag=12 (12M HH).\n")
