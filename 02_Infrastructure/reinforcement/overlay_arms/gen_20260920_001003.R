#==============================================================================
# gen_20260920_001003 — 책 위험균형 갭 브레이크 (같은 이름들을 균형 잡았을 때의 위험만 진다)
#                       (표적 칸: action = scalar_exposure · state = holding_level)
#
# ★기전
#   이 칸의 선행 arm 둘은 책 적재의 **수준**(예산 대비 크기)과 **모양**(하락/전구간 비대칭)을 읽었다.
#   둘 다 책을 대표값 하나로 접어서 본다. 여기서 읽는 것은 접기 전의 **흩어짐**이다.
#   등가중 25종은 비중이 같을 뿐 위험이 같지 않다 — 적재가 큰 소수가 책 변동의 대부분을 나르면
#   명목 25종이 실질 몇 종의 베팅이 된다. 평균 적재가 같고 상하 대칭도 같은데 흩어짐만 다른 두 책은
#   앞 두 층에 똑같이 보인다. 그 차이가 이 칸의 미탐색 내용이다.
#
#   기준점은 튜닝이 아니라 정리(theorem)에서 온다. Maillard-Roncalli-Teiletche(2010, On the
#   properties of equally-weighted risk contributions portfolios)는 같은 종목 집합 위에서
#   sigma_MV <= sigma_ERC <= sigma_EW 를 보인다 — 등위험기여(ERC) 책의 변동은 등가중 책의 변동을
#   결코 넘지 않고, 두 값이 같아지는 경우는 등가중이 이미 등위험기여일 때뿐이다. 따라서
#       e = sigma_ERC / sigma_EW
#   는 구조적으로 [0,1] 안에 있고 e=1 이 '이 책은 이미 균형' 이라는 뜻을 정확히 갖는다. 문턱이 없다.
#   행동의 해석: 비중은 알파가 정하므로 건드리지 않되(여기는 총노출 축이다), **같은 이름들을 균형
#   잡았을 때 졌을 만큼의 위험만** 지도록 책 전체를 줄인다 — 고르지 못함에서 공짜로 따라온 몫,
#   즉 고르고 진 위험이 아닌 몫만 덜어낸다.
#
#   추정은 단일요인 분해다. 종목 i 의 자체변동 ovol_i 가 시장 성분 m_i = ovol_i*|bcorr_i| 와
#   잔차 u_i = ovol_i*sqrt(1-bcorr_i^2) 로 갈리고, 책 변동은 sigma(w) = sqrt((sum w*m)^2 + sum w^2*u^2).
#   ERC 비중은 w_i <- sqrt(w_i / MRC_i) 정규화 반복의 고정점으로 푼다 — 고정점에서 w_i*MRC_i 가 전
#   종목 같아지므로 그 점이 곧 등위험기여다. 기하 감쇠라 진동하지 않고, 보유가 25종 이하라 비용이 없다.
#   ★상관을 절대값으로 읽는 이유: 헤지가 주는 상쇄 이득은 책 적재의 **수준** 층이 이미 값을 매기는
#   몫이고, 이 층이 값을 매기는 것은 위험예산이 몇 이름에 몰렸는가다. 분자·분모를 같은 규약으로
#   재므로 이 선택은 비에서 대부분 상쇄된다.
#   ★한계 명시: ① 잔차 간 상관 0 을 가정한다 — 보유가 한 덩어리로 묶인 달에는 불균형을 과소평가한다
#   (과대 개입 쪽으로는 틀리지 않는다). ② ovol·bcorr 이 확장창 누적 추정이라 느리게 움직인다 — 이
#   배율의 달별 변화는 대부분 **보유 교체**에서 온다. 국면 급변에 대한 반응은 시장 상태 층의 몫이다.
#   ③ 이상치를 횡단면 분위로 절단하지 않는다 — 한 이름이 책 위험을 혼자 나르는 상황이 바로 이 층이
#   재려는 것이라 절단하면 신호를 절단한다. 대신 관측수 신뢰도로만 축소한다.
#
# ★계약
#   반환 = 스칼라 e ∈ [0,1] (표적이 scalar_exposure 이므로 종목별 표를 내지 않는다).
#   H 는 읽지 않는다 — 따라서 t 행이 미실현인 익월 수익 열에 닿을 경로 자체가 없다.
#   ctx$hold = 그 달 보유의 확장창 상태(ovol=자체변동 · bcorr=시장상관 · n_obs). 엔진이 신호일 이하
#   관측만으로 만든 값이다. 비중 열이 없으므로 고정 축(Sigma w=1 · 등가중)을 현행 비중으로 읽는다.
#   임의 상수 금지 — 결측 대치는 보유 횡단면 중앙값, 신뢰도 축소는 보유 안 관측수 중앙값, 기준점은
#   '등가중 = 등위험기여' 라는 구조적 일치점에서 나온다.
#   추정 불가·유효 이름 2 미만이면 e <- 1(무개입). 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20260920_001003 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)

  n <- nrow(hold)
  if (n < 2L) return(1)                        # 균형·불균형을 가를 횡단면이 아니다

  ov <- suppressWarnings(as.numeric(hold$ovol))
  bc <- suppressWarnings(as.numeric(hold$bcorr))
  nb <- suppressWarnings(as.numeric(hold$n_obs))
  if (length(ov) != n || length(bc) != n) return(1)
  if (length(nb) != n) nb <- rep(NA_real_, n)

  # ── ① 자체변동 — 못 읽은 이름은 보유 횡단면 중앙값으로 채운다.
  #   대치는 흩어짐을 줄이는 쪽이라 개입을 약하게 만든다(보수적 방향).
  okv <- is.finite(ov) & ov > 0
  if (sum(okv) < 2L) return(1)                 # 변동을 두 이름도 못 읽으면 균형을 말하지 않는다
  med_v <- suppressWarnings(stats::median(ov[okv]))
  if (!is.finite(med_v) || med_v <= 0) return(1)
  ov[!okv] <- med_v

  # ── ② 관측 신뢰도 축소 — 표본이 짧은 이름의 변동 추정을 보유 중앙값 쪽으로 당긴다.
  #   가중 n/(n + 보유 안 관측수 중앙값) — 중앙인 이름이 자기 추정 절반을 싣는다. 문턱이 아니다.
  m_n <- suppressWarnings(stats::median(nb[is.finite(nb)]))
  lam <- if (is.finite(m_n) && m_n > 0) nb / (nb + m_n) else rep(NA_real_, n)
  lam[!is.finite(lam)] <- 0.5                  # 관측수를 못 읽은 이름 = 자기 추정과 중앙값 반반
  ov <- lam * ov + (1 - lam) * med_v
  if (!all(is.finite(ov)) || !all(ov > 0)) return(1)

  # ── ③ 시장상관 — 정의역으로 되돌리고 결측은 보유 안 |상관| 중앙값으로 채운다.
  bc <- pmax(-1, pmin(1, bc))
  bm <- suppressWarnings(stats::median(abs(bc[is.finite(bc)])))
  if (!is.finite(bm)) bm <- 0                  # 상관을 한 이름도 못 읽은 달 = 공통성분 없이 읽는다(하한)
  bc <- abs(bc)
  bc[!is.finite(bc)] <- bm

  m <- ov * bc                                 # 시장 성분 (적재 x 시장변동, vol 단위)
  u <- ov * sqrt(pmax(0, 1 - bc * bc))         # 잔차 성분
  if (!all(is.finite(m)) || !all(is.finite(u))) return(1)

  .sig <- function(w) {                        # 단일요인 책 변동
    s2 <- sum(w * m)^2 + sum(w * w * u * u)
    if (!is.finite(s2) || s2 <= 0) NA_real_ else sqrt(s2)
  }

  w_ew <- rep(1 / n, n)                        # 고정 축 = 등가중 (보유표에 비중 열이 없다)
  s_ew <- .sig(w_ew)
  if (!is.finite(s_ew)) return(1)

  # ── ④ 같은 이름들의 등위험기여 책 — 고정점 반복. 고정점에서 w_i*MRC_i 가 전 종목 같다.
  #   반복 횟수는 수렴 여유이지 문턱이 아니다(보유가 25종 이하라 비용이 없다).
  w <- w_ew
  for (.k in seq_len(200L)) {
    s <- .sig(w)
    if (!is.finite(s)) return(1)
    mrc <- (m * sum(w * m) + w * u * u) / s    # 한계 기여 = 편미분 d(sigma)/d(w_i)
    if (!all(is.finite(mrc)) || !all(mrc > 0)) return(1)
    w2 <- sqrt(w / mrc)                        # 기하 감쇠 — 목표(∝ 1/MRC)와 현재의 중간으로만 간다
    sw <- sum(w2)
    if (!is.finite(sw) || sw <= 0) return(1)
    w <- w2 / sw
  }
  s_erc <- .sig(w)
  if (!is.finite(s_erc)) return(1)

  # ── ⑤ 총노출 = 균형 책의 변동 / 등가중 책의 변동 (이미 균형이면 1 · 증액은 하지 않는다)
  max(0, min(1, s_erc / s_ew))
}
