cat("=== TEST-KR-G3-01: 4-Regime x 269 Factor Conditional IC ===\n")
cat("=== 근거: KR-013 (SJM), KR-023 (RSFM), KR-014 (Momentum Regime) ===\n")

# ── 환경 ──────────────────────────────────────────────────────────
suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/factor_db_builder.R")
  source("02_Infrastructure/regime_engine_daily.R")
})
library(data.table)

# ── 1. Regime 데이터 로드 ─────────────────────────────────────────
cat("[G3-01] Step 1: Loading regime data...\n")
regime_path <- file.path(CACHE_DIR, "regime_daily_v2.parquet")
if (!file.exists(regime_path)) {
  cat("  Building regime (2005-01 ~ 2026-03)...\n")
  dates <- seq(as.Date("2005-01-01"), as.Date("2026-03-31"), by = "month")
  build_daily_regime(dates)
}
regime_dt <- arrow::read_parquet(regime_path)
setDT(regime_dt)
regime_dt[, Date := as.Date(Date)]

# MRS 4분위 국면 분류
regime_dt[, regime_q := cut(
  MRS,
  breaks = quantile(MRS, probs = c(0, 0.25, 0.50, 0.75, 1.0), na.rm = TRUE),
  labels = c("CALM", "NORMAL", "CAUTION", "CRISIS"),
  include.lowest = TRUE
)]
cat(sprintf("  Regime distribution:\n"))
print(table(regime_dt$regime_q))

# ── 2. Factor DB 월말 데이터 로드 ──────────────────────────────────
cat("\n[G3-01] Step 2: Loading factor DB month-ends...\n")
all_dates <- sort(unique(regime_dt$Date))
dt_dates <- data.table(Date = all_dates)
dt_dates[, YM := format(Date, "%Y%m")]
month_ends <- dt_dates[, .(Date = max(Date)), by = YM][order(YM)]$Date

# 최근 20년 (2005~2026)
month_ends <- month_ends[month_ends >= as.Date("2005-01-01")]
cat(sprintf("  Month-ends to process: %d\n", length(month_ends)))

# ── 2b. RAWDATA 로드 (수익률 계산용) ──────────────────────────────
cat("[G3-01] Step 2b: Loading RAWDATA...\n")
.load_base_data()
RAWDATA <- .fdb_env$RAWDATA
cat(sprintf("  RAWDATA: %s rows\n", format(nrow(RAWDATA), big.mark = ",")))

# ── 3. 팩터별 IC 계산 (regime 조건부) ──────────────────────────────
cat("\n[G3-01] Step 3: Computing regime-conditional IC...\n")

results <- list()
processed <- 0

for (sig_date in as.character(month_ends)) {
  sig_d <- as.Date(sig_date)

  # Factor DB 로드
  fdb <- tryCatch(
    load_factor_db(sig_d, format = "wide"),
    error = function(e) NULL
  )
  if (is.null(fdb) || nrow(fdb) < 50) next

  # 다음 달 수익률 (t+1 forward return)
  next_month <- month_ends[which(as.character(month_ends) == sig_date) + 1]
  if (is.na(next_month)) next

  # RAWDATA에서 t+1 수익률 계산
  raw <- RAWDATA[Date > sig_d & Date <= next_month,
                          .(Fwd_Ret = sum(Ret, na.rm = TRUE)), by = Ticker]

  merged <- merge(fdb, raw, by = "Ticker", all.x = FALSE)
  if (nrow(merged) < 30) next

  # Regime 매핑 (sig_date 기준 regime)
  regime_row <- regime_dt[Date == sig_d]
  if (nrow(regime_row) == 0) {
    regime_row <- regime_dt[Date <= sig_d][.N]
  }
  if (nrow(regime_row) == 0) next
  current_regime <- as.character(regime_row$regime_q[1])

  # 팩터별 IC 계산
  factor_cols <- setdiff(names(fdb), c("Date", "Ticker", "Fwd_Ret"))
  for (fc in factor_cols) {
    vals <- merged[[fc]]
    if (sum(!is.na(vals)) < 20) next
    ic <- cor(vals, merged$Fwd_Ret, use = "pairwise.complete.obs")
    if (!is.finite(ic)) next

    results[[length(results) + 1]] <- data.table(
      sig_date = sig_d,
      factor_id = fc,
      regime = current_regime,
      ic = ic,
      n_stocks = sum(!is.na(vals))
    )
  }

  processed <- processed + 1
  if (processed %% 20 == 0) {
    cat(sprintf("  Processed %d/%d months\n", processed, length(month_ends)))
  }
}

cat(sprintf("  Total months processed: %d\n", processed))

# ── 4. 집계 ──────────────────────────────────────────────────────
cat("\n[G3-01] Step 4: Aggregating results...\n")
ic_dt <- rbindlist(results)

# 국면별 평균 IC + ICIR
regime_ic <- ic_dt[, .(
  mean_ic = mean(ic, na.rm = TRUE),
  sd_ic = sd(ic, na.rm = TRUE),
  icir = mean(ic, na.rm = TRUE) / (sd(ic, na.rm = TRUE) + 1e-8),
  n_months = .N
), by = .(factor_id, regime)]

# Wide format: factor × regime
regime_ic_wide <- dcast(regime_ic, factor_id ~ regime,
                        value.var = c("mean_ic", "icir", "n_months"))

# Conditional value (CRISIS IC - CALM IC)
if ("mean_ic_CRISIS" %in% names(regime_ic_wide) &&
    "mean_ic_CALM" %in% names(regime_ic_wide)) {
  regime_ic_wide[, conditional_value := mean_ic_CRISIS - mean_ic_CALM]
}

# 전체 기간 IC
all_ic <- ic_dt[, .(
  ic_all = mean(ic, na.rm = TRUE),
  icir_all = mean(ic, na.rm = TRUE) / (sd(ic, na.rm = TRUE) + 1e-8)
), by = factor_id]

final <- merge(regime_ic_wide, all_ic, by = "factor_id")
setorder(final, -conditional_value)

# ── 5. 저장 ──────────────────────────────────────────────────────
out_path <- file.path(CACHE_DIR, "conditional_ic_matrix_4regime.csv")
fwrite(final, out_path)
cat(sprintf("\n[G3-01] Saved: %s (%d factors)\n", out_path, nrow(final)))

# ── 6. 요약 출력 ─────────────────────────────────────────────────
cat("\n=== Top 15 Defense Candidates (highest conditional_value) ===\n")
top_defense <- head(final[!is.na(conditional_value)], 15)
print(top_defense[, .(factor_id, ic_all, icir_all,
                       mean_ic_CALM, mean_ic_CRISIS,
                       conditional_value)])

cat("\n=== Top 15 Core Alpha (highest ic_all) ===\n")
top_core <- head(final[order(-ic_all)], 15)
print(top_core[, .(factor_id, ic_all, icir_all,
                    mean_ic_CALM, mean_ic_CRISIS,
                    conditional_value)])

cat("\n=== Regime Distribution Summary ===\n")
regime_summary <- ic_dt[, .(
  avg_ic = mean(ic, na.rm = TRUE),
  n_factor_months = .N,
  n_months = uniqueN(sig_date)
), by = regime]
print(regime_summary)

cat("\n[G3-01] Complete.\n")
