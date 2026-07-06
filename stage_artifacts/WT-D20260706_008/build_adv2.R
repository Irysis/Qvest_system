suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")
TMP <- "C:/Users/99922/AppData/Local/Temp/claude"
panel <- readRDS(file.path(TMP,"wt008_panel.rds")); setDT(panel)
tickers <- unique(panel$Ticker)
cat("panel tickers:", length(tickers), "\n")
# read only needed tickers via arrow filter
ds <- open_dataset(".cache/RAWDATA.parquet")
rd <- as.data.table(ds |> dplyr::filter(Ticker %in% tickers, Date >= as.Date("2015-11-01")) |>
  dplyr::select(Date,Ticker,Close,Vol) |> dplyr::collect())
rd[, Date := as.Date(Date)]
rd[, trade_val := Vol*Close]
rd[, ym := format(Date,"%Y-%m")]
# monthly mean daily trade value = adv proxy (KRW)
adv <- rd[, .(adv_m = mean(trade_val, na.rm=TRUE)), by=.(Ticker, ym)]
saveRDS(adv, file.path(TMP,"wt008_adv.rds"))
cat("adv rows:", nrow(adv), "\n")
print(summary(adv$adv_m))
