suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
D <- "stage_artifacts/WT_D20260802_001"
for (f in list.files(D, pattern="\.parquet$")) {
  x <- as.data.table(read_parquet(file.path(D,f)))
  cat(sprintf("  %-46s %7d행 %2d열: %s\n", f, nrow(x), ncol(x),
              paste(head(names(x),8), collapse=",")))
}
for (f in list.files(D, pattern="\.csv$")) {
  x <- tryCatch(fread(file.path(D,f), nrows=3), error=function(e) NULL)
  if (!is.null(x)) cat(sprintf("  %-46s (csv) 열: %s\n", f, paste(head(names(x),8), collapse=",")))
}
