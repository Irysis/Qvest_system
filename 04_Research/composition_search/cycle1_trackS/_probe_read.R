suppressMessages({library(arrow); library(data.table)})
cat("R:", R.version.string, "\n")
for (m in c("201506","202602","202603","202604","202605","202606")) {
  f <- as.data.table(read_parquet(paste0(".cache/factor_db/factor_db_",m,".parquet"),
       col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
  inv <- f[grepl("^INV", Factor_Name)]
  cat(m, "rows:", nrow(f), " INV non-NA Z:", inv[!is.na(Z_Score),.N],
      " INV nfactors:", uniqueN(inv[!is.na(Z_Score)]$Factor_Name), "\n")
  rm(f, inv); invisible(gc(verbose=FALSE))
}
cat("PROBE_DONE\n")
