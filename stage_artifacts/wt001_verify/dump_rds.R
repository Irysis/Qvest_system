OUT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/WT_D20260808_001"
for (f in c("wt122_results.rds","wt122_control.rds","wt122_addendum.rds","probe_precheck.rds","probe_inputs.rds")) {
  cat("\n\n######## ", f, " ########\n")
  x <- tryCatch(readRDS(file.path(OUT,f)), error=function(e) NULL)
  if (is.null(x)) { cat("READ FAIL\n"); next }
  str(x, max.level=3, list.len=200)
}
