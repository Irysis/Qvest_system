# =============================================================================
# fe_ptv_intermediate_top25.R — [배포형태 변형] Eom, Eom & Park (2026, Research in International Business and Finance)
#   "Investor trading behavior and intermediate prospect theory value in cross-sectional expected
#   returns" 의 KR 복제 (pg2 큐 title:investortradingbehaviorandintermediateprospecttheoryvalue…)
# =============================================================================
# 논문 핵심(Google Scholar 초록 발췌 — 본문·SSRN·ScienceDirect 접근 불가): "past intermediate prospect
#   theory value (PTV) based on 12-month return distributions" 과 기대수익의 **양(+)** 관계 — Barberis-
#   Jin-Wang(2021) 의 장기(60M) PTV 음(−) 관계와 반대 방향인 '중기' 변형. 투자자 거래행태가 이를 매개.
# KR 재구성:
#   - PTV = Tversky-Kahneman 누적전망이론 값(BJW 2021 식): 과거 12개월 **월간 수익률** 12개 관측 분포
#     (FREQ="monthly"; 초록 '12-month return distributions' — 일별(252d) 변형은 FREQ="daily" 로 전환 가능,
#     논문 본문 미확인이라 월간을 기본으로 두고 명시). 파라미터 α=0.88 · λ=2.25 · γ=0.61 · δ=0.69(TK 1992).
#     v(x)=x^α (x≥0), −λ(−x)^α (x<0); 확률가중 w+(p)=p^γ/(p^γ+(1−p)^γ)^(1/γ), w−(p)=p^δ/(p^δ+(1−p)^δ)^(1/δ);
#     결정가중 = 누적 확률가중의 차분(이득은 상위부터, 손실은 하위부터). PTV = Σ π_i·v(r_i).
#   - 롱 레그 = PTV **상위** decile(ceiling(n/10), ≥5) EW 월간(양(+) 관계 → 고PTV 매수). 정렬 분위수·
#     가중은 논문 미확인 → 시스템 표준(명시 보충). 유니버스 K200∪KQ150 ∧ 유동성 2e8. 기간 2005~.
# ===== PIT (C1~C15) =====
#   - 월말 d 의 PTV 는 d 이전 12개월 월간 수익률만(과거 윈도우, C2). full-sample 통계 없음(C1).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

FREQ  <- "monthly"
N_WIN <- 12L
TK_A <- 0.88; TK_L <- 2.25; TK_G <- 0.61; TK_D <- 0.69

.w_plus  <- function(p) p^TK_G / (p^TK_G + (1 - p)^TK_G)^(1 / TK_G)
.w_minus <- function(p) p^TK_D / (p^TK_D + (1 - p)^TK_D)^(1 / TK_D)
.ptv <- function(r) {
  r <- r[is.finite(r)]; n <- length(r)
  if (n < 6L) return(NA_real_)
  r <- sort(r)
  v <- ifelse(r >= 0, r^TK_A, -TK_L * (-r)^TK_A)
  pi <- numeric(n)
  # 이득: 상위부터 누적 (P(r >= r_i) − P(r > r_i)) ; 손실: 하위부터 누적 (P(r <= r_i) − P(r < r_i))
  for (i in seq_len(n)) {
    if (r[i] >= 0) {
      pi[i] <- .w_plus((n - i + 1) / n) - .w_plus((n - i) / n)
    } else {
      pi[i] <- .w_minus(i / n) - .w_minus((i - 1) / n)
    }
  }
  sum(pi * v)
}

RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]

RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.me <- RAWDATA[Date %in% .month_ends, .(Date, Ticker, Close, K200, KQ150, AvgTV20 = .AvgTV20)]
RAWDATA[, c(".TV", ".AvgTV20") := NULL]
setorder(.me, Ticker, Date)
.me[, mret := Close / shift(Close, 1L) - 1, by = Ticker]          # 월간 수익률(월말 종가 기준)

if (FREQ == "monthly") {
  .me[, PTV := frollapply(mret, N_WIN, .ptv, align = "right"), by = Ticker]
} else {
  RAWDATA[, .dr := Close / shift(Close, 1L) - 1, by = Ticker]
  RAWDATA[, .ptvd := frollapply(.dr, 252L, .ptv, align = "right"), by = Ticker]
  .me <- merge(.me, RAWDATA[Date %in% .month_ends, .(Date, Ticker, PTV = .ptvd)], by = c("Date", "Ticker"))
  RAWDATA[, c(".dr", ".ptvd") := NULL]
}

.panel <- .me[Date >= as.Date("2004-06-01") & (K200 == TRUE | KQ150 == TRUE) &
                !is.na(AvgTV20) & AvgTV20 >= 2e8 & is.finite(PTV), .(Date, Ticker, PTV)]
.panel[, N := 25L]   # 배포 형태: 상위 25종
FACTORS <- .panel[, .(Date, Ticker, Score = PTV, N)]
if (!nrow(FACTORS)) stop("[fe_ptv_intermediate_top25] FACTORS 0 rows")

cat(sprintf("[fe_ptv_intermediate_top25] Eom-Eom-Park(2026) KR: 12M %s 수익률 TK-PTV 상위 25종 EW 월간 | FACTORS rows=%d | signal months=%d\n",
            FREQ, nrow(FACTORS), uniqueN(FACTORS$Date)))
