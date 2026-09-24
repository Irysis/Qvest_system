build_vix <- function(RAWDATA, CACHE_DIR) {
  fn <- paste0("macro_", "fred.parquet")
  macro <- as.data.table(read_parquet(file.path(CACHE_DIR, fn)))
  vix <- macro[Series_ID == "VIXCLS", .(Date, VIX = Value)]
  merge(RAWDATA, vix, by = "Date", all.x = TRUE)
}
