#==============================================================================
# cycle58c_prediction_correlation_diag.R
#
# 목적: 모든 q15 mean5 prediction 파일 간 pairwise correlation 측정 +
#       architecture homogeneity 진단 → 58D direction decision 준비.
#
# 가설: mean5 within-cycle (variance reduction)는 PatchTST family seed variance
#       위주. cross-cycle ensemble 효과 적은 이유 = 모든 cycle PatchTST family
#       변형이므로 systematic error 상관. 진정 architecture diversity 필요.
#
# Schema: Date / p_mean5 / p_per_seed_std / y / split / target / cycle / n_seeds
# CPU-only (no GPU contention with Phase 2-5 runner).
# Date: 2026-05-21 Cycle 58C parallel diagnostic.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(
  PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data"
)
MODEL_DIR <- file.path(WS, "outputs/03_models")
OUT_DIR <- file.path(WS, "outputs/04_evaluation")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# 1. mean5 q15 files
cat(sprintf("[%s] Collecting q15 mean5 files...\n",
            format(Sys.time(), "%H:%M:%S")))
mean5_files <- list.files(
  MODEL_DIR,
  pattern = "predictions_.*_mean5_y_tail_q15\\.parquet$",
  recursive = TRUE,
  full.names = TRUE
)
cat(sprintf("[%s] mean5 ensembles: %d\n",
            format(Sys.time(), "%H:%M:%S"),
            length(mean5_files)))

labels <- sub("_mean5_y_tail_q15.parquet", "",
              sub("^predictions_", "", basename(mean5_files)))

# 2. Load — OOS only, p_mean5
cat(sprintf("[%s] Loading OOS predictions...\n",
            format(Sys.time(), "%H:%M:%S")))
pred_list <- lapply(seq_along(mean5_files), function(i) {
  d <- as.data.table(read_parquet(mean5_files[i]))
  d <- d[split == "oos", .(Date = as.Date(Date), pred = p_mean5)]
  setorder(d, Date)
  d
})

# 3. Common dates intersection
date_sets <- lapply(pred_list, function(x) x$Date)
common_dates <- Reduce(intersect, date_sets)
common_dates <- as.Date(common_dates, origin = "1970-01-01")
cat(sprintf("[%s] Common OOS dates across %d ensembles: %d\n",
            format(Sys.time(), "%H:%M:%S"),
            length(pred_list),
            length(common_dates)))

# 4. Build prediction matrix
pred_mat <- do.call(cbind, lapply(pred_list, function(d) {
  d2 <- d[Date %in% common_dates]
  setorder(d2, Date)
  d2$pred
}))
colnames(pred_mat) <- labels
cat(sprintf("[%s] Matrix dim: %d × %d\n",
            format(Sys.time(), "%H:%M:%S"),
            nrow(pred_mat), ncol(pred_mat)))

# 5. Pairwise Spearman correlation
cat(sprintf("[%s] Spearman correlation matrix...\n",
            format(Sys.time(), "%H:%M:%S")))
cor_mat <- cor(pred_mat, method = "spearman", use = "pairwise.complete.obs")

# 6. Upper-triangle statistics
upper <- cor_mat[upper.tri(cor_mat)]
cat(sprintf("[%s] Pairwise correlation (n=%d pairs):\n",
            format(Sys.time(), "%H:%M:%S"),
            length(upper)))
cat(sprintf("  min: %.4f\n", min(upper, na.rm = TRUE)))
cat(sprintf("  Q1:  %.4f\n", quantile(upper, 0.25, na.rm = TRUE)))
cat(sprintf("  med: %.4f\n", median(upper, na.rm = TRUE)))
cat(sprintf("  mean:%.4f\n", mean(upper, na.rm = TRUE)))
cat(sprintf("  Q3:  %.4f\n", quantile(upper, 0.75, na.rm = TRUE)))
cat(sprintf("  max: %.4f\n", max(upper, na.rm = TRUE)))

# 7. Diversity check
low_pairs <- which(cor_mat < 0.5 & lower.tri(cor_mat), arr.ind = TRUE)
cat(sprintf("\n[%s] Architectural diversity (Spearman < 0.5):\n",
            format(Sys.time(), "%H:%M:%S")))
if (nrow(low_pairs) > 0) {
  for (i in seq_len(min(20, nrow(low_pairs)))) {
    r <- low_pairs[i, 1]
    cc <- low_pairs[i, 2]
    cat(sprintf("  %s  vs  %s : rho=%.4f\n",
                labels[r], labels[cc], cor_mat[r, cc]))
  }
} else {
  cat("  NONE — all pairs rho >= 0.5 (homogeneity confirmed)\n")
}

# Also: highest correlations (most redundant pairs)
high_pairs <- which(cor_mat > 0.95 & lower.tri(cor_mat), arr.ind = TRUE)
cat(sprintf("\n[%s] Redundant pairs (rho > 0.95):\n",
            format(Sys.time(), "%H:%M:%S")))
if (nrow(high_pairs) > 0) {
  for (i in seq_len(min(20, nrow(high_pairs)))) {
    r <- high_pairs[i, 1]
    cc <- high_pairs[i, 2]
    cat(sprintf("  %s  vs  %s : rho=%.4f\n",
                labels[r], labels[cc], cor_mat[r, cc]))
  }
} else {
  cat("  NONE\n")
}

# 8. Hierarchical clustering
cat(sprintf("\n[%s] Hierarchical clustering (1-rho complete linkage):\n",
            format(Sys.time(), "%H:%M:%S")))
dist_mat <- as.dist(1 - cor_mat)
hc <- hclust(dist_mat, method = "complete")

clusters <- cutree(hc, h = 0.3)
n_clusters <- length(unique(clusters))
cat(sprintf("  Clusters at rho>0.7 threshold: %d\n", n_clusters))
for (cl in seq_len(n_clusters)) {
  members <- labels[clusters == cl]
  cat(sprintf("  Cluster %d (n=%d): %s\n",
              cl, length(members),
              paste(head(members, 5), collapse = ", ")))
  if (length(members) > 5) {
    cat(sprintf("    ... (+%d more)\n", length(members) - 5))
  }
}

# 9. Save diagnostic JSON
mean_rho <- mean(upper, na.rm = TRUE)
diag <- list(
  timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  n_mean5_ensembles = length(mean5_files),
  common_oos_dates = length(common_dates),
  labels = labels,
  pairwise_cor_summary = list(
    n_pairs = length(upper),
    min = min(upper, na.rm = TRUE),
    q1 = quantile(upper, 0.25, na.rm = TRUE),
    median = median(upper, na.rm = TRUE),
    mean = mean_rho,
    q3 = quantile(upper, 0.75, na.rm = TRUE),
    max = max(upper, na.rm = TRUE)
  ),
  diversity_check = list(
    n_pairs_below_0.5 = sum(upper < 0.5, na.rm = TRUE),
    n_pairs_above_0.95 = sum(upper > 0.95, na.rm = TRUE),
    n_pairs_total = length(upper),
    pct_diverse = mean(upper < 0.5, na.rm = TRUE) * 100,
    pct_redundant = mean(upper > 0.95, na.rm = TRUE) * 100,
    interpretation = if (mean_rho > 0.7) {
      "ARCHITECTURAL_HOMOGENEITY_CONFIRMED"
    } else if (mean_rho > 0.5) {
      "MODERATE_DIVERSITY"
    } else {
      "HIGH_DIVERSITY"
    }
  ),
  clusters_at_rho07 = n_clusters,
  cluster_assignments = setNames(as.integer(clusters), labels),
  recommendation_for_58d = if (n_clusters <= 2) {
    paste("LAUNCH_TRUE_DIVERSITY: 58D should test fundamentally different",
          "architectures outside PatchTST family.",
          "Current corpus dominated by 1-2 clusters = mean5 within-cycle",
          "absorbs seed noise but cross-cycle yields little because",
          "systematic errors correlate.")
  } else if (n_clusters <= 5) {
    paste("STACKING_OPPORTUNITY: 58D should test meta-learner stacking",
          "on cluster representatives (XGB/Ridge).")
  } else {
    paste("DIVERSITY_OK: corpus already diverse, focus on",
          "calibration (conformal/isotonic) or feature engineering.")
  }
)
out_json <- file.path(OUT_DIR, "cycle58c_prediction_correlation_diag.json")
jsonlite::write_json(diag, out_json, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[%s] Saved: %s\n",
            format(Sys.time(), "%H:%M:%S"), out_json))

# 10. Save correlation matrix CSV
cor_dt <- data.table(label_row = rownames(cor_mat), cor_mat)
out_csv <- file.path(OUT_DIR, "cycle58c_prediction_correlation_matrix.csv")
fwrite(cor_dt, out_csv)
cat(sprintf("[%s] Saved: %s\n",
            format(Sys.time(), "%H:%M:%S"), out_csv))

cat(sprintf("\n[%s] DONE diagnostic.\n", format(Sys.time(), "%H:%M:%S")))
