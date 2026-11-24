## 06_smb_outlier_check.R — 트래커 SMB 2026-03 +43.6%(정본 +5.5%)의 원인: 종가 비율 수익 대 Ret 연쇄 대조
##   트래커(ff5_kr_tracker.R:47-50)는 월말 Close/직전 월말 Close − 1 을 쓴다(|ret| ≤ 500% 만 거름).
##   RAWDATA 읽기 = 두 달치 · 5열만(메모리 상한).
suppressMessages({ library(arrow); library(data.table); library(dplyr) })
a <- commandArgs(trailingOnly = TRUE)
M0 <- if (length(a) >= 1) a[1] else "2026-02"; M1 <- if (length(a) >= 2) a[2] else "2026-03"
ds <- open_dataset(".cache/rawdata.parquet")
lo <- as.Date(paste0(M0, "-15")); hi <- seq(as.Date(paste0(M1, "-01")), by = "1 month", length.out = 2)[2] - 1
d <- as.data.table(ds |> filter(Date >= lo & Date <= hi) |> select(Date, Ticker, Close, Size, Ret) |> collect())
rm(ds); invisible(gc())
d[, Date := as.Date(Date)]
me0 <- d[format(Date, "%Y-%m") == M0, max(Date)]; me1 <- d[format(Date, "%Y-%m") == M1, max(Date)]
p0 <- d[Date == me0]; p1 <- d[Date == me1]
x <- merge(p0[, .(Ticker, C0 = Close, S0 = Size)], p1[, .(Ticker, C1 = Close)], by = "Ticker")
x <- x[C0 > 0 & C1 > 0 & S0 > 0]; x[, ret := C1 / C0 - 1]; x <- x[ret <= 5 & ret >= -1]
cmp <- d[Date > me0 & Date <= me1, .(ret_chain = prod(1 + Ret, na.rm = TRUE) - 1, nd = .N), by = Ticker]
x <- merge(x, cmp, by = "Ticker", all.x = TRUE)
med <- median(x$S0); sm <- x[S0 <= med]; bg <- x[S0 > med]
cat(sprintf("월말 %s→%s · 종목 %d · 소형 절반 VW %+.1f%% · 대형 절반 VW %+.1f%% (Ret 연쇄로는 소형 %+.1f%% · 대형 %+.1f%%)\n",
            me0, me1, nrow(x), 100 * sm[, sum(ret * S0) / sum(S0)], 100 * bg[, sum(ret * S0) / sum(S0)],
            100 * sm[is.finite(ret_chain), sum(ret_chain * S0) / sum(S0)], 100 * bg[is.finite(ret_chain), sum(ret_chain * S0) / sum(S0)]))
sm[, contrib := ret * S0 / sum(S0)]
print(sm[order(-abs(contrib))][1:10, .(Ticker, S0_eok = round(S0 / 1e8), C0, C1, ret = round(ret, 3), ret_chain = round(ret_chain, 3), contrib = round(contrib, 4))])
bad <- sm[abs(ret - ret_chain) > 0.2]
cat(sprintf("소형 절반 중 |종가 비율 − Ret 연쇄| > 20%%p 종목 %d개 · 그 종목들의 소형 VW 기여 합 %+.1f%%p\n", nrow(bad), 100 * sum(bad$contrib)))
