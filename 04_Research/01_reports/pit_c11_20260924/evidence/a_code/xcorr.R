suppressMessages({library(arrow);library(data.table)})
m <- as.data.table(read_parquet(".cache/macro_fred.parquet", mmap=FALSE))[Series_ID %in% c("VIXCLS","SP500")]
m[, Date:=as.Date(Date)]
w <- dcast(m, Date ~ Series_ID, value.var="Value", fun.aggregate=function(x) if (length(x)) x[length(x)] else NA_real_)
setorder(w, Date)
w[, dVIX := c(NA, diff(log(VIXCLS)))]
w[, rSPX := c(NA, diff(log(SP500)))]
b <- as.data.table(read_parquet(".cache/benchmark.parquet", mmap=FALSE))[, .(Date=as.Date(Date), BM_Ret)]
b <- b[Date >= as.Date("2001-01-01") & Date <= as.Date("2026-09-04") & is.finite(BM_Ret)]
setkey(w, Date); setkey(b, Date)
# (A) same calendar date: KR d with US d (US close after KR close)
A <- w[, .(Date, dVIX_same=dVIX, rSPX_same=rSPX)][b, on="Date"]
# (B) latest US obs strictly before KR d (US d-1 close, known KST d ~05-06h, before KR open d)
wu <- w[!is.na(VIXCLS), .(UDate=Date, dVIX_prev=dVIX, rSPX_prev=rSPX)]
b2 <- copy(b); b2[, key := Date - 1L]; setkey(wu, UDate)
B <- wu[b2, on=.(UDate=key), roll=TRUE]
out <- data.table(
  pair=c("KR_ret(d) ~ dlogVIX_US(same d)", "KR_ret(d) ~ dlogVIX_US(last<d)", "KR_ret(d) ~ rSPX_US(same d)", "KR_ret(d) ~ rSPX_US(last<d)"),
  cor=c(A[, cor(BM_Ret, dVIX_same, use="complete.obs")], B[, cor(BM_Ret, dVIX_prev, use="complete.obs")],
        A[, cor(BM_Ret, rSPX_same, use="complete.obs")], B[, cor(BM_Ret, rSPX_prev, use="complete.obs")]),
  n=c(A[, sum(is.finite(BM_Ret)&is.finite(dVIX_same))], B[, sum(is.finite(BM_Ret)&is.finite(dVIX_prev))],
      A[, sum(is.finite(BM_Ret)&is.finite(rSPX_same))], B[, sum(is.finite(BM_Ret)&is.finite(rSPX_prev))]))
print(out)
