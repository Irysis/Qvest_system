# =============================================================================
# engine.R — RP_AUTO_1806_01743  (3판 · 2026-09-15 — 1판 = 자체 DNN 기울기 검산 중단 · 2판 = 자체 AUC 검산 중단 → 재구현)
# XingYu Fu · JinHong Du · YiFeng Guo · MingWen Liu · Tao Dong · XiuWen Duan,
#   "A Machine Learning Framework for Stock Selection"  arXiv:1806.01743 (2018-06)
#   https://arxiv.org/abs/1806.01743 — 본문 = r.jina.ai PDF 텍스트 프록시(2018 논문 · arxiv html 렌더 없음)
#
# ★라벨(adapted)·변경 전수 신고·러너 사양의 정본 = FIDELITY.json. 이 주석은 아무것도 결정하지 않는다.
#   코드 옆 ★changed(n) 표식 = FIDELITY.json changed 의 항목 번호.
#
# ★1판 중단 원인(재도출): 1판 검산은 n=9 · 특성 8 · BN 유닛 2 인 임의 지점에서 h=1e-5 중심차분을 썼다. 배치 9행짜리 BN 열의
#   분산이 eps(1e-3) 근처까지 작아지면 정규화 함수의 3계 도함수가 (분산+eps)^{-5/2} ≈ 1e7 로 커져 중심차분의 절단오차
#   (h²/6·f''')가 기울기 자체와 같은 자릿수가 된다 — 역전파 식은 옳았고(2판에서 BN·드롭아웃·softmax CE·L2 전 경로 재유도)
#   검산 지점이 병적이었다. 2판 검산: n=64 · 특성 24 · 편향·감마 무작위 지점 · BN 열 분산 ≥ 0.05 · |Z1|,|Z2| ≥ 1e-4(ReLU 꺾임
#   여유) 인 시드를 골라 h=1e-6 중심차분 · 벡터 노름 상대오차 ≤ 1e-5 ∧ 성분 상대오차(바닥 = 최대 기울기의 1e-3) ≤ 1e-3.
#   모델·학습 경로는 1판과 동일 — 바뀐 것은 검산 설계와 메모리 경로(§4 종목별 월말 추출)·§3 격자 시작·롤링 창 커버리지 규약뿐이다.
# ★2판 중단 원인(재도출): 2판 §2 의 AUC 검산 픽스처 — 점수 (0.9, 0.8, 0.7, 0.2, 0.1) · 라벨 (1,1,0,0,0) — 는 양성 둘(0.9 · 0.8)이 음성
#   셋(0.7 · 0.2 · 0.1)을 전부 이기므로 Mann–Whitney AUC = 6/6 = 1 인데, 기대값을 5/6 으로 손계산해 두었다. .auc(순위식)는 옳았고
#   기대값이 틀렸다 — 1판과 같은 종류의 병(계기 자체의 조건)이다. 3판 검산: 손계산 상수 하나에 기대지 않고 **독립 계산(양·음 쌍 전수
#   비교 · 동률 0.5)** 과 대조하며, 손으로 유도한 픽스처 4건(완전 분리 1 · 5/6 · 전 동률 1/2 · 완전 역전 0)은 유도 과정을 코드 옆에 적는다.
#   모델·학습·데이터 경로는 2판과 동일(무변경). ★2판 러너 실행이 §2 의 DNN·LR 기울기 검산과 학습 양성 대조를 통과했음은 실패 지점
#   (그 뒤 줄에서 죽었다)이 증명한다 — §3 이후 데이터 경로는 1·2판 모두 미실행이라 3판에서 정적으로 재대조했다(FIDELITY revision).
#
# 논문 기전(그대로): 종목 i 의 t 시점 특성벡터 X_i(t)(244 토큰 = 124 고유 이름 · Uqer 팩터 라이브러리 · 부록)에
#   [t+1, t+f] 구간의 return-to-volatility ratio y_i(t,f) 를 붙이고, 각 t 의 횡단면에서 상위 Q% = 1 · 하위 Q% = 0 ·
#   가운데 폐기(Tail and Head Label · 'To avoid data overlapping, at most ⌊2QTM/(100(1+f))⌋ samples can be labeled').
#   LR(SGD Nesterov 0.9 · η 1e-2 · decay 1e-6 · 20 epoch) · RF(100 trees · depth 4 · min split 2) ·
#   DNN(n → ⌊n/2⌋ ReLU Dropout 0.5 → ⌊n/4⌋ ReLU BN → 2 Softmax · L2 0.01 · SGD Nesterov η 1e-3 · decay 1e-6 · batch 128 ·
#   20 epoch) · Stacking(학습집합을 Train-1 · Train-2 · Validation 으로 3분할 → DNN = Train-1∪Train-2 · RF = Train-2 ·
#   메타 LR = Validation 위에서 (p_RF, p_DNN) 입력)으로 분류 → 모델 출력(0~1)로 포트폴리오를 만들어 시장평균과 비교.
#
# 이 구현(adapted — 사유 전부 FIDELITY.json): 논문이 인쇄하지 않는 Q · f · 재학습 · 전처리 · 포트폴리오 규칙은 고정 축
#   (월간 · 롱온리 25종 EW)과 명시 선택으로 채웠다 — f = 다음 달력월 거래일(보유 1개월) · Q = 25 · 학습집합 = 시그널 월말
#   이전 실현 완료된 최근 6개 월말 횡단면(논문 학습 구간 2012.08.08~2013.02.01 ≈ 6 개 비중첩 창) · 매 월말 재학습 ·
#   부록 이름 124종 중 112종을 RAWDATA(가격·거래량·시총) + 회계 패널(DART 연간 + QuantiWise 분기) + 컨센서스 패널에서
#   원값으로 계산 · 전처리 = 학습표본 1/99% winsorize → 학습표본 평균/표준편차 표준화 → 결측 0. GA 특성선택은 미구현(신고).
#
# 산출: FACTORS(Date, Ticker, Score) — 월말 시그널일 · 그날 K200∪KQ150 적격 종목 전부 · Score = Stacking 확률
#       (PORTFOLIO 없음 — 논문이 비중을 정의하지 않는다 → 러너 top_n_long 25 EW 월간 · FIDELITY portfolio_spec)
#
# PIT(C1~C15) 구조 보장: 시그널일 d_j = 달 j 마지막 거래일. 특성 = Date ≤ d_j 행만(일간 창 · 월말 회계 = usable ≤ d_j 인
#   최신 분기 · 컨센서스 = 관측 ≤ d_j). 학습 표본 = 횡단면 m ≤ j−1 (표적 = 달 m+1 수익 → d_{m+1} ≤ d_j 에 실현).
#   winsor·표준화 통계 = 그 달 학습표본만. 전 표본 통계 0건 · 팩터 DB 미사용(C13/C15 대상 코드 없음) ·
#   유동성 스크린 없음(논문 우선 · C10 대상 코드 없음). 집행 = 달 j+1 첫 거래일(러너 get_execution_date).
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(arrow)
  library(ranger)
  library(TTR)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(exists("BM_DT"), is.data.table(BM_DT))
.TAG <- "[RP_AUTO_1806_01743]"
.t0 <- Sys.time()
.REQ <- c("Date", "Ticker", "Open", "High", "Low", "Close", "Vol", "Size", "Ret", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("%s RAWDATA 필수 열 부재: %s", .TAG, paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))
if (!all(c("Date", "BM_Ret") %in% names(BM_DT))) stop(sprintf("%s BM_DT 필수 열 부재(Date, BM_Ret)", .TAG))

# =============================================================================
# 0. 상수 — 논문 명시값(모델) + 논문이 인쇄하지 않는 규약(전부 FIDELITY.json changed 신고)
# =============================================================================
.START      <- as.Date("2005-01-01")   # 고정 축 — 이 날 이후 시그널만 발행
.GRID_FROM  <- as.Date("2001-01-01")   # ★changed(1) 일간 격자 시작(첫 학습 횡단면 2004-07 의 504일 창 선행 · 발행 신호에 영향 없음)
.Q_PCT      <- 25                      # ★changed(2) Tail and Head Label 의 Q (논문 NOT STATED)
.K_CS       <- 6L                      # ★changed(3) 학습 횡단면 수 = 논문 학습 구간(2012.08.08~2013.02.01 ≈ 122 거래일) ÷ (1+f≈21)
.MIN_LABEL_DAYS <- 10L                 # ★changed(2) 표적 창 유효 일수 하한
.MIN_CS_N   <- 20L                     # ★changed(2) 횡단면 라벨링·예측 최소 종목수(상·하위 Q% 각 ≥ 5)
.WINSOR     <- c(0.01, 0.99)           # ★changed(6) 특성 winsorize(학습표본 분위)
.SEED_BASE  <- 18060174L               # ★changed(9) 시드 = 논문 번호(임의 상수) + 월 인덱스
# 모델 — 논문 §IV Table I · II · III · IV 명시값
.LR_LR  <- 1e-2; .LR_DECAY  <- 1e-6; .LR_MOM  <- 0.9; .LR_EPOCHS  <- 20L; .LR_BATCH  <- 128L   # LR batch = NOT STATED → DNN 값 (changed(8))
.DNN_LR <- 1e-3; .DNN_DECAY <- 1e-6; .DNN_MOM <- 0.9; .DNN_EPOCHS <- 20L; .DNN_BATCH <- 128L
.DNN_DROP <- 0.5; .DNN_L2 <- 0.01
.RF_TREES <- 100L; .RF_DEPTH <- 4L; .RF_MIN_NODE <- 1L                                         # sklearn min_samples_split 2 ⇔ 말단 1
.BN_MOM <- 0.99; .BN_EPS <- 1e-3                                                                # ★changed(8) Keras 기본값
.GC_TOL_NORM <- 1e-5; .GC_TOL_MAX <- 1e-3                                                       # 기울기 검산 허용오차(노름 · 성분)
# 특성 창 — 논문은 이름만 인쇄 · Uqer 규약/표준 기본값 (★changed(4)(5))
.MA_K <- c(5L, 10L, 20L, 60L, 120L); .VOL_K <- c(5L, 10L, 20L, 60L, 120L, 240L); .REVS_K <- c(5L, 10L, 20L)
.W_BETA <- 252L; .W_BETA_MIN <- 126L; .W_RSTR12 <- 252L; .W_RSTR24 <- 504L; .W_DHILO <- 60L
.RSI_N <- 14L; .MFI_N <- 14L; .PSY_N <- 12L; .WVAD_N <- 24L; .WVAD_M <- 6L; .VR_Q <- 10L; .CMRA_BLK <- 21L
.ROLL_MIN_FRAC <- 0.8                  # ★changed(5) 결측 허용 롤링 창의 유효 관측 하한(창의 80%)
.FUND_CARRY <- 400L; .CONS_CARRY <- 35L; .SUE_CARRY <- 130L; .REV_LAG_D <- 60L; .REV_LAG_G <- 20L
.MIN5 <- 3L                            # 5년 평균·EGRO 의 최소 연도 수
.TECH_FEATS <- c("MA5", "MA10", "MA20", "MA60", "MA120", "EMA5", "EMA10", "EMA20", "EMA60", "EMA120",
                 "VOL5", "VOL10", "VOL20", "VOL60", "VOL120", "VOL240", "DAVOL5", "DAVOL10", "DAVOL20",
                 "REVS5", "REVS10", "REVS20", "RSI", "MFI", "PSY", "WVAD", "MAWVAD", "DHILO", "RSTR12", "RSTR24",
                 "HBETA", "HSIGMA", "DDNBT", "DDNCR", "DDNSR", "DVRAT", "CMRA", "LCAP")
.REG_FEATS  <- c("HBETA", "HSIGMA", "DDNBT", "DDNCR", "DDNSR", "DVRAT", "CMRA")
.FUND_FEATS <- c("ASSI", "ROE", "ROA", "ROE5", "ROA5", "EGRO", "GrossIncomeRatio", "NetProfitRatio", "OperatingProfitRatio",
                 "SalesCostRatio", "AdminiExpenseRate", "FinancialExpenseRate", "EBITToTOR", "TaxRatio", "TotalProfitCostRatio",
                 "CashRateOfSales", "CashToCurrentLiability", "OperCashInToCurrentLiability", "NOCFToOperatingNI",
                 "EquityFixedAssetRatio", "EquityToAsset", "FixAssetRatio", "IntangibleAssetRatio", "CurrentAssetsRatio",
                 "NonCurrentAssetsRatio", "LongDebtToAsset", "LongTermDebtToAsset", "LongDebtToWorkingCapital",
                 "DebtEquityRatio", "DebtsAssetRatio", "CurrentRatio", "QuickRatio", "BLEV",
                 "TotalAssetsTRate", "CurrentAssetsTRate", "FixedAssetsTRate", "EquityTRate", "ARTRate", "ARTDays",
                 "InventoryTRate", "InventoryTDays", "AccountsPayablesTRate", "AccountsPayablesTDays",
                 "NetProfitGrowRate", "TotalProfitGrowRate", "OperatingProfitGrowRate", "OperatingRevenueGrowRate",
                 "NetAssetGrowRate", "TotalAssetGrowRate", "OperCashGrowRate", "InvestCashGrowRate", "FinancingCashGrowRate", "ACCA")
.MKT_FEATS  <- c("PE", "PB", "PS", "PCF", "ETOP", "CTOP", "ETP5", "CTP5", "MLEV", "TA2EV", "CFO2EV", "EPS")
.CONS_FEATS <- c("FY12P", "SFY12P", "FEARNG", "FSALESG", "DAREV", "GREV", "DASREV", "GSREV", "SUE")
.FEATS <- c(.TECH_FEATS, .FUND_FEATS, .MKT_FEATS, .CONS_FEATS)
stopifnot(!anyDuplicated(.FEATS), length(.FEATS) == 112L)

# =============================================================================
# 1. 루트·캐시 경로 (r-portability: 표지 파일 검증 · env= 미사용)
# =============================================================================
.find_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             if (exists("PROJECT_ROOT", inherits = TRUE)) as.character(get("PROJECT_ROOT", inherits = TRUE))[1] else "",
             getwd())
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  for (p in cands) {
    if (!nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (file.exists(file.path(p, marker))) return(p)
  }
  stop(sprintf("%s 프로젝트 루트를 찾지 못함(표지 %s) — CLAUDE_PROJECT_DIR/QM_ROOT 확인", .TAG, marker))
}
.ROOT  <- .find_root()
.CACHE <- if (exists("CACHE_DIR", inherits = TRUE)) as.character(get("CACHE_DIR", inherits = TRUE))[1] else file.path(.ROOT, ".cache")
.FM_PATH <- file.path(.CACHE, "fundamental_merged.parquet")
.CONS_DIR <- file.path(.CACHE, "consensus")
if (!file.exists(.FM_PATH)) stop(sprintf("%s 회계 패널 부재: %s — 부록 회계 특성 원천. data_gap 적재 대상", .TAG, .FM_PATH))
.CONS_HAVE <- c(eps_1y = file.exists(file.path(.CONS_DIR, "eps_1y.parquet")),
                revenue_fy1 = file.exists(file.path(.CONS_DIR, "revenue_fy1.parquet")),
                sue = file.exists(file.path(.CONS_DIR, "sue.parquet")))
cat(sprintf("%s root %s · cache %s · 컨센서스 패널 eps_1y %s · revenue_fy1 %s · sue %s\n", .TAG, .ROOT, .CACHE,
            if (.CONS_HAVE[["eps_1y"]]) "있음" else "없음", if (.CONS_HAVE[["revenue_fy1"]]) "있음" else "없음",
            if (.CONS_HAVE[["sue"]]) "있음" else "없음"))

# =============================================================================
# 2. 헬퍼 + 양성 대조 (구현 결함 = 중단 · 조용한 F 방지)
# =============================================================================
.sdiv <- function(a, b) fifelse(is.finite(a) & is.finite(b) & b > 0, a / b, NA_real_)          # 분모 > 0 만 (changed(5))
.gro  <- function(x, xp) fifelse(is.finite(x) & is.finite(xp) & abs(xp) > 0, (x - xp) / abs(xp), NA_real_)   # (x − x_prev)/|x_prev|
.logpos <- function(x) fifelse(is.finite(x) & x > 0, log(x), NA_real_)
.ema_safe <- function(x, n) { if (length(x) < n) return(rep(NA_real_, length(x))); as.numeric(TTR::EMA(x, n = n)) }
.rsi_safe <- function(x, n) { if (length(x) <= n) return(rep(NA_real_, length(x))); as.numeric(TTR::RSI(x, n = n)) }
.fsum_ok <- function(x, n) {                        # 창 합(결측 제외) — 유효 관측이 창의 .ROLL_MIN_FRAC 미만이면 결측 (changed(5))
  s <- frollsum(x, n, na.rm = TRUE, hasNA = TRUE); k <- frollsum(as.numeric(is.finite(x)), n)
  fifelse(is.finite(k) & k >= .ROLL_MIN_FRAC * n & is.finite(s), s, NA_real_)
}
.fmean_ok <- function(x, n) {                       # 창 평균(결측 제외) — 같은 커버리지 규약 (changed(5))
  s <- frollmean(x, n, na.rm = TRUE, hasNA = TRUE); k <- frollsum(as.numeric(is.finite(x)), n)
  fifelse(is.finite(k) & k >= .ROLL_MIN_FRAC * n & is.finite(s), s, NA_real_)
}
.auc <- function(score, y) {                       # Mann–Whitney AUC (진단 전용)
  ok <- is.finite(score) & !is.na(y); score <- score[ok]; y <- y[ok]
  n1 <- sum(y == 1L); n0 <- sum(y == 0L)
  if (n1 < 2L || n0 < 2L) return(NA_real_)
  r <- frank(score, ties.method = "average")
  (sum(r[y == 1L]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}
.softmax <- function(Z) { Z <- Z - apply(Z, 1L, max); E <- exp(Z); E / rowSums(E) }

# ── 신경망(순수 R) — DNN: n → ⌊n/2⌋ ReLU → Dropout → ⌊n/4⌋ ReLU → BN → 2 Softmax · LR: n → 2 Softmax ──
#    (2-클래스 softmax = 로지스틱 함수의 재매개화 · 논문 LR 은 logistic function — changed(8))
.glorot <- function(nr, nc) { lim <- sqrt(6 / (nr + nc)); matrix(runif(nr * nc, -lim, lim), nr, nc) }     # Keras Dense 기본 초기화 (changed(8))
.dnn_new <- function(n_in, seed) {
  set.seed(seed)
  h1 <- max(2L, n_in %/% 2L); h2 <- max(2L, n_in %/% 4L)                                            # 논문: ⌊n/2⌋ · ⌊n/4⌋
  list(P = list(W1 = .glorot(n_in, h1), b1 = numeric(h1), W2 = .glorot(h1, h2), b2 = numeric(h2),
                g = rep(1, h2), be = numeric(h2), W3 = .glorot(h2, 2L), b3 = numeric(2L)),
       rm = numeric(h2), rv = rep(1, h2), h = c(h1, h2))
}
.lr_new <- function(n_in, seed) { set.seed(seed); list(P = list(W = .glorot(n_in, 2L), b = numeric(2L))) }
.dnn_fwd <- function(m, X, train, mask = NULL) {
  P <- m$P
  Z1 <- sweep(X %*% P$W1, 2L, P$b1, "+"); A1 <- Z1 * (Z1 > 0)
  if (train) {
    if (is.null(mask)) mask <- matrix(rbinom(length(A1), 1L, 1 - .DNN_DROP), nrow(A1)) / (1 - .DNN_DROP)   # inverted dropout (Keras)
    D1 <- A1 * mask
  } else { D1 <- A1; mask <- NULL }
  Z2 <- sweep(D1 %*% P$W2, 2L, P$b2, "+"); A2 <- Z2 * (Z2 > 0)
  if (train) {
    mu <- colMeans(A2); Ac <- sweep(A2, 2L, mu, "-"); va <- colMeans(Ac * Ac)
    m$rm <- .BN_MOM * m$rm + (1 - .BN_MOM) * mu
    m$rv <- .BN_MOM * m$rv + (1 - .BN_MOM) * va
  } else { Ac <- sweep(A2, 2L, m$rm, "-"); va <- m$rv }
  istd <- 1 / sqrt(va + .BN_EPS)
  Ah <- sweep(Ac, 2L, istd, "*")
  B  <- sweep(sweep(Ah, 2L, P$g, "*"), 2L, P$be, "+")
  Z3 <- sweep(B %*% P$W3, 2L, P$b3, "+")
  list(prob = .softmax(Z3), m = m,
       cache = list(X = X, Z1 = Z1, mask = mask, D1 = D1, Z2 = Z2, va = va, Ah = Ah, istd = istd, B = B))
}
# 역전파 — softmax CE: dZ3 = (P − Y)/n · BN(배치 통계): dA2 = istd/n · (n·dAh − Σ dAh − Ah·Σ(dAh·Ah)) · 드롭아웃 = 마스크 · ReLU = 1[Z>0] · L2 = 2·l2·W
.dnn_bwd <- function(m, fw, y, l2) {
  P <- m$P; cc <- fw$cache; n <- length(y)
  Y <- cbind(1 - y, y)
  dZ3 <- (fw$prob - Y) / n
  G <- list()
  G$W3 <- crossprod(cc$B, dZ3) + 2 * l2 * P$W3; G$b3 <- colSums(dZ3)
  dB <- tcrossprod(dZ3, P$W3)
  G$g  <- colSums(dB * cc$Ah); G$be <- colSums(dB)
  dAh <- sweep(dB, 2L, P$g, "*")
  s1 <- colSums(dAh); s2 <- colSums(dAh * cc$Ah)
  dA2 <- sweep(sweep(n * dAh, 2L, s1, "-") - sweep(cc$Ah, 2L, s2, "*"), 2L, cc$istd / n, "*")
  dZ2 <- dA2 * (cc$Z2 > 0)
  G$W2 <- crossprod(cc$D1, dZ2) + 2 * l2 * P$W2; G$b2 <- colSums(dZ2)
  dD1 <- tcrossprod(dZ2, P$W2)
  dZ1 <- (dD1 * cc$mask) * (cc$Z1 > 0)
  G$W1 <- crossprod(cc$X, dZ1) + 2 * l2 * P$W1; G$b1 <- colSums(dZ1)
  G
}
.lr_fwd <- function(m, X) list(prob = .softmax(sweep(X %*% m$P$W, 2L, m$P$b, "+")), cache = list(X = X))
.lr_bwd <- function(m, fw, y) { n <- length(y); dZ <- (fw$prob - cbind(1 - y, y)) / n
                                list(W = crossprod(fw$cache$X, dZ), b = colSums(dZ)) }
.ce_loss <- function(prob, y) -mean(log(pmax(ifelse(y == 1L, prob[, 2L], prob[, 1L]), 1e-12)))
# SGD + Nesterov momentum + 학습률 감쇠 (Keras SGD 규약: v = μv − η g · θ = θ + μv − η g · η_t = η/(1 + decay·t))
.sgd_fit <- function(m, X, y, kind, lr0, decay, mom, epochs, batch, l2, seed) {
  set.seed(seed)
  V <- lapply(m$P, function(p) p * 0)
  it <- 0L; n <- nrow(X); n_skip <- 0L; last <- NA_real_
  for (e in seq_len(epochs)) {
    idx <- sample.int(n)
    for (s in seq(1L, n, by = batch)) {
      ii <- idx[s:min(n, s + batch - 1L)]
      if (length(ii) < 2L) { n_skip <- n_skip + 1L; next }                                        # ★changed(8) BN 은 행 ≥ 2
      Xb <- X[ii, , drop = FALSE]; yb <- y[ii]
      if (kind == "dnn") { fw <- .dnn_fwd(m, Xb, TRUE); m <- fw$m; G <- .dnn_bwd(m, fw, yb, l2) }
      else { fw <- .lr_fwd(m, Xb); G <- .lr_bwd(m, fw, yb) }
      it <- it + 1L; lr <- lr0 / (1 + decay * it)
      for (k in names(m$P)) { V[[k]] <- mom * V[[k]] - lr * G[[k]]; m$P[[k]] <- m$P[[k]] + mom * V[[k]] - lr * G[[k]] }
      last <- .ce_loss(fw$prob, yb)
    }
  }
  m$it <- it; m$n_skip <- n_skip; m$last_loss <- last
  m
}
.nn_predict <- function(m, X, kind) if (kind == "dnn") .dnn_fwd(m, X, FALSE)$prob[, 2L] else .lr_fwd(m, X)$prob[, 2L]

# 기울기 검산(양성 대조) — 해석적 역전파 vs 중심차분. ★2판: 잘 조건화된 검산 지점을 고른다(1판 중단 원인 = 병적 지점 — 머리말).
.gc_compare <- function(an, num) {
  e_norm <- sqrt(sum((an - num)^2)) / (sqrt(sum(an^2)) + sqrt(sum(num^2)))
  fl <- 1e-3 * max(abs(an) + abs(num))
  e_max <- max(abs(an - num) / pmax(abs(an) + abs(num), fl))
  c(norm = e_norm, max = e_max)
}
local({
  n <- 64L; p <- 24L; l2 <- 1e-3; h <- 1e-6
  pick <- NULL
  for (s in seq_len(60L)) {
    m <- .dnn_new(p, .SEED_BASE + 100L + s)                                  # set.seed 는 .dnn_new 안 — 이후 난수도 결정론
    m$P$b1 <- rnorm(m$h[1], 0, 0.3); m$P$b2 <- rnorm(m$h[2], 0, 0.3); m$P$b3 <- rnorm(2L, 0, 0.3)
    m$P$g <- runif(m$h[2], 0.5, 1.5); m$P$be <- rnorm(m$h[2], 0, 0.3)
    X <- matrix(rnorm(n * p), n, p); y <- as.integer(runif(n) > 0.5)
    mask <- matrix(rbinom(n * m$h[1], 1L, 1 - .DNN_DROP), n) / (1 - .DNN_DROP)
    fw <- .dnn_fwd(m, X, TRUE, mask); cc <- fw$cache
    if (min(abs(cc$Z1)) > 1e-4 && min(abs(cc$Z2)) > 1e-4 && min(cc$va) > 0.05 && sum(y == 1L) >= 8L && sum(y == 0L) >= 8L) {
      pick <- list(m = m, X = X, y = y, mask = mask, fw = fw, seed = s); break
    }
  }
  if (is.null(pick)) stop(sprintf("%s DNN 기울기 검산 지점 확보 실패(60 시드) — 검산 설계 결함", .TAG))
  m <- pick$m; X <- pick$X; y <- pick$y; mask <- pick$mask; fw <- pick$fw
  G <- .dnn_bwd(m, fw, y, l2)
  lossf <- function(P) { mm <- m; mm$P <- P; f <- .dnn_fwd(mm, X, TRUE, mask)
                         .ce_loss(f$prob, y) + l2 * (sum(P$W1^2) + sum(P$W2^2) + sum(P$W3^2)) }
  an <- numeric(0); num <- numeric(0)
  for (k in names(m$P)) {
    for (i in seq_along(m$P[[k]])) {
      Pp <- m$P; Pp[[k]][i] <- Pp[[k]][i] + h
      Pm <- m$P; Pm[[k]][i] <- Pm[[k]][i] - h
      an <- c(an, as.numeric(G[[k]][i])); num <- c(num, (lossf(Pp) - lossf(Pm)) / (2 * h))
    }
  }
  e_dnn <- .gc_compare(an, num)
  if (!all(is.finite(e_dnn)) || e_dnn[["norm"]] > .GC_TOL_NORM || e_dnn[["max"]] > .GC_TOL_MAX)
    stop(sprintf("%s DNN 기울기 검산 불일치 — 노름 상대오차 %.3g (허용 %.0e) · 성분 최대 %.3g (허용 %.0e) · 파라미터 %d — 원인 귀속 없음(검산 지점 조건화부터 볼 것) — 중단",
                 .TAG, e_dnn[["norm"]], .GC_TOL_NORM, e_dnn[["max"]], .GC_TOL_MAX, length(an)))
  # LR(softmax 회귀) 기울기 검산 — 같은 규약
  ml <- .lr_new(p, .SEED_BASE + 3L); ml$P$b <- rnorm(2L, 0, 0.3)
  fl <- .lr_fwd(ml, X); Gl <- .lr_bwd(ml, fl, y)
  lossl <- function(P) { mm <- ml; mm$P <- P; .ce_loss(.lr_fwd(mm, X)$prob, y) }
  an2 <- numeric(0); num2 <- numeric(0)
  for (k in names(ml$P)) {
    for (i in seq_along(ml$P[[k]])) {
      Pp <- ml$P; Pp[[k]][i] <- Pp[[k]][i] + h
      Pm <- ml$P; Pm[[k]][i] <- Pm[[k]][i] - h
      an2 <- c(an2, as.numeric(Gl[[k]][i])); num2 <- c(num2, (lossl(Pp) - lossl(Pm)) / (2 * h))
    }
  }
  e_lr <- .gc_compare(an2, num2)
  if (!all(is.finite(e_lr)) || e_lr[["norm"]] > .GC_TOL_NORM || e_lr[["max"]] > .GC_TOL_MAX)
    stop(sprintf("%s LR 기울기 검산 불일치 — 노름 상대오차 %.3g · 성분 최대 %.3g — 원인 귀속 없음", .TAG, e_lr[["norm"]], e_lr[["max"]]))
  # 학습 양성 대조 — 선형 분리 가능한 합성 표본을 LR·DNN 이 학습하는지 (검산 전용 설정 — 60 epoch · DNN η 1e-2. 본 학습은 §0 논문값)
  set.seed(.SEED_BASE + 1L)
  ns <- 800L; w <- rnorm(p)
  Xs <- matrix(rnorm(ns * p), ns, p); ys <- as.integer(as.numeric(Xs %*% w) + 0.3 * rnorm(ns) > 0)
  Xt <- matrix(rnorm(400L * p), 400L, p); yt <- as.integer(as.numeric(Xt %*% w) > 0)
  fl2 <- .sgd_fit(.lr_new(p, 5L), Xs, ys, "lr", .LR_LR, .LR_DECAY, .LR_MOM, 60L, .LR_BATCH, 0, 11L)
  fd2 <- .sgd_fit(.dnn_new(p, 5L), Xs, ys, "dnn", 1e-2, .DNN_DECAY, .DNN_MOM, 60L, .DNN_BATCH, .DNN_L2, 12L)
  a_lr <- .auc(.nn_predict(fl2, Xt, "lr"), yt); a_dnn <- .auc(.nn_predict(fd2, Xt, "dnn"), yt)
  if (!(is.finite(a_lr) && a_lr > 0.9) || !(is.finite(a_dnn) && a_dnn > 0.75))
    stop(sprintf("%s 학습 양성 대조 문턱 미달 — LR AUC %.3f (> 0.9) · DNN AUC %.3f (> 0.75) — 원인 귀속 없음", .TAG, a_lr, a_dnn))
  # AUC 검산(★3판 재설계 — 2판 중단 원인): 순위식 .auc 를 독립 계산(양·음 쌍 전수 비교 · 동률 = 0.5)과 대조한다. 두 식은 평균순위
  #   규약 아래 항등(Σ_pos r_i = n1(n1+1)/2 + n1·n0·AUC_pair). 손 유도 픽스처의 기대값은 유도 과정과 함께 적는다 — 2판은 픽스처
  #   (0.9,0.8,0.7,0.2,0.1)/(1,1,0,0,0) 의 기대값을 5/6 으로 잘못 손계산했다(실제 = 양성 2 × 음성 3 = 6쌍 전부 승 = 1).
  .auc_pairs <- function(score, y) { sp <- score[y == 1L]; sn <- score[y == 0L]
                                     mean(outer(sp, sn, function(a, b) (a > b) + 0.5 * (a == b))) }
  set.seed(.SEED_BASE + 2L)
  .sc_rand <- round(runif(200L), 1); .y_rand <- as.integer(runif(200L) > 0.5)                       # 동률 다수 포함 무작위(기대값 = 쌍비교)
  .auc_cases <- list(
    list(s = c(0.9, 0.8, 0.7, 0.2, 0.1), y = c(1L, 1L, 0L, 0L, 0L), e = 1),      # 완전 분리: 0.9·0.8 > {0.7,0.2,0.1} → 6/6 쌍 승 = 1
    list(s = c(0.9, 0.6, 0.7, 0.2, 0.1), y = c(1L, 1L, 0L, 0L, 0L), e = 5 / 6),  # 0.9 > {0.7,0.2,0.1} 3승 · 0.6 > {0.2,0.1} 2승 · 0.6 < 0.7 1패 → 5/6
    list(s = c(0.5, 0.5, 0.5, 0.5), y = c(1L, 0L, 1L, 0L), e = 0.5),             # 전 동률: 4쌍 × 0.5 → 1/2
    list(s = c(0.1, 0.2, 0.7, 0.8, 0.9), y = c(1L, 1L, 0L, 0L, 0L), e = 0),      # 완전 역전: 0.1·0.2 < {0.7,0.8,0.9} → 0/6 = 0
    list(s = .sc_rand, y = .y_rand, e = NA_real_))
  for (k_ in seq_along(.auc_cases)) {
    cs_ <- .auc_cases[[k_]]
    a_rank <- .auc(cs_$s, cs_$y); a_pair <- .auc_pairs(cs_$s, cs_$y)
    if (!is.finite(a_rank) || !is.finite(a_pair) || !isTRUE(all.equal(a_rank, a_pair)) ||
        (is.finite(cs_$e) && !isTRUE(all.equal(a_rank, cs_$e))))
      stop(sprintf("%s AUC 검산 불일치(픽스처 %d) — 순위식 %.4f · 쌍비교 %.4f · 손유도 기대 %s — 원인 귀속 없음", .TAG, k_, a_rank, a_pair,
                   if (is.finite(cs_$e)) sprintf("%.4f", cs_$e) else "(없음 · 쌍비교만)"))
  }
  if (!isTRUE(all.equal(.gro(c(10, -6, 0), c(8, 4, 5)), c(0.25, -2.5, -1)))) stop(sprintf("%s 증가율 검산 실패", .TAG))
  # 창 5 · 유효 ≥ 4: i=5 [1,NA,3,4,5] → 13 · i=6 [NA,3,4,5,NA] 유효 3 → NA · i=7 [3,4,5,NA,7] → 19 · i=8 → 24 · i=9 → 29 · i=10 → 34
  fs <- .fsum_ok(c(1, NA, 3, 4, 5, NA, 7, 8, 9, 10), 5L)
  if (!isTRUE(all.equal(fs, c(NA, NA, NA, NA, 13, NA, 19, 24, 29, 34)))) stop(sprintf("%s 롤링 창 커버리지 검산 실패", .TAG))
  cat(sprintf("%s 양성 대조 통과 — DNN 기울기(시드 %d · 파라미터 %d · 노름 %.2e · 성분 최대 %.2e) · LR 기울기(노름 %.2e · 성분 최대 %.2e) · 학습 AUC LR %.3f / DNN %.3f · AUC(순위식 = 쌍비교 · 픽스처 %d) · 증가율 · 롤링 창\n",
              .TAG, pick$seed, length(an), e_dnn[["norm"]], e_dnn[["max"]], e_lr[["norm"]], e_lr[["max"]], a_lr, a_dnn, length(.auc_cases)))
})

# =============================================================================
# 3. 일간 패널 — 격자 2001-01-01~ · 적격 이력 종목(K200∪KQ150 플래그가 한 번이라도 TRUE) · RAWDATA 비파괴  ★changed(1)(5)
#    열 정체: Close·Open·High·Low = 수정주가 · Vol = 주식수 거래량 · Size = 시가총액(KRW) · Ret = 인프라 일간수익률
# =============================================================================
.cols <- c("Date", "Ticker", "Open", "High", "Low", "Close", "Vol", "Size", "Ret", "K200", "KQ150")
.rd <- RAWDATA[Date >= .GRID_FROM & is.finite(Close) & Close > 0, .cols, with = FALSE]
.rd[, Ticker := as.character(Ticker)]
if (!inherits(.rd$Date, "Date")) .rd[, Date := as.Date(Date)]
.rd[, MEM := (K200 == TRUE | KQ150 == TRUE) %in% TRUE]                       # 러너 .apply_universe 와 같은 술어
.rd[, c("K200", "KQ150") := NULL]
.mem_tk <- sort(unique(.rd$Ticker[.rd$MEM]))
if (length(.mem_tk) < 50L) stop(sprintf("%s 적격 이력 종목 %d — 멤버십 플래그 확인", .TAG, length(.mem_tk)))
.n_all_rows <- nrow(.rd)
.rd <- .rd[Ticker %in% .mem_tk]
for (.cc in c("Open", "High", "Low", "Vol", "Size", "Ret")) .rd[, (.cc) := as.numeric(get(.cc))]
.rd[!is.finite(Open) | Open <= 0, Open := NA_real_]
.rd[!is.finite(High) | High <= 0, High := NA_real_]
.rd[!is.finite(Low) | Low <= 0, Low := NA_real_]
.rd[!is.finite(Vol) | Vol < 0, Vol := NA_real_]
.rd[!is.finite(Size) | Size <= 0, Size := NA_real_]
.rd[!is.finite(Ret), Ret := NA_real_]
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) { cat(sprintf("%s (Ticker,Date) 중복 %d행 — 첫 행만 유지\n", .TAG, .ndup)); .rd <- unique(.rd, by = c("Ticker", "Date")) }
setorder(.rd, Ticker, Date)
.rd[, MI := year(Date) * 12L + month(Date)]

# 시장 거래일 격자(RAWDATA 전 종목) · 완결 달력월의 마지막 거래일 = 시그널일 · 마지막 부분월 제외
.CAL <- data.table(Date = sort(unique(RAWDATA$Date)))
if (!inherits(.CAL$Date, "Date")) .CAL[, Date := as.Date(Date)]
.CAL <- .CAL[Date >= .GRID_FROM]
.CAL[, di := .I]
.CAL[, MI := year(Date) * 12L + month(Date)]
.me <- .CAL[, .(MEnd = max(Date), me_di = max(di)), by = MI]
setorder(.me, MI)
.MI_LAST <- max(.me$MI)
.me <- .me[MI < .MI_LAST]
.n_gap <- sum(diff(.me$MI) != 1L)
if (.n_gap > 0L) cat(sprintf("%s [WARN] 거래일이 없는 달력월 %d개 — 그 달의 횡단면·표적은 비어 있다(발행은 다음 달부터 이어진다)\n", .TAG, .n_gap))
.me[, j := .I]
.mk <- BM_DT[is.finite(BM_Ret), .(Date, BM_Ret = as.numeric(BM_Ret))]
if (!inherits(.mk$Date, "Date")) .mk[, Date := as.Date(Date)]
.mk <- unique(.mk, by = "Date")
.CAL[.mk, on = "Date", mret := i.BM_Ret]
.rd[, is_me := Date %in% .me$MEnd]
.ym <- function(mi) sprintf("%d-%02d", (mi - 1L) %/% 12L, (mi - 1L) %% 12L + 1L)
cat(sprintf("%s RAWDATA %d행(격자 이후) → 적격 이력 %d종 %d행 · 거래일 %d(%s ~ %s) · 완결 월말 %d(마지막 부분월 %s 제외) · 벤치 수익 있는 날 %.1f%%\n",
            .TAG, .n_all_rows, length(.mem_tk), nrow(.rd), nrow(.CAL), as.character(min(.CAL$Date)), as.character(max(.CAL$Date)),
            nrow(.me), .ym(.MI_LAST), 100 * mean(is.finite(.CAL$mret))))

# =============================================================================
# 4. 일간 기술 특성 — 종목별로 전 이력 위에서 계산하고 월말 행만 남긴다 (부록 이름 · Uqer 규약/표준 창 — 논문은 이름만 인쇄)  ★changed(4)(5)
#    창은 종목 자신의 관측 행(거래일) 위에서 센다(거래정지 갭은 압축 — 신고). 값 절단 없음.
# =============================================================================
.tech_one <- function(Date, Close, Open, High, Low, Vol, Size, Ret, MEM, is_me) {
  keep <- which(is_me)
  tr  <- fifelse(is.finite(Vol) & is.finite(Size), Vol * Close / Size, NA_real_)                  # 회전율 = 거래량 / 발행주식수(= Size/Close)
  up  <- as.numeric(Close > shift(Close, 1L))
  ma  <- lapply(.MA_K, function(k) frollmean(Close, k))
  ema <- lapply(.MA_K, function(k) .ema_safe(Close, k))
  vol <- lapply(.VOL_K, function(k) .fmean_ok(tr, k))
  dav <- lapply(1:3, function(i) .sdiv(vol[[i]], vol[[5L]]))                                       # DAVOLk = VOLk / VOL120
  revs <- lapply(.REVS_K, function(k) Close / shift(Close, k))
  rsi <- .rsi_safe(Close, .RSI_N)                                                                 # Wilder 평활 (TTR 기본)
  psy <- frollsum(up, .PSY_N) / .PSY_N * 100
  # MFI(14) — 대표가격 (H+L+C)/3 · 자금흐름 = 대표가격 × 거래량 · 상승/하락일 합의 비율
  tp  <- (High + Low + Close) / 3
  mf  <- tp * Vol
  dtp <- tp - shift(tp, 1L)
  okm <- is.finite(mf) & is.finite(dtp)
  pmf <- fifelse(okm, fifelse(dtp > 0, mf, 0), NA_real_)
  nmf <- fifelse(okm, fifelse(dtp < 0, mf, 0), NA_real_)
  spm <- .fsum_ok(pmf, .MFI_N); snm <- .fsum_ok(nmf, .MFI_N)
  mfi <- fifelse(is.finite(spm) & is.finite(snm) & (spm + snm) > 0, 100 * spm / (spm + snm), NA_real_)
  # WVAD(24) = Σ (C−O)/(H−L) × V · MAWVAD = WVAD 의 6일 평균
  wv  <- fifelse(is.finite(Open) & is.finite(High) & is.finite(Low) & High > Low & is.finite(Vol), (Close - Open) / (High - Low) * Vol, NA_real_)
  wvad <- .fsum_ok(wv, .WVAD_N)
  mawvad <- frollmean(wvad, .WVAD_M)
  # RSTR12/24 = 최근 252/504 거래일 로그수익 합 (Barra RSTR 의 시차·무위험 차감 없음 — 신고)
  lr  <- fifelse(is.finite(Ret) & Ret > -1, log1p(Ret), NA_real_)
  rstr12 <- .fsum_ok(lr, .W_RSTR12); rstr24 <- .fsum_ok(lr, .W_RSTR24)
  lcap <- .logpos(Size)
  hl  <- fifelse(is.finite(High) & is.finite(Low) & High >= Low, log(High / Low), NA_real_)
  # DHILO = 최근 60 거래일 ln(H/L) 중앙값 (유효 ≥ 30) — 월말 행에서만
  dhilo <- vapply(keep, function(i) {
    if (i < .W_DHILO) return(NA_real_)
    v <- hl[seq.int(i - .W_DHILO + 1L, i)]; v <- v[is.finite(v)]
    if (length(v) < .W_DHILO %/% 2L) NA_real_ else median(v)
  }, numeric(1))
  list(Date = Date[keep], MEM = MEM[keep], Close = Close[keep], Size = Size[keep], Ret = Ret[keep],
       MA5 = ma[[1L]][keep], MA10 = ma[[2L]][keep], MA20 = ma[[3L]][keep], MA60 = ma[[4L]][keep], MA120 = ma[[5L]][keep],
       EMA5 = ema[[1L]][keep], EMA10 = ema[[2L]][keep], EMA20 = ema[[3L]][keep], EMA60 = ema[[4L]][keep], EMA120 = ema[[5L]][keep],
       VOL5 = vol[[1L]][keep], VOL10 = vol[[2L]][keep], VOL20 = vol[[3L]][keep], VOL60 = vol[[4L]][keep], VOL120 = vol[[5L]][keep], VOL240 = vol[[6L]][keep],
       DAVOL5 = dav[[1L]][keep], DAVOL10 = dav[[2L]][keep], DAVOL20 = dav[[3L]][keep],
       REVS5 = revs[[1L]][keep], REVS10 = revs[[2L]][keep], REVS20 = revs[[3L]][keep],
       RSI = rsi[keep], MFI = mfi[keep], PSY = psy[keep], WVAD = wvad[keep], MAWVAD = mawvad[keep], DHILO = dhilo,
       RSTR12 = rstr12[keep], RSTR24 = rstr24[keep], LCAP = lcap[keep])
}
.F <- .rd[, .tech_one(Date, Close, Open, High, Low, Vol, Size, Ret, MEM, is_me), by = Ticker]
# 표적 재료 — 달(MI)별 일간수익 평균·표준편차·유효일수 (§8 에서 달 MI−1 월말 시그널의 표적이 된다)
.LB <- .rd[MI < .MI_LAST, .(mu = mean(Ret, na.rm = TRUE), sdv = sd(Ret, na.rm = TRUE), nn = sum(is.finite(Ret))), by = .(Ticker, MI)]
# 회귀 특성 재료 — 일간수익 와이드 행렬(거래일 × 종목)
.RW <- dcast(.rd[, .(Date, Ticker, Ret)], Date ~ Ticker, value.var = "Ret")
.RW <- .RW[.CAL[, .(Date)], on = "Date"]                                     # 격자 전 거래일(행 없는 날 = 전부 결측)
setorder(.RW, Date)
.TKW <- setdiff(names(.RW), "Date")
.R <- as.matrix(.RW[, .TKW, with = FALSE]); colnames(.R) <- .TKW
rm(.RW, .rd); gc(verbose = FALSE)
cat(sprintf("%s 일간 기술 특성 %d종 완료 · 월말 행 %d (적격 %d) · 표적 재료 %d (종목,달) · 수익 행렬 %d × %d · %.1f분\n", .TAG,
            length(.TECH_FEATS) - length(.REG_FEATS), nrow(.F), .F[, sum(MEM)], nrow(.LB), nrow(.R), ncol(.R),
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))

# =============================================================================
# 5. 월말 회귀 특성 — 최근 252 거래일 · 시장 = BM_DT 일간수익 (HBETA · HSIGMA · DDNBT · DDNCR · DDNSR · DVRAT · CMRA)  ★changed(5)
# =============================================================================
.MRET <- .CAL$mret
.ols_cols <- function(Y, x) {                      # 열별 단순회귀(절편 포함) — 결측 마스크 · 반환 beta·잔차sd·상관·n
  M <- is.finite(Y); Y0 <- Y; Y0[!M] <- 0; Mn <- M + 0
  n <- colSums(Mn); Sx <- as.vector(crossprod(Mn, x)); Sxx <- as.vector(crossprod(Mn, x * x))
  Sy <- colSums(Y0); Sxy <- as.vector(crossprod(Y0, x)); Syy <- colSums(Y0 * Y0)
  vx <- n * Sxx - Sx * Sx; vy <- n * Syy - Sy * Sy
  beta <- (n * Sxy - Sx * Sy) / vx
  rss  <- (Syy - Sy * Sy / n) - beta * beta * (Sxx - Sx * Sx / n)
  sig  <- sqrt(pmax(rss, 0) / pmax(n - 2, 1))
  cor  <- (n * Sxy - Sx * Sy) / sqrt(pmax(vx * vy, 0))
  sdy  <- sqrt(pmax(vy, 0) / (n * pmax(n - 1, 1)))
  list(beta = beta, sig = sig, cor = cor, sdy = sdy, n = n, vx = vx)
}
.reg_month <- function(di, tk) {
  n <- length(tk)
  out <- matrix(NA_real_, n, 7L, dimnames = list(tk, .REG_FEATS))
  if (di < .W_BETA) return(out)
  rows <- seq.int(di - .W_BETA + 1L, di)
  x <- .MRET[rows]; okx <- is.finite(x)
  ci <- match(tk, colnames(.R)); hit <- !is.na(ci)
  Y <- matrix(NA_real_, length(rows), n); if (any(hit)) Y[, hit] <- .R[rows, ci[hit], drop = FALSE]
  Yx <- Y[okx, , drop = FALSE]; xx <- x[okx]
  if (length(xx) >= .W_BETA_MIN) {
    f <- .ols_cols(Yx, xx)
    ok <- f$n >= .W_BETA_MIN & f$vx > 0
    ok[is.na(ok)] <- FALSE
    out[ok, "HBETA"] <- f$beta[ok]; out[ok, "HSIGMA"] <- f$sig[ok]
    dn <- xx < 0
    if (sum(dn) >= .W_BETA_MIN %/% 3L) {
      fd <- .ols_cols(Yx[dn, , drop = FALSE], xx[dn])
      okd <- fd$n >= .W_BETA_MIN %/% 3L & fd$vx > 0
      okd[is.na(okd)] <- FALSE
      sdm <- sd(xx[dn])
      out[okd, "DDNBT"] <- fd$beta[okd]; out[okd, "DDNCR"] <- fd$cor[okd]
      if (is.finite(sdm) && sdm > 0) out[okd, "DDNSR"] <- fd$sdy[okd] / sdm
    }
  }
  # DVRAT = Var(10일 로그수익 합)/(10·Var(일간 로그수익)) · CMRA = 12 블록(21일) 누적 로그수익의 max − min (결측일 = 0 수익 — 신고)
  L <- log1p(Y); Lok <- is.finite(L); nL <- colSums(Lok); L[!Lok] <- 0
  S <- apply(L, 2L, cumsum); if (!is.matrix(S)) S <- matrix(S, ncol = n)
  Sq <- S[seq.int(.VR_Q + 1L, nrow(S)), , drop = FALSE] - S[seq.int(1L, nrow(S) - .VR_Q), , drop = FALSE]
  vq <- apply(Sq, 2L, var); v1 <- apply(L, 2L, var)
  okv <- nL >= .W_BETA_MIN & is.finite(v1) & v1 > 0
  okv[is.na(okv)] <- FALSE
  out[okv, "DVRAT"] <- vq[okv] / (.VR_Q * v1[okv])
  nb <- nrow(S) %/% .CMRA_BLK
  Z <- S[seq_len(nb) * .CMRA_BLK, , drop = FALSE]
  cm <- apply(Z, 2L, max) - apply(Z, 2L, min)
  out[okv, "CMRA"] <- cm[okv]
  out
}
.reg_rows <- vector("list", nrow(.me))
for (jj in seq_len(nrow(.me))) {
  d <- .me$MEnd[jj]
  tk <- .F[Date == d & MEM == TRUE, Ticker]
  if (!length(tk)) next
  o <- .reg_month(.me$me_di[jj], tk)
  .reg_rows[[jj]] <- data.table(Date = d, Ticker = tk, HBETA = o[, "HBETA"], HSIGMA = o[, "HSIGMA"], DDNBT = o[, "DDNBT"],
                                DDNCR = o[, "DDNCR"], DDNSR = o[, "DDNSR"], DVRAT = o[, "DVRAT"], CMRA = o[, "CMRA"])
}
.REG <- rbindlist(.reg_rows, use.names = TRUE)
if (nrow(.REG) > 0L)
  .F[.REG, on = .(Ticker, Date), c("HBETA", "HSIGMA", "DDNBT", "DDNCR", "DDNSR", "DVRAT", "CMRA") :=
       .(i.HBETA, i.HSIGMA, i.DDNBT, i.DDNCR, i.DDNSR, i.DVRAT, i.CMRA)]
for (.cc in .REG_FEATS) if (!.cc %in% names(.F)) .F[, (.cc) := NA_real_]
rm(.reg_rows, .REG, .R, .MRET)
gc(verbose = FALSE)
cat(sprintf("%s 월말 회귀 특성 7종 완료 (창 %d · 하한 %d · 시장 = BM_DT) · 적격 월말행 HBETA 커버리지 %.1f%% · %.1f분\n",
            .TAG, .W_BETA, .W_BETA_MIN, 100 * .F[MEM == TRUE, mean(is.finite(HBETA))], as.numeric(difftime(Sys.time(), .t0, units = "mins"))))

# =============================================================================
# 6. 회계 특성 — fundamental_merged 원값(DART 연간 + QuantiWise XLSX 분기) → 분기 TTM · YoY · 5년 평균 → usable(C4) 로 월말 as-of  ★changed(6)
#    원천 규약: 같은 (Ticker, Period, Item) 은 병합 파일이 DART 우선으로 이미 dedupe → FY≥2015 의 Q4 유량은 DART 연간 합계만 남는다.
#    → XLSX Q1~Q3 가 있으면 Q4 단일분기 = 연간 − (Q1+Q2+Q3) 로 복원, 없으면 Q4 TTM = 연간(폴백). 순이익(XLSX 부재) = 세전이익 − 법인세비용.
# =============================================================================
.FLOW <- c("Revenue", "COGS", "GrossProfit", "SGAExpense", "OperatingProfit", "PretaxIncome", "TaxExpense", "NetIncome",
           "InterestExp", "OperatingCF", "InvestCF", "FinanceCF")
.BS   <- c("TotalAssets", "CurrentAssets", "NonCurrentAssets", "CashAndEquiv", "Inventory", "AccountsRecv", "TangibleAssets",
           "IntangibleAssets", "TotalLiab", "CurrentLiab", "NonCurrentLiab", "ShortTermBorr", "LongTermBorr", "AccountsPay", "TotalEquity")
.FUND_ITEMS <- c(.FLOW, .BS)
.fm <- as.data.table(dplyr::collect(dplyr::filter(arrow::open_dataset(.FM_PATH), Item %in% .FUND_ITEMS, Source %in% c("DART", "XLSX"))))
if (!all(c("Ticker", "Period", "Item", "Value", "Source") %in% names(.fm)))
  stop(sprintf("%s 회계 패널 스키마 불일치: %s", .TAG, paste(names(.fm), collapse = ",")))
.fm[, Ticker := as.character(Ticker)]
.fm[, Item := as.character(Item)]                                          # arrow dictionary(factor) 가능 → 문자열로 통일(rbind·join 형 정합)
.fm[, Source := as.character(Source)]
.fm[, Value := as.numeric(Value)]
.fm <- .fm[Ticker %in% .mem_tk & is.finite(Value)]
if (nrow(.fm) == 0L) stop(sprintf("%s 회계 패널이 적격 종목과 0행 교차 — Ticker 형식 확인", .TAG))
.fm[, Period := as.character(Period)]
.fm[, FY := as.integer(substr(Period, 1L, 4L))]
.fm[, MM := as.integer(substr(Period, 5L, 6L))]
.fm <- .fm[is.finite(FY) & MM %in% c(3L, 6L, 9L, 12L)]
.fm[, QI := FY * 4L + MM %/% 3L]
# (a) XLSX 분기 유량 → 단일분기 (+ 순이익 파생)
.fx <- unique(.fm[Source == "XLSX" & Item %in% .FLOW, .(Ticker, FY, MM, QI, Item, Value)], by = c("Ticker", "QI", "Item"))
.pt <- .fx[Item %in% c("PretaxIncome", "TaxExpense")]
if (nrow(.pt) > 0L) {
  .ni <- dcast(.pt, Ticker + FY + MM + QI ~ Item, value.var = "Value")
  for (.cc in c("PretaxIncome", "TaxExpense")) if (!.cc %in% names(.ni)) .ni[, (.cc) := NA_real_]
  .ni <- .ni[is.finite(PretaxIncome) & is.finite(TaxExpense), .(Ticker, FY, MM, QI, Item = "NetIncome", Value = PretaxIncome - TaxExpense)]
  .fx <- rbind(.fx[Item != "NetIncome"], .ni)
  rm(.ni)
}
rm(.pt)
.xq <- .fx[Item == "Revenue", .(n_q = uniqueN(MM), s4 = sum(Value), q4 = sum(Value[MM == 12L]), has12 = any(MM == 12L)), by = .(Ticker, FY)]
.rr <- .xq[n_q == 4L & has12 == TRUE & q4 > 0 & s4 > 0, s4 / q4]
.rr_med <- if (length(.rr)) median(.rr) else NA_real_
.XQ_SINGLE <- is.finite(.rr_med) && .rr_med > 3                              # 단일분기 유량이면 4분기합/Q4 ≈ 4 · 누적이면 ≈ 2.5
if (!isTRUE(.XQ_SINGLE) && nrow(.fx) > 0L) {                                # 누적 → 단일분기: 같은 FY 의 직전 분기가 있을 때만 차분
  setorder(.fx, Ticker, Item, FY, MM)
  .fx[, prevV := shift(Value, 1L), by = .(Ticker, Item, FY)]
  .fx[, prevMM := shift(MM, 1L), by = .(Ticker, Item, FY)]
  .fx[, Value := fifelse(MM == 3L, Value, fifelse(is.finite(prevV) & prevMM == MM - 3L, Value - prevV, NA_real_))]
  .fx <- .fx[is.finite(Value)]
  .fx[, c("prevV", "prevMM") := NULL]
}
# (b) DART 연간 유량(AV12) · Q4 단일분기 복원 · 분기 격자 → TTM(연속 4분기 합) · 연간 폴백
.da <- unique(.fm[Source == "DART" & Item %in% .FLOW & MM == 12L, .(Ticker, FY, Item, AV12 = Value)], by = c("Ticker", "FY", "Item"))
if (nrow(.fx) > 0L) {
  .qw <- dcast(.fx, Ticker + FY + Item ~ MM, value.var = "Value")
} else {
  .qw <- data.table(Ticker = character(0), FY = integer(0), Item = character(0))
}
for (.cc in c("3", "6", "9", "12")) if (!.cc %in% names(.qw)) .qw[, (.cc) := NA_real_]
.qw <- merge(.qw, .da, by = c("Ticker", "FY", "Item"), all = TRUE)
.q4fix <- .qw[, is.na(`12`) & is.finite(AV12) & is.finite(`3`) & is.finite(`6`) & is.finite(`9`)]
.n_q4rec <- sum(.q4fix)
if (.n_q4rec > 0L) .qw[.q4fix, `12` := AV12 - `3` - `6` - `9`]
.ql <- melt(.qw, id.vars = c("Ticker", "FY", "Item", "AV12"), measure.vars = c("3", "6", "9", "12"), variable.name = "MM", value.name = "Value")
.ql[, MM := as.integer(as.character(MM))]
.ql[, QI := FY * 4L + MM %/% 3L]
.ql <- .ql[is.finite(Value) | (MM == 12L & is.finite(AV12))]
setorder(.ql, Ticker, Item, QI)
.ql[, ttm := frollsum(Value, 4L), by = .(Ticker, Item)]
.ql[, ok4 := shift(QI, 3L) == QI - 3L, by = .(Ticker, Item)]
.ql[!(ok4 %in% TRUE), ttm := NA_real_]
.av_fb <- .ql[, !is.finite(ttm) & MM == 12L & is.finite(AV12)]
.n_av_fb <- sum(.av_fb)
if (.n_av_fb > 0L) .ql[.av_fb, ttm := AV12]
.ql <- .ql[is.finite(ttm), .(Ticker, QI, FY, MM, Item, ttm)]
# (c) 시점 항목 — 분기말 값 (DART 우선 · 병합 파일 규약)
.bs <- .fm[Item %in% .BS, .(Ticker, QI, FY, MM, Item, ttm = Value, pri = fifelse(Source == "DART", 1L, 2L))]
setorder(.bs, Ticker, QI, Item, pri)
.bs <- unique(.bs, by = c("Ticker", "QI", "Item"))
.bs[, pri := NULL]
.FQ <- dcast(rbind(.ql, .bs), Ticker + QI + FY + MM ~ Item, value.var = "ttm")
for (.cc in .FUND_ITEMS) if (!.cc %in% names(.FQ)) .FQ[, (.cc) := NA_real_]
setkey(.FQ, Ticker, QI)
rm(.fm, .fx, .xq, .da, .qw, .ql, .bs, .q4fix, .av_fb)
# 단위 정합 진단 — 인접 분기 자산총계 비율 중앙값(2015~16 · ≈1 이어야 한다 · 교정하지 않는다)
.unit_chk <- local({
  a <- .FQ[, .(Ticker, QI, TotalAssets)]
  b <- a[, .(Ticker, QI = QI + 1L, TA_prev = TotalAssets)]
  x <- a[b, on = .(Ticker, QI), nomatch = 0L][is.finite(TotalAssets) & is.finite(TA_prev) & TA_prev > 0 & TotalAssets > 0]
  x <- x[QI %in% seq.int(2015L * 4L + 4L, 2016L * 4L + 4L)]
  if (nrow(x)) median(x$TotalAssets / x$TA_prev) else NA_real_
})
# (d) 직전 연도(QI−4) · 5년(QI−4·8·12·16) 조회
.lk <- function(col, k) { tmp <- .FQ[, .(Ticker, QI = QI + k, v = get(col))]; tmp[.FQ, on = .(Ticker, QI), x.v] }
.avg5 <- function(col) {
  M <- cbind(.FQ[[col]], .lk(col, 4L), .lk(col, 8L), .lk(col, 12L), .lk(col, 16L))
  k <- rowSums(is.finite(M)); m <- rowSums(M, na.rm = TRUE) / k
  fifelse(k >= .MIN5, m, NA_real_)
}
.egro <- function(col) {                            # 5 연간 점(오래된→최근 x = 1..5) 회귀 기울기 / 평균 |y| (점 ≥ 3)
  M <- cbind(.lk(col, 16L), .lk(col, 12L), .lk(col, 8L), .lk(col, 4L), .FQ[[col]])
  W <- is.finite(M) + 0; M0 <- M; M0[!is.finite(M)] <- 0
  xs <- matrix(1:5, nrow(M), 5L, byrow = TRUE)
  n <- rowSums(W); Sx <- rowSums(W * xs); Sxx <- rowSums(W * xs * xs); Sy <- rowSums(M0); Sxy <- rowSums(M0 * xs)
  slope <- (n * Sxy - Sx * Sy) / (n * Sxx - Sx * Sx)
  ma <- rowSums(abs(M0)) / n
  fifelse(n >= .MIN5 & is.finite(slope) & is.finite(ma) & ma > 0, slope / ma, NA_real_)
}
.FQ[, `:=`(Revenue_p = .lk("Revenue", 4L), NetIncome_p = .lk("NetIncome", 4L), PretaxIncome_p = .lk("PretaxIncome", 4L),
           OperatingProfit_p = .lk("OperatingProfit", 4L), TotalEquity_p = .lk("TotalEquity", 4L), TotalAssets_p = .lk("TotalAssets", 4L),
           OperatingCF_p = .lk("OperatingCF", 4L), InvestCF_p = .lk("InvestCF", 4L), FinanceCF_p = .lk("FinanceCF", 4L))]
.FQ[, `:=`(NI5 = .avg5("NetIncome"), CF5 = .avg5("OperatingCF"), EQ5 = .avg5("TotalEquity"), TA5 = .avg5("TotalAssets"))]
.FQ[, EGRO := .egro("NetIncome")]
# (e) 비율 — 부록 이름 · 정의 = FIDELITY feature_definitions (분모 ≤ 0 = 결측)
.FQ[, ASSI := .logpos(TotalAssets)]
.FQ[, ROE := .sdiv(NetIncome, TotalEquity)]
.FQ[, ROA := .sdiv(NetIncome, TotalAssets)]
.FQ[, ROE5 := .sdiv(NI5, EQ5)]
.FQ[, ROA5 := .sdiv(NI5, TA5)]
.FQ[, GrossIncomeRatio := .sdiv(GrossProfit, Revenue)]
.FQ[, NetProfitRatio := .sdiv(NetIncome, Revenue)]
.FQ[, OperatingProfitRatio := .sdiv(OperatingProfit, Revenue)]
.FQ[, SalesCostRatio := .sdiv(COGS, Revenue)]
.FQ[, AdminiExpenseRate := .sdiv(SGAExpense, Revenue)]
.FQ[, FinancialExpenseRate := .sdiv(InterestExp, Revenue)]
.FQ[, EBITToTOR := .sdiv(PretaxIncome + fifelse(is.finite(InterestExp), InterestExp, 0), Revenue)]
.FQ[, TaxRatio := .sdiv(TaxExpense, PretaxIncome)]
.FQ[, TotalProfitCostRatio := .sdiv(PretaxIncome, Revenue - OperatingProfit)]
.FQ[, CashRateOfSales := .sdiv(OperatingCF, Revenue)]
.FQ[, CashToCurrentLiability := .sdiv(CashAndEquiv, CurrentLiab)]
.FQ[, OperCashInToCurrentLiability := .sdiv(OperatingCF, CurrentLiab)]
.FQ[, NOCFToOperatingNI := .sdiv(OperatingCF, OperatingProfit)]
.FQ[, EquityFixedAssetRatio := .sdiv(TotalEquity, TangibleAssets)]
.FQ[, EquityToAsset := .sdiv(TotalEquity, TotalAssets)]
.FQ[, FixAssetRatio := .sdiv(TangibleAssets, TotalAssets)]
.FQ[, IntangibleAssetRatio := .sdiv(IntangibleAssets, TotalAssets)]
.FQ[, CurrentAssetsRatio := .sdiv(CurrentAssets, TotalAssets)]
.FQ[, NonCurrentAssetsRatio := .sdiv(NonCurrentAssets, TotalAssets)]
.FQ[, LongDebtToAsset := .sdiv(LongTermBorr, TotalAssets)]
.FQ[, LongTermDebtToAsset := .sdiv(NonCurrentLiab, TotalAssets)]
.FQ[, LongDebtToWorkingCapital := .sdiv(NonCurrentLiab, CurrentAssets - CurrentLiab)]
.FQ[, DebtEquityRatio := .sdiv(TotalLiab, TotalEquity)]
.FQ[, DebtsAssetRatio := .sdiv(TotalLiab, TotalAssets)]
.FQ[, CurrentRatio := .sdiv(CurrentAssets, CurrentLiab)]
.FQ[, QuickRatio := .sdiv(CurrentAssets - Inventory, CurrentLiab)]
.FQ[, BLEV := .sdiv(NonCurrentLiab + TotalEquity, TotalEquity)]
.FQ[, TotalAssetsTRate := .sdiv(Revenue, TotalAssets)]
.FQ[, CurrentAssetsTRate := .sdiv(Revenue, CurrentAssets)]
.FQ[, FixedAssetsTRate := .sdiv(Revenue, TangibleAssets)]
.FQ[, EquityTRate := .sdiv(Revenue, TotalEquity)]
.FQ[, ARTRate := .sdiv(Revenue, AccountsRecv)]
.FQ[, ARTDays := .sdiv(rep(360, .N), ARTRate)]
.FQ[, InventoryTRate := .sdiv(COGS, Inventory)]
.FQ[, InventoryTDays := .sdiv(rep(360, .N), InventoryTRate)]
.FQ[, AccountsPayablesTRate := .sdiv(COGS, AccountsPay)]
.FQ[, AccountsPayablesTDays := .sdiv(rep(360, .N), AccountsPayablesTRate)]
.FQ[, NetProfitGrowRate := .gro(NetIncome, NetIncome_p)]
.FQ[, TotalProfitGrowRate := .gro(PretaxIncome, PretaxIncome_p)]
.FQ[, OperatingProfitGrowRate := .gro(OperatingProfit, OperatingProfit_p)]
.FQ[, OperatingRevenueGrowRate := .gro(Revenue, Revenue_p)]
.FQ[, NetAssetGrowRate := .gro(TotalEquity, TotalEquity_p)]
.FQ[, TotalAssetGrowRate := .gro(TotalAssets, TotalAssets_p)]
.FQ[, OperCashGrowRate := .gro(OperatingCF, OperatingCF_p)]
.FQ[, InvestCashGrowRate := .gro(InvestCF, InvestCF_p)]
.FQ[, FinancingCashGrowRate := .gro(FinanceCF, FinanceCF_p)]
.FQ[, ACCA := fifelse(is.finite(NetIncome) & is.finite(OperatingCF) & is.finite(TotalAssets) & TotalAssets > 0, (NetIncome - OperatingCF) / TotalAssets, NA_real_)]
# (f) usable(C4): 3월 분기 → 5/15 · 6월 → 8/15 · 9월 → 11/15 · 12월(연간) → 익년 3/31 → 월말 as-of (캐리 ≤ 400일 · 시차 = 공시 규약)
.FQ[, usable := as.Date(fifelse(MM == 12L, sprintf("%d-03-31", FY + 1L),
                          fifelse(MM == 3L, sprintf("%d-05-15", FY), fifelse(MM == 6L, sprintf("%d-08-15", FY), sprintf("%d-11-15", FY)))))]
.carry <- c("NetIncome", "TotalEquity", "Revenue", "OperatingCF", "TotalAssets", "TotalLiab", "CashAndEquiv", "NonCurrentLiab", "NI5", "CF5", "QI")
.fcols <- c(.FUND_FEATS, .carry)
.n_fq <- nrow(.FQ); .n_fq_tk <- uniqueN(.FQ$Ticker); .fy_rng <- range(.FQ$FY)
.FQs <- .FQ[, c("Ticker", "usable", .fcols), with = FALSE]
setorder(.FQs, Ticker, usable)
.FQs <- unique(.FQs, by = c("Ticker", "usable"))
.tmp <- .FQs[.F[, .(Ticker, Date)], on = .(Ticker, usable = Date), roll = .FUND_CARRY]       # as-of: usable ≤ Date · 시차 적용 후 캐리 ≤ 400일
.F[, (.fcols) := .tmp[, .fcols, with = FALSE]]
rm(.tmp, .FQ, .FQs)
.fund_cov <- .F[MEM == TRUE, mean(is.finite(QI))]
cat(sprintf("%s 회계: 분기 행 %d(%d종 · FY %d~%d) · XLSX 분기값 형식 = %s(매출 4분기합/Q4 중앙 %s · n=%d) · Q4 단일분기 복원 %d · 연간 폴백 %d · 단위 정합(자산총계 인접분기 비 2015~16 중앙) %s · 적격 월말행 회계 커버리지 %.1f%% · ROE %.1f%% · EGRO %.1f%%\n",
            .TAG, .n_fq, .n_fq_tk, .fy_rng[1], .fy_rng[2], if (isTRUE(.XQ_SINGLE)) "단일분기 유량" else "누적(차분 적용)",
            if (is.finite(.rr_med)) sprintf("%.2f", .rr_med) else "NA", length(.rr), .n_q4rec, .n_av_fb,
            if (is.finite(.unit_chk)) sprintf("%.3g", .unit_chk) else "NA", 100 * .fund_cov,
            100 * .F[MEM == TRUE, mean(is.finite(ROE))], 100 * .F[MEM == TRUE, mean(is.finite(EGRO))]))
if (.fund_cov <= 0) stop(sprintf("%s 회계 패널 커버리지 0 — Ticker 형식 또는 usable 규약 확인", .TAG))
# (g) 시총 결합 특성
.F[, PE := .sdiv(Size, NetIncome)]
.F[, PB := .sdiv(Size, TotalEquity)]
.F[, PS := .sdiv(Size, Revenue)]
.F[, PCF := .sdiv(Size, OperatingCF)]
.F[, ETOP := fifelse(is.finite(NetIncome) & is.finite(Size), NetIncome / Size, NA_real_)]
.F[, CTOP := fifelse(is.finite(OperatingCF) & is.finite(Size), OperatingCF / Size, NA_real_)]
.F[, ETP5 := fifelse(is.finite(NI5) & is.finite(Size), NI5 / Size, NA_real_)]
.F[, CTP5 := fifelse(is.finite(CF5) & is.finite(Size), CF5 / Size, NA_real_)]
.F[, MLEV := fifelse(is.finite(NonCurrentLiab) & is.finite(Size), (NonCurrentLiab + Size) / Size, NA_real_)]
.F[, EV := fifelse(is.finite(TotalLiab) & is.finite(CashAndEquiv) & is.finite(Size), Size + TotalLiab - CashAndEquiv, NA_real_)]
.F[, TA2EV := .sdiv(TotalAssets, EV)]
.F[, CFO2EV := fifelse(is.finite(OperatingCF) & is.finite(EV) & EV > 0, OperatingCF / EV, NA_real_)]
.F[, shares := fifelse(is.finite(Size), Size / Close, NA_real_)]
.F[, EPS := fifelse(is.finite(NetIncome) & is.finite(shares) & shares > 0, NetIncome / shares, NA_real_)]

# =============================================================================
# 7. 분석가 컨센서스 특성 — QuantiWise eps_1y(12M fwd EPS · KRW/주) · revenue_fy1 · sue (논문 Uqer 분석가 팩터의 KR 대응)  ★changed(7)
#    관측 ≤ t 만(벤더 스냅샷 일자 = 가용일 · 저장소 규약) · 캐리 ≤ 35달력일(sue 130일) · 개정 = 20/60 거래일 전 관측 대비 변화율
#    패널 파일이 없으면 그 특성은 전부 결측(→ 표준화 후 0)으로 두고 로그에 남긴다 — 대리변수 없음 (changed(7))
# =============================================================================
.read_cons <- function(metric) {
  p <- file.path(.CONS_DIR, paste0(metric, ".parquet"))
  if (!file.exists(p)) return(data.table(Date = as.Date(character(0)), Ticker = character(0), v = numeric(0)))
  d <- as.data.table(read_parquet(p))
  if (!all(c("Date", "Ticker", metric) %in% names(d))) stop(sprintf("%s 컨센서스 %s 스키마 불일치: %s", .TAG, metric, paste(names(d), collapse = ",")))
  d <- d[, c("Date", "Ticker", metric), with = FALSE]
  setnames(d, metric, "v")
  if (!inherits(d$Date, "Date")) d[, Date := as.Date(Date)]
  d[, Ticker := as.character(Ticker)]; d[, v := as.numeric(v)]
  d <- d[is.finite(v) & Ticker %in% .mem_tk]
  d <- unique(d, by = c("Ticker", "Date"))
  setorder(d, Ticker, Date)
  d
}
.eps <- .read_cons("eps_1y"); .rev <- .read_cons("revenue_fy1"); .sue <- .read_cons("sue")
.F[.CAL, on = "Date", di := i.di]
.F[, Date_l20 := .CAL$Date[pmax(di - .REV_LAG_G, 1L)]]
.F[, Date_l60 := .CAL$Date[pmax(di - .REV_LAG_D, 1L)]]
.asof <- function(src, dcol, carry) {
  if (nrow(src) == 0L) return(rep(NA_real_, nrow(.F)))
  key <- data.table(Ticker = .F$Ticker, Date = .F[[dcol]])
  src[key, on = .(Ticker, Date), roll = carry, x.v]
}
.F[, eps1 := .asof(.eps, "Date", .CONS_CARRY)]
.F[, eps1_l20 := .asof(.eps, "Date_l20", .CONS_CARRY)]
.F[, eps1_l60 := .asof(.eps, "Date_l60", .CONS_CARRY)]
.F[, rev1 := .asof(.rev, "Date", .CONS_CARRY)]
.F[, rev1_l20 := .asof(.rev, "Date_l20", .CONS_CARRY)]
.F[, rev1_l60 := .asof(.rev, "Date_l60", .CONS_CARRY)]
.F[, SUE := .asof(.sue, "Date", .SUE_CARRY)]
# revenue_fy1 단위 판별(패널 문서 미기재): 적격 월말행에서 revenue_fy1 / 매출 TTM 의 중앙값 → 10^k 배수만 맞춘다(형식 판별 · 로그)
.rs <- .F[MEM == TRUE & is.finite(rev1) & rev1 > 0 & is.finite(Revenue) & Revenue > 0, median(rev1 / Revenue)]
.REV_SCALE <- if (length(.rs) == 1L && is.finite(.rs) && (.rs < 0.2 || .rs > 5)) 10^round(-log10(.rs)) else 1
.F[, FY12P := fifelse(is.finite(eps1) & is.finite(Close) & Close > 0, eps1 / Close, NA_real_)]
.F[, SFY12P := fifelse(is.finite(rev1) & is.finite(Size), rev1 * .REV_SCALE / Size, NA_real_)]
.F[, FEARNG := .gro(eps1 * shares, NetIncome)]
.F[, FSALESG := .gro(rev1 * .REV_SCALE, Revenue)]
.F[, DAREV := .gro(eps1, eps1_l60)]
.F[, GREV := .gro(eps1, eps1_l20)]
.F[, DASREV := .gro(rev1, rev1_l60)]
.F[, GSREV := .gro(rev1, rev1_l20)]
cat(sprintf("%s 컨센서스: eps_1y %d행 · revenue_fy1 %d행 · sue %d행 · 적격 월말행 커버리지 FY12P %.1f%% · SFY12P %.1f%% · SUE %.1f%% · revenue_fy1/매출TTM 중앙 %s → 배수 %g\n",
            .TAG, nrow(.eps), nrow(.rev), nrow(.sue),
            100 * .F[MEM == TRUE, mean(is.finite(FY12P))], 100 * .F[MEM == TRUE, mean(is.finite(SFY12P))], 100 * .F[MEM == TRUE, mean(is.finite(SUE))],
            if (length(.rs) == 1L && is.finite(.rs)) sprintf("%.3g", .rs) else "NA", .REV_SCALE))
rm(.eps, .rev, .sue)
.F[, c("eps1", "eps1_l20", "eps1_l60", "rev1", "rev1_l20", "rev1_l60", "Date_l20", "Date_l60", "EV", "shares", .carry) := NULL]
gc(verbose = FALSE)

# =============================================================================
# 8. 표적 — return-to-volatility ratio = 다음 달력월(보유월 · f = 그 달 거래일) 일간수익 평균/표준편차 (논문 식 미인쇄)  ★changed(2)
#    횡단면(월말 m · 적격 종목 · 표적 유한) 안에서 상위 Q% = 1 · 하위 Q% = 0 · 가운데 폐기 (Tail and Head Label 그대로)
# =============================================================================
.LB[, rv := fifelse(nn >= .MIN_LABEL_DAYS & is.finite(sdv) & sdv > 0, mu / sdv, NA_real_)]
.LB[, MI_sig := MI - 1L]                                                     # 달 MI 의 수익 = 달 MI−1 월말 시그널의 표적
.F[, MI := year(Date) * 12L + month(Date)]
.F[.LB, on = .(Ticker, MI = MI_sig), c("rv", "n_fwd") := .(i.rv, i.nn)]
rm(.LB); gc(verbose = FALSE)
.F <- .F[MEM == TRUE]                                                        # 이후 학습·예측 = 적격 행만 (러너 술어와 동일)
setorder(.F, Date, Ticker)
.F[, y := NA_integer_]
.F[is.finite(rv), y := {
  N <- .N
  if (N < .MIN_CS_N) rep(NA_integer_, N) else {
    k <- as.integer(floor(N * .Q_PCT / 100))
    r <- frank(-rv, ties.method = "average")
    fifelse(r <= k, 1L, fifelse(r > N - k, 0L, NA_integer_))
  }
}, by = Date]
.na_frac <- .F[, lapply(.SD, function(v) 100 * mean(!is.finite(v))), .SDcols = .FEATS]
cat(sprintf("%s 표적: 적격 월말행 %d · 표적 유한 %.1f%% · 라벨 1/0/폐기 = %d/%d/%d · 횡단면 %d개 (%s ~ %s)\n",
            .TAG, nrow(.F), 100 * .F[, mean(is.finite(rv))], .F[, sum(y == 1L, na.rm = TRUE)], .F[, sum(y == 0L, na.rm = TRUE)],
            .F[is.finite(rv), sum(is.na(y))], uniqueN(.F$Date), as.character(min(.F$Date)), as.character(max(.F$Date))))
cat(sprintf("  특성 결측률(전처리 전 · 결측 = 표준화 후 0): %s\n", paste(sprintf("%s %.0f", .FEATS, as.numeric(.na_frac[1, ])), collapse = " · ")))

# =============================================================================
# 9. 월별 롤링 학습 — 시그널 j: 학습 = 횡단면 j−1..j−6(표적 실현 완료) · 전처리(학습표본 winsor 1/99% → 표준화) →
#    LR · RF · DNN(진단) · Stacking(시간순 3분할: Train-1 · Train-2 · Validation) → 시그널일 예측  ★changed(3)(6)(8)(9)
# =============================================================================
.RF_THREADS <- max(1L, parallel::detectCores() - 1L)
.NF <- length(.FEATS)
.prep <- function(Xtr, Xp) {
  lo <- apply(Xtr, 2L, quantile, probs = .WINSOR[1], na.rm = TRUE, names = FALSE)
  hi <- apply(Xtr, 2L, quantile, probs = .WINSOR[2], na.rm = TRUE, names = FALSE)
  clip <- function(X) { for (k in seq_len(ncol(X))) if (is.finite(lo[k]) && is.finite(hi[k])) X[, k] <- pmin(pmax(X[, k], lo[k]), hi[k]); X }
  Xtr <- clip(Xtr); Xp <- clip(Xp)
  mu <- colMeans(Xtr, na.rm = TRUE); sdv <- apply(Xtr, 2L, sd, na.rm = TRUE)
  ok <- is.finite(mu) & is.finite(sdv) & sdv > 0
  z <- function(X) {
    Z <- sweep(X, 2L, ifelse(ok, mu, 0), "-"); Z <- sweep(Z, 2L, ifelse(ok, sdv, 1), "/")
    Z[, !ok] <- 0; Z[!is.finite(Z)] <- 0; Z
  }
  list(tr = z(Xtr), p = z(Xp), n_dead = sum(!ok))
}
.rf_fit <- function(X, y, seed)
  ranger(x = as.data.frame(X), y = factor(y, levels = c(0L, 1L)), num.trees = .RF_TREES, max.depth = .RF_DEPTH,
         min.node.size = .RF_MIN_NODE, probability = TRUE, seed = seed, num.threads = .RF_THREADS, verbose = FALSE)
.rf_pred <- function(f, X) predict(f, data = as.data.frame(X), num.threads = .RF_THREADS, verbose = FALSE)$predictions[, "1"]
.both <- function(y) sum(y == 1L) >= 2L && sum(y == 0L) >= 2L
.fit_lr  <- function(X, y, seed) .sgd_fit(.lr_new(ncol(X), seed), X, y, "lr", .LR_LR, .LR_DECAY, .LR_MOM, .LR_EPOCHS, .LR_BATCH, 0, seed)
.fit_dnn <- function(X, y, seed) .sgd_fit(.dnn_new(ncol(X), seed), X, y, "dnn", .DNN_LR, .DNN_DECAY, .DNN_MOM, .DNN_EPOCHS, .DNN_BATCH, .DNN_L2, seed)

.j_start <- which(.me$MEnd >= .START)[1]
if (is.na(.j_start)) stop(sprintf("%s %s 이후 완결 월말이 없다", .TAG, as.character(.START)))
.rows_f <- list(); .pred_rows <- list(); .diag <- list()
.skip <- c(no_pred = 0L, few_cs = 0L, class = 0L)
.t_loop <- Sys.time()
for (j in .j_start:nrow(.me)) {
  d <- .me$MEnd[j]
  P <- .F[Date == d]
  if (nrow(P) < .MIN_CS_N) { .skip["no_pred"] <- .skip["no_pred"] + 1L; next }
  cs <- .me$MEnd[seq.int(max(1L, j - .K_CS), j - 1L)]
  TR <- .F[Date %in% cs & !is.na(y)]
  n_cs <- uniqueN(TR$Date)
  if (n_cs < 3L) { .skip["few_cs"] <- .skip["few_cs"] + 1L; next }                     # ★changed(3) 실현 횡단면 ≥ 3 (정상 = 6)
  csd <- sort(unique(TR$Date))
  g <- as.integer(ceiling(match(TR$Date, csd) / length(csd) * 3))                        # 시간순 3등분(횡단면 단위) — Train-1 · Train-2 · Validation
  i1 <- g == 1L; i2 <- g == 2L; i3 <- g == 3L
  ytr <- TR$y
  if (!.both(ytr) || !.both(ytr[i1 | i2]) || !.both(ytr[i2]) || !.both(ytr[i3])) { .skip["class"] <- .skip["class"] + 1L; next }
  Xtr <- as.matrix(TR[, .FEATS, with = FALSE]); Xp <- as.matrix(P[, .FEATS, with = FALSE])
  storage.mode(Xtr) <- "double"; storage.mode(Xp) <- "double"
  dimnames(Xtr) <- list(NULL, .FEATS); dimnames(Xp) <- list(NULL, .FEATS)
  pp <- .prep(Xtr, Xp)
  seed <- .SEED_BASE + j
  # 개별 모델 — 전 학습표본 (논문 Table V 의 LR · RF · DNN 칸 · 진단 전용)
  m_lr  <- .fit_lr(pp$tr, ytr, seed)
  m_dnn <- .fit_dnn(pp$tr, ytr, seed + 1L)
  f_rf  <- .rf_fit(pp$tr, ytr, seed + 2L)
  # Stacking — DNN = Train-1 ∪ Train-2 · RF = Train-2 · 메타 LR = Validation 위에서 (p_RF, p_DNN) → 시그널일 점수
  m_dnn_s <- .fit_dnn(pp$tr[i1 | i2, , drop = FALSE], ytr[i1 | i2], seed + 3L)
  f_rf_s  <- .rf_fit(pp$tr[i2, , drop = FALSE], ytr[i2], seed + 4L)
  Xv <- cbind(.rf_pred(f_rf_s, pp$tr[i3, , drop = FALSE]), .nn_predict(m_dnn_s, pp$tr[i3, , drop = FALSE], "dnn"))
  colnames(Xv) <- c("p_rf", "p_dnn")
  m_meta <- .fit_lr(Xv, ytr[i3], seed + 5L)
  Xq <- cbind(.rf_pred(f_rf_s, pp$p), .nn_predict(m_dnn_s, pp$p, "dnn")); colnames(Xq) <- c("p_rf", "p_dnn")
  s_stack <- .nn_predict(m_meta, Xq, "lr")
  s_lr <- .nn_predict(m_lr, pp$p, "lr"); s_dnn <- .nn_predict(m_dnn, pp$p, "dnn"); s_rf <- .rf_pred(f_rf, pp$p)
  if (!all(is.finite(s_stack))) stop(sprintf("%s %s Stacking 점수 비유한 — 학습 발산", .TAG, as.character(d)))
  cr <- suppressWarnings(cor(Xq[, 1L], Xq[, 2L]))
  .rows_f[[length(.rows_f) + 1L]] <- data.table(Date = d, Ticker = P$Ticker, Score = as.numeric(s_stack))
  .pred_rows[[length(.pred_rows) + 1L]] <- data.table(Date = d, Ticker = P$Ticker, s_lr = s_lr, s_rf = s_rf, s_dnn = s_dnn, s_stack = as.numeric(s_stack))
  .diag[[length(.diag) + 1L]] <- data.table(Date = d, N = nrow(P), n_train = nrow(TR), n_cs = n_cs, n1 = sum(ytr == 1L), n_t1 = sum(i1), n_t2 = sum(i2), n_val = sum(i3),
                                           n_dead = pp$n_dead, it_dnn = m_dnn$it, loss_dnn = m_dnn$last_loss, loss_lr = m_lr$last_loss,
                                           loss_meta = m_meta$last_loss, skip_b = m_dnn$n_skip + m_dnn_s$n_skip,
                                           sd_stack = sd(s_stack), cor_rf_dnn = cr)
  if (length(.rows_f) %% 12L == 0L || length(.rows_f) <= 2L)
    cat(sprintf("%s   %s · N %d · 학습 %d(횡단면 %d · 1=%d) · 분할 %d/%d/%d · 죽은 특성 %d · DNN 스텝 %d 손실 %.3f · 메타 손실 %.3f · Stacking sd %.3f · cor(RF,DNN) %.2f · 경과 %.1f분\n",
                .TAG, as.character(d), nrow(P), nrow(TR), n_cs, sum(ytr == 1L), sum(i1), sum(i2), sum(i3), pp$n_dead, m_dnn$it, m_dnn$last_loss,
                m_meta$last_loss, sd(s_stack), cr, as.numeric(difftime(Sys.time(), .t_loop, units = "mins"))))
}

# =============================================================================
# 10. 조립 · 검산 · 요약 (구성 요약 — 성과 수치 선언 아님. 등급은 계약이 낸다)
# =============================================================================
if (length(.rows_f) == 0L)
  stop(sprintf("%s 발행 행 0 — 건너뜀: 예측 없음 %d · 횡단면 부족 %d · 클래스 부족 %d", .TAG, .skip[["no_pred"]], .skip[["few_cs"]], .skip[["class"]]))
FACTORS <- rbindlist(.rows_f, use.names = TRUE)
setorder(FACTORS, Date, Ticker)
if (anyDuplicated(FACTORS, by = c("Date", "Ticker")) > 0L) stop(sprintf("%s FACTORS (Date,Ticker) 중복", .TAG))
if (!all(is.finite(FACTORS$Score))) stop(sprintf("%s FACTORS Score 비유한값 %d건", .TAG, sum(!is.finite(FACTORS$Score))))
if (max(FACTORS$Date) > max(RAWDATA$Date)) stop(sprintf("%s 시그널일이 RAWDATA 범위 밖", .TAG))
# 사후 진단 — 발행 후 실현된 다음 달 표적(Tail/Head) 대비 각 모델의 월별 AUC 평균 (발행에 영향 없음 · 논문 Table V 대응 · 성과 아님)
.PR <- rbindlist(.pred_rows, use.names = TRUE)
.PR[.F, on = .(Date, Ticker), y := i.y]
.AU <- .PR[!is.na(y), .(lr = .auc(s_lr, y), rf = .auc(s_rf, y), dnn = .auc(s_dnn, y), stack = .auc(s_stack, y), n = .N), by = Date]
.DG <- rbindlist(.diag, use.names = TRUE)
.mins <- as.numeric(difftime(Sys.time(), .t0, units = "mins"))
cat(sprintf("%s adapted(기전 = 논문 그대로: Tail/Head 라벨(Q %d%% · 가운데 폐기) · LR SGD-Nesterov · RF 100×depth4 · DNN n→⌊n/2⌋→⌊n/4⌋ ReLU Dropout BN Softmax L2 · Stacking(Train-1/Train-2/Validation · 메타 LR) · 부록 Uqer 팩터 이름): 특성 %d/124 고유 이름(244 토큰) · f = 보유월 거래일 · 학습 = 최근 %d 월말 횡단면 · 매월 재학습 · 유니버스 K200∪KQ150 · 유동성 스크린 없음 · 팩터 DB 미사용 · GA 특성선택 미구현\n",
            .TAG, as.integer(.Q_PCT), .NF, .K_CS))
cat(sprintf("  발행 %d개월 (%s ~ %s) · 건너뜀 예측없음 %d · 횡단면부족 %d · 클래스부족 %d · 횡단면 N %d~%d(중앙 %d) · 학습행 %d~%d(중앙 %d · 횡단면 %d~%d) · 죽은 특성 0~%d · BN 건너뛴 배치 합 %d\n",
            nrow(.DG), as.character(min(.DG$Date)), as.character(max(.DG$Date)), .skip[["no_pred"]], .skip[["few_cs"]], .skip[["class"]],
            min(.DG$N), max(.DG$N), as.integer(median(.DG$N)), min(.DG$n_train), max(.DG$n_train), as.integer(median(.DG$n_train)),
            min(.DG$n_cs), max(.DG$n_cs), max(.DG$n_dead), sum(.DG$skip_b)))
cat(sprintf("  사후 월별 AUC 평균(다음 달 Tail/Head 실현 표적 · 진단): LR %.3f · RF %.3f · DNN %.3f · Stacking %.3f (월 %d · 논문 Table V: 0.964 · 0.965 · 0.970 · 0.972) · cor(p_RF,p_DNN) 중앙 %.2f · Stacking sd 중앙 %.3f\n",
            mean(.AU$lr, na.rm = TRUE), mean(.AU$rf, na.rm = TRUE), mean(.AU$dnn, na.rm = TRUE), mean(.AU$stack, na.rm = TRUE), nrow(.AU),
            median(.DG$cor_rf_dnn, na.rm = TRUE), median(.DG$sd_stack, na.rm = TRUE)))
cat(sprintf("  FACTORS %d행 · %.1f분 · 러너 사양 = FIDELITY 파일 portfolio_spec(top_n_long · ew · monthly · n_long 25) · commission_paper = null(논문 비용 무명시 → gross 병기)\n",
            nrow(FACTORS), .mins))
rm(.PR, .AU, .DG, .F, .CAL, .me, .rows_f, .pred_rows, .diag); gc(verbose = FALSE)

FACTORS <- FACTORS[, .(Date, Ticker, Score)]
