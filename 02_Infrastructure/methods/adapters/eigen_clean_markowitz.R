# eigen_clean_markowitz.R — arXiv 1810.08384 "Portfolio Construction Matters"(2018) — 고유모드 정제 상관행렬 공분산의
#   마코위츠 구성(2026-10-15 · P3 구성 라운드 재료 · decision_register SUPERVISION-1810-CORRECTIONS ③).
#
# 논문 메커니즘(§II · §III 원문):
#   · 마코위츠 해 x_i ∝ C⁻¹p_i — p = 정규화한 순위 예측자(전 종목 [-1, +1] 균등).
#   · 공분산 정제: 'we only keep the k largest eigenvectors of the covariance matrix' · 식 (4)
#       C_ij ≃ σ_i σ_j ( Σ_{α≤k} λ^α v^α_i v^α_j + ε² δ_ij ) — λ · v = **상관행렬**의 고유값 · 고유벡터,
#       ε² 는 'the total variance of the portfolio is unchanged, i.e. Tr C = Σ_i σ_i²' 가 되게 고른다.
#   · 'we will instead test a few values up to k = 5' · §III: k = 5 칸이 최고 SR(1.19 · FF 0.34). 추정 창 = 'at least two years
#     of historical close-to-close daily returns'. ★k = 5 는 1000종 풀(모드 비율 0.5%)의 결과다 — 25종 상관행렬에선 상위 5 모드가
#     스펙트럼의 20% 이고 잡음 상한((1+√(25/252))² ≈ 1.73) 근처 모드가 섞일 수 있다. 사전 단일 고정(스윕 없음)은 그대로 둔다.
#   교차 점검 ①(2026-10-14 · 감독 기록 04_Research/programs/_supervision/1810_08384_loop_supervision.md)이 원문으로 확인한 기전 =
#   신호가 아니라 **구성법**이 성과를 만든다.
#
# KR 롱온리 사상(우리 축: long-only · ≤25종 · Σw ≤ 1 — 종목 선택은 엔진이 한다 · 이 어댑터는 선택된 종목의 비중만 정한다):
#   ① 정제: 받은 종목의 상관행렬을 고유분해해 상위 k = min(5, n−1) 모드만 남기고, 나머지는 평평한 ε² 로 둔다.
#      Σ̃ = D (V_k Λ_k V_kᵀ + ε² I) D · D = diag(σ). ε² 는 논문대로 **공분산 대각합**을 보존하게 고른다(Tr Σ̃ = Σσ² —
#      종목별 분산이 아니라 총분산 보존이다). ε² > 0 이라 Σ̃ 는 양정치 — 25종 · 252일 표본의 잡음 모드를 버린다.
#   ② 마코위츠: argmin_{x ≥ 0, x_i ≤ c·Σx} ½ xᵀΣ̃x − pᵀx(부등식 제약 2차 계획 — 음수 사후 절단 아님 · 상한도 계획 **안**).
#      합-정규화는 wrap_adapter 가 한다(제약이 모두 동차라 정규화 뒤에도 같은 문제의 해다).
#   ③ 예측자 p = 1(상수): 논문 p 는 **전 종목** 순위를 [-1, +1] 로 편 값이고, 엔진이 고른 상위 ≤25종의 그 값은
#      [1 − 48/(N−1), 1] 에 몰려 있다(N = 그날 후보 폭 · N = 1000 이면 상대 차 ≤ 4.8% · 후보 폭이 작은 초기 연도엔 더 크다).
#      x ∝ C⁻¹p 와 이 2차 계획은 p 의 척도에 불변이라 p = 1 은 원문 사상의 근사다(원문 그대로 = ctx$mu 패널 rank-Z ∝ p).
#      ★p = 1 ⇒ 해 = Σ̃ 의 **상한 c 롱온리 최소분산**(KKT: Σ̃x − 1 − ν + Aκ = 0 을 1ᵀx 로 나누면 최소분산의 KKT — 동치).
#      원문의 롱숏 통계 요인(시장 · 업종) 중립화는 이 사상에서 작동하지 않는다 — 남는 기전은 선택 집합 안의 위험 분산이다.
#      결론 범위 = '고유모드 정제 공분산 최소분산 구성'(가장 가까운 비교군 = P3R01 K2 LW 최소분산). 이 상수는 기전 서술이지
#      튜닝이 아니다(성과를 보고 고르지 않았다).
#   ④ 상한 c = 축 값(ctx$ub) — 고정 축 '비중 상한 없음'(2026-10-15 도훈 "고정축 비중상한 없음으로 진행하자" · 셀 엔진 ctx$ub = 1 ·
#      카탈로그 하네스 WC_UB = 1). 그래서 운영 경로에서는 상한 제약이 없다(롱온리 최소분산 그대로 — 소수 종목 집중 가능).
#      구판(10-15 오전)은 하네스 상한 0.20 을 계획 안에 넣었다 — 하네스가 사후 재분배(휴리스틱)로 상한을 걸고 양수 ≤4종 해는 래퍼 단언
#      실패 → 엔진이 그 신호일을 기록 없이 버렸기 때문이다(P3R02 격리 교차 점검 R1). 하네스 상한이 축대로 풀리면서 그 결함도 사라졌다.
#      ctx$ub < 1 을 넘기는 호출자가 있으면 그 상한은 계획 **안**에 넣는다(x_i ≤ c·Σx · 사후 재분배 휴리스틱 회피) — n·c = 1 이면
#      유일 가능해 EW, n·c < 1 이면 이름을 부르고 멈춘다(래퍼 EW 폴백 · 그 사실이 로그에 남는다).
#
# 측정 경로(P3R02 RX 칸 · rf_cell_engine.R catalog 분기 — backtest_harness.R 카탈로그 분기가 아니다):
#   신호일 d 의 선정 종목 중 직전 252 거래일(Date < d) 일별 수익이 **결측 없이 완전한** 종목만 ctx$assets 로 온다(이력 불완전 종목은
#   비중 계산 · 보유에서 빠진다 — 선택 교락은 아래 진단 줄의 n 과 기준 칸 선정 수로 센다). 창 252 는 셀 사양 lookback 기본값이다
#   (P3R01 의 다른 비중 변형과 창이 같지 않다 — 빌트인 K1 ivol 60 · K2 minvar 120(LW · 계획 안 상한 0.15) · K4 kelly 120(상한 0.15)).
#   하네스는 0 비중 행을 시뮬레이션 전에 버린다(replication_harness.R W[Weight != 0]).
# PIT: ctx$R 은 엔진이 Date < 신호일로 자른 창이다(C1 · C2 · C9). 어댑터는 ctx 밖을 보지 않는다. 전기간 통계 없음.
# 진단 줄: 호출마다 '[ecm] d=… n=… k=… cap=… active=… capbind=… eps2=…' 한 줄을 표준출력에 남긴다(셀 로그 results/<code>.log —
#   사전등록 record 의 커버리지 · 이력 탈락 · 상한 구속 · 활성 종목 수를 산출물에서 정확히 세는 근거 · 성과 수치 아님).
# 반환: 선호 벡터(이름 = ctx$assets). long-only · Σw = 1 은 wrap_adapter(method_registry.R)가 강제한다.

EIG_K_MODES <- 5L   # 논문 §II~§III — 'test a few values up to k = 5' · k = 5 = 최고 SR 칸(근거 = arXiv 1810.08384 §III). 스윕 아님(단일 사전 고정)

.ecm_clean_cov <- function(X, k = EIG_K_MODES) {
  n <- ncol(X)
  s <- apply(X, 2L, stats::sd, na.rm = TRUE)
  if (any(!is.finite(s) | s <= 0)) stop("표준편차 0 또는 결측 종목이 있다 — 정제 불가")
  Cr <- suppressWarnings(stats::cor(X, use = "pairwise.complete.obs"))
  Cr[!is.finite(Cr)] <- 0; diag(Cr) <- 1
  e <- eigen(Cr, symmetric = TRUE)
  k <- max(1L, min(as.integer(k), n - 1L))                 # 평평한 잔여 모드가 최소 하나 남게(ε² > 0)
  lam <- pmax(e$values[seq_len(k)], 0)
  V <- e$vectors[, seq_len(k), drop = FALSE]
  dk <- as.numeric((V^2) %*% lam)                           # 남긴 모드가 설명하는 상관 대각 몫(종목별)
  s2 <- s^2
  eps2 <- max((sum(s2) - sum(s2 * dk)) / sum(s2), 1e-8)     # 식 (4) 'Tr C = Σ_i σ_i²' — 공분산 총분산 보존
  Cc <- V %*% (lam * t(V)) + eps2 * diag(n)
  list(Sigma = (s %o% s) * Cc, k = k, eps2 = eps2, sd = s)
}

## 적용 상한 = 축 값(ctx$ub · 유한 · 양수일 때만 · 1 이상이면 상한 없음) — 머리 주석 ④
.ecm_cap <- function(ub) {
  u <- suppressWarnings(as.numeric(ub)[1])
  if (length(u) && is.finite(u) && u > 0) min(u, 1) else 1
}

method_weights <- function(ctx) {
  a <- ctx$assets
  n <- length(a)
  if (n < 3L) stop("자산 3종 미만 — 하네스가 먼저 EW 로 처리한다")
  cap <- .ecm_cap(ctx$ub)
  dd <- if (is.null(ctx$decision_date)) "NA" else format(ctx$decision_date)
  if (n * cap < 1 - 1e-12) {
    cat(sprintf("[ecm] d=%s n=%d k=NA cap=%.2f active=NA capbind=NA eps2=NA infeasible=1\n", dd, n, cap))
    stop(sprintf("상한 불능 — 종목 %d × 상한 %.2f < 1(어떤 롱온리 비중도 상한을 못 지킨다)", n, cap))
  }
  X <- ctx$R[, a, drop = FALSE]
  cc <- .ecm_clean_cov(X)
  if (cap < 1 && n * cap < 1 + 1e-12) {
    ## n·c = 1(예: 5종 × 0.20) — 가능해는 EW 하나뿐이다. 상한 제약 n 개의 법선 합이 0 이라 일차종속 → quadprog 가 반올림으로
    ##   'constraints are inconsistent' 를 던질 수 있어(재점검 권고 · 10-15) 계획을 풀지 않고 그 유일해를 낸다(진단 줄은 그대로)
    x <- rep(1, n)
  } else {
    p <- rep(1, n)                                          # 머리 주석 ③ — 보유 종목의 전 종목 순위 예측자 ≈ 1
    Am <- if (cap < 1) cbind(diag(n), cap * matrix(1, n, n) - diag(n)) else diag(n)   # x ≥ 0 (· 상한이 있으면 c·Σx − x_i ≥ 0 — 머리 주석 ④)
    s0 <- mean(diag(cc$Sigma))                              # 척도 정규화(Σ̃/s0) — 해는 비례만 바뀌어 정규화 뒤 같다 · quadprog 절대 허용오차를 1/σ² 척도에서 떼어 낸다
    sol <- quadprog::solve.QP(Dmat = cc$Sigma / s0, dvec = p, Amat = Am, bvec = rep(0, ncol(Am)))
    x <- pmax(sol$solution, 0)
    x[x < 1e-10 * sum(x)] <- 0                              # 0 에 묶인 종목의 ±1e-17 급 잔차 — 하네스(Weight != 0)가 보유로 세어 MC3 보유 수 · 축 감사 n 을 부풀린다
  }
  w <- x / sum(x)
  cat(sprintf("[ecm] d=%s n=%d k=%d cap=%.2f active=%d capbind=%d eps2=%.4f infeasible=0\n", dd, n, cc$k, cap,
              sum(w > 1e-8), sum(w >= cap - 1e-6), cc$eps2))
  setNames(x, a)
}
