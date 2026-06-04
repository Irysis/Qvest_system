# 단기 반전 (Short-term Reversal) — Jegadeesh (1990), JF
# 지난 1개월 패자 매수. Score = -(과거 약 1개월 수익률). PIT: shift(1)로 t-1까지.
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA)); setorder(RAWDATA, Ticker, Date)
RAWDATA[, .rev := -(shift(Close, 1L) / shift(Close, 22L) - 1), by = Ticker]   # 패자 = 높은 Score
RAWDATA[, .ym := format(Date, "%Y-%m")]; .me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
FACTORS <- RAWDATA[Date %in% .me & LiqPass == TRUE & is.finite(.rev), .(Date, Ticker, Score = .rev)]
RAWDATA[, c(".rev", ".ym") := NULL]
cat(sprintf("[fe_streversal] rows=%d dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
