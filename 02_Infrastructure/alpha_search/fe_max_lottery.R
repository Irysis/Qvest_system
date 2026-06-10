# =============================================================================
# fe_max_lottery.R — MAX 복권성향 (Bali, Cakici, Whitelaw 2011, JFE) 충실 복제
# =============================================================================
# 가설: 직전 calendar month의 일간수익 극단상승(복권성)이 큰 종목이 과대평가→저조.
#   MAX5 = 직전 한 달 일간수익 중 상위 5개의 평균. 높을수록 미래수익 낮음.
#   → 매수는 LOW MAX. Score = -MAX5 (낮은 복권성일수록 매수 우선).
# 충실복제: MAX5(논문 주 정의, MAX1도 보고). decile long-leg(낮은 MAX 상위 N), EW.
#   유니버스/기간 모드 표준(K200∪KQ150·2005~). VW 미가용→EW 보충(명시).
# PIT: MAX5는 직전 calendar month(month t) 일간수익만 사용 → 월말(t) 신호·익월(t+1) 집행.
#   동일시점 순환 없음(미래 미사용). groupby-month 집계.
# =============================================================================
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 일간수익 + calendar month ---------------------------------------------
RAWDATA[, .ret := Close / shift(Close, 1L) - 1, by = Ticker]
RAWDATA[, .ym := format(Date, "%Y-%m")]

# ---- ticker-month별 MAX5 (상위 5 일간수익 평균) + 월말 일자 ----------------
mm <- RAWDATA[is.finite(.ret),
              .(MEnd = max(Date),
                NDays = .N,
                MAX5  = mean(head(sort(.ret, decreasing = TRUE), 5L))),
              by = .(Ticker, .ym)]
mm <- mm[NDays >= 10L & is.finite(MAX5)]          # 월내 최소 거래일

# ---- 월말 유동성 통과만 (LiqPass at MEnd) ----------------------------------
le <- RAWDATA[, .(Date, Ticker, LiqPass)]
FACTORS <- merge(mm, le, by.x = c("Ticker", "MEnd"), by.y = c("Ticker", "Date"))
FACTORS <- FACTORS[LiqPass == TRUE, .(Date = MEnd, Ticker, Score = -MAX5)]  # 저MAX = 매수

RAWDATA[, c(".ret", ".ym") := NULL]
cat(sprintf("[fe_max_lottery] FACTORS rows=%d | dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
