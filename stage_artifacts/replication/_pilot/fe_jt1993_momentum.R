# fe_jt1993_momentum.R — v10 충실구현 파일럿 엔진
# 논문: Jegadeesh & Titman (1993, JF) "Returns to Buying Winners and Selling Losers"
#   원문: https://www.bauer.uh.edu/rsusmel/phd/jegadeesh-titman93.pdf (classic seed)
# 사양(논문 그대로): J=6개월 형성기(직전 1개월 skip 은 후속 관례 — 여기선 J6/skip1 채택,
#   Table 1 의 6-6 전략 계열), 월말 시그널, 데실 승자 롱 / 패자 숏, EW.
# PIT: 형성기 수익 = t-1 까지의 과거 수익만(shift). 동일시점 참조 없음.

suppressPackageStartupMessages({ library(data.table) })

stopifnot(exists("RAWDATA"))
rd <- RAWDATA[is.finite(Ret), .(Date, Ticker, Ret)]
setorder(rd, Ticker, Date)

# 월말 식별
rd[, ym := format(Date, "%Y-%m")]
month_ends <- rd[, .(me = max(Date)), by = ym]$me
me_set <- sort(unique(month_ends))

# 월간 수익 (월내 복리 — 시그널 형성용 과거 집계)
mret <- rd[, .(mr = prod(1 + Ret) - 1), by = .(Ticker, ym)]
setorder(mret, Ticker, ym)
# 형성기: 직전 7~2개월 (J=6, skip 최근 1개월) — shift 로 과거만 참조 (PIT)
mret[, form := {
  x <- shift(mr, 2L)  # t-2
  s <- rep(NA_real_, .N)
  for (k in 2:7) {
    xx <- shift(mr, k)
    s <- ifelse(is.na(s), 0, s) + log(1 + fifelse(is.finite(xx), xx, NA_real_))
  }
  s
}, by = Ticker]
mret[, n_form := {
  cnt <- rep(0L, .N)
  for (k in 2:7) cnt <- cnt + as.integer(is.finite(shift(mr, k)))
  cnt
}, by = Ticker]

sig <- mret[is.finite(form) & n_form == 6L]
# ym → 월말 날짜
ym_me <- data.table(ym = format(me_set, "%Y-%m"), Date = me_set)
sig <- merge(sig, ym_me, by = "ym")

FACTORS <- sig[, .(Date, Ticker, Score = form)]
cat(sprintf("[fe_jt1993] FACTORS: %d rows · %d months · %d tickers\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
