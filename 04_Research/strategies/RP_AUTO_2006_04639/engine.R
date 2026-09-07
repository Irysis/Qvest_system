# =============================================================================
# engine.R — RP_AUTO_2006_04639   (재구현 v2 · 2026-09-07 · 앞 판 = engine.rejected1.R)
# "Dynamic (Horizon Specific) Network Risk" — Barunik & Ellington, arXiv:2006.04639
#   원문: arxiv.org/html/2006.04639v1 (+v2 대조). RV 식의 제곱근은 PDF 텍스트(jina 추출)로
#   확인: "RV_t = sqrt( SUM_{i=1}^{D} (p_{t,i} - p_{t,i-1})^2 )".
#
# ★fidelity = ADAPTED.  **선언 정본 = FIDELITY.json** (이 헤더는 요약 사본이다)
#
# ===== 감사(2026-09-06) 지적 → 이 판에서 되돌린 것 =============================
#  (A) 수익 정의 — 논문 §Data: R_t = SUM_{i=1..D}(p_{t,i} - p_{t,i-1}) = p_{t,D} - p_{t,0}
#      = **일중(그날 첫 가격 ~ 마지막 가격)** 수익, 오버나이트 갭 배제. 앞 판은 종가-종가
#      RAWDATA$Ret 을 썼다. 이 판: R_t = log(Close_t / Open_t). 식(16) NET(d) 구성 포트폴리오
#      수익과 식(17) 회귀 LHS 는 이 R_t 만 소비한다 (RAWDATA$Ret 은 이 엔진에서 미사용).
#  (B) 실패월 — 네트워크 미산출 달은 NET(d) 일별 시계열이 **그 달 전부 부재(NA)** 다.
#      날짜 -> 시그널일 사상은 "직전 달 월말 거래일" 하나로 고정(findInterval 이월 제거).
#  (C) 헤지 다리 — 논문 §5.2 그대로: **최고 20% beta^NET 롱 / 최저 20% 숏**. 앞 판 반전 폐기.
#  (D) 대역 경계 — 저자 본인 관행(frequencyConnectedness: 경계 = pi/d) 에 맞춰 wc = pi/5.
#
# ===== 논문 원문 인용 (그대로 옮긴 것) ========================================
#  §Data    "we compute daily returns R_t = SUM_{i=1}^{D}(p_{t,i} - p_{t,i-1}) and realized
#            volatility RV_t = sqrt(SUM_{i=1}^{D}(p_{t,i} - p_{t,i-1})^2)" (5분 간격 ·
#            "p_{t,i} is the intraday price of the asset")
#  §2 식(4) [theta(u,d)]_{j,k} = sigma_kk^{-1} INT_a^b |[Psi(u)e^{-iw}Sigma(u)]_{j,k}|^2 dw
#            / INT_{-pi}^{pi} [{Psi(u)e^{-iw}}Sigma(u){Psi(u)e^{+iw}}']_{j,j} dw
#            [theta~(u,d)]_{j,k} = [theta(u,d)]_{j,k} / SUM_{k=1}^{N} [theta(u,inf)]_{j,k}
#  식(6)(7) C_{j<-.}(u,d) = 100 x SUM_{k!=j}[theta~(u,d)]_{j,k} / SUM_{j,k}[theta~(u,inf)]_{j,k}
#            C_{j->.}(u,d) = 100 x SUM_{k!=j}[theta~(u,d)]_{k,j} / SUM_{j,k}[theta~(u,inf)]_{k,j}
#            net-directional = C_{j->.}(u,d) - C_{j<-.}(u,d)
#  §2/§3    TVP-VAR p = 2 (fn 11) · H = 100 (강건성 H in {50,100,200}) · QBLL: "a kernel
#            weighting function that provides larger weights to observations that surround
#            the period whose coefficient and covariance matrices are of interest"
#  §3.1     "short-term as 1 day-1 week and long-term as horizons as 1 week-inf" · A = 전 지평
#            (fn 13: 대역 선택은 "subjective" — 수치 경계 없음)
#  §3.1.1   "each day we sort S&P500 stocks above and below the day's median price level and
#  (v2 4.1.1) define these as small and big stocks. Then, conditional on size, we sort on
#            horizon specific net-directional connectedness and create value-weighted to and
#            from portfolios. These portfolios admit stocks above (below) the 70th (30th)
#            percentile ... We then take an average of the to and from portfolios and then a
#            long-short position in the respective small and big portfolios."
#            식(8)/(16) NET(d)_t = (from_small + to_small)/2 - (from_big + to_big)/2
#  §5.2     R_{i,t} = b0_i + bMKT_i MKT_t + bNET(d)_i NET(d)_t + e_{i,t}, d in {S, L, A}
#            ("R_{i,t} is the excess return ... MKT_t is the excess return on the market
#            portfolio, from Ken French's data library") · "3-year rolling window, and moving
#            forward through the sample on a day-by-day basis" · "sort stocks into quintiles"
#            · "rebalanced monthly" · 헤지 = "long position in the portfolio containing assets
#            with the highest 20% loadings, and a short position in the portfolio containing
#            assets with the lowest 20% loadings" · VW(Table 6) / EW(Table 7)
#  초록      "stocks with high sensitivities to dynamic network risk earn lower returns"
#
# ===== 산출 형태 =============================================================
#   PORTFOLIO(Date, Ticker, Weight, Leg) — beta^NET(L) 5분위 가치가중 롱숏
#   long SUM w = +1 · short SUM w = -1 (논문 헤지 = 다리 각각 1배 총노출)
#   FIDELITY::portfolio_spec = {"construction":"engine_direct"}
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) ==
#   * 시그널일 d = 월말 거래일. 러너가 익월 첫 거래일에 집행하므로 d 는 t-1 이다.
#   * 모든 창은 우측정렬·종점 d — RV VAR 창 = date_all[(pd-749):pd] · beta 창 = (d-3y, d]
#     · ADV20 = shift(frollmean(.), 1L) (C10). NET(d) 일별 수익 = **직전 달 월말** 비중 x 당일
#     일중 수익 (비중 확정일 < 수익일).
#   * 논문의 QBLL 커널은 u 전후 관측에 가중하는 양측 커널 = 미래참조. PIT 상 후행 창으로 대체.
#   C1 : 전 표본 통계 0건(ridge lambda 도 창 안 GCV). 횡단면 통계(중앙값 주가·30/70·5분위)는
#        한 날짜 안.  C2/C3 : 없음.  C4 : 재무 미사용.  C5 : 오버레이 없음.  C6 : 날짜별
#        멤버십(ever-member 축소는 메모리용, 선택은 날짜별 멤버십).  C9 : 없음.  C10 : 위.
#   C11 : 매크로 미사용.  C13 : 부호 수동 반전 0건.  C14/C15 : Factor DB 미접근.
#   * 비선언 idiom 자체 감사: shift() 전부 양수 lag · shift(-N)/lead() 0건 · 수동 미래 인덱싱
#     0건 · 전표본 cov()/mean()/sd()/scale() 0건 · nafill/locf 0건 · 난수 0건.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(exists("BM_DT"))
.REQ <- c("Date", "Ticker", "Open", "High", "Low", "Close", "Vol", "Size", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("[2006.04639] RAWDATA 필수 컬럼 부재: %s",
               paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))

# ---------------------------------------------------------------------------
# 0. 상수 — 출처가 논문인 것과 우리가 정한 것을 분리 표기 (FIDELITY.json 과 1:1)
# ---------------------------------------------------------------------------
.P_LAG     <- 2L     # 논문: VAR lag order p = 2 (fn 11)
.H_TRUNC   <- 100L   # 논문: truncation horizon H = 100 (기준 칸)
.PCT_LO    <- 0.30   # 논문: 30th percentile (from)
.PCT_HI    <- 0.70   # 논문: 70th percentile (to)
.QUINT     <- 0.20   # 논문: quintile 정렬 = 상/하 20%
.BETA_YRS  <- 3L     # 논문: 3-year rolling window (달력 3년)
.C_SCALE   <- 100    # 논문: 식(6)(7) 의 100x

.WEEK_D    <- 5L     # 우리: "1 week" = 5거래일
.WC        <- pi / .WEEK_D   # 우리: 대역 경계 = pi/d (저자의 frequencyConnectedness 관행)
.VAR_WIN   <- 750L   # 우리: 후행 롤링 VAR 창(거래일) — 논문 양측 QBLL 커널의 PIT 대체
.N_NET_MAX <- 150L   # 우리: 네트워크 단면 상한 (t-1 ADV20 상위)
.N_NET_MIN <- 40L    # 우리: 네트워크 최소 단면
.PORT_MIN  <- 3L     # 우리: to/from 포트폴리오 최소 종목수
.MIN_SORT  <- 50L    # 우리: 5분위 정렬 최소 후보수
.BETA_MIN_OBS <- 504L  # 우리: beta 창 안 유효 관측 하한 (3년 창의 2/3)
.LIQ_MIN   <- 2e8    # 축: 20일 평균 거래대금 하한 (KRW)
.ADV_WIN   <- 20L    # 축: 유동성 창
.RV_FLOOR  <- 1e-8   # 우리: Parkinson 분산 바닥 (H==L 무거래/상하한가 방어)
.SIG_JIT   <- 1e-6   # 우리: 잔차공분산 대각 지터 배율
.PSI_CAP   <- 1e6    # 우리: VMA 발산 가드
.LAM_STEP  <- 6L     # 우리: 발산 시 lambda 격자 상향 폭
.LAM_TRY   <- 4L     # 우리: 재추정 최대 횟수

# ---------------------------------------------------------------------------
# 1. 작업 패널 — ever-member 로 축소(메모리 상한). 선택은 날짜별 멤버십이 가른다.
# ---------------------------------------------------------------------------
.RD <- RAWDATA[, .(Date, Ticker, Open, High, Low, Close, Vol, Size, K200, KQ150)]
if (!inherits(.RD$Date, "Date")) .RD[, Date := as.Date(Date)]
.evm <- unique(.RD[K200 %in% TRUE | KQ150 %in% TRUE, Ticker])
if (!length(.evm)) stop("[2006.04639] K200/KQ150 멤버 0종 — 멤버십 패널 확인")
.RD <- .RD[Ticker %in% .evm]
.RD <- unique(.RD, by = c("Ticker", "Date"))
setorder(.RD, Ticker, Date)

# 유동성 (t-1) — 당일 거래대금 제외 (C10). 20일 중 하루라도 결측이면 NA(자격 미달).
.RD[, .tv := Close * Vol]
.RD[, .adv := shift(frollmean(.tv, .ADV_WIN, align = "right"), 1L), by = Ticker]

# 논문 RV_t(5분 수익 제곱합의 제곱근 = 표준편차 척도) 의 대체 추정량:
#   Parkinson(1980) 일별 고저범위  sigma^2 = (log(H/L))^2 / (4 log 2)  ->  RV = sqrt(sigma^2)
.RD[, .rv := NA_real_]
.RD[is.finite(High) & is.finite(Low) & High > 0 & Low > 0 & High >= Low,
    .rv := sqrt(pmax((log(High / Low))^2 / (4 * log(2)), .RV_FLOOR))]

# 논문 R_t = SUM_{i}(p_{t,i} - p_{t,i-1}) = p_{t,D} - p_{t,0}  (텔레스코핑 = 일중 구간).
#   p = 로그가격으로 읽어 R_t = log(Close_t / Open_t). 시가/종가 = 그날 첫/마지막 가격.
#   Open 결측·0 인 날은 NA (값 대체 없음).
.RD[, .rid := NA_real_]
.RD[is.finite(Open) & Open > 0 & is.finite(Close) & Close > 0, .rid := log(Close / Open)]

.date_all <- sort(unique(.RD$Date))
.tick_all <- sort(unique(.RD$Ticker))
.nD <- length(.date_all); .nT <- length(.tick_all)
.di <- setNames(seq_len(.nD), as.character(.date_all))
.ti <- setNames(seq_len(.nT), .tick_all)

# 넓은 RV 행렬 (창 슬라이싱 전용 — 반복 join 회피)
.M_RV <- matrix(NA_real_, .nD, .nT)
.rvok <- .RD[is.finite(.rv)]
.M_RV[cbind(.di[as.character(.rvok$Date)], .ti[.rvok$Ticker])] <- .rvok$.rv
rm(.rvok); gc(verbose = FALSE)

# 월말 거래일 = 시그널일 (논문: monthly rebalancing) + 날짜 -> "직전 달 월말" 사상
#   ★이월 없음: 어떤 날 tau 의 NET(d) 비중은 tau 가 속한 달의 **직전 달 월말** 시그널에서만
#   온다. 그 달 네트워크가 미산출이면 tau 는 NET(d) 를 갖지 않는다(NA).
.mdt <- data.table(Date = .date_all)
.mdt[, ymk := format(Date, "%Y-%m")]
.SIGT <- .mdt[, .(Date = max(Date)), by = "ymk"]
setorder(.SIGT, Date)
.sig_all <- .SIGT$Date
.mdt[, ym_prev := format(as.Date(paste0(ymk, "-01")) - 1L, "%Y-%m")]
.mdt[, SigDate := .SIGT$Date[match(ym_prev, .SIGT$ymk)]]

# 자격 패널 (시그널일 한정) — 날짜별 멤버십 + 유동성 + 유한 가격/시총
.ELG <- .RD[Date %in% .sig_all & (K200 %in% TRUE | KQ150 %in% TRUE) &
              is.finite(.adv) & .adv >= .LIQ_MIN &
              is.finite(Close) & Close > 0 & is.finite(Size) & Size > 0,
            .(Date, Ticker, Close, Size, Adv = .adv)]
setkey(.ELG, Date)

# ---------------------------------------------------------------------------
# 2. 대역 가중 Toeplitz — 장기 대역 (0, wc] 적분을 해석적으로 계산
# ---------------------------------------------------------------------------
# 대역 (0, wc] 의 분자  I_jk = (1/pi) * INT_0^wc | SUM_h A_h[j,k] e^{-i w h} |^2 dw
#                            = (1/pi) * SUM_{h,m} C[h,m] A_h[j,k] A_m[j,k],
#   C[h,m] = INT_0^wc cos(w*(h-m)) dw = sin(wc*l)/l  (l = h-m != 0),  wc (l = 0).
# 전대역(wc = pi)이면 C = pi*I 라 I_jk = SUM_h A_h^2 — 시간영역 GFEVD 분자와 동일.
# 즉 장기 + 단기 = 전대역이 **정확히** 성립한다(구적 오차 없음).
.lmat <- outer(0:.H_TRUNC, 0:.H_TRUNC, "-")
.CMAT <- sin(.WC * .lmat) / .lmat
.CMAT[.lmat == 0L] <- .WC

# ---------------------------------------------------------------------------
# 3. 창 하나 -> 장기 대역 net-directional connectedness (식 4·6·7)
# ---------------------------------------------------------------------------
# 반환: 길이 N 의 NET_j = C_{j->.} - C_{j<-.}  (실패 시 NULL)
.net_long <- function(Y) {
  N <- ncol(Y); Tn <- nrow(Y)
  p <- .P_LAG
  Xl <- do.call(cbind, lapply(seq_len(p), function(h) Y[(p - h + 1L):(Tn - h), , drop = FALSE]))
  Yl <- Y[(p + 1L):Tn, , drop = FALSE]
  nn <- nrow(Xl)
  Xc <- sweep(Xl, 2L, colMeans(Xl), "-")
  Yc <- sweep(Yl, 2L, colMeans(Yl), "-")
  sv <- tryCatch(svd(Xc), error = function(e) NULL)
  if (is.null(sv) || !length(sv$d) || !all(is.finite(sv$d))) return(NULL)
  dv <- sv$d; d2 <- dv * dv
  UtY <- crossprod(sv$u, Yc)
  rowe <- rowSums(UtY * UtY)
  ssY <- sum(Yc * Yc); ssU <- sum(rowe)
  if (!is.finite(ssY) || ssY <= 0) return(NULL)

  # ridge lambda = 창 **안**의 GCV 최소점 (전 표본 최적화 아님 — 창마다 독립)
  lam_grid <- max(d2) * 10^seq(-8, 1, length.out = 30)
  gcv <- vapply(lam_grid, function(lv) {
    s <- d2 / (d2 + lv)
    rss <- sum((1 - s)^2 * rowe) + (ssY - ssU)
    dfl <- sum(s)
    if (dfl >= nn) return(Inf)
    (rss / nn) / (1 - dfl / nn)^2
  }, numeric(1))
  li <- which.min(gcv)
  if (!length(li) || !is.finite(gcv[li])) return(NULL)

  Amat <- NULL; den <- NULL; Sig <- NULL
  for (esc in seq_len(.LAM_TRY)) {
    lam <- lam_grid[min(li + (esc - 1L) * .LAM_STEP, length(lam_grid))]
    s <- d2 / (d2 + lam); dfl <- sum(s)
    Bc <- sv$v %*% ((dv / (d2 + lam)) * UtY)          # (p*N x N)
    E <- Yc - Xc %*% Bc
    S0 <- crossprod(E) / max(1, nn - dfl)
    dg <- diag(S0)
    if (!all(is.finite(dg)) || any(dg <= 0)) next
    S0 <- S0 + diag(N) * (.SIG_JIT * mean(dg))
    P1 <- t(Bc[1:N, , drop = FALSE])
    P2 <- t(Bc[(N + 1L):(2L * N), , drop = FALSE])
    if (!all(is.finite(P1)) || !all(is.finite(P2))) next

    # VMA 재귀 Psi_h = Phi_1 Psi_{h-1} + Phi_2 Psi_{h-2} + 발산 가드(실패 = lambda 상향 재추정)
    Am <- matrix(0, .H_TRUNC + 1L, N * N)
    dn <- numeric(N)
    Pp1 <- diag(N); Pp2 <- matrix(0, N, N)
    A0 <- Pp1 %*% S0
    Am[1L, ] <- as.vector(A0)
    dn <- dn + rowSums(A0 * Pp1)
    ok <- TRUE
    for (h in seq_len(.H_TRUNC)) {
      Ph <- P1 %*% Pp1 + P2 %*% Pp2
      if (!all(is.finite(Ph)) || max(abs(Ph)) > .PSI_CAP) { ok <- FALSE; break }
      Ah <- Ph %*% S0
      Am[h + 1L, ] <- as.vector(Ah)
      dn <- dn + rowSums(Ah * Ph)
      Pp2 <- Pp1; Pp1 <- Ph
    }
    if (!ok || any(!is.finite(dn)) || any(dn <= 0)) next
    Amat <- Am; den <- dn; Sig <- S0
    break
  }
  if (is.null(Amat)) return(NULL)

  tot_v <- colSums(Amat * Amat)                       # SUM_h A_h^2  (전대역 분자)
  lng_v <- colSums(Amat * (.CMAT %*% Amat)) / pi      # 장기 대역 분자
  lng_v <- pmin(pmax(lng_v, 0), tot_v)                # 수치 가드 (0 <= 장기 <= 전대역)
  Tm <- matrix(tot_v, N, N); Lm <- matrix(lng_v, N, N)
  sk <- diag(Sig)
  th_tot <- sweep(Tm, 2L, sk, "/") / den              # 열 k <- /sigma_kk, 행 j <- /den_j
  th_lng <- sweep(Lm, 2L, sk, "/") / den
  rn <- rowSums(th_tot)                               # 논문: SUM_k theta(u,inf)_{j,k} 로 정규화
  if (any(!is.finite(rn)) || any(rn <= 0)) return(NULL)
  thl <- th_lng / rn                                  # theta~(u,d)
  tot_norm <- sum(th_tot / rn)                        # SUM_{j,k} theta~(u,inf)_{j,k} (= N)
  if (!is.finite(tot_norm) || tot_norm <= 0) return(NULL)
  dl <- diag(thl)
  from_j <- .C_SCALE * (rowSums(thl) - dl) / tot_norm  # 식(6)
  to_j   <- .C_SCALE * (colSums(thl) - dl) / tot_norm  # 식(7)
  out <- to_j - from_j                                 # net-directional
  if (!all(is.finite(out))) return(NULL)
  out
}

# ---------------------------------------------------------------------------
# 4. 월별 네트워크 추정 -> NET(d) 팩터 구성 포트폴리오 4종 (§3.1.1 / v2 §4.1.1)
# ---------------------------------------------------------------------------
.sig_net <- .sig_all[.di[as.character(.sig_all)] >= .VAR_WIN]
.plist <- vector("list", length(.sig_net))
.nlog  <- rep("ok", length(.sig_net))

for (.k in seq_along(.sig_net)) {
  d <- .sig_net[.k]
  pd <- .di[as.character(d)]
  wr <- (pd - .VAR_WIN + 1L):pd
  eg <- .ELG[.(d), nomatch = 0L]
  if (nrow(eg) < .N_NET_MIN) { .nlog[.k] <- "skip_universe"; next }
  ci <- .ti[eg$Ticker]
  sub <- .M_RV[wr, ci, drop = FALSE]
  full <- which(colSums(is.na(sub)) == 0L)            # 창 전구간 관측 요건 (균형 패널)
  if (length(full) < .N_NET_MIN) { .nlog[.k] <- "skip_coverage"; next }
  eg <- eg[full]; sub <- sub[, full, drop = FALSE]
  if (nrow(eg) > .N_NET_MAX) {                        # 상한 초과 시 t-1 ADV20 상위
    # ★eg 행 순서와 sub 열 순서는 항상 같은 색인으로 함께 움직여야 한다.
    ord <- order(-eg$Adv)[seq_len(.N_NET_MAX)]
    eg <- eg[ord]; sub <- sub[, ord, drop = FALSE]
  }
  nv <- .net_long(sub)
  if (is.null(nv) || length(nv) != nrow(eg)) { .nlog[.k] <- "skip_var"; next }

  eg[, NETj := nv]
  # 논문: 그날 중앙값 주가로 small/big 분할 (중앙값은 네트워크 단면 안에서 계산 — FIDELITY 신고)
  #   -> 각 그룹 안에서 net-directional 30/70 조건부 정렬 -> 가치가중 to/from
  pmed <- median(eg$Close)
  eg[, SzGrp := ifelse(Close < pmed, "small", "big")]
  rows <- lapply(c("small", "big"), function(g) {
    gg <- eg[SzGrp == g]
    if (nrow(gg) < 2L * .PORT_MIN) return(NULL)
    nq <- as.numeric(gg$NETj)
    qlo <- as.numeric(stats::quantile(nq, .PCT_LO, names = FALSE, type = 7))
    qhi <- as.numeric(stats::quantile(nq, .PCT_HI, names = FALSE, type = 7))
    hi <- gg[NETj > qhi]; lo <- gg[NETj < qlo]
    if (nrow(hi) < .PORT_MIN || nrow(lo) < .PORT_MIN) return(NULL)
    rbind(
      data.table(Date = d, Ticker = hi$Ticker, PortID = paste0("to_", g),
                 W = hi$Size / sum(hi$Size)),
      data.table(Date = d, Ticker = lo$Ticker, PortID = paste0("from_", g),
                 W = lo$Size / sum(lo$Size)))
  })
  rows <- Filter(Negate(is.null), rows)
  if (length(rows) < 2L) { .nlog[.k] <- "skip_ports"; next }   # small/big 둘 다 서야 스프레드
  .plist[[.k]] <- rbindlist(rows, use.names = TRUE)
}

.NETW <- rbindlist(Filter(Negate(is.null), .plist), use.names = TRUE)
cat(sprintf("[2006.04639] 네트워크 월 %d: ok %d · skip universe %d · coverage %d · var %d · ports %d (skip 달 = NET(d) 부재, 이월 없음)\n",
            length(.sig_net), sum(.nlog == "ok"), sum(.nlog == "skip_universe"),
            sum(.nlog == "skip_coverage"), sum(.nlog == "skip_var"), sum(.nlog == "skip_ports")))
if (!nrow(.NETW)) stop("[2006.04639] NET(d) 구성 포트폴리오 0건 — 창/유니버스 확인")
rm(.plist, .M_RV); gc(verbose = FALSE)

# ---------------------------------------------------------------------------
# 5. NET(d) 일별 팩터 수익 — 비중은 직전 달 월말 d, 수익은 그 다음 달의 일중 수익 (PIT)
# ---------------------------------------------------------------------------
.dmap <- .mdt[!is.na(SigDate), .(Date, SigDate)]
.RET <- .RD[is.finite(.rid), .(Date, Ticker, R = .rid)]     # 논문 R_t (일중 로그수익)
rm(.RD); gc(verbose = FALSE)
.HOLD <- merge(.dmap, .NETW, by.x = "SigDate", by.y = "Date", allow.cartesian = TRUE)
.HOLD <- merge(.HOLD, .RET, by = c("Date", "Ticker"))
# 그날 수익이 없는 종목(상폐·거래정지·시가 결측)은 비중에서 빠지고 잔여 비중으로 재정규화
.PR <- .HOLD[, .(r = sum(W * R) / sum(W)), by = .(Date, PortID)]
rm(.HOLD); gc(verbose = FALSE)

.PWID <- dcast(.PR, Date ~ PortID, value.var = "r")
.need <- c("from_small", "to_small", "from_big", "to_big")
if (!all(.need %in% names(.PWID)))
  stop("[2006.04639] NET(d) 4포트폴리오 미완성: ", paste(setdiff(.need, names(.PWID)), collapse = ", "))
.PWID <- .PWID[, c("Date", .need), with = FALSE]
.PWID <- .PWID[complete.cases(.PWID)]
# 논문 식(8)/(16)
.PWID[, NETF := (from_small + to_small) / 2 - (from_big + to_big) / 2]
.NETF <- .PWID[is.finite(NETF), .(Date, NETF)]
if (nrow(.NETF) < .BETA_MIN_OBS + 20L)
  stop(sprintf("[2006.04639] NET(d) 일별 시계열 %d일 — 3년 베타 창 불가", nrow(.NETF)))
.span <- .date_all[.date_all >= min(.NETF$Date) & .date_all <= max(.NETF$Date)]
cat(sprintf("[2006.04639] NET(d) 일별 %d일 (%s ~ %s) · 구간 내 부재일 %d (실패월·미완성일 = NA, 이월 없음)\n",
            nrow(.NETF), min(.NETF$Date), max(.NETF$Date), sum(!(.span %in% .NETF$Date))))

# ---------------------------------------------------------------------------
# 6. 3년 롤링 beta — R_i = b0 + bMKT*MKT + bNET*NET(d) + e  (식 17 · 통제는 시장 하나)
#    창 = 달력 (d - 3y, d] 안의 유효 관측 (R_i·MKT·NET(d) 모두 유한) · 하한 .BETA_MIN_OBS
# ---------------------------------------------------------------------------
# ★파생 사본에서만 := 한다 — 호출자의 BM_DT 를 참조로 바꾸지 않기 위해 copy().
.BM <- copy(as.data.table(BM_DT))
if (!inherits(.BM$Date, "Date")) .BM[, Date := as.Date(Date)]
.BM <- .BM[is.finite(BM_Ret), .(Date, MKT = BM_Ret)]

.BP <- merge(.RET, .BM, by = "Date")
.BP <- merge(.BP, .NETF, by = "Date")
.BP <- .BP[is.finite(R) & is.finite(MKT) & is.finite(NETF)]
setorder(.BP, Ticker, Date)
rm(.RET); gc(verbose = FALSE)

# 종목별 누적합 -> 창 합 = 누적합 차분 (창 = (d-3y, d], 우측 종점 = 시그널일)
.BP[, `:=`(
  c_m  = cumsum(MKT),        c_f  = cumsum(NETF),        c_r  = cumsum(R),
  c_mm = cumsum(MKT * MKT),  c_ff = cumsum(NETF * NETF), c_mf = cumsum(MKT * NETF),
  c_mr = cumsum(MKT * R),    c_fr = cumsum(NETF * R)
), by = Ticker]

.minus_years <- function(d, k) {
  y <- as.integer(format(d, "%Y")) - as.integer(k)
  out <- as.Date(paste0(y, format(d, "-%m-%d")), format = "%Y-%m-%d")
  bad <- is.na(out)
  if (any(bad)) out[bad] <- as.Date(paste0(y[bad], "-02-28"))
  out
}
.sig_hi <- as.numeric(.sig_all)
.sig_lo <- as.numeric(.minus_years(.sig_all, .BETA_YRS))

.BETA <- .BP[, {
  dn <- as.numeric(Date)
  hi <- findInterval(.sig_hi, dn)          # 행 수 with Date <= d
  lo <- findInterval(.sig_lo, dn)          # 행 수 with Date <= d - 3y
  nn <- hi - lo                            # 창 (d-3y, d] 안의 유효 관측 수
  ok <- which(nn >= .BETA_MIN_OBS)
  if (length(ok)) {
    h <- hi[ok] + 1L; l <- lo[ok] + 1L
    g <- function(v) { cv <- c(0, v); cv[h] - cv[l] }
    list(Date = .sig_all[ok], n = nn[ok],
         s_m = g(c_m), s_f = g(c_f), s_r = g(c_r),
         s_mm = g(c_mm), s_ff = g(c_ff), s_mf = g(c_mf),
         s_mr = g(c_mr), s_fr = g(c_fr))
  } else NULL
}, by = Ticker]
rm(.BP); gc(verbose = FALSE)
if (!nrow(.BETA)) stop("[2006.04639] beta 창 요건(유효 관측 >= .BETA_MIN_OBS)을 만족하는 종목-월 0건")

# 2회귀자 OLS(절편 포함) 정규방정식의 닫힌 해
.BETA[, xmm := s_mm - s_m * s_m / n]
.BETA[, xff := s_ff - s_f * s_f / n]
.BETA[, xmf := s_mf - s_m * s_f / n]
.BETA[, ymr := s_mr - s_m * s_r / n]
.BETA[, yfr := s_fr - s_f * s_r / n]
.BETA[, dtm := xmm * xff - xmf * xmf]
.BETA[, BetaNet := NA_real_]
# 공선성 가드: det 를 xmm*xff 대비 상대 하한으로 판정
.BETA[is.finite(dtm) & xmm > 0 & xff > 0 & dtm > 1e-10 * xmm * xff,
      BetaNet := (xmm * yfr - xmf * ymr) / dtm]
.SIG <- .BETA[is.finite(BetaNet), .(Date, Ticker, BetaNet)]
rm(.BETA); gc(verbose = FALSE)

# ---------------------------------------------------------------------------
# 7. 5분위 정렬 -> PORTFOLIO (월간 · 가치가중 · 롱숏) — §5.2 그대로
#    헤지 = 최고 20% 로딩 롱 / 최저 20% 로딩 숏 (논문이 이 스프레드를 음(-)으로 보고한다)
# ---------------------------------------------------------------------------
.SIG <- merge(.SIG, .ELG[, .(Date, Ticker, Size)], by = c("Date", "Ticker"))
.SIG <- .SIG[is.finite(Size) & Size > 0]
if (!nrow(.SIG)) stop("[2006.04639] 베타 정렬 후보 0건")

.mk_leg <- function(md) {
  n <- nrow(md)
  if (n < .MIN_SORT) return(NULL)
  kq <- as.integer(floor(n * .QUINT))
  if (kq < 2L) return(NULL)
  setorder(md, BetaNet)
  lo <- md[1:kq]                       # 최저 20% beta^NET  = 숏 (논문)
  hi <- md[(n - kq + 1L):n]            # 최고 20% beta^NET  = 롱 (논문)
  rbind(
    data.table(Date = md$Date[1], Ticker = hi$Ticker,
               Weight = hi$Size / sum(hi$Size), Leg = "long"),
    data.table(Date = md$Date[1], Ticker = lo$Ticker,
               Weight = -lo$Size / sum(lo$Size), Leg = "short"))
}

PORTFOLIO <- rbindlist(
  Filter(Negate(is.null), lapply(split(.SIG, by = "Date"), .mk_leg)),
  use.names = TRUE)
if (!nrow(PORTFOLIO)) stop("[2006.04639] PORTFOLIO 0행 — 최소 후보수 요건 확인")
setorder(PORTFOLIO, Date, Leg, Ticker)
PORTFOLIO <- PORTFOLIO[is.finite(Weight) & Weight != 0]

cat(sprintf("[2006.04639] PORTFOLIO %d행 · %s ~ %s · 리밸 %d회 · 최대보유 %d종 · 다리 = 고beta 롱 / 저beta 숏 (논문 §5.2)\n",
            nrow(PORTFOLIO), min(PORTFOLIO$Date), max(PORTFOLIO$Date),
            uniqueN(PORTFOLIO$Date), max(PORTFOLIO[, .N, by = Date]$N)))
