# 직전 6개월 모멘텀 (6-12 구간) — 7~12개월 전 수익(최근 6개월 제외). 장기 추세 지속성. PIT-safe.
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA)); setorder(RAWDATA, Ticker, Date)
RAWDATA[, .Score := shift(Close, 126L) / shift(Close, 252L) - 1, by = Ticker]   # 12개월 전 ~ 6개월 전 구간 수익
RAWDATA[, .ym := format(Date, "%Y-%m")]; .me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
FACTORS <- RAWDATA[Date %in% .me & LiqPass == TRUE & is.finite(.Score), .(Date, Ticker, Score = .Score)]
RAWDATA[, c(".Score", ".ym") := NULL]
cat(sprintf("[fe_mom6_12] rows=%d dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
