#==============================================================================
# WT-D20260528_003 / hypothesis_C — Alpha Vector Bug Fix
#
# Issues found in 01_microstructure_alpha.R draft:
#   1. alpha_vector serialized as unnamed array (lost Ticker keys) — jsonlite/data.table interaction
#      → Optimizer cannot map alpha to Ticker. Use named numeric vector via setNames+as.list.
#   2. alpha_z tied: 5 stocks × 4 sleeves all received identical 0.6441 (mean of single-sleeve membership)
#      → Lost intra-sleeve gradient. Solution: use raw Z_Score_Aligned values, not mean (sleeve_count=1 dominant).
#   3. sleeves_in distribution: 1 or 2 only (no triple/quad overlap)
#      → Multi-sleeve union working but with weak intersection. Acceptable design (orthogonality intentional).
#
# Strategy: Use *within-sleeve aligned Z* as alpha. For multi-sleeve overlap, sum (or weighted).
# Drop sig_date <= cutoff filter on outputs (already PIT-safe via load).
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ_ROOT)

WT_ID <- "WT-D20260528_003"
OUT_MAILBOX <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
OUT_STAGE   <- file.path(PROJ_ROOT, "stage_artifacts", "WT_D20260528_003_overnight_C")

SIGNAL_CUTOFF <- as.Date("2023-12-22")
SIG_START     <- as.Date("2008-01-31")
TARGET_FACTORS <- c(
  "L44_Vol_Ret_Asymmetry",
  "L42_Vol_Skewness",
  "L33_AbsRet_Vol_Corr",
  "L13_Vol_Variance_Ratio"
)
SLEEVE_SIZE <- 5L

source(file.path(PROJ_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

cat("=== Alpha vector fix: ranked + named ===\n")

# Step 1: re-build alpha_scores with ranked sleeve scores
load_factor_panel <- function(sig_date) {
  sig_d <- as.Date(sig_date)
  ym_tag <- format(sig_d, "%Y%m")
  fpath <- file.path(".cache/factor_db", paste0("factor_db_", ym_tag, ".parquet"))
  if (!file.exists(fpath)) return(NULL)
  dt <- as.data.table(read_parquet(fpath))
  dt <- dt[Factor_Name %in% TARGET_FACTORS & Coverage == TRUE]
  if (nrow(dt) == 0) return(NULL)
  registry <- jsonlite::fromJSON("02_Infrastructure/factor_db/factor_registry.json")
  dt <- align_factor_direction(dt, registry, sig_date = sig_d)
  z_wide <- dcast(dt, Ticker + Date ~ Factor_Name, value.var = "Z_Score_Aligned")
  z_wide[, sig_date := sig_d]
  z_wide
}

all_parquets <- list.files(".cache/factor_db", pattern = "^factor_db_\\d{6}\\.parquet$")
ym_avail <- gsub("factor_db_(\\d{6})\\.parquet", "\\1", all_parquets)
ym_avail <- sort(ym_avail)
sig_date_candidates <- as.Date(paste0(substr(ym_avail, 1, 4), "-",
                                      substr(ym_avail, 5, 6), "-01"))
sig_date_candidates <- as.Date(format(sig_date_candidates + 35, "%Y-%m-01")) - 1
sig_dates <- sig_date_candidates[sig_date_candidates >= SIG_START &
                                 sig_date_candidates <= SIGNAL_CUTOFF]

cat(sprintf("Walk-forward: %d months\n", length(sig_dates)))

# Compute composite alpha as *sum of sleeve-aligned Z* (rank preserved + multi-sleeve bonus)
build_alpha_ranked <- function(panel) {
  if (is.null(panel) || nrow(panel) == 0) return(NULL)

  # For each sleeve, compute rank within sig_date (1 = best per sleeve)
  # Then select top 5 per sleeve, retain their Z values
  picks <- list()
  for (f in TARGET_FACTORS) {
    sub <- panel[!is.na(get(f))]
    if (nrow(sub) < SLEEVE_SIZE) next
    setorderv(sub, f, order = -1L)  # descending: higher = better
    sub_top <- sub[1:SLEEVE_SIZE]
    picks[[f]] <- sub_top[, .(Ticker, Z = get(f), sleeve = f, sleeve_rank = .I)]
  }
  if (length(picks) == 0) return(NULL)
  all_picks <- rbindlist(picks, fill = TRUE)

  # For each ticker: sum Z across sleeves where it appears (multi-sleeve bonus = additive)
  # Plus sleeves_in count for confidence
  agg <- all_picks[, .(
    alpha_raw   = sum(Z, na.rm = TRUE),     # additive composite score
    alpha_max_z = max(Z, na.rm = TRUE),     # max Z among sleeves it belongs to (tie-breaker)
    sleeves_in  = .N,
    sleeve_names = paste(unique(sleeve), collapse = ","),
    best_rank   = min(sleeve_rank, na.rm = TRUE)
  ), by = Ticker]

  # Cross-sectional standardize within sig_date
  agg[, alpha_z := scale(alpha_raw)[, 1]]
  agg[, sig_date := unique(panel$sig_date)]

  # Confidence: convex combination
  # sleeves_in / 4 (orthogonality) + (1 - (best_rank - 1)/SLEEVE_SIZE) (within-sleeve quality)
  agg[, confidence := pmin(1.0,
                           (sleeves_in / 4) * 0.5 +
                           (1 - (best_rank - 1) / SLEEVE_SIZE) * 0.5)]

  agg
}

cat("\n[Rebuild] Walk-forward alpha...\n")
all_alpha <- list()
for (i in seq_along(sig_dates)) {
  sd <- sig_dates[i]
  panel <- load_factor_panel(sd)
  if (is.null(panel)) next
  alpha <- build_alpha_ranked(panel)
  if (!is.null(alpha)) all_alpha[[length(all_alpha) + 1L]] <- alpha
}
alpha_scores <- rbindlist(all_alpha, fill = TRUE)

cat(sprintf("Alpha rows: %d | sig_dates: %d | unique tickers: %d\n",
            nrow(alpha_scores), uniqueN(alpha_scores$sig_date),
            uniqueN(alpha_scores$Ticker)))
cat("\nSleeves_in distribution:\n")
print(table(alpha_scores$sleeves_in))

cat("\nAlpha_z statistics:\n")
print(summary(alpha_scores$alpha_z))

# Overwrite alpha_scores.parquet
write_parquet(alpha_scores, file.path(OUT_STAGE, "alpha_scores.parquet"))
cat(sprintf("\n→ Saved (overwrite): %s/alpha_scores.parquet\n", OUT_STAGE))

# Final alpha vector at sig_date = SIGNAL_CUTOFF
final_sig <- max(alpha_scores$sig_date)
final_alpha <- alpha_scores[sig_date == final_sig]
setorder(final_alpha, -alpha_z)

cat(sprintf("\nFinal alpha at sig_date = %s (Top 20):\n", final_sig))
print(head(final_alpha[, .(Ticker, alpha_z, alpha_raw, sleeves_in, sleeve_names, confidence)], 20))

cat(sprintf("\nUnique alpha_z (final): %d / %d total\n",
            uniqueN(round(final_alpha$alpha_z, 6)), nrow(final_alpha)))

#==============================================================================
# Re-emit alpha_package_draft_C.json with NAMED alpha_vector + confidence_vector
#==============================================================================

# Load existing draft for non-alpha fields
draft_existing <- fromJSON(file.path(OUT_MAILBOX, "alpha_package_draft_C.json"),
                          simplifyVector = FALSE)

# Build NAMED lists — jsonlite needs proper structure
alpha_vector_named <- as.list(round(final_alpha$alpha_z, 4))
names(alpha_vector_named) <- final_alpha$Ticker

confidence_vector_named <- as.list(round(final_alpha$confidence, 3))
names(confidence_vector_named) <- final_alpha$Ticker

# Replace in draft
draft_existing$alpha_vector <- alpha_vector_named
draft_existing$confidence_vector <- confidence_vector_named

# Update diagnostics — recompute alpha summary
draft_existing$build_metadata$alpha_vector_fix_applied <- TRUE
draft_existing$build_metadata$alpha_vector_fix_timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
draft_existing$build_metadata$alpha_vector_method <- "additive composite (sum of sleeve-aligned Z, cross-sectional z-score). sleeves_in distribution preserves multi-sleeve overlap."

# Add sleeve overlap statistics
sleeve_overlap_stats <- alpha_scores[, .(
  avg_sleeves_in = mean(sleeves_in),
  max_sleeves_in = max(sleeves_in),
  pct_multi_sleeve = mean(sleeves_in >= 2) * 100,
  avg_union_size = mean(.N),
  ratio_union_vs_max = mean(.N) / 20
), by = sig_date]
sleeve_overall <- sleeve_overlap_stats[, .(
  avg_union_size_overall = round(mean(avg_union_size), 1),
  avg_sleeves_in_overall = round(mean(avg_sleeves_in), 3),
  pct_multi_sleeve_overall = round(mean(pct_multi_sleeve), 2)
)]
cat("\nSleeve overlap statistics (walk-forward):\n")
print(sleeve_overall)

draft_existing$diagnostics$avg_union_size <- sleeve_overall$avg_union_size_overall
draft_existing$diagnostics$avg_sleeves_per_ticker <- sleeve_overall$avg_sleeves_in_overall
draft_existing$diagnostics$pct_multi_sleeve <- sleeve_overall$pct_multi_sleeve_overall

# Re-save
write_json(draft_existing, file.path(OUT_MAILBOX, "alpha_package_draft_C.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("\n→ Saved (rewrite): %s/alpha_package_draft_C.json\n", OUT_MAILBOX))

cat("\n=== Fix complete. Alpha vector now named + ranked. ===\n")
