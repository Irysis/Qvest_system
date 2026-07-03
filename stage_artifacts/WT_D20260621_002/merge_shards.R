# Merge chunk shards into unified panels
Sys.setenv(OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1")
suppressMessages({library(arrow); library(data.table)})
setDTthreads(1); arrow::set_cpu_count(1)
OUT <- "stage_artifacts/WT_D20260621_002"
for (nm in c("pcdm","ref","fwd","adtv")) {
  files <- sort(list.files(OUT, pattern=paste0("^shard_",nm,"_[0-9]+\\.parquet$"), full.names=TRUE))
  stopifnot(length(files) > 0)
  dt <- rbindlist(lapply(files, function(f) as.data.table(read_parquet(f))), use.names=TRUE, fill=TRUE)
  write_parquet(dt, file.path(OUT, paste0(nm, "_panel.parquet")))
  cat(sprintf("%s_panel: %d rows from %d shards\n", nm, nrow(dt), length(files)))
}
cat("MERGE DONE\n")
