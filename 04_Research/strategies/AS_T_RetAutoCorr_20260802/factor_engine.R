# =============================================================================
# fe_T_RetAutoCorr_12M.R — Monthly Return Lag-1 Autocorrelation (12m window)
# =============================================================================
# 출처: "The Science and Practice of Trend-Following Systems" (arxiv:2607.19497)
#       Sepp & Lucic (2026) — 저주파 스펙트럼 질량이 높은 종목 = 양의 자기상관 우위
#
# 가설: 월간 수익률의 lag-1 자기상관이 높은 종목(= 추세 지속성)이
#        cross-section에서 초과수익 — 논문 핵심 TF 알파의 종목 수준 이식
#
# 신호: cor(ret[t-12:t-2], ret[t-11:t-1]) — 12m 롤링창 lag-1 자기상관
# PIT: 신호 시점(월말 t)에 사용 데이터 = t-12~t-1 월간수익 (PIT-safe)
#      "PIT lag=1 (use returns through t-1)" — 논문 정의 준수
#
# 구현 충실도 (batch_434 가드):
#   - 논문 정의 그대로: corr(ret[t-12:t-2], ret[t-11:t-1])
#   - L/S 논문이지만 long-only long-leg로 사상 (알파서칭 모드 규칙)
#   - 유니버스 = K200∪KQ150 (논문과 다름, 명시)
#   - 비중 = equal-weight top-20 (논문 명시 없음 → 시스템 표준 적용)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- Step 1: 월간 종가 → 월간수익률 ----------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]

.mdt <- RAWDATA[, .(
  Date       = max(Date),
  Close_mend = last(Close),
  LiqPass    = last(LiqPass)
), by = .(Ticker, .ym)]
setorder(.mdt, Ticker, Date)

# 월간 수익률 (전월말 대비)
.mdt[, ret_m := Close_mend / shift(Close_mend) - 1, by = Ticker]

# ---- Step 2: 12m 롤링 lag-1 자기상관 ----------------------------------------
# 신호 시점 t에서: cor(ret[t-12:t-2], ret[t-11:t-1])
#   x = ret[t-12], ..., ret[t-2]  (11 values, ending at t-2)
#   y = ret[t-11], ..., ret[t-1]  (11 values, ending at t-1)
# → 11쌍 lag-1 자기상관. 최소 7쌍 이상 유효값 필요.
# PIT 보장: i행(월 t)에서 i-12~i-1행(월 t-12~t-1) 데이터만 사용
.mdt[, .Score := {
  n  <- .N
  rr <- ret_m
  scores <- rep(NA_real_, n)
  if (n >= 13L) {
    for (i in 13L:n) {
      x <- rr[(i - 12L):(i - 2L)]   # t-12 to t-2 (11 values)
      y <- rr[(i - 11L):(i - 1L)]   # t-11 to t-1 (11 values)
      ok <- is.finite(x) & is.finite(y)
      if (sum(ok) >= 7L) {
        scores[i] <- cor(x[ok], y[ok])
      }
    }
  }
  scores
}, by = Ticker]

# ---- Step 3: 월말 시그널 추출 + 유동성 필터 ----------------------------------
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

FACTORS <- .mdt[
  Date %in% .month_ends & LiqPass == TRUE & is.finite(.Score),
  .(Date, Ticker, Score = .Score)
]

# 정리
RAWDATA[, .ym := NULL]

cat(sprintf(
  "[fe_RetAutoCorr_12M] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
  nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)
))
