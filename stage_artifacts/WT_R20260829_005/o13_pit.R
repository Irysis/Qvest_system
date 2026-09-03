setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/validation/lookahead_detector.R")
out <- list()
for (f in c("stage_artifacts/WT_R20260829_005/o5_recon.R",
            "stage_artifacts/WT_R20260829_005/o7_methods.R",
            "stage_artifacts/WT_R20260829_005/o11_diag.R",
            "stage_artifacts/WT_R20260829_005/o12_emit.R")) {
  cat("\n##################", f, "\n")
  r <- try(detect_lookahead(f, verbose = TRUE), silent = TRUE)
  out[[f]] <- r
  cat("-- class:", paste(class(r), collapse=","), "\n")
  if (!inherits(r, "try-error")) { cat("-- str:\n"); str(r, max.level = 2) }
}
saveRDS(out, "stage_artifacts/WT_R20260829_005/opt_pit.rds")
