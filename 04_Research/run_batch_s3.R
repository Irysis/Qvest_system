## Batch S3 Orthogonality Analysis — 3 strategies
## STR_1473, STR_1476, STR_1477
## Scout: 2026-03-26

cat("=== Batch S3 Orthogonality Analysis ===\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
INFRA_DIR <- file.path(PROJECT_ROOT, "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

LIQ_THRESHOLD <- 2e8

# ---- Load RAWDATA once ----
cat("[Batch] Loading RAWDATA...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT

# ---- Helper: inline S3 orthogonality ----
run_s3 <- function(strat_id, factor_id, component_factors) {
  cat(sprintf("\n======== S3: %s (%s) ========\n", strat_id, factor_id))

  strat_dir <- file.path(PROJECT_ROOT, "research_output", "strategies", strat_id)
  art_dir <- file.path(strat_dir, "stage_artifacts")

  # Run factor_engine
  cat("[S3] Running factor_engine.R...\n")
  fe_path <- file.path(strat_dir, "factor_engine.R")
  if (!file.exists(fe_path)) { cat("[S3] ERROR: factor_engine.R not found\n"); return(NULL) }
  source(fe_path)

  # Latest signal
  latest_date <- max(FACTORS$Date)
  latest_scores <- FACTORS[Date == latest_date, .(Ticker, Score)]
  new_factor_z <- setNames(latest_scores$Score, latest_scores$Ticker)
  cat(sprintf("[S3] Latest: %s | N stocks: %d\n", latest_date, length(new_factor_z)))

  # Load DB factors
  fdt <- load_month_factors(latest_date, coverage_min = 0.01)
  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  new_dt <- data.table(Ticker = names(new_factor_z), New_Z = as.numeric(new_factor_z))
  merged <- merge(fdt_wide, new_dt, by = "Ticker")
  cat(sprintf("[S3] Merged: %d stocks\n", nrow(merged)))

  # Exclude component factors
  factor_cols <- setdiff(names(merged), c("Ticker", "New_Z", component_factors))
  cat(sprintf("[S3] Excluding: %s | Comparing %d factors\n",
              paste(component_factors, collapse=", "), length(factor_cols)))

  # Pairwise Spearman
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

  cat(sprintf("[S3] max_abs_corr: %.3f (vs %s)\n", max_corr, max_factor))
  cat(sprintf("[S3] independence: %s\n", independence))
  cat("[S3] Top 5:\n")
  for (j in 1:min(5, nrow(top10))) {
    cat(sprintf("  %d. %s: %.3f\n", j, top10$Factor_Name[j], top10$Corr[j]))
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
    fc_d <- setdiff(names(m_d), c("Ticker", "New_Z", component_factors))
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

  # Component inter-correlation
  comp_intercorr <- list()
  if (length(component_factors) >= 2) {
    for (i in 1:(length(component_factors)-1)) {
      for (k in (i+1):length(component_factors)) {
        f1 <- component_factors[i]; f2 <- component_factors[k]
        if (f1 %in% names(merged) && f2 %in% names(merged)) {
          v <- !is.na(merged[[f1]]) & !is.na(merged[[f2]])
          if (sum(v) >= 20) {
            key <- paste0(gsub("_.*", "", f1), "_x_", gsub("_.*", "", f2))
            comp_intercorr[[key]] <- round(cor(merged[[f1]][v], merged[[f2]][v],
                                               method = "spearman"), 3)
          }
        }
      }
    }
  }

  # Component max_corrs
  comp_max_corrs <- list()
  for (cf in component_factors) {
    if (cf %in% names(fdt_wide)) {
      cf_vec <- merged[[cf]]
      if (!all(is.na(cf_vec))) {
        cf_corrs <- sapply(factor_cols, function(fc) {
          v <- !is.na(merged[[fc]]) & !is.na(cf_vec)
          if (sum(v) < 20) return(NA_real_)
          cor(merged[[fc]][v], cf_vec[v], method = "spearman")
        })
        cf_corrs <- cf_corrs[!is.na(cf_corrs)]
        top5_cf <- sort(abs(cf_corrs), decreasing = TRUE)[1:min(5, length(cf_corrs))]
        comp_max_corrs[[cf]] <- as.list(setNames(
          round(cf_corrs[names(top5_cf)], 3),
          paste0("vs_", names(top5_cf))
        ))
      }
    }
  }

  # Save artifact
  s3 <- list(
    factor_id = factor_id,
    strategy_id = strat_id,
    components = as.list(component_factors),
    component_intercorr = comp_intercorr,
    max_abs_corr_db = round(max_corr, 4),
    most_correlated_factor = max_factor,
    component_max_corrs = comp_max_corrs,
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
      "max_abs_corr %.3f(vs %s). Independence: %s. Multi-date avg: %.3f. N stocks: %d.",
      max_corr, max_factor, independence, avg_corr, length(new_factor_z)
    )
  )

  s3_path <- file.path(art_dir, sprintf("s3_orthogonality_%s.json", factor_id))
  jsonlite::write_json(s3, s3_path, auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf("[S3] Artifact saved: %s\n", basename(s3_path)))

  list(strat_id = strat_id, factor_id = factor_id,
       max_corr = max_corr, max_factor = max_factor, independence = independence)
}

# ---- Run all 3 ----
r1 <- run_s3("STR_1473_vol_concentration_alpha", "MF12_VolConcentration", "L31_Vol_Concentration")
r2 <- run_s3("STR_1476_net_margin_alpha", "MF15_NetMarginAlpha", "Q11_Net_Margin")
r3 <- run_s3("STR_1477_profitability_liquidity_cross", "MF16_ProfitLiqCross",
             c("Q11_Net_Margin", "L31_Vol_Concentration"))

# ---- Summary ----
cat("\n\n========== S3 BATCH SUMMARY ==========\n")
for (r in list(r1, r2, r3)) {
  if (!is.null(r)) {
    cat(sprintf("  %s | %s | max_corr: %.3f (vs %s) | %s\n",
                r$strat_id, r$factor_id, r$max_corr, r$max_factor, r$independence))
  }
}
cat("=======================================\n")
