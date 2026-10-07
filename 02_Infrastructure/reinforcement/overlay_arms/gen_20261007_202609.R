#==============================================================================
# gen_20261007_202609 — 이름의 '하방 대비 상방' 교환비로 세우는 횡단면 트림 (v10.4 2026-10-07)
#   target cell: action = cross_sectional · state = ml (기전 지도 표적 칸 · 측정 8 · 카탈로그 5 · 미포화)
#
# ★기전
#   이 칸의 선행 5종은 전부 **한쪽만** 잰다. 이름의 처분 순서가 예측 하방 산포(직교합 L)든, 사후축소
#   적재든, 꼬리초과확률이든, 위험예산 대비 배율이든, 책 2차형식의 기여 몫이든 — 커지면 깎는다.
#   그래서 노출을 깎을 때 그 이름이 같이 내놓는 **상방 참여**는 어디에도 들어오지 않는다. 오버레이의
#   목적이 비대칭인데 순서는 한쪽 척도의 단조함수다: 하방이 큰 이름은 보통 상방도 크므로 하방 상위를
#   깎는 일은 상방 상위를 깎는 일이기도 하다(dbeta_tilt 머리말이 시간축에서 문제삼은 '하락과 회복이
#   같은 비율로 함께 줄어듦' 이 종목축에서 그대로 반복된다).
#   이 arm 은 순서를 **교환비**로 세운다 — 이름마다 하방 부분적률 D_i 와 상방 부분적률 U_i 를 따로
#   추정해 Ω_i = U_i / D_i 의 보유 내 순위로 깎는다. 깎이는 쪽은 '위험이 큰 이름' 이 아니라 **같은
#   하방을 사면서 상방을 가장 적게 돌려주는 이름**이다.
#   세 자리가 그 때문에 바뀐다.
#     ① **상승측 적재를 식별한다** — 엔진이 주는 것은 전구간 적재 beta 와 하락측 적재 dbeta 뿐이다.
#        전구간 적재는 두 측면의 분산가중 평균이므로 beta = w·dbeta + (1−w)·b_up 에서
#        b_up = (beta − w·dbeta)/(1−w) 가 식별된다(w = 하락측이 나르는 시장 분산 몫 · 확장창 월별
#        시장 경로에서 실측). 선행 중 상방을 쓴 arm 은 하나뿐이고 그마저 전구간 적재를 상승 반응으로
#        그대로 썼다 — w=0 특수해다. 그래서 선행의 순서는 (dbeta, 고유변동)만의 함수였고, 이 arm 은
#        같은 dbeta·고유변동을 가진 두 이름을 beta 가 갈라놓는다.
#     ② **학습 머리가 짝을 이룬다** — 상태 4축(이 칸 공통으로 고정)에서 익월 시장의 **하방 부분적률**
#        max(0,−fwd) 와 **상방 부분적률** max(0,fwd) 를 각각 적합한다. 선행은 하방(또는 그 2차모멘트)과
#        횡단면산포를 배웠다 — 상방을 배우지 않았으니 교환비를 만들 재료 자체가 없었다.
#     ③ **예보는 자격만큼만 실린다** — 두 머리는 LOO(해트 보정) 제곱오차를 무조건부 평균과 대조해
#        신뢰도 θ = max(0, 1 − SSE_cond/SSE_mean) 를 벌고, 예보는 그만큼만 평균에서 떨어진다.
#        θ=0 이면 무조건부로 수축하고 경로가 상수가 되어 아래 깊이가 스스로 0 이 된다(자기 소멸).
#   고유 채널은 분자·분모에 같은 모양으로 들어간다 — 고유변동이 지배하는 이름의 Ω 는 표준화 충격의
#   상·하 평균비로 수렴해 횡단면 중앙에 모이고, 갈리는 것은 **체계 비대칭**뿐이다(선행에서는 고유변동이
#   언제나 깎는 쪽으로만 작용했다).
#   예산·램프는 이 칸의 램프 계열과 같게 고정했다(e = 1 − g·r · 횡단면 평균 1 − g/2) — 갈리는 인자를
#   '순서를 만든 양' 하나로 좁히기 위해서다. 깊이 g 만 교환비로 denominate 한다: 오늘의 시장 교환비가
#   자기 적합 경로의 **아래쪽 절반**에 있을 때만 켜진다(경로 중앙 = 개입 시작점).
#
# ★가정(정직하게 적는다)
#   ①식별식은 근사다 — beta·dbeta 는 일별 표본 위 회귀이고 w 는 월별 경로에서 재므로 빈도가 다르고,
#     두 측면의 평균 오프셋 항을 버렸다. w=0 후퇴(선행의 선택)가 그 근사의 한 극단이다.
#   ②부분적률을 체계·고유로 나눠 더한 것은 합의 한쪽 적률보다 크다(E[max(0,−(A+B))] ≤ 둘의 합) —
#     분자·분모에 같은 방향으로 실리므로 비에서 상당 부분 상쇄된다.
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 e in [0,1]. (cross_sectional 은 표를 내야 처치 전달.)
#   H = 확장창(미래 행 없음). ★H$fwd 의 t 행은 신호일에 미실현 — 읽지 않는다. 학습쌍은 i <= t−1 만
#     쓴다(그때 fwd[i] 의 관측 시점이 t 이하로 확정된다).
#   ctx$hold = 보유 상태(beta · dbeta=하락측 적재 · ovol=자체변동 · bcorr=시장상관 · n_obs).
#   임의 상수 금지 — 분산 몫 w·표준화 충격의 상하 모양·능형 강도(차원/(차원+표본))·신뢰도·개입 시작점
#     (경로 중앙)·표본 하한(모수당 12개월·ctx$n_min) 전부 그 시점 확장창에서 나온다.
#   보유 없음·표본 부족·적합 실패·교환비 2종 미만 = e <- 1(무개입). 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20261007_202609 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)
  if (t < 61L) return(1)                         # 학습쌍 60개월 미만이면 모형을 말하지 않는다(칸 공통 하한)

  # ── ① 학습쌍 — 결과가 실현된 과거쌍만(i <= t−1). t 행의 익월 수익은 읽지 않는다
  idx <- seq_len(t - 1L)
  trn <- cbind(as.numeric(H$rv60[idx]), as.numeric(H$dd[idx]),
               as.numeric(H$r252[idx]), as.numeric(H$xs[idx]), as.numeric(H$fwd[idx]))
  trn <- trn[stats::complete.cases(trn), , drop = FALSE]
  nn  <- nrow(trn)
  nfl <- 60L                                     # 모수(절편 + 상태 4축)당 12개월
  nmn <- suppressWarnings(as.integer(ctx$n_min))
  if (length(nmn) == 1L && !is.na(nmn)) nfl <- max(nfl, nmn)
  if (nn < nfl) return(1)
  nax <- ncol(trn) - 1L
  Xm  <- trn[, seq_len(nax), drop = FALSE]
  fwv <- trn[, ncol(trn)]

  mu  <- colMeans(Xm)
  sdv <- vapply(seq_len(nax), function(j) stats::sd(Xm[, j]), numeric(1))
  if (any(!is.finite(mu)) || any(!is.finite(sdv)) || any(sdv <= 0)) return(1)
  Zm  <- sweep(sweep(Xm, 2, mu, "-"), 2, sdv, "/")      # 표준화 — 4축은 서로 겹친다(변동성 창·산포)
  znw <- (c(as.numeric(H$rv60[t]), as.numeric(H$dd[t]),
            as.numeric(H$r252[t]), as.numeric(H$xs[t])) - mu) / sdv
  if (any(!is.finite(Zm)) || any(!is.finite(znw))) return(1)

  # ── ② 능형 적합 + LOO 신뢰도 — 겹친 축에서도 적합이 정의되게 하고, 표본외에서 번 만큼만 예보를 쓴다
  lam <- nax / (nax + nn)                        # 능형 강도 = 차원/(차원+표본) — 상수가 아니라 표본이 정한다
  gxx <- vapply(seq_len(nax), function(j)
           vapply(seq_len(nax), function(k) sum(Zm[, j] * Zm[, k]), numeric(1)), numeric(nax))
  if (any(!is.finite(gxx))) return(1)
  Ai  <- tryCatch(solve(gxx + diag(lam * mean(diag(gxx)), nax)), error = function(z) NULL)
  if (is.null(Ai) || any(!is.finite(Ai))) return(1)
  hdg <- 1 / nn + rowSums((Zm %*% Ai) * Zm)      # 해트 대각(중심화 절편 1/n 포함) — LOO 보정에 쓴다
  if (any(!is.finite(hdg))) return(1)

  fit_pm <- function(yv) {                       # 한 머리 — 적합 경로 · 오늘 예보(신뢰도 축소 후)
    ybr <- mean(yv)
    cfv <- as.numeric(Ai %*% vapply(seq_len(nax), function(j) sum(Zm[, j] * (yv - ybr)), numeric(1)))
    ftv <- ybr + as.numeric(Zm %*% cfv)
    rsl <- (yv - ftv) / pmax(1 - hdg, .Machine$double.eps)   # LOO 잔차(해트 보정)
    rs0 <- (yv - ybr) / (1 - 1 / nn)                         # 무조건부 평균의 LOO 잔차
    s1  <- sum(rsl * rsl); s0 <- sum(rs0 * rs0)
    th  <- if (is.finite(s1) && is.finite(s0) && s0 > 0) max(0, min(1, 1 - s1 / s0)) else 0
    if (!(th > 0)) return(list(path = rep(ybr, nn), now = ybr))   # 표본외에서 번 것이 없으면 무조건부로 수축
    cnd <- ybr + sum(cfv * znw)
    list(path = ybr + th * (ftv - ybr), now = ybr + th * (cnd - ybr))
  }
  hdn <- fit_pm(pmax(0, -fwv))                   # 익월 시장 하방 부분적률 E[max(0,−r)]
  hup <- fit_pm(pmax(0,  fwv))                   # 익월 시장 상방 부분적률 E[max(0, r)]
  mdn <- max(0, hdn$now); mup <- max(0, hup$now)
  if (!is.finite(mdn) || !is.finite(mup)) return(1)

  # ── ③ 깊이 g — 오늘의 시장 교환비가 자기 적합 경로의 아래쪽 절반에 있을 때만 켜진다
  eps <- .Machine$double.eps
  rpt <- hup$path / pmax(hdn$path, eps)
  rpt <- rpt[is.finite(rpt)]
  rnw <- mup / max(mdn, eps)
  if (length(rpt) < 24L || !is.finite(rnw)) return(1)
  g <- max(0, min(1, (0.5 - stats::ecdf(rpt)(rnw)) / 0.5))      # 경로 중앙 = 개입 시작점(상수 문턱 아님)
  if (g <= 0) return(1)

  # ── ④ 시장 경로 실측 — 하락측이 나르는 분산 몫 w(상승측 적재 식별) · 표준화 충격의 상·하 모양
  nv  <- as.numeric(H$nav)
  rmk <- nv[-1L] / nv[-length(nv)] - 1           # 신호일까지 실현된 월별 시장수익(미래 아님)
  rmk <- rmk[is.finite(rmk)]
  if (length(rmk) < 60L) return(1)
  msd <- stats::sd(rmk)
  if (!is.finite(msd) || msd <= 0) return(1)
  zsh <- (rmk - mean(rmk)) / msd                 # 표준화 충격 — 정규 가정 대신 실측 모양
  cdn <- mean(pmax(0, -zsh)); cup <- mean(pmax(0, zsh))
  if (!is.finite(cdn) || !is.finite(cup) || cdn <= 0) return(1)
  dnr <- rmk[rmk < 0]                            # 하락 월 — 부호는 하락의 정의지 조정 문턱이 아니다
  if (length(dnr) < 12L) return(1)
  vall <- stats::var(rmk); vdn <- stats::var(dnr)
  if (!is.finite(vall) || vall <= 0 || !is.finite(vdn)) return(1)
  wdn <- (length(dnr) / length(rmk)) * (vdn / vall)             # 하락측 관측 비중 × 하락측 분산비
  if (!is.finite(wdn)) return(1)
  wdn <- max(0, min(1 - 1 / length(rmk), wdn))   # 1 에 붙으면 상승측 적재가 식별되지 않는다

  # ── ⑤ 두 측면 적재 — 하락측은 주어지고, 상승측은 전구간 적재에서 식별한다
  bdn <- suppressWarnings(as.numeric(hold$dbeta))
  bal <- suppressWarnings(as.numeric(hold$beta))
  ovl <- suppressWarnings(as.numeric(hold$ovol))
  bcr <- suppressWarnings(as.numeric(hold$bcorr))
  gpd <- !is.finite(bdn) & is.finite(bal)
  bdn[gpd] <- bal[gpd]                           # 하락측 적재 결측 = 전구간 적재로 후퇴(그 이름은 비대칭 0)
  bup <- (bal - wdn * bdn) / (1 - wdn)           # 식별식 — 전구간 적재 = 두 측면의 분산가중 평균
  gpu <- !is.finite(bup)
  bup[gpu] <- bal[gpu]                           # 식별 불가 = 전구간 적재로 후퇴(w→0 판)
  sig <- ovl * sqrt(pmax(0, 1 - bcr * bcr)) / sqrt(12)         # 월 단위 고유변동
  sig[!is.finite(sig)] <- 0                      # 고유 채널 추정 없음 = 체계 채널로만 잰다
  dmg <- pmax(0, bdn) * mdn + sig * cdn          # 하방 부분적률 — 음의 하락측 적재(헤지)는 체계 기여 0
  prt <- pmax(0, bup) * mup + sig * cup          # 상방 부분적률 — 음의 상승측 적재는 참여 0
  okn <- is.finite(dmg) & is.finite(prt) & dmg > 0
  if (sum(okn) < 2L) return(1)                   # 교환비를 비교할 수 없으면 무개입
  omg <- prt[okn] / dmg[okn]                     # 이득-손실 교환비

  # ── ⑥ 램프 — 예산·감액 범위는 이 칸의 램프 계열과 같다(갈린 것은 순서를 만든 양이다)
  rnk <- rep(0.5, length(dmg))                   # 값 없는 이름은 중앙 — 유·불리 어느 쪽도 아니다
  rnk[okn] <- (rank(-omg, ties.method = "average") - 0.5) / sum(okn)
  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - g * rnk)))
}
