# =============================================================================
# factor_engine_RetAutoCorr_B.R — FQ-094: 저 월간수익 자기상관 long (Direction B)
# =============================================================================
# 가설: T_RetAutoCorr_12M 역방향 — 월간수익 lag-1 자기상관이 낮거나 음수인 종목
#   (= 추세 미약·평균회귀 구간) 매수
#   - Direction A(STR_AS_20260802_072220_10368): 고 autocorr long → PORT_t=-0.295(QUARANTINE)
#   - KR 추세추종이 평균회귀보다 약한 구조라면 역방향이 long-only 친화적
#   - FMB Score t=2.50*(원 논문 신호력) = 방향 판단만 재검 대상
#   - Score = -AutoCorr_12M (낮은 자기상관 = 높은 Score = long 선호)
#
# PIT 준수:
#   - 신호 계산: 직전 12개 월간수익(일간 Ret 월별 복리 집계, 월말 기준)
#   - Usable_Date = 익월 1일 (당월말 신호 → 익월 실행)
#   - 전기간 통계 금지: 12개월 rolling만 사용
#
# 입력: RAWDATA data.table (run_alpha_search.R 제공, 일간 Ret 포함)
# 출력: FACTORS data.table(Date, Ticker, Score)
# 논문: arXiv:2607.19497 (The Science and Practice of Trend-Following Systems)
# L-code 참조: L-AS-20260802-T_RetAutoCorr (방향 A, PORT_t=-0.295 QUARANTINE)
# =============================================================================

stopifnot(exists("RAWDATA"), data.table::is.data.table(RAWDATA))

setorder(RAWDATA, Ticker, Date)

# Step 1: 월간 수익률 집계 (일간 복리 → 월간)
# LiqPass 필터는 신호 계산 전 적용 (유동성 조건 충족 월만)
RAWDATA[, .ym := format(Date, "%Y-%m")]

monthly_rets <- RAWDATA[
  LiqPass == TRUE,
  .(MRet = prod(1 + Ret, na.rm = TRUE) - 1L,
    Date  = max(Date)),
  by = .(Ticker, .ym)
]
setorder(monthly_rets, Ticker, Date)

# Step 2: 12개월 rolling lag-1 자기상관
# 창 내 12개 월간 수익: x[1:11] vs x[2:12]
.lag1_autocorr <- function(x) {
  n <- length(x)
  if (n < 4L) return(NA_real_)
  x1 <- x[seq_len(n - 1L)]
  x2 <- x[seq_len(n - 1L) + 1L]
  # 분산이 0인 경우 NA 반환
  if (stats::var(x1, na.rm = TRUE) < 1e-12 ||
      stats::var(x2, na.rm = TRUE) < 1e-12) return(NA_real_)
  stats::cor(x1, x2, use = "pairwise.complete.obs")
}

monthly_rets[,
  AutoCorr_12M := frollapply(
    MRet, n = 12L, FUN = .lag1_autocorr,
    fill = NA, align = "right"
  ),
  by = Ticker
]

# Direction B: Score = -AutoCorr_12M
# (낮은/음수 자기상관 = 높은 Score = long 선호)
FACTORS <- monthly_rets[
  is.finite(AutoCorr_12M),
  .(Date, Ticker, Score = -AutoCorr_12M)
]

# 임시 컬럼 정리
RAWDATA[, .ym := NULL]

cat(sprintf(
  "[factor_engine_RetAutoCorr_B] FACTORS rows=%d | signal_dates=%d | tickers=%d\n",
  nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)
))
cat(sprintf(
  "[factor_engine_RetAutoCorr_B] AutoCorr range: [%.4f, %.4f] | median=%.4f\n",
  -max(FACTORS$Score, na.rm = TRUE),
  -min(FACTORS$Score, na.rm = TRUE),
  -median(FACTORS$Score, na.rm = TRUE)
))
cat(sprintf(
  "[factor_engine_RetAutoCorr_B] Score(= -AutoCorr) range: [%.4f, %.4f] | median=%.4f\n",
  min(FACTORS$Score, na.rm = TRUE),
  max(FACTORS$Score, na.rm = TRUE),
  median(FACTORS$Score, na.rm = TRUE)
))
