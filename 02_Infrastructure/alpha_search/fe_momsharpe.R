# Sharpe 모멘텀 (risk-adjusted momentum) — 12-1 모멘텀 / 252일 실현변동성.
# 위험조정 모멘텀: 추세의 질(노이즈 대비 추세). Score = (12-1) / vol_252. PIT-safe.
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA)); setorder(RAWDATA, Ticker, Date)
RAWDATA[, .ret := Close / shift(Close, 1L) - 1, by = Ticker]
RAWDATA[, .m1  := frollmean(shift(.ret, 1L),      252L), by = Ticker]
RAWDATA[, .m2  := frollmean(shift(.ret, 1L) ^ 2L, 252L), by = Ticker]
RAWDATA[, .vol := sqrt(pmax(.m2 - .m1 ^ 2L, 0)), by = Ticker]
RAWDATA[, .mom := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]
RAWDATA[, .Score := .mom / (.vol + 1e-8), by = Ticker]
RAWDATA[, .ym := format(Date, "%Y-%m")]; .me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
FACTORS <- RAWDATA[Date %in% .me & LiqPass == TRUE & is.finite(.Score), .(Date, Ticker, Score = .Score)]
RAWDATA[, c(".ret", ".m1", ".m2", ".vol", ".mom", ".Score", ".ym") := NULL]
cat(sprintf("[fe_momsharpe] rows=%d dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
