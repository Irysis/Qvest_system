suppressPackageStartupMessages({library(data.table);library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
fw<-readRDS("stage_artifacts/WT-D20260813_001/final_weights.rds")
snap<-fw$snap
o<-c(paste("snap as_of:",as.character(snap$as_of_date[1]),"holding:",as.character(snap$holding_month[1])))
tb<-snap[,.N,by=sector]
o<-c(o, apply(tb,1,function(r)paste(r,collapse="=")))
# what sector does RAWDATA give for these tickers at latest?
ds<-open_dataset(".cache/RAWDATA.parquet")
raw<-ds|>dplyr::filter(Ticker%in%snap$Ticker)|>dplyr::select(Date,Ticker,Sector)|>dplyr::collect()|>as.data.table()
raw[,ym:=format(as.Date(Date),"%Y%m")]
o<-c(o,paste("max ym in raw:",max(raw$ym)))
last<-raw[, .(Sector=tail(Sector,1), ym=max(ym)), by=Ticker]
o<-c(o,"latest sector per ticker:", apply(last[,.(Ticker,Sector,ym)],1,function(r)paste(r,collapse=" ")))
writeLines(o,"stage_artifacts/WT-D20260813_001/chk_snap.txt")
