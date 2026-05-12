# judge_pd18_holdings_cash_fix.R
# Codex C4 ACCEPT — ticker-level holdings sum to 0.955 (Cash sleeve 0.045 omitted)
# Add Cash placeholder row + verify Σw=1 strict

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260511_001"
WT_DIR <- file.path(PROJECT_ROOT, "qepm", "mailbox", "worktask", WT_ID)
STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", "WT_D20260511_001")

# Load alpha scores
alpha_dt <- as.data.table(arrow::read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))
setnames(alpha_dt, names(alpha_dt), tolower(names(alpha_dt)))
alpha_dt[, date := as.Date(sig_date)]

# Load STR_1715 H1 latest production
str1715_dir <- file.path(PROJECT_ROOT, "04_Research", "strategies",
                         "STR_1715_WT016_Iter31_GridBestProd", "production_weights")
str1715_files <- list.files(str1715_dir, pattern = "weights_cap_0p20.*\\.csv$", full.names = TRUE)
str1715_dt <- fread(str1715_files[length(str1715_files)])

tsmom_etfs <- c("A114800", "A152100", "A114820", "A091160", "A099140",
                "A114080", "A091170", "A091180")
kr10y_ticker <- "A148070"

build_ticker_holdings_with_cash <- function(sig_date_d, str1715_dt, tsmom_etfs, kr10y_ticker,
                                              new_top20, NEW_active = TRUE) {
  if (NEW_active) {
    w_AR_per <- 0.45 / nrow(str1715_dt)
    w_TSMOM_per <- 0.225 / length(tsmom_etfs)
    w_KR10y_per <- 0.18
    w_Cash_per <- 0.045  # Cash sleeve placeholder (single row)
    w_NEW_per <- 0.10 / nrow(new_top20)
  } else {
    w_AR_per <- 0.50 / nrow(str1715_dt)
    w_TSMOM_per <- 0.25 / length(tsmom_etfs)
    w_KR10y_per <- 0.20
    w_Cash_per <- 0.05
    w_NEW_per <- 0  # NEW inactive
  }

  rows_AR <- data.table(Date = sig_date_d, sleeve = "AR_on_M4",
                        ticker = str1715_dt$Ticker, weight = w_AR_per)
  rows_TSMOM <- data.table(Date = sig_date_d, sleeve = "TSMOM",
                           ticker = tsmom_etfs, weight = w_TSMOM_per)
  rows_KR10y <- data.table(Date = sig_date_d, sleeve = "KR_10y",
                           ticker = kr10y_ticker, weight = w_KR10y_per)
  rows_Cash <- data.table(Date = sig_date_d, sleeve = "Cash",
                          ticker = "KRW_CASH_PLACEHOLDER", weight = w_Cash_per)
  rows_NEW <- if (NEW_active && nrow(new_top20) > 0) {
    data.table(Date = sig_date_d, sleeve = "NEW",
               ticker = new_top20$ticker, weight = w_NEW_per)
  } else {
    data.table(Date = sig_date_d, sleeve = "NEW", ticker = NA_character_, weight = 0)[0]
  }

  rbindlist(list(rows_AR, rows_TSMOM, rows_KR10y, rows_Cash, rows_NEW),
            use.names = TRUE, fill = TRUE)
}

sample_dates_12 <- alpha_dt[, unique(date)][seq(1, length(alpha_dt[, unique(date)]), length.out = 12)]
holdings_v2 <- rbindlist(lapply(sample_dates_12, function(d) {
  top20_d <- alpha_dt[date == d][order(-confidence)][1:20]
  build_ticker_holdings_with_cash(d, str1715_dt, tsmom_etfs, kr10y_ticker, top20_d, NEW_active = TRUE)
}), use.names = TRUE, fill = TRUE)

# Verify Σw=1 per date
sums <- holdings_v2[, .(sum_w = sum(weight, na.rm = TRUE), n = .N), by = Date]
cat("After Cash sleeve addition:\n")
print(sums)
cat("\nMean sum:", round(mean(sums$sum_w), 6), "  Target: 1.0 STRICT\n")
cat("All sums = 1.0:", all(abs(sums$sum_w - 1.0) < 1e-9), "\n")

# Save fixed CSV
fwrite(holdings_v2, file.path(WT_DIR, "ticker_level_holdings_pd18_sample12dates_v2_cash_fixed.csv"))
cat("\nSaved: ticker_level_holdings_pd18_sample12dates_v2_cash_fixed.csv (",
    nrow(holdings_v2), " rows including Cash sleeve placeholder)\n")
