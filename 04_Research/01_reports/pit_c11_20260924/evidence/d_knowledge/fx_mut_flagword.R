build_vix <- function(RAWDATA, CACHE_DIR, verbose_flag = TRUE) {
  macro <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))
  vix <- macro[Series_ID == "VIXCLS", .(Date, VIX = Value)]
  out <- merge(RAWDATA, vix, by = "Date", all.x = TRUE)
  out
}
