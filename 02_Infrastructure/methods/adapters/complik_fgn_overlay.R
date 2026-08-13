# complik_fgn_overlay.R — arXiv 2606.11962 "Composite likelihood inference of fractional
#   Gaussian processes with sequentially optimal subset selection" (Fourreau & Garcin).
#   원문: paper_pdf("arxiv:2606.11962"). ★원문 없이 memo 만 보고 쓰면 날조다.
#
#------------------------------------------------------------------------------
# 논문 기전 (충실한 재구성 — 날조 아님)
#------------------------------------------------------------------------------
# fGn 의 자기공분산은 H 하나로 완전히 결정된다 (원문 eq. covFGN):
#     E[Y_s Y_t] = (σ²/2)(|t−s−1|^{2H} − 2|t−s|^{2H} + |t−s+1|^{2H})
# 전체 MLE 는 N×N 공분산의 역행렬이 필요해 비싸다. 논문은 **합성우도**로 대체한다:
#     C(θ) = Σ_{k=1..N_cl} ℓ(V_k; θ)      (원문 §3.1)
# 여기서 V_k 는 크기 p 의 부분벡터다. 어느 부분벡터를 고를지가 논문의 본체이고,
# Godambe 정보(부분벡터 간 종속을 반영한 Fisher 정보의 확장)를 **축차적으로 최대화**해 설계한다.
#
# ★논문이 우리 대신 어려운 부분을 풀어줬다 (§3.3): 그 축차 최적화의 **결론이 "연속 관측"**이다
#   — t_{k,i} = k+i−2. H∈[0,1] 전 구간과 p∈[2,5] 전부에서 같은 답이 나왔다. 따라서 구현은
#   조합최적화가 아니라 **연속 창 슬라이딩**이고, 공분산 행렬이 모든 부분벡터에서 동일하므로
#   행렬식과 역행렬을 **한 번만** 계산한다(논문이 명시한 계산 이득).
#
# σ² 는 nuisance 다 — 원문 §2.1: "the entire serial dependence structure is encoded in a
#   single parameter H. We therefore focus on the estimation of H alone." 그래서 ∂C/∂σ²=0 에서
#   σ̂²(H) = (1/(N_cl·p))·Σ_k V_k' A(H)^{-1} V_k 로 해석적으로 소거하고 **H 1차원**만 최적화한다.
#
#------------------------------------------------------------------------------
# KR 사상 — ★이것은 신규 기전이 아니라 **추정기 교체 짝(paired estimator swap)** 이다
#------------------------------------------------------------------------------
# 기등재 `HurstTrendOverlay`(2607.19497)와 **기전·창·문턱·노출값이 전부 동일**하고
# H 추정기만 R/S(재척도범위, 적률 계열) → 합성우도 MLE 로 바뀐다. 논문의 비교 대상이
# 정확히 "method of moments" 이므로, 이 짝이 논문 주장을 우리 자료에서 직접 시험한다.
#   ⇒ 나는 등재 전에 "기전이 같으니 nearest_arm 이 가깝게 나올 것"이라고 적었다. **틀렸다.**
#     실측 `max|Δexposure| = 0.300` — 이 기전에서 **가능한 최대값**이다(EXP_TREND−EXP_MEANREVERT).
#     즉 기전이 같아도 추정기가 다르면 행동은 최대로 갈린다. TailConformalBand 는 정반대였다
#     (기전이 다른데 행동이 수렴, max|Δw| 1.4e-03). ⇒ **기전 차이는 행동 차이를 어느 방향으로도
#     예측하지 못한다 — 재야 한다.** 이 두 사례가 구별성 축을 만든 이유를 양쪽에서 채운다.
#
# ★등재 전 실측 (2026-08-13, 합성 fGn 양성대조 200회 × n=252 · KR 벤치 426개월):
#   · 참값 회수:   R/S 평균|편의| **0.0702** vs CompLik **0.0101**. R/S 는 H=0.3 에서 +0.121 로
#                  체계적 상향 편의(소표본 R/S 편의는 알려진 현상), CompLik 은 사실상 불편.
#   · 안정성:      sd 0.0792 vs **0.0404**. 논문 주장(적률 대비 안정) 재현.
#   · ★문턱 편향:  **순수 랜덤워크(H=0.5) 자료를 R/S 는 81.2% 를 "추세"로 판정**한다(CompLik 45.0%).
#                  KR 벤치 실측에서 R/S 추세판정 88.5% — 즉 기존 arm 라벨의 대부분이
#                  시장 지속성이 아니라 **추정기 편의**이며, 그 arm 은 평균노출 0.966 으로
#                  거의 상시 ON 이다(≈무작동). 이 어댑터는 40.8% · 평균노출 0.823.
#   · 두 스케줄은 **426개월 중 241개월(56.6%) 판정이 갈린다** — 중복 arm 이 아니다.
#   ⚠ 이 실측은 "CompLik 이 H 를 더 잘 잰다"까지만 말한다. **더 잘 잰 H 가 더 나은 수익을 준다는
#     주장은 아니다** — 그건 Σ-A/B 의 ΔIR 이 답할 문제이고, 여기서 선취하지 않는다.
#
# ★사전등록 파라미터 (스윕 아님 — 전부 원문 또는 기존 arm 에서 상속, 튜닝 0)
#   P_CL = 15         · 원문 §5.1 이 변동성 계열에 쓴 부분벡터 크기 그대로. 내가 고른 값 아님.
#   설계 = 연속       · 원문 §3.3 의 최적화 **결론**. 대안을 시험해 고른 것이 아니다.
#   WIN=252 / H_THRESHOLD=0.5 / EXP_TREND=1.00 / EXP_MEANREVERT=0.70 / MIN_OBS=64
#                     · **HurstTrendOverlay 에서 그대로 상속** — 추정기 외 모든 것을 고정해야
#                       짝 비교가 성립한다. 여기서 하나라도 흔들면 그 순간 sweep 이다.
#   H 탐색구간 [0.05, 0.95] · 수치 가드(경계에서 공분산이 특이해짐). 성과로 고른 값 아님.
#
# ★이 구현이 정한 것 (원문에 없음, 명시):
#   창 전체를 한 번 **중심화**한다. 원문 모형은 centered Gaussian 벡터(eq. covFBM)라 위치모수가
#   없는데 일별 수익에는 미세 드리프트가 있다. 드리프트를 남기면 γ(0)이 부풀어 H 가 상향된다.
#
# PIT (pit.md C5): 각 홀딩월 M 에 대해 `Date < first-day-of-M` 만 잘라 추정하고 그 창의
#   마지막 날짜를 used_cutoff 로 신고한다. 래퍼가 cutoff >= 홀딩월 시작이면 로드를 거부한다.

suppressMessages({ library(data.table); library(arrow) })

BENCH_PATH     <- ".cache/benchmark.parquet"
WIN            <- 252L
H_THRESHOLD    <- 0.5
EXP_TREND      <- 1.00
EXP_MEANREVERT <- 0.70
MIN_OBS        <- 64L
P_CL           <- 15L          # 원문 §5.1
H_LO           <- 0.05
H_HI           <- 0.95

#' fGn 자기공분산 (σ²=1) — 원문 eq. covFGN
.fgn_acf <- function(H, p) {
  k <- 0:(p - 1L)
  0.5 * (abs(k - 1)^(2 * H) - 2 * abs(k)^(2 * H) + abs(k + 1)^(2 * H))
}

#' 합성우도 H 추정 (연속 설계 + σ² 해석적 프로파일)
.hurst_complik <- function(x, p = P_CL) {
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < MIN_OBS || n < p + 10L) return(NA_real_)
  x <- x - mean(x)                                   # 중심화 — 위 "이 구현이 정한 것" 참조
  Ncl <- n - p + 1L                                  # §3.3: 연속 부분벡터 전부
  V <- outer(seq_len(Ncl), 0:(p - 1L), function(a, b) x[a + b])   # Ncl x p

  negC <- function(H) {
    A <- stats::toeplitz(.fgn_acf(H, p))             # 모든 부분벡터가 공유 → 1회만 분해
    ch <- tryCatch(chol(A), error = function(e) NULL)
    if (is.null(ch)) return(1e10)
    Z <- backsolve(ch, t(V), transpose = TRUE)
    s2 <- sum(Z^2) / (Ncl * p)                       # σ̂²(H)
    if (!is.finite(s2) || s2 <= 0) return(1e10)
    -(-(Ncl * p / 2) * log(s2) - (Ncl / 2) * (2 * sum(log(diag(ch)))))
  }
  o <- tryCatch(stats::optimize(negC, c(H_LO, H_HI), tol = 1e-4), error = function(e) NULL)
  if (is.null(o)) return(NA_real_)
  h <- o$minimum
  # 경계에 붙은 해는 추정 실패로 본다(구간 밖의 최적을 구간 끝으로 보고하는 것을 값으로 쓰지 않는다)
  if (h <= H_LO + 1e-3 || h >= H_HI - 1e-3) return(NA_real_)
  h
}

exposure_schedule <- function(ctx) {
  pr <- as.data.table(ctx$periods)
  pr[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
  setorder(pr, eval_date)
  pr[, hold_start := as.Date(format(decision_date, "%Y-%m-01"))]

  if (!file.exists(BENCH_PATH)) {
    cat("[CompLikFGnOverlay] 벤치 부재 — 어댑터 제외\n"); return(NULL)
  }
  bm <- as.data.table(read_parquet(BENCH_PATH))
  if (!all(c("Date", "BM_Ret") %in% names(bm))) {
    cat("[CompLikFGnOverlay] 벤치 컬럼 결손(Date/BM_Ret) — 제외\n"); return(NULL)
  }
  bm[, Date := as.Date(Date)]; setorder(bm, Date); bm <- bm[is.finite(BM_Ret)]

  n <- nrow(pr)
  expo <- rep(NA_real_, n); cut <- rep(as.Date(NA), n); hval <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    w <- bm[Date < pr$hold_start[i]]                 # ★엄격 부등호 (C5)
    if (nrow(w) < MIN_OBS) next
    w <- tail(w, WIN)
    h <- .hurst_complik(w$BM_Ret)
    hval[i] <- h
    cut[i]  <- max(w$Date)
    # 신호 결측 → 오버레이 없음(1.0). 결측을 '방어'로 내려앉히지 않는다.
    expo[i] <- if (!is.finite(h)) 1.0 else if (h > H_THRESHOLD) EXP_TREND else EXP_MEANREVERT
  }
  ok <- is.finite(expo) & !is.na(cut)
  if (!any(ok)) { cat("[CompLikFGnOverlay] 유효 월 0 — 제외\n"); return(NULL) }
  expo[!ok] <- 1.0
  cut[!ok]  <- pr$hold_start[!ok] - 1L

  cat(sprintf("[CompLikFGnOverlay] %d개월 · H 중앙값 %.3f (sd %.3f) · 추세월 %d (%.1f%%) · 평균노출 %.4f\n",
              n, stats::median(hval, na.rm = TRUE), stats::sd(hval, na.rm = TRUE),
              sum(hval > H_THRESHOLD, na.rm = TRUE),
              100 * mean(hval > H_THRESHOLD, na.rm = TRUE), mean(expo)))
  list(exposure = data.table(Date = pr$eval_date, exposure = expo),
       used_cutoff = cut)
}
