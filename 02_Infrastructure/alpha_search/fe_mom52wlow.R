# 52주 신저가 근접 reversal — 52주 최저가 근접(oversold) 종목 매수. PIT-safe.
# Score = 52주최저/Close - 1: 신저가 근접(Close≈low, Score≈0)일수록 큼 → oversold 매수. George-Hwang 역.
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA)); setorder(RAWDATA, Ticker, Date)
RAWDATA[, .lo52 := frollapply(shift(Close, 1L), 252L, min, align = "right"), by = Ticker]  # t-1까지 252일 최저가
RAWDATA[, .Score := .lo52 / Close - 1, by = Ticker]   # 신저가 근접(0)일수록 매수, 멀수록(상승) 음수
RAWDATA[, .ym := format(Date, "%Y-%m")]; .me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
FACTORS <- RAWDATA[Date %in% .me & LiqPass == TRUE & is.finite(.Score), .(Date, Ticker, Score = .Score)]
RAWDATA[, c(".lo52", ".Score", ".ym") := NULL]
cat(sprintf("[fe_mom52wlow] rows=%d dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
