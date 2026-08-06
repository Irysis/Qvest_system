# =============================================================================
# factor_engine_cv_vol_exclusion_20pct.R
# FQ-150: CV_Vol 유니버스 exclusion filter — 고 CV_Vol 상위 20% 제거
#
# 목적: alpha signal 테스트가 아님. 유니버스에서 CV_Vol 극단값(상위 20%) 종목을
#   제거한 후, 나머지 유니버스에서 uniform EW top-25 선택 시 성과 변화 측정.
#   이 결과를 base(필터 없음) 대비 ΔIR로 판단.
#
# PIT C10 준수: 거래량(Vol)은 t-1 기준 21일 rolling (당일 거래량 사용 금지).
#   월말 시점 CV_Vol = 의사결정 시점에 알 수 있는 정보이므로 C10 위반 아님.
#
# Score: uniform (모든 생존 종목 Score=1). 필터 효과만 측정.
# cut: 상위 20% (CV_Vol ≥ p80) 제거 → 하위 80% 유니버스만 허용.
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- CV_Vol 계산 (PIT-safe: 월말 시점에 직전 21거래일 Vol만 사용) -----------
RAWDATA[, .vol := as.numeric(Vol)]
RAWDATA[, .vol_sq := .vol^2]

RAWDATA[, .roll_mean   := frollmean(.vol,    n = 21L, align = "right", fill = NA), by = Ticker]
RAWDATA[, .roll_meansq := frollmean(.vol_sq, n = 21L, align = "right", fill = NA), by = Ticker]

RAWDATA[, .roll_var := pmax(.roll_meansq - .roll_mean^2, 0)]
RAWDATA[, .CV_Vol   := sqrt(.roll_var) / pmax(.roll_mean, 1)]  # pmax 방어: 거래량=0 종목 Inf 방지

# ---- 월말 시그널 날짜 추출 ---------------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

# ---- 월말 단면 추출 (유동성 통과 + 유효 CV_Vol) --------------------------------
.panel <- RAWDATA[Date %in% .month_ends & LiqPass == TRUE & is.finite(.CV_Vol),
                  .(Date, Ticker, CV_Vol = .CV_Vol)]

# ---- 상위 20% CV_Vol 제거 (횡단면 기준, PIT) ----------------------------------
#   매월 CV_Vol의 80th percentile을 구한 뒤, p80 이상 종목 제거
.panel[, .p80 := quantile(CV_Vol, probs = 0.80, na.rm = TRUE), by = Date]
.panel_kept <- .panel[CV_Vol < .p80]  # 상위 20% 제거: CV_Vol < p80만 허용

# ---- n_holdable ≥ 25 보장 확인 (각 월별) ------------------------------------
.n_check <- .panel_kept[, .N, by = Date]
.insufficient <- .n_check[N < 25]
if (nrow(.insufficient) > 0L) {
  cat(sprintf("[cv_vol_excl_20pct] 주의: %d개월에서 필터 후 n < 25 (min=%d). 해당 월은 FACTORS에서 제외.\n",
              nrow(.insufficient), min(.insufficient$N)))
  .valid_dates <- .n_check[N >= 25, Date]
  .panel_kept <- .panel_kept[Date %in% .valid_dates]
} else {
  cat(sprintf("[cv_vol_excl_20pct] 모든 월 n >= 25 확인 (min=%d, 20pct cut)\n", min(.n_check$N)))
}

# ---- Score = uniform (EW 기준, 필터 효과만 측정) ----------------------------
.panel_kept[, Score := 1.0]

# ---- FACTORS 산출 ------------------------------------------------------------
FACTORS <- .panel_kept[, .(Date, Ticker, Score)]

# 정리
RAWDATA[, c(".vol", ".vol_sq", ".roll_mean", ".roll_meansq",
            ".roll_var", ".CV_Vol", ".ym") := NULL]
rm(.panel, .panel_kept, .n_check)
if (exists(".insufficient")) rm(.insufficient)
if (exists(".valid_dates")) rm(.valid_dates)

cat(sprintf("[cv_vol_excl_20pct] FACTORS rows=%d | signal dates=%d | avg/month=%.0f\n",
    nrow(FACTORS), uniqueN(FACTORS$Date), nrow(FACTORS) / max(1, uniqueN(FACTORS$Date))))
