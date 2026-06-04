# =============================================================================
# factor_engine_template.R — 알파 서칭 모드 팩터 엔진 템플릿
# =============================================================================
# run_alpha_search()가 local source 하므로 RAWDATA / BM_DT 가 이 스코프에 보인다.
# 반드시 산출: FACTORS data.table with columns (Date, Ticker, Score)
#   - Date  : 시그널(리밸런싱) 날짜 — 월말 권장
#   - Ticker: 종목코드
#   - Score : 높을수록 매수 우선 (run_monthly_simulation이 상위 n_holdings 선택)
#
# ===== PIT 규칙 (lookahead_detector가 검사) =====
#   - 동일시점 순환참조 금지: 신호는 t-1 이전 정보만 사용 (shift / 과거 윈도우).
#   - 전체표본 통계 금지: expanding / rolling 만.
#   - 재무데이터: 연간→5월, 분기→45일 지연.
#   - 수동 방향반전(NEGATE/FLIP) 금지.
#
# 가설마다 아래 "팩터 정의" 블록만 교체하면 된다. 기본 예시 = 12-1 모멘텀.
# RAWDATA columns: Date, Ticker, Close, Vol, TradingValue, AvgTV20, LiqPass
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 팩터 정의 (가설별 교체 지점) -------------------------------------------
# 예시: 12-1개월 가격 모멘텀 (최근 1개월 제외한 과거 12개월 수익률).
#   shift(Close, 21)  = 약 1개월 전 종가 (skip recent month — 단기 반전 회피)
#   shift(Close, 252) = 약 12개월 전 종가
#   → 두 값 모두 과거 시점이므로 PIT-safe (동일시점 참조 없음).
RAWDATA[, .Score := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]
# ---------------------------------------------------------------------------

# ---- 월말 시그널 날짜 추출 (각 달의 마지막 거래일) --------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

# ---- FACTORS 산출 (유동성 통과 + 유효 스코어만) -----------------------------
FACTORS <- RAWDATA[
  Date %in% .month_ends & LiqPass == TRUE & is.finite(.Score),
  .(Date, Ticker, Score = .Score)
]

# 정리 (RAWDATA 임시컬럼 제거)
RAWDATA[, c(".Score", ".ym") := NULL]

cat(sprintf("[factor_engine_template] FACTORS rows=%d | signal dates=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date)))
