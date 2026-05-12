#==============================================================================
# WT-D20260511_001 PD20-A — Build STR_1715 top20 EW returns (baseline reference)
#
# Purpose: 동일 방법론으로 1715 top20 EW returns 산출 → top16 truncation effect 정량 비교
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
SA_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260511_001")
RAW_PATH <- file.path(PROJECT_ROOT, ".cache/rawdata.parquet")
STR1715_HOLDINGS_PATH <- file.path(PROJECT_ROOT, "stage_artifacts/WT_WT-S20260504_005/_logs/str1715_actual_holdings_268m.csv")

cat("=== STR_1715 top20 EW baseline returns build (top16 truncation comparison) ===\n\n")

rd <- as.data.table(read_parquet(RAW_PATH))
setkey(rd, Ticker, Date)

str1715 <- fread(STR1715_HOLDINGS_PATH)
setnames(str1715, c("Date", "Ticker", "weight", "regime", "cash_pct", "score_eff"))
str1715[, Date := as.Date(Date)]

sig_dates_1715 <- sort(unique(str1715$Date))
cat("1715 sig_dates:", length(sig_dates_1715), "\n")

str1715_top20 <- data.table()

for (i in seq_along(sig_dates_1715)) {
  d_now <- sig_dates_1715[i]
  if (i < length(sig_dates_1715)) {
    d_next <- sig_dates_1715[i + 1]
  } else {
    d_next <- as.Date("2026-05-31")
  }

  rows_now <- str1715[Date == d_now]
  if (nrow(rows_now) == 0) {
    str1715_top20 <- rbind(str1715_top20, data.table(
      sig_date = d_now, n_holdings = 0, monthly_ret = NA_real_, n_present = 0
    ))
    next
  }

  setorder(rows_now, -score_eff)
  top20 <- head(rows_now, 20)

  entry_prices <- rd[Ticker %in% top20$Ticker & Date >= d_now & Date <= (d_now + 5L)]
  if (nrow(entry_prices) == 0) {
    str1715_top20 <- rbind(str1715_top20, data.table(
      sig_date = d_now, n_holdings = nrow(top20), monthly_ret = NA_real_, n_present = 0
    ))
    next
  }
  entry_prices <- entry_prices[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
  setnames(entry_prices, c("Ticker", "entry_date", "entry_price"))

  exit_prices <- rd[Ticker %in% top20$Ticker & Date >= d_next & Date <= (d_next + 5L)]
  if (nrow(exit_prices) == 0) {
    monthly_ret <- NA_real_; n_valid <- 0
  } else {
    exit_prices <- exit_prices[, .SD[which.min(Date)], by = Ticker, .SDcols = c("Date", "Close")]
    setnames(exit_prices, c("Ticker", "exit_date", "exit_price"))

    rets <- merge(entry_prices, exit_prices, by = "Ticker", all.x = TRUE)
    rets[, ret_pct := (exit_price / entry_price) - 1]

    valid <- rets[!is.na(ret_pct)]
    if (nrow(valid) == 0) {
      monthly_ret <- NA_real_; n_valid <- 0
    } else {
      monthly_ret <- mean(valid$ret_pct); n_valid <- nrow(valid)
    }
  }

  str1715_top20 <- rbind(str1715_top20, data.table(
    sig_date = d_now, n_holdings = nrow(top20), monthly_ret = monthly_ret, n_present = n_valid
  ))
}

cat("1715 top20 EW returns built:", nrow(str1715_top20), "rows\n")
non_na <- str1715_top20[!is.na(monthly_ret)]
cat("non-NA rows:", nrow(non_na), "\n")
cat("mean monthly:", mean(non_na$monthly_ret), "\n")
cat("sd monthly:", sd(non_na$monthly_ret), "\n")
cat("SR_ann (geom approx):", mean(non_na$monthly_ret) / sd(non_na$monthly_ret) * sqrt(12), "\n")

out_path <- file.path(SA_DIR, "str1715_sleeve_top20_baseline_returns_pd20a.csv")
fwrite(str1715_top20, out_path)
cat("written:", out_path, "\n")

# Comparison vs top16
top16 <- fread(file.path(SA_DIR, "str1715_sleeve_top16_returns_pd20a.csv"))
non_na_16 <- top16[!is.na(monthly_ret)]
cat("\n=== 1715 top16 vs top20 EW comparison ===\n")
cat("top16: mean=", round(mean(non_na_16$monthly_ret), 6), " sd=", round(sd(non_na_16$monthly_ret), 6),
    " SR(approx)=", round(mean(non_na_16$monthly_ret) / sd(non_na_16$monthly_ret) * sqrt(12), 4), "\n")
cat("top20: mean=", round(mean(non_na$monthly_ret), 6), " sd=", round(sd(non_na$monthly_ret), 6),
    " SR(approx)=", round(mean(non_na$monthly_ret) / sd(non_na$monthly_ret) * sqrt(12), 4), "\n")
cat("\nDONE\n")
