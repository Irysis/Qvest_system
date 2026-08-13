# tail_conformal_band.R — arXiv 2606.18199 "Conformal Prediction Intervals with
#   Tail-Specific Guarantees" (52쪽, §초록·구성 정독). 2026-06-18 라우터 risk 큐.
#   원문: paper_pdf("arxiv:2606.18199"). ★원문 없이 memo 만 보고 쓰면 날조다.
#   (골격은 new_adapter("TailConformalBand", kind="weight", ...) 로 생성 후 기전을 채웠다.)
#
#------------------------------------------------------------------------------
# 논문 기전 (충실한 재구성 — 날조 아님)
#------------------------------------------------------------------------------
# 고전 conformal 은 전역 marginal coverage 1−α 짜리 **대칭** 구간을 준다. 이 논문은 그것을
# **꼬리별로 분리**한다: split conformal 로 **한쪽 꼬리씩** one-sided 구간을 각각 유효하게
# 만들고, 그 둘의 **교집합**으로 two-sided 구간을 유도한다. 교집합 구간이 tail-specific
# coverage 와 global coverage 를 동시에 만족함을 증명한다(exchangeable = 유한표본 보장,
# non-exchangeable = 점근 보장). 시뮬레이션에서 **왜곡(skew) 자료일수록** 고전 양측 구간 대비
# 방향별 보정이 개선된다. ★저자들이 밝힌 금융 응용이 정확히 우리 상황이다 —
# "수익 최대화를 추구하되 **왼쪽 꼬리를 엄격히 통제**".
#
#------------------------------------------------------------------------------
# KR long-only 사상 · 기등재 ConformalKelly 와의 차별점
#------------------------------------------------------------------------------
# 이미 등재된 `ConformalKelly`(2608.01494)는 **대칭** 잔차 분위수를 band 로 써서
#   w ∝ max(mu,0) / band  로 불확실한 종목의 비중을 깎는다.
# 이 논문의 기여는 **꼬리 비대칭**이다. long-only 주식에서 실제 위험은 **하방**이므로
# 대칭 폭이 아니라 **하방 one-sided 폭**으로 나눈다:
#   w ∝ max(mu,0) / band_down ,   band_down = −Q_{α_lo}(잔차)
# 즉 "상방으로 넓은 종목"은 벌하지 않고 "**하방으로 넓은 종목**"만 벌한다.
#
# ⚠★분리 미입증 (2026-08-13 실측, 정정): 초판 헤더는 "왜곡 자료에서 두 band 가 갈린다"고
#   단정했으나 **입증되지 않았다**. 합성 fixture 에서 ConformalKelly 와 max|Δw| = **1.4e-03**
#   이고, 좌측 꼬리를 두껍게 주입해도 **거의 커지지 않았다(0.0014)**. 등재 게이트의
#   `nearest_arm` 축이 이를 "★근접"으로 신고한다.
#   ⇒ 이 arm 은 **실데이터에서 ConformalKelly 와 갈리는지가 미검**인 상태로 등재돼 있다.
#     Σ-A/B 에서 두 arm 의 ΔIR 이 사실상 같게 나오면 그것이 답이고, 그때는 하나를 접어야 한다
#     ("같은 것을 두 이름으로 재는" 상태를 결과표가 독립 arm 두 개로 보이게 하기 때문).
#   대칭 자료에서 ConformalKelly 로 수렴하는 것은 설계상 의도다(연속성) — 문제는 왜곡에서도
#   수렴해 보인다는 점이고, 그건 내 주입이 약했기 때문일 수도 있어 **판정은 실데이터에 맡긴다**.
#
# ★논문이 준 것 = one-sided split conformal 구성과 그 유효성. 임의성 없음.
# ★이 구현이 정한 것 = α_lo = 0.10 (ConformalKelly 의 양측 α=0.20 을 한쪽으로 옮긴 값 —
#   같은 총 신뢰수준에서 **방향만** 바꿔 두 arm 이 비교 가능하게 한 단일 사전고정).
#   split 절반 분할·중심=중앙값은 ConformalKelly 선례를 따랐다. **sweep 아님**:
#   이 값들을 바꿔가며 백테를 돌려 고르지 않았다(selection_type="chain").
#
# PIT: ctx$R 은 하네스가 `raw[Date < start_d]` 로 만든 trailing 행렬(C1/C2). ctx 밖 데이터 미사용.

TCB_ALPHA_LO <- 0.10   # 하방 one-sided 수준. 사전고정 — sweep 아님
TCB_MIN_OBS  <- 40L    # split conformal 최소 관측(절반씩 나눠야 함)

method_weights <- function(ctx) {
  a <- ctx$assets
  R <- ctx$R[, a, drop = FALSE]
  mu <- ctx$mu

  # ── 하방 one-sided split conformal 폭
  band_dn <- vapply(seq_along(a), function(j) {
    x <- R[, j]; x <- x[is.finite(x)]
    if (length(x) < TCB_MIN_OBS) return(NA_real_)
    h <- floor(length(x) / 2L)
    center <- stats::median(x[seq_len(h)])                 # 중심 = 앞 절반(robust, CK 선례)
    resid  <- x[(h + 1L):length(x)] - center               # ★부호 유지 — 대칭화하지 않는다
    q_lo <- stats::quantile(resid, probs = TCB_ALPHA_LO, names = FALSE, na.rm = TRUE)
    w <- -as.numeric(q_lo)                                 # 하방 폭 (좌측 분위수의 절대폭)
    if (!is.finite(w) || w <= 0) NA_real_ else w
  }, numeric(1))

  # 이력 부족·추정 실패는 **제외가 아니라 중립**(중앙값 대체) — 제외하면 선별이 바뀌어
  # A/B 통제 전제가 깨진다(ConformalKelly 와 동일 규약).
  if (all(is.na(band_dn))) return(stats::setNames(rep(1, length(a)), a))
  band_dn[is.na(band_dn)] <- stats::median(band_dn, na.rm = TRUE)

  # ── 알파 방향: mu 없으면 순수 역-하방불확실성. 있으면 양수부만(부호 뒤집기 금지, C13 정합)
  if (is.null(mu)) {
    m <- rep(1, length(a))
  } else {
    m <- suppressWarnings(as.numeric(mu[a])); m[!is.finite(m)] <- 0; m <- pmax(m, 0)
    if (sum(m) <= 0) m <- rep(1, length(a))
  }

  w <- m / band_dn
  names(w) <- a
  cat(sprintf("[TailConformalBand] p=%d · 하방폭 중앙 %.5f · 최대/최소 %.2f\n",
              length(a), stats::median(band_dn), max(band_dn) / max(min(band_dn), 1e-12)))
  w
}
