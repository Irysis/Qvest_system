# =============================================================================
# factor_engine_JumpShare_B.R — FQ-110B: 저 jump-share long (Direction B)
# =============================================================================
# 가설: JumpShare_12M 역방향 — 수익이 분산된(소폭 꾸준한) 종목이 지속 상승 후보.
#   - frog-in-the-pan 재해석: 시장이 서서히 알아차리는(low jump-share) 추세 포착
#   - Direction A(FQ-110) IC=-0.028 음수 실측 → Direction B 근거 확보
#   - Score = -JumpShare_12M (높을수록 분산 수익 = 지속 모멘텀 후보)
#
# PIT 준수: Direction A와 동일 (변경 없음)
#   - 신호 계산: 월말 t-1 기준 look-back 252 거래일 window
#   - Usable_Date = 익월 1일 (당월 말 신호 → 익월 적용)
#   - 전기간 통계 금지: 종목별 rolling 절대값 합산만 사용
#
# 입력: RAWDATA data.table (run_alpha_search.R 제공)
# 출력: FACTORS data.table(Date, Ticker, Score)
# L-code 참조: L-AS-20260808-FQ110 (Direction A IC=-0.028 → Direction B 도출)
# =============================================================================

stopifnot(exists("RAWDATA"), data.table::is.data.table(RAWDATA))

setorder(RAWDATA, Ticker, Date)

LOOKBACK <- 252L

.calc_jump_share <- function(ret_vec) {
  abs_ret <- abs(ret_vec)
  denom <- sum(abs_ret, na.rm = TRUE)
  if (is.na(denom) || denom < 1e-6) return(NA_real_)
  top5_sum <- sum(sort(abs_ret, decreasing = TRUE)[1:min(5L, length(abs_ret))],
                  na.rm = TRUE)
  top5_sum / denom
}

RAWDATA[, .JumpShare := frollapply(
  Ret, n = LOOKBACK, FUN = .calc_jump_share,
  fill = NA, align = "right"
), by = Ticker]

RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

# Direction B: Score = -JumpShare (낮은 jump-share = 높은 Score = long 선호)
FACTORS <- RAWDATA[
  Date %in% .month_ends & LiqPass == TRUE & is.finite(.JumpShare),
  .(Date, Ticker, Score = -.JumpShare)
]

RAWDATA[, c(".JumpShare", ".ym") := NULL]

cat(sprintf(
  "[factor_engine_JumpShare_B] FACTORS rows=%d | signal_dates=%d | tickers=%d\n",
  nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)
))
cat(sprintf(
  "[factor_engine_JumpShare_B] Score range: [%.4f, %.4f] | median=%.4f\n",
  min(FACTORS$Score, na.rm = TRUE),
  max(FACTORS$Score, na.rm = TRUE),
  median(FACTORS$Score, na.rm = TRUE)
))
