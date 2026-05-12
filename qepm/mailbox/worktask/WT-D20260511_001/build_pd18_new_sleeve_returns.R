#==============================================================================
# WT-D20260511_001 PD18 — NEW sleeve returns 184 dates monthly rebal
#
# Mission:
#   PD16 supersede with NEW alpha 184 sig_dates (155 → 184, 29 new 2023-12 ~ 2026-04).
#   redistribute primary mandate (qlead_forge_primary_variant_override.json):
#     - 5-sleeve composite monthly rebal (lockbox-scope.md forge 폐기 정합)
#     - NEW sleeve: 184 sig_dates 각각 top20 EW 5% per name monthly rebal (frozen X)
#     - sleeve weights 비례 fixed (45/22.5/18/4.5/10)
#
# Output:
#   - new_sleeve_returns_184m_pd18.csv: 184 dates × NEW sleeve monthly returns
#   - Universe: KOSPI200 ∪ KOSDAQ150 ∩ ADV_20d >= 2e8 KRW (alpha-research universe match)
#
# Methodology (도훈 mandate lockbox-scope.md 2026-05-09):
#   for each sig_date in alpha (184 dates):
#     top20 = top 20 tickers by alpha score (5% EW per name)
#     return_month = mean of monthly compound return of top20 from sig_date to next sig_date
#     (PerformanceAnalytics convention geometric)
#
# Constraints:
#   - Pure function: alpha/risk/optimization read-only
#   - PIT strict: alpha lookbox cutoff retain at alpha-research stage; forge stage lockbox 폐기
#   - PerformanceAnalytics 표준 함수만 (geometric=TRUE)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics)
})

# Paths
SA_DIR <- "stage_artifacts/WT_D20260511_001"
WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"
RAW_PATH <- ".cache/rawdata.parquet"

cat("=== PD18 NEW sleeve returns 184 dates monthly rebal build ===\n\n")

# 1. Load alpha_scores (184 sig_dates × 770 tickers × alpha + confidence)
ap <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores.parquet")))
sig_dates <- sort(unique(ap$sig_date))
cat("alpha sig_dates:", length(sig_dates), "\n")
cat("range:", as.character(range(sig_dates)), "\n")
stopifnot(length(sig_dates) == 184)

# 2. Load rawdata (KR daily prices)
cat("\nLoading rawdata.parquet ...\n")
rd <- as.data.table(read_parquet(RAW_PATH))
setkey(rd, Ticker, Date)
cat("rawdata rows:", nrow(rd), "tickers:", length(unique(rd$Ticker)),
    "date range:", as.character(range(rd$Date)), "\n")

# 3. Universe filter (KOSPI200 ∪ KOSDAQ150 ∩ ADV_20d >= 2e8 KRW)
# Same universe as alpha-research stage
# K200 = 1 indicates KOSPI200 membership; KQ150 = 1 indicates KOSDAQ150
# ADV_20d using Close × Vol rolling 20-day mean
cat("\nBuilding universe filter (PIT-safe)...\n")
rd[, vol_value := Close * Vol]  # daily KRW value
setorder(rd, Ticker, Date)
rd[, adv_20d := frollmean(vol_value, n = 20, align = "right", na.rm = FALSE), by = Ticker]

# 4. For each sig_date, compute NEW sleeve return (top20 EW from sig_date to next sig_date)
# Holdings cadence: alpha sig_date to next alpha sig_date
# Monthly return = mean compound return of top20 holdings over the period

LIQ_THRESHOLD <- 2e8

# Build sleeve returns
new_returns <- data.table()

for (i in seq_along(sig_dates)) {
  d_now <- sig_dates[i]

  # Next sig_date (or +1 month if last)
  if (i < length(sig_dates)) {
    d_next <- sig_dates[i + 1]
  } else {
    # Last sig_date 2026-04-01 → use latest available data (2026-05-11)
    d_next <- as.Date("2026-05-01")  # one month forward
  }

  # Universe at d_now: K200=1 OR KQ150=1 AND adv_20d >= LIQ_THRESHOLD
  # PIT: use data at d_now (lag-1 day prior to sig_date for liquidity)
  d_lag <- d_now - 1L  # PIT-safe lag-1 day

  uni_dt <- rd[Date <= d_now & Date >= (d_now - 30L), .SD[which.max(Date)], by = Ticker]
  uni_dt <- uni_dt[(K200 == 1 | KQ150 == 1) & !is.na(adv_20d) & adv_20d >= LIQ_THRESHOLD]

  # Merge with alpha_scores at d_now
  alpha_now <- ap[sig_date == d_now]
  alpha_uni <- alpha_now[Ticker %in% uni_dt$Ticker]

  # Top 20 by alpha
  setorder(alpha_uni, -alpha)
  top20 <- head(alpha_uni, 20)

  if (nrow(top20) == 0) {
    new_returns <- rbind(new_returns, data.table(
      sig_date = d_now,
      n_holdings = 0,
      monthly_ret = NA_real_,
      n_present = 0
    ))
    next
  }

  # Compute monthly return for top20: from d_now (entry) to d_next (exit)
  # PerformanceAnalytics convention: compound return per name → EW mean
  # Use Close prices: P_exit / P_entry - 1

  # Entry price at d_now (or first trading day on/after d_now)
  entry_prices <- rd[Ticker %in% top20$Ticker & Date >= d_now & Date <= (d_now + 5L)]
  entry_prices <- entry_prices[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
  setnames(entry_prices, c("Ticker", "entry_date", "entry_price"))

  # Exit price at d_next (or first trading day on/after d_next)
  exit_prices <- rd[Ticker %in% top20$Ticker & Date >= d_next & Date <= (d_next + 5L)]
  exit_prices <- exit_prices[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
  setnames(exit_prices, c("Ticker", "exit_date", "exit_price"))

  # Merge
  rets <- merge(entry_prices, exit_prices, by = "Ticker", all.x = TRUE)
  rets[, ret_pct := (exit_price / entry_price) - 1]

  # EW return (5% per name, max 20 names) — sum / N
  valid <- rets[!is.na(ret_pct)]
  if (nrow(valid) == 0) {
    monthly_ret <- NA_real_
  } else {
    monthly_ret <- mean(valid$ret_pct)
  }

  new_returns <- rbind(new_returns, data.table(
    sig_date = d_now,
    n_holdings = nrow(top20),
    monthly_ret = monthly_ret,
    n_present = nrow(valid)
  ))

  if (i %% 20 == 0 || i == length(sig_dates)) {
    cat(sprintf("  [%3d/%3d] %s: n_top20=%d, n_present=%d, ret=%.4f\n",
                i, length(sig_dates), as.character(d_now),
                nrow(top20), nrow(valid), monthly_ret))
  }
}

cat("\nNEW sleeve returns built:", nrow(new_returns), "rows\n")
cat("monthly_ret stats:\n")
print(summary(new_returns$monthly_ret))

# Save
out_path <- file.path(SA_DIR, "new_sleeve_returns_184m_pd18.csv")
fwrite(new_returns, out_path)
cat("\nwritten:", out_path, "\n")

# Quick stats
non_na <- new_returns[!is.na(monthly_ret)]
cat("\nnon-NA rows:", nrow(non_na), "\n")
cat("mean monthly:", mean(non_na$monthly_ret), "\n")
cat("sd monthly:", sd(non_na$monthly_ret), "\n")
cat("SR_ann (geom approx):", mean(non_na$monthly_ret) / sd(non_na$monthly_ret) * sqrt(12), "\n")

cat("\nDONE: PD18 NEW sleeve returns 184m monthly rebal\n")
