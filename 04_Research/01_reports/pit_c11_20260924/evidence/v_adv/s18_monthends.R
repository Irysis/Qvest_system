suppressMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
d <- unique(as.data.table(read_parquet(paste0(R,"RAWDATA.parquet"), col_select="Date", mmap=FALSE)))[, Date:=as.Date(Date)]
me <- d[Date>=as.Date("2005-01-01") & Date<=as.Date("2026-08-31"), .(sig=max(Date)), by=format(Date,"%Y%m")]$sig
m <- as.data.table(read_parquet(paste0(R,"macro_fred.parquet"), mmap=FALSE)); m[, Date:=as.Date(Date)]
vd <- m[Series_ID=="VIXCLS" & !is.na(Value)]$Date
cat(sprintf("KR month-ends 2005-01..2026-08: %d ; with US VIX print dated same day: %d (%.1f%%)\n", length(me), sum(me %in% vd), 100*mean(me %in% vd)))
