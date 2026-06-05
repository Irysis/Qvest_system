#==============================================================================
# 131_feature_panel_v5e_q126_usmacro.R — Cycle 53H Path C 확장 Step 1
#
# Mandate:
#   - v4a 70 features (Cycle 52, v1.3 + foreign_breadth_ad_ratio_5d_avg_lag1)
#   - + 4 US macro features (Cycle 47B/48A, FRED, lag1):
#       us_t10y2y_spread_lag1
#       us_initial_claims_4w_avg_lag1
#       us_cfnai_lag1
#       us_stlfsi_lag1
#   - Total = 74 features
#
# Hypothesis 인용 (Cycle 48A discovery):
#   - q126 target swap에서 XGB/RF rank 1 = us_initial_claims_4w_avg_lag1
#   - q15/q63 target에서 rank 1 = us_cfnai_lag1
#   - US macro = 6-month leading indicator for KR equity
#   - Cycle 53B PatchTST q126 = 0.3456 (forward best ever) without US macro
#   - 가설: PatchTST + US macro = additive (+0.02~0.04 → 0.36~0.40)
#
# PIT 정합:
#   - v4a 70 features PIT validated (Cycle 52)
#   - US macro lag1: FRED publication lag 고려 (Cycle 47B 검증)
#   - v3f panel에서 column 추출 (재계산 회피)
#
# Output:
#   outputs/01_data/feature_panel_v5e_q126_usmacro.parquet (74 features)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")

dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)

cat("\n========== Cycle 53H Path C 확장 Step 1: v5e panel build (v4a 70 + US macro 4) ==========\n")

# ----------------------------------------------------------------------------
# Step 1a: Load v4a base panel (70 features — Cycle 52 forward research)
# ----------------------------------------------------------------------------
v4a_path <- file.path(DATA_DIR, "feature_panel_v4a_combined.parquet")
if (!file.exists(v4a_path)) stop(sprintf("missing v4a panel: %s", v4a_path))
v4a <- as.data.table(read_parquet(v4a_path))
v4a[, Date := as.Date(Date)]
setorder(v4a, Date)
n_v4a <- ncol(v4a) - 1L
cat(sprintf("[Step 1a] v4a base: %d rows × %d features\n", nrow(v4a), n_v4a))
stopifnot(n_v4a == 70L)

# ----------------------------------------------------------------------------
# Step 1b: Load v3f panel (74 features — Cycle 47B with US macro)
# ----------------------------------------------------------------------------
v3f_path <- file.path(DATA_DIR, "feature_panel_v3f_us_macro.parquet")
if (!file.exists(v3f_path)) stop(sprintf("missing v3f panel: %s", v3f_path))
v3f <- as.data.table(read_parquet(v3f_path))
v3f[, Date := as.Date(Date)]
setorder(v3f, Date)
cat(sprintf("[Step 1b] v3f panel: %d rows × %d features (includes US macro)\n",
            nrow(v3f), ncol(v3f) - 1L))

# ----------------------------------------------------------------------------
# Step 1c: Extract 4 US macro features from v3f
# ----------------------------------------------------------------------------
us_macro_cols <- c(
  "us_t10y2y_spread_lag1",
  "us_initial_claims_4w_avg_lag1",
  "us_cfnai_lag1",
  "us_stlfsi_lag1"
)
missing_us_cols <- setdiff(us_macro_cols, names(v3f))
if (length(missing_us_cols) > 0) {
  stop(sprintf("US macro columns missing from v3f: %s",
               paste(missing_us_cols, collapse = ", ")))
}
us_macro <- v3f[, c("Date", us_macro_cols), with = FALSE]
cat(sprintf("[Step 1c] US macro extracted: %d cols (%s)\n",
            length(us_macro_cols), paste(us_macro_cols, collapse = ", ")))

# ----------------------------------------------------------------------------
# Step 1d: PIT lag1 sanity — confirm shift(., 1, lag) already applied
# ----------------------------------------------------------------------------
fred_path <- file.path(DATA_DIR, "fred_us_macro_daily.csv")
if (file.exists(fred_path)) {
  fred <- fread(fred_path)
  fred[, Date := as.Date(Date)]
  setorder(fred, Date)
  cat(sprintf("[Step 1d] FRED CSV: %d rows, cols=%s\n",
              nrow(fred), paste(names(fred), collapse = ", ")))

  # PIT sanity: check lag1 columns vs FRED raw shift(., 1, lag)
  for (col in us_macro_cols) {
    raw_col <- sub("_lag1$", "", col)
    if (raw_col %in% names(fred)) {
      check <- merge(
        us_macro[, .(Date, val_panel = get(col))],
        fred[, .(Date, val_raw = get(raw_col))],
        by = "Date"
      )
      check[, val_shift := shift(val_raw, 1, type = "lag")]
      check_clean <- check[!is.na(val_panel) & !is.na(val_shift)]
      if (nrow(check_clean) > 0) {
        diff_max <- max(abs(check_clean$val_panel - check_clean$val_shift), na.rm = TRUE)
        cat(sprintf("  %s vs shift(%s, 1, lag): n=%d, max|diff|=%.6e\n",
                    col, raw_col, nrow(check_clean), diff_max))
      } else {
        cat(sprintf("  %s vs %s: NO overlap (forward-fill or different cadence)\n", col, raw_col))
      }
    } else {
      cat(sprintf("  %s: raw column %s NOT in FRED CSV (likely derived in panel build)\n",
                  col, raw_col))
    }
  }
} else {
  cat("[Step 1d] FRED CSV not found (skip raw shift sanity, v3f panel PIT inherit Cycle 47B)\n")
}

# ----------------------------------------------------------------------------
# Step 2: Merge v4a + US macro
# ----------------------------------------------------------------------------
combined <- merge(v4a, us_macro, by = "Date", all.x = TRUE)
setorder(combined, Date)

n_combined_features <- ncol(combined) - 1L
cat(sprintf("\n[Step 2] Combined panel: %d rows × %d features (v4a 70 + US macro 4 = 74)\n",
            nrow(combined), n_combined_features))
stopifnot(n_combined_features == 74L)

# Coverage report per US macro feature
cat("\n[Coverage US macro features]\n")
for (col in us_macro_cols) {
  non_na <- sum(!is.na(combined[[col]]))
  first_valid <- combined[!is.na(get(col))][1, Date]
  last_valid <- combined[!is.na(get(col))][.N, Date]
  cat(sprintf("  %s: non-NA=%d/%d (%.1f%%), range %s ~ %s\n",
              col, non_na, nrow(combined), 100 * non_na / nrow(combined),
              first_valid, last_valid))
}

# ----------------------------------------------------------------------------
# Step 3: Save
# ----------------------------------------------------------------------------
out_path <- file.path(DATA_DIR, "feature_panel_v5e_q126_usmacro.parquet")
write_parquet(combined, out_path)
cat(sprintf("\n[Saved] %s (size: %.1f KB)\n",
            out_path, file.info(out_path)$size / 1024))

# ----------------------------------------------------------------------------
# Step 4: Audit log
# ----------------------------------------------------------------------------
audit <- list(
  cycle = "53H_path_c_extension_q126_usmacro",
  step = "step1_feature_panel_build",
  base_panel = list(
    path = v4a_path,
    n_features = n_v4a,
    pit_validated = TRUE,
    inherit = "v1.3 baseline 69 + Cycle 43 winner foreign_breadth_ad_ratio_5d_avg_lag1"
  ),
  added_features = list(
    us_t10y2y_spread_lag1 = list(
      source = "v3f panel (Cycle 47B FRED fetch)",
      semantics = "US 10y-2y Treasury yield spread, lag1",
      cycle_48a_q126_xgb_rank = "found in top",
      pit_lag1 = TRUE
    ),
    us_initial_claims_4w_avg_lag1 = list(
      source = "v3f panel (Cycle 47B FRED fetch)",
      semantics = "US weekly initial jobless claims, 4-week MA, lag1",
      cycle_48a_q126_xgb_rank = "rank 1 (XGB q126), rank 1 (RF q126)",
      pit_lag1 = TRUE
    ),
    us_cfnai_lag1 = list(
      source = "v3f panel (Cycle 47B FRED fetch)",
      semantics = "Chicago Fed National Activity Index, lag1",
      cycle_48a_q126_xgb_rank = "rank 1 (q15 + q63), strong q126",
      pit_lag1 = TRUE
    ),
    us_stlfsi_lag1 = list(
      source = "v3f panel (Cycle 47B FRED fetch)",
      semantics = "St. Louis Fed Financial Stress Index, lag1",
      cycle_48a_q126_xgb_rank = "found in top",
      pit_lag1 = TRUE
    )
  ),
  combined_n_features = n_combined_features,
  output = out_path,
  pit_audit = list(
    C13 = "no negation / sign flip — US macro features use raw lag1 shift",
    C14 = "label-side NOT used in feature panel — IC contamination 무관",
    C15 = "non-Factor DB features — FRED enhancement"
  ),
  inherits_from = list(
    "Cycle 47B: v3f panel build (us_macro_features fetch + lag1 validation)",
    "Cycle 48A: q126 target swap discovery (us_initial_claims, us_cfnai rank 1)",
    "Cycle 52: v4a base panel build (v1.3 + foreign breadth winner)",
    "Cycle 53B: PatchTST q126 0.3456 (forward best ever) — baseline for additivity test"
  )
)
write_json(audit,
           file.path(EVAL_DIR, "v5e_q126_usmacro_step1.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[Audit] %s\n", file.path(EVAL_DIR, "v5e_q126_usmacro_step1.json")))

cat("\n========== Cycle 53H Step 1 DONE — Run scripts/132_patchtst_q126_usmacro.py next ==========\n")
