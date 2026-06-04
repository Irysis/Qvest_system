# 초장기 모멘텀 24-1 — Jegadeesh-Titman 변형. 24개월(최근 1개월 제외). PIT-safe.
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA)); setorder(RAWDATA, Ticker, Date)
RAWDATA[, .Score := shift(Close, 21L) / shift(Close, 504L) - 1, by = Ticker]   # 24개월(~504일), 최근 1개월 제외
RAWDATA[, .ym := format(Date, "%Y-%m")]; .me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
FACTORS <- RAWDATA[Date %in% .me & LiqPass == TRUE & is.finite(.Score), .(Date, Ticker, Score = .Score)]
RAWDATA[, c(".Score", ".ym") := NULL]
cat(sprintf("[fe_mom24_1] rows=%d dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
