#==============================================================================
# 173_panel_rebuild_v3f_v5e_v5f_FIXED.R — Cycle 57A Phase 2
#
# Mandate:
#   Rebuild v3f / v5e / v5f panels using fred_us_macro_daily_fixed.csv
#   (publication-lag corrected per Cycle 55B Q-Lead+Codex audit).
#
#   - v3f_fixed: v1.3 (69) + 4 US macro (FRED publication-lag fixed) = 73 features
#   - v5e_fixed: v4a (70) + 4 US macro (fixed) = 74 features
#   - v5f_fixed: v5e_fixed (74) + 5 ECOS KR (no change) = 79 features
#
# PIT pipeline (inherited from 96_5way_retrain_v3f_us_macro.R, but uses FIXED FRED CSV):
#   FRED publication-lag-shifted raw → nafill LOCF (daily) → 4w MA for ICSA → shift(1L) lag1
#
#   Net effect: any reference-period dating is converted to release-date dating BEFORE
#   forward-fill, ensuring next-day usable values at KR open.
#
# Outputs (write to NEW paths, do NOT overwrite original):
#   outputs/01_data/feature_panel_v3f_us_macro_FIXED.parquet (73 features)
#   outputs/01_data/feature_panel_v5e_q126_usmacro_FIXED.parquet (74 features)
#   outputs/01_data/feature_panel_v5f_ecos_kr_FIXED.parquet (79 features)
#   outputs/04_evaluation/cycle57a_panel_rebuild_audit.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")

cat("\n========== Cycle 57A Phase 2: panel rebuild (FRED publication-lag FIXED) ==========\n")

# ----------------------------------------------------------------------------
# Step 1: Load FIXED FRED CSV and build 4 US macro features (lag1)
# ----------------------------------------------------------------------------
cat("\n[Step 1] FIXED FRED CSV → 4 US macro lag1 features\n")

fred_fixed_path <- file.path(DATA_DIR, "fred_us_macro_daily_fixed.csv")
if (!file.exists(fred_fixed_path)) stop(sprintf("missing FIXED FRED CSV: %s", fred_fixed_path))
fred <- fread(fred_fixed_path)
fred[, Date := as.Date(Date)]
setorder(fred, Date)
cat(sprintf("  loaded: %d rows, cols=%s\n", nrow(fred), paste(names(fred), collapse=", ")))

# Forward-fill (LOCF) — daily spine of release-date dated values
# After publication-lag shift in Phase 1, values appear on release date, then LOCF carries
# forward until next release.
fred[, t10y2y_ff := nafill(t10y2y_raw, type = "locf")]
fred[, icsa_ff   := nafill(icsa_raw,   type = "locf")]
fred[, cfnai_ff  := nafill(cfnai_raw,  type = "locf")]
fred[, stlfsi_ff := nafill(stlfsi4_raw, type = "locf")]

# ICSA 4-week MA on forward-filled daily values
fred[, icsa_4w_avg := frollmean(icsa_ff, n = 28, align = "right", na.rm = TRUE)]

# lag-1 (PIT C2 — yesterday's value usable today at KR open)
fred[, us_t10y2y_spread_lag1 := shift(t10y2y_ff, 1L, type = "lag")]
fred[, us_initial_claims_4w_avg_lag1 := shift(icsa_4w_avg, 1L, type = "lag")]
fred[, us_cfnai_lag1 := shift(cfnai_ff, 1L, type = "lag")]
fred[, us_stlfsi_lag1 := shift(stlfsi_ff, 1L, type = "lag")]

us_macro_feats <- fred[, .(Date,
                            us_t10y2y_spread_lag1,
                            us_initial_claims_4w_avg_lag1,
                            us_cfnai_lag1,
                            us_stlfsi_lag1)]

cat("\n[us_macro feats cover after lag1]:\n")
for (col in c("us_t10y2y_spread_lag1", "us_initial_claims_4w_avg_lag1",
              "us_cfnai_lag1", "us_stlfsi_lag1")) {
  n_valid <- sum(!is.na(us_macro_feats[[col]]))
  first_valid <- if (n_valid > 0) as.character(us_macro_feats$Date[which(!is.na(us_macro_feats[[col]]))[1]]) else "n/a"
  cat(sprintf("  %-35s valid=%d (%.1f%%)  first=%s\n",
              col, n_valid, 100 * n_valid / nrow(us_macro_feats), first_valid))
}

# ----------------------------------------------------------------------------
# Step 2a: PIT sanity check — CFNAI 2020-03-02 row in panel SHOULD be NA or older value
# (NOT the Feb 2020 -4.37 reading which is now dated 2020-03-26 in fixed CSV)
# ----------------------------------------------------------------------------
cat("\n[Step 2a] PIT sanity — CFNAI Q-Lead inspection\n")
mar02 <- us_macro_feats[Date == as.Date("2020-03-02")]
mar26 <- us_macro_feats[Date == as.Date("2020-03-26")]
mar27 <- us_macro_feats[Date == as.Date("2020-03-27")]
cat(sprintf("  CFNAI lag1 on 2020-03-02: %s\n", as.character(mar02$us_cfnai_lag1)))
cat(sprintf("    (BEFORE FIX was -4.37 = Feb 2020 reading, BUGGY ~22d lookahead)\n"))
cat(sprintf("    (AFTER FIX should be Jan 2020 reading = +0.07 or NA depending on coverage)\n"))
cat(sprintf("  CFNAI lag1 on 2020-03-26: %s (should be Jan 2020 reading +0.07)\n",
            as.character(mar26$us_cfnai_lag1)))
cat(sprintf("  CFNAI lag1 on 2020-03-27: %s (should be Feb 2020 reading -4.37, released 3/26)\n",
            as.character(mar27$us_cfnai_lag1)))

# ----------------------------------------------------------------------------
# Step 3: Build v3f_FIXED panel (v1.3 69 + 4 US macro = 73)
# ----------------------------------------------------------------------------
cat("\n[Step 3] Build v3f_FIXED panel (v1.3 69 + 4 US macro = 73)\n")

v1_3_path <- file.path(DATA_DIR, "feature_panel_v1_3.parquet")
if (!file.exists(v1_3_path)) stop(sprintf("missing v1.3 panel: %s", v1_3_path))
v1_3 <- as.data.table(read_parquet(v1_3_path))
v1_3[, Date := as.Date(Date)]
setorder(v1_3, Date)
n_v1_3 <- ncol(v1_3) - 1L
cat(sprintf("  v1.3 baseline: %d rows × %d features\n", nrow(v1_3), n_v1_3))
stopifnot(n_v1_3 == 69L)

v3f_fixed <- merge(v1_3, us_macro_feats, by = "Date", all.x = TRUE)
setorder(v3f_fixed, Date)
n_v3f_fixed <- ncol(v3f_fixed) - 1L
cat(sprintf("  v3f_FIXED: %d rows × %d features (v1.3 69 + US macro 4 = 73)\n",
            nrow(v3f_fixed), n_v3f_fixed))
stopifnot(n_v3f_fixed == 73L)

v3f_path <- file.path(DATA_DIR, "feature_panel_v3f_us_macro_FIXED.parquet")
write_parquet(v3f_fixed, v3f_path)
cat(sprintf("  saved: %s (%.1f KB)\n", v3f_path, file.info(v3f_path)$size / 1024))

# ----------------------------------------------------------------------------
# Step 4: Build v5e_FIXED panel (v4a 70 + 4 US macro = 74)
# ----------------------------------------------------------------------------
cat("\n[Step 4] Build v5e_FIXED panel (v4a 70 + 4 US macro = 74)\n")

v4a_path <- file.path(DATA_DIR, "feature_panel_v4a_combined.parquet")
if (!file.exists(v4a_path)) stop(sprintf("missing v4a panel: %s", v4a_path))
v4a <- as.data.table(read_parquet(v4a_path))
v4a[, Date := as.Date(Date)]
setorder(v4a, Date)
n_v4a <- ncol(v4a) - 1L
cat(sprintf("  v4a baseline: %d rows × %d features\n", nrow(v4a), n_v4a))
stopifnot(n_v4a == 70L)

v5e_fixed <- merge(v4a, us_macro_feats, by = "Date", all.x = TRUE)
setorder(v5e_fixed, Date)
n_v5e_fixed <- ncol(v5e_fixed) - 1L
cat(sprintf("  v5e_FIXED: %d rows × %d features (v4a 70 + US macro 4 = 74)\n",
            nrow(v5e_fixed), n_v5e_fixed))
stopifnot(n_v5e_fixed == 74L)

v5e_path <- file.path(DATA_DIR, "feature_panel_v5e_q126_usmacro_FIXED.parquet")
write_parquet(v5e_fixed, v5e_path)
cat(sprintf("  saved: %s (%.1f KB)\n", v5e_path, file.info(v5e_path)$size / 1024))

# ----------------------------------------------------------------------------
# Step 5: Build v5f_FIXED panel (v5e_FIXED 74 + 5 ECOS = 79)
# ----------------------------------------------------------------------------
cat("\n[Step 5] Build v5f_FIXED panel (v5e_FIXED 74 + 5 ECOS = 79)\n")

ecos_path <- file.path(DATA_DIR, "ecos_kr_daily.csv")
if (!file.exists(ecos_path)) stop(sprintf("missing ECOS CSV: %s", ecos_path))
ecos <- fread(ecos_path)
ecos[, Date := as.Date(Date)]
setorder(ecos, Date)

ecos_features <- c(
  "ecos_m2_yoy_lag1",
  "ecos_krw_usd_change_5d_lag1",
  "ecos_base_rate_lag1",
  "ecos_industrial_production_yoy_lag1",
  "ecos_cpi_yoy_lag1"
)
stopifnot(all(ecos_features %in% names(ecos)))

v5f_fixed <- merge(v5e_fixed, ecos[, c("Date", ecos_features), with = FALSE],
                   by = "Date", all.x = TRUE)
setorder(v5f_fixed, Date)
n_v5f_fixed <- ncol(v5f_fixed) - 1L
cat(sprintf("  v5f_FIXED: %d rows × %d features (v5e_FIXED 74 + ECOS 5 = 79)\n",
            nrow(v5f_fixed), n_v5f_fixed))
stopifnot(n_v5f_fixed == 79L)

v5f_path <- file.path(DATA_DIR, "feature_panel_v5f_ecos_kr_FIXED.parquet")
write_parquet(v5f_fixed, v5f_path)
cat(sprintf("  saved: %s (%.1f KB)\n", v5f_path, file.info(v5f_path)$size / 1024))

# ----------------------------------------------------------------------------
# Step 6: Validation — compare BEFORE vs AFTER on 2020-03-02 (COVID lookahead test)
# ----------------------------------------------------------------------------
cat("\n[Step 6] Validation: v5e BEFORE vs AFTER on 2020-03-02 (COVID lookahead test)\n")

v5e_before <- as.data.table(read_parquet(file.path(DATA_DIR, "feature_panel_v5e_q126_usmacro.parquet")))
v5e_before[, Date := as.Date(Date)]
v5e_after <- v5e_fixed

mar02_before <- v5e_before[Date == as.Date("2020-03-02")]
mar02_after <- v5e_after[Date == as.Date("2020-03-02")]
cat(sprintf("  v5e BEFORE us_cfnai_lag1 on 2020-03-02: %.4f\n",
            mar02_before$us_cfnai_lag1[1]))
cat(sprintf("  v5e AFTER  us_cfnai_lag1 on 2020-03-02: %s\n",
            if (is.na(mar02_after$us_cfnai_lag1[1])) "NA" else sprintf("%.4f", mar02_after$us_cfnai_lag1[1])))
cat(sprintf("  EXPECTED: AFTER should be NA or older Jan 2020 reading (-0.25), NOT Mar -4.37 (BUGGY 53d lookahead)\n"))

# Codex Q2 nit (2026-05-21): hard assertion to catch regression
# After +55d fix: trader on 2020-03-02 (after shift(1L)) sees value dated 2020-03-01 or earlier
# in fixed CSV. 2020-03-01 = NA (March reading not released until 4/25). LOCF carries
# 2020-01-26 (-0.25, Jan reading at release date) forward. So expected ~ -0.25.
expected_jan_reading <- -0.25
mar02_after_val <- mar02_after$us_cfnai_lag1[1]
stopifnot(
  "PIT FIX REGRESSION: us_cfnai_lag1 on 2020-03-02 still shows BUGGY -4.37 (March reading 53d early)" =
    is.na(mar02_after_val) || abs(mar02_after_val - (-4.37)) > 1e-3,
  "PIT FIX REGRESSION: us_cfnai_lag1 on 2020-03-02 expected Jan reading (-0.25) but got unexpected value" =
    is.na(mar02_after_val) || abs(mar02_after_val - expected_jan_reading) < 0.5
)
cat(sprintf("  [stopifnot] CFNAI 2020-03-02 PIT regression test PASS (value=%.4f, not BUGGY -4.37)\n",
            ifelse(is.na(mar02_after_val), 0, mar02_after_val)))

# Sanity: any 2020-03-XX row where AFTER < BEFORE for CFNAI (indicates contamination removed)
v5e_before_covid <- v5e_before[Date >= as.Date("2020-03-01") & Date <= as.Date("2020-03-31")]
v5e_after_covid <- v5e_after[Date >= as.Date("2020-03-01") & Date <= as.Date("2020-03-31")]

# CFNAI lookahead validation
both_covid <- merge(v5e_before_covid[, .(Date, before_cfnai = us_cfnai_lag1)],
                     v5e_after_covid[, .(Date, after_cfnai = us_cfnai_lag1)],
                     by = "Date")
cat("\n[CFNAI lookahead diff 2020-03 (BEFORE buggy = -4.37 from 3/02 vs AFTER fixed)]:\n")
print(both_covid[1:15])

# Codex Q2 nit ICSA regression assertion (2026-05-21)
# Before fix: us_initial_claims_4w_avg_lag1 includes COVID claims 5d early via Sat dating
# After +5d fix: 2020-04-09 4w MA should be reduced (claims rolled into 4w window later)
v5e_b_apr09 <- v5e_before[Date == as.Date("2020-04-09")]
v5e_a_apr09 <- v5e_after[Date == as.Date("2020-04-09")]
icsa_diff_apr09 <- abs(v5e_b_apr09$us_initial_claims_4w_avg_lag1[1] - v5e_a_apr09$us_initial_claims_4w_avg_lag1[1])
stopifnot(
  "PIT FIX REGRESSION: ICSA 4w MA on 2020-04-09 unchanged after +5d shift (expected diff > 100K from COVID claims rolling)" =
    is.na(icsa_diff_apr09) || icsa_diff_apr09 > 100000
)
cat(sprintf("  [stopifnot] ICSA 4w MA 2020-04-09 PIT regression PASS (|Δ|=%.0f > 100K threshold)\n", icsa_diff_apr09))

# ----------------------------------------------------------------------------
# Step 7: Audit log
# ----------------------------------------------------------------------------
audit <- list(
  cycle = "57A",
  phase = "Phase 2: panel rebuild (FRED publication-lag FIXED)",
  inputs = list(
    fred_fixed_csv = fred_fixed_path,
    v1_3_panel = v1_3_path,
    v4a_panel = v4a_path,
    ecos_csv = ecos_path
  ),
  outputs = list(
    v3f_FIXED = v3f_path,
    v5e_FIXED = v5e_path,
    v5f_FIXED = v5f_path
  ),
  n_features = list(
    v3f_FIXED = n_v3f_fixed,
    v5e_FIXED = n_v5e_fixed,
    v5f_FIXED = n_v5f_fixed
  ),
  validation_covid_lookahead = list(
    v5e_before_us_cfnai_lag1_on_2020_03_02 = round(mar02_before$us_cfnai_lag1[1], 4),
    v5e_after_us_cfnai_lag1_on_2020_03_02 = if (is.na(mar02_after$us_cfnai_lag1[1])) "NA" else round(mar02_after$us_cfnai_lag1[1], 4),
    expected_after = "NA or older value (Jan 2020 reading +0.07) — NOT -4.37",
    lookahead_removed = !is.na(mar02_before$us_cfnai_lag1[1]) && (is.na(mar02_after$us_cfnai_lag1[1]) ||
                              mar02_after$us_cfnai_lag1[1] != mar02_before$us_cfnai_lag1[1])
  ),
  inherits_from = list(
    "Cycle 47B: original v3f panel build",
    "Cycle 52: v4a base panel (v1.3 + foreign breadth winner)",
    "Cycle 53H: v5e panel (v4a 70 + 4 US macro)",
    "Cycle 53I: v5f panel (v5e 74 + 5 ECOS)",
    "Cycle 55B: PIT deep audit (CFNAI ~22d / ICSA ~5d lookahead identified)",
    "Cycle 57A Phase 1: 95_fred_us_macro_pubLag_FIXED_offline.py (release-date dating)"
  ),
  next_step = "Phase 3: retrain affected q15 cycles (53H_v5e / 53I_v5f) on FIXED panels"
)
audit_path <- file.path(EVAL_DIR, "cycle57a_panel_rebuild_audit.json")
write_json(audit, audit_path, auto_unbox = TRUE, pretty = TRUE, na = "string")
cat(sprintf("\n[audit] %s\n", audit_path))

cat("\n========== Cycle 57A Phase 2 DONE ==========\n")
cat("\nRebuilt panels:\n")
cat(sprintf("  %s (73 features)\n", v3f_path))
cat(sprintf("  %s (74 features)\n", v5e_path))
cat(sprintf("  %s (79 features)\n", v5f_path))
cat("\nNext: scripts/174-176 (Phase 3 q15 retrain on FIXED panels)\n")
