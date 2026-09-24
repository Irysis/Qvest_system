suppressPackageStartupMessages({library(arrow); library(data.table); library(dplyr)})
C <- "C:/qm_cache"
m0 <- as.data.table(read_parquet(file.path(C,"macro_fred.parquet"), mmap=FALSE)); m0[,Date:=as.Date(Date)]
m0[, Series := fifelse(!is.na(Series_ID) & nchar(Series_ID)>0, Series_ID, Series)]
run <- function(ym) {
  fd <- as.data.table(read_parquet(file.path(C,"factor_db",sprintf("factor_db_%s.parquet",ym)), mmap=FALSE))
  sig <- max(as.Date(fd$Date)); cat("\n==== ym", ym, "sig", format(sig), " MA factors present:", paste(unique(grep("^MA0", fd$Factor_Name, value=TRUE)), collapse=","), "\n")
  rd <- as.data.table(open_dataset(file.path(C,"RAWDATA.parquet")) %>% filter(Date >= !!(sig-365) & Date <= !!sig) %>% select(Date,Ticker,Ret) %>% collect()); rd[,Date:=as.Date(Date)]
  rdm <- rd[!is.na(Ret) | TRUE, .(monthly_ret = prod(1+Ret, na.rm=TRUE)-1), by=.(Ticker, YM=format(Date,"%Y-%m"))]
  MAC <- m0[Date <= sig-1L & !is.na(Value)]; setorder(MAC, Series, Date); MAC <- unique(MAC, by=c("Series","Date"), fromLast=TRUE)
  mb <- function(MACRO, s) {
    ms <- MACRO[Series==s & !is.na(Value)]; setorder(ms, Date); ms[, YM:=format(Date,"%Y-%m")]; ms <- ms[, .SD[.N], by=YM]; setorder(ms, YM)
    ms[, macro_chg := Value - shift(Value,1)]; ms <- ms[!is.na(macro_chg), .(YM, macro_chg)]
    mg <- merge(rdm, ms, by="YM"); mg <- mg[!is.na(monthly_ret)&!is.na(macro_chg)]
    list(last=tail(ms,2), b=mg[, {if (.N>=12L) {f<-lm.fit(cbind(1,macro_chg), monthly_ret); .(beta=f$coefficients[2], n=.N)} else .(beta=NA_real_, n=.N)}, by=Ticker][!is.na(beta)])
  }
  first_of_month <- as.Date(format(sig, "%Y-%m-01"))
  for (pair in list(c("INDPRO","MA01_GDP_Sensitivity"), c("CPIAUCSL","MA02_CPI_Sensitivity"))) {
    s <- pair[1]; fn <- pair[2]
    st <- fd[Factor_Name==fn, .(Ticker, stored=Raw_Value)]
    a <- mb(MAC, s); p <- mb(MAC[!(Series==s & Date >= first_of_month)], s)
    cat(sprintf("-- %s (%s): coded-path last macro rows:\n", fn, s)); print(a$last)
    cat(sprintf("   n tickers coded=%d pit=%d stored=%d; coded n_obs median=%s pit n_obs median=%s\n", nrow(a$b), nrow(p$b), nrow(st), median(a$b$n), median(p$b$n)))
    if (nrow(st)) {
      z <- merge(st, a$b[,.(Ticker,coded=beta)], by="Ticker", all.x=TRUE); z <- merge(z, p$b[,.(Ticker,pit=beta)], by="Ticker", all.x=TRUE)
      cat(sprintf("   match(stored,coded)=%.4f n_both_coded=%d
", mean(abs(z$stored-z$coded)<1e-9,na.rm=TRUE), sum(!is.na(z$coded))))
      if (sum(!is.na(z$pit))>10) cat(sprintf("   match(stored,pit)=%.4f spearman(stored,pit)=%.4f n_pit=%d
", mean(abs(z$stored-z$pit)<1e-9,na.rm=TRUE), cor(z$stored,z$pit,method="spearman",use="c"), sum(!is.na(z$pit)))) else cat("   PIT variant: factor not computable (n_obs<12 for all tickers)
")
    }
  }
}
for (ym in commandArgs(TRUE)) run(ym)
