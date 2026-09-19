#==============================================================================
# b5gen_trend_ladder_gate_1 — 지평 사다리(1·3·6·12개월) 후행수익 백분위로 정하는 총노출 게이트
#                             (표적 칸: action = scalar_exposure · state = trend)
#
# ★기전 (사전 선언 — 특정 시기를 보고 만든 규칙이 아니다)
#   추세를 스칼라로 소비하는 기존 arm 은 지평 하나(12개월)의 부호 하나를 본다. 부호는 하락이
#   시작되고 여러 달 뒤에야 뒤집히고, 바닥을 지나고도 여러 달 음으로 남는다 — 진입도 늦고
#   해제도 늦다. 지속성(추세 아래 연속 개월수) 계열은 해제가 더 늦다.
#   이 arm 은 nav 한 원천에서 1·3·6·12개월 후행수익을 뽑아 각 지평을 자기 이력의 확장창
#   경험분포 백분위로 무차원화하고, 지평 평균 백분위가 자기 이력 중앙 아래인 만큼만 총노출을
#   줄인다. 단기 지평은 하락 초입에 먼저 내려가고 반등 초입에 먼저 올라오며, 장기 지평은 침식이
#   여러 달 이어질 때만 함께 내려간다 — 그래서 급락에는 빠르게 걸리고 빠르게 풀리며, 침식에는
#   네 지평이 함께 낮아져 오래 걸린다. 같은 상태를 종목 하방채널 순위로 소비하는
#   arm(trend_horizon_split_tilt)은 이미 있다 — 이 arm 은 총노출 하나로 소비한다(소비 지점의 짝).
#   같은 g 를 예산으로 받아 잔차 축에 집중 배분하는 종목별 arm 과는 예산이 같고 배분만 다르다.
#   반증 조건: 1개월 지평이 잡음이라 한 달 지연에 지속성 계열보다 약하다 — lag-1 에서 무너지면
#   이 게이트의 개선은 짧은 지평의 동월 정보에서 온 것이다.
#
# ★계약
#   반환 = 스칼라 e ∈ [0,1] (표적이 scalar_exposure 이므로 종목별 표를 내지 않는다).
#   H = 확장창(t 행까지 · 미래 행 없음) · t 행이 미실현인 익월 수익 열은 읽지 않는다.
#   임의 상수 금지 — 개입 시작점은 각 지평 수익의 자기 이력 경험분포 중앙. 지평 집합(1·3·6·12)은
#   관측 창이지 문턱이 아니다. 추정 불가·표본 부족이면 e <- 1(무개입). 오류를 던지지 않는다.
#   외부 데이터 없음 — ctx$hold 도 읽지 않는다(보유 구성과 무관한 순수 시장 상태 층).
#==============================================================================

overlay_expo_b5gen_trend_ladder_gate_1 <- function(H, t, ctx) {
  nmin <- suppressWarnings(as.integer(ctx$n_min))
  if (length(nmin) != 1L || !is.finite(nmin) || nmin < 12L) nmin <- 24L

  tt <- suppressWarnings(as.integer(t))
  if (length(tt) != 1L || !is.finite(tt)) return(1)
  tt <- min(tt, nrow(H))
  if (tt < 13L) return(1)                      # 최장 지평(12개월) 하나도 못 만든다

  # ── ① 추세 사다리 — 지평별 후행수익을 nav 한 원천에서 뽑는다(원천을 섞지 않아야 백분위가 비교된다)
  nv <- suppressWarnings(as.numeric(H$nav))[seq_len(tt)]
  nv[!is.finite(nv) | nv <= 0] <- NA_real_
  if (!is.finite(nv[tt])) return(1)            # 지금 달 추세가 결측 = 개입 근거 없음

  hz <- c(1L, 3L, 6L, 12L)                     # 관측 창(월)이지 문턱이 아니다
  qv <- numeric(0)
  for (k in hz) {
    if (tt <= k + nmin) next                   # 그 지평의 경험분포를 세울 표본이 없다
    tr   <- c(rep(NA_real_, k), nv[(k + 1L):tt] / nv[seq_len(tt - k)] - 1)
    now  <- tr[tt]
    hist <- tr[is.finite(tr)]
    if (!is.finite(now) || length(hist) < nmin) next
    qv <- c(qv, stats::ecdf(hist)(now))        # 0~1. 지평마다 자기 이력 안에서의 위치
  }
  if (length(qv) < 2L) return(1)               # 지평 구조가 안 서면 이 arm 의 일이 아니다

  # ── ② 개입 강도 g — 지평 평균 백분위가 자기 이력 중앙 아래일 때만(데이터가 정한 시작점)
  qbar <- mean(qv)
  if (!is.finite(qbar)) return(1)
  g <- (0.5 - qbar) / 0.5
  g <- max(0, min(1, g))
  if (g <= 0) return(1)

  # ── ③ 총노출 = 1 − g — 전 보유에 같은 값(배분 균등). 증액은 없다.
  max(0, min(1, 1 - g))
}
