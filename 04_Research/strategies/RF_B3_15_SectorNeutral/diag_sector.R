suppressPackageStartupMessages({library(arrow); library(data.table)})
PR <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot")
p <- file.path(PR,".cache/rawdata.parquet")
sch <- arrow::open_dataset(p)$schema
cat("=== schema names ===\n"); print(names(sch))
dt <- as.data.table(arrow::open_dataset(p) |> dplyr::select(Date,Ticker,Sector_Lv2) |> dplyr::collect())
cat("\n=== rows:", nrow(dt), " date range:", format(min(dt$Date)), "~", format(max(dt$Date)), "\n")
cat("\n=== NA rate:", round(mean(is.na(dt$Sector_Lv2)),4), "\n")
cat("\n=== distinct sectors:", uniqueN(dt$Sector_Lv2), "\n")
print(dt[, .N, by=Sector_Lv2][order(-N)])
# time-varying?
tv <- dt[!is.na(Sector_Lv2), .(nsec = uniqueN(Sector_Lv2)), by=Ticker]
cat("\n=== tickers total:", nrow(tv), " | tickers with >1 sector over time:", sum(tv$nsec>1), "\n")
print(tv[, .N, by=nsec][order(nsec)])
