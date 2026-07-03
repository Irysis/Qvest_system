# =============================================================================
# factor_engine_pindex_2606_08569.R
# "Stock Investment: The p-index Approach" (Xie, Nie, Chang 2026; arXiv 2606.08569)
# 횡단면 p-index 팩터 — KR(KOSPI200∪KOSDAQ150) faithful 복제
# =============================================================================
# 논문 방법(eq. 6-9, Section 3.1)을 그대로 구현한다. Black-Scholes 합성이 아니라
# 논문이 실제로 쓴 BINOMIAL(이항) p-index closed-form(eq. 7)을 사용한다 —
# 논문은 옵션 시장가 불요로 주간 고/저 종가에서 u/d를 추정한다.
# 본 KR 검증은 주간→월간 리밸로 스케일(IMPL_SPEC T≈1개월 허용)하되 수식은 동일.
#
# 각 신호월 t (월말 = 리밸/시그널 날짜)에서, 그 달 전체 일별 OHLC만 사용(전부 과거):
#   시장(BM) 기준 risk-neutral π:
#     S0_M = 그 달 첫 거래일 BM 종가, u_M = max(그 달 BM 종가)/S0_M, d_M = min/S0_M
#     π = ((1+r) - d_M) / (u_M - d_M)              (eq. 6)   ← 시장 단일 π
#   종목 i:
#     S0u_i = max(그 달 i 종가), S0d_i = min(그 달 i 종가)
#     fair price S0_i = (1/(1+r))[π·S0u_i + (1-π)·S0d_i]     (eq. 8)
#     d_i = S0d_i / S0_i  (fair price 대비 하방이동 비율)
#     δ = r,  K_i = (1+δ)·S0_i
#   p-index (eq. 7 closed-form):
#     p_index_i = [(1+δ) - d_i] / (1+δ) · (1-π)/(1+r)
#   higher p-index = higher risk = LESS likely to deliver ≥δ return.
#   (Table 2: high-yield firms = LOWER p-index, low-yield = HIGHER p-index.)
#
# 신호(Score) = p-index 횡단면 정렬. 방향은 run 시 두 엔진(A/B)로 분리 테스트:
#   DIRECTION="LOW"  → Score = -p_index  (저보험료=저리스크 롱; Table 2 정합 가설)
#   DIRECTION="HIGH" → Score = +p_index  (고보험료=고리스크 롱; 반대 방향)
# 환경변수 PINDEX_DIRECTION 로 선택(기본 LOW).
#
# ── PIT (lookahead_detector + C1~C15) ──
#  - 신호월 t 의 OHLC는 t 시그널 날짜(월말) 시점 전부 관측가능 → same-day 순환 없음.
#  - 포지션은 run_monthly_simulation 이 다음 달 보유(t+1) → t-1 PIT 충족.
#  - 전체표본 통계 없음(월별 by-group 집계만). scale()/quantile($)/fwd_ret 없음.
#  - 수동 부호반전(NEGATE/FLIP) 아님 — p-index의 경제적 정의에 따른 방향 가설(C13 비위반).
#
# RAWDATA columns: Date, Ticker, Close, High, Low, Open, Vol, Size, Ret, K200, KQ150, ...
# BM_DT columns:   Date, BM_Close, BM_Ret
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(exists("BM_DT"),   is.data.table(BM_DT))
setorder(RAWDATA, Ticker, Date)

# ---- 방향 선택 (A: LOW p-index 롱 / B: HIGH p-index 롱) ----
.DIR <- toupper(Sys.getenv("PINDEX_DIRECTION", "LOW"))
if (!.DIR %in% c("LOW", "HIGH")) .DIR <- "LOW"

# ---- 파라미터 (논문 명시값) ----
# r = 무위험금리(월간). 논문은 10yr 中 국채/52(주간). KR rf 컬럼 부재 → 월 단순금리 상수.
#   δ=r. r은 π 레벨·p-index 스케일에만 영향(횡단면 랭킹 신호엔 미세). 보충값 명시.
#   KR 기준 연 2.5% 가정 → 월 r ≈ 0.025/12.
.r_month <- 0.025 / 12
.delta   <- .r_month   # 논문: δ = r

# ---- 월(period) 라벨 ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
BM_DT[,   .ym := format(Date, "%Y-%m")]

# ---- 시장 단일 π: 그 달 BM 종가 high/low/first ----
setorder(BM_DT, Date)
.bm_m <- BM_DT[is.finite(BM_Close) & BM_Close > 0,
               .(S0_M = BM_Close[1L],
                 uHi  = max(BM_Close),
                 dLo  = min(BM_Close)), by = .ym]
.bm_m[, u_M := uHi / S0_M]
.bm_m[, d_M := dLo / S0_M]
# eq. (6): π = ((1+r) - d)/(u - d). u==d(무변동)면 π 미정의 → 0.5 폴백(중립).
.bm_m[, pi_mkt := fifelse(u_M > d_M, ((1 + .r_month) - d_M) / (u_M - d_M), 0.5)]
# 논문 주: 1>π>0 미충족 시 직전 주 포함 재계산. 월간에선 [0,1] clamp 으로 단순화(명시).
.bm_m[, pi_mkt := pmin(pmax(pi_mkt, 0), 1)]

# ---- 종목 월별 high/low Close ----
.stk_m <- RAWDATA[is.finite(Close) & Close > 0,
                  .(S0u = max(Close), S0d = min(Close), n_obs = .N),
                  by = .(Ticker, .ym)]
.stk_m <- .stk_m[n_obs >= 10L]   # 한 달 최소 10거래일(고/저 추정 신뢰)

# ---- π join ----
.stk_m <- merge(.stk_m, .bm_m[, .(.ym, pi_mkt)], by = ".ym", all.x = FALSE)

# ---- fair price S0_i = (1/(1+r))[π·S0u + (1-π)·S0d]  (eq. 8) ----
.stk_m[, S0_fair := (pi_mkt * S0u + (1 - pi_mkt) * S0d) / (1 + .r_month)]
.stk_m <- .stk_m[is.finite(S0_fair) & S0_fair > 0]

# ---- d_i = S0d / S0_fair, p-index (eq. 7) ----
.stk_m[, d_i := S0d / S0_fair]
.stk_m[, p_index := ((1 + .delta) - d_i) / (1 + .delta) * (1 - pi_mkt) / (1 + .r_month)]
# p-index 이론 하/상한: Max[1/(1+r)-1/(1+δ),0] ≤ p_index < 1/(1+r). δ=r 이면 하한 0.
.stk_m <- .stk_m[is.finite(p_index)]

# ---- 신호월(.ym) → 그 달 마지막 거래일을 시그널 Date 로 매핑 ----
.me <- RAWDATA[, .(Date = max(Date)), by = .ym]
.stk_m <- merge(.stk_m, .me, by = ".ym", all.x = FALSE)

# ---- Score: 방향별 p-index 정렬 ----
if (.DIR == "LOW") {
  .stk_m[, Score := -p_index]   # 저 p-index(저리스크) 롱
} else {
  .stk_m[, Score :=  p_index]   # 고 p-index(고리스크) 롱
}

# ---- 유동성 통과 종목만 (해당 시그널 날짜 LiqPass) ----
.liq <- unique(RAWDATA[LiqPass == TRUE, .(Date, Ticker)])
FACTORS <- merge(.stk_m[is.finite(Score), .(Date, Ticker, Score)],
                 .liq, by = c("Date", "Ticker"), all.x = FALSE)
FACTORS <- unique(FACTORS[, .(Date, Ticker, Score)])

# ---- 정리 ----
RAWDATA[, .ym := NULL]
BM_DT[,   .ym := NULL]

cat(sprintf("[fe_pindex 2606.08569] direction=%s | FACTORS rows=%d | signal dates=%d | tickers=%d\n",
            .DIR, nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
