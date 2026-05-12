#==============================================================================
# WT-D20260511_001 PD20-A Path 1 — Sleeve-weighted top-N returns build
#
# Mission (도훈 mandate 2026-05-11 KST PD20-A):
#   Production Constraints 종목수 max 20 정합화.
#   Path 1 (sleeve-weighted top-N):
#     - STR_1715 H1 sleeve weight 45% retain × sleeve internal top16 EW
#     - NEW Vol/Skew sleeve weight 10% retain × sleeve internal top4 EW
#     - TSMOM (22.5%), KR_10y (18%), Cash (4.5%) inherit
#     - Aggregate KR equity 16 + 4 = 20 (= 20 cap PASS) + ETF 9 + Cash 1 (excluded)
#
# Outputs:
#   - stage_artifacts/WT_D20260511_001/str1715_sleeve_top16_returns_pd20a.csv (269 dates)
#   - stage_artifacts/WT_D20260511_001/new_sleeve_top4_returns_184m_pd20a.csv (184 dates)
#
# Methodology:
#   STR_1715 top16:
#     for each sig_date in str1715_actual_holdings_268m (269 dates):
#       rank by score_eff DESC, take top16 (drop ranks 17-20)
#       EW 1/16 per name
#       return_month = mean compound return Close[next] / Close[now] - 1
#
#   NEW top4:
#     for each sig_date in alpha_scores.parquet (184 dates):
#       universe filter KOSPI200 ∪ KOSDAQ150 ∩ ADV_20d >= 2e8 KRW (PIT-safe)
#       rank by alpha DESC, take top4
#       EW 1/4 per name
#       return_month = mean compound return Close[next] / Close[now] - 1
#
# Constraints:
#   - Pure function: alpha/risk/optimization read-only
#   - PerformanceAnalytics 표준 함수만 (geometric=TRUE)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

# Paths
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
SA_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260511_001")
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260511_001")
RAW_PATH <- file.path(PROJECT_ROOT, ".cache/rawdata.parquet")
STR1715_HOLDINGS_PATH <- file.path(PROJECT_ROOT, "stage_artifacts/WT_WT-S20260504_005/_logs/str1715_actual_holdings_268m.csv")

cat("=== PD20-A Path 1 — 1715 top16 + NEW top4 sleeve returns build ===\n\n")

#====================================================
# 1. Load rawdata (KR daily prices)
#====================================================
cat("Loading rawdata.parquet ...\n")
rd <- as.data.table(read_parquet(RAW_PATH))
setkey(rd, Ticker, Date)
cat("rawdata rows:", nrow(rd), "tickers:", length(unique(rd$Ticker)),
    "date range:", as.character(range(rd$Date)), "\n\n")

# Build ADV_20d for NEW universe filter
rd[, vol_value := Close * Vol]
setorder(rd, Ticker, Date)
rd[, adv_20d := frollmean(vol_value, n = 20, align = "right", na.rm = FALSE), by = Ticker]

#====================================================
# 2. STR_1715 H1 sleeve top16 returns (269 dates)
#====================================================
cat("=== STR_1715 H1 sleeve top16 EW returns ===\n")

str1715 <- fread(STR1715_HOLDINGS_PATH)
setnames(str1715, c("Date", "Ticker", "weight", "regime", "cash_pct", "score_eff"))
str1715[, Date := as.Date(Date)]

sig_dates_1715 <- sort(unique(str1715$Date))
cat("1715 sig_dates:", length(sig_dates_1715), "\n")
cat("range:", as.character(range(sig_dates_1715)), "\n")

# Build top16 EW returns
str1715_returns <- data.table()

for (i in seq_along(sig_dates_1715)) {
  d_now <- sig_dates_1715[i]

  if (i < length(sig_dates_1715)) {
    d_next <- sig_dates_1715[i + 1]
  } else {
    d_next <- as.Date("2026-05-31")  # last sig_date 2026-05-01 → use 5월 말까지
  }

  # Pick rows for d_now
  rows_now <- str1715[Date == d_now]
  if (nrow(rows_now) == 0) {
    str1715_returns <- rbind(str1715_returns, data.table(
      sig_date = d_now,
      n_holdings = 0,
      monthly_ret = NA_real_,
      n_present = 0
    ))
    next
  }

  # Rank by score_eff DESC, take top16 (drop ranks 17-20)
  setorder(rows_now, -score_eff)
  top16 <- head(rows_now, 16)

  # Entry prices at d_now
  entry_prices <- rd[Ticker %in% top16$Ticker & Date >= d_now & Date <= (d_now + 5L)]
  if (nrow(entry_prices) == 0) {
    str1715_returns <- rbind(str1715_returns, data.table(
      sig_date = d_now,
      n_holdings = nrow(top16),
      monthly_ret = NA_real_,
      n_present = 0
    ))
    next
  }
  entry_prices <- entry_prices[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
  setnames(entry_prices, c("Ticker", "entry_date", "entry_price"))

  # Exit prices at d_next
  exit_prices <- rd[Ticker %in% top16$Ticker & Date >= d_next & Date <= (d_next + 5L)]
  if (nrow(exit_prices) == 0) {
    monthly_ret <- NA_real_
    n_valid <- 0
  } else {
    exit_prices <- exit_prices[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
    setnames(exit_prices, c("Ticker", "exit_date", "exit_price"))

    rets <- merge(entry_prices, exit_prices, by = "Ticker", all.x = TRUE)
    rets[, ret_pct := (exit_price / entry_price) - 1]

    valid <- rets[!is.na(ret_pct)]
    if (nrow(valid) == 0) {
      monthly_ret <- NA_real_
      n_valid <- 0
    } else {
      monthly_ret <- mean(valid$ret_pct)  # EW 1/n
      n_valid <- nrow(valid)
    }
  }

  str1715_returns <- rbind(str1715_returns, data.table(
    sig_date = d_now,
    n_holdings = nrow(top16),
    monthly_ret = monthly_ret,
    n_present = n_valid
  ))

  if (i %% 30 == 0 || i == length(sig_dates_1715)) {
    cat(sprintf("  [%3d/%3d] %s: n_top16=%d, n_present=%d, ret=%.4f\n",
                i, length(sig_dates_1715), as.character(d_now),
                nrow(top16), n_valid, ifelse(is.na(monthly_ret), 0, monthly_ret)))
  }
}

cat("\n1715 top16 returns built:", nrow(str1715_returns), "rows\n")
cat("monthly_ret stats:\n")
print(summary(str1715_returns$monthly_ret))

# Save
out_path_1715 <- file.path(SA_DIR, "str1715_sleeve_top16_returns_pd20a.csv")
fwrite(str1715_returns, out_path_1715)
cat("written:", out_path_1715, "\n\n")

# Quick stats
non_na_1715 <- str1715_returns[!is.na(monthly_ret)]
cat("1715 top16 non-NA rows:", nrow(non_na_1715), "\n")
cat("mean monthly:", mean(non_na_1715$monthly_ret), "\n")
cat("sd monthly:", sd(non_na_1715$monthly_ret), "\n")
cat("SR_ann (geom approx):", mean(non_na_1715$monthly_ret) / sd(non_na_1715$monthly_ret) * sqrt(12), "\n\n")

#====================================================
# 3. NEW Vol/Skew sleeve top4 returns (184 dates)
#====================================================
cat("=== NEW Vol/Skew sleeve top4 EW returns ===\n")

ap <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores.parquet")))
sig_dates_new <- sort(unique(ap$sig_date))
cat("alpha sig_dates:", length(sig_dates_new), "\n")
cat("range:", as.character(range(sig_dates_new)), "\n")
stopifnot(length(sig_dates_new) == 184)

LIQ_THRESHOLD <- 2e8

new_returns <- data.table()

for (i in seq_along(sig_dates_new)) {
  d_now <- sig_dates_new[i]

  if (i < length(sig_dates_new)) {
    d_next <- sig_dates_new[i + 1]
  } else {
    d_next <- as.Date("2026-05-01")
  }

  # Universe at d_now
  uni_dt <- rd[Date <= d_now & Date >= (d_now - 30L), .SD[which.max(Date)], by = Ticker]
  uni_dt <- uni_dt[(K200 == 1 | KQ150 == 1) & !is.na(adv_20d) & adv_20d >= LIQ_THRESHOLD]

  alpha_now <- ap[sig_date == d_now]
  alpha_uni <- alpha_now[Ticker %in% uni_dt$Ticker]

  # Top4 by alpha DESC (drastic concentration)
  setorder(alpha_uni, -alpha)
  top4 <- head(alpha_uni, 4)

  if (nrow(top4) == 0) {
    new_returns <- rbind(new_returns, data.table(
      sig_date = d_now,
      n_holdings = 0,
      monthly_ret = NA_real_,
      n_present = 0
    ))
    next
  }

  # Entry prices
  entry_prices <- rd[Ticker %in% top4$Ticker & Date >= d_now & Date <= (d_now + 5L)]
  if (nrow(entry_prices) == 0) {
    new_returns <- rbind(new_returns, data.table(
      sig_date = d_now,
      n_holdings = nrow(top4),
      monthly_ret = NA_real_,
      n_present = 0
    ))
    next
  }
  entry_prices <- entry_prices[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
  setnames(entry_prices, c("Ticker", "entry_date", "entry_price"))

  # Exit prices
  exit_prices <- rd[Ticker %in% top4$Ticker & Date >= d_next & Date <= (d_next + 5L)]
  if (nrow(exit_prices) == 0) {
    monthly_ret <- NA_real_
    n_valid <- 0
  } else {
    exit_prices <- exit_prices[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
    setnames(exit_prices, c("Ticker", "exit_date", "exit_price"))

    rets <- merge(entry_prices, exit_prices, by = "Ticker", all.x = TRUE)
    rets[, ret_pct := (exit_price / entry_price) - 1]

    valid <- rets[!is.na(ret_pct)]
    if (nrow(valid) == 0) {
      monthly_ret <- NA_real_
      n_valid <- 0
    } else {
      monthly_ret <- mean(valid$ret_pct)  # EW 1/4
      n_valid <- nrow(valid)
    }
  }

  new_returns <- rbind(new_returns, data.table(
    sig_date = d_now,
    n_holdings = nrow(top4),
    monthly_ret = monthly_ret,
    n_present = n_valid
  ))

  if (i %% 20 == 0 || i == length(sig_dates_new)) {
    cat(sprintf("  [%3d/%3d] %s: n_top4=%d, n_present=%d, ret=%.4f\n",
                i, length(sig_dates_new), as.character(d_now),
                nrow(top4), n_valid, ifelse(is.na(monthly_ret), 0, monthly_ret)))
  }
}

cat("\nNEW top4 returns built:", nrow(new_returns), "rows\n")
cat("monthly_ret stats:\n")
print(summary(new_returns$monthly_ret))

# Save
out_path_new <- file.path(SA_DIR, "new_sleeve_top4_returns_184m_pd20a.csv")
fwrite(new_returns, out_path_new)
cat("written:", out_path_new, "\n\n")

# Quick stats
non_na_new <- new_returns[!is.na(monthly_ret)]
cat("NEW top4 non-NA rows:", nrow(non_na_new), "\n")
cat("mean monthly:", mean(non_na_new$monthly_ret), "\n")
cat("sd monthly:", sd(non_na_new$monthly_ret), "\n")
cat("SR_ann (geom approx):", mean(non_na_new$monthly_ret) / sd(non_na_new$monthly_ret) * sqrt(12), "\n\n")

#====================================================
# 4. Sanity check vs PD18 baseline (NEW top20)
#====================================================
cat("=== Comparison with PD18 baseline (NEW top20) ===\n")
pd18_new <- fread(file.path(SA_DIR, "new_sleeve_returns_184m_pd18.csv"))
non_na_pd18 <- pd18_new[!is.na(monthly_ret)]
cat("PD18 NEW top20: n=", nrow(non_na_pd18), " mean=", round(mean(non_na_pd18$monthly_ret), 6),
    " sd=", round(sd(non_na_pd18$monthly_ret), 6),
    " SR(geom approx)=", round(mean(non_na_pd18$monthly_ret) / sd(non_na_pd18$monthly_ret) * sqrt(12), 4), "\n")
cat("PD20A NEW top4:  n=", nrow(non_na_new), " mean=", round(mean(non_na_new$monthly_ret), 6),
    " sd=", round(sd(non_na_new$monthly_ret), 6),
    " SR(geom approx)=", round(mean(non_na_new$monthly_ret) / sd(non_na_new$monthly_ret) * sqrt(12), 4), "\n")

cat("\nDONE: PD20-A Path 1 sleeve returns built (1715 top16 + NEW top4)\n")
