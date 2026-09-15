#==============================================================================
# trend_persist_tilt — 추세 지속성 × 시장베타 횡단면 틸트 (2026-09-13)
#
# ★표적 칸: action = cross_sectional · state = trend  (기전 지도 측정 1회 · 미포화)
#   낙폭(drawdown) 칸은 스칼라 25회 · 횡단면 18회로 이미 포화다. 이 arm 은 그 칸에 다시
#   들어가지 않는다.
#
# ★기전 (사전 선언 — 특정 구간을 보고 만든 규칙이 아니다)
#   기존 오버레이는 전부 **얼마나 깊이 빠졌나**(dd 의 경험분위)로 개입한다. 그 계열은 급락에
#   잘 듣는다 — 깊이가 빠르게 극단으로 가므로 분위가 즉시 1 에 붙는다.
#   느린 침식은 정의상 깊이가 극단으로 안 간다. 매달 조금씩 밀리면 dd 분위는 중간에 머물고
#   개입이 약하게만 걸린다. 그런데 수중 기간은 그런 국면에서 가장 길다. 즉 깊이 기반 계열은
#   **가장 오래 잃는 국면에서 가장 덜 개입한다**. 이건 그 계열의 구조이지 튜닝 문제가 아니다.
#   이 arm 은 상태 변수를 깊이에서 **지속성**으로 바꾼다: 시장이 자기 추세 아래에 얼마나
#   **연속으로** 머물렀나. 그리고 축소 몫을 시장베타 높은 보유에 몰아준다 — 추세가 이어지는
#   동안 손실을 계속 복리로 쌓는 쪽이 거기이기 때문이다.
#   ★dbeta_tilt 와의 구분: 저쪽은 상태=깊이·차등=하방베타, 이쪽은 상태=지속성·차등=시장베타.
#     상태와 차등이 둘 다 다르므로 같은 축의 라벨 바꾸기가 아니다.
#
# ★계약
#   반환 = 스칼라 e ∈ [0,1] 또는 data.table(Ticker, e). H = 확장창(t 행까지).
#   H$fwd 는 읽지 않는다(t 행 미실현). 임의 상수 문턱 없음 — 개입 강도는 연속 길이의
#   자기 이력 경험분포에서, 종목 차등은 그 달 보유 안의 횡단면 순위에서 나온다.
#   추정 불가 시 e <- 1(무개입).
#==============================================================================

overlay_expo_trend_persist_tilt <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)

  # ── ① 추세 아래 여부 — 엔진이 주는 r252(추종 252거래일 수익)의 부호.
  #   창 길이를 내가 고르지 않는다(엔진 제공 열). 과거 행만 쓴다.
  r <- suppressWarnings(as.numeric(H$r252))
  if (length(r) < t) return(1)
  r <- r[seq_len(t)]
  below <- is.finite(r) & r < 0
  if (sum(is.finite(r)) < 24L) return(1)          # 최소 표본(참조 arm dbeta_tilt 와 동일 규약)

  # ── ② 연속 길이의 이력 — 각 시점까지의 "현재 연속 below 개월수"를 만든다.
  #   run[s] 는 s 시점 정보만으로 정해진다(누적 전방 없음).
  run <- integer(t)
  acc <- 0L
  for (s in seq_len(t)) {
    acc <- if (isTRUE(below[s])) acc + 1L else 0L
    run[s] <- acc
  }
  run_now <- run[t]
  if (run_now <= 0L) return(1)                    # 추세 위 = 무개입

  # ── ③ 개입 강도 g — 지금 연속 길이가 자기 이력에서 얼마나 긴가(확장창 경험분포).
  #   중앙 위에서만 개입한다. 문턱은 데이터가 정한다(상수 아님).
  hist_run <- run[seq_len(t)]
  hist_run <- hist_run[hist_run > 0L]             # 추세 위 구간은 분포에서 제외(0 이 분포를 지배)
  if (length(hist_run) < 24L) return(1)
  q <- stats::ecdf(hist_run)(run_now)
  g <- (q - 0.5) / 0.5
  g <- max(0, min(1, g))
  if (g <= 0) return(1)

  # ── ④ 종목 차등 — 그 달 보유 안 시장베타 횡단면 순위(높을수록 많이 줄인다)
  b  <- suppressWarnings(as.numeric(hold$beta))
  ok <- is.finite(b)
  if (sum(ok) < 2L) return(1)                     # 순위 불가 = 무개입
  rk <- rep(0.5, length(b))                       # 추정 없는 종목은 중앙
  rk[ok] <- (rank(b[ok], ties.method = "average") - 0.5) / sum(ok)

  # ── ⑤ 노출 = 1 − g·rk  (횡단면 평균 노출 1 − g/2)
  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - g * rk)))
}
