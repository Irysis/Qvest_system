# ==============================================================================
# RP_AUTO_CLEAN_1810_08384 — engine.R  (재구현 r2 — 앞 판 engine.rejected1.R 기각 수정)
# Paper  : S. Ciliberti & S. Gualdi, "Portfolio Construction Matters" (arXiv:1810.08384v1)
# Cell   : Markowitz construction, k = 5 statistical factors
#          (§III — "the Markowitz solution, with k=5 statistical factors ... has the
#           highest Sharpe Ratio (1.19)"; FF 칸이 최악 0.34)
# Signal : §V 의 **유일한 명시식** — "Momentum: we compute 230 days rolling average
#          returns (lagged by 1 month) and rank from lowest to highest"
#          = 230 거래일 **일별 수익 산술평균**(1개월 지연) → 오름차순 순위
#          → 예측자 p 가 [-1,+1] 균등 (§II)
#          ★앞 판은 §I 산문("cumulative performance ... past 12 months, last month
#            taken away")을 복리 누적으로 구현했고 감사가 기각했다. §I 은 문헌 관행
#            서술이고 모멘텀 계산식은 §V 뿐이다 — 230 거래일 ≈ 11개월이라 §V 는 §I 의
#            12-1 창을 정밀하게 쓴 것과 같은 창이고, 다른 것은 집계(평균 vs 복리)뿐이다.
# Build  : x ∝ C^{-1} p,  C_ij ≈ σ_iσ_j(Σ_{α≤k} λ^α v^α_i v^α_j + ε² δ_ij)   (§II 식 4)
#          ★마코위츠 해 x_i ∝ C^{-1}p_i 는 §II 의 **번호 없는** 식이다(식 (2)(3) 은
#            Betaopt 의 β-중립 해이고 이 엔진은 그 칸을 구현하지 않는다).
# Output : PORTFOLIO(Date, Ticker, Weight, Leg) — 부호 있는 비중 = 논문의 x_i 그대로.
#          롱숏이므로 construction = "engine_direct" (FIDELITY.json::portfolio_spec).
#
# ★선언·근거·논문과의 편차는 FIDELITY.json 이 정본이다. 이 주석은 요약일 뿐이다.
# PIT: 모든 창의 종점은 결정일 d(집행 = 다음 거래일 종가 · close_t1). 전표본 통계 없음 —
#      평균·변동성·상관·고유벡터·횡단면 순위·총노출 정규화 전부 날짜별 후방 창에서만 계산한다.
#      shift(-1)·미래 인덱싱·전표본 cov()/mean() 없음(구조로 보장 — 창 인덱스는 전부
#      거래일 격자에서 <= id 범위만 뽑고, 모멘텀 창 종점은 d 보다 1개월 더 이르다).
# ==============================================================================

library(data.table)

## ---- 상수 — 전부 FIDELITY.json::constants 에 신고 ---------------------------
MOM_WINDOW_D   <- 230L    # paper §V "230 days rolling average returns" (거래일)
MOM_LAG_M      <- 1L      # paper §V "(lagged by 1 month)" · §I "lagged by (at least) one month"
COV_WINDOW_D   <- 500L    # supplement — §II "at least two years of ... daily returns" 거래일 환산
K_FACTORS      <- 5L      # paper §III — Markowitz k = 5
P_LO           <- -1      # paper §II — predictor uniformly distributed in [-1,+1]
P_HI           <- 1       # paper §II — 같은 문장의 상한
MIN_STOCKS     <- 50L     # supplement — k=5 고유분해·ε² 가 성립할 최소 횡단면(= 10 × K_FACTORS)
RET_CLIP       <- 0.5     # supplement — 데이터 오류·미조정 분할 방어(한국 가격제한폭 밖)
VOL_MIN_DAILY  <- 1e-4    # supplement — 상관·1/σ 정의 불가 종목 제외
EPS2_MIN       <- 1e-6    # supplement — ε² 하한(1/(λ+ε²) 분모 가드)
EIG_MIN        <- 1e-10   # supplement — 양의 고유값 판정 하한
WEIGHT_MIN     <- 1e-8    # supplement — 수치 잔여 비중 행 제거
HIST_PAD_D     <- 1500L   # supplement — 사전 이력 적재 상한(필요 창보다 길어 결과 불변)
WK_EPOCH_SHIFT <- 3L      # harness — 1970-01-01 = 목요일 → 월요일 시작 주 분할 보정
WK_LEN_D       <- 7L      # harness — 주 길이(일)
MONTHS_PER_Y   <- 12L     # harness — 캘린더 월 되돌림 산술(달력 사실)
RANK_MID_ADJ   <- 0.5     # supplement — 순위 중앙 보정 (r − 0.5)/N · 논문 미명시

## ---- 입력 ------------------------------------------------------------------
stopifnot(exists("RAWDATA"))
RD <- as.data.table(RAWDATA)
if (!all(c("Date", "Ticker", "Ret", "K200", "KQ150") %in% names(RD)))
  stop("[1810.08384] RAWDATA 에 Date/Ticker/Ret/K200/KQ150 필요")
if (!inherits(RD$Date, "Date")) RD <- copy(RD)[, Date := as.Date(Date)]

# 신호 시작 = 호출자가 주는 측정 축 시작(리터럴 금지). 후방 창은 그 이전 이력을 쓴다(과거 데이터).
.SIG_FROM <- if (exists(".RP_START_DATE", inherits = TRUE)) as.Date(.RP_START_DATE) else min(RD$Date)

## 거래일 격자
all_dates <- sort(unique(RD$Date))
nD <- length(all_dates)

## 일간 수익 패널(RAWDATA$Ret = 종가-종가 일간수익 · 하네스 leg 산출과 같은 열)
RT <- RD[Date >= (.SIG_FROM - HIST_PAD_D) & is.finite(Ret),
         .(Date, Ticker = as.character(Ticker), Ret = as.numeric(Ret))]
RT[, Ret := pmax(pmin(Ret, RET_CLIP), -RET_CLIP)]
TKS <- sort(unique(RT$Ticker)); n_tk <- length(TKS)
RT[, di := match(Date, all_dates)]
RT[, tid := match(Ticker, TKS)]
RT <- unique(RT, by = c("di", "tid"))          # 방어: (날짜,종목) 중복 행 제거(통상 무연산)
setorder(RT, di, tid)
## 거래일별 행 구간 — 창 추출을 연속 슬라이스로(결과 불변 · 속도)
off_end <- cumsum(tabulate(RT$di, nbins = nD))
V_di <- RT$di; V_tid <- RT$tid; V_ret <- RT$Ret

## 유니버스 = 측정 축이 주입한 멤버십(H1·H2) — 엔진은 거르기만 한다
MEM <- unique(RD[(K200 == 1 | KQ150 == 1),
                 .(di = match(Date, all_dates), tid = match(as.character(Ticker), TKS))])
MEM <- MEM[!is.na(tid)]
setkey(MEM, di)

## ---- 신호일 = 각 주(월요일 시작)의 마지막 거래일 ---------------------------
##   논문 §II "the portfolio is rebalanced on a daily basis". 하네스(H10)는 일간 신호를
##   ISO 주마다 마지막 1개로 접으므로, 주 마지막 거래일만 내면 산출이 같다(계산량만 줄인다).
wkid <- (as.integer(all_dates) + WK_EPOCH_SHIFT) %/% WK_LEN_D
sig_idx <- which(c(wkid[-1L] != wkid[-nD], TRUE) & all_dates >= .SIG_FROM)
if (!length(sig_idx)) stop("[1810.08384] 신호일 0개 — .RP_START_DATE / RAWDATA 범위 확인")

## 모멘텀 1개월 지연 종점 = 마지막 거래일 <= (d − 1개월). 월말 넘침은 그 달 말일로 cap.
sdt <- all_dates[sig_idx]
yy <- as.integer(format(sdt, "%Y")); mm <- as.integer(format(sdt, "%m"))
dd <- as.integer(format(sdt, "%d"))
m2 <- mm - MOM_LAG_M; y2 <- yy
.b <- m2 < 1L; m2[.b] <- m2[.b] + MONTHS_PER_Y; y2[.b] <- y2[.b] - 1L
m3 <- m2 + 1L; y3 <- y2
.c <- m3 > MONTHS_PER_Y; m3[.c] <- 1L; y3[.c] <- y3[.c] + 1L
f_lag <- as.Date(sprintf("%04d-%02d-01", y2, m2))
f_nxt <- as.Date(sprintf("%04d-%02d-01", y3, m3))
lag_idx <- findInterval(f_lag + (pmin(dd, as.integer(f_nxt - f_lag)) - 1L), all_dates)

## ---- 라운드 루프 -----------------------------------------------------------
Tn  <- COV_WINDOW_D
out <- vector("list", length(sig_idx))

for (ii in seq_along(sig_idx)) {
  id <- sig_idx[ii]      # 결정일(신호일) 인덱스
  il <- lag_idx[ii]      # 모멘텀 창 종점 인덱스(= 1개월 지연)
  i1 <- id - COV_WINDOW_D + 1L          # 공분산 창 시작 · 종점 = id
  r1 <- il - MOM_WINDOW_D + 1L          # 모멘텀 창 시작 · 종점 = il
  # 이력 부족 · 모멘텀 창이 공분산 창을 벗어나는 날은 산출 없음(하네스 H5 로 직전 보유 이월)
  if (i1 < 1L || il < 1L || il > id || r1 < i1) next

  ## (1) 그 신호일의 유니버스 멤버십
  uni <- MEM[.(id), nomatch = 0L]$tid
  nu <- length(uni)
  if (nu < MIN_STOCKS) next

  ## (2) 일간 수익 행렬 [공분산 창 × 멤버] — 완전 관측(500 거래일 전부) 열만 남긴다
  ##     §II "at least two years of historical close-to-close daily returns" 를 종목별
  ##     요건으로 읽는다 → 결측 대체가 필요 없고 상관행렬 대각이 정확히 1 이 된다.
  ##     모멘텀 창 ⊂ 공분산 창 이므로 두 레그의 실효 구간이 종목마다 다르지 않다.
  rf <- if (i1 > 1L) off_end[i1 - 1L] + 1L else 1L
  re <- off_end[id]
  if (re < rf) next
  sl <- rf:re
  posv <- integer(n_tk); posv[uni] <- seq_len(nu)
  cv <- posv[V_tid[sl]]
  hit <- which(cv > 0L)
  if (!length(hit)) next
  ar <- sl[hit]; cc <- cv[hit]
  M <- matrix(NA_real_, Tn, nu)
  M[(cc - 1L) * Tn + (V_di[ar] - i1 + 1L)] <- V_ret[ar]
  keep <- tabulate(cc, nbins = nu) == Tn
  if (sum(keep) < MIN_STOCKS) next
  M <- M[, keep, drop = FALSE]
  tk <- uni[keep]

  ## (3) 식 4 의 σ_i · 상관용 평균 — 같은 창의 표본값(분모 T−1)
  cmu <- colMeans(M)
  Mc <- M - rep(cmu, each = Tn)
  csd <- sqrt(colSums(Mc * Mc) / (Tn - 1L))
  gd <- is.finite(csd) & csd >= VOL_MIN_DAILY
  if (sum(gd) < MIN_STOCKS) next

  ## (4) 모멘텀 = 230 거래일 일별 수익 **산술평균**(1개월 지연) — §V
  mom <- colMeans(M[(r1 - i1 + 1L):(il - i1 + 1L), gd, drop = FALSE])
  Mc <- Mc[, gd, drop = FALSE]; csd <- csd[gd]; tk <- tk[gd]
  nn <- length(tk)

  ## (5) 상관행렬 상위 k 고유모드 (§II "we only keep the k largest eigenvectors").
  ##     N > T 이므로 그램행렬(T×T)로 푼다 — R = Z'Z/(T−1) 과 G = ZZ'/(T−1) 의 0 아닌
  ##     고유값은 같고 v^α = Z'u^α / sqrt((T−1)λ_α) (수학적 항등 · V'V = I).
  Z <- Mc / rep(csd, each = Tn)
  G <- tcrossprod(Z) / (Tn - 1L)
  eg <- tryCatch(eigen(G, symmetric = TRUE), error = function(e) NULL)
  if (is.null(eg)) next
  kmx <- min(K_FACTORS, Tn - 1L, nn - 1L)
  lam <- eg$values[seq_len(kmx)]
  nk <- sum(is.finite(lam) & lam > EIG_MIN)   # 내림차순이라 통과분 = 선두 블록
  if (nk < 1L) next
  lam <- lam[seq_len(nk)]
  Vm <- crossprod(Z, eg$vectors[, seq_len(nk), drop = FALSE]) /
          rep(sqrt((Tn - 1L) * lam), each = nn)

  ## (6) 식 4 의 ε² — §II "chosen such that the total variance of the portfolio is
  ##     unchanged, i.e. Tr C = Σ_i σ_i²" 의 정확해:
  ##     Tr C = Σ_i σ_i²(Σ_α λ^α (v^α_i)² + ε²) = Σ_i σ_i²
  ##       → ε² = 1 − Σ_i σ_i²(Σ_α λ^α (v^α_i)²) / Σ_i σ_i²
  v2 <- csd * csd
  ex <- as.vector((Vm * Vm) %*% lam)
  eps2 <- max(1 - sum(v2 * ex) / sum(v2), EPS2_MIN)

  ## (7) 예측자 p — 횡단면 **오름차순** 순위를 [-1,+1] 균등으로 (§II 균등 예측자 ·
  ##     §V "rank from lowest to highest"). 승자(최고 모멘텀) = p 최대 = 롱,
  ##     패자 = 숏 (§I "buying past winners and selling past losers").
  rk <- rank(mom, ties.method = "average")
  p <- P_LO + (P_HI - P_LO) * (rk - RANK_MID_ADJ) / nn

  ## (8) 마코위츠 해 x ∝ C^{-1}p. C = D(VΛV' + ε²I)D 이므로 Woodbury 로 역행렬 없이:
  ##     x = D^{-1}(1/ε²)(I − VΓV')D^{-1}p,  Γ = diag(λ_α/(λ_α+ε²)).
  ##     스칼라 1/ε² 는 아래 (9) 날짜별 총노출 정규화에서 소거되므로 생략한다.
  qv <- p / csd
  gam <- lam / (lam + eps2)
  xv <- (qv - as.vector(Vm %*% (gam * as.vector(crossprod(Vm, qv))))) / csd

  ## (9) 비중 — 리밸마다 총노출 Σ|w| = 1 로 정규화(단일 스칼라 · 횡단면 구성 불변).
  ##     논문의 "rescaled in order to have the same average risk over the total
  ##     back-test period" 는 전표본 통계(C1)라 쓸 수 없다. 순노출(Σw)은 0 으로
  ##     강제하지 않는다 — 마코위츠 칸에는 β·현금 중립 제약이 없고 순노출이 0 근방에서
  ##     변동하는 것이 논문 Fig.3 의 산출이다.
  gs <- sum(abs(xv))
  if (!is.finite(gs) || gs <= 0) next
  w <- xv / gs
  s3 <- is.finite(w) & abs(w) > WEIGHT_MIN
  if (sum(s3) < MIN_STOCKS) next

  out[[ii]] <- data.table(Date = all_dates[id], Ticker = TKS[tk[s3]], Weight = w[s3],
                          Leg = ifelse(w[s3] > 0, "long", "short"))
}

## ---- 산출 ------------------------------------------------------------------
PORTFOLIO <- rbindlist(Filter(Negate(is.null), out), use.names = TRUE)
if (!nrow(PORTFOLIO))
  stop("[1810.08384] PORTFOLIO 0행 — 완전관측 500거래일 · 멤버 하한 요건 확인")
setorder(PORTFOLIO, Date, Ticker)

cat(sprintf("[1810.08384] Markowitz k=%d · 주간 리밸 %d회(%s ~ %s) · 신호일 평균 %d종(롱 %.0f%%)\n",
            K_FACTORS, uniqueN(PORTFOLIO$Date), min(PORTFOLIO$Date), max(PORTFOLIO$Date),
            round(nrow(PORTFOLIO) / uniqueN(PORTFOLIO$Date)),
            100 * mean(PORTFOLIO$Weight > 0)))
