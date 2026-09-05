# =============================================================================
# engine.R — RP_AUTO_2404_08129
# "One Factor to Bind the Cross-Section of Returns"
#   Nicola Borri · Denis Chetverikov · Yukun Liu · Aleh Tsyvinski
#   arXiv:2404.08129 (2024-04-11) · NBER w32365 · Cowles DP 2386
#   https://arxiv.org/abs/2404.08129
#
# ★fidelity = ADAPTED (착안 이식). 정본 = FIDELITY.json — 이 주석은 요약일 뿐이다.
#
# ── 논문이 준 것 ───────────────────────────────────────────────────────────────
#   모형(식 1)  r_it = h(f_t λ_i) + ε_it ,  f_t > 0 · λ_i > 0 · h(·) 비모수 링크
#   추정(식 4)  ({ĉ_j},{φ̂_t},{l̂_i}) = argmin Σ_i Σ_t ( r_it − Σ_{j=0}^{K} c_j (φ_t l_i)^j )²
#               제약: {c_j} ∈ R^{K+1} (|c_j| ≤ L) · φ_t ∈ (0,1] · l_i ∈ (0,1]
#   차수        HFL 사양 K = 4 ("degree of the polynomial used to approximate h(.) equal to 4";
#               "polynomials of degree as low as four suffices for the majority of results")
#   데이터      171 시험자산(미국 주식 포트폴리오 · 미국/국제 국채 · 상품 · 통화 포트폴리오)
#               × 월간 360 관측 — 전표본 1회 공동 추정
#   평가        Fama-MacBeth 횡단면 회귀 adj.R² · MAPE (FF3/FF5/FF5+MOM 대비 α) — 거래전략 없음
#
# ── 산출 형태가 다르다 → 충실구현 불가 → 기전 이식 ────────────────────────────────
#   논문의 기전: 기대수익 횡단면이 **단일 적재 λ_i 의 함수 E[h(f λ_i)]** 로 묶인다.
#   이식: 매 월말 d 에 K200∪KQ150 적격 종목의 **월간** 수익률 패널(가용 첫 달 ~ d, 확장창)에
#   식(4)를 그대로 추정하고  Score_i = (1/T) Σ_t ĥ(φ̂_t l̂_i)  = 모형 함의 기대수익 을 낸다.
#   Score 는 l̂_i 만의 함수 g(l) 이므로 정렬 방향은 데이터가 정한 ĥ 의 형상에서 나온다(부호 조작 0).
#   포트폴리오 = 고정 축(top 25 · EW · 월간) — 러너가 FIDELITY.json::portfolio_spec 으로 구성.
#
# ── 논문에 없는데 넣은 것 (FIDELITY.json::changed 와 같은 목록) ───────────────────
#   (1) 유니버스 171 다자산 포트폴리오 → K200∪KQ150 개별 종목(PIT 시변) + adv20(t-1) ≥ 2e8
#   (2) 산출 = 가격결정 검정 → FACTORS(Score = 모형 함의 기대수익) → top-25 EW 월간
#   (3) 전표본 1회 추정(T=360) → 월말마다 확장창 재추정(가용 전기간, 창 종점 = 시그널 월)
#   (4) 불균형 패널: 관측 셀만 합산 · 종목 ≥ 24개월 · 월 ≥ 20종 · 시그널월 횡단면 ≥ 50종
#   (5) 추정 패널 = 시그널일 적격 종목(그 종목들의 과거 전 이력)
#   (6) 알고리즘: 교대 최소화(c = OLS · φ_t, l_i = (0,1] 100점 격자 전역 최소 → optimize 연속 정련)
#       초기 l = EW 패널평균 대비 기울기의 순위/N · 초기 φ = 패널평균의 순위/T · |c_j| ≤ L 미부과
#   (7) 초과수익 → 원수익(무위험 패널 부재 — 날짜별 공통항)
#   (8) winsorize/clip 없음(논문 최소제곱 그대로)
#
# ── PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) ─────────
#   행렬 .RM 은 월 오름차순이고 모든 접근은 .RM[seq_len(ip), ] (ip = 시그널 월 행)뿐이다 —
#   ip 초과 행을 읽는 코드가 존재하지 않는다. 창의 종점 = 시그널 월(월말 d 종가까지).
#   C1  : 전표본 통계 0건 — 모든 추정은 확장창 내부(rolling/expanding 허용 규정)
#   C2  : 미래 인덱싱 없음(shift(+1)만 사용)
#   C6  : 유니버스 = d 시점 K200/KQ150 멤버십 — 미래 명부 없음
#   C10 : 유동성 = 20일 평균 거래대금의 by-Ticker shift(1) = t-1
#   C13 : 부호 조작 0 — 방향은 추정된 ĥ 의 형상이 정한다
#   C15 : Factor DB 미접근 — RAWDATA 가격/거래대금만 사용
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

set.seed(24040813L)   # 난수 미사용(결정론적 엔진) — 재현성 선언 고정

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.REQ <- c("Date", "Ticker", "Close", "Vol", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("[RP_AUTO_2404_08129] RAWDATA 필수 열 부재: %s",
               paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))

# =============================================================================
# 상수 — 논문에서 온 것 / 고정 축 / 계산 경계 (성과를 보고 고르지 않았다)
# =============================================================================
.K        <- 4L                      # 논문 HFL 사양: h 근사 다항식 차수 4
.SIG_FROM <- as.Date("2005-01-01")   # 고정 축 시작
.LIQ      <- 2e8                     # adv20(t-1) 하한 (KRW) — 고정 축
.G        <- 100L                    # φ_t, l_i 격자 점수 on (0,1] (해상도 0.01) → optimize 로 연속 정련
.MAXIT    <- 40L                     # 교대 최소화 최대 스윕
.TOL      <- 1e-6                    # 상대 손실 개선 하한(수렴)
.TMIN     <- 24L                     # 종목 최소 관측 월수 (l_i 식별 하한 — 커버리지 요건)
.NMIN_T   <- 20L                     # 월 최소 관측 종목수 (φ_t 식별 하한 — 커버리지 요건)
.NMIN     <- 50L                     # 시그널월 최소 횡단면 (top-25 선택이 의미를 갖는 하한)
.GRID     <- seq_len(.G) / .G        # (0,1] 격자: 0.01, 0.02, ..., 1

# ---- 다항식 평가 (Horner). cf = c(c_0, c_1, ..., c_K) · X 는 행렬 또는 벡터 ----
.polyval <- function(cf, X) {
  out <- X * 0 + cf[length(cf)]
  if (length(cf) > 1L) for (j in (length(cf) - 1L):1L) out <- out * X + cf[j]
  out
}

# ---- 멤버십 플래그 정규화 (logical / 0-1 / 문자 모두 수용) ----
.as_flag <- function(x) {
  if (is.logical(x)) return(x %in% TRUE)
  if (is.numeric(x)) return(is.finite(x) & x != 0)
  toupper(trimws(as.character(x))) %in% c("TRUE", "T", "1", "Y", "YES")
}

# =============================================================================
# 식(4) 추정기 — 교대 최소화
#   R0: T×N 수익률(결측 0) · M: T×N 관측 마스크(0/1) · K: 차수 · grid: (0,1] 격자
#   각 블록 갱신은 나머지를 고정한 정확 최소화(c: OLS · φ_t, l_i: 격자 전역 최소)라
#   손실이 단조 비증가한다. 격자 수렴 뒤 ±1칸 안에서 optimize 로 연속 정련(동점 제거).
# =============================================================================
.fit_hfl <- function(R0, M, K, grid, maxit, tol) {
  Tn  <- nrow(R0); Nn <- ncol(R0)
  obs <- which(M > 0)
  y   <- R0[obs]

  # 초기값 — EW 패널평균 m_t 에 대한 종목별 기울기(관측 셀) → 순위/N ∈ (0,1] · φ = m_t 순위/T
  m <- rowSums(R0) / pmax(rowSums(M), 1)
  b <- numeric(Nn)
  for (i in seq_len(Nn)) {
    o <- M[, i] > 0
    if (sum(o) >= 3L) {
      mv <- m[o] - mean(m[o]); rv <- R0[o, i] - mean(R0[o, i])
      vm <- sum(mv * mv)
      b[i] <- if (vm > 0) sum(mv * rv) / vm else 0
    }
  }
  l   <- rank(b, ties.method = "average") / Nn
  phi <- rank(m, ties.method = "average") / Tn

  .ols_c <- function(phi, l) {              # c 갱신 — x = φ_t l_i 의 거듭제곱에 OLS (관측 셀만)
    x  <- outer(phi, l)[obs]
    Xd <- matrix(1, nrow = length(x), ncol = K + 1L)
    for (j in seq_len(K)) Xd[, j + 1L] <- Xd[, j] * x
    cf <- lm.fit(Xd, y)$coefficients
    cf[!is.finite(cf)] <- 0
    unname(cf)
  }
  .loss <- function(cf, phi, l) sum(M * (R0 - .polyval(cf, outer(phi, l)))^2)

  cf <- .ols_c(phi, l)
  loss_prev <- .loss(cf, phi, l)
  if (!is.finite(loss_prev)) return(list(ok = FALSE))
  it <- 0L
  repeat {
    it <- it + 1L
    # φ_t 갱신 — 격자 g 별 손실(상수항 제외) = −2 Σ_i R_ti h(g l_i) + Σ_i M_ti h(g l_i)²
    H   <- .polyval(cf, outer(grid, l))                        # G×N
    Lp  <- -2 * (R0 %*% t(H)) + M %*% t(H * H)                 # T×G
    phi <- grid[max.col(-Lp, ties.method = "first")]
    # l_i 갱신 — 대칭
    Q   <- .polyval(cf, outer(grid, phi))                      # G×T
    Ll  <- -2 * crossprod(R0, t(Q)) + crossprod(M, t(Q * Q))   # N×G
    l   <- grid[max.col(-Ll, ties.method = "first")]
    # c 갱신 · 수렴
    cf   <- .ols_c(phi, l)
    loss <- .loss(cf, phi, l)
    if (!is.finite(loss) || anyNA(phi) || anyNA(l)) return(list(ok = FALSE))
    if (it >= maxit || (loss_prev - loss) <= tol * loss_prev) break
    loss_prev <- loss
  }

  # 연속 정련 — 격자 최적점 ±1칸 안에서 optimize (제약 (0,1] 유지 · 개선될 때만 채택)
  step <- grid[2L] - grid[1L]
  for (i in seq_len(Nn)) {
    o <- M[, i] > 0
    if (!any(o)) next
    ri <- R0[o, i]; po <- phi[o]
    f_i <- function(v) { e <- ri - .polyval(cf, po * v); sum(e * e) }
    r <- optimize(f_i, interval = c(max(step / 10, l[i] - step), min(1, l[i] + step)))
    if (is.finite(r$objective) && r$objective <= f_i(l[i])) l[i] <- r$minimum
  }
  for (tt in seq_len(Tn)) {
    o <- M[tt, ] > 0
    if (!any(o)) next
    rt <- R0[tt, o]; lo <- l[o]
    f_t <- function(v) { e <- rt - .polyval(cf, lo * v); sum(e * e) }
    r <- optimize(f_t, interval = c(max(step / 10, phi[tt] - step), min(1, phi[tt] + step)))
    if (is.finite(r$objective) && r$objective <= f_t(phi[tt])) phi[tt] <- r$minimum
  }
  cf   <- .ols_c(phi, l)
  loss <- .loss(cf, phi, l)
  list(ok = is.finite(loss) && !anyNA(cf), cf = cf, phi = phi, l = l,
       loss = loss, it = it, n_obs = length(obs))
}

# =============================================================================
# 1. 일간 패널 → 멤버십 · 유동성(t-1) · 월 인덱스 (RAWDATA 비파괴 — 러너가 재사용)
# =============================================================================
.rd <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]
if (!inherits(.rd$Date, "Date")) .rd[, Date := as.Date(Date)]
.rd[, Ticker := as.character(Ticker)]
.rd <- .rd[is.finite(Close) & Close > 0]
.rd[, MEM := .as_flag(K200) | .as_flag(KQ150)]
.rd[, c("K200", "KQ150") := NULL]
setorder(.rd, Ticker, Date)

# (Ticker,Date) 중복 방어 — 중복이 남으면 뒤의 dcast 가 조용히 건수 행렬을 만든다(침묵 실패)
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[RP_AUTO_2404_08129] (Ticker,Date) 중복 %d행 — 첫 행만 남긴다\n", .ndup))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}

.rd[, TV := Close * Vol]
.rd[, ADV20_L1 := shift(frollmean(TV, 20L, align = "right"), 1L), by = Ticker]   # C10 t-1
.rd[, TV := NULL]
.rd[, MI := year(Date) * 12L + month(Date)]

# 시그널일 = 시장 전체 월말(그 달의 마지막 거래일) — 고정 축 시작 이후
.mend <- .rd[, .(SigDate = max(Date)), by = MI]
setorder(.mend, MI)
.SIG <- .mend[SigDate >= .SIG_FROM]
if (nrow(.SIG) == 0L)
  stop("[RP_AUTO_2404_08129] 시그널일 0건 — RAWDATA 날짜 범위 확인")

# 적격: 시그널일에 거래 + K200/KQ150 멤버십(PIT 시변) + adv20(t-1) 하한   (C6 · C10)
.ELIG <- .rd[Date %in% .SIG$SigDate & MEM & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ,
             .(SigDate = Date, MI, Ticker)]
if (nrow(.ELIG) == 0L)
  stop("[RP_AUTO_2404_08129] 적격 종목 0건 — 멤버십/유동성 필터 확인")
.KEEP_TK <- unique(.ELIG$Ticker)

# =============================================================================
# 2. 월간 수익률 패널 (논문 빈도) — 종목별 그 달 마지막 종가 → 연속 월끼리만 수익률
# =============================================================================
.rs <- .rd[Ticker %chin% .KEEP_TK, .(Ticker, MI, Date, Close)]
rm(.rd); gc(verbose = FALSE)
setorder(.rs, Ticker, Date)
.n   <- nrow(.rs)
.brk <- c(.rs$Ticker[-1L] != .rs$Ticker[-.n] | .rs$MI[-1L] != .rs$MI[-.n], TRUE)  # 그룹 마지막 행
.mp  <- .rs[.brk]
rm(.rs)
setorder(.mp, Ticker, MI)
.mp[, R   := Close / shift(Close) - 1, by = Ticker]
.mp[, GAP := MI - shift(MI), by = Ticker]
.mp[is.na(GAP) | GAP != 1L, R := NA_real_]        # 결측 월이 끼면 그 수익률은 쓰지 않는다(채우지 않음)
.mp <- .mp[is.finite(R), .(MI, Ticker, R)]
if (nrow(.mp) == 0L)
  stop("[RP_AUTO_2404_08129] 월간 수익률 0행 — 종가/월 인덱스 확인")

# ★PIT 구조: .RM 은 월 오름차순 행렬. 아래 루프의 모든 소비는 .RM[seq_len(ip), ] 뿐이다.
.wide <- dcast(.mp, MI ~ Ticker, value.var = "R")
setorder(.wide, MI)
.MIs <- .wide$MI
.RM  <- as.matrix(.wide[, setdiff(names(.wide), "MI"), with = FALSE])
.TK  <- colnames(.RM)
rm(.wide, .mp); gc(verbose = FALSE)

.SIG[, IP := match(MI, .MIs)]
cat(sprintf(paste0("[RP_AUTO_2404_08129] 월간 패널 %d개월 (%d-%02d ~ %d-%02d) × %d종 | ",
                   "시그널월 %d개 (%s ~ %s) | K=%d · 격자 %d · 확장창\n"),
            length(.MIs), (min(.MIs) - 1L) %/% 12L, (min(.MIs) - 1L) %% 12L + 1L,
            (max(.MIs) - 1L) %/% 12L, (max(.MIs) - 1L) %% 12L + 1L, length(.TK),
            nrow(.SIG), as.character(min(.SIG$SigDate)), as.character(max(.SIG$SigDate)),
            .K, .G))

# =============================================================================
# 3. 월별 루프 — 확장창 추정 → Score = 모형 함의 기대수익 (1/T) Σ_t ĥ(φ̂_t l̂_i)
# =============================================================================
.out   <- vector("list", nrow(.SIG))
.nskip <- 0L
.t0    <- Sys.time()

for (k in seq_len(nrow(.SIG))) {
  sd_k <- .SIG$SigDate[k]
  ip   <- .SIG$IP[k]
  if (is.na(ip)) { .nskip <- .nskip + 1L; next }

  tkc <- .ELIG[SigDate == sd_k, Ticker]
  ci  <- match(tkc, .TK)
  ok  <- !is.na(ci)
  ci  <- ci[ok]; tkc <- tkc[ok]
  if (length(ci) < .NMIN) { .nskip <- .nskip + 1L; next }

  Rm <- .RM[seq_len(ip), ci, drop = FALSE]     # ★확장창: 첫 달 ~ 시그널 월(ip). ip 초과 행 접근 없음
  M  <- is.finite(Rm)
  kt <- rowSums(M) >= .NMIN_T                  # φ_t 식별 하한 미달 월 제외
  if (sum(kt) < .TMIN) { .nskip <- .nskip + 1L; next }
  Rm <- Rm[kt, , drop = FALSE]; M <- M[kt, , drop = FALSE]
  ki <- colSums(M) >= .TMIN                    # l_i 식별 하한 미달 종목 제외
  if (sum(ki) < .NMIN) { .nskip <- .nskip + 1L; next }
  Rm <- Rm[, ki, drop = FALSE]; M <- M[, ki, drop = FALSE]; tkc <- tkc[ki]
  R0 <- Rm; R0[!M] <- 0
  Mn <- M * 1

  fit <- .fit_hfl(R0, Mn, .K, .GRID, .MAXIT, .TOL)
  if (!isTRUE(fit$ok)) { .nskip <- .nskip + 1L; next }

  sc  <- colMeans(.polyval(fit$cf, outer(fit$phi, fit$l)))   # g(l̂_i) — 전 월의 φ̂ 분포로 적분
  fin <- is.finite(sc)
  if (sum(fin) < .NMIN) { .nskip <- .nskip + 1L; next }
  .out[[k]] <- data.table(Date = sd_k, Ticker = tkc[fin], Score = sc[fin])

  if (k == 1L || k %% 24L == 0L) {
    rho <- suppressWarnings(cor(fit$l[fin], sc[fin], method = "spearman"))
    cat(sprintf(paste0("[RP_AUTO_2404_08129] %s | T=%d N=%d obs=%d | it=%d RMSE=%.4f | ",
                       "c=(%s) | rho(l,Score)=%+.2f | skip=%d | %.1f분\n"),
                as.character(sd_k), nrow(R0), ncol(R0), fit$n_obs, fit$it,
                sqrt(fit$loss / fit$n_obs), paste(sprintf("%.3g", fit$cf), collapse = ","),
                rho, .nskip, as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
    gc(verbose = FALSE)
  }
}

FACTORS <- rbindlist(Filter(Negate(is.null), .out), use.names = TRUE)
if (nrow(FACTORS) == 0L)
  stop("[RP_AUTO_2404_08129] FACTORS 0행 — 유니버스/패널/추정 확인")
setorder(FACTORS, Date, -Score)

.ncs <- FACTORS[, .N, by = Date]$N
cat(sprintf(paste0("[RP_AUTO_2404_08129] adapted: r_it = h(f_t l_i) + e (K=%d 다항식 시브 · 식(4) 교대 최소화 · 확장창 월간) | ",
                   "Score = 모형 함의 기대수익 (1/T) sum_t h(phi_t l_i)\n",
                   "  월 %d개 (%s ~ %s) · skip %d · 횡단면 중앙 %.0f (min %d / max %d) · FACTORS %d행 · %.1f분\n",
                   "  ★러너 사양 = FIDELITY.json::portfolio_spec (top_n_long · ew · monthly · 25) · commission_paper = null\n"),
            .K, uniqueN(FACTORS$Date),
            as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date)),
            .nskip, median(.ncs), min(.ncs), max(.ncs), nrow(FACTORS),
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
