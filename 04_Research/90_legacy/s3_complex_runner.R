cat("=== S3 Complex Strategy Orthogonality ===\n")
cat("=== STR_1433, STR_1434, STR_1439 ===\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(xts)
})

source(file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "02_Infrastructure/config.R"))
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

STRAT_BASE <- file.path(PROJECT_ROOT, "research_output", "strategies")
sig_date <- as.Date("2026-02-28")

# ---- Load Factor DB (single load) ----
cat("[1/4] Loading Factor DB...\n")
fdt <- load_month_factors(sig_date, coverage_min = 0.01)
fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
factor_cols <- setdiff(names(fdt_wide), "Ticker")
cat("  ", length(factor_cols), "factors x", nrow(fdt_wide), "tickers\n\n")

# ---- Extract portfolio z-scores from sim_result ----
extract_portfolio_z <- function(sim_path, strategy_id) {
  cat("[Load]", strategy_id, "sim_result.rds...\n")
  sim <- readRDS(sim_path)

  # sim_result typically has $holdings (list of data.tables per rebalance)
  # or $portfolio_weights or similar
  holdings <- NULL

  if (!is.null(sim$holdings)) {
    # Get last 3 rebalance dates' holdings
    n <- length(sim$holdings)
    last_few <- sim$holdings[max(1, n-2):n]
    holdings <- rbindlist(last_few, fill = TRUE)
  } else if (!is.null(sim$weight_history)) {
    wh <- sim$weight_history
    n <- length(wh)
    last_few <- wh[max(1, n-2):n]
    holdings <- rbindlist(last_few, fill = TRUE)
  }

  if (is.null(holdings) || nrow(holdings) == 0) {
    # Try extracting from the sim object structure
    nms <- names(sim)
    cat("  sim_result names:", paste(nms, collapse=", "), "\n")

    # Check for selected_stocks or portfolio
    for (nm in c("selected_stocks", "portfolio", "tickers", "selected")) {
      if (nm %in% nms) {
        obj <- sim[[nm]]
        if (is.character(obj)) {
          holdings <- data.table(Ticker = obj)
          break
        } else if (is.data.table(obj) || is.data.frame(obj)) {
          holdings <- as.data.table(obj)
          break
        }
      }
    }
  }

  if (is.null(holdings) || nrow(holdings) == 0) {
    cat("  WARNING: Cannot extract holdings. Trying alternative approach.\n")
    # Use strategy returns correlation with factor returns as proxy
    return(NULL)
  }

  # Get unique tickers
  if ("Ticker" %in% names(holdings)) {
    tickers <- unique(holdings$Ticker)
  } else {
    first_col <- names(holdings)[1]
    tickers <- unique(holdings[[first_col]])
  }

  cat("  Extracted", length(tickers), "unique tickers\n")
  tickers
}

# ---- Alternative: correlate strategy RETURNS with factor quintile returns ----
extract_strategy_returns_profile <- function(sim_path, strategy_id, fdt_cache, fdt_wide_cache, factor_cols_vec) {
  cat("[Profile]", strategy_id, "- return-based factor exposure...\n")
  sim <- readRDS(sim_path)

  # Get strategy daily returns
  strat_xts <- sim$strategy_xts
  if (is.null(strat_xts)) {
    cat("  No strategy_xts found\n")
    return(NULL)
  }

  # Convert to monthly
  ep <- endpoints(strat_xts, "months")
  strat_monthly <- period.apply(strat_xts, ep, function(x) prod(1 + x) - 1)
  strat_ret <- data.table(
    YM = format(index(strat_monthly), "%Y-%m"),
    Strat_Ret = as.numeric(strat_monthly)
  )

  cat("  Monthly returns:", nrow(strat_ret), "months\n")

  # Approach: Use final holdings to compute portfolio's factor z-score profile
  # Get the last holdings from the sim result
  nms <- names(sim)
  cat("  sim names:", paste(head(nms, 15), collapse=", "), "\n")

  # Most sims have $holdings as list
  final_tickers <- NULL
  if ("holdings" %in% nms && is.list(sim$holdings) && length(sim$holdings) > 0) {
    last_h <- sim$holdings[[length(sim$holdings)]]
    if (is.data.table(last_h) || is.data.frame(last_h)) {
      last_h <- as.data.table(last_h)
      if ("Ticker" %in% names(last_h)) final_tickers <- last_h$Ticker
    }
  }

  # Also try weight_history
  if (is.null(final_tickers) && "weight_history" %in% nms) {
    wh <- sim$weight_history
    if (is.list(wh) && length(wh) > 0) {
      last_w <- as.data.table(wh[[length(wh)]])
      if ("Ticker" %in% names(last_w)) final_tickers <- last_w$Ticker
    }
  }

  # Try selected_history
  if (is.null(final_tickers) && "selected_history" %in% nms) {
    sh <- sim$selected_history
    if (is.list(sh) && length(sh) > 0) {
      final_tickers <- sh[[length(sh)]]
    }
  }

  if (is.null(final_tickers)) {
    cat("  Cannot extract holdings. Using indicator approach.\n")
    return(NULL)
  }

  cat("  Final portfolio:", length(final_tickers), "tickers\n")

  # Create portfolio indicator (1 = in portfolio)
  all_tickers <- fdt_wide_cache$Ticker
  port_indicator <- as.numeric(all_tickers %in% final_tickers)
  cat("  Portfolio coverage in Factor DB:", sum(port_indicator), "/", length(final_tickers), "\n")

  if (sum(port_indicator) < 5) {
    cat("  WARNING: < 5 matched tickers\n")
    return(NULL)
  }

  # Correlate portfolio indicator with each factor z-score
  corr_list <- lapply(factor_cols_vec, function(fc) {
    x <- fdt_wide_cache[[fc]]
    valid <- !is.na(x)
    if (sum(valid & port_indicator == 1) < 3) return(data.table(Factor_Name = fc, Corr = NA_real_))
    data.table(Factor_Name = fc, Corr = cor(x[valid], port_indicator[valid], method = "spearman"))
  })
  pairwise <- rbindlist(corr_list)[!is.na(Corr)]

  if (nrow(pairwise) == 0) return(NULL)

  max_idx <- which.max(abs(pairwise$Corr))
  max_corr <- abs(pairwise$Corr[max_idx])
  max_factor <- pairwise$Factor_Name[max_idx]
  independence <- if (max_corr < 0.3) "independent"
                  else if (max_corr < 0.6) "partial"
                  else "redundant"

  pairwise[, Category := gsub("^([A-Z]+)\\d+.*", "\\1", Factor_Name)]
  cat_corr <- pairwise[, .(Max_Corr = max(abs(Corr), na.rm=TRUE)), by=Category][order(-Max_Corr)]

  list(
    pairwise_corr = pairwise,
    max_corr = max_corr,
    max_corr_factor = max_factor,
    independence = independence,
    n_compared = nrow(pairwise),
    category_corr = cat_corr,
    n_portfolio = length(final_tickers),
    n_matched = sum(port_indicator)
  )
}

# ---- Run S3 for 3 strategies ----
cat("[2/4] Running S3...\n\n")

tasks <- list(
  list(id = "STR_1433", dir = "STR_1433_consgate_c11fix_dd722",
       tag = "Strong", sr = 1.329, grade = "A"),
  list(id = "STR_1434", dir = "STR_1434_nco_herc_cdar",
       tag = "Strong", sr = 1.323, grade = "A"),
  list(id = "STR_1439", dir = "STR_1439_1047_to_fix",
       tag = "Strong", sr = 1.532, grade = "A")
)

results <- list()
for (task in tasks) {
  sim_path <- file.path(STRAT_BASE, task$dir, "sim_result.rds")
  cat("━━━", task$id, "(SR", task$sr, "Grade", task$grade, ") ━━━\n")

  tryCatch({
    res <- extract_strategy_returns_profile(
      sim_path, task$id, fdt, fdt_wide, factor_cols
    )
    if (!is.null(res)) {
      cat("  max_abs_corr:", round(res$max_corr, 4),
          "| most_corr:", res$max_corr_factor,
          "| independence:", res$independence,
          "| n_compared:", res$n_compared, "\n")
      top5 <- res$pairwise_corr[order(-abs(Corr))][1:min(5,.N)]
      cat("  Top 5 factor exposures:\n")
      for (i in seq_len(nrow(top5))) {
        cat("    ", top5$Factor_Name[i], ":", round(top5$Corr[i], 4), "\n")
      }
      cat("  Category exposures:\n")
      for (i in seq_len(min(5, nrow(res$category_corr)))) {
        cat("    ", res$category_corr$Category[i], ":",
            round(res$category_corr$Max_Corr[i], 4), "\n")
      }
    }
    results[[task$id]] <- res
    cat("\n")
  }, error = function(e) {
    cat("  ERROR:", conditionMessage(e), "\n\n")
    results[[task$id]] <<- NULL
  })
}

# ---- Save artifacts ----
cat("[3/4] Saving S3 artifacts...\n")
for (task in tasks) {
  res <- results[[task$id]]
  if (is.null(res)) { cat("  SKIP", task$id, "(NULL)\n"); next }

  cell <- paste0(task$tag, "_", tools::toTitleCase(res$independence))
  artifact <- list(
    factor_id = task$id,
    strategy_id = paste0(task$id, "_", sub("STR_\\d+_", "", task$dir)),
    max_abs_corr_db = round(res$max_corr, 4),
    most_correlated_factor = res$max_corr_factor,
    independence_class = res$independence,
    value_matrix_cell = cell,
    n_compared = res$n_compared,
    n_portfolio = res$n_portfolio,
    n_matched = res$n_matched,
    computed_date = as.character(Sys.Date()),
    method = "portfolio_indicator_spearman",
    top5_correlated = lapply(
      seq_len(min(5, nrow(res$pairwise_corr[order(-abs(Corr))]))),
      function(i) {
        d <- res$pairwise_corr[order(-abs(Corr))][i]
        list(factor = d$Factor_Name, corr = round(d$Corr, 4))
      }
    )
  )

  art_dir <- file.path(STRAT_BASE, task$dir, "stage_artifacts")
  fpath <- file.path(art_dir, paste0("s3_orthogonality_", task$id, ".json"))
  writeLines(toJSON(artifact, auto_unbox = TRUE, pretty = TRUE), fpath)
  cat("  Saved:", basename(fpath), "\n")
}

# ---- Summary ----
cat("\n[4/4] === S3 SUMMARY ===\n")
cat(sprintf("%-10s %-6s %-5s %-12s %-8s %-30s %-20s\n",
            "STR", "SR", "Grade", "Independence", "MaxCorr", "MostCorr", "Cell"))
cat(strrep("-", 100), "\n")
for (task in tasks) {
  res <- results[[task$id]]
  if (!is.null(res)) {
    cell <- paste0(task$tag, "_", tools::toTitleCase(res$independence))
    cat(sprintf("%-10s %-6s %-5s %-12s %-8s %-30s %-20s\n",
                task$id, task$sr, task$grade,
                res$independence, round(res$max_corr, 4),
                res$max_corr_factor, cell))
  } else {
    cat(sprintf("%-10s %-6s %-5s FAILED\n", task$id, task$sr, task$grade))
  }
}
cat("\n=== Done ===\n")
