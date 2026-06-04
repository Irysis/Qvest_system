# 비유동성 (Illiquidity ILLIQ) — Amihud (2002), J. Financial Markets
# ILLIQ = mean(|일별수익률| / 거래대금) over 252일. 비유동성 프리미엄 → 높을수록 매수.
# PIT: shift(1)로 t-1까지. 거래대금 = Close*Vol.
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA)); setorder(RAWDATA, Ticker, Date)
RAWDATA[, .tv := Close * Vol]
RAWDATA[, .il := abs(shift(Ret, 1L)) / shift(.tv, 1L), by = Ticker]   # 일별 가격충격
RAWDATA[is.infinite(.il), .il := NA_real_]
RAWDATA[, .Score := frollmean(.il, 252L), by = Ticker]                # 252일 평균 = ILLIQ
RAWDATA[, .ym := format(Date, "%Y-%m")]; .me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
FACTORS <- RAWDATA[Date %in% .me & LiqPass == TRUE & is.finite(.Score) & .Score > 0, .(Date, Ticker, Score = .Score)]
RAWDATA[, c(".tv",".il",".Score",".ym") := NULL]
cat(sprintf("[fe_amihud] rows=%d dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
