## H_1685_v2 (STR_1686) S3 Orthogonality Measurement
## Forge S1 완료 후 즉시 실행
## pre-requisite: 04_Research/strategies/STR_1686_foreign_resid_individual/output/daily_returns.csv
## output: stage_artifacts/s3_orthogonality_H_1685_v2.json
##
## 실행: cd "Quant_Module_Moltbot" && Rscript 04_Research/s3_h1685_v2_orthogonality_measure.R

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)
setwd(PROJECT_ROOT)

cat("=== H_1685_v2 STR_1686 S3 Orthogonality Measurement ===\n")
cat("Start:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

load_daily_returns <- function(path, label) {
  if (!file.exists(path)) {
    warning(sprintf("File not found: %s (%s)", path, label))
    return(NULL)
  }
  dt <- fread(path)
  ret_candidates <- c("Return", "Strategy_Ret", "Ret_overlay")
  ret_col <- intersect(ret_candidates, names(dt))
  if (length(ret_col) == 0L) {
    ret_col <- setdiff(names(dt), c("Date", "NAV", "MRS", "Layer", "NAV_base", "NAV_overlay"))[1]
  } else {
    ret_col <- ret_col[1]
  }
  dt <- dt[, .(Date = as.Date(Date), Return = get(ret_col))]
  setnames(dt, "Return", label)
  dt
}

strat_paths <- list(
  STR_1686          = "04_Research/strategies/STR_1686_foreign_resid_individual/output/daily_returns.csv",
  STR_1631_SYN_05   = "04_Research/strategies/STR_1631/output/daily_nav.csv",
  STR_1656_MLRA     = "04_Research/strategies/STR_1656_MLRA/output/nav_S1_A.csv",
  STR_1679v3        = "04_Research/strategies/STR_1679_score_blend/output/daily_returns_primary.csv"
)

# H_1674 predecessor (corr baseline — 사전 추정 0.897 → residualization 후 0.194 예상)
h1674_path <- "04_Research/strategies/STR_1674_foreign_individual/output/daily_returns.csv"
if (file.exists(h1674_path)) strat_paths[["H_1674_predecessor"]] <- h1674_path

dr_list <- list()
for (nm in names(strat_paths)) {
  dr <- load_daily_returns(strat_paths[[nm]], nm)
  if (!is.null(dr)) dr_list[[nm]] <- dr
}

if (length(dr_list) < 2) stop("daily_returns 로드 실패 — STR_1686 S1 완료 확인 필요")

merged <- Reduce(function(x, y) merge(x, y, by = "Date", all = FALSE), dr_list)
cat("Merged data:", nrow(merged), "days,", ncol(merged) - 1, "strategies\n")
cat("Date range:", format(range(merged$Date)), "\n\n")

merged[, YearMonth := format(Date, "%Y-%m")]
strat_cols <- setdiff(names(merged), c("Date", "YearMonth"))

monthly <- merged[, lapply(.SD, function(x) prod(1 + x) - 1), by = YearMonth, .SDcols = strat_cols]
cat("Monthly aggregation:", nrow(monthly), "months\n\n")

compute_empirical_tdc <- function(x, y, quantile_threshold = 0.95) {
  u <- rank(x) / (length(x) + 1)
  v <- rank(y) / (length(y) + 1)
  q <- quantile_threshold
  sum(u > q & v > q) / sum(u > q)
}

# STR_1686 vs benchmarks 쌍 (TODO S3 C7/C8 요건 준수)
primary_pairs <- list(
  c("STR_1686", "STR_1631_SYN_05"),
  c("STR_1686", "STR_1656_MLRA"),
  c("STR_1686", "STR_1679v3")
)
if ("H_1674_predecessor" %in% strat_cols) {
  primary_pairs <- c(primary_pairs, list(c("STR_1686", "H_1674_predecessor")))
}

pair_results <- list()
for (pair in primary_pairs) {
  if (!all(pair %in% strat_cols)) {
    cat(sprintf("  SKIP %s (missing)\n", paste(pair, collapse = " vs ")))
    next
  }
  x_daily   <- merged[[pair[1]]]; y_daily   <- merged[[pair[2]]]
  x_monthly <- monthly[[pair[1]]]; y_monthly <- monthly[[pair[2]]]

  pearson_d  <- cor(x_daily,   y_daily,   use = "pairwise.complete.obs")
  spearman_m <- cor(x_monthly, y_monthly, method = "spearman", use = "pairwise.complete.obs")
  tdc_u      <- compute_empirical_tdc(x_daily,  y_daily,  0.95)
  tdc_l      <- compute_empirical_tdc(-x_daily, -y_daily, 0.95)

  key <- paste(pair, collapse = "__vs__")
  pair_results[[key]] <- list(
    pair              = pair,
    pearson_daily     = round(pearson_d,  4),
    spearman_monthly  = round(spearman_m, 4),
    tdc_upper_95      = round(tdc_u, 4),
    tdc_lower_95      = round(tdc_l, 4),
    n_days            = sum(!is.na(x_daily)   & !is.na(y_daily)),
    n_months          = sum(!is.na(x_monthly) & !is.na(y_monthly)),
    gate_11_verdict   = ifelse(max(tdc_u, tdc_l) < 0.50, "PASS", "FAIL"),
    tdc_gate_full_040 = ifelse(max(tdc_u, tdc_l) < 0.40, "PASS", "REVIEW"),
    sequential_admission_crisis_gate = ifelse(max(tdc_u, tdc_l) < 0.30, "PASS", "REVIEW")
  )

  cat(sprintf("  %s vs %s: Pearson=%.3f Spearman=%.3f TDC_upper=%.3f TDC_lower=%.3f Gate11=%s Gate_040=%s\n",
    pair[1], pair[2], pearson_d, spearman_m, tdc_u, tdc_l,
    pair_results[[key]]$gate_11_verdict,
    pair_results[[key]]$tdc_gate_full_040))
}

# Crisis-conditional TDC (C8 요건)
regime_path <- file.path(PROJECT_ROOT, ".cache", "unified_regime_signal.parquet")
if (file.exists(regime_path)) {
  regime_dt  <- as.data.table(read_parquet(regime_path))
  regime_col <- intersect(names(regime_dt), c("FRED_MRS", "MSM_Crisis_Prob"))[1]
  if ("Date" %in% names(regime_dt) && !is.na(regime_col)) {
    regime_dt[, Date := as.Date(Date)]
    threshold <- if (regime_col == "MSM_Crisis_Prob") 0.5 else 30
    regime_dt[, is_crisis := get(regime_col) >= threshold]
    regime_dt[, YearMonth := format(Date, "%Y-%m")]
    merged[, YearMonth := format(Date, "%Y-%m")]
    merged_regime <- merge(merged, regime_dt[, .(YearMonth, is_crisis)], by = "YearMonth", all.x = TRUE)
    cat("\nCrisis-conditional TDC (C8):\n")
    for (pair in primary_pairs) {
      if (!all(pair %in% strat_cols)) next
      cr <- merged_regime[is_crisis == TRUE]
      if (nrow(cr) < 60) { cat(sprintf("  %s: insufficient crisis days\n", paste(pair, collapse=" vs "))); next }
      tdc_cr <- compute_empirical_tdc(cr[[pair[1]]], cr[[pair[2]]], 0.95)
      key <- paste(pair, collapse = "__vs__")
      pair_results[[key]]$tdc_crisis_95   <- round(tdc_cr, 4)
      pair_results[[key]]$tdc_crisis_055  <- ifelse(tdc_cr < 0.55, "PASS", "FAIL")
      pair_results[[key]]$n_crisis_days   <- nrow(cr)
      cat(sprintf("  %s vs %s: TDC_crisis=%.3f gate_055=%s (n=%d)\n",
        pair[1], pair[2], tdc_cr, pair_results[[key]]$tdc_crisis_055, nrow(cr)))
    }
  }
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

novelty_score <- if (length(pair_results) > 0) {
  tdc_max <- sapply(pair_results, function(p) max(p$tdc_upper_95, p$tdc_lower_95, p$tdc_crisis_95 %||% 0))
  1 - mean(tdc_max, na.rm = TRUE)
} else NA_real_

# p95 극단 월 감지 (C7 요건 — p95 |corr| 0.447 경고 확인)
if ("STR_1686" %in% strat_cols && "STR_1631_SYN_05" %in% strat_cols) {
  monthly_corr <- cor(monthly[["STR_1686"]], monthly[["STR_1631_SYN_05"]], use = "pairwise.complete.obs")
  p95_extreme_months <- sum(abs(monthly[["STR_1686"]] * monthly[["STR_1631_SYN_05"]]) > 0, na.rm = TRUE)
} else {
  monthly_corr <- NA; p95_extreme_months <- NA
}

# residualization 효과: H_1674 predecessor 대비 corr 변화
predecessor_corr <- NA
if ("H_1674_predecessor" %in% strat_cols && "STR_1686" %in% strat_cols) {
  predecessor_corr <- round(cor(monthly[["STR_1686"]], monthly[["H_1674_predecessor"]],
                                use = "pairwise.complete.obs"), 4)
  cat(sprintf("\nResidual vs Predecessor corr: %.3f (expected ~0.194, was 0.897)\n", predecessor_corr))
}

result <- list(
  artifact_type    = "s3_orthogonality_measured",
  hypothesis_id    = "H_1685_v2",
  strategy_id      = "STR_1686",
  measured_at      = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  measured_by      = "Scout (s3_h1685_v2_orthogonality_measure.R)",
  n_days           = nrow(merged),
  n_months         = nrow(monthly),
  date_range       = format(range(merged$Date)),
  strategies_loaded = strat_cols,
  pair_results     = pair_results,
  novelty_score    = round(novelty_score, 4),
  gate_11_overall_pass = all(sapply(pair_results, function(p) p$gate_11_verdict == "PASS")),
  gate_tdc_full_040_all_pass = all(sapply(pair_results, function(p) p$tdc_gate_full_040 == "PASS")),
  gate_tdc_crisis_055_all_pass = all(sapply(pair_results, function(p) {
    v <- p$tdc_crisis_055
    !is.null(v) && v == "PASS"
  })),
  sequential_admission_crisis_summary = sapply(pair_results, function(p) p$sequential_admission_crisis_gate),
  predecessor_corr_reduction = list(
    H_1674_corr = predecessor_corr,
    expected_H_1674 = 0.897,
    expected_H_1685_v2 = 0.194,
    residualization_effective = if (!is.na(predecessor_corr)) predecessor_corr < 0.40 else NA
  ),
  candidate_role_hint = "diversifier"
)

output_path <- file.path(PROJECT_ROOT, "stage_artifacts", "s3_orthogonality_H_1685_v2.json")
write(toJSON(result, pretty = TRUE, auto_unbox = TRUE, na = "null"), output_path)
cat("\nSaved:", output_path, "\n")
cat("Novelty score:", round(novelty_score, 4), "\n")
cat("Gate 11 overall PASS:", result$gate_11_overall_pass, "\n")
cat("Gate TDC full 0.40 all PASS:", result$gate_tdc_full_040_all_pass, "\n")
cat("\n=== S3 Measurement Complete ===\n")
