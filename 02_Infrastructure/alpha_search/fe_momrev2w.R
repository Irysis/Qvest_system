# 2주 단기 reversal — 최근 2주(10거래일) 하락 종목 매수(oversold 반등). PIT-safe.
# Score = shift(10)/Close - 1: 2주 하락(Close<shift10)일수록 Score 큼 → 매수. KR 단기 reversal 우세.
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA)); setorder(RAWDATA, Ticker, Date)
RAWDATA[, .Score := shift(Close, 10L) / Close - 1, by = Ticker]   # 2주 전/현재 - 1 (= 역방향 2주수익)
RAWDATA[, .ym := format(Date, "%Y-%m")]; .me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
FACTORS <- RAWDATA[Date %in% .me & LiqPass == TRUE & is.finite(.Score), .(Date, Ticker, Score = .Score)]
RAWDATA[, c(".Score", ".ym") := NULL]
cat(sprintf("[fe_momrev2w] rows=%d dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
