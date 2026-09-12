#==============================================================================
# gen_20260913_000156 — 산포/시장변동 격차 브레이크 (내재 평균상관 축)
#                       (표적 칸: action = scalar_exposure · state = dispersion)
#
# ★기전
#   산포를 보는 기존 arm 은 횡단면 축이고(csd_idio_tilt), 총노출 축의 스칼라 arm 은 전부
#   변동성·낙폭의 **수준**을 본다. 미측정으로 남은 건 산포와 시장변동의 **비**다.
#   등가중 책에서 두 양은 같은 공통성분을 반대편에서 재는 항등식으로 묶인다 —
#   시장분산 ≈ 평균상관 × 평균 종목분산, 횡단면분산 ≈ (1 − 평균상관) × 평균 종목분산.
#   따라서 log(산포) − log(시장변동) 은 단조 변환 하나 차이로 그 시점 **내재 평균상관**이고,
#   두 계열이 같은 배수로 함께 커지면 이 격차는 움직이지 않는다 — 변동성 수준 축과 겹치지 않는
#   정보만 남는다. 격차가 자기 이력 중앙 아래로 내려가는 달은 종목들이 한 덩어리로 움직이는
#   달이다: ①25종 책의 분산효과가 사라져 같은 명목노출이 더 큰 포트폴리오 변동을 나르고
#   ②종목 선택이 벌 수 있는 횡단면 폭 자체가 줄어든다. 두 읽기가 같은 방향을 가리키므로
#   이 arm 은 그 달의 총노출을 격차 분위만큼 깎는다.
#   단위계(일별 산포 vs 연율 변동성)는 로그 격차의 **이력 경험분포 분위**에서 상쇄되므로
#   환산 상수를 가정하지 않는다 — 순서만 쓰면 되고, 순서는 단위에 불변이다.
#
# ★계약
#   반환 = 스칼라 e ∈ [0,1] (표적이 scalar_exposure 이므로 종목별 표를 내지 않는다).
#   H = 확장창(미래 행 없음) · t 행이 미실현인 익월 수익 열은 읽지 않는다.
#   임의 상수 금지 — 개입 시작점은 격차의 확장창 경험분포 중앙이고, 평활 관측창은 과거쌍
#   1개월 앞 적합에서, 책의 공통성분 몫은 그 달 보유의 횡단면 중앙값에서 나온다.
#   추정 불가·표본 부족이면 e <- 1(무개입). 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20260913_000156 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)

  nmin <- suppressWarnings(as.integer(ctx$n_min))
  if (!is.finite(nmin) || nmin < 12L) nmin <- 24L

  tt <- suppressWarnings(as.integer(t))
  if (!is.finite(tt)) return(1)
  tt <- min(tt, nrow(H))
  if (tt < nmin) return(1)

  # ── ① 산포 계열 — 신호일 하루의 횡단면 표준편차는 표본이 하루라 잡음이 수준을 덮는다.
  #   로그로 옮겨 비율 축으로 놓는다(비양수·결측은 로그에서 그대로 떨어진다).
  lx <- suppressWarnings(log(as.numeric(H$xs)))[seq_len(tt)]
  lx[!is.finite(lx)] <- NA_real_
  okx <- is.finite(lx)
  if (sum(okx) < nmin) return(1)

  cs <- c(0, cumsum(ifelse(okx, lx, 0)))
  cn <- c(0, cumsum(as.numeric(okx)))
  trail <- function(w) {                       # 후행 w개월 평균(결측 제외) — 확장창 안에서만
    i <- seq_len(tt); j <- pmax(0L, i - w)
    d <- cn[i + 1L] - cn[j + 1L]
    m <- (cs[i + 1L] - cs[j + 1L]) / d
    m[d <= 0] <- NA_real_
    m
  }

  # ── ② 평활 길이 — 1개월 앞 산포를 가장 잘 맞힌 관측창(결과가 이미 실현된 과거쌍만).
  #   길이를 상수로 박지 않고 그 시점까지의 적합으로 고른다.
  ws <- seq_len(6L)
  sm <- vector("list", length(ws)); best <- NA_integer_; berr <- Inf
  for (w in ws) {
    m <- trail(w); sm[[w]] <- m
    err <- suppressWarnings(mean((m[-tt] - lx[-1L])^2, na.rm = TRUE))
    if (is.finite(err) && err < berr) { berr <- err; best <- w }
  }
  xhat <- if (is.na(best)) lx else sm[[best]]
  if (!is.finite(xhat[tt])) return(1)

  # ── ③ 격차 분위 — 참조 변동성 두 관측창에서 각각 읽고 평균한다.
  #   격차 계열의 이력 분산이 0 이면 두 원천이 서로 비례한다는 뜻이라 이 축엔 정보가 없다.
  refs <- list(as.numeric(H$rv20), as.numeric(H$rv60))
  qs <- vapply(refs, function(v) {
    lv <- suppressWarnings(log(v))[seq_len(tt)]
    lv[!is.finite(lv)] <- NA_real_
    d  <- xhat - lv
    dh <- d[is.finite(d)]
    if (!is.finite(d[tt]) || length(dh) < nmin) return(NA_real_)
    s <- suppressWarnings(stats::sd(dh))
    if (!is.finite(s) || s <= 0) return(NA_real_)
    stats::ecdf(dh)(d[tt])
  }, numeric(1))
  okq <- is.finite(qs)
  if (!any(okq)) return(1)
  qbar <- mean(qs[okq])
  if (!is.finite(qbar)) return(1)

  # ── ④ 개입 강도 g — 격차가 자기 이력 중앙 **아래**인 만큼만(공통성분이 산포를 삼킨 국면)
  g <- (0.5 - qbar) / 0.5                      # 중앙 = 개입 시작점(데이터가 정한다, 상수 문턱 아님)
  g <- max(0, min(1, g))
  if (g <= 0) return(1)

  # ── ⑤ 책이 공통성분에 실린 몫 phi — 보유 상관 제곱(시장이 설명하는 변동 몫)의 횡단면 중앙값.
  #   이미 [0,1] 무차원이라 문턱을 세울 일이 없다. 상관을 못 재는 달은 시장 상태 판독을
  #   할인할 근거도 없으므로 phi <- 1(강도 그대로)로 둔다.
  bc  <- suppressWarnings(as.numeric(hold$bcorr))
  bc  <- pmax(-1, pmin(1, bc))                 # 상관의 정의역 — 추정 잡음으로 벗어난 값만 되돌린다
  phi <- suppressWarnings(stats::median((bc * bc)[is.finite(bc)]))
  if (!is.finite(phi)) phi <- 1
  phi <- max(0, min(1, phi))

  # ── ⑥ 총노출 = 1 − g·phi
  max(0, min(1, 1 - g * phi))
}
