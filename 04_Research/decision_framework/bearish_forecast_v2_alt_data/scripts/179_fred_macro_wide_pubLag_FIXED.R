#==============================================================================
# 179_fred_macro_wide_pubLag_FIXED.R — Cycle 57B Phase 1
#
# Mandate (Codex 57A_followup priority 1):
#   .cache/fred_macro_wide.parquet 안의 모든 monthly/weekly FRED indicators에 대해
#   publication-lag fix 적용. 이전 95_fred_us_macro_pubLag_FIXED_offline.py 패턴 inherit.
#
#   Direct: ICSA Sat→Thu (+5d) / CFNAI MM-01→MM+55d
#   Indirect impact on BBVA: Init_Claims used in bbva_market_z composite.
#                            5d ICSA pub-lag → bbva_market_z 5d lookahead bias.
#
#   Monthly indicators (모두 MM-01 dating 확인됨):
#     Copper_Price       — Reference month-end + ~1d (LME) → +30d (next MM end의 release)
#                          단 LME Copper는 daily ticker, monthly 평균이 보통 next MM 첫 주
#                          → conservative +30d 적용 (release ~3d in next month)
#     Housing_Permits    — 다음달 ~17일 (US Census Bureau) → +47d (MM-01 → next MM mid)
#     UMich_Sentiment    — Final 다음달 둘째 금요일 (보통 +14d~+25d 다음달)
#                          → +30d 적용 (next MM 초중반)
#     US_M2              — 다음달 셋째주 (Fed H.6) → +55d (MM-01 → next MM late)
#     US_CPI             — 다음달 둘째주 (BLS) → +45d
#     US_IndProd         — 다음달 셋째주 (FRB G.17) → +50d
#     US_Unemployment    — 다음달 첫 금요일 (BLS Employment Situation) → +35d
#     Fed_Funds_Rate     — 당일 보고 (FOMC meeting) → 0d (daily series, no lag adjust)
#                          단 fred_macro_wide.parquet는 monthly aggregate
#                          → 0d retain (rate decisions are public same-day)
#                            BUT monthly avg = looking ahead within month.
#                            → +30d 적용 (next month start에서 avg 사용 가능)
#     Bank_Lending_Std   — SLOOS quarterly release ~Q+1 month → +90d
#                          (Q-Lead: quarterly survey → next quarter mid release)
#
#   Weekly indicators:
#     Init_Claims        — Saturday-dated week-ending → +5d (Thursday release)
#     Chi_Fin_Cond       — Weekly (Wednesday) → 0d (same-day release)
#                          단 안전을 위해 +1d (next business day 사용)
#     StL_Fin_Stress     — Weekly (Thursday) → 0d (same-day release)
#                          단 안전을 위해 +1d
#     Fed_BalSheet       — Weekly (Wednesday H.4.1) → +1d (next day release)
#
#   Daily indicators (no lag):
#     BBB_Spread, HY_Spread, KRW_USD, VIX, US_10Y_Yield, US_2Y_Yield, Term_Spread,
#     Breakeven_5Y, Breakeven_Infl
#       → 0d (daily series, end-of-day release)
#       단 PIT lag1 (다음 거래일 사용)은 BBVA builder/feature engineering 단계에서 처리
#
# Output:
#   outputs/01_data/fred_macro_wide_FIXED.parquet (release-date dated)
#   outputs/04_evaluation/cycle57b_fred_macro_wide_pubLag_FIXED.json (audit log)
#
# PIT contract:
#   - 각 indicator의 dating convention (FRED MM-START reference 등)을 release-date로 shift
#   - 후속 단계 (180 A6 rebuild)에서 nafill LOCF + lag1 적용 → KR open 시점 usable
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
DATA_DIR <- file.path(WS, "outputs/01_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")

cat("\n========== Cycle 57B Phase 1: fred_macro_wide pub-lag FIXED rebuild ==========\n")

# ── Load source ─────────────────────────────────────────
src_path <- file.path(CACHE_DIR, "fred_macro_wide.parquet")
if (!file.exists(src_path)) stop(sprintf("missing: %s", src_path))
fred <- as.data.table(read_parquet(src_path))
fred[, Date := as.Date(Date)]
setorder(fred, Date)
cat(sprintf("[loaded] %d rows × %d cols (Date range: %s ~ %s)\n",
            nrow(fred), ncol(fred), min(fred$Date), max(fred$Date)))

# ── Publication lag map ──
# Source rationale 명시: 95_fred_us_macro_pubLag_FIXED_offline.py 패턴 + 표준 FRED release calendar
PUB_LAG <- list(
  # Monthly (MM-START dating in source) → conservative shift to release date
  "Copper_Price"      = 30L,   # LME monthly avg release ~3d into next month (conservative)
  "Housing_Permits"   = 47L,   # Census Bureau monthly release ~17d into next month
  "UMich_Sentiment"   = 30L,   # Survey final release next month early
  "US_M2"             = 55L,   # Fed H.6 next month late (~25d)
  "US_CPI"            = 45L,   # BLS next month mid (~15d)
  "US_IndProd"        = 50L,   # FRB G.17 next month mid (~20d)
  "US_Unemployment"   = 35L,   # BLS Employment Situation next month first Friday (~5d)
  "Fed_Funds_Rate"    = 30L,   # Daily series but monthly aggregate → next month start
  "Bank_Lending_Std"  = 90L,   # SLOOS quarterly survey → next quarter mid release
  # Weekly
  "Init_Claims"       = 5L,    # Sat-dated → Thu release (+5d)
  "Chi_Fin_Cond"      = 1L,    # Wed release → next day usable (safety)
  "StL_Fin_Stress"    = 1L,    # Thu release → next day usable (safety)
  "Fed_BalSheet"      = 1L     # H.4.1 next day usable
  # Daily (no lag) → BBB_Spread, HY_Spread, KRW_USD, VIX, US_10Y_Yield, US_2Y_Yield,
  #                  Term_Spread, Breakeven_5Y, Breakeven_Infl
)

# ── Apply publication lag ──
apply_lag <- function(dt, col, lag_days) {
  if (lag_days == 0L) return(list(dt = dt, audit = list(col = col, lag = 0L, n_shifted = 0L)))
  if (!col %in% names(dt)) return(list(dt = dt, audit = list(col = col, lag = lag_days, status = "MISSING")))

  # Extract non-NA observations
  obs <- dt[!is.na(get(col)), .(Date_ref = Date, val = get(col))]
  n_obs <- nrow(obs)
  if (n_obs == 0L) {
    return(list(dt = dt, audit = list(col = col, lag = lag_days, n_obs = 0L, status = "EMPTY")))
  }
  obs[, Date_release := Date_ref + lag_days]

  first_ref <- min(obs$Date_ref); last_ref <- max(obs$Date_ref)
  first_rel <- min(obs$Date_release); last_rel <- max(obs$Date_release)

  # Drop original, then merge shifted
  dt[, (col) := NULL]
  shifted <- obs[, .(Date = Date_release, val)]
  # Collision handling (multiple reference dates → same release date): take first
  shifted <- shifted[!duplicated(shifted$Date)]
  setnames(shifted, "val", col)
  dt2 <- merge(dt, shifted, by = "Date", all.x = TRUE)
  setorder(dt2, Date)

  cat(sprintf("  [PUB_LAG %-20s] +%dd  ref=%s~%s → rel=%s~%s  n_obs=%d\n",
              col, lag_days,
              format(first_ref, "%Y-%m-%d"), format(last_ref, "%Y-%m-%d"),
              format(first_rel, "%Y-%m-%d"), format(last_rel, "%Y-%m-%d"),
              n_obs))

  list(dt = dt2, audit = list(
    col = col, lag_days = lag_days, n_obs = n_obs,
    first_ref = format(first_ref, "%Y-%m-%d"), last_ref = format(last_ref, "%Y-%m-%d"),
    first_rel = format(first_rel, "%Y-%m-%d"), last_rel = format(last_rel, "%Y-%m-%d"),
    status = "OK"
  ))
}

cat("\n[applying publication lag]\n")
fix_log <- list()
fred_fixed <- copy(fred)
for (col in names(PUB_LAG)) {
  res <- apply_lag(fred_fixed, col, PUB_LAG[[col]])
  fred_fixed <- res$dt
  fix_log[[col]] <- res$audit
}

# Identify daily (no-lag) indicators that retained
daily_indicators <- setdiff(setdiff(names(fred_fixed), "Date"), names(PUB_LAG))
cat(sprintf("\n[no-lag retain] daily indicators (count=%d): %s\n",
            length(daily_indicators), paste(daily_indicators, collapse = ", ")))

# ── Re-order columns to match source ──
orig_cols <- names(fred)
fred_fixed <- fred_fixed[, ..orig_cols]

# ── Validation: sanity checks ──
cat("\n[validation samples]\n")
# 1) ICSA Sat → Thu shift
icsa_sat <- fred[Date == as.Date("2020-03-21"), Init_Claims]
icsa_thu_fixed <- fred_fixed[Date == as.Date("2020-03-26"), Init_Claims]
cat(sprintf("  ICSA orig 2020-03-21 (Sat) = %s\n", as.character(icsa_sat)))
cat(sprintf("  ICSA fixed 2020-03-26 (Thu, +5d) = %s (expected = %s)\n",
            as.character(icsa_thu_fixed), as.character(icsa_sat)))
stopifnot(icsa_thu_fixed == icsa_sat)
icsa_orig_at_fixed = fred_fixed[Date == as.Date("2020-03-21"), Init_Claims]
cat(sprintf("  ICSA fixed 2020-03-21 (Sat) = %s (expected NA)\n", as.character(icsa_orig_at_fixed)))
stopifnot(is.na(icsa_orig_at_fixed))

# 2) Monthly indicator (Copper) shift check
copper_mar20 <- fred[Date == as.Date("2020-03-01"), Copper_Price]
copper_mar31_fixed <- fred_fixed[Date == as.Date("2020-03-31"), Copper_Price]
cat(sprintf("  Copper orig 2020-03-01 (MM-01) = %s\n", as.character(copper_mar20)))
cat(sprintf("  Copper fixed 2020-03-31 (+30d) = %s (expected = %s)\n",
            as.character(copper_mar31_fixed), as.character(copper_mar20)))
stopifnot(round(copper_mar31_fixed, 4) == round(copper_mar20, 4))

# 3) US_CPI +45d
cpi_mar20 <- fred[Date == as.Date("2020-03-01"), US_CPI]
cpi_apr15_fixed <- fred_fixed[Date == as.Date("2020-04-15"), US_CPI]
cat(sprintf("  US_CPI orig 2020-03-01 = %s\n", as.character(cpi_mar20)))
cat(sprintf("  US_CPI fixed 2020-04-15 (+45d) = %s (expected = %s)\n",
            as.character(cpi_apr15_fixed), as.character(cpi_mar20)))
stopifnot(round(cpi_apr15_fixed, 4) == round(cpi_mar20, 4))

# 4) Init_Claims COVID lookahead test (2020-03-26 should match week-ending 3/21 = 2914000)
icsa_apr_3 <- fred_fixed[Date >= as.Date("2020-03-26") & Date <= as.Date("2020-04-10"),
                          .(Date, Init_Claims)]
icsa_apr_3 <- icsa_apr_3[!is.na(Init_Claims)]
cat("  ICSA COVID release dates (after fix):\n")
print(icsa_apr_3)

# ── Save ──
out_path <- file.path(DATA_DIR, "fred_macro_wide_FIXED.parquet")
write_parquet(fred_fixed, out_path)
cat(sprintf("\n[saved] %s (%.1f KB)\n", out_path, file.info(out_path)$size / 1024))

# ── Audit log ──
audit <- list(
  cycle = "57B_Phase1",
  description = "fred_macro_wide.parquet publication-lag fix (all monthly/weekly indicators)",
  inputs = list(source = src_path,
                n_rows = nrow(fred), n_cols = ncol(fred),
                date_range = paste(min(fred$Date), "~", max(fred$Date))),
  outputs = list(fixed = out_path),
  publication_lag_map = PUB_LAG,
  fixed_indicators_count = length(PUB_LAG),
  daily_no_lag_indicators = daily_indicators,
  fix_log = fix_log,
  validation_samples = list(
    ICSA_2020_03_21_orig = icsa_sat,
    ICSA_2020_03_26_fixed = icsa_thu_fixed,
    Copper_2020_03_01_orig = copper_mar20,
    Copper_2020_03_31_fixed = copper_mar31_fixed,
    CPI_2020_03_01_orig = cpi_mar20,
    CPI_2020_04_15_fixed = cpi_apr15_fixed
  ),
  next_step = "Phase 2: scripts/180_A6_bbva_macro_FIXED.R (rebuild BBVA composite using fixed FRED)"
)
audit_path <- file.path(EVAL_DIR, "cycle57b_fred_macro_wide_pubLag_FIXED.json")
write_json(audit, audit_path, auto_unbox = TRUE, pretty = TRUE, na = "string")
cat(sprintf("[audit] %s\n", audit_path))

cat("\n========== Cycle 57B Phase 1 DONE ==========\n")
cat(sprintf("Fixed %d indicators (10 monthly + 4 weekly); %d daily indicators retained no-lag.\n",
            length(PUB_LAG), length(daily_indicators)))
