# hurst_trend_overlay.R — regime 레인 노출 어댑터 (논문 arxiv:2607.19497 유래, 2026-08-09).
#
# 논문: "The Science and Practice of Trend-Following Systems" — 추세추종 통일 이론.
#   핵심 주장: TF alpha ∝ **저주파 스펙트럼 질량**. 즉 시장이 지속성(persistence)을 가질 때
#   추세형 노출이 보상받고, 평균회귀 국면에서는 그 노출이 벌점을 받는다.
#
# ★왜 팩터가 아니라 오버레이인가 (라우팅 축 분리):
#   이 논문의 **횡단면 팩터 축은 소진**됐다(spec_mass · T_RetAutoCorr · Hurst 3회 QUARANTINE,
#   큐 `paper_exhausted=TRUE`). 그런데 큐의 `regime_application` 은 다른 축을 가리킨다 —
#   "**시장 레벨** Hurst > 0.5 인 달 = momentum overlay 활성화 타이밍". 종목을 고르는 신호가 아니라
#   **얼마나 태울지**를 정하는 신호다. 같은 논문이라도 축이 다르면 판결도 다르다
#   ([[project-consumption-path-changes-verdict-20260802]] — 랭킹에서 죽은 재료가 필터로는 살았던 실측).
#
# 계약 (method_registry.R::wrap_exposure_adapter):
#   exposure_schedule(ctx) -> list(exposure = data.table(Date, exposure), used_cutoff = Date[])
#   ctx$periods = data.table(decision_date, eval_date). 홀딩월 = month(decision_date).
#   exposure ∈ [0,1] (long-only 무레버리지). used_cutoff 는 **월별로** 신고한다.
#
# ★PIT (pit.md C5): 홀딩월이 **시작되기 전** 데이터만 쓴다.
#   각 홀딩월 M 에 대해 벤치 일별수익 중 `Date < first-day-of-M` 만 잘라 Hurst 를 추정하고,
#   그 창의 마지막 날짜를 used_cutoff 로 신고한다. 래퍼가 cutoff >= 홀딩월 시작이면 **로드를 거부**한다.
#   (2026-07-06 BearProb 사고 = 홀딩월 말 정보로 그 홀딩월을 스케일한 동월 look-ahead.)
#
# ★사전등록 파라미터 (스윕 아님 — 논문·기존 하네스에서 도출, 튜닝 금지):
#   WIN=252 (1년 거래일)  · 논문의 저주파 질량을 담는 표준 창
#   H_THRESHOLD=0.5       · 논문 주장의 분기점 그 자체(0.5 = 랜덤워크). 최적화로 고른 값이 아니다.
#   EXP_TREND=1.00 / EXP_MEANREVERT=0.70
#     · 0.70 은 임의값이 아니라 **기존 하네스의 CAUTION 노출**(auto_regime_overlay_ab.R::CAT_EXPOSURE)
#       을 그대로 재사용한 것 — 새 자유도를 만들지 않기 위해서다.
#   ⇒ 자유 파라미터 0개. 문턱·노출을 흔들어 최선을 고르면 그 순간 sweep 이 되고 DSR 게이트 대상이다.

suppressMessages({ library(data.table); library(arrow) })

BENCH_PATH <- ".cache/benchmark.parquet"
WIN            <- 252L
H_THRESHOLD    <- 0.5
EXP_TREND      <- 1.00
EXP_MEANREVERT <- 0.70
MIN_OBS        <- 64L

#' 재척도 범위(R/S) Hurst 지수. x = 일별 수익 벡터.
#' 표준 R/S: 창 크기 k 별로 평균 R/S 를 구해 log(R/S) ~ log(k) 기울기를 취한다.
.hurst_rs <- function(x) {
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < MIN_OBS) return(NA_real_)
  ks <- unique(round(exp(seq(log(16), log(floor(n / 2)), length.out = 8L))))
  ks <- ks[ks >= 16L & ks <= floor(n / 2)]
  if (length(ks) < 3L) return(NA_real_)
  rs <- vapply(ks, function(k) {
    m <- floor(n / k)
    v <- vapply(seq_len(m), function(j) {
      seg <- x[((j - 1L) * k + 1L):(j * k)]
      z <- cumsum(seg - mean(seg))
      s <- stats::sd(seg)
      if (!is.finite(s) || s <= 0) NA_real_ else (max(z) - min(z)) / s
    }, numeric(1))
    mean(v, na.rm = TRUE)
  }, numeric(1))
  ok <- is.finite(rs) & rs > 0
  if (sum(ok) < 3L) return(NA_real_)
  unname(stats::coef(stats::lm(log(rs[ok]) ~ log(ks[ok])))[2L])
}

exposure_schedule <- function(ctx) {
  pr <- as.data.table(ctx$periods)
  pr[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
  setorder(pr, eval_date)
  # 홀딩월 = month(decision_date) — 캐리어 실측 규약(decision→eval 간격 31일, 월 겹침 0.000)
  pr[, hold_start := as.Date(format(decision_date, "%Y-%m-01"))]

  if (!file.exists(BENCH_PATH)) {
    cat("[HurstTrendOverlay] 벤치 부재 — 어댑터 제외\n"); return(NULL)
  }
  bm <- as.data.table(read_parquet(BENCH_PATH))
  if (!all(c("Date", "BM_Ret") %in% names(bm))) {
    cat("[HurstTrendOverlay] 벤치 컬럼 결손(Date/BM_Ret) — 제외\n"); return(NULL)
  }
  bm[, Date := as.Date(Date)]; setorder(bm, Date)
  bm <- bm[is.finite(BM_Ret)]

  n <- nrow(pr)
  expo <- rep(NA_real_, n); cut <- rep(as.Date(NA), n); hval <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    # ★엄격 부등호 — 홀딩월 시작일 당일은 이미 홀딩월이다.
    w <- bm[Date < pr$hold_start[i]]
    if (nrow(w) < MIN_OBS) next
    w <- tail(w, WIN)
    h <- .hurst_rs(w$BM_Ret)
    hval[i] <- h
    cut[i]  <- max(w$Date)
    # 신호 결측 → 오버레이 없음(1.0). ★결측을 '방어'로 내려앉히지 않는다 — 없는 정보로 태우지도 줄이지도 않는다.
    expo[i] <- if (!is.finite(h)) 1.0 else if (h > H_THRESHOLD) EXP_TREND else EXP_MEANREVERT
  }
  ok <- is.finite(expo) & !is.na(cut)
  if (!any(ok)) { cat("[HurstTrendOverlay] 유효 월 0 — 제외\n"); return(NULL) }
  # 창 부족으로 추정 불가한 초기 구간은 노출 1.0 · cutoff = 홀딩월 직전일로 신고(중립 처리, PIT 준수)
  expo[!ok] <- 1.0
  cut[!ok]  <- pr$hold_start[!ok] - 1L
  cat(sprintf("[HurstTrendOverlay] %d개월 · H 중앙값 %.3f · 추세월 %d (%.1f%%) · 평균노출 %.4f\n",
              n, stats::median(hval, na.rm = TRUE), sum(hval > H_THRESHOLD, na.rm = TRUE),
              100 * mean(hval > H_THRESHOLD, na.rm = TRUE), mean(expo)))
  list(exposure = data.table(Date = pr$eval_date, exposure = expo),
       used_cutoff = cut)
}
