# S2b — 회전율 배관 무결성: Close/Vol/Size 조정기준 일치 실측 (INV-3 진단의 전제)
suppressWarnings(suppressMessages({library(data.table); library(arrow)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
d <- as.data.table(arrow::read_parquet(".cache/rawdata.parquet",
      col_select = c("Date","Ticker","Close","Vol","Size","Ret")))
d[, Date := as.Date(Date)]
chk <- function(tkr, lo, hi, lab) {
  x <- d[Ticker == tkr & Date >= as.Date(lo) & Date <= as.Date(hi)][order(Date)]
  x[, sh := Size / Close]
  cat(sprintf("\n== %s (%s) n=%d\n", lab, tkr, nrow(x)))
  print(x[, .(Date, Close, Vol, Size, sh = round(sh/1e6, 3), Ret = round(Ret, 4))])
}
# 삼성전자 50:1 액면분할 2018-05-04 (매매재개)
chk("005930", "2018-04-25", "2018-05-11", "Samsung 50:1 split 2018-05")
# 네이버 5:1 액면분할 2018-10-12
chk("035420", "2018-10-05", "2018-10-18", "NAVER 5:1 split 2018-10")
cat("\n== 전체 표본: |dlog(Size/Close)| > 0.4 인 일자 수 vs |dlog(Vol)| 동시 점프 ==\n")
d2 <- d[is.finite(Close) & Close > 0 & is.finite(Size) & Size > 0][order(Ticker, Date)]
d2[, sh := Size / Close]
d2[, dsh := c(NA, diff(log(sh))), by = Ticker]
d2[, dvol := c(NA, diff(log(pmax(Vol, 1)))), by = Ticker]
cat(sprintf("dsh jump days: %d / %d (%.4f%%)\n", sum(abs(d2$dsh) > 0.4, na.rm = TRUE), nrow(d2),
            100*mean(abs(d2$dsh) > 0.4, na.rm = TRUE)))
cat(sprintf("그중 |dvol|>0.4 동반 비율: %.3f\n",
            mean(abs(d2$dvol[abs(d2$dsh) > 0.4]) > 0.4, na.rm = TRUE)))
cat(sprintf("corr(dsh, dvol | dsh jump days) = %.4f\n",
            suppressWarnings(cor(d2$dsh[abs(d2$dsh) > 0.4], d2$dvol[abs(d2$dsh) > 0.4], use = "complete.obs"))))
