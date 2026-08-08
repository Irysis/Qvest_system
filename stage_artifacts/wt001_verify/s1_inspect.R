setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- "stage_artifacts/WT_D20260808_001"
for (f in c("wt122_results.rds","wt122_control.rds","wt122_addendum.rds","precheck_results.rds")) {
  x <- readRDS(file.path(OUT,f))
  cat("=====", f, "=====\n")
  cat("names:", paste(names(x), collapse=" | "), "\n")
  str(x, max.level=2, list.len=20)
}
