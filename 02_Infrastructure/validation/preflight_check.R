#==============================================================================
# Preflight Check — Lawbook v1.4.2 Quick Validation Before Full Backtest
#
# Purpose: Fast sanity check of factor_engine.R output before committing
#          to a full 25-year monthly simulation (~5-10 min save per bad run).
#
# Checks:
#   1. FACTORS has expected columns (Date, Ticker, Score)
#   2. Score distribution is reasonable (not constant, no NaN)
#   3. Sufficient coverage (>= 50 tickers per signal date)
#   4. Date range spans >= 5 years
#   5. No PIT violations (no future dates)
#   6. Factor fingerprint vs existing registry (duplicate detection)
#
# Usage:
#   source("preflight_check.R")
#   ok <- preflight_run(FACTORS, config = list(...))
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

cat("[preflight] Loaded.\n")

preflight_run <- function(FACTORS,
                           config = list(),
                           min_tickers = 50L,
                           min_years = 5,
                           verbose = TRUE) {

  checks <- list()
  pass <- TRUE

  # ── 1. Column check ──
  required_cols <- c("Date", "Ticker", "Score")
  missing_cols <- setdiff(required_cols, names(FACTORS))
  if (length(missing_cols) > 0) {
    checks$columns <- list(pass = FALSE,
                            msg = sprintf("Missing columns: %s", paste(missing_cols, collapse = ", ")))
    pass <- FALSE
  } else {
    checks$columns <- list(pass = TRUE, msg = "OK")
  }

  if (!pass) {
    if (verbose) cat("[preflight] FAIL — missing required columns\n")
    return(list(pass = FALSE, checks = checks))
  }

  # ── 2. Score distribution ──
  scores <- FACTORS$Score[!is.na(FACTORS$Score)]
  n_na <- sum(is.na(FACTORS$Score))
  na_pct <- n_na / nrow(FACTORS) * 100

  if (length(scores) == 0) {
    checks$score_dist <- list(pass = FALSE, msg = "All scores are NA")
    pass <- FALSE
  } else if (sd(scores) < 1e-10) {
    checks$score_dist <- list(pass = FALSE, msg = "Constant scores (sd ≈ 0)")
    pass <- FALSE
  } else if (any(is.nan(scores)) || any(is.infinite(scores))) {
    checks$score_dist <- list(pass = FALSE,
                               msg = sprintf("NaN/Inf in scores: %d values",
                                             sum(is.nan(scores) | is.infinite(scores))))
    pass <- FALSE
  } else {
    checks$score_dist <- list(
      pass = TRUE,
      msg = sprintf("OK (mean=%.2f, sd=%.2f, NA=%.1f%%)",
                    mean(scores), sd(scores), na_pct)
    )
  }

  # ── 3. Coverage ──
  coverage <- FACTORS[!is.na(Score), .N, by = Date]
  min_cov <- min(coverage$N)
  median_cov <- median(coverage$N)
  if (min_cov < min_tickers) {
    low_dates <- coverage[N < min_tickers]
    checks$coverage <- list(
      pass = FALSE,
      msg = sprintf("Low coverage: %d dates with < %d tickers (min=%d, median=%d)",
                    nrow(low_dates), min_tickers, min_cov, median_cov)
    )
    # Warning only, not a hard fail
  } else {
    checks$coverage <- list(
      pass = TRUE,
      msg = sprintf("OK (min=%d, median=%d tickers/date)", min_cov, median_cov)
    )
  }

  # ── 4. Date range ──
  date_range <- as.numeric(difftime(max(FACTORS$Date), min(FACTORS$Date),
                                      units = "days")) / 365.25
  if (date_range < min_years) {
    checks$date_range <- list(
      pass = FALSE,
      msg = sprintf("Short span: %.1f years (need >= %d)", date_range, min_years)
    )
    pass <- FALSE
  } else {
    checks$date_range <- list(
      pass = TRUE,
      msg = sprintf("OK (%.1f years: %s ~ %s)",
                    date_range, min(FACTORS$Date), max(FACTORS$Date))
    )
  }

  # ── 5. PIT check ──
  future_signals <- sum(FACTORS$Date > Sys.Date())
  if (future_signals > 0) {
    checks$pit <- list(
      pass = FALSE,
      msg = sprintf("Future signal dates: %d (possible PIT violation)", future_signals)
    )
    pass <- FALSE
  } else {
    checks$pit <- list(pass = TRUE, msg = "OK")
  }

  # ── 6. Fingerprint duplicate check ──
  if (length(config) > 0) {
    reg_path <- file.path(
      ifelse(exists("CACHE_DIR"), CACHE_DIR, ".cache"),
      "strategy_registry.json"
    )
    if (file.exists(reg_path)) {
      tryCatch({
        if (exists("compute_fingerprint") && is.function(compute_fingerprint)) {
          fp <- compute_fingerprint(config)
          registry <- jsonlite::fromJSON(reg_path, simplifyDataFrame = FALSE)
          dups <- names(Filter(function(x) identical(x$fingerprint, fp), registry))
          if (length(dups) > 0) {
            checks$fingerprint <- list(
              pass = FALSE,
              msg = sprintf("Duplicate fingerprint (%s) matches: %s",
                            fp, paste(dups, collapse = ", "))
            )
          } else {
            checks$fingerprint <- list(pass = TRUE,
                                        msg = sprintf("OK (fp=%s, unique)", fp))
          }
        }
      }, error = function(e) NULL)
    }
  }

  # ── Summary ──
  n_pass <- sum(sapply(checks, function(x) x$pass))
  n_total <- length(checks)

  if (verbose) {
    cat(sprintf("\n=== PREFLIGHT CHECK (%d/%d passed) ===\n", n_pass, n_total))
    for (nm in names(checks)) {
      status <- if (checks[[nm]]$pass) "PASS" else "FAIL"
      cat(sprintf("  [%s] %s: %s\n", status, nm, checks[[nm]]$msg))
    }
    cat(sprintf("  Overall: %s\n", if (pass) "READY for backtest" else "FIX issues first"))
    cat("======================================\n\n")
  }

  list(pass = pass, checks = checks, n_checks = n_total, n_passed = n_pass)
}

cat("[preflight] Functions: preflight_run()\n")
