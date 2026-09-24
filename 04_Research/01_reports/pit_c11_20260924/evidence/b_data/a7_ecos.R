suppressPackageStartupMessages({library(data.table); library(arrow)})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache"
e <- as.data.table(read_parquet(file.path(root,"ecos_krw_usd.parquet"), mmap=FALSE)); e[,Date:=as.Date(Date)]
b <- as.data.table(read_parquet(file.path(root,"ecos_bond_rates.parquet"), mmap=FALSE)); b[,Date:=as.Date(Date)]
p <- as.data.table(read_parquet(file.path(root,"ecos_bond_rates_pin20260718wt006.parquet"), mmap=FALSE)); p[,Date:=as.Date(Date)]
m <- as.data.table(read_parquet(file.path(root,"macro_fred.parquet"), mmap=FALSE)); m[,Date:=as.Date(Date)]
cat("ecos_krw weekday dist(1=Sun..7=Sat):", table(factor(wday(e$Date),levels=1:7)), "\n")
kr_hol <- as.Date(c("2025-01-28","2025-01-29","2025-01-30","2025-10-03","2025-10-06","2025-10-07","2025-10-08","2025-10-09","2025-05-05","2025-05-06","2025-06-03","2025-08-15","2026-02-16","2026-02-17","2026-02-18","2026-03-02","2026-05-05","2026-05-25","2026-06-03"))
us_hol <- as.Date(c("2026-07-03","2025-11-27","2025-07-04","2025-01-20","2025-09-01","2025-05-26","2026-01-19"))
cat("ECOS KRW present on KR holidays:", sum(kr_hol %in% e$Date), "/", length(kr_hol), "\n")
cat("ECOS KRW present on US holidays:", sum(us_hol %in% e$Date), "/", length(us_hol), "\n")
g3 <- b[Series=="KR_Gov3Y"]
cat("ECOS Gov3Y present on KR holidays:", sum(kr_hol %in% g3$Date), "/", length(kr_hol), " US holidays:", sum(us_hol %in% g3$Date), "/", length(us_hol), "\n")
# cross-correlation of daily log changes: ECOS KRW(d) vs DEXKOUS(d+h)
dx <- m[Series_ID=="DEXKOUS", .(Date, D=Value)]
e2 <- copy(e)[order(Date)][, dE := c(NA, diff(log(KRW_USD)))]
dx <- dx[order(Date)][, dD := c(NA, diff(log(D)))]
# align on calendar: for each ECOS date d, DEXKOUS change for the US date that is k business-row offset
ed <- merge(e2[, .(Date, dE)], dx[, .(Date, dD)], by="Date")  # common dates
setorder(ed, Date)
cat("\nCross-corr of daily changes on common dates, cor(dECOS_t, dDEX_{t+h}):\n")
for (h in -2:2) { x <- ed$dE; y <- shift(ed$dD, -h); ok <- is.finite(x)&is.finite(y); cat(sprintf("  h=%+d  cor=%.3f  n=%d\n", h, cor(x[ok],y[ok]), sum(ok))) }
cat("\nLevel gap: median |ECOS(d)-DEX(d)|=", round(median(abs(merge(e,dx,by='Date')[, KRW_USD-D]),na.rm=TRUE),2),
    "  median |ECOS(d)-DEX(d-1 row)|=", { z <- merge(e, dx[, .(Date, Dlag=shift(D))], by="Date"); round(median(abs(z$KRW_USD-z$Dlag),na.rm=TRUE),2)},
    "  median |ECOS(d)-DEX(d+1 row)|=", { z <- merge(e, dx[, .(Date, Dlead=shift(D,-1))], by="Date"); round(median(abs(z$KRW_USD-z$Dlead),na.rm=TRUE),2)}, "\n")
cat("\nECOS bond series:\n"); print(b[, .(n=.N, from=min(Date), to=max(Date), dom1=round(mean(mday(Date)==1),3)), by=Series])
cat("\npin (mtime 07-18 23:28) max dates:\n"); print(p[, .(to=max(Date)), by=Series])
cat("\nKR_CPI tail:\n"); print(tail(b[Series=="KR_CPI"],3))
