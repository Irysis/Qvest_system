# =============================================================================
# fe_short_term_momentum.R — Medhat & Schmeling (2022, RFS 35(3)) "Short-term Momentum" 의 KR 복제
#   (pg2 큐 title:shorttermmomentum)
# =============================================================================
# 논문 핵심: 직전 1개월 수익률 r(1,0) 은 평균적으로 반전(short-term reversal)이지만 **회전율이 높은
#   종목에서는 모멘텀**(short-term momentum) — 저회전 종목에서 반전, 고회전 종목에서 지속. 독립/조건부
#   이중정렬 r(1,0) × TO(1,0), 롱 코너 = 고회전 ∧ 고수익(winner). 월간 리밸, 1개월 보유.
# KR 재구성 (pg2 implementation_sketch):
#   - r(1,0) = 직전 21 거래일 수익률(Close_t / Close_{t−21} − 1). TO(1,0) = 직전 21일 평균 일별 회전율
#     = mean(Vol × Close / Size)(Size = 시가총액, Vol = 주식수 거래량 ⇒ 주식 회전율과 동일).
#     논문 변형(말일 3일 스킵)은 보조 — 기본은 스킵 없음(논문 본판).
#   - 유니버스 ~300~350 이라 decile 코너 희박 → **조건부 quintile 정렬**(TO 5분위 → 내부 r(1,0) 5분위),
#     롱 코너 = TO 최상위 quintile 안의 r(1,0) 최상위 quintile 전부 EW(동적 N ≈ 12~15).
#     논문 가중(VW) 미확인 → 시스템 표준 EW(명시 보충). ★회전율 ~1,000%/yr 예상(논문도 고회전) — 15bps 과금.
#   - 유니버스 K200∪KQ150 ∧ 유동성 2e8. 기간 2005~.
# ===== PIT (C1~C15) =====
#   - 모든 입력은 t 이전 윈도우(shift/rolling)만(C2). full-sample 통계 없음(C1). 회전율 t−1 관측치(C10).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

LB <- 21L; Q_CUT <- 0.20

RAWDATA[, .r10 := Close / shift(Close, LB) - 1, by = Ticker]
RAWDATA[, .to_d := fifelse(is.finite(Size) & Size > 0, Vol * Close / Size, NA_real_)]
RAWDATA[, .to10 := frollmean(.to_d, LB, align = "right", na.rm = TRUE), by = Ticker]
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]

RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.month_ends <- .month_ends[.month_ends >= as.Date("2004-06-01")]

.panel <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                    !is.na(.AvgTV20) & .AvgTV20 >= 2e8 & is.finite(.r10) & is.finite(.to10) & .to10 > 0,
                  .(Date, Ticker, R10 = .r10, TO10 = .to10)]
RAWDATA[, c(".r10", ".to_d", ".to10", ".TV", ".AvgTV20") := NULL]
setkey(.panel, Date, Ticker)

.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  pd <- .panel[.(d), nomatch = 0L]
  if (nrow(pd) < 50L) next
  pd[, p_to := (frank(-TO10, ties.method = "first") - 0.5) / .N]      # 고회전 = 상위
  hi <- pd[p_to <= Q_CUT]
  if (nrow(hi) < 10L) next
  hi[, p_r := (frank(-R10, ties.method = "first") - 0.5) / .N]        # 고회전 내 winner = 상위
  corner <- hi[p_r <= Q_CUT]
  if (nrow(corner) < 3L) next
  out <- corner[, .(Date = d, Ticker, Score = R10)]
  out[, N := .N]
  .factor_list[[i]] <- out
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)
if (!nrow(FACTORS)) stop("[fe_short_term_momentum] FACTORS 0 rows")

cat(sprintf("[fe_short_term_momentum] Medhat-Schmeling(2022) KR: TO(1,0) 상위 quintile 내 r(1,0) 상위 quintile 코너 EW 월간 | FACTORS rows=%d | signal months=%d | N range=%d~%d (median %d)\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), min(FACTORS$N), max(FACTORS$N), as.integer(median(FACTORS$N))))
