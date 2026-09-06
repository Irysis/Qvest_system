# =============================================================================
# engine.R — RP_AUTO_COMBO_combo_1403_8125_2007_081   (2판 · 2026-09-06 · 4편 재료)
#
#   [H] Borri · Chetverikov · Liu · Tsyvinski, "One Factor to Bind the Cross-Section
#       of Returns" (arXiv:2404.08129 · NBER w32365)   https://arxiv.org/abs/2404.08129
#   [A] Choi · Choi · Kang, "Maximum drawdown, recovery, and momentum"
#       (arXiv:1403.8125)                               https://arxiv.org/abs/1403.8125
#   [B] Polimenis, "Uncovering a factor-based expected return conditioning structure
#       with Regression Trees jointly for many stocks" (arXiv:2007.08115)
#       — **스코어에 넣지 않는다. 잔차 패널의 진단(F4)에만 쓴다** (FIDELITY.changed ③(1))
#   [C] Pinchuk, "Labor Income Risk and the Cross-Section of Expected Returns"
#       (arXiv:2301.09173) — **미사용** (FIDELITY.changed ③(2))
#
# ★fidelity = COMBINATION. 선언 정본 = FIDELITY.json (이 주석은 사본이지 통로가 아니다)
# ★1판(2026-09-05 · [A]+[B] · Score = CM + R_II^sys)은 측정됐다: Grade C · PORT_t 0.691 ·
#   MDD 0.566 · Calmar 0.235 (stage_artifacts/replication/20260905_142502_37820). 자기 반증
#   조건(MDD<0.577 ∧ Calmar>0.240) 중 Calmar 가 깨졌다 → 그 설계는 폐기. 이 판은 재료가
#   4편으로 늘어난 재발행 요청에 대한 **새 설계**이지 1판의 수리가 아니다.
#
# =============================================================================
# 한 문장 요약
# =============================================================================
#   [H] 는 "양의 단일 요인 하나가 횡단면을 묶는다(binds)" 고 주장한다 — r_it = h(f_t λ_i) + ε_it.
#   그 주장이 KR 에서 참이면 잔차 ε 는 가격이 매겨지지 않은 잡음이고, 거짓이면 잔차에는
#   그 요인이 설명하지 못한 **종목 고유의 정보**가 남는다. [A] 의 규칙 CM = C − MDD 는
#   "매끄럽게 누적된 수익" 을 고르는 경로 규칙이다. 이 판은 [A] 의 규칙을 원수익 경로가
#   아니라 **[H] 의 잔차 경로**에 적용한다:
#     Score_i = CM( ε_i,f−5 … ε_i,f ),   ε_it = r_it − ĥ(φ̂_t l̂_i)
#   즉 "[H] 가 가격을 매긴 것을 걷어낸 뒤, 남은 것이 매끄럽게 쌓인 종목" 을 산다.
#
# =============================================================================
# §1. [H] 원문 대조  (본 세션 2026-09-06 · arxiv.org/html/2404.08129v1 = 이론부만 렌더 ·
#      §5.7/Table 8 은 r.jina.ai 텍스트 프록시 경유 arXiv PDF + NBER w32365 PDF 2-source)
# =============================================================================
#  (H1) 모형   "r_{it}=h(f_t λ_i)+ε_{it}, i=1,…,N, t=1,…,T" · f_t > 0 · λ_i > 0 · h 연속
#  (H2) 추정   식(4) argmin Σ_i Σ_t ( r_it − Σ_{j=0}^{K} c_j (φ_t l_i)^j )²,
#              {c_j} ∈ R^{K+1} · {φ_t} ∈ (0,1]^T · {l_i} ∈ (0,1]^N ·
#              "in practice, we find that these constraints are not binding if the constant
#               L is chosen large enough" → c 는 무제약 OLS.
#  (H3) 3단계  "First, we calculate the initial values of {φ_t} and {l_i} as the first left
#              and right singular vectors of the T×N matrix {r_it} shifted and scaled in a way
#              to make sure that their components are taking values in the (0,1] interval.
#              Second, we perform gradient descent starting from the initial values to find a
#              local minimum of the optimization problem. Third, we reoptimize each component
#              of the sequences {φ_t} and {l_i} in turn multiple times until the change in the
#              criterion function from reoptimization becomes negligible."
#  (H4) 차수   Table 8 주석 "The HFL model is based on a degree of the polynomial used to
#              approximate the function h(.) equal to 4." · 초록 "polynomials of degree as low
#              as 2–4 suffice for the majority of empirical results"
#  (H5) 자료   "Returns are monthly and in excess of the US risk-free rate (Ken French)" ·
#              Table 1 헤더 'Mean (R_i,t, %)' → 퍼센트 단위 · 171 자산(주식·채권·상품·통화
#              포트폴리오) · 1988-01~2017-12
#  (H6) §5.7   "We start by estimating the model on all 171 assets and the first 120 months
#              of data. Next, we use the model predicted returns to sort assets in five
#              portfolios, and compute the equally-weighted average portfolio return in the
#              following six months. Finally, we repeat the procedure expanding the estimation
#              window by 6 months each time until the end of the sample" ·
#              "In each period t, we sort assets only using information available up to
#              period t" · Table 8: P1 0.079% … P5 0.769% · LS 0.689%/월 · SR 0.147
#  (H7) 주장   §5.1 adjusted R² 89% · "Most known finance and macro factors become
#              insignificant" (HFL 통제 후) — 이것이 본 판이 검정하는 명제다.
#  (H8) ★원문은 ĥ 의 형태(단조·볼록)와 f̂_t·λ̂_i 의 성질(시장수익·베타와의 관계)을 **한 줄도
#       서술하지 않는다**(두 프록시 판독 모두 확인). 그래서 이 엔진은 그것을 진단으로
#       **인쇄**하지 가정하지 않는다.
#  (H9) 저장소 실측: 이 논문의 예측수익 정렬을 고정 축(top-25 롱온리 EW)에 올린 기저 =
#       Grade C · PORT_t 0.55 · IC −0.002 (stage_artifacts/replication/20260905_184253_720).
#       → [H] 의 **예측값**은 KR 횡단면을 못 가른다. 본 판은 예측값이 아니라 **잔차**를 쓴다.
#
# =============================================================================
# §2. [A] 원문 대조  (arxiv.org/html/1403.8125v1 · 본 세션 직접 대조 · 1판과 2-source)
# =============================================================================
#  (A1) 식(1)  "MDD=max_{τ∈(0,T)}(max_{t∈(0,τ)}(P(t)−P(τ)))" [로그가격]
#  (A2) 분해   "C = R_I + R_II + R_III = PP − MDD + R" · R_I 시작→peak · R_II peak→trough
#              (= −MDD) · R_III trough→말일(회복) · "R = R(t*, T)" · "t* is the moment for the
#              end of the maximum drawdown formation" · "R(t,τ) is the log-return between t and τ"
#  (A3) Table 1  C(1,1,1) · M(0,1,0) · R(0,0,1) · RM(0,1,1) · **CM(1,2,1)** · CR(1,1,2) · CMR(1,2,2)
#              CM 설명: "pays attention to the period of the maximum drawdown. It is a penalty
#              to the assets with the large drawdowns."
#  (A4) §3.2   "during 6 months (weeks) of estimation period, assets in market universes are
#              sorted in ascending order" · "numbers of groups are 10" · "Each group is
#              constructed as an equal-weighted portfolio" · "The winner group is at long
#              position and the loser group is at short position" · 6개월 보유 오버래핑
#  (A5) Table 3 (KOSPI 200 월간 6/6, 2003-01~2012-12): C 1.3305%/6.8258% · M 1.0234/6.5769 ·
#              R 0.3740/4.0823 · RM 1.2803/6.2406 · **CM 1.4330/7.0357(최우수)** · CR 1.1028/6.5956 ·
#              CMR 1.3106/6.7290. "The winner basket of the CM strategy achieves monthly 1.701%
#              … the return volatility of the position is only 8.062%"
#  (A6) §4.1.2 "the portfolios ranked by the maximum drawdown related selection rules are less
#              riskier in many reward-risk measures than the benchmark"
#  (A7) 형성창 내부 표본주기(일별/월별)는 원문 미명시(§3.1 은 자료원·기간만). 위험 측정만
#              "calculated from the daily time series of the overlapping portfolio".
#  (A8) 저장소 실측(같은 고정 축): [A] CM 원수익판 = cell B1_1 · PORT_t 0.925 · SR 0.631 ·
#       CAGR 0.138 · MDD 0.577 · Calmar 0.240 · Grade C
#       (06_Registry/reinforce_ledger_l1.json · RP_20260904_163647_18444_rescued_rulefast · n=1)
#
# =============================================================================
# §3. [B]·[C] — 왜 스코어에 없는가 (전문은 FIDELITY.changed ③)
# =============================================================================
#  [B] "in all cases (solo and joint) the most informative factor is the market excess return
#      factor" · "a single model capable of predicting simultaneously n stocks is built" ·
#      "correlation information enters the tree structure" · IBM 분기 −70bp 에서 "left branch,
#      IBM returns are expected to have ER = −180bp versus ER=30bp for the right".
#      → [B] 는 **공통 요인 하나 위의 조건부 기대수익 구조**를 재는 도구다. 그 역할을 [H] 가
#        매끄러운 h 로 이미 맡았으므로, [B] 는 "[H] 가 걷어낸 뒤 꼬리 계단이 남는가" 를 재는
#        진단(F4)으로만 쓴다. 1판이 [B] 를 스코어(체계 낙폭 가중)에 넣은 결과 = C 0.691.
#  [C] CID_t = (1/N)Σ|R_it − R_MKT,t| · Δ(CID) AR 잔차 u · 24개월 β_CID · 5분위 VW ·
#      Q1 0.79% > Q5 0.30% · L/S −0.49%(t −3.19). 저장소 실측: KR 에서 cor(u, 시장) +0.43 ·
#      β_CID 정렬 = 시장베타 정렬 · 충실구현 Grade F(PORT_t −1.16). [H] 의 주장대로 요인이
#      하나뿐이면 [C] 의 상태변수는 그 요인과 공선이고, 실측이 정확히 그렇다 → 미사용.
#
# =============================================================================
# §4. 결합 연산자 — 무엇을 어떻게 붙였나 (평균이 아니다 · 스코어 층 블렌딩 0건)
# =============================================================================
#   월 m 의 초과수익 x_im = (r_im − rf_m)·100  (퍼센트, H5)
#   [H] 적합(반년, 확장창, H6): (ĉ, φ̂_1..T, l̂_i) = argmin 식(4), 3단계(H3) 그대로
#   형성월 f 의 창 W = {f−5, …, f}  ([A] 6개월, A4)
#   잔차 경로:  ε_im = x_im − ĥ(φ̂_m l̂_i),  path_i(0)=0, path_i(k) = Σ_{m≤k} ε_im
#   [A] 분해(A2)를 잔차 경로에:  t_s = argmin(path − cummax path) · t_p = argmax path[1..t_s]
#       R_I = path(t_p) · R_II = path(t_s) − path(t_p) (= −MDD^res) · R_III = path(6) − path(t_s)
#   ▸ Score_i = 1·R_I + 2·R_II + 1·R_III = C_i^res − MDD_i^res      (Table 1 CM, A3)
#
#   ★자유 파라미터 0 — K=4·창 120·반년 확장 = [H] · 6개월·(1,2,1) = [A] · 구현 상수 9종은
#     [H] 단독구현(RP_AUTO_2404_08129 v2, 감사 adapted)의 값을 그대로 승계.
#   ★퇴화 경계: [H] 가 KR 에서 완전하면(잔차 = 백색잡음) Score 는 정보가 없다 → PORT_t ≈ 0.
#     그 결과는 이 설계의 실패가 아니라 **[H] 의 KR 결속 주장에 대한 양성 판정**이다. 반대로
#     Score 가 [A] 원수익판(0.925)을 넘으면 [H] 의 요인이 KR 횡단면을 다 묶지 못한다는
#     반증이 된다. 어느 쪽이든 측정이 명제 하나를 닫는다.
#
# =============================================================================
# §5. PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다)
# =============================================================================
#  ▸ 구조 경계 1: 행렬 .RM 은 월 오름차순이고 형성월 f(행 ip)에서의 모든 접근은
#    `seq_len(ip)`·`seq.int(ip−5, ip)` 뿐이다. ip 를 넘는 인덱스·음수 shift·lead 0건.
#  ▸ 구조 경계 2: (ĉ, l̂) 는 f 이전 마지막 반년 적합(ip0 ≤ ip)의 것, φ̂_m 은 **그 달의
#    횡단면**만으로 성분별 정확 최소화(H3 3단계의 φ 블록 연산) — 전부 f 이하 정보.
#  ▸ 구조 경계 3: 적합 유니버스 = ip0 시점까지 **이미 관측된** 멤버십(첫 편입월 ≤ ip0 월).
#    스코어 자격 = f 당일 멤버십 + adv20 종점 f−1. 미래 명부 주입 0건.
#  C1 rolling/expanding 만(확장창 종점 = f) · C2 f 종가까지·집행은 러너가 익월 첫 거래일 ·
#  C3 신호창 종점 f < 보유월 · C4 재무 미사용 · C5 오버레이 없음 · C6 PIT 멤버십 ·
#  C7 shift 는 +1 뿐 · C10 adv20 = frollmean 후 shift(1) · C11 rf = **전월** 마지막 호가 ·
#  C13 부호 조작 0건(방향 = [A] 오름차순 정렬 하나) · C15 팩터 DB 미접근.
#
# =============================================================================
# §6. 산출
# =============================================================================
#   FACTORS(Date, Ticker, Score) — Score = C^res − MDD^res (퍼센트 단위, 클수록 롱).
#   러너 사양 = FIDELITY.json 의 portfolio_spec (top_n_long · ew · monthly · 25) ·
#   commission_paper = null. 기간 절단(2005-01-01~)은 러너가 적용한다.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(arrow)
  library(matrixStats)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.REQ <- c("Date", "Ticker", "Close", "Vol", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("[COMBO_HFL_CM] RAWDATA 열 부족: %s",
               paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))
.t0 <- Sys.time()
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# =============================================================================
# 0. 상수 — 출처가 셋뿐이다: [H] 명시값 · [A] 명시값 · 지시된 고정 축 (+ [H] 단독구현 승계 상수)
# =============================================================================
# ▸ [H] 에서 온 것
.K         <- 4L               # (H4) 다항 차수 4
.T0        <- 120L             # (H6) "the first 120 months of data"
.REFIT_MON <- c(6L, 12L)       # (H6) 반년마다 확장 재추정 — 6월말·12월말 시그널
.UNIT      <- 100              # (H5) 퍼센트 단위 'Mean (R_i,t, %)'
# ▸ [A] 에서 온 것
.FORM_M    <- 6L               # (A4) "during 6 months of estimation period"
.W         <- c(1, 2, 1)       # (A3) Table 1 CM = Cumulative return−MDD
# ▸ 지시된 고정 축 (두 논문에 없다)
.LIQ       <- 2e8              # adv20(t−1) 하한 (KRW)
.LIQ_WIN   <- 20L
# ▸ [H] 단독구현(RP_AUTO_2404_08129 v2) 승계 구현 상수 — 논문 미명시, 성과를 보고 고른 값 아님
.TMIN_I    <- 12L              # 종목이 추정에 참여하는 최소 월간 관측수
.EPS       <- 1e-6             # 열린구간 (0,1] 의 닫힌 근사 [EPS, 1]
.GD_MAXIT  <- 300L; .GD_TOL <- 1e-7; .GD_ARMIJO <- 1e-4; .GD_BT <- 40L
.CD_MAXIT  <- 50L;  .CD_TOL <- 1e-6; .ROOT_TOL  <- 1e-7
# ▸ [B] 진단 트리 전용
.MIN_LEAF  <- 2L

# =============================================================================
# 1. 보조 함수 — [H] 추정기는 RP_AUTO_2404_08129/engine.R(v2) 의 것을 그대로 승계
# =============================================================================
.as_flag <- function(x) {
  if (is.logical(x)) return(x %in% TRUE)
  if (is.numeric(x)) return(is.finite(x) & x != 0)
  toupper(trimws(as.character(x))) %in% c("TRUE", "T", "1", "Y", "YES")
}
# Σ_j cf[j+1] X^j (Horner) — X 는 벡터 또는 행렬, cf = (c_0, ..., c_K)
.polyval <- function(cf, X) {
  n <- length(cf)
  out <- X * 0 + cf[n]
  if (n > 1L) for (j in (n - 1L):1L) out <- out * X + cf[j]
  out
}
# h'(X) = Σ_j j c_j X^{j−1}
.polyder <- function(cf, X) {
  n <- length(cf)
  if (n < 2L) return(X * 0)
  .polyval(cf[-1L] * seq_len(n - 1L), X)
}
# 벡터를 [eps, 1] ⊂ (0,1] 로 아핀 사상 (H3 "shifted and scaled ... in the (0,1] interval")
.to_unit <- function(x, eps) {
  r <- range(x)
  y <- if (r[2L] > r[1L]) (x - r[1L]) / (r[2L] - r[1L]) else rep(1, length(x))
  eps + (1 - eps) * y
}
.relimp <- function(a, b) if (is.finite(a) && a > 0) (a - b) / a else 0

# ---- 3단계용: 한 블록(모든 φ_t 또는 모든 l_i)의 성분별 정확 최소화 ----
#   성분 하나의 목적함수는 그 성분의 2K차 다항식이다:
#     f(x) = Σ_m M_m (R_m − Σ_j a_mj x^j)²,  a_mj = c_j w_m^j (w = 고정 블록)
#   행 = 갱신 성분(n) · 열 = 고정 블록(m). Rm 은 결측 0 채움, Mm 은 0/1 마스크.
.block_argmin <- function(Rm, Mm, cf, w, cur, K, eps, root_tol) {
  P <- outer(as.numeric(w), 0:K, "^")            # m × (K+1) : w^j
  A <- sweep(P, 2L, cf, "*")                     # a_mj = c_j w_m^j
  B <- matrix(0, nrow(A), 2L * K + 1L)           # B[m, j+k] = Σ_{j+k} a_mj a_mk
  for (j in 0:K) for (k in 0:K)
    B[, j + k + 1L] <- B[, j + k + 1L] + A[, j + 1L] * A[, k + 1L]
  cst  <- rowSums(Rm * Rm)                       # Σ_m M R²  (결측 = 0)
  lin  <- -2 * (Rm %*% A)                        # n × (K+1)
  coef <- Mm %*% B                               # n × (2K+1)
  coef[, seq_len(K + 1L)] <- coef[, seq_len(K + 1L)] + lin
  coef[, 1L] <- coef[, 1L] + cst
  out  <- as.numeric(cur)
  mdeg <- seq_len(2L * K)
  for (r in seq_len(nrow(coef))) {
    cr <- coef[r, ]
    if (!all(is.finite(cr))) next
    cand <- c(out[r], eps, 1)                    # 현재값을 첫 후보로 — 동률이면 움직이지 않는다
    d  <- cr[-1L] * mdeg                         # f'(x) 계수 (오름차순)
    nz <- which(d != 0)
    if (length(nz) && max(nz) >= 2L) {
      d  <- d[seq_len(max(nz))]
      d  <- d / max(abs(d))
      rt <- polyroot(d)
      re <- Re(rt); im <- Im(rt)
      ok <- abs(im) <= root_tol * pmax(1, abs(re)) & re >= eps & re <= 1
      if (any(ok)) cand <- c(cand, re[ok])
    }
    v <- .polyval(cr, cand)
    out[r] <- cand[which.min(v)]
  }
  out
}

# ---- 식(4) 추정기 — [H] §2 의 3단계 그대로 (H3) ----
#   R0: T×N 초과수익(결측 0) · M: T×N 관측 마스크(0/1)
.fit_hfl <- function(R0, M, K, eps, gd_maxit, gd_tol, armijo, gd_bt, cd_maxit, cd_tol, root_tol) {
  obs <- which(M > 0)
  y   <- R0[obs]
  Xd0 <- matrix(1, length(obs), K + 1L)
  ols_c <- function(phi, l) {                    # c | (φ, l) = 관측 셀 OLS (H2: 무제약)
    x  <- outer(phi, l)[obs]
    Xd <- Xd0
    for (j in seq_len(K)) Xd[, j + 1L] <- Xd[, j] * x
    cf <- unname(lm.fit(Xd, y)$coefficients)
    if (!all(is.finite(cf)))
      stop("[COMBO_HFL_CM] 식(4) OLS 계수 비유한(퇴화 설계행렬) — 이 적합은 무효")
    cf
  }
  loss <- function(cf, phi, l) {
    E <- M * (R0 - .polyval(cf, outer(phi, l)))
    sum(E * E)
  }
  # ① 초기값: 제1 좌(u)/우(v) 특이벡터 → 결합 부호 규약(Σv > 0) → [eps,1] 아핀 사상
  sv <- svd(R0, nu = 1L, nv = 1L)
  u <- sv$u[, 1L]; v <- sv$v[, 1L]
  if (sum(v) < 0) { u <- -u; v <- -v }
  phi <- .to_unit(u, eps)
  l   <- .to_unit(v, eps)
  cf  <- ols_c(phi, l)
  L_init <- loss(cf, phi, l)
  if (!is.finite(L_init)) stop("[COMBO_HFL_CM] 초기 손실 비유한 — 패널 값 확인")
  # ② 사영 경사하강 on (φ, l), c 는 OLS 프로파일 (Armijo 역추적 · 박스 [eps,1] 사영)
  L0 <- L_init; alpha <- 1; it_gd <- 0L
  repeat {
    it_gd <- it_gd + 1L
    X <- outer(phi, l)
    G <- (M * (R0 - .polyval(cf, X))) * .polyder(cf, X)
    g_phi <- -2 * as.vector(G %*% l)
    g_l   <- -2 * as.vector(crossprod(G, phi))
    if (!any(g_phi != 0) && !any(g_l != 0)) break
    acc <- FALSE
    for (b in seq_len(gd_bt)) {
      phi_n <- pmin(1, pmax(eps, phi - alpha * g_phi))
      l_n   <- pmin(1, pmax(eps, l - alpha * g_l))
      dec   <- sum(g_phi * (phi_n - phi)) + sum(g_l * (l_n - l))
      L_n   <- loss(cf, phi_n, l_n)
      if (is.finite(L_n) && L_n <= L0 + armijo * dec) { acc <- TRUE; break }
      alpha <- alpha / 2
    }
    if (!acc) break
    phi <- phi_n; l <- l_n
    cf  <- ols_c(phi, l)
    L1  <- loss(cf, phi, l)
    rel <- .relimp(L0, L1)
    L0  <- L1
    alpha <- alpha * 2
    if (it_gd >= gd_maxit || rel < gd_tol) break
  }
  L_gd <- L0
  # ③ 성분별 재최적화: 모든 φ_t → 모든 l_i → c(OLS), 기준함수 상대변화 < cd_tol 까지
  it_cd <- 0L
  repeat {
    it_cd <- it_cd + 1L
    phi <- .block_argmin(R0, M, cf, l, phi, K, eps, root_tol)
    l   <- .block_argmin(t(R0), t(M), cf, phi, l, K, eps, root_tol)
    cf  <- ols_c(phi, l)
    L1  <- loss(cf, phi, l)
    rel <- .relimp(L0, L1)
    L0  <- L1
    if (it_cd >= cd_maxit || rel < cd_tol) break
  }
  list(cf = cf, phi = phi, l = l, loss_init = L_init, loss_gd = L_gd, loss = L0,
       it_gd = it_gd, it_cd = it_cd, n_obs = length(obs))
}

# ---- [A] 경로 분해 (A2) 를 열 단위로: E = 6×n 증분 행렬(퍼센트) → CM 스코어 ----
#   path = c(0, cumsum) · trough = argmin(path − cummax) · peak = argmax(path[1..trough])
.path_score <- function(E) {
  n    <- ncol(E)
  path <- rbind(0, colCumsums(E))                # (L+1) × n · path[1] = 0
  dd   <- path - colCummaxs(path)                # <= 0 (포함형 cummax)
  L1   <- nrow(path)
  sc <- numeric(n); mdd <- numeric(n); ri <- numeric(n); riii <- numeric(n)
  for (j in seq_len(n)) {
    p  <- path[, j]
    ts <- which.min(dd[, j])                     # trough (동값이면 최초)
    tp <- which.max(p[seq_len(ts)])              # trough 이전(포함) peak
    RI <- p[tp]; RII <- p[ts] - p[tp]; RIII <- p[L1] - p[ts]
    sc[j]   <- .W[1] * RI + .W[2] * RII + .W[3] * RIII
    mdd[j]  <- -dd[ts, j]
    ri[j]   <- RI; riii[j] <- RIII
  }
  list(score = sc, mdd = mdd, C = path[L1, ], RI = ri, RIII = riii)
}

# ---- [B] joint depth=1 회귀트리 — 패널 Y0(T×N, 결측 0)·마스크 Mn 을 분기변수 x 로 한 번 가른다 ----
#   반환: SSE 감소분/TSS(전 종목 합), 임계값, 좌잎 비중. 진단 전용(F4).
.tree_gain <- function(Y0, Mn, x) {
  ok <- is.finite(x)
  Y0 <- Y0[ok, , drop = FALSE]; Mn <- Mn[ok, , drop = FALSE]; x <- x[ok]
  Tn <- nrow(Y0)
  if (Tn < 2L * .MIN_LEAF + 1L || ncol(Y0) < 2L) return(NULL)
  o  <- order(x); xs <- x[o]
  Ys <- Y0[o, , drop = FALSE] * Mn[o, , drop = FALSE]
  Ms <- Mn[o, , drop = FALSE]
  CX <- colCumsums(Ys); CM <- colCumsums(Ms)
  SX <- CX[Tn, ]; SM <- CM[Tn, ]
  RX <- matrix(SX, Tn, ncol(Ys), byrow = TRUE) - CX
  RN <- matrix(SM, Tn, ncol(Ys), byrow = TRUE) - CM
  LT <- CX^2 / CM; RT <- RX^2 / RN
  LT[!is.finite(LT)] <- 0; RT[!is.finite(RT)] <- 0
  root <- SX^2 / SM; root[!is.finite(root)] <- 0
  gn  <- rowSums(LT + RT) - sum(root)
  okv <- c(xs[-Tn] < xs[-1L], FALSE)
  okv[seq_len(.MIN_LEAF - 1L)] <- FALSE
  okv[(Tn - .MIN_LEAF + 1L):Tn] <- FALSE
  if (!any(okv)) return(NULL)
  gn[!okv] <- -Inf
  ks  <- which.max(gn)
  tss <- sum(Ys^2) - sum(root)
  list(ratio = if (tss > 0) gn[ks] / tss else NA_real_,
       split = (xs[ks] + xs[ks + 1L]) / 2, bal_left = ks / Tn)
}

# =============================================================================
# 2. 일간 패널 → 멤버십 · 유동성(t−1) · 월 인덱스   (RAWDATA 비파괴 — 러너가 재사용)
# =============================================================================
.rd <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]
if (!inherits(.rd$Date, "Date")) .rd[, Date := as.Date(Date)]
.rd[, Ticker := as.character(Ticker)]
.rd <- .rd[is.finite(Close) & Close > 0]
.rd[, MEM := .as_flag(K200) | .as_flag(KQ150)]
.rd[, c("K200", "KQ150") := NULL]
setorder(.rd, Ticker, Date)
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[COMBO_HFL_CM] (Ticker,Date) 중복 %d행 — 첫 행만 유지\n", .ndup))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}
# 거래대금(거래량 결측 = 그날 회전 0). adv20 후 shift(1) → 종점 t−1 (C10)
.rd[, TV := Close * fifelse(is.finite(as.numeric(Vol)), as.numeric(Vol), 0)]
.rd[, ADV20_L1 := shift(frollmean(TV, .LIQ_WIN, align = "right"), 1L), by = Ticker]
.rd[, c("TV", "Vol") := NULL]
.rd[, MI := year(Date) * 12L + month(Date)]

# 시장 월말(그 달 마지막 거래일). RAWDATA 의 마지막 달은 진행 중(부분월)으로 보고 제외 ([H] 단독구현 규약)
.me <- .rd[, .(MEnd = max(Date)), by = MI]
setorder(.me, MI)
.MI_LAST <- max(.me$MI)
.me <- .me[MI < .MI_LAST]
.me[, MON := (MI - 1L) %% 12L + 1L]
if (nrow(.me) < .T0 + .FORM_M) stop("[COMBO_HFL_CM] 완결 월이 창 길이에 못 미침 — RAWDATA 날짜 범위 확인")

# 첫 편입월(PIT 멤버십 이력) — 적합 유니버스는 ip0 시점까지 **이미 편입된 적 있는** 종목만
.fm <- .rd[MEM == TRUE, .(MI_first = min(MI)), by = Ticker]
if (!nrow(.fm)) stop("[COMBO_HFL_CM] K200/KQ150 멤버십 0건 — RAWDATA 확인")
.first_mem <- setNames(.fm$MI_first, .fm$Ticker)

# =============================================================================
# 3. 월간 수익률 패널 → 초과수익(퍼센트)   rf = 전월 마지막 호가 / 100 / 12 (C11)
# =============================================================================
.rs <- .rd[MI < .MI_LAST, .(Ticker, MI, Date, Close)]
setorder(.rs, Ticker, Date)
.n <- nrow(.rs)
.lastrow <- c(.rs$Ticker[-1L] != .rs$Ticker[-.n] | .rs$MI[-1L] != .rs$MI[-.n], TRUE)
.mp <- .rs[.lastrow, .(Ticker, MI, Close)]
rm(.rs)
setorder(.mp, Ticker, MI)
.mp[, R := Close / shift(Close) - 1, by = Ticker]
.mp[, GAP := MI - shift(MI), by = Ticker]
.mp[is.na(GAP) | GAP != 1L, R := NA_real_]
.mp <- .mp[is.finite(R), .(MI, Ticker, R)]
if (!nrow(.mp)) stop("[COMBO_HFL_CM] 월간 수익률 0행")

# 무위험: ECOS 817Y002 일별 호가 캐시. 월 m 의 rf = m−1 월 마지막 호가(연 %)/100/12.
#   1순위 KR_CD91([H] 단독구현과 동일), 그 달에 없으면 KR_Call1D, 둘 다 없으면 0 (커버리지 인쇄).
.CACHE_DIR <- local({
  cd <- if (exists("CACHE_DIR", inherits = TRUE)) as.character(get("CACHE_DIR", inherits = TRUE))[1L] else ""
  if (!nzchar(cd)) {
    root <- Sys.getenv("QM_ROOT", "")
    if (!nzchar(root)) root <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
    if (!nzchar(root) && exists("PROJECT_ROOT", inherits = TRUE))
      root <- as.character(get("PROJECT_ROOT", inherits = TRUE))[1L]
    if (!nzchar(root)) root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
    cd <- file.path(root, ".cache")
  }
  cd
})
.rf_load <- function(cache_dir) {
  out <- data.table(MI = integer(0), RF = numeric(0), src = character(0))
  fp  <- file.path(cache_dir, "ecos_bond_rates.parquet")
  if (!file.exists(fp)) return(out)
  ec <- tryCatch(as.data.table(read_parquet(fp)), error = function(e) NULL)
  if (is.null(ec) || !all(c("Date", "Value", "Series") %in% names(ec))) return(out)
  ec <- ec[is.finite(Value)]
  if (inherits(ec$Date, "POSIXt")) ec[, Date := as.Date(Date, tz = "Asia/Seoul")] else ec[, Date := as.Date(Date)]
  ec <- ec[!is.na(Date)]
  setorder(ec, Date)
  ec[, MIq := year(Date) * 12L + month(Date)]
  for (s in c("KR_CD91", "KR_Call1D")) {
    d <- ec[Series == s, .(RF = Value[.N] / 100 / 12), by = MIq]      # 그 달 마지막 호가
    if (!nrow(d)) next
    d[, MI := MIq + 1L]                                                # m 월의 rf = m−1 월 호가
    d <- d[!(MI %in% out$MI), .(MI, RF, src = s)]
    out <- rbind(out, d)
  }
  setorder(out, MI)
  out
}
.rf_tbl <- .rf_load(.CACHE_DIR)
.mp <- merge(.mp, .rf_tbl[, .(MI, RF)], by = "MI", all.x = TRUE)
.mp[!is.finite(RF), RF := 0]
.mp[, X := (R - RF) * .UNIT]                                           # 퍼센트 초과수익 (H5)

# ★PIT 구조: .RM 은 월 오름차순 행렬. 아래 모든 추정·잔차 접근은 행 ip 이하뿐이다.
.wide <- dcast(.mp[, .(MI, Ticker, X)], MI ~ Ticker, value.var = "X")
setorder(.wide, MI)
.MIs <- .wide$MI
.RM  <- as.matrix(.wide[, setdiff(names(.wide), "MI"), with = FALSE])
.TK  <- colnames(.RM)
rm(.wide); gc(verbose = FALSE)

.ym <- function(mi) sprintf("%d-%02d", (mi - 1L) %/% 12L, (mi - 1L) %% 12L + 1L)
.rf_cov <- .rf_tbl[MI %in% .MIs]
cat(sprintf(paste0("[COMBO_HFL_CM] 월간 초과수익 패널 %d개월 (%s ~ %s) × %d종 · rf 커버 %d/%d개월",
                   " (CD91 %d · Call1D %d · 0 폴백 %d) · 첫 rf 월 %s\n"),
            length(.MIs), .ym(min(.MIs)), .ym(max(.MIs)), length(.TK),
            nrow(.rf_cov), length(.MIs), sum(.rf_cov$src == "KR_CD91"), sum(.rf_cov$src == "KR_Call1D"),
            length(.MIs) - nrow(.rf_cov), if (nrow(.rf_cov)) .ym(min(.rf_cov$MI)) else "없음"))

# 시장 월간 초과수익(퍼센트) — [B] 진단의 분기변수 전용. 부재면 F4 만 비운다.
.mexv <- rep(NA_real_, length(.MIs))
if (exists("BM_DT") && is.data.table(BM_DT) && nrow(BM_DT)) {
  .b <- copy(BM_DT)
  if (!inherits(.b$Date, "Date")) .b[, Date := as.Date(Date)]
  setorder(.b, Date)
  if (!"BM_Ret" %in% names(.b) && "BM_Close" %in% names(.b))
    .b[, BM_Ret := BM_Close / shift(BM_Close, 1L) - 1]
  if ("BM_Ret" %in% names(.b)) {
    .b <- .b[is.finite(BM_Ret)]
    .b[, MI := year(Date) * 12L + month(Date)]
    .bm <- .b[, .(BR = prod(1 + BM_Ret) - 1), by = MI]
    .bm <- merge(.bm, .rf_tbl[, .(MI, RF)], by = "MI", all.x = TRUE)
    .bm[!is.finite(RF), RF := 0]
    .bm[, MEX := (BR - RF) * .UNIT]
    .mexv <- .bm$MEX[match(.MIs, .bm$MI)]
  }
  rm(.b)
}

# =============================================================================
# 4. 형성일 · 적격 종목 (C6 멤버십 PIT · C10 유동성 t−1)
# =============================================================================
.ELIG <- .rd[Date %in% .me$MEnd & MEM & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ, .(Date, Ticker)]
setkey(.ELIG, Date)
rm(.rd); gc(verbose = FALSE)
if (!nrow(.ELIG)) stop("[COMBO_HFL_CM] 적격 종목 0건 — 멤버십/유동성 확인")

# =============================================================================
# 5. [H] 상태 — 반년 확장 적합 · 사이 달의 φ 블록 갱신 · 신규 종목의 l 블록 갱신
# =============================================================================
# 적합 유니버스: ip0 월까지 첫 편입월이 이미 지난 종목 중 관측 ≥ .TMIN_I (PIT 멤버십 이력).
.hfl_state <- function(ip0, mi0) {
  cols <- .TK[.TK %in% names(.first_mem)]
  cols <- cols[.first_mem[cols] <= mi0]
  if (length(cols) < 5L) return(NULL)
  ci <- match(cols, .TK)
  Rm <- .RM[seq_len(ip0), ci, drop = FALSE]      # ★확장창: 첫 달 ~ 시그널 월(ip0). ip0 초과 행 접근 없음
  M  <- is.finite(Rm)
  ki <- colSums(M) >= .TMIN_I
  if (sum(ki) < 5L) return(NULL)
  Rm <- Rm[, ki, drop = FALSE]; M <- M[, ki, drop = FALSE]; cols <- cols[ki]
  kt <- rowSums(M) >= 1L                         # 관측이 하나도 없는 달은 φ_t 가 정의되지 않아 제외
  rows <- which(kt)
  Rm <- Rm[kt, , drop = FALSE]; M <- M[kt, , drop = FALSE]
  if (length(rows) < 2L) return(NULL)
  R0 <- Rm; R0[!M] <- 0; Mn <- M * 1
  fit <- .fit_hfl(R0, Mn, .K, .EPS, .GD_MAXIT, .GD_TOL, .GD_ARMIJO, .GD_BT, .CD_MAXIT, .CD_TOL, .ROOT_TOL)
  phi <- rep(NA_real_, ip0); phi[rows] <- fit$phi
  ybar <- sum(R0) / sum(Mn)
  tss  <- sum(Mn * (R0 - ybar)^2)
  list(ip0 = ip0, mi0 = mi0, cf = fit$cf, phi = phi, l = setNames(fit$l, cols), tk = cols,
       rows = rows, R0 = R0, Mn = Mn, fit = fit, r2 = if (tss > 0) 1 - fit$loss / tss else NA_real_)
}
# 반년 적합 이후의 달: (ĉ, l̂) 고정, 그 달 횡단면만으로 φ_t 를 성분별 정확 최소화 (H3 3단계의 φ 블록)
.extend_phi <- function(st, ip) {
  n0 <- length(st$phi)
  if (ip <= n0) return(st)
  nr <- seq.int(n0 + 1L, ip)
  ci <- match(st$tk, .TK)
  Rm <- .RM[nr, ci, drop = FALSE]
  M  <- is.finite(Rm)
  R0 <- Rm; R0[!M] <- 0; Mn <- M * 1
  cur <- rep(stats::median(st$phi, na.rm = TRUE), length(nr))
  ph  <- .block_argmin(R0, Mn, st$cf, st$l, cur, .K, .EPS, .ROOT_TOL)
  ph[rowSums(Mn) < 1] <- NA_real_
  st$phi <- c(st$phi, ph)
  st
}
# 적합에 없던 적격 종목: (ĉ, φ̂) 고정, 그 종목의 과거 관측(행 ≤ ip)만으로 l_i 를 성분별 정확 최소화
.l_for_new <- function(st, ip, new_tk) {
  rows <- which(is.finite(st$phi[seq_len(ip)]))
  if (length(rows) < .TMIN_I) return(numeric(0))
  ci <- match(new_tk, .TK)
  Rm <- .RM[rows, ci, drop = FALSE]
  M  <- is.finite(Rm)
  ok <- colSums(M) >= .TMIN_I
  if (!any(ok)) return(numeric(0))
  Rm <- Rm[, ok, drop = FALSE]; M <- M[, ok, drop = FALSE]; new_tk <- new_tk[ok]
  R0 <- Rm; R0[!M] <- 0; Mn <- M * 1
  cur <- rep(stats::median(st$l), length(new_tk))
  lv  <- .block_argmin(t(R0), t(Mn), st$cf, st$phi[rows], cur, .K, .EPS, .ROOT_TOL)
  setNames(lv, new_tk)
}

# =============================================================================
# 6. 형성월 루프 — 반년 재적합 → φ 확장 → 잔차 경로 → [A] CM 스코어
# =============================================================================
.OUT <- vector("list", nrow(.me)); .LOG <- vector("list", nrow(.me)); .FIT <- list()
st <- NULL
.skip_warm <- 0L; .skip_def <- 0L; .n_fit_fail <- 0L; .n_fit_ok <- 0L
for (k in seq_len(nrow(.me))) {
  mi_f <- .me$MI[k]; d_f <- .me$MEnd[k]; mon <- .me$MON[k]
  ip <- match(mi_f, .MIs)
  if (is.na(ip) || ip < .T0) { .skip_warm <- .skip_warm + 1L; next }

  # ---- 반년 재적합 (H6: 6월말·12월말 시그널) — 실패 시 직전 상태 유지 + 건수 기록 ----
  if (mon %in% .REFIT_MON) {
    ns <- tryCatch(.hfl_state(ip, mi_f), error = function(e) {
      cat(sprintf("[COMBO_HFL_CM] %s 적합 실패 — %s (직전 상태 유지)\n", as.character(d_f), conditionMessage(e)))
      NULL })
    if (!is.null(ns)) {
      st <- ns; .n_fit_ok <- .n_fit_ok + 1L
      # [B] 진단: 잔차 패널 vs 원패널의 joint depth=1 트리 SSE 감소분 (분기변수 = 시장 월간 초과수익)
      Hf <- .polyval(st$cf, outer(st$fit$phi, st$fit$l))
      E0 <- (st$R0 - Hf) * st$Mn
      xm <- .mexv[st$rows]
      tr_raw <- .tree_gain(st$R0, st$Mn, xm)
      tr_res <- .tree_gain(E0, st$Mn, xm)
      .FIT[[length(.FIT) + 1L]] <- data.table(
        FormDate = d_f, T_rows = length(st$rows), N = length(st$tk), n_obs = st$fit$n_obs,
        loss_init = st$fit$loss_init, loss_gd = st$fit$loss_gd, loss = st$fit$loss,
        it_gd = st$fit$it_gd, it_cd = st$fit$it_cd, r2 = st$r2,
        cor_phi_mex = if (all(is.na(xm))) NA_real_ else
          suppressWarnings(stats::cor(st$fit$phi, xm, use = "pairwise.complete.obs", method = "spearman")),
        gain_raw = tr_raw$ratio %||% NA_real_, gain_res = tr_res$ratio %||% NA_real_,
        split_raw = tr_raw$split %||% NA_real_, split_res = tr_res$split %||% NA_real_,
        bal_raw = tr_raw$bal_left %||% NA_real_, bal_res = tr_res$bal_left %||% NA_real_)
      .fl <- .FIT[[length(.FIT)]]
      cat(sprintf(paste0("[COMBO_HFL_CM] 적합 %s | T=%d N=%d obs=%d | loss %.4g → gd %.4g (%d it) → cd %.4g (%d rounds)",
                         " | R² %.3f | c=(%s) | rho(phi,mex) %+.2f | tree gain raw %.4f / res %.4f | %.1f분\n"),
                  as.character(d_f), .fl$T_rows, .fl$N, .fl$n_obs, .fl$loss_init, .fl$loss_gd, .fl$it_gd,
                  .fl$loss, .fl$it_cd, .fl$r2, paste(sprintf("%.3g", st$cf), collapse = ","),
                  .fl$cor_phi_mex, .fl$gain_raw, .fl$gain_res,
                  as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
      rm(Hf, E0)
    } else .n_fit_fail <- .n_fit_fail + 1L
  }
  if (is.null(st)) { .skip_warm <- .skip_warm + 1L; next }     # 첫 반년 적합 전 = 워밍업

  # ---- 사이 달의 φ_t (그 달 횡단면만) ----
  st <- .extend_phi(st, ip)

  # ---- [A] 6개월 창: 달이 연속이고 φ 가 전부 정의돼야 경로가 성립한다 ----
  wr <- seq.int(ip - .FORM_M + 1L, ip)
  if (!identical(as.integer(.MIs[wr]), as.integer(mi_f - seq.int(.FORM_M - 1L, 0L)))) { .skip_def <- .skip_def + 1L; next }
  if (any(!is.finite(st$phi[wr]))) { .skip_def <- .skip_def + 1L; next }

  # ---- 자격: f 의 멤버십 + adv20(t−1) 하한 (C6 · C10) ----
  elig <- .ELIG[.(d_f), Ticker, nomatch = 0L]
  elig <- elig[elig %chin% .TK]
  if (length(elig) < 2L) { .skip_def <- .skip_def + 1L; next }

  # ---- 적재값 l̂: 적합에 있으면 그것, 없으면 (ĉ, φ̂) 고정 블록 갱신 ----
  lv <- st$l[elig[elig %chin% names(st$l)]]
  new_tk <- setdiff(elig, names(st$l))
  n_new <- 0L
  if (length(new_tk)) {
    ln <- .l_for_new(st, ip, new_tk)
    if (length(ln)) { lv <- c(lv, ln); n_new <- length(ln) }
  }
  if (length(lv) < 2L) { .skip_def <- .skip_def + 1L; next }
  tk <- names(lv)
  ci <- match(tk, .TK)
  Xw  <- .RM[wr, ci, drop = FALSE]                # 6 × n 퍼센트 초과수익
  okc <- colSums(is.finite(Xw)) == .FORM_M        # 6개월 전부 관측된 종목만 (경로 성립 조건)
  if (sum(okc) < 2L) { .skip_def <- .skip_def + 1L; next }
  Xw <- Xw[, okc, drop = FALSE]; tk <- tk[okc]; lv <- as.numeric(lv[okc])

  # ---- 잔차 경로 → [A] CM ----
  Hw <- .polyval(st$cf, outer(st$phi[wr], lv))     # 6 × n 모형 설명분 ĥ(φ̂_m l̂_i)
  E  <- Xw - Hw                                    # 잔차 ε_im (퍼센트)
  ps <- .path_score(E)                             # Score = C^res − MDD^res
  pr <- .path_score(Xw)                            # 대조군: 같은 규칙을 원(초과)수익 경로에 (F1)
  ok <- is.finite(ps$score)
  if (!any(ok)) { .skip_def <- .skip_def + 1L; next }
  .OUT[[k]] <- data.table(Date = d_f, Ticker = tk[ok], Score = ps$score[ok])

  # ---- 진단 (전부 행 ≤ ip 의 통계 — 미래참조 0) ----
  rows_ok <- which(is.finite(st$phi[seq_len(ip)]))
  pred <- colMeans(.polyval(st$cf, outer(st$phi[rows_ok], lv)))   # [H] 예측수익 (1/T)Σ_t ĥ(φ̂_t l̂_i)
  n25  <- min(25L, sum(ok))
  o_sc <- order(-ps$score, tk); o_raw <- order(-pr$score, tk); o_pr <- order(-pred, tk)
  top_sc <- tk[o_sc][seq_len(n25)]
  .LOG[[k]] <- data.table(
    f = d_f, N = sum(ok), n_elig = length(elig), n_scored_new = n_new, n_fit_l = sum(tk %chin% st$tk),
    rho_raw = if (sum(ok) >= 5L) suppressWarnings(stats::cor(ps$score, pr$score, method = "spearman")) else NA_real_,
    rho_pred = if (sum(ok) >= 5L) suppressWarnings(stats::cor(ps$score, pred, method = "spearman")) else NA_real_,
    ovl_raw = length(intersect(top_sc, tk[o_raw][seq_len(n25)])) / n25,
    ovl_pred = length(intersect(top_sc, tk[o_pr][seq_len(n25)])) / n25,
    l_top = mean(lv[o_sc][seq_len(n25)]), l_med = stats::median(lv),
    mdd_res_top = stats::median(ps$mdd[o_sc][seq_len(n25)]), mdd_res_all = stats::median(ps$mdd),
    C_res_top = stats::median(ps$C[o_sc][seq_len(n25)]), C_raw_top = stats::median(pr$C[o_sc][seq_len(n25)]),
    share_res_var = { v1 <- sum(E * E); v0 <- sum(Xw * Xw); if (v0 > 0) v1 / v0 else NA_real_ })
}

FACTORS <- rbindlist(Filter(Negate(is.null), .OUT), use.names = TRUE)
if (!nrow(FACTORS))
  stop(sprintf("[COMBO_HFL_CM] FACTORS 0행 — 워밍업 skip %d · 정의역 skip %d · 적합 성공 %d/실패 %d",
               .skip_warm, .skip_def, .n_fit_ok, .n_fit_fail))
setorder(FACTORS, Date, -Score)

# =============================================================================
# 7. 보고 — 구성 요약 + 엔진이 스스로 인쇄하는 반증 6종 (성과 수치 선언 아님 · 등급은 계약이 낸다)
# =============================================================================
LG <- rbindlist(Filter(Negate(is.null), .LOG), use.names = TRUE)
FT <- rbindlist(.FIT, use.names = TRUE)
.med <- function(x) { x <- as.numeric(x); x <- x[is.finite(x)]; if (length(x)) stats::median(x) else NA_real_ }

# F6 — ★세기 전에 범위를 선언한다: 분모 = 측정구간(2005-01-01~)의 월말 중 첫 반년 적합 이후의 것.
.RANGE0 <- as.Date("2005-01-01")
.first_fit <- if (nrow(FT)) min(FT$FormDate) else as.Date(NA)
.cand_f <- .me$MEnd[.me$MEnd >= .RANGE0 & !is.na(.first_fit) & .me$MEnd >= .first_fit]
.got_f  <- LG$f[LG$f >= .RANGE0]
.miss   <- !(.cand_f %in% .got_f)
.rl     <- rle(.miss)
.gapmax <- if (any(.miss)) max(.rl$lengths[.rl$values]) else 0L
.f1 <- .med(LG$ovl_raw); .f2 <- .med(LG$rho_pred); .f3 <- .med(FT$r2)
.f4a <- .med(FT$gain_raw); .f4b <- .med(FT$gain_res)
.f5 <- .med(LG$l_top - LG$l_med); .f5s <- .med(abs(LG$l_top - LG$l_med) / pmax(1e-9, LG$l_med))

cat(sprintf(paste0(
  "[COMBO_HFL_CM] combination: Score = CM([H] 잔차 경로) = C^res − MDD^res\n",
  "  [H] HFL 식(4) K=%d · 3단계(SVD→사영GD→성분별 재최적화) · 확장창 첫 %d개월 · 반년 재적합 %d회(실패 %d)\n",
  "  [A] 6개월 형성창 · Table 1 CM(1,2,1) · 잔차 증분 경로(퍼센트) · 월간 top-25 롱온리 EW(고정 축)\n",
  "  형성 %d개월(%s~%s · 워밍업 skip %d · 정의역 skip %d) · FACTORS %s행 · 횡단면 중앙 %d종",
  " (적합 내 l̂ 중앙 %d · 블록갱신 l̂ 중앙 %d)\n",
  "  [H] 적합: 패널 R² 중앙 %.3f · rho(φ̂, 시장초과) 중앙 %+.2f · 잔차분산/원분산 중앙 %.3f\n"),
  .K, .T0, .n_fit_ok, .n_fit_fail,
  nrow(LG), as.character(min(LG$f)), as.character(max(LG$f)), .skip_warm, .skip_def,
  format(nrow(FACTORS), big.mark = ","), as.integer(.med(LG$N)),
  as.integer(.med(LG$n_fit_l)), as.integer(.med(LG$n_scored_new)),
  .f3, .med(FT$cor_phi_mex), .med(LG$share_res_var)))

cat(sprintf(paste0(
  "[COMBO_HFL_CM] 반증 (전부 행 ≤ 형성월 통계 · 미래참조 0):\n",
  "  F1 [A] 재라벨 아님 : top-25 겹침(vs 원수익 CM) 중앙 %.3f          → %s (기준 < 0.80)\n",
  "  F2 [H] 재라벨 아님 : rho(Score, [H] 예측수익) 중앙 %+.3f           → %s (기준 |rho| < 0.50)\n",
  "  F3 [H] KR 결속도   : 패널 R² 중앙 %.3f (논문 US 횡단면 adj.R² 0.89 — 다른 양, 참고만)\n",
  "  F4 [B] 꼬리 계단   : joint depth=1 SSE 감소분/TSS 원패널 %.4f → 잔차패널 %.4f → %s\n",
  "     ★설계는 F4 에 의존하지 않는다 — 잔차에 계단이 남으면 [H] 의 매끄러운 h 가 꼬리를 못 담는다는 사실의 보고다.\n",
  "  F5 적재 편향 아님  : top-25 평균 l̂ − 유니버스 중앙 l̂ = %+.4f (상대 %.3f) → %s (기준 상대 < 0.10)\n",
  "  F6 월 결번 0       : [범위 = 2005-01-01~ ∧ 첫 적합 %s 이후] 후보 %d · 산출 %d · 최대 연속 결번 %d → %s\n",
  "  ★러너 사양 = FIDELITY.json 의 portfolio_spec (top_n_long · ew · monthly · n_max 25) · commission_paper = null · %.1f분\n"),
  .f1,  if (is.finite(.f1) && .f1 < 0.80) "PASS" else "FAIL",
  .f2,  if (is.finite(.f2) && abs(.f2) < 0.50) "PASS" else "FAIL",
  .f3,
  .f4a, .f4b, if (is.finite(.f4a) && is.finite(.f4b)) { if (.f4b < 0.2 * .f4a) "계단 소거" else "계단 잔존" } else "n/a",
  .f5, .f5s, if (is.finite(.f5s) && .f5s < 0.10) "PASS" else "FAIL",
  as.character(.first_fit), length(.cand_f), length(.got_f), .gapmax,
  if (length(.cand_f) && length(.got_f) == length(.cand_f) && .gapmax == 0L) "PASS" else "FAIL",
  as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
