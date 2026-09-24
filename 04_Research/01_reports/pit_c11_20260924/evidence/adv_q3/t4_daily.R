suppressPackageStartupMessages({library(arrow); library(data.table); library(dplyr)})
C <- "C:/qm_cache"
m <- as.data.table(read_parquet(file.path(C,"macro_fred.parquet"), mmap=FALSE)); m[,Date:=as.Date(Date)]
v <- m[Series_ID=="VIXCLS" & !is.na(Value), .(VIX=last(Value)), by=Date]; setorder(v, Date)
ds <- open_dataset(file.path(C,"factor_db_daily","fdb_daily_202003.parquet"))
cn <- names(ds$schema); cat("macro/regime cols in daily:", paste(grep("^RE1|^RE_|D32|^MA0", cn, value=TRUE), collapse=","), "\n")
d <- as.data.table(ds %>% select(any_of(c("Date","Ticker","D32_Beta_VIX","RE10_VIX_Pctile","RE11_VIX_Change_EWMA","RE13_Credit_Spread_Pctile","RE14_Inflation_YoY","RE_VIX_z","RE_MRS"))) %>% collect()); d[,Date:=as.Date(Date)]
mk <- unique(d[, .(Date, RE10_VIX_Pctile, RE11_VIX_Change_EWMA, RE14_Inflation_YoY)])
# RE10 full-sample vs expanding
vv <- copy(v); vv[, full := -frank(VIX, ties.method="average")/.N]; vv[, expd := -sapply(seq_len(.N), function(i) mean(VIX[1:i] <= VIX[i]))]
vv[, lchg := c(NA, diff(log(VIX)))]
ew <- function(x, h=21){a<-1-exp(-log(2)/h); o<-rep(NA_real_,length(x)); o[1]<-x[1]; for(k in 2:length(x)){ if(is.na(x[k])) o[k]<-o[k-1] else if(is.na(o[k-1])) o[k]<-x[k] else o[k]<-a*x[k]+(1-a)*o[k-1]}; o}
vv[, re11 := -ew(lchg)]
setkey(vv, Date)
chk <- mk[Date %in% as.Date(c("2020-03-12","2020-03-13","2020-03-16","2020-03-17","2020-03-31"))]
kk <- chk$Date; kp <- chk$Date - 1L
chk[, full_same := vv[J(kk), roll=TRUE]$full][, full_pit := vv[J(kp), roll=TRUE]$full][, expd_same := vv[J(kk), roll=TRUE]$expd][, re11_same := vv[J(kk), roll=TRUE]$re11][, re11_pit := vv[J(kp), roll=TRUE]$re11]
options(width=200); print(chk[, .(Date, RE10=RE10_VIX_Pctile, full_same, full_pit, expd_same, RE11=RE11_VIX_Change_EWMA, re11_same, re11_pit)])
cat("VIX rows N (full-sample denominator, current file):", nrow(v), "\n")
cpi <- m[Series_ID=="CPIAUCSL", .(Date, CPI=Value)][order(Date)]; cpi[, yoy := CPI/shift(CPI,12)-1]
cat("RE14 daily on 2020-03-31:", unique(mk[Date==as.Date("2020-03-31")]$RE14_Inflation_YoY), " vs -yoy(2020-03-01)=", -cpi[Date==as.Date("2020-03-01")]$yoy, " -yoy(2020-02-01)=", -cpi[Date==as.Date("2020-02-01")]$yoy, "\n")
cat("RE14 daily on 2020-03-02:", unique(mk[Date==as.Date("2020-03-02")]$RE14_Inflation_YoY), "\n")
# D32 daily cross-section on 2020-03-31: same vs pit alignment
rw <- as.data.table(open_dataset(file.path(C,"RAWDATA.parquet")) %>% filter(Date >= as.Date("2018-06-01") & Date <= as.Date("2020-03-31")) %>% select(Date,Ticker,Ret) %>% collect()); rw[,Date:=as.Date(Date)]
kd <- sort(unique(rw$Date)); mp <- data.table(Date=kd, Vs=v[.(Date=kd), on="Date", roll=TRUE]$VIX, Vp=v[.(Date=kd-1L), on="Date", roll=TRUE]$VIX)
rw <- merge(rw, mp, by="Date"); setkey(rw, Ticker, Date)
b <- rw[, { cs <- c(NA, diff(log(Vs))); cp <- c(NA, diff(log(Vp))); n <- .N; i <- max(1,n-251):n
  f <- function(x){ok<-!is.na(Ret[i])&!is.na(x[i])&is.finite(x[i]); if(sum(ok)<3) NA_real_ else cov(Ret[i][ok],x[i][ok])/var(x[i][ok])}
  .(last=Date[n], bs=f(cs), bp=f(cp))}, by=Ticker][last==as.Date("2020-03-31")]
z <- merge(b, d[Date==as.Date("2020-03-31"), .(Ticker, st=D32_Beta_VIX)], by="Ticker")
cat(sprintf("daily D32 2020-03-31: n=%d spearman(stored,same)=%.4f spearman(stored,pit)=%.4f\n", nrow(z[!is.na(st)&!is.na(bs)]), cor(z$st,z$bs,method="spearman",use="c"), cor(z$st,z$bp,method="spearman",use="c")))
