#==============================================================================
# gen_20261009_193812 — 두 채널이 **같은 달에 함께 터지는가**를 학습해 세우는 횡단면 트림
#   (v10.4 2026-10-09 · target cell: action = cross_sectional · state = ml · 측정 8 · 카탈로그 7 · 미포화)
#
# ★기전
#   이 칸의 선행 7종은 점수의 정의가 제각각이었다(직교합 · 사후 적재 · 꼬리초과확률 ·
#   위험예산 비율 · 오일러 기여몫 · 상하 부분적률 교환비 · 모형집합 최악값). 그런데 **한 식을
#   예외 없이 공유한다**: 이름 i 의 피해 크기를 체계 채널 p_i = max(0,dbeta_i)·s 와
#   고유 채널 q_i = u_i·k 의 **직교 결합** sqrt(p_i^2 + q_i^2) 으로 센다. 그것은 두 채널의
#   충격이 같은 달에 **독립**이라는 가정의 식이다 — 이 칸에서 아무도 그 가정을 재지 않았다.
#   재면 되는 일이다. 두 머리의 예보가 주는 것은 각 채널의 **수준**이고, 남은 것은 잔차의
#   **동시성**이다. 한 모수를 복원하면 결합식은 이렇게 넓어진다:
#        L_i = sqrt( p_i^2 + q_i^2 + 2·rho·p_i·q_i )
#   rho = 0 이면 선행의 원(circle) 등위집합, rho → 1 이면 p+q(완전 동행), rho → −1 이면
#   |p−q|(상쇄). 즉 선행 7종은 한 모수 족(族)의 **한 점만** 써 왔다.
#   등위집합이 원에서 45°축 타원으로 돌면 순위가 회전한다 — 같은 p^2+q^2 을 가진 이름들 중
#   **대각선 위(두 채널이 섞인 이름)** 와 **축 위(한 채널에 쏠린 이름)** 가 자리를 바꾼다.
#   원 등위집합의 어떤 단조변환으로도 나오지 않는 순서다(교차항은 p^2+q^2 의 함수가 아니다).
#   세 번째 머리가 rho 를 그 시점 확장창에서 추정한다: 두 머리의 **축소예측기 LOO 잔차**를
#   표준화해 곱하고, 그 곱을 같은 상태 4축에 회귀한다(곱의 조건부 평균 = 조건부 동시성).
#   조건부 층이 표본외에서 벌지 못하면 **무조건부 동시성**으로 떨어지고, 그 무조건부 값까지
#   0 이면 이 arm 은 스스로 선행의 직교합이 된다(자기 소멸 · 거짓 차이를 만들지 않는다).
#   깊이 g·램프·예산은 가족 규약을 글자 그대로 유지했다 — 갈리는 인자를 '채널 동시성' 하나로
#   좁히기 위해서다. 평균(1 − g/2)도 감액 범위(0~g)도 같으므로, 차이가 나면 그 차이는
#   '언제 얼마나 줄였나' 가 아니라 **'누구를 상단에 세웠나'** 에서만 온다.
#
# ★가정(정직하게 적는다)
#   ①s·k 는 수준 예보이고 rho 는 잔차의 동시성이다 — 수준 척도에 동시성을 접목한 근사다
#     (조건부 분산을 따로 재지 않는다. 그건 이 칸의 다른 축이다).
#   ②E[zD·zX | state] 가 조건부 상관과 같아지려면 조건부 분산이 1 이어야 한다. 아니므로 이
#     추정량은 '척도된 동시성' 이고, 이차형식이 성립하는 정의역 [−1,1] 으로만 자른다.
#   ③곱 표적은 4차 적률 꼬리를 타서 분산이 크다 — 조건부 층은 LOO 로 번 만큼만 쓰이고
#     자주 0 에 가까울 것이다. 그때 남는 것은 무조건부 동시성 한 값(순위 회전은 상수)이다.
#   ④고유 채널은 ovol 이 전체 변동뿐이라 대칭 분산으로, 체계 채널은 하락측 적재로
#     denominate 된다 — 고유 쪽 과대평가 방향이고 이 arm 의 주장에 유리하지 않다(보수적).
#   ⑤KR 월별 자료에서 변동과 산포는 함께 커지는 쪽이라 rho 는 양(+)으로 추정될 공산이 크다.
#     그러면 이 arm 은 주로 '두 채널이 섞인 이름' 을 더 깎는다 — 상태 의존성은 주장의 약한 쪽이다.
#
# ★계약
#   반환 = data.table(Ticker, e) — 종목별 노출 e in [0,1]. (cross_sectional 은 표를 내야 처치 전달.)
#   H = 확장창(미래 행 없음). ★H$fwd 의 t 행은 신호일에 미실현 — 읽지 않는다. 학습쌍은 i <= t−1 만
#     쓴다(그때 fwd[i] 와 xs[i+1] 의 관측 시점이 t 이하로 확정된다).
#   ctx$hold = 보유 상태(beta · dbeta=하락측 적재 · ovol=자체변동 · bcorr=시장상관 · n_obs).
#   임의 상수 금지 — 능형 강도(차원/(차원+표본))·신뢰도 th·표본 하한·개입 시작점(경로 중앙)·
#     산포 무차원화(표본 중앙)·동시성 rho 가 전부 그 시점 확장창에서 나온다.
#   보유 없음·열 부재·표본 부족·적합 실패·잔차 퇴화·유한 채널 2종 미만 = e <- 1(무개입). 오류를 던지지 않는다.
#==============================================================================

overlay_expo_gen_20261009_193812 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)
  if (t < 61L) return(1)                           # 학습쌍 60개월 미만이면 모형을 말하지 않는다(칸 공통 하한)
  eps <- .Machine$double.eps
  if (!all(c("rv60", "dd", "r252", "xs", "fwd") %in% names(H))) return(1)
  hnm <- names(hold)
  if (!all(c("Ticker", "ovol", "bcorr") %in% hnm)) return(1)

  # ── ① 학습쌍 — 결과가 실현된 과거쌍만(i <= t−1). t 행의 익월 수익은 읽지 않는다.
  idx <- seq_len(t - 1L)
  big <- cbind(as.numeric(H$rv60[idx]), as.numeric(H$dd[idx]),
               as.numeric(H$r252[idx]), as.numeric(H$xs[idx]),
               pmax(0, -as.numeric(H$fwd[idx])), as.numeric(H$xs[idx + 1L]))
  big <- big[stats::complete.cases(big), , drop = FALSE]
  nn  <- nrow(big)
  nfl <- 60L                                       # 모수(절편 + 상태 4축)당 12개월 — 가족 하한
  nmn <- suppressWarnings(as.integer(ctx$n_min))
  if (length(nmn) == 1L && !is.na(nmn)) nfl <- max(nfl, nmn)
  if (nn < nfl) return(1)
  Xm  <- big[, seq_len(4L), drop = FALSE]          # 상태 4축 = 가족 고정(rv60 · dd · r252 · xs)
  ydn <- big[, 5L]                                 # 익월 시장 하방 손실폭 max(0,−fwd)
  ydp <- big[, 6L]                                 # 익월 실현 횡단면산포 xs[i+1] (i+1 <= t 라 관측됨)
  xnw <- c(as.numeric(H$rv60[t]), as.numeric(H$dd[t]), as.numeric(H$r252[t]), as.numeric(H$xs[t]))
  if (any(!is.finite(xnw))) return(1)

  # ── ② 설계행렬 — 표준화 + 능형(강도 = 차원/(차원+표본) · 상수가 아니라 표본이 정한다)
  nax <- ncol(Xm)
  mu  <- colMeans(Xm)
  sdv <- vapply(seq_len(nax), function(j) stats::sd(Xm[, j]), numeric(1))
  if (any(!is.finite(mu)) || any(!is.finite(sdv)) || any(sdv <= 0)) return(1)
  Zm  <- sweep(sweep(Xm, 2, mu, "-"), 2, sdv, "/")
  znw <- (xnw - mu) / sdv
  if (any(!is.finite(Zm)) || any(!is.finite(znw))) return(1)
  lam <- nax / (nax + nn)
  gxx <- vapply(seq_len(nax), function(j)
           vapply(seq_len(nax), function(k) sum(Zm[, j] * Zm[, k]), numeric(1)), numeric(nax))
  if (any(!is.finite(gxx))) return(1)
  Ai  <- tryCatch(solve(gxx + diag(lam * mean(diag(gxx)), nax)), error = function(z) NULL)
  if (is.null(Ai) || any(!is.finite(Ai))) return(1)
  hdg <- 1 / nn + rowSums((Zm %*% Ai) * Zm)        # 해트 대각(중심화 절편 1/n 포함)
  if (any(!is.finite(hdg))) return(1)

  # ── ③ 머리 하나 — 적합 경로 · 오늘 예보 · LOO 신뢰도 th · **축소예측기의 LOO 잔차**
  #   y − [ybar_{-i} + th·(yhat_{-i} − ybar_{-i})] = (1−th)·rs0 + th·rsl — 대수적으로 정확하다.
  #   이 잔차가 ④의 동시성 추정 입력이다(in-sample 잔차의 낙관을 쓰지 않는다).
  one_head <- function(yv) {
    ybr <- mean(yv)
    cfv <- as.numeric(Ai %*% vapply(seq_len(nax), function(j) sum(Zm[, j] * (yv - ybr)), numeric(1)))
    ftv <- ybr + as.numeric(Zm %*% cfv)
    rsl <- (yv - ftv) / pmax(1 - hdg, eps)         # LOO 잔차(해트 보정)
    rs0 <- (yv - ybr) / (1 - 1 / nn)               # 무조건부 평균의 LOO 잔차
    s1  <- sum(rsl * rsl); s0 <- sum(rs0 * rs0)
    th  <- if (is.finite(s1) && is.finite(s0) && s0 > 0) max(0, min(1, 1 - s1 / s0)) else 0
    list(path = ybr + th * (ftv - ybr),
         now  = ybr + th * sum(cfv * znw),
         inn  = (1 - th) * rs0 + th * rsl)
  }
  hdd <- one_head(ydn)
  hxs <- one_head(ydp)
  if (!is.finite(hdd$now) || !is.finite(hxs$now)) return(1)

  # ── ④ 세 번째 머리 — 채널 동시성 rho. 표준화한 두 LOO 잔차의 곱을 같은 상태 4축에 회귀한다.
  #   조건부 층이 표본외에서 벌지 못하면 곱의 표본 평균(무조건부 동시성)으로 떨어진다.
  rdn <- hdd$inn; rxs <- hxs$inn
  sdd <- stats::sd(rdn); sxs <- stats::sd(rxs)
  if (!is.finite(sdd) || !is.finite(sxs) || sdd <= 0 || sxs <= 0) return(1)
  ycp <- ((rdn - mean(rdn)) / sdd) * ((rxs - mean(rxs)) / sxs)
  if (any(!is.finite(ycp))) return(1)
  hcp <- one_head(ycp)
  rho <- max(-1, min(1, hcp$now))                  # 이차형식이 성립하는 정의역으로만 자른다
  if (!is.finite(rho)) return(1)

  # ── ⑤ 깊이 g — 가족 규약 그대로: 오늘의 하방 충격 예보가 자기 적합 경로에서 차지한 분위
  spt <- stats::sd(hdd$path)
  q <- if (is.finite(spt) && spt > 0) stats::ecdf(hdd$path)(hdd$now) else 0.5
  g <- max(0, min(1, (q - 0.5) / 0.5))             # 경로 중앙 = 개입 시작점(데이터가 정한다)
  if (!is.finite(g) || g <= 0) return(1)

  # ── ⑥ 두 채널 척도 — 체계(하락측 적재)·고유(시장과 무관한 변동). 가족과 같은 형태로 고정
  mdp <- stats::median(ydp)
  if (!is.finite(mdp) || mdp <= 0) return(1)
  sct <- max(0, hdd$now)                           # 체계 채널 척도(월 단위 손실폭)
  kct <- max(0, hxs$now) / mdp                     # 고유 채널 척도(표본 중앙 대비 배수 = 무차원)
  bdn <- suppressWarnings(as.numeric(hold$dbeta))
  bal <- suppressWarnings(as.numeric(hold$beta))
  if (!length(bdn)) bdn <- bal
  if (!length(bal)) bal <- bdn
  if (!length(bdn)) return(1)
  gpd <- !is.finite(bdn) & is.finite(bal)
  bdn[gpd] <- bal[gpd]                             # 하락측 적재 결측 = 전구간 적재로 후퇴
  ovl <- suppressWarnings(as.numeric(hold$ovol))
  bcr <- suppressWarnings(as.numeric(hold$bcorr))
  pch <- pmax(0, bdn) * sct                        # 체계 기여 p_i (음의 하락측 적재 = 진짜 헤지 → 0)
  uch <- ovl * sqrt(pmax(0, 1 - bcr * bcr)) / sqrt(12) * kct   # 고유 기여 q_i (월 단위)
  pch[!is.finite(pch)] <- 0
  uch[!is.finite(uch)] <- 0                        # 고유 채널 추정 없음 = 체계 채널로만 잰다
  okn <- (pch + uch) > 0
  if (sum(okn) < 2L) return(1)                     # 비교할 이름이 둘 미만이면 무개입

  # ── ⑦ 결합 — 직교합(rho=0)의 일반화. rho=1 이면 p+q(동행), rho=−1 이면 |p−q|(상쇄)
  lvi <- sqrt(pmax(0, pch * pch + uch * uch + 2 * rho * pch * uch))
  if (!any(is.finite(lvi) & lvi > 0)) return(1)    # 모든 이름이 0 = 순서가 없다

  # ── ⑧ 램프 — 예산(횡단면 평균 1 − g/2)·감액 범위(0~g)는 이 칸의 램프 계열과 같다
  rnk <- rep(0.5, length(lvi))                     # 채널 추정이 없는 이름은 중앙 — 유·불리 어느 쪽도 아니다
  rnk[okn] <- (rank(lvi[okn], ties.method = "average") - 0.5) / sum(okn)
  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, 1 - g * rnk)))
}
