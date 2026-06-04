# 중기 모멘텀 6-1 (Momentum) — Jegadeesh & Titman (1993), JF
# 과거 6개월 수익률(최근 1개월 제외) 승자 매수. Score = shift(21)/shift(126)-1. PIT-safe.
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA)); setorder(RAWDATA, Ticker, Date)
RAWDATA[, .Score := shift(Close, 21L) / shift(Close, 126L) - 1, by = Ticker]   # 6개월(~126일), 최근 1개월(~21일) 제외
RAWDATA[, .ym := format(Date, "%Y-%m")]; .me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
FACTORS <- RAWDATA[Date %in% .me & LiqPass == TRUE & is.finite(.Score), .(Date, Ticker, Score = .Score)]
RAWDATA[, c(".Score", ".ym") := NULL]
cat(sprintf("[fe_mom6_1] rows=%d dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
