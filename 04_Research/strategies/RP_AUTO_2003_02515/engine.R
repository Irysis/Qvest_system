# =============================================================================
# engine.R — RP_AUTO_2003_02515  (2판 · 2026-09-12 — 1판이 적대적 충실도 감사에서 misdeclared 로 기각된 뒤 재구현)
# Steven Y. K. Wong · Jennifer Chan · Lamiae Azizi · Richard Y. D. Xu,
#   "Time-varying neural network for stock return prediction"  arXiv:2003.02515
#   (v1 2020-03-05 'Non-stationary neural network for stock return prediction' · v4 2021-01-22)
#   https://arxiv.org/abs/2003.02515 — 본문 = arxiv.org/html/2003.02515v1 · v4 + r.jina.ai PDF 텍스트 프록시
#
# ★라벨(adapted)·변경 전수 신고·러너 사양의 정본 = FIDELITY.json. 이 주석은 아무것도 결정하지 않는다.
#   코드 옆 ★changed(n) 표식 = FIDELITY.json changed 의 항목 번호.
#
# 2판에서 바뀐 것 = 감사가 지적한 **특성 전처리 사슬** 하나다. 1판은 월간 팩터 DB 의 Z_Score_Aligned
#   (전체 상장 유니버스 1%/99% clip → z → ±3 clip → 재표준화 → 부호정렬)를 순위로 바꿔 썼다. 논문
#   (§5.1 'cross-sectionally ranked and scaled to [−1,1]' · Table 3 'Rank [−1,1]; Fill median')에는 특성
#   winsorize 가 없고, 그 clip 이 K200 상단에 동률을 만들었다. 정본 커넥터(load_month_factors)는 clip 전
#   값을 노출하지 않고 파케이 직접 로드는 C15 금지라, 2판은 **팩터 DB 를 전혀 쓰지 않는다**: 논문의 특성
#   원천인 Gu-Kelly-Xiu(2020) 94 특성 중 가격·거래량·시가총액만으로 정의되는 19개(논문 §5.3 중요도 상위
#   10 = idiovol·mvel1·dolvol·retvol·beta·mom12m·betasq·mom6m·ill·maxret 전부 포함)를 RAWDATA 에서
#   **원값**으로 계산하고, 그 달 투자 유니버스(K200∪KQ150) 안에서 순위 → [−1,1] · 결측 = 0(중앙값)으로
#   만든다. 회계·애널리스트·배당·호가 기반 특성은 넣지 않았다(changed(4) · data_gap).
#   신경망·OES·표적·데실은 1판 그대로다(감사 timing/universe/portfolio/cost 축 = faithful).
#
# 구현 = 논문 §3.2 Algorithm 1(online early stopping, OES) + Algorithm 2(EarlyStopping) 을
#   Table 3 사양(은닉 32-16-8 · ReLU/Linear · MSE · ADAM · L1 {1e-5,1e-4,1e-3} · η {0.001,0.01} ·
#   batch 1,000 · patience 5 · tolerance 0.001 · batch normalization · 앙상블 10 평균)으로
#   순수 R(행렬 연산)에 옮긴 것. 하이퍼파라미터는 논문처럼 초기(워밍업) 구간에서 **1회** 선택
#   (§5.1 "Hyperparameter tuning is only performed once on this period … lowest monthly average MSE").
#   Algorithm 1 축자:
#     for t = 2..T:  τ', θ*_{t−1} ← EarlyStopping(θ*_{t−2}, X_{t−2}, r_{t−2}, X_{t−1}, r_{t−1})
#                    τ̄_{t−1} ← 지금까지의 τ' 평균;  θ ← θ*_{t−1};  θ ← θ − η∇̂J_{t−1}(θ)  ⌊τ̄+0.5⌋회
#                    θ_t ← θ;  r̂_t ← F(X_t; θ_t)
#   Algorithm 2 축자: 학습 J(train) 한 스텝마다 J(test) 평가 → 최소 J(test) 의 (k, θ) 반환,
#                    ε(0.001) 이상 개선 없는 스텝이 Q(5)회 연속이면 중단.
#   입력 = 횡단면 순위 [−1,1] 특성 19 + 업종 더미(논문 SIC 2자리 74개 → KR 업종 슬롯 64) · 매크로 상호작용항 없음.
#   표적 = 익월 수익(§5.4: "winsorize excess returns at 1% and 99% for each month … standardized by subtracting
#          the cross-sectional mean and dividing by cross-sectional standard deviation" — 무위험수익률은 횡단면
#          표준화에서 상쇄된다, changed(7)).
#   포트폴리오 = 예측수익 십분위, P10(롱) − P1(숏) 스프레드 (§5.2 Table 5 · SR 정의 = P10−P1 월 스프레드).
#
# 산출: FACTORS(Date, Ticker, Score)          — 유니버스 전 종목 · Score = 앙상블 10 평균 예측(표준화 척도)
#       PORTFOLIO(Date, Ticker, Weight, Leg)  — 상위 데실 롱 EW Σ=+1 / 하위 데실 숏 EW Σ=−1
#
# PIT(C1~C15) 구조 보장: 시그널 d_j = 달 j 의 마지막 거래일. 그 시점의 코드 접근 = 특성 X_{j−2}, X_{j−1}, X_j
#   (전부 Date ≤ 해당 월말의 RAWDATA 행만: 월내 일간 집계는 달력월 안 · 월간 종가는 그 달 안 마지막 관측 ·
#   주간 창은 주말일 ≤ 월말인 주만 · 시총·업종은 월말 당일 행) 와 r_{j−2} = P[d_{j−1}]/P[d_{j−2}]−1,
#   r_{j−1} = P[d_j]/P[d_{j−1}]−1 (전부 d_j 이전에 실현). 집행 = 달 j+1 첫 거래일(러너 get_execution_date).
#   전 표본 통계 0건(순위·winsorize·표준화 = 그 달 횡단면만 · 회귀 창 = 과거 156주 롤링) ·
#   하이퍼파라미터 선택 = OOS 시작 전 워밍업 구간 데이터만 · 멤버십 = d 당일 RAWDATA 행의 K200|KQ150 플래그.
#   팩터 DB 미사용 → C13/C15 대상 코드 없음. 유동성 스크린 없음(논문 우선) → C10 대상 코드 없음.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.TAG <- "[RP_AUTO_2003_02515]"
.REQ <- c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("%s RAWDATA 필수 열 부재: %s", .TAG, paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))
.t0 <- Sys.time()

# =============================================================================
# 0. 상수 — 논문 Table 3 명시값 + 특성 정의 창(Gu-Kelly-Xiu 2020 Table A.6) + 논문이 침묵하는 규약(전부 FIDELITY.json changed 신고)
# =============================================================================
.NN_HIDDEN   <- c(32L, 16L, 8L)          # Table 3: Hidden layers 32-16-8
.LR_SET      <- c(0.001, 0.01)           # Table 3: Learning rate η {0.001, 0.01}
.L1_SET      <- c(1e-5, 1e-4, 1e-3)      # Table 3: L1 penalty {1e-5, 1e-4, 1e-3}
.BATCH       <- 1000L                    # Table 3: Batch size OES 1,000 (KR 횡단면 < 1,000 → 매 스텝 전량 배치)
.ES_PATIENCE <- 5L                       # Table 3: Early stopping patience 5
.ES_TOL      <- 1e-3                     # Table 3: Tolerance 0.001
.N_ENSEMBLE  <- 10L                      # Table 3: Ensemble — average over 10
.N_GRP       <- 10L                      # §5.2 decile portfolios
.WINSOR      <- c(0.01, 0.99)            # §5.4 winsorize (표적) at 1% and 99% each month — 특성에는 적용하지 않는다
.TRAIN_FRAC  <- 18 / 30                  # §5.1 초기 구간 분할 = 학습 18년 : 검증 12년 (비율만 이식)
.ES_MAX      <- 100L                     # ★changed(9)  Algorithm 2 의 T(최대 반복) 는 논문 미명시 → 상한 100
.ADAM_B1 <- 0.9; .ADAM_B2 <- 0.999; .ADAM_EPS <- 1e-7    # ★changed(10) ADAM 모멘트 계수 = Keras 기본값(논문 미명시)
.BN_MOM  <- 0.99; .BN_EPS <- 1e-3                        # ★changed(11) BN momentum/epsilon = Keras 기본값(논문 미명시)
.OOS_START   <- (if (exists(".RP_START_DATE")) .RP_START_DATE else as.Date("2005-01-01"))    # 고정 축(기간 2005-01-01~) — 이 날 이후 시그널만 산출
.MIN_WARM    <- 12L                      # ★changed(13) 워밍업 유효 월 하한(미달 시 OOS 시작을 뒤로 민다 — 로그로 드러난다)
.SEC_CAP     <- 64L                      # ★changed(6)  업종 더미 슬롯 용량(첫 등장 순 배정 · 초과 업종은 더미 없음)
.SEED_BASE   <- 2003L                    # ★changed(12) 앙상블 시드 = 2003 + 1..10 (임의 상수 · 재현성)
.SEED_GCHK   <- 20200305L                # ★changed(12) 기울기 검산용 시드(논문 v1 게재일 — 임의 상수)
.GCHK_TOL    <- 1e-4                     # ★changed(12) 기울기 검산 허용 상대오차(99 백분위)
# 특성 정의 창 — Gu-Kelly-Xiu(2020) Table A.6 / Green-Hand-Zhang(2017)  ★changed(4)(5)
.W_LEN       <- 156L                     # beta·idiovol·pricedelay: 주간 수익 3년(=156주) 창
.W_MIN       <- 52L                      # beta 'at least 52 weeks of returns' — idiovol·pricedelay 에도 같은 하한 적용(신고)
.PD_LAGS     <- 4L                       # pricedelay: 시장 주간수익 4 시차
.ZT_DEFL     <- 480000                   # zerotrade: Liu(2006)/GHZ 회전율 항 deflator ((1/turnover)/deflator ∈ (0,1) 이면 동률 판별기로만 작용)
.DAYS_M      <- 21                       # zerotrade: 월 거래일 정규화 상수 21 (Liu 2006)
.FEATS <- c("beta", "betasq", "chmom", "dolvol", "idiovol", "ill", "indmom", "maxret",
            "mom12m", "mom1m", "mom36m", "mom6m", "mvel1", "pricedelay", "retvol",
            "std_dolvol", "std_turn", "turn", "zerotrade")
.ym <- function(mi) sprintf("%d-%02d", (mi - 1L) %/% 12L, (mi - 1L) %% 12L + 1L)
.logpos <- function(x) { y <- rep(NA_real_, length(x)); ok <- is.finite(x) & x > 0; y[ok] <- log(x[ok]); y }

# =============================================================================
# 1. 일간 패널 (RAWDATA 비파괴 복사본) — 열 정체: Close = 수정주가 · Vol = 주식수 거래량 · Size = 시가총액(KRW)
#    (compute_liquidity.R:36-63 · compute_size.R:38-48 · krx_build_rawdata.R:113-114 규약) · Ret = 인프라 일간수익률(있으면)
# =============================================================================
.has_sector <- "Sector" %in% names(RAWDATA)                                  # ★changed(6)
.has_ret    <- "Ret" %in% names(RAWDATA)                                     # ★changed(3)
.cols <- c(.REQ, if (.has_sector) "Sector", if (.has_ret) "Ret")
.rd <- RAWDATA[is.finite(Close) & Close > 0, .cols, with = FALSE]           # ★changed(15) 종가 유한·>0 행만
.rd[, Ticker := as.character(Ticker)]
.rd[, MEM := (K200 == TRUE | KQ150 == TRUE) %in% TRUE]                       # ★changed(1) 러너 .apply_universe 와 같은 술어
if (.has_sector) .rd[, SEC := as.character(Sector)] else .rd[, SEC := NA_character_]
.rd[, Vol := as.numeric(Vol)]
.rd[, Size := as.numeric(Size)]
.rd[, c("K200", "KQ150", if (.has_sector) "Sector") := NULL]
if (!inherits(.rd$Date, "Date")) .rd[, Date := as.Date(Date)]
setorder(.rd, Ticker, Date)
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("%s (Ticker,Date) 중복 %d행 — 첫 행만 유지\n", .TAG, .ndup))                 # ★changed(15)
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}
if (.has_ret) .rd[, Ret := as.numeric(Ret)] else .rd[, Ret := Close / shift(Close) - 1, by = Ticker]   # ★changed(3)
.rd[, MI := year(Date) * 12L + month(Date)]
.rd[, WK := (as.integer(Date) + 3L) %/% 7L]                                  # ★changed(5) 달력 주(월~일) 인덱스 — locale 무관
.n_rd <- nrow(.rd)

# 시장 월말 = 그 달력월의 마지막 거래일(전 종목 통합). 마지막 달력월은 진행 중(부분월)으로 보고 제외.  ★changed(14)
.me <- .rd[, .(MEnd = max(Date)), by = MI]
setorder(.me, MI)
.MI_LAST <- max(.me$MI)
.me <- .me[MI < .MI_LAST]
if (nrow(.me) < 40L) stop(sprintf("%s 완결 월 %d개 — RAWDATA 날짜 범위 확인", .TAG, nrow(.me)))

# 월말 당일 행 — 적격(멤버십) 집합 + 전 종목 업종 라벨(더미 · 업종 모멘텀용)                   ★changed(1)(2)(6)
.rd[, MEnd := .me$MEnd[match(MI, .me$MI)]]
.mer <- .rd[!is.na(MEnd) & Date == MEnd, .(MI, Ticker, MEM, SEC)]
.EL     <- split(.mer$Ticker[.mer$MEM], .mer$MI[.mer$MEM])
.SECALL <- split(setNames(.mer$SEC, .mer$Ticker), .mer$MI)
.rd[, c("MEnd", "MEM", "SEC") := NULL]
rm(.mer)

# =============================================================================
# 2. 월내 일간 집계(전 종목 · 달력월 = 그 달 안 행만) — GKX Table A.6 의 '일간→월간' 특성 재료           ★changed(4)(5)
#    dv = Vol×Close(KRW 거래대금) · 회전율 = dv/Size(= Vol / (Size/Close), 주식수 = Size/Close) · amih = |Ret|/dv
# =============================================================================
.rd[, dv := fifelse(is.finite(Vol) & Vol > 0, Vol * Close, NA_real_)]
.rd[, ldv := log(dv)]
.rd[, tr := fifelse(is.finite(dv) & is.finite(Size) & Size > 0, dv / Size, NA_real_)]
.rd[, amih := fifelse(is.finite(dv) & is.finite(Ret), abs(Ret) / dv, NA_real_)]
.rd[, zt := !is.finite(dv)]                                                  # 거래량 0·결측 일 = 무거래일(Liu 2006 zero-volume day)
.MA <- suppressWarnings(.rd[, .(
  n_d = .N,
  retvol = sd(Ret, na.rm = TRUE), maxret = max(Ret, na.rm = TRUE),
  ill = mean(amih, na.rm = TRUE),
  std_dolvol = sd(ldv, na.rm = TRUE), std_turn = sd(tr, na.rm = TRUE),
  n_zero = sum(zt), vol_sum = sum(Vol, na.rm = TRUE), dvol_sum = sum(dv, na.rm = TRUE),
  size_end = last(Size), close_end = last(Close)), by = .(Ticker, MI)])
.MA[!is.finite(retvol), retvol := NA_real_]
.MA[!is.finite(maxret), maxret := NA_real_]
.MA[!is.finite(ill), ill := NA_real_]
.MA[!is.finite(std_dolvol), std_dolvol := NA_real_]
.MA[!is.finite(std_turn), std_turn := NA_real_]
.MA[, shares_end := fifelse(is.finite(size_end) & size_end > 0, size_end / close_end, NA_real_)]
setkey(.MA, Ticker, MI)
.rd[, c("dv", "ldv", "tr", "amih", "zt", "Vol", "Size", "Ret") := NULL]
gc(verbose = FALSE)

# 월간 종가 패널(달력월 안 마지막 관측 종가) — 모멘텀 특성 + 표적                                      ★changed(3)
.wide <- dcast(.MA[, .(MI, Ticker, close_end)], MI ~ Ticker, value.var = "close_end")
setorder(.wide, MI)
.MIs <- .wide$MI
if (any(diff(.MIs) != 1L))
  stop(sprintf("%s 월 인덱스가 연속이 아님 — 거래 데이터가 통째로 빈 달이 있다", .TAG))   # ★changed(15)
.TK <- setdiff(names(.wide), "MI")
.P  <- as.matrix(.wide[, .TK, with = FALSE])
colnames(.P) <- .TK
rm(.wide)

# =============================================================================
# 3. 주간 패널(전 종목) — beta · idiovol · pricedelay 재료. 주 = 달력 주(월~일), 주간 종가 = 그 주 안 마지막 관측 종가,
#    주말일 = 그 주의 마지막 거래일(시장 통합). 주간수익 = 거래가 있었던 연속 두 주의 종가 비율.
#    시장 = RAWDATA 전 종목 주간수익의 동일가중 평균(GKX 'equal weighted market returns')                ★changed(5)
# =============================================================================
.wke <- .rd[, .(WEnd = max(Date)), by = WK]
setorder(.wke, WK)
.wp  <- .rd[, .(P = last(Close)), by = .(Ticker, WK)]
.ww  <- dcast(.wp, WK ~ Ticker, value.var = "P")
setorder(.ww, WK)
if (!identical(.ww$WK, .wke$WK)) stop(sprintf("%s 주간 격자 불일치", .TAG))
.PW <- as.matrix(.ww[, setdiff(names(.ww), "WK"), with = FALSE])
.RW <- .PW[-1L, , drop = FALSE] / .PW[-nrow(.PW), , drop = FALSE] - 1        # 행 w = 주 w 의 수익(직전 거래 주 대비)
.WEND <- .wke$WEnd[-1L]                                                      # 행 w 의 주말일(그 주 마지막 거래일)
.MW <- rowMeans(.RW, na.rm = TRUE)
.MW[!is.finite(.MW)] <- NA_real_
.mw_top <- head(order(-abs(.MW), na.last = NA), 3L)                          # 시장 주간수익 극단 3주 — 원천 이음매 결함(×5·×2 점프)이 남아 있으면 여기 드러난다
cat(sprintf("%s 시장(EW) 주간수익 극단 3주: %s\n", .TAG,
            paste(sprintf("%s %+.1f%%", as.character(.WEND[.mw_top]), 100 * .MW[.mw_top]), collapse = " · ")))
rm(.wp, .ww, .PW, .wke, .rd)
gc(verbose = FALSE)
cat(sprintf("%s 일간 행 %d → 월간 패널 %d개월 (%s ~ %s) × %d종 · 주간 패널 %d주 · 마지막 부분월 %s 제외 · 완결 월말 %d개 · 적격 집합 있는 달 %d · Sector 열 %s · Ret 열 %s\n",
            .TAG, .n_rd, nrow(.P), .ym(min(.MIs)), .ym(max(.MIs)), length(.TK), nrow(.RW), .ym(.MI_LAST),
            nrow(.me), length(.EL), if (.has_sector) "있음" else "없음(업종 더미 전부 0 · indmom 결측)",
            if (.has_ret) "있음(인프라 값 사용)" else "없음(Close 비율로 계산)"))

# =============================================================================
# 4. 특성 행렬 — 19 특성 원값 → 그 달 투자 유니버스 안 횡단면 순위 [−1,1] (동률 = 평균 순위 · 결측 = 0 = 중앙값)
#    + 업종 더미. 논문 §5.1/Table 3 전처리 그대로 — clip·winsorize·표준화 없음.                          ★changed(4)
# =============================================================================
.rank11 <- function(x) {
  ok <- is.finite(x); n <- sum(ok); out <- numeric(length(x))
  if (n >= 2L) out[ok] <- 2 * (frank(x[ok], ties.method = "average") - 1) / (n - 1) - 1
  out
}

# 단순회귀(절편 포함) 벡터화 — 열별 결측 마스크. beta = cov/var · idiovol = 잔차 표준편차(자유도 n−2)   ★changed(5)
.beta_idio <- function(Y, x) {
  M  <- is.finite(Y)
  Y0 <- Y; Y0[!M] <- 0
  Mn <- M + 0
  n   <- colSums(Mn)
  Sx  <- as.vector(crossprod(Mn, x))
  Sxx <- as.vector(crossprod(Mn, x * x))
  Sy  <- colSums(Y0)
  Sxy <- as.vector(crossprod(Y0, x))
  Syy <- colSums(Y0 * Y0)
  vx  <- n * Sxx - Sx * Sx
  beta <- (n * Sxy - Sx * Sy) / vx
  rss  <- (Syy - Sy * Sy / n) - beta * beta * (Sxx - Sx * Sx / n)
  idio <- sqrt(pmax(rss, 0) / (n - 2))
  bad <- !(n >= .W_MIN) | !(vx > 0) | !is.finite(beta)
  beta[bad] <- NA_real_; idio[bad] <- NA_real_
  list(beta = beta, idiovol = idio)
}
# OLS R² (절편 포함 설계행렬 X) — pricedelay 용. 특이행렬이면 NA.
.ols_r2 <- function(y, X) {
  b <- tryCatch(solve(crossprod(X), crossprod(X, y)), error = function(e) NULL)
  if (is.null(b)) return(NA_real_)
  e  <- y - as.vector(X %*% b)
  yc <- y - sum(y) / length(y)
  sst <- sum(yc * yc)
  if (!(sst > 0)) return(NA_real_)
  1 - sum(e * e) / sst
}

# 19 특성 원값 (n × 19, NA 허용) — 달 j 월말 d_j 시점, 종목 tk. 정의 = GKX(2020) Table A.6 (FIDELITY changed(4) 축자)
.features <- function(j, tk) {
  mi <- .me$MI[j]; d <- .me$MEnd[j]; key <- as.character(mi)
  ir <- match(mi, .MIs)
  n  <- length(tk)
  F  <- matrix(NA_real_, n, length(.FEATS), dimnames = list(tk, .FEATS))
  # (a) 월간 종가 모멘텀 — P0 = 달 j 종가(= d_j 이전 그 달 마지막 관측)
  pick <- function(k) if (ir - k >= 1L) .P[ir - k, tk] else rep(NA_real_, n)
  P0 <- pick(0L); P1 <- pick(1L); P6 <- pick(6L); P12 <- pick(12L); P36 <- pick(36L)
  F[, "mom1m"]  <- P0 / P1 - 1                          # 1-month cumulative return
  F[, "mom6m"]  <- P1 / P6 - 1                          # 5-month cumulative returns ending one month before month end
  F[, "mom12m"] <- P1 / P12 - 1                         # 11-month cumulative returns ending one month before month end
  F[, "mom36m"] <- P12 / P36 - 1                        # cumulative returns from months t−36 to t−13
  F[, "chmom"]  <- (P0 / P6 - 1) - (P6 / P12 - 1)       # months t−6..t−1 minus t−12..t−7
  # (b) 업종 모멘텀 — 그 달 월말 행이 있고 업종 라벨이 있는 RAWDATA 전 종목의 mom12m 업종 평균           ★changed(6)
  if (ir - 12L >= 1L) {
    m12_all <- .P[ir - 1L, ] / .P[ir - 12L, ] - 1
    sec_all <- .SECALL[[key]]
    if (!is.null(sec_all)) {
      ok <- !is.na(sec_all) & nzchar(sec_all)
      if (any(ok)) {
        di <- data.table(SEC = unname(sec_all[ok]), m12 = unname(m12_all[names(sec_all)[ok]]))
        di <- di[is.finite(m12)]
        if (nrow(di)) {
          im <- di[, .(im = mean(m12)), by = SEC]
          F[, "indmom"] <- im$im[match(unname(sec_all[tk]), im$SEC)]
        }
      }
    }
  }
  # (c) 월내 일간 집계 — 달 j (A0) · 달 j−1 (A1) · 달 j−2 (A2)
  A0 <- .MA[.(tk, mi)]
  A1 <- .MA[.(tk, mi - 1L)]
  A2 <- .MA[.(tk, mi - 2L)]
  F[, "retvol"]     <- A0$retvol                        # sd of daily returns, month t−1
  F[, "maxret"]     <- A0$maxret                        # max daily return, calendar month t−1
  F[, "ill"]        <- A0$ill                           # average daily |ret| / KRW volume
  F[, "std_dolvol"] <- A0$std_dolvol                    # monthly sd of daily log KRW volume
  F[, "std_turn"]   <- A0$std_turn                      # monthly sd of daily share turnover
  F[, "mvel1"]      <- .logpos(A0$size_end)             # log market cap at end of month t−1
  F[, "dolvol"]     <- .logpos(A1$dvol_sum)             # log KRW volume, month t−2
  sh <- A0$shares_end
  turn_m <- A0$vol_sum / sh
  F[, "zerotrade"]  <- (A0$n_zero + (1 / turn_m) / .ZT_DEFL) * .DAYS_M / A0$n_d    # Liu(2006) LM1 — 회전율 ≤ 0 이면 비유한 → 결측
  F[, "turn"]       <- (A0$vol_sum + A1$vol_sum + A2$vol_sum) / 3 / sh             # 3-month avg volume / shares outstanding
  # (d) 주간 회귀 — 주말일 ≤ d_j 인 최근 156주(시장 4 시차 확보분) · 종목별 유효 주 ≥ 52
  iw_all <- which(.WEND <= d)
  iw_all <- iw_all[iw_all > .PD_LAGS]
  if (length(iw_all) >= .W_MIN) {
    iw <- tail(iw_all, .W_LEN)
    x  <- .MW[iw]
    L  <- cbind(.MW[iw - 1L], .MW[iw - 2L], .MW[iw - 3L], .MW[iw - 4L])
    okm <- is.finite(x) & is.finite(rowSums(L))
    iw <- iw[okm]; x <- x[okm]; L <- L[okm, , drop = FALSE]
    if (length(iw) >= .W_MIN) {
      Y <- matrix(NA_real_, length(iw), n)
      ci <- match(tk, colnames(.RW))
      hit <- !is.na(ci)
      if (any(hit)) Y[, hit] <- .RW[iw, ci[hit], drop = FALSE]
      bi <- .beta_idio(Y, x)
      F[, "beta"]    <- bi$beta
      F[, "betasq"]  <- bi$beta * bi$beta
      F[, "idiovol"] <- bi$idiovol
      Xu <- cbind(1, x, L); Xr <- cbind(1, x)
      pd <- rep(NA_real_, n)
      for (i in seq_len(n)) {
        y <- Y[, i]; ok <- is.finite(y)
        if (sum(ok) < .W_MIN) next
        r2u <- .ols_r2(y[ok], Xu[ok, , drop = FALSE])
        r2r <- .ols_r2(y[ok], Xr[ok, , drop = FALSE])
        if (is.finite(r2u) && is.finite(r2r) && r2u > 0) pd[i] <- 1 - r2r / r2u
      }
      F[, "pricedelay"] <- pd                          # Hou-Moskowitz D1: 1 − R²(contemp.)/R²(contemp.+4 lags)
    }
  }
  F
}

# 업종 더미 — 슬롯은 업종 라벨의 첫 등장 순으로 배정(PIT · 고정 차원)                                    ★changed(6)
.SEC <- new.env()
.SEC$map <- integer(0)
.SEC$overflow <- character(0)
.sector_dummies <- function(sec) {
  n <- length(sec)
  D <- matrix(0, n, .SEC_CAP)
  lv <- sec[!is.na(sec) & nzchar(sec)]
  new_lv <- setdiff(unique(lv), names(.SEC$map))
  if (length(new_lv)) {
    free <- .SEC_CAP - length(.SEC$map)
    take <- if (free > 0L) head(sort(new_lv), free) else character(0)
    if (length(take)) .SEC$map <- c(.SEC$map, setNames(length(.SEC$map) + seq_along(take), take))
    if (length(new_lv) > length(take)) .SEC$overflow <- unique(c(.SEC$overflow, setdiff(new_lv, take)))
  }
  idx <- unname(.SEC$map[sec])
  ok <- !is.na(idx)
  if (any(ok)) D[cbind(which(ok), idx[ok])] <- 1
  colnames(D) <- sprintf("SEC_%02d", seq_len(.SEC_CAP))
  D
}

# 특성 행렬 X (n × (19 + 64)) — 행 = 그 달 적격 종목 전부(특성이 전부 결측인 종목도 논문 규약대로 중앙값(0) 행으로 남는다)
.build_X <- function(j) {
  key <- as.character(.me$MI[j])
  tk <- .EL[[key]]
  if (is.null(tk) || length(unique(tk)) < .N_GRP) return(NULL)
  tk <- sort(unique(tk))
  F <- .features(j, tk)
  M <- apply(F, 2L, .rank11)
  if (is.null(dim(M))) M <- matrix(M, nrow = length(tk))
  dimnames(M) <- list(tk, .FEATS)
  D <- .sector_dummies(unname(.SECALL[[key]][tk]))
  X <- cbind(M, D)
  attr(X, "na_frac") <- colMeans(!is.finite(F))
  X
}

# 표적 — 그 달 횡단면에서 1%/99% winsorize(quantile type 7) 후 (r − mean)/sd (§5.4)                ★changed(7)
.std_target <- function(r) {
  q <- quantile(r, .WINSOR, names = FALSE, type = 7L)
  w <- pmin(pmax(r, q[1]), q[2])
  s <- sd(w); m0 <- mean(w)
  if (!is.finite(s) || s <= 0) return(NULL)
  (w - m0) / s
}

# =============================================================================
# 5. 신경망 — 32-16-8 · Linear→BN→ReLU · 선형 출력 · MSE + L1(커널) · ADAM   (순수 R · 파라미터 = 평탄 벡터)
# =============================================================================
.nn_shape <- function(m) {
  dims <- c(m, .NN_HIDDEN, 1L)
  sh <- list(); off <- 0L
  add <- function(name, nr, nc) {
    sh[[name]] <<- list(nr = nr, nc = nc, idx = off + seq_len(nr * nc))
    off <<- off + nr * nc
  }
  for (l in 1:4) add(paste0("W", l), dims[l], dims[l + 1L])
  for (l in 1:3) { add(paste0("g", l), dims[l + 1L], 1L); add(paste0("b", l), dims[l + 1L], 1L) }
  add("bo", 1L, 1L)
  attr(sh, "n") <- off
  sh
}
# 초기화 — Glorot uniform(Keras Dense 기본) · BN γ=1 β=0 · 출력 편향 0 · 은닉층 Dense 편향은 BN β 가 흡수(생략)  ★changed(11)(12)
.nn_new <- function(sh, seed) {
  set.seed(seed)
  th <- numeric(attr(sh, "n"))
  for (l in 1:4) {
    s <- sh[[paste0("W", l)]]; lim <- sqrt(6 / (s$nr + s$nc))
    th[s$idx] <- runif(s$nr * s$nc, -lim, lim)
  }
  for (l in 1:3) th[sh[[paste0("g", l)]]$idx] <- 1
  list(theta = th,
       rm = lapply(.NN_HIDDEN, function(k) numeric(k)),
       rv = lapply(.NN_HIDDEN, function(k) rep(1, k)),
       tau_sum = 0, tau_n = 0L)
}
.nn_fwd <- function(net, sh, X, train) {
  th <- net$theta; A <- X; cache <- vector("list", 3L)
  for (l in 1:3) {
    sW <- sh[[paste0("W", l)]]
    W <- matrix(th[sW$idx], sW$nr, sW$nc)
    g <- th[sh[[paste0("g", l)]]$idx]; b <- th[sh[[paste0("b", l)]]$idx]
    Z <- A %*% W
    if (train) {
      mu <- colMeans(Z); Zc <- sweep(Z, 2L, mu, "-"); va <- colMeans(Zc * Zc)
      net$rm[[l]] <- .BN_MOM * net$rm[[l]] + (1 - .BN_MOM) * mu
      net$rv[[l]] <- .BN_MOM * net$rv[[l]] + (1 - .BN_MOM) * va
    } else {
      Zc <- sweep(Z, 2L, net$rm[[l]], "-"); va <- net$rv[[l]]
    }
    istd <- 1 / sqrt(va + .BN_EPS)
    Zh <- sweep(Zc, 2L, istd, "*")
    Y  <- sweep(sweep(Zh, 2L, g, "*"), 2L, b, "+")
    mask <- Y > 0
    cache[[l]] <- list(A_in = A, Zh = Zh, istd = istd, mask = mask)
    A <- Y * mask
  }
  W4 <- matrix(th[sh$W4$idx], sh$W4$nr, sh$W4$nc)
  out <- as.vector(A %*% W4) + th[sh$bo$idx]
  list(out = out, A3 = A, cache = cache, net = net)
}
# 역전파 — 손실 = mean((ŷ−y)²) + l1·Σ|W| (커널 4개 · 편향/BN 제외 — Keras kernel_regularizer 관용)  ★changed(10)
.nn_bwd <- function(net, sh, fw, y, l1) {
  th <- net$theta; n <- length(y); G <- numeric(length(th))
  dout <- 2 * (fw$out - y) / n
  W4 <- matrix(th[sh$W4$idx], sh$W4$nr, sh$W4$nc)
  G[sh$W4$idx] <- as.vector(crossprod(fw$A3, dout)) + l1 * sign(th[sh$W4$idx])
  G[sh$bo$idx] <- sum(dout)
  dA <- tcrossprod(matrix(dout, ncol = 1L), W4)
  for (l in 3:1) {
    cc <- fw$cache[[l]]
    sW <- sh[[paste0("W", l)]]; sg <- sh[[paste0("g", l)]]; sb <- sh[[paste0("b", l)]]
    g <- th[sg$idx]
    dY <- dA * cc$mask
    G[sg$idx] <- colSums(dY * cc$Zh)
    G[sb$idx] <- colSums(dY)
    dZh <- sweep(dY, 2L, g, "*")
    s1 <- colSums(dZh); s2 <- colSums(dZh * cc$Zh)
    dZ <- n * dZh
    dZ <- sweep(dZ, 2L, s1, "-")
    dZ <- dZ - sweep(cc$Zh, 2L, s2, "*")
    dZ <- sweep(dZ, 2L, cc$istd / n, "*")
    G[sW$idx] <- as.vector(crossprod(cc$A_in, dZ)) + l1 * sign(th[sW$idx])
    if (l > 1L) {
      W <- matrix(th[sW$idx], sW$nr, sW$nc)
      dA <- tcrossprod(dZ, W)
    }
  }
  G
}
.adam_new <- function(p) list(m = numeric(p), v = numeric(p), t = 0L)
# 1 스텝 = 미니배치 1개(n ≤ 1,000 이면 전량) 의 ADAM 갱신 (Algorithm 2 의 k 한 번 · Algorithm 1 의 i 한 번)
.train_step <- function(net, sh, X, y, hp, S) {
  n <- nrow(X)
  if (n > .BATCH) {
    ii <- sample.int(n, .BATCH)
    Xb <- X[ii, , drop = FALSE]; yb <- y[ii]
  } else { Xb <- X; yb <- y }
  fw <- .nn_fwd(net, sh, Xb, TRUE)
  net <- fw$net
  G <- .nn_bwd(net, sh, fw, yb, hp$l1)
  S$t <- S$t + 1L
  S$m <- .ADAM_B1 * S$m + (1 - .ADAM_B1) * G
  S$v <- .ADAM_B2 * S$v + (1 - .ADAM_B2) * G * G
  mh <- S$m / (1 - .ADAM_B1^S$t)
  vh <- S$v / (1 - .ADAM_B2^S$t)
  net$theta <- net$theta - hp$lr * mh / (sqrt(vh) + .ADAM_EPS)
  list(net = net, S = S)
}
.nn_pred <- function(net, sh, X) .nn_fwd(net, sh, X, FALSE)$out
.nn_mse  <- function(net, sh, X, y) { o <- .nn_pred(net, sh, X); mean((o - y)^2) }

# Algorithm 2 — EarlyStopping(θ, X_train, r_train, X_test, r_test): 최소 J(test) 의 (τ, θ) 반환
#   ADAM 상태는 호출마다 새로 시작(논문 미명시 · changed(10)). J(test) = 순수 MSE(정규화항 제외 — 알고리즘 축자).
.early_stop <- function(net, sh, Xtr, ytr, Xte, yte, hp) {
  J_min <- .nn_mse(net, sh, Xte, yte)
  if (!is.finite(J_min)) J_min <- Inf                             # ★changed(9) 출발점 손실 비유한 = 첫 유한 스텝을 최소로
  net_min <- net; k_min <- 0L; q <- 0L; k <- 0L
  S <- .adam_new(length(net$theta))
  while (k < .ES_MAX) {
    k <- k + 1L
    st <- .train_step(net, sh, Xtr, ytr, hp, S); net <- st$net; S <- st$S
    Jp <- .nn_mse(net, sh, Xte, yte)
    if (!is.finite(Jp)) break                                   # ★changed(9) 발산 가드(비유한 손실 = 개선 없음으로 종료)
    gain <- J_min - Jp
    if (Jp < J_min) { J_min <- Jp; net_min <- net; k_min <- k }
    if (gain >= .ES_TOL) q <- 0L else { q <- q + 1L; if (q >= .ES_PATIENCE) break }
  }
  list(tau = k_min, net = net_min, J = J_min, steps = k)
}
# Algorithm 1 line 5~9 — θ*_{t−1} 에서 J_{t−1} 로 ⌊τ̄+0.5⌋ 스텝
.train_k <- function(net, sh, X, y, hp, k) {
  S <- .adam_new(length(net$theta)); i <- 0L
  while (i < k) {
    i <- i + 1L
    st <- .train_step(net, sh, X, y, hp, S)
    if (!all(is.finite(st$net$theta))) break                       # ★changed(9) 발산 가드 — 직전 유한 상태 유지
    net <- st$net; S <- st$S
  }
  net
}

# 기울기 검산(양성 대조) — 해석적 역전파 vs 중심차분. 실패 = 구현 결함 → 중단(조용한 F 방지)   ★changed(12)
.grad_check <- function() {
  set.seed(.SEED_GCHK)
  m <- 7L; n <- 9L; l1 <- 1e-3
  sh <- .nn_shape(m); net <- .nn_new(sh, 11L)
  X <- matrix(rnorm(n * m), n, m); y <- rnorm(n)
  fw <- .nn_fwd(net, sh, X, TRUE)
  G  <- .nn_bwd(net, sh, fw, y, l1)
  lossf <- function(th) {
    nn <- net; nn$theta <- th
    f <- .nn_fwd(nn, sh, X, TRUE)
    pen <- 0
    for (l in 1:4) pen <- pen + sum(abs(th[sh[[paste0("W", l)]]$idx]))
    mean((f$out - y)^2) + l1 * pen
  }
  h <- 1e-5; th0 <- net$theta; num <- numeric(length(th0))
  for (i in seq_along(th0)) {
    tp <- th0; tp[i] <- tp[i] + h
    tm <- th0; tm[i] <- tm[i] - h
    num[i] <- (lossf(tp) - lossf(tm)) / (2 * h)
  }
  keep <- rep(TRUE, length(th0))
  for (l in 1:4) { ix <- sh[[paste0("W", l)]]$idx; keep[ix] <- abs(th0[ix]) > 1e-3 }
  rel <- abs(G - num) / pmax(abs(G) + abs(num), 1e-6)
  rel <- rel[keep]
  q99 <- as.numeric(quantile(rel, 0.99, names = FALSE))
  if (!is.finite(q99) || q99 > .GCHK_TOL)
    stop(sprintf("%s 기울기 검산 실패 — 상대오차 99백분위 %.3g > %.0e (역전파 구현 결함) — 중단", .TAG, q99, .GCHK_TOL))
  cat(sprintf("%s 기울기 검산 통과 — 파라미터 %d개 · 상대오차 중앙 %.2e · 99백분위 %.2e · 최대 %.2e\n",
              .TAG, length(th0), median(rel), q99, max(rel)))
}
.grad_check()

# 특성 양성 대조 — 합성 패널로 .rank11 / .beta_idio / .ols_r2 를 검산(구현 결함 = 중단)               ★changed(12)
local({
  r <- .rank11(c(3, NA, 1, 2, 2))
  if (!isTRUE(all.equal(r, c(1, 0, -1, 0, 0)))) stop(sprintf("%s 순위 변환 검산 실패", .TAG))
  set.seed(.SEED_GCHK)
  x <- rnorm(200); e <- rnorm(200)
  Y <- cbind(0.5 + 1.3 * x + 0.2 * e, -0.7 * x + 0.5 * e, NA_real_)
  Y[1:10, 1L] <- NA_real_
  bi <- .beta_idio(Y, x)
  ok1 <- is.finite(bi$beta[1L]) && abs(bi$beta[1L] - 1.3) < 0.15 && abs(bi$idiovol[1L] - 0.2) < 0.06
  ok2 <- is.finite(bi$beta[2L]) && abs(bi$beta[2L] + 0.7) < 0.25 && abs(bi$idiovol[2L] - 0.5) < 0.12
  ok3 <- is.na(bi$beta[3L]) && is.na(bi$idiovol[3L])
  if (!(ok1 && ok2 && ok3)) stop(sprintf("%s 주간 회귀 검산 실패 (beta %.3f/%.3f · idio %.3f/%.3f)", .TAG,
                                         bi$beta[1L], bi$beta[2L], bi$idiovol[1L], bi$idiovol[2L]))
  y1 <- Y[11:200, 1L]; x1 <- x[11:200]
  fit <- lm(y1 ~ x1)
  lmb <- unname(coef(fit))
  if (abs(lmb[2L] - bi$beta[1L]) > 1e-8) stop(sprintf("%s beta 가 lm() 과 불일치", .TAG))
  if (abs(summary(fit)$sigma - bi$idiovol[1L]) > 1e-8) stop(sprintf("%s idiovol 이 lm() 잔차표준오차와 불일치", .TAG))
  r2 <- .ols_r2(y1, cbind(1, x1))
  if (abs(r2 - summary(fit)$r.squared) > 1e-8) stop(sprintf("%s R² 가 lm() 과 불일치", .TAG))
  cat(sprintf("%s 특성 검산 통과 — 순위 · beta(%.3f≈1.3) · idiovol(%.3f≈0.2) · R²(%.4f) = lm() 정확 일치\n",
              .TAG, bi$beta[1L], bi$idiovol[1L], r2))
})

# =============================================================================
# 6. 워밍업 사전 스캔 — 특성 정의역(월간 패널 36개월 이후) · 적격 종목 ≥ 10 인 달 · 검증 월 지정 (OOS 시작 전 데이터만)
# =============================================================================
.j_first <- which(match(.me$MI, .MIs) > 36L)[1]                              # ★changed(13) mom36m 정의역(36개월 선행)
if (is.na(.j_first)) stop(sprintf("%s 월간 패널이 37개월 미만 — 특성 정의역 없음", .TAG))
.valid_pre <- logical(nrow(.me))
.n_valid <- 0L; .j_oos <- NA_integer_
for (j in .j_first:nrow(.me)) {
  d <- .me$MEnd[j]
  if (d >= .OOS_START && .n_valid >= .MIN_WARM) { .j_oos <- j; break }
  tk <- .EL[[as.character(.me$MI[j])]]
  if (!is.null(tk) && length(unique(tk)) >= .N_GRP) { .valid_pre[j] <- TRUE; .n_valid <- .n_valid + 1L }
}
if (is.na(.j_oos)) stop(sprintf("%s 워밍업 유효 월 %d개(하한 %d) 뒤에 OOS 월이 남지 않는다 — 멤버십 플래그 범위 확인", .TAG, .n_valid, .MIN_WARM))
.J_WARM <- which(.valid_pre)
if (.me$MEnd[.j_oos] > .OOS_START + 31)
  cat(sprintf("%s ★워밍업 유효 월이 %s 이전에 %d개뿐 — OOS 시작을 %s 로 민다(changed(13))\n",
              .TAG, as.character(.OOS_START), sum(.me$MEnd[.J_WARM] < .OOS_START), as.character(.me$MEnd[.j_oos])))
.n_train_w <- floor(.TRAIN_FRAC * length(.J_WARM))
.is_val <- logical(nrow(.me)); .is_val[.J_WARM[seq_along(.J_WARM) > .n_train_w]] <- TRUE
cat(sprintf("%s 워밍업 %d개월 유효 (%s ~ %s · 학습 %d / 검증 %d) · OOS 시작 %s · 특성 = %d + 업종 슬롯 %d\n",
            .TAG, length(.J_WARM), as.character(.me$MEnd[.J_WARM[1]]), as.character(.me$MEnd[.J_WARM[length(.J_WARM)]]),
            .n_train_w, length(.J_WARM) - .n_train_w, as.character(.me$MEnd[.j_oos]), length(.FEATS), .SEC_CAP))

# =============================================================================
# 7. 네트워크 — 하이퍼파라미터 격자 6 × 앙상블 10 = 60 (워밍업) → 선택 후 10 (OOS)
# =============================================================================
.SH <- .nn_shape(length(.FEATS) + .SEC_CAP)
.HPG <- CJ(lr = .LR_SET, l1 = .L1_SET)
.NCFG <- nrow(.HPG)
.nets <- vector("list", .NCFG * .N_ENSEMBLE)
.cfg_of <- integer(length(.nets))
for (cf in seq_len(.NCFG)) for (s in seq_len(.N_ENSEMBLE)) {
  i <- (cf - 1L) * .N_ENSEMBLE + s
  nn <- .nn_new(.SH, .SEED_BASE + s)
  nn$hp <- list(lr = .HPG$lr[cf], l1 = .HPG$l1[cf])
  .nets[[i]] <- nn; .cfg_of[i] <- cf
}
cat(sprintf("%s 네트워크 %d개 초기화 (격자 %d × 앙상블 %d · 파라미터 %d개/망 · 입력 %d)\n",
            .TAG, length(.nets), .NCFG, .N_ENSEMBLE, attr(.SH, "n"), length(.FEATS) + .SEC_CAP))

# =============================================================================
# 8. 월별 온라인 루프 (Algorithm 1) — 워밍업(선택) → OOS(발행)
# =============================================================================
.Xs <- vector("list", nrow(.me)); .Ys <- vector("list", nrow(.me))
.val_mse <- vector("list", .NCFG); for (cf in seq_len(.NCFG)) .val_mse[[cf]] <- numeric(0)
.pst <- vector("list", .NCFG); .pst_j <- NA_integer_
.rows_f <- list(); .rows_p <- list(); .diag <- list()
.n_gap <- 0L; .n_nox <- 0L; .n_nopf <- 0L; .n_div <- 0L
.na_acc <- numeric(length(.FEATS)); .na_n <- 0L
.sel_c <- NA_integer_
.t_loop <- Sys.time()
for (j in .j_first:nrow(.me)) {
  d  <- .me$MEnd[j]; mi <- .me$MI[j]; key <- as.character(mi)
  ir <- match(mi, .MIs)
  in_oos <- j >= .j_oos

  # (1) X_j — 시그널일 d 의 특성(그 달 적격 종목 · 원값 → 유니버스 안 순위 [−1,1] · 업종 더미)
  X_j <- .build_X(j)
  .Xs[j] <- list(X_j)
  if (!is.null(X_j) && in_oos) { .na_acc <- .na_acc + attr(X_j, "na_frac"); .na_n <- .na_n + 1L }

  # (2) r_{j−1} 실현 — d_{j−1} → d_j 월수익 (d 에 확정) → winsorize → 표준화. 그 이후 접근 0건.
  if (j > 1L && !is.null(.Xs[[j - 1L]]) && ir > 1L) {
    tk1 <- rownames(.Xs[[j - 1L]])
    r <- .P[ir, tk1] / .P[ir - 1L, tk1] - 1
    ok <- is.finite(r)
    y <- NULL
    if (sum(ok) >= .N_GRP) { y <- .std_target(r[ok]); if (!is.null(y)) names(y) <- tk1[ok] }
    .Ys[j - 1L] <- list(y)
  }

  # (3) 워밍업 검증 MSE — 직전 달 예측 vs 지금 실현된 표적 (선택 통계 · 성과 아님)
  if (!is.na(.pst_j) && .pst_j == j - 1L && .is_val[j - 1L] && !is.null(.Ys[[j - 1L]])) {
    y <- .Ys[[j - 1L]]
    for (cf in seq_len(.NCFG)) {
      pc <- .pst[[cf]]
      if (!is.null(pc)) {
        cm <- intersect(names(pc), names(y))
        if (length(cm) >= .N_GRP) .val_mse[[cf]] <- c(.val_mse[[cf]], mean((pc[cm] - y[cm])^2))
      }
    }
  }

  # (4) OOS 첫 달 — 하이퍼파라미터 1회 선택(워밍업 검증 월 평균 MSE 최소 · 동률 = 격자 순) → 그 격자의 앙상블 10 만 존속
  if (in_oos && is.na(.sel_c)) {
    mv <- vapply(.val_mse, function(v) if (length(v)) mean(v) else NA_real_, numeric(1))
    if (all(is.na(mv))) stop(sprintf("%s 워밍업 검증 MSE 가 한 격자도 산출되지 않았다 — 선택 불가", .TAG))
    .sel_c <- which.min(mv)
    for (cf in seq_len(.NCFG))
      cat(sprintf("%s   격자 %d: η %.3f · L1 %.0e · 검증 월 %d · 평균 MSE %s%s\n", .TAG, cf, .HPG$lr[cf], .HPG$l1[cf],
                  length(.val_mse[[cf]]), if (is.na(mv[cf])) "NA" else sprintf("%.5f", mv[cf]),
                  if (cf == .sel_c) "  ← 선택" else ""))
    keep <- which(.cfg_of == .sel_c)
    .nets <- .nets[keep]; .cfg_of <- .cfg_of[keep]
    .HP <- list(lr = .HPG$lr[.sel_c], l1 = .HPG$l1[.sel_c])
    cat(sprintf("%s 하이퍼파라미터 선택 완료 (η %.3f · L1 %.0e) · 워밍업 소요 %.1f분 · 이후 앙상블 %d 망\n",
                .TAG, .HP$lr, .HP$l1, as.numeric(difftime(Sys.time(), .t_loop, units = "mins")), length(.nets)))
  }

  # (5) Algorithm 1 — 학습 J_{j−2}, 검증 J_{j−1} 로 조기중단 → τ̄ 갱신 → J_{j−1} 로 ⌊τ̄+0.5⌋ 스텝 → X_j 예측
  have_tr <- j > 2L && !is.null(.Xs[[j - 2L]]) && !is.null(.Ys[[j - 2L]])
  have_va <- j > 1L && !is.null(.Xs[[j - 1L]]) && !is.null(.Ys[[j - 1L]])
  can_train <- have_tr && have_va
  if (can_train) {
    ytr <- .Ys[[j - 2L]]; Xtr <- .Xs[[j - 2L]][names(ytr), , drop = FALSE]
    yva <- .Ys[[j - 1L]]; Xva <- .Xs[[j - 1L]][names(yva), , drop = FALSE]
  }
  preds <- vector("list", length(.nets)); es_steps <- integer(length(.nets)); taus <- integer(length(.nets))
  for (i in seq_along(.nets)) {
    net <- .nets[[i]]
    net_p <- net
    if (can_train) {
      es <- .early_stop(net, .SH, Xtr, ytr, Xva, yva, net$hp)
      net <- es$net
      net$tau_sum <- net$tau_sum + es$tau; net$tau_n <- net$tau_n + 1L
      k <- as.integer(floor(net$tau_sum / net$tau_n + 0.5))
      net_p <- .train_k(net, .SH, Xva, yva, net$hp, k)
      es_steps[i] <- es$steps; taus[i] <- es$tau
      .nets[[i]] <- net
    }
    if (!is.null(X_j)) preds[[i]] <- .nn_pred(net_p, .SH, X_j)
  }
  if (in_oos && !can_train) .n_gap <- .n_gap + 1L
  if (!in_oos && (j - .j_first + 1L) %% 12L == 0L)
    cat(sprintf("%s   워밍업 %s · N %s · 경과 %.1f분\n", .TAG, as.character(d),
                if (is.null(X_j)) "없음" else as.character(nrow(X_j)),
                as.numeric(difftime(Sys.time(), .t_loop, units = "mins"))))
  if (is.null(X_j)) { if (in_oos) .n_nox <- .n_nox + 1L; .pst_j <- NA_integer_; next }

  # (6) 앙상블 평균(격자별 · 비유한 예측을 낸 망은 그 달 평균에서 제외 — 건수 기록) — 워밍업이면 다음 달 검증용 보관, OOS 면 발행
  cfgs <- unique(.cfg_of)
  ens <- vector("list", .NCFG)
  for (cf in cfgs) {
    ii <- which(.cfg_of == cf)
    okp <- vapply(preds[ii], function(p) all(is.finite(p)), logical(1))
    .n_div <- .n_div + sum(!okp)                                    # ★changed(9)
    if (!any(okp)) next
    ens[[cf]] <- Reduce(`+`, preds[ii][okp]) / sum(okp)
    names(ens[[cf]]) <- rownames(X_j)
  }
  if (!in_oos) { .pst <- ens; .pst_j <- j; next }

  sc <- ens[[.sel_c]]
  if (is.null(sc)) { .n_nox <- .n_nox + 1L; next }
  .rows_f[[length(.rows_f) + 1L]] <- data.table(Date = d, Ticker = names(sc), Score = unname(sc))
  N <- length(sc)
  o <- order(sc, names(sc))                                        # 오름차순 · 동률 = 종목코드(결정론)  ★changed(8)
  grp <- integer(N); grp[o] <- as.integer(ceiling(seq_len(N) * .N_GRP / N))   # 그룹 크기 차 ≤ 1
  hi <- names(sc)[grp == .N_GRP]; lo <- names(sc)[grp == 1L]
  nL <- length(hi); nS <- length(lo)
  if (nL < 1L || nS < 1L) { .n_nopf <- .n_nopf + 1L } else {
    .rows_p[[length(.rows_p) + 1L]] <- data.table(
      Date = d, Ticker = c(hi, lo),
      Weight = c(rep(1 / nL, nL), rep(-1 / nS, nS)),               # 데실 내 EW · 롱 Σ=+1 / 숏 Σ=−1  ★changed(8)
      Leg = rep(c("long", "short"), c(nL, nS)))
  }
  .diag[[length(.diag) + 1L]] <- data.table(
    Date = d, N = N, nL = nL, nS = nS, trained = can_train,
    es_mean = if (can_train) mean(es_steps) else NA_real_, tau_mean = if (can_train) mean(taus) else NA_real_,
    tau_bar = mean(vapply(.nets, function(z) if (z$tau_n > 0L) z$tau_sum / z$tau_n else NA_real_, numeric(1))))
  if (length(.rows_f) %% 12L == 0L) {
    dg <- rbindlist(.diag, use.names = TRUE)
    cat(sprintf("%s   %s · N %d · 롱 %d / 숏 %d · ES 스텝 평균 %.1f · τ* 평균 %.1f · τ̄ %.1f · 경과 %.1f분\n",
                .TAG, as.character(d), N, nL, nS,
                mean(dg$es_mean, na.rm = TRUE), mean(dg$tau_mean, na.rm = TRUE), dg$tau_bar[nrow(dg)],
                as.numeric(difftime(Sys.time(), .t_loop, units = "mins"))))
  }
  # 메모리 — 세 달 전 행렬은 더 쓰지 않는다
  if (j > 3L) { .Xs[j - 3L] <- list(NULL); .Ys[j - 3L] <- list(NULL) }
}

# =============================================================================
# 9. 조립 · 검산 · 요약 (구성 요약 — 성과 수치 선언 아님. 등급은 계약이 낸다)
# =============================================================================
if (length(.rows_f) == 0L)
  stop(sprintf("%s 발행 행 0 — OOS 월 중 특성 없는 달 %d · 학습 불가(갭) 달 %d", .TAG, .n_nox, .n_gap))
FACTORS <- rbindlist(.rows_f, use.names = TRUE)
setorder(FACTORS, Date, Ticker)
if (length(.rows_p) == 0L) stop(sprintf("%s PORTFOLIO 행 0", .TAG))
PORTFOLIO <- rbindlist(.rows_p, use.names = TRUE)
setorder(PORTFOLIO, Date, Leg, Ticker)

.chk <- PORTFOLIO[, .(gl = sum(Weight[Weight > 0]), gs = -sum(Weight[Weight < 0])), by = Date]
.bad <- .chk[abs(gl - 1) > 1e-9 | abs(gs - 1) > 1e-9]
if (nrow(.bad) > 0L)
  stop(sprintf("%s 다리 총노출 검산 실패 %d건 (예: %s gL %.6f / gS %.6f)",
               .TAG, nrow(.bad), as.character(.bad$Date[1L]), .bad$gl[1L], .bad$gs[1L]))
if (anyDuplicated(PORTFOLIO, by = c("Date", "Ticker")) > 0L) stop(sprintf("%s PORTFOLIO (Date,Ticker) 중복", .TAG))
if (anyDuplicated(FACTORS, by = c("Date", "Ticker")) > 0L)   stop(sprintf("%s FACTORS (Date,Ticker) 중복", .TAG))
if (!all(is.finite(FACTORS$Score))) stop(sprintf("%s FACTORS Score 비유한값 %d건", .TAG, sum(!is.finite(FACTORS$Score))))

.DG <- rbindlist(.diag, use.names = TRUE)
.mins <- as.numeric(difftime(Sys.time(), .t0, units = "mins"))
.na_txt <- if (.na_n > 0L) paste(sprintf("%s %.0f%%", .FEATS, 100 * .na_acc / .na_n), collapse = " · ") else "n/a"
cat(sprintf("%s adapted(기전 = 논문 그대로: OES Algorithm 1·2 · 32-16-8 ReLU · BN · ADAM · L1 · 앙상블 10 · 격자 6 워밍업 1회 선택(η %.3f · L1 %.0e) · 특성 = GKX 가격·거래량·시총 19종 원값 → 유니버스 안 순위[−1,1] + 업종 슬롯 %d(배정 %d · 초과 %d) · 표적 = 익월 수익 winsorize 1/99%% → 횡단면 표준화 · 십분위 롱숏 EW): 유니버스 K200∪KQ150 · 유동성·가격·기타 스크린 없음 · 팩터 DB 미사용\n",
            .TAG, .HP$lr, .HP$l1, .SEC_CAP, length(.SEC$map), length(.SEC$overflow)))
cat(sprintf("  발행 %d개월 (%s ~ %s) · 학습 수행 달 %d · 갭(학습 불가) 달 %d · 예측 없는 달 %d · 데실 미성립 달 %d · 발산 망-월 %d · 횡단면 N %d~%d(중앙 %d)\n",
            nrow(.DG), as.character(min(.DG$Date)), as.character(max(.DG$Date)), sum(.DG$trained), .n_gap, .n_nox, .n_nopf, .n_div,
            min(.DG$N), max(.DG$N), as.integer(median(.DG$N))))
cat(sprintf("  OOS 특성 결측률(순위 전 · 결측 = 중앙값 0 삽입): %s\n", .na_txt))
cat(sprintf("  롱 %d~%d / 숏 %d~%d종 (합 최대 %d — 고정 축 25 초과는 논문 데실 정의상 · engine_direct 라 러너가 자르지 않는다) · ES 스텝 평균 %.1f · τ* 평균 %.1f · 최종 τ̄ %.1f (학습 통계 — 성과 아님)\n",
            min(.DG$nL), max(.DG$nL), min(.DG$nS), max(.DG$nS), max(.DG$nL + .DG$nS),
            mean(.DG$es_mean, na.rm = TRUE), mean(.DG$tau_mean, na.rm = TRUE), .DG$tau_bar[nrow(.DG)]))
cat(sprintf("  PORTFOLIO %d행 · FACTORS %d행 · %.1f분 · 러너 사양 = FIDELITY 파일 portfolio_spec(engine_direct) · commission_paper = null(논문 비용 무명시 → gross 병기)\n",
            nrow(PORTFOLIO), nrow(FACTORS), .mins))

PORTFOLIO <- PORTFOLIO[, .(Date, Ticker, Weight, Leg)]
FACTORS   <- FACTORS[, .(Date, Ticker, Score)]
