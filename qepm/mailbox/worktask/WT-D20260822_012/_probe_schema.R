suppressMessages({library(arrow); library(data.table)})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
out <- file(file.path(root, "qepm/mailbox/worktask/WT-D20260822_012/_probe_schema.txt"), open = "wt")
w <- function(...) cat(..., "\n", file = out)

mb <- as.data.table(read_parquet(file.path(root, ".cache/macro_beta_scores.parquet")))
w("=== macro_beta_scores ===")
w("cols:", paste(names(mb), collapse = ","))
w("nrow:", nrow(mb))
w("dates:", as.character(min(mb$Date)), "~", as.character(max(mb$Date)))
w("n_unique_dates:", length(unique(mb$Date)), " n_unique_ticker:", length(unique(mb$Ticker)))
w("head:")
capture.output(print(head(mb, 3)), file = out)
# per-date count distribution
nd <- mb[, .N, by = Date]
w("names_per_date quantiles:", paste(round(quantile(nd$N, c(0,.25,.5,.75,1))), collapse=","))

fm <- as.data.table(read_parquet(file.path(root, ".cache/fred_macro.parquet")))
w("\n=== fred_macro ===")
w("cols:", paste(names(fm), collapse = ","))
w("nrow:", nrow(fm))
w("Series values:", paste(sort(unique(fm$Series)), collapse=","))
if ("Frequency" %in% names(fm)) w("Frequency values:", paste(sort(unique(fm$Frequency)), collapse=","))
w("head:")
capture.output(print(head(fm, 3)), file = out)
# target series check
tgt <- c("T10Y2Y","VIXCLS","VIX","KRW_USD","KRWUSD","Term_Spread")
for (s in tgt) {
  sub <- fm[Series == s]
  if (nrow(sub) > 0) {
    fr <- if ("Frequency" %in% names(fm)) paste(unique(sub$Frequency), collapse="/") else "?"
    w(sprintf("  %s: n=%d freq=%s range=%s~%s", s, nrow(sub), fr,
              as.character(min(sub$Date)), as.character(max(sub$Date))))
  }
}
close(out)
cat("PROBE_DONE\n")
