# isotropic_corr_cov.R — arXiv 2411.08864 Giller(2024) "Isotropic Correlation Models for the Cross-Section of Equity Returns"
#   — 이분산 등방 상관 공분산 추정기(2026-11-11 · 비중 규칙용 Σ 추정기 후보 · 생성기 연결 · 등재는 호출자 몫).
#   ★독립 파일 — 다른 파일을 source 하지 않는다(기본 R + stats 만). 난수 없음(결정적).
#   ★식 번호는 arXiv LaTeX 원본의 \eqnlab 표식 이름으로 단다(조판본 번호는 확인하지 않았다). 절 번호 = LaTeX 절 순서.
#   개정 2026-11-11(검수 반영): ρ 추정량 = §2.3 식을 **표준화 수익**에 적용한 값(= 전 쌍 표본 상관의 평균). 원자료 판은 진단.
#
# 논문 메커니즘(원문):
#   · 모형 §1.1 Definition · 식 (Vdef): 'V[r_it, r_jt] = σ_i σ_j ρ ⇔ V[r_t] = S_N G_N S_N' — G_N = 대각 1 · 비대각 ρ 인
#     등방 상관행렬, S_N = diag(σ_1 … σ_N)(이분산 — σ_i 는 종목마다 다르다). 원문은 이를 'more as an aide to exposition than
#     a serious proposal' 인 장난감 모형으로 소개한다(Grinold & Kahn 인용). 'these parameters may all be read with an implicit
#     time index, i.e. σ_it and ρ_t'.
#   · 허용 범위 §1.5 · 부록 Definition: 'all other entries equal to a constant ρ ∈ [1/(1−N), +1]' · V_P ≥ 0 에서
#     '1 + (N−1)ρ ≥ 0 ⇒ ρ ≥ −1/(N−1)'. 부록 Corollary (singular): 'G_N is singular if ρ = 1 or ρ = 1/(1−N)'.
#     ⇒ 양정치 = 열린 구간 −1/(N−1) < ρ < 1(닫힌 끝점은 특이).
#   · 고유분해 §1.7 · 부록 Theorem (eigen): 'G_N has N−1 eigenvalues equal to 1−ρ and one eigenvalue equal to 1+(N−1)ρ'
#     (시장 모드 고유벡터 ∝ 1_N).
#   · 역행렬 §3.1(부록 Theorem inv2 에서): 'G_N^{-1} = I_N/(1−ρ) − ρ 1_N 1_Nᵀ / ((1−ρ){1+(N−1)ρ})'.
#   · 평균 상관 §2.1 탐색: 무작위 5,000 쌍 표본 상관의 평균 — 'a mean Pearson correlation coefficient of +17%'.
#   · ρ 추정 식 §2.3 Results of Experiment:
#       'the data appears to be consistent with the functional form expected for an homoskedastic isotropic covariance matrix.
#        For this data set, ρ̂ under this assumption, may be estimated as ρ̂ = (N_max − N*) / ((N_max − 1) N*)'
#       — N* = 동일가중 포트폴리오의 유효 자유도, 식 (Nstar) 'N* = N/(1 + V_C/V_I) = N V_I / V_P' · §1.2 'V_I = tr Σ / N²' ·
#       V_P = 동일가중 포트폴리오 분산(= gs Σ / N², gs = 원소 총합). 절차 §2.2 단계 3~4. 이 식은 **등분산** 식 (isovar)
#       'V_P = σ² (1+(N−1)ρ)/N ⇒ N* = N/(1+(N−1)ρ)' 의 역산이고, 원문은 그 가정('under this assumption')에 한정한다.
#       (S&P 500 실증 값 13.27% — §2.1 평균 상관 17% 보다 작다.)
#   · 추정 표본 §2: 'Results are presented for the adjusted daily returns of members of the S&P 500 Index since the last index
#     re-balance … the last index re-balance was on September 30th., 2024'(집필 2024-10 · 약 한 달 이내의 일별 수익 · 503종).
#     ★이 함수는 호출자가 준 창 R 을 그대로 쓴다(우리 쪽 기본 252 거래일). 논문 창(≈ 한 달 · 생존 편향 회피 목적)과 다르다 —
#       창 길이는 호출자 결정이며 이 추정량의 표본 잡음 · 국면 민감도는 창에 따라 달라진다.
#   · 평균-분산 해 §3.1 식 (mvoiso)(Σ = S_N G_N S_N · z = S_N^{-1} α · N z̄ = 1ᵀz):
#       ĥ = S_N^{-1} / (2λ(1−ρ)) · { z − N ρ z̄ 1_N / (1+(N−1)ρ) }
#     등분산 극한: 'lim_{N→∞} ĥ = (α − ᾱ 1_N) / (2λ(1−ρ)σ²)'. 함수로 구현하지 않는다 — 시험 (e) 가 solve(Σ, μ) 와 대조한다.
#
# ★이 구현의 ρ̂ — §2.3 식을 표준화 수익에 적용(유도):
#   이분산 모형에서 등분산 가정이 성립하는 것은 표준화 수익 u_it = r_it / σ̂_i(자기 표본 표준편차로 나눈 것)다.
#   u 의 표본공분산 = 표본 상관행렬 C(대각 1 · 비대각 c_ij) 이므로
#       V_I = tr C / N² = 1/N ,   V_P = gs C / N² = (N + Σ_{i≠j} c_ij) / N² ,
#       N* = N V_I / V_P = N / (1 + (N−1) c̄) ,   c̄ = Σ_{i≠j} c_ij / (N(N−1))(전 쌍 평균),
#       ρ̂ = (N − N*) / ((N−1) N*) = c̄ .
#   즉 ρ̂ = 전 쌍 표본 상관의 평균 = §2.1 의 평균 피어슨 상관과 같은 양이다(무작위 5,000 쌍 대신 전 쌍).
#   이유 = 일치성: 원자료에 §2.3 식을 그대로 쓰면 이분산 등방 모형에서
#       ρ̂_raw → ρ · ((Σσ_i)² − Σσ_i²) / ((N−1) Σσ_i²) ≤ ρ  (등분산일 때만 등호)
#   로 ρ 보다 작게 수렴한다(편의 — 시험 (a2)). 논문 실증의 17%(평균 상관) 대 13.3%(원자료 식) 차이도 이 편의와 같은 방향이다.
#   원자료 판은 진단 rho_nstar_raw(· N_star_raw · V_I_raw · V_P_raw)로 남긴다.
#
# ★원문 주의:
#   · §2.3 본문 수치 불일치: 'measured to be 7.44. This gives ρ̂ = (503−7.12)/(502×7.12) ≈ 13.27%' — 7.44 와 7.12 가 섞여 있다
#     (식 자체는 일관). 이 구현은 식만 쓴다.
#   · §2.3 끝의 다른 추정 — N ∈ [300, 502] 부분 포트폴리오 N* 회귀 절편을 식 (doflim) 'lim N* = 1/ρ' 로 읽은 값(13.6%) — 은
#     무작위 부분 포트폴리오 1,000 개가 필요하다(난수 · 대형 N 전제) → 구현 안 함.
#
# 논문이 준 것 / 이 구현이 정한 것:
#   [논문] §1.1 이분산 모형 Σ = S_N G_N S_N · §2.1 평균 상관(무작위 쌍) · §2.3 식 ρ̂ = (N − N*)/((N−1)N*) 와 그 등분산 가정 ·
#          N* = N V_I/V_P · 허용 범위 [−1/(N−1), 1] · 끝점 특이 · 고유값 1+(N−1)ρ / 1−ρ · G_N^{-1} 닫힌 식 · 평균-분산 해 (mvoiso).
#   [구현] ① 이분산 자료에서는 §2.3 식을 표준화 수익에 적용한다(= 전 쌍 표본 상관 평균) · 이유 = 일치성(위 유도).
#             원자료 판 = 진단 rho_nstar_raw(V_P_raw ≤ 0 이면 NA).
#          ② σ_i² = 표본분산(stats::cov · 분모 T−1 — 논문은 'individual variances of daily returns' 로 분모를 정하지 않는다).
#             표준화도 같은 표본 표준편차(상관행렬 = cov2cor(표본공분산)).
#          ③ 경계 처리: 양정치 = 두 고유값 1+(N−1)ρ̂ · 1−ρ̂ 모두 > ISO_EIG_TOL(= sqrt(.Machine$double.eps) ≈ 1.49e-8 · 수치 허용오차 ·
#             논문 수치 아님). 그 아래(끝점 · 밖)면 stop — 끝점 절단(clamp)이나 표본공분산 낙하를 하지 않는다. 촐레스키 확인 1회.
#          ④ 입력 검사: N ≥ 2 · T ≥ 2 · 열 이름 필수(중복 금지) · 결측/비유한 · 분산 0 열은 이름을 부르고 stop.
#          ⑤ 대각 = 표본분산을 비트 그대로 넣는다(sqrt 왕복 반올림 제거).
#
# KR 롱온리 사상: 엔진이 고른 ≤25종의 일별 수익 창을 받아 Σ 만 낸다. 비중은 호출자(gen_sigma 를 쓰는 비중 규칙)가 정한다.
#   25종 · 252일이면 추정 모수는 σ 25개 + ρ 1개 — 표본공분산(325개)보다 훨씬 적다(축소 정도는 데이터가 아니라 모형 구조가 정한다).
# PIT: R 밖의 자료를 읽지 않는다. 창은 호출자가 신호일 전(Date < 신호일)으로 자른다(C1 · C2). 전기간 통계 없음. 난수 없음.
# 조용한 낙하 금지(_gen_sigma.R 규약): 어떤 실패도 표본공분산을 돌려주지 않는다 — 이름을 부르고 stop, 처리는 호출자.
# 반환: N×N 공분산(대칭 · 양정치 · dimnames = colnames(R)) + attr(, "iso_diag") 진단 목록.

ISO_EIG_TOL <- sqrt(.Machine$double.eps)   # [구현 ③] 양정치 판정의 수치 허용오차(논문 수치 아님)

isotropic_corr_cov <- function(R) {
  if (is.data.frame(R)) R <- as.matrix(R)
  if (!is.matrix(R) || !is.numeric(R)) stop("isotropic_corr_cov: R 은 수치 행렬(관측 × 자산)이어야 한다")
  a <- colnames(R)
  N <- ncol(R); TT <- nrow(R)
  if (is.null(a) || any(!nzchar(a)) || anyDuplicated(a)) stop("isotropic_corr_cov: 열 이름(자산)이 없거나 중복이다")
  if (N < 2L) stop(sprintf("isotropic_corr_cov: 자산 %d종 — 공통 상관은 2종 이상에서만 정의된다", N))
  if (TT < 2L) stop(sprintf("isotropic_corr_cov: 관측 %d행 — 분산을 잴 수 없다", TT))
  bad <- a[colSums(!is.finite(R)) > 0]
  if (length(bad)) stop(sprintf("isotropic_corr_cov: 결측 · 비유한 값이 있는 자산 %d종 — %s", length(bad), paste(bad, collapse = ",")))

  S0 <- stats::cov(R)
  v <- diag(S0)
  zv <- a[!(v > 0)]
  if (length(zv)) stop(sprintf("isotropic_corr_cov: 분산 0 자산 %d종 — %s(상관 정의 불가)", length(zv), paste(zv, collapse = ",")))

  ## 진단 — 원자료에 §2.3 식을 그대로 적용한 판(이분산이면 편의 · 머리말 유도)
  V_I_raw <- sum(v) / N^2                   # tr Σ / N²
  V_P_raw <- sum(S0) / N^2                  # gs Σ / N² = 동일가중 포트폴리오 표본분산
  N_star_raw <- if (V_P_raw > 0) N * V_I_raw / V_P_raw else NA_real_
  rho_nstar_raw <- if (is.finite(N_star_raw)) (N - N_star_raw) / ((N - 1) * N_star_raw) else NA_real_

  ## 본 추정 — §2.3 식을 표준화 수익에 적용 = 전 쌍 표본 상관 평균(머리말 유도 · [구현 ①])
  Cs <- stats::cov2cor(S0)
  rho <- mean(Cs[upper.tri(Cs)])
  lo <- -1 / (N - 1); hi <- 1               # 허용 범위(닫힌 끝점은 특이 — 부록 Corollary singular)
  lam_mkt <- 1 + (N - 1) * rho              # 시장 모드 고유값(§1.7)
  lam_res <- 1 - rho                        # 나머지 N−1 개 고유값
  if (!is.finite(rho) || !(lam_mkt > ISO_EIG_TOL && lam_res > ISO_EIG_TOL))
    stop(sprintf(paste0("isotropic_corr_cov: 허용 범위 밖 — ρ̂ = %.6f · 열린 구간 (%.4f, 1) 이 아니다",
                        "(고유값 1+(N−1)ρ̂ = %.3e · 1−ρ̂ = %.3e · 문턱 %.1e)"), rho, lo, lam_mkt, lam_res, ISO_EIG_TOL))

  ## 식 (Vdef) Σ = S_N G_N S_N
  G <- matrix(rho, N, N); diag(G) <- 1
  s <- sqrt(v)
  S <- (s %o% s) * G
  diag(S) <- v                              # [구현 ⑤] 대각 = 표본분산 그대로
  dimnames(S) <- list(a, a)
  ok_chol <- tryCatch({ chol(S); TRUE }, error = function(e) FALSE)
  if (!ok_chol) stop(sprintf("isotropic_corr_cov: 촐레스키 실패 — ρ̂ = %.6f 에서 Σ 가 수치적으로 양정치가 아니다", rho))

  attr(S, "iso_diag") <- list(
    estimator     = paste0("arXiv 2411.08864 §2.3 rho_hat = (N - N*)/((N - 1) N*) applied to standardized returns ",
                           "(r_i / sd_i) = mean pairwise sample correlation (§2.1) · raw-return version = rho_nstar_raw"),
    rho           = rho,
    rho_feasible  = c(lower = lo, upper = hi),   # 닫힌 끝점은 특이 — 허용은 열린 구간
    eig_tol       = ISO_EIG_TOL,
    eig_corr      = c(market = lam_mkt, residual = lam_res),
    n_assets      = N,
    n_obs         = TT,
    rho_nstar_raw = rho_nstar_raw,               # 진단 — 원자료 §2.3 식(이분산이면 ρ 보다 작게 수렴)
    N_star_raw    = N_star_raw,
    V_I_raw       = V_I_raw,
    V_P_raw       = V_P_raw
  )
  S
}
