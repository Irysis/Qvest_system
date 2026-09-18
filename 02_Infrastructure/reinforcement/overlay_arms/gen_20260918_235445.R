#==============================================================================
# gen_20260918_235445 — 책 볼록성 브레이크 (보유가 고른 하방/전구간 적재 비대칭으로 총노출을 정한다)
#                       (표적 칸: action = scalar_exposure · state = holding_level)
#
# ★기전
#   총노출 축의 기존 arm 은 시장 상태(변동성·낙폭·산포·추세)를 읽어 **얼마나 위험한 때인가**로
#   배율을 정하고, 이 칸의 선행 arm 한 건은 책이 지금 지고 있는 위험의 **크기**를 재서 예산과
#   비교했다. 둘 다 '위험의 양' 축이다. 여기서 재는 것은 양이 아니라 **모양**이다:
#   같은 양의 시장 적재라도 하락장에서 더 많이 실리는 책과 덜 실리는 책이 있다.
#   종목 i 의 전구간 베타 b_i 는 시장 전 국면에서의 평균 적재이고 하방베타 d_i 는 시장이
#   내린 날들만의 적재라, 두 값의 괴리 d_i − b_i 는 그 종목이 상승은 덜 따라가고 하락은 더
#   따라가는 정도 — 곧 음의 볼록성이다. 책 수준으로 모으면 D/B 는 "이 책이 시장 한 단위
#   전구간 적재당 하락에서 지는 적재" 이고, 이 비는 노출 배율에 대해 무차원이라 변동성의
#   수준과 무관하게 정의된다. 그래서 이 arm 은 조용한 시장에서도 책이 볼록성 나쁜 이름들로
#   기울면 깎고, 시끄러운 시장이라도 책이 볼록성을 사 두었으면(D ≤ B) 전혀 깎지 않는다.
#   시장 시계열을 한 열도 읽지 않는다는 것이 이 설계의 요점이다 — 변동성·낙폭 층과 곱해질 때
#   같은 정보를 두 번 세지 않는 층을 하나 만든다.
#
#   집계는 등가중 평균이 아니라 **시장위험 지분 가중**이다. 종목의 시장 성분 변동은
#   ovol_i·|bcorr_i| 이므로 책의 시장위험에 실제로 실리는 몫이 그만큼이고, 그 가중으로 모아야
#   "책이 어디에 시장 적재를 몰아 두었는가" 가 비에 반영된다. 등가중이면 시장 노출이 거의
#   없는 이름이 볼록성 판정을 흔든다.
#
#   개입식: e = min(1, B/D) — 책의 하방 적재가 전구간 적재를 넘는 배수만큼만 깎는다.
#   기준점 1(하방 = 전구간, 즉 대칭)은 튜닝한 문턱이 아니라 대칭성 그 자체이고, 증액은 없다.
#   ★한계 명시: b_i·d_i 는 확장창 누적 추정이라 천천히 움직인다 — 이 arm 의 시간 변화는 거의
#   전부 **보유 교체**에서 온다. 국면이 급변해도 같은 이름을 들고 있으면 배율은 거의 그대로다.
#   그 반응은 다른 층(시장 상태 축)의 몫이지 이 층의 결함이 아니다.
#
# ★계약
#   반환 = 스칼라 e ∈ [0,1] (표적이 scalar_exposure 이므로 종목별 표를 내지 않는다).
#   H 는 읽지 않는다 — 따라서 t 행이 미실현인 익월 수익 열에 닿을 경로 자체가 없다.
#   ctx$hold = 그 달 보유의 확장창 상태(beta · dbeta=하방베타 · ovol=자체변동 · bcorr=시장상관 ·
#   n_obs). 엔진이 신호일 이하 관측만으로 만든 값이다.
#   임의 상수 금지 — 이상치 절단은 보유 횡단면 분위, 추정 축소는 보유 안 관측수 중앙값,
#   하방베타 결측 대치는 보유 안 비대칭비 중앙값에서 나온다. 전부 그 달 데이터의 추정이다.
#   추정 불가·표본 부족이면 e <- 1(무개입). 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20260918_235445 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)

  n  <- nrow(hold)
  b  <- suppressWarnings(as.numeric(hold$beta))
  d  <- suppressWarnings(as.numeric(hold$dbeta))
  ov <- suppressWarnings(as.numeric(hold$ovol))
  bc <- suppressWarnings(as.numeric(hold$bcorr))
  nb <- suppressWarnings(as.numeric(hold$n_obs))
  if (length(b) != n || length(d) != n) return(1)

  base <- is.finite(b)                       # 전구간 적재를 읽은 이름 = 비교의 모집단
  if (sum(base) < 2L) return(1)              # 책 수준 비를 말할 표본이 아니다
  b <- b[base]; d <- d[base]; ov <- ov[base]; bc <- bc[base]; nb <- nb[base]
  m <- length(b)

  # ── ① 이상치 절단 — 보유 횡단면의 자기 분위로만 자른다(고정 상한 아님).
  #   한 이름의 극단 적재가 책의 볼록성 판정을 혼자 정하지 못하게 한다.
  .wins <- function(x) {
    qq <- suppressWarnings(stats::quantile(x[is.finite(x)], c(0.1, 0.9),
                                           names = FALSE, type = 7))
    if (length(qq) != 2L || !all(is.finite(qq))) return(x)
    pmin(pmax(x, qq[1L]), qq[2L])
  }
  b <- .wins(b); d <- .wins(d)

  # ── ② 추정 축소 — 관측이 짧은 이름일수록 보유 횡단면 중앙값 쪽으로 당긴다.
  #   가중 n/(n + 보유 안 관측수 중앙값): 중앙인 이름이 자기 추정 절반, 짧은 이름은 더 적게 싣는다.
  m_n <- suppressWarnings(stats::median(nb[is.finite(nb)]))
  lam <- if (is.finite(m_n) && m_n > 0) nb / (nb + m_n) else rep(NA_real_, m)
  lam[!is.finite(lam)] <- 0.5                # 관측수를 못 읽은 이름 = 자기 추정과 중앙값 반반
  med_b <- suppressWarnings(stats::median(b[is.finite(b)]))
  if (!is.finite(med_b)) return(1)
  b <- lam * b + (1 - lam) * med_b
  okd <- is.finite(d)
  if (any(okd)) {
    med_d <- suppressWarnings(stats::median(d[okd]))
    if (is.finite(med_d)) d[okd] <- lam[okd] * d[okd] + (1 - lam[okd]) * med_d
  }

  # ── ③ 하방베타 결측 대치 — 하방 표본(시장 하락일)이 모자라 d 를 못 낸 이름을 그냥 버리면
  #   분자·분모의 이름 집합이 갈려 비가 선택으로 오염된다. 측정된 이름들의 비대칭비 중앙값을
  #   그 이름의 전구간 적재에 곱해 같은 집합 위에서 비교한다.
  rr <- rep(NA_real_, m)
  pos <- okd & is.finite(b) & b > 0
  if (any(pos)) rr[pos] <- d[pos] / b[pos]
  a_med <- suppressWarnings(stats::median(rr[is.finite(rr)]))
  if (!is.finite(a_med)) return(1)           # 비대칭을 한 이름도 측정 못 했으면 말하지 않는다
  d[!okd] <- b[!okd] * a_med

  # ── ④ 시장위험 지분 가중 — 종목의 시장 성분 변동 ovol·|bcorr| 만큼이 책의 시장위험에 실린다.
  #   전량 결측이면 등가중으로 후퇴하고, 일부 결측은 유효 이름들의 중앙값으로 채운다.
  w <- ov * abs(bc)
  okw <- is.finite(w) & w > 0
  if (!any(okw)) {
    w <- rep(1, m)
  } else {
    w[!okw] <- suppressWarnings(stats::median(w[okw]))
  }
  sw <- sum(w)
  if (!is.finite(sw) || sw <= 0) return(1)
  w <- w / sw

  # ── ⑤ 책 수준 적재 두 개 → 볼록성 비 → 총노출
  B <- sum(w * b)                            # 전구간 적재
  D <- sum(w * d)                            # 하락장 적재
  if (!is.finite(B) || !is.finite(D) || B <= 0 || D <= 0) return(1)
  max(0, min(1, B / D))                      # 대칭(D ≤ B)이면 무개입 · 증액은 하지 않는다
}
