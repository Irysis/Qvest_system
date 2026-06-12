# Inspect aligned_series.rds (book/value/bench by realized_ym) for benchmark coverage
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
M <- as.data.table(readRDS(file.path(ROOT,
  "04_Research/composition_search/value_sleeve_combination/aligned_series.rds")))
cat("cols:", paste(names(M), collapse=", "), "\n")
cat(sprintf("n=%d  realized_ym %s..%s\n", nrow(M), min(M$realized_ym), max(M$realized_ym)))
cat("head:\n"); print(head(M, 3))
cat("tail:\n"); print(tail(M, 3))
cat(sprintf("bench_ret nonzero=%d  NA=%d\n", sum(M$bench_ret != 0, na.rm=TRUE), sum(is.na(M$bench_ret))))
