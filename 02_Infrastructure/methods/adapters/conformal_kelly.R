# conformal_kelly.R — arXiv 2608.01494 "Conformal Kelly: Conformal Prediction Intervals as the
#   Scale in Fractional Kelly Position Sizing" (2026-08-06 라우터 optimizer 큐).
#
# 논문 메커니즘: 수익률 **예측구간의 폭**을 Kelly 사이징의 스케일로 쓴다.
#   구간이 넓다(=불확실) → 비중 축소 / 좁다(=확신) → 비중 확대. fractional Kelly 의 분수를
#   상수가 아니라 conformal 구간폭에서 도출하는 것이 기여. (논문 IS 28.5% CAGR/SR 1.34,
#   OOS 2022~ 패시브 미달 — 방법론 참고 목적으로 큐 등재됨.)
#
# KR long-only 사상 (충실한 재구성, 날조 아님):
#   w_i ∝ max(mu_i, 0) / band_i     (band = conformal 반폭)
#   = "알파 방향은 그대로, 불확실한 종목의 비중만 깎는다".
#   논문은 L/S·레버리지 Kelly 지만 헌법상 long-only·Σw=1 이므로 **long leg 사상**
#   (헌법 허용 — paper_router_prompt §STEP2 "L/S 는 infeasible 사유 아님").
#
# ★구간 산출: `predictions_with_ci.parquet` 를 쓰지 않는다.
#   현존분은 2026-05 WT 실험 산출물뿐이라 캐리어 유니버스·기간을 못 덮고, 저장 파생 패널은
#   동월 look-ahead 실사고 이력이 있다([[project-stored-panel-samemonth-lookahead]], §7b).
#   대신 하네스가 주는 **PIT-safe trailing 행렬 ctx$R** 에서 split-conformal 잔차 분위수로
#   구간을 직접 만든다 — 구조적으로 미래참조 불가(R 은 매수 이전 창만 담는다).
#
# PIT: ctx$R / ctx$Sigma 는 run_sigma_ab 가 `raw[Date < start_d]` 로 만든다(C1/C2/C9 준수).
# 제약: 반환은 **선호 벡터**다. long-only/Σw=1 은 wrap_adapter 가 강제한다 (v10: 비중 상한 폐지).

CONFORMAL_ALPHA <- 0.20   # 80% 구간 (양측 10%) — 표준 선택. sweep 아님(단일 사전 고정, DSR 부적용)

method_weights <- function(ctx) {
  a <- ctx$assets
  R <- ctx$R                       # obs × assets, PIT trailing
  mu <- ctx$mu

  # ── conformal 반폭: split-conformal. 앞 절반으로 중심 추정 → 뒤 절반 잔차의 (1-α) 분위수.
  #    ★단일 표본 분위수가 아니라 **분할**을 쓰는 이유: 같은 데이터로 중심과 폭을 동시에
  #      추정하면 폭이 체계적으로 과소해진다(conformal 의 핵심이 그 분리다).
  n <- nrow(R)
  band <- vapply(seq_along(a), function(j) {
    x <- R[, j]
    x <- x[is.finite(x)]
    if (length(x) < 40L) return(NA_real_)          # 이력 부족 → 판정 불가(EW 몫으로 넘김)
    h <- floor(length(x) / 2L)
    center <- median(x[seq_len(h)])                 # 중심 = 앞 절반 (robust)
    resid  <- abs(x[(h + 1L):length(x)] - center)   # 잔차 = 뒤 절반
    q <- stats::quantile(resid, probs = 1 - CONFORMAL_ALPHA, names = FALSE, na.rm = TRUE)
    if (!is.finite(q) || q <= 0) NA_real_ else q
  }, numeric(1))

  # 이력 부족 종목은 밴드 중앙값으로 대체 — **제외가 아니라 중립**.
  #   (제외하면 그 종목이 조용히 0 이 되어 선별을 바꾼다. 선별 고정이 A/B 통제의 전제다.)
  if (all(is.na(band))) return(setNames(rep(1, length(a)), a))   # 전부 불가 → EW 동치
  band[is.na(band)] <- stats::median(band, na.rm = TRUE)

  # ── 알파 방향: mu 없으면 균등(=순수 역-불확실성 가중). 있으면 양수부만.
  if (is.null(mu)) {
    m <- rep(1, length(a))
  } else {
    m <- suppressWarnings(as.numeric(mu[a]))
    m[!is.finite(m)] <- 0
    m <- pmax(m, 0)
    # 전부 비양수면 알파 정보 없음 → 역-불확실성만 사용(부호 뒤집기 금지, C13 정합)
    if (sum(m) <= 0) m <- rep(1, length(a))
  }

  w <- m / band
  names(w) <- a
  w
}
