suppressPackageStartupMessages({ library(arrow); library(data.table) })
PR <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
iw <- file.path(PR, ".cache/investor_stock/investor_wide.parquet")
if (file.exists(iw)) {
  d <- tryCatch(read_parquet(iw, as_data_frame=FALSE), error=function(e)NULL)
  if(!is.null(d)) cat("investor_wide cols:", paste(names(d), collapse=", "), "\n")
} else cat("investor_wide NOT FOUND\n")
# any lending/short columns anywhere in dart_raw
dr <- file.path(PR, "03_Universe/dart_raw")
if (dir.exists(dr)) cat("dart_raw files:", length(list.files(dr, pattern="parquet")), "\n")
