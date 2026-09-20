#==============================================================================
# gen_20260921_071600 — 책 이력담보 브레이크 (위기를 겪어본 이름들만큼만 진다)
#                       (표적 칸: action = scalar_exposure · state = holding_level)
#
# ★기전
#   이 칸의 선행 arm 셋은 책의 위험을 **양**(예산 대비 크기) · **모양**(하락/전구간 비대칭) ·
#   **흩어짐**(균형 잡았을 때와의 비)으로 읽었다. 셋 다 hold 의 숫자를 액면 그대로 믿는다.
#   그런데 그 숫자들이 어디서 왔는지는 이름마다 다르다 — 엔진은 각 이름의 **자기 가용 이력**
#   전체에서 확장창으로 beta·dbeta·ovol·bcorr 을 만든다(rf_cell_engine.R: 누적합, 최소관측 250일 ·
#   하방베타는 시장 하락일 60일). 2001년부터 있는 이름의 하방베타는 위기를 통과하며 만들어진 값이고,
#   최근 상장·편입된 이름의 하방베타는 **위기를 한 번도 통과하지 않은 창**에서 나온 값이다.
#   책 수준으로 접으면 이 차이가 사라진다 — 위 세 층은 둘을 구별하지 못한다. 그 구별이 이 칸의
#   미탐색 내용이고, 이 arm 이 재는 상태다: **이 책의 위험 숫자 중 얼마가 스트레스를 통과해 만들어졌나.**
#
#   담보(coverage)의 정의. 시장의 스트레스 이력을 월 단위 하락 에너지 min(0, r)^2 의 누적으로 놓으면
#   (에너지는 손실 크기의 제곱이라 큰 사건이 지배한다 — 우리가 벼르는 것이 바로 그 사건이다),
#   이름 i 의 추정창이 덮는 몫은
#       c_i = (최근 m_i 개월의 하락 에너지) / (확장창 전체의 하락 에너지)
#   이고 m_i 는 그 이름의 관측수를 월로 환산한 길이다. 자기 이력이 전 구간을 덮는 이름은 c=1,
#   위기 이후에 들어온 이름은 c 가 작다. 문턱이 없다 — c 는 구조적으로 [0,1] 이고 1 이 '전부 담보'다.
#
#   행동. 담보 못한 몫을 **책이 스스로 보여주는 상단**으로 청구한 적재를 만들고, 액면 적재가 그
#   청구 적재에서 차지하는 비만큼만 진다:
#       D_v = Σ w_i d_i                      (액면 — 위 세 층이 쓰는 값)
#       D_c = Σ w_i [ c_i d_i + (1-c_i) d_hi ]   (담보 못한 몫은 읽히는 상단으로 청구)
#       e   = D_v / D_c
#   뜻: "벼랑에서 어떻게 움직일지 모르는 이름들이 알고 보니 이 책에서 가장 시장에 민감한 이름만큼
#   나쁘다면, 그때도 지금 지려던 만큼만 지도록" 책 전체를 줄인다. d_hi 는 외부 상수가 아니라 그 달
#   보유 횡단면의 상단(양끝 절단 후)이라 책이 균질하면 자동으로 개입이 사라진다.
#   기준점 1(전부 담보)은 튜닝한 문턱이 아니라 '모르는 이름이 없다'는 상태 그 자체이고, 증액은 없다.
#
#   ★한계 명시: ① 하락 에너지는 **시장 달력**이라 이름 고유의 사건(개별 악재)은 세지 않는다 —
#   이 층은 공통 스트레스에 대한 담보만 말한다. ② 창 길이는 관측수를 연 252거래일/12개월 규약으로
#   환산한 값이고, 그 규약은 ovol 을 sqrt(252) 로 연율화한 추정기의 규약을 그대로 따른다 —
#   환산 오차는 창을 길게도 짧게도 만들 수 있으나 c 는 에너지 비라 완만하게만 반응한다.
#   ③ 이름의 이력에 공백(거래정지·편출입)이 있으면 관측수가 실제 경과보다 짧아 담보를 과소평가한다
#   — 과대 개입 쪽이 아니라 **과소 담보 → 더 줄이는** 쪽이므로 보수적으로만 틀린다.
#   ④ 관측수를 못 읽은 이름은 보유 중앙값으로 둔다(모름을 개입 근거로 삼지 않는다).
#
# ★계약
#   반환 = 스칼라 e ∈ [0,1] (표적이 scalar_exposure 이므로 종목별 표를 내지 않는다).
#   H = 확장창(미래 행 없음) — nav 의 t 행까지만 읽어 과거 실현 월수익을 만든다. t 행이 미실현인
#   익월 수익 열은 읽지 않는다(스트레스 달력은 전부 이미 실현된 과거다).
#   ctx$hold = 그 달 보유의 확장창 상태(beta · dbeta · ovol · bcorr · n_obs). ctx$n_min = 그 층의
#   표본 하한 — 달력이 그보다 짧으면 담보를 말하지 않는다.
#   임의 상수 금지 — 담보 분모는 확장창 전체의 하락 에너지, 상단은 보유 횡단면 분위, 결측 대치는
#   보유 안 중앙값에서 나온다. 전부 그 시점 데이터의 추정이다.
#   추정 불가·표본 부족·하락 이력 부재면 e <- 1(무개입). 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20260921_071600 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)
  n <- nrow(hold)

  tt <- suppressWarnings(as.integer(t))
  if (!is.finite(tt)) return(1)
  tt <- min(tt, nrow(H))

  nmin <- suppressWarnings(as.integer(ctx$n_min))
  if (!is.finite(nmin) || nmin < 12L) nmin <- 24L
  if (tt <= nmin) return(1)                    # 달력이 표본 하한보다 짧으면 담보를 말하지 않는다

  # ── ① 시장 스트레스 달력 — 확장창 월수익의 하락 에너지. 전부 이미 실현된 과거다.
  nv <- suppressWarnings(as.numeric(H$nav))
  if (length(nv) < tt) return(1)
  nv <- nv[seq_len(tt)]
  ok_nv <- is.finite(nv) & nv > 0
  if (sum(ok_nv) < nmin) return(1)
  r <- nv[-1L] / nv[-tt] - 1                   # 월수익 (달 2..tt)
  r[!is.finite(r)] <- 0                        # 읽히지 않는 달은 에너지 0 — 없는 사건을 만들지 않는다
  s <- pmin(0, r)^2                            # 하락분만. 제곱이라 큰 사건이 지배한다
  m <- length(s)
  if (m < nmin) return(1)
  tot <- sum(s)
  if (!is.finite(tot) || tot <= 0) return(1)   # 하락 이력이 없으면 담보의 뜻이 없다
  suf <- rev(cumsum(rev(s)))                   # suf[k] = 달 k 이후의 하락 에너지

  # ── ② 이름별 추정창 길이(월) — 관측수를 추정기와 같은 연율화 규약으로 환산한다.
  dpm <- 252 / 12                              # 연 252거래일 / 12개월 (ovol 의 sqrt(252) 와 같은 규약)
  nb <- suppressWarnings(as.numeric(hold$n_obs))
  if (length(nb) != n) nb <- rep(NA_real_, n)
  okn <- is.finite(nb) & nb > 0
  if (!any(okn)) return(1)                     # 창 길이를 한 이름도 못 읽으면 담보를 말하지 않는다
  nb[!okn] <- suppressWarnings(stats::median(nb[okn]))   # 모름은 보유 중앙값 — 개입 근거로 쓰지 않는다
  win <- pmax(1, floor(nb / dpm))
  win <- pmin(win, m)                          # 달력보다 긴 창은 달력 전체를 덮는다
  idx <- pmax(1L, pmin(m, as.integer(m - win + 1L)))
  cvg <- suf[idx] / tot                        # 담보 c_i ∈ [0,1] — 그 창이 덮은 하락 에너지의 몫
  cvg[!is.finite(cvg)] <- 1                    # 계산이 안 되면 담보된 것으로 둔다(무개입 쪽)
  cvg <- pmax(0, pmin(1, cvg))

  # ── ③ 하방 적재 d — dbeta, 없으면 전구간 베타, 그것도 없으면 읽히는 이름들의 중앙값.
  #   읽히지 않는 이름을 버리지 않는 것이 요점이다 — 관측이 짧아 못 읽은 이름이 바로 이 층의 표적이라
  #   버리면 신호를 버린다(그 이름의 담보 c 는 자기 관측수에서 따로 나온다).
  dd <- suppressWarnings(as.numeric(hold$dbeta))
  bb <- suppressWarnings(as.numeric(hold$beta))
  if (length(dd) != n) dd <- rep(NA_real_, n)
  if (length(bb) != n) bb <- rep(NA_real_, n)
  d <- ifelse(is.finite(dd), dd, bb)
  rd <- is.finite(d)
  if (sum(rd) < 2L) return(1)                  # 상단을 말할 횡단면이 아니다
  med_d <- suppressWarnings(stats::median(d[rd]))
  if (!is.finite(med_d)) return(1)
  d[!rd] <- med_d

  # ── ④ 읽히는 상단 d_hi — 보유 횡단면의 자기 분위로 양끝을 접은 뒤의 상단.
  #   한 이름의 극단 적재가 청구액을 혼자 정하지 못하게 한다(고정 상한 아님).
  qq <- suppressWarnings(stats::quantile(d[rd], c(0.1, 0.9), names = FALSE, type = 7))
  if (length(qq) != 2L || !all(is.finite(qq))) return(1)
  d <- pmin(pmax(d, qq[1L]), qq[2L])
  d_hi <- qq[2L]
  if (!is.finite(d_hi) || d_hi <= 0) return(1)

  # ── ⑤ 가중 = 시장위험 지분 ovol·|bcorr| — 책의 시장 적재를 실제로 나르는 이름이 담보 판정을 지배한다.
  #   전량 결측이면 등가중으로 후퇴하고, 일부 결측은 유효 이름들의 중앙값으로 채운다.
  ov <- suppressWarnings(as.numeric(hold$ovol))
  bc <- suppressWarnings(as.numeric(hold$bcorr))
  if (length(ov) != n) ov <- rep(NA_real_, n)
  if (length(bc) != n) bc <- rep(NA_real_, n)
  bc <- pmax(-1, pmin(1, bc))                  # 상관의 정의역 — 추정 잡음으로 벗어난 값만 되돌린다
  w <- ov * abs(bc)
  okw <- is.finite(w) & w > 0
  if (!any(okw)) {
    w <- rep(1, n)
  } else {
    w[!okw] <- suppressWarnings(stats::median(w[okw]))
  }
  sw <- sum(w)
  if (!is.finite(sw) || sw <= 0) return(1)
  w <- w / sw

  # ── ⑥ 액면 적재 vs 담보 청구 적재 → 총노출 (전부 담보면 1 · 증액은 하지 않는다)
  D_v <- sum(w * d)
  D_c <- sum(w * (cvg * d + (1 - cvg) * d_hi))
  if (!is.finite(D_v) || !is.finite(D_c) || D_v <= 0 || D_c <= 0) return(1)
  max(0, min(1, D_v / D_c))
}
