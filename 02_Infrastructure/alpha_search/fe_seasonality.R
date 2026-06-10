# =============================================================================
# fe_seasonality.R — Return Seasonality (Heston-Sadka 2008)
# =============================================================================
# 논문: Heston & Sadka (2008) "Seasonality in the Cross-Section of Stock Returns", JFE.
#   종목의 미래 calendar-month 수익은 과거 same-calendar-month 평균수익과 양(+)의 관계.
#   "stocks with high historical same-month returns continue to outperform in that month."
#
# ★ 제1원칙(완전 복제) — 논문 미명시값 보충(명시):
#   - 시그널: 종목 i, 시점 t(월말)에서 과거 same-calendar-month(month-of-year 일치) 월수익의
#     expanding 평균(현재월 제외). 논문은 Fama-MacBeth 계수로 측정하나, alpha-search는
#     decile long-only 검증 프레임 → high-seasonality decile long-only로 복제(검증 프레임 보충).
#   - 비중·종목수: top decile + equal-weight(run_alpha_search weight_method="equal").
#   - 리밸런싱: 월간. 유니버스 K200∪KQ150(엔진). 기간 2005~.
#
# ===== PIT =====
#   - seas = 과거 same-month 월수익만 사용(shift로 현재월 제외) — forward 정보 없음.
#   - 월수익 = month-end Close 기준(t-1 종가까지). NEGATE/FLIP 없음.
# RAWDATA columns: Date, Ticker, Close, LiqPass ...
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 월말 패널 (종목×월: month-end Close + LiqPass) ----
RAWDATA[, .ymc := format(Date, "%Y-%m")]
.me <- RAWDATA[, .(Date = Date[.N], Close = Close[.N], LiqPass = LiqPass[.N]),
               by = .(Ticker, .ymc)]
setorder(.me, Ticker, Date)

# ---- 월수익 + month-of-year ----
.me[, mret := Close / shift(Close, 1L) - 1, by = Ticker]
.me[, moy := format(Date, "%m")]

# ---- 과거 same-month expanding 평균 (현재월 제외 = PIT) ----
#   cumsum(non-NA)/cumsum(count) = expanding mean(NA 무시); shift(1) = 현재 제외.
setorder(.me, Ticker, moy, Date)
.me[, seas := shift(cumsum(fifelse(is.na(mret), 0, mret)) /
                    pmax(cumsum(as.integer(!is.na(mret))), 1L), 1L),
    by = .(Ticker, moy)]

# ---- FACTORS (월말 + 유동성 통과 + 유효 시그널; top decile) ----
FACTORS <- .me[is.finite(seas) & LiqPass == TRUE, .(Date, Ticker, Score = seas)]
FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]

RAWDATA[, .ymc := NULL]
cat(sprintf("[fe_seasonality] Heston-Sadka 2008 | rows=%d dates=%d decile N=%d~%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            if (nrow(FACTORS)) min(FACTORS$N) else 0L,
            if (nrow(FACTORS)) max(FACTORS$N) else 0L))
