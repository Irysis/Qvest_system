suppressPackageStartupMessages({library(arrow); library(data.table); library(dplyr)})
C <- "C:/qm_cache"
args <- commandArgs(TRUE); ym <- if (length(args)) args[1] else "202608"
fd <- as.data.table(read_parquet(file.path(C,"factor_db",sprintf("factor_db_%s.parquet",ym)), mmap=FALSE))
sig <- max(as.Date(fd$Date)); cat("ym", ym, "sig", format(sig), "\n")
st <- fd[Factor_Name=="D32_Beta_VIX", .(Ticker, stored=Raw_Value)]
rd <- as.data.table(open_dataset(file.path(C,"RAWDATA.parquet")) %>% filter(Date >= !!(sig-366) & Date <= !!sig) %>% select(Date,Ticker,Ret) %>% collect())
rd[, Date:=as.Date(Date)]
m <- as.data.table(read_parquet(file.path(C,"macro_fred.parquet"), mmap=FALSE)); m[,Date:=as.Date(Date)]
v <- m[Series_ID=="VIXCLS" & !is.na(Value), .(VIX=last(Value)), by=Date]; setkey(v, Date)
kd <- sort(unique(rd$Date))
map <- data.table(Date=kd, VIX_same=v[J(kd), roll=TRUE]$VIX, VIX_pit=v[J(kd-1L), roll=TRUE]$VIX)
cat("KR last dates & VIX mapping:\n"); print(tail(map,4))
rd <- merge(rd, map, by="Date"); setkey(rd, Ticker, Date)
rd <- rd[Date >= sig-365 & Date <= sig]
d32 <- function(col) rd[, {
  sub <- .SD[!is.na(Ret) & !is.na(get(col))]
  b <- NA_real_
  if (nrow(sub) >= 120L) {
    x <- sub[[col]]; vc <- diff(x)/head(x,-1); r <- sub$Ret[-1]
    ok <- !is.na(vc)&!is.na(r)&is.finite(vc)
    if (length(vc) >= 119L && sum(ok) >= 60L) { f <- lm.fit(cbind(1,vc[ok]), r[ok]); b <- f$coefficients[2] }
  }
  .(b=b)}, by=Ticker]
a <- d32("VIX_same"); p <- d32("VIX_pit")
rd_full <- rd; rd <- rd[Date < sig]; tr <- d32("VIX_same"); rd <- rd_full
z <- merge(st, a[,.(Ticker,same=b)], by="Ticker"); z <- merge(z, p[,.(Ticker,pit=b)], by="Ticker")
z <- merge(z, tr[,.(Ticker,trunc=b)], by="Ticker"); z <- z[!is.na(stored)]
cat(sprintf("TRUNC (same-align, sig-day pair dropped): cor(stored,trunc)=%.5f spearman=%.5f median|stored-trunc|=%.3g median|stored|=%.3g top-decile overlap=%.3f
", cor(z$stored,z$trunc,use="c"), cor(z$stored,z$trunc,method="spearman",use="c"), median(abs(z$stored-z$trunc),na.rm=T), median(abs(z$stored)), {q1<-z[stored>=quantile(stored,.9)]$Ticker; q2<-z[trunc>=quantile(trunc,.9,na.rm=T)]$Ticker; length(intersect(q1,q2))/length(q1)}))
cat(sprintf("n=%d | match(same,1e-9)=%.4f  median|stored-same|=%.3g  | match(pit,1e-9)=%.4f median|stored-pit|=%.3g\n",
  nrow(z), mean(abs(z$stored-z$same)<1e-9, na.rm=TRUE), median(abs(z$stored-z$same),na.rm=TRUE),
  mean(abs(z$stored-z$pit)<1e-9, na.rm=TRUE), median(abs(z$stored-z$pit),na.rm=TRUE)))
cat(sprintf("cor(stored,same)=%.6f cor(stored,pit)=%.6f  rank cor(same,pit)=%.4f\n", cor(z$stored,z$same,use="c"), cor(z$stored,z$pit,use="c"), cor(z$same,z$pit,method="spearman",use="c")))
cat("top-decile overlap same vs pit:", {q1 <- z[same>=quantile(same,.9,na.rm=T)]$Ticker; q2 <- z[pit>=quantile(pit,.9,na.rm=T)]$Ticker; round(length(intersect(q1,q2))/length(q1),3)}, "\n")
print(head(z[order(-abs(stored-pit))],3))
