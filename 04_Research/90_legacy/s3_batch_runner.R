cat("=== S3 Batch Orthogonality Analysis (direct impl) ===\n")
cat("=== STR_1426~1432: Scout S3 직교성 분석 ===\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

# ---- Config ----
source(file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "02_Infrastructure/config.R"))
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

sig_date <- as.Date("2026-02-28")

# ---- Load factor data ONCE ----
cat("[1/4] Loading Factor DB for sig_date =", as.character(sig_date), "...\n")
fdt <- load_month_factors(sig_date, coverage_min = 0.01)
n_factors <- uniqueN(fdt$Factor_Name)
n_tickers <- uniqueN(fdt$Ticker)
cat("  Loaded:", n_factors, "factors,", n_tickers, "tickers\n")

# Pivot to wide: Ticker x Factor
cat("  Pivoting to wide format...\n")
fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
factor_cols <- setdiff(names(fdt_wide), "Ticker")
cat("  Wide matrix:", nrow(fdt_wide), "tickers x", length(factor_cols), "factors\n\n")

# ---- Direct S3 implementation (avoids Korean path JSON issue) ----
run_s3 <- function(new_z_vec, factor_label, fdt_wide_mat, factor_cols_vec) {
  # new_z_vec: named numeric (Ticker -> z)
  new_dt <- data.table(Ticker = names(new_z_vec), New_Z = as.numeric(new_z_vec))
  merged <- merge(fdt_wide_mat, new_dt, by = "Ticker")

  if(nrow(merged) < 30) {
    cat("  WARNING:", factor_label, "< 30 merged tickers\n")
    return(NULL)
  }

  # Spearman correlation with each existing factor
  corr_list <- lapply(factor_cols_vec, function(fc) {
    x <- merged[[fc]]
    y <- merged$New_Z
    valid <- !is.na(x) & !is.na(y)
    if(sum(valid) < 20) return(data.table(Factor_Name = fc, Corr = NA_real_))
    data.table(Factor_Name = fc, Corr = cor(x[valid], y[valid], method = "spearman"))
  })
  pairwise <- rbindlist(corr_list)[!is.na(Corr)]

  if(nrow(pairwise) == 0) return(NULL)

  # Remove self if single factor
  if(factor_label %in% pairwise$Factor_Name) {
    pairwise <- pairwise[Factor_Name != factor_label]
  }

  if(nrow(pairwise) == 0) return(NULL)

  max_idx <- which.max(abs(pairwise$Corr))
  max_corr <- abs(pairwise$Corr[max_idx])
  max_factor <- pairwise$Factor_Name[max_idx]
  independence <- if(max_corr < 0.3) "independent"
                  else if(max_corr < 0.6) "partial"
                  else "redundant"

  # Category summary
  pairwise[, Category := gsub("^([A-Z]+)\\d+.*", "\\1", Factor_Name)]
  cat_corr <- pairwise[, .(Max_Corr = max(abs(Corr), na.rm=TRUE)), by=Category][order(-Max_Corr)]

  list(
    pairwise_corr = pairwise,
    max_corr = max_corr,
    max_corr_factor = max_factor,
    independence = independence,
    n_compared = nrow(pairwise),
    category_corr = cat_corr
  )
}

# ---- S3 specs ----
s3_tasks <- list(
  list(id = "STR_1426", factors = "Q07_Earnings_Stability", type = "single",
       s2_tag = "Weak", sr = 0.362),
  list(id = "STR_1427", factors = "R18_Book_Leverage", type = "single",
       s2_tag = "Weak", sr = 0.217),
  list(id = "STR_1428", factors = "AC21_CF_to_Accrual_Ratio", type = "single",
       s2_tag = "Moderate", sr = 0.543),
  list(id = "STR_1429", factors = c("V02_EP", "AC21_CF_to_Accrual_Ratio"), type = "combo",
       s2_tag = "Moderate", sr = 0.797),
  list(id = "STR_1430", factors = c("V14_EBIT_EV", "Q11_Net_Margin"), type = "combo",
       s2_tag = "Moderate", sr = 0.886),
  list(id = "STR_1431", factors = c("Q28_Cash_Conversion", "C19_Composite_Earnings"), type = "combo",
       s2_tag = "Moderate", sr = 0.768),
  list(id = "STR_1432", factors = c("Q01_ROE", "Q07_Earnings_Stability", "C04_ESBR", "D01_IdioVol"),
       type = "combo", s2_tag = "Weak", sr = 0.568)
)

# ---- Execute ----
cat("[2/4] Running S3 orthogonality for 7 strategies...\n\n")
results <- list()

for(task in s3_tasks) {
  cat("[S3]", task$id, "-", paste(task$factors, collapse="+"), "\n")

  tryCatch({
    if(task$type == "single") {
      # Single factor: use its z-scores directly
      sub <- fdt[Factor_Name == task$factors]
      new_z <- setNames(sub$Z_Score_Aligned, sub$Ticker)
      new_z <- new_z[!is.na(new_z)]
      label <- task$factors
    } else {
      # Composite: EW average of z-scores
      sub <- fdt[Factor_Name %in% task$factors]
      wide_sub <- dcast(sub, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
      fcols <- setdiff(names(wide_sub), "Ticker")
      wide_sub[, composite_z := rowMeans(.SD, na.rm = TRUE), .SDcols = fcols]
      valid <- wide_sub[!is.na(composite_z)]
      new_z <- setNames(valid$composite_z, valid$Ticker)
      label <- paste(task$factors, collapse = "+")
    }

    cat("  N tickers:", length(new_z), "\n")
    res <- run_s3(new_z, if(task$type == "single") task$factors else "", fdt_wide, factor_cols)

    if(!is.null(res)) {
      cat("  max_abs_corr:", round(res$max_corr, 3),
          "| most_corr:", res$max_corr_factor,
          "| independence:", res$independence,
          "| n_compared:", res$n_compared, "\n")
      top5 <- res$pairwise_corr[order(-abs(Corr))][1:min(5,.N)]
      cat("  Top 5:\n")
      for(i in seq_len(nrow(top5))) {
        cat("    ", top5$Factor_Name[i], ":", round(top5$Corr[i], 3), "\n")
      }
      cat("  Categories:\n")
      for(i in seq_len(min(5, nrow(res$category_corr)))) {
        cat("    ", res$category_corr$Category[i], ":",
            round(res$category_corr$Max_Corr[i], 3), "\n")
      }
    } else {
      cat("  FAILED: insufficient data\n")
    }
    results[[task$id]] <- res
    cat("\n")
  }, error = function(e) {
    cat("  ERROR:", conditionMessage(e), "\n\n")
    results[[task$id]] <<- NULL
  })
}

# ---- Save S3 artifacts ----
cat("[3/4] Saving S3 artifacts...\n")

strat_base <- file.path(PROJECT_ROOT, "research_output", "strategies")

for(task in s3_tasks) {
  res <- results[[task$id]]
  if(is.null(res)) next

  cell <- paste0(task$s2_tag, "_", tools::toTitleCase(res$independence))

  artifact <- list(
    factor_id = paste(task$factors, collapse = "+"),
    strategy_id = task$id,
    max_abs_corr_db = round(res$max_corr, 4),
    most_correlated_factor = res$max_corr_factor,
    independence_class = res$independence,
    value_matrix_cell = cell,
    n_compared = res$n_compared,
    computed_date = as.character(Sys.Date()),
    top5_correlated = lapply(
      seq_len(min(5, nrow(res$pairwise_corr[order(-abs(Corr))]))),
      function(i) {
        d <- res$pairwise_corr[order(-abs(Corr))][i]
        list(factor = d$Factor_Name, corr = round(d$Corr, 4))
      }
    )
  )

  strat_dirs <- list.dirs(strat_base, recursive = FALSE, full.names = TRUE)
  matches <- strat_dirs[grepl(paste0(task$id, "_"), basename(strat_dirs))]
  if(length(matches) > 0) {
    art_dir <- file.path(matches[1], "stage_artifacts")
    if(!dir.exists(art_dir)) dir.create(art_dir, recursive = TRUE)
    fpath <- file.path(art_dir, paste0("s3_orthogonality_", task$id, ".json"))
    writeLines(toJSON(artifact, auto_unbox = TRUE, pretty = TRUE), fpath)
    cat("  Saved:", basename(matches[1]), "/", basename(fpath), "\n")
  } else {
    cat("  WARNING: No dir for", task$id, "\n")
  }
}

# ---- Summary Table ----
cat("\n[4/4] === S3 SUMMARY ===\n")
cat(sprintf("%-10s %-6s %-35s %-12s %-7s %-25s %-20s\n",
            "STR", "SR", "Factor(s)", "Independence", "MaxCorr", "MostCorr", "Cell"))
cat(strrep("-", 120), "\n")
for(task in s3_tasks) {
  res <- results[[task$id]]
  if(!is.null(res)) {
    cell <- paste0(task$s2_tag, "_", tools::toTitleCase(res$independence))
    cat(sprintf("%-10s %-6s %-35s %-12s %-7s %-25s %-20s\n",
                task$id, round(task$sr, 3),
                substr(paste(task$factors, collapse="+"), 1, 35),
                res$independence, round(res$max_corr, 3),
                res$max_corr_factor, cell))
  } else {
    cat(sprintf("%-10s %-6s %-35s FAILED\n",
                task$id, round(task$sr, 3),
                paste(task$factors, collapse="+")))
  }
}

cat("\n=== S3 Batch Complete ===\n")
