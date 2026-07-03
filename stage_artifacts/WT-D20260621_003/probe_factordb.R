suppressMessages({library(data.table); library(arrow)})
setDTthreads(1)
OUT <- "stage_artifacts/WT-D20260621_003/probe_fdb.txt"
w <- function(...) cat(paste0(..., "\n"), file=OUT, append=TRUE); cat("", file=OUT)
fs <- list.files(".cache/factor_db", pattern="factor_db_2025|factor_db_2026", full.names=TRUE)
w("latest factor_db files: ", paste(basename(tail(sort(fs),4)), collapse=", "))
f <- tail(sort(fs),1)
d <- as.data.table(arrow::read_parquet(f))
w("file: ", basename(f), " nrow=", nrow(d), " ncol=", ncol(d))
cols <- names(d)
# find comparator columns
hits <- grep("INV|C19|C02|C04|Composite_Earn|Smart_Money|Foreign_Inst|Agreement|Mom|Residual|M01|M08|M05|M06|M24|M32", cols, value=TRUE, ignore.case=TRUE)
w("comparator-ish cols (", length(hits), "):")
w(paste(sort(hits), collapse="\n"))
