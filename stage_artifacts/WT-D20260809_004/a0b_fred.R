setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table); library(arrow) })
FR <- as.data.table(read_parquet(".cache/fred_macro.parquet"))
tb <- FR[, .(N = .N, from = as.character(min(Date)), to = as.character(max(Date)),
             freq = Frequency[1], sid = Series_ID[1]), by = Series][order(Series)]
cat(sprintf("FRED series 총 %d종\n", nrow(tb)))
for (i in seq_len(nrow(tb)))
  cat(sprintf("  %-26s %6d  %s ~ %s  freq=%s  id=%s\n",
              tb$Series[i], tb$N[i], tb$from[i], tb$to[i], tb$freq[i], tb$sid[i]))

cat("\n--- 인플레 관련 후보 탐색 ---\n")
pat <- "T5YIE|BREAK|Copper|COPPER|PCOPP|CPI|Inflation|PPI|Commodity|WTI|Oil"
hit <- tb[grepl(pat, paste(Series, sid), ignore.case = TRUE)]
print(hit)

cat("\n--- macro_fred.parquet (별도 파일) ---\n")
if (file.exists(".cache/macro_fred.parquet")) {
  M <- as.data.table(read_parquet(".cache/macro_fred.parquet"))
  cat(sprintf("행 %d · 컬럼: %s\n", nrow(M), paste(names(M), collapse = ", ")))
}
cat("\n--- fred_macro_wide.parquet ---\n")
if (file.exists(".cache/fred_macro_wide.parquet")) {
  W <- as.data.table(read_parquet(".cache/fred_macro_wide.parquet"))
  cat(sprintf("행 %d · 컬럼: %s\n", nrow(W), paste(names(W), collapse = ", ")))
  cat(sprintf("기간 %s ~ %s\n", as.character(min(W[[1]])), as.character(max(W[[1]]))))
}
