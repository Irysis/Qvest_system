# ==============================================================================
# RP_AUTO_CLEAN_1810_08384 — engine.R
# Paper  : S. Ciliberti & S. Gualdi, "Portfolio Construction Matters" (arXiv:1810.08384v1)
# Cell   : Markowitz construction, k = 5 statistical factors
#          (§III — "the Markowitz solution, with k=5 statistical factors ... has the
#           highest Sharpe Ratio (1.19)"; FF is the worst at 0.34)
# Signal : classical 12-1 momentum → cross-sectional rank → predictor p uniform on [-1,+1] (§II)
# Build  : x ∝ C^{-1} p,  C_ij ≈ σ_iσ_j(Σ_{α≤k} λ^α v^α_i v^α_j + ε² δ_ij)   (§II Eq. 4)
# Output : PORTFOLIO(Date, Ticker, Weight, Leg) — signed weights = the paper's own x_i.
#          Long-short, so construction = "engine_direct" (see FIDELITY.json::portfolio_spec).
#
# ★선언·근거·논문과의 편차는 FIDELITY.json 이 정본이다. 이 주석은 요약일 뿐이다.
# PIT: 모든 창의 종점은 결정일 d(체결 = 익월 첫 거래일 종가 · close_t1). 전표본 통계 없음 —
#      변동성·상관·고유벡터·횡단면 순위·총노출 정규화 전부 날짜별 후방 창에서만 계산한다.
#      shift(-1)·미래 인덱싱·전표본 cov()/mean() 없음(구조로 보장 — 창 날짜는 all_dates[.. <= d] 에서만 뽑는다).
# ==============================================================================

library(data.table)

## ---- 상수 — 전부 FIDELITY.json::constants 에 신고 ---------------------------
MOM_TOTAL_M    <- 12L     # paper §II "past 12 months"
MOM_SKIP_M     <- 1L      # paper §II "the last month is taken away"
MOM_WINDOW_M   <- MOM_TOTAL_M - MOM_SKIP_M   # 11 — (d-12m, d-1m]
MOM_MIN_MONTHS <- MOM_WINDOW_M               # supplement — 창 전 구간 존재 요건
COV_WINDOW_D   <- 500L    # supplement — paper §II "at least two years of ... daily returns" 의 거래일 환산
COV_MIN_OBS    <- 250L    # supplement — 종목별 최소 관측(= 창의 절반) · 창 길이 자체의 하한도 겸함
K_FACTORS      <- 5L      # paper §III — Markowitz k=5
P_LO           <- -1      # paper §II — predictor uniformly distributed in [-1,+1]
P_HI           <-  1      # paper §II
MIN_STOCKS     <- 50L     # supplement — k=5 고유분해·ε² 가 성립할 최소 횡단면(= 10 × K_FACTORS)
RET_CLIP       <- 0.5     # supplement — 데이터 오류·미조정 분할 방어(한국 가격제한폭 밖이라 정상 수익 불변)
VOL_MIN_DAILY  <- 1e-4    # supplement — 상관 정의 불가 종목 제외(거래정지·상한가 고정)
EPS2_MIN       <- 1e-6    # supplement — ε² 분모 가드
EIG_MIN        <- 1e-10   # supplement — 양의 고유값 판정 하한
WEIGHT_MIN     <- 1e-8    # supplement — 수치 잔여 비중 행 제거
HIST_PAD_D     <- 1500L   # supplement — 사전 이력 적재 상한(필요 창보다 길어 결과 불변 · 메모리 상한)

## ---- 입력 ------------------------------------------------------------------
stopifnot(exists("RAWDATA"))
RD <- as.data.table(RAWDATA)
if (!inherits(RD$Date, "Date")) RD[, Date := as.Date(Date)]
if (!all(c("Date", "Ticker", "Ret", "K200", "KQ150") %in% names(RD)))
  stop("[1810.08384] RAWDATA 에 Date/Ticker/Ret/K200/KQ150 필요")

# 신호 시작 = 호출자가 주는 측정 축 시작(리터럴 금지). 후방 창은 그 이전 이력을 쓸 수 있다(과거 데이터).
.SIG_FROM <- if (exists(".RP_START_DATE", inherits = TRUE)) as.Date(.RP_START_DATE) else min(RD$Date)

## 유니버스 = 측정 축이 주입한 멤버십(H1·H2) — 엔진은 거르기만 한다
MEM <- unique(RD[(K200 == 1 | KQ150 == 1), .(Date, Ticker = as.character(Ticker))])
setkey(MEM, Date)

## 일간 수익(RAWDATA$Ret = 종가-종가 일간 수익 · 하네스 leg 산출과 같은 열)
RT <- RD[Date >= (.SIG_FROM - HIST_PAD_D) & is.finite(Ret),
         .(Date, Ticker = as.character(Ticker), Ret = as.numeric(Ret))]
RT[, Ret := pmax(pmin(Ret, RET_CLIP), -RET_CLIP)]

## 월간 복리 수익 — 모멘텀 창 집계용. 월 단위 곱 = 그 달 일간 곱(항등 · 근사 아님)
MONR <- RT[, .(mret = prod(1 + Ret) - 1), by = .(Ticker, ym = year(Date) * 12L + month(Date))]
setkey(MONR, ym)
setkey(RT, Date)

## 신호일 = 월말 거래일(RAWDATA 격자) — 월간 리밸(하네스 EXEC = 익월 첫 거래일)
all_dates <- sort(unique(RD$Date))
ME <- data.table(Date = all_dates)[, .(Date = max(Date)), by = .(ym = year(Date) * 12L + month(Date))]
sig_dates <- sort(ME[Date >= .SIG_FROM, Date])

## ---- 라운드 루프 -----------------------------------------------------------
out <- vector("list", length(sig_dates))

for (ii in seq_along(sig_dates)) {
  d    <- sig_dates[ii]
  ym_d <- year(d) * 12L + month(d)

  ## (1) 그 신호일의 유니버스 멤버십
  uni <- MEM[.(d), nomatch = 0L]$Ticker
  if (length(uni) < MIN_STOCKS) next

  ## (2) 모멘텀 — (d-12개월, d-1개월] 누적수익. 당월 제외 = §II 의 1개월 lag
  mwin <- seq.int(ym_d - MOM_TOTAL_M + 1L, ym_d - MOM_SKIP_M)   # ym(d)-11 .. ym(d)-1
  mm <- MONR[.(mwin), nomatch = 0L][Ticker %chin% uni,
             .(mom = prod(1 + mret) - 1, nmo = .N), by = Ticker]
  mm <- mm[nmo >= MOM_MIN_MONTHS & is.finite(mom)]
  if (nrow(mm) < MIN_STOCKS) next

  ## (3) 공분산 창 — d 까지의 마지막 COV_WINDOW_D 거래일 (종점 = 결정일 d)
  idx_d <- match(d, all_dates)
  wdt   <- all_dates[max(1L, idx_d - COV_WINDOW_D + 1L):idx_d]
  Tn    <- length(wdt)
  if (Tn < COV_MIN_OBS) next

  win <- RT[.(wdt), nomatch = 0L][Ticker %chin% mm$Ticker]
  if (!nrow(win)) next

  tks <- sort(unique(win$Ticker))
  M <- matrix(NA_real_, nrow = Tn, ncol = length(tks))
  M[cbind(match(win$Date, wdt), match(win$Ticker, tks))] <- win$Ret

  nobs <- colSums(!is.na(M))
  cmu  <- colMeans(M, na.rm = TRUE)
  Mc   <- M - rep(cmu, each = Tn)
  csd  <- sqrt(colSums(Mc * Mc, na.rm = TRUE) / pmax(nobs - 1L, 1L))

  keep <- nobs >= COV_MIN_OBS & is.finite(csd) & csd >= VOL_MIN_DAILY
  if (sum(keep) < MIN_STOCKS) next
  tks <- tks[keep]; Mc <- Mc[, keep, drop = FALSE]
  nobs <- nobs[keep]; csd <- csd[keep]
  Nn <- length(tks)

  ## 표준화: 결측일 = 편차 0 · 열 2차모멘트를 (T-1) 로 맞춰 상관행렬 대각을 정확히 1 로
  ##   (식 4 의 Tr 조건이 성립할 자리를 만든다 — σ_i 는 아래에서 정직한 표본표준편차를 쓴다)
  Z <- Mc / rep(csd, each = Tn)
  Z[!is.finite(Z)] <- 0
  Z <- Z * rep(sqrt((Tn - 1) / pmax(nobs - 1L, 1L)), each = Tn)

  ## (4) 상관행렬 상위 k 고유모드 — N > T 이므로 그램행렬(T×T)로 푼다.
  ##     R = Z'Z/(T-1) 과 G = ZZ'/(T-1) 의 0 아닌 고유값은 같고, v^α = Z'u^α / sqrt((T-1)λ_α).
  G  <- tcrossprod(Z) / (Tn - 1)
  eg <- tryCatch(eigen(G, symmetric = TRUE), error = function(e) NULL)
  if (is.null(eg)) next
  kmax <- min(K_FACTORS, Tn - 1L, Nn - 1L)
  lam  <- eg$values[seq_len(kmax)]
  kk   <- sum(is.finite(lam) & lam > EIG_MIN)     # 내림차순이라 통과분 = 선두 블록
  if (kk < 1L) next
  lam <- lam[seq_len(kk)]
  V   <- crossprod(Z, eg$vectors[, seq_len(kk), drop = FALSE]) /
           rep(sqrt((Tn - 1) * lam), each = Nn)

  ## 식 (4) 의 ε² — "chosen such that the total variance is unchanged": Tr R = N 유지
  eps2 <- max((Nn - sum(lam)) / Nn, EPS2_MIN)

  ## (5) 예측자 p — 횡단면 순위를 [-1,+1] 균등으로 (§II). 모멘텀 낮은→높은 순위이므로
  ##     승자(최고 모멘텀) = p 최대 = 롱, 패자 = 숏 (§I "buying past winners and selling past losers")
  mv <- mm$mom[match(tks, mm$Ticker)]
  r  <- rank(mv, ties.method = "average")
  p  <- P_LO + (P_HI - P_LO) * (r - 0.5) / Nn

  ## (6) 마코위츠 해 x ∝ C^{-1}p. C = D(VΛV' + ε²I)D 이므로 Woodbury 로 역행렬 없이 닫힌형:
  ##     x = D^{-1}(1/ε²)(I - VΓV')D^{-1}p,  Γ = diag(λ_α/(λ_α+ε²)).
  ##     스칼라 1/ε² 는 아래 날짜별 총노출 정규화에서 소거되므로 생략한다.
  sig <- csd
  qv  <- p / sig
  gam <- lam / (lam + eps2)
  xv  <- (qv - as.vector(V %*% (gam * as.vector(crossprod(V, qv))))) / sig

  ## (7) 비중 — 리밸마다 총노출 Σ|w| = 1 로 정규화.
  ##     논문의 "rescaled to have the same average risk over the total back-test period" 는
  ##     전표본 통계(C1) 라 쓸 수 없다. 순노출(Σw)은 0 으로 강제하지 않는다 — 마코위츠 칸에는
  ##     β·현금 중립 제약이 없고 순노출이 0 근방에서 변동하는 것이 논문 Fig.3 의 산출이다.
  gs <- sum(abs(xv))
  if (!is.finite(gs) || gs <= 0) next
  w <- xv / gs
  sel <- is.finite(w) & abs(w) > WEIGHT_MIN
  if (sum(sel) < MIN_STOCKS) next

  out[[ii]] <- data.table(Date = d, Ticker = tks[sel], Weight = w[sel],
                          Leg = ifelse(w[sel] > 0, "long", "short"))
}

## ---- 산출 ------------------------------------------------------------------
PORTFOLIO <- rbindlist(Filter(Negate(is.null), out), use.names = TRUE)
if (!nrow(PORTFOLIO))
  stop("[1810.08384] PORTFOLIO 0행 — 유니버스/이력 요건(COV_MIN_OBS·MOM_MIN_MONTHS) 확인")
setorder(PORTFOLIO, Date, Ticker)

cat(sprintf("[1810.08384] Markowitz k=%d · %d 리밸(%s ~ %s) · 신호일 평균 %d종(롱 %.0f%%)\n",
            K_FACTORS, uniqueN(PORTFOLIO$Date), min(PORTFOLIO$Date), max(PORTFOLIO$Date),
            round(nrow(PORTFOLIO) / uniqueN(PORTFOLIO$Date)),
            100 * mean(PORTFOLIO$Weight > 0)))
