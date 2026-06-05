#==============================================================================
# 119_feature_panel_v4a_combined.R — Cycle 52 Path A Step 1
#
# Mandate (Cycle 51 cleanup 후 첫 정식 forward research cycle):
#   - v1.3 baseline 69 features + Cycle 43 winning feature
#   - Cycle 43 winner: foreign_breadth_ad_ratio_5d_avg_lag1 (1 feature, "5d MA")
#   - Cycle 43 v2_2feat 다른 feature foreign_cum_5d_lag1 DROP (dead 입증)
#   - Total = 70 features
#
# PIT 정합:
#   - v1.3 baseline 69 PIT validated retain
#   - foreign_breadth_ad_ratio_5d_avg_lag1 lag1 shift 확인 (이미 v2_2feat 내장)
#   - feature_panel_v2_2feat.parquet 의 ad_ratio_5d_avg_lag1 column 이 정확히 foreign breadth
#     advance/decline ratio 5-day moving average lag1 (corr 1.0 with investor_breadth_daily.csv)
#
# Output:
#   outputs/01_data/feature_panel_v4a_combined.parquet (70 features)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")

dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)

cat("\n========== Cycle 52 Path A Step 1: Combined feature panel build ==========\n")

# v1.3 baseline 69 features (PIT validated, forward labels 정합)
v13_path <- file.path(DATA_DIR, "feature_panel_v1_3.parquet")
if (!file.exists(v13_path)) stop(sprintf("missing v1.3 panel: %s", v13_path))
v13 <- as.data.table(read_parquet(v13_path))
v13[, Date := as.Date(Date)]
setorder(v13, Date)
n_v13 <- ncol(v13) - 1L
cat(sprintf("[Step 1a] v1.3 baseline: %d rows × %d features\n", nrow(v13), n_v13))
stopifnot(n_v13 == 69L)

# v2_2feat panel from which foreign_breadth_ad_ratio_5d_avg_lag1 is extracted
v22_path <- file.path(DATA_DIR, "feature_panel_v2_2feat.parquet")
if (!file.exists(v22_path)) stop(sprintf("missing v2_2feat panel: %s", v22_path))
v22 <- as.data.table(read_parquet(v22_path))
v22[, Date := as.Date(Date)]
setorder(v22, Date)
cat(sprintf("[Step 1b] v2_2feat: %d rows × %d cols\n", nrow(v22), ncol(v22) - 1L))

stopifnot("ad_ratio_5d_avg_lag1" %in% names(v22))

# Extract winning feature (Cycle 43 verdict #1 forward leaderboard 0.2129 M4_Bayes)
winner_col <- "ad_ratio_5d_avg_lag1"  # foreign_breadth_ad_ratio_5d_avg_lag1
winner <- v22[, .(Date, foreign_breadth_ad_ratio_5d_avg_lag1 = get(winner_col))]
cat(sprintf("[Step 1c] Winning feature extracted: %s → renamed foreign_breadth_ad_ratio_5d_avg_lag1\n",
            winner_col))

# Sanity: investor_breadth_daily.csv 직접 비교 (Cycle 41 source — foreign breadth)
br_path <- file.path(DATA_DIR, "investor_breadth_daily.csv")
if (file.exists(br_path)) {
  br <- fread(br_path)
  br[, Date := as.Date(Date)]
  br[, ad_ratio_5d := frollmean(ad_ratio, 5)]
  br[, ad_ratio_5d_avg_lag1 := shift(ad_ratio_5d, 1, type = "lag")]
  merged <- merge(winner, br[, .(Date, br_val = ad_ratio_5d_avg_lag1)], by = "Date")
  nn <- merged[complete.cases(merged)]
  diff_max <- max(abs(nn$foreign_breadth_ad_ratio_5d_avg_lag1 - nn$br_val))
  cat(sprintf("[Step 1c-sanity] vs investor_breadth_daily reconstruction: n=%d, max|diff|=%.6e\n",
              nrow(nn), diff_max))
  stopifnot(diff_max < 1e-6)
  cat("[Step 1c-sanity] CONFIRMED: winner == foreign breadth advance/decline ratio 5d MA lag1 (Cycle 41 source)\n")
}

# Combined panel: v1.3 + winner (70 features)
combined <- merge(v13, winner, by = "Date", all.x = TRUE)
setorder(combined, Date)

n_combined_features <- ncol(combined) - 1L
cat(sprintf("\n[Step 2] Combined panel: %d rows × %d features (v1.3 69 + winner 1 = 70)\n",
            nrow(combined), n_combined_features))
stopifnot(n_combined_features == 70L)

# PIT lag1 sanity: winner feature has lag1 in name (shift from t to t+1 already applied in source)
# Confirm by computing winner_unlagged from investor_breadth_daily and verifying winner == shift(unlagged, 1)
if (file.exists(br_path)) {
  br[, ad_ratio_5d_TODAY := frollmean(ad_ratio, 5)]
  br_check <- merge(winner, br[, .(Date, today = ad_ratio_5d_TODAY)], by = "Date")
  br_check[, lag1_reconstruct := shift(today, 1, type = "lag")]
  br_check_clean <- br_check[complete.cases(br_check)]
  diff_lag1 <- max(abs(br_check_clean$foreign_breadth_ad_ratio_5d_avg_lag1 -
                       br_check_clean$lag1_reconstruct))
  cat(sprintf("[PIT lag1 sanity] max|winner - shift(today_5d_avg, 1)|=%.6e — must be 0\n", diff_lag1))
  stopifnot(diff_lag1 < 1e-9)
  cat("[PIT lag1 sanity] PASS — feature uses t-1 information only (no lookahead)\n")
}

# Coverage report
cat("\n[Coverage]\n")
non_na_v13_first <- v13[which.min(apply(v13[, -1], 1, function(r) sum(is.na(r))))]
non_na_winner_count <- sum(!is.na(combined$foreign_breadth_ad_ratio_5d_avg_lag1))
cat(sprintf("  v1.3 features non-NA: row 1 NA count = %d (excluding Date)\n",
            sum(is.na(v13[1, -1]))))
cat(sprintf("  winner non-NA: %d / %d (%.1f%%)\n",
            non_na_winner_count, nrow(combined),
            100 * non_na_winner_count / nrow(combined)))
first_valid <- combined[!is.na(foreign_breadth_ad_ratio_5d_avg_lag1)][1, Date]
last_valid <- combined[!is.na(foreign_breadth_ad_ratio_5d_avg_lag1)][.N, Date]
cat(sprintf("  winner valid range: %s ~ %s\n", first_valid, last_valid))

# Save
out_path <- file.path(DATA_DIR, "feature_panel_v4a_combined.parquet")
write_parquet(combined, out_path)
cat(sprintf("\n[Saved] %s (size: %.1f KB)\n",
            out_path, file.info(out_path)$size / 1024))

# Audit log
audit <- list(
  cycle = "52_path_a_combined",
  step = "step1_feature_panel_build",
  base_panel = list(
    path = v13_path,
    n_features = n_v13,
    pit_validated = TRUE
  ),
  added_features = list(
    foreign_breadth_ad_ratio_5d_avg_lag1 = list(
      source = "v2_2feat panel (ad_ratio_5d_avg_lag1) — Cycle 41 investor breadth",
      semantics = "foreign investor (외인) breadth advance/decline ratio, 5-day moving average, lag-1",
      cycle_43_verdict = "WINNING_FEATURE",
      forward_M4_Bayes_PRAUC = 0.2129,
      pit_lag1_verified = TRUE
    )
  ),
  dropped_features = list(
    foreign_cum_5d_lag1 = "DROPPED — Cycle 43 dead 입증"
  ),
  combined_n_features = n_combined_features,
  output = out_path,
  pit_audit = list(
    C13 = "no negation / sign flip — winner uses raw lag1 shift",
    C14 = "label-side NOT used in feature panel — IC contamination 무관",
    C15 = "non-Factor DB feature — investor breadth is local enhancement"
  )
)
write_json(audit,
           file.path(EVAL_DIR, "v4a_combined_step1.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[Audit] %s\n", file.path(EVAL_DIR, "v4a_combined_step1.json")))

cat("\n========== Cycle 52 Step 1 DONE — Run scripts/120_5way_retrain_v4a_combined.R next ==========\n")
