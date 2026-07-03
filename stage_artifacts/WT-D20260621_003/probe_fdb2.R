suppressMessages({library(data.table); library(arrow)})
setDTthreads(1)
OUT <- "stage_artifacts/WT-D20260621_003/probe_fdb2.txt"
w <- function(...) cat(paste0(..., "\n"), file=OUT, append=TRUE); cat("", file=OUT)
d <- as.data.table(arrow::read_parquet(".cache/factor_db/factor_db_202606.parquet"))
w("cols: ", paste(names(d), collapse=", "))
w("head:\n", paste(capture.output(print(head(d,3))), collapse="\n"))
# if there is a Factor/factor_id column, list distinct
fcol <- intersect(c("Factor","factor_id","FactorID","factor","Field","field"), names(d))
if(length(fcol)>0){
  fc <- fcol[1]
  facs <- sort(unique(d[[fc]]))
  w("n factors: ", length(facs))
  hits <- grep("INV|C19|C02|C04|Composite|Smart|Foreign|Agreement|Mom|Resid|M01|M08|M05|M06|M24|M32", facs, value=TRUE, ignore.case=TRUE)
  w("comparator factors (", length(hits),"):")
  w(paste(hits, collapse="\n"))
} else {
  w("no factor-name column; columns are: ", paste(names(d), collapse=", "))
}
