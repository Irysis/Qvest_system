# =============================================================================
# engine.R — RP_AUTO_CLEAN_2407_10175 (충실구현 · 청정 레인)
# 논문: Yang & Shestopaloff (2024) "Low Volatility Stock Portfolio Through High Dimensional
#       Bayesian Cointegration" — https://arxiv.org/abs/2407.10175 (v1)
# 상위 논문(알고리즘 세부를 맡긴 곳): Yang & Shestopaloff (2023) "Bayesian Analysis of High Dimensional
#       Vector Error Correction Model" — https://arxiv.org/abs/2312.17061 (v2)
#
# 산출: PORTFOLIO(Date, Ticker, Weight, Leg) — 논문 비중 그대로(롱숏 · engine_direct).
# 변형: sr_opt  = §4.2 식 (13)-(14) SR 최대화(벤치마크 비중 1/2 이상) — 대표
#       vol_min = §5.2 식 (15) 변동성 최소화(벤치마크 비중 0 이상)
#
# 절차(신호일 = 월말 d · 학습 창 = d 까지 24개 달력월 · 그 뒤 정보 무사용):
#   1 유니버스(측정 축 멤버) → 창 안 전 거래일 자료 보유 → ADF 로 I(1) 선별           (§3.2)
#   2 Y = 창 첫날 대비 누적수익 지수 · A = dY · B = Y(t-1)                              (§2.1 · 상위 §4.2)
#   3 사전추정 Pi~ = (AB')(BB')^-1 → 직교분해 Pi~ = R~'S~'                              (식 3-4)
#   4 dY 중심화 · S~'Y 정규화 → 열별 SSL · EM(알고리즘 1: 공통 lambda0 사다리 → 무작위 열 증가)  (§2.2-2.4)
#   5 Pi^ = R^'S~' 의 비영 독립 행 → alpha_i = Pi^_i / ||Pi^_i||_1                       (식 5 · §3.1)
#   6 theta 최적화(변형별) → 종목 비중 = sum_i theta_i alpha_i + theta_b x 벤치마크      (§4.1 · §5.2)
# 미명시 값의 보충 · 논문과 다른 점은 전부 FIDELITY.json(changed · constants · paper_steps)에 있다.
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(quadprog)
  library(tseries)
})

# ---- 변형 스위치(하네스가 .RP_VARIANT 로 넣는다) ------------------------------------
.VARIANTS <- c("sr_opt", "vol_min")
VARIANT <- if (exists(".RP_VARIANT", inherits = FALSE) && nzchar(.RP_VARIANT)) .RP_VARIANT else "sr_opt"
if (!VARIANT %in% .VARIANTS) stop("unknown variant: ", VARIANT)

# ---- 측정 축 시작(리터럴 금지 — 호출자가 넣는다) -----------------------------------
.SIG_FROM <- .RP_START_DATE

# ---- 상수(전부 FIDELITY.json constants 에 같은 값으로 실려 있다) ---------------------
TRAIN_MONTHS  <- 24
BENCH_MIN     <- 0.5
ADF_ALPHA     <- 0.05
SIG_DF        <- 2
BETA_MODE_NUM <- 1
BETA_MODE_DEN <- 2
LAMBDA1       <- 1
N_LADDER      <- 100
DELTA_DIV     <- 100
N_R           <- 100
EM_MAX_ITER   <- 500
EPS_CAP       <- 1e-3
CD_TOL        <- 1e-8
CD_MAX_SWEEP  <- 10000
KKT_TOL       <- 1e-9
SIG2_FLOOR    <- 1e-12
ZVAR_RTOL     <- 1e-10
RANK_TOL      <- 1e-7
QP_RIDGE      <- 1e-9
ENUM_MAX      <- 24
ENUM_CHUNK    <- 65536
SEED          <- 1
MIN_P         <- 2

# =============================================================================
# SSL 사후 가중 — 상위 논문 식 (24)-(27)
#   p*_theta(x)      = [1 + (lambda0 (1-theta)) / (lambda1 theta) * exp(|x| (lambda1 - lambda0))]^-1
#   lambda*_theta(x) = lambda0 + (lambda1 - lambda0) p*_theta(x)
# =============================================================================
.pstar <- function(x, theta, l0) {
  lr <- log(l0) - log(LAMBDA1) + log1p(-theta) - log(theta) - abs(x) * (l0 - LAMBDA1)
  1 / (1 + exp(lr))
}
.lstar <- function(x, theta, l0) l0 + (LAMBDA1 - l0) * .pstar(x, theta, l0)

# =============================================================================
# 가중 lasso(EM 의 M 단계) — argmin_b { sum_t e_t^2 + 2 sum_i pen_i |b_i| }
#   = argmin_b { (1/2) b'Gb - c'b + sum_i pen_i |b_i| }  (G = Z'Z · c = Z'a · pen_i = sigma^2 lambda*_i)
#   좌표하강 + 활성 집합. g = c - Gb(잔차 상관).
# =============================================================================
.wlasso <- function(G, Gd, cj, pen, beta, tol, ktol) {
  nz <- which(beta != 0)
  g <- if (length(nz)) cj - drop(G[, nz, drop = FALSE] %*% beta[nz]) else cj
  act <- which(beta != 0 | abs(g) > pen + ktol)
  repeat {
    if (length(act)) {
      for (sw in seq_len(CD_MAX_SWEEP)) {
        dmax <- 0
        for (i in act) {
          bi <- beta[i]
          zi <- g[i] + Gd[i] * bi
          ai <- abs(zi) - pen[i]
          bn <- if (ai > 0) sign(zi) * ai / Gd[i] else 0
          dl <- bn - bi
          if (dl != 0) {
            beta[i] <- bn
            g <- g - G[, i] * dl
            if (abs(dl) > dmax) dmax <- abs(dl)
          }
        }
        if (dmax < tol) break
      }
      nz <- which(beta != 0)
      g <- if (length(nz)) cj - drop(G[, nz, drop = FALSE] %*% beta[nz]) else cj
    }
    add <- setdiff(which(beta == 0 & abs(g) > pen + ktol), act)
    if (!length(add)) break
    act <- c(act, add)
  }
  list(beta = beta, g = g)
}

# =============================================================================
# 열 j 의 EM — 상위 논문 알고리즘 1·2 의 안쪽 반복(냉시작: 매 호출 초기값에서 출발)
#   beta(k)    = argmin { sum e^2 + 2 sum_i sigma^2(k-1) lambda*_{theta(k-1)}(beta_i(k-1)) |beta_i| }
#   theta(k)   = (a_j - 1 + sum_{i in [p]} p*_{theta(k-1)}(beta_i(k))) / (a_j + b_j + p - 2)
#   sigma^2(k) = sum_t e_t(k)^2 / (T - 2)
#   정지: ||beta(k) - beta(k-1)||_2 < eps_cap 또는 k = K
#   초기값(보충): beta(0) = 0 · theta(0) = a_j / (a_j + b_j) · sigma^2(0) = sum_t a_t^2 / (T - 2)
#   식별되지 않는 변환 회귀변수(p - nreg 개)의 계수는 0 이고 theta 합에 p*(0) 으로 들어간다.
# =============================================================================
.ssl_em <- function(cj, G, Gd, rss0j, l0, aj, bj, pdim, nT) {
  nreg <- length(cj)
  beta <- numeric(nreg)
  theta <- aj / (aj + bj)
  s20 <- rss0j / (nT - SIG_DF)
  sig2 <- s20
  bunit <- sqrt(rss0j / nT) / sqrt(nT)
  ktol <- KKT_TOL * max(abs(cj))
  for (k in seq_len(EM_MAX_ITER)) {
    pen <- sig2 * .lstar(beta, theta, l0)
    fit <- .wlasso(G, Gd, cj, pen, beta, CD_TOL * bunit, ktol)
    bnew <- fit$beta
    theta <- (aj - BETA_MODE_NUM + sum(.pstar(bnew, theta, l0)) + (pdim - nreg) * .pstar(0, theta, l0)) /
      (aj + bj + pdim - BETA_MODE_DEN)
    rss <- rss0j - sum(bnew * (cj + fit$g))
    sig2 <- max(rss / (nT - SIG_DF), SIG2_FLOOR * s20)
    dnorm <- sqrt(sum((bnew - beta)^2))
    beta <- bnew
    if (dnorm < EPS_CAP * bunit) break
  }
  beta
}

# ---- 행렬 계수 · 선형독립 열(열 순서 유지) — R qr(LINPACK dqrdc2): 종속 열을 뒤로 넘긴다 ----
.mrank <- function(M) {
  if (!ncol(M)) return(0L)
  rz <- which(rowSums(M != 0) > 0)
  if (!length(rz)) return(0L)
  qr(M[rz, , drop = FALSE], tol = RANK_TOL)$rank
}
.indep <- function(M) {
  if (!ncol(M)) return(integer(0))
  rz <- which(rowSums(M != 0) > 0)
  if (!length(rz)) return(integer(0))
  qq <- qr(M[rz, , drop = FALSE], tol = RANK_TOL)
  sort(qq$pivot[seq_len(qq$rank)])
}

# =============================================================================
# 논문 알고리즘 1 (= 상위 논문 알고리즘 2) — 열별 SSL · EM 으로 R^ 과 계수 r^ 을 추정
#   입력: Cm = Z~'A~ (nreg x p) · G = Z~'Z~ · rss0 = 열별 sum a^2 · nT = T · seed
#   1단계: lambda0 를 모든 열에 같은 폭(dlam)으로 올리며 r^ < T / sqrt(p) 가 될 때까지
#   2단계: 비영 열 집합 P 에서 균등 추출한 열 j 의 lambda0_j 를 dl2 * |P| 만큼 올리고 그 열만 재추정,
#          영벡터가 되면 P 에서 뺀다. 계수가 N_R 회 연속 같거나 0 이면 멈춘다.
#   ★매 lambda0 에서 EM 은 초기값에서 다시 출발한다(상위 논문 상자 'Initialise theta_j(0), beta_j(0), sigma_j^2(0)').
#     그래서 1단계 중간 칸의 R^ 은 정지 판정(r^ >= T/sqrt(p))에만 쓰이고 다음 칸으로 넘어가지 않는다 —
#     중간 칸에서는 계수가 문턱 이상임을 확인하는 데 필요한 열만 EM 을 돌리고, 정지 칸에서는
#     첫 M 단계가 영이 아닌 열(나머지는 정확히 영벡터) 전부를 돌린다. 결과는 전 열을 돌린 것과 같다.
# =============================================================================
.ssl_cointegration <- function(Cm, G, Gd, rss0, nT, seed_m) {
  nreg <- nrow(Cm)
  p <- ncol(Cm)
  jj <- seq_len(p)
  aj <- p - jj + 1
  bj <- p
  th0 <- aj / (aj + bj)
  s20 <- rss0 / (nT - SIG_DF)
  absC <- abs(Cm)
  kst <- max.col(t(absC), ties.method = "first")
  Mj <- absC[cbind(kst, jj)]
  thr <- nT / sqrt(p)
  need <- as.integer(ceiling(thr))
  out0 <- list(P = integer(0), B = matrix(0, nreg, 0L), steps = 0L, draws = 0L, r1 = 0L)
  if (p < need) return(out0)
  lam_stop <- sort(Mj / s20, decreasing = TRUE)[need]
  dlam <- (lam_stop - LAMBDA1) / N_LADDER
  if (!is.finite(dlam) || dlam <= 0) return(out0)
  em <- function(j, l0) .ssl_em(Cm[, j], G, Gd, rss0[j], l0, aj[j], bj, p, nT)

  # ---- 1단계: 공통 lambda0 사다리 ----
  k <- 0L
  l0 <- LAMBDA1
  found <- integer(0)
  cols <- list()
  repeat {
    k <- k + 1L
    l0 <- LAMBDA1 + k * dlam
    tau <- s20 * .lstar(0, th0, l0)
    alive <- which(Mj > tau + KKT_TOL * Mj)
    found <- integer(0)
    cols <- list()
    if (!length(alive)) break
    alive <- alive[order(Mj[alive] / tau[alive])]
    reps <- alive[!duplicated(kst[alive])]
    ordv <- c(reps, setdiff(alive, reps))
    cert <- FALSE
    chk <- need
    for (pos in seq_along(ordv)) {
      e <- em(ordv[pos], l0)
      if (any(e != 0)) {
        found <- c(found, ordv[pos])
        cols[[length(cols) + 1L]] <- e
      }
      if (pos == chk || pos == length(ordv)) {
        if (length(found) >= need && .mrank(do.call(cbind, cols)) >= thr) {
          cert <- TRUE
          break
        }
        chk <- pos + need
      }
    }
    if (!cert) break
  }
  Pset <- found
  Bmat <- if (length(cols)) do.call(cbind, cols) else matrix(0, nreg, 0L)
  r1 <- .mrank(Bmat)

  # ---- 2단계: 무작위 열의 lambda0_j 증가 ----
  set.seed(seed_m)
  l0v <- rep(l0, length(Pset))
  rhat <- r1
  rbuf <- rep(rhat + 1L, N_R)
  dl2 <- dlam / DELTA_DIV
  draws <- 0L
  while (rhat != 0L && !all(rbuf == rhat)) {
    draws <- draws + 1L
    ii <- sample.int(length(Pset), 1L)
    l0v[ii] <- l0v[ii] + dl2 * length(Pset)
    e <- em(Pset[ii], l0v[ii])
    if (any(e != 0)) {
      Bmat[, ii] <- e
    } else {
      Pset <- Pset[-ii]
      l0v <- l0v[-ii]
      Bmat <- Bmat[, -ii, drop = FALSE]
    }
    rhat <- .mrank(Bmat)
    rbuf <- c(rbuf[-1L], rhat)
  }
  list(P = Pset, B = Bmat, steps = k, draws = draws, r1 = r1)
}

# =============================================================================
# theta 최적화 — Psi = sum_i theta_i (alpha_i Y) + theta_b (beta Y) · ||theta||_1 = 1  (§4.1)
#   입력 수익 = 학습 창의 일별 차분(정규화 가격 단위): X (T x r) = 공적분 포트폴리오 · dB = 벤치마크
# =============================================================================
# sr_opt — 식 (13)-(14): max E[mu]/sigma  s.t. theta_b >= BENCH_MIN (닫힌 집합).
#   비율 목적은 척도 불변이므로 제약을 원뿔 theta_b >= kap * sum|theta_i| 로 쓰고
#   평균이 양수가 될 수 있으면 min theta'V theta s.t. m'theta = 1 (볼록 QP · 전역해),
#   될 수 없으면 원뿔 밑면의 극점(theta_b = BENCH_MIN · theta_i = +-(1 - BENCH_MIN))에서 최대.
.theta_sr <- function(m, V, s) {
  n <- length(m)
  r <- n - 1L
  kap <- BENCH_MIN / (1 - BENCH_MIN)
  fobj <- function(th) {
    v <- sum(th * drop(V %*% th))
    if (is.finite(v) && v > 0) sum(m * th) / sqrt(v) else -Inf
  }
  cand <- list(c(numeric(r), 1))
  for (i in seq_len(r)) for (sg in c(1, -1)) {
    th <- numeric(n)
    th[i] <- sg * (1 - BENCH_MIN)
    th[n] <- BENCH_MIN
    cand[[length(cand) + 1L]] <- th
  }
  fv <- vapply(cand, fobj, numeric(1))
  th_v <- cand[[which.max(fv)]]
  if (m[n] + max(abs(m[seq_len(r)])) / kap <= 0) return(th_v)
  Cr <- V / tcrossprod(s)
  ms <- m / s
  M <- rbind(cbind(diag(r), -diag(r), 0), c(numeric(2L * r), 1))
  nzv <- 2L * r + 1L
  Dm <- crossprod(M, Cr %*% M) + diag(QP_RIDGE, nzv)
  a_eq <- drop(crossprod(M, ms))
  a_in <- c(rep(-kap * s[n] / s[seq_len(r)], 2L), 1)
  Am <- cbind(a_eq, a_in, diag(nzv))
  qp <- tryCatch(quadprog::solve.QP(Dm, numeric(nzv), Am, c(1, numeric(nzv + 1L)), meq = 1L),
                 error = function(e) NULL)
  if (is.null(qp)) return(th_v)
  tt <- drop(M %*% qp$solution) / s
  if (!all(is.finite(tt)) || sum(abs(tt)) <= 0) return(th_v)
  tt <- tt / sum(abs(tt))
  if (fobj(tt) >= fobj(th_v)) tt else th_v
}

# vol_min — 식 (15): min sigma  s.t. ||theta||_1 = 1 · theta_b >= 0 (닫힌 집합).
#   min_{||theta||_1 = 1} theta'V theta = 1 / max_{sg in {+-1}^n} sg'V^-1 sg · 해 theta = V^-1 sg / ||V^-1 sg||_1
#   (코시-슈바르츠). 부호 패턴 전수(벤치마크 부호 = + 고정 — 목적이 theta -> -theta 에 대칭).
#   포트폴리오 수가 ENUM_MAX 를 넘으면 부호 한 칸 뒤집기 국소 탐색(근사).
.theta_vm <- function(V, s) {
  n <- length(s)
  r <- n - 1L
  Cr <- V / tcrossprod(s)
  Ci <- tryCatch(solve(Cr + diag(QP_RIDGE, n)), error = function(e) NULL)
  if (is.null(Ci)) return(c(numeric(r), 1))
  Q <- Ci / tcrossprod(s)
  if (r <= ENUM_MAX) {
    tot <- 2^r
    pw <- 2^(seq_len(r) - 1L)
    hi_v <- -Inf
    hi_s <- rep(1, n)
    st <- 0
    while (st < tot) {
      idv <- st + seq_len(min(ENUM_CHUNK, tot - st)) - 1
      S <- cbind(1 - 2 * outer(idv, pw, function(a, b) (a %/% b) %% 2), 1)
      val <- rowSums((S %*% Q) * S)
      w <- which.max(val)
      if (val[w] > hi_v) {
        hi_v <- val[w]
        hi_s <- S[w, ]
      }
      st <- st + length(idv)
    }
  } else {
    ev <- eigen(Q, symmetric = TRUE)$vectors[, 1L]
    hi_s <- ifelse(ev >= 0, 1, -1)
    if (hi_s[n] < 0) hi_s <- -hi_s
    repeat {
      gain <- 4 * (diag(Q) - hi_s * drop(Q %*% hi_s))
      gain[n] <- -Inf
      i <- which.max(gain)
      if (!(gain[i] > 0)) break
      hi_s[i] <- -hi_s[i]
    }
  }
  tt <- drop(Q %*% hi_s)
  if (!all(is.finite(tt)) || sum(abs(tt)) <= 0) return(c(numeric(r), 1))
  tt <- tt / sum(abs(tt))
  if (tt[n] < 0) tt <- -tt
  tt
}

.solve_theta <- function(X, dB) {
  r <- ncol(X)
  if (r == 0L) return(1)
  Xa <- cbind(X, dB)
  nn <- nrow(Xa)
  m <- colMeans(Xa)
  V <- crossprod(Xa - rep(m, each = nn)) / nn
  s <- sqrt(diag(V))
  th <- numeric(r + 1L)
  ok <- which(is.finite(s[seq_len(r)]) & s[seq_len(r)] > 0)
  if (!length(ok) || !(is.finite(s[r + 1L]) && s[r + 1L] > 0)) {
    th[r + 1L] <- 1
    return(th)
  }
  idx <- c(ok, r + 1L)
  if (identical(VARIANT, "sr_opt")) {
    th[idx] <- .theta_sr(m[idx], V[idx, idx, drop = FALSE], s[idx])
  } else {
    th[idx] <- .theta_vm(V[idx, idx, drop = FALSE], s[idx])
  }
  th
}

# ---- 표준 ADF(R tseries::adf.test 기본: 상수 + 선형 추세 · 시차 k = trunc((n-1)^(1/3))) ----
.adf_p <- function(x) tryCatch(suppressWarnings(tseries::adf.test(x)$p.value), error = function(e) NA_real_)

# =============================================================================
# 0. 입력 격자 — RAWDATA 는 읽기만 한다(참조 수정 없음)
# =============================================================================
stopifnot(is.data.table(RAWDATA), is.data.table(BM_DT))
.NEED <- c("Date", "Ticker", "Ret", "Size", "K200", "KQ150")
if (!all(.NEED %in% names(RAWDATA)))
  stop("[engine] RAWDATA columns missing: ", paste(setdiff(.NEED, names(RAWDATA)), collapse = ","))
if (!all(c("Date", "BM_Ret") %in% names(BM_DT))) stop("[engine] BM_DT needs Date and BM_Ret")
# 벤치마크(KOSPI200) 구성종목 표식 — 측정 축 주입 뒤에는 원 지수 멤버십이 K200_IDX 에 있다(하네스 고지 H2)
.IDXCOL <- if ("K200_IDX" %in% names(RAWDATA)) "K200_IDX" else "K200"

.dnum   <- as.integer(RAWDATA$Date)
.tkv    <- as.character(RAWDATA$Ticker)
.dgrid  <- sort(unique(.dnum))
.dates  <- as.Date(.dgrid, origin = "1970-01-01")
.tk_all <- sort(unique(.tkv))
.RETM   <- matrix(NA_real_, nrow = length(.dgrid), ncol = length(.tk_all))
.RETM[cbind(match(.dnum, .dgrid), match(.tkv, .tk_all))] <- as.numeric(RAWDATA$Ret)
.bmr    <- as.numeric(BM_DT$BM_Ret)[match(.dgrid, as.integer(BM_DT$Date))]

# 달력월 격자: 각 달의 첫 · 마지막 거래일 위치
.mi      <- as.integer(format(.dates, "%Y")) * 12L + as.integer(format(.dates, "%m")) - 1L
.m_first <- which(c(TRUE, diff(.mi) != 0L))
.m_last  <- which(c(diff(.mi) != 0L, TRUE))
.m_id    <- .mi[.m_first]

# 신호 달: (a) 월말이 측정 축 시작 이후 (b) 격자에 다음 달이 있다(월말 확정)
#          (c) 학습 창 24개 달력월이 격자에 연속으로 있고 창의 첫 달이 격자의 첫 달이 아니다(첫 달은 온전한지 알 수 없다)
.sig_m  <- integer(0)
.sig_lo <- integer(0)
for (.s in seq_along(.m_id)) {
  if (.s >= length(.m_id)) next
  if (.dates[.m_last[.s]] < .SIG_FROM) next
  .s0 <- match(.m_id[.s] - (TRAIN_MONTHS - 1L), .m_id)
  if (is.na(.s0) || .s0 < 2L || (.s - .s0 + 1L) != TRAIN_MONTHS) next
  .sig_m  <- c(.sig_m, .s)
  .sig_lo <- c(.sig_lo, .m_first[.s0])
}
.sig_hi <- .m_last[.sig_m]

# 신호일 횡단면(측정 축 멤버 · 시가총액 · 지수 표식) — 신호일 행만 복사
.sel <- which(.dnum %in% .dgrid[.sig_hi])
.XS <- data.table(dn = .dnum[.sel], Ticker = .tkv[.sel], Size = as.numeric(RAWDATA$Size[.sel]),
                  K200 = RAWDATA$K200[.sel], KQ150 = RAWDATA$KQ150[.sel],
                  IDX = RAWDATA[[.IDXCOL]][.sel])
.XS <- unique(.XS[K200 == 1 | KQ150 == 1], by = c("dn", "Ticker"))
.XSL <- split(.XS, by = "dn")
rm(.sel, .XS)

# =============================================================================
# 1. 한 신호일의 추정 · 비중 — 창 = 격자 위치 i0..i1 (i1 = 신호일 · 그 뒤 자료 무사용)
# =============================================================================
.fit_month <- function(i0, i1) {
  d_end <- .dates[i1]
  rows <- i0:i1
  nT <- length(rows) - 1L
  mem <- .XSL[[as.character(.dgrid[i1])]]
  if (is.null(mem) || !nrow(mem)) return(list(pf = NULL, note = "skip: no members"))

  # ---- 벤치마크: 학습용 수익(BM_DT) + 보유용 구성종목 시총가중 바스켓 ----
  br <- .bmr[rows[-1L]]
  if (any(!is.finite(br)) || any(br <= -1)) return(list(pf = NULL, note = "skip: benchmark return missing"))
  bl <- c(1, cumprod(1 + br))
  dB <- bl[-1L] - bl[-(nT + 1L)]
  bk <- mem[IDX == 1 & is.finite(Size) & Size > 0]
  if (!nrow(bk)) return(list(pf = NULL, note = "skip: no index members"))
  bw <- bk$Size / sum(bk$Size)

  # ---- 자산공간: 창 안 전 거래일 자료 보유 → 정규화 가격 Y(창 첫날 = 1) ----
  sub <- .RETM[rows, match(mem$Ticker, .tk_all), drop = FALSE]
  full <- which(colSums(is.na(sub)) == 0L)
  R1 <- sub[-1L, full, drop = FALSE]
  tks <- mem$Ticker[full]
  szs <- mem$Size[full]
  okr <- which(colSums(!(is.finite(R1) & R1 > -1)) == 0L)
  R1 <- R1[, okr, drop = FALSE]
  tks <- tks[okr]
  szs <- szs[okr]
  if (ncol(R1) < MIN_P) return(list(pf = NULL, note = "skip: too few complete series"))
  Y <- rbind(1, apply(1 + R1, 2L, cumprod))
  dY <- Y[-1L, , drop = FALSE] - Y[-(nT + 1L), , drop = FALSE]
  vv <- colSums((dY - rep(colMeans(dY), each = nT))^2)

  # ---- I(1) 선별: 수준은 단위근 기각 못 함 · 차분은 기각 ----
  i1set <- logical(ncol(Y))
  for (jx in which(is.finite(vv) & vv > 0)) {
    pl <- .adf_p(Y[, jx])
    if (!is.finite(pl) || pl < ADF_ALPHA) next
    pd <- .adf_p(dY[, jx])
    i1set[jx] <- is.finite(pd) && pd < ADF_ALPHA
  }
  keep <- which(i1set)
  p0 <- ncol(Y)
  if (length(keep) < MIN_P) return(list(pf = NULL, note = "skip: too few I(1) series"))

  # ---- 종목 순서(열 번호 j): 신호일 시가총액 내림차순 · 동률은 종목코드 ----
  ord <- keep[order(-szs[keep], tks[keep], na.last = TRUE)]
  Y <- Y[, ord, drop = FALSE]
  tks <- tks[ord]
  p <- length(ord)
  if (p < nT / sqrt(p)) return(list(pf = NULL, note = "skip: p below rank bound"))
  A <- Y[-1L, , drop = FALSE] - Y[-(nT + 1L), , drop = FALSE]
  B <- Y[-(nT + 1L), , drop = FALSE]

  # ---- 사전추정 Pi~' = B^+ A (식 3 · 의사역행렬) → QR: Pi~' = S~ R~ (식 4) ----
  #   B = U D V' 이면 Pi~' = V (D^-1 U'A) = V W · W = Qw Rw → S~ = V Qw · 변환 회귀변수 Z = B S~ = U D Qw
  sv <- svd(B)
  ks <- which(sv$d > max(dim(B)) * .Machine$double.eps * sv$d[1L])
  U <- sv$u[, ks, drop = FALSE]
  Vm <- sv$v[, ks, drop = FALSE]
  dk <- sv$d[ks]
  q <- length(ks)
  W <- crossprod(U, A) / dk
  qw <- qr(W[, seq_len(min(p, q)), drop = FALSE], tol = RANK_TOL)
  if (qw$rank < q && p > q) qw <- qr(W, tol = RANK_TOL)
  rk <- qw$rank
  if (rk < 1L) return(list(pf = NULL, note = "skip: degenerate decomposition"))
  Qw <- qr.Q(qw)[, seq_len(rk), drop = FALSE]
  Z <- (U * rep(dk, each = nT)) %*% Qw
  Sm <- Vm %*% Qw

  # ---- 전처리: dY 중심화 · S~'Y 정규화(평균 0 · 분산 T) — 상위 논문 식 (30)-(31) ----
  Zc <- Z - rep(colMeans(Z), each = nT)
  sdz <- sqrt(colMeans(Zc^2))
  okz <- which(is.finite(sdz) & sdz > ZVAR_RTOL * sqrt(colMeans(Z^2)))
  if (!length(okz)) return(list(pf = NULL, note = "skip: no transformed regressor"))
  Zc <- Zc[, okz, drop = FALSE]
  sdz <- sdz[okz]
  Sm <- Sm[, okz, drop = FALSE]
  Zt <- Zc * rep(sqrt(nT) / sdz, each = nT)
  Ac <- A - rep(colMeans(A), each = nT)
  Cm <- crossprod(Zt, Ac)
  G <- crossprod(Zt)
  rss0 <- colSums(Ac^2)

  # ---- 열별 SSL · EM (알고리즘 1) ----
  ssl <- .ssl_cointegration(Cm, G, diag(G), rss0, nT, SEED + as.integer(format(d_end, "%Y%m")))

  # ---- 정상 포트폴리오: Pi^ = R^'S~' 의 비영 독립 행(식 5 · §3.1) → alpha = Pi^_i / ||Pi^_i||_1 ----
  o <- order(ssl$P)
  Bm <- ssl$B[, o, drop = FALSE]
  sel <- .indep(Bm)
  alpha <- matrix(0, p, 0L)
  if (length(sel)) {
    Pi <- Sm %*% (Bm[, sel, drop = FALSE] * (sqrt(nT) / sdz))
    l1 <- colSums(abs(Pi))
    okp <- which(is.finite(l1) & l1 > 0)
    alpha <- Pi[, okp, drop = FALSE] / rep(l1[okp], each = p)
  }
  r <- ncol(alpha)

  # ---- theta 최적화(변형별) — 학습 창의 일별 차분으로 ----
  vals <- Y %*% alpha
  X <- vals[-1L, , drop = FALSE] - vals[-(nT + 1L), , drop = FALSE]
  theta <- .solve_theta(X, dB)
  thb <- theta[r + 1L]

  # ---- 종목 비중: 신호일의 달러 보유 = theta_i alpha_ij Y_Tj + theta_b b_T x 바스켓 → 합계 배분 1 로 환산 ----
  bT <- bl[nT + 1L]
  if (r > 0L) {
    aY <- alpha * Y[nT + 1L, ]
    hs <- drop(aY %*% theta[seq_len(r)])
    CT <- sum(abs(theta[seq_len(r)]) * colSums(abs(aY))) + thb * bT
    wd <- data.table(Ticker = c(tks, bk$Ticker), Weight = c(hs, thb * bT * bw) / CT)
  } else {
    CT <- thb * bT
    wd <- data.table(Ticker = bk$Ticker, Weight = thb * bT * bw / CT)
  }
  if (!is.finite(CT) || CT <= 0) return(list(pf = NULL, note = "skip: nonpositive capital base"))
  wd <- wd[, list(Weight = sum(Weight)), by = Ticker]
  wd <- wd[is.finite(Weight) & Weight != 0]
  if (!nrow(wd)) return(list(pf = NULL, note = "skip: empty weights"))
  pf <- data.table(Date = d_end, Ticker = wd$Ticker, Weight = wd$Weight,
                   Leg = ifelse(wd$Weight > 0, "long", "short"))
  list(pf = pf, note = sprintf("p0=%d p=%d nreg=%d ladder=%d r1=%d draws=%d nonzero=%d r=%d theta_b=%.4f",
                               p0, p, length(okz), ssl$steps, ssl$r1, ssl$draws, length(ssl$P), r, thb))
}

# =============================================================================
# 2. 월별 실행 → PORTFOLIO
# =============================================================================
.res <- vector("list", length(.sig_hi))
cat(sprintf("[engine] variant=%s signal months=%d\n", VARIANT, length(.sig_hi)))
for (.s in seq_along(.sig_hi)) {
  .t0 <- proc.time()[[3L]]
  .fm <- .fit_month(.sig_lo[.s], .sig_hi[.s])
  if (!is.null(.fm$pf)) .res[[.s]] <- .fm$pf
  cat(sprintf("[engine] %s %s (%.0fs)\n", format(.dates[.sig_hi[.s]]), .fm$note, proc.time()[[3L]] - .t0))
}
PORTFOLIO <- rbindlist(.res)
if (!nrow(PORTFOLIO)) stop("[engine] no output rows: no signal month with a full training window")
cat(sprintf("[engine] PORTFOLIO rows=%d signal dates=%d variant=%s\n", nrow(PORTFOLIO), uniqueN(PORTFOLIO$Date), VARIANT))
