setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(data.table); library(arrow)})
p <- readRDS("stage_artifacts/WT_R20260829_005/panel.rds")
cat("class:", class(p), "\n")
if (is.list(p) && !is.data.frame(p)) {
  cat("names:", names(p), "\n")
  for (n in names(p)) cat(sprintf("  %-24s %-16s dim=%s\n", n, paste(class(p[[n]]),collapse=","), paste(dim(p[[n]]), collapse="x")))
} else {
  setDT(p); print(dim(p)); print(names(p)); print(head(p,3))
}
cat("\n=== exposure_matrix ===\n")
em <- read_parquet("stage_artifacts/WT_R20260829_005/exposure_matrix.parquet"); setDT(em)
print(dim(em)); print(names(em)); print(head(em,3))
cat("\n=== specific_risk ===\n")
sr <- read_parquet("stage_artifacts/WT_R20260829_005/specific_risk.parquet"); setDT(sr)
print(dim(sr)); print(names(sr)); print(head(sr,3))
cat("\n=== benchmark_covariance ===\n")
bc <- read_parquet("stage_artifacts/WT_R20260829_005/benchmark_covariance.parquet"); setDT(bc)
print(dim(bc)); print(names(bc)); print(head(bc,3))
