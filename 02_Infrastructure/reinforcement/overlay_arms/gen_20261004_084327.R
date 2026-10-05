#==============================================================================
# gen_20261004_084327 — 학습된 조건부 '분포' 위에서 세우는 꼬리초과확률 횡단면 트림 (v10.4 2026-10-04)
#   target cell: action = cross_sectional · state = ml (기전 지도 표적 칸 · 카탈로그 2종 대비 신설)
#
# ★기전
#   이 칸의 선행 arm 2종은 **학습 대상이 조건부 평균**이다 — 상태 4열의 선형 적합으로 익월 손실폭과
#   횡단면산포의 기대값 두 개를 뽑고, 그 둘을 손으로 정한 이차형식
#   L = sqrt((하방베타·s)^2 + (고유변동·k)^2) 에 꽂아 보유 안 순위를 매긴다. 두 arm 의 차이는 그 L 에
#   넣는 적재가 대입값인가 사후평균인가 하나뿐이고, **순서를 만드는 함수형**은 같다: 척도(scale) 하나의
#   크기순이다. 그래서 둘 다 ①분포의 모양(왜도·꼬리 두께)을 보지 못하고 ②예보에 표본외 정확도가
#   없어도 적합값이 자기 중앙만 넘으면 개입한다.
#   이 arm 은 세 자리를 바꾼다(상태 4열·예산·램프는 그대로 둔다 — 갈리는 인자를 좁히기 위해):
#     ① **학습 대상 = 조건부 분포** — 백화한 상태공간에서 오늘과 닮은 과거 달에 tricube 가중을 주어
#        익월 시장수익의 **가중 경험분포**를 세운다(국소 상수 조건부 분포 추정). 평균을 적합하지 않는다.
#        대역폭은 상수가 아니라 **표본외(LOO) 하위 분위손실**(pinball — 분포에 맞는 적정 점수)을
#        최소화하는 후보로 그 시점 데이터가 고른다. 점수는 하위 꼬리에만 매긴다(비대칭 표적).
#     ② **개입 자격을 번다** — 상태를 쓰는 예보가 상태를 안 쓰는 등가중 예보의 LOO 꼬리손실을 못 넘으면
#        학습된 것이 없다는 뜻이라 개입하지 않는다(e=1). 선행 arm 에는 이 관문이 없다. 넓은 대역이
#        이기면 조건부 분포가 무조건부로 수축해 강도도 스스로 0 으로 간다(자기 소멸 성질).
#     ③ **순서 = 꼬리초과확률** — 각 보유의 시나리오 반응을 비대칭으로 둔다(하락 시나리오 = 하방베타 ·
#        상승 시나리오 = 베타. 음의 하방베타는 0 으로 접어 하락장에서 버는 이름을 보존한다). 책 평균
#        반응의 하위 분위를 공통 기준선 c 로 잡고, 이름별로 P(반응 + 고유충격 < c) 를 학습된 시나리오
#        가중으로 적분한다. 이 확률은 위치·척도·**분포 모양**을 함께 쓰므로 척도 하나의 단조변환이
#        아니다 — 같은 L 을 가진 두 이름이 시나리오 집합의 왜도에 따라 순서를 바꾼다.
#   ★가정(정직하게 적는다): 고유충격의 표준화 모양을 시장 충격의 표준화 경험분포에서 가져온다.
#     두꺼운 꼬리를 정규분포로 가정하지 않기 위한 선택이지, 두 분포가 같다는 주장은 아니다.
#   예산은 선행과 동일하다 — e = 1 − g·r · 횡단면 평균 1 − g/2 · 감액 범위 0~g(강도에 개선분을 곱해
#   깎지 않는다. 처치 크기를 같게 둬야 이 칸 안에서 기전만 갈린다).
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 e in [0,1]. (cross_sectional 은 표를 내야 처치 전달.)
#   H = 확장창(미래 행 없음). ★H$fwd 의 t 행은 신호일에 미실현이라 읽지 않는다 — 학습쌍·시나리오는
#     i <= t-1 만 쓴다(그때 fwd[i] 의 관측 시점이 t 이하로 확정된다).
#   ctx$hold = 보유 상태(beta · dbeta=하방베타 · ovol=자체변동 · bcorr=시장상관 · n_obs).
#   임의 상수 금지 — 대역폭은 LOO 분위손실, 개입 강도는 꼬리 이동폭의 확장창 경험분포, 기준선 c 는
#   학습된 시나리오의 가중분위, 종목 차등은 보유 내 순위, 공분산 축소 강도는 차원/표본에서 나온다.
#   보유 없음·표본 부족·추정 실패·표본외 개선 없음 시 e <- 1(무개입). 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20261004_084327 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)
  if (t < 61L) return(1)                       # 학습쌍 60개월 미만이면 분포를 말하지 않는다(선행과 같은 하한)

  # ── ① 학습쌍 — 결과가 실현된 과거쌍만(i <= t-1). t 행의 익월 수익은 읽지 않는다
  idx <- seq_len(t - 1L)
  trd <- data.frame(rv60 = as.numeric(H$rv60[idx]), dd = as.numeric(H$dd[idx]),
                    r252 = as.numeric(H$r252[idx]), xs = as.numeric(H$xs[idx]),
                    yy   = as.numeric(H$fwd[idx]))
  trd <- trd[stats::complete.cases(trd), , drop = FALSE]
  n_tr <- nrow(trd)
  if (n_tr < 60L) return(1)
  xt <- c(as.numeric(H$rv60[t]), as.numeric(H$dd[t]), as.numeric(H$r252[t]), as.numeric(H$xs[t]))
  if (!all(is.finite(xt))) return(1)
  yv <- trd$yy

  # ── ② 상태공간 백화 — 표준화 + 공분산 축소(강도 = 차원/(차원+표본) · 상수가 아니라 표본이 정한다).
  #    4열은 서로 강하게 겹친다(변동성 창·산포). 백화 없이 유클리드로 재면 겹친 축을 여러 번 세게 된다.
  Xm  <- cbind(trd$rv60, trd$dd, trd$r252, trd$xs)
  np  <- ncol(Xm)
  mu  <- colMeans(Xm)
  sdv <- vapply(seq_len(np), function(j) stats::sd(Xm[, j]), numeric(1))
  if (any(!is.finite(sdv)) || any(sdv <= 0)) return(1)
  Zm <- sweep(sweep(Xm, 2, mu, "-"), 2, sdv, "/")
  zt <- (xt - mu) / sdv
  if (any(!is.finite(Zm)) || any(!is.finite(zt))) return(1)
  Sm  <- suppressWarnings(stats::var(Zm))
  ash <- np / (np + n_tr)
  Sm  <- Sm * (1 - ash) + diag(1, np) * ash    # 표준화 좌표라 항등행렬이 자연한 축소 표적
  Si  <- tryCatch(solve(Sm), error = function(z) NULL)
  if (is.null(Si) || any(!is.finite(Si))) Si <- diag(1, np)

  # 마할라노비스 제곱거리 — 과거×과거(LOO 용) · 오늘×과거
  dmat <- apply(Zm, 1, function(v) { Dv <- sweep(Zm, 2, v, "-"); rowSums((Dv %*% Si) * Dv) })
  Dn   <- sweep(Zm, 2, zt, "-")
  dnow <- rowSums((Dn %*% Si) * Dn)
  if (any(!is.finite(dmat)) || any(!is.finite(dnow))) return(1)

  # ── ③ 추정기 — tricube 적응 대역(대역폭 = kk번째 근접거리. 그 시점 표본이 정한다) + 가중 경험분위
  .kw <- function(d2v, kk, exi) {
    nd  <- length(d2v)
    uf  <- rep(1, nd); if (exi >= 1L) uf[exi] <- 0
    uf  <- uf / sum(uf)                        # 추정 불가 시 등가중(= 상태를 안 쓰는 예보)으로 떨어진다
    dv_ <- sqrt(pmax(0, d2v))
    sv_ <- if (exi >= 1L) sort(dv_[-exi]) else sort(dv_)
    if (!length(sv_)) return(uf)
    hb <- sv_[min(kk, length(sv_))]
    if (!is.finite(hb) || hb <= 0) hb <- sv_[length(sv_)]
    if (!is.finite(hb) || hb <= 0) return(uf)
    uu <- pmin(1, dv_ / hb)
    ww <- (1 - uu * uu * uu)^3
    if (exi >= 1L) ww[exi] <- 0
    sw <- sum(ww)
    if (!is.finite(sw) || sw <= 0) return(uf)
    ww / sw
  }
  .wqs <- function(ys, ws, qq) {               # 가중 경험분위 — 이미 오름차순인 (ys, ws)
    cw <- cumsum(ws); jj <- which(cw >= qq)
    if (!length(jj)) ys[length(ys)] else ys[jj[1]]
  }
  .wq <- function(yy, ww, qq) {                # 정렬이 필요한 자리(기준선 1회)
    o2 <- rank(yy, ties.method = "first")
    y2 <- numeric(length(yy)); w2 <- numeric(length(ww))
    y2[o2] <- yy; w2[o2] <- ww
    .wqs(y2, w2, qq)
  }

  taus <- c(0.1, 0.2, 0.3)                     # 점수를 매기는 분위 = 하위 꼬리만(오버레이가 맞혀야 하는 쪽)
  kmin <- suppressWarnings(as.integer(ctx$n_min))
  if (!length(kmin) || !is.finite(kmin) || kmin < 12L) kmin <- 12L   # 꼬리 분위를 말할 유효표본 하한
  kcd  <- unique(pmin(n_tr, pmax(kmin, floor(n_tr * c(0.2, 0.4, 0.7, 1)))))
  if (!length(kcd)) return(1)

  ordv <- rank(yv, ties.method = "first")      # 각 관측의 오름차순 위치
  ysrt <- numeric(n_tr); ysrt[ordv] <- yv

  # ── ④ 대역폭 선택 + 표본외 꼬리 개선분 — LOO 분위손실. 평균오차가 아니라 꼬리를 점수로 잰다
  lo_u <- 0                                    # 무조건부(등가중) 예보
  lo_c <- rep(0, length(kcd))                  # 후보 대역폭별 조건부 예보
  sevm <- matrix(0, nrow = n_tr, ncol = length(kcd))
  for (i in seq_len(n_tr)) {
    pos  <- ordv[i]
    ys_i <- ysrt[-pos]                         # 자기 관측을 뺀 표본(LOO)
    nn_i <- length(ys_i)
    wun  <- rep(1 / nn_i, nn_i)
    qu_v <- vapply(taus, function(qq) .wqs(ys_i, wun, qq), numeric(1))
    rs   <- yv[i] - qu_v
    lo_u <- lo_u + sum(pmax(taus * rs, (taus - 1) * rs))
    for (kk in seq_along(kcd)) {
      ww   <- .kw(dmat[, i], kcd[kk], i)
      wsrt <- numeric(n_tr); wsrt[ordv] <- ww
      ws_i <- wsrt[-pos]
      sw   <- sum(ws_i)
      ws_i <- if (is.finite(sw) && sw > 0) ws_i / sw else wun
      qc_v <- vapply(taus, function(qq) .wqs(ys_i, ws_i, qq), numeric(1))
      rc   <- yv[i] - qc_v
      lo_c[kk] <- lo_c[kk] + sum(pmax(taus * rc, (taus - 1) * rc))
      sevm[i, kk] <- mean(qu_v - qc_v)         # 조건부 꼬리가 무조건부보다 얼마나 아래로 내려갔나
    }
  }
  if (!is.finite(lo_u) || lo_u <= 0 || any(!is.finite(lo_c))) return(1)
  kb  <- which(lo_c == min(lo_c))[1]
  skl <- 1 - lo_c[kb] / lo_u                   # 상태를 쓴 예보의 표본외 꼬리 개선분
  if (!is.finite(skl) || skl <= 0) return(1)   # 학습된 것이 없으면 개입하지 않는다 — 자격을 번다
  ksel <- kcd[kb]

  # ── ⑤ 개입 강도 g — 오늘의 꼬리 이동폭이 자기 이력 경험분포에서 어디인가(중앙 = 개입 시작점).
  #    이력은 LOO(n-1) 표본, 오늘은 전 표본(n) — 차이는 1/n 규모라 분위 비교를 바꾸지 않는다.
  wn   <- .kw(dnow, ksel, 0L)
  wns  <- numeric(n_tr); wns[ordv] <- wn
  uf0  <- rep(1 / n_tr, n_tr)
  q0v  <- vapply(taus, function(qq) .wqs(ysrt, uf0, qq), numeric(1))
  qtv  <- vapply(taus, function(qq) .wqs(ysrt, wns, qq), numeric(1))
  sev_t <- mean(q0v - qtv)
  sevv <- sevm[, kb]; sevv <- sevv[is.finite(sevv)]
  if (!is.finite(sev_t) || length(sevv) < 24L) return(1)
  g <- max(0, min(1, (stats::ecdf(sevv)(sev_t) - 0.5) / 0.5))
  if (g <= 0) return(1)

  # ── ⑥ 종목별 꼬리초과확률 — 학습된 시나리오 집합 위에서 각 이름의 비대칭 반응을 적분한다
  bdn <- pmax(0, suppressWarnings(as.numeric(hold$dbeta)))    # 하락 시나리오 반응(음수 = 헤지 → 0 으로 접는다)
  bup <- suppressWarnings(as.numeric(hold$beta))              # 상승 시나리오 반응
  ovl <- suppressWarnings(as.numeric(hold$ovol))
  bcr <- suppressWarnings(as.numeric(hold$bcorr))
  sig <- ovl * sqrt(pmax(0, 1 - bcr * bcr)) / sqrt(12)        # 월 단위 고유변동
  okh <- is.finite(bdn) & is.finite(bup) & is.finite(sig) & sig > 0
  if (sum(okh) < 2L) return(1)                                # 순위를 매길 수 없으면 무개입

  nvv <- as.numeric(H$nav)                                    # 신호일까지 실현된 벤치 누적(미래 아님)
  rmk <- nvv[-1L] / nvv[-length(nvv)] - 1
  rmk <- rmk[is.finite(rmk)]
  if (length(rmk) < 60L) return(1)
  sd_m <- stats::sd(rmk)
  if (!is.finite(sd_m) || sd_m <= 0) return(1)
  Fz <- stats::ecdf((rmk - mean(rmk)) / sd_m)                 # 표준화 충격의 경험 모양(정규 가정 대신 실측)

  mb_dn <- mean(bdn[okh]); mb_up <- mean(bup[okh])
  mu_bk <- ifelse(yv < 0, mb_dn * yv, mb_up * yv)             # 책 평균 반응 — 부호는 하락의 정의지 문턱이 아니다
  c_lo  <- mean(vapply(taus, function(qq) .wq(mu_bk, wn, qq), numeric(1)))
  if (!is.finite(c_lo)) return(1)

  pv <- rep(NA_real_, length(bdn))
  pv[okh] <- vapply(which(okh), function(i2) {
    mui <- ifelse(yv < 0, bdn[i2] * yv, bup[i2] * yv)         # 이름별 비대칭 반응
    sum(wn * Fz((c_lo - mui) / sig[i2]))                      # 학습된 가중으로 적분한 P(반응+고유충격 < c)
  }, numeric(1))

  # ── ⑦ 순위 램프 — 예산·감액 범위는 선행과 같다(갈린 것은 순서를 만든 함수형이다)
  okp <- is.finite(pv)
  if (sum(okp) < 2L) return(1)
  rr <- rep(0.5, length(pv))                                  # 값 없는 이름은 중앙 — 유·불리 어느 쪽도 아니다
  rr[okp] <- (rank(pv[okp], ties.method = "average") - 0.5) / sum(okp)

  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - g * rr)))
}
