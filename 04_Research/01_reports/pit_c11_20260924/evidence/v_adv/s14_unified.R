suppressMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
u <- as.data.table(read_parquet(paste0(R,"unified_regime_signal_daily.parquet"), mmap=FALSE)); u[, Date:=as.Date(Date)]; setorder(u, Date)
cat("cols:", paste(names(u), collapse=","), " range:", format(range(u$Date)), "\n")
m <- as.data.table(read_parquet(paste0(R,"macro_fred.parquet"), mmap=FALSE)); m[, Date:=as.Date(Date)]
v <- m[Series_ID=="VIXCLS" & !is.na(Value)][order(Date), .(Date, VIX=Value, dv=c(NA,diff(Value)))]
x <- merge(u[, .(Date, FRED_MRS)], v, by="Date"); x[, dF := FRED_MRS - shift(FRED_MRS)]; x[, dv_prev := shift(dv)]
cat(sprintf("US-trading rows n=%d cor(dFRED_MRS_t, dVIX_t)=%.3f  cor(dFRED_MRS_t, dVIX_{t-1})=%.3f\n", nrow(x), cor(x$dF,x$dv,use="c"), cor(x$dF,x$dv_prev,use="c")))
print(merge(u[Date>=as.Date("2020-03-11")&Date<=as.Date("2020-03-18"), .(Date, FRED_MRS, Category=if("Category"%in%names(u)) Category else NA)], v[, .(Date, VIX)], by="Date", all.x=TRUE))
