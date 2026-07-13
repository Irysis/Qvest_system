suppressWarnings(suppressMessages(library(data.table)))
d <- fread("merged_series.csv")
a <- d$active_rds
cat(sprintf("n=%d  min|a|=%.6f  q05|a|=%.5f  median|a|=%.5f  a^2: min=%.2e mean=%.2e\n",
  length(a), min(abs(a)), quantile(abs(a),.05), median(abs(a)), min(a^2), mean(a^2)))
cat(sprintf("bm: mean=%.5f sd=%.5f mean(bm^2)=%.5f\n", mean(d$bm), sd(d$bm), mean(d$bm^2)))
cat(sprintf("book_rds: mean=%.5f sd=%.5f | exposure range [%.2f, %.2f]\n",
  mean(d$book_rds), sd(d$book_rds), min(d$exposure), max(d$exposure)))
