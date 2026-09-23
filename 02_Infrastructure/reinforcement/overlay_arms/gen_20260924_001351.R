#==============================================================================
# gen_20260924_001351 — 산포 혁신 브레이크 (잠재 AR(1)+측정잡음 구조 추정 · 2026-09-24)
#                       (표적 칸: action = scalar_exposure · state = dispersion)
#
# ★기전
#   횡단면분산은 그 시점 횡단면의 **평균 고유분산**을 재는 추정량이다. 25종 롱온리 책의
#   분산은 공통성분 + 평균고유분산/유효종목수 로 갈리므로, 산포는 종목 수로 지울 수 없는
#   몫에 직접 실린다. 그런데 이 칸이 지금까지 읽은 것은 산포의 **수준**(과 시장변동 대비 비)이고,
#   수준은 그 달의 책을 세울 때 쓴 후행 추정이 이미 대부분 담고 있다. 남아 있는 축은
#   수준에서 예측된 몫을 뺀 나머지 — **혁신(news)** 이다. 혁신은 지연 수준과 직교하도록
#   구성되므로 수준 축과 겹치는 정보를 스스로 버린다.
#   혁신이 위로 뜬 달은 책을 세울 때 쓴 위험 추정이 그만큼 낡은 달이다. 이 arm 은 그 낡음만큼
#   총노출을 줄인다 — 수익 방향에 대한 주장이 아니라 "위험 추정이 방금 낡았으니 갱신될 때까지
#   크기를 줄인다"는 위험 서술이다. 그래서 상방을 맞히는 시점 주장을 지지 않는다.
#
# ★왜 구조 추정이 필요한가
#   H$xs 는 신호일 **하루**의 횡단면 표준편차다 — 관측 = 잠재 산포 + 표본잡음. 차분이나 단순
#   잔차를 혁신으로 쓰면 대부분이 표본잡음이 되어 이 축은 잡음에 반응하는 팔이 된다.
#   잠재 AR(1) + 백색잡음 모형은 자기상관 둘로 식별된다: rho1 = lam*phi · rho2 = lam*phi^2 이므로
#     phi = rho2/rho1  (잠재 지속성)        lam = rho1^2/rho2  (신호몫 = 관측분산 중 잠재의 몫)
#   잡음이 섞이면 1차 자기상관이 더 크게 깎여 ACF 가 순수 AR(1)보다 늦게 감쇠하는데, 그 간격이
#   정확히 lam 을 식별한다. phi·lam 이 정상상태 칼만 이득 K 를 정하고, K 가 "관측 하나를 얼마나
#   믿고 잠재 상태를 갱신하는가" = 오늘 읽은 값 중 news 로 셀 몫을 정한다.
#   감쇠하는 양의 ACF 가 아니면 모형이 식별되지 않으므로 관측 AR(1) 예측으로 떨어진다(K = 1 —
#   관측을 액면 그대로). 폴백에서도 산출은 상수가 되지 않는다.
#
# ★계약
#   반환 = 스칼라 e ∈ [0,1] (표적이 scalar_exposure 이므로 종목별 표를 내지 않는다).
#   H = 확장창(미래 행 없음) · t 행이 미실현인 익월 수익 열은 읽지 않는다.
#   임의 상수 금지 — 개입 시작점은 혁신의 확장창 경험분포 중앙이고, 지속성·신호몫·칼만 이득은
#   전부 그 시점까지의 자기상관에서 나오며, 강도 할인은 그 달 보유의 횡단면 중앙값에서 온다.
#   추정 불가·표본 부족·보유 없음이면 e <- 1(무개입). 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20260924_001351 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)

  nmin <- suppressWarnings(as.integer(ctx$n_min))
  if (!is.finite(nmin) || nmin < 12L) nmin <- 24L

  tt <- suppressWarnings(as.integer(t))
  if (!is.finite(tt)) return(1)
  tt <- min(tt, nrow(H))
  if (tt < nmin) return(1)

  # ── ① 산포 계열 — 로그로 옮겨 비율 축에 놓는다(비양수·결측은 로그에서 NA 로 떨어진다)
  x <- suppressWarnings(log(as.numeric(H$xs)))[seq_len(tt)]
  x[!is.finite(x)] <- NA_real_
  if (!is.finite(x[tt])) return(1)              # 오늘 상태를 못 읽으면 개입하지 않는다
  okx <- is.finite(x)
  if (sum(okx) < nmin) return(1)

  mu <- mean(x[okx])
  vv <- suppressWarnings(stats::var(x[okx]))
  if (!is.finite(vv) || vv <= 0) return(1)      # 이력 분산 0 = 이 축엔 정보가 없다
  z <- x - mu                                   # 평균편차. 결측 달은 NA 로 남는다

  # ── ② 자기상관 둘 — 식별식이 쓰는 전부. 완전쌍만 세므로 결측 달은 쌍에서 빠진다.
  ac <- function(k) {
    a <- z[seq_len(tt - k)]; b <- z[(1L + k):tt]
    p <- is.finite(a) & is.finite(b)
    if (sum(p) < nmin) return(NA_real_)
    sum(a[p] * b[p]) / (sum(p) * vv)
  }
  r1 <- ac(1L); r2 <- ac(2L)
  if (!is.finite(r1)) return(1)

  tiny <- .Machine$double.eps^0.25
  phi <- max(0, min(1 - tiny, r1))              # 폴백 = 관측 AR(1) 예측
  lam <- 1                                      #   그 경우 신호몫 가정 없음(관측을 액면 그대로)
  if (is.finite(r2) && r1 > 0 && r2 > 0 && r2 < r1) {   # 감쇠하는 양의 ACF 에서만 식별된다
    ph <- r2 / r1                               # 잠재 지속성 — r2 < r1 이 (0,1) 을 보장한다
    lm <- (r1 * r1) / r2                        # 신호몫. 상한에 걸리면 표본잡음이 안 잡힌 것(순수 AR(1))
    if (is.finite(ph) && is.finite(lm)) {
      phi <- max(0, min(1 - tiny, ph))
      lam <- max(0, min(1, lm))
    }
  }

  # ── ③ 정상상태 칼만 이득 K — 관측 하나가 잠재 산포를 얼마나 갱신하는가.
  #   Q = 잠재 충격 분산 · R = 표본잡음 분산 · P = 갱신 후 오차분산의 고정점.
  Q <- (1 - phi * phi) * lam * vv
  R <- (1 - lam) * vv
  P <- lam * vv
  for (it in seq_len(200L)) {
    Pm  <- phi * phi * P + Q
    den <- Pm + R
    Pn  <- if (is.finite(den) && den > 0) Pm * R / den else 0
    if (!is.finite(Pn)) { Pn <- 0; break }
    if (abs(Pn - P) <= tiny * max(vv, abs(P))) { P <- Pn; break }
    P <- Pn
  }
  Pm  <- phi * phi * P + Q
  den <- Pm + R
  K <- if (is.finite(den) && den > 0) Pm / den else 1
  if (!is.finite(K)) K <- 1
  K <- max(0, min(1, K))

  # ── ④ 혁신 계열 — 관측에서 '과거만으로 이미 알던 몫'을 뺀 나머지.
  #   초기값은 무조건평균(z 기준 0). 첫 몇 달은 사전분산이 커 혁신이 과대분산이지만 확장창이
  #   쌓이면 정상상태로 수렴한다 — 필터 워밍업이지 절벽이 아니다.
  xi <- 0; u <- rep(NA_real_, tt)
  for (s in seq_len(tt)) {
    pr <- phi * xi                              # 과거만으로 세운 오늘의 기대 편차
    if (is.finite(z[s])) { u[s] <- z[s] - pr; xi <- pr + K * u[s] } else xi <- pr
  }
  un <- u[tt]
  uh <- u[is.finite(u)]
  if (!is.finite(un) || length(uh) < nmin) return(1)

  # ── ⑤ 개입 강도 g — 혁신이 자기 이력 경험분포 중앙 **위**인 만큼만
  q <- stats::ecdf(uh)(un)                      # 0~1. 중앙 = 개입 시작점(데이터가 정한다, 상수 문턱 아님)
  g <- (q - 0.5) / 0.5
  g <- max(0, min(1, g))
  if (g <= 0) return(1)

  # ── ⑥ 책이 산포 축에 실린 몫 iota — 고유분산 몫 = 1 − 상관제곱의 횡단면 중앙값.
  #   산포가 책에 닿는 통로가 고유성분이므로, 거의 전부가 공통 노출인 책은 산포 놀람에 반응할
  #   이유가 없다. 이미 [0,1] 무차원이라 문턱을 세울 일이 없다.
  bc <- suppressWarnings(as.numeric(hold$bcorr))
  bc <- pmax(-1, pmin(1, bc))                   # 상관의 정의역 — 추정 잡음으로 벗어난 값만 되돌린다
  md <- suppressWarnings(stats::median((bc * bc)[is.finite(bc)]))
  iota <- if (is.finite(md)) max(0, min(1, 1 - md)) else 1   # 못 재는 달은 할인 없음

  # ── ⑦ 총노출 = 1 − g·iota
  max(0, min(1, 1 - g * iota))
}
