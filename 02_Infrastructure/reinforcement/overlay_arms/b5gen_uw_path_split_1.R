#==============================================================================
# b5gen_uw_path_split_1 — 수중(underwater) 경로 예산 × 경로 형태별 채널 회전 × 물채우기 배분
#                         (표적 칸: action = cross_sectional · state = drawdown)
#
# ★기전 (사전 선언 — 특정 시기를 보고 만든 규칙이 아니다)
#   낙폭 계열 arm 은 상태를 '지금 얼마나 깊은가' 한 숫자로 읽고, 종목 차등 계열은 그 강도를
#   1 − g·순위 로 모든 보유에 얇게 펴 바른다(책 평균 노출 1 − g/2 는 규칙의 부산물로 정해진다).
#   이 arm 은 세 가지를 바꾼다.
#   ① 상태 = 벤치 수중 **경로**: 깊이(depth) · 수중 연속 개월수(dur) · 12개월 추세의 음(trend) ·
#      현 구간 바닥 대비 반등(rec). 각 축은 엄격 과거(1..t−1)의 **수중 달들** 안에서의 경험분위로만
#      읽는다(상수 문턱 없음). 강도 s = q_depth · q_dur · q_trend · (1 − q_rec) (곱).
#      곱이라 평범한 수중 달(각 분위 ≈ 중앙)은 s ≈ 1/16 로 거의 무개입이고, 네 축이 함께 극단인
#      드문 달에만 강하게 선다 — 개입이 드물고 오래 이어지는 형태라 한 달 지연에 둔감하고
#      상수 축소와도 갈린다. rec 축은 바닥 탈출 시 강도를 되돌려 회복 구간에서 스스로 풀린다.
#      깊이 계열(급락에서만 극단)과 지속성 계열(길이만 본다)이 따로 못 잡는 '깊고 길고 아직
#      반등 없는' 상태를 곱이 잡는다.
#   ② 소비 = 책 평균 노출 **예산** E = 1 − s 를 먼저 정하고, 축소분 (1 − E) 을 종목 취약도 k 에
#      비례해 배분하되 [0,1] 절단분은 물채우기로 재배분해 책 평균 노출이 E 와 정확히 같게 한다.
#      취약도가 큰 이름은 노출 0(그 달 제외)까지 가고 작은 이름은 1 에 남는다 — 얇게 펴 바르는
#      선형 순위 규칙과 달리 축소가 **소수 이름에 집중**된다(집중 축소 vs 균등 삭감의 대조).
#   ③ 채널 = 경로 형태가 정한다: λ = q_dur / (q_dur + q_depth). 오래 끄는 침식(λ↑)에서는 시장 대비
#      초과 손실이 개별 종목의 잔차에서 여러 달 쌓이므로 잔차 변동 몫 ovol·sqrt(1 − bcorr²) 을,
#      빠르고 깊은 급락(λ↓)에서는 상관이 올라붙어 시장이 실어 나르는 몫 ovol·|bcorr| 을 취약도로
#      쓴다. 같은 예산이라도 경로 형태가 다르면 깎이는 이름이 다르다.
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 ∈ [0,1]. 표적이 cross_sectional 이므로 횡단면 차등이
#   서지 않는 달(보유 1종 · 취약도 전부 동률)은 스칼라로 때우지 않고 무개입한다.
#   H = 확장창(t 행까지 · 미래 행 없음). t 행이 미실현인 익월 수익 열은 읽지 않는다.
#   행 s 의 경로값은 s 행까지의 정보로만 만든다(누적 최대 · 구간 누적 최소). 외부 데이터 없음.
#   임의 상수 금지 — 문턱은 전부 자기 이력의 경험분위, 종목 차등은 그 달 보유 안의 횡단면 순위에서
#   나온다. 추정 불가 · 표본 부족(과거 수중 달 < ctx$n_min)이면 e <- 1(무개입). 오류를 던지지 않는다.
#==============================================================================

overlay_expo_b5gen_uw_path_split_1 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)
  n_h <- nrow(hold)
  if (n_h < 2L) return(1)                          # 한 종목만 있으면 횡단면이 없다

  nmin <- suppressWarnings(as.integer(ctx$n_min))
  if (length(nmin) != 1L || !is.finite(nmin) || nmin < 12L) nmin <- 24L

  tt <- suppressWarnings(as.integer(t))
  if (length(tt) != 1L || !is.finite(tt)) return(1)
  tt <- min(tt, nrow(H))
  if (tt <= nmin) return(1)                        # 경험분위를 세울 이력이 없다

  # ── ① 벤치 수중 경로 — 행 s 의 값은 s 행까지의 정보로만(누적 최대 · 구간 누적 최소)
  nav <- suppressWarnings(as.numeric(H$nav))[seq_len(tt)]
  if (!all(is.finite(nav)) || any(nav <= 0)) return(1)
  peak  <- cummax(nav)
  below <- nav < peak                              # 고점 아래인가 — 구조적 경계(리터럴 없음)
  if (!isTRUE(below[tt])) return(1)                # 고점 = 무개입
  depth <- 1 - nav / peak
  seg   <- cumsum(!below)                          # 고점 행마다 새 수중 구간
  dur   <- stats::ave(as.numeric(below), seg, FUN = cumsum)
  smin  <- stats::ave(nav, seg, FUN = cummin)
  rec   <- nav / smin - 1                          # 현 구간 바닥 대비 반등(신저점 = 0)
  rec[!below] <- 0
  trend <- -suppressWarnings(as.numeric(H$r252))[seq_len(tt)]   # 12개월 추세의 음 — 클수록 침식

  # ── ② 희소도 — 엄격 과거(1..t−1)의 수중 달들 안에서의 경험분위 ∈ [0,1)
  past <- seq_len(tt - 1L)
  pu   <- past[below[past]]
  if (length(pu) < nmin) return(1)                 # 과거 수중 달이 모자라면 분위가 아니다
  .q <- function(x) {
    p <- x[pu]; p <- p[is.finite(p)]
    if (length(p) < nmin || !is.finite(x[tt])) return(NA_real_)
    mean(p < x[tt])
  }
  q_depth <- .q(depth); q_dur <- .q(dur); q_trend <- .q(trend); q_rec <- .q(rec)
  if (anyNA(c(q_depth, q_dur, q_trend, q_rec))) return(1)

  # ── ③ 침식 강도(곱) → 책 평균 노출 예산 E · 축소 예산 R
  s <- q_depth * q_dur * q_trend * (1 - q_rec)
  E <- max(0, min(1, 1 - s))
  R <- 1 - E
  if (R <= 0) return(1)                            # 예산이 없으면 배분할 것도 없다

  # ── ④ 경로 형태 → 채널 배합 λ (오래 끄는 침식 ↑ · 빠르고 깊은 급락 ↓)
  lam <- if ((q_dur + q_depth) > 0) q_dur / (q_dur + q_depth) else 0.5
  lam <- max(0, min(1, lam))

  # ── ⑤ 종목 취약도 — 자체변동을 시장이 실어 나르는 몫과 잔차 몫으로 가른다(관측수 신뢰도 축소)
  ov <- suppressWarnings(as.numeric(hold$ovol))
  bc <- suppressWarnings(as.numeric(hold$bcorr))
  no <- suppressWarnings(as.numeric(hold$n_obs))
  if (length(ov) != n_h || length(bc) != n_h) return(1)
  bc <- pmax(-1, pmin(1, bc))                      # 상관의 정의역 — 추정 잡음으로 벗어난 값만 되돌린다
  a_res <- ov * sqrt(pmax(0, 1 - bc * bc))         # 잔차 변동 몫 — 침식 채널
  a_mkt <- ov * abs(bc)                            # 시장 전달 몫 — 급락 채널
  if (length(no) == n_h) {
    n_med <- suppressWarnings(stats::median(no[is.finite(no)]))
    kw <- if (is.finite(n_med) && n_med > 0) no / (no + n_med) else rep(NA_real_, n_h)
    kw[!is.finite(kw)] <- 1                        # 표본수 미상 = 축소 근거도 없으니 원값 유지
    shrink <- function(v) {
      m <- suppressWarnings(stats::median(v[is.finite(v)]))
      if (!is.finite(m)) return(v)
      m + kw * (v - m)
    }
    a_res <- shrink(a_res); a_mkt <- shrink(a_mkt)
  }
  rk <- function(v) {                              # 보유 안 횡단면 순위 ∈ (0,1) · 추정 없는 종목은 중앙
    r <- rep(0.5, length(v)); okv <- is.finite(v)
    if (sum(okv) >= 2L) r[okv] <- (rank(v[okv], ties.method = "average") - 0.5) / sum(okv)
    r
  }
  v <- lam * rk(a_res) + (1 - lam) * rk(a_mkt)
  sd_v <- suppressWarnings(stats::sd(v))
  if (!all(is.finite(v)) || !is.finite(sd_v) || sd_v <= 0) return(1)   # 차등 미성립 = 무개입

  # ── ⑥ 물채우기 — 축소 red_i = min(1, μ·k_i), k = v / mean(v), 책 평균 축소가 R 과 같도록 μ 를 푼다.
  #   상한(전량 축소)에 닿은 이름은 고정하고 나머지에 남은 예산을 다시 나눈다(집중 축소).
  k   <- v / mean(v)
  cap <- rep(FALSE, n_h)
  mu  <- 0
  repeat {
    free <- !cap
    den  <- sum(k[free]) / n_h
    need <- R - sum(cap) / n_h
    mu   <- if (den > 0) need / den else 0
    over <- free & (mu * k > 1)
    if (!any(over)) break
    cap  <- cap | over
  }
  red <- pmin(1, pmax(0, mu * k)); red[cap] <- 1

  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - red)))
}
