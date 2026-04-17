## S3 Orthogonality: STR_1478_info_discreteness_momentum (MF17_InfoDiscreteness)
cat("=== S3: STR_1478 (MF17_InfoDiscreteness) ===\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
INFRA_DIR <- file.path(PROJECT_ROOT, "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
LIQ_THRESHOLD <- 2e8

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT

strat_dir <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1478_info_discreteness_momentum")
source(file.path(strat_dir, "factor_engine.R"))

COMPONENT_FACTORS <- c("M07_IndMom")
latest_date <- max(FACTORS$Date)
latest_scores <- FACTORS[Date == latest_date, .(Ticker, Score)]
new_factor_z <- setNames(latest_scores$Score, latest_scores$Ticker)
cat(sprintf("[S3] Latest: %s | N stocks: %d\n", latest_date, length(new_factor_z)))

fdt <- load_month_factors(latest_date, coverage_min = 0.01)
fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
new_dt <- data.table(Ticker = names(new_factor_z), New_Z = as.numeric(new_factor_z))
merged <- merge(fdt_wide, new_dt, by = "Ticker")
factor_cols <- setdiff(names(merged), c("Ticker", "New_Z", COMPONENT_FACTORS))
cat(sprintf("[S3] Merged: %d | Excluding: %s | Comparing %d factors\n",
            nrow(merged), paste(COMPONENT_FACTORS, collapse=","), length(factor_cols)))

corr_list <- lapply(factor_cols, function(fc) {
  valid <- !is.na(merged[[fc]]) & !is.na(merged$New_Z)
  if (sum(valid) < 20) return(data.table(Factor_Name = fc, Corr = NA_real_))
  data.table(Factor_Name = fc,
             Corr = cor(merged[[fc]][valid], merged$New_Z[valid], method = "spearman"))
})
pairwise <- rbindlist(corr_list)
pairwise <- pairwise[!is.na(Corr)]

max_idx <- which.max(abs(pairwise$Corr))
max_corr <- abs(pairwise$Corr[max_idx])
max_factor <- pairwise$Factor_Name[max_idx]
independence <- ifelse(max_corr < 0.3, "independent",
                       ifelse(max_corr < 0.6, "partial", "redundant"))

pairwise[, Category := gsub("^([A-Z]+)\\d+.*", "\\1", Factor_Name)]
cat_corr <- pairwise[, .(Max_Corr = max(abs(Corr), na.rm = TRUE)), by = Category]
setorder(cat_corr, -Max_Corr)

top10 <- pairwise[order(-abs(Corr))][1:min(10, nrow(pairwise))]
cat(sprintf("[S3] max_abs_corr: %.3f (vs %s) | independence: %s\n",
            max_corr, max_factor, independence))
cat("[S3] Top 10:\n")
for (j in seq_len(nrow(top10))) {
  cat(sprintf("  %2d. %s: %.3f\n", j, top10$Factor_Name[j], top10$Corr[j]))
}

# Multi-date (3 months)
all_dates <- sort(unique(FACTORS$Date), decreasing = TRUE)
check_dates <- all_dates[seq_len(min(3, length(all_dates)))]
multi_results <- lapply(check_dates, function(d) {
  scores_d <- FACTORS[Date == d, .(Ticker, Score)]
  z_d <- setNames(scores_d$Score, scores_d$Ticker)
  if (length(z_d) < 30) return(NULL)
  fdt_d <- tryCatch(load_month_factors(d, coverage_min = 0.01), error = function(e) NULL)
  if (is.null(fdt_d)) return(NULL)
  fdt_w <- dcast(fdt_d, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  new_d <- data.table(Ticker = names(z_d), New_Z = as.numeric(z_d))
  m_d <- merge(fdt_w, new_d, by = "Ticker")
  if (nrow(m_d) < 30) return(NULL)
  fc_d <- setdiff(names(m_d), c("Ticker", "New_Z", COMPONENT_FACTORS))
  corrs_d <- sapply(fc_d, function(fc) {
    v <- !is.na(m_d[[fc]]) & !is.na(m_d$New_Z)
    if (sum(v) < 20) return(NA_real_)
    cor(m_d[[fc]][v], m_d$New_Z[v], method = "spearman")
  })
  corrs_d <- corrs_d[!is.na(corrs_d)]
  if (length(corrs_d) == 0) return(NULL)
  mx <- which.max(abs(corrs_d))
  data.table(Date = d, max_corr = abs(corrs_d[mx]), max_factor = names(corrs_d)[mx])
})
multi_dt <- rbindlist(multi_results[!sapply(multi_results, is.null)])
avg_corr <- ifelse(nrow(multi_dt) > 0, mean(multi_dt$max_corr), max_corr)

# Save artifact
s3 <- list(
  factor_id = "MF17_InfoDiscreteness",
  strategy_id = "STR_1478",
  components = as.list(COMPONENT_FACTORS),
  max_abs_corr_db = round(max_corr, 4),
  most_correlated_factor = max_factor,
  top5_corr = as.list(setNames(
    round(top10$Corr[1:min(5, nrow(top10))], 4),
    top10$Factor_Name[1:min(5, nrow(top10))]
  )),
  category_max_corr = as.list(setNames(round(cat_corr$Max_Corr, 4), cat_corr$Category)),
  independence_class = independence,
  value_matrix_cell = paste0(
    ifelse(max_corr < 0.3, "Independent", ifelse(max_corr < 0.6, "Partial", "Redundant")),
    "_S2"
  ),
  n_compared = nrow(pairwise),
  n_months_analyzed = nrow(multi_dt),
  avg_max_corr_multidate = round(avg_corr, 4),
  computed_date = as.character(Sys.Date()),
  scout_note = sprintf(
    "MF17_InfoDiscreteness uses M07_IndMom with info discreteness filtering. max_abs_corr %.3f(vs %s). Independence: %s. Multi-date avg: %.3f.",
    max_corr, max_factor, independence, avg_corr
  )
)

art_dir <- file.path(strat_dir, "stage_artifacts")
s3_path <- file.path(art_dir, "s3_orthogonality_MF17_InfoDiscreteness.json")
jsonlite::write_json(s3, s3_path, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[S3] Artifact saved: %s\n", s3_path))
cat(sprintf("\n[Scout] S3 complete: %s | %.3f | %s\n", max_factor, max_corr, independence))
