#==============================================================================
# uw_erosion_dbeta — 수중(underwater) 침식 강도 × 하방베타 배분 오버레이 (2026-09-17 · 사전등록 설계)
#
# ★표적 칸: action = cross_sectional · state = drawdown
#
# ★기전 (사전 선언)
#   깊이만 보는 낙폭 계열은 급락에서 분위가 즉시 극단으로 가지만, 완만한 침식(깊이는 중간 ·
#   기간은 길다 · 추세는 음)에서는 덜 개입한다. 이 arm 은 수중 상태를 네 축으로 읽는다:
#   깊이(depth) · 수중 연속 개월수(dur) · 12개월 추세의 음(trend) · 현 수중 구간 바닥 대비 반등(rec).
#   각 축은 자기 과거(1..t-1)에서의 희소도(엄격 경험분위 — 과거값 중 현재값보다 작은 비율)로만
#   읽는다. 상수 문턱 없음. 침식 강도 s = q_depth · q_dur · q_trend · (1 − q_rec)  (곱).
#   고점(depth = dur = 0)이면 s = 0 → 전액 투자. 목표 총노출 E = 1 − s.
#   축소분 (1−E) 은 그 달 보유의 하방베타 순위 k(가중평균 1)에 비례 배분한다:
#   e_i = 1 − (1−E)·k_i, [0,1] 절단 후 잘린 몫은 남은 종목에 k 비례로 재배분(물채우기)해
#   책 가중평균 노출이 E 와 정확히 같게 한다. 하방베타 미추정 종목은 e = E.
#   즉 현금 타이밍(전략↔현금)과 종목별 배분을 한 arm 에서 결합한다.
#   ★반증 조건: V자 급반등 직전 바닥에서 현금이 최대가 되어 반등을 놓치면 CAGR 손실이
#     낙폭 감소를 상쇄한다. rec 축이 바닥 탈출 시 강도를 되돌리지만 바닥은 사후에만 확인되므로
#     첫 반등 달은 구조적으로 놓친다.
#
# ★사전등록 수정 2건 (측정 전 · 2026-09-17 코디네이터 결정)
#   ① 상태 원천 = 엔진 H(KOSPI200 벤치마크 nav/dd/r252)이지 책 NAV 가 아니다. 오버레이는 하네스가
#      수익을 시뮬레이션하기 전에 적용되는 비중 변환이라, 현 엔진에서는 오버레이 시점에 책 NAV 가
#      존재하지 않는다. 또 이 설계의 기전 전제는 "이 전략 계열의 낙폭은 보유 종목이 공유하는 시장
#      적재에서 온다" 이므로 시장의 침식 상태가 기전에 정합하는 상태변수다. 책 NAV 채널은 뒤로
#      미룬 엔진 변경이다(여기서 구현하지 않는다).
#   ② 강도 사상 = 기하평균 대신 곱. 기하평균은 보통의 상태(각 엄격 순위 ≈ 0.5)를 s ≈ 0.5 로 보내
#      평범한 달에 절반 현금이 되어 "희소한 역경 상태에서만 개입한다" 는 목적과 모순된다. 곱은
#      보통의 상태를 ≈ 0.125 로 보내고 네 축이 함께 극단일 때만 완전 현금 쪽으로 간다.
#
# ★계약
#   반환 = 스칼라 e ∈ [0,1] 또는 data.table(Ticker, e). H = 확장창(t 행까지).
#   H$fwd 는 t 행이 미실현이므로 읽지 않는다(어느 열도 t 이후를 보지 않는다).
#   H$nav · H$dd · H$r252 = 엔진이 BM_DT(KOSPI200)에서 만든 시그널일 표본(rf_cell_engine.R:443-475).
#   과거 행의 상태값도 그 행 시점까지의 정보로만 만든다(구간 바닥 = 누적 최소).
#   표본 부족(과거 유효 행 < ctx$n_min · 엔진 워밍업 하한) 이면 e <- 1(무개입) — 숫자를 지어내지 않는다.
#   비중은 등가 — 엔진 .HOLD 는 비중을 싣지 않는다(Weight 열이 오면 그 가중으로 같은 식).
#==============================================================================

overlay_expo_uw_erosion_dbeta <- function(H, t, ctx) {
  t <- suppressWarnings(as.integer(t))
  if (length(t) != 1L || !is.finite(t) || t < 1L) return(1)
  n_min <- suppressWarnings(as.integer(ctx$n_min))
  if (length(n_min) != 1L || !is.finite(n_min)) return(1)    # 엔진 하한이 없으면 추정을 시작하지 않는다

  nav  <- suppressWarnings(as.numeric(H$nav))
  dd   <- suppressWarnings(as.numeric(H$dd))
  r252 <- suppressWarnings(as.numeric(H$r252))
  if (length(nav) < t || length(dd) < t || length(r252) < t) return(1)
  nav <- nav[seq_len(t)]; dd <- dd[seq_len(t)]; r252 <- r252[seq_len(t)]
  if (!all(is.finite(nav))) return(1)

  # ── ① 수중 상태 4축 — 행 i 의 값은 i 까지의 정보로만(과거 행도 그 시점 PIT 값)
  below <- nav < cummax(nav)                                  # 고점 아래인가 — 구조적(리터럴 없음)
  grp   <- cumsum(!below)                                     # 고점 행에서 시작하는 구간 번호
  dur   <- stats::ave(as.numeric(below), grp, FUN = cumsum)   # 수중 연속 개월수(고점 = 0)
  smin  <- stats::ave(nav, grp, FUN = cummin)                 # 현 구간 바닥(누적 최소)
  depth <- abs(dd)                                            # 부호규약 무관 — 크기만(고점 = 0)
  trend <- -r252                                              # 12개월 추세의 음 — 클수록 침식
  rec   <- nav / smin - 1                                     # 구간 바닥 대비 반등(고점·신저점 = 0)
  rec[!below] <- 0

  # ── ② 희소도 — 엄격 과거(1..t-1) 경험분위 ∈ [0,1). 유효 표본 < n_min 이면 추정하지 않는다
  past <- seq_len(t - 1L)
  .q <- function(x) {
    p <- x[past]; p <- p[is.finite(p)]
    if (length(p) < n_min || !is.finite(x[t])) return(NA_real_)
    mean(p < x[t])
  }
  q_depth <- .q(depth); q_dur <- .q(dur); q_trend <- .q(trend); q_rec <- .q(rec)
  if (anyNA(c(q_depth, q_dur, q_trend, q_rec))) return(1)     # 표본 부족 = 무개입

  # ── ③ 침식 강도(곱) → 목표 총노출
  s <- q_depth * q_dur * q_trend * (1 - q_rec)
  E <- max(0, min(1, 1 - s))

  # ── ④ 종목 배분 — 축소분 (1−E) 을 하방베타 순위에 비례. 물채우기로 가중평균 = E 를 정확히 맞춘다
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(E)                 # 보유 정보가 없으면 스칼라 총노출
  tk <- as.character(hold$Ticker)
  n  <- length(tk)
  b  <- suppressWarnings(as.numeric(hold$dbeta))
  if (length(b) != n) b <- rep(NA_real_, n)
  # 비중 — 계약(ctx$hold)에 비중 열이 있으면 그것, 없으면 등가(엔진 .HOLD 는 비중을 싣지 않는다)
  w <- if ("Weight" %in% names(hold)) suppressWarnings(as.numeric(hold$Weight)) else rep(1, n)
  if (length(w) != n || !all(is.finite(w)) || !all(w > 0)) w <- rep(1, n)

  ok <- is.finite(b)
  e  <- rep(E, n)                                             # 하방베타 미추정 종목 = 책 평균 노출
  if (any(ok)) {
    wk <- w[ok] / sum(w[ok])
    k  <- rank(b[ok], ties.method = "average")
    k  <- k / sum(wk * k)                                     # 가중평균 1 로 정규화
    R  <- 1 - E                                               # 가중평균 축소 목표
    cap <- rep(FALSE, length(k)); lam <- 0
    repeat {                                                  # 물채우기: sum wk·min(1, lam·k) = R
      free  <- !cap
      denom <- sum(wk[free] * k[free])
      lam   <- if (denom > 0) (R - sum(wk[cap])) / denom else 0
      over  <- free & (lam * k > 1)
      if (!any(over)) break
      cap <- cap | over
    }
    red <- pmin(1, pmax(0, lam * k)); red[cap] <- 1
    e[ok] <- 1 - red
  }
  data.table::data.table(Ticker = tk, e = pmax(0, pmin(1, e)))
}
