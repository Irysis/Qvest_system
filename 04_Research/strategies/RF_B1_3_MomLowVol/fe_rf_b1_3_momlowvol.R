# =============================================================================
# fe_rf_b1_3_momlowvol.R — 규칙기반 고속강화 B1-3 (rulefast 3/20 · 설계 재량 0)
# 신호: 모멘텀(12-1) rank-Z + 저변동성(직전 60거래일 일수익 σ 역방향) rank-Z 50/50
# 근거: Jegadeesh & Titman (1993, JF 48) — 12-1 가격모멘텀
#       Ang, Hodrick, Xing & Zhang (2006, JF 61) — 고변동성 종목의 낮은 기대수익
#       https://onlinelibrary.wiley.com/doi/10.1111/j.1540-6261.2006.00836.x
# ===== PIT 구조 논거 =====
#  C2: σ60 = shift(.ret,1L) 기반 → 창 종점 t-1 (당일 수익 미포함, 순환참조 없음)
#  C1: frollmean 60일 rolling 만 사용 — full-sample 시계열 통계 없음.
#      rank-Z 는 시그널일 '횡단면' 표준화(그 날 알 수 있는 단면) — 시계열 집계 아님
#  C10: adv20 = shift(.TV,1L) 기반 20일 평균 → t-1 까지만
#  C13: 부호반전 없음 — 저변동성 고득점(-vol60 랭크)은 AHXZ2006 의 경제적 방향
#  모멘텀 끝점 = t-21 (skip 1개월) · 시작점 t-252 — JT1993 12-1 그대로
# =============================================================================
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

RAWDATA[, .ret := Close / shift(Close, 1L) - 1, by = Ticker]
RAWDATA[, .s1  := frollmean(shift(.ret, 1L),      60L), by = Ticker]   # t-1까지 60일 평균
RAWDATA[, .s2  := frollmean(shift(.ret, 1L) ^ 2L, 60L), by = Ticker]   # t-1까지 60일 제곱평균
RAWDATA[, .vol60 := sqrt(pmax(.s2 - .s1 ^ 2L, 0))]                     # σ = sqrt(E[r^2]-E[r]^2)
RAWDATA[, .mom := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]  # 12-1
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .adv20 := frollmean(shift(.TV, 1L), 20L), by = Ticker]       # C10: t-1까지

RAWDATA[, .ym := format(Date, "%Y-%m")]
.me <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)

EL <- RAWDATA[Date %in% .me & (K200 == TRUE | KQ150 == TRUE) &
                is.finite(.adv20) & .adv20 >= 2e8 &
                is.finite(.mom) & is.finite(.vol60) & .vol60 > 0,
              .(Date, Ticker, mom = .mom, vol60 = .vol60)]

.rz <- function(x) {                                                   # 횡단면 rank-Z
  r <- frank(x, ties.method = "average")
  s <- sd(r)
  if (!is.finite(s) || s == 0) return(rep(0, length(r)))
  (r - mean(r)) / s
}
EL[, z_mom := .rz(mom),    by = Date]
EL[, z_lv  := .rz(-vol60), by = Date]                                  # σ 낮을수록 높은 점수
EL[, Score := 0.5 * z_mom + 0.5 * z_lv]

FACTORS <- EL[is.finite(Score), .(Date, Ticker, Score)]
RAWDATA[, c(".ret", ".s1", ".s2", ".vol60", ".mom", ".TV", ".adv20", ".ym") := NULL]
cat(sprintf("[fe_rf_b1_3] rows=%d dates=%d avg_n_per_date=%.0f\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), nrow(FACTORS) / uniqueN(FACTORS$Date)))
