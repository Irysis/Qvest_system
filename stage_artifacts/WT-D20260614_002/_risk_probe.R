suppressMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
cat("FACTOR_DB_DIR resolved =", FACTOR_DB_DIR, "\n")
ff <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_[0-9]{6}[.]parquet$")
cat("n monthly parquet in FACTOR_DB_DIR:", length(ff), "\n")
if (length(ff)) {
  ym <- sort(gsub("factor_db_([0-9]{6})[.]parquet", "\\1", ff))
  cat("range:", head(ym,1), "-", tail(ym,1), "\n")
}
# RC_16 bt_result: CORE returns for incumbent joint-cov
btp <- "stage_artifacts/alpha_search/20260613_021015_217222/bt_result.rds"
cat("\nRC_16 bt_result exists:", file.exists(btp), "\n")
if (file.exists(btp)) {
  btr <- readRDS(btp)
  cat("bt_result names:", paste(names(btr), collapse=", "), "\n")
  pr <- as.data.table(btr$period_returns)
  br <- as.data.table(btr$benchmark_returns)
  cat("period_returns cols:", paste(names(pr), collapse=","), " nrow:", nrow(pr), "\n")
  print(head(pr, 2)); print(tail(pr, 2))
  cat("benchmark_returns cols:", paste(names(br), collapse=","), " nrow:", nrow(br), "\n")
  print(head(br, 2))
}
