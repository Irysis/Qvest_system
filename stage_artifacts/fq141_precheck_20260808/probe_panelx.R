suppressPackageStartupMessages({ library(arrow); library(data.table) })
x <- as.data.table(read_parquet("04_Research/method_frontier/fq002_contract_magnitude/panelx_A.parquet"))
cat("rows:", nrow(x), " cols:", ncol(x), "\n")
cat("names:", paste(names(x), collapse=", "), "\n\n")
dc <- names(x)[grepl("date|ym", names(x), ignore.case=TRUE)]
cat("time cols:", paste(dc, collapse=", "), "\n")
for (d in dc) {
  v <- x[[d]]
  cat(sprintf("  %-14s uniq=%4d  range=%s ~ %s\n", d, uniqueN(v), as.character(min(v,na.rm=TRUE)), as.character(max(v,na.rm=TRUE))))
}
if (length(dc)) {
  k <- dc[1]
  per <- x[, .N, by=c(k)][order(get(k))]
  cat(sprintf("\n월별 행수: 중앙 %.0f · 최소 %d · 최대 %d · 개월 %d\n",
              median(per$N), min(per$N), max(per$N), nrow(per)))
  cat("처음 3개월:\n"); print(head(per,3)); cat("마지막 3개월:\n"); print(tail(per,3))
}
