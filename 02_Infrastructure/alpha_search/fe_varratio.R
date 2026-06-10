# =============================================================================
# fe_varratio.R — Variance Ratio Information Speed (H-10)
# =============================================================================
# 가설 출처: paper_ensemble_hypotheses.md H-10 (Lo-MacKinlay 1988 Variance Ratio
#   "Stock Market Prices Do Not Follow Random Walks", RFS 응용) + Beyond Volatility
#   (arXiv 2208.14267) idiosyncratic quantile risk 맥락.
#
# 메커니즘: 종목이 일간 수준에서는 추세(VR>1)지만 주간 수준에서는 평균회귀(VR<1)
#   하는 "정보처리 속도" 스프레드를 cross-sectional alpha로. 뉴스는 빠르게 반영
#   되나 펀더멘털 가격발견이 느린 종목 = 지속적 미스프라이싱.
#
# 신호: Score_i = VR(5d/1d) - VR(20d/5d)  (높을수록 매수)
#   VR(q-base-b) = Var(b-합 기준 q-step 수익률) / ((q/b) * Var(b-합 수익률))  [Lo-MacKinlay]
#   - VR(5d/1d)  = Var(5일합 lr) / (5 * Var(1일 lr))      : 1→5일 분산비(단기 추세)
#   - VR(20d/5d) = Var(20일합 lr) / (4 * Var(5일합 lr))   : 5→20일 분산비(장기 회귀)
#
# ★ 제1원칙(완전 복제) — 논문 미명시값 보충 (명시):
#   - 추정 윈도우: rolling 252 거래일(약 1년). H-10/Lo-MacKinlay 미명시 → KR 표준 252d 보충.
#   - 비중·종목수: top decile + (run_alpha_search weight_method 인자) — H-10 "long top decile" 따름.
#   - 리밸런싱: 월간(월말 시그널) — KR factor 표준 보충.
#   - 수익률: 로그수익률(VR 표준 정의 정합).
#
# ===== PIT =====
#   - VR 추정은 t(월말) 시점 과거 252일 lr만 사용(과거 윈도우). 동일시점 순환참조 없음.
#   - lr = log(Close/shift(Close,1)) — t-1 종가까지. NEGATE/FLIP 없음.
# RAWDATA columns: Date, Ticker, Close, Vol, LiqPass, K200, KQ150 ...
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- VR 스프레드 함수 (Lo-MacKinlay overlapping VR) -------------------------
.vr_spread <- function(x) {
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < 120L) return(NA_real_)                 # 최소 표본 가드
  v1 <- stats::var(x)
  if (!is.finite(v1) || v1 <= 0) return(NA_real_)
  s5  <- frollsum(x, 5L);  v5  <- stats::var(s5,  na.rm = TRUE)
  s20 <- frollsum(x, 20L); v20 <- stats::var(s20, na.rm = TRUE)
  if (!is.finite(v5) || v5 <= 0 || !is.finite(v20)) return(NA_real_)
  vr5  <- v5  / (5 * v1)     # VR(5d/1d)
  vr20 <- v20 / (4 * v5)     # VR(20d/5d)
  vr5 - vr20
}

# ---- 로그수익률 + 월말 시그널 날짜 -----------------------------------------
RAWDATA[, .lr := log(Close / shift(Close, 1L)), by = Ticker]
RAWDATA[, .ym := format(Date, "%Y-%m")]
.me <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
RAWDATA[, .ym := NULL]

# ---- 월말 행에만 과거 252일 윈도우로 VR 계산 (성능: 월말만 평가) ------------
RAWDATA[, .vr := {
  v  <- rep(NA_real_, .N)
  mp <- which(Date %in% .me & LiqPass == TRUE)
  for (ix in mp) {
    lo <- ix - 251L
    if (lo >= 1L) v[ix] <- .vr_spread(.lr[lo:ix])
  }
  v
}, by = Ticker]

# ---- FACTORS 산출 (월말 + VR 유효; top decile EW는 N 컬럼) ------------------
FACTORS <- RAWDATA[is.finite(.vr), .(Date, Ticker, Score = .vr)]
FACTORS[, N := pmax(5L, as.integer(ceiling(.N / 10))), by = Date]   # top decile

RAWDATA[, c(".lr", ".vr") := NULL]
cat(sprintf("[fe_varratio] H-10 VR InfoSpeed | rows=%d dates=%d decile N=%d~%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            if (nrow(FACTORS)) min(FACTORS$N) else 0L,
            if (nrow(FACTORS)) max(FACTORS$N) else 0L))
