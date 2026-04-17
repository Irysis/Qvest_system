cat("=== Forge 2: Marginal IC Screening — 미사용 팩터 탐색 ===\n")
cat("## S0 Track 1: Factor DB 미사용 팩터 marginal contribution 스크리닝\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

# ---- Setup ----
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_research_pipeline.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

# ---- Step 1: Grade A에서 사용된 25개 팩터 정의 ----
grade_a_factors <- c(
  "D01_IdioVol", "D02_Beta", "M01_Mom_12_1", "M07_IndMom", "M08_Residual_Mom",
  "M11_ST_Reversal", "C01_SUE", "C02_EPS_Chg_1m", "C03_EPS_Chg_3m", "C04_ESBR",
  "C06_TP_Gap", "C08_Coverage", "C13_Revision_Breadth_3m", "C17_OP_Revision",
  "V04_fPER", "Q04_Piotroski_F", "Q06_Asset_Growth", "Q12_Asset_Turnover",
  "Q28_Cash_Conversion", "Q29_Inventory_Turnover", "Q02_ROE", "Q10_Gross_Margin",
  "D47_CVaR_5pct", "SE01_Consensus_Dispersion", "M26_Revenue_Mom"
)
cat("[Step 1] Grade A 사용 팩터:", length(grade_a_factors), "개\n")

# ---- Step 2: IC 시계열 로드 (PIT: Usable_Date 기준) ----
sig_date <- as.Date("2026-02-28")  # 최신 available
ic_hist <- as.data.table(read_parquet(
  file.path(CACHE_DIR, "factor_db/factor_ic_monthly.parquet")
))
ic_hist[, Date := as.Date(Date)]
ic_hist[, Usable_Date := as.Date(Usable_Date)]
ic_hist <- ic_hist[Usable_Date <= sig_date]

all_factors <- unique(ic_hist$Factor_Name)
cat("[Step 2] IC 시계열 팩터:", length(all_factors), "개\n")

# Grade A 팩터의 IC 시계열 로드
grade_a_ic <- ic_hist[Factor_Name %in% grade_a_factors]
cat("[Step 2] Grade A IC 관측치:", nrow(grade_a_ic), "개\n")

# 미사용 팩터 목록
unused_factors <- setdiff(all_factors, grade_a_factors)
cat("[Step 2] 미사용 팩터:", length(unused_factors), "개\n\n")

# ---- Step 3: 263개 미사용 팩터 IC_marginal 배치 계산 ----
cat("[Step 3] IC_marginal 배치 계산 시작...\n")

# Grade A IC 시계열 → wide 형태 (Date × Factor)
ga_wide <- dcast(grade_a_ic, Date ~ Factor_Name, value.var = "IC")
ga_dates <- ga_wide$Date
ga_mat <- as.matrix(ga_wide[, -1, with = FALSE])

results <- rbindlist(lapply(seq_along(unused_factors), function(i) {
  fn <- unused_factors[i]
  if (i %% 50 == 0) cat(sprintf("  [%d/%d] %s\n", i, length(unused_factors), fn))

  new_ts <- ic_hist[Factor_Name == fn, .(Date, IC)]
  if (nrow(new_ts) < 24) return(NULL)

  # IC_raw: expanding mean IC
  ic_raw <- mean(new_ts$IC, na.rm = TRUE)

  # Merge with Grade A dates
  merged <- merge(new_ts, ga_wide, by = "Date")
  if (nrow(merged) < 24) {
    return(data.table(Factor_Name = fn, IC_Raw = ic_raw, IC_Marginal = ic_raw,
                      IC_Explained = 0, N_Months = nrow(new_ts), Passes = ic_raw > 0.005))
  }

  # β_i = corr(new IC, grade_a_factor_i IC) across time
  ga_cols <- setdiff(names(merged), c("Date", "IC"))
  betas <- sapply(ga_cols, function(gc) {
    valid <- !is.na(merged[[gc]]) & !is.na(merged$IC)
    if (sum(valid) < 12) return(0)
    cor(merged$IC[valid], merged[[gc]][valid], use = "complete.obs")
  })

  # Grade A 각 팩터의 mean IC (같은 기간)
  ga_mean_ic <- sapply(ga_cols, function(gc) {
    mean(merged[[gc]], na.rm = TRUE)
  })

  # IC_explained = Σ(β_i × IC_i)
  ic_explained <- sum(betas * ga_mean_ic, na.rm = TRUE)
  ic_marginal <- ic_raw - ic_explained

  data.table(
    Factor_Name = fn,
    IC_Raw = round(ic_raw, 6),
    IC_Marginal = round(ic_marginal, 6),
    IC_Explained = round(ic_explained, 6),
    N_Months = nrow(new_ts),
    Passes = ic_marginal > 0.005
  )
}))

cat(sprintf("\n[Step 3] 계산 완료: %d개 팩터\n", nrow(results)))
cat(sprintf("[Step 3] IC_Marginal > 0.005 통과: %d개\n", sum(results$Passes)))

# 결과 정렬
setorder(results, -IC_Marginal)
cat("\n[Step 3] Top 20 Marginal IC:\n")
print(head(results, 20))

# ---- Step 4: 통과 팩터 추출 ----
passing <- results[Passes == TRUE]
cat(sprintf("\n[Step 4] 통과 팩터 %d개:\n", nrow(passing)))
print(passing[, .(Factor_Name, IC_Raw, IC_Marginal, N_Months)])

# ---- Step 5: 직교성 상위 10개 팩터 orthogonality 분석 ----
cat("\n[Step 5] 직교성 분석 — Top 10 by IC_Marginal\n")
top10 <- head(passing, 10)

ortho_results <- rbindlist(lapply(seq_len(nrow(top10)), function(i) {
  fn <- top10$Factor_Name[i]
  cat(sprintf("  [%d/10] %s orthogonality...\n", i, fn))

  # 최신 sig_date에서 Z_Score 로드
  fdt <- tryCatch(load_month_factors(sig_date, coverage_min = 0.01), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) {
    return(data.table(Factor_Name = fn, Max_Abs_Corr = NA, Independence = "unknown",
                      Most_Correlated_With = NA, N_Compared = 0))
  }

  new_z <- fdt[Factor_Name == fn]
  if (nrow(new_z) < 30) {
    return(data.table(Factor_Name = fn, Max_Abs_Corr = NA, Independence = "unknown",
                      Most_Correlated_With = NA, N_Compared = 0))
  }

  # Grade A 팩터만 로드해서 비교
  ga_z <- fdt[Factor_Name %in% grade_a_factors]
  if (nrow(ga_z) == 0) {
    return(data.table(Factor_Name = fn, Max_Abs_Corr = 0, Independence = "independent",
                      Most_Correlated_With = NA, N_Compared = 0))
  }

  ga_wide_z <- dcast(ga_z, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  new_dt <- new_z[, .(Ticker, New_Z = Z_Score_Aligned)]
  merged_z <- merge(ga_wide_z, new_dt, by = "Ticker")

  if (nrow(merged_z) < 30) {
    return(data.table(Factor_Name = fn, Max_Abs_Corr = NA, Independence = "unknown",
                      Most_Correlated_With = NA, N_Compared = 0))
  }

  ga_cols <- setdiff(names(merged_z), c("Ticker", "New_Z"))
  corrs <- sapply(ga_cols, function(gc) {
    valid <- !is.na(merged_z[[gc]]) & !is.na(merged_z$New_Z)
    if (sum(valid) < 20) return(NA_real_)
    cor(merged_z[[gc]][valid], merged_z$New_Z[valid], method = "spearman")
  })
  corrs <- corrs[!is.na(corrs)]

  if (length(corrs) == 0) {
    return(data.table(Factor_Name = fn, Max_Abs_Corr = 0, Independence = "independent",
                      Most_Correlated_With = NA, N_Compared = 0))
  }

  max_idx <- which.max(abs(corrs))
  max_abs <- abs(corrs[max_idx])
  indep <- if (max_abs < 0.3) "independent" else if (max_abs < 0.6) "partial" else "redundant"

  data.table(
    Factor_Name = fn,
    Max_Abs_Corr = round(max_abs, 3),
    Independence = indep,
    Most_Correlated_With = names(corrs)[max_idx],
    N_Compared = length(corrs)
  )
}))

cat("\n[Step 5] Orthogonality Results:\n")
print(ortho_results)

# ---- Step 6: JSON 저장 ----
final_top10 <- merge(top10, ortho_results, by = "Factor_Name", all.x = TRUE)
setorder(final_top10, -IC_Marginal)

output <- list(
  version = "1.0",
  generated = as.character(Sys.time()),
  sig_date = as.character(sig_date),
  grade_a_factors_count = length(grade_a_factors),
  unused_factors_screened = length(unused_factors),
  passing_threshold = 0.005,
  n_passing = nrow(passing),
  passing_factors = as.list(passing),
  top10_with_orthogonality = as.list(final_top10),
  all_results = as.list(results)
)

outpath <- "04_Research/strategy_distill/marginal_screening.json"
write_json(output, outpath, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[Step 6] 저장 완료: %s\n", outpath))

# ---- Step 7: 텔레그램 보고 ----
tryCatch({
  source("02_Infrastructure/config.R")

  msg_lines <- c(
    "📊 [Forge 2] Marginal IC Screening 완료",
    "",
    sprintf("스크리닝: %d개 미사용 팩터 (Grade A 사용 %d개 대비)",
            length(unused_factors), length(grade_a_factors)),
    sprintf("IC_Marginal > 0.005 통과: %d개", nrow(passing)),
    "",
    "🏆 Top 10 (IC_Marginal | Independence):"
  )

  for (i in seq_len(nrow(final_top10))) {
    r <- final_top10[i]
    msg_lines <- c(msg_lines, sprintf(
      "%d. %s: %.4f | %s (max_corr=%.2f vs %s)",
      i, r$Factor_Name, r$IC_Marginal,
      ifelse(is.na(r$Independence), "?", r$Independence),
      ifelse(is.na(r$Max_Abs_Corr), 0, r$Max_Abs_Corr),
      ifelse(is.na(r$Most_Correlated_With), "-", r$Most_Correlated_With)
    ))
  }

  msg_lines <- c(msg_lines, "",
    "→ Scout 가설 3 입력용 데이터.",
    "→ independent + IC_Marginal 높은 팩터 = 신규 alpha source 후보"
  )

  msg <- paste(msg_lines, collapse = "\n")
  tg_send(msg)
  cat("\n[Step 7] 텔레그램 발송 완료\n")
}, error = function(e) {
  cat(sprintf("\n[Step 7] 텔레그램 발송 실패: %s\n", e$message))
})

cat("\n=== Forge 2: Marginal IC Screening 완료 ===\n")
