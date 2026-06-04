# 단기 모멘텀 3-1 — Jegadeesh-Titman 변형. 3개월(최근 1개월 제외). PIT-safe.
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA)); setorder(RAWDATA, Ticker, Date)
RAWDATA[, .Score := shift(Close, 21L) / shift(Close, 63L) - 1, by = Ticker]   # 3개월(~63일), 최근 1개월 제외
RAWDATA[, .ym := format(Date, "%Y-%m")]; .me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
FACTORS <- RAWDATA[Date %in% .me & LiqPass == TRUE & is.finite(.Score), .(Date, Ticker, Score = .Score)]
RAWDATA[, c(".Score", ".ym") := NULL]
cat(sprintf("[fe_mom3_1] rows=%d dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
