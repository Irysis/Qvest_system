suppressPackageStartupMessages({library(arrow); library(data.table)})
PR <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot")
p <- file.path(PR,".cache/rawdata.parquet")
cat("=== schema ===\n"); print(names(arrow::open_dataset(p)$schema))
dt <- as.data.table(arrow::open_dataset(p) |> dplyr::select(Date,Ticker,Sector_Lv2) |> dplyr::collect())
cat("\nrows",nrow(dt),"dates",format(min(dt$Date)),format(max(dt$Date)),"NArate",round(mean(is.na(dt$Sector_Lv2)),4),"nsec",uniqueN(dt$Sector_Lv2),"\n")
setorder(dt, Ticker, Date)
dt[, prev := shift(Sector_Lv2), by=Ticker]
ch <- dt[!is.na(Sector_Lv2) & !is.na(prev) & Sector_Lv2 != prev]
cat("\n=== sector change events:", nrow(ch), "\n")
print(ch[, .N, by=.(yr=year(Date))][order(yr)])
