#==============================================================================
# compute_technical.R — Technical Factor 계산 모듈 (T01~T15) · 신설 2026-09-01
#
# 왜 이제야 생기나: registry 에 technical 12종이 **등재돼 있는데 생산자 코드가 없었다**.
#   emission_expected_absent.json 이 이미 진단해 뒀다 — "월 빌더 compute_*.R 에 생산자 코드
#   없음 (technical 계열 12종 전체가 동일) · compute_*.R 전수 grep 0건 · 원장 440개월 0회 ·
#   계열 전체 결측(부분 결측 아님)". 즉 데이터가 없어서가 아니라 **아무도 한 줄을 안 썼기
#   때문**이다(weight_catalog·overlay_catalog 가 진단한 것과 같은 병).
#   원천은 이미 있다 — 12종 전부 data_source=price 이고 정의가 registry 에 수식으로 박혀 있다.
#
# 함수: compute_technical(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL)
# 반환: data.table(Ticker, Factor_Name, Raw_Value)
#
# PIT: RAWDATA 는 빌더가 Date <= sig_date 로 이미 잘라 준다(모듈 계약). 이 파일은 그 안에서
#   **후행 창만** 쓰고 미래를 참조하지 않는다. 방향(부호)은 여기서 정하지 않는다 —
#   커넥터의 expanding IC 가 Z_Score_Aligned 로 정렬한다(C13: NEGATE/FLIP 금지).
#
# 정의 출처 = .cache/factor_db/factor_registry.json (지어내지 않았다):
#   T01_RSI14   RSI, 14d Wilder smoothing            T10_RSI28  RSI, 28d Wilder
#   T03_BB20    (Close - MA20) / (2 * SD20)          T13_Gap    (Open - prevClose)/prevClose
#   T04_OBV21   cumulative signed volume slope 21d   T14_HLRange (High - Low) / Open
#   T05_MFI14   volume-weighted RSI, 14d             T15_AutoCorr AR(1) of daily ret over 21d
#   T06~T09_PMA{5,20,60,120}  Close / MA_n - 1
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })

.tech_lookback <- 200L   # 종목당 필요한 최근 거래일 수 (최장 창 120 + Wilder 수렴 여유)

# Wilder RSI — 마지막 값 하나. 창이 모자라면 NA.
.tech_rsi <- function(cl, period) {
  n <- length(cl)
  if (n < period * 2L + 1L) return(NA_real_)
  d <- diff(cl)
  up <- pmax(d, 0); dn <- pmax(-d, 0)
  ag <- mean(up[seq_len(period)]); al <- mean(dn[seq_len(period)])
  if (length(d) > period) for (i in (period + 1L):length(d)) {
    ag <- (ag * (period - 1L) + up[i]) / period
    al <- (al * (period - 1L) + dn[i]) / period
  }
  if (!is.finite(ag) || !is.finite(al)) return(NA_real_)
  if (al == 0) return(if (ag == 0) 50 else 100)
  100 - 100 / (1 + ag / al)
}

# Money Flow Index — 거래대금 가중 RSI
.tech_mfi <- function(hi, lo, cl, vo, period) {
  n <- length(cl)
  if (n < period + 1L) return(NA_real_)
  tp <- (hi + lo + cl) / 3
  rmf <- tp * vo
  d <- diff(tp)
  idx <- (n - period):(n - 1L)                 # 마지막 period 개의 변화
  pos <- sum(rmf[idx + 1L][d[idx] > 0], na.rm = TRUE)
  neg <- sum(rmf[idx + 1L][d[idx] < 0], na.rm = TRUE)
  if (!is.finite(pos) || !is.finite(neg)) return(NA_real_)
  if (neg == 0) return(if (pos == 0) 50 else 100)
  100 - 100 / (1 + pos / neg)
}

# 마지막 w 개 점에 대한 선형 추세 기울기 (시간에 대한 OLS 계수)
.tech_slope <- function(v, w) {
  n <- length(v); if (n < w) return(NA_real_)
  y <- v[(n - w + 1L):n]; x <- seq_len(w)
  if (!all(is.finite(y))) return(NA_real_)
  sx <- var(x); if (!is.finite(sx) || sx == 0) return(NA_real_)
  cov(x, y) / sx
}

.tech_pma <- function(cl, w) {
  n <- length(cl); if (n < w) return(NA_real_)
  m <- mean(cl[(n - w + 1L):n], na.rm = TRUE)
  if (!is.finite(m) || m <= 0) return(NA_real_)
  cl[n] / m - 1
}

compute_technical <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {
  empty <- data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric())
  rd <- as.data.table(RAWDATA)
  if (!nrow(rd)) return(empty)
  need <- c("Date", "Ticker", "Open", "High", "Low", "Close", "Vol")
  if (!all(need %in% names(rd))) {
    warning("[compute_technical] 필수 컬럼 부재: ", paste(setdiff(need, names(rd)), collapse = ", "))
    return(empty)
  }
  # 최근 lookback 거래일만 (전 이력을 종목별로 도는 것을 피한다 — PIT 는 이미 빌더가 보장)
  ds <- sort(unique(rd$Date), decreasing = TRUE)
  ds <- ds[seq_len(min(.tech_lookback, length(ds)))]
  rd <- rd[Date %in% ds]
  setorder(rd, Ticker, Date)

  out <- rd[, {
    cl <- as.numeric(Close); op <- as.numeric(Open)
    hi <- as.numeric(High);  lo <- as.numeric(Low); vo <- as.numeric(Vol)
    n <- length(cl)
    ok <- n >= 2L && is.finite(cl[n]) && cl[n] > 0
    ret <- if (n >= 2L) c(NA_real_, cl[-1L] / cl[-n] - 1) else NA_real_

    # OBV = 부호 있는 거래량 누적, 그 21일 기울기
    obv <- if (n >= 2L) cumsum(c(0, sign(diff(cl)) * vo[-1L])) else NA_real_

    # AR(1) — 최근 21일 일간수익률의 1차 자기상관 계수
    ac <- {
      if (n < 23L) NA_real_ else {
        r <- ret[(n - 20L):n]; r <- r[is.finite(r)]
        if (length(r) < 10L) NA_real_ else {
          a <- r[-length(r)]; b <- r[-1L]
          v <- var(a)
          if (!is.finite(v) || v == 0) NA_real_ else cov(a, b) / v
        } } }

    bb <- {
      if (n < 20L) NA_real_ else {
        w <- cl[(n - 19L):n]; s <- stats::sd(w)          # 직접 sd() — 모멘트 항등식 금지
        if (!is.finite(s) || s <= 0) NA_real_ else (cl[n] - mean(w)) / (2 * s)
      } }

    gap <- if (n >= 2L && is.finite(op[n]) && is.finite(cl[n - 1L]) && cl[n - 1L] > 0)
             op[n] / cl[n - 1L] - 1 else NA_real_
    hlr <- if (is.finite(hi[n]) && is.finite(lo[n]) && is.finite(op[n]) && op[n] > 0)
             (hi[n] - lo[n]) / op[n] else NA_real_

    list(Factor_Name = c("T01_RSI14", "T03_BB20", "T04_OBV21", "T05_MFI14",
                         "T06_PMA5", "T07_PMA20", "T08_PMA60", "T09_PMA120",
                         "T10_RSI28", "T13_Gap", "T14_HLRange", "T15_AutoCorr"),
         Raw_Value = c(if (ok) .tech_rsi(cl, 14L) else NA_real_,
                       if (ok) bb else NA_real_,
                       if (ok) .tech_slope(obv, 21L) else NA_real_,
                       if (ok) .tech_mfi(hi, lo, cl, vo, 14L) else NA_real_,
                       if (ok) .tech_pma(cl, 5L) else NA_real_,
                       if (ok) .tech_pma(cl, 20L) else NA_real_,
                       if (ok) .tech_pma(cl, 60L) else NA_real_,
                       if (ok) .tech_pma(cl, 120L) else NA_real_,
                       if (ok) .tech_rsi(cl, 28L) else NA_real_,
                       if (ok) gap else NA_real_,
                       if (ok) hlr else NA_real_,
                       if (ok) ac else NA_real_))
  }, by = Ticker]

  out <- out[is.finite(Raw_Value)]
  if (!nrow(out)) return(empty)
  out[, .(Ticker = as.character(Ticker), Factor_Name, Raw_Value = as.numeric(Raw_Value))]
}

cat("[compute_technical] Loaded — T01/T03/T04/T05/T06~T09/T10/T13/T14/T15 (12종, price 원천)\n")
