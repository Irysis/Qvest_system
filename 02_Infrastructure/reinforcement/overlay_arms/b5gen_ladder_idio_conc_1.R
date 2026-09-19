#==============================================================================
# b5gen_ladder_idio_conc_1 — 지평 사다리 예산을 잔차 변동 몫에 **집중 배분**하는 종목별 오버레이
#                            (표적 칸: action = cross_sectional · state = trend)
#
# ★기전 (사전 선언 — 특정 시기를 보고 만든 규칙이 아니다)
#   기존 종목별 arm 은 전부 1 − g·순위 로 모든 보유에 얇게 펴 바른다 — 책 평균 노출이 1 − g/2 라
#   같은 상태의 스칼라판(1 − g)과 예산이 다르고, 그래서 "배분이 정보를 나르는가" 와 "덜 깎았는가" 가
#   한 수치에 섞인다. 이 arm 은 예산을 먼저 고정한다: 책 평균 노출 E = 1 − g 를 같은 상태의 스칼라
#   게이트(trend_ladder_gate)와 **정확히 같게** 두고, 총 축소량 g·n 을 종목 취약도에 비례해 배분하되
#   한 이름의 축소가 1(전량)을 넘으면 넘친 몫을 남은 이름에 재배분한다(물채우기). 취약도 큰 이름은
#   그 달 노출 0 까지 가고 작은 이름은 1 에 남는다 — 균등 삭감의 반대편 끝이다.
#   취약도 축 = 잔차 변동 몫 ovol·sqrt(1 − bcorr²). 이 계보에서 시장 적재 축(베타·하방베타·상관)은
#   선정 축에서도 배분 축에서도 정보를 못 냈고, 침식의 시장 대비 초과 손실은 개별 이름의 잔차에서
#   여러 달 쌓인다는 가설이 남았다. 표본 짧은 이름의 추정치는 관측수 신뢰도 n/(n + 보유 안 관측수
#   중앙값)로 보유 중앙에 축소한다(축소계수도 그 달 보유에서).
#   상태는 trend_ladder_gate 와 동일한 지평 사다리(1·3·6·12개월 후행수익의 자기 이력 백분위 평균)다 —
#   두 arm 의 차이가 곧 배분의 값이고, 횡단면 순열 반증이 그 값을 무작위 배분과 가른다.
#   반증 조건: 잔차 축이 이 책에서 손실 이름을 못 고르면 횡단면 순열과 구분되지 않고, 집중 배분은
#   균등보다 종목 집중 위험만 키운다.
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 ∈ [0,1]. 표적이 cross_sectional 이므로 개입하는 달은
#   표를 낸다(취약도를 못 읽는 달은 예산을 지키기 위해 균등값 표). 개입 없는 달은 1.
#   H = 확장창(t 행까지 · 미래 행 없음) · t 행이 미실현인 익월 수익 열은 읽지 않는다.
#   ctx$hold = 그 달 보유의 확장창 상태(beta · dbeta · ovol · bcorr · n_obs). 임의 상수 금지 —
#   개입 시작점은 각 지평 수익의 자기 이력 경험분포 중앙, 종목 차등은 그 달 보유 안의 횡단면 순위,
#   축소계수는 보유 안 관측수 중앙값. 추정 불가·표본 부족이면 e <- 1(무개입). 오류를 던지지 않는다.
#   외부 데이터 없음.
#==============================================================================

overlay_expo_b5gen_ladder_idio_conc_1 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)
  n_h <- nrow(hold)
  if (n_h < 2L) return(1)                      # 한 종목만 있으면 횡단면이 없다

  nmin <- suppressWarnings(as.integer(ctx$n_min))
  if (length(nmin) != 1L || !is.finite(nmin) || nmin < 12L) nmin <- 24L

  tt <- suppressWarnings(as.integer(t))
  if (length(tt) != 1L || !is.finite(tt)) return(1)
  tt <- min(tt, nrow(H))
  if (tt < 13L) return(1)

  # ── ① 상태 = 지평 사다리 (스칼라 짝 trend_ladder_gate 와 같은 식 — 예산이 같아야 배분만 갈린다)
  nv <- suppressWarnings(as.numeric(H$nav))[seq_len(tt)]
  nv[!is.finite(nv) | nv <= 0] <- NA_real_
  if (!is.finite(nv[tt])) return(1)
  hz <- c(1L, 3L, 6L, 12L)                     # 관측 창(월)이지 문턱이 아니다
  qv <- numeric(0)
  for (k in hz) {
    if (tt <= k + nmin) next
    tr   <- c(rep(NA_real_, k), nv[(k + 1L):tt] / nv[seq_len(tt - k)] - 1)
    now  <- tr[tt]
    hist <- tr[is.finite(tr)]
    if (!is.finite(now) || length(hist) < nmin) next
    qv <- c(qv, stats::ecdf(hist)(now))
  }
  if (length(qv) < 2L) return(1)
  qbar <- mean(qv)
  if (!is.finite(qbar)) return(1)
  g <- (0.5 - qbar) / 0.5
  g <- max(0, min(1, g))
  if (g <= 0) return(1)                        # 추세가 자기 이력 중앙 위 = 무개입

  # ── ② 취약도 — 잔차 변동 몫 ovol·sqrt(1−bcorr²), 관측수 신뢰도로 보유 중앙에 축소 → 보유 안 순위
  ov <- suppressWarnings(as.numeric(hold$ovol))
  bc <- suppressWarnings(as.numeric(hold$bcorr))
  no <- suppressWarnings(as.numeric(hold$n_obs))
  rk <- rep(0.5, n_h)                          # 추정 없는 이름은 중앙 — 유리·불리 어느 쪽도 아니다
  if (length(ov) == n_h && length(bc) == n_h) {
    bc <- pmax(-1, pmin(1, bc))                # 상관의 정의역 — 추정 잡음으로 벗어난 값만 되돌린다
    a_idio <- ov * sqrt(pmax(0, 1 - bc * bc))
    if (length(no) == n_h) {
      n_med <- suppressWarnings(stats::median(no[is.finite(no)]))
      kw <- if (is.finite(n_med) && n_med > 0) no / (no + n_med) else rep(NA_real_, n_h)
      kw[!is.finite(kw)] <- 1                  # 표본수 미상 = 축소 근거도 없으니 원값 유지
      m_a <- suppressWarnings(stats::median(a_idio[is.finite(a_idio)]))
      if (is.finite(m_a)) a_idio <- m_a + kw * (a_idio - m_a)
    }
    okv <- is.finite(a_idio)
    if (sum(okv) >= 2L)
      rk[okv] <- (rank(a_idio[okv], ties.method = "average") - 0.5) / sum(okv)
  }

  # ── ③ 물채우기 — 총 축소량 R = g·n 을 순위에 비례 배분, 1 을 넘는 이름은 전량(축소 1)으로 두고
  #   넘친 몫을 남은 이름에 다시 비례 배분한다. 끝나면 책 평균 노출이 정확히 1 − g 다.
  R    <- g * n_h
  red  <- rep(0, n_h)
  free <- rep(TRUE, n_h)
  for (it in seq_len(n_h)) {
    if (!any(free)) break
    left  <- R - sum(red[!free])
    if (left <= 0) { red[free] <- 0; break }
    sfree <- sum(rk[free])
    if (!is.finite(sfree) || sfree <= 0) {     # 순위가 전부 0 이면 비례가 안 선다 — 남은 몫을 균등하게
      red[free] <- min(1, left / sum(free)); break
    }
    prop <- (left / sfree) * rk
    over <- free & prop >= 1
    if (!any(over)) { red[free] <- prop[free]; break }
    red[over] <- 1
    free[over] <- FALSE
  }
  red <- pmax(0, pmin(1, red))

  # ── ④ 노출 = 1 − 축소 (집중 배분: 취약한 이름부터 0 으로 간다)
  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - red)))
}
