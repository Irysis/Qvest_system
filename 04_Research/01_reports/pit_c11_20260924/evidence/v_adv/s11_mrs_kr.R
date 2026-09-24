suppressMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
rg <- as.data.table(read_parquet(paste0(R,"regime_daily_v2.parquet"), mmap=FALSE)); rg[, Date:=as.Date(Date)]; setkey(rg, Date)
bm <- as.data.table(read_parquet(paste0(R,"benchmark.parquet"), mmap=FALSE)); bm[, Date:=as.Date(Date)]
cat("bm cols:", paste(names(bm), collapse=","), "\n")
rc <- intersect(c("Ret","BM_Ret"), names(bm))[1]
bm <- bm[, .(Date, r=get(rc))][!is.na(r)][Date>=as.Date("2005-01-01")]; setkey(bm, Date)
x <- rg[, .(Date, MRS, ax1_VIX, VZ=VIX_z_smooth)][bm, roll=TRUE]   # KR dates, as apply_regime_overlay does
setorder(x, Date); x[, `:=`(dMRS=MRS-shift(MRS), dVZ=VZ-shift(VZ))]
m <- as.data.table(read_parquet(paste0(R,"macro_fred.parquet"), mmap=FALSE)); m[, Date:=as.Date(Date)]
v <- m[Series_ID=="VIXCLS" & !is.na(Value)][order(Date), .(Date, dlv=c(NA, diff(log(Value))))]
# last US session strictly before KR date t  vs  US session on KR date t
x[, us_prev := v[.(x$Date - 1L), on="Date", roll=TRUE]$dlv]
x[, us_same := v[.(x$Date), on="Date", nomatch=NA]$dlv]
f <- function(a,b) round(cor(a,b,use="complete.obs"),3)
cat(sprintf("KR r_t vs dlogVIX US(prev session) = %s ; vs US(same date) = %s\n", f(x$r,x$us_prev), f(x$r,x$us_same)))
cat(sprintf("dMRS_t vs US(prev) = %s ; vs US(same) = %s\n", f(x$dMRS,x$us_prev), f(x$dMRS,x$us_same)))
cat(sprintf("dVIX_z_smooth_t vs US(prev) = %s ; vs US(same) = %s\n", f(x$dVZ,x$us_prev), f(x$dVZ,x$us_same)))
cat(sprintf("KR r_t vs dMRS_t = %s ; KR r_t vs dMRS_{t-1} = %s ; KR r_t vs dVIX_z_smooth_t = %s\n", f(x$r,x$dMRS), f(x$r, shift(x$dMRS)), f(x$r,x$dVZ)))
