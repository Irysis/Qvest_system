#==============================================================================
# 77_inst_breadth_extract.R — Cycle 45B Phase 1: Investor_Act 기관 sheet에서
# 일별 institutional flow breadth 지표 추출
#
# 데이터: 03_Universe/Investor_Act.xlsx > 기관 sheet
#         외국인용 65_breadth_extract.R를 미러링하되 sheet="기관"으로 변경
#
# 계산 지표:
#   n_buy:    기관 net > 0 종목 수
#   n_sell:   기관 net < 0 종목 수
#   n_active: buy + sell (NA/0 제외)
#   ad_ratio: buy / active (1.0이면 모두 매수)
#   hhi_buy:  HHI of buy amounts (concentration)
#
# Output: outputs/01_data/inst_breadth_daily.csv
#==============================================================================

suppressPackageStartupMessages({
  library(readxl); library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
UNIV <- file.path(PROJECT_ROOT, "03_Universe")
OUT_DIR <- file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data/outputs/01_data")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# Verify sheet name
sheets <- excel_sheets(file.path(UNIV, "Investor_Act.xlsx"))
cat(sprintf("[%s] Available sheets: %s\n",
            format(Sys.time(), "%H:%M:%S"), paste(sheets, collapse = ", ")))
SHEET_NAME <- "기관"
if (!SHEET_NAME %in% sheets) {
  stop(sprintf("Sheet '%s' not found. Available: %s",
               SHEET_NAME, paste(sheets, collapse = ", ")))
}

cat(sprintf("[%s] Reading Investor_Act %s sheet...\n",
            format(Sys.time(), "%H:%M:%S"), SHEET_NAME))
d <- as.data.frame(read_excel(
  file.path(UNIV, "Investor_Act.xlsx"),
  sheet = SHEET_NAME, skip = 13, col_types = "text"))
cat(sprintf("[%s] Read complete. dim: %d rows × %d cols\n",
            format(Sys.time(), "%H:%M:%S"), nrow(d), ncol(d)))

# Date column (1st col)
dates <- as.Date(as.numeric(d[[1]]), origin = "1899-12-30")
valid <- !is.na(dates)
dates <- dates[valid]
d <- d[valid, ]
cat(sprintf("[%s] Valid date rows: %d. Range %s ~ %s\n",
            format(Sys.time(), "%H:%M:%S"),
            length(dates), as.character(min(dates)), as.character(max(dates))))

# Convert stock columns (2 to ncol) to numeric
cat(sprintf("[%s] Converting %d stock columns to numeric...\n",
            format(Sys.time(), "%H:%M:%S"), ncol(d) - 1))
stock_mat <- as.matrix(d[, -1])
storage.mode(stock_mat) <- "numeric"
cat(sprintf("[%s] Matrix dim: %d × %d. NA count: %d / %d (%.1f%%%%)\n",
            format(Sys.time(), "%H:%M:%S"),
            nrow(stock_mat), ncol(stock_mat),
            sum(is.na(stock_mat)),
            length(stock_mat),
            100 * mean(is.na(stock_mat))))

# Per-row breadth indicators
cat(sprintf("[%s] Computing breadth indicators per day...\n",
            format(Sys.time(), "%H:%M:%S")))
n_buy <- apply(stock_mat, 1, function(x) sum(x > 0, na.rm = TRUE))
n_sell <- apply(stock_mat, 1, function(x) sum(x < 0, na.rm = TRUE))
n_zero <- apply(stock_mat, 1, function(x) sum(x == 0, na.rm = TRUE))
n_active <- n_buy + n_sell

# AD ratio
ad_ratio <- ifelse(n_active > 0, n_buy / n_active, NA_real_)

# Concentration index (HHI of buy amounts)
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

# Save
out_path <- file.path(OUT_DIR, "inst_breadth_daily.csv")
fwrite(breadth_dt, out_path)
cat(sprintf("\n[%s] [SAVED] %s\n", format(Sys.time(), "%H:%M:%S"), out_path))
cat(sprintf("Rows: %d / Date range: %s ~ %s\n",
            nrow(breadth_dt),
            as.character(min(breadth_dt$Date)),
            as.character(max(breadth_dt$Date))))

cat("\nSummary:\n")
print(summary(breadth_dt[, .(n_buy, n_sell, ad_ratio, hhi_buy)]))

cat("\nRecent 5:\n")
print(tail(breadth_dt, 5))
