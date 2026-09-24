suppressMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
rg <- as.data.table(read_parquet(paste0(R,"regime_daily_v2.parquet"), mmap=FALSE)); rg[, Date:=as.Date(Date)]; setorder(rg, Date)
m <- as.data.table(read_parquet(paste0(R,"macro_fred.parquet"), mmap=FALSE)); m[, Date:=as.Date(Date)]
cal <- data.table(Date=seq(min(rg$Date), max(rg$Date), by="day"))
for (pr in list(c("NFCI_z_smooth","NFCI",5), c("FinStress_z_smooth","STLFSI4",6), c("Claims_z_smooth","ICSA",5), c("Sentiment_z_smooth","UMCSENT",NA))) {
  z <- rg[, .(Date, z=get(pr[1]))]; z <- z[cal, on="Date", roll=TRUE]; z[, dz := z - shift(z)]
  u <- m[Series_ID==pr[2] & !is.na(Value)][order(Date)][, .(Date, dv=c(NA,diff(Value)))][!is.na(dv)]
  out <- sapply(0:9, function(k){ x <- merge(u[, .(Date=Date+k, dv)], z, by="Date")[is.finite(dz)]; round(cor(x$dz, x$dv),3) })
  cat(sprintf("%-19s %-8s dow(obs)=%s nominal_pub_lag=%s  cor(dz[D+k], dObs[D]) k=0..9: %s\n", pr[1], pr[2],
      names(which.max(table(weekdays(u$Date)))), pr[3], paste(out, collapse=" ")))
}
# which calendar dates exist in rg grid (weekday distribution)
print(table(weekdays(rg$Date)))
