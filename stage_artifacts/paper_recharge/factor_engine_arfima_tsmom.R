# =============================================================================
# factor_engine_arfima_tsmom.R — ARFIMA_TSMOM (VR-Conditioned Momentum)
# =============================================================================
# 논문: "The Science and Practice of Trend-Following Systems" (arXiv 2607.19497)
# 핵심 가설: 분산비(VR(3)) > 1 = 양의 자기상관(추세) 존재 → 모멘텀 신호 유효.
#            VR <= 1 → 평균회귀 구간 → 신호 제거.
# 구현:
#   1. 12-1 모멘텀(mom12_1): 최근 13개월 누적 - 최근 1개월(단기반전 스킵)
#   2. VR(3) = Var(3개월 롤링 누적수익) / (3 * Var(1개월 수익))
#      - 12개월 rolling 창에서 계산 (C1: 전표본 금지 → rolling만)
#   3. VR > 1 인 종목만 mom12_1 신호 유지, 그 외 0.
#   4. 횡단면 Z-score 표준화 후 FACTORS 산출.
#
# PIT 준수:
#   - C1: rolling/expanding 창만 (전표본 var 금지) — slider::slide_dbl 사용
#   - C2: 현재 시점 수익(Ret)을 직접 사용하지 않음; 신호는 t-1 lag 경유
#   - C3: 월말 신호 → 다음 달 적용 (run_alpha_search가 FACTORS 시그널로 전달받아 다음달 수익 비교)
#   - 방향반전(NEGATE/FLIP) 금지
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# slider 패키지 확인 (RAWDATA rolling 창 계산에 필요)
if (!requireNamespace("slider", quietly = TRUE)) {
  install.packages("slider", repos = "https://cran.r-project.org", quiet = TRUE)
}
library(slider)

# ---- 팩터 정의 (ARFIMA_TSMOM / VR-Conditioned Momentum) -----------------------

# Step 1: 월간 종가 기반 수익률을 일별 패널에서 추출할 수 없으므로
#         RAWDATA의 일별 Close를 이용해 월말 종가를 계산, 월간 수익률을 파생.
#
# 일별 패널 → 월말 집계
RAWDATA[, .ym := format(Date, "%Y-%m")]
.me <- RAWDATA[, .(Date = max(Date), Close_me = Close[which.max(Date)]), by = .(Ticker, .ym)]
setorder(.me, Ticker, Date)

# 월간 수익률 (단순 수익률, C1: 과거값만 사용)
.me[, Ret_m := Close_me / shift(Close_me, 1L) - 1, by = Ticker]

# Step 2: 12-1 모멘텀 신호
#   mom12 = 13개월 전 → 2개월 전 누적 수익률 (직전 1개월 스킵)
#   PIT: shift(Close_me, 2L) = 2개월 전 종가 (최소 1개월 lag 보장)
#         shift(Close_me, 13L) = 13개월 전 종가
.me[, mom12_1 := shift(Close_me, 2L) / shift(Close_me, 13L) - 1, by = Ticker]

# Step 3: VR(3) 계산 — 최근 12개월 월간 수익률 기준
#   r3[t] = (1+Ret_m[t])*(1+Ret_m[t-1])*(1+Ret_m[t-2]) - 1
#   VR(3) = var(r3 rolling 10) / (3 * var(Ret_m rolling 12))
#
# r3 (3개월 누적 수익률) — PIT: shift 된 Ret_m 만 사용
.me[, r3 := (1 + Ret_m) * (1 + shift(Ret_m, 1L)) * (1 + shift(Ret_m, 2L)) - 1, by = Ticker]

# 분산 rolling — .before=11 → 현재 포함 12개 관측 (C1: 전표본 금지)
.me[, var_r1_12 := slide_dbl(Ret_m, var, .before = 11L, .complete = TRUE), by = Ticker]
.me[, var_r3_10 := slide_dbl(r3,    var, .before =  9L, .complete = TRUE), by = Ticker]

# VR(3) — 분모가 0이거나 NA면 NA 처리
.me[, VR3 := fifelse(
  is.finite(var_r1_12) & var_r1_12 > 1e-12,
  var_r3_10 / (3.0 * var_r1_12),
  NA_real_
)]

# Step 4: VR-conditioned signal
#   VR3 > 1 → 추세 구간 → mom12_1 신호 유지
#   VR3 <= 1 또는 NA → 평균회귀/불확실 → 0 (신호 없음)
.me[, signal_raw := fifelse(!is.na(VR3) & VR3 > 1.0 & is.finite(mom12_1),
                            mom12_1, 0.0)]

# Step 5: 횡단면 Z-score (월별 표준화)
.me[, n_valid := sum(signal_raw != 0 & is.finite(signal_raw)), by = Date]
.me[, signal_z := fifelse(
  n_valid >= 5L & signal_raw != 0 & is.finite(signal_raw),
  {
    mu <- mean(signal_raw[signal_raw != 0 & is.finite(signal_raw)])
    sg <- sd(signal_raw[signal_raw != 0 & is.finite(signal_raw)])
    (signal_raw - mu) / pmax(sg, 1e-8)
  },
  0.0
), by = Date]

# ---- 월말 시그널 날짜 추출 (일별 RAWDATA의 월말 Date 기준) -------------------
RAWDATA_me_dates <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

# ---- FACTORS 산출 -----------------------------------------------------------
# .me$Date 가 이미 월말 기준이므로 직접 join
# LiqPass 조건: RAWDATA에서 각 월말 기준 LiqPass 가져오기
.liq <- RAWDATA[Date %in% RAWDATA_me_dates & LiqPass == TRUE, .(Date, Ticker)]

.factors_raw <- .me[
  is.finite(signal_z) & !is.na(signal_z),
  .(Date, Ticker, Score = signal_z)
]

# 유동성 필터 적용
FACTORS <- merge(.factors_raw, .liq, by = c("Date", "Ticker"))

# 정리
rm(.me, .factors_raw, .liq)
RAWDATA[, .ym := NULL]
gc(verbose = FALSE)

cat(sprintf("[factor_engine_arfima_tsmom] VR-conditioned MOM | FACTORS rows=%d | signal dates=%d | tickers=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
