#==============================================================================
# gen_20260910_112827 — 추세 지평 불일치 × 종목 하방채널 틸트
#                       (표적 칸: action = cross_sectional · state = trend)
#
# ★기전
#   추세 상태를 보는 기존 arm 은 지평 하나(장기 수익)의 부호·크기를 스칼라 노출로 옮긴다.
#   그러면 추세가 가진 **지평 구조**가 버려진다 — 오래 눌린 시장과 방금 꺾인 시장은
#   같은 강도라도 손실을 실어 나르는 종목이 다른데, 스칼라는 둘을 구별하지 못한다.
#   이 arm 은 nav 하나에서 지평 사다리(1·3·6·12개월) 후행수익을 뽑아 각 지평을
#   자기 이력의 경험분포로 무차원화한 뒤,
#     ① 지평 평균 백분위 → 개입 강도 g (추세가 자기 이력 중앙 아래일 때만 개입)
#     ② 장기 백분위 − 단기 백분위 → 꺾임 정도 λ (장기는 강한데 단기만 무너진 국면)
#   로 갈라 쓴다. λ 는 강도가 아니라 **종목축 배합**을 정한다.
#   지속 하락(λ↓)에서는 여러 달에 걸쳐 시장과 실제로 함께 내려가는 몫이 손실을 만들므로
#   하방베타 × 시장상관을 쓰고(상관이 낮은 큰 하방베타는 추정 잡음 쪽에 가깝다),
#   갓 꺾인 국면(λ↑)에서는 무조건부 베타가 예고한 것보다 더 빠지는 비대칭 초과분
#   (하방베타 − 베타)을 쓴다. 같은 g 라도 깎이는 종목이 국면마다 갈린다.
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 ∈ [0,1]. 표적이 cross_sectional 이므로
#   횡단면 차등이 서지 않는 달(보유 1종·특성 전부 결측)은 스칼라로 때우지 않고 무개입한다.
#   H = 확장창(미래 행 없음) · H$fwd 는 t 행이 미실현이라 읽지 않는다.
#   임의 상수 금지 — 개입 시작점은 각 지평 수익의 자기 이력 경험분포 중앙이고,
#   축 배합은 그 시점 지평 백분위 차이에서, 종목 차등은 그 달 보유 안의 횡단면 순위에서 나온다.
#   추정 불가·표본 부족이면 e <- 1(무개입). 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20260910_112827 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)
  n_h <- nrow(hold)
  if (n_h < 2L) return(1)                      # 한 종목만 있으면 횡단면이 없다

  nmin <- suppressWarnings(as.integer(ctx$n_min))
  if (!is.finite(nmin) || nmin < 12L) nmin <- 24L

  tt <- suppressWarnings(as.integer(t))
  if (!is.finite(tt)) return(1)
  tt <- min(tt, nrow(H))
  if (tt < 13L) return(1)

  # ── ① 추세 사다리 — 지평별 후행수익을 nav 한 원천에서 뽑는다(원천을 섞지 않아야 백분위가 비교된다)
  nv <- suppressWarnings(as.numeric(H$nav))[seq_len(tt)]
  nv[!is.finite(nv) | nv <= 0] <- NA_real_
  if (!is.finite(nv[tt])) return(1)            # 지금 달 추세가 결측 = 개입 근거 없음

  hz  <- c(1L, 3L, 6L, 12L)                    # 관측 창(월)이지 문턱이 아니다
  qv  <- numeric(0)
  hzu <- integer(0)
  for (k in hz) {
    if (tt <= k + nmin) next                   # 그 지평의 경험분포를 세울 표본이 없다
    tr   <- c(rep(NA_real_, k), nv[(k + 1L):tt] / nv[seq_len(tt - k)] - 1)
    now  <- tr[tt]
    hist <- tr[is.finite(tr)]
    if (!is.finite(now) || length(hist) < nmin) next
    qv  <- c(qv, stats::ecdf(hist)(now))       # 0~1. 지평마다 자기 이력 안에서의 위치
    hzu <- c(hzu, k)
  }
  if (length(qv) < 2L) return(1)               # 지평 구조가 안 서면 이 arm 의 일이 아니다

  # ── ② 개입 강도 g — 지평 평균 백분위가 자기 이력 중앙 아래일 때만
  qbar <- mean(qv)
  if (!is.finite(qbar)) return(1)
  g <- (0.5 - qbar) / 0.5                      # 중앙 = 개입 시작점(데이터가 정한다, 상수 문턱 아님)
  g <- max(0, min(1, g))
  if (g <= 0) return(1)

  # ── ③ 꺾임 정도 λ — 장기 백분위 − 단기 백분위. 강도가 아니라 종목축 배합을 정한다
  h_mid  <- stats::median(hzu)
  long_i <- hzu > h_mid
  shrt_i <- hzu < h_mid
  if (!any(long_i) || !any(shrt_i)) return(1)
  qL  <- mean(qv[long_i])
  qS  <- mean(qv[shrt_i])
  if (!is.finite(qL) || !is.finite(qS)) return(1)
  lam <- max(0, min(1, qL - qS))               # 장기 강 · 단기 약 = 갓 꺾인 국면

  # ── ④ 종목 특성 — 표본이 짧은 종목의 추정치는 보유 중앙 쪽으로 당긴다(축소계수도 보유에서 나온다)
  b  <- suppressWarnings(as.numeric(hold$beta))
  db <- suppressWarnings(as.numeric(hold$dbeta))
  bc <- suppressWarnings(as.numeric(hold$bcorr))
  no <- suppressWarnings(as.numeric(hold$n_obs))

  n_med <- suppressWarnings(stats::median(no[is.finite(no)]))
  kw <- if (is.finite(n_med) && n_med > 0) no / (no + n_med) else rep(NA_real_, n_h)
  kw[!is.finite(kw)] <- 1                      # 표본수 미상 = 축소 근거도 없으니 원값 유지

  shrink <- function(v) {
    m <- suppressWarnings(stats::median(v[is.finite(v)]))
    if (!is.finite(m)) return(v)
    m + kw * (v - m)
  }
  a_grind <- shrink(db * bc)                   # 지속 하락 채널 = 시장과 실제로 함께 내려가는 하방 민감도
  a_roll  <- shrink(db - b)                    # 꺾임 채널 = 무조건부 베타를 넘는 하방 초과분

  rk <- function(v) {                          # 보유 안 횡단면 순위 ∈ (0,1). 추정 없는 종목은 중앙
    r <- rep(0.5, length(v)); okv <- is.finite(v)
    if (sum(okv) >= 2L) r[okv] <- (rank(v[okv], ties.method = "average") - 0.5) / sum(okv)
    r
  }
  r_mix <- (1 - lam) * rk(a_grind) + lam * rk(a_roll)
  sd_r  <- suppressWarnings(stats::sd(r_mix))
  if (!all(is.finite(r_mix)) || !is.finite(sd_r) || sd_r <= 0) return(1)  # 차등 미성립 = 무개입

  # ── ⑤ 노출 = 1 − g·r_mix (횡단면 평균 1 − g/2 — 스칼라판보다 덜 깎고 몫은 취약축에 몰린다)
  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - g * r_mix)))
}
