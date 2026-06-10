# =============================================================================
# fe_volpremium.R — High-Volume Return Premium (Gervais, Kaniel & Mingelgrin 2001)
# =============================================================================
# 논문: Gervais, Kaniel & Mingelgrin (2001) "The High-Volume Return Premium", JF.
#   비정상적으로 높은 거래량(visibility shock)을 겪은 종목이 이후 양(+)의 초과수익.
#   Score = abnormal volume = Vol / MA20(Vol), t-1 lag(당일 거래량 미사용, C10). high long.
#
# ★ 제1원칙 — 미명시값 보충(명시):
#   - abnormal volume = Vol_{t-1} / 20일 평균. high decile long-only EW. 월간. K200∪KQ150. 2005~.
# ===== PIT =====: .avl = shift(.av, 1L) — 당일(t) 거래량 미사용(C10). NEGATE/FLIP 없음.
# RAWDATA columns: Date, Ticker, Vol, LiqPass
# =============================================================================
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

RAWDATA[, .av  := Vol / frollmean(Vol, 20L, align = "right"), by = Ticker]
RAWDATA[, .avl := shift(.av, 1L), by = Ticker]   # t-1 (C10 당일 거래량 회피)
RAWDATA[, .ym  := format(Date, "%Y-%m")]
.me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

FACTORS <- RAWDATA[Date %in% .me & LiqPass == TRUE & is.finite(.avl) & .avl > 0,
                   .(Date, Ticker, Score = .avl)]                 # high abnormal volume long
FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]
RAWDATA[, c(".av", ".avl", ".ym") := NULL]
cat(sprintf("[fe_volpremium] GKM 2001 high-volume premium | rows=%d dates=%d decile N=%d~%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            if (nrow(FACTORS)) min(FACTORS$N) else 0L, if (nrow(FACTORS)) max(FACTORS$N) else 0L))
