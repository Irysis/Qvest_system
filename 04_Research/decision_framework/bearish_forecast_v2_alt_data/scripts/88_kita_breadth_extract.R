#==============================================================================
# 88_kita_breadth_extract.R — Cycle 46B Phase 2: Investor_Act 기타법인 sheet에서
# 일별 corporate (기타법인) breadth 지표 추출
#
# 데이터: 03_Universe/Investor_Act.xlsx > 기타법인 sheet
#         자사주 매입 / 일반 corporate flow
#
# Hypothesis: 시장 신호 약함 예상이나 다른 axis 검증 필요
#==============================================================================

suppressPackageStartupMessages({
  library(readxl); library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
UNIV <- file.path(PROJECT_ROOT, "03_Universe")
OUT_DIR <- file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data/outputs/01_data")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

all_sheets <- excel_sheets(file.path(UNIV, "Investor_Act.xlsx"))
cat(sprintf("[%s] All sheets: %s\n",
            format(Sys.time(), "%H:%M:%S"),
            paste(all_sheets, collapse = ", ")))
stopifnot("기타법인" %in% all_sheets)

cat(sprintf("[%s] Reading Investor_Act 기타법인 sheet...\n", format(Sys.time(), "%H:%M:%S")))
d <- as.data.frame(read_excel(
  file.path(UNIV, "Investor_Act.xlsx"),
  sheet = "기타법인", skip = 13, col_types = "text"))
cat(sprintf("[%s] Read complete. dim: %d rows x %d cols\n",
            format(Sys.time(), "%H:%M:%S"), nrow(d), ncol(d)))

dates <- as.Date(as.numeric(d[[1]]), origin = "1899-12-30")
valid <- !is.na(dates)
dates <- dates[valid]
d <- d[valid, ]
cat(sprintf("[%s] Valid date rows: %d. Range %s ~ %s\n",
            format(Sys.time(), "%H:%M:%S"),
            length(dates), as.character(min(dates)), as.character(max(dates))))

cat(sprintf("[%s] Converting %d stock columns to numeric...\n",
            format(Sys.time(), "%H:%M:%S"), ncol(d) - 1))
stock_mat <- as.matrix(d[, -1])
storage.mode(stock_mat) <- "numeric"
cat(sprintf("[%s] Matrix dim: %d x %d. NA count: %d / %d (%.1f%%)\n",
            format(Sys.time(), "%H:%M:%S"),
            nrow(stock_mat), ncol(stock_mat),
            sum(is.na(stock_mat)),
            length(stock_mat),
            100 * mean(is.na(stock_mat))))

cat(sprintf("[%s] Computing breadth indicators per day...\n",
            format(Sys.time(), "%H:%M:%S")))
n_buy <- apply(stock_mat, 1, function(x) sum(x > 0, na.rm = TRUE))
n_sell <- apply(stock_mat, 1, function(x) sum(x < 0, na.rm = TRUE))
n_zero <- apply(stock_mat, 1, function(x) sum(x == 0, na.rm = TRUE))
n_active <- n_buy + n_sell

ad_ratio <- ifelse(n_active > 0, n_buy / n_active, NA_real_)
breadth_pct <- n_buy / pmax(n_active, 1L)

hhi_buy <- apply(stock_mat, 1, function(x) {
  buys <- x[x > 0 & !is.na(x)]
  if (length(buys) < 5) return(NA_real_)
  shares <- buys / sum(buys)
  sum(shares^2)
})

breadth_dt <- data.table(
  Date = dates,
  n_buy = n_buy, n_sell = n_sell, n_active = n_active,
  ad_ratio = round(ad_ratio, 4),
  hhi_buy = round(hhi_buy, 4)
)
setorder(breadth_dt, Date)

fwrite(breadth_dt, file.path(OUT_DIR, "kita_breadth_daily.csv"))
cat(sprintf("\n[%s] [SAVED] %s/kita_breadth_daily.csv\n",
            format(Sys.time(), "%H:%M:%S"), OUT_DIR))
cat(sprintf("Rows: %d / Date range: %s ~ %s\n",
            nrow(breadth_dt),
            as.character(min(breadth_dt$Date)),
            as.character(max(breadth_dt$Date))))

cat("\nSummary:\n")
print(summary(breadth_dt[, .(n_buy, n_sell, ad_ratio, hhi_buy)]))

cat("\nRecent 5:\n")
print(tail(breadth_dt, 5))

cat("\nFiltered (n_active >= 100):\n")
breadth_filt <- breadth_dt[n_active >= 100]
cat(sprintf("  rows: %d (%.1f%% of total)\n",
            nrow(breadth_filt), 100 * nrow(breadth_filt) / nrow(breadth_dt)))
if (nrow(breadth_filt) > 0) {
  cat(sprintf("  ad_ratio: mean=%.4f sd=%.4f range [%.4f, %.4f]\n",
              mean(breadth_filt$ad_ratio, na.rm = TRUE),
              sd(breadth_filt$ad_ratio, na.rm = TRUE),
              min(breadth_filt$ad_ratio, na.rm = TRUE),
              max(breadth_filt$ad_ratio, na.rm = TRUE)))
} else {
  cat("  WARNING: 기타법인 sheet에 n_active>=100 행 없음 (corporate flow 자체가 희소)\n")
  cat("  Filter 완화: n_active >= 30 시도\n")
  breadth_filt2 <- breadth_dt[n_active >= 30]
  cat(sprintf("  rows (n_active>=30): %d\n", nrow(breadth_filt2)))
}
