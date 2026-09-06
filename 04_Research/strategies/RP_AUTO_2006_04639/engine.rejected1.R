# =============================================================================
# engine.R — RP_AUTO_2006_04639
# "Dynamic Network Risk"  (Barunik & Ellington, arXiv:2006.04639, v2 2020-07-11)
#   원문: arxiv.org/html/2006.04639v2
#
# ★fidelity = ADAPTED.  **선언 정본 = FIDELITY.json** (이 주석은 사본이다)
#
# ===== 논문 원문 인용 (그대로 옮긴 것) =======================================
#  §데이터  "we compute daily returns Rt=SUM(pt,i - pt,i-1) and realized volatility
#            RVt=sqrt(SUM (pt,i - pt,i-1)^2) for each stock on day t"  (5분 간격)
#  §VAR     lag order p = 2 · truncation horizon H = 100 (robustness H in {50,100,200})
#  §대역    "short-term as the 1-day to 1-week horizon and long-term as horizons
#            greater than 1-week"
#  §정규화  인접행렬은 "SUM_{k=1..N} [theta(u,inf)]_{j,k}" 로 row-normalize
#  §NET_j   "the difference between to connectedness and from connectedness
#            C(u,d)_{j->.} - C(u,d)_{j<-.}"
#  §4.1.1   "each day we sort S&P500 stocks above and below the day's median price
#            level and define these as small and big stocks. Then, conditional on
#            size, we sort on horizon specific net-directional connectedness and
#            create value-weighted to and from portfolios. These portfolios admit
#            stocks above (below) the 70th (30th) percentile of each respective
#            day's horizon specific net-directional connectedness distribution.
#            We characterize these portfolios as to and from portfolios. We then
#            take an average of the to and from portfolios and then a long-short
#            position in the respective small and big portfolios."
#           식(16) NET(d)_t = (from_small+to_small)/2 - (from_big+to_big)/2
#  §베타    R_{i,t} = b0_i + bMKT_i*MKT_t + bNET(d)_i*NET(d)_t + e_{i,t}
#           "3-year rolling regressions" · 통제는 시장 프리미엄 하나뿐
#  §정렬    "sort stocks into quintiles based on daily realized horizon specific
#            network risk betas" · "Portfolios are rebalanced monthly"
#           헤지 = "long position in the portfolio containing assets with the
#            highest 20% loadings, and a short position in the portfolio
#            containing assets with the lowest 20%"
#  §초록    "Stocks with high sensitivities to dynamic network risk earn lower
#            returns ... A one-standard deviation increase in long-term
#            (short-term) network risk loadings associate with a 7.66% (6.71%)
#            drop in annualised expected returns."
#
# ===== 바꾼 것 (전문 = FIDELITY.json::changed. 여기 없는 변경은 없다) =========
#  (1) RV 원천: 5분 일중 RV -> 일별 고저범위 Parkinson(1980). 일중 패널 미보유.
#  (2) 네트워크 추정기: QBLL TVP-VAR -> 750거래일 롤링 ridge-VAR(GCV lambda),
#      월별 재추정. 원 추정기는 N=496 일별로 본 하네스에서 실행 불가.
#  (3) 네트워크 단면 상한 150종(신호일 t-1 ADV20 상위).  (4) 일별 정렬 -> 월별.
#  (5) 유니버스 K200 U KQ150 + adv20 >= 2e8 (t-1).       (6) MKT = KOSPI200(무위험 미차감).
#  (7) 대역 = 장기(주 초과) 하나.  (8) 가치가중 판.       (9) 헤지 다리 방향 = 저베타 롱.
#  (10) 수치·커버리지 가드(전수 열거 = FIDELITY.json::changed) ·
#  (11) 3년 = 종목별 756 유효관측 · (12) H=100 칸 · (13) 1주 = 5거래일.
#
# ===== 산출 형태 =============================================================
#   PORTFOLIO(Date, Ticker, Weight, Leg) — 롱숏 5분위 가치가중.
#   FIDELITY::portfolio_spec = {"construction":"engine_direct"}.
#   long SUM w = +1 · short SUM w = -1 (논문 헤지 = 다리 각각 1배 총노출).
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) ==
#   * 시그널일 d = 월말 거래일. 하네스가 d+1 에 집행하므로 d 는 t-1 이다.
#   * 모든 창은 **우측정렬 · 종점 d**. 미래 인덱싱 0건.
#       - RV VAR 창 = date_all[(pd-749):pd]        (pd = d 의 위치)
#       - 베타 창   = 종목별 직전 756 유효관측 (frollsum align="right")
#       - ADV20     = shift(frollmean(...), 1L)    (C10 — 당일 거래대금 제외)
#   * NET(d) 팩터 일별 수익: 비중은 신호일 d 에서 확정되고 수익은 **d 초과** 날에만
#     귀속된다(findInterval(tau - 0.5, ...) 로 strict less-than). 동월 누출 불가.
#   C1  : 전 표본 통계 0건. 모든 평균·분산·공분산은 [pd-749, pd] 창 안에서만.
#         횡단면 통계(중앙값 주가·30/70 백분위·5분위)는 **한 날짜 안**이라 PIT 무해.
#   C2  : same-day 순환참조 없음.       C3 : 같은 기간 집계->적용 없음.
#   C4  : 재무 패널 미사용(신호가 가격·거래량뿐).   C11 : 매크로 미사용.
#   C5  : 오버레이 없음(총노출 스케일러·레짐 스위치 0건).
#   C6  : 유니버스 = 날짜별 K200/KQ150 멤버십(PIT 시변). ever-member 축소는 메모리
#         상한용이고 선택은 전부 날짜별 멤버십이 가른다 — 출력 동일.
#   C9  : DD/VT 미사용.                 C10: 위 ADV20 참조.
#   C13 : 부호 수동 반전 0건. 롱 다리는 **최저 20% 베타 분위를 고르는 것**이지
#         베타에 -1 을 곱하는 것이 아니다. 방향의 출처는 논문 초록 문장 하나
#         ("high sensitivities ... earn lower returns") 이고 FIDELITY 에 신고돼 있다.
#   C14/C15 : Factor DB 미접근(RAWDATA 가격·거래량·시총·멤버십만).
#   * 비선언 idiom 자체 감사: shift() 는 전부 양수 lag · shift(-N)/lead() 0건 ·
#     수동 미래 인덱싱 0건 · 전표본 cov()/mean()/sd()/scale() 0건 · nafill/locf 0건 ·
#     미래수익 정렬 0건 · 파라미터 전표본 최적화 0건(ridge lambda 는 **창 안** GCV).
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(exists("BM_DT"))
.REQ <- c("Date", "Ticker", "High", "Low", "Close", "Vol", "Size", "Ret", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("[2006.04639] RAWDATA 필수 컬럼 부재: %s",
               paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))

# ---------------------------------------------------------------------------
# 0. 상수 — 출처가 논문인 것과 우리가 정한 것을 분리 표기 (FIDELITY 와 1:1)
# ---------------------------------------------------------------------------
.P_LAG     <- 2L     # 논문: VAR lag order p = 2
.H_TRUNC   <- 100L   # 논문: truncation horizon H = 100 (기준 칸)
.WEEK_D    <- 5L     # 논문 "1 week" 의 거래일 이산화 (KRX 주 5거래일)
.BETA_WIN  <- 756L   # 논문: 3-year rolling (252*3 거래일 관측)
.PCT_LO    <- 0.30   # 논문: 30th percentile
.PCT_HI    <- 0.70   # 논문: 70th percentile
.QUINT     <- 0.20   # 논문: quintile 정렬 = 상/하 20%

.VAR_WIN   <- 750L   # 우리: 롤링 VAR 창(거래일). 논문 QBLL 커널의 대체
.N_NET_MAX <- 150L   # 우리: 네트워크 단면 상한 (k=2N+1=301 vs T=748)
.N_NET_MIN <- 40L    # 우리: 네트워크 최소 단면
.PORT_MIN  <- 3L     # 우리: to/from 포트폴리오 최소 종목수
.MIN_SORT  <- 50L    # 우리: 5분위 정렬 최소 후보수
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
.RD <- RAWDATA[, .(Date, Ticker, High, Low, Close, Vol, Size, Ret, K200, KQ150)]
if (!inherits(.RD$Date, "Date")) .RD[, Date := as.Date(Date)]
.evm <- unique(.RD[K200 %in% TRUE | KQ150 %in% TRUE, Ticker])
if (!length(.evm)) stop("[2006.04639] K200/KQ150 멤버 0종 — 멤버십 패널 확인")
.RD <- .RD[Ticker %in% .evm]
setorder(.RD, Ticker, Date)

# 유동성 (t-1) — 당일 거래대금 제외 (C10)
.RD[, .tv := Close * Vol]
.RD[, .adv := shift(frollmean(.tv, .ADV_WIN, align = "right"), 1L), by = Ticker]

# Parkinson(1980) 일별 범위 변동성 = 논문 RV 의 대체 추정량
#   sigma^2 = (log(H/L))^2 / (4 log 2)   ->  RV = sqrt(sigma^2)
.RD[, .rv := NA_real_]
.RD[is.finite(High) & is.finite(Low) & High > 0 & Low > 0 & High >= Low,
    .rv := sqrt(pmax((log(High / Low))^2 / (4 * log(2)), .RV_FLOOR))]

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

# 월말 거래일 = 시그널일 (논문: monthly rebalancing)
.mdt <- data.table(Date = .date_all)
.mdt[, ymk := format(Date, "%Y-%m")]
.sig_all <- .mdt[, .(Date = max(Date)), by = "ymk"]$Date
.sig_all <- sort(.sig_all)

# 자격 패널 (시그널일 한정) — 날짜별 멤버십 + 유동성 + 유한 가격/시총
.ELG <- .RD[Date %in% .sig_all & (K200 %in% TRUE | KQ150 %in% TRUE) &
              is.finite(.adv) & .adv >= .LIQ_MIN &
              is.finite(Close) & Close > 0 & is.finite(Size) & Size > 0,
            .(Date, Ticker, Close, Size, Adv = .adv)]
setkey(.ELG, Date)

# ---------------------------------------------------------------------------
# 2. 대역 가중 Toeplitz — 장기 대역(주기 > 5거래일) 적분을 해석적으로 계산
# ---------------------------------------------------------------------------
# BK(2018) 주파수 분해에서 대역 (0, wc] 의 분자는
#   I_jk = (1/pi) * INT_0^wc | SUM_h A_h[j,k] e^{-i w h} |^2 dw
#        = (1/pi) * SUM_{h,m} C[h,m] A_h[j,k] A_m[j,k],
#   C[h,m] = INT_0^wc cos(w*(h-m)) dw = sin(wc*l)/l  (l = h-m != 0),  wc (l = 0).
# 전대역(wc = pi)이면 C = pi*I 라 I_jk = SUM_h A_h^2 — 시간영역 GFEVD 분자와 동일.
# 즉 장기 + 단기 = 전대역이 **정확히** 성립한다(구적 오차 없음).
.wc <- 2 * pi / .WEEK_D
.lmat <- outer(0:.H_TRUNC, 0:.H_TRUNC, "-")
.CMAT <- ifelse(.lmat == 0L, .wc, sin(.wc * .lmat) / .lmat)
.CMAT[.lmat == 0L] <- .wc

# ---------------------------------------------------------------------------
# 3. 창 하나 -> 장기 대역 net-directional connectedness
# ---------------------------------------------------------------------------
# 반환: 길이 N 의 NET_j = TO_j - FROM_j  (실패 시 NULL)
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

    # VMA 재귀 + 발산 가드 (안정성 실패 = lambda 상향 재추정)
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

  tot_v <- colSums(Amat * Amat)                       # SUM_h A_h^2
  lng_v <- colSums(Amat * (.CMAT %*% Amat)) / pi      # 장기 대역 분자
  lng_v <- pmin(pmax(lng_v, 0), tot_v)                # 수치 가드 (0 <= 장기 <= 전대역)
  Tm <- matrix(tot_v, N, N); Lm <- matrix(lng_v, N, N)
  sk <- diag(Sig)
  th_tot <- sweep(Tm, 2L, sk, "/") / den              # 열 k <- /sigma_kk, 행 j <- /den_j
  th_lng <- sweep(Lm, 2L, sk, "/") / den
  rn <- rowSums(th_tot)                               # 논문: theta(u,inf) 행합으로 정규화
  if (any(!is.finite(rn)) || any(rn <= 0)) return(NULL)
  thl <- th_lng / rn
  dl <- diag(thl)
  from_j <- rowSums(thl) - dl
  to_j   <- colSums(thl) - dl
  out <- to_j - from_j
  if (!all(is.finite(out))) return(NULL)
  out
}

# ---------------------------------------------------------------------------
# 4. 월별 네트워크 추정 -> NET(d) 팩터 구성 포트폴리오 4종
# ---------------------------------------------------------------------------
.sig_net <- .sig_all[.di[as.character(.sig_all)] >= .VAR_WIN]
.plist <- vector("list", length(.sig_net))

for (.k in seq_along(.sig_net)) {
  d <- .sig_net[.k]
  pd <- .di[as.character(d)]
  wr <- (pd - .VAR_WIN + 1L):pd
  eg <- .ELG[.(d), nomatch = 0L]
  if (nrow(eg) < .N_NET_MIN) next
  ci <- .ti[eg$Ticker]
  sub <- .M_RV[wr, ci, drop = FALSE]
  full <- which(colSums(is.na(sub)) == 0L)            # 창 전구간 관측 요건
  if (length(full) < .N_NET_MIN) next
  eg <- eg[full]; sub <- sub[, full, drop = FALSE]
  if (nrow(eg) > .N_NET_MAX) {                        # 상한 초과 시 t-1 ADV20 상위
    # ★eg 행 순서와 sub 열 순서는 항상 같은 색인으로 함께 움직여야 한다
    #   (setorder 로 eg 만 재정렬하면 NET_j 가 다른 종목에 붙는다).
    ord <- order(-eg$Adv)[seq_len(.N_NET_MAX)]
    eg <- eg[ord]; sub <- sub[, ord, drop = FALSE]
  }
  nv <- .net_long(sub)
  if (is.null(nv) || length(nv) != nrow(eg)) next

  eg[, NETj := nv]
  # 논문 §4.1.1: 그날 중앙값 주가로 small/big 분할 -> 각 그룹 안에서 30/70 조건부 정렬
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
  if (length(rows) < 2L) next                          # small/big 둘 다 서야 스프레드
  .plist[[.k]] <- rbindlist(rows, use.names = TRUE)
}

.NETW <- rbindlist(Filter(Negate(is.null), .plist), use.names = TRUE)
if (!nrow(.NETW)) stop("[2006.04639] NET(d) 구성 포트폴리오 0건 — 창/유니버스 확인")
rm(.plist, .M_RV); gc(verbose = FALSE)

# ---------------------------------------------------------------------------
# 5. NET(d) 일별 팩터 수익 — 비중은 신호일 d, 수익은 d **초과** 날에만 (PIT)
# ---------------------------------------------------------------------------
.sv <- sort(unique(.NETW$Date))
.dmap <- data.table(Date = .date_all)
.dmap[, si_idx := findInterval(as.numeric(Date) - 0.5, as.numeric(.sv))]
.dmap <- .dmap[si_idx > 0L]
.dmap[, SigDate := .sv[si_idx]]
.dmap[, si_idx := NULL]

.RET <- .RD[is.finite(Ret), .(Date, Ticker, Ret)]
rm(.RD); gc(verbose = FALSE)
.HOLD <- merge(.dmap, .NETW, by.x = "SigDate", by.y = "Date", allow.cartesian = TRUE)
.HOLD <- merge(.HOLD, .RET, by = c("Date", "Ticker"))
# 결측 수익(상폐·거래정지) 종목은 그날 비중에서 빠지므로 잔여 비중으로 재정규화
.PR <- .HOLD[, .(r = sum(W * Ret) / sum(W)), by = .(Date, PortID)]
rm(.HOLD); gc(verbose = FALSE)

.PWID <- dcast(.PR, Date ~ PortID, value.var = "r")
.need <- c("from_small", "to_small", "from_big", "to_big")
if (!all(.need %in% names(.PWID)))
  stop("[2006.04639] NET(d) 4포트폴리오 미완성: ", paste(setdiff(.need, names(.PWID)), collapse = ", "))
.PWID <- .PWID[, c("Date", .need), with = FALSE]
.PWID <- .PWID[complete.cases(.PWID)]
# 논문 식(16)
.PWID[, NETF := (from_small + to_small) / 2 - (from_big + to_big) / 2]
.NETF <- .PWID[is.finite(NETF), .(Date, NETF)]
if (nrow(.NETF) < .BETA_WIN + 20L)
  stop(sprintf("[2006.04639] NET(d) 일별 시계열 %d일 — 3년 베타 창 불가", nrow(.NETF)))

# ---------------------------------------------------------------------------
# 6. 3년 롤링 베타 — R_i = b0 + bMKT*MKT + bNET*NET(d) + e  (통제는 시장 하나)
# ---------------------------------------------------------------------------
# ★파생 사본에서만 := 한다 — as.data.table 은 이미 data.table 이면 같은 객체를 돌려주므로
#   호출자의 BM_DT 를 참조로 바꿔버릴 수 있다.
.BM <- as.data.table(BM_DT)[is.finite(BM_Ret), .(Date, MKT = BM_Ret)]
if (!inherits(.BM$Date, "Date")) .BM[, Date := as.Date(Date)]

.BP <- merge(.RET, .BM, by = "Date")
.BP <- merge(.BP, .NETF, by = "Date")
.BP <- .BP[is.finite(Ret) & is.finite(MKT) & is.finite(NETF)]
setorder(.BP, Ticker, Date)
rm(.RET); gc(verbose = FALSE)

.K <- .BETA_WIN
.BP[, `:=`(
  s_m  = frollsum(MKT, .K, align = "right"),
  s_f  = frollsum(NETF, .K, align = "right"),
  s_r  = frollsum(Ret, .K, align = "right"),
  s_mm = frollsum(MKT * MKT, .K, align = "right"),
  s_ff = frollsum(NETF * NETF, .K, align = "right"),
  s_mf = frollsum(MKT * NETF, .K, align = "right"),
  s_mr = frollsum(MKT * Ret, .K, align = "right"),
  s_fr = frollsum(NETF * Ret, .K, align = "right")
), by = Ticker]

# 2회귀자 OLS 정규방정식의 닫힌 해 (창 = 직전 756 유효관측, 종점 = 신호일)
.BP[, xmm := s_mm - s_m * s_m / .K]
.BP[, xff := s_ff - s_f * s_f / .K]
.BP[, xmf := s_mf - s_m * s_f / .K]
.BP[, ymr := s_mr - s_m * s_r / .K]
.BP[, yfr := s_fr - s_f * s_r / .K]
.BP[, c("s_m", "s_f", "s_r", "s_mm", "s_ff", "s_mf", "s_mr", "s_fr") := NULL]
.BP[, dtm := xmm * xff - xmf * xmf]
.BP[, BetaNet := NA_real_]
# 공선성 가드: det 를 절대값이 아니라 xmm*xff 대비 상대 하한으로 판정
.BP[is.finite(dtm) & xmm > 0 & xff > 0 & dtm > 1e-10 * xmm * xff,
    BetaNet := (xmm * yfr - xmf * ymr) / dtm]

.SIG <- .BP[Date %in% .sig_all & is.finite(BetaNet), .(Date, Ticker, BetaNet)]
rm(.BP); gc(verbose = FALSE)

# ---------------------------------------------------------------------------
# 7. 5분위 정렬 -> PORTFOLIO (월간 · 가치가중 · 롱숏)
# ---------------------------------------------------------------------------
# 논문 헤지는 "최고 20% 로딩 롱 / 최저 20% 숏" 이고, 논문이 보고하는 그 스프레드의
# 부호는 **음(-)** 이다("high sensitivities ... earn lower returns", 장기 로딩 1sd
# 증가 = 기대수익 -7.66%/년). 여기서는 같은 5분위 정렬을 그대로 쓰되 매매 가능한
# 다리, 즉 **최저 20% 롱 / 최고 20% 숏** 으로 낸다. 정렬·분위·가중은 논문 그대로이고
# 다리 방향만 논문이 진술한 부호를 따른다 (FIDELITY::changed 에 신고).
.SIG <- merge(.SIG, .ELG[, .(Date, Ticker, Size)], by = c("Date", "Ticker"))
.SIG <- .SIG[is.finite(Size) & Size > 0]
if (!nrow(.SIG)) stop("[2006.04639] 베타 정렬 후보 0건")

.mk_leg <- function(md) {
  n <- nrow(md)
  if (n < .MIN_SORT) return(NULL)
  kq <- as.integer(floor(n * .QUINT))
  if (kq < 2L) return(NULL)
  setorder(md, BetaNet)
  lo <- md[1:kq]                       # 최저 20% 베타 = 롱
  hi <- md[(n - kq + 1L):n]            # 최고 20% 베타 = 숏
  rbind(
    data.table(Date = md$Date[1], Ticker = lo$Ticker,
               Weight = lo$Size / sum(lo$Size), Leg = "long"),
    data.table(Date = md$Date[1], Ticker = hi$Ticker,
               Weight = -hi$Size / sum(hi$Size), Leg = "short"))
}

PORTFOLIO <- rbindlist(
  Filter(Negate(is.null), lapply(split(.SIG, by = "Date"), .mk_leg)),
  use.names = TRUE)
if (!nrow(PORTFOLIO)) stop("[2006.04639] PORTFOLIO 0행 — 최소 후보수 요건 확인")
setorder(PORTFOLIO, Date, Leg, Ticker)
PORTFOLIO <- PORTFOLIO[is.finite(Weight) & Weight != 0]

cat(sprintf("[2006.04639] PORTFOLIO %d행 · %s ~ %s · 리밸 %d회 · 최대보유 %d종\n",
            nrow(PORTFOLIO), min(PORTFOLIO$Date), max(PORTFOLIO$Date),
            uniqueN(PORTFOLIO$Date), max(PORTFOLIO[, .N, by = Date]$N)))
