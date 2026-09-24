suppressMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
st <- as.data.table(read_parquet(paste0(R,"factor_db_daily/fdb_daily_200810.parquet"), mmap=FALSE))
cols <- intersect(c("RE10_VIX_Pctile","RE11_VIX_Change_EWMA","RE13_Credit_Spread_Pctile","RE14_Inflation_YoY","RE_VIX_z","RE_MRS"), names(st))
cat("present:", paste(cols, collapse=","), "\n")
st <- unique(st[, c("Date", cols), with=FALSE]); st[, Date:=as.Date(Date)]
m <- as.data.table(read_parquet(paste0(R,"macro_fred.parquet"), mmap=FALSE)); m[, Date:=as.Date(Date)]
v <- m[Series_ID=="VIXCLS" & !is.na(Value), .(VIX=last(Value)), by=Date][Date <= as.Date("2026-07-24")]; setorder(v, Date)
v[, full := -frank(VIX, ties.method="average")/.N]
v[, expd := -sapply(seq_len(.N), function(i) mean(VIX[1:i] <= VIX[i]))]   # expanding pct (approx)
d <- as.Date(c("2008-10-24","2008-10-27","2008-10-28"))
for (dd in as.list(d)) {
  s <- st[Date==dd]; vs <- v[Date==dd]; vp <- v[Date==dd-1L]
  cat(sprintf("%s stored RE10=%.6f | full-sample same-date=%.6f | expanding same-date=%.6f | VIX same-date=%.2f prev=%.2f | stored RE14=%.6f\n",
     dd, s$RE10_VIX_Pctile, vs$full, vs$expd, vs$VIX, if(nrow(vp)) vp$VIX else NA, s$RE14_Inflation_YoY))
}
cpi <- m[Series_ID=="CPIAUCSL"][order(Date)]; cpi[, yoy:=-(Value/shift(Value,12)-1)]
cat("CPI yoy(neg) 2008-09-01 ref:", cpi[Date==as.Date("2008-09-01")]$yoy, " 2008-10-01 ref:", cpi[Date==as.Date("2008-10-01")]$yoy, "\n")
