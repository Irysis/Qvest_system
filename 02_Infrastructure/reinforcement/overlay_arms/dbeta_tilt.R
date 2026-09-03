#==============================================================================
# dbeta_tilt — 하방베타 횡단면 틸트 오버레이 (v10.2 2026-09-03 · 첫 cross_sectional arm)
#
# ★기전
#   기존 오버레이는 월별 스칼라 하나로 총노출을 깎는다 — 전 종목을 같은 비율로 줄이므로
#   하락과 회복이 같은 비율로 함께 줄어든다. 시장 상태 예측기가 가진 정보는 주로 분산이고
#   방향이 아니므로, 시간축 타이밍만으로는 이 대칭을 깨기 어렵다.
#   이 arm 은 비대칭을 **종목축**에서 만든다: 같은 스트레스 국면에서 하방베타가 높은 종목은
#   많이, 낮은 종목은 적게 줄인다. 횡단면 평균 노출은 1 − g/2 라 스칼라판(1 − g)보다 덜 깎이고,
#   줄인 몫은 하방 기여가 큰 쪽에 몰린다.
#
# ★계약
#   반환 = 스칼라 e ∈ [0,1]  또는  data.table(Ticker, e) — 종목별 노출.
#   H = .M[seq_len(t)] 확장창(미래 행 없음). H$fwd 는 t 행이 미실현이므로 읽지 않는다.
#   ctx$hold = 그 달 보유 종목의 확장창 상태(beta · dbeta · ovol · bcorr · n_obs).
#   임의 상수 금지 — 개입 강도는 낙폭의 자기 이력 경험분포에서, 종목 차등은 그 달 보유 안의
#   횡단면 순위에서 나온다. 추정 불가 시 e <- 1(무개입).
#==============================================================================

overlay_expo_dbeta_tilt <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)

  # ── ① 개입 강도 g — 지금 낙폭이 자기 이력에서 얼마나 깊은가 (확장창 경험분포)
  dd_hist <- H$dd[is.finite(H$dd)]
  dd_now  <- H$dd[t]
  if (!is.finite(dd_now) || length(dd_hist) < 24L) return(1)
  q <- stats::ecdf(dd_hist)(dd_now)            # 0~1. 경험분포 중앙 위에서만 개입한다
  g <- (q - 0.5) / 0.5                         # 중앙 = 개입 시작점(데이터가 정한다, 상수 문턱 아님)
  g <- max(0, min(1, g))
  if (g <= 0) return(1)

  # ── ② 종목 차등 r — 그 달 보유 안에서 하방베타 횡단면 순위
  b  <- suppressWarnings(as.numeric(hold$dbeta))
  ok <- is.finite(b)
  if (sum(ok) < 2L) return(1)                  # 순위를 매길 수 없으면 무개입
  r <- rep(0.5, length(b))                     # 추정 없는 종목은 중앙 — 유리·불리 어느 쪽도 아니다
  r[ok] <- (rank(b[ok], ties.method = "average") - 0.5) / sum(ok)

  # ── ③ 노출 = 1 − g·r
  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - g * r)))
}
