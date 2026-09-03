suppressPackageStartupMessages({library(data.table);library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
sec <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Sector")))
sec[, Date:=as.Date(Date)]; sec <- sec[Date>=as.Date("2005-01-01")]
tb <- sec[, .N, by=Sector][order(-N)]
print(tb)
