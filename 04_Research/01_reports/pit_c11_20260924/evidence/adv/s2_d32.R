suppressPackageStartupMessages({library(arrow); library(data.table)})
C <- "C:/qm_cache"
run_month <- function(ym, sig_d) {
  m <- as.data.table(read_parquet(file.path(C,"macro_fred.parquet"), mmap=FALSE))
  m[, Date:=as.Date(Date)]
  vix <- m[Series_ID=="VIXCLS" & !is.na(Value), .(Date, VIX=Value)][, .(VIX=last(VIX)), by=Date]; setkey(vix, Date)
  ds <- open_dataset(file.path(C,"RAWDATA.parquet"))
  lo <- sig_d - 365
  rd <- as.data.table(ds |> dplyr::filter(Date >= lo, Date <= sig_d) |> dplyr::select(Date, Ticker, Ret, BM_Ret) |> dplyr::collect())
  rd[, Date:=as.Date(Date)]
  dts <- data.table(Date=sort(unique(rd$Date)))
  # builder convention: same calendar date roll
  v0 <- vix[dts, on="Date", roll=TRUE]; setnames(v0, "VIX", "VIX_same")
  # PIT alternative: KR d uses last US obs with Date <= d-1
  dts1 <- copy(dts)[, Dm1 := Date - 1]
  v1 <- vix[dts1, on=.(Date=Dm1), roll=TRUE][, .(Date=dts1$Date, VIX_lag=VIX)]
  rd <- merge(rd, v0, by="Date", all.x=TRUE); rd <- merge(rd, v1, by="Date", all.x=TRUE)
  setkey(rd, Ticker, Date)
  cat(sprintf("[%s] sig_d=%s  last KR date in slice=%s  VIX_same(last)=%.2f VIX_lag(last)=%.2f  VIX_same(prev)=%.2f\n",
      ym, sig_d, max(rd$Date), v0[.N, VIX_same], v1[.N, VIX_lag], v0[.N-1, VIX_same]))
  est <- function(col, drop_last=FALSE) rd[, {
     sub <- .SD[!is.na(Ret) & !is.na(get(col))]
     if (drop_last) sub <- sub[Date < sig_d]
     b <- NA_real_
     if (nrow(sub) >= 120L) {
       x <- diff(sub[[col]]) / head(sub[[col]], -1); y <- sub$Ret[-1]
       ok <- !is.na(x) & !is.na(y) & is.finite(x)
       if (length(x) >= 119L && sum(ok) >= 60L) { f <- lm.fit(cbind(1, x[ok]), y[ok]); b <- f$coefficients[2] }
     }
     .(b=b)
  }, by=Ticker, .SDcols=c("Date","Ret",col)]
  a <- est("VIX_same"); l <- est("VIX_lag"); t <- est("VIX_same", TRUE)
  fd <- as.data.table(read_parquet(file.path(C,"factor_db",sprintf("factor_db_%s.parquet", ym)), mmap=FALSE))[Factor_Name=="D32_Beta_VIX", .(Ticker, stored=Raw_Value, Z_Score)]
  x <- Reduce(function(p,q) merge(p,q,by="Ticker"), list(fd, a[,.(Ticker, rep_same=b)], l[,.(Ticker, rep_lag=b)], t[,.(Ticker, rep_trunc=b)]))
  x <- x[!is.na(stored)]
  cat(sprintf("  n=%d | replication max|stored-rep_same|=%.3g  (cor %.6f)\n", nrow(x), max(abs(x$stored-x$rep_same), na.rm=TRUE), cor(x$stored, x$rep_same, use="c")))
  cat(sprintf("  same vs lag(PIT): spearman=%.4f  median|diff|/sd=%.3f  top-quintile overlap=%.3f\n",
      cor(x$rep_same, x$rep_lag, method="spearman", use="c"),
      median(abs(x$rep_same-x$rep_lag), na.rm=TRUE)/sd(x$rep_same, na.rm=TRUE),
      { q1 <- x$Ticker[x$rep_same >= quantile(x$rep_same,.8,na.rm=TRUE)]; q2 <- x$Ticker[x$rep_lag >= quantile(x$rep_lag,.8,na.rm=TRUE)]; length(intersect(q1,q2))/length(q1) }))
  cat(sprintf("  same vs truncated(drop sig_d row): spearman=%.4f  median|diff|/sd=%.3f\n",
      cor(x$rep_same, x$rep_trunc, method="spearman", use="c"), median(abs(x$rep_same-x$rep_trunc), na.rm=TRUE)/sd(x$rep_same, na.rm=TRUE)))
  invisible(x)
}
x <- run_month("202608", as.Date("2026-08-31"))
x2 <- run_month("202003", as.Date("2020-03-31"))
