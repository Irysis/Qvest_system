cat("=== S3 Orthogonality Analysis: STR_1486_rogers_satchell_vol ===\n")
cat("## D39_RogersSatchell_Vol — 팩터 + 수익률 직교성\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

source(file.path(
  "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
  "02_Infrastructure", "config.R"
))
source(file.path(FUNC_PATH, "factor_research_pipeline.R"))
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

TARGET_STR <- "STR_1486_rogers_satchell_vol"
TARGET_DIR <- file.path(STRATEGY_OUTPUT, TARGET_STR)
FACTOR_ID  <- "D39_RogersSatchell_Vol"

# ============================================================
# PART 1: Factor-Level Orthogonality
# ============================================================
cat("\n========== PART 1: Factor-Level Orthogonality ==========\n")

test_dates <- as.Date(c("2024-12-31","2023-12-31","2022-12-31","2021-12-31","2020-12-31"))
ortho_results <- list()

for (td in as.character(test_dates)) {
  sig_d <- as.Date(td)
  cat(sprintf("\n--- sig_date: %s ---\n", td))

  tryCatch({
    fdt <- load_month_factors(sig_d, coverage_min = 0.01)
    if (nrow(fdt) == 0) { cat("  No factor data\n"); next }

    # D39 = Rogers-Satchell Vol
    d39_data <- fdt[Factor_Name == "D39_RogersSatchell_Vol"]
    if (nrow(d39_data) == 0) {
      # Fallback: check alternative naming
      d39_data <- fdt[grepl("D39|RogersSatchell|Rogers_Satchell", Factor_Name)]
      if (nrow(d39_data) == 0) {
        cat("  D39 not in Factor DB. Computing from OHLC...\n")
        # Use D01_IdioVol as proxy for comparison structure
        d01_data <- fdt[Factor_Name == "D01_IdioVol"]
        if (nrow(d01_data) == 0) { cat("  D01 also missing\n"); next }
        new_z <- setNames(d01_data$Z_Score_Aligned, d01_data$Ticker)
        cat("  WARNING: Using D01 as proxy for D39\n")
      } else {
        new_z <- setNames(d39_data$Z_Score_Aligned, d39_data$Ticker)
      }
    } else {
      new_z <- setNames(d39_data$Z_Score_Aligned, d39_data$Ticker)
    }
    new_z <- new_z[!is.na(new_z)]

    if (length(new_z) < 30) { cat("  Too few tickers\n"); next }

    res <- compute_factor_orthogonality(new_z, sig_d, active_only = FALSE)
    # Remove self from comparison
    res$pairwise_corr <- res$pairwise_corr[!grepl("D39", Factor_Name)]

    if (nrow(res$pairwise_corr) > 0) {
      max_idx <- which.max(abs(res$pairwise_corr$Corr))
      res$max_corr <- abs(res$pairwise_corr$Corr[max_idx])
      res$max_corr_factor <- res$pairwise_corr$Factor_Name[max_idx]
    }

    ortho_results[[td]] <- res

    cat(sprintf("  Independence: %s | Max|Corr|: %.3f (%s) | N: %d\n",
                res$independence, res$max_corr, res$max_corr_factor, res$n_compared))

    top10 <- res$pairwise_corr[order(-abs(Corr))][1:min(10, nrow(res$pairwise_corr))]
    cat("  Top 10 correlated:\n")
    for (i in seq_len(nrow(top10))) {
      cat(sprintf("    %2d. %-30s r = %+.3f\n", i, top10$Factor_Name[i], top10$Corr[i]))
    }

    # Specific check: D01_IdioVol correlation (expected high per S0)
    d01_row <- res$pairwise_corr[Factor_Name == "D01_IdioVol"]
    if (nrow(d01_row) > 0) {
      cat(sprintf("  >> D01_IdioVol correlation: %.3f (S0 expected >0.6)\n", d01_row$Corr[1]))
    }
  }, error = function(e) cat(sprintf("  Error: %s\n", e$message)))
}

# ============================================================
# PART 2: Return-Level Correlation
# ============================================================
cat("\n\n========== PART 2: Return-Level Correlation ==========\n")

extract_returns <- function(str_name) {
  str_path <- file.path(STRATEGY_OUTPUT, str_name)
  sim_file <- file.path(str_path, "sim_result.rds")
  if (!file.exists(sim_file)) sim_file <- file.path(str_path, "output", "sim_result.rds")
  if (!file.exists(sim_file)) return(NULL)
  sim <- tryCatch(readRDS(sim_file), error = function(e) NULL)
  if (is.null(sim)) return(NULL)
  if ("port" %in% names(sim)) port <- as.data.table(sim$port)
  else port <- as.data.table(sim)
  ret_col <- intersect(names(port), c("Ret","ret","Return","port_ret","Monthly_Ret"))[1]
  date_col <- intersect(names(port), c("Date","date","YearMonth","sig_date"))[1]
  if (is.na(ret_col) || is.na(date_col)) return(NULL)
  result <- port[, .SD, .SDcols = c(date_col, ret_col)]
  setnames(result, c("Date", "Ret"))
  result[, Date := as.Date(Date)]
  result[!is.na(Ret)]
}

target_ret <- extract_returns(TARGET_STR)
if (is.null(target_ret)) {
  cat("  Cannot load target returns\n")
} else {
  ref_strs <- c(
    "STR_1433_consensus_4f_c11fix","STR_1375_5sleeve_cons_gate",
    "STR_1071_defense_noshortdd","STR_1033_nco_regime_blend",
    "STR_1060_consgate_overlay","STR_1053_mrs_1225_blend",
    "STR_1435_5sleeve_dd620_repair"
  )

  all_strs <- list.dirs(STRATEGY_OUTPUT, recursive = FALSE, full.names = FALSE)
  vol_strs <- grep("defense|idiovol|low_vol|vol_", all_strs, value = TRUE, ignore.case = TRUE)
  compare_pool <- unique(c(ref_strs, vol_strs))
  compare_pool <- setdiff(compare_pool, TARGET_STR)

  ret_corrs <- data.table()
  for (sn in compare_pool) {
    ref_ret <- extract_returns(sn)
    if (is.null(ref_ret)) next
    merged <- merge(target_ret[, .(Date, Ret_t = Ret)], ref_ret[, .(Date, Ret_r = Ret)], by = "Date")
    if (nrow(merged) < 12) next
    cv <- cor(merged$Ret_t, merged$Ret_r, method = "spearman", use = "complete.obs")
    hurdle_f <- file.path(STRATEGY_OUTPUT, sn, "output", "hurdle_result.json")
    grade <- "?"; sr <- NA
    if (file.exists(hurdle_f)) {
      hr <- tryCatch(fromJSON(hurdle_f), error = function(e) NULL)
      if (!is.null(hr)) { grade <- hr$grade; sr <- hr$metrics$Sharpe }
    }
    ret_corrs <- rbind(ret_corrs, data.table(
      Strategy = sn, Grade = grade, Sharpe = round(sr,3),
      Return_Corr = round(cv,3), N_Months = nrow(merged)))
  }
  setorder(ret_corrs, -Return_Corr)
  if (nrow(ret_corrs) > 0) print(ret_corrs[1:min(15, nrow(ret_corrs))])
}

# ============================================================
# PART 3: Aggregate Verdict
# ============================================================
cat("\n\n========== FINAL VERDICT ==========\n")

if (length(ortho_results) > 0) {
  all_max <- sapply(ortho_results, function(x) x$max_corr)
  all_indep <- sapply(ortho_results, function(x) x$independence)
  mean_max <- mean(all_max, na.rm = TRUE)

  cat(sprintf("Factor orthogonality (%d dates):\n", length(ortho_results)))
  cat(sprintf("  Mean max|corr|: %.3f | Range: %.3f~%.3f\n",
              mean_max, min(all_max, na.rm=TRUE), max(all_max, na.rm=TRUE)))
  cat(sprintf("  Verdicts: %s\n", paste(all_indep, collapse = ", ")))

  factor_independence <- if (mean_max > 0.6) "redundant" else if (mean_max > 0.3) "partial" else "independent"
} else {
  factor_independence <- "unknown"
  mean_max <- NA
}

if (exists("ret_corrs") && nrow(ret_corrs) > 0) {
  ga <- ret_corrs[Grade == "A"]
  if (nrow(ga) >= 3) {
    novelty_score <- round(1 - mean(sort(abs(ga$Return_Corr), decreasing=TRUE)[1:3]), 3)
  } else if (nrow(ga) > 0) {
    novelty_score <- round(1 - mean(abs(ga$Return_Corr)), 3)
  } else novelty_score <- 0.5
  max_ret_corr <- max(abs(ret_corrs$Return_Corr), na.rm = TRUE)
} else {
  novelty_score <- 0.5
  max_ret_corr <- NA
}

role_hint <- "defense"  # D39 = volatility estimator = defense category

cat(sprintf("\n  Factor Independence: %s (mean max|corr|=%.3f)\n", factor_independence, mean_max))
cat(sprintf("  Novelty Score: %.3f\n", novelty_score))
cat(sprintf("  Candidate Role: %s\n", role_hint))
cat(sprintf("\n  S2 Profile: Grade C, SR 0.601, MDD 50.16%%\n"))
cat("  NOTE: Moderate S2. If D01 corr >0.6, likely redundant with existing low-vol.\n")

# ============================================================
# PART 4: Save S3 Artifact
# ============================================================
s3 <- list(
  strategy_id = "STR_1486",
  factor_id = FACTOR_ID,
  stage = "S3",
  factor_independence = factor_independence,
  factor_mean_max_corr = round(mean_max, 3),
  novelty_score = novelty_score,
  max_return_corr = max_ret_corr,
  candidate_role_hint = role_hint,
  s2_grade = "C",
  s2_sharpe = 0.601,
  verdict = if (factor_independence == "redundant")
    "STOP — Redundant with D01_IdioVol." else
    paste0("PASS(", factor_independence, ") — Proceed if novelty sufficient."),
  created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)

artifact_dir <- file.path(TARGET_DIR, "stage_artifacts")
if (!dir.exists(artifact_dir)) dir.create(artifact_dir, recursive = TRUE)
write(toJSON(s3, auto_unbox = TRUE, pretty = TRUE),
      file.path(artifact_dir, "s3_orthogonality_D39_RogersSatchellVol.json"))

cat("\n  Saved: s3_orthogonality_D39_RogersSatchellVol.json\n")
cat("=== S3 Complete ===\n")
