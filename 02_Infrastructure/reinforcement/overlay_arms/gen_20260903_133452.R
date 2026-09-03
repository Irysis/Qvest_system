#==============================================================================
# gen_20260903_133452 — 횡단면분산 상태 × 특이변동 횡단면 틸트 (v10.2 2026-09-03)
#   target cell: action = cross_sectional · state = dispersion (기전 지도 미측정 칸)
#
# ★기전
#   횡단면분산(cross-sectional dispersion)이 높은 국면은 종목 간 결과가 크게 벌어지는 국면이다.
#   그 벌어짐을 실제로 키우는 건 시장 공통성분이 아니라 각 종목의 **특이(idiosyncratic) 변동**이다
#   (총변동 = 시장성분 + 특이성분, 특이몫 = 1 − R^2 = 1 − bcorr^2). 그래서 이 arm 은 상태를
#   시장 횡단면분산(H$xs)으로 읽되, 축소는 그 달 보유 안에서 **특이변동 기여가 큰 종목**에 몰아준다.
#   dbeta_tilt 와 행동 축(종목별 차등 축소)은 같지만 겨누는 상태가 다르다 — 저기는 낙폭, 여기는 분산.
#   총노출 스칼라 축소가 분산 국면에서 상방·하방을 같은 비율로 깎는 대칭을 종목축에서 깬다:
#   횡단면 평균 노출은 1 − g/2 라 스칼라판(1 − g)보다 덜 깎이고, 줄인 몫은 특이변동 큰 쪽에 쏠린다.
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 e ∈ [0,1]. (cross_sectional 은 표를 내야 처치가 전달된다.)
#   H = 확장창(미래 행 없음). H$fwd 의 t 행은 미실현이므로 읽지 않는다.
#   H$xs = 시장 횡단면분산 시계열. ctx$hold = 보유 상태(ovol = 자체변동 · bcorr = 시장상관 · …).
#   임의 상수 금지 — 개입 강도는 분산의 자기 이력 경험분포에서, 종목 차등은 그 달 보유 안 순위에서.
#   추정 불가·표본 부족 시 e <- 1(무개입), 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20260903_133452 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)

  # ── ① 개입 강도 g — 지금 횡단면분산이 자기 이력에서 얼마나 높은가 (확장창 경험분포)
  xs_hist <- H$xs[is.finite(H$xs)]
  xs_now  <- H$xs[t]
  if (!is.finite(xs_now) || length(xs_hist) < 24L) return(1)
  q <- stats::ecdf(xs_hist)(xs_now)            # 0~1. 경험분포 중앙 위에서만 개입한다
  g <- (q - 0.5) / 0.5                         # 중앙 = 개입 시작점(데이터가 정한다, 상수 문턱 아님)
  g <- max(0, min(1, g))
  if (g <= 0) return(1)

  # ── ② 종목 차등 r — 그 달 보유 안 특이변동 기여의 횡단면 순위
  ovol  <- suppressWarnings(as.numeric(hold$ovol))
  bcorr <- suppressWarnings(as.numeric(hold$bcorr))
  bc    <- pmin(1, pmax(-1, bcorr))            # 상관 범위 밖 값 방어
  idio  <- ovol * sqrt(pmax(0, 1 - bc * bc))   # 특이변동 = 총변동 × sqrt(1 − R^2)
  s     <- idio                                # 1순위 신호 = 특이변동 기여
  ok    <- is.finite(s)
  if (sum(ok) < 2L) { s <- ovol; ok <- is.finite(s) }  # bcorr 결측이면 총변동으로 후퇴
  if (sum(ok) < 2L) return(1)                  # 순위를 매길 수 없으면 무개입

  r <- rep(0.5, length(s))                     # 추정 없는 종목은 중앙 — 유리·불리 어느 쪽도 아니다
  r[ok] <- (rank(s[ok], ties.method = "average") - 0.5) / sum(ok)

  # ── ③ 노출 = 1 − g·r  (횡단면 평균 ≈ 1 − g/2, 축소 몫은 특이변동 큰 쪽에)
  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - g * r)))
}
