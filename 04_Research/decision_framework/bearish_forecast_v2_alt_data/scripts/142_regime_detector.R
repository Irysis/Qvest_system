## ============================================================
## Cycle 56B Step 1 — Regime Detector (M4 + AR + R05 inherit)
##
## Purpose:
##   Production regime overlay 자산 (STR_1715_AR_on_M4_R05_overlay_PG2)
##   에서 4-state regime (BULL / NORMAL / CAUTION / CRISIS) extract +
##   monthly sig_date 기준으로 일별 dates에 lag1 forward-fill.
##
## Data source (existing, PIT-validated):
##   - 05_Production/.../alpha_scores_r05_panel.parquet (268 monthly sig_dates,
##     2004-01-01 ~ 2026-04-01, single regime per Date)
##   - 4-state buckets: BULL=92 / NORMAL=158 / CAUTION=15 / CRISIS=3 (sig_date level)
##
## PIT contract:
##   1. Production panel monthly regime_state는 R05 production overlay에서 검증된
##      m4(BOCPD) × AR threshold × R05 결합 결과 (apply_regime_overlay.R 정통).
##   2. regime_state는 이미 R05 overlay 산출 시점에 sig_date의 lag-1 정보 사용
##      (production overlay PIT compliance 인증).
##   3. 일별 daily Date에 forward-fill 시 t-1 lag 추가:
##        regime_daily[t] = regime_monthly[sig_date_t_minus_1]
##      즉 시점 t의 모델은 직전 월말 EOM의 regime만 사용.
##
## Output:
##   outputs/01_data/regime_daily_lag1.parquet (Date, regime_state)
##   outputs/01_data/regime_monthly_sig.csv (sig_date level audit)
## ============================================================

cat("============================================================\n")
cat("Cycle 56B Step 1 — Regime Detector (M4 + AR + R05 inherit)\n")
cat("============================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(lubridate)
})

BASE_DIR <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(BASE_DIR,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data")
OUT_DATA <- file.path(WS_DIR, "outputs/01_data")
OUT_EVAL <- file.path(WS_DIR, "outputs/04_evaluation")
dir.create(OUT_DATA, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_EVAL, recursive = TRUE, showWarnings = FALSE)

# ============================================================
# 1. Load Production R05 panel (regime_state column)
# ============================================================
cat("[1] Load Production R05 panel\n")

r05_path <- file.path(BASE_DIR,
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet")
stopifnot(file.exists(r05_path))
r05 <- as.data.table(read_parquet(r05_path))

cat(sprintf("  rows=%d cols=%d\n", nrow(r05), ncol(r05)))
cat(sprintf("  Date range: %s ~ %s\n",
            as.character(min(r05$Date)), as.character(max(r05$Date))))

# ============================================================
# 2. Extract per-Date regime (single regime per sig_date)
# ============================================================
cat("\n[2] Extract per-Date regime\n")

regime_sig <- r05[, .(n_regimes = uniqueN(regime_state),
                       regime_state = regime_state[1]),
                  by = Date]
setorder(regime_sig, Date)

# Sanity: all dates single regime
stopifnot(all(regime_sig$n_regimes == 1L))

cat(sprintf("  n sig_dates: %d (%s ~ %s)\n",
            nrow(regime_sig),
            as.character(min(regime_sig$Date)),
            as.character(max(regime_sig$Date))))
cat("  regime distribution (sig_date level):\n")
print(table(regime_sig$regime_state))

# Save sig_date-level audit
fwrite(regime_sig[, .(Date, regime_state)],
       file.path(OUT_DATA, "regime_monthly_sig.csv"))

# ============================================================
# 3. Forward-fill to daily Dates with t-1 lag
#
# Logic:
#   For each calendar day d,
#     regime_daily[d] = regime_monthly[sig_date], where
#     sig_date = max(sig in regime_sig$Date | sig < d)
#   (strictly less than → applies t-1 lag automatically)
# ============================================================
cat("\n[3] Forward-fill to daily Dates with t-1 lag\n")

# Daily Date grid: same range as v5e panel for join
panel <- as.data.table(read_parquet(
  file.path(OUT_DATA, "feature_panel_v5e_q126_usmacro.parquet")))
daily_dates <- panel[, .(Date = as.Date(Date))]
setorder(daily_dates, Date)
cat(sprintf("  Daily grid: %d rows (%s ~ %s)\n",
            nrow(daily_dates),
            as.character(min(daily_dates$Date)),
            as.character(max(daily_dates$Date))))

# Roll join with t-1 lag enforcement
# Trick: shift sig_date by +1 day so roll join finds nearest sig_date strictly < d
regime_sig_shifted <- copy(regime_sig)
regime_sig_shifted[, Date_join := Date + 1L]  # sig_date d_s → applies starting d_s+1
setkey(regime_sig_shifted, Date_join)

daily_dates_join <- copy(daily_dates)
daily_dates_join[, Date_join := Date]
setkey(daily_dates_join, Date_join)

regime_daily <- regime_sig_shifted[, .(Date_join, regime_state, sig_date_used = Date)
                                   ][daily_dates_join, on = "Date_join", roll = TRUE]
regime_daily <- regime_daily[, .(Date, regime_state, sig_date_used)]

# Drop pre-2004 (NA regime — no data)
n_na <- sum(is.na(regime_daily$regime_state))
cat(sprintf("  NA regimes (pre-2004 daily Dates): %d\n", n_na))

# Audit lag sanity: regime_daily$sig_date_used must be < Date
non_na <- regime_daily[!is.na(regime_state)]
lag_check <- non_na[, .(violation_count = sum(sig_date_used >= Date))]
cat(sprintf("  Lag1 sanity (sig_date_used < Date): violations = %d (must be 0)\n",
            lag_check$violation_count))
stopifnot(lag_check$violation_count == 0)

cat("\n  Daily regime distribution (post-fill, non-NA):\n")
print(table(regime_daily$regime_state, useNA = "no"))

# Save daily lag1 mapping
write_parquet(regime_daily[, .(Date, regime_state, sig_date_used)],
              file.path(OUT_DATA, "regime_daily_lag1.parquet"))

# ============================================================
# 4. Per-period regime distribution (S2018-19 / S2020-21 / S2022-24)
# ============================================================
cat("\n[4] Per-period regime distribution\n")

regime_daily[!is.na(regime_state),
             period := fcase(
               Date >= as.Date("2018-01-01") & Date <= as.Date("2019-12-31"), "S2018-19",
               Date >= as.Date("2020-01-01") & Date <= as.Date("2021-12-31"), "S2020-21",
               Date >= as.Date("2022-01-01") & Date <= as.Date("2024-12-31"), "S2022-24",
               default = "other")]

per_period <- regime_daily[!is.na(regime_state) & period != "other",
                            .N, by = .(period, regime_state)]
per_period <- dcast(per_period, period ~ regime_state, value.var = "N", fill = 0)
cat("  Per-period regime count (daily):\n")
print(per_period)

# ============================================================
# 5. Save audit summary
# ============================================================
audit <- list(
  cycle = "56B_step1_regime_detector",
  source_panel = "05_Production/.../alpha_scores_r05_panel.parquet",
  n_sig_dates = nrow(regime_sig),
  sig_date_range = list(start = as.character(min(regime_sig$Date)),
                         end = as.character(max(regime_sig$Date))),
  regime_distribution_sig_date = as.list(table(regime_sig$regime_state)),
  n_daily_dates_total = nrow(daily_dates),
  n_daily_dates_na = n_na,
  n_daily_dates_assigned = sum(!is.na(regime_daily$regime_state)),
  regime_distribution_daily = as.list(table(regime_daily$regime_state, useNA = "no")),
  lag1_violation_count = lag_check$violation_count,
  pit_compliance = list(
    lag_strategy = "sig_date_used strictly < Date (t-1 enforced via Date_join = sig_date + 1)",
    inherit_pit = "Production regime_state already t-1 lagged in R05 overlay",
    additional_lag = "+1 day enforced in roll join"
  ),
  per_period_distribution = as.list(per_period),
  output_files = list(
    daily_parquet = "outputs/01_data/regime_daily_lag1.parquet",
    sig_csv = "outputs/01_data/regime_monthly_sig.csv"
  )
)
write_json(audit, file.path(OUT_EVAL, "cycle56b_step1_regime_detector_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null")

cat(sprintf("\n[done] outputs/01_data/regime_daily_lag1.parquet\n"))
cat(sprintf("       outputs/04_evaluation/cycle56b_step1_regime_detector_audit.json\n"))
