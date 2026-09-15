#==============================================================================
# gen_20260915_203006 — 책 위험예산 브레이크 (보유가 나르는 위험을 직접 재서 총노출을 정한다)
#                       (표적 칸: action = scalar_exposure · state = holding_level)
#
# ★기전
#   총노출 축의 기존 arm 은 전부 **시장**의 상태(변동성·낙폭·산포·추세)만 본다 — 같은 시장에서
#   어떤 책을 들고 있든 같은 배율을 건다. 그런데 시장 충격이 실제로 포트폴리오에 얼마나 실리는지는
#   책의 구성이 정한다: 하방 적재가 낮고 잔차가 흩어진 25종 책은 같은 충격을 절반만 받고,
#   하방 적재가 높은 책은 그대로 받는다. 보유 상태를 보는 arm 은 지금까지 전부 횡단면 축이었다
#   (dbeta_tilt·holdlvl_syscrowd_tilt 계열 — 책 **안에서** 누구를 더 깎을지만 정한다).
#   이 arm 은 같은 상태를 총노출 축으로 옮긴다: 책 **전체**가 지금 얼마를 지고 있는지를 추정해
#   그 값이 위험예산을 넘는 만큼만 깎는다.
#
#   추정은 단일요인 분해다. 종목 i 의 변동은 시장 성분과 잔차로 갈리고(bcorr² = 시장이 설명하는 몫),
#   손실을 만드는 것은 하락장에서의 적재이므로 요인 적재는 하방베타로 읽는다:
#     s_book = sqrt( (d_bar · s_m)^2 + iota^2 )
#     d_bar  = 관측 신뢰도 가중 평균 하방베타 (표본이 짧은 종목은 덜 실린다)
#     iota^2 = 평균 잔차분산 / n   — 등가중 n 종목이 잔차를 얼마나 흩뜨리는가
#   d_bar 와 iota 가 갈리므로 같은 시장변동 s_m 에서도 책마다 다른 배율이 나온다.
#   ★한계 명시: iota 는 잔차 간 상관 0 을 가정한 **하한**이다. 보유가 한 덩어리로 묶인 달에는
#   실제 책 위험이 이보다 크므로 이 arm 은 그쪽으로 과소 반응한다 — 과대 반응은 하지 않는다.
#
# ★계약
#   반환 = 스칼라 e ∈ [0,1] (표적이 scalar_exposure 이므로 종목별 표를 내지 않는다).
#   H = 확장창(미래 행 없음) · t 행이 미실현인 익월 수익 열은 읽지 않는다.
#   ctx$hold = 그 달 보유 상태(beta · dbeta=하방베타 · ovol=자체변동 · bcorr=시장상관 · n_obs).
#   임의 상수 금지 — 위험예산은 계약이 주는 시장 자기이력 중앙 변동(없으면 확장창 중앙값),
#   관측창은 과거쌍 1개월 앞 적합, 신뢰도 가중은 보유 안 관측수 중앙값에서 나온다.
#   절벽형 워밍업을 두지 않는다(표본 부족 구간은 러너의 축소 가중이 처리한다).
#   추정 불가·표본 부족이면 e <- 1(무개입). 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20260915_203006 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)

  tt <- suppressWarnings(as.integer(t))
  if (!is.finite(tt)) return(1)
  tt <- min(tt, nrow(H))
  if (tt < 2L) return(1)

  nmin <- suppressWarnings(as.integer(ctx$n_min))
  if (!is.finite(nmin) || nmin < 12L) nmin <- 24L

  # ── ① 시장 충격 규모 s_m — 한 달 앞 시장 변동을 가장 잘 맞힌 관측창.
  #   길이를 상수로 박지 않고 그 시점까지의 적합으로 고른다(결과가 이미 실현된 과거쌍만).
  cand <- list(suppressWarnings(as.numeric(H$rv20)),
               suppressWarnings(as.numeric(H$rv60)),
               suppressWarnings(as.numeric(H$rv120)))
  act  <- cand[[1L]][seq_len(tt)]
  best <- NA_integer_; berr <- Inf
  if (tt >= nmin) {
    for (k in seq_along(cand)) {
      pr  <- cand[[k]][seq_len(tt)]
      err <- suppressWarnings(mean((pr[-tt] - act[-1L])^2, na.rm = TRUE))
      if (is.finite(err) && err < berr) { berr <- err; best <- k }
    }
  }
  s_m <- if (is.na(best)) NA_real_ else cand[[best]][tt]
  if (!is.finite(s_m)) s_m <- suppressWarnings(as.numeric(ctx$v_now)[1])
  if (!is.finite(s_m) || s_m <= 0) return(1)

  n_name <- nrow(hold)

  # ── ② 책의 하방 적재 d_bar — 손실을 만드는 쪽의 적재를 신뢰도로 가중해 모은다.
  #   하방베타가 없는 종목은 전구간 베타로 후퇴하고, 관측이 짧은 종목은 덜 실린다
  #   (가중 = n/(n + 보유 안 관측수 중앙값) — 문턱이 아니라 축소 가중이다).
  db <- suppressWarnings(as.numeric(hold$dbeta))
  bb <- suppressWarnings(as.numeric(hold$beta))
  ld <- ifelse(is.finite(db), db, bb)
  nb <- suppressWarnings(as.numeric(hold$n_obs))
  mo <- suppressWarnings(stats::median(nb[is.finite(nb)]))
  rel <- if (is.finite(mo) && mo > 0) nb / (nb + mo) else rep(1, n_name)
  rel[!is.finite(rel)] <- 0
  okl <- is.finite(ld) & rel > 0
  if (!any(okl)) return(1)                       # 적재를 못 읽으면 책 위험을 말하지 않는다
  d_bar <- sum(ld[okl] * rel[okl]) / sum(rel[okl])
  if (!is.finite(d_bar)) return(1)
  d_bar <- max(0, d_bar)                         # 음의 적재(헤지)는 노출을 늘릴 근거가 아니다

  # ── ③ 잔차 위험 iota — 평균 잔차분산을 등가중 n 종목이 흩뜨린 뒤 남는 몫.
  #   잔차 = 자체변동 × sqrt(1 − 시장상관²). 상관 결측은 보유 횡단면 중앙값으로 채운다.
  ov <- suppressWarnings(as.numeric(hold$ovol))
  bc <- suppressWarnings(as.numeric(hold$bcorr))
  bc <- pmax(-1, pmin(1, bc))                    # 상관의 정의역 — 추정 잡음으로 벗어난 값만 되돌린다
  bm <- suppressWarnings(stats::median(bc[is.finite(bc)]))
  if (!is.finite(bm)) bm <- 0
  bc[!is.finite(bc)] <- bm
  u  <- ov * sqrt(pmax(0, 1 - bc * bc))
  ou <- is.finite(u)
  iota2 <- if (any(ou)) mean(u[ou] * u[ou]) / n_name else 0
  if (!is.finite(iota2) || iota2 < 0) iota2 <- 0

  # ── ④ 위험예산 — 시장이 자기 이력에서 통상 지고 있던 변동(계약 제공값).
  #   같은 연율 단위라 환산 상수를 가정하지 않는다. 계약값이 없으면 확장창 중앙값으로 만든다.
  bud <- suppressWarnings(as.numeric(ctx$tgt)[1])
  if (!is.finite(bud) || bud <= 0) {
    rv  <- cand[[2L]][seq_len(tt)]
    bud <- suppressWarnings(stats::median(rv[is.finite(rv)]))
  }
  if (!is.finite(bud) || bud <= 0) return(1)

  # ── ⑤ 총노출 = 예산 / 책이 지금 지고 있는 위험 (예산 아래면 무개입 — 증액은 하지 않는다)
  s_book <- sqrt((d_bar * s_m)^2 + iota2)
  if (!is.finite(s_book) || s_book <= 0) return(1)
  max(0, min(1, bud / s_book))
}
