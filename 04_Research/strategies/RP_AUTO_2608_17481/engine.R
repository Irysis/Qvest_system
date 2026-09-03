# =============================================================================
# engine.R — RP_AUTO_2608_17481
# "A generic nonparametric value-at-risk estimator for high dimensions"
#  Siyuan Sun, arXiv:2608.17481   https://arxiv.org/abs/2608.17481
#
# ★fidelity = ADAPTED (기전 이식). 정본 = FIDELITY.json
#
# ===== 왜 faithful 이 불가능한가 (판정 순서 1 → 2) =====
# 이 논문은 **리스크 측정** 논문이다. 산출은 하루짜리 숫자 두 개(99% VaR · CVaR)이고,
# 검증은 "무작위 포지션 500 포트폴리오 × 49개 선물에서 초과손실 빈도가 1.0% 인가"
# (중앙값 1.0±0.1%) 라는 backtest-of-the-estimator 다. 논문에 신호도, 종목선택도,
# 롱숏도, 리밸런싱도, 종목수도, 비중규칙도, 거래비용도 없다. 포지션은 알파가 아니라
# **난수**로 만든다(식 9: expo = (1/1000)·(1/σ^252)·U(0.3,1)·RandomSign).
#   → 복제할 '논문 그대로의 신호·종목수·비중·리밸'이 존재하지 않는다. faithful 불가.
#   → 데이터(일별 수익률)는 있다. ABORT 사유도 아니다. 판정 순서 2 = 기전 이식.
#
# ===== 무엇을 남기는가 (kept — 논문의 기전, 원문 식 그대로) =====
#  (K1) **최근변동성 σ^14 (식 4)** — 14일 TRP 의 RMS:
#         σ^14_{k,i−1} = sqrt( (1/14) · Σ_{l=i−14}^{i−1} TRP_{k,l}·TRP_{k,l} )
#       TRP 는 식 2: [max(high_i, close_{i−1}) − min(low_i, close_{i−1})] / close_{i−1}.
#       "빠르게 적응하는 스케일"이 이 논문의 첫 번째 부품이다.
#  (K2) **과거수익의 변동성 정규화 (식 5의 셋째 항)** — r_{k,j} / σ^14_{k,j−1}.
#       원문: "each past day j also has its own past recent volatility σ^14_{k,j−1},
#       calculated using days j−1 to j−14". 스케일을 나눠내면 남는 것이 **느리게 변하는
#       비가우스 모양**이고, 그게 미래로 지속된다는 것이 논문의 핵심 가정이다.
#  (K3) **시나리오 = 과거 하루를 통째로 (식 5)**:
#         P(portfolio return_i) = Σ_k expo_{k,i−1} · σ^14_{k,i−1} · (r_{k,j}/σ^14_{k,j−1})
#       과거 날짜 j 를 종목 간에 **쪼개지 않고** 그대로 하나의 시나리오로 쓴다. 그래서
#       상관행렬·공분산·팩터모형을 한 번도 만들지 않는다(원문: "Instead of modeling,
#       parameterization, and compression of these high-dimensional relationships, we
#       take the unperturbed historical values directly as inputs"). ★이것이 논문 제목의
#       'for high dimensions' 그 자체다 — 차원이 커져도 정확도가 안 죽는 이유.
#  (K4) **꼬리 추출** — 99% VaR = 시나리오 PDF 의 최악 1%. CVaR(ES) = 그 꼬리의 기대값.
#  (K5) **완전한 과거 이력 요구** — 원문: "We are therefore limited by the instrument
#       with the shortest amount of past data." 창 전체를 채우는 종목만 쓴다.
#  (K6) **모수는 둘뿐** — 변동성 창(14/30/45) · 과거 창(1260/2520/전체). 여기서는
#       식 4 에 박혀 있는 14 와, 제시된 3안 중 최단인 1260 을 쓴다(선택 근거 = 아래).
#
# ===== 무엇을 바꿨는가 (changed) — 전문은 FIDELITY.json =====
#  (1) **산출 형태**: 포트폴리오 1개의 VaR 숫자 → 횡단면 팩터 점수. 논문의 시나리오
#      엔진(K1~K4)을 **등가중 적격 유니버스 포트폴리오**에 걸고, 그 포트폴리오
#      99% ES 에 대한 **종목별 기여도(component ES · Euler 분해)**를 Score 로 낸다.
#      ES 는 양의 1차동차라 Σ_k expo_k·CC_k = ES 로 **정확히** 분해된다(VaR 은 시나리오
#      한 점이라 분해가 성립하지 않는다 — 그래서 논문이 함께 제시한 CVaR 쪽을 쓴다).
#  (2) **방향**: 논문은 수익 방향을 말하지 않는다(수익예측 논문이 아니다). 부호는
#      "리스크 추정량은 줄이라고 만든다"는 그 용도에서만 나온다 — 고정 축(롱온리·25종)
#      아래서 이 추정량을 최소화하는 선택 = **꼬리 기여가 가장 작은 25종 롱**.
#      외부 논문의 알파 부호(저변동성·하방베타 프리미엄 등)를 끌어오지 않았다.
#  (3) **TRP(식 2)의 정의역**: RAWDATA 에 high/low 가 없다. 식 2 를 **관측된 가격점이
#      종가뿐인 경로**에 그대로 대입하면 max(close_i, close_{i−1}) − min(close_i,
#      close_{i−1}) = |close_i − close_{i−1}| → TRP = |r_i|. 근사치를 지어낸 게 아니라
#      같은 식의 퇴화값이다. ★게다가 식 5 는 σ^14_{k,i−1} · (r_{k,j}/σ^14_{k,j−1}) 이라
#      종목별 상수배 c_k(장중폭/종가폭 비율)는 **정확히 상쇄**된다: (c_kσ_now)·
#      (r_j/(c_kσ_then)) = σ_now·r_j/σ_then. 남는 오차는 c_k 의 시간변동뿐이다.
#  (4) expo (식 9): 난수 포지션 → 등가중(1/n). 우리 고정 축이고, 랭킹은 expo 가
#      상수면 CC_k 순서에 영향을 주지 않는다.
#  (5) 과거 창 = 1260(논문 3안 중 최단). 근거는 성과가 아니라 **횡단면 보존**이다 —
#      K5(완전 이력)를 2520 으로 걸면 상장 10년 미만 종목이 전부 탈락해 유니버스가
#      대형·고령주로 기운다. 1260 도 '상장 5년 이상' 제약을 남기며 이는 논문 제약을
#      그대로 옮긴 것이지 우리가 만든 필터가 아니다(FIDELITY.json 에 명시).
#  (6) 유니버스만 K200∪KQ150(PIT 시변) + adv20(t−1) ≥ 2e8 · 2005-01-01~ · 월간 리밸.
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) =====
#  ▸ 구조 경계 ①: 패널 전체를 훑는 연산은 **행별 후방 롤링 3개**뿐이다
#      (frollmean(align="right") + by=Ticker shift(+1)). 각 행의 값이 그 행의 과거만
#      본다 — 전 표본 통계(cov/mean/quantile/scale)가 코드에 0건이다.
#  ▸ 구조 경계 ②: 시나리오·꼬리·기여도는 전부 `.UM[lo:ip, ]` 한 창 안에서만 계산된다.
#      ip = 시그널일(그 달 마지막 거래일) 행, lo = ip − 1259. ip 보다 큰 행을 읽는
#      코드가 **존재하지 않는다**. shift(−N)·미래 인덱싱 0건.
#  C1  : 전 표본 통계 0건. σ^14·u·ES·꼬리 전부 롤링/창 내부.
#  C2  : same-day 순환참조 없음. σ^14_{i−1} 의 종점 = 시그널일 t 종가(식 5 의 i−1 이
#        곧 t 다), 집행은 익월 첫 거래일(t+1). 예측 대상 수익은 그 이후에 발생한다.
#  C3  : 같은 기간 집계→적용 없음. 창의 종점이 보유월 **시작 전**이다.
#  C4  : 재무 패널 미사용(일별 수익·거래대금만). 공시시차 이슈 자체가 없다.
#  C5  : 오버레이 없음(S0/S1 오버레이 금지 준수).
#  C6  : 유니버스 = 각 시그널일의 K200/KQ150 멤버십(PIT 시변). 최종 명부 주입 없음.
#        ★K5(창 전체 이력 보유)는 t 시점에 확인 가능한 전방 필터라 생존편의가 아니다.
#  C7  : 자동탐지 idiom 0건. 유일한 shift 는 +1(과거 방향).
#  C9  : DD/VT 미사용.
#  C10 : 유동성 = 20일 평균 거래대금의 by-Ticker shift(1) = t−1 값 ≥ 2e8.
#  C11 : 매크로·외부 시계열 미사용.
#  C13 : Factor DB 미소비 → 부호 정렬 대상 없음. 방향은 논문의 용도(위험 최소화)에서
#        사전(a priori)으로 나온다 — 측정된 IC 부호를 보고 정한 것이 아니다.
#  C15 : Factor DB parquet 직접 load 0건.
#  ★rawdata 의 Market 열 미사용(KOSDAQ 0건 날조 — 메모리 카드). 시장구분 불필요.
#
# ===== 산출 =====
#   FACTORS(Date, Ticker, Score) — Score = CC_k = 등가중 유니버스 포트폴리오의
#     99% ES 꼬리 시나리오에서 종목 k 가 낸 평균 수익(단위노출당 · 손실이면 음수).
#     **높을수록(덜 음수일수록) 꼬리 기여가 작다 = 롱 후보.** 적격 전 종목에 발행하므로
#     러너의 IC·FF3/FF5/Carhart·FMB 분석이 선다.
#   러너 호출: portfolio_spec = list(construction="top_n_long", weighting="ew",
#              rebalance="monthly", n_long=25) · commission_paper = NULL(논문 무명시).
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

# 난수 미사용(결정론적 엔진)이지만 재현성 선언 고정.
set.seed(26081748L)

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(all(c("Date", "Ticker", "Close", "Vol", "Ret", "K200", "KQ150")
              %in% names(RAWDATA)))

# =============================================================================
# 상수 — 논문에서 온 것 / 우리 고정 축에서 온 것
# =============================================================================
# ▸ 논문에서 온 것 (자유 모수는 논문이 말한 대로 딱 2개다)
.VOLWIN   <- 14L      # 식 4 의 σ^14 — 원문이 식에 박아둔 값(대안 30·45 는 민감도 절)
.LOOKBACK <- 1260L    # 과거 창. 논문 제시 3안(1260 / 2520 / 전체) 중 최단.
                      #   선택 근거 = 성과가 아니라 횡단면 보존(K5 완전이력 제약과 결합).
.TAILP    <- 0.01     # 99% VaR/CVaR — 원문 "the worst 1% of the PDF"
# ▸ 우리 고정 축
.LIQ        <- 2e8                      # adv20(t−1) 하한 (KRW)
.NMIN       <- 25L                      # 월 최소 횡단면 = 고정 축 종목수. 미만이면 선택
                                        #   자체가 성립하지 않는다(실측상 200+ 라 무구속).
.SIG_FROM   <- as.Date("2005-01-01")
.PANEL_FROM <- as.Date("1999-01-01")    # 패널 하한. 첫 시그널일(2005-01)의 1260 거래일
                                        #   창은 ~2000-01 까지 필요하고, 그 시점에 σ^14·u
                                        #   가 이미 정의돼 있으려면 +15 거래일 여유가
                                        #   필요하다. 1년 여유. 신호 산출 범위에 무영향.

# =============================================================================
# 1. 일별 패널 → σ^14(식 4) · 정규화수익 u(식 5 셋째 항) · 유동성(C10)
# =============================================================================
.rd <- RAWDATA[Date >= .PANEL_FROM, .(Date, Ticker, Close, Vol, Ret, K200, KQ150)]
.rd <- .rd[is.finite(Close) & Close > 0]
setorder(.rd, Ticker, Date)

# (Date,Ticker) 중복 방어. 중복이 남으면 뒤의 dcast 가 조용히 fun.aggregate=length 로
#   떨어져 '정규화수익' 대신 '건수' 행렬을 만든다 — 에러 없이 신호가 통째로 바뀌는
#   침묵 실패다. by-Ticker shift 도 같은 전제를 쓴다. 중복이 없으면 무연산.
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[RP_AUTO_2608_17481] (Date,Ticker) 중복 %d행 — 첫 행만 남긴다\n", .ndup))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}

# 유동성 (C10 — t−1)
.rd[, TV := Close * Vol]
.rd[, ADV20_L1 := shift(frollmean(TV, 20L, align = "right"), 1L), by = Ticker]
.rd[, c("TV", "Close", "Vol") := NULL]   # 소비 끝난 열은 즉시 버린다(패널 1100만행)

# ---- 식 2 (TRP) · 식 4 (σ^14) ----
#   RAWDATA 에 high/low 가 없으므로 식 2 를 '관측 가격점 = 종가뿐' 인 경로에 대입한다:
#     max(close_i, close_{i−1}) − min(close_i, close_{i−1}) = |close_i − close_{i−1}|
#     → TRP_i = |close_i − close_{i−1}| / close_{i−1} = |r_i|.   (TRP² = r²)
#   식 5 에서 종목별 상수배는 정확히 상쇄된다(헤더 changed (3) 참조).
.rd[, TRP2 := Ret * Ret]
# SIG_AT[행 j] = 식 4 의 RMS(TRP, 종점 = 행 j 포함 14일).  align="right" = 후방 전용.
.rd[, SIG_AT := sqrt(frollmean(TRP2, .VOLWIN, align = "right")), by = Ticker]
# SIG_L1[행 j] = 종점이 j−1 인 14일 RMS = 원문 σ^14_{k,j−1} (days j−1 … j−14).  ★+1 shift
.rd[, SIG_L1 := shift(SIG_AT, 1L), by = Ticker]
.rd[, TRP2 := NULL]

# ---- 식 5 의 셋째 항: u_{k,j} = r_{k,j} / σ^14_{k,j−1} ----
#   분모가 시점 j 이전 정보만으로 만들어져 있어 same-day 순환이 구조적으로 불가능하다.
.rd[, U := Ret / SIG_L1]
.rd[!is.finite(SIG_L1) | SIG_L1 <= 0, U := NA_real_]
.rd[, c("Ret", "SIG_L1") := NULL]
gc(verbose = FALSE)

# =============================================================================
# 2. 시그널일(월말) · 적격 유니버스 (C6 · C10)
# =============================================================================
.rd[, MI := year(Date) * 12L + month(Date)]
.mend <- .rd[, .(SigDate = max(Date)), by = MI]
setorder(.mend, MI)
.SIG <- .mend[SigDate >= .SIG_FROM, .(MI, SigDate)]
if (nrow(.SIG) == 0L)
  stop("[RP_AUTO_2608_17481] 시그널일 0건 — RAWDATA 날짜 범위 확인")

# 적격 = 시그널일의 K200/KQ150 멤버십(PIT 시변) + adv20(t−1) 하한 + 현재변동성 유효.
#   SNOW = 식 5 의 σ^14_{k,i−1} (i = 보유월 첫 거래일 → i−1 = 시그널일 t).
#   ★SNOW > 0 강제: 14일 내리 무변동(장기 거래정지)이면 σ_now = 0 → CC_k = 0 이 되어
#     '꼬리 기여 0' 으로 최상위에 올라온다. 값이 아니라 미측정이므로 배제한다.
.ELIG <- .rd[Date %in% .SIG$SigDate][
             (K200 | KQ150) & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ &
             is.finite(SIG_AT) & SIG_AT > 0,
             .(SigDate = Date, Ticker, SNOW = SIG_AT)]
if (nrow(.ELIG) == 0L)
  stop("[RP_AUTO_2608_17481] 적격 종목 0건 — 멤버십/유동성 필터 확인")

# =============================================================================
# 3. 정규화수익 행렬 (한 번만 만든다 — 이후 전부 '창 슬라이스'로만 접근한다)
# =============================================================================
# ★PIT 구조: .UM 은 날짜 오름차순 행렬이고 모든 소비는 `.UM[lo:ip, ]` 뿐이다.
.DATES <- sort(unique(.rd$Date))
.SIG[, IP := match(SigDate, .DATES)]
.SIG <- .SIG[is.finite(IP) & IP >= .LOOKBACK]
if (nrow(.SIG) == 0L)
  stop(sprintf("[RP_AUTO_2608_17481] 과거 창 %d일을 채우는 시그널일 없음", .LOOKBACK))

.from_i  <- min(.SIG$IP) - .LOOKBACK + 1L
.from_d  <- .DATES[.from_i]
.KEEP_TK <- unique(.ELIG$Ticker)

.wide <- dcast(.rd[Date >= .from_d & Ticker %chin% .KEEP_TK, .(Date, Ticker, U)],
               Date ~ Ticker, value.var = "U")
setorder(.wide, Date)
.WD <- .wide$Date
.UM <- as.matrix(.wide[, -1L, with = FALSE])
.TK <- colnames(.UM)
rm(.wide, .rd); gc(verbose = FALSE)   # 이후 소비는 .UM 창 슬라이스와 .ELIG 뿐이다

.SIG[, RI := match(SigDate, .WD)]
.SIG <- .SIG[is.finite(RI) & RI >= .LOOKBACK]
if (nrow(.SIG) == 0L)
  stop("[RP_AUTO_2608_17481] 행렬 정렬 후 시그널일 0건 — 패널 하한/과거 창 확인")

# (K5) 종목별 '이력 시작' 행 = u 가 처음 유효해지는 행. 창 전체를 못 채우는 종목은
#   그 달에서 배제한다 — 원문 "limited by the instrument with the shortest amount of
#   past data" 의 종목별 적용이다. 열 단위로만 훑는다(큰 논리행렬 생성 회피).
.FIRST <- vapply(seq_len(ncol(.UM)), function(j) {
  w <- which(is.finite(.UM[, j])); if (length(w)) w[1L] else NA_integer_
}, integer(1L))

cat(sprintf("[RP_AUTO_2608_17481] 패널 %d일 × %d종 | 시그널일 %d개 (%s ~ %s) | 창 %d일 · σ^%d\n",
            length(.WD), length(.TK), nrow(.SIG),
            as.character(min(.SIG$SigDate)), as.character(max(.SIG$SigDate)),
            .LOOKBACK, .VOLWIN))

# =============================================================================
# 4. 월별 루프 — 식 5 시나리오 → 99% VaR/ES(K4) → 종목별 ES 기여(Euler)
# =============================================================================
# 꼬리 표본 수: 원문은 "1 퍼센트의 과거일이 선(線) 아래 놓일 때까지 선을 내린다".
#   '아래' = 엄격 미만이므로 floor(1% × N) = 12일(N=1260)이 꼬리다.
.MTAIL <- max(1L, as.integer(floor(.TAILP * .LOOKBACK)))

.out    <- vector("list", nrow(.SIG))
.nskip  <- 0L
.nmin_x <- NA_integer_
.t0     <- Sys.time()

for (k in seq_len(nrow(.SIG))) {
  sd_k <- .SIG$SigDate[k]
  ip   <- .SIG$RI[k]
  lo   <- ip - .LOOKBACK + 1L                 # ★창 = [ip−1259, ip]. 종점이 시그널일이다.

  el   <- .ELIG[SigDate == sd_k]
  ci   <- match(el$Ticker, .TK)
  ok   <- is.finite(ci)
  ci   <- ci[ok]; tkc <- el$Ticker[ok]; snow <- el$SNOW[ok]

  # (K5) 창 전체를 덮는 이력이 있는 종목만. t 시점에 확인 가능한 전방 필터다.
  hok  <- is.finite(.FIRST[ci]) & .FIRST[ci] <= lo
  ci   <- ci[hok]; tkc <- tkc[hok]; snow <- snow[hok]
  n    <- length(ci)
  if (n < .NMIN) { .nskip <- .nskip + 1L; next }
  .nmin_x <- if (is.na(.nmin_x)) n else min(.nmin_x, n)

  Umat <- .UM[lo:ip, ci, drop = FALSE]        # T×n — 이 블록 밖 데이터는 만지지 않는다
  # 상장 이후의 창 내부 결측(거래정지 등)은 '무거래 = 무수익' 이므로 0. 상장 이전은
  #   위 (K5) 에서 이미 배제됐다 — 없는 이력을 0 으로 지어내지 않는다.
  nfill <- sum(!is.finite(Umat))
  Umat[!is.finite(Umat)] <- 0

  # ---- 식 5: 시나리오 j 에서 종목 k 의 기여 = σ^14_{k,i−1} · (r_{k,j}/σ^14_{k,j−1})
  #      (열 = 종목이므로 rep(each = 행수) 가 곧 열별 스케일링)
  Smat <- Umat * rep(snow, each = .LOOKBACK)
  # 포트폴리오 시나리오 수익 = Σ_k expo_k · (위) · expo = 1/n (등가중)
  Rsc  <- rowSums(Smat) / n
  if (!all(is.finite(Rsc))) { .nskip <- .nskip + 1L; next }

  # ---- (K4) 최악 1% = 꼬리. VaR = 그 선, ES = 꼬리의 기대값.
  ordr <- order(Rsc)
  ti   <- ordr[seq_len(.MTAIL)]

  # ---- Euler 분해: ES = Σ_k expo_k · CC_k, CC_k = 꼬리 시나리오에서의 평균 기여.
  #      expo 가 상수(1/n)라 CC_k 자체가 단위노출당 꼬리 기여다.
  cc  <- colMeans(Smat[ti, , drop = FALSE])
  fin <- is.finite(cc)
  if (sum(fin) < .NMIN) { .nskip <- .nskip + 1L; next }

  # Score = CC_k. 손실 기여는 음수 → **높을수록 꼬리 기여가 작다 = 롱 후보.**
  .out[[k]] <- data.table(Date = sd_k, Ticker = tkc[fin], Score = as.numeric(cc[fin]))

  if (k %% 24L == 0L) {
    cat(sprintf(paste0("[RP_AUTO_2608_17481] %s | n=%d | 99%%VaR %.3f%% · ES %.3f%% ",
                       "| CC 중앙 %.4f%% · 최소 %.4f%% | fill %.3f%% | skip=%d\n"),
                as.character(sd_k), sum(fin),
                -Rsc[ordr[.MTAIL]] * 100, -mean(Rsc[ti]) * 100,
                median(cc[fin]) * 100, min(cc[fin]) * 100,
                100 * nfill / length(Umat), .nskip))
    gc(verbose = FALSE)
  }
  rm(Umat, Smat)
}

FACTORS <- rbindlist(Filter(Negate(is.null), .out), use.names = TRUE)
if (nrow(FACTORS) == 0L)
  stop("[RP_AUTO_2608_17481] FACTORS 0행 — 유니버스/과거 창 확인")
setorder(FACTORS, Date, -Score)

cat(sprintf(paste0("[RP_AUTO_2608_17481] adapted: 논문 시나리오 엔진(식 4·5)으로 등가중 ",
                   "유니버스의 99%% ES 를 만들고 그 **종목별 기여(Euler)** 를 Score 로.\n",
                   "  Score 높을수록 꼬리 기여 작음 = 롱. 창 %d일 · σ^%d · 꼬리 %d일(=1%%)\n",
                   "  월 %d개 (%s ~ %s) · skip %d · 최소 횡단면 %s · FACTORS %d행 · %.1f분\n",
                   "  ★러너 호출: portfolio_spec=list(construction=\"top_n_long\", ",
                   "weighting=\"ew\", rebalance=\"monthly\", n_long=25) · commission_paper=NULL\n"),
            .LOOKBACK, .VOLWIN, .MTAIL,
            uniqueN(FACTORS$Date),
            as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date)),
            .nskip, as.character(.nmin_x), nrow(FACTORS),
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
