# =============================================================================
# factor_engine.R — T11_CIRCUIT_HIT_UPPER_21D
# 논문: Das (2026) "Retained hidden excess generates memory in price-limited markets"
#        arXiv:2608.08625
#
# 기전: 가격제한 시장에서 상한가 마감 시 잠재 초과 수익(hidden excess)의
#       일부가 다음 날로 이월 → 상한가 이후 다음 날 동일 부호 수익 지속.
#       따라서 최근 N일 상한가 경험 빈도가 높을수록 다음 달 양수 수익 예측.
#
# 신호 1 (주력): circuit_hit_upper_21d
#   = count(Close_t >= prevClose_{t-1} * upper_limit * 0.999) / n_valid_days
#   - upper_limit: 1.15 if Date < 2015-06-15, else 1.30 (KR 제도 변경)
#   - prevClose = lag(Close, 1) by Ticker (PIT: t-1 정보만)
#   - 최소 15일 유효 데이터 요건
#
# 신호 2 (비교): net_circuit_ratio_21d
#   = (upper_hits - lower_hits) / n_valid_days
#   방향: higher_better (상한가 우세 → 양수 수익 예측)
#   * long-only 적용 시 음수 Score 포함되면 유동성 순으로 사실상 선택됨 주의
#
# PIT 보증:
#   - prevClose = shift(Close, 1L, type="lag") by Ticker: t-1 종가
#   - upper_limit 기준: Date 컬럼(당일)을 기준으로 제도 분기 → PIT 위반 없음
#     (2015-06-15 제도 변경은 사전에 공지된 과거 사실)
#   - rolling 21일 집계: 동일시점(t) 포함 없음 (hit 판단은 당일 Close와 t-1 prevClose 비교)
#     ★ PIT 주의: Close_t vs prevClose_{t-1} 비교는 당일 정보를 사용하나
#       이는 당일 종가가 이미 형성된 후의 사실이며, 시그널 날짜는 month_end
#       (그 달의 마지막 거래일)이므로 month_end 이전 거래일의 Close 값은 PIT-safe.
#       month_end 당일 Close는 시그널에 포함되지 않도록 rolling window를 [2, 22] lag로 조정.
#       즉 신호는 sig_date 기준 직전 21 거래일 (sig_date 미포함) 집계.
#
# 유니버스: KOSPI200 ∪ KOSDAQ150 (LiqPass 필터 적용)
# 리밸: 월간 (월말 신호 → 다음 달 수익)
# 비용: 15bps (run_alpha_search 기본값)
# 기간: 2005-01-01 ~ 현재 (표준)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- PIT-safe 이전일 종가 -------------------------------------------------------
# shift(Close, 1L) = t-1 종가 (by Ticker). 월초 첫 거래일의 prevClose는 이전 달 말 종가.
RAWDATA[, prevClose := shift(Close, 1L, type = "lag"), by = Ticker]

# ---- KR 가격제한 제도 분기 -------------------------------------------------------
# 2015-06-15 이전: 일일 ±15% (upper_limit = 1.15)
# 2015-06-15 이후: 일일 ±30% (upper_limit = 1.30)
# 제도 변경일은 역사적 공지 사항 → PIT 위반 없음
CHANGE_DATE <- as.Date("2015-06-15")
RAWDATA[, upper_limit := ifelse(Date < CHANGE_DATE, 1.15, 1.30)]
RAWDATA[, lower_limit := ifelse(Date < CHANGE_DATE, 0.85, 0.70)]

# ---- 상한가 근접 여부 (당일) -----------------------------------------------------
# 상한가 근접 기준: Close >= prevClose * upper_limit * 0.999 (논문: limit close = 상한가 마감)
# 하한가 근접 기준: Close <= prevClose * lower_limit * 1.001
RAWDATA[, upper_hit := (!is.na(prevClose)) & (!is.na(Close)) &
          (Close >= prevClose * upper_limit * 0.999)]
RAWDATA[, lower_hit := (!is.na(prevClose)) & (!is.na(Close)) &
          (Close <= prevClose * lower_limit * 1.001)]
RAWDATA[, valid_day  := (!is.na(prevClose)) & (!is.na(Close))]

# ---- 월말 시그널 날짜 추출 --------------------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

# ---- 21 거래일 rolling 집계 (PIT: sig_date 미포함 → shift 2부터 22) ---------------
# 월말 sig_date를 t=0으로 볼 때, 신호는 [t-22, t-2] 구간 (=직전 21 거래일, sig_date 자체 제외)
# 구현: 각 sig_date에서 해당 Ticker의 과거 22번째 ~ 2번째 행을 집계
# 단순화: 당월 말일 이전 21거래일을 rolling으로 구하고, 마지막(sig_date) 행은 제외
# → shift 방식: 월말 시그널 행에서 lag 2~22 범위의 upper_hit 합산

# 구현 방식: 일별 rolling sum (lag 포함) 후 월말 추출
# roll_sum_upper = sum of upper_hit in past 21 days ENDING AT t-1 (not including t)
# = sum(shift(upper_hit, k)) for k=1..21 (lag)
# 단, 합산 루프 대신 frollapply 사용:

.MIN_DAYS <- 15L
.WIN      <- 21L

# shift upper_hit by 1 (exclude same day sig), then rolling sum of 21 days
RAWDATA[, .uh_lag1 := shift(upper_hit, 1L, type = "lag"), by = Ticker]
RAWDATA[, .lh_lag1 := shift(lower_hit, 1L, type = "lag"), by = Ticker]
RAWDATA[, .vd_lag1 := shift(valid_day, 1L, type = "lag"), by = Ticker]

RAWDATA[, .n_upper := frollsum(.uh_lag1, n = .WIN, align = "right", na.rm = TRUE, fill = NA_real_), by = Ticker]
RAWDATA[, .n_lower := frollsum(.lh_lag1, n = .WIN, align = "right", na.rm = TRUE, fill = NA_real_), by = Ticker]
RAWDATA[, .n_valid := frollsum(as.numeric(.vd_lag1), n = .WIN, align = "right", na.rm = TRUE, fill = NA_real_), by = Ticker]

# 신호 1: circuit_hit_upper_21d (주력 신호)
RAWDATA[, .score_upper := ifelse(
  !is.na(.n_valid) & .n_valid >= .MIN_DAYS,
  .n_upper / .n_valid,
  NA_real_
)]

# 신호 2: net_circuit_ratio_21d (비교용 — 별도 이름 .score_net)
RAWDATA[, .score_net := ifelse(
  !is.na(.n_valid) & .n_valid >= .MIN_DAYS,
  (.n_upper - .n_lower) / .n_valid,
  NA_real_
)]

# ---- 월말 FACTORS 추출 (신호 1 사용) -------------------------------------------
FACTORS <- RAWDATA[
  Date %in% .month_ends & LiqPass == TRUE & is.finite(.score_upper),
  .(Date, Ticker, Score = .score_upper)
]

# ---- 희소성 진단 리포트 ----------------------------------------------------------
.n_nonzero <- sum(FACTORS$Score > 0, na.rm = TRUE)
.n_total   <- nrow(FACTORS)
.n_months  <- uniqueN(FACTORS$Date)
.pct_nonzero <- if (.n_total > 0) round(100 * .n_nonzero / .n_total, 1) else 0
cat(sprintf("[CIRCUIT_UPPER] FACTORS rows=%d | months=%d | Score>0: %d (%.1f%%)\n",
            .n_total, .n_months, .n_nonzero, .pct_nonzero))

# 희소성 경고: Score > 0이 5% 미만이면 신호 사실상 무효 → 유동성 정렬과 동일
if (.pct_nonzero < 5) {
  warning(sprintf(
    "[CIRCUIT_UPPER] SPARSITY WARNING: Score>0 = %.1f%% < 5%%. ",
    "신호가 희소하여 top-25 선택이 유동성 정렬과 사실상 동일할 수 있음. ",
    "판정: '신호 희소 → IC 구조적 0' 가능성 높음.", .pct_nonzero
  ))
}

# ---- 정리 (임시컬럼 제거) --------------------------------------------------------
RAWDATA[, c("prevClose","upper_limit","lower_limit","upper_hit","lower_hit","valid_day",
            ".ym",".uh_lag1",".lh_lag1",".vd_lag1",
            ".n_upper",".n_lower",".n_valid",
            ".score_upper",".score_net") := NULL]

cat(sprintf("[factor_engine_circuit_upper] FACTORS final rows=%d | signal dates=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date)))
