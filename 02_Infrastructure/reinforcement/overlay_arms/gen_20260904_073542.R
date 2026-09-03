#==============================================================================
# gen_20260904_073542 — 보유 체계-결합 상태 × 하방 기여 횡단면 트림 (v10.2 2026-09-04)
#   target cell: action = cross_sectional · state = holding_level (기전 지도 미측정 칸)
#
# ★기전
#   등가중 25종의 '실현' 분산은 보유들이 시장 공통인자에 얼마나 함께 묶여 있느냐로 정해진다.
#   보유들이 집단으로 시장에 결합(높은 R² = bcorr²)하고 하방으로 기울면(높은 dbeta), 책은
#   사실상 하나의 레버리지 시장베팅처럼 움직여 '25종'이라는 명목 분산이 허상이 된다.
#   이 상태는 낙폭(H$dd)이나 시장 횡단면분산(H$xs) 같은 시장 시계열이 아니라 **그 달 보유
#   자체**의 결합도에서 읽힌다 — 그래서 dbeta_tilt(상태=낙폭)·csd_idio_tilt(상태=분산)와
#   상태 원천이 다르다(state = holding_level). H 는 아예 읽지 않는다.
#   행동은 종목축이다: 책을 단일 시장베팅으로 만드는 종목에서 노출을 빼고, 진짜 분산원
#   (시장상관이 낮거나 음인 종목)은 보존한다. 횡단면 평균 노출 1−g/2 라 스칼라 축소(1−g)보다
#   덜 깎으면서 깎은 몫을 체계-하방 기여가 큰 쪽에 몰아준다.
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 e ∈ [0,1]. (cross_sectional 은 표를 내야 처치 전달.)
#   H = 확장창(미래 행 없음). 이 arm 은 H 를 읽지 않는다 — 상태가 보유 자체에 있기 때문이다.
#   ctx$hold = 보유 상태(beta · dbeta=하방베타 · ovol=자체변동 · bcorr=시장상관 · n_obs).
#   임의 상수 금지 — 개입 강도는 보유 체계위험 비중의 횡단면 중앙값, 종목 차등은 보유 내 순위에서.
#   보유 없음·표본 부족·추정 불가 시 e <- 1(무개입), 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20260904_073542 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)

  bc <- suppressWarnings(as.numeric(hold$bcorr))   # 시장상관 ∈ [-1,1] — 부호가 헤지를 가른다
  db <- suppressWarnings(as.numeric(hold$dbeta))   # 하방베타 — 떨어지는 장에서의 결합
  ov <- suppressWarnings(as.numeric(hold$ovol))    # 자체 변동 — 움직임의 규모
  n  <- nrow(hold)

  # ── ① 개입 강도 g — 이 책이 시장위험에 얼마나 포화됐나 (보유 자체의 상태)
  #    체계위험 비중 φ = bcorr² = 시장 공통성분이 설명하는 변동 몫(R²). 상관은 그 자체로
  #    [0,1] 비중이라 낙폭처럼 이력 센터링이 필요 없다 — 그 시점 보유 횡단면의 대표 수준을 쓴다.
  phi <- bc * bc
  phi <- phi[is.finite(phi)]
  if (length(phi) < 2L) return(1)                  # 표본 부족 → 무개입
  g <- stats::median(phi)                          # 책의 체계위험 포화도 ∈ [0,1] (상수 문턱 아님)
  g <- max(0, min(1, g))
  if (!is.finite(g) || g <= 0) return(1)           # 시장 결합이 없으면 깎을 체계위험도 없다

  # ── ② 종목 차등 r — 분산 불가능한 하방 기여의 보유 내 횡단면 순위
  #    체계 변동 = bcorr·ovol(자체변동 중 시장에 투영된 몫)을 하방베타로 가중.
  #    헤지(bcorr<0)는 s<0 → 최저 순위 → 최소 축소로 보존된다.
  s  <- db * (bc * ov)
  ok <- is.finite(s)
  if (sum(ok) < 2L) return(1)                      # 순위를 매길 수 없으면 무개입
  r  <- rep(0.5, n)                                # 추정 없는 종목은 중앙 — 유·불리 없음
  r[ok] <- (rank(s[ok], ties.method = "average") - 0.5) / sum(ok)

  # ── ③ 노출 = 1 − g·r  (횡단면 평균 ≈ 1 − g/2, 깎은 몫은 체계-하방 기여 큰 쪽에)
  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - g * r)))
}
