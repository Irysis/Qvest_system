#==============================================================================
# gen_20260907_002324 — 다변량 상태의 채널 분해 × 종목 취약축 틸트
#                       (표적 칸: action = cross_sectional · state = multivar)
#
# ★기전
#   기존 multivar arm 들은 여러 상태변수를 하나의 스칼라 강도로 뭉쳐 총노출을 깎는다.
#   그러면 "지금 무엇이 스트레스인가" 라는 다변량 정보 중 **방향**은 버려지고 크기만 남는다.
#   이 arm 은 그 방향을 종목축에서 쓴다: 상태 4축(시장변동성·낙폭·추세·횡단면분산)을
#   확장창 상관구조로 화이트닝한 GLS 합성으로 하나의 스트레스 지수로 모으되,
#   **그 지수에 대한 축별 기여도**를 그대로 종목 취약도의 배합 가중치로 쓴다.
#   같은 강도의 스트레스라도 변동성 충격이면 β 높은 종목을, 낙폭이면 하방베타 높은 종목을,
#   추세 하락이면 시장상관 높은 종목을, 횡단면 분산이면 고유변동성 큰 종목을 더 깎는다.
#   상관구조를 쓰는 이유: rv60 과 xs 처럼 겹치는 축을 단순 평균하면 같은 정보를 두 번 세는데,
#   S^{-1} 합성은 겹친 몫을 나눠 갖게 해 축 기여도가 중복에 오염되지 않는다.
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 ∈ [0,1]. 표적이 cross_sectional 이므로
#   종목 차등이 서지 않는 달(보유 1종·특징 전부 결측)은 스칼라로 때우지 않고 무개입한다.
#   H = 확장창(미래 행 없음) · H$fwd 는 t 행이 미실현이라 읽지 않는다.
#   임의 상수 금지 — 개입 시작점은 스트레스 지수 자기 이력의 경험분포 중앙이고,
#   축 배합은 그 시점 상관행렬에서, 종목 차등은 그 달 보유 안의 횡단면 순위에서 나온다.
#   추정 불가·표본 부족이면 e <- 1(무개입). 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20260907_002324 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)

  nmin <- suppressWarnings(as.integer(ctx$n_min))
  if (!is.finite(nmin) || nmin < 12L) nmin <- 24L

  # ── ① 상태 행렬 — 부호를 스트레스 방향(값이 클수록 나쁨)으로 맞춘 4축, t 행까지
  X <- cbind(vol   =  suppressWarnings(as.numeric(H$rv60)),
             dd    =  suppressWarnings(as.numeric(H$dd)),
             trend = -suppressWarnings(as.numeric(H$r252)),
             disp  =  suppressWarnings(as.numeric(H$xs)))
  tt <- min(as.integer(t), nrow(X))
  if (!is.finite(tt) || tt < 2L) return(1)
  X  <- X[seq_len(tt), , drop = FALSE]

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

  # ── ③ GLS 합성 — a = S^{-1}1. 상관이 높은 축끼리 몫을 나눠 갖는다(중복 계상 제거)
  S <- suppressWarnings(stats::cor(Zo))
  a <- tryCatch(as.numeric(solve(S, rep(1, ncol(Zo)))), error = function(e) NULL)
  if (is.null(a) || !all(is.finite(a))) a <- rep(1, ncol(Zo))   # 특이행렬 폴백 = 단순 평균
  den <- sqrt(sum(a))
  if (!is.finite(den) || den <= 0) return(1)                    # 축들이 서로 상쇄 = 합성 불가
  m     <- as.numeric(Zo %*% a) / den
  z_now <- as.numeric(Zo[nrow(Zo), ])
  m_now <- m[length(m)]
  if (!is.finite(m_now) || !all(is.finite(m))) return(1)

  # ── ④ 개입 강도 g — 합성 지수가 자기 이력에서 얼마나 위쪽인가(확장창 경험분포)
  q <- stats::ecdf(m)(m_now)                # 0~1. 경험분포 중앙 위에서만 개입한다
  g <- (q - 0.5) / 0.5                      # 중앙 = 개입 시작점(데이터가 정한다)
  g <- max(0, min(1, g))
  if (g <= 0) return(1)

  # ── ⑤ 축 배합 w — 지금 스트레스 지수를 만든 몫. Σ_j a_j·z_j = m·den 이라 가법 분해다
  contrib <- a * z_now
  w <- pmax(0, contrib)
  sw <- sum(w)
  if (!is.finite(sw) || sw <= 0) return(1)  # 스트레스 방향으로 선 축이 없다
  w <- w / sw
  names(w) <- ax

  # ── ⑥ 종목 취약축 — 상태 축이 손실을 실어 나르는 종목 특성으로 각각 갈린다
  b  <- suppressWarnings(as.numeric(hold$beta))
  db <- suppressWarnings(as.numeric(hold$dbeta))
  ov <- suppressWarnings(as.numeric(hold$ovol))
  bc <- suppressWarnings(as.numeric(hold$bcorr))
  chan <- list(vol   = b,                                  # 시장 변동성 충격은 β 로 전달된다
               dd    = db,                                 # 낙폭 국면의 손실은 하방베타로
               trend = bc,                                 # 추세 하락은 시장상관이 높을수록 그대로 받는다
               disp  = ov * sqrt(pmax(0, 1 - bc^2)))       # 횡단면 분산 국면의 채널 = 고유변동성

  rk <- function(v) {                       # 보유 안 횡단면 순위 ∈ (0,1). 추정 없는 종목은 중앙
    r <- rep(0.5, length(v)); okv <- is.finite(v)
    if (sum(okv) >= 2L) r[okv] <- (rank(v[okv], ties.method = "average") - 0.5) / sum(okv)
    r
  }
  n_h <- nrow(hold)
  if (n_h < 2L) return(1)                   # 한 종목만 있으면 횡단면이 없다
  r_mix <- rep(0, n_h)
  for (j in ax) r_mix <- r_mix + w[[j]] * rk(chan[[j]])
  sd_r <- suppressWarnings(stats::sd(r_mix))
  if (!all(is.finite(r_mix)) || !is.finite(sd_r) || sd_r <= 0) return(1)  # 차등 미성립 = 무개입

  # ── ⑦ 노출 = 1 − g·r_mix
  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - g * r_mix)))
}
