suppressMessages({library(arrow); library(data.table)})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
out <- file(file.path(root, "qepm/mailbox/worktask/WT-D20260822_012/_probe2.txt"), open = "wt")
w <- function(...) cat(..., "\n", file = out)

# RAWDATA schema (columns only, avoid full load)
sch <- schema(read_parquet(file.path(root, ".cache/RAWDATA.parquet"), as_data_frame = FALSE))
w("=== RAWDATA columns ===")
w(paste(names(sch), collapse = ","))

# investor_wide schema
sch2 <- schema(read_parquet(file.path(root, ".cache/investor_stock/investor_wide.parquet"), as_data_frame = FALSE))
w("\n=== investor_wide columns ===")
w(paste(names(sch2), collapse = ","))

# investor_foreign schema (likely simpler - direction of foreign flow)
sch3 <- schema(read_parquet(file.path(root, ".cache/investor_stock/investor_foreign.parquet"), as_data_frame = FALSE))
w("\n=== investor_foreign columns ===")
w(paste(names(sch3), collapse = ","))
# peek a few rows of foreign
ds <- open_dataset(file.path(root, ".cache/investor_stock/investor_foreign.parquet"))
fh <- as.data.table(head(ds, 3) |> dplyr::collect())
capture.output(print(fh), file = out)
w("foreign date range approx:")
capture.output(print(ds |> dplyr::summarise(mn = min(Date), mx = max(Date)) |> dplyr::collect()), file = out)

close(out)
cat("PROBE2_DONE\n")
