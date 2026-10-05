#==============================================================================
# gen_20261006_070654 — 책 2차형식 안의 위험기여 균형 트림 (v10.4 2026-10-06)
#   target cell: action = cross_sectional · state = ml (기전 지도 미측정 칸 — 측정 8 · 카탈로그 4)
#
# ★기전
#   이 칸의 선행 arm 들은 종목을 **단독 보유처럼** 잰다 — 이름마다 두 위험 채널을 직교합
#   L_i = sqrt((b_i·s)^2 + u_i^2) 으로 묶고, 그 수준의 보유 내 순위(또는 그 수준 대비 예산)로 깎는다.
#   그런데 n 종 책에서 고유분산은 n 으로 나뉘고 체계분산은 안 나뉜다. 단독 척도는 고유 채널을
#   책 기여 대비 약 n 배로 세우므로, 처분 순서가 체계 쪽으로 가야 할 만큼 가지 않는다.
#   이 arm 은 이름을 **책의 2차형식 안에서** 잰다. 학습 예보로 Σ 를 세우고(체계 = 이름 간 완전상관
#   b·b' · 고유 = 대각) 각 보유의 오일러 기여 몫 c_i (Σ c_i = 1)를 구해, 동일기여 기준 1/n 을
#   넘는 몫만 깎는다:  e_i = min(1, (1/n)/c_i) = min(1, w'Σw / (Σw)_i).
#   성질 둘이 여기서 나온다.
#     ① 예보의 **수준이 아니라 혼합**만 노출에 실린다 — 두 채널을 같은 배율로 키우면 c_i 가 불변이다.
#        모형은 "누가 책의 하방을 나르는가" 만 정하고 깊이는 정하지 않는다.
#     ② 깊이는 책의 **불균형**에서 온다 — 기여가 고르면 전원 e=1 로 스스로 침묵하고, 한 이름이
#        몰면 그 이름만 깊게 깎인다(평균 노출은 집중도가 허용하는 만큼만 내려간다).
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 e ∈ [0,1]. (cross_sectional 은 표를 내야 처치 전달.)
#   H = 확장창(미래 행 없음). ★H$fwd[t] 는 신호일에 미실현 — 읽지 않는다. 학습쌍은 i <= t-1 만
#     쓴다(그때 fwd[i] 와 xs[i+1] 의 관측 시점이 t 이하로 확정된다).
#   ctx$hold = 보유 상태(beta · dbeta=하방베타 · ovol=자체변동 · bcorr=시장상관 · n_obs).
#   임의 상수 금지 — 채널 혼합은 학습 예보, 산포 배수는 학습 표본 중앙값, 기준 기여는 책 크기 1/n,
#     표본 하한은 설계행렬 열 수(모수당 12개월)와 ctx$n_min 에서 온다.
#   비중은 전달되지 않으므로 추정 가능한 부분책을 등가중으로 본다. 추정 불가·적합 실패 = e <- 1.
#==============================================================================

overlay_expo_gen_20261006_070654 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)

  # ── ① 학습 표본 — 결과가 이미 실현된 과거쌍만 (i <= t-1)
  n_need <- 12L * 5L                             # 모수당 12개월 (절편 + 상태 4축) — 표본 하한
  nmin <- suppressWarnings(as.integer(ctx$n_min))
  if (length(nmin) == 1L && !is.na(nmin)) n_need <- max(n_need, nmin)
  if (t - 1L < n_need) return(1)
  idx <- seq_len(t - 1L)
  dn  <- pmax(0, -as.numeric(H$fwd[idx]))        # 익월 시장 하방 손실폭(상승월 = 0)
  trd <- data.frame(rv60 = as.numeric(H$rv60[idx]), dd = as.numeric(H$dd[idx]),
                    r252 = as.numeric(H$r252[idx]), xs = as.numeric(H$xs[idx]),
                    sv  = dn * dn,                       # 하방 2차모멘트 — 2차형식과 같은 분산 단위
                    dsp = as.numeric(H$xs[idx + 1L]))    # 익월 실현 횡단면산포 — i+1 <= t 라 관측됐다
  trd <- trd[stats::complete.cases(trd), , drop = FALSE]
  if (nrow(trd) < n_need) return(1)

  nd <- data.frame(rv60 = as.numeric(H$rv60[t]), dd = as.numeric(H$dd[t]),
                   r252 = as.numeric(H$r252[t]), xs = as.numeric(H$xs[t]))
  if (!all(is.finite(unlist(nd)))) return(1)

  fitS <- tryCatch(suppressWarnings(stats::lm(sv ~ rv60 + dd + r252 + xs, data = trd)),
                   error = function(z) NULL)
  fitD <- tryCatch(suppressWarnings(stats::lm(dsp ~ rv60 + dd + r252 + xs, data = trd)),
                   error = function(z) NULL)
  if (is.null(fitS) || is.null(fitD)) return(1)
  psv <- tryCatch(suppressWarnings(as.numeric(stats::predict(fitS, nd))), error = function(z) NA_real_)
  pdp <- tryCatch(suppressWarnings(as.numeric(stats::predict(fitD, nd))), error = function(z) NA_real_)
  if (!is.finite(psv) || !is.finite(pdp)) return(1)

  # ── ② 두 채널의 예보 — 체계는 절대 수준(하방 반분산), 고유는 평상시 대비 산포 배수(무차원)
  vsys <- max(0, psv)                            # 선형적합이 음을 부르면 그 달 체계 채널은 0
  dref <- stats::median(trd$dsp)
  rho  <- if (is.finite(dref) && dref > 0) max(0, pdp) / dref else 1
  if (!is.finite(rho)) rho <- 1

  # ── ③ 책의 2차형식 — 체계는 이름 간 완전상관(b·b'), 고유는 대각. 비중은 등가중으로 본다
  bdn <- suppressWarnings(as.numeric(hold$dbeta))
  ovl <- suppressWarnings(as.numeric(hold$ovol))
  bcr <- suppressWarnings(as.numeric(hold$bcorr))
  bld <- pmax(0, bdn)                                          # 하방베타 음 = 체계 기여 0 → 헤지 보존
  uid <- ovl * sqrt(pmax(0, 1 - bcr * bcr)) / sqrt(12) * rho   # 월 단위 고유변동(학습 산포 국면 반영)
  ok  <- is.finite(bld) & is.finite(uid)
  ne  <- sum(ok)
  if (ne < 2L) return(1)                         # 기여를 비교할 수 없으면 무개입
  bl  <- bld[ok]
  ui2 <- uid[ok] * uid[ok]
  wgt <- 1 / ne                                  # 비중 미전달 — 추정 가능한 부분책을 등가중으로 본다
  blk <- mean(bl)                                # 책의 체계 적재 w'b
  vbk <- vsys * blk * blk + mean(ui2) * wgt      # 책의 예측 하방분산 w'Σw — 고유 쪽만 n 으로 나뉜다
  if (!is.finite(vbk) || vbk <= 0) return(1)

  # ── ④ 노출 = 동일기여 몫 대비 초과분만 깎는다 (증액 없음 · 기여가 고르면 전원 1)
  mrg <- vsys * bl * blk + ui2 * wgt             # 이름별 한계기여 (Σw)_i — 책 크기가 두 채널을 가른다
  ex  <- pmax(0, pmin(1, vbk / mrg))
  fin <- is.finite(ex)
  if (!any(fin)) return(1)
  data.table::data.table(Ticker = as.character(hold$Ticker[ok][fin]), e = ex[fin])
}
