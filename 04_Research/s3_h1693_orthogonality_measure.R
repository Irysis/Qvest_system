## H_1693 STR_1687 S3 Orthogonality Measurement
## Forge S1 완료 후 즉시 실행 가능 pre-built script
## template: stage_artifacts/h_1693_s3_orthogonality_protocol.json
## output: stage_artifacts/s3_orthogonality_H_1693_measured.json
##
## 실행: cd "Quant_Module_Moltbot" && Rscript 04_Research/s3_h1693_orthogonality_measure.R
##
## pre-requisite:
##  - 04_Research/strategies/STR_1687/output/daily_returns.csv (Forge S1 산출)
##  - Benchmark strategies daily_returns.csv 각각 EXISTS

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

cat("=== H_1693 STR_1687 S3 Orthogonality Measurement ===\n")
cat("Start:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# ─────────────────────────────────────────────────────
# Step 1: daily_returns 로드 (H_1693 + 5 benchmarks)
# ─────────────────────────────────────────────────────

load_daily_returns <- function(path, label) {
  if (!file.exists(path)) {
    warning(sprintf("File not found: %s (%s)", path, label))
    return(NULL)
  }
  dt <- fread(path)
  # 다양한 return 컬럼명 처리: Return, Strategy_Ret, NAV 등
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

# 실제 존재하는 폴더명 기준 경로 매핑 (Session 68 Day 2 확인)
# STR_1687 → STR_1687_q07_sector_neutral_defense (Forge S1 완료 후 daily_returns.csv 생성 예정)
# STR_1631_SYN_05 → STR_1631/output/daily_nav.csv (Strategy_Ret 컬럼)
# STR_1656_MLRA → STR_1656_MLRA/output/nav_S1_A.csv (Strategy_Ret 컬럼)
# STR_1679v3 → STR_1679_score_blend/output/daily_returns_primary.csv (현재 v2 폴더)
# STR_1689_v1 → STR_1689_quality_aggregate_defense/output/ (Forge S1 완료 후 생성 예정)
strat_paths <- list(
  STR_1687         = "04_Research/strategies/STR_1687_q07_sector_neutral_defense/output/daily_returns.csv",
  STR_1631_SYN_05  = "04_Research/strategies/STR_1631/output/daily_nav.csv",
  STR_1656_MLRA    = "04_Research/strategies/STR_1656_MLRA/output/nav_S1_A.csv",
  STR_1679v3       = "04_Research/strategies/STR_1679_score_blend/output/daily_returns_primary.csv",
  STR_1689_v1      = "04_Research/strategies/STR_1689_quality_aggregate_defense/output/daily_returns.csv"
)

dr_list <- list()
for (nm in names(strat_paths)) {
  dr <- load_daily_returns(strat_paths[[nm]], nm)
  if (!is.null(dr)) dr_list[[nm]] <- dr
}

if (length(dr_list) < 2) stop("daily_returns 로드 실패 — minimum 2 strategies required")

merged <- Reduce(function(x, y) merge(x, y, by = "Date", all = FALSE), dr_list)
cat("Merged data:", nrow(merged), "days,", ncol(merged) - 1, "strategies\n")
cat("Date range:", format(range(merged$Date)), "\n\n")

# ─────────────────────────────────────────────────────
# Step 2: Monthly aggregation (Spearman)
# ─────────────────────────────────────────────────────

merged[, YearMonth := format(Date, "%Y-%m")]
strat_cols <- setdiff(names(merged), c("Date", "YearMonth"))

monthly <- merged[, lapply(.SD, function(x) prod(1 + x) - 1), by = YearMonth, .SDcols = strat_cols]
cat("Monthly aggregation:", nrow(monthly), "months\n\n")

# ─────────────────────────────────────────────────────
# Step 3-4: Pairwise correlation + TDC
# ─────────────────────────────────────────────────────

compute_empirical_tdc <- function(x, y, quantile_threshold = 0.95) {
  # empirical upper tail dependence coefficient
  u <- rank(x) / (length(x) + 1)
  v <- rank(y) / (length(y) + 1)
  q <- quantile_threshold
  upper <- sum(u > q & v > q) / sum(u > q)
  upper
}

primary_pairs <- list(
  c("STR_1687", "STR_1631_SYN_05"),
  c("STR_1687", "STR_1656_MLRA"),
  c("STR_1687", "STR_1679v3"),
  c("STR_1687", "STR_1661_V2"),
  c("STR_1687", "STR_1689_v1")
)

pair_results <- list()
for (pair in primary_pairs) {
  if (!all(pair %in% strat_cols)) {
    cat(sprintf("  SKIP %s (missing strategy)\n", paste(pair, collapse = " vs ")))
    next
  }
  x_daily <- merged[[pair[1]]]
  y_daily <- merged[[pair[2]]]
  x_monthly <- monthly[[pair[1]]]
  y_monthly <- monthly[[pair[2]]]

  pearson_daily <- cor(x_daily, y_daily, use = "pairwise.complete.obs")
  spearman_monthly <- cor(x_monthly, y_monthly, method = "spearman", use = "pairwise.complete.obs")
  tdc_upper <- compute_empirical_tdc(x_daily, y_daily, 0.95)
  tdc_lower <- compute_empirical_tdc(-x_daily, -y_daily, 0.95)

  pair_results[[paste(pair, collapse = "__vs__")]] <- list(
    pair = pair,
    pearson_daily = round(pearson_daily, 4),
    spearman_monthly = round(spearman_monthly, 4),
    tdc_upper_95 = round(tdc_upper, 4),
    tdc_lower_95 = round(tdc_lower, 4),
    n_days = sum(!is.na(x_daily) & !is.na(y_daily)),
    n_months = sum(!is.na(x_monthly) & !is.na(y_monthly)),
    gate_11_verdict = ifelse(max(tdc_upper, tdc_lower) < 0.50, "PASS", "FAIL"),
    sequential_admission_crisis_gate = ifelse(max(tdc_upper, tdc_lower) < 0.30, "PASS", "REVIEW")
  )

  cat(sprintf("  %s vs %s: Pearson=%.3f Spearman=%.3f TDC_upper=%.3f TDC_lower=%.3f Gate11=%s\n",
              pair[1], pair[2], pearson_daily, spearman_monthly, tdc_upper, tdc_lower,
              pair_results[[paste(pair, collapse = "__vs__")]]$gate_11_verdict))
}

# ─────────────────────────────────────────────────────
# Step 5: Regime-conditional TDC (CRISIS subset)
# ─────────────────────────────────────────────────────

regime_path <- file.path(PROJECT_ROOT, ".cache", "unified_regime_signal.parquet")
if (file.exists(regime_path)) {
  regime_dt <- as.data.table(read_parquet(regime_path))
  # 실제 컬럼명: FRED_MRS 또는 MSM_Crisis_Prob (MRS 아님 — 2차 실행 오류 수정)
  regime_col <- intersect(names(regime_dt), c("FRED_MRS", "MSM_Crisis_Prob"))[1]
  if ("Date" %in% names(regime_dt) && !is.na(regime_col)) {
    regime_dt[, Date := as.Date(Date)]
    # MSM_Crisis_Prob은 0~1 확률값 → >=0.5; FRED_MRS는 0~100 점수 → >=30
    threshold <- if (regime_col == "MSM_Crisis_Prob") 0.5 else 30
    regime_dt[, is_crisis := get(regime_col) >= threshold]
    # 월별 신호 → 일별 확장 (YearMonth join)
    regime_dt[, YearMonth := format(Date, "%Y-%m")]
    merged[, YearMonth := format(Date, "%Y-%m")]
    regime_monthly <- regime_dt[, .(YearMonth, is_crisis)]
    merged_regime <- merge(merged, regime_monthly, by = "YearMonth", all.x = TRUE)
    cat("\nCrisis-conditional TDC:\n")
    for (pair in primary_pairs) {
      if (!all(pair %in% strat_cols)) next
      crisis_subset <- merged_regime[is_crisis == TRUE]
      if (nrow(crisis_subset) < 60) {
        cat(sprintf("  %s: insufficient crisis days (%d)\n", paste(pair, collapse = " vs "), nrow(crisis_subset)))
        next
      }
      x_cr <- crisis_subset[[pair[1]]]
      y_cr <- crisis_subset[[pair[2]]]
      tdc_crisis <- compute_empirical_tdc(x_cr, y_cr, 0.95)
      key <- paste(pair, collapse = "__vs__")
      pair_results[[key]]$tdc_crisis_95 <- round(tdc_crisis, 4)
      pair_results[[key]]$n_crisis_days <- nrow(crisis_subset)
      cat(sprintf("  %s vs %s: TDC_crisis=%.3f (n=%d)\n",
                  pair[1], pair[2], tdc_crisis, nrow(crisis_subset)))
    }
  }
} else {
  cat("\nRegime signal not found — skip crisis-conditional TDC\n")
}

# ─────────────────────────────────────────────────────
# Step 7: Aggregate + Save
# ─────────────────────────────────────────────────────

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

novelty_score <- if (length(pair_results) > 0) {
  tdc_max_per_pair <- sapply(pair_results, function(p) max(p$tdc_upper_95, p$tdc_lower_95, p$tdc_crisis_95 %||% 0))
  1 - mean(tdc_max_per_pair, na.rm = TRUE)
} else NA_real_

result <- list(
  artifact_type = "s3_orthogonality_measured",
  hypothesis_id = "H_1693",
  strategy_id = "STR_1687",
  measured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  measured_by = "Scout (s3_h1693_orthogonality_measure.R)",
  n_days = nrow(merged),
  n_months = nrow(monthly),
  date_range = format(range(merged$Date)),
  strategies_loaded = strat_cols,
  pair_results = pair_results,
  novelty_score = round(novelty_score, 4),
  gate_11_overall_pass = all(sapply(pair_results, function(p) p$gate_11_verdict == "PASS")),
  sequential_admission_crisis_summary = sapply(pair_results, function(p) p$sequential_admission_crisis_gate),
  candidate_role_hint = "defense"
)

output_path <- file.path(PROJECT_ROOT, "stage_artifacts", "s3_orthogonality_H_1693_measured.json")
write(toJSON(result, pretty = TRUE, auto_unbox = TRUE, na = "null"), output_path)
cat("\nSaved:", output_path, "\n")
cat("Novelty score:", round(novelty_score, 4), "\n")
cat("Gate 11 overall PASS:", result$gate_11_overall_pass, "\n")
cat("\n=== S3 Measurement Complete ===\n")
