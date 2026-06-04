# 저베타 (Betting Against Beta) — Frazzini & Pedersen (2014), JFE
# 저베타 매수. beta = cov(r,bm)/var(bm) over 252일. Score = -beta. PIT: shift(1).
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA)); setorder(RAWDATA, Ticker, Date)
RAWDATA[, .r := shift(Ret, 1L), by = Ticker]
RAWDATA[, .b := shift(BM_Ret, 1L), by = Ticker]
RAWDATA[, .rb := .r * .b]; RAWDATA[, .b2 := .b^2]
RAWDATA[, .mr := frollmean(.r, 252L), by = Ticker]
RAWDATA[, .mb := frollmean(.b, 252L), by = Ticker]
RAWDATA[, .mrb := frollmean(.rb, 252L), by = Ticker]
RAWDATA[, .mb2 := frollmean(.b2, 252L), by = Ticker]
RAWDATA[, .cov := .mrb - .mr * .mb]
RAWDATA[, .var := .mb2 - .mb^2]
RAWDATA[, .beta := .cov / .var]
RAWDATA[, .Score := -.beta]                                  # 저베타 = 높은 Score
RAWDATA[, .ym := format(Date, "%Y-%m")]; .me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
FACTORS <- RAWDATA[Date %in% .me & LiqPass == TRUE & is.finite(.Score) & .var > 0, .(Date, Ticker, Score = .Score)]
RAWDATA[, c(".r",".b",".rb",".b2",".mr",".mb",".mrb",".mb2",".cov",".var",".beta",".Score",".ym") := NULL]
cat(sprintf("[fe_bab] rows=%d dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
