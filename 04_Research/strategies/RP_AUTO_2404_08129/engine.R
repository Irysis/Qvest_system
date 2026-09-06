# =============================================================================
# engine.R — RP_AUTO_2404_08129  (2판 · 재구현 — 1판 = engine.rejected1.R, 적대 감사 misdeclared)
# "One Factor to Bind the Cross-Section of Returns"
#   Nicola Borri · Denis Chetverikov · Yukun Liu · Aleh Tsyvinski
#   arXiv:2404.08129 (2024-04-11) · NBER w32365 · Cowles DP 2386
#   https://arxiv.org/abs/2404.08129   (전문: arxiv.org/pdf/2404.08129 · NBER PDF — 두 추출 대조)
#
# ★fidelity = faithful. 정본 = FIDELITY.json — 이 주석은 요약일 뿐이고 아무것도 결정하지 않는다.
#
# ── 논문이 준 것 (원문 위치) ──────────────────────────────────────────────────
#   모형 식(1)   r_it = h(f_t λ_i) + ε_it ,  f_t > 0 · λ_i > 0 · h 비모수 링크
#   추정 식(4)   argmin Σ_i Σ_t ( r_it − Σ_{j=0}^{K} c_j (φ_t l_i)^j )²
#                제약 {c_j} ∈ R^{K+1} · {φ_t} ∈ (0,1]^T · {l_i} ∈ (0,1]^N
#                ("By rescaling the function h, it is then without loss of generality to assume
#                  that both f_t and λ_i are taking values in the (0,1] interval")
#   |c_j| ≤ L    "In practice, we find that these constraints are not binding if the constant L
#                 is chosen large enough" → 무제약 OLS = 논문 실무와 동일
#   차수         K = 4 (표 주석 반복: "degree of the polynomial used to approximate h(.) equal to 4")
#   §2 추정 3단계 ① 초기값 = T×N 수익률 행렬의 제1 좌/우 특이벡터를 (0,1] 로 shift·scale
#                ② 초기값에서 경사하강으로 국소최소 ③ {φ_t}·{l_i} 각 성분을 번갈아 재최적화,
#                   기준함수 변화가 무시할 만해질 때까지 (c 는 언제나 OLS — "optimization over
#                   {c_j} is easy as it can be implemented via OLS")
#   데이터       "Returns are monthly and in excess of the US risk-free rate (Ken French)"
#   §5.7 예측    "estimating the model on all 171 assets and the first 120 months of data" →
#                "use the model predicted returns to sort assets in five portfolios, and compute the
#                 equally-weighted average portfolio return in the following six months" →
#                "repeat the procedure expanding the estimation window by 6 months each time" (40회)
#                "the first four portfolios contain 34 assets each, and the last portfolio contains
#                 the remaining 35 assets" · "rebalancing at a semi-annual frequency" ·
#                "Starting in January 1998" · Table 8: long P5 / short P1 · 월 0.689% · 월 SR 0.15
#   예측값       §5.1 식(8) E[h(f_t λ_i)] — 기대값은 표본평균, h(f_t λ_i) 는 ĥ(f̂_t λ̂_i) 로 치환
#                → 예측수익_i = (1/T) Σ_t ĥ(φ̂_t l̂_i)
#
# ── 이 엔진이 하는 일 (논문 그대로 · 유니버스만 K200∪KQ150) ───────────────────
#   6월말·12월말(=1월·7월 형성) 마다: 적격 종목(멤버십 PIT + adv20(t−1) ≥ 2e8)의 월간 초과수익
#   확장창(패널 첫 달 ~ 시그널 월, 첫 형성은 ≥120개월)에 식(4)를 §2 3단계로 추정 →
#   예측수익으로 5분위(floor(N/5)×4 + 나머지) → P5 롱(EW, Σ=+1) · P1 숏(EW, Σ=−1) → 6개월 보유.
#   보유 6개월 동안 매 월말 같은 구성으로 EW 재설정 행을 낸다(= 월별 EW 평균수익 정의).
#   산출 = PORTFOLIO(Date, Ticker, Weight, Leg). 러너 사양 = FIDELITY.json::portfolio_spec.
#
# ── PIT (C1~C15) — 구조로 보장 (정적 탐지 통과를 근거로 삼지 않는다) ─────────────
#   행렬 .RM 은 월 오름차순이고 모든 추정 접근은 .RM[seq_len(ip), ] (ip = 시그널 월 행) 뿐이다.
#   시그널 d = 월 마지막 거래일, 집행 = 익월 첫 거래일(러너) → 창 종점 = t−1 이 구조로 성립.
#   C1 전표본 통계 0건(확장창 내부만) · C2 미래 인덱싱 0건 · C6 멤버십 = d 시점 플래그 ·
#   C10 유동성 = 20일 평균 거래대금의 shift(1) · C11 무위험 = m−1 월말 CD91(사전 확정 호가) ·
#   C13 부호 조작 0건(방향 = 추정된 ĥ 가 정함) · C15 팩터 DB 미접근.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.REQ <- c("Date", "Ticker", "Close", "Vol", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("[RP_AUTO_2404_08129] RAWDATA 필수 열 부재: %s",
               paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))

# =============================================================================
# 0. 상수 — 논문값 / 고정 축 / 구현 상수(논문 미명시 — FIDELITY.json changed 전수 신고)
# =============================================================================
.K       <- 4L                    # 논문: HFL 다항 차수 4
.NQ      <- 5L                    # 논문 §5.7: five portfolios
.T0      <- 120L                  # 논문 §5.7: first 120 months (첫 추정창 하한, 이후 확장)
.HOLD    <- 6L                    # 논문 §5.7: following six months · semi-annual
.FORM_M  <- c(6L, 12L)            # 시그널 월 = 6월·12월 말 (형성 = 1월·7월, "Starting in January")

.SIG_FROM <- as.Date("2005-01-01")   # 고정 축 시작
.LIQ      <- 2e8                     # adv20(t−1) 하한 KRW — 고정 축

.EPS       <- 1e-6      # 열린구간 (0,1] 의 닫힌 근사 [EPS, 1] (사영·근 탐색용)
.GD_MAXIT  <- 300L      # 2단계 경사하강 최대 반복
.GD_TOL    <- 1e-7      # 2단계 수렴: 반복당 손실 상대개선 하한
.GD_ARMIJO <- 1e-4      # 2단계 역추적 선탐색 Armijo 상수
.GD_BT     <- 40L       # 2단계 역추적 최대 반감 횟수
.CD_MAXIT  <- 50L       # 3단계 성분별 재최적화 최대 라운드
.CD_TOL    <- 1e-6      # 3단계 수렴: 라운드당 기준함수 상대변화 하한 ("negligible")
.TMIN_I    <- 12L       # 종목 최소 월간 관측수 (불균형 패널 커버리지 요건 — 논문에 없음)
.ROOT_TOL  <- 1e-7      # 다항 근의 실근 판정 허용 허수부

# =============================================================================
# 1. 보조 함수
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
# 벡터를 [eps, 1] ⊂ (0,1] 로 아핀 사상 (논문: "shifted and scaled ... in the (0,1] interval")
.to_unit <- function(x, eps) {
  r <- range(x)
  y <- if (r[2L] > r[1L]) (x - r[1L]) / (r[2L] - r[1L]) else rep(1, length(x))
  eps + (1 - eps) * y
}
.relimp <- function(a, b) if (is.finite(a) && a > 0) (a - b) / a else 0

# ---- 3단계용: 한 블록(모든 φ_t 또는 모든 l_i)의 성분별 정확 최소화 ----
#   성분 하나의 목적함수는 그 성분의 2K차 다항식이다:
#     f(x) = Σ_m M_m (R_m − Σ_j a_mj x^j)²,  a_mj = c_j w_m^j (w = 고정 블록)
#   계수를 닫힌 형태로 조립(행렬곱 2회) → 도함수(2K−1차)의 실근 + 구간 끝점 + 현재값 중 최소.
#   행 = 갱신 성분(n) · 열 = 고정 블록(m). Rm 은 결측 0 채움, Mm 은 0/1 마스크.
.block_argmin <- function(Rm, Mm, cf, w, cur, K, eps, root_tol) {
  P <- outer(w, 0:K, "^")                        # m × (K+1) : w^j
  A <- sweep(P, 2L, cf, "*")                     # a_mj = c_j w_m^j
  B <- matrix(0, nrow(A), 2L * K + 1L)           # B[m, j+k] = Σ_{j+k} a_mj a_mk
  for (j in 0:K) for (k in 0:K)
    B[, j + k + 1L] <- B[, j + k + 1L] + A[, j + 1L] * A[, k + 1L]
  cst  <- rowSums(Rm * Rm)                       # Σ_m M R²  (결측 = 0)
  lin  <- -2 * (Rm %*% A)                        # n × (K+1)
  coef <- Mm %*% B                               # n × (2K+1)
  coef[, seq_len(K + 1L)] <- coef[, seq_len(K + 1L)] + lin
  coef[, 1L] <- coef[, 1L] + cst
  out  <- cur
  mdeg <- seq_len(2L * K)
  for (r in seq_len(nrow(coef))) {
    cr <- coef[r, ]
    if (!all(is.finite(cr))) next
    cand <- c(cur[r], eps, 1)                    # 현재값을 첫 후보로 — 동률이면 움직이지 않는다
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

# ---- 식(4) 추정기 — 논문 §2 의 3단계 그대로 ----
#   R0: T×N 초과수익(결측 0) · M: T×N 관측 마스크(0/1)
.fit_hfl <- function(R0, M, K, eps, gd_maxit, gd_tol, armijo, gd_bt, cd_maxit, cd_tol, root_tol) {
  obs <- which(M > 0)
  y   <- R0[obs]
  Xd0 <- matrix(1, length(obs), K + 1L)
  ols_c <- function(phi, l) {                    # c | (φ, l) = 관측 셀 OLS (논문: "implemented via OLS")
    x  <- outer(phi, l)[obs]
    Xd <- Xd0
    for (j in seq_len(K)) Xd[, j + 1L] <- Xd[, j] * x
    cf <- unname(lm.fit(Xd, y)$coefficients)
    if (!all(is.finite(cf)))
      stop("[RP_AUTO_2404_08129] 식(4) OLS 계수 비유한(퇴화 설계행렬) — 추정 불가라 중단 (침묵 대체 없음)")
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
  if (!is.finite(L_init))
    stop("[RP_AUTO_2404_08129] 초기 손실 비유한 — 패널 값 확인")

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

# =============================================================================
# 2. 일간 패널 → 멤버십 · 유동성(t−1) · 월 인덱스   (RAWDATA 비파괴 — 러너가 재사용)
# =============================================================================
.t0 <- Sys.time()
.rd <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]
if (!inherits(.rd$Date, "Date")) .rd[, Date := as.Date(Date)]
.rd[, Ticker := as.character(Ticker)]
.rd <- .rd[is.finite(Close) & Close > 0]
.rd[, MEM := .as_flag(K200) | .as_flag(KQ150)]
.rd[, c("K200", "KQ150") := NULL]
setorder(.rd, Ticker, Date)

.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[RP_AUTO_2404_08129] (Ticker,Date) 중복 %d행 — 첫 행만 유지\n", .ndup))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}

.rd[, TV := Close * Vol]
.rd[, ADV20_L1 := shift(frollmean(TV, 20L, align = "right"), 1L), by = Ticker]
.rd[, TV := NULL]
.rd[, MI := year(Date) * 12L + month(Date)]

# 시장 월말(그 달 마지막 거래일). RAWDATA 의 마지막 달은 진행 중(부분월)으로 보고 제외한다.
.me <- .rd[, .(MEnd = max(Date)), by = MI]
setorder(.me, MI)
.MI_LAST <- max(.me$MI)
.me <- .me[MI < .MI_LAST]
.me[, MON := (MI - 1L) %% 12L + 1L]
if (nrow(.me) == 0L) stop("[RP_AUTO_2404_08129] 완결 월 0개 — RAWDATA 날짜 범위 확인")

# =============================================================================
# 3. 월간 수익률 패널 (논문 빈도) → 초과수익 (r_it − rf_t, rf = 전월말 CD91 / 12)
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
if (nrow(.mp) == 0L) stop("[RP_AUTO_2404_08129] 월간 수익률 0행")

# 무위험: ECOS KR_CD91 (일별 호가). 월 m 의 rf = m−1 월의 마지막 호가(연 %) / 100 / 12.
#   부재·결측이면 원수익으로 대체하지 않고 중단한다(논문 정의 = 초과수익).
.rf_path <- local({
  cd <- if (exists("CACHE_DIR", inherits = TRUE)) as.character(get("CACHE_DIR", inherits = TRUE))[1L] else ""
  if (!nzchar(cd)) {
    root <- Sys.getenv("QM_ROOT", "")
    if (!nzchar(root)) root <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
    if (!nzchar(root) && exists("PROJECT_ROOT", inherits = TRUE))
      root <- as.character(get("PROJECT_ROOT", inherits = TRUE))[1L]
    if (!nzchar(root)) root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
    cd <- file.path(root, ".cache")
  }
  file.path(cd, "ecos_bond_rates.parquet")
})
if (!file.exists(.rf_path))
  stop(sprintf("[RP_AUTO_2404_08129] 무위험(KR_CD91) 패널 부재: %s — 초과수익 정의를 지킬 수 없어 중단", .rf_path))
.ec <- as.data.table(arrow::read_parquet(.rf_path))
if (!all(c("Date", "Value", "Series") %in% names(.ec)))
  stop("[RP_AUTO_2404_08129] ecos_bond_rates 열 부재 (Date, Value, Series)")
.ec <- .ec[Series == "KR_CD91" & is.finite(Value)]
if (nrow(.ec) == 0L) stop("[RP_AUTO_2404_08129] KR_CD91 0행")
.ec[, Date := as.Date(Date, tz = "Asia/Seoul")]
setorder(.ec, Date)
.ec[, MIq := year(Date) * 12L + month(Date)]
.rfm <- .ec[, .(RF = Value[.N] / 100 / 12), by = MIq]
.rfm[, MI := MIq + 1L]
.rfm <- .rfm[, .(MI, RF)]
rm(.ec)

.n_ret_months <- uniqueN(.mp$MI)
.mp <- merge(.mp, .rfm, by = "MI")
if (nrow(.mp) == 0L) stop("[RP_AUTO_2404_08129] 수익률 패널과 CD91 이 겹치는 달 0개")
.mp[, R := R - RF]
.mp[, RF := NULL]

# ★PIT 구조: .RM 은 월 오름차순 행렬. 아래 루프의 모든 추정 소비는 .RM[seq_len(ip), ] 뿐이다.
.wide <- dcast(.mp, MI ~ Ticker, value.var = "R")
setorder(.wide, MI)
.MIs <- .wide$MI
.RM  <- as.matrix(.wide[, setdiff(names(.wide), "MI"), with = FALSE])
.TK  <- colnames(.RM)
rm(.wide, .mp); gc(verbose = FALSE)

.ym <- function(mi) sprintf("%d-%02d", (mi - 1L) %/% 12L, (mi - 1L) %% 12L + 1L)
cat(sprintf(paste0("[RP_AUTO_2404_08129] 월간 초과수익 패널 %d개월 (%s ~ %s) × %d종 | ",
                   "rf(CD91) 결합 전 %d개월 → 결합 후 %d개월 | 마지막 부분월 %s 제외\n"),
            length(.MIs), .ym(min(.MIs)), .ym(max(.MIs)), length(.TK),
            .n_ret_months, length(.MIs), .ym(.MI_LAST)))

# =============================================================================
# 4. 형성일 · 적격 종목 (C6 멤버십 PIT · C10 유동성 t−1)
# =============================================================================
.MI_FROM <- year(.SIG_FROM) * 12L + month(.SIG_FROM)
.FORM <- .me[MON %in% .FORM_M & (MI + .HOLD) >= .MI_FROM]      # 보유 6개월이 고정 축 구간과 겹치는 형성만
if (nrow(.FORM) == 0L) stop("[RP_AUTO_2404_08129] 형성 후보 0건")
.ELIG <- .rd[Date %in% .FORM$MEnd & MEM & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ, .(Date, Ticker)]
rm(.rd); gc(verbose = FALSE)
if (nrow(.ELIG) == 0L) stop("[RP_AUTO_2404_08129] 적격 종목 0건 — 멤버십/유동성 확인")

# =============================================================================
# 5. 반년 형성 루프 — 확장창 추정(§2 3단계) → 예측수익 5분위 → P5 롱 / P1 숏 EW → 6개월 보유
# =============================================================================
.rows  <- list()
.diag  <- list()
.nskip_win <- 0L; .nskip_n <- 0L

for (k in seq_len(nrow(.FORM))) {
  mi_f <- .FORM$MI[k]; d_f <- .FORM$MEnd[k]
  ip <- match(mi_f, .MIs)
  if (is.na(ip) || ip < .T0) { .nskip_win <- .nskip_win + 1L; next }   # 첫 형성 = 창 ≥ 120개월 (논문)

  tk <- .ELIG[Date == d_f, Ticker]
  ci <- match(tk, .TK); ok <- !is.na(ci); ci <- ci[ok]; tk <- tk[ok]
  Rm <- .RM[seq_len(ip), ci, drop = FALSE]        # ★확장창: 패널 첫 달 ~ 시그널 월(ip). ip 초과 행 접근 없음
  M  <- is.finite(Rm)
  ki <- colSums(M) >= .TMIN_I                     # 종목 커버리지 요건(구현 상수)
  Rm <- Rm[, ki, drop = FALSE]; M <- M[, ki, drop = FALSE]; tk <- tk[ki]
  kt <- rowSums(M) >= 1L                          # 관측이 하나도 없는 달은 φ_t 가 정의되지 않아 제외
  Rm <- Rm[kt, , drop = FALSE]; M <- M[kt, , drop = FALSE]
  n  <- ncol(Rm)
  if (n < .NQ) {
    .nskip_n <- .nskip_n + 1L
    cat(sprintf("[RP_AUTO_2404_08129] %s 적격 %d종 < %d — 5분위 불가, 이 형성 미발행\n", as.character(d_f), n, .NQ))
    next
  }
  R0 <- Rm; R0[!M] <- 0; Mn <- M * 1

  fit <- .fit_hfl(R0, Mn, .K, .EPS, .GD_MAXIT, .GD_TOL, .GD_ARMIJO, .GD_BT, .CD_MAXIT, .CD_TOL, .ROOT_TOL)

  pred <- colMeans(.polyval(fit$cf, outer(fit$phi, fit$l)))    # (1/T) Σ_t ĥ(φ̂_t l̂_i)
  if (!all(is.finite(pred)))
    stop(sprintf("[RP_AUTO_2404_08129] %s 예측수익 비유한 — 중단", as.character(d_f)))
  o    <- order(pred)                             # 오름차순: P1 = 최저 예측, P5 = 최고 예측
  nb   <- n %/% .NQ                               # 논문: 앞 4개 분위 = floor(N/5), 마지막 = 나머지
  i_lo <- o[seq_len(nb)]
  i_hi <- o[((.NQ - 1L) * nb + 1L):n]
  n_hi <- length(i_hi)

  w_long  <- rep(1 / n_hi, n_hi)
  w_short <- rep(-1 / nb, nb)
  tk_long <- tk[i_hi]; tk_short <- tk[i_lo]

  # 보유 6개월: 시그널 월말 d_f (집행 = 익월 초) 부터 5개월 뒤 월말까지, 같은 구성으로 EW 재설정
  for (h in 0:(.HOLD - 1L)) {
    ms <- .me[MI == mi_f + h]
    if (nrow(ms) == 0L) break                     # 데이터 끝
    .rows[[length(.rows) + 1L]] <- data.table(
      Date   = ms$MEnd[1L],
      Ticker = c(tk_long, tk_short),
      Weight = c(w_long, w_short),
      Leg    = c(rep("long", n_hi), rep("short", nb)),
      FormDate = d_f)
  }

  .diag[[length(.diag) + 1L]] <- data.table(
    FormDate = d_f, T_win = nrow(R0), N = n, n_obs = fit$n_obs,
    loss_init = fit$loss_init, loss_gd = fit$loss_gd, loss = fit$loss,
    it_gd = fit$it_gd, it_cd = fit$it_cd, n_long = n_hi, n_short = nb,
    rho_l_pred = suppressWarnings(cor(fit$l, pred, method = "spearman")))
  cat(sprintf(paste0("[RP_AUTO_2404_08129] %s | T=%d N=%d obs=%d | loss %.5g → gd %.5g (%d it) → cd %.5g (%d rounds) | ",
                     "c=(%s) | P1 %d / P5 %d | rho(l,pred)=%+.2f | %.1f분\n"),
              as.character(d_f), nrow(R0), n, fit$n_obs, fit$loss_init, fit$loss_gd, fit$it_gd,
              fit$loss, fit$it_cd, paste(sprintf("%.3g", fit$cf), collapse = ","),
              nb, n_hi, .diag[[length(.diag)]]$rho_l_pred,
              as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
}

# =============================================================================
# 6. PORTFOLIO 조립 · 검산 · 요약
# =============================================================================
if (length(.rows) == 0L)
  stop(sprintf("[RP_AUTO_2404_08129] 발행 행 0 — 창 미달 %d · 종목수 미달 %d (패널 %s~)",
               .nskip_win, .nskip_n, .ym(min(.MIs))))
PORTFOLIO <- rbindlist(.rows, use.names = TRUE)
PORTFOLIO <- PORTFOLIO[Date >= .SIG_FROM]
if (nrow(PORTFOLIO) == 0L) stop("[RP_AUTO_2404_08129] 고정 축 시작 이후 행 0")
setorder(PORTFOLIO, Date, Leg, Ticker)

.chk <- PORTFOLIO[, .(sw = sum(Weight)), by = .(Date, Leg)]
.bad <- .chk[(Leg == "long" & abs(sw - 1) > 1e-9) | (Leg == "short" & abs(sw + 1) > 1e-9)]
if (nrow(.bad) > 0L)
  stop(sprintf("[RP_AUTO_2404_08129] 레그 합 검산 실패 %d건 (예: %s %s %.6f)",
               nrow(.bad), as.character(.bad$Date[1L]), .bad$Leg[1L], .bad$sw[1L]))
.dupw <- sum(duplicated(PORTFOLIO, by = c("Date", "Ticker")))
if (.dupw > 0L) stop(sprintf("[RP_AUTO_2404_08129] (Date,Ticker) 중복 %d — 롱·숏 동시 편입 불가", .dupw))

.FORMS <- unique(PORTFOLIO$FormDate)
.DIAG  <- rbindlist(.diag, use.names = TRUE)
.pm <- PORTFOLIO[, .(nL = sum(Leg == "long"), nS = sum(Leg == "short")), by = Date]
cat(sprintf(paste0("[RP_AUTO_2404_08129] faithful: HFL 식(4) K=%d · §2 3단계(SVD 초기값 → 사영 GD → 성분별 재최적화) · ",
                   "확장창(첫 창 ≥%d개월, 반년 재추정) · 예측수익 5분위 P5 롱/P1 숏 EW · 6개월 보유(월별 EW 재설정)\n",
                   "  형성 %d회 (%s ~ %s) · 창 미달 스킵 %d · 발행 월 %d개 (%s ~ %s) · 행 %d\n",
                   "  롱 %d~%d종 / 숏 %d~%d종 (형성당) · 최대 보유 %d종 · 추정 T %d~%d · N %d~%d · %.1f분\n",
                   "  ★러너 사양 = FIDELITY.json::portfolio_spec (engine_direct) · commission_paper = null (논문 비용 무명시 → gross 병기)\n"),
            .K, .T0, length(.FORMS), as.character(min(.FORMS)), as.character(max(.FORMS)), .nskip_win,
            uniqueN(PORTFOLIO$Date), as.character(min(PORTFOLIO$Date)), as.character(max(PORTFOLIO$Date)),
            nrow(PORTFOLIO), min(.pm$nL), max(.pm$nL), min(.pm$nS), max(.pm$nS), max(.pm$nL + .pm$nS),
            min(.DIAG$T_win), max(.DIAG$T_win), min(.DIAG$N), max(.DIAG$N),
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
PORTFOLIO[, FormDate := NULL]
PORTFOLIO <- PORTFOLIO[, .(Date, Ticker, Weight, Leg)]
