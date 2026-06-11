# Cross-check aligned book_ret vs READ-ONLY production CSV ret_L5_V2
suppressMessages(library(data.table))
al <- readRDS("../aligned_series.rds")
book <- fread("C:/Users/99922/OneDrive/Quant_Module_Moltbot/05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
cat("book csv rows:", nrow(book), "| cols:", paste(head(names(book), 12), collapse=","), "\n")
cat("book csv realized_ym range:", min(book$realized_ym), "..", max(book$realized_ym), "\n")
m <- merge(al[, c("realized_ym","book_ret")], book[, .(realized_ym, ret_L5_V2)], by = "realized_ym")
cat("matched months:", nrow(m), "\n")
cat("max|aligned book_ret - csv ret_L5_V2| =", format(max(abs(m$book_ret - m$ret_L5_V2)), digits = 6), "\n")
# contiguity of 248 months
ym <- as.integer(substr(al$realized_ym,1,4)) * 12 + as.integer(substr(al$realized_ym,6,7))
cat("contiguous monthly index:", all(diff(ym) == 1), "\n")
# how many book months were dropped by intersection (value sleeve availability)
cat("book csv non-NA ret_L5_V2 months:", sum(!is.na(book$ret_L5_V2)), "\n")
