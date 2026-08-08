suppressPackageStartupMessages({ library(arrow); library(data.table) })
D <- "04_Research/method_frontier/fq002_contract_magnitude"
for (f in c("grid_returns.parquet","gridx_returns.parquet","grid_bench.parquet","gridx_bench.parquet",
            "grid_universe_size.parquet","gridx_universe_size.parquet","panelx_A.parquet")) {
  p <- file.path(D,f)
  if (!file.exists(p)) { cat(sprintf("  %-28s absent\n", f)); next }
  x <- as.data.table(read_parquet(p))
  dc <- names(x)[grepl("date", names(x), ignore.case=TRUE)]
  rng <- ""
  if (length(dc)) { s <- as.Date(x[[dc[1]]]); rng <- sprintf("%s ~ %s · %d months",
      min(s,na.rm=TRUE), max(s,na.rm=TRUE), uniqueN(format(s,"%Y-%m"))) }
  cat(sprintf("  %-28s rows=%9s cols=%3d  %s\n", f, format(nrow(x), big.mark=","), ncol(x), rng))
}
cat("\n-- gridx_vintage_compare.json --\n")
if (file.exists(file.path(D,"gridx_vintage_compare.json")))
  cat(paste(readLines(file.path(D,"gridx_vintage_compare.json"), warn=FALSE), collapse="\n"), "\n")
