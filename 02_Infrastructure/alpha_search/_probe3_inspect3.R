PROJ <- "G:/Quant_Module_Moltbot"
source(file.path(PROJ, "02_Infrastructure/config.R"))
source(file.path(PROJ, "02_Infrastructure/backtest_harness.R"))
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
# Sector_Lv2 in RAWDATA: time-varying? count distinct sectors, NA rate
cat("Sector_Lv2 in RAWDATA: uniq=", length(unique(RAWDATA$Sector_Lv2)),
    "NA_frac=", round(mean(is.na(RAWDATA$Sector_Lv2)),4), "\n")
cat("sample:", paste(head(unique(RAWDATA$Sector_Lv2[!is.na(RAWDATA$Sector_Lv2)]),8), collapse="|"), "\n")
# does a ticker's sector change over time? (time-varying check)
tk <- RAWDATA[!is.na(Sector_Lv2), .N, by=.(Ticker, Sector_Lv2)][, .N, by=Ticker]
cat("tickers with >1 distinct sector over time:", sum(tk$N>1), "/", nrow(tk), "\n")
# sector sizes within K200|KQ150 at recent month
RAWDATA[, ym := format(Date,"%Y-%m")]
me <- RAWDATA[, .(Date=max(Date)), by=ym]$Date
mlast <- max(me)
ss <- RAWDATA[Date==mlast & (K200==1 | KQ150==1) & !is.na(Sector_Lv2)]
st <- ss[, .N, by=Sector_Lv2][order(-N)]
cat("\nAt", as.character(mlast), "within K200|KQ150: n sectors=", nrow(st),
    "n stocks=", nrow(ss), "\n")
print(head(st, 12))
cat("\nsectors with >=4 members (needed for leader/follower split):", sum(st$N>=4), "\n")
