suppressMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
rg <- as.data.table(read_parquet(paste0(R,"regime_daily_v2.parquet"), mmap=FALSE)); rg[, Date:=as.Date(Date)]
cat("cols:", paste(names(rg), collapse=","), "\n dup names:", any(duplicated(names(rg))), " range:", format(range(rg$Date)), "\n")
m <- as.data.table(read_parquet(paste0(R,"macro_fred.parquet"), mmap=FALSE)); m[, Date:=as.Date(Date)]
w <- dcast(m[Series_ID %in% c("VIXCLS","BAMLH0A0HYM2","T10Y2Y")], Date ~ Series_ID, value.var="Value", fun.aggregate=function(z) if (length(z)) z[length(z)] else NA_real_)
setorder(w, Date)
# US-row changes
for (s in c("VIXCLS","BAMLH0A0HYM2","T10Y2Y")) { x <- w[!is.na(get(s)), .(Date, v=get(s))]; x[, dv:=c(NA,diff(v))]; x[, dv_prev:=shift(dv)]; assign(paste0("u_",s), x) }
setorder(rg, Date)
chk <- function(col, s){
  r <- rg[, .(Date, z=get(col))][, dz:=z-shift(z)]
  u <- get(paste0("u_",s))
  x <- merge(r, u, by="Date")[is.finite(dz)&is.finite(dv)&is.finite(dv_prev)]
  cat(sprintf("%-14s vs %-13s n=%d  cor(dz_t, dUS_t)=%+.3f  cor(dz_t, dUS_{t-1})=%+.3f\n", col, s, nrow(x), cor(x$dz,x$dv), cor(x$dz,x$dv_prev)))
}
chk("VIX_z_smooth","VIXCLS"); chk("HY_z_smooth","BAMLH0A0HYM2"); chk("TS_z_smooth","T10Y2Y")
print(rg[Date >= as.Date("2020-03-11") & Date <= as.Date("2020-03-19"), .(Date, MRS, VIX_z_smooth, HY_z_smooth)])
print(w[Date >= as.Date("2020-03-11") & Date <= as.Date("2020-03-19"), .(Date, VIXCLS)])
