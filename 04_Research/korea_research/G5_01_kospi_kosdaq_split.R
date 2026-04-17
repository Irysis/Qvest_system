cat("=== TEST-KR-G5-01: KOSPI vs KOSDAQ Factor IC Split ===\n")
cat("=== 근거: KR-002 (소형주 필터), KR-020 (투자자 유형) ===\n")

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/factor_db_builder.R")
})
library(data.table)

# ── 1. RAWDATA + Universe 로드 ────────────────────────────────────
cat("[G5-01] Step 1: Loading RAWDATA + Universe...\n")
.load_base_data()
raw <- copy(.fdb_env$RAWDATA)

# K200/KQ150 태그 (Universe_Support에서)
universe_path <- file.path(CACHE_DIR, "Universe_Support.parquet")
if (file.exists(universe_path)) {
  univ <- arrow::read_parquet(universe_path)
  setDT(univ)
  cat(sprintf("  Universe Support: %d rows\n", nrow(univ)))
} else {
  cat("  [WARN] Universe_Support not found. Using RAWDATA WI26.\n")
  univ <- NULL
}

# ── 2. 월말 IC 계산 (KOSPI/KOSDAQ 분리) ──────────────────────────
cat("[G5-01] Step 2: Computing split IC...\n")

all_dates <- sort(unique(raw$Date))
dt_dates <- data.table(Date = all_dates)
dt_dates[, YM := format(Date, "%Y%m")]
month_ends <- dt_dates[, .(Date = max(Date)), by = YM][order(YM)]$Date
month_ends <- month_ends[month_ends >= as.Date("2005-01-01")]

results <- list()
processed <- 0

for (sig_date in as.character(month_ends)) {
  sig_d <- as.Date(sig_date)

  fdb <- tryCatch(load_factor_db(sig_d, format = "wide"), error = function(e) NULL)
  if (is.null(fdb) || nrow(fdb) < 50) next

  # Forward return
  next_idx <- which(as.character(month_ends) == sig_date) + 1
  if (next_idx > length(month_ends)) next
  next_month <- month_ends[next_idx]

  fwd <- raw[Date > sig_d & Date <= next_month,
             .(Fwd_Ret = sum(Ret, na.rm = TRUE)), by = Ticker]

  merged <- merge(fdb, fwd, by = "Ticker")
  if (nrow(merged) < 30) next

  # 시장 구분 (Ticker: A0xxxxx=KOSPI, A1~A9xxxxx=KOSDAQ)
  merged[, market := fifelse(
    substr(Ticker, 2, 2) == "0",
    "KOSPI", "KOSDAQ"
  )]

  factor_cols <- setdiff(names(fdb), c("Date", "Ticker"))

  for (mkt in c("KOSPI", "KOSDAQ", "ALL")) {
    sub <- if (mkt == "ALL") merged else merged[market == mkt]
    if (nrow(sub) < 20) next

    for (fc in factor_cols) {
      vals <- sub[[fc]]
      if (sum(!is.na(vals)) < 15) next
      ic_val <- cor(vals, sub$Fwd_Ret, use = "pairwise.complete.obs")
      if (!is.finite(ic_val)) next

      results[[length(results) + 1]] <- data.table(
        sig_date = sig_d,
        factor_id = fc,
        market = mkt,
        ic = ic_val,
        n_stocks = sum(!is.na(vals))
      )
    }
  }

  processed <- processed + 1
  if (processed %% 20 == 0) {
    cat(sprintf("  Processed %d months\n", processed))
  }
}

# ── 3. 집계 ──────────────────────────────────────────────────────
cat("[G5-01] Step 3: Aggregating...\n")
ic_dt <- rbindlist(results)

split_ic <- ic_dt[, .(
  mean_ic = mean(ic, na.rm = TRUE),
  sd_ic = sd(ic, na.rm = TRUE),
  icir = mean(ic, na.rm = TRUE) / (sd(ic, na.rm = TRUE) + 1e-8),
  n_months = uniqueN(sig_date)
), by = .(factor_id, market)]

split_wide <- dcast(split_ic, factor_id ~ market,
                    value.var = c("mean_ic", "icir"))

cat(sprintf("  dcast columns: %s\n", paste(names(split_wide), collapse = ", ")))
if ("mean_ic_KOSPI" %in% names(split_wide) &&
    "mean_ic_KOSDAQ" %in% names(split_wide)) {
  split_wide[, ic_diff := mean_ic_KOSDAQ - mean_ic_KOSPI]
} else {
  split_wide[, ic_diff := 0]
  cat("  [WARN] KOSPI/KOSDAQ columns missing, ic_diff set to 0\n")
}

setorder(split_wide, -ic_diff)

# ── 4. 저장 ──────────────────────────────────────────────────────
out_path <- file.path(CACHE_DIR, "factor_ic_kospi_kosdaq_split.csv")
fwrite(split_wide, out_path)
cat(sprintf("\n[G5-01] Saved: %s (%d factors)\n", out_path, nrow(split_wide)))

# ── 5. 요약 ──────────────────────────────────────────────────────
cat("\n=== Top 10 KOSDAQ-Dominant Factors (IC_KOSDAQ >> IC_KOSPI) ===\n")
print_cols <- intersect(c("factor_id", "mean_ic_ALL", "mean_ic_KOSPI",
                           "mean_ic_KOSDAQ", "ic_diff"), names(split_wide))
print(head(split_wide[, ..print_cols], 10))

cat("\n=== Top 10 KOSPI-Dominant Factors ===\n")
print(tail(split_wide[, ..print_cols], 10))

cat("\n[G5-01] Complete.\n")
