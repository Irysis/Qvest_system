## run_00_inspect.R — 입력 자산 실측 점검 (스키마 / vintage / 커버리지)
## WT-D20260802_002 FQ-084. 소비 전 사실 확인만 — 판정 없음.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setDTthreads(2); try(arrow::set_io_thread_count(2), silent = TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)

cat("=== [1] cleanT1 base panel ===\n")
P_CLEAN <- "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet"
sch <- arrow::open_dataset(P_CLEAN)$schema
print(names(sch))
cl <- as.data.table(read_parquet(P_CLEAN))
cat(sprintf("rows=%d  cols=%s\n", nrow(cl), paste(names(cl), collapse=",")))
cl[, Date := as.Date(Date)]
cat(sprintf("Date range: %s ~ %s  n_months=%d  n_tickers=%d\n",
            min(cl$Date), max(cl$Date), uniqueN(cl$Date), uniqueN(cl$Ticker)))
print(head(cl, 3))
cat("\nper-month name counts (quantile):\n"); print(quantile(cl[, .N, by=Date]$N, c(0,.1,.5,.9,1)))

cat("\n=== [2] investor_wide vintage (내용 기준) ===\n")
P_INV <- ".cache/investor_stock/investor_wide.parquet"
ds <- arrow::open_dataset(P_INV)
cat("schema:\n"); print(names(ds$schema))
iv_max <- as.data.table(ds |> dplyr::summarise(mx = max(Date), mn = min(Date), n = dplyr::n()) |> dplyr::collect())
print(iv_max)

cat("\n=== [3] investor_all vintage (파일 간 불일치 확인 — 07-17 실사고) ===\n")
ds2 <- arrow::open_dataset(".cache/investor_stock/investor_all.parquet")
cat("schema:\n"); print(names(ds2$schema))
a_max <- as.data.table(ds2 |> dplyr::summarise(mx = max(Date), mn = min(Date), n = dplyr::n()) |> dplyr::collect())
print(a_max)

cat("\n=== [4] investor_foreign vintage ===\n")
ds3 <- arrow::open_dataset(".cache/investor_stock/investor_foreign.parquet")
cat("schema:\n"); print(names(ds3$schema))
f_max <- as.data.table(ds3 |> dplyr::summarise(mx = max(Date), n = dplyr::n()) |> dplyr::collect())
print(f_max)

cat("\n=== [5] rawdata (size/liq) ===\n")
RAW_P <- ".cache/rawdata.parquet"
cat("exists:", file.exists(RAW_P), "\n")
if (file.exists(RAW_P)) {
  rs <- arrow::open_dataset(RAW_P)$schema
  print(names(rs))
}
cat("\n[DONE]\n")
