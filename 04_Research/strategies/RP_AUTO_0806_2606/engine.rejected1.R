# =============================================================================
# engine.R — RP_AUTO_0806_2606
# "Anomalous Returns in a Neural Network Equity-Ranking Predictor"
#   J.B. Satinover (Univ. Nice) · D. Sornette (ETH Zurich) — arXiv:0806.2606 (2008-06-16)
#   https://arxiv.org/abs/0806.2606   (전문: arxiv PDF 를 텍스트 프록시로 판독 — FIDELITY.json source_paper)
#
# ★fidelity 라벨·변경 전수 신고·러너 사양의 정본 = FIDELITY.json. 이 주석은 요약일 뿐 아무것도 결정하지 않는다.
#
# ── 논문이 준 것 (원문 위치) ──────────────────────────────────────────────────
#   §3.2  "Inputs to the network consist of the ten preceding quarterly percent price and earnings
#          changes (not accumulated) transformed as ranks." / Abstract: "converted to a relative rank
#          scaled around zero" / "Outputs are the predicted next quarter's percentage price changes.
#          All ~1452 stocks are then ranked in descending order by the ANN's predicted percentage
#          price change for the next (out of sample) quarter."
#   §3.2  "A T10 portfolio consists of the 10 equities predicted to perform best, the T20 the twenty
#          ... and so on to T100. ... B10,…,B100 ... from the bottom of the ranking up. H10,…H100
#          ... T equities bought and the B equities sold short."
#   §3.2  "the final column of earnings data is not used at all as input for those weekly or monthly
#          date cycles when it couldn't be available at all, and in all earnings input columns, 30% of
#          the earnings figures are removed at random before ranking"
#   §3.4  "a simple back propagation network with a single hidden layer and recurrence." /
#         "The results of multiple initializations are aggregated to obtain a final ranking." /
#         "Exact net architecture and parameters are optimized independently on each new data set
#          using a genetic algorithm but with extremely tight constraints. ... Only a hidden single
#          hidden layer is allowed. In general, minimal searching is permitted."
#   §3.5  "Training and testing sets are selected a-priori at random for optimization of training
#          iterations. Under-fitting is greatly preferred to over fitting." / "the network is always
#          freshly trained on (ten quarters of) data that is out of the (one quarter) prediction sample."
#   §4.1.1 "Once a month, the ANN ... predict and rank-order ... Every portfolio is readjusted once per
#          month. To adjust for possible monthly or seasonal effects, results are averaged over all three
#          possible monthly starting points in a quarter." / Abstract: "all portfolios are held fixed for
#          one quarter." / "the fully hedged T100+B100 = H100 equity portfolio"
#
# ── 이 엔진이 하는 일 (논문 그대로 · 유니버스만 K200∪KQ150) ───────────────────
#   매 월말 d: 적격 종목(멤버십 PIT + adv20(t−1) ≥ 2e8)의 20입력(가격 변화율 10분기 + 이익 변화율
#   10분기, 각 열을 d 시점 횡단면 순위 → [−1,1]) 으로 단일 은닉층 역전파 MLP 를 **d 이전 10분기**
#   (표적 = 다음 분기 가격 변화율, d 까지 실현된 것만)로 새로 학습 → d 의 예측값 내림차순 →
#   T100 롱(EW) / B100 숏(EW) 트랜치 → 1분기 보유. 월간 시작점 3개의 평균 = 중첩 트랜치 3개(각 1/3).
#   산출 = PORTFOLIO(Date, Ticker, Weight, Leg) [H100 집계] + FACTORS(Date, Ticker, Score) [전 종목 예측].
#
# ── PIT (C1~C15) — 구조로 보장 (정적 탐지 통과를 근거로 삼지 않는다) ─────────────
#   시그널 d = 월 마지막 거래일, 집행 = 익월 첫 거래일(러너) → 모든 창의 종점 = t−1.
#   가격 입력 = d 이하 월말 종가만 · 표적 = d 이하에서 실현 완료된 분기만(학습 표본은 d−3k 시점) ·
#   이익 = Factor_Date(PIT 가용일: Q1~Q3 분기말+45일 · Q4 익년 3/31) ≤ 해당 시점 것만 ·
#   순위·표적 표준화 = 각 시점 횡단면 / 학습 표본 내부만(전 표본 통계 0건) · 멤버십 = 해당 시점 플래그(C6) ·
#   유동성 = 20일 평균 거래대금의 shift(1)(C10) · 부호 조작 0건(C13) · 팩터 DB 미접근(C15) · 난수 = 고정 seed.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.REQ <- c("Date", "Ticker", "Close", "Vol", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("[RP_AUTO_0806_2606] RAWDATA 필수 열 부재: %s",
               paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))

# =============================================================================
# 0. 상수 — 논문값 / 고정 축 / 구현 상수(논문 미명시 — FIDELITY.json changed 전수 신고)
# =============================================================================
.N_LAG     <- 10L      # 논문: ten preceding quarterly changes (가격·이익 각각)
.N_TRAINQ  <- 10L      # 논문 §3.5: freshly trained on (ten quarters of) data
.HOLD_M    <- 3L       # 논문: held fixed for one quarter · 월간 시작점 3개 → 중첩 트랜치 3개
.N_TOP     <- 100L     # 논문 T100 (선택한 칸 = H100. 다른 CD 10~90 은 미측정 — FIDELITY changed)
.N_BOT     <- 100L     # 논문 B100
.EARN_DROP <- 0.30     # 논문 §3.2: 30% of the earnings figures are removed at random before ranking

.SIG_FROM  <- as.Date("2005-01-01")   # 고정 축 시작
.LIQ       <- 2e8                     # adv20(t−1) 하한 KRW — 고정 축

.VAL_FRAC     <- 0.20        # 학습 표본 중 무작위 검증 비율 (논문: 'selected a-priori at random', 비율 미명시)
.HID          <- c(4L, 8L, 16L)  # 은닉 유닛 후보 (논문: GA 로 'exact net architecture' 결정, 값 미명시)
.N_INIT       <- 5L          # 초기화 횟수 (논문: 'multiple initializations are aggregated', 횟수 미명시)
.MAX_EPOCH    <- 300L        # 전배치 역전파 최대 에폭 (논문 미명시)
.PATIENCE     <- 20L         # 검증 MSE 무개선 허용 에폭 = 'optimization of training iterations' 의 수치화
.LR           <- 0.01        # 학습률 (논문 미명시)
.MOM          <- 0.9         # 모멘텀 (논문 미명시)
.UNDERFIT_TOL <- 0.02        # 'Under-fitting is greatly preferred': 최소 검증 MSE ×(1+tol) 안의 가장 작은 은닉 수 선택
.Y_CLIP       <- 5           # 학습 표적(표준화) 절단 ±5 SD — 우리 데이터 위생(분할 미조정 잔재), 논문에 없음
.MIN_TRAIN    <- 100L        # 학습 표본 하한 (논문에 없음 — 하한 미달 월은 미발행·출력)
.SEED_BASE    <- 20080616L   # 난수 seed 기저 (논문 제출일) + 월 인덱스 → 결정론적 재현

# =============================================================================
# 1. 보조 함수
# =============================================================================
.as_flag <- function(x) {
  if (is.logical(x)) return(x %in% TRUE)
  if (is.numeric(x)) return(is.finite(x) & x != 0)
  toupper(trimws(as.character(x))) %in% c("TRUE", "T", "1", "Y", "YES")
}
.ym <- function(mi) sprintf("%d-%02d", (mi - 1L) %/% 12L, (mi - 1L) %% 12L + 1L)

# 횡단면 순위 → [−1, 1] (논문: 'relative rank scaled around zero' — 범위는 우리 선택). 동률 = 평균 순위. 결측 = 0(중립).
.rank_unit <- function(v) {
  out <- numeric(length(v))
  ok  <- is.finite(v)
  m   <- sum(ok)
  if (m >= 2L) {
    r <- rank(v[ok], ties.method = "average")
    out[ok] <- 2 * (r - 1) / (m - 1) - 1
  }
  out
}
.rank_cols <- function(M) { for (j in seq_len(ncol(M))) M[, j] <- .rank_unit(M[, j]); M }

# =============================================================================
# 2. 일간 패널 → 멤버십 · 유동성(t−1) · 월말 종가 패널   (RAWDATA 비파괴 — 러너가 재사용)
# =============================================================================
.t0 <- Sys.time()
.rd <- RAWDATA[is.finite(Close) & Close > 0,
               .(Date, Ticker = as.character(Ticker), Close, TV = Close * Vol,
                 MEM = .as_flag(K200) | .as_flag(KQ150))]
if (!inherits(.rd$Date, "Date")) .rd[, Date := as.Date(Date)]
setorder(.rd, Ticker, Date)
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[RP_AUTO_0806_2606] (Ticker,Date) 중복 %d행 — 첫 행만 유지\n", .ndup))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}
.rd[, ADV20_L1 := shift(frollmean(TV, 20L, align = "right"), 1L), by = Ticker]   # C10: t−1 유동성
.rd[, TV := NULL]
.rd[, MI := year(Date) * 12L + month(Date)]

# 시장 월말(그 달 마지막 거래일). RAWDATA 의 마지막 달은 진행 중(부분월)으로 보고 제외한다.
.me <- .rd[, .(MEnd = max(Date)), by = MI]
setorder(.me, MI)
.MI_LAST <- max(.me$MI)
.me <- .me[MI < .MI_LAST]
if (nrow(.me) == 0L) stop("[RP_AUTO_0806_2606] 완결 월 0개 — RAWDATA 날짜 범위 확인")

# 종목별 월간 마지막 관측(종가·멤버십·유동성) — 한 종목·한 달에 한 행
.rs <- .rd[MI < .MI_LAST]
rm(.rd); gc(verbose = FALSE)
.n <- nrow(.rs)
.lastrow <- c(.rs$Ticker[-1L] != .rs$Ticker[-.n] | .rs$MI[-1L] != .rs$MI[-.n], TRUE)
.mp <- .rs[.lastrow, .(Ticker, MI, Close, MEM, ADV20_L1)]
rm(.rs); gc(verbose = FALSE)

# 월말 종가 행렬 P[월, 종목] → 분기 가격 변화율 QC[i, ] = P[i, ]/P[i−3, ] − 1  (논문: quarterly percent price change)
.wide <- dcast(.mp, MI ~ Ticker, value.var = "Close")
setorder(.wide, MI)
.MIs <- .wide$MI
if (any(diff(.MIs) != 1L))
  stop("[RP_AUTO_0806_2606] 월 인덱스가 연속이 아님 — 거래 데이터가 통째로 빈 달이 있다")
.TK <- setdiff(names(.wide), "MI")
.P  <- as.matrix(.wide[, .TK, with = FALSE])
rm(.wide)
.NR <- nrow(.P)
.QC <- matrix(NA_real_, .NR, ncol(.P), dimnames = list(NULL, .TK))
if (.NR > 3L) .QC[4L:.NR, ] <- .P[4L:.NR, , drop = FALSE] / .P[1L:(.NR - 3L), , drop = FALSE] - 1
rm(.P); gc(verbose = FALSE)

# 적격 종목(시점별): 멤버십(C6) ∧ adv20(t−1) ≥ 2e8 (C10)
.el <- .mp[MEM & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ, .(MI, Ticker)]
.EL <- split(.el$Ticker, .el$MI)
rm(.mp, .el); gc(verbose = FALSE)
cat(sprintf("[RP_AUTO_0806_2606] 월말 종가 패널 %d개월 (%s ~ %s) × %d종 | 마지막 부분월 %s 제외 | %.1f분\n",
            length(.MIs), .ym(min(.MIs)), .ym(max(.MIs)), length(.TK), .ym(.MI_LAST),
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))

# =============================================================================
# 3. 분기 이익 패널 (QuantiWise xlsx 분기 재무 → 주당순이익 → 분기 변화율 · PIT 가용일)
#    이익 = (PretaxIncome − TaxExpense) / ISSD(수정 발행주식수)  ← 논문 VL 분기 EPS 의 KR 대응
#    변화율 g_q = (E_q − E_{q−1}) / |E_{q−1}| (연속 분기만 · 분모 0 = NA)
#    가용일 AVAIL = max(Factor_Date_q, Factor_Date_{q−1}) — 두 분기가 모두 공표된 뒤에만 입력 (C4 lag 반영)
# =============================================================================
.cache_dir <- local({
  cd <- if (exists("CACHE_DIR", inherits = TRUE)) as.character(get("CACHE_DIR", inherits = TRUE))[1L] else ""
  if (!nzchar(cd)) {
    root <- Sys.getenv("QM_ROOT", "")
    if (!nzchar(root)) root <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
    if (!nzchar(root) && exists("PROJECT_ROOT", inherits = TRUE))
      root <- as.character(get("PROJECT_ROOT", inherits = TRUE))[1L]
    if (nzchar(root)) cd <- file.path(root, ".cache")
  }
  cd
})
if (!nzchar(.cache_dir) || !dir.exists(.cache_dir))
  stop("[RP_AUTO_0806_2606] 캐시 디렉터리를 찾지 못함 (CACHE_DIR / QM_ROOT / CLAUDE_PROJECT_DIR) — 이익 패널 접근 불가라 중단")
.fx_path <- file.path(.cache_dir, "fundamental_xlsx.parquet")
if (!file.exists(.fx_path))
  stop(sprintf("[RP_AUTO_0806_2606] 분기 이익 패널 부재: %s — 논문 입력(이익 변화율)을 지킬 수 없어 중단", .fx_path))
.fx <- as.data.table(arrow::read_parquet(.fx_path,
                                         col_select = c("Ticker", "Item", "Value", "Period_Date", "Factor_Date")))
.fx <- .fx[Item %in% c("PretaxIncome", "TaxExpense", "ISSD") & is.finite(Value)]
if (nrow(.fx) == 0L) stop("[RP_AUTO_0806_2606] 이익 패널에 PretaxIncome/TaxExpense/ISSD 0행")
.fx[, Ticker := as.character(Ticker)]
if (!inherits(.fx$Period_Date, "Date")) .fx[, Period_Date := as.Date(Period_Date, tz = "Asia/Seoul")]
if (!inherits(.fx$Factor_Date, "Date")) .fx[, Factor_Date := as.Date(Factor_Date, tz = "Asia/Seoul")]
.fw <- dcast(.fx, Ticker + Period_Date + Factor_Date ~ Item, value.var = "Value",
             fun.aggregate = function(x) x[1L])
for (.cc in c("PretaxIncome", "TaxExpense", "ISSD")) if (!.cc %in% names(.fw)) .fw[, (.cc) := NA_real_]
.fw[, NI  := fifelse(is.finite(PretaxIncome) & is.finite(TaxExpense), PretaxIncome - TaxExpense, NA_real_)]
.fw[, EPS := fifelse(is.finite(NI) & is.finite(ISSD) & ISSD > 0, NI / ISSD, NA_real_)]
.fw[, PMI := year(Period_Date) * 12L + month(Period_Date)]
.fw[, FDn := as.numeric(Factor_Date)]                      # 가용일을 일수로 (shift/pmax 의 클래스 보존 문제 회피)
setorder(.fw, Ticker, PMI)
.fw[, `:=`(EPS_L1 = shift(EPS), PMI_L1 = shift(PMI), FDn_L1 = shift(FDn)), by = Ticker]
.fw[, G := fifelse(is.finite(EPS) & is.finite(EPS_L1) & EPS_L1 != 0 & (PMI - PMI_L1) == 3L,
                   (EPS - EPS_L1) / abs(EPS_L1), NA_real_)]
.fw[, AVAIL := as.Date(pmax(FDn, FDn_L1), origin = "1970-01-01")]   # 두 분기 가용일의 늦은 쪽 (lag 반영)
.E <- .fw[is.finite(G) & !is.na(AVAIL), .(Ticker, PMI, AVAIL, G)]
if (nrow(.E) == 0L) stop("[RP_AUTO_0806_2606] 분기 이익 변화율 0행 — 패널 항목·주식수 확인")
cat(sprintf("[RP_AUTO_0806_2606] 이익 패널: 원행 %d → EPS 변화율 %d행 · %d종 · 기간 %s ~ %s · 가용일 %s ~ %s\n",
            nrow(.fx), nrow(.E), uniqueN(.E$Ticker), .ym(min(.E$PMI)), .ym(max(.E$PMI)),
            as.character(min(.E$AVAIL)), as.character(max(.E$AVAIL))))
rm(.fx, .fw); gc(verbose = FALSE)

# 시점 d 에 가용(AVAIL ≤ d)한 최근 10개 분기 변화율 — 행 = tk 순서, 열 = 최근순 lag 1..10
.earn_mat <- function(d, tk) {
  M <- matrix(NA_real_, length(tk), .N_LAG)
  a <- .E[AVAIL <= d & Ticker %chin% tk]
  if (nrow(a) == 0L) return(M)
  setorder(a, Ticker, -PMI)
  a[, LAG := seq_len(.N), by = Ticker]
  a <- a[LAG <= .N_LAG]
  M[cbind(match(a$Ticker, tk), a$LAG)] <- a$G
  M
}

# =============================================================================
# 4. 시점별 입력 행렬 X(s) [N × 20] · 표적 y(s) [다음 분기 가격 변화율] — 월말마다 1회 구성
#    가격 블록: QC[i], QC[i−3], …, QC[i−27]  (ten preceding quarterly changes, 최근순)
#    이익 블록: .earn_mat(d, tk) → 열별 30% 무작위 제거(논문) → 순위
# =============================================================================
.build_inputs <- function(i, d, tk) {
  ci <- match(tk, .TK)
  XP <- matrix(NA_real_, length(tk), .N_LAG)
  for (k in seq_len(.N_LAG)) {
    r <- i - 3L * (k - 1L)
    if (r >= 1L) XP[, k] <- .QC[r, ci]
  }
  XE <- .earn_mat(d, tk)
  ecov <- mean(rowSums(is.finite(XE)) > 0)          # 진단: 이익 입력이 하나라도 있는 종목 비율(제거 전)
  for (j in seq_len(.N_LAG)) {
    ok <- which(is.finite(XE[, j]))
    nd <- as.integer(round(.EARN_DROP * length(ok)))
    if (nd > 0L) XE[ok[sample.int(length(ok), nd)], j] <- NA_real_
  }
  list(X = cbind(.rank_cols(XP), .rank_cols(XE)), ecov = ecov)
}

.MI_SIG0 <- (year(.SIG_FROM) * 12L + month(.SIG_FROM)) - (.HOLD_M - 1L)   # 첫 트랜치 = 2004-11 (2005-01 집계용)
.MI_PRE0 <- .MI_SIG0 - 3L * .N_TRAINQ
.pre <- list()
for (mi in seq(.MI_PRE0, max(.me$MI))) {
  i <- match(mi, .MIs)
  if (is.na(i)) next
  tk <- .EL[[as.character(mi)]]
  if (is.null(tk) || length(tk) < 2L) next
  tk <- tk[tk %chin% .TK]
  if (length(tk) < 2L) next
  d <- .me[MI == mi]$MEnd[1L]
  set.seed(.SEED_BASE + mi)
  bi <- .build_inputs(i, d, tk)
  y  <- if (i + .HOLD_M <= .NR) .QC[i + .HOLD_M, match(tk, .TK)] else rep(NA_real_, length(tk))
  .pre[[as.character(mi)]] <- list(tk = tk, X = bi$X, y = y, d = d, ecov = bi$ecov)
}
if (length(.pre) == 0L) stop("[RP_AUTO_0806_2606] 입력 행렬 0개 — 적격 종목/월말 확인")
cat(sprintf("[RP_AUTO_0806_2606] 입력 행렬 %d개월 구성 (%s ~ %s) | %.1f분\n",
            length(.pre), .ym(min(as.integer(names(.pre)))), .ym(max(as.integer(names(.pre)))),
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))

# =============================================================================
# 5. 단일 은닉층 역전파 MLP — 다중 초기화 × 은닉 크기 후보를 블록 대각 한 네트워크로 동시 학습
#    (헤드 간 가중치 공유 0 = 독립 네트워크 K×|HID| 개와 수학적으로 동일)
#    은닉 tanh · 출력 선형 · 손실 = 헤드별 MSE · 전배치 경사하강 + 모멘텀 · 헤드별 검증 조기종료
#    표적 = 다음 분기 가격 변화율(학습 분할의 평균·SD 로 표준화, ±Y_CLIP 절단)
#    반환 = 선택 은닉 크기의 헤드들(각자 최적 에폭)의 예측 평균 (논문: multiple initializations aggregated)
# =============================================================================
.fwd <- function(X, W1, b1, W2, b2) {
  Hd <- tanh(X %*% W1 + rep(b1, each = nrow(X)))
  list(Hd = Hd, out = Hd %*% W2 + rep(b2, each = nrow(X)))
}
.ann_fit_predict <- function(Xtr, ytr, Xpr, seed) {
  set.seed(seed)
  n <- nrow(Xtr); p <- ncol(Xtr)
  nv  <- max(1L, as.integer(floor(n * .VAL_FRAC)))
  iv  <- sample.int(n, nv)
  itr <- setdiff(seq_len(n), iv)
  if (length(itr) < 2L) return(NULL)
  mu  <- mean(ytr[itr]); sdv <- sd(ytr[itr])
  if (!is.finite(sdv) || sdv <= 0) return(NULL)
  yz <- (ytr - mu) / sdv
  yz <- pmin(pmax(yz, -.Y_CLIP), .Y_CLIP)
  Xa <- Xtr[itr, , drop = FALSE]; ya <- yz[itr]; na <- length(itr)
  Xv <- Xtr[iv,  , drop = FALSE]; yv <- yz[iv]

  hs  <- rep(.HID, each = .N_INIT)             # 헤드 → 은닉 유닛 수
  H   <- length(hs); tot <- sum(hs)
  blk <- rep(seq_len(H), times = hs)           # 은닉 유닛 → 헤드
  W1  <- matrix(runif(p * tot, -1, 1) / sqrt(p), p, tot)
  b1  <- runif(tot, -1, 1) / sqrt(p)
  M2  <- matrix(0, tot, H); M2[cbind(seq_len(tot), blk)] <- 1
  W2  <- sweep(M2 * matrix(runif(tot * H, -1, 1), tot, H), 2L, sqrt(hs), "/")
  b2  <- numeric(H)
  vW1 <- 0 * W1; vb1 <- 0 * b1; vW2 <- 0 * W2; vb2 <- 0 * b2
  bv <- rep(Inf, H); be <- integer(H); since <- integer(H); alive <- rep(TRUE, H)
  pb <- matrix(NA_real_, nrow(Xpr), H)
  ep <- 0L
  for (ep in seq_len(.MAX_EPOCH)) {
    f   <- .fwd(Xa, W1, b1, W2, b2)
    E   <- (f$out - ya) * (2 / na)             # d MSE_h / d out  (헤드별)
    gW2 <- crossprod(f$Hd, E) * M2
    gb2 <- colSums(E)
    dH  <- (E %*% t(W2)) * (1 - f$Hd^2)        # 블록 대각 W2 → 은닉 유닛은 자기 헤드의 오차만 받는다
    gW1 <- crossprod(Xa, dH)
    gb1 <- colSums(dH)
    vW1 <- .MOM * vW1 - .LR * gW1; W1 <- W1 + vW1
    vb1 <- .MOM * vb1 - .LR * gb1; b1 <- b1 + vb1
    vW2 <- .MOM * vW2 - .LR * gW2; W2 <- W2 + vW2
    vb2 <- .MOM * vb2 - .LR * gb2; b2 <- b2 + vb2
    vm  <- colMeans((.fwd(Xv, W1, b1, W2, b2)$out - yv)^2)
    imp <- alive & is.finite(vm) & (vm < bv)
    if (any(imp)) {
      pp <- .fwd(Xpr, W1, b1, W2, b2)$out
      bv[imp] <- vm[imp]; be[imp] <- ep; since[imp] <- 0L
      pb[, imp] <- pp[, imp, drop = FALSE]
    }
    since[alive & !imp] <- since[alive & !imp] + 1L
    alive <- alive & (since < .PATIENCE)
    if (!any(alive)) break
  }
  # 은닉 크기 선택: 초기화 평균 검증 MSE 가 최소 ×(1+tol) 안에 드는 가장 작은 크기 (under-fitting 선호)
  mv <- vapply(.HID, function(h) {
    j <- which(hs == h & is.finite(bv)); if (length(j)) mean(bv[j]) else NA_real_ }, numeric(1L))
  if (!any(is.finite(mv))) return(NULL)
  hmin <- min(mv, na.rm = TRUE)
  hsel <- .HID[which(is.finite(mv) & mv <= (1 + .UNDERFIT_TOL) * hmin)][1L]
  jj   <- which(hs == hsel & is.finite(bv))
  list(pred = rowMeans(pb[, jj, drop = FALSE]), hsel = hsel, mv = mv,
       ep_med = as.integer(median(be[jj])), n_tr = na, n_val = nv, n_heads = length(jj), ep_run = ep)
}

# =============================================================================
# 6. 월별 루프 — 학습(직전 10분기) → 예측 → 내림차순 → T100 롱 / B100 숏 트랜치 → 중첩 3트랜치 집계
# =============================================================================
.rows_f <- list(); .rows_p <- list(); .diag <- list(); .tranche <- list()
.nskip <- 0L
.MI_OUT0 <- year(.SIG_FROM) * 12L + month(.SIG_FROM)
for (mi in seq(.MI_SIG0, max(.me$MI))) {
  pr <- .pre[[as.character(mi)]]
  if (is.null(pr)) { .nskip <- .nskip + 1L; cat(sprintf("[RP_AUTO_0806_2606] %s 입력 없음 — 미발행\n", .ym(mi))); next }
  tr <- lapply(seq_len(.N_TRAINQ), function(k) .pre[[as.character(mi - 3L * k)]])
  tr <- Filter(Negate(is.null), tr)
  if (length(tr) == 0L) { .nskip <- .nskip + 1L; cat(sprintf("[RP_AUTO_0806_2606] %s 학습 분기 0 — 미발행\n", .ym(mi))); next }
  Xtr <- do.call(rbind, lapply(tr, `[[`, "X"))
  ytr <- unlist(lapply(tr, `[[`, "y"), use.names = FALSE)
  ok  <- is.finite(ytr)
  Xtr <- Xtr[ok, , drop = FALSE]; ytr <- ytr[ok]
  if (nrow(Xtr) < .MIN_TRAIN) {
    .nskip <- .nskip + 1L
    cat(sprintf("[RP_AUTO_0806_2606] %s 학습 표본 %d < %d — 미발행\n", .ym(mi), nrow(Xtr), .MIN_TRAIN)); next
  }
  fit <- .ann_fit_predict(Xtr, ytr, pr$X, seed = .SEED_BASE + 1000L + mi)
  if (is.null(fit) || !all(is.finite(fit$pred))) {
    .nskip <- .nskip + 1L
    cat(sprintf("[RP_AUTO_0806_2606] %s 학습 실패(검증 개선 헤드 0 또는 비유한 예측) — 미발행\n", .ym(mi))); next
  }
  score <- fit$pred
  n <- length(pr$tk)
  .rows_f[[length(.rows_f) + 1L]] <- data.table(Date = pr$d, Ticker = pr$tk, Score = score)

  # 트랜치: 예측 내림차순 → 상위 .N_TOP 롱 EW(+1/k) · 하위 .N_BOT 숏 EW(−1/k). 다리 중첩 불가 → k ≤ floor(N/2) (N<200 에서만 구속)
  o  <- order(-score, pr$tk)
  kl <- min(.N_TOP, n %/% 2L); ks <- min(.N_BOT, n %/% 2L)
  if (kl < 1L || ks < 1L) { .nskip <- .nskip + 1L; cat(sprintf("[RP_AUTO_0806_2606] %s 적격 %d종 — 다리 구성 불가\n", .ym(mi), n)); next }
  w <- numeric(n)
  w[o[seq_len(kl)]] <- 1 / kl
  w[o[(n - ks + 1L):n]] <- w[o[(n - ks + 1L):n]] - 1 / ks
  .tranche[[as.character(mi)]] <- data.table(Ticker = pr$tk, W = w)[W != 0]

  .diag[[length(.diag) + 1L]] <- data.table(
    Date = pr$d, N = n, n_train = fit$n_tr, n_val = fit$n_val, hsel = fit$hsel, n_heads = fit$n_heads,
    ep_med = fit$ep_med, ep_run = fit$ep_run, ecov = pr$ecov, kl = kl, ks = ks,
    mv4 = fit$mv[1L], mv8 = fit$mv[2L], mv16 = fit$mv[3L])
  cat(sprintf(paste0("[RP_AUTO_0806_2606] %s | N=%d train=%d(+%d val) | 이익입력 보유율 %.0f%% | ",
                     "valMSE h4/h8/h16 = %.3f/%.3f/%.3f → h=%d (헤드 %d · 최적 에폭 중앙 %d · 실행 %d) | L%d/S%d | %.1f분\n"),
              as.character(pr$d), n, fit$n_tr, fit$n_val, 100 * pr$ecov,
              fit$mv[1L], fit$mv[2L], fit$mv[3L], fit$hsel, fit$n_heads, fit$ep_med, fit$ep_run, kl, ks,
              as.numeric(difftime(Sys.time(), .t0, units = "mins"))))

  # 집계 = 최근 3개 월간 시작점 트랜치의 평균 (논문: results are averaged over all three possible monthly starting points)
  if (mi >= .MI_OUT0) {
    parts <- lapply(0L:(.HOLD_M - 1L), function(j) .tranche[[as.character(mi - j)]])
    parts <- Filter(Negate(is.null), parts)
    if (length(parts)) {
      agg <- rbindlist(parts)[, .(Weight = sum(W) / length(parts)), by = Ticker][abs(Weight) > 1e-12]
      if (nrow(agg))
        .rows_p[[length(.rows_p) + 1L]] <- data.table(
          Date = pr$d, Ticker = agg$Ticker, Weight = agg$Weight,
          Leg = ifelse(agg$Weight > 0, "long", "short"), n_tranche = length(parts))
    }
  }
}

# =============================================================================
# 7. PORTFOLIO · FACTORS 조립 · 검산 · 요약
# =============================================================================
if (length(.rows_p) == 0L)
  stop(sprintf("[RP_AUTO_0806_2606] 발행 행 0 — 미발행 월 %d (입력 행렬 %d개월)", .nskip, length(.pre)))
PORTFOLIO <- rbindlist(.rows_p, use.names = TRUE)
PORTFOLIO <- PORTFOLIO[Date >= .SIG_FROM]
if (nrow(PORTFOLIO) == 0L) stop("[RP_AUTO_0806_2606] 고정 축 시작 이후 행 0")
setorder(PORTFOLIO, Date, Leg, Ticker)
FACTORS <- rbindlist(.rows_f, use.names = TRUE)
FACTORS <- FACTORS[is.finite(Score)]
setorder(FACTORS, Date, Ticker)

.chk <- PORTFOLIO[, .(net = sum(Weight), gl = sum(Weight[Weight > 0]), gs = -sum(Weight[Weight < 0]),
                      nt = n_tranche[1L]), by = Date]
.bad <- .chk[abs(net) > 1e-9]
if (nrow(.bad) > 0L)
  stop(sprintf("[RP_AUTO_0806_2606] 달러중립 검산 실패 %d건 (예: %s net %.6f)",
               nrow(.bad), as.character(.bad$Date[1L]), .bad$net[1L]))
.dupw <- sum(duplicated(PORTFOLIO, by = c("Date", "Ticker")))
if (.dupw > 0L) stop(sprintf("[RP_AUTO_0806_2606] (Date,Ticker) 중복 %d", .dupw))
.dupf <- sum(duplicated(FACTORS, by = c("Date", "Ticker")))
if (.dupf > 0L) stop(sprintf("[RP_AUTO_0806_2606] FACTORS (Date,Ticker) 중복 %d", .dupf))

.DIAG <- rbindlist(.diag, use.names = TRUE)
.pm <- PORTFOLIO[, .(nL = sum(Leg == "long"), nS = sum(Leg == "short")), by = Date]
cat(sprintf(paste0("[RP_AUTO_0806_2606] faithful: 20입력(가격 10분기 + 이익 10분기 순위 [−1,1] · 이익 30%% 무작위 제거) → ",
                   "단일 은닉층 역전파 MLP(초기화 %d × 은닉 %s · 검증 조기종료 · under-fit 선택) · 직전 %d분기 학습 → ",
                   "예측 내림차순 T%d 롱 / B%d 숏 EW · 1분기 보유 · 월간 시작점 3개 평균(중첩 트랜치)\n",
                   "  시그널 월 %d개 (%s ~ %s) · 미발행 %d · 발행 월 %d개 (%s ~ %s) · 행 %d\n",
                   "  적격 N %d~%d · 다리 %d~%d종(트랜치) · 집계 보유 롱 %d~%d / 숏 %d~%d · 최대 %d종 · ",
                   "선택 은닉 h4/h8/h16 = %d/%d/%d회 · 이익입력 보유율 중앙 %.0f%% · %.1f분\n",
                   "  ★러너 사양 = FIDELITY.json portfolio_spec (engine_direct) · commission_paper = null (논문 비용 무명시 → gross 병기)\n"),
            .N_INIT, paste(.HID, collapse = "/"), .N_TRAINQ, .N_TOP, .N_BOT,
            nrow(.DIAG), as.character(min(.DIAG$Date)), as.character(max(.DIAG$Date)), .nskip,
            uniqueN(PORTFOLIO$Date), as.character(min(PORTFOLIO$Date)), as.character(max(PORTFOLIO$Date)), nrow(PORTFOLIO),
            min(.DIAG$N), max(.DIAG$N), min(.DIAG$kl), max(.DIAG$kl),
            min(.pm$nL), max(.pm$nL), min(.pm$nS), max(.pm$nS), max(.pm$nL + .pm$nS),
            sum(.DIAG$hsel == 4L), sum(.DIAG$hsel == 8L), sum(.DIAG$hsel == 16L), 100 * median(.DIAG$ecov),
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
PORTFOLIO[, n_tranche := NULL]
PORTFOLIO <- PORTFOLIO[, .(Date, Ticker, Weight, Leg)]
FACTORS   <- FACTORS[, .(Date, Ticker, Score)]
