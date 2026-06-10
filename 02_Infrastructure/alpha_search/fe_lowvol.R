# =============================================================================
# fe_lowvol.R — Low-Volatility Anomaly 복제
# =============================================================================
# 논문: Baker, Bradley & Wurgler (2011) "Benchmarks as Limits to Arbitrage:
#       Understanding the Low-Volatility Anomaly", FAJ. (계보: Haugen & Baker 1991.)
#       → 과거 변동성 낮은 종목이 위험조정 초과수익. Low-vol decile long-only EW.
#
# ★ 논문 완전 복제 (alpha-search 제1원칙):
#   - 시그널: 과거 252일(약 1년) 일간수익 표준편차(total volatility).
#       낮을수록 매수 → Score = -vol (저변동성 = 높은 Score). 표준 BBW/Haugen-Baker 정의.
#   - 포트폴리오: low-vol **decile** (하위 10% 변동성), **equal-weight** (논문 그대로).
#       → FACTORS$N = ceil(n_eligible/10) per month → run_monthly_simulation이 월별
#         bottom-vol(=top-Score) decile 선택. weight_method는 run_alpha_search 인자.
#   - 리밸런싱: 월간 (월말 시그널).
#   - 유니버스: K200 ∪ KQ150 멤버십 (도훈 mandate: 외국논문 → KR 실투 유니버스 고정).
#       run_alpha_search는 universe="ALL"로 호출(decile 분모 정합 위해 멤버십을 fe 내부 적용).
#
# ===== PIT (lookahead_detector 검사) =====
#   - 일간수익 .ret = Close/shift(Close,1)-1. 변동성 계산은 shift(.ret,1L)로 t-1까지만
#     (당일 수익 미사용 — 동일시점 순환참조 없음). frollmean rolling window(252일)만 사용.
#   - 전체표본 통계 없음. NEGATE/FLIP 수동 반전 없음(Score=-vol은 신호의 경제적 방향이지
#     IC 기반 부호반전이 아님 — BBW 논문 정의 그대로).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 과거 252일 일간수익 표준편차 (total volatility, PIT t-1까지) ----
RAWDATA[, .ret := Close / shift(Close, 1L) - 1, by = Ticker]
RAWDATA[, .m1  := frollmean(shift(.ret, 1L),       252L), by = Ticker]   # t-1까지 평균
RAWDATA[, .m2  := frollmean(shift(.ret, 1L) ^ 2L,  252L), by = Ticker]   # t-1까지 제곱평균
RAWDATA[, .vol := sqrt(pmax(.m2 - .m1 ^ 2L, 0)), by = Ticker]            # 표준편차 = sqrt(E[r^2]-E[r]^2)
RAWDATA[, .Score := -.vol]                                              # 저변동성 = 높은 Score

# ---- 월말 시그널 날짜 (각 달 마지막 거래일) ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]

# ---- 유니버스: K200 ∪ KQ150 멤버십 + 유동성 2e8 (fe 내부 적용 → decile 분모 정합) ----
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  !is.na(.AvgTV20) & .AvgTV20 >= 2e8 & is.finite(.Score),
                .(Date, Ticker, Score = .Score)]

# ---- FACTORS 산출 ----
FACTORS <- copy(.mem)

# ---- decile sizing: 유니버스 내 저변동성 하위 10% (low-vol decile, equal-weight 복제) ----
FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]

# 정리
RAWDATA[, c(".ret", ".m1", ".m2", ".vol", ".Score", ".TV", ".AvgTV20") := NULL]

cat(sprintf("[fe_lowvol] BBW low-vol (252d total vol) | FACTORS rows=%d | signal months=%d | decile N range=%d~%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            min(FACTORS$N, na.rm = TRUE), max(FACTORS$N, na.rm = TRUE)))
