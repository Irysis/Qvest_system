PROJ <- "G:/Quant_Module_Moltbot"
source(file.path(PROJ, "02_Infrastructure/config.R"))
source(file.path(PROJ, "02_Infrastructure/backtest_harness.R"))
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
cat("RAWDATA cols:", paste(names(RAWDATA), collapse=", "), "\n")
cat("nrow:", nrow(RAWDATA), "\n")
cat("Date range:", as.character(range(RAWDATA$Date)), "\n")
for (c in c("Size","K200","KQ150","Ret","Close","Vol")) {
  if (c %in% names(RAWDATA)) {
    v <- RAWDATA[[c]]
    cat(sprintf("  %s: class=%s, n_finite=%d, sample=%s\n", c, class(v)[1],
        sum(is.finite(suppressWarnings(as.numeric(v))) | (is.logical(v) & !is.na(v))),
        paste(head(v[!is.na(v)],4), collapse="|")))
  } else cat("  MISSING:", c, "\n")
}
# month-end membership count
RAWDATA[, ym := format(Date,"%Y-%m")]
me <- RAWDATA[, .(Date=max(Date)), by=ym]$Date
ss <- RAWDATA[Date %in% me & (K200==TRUE | KQ150==TRUE)]
cat("avg K200|KQ150 members per month:", round(nrow(ss)/length(me)), "\n")
cat("Size at a recent month-end - is it market cap? head:\n")
print(RAWDATA[Date==max(me) & (K200==TRUE|KQ150==TRUE), .(Ticker,Size)][order(-Size)][1:5])
