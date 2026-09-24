suppressMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
st <- as.data.table(read_parquet(paste0(R,"factor_db_daily/fdb_daily_202003.parquet"), mmap=FALSE))
cat("cols:", paste(head(names(st),8), collapse=","), "... has D32:", "D32_Beta_VIX" %in% names(st), "\n")
st <- st[, .(Date=as.Date(Date), Ticker, stored=D32_Beta_VIX)]
tks <- head(unique(st[Date==as.Date("2020-03-16") & !is.na(stored)]$Ticker), 400)
rw <- as.data.table(read_parquet(paste0(R,"RAWDATA.parquet"), col_select=c("Date","Ticker","Ret"), mmap=FALSE))[Ticker %in% tks]
rw[, Date:=as.Date(Date)]; rw <- rw[Date >= as.Date("1989-01-01")]; setkey(rw, Ticker, Date)
m <- as.data.table(read_parquet(paste0(R,"macro_fred.parquet"), mmap=FALSE)); m[, Date:=as.Date(Date)]
vix <- m[Series_ID=="VIXCLS" & !is.na(Value), .(VIX=last(Value)), by=Date]; setkey(vix,Date)
dts <- data.table(Date=sort(unique(rw$Date)))
vA <- vix[dts, on="Date", roll=TRUE]; vB <- copy(vix)[, Date:=Date+1L]; setkey(vB,Date); vB <- vB[dts, on="Date", roll=TRUE]
rw <- merge(rw, vA[,.(Date,VA=VIX)], by="Date"); rw <- merge(rw, vB[,.(Date,VB=VIX)], by="Date"); setkey(rw,Ticker,Date)
rb <- function(y,x,n=252L){ ok <- !is.na(y)&!is.na(x); y0<-fifelse(ok,y,0); x0<-fifelse(ok,x,0)
  v<-frollsum(as.numeric(ok),n); sr<-frollsum(y0,n); sb<-frollsum(x0,n); srb<-frollsum(y0*x0,n); sb2<-frollsum(x0*x0,n)
  den <- v*sb2-sb^2; fifelse(v>=3 & abs(den)>1e-12, (v*srb-sr*sb)/den, NA_real_) }
rw[, `:=`(A = rb(Ret, {v<-VA; v[v<=0]<-NA; c(NA,diff(log(v)))}), B = rb(Ret, {v<-VB; v[v<=0]<-NA; c(NA,diff(log(v)))})), by=Ticker]
for (d in c("2020-03-13","2020-03-16","2020-03-17")) {
  x <- merge(st[Date==as.Date(d)], rw[Date==as.Date(d), .(Ticker,A,B)], by="Ticker")[!is.na(stored)&!is.na(A)&!is.na(B)]
  cat(sprintf("%s n=%d  |stored-A|<1e-8: %.3f  |stored-B|<1e-8: %.3f  cor(stored,A)=%.5f cor(stored,B)=%.5f\n", d, nrow(x),
     mean(abs(x$stored-x$A)<1e-8), mean(abs(x$stored-x$B)<1e-8), cor(x$stored,x$A), cor(x$stored,x$B)))
}
