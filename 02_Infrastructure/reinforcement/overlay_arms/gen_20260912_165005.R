#==============================================================================
# gen_20260912_165005 — 변동성 기간구조 × 종목 위험 분해 틸트
#                       (표적 칸: action = cross_sectional · state = vol)
#
# ★기전
#   변동성을 보는 기존 arm 은 전부 총노출 스칼라다 — 변동성이 높으면 전 종목을 같은 비율로
#   깎는다. 그러면 "변동성이 얼마나 높은가" 한 숫자만 쓰이고 "그 변동성이 어디서 오는가" 는
#   버려진다. 같은 고변동 국면이라도 관측창 기간구조가 가파르게 서 있는 달(단기 변동성이
#   장기보다 자기 이력 안에서 훨씬 위 — 충격이 지금 터지는 중)과 평평·역전된 달
#   (높은 수준이 이미 오래 눌러앉은 상태)은 손실을 실어 나르는 종목이 다르다.
#   이 arm 은 그 차이를 **강도가 아니라 종목축**으로 옮긴다:
#     ① 세 관측창(rv20·rv60·rv120) 로그 변동성의 자기 이력 백분위 평균 → 개입 강도 g
#        (자기 이력 중앙 위에서만 개입한다)
#     ② 단기 − 장기 로그 변동성 격차의 자기 이력 백분위 → 기간구조 위치 λ
#   λ 는 종목 위험 분해의 배합을 정한다. 충격 개시(λ↑)에서는 상관이 한꺼번에 올라붙어
#   시장과 함께 움직이는 몫이 손실을 만들므로 ovol·|bcorr|(체계적 몫)로 깎고,
#   고변동이 눌러앉은 국면(λ↓)에서는 개별 종목 사고가 손실을 만들므로
#   ovol·sqrt(1−bcorr²)(잔차 몫)로 깎는다. 같은 g 라도 깎이는 종목이 국면마다 갈린다.
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 ∈ [0,1]. 표적이 cross_sectional 이므로
#   횡단면 차등이 서지 않는 달(보유 1종·특성 전부 결측)은 스칼라로 때우지 않고 무개입한다.
#   H = 확장창(미래 행 없음) · t 행이 미실현인 익월 수익 열은 읽지 않는다.
#   임의 상수 금지 — 개입 시작점은 각 관측창 변동성의 자기 이력 경험분포 중앙이고,
#   축 배합은 그 시점 기간구조 격차의 이력 백분위에서, 종목 차등은 그 달 보유 안의
#   횡단면 순위에서 나온다. 추정 불가·표본 부족이면 e <- 1(무개입). 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20260912_165005 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)
  n_h <- nrow(hold)
  if (n_h < 2L) return(1)                      # 한 종목만 있으면 횡단면이 없다

  nmin <- suppressWarnings(as.integer(ctx$n_min))
  if (!is.finite(nmin) || nmin < 12L) nmin <- 24L

  tt <- suppressWarnings(as.integer(t))
  if (!is.finite(tt)) return(1)
  tt <- min(tt, nrow(H))
  if (tt < nmin) return(1)                     # 경험분포를 세울 이력이 없다

  # ── ① 로그 변동성 — 비양수·결측은 로그에서 그대로 떨어진다(상수 문턱을 세울 일이 없다)
  lvol <- function(col) {
    v  <- suppressWarnings(as.numeric(col))[seq_len(tt)]
    lv <- suppressWarnings(log(v))
    lv[!is.finite(lv)] <- NA_real_
    lv
  }
  l_s <- lvol(H$rv20); l_m <- lvol(H$rv60); l_l <- lvol(H$rv120)

  pct_now <- function(lv) {                    # 지금 값이 자기 이력 안에서 어디인가 ∈ [0,1]
    hist <- lv[is.finite(lv)]
    if (!is.finite(lv[tt]) || length(hist) < nmin) return(NA_real_)
    stats::ecdf(hist)(lv[tt])
  }
  qs <- c(pct_now(l_s), pct_now(l_m), pct_now(l_l))
  ok_q <- is.finite(qs)
  if (sum(ok_q) < 2L) return(1)                # 변동성 상태가 안 서면 이 arm 의 일이 아니다

  # ── ② 개입 강도 g — 관측창 평균 백분위가 자기 이력 중앙 위인 만큼만
  qbar <- mean(qs[ok_q])
  if (!is.finite(qbar)) return(1)
  g <- (qbar - 0.5) / 0.5                      # 중앙 = 개입 시작점(데이터가 정한다, 상수 문턱 아님)
  g <- max(0, min(1, g))
  if (g <= 0) return(1)

  # ── ③ 기간구조 위치 λ — 단기−장기 로그 변동성 격차의 이력 백분위.
  #   격차 계열이 사실상 상수면(원천이 서로 비례) 이 축엔 정보가 없다 → 중립 배합으로 둔다.
  d  <- l_s - l_l
  dh <- d[is.finite(d)]
  lam <- 0.5
  if (is.finite(d[tt]) && length(dh) >= nmin) {
    sdd <- suppressWarnings(stats::sd(dh))
    if (is.finite(sdd) && sdd > 0) lam <- stats::ecdf(dh)(d[tt])
  }
  lam <- max(0, min(1, lam))

  # ── ④ 종목 위험 분해 — 자체 변동성을 시장과 함께 가는 몫 / 남는 몫으로 가른다
  ov <- suppressWarnings(as.numeric(hold$ovol))
  bc <- suppressWarnings(as.numeric(hold$bcorr))
  no <- suppressWarnings(as.numeric(hold$n_obs))
  bc <- pmax(-1, pmin(1, bc))                  # 상관의 정의역 — 추정 잡음으로 벗어난 값만 되돌린다

  a_sys  <- ov * abs(bc)                       # 충격 개시에서 손실을 나르는 체계적 몫
  a_idio <- ov * sqrt(pmax(0, 1 - bc * bc))    # 고변동이 눌러앉은 국면의 잔차 몫

  # 표본이 짧은 종목의 추정치는 보유 중앙 쪽으로 당긴다(축소계수도 그 달 보유에서 나온다)
  n_med <- suppressWarnings(stats::median(no[is.finite(no)]))
  kw <- if (is.finite(n_med) && n_med > 0) no / (no + n_med) else rep(NA_real_, n_h)
  kw[!is.finite(kw)] <- 1                      # 표본수 미상 = 축소 근거도 없으니 원값 유지

  shrink <- function(v) {
    m <- suppressWarnings(stats::median(v[is.finite(v)]))
    if (!is.finite(m)) return(v)
    m + kw * (v - m)
  }
  rk <- function(v) {                          # 보유 안 횡단면 순위 ∈ (0,1). 추정 없는 종목은 중앙
    r <- rep(0.5, length(v)); okv <- is.finite(v)
    if (sum(okv) >= 2L) r[okv] <- (rank(v[okv], ties.method = "average") - 0.5) / sum(okv)
    r
  }
  r_mix <- lam * rk(shrink(a_sys)) + (1 - lam) * rk(shrink(a_idio))
  sd_r  <- suppressWarnings(stats::sd(r_mix))
  if (!all(is.finite(r_mix)) || !is.finite(sd_r) || sd_r <= 0) return(1)  # 차등 미성립 = 무개입

  # ── ⑤ 노출 = 1 − g·r_mix (횡단면 평균 1 − g/2 — 스칼라판보다 덜 깎고 몫은 취약축에 몰린다)
  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - g * r_mix)))
}
