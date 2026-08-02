## run_01_probe_inputs.R — screen_inputs.rds(정본 canonical screen 입력) 구조 확인 + base parity 재현
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setDTthreads(2); try(arrow::set_io_thread_count(2), silent = TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)

SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
cat("names(SI):", paste(names(SI), collapse=", "), "\n\n")
for (nm in names(SI)) {
  o <- SI[[nm]]
  cat("---", nm, "---\n")
  if (is.data.frame(o)) {
    o <- as.data.table(o)
    cat(sprintf("  dim=%dx%d cols=%s\n", nrow(o), ncol(o), paste(names(o), collapse=",")))
    if ("Date" %in% names(o)) cat(sprintf("  Date: %s ~ %s (n=%d)\n", min(o$Date), max(o$Date), uniqueN(o$Date)))
    print(head(o, 2))
  } else {
    cat("  class:", class(o), " len:", length(o), "\n")
  }
}
cat("\n[DONE]\n")
