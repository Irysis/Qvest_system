#!/usr/bin/env Rscript
# S3 직교성 분석 — 범용 스크립트
# Usage: Rscript -e 'STRATEGY_DIR <- "..."; STRATEGY_ID <- "..."; FACTOR_IDS <- "..."; source(".cache/run_s3_orthogonality.R")'

suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(arrow)
})

ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
INFRA <- file.path(ROOT, "02_Infrastructure")

cat(sprintf("\n=== S3 Orthogonality: %s ===\n", STRATEGY_ID))

# Source infrastructure
INFRA_DIR <- INFRA
LIQ_THRESHOLD <- 2e8
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "factor_research_pipeline.R"))

# OPTIMIZED: Load only latest month Z-score directly from Factor DB
# (instead of re-running full 302-month factor_engine.R)
cat("[S3] Loading latest month Z-score directly from Factor DB...\n")
SCRIPT_DIR <- STRATEGY_DIR
source(file.path(INFRA, "factor_db_connector.R"))

# Find latest available factor DB date
fdb_files <- list.files(file.path(CACHE_DIR, "factor_db"), pattern = "^factor_db_\\d{6}\\.parquet$")
latest_ym <- max(gsub("factor_db_(\\d{6})\\.parquet", "\\1", fdb_files))
latest_date <- as.Date(paste0(latest_ym, "01"), "%Y%m%d")
cat(sprintf("[S3] Latest factor DB date: %s\n", latest_date))

# Load all factors for latest month
fdt <- load_month_factors(latest_date, coverage_min = 0.01)
cat(sprintf("[S3] Loaded %d rows, %d factors\n", nrow(fdt), length(unique(fdt$Factor_Name))))

# Extract target factor Z-score
self_factors <- unlist(strsplit(FACTOR_IDS, "[+]"))
target_fdt <- fdt[Factor_Name %in% self_factors & !is.na(Z_Score_Aligned)]

if (nrow(target_fdt) == 0) {
  # Fallback: for multi-factor strategies, run factor_engine
  cat("[S3] Target factor not found in DB, falling back to factor_engine...\n")
  source(file.path(INFRA, "backtest_harness.R"))
  res <- load_rawdata(use_cache = TRUE)
  RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
  source(file.path(STRATEGY_DIR, "factor_engine.R"))
  latest_date <- FACTORS[, max(Date)]
  score_dt <- FACTORS[Date == latest_date, .(Ticker, Score)]
} else if (length(self_factors) == 1) {
  # Single factor: use Z_Score_Aligned directly
  score_dt <- target_fdt[, .(Ticker, Score = Z_Score_Aligned)]
} else {
  # Multi-factor: average Z_Score_Aligned across factors
  score_dt <- target_fdt[, .(Score = mean(Z_Score_Aligned, na.rm = TRUE)), by = Ticker]
}

score_dt <- score_dt[!is.na(Score)]
new_z <- setNames(score_dt$Score, score_dt$Ticker)
cat(sprintf("[S3] N tickers with score: %d\n", length(new_z)))

# Run orthogonality
cat("[S3] Computing orthogonality vs 268 factors...\n")
orth <- compute_factor_orthogonality(new_z, latest_date, active_only = FALSE)

# Remove self-reference: exclude factors that match FACTOR_IDS
self_factors <- unlist(strsplit(FACTOR_IDS, "[+]"))
orth$pairwise_corr <- orth$pairwise_corr[!Factor_Name %in% self_factors]
if (nrow(orth$pairwise_corr) > 0) {
  max_idx <- which.max(abs(orth$pairwise_corr$Corr))
  orth$max_corr <- abs(orth$pairwise_corr$Corr[max_idx])
  orth$max_corr_factor <- orth$pairwise_corr$Factor_Name[max_idx]
  orth$independence <- if (orth$max_corr < 0.3) "independent"
    else if (orth$max_corr < 0.6) "partial"
    else "redundant"
  orth$n_compared <- nrow(orth$pairwise_corr)
  # Recalculate category corr
  orth$pairwise_corr[, Category := gsub("^([A-Z]+)\\d+.*", "\\1", Factor_Name)]
  orth$category_corr <- orth$pairwise_corr[, .(Max_Corr = max(abs(Corr), na.rm = TRUE)), by = Category]
  setorder(orth$category_corr, -Max_Corr)
}

cat(sprintf("[S3] Max |corr|: %.3f with %s\n", orth$max_corr, orth$max_corr_factor))
cat(sprintf("[S3] Independence: %s\n", orth$independence))
cat(sprintf("[S3] N compared: %d\n", orth$n_compared))

# Top 10 most correlated
top10 <- orth$pairwise_corr[order(-abs(Corr))][1:min(10, nrow(orth$pairwise_corr))]
cat("\n[S3] Top 10 correlated factors:\n")
print(top10[, .(Factor_Name, Corr = round(Corr, 3))])

# Category correlations
cat("\n[S3] Category-level max correlations:\n")
print(orth$category_corr[1:min(10, nrow(orth$category_corr))])

# Compute novelty score: 1 - max_corr (higher = more novel)
novelty_score <- round(1 - orth$max_corr, 2)

# Determine candidate role hint based on correlations
# If low corr with C19 (consensus) -> good diversifier
c19_corr <- orth$pairwise_corr[Factor_Name == "C19_Composite_Earnings", Corr]
d01_corr <- orth$pairwise_corr[Factor_Name == "D01_IdioVol", Corr]

if (length(c19_corr) == 0) c19_corr <- NA
if (length(d01_corr) == 0) d01_corr <- NA

role_hint <- if (!is.na(c19_corr) && abs(c19_corr) < 0.3) {
  "diversifier"
} else if (!is.na(d01_corr) && abs(d01_corr) > 0.5) {
  "defense"
} else {
  "core_alpha"
}

# Compute mean of top-5 max correlations across categories
cat_top5 <- orth$category_corr[1:min(5, nrow(orth$category_corr)), Mean_Cat := Max_Corr]
factor_mean_max_corr <- round(mean(orth$category_corr$Max_Corr[1:min(5, nrow(orth$category_corr))]), 3)

# Write S3 artifact
s3_artifact <- list(
  factor_id = FACTOR_IDS,
  strategy_id = STRATEGY_ID,
  stage = "S3",
  max_abs_corr_db = round(orth$max_corr, 3),
  most_correlated_factor = orth$max_corr_factor,
  independence_class = orth$independence,
  factor_mean_max_corr = factor_mean_max_corr,
  c19_corr = if (!is.na(c19_corr)) round(c19_corr, 3) else NA,
  d01_corr = if (!is.na(d01_corr)) round(d01_corr, 3) else NA,
  n_compared = orth$n_compared,
  computed_date = as.character(latest_date),
  novelty_score = novelty_score,
  candidate_role_hint = role_hint,
  top10_correlated = lapply(1:nrow(top10), function(i) {
    list(factor = top10$Factor_Name[i], corr = round(top10$Corr[i], 3))
  }),
  category_corr = lapply(1:min(10, nrow(orth$category_corr)), function(i) {
    list(category = orth$category_corr$Category[i], max_corr = round(orth$category_corr$Max_Corr[i], 3))
  })
)

artifact_dir <- file.path(STRATEGY_DIR, "stage_artifacts")
dir.create(artifact_dir, showWarnings = FALSE, recursive = TRUE)
artifact_path <- file.path(artifact_dir, paste0("s3_orthogonality_", STRATEGY_ID, ".json"))
write_json(s3_artifact, artifact_path, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[S3] Artifact written: %s\n", artifact_path))
cat(sprintf("=== S3 Complete: %s | independence=%s | novelty=%.2f | role=%s ===\n",
            STRATEGY_ID, orth$independence, novelty_score, role_hint))
