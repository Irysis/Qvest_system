setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(data.table); library(arrow)})
p <- readRDS("stage_artifacts/WT_R20260829_005/panel.rds")
f <- p$fwd
cat("fwd class:", class(f), " names:", names(f), "\n")
for (n in names(f)) {
  x <- f[[n]]
  cat(sprintf("  %-20s %-24s dim=%s\n", n, paste(class(x),collapse=","), paste(dim(x),collapse="x")))
  if (is.data.frame(x)) { print(names(x)); print(head(as.data.table(x),3)) }
}
cat("\n=== mem ===\n"); print(names(p$mem)); print(head(p$mem,3))
cat("\n=== ME ===\n"); print(class(p$ME)); print(head(p$ME,3))
cat("\n=== bench cov ===\n")
bc <- read_parquet("stage_artifacts/WT_R20260829_005/benchmark_covariance.parquet"); setDT(bc)
print(dim(bc)); print(names(bc)); print(head(bc,3))
