suppressPackageStartupMessages({library(data.table); library(arrow)})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache"
m <- as.data.table(read_parquet(file.path(root,"macro_fred.parquet"), mmap=FALSE))
m[, Date := as.Date(Date)]
cat("cols:", names(m), "\n"); cat("rows:", nrow(m), "\n")
s <- m[, .(n=.N, from=min(Date), to=max(Date), freq=Frequency[1],
           dom1=mean(mday(Date)==1), wd=paste(names(table(factor(weekdays(Date),levels=c("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday")))), table(factor(weekdays(Date),levels=c("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"))), sep=":", collapse=" ")), by=.(Series,Series_ID)]
print(s[, .(Series_ID, freq, n, from, to, dom1=round(dom1,3))])
cat("\nweekday dist:\n"); for (i in seq_len(nrow(s))) cat(sprintf("%-14s %s\n", s$Series_ID[i], gsub("day","",s$wd[i])))
# last 5 rows per daily series
cat("\nlast obs per series:\n")
print(m[, tail(.SD,2), by=Series_ID][, .(Series_ID, Date, Value)])
f <- as.data.table(read_parquet(file.path(root,"fred_macro.parquet"), mmap=FALSE)); f[,Date:=as.Date(Date)]
cat("\nfred_macro.parquet:", nrow(f), "rows, series", uniqueN(f$Series_ID), " to", format(max(f$Date)), "\n")
w <- as.data.table(read_parquet(file.path(root,"fred_macro_wide.parquet"), mmap=FALSE))
cat("fred_macro_wide cols:", names(w), "\n"); print(tail(w[, .(Date, VIX, US_10Y_Yield, KRW_USD)], 6))
