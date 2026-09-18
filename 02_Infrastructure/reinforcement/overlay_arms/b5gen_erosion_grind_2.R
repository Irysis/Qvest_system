#==============================================================================
# b5gen_erosion_grind_2 — 침식 형태(지속 × 완만) 상태 × 잔차 변동 몫 종목 틸트
#                         (표적 칸: action = cross_sectional · state = multivar)
#
# ★기전 (사전 선언 — 특정 시기를 보고 만든 규칙이 아니다)
#   깊이 계열(dd 분위)은 급락에서 즉시 극단 분위에 닿고, 지속성 계열(추세 아래 연속 개월수)은
#   국면의 길이만 본다. 둘 다 "얼마나 빠르게 잃고 있는가" 는 읽지 않는다. 그런데 같은 깊이라도
#   몇 달 만에 무너지는 급락과 여러 해에 걸쳐 조금씩 밀리는 침식은 손실을 나르는 종목이 다르다 —
#   급락은 상관이 한꺼번에 올라붙어 시장과 함께 가는 몫이 손실이고, 침식은 시장 대비 초과 손실이
#   개별 종목의 잔차 몫에서 여러 달에 걸쳐 쌓인다.
#   이 arm 은 상태를 두 축의 곱으로 읽는다:
#     ① 지속성  = 후행 3·6·12개월 하락월 비율을 각각 자기 이력의 확장창 백분위로 환산해 평균
#     ② 완만함  = 1 − (rv60 백분위가 자기 이력 중앙 위인 만큼) — 변동성 arm 이 개입할 만큼
#                 변동성이 극단으로 갈수록 이 arm 은 스스로 물러선다(급락은 이 arm 의 몫이 아니다).
#   기존 다변량 arm 은 변동성을 스트레스 방향으로 **더한다** — 여기서는 부호가 반대다. 이 부호가
#   스택 의미(층별 노출의 곱)에서 중요하다: 변동성 층이 켜지는 달에 이 층은 꺼지므로 두 층이
#   같은 달에 겹쳐 이중 축소로 가지 않는다(소비 구간의 분할).
#   개입 강도 g 는 곱 점수의 자기 이력 경험분포 중앙 위에서만 세운다(상수 문턱 없음).
#   종목 차등은 그 달 보유의 잔차 변동 몫 ovol·sqrt(1−bcorr²) 횡단면 순위에 비례시킨다 —
#   침식의 초과 손실이 체계 몫이 아니라 잔차에서 쌓인다는 가설을 종목축에서 직접 건다
#   (같은 지속성 상태에 시장베타 순위를 쓰는 arm 과 축이 갈리는 대조쌍).
#   상승월이 쌓이면 ① 이 3~6개월 안에 내려가 회복 초입에서 스스로 풀린다 — 고점 회복까지
#   잠그는 수중 기간 계열과 다르다.
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 ∈ [0,1]. 표적이 cross_sectional 이므로 횡단면
#   차등이 서지 않는 달(보유 1종·특성 전부 결측)은 스칼라로 때우지 않고 무개입한다.
#   H = 확장창(t 행까지 · 미래 행 없음) · t 행이 미실현인 익월 수익 열은 읽지 않는다.
#   행 s 의 상태값은 s 행까지의 정보로만 만든다(과거 행도 그 시점 PIT 값) — 점수 이력이 확장창이다.
#   임의 상수 금지 — 문턱은 전부 자기 이력 경험분포에서, 종목 차등은 그 달 보유 안의 횡단면
#   순위에서 나온다. 추정 불가·표본 부족이면 e <- 1(무개입). 오류를 던지지 않는다.
#   외부 데이터 없음(H 와 ctx$hold 만).
#==============================================================================

overlay_expo_b5gen_erosion_grind_2 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)
  n_h <- nrow(hold)
  if (n_h < 2L) return(1)                      # 한 종목만 있으면 횡단면이 없다

  nmin <- suppressWarnings(as.integer(ctx$n_min))
  if (length(nmin) != 1L || !is.finite(nmin) || nmin < 12L) nmin <- 24L

  tt <- suppressWarnings(as.integer(t))
  if (length(tt) != 1L || !is.finite(tt)) return(1)
  tt <- min(tt, nrow(H))
  if (tt < nmin) return(1)                     # 경험분포를 세울 이력이 없다

  # ── ① 시장 월수익 — 벤치 nav 의 로그 차분. t 행까지의 값은 신호일에 전부 실현돼 있다.
  nav  <- suppressWarnings(as.numeric(H$nav))[seq_len(tt)]
  lnav <- suppressWarnings(log(nav))
  lnav[!is.finite(lnav)] <- NA_real_
  r   <- c(NA_real_, diff(lnav))
  okr <- is.finite(r)
  if (sum(okr) < nmin) return(1)
  dn  <- as.numeric(okr & r < 0)               # 하락월 표시 — 부호 경계(상수 문턱이 아니다)

  # ── ② 확장창 백분위 — 행 s 의 값이 s 행까지의 유효 이력 안에서 어디인가 ∈ (0,1]
  exp_pct <- function(x) {
    n <- length(x); p <- rep(NA_real_, n)
    for (s in seq_len(n)) {
      if (!is.finite(x[s])) next
      past <- x[seq_len(s)]; past <- past[is.finite(past)]
      if (length(past) < 2L) next              # 비교 대상이 없으면 백분위가 아니다
      p[s] <- mean(past <= x[s])
    }
    p
  }

  # ── ③ 지속성 — 후행 h개월 하락월 비율 (h = 3·6·12) → 각각 백분위 → 평균
  cdn <- c(0, cumsum(dn)); cok <- c(0, cumsum(as.numeric(okr)))
  idx <- seq_len(tt)
  share_h <- function(h) {
    j <- pmax(0L, idx - h)
    d <- cok[idx + 1L] - cok[j + 1L]           # 창 안 유효 개월수
    s <- (cdn[idx + 1L] - cdn[j + 1L]) / d
    s[!is.finite(s) | d < h] <- NA_real_       # 창이 덜 찬 행은 없는 값
    s
  }
  hs <- c(3L, 6L, 12L)
  P  <- matrix(NA_real_, nrow = tt, ncol = length(hs))
  for (k in seq_along(hs)) P[, k] <- exp_pct(share_h(hs[k]))
  pers <- rowMeans(P, na.rm = TRUE)
  pers[!is.finite(pers)] <- NA_real_

  # ── ④ 완만함 — 변동성 백분위가 자기 이력 중앙 위인 만큼 물러선다(변동성 층에 소비 구간을 넘긴다)
  rv <- suppressWarnings(as.numeric(H$rv60))[seq_len(tt)]
  rv[!is.finite(rv)] <- NA_real_
  pv <- exp_pct(rv)
  gv <- pmax(0, pmin(1, (pv - 0.5) / 0.5))
  slow <- 1 - gv

  # ── ⑤ 침식 점수(곱) → 개입 강도 g — 점수 자기 이력의 경험분포 중앙 위에서만
  sc   <- pers * slow
  ok_s <- is.finite(sc)
  if (!isTRUE(ok_s[tt]) || sum(ok_s) < nmin) return(1)
  q <- stats::ecdf(sc[ok_s])(sc[tt])
  g <- (q - 0.5) / 0.5                         # 중앙 = 개입 시작점(데이터가 정한다)
  g <- max(0, min(1, g))
  if (g <= 0) return(1)

  # ── ⑥ 종목 차등 — 잔차 변동 몫 ovol·sqrt(1−bcorr²) 의 보유 안 횡단면 순위.
  #   표본이 짧은 종목의 추정치는 관측수 신뢰도로 보유 중앙 쪽에 축소한다(축소계수도 그 달 보유에서).
  ov <- suppressWarnings(as.numeric(hold$ovol))
  bc <- suppressWarnings(as.numeric(hold$bcorr))
  no <- suppressWarnings(as.numeric(hold$n_obs))
  if (length(ov) != n_h || length(bc) != n_h) return(1)
  bc <- pmax(-1, pmin(1, bc))                  # 상관의 정의역 — 추정 잡음으로 벗어난 값만 되돌린다
  a_idio <- ov * sqrt(pmax(0, 1 - bc * bc))
  if (length(no) == n_h) {
    n_med <- suppressWarnings(stats::median(no[is.finite(no)]))
    kw <- if (is.finite(n_med) && n_med > 0) no / (no + n_med) else rep(NA_real_, n_h)
    kw[!is.finite(kw)] <- 1                    # 표본수 미상 = 축소 근거도 없으니 원값 유지
    m_a <- suppressWarnings(stats::median(a_idio[is.finite(a_idio)]))
    if (is.finite(m_a)) a_idio <- m_a + kw * (a_idio - m_a)
  }
  okv <- is.finite(a_idio)
  if (sum(okv) < 2L) return(1)                 # 순위를 매길 수 없으면 무개입
  rk <- rep(0.5, n_h)                          # 추정 없는 종목은 중앙 — 유리·불리 어느 쪽도 아니다
  rk[okv] <- (rank(a_idio[okv], ties.method = "average") - 0.5) / sum(okv)
  sd_r <- suppressWarnings(stats::sd(rk))
  if (!is.finite(sd_r) || sd_r <= 0) return(1) # 차등 미성립 = 무개입

  # ── ⑦ 노출 = 1 − g·rk (횡단면 평균 1 − g/2 — 스칼라판보다 덜 깎고 몫은 잔차 축에 몰린다)
  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - g * rk)))
}
