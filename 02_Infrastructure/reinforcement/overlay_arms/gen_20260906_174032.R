#==============================================================================
# gen_20260906_174032 — 학습 예보 2종이 회전시키는 횡단면 트림 (v10.4 2026-09-06)
#   target cell: action = cross_sectional · state = ml (기전 지도 미측정 칸)
#
# ★기전
#   기존 cross_sectional arm 3종(dbeta_tilt=낙폭 · csd_idio_tilt=분산 · holdlvl_syscrowd=보유결합)은
#   **축이 고정**이다 — 상태가 강도 g 만 정하고, 어느 종목을 깎을지의 순서는 언제나 같은 한 열
#   (dbeta 또는 특이변동)에서 나온다. 그래서 국면이 바뀌어도 책 안의 처분 순서는 안 바뀐다.
#   이 arm 은 학습된 예보가 **순서 자체**를 돌린다.
#   확장창 과거쌍(신호일 t-1 이하, 결과가 이미 실현된 쌍만)으로 두 모형을 적합한다:
#     ① 익월 시장 하방 손실폭  loss = max(0, -fwd)   → 예보 s_m (체계 충격의 크기)
#     ② 익월 실현 횡단면분산   disp = xs(다음 행)     → 예보 s_x (특이 산포의 크기)
#   각 보유의 예측 하방 산포를 두 성분의 직교합으로 세운다:
#     L_i = sqrt( (max(0,dbeta_i)·s_m)^2 + (idio_i·kappa)^2 ),  idio_i = ovol_i·sqrt(1-bcorr_i^2)/sqrt(12)
#   모형이 체계 충격을 크게 부르는 달에는 dbeta 가 순서를 지배하고, 조용하지만 종목이 흩어지는
#   달에는 특이변동이 지배한다. 하방베타가 음인 종목(하락장에서 버는 진짜 헤지)은 체계 성분이
#   0 으로 떨어져 보존된다. 개입 강도 g 는 ①모형의 오늘 예보가 **자기 적합값 분포**에서
#   어디인가로만 정해진다 — 상수 문턱이 아니라 학습 표본 내 보정 분위다.
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 e ∈ [0,1]. (cross_sectional 은 표를 내야 처치 전달.)
#   H = 확장창(미래 행 없음). ★H$fwd[t] 와 H$xs[t+1] 은 미실현이라 읽지 않는다 — 학습쌍은
#     i <= t-1 만 쓴다(그때 fwd[i]·xs[i+1] 의 관측 시점이 t 이하로 확정된다).
#   ctx$hold = 보유 상태(beta · dbeta=하방베타 · ovol=자체변동 · bcorr=시장상관 · n_obs).
#   임의 상수 금지 — 강도는 적합값 경험분포, 분산 배수는 학습 표본 중앙값, 종목 차등은 보유 내 순위.
#   보유 없음·표본 부족·적합 실패 시 e <- 1(무개입), 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20260906_174032 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)
  if (t < 61L) return(1)                       # 학습쌍이 60개월 미만이면 모형을 말하지 않는다

  # ── ① 학습 표본 — 결과가 실현된 과거쌍만 (i <= t-1)
  idx  <- seq_len(t - 1L)
  loss <- pmax(0, -as.numeric(H$fwd[idx]))     # 익월 시장 손실폭(상승월 = 0)
  disp <- as.numeric(H$xs[idx + 1L])           # 익월 실현 횡단면분산 — i+1 <= t 라 관측됐다
  trd  <- data.frame(rv60 = as.numeric(H$rv60[idx]), dd   = as.numeric(H$dd[idx]),
                     r252 = as.numeric(H$r252[idx]), xs   = as.numeric(H$xs[idx]),
                     loss = loss,                    disp = disp)
  trd <- trd[stats::complete.cases(trd), , drop = FALSE]
  if (nrow(trd) < 60L) return(1)

  nd <- data.frame(rv60 = as.numeric(H$rv60[t]), dd   = as.numeric(H$dd[t]),
                   r252 = as.numeric(H$r252[t]), xs   = as.numeric(H$xs[t]))
  if (!all(is.finite(unlist(nd)))) return(1)

  fitL <- tryCatch(suppressWarnings(stats::lm(loss ~ rv60 + dd + r252 + xs, data = trd)),
                   error = function(z) NULL)
  fitX <- tryCatch(suppressWarnings(stats::lm(disp ~ rv60 + dd + r252 + xs, data = trd)),
                   error = function(z) NULL)
  if (is.null(fitL) || is.null(fitX)) return(1)
  pl <- tryCatch(suppressWarnings(as.numeric(stats::predict(fitL, nd))), error = function(z) NA_real_)
  px <- tryCatch(suppressWarnings(as.numeric(stats::predict(fitX, nd))), error = function(z) NA_real_)
  if (!is.finite(pl) || !is.finite(px)) return(1)

  # ── ② 개입 강도 g — 오늘 예보가 모형 자기 적합값 분포에서 어디인가(학습 표본 내 보정)
  fl <- as.numeric(stats::fitted(fitL)); fl <- fl[is.finite(fl)]
  if (length(fl) < 60L) return(1)
  q <- stats::ecdf(fl)(pl)                     # 0~1. 모형이 평소보다 나쁘다고 부를 때만 개입한다
  g <- max(0, min(1, (q - 0.5) / 0.5))         # 중앙 = 개입 시작점(모형이 정한다, 상수 문턱 아님)
  if (g <= 0) return(1)

  # ── ③ 축 회전 — 두 예보의 상대 크기가 그 달의 랭킹 축을 정한다
  s_m  <- max(0, pl)                           # 예측 체계 하방 손실폭(월 단위 수익률)
  dref <- stats::median(trd$disp)              # 학습 표본의 평상시 횡단면분산
  kap  <- if (is.finite(dref) && dref > 0) max(0, px) / dref else 1   # 분산 국면 배수(무차원)
  if (!is.finite(kap)) kap <- 1

  db <- suppressWarnings(as.numeric(hold$dbeta))
  ov <- suppressWarnings(as.numeric(hold$ovol))
  bc <- suppressWarnings(as.numeric(hold$bcorr))
  sysd <- pmax(0, db) * s_m                                   # 헤지(하방베타 음)는 체계 기여 0 → 보존
  idio <- ov * sqrt(pmax(0, 1 - bc * bc)) / sqrt(12)          # 월 단위 특이변동
  L    <- sqrt(sysd * sysd + (idio * kap) * (idio * kap))     # 예측 하방 산포(두 성분 직교합)

  ok <- is.finite(L)
  if (sum(ok) < 2L) return(1)                  # 순위를 매길 수 없으면 무개입
  r <- rep(0.5, length(L))                     # 추정 없는 종목은 중앙 — 유·불리 없음
  r[ok] <- (rank(L[ok], ties.method = "average") - 0.5) / sum(ok)

  # ── ④ 노출 = 1 − g·r  (횡단면 평균 ≈ 1 − g/2, 깎은 몫은 그 달 모형이 지목한 축의 상위에)
  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - g * r)))
}
