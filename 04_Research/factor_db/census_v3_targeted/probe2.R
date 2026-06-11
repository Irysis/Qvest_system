# probe2.R — K200/KQ150 column types + monthly coverage (diagnostic)
suppressMessages({library(arrow); library(data.table)})
PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
raw <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/rawdata.parquet"),
  col_select = c("Date","Ticker","K200","KQ150")))
cat("class K200:", class(raw$K200), "| class KQ150:", class(raw$KQ150), "\n")
cat("K200 uniques:", paste(head(sort(unique(raw$K200)), 10), collapse=","), "\n")
cat("KQ150 uniques:", paste(head(sort(unique(raw$KQ150)), 10), collapse=","), "\n")
raw[, Date := as.Date(Date)]
for (d in c("2006-12-28","2010-01-29","2020-01-31","2026-04-30")) {
  dd <- as.Date(d)
  sub <- raw[Date >= dd - 6 & Date <= dd]
  if (nrow(sub) == 0) { cat(d, ": no rows\n"); next }
  last_d <- max(sub$Date)
  s2 <- sub[Date == last_d]
  cat(sprintf("%s (last td %s): K200 n=%d KQ150 n=%d union=%d total=%d\n",
      d, as.character(last_d),
      s2[K200 %in% c(1, TRUE), .N], s2[KQ150 %in% c(1, TRUE), .N],
      s2[K200 %in% c(1, TRUE) | KQ150 %in% c(1, TRUE), .N], nrow(s2)))
}
cat("Date range:", as.character(range(raw$Date)), "\n")
cat("DONE\n")
