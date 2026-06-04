# 저회전율 (Low Turnover / Liquidity) — Datar, Naik & Radcliffe (1998), J. Financial Markets
# 회전율(거래량/유통주식수) 낮을수록 수익 우위. Score = -평균회전율(252일). PIT: shift(1).
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA)); setorder(RAWDATA, Ticker, Date)
RAWDATA[, .to := shift(Vol, 1L) / Float, by = Ticker]        # 회전율 (Float=유통주식수)
RAWDATA[is.infinite(.to), .to := NA_real_]
RAWDATA[, .Score := -frollmean(.to, 252L), by = Ticker]      # 저회전율 = 높은 Score
RAWDATA[, .ym := format(Date, "%Y-%m")]; .me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
FACTORS <- RAWDATA[Date %in% .me & LiqPass == TRUE & is.finite(.Score), .(Date, Ticker, Score = .Score)]
RAWDATA[, c(".to",".Score",".ym") := NULL]
cat(sprintf("[fe_turnover] rows=%d dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
