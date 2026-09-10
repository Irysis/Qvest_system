# =============================================================================
# RP_AUTO_COMBO_combo_1403_8125_2301_091 — 3편 결합 전략 (설계 기저)
# =============================================================================
# 재료
#   [A] Choi, Choi, Kang (2014) "Maximum drawdown, recovery, and momentum"
#       arXiv:1403.8125   https://arxiv.org/abs/1403.8125
#   [B] Borri, Chetverikov, Liu, Tsyvinski (2024) "One Factor to Bind the
#       Cross-Section of Returns"  arXiv:2404.08129  https://arxiv.org/abs/2404.08129
#   [C] Pinchuk (2023) "Labor Income Risk and the Cross-Section of Expected
#       Returns"  arXiv:2301.09173  https://arxiv.org/abs/2301.09173
#
# -- 결합의 논리 (세 재료가 **서로 다른 소비 지점**에 들어간다) ----------------
#   [A] = 점수.   6개월 일별 로그가격 경로의 CM = C - MDD (Table 1 CM 규칙 (1,2,1)).
#   [B] = 통제.   B 의 헤드라인 주장은 "단일 비선형 팩터를 통제하면 알려진 팩터가
#                 무의미해진다" 이다(거래 설계 5.7 은 부수 결과다). 그 주장을
#                 **A 의 신호에 그대로 적용**한다: 형성월 횡단면에서 CM 을 B 의
#                 추정 적재 lam 의 시브 기저 {1, lam, lam^2, lam^3, lam^4}(차수 K=4 =
#                 B 논문값)에 회귀하고 **잔차**를 점수로 쓴다. B 가 옳으면 CM 은
#                 잔차에서 죽고, A 의 경로형태 정보가 단일 팩터와 직교하면 살아남는다.
#   [C] = 비중.   C 의 가격결정 대상은 산업 이탈 자체가 아니라 **CID 변화 민감도**다
#                 (원문 대조 2026-09-10: "sensitivity to changes in cross-industry
#                 dispersion ... represents the compensated risk factor, not
#                 idiosyncratic industry performance"). 논문 사전 선언 방향
#                 (high beta_CID = low expected return, 스프레드 연 5.9%)을 **선택이
#                 아니라 비중**에 싣는다 - 선택에 실으면 B 의 통제 축과 같은 노출 축을
#                 두 번 세는 것이 되고(저장소 교훈: 라벨의 다양성 != 행동의 다양성),
#                 비중에 실으면 같은 종목 집합 안에서 C 의 기여만 분리 측정된다.
#
# -- 반증 조건 ----------------------------------------------------------------
#   (1) vs [A] 단독: lam 통제가 A 의 선택력을 죽이면(잔차 점수의 성과가 CM 단독보다
#       낮으면) B 의 "단일 팩터가 횡단면을 묶는다" 가 KR 에서도 성립하는 것이고
#       본 설계는 기각된다. 살아남으면 경로형태 정보가 단일 팩터에 직교한다는 뜻.
#   (2) vs [C] 단독(KR 실측 F): C 를 비중에만 쓰므로, beta_CID 랭크 비중을 EW 로
#       바꾼 절제 칸이 성과를 유지하면 C 의 기여는 0 이다.
#   (3) 세 재료 전부 KR 실측에서 단독 A 만 양(+)이었다(1403.8125 강화 최고 t 2.567 ·
#       2404.08129 충실구현 F PORT_t -2.326 · 2301.09173 충실구현 F). 그래서 본 설계는
#       B·C 를 알파로 쓰지 않는다 - 통제와 비중이라는 **다른 소비 지점**에만 쓴다.
#
# -- 고정 축 (설계 변수 아님 · 요청 axis = n_max_25) ---------------------------
#   long-only(w >= 0) · 최대 25종 · K200 U KQ150 PIT 시변 멤버십 ·
#   adv20(t-1) >= 2e8 KRW · sum(w) = 1 · 월간 리밸 · 비중 상한 없음.
#   비용 15bps 는 러너가 부과한다.
#
# -- PIT (C1~C15) -------------------------------------------------------------
#   형성일 f = 완결 월의 시장 마지막 거래일. 모든 입력의 창 종점 <= f, 보유는 f 다음 달부터.
#   C1  전 표본 통계 0건 - HFL 은 확장창(<= f), CID AR 은 확장창(<= f), beta_CID 는 f 로
#       끝나는 24개월, CM 은 f 로 끝나는 6개월, 횡단면 회귀·winsorize·랭크는 그 달 단면 내부.
#   C5  신호 컷오프 = f (보유월 시작 전) - 오버레이 없음(총노출 스칼라 조정 0건).
#   C6  멤버십은 f 시점 기록 그대로.  C10 adv20 은 shift(1) 로 t-1.
#   C13 부호반전 0건 - A 는 논문 방향(승자 롱), C 는 논문 사전선언 방향(-beta),
#       B 는 방향을 쓰지 않는다(통제 변수라 부호가 없다).
#   C15 Factor DB 미사용(원자료에서 직접 산출).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.REQ <- c("Date", "Ticker", "Close", "Vol", "K200", "KQ150", "Ret", "Size", "Sector_Lv2")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("[COMBO] RAWDATA 열 부재: %s",
               paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))

.t0 <- Sys.time()

# ---- 상수: 전부 논문값 또는 고정 축에서 유도 (임의 상수 0) -------------------
.W        <- c(1, 2, 1)   # [A] Table 1 CM 가중 (R_I,R_II,R_III) = C - MDD
.FORM_M   <- 6L           # [A] 3.2 형성 6개월
.HOLD     <- 6L           # [A] 3.2 보유 6개월 = J-T 오버래핑 K
.NDEC     <- 10L          # [A] 3.2 "numbers of groups are 10" - 횡단면 최소 요건으로만 사용
.K        <- 4L           # [B] HFL 다항 차수 4 (통제 회귀의 시브 차수도 동일)
.T0       <- 120L         # [B] 5.7 첫 추정창 120개월 (이후 확장)
.HFL_MON  <- c(6L, 12L)   # [B] 5.7 반년 재추정 (형성 1월·7월 위상)
.CID_MINF <- 10L          # [C] Eq.1 "at least 10 firms"
.CID_WIN  <- 24L          # [C] Eq.3 "two years of monthly returns"
.CID_MINO <- 18L          # [C] 구현 보충 - 부모 엔진(RP_2301_09173_CID) 규약 승계
.CID_BURN <- 60L          # [C] 구현 보충 - 확장창 AR 워밍업, 부모 엔진 규약 승계
.CID_CAP  <- 1.0          # [C] 구현 보충 - KRX +-30% 초과 일간수익 = 단위 아티팩트, 부모 승계
.LIQ      <- 2e8          # 고정 축
.LIQ_WIN  <- 20L
.NMAX     <- 25L          # 고정 축
.SEL_N    <- .NMAX %/% .HOLD   # = 4. 슬리브당 종목수 = 고정 축 25 / [A] 의 K=6 (유도값)
# [B] 수치 최적화 상수 - 부모 엔진(RP_AUTO_2404_08129) 값 그대로 승계
.EPS <- 1e-6; .GD_MAXIT <- 300L; .GD_TOL <- 1e-7; .GD_ARMIJO <- 1e-4
.GD_BT <- 40L; .CD_MAXIT <- 50L; .CD_TOL <- 1e-6; .ROOT_TOL <- 1e-7
.TMIN_I <- 12L            # [B] 종목 최소 월간 관측(부모 승계 · 논문 무명시)

.as_flag <- function(x) {
  if (is.logical(x)) return(x %in% TRUE)
  if (is.numeric(x)) return(is.finite(x) & x != 0)
  toupper(trimws(as.character(x))) %in% c("TRUE", "T", "1", "Y", "YES")
}

# =============================================================================
# [A] 경로 통계 - 부모 엔진 RP_AUTO_1403_8125 의 .mdd_stats 그대로
# =============================================================================
.mdd_stats <- function(cl) {
  n <- length(cl)
  if (n < 2L) return(list(C = NA_real_, MDD = NA_real_, RI = NA_real_,
                          RII = NA_real_, RIII = NA_real_, nobs = n))
  path <- log(cl) - log(cl[1L])
  dd   <- path - cummax(path)
  ts   <- which.min(dd)
  tp   <- which.max(path[seq_len(ts)])
  list(C = path[n], MDD = -dd[ts], RI = path[tp],
       RII = path[ts] - path[tp], RIII = path[n] - path[ts], nobs = n)
}

# =============================================================================
# [B] HFL 추정기 - 부모 엔진 RP_AUTO_2404_08129 의 2절 3단계 구현 그대로
# =============================================================================
.polyval <- function(cf, X) {
  n <- length(cf); out <- X * 0 + cf[n]
  if (n > 1L) for (j in (n - 1L):1L) out <- out * X + cf[j]
  out
}
.polyder <- function(cf, X) {
  n <- length(cf); if (n < 2L) return(X * 0)
  .polyval(cf[-1L] * seq_len(n - 1L), X)
}
.to_unit <- function(x, eps) {
  r <- range(x)
  y <- if (r[2L] > r[1L]) (x - r[1L]) / (r[2L] - r[1L]) else rep(1, length(x))
  eps + (1 - eps) * y
}
.relimp <- function(a, b) if (is.finite(a) && a > 0) (a - b) / a else 0

.block_argmin <- function(Rm, Mm, cf, w, cur, K, eps, root_tol) {
  P <- outer(w, 0:K, "^")
  A <- sweep(P, 2L, cf, "*")
  B <- matrix(0, nrow(A), 2L * K + 1L)
  for (j in 0:K) for (k in 0:K)
    B[, j + k + 1L] <- B[, j + k + 1L] + A[, j + 1L] * A[, k + 1L]
  cst  <- rowSums(Rm * Rm)
  lin  <- -2 * (Rm %*% A)
  coef <- Mm %*% B
  coef[, seq_len(K + 1L)] <- coef[, seq_len(K + 1L)] + lin
  coef[, 1L] <- coef[, 1L] + cst
  out  <- cur; mdeg <- seq_len(2L * K)
  for (r in seq_len(nrow(coef))) {
    cr <- coef[r, ]
    if (!all(is.finite(cr))) next
    cand <- c(cur[r], eps, 1)
    d <- cr[-1L] * mdeg
    nz <- which(d != 0)
    if (length(nz) && max(nz) >= 2L) {
      d <- d[seq_len(max(nz))]; d <- d / max(abs(d))
      rt <- polyroot(d); re <- Re(rt); im <- Im(rt)
      ok <- abs(im) <= root_tol * pmax(1, abs(re)) & re >= eps & re <= 1
      if (any(ok)) cand <- c(cand, re[ok])
    }
    out[r] <- cand[which.min(.polyval(cr, cand))]
  }
  out
}

.fit_hfl <- function(R0, M, K, eps, gd_maxit, gd_tol, armijo, gd_bt,
                     cd_maxit, cd_tol, root_tol) {
  obs <- which(M > 0); y <- R0[obs]
  Xd0 <- matrix(1, length(obs), K + 1L)
  ols_c <- function(phi, l) {
    x <- outer(phi, l)[obs]; Xd <- Xd0
    for (j in seq_len(K)) Xd[, j + 1L] <- Xd[, j] * x
    cf <- unname(lm.fit(Xd, y)$coefficients)
    if (!all(is.finite(cf)))
      stop("[COMBO/B] Eq.4 OLS 계수 비유한(퇴화 설계행렬) - 중단 (침묵 대체 없음)")
    cf
  }
  loss <- function(cf, phi, l) { E <- M * (R0 - .polyval(cf, outer(phi, l))); sum(E * E) }

  sv <- svd(R0, nu = 1L, nv = 1L)
  u <- sv$u[, 1L]; v <- sv$v[, 1L]
  if (sum(v) < 0) { u <- -u; v <- -v }
  phi <- .to_unit(u, eps); l <- .to_unit(v, eps)
  cf <- ols_c(phi, l); L_init <- loss(cf, phi, l)
  if (!is.finite(L_init)) stop("[COMBO/B] 초기 손실 비유한 - 패널 값 확인")

  L0 <- L_init; alpha <- 1; it_gd <- 0L
  repeat {
    it_gd <- it_gd + 1L
    X <- outer(phi, l)
    G <- (M * (R0 - .polyval(cf, X))) * .polyder(cf, X)
    g_phi <- -2 * as.vector(G %*% l); g_l <- -2 * as.vector(crossprod(G, phi))
    if (!any(g_phi != 0) && !any(g_l != 0)) break
    acc <- FALSE
    for (b in seq_len(gd_bt)) {
      phi_n <- pmin(1, pmax(eps, phi - alpha * g_phi))
      l_n   <- pmin(1, pmax(eps, l   - alpha * g_l))
      dec   <- sum(g_phi * (phi_n - phi)) + sum(g_l * (l_n - l))
      L_n   <- loss(cf, phi_n, l_n)
      if (is.finite(L_n) && L_n <= L0 + armijo * dec) { acc <- TRUE; break }
      alpha <- alpha / 2
    }
    if (!acc) break
    phi <- phi_n; l <- l_n; cf <- ols_c(phi, l)
    L1 <- loss(cf, phi, l); rel <- .relimp(L0, L1); L0 <- L1; alpha <- alpha * 2
    if (it_gd >= gd_maxit || rel < gd_tol) break
  }
  it_cd <- 0L
  repeat {
    it_cd <- it_cd + 1L
    phi <- .block_argmin(R0, M, cf, l, phi, K, eps, root_tol)
    l   <- .block_argmin(t(R0), t(M), cf, phi, l, K, eps, root_tol)
    cf  <- ols_c(phi, l)
    L1 <- loss(cf, phi, l); rel <- .relimp(L0, L1); L0 <- L1
    if (it_cd >= cd_maxit || rel < cd_tol) break
  }
  list(cf = cf, phi = phi, l = l, loss = L0, it_gd = it_gd, it_cd = it_cd)
}

# =============================================================================
# 1. 일간 패널 · 멤버십 · 유동성(t-1) · 월말 격자
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
  cat(sprintf("[COMBO] (Ticker,Date) 중복 %d행 - 첫 행만 유지\n", .ndup))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}
.rd[, TV := Close * fifelse(is.finite(as.numeric(Vol)), as.numeric(Vol), 0)]
.rd[, ADV20_L1 := shift(frollmean(TV, .LIQ_WIN, align = "right"), 1L), by = Ticker]
.rd[, TV := NULL]
.rd[, MI := year(Date) * 12L + month(Date)]

.me <- .rd[, .(MEnd = max(Date)), by = MI]
setorder(.me, MI)
.MI_LAST <- max(.me$MI)
.me <- .me[MI < .MI_LAST]                       # 마지막 달 = 진행 중(부분월) 제외
.me[, MON := (MI - 1L) %% 12L + 1L]
if (nrow(.me) < (.FORM_M + .HOLD)) stop("[COMBO] 완결 월 부족")
.all_dates <- sort(unique(.rd$Date))
setkey(.rd, Date)

# =============================================================================
# 2. [B] 월간 초과수익 패널  (rf = ECOS KR_Call1D, 전월말 호가 / 12)
# =============================================================================
.rs <- .rd[MI < .MI_LAST, .(Ticker, MI, Date, Close)]
setorder(.rs, Ticker, Date)
.nn <- nrow(.rs)
.lastrow <- c(.rs$Ticker[-1L] != .rs$Ticker[-.nn] | .rs$MI[-1L] != .rs$MI[-.nn], TRUE)
.mp <- .rs[.lastrow, .(Ticker, MI, Close)]
rm(.rs)
setorder(.mp, Ticker, MI)
.mp[, R := Close / shift(Close) - 1, by = Ticker]
.mp[, GAP := MI - shift(MI), by = Ticker]
.mp[is.na(GAP) | GAP != 1L, R := NA_real_]
.mp <- .mp[is.finite(R), .(MI, Ticker, R)]
if (nrow(.mp) == 0L) stop("[COMBO] 월간 수익률 0행")

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
  stop(sprintf("[COMBO/B] 무위험 패널 부재: %s - 초과수익 정의를 지킬 수 없어 중단", .rf_path))
.ec <- as.data.table(arrow::read_parquet(.rf_path))
if (!all(c("Date", "Value", "Series") %in% names(.ec)))
  stop("[COMBO/B] ecos_bond_rates 열 부재 (Date, Value, Series)")
.ec <- .ec[Series == "KR_Call1D" & is.finite(Value)]
if (nrow(.ec) == 0L) stop("[COMBO/B] KR_Call1D 0행")
.ec[, Date := as.Date(Date)]
setorder(.ec, Date)
.ec[, MIq := year(Date) * 12L + month(Date)]
.rfm <- .ec[, .(RF = Value[.N] / 100 / 12), by = MIq][, .(MI = MIq + 1L, RF)]
rm(.ec)
.n_ret_months <- uniqueN(.mp$MI)
.mp <- merge(.mp, .rfm, by = "MI")
if (nrow(.mp) == 0L) stop("[COMBO/B] 수익률 패널과 Call1D 가 겹치는 달 0개")
.mp[, R := R - RF][, RF := NULL]

.wide <- dcast(.mp, MI ~ Ticker, value.var = "R")
setorder(.wide, MI)
.MIs <- .wide$MI
.RM  <- as.matrix(.wide[, setdiff(names(.wide), "MI"), with = FALSE])
.TK  <- colnames(.RM)
rm(.wide, .mp); gc(verbose = FALSE)
.ym <- function(mi) sprintf("%d-%02d", (mi - 1L) %/% 12L, (mi - 1L) %% 12L + 1L)
cat(sprintf("[COMBO/B] 월간 초과수익 패널 %d개월 (%s ~ %s) x %d종 (rf 결합 전 %d개월)\n",
            length(.MIs), .ym(min(.MIs)), .ym(max(.MIs)), length(.TK), .n_ret_months))

# ---- 반년 HFL 재추정 -> lam 저장 (확장창 >= 120개월, 창 종점 = 그 형성월) -----
#   ★추정 패널 = 그 형성일의 **적격 집합**(K200 U KQ150 + adv20 하한). 논문도 추정 자산 =
#     정렬 자산이고 부모 엔진 RP_AUTO_2404_08129 도 .ELIG 로 열을 자른다. 전 상장 3,419종을
#     넣으면 제1 특이벡터가 극단 수익 소수 종목에 지배돼 .to_unit 사상 후 l 이 EPS 로 붕괴하고
#     Eq.4 의 [1,x,x^2,x^3,x^4] 설계행렬이 퇴화한다(2026-09-10 실측 — 첫 적합에서 중단).
.HF <- .me[MON %in% .HFL_MON]
.HELIG <- .rd[.(.HF$MEnd), .(Date, Ticker, MEM, ADV20_L1), nomatch = 0L][
              MEM & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ, .(Date, Ticker)]
setkey(.HELIG, Date)
.lam <- list()          # key = MI(문자) -> named numeric lam
.n_hfl <- 0L
for (k in seq_len(nrow(.HF))) {
  mi_f <- .HF$MI[k]; d_f <- .HF$MEnd[k]
  ip <- match(mi_f, .MIs)
  if (is.na(ip) || ip < .T0) next
  tk <- .HELIG[.(d_f), Ticker, nomatch = 0L]
  ci <- match(tk, .TK); okc <- !is.na(ci); ci <- ci[okc]; tk <- tk[okc]
  if (!length(ci)) next
  Rm  <- .RM[seq_len(ip), ci, drop = FALSE]      # 확장창: 창 종점 = 형성월 (C1)
  Msk <- is.finite(Rm)
  ki  <- colSums(Msk) >= .TMIN_I
  if (sum(ki) < (.K + 2L)) next
  Rm <- Rm[, ki, drop = FALSE]; Msk <- Msk[, ki, drop = FALSE]; tk <- tk[ki]
  kt <- rowSums(Msk) >= 1L                       # 관측 0 인 달은 phi_t 미정의 -> 제외
  Rm <- Rm[kt, , drop = FALSE]; Msk <- Msk[kt, , drop = FALSE]
  R0 <- Rm; R0[!Msk] <- 0; Mn <- Msk * 1
  fit <- .fit_hfl(R0, Mn, .K, .EPS, .GD_MAXIT, .GD_TOL, .GD_ARMIJO, .GD_BT,
                  .CD_MAXIT, .CD_TOL, .ROOT_TOL)
  lv <- fit$l; names(lv) <- tk
  .lam[[as.character(mi_f)]] <- lv
  .n_hfl <- .n_hfl + 1L
}
if (!length(.lam)) stop("[COMBO/B] HFL 적합 0건 - 확장창 120개월 미충족")
.lam_mi <- sort(as.integer(names(.lam)))
cat(sprintf("[COMBO/B] HFL 반년 적합 %d회 (%s ~ %s) · 첫 lam 종목수 %d · 경과 %.1f분\n",
            .n_hfl, .ym(min(.lam_mi)), .ym(max(.lam_mi)),
            length(.lam[[as.character(min(.lam_mi))]]),
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))

# =============================================================================
# 3. [C] CID (Eq.1) -> 충격 u_t (Eq.2, 확장창) -> beta_CID (Eq.3, 24개월 · winsorize)
#        CID 는 거시 상태변수라 논문대로 **전 상장종목**에서 만든다.
# =============================================================================
.DD <- RAWDATA[, .(Date, Ticker, Ret, Size, Sector_Lv2)]
if (!inherits(.DD$Date, "Date")) .DD[, Date := as.Date(Date)]
.DD[, Ticker := as.character(Ticker)]
.DD[, rr := as.numeric(Ret)]
.DD[!is.finite(rr) | abs(rr) > .CID_CAP, rr := NA_real_]
.DD[, ymi := year(Date) * 12L + month(Date)]
.MEC <- .DD[, .(me = max(Date)), by = ymi]
.MON2 <- .DD[, .(mret = if (sum(is.finite(rr)) >= 1L) prod(1 + rr[is.finite(rr)]) - 1 else NA_real_),
             by = .(Ticker, ymi)]
.EOM <- .DD[Date %in% .MEC$me, .(Ticker, ymi, size_end = Size, ind = Sector_Lv2)]
.EOM <- unique(.EOM, by = c("Ticker", "ymi"))
.MON2 <- merge(.MON2, .EOM, by = c("Ticker", "ymi"))
rm(.DD); gc(verbose = FALSE)
setorder(.MON2, Ticker, ymi)
.MON2[, `:=`(size_prev = shift(size_end), ymi_prev = shift(ymi)), by = Ticker]
.MON2[!is.finite(ymi_prev) | ymi_prev != ymi - 1L, size_prev := NA_real_]

.VAL <- .MON2[is.finite(mret) & is.finite(size_prev) & size_prev > 0 & !is.na(ind)]
.IP  <- .VAL[, .(nf = .N, r_ind = sum(mret * size_prev) / sum(size_prev)),
             by = .(ymi, ind)][nf >= .CID_MINF]
.MKT <- .MON2[is.finite(mret) & is.finite(size_prev) & size_prev > 0,
              .(r_mkt = sum(mret * size_prev) / sum(size_prev)), by = ymi]
.CIDT <- merge(.IP, .MKT, by = "ymi")[, .(CID = mean(abs(r_ind - r_mkt)), n_ind = .N), by = ymi]
setorder(.CIDT, ymi)
.CIDT[, dC := CID - shift(CID)]
.CIDT[, `:=`(dC_l1 = shift(dC), C_l1 = shift(CID))]
.CIDT[, u := NA_real_]
.fr <- which(is.finite(.CIDT$dC) & is.finite(.CIDT$dC_l1) & is.finite(.CIDT$C_l1))
if (length(.fr) >= .CID_BURN) {
  for (k in seq.int(.CID_BURN, length(.fr))) {
    sub <- .CIDT[.fr[seq_len(k)]]                       # 확장창: <= t 만 (C1)
    res <- stats::residuals(stats::lm(dC ~ dC_l1 + C_l1, data = sub))
    set(.CIDT, i = .fr[k], j = "u", value = as.numeric(res[length(res)]))
  }
}
.SS <- .MON2[, .(Ticker, ymi, mret)]
.GRID <- .SS[, .(ymi = seq.int(min(ymi), max(ymi))), by = Ticker]
.SS <- merge(.GRID, .SS, by = c("Ticker", "ymi"), all.x = TRUE)
.SS <- merge(.SS, .CIDT[, .(ymi, u)], by = "ymi", all.x = TRUE)
setorder(.SS, Ticker, ymi)
.SS[, ok := as.integer(is.finite(mret) & is.finite(u))]
.SS[, `:=`(p_ru = fifelse(ok == 1L, mret * u, 0), p_r = fifelse(ok == 1L, mret, 0),
           p_uu = fifelse(ok == 1L, u * u, 0),    p_u = fifelse(ok == 1L, u, 0))]
.SS[, `:=`(n_ok = frollsum(ok, .CID_WIN), Sxy = frollsum(p_ru, .CID_WIN),
           Sy = frollsum(p_r, .CID_WIN), Sxx = frollsum(p_uu, .CID_WIN),
           Sx = frollsum(p_u, .CID_WIN)), by = Ticker]
.SS[, den := n_ok * Sxx - Sx * Sx]
.SS[, beta := fifelse(is.finite(den) & den > 0, (n_ok * Sxy - Sx * Sy) / den, NA_real_)]
.SS[!is.finite(n_ok) | n_ok < .CID_MINO, beta := NA_real_]
.BW <- .SS[is.finite(beta), .(Ticker, ymi, beta)]
.BW[, beta_w := {
  qq <- stats::quantile(beta, c(0.01, 0.99), na.rm = TRUE, names = FALSE)
  pmin(pmax(beta, qq[1]), qq[2])
}, by = ymi]                                            # [C] 명시 winsorize
setkey(.BW, ymi, Ticker)
rm(.SS, .MON2, .VAL, .IP, .MKT, .GRID); gc(verbose = FALSE)
cat(sprintf("[COMBO/C] CID %d개월 (u 유효 %d) · 산업수 중앙값 %.0f · beta_CID 행 %s\n",
            nrow(.CIDT), sum(is.finite(.CIDT$u)), stats::median(.CIDT$n_ind, na.rm = TRUE),
            format(nrow(.BW), big.mark = ",")))

# =============================================================================
# 4. 월별 코호트 - [A] CM -> [B] lam 시브 통제 잔차 -> 상위 .SEL_N -> [C] beta 랭크 비중
# =============================================================================
.me_dates <- .me$MEnd
.cohorts  <- vector("list", length(.me_dates))
.diag     <- vector("list", length(.me_dates))
.nskip_lam <- 0L; .nskip_n <- 0L

for (k in seq_along(.me_dates)) {
  if (k <= .FORM_M) next
  f    <- .me_dates[k]; mi_f <- .me$MI[k]
  lm_i <- .lam_mi[.lam_mi <= mi_f]                       # 가장 최근 반년 적합만 (<= f)
  if (!length(lm_i)) { .nskip_lam <- .nskip_lam + 1L; next }
  lam  <- .lam[[as.character(max(lm_i))]]

  w0     <- .me_dates[k - .FORM_M]
  wdates <- .all_dates[.all_dates > w0 & .all_dates <= f]
  if (!length(wdates)) next

  rf0  <- .rd[.(f), .(Ticker, MEM, ADV20_L1), nomatch = 0L]
  elig <- rf0[MEM & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ, Ticker]
  elig <- intersect(elig, names(lam))                    # lam(통제) 없는 종목은 제외
  if (!length(elig)) next

  wd <- .rd[.(wdates), .(Date, Ticker, Close), nomatch = 0L][Ticker %chin% elig]
  if (!nrow(wd)) next
  setorder(wd, Ticker, Date)
  st <- wd[, .mdd_stats(Close), by = Ticker]
  st[, cm := .W[1] * RI + .W[2] * RII + .W[3] * RIII]    # [A] CM = C - MDD
  st <- st[is.finite(cm)]
  if (nrow(st) < .NDEC) { .nskip_n <- .nskip_n + 1L; next }

  # ---- [B] 통제: CM 을 lam 의 시브 기저(차수 K=4)에 회귀 -> 잔차를 점수로 ----
  st[, lam_i := as.numeric(lam[Ticker])]
  X <- matrix(1, nrow(st), .K + 1L)
  for (j in seq_len(.K)) X[, j + 1L] <- X[, j] * st$lam_i
  st[, score := as.numeric(lm.fit(X, st$cm)$residuals)]

  setorder(st, -score, Ticker)                            # 승자 = 잔차 상위(동값 결정론)
  sel <- st[seq_len(min(.SEL_N, nrow(st)))]

  # ---- [C] 비중: 논문 사전선언 방향(high beta_CID = low E[r]) -> -beta 랭크 선형비중 --
  bs <- .BW[.(mi_f, sel$Ticker), beta_w]
  if (all(!is.finite(bs))) {
    bs <- rep(0, nrow(sel))
  } else {
    bs[!is.finite(bs)] <- stats::median(bs, na.rm = TRUE) # 결측 = 그 달 코호트 중앙값(중립)
  }
  n_s <- nrow(sel)
  rk  <- rank(bs, ties.method = "first")                  # 1 = 최저 beta = 최선호
  wgt <- (n_s + 1 - rk); wgt <- wgt / sum(wgt)

  .cohorts[[k]] <- data.table(Ticker = sel$Ticker, w = wgt)
  .diag[[k]] <- data.table(f = f, N = nrow(st), n_sel = n_s,
                           lam_mi = max(lm_i), n_lam = length(lam),
                           cm_med = stats::median(st$cm),
                           r2_ctrl = 1 - sum(st$score^2) / sum((st$cm - mean(st$cm))^2),
                           beta_med = stats::median(bs, na.rm = TRUE))
}

# =============================================================================
# 5. [A] J-T 오버래핑 - 최근 K=6 코호트 고정 1/K (재스케일 없음)
#    6 슬리브가 모두 존재하는 달부터 산출 -> sum(w) = 1 · 최대 24종 (= 4 x 6 <= 25)
# =============================================================================
.out <- vector("list", length(.me_dates))
for (k in seq_along(.me_dates)) {
  idx <- seq.int(k - .HOLD + 1L, k)
  if (min(idx) < 1L) next
  sl  <- .cohorts[idx]
  if (any(vapply(sl, is.null, logical(1)))) next
  agg <- rbindlist(sl)[, .(Weight = sum(w) / .HOLD), by = Ticker]
  agg <- agg[Weight > 0]
  if (!nrow(agg)) next
  if (nrow(agg) > .NMAX)
    stop(sprintf("[COMBO] %s 종목수 %d > 고정 축 %d - 설계 오류",
                 as.character(.me_dates[k]), nrow(agg), .NMAX))
  .out[[k]] <- data.table(Date = .me_dates[k], Ticker = agg$Ticker,
                          Weight = agg$Weight, Leg = "long")
}
PORTFOLIO <- rbindlist(Filter(Negate(is.null), .out), use.names = TRUE)
if (nrow(PORTFOLIO) == 0L) stop("[COMBO] PORTFOLIO 0행")
setorder(PORTFOLIO, Date, -Weight)

.pm <- PORTFOLIO[, .(n = .N, sw = sum(Weight)), by = Date]
.dg <- rbindlist(Filter(Negate(is.null), .diag), use.names = TRUE)
cat(sprintf(paste0("[COMBO] PORTFOLIO %s행 · %d개월 %s~%s · 월평균 %.1f종(최대 %d) · sum(w) %.4f~%.4f\n",
                   "[COMBO] 통제 R2(CM~시브 lam) 중앙값 %.4f · 적격 N 중앙값 %.0f · ",
                   "lam 미보유 스킵 %d월 · 횡단면 부족 %d월 · 총경과 %.1f분\n"),
            format(nrow(PORTFOLIO), big.mark = ","), uniqueN(PORTFOLIO$Date),
            as.character(min(PORTFOLIO$Date)), as.character(max(PORTFOLIO$Date)),
            mean(.pm$n), max(.pm$n), min(.pm$sw), max(.pm$sw),
            stats::median(.dg$r2_ctrl, na.rm = TRUE), stats::median(.dg$N, na.rm = TRUE),
            .nskip_lam, .nskip_n,
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
