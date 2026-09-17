#==============================================================================
# gen_20260917_091415 — 변동성 국면 × 위험지분 횡단면 균등화 (2026-09-17)
#
# ★표적 칸: action = cross_sectional · state = vol   (기전 지도 측정 0회 · 미포화)
#
# ★기전 (사전 선언)
#   변동성 상태를 쓰는 기존 arm 은 전부 총노출 스칼라다 — tgt/sigma_hat 한 배율을 책 전체에
#   똑같이 곱한다. 그 구조는 "지금 시장이 얼마나 흔들리나" 만 쓰고 "그 흔들림이 내 보유 안
#   **누구에게** 실리나" 는 버린다. 같은 시장 충격이라도 종목이 나르는 위험은 sigma_m 에
#   비례하는 시장항(beta*sigma_m)과 sigma_m 과 무관한 고유항(ovol*sqrt(1-bcorr^2))으로
#   갈리고, 둘의 비중은 sigma_m 이 움직이면 함께 회전한다. 조용한 달에는 고유항이 지분을
#   지배하고 흔들리는 달에는 시장항이 지배한다 — 즉 **누구를 깎아야 하는지의 답 자체가
#   변동성 상태의 함수**다. 총노출 축은 이 회전을 원리적으로 표현할 수 없다(배율이 하나뿐).
#   이 arm 은 그 회전을 종목축에 싣는다: 매달 현재 sigma_m 에서 각 보유의 위험지분을 다시
#   추정하고, 등가 지분(1/n)을 넘는 만큼만 노출을 깎는다. 깎는 세기는 변동성 상태의 자기
#   이력 백분위 g 로, g=0(가장 조용한 달)이면 등가중 그대로, g=1(가장 흔들리는 달)이면
#   위험지분이 균등해지는 배분까지 밀어붙인다. 등가 지분 아래인 종목은 건드리지 않는다
#   (노출 상한 1) — 총노출을 무조건 깎는 계열과 달리 축소분이 위쪽에만 몰린다.
#   ★기존 arm 과의 구분: dbeta_tilt = 상태 낙폭·차등 하방베타 순위,
#     trend_persist_tilt = 상태 추세지속·차등 시장베타 순위. 둘 다 차등 키가 고정이고
#     상태는 세기만 정한다. 여기서는 상태가 **차등 키의 구성 자체**를 바꾼다.
#
# ★계약
#   반환 = 스칼라 e ∈ [0,1] 또는 data.table(Ticker, e). H = 확장창(t 행까지).
#   H$fwd 는 t 행이 미실현이므로 읽지 않는다(어느 열도 t 이후를 보지 않는다).
#   임의 상수 문턱 없음 — 세기는 변동성의 자기 이력 경험분포에서, 종목 차등은 그 달 보유
#   안의 위험지분 비(比)에서 나온다. 창(20/60/120) 선택도 하지 않는다: 각 창의 자기
#   백분위를 낸 뒤 평균한다. 추정 불가·표본 부족이면 e <- 1(무개입).
#==============================================================================

overlay_expo_gen_20260917_091415 <- function(H, t, ctx) {
  hold <- ctx$hold
  if (is.null(hold) || !nrow(hold)) return(1)
  n <- nrow(hold)
  if (n < 2L) return(1)                          # 지분을 나눌 수 없으면 무개입

  nm_raw <- suppressWarnings(as.integer(ctx$n_min))
  n_min  <- if (length(nm_raw) == 1L && is.finite(nm_raw) && nm_raw > 0L) nm_raw else 24L

  # ── ① 개입 세기 g — 지금 변동성이 자기 이력에서 몇 분위인가.
  #   창을 고르지 않는다(고르면 내가 고른 상수가 된다): 엔진이 주는 세 창 각각의 경험분위를
  #   내고 평균한다. 각 창은 자기 이력하고만 비교되므로 스케일 가정이 없다.
  qs <- numeric(0)
  for (nm_ in c("rv20", "rv60", "rv120")) {
    x <- suppressWarnings(as.numeric(H[[nm_]]))
    if (length(x) < t) next
    x  <- x[seq_len(t)]                          # 과거 행만
    xt <- x[t]
    xf <- x[is.finite(x)]
    if (!is.finite(xt) || length(xf) < n_min) next
    qs <- c(qs, stats::ecdf(xf)(xt))
  }
  if (!length(qs)) return(1)                     # 표본 부족 = 무개입
  g <- mean(qs)
  if (!is.finite(g)) return(1)
  g <- max(0, min(1, g))
  if (g <= 0) return(1)

  # ── ② 시장 충격 규모 sigma_m — 계약이 주는 당월 변동. 없으면 세 창의 중앙값.
  sig <- suppressWarnings(as.numeric(ctx$v_now))
  sig <- if (length(sig)) sig[1] else NA_real_
  if (!is.finite(sig) || sig <= 0) {
    cand <- suppressWarnings(as.numeric(c(H$rv20[t], H$rv60[t], H$rv120[t])))
    cand <- cand[is.finite(cand)]
    cand <- cand[cand > 0]
    sig  <- if (length(cand)) stats::median(cand) else NA_real_
  }
  if (!is.finite(sig) || sig <= 0) return(1)

  # ── ③ 종목별 위험 분해 — 추정 없는 종목은 횡단면 중앙값으로 채운다(유리·불리 어느 쪽도 아님)
  .fill <- function(z) {
    z <- suppressWarnings(as.numeric(z))
    if (length(z) != n) return(NULL)
    ok <- is.finite(z)
    if (!any(ok)) return(NULL)
    z[!ok] <- stats::median(z[ok])
    z
  }
  b <- .fill(abs(hold$beta))
  if (is.null(b)) b <- .fill(abs(hold$dbeta))    # 시장 적재 추정이 없으면 하방 적재로 후퇴
  if (is.null(b)) return(1)
  o <- .fill(hold$ovol)
  if (is.null(o)) return(1)                      # 고유 변동을 모르면 지분을 못 나눈다
  cc <- .fill(hold$bcorr)
  if (is.null(cc)) cc <- rep(0, n)               # 상관 미상 = 전부 고유로 읽는다(시장항 과대계상 회피)
  b  <- pmax(0, b)
  o  <- pmax(0, o)
  cc <- pmax(-1, pmin(1, cc))

  v <- (b * sig)^2 + (o * sqrt(pmax(0, 1 - cc^2)))^2   # 단위 비중당 분산 기여(잔차 상관 0 가정)

  # ── ④ 신뢰도 축소 — 관측수가 얕은 종목의 추정이 지분을 지배하지 않게 횡단면 평균으로 당긴다
  nobs <- suppressWarnings(as.numeric(hold$n_obs))
  if (length(nobs) == n && any(is.finite(nobs))) {
    nmed <- stats::median(nobs[is.finite(nobs)])
    lam  <- nobs / (nobs + nmed)
    lam[!is.finite(lam)] <- 0
    lam  <- pmax(0, pmin(1, lam))
    v    <- lam * v + (1 - lam) * mean(v)
  }

  tot <- sum(v)
  if (!is.finite(tot) || tot <= 0) return(1)

  # ── ⑤ 노출 = min(1, ((1/n)/지분)^g)
  #   지분이 등가 몫 이하면 1(무개입), 넘으면 넘은 배수만큼 깎되 지수는 변동성 분위 g.
  #   g→0 이면 등가중 그대로, g→1 이면 위험지분이 균등해지는 배분.
  s     <- v / tot
  ratio <- (1 / n) / s
  ratio[!is.finite(ratio)] <- 1
  e <- pmin(1, ratio^g)
  e[!is.finite(e)] <- 1

  data.table::data.table(Ticker = as.character(hold$Ticker),
                         e      = pmax(0, pmin(1, e)))
}
