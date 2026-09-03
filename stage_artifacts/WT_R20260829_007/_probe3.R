suppressWarnings(suppressMessages({library(data.table);library(arrow)}))
p <- ".cache/investor_stock/investor_wide.parquet"
s <- arrow::open_dataset(p)
cat("cols:", paste(names(s), collapse=", "), "\n")
d <- as.data.table(arrow::read_parquet(p))
cat("rows:", nrow(d), "\n")
dc <- names(d)[sapply(d, function(x) inherits(x,"Date")|inherits(x,"POSIXct"))]
cat("datecols:", paste(dc, collapse=","), "\n")
print(utils::head(d,3))
