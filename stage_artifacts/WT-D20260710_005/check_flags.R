suppressMessages({library(data.table); library(arrow)})
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
raw <- as.data.table(read_parquet(file.path(ROOT,".cache/RAWDATA.parquet"),
  col_select=c("Date","Ticker","K200","KQ150","UnfaithfulDisc","AdminStock","TradingHalt","Size")))
raw[, Date := as.IDate(as.character(Date))]
raw[, ym := as.integer(format(Date,"%Y%m"))]
cat("date range:", as.character(min(raw$Date)), "..", as.character(max(raw$Date)), " rows:", nrow(raw), "\n")
for(f in c("UnfaithfulDisc","AdminStock","TradingHalt")){
  v <- raw[[f]]
  cat(sprintf("%s: class=%s uniq=%s NA=%d nz=%d\n", f, class(v)[1],
    paste(head(unique(v),6),collapse=","), sum(is.na(v)), sum(v %in% c(1,TRUE) | (is.numeric(v)&v>0),na.rm=TRUE)))
}
# fast month-end: max Date per (Ticker,ym) via join
setkey(raw, Ticker, ym, Date)
me <- raw[raw[, .I[.N], by=.(Ticker,ym)]$V1]
me <- me[(K200==1)|(KQ150==1)]
tofl <- function(x) as.integer(x %in% c(1,TRUE) | (is.numeric(x)&x>0))
me[, u:=tofl(UnfaithfulDisc)][, a:=tofl(AdminStock)][, h:=tofl(TradingHalt)]
me[, anybad := pmax(u,a,h)]
agg <- me[, .(univ=.N, unfaith=sum(u), admin=sum(a), halt=sum(h), anybad=sum(anybad)), by=ym][order(ym)]
cat("\nuniv median:", median(agg$univ), " unfaith/mo:", round(mean(agg$unfaith),2),
    " admin/mo:", round(mean(agg$admin),2), " halt/mo:", round(mean(agg$halt),2),
    " anybad/mo:", round(mean(agg$anybad),2), "\n")
cat("distinct tickers ever anybad:", length(unique(me[anybad==1]$Ticker)),
    " months w/ >=1:", sum(agg$anybad>0), "of", nrow(agg), "\n")
saveRDS(me[, .(Ticker, ym, u, a, h, anybad, Size)], file.path(ROOT,"stage_artifacts/WT-D20260710_005/flags_me.rds"))
saveRDS(agg, file.path(ROOT,"stage_artifacts/WT-D20260710_005/flags_agg.rds"))
cat("DONE\n")
