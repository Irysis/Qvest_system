cat("=== S3 Orthogonality Analysis: STR_1435_5sleeve_dd620_repair ===\n")
cat("## 5-Sleeve DD 6/20 Repair — 수익률 기반 직교성 (복합 전략)\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

source(file.path(
  Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
  "02_Infrastructure", "config.R"
))

TARGET_STR <- "STR_1435_5sleeve_dd620_repair"
TARGET_DIR <- file.path(STRATEGY_OUTPUT, TARGET_STR)

# ============================================================
# PART 1: Load target returns
# ============================================================
cat("\n========== PART 1: Target Strategy Returns ==========\n")

extract_returns <- function(str_name) {
  str_path <- file.path(STRATEGY_OUTPUT, str_name)
  sim_file <- file.path(str_path, "sim_result.rds")
  if (!file.exists(sim_file)) sim_file <- file.path(str_path, "output", "sim_result.rds")
  if (!file.exists(sim_file)) return(NULL)

  sim <- tryCatch(readRDS(sim_file), error = function(e) NULL)
  if (is.null(sim)) return(NULL)

  # Case 1: DAILY_NAV_DT format (5-sleeve etc.)
  if ("DAILY_NAV_DT" %in% names(sim)) {
    nav <- as.data.table(sim$DAILY_NAV_DT)
    date_col <- intersect(names(nav), c("Date","date"))[1]
    nav_col <- intersect(names(nav), c("NAV","nav","Strategy","Strat_NAV","Value","Strategy_Ret"))[1]
    if (is.na(date_col) || is.na(nav_col)) return(NULL)
    nav[, Date := as.Date(nav[[date_col]])]
    setorder(nav, Date)
    # If Strategy_Ret exists, use daily returns → aggregate monthly
    if ("Strategy_Ret" %in% names(nav)) {
      nav[, YM := format(Date, "%Y-%m")]
      monthly <- nav[, .(Date = max(Date), Ret = prod(1 + Strategy_Ret) - 1), by = YM]
      setorder(monthly, Date)
      return(monthly[!is.na(Ret) & is.finite(Ret), .(Date, Ret)])
    }
    setnames(nav, nav_col, "NAV", skip_absent = TRUE)
    nav[, YM := format(Date, "%Y-%m")]
    monthly <- nav[, .(Date = max(Date), NAV = NAV[.N]), by = YM]
    setorder(monthly, Date)
    monthly[, Ret := NAV / shift(NAV) - 1]
    return(monthly[!is.na(Ret), .(Date, Ret)])
  }

  # Case 2: Standard port format
  if ("port" %in% names(sim)) {
    port <- as.data.table(sim$port)
  } else {
    port <- tryCatch(as.data.table(sim), error = function(e) NULL)
    if (is.null(port)) return(NULL)
  }

  ret_col <- intersect(names(port), c("Ret", "ret", "Return", "port_ret", "Monthly_Ret"))[1]
  date_col <- intersect(names(port), c("Date", "date", "YearMonth", "sig_date"))[1]

  if (is.na(ret_col) || is.na(date_col)) {
    # Try NAV-based from PORTFOLIO_LOG
    nav_col <- intersect(names(port), c("NAV","nav"))[1]
    date_col2 <- intersect(names(port), c("Signal_Date","Date","date","Exec_Date"))[1]
    if (!is.na(nav_col) && !is.na(date_col2)) {
      setnames(port, c(date_col2, nav_col), c("Date", "NAV"), skip_absent = TRUE)
      port[, Date := as.Date(Date)]
      setorder(port, Date)
      port[, Ret := NAV / shift(NAV) - 1]
      return(port[!is.na(Ret), .(Date, Ret)])
    }
    return(NULL)
  }

  result <- port[, .SD, .SDcols = c(date_col, ret_col)]
  setnames(result, c("Date", "Ret"))
  result[, Date := as.Date(Date)]
  result[!is.na(Ret)]
}

target_ret <- extract_returns(TARGET_STR)
if (is.null(target_ret)) {
  cat("ERROR: Cannot load target returns\n"); q("no")
}
cat(sprintf("  Target: %d months loaded\n", nrow(target_ret)))

# ============================================================
# PART 2: Grade A Reference Pool — Return Correlation
# ============================================================
cat("\n========== PART 2: Grade A Reference Correlation ==========\n")

# Key Grade A strategies for comparison
ref_strs <- c(
  "STR_1433_consensus_4f_c11fix",
  "STR_1375_5sleeve_cons_gate",
  "STR_1071_defense_noshortdd",
  "STR_1033_nco_regime_blend",
  "STR_1060_consgate_overlay",
  "STR_1053_mrs_1225_blend"
)

# Also scan for strategies with "dd" or "5sleeve" in name (lineage comparison)
all_strs <- list.dirs(STRATEGY_OUTPUT, recursive = FALSE, full.names = FALSE)
lineage_strs <- grep("5sleeve|dd.*repair|dd620|dd_brake", all_strs, value = TRUE, ignore.case = TRUE)
lineage_strs <- setdiff(lineage_strs, TARGET_STR)

# Combine, deduplicate
compare_pool <- unique(c(ref_strs, lineage_strs))

corr_results <- data.table()
for (str_name in compare_pool) {
  ref_ret <- extract_returns(str_name)
  if (is.null(ref_ret)) next

  merged <- merge(target_ret[, .(Date, Ret_target = Ret)],
                  ref_ret[, .(Date, Ret_ref = Ret)], by = "Date")
  if (nrow(merged) < 12) next

  corr_val <- cor(merged$Ret_target, merged$Ret_ref, method = "spearman", use = "complete.obs")

  # Try to get grade info
  hurdle_f <- file.path(STRATEGY_OUTPUT, str_name, "output", "hurdle_result.json")
  grade <- "?"
  sr <- NA_real_
  if (file.exists(hurdle_f)) {
    hr <- tryCatch(fromJSON(hurdle_f), error = function(e) NULL)
    if (!is.null(hr)) {
      grade <- if (!is.null(hr$grade)) hr$grade else "?"
      sr <- if (!is.null(hr$metrics$Sharpe)) hr$metrics$Sharpe else NA
    }
  }

  corr_results <- rbind(corr_results, data.table(
    Strategy = str_name, Grade = grade, Sharpe = round(sr, 3),
    Return_Corr = round(corr_val, 3), N_Months = nrow(merged)
  ))
}

setorder(corr_results, -Return_Corr)
cat("\n--- Return Correlation with Reference Pool ---\n")
if (nrow(corr_results) > 0) {
  print(corr_results[1:min(20, nrow(corr_results))])

  # Grade A only correlations
  grade_a_corr <- corr_results[Grade == "A"]
  cat(sprintf("\nGrade A comparisons: %d strategies\n", nrow(grade_a_corr)))
  if (nrow(grade_a_corr) > 0) {
    cat(sprintf("  Mean corr: %.3f | Max: %.3f (%s) | Min: %.3f\n",
                mean(grade_a_corr$Return_Corr, na.rm = TRUE),
                max(grade_a_corr$Return_Corr, na.rm = TRUE),
                grade_a_corr$Strategy[which.max(grade_a_corr$Return_Corr)],
                min(grade_a_corr$Return_Corr, na.rm = TRUE)))
  }

  # Lineage correlations
  lineage_corr <- corr_results[Strategy %in% lineage_strs]
  if (nrow(lineage_corr) > 0) {
    cat(sprintf("\nLineage (5sleeve/DD) comparisons: %d strategies\n", nrow(lineage_corr)))
    cat(sprintf("  Mean corr: %.3f | Max: %.3f (%s)\n",
                mean(lineage_corr$Return_Corr, na.rm = TRUE),
                max(lineage_corr$Return_Corr, na.rm = TRUE),
                lineage_corr$Strategy[which.max(lineage_corr$Return_Corr)]))
  }
}

# ============================================================
# PART 3: Novelty Score & Verdict
# ============================================================
cat("\n\n========== PART 3: Novelty Score & Verdict ==========\n")

if (nrow(corr_results) > 0) {
  # Novelty = 1 - mean(top3 absolute correlations with Grade A)
  ga <- corr_results[Grade == "A"]
  if (nrow(ga) >= 3) {
    top3_corr <- sort(abs(ga$Return_Corr), decreasing = TRUE)[1:3]
    novelty_score <- round(1 - mean(top3_corr), 3)
  } else if (nrow(ga) > 0) {
    novelty_score <- round(1 - mean(abs(ga$Return_Corr)), 3)
  } else {
    novelty_score <- 0.5  # No Grade A to compare
  }

  max_abs_corr <- max(abs(corr_results$Return_Corr), na.rm = TRUE)
  mean_abs_corr <- mean(abs(corr_results$Return_Corr), na.rm = TRUE)

  if (max_abs_corr > 0.8) {
    independence <- "redundant"
  } else if (max_abs_corr > 0.5) {
    independence <- "partial"
  } else {
    independence <- "independent"
  }

  cat(sprintf("  Novelty Score: %.3f\n", novelty_score))
  cat(sprintf("  Max |corr|: %.3f | Mean |corr|: %.3f\n", max_abs_corr, mean_abs_corr))
  cat(sprintf("  Independence: %s\n", independence))

  # Candidate role hint based on S0 record (REPAIR = improvement of existing)
  cat(sprintf("  Candidate Role: core_alpha (5-sleeve diversified, DD-repaired from STR_1417)\n"))
} else {
  novelty_score <- 0.5
  independence <- "unknown"
  cat("  No reference strategies found for comparison\n")
}

# ============================================================
# PART 4: Save S3 Artifact
# ============================================================
cat("\n========== Saving S3 Artifact ==========\n")

s3_artifact <- list(
  strategy_id = "STR_1435",
  strategy_name = TARGET_STR,
  stage = "S3",
  independence = independence,
  novelty_score = novelty_score,
  n_compared = nrow(corr_results),
  max_return_corr = if (nrow(corr_results) > 0) max(abs(corr_results$Return_Corr)) else NA,
  max_corr_strategy = if (nrow(corr_results) > 0) corr_results$Strategy[which.max(abs(corr_results$Return_Corr))] else NA,
  candidate_role_hint = "core_alpha",
  analysis_type = "return_correlation_only",
  note = "5-sleeve composite. Factor-level not applicable.",
  created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)

artifact_dir <- file.path(TARGET_DIR, "stage_artifacts")
if (!dir.exists(artifact_dir)) dir.create(artifact_dir, recursive = TRUE)
write(toJSON(s3_artifact, auto_unbox = TRUE, pretty = TRUE),
      file.path(artifact_dir, "s3_orthogonality_5sleeve_dd_repair.json"))

cat(sprintf("\n  Saved: s3_orthogonality_5sleeve_dd_repair.json\n"))
cat("=== S3 Complete ===\n")
