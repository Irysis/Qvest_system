# =============================================================================
# factor_engine.R — T_RetAutoCorr_12M
# 논문: "The Science and Practice of Trend-Following Systems" (Sepp & Lucic 2026)
#        arXiv:2607.19497
# 핵심 이론: E[TF return] ∝ 자기상관 ρ + drift^2
#   → 월간 lag-1 수익률 자기상관이 높은 종목 = 추세추종 수익 우위
#   → long-only 횡단면 신호: 양의 autocorr 상위 종목 선택
#
# 팩터 정의:
#   - 각 종목·월말 t에서 과거 12개월 월별 수익률 벡터를 구성
#   - lag-1 자기상관 = cor(ret[t-12:t-2], ret[t-11:t-1])  — 11쌍
#   - PIT lag=1: t-1월 말까지의 수익률만 사용 (동월 수익률 참조 금지)
#   - Signal 방향: 양수 = 추세 지속 = 매수 우선
#
# PIT 준수:
#   C1: 전체 표본 통계 금지 — by=Ticker rolling window만 사용
#   C2: 동일시점 순환참조 금지 — shift(1) 로 월별 수익률 먼저 lag
#   데이터 접근 기준: 월별 수익률은 해당 월 종가 기준이며,
#     신호일(month-end Date) = 직전 11개 월별 수익률 쌍으로만 계산
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- Step 1: 월별 수익률 집계 ------------------------------------------------
# 각 종목의 월말 종가를 추출해 월별 수익률 계산
# month-end close = 각 달 마지막 거래일의 Close
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends_raw <- RAWDATA[, .(
  Date_me = max(Date),
  Close_me = Close[which.max(Date)]
), by = .(Ticker, .ym)]
setorder(.month_ends_raw, Ticker, Date_me)

# 월별 수익률: ret_m[t] = Close_me[t] / Close_me[t-1] - 1
# PIT-safe: 이 시점의 수익률은 당월 마지막 거래일에 이미 실현된 값
.month_ends_raw[, ret_m := Close_me / shift(Close_me, 1L) - 1, by = Ticker]

# ---- Step 2: lag-1 자기상관 계산 (12개월 윈도우) ----------------------------
# 신호일(Date_me = t) 기준, 과거 12개월 수익률로 lag-1 autocorr 계산
# 사용 데이터: ret_m[t-12], ret_m[t-11], ..., ret_m[t-1]
# → x = ret_m[t-12 : t-2]  (11개)
# → y = ret_m[t-11 : t-1]  (11개)  — 각각 1개월 shift
# cor(x, y) = lag-1 자기상관 (Pearson)
#
# 구현: 각 (Ticker, 신호월)에서 12개월 롤링 윈도우 안에서
#   shift(ret_m, 2L) ~ shift(ret_m, 12L) 를 x
#   shift(ret_m, 1L) ~ shift(ret_m, 11L) 를 y 로 cor() 계산
# → 11쌍 모두 과거 시점이므로 PIT-safe
#
# 최소 유효 쌍 기준: 7쌍 이상 (ret_m NA 허용)
.calc_autocorr_12m <- function(ret_m_vec) {
  n <- length(ret_m_vec)
  if (n < 13L) return(rep(NA_real_, n))
  result <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    # i번째 행 = 신호 시점 t
    # 필요한 인덱스: t-12 ~ t-1 (i-12 ~ i-1)
    idx_start <- i - 12L
    idx_end   <- i - 1L
    if (idx_start < 1L) next
    window_ret <- ret_m_vec[idx_start:idx_end]  # 12개월치 수익률
    # NA가 너무 많으면 skip
    valid_idx <- which(is.finite(window_ret))
    if (length(valid_idx) < 7L) next
    # x = window[1:11], y = window[2:12] — lag-1 쌍
    x_vec <- window_ret[1:11]
    y_vec <- window_ret[2:12]
    # 두 벡터 모두 유효한 인덱스만
    valid_pairs <- which(is.finite(x_vec) & is.finite(y_vec))
    if (length(valid_pairs) < 5L) next
    result[i] <- tryCatch(
      cor(x_vec[valid_pairs], y_vec[valid_pairs], method = "pearson"),
      error = function(e) NA_real_
    )
  }
  result
}

# data.table by-group 적용
.month_ends_raw[, .autocorr := .calc_autocorr_12m(ret_m), by = Ticker]

# ---- Step 3: FACTORS 산출 ---------------------------------------------------
# 유동성 통과 + 유효 스코어만 추출
# 신호일 = .month_ends_raw의 Date_me (각 달 마지막 거래일)
# RAWDATA의 LiqPass와 join
.liq_map <- RAWDATA[, .(LiqPass = any(LiqPass == TRUE)), by = .(Ticker, .ym)]
.month_ends_raw[, .ym := format(Date_me, "%Y-%m")]
.month_ends_raw <- .liq_map[.month_ends_raw, on = .(Ticker, .ym)]

FACTORS <- .month_ends_raw[
  !is.na(.autocorr) & is.finite(.autocorr) & LiqPass == TRUE,
  .(Date = Date_me, Ticker, Score = .autocorr)
]

# 정리
RAWDATA[, c(".ym") := NULL]
rm(.month_ends_raw, .liq_map)

cat(sprintf("[T_RetAutoCorr_12M] FACTORS rows=%d | signal dates=%d | unique tickers=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
cat(sprintf("[T_RetAutoCorr_12M] Score range: [%.3f, %.3f] | NA 제거 후\n",
            min(FACTORS$Score, na.rm=TRUE), max(FACTORS$Score, na.rm=TRUE)))
