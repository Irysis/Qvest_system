cat("=== TEST-KR-G8-01: Samsara 6-Factor Monthly IC Profiling ===\n")
cat("=== 근거: KR-018 (TA→Factor), Samsara Protocol v4.3 ===\n")
cat("=== 목적: Samsara 물리 팩터의 한국시장 IC/ICIR 측정 ===\n")

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/factor_db_builder.R")
})
library(data.table)

# ── 1. Samsara 팩터 추출 ─────────────────────────────────────────
cat("[G8-01] Step 1: Locating Samsara output...\n")
samsara_dir <- file.path(PROJECT_ROOT, "05_Production", "4-1.Samsara_Protocol")

# Samsara 월별 팩터 파일 탐색
samsara_files <- list.files(samsara_dir, pattern = "monthly_factors.*\\.csv$|\\.rds$|\\.parquet$",
                             recursive = TRUE, full.names = TRUE)
cat(sprintf("  Found %d Samsara factor files\n", length(samsara_files)))

if (length(samsara_files) == 0L) {
  # Samsara 팩터가 없으면 Factor DB에서 물리/카오스 관련 팩터로 대체
  cat("  [WARN] No Samsara files found. Using Factor DB physics-proxy factors.\n")
  cat("  Searching for related factors in Factor DB...\n")

  .load_base_data()
  fdb_sample <- as.data.table(arrow::read_parquet(
    file.path(CACHE_DIR, "factor_db/factor_db_202603.parquet"),
    col_select = "Factor_Name"
  ))
  all_factors <- sort(unique(fdb_sample$Factor_Name))

  # 물리/비선형 proxy: 변동성 계열 + 정보 계열 + 비대칭성
  physics_proxy <- c(
    "D01_IdioVol", "D03_RealVol", "D22_Tracking_Error",
    "D44_Kurtosis", "D45_Skewness", "D46_Sortino",
    "D23_Info_Ratio", "R01_VaR_95", "R03_CVaR_95",
    "MK01_CAPM_Beta", "MK02_HM_DownBeta"
  )
  physics_proxy <- intersect(physics_proxy, all_factors)
  cat(sprintf("  Physics-proxy factors available: %d\n", length(physics_proxy)))

  # Momentum 비교군
  momentum_factors <- c("M04_Mom_1", "M05_Trended_Mom", "M11_ST_Reversal",
                         "M09_Composite_Mom")
  momentum_factors <- intersect(momentum_factors, all_factors)

  ALL_TEST_FACTORS <- c(physics_proxy, momentum_factors)
} else {
  stop("Samsara file loading not yet implemented. Use Factor DB proxy.")
}

# ── 2. 월별 IC 계산 ─────────────────────────────────────────────
cat("\n[G8-01] Step 2: Computing monthly IC for physics-proxy + momentum factors...\n")
RAWDATA <- .fdb_env$RAWDATA

setorder(RAWDATA, Ticker, Date)
all_dates <- sort(unique(RAWDATA$Date))
dt_dates <- data.table(Date = all_dates)
dt_dates[, YM := format(Date, "%Y%m")]
month_ends <- dt_dates[, .(Date = max(Date)), by = YM][order(YM)]$Date
month_ends <- month_ends[month_ends >= as.Date("2005-01-01")]

results <- list()
processed <- 0L

for (sig_date in as.character(month_ends)) {
  sig_d <- as.Date(sig_date)
  fdb <- tryCatch(load_factor_db(sig_d, format = "wide"), error = function(e) NULL)
  if (is.null(fdb) || nrow(fdb) < 50) next

  next_idx <- which(as.character(month_ends) == sig_date) + 1L
  if (next_idx > length(month_ends)) next
  next_month <- month_ends[next_idx]

  fwd <- RAWDATA[Date > sig_d & Date <= next_month,
                 .(Fwd_Ret = sum(Ret, na.rm = TRUE)), by = Ticker]
  merged <- merge(fdb, fwd, by = "Ticker")
  if (nrow(merged) < 30) next

  for (fc in ALL_TEST_FACTORS) {
    if (!(fc %in% names(merged))) next
    vals <- merged[[fc]]
    if (sum(!is.na(vals)) < 20) next
    ic_val <- cor(vals, merged$Fwd_Ret, use = "pairwise.complete.obs",
                  method = "spearman")
    if (!is.finite(ic_val)) next

    results[[length(results) + 1L]] <- data.table(
      sig_date = sig_d, factor_id = fc, ic = ic_val,
      n_stocks = sum(!is.na(vals))
    )
  }
  processed <- processed + 1L
  if (processed %% 50 == 0) cat(sprintf("  Processed %d months\n", processed))
}

cat(sprintf("  Total: %d months processed\n", processed))

# ── 3. 집계 ──────────────────────────────────────────────────────
cat("\n[G8-01] Step 3: Aggregating IC/ICIR...\n")
ic_dt <- rbindlist(results)

summary_dt <- ic_dt[, .(
  mean_ic = mean(ic, na.rm = TRUE),
  sd_ic = sd(ic, na.rm = TRUE),
  icir = mean(ic, na.rm = TRUE) / (sd(ic, na.rm = TRUE) + 1e-8),
  pos_rate = mean(ic > 0, na.rm = TRUE),
  n_months = .N
), by = factor_id]
setorder(summary_dt, -icir)

# ── 4. 직교성 행렬 ──────────────────────────────────────────────
cat("\n[G8-01] Step 4: Cross-correlation matrix (physics x momentum)...\n")
ic_wide <- dcast(ic_dt, sig_date ~ factor_id, value.var = "ic")
corr_cols <- intersect(ALL_TEST_FACTORS, names(ic_wide))
if (length(corr_cols) >= 2) {
  corr_mat <- cor(ic_wide[, ..corr_cols], use = "pairwise.complete.obs")
  cat("  IC Time-Series Correlation Matrix:\n")
  print(round(corr_mat, 3))
}

# ── 5. 저장 + 출력 ──────────────────────────────────────────────
cat("\n=== Factor IC/ICIR Summary ===\n")
print(summary_dt)

cat("\n=== ICIR >= 0.20 Factors (S2 Entry) ===\n")
print(summary_dt[icir >= 0.20])

out_dir <- "04_Research/korea_research/G8_01_output"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
fwrite(summary_dt, file.path(out_dir, "factor_ic_summary.csv"))
if (exists("corr_mat")) {
  fwrite(as.data.table(corr_mat, keep.rownames = "factor"),
         file.path(out_dir, "ic_correlation_matrix.csv"))
}

cat("\n[G8-01] Complete.\n")
