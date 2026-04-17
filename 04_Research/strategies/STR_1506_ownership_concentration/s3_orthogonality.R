#==============================================================================
# STR_1506_ownership_concentration — S3 Orthogonality Analysis
# Factor: CR04_Ownership_Concentration
# Grade C, SR 0.531 (from S2 profile)
#==============================================================================
cat("=== STR_1506: S3 Orthogonality — CR04_Ownership_Concentration ===\n")

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

# ---- Source infrastructure ----
ROOT <- "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
INFRA <- file.path(ROOT, "02_Infrastructure")

source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "factor_db_connector.R"))
source(file.path(INFRA, "factor_research_pipeline.R"))

# ---- Parameters ----
FACTOR_ID   <- "CR04_Ownership_Concentration"
STRATEGY_ID <- "STR_1506_ownership_concentration"
SIG_DATES   <- as.Date(c("2024-12-31", "2023-12-31", "2022-12-31",
                          "2021-12-31", "2020-12-31"))

cat("\n[S3] Factor:", FACTOR_ID, "\n")
cat("[S3] Dates:", paste(SIG_DATES, collapse = ", "), "\n\n")

# ---- Factor-Level Orthogonality per date ----
results_list <- list()

for (sig_d in SIG_DATES) {
  sig_d <- as.Date(sig_d, origin = "1970-01-01")
  cat("\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\n")
  cat("[S3] Date:", as.character(sig_d), "\n")

  # Load CR04 Z-scores for this date
  fdt <- tryCatch(
    load_month_factors(sig_d, coverage_min = 0.01),
    error = function(e) { cat("  ERROR loading factors:", e$message, "\n"); NULL }
  )
  if (is.null(fdt)) next

  cr04 <- fdt[Factor_Name == FACTOR_ID]
  if (nrow(cr04) == 0) {
    cat("  WARNING: CR04 not found in factor DB for", as.character(sig_d), "\n")
    next
  }

  new_z <- setNames(cr04$Z_Score_Aligned, cr04$Ticker)
  cat("  CR04 coverage:", length(new_z), "tickers\n")

  # Compute orthogonality (active_only = FALSE per instructions)
  ortho <- tryCatch(
    compute_factor_orthogonality(new_z, sig_d, active_only = FALSE),
    error = function(e) { cat("  ERROR in orthogonality:", e$message, "\n"); NULL }
  )
  if (is.null(ortho)) next

  # Remove CR04 itself from pairwise_corr
  pw <- ortho$pairwise_corr[Factor_Name != FACTOR_ID]

  # Top 10 most correlated
  pw[, Abs_Corr := abs(Corr)]
  top10 <- pw[order(-Abs_Corr)][1:min(10, nrow(pw))]
  cat("\n  Top 10 most correlated factors:\n")
  cat("  ", sprintf("%-35s %s", "Factor", "Corr"), "\n")
  cat("  ", paste(rep("-", 45), collapse = ""), "\n")
  for (i in seq_len(nrow(top10))) {
    cat("  ", sprintf("%-35s %+.4f", top10$Factor_Name[i], top10$Corr[i]), "\n")
  }

  # Check CR06_DTC_Proxy and CR08 specifically
  cat("\n  Specific factor checks:\n")
  for (check_f in c("CR06_DTC_Proxy", "CR08_Herding_Beta")) {
    row <- pw[grepl(check_f, Factor_Name, fixed = FALSE)]
    if (nrow(row) > 0) {
      cat("    ", row$Factor_Name[1], ": corr =", sprintf("%+.4f", row$Corr[1]), "\n")
    } else {
      # Try broader match for CR08
      row2 <- pw[grepl(paste0("^", sub("_.*", "", check_f)), Factor_Name)]
      if (nrow(row2) > 0) {
        cat("    ", row2$Factor_Name[1], ": corr =", sprintf("%+.4f", row2$Corr[1]), "\n")
      } else {
        cat("    ", check_f, ": NOT FOUND in factor DB\n")
      }
    }
  }

  # Recompute max_corr excluding CR04 itself
  filtered_max_corr <- pw[, max(Abs_Corr, na.rm = TRUE)]
  filtered_max_factor <- pw[which.max(Abs_Corr), Factor_Name]
  filtered_independence <- if (filtered_max_corr > 0.6) "redundant" else if (filtered_max_corr > 0.3) "partial" else "independent"

  cat("\n  Max |corr| (excl self):", sprintf("%.4f", filtered_max_corr),
      " (", filtered_max_factor, ")\n")
  cat("  Independence:", filtered_independence, "\n\n")

  results_list[[as.character(sig_d)]] <- list(
    date = as.character(sig_d),
    max_corr = filtered_max_corr,
    max_corr_factor = filtered_max_factor,
    independence = filtered_independence,
    n_factors = nrow(pw),
    top3 = head(top10, 3)
  )
}

# ---- Aggregate across dates ----
cat("\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\n")
cat("[S3] AGGREGATE RESULTS\n")
cat("\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\n")

max_corrs <- sapply(results_list, function(x) x$max_corr)
mean_max_corr <- mean(max_corrs, na.rm = TRUE)
novelty_score <- max(0, 1 - mean_max_corr)

cat("  Dates analyzed:", length(results_list), "/", length(SIG_DATES), "\n")
cat("  Max |corr| per date:", paste(sprintf("%.4f", max_corrs), collapse = ", "), "\n")
cat("  Mean max |corr|:", sprintf("%.4f", mean_max_corr), "\n")
cat("  Novelty score:", sprintf("%.4f", novelty_score), "\n")

# Independence verdict based on mean_max_corr
if (mean_max_corr > 0.6) {
  verdict_independence <- "redundant"
} else if (mean_max_corr > 0.3) {
  verdict_independence <- "partial"
} else {
  verdict_independence <- "independent"
}
cat("  Factor independence:", verdict_independence, "\n")

# Overall verdict
if (verdict_independence == "redundant") {
  verdict <- "REJECT — factor is redundant with existing pool"
} else if (verdict_independence == "partial") {
  verdict <- "CONDITIONAL — partial overlap; may add value if alpha is strong"
} else {
  verdict <- "PASS — factor is sufficiently independent"
}
cat("  S3 Verdict:", verdict, "\n\n")

# ---- Load s0/s2 for context ----
artifact_dir <- file.path(
  ROOT, "04_Research/strategies", STRATEGY_ID, "stage_artifacts"
)

s0_path <- file.path(artifact_dir, "s0_record_CR04_Ownership_Concentration.json")
s2_path <- file.path(artifact_dir, "s2_profile_CR04_Ownership_Concentration.json")

s2_grade <- NA_character_
s2_sharpe <- NA_real_
if (file.exists(s2_path)) {
  s2 <- fromJSON(s2_path)
  s2_grade <- s2$grade %||% NA_character_
  s2_sharpe <- s2$sharpe %||% NA_real_
  cat("[S3] S2 profile: Grade =", s2_grade, ", Sharpe =", s2_sharpe, "\n")
}
if (file.exists(s0_path)) {
  s0 <- fromJSON(s0_path)
  cat("[S3] S0 expected_role:", s0$expected_role %||% "NA", "\n")
}

# ---- Save artifact ----
artifact <- list(
  strategy_id          = STRATEGY_ID,
  factor_id            = FACTOR_ID,
  stage                = "S3",
  factor_independence   = verdict_independence,
  factor_mean_max_corr  = round(mean_max_corr, 4),
  max_corr_per_date    = as.list(round(max_corrs, 4)),
  novelty_score        = round(novelty_score, 4),
  candidate_role_hint  = "diversifier",
  s2_grade             = s2_grade,
  s2_sharpe            = s2_sharpe,
  verdict              = verdict,
  dates_analyzed       = length(results_list),
  created_at           = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
)

if (!dir.exists(artifact_dir)) dir.create(artifact_dir, recursive = TRUE)

artifact_path <- file.path(artifact_dir, "s3_orthogonality_CR04_OwnershipConcentration.json")
write_json(artifact, artifact_path, pretty = TRUE, auto_unbox = TRUE)
cat("[S3] Artifact saved:", artifact_path, "\n")
cat("\n=== S3 Orthogonality Complete ===\n")
