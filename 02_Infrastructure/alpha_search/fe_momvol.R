# 변동성조정 모멘텀 — Barroso & Santa-Clara (2015), JFE. 6-1 모멘텀 / 실현변동성.
# Score = (6-1 모멘텀) / (126일 실현변동성). 변동성 정규화로 모멘텀 크래시 완화. PIT-safe.
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA)); setorder(RAWDATA, Ticker, Date)
RAWDATA[, .ret := Close / shift(Close, 1L) - 1, by = Ticker]
RAWDATA[, .m1  := frollmean(shift(.ret, 1L),      126L), by = Ticker]   # t-1까지 평균수익
RAWDATA[, .m2  := frollmean(shift(.ret, 1L) ^ 2L, 126L), by = Ticker]   # t-1까지 제곱평균 (분산 = m2-m1^2)
RAWDATA[, .vol := sqrt(pmax(.m2 - .m1 ^ 2L, 0)), by = Ticker]
RAWDATA[, .mom := shift(Close, 21L) / shift(Close, 126L) - 1, by = Ticker]
RAWDATA[, .Score := .mom / (.vol + 1e-8), by = Ticker]
RAWDATA[, .ym := format(Date, "%Y-%m")]; .me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
FACTORS <- RAWDATA[Date %in% .me & LiqPass == TRUE & is.finite(.Score), .(Date, Ticker, Score = .Score)]
RAWDATA[, c(".ret", ".m1", ".m2", ".vol", ".mom", ".Score", ".ym") := NULL]
cat(sprintf("[fe_momvol] rows=%d dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
