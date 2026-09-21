#==============================================================================
# gen_20260922_000207 — 다변량 상태 × **보유 특성공간 화이트닝** 틸트
#                       (표적 칸: action = cross_sectional · state = multivar)
#
# ★기전 (사전 선언 — 한 인자만 갈리는 통제 대조로 설계했다)
#   이 칸의 선행 arm 은 상태 쪽의 중복 계상을 지웠다: rv60 과 xs 처럼 겹치는 상태 축을 단순
#   평균하면 같은 정보를 두 번 세므로 확장창 상관행렬로 화이트닝(S^{-1}1)해 축 기여도를 낸다.
#   그런데 그 기여도를 **보유 쪽에서 소비할 때는 화이트닝을 하지 않는다** — 채널별(β·하방베타·
#   시장상관·고유변동성) 횡단면 순위를 그대로 만들어 기여도로 섞는다. 문제는 이 네 특성이
#   한 책 안에서 서로 강하게 얽혀 있다는 것이다(엔진이 같은 수익 표본에서 만든다:
#   rf_cell_engine.R — beta·bcorr·ovol 이 동일 누적합에서 나온다). 채널 순위가 거의 같은 순서면
#   배합 가중치를 어떻게 흔들어도 **지목되는 종목은 하나의 순서로 붕괴한다** — 상태의 방향
#   정보가 종목축에 도달하지 못하고 라벨만 네 개인 셈이다.
#   이 arm 이 바꾸는 것은 그 한 지점이다: 보유 특성 행렬을 그 달 책 안에서 표준화한 뒤
#   **책 자신의 채널 상관구조로 화이트닝**해 지목 점수를 만든다.
#       u_i = z_i' S_c^{-1} w        (z_i = 종목 i 의 표준화 채널 벡터 · w = 상태 축 기여도)
#   S_c^{-1} 의 회귀 해석이 요점이다 — 화이트닝한 채널 j 의 몫은 "나머지 채널로 설명되지 않는
#   j 의 잔차"다. 그래서 '변동성 채널'은 β 가 높은 종목이 아니라 **나머지 특성이 예측하는 것보다
#   β 가 더 높은** 종목을 지목한다. 채널이 겹쳐 있을수록 이 차이는 커진다.
#   S_c 는 그대로 쓰지 않는다 — 책이 25종이고 채널이 넷이라 표본 대비 차원이 가볍지 않고,
#   거의 공선인 행렬의 역은 작은 차이를 증폭한다. 축소 강도는 튜닝값이 아니라 차원/표본 비에서
#   온다: lam = p / (n + p) (채널 수 p · 보유 수 n). 보유가 많을수록 화이트닝을 믿고, 책이
#   얇을수록 단순 배합(항등) 쪽으로 끌어당긴다 — 축소 추정의 정의 그대로다.
#
#   ★갈리는 인자는 **보유측 기하 하나**다. 상태측(4축 · 확장창 표준화 · GLS 합성 · 경험분포
#   중앙에서 시작하는 개입 강도 g · 축 기여도 w)과 산출 형태(e = 1 − g·r, 횡단면 평균 1 − g/2)는
#   선행 arm 과 같은 형태로 **고정**했다. 노출 경로의 평균이 같으므로 차이가 나면 그 차이는
#   '언제 얼마나 줄였나'가 아니라 '누구를 줄였나'에서만 온다 — 노출을 짝지은 대조가 이 칸의
#   판별기라 그 대조와 같은 축에서 답하도록 설계했다.
#
#   ★한계 명시: ① 화이트닝은 채널이 실제로 겹칠 때만 순서를 바꾼다 — 책의 채널 상관이 낮으면
#   이 arm 은 선행 arm 과 거의 같은 지목을 내고 차이가 0 에 수렴한다(그 자체가 이 층의 반증).
#   ② 역행렬은 잡음을 증폭한다 — 축소가 조건수를 1/lam 근처로 묶지만 없애지는 못한다.
#   ③ 채널 결측은 그 달 보유 중앙값으로 채운다(모름을 지목 근거로 삼지 않는다) — 결측이 많은 달은
#   유효 표본이 n 보다 작아 축소가 약하게 걸린다. ④ 상태 축이 스트레스 방향으로 서지 않는 달은
#   무개입이다(증액은 하지 않는다 — 이 층은 줄이기만 한다).
#   ★반증 조건: 화이트닝 순서가 선행 순서와 뒤집히는 종목들이 실제로는 하락에서 덜 깨지는
#   이름이라면, 이 arm 은 같은 평균 노출로 더 나쁜 분배를 하게 된다.
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 ∈ [0,1]. 표적이 cross_sectional 이므로 횡단면
#   차등이 서지 않는 달(보유 1종 · 채널 전부 결측 · 책 안에서 갈리지 않는 채널만)은 스칼라로
#   때우지 않고 무개입한다.
#   H = 확장창(t 행까지 · 미래 행 없음) — t 행이 미실현인 익월 수익 열은 읽지 않는다.
#   임의 상수 금지 — 개입 시작점은 합성 지수 자기 이력의 경험분포 중앙, 축 배합은 그 시점
#   상관행렬, 종목 차등은 그 달 보유 안의 횡단면 표준화·순위, 축소 강도는 차원/표본 비에서 온다.
#   추정 불가·표본 부족이면 e <- 1(무개입). 오류를 던지지 않는다. 외부 데이터 없음(H·ctx$hold).
#==============================================================================

overlay_expo_gen_20260922_000207 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)
  n_h <- nrow(hold)
  if (n_h < 2L) return(1)                      # 한 종목만 있으면 횡단면이 없다

  nmin <- suppressWarnings(as.integer(ctx$n_min))
  if (length(nmin) != 1L || !is.finite(nmin) || nmin < 12L) nmin <- 24L

  tt <- suppressWarnings(as.integer(t))
  if (length(tt) != 1L || !is.finite(tt)) return(1)

  # ── ① 상태 4축 — 부호를 스트레스 방향(값이 클수록 나쁨)으로 맞춘다. t 행까지만 읽는다.
  X <- cbind(vol   =  suppressWarnings(as.numeric(H$rv60)),
             dd    =  suppressWarnings(as.numeric(H$dd)),
             trend = -suppressWarnings(as.numeric(H$r252)),
             disp  =  suppressWarnings(as.numeric(H$xs)))
  tt <- min(tt, nrow(X))
  if (tt < 2L) return(1)
  X <- X[seq_len(tt), , drop = FALSE]

  fin <- stats::complete.cases(X) & is.finite(rowSums(X))
  if (!isTRUE(fin[tt])) return(1)                     # 지금 달 상태가 결측 = 개입 근거 없음
  if (sum(fin) < max(nmin, ncol(X) * 6L)) return(1)   # 상관 추정 표본 부족
  Xo <- X[fin, , drop = FALSE]

  # ── ② 확장창 표준화 — 축마다 단위가 다르므로 자기 이력의 평균·산포로 무차원화
  mu  <- colMeans(Xo)
  sdv <- apply(Xo, 2L, stats::sd)
  keep <- is.finite(sdv) & sdv > 0
  if (sum(keep) < 2L) return(1)                       # 다변량이 성립 안 하면 이 arm 의 일이 아니다
  Zo <- sweep(sweep(Xo[, keep, drop = FALSE], 2L, mu[keep], "-"), 2L, sdv[keep], "/")
  ax <- colnames(Xo)[keep]

  # ── ③ 상태 GLS 합성 a = S^{-1}1 — 겹친 축이 몫을 나눠 갖는다(상태측 중복 계상 제거)
  S_s <- suppressWarnings(stats::cor(Zo))
  a <- tryCatch(as.numeric(solve(S_s, rep(1, ncol(Zo)))), error = function(z) NULL)
  if (is.null(a) || !all(is.finite(a))) a <- rep(1, ncol(Zo))   # 특이행렬 폴백 = 단순 평균
  den <- sqrt(sum(a))
  if (!is.finite(den) || den <= 0) return(1)                    # 축들이 서로 상쇄 = 합성 불가
  m <- as.numeric(Zo %*% a) / den
  if (!all(is.finite(m))) return(1)

  # ── ④ 개입 강도 g — 합성 지수가 자기 이력에서 얼마나 위쪽인가(확장창 경험분포)
  q <- stats::ecdf(m)(m[length(m)])            # 0~1. 경험분포 중앙 위에서만 개입한다
  g <- max(0, min(1, (q - 0.5) / 0.5))         # 중앙 = 개입 시작점(데이터가 정한다)
  if (g <= 0) return(1)

  # ── ⑤ 축 기여도 w — 지금 합성 지수를 만든 몫. Σ_j a_j·z_j = m·den 이라 가법 분해다
  z_now <- as.numeric(Zo[nrow(Zo), ])
  w <- pmax(0, a * z_now)
  sw <- sum(w)
  if (!is.finite(sw) || sw <= 0) return(1)     # 스트레스 방향으로 선 축이 없다
  w <- w / sw
  names(w) <- ax

  # ── ⑥ 보유 채널 — 상태 축이 손실을 실어 나르는 종목 특성
  bb  <- suppressWarnings(as.numeric(hold$beta))
  dbv <- suppressWarnings(as.numeric(hold$dbeta))
  ovv <- suppressWarnings(as.numeric(hold$ovol))
  bcv <- suppressWarnings(as.numeric(hold$bcorr))
  if (length(bb) != n_h || length(dbv) != n_h ||
      length(ovv) != n_h || length(bcv) != n_h) return(1)
  bcv <- pmax(-1, pmin(1, bcv))                # 상관의 정의역 — 추정 잡음으로 벗어난 값만 되돌린다
  chan <- list(vol   = bb,                                 # 변동성 충격은 β 로 전달된다
               dd    = dbv,                                # 낙폭 국면의 손실은 하방베타로
               trend = bcv,                                # 추세 하락은 시장상관이 높을수록 그대로 받는다
               disp  = ovv * sqrt(pmax(0, 1 - bcv * bcv))) # 횡단면 분산 국면의 채널 = 고유변동성

  # 생존 채널만 — 그 달 책 안에서 종목을 갈라놓지 못하는 채널은 지목을 못 한다.
  use <- character(0); cols <- list()
  for (j in intersect(ax, names(chan))) {
    v <- chan[[j]]
    okv <- is.finite(v)
    if (sum(okv) < 2L) next
    med <- suppressWarnings(stats::median(v[okv]))
    if (!is.finite(med)) next
    v[!okv] <- med                             # 모름은 보유 중앙 — 지목 근거로 삼지 않는다
    s <- suppressWarnings(stats::sd(v))
    if (!is.finite(s) || s <= 0) next
    cols[[j]] <- (v - mean(v)) / s             # 책 안 표준화(그 달 데이터의 추정)
    use <- c(use, j)
  }
  if (!length(use)) return(1)
  wu <- as.numeric(w[use])
  swu <- sum(wu)
  if (!is.finite(swu) || swu <= 0) return(1)   # 살아남은 채널에 실린 기여가 없다
  wu <- wu / swu
  Cz <- do.call(cbind, cols[use])
  if (!all(is.finite(Cz))) return(1)

  # ── ⑦ 보유측 화이트닝 — 채널 상관을 차원/표본 비로 축소한 뒤 역을 취한다.
  #   축소 강도는 튜닝값이 아니라 p/(n+p): 책이 두꺼울수록 화이트닝을, 얇을수록 단순 배합을 믿는다.
  p <- ncol(Cz)
  v_w <- wu
  if (p >= 2L) {
    R <- suppressWarnings(stats::cor(Cz))
    if (all(is.finite(R))) {
      lam <- p / (n_h + p)
      R <- (1 - lam) * R + lam * diag(p)
      sol <- tryCatch(as.numeric(solve(R, wu)), error = function(z) NULL)
      if (!is.null(sol) && all(is.finite(sol))) v_w <- sol   # 실패 시 화이트닝 포기 = 단순 배합
    }
  }
  u <- as.numeric(Cz %*% v_w)                  # 지목 점수 — 겹친 채널의 몫을 나눈 뒤의 위험 적재

  # ── ⑧ 노출 = 1 − g·r (r = 보유 안 횡단면 순위 · 평균 1 − g/2 — 선행 arm 과 같은 형태)
  oku <- is.finite(u)
  if (sum(oku) < 2L) return(1)                 # 순위를 매길 수 없으면 무개입
  r <- rep(0.5, n_h)                           # 점수 없는 종목은 중앙 — 유리·불리 어느 쪽도 아니다
  r[oku] <- (rank(u[oku], ties.method = "average") - 0.5) / sum(oku)
  sdr <- suppressWarnings(stats::sd(r))
  if (!is.finite(sdr) || sdr <= 0) return(1)   # 차등 미성립 = 무개입

  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - g * r)))
}
