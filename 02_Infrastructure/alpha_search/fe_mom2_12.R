# 중기 모멘텀 2-12 — 최근 2개월 제외 12개월(reversal carryover 회피). PIT-safe.
# KR 연구(IAJ 2024): 최근 2개월 reversal 제외 시 모멘텀 순화.
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA)); setorder(RAWDATA, Ticker, Date)
RAWDATA[, .Score := shift(Close, 42L) / shift(Close, 252L) - 1, by = Ticker]   # 12개월(~252일), 최근 2개월(~42일) 제외
RAWDATA[, .ym := format(Date, "%Y-%m")]; .me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
FACTORS <- RAWDATA[Date %in% .me & LiqPass == TRUE & is.finite(.Score), .(Date, Ticker, Score = .Score)]
RAWDATA[, c(".Score", ".ym") := NULL]
cat(sprintf("[fe_mom2_12] rows=%d dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
