# 52주 신고가 근접도 — George & Hwang (2004), JF. Close[t] / 52주 최고가.
# 신고가에 가까울수록(0에 근접) 모멘텀 강함. PIT-safe: 최고가는 t-1까지 252일 윈도우.
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA)); setorder(RAWDATA, Ticker, Date)
RAWDATA[, .hi52 := frollapply(shift(Close, 1L), 252L, max, align = "right"), by = Ticker]  # t-1까지 252일 최고가
RAWDATA[, .Score := Close / .hi52 - 1, by = Ticker]   # [-1, 0]: 0=신고가, 음수=하락. 높을수록 모멘텀
RAWDATA[, .ym := format(Date, "%Y-%m")]; .me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
FACTORS <- RAWDATA[Date %in% .me & LiqPass == TRUE & is.finite(.Score), .(Date, Ticker, Score = .Score)]
RAWDATA[, c(".hi52", ".Score", ".ym") := NULL]
cat(sprintf("[fe_mom52w] rows=%d dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
