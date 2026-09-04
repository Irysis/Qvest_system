# =============================================================================
# engine.R — RP_AUTO_2302_10175
# "Spatio-Temporal Momentum: Jointly Learning Time-Series and Cross-Sectional
#  Strategies" — Tan, Roberts, Zohren (arXiv:2302.10175 ·
#  The Journal of Financial Data Science, Summer 2023, DOI 10.3905/jfds.2023.1.130)
#  https://arxiv.org/abs/2302.10175
#  ★원문 전문 대조 완료(2026-09-04) — https://arxiv.org/html/2302.10175v1
#
# ★fidelity = ADAPTED. 정본 = FIDELITY.json (이 주석은 사본이지 통로가 아니다)
#
# ===== 판정 순서 1 — 충실구현이 왜 완전히는 안 되는가 =====
# 이 논문은 **횡단면 종목선택 논문이 맞다**. 산출도 포트폴리오다. 신호·비중·목적함수는
# 전부 원문 수식이 있고 데이터도 다 있다(일별 수익·종가·거래대금). ABORT 사유 없음.
# 그런데 두 지점이 우리 계약과 충돌한다 — 둘 다 논문 훼손이 아니라 계약 제약이다.
#
#  (X1) **리밸 주기**. 논문은 daily rebalancing 이다. 그런데 측정 계약의 집행일 규약
#       `get_execution_date()`(02_Infrastructure/backtest_harness.R:316)는 시그널일 →
#       **익월 첫 거래일**로 하드와이어돼 있다. 일별 비중을 내보내면 같은 달의 시그널일이
#       전부 같은 exec_date 로 접히고 hold_pool 이 비어 `next` 로 조용히 버려진다
#       (replication_harness.R:84~89) — 결과적으로 **월말 1건만 살아남아 월간으로 측정**된다.
#       즉 "일별로 냈다"는 기록만 남고 실제 측정은 월간인 침묵 실패가 된다.
#       → 지어내지 않고 **집행을 월간으로 선언**한다. 학습은 논문 그대로 일별이다.
#  (X2) **자산 집합의 고정성**. SLP 의 W ∈ R^{m×N}(m = N·τ·d)는 열 j 가 "자산 j"에
#       묶인 **identity-indexed** 행렬이다 — 논문은 46종 고정 패널(1990-2022)을 쓴다.
#       우리 유니버스 K200∪KQ150 은 PIT 시변이라 그대로는 사상되지 않는다.
#       → 패널을 **확장창 반복(iteration)마다 PIT 재선정**한다(선정 시점 이전 정보만).
#          논문이 재학습하는 바로 그 지점에서 재선정하므로 구조가 어긋나지 않는다.
#
# ===== 무엇을 남기는가 (kept — 논문의 기전, 전부 원문 수식) =====
#  (K1) **시공간 결합 = 한 장의 W 가 전 종목의 모멘텀 피처를 받아 전 종목의 포지션을
#       동시에 낸다.** 원문: "𝐗t = g(𝐖⊤𝐮t + 𝐛)", 𝐮t ∈ ℝ^m (m = Nt·τ·d), 𝐖 ∈ ℝ^{m×Nt},
#       g = tanh. 자산 i 의 포지션이 자산 j 의 모멘텀 피처에 걸리는 것이 이 논문의 전부다
#       (TSMOM = 대각, CSMOM = 순위, 이 모델 = 전체 행렬). 여기를 잘라내면 논문이 아니다.
#  (K2) **피처 d = 14** — 원문 F.1/F.2 그대로.
#       F.1 변동성 정규화 수익 r_{t−k,t}/(σ_t√k), k ∈ {1,20,63,126,252}  → 5개
#       F.2 MACD(i,t,S,L) = m(i,t,S) − m(i,t,L), m = 반감기 HL=log(0.5)/log(1−1/j) EWMA,
#           MACD_norm = MACD/std(p_{t−63:t}),  Y = MACD_norm/std(MACD_norm_{t−252:t}),
#           S ∈ {8,16,32} × L ∈ {24,48,96} 전 조합 → 9개  (5 + 9 = 14 ✓ 원문 d=14)
#       ★HL 정의를 풀면 EWMA 감쇠계수가 정확히 (1−1/j) 다 — 0.5^(1/HL) = 1−1/j.
#         그래서 α = 1/j 인 단순 EWMA 이고, 자의적 수치가 들어갈 자리가 없다.
#  (K2b) **winsorize** — 원문 전처리 명시: "we winsorize all data to limit values to be
#       within 5 times its 252-day exponentially weighted moving standard deviation from
#       its exponentially weighted moving average". 5 도 252 도 원문값이다.
#       ★이건 장식이 아니다: 입력이 3220차원(τ·N·d)이라 몇 개만 O(100)이어도 tanh 가
#         포화하고 (1−X²)≈0 으로 기울기가 죽는다. 빼면 학습이 조용히 멈춘다.
#  (K3) **목적함수 = 자산별 Sharpe 손실의 등가중 합**. 원문:
#       ℒ_sharpe^(i)(θ) = −√252·ΣR_i(t) / sqrt(ΣR_i(t)² − (ΣR_i(t))²),
#       R_i(t) = X_t^(i)·(σ_tgt/σ_t^(i))·r_{t,t+1}^(i),  ℒ = Σ_i λ_i ℒ^(i), λ_i = 1/N.
#  (K4) **LASTR = L1 수축 + 회전율 정규화**(원문이 최적이라고 보고한 구성).
#       ℒ(θ) = ℒ_sharpe(θ) + α·Σ|w_ij|,
#       회전율은 학습 수익에 직접 차감: R̃ = X·(σ_tgt/σ)·r − c·TO,
#       TO_t^(i) = σ_tgt·|X_t^(i)/σ_t^(i) − X_{t*}^(i)/σ_{t*}^(i)| (t* = 미니배치 내 직전 표본
#       = "localized minibatch turnover regularization"). → 미니배치는 **연속 구간**이어야 한다.
#  (K5) **비중 = 논문 산식 그대로**. r_{t,t+1} = (1/N_t)Σ_i X_t^(i)·(σ_tgt/σ_t^(i))·r_{t,t+1}^(i)
#       ⇒ w_i = (1/N)·X_i·σ_tgt/σ_i. Σw=1 도 달러중립도 걸지 않는다(원문: 제약 없음).
#       그 위에 원문이 명시한 **포트폴리오 레벨 변동성 스케일링(연 15% 표적)**을 얹는다.
#  (K6) **확장창 재학습**. 원문: 첫 반복 = 앞 5년 학습/검증 → 다음 5년 OOS, 이후 5년씩
#       누적 추가. 학습/검증 분할 = 시간순 앞 90% / 뒤 10%.
#
# ===== 무엇을 바꿨는가 (changed — 전문·기계판독은 FIDELITY.json) =====
#  (C1) 유니버스: 미국 금융섹터 46종 → **K200∪KQ150**(고정 축). 패널 N=46 은 논문값 유지.
#       선정: 논문은 "random sample of 46" 인데 그건 그 표본 고유의 선택이라 복제 불가 —
#       확장창 반복마다 선정일 t−1 기준 **adv20 상위 46종**(멤버십·유동성 하한 통과 +
#       학습창 내 수익 관측 95% 이상)으로 결정론 선정한다. 미래 정보 0.
#  (C2) 집행 주기: daily → **monthly**(X1 — 계약 제약). **학습은 일별 그대로**이고,
#       월말 시그널일의 포지션을 그대로 다음 달 보유분으로 내보낸다.
#  (C3) 탐색 예산: 원문 랜덤서치 100회(minibatch·hidden·lr·α·dropout) → α 3점만
#       **첫 확장창 반복에서** 검증손실로 선정 후 고정. lr=1e-3 · minibatch=128 은 원문
#       탐색공간 안의 값으로 고정. dropout 은 SLP(은닉층 없음)에 정의되지 않아 미사용.
#       epochs 500/patience 25 → **50/8**. 전부 계산예산 사유이고 방법 변경이 아니다.
#  (C4) 학습 회전율 계수 c = **0.0015** — 원문에서 c 는 "거래비용" 그 자체이고(원문은
#       0~10bps 시나리오를 훑는다), 우리가 실제로 부과받는 등급 기준 비용이 15bps 다.
#       임의 튜닝값이 아니라 측정 계약이 정한 값을 그대로 넣은 것이다.
#
# ===== PIT (C1~C15) — 구조로 보장. detect_lookahead 통과를 근거로 삼지 않는다 =====
#  ▸ 구조 경계 ①(학습): 반복 b 의 모델은 `[.TRAIN_FROM, psel_b]` 행만 본다. psel_b =
#    OOS 블록 시작 **직전** 거래일. OOS 구간 행이 학습 인덱스에 들어가는 경로가 없다.
#  ▸ 구조 경계 ②(피처): 모든 창이 종점 t 의 **후향(align="right")** 이다. 미래 인덱싱·
#    음수 shift·전 표본 mean/sd/cov 가 코드에 0건이다(재귀 EWMA도 과거→미래 1방향).
#  ▸ 구조 경계 ③(표적): 학습 표적 r_{t,t+1} 은 **손실 안에서만** 쓰이고 피처에 절대
#    섞이지 않는다. 표본 t 의 입력은 FB[t], FB[t−1] … FB[t−4] 뿐이다.
#  C1  : 전 표본 통계 0건. 변동성 = 60일 EWM(재귀) · 가격 std = 63일 후향창 ·
#        MACD std = 252일 후향창. 패널 선정 통계도 선정일까지의 창 안에서만.
#  C2  : same-day 순환참조 없음. 시그널일 종가까지의 정보로 비중 확정 → 익월 첫 거래일 집행.
#  C3  : 같은 기간 집계→적용 없음. 포트폴리오 변동성 스케일러도 시그널일까지의 실현치만.
#  C4  : 재무 패널 미사용(일별 종가·수익·거래대금만). 재무 시차 이슈 자체가 없다.
#  C5  : 포트폴리오 변동성 스케일러 = 오버레이 성격 → 컷오프가 **홀딩월 시작 전**이다
#        (시그널일 = 그 달 마지막 거래일, 집행 = 익월 첫 거래일). 홀딩월 정보 0.
#  C6  : 패널·적격 판정 모두 그 시점 K200/KQ150 멤버십(PIT 시변). 최종 명부 주입 없음.
#        "학습창 관측 95%" 는 **과거** 완전성 요구이지 미래 생존 요구가 아니다.
#  C7  : shift(-N)·미래 인덱싱 0건. 유일한 shift 는 +k(과거 방향).
#  C9  : 변동성 스케일러가 참조하는 전략 수익은 시그널일까지 실현분뿐(동일시점 미사용).
#  C10 : 유동성 = 20일 평균 거래대금을 by-Ticker shift(1) 한 t−1 값 ≥ 2e8.
#  C11 : 매크로·외부 시계열 미사용.
#  C13 : Factor DB 미소비 → 부호 정렬 대상 없음. 부호는 학습된 W 가 낸다(수동 반전 0건).
#  C15 : Factor DB parquet 직접 load 0건.
#  ★rawdata 의 Market 열 미사용(KOSDAQ 0건 날조 기록) · Sector 열 미사용.
#
# ===== 산출 =====
#   PORTFOLIO(Date, Ticker, Weight, Leg) — 논문 비중 그대로(롱숏·레버리지 보존).
#   ★러너 호출: portfolio_spec = list(construction="engine_direct")
#     commission_paper = NULL (원문은 0~10bps 시나리오를 훑을 뿐 단일 명시값이 없다).
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

# 가중치 초기화·미니배치 순서에만 난수가 쓰인다. 재현성 고정.
set.seed(23021017L)

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(all(c("Date", "Ticker", "Close", "Vol", "Ret", "K200", "KQ150")
              %in% names(RAWDATA)))

.TAG <- "RP_AUTO_2302_10175"

# =============================================================================
# 0. 상수 — 논문에서 온 것 / 고정 축에서 온 것 / 계산예산에서 온 것
# =============================================================================
# ▸ 논문(원문 수식·명시값)
.TAU      <- 5L                          # SLP 시간 히스토리 τ = 5
.KWIN     <- c(1L, 20L, 63L, 126L, 252L) # F.1 수익 룩백 k
.MACD_S   <- c(8L, 16L, 32L)             # F.2 단기 시간척도 S
.MACD_L   <- c(24L, 48L, 96L)            # F.2 장기 시간척도 L
.DFEAT    <- length(.KWIN) + length(.MACD_S) * length(.MACD_L)   # = 14
.VOL_SPAN <- 60L                         # 60일 EWM 표준편차(사전 변동성)
.STD_P    <- 63L                         # std(p_{t−63:t})
.STD_Q    <- 252L                        # std(MACD_norm_{t−252:t})
.WIN_SPAN <- 252L                        # winsorize 기준 EWM span (원문 명시)
.WIN_K    <- 5                           # winsorize 폭 = 5 × EWM std (원문 명시)
.SIG_TGT  <- 0.15                        # σ_tgt = 연 15%
.NPANEL   <- 46L                         # 논문 주식 패널 크기
.VAL_FRAC <- 0.10                        # 학습/검증 = 앞 90% / 뒤 10%
.MB       <- 128L                        # 미니배치(원문 탐색집합 {32,64,128,256})
.BLOCK_Y  <- 5L                          # 확장창 반복 = 5년

# ▸ 고정 축(v10)
.LIQ      <- 2e8                         # adv20(t−1) 하한 (KRW)
.OOS_FROM <- as.Date("2005-01-01")       # 신호 산출 시작
.TRAIN_FROM <- as.Date("2000-01-01")     # 첫 반복 학습창 시작 → 정확히 5년(논문 첫 반복과 동형)
.PANEL_FROM <- as.Date("1997-07-01")     # 피처 워밍업 하한(≈620거래일 여유. 필요 315거래일)

# ▸ 계산예산(C3 — 방법이 아니라 예산에서 온 값. 성과를 보고 고르지 않았다)
.LR       <- 1e-3                        # Adam (원문 탐색구간 [1e−5, 1e0] 안)
.EPOCH    <- 50L                         # 원문 500
.PATIENCE <- 8L                          # 원문 25
.ALPHAS   <- c(1e-5, 1e-4, 1e-3)         # L1 α 후보(원문 탐색구간 [1e−5, 1e0] 안)
.COST_C   <- 0.0015                      # 학습 회전율 계수 = 등급 기준 비용 15bps

# ▸ 수치 가드(경제적 임계가 아니라 0나눗셈·발산 방지)
.SD_FLOOR <- 0.01                        # 연율 변동성 1% 미만 = 거래정지성 퇴화 → 포지션 0
.BIG      <- 1e6                         # |피처| 상한(넘으면 비유한 취급)
.ANN      <- sqrt(252)

.t0 <- Sys.time()

# =============================================================================
# 1. 일별 패널 · 거래일 캘린더 · 유동성(C10) · 멤버십(C6)
# =============================================================================
.rd <- RAWDATA[Date >= .PANEL_FROM, .(Date, Ticker, Close, Vol, Ret, K200, KQ150)]
.rd <- .rd[is.finite(Close) & Close > 0]
setorder(.rd, Ticker, Date)

# (Date,Ticker) 중복 방어 — 남으면 dcast 가 조용히 fun.aggregate=length 로 떨어져
#   '가격' 대신 '건수' 행렬을 만든다(에러 없는 신호 치환). 없으면 무연산.
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[%s] (Date,Ticker) 중복 %d행 — 첫 행만 남긴다\n", .TAG, .ndup))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}

# 지수 유니버스에 한 번이라도 들어간 적 있는 종목으로 축소(메모리) — 선정은 시점별로 다시 건다.
.rd <- .rd[Ticker %chin% unique(.rd[(K200 | KQ150), Ticker])]
.rd[, ADV20_L1 := shift(frollmean(Close * Vol, 20L, align = "right"), 1L), by = Ticker]  # C10 t−1
.rd[, Vol := NULL]

.DATES <- sort(unique(.rd$Date))
.DMAX  <- max(.DATES)
if (!any(.DATES >= .OOS_FROM)) stop(sprintf("[%s] OOS 거래일 0건", .TAG))

# 월말 거래일 = 시그널일 (집행 = 익월 첫 거래일 — get_execution_date 규약)
.cal <- data.table(Date = .DATES)
.cal[, MI := year(Date) * 12L + month(Date)]
.SIGDATES <- .cal[, .(SigDate = max(Date)), by = MI][order(MI)]$SigDate
.SIGDATES <- .SIGDATES[.SIGDATES >= .OOS_FROM]

# 확장창 반복 블록 — 논문: 5년 OOS 씩 전진하며 학습 데이터를 5년씩 누적
.BLK <- list()
.bs  <- .OOS_FROM
while (.bs <= .DMAX) {
  .be <- seq(.bs, by = paste(.BLOCK_Y, "years"), length.out = 2L)[2L]
  .BLK[[length(.BLK) + 1L]] <- list(start = .bs, end = min(.be - 1L, .DMAX))
  .bs <- .be
}
cat(sprintf("[%s] 거래일 %d (%s ~ %s) | 시그널월 %d | 확장창 반복 %d\n",
            .TAG, length(.DATES), as.character(min(.DATES)), as.character(.DMAX),
            length(.SIGDATES), length(.BLK)))

# =============================================================================
# 2. 반복별 패널 선정 (PIT — 선정일 이전 정보만)
# =============================================================================
#   ① 선정일 psel = 블록 시작 직전 거래일
#   ② 그 시점 K200∪KQ150 멤버 & adv20(t−1) ≥ 2e8
#   ③ 학습창 [.TRAIN_FROM, psel] 수익 관측 완전성(높을수록 우선 — 논문 고정패널 성질)
#   ④ 그 안에서 adv20 상위 .NPANEL 종
.panel_of <- function(psel) {
  ndays <- sum(.DATES >= .TRAIN_FROM & .DATES <= psel)
  cand  <- .rd[Date == psel & (K200 | KQ150) &
                 is.finite(ADV20_L1) & ADV20_L1 >= .LIQ, .(Ticker, ADV20_L1)]
  if (!nrow(cand)) return(character(0))
  cmp <- .rd[Date >= .TRAIN_FROM & Date <= psel & is.finite(Ret), .(NOBS = .N), by = Ticker]
  cand <- merge(cand, cmp, by = "Ticker", all.x = TRUE)
  cand[!is.finite(NOBS), NOBS := 0L]
  cand[, FULL := as.integer(NOBS >= 0.95 * ndays)]
  setorder(cand, -FULL, -ADV20_L1)
  head(cand$Ticker, .NPANEL)
}

for (b in seq_along(.BLK)) {
  ps <- max(.DATES[.DATES < .BLK[[b]]$start])
  .BLK[[b]]$psel  <- ps
  .BLK[[b]]$panel <- .panel_of(ps)
  cat(sprintf("[%s] 반복 %d | 학습 %s~%s | OOS %s~%s | 패널 %d종\n", .TAG, b,
              as.character(.TRAIN_FROM), as.character(ps),
              as.character(.BLK[[b]]$start), as.character(.BLK[[b]]$end),
              length(.BLK[[b]]$panel)))
}
.UTK <- sort(unique(unlist(lapply(.BLK, `[[`, "panel"))))
if (length(.UTK) < 10L) stop(sprintf("[%s] 패널 합집합 %d종 — 유니버스/유동성 확인", .TAG, length(.UTK)))

# =============================================================================
# 3. 피처 14종 (F.1 5 + F.2 9) — 전부 후향창. 합집합 종목에 대해 한 번만 만든다.
# =============================================================================
.wc <- dcast(.rd[Ticker %chin% .UTK, .(Date, Ticker, Close)], Date ~ Ticker, value.var = "Close")
.wr <- dcast(.rd[Ticker %chin% .UTK, .(Date, Ticker, Ret)],   Date ~ Ticker, value.var = "Ret")
setorder(.wc, Date); setorder(.wr, Date)
stopifnot(identical(.wc$Date, .wr$Date))
.WD <- .wc$Date
.PM <- as.matrix(.wc[, -1L, with = FALSE])
.RM <- as.matrix(.wr[, -1L, with = FALSE])
.TKC <- colnames(.PM)
stopifnot(identical(.TKC, colnames(.RM)))
rm(.wc, .wr); gc(verbose = FALSE)

.NT <- length(.WD); .NC <- length(.TKC)
.FEAT <- vector("list", .DFEAT)
for (j in seq_len(.DFEAT)) .FEAT[[j]] <- matrix(0, nrow = .NT, ncol = .NC)
.SANN <- matrix(NA_real_, nrow = .NT, ncol = .NC)   # 사전 연율 변동성 σ_ann(t)

.aVOL <- 2 / (.VOL_SPAN + 1)
.aWIN <- 2 / (.WIN_SPAN + 1)

# 후향 롤링 표준편차 (frollmean 2회 — 전 표본 통계 아님)
.roll_sd <- function(x, w) {
  m1 <- frollmean(x, w, align = "right")
  m2 <- frollmean(x * x, w, align = "right")
  sqrt(pmax(m2 - m1 * m1, 0) * (w / (w - 1)))
}
# 재귀 EWMA: y_t = (1−a)·y_{t−1} + a·x_t  (과거→미래 1방향)
.ewma <- function(x, a, init) as.numeric(stats::filter(a * x, filter = 1 - a,
                                                       method = "recursive", init = init))

for (cj in seq_len(.NC)) {
  p <- .PM[, cj]; r <- .RM[, cj]
  fo <- which(is.finite(p))[1L]
  if (is.na(fo)) next
  p <- nafill(p, type = "locf")
  if (fo > 1L) p[1L:(fo - 1L)] <- p[fo]          # 상장 전 구간 = 상수(재귀 워밍업용, 뒤에서 마스킹)
  r[!is.finite(r)] <- 0

  # ---- 사전 변동성: 60일 EWM 표준편차(원문) → 연율화
  mu  <- .ewma(r, .aVOL, 0)
  vv  <- .ewma((r - mu)^2, .aVOL, 0)
  sdd <- sqrt(pmax(vv, 0))
  .SANN[, cj] <- sdd * .ANN

  # ---- F.1: r_{t−k,t} / (σ_t·√k)
  for (jj in seq_along(.KWIN)) {
    k  <- .KWIN[jj]
    rk <- p / shift(p, k) - 1
    .FEAT[[jj]][, cj] <- rk / (sdd * sqrt(k))
  }

  # ---- F.2: MACD.  HL=log(0.5)/log(1−1/j) ⇒ EWMA 감쇠 = (1−1/j), 즉 α = 1/j
  ms <- lapply(.MACD_S, function(j) .ewma(p, 1 / j, p[1L]))
  ml <- lapply(.MACD_L, function(j) .ewma(p, 1 / j, p[1L]))
  sp <- .roll_sd(p, .STD_P)
  ix <- length(.KWIN)
  for (si in seq_along(.MACD_S)) for (li in seq_along(.MACD_L)) {
    ix <- ix + 1L
    q  <- (ms[[si]] - ml[[li]]) / ifelse(is.finite(sp) & sp > 0, sp, NA_real_)
    sq <- .roll_sd(q, .STD_Q)
    .FEAT[[ix]][, cj] <- q / ifelse(is.finite(sq) & sq > 0, sq, NA_real_)
  }

  # ---- (K2b) 원문 전처리 winsorize: |x − EWM평균| ≤ 5 × EWM표준편차 (span 252)
  #      EWM 이 t 를 포함한 **후향 재귀**라 창 밖·미래를 보지 않는다(C1·C7 유지).
  #      ★자르는 대상은 **모델 입력뿐**이다 — 표적 r_{t,t+1} 과 σ_t 는 건드리지 않는다.
  #        수익 자체를 winsorize 하면 백테스트 수익이 실현치가 아니게 된다.
  for (j in seq_len(.DFEAT)) {
    x <- .FEAT[[j]][, cj]
    x[!is.finite(x) | abs(x) > .BIG] <- 0
    mx <- .ewma(x, .aWIN, 0)
    sx <- sqrt(pmax(.ewma((x - mx)^2, .aWIN, 0), 0))
    .FEAT[[j]][, cj] <- pmin(pmax(x, mx - .WIN_K * sx), mx + .WIN_K * sx)
  }

  # ---- 워밍업 마스킹: 상장 후 (63+252)거래일 미만 구간은 피처 미발행
  wu <- min(.NT, fo + .STD_P + .STD_Q - 1L)
  if (wu >= 1L) {
    for (j in seq_len(.DFEAT)) .FEAT[[j]][1L:wu, cj] <- NA_real_
    .SANN[1L:wu, cj] <- NA_real_
  }
}
for (j in seq_len(.DFEAT)) {
  m <- .FEAT[[j]]
  m[!is.finite(m) | abs(m) > .BIG] <- 0        # 비유한 = 무신호(중립). 수치 가드.
  .FEAT[[j]] <- m
}
rm(.PM); gc(verbose = FALSE)
cat(sprintf("[%s] 피처 %d종 × %d종목 × %d일 구축 (%.1f분)\n", .TAG, .DFEAT, .NC, .NT,
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))

# 시그널일 적격(멤버십 + 유동성) 조회표
.EL <- .rd[Date %in% .SIGDATES & (K200 | KQ150) & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ,
           .(Date, Ticker)]
setkey(.EL, Date, Ticker)
rm(.rd); gc(verbose = FALSE)

# =============================================================================
# 4. SLP — X_t = tanh(W'u_t + b) · 손실 = Σ_i (1/N)·(−Sharpe_i) + α·Σ|w|
# =============================================================================
#   u_t = [f_t, f_{t−1}, …, f_{t−τ+1}] 를 실제로 만들지 않는다(메모리). 대신 lag 블록별
#   행렬곱을 누적한다 — 수학적으로 동일하고 τ배 메모리를 안 쓴다.
.fwd <- function(FB, ii, Wm, bv, nd, N) {
  Z <- matrix(bv, nrow = length(ii), ncol = N, byrow = TRUE)
  for (l in seq_len(.TAU))
    Z <- Z + FB[ii - (l - 1L), , drop = FALSE] %*% Wm[((l - 1L) * nd + 1L):(l * nd), , drop = FALSE]
  tanh(Z)
}

# 손실 + dL/dX.  R_ti = X·s·r − c·|X_t·s_t − X_{t−1}·s_{t−1}| (미니배치 내부 국소 회전율)
.objective <- function(X, S, RF, cc) {
  nb <- nrow(X); N <- ncol(X)
  XS  <- X * S
  DXS <- rbind(matrix(0, 1L, N), diff(XS))     # 배치 첫 행 = 회전율 0 (localized)
  Gs  <- sign(DXS)
  R   <- X * S * RF - cc * abs(DXS)
  mu  <- colMeans(R)
  v   <- pmax(colMeans(R * R) - mu * mu, 1e-16)
  sv  <- sqrt(v)
  Li  <- -.ANN * mu / sv
  # dL_i/dR_t = −(√252/nb)·[ v^{−1/2} − μ(R_t−μ)v^{−3/2} ],  ×λ_i(=1/N)
  A <- -(.ANN / (nb * N)) *
    (rep(1 / sv, each = nb) - rep(mu / (v * sv), each = nb) * (R - rep(mu, each = nb)))
  Ash <- rbind(A[-1L, , drop = FALSE], matrix(0, 1L, N))
  Gsh <- rbind(Gs[-1L, , drop = FALSE], matrix(0, 1L, N))
  list(loss = mean(Li),
       dX   = A * S * RF - cc * S * (A * Gs - Ash * Gsh))
}

.val_loss <- function(FB, ii, S, RF, Wm, bv, nd, N, cc) {
  X <- .fwd(FB, ii, Wm, bv, nd, N)
  .objective(X, S[ii, , drop = FALSE], RF[ii, , drop = FALSE], cc)$loss
}

# Adam + L1 서브그래디언트. 검증손실 최소 시점의 파라미터를 보존(조기중단).
.train_slp <- function(FB, S, RF, tr, va, alpha, nd, N, cc) {
  m  <- .TAU * nd
  Wm <- matrix(rnorm(m * N, sd = 1 / sqrt(m)), m, N)
  bv <- rep(0, N)
  mW <- matrix(0, m, N); vW <- matrix(0, m, N); mb <- rep(0, N); vb <- rep(0, N)
  b1 <- 0.9; b2 <- 0.999; eps <- 1e-8; step <- 0L
  keep_W <- Wm; keep_b <- bv
  vl_ref <- .val_loss(FB, va, S, RF, Wm, bv, nd, N, cc)
  stale  <- 0L
  nb_all <- length(tr)
  starts <- seq(1L, nb_all, by = .MB)
  for (ep in seq_len(.EPOCH)) {
    # ★sample(starts) 금지 — starts 가 길이 1이면 R 이 sample(n)=1:n 순열로 해석한다.
    for (s0 in starts[sample.int(length(starts))]) {   # 연속 구간 배치, 순서만 섞는다
      ii <- tr[s0:min(s0 + .MB - 1L, nb_all)]
      if (length(ii) < 8L) next
      X  <- .fwd(FB, ii, Wm, bv, nd, N)
      og <- .objective(X, S[ii, , drop = FALSE], RF[ii, , drop = FALSE], cc)
      dZ <- og$dX * (1 - X * X)
      gW <- matrix(0, m, N)
      for (l in seq_len(.TAU))
        gW[((l - 1L) * nd + 1L):(l * nd), ] <-
          crossprod(FB[ii - (l - 1L), , drop = FALSE], dZ)
      gW <- gW + alpha * sign(Wm)
      gb <- colSums(dZ)
      step <- step + 1L
      mW <- b1 * mW + (1 - b1) * gW; vW <- b2 * vW + (1 - b2) * gW * gW
      mb <- b1 * mb + (1 - b1) * gb; vb <- b2 * vb + (1 - b2) * gb * gb
      c1 <- 1 - b1^step; c2 <- 1 - b2^step
      Wm <- Wm - .LR * (mW / c1) / (sqrt(vW / c2) + eps)
      bv <- bv - .LR * (mb / c1) / (sqrt(vb / c2) + eps)
    }
    vl <- .val_loss(FB, va, S, RF, Wm, bv, nd, N, cc)
    if (is.finite(vl) && vl < vl_ref) {
      vl_ref <- vl; keep_W <- Wm; keep_b <- bv; stale <- 0L
    } else {
      stale <- stale + 1L
      if (stale >= .PATIENCE) break
    }
  }
  list(W = keep_W, b = keep_b, vloss = vl_ref)
}

# =============================================================================
# 5. 반복별 학습 → OOS 월말 포지션 → 논문 비중 (K5)
# =============================================================================
.ALPHA_SEL <- NA_real_
.wraw  <- list()     # 시그널일별 (Ticker, w_raw)
.sigd  <- as.Date(character(0))

for (b in seq_along(.BLK)) {
  pan <- .BLK[[b]]$panel
  ci  <- match(pan, .TKC); ci <- ci[is.finite(ci)]
  N   <- length(ci)
  if (N < 10L) { cat(sprintf("[%s] 반복 %d 패널 %d종 — 건너뜀\n", .TAG, b, N)); next }
  nd  <- N * .DFEAT

  # 블록 전용 피처 행렬 FB[date, (feature j 블록) × (asset)]
  FB <- matrix(0, nrow = .NT, ncol = nd)
  for (j in seq_len(.DFEAT)) FB[, ((j - 1L) * N + 1L):(j * N)] <- .FEAT[[j]][, ci, drop = FALSE]

  Sm <- .SIG_TGT / .SANN[, ci, drop = FALSE]
  Sm[!is.finite(Sm) | .SANN[, ci, drop = FALSE] < .SD_FLOOR] <- 0     # 퇴화 종목 = 포지션 0
  RFm <- rbind(.RM[-1L, ci, drop = FALSE], matrix(NA_real_, 1L, N))   # r_{t,t+1} (표적 전용)
  RFm[!is.finite(RFm)] <- 0

  # 학습 표본 인덱스: 창 안 + lag τ 확보 + t+1 수익 존재
  ip_lo <- which(.WD >= .TRAIN_FROM)[1L]
  ip_hi <- max(which(.WD <= .BLK[[b]]$psel))
  r_lo  <- max(ip_lo, .TAU); r_hi <- ip_hi - 1L
  # ★seq.int(a, b) 는 a > b 면 조용히 내림차순을 낸다 — 학습창이 비면 배치가 뒤집힌
  #   시간순으로 돌고 회전율 항이 의미를 잃는다. 빈 창은 배치가 아니라 중단이다.
  if (!is.finite(r_lo) || !is.finite(r_hi) || r_hi - r_lo < 4L * .MB)
    stop(sprintf("[%s] 반복 %d 학습창 부족 (%s 행) — .TRAIN_FROM/데이터 범위 확인",
                 .TAG, b, format(r_hi - r_lo)))
  rows  <- seq.int(r_lo, r_hi)
  ncut  <- floor(length(rows) * (1 - .VAL_FRAC))
  tr <- rows[seq_len(ncut)]; va <- rows[(ncut + 1L):length(rows)]    # 시간순 90/10

  if (!is.finite(.ALPHA_SEL)) {
    # α 선정 — 첫 확장창 반복의 검증손실만 본다(그 시점 이전 데이터). 이후 반복은 재사용.
    vls <- rep(NA_real_, length(.ALPHAS)); fits <- vector("list", length(.ALPHAS))
    for (ai in seq_along(.ALPHAS)) {
      fits[[ai]] <- .train_slp(FB, Sm, RFm, tr, va, .ALPHAS[ai], nd, N, .COST_C)
      vls[ai] <- fits[[ai]]$vloss
      cat(sprintf("[%s]   alpha=%.0e -> val %.4f\n", .TAG, .ALPHAS[ai], vls[ai]))
    }
    if (!any(is.finite(vls)))
      stop(sprintf("[%s] alpha 후보 전부 검증손실 비유한 — 학습 실패", .TAG))
    pick <- which.min(vls)
    .ALPHA_SEL <- .ALPHAS[pick]
    fit <- fits[[pick]]
    cat(sprintf("[%s] alpha 선정 = %.0e (검증손실 최소)\n", .TAG, .ALPHA_SEL))
    rm(fits)
  } else {
    fit <- .train_slp(FB, Sm, RFm, tr, va, .ALPHA_SEL, nd, N, .COST_C)
  }

  sd_b <- .SIGDATES[.SIGDATES >= .BLK[[b]]$start & .SIGDATES <= .BLK[[b]]$end]
  ii   <- match(sd_b, .WD)
  ok   <- is.finite(ii) & ii >= .TAU
  sd_b <- sd_b[ok]; ii <- ii[ok]
  if (!length(ii)) { rm(FB); gc(verbose = FALSE); next }

  X <- .fwd(FB, ii, fit$W, fit$b, nd, N)          # [-1,1] 포지션
  Wraw <- (1 / N) * X * Sm[ii, , drop = FALSE]    # w_i = (1/N)·X_i·σ_tgt/σ_i  (논문 산식)

  for (kk in seq_along(sd_b)) {
    elg <- .EL[.(sd_b[kk]), Ticker, nomatch = 0L]
    keep <- .TKC[ci] %chin% elg
    w <- Wraw[kk, ]; w[!keep | !is.finite(w)] <- 0
    .sigd <- c(.sigd, sd_b[kk])
    .wraw[[length(.wraw) + 1L]] <- list(ci = ci, w = w)
  }
  cat(sprintf("[%s] 반복 %d 학습 완료 | val %.4f | OOS 월 %d | 누적 %.1f분\n",
              .TAG, b, fit$vloss, length(sd_b),
              as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
  rm(FB, Sm, RFm, X, Wraw); gc(verbose = FALSE)
}

if (!length(.wraw)) stop(sprintf("[%s] OOS 시그널 0건", .TAG))

# =============================================================================
# 6. 포트폴리오 레벨 변동성 스케일링 (원문 명시: 연 15% 표적) — C5 준수
# =============================================================================
#   스케일러 k_t = σ_tgt / σ̂_port(t).  σ̂_port = **논문의 자산 추정기와 같은** 60일 EWM
#   표준편차를, 논문에 포트폴리오 레벨 산식이 없으므로 그대로 포트폴리오 수익에 적용한 것.
#   입력 = 미스케일 비중으로 실현된 **월간 보유** 일별 수익, 시그널일까지만. 홀딩월 정보 0.
#   워밍업 60거래일 미충족 구간은 신호를 발행하지 않는다(추정치 날조 금지).
.ord   <- order(.sigd)
.sigd  <- .sigd[.ord]; .wraw <- .wraw[.ord]
.mu_p <- 0; .v_p <- 0; .nobs_p <- 0L
.out  <- vector("list", length(.sigd))
.grs  <- rep(NA_real_, length(.sigd)); .lev <- rep(NA_real_, length(.sigd))

for (kk in seq_along(.sigd)) {
  ent <- .wraw[[kk]]
  ip  <- match(.sigd[kk], .WD)

  if (.nobs_p >= .VOL_SPAN) {
    sp <- sqrt(max(.v_p, 0)) * .ANN
    if (is.finite(sp) && sp > 1e-8) {
      kscale <- .SIG_TGT / sp
      w <- ent$w * kscale
      nz <- which(w != 0 & is.finite(w))
      if (length(nz)) {
        .out[[kk]] <- data.table(Date = .sigd[kk], Ticker = .TKC[ent$ci][nz],
                                 Weight = w[nz],
                                 Leg = ifelse(w[nz] > 0, "long", "short"))
        .grs[kk] <- sum(abs(w[nz])); .lev[kk] <- kscale
      }
    }
  }

  # 보유구간 (t_k, t_{k+1}] 의 미스케일 일별 수익으로 추정기 전진 — 전부 과거가 된 뒤 소비된다.
  hi <- if (kk < length(.sigd)) match(.sigd[kk + 1L], .WD) else min(.NT, ip + 25L)
  if (is.finite(ip) && is.finite(hi) && hi > ip) {
    Rh <- .RM[(ip + 1L):hi, ent$ci, drop = FALSE]
    Rh[!is.finite(Rh)] <- 0
    rp <- as.vector(Rh %*% ent$w)
    for (x in rp) {
      .mu_p <- (1 - .aVOL) * .mu_p + .aVOL * x
      .v_p  <- (1 - .aVOL) * .v_p + .aVOL * (x - .mu_p)^2
      .nobs_p <- .nobs_p + 1L
    }
  }
}

PORTFOLIO <- rbindlist(Filter(Negate(is.null), .out), use.names = TRUE)
if (!nrow(PORTFOLIO)) stop(sprintf("[%s] PORTFOLIO 0행 — 스케일러 워밍업/적격 확인", .TAG))
setorder(PORTFOLIO, Date, -Weight)

.nd <- PORTFOLIO[, .(N = .N, NL = sum(Weight > 0), NS = sum(Weight < 0)), by = Date]
cat(sprintf(paste0(
  "[%s] adapted: SLP(tanh) 한 장의 W 가 %d종 모멘텀피처 %d종을 받아 전 종목 포지션 동시 산출\n",
  "  피처 τ=%d·d=%d | 손실 = 자산별 −Sharpe 등가중 + L1(alpha=%.0e) + 회전율 c=%.4f\n",
  "  확장창 반복 %d회 · 학습 일별(논문) · 집행 월간(계약 제약)\n",
  "  월 %d개 (%s ~ %s) · 행 %d · 종목수 중앙 %.0f (롱 %.0f / 숏 %.0f)\n",
  "  총노출 Σ|w| 중앙 %.2f (10%%~90%% %.2f~%.2f) · 변동성 스케일러 중앙 %.2f\n",
  "  ★러너 호출: portfolio_spec=list(construction=\"engine_direct\") · commission_paper=NULL\n",
  "  소요 %.1f분\n"),
  .TAG, .NPANEL, .DFEAT, .TAU, .DFEAT, .ALPHA_SEL, .COST_C, length(.BLK),
  nrow(.nd), as.character(min(PORTFOLIO$Date)), as.character(max(PORTFOLIO$Date)),
  nrow(PORTFOLIO), median(.nd$N), median(.nd$NL), median(.nd$NS),
  median(.grs, na.rm = TRUE),
  as.numeric(stats::quantile(.grs, 0.1, na.rm = TRUE, names = FALSE)),
  as.numeric(stats::quantile(.grs, 0.9, na.rm = TRUE, names = FALSE)),
  median(.lev, na.rm = TRUE),
  as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
