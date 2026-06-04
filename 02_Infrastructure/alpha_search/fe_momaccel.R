# 모멘텀 가속 (acceleration) — 최근 6개월 모멘텀 - 직전 6개월 모멘텀. 추세 강화 종목. PIT-safe.
# Gettleman & Marks (2006) momentum change 계열.
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA)); setorder(RAWDATA, Ticker, Date)
RAWDATA[, .m_recent := shift(Close, 21L)  / shift(Close, 126L) - 1, by = Ticker]   # 최근 6-1
RAWDATA[, .m_prior  := shift(Close, 126L) / shift(Close, 252L) - 1, by = Ticker]   # 직전 6개월
RAWDATA[, .Score := .m_recent - .m_prior, by = Ticker]                              # 가속(모멘텀 증가분)
RAWDATA[, .ym := format(Date, "%Y-%m")]; .me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
FACTORS <- RAWDATA[Date %in% .me & LiqPass == TRUE & is.finite(.Score), .(Date, Ticker, Score = .Score)]
RAWDATA[, c(".m_recent", ".m_prior", ".Score", ".ym") := NULL]
cat(sprintf("[fe_momaccel] rows=%d dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
