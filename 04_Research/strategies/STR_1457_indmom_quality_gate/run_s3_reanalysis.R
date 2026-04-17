## STR_1457: S3 Orthogonality Re-analysis (Post-S5 M1 Relaxed Gate)
## Scout: GATE_PERCENTILE 0.50 -> 0.20 변경 후 직교성 재검증
## Date: 2026-03-26

cat("=== STR_1457: S3 Orthogonality Re-analysis (Post-S5 M1) ===\n")

# ---- Setup ----
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
INFRA_DIR <- file.path(PROJECT_ROOT, "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

# ---- Constants ----
LIQ_THRESHOLD <- 2e8

# ---- Load RAWDATA ----
cat("[S3] Loading RAWDATA...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT

# ---- Run factor_engine to get FACTORS ----
cat("[S3] Running factor_engine.R (S5 M1: gate 0.20)...\n")
source(file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1457_indmom_quality_gate/factor_engine.R"))

# ---- Extract latest signal date's Z-scores ----
latest_date <- max(FACTORS$Date)
cat(sprintf("[S3] Latest signal date: %s\n", latest_date))

latest_scores <- FACTORS[Date == latest_date, .(Ticker, Score)]
new_factor_z <- setNames(latest_scores$Score, latest_scores$Ticker)
cat(sprintf("[S3] N stocks in latest signal: %d\n", length(new_factor_z)))

# ---- Inline orthogonality computation (avoids re-source encoding issue) ----
cat("[S3] Computing orthogonality vs Factor DB...\n")

# Load existing DB factors for latest_date (connector already sourced)
fdt <- load_month_factors(latest_date, coverage_min = 0.01)
cat(sprintf("[S3] Loaded %d factor-ticker rows, %d unique factors\n",
            nrow(fdt), uniqueN(fdt$Factor_Name)))

# Pivot to wide: Ticker x Factor
fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

# Merge with new factor
new_dt <- data.table(Ticker = names(new_factor_z), New_Z = as.numeric(new_factor_z))
merged <- merge(fdt_wide, new_dt, by = "Ticker")
cat(sprintf("[S3] Merged: %d stocks with both new + DB factors\n", nrow(merged)))

# Exclude component factors from comparison (M07_IndMom is the Score itself)
COMPONENT_FACTORS <- c("M07_IndMom", "Q07_Earnings_Stability")
factor_cols <- setdiff(names(merged), c("Ticker", "New_Z", COMPONENT_FACTORS))
cat(sprintf("[S3] Excluding components: %s\n", paste(COMPONENT_FACTORS, collapse = ", ")))
cat(sprintf("[S3] Comparing against %d non-component factors\n", length(factor_cols)))
corr_list <- lapply(factor_cols, function(fc) {
  valid <- !is.na(merged[[fc]]) & !is.na(merged$New_Z)
  if (sum(valid) < 20) return(data.table(Factor_Name = fc, Corr = NA_real_))
  data.table(
    Factor_Name = fc,
    Corr = cor(merged[[fc]][valid], merged$New_Z[valid], method = "spearman")
  )
})
pairwise <- rbindlist(corr_list)
pairwise <- pairwise[!is.na(Corr)]

# Max correlation
max_idx <- which.max(abs(pairwise$Corr))
max_corr <- abs(pairwise$Corr[max_idx])
max_factor <- pairwise$Factor_Name[max_idx]

# Independence classification
independence <- ifelse(max_corr < 0.3, "independent",
                       ifelse(max_corr < 0.6, "partial", "redundant"))

# Category-level max
pairwise[, Category := gsub("^([A-Z]+)\\d+.*", "\\1", Factor_Name)]
cat_corr <- pairwise[, .(Max_Corr = max(abs(Corr), na.rm = TRUE)), by = Category]
setorder(cat_corr, -Max_Corr)

cat(sprintf("[S3] Max abs corr: %.3f (vs %s)\n", max_corr, max_factor))
cat(sprintf("[S3] Independence: %s\n", independence))
cat(sprintf("[S3] N factors compared: %d\n", nrow(pairwise)))

# ---- Top 10 most correlated ----
top10 <- pairwise[order(-abs(Corr))][1:min(10, nrow(pairwise))]
cat("\n[S3] Top 10 most correlated factors:\n")
for (j in seq_len(nrow(top10))) {
  cat(sprintf("  %2d. %s: %.3f\n", j, top10$Factor_Name[j], top10$Corr[j]))
}

# ---- Category-level correlations ----
cat("\n[S3] Category-level max correlations:\n")
for (j in seq_len(nrow(cat_corr))) {
  cat(sprintf("  %s: %.3f\n", cat_corr$Category[j], cat_corr$Max_Corr[j]))
}

# ---- Multi-date robustness (last 6 months) ----
cat("\n[S3] Multi-date robustness check (last 6 months)...\n")
all_dates <- sort(unique(FACTORS$Date), decreasing = TRUE)
check_dates <- all_dates[seq_len(min(6, length(all_dates)))]

multi_results <- lapply(check_dates, function(d) {
  scores_d <- FACTORS[Date == d, .(Ticker, Score)]
  z_d <- setNames(scores_d$Score, scores_d$Ticker)
  if (length(z_d) < 30) return(NULL)

  fdt_d <- tryCatch(load_month_factors(d, coverage_min = 0.01), error = function(e) NULL)
  if (is.null(fdt_d) || nrow(fdt_d) == 0) return(NULL)

  fdt_w <- dcast(fdt_d, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  new_d <- data.table(Ticker = names(z_d), New_Z = as.numeric(z_d))
  m_d <- merge(fdt_w, new_d, by = "Ticker")
  if (nrow(m_d) < 30) return(NULL)

  fc_d <- setdiff(names(m_d), c("Ticker", "New_Z", COMPONENT_FACTORS))
  corrs_d <- sapply(fc_d, function(fc) {
    v <- !is.na(m_d[[fc]]) & !is.na(m_d$New_Z)
    if (sum(v) < 20) return(NA_real_)
    cor(m_d[[fc]][v], m_d$New_Z[v], method = "spearman")
  })
  corrs_d <- corrs_d[!is.na(corrs_d)]
  if (length(corrs_d) == 0) return(NULL)

  mx <- which.max(abs(corrs_d))
  data.table(
    Date = d,
    max_corr = abs(corrs_d[mx]),
    max_factor = names(corrs_d)[mx],
    independence = ifelse(abs(corrs_d[mx]) < 0.3, "independent",
                          ifelse(abs(corrs_d[mx]) < 0.6, "partial", "redundant")),
    n_stocks = length(z_d)
  )
})
multi_dt <- rbindlist(multi_results[!sapply(multi_results, is.null)])

if (nrow(multi_dt) > 0) {
  cat("[S3] Multi-date results:\n")
  print(multi_dt)
  avg_max_corr <- mean(multi_dt$max_corr, na.rm = TRUE)
  cat(sprintf("[S3] Average max_abs_corr across dates: %.3f\n", avg_max_corr))
} else {
  avg_max_corr <- max_corr
  cat("[S3] Multi-date: single date only\n")
}

# ---- Comparison with pre-S5 ----
cat("\n[S3] Comparison with pre-S5 orthogonality:\n")
cat("  Pre-S5 (gate 0.50): max_abs_corr = 0.198, vs M03_Mom_3_1, independent\n")
cat(sprintf("  Post-S5 (gate 0.20): max_abs_corr = %.3f, vs %s, %s\n",
            max_corr, max_factor, independence))

# ---- Save S3 artifact ----
cat("\n[S3] Saving s3_orthogonality artifact...\n")

scout_note <- sprintf(
  paste0(
    "S5 M1(gate 0.50->0.20) 후 재분석. max_abs_corr %.3f(vs %s). ",
    "Pre-S5 0.198 대비 %s. Independence: %s. ",
    "Gate 완화로 종목 풀 확대(~%d stocks) → momentum 신호 순도 변화 확인. ",
    "Multi-date avg: %.3f. %s"
  ),
  max_corr, max_factor,
  ifelse(max_corr > 0.198, "상승(모멘텀 노출 증가)", "유지/감소(직교성 보존)"),
  independence,
  length(new_factor_z),
  avg_max_corr,
  ifelse(independence == "independent", "독립성 유지 — S4 재평가 가능.",
         "직교성 약화 — 추가 mutation 검토 필요.")
)

s3_artifact <- list(
  factor_id = "MF07_MomQualGate",
  strategy_id = "STR_1457",
  stage = "S3_post_s5_m1",
  components = list("M07_IndMom", "Q07_Earnings_Stability (gate, relaxed 0.20)"),
  max_abs_corr_db = max_corr,
  most_correlated_factor = max_factor,
  top5_corr = as.list(setNames(
    top10$Corr[1:min(5, nrow(top10))],
    top10$Factor_Name[1:min(5, nrow(top10))]
  )),
  category_max_corr = as.list(setNames(cat_corr$Max_Corr, cat_corr$Category)),
  independence_class = independence,
  value_matrix_cell = paste0(
    ifelse(max_corr < 0.3, "Independent", ifelse(max_corr < 0.6, "Partial", "Redundant")),
    "_PostS5M1"
  ),
  n_compared = nrow(pairwise),
  n_months_analyzed = nrow(multi_dt),
  avg_max_corr_multidate = avg_max_corr,
  gate_change = "0.50 -> 0.20 (S5 M1 relaxed)",
  pre_s5_max_corr = 0.198,
  pre_s5_most_correlated = "M03_Mom_3_1",
  computed_date = as.character(Sys.Date()),
  scout_note = scout_note
)

artifact_path <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1457_indmom_quality_gate/stage_artifacts",
  "s3_orthogonality_MF07_MomQualGate.json")
jsonlite::write_json(s3_artifact, artifact_path, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[S3] Artifact saved: %s\n", artifact_path))

# ---- Summary ----
cat("\n========================================\n")
cat("[Scout] S3 직교성 재분석 완료\n")
cat(sprintf("  max_abs_corr: %.3f (vs %s)\n", max_corr, max_factor))
cat(sprintf("  independence: %s\n", independence))
cat(sprintf("  pre-S5 vs post-S5: %.3f -> %.3f\n", 0.198, max_corr))
cat(sprintf("  n_stocks: %d | n_compared: %d\n", length(new_factor_z), nrow(pairwise)))
cat("========================================\n")
