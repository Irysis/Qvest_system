# factor DB factor 카탈로그 — 미검증 직교 축 파악 (factor_db_YYYYMM.parquet, Long)
suppressWarnings(suppressMessages({ library(arrow) }))
f <- sort(list.files(".cache/factor_db", pattern = "^factor_db_[0-9]{6}\\.parquet$", full.names = TRUE))
if (!length(f)) {
  cat("factor_db_YYYYMM.parquet 없음. .cache/factor_db parquet 목록:\n")
  cat(list.files(".cache/factor_db", pattern = "parquet$"), sep = "\n")
} else {
  latest <- f[length(f)]
  d  <- read_parquet(latest, col_select = "Factor_Name")
  fn <- sort(unique(as.character(d[["Factor_Name"]])))
  cat("file:", basename(latest), "| 총 factor:", length(fn), "\n\n[prefix(family) 분포]\n")
  print(table(substr(fn, 1, 1)))
  cat("\n[★★ 미검증 직교 후보 — accruals/liquidity/investment/issuance/payout/cashflow]\n")
  pat <- "Accr|Issu|Invest|Asset|Liq|Amih|Turn|NOA|Capex|Sloan|Buyback|Payout|Debt|Equity|Working|Inventory|Growth|Financ|Cash|Dividend|Repurch|External|CFO|NetIss|Yield"
  hit <- grep(pat, fn, ignore.case = TRUE, value = TRUE)
  cat(if (length(hit)) paste(hit, collapse = "\n") else "(직접 매칭 적음 — 전체 하단)", "\n")
  cat("\n[전체 factor 목록]\n"); cat(fn, sep = "\n")
}
