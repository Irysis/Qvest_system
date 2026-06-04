# 중기 모멘텀 9-1 (Momentum) — Jegadeesh & Titman (1993) 변형. 9개월(최근 1개월 제외).
# Score = shift(21)/shift(189)-1. PIT-safe.
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA)); setorder(RAWDATA, Ticker, Date)
RAWDATA[, .Score := shift(Close, 21L) / shift(Close, 189L) - 1, by = Ticker]   # 9개월(~189일), 최근 1개월 제외
RAWDATA[, .ym := format(Date, "%Y-%m")]; .me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
FACTORS <- RAWDATA[Date %in% .me & LiqPass == TRUE & is.finite(.Score), .(Date, Ticker, Score = .Score)]
RAWDATA[, c(".Score", ".ym") := NULL]
cat(sprintf("[fe_mom9_1] rows=%d dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
