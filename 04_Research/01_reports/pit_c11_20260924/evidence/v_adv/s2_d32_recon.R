suppressMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
rd_all <- as.data.table(read_parquet(paste0(R,"RAWDATA.parquet"), col_select=c("Date","Ticker","Ret","BM_Ret"), mmap=FALSE))
rd_all[, Date:=as.Date(Date)]
m <- as.data.table(read_parquet(paste0(R,"macro_fred.parquet"), mmap=FALSE)); m[, Date:=as.Date(Date)]
vix <- m[Series_ID=="VIXCLS" & !is.na(Value), .(VIX=last(Value)), by=Date]; setkey(vix, Date)
d32 <- function(rd, vixcol){
  setkey(rd, Ticker, Date)
  rd[, {
    s <- .SD[!is.na(Ret) & !is.na(get(vixcol))]
    if (nrow(s) < 120L) NULL else {
      vc <- diff(s[[vixcol]])/head(s[[vixcol]],-1); r <- s$Ret[-1]
      ok <- !is.na(vc) & !is.na(r) & is.finite(vc)
      if (sum(ok) < 60L) NULL else { f <- lm.fit(cbind(1,vc[ok]), r[ok]); list(b=unname(f$coefficients[2])) }
    }}, by=Ticker]
}
run <- function(sig, ym){
  sig <- as.Date(sig)
  dts <- data.table(Date=sort(unique(rd_all$Date)))
  vA <- vix[dts, on="Date", roll=TRUE]                                   # builder as coded (same date)
  vB <- copy(vix)[, Date:=Date+1L]; setkey(vB,Date); vB <- vB[dts, on="Date", roll=TRUE]   # 1-day lag (US d-1 -> KR d)
  vC <- vix[Date < sig][dts, on="Date", roll=TRUE]                        # live: US sig not yet published
  rd <- rd_all[Date <= sig & Date >= sig-365]
  rd <- merge(rd, vA[,.(Date,VA=VIX)], by="Date"); rd <- merge(rd, vB[,.(Date,VB=VIX)], by="Date"); rd <- merge(rd, vC[,.(Date,VC=VIX)], by="Date")
  cat(sprintf("\n== sig %s: VIX on sig row: A(same)=%.2f  B(lag1)=%.2f  C(live)=%.2f\n", sig,
      vA[Date==sig,VIX], vB[Date==sig,VIX], vC[Date==sig,VIX]))
  a <- d32(copy(rd),"VA"); b <- d32(copy(rd),"VB"); c <- d32(copy(rd),"VC")
  st <- as.data.table(read_parquet(sprintf("%sfactor_db/factor_db_%s.parquet",R,ym), mmap=FALSE))[Factor_Name=="D32_Beta_VIX", .(Ticker, stored=Raw_Value)]
  x <- Reduce(function(p,q) merge(p,q,by="Ticker"), list(st, a[,.(Ticker,A=b)], b[,.(Ticker,B=b)], c[,.(Ticker,C=b)]))
  cat(sprintf("n stored=%d matched=%d\n", nrow(st), nrow(x)))
  cat(sprintf("max|stored-A|=%.3g  max|stored-B|=%.3g  max|stored-C|=%.3g\n", max(abs(x$stored-x$A)), max(abs(x$stored-x$B)), max(abs(x$stored-x$C))))
  cat(sprintf("share exact(1e-10) A=%.4f B=%.4f C=%.4f\n", mean(abs(x$stored-x$A)<1e-10), mean(abs(x$stored-x$B)<1e-10), mean(abs(x$stored-x$C)<1e-10)))
  cat(sprintf("spearman(stored,B)=%.5f  spearman(A,C)=%.5f  rank-changes top quintile A vs B: %d\n",
      cor(x$stored,x$B,method="spearman"), cor(x$A,x$C,method="spearman"),
      sum(xor(frank(-x$A)<=nrow(x)/5, frank(-x$B)<=nrow(x)/5))))
  cat(sprintf("mean|A-B|/sd(A)=%.4f  mean|A-C|/sd(A)=%.4f\n", mean(abs(x$A-x$B))/sd(x$A), mean(abs(x$A-x$C))/sd(x$A)))
  invisible(x)
}
x1 <- run("2026-08-31","202608")
x2 <- run("2020-03-31","202003")
