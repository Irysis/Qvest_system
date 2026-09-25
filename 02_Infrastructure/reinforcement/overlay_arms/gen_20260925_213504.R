#==============================================================================
# gen_20260925_213504 — 학습 예보의 횡단면 축을 '대입값' 에서 '사후 적재' 로 바꾼 트림 (v10.4 2026-09-25)
#   target cell: action = cross_sectional · state = ml (기전 지도 표적 칸 · 카탈로그 1종 대비 신설)
#
# ★기전
#   이 칸의 선행 arm(ml_dual_forecast_tilt)은 두 학습 예보로 채널 배율을 세우고, 각 보유의 예측
#   하방 산포 L = sqrt((max(0,dbeta)·s_m)^2 + (idio·kappa)^2) 의 **보유 안 순위**로 깎는다.
#   그 L 에 들어가는 적재는 **대입값(plug-in)** 이다 — dbeta 는 하락일 표본 위 회귀 기울기의 추정치이고
#   그 표집분산은 잔차분산/(하락측 관측수 · 하락측 시장분산) 이라 이름마다 수십 배 다르다.
#   순위 상단을 고른다는 것은 **추정오차의 최댓값을 고르는 일**이기도 하다: 표본이 얕거나 잔차가 크거나
#   시장과 덜 움직이는 이름은 적재가 실제로 높지 않아도 순위 상단에 오른다(승자의 저주). 반대쪽도 같다 —
#   음의 dbeta 를 헤지로 보존하는 규칙은 같은 오차를 반대 부호에서 믿는 것이다.
#   이 arm 은 순위에 넣는 값을 대입값에서 **사후평균**으로 바꾼다. 이름별 표집분산을 hold 로 세우고
#   (잔차분산 = ovol^2(1-bcorr^2) · 하락측 관측수 = n_obs × 하락 비중 · 하락측 시장분산 = 분산비 × 창 평균
#   시장분산), 횡단면 총분산에서 평균 표집분산을 뺀 적률법 신호분산으로 이름별 신뢰도 k_i = Vs/(Vs+Vb_i)
#   를 만들어 책 평균 쪽으로 당긴다. 두 성질이 여기서 나온다:
#     ① **순위가 바뀐다** — 공통 배율 축소(기존 arm 들의 n/(n+중앙n) 형태)는 단조변환이라 순위 램프에
#        원리적으로 보이지 않는다. 이름마다 다른 신뢰도만이 순서를 갈아친다.
#     ② **강도가 책의 신호대잡음에서 나온다** — 관측 차이가 전부 잡음이면 Vs=0 이라 전원이 책 평균으로
#        모여 적재 축의 차등을 스스로 접는다. 관측수만 보는 가중은 그 판단을 할 수 없다(중앙 이름은
#        책이 균질하든 흩어지든 언제나 0.5 를 받는다).
#   ★갈리는 인자는 하나다 — 상태층(학습쌍 i<=t-1 · 같은 4축 · 적합값 경험분포 중앙에서 시작하는 g ·
#   채널 배율 s_m·kappa)·순위 램프·예산(횡단면 평균 1-g/2)·감액 범위(0~g)를 선행과 같은 형태로 고정했다.
#   차이는 **순위에 넣은 값이 대입값인가 사후평균인가** 뿐이다.
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 e in [0,1]. (cross_sectional 은 표를 내야 처치 전달.)
#   H = 확장창(미래 행 없음). ★H$fwd 의 t 행은 미실현이라 읽지 않는다 — 학습쌍은 i <= t-1 만 쓴다.
#   ctx$hold = 보유 상태(beta · dbeta=하방베타 · ovol=자체변동 · bcorr=시장상관 · n_obs).
#   임의 상수 금지 — 개입 강도는 모형 적합값 경험분포, 하락측 비중·분산비·평균 시장분산은 확장창 실측,
#   축소 강도는 그 달 횡단면 적률, 종목 차등은 보유 내 순위에서 나온다.
#   보유 없음·표본 부족·적합 실패·차등 미성립 시 e <- 1(무개입). 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20260925_213504 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)
  if (t < 61L) return(1)                       # 학습쌍이 60개월 미만이면 모형을 말하지 않는다(선행과 같은 하한)

  # ── ① 상태층 — 선행 arm 과 같은 형태로 고정(갈리는 인자를 하나로 만들기 위해)
  idx  <- seq_len(t - 1L)                      # 결과가 실현된 과거쌍만
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

  fl <- as.numeric(stats::fitted(fitL)); fl <- fl[is.finite(fl)]
  if (length(fl) < 60L) return(1)
  g <- max(0, min(1, (stats::ecdf(fl)(pl) - 0.5) / 0.5))   # 모형 자기 적합값 분포의 중앙 = 개입 시작점
  if (g <= 0) return(1)

  s_m  <- max(0, pl)                           # 예측 체계 하방 손실폭(월 단위 수익률)
  dref <- stats::median(trd$disp)              # 학습 표본의 평상시 횡단면분산
  kap  <- if (is.finite(dref) && dref > 0) max(0, px) / dref else 1   # 산포 국면 배수(무차원)
  if (!is.finite(kap)) kap <- 1

  # ── ② 적재 추정의 표집분산 — Var(dbeta_i) = 잔차분산 / (하락측 관측수 · 하락측 시장분산)
  #    시장 쪽 인자는 전부 확장창 실측이다. 연율화 인자(252)는 분자·분모에서 상쇄되므로
  #    ovol(연율)과 평균 시장분산(연율^2)을 그대로 써도 무차원 분산이 나온다.
  nv  <- as.numeric(H$nav)
  rmk <- nv[-1L] / nv[-length(nv)] - 1         # 이미 실현된 월별 시장수익(직전 달까지)
  rmk <- rmk[is.finite(rmk)]
  if (length(rmk) < 60L) return(1)
  dnr <- rmk[rmk < 0]                          # 하락 월 — 부호는 하락측의 정의지 조정 문턱이 아니다
  if (length(dnr) < 12L) return(1)
  v_all <- stats::var(rmk)
  if (!is.finite(v_all) || v_all <= 0) return(1)
  p_dn <- length(dnr) / length(rmk)            # 하락측 관측 비중(공통 인자)
  phi  <- stats::var(dnr) / v_all              # 하락측 분산비 — 정규성 가정 대신 실측(공통 인자)
  if (!is.finite(phi) || phi <= 0) return(1)
  rv   <- as.numeric(H$rv60)
  vbar <- mean(rv * rv, na.rm = TRUE)          # 적재가 추정된 창의 평균 시장분산(연율^2)
  if (!is.finite(vbar) || vbar <= 0) return(1)

  db <- suppressWarnings(as.numeric(hold$dbeta))
  ov <- suppressWarnings(as.numeric(hold$ovol))
  bc <- suppressWarnings(as.numeric(hold$bcorr))
  nb <- suppressWarnings(as.numeric(hold$n_obs))
  res2 <- ov * ov * pmax(0, 1 - bc * bc)       # 잔차분산(연율^2)
  vb   <- res2 / (nb * p_dn * phi * vbar)      # 이름별 표집분산 — 관측수만이 아니라 잔차·상관도 들어온다
  vb[!is.finite(vb) | vb <= 0] <- NA_real_

  # ── ③ 사후 적재 — 경험적 베이즈(적률법). 신호분산 = 횡단면 총분산 − 평균 표집분산.
  #    k_i 가 이름마다 다르므로 순위가 바뀐다(공통 배율 축소는 단조변환이라 순위에 안 보인다).
  okb <- is.finite(db) & is.finite(vb)
  if (sum(okb) < 3L) return(1)
  m0 <- mean(db[okb])                          # 사전평균 = 그 달 책의 적재 평균
  vt <- stats::var(db[okb])
  vs <- if (is.finite(vt)) max(0, vt - mean(vb[okb])) else 0   # 음수 = 관측 차이가 전부 잡음 → 전원 책 평균
  den <- vs + vb
  kb  <- rep(0, length(db))
  kb[okb] <- ifelse(is.finite(den[okb]) & den[okb] > 0, vs / den[okb], 0)
  dbp <- rep(m0, length(db))                   # 추정 없는 이름 = 사전평균(유·불리 없음)
  dbp[okb] <- m0 + kb[okb] * (db[okb] - m0)

  # ── ④ 사후 고유변동 — 같은 원리를 로그 척도에서. Var(log sd) ~ 1/(2n) 라 이 축의 축소는 약하다
  #    (표준편차는 회귀 기울기보다 빨리 수렴한다 — 대입값을 흐리는 통로는 주로 적재다).
  idio <- ov * sqrt(pmax(0, 1 - bc * bc)) / sqrt(12)          # 월 단위 특이변동
  li   <- suppressWarnings(log(idio))
  oki  <- is.finite(li) & is.finite(nb) & nb > 1
  if (sum(oki) >= 3L) {
    vi  <- 1 / (2 * nb[oki])
    l0  <- mean(li[oki]); vti <- stats::var(li[oki])
    vsi <- if (is.finite(vti)) max(0, vti - mean(vi)) else 0
    ki  <- ifelse(vsi + vi > 0, vsi / (vsi + vi), 0)
    li[oki]   <- l0 + ki * (li[oki] - l0)
    idio[oki] <- exp(li[oki])
  }

  # ── ⑤ 순위 램프 — 선행과 같은 형태(같은 예산 1-g/2 · 같은 감액 범위 0~g). 갈린 것은 순위에 넣은 값 하나다.
  L   <- sqrt((pmax(0, dbp) * s_m)^2 + (idio * kap)^2)        # 예측 하방 산포(두 성분 직교합)
  okL <- is.finite(L)
  if (sum(okL) < 2L) return(1)                 # 순위를 매길 수 없으면 무개입
  r <- rep(0.5, length(L))                     # 값 없는 이름은 중앙 — 유·불리 어느 쪽도 아니다
  r[okL] <- (rank(L[okL], ties.method = "average") - 0.5) / sum(okL)

  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - g * r)))
}
