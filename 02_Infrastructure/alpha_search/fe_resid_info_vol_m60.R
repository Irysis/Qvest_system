# =============================================================================
# fe_resid_info_vol_m60.R — Persistent Residual Information Volume (60d mean)
#
# 계보: 07-27 RESID_INFO_VOL (STR_AS_20260727_204043_17032, Grade F,
#       PORT_t -0.487, IC 0.0024, Turnover 1026%/yr) 의 next_probe P1 소비.
#
# 원논문: arXiv:2606.08141 Bucci-Palomba-Rossi (2026) SMAR — 변동성이 거래량의
#       1차 구동원. 변동성 설명분을 제거한 잔차 거래량 = 정보거래 활동 프록시.
#
# 07-27 base와의 차별점 (chain iteration, IS-only 선택):
#   base : 20일 OLS 윈도우의 **마지막 하루** 잔차 = 1일 거래량 서프라이즈
#   본건 : 일별 잔차의 **직전 60거래일 평균** = 지속적 비정상 거래량 *수준*
#   기전 가설: base의 진단(mechanism_diagnosis.turnover_trap)은 "일별 OLS 잔차
#   노이즈 → 연 1026% 회전 → 15bps×1026% ≈ 307bps/yr 비용 잠식". 평활이
#   회전율을 낮추면 (a) 비용이 병목이었는지 (b) 신호 자체가 0(IC 0.0024)이었는지
#   를 분리 식별한다. 두 경우 모두 정보성 판정.
#
# 팩터 정의 (PIT-safe, 전부 후향 윈도우):
#   y_t = log(Vol_t + 1)
#   x_t = log(|Ret_t| + 1e-4)
#   직전 20거래일 rolling OLS  y ~ a + b x  (해석적 rolling moment 방식)
#   e_t = y_t - a_t - b_t x_t                      (당일 잔차)
#   Score = mean(e_{t-59..t})                      (60거래일 평균 = 지속 수준)
#   신호일 = 월말 거래일, 수익 실현 = 익월 (run_monthly_simulation)
#
# rolling OLS 구현 주: 07-27 base는 lm.fit 루프(윈도우당 유효 10개 이상 요구).
#   본건은 frollmean 기반 해석해로 동일 추정량을 벡터화(수치적으로 동일한 OLS).
#   차이는 결측 처리 방식(윈도우 내 NA 시 NA 전파)뿐이며 PIT 성질 동일.
#
# PIT 체크:
#   C1 rolling only (전표본 통계 없음) / C2 동일시점 순환 없음 (거래량~|수익|의
#   동시점 *기술적 분해*이며 수익 예측 회귀가 아님 — base와 동일 논거)
#   C10 유동성은 상류 AvgTV20(t-1) LiqPass 사용
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

.W_OLS  <- 20L   # rolling OLS 윈도우 (base와 동일)
.W_MEAN <- 60L   # 잔차 평활 윈도우 (본건 차별점)

# ---- 1. 일별 y, x ------------------------------------------------------------
if ("Ret" %in% names(RAWDATA)) {
  RAWDATA[, .dret := Ret]
} else {
  RAWDATA[, .dret := Close / shift(Close, 1L) - 1, by = Ticker]
}
RAWDATA[, .y := ifelse(!is.na(Vol) & Vol > 0, log(Vol + 1), NA_real_)]
RAWDATA[, .x := ifelse(is.finite(.dret), log(abs(.dret) + 1e-4), NA_real_)]
RAWDATA[!is.finite(.y) | !is.finite(.x), c(".y", ".x") := NA_real_]

# ---- 2. rolling OLS moments (해석해, 전부 trailing) --------------------------
RAWDATA[, .xy := .x * .y]
RAWDATA[, .xx := .x * .x]

RAWDATA[, `:=`(
  .mx  = frollmean(.x,  .W_OLS, align = "right", na.rm = TRUE, hasNA = TRUE),
  .my  = frollmean(.y,  .W_OLS, align = "right", na.rm = TRUE, hasNA = TRUE),
  .mxy = frollmean(.xy, .W_OLS, align = "right", na.rm = TRUE, hasNA = TRUE),
  .mxx = frollmean(.xx, .W_OLS, align = "right", na.rm = TRUE, hasNA = TRUE)
), by = Ticker]

RAWDATA[, .varx := .mxx - .mx * .mx]
RAWDATA[, .beta := ifelse(is.finite(.varx) & .varx > 1e-10,
                          (.mxy - .mx * .my) / .varx, NA_real_)]
RAWDATA[, .resid := .y - (.my - .beta * .mx) - .beta * .x]
RAWDATA[!is.finite(.resid), .resid := NA_real_]

# ---- 3. 잔차 60거래일 평균 (지속 수준) --------------------------------------
RAWDATA[, .score := frollmean(.resid, .W_MEAN, align = "right",
                              na.rm = TRUE, hasNA = TRUE), by = Ticker]

# ---- 4. 월말 시그널 ----------------------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

FACTORS <- RAWDATA[
  Date %in% .month_ends & LiqPass == TRUE & is.finite(.score),
  .(Date, Ticker, Score = .score)
]

# ---- 5. cleanup --------------------------------------------------------------
RAWDATA[, c(".dret", ".y", ".x", ".xy", ".xx", ".mx", ".my", ".mxy", ".mxx",
            ".varx", ".beta", ".resid", ".score", ".ym") := NULL]

cat(sprintf(
  "[fe_resid_info_vol_m60] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
  nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
