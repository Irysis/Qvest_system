suppressMessages({library(data.table); library(arrow)})
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(root, "02_Infrastructure", "config.R"))
cat("RAWDATA_CACHE:", RAWDATA_CACHE, "\n exists:", file.exists(RAWDATA_CACHE), "\n")
RD <- as.data.table(arrow::read_parquet(RAWDATA_CACHE))
cat("\nRAWDATA cols:\n"); print(names(RD))
cat("\nDate range:", as.character(min(RD$Date)), "->", as.character(max(RD$Date)), "\n")
cat("Ticker sample:\n"); print(head(unique(RD$Ticker), 8))
cat("Ticker nchar:", paste(range(nchar(unique(RD$Ticker))), collapse="-"), "\n")
memcols <- intersect(c("K200","KQ150","Size","Ret","Close","Vol"), names(RD))
cat("\nmembership/size cols present:", paste(memcols, collapse=", "), "\n")
if ("K200" %in% names(RD))  { cat("K200 class:", class(RD$K200), " | table:\n"); print(table(RD$K200, useNA="always")) }
if ("KQ150" %in% names(RD)) { cat("KQ150 class:", class(RD$KQ150), " | table:\n"); print(table(RD$KQ150, useNA="always")) }
# membership coverage over time (any K200/KQ150 per month)
if (all(c("K200","KQ150") %in% names(RD))) {
  RD[, ym := format(Date, "%Y-%m")]
  mm <- RD[, .(nK200 = sum(K200==TRUE, na.rm=TRUE), nKQ150 = sum(KQ150==TRUE, na.rm=TRUE)), by=ym][order(ym)]
  cat("\nmembership by month (head/tail):\n"); print(head(mm,3)); print(tail(mm,3))
}
