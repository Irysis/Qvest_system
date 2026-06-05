cat("=== S3 Orthogonality Analysis: STR_1422_crowding_defense ===\n")
cat("## CR08+D01 — 팩터 + 수익률 직교성\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

source(file.path(
  Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
  "02_Infrastructure", "config.R"
))
source(file.path(FUNC_PATH, "factor_research_pipeline.R"))
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

TARGET_STR <- "STR_1422_crowding_defense"
TARGET_DIR <- file.path(STRATEGY_OUTPUT, TARGET_STR)

# ============================================================
# PART 1: Factor-Level — CR08+D01 composite orthogonality
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

    cr08 <- fdt[Factor_Name == "CR08_Volume_Price_Divergence"]
    d01  <- fdt[Factor_Name == "D01_IdioVol"]

    if (nrow(cr08) == 0 || nrow(d01) == 0) {
      cat("  CR08 or D01 missing\n"); next
    }

    wide_cr08 <- cr08[, .(Ticker, Z_CR08 = Z_Score_Aligned)]
    wide_d01  <- d01[, .(Ticker, Z_D01 = Z_Score_Aligned)]
    merged <- merge(wide_cr08, wide_d01, by = "Ticker")
    merged <- merged[!is.na(Z_CR08) & !is.na(Z_D01)]

    # Composite: equal weight
    composite_z <- setNames(0.5 * merged$Z_CR08 + 0.5 * merged$Z_D01, merged$Ticker)
    composite_z <- composite_z[!is.na(composite_z)]

    if (length(composite_z) < 30) { cat("  Too few tickers\n"); next }

    res <- compute_factor_orthogonality(composite_z, sig_d, active_only = FALSE)
    # Remove CR08 and D01 from results (they're components)
    res$pairwise_corr <- res$pairwise_corr[!grepl("CR08|D01", Factor_Name)]

    if (nrow(res$pairwise_corr) > 0) {
      max_idx <- which.max(abs(res$pairwise_corr$Corr))
      res$max_corr <- abs(res$pairwise_corr$Corr[max_idx])
      res$max_corr_factor <- res$pairwise_corr$Factor_Name[max_idx]
    }
    ortho_results[[td]] <- res

    cat(sprintf("  Independence: %s | Max|Corr|: %.3f (%s) | N: %d\n",
                res$independence, res$max_corr, res$max_corr_factor,
                nrow(res$pairwise_corr)))

    top10 <- res$pairwise_corr[order(-abs(Corr))][1:min(10, nrow(res$pairwise_corr))]
    cat("  Top 10 correlated:\n")
    for (i in seq_len(nrow(top10))) {
      cat(sprintf("    %2d. %-30s r = %+.3f\n", i, top10$Factor_Name[i], top10$Corr[i]))
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
  if ("DAILY_NAV_DT" %in% names(sim)) {
    nav <- as.data.table(sim$DAILY_NAV_DT)
    nav[, Date := as.Date(Date)]
    setorder(nav, Date)
    if ("Strategy_Ret" %in% names(nav)) {
      nav[, YM := format(Date, "%Y-%m")]
      monthly <- nav[, .(Date = max(Date), Ret = prod(1 + Strategy_Ret) - 1), by = YM]
      return(monthly[!is.na(Ret) & is.finite(Ret), .(Date, Ret)])
    }
  }
  if ("port" %in% names(sim)) port <- as.data.table(sim$port)
  else port <- tryCatch(as.data.table(sim), error = function(e) NULL)
  if (is.null(port)) return(NULL)
  ret_col <- intersect(names(port), c("Ret","ret","Return","port_ret","Monthly_Ret"))[1]
  date_col <- intersect(names(port), c("Date","date","YearMonth","sig_date","Signal_Date"))[1]
  if (is.na(ret_col) || is.na(date_col)) {
    nav_col <- intersect(names(port), c("NAV","nav"))[1]
    date_col2 <- intersect(names(port), c("Signal_Date","Date","Exec_Date"))[1]
    if (!is.na(nav_col) && !is.na(date_col2)) {
      setnames(port, c(date_col2, nav_col), c("Date","NAV"), skip_absent=TRUE)
      port[, Date := as.Date(Date)]; setorder(port, Date)
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

if (!is.null(target_ret)) {
  cat(sprintf("  Target: %d months loaded\n", nrow(target_ret)))

  ref_strs <- c(
    "STR_1433_consensus_4f_c11fix","STR_1375_5sleeve_cons_gate",
    "STR_1071_defense_noshortdd","STR_1033_nco_regime_blend",
    "STR_1060_consgate_overlay","STR_1435_5sleeve_dd620_repair"
  )
  all_strs <- list.dirs(STRATEGY_OUTPUT, recursive=FALSE, full.names=FALSE)
  crowd_strs <- grep("crowding|defense|cr08|d01_", all_strs, value=TRUE, ignore.case=TRUE)
  compare_pool <- unique(c(ref_strs, crowd_strs))
  compare_pool <- setdiff(compare_pool, TARGET_STR)

  ret_corrs <- data.table()
  for (sn in compare_pool) {
    ref_ret <- extract_returns(sn)
    if (is.null(ref_ret)) next
    merged <- merge(target_ret[, .(Date, Ret_t = Ret)], ref_ret[, .(Date, Ret_r = Ret)], by="Date")
    if (nrow(merged) < 12) next
    cv <- cor(merged$Ret_t, merged$Ret_r, method="spearman", use="complete.obs")
    hurdle_f <- file.path(STRATEGY_OUTPUT, sn, "output", "hurdle_result.json")
    grade <- "?"; sr <- NA
    if (file.exists(hurdle_f)) {
      hr <- tryCatch(fromJSON(hurdle_f), error=function(e) NULL)
      if (!is.null(hr)) { grade <- hr$grade; sr <- as.numeric(hr$metrics$Sharpe) }
    }
    ret_corrs <- rbind(ret_corrs, data.table(
      Strategy=sn, Grade=grade, Sharpe=round(sr,3),
      Return_Corr=round(cv,3), N_Months=nrow(merged)))
  }
  setorder(ret_corrs, -Return_Corr)
  if (nrow(ret_corrs) > 0) print(ret_corrs[1:min(15, nrow(ret_corrs))])
} else {
  cat("  Cannot load target returns\n")
  ret_corrs <- data.table()
}

# ============================================================
# PART 3: Verdict
# ============================================================
cat("\n\n========== FINAL VERDICT ==========\n")

if (length(ortho_results) > 0) {
  all_max <- sapply(ortho_results, function(x) x$max_corr)
  mean_max <- mean(all_max, na.rm=TRUE)
  factor_independence <- if (mean_max > 0.6) "redundant" else if (mean_max > 0.3) "partial" else "independent"
  cat(sprintf("Factor: %s (mean max|corr|=%.3f)\n", factor_independence, mean_max))
} else {
  factor_independence <- "unknown"; mean_max <- NA
}

if (nrow(ret_corrs) > 0) {
  ga <- ret_corrs[Grade == "A"]
  if (nrow(ga) >= 3) {
    novelty_score <- round(1 - mean(sort(abs(ga$Return_Corr), decreasing=TRUE)[1:3]), 3)
  } else if (nrow(ga) > 0) {
    novelty_score <- round(1 - mean(abs(ga$Return_Corr)), 3)
  } else novelty_score <- 0.5
  max_ret_corr <- max(abs(ret_corrs$Return_Corr), na.rm=TRUE)
} else {
  novelty_score <- 0.5; max_ret_corr <- NA
}

cat(sprintf("  Novelty Score: %.3f\n", novelty_score))
cat(sprintf("  Candidate Role: diversifier (CR08 crowding + D01 defense)\n"))

# Save
s3 <- list(
  strategy_id = "STR_1422", factor_id = "CR08+D01", stage = "S3",
  factor_independence = factor_independence,
  factor_mean_max_corr = round(mean_max, 3),
  novelty_score = novelty_score,
  max_return_corr = max_ret_corr,
  candidate_role_hint = "diversifier",
  s2_grade = "C", s2_sharpe = 0.588,
  created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)
artifact_dir <- file.path(TARGET_DIR, "stage_artifacts")
write(toJSON(s3, auto_unbox=TRUE, pretty=TRUE),
      file.path(artifact_dir, "s3_orthogonality_CR08_D01.json"))
cat("\n  Saved: s3_orthogonality_CR08_D01.json\n")
cat("=== S3 Complete ===\n")
