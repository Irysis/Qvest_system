options(warn=1)
cat("R:", R.version.string, "\n")
for (p in c("arrow","data.table","Rcpp","zoo","sandwich","lmtest","jsonlite")) cat(p, requireNamespace(p, quietly=TRUE), "\n")
library(arrow); library(data.table)
f <- ".cache/rawdata.parquet"
cat("exists:", file.exists(f), "\n")
sch <- arrow::open_dataset(f)
print(sch$schema)
cat("nrow:", sch$num_rows, "\n")
