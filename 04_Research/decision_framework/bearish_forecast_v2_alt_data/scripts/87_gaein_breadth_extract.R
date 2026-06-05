#==============================================================================
# 87_gaein_breadth_extract.R — Cycle 46B Phase 1: Investor_Act 개인 sheet에서
# 일별 retail (개인) breadth 지표 추출
#
# 데이터: 03_Universe/Investor_Act.xlsx > 개인 sheet
#         3669 종목 × 9354일 (1990-01-03 ~ 2026-03-27)
#         개인 종목별 순매수대금 (백만원)
#
# 계산 지표:
#   AD_count_buy:  개인 net > 0 종목 수
#   AD_count_sell: 개인 net < 0 종목 수
#   AD_ratio:      buy / (buy + sell) — 1.0이면 모두 매수
#   breadth_pct:   buy / total_active
#   concentration: HHI of buys (top 10 vs tail)
#
# KR literature theory:
#   개인 (retail) = noise trader / contrarian signal
#   개인 매수 집중 시 약세 onset 가능성 (smart money vs retail divergence)
#==============================================================================

suppressPackageStartupMessages({
  library(readxl); library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
UNIV <- file.path(PROJECT_ROOT, "03_Universe")
OUT_DIR <- file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data/outputs/01_data")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# Sheet name verification
all_sheets <- excel_sheets(file.path(UNIV, "Investor_Act.xlsx"))
cat(sprintf("[%s] All sheets: %s\n",
            format(Sys.time(), "%H:%M:%S"),
            paste(all_sheets, collapse = ", ")))
stopifnot("개인" %in% all_sheets)

cat(sprintf("[%s] Reading Investor_Act 개인 sheet...\n", format(Sys.time(), "%H:%M:%S")))
d <- as.data.frame(read_excel(
  file.path(UNIV, "Investor_Act.xlsx"),
  sheet = "개인", skip = 13, col_types = "text"))
cat(sprintf("[%s] Read complete. dim: %d rows x %d cols\n",
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
cat(sprintf("[%s] Matrix dim: %d x %d. NA count: %d / %d (%.1f%%)\n",
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

ad_ratio <- ifelse(n_active > 0, n_buy / n_active, NA_real_)
breadth_pct <- n_buy / pmax(n_active, 1L)

# Concentration index (HHI of top buy amounts / total buy amount)
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

fwrite(breadth_dt, file.path(OUT_DIR, "gaein_breadth_daily.csv"))
cat(sprintf("\n[%s] [SAVED] %s/gaein_breadth_daily.csv\n",
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
cat(sprintf("  ad_ratio: mean=%.4f sd=%.4f range [%.4f, %.4f]\n",
            mean(breadth_filt$ad_ratio, na.rm = TRUE),
            sd(breadth_filt$ad_ratio, na.rm = TRUE),
            min(breadth_filt$ad_ratio, na.rm = TRUE),
            max(breadth_filt$ad_ratio, na.rm = TRUE)))
