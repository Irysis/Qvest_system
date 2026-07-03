cat("=== S3 Batch Orthogonality Analysis ===\n")
cat("=== 7 strategies: STR_1607~1613 ===\n\n")

library(data.table)
library(jsonlite)
library(arrow)

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
INFRA_DIR    <- file.path(PROJECT_ROOT, "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

# === Load Factor DB at latest date (one-time, for all 7 strategies) ===
FDB_DIR <- file.path(PROJECT_ROOT, ".cache", "factor_db")
ds <- open_dataset(FDB_DIR, format = "parquet")

# Get latest date
dates_avail <- ds |> dplyr::distinct(Date) |> dplyr::collect()
dates_avail <- sort(as.Date(dates_avail$Date), decreasing = TRUE)
latest_sig_date <- dates_avail[1]
cat("Latest signal date:", as.character(latest_sig_date), "\n")

# Load ALL factor Z-scores at latest date (one-time bulk load)
cat("Loading all factors at latest date...\n")
all_fdt <- ds |>
  dplyr::filter(Date == latest_sig_date) |>
  dplyr::collect() |> as.data.table()

# Load registry for direction alignment
REG_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure/factor_db/factor_registry.json")
raw_json <- paste(readLines(REG_PATH, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
registry <- fromJSON(raw_json)
cat(sprintf("Registry: %d factors\n", length(registry)))

# Align factor direction
all_fdt <- align_factor_direction(all_fdt, registry)
cat(sprintf("All factors loaded: %s rows, %d unique factors\n\n",
            format(nrow(all_fdt), big.mark = ","), uniqueN(all_fdt$Factor_Name)))

# Pivot to wide: Ticker × Factor
fdt_wide <- dcast(all_fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

# === Admitted portfolio strategies for return correlation ===
admitted <- c("STR_1555_score_blend_3factor", "STR_1550_consensus_core_alpha")

load_monthly_ret <- function(str_name) {
  path <- file.path(PROJECT_ROOT, "04_Research/strategies", str_name, "sim_result.rds")
  if (!file.exists(path)) return(NULL)
  sim <- readRDS(path)
  nav <- as.data.table(sim$DAILY_NAV_DT)
  nav[, YM := format(Date, "%Y-%m")]
  monthly <- nav[, .(Month_Ret = prod(1 + Strategy_Ret, na.rm = TRUE) - 1), by = YM]
  setorder(monthly, YM)
  monthly
}

admitted_rets <- lapply(admitted, function(s) {
  r <- load_monthly_ret(s)
  if (!is.null(r)) setnames(r, "Month_Ret", s)
  r
})
admitted_rets <- Filter(Negate(is.null), admitted_rets)

# === Target strategies ===
targets <- list(
  list(str_id = "STR_1607", name = "STR_1607_gross_margin_defense",         factor = "Q10_Gross_Margin",            role = "defense"),
  list(str_id = "STR_1608", name = "STR_1608_tracking_error_diversifier",   factor = "D22_Tracking_Error",          role = "diversifier"),
  list(str_id = "STR_1609", name = "STR_1609_vwap_spread_diversifier",      factor = "L40_VWAP_Spread",             role = "diversifier"),
  list(str_id = "STR_1610", name = "STR_1610_volprice_divergence",          factor = "CR08_Volume_Price_Divergence", role = "diversifier"),
  list(str_id = "STR_1611", name = "STR_1611_intermediate_mom_diversifier", factor = "M10_Intermediate_Mom",         role = "diversifier"),
  list(str_id = "STR_1612", name = "STR_1612_rafi_value_diversifier",       factor = "V23_RAFI_Weight",              role = "diversifier"),
  list(str_id = "STR_1613", name = "STR_1613_earnings_growth_diversifier",  factor = "GR02_Earnings_Growth",         role = "diversifier")
)

results <- list()

for (tgt in targets) {
  cat(sprintf("--- %s (%s, role=%s) ---\n", tgt$name, tgt$factor, tgt$role))

  # 1. Get new factor Z-scores
  if (!(tgt$factor %in% names(fdt_wide))) {
    cat("  SKIP: Factor not in wide table\n\n")
    results[[tgt$str_id]] <- list(status = "skip", reason = "factor_not_found")
    next
  }

  new_z <- fdt_wide[[tgt$factor]]
  names(new_z) <- fdt_wide$Ticker
  new_z <- new_z[!is.na(new_z)]
  cat(sprintf("  Tickers with Z-score: %d\n", length(new_z)))

  # 2. Pairwise Spearman correlation with all other factors
  factor_cols <- setdiff(names(fdt_wide), c("Ticker", tgt$factor))
  corr_list <- lapply(factor_cols, function(fc) {
    other_z <- fdt_wide[[fc]]
    valid <- !is.na(new_z) & !is.na(other_z[match(fdt_wide$Ticker, names(new_z))])
    # Use matched tickers
    tickers <- intersect(names(new_z), fdt_wide$Ticker[!is.na(fdt_wide[[fc]])])
    if (length(tickers) < 20) return(data.table(Factor_Name = fc, Corr = NA_real_))
    idx <- match(tickers, fdt_wide$Ticker)
    data.table(
      Factor_Name = fc,
      Corr = cor(new_z[tickers], fdt_wide[[fc]][idx], method = "spearman", use = "complete.obs")
    )
  })
  pairwise <- rbindlist(corr_list)
  pairwise <- pairwise[!is.na(Corr)]

  if (nrow(pairwise) == 0) {
    cat("  SKIP: No valid pairwise correlations\n\n")
    results[[tgt$str_id]] <- list(status = "skip", reason = "no_correlations")
    next
  }

  # Max correlation
  max_idx <- which.max(abs(pairwise$Corr))
  max_corr <- abs(pairwise$Corr[max_idx])
  max_factor <- pairwise$Factor_Name[max_idx]

  # Independence classification
  independence <- if (max_corr < 0.3) "independent"
  else if (max_corr < 0.6) "partial"
  else "redundant"

  # Category-level correlation
  pairwise[, Category := gsub("^([A-Z]+)\\d+.*", "\\1", Factor_Name)]
  cat_corr <- pairwise[, .(Max_Corr = max(abs(Corr), na.rm = TRUE)), by = Category]
  setorder(cat_corr, -Max_Corr)

  # Top 5
  top5 <- head(pairwise[order(-abs(Corr))], 5)
  cat(sprintf("  Max corr: %.3f (%s) | Independence: %s | Compared: %d factors\n",
              max_corr, max_factor, independence, nrow(pairwise)))
  cat("  Top-5 correlated:\n")
  for (j in seq_len(nrow(top5))) {
    cat(sprintf("    %s: %.3f\n", top5$Factor_Name[j], top5$Corr[j]))
  }

  # 3. Cross-strategy return correlation with admitted portfolio
  new_ret <- load_monthly_ret(tgt$name)
  port_corrs <- list()
  if (!is.null(new_ret) && length(admitted_rets) > 0) {
    for (ar in admitted_rets) {
      ar_name <- setdiff(names(ar), "YM")
      merged_m <- merge(new_ret, ar, by = "YM")
      if (nrow(merged_m) >= 12) {
        cr <- cor(merged_m$Month_Ret, merged_m[[ar_name]], method = "spearman", use = "complete.obs")
        port_corrs[[ar_name]] <- round(cr, 4)
        cat(sprintf("  Return corr with %s: %.3f\n", ar_name, cr))
      }
    }
  }

  # 4. Novelty score (0-100)
  novelty_score <- round(max(0, min(100, (1 - max_corr) * 100)), 1)

  # 5. Candidate role hint
  avg_port_corr <- if (length(port_corrs) > 0) mean(unlist(port_corrs)) else NA
  candidate_role_hint <- tgt$role
  if (!is.na(avg_port_corr)) {
    if (avg_port_corr < -0.1) candidate_role_hint <- "defense"
    else if (avg_port_corr < 0.2) candidate_role_hint <- "diversifier"
    else candidate_role_hint <- "core_alpha"
  }

  cat(sprintf("  Novelty: %.1f | Role hint: %s\n\n", novelty_score, candidate_role_hint))

  # 6. S3 verdict
  s3_verdict <- if (independence == "redundant") "REJECT_REDUNDANT"
  else if (novelty_score >= 50) "ADVANCE"
  else "ADVANCE_CONDITIONAL"

  # 7. Write S3 artifact
  s3_artifact <- list(
    strategy_id = tgt$str_id,
    strategy_name = tgt$name,
    factor_id = tgt$factor,
    stage = "S3",
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    signal_date_used = as.character(latest_sig_date),
    orthogonality = list(
      max_corr = round(max_corr, 4),
      max_corr_factor = max_factor,
      independence = independence,
      n_factors_compared = nrow(pairwise),
      top5_correlated = lapply(seq_len(min(5, nrow(top5))), function(j) {
        list(factor = top5$Factor_Name[j], corr = round(top5$Corr[j], 4))
      }),
      category_corr_top3 = lapply(1:min(3, nrow(cat_corr)), function(j) {
        list(category = cat_corr$Category[j], max_corr = round(cat_corr$Max_Corr[j], 4))
      })
    ),
    portfolio_correlation = port_corrs,
    avg_portfolio_corr = if (!is.na(avg_port_corr)) round(avg_port_corr, 4) else NULL,
    novelty_score = novelty_score,
    candidate_role_hint = candidate_role_hint,
    expected_role = tgt$role,
    s2_flag = "hard_fail: MDD > 45%",
    s3_verdict = s3_verdict,
    s3_note = "MDD >45% from S2 is single-factor standalone; S5 overlay may resolve.",
    status = "completed"
  )

  artifact_dir <- file.path(PROJECT_ROOT, "04_Research/strategies", tgt$name, "stage_artifacts")
  artifact_path <- file.path(artifact_dir, paste0("s3_orthogonality_", tgt$str_id, ".json"))
  write_json(s3_artifact, artifact_path, auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf("  Artifact saved: %s\n\n", basename(artifact_path)))

  results[[tgt$str_id]] <- s3_artifact
}

# === Summary ===
cat("\n========================================\n")
cat("=== S3 BATCH SUMMARY ===\n")
cat("========================================\n")
for (r in results) {
  if (is.list(r) && !is.null(r$strategy_name)) {
    cat(sprintf("  %-45s max_corr=%.3f  %s  novelty=%.0f  role=%s  -> %s\n",
                r$strategy_name, r$orthogonality$max_corr, r$orthogonality$independence,
                r$novelty_score, r$candidate_role_hint, r$s3_verdict))
  }
}
cat("\nDone.\n")
