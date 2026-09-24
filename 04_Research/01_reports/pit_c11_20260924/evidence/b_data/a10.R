suppressPackageStartupMessages({library(data.table); library(arrow); library(dplyr)})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache"
bm <- as.data.table(open_dataset(file.path(root,"RAWDATA.parquet")) %>% select(Date, BM_Ret) %>% collect())
bm[, Date := as.Date(Date)]; bm <- bm[!is.na(BM_Ret), .(BM_Ret = BM_Ret[1]), by=Date]; setorder(bm, Date)
m <- as.data.table(read_parquet(file.path(root,"macro_fred.parquet"), mmap=FALSE)); m[,Date:=as.Date(Date)]
v <- m[Series_ID=="VIXCLS", .(Date, VIX=Value)][order(Date)][, dV := c(NA, diff(log(VIX)))]
# builder rule: KR date d gets VIX with US Date <= d (roll). PIT rule: US Date <= d-1.
setkey(v, Date)
bm[, vix_same := v[J(bm$Date), roll=TRUE]$VIX]
bm[, vix_pit  := v[J(bm$Date - 1L), roll=TRUE]$VIX]
bm[, dsame := c(NA, diff(log(vix_same)))]; bm[, dpit := c(NA, diff(log(vix_pit)))]
bm[, next_ret := shift(BM_Ret, -1)]
bm <- bm[Date >= as.Date("2005-01-01")]
ok <- function(a,b) {i <- is.finite(a)&is.finite(b); c(cor=round(cor(a[i],b[i]),3), n=sum(i))}
cat("share of KR dates where builder VIX != PIT VIX:", round(mean(bm$vix_same != bm$vix_pit, na.rm=TRUE),3), "\n")
cat("cor(dVIX builder-aligned at d, KR BM_Ret d)   :", ok(bm$dsame, bm$BM_Ret), "\n")
cat("cor(dVIX builder-aligned at d, KR BM_Ret d+1) :", ok(bm$dsame, bm$next_ret), "  <- leak channel (US session d drives KR d+1)\n")
cat("cor(dVIX PIT-aligned at d, KR BM_Ret d)       :", ok(bm$dpit, bm$BM_Ret), "\n")
cat("cor(dVIX PIT-aligned at d, KR BM_Ret d+1)     :", ok(bm$dpit, bm$next_ret), "\n")
