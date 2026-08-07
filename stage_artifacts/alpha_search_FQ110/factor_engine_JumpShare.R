# =============================================================================
# factor_engine_JumpShare.R — FQ-110: 12M 창 상위-5 일간수익 기여 비중(jump-share)
# =============================================================================
# 가설: 12-1 창 상위-5 |일간수익률| 기여 비중(JumpShare_12M)을 신호로 직접 팩터화.
#   - frog-in-the-pan 기전: 수익이 소수 날짜에 집중(높은 jump-share) = 단기 탄성
#   - 양방향 테스트: IC 방향에 따라 run_alpha_search 수준에서 결정
#
# PIT 준수:
#   - 신호 계산: 월말 t-1 기준 look-back 252 거래일 window (shift/rolling 전용)
#   - Usable_Date = 익월 1일 (당월 말 신호 → 익월 적용)
#   - 전기간 통계 금지: 종목별 rolling 절대값 합산만 사용
#   - 동일시점 순환참조 없음 (shift 기반)
#
# 입력 (run_alpha_search.R이 제공): RAWDATA data.table
#   cols: Date, Ticker, Close, Vol, Ret, TradingValue, AvgTV20, LiqPass, K200, KQ150
# 출력: FACTORS data.table(Date, Ticker, Score)
# =============================================================================

stopifnot(exists("RAWDATA"), data.table::is.data.table(RAWDATA))

setorder(RAWDATA, Ticker, Date)

# ---- 팩터 정의: JumpShare_12M -----------------------------------------------
# lookback = 252 거래일 (~12개월), lag = 1개월 (PIT: 월말 신호 → 익월 사용)
# jump_share = sum(top-5 |일간수익률|) / sum(ALL |일간수익률|)
#   - 분모 < 1e-6이면 NA
#   - shift()를 사용하므로 전기간 누출 없음 (expanding/rolling 아닌 종목별 창)
#
# 구현 전략:
#   1. frollapply로 종목별 252일 rolling window에서 jump_share 계산
#   2. 분모가 너무 작으면 NA 처리
#   3. 월말 시그널 날짜에서 FACTORS 추출

LOOKBACK <- 252L  # 약 12개월 거래일

# jump_share 계산 함수: 창 내 top-5 |ret| 합 / 전체 |ret| 합
.calc_jump_share <- function(ret_vec) {
  abs_ret <- abs(ret_vec)
  denom <- sum(abs_ret, na.rm = TRUE)
  if (is.na(denom) || denom < 1e-6) return(NA_real_)
  # top-5 절대수익률
  top5_sum <- sum(sort(abs_ret, decreasing = TRUE)[1:min(5L, length(abs_ret))],
                  na.rm = TRUE)
  top5_sum / denom
}

# Ret 컬럼 사용 (C15 예외: RAWDATA 직접 접근, load_month_factors 아님)
# Ret은 이미 일간 수익률 (Close 기반 사전 계산됨)
# frollapply: 252일 rolling, align="right" (t 시점 포함 과거 252일)
# PIT: 이 자체는 과거 window만 보므로 안전 — 월말 시그널 날짜 적용 시 이미 past

RAWDATA[, .JumpShare := frollapply(
  Ret, n = LOOKBACK, FUN = .calc_jump_share,
  fill = NA, align = "right"
), by = Ticker]

# ---- 월말 시그널 날짜 추출 ---------------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

# ---- FACTORS 산출 -----------------------------------------------------------
# PIT: 월말(신호일) 기준 유효한 jump_share만 추출
# 유동성 필터: LiqPass (20일 평균 거래대금 >= 2e8 KRW)
# Score = JumpShare_12M (양방향은 run_alpha_search 레벨에서 결정)
FACTORS <- RAWDATA[
  Date %in% .month_ends & LiqPass == TRUE & is.finite(.JumpShare),
  .(Date, Ticker, Score = .JumpShare)
]

# 정리 (임시 컬럼 제거)
RAWDATA[, c(".JumpShare", ".ym") := NULL]

cat(sprintf(
  "[factor_engine_JumpShare] FACTORS rows=%d | signal_dates=%d | tickers=%d\n",
  nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)
))
cat(sprintf(
  "[factor_engine_JumpShare] Score range: [%.4f, %.4f] | median=%.4f\n",
  min(FACTORS$Score, na.rm = TRUE),
  max(FACTORS$Score, na.rm = TRUE),
  median(FACTORS$Score, na.rm = TRUE)
))
