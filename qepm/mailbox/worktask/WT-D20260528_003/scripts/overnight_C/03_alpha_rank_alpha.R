#==============================================================================
# WT-D20260528_003 / hypothesis_C — Alpha v3: Rank-based composite alpha
#
# Root cause of v2 issue:
#   Factor DB Z_Score winsorize cap at ~3 std → top 5 per sleeve all hit cap → identical Z_Aligned
#   This loses intra-sleeve rank information. Solution: use Raw_Value rank instead.
#
# v3 design:
#   1. Per sleeve, rank by Raw_Value (direction-aware: ic_sign * Raw_Value)
#   2. Take top 5 per sleeve. Sleeve_rank ∈ {1, 2, 3, 4, 5} → score = (5 + 1 - rank) / 5 ∈ {1.0, 0.8, 0.6, 0.4, 0.2}
#   3. Multi-sleeve overlap: sum of sleeve_scores (max 4 if in all 4 sleeves at rank 1)
#   4. Cross-sectional z-score for final alpha_z
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

cat("=== Alpha v3: rank-based composite ===\n")

# Load registry once (to get IC sign per factor via expanding window per sig_date)
registry <- jsonlite::fromJSON("02_Infrastructure/factor_db/factor_registry.json")
ic_hist <- as.data.table(read_parquet(".cache/factor_db/factor_ic_monthly.parquet"))
ic_hist[, Usable_Date := as.Date(Usable_Date)]
ic_hist[, Date := as.Date(Date)]
ic_hist <- ic_hist[Factor_Name %in% TARGET_FACTORS]

#------------------------------------------------------------------------------
# Helper: PIT-safe ic_sign at sig_date (mirrors align_factor_direction logic)
#------------------------------------------------------------------------------
get_ic_sign_at <- function(sig_date, factor_name, min_months = 36L) {
  ic_sub <- ic_hist[Factor_Name == factor_name & Usable_Date <= sig_date]
  if (nrow(ic_sub) >= min_months) {
    m <- mean(ic_sub$IC, na.rm = TRUE)
    if (m > 0) return(1L) else return(-1L)
  }
  # Fallback to registry direction
  reg_dir <- registry[[factor_name]]$direction %||% "higher_better"
  if (reg_dir == "lower_better") return(-1L) else return(1L)
}

#------------------------------------------------------------------------------
# Build sleeve-rank-based alpha
#------------------------------------------------------------------------------
load_factor_panel_raw <- function(sig_date) {
  sig_d <- as.Date(sig_date)
  ym_tag <- format(sig_d, "%Y%m")
  fpath <- file.path(".cache/factor_db", paste0("factor_db_", ym_tag, ".parquet"))
  if (!file.exists(fpath)) return(NULL)
  dt <- as.data.table(read_parquet(fpath))
  dt <- dt[Factor_Name %in% TARGET_FACTORS & Coverage == TRUE]
  if (nrow(dt) == 0) return(NULL)
  dt[, sig_date := sig_d]
  dt
}

build_alpha_v3 <- function(panel) {
  if (is.null(panel) || nrow(panel) == 0) return(NULL)
  sd <- unique(panel$sig_date)[1]

  picks <- list()
  for (f in TARGET_FACTORS) {
    sub <- panel[Factor_Name == f & !is.na(Raw_Value)]
    if (nrow(sub) < SLEEVE_SIZE) next

    ic_sign <- get_ic_sign_at(sd, f)
    # Rank by ic_sign * Raw_Value descending: higher = better post-alignment
    # Use frank with ties.method = "min" for robust rank
    sub[, aligned_value := ic_sign * Raw_Value]
    setorder(sub, -aligned_value)
    sub_top <- sub[1:SLEEVE_SIZE]
    sub_top[, sleeve_rank := seq_len(.N)]
    sub_top[, sleeve_score := (SLEEVE_SIZE + 1L - sleeve_rank) / SLEEVE_SIZE]  # 1.0, 0.8, 0.6, 0.4, 0.2
    picks[[f]] <- sub_top[, .(Ticker, sleeve = f, sleeve_rank, sleeve_score, aligned_value)]
  }
  if (length(picks) == 0) return(NULL)

  all_picks <- rbindlist(picks, fill = TRUE)

  # Aggregate per ticker — sum sleeve_score across all sleeves it appears in
  agg <- all_picks[, .(
    alpha_raw    = sum(sleeve_score, na.rm = TRUE),
    sleeves_in   = .N,
    sleeve_names = paste(unique(sleeve), collapse = ","),
    best_rank    = min(sleeve_rank, na.rm = TRUE),
    avg_rank     = mean(sleeve_rank, na.rm = TRUE)
  ), by = Ticker]
  agg[, sig_date := sd]

  # Cross-sectional z within sig_date (mean=0, sd=1)
  if (nrow(agg) >= 2 && sd(agg$alpha_raw) > 0) {
    agg[, alpha_z := scale(alpha_raw)[, 1]]
  } else {
    agg[, alpha_z := 0]
  }

  # Confidence: weighted by sleeves_in + best_rank
  agg[, confidence := pmin(1.0, (sleeves_in / 4) * 0.5 + (SLEEVE_SIZE + 1L - best_rank) / SLEEVE_SIZE * 0.5)]

  agg[]
}

# Walk-forward
all_parquets <- list.files(".cache/factor_db", pattern = "^factor_db_\\d{6}\\.parquet$")
ym_avail <- gsub("factor_db_(\\d{6})\\.parquet", "\\1", all_parquets)
ym_avail <- sort(ym_avail)
sig_date_candidates <- as.Date(paste0(substr(ym_avail, 1, 4), "-",
                                      substr(ym_avail, 5, 6), "-01"))
sig_date_candidates <- as.Date(format(sig_date_candidates + 35, "%Y-%m-01")) - 1
sig_dates <- sig_date_candidates[sig_date_candidates >= SIG_START &
                                 sig_date_candidates <= SIGNAL_CUTOFF]

cat(sprintf("\n[Walk-forward v3] %d months\n", length(sig_dates)))

t0 <- Sys.time()
all_alpha <- list()
for (i in seq_along(sig_dates)) {
  sd <- sig_dates[i]
  panel <- load_factor_panel_raw(sd)
  if (is.null(panel)) next
  alpha <- build_alpha_v3(panel)
  if (!is.null(alpha)) all_alpha[[length(all_alpha) + 1L]] <- alpha
}
t1 <- Sys.time()
cat(sprintf("Done in %.1fs\n", as.numeric(t1 - t0, units = "secs")))

alpha_scores <- rbindlist(all_alpha, fill = TRUE)
cat(sprintf("Alpha rows: %d | sig_dates: %d | unique tickers: %d\n",
            nrow(alpha_scores), uniqueN(alpha_scores$sig_date),
            uniqueN(alpha_scores$Ticker)))
cat("\nSleeves_in distribution:\n")
print(table(alpha_scores$sleeves_in))
cat("\nAlpha_z summary:\n")
print(summary(alpha_scores$alpha_z))
cat("\nUnique alpha_z values (rounded 6 dp):\n")
cat(uniqueN(round(alpha_scores$alpha_z, 6)), "\n")

# Final alpha at cutoff
final_sig <- max(alpha_scores$sig_date)
final_alpha <- alpha_scores[sig_date == final_sig]
setorder(final_alpha, -alpha_z)

cat(sprintf("\nFinal alpha at sig_date = %s (Top 20):\n", final_sig))
print(head(final_alpha[, .(Ticker, alpha_z, alpha_raw, sleeves_in, sleeve_names, best_rank, confidence)], 20))

cat(sprintf("\nUnique alpha_z (final): %d / %d total\n",
            uniqueN(round(final_alpha$alpha_z, 6)), nrow(final_alpha)))

# Overwrite
write_parquet(alpha_scores, file.path(OUT_STAGE, "alpha_scores.parquet"))
cat(sprintf("\n→ Saved (overwrite): %s/alpha_scores.parquet\n", OUT_STAGE))

#==============================================================================
# Rewrite draft with v3 alpha + diagnostics
#==============================================================================

draft_existing <- fromJSON(file.path(OUT_MAILBOX, "alpha_package_draft_C.json"),
                          simplifyVector = FALSE)

# NAMED named lists
alpha_vector_named <- as.list(round(final_alpha$alpha_z, 4))
names(alpha_vector_named) <- final_alpha$Ticker

confidence_vector_named <- as.list(round(final_alpha$confidence, 3))
names(confidence_vector_named) <- final_alpha$Ticker

draft_existing$alpha_vector <- alpha_vector_named
draft_existing$confidence_vector <- confidence_vector_named

# Update method description
draft_existing$build_metadata$alpha_vector_method <- paste0(
  "v3 rank-based composite: per sleeve f, rank tickers by ic_sign(f, sig_date) * Raw_Value descending. ",
  "Top 5 receive sleeve_score = (6 - rank)/5 ∈ {1.0, 0.8, 0.6, 0.4, 0.2}. ",
  "alpha_raw = sum(sleeve_score) across sleeves a ticker appears in (max 4.0 if rank 1 in all 4 sleeves). ",
  "Cross-sectional z-score within sig_date. ",
  "Confidence = 0.5*(sleeves_in/4) + 0.5*((6 - best_rank)/5). ",
  "PIT-safe: ic_sign computed from Usable_Date <= sig_date expanding window with min_months=36 burn-in, ",
  "registry direction fallback if insufficient IC history."
)
draft_existing$build_metadata$alpha_v3_timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# Update sleeve overlap stats
sleeve_stats <- alpha_scores[, .(union_n = .N, mean_sleeves_in = mean(sleeves_in),
                                 pct_multi = mean(sleeves_in >= 2) * 100), by = sig_date]
sleeve_summary <- sleeve_stats[, .(
  avg_union_size = round(mean(union_n), 2),
  avg_sleeves_in = round(mean(mean_sleeves_in), 3),
  pct_multi_sleeve_overall = round(mean(pct_multi), 2)
)]
cat("\nSleeve overlap (walk-forward avg):\n")
print(sleeve_summary)

draft_existing$diagnostics$avg_union_size <- sleeve_summary$avg_union_size
draft_existing$diagnostics$avg_sleeves_per_ticker <- sleeve_summary$avg_sleeves_in
draft_existing$diagnostics$pct_multi_sleeve <- sleeve_summary$pct_multi_sleeve_overall
draft_existing$diagnostics$unique_alpha_values_final <- uniqueN(round(final_alpha$alpha_z, 6))

# Save
write_json(draft_existing, file.path(OUT_MAILBOX, "alpha_package_draft_C.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("\n→ Rewrite: %s\n", file.path(OUT_MAILBOX, "alpha_package_draft_C.json")))

cat("\n=== v3 fix complete ===\n")
