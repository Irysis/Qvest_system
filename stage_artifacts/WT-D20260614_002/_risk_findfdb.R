source("02_Infrastructure/config.R")
ff <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_[0-9]{6}[.]parquet$")
cat("n monthly parquet:", length(ff), "\n")
if (length(ff)) {
  ym <- sort(gsub("factor_db_([0-9]{6})[.]parquet", "\\1", ff))
  cat("range:", head(ym, 1), "-", tail(ym, 1), "\n")
}
