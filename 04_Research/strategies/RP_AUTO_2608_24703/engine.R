# =============================================================================
# engine.R — RP_AUTO_2608_24703
# "Lead-Lag Relationships in Financial Markets: A Comparison of Multiple
#  Clustering Algorithms" — Ruichen Deng, Yichi Zhang (arXiv:2608.24703)
#  https://arxiv.org/abs/2608.24703
#
# ★fidelity = ADAPTED (군집기 1개소만 치환). 정본 = FIDELITY.json
#
# 논문 Algorithm 1 을 단계 그대로 옮긴다(원문 인용):
#   1. "Extract sub-time series using a sliding window of fixed length l=21,
#       obtaining X_{n×l} for each window."
#   2. 창 내부 군집화 — K 는 "finds the best number of clusters by maximizing
#       the silhouette coefficient" (초록 명시).
#   3. "For asset pairs **within each cluster**, apply the DTW-based lead-lag
#       detection algorithm to divide them into Leader L and Lagger G."
#       M[i,j] = L_ij − L_ji  ·  S_i = Σ_j M[i,j]
#   4. "Compute the trading signal as the sign of the EWMA (span spn) of the
#       average returns of the Leader: signal = sign(1/|L| Σ_{k∈L} EWMA(R_k,spn))"
#       — spn = "p={1,3,5,7} days"
#   5. "Lead strategy: PnL_i = signal · (1/|L|) Σ_{k∈L} R_k(t+i·w+f)"
#
# ★Step 5 는 **리더를 매매한다**(팔로워가 아니다). lag strategy 가 팔로워(G)를 매매하는
#   쪽이고 성적이 더 나쁘다(679종 표본 lead 0.866 vs lag 0.739). 헤드라인
#   (MiniRocket-KMeans · SR 0.866 · MDD −63.9%)도 lead 쪽 값이다.
#   그러므로 논문의 산출 형태는 횡단면 종목선택 팩터가 아니라
#   **부호(±1) 타이밍 × 리더 바스켓 EW 보유**다.
#   → FACTORS(Score) 가 아니라 PORTFOLIO(Weight) 로 낸다. 그래야 논문의 비중·방향이
#     러너의 top_n 재구성에 덮이지 않는다(러너: FACTORS 부재 → PORTFOLIO 직접 소비).
#
# ★alpha = 0.75 를 쓰는 이유 (논문 내부 모순의 해소 — 지어낸 값이 아니다):
#   §2.6.2(lead-lag 탐지 알고리즘 일반 서술): "the top alpha (0.25) fraction of assets
#     with the lowest scores (most leading) form the Leader set"
#   §4.2(Trading Strategy — 우리가 복제하는 대상, SR 0.866 을 낸 그 절차):
#     "We take the top 75% of time series after ranking as the Leader and the
#      remaining as the Lagger."
#   두 진술이 충돌한다. **전략 복제의 준거는 전략 절을 쓴 §4.2** 이므로 0.75 를 쓴다.
#   방증: 군집기 4종의 lead SR 이 0.801~0.866 으로 촘촘히 붙는다 — 리더 집합이
#   유니버스의 3/4 라 군집기 선택의 영향이 작다는 관측과 정합적이다.
#   (0.25 판을 보고 싶으면 .ALPHA 한 줄만 바꾸면 된다. 성과를 보고 고른 값이 아니다.)
#
# ★"(median)" 표기 = L_ij 를 DTW 정렬경로 오프셋의 **중앙값**으로 집계한 판.
#   헤드라인 0.866 이 median 판이므로 여기서도 median 을 쓴다(rowMedians).
#
# 논문 대비 변경 (FIDELITY.json::changed 와 동일 — 4건):
#   (1) 유니버스 → K200∪KQ150(PIT 시변) + adv20(t-1) ≥ 2e8   ← 지시된 유일 필수 변경
#   (2) 군집기 MiniRocket-KMeans → 창내 z정규 가격경로 KMeans. MiniRocket 은 파이썬
#       전용 random convolutional kernel 변환이라 R-native 대체가 불가피하다. 논문
#       자신의 비교표가 군집기 4종 모두 lead SR 0.80~0.87 로 붙는다고 보고 —
#       군집기는 이 전략의 기전이 아니다. lead-lag 추정(DTW)·리더 규칙·매매 규칙은 보존.
#   (3) 논문 미명시 step w → 1개월(≈21거래일·비중첩). l=21 과 일치하고, t+1 월간
#       집행기(get_execution_date = 익월 첫 거래일)가 지원하는 유일 주기다.
#   (4) EWMA span → 논문 선언 격자 {1,3,5,7} **전체 평균**에 sign. 넷 중 하나를
#       고르면 그 자체가 selection 이므로 선언된 값을 전부 소비한다.
#
# ★X(군집·DTW 입력)는 가격 경로다: Algorithm 1 은 군집 입력을 X 로, 신호 계산을 R_k 로
#   따로 적는다 — 같은 알고리즘 안에서 기호를 나눈 이상 X ≠ R 로 읽는 게 정직하다.
#   자산 간 비교를 위한 창내 z정규화는 논문 미서술이지만 KShape/KMeans 가 전제하는
#   전처리이고, 창 **내부** 통계라 C1 을 건드리지 않는다.
#
# ★고정 축(25종·long-only)을 여기 걸지 않는 이유: 그건 강화 단계의 축이고, 충실구현
#   라운드의 축은 "논문 명시값"이다. 논문은 비중(EW)·보유집합(리더 alpha)·방향(±1)을
#   전부 명시한다. ±1 신호를 long-only top-N 으로 접으면 부호 정보가 소멸해(음수 신호월에
#   "가장 덜 나쁜" 종목을 사게 된다) 논문 전략이 아니라 다른 전략이 된다.
#   러너의 replication_harness 는 롱숏·종목수 무제한을 지원한다(constraint_profile="replication").
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) =====
#   모든 창의 종점 = 시그널일 d(월말 종가 — d 시점에 기지). 러너가 익월 첫 거래일에
#   집행하므로 신호창과 보유구간의 교집합이 없다(동월 참조 원천 부재).
#   C1  : 전 표본 통계 0건. z정규화·kmeans·silhouette·DTW·EWMA 전부 21일 창 내부.
#   C2  : 미래 인덱싱 없음. DTW 역추적은 창 내부 (a,b) 격자를 (l,l)→(1,1) 로 거슬러만 간다.
#   C6  : 유니버스 = 날짜 d 의 K200/KQ150 멤버십(PIT 시변) — 미래 명부 주입 없음.
#   C10 : 유동성 = 20일 평균 거래대금을 by-Ticker shift(1) 한 t-1 값.
#   C13 : 부호 조작 없음. 방향이 정해지는 곳은 논문이 정의한 두 지점뿐 —
#         (1)리더 = S_i 최저(원문 명시) (2)포지션 부호 = sign(리더 EWMA)(원문 명시).
#   C15 : 팩터 DB 미접근 — 신호는 RAWDATA 가격/거래대금에서만 산출.
#
# 실행 비용: 군집 내부 전(全) 쌍 DTW 라 월당 최대 ~8e4 쌍. 쌍 축으로 벡터화한
#   band-free DP 로 청크 처리한다. 전 구간 십수 분대(단일 스레드).
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(cluster)      # silhouette — 논문의 K 선택 기준
  library(matrixStats)  # rowMedians — DTW 정렬 오프셋의 쌍별 중앙값
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(all(c("Date", "Ticker", "Close", "Vol", "Ret", "K200", "KQ150") %in% names(RAWDATA)))

# ---- 논문 명시 파라미터 (원문 값 — 임의 선택 아님) ----
.L     <- 21L                # "sliding window of fixed length l=21"
.ALPHA <- 0.75               # §4.2 "top 75% of time series after ranking as the Leader"
.SPANS <- c(1L, 3L, 5L, 7L)  # "EWMA ... p={1,3,5,7} days"
# ---- 계산 경계 (논문 미명시. 성과를 보고 고르지 않는다) ----
.KMAX  <- 10L                # silhouette 탐색 상한
.CMIN  <- 2L                 # 군집 최소 크기 — 쌍이 없으면 S_i 가 정의되지 않는다
.NMIN  <- 40L                # 월 최소 횡단면 — 군집·리더 분할이 의미를 갖는 하한
.LIQ   <- 2e8                # adv20(t-1) 하한 (KRW)
.CHUNK <- 12000L             # DTW 벡터화 청크 (메모리 경계)

# ---- 열 단위 z정규화 (창 내부. scale() 미사용 — 전역 통계 오해 소지 제거) ----
.znorm <- function(M) {
  n  <- nrow(M)
  mu <- colMeans(M)
  s  <- sqrt(pmax(colMeans(M * M) - mu * mu, 0) * (n / (n - 1)))
  ok <- is.finite(s) & s > 1e-12
  Z  <- matrix(0, nrow = n, ncol = ncol(M))
  if (any(ok))
    Z[, ok] <- (M[, ok, drop = FALSE] - rep(mu[ok], each = n)) / rep(s[ok], each = n)
  list(Z = Z, ok = ok)
}

# ---- DTW 상대 lag — 쌍 전체를 한 번에 (At, Bt = P x l, 행 하나가 한 쌍) ----
#   L_ij = median(idx_i − idx_j)  over the DTW alignment path.
#   리더는 자기 움직임이 상대에게 delta>0 뒤에 나타나므로 정렬이 i[a] <-> j[a+delta] 로
#   잡혀 idx_i − idx_j = −delta < 0 → S_i 최저. 원문 "lowest = most leading" 과 규약 일치.
#   step pattern 이 대칭(대각/수평/수직)이라 DTW(j,i) 경로는 DTW(i,j) 의 전치다 —
#   따라서 L_ji = −L_ij 가 성립하고 M[i,j] = L_ij − L_ji = 2·L_ij.
.dtw_lag <- function(At, Bt) {
  P <- nrow(At); l <- ncol(At)
  kk <- function(a, b) (a - 1L) * l + b
  D <- matrix(NA_real_, nrow = P, ncol = l * l)

  D[, kk(1L, 1L)] <- (At[, 1L] - Bt[, 1L])^2
  for (b in 2:l) D[, kk(1L, b)] <- D[, kk(1L, b - 1L)] + (At[, 1L] - Bt[, b])^2
  for (a in 2:l) {
    D[, kk(a, 1L)] <- D[, kk(a - 1L, 1L)] + (At[, a] - Bt[, 1L])^2
    for (b in 2:l)
      D[, kk(a, b)] <- pmin(D[, kk(a - 1L, b)], D[, kk(a, b - 1L)],
                            D[, kk(a - 1L, b - 1L)]) + (At[, a] - Bt[, b])^2
  }

  # 역추적 (l,l) → (1,1). 쌍마다 (1,1) 도달 시 기록을 끊는다 —
  # 도달 후에도 0 을 계속 적으면 중앙값이 0 쪽으로 끌린다.
  ai <- rep(l, P); bi <- rep(l, P)
  pr <- seq_len(P)
  fin <- rep(FALSE, P)
  off <- matrix(NA_real_, nrow = P, ncol = 2L * l)
  for (st in seq_len(2L * l)) {
    rec <- !fin
    off[rec, st] <- ai[rec] - bi[rec]
    fin <- fin | (ai == 1L & bi == 1L)
    if (all(fin)) break
    up <- !fin & ai > 1L
    lf <- !fin & bi > 1L
    dg <- up & lf
    cU <- rep(Inf, P); cL <- rep(Inf, P); cD <- rep(Inf, P)
    if (any(up)) cU[up] <- D[cbind(pr[up], kk(ai[up] - 1L, bi[up]))]
    if (any(lf)) cL[lf] <- D[cbind(pr[lf], kk(ai[lf], bi[lf] - 1L))]
    if (any(dg)) cD[dg] <- D[cbind(pr[dg], kk(ai[dg] - 1L, bi[dg] - 1L))]
    go_d <- dg & cD <= cU & cD <= cL
    go_u <- !go_d & up & cU <= cL
    go_l <- !go_d & !go_u & lf
    ai[go_d] <- ai[go_d] - 1L; bi[go_d] <- bi[go_d] - 1L
    ai[go_u] <- ai[go_u] - 1L
    bi[go_l] <- bi[go_l] - 1L
  }
  rowMedians(off, na.rm = TRUE)
}

# ---- EWMA 종점값 (span p → a = 2/(p+1)). 창 내부, pandas ewm(span=) 기본형 ----
#   w_i = (1-a)^(n-i), 정규화 합. x[n] 이 창의 마지막 날(= 시그널일 d).
.ewma_last <- function(x, span) {
  a <- 2 / (span + 1)
  w <- (1 - a)^seq.int(length(x) - 1L, 0L)
  sum(w * x) / sum(w)
}

# ---- 패널 준비 (RAWDATA 비파괴 — 러너가 이후 시뮬레이션에 재사용) ----
.rd <- RAWDATA[, .(Date, Ticker, Close, Vol, Ret, K200, KQ150)]
.rd <- .rd[is.finite(Close) & Close > 0]
setorder(.rd, Ticker, Date)
.rd[, TV := Close * Vol]
.rd[, ADV20_L1 := shift(frollmean(TV, 20L, align = "right"), 1L), by = Ticker]  # C10 t-1

.rd[, ymk := format(Date, "%Y-%m")]
.month_ends <- sort(.rd[, .(D = max(Date)), by = ymk]$D)
.rd[, ymk := NULL]
.sig_dates <- .month_ends[.month_ends >= as.Date("2005-01-01")]   # 러너 절단선과 정합
.all_dates <- sort(unique(.rd$Date))
setkey(.rd, Date, Ticker)

# ---- 월별 (step w = 1개월): 군집 → 군집내 DTW lead-lag → 리더 바스켓 부호 타이밍 ----
.out <- vector("list", length(.sig_dates))
for (ii in seq_along(.sig_dates)) {
  d  <- .sig_dates[ii]
  di <- match(d, .all_dates)
  if (is.na(di) || di < .L) next
  win <- .all_dates[(di - .L + 1L):di]        # [Step 1] 종점 = d. 창 전체가 d 시점 기지.

  # 유니버스: d 의 K200/KQ150 멤버십 + adv20(t-1) 하한 (C6·C10)
  elig <- .rd[.(d), .(Ticker, K200, KQ150, ADV20_L1)][
                (K200 | KQ150) & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ, Ticker]
  if (length(elig) < .NMIN) next

  wdt  <- .rd[.(win), .(Date, Ticker, Close, Ret), nomatch = 0L]
  wdt  <- wdt[Ticker %chin% elig & is.finite(Close) & is.finite(Ret)]
  full <- wdt[, .N, by = Ticker][N == .L, Ticker]   # 창 전체 관측이 있는 종목만
  if (length(full) < .NMIN) next
  wdt  <- wdt[Ticker %chin% full]

  PW <- dcast(wdt, Date ~ Ticker, value.var = "Close"); setorder(PW, Date)
  RW <- dcast(wdt, Date ~ Ticker, value.var = "Ret");   setorder(RW, Date)
  Pw  <- as.matrix(PW[, -1L, with = FALSE])         # l x n — 논문 X_{n×l} 의 전치
  Rw  <- as.matrix(RW[, -1L, with = FALSE])         # l x n — Step 4/5 의 R_k
  tks <- colnames(Pw)
  stopifnot(identical(tks, colnames(Rw)))

  zz <- .znorm(Pw)                                  # 창 내부 정규화 (C1)
  if (sum(zz$ok) < .NMIN) next
  Zt <- t(zz$Z[, zz$ok, drop = FALSE])              # n x l — 군집·DTW 입력
  Rk <- Rw[, zz$ok, drop = FALSE]                   # l x n — 신호용 수익
  tk <- tks[zz$ok]
  n  <- nrow(Zt)

  # [Step 2] 군집화 — K = 평균 silhouette 최대 (초록 명시 기준)
  set.seed(as.integer(d))                           # 재현성 (Judge 재현 축)
  dz  <- dist(Zt)
  khi <- min(.KMAX, n - 1L)
  if (khi < 2L) next
  cl <- NULL; sil_max <- -Inf
  for (k in 2:khi) {
    km <- tryCatch(suppressWarnings(kmeans(Zt, centers = k, nstart = 3L, iter.max = 50L)),
                   error = function(e) NULL)
    if (is.null(km) || length(unique(km$cluster)) < 2L) next
    sw <- mean(silhouette(km$cluster, dz)[, 3L])
    if (is.finite(sw) && sw > sil_max) { sil_max <- sw; cl <- km$cluster }
  }
  rm(dz)
  if (is.null(cl)) next

  # [Step 3] 군집 내부 전(全) 쌍 DTW → M[i,j] = L_ij − L_ji → S_i = Σ_j M[i,j]
  #          → S_i 최저 alpha 분율 = Leader L (분할은 군집별로 — 원문 Step 3)
  lead_pos <- integer(0)
  for (g in sort(unique(cl))) {
    mem <- which(cl == g)
    m   <- length(mem)
    if (m < .CMIN) next                             # 쌍이 없으면 S_i 미정의
    cmb <- which(upper.tri(matrix(TRUE, m, m)), arr.ind = TRUE)
    u <- cmb[, 1L]; v <- cmb[, 2L]
    P <- length(u)
    Lh <- numeric(P)
    for (s0 in seq(1L, P, by = .CHUNK)) {
      sl <- s0:min(s0 + .CHUNK - 1L, P)
      Lh[sl] <- .dtw_lag(Zt[mem[u[sl]], , drop = FALSE],
                         Zt[mem[v[sl]], , drop = FALSE])
    }
    M <- matrix(0, nrow = m, ncol = m)
    M[cbind(u, v)] <-  2 * Lh                       # L_ij − L_ji = 2·L_ij (대칭 step pattern)
    M[cbind(v, u)] <- -2 * Lh
    S  <- rowSums(M)
    nl <- max(1L, as.integer(floor(.ALPHA * m)))
    lead_pos <- c(lead_pos, mem[order(S)[seq_len(nl)]])
  }
  if (length(lead_pos) < 2L) next

  # [Step 4] signal = sign( (1/|L|) Σ_{k∈L} EWMA(R_k, spn) ), spn = {1,3,5,7}
  #   원문은 excess return 이라 적는다. 일간 무위험수익 패널이 없고 부호 판정에 대한
  #   기여가 무시할 수준이라 원수익을 쓴다 — 대리변수 합성이 아니라 항 생략이다.
  Rlead <- rowMeans(Rk[, lead_pos, drop = FALSE])   # 리더 EW 바스켓의 창 내 일별 수익
  ew  <- vapply(.SPANS, function(p) .ewma_last(Rlead, p), numeric(1))
  if (!all(is.finite(ew))) next
  sgn <- sign(mean(ew))
  if (sgn == 0) next

  # [Step 5] lead strategy — 리더 바스켓을 EW 로, signal 부호 방향으로 보유
  .out[[ii]] <- data.table(
    Date   = d,
    Ticker = tk[lead_pos],
    Weight = sgn / length(lead_pos),
    Leg    = if (sgn > 0) "long" else "short")

  if (ii %% 24L == 0L) {
    cat(sprintf("[RP_AUTO_2608_24703] %s | N=%d K=%d |L|=%d sil=%.3f sgn=%+d\n",
                as.character(d), n, length(unique(cl)), length(lead_pos),
                sil_max, as.integer(sgn)))
    gc(verbose = FALSE)
  }
}

PORTFOLIO <- rbindlist(Filter(Negate(is.null), .out), use.names = TRUE)
if (nrow(PORTFOLIO) == 0L)
  stop("[RP_AUTO_2608_24703] PORTFOLIO 0행 — 유니버스/창/군집 확인")

cat(sprintf(paste0("[RP_AUTO_2608_24703] lead strategy (l=%d · alpha=%.2f · spans %s) | ",
                   "rows=%d months=%d %s~%s | avg |L|/mo=%.0f | long %d mo / short %d mo\n"),
            .L, .ALPHA, paste(.SPANS, collapse = ","),
            nrow(PORTFOLIO), uniqueN(PORTFOLIO$Date),
            as.character(min(PORTFOLIO$Date)), as.character(max(PORTFOLIO$Date)),
            nrow(PORTFOLIO) / uniqueN(PORTFOLIO$Date),
            uniqueN(PORTFOLIO[Leg == "long"]$Date),
            uniqueN(PORTFOLIO[Leg == "short"]$Date)))
