# =============================================================================
# engine.R — RP_AUTO_2608_14014
# "Buy the Rumor, Sell the News: When Is News Priced In?"
#  arXiv:2608.14014   https://arxiv.org/abs/2608.14014
#
# ★fidelity = ADAPTED (기전 이식). 정본 = FIDELITY.json — 이 주석은 사본이다.
#
# ===== 왜 faithful 이 불가능한가 (판정 순서 1 → 2 → 3) =====
# 세 조건이 각각 독립적으로 faithful 을 막는다. 하나라도 살아 있으면 시도했을 것이다.
#  (F1) **뉴스 코퍼스 부재**. 논문의 신호는 NewsWitch 상용 코퍼스(기사 4.57M → stock-day
#       이벤트 1.68M)에 붙은 **17개 이벤트 태그 × 5단계 감성**이다. 한국시장에 그런 패널이
#       없고, 우리 인프라에도 없다. 감성·태그는 대리변수로 지어낼 수 있는 종류가 아니다.
#  (F2) **일간 리밸·중첩 코호트 불가**. 논문 포트폴리오는 "이벤트 +5일 종가 진입 → +20일
#       종가 청산, 열린 포지션 전체 등가중, **일간 리밸**"이다. 우리 러너의
#       `get_execution_date()`(backtest_harness.R:316)는 시그널일 → **익월 첫 거래일**로
#       하드코딩돼 있어 한 달에 시그널일이 하나뿐이다. 중첩 코호트를 표현할 수 없다.
#  (F3) **논문 전략의 유니버스가 뉴스로 정의된다**. Strategy 2(벤치마크)조차 "뉴스에 등장한
#       모든 소형주를 숏" 이다 — (F1) 이 죽으면 유니버스 자체가 정의되지 않는다.
# → 데이터(일별 수익 · 벤치마크 수익)는 있으므로 ABORT 사유는 아니다. 판정 순서 2 = 이식.
#
# ===== 무엇을 남기는가 (kept — 논문의 기전·식·수치 그대로) =====
#  (K1) **초과수익 정의(원문 그대로)**: "The abnormal return is AR_t = r_t − β_t × r_m,t
#       with β_t a rolling 252-day OLS beta of the stock against the S&P 500, as of day t
#       (minimum 126 observations, **missing betas set to 1**)."
#       → 252일 롤링 OLS 베타 · 최소 126관측 · 결측 β = 1. 지수만 KOSPI(BM_DT)로 바뀐다.
#  (K2) **이벤트 시간 창(논문 Table 2 열 머리글 그대로)**: −5..0 | day 0 | +1..+5 | +6..+20.
#       신호는 **−5..0**(공표일 포함 6거래일)의 누적 AR, 거래는 **+6..+20**.
#  (K3) **진입 시점 = day +5 종가, 청산 = day +20 종가**. 즉 신호창과 보유창 사이에
#       **+1..+5 5거래일을 통째로 버린다**. 이 간극이 논문 설계의 핵심이고 그대로 남긴다.
#  (K4) **페이드 방향**: "After positive sentiment → short stock; after negative → long."
#       논문 실측 근거 = 공표일 종가까지의 누적 AR +0.58% 가 +20일에 +0.20% 로 줄어든다
#       (비율 2.8 — 제목의 'buy the rumor, sell the news'). 즉 **선반영된 움직임은 되돌린다**.
#  (K5) **기저 드리프트 차감 s(AR_w − b_{k,w})** — 이 논문의 방법론적 본체다. b_{k,w} =
#       **사이즈 버킷 k** 의 플라시보(중립) 이벤트가 창 w 에서 낸 평균 AR. 이걸 빼야
#       "호재는 역전, 악재는 지속" 이라는 겉보기 비대칭이 "at once" 사라진다.
#  (K6) **사이즈 버킷 = 거래대금 3분위, 매년**: "Stocks are split each year into three
#       equal-sized groups (small, mid, large) by dollar volume."
#  (K7) **논문의 자기반증까지 남긴다**: 논문은 페이드 전략의 이득이 전부 기저 드리프트였고
#       ("The fading strategy's entire edge is the background drift; the news direction
#       contributes nothing") 조정 후 +6..+20 은 −0.05% ≈ 0 이라고 스스로 결론짓는다.
#       ★그래서 이 엔진은 **논문이 미국 2023~26 에서 null 이라 판정한 그 조정판**을
#       한국 2005~2026 횡단면에 그대로 거는 것이다. null 이 나오면 그건 구현 실패가 아니라
#       논문 주장의 표본외 확인이다. 성과를 만들려고 (K5)를 빼는 선택은 하지 않았다.
#  (K8) **이벤트 조건을 걸지 않는 것도 논문 근거다**: 논문은 뉴스 없는 'quiet stock-days'
#       도 같은 드리프트를 낸다고 실측했다(소형 −0.74% · 중형 −0.88% · 대형 −0.59%,
#       뉴스 중립 이벤트는 −0.92 / −0.58 / −0.34). 뉴스 유무가 아니라 사이즈가 축이다.
#       → 거래량 급증 같은 '뉴스 대리변수'를 만들지 않았다. 논문이 쓰지 않는 축이다.
#
# ===== 이벤트시간 ↔ 달력 정렬 (이식의 유일한 좌표변환) =====
#   러너는 시그널일 t(월말) → 익월 첫 거래일 집행 → 그 달 보유(≈20거래일)다.
#   논문은 day +5 종가 진입 → +6..+20 보유(15거래일)다.
#   ⇒ **t ≡ 논문의 day +5** 로 놓는다. 그러면
#        보유창  +6..+20  =  t+1 …            (우리 보유월)          ✓ 논문 거래창
#        공표일  day 0    =  t − 5거래일
#        신호창  −5..0    =  거래일 오프셋 [t−10, t−5]  (6거래일)     ✓ 논문 신호창
#        버리는 +1..+5    =  [t−4, t]                                 ✓ 논문대로 미사용
#   ★그래서 이 신호는 표준 1개월 리버설이 아니다 — **최근 5거래일을 건너뛴 6거래일 창**이고,
#     그 간극은 우리가 만든 게 아니라 논문 진입시점(+5)이 만든 것이다.
#
# ===== 무엇을 바꿨는가 (changed) — 전문은 FIDELITY.json =====
#  (1) 신호원: 뉴스 감성 부호 s → **베타조정 런업 자체의 부호**. 논문에서 s 와 day-0 누적
#      AR 은 정의상 같은 방향이고(K4 의 +0.58% 가 그 s 방향 값이다), 우리는 s 를 못 얻으므로
#      논문이 s 방향으로 잰 그 움직임을 직접 신호로 쓴다. 감성을 지어내지 않았다.
#  (2) 플라시보 b_{k,w}: 논문은 '중립 감성 이벤트의 표본평균'으로 잰다. 중립군이 없고,
#      표본 전체 평균은 C1(전 표본 통계) 위반이다. → **같은 시그널일 · 같은 사이즈 버킷의
#      횡단면 평균**으로 잰다. 시점 t 정보만 쓰므로 구조적으로 미래참조가 불가능하고,
#      역할(그 버킷의 배경 드리프트 제거)은 동일하다.
#  (3) 버킷 갱신 시점: 논문 "each year" 를 지키되 PIT 로 못박는다 — 연도 Y 의 버킷은
#      **Y−1 마지막 거래일**의 252일 평균 거래대금으로 배정하고 분위점도 그 날짜에서 뜬다.
#      그 날 값이 없는 종목(신규상장)만 자기 t−1 ADV252 를 같은 분위점에 대본다.
#  (4) 리밸·종목수·비중: 논문(일간 리밸 · 열린 포지션 전체 등가중)은 (F2)로 표현 불가.
#      → **우리 고정 축**(월간 · 25종 · EW)을 쓴다. 임의로 정한 수치가 아니다.
#  (5) 방향 축소: 논문은 롱숏(주로 숏)이다. 고정 축이 롱온리이므로 **페이드의 롱 다리만**
#      취한다 — 조정 런업이 가장 음(−)인 25종. 부호를 뒤집은 게 아니라 다리를 하나 뺐다.
#  (6) 지수: S&P 500 → BM_DT(국내 벤치마크). 유니버스만 K200∪KQ150(PIT 시변) +
#      adv20(t−1) ≥ 2e8 + 2005-01-01~.
#  ▸ 임의로 정한 수치: 0개. 252·126·β결측=1·(−5..0)·(+5 진입)·3분위·거래대금 = 논문값,
#    25·EW·월간·2e8·K200∪KQ150 = 고정 축. 나머지는 '값'이 아니라 유효성 가드다(아래 ★).
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) =====
#  ▸ 구조 경계 ①: 시계열 연산은 **후방 누적합 `.rsum()` + by-Ticker shift(+1)** 뿐이다.
#      `.rsum(x,k)[i] = Σ_{j=max(1,i−k+1)}^{i} x_j` — 정의상 i 보다 큰 인덱스를 못 읽는다.
#      shift 는 전부 양수(과거 방향). shift(−n)·미래 인덱싱·rev()·future join 0건.
#  ▸ 구조 경계 ②: 횡단면 연산(버킷 평균·분위점)은 전부 `by = SigDate` 또는 `by = ANCH`
#      (= 과거의 특정 하루) 안에서만 돈다. 여러 날짜를 가로지르는 통계가 0건이다.
#  ▸ 구조 경계 ③: 신호창의 마지막 거래일은 **t−5** 다. 보유는 t+1 부터다. 6거래일의
#      완충이 코드가 아니라 창 산술로 강제된다(.K_LONG/.K_SHORT).
#  C1  : 전 표본 통계 0건. β·ADV·CAR 전부 후방 롤링, 분위점은 단일 과거일 횡단면.
#  C2  : same-day 순환 없음. β 는 **1일 지연**(창 종점 t−1)이라 AR_t 가 자기 자신으로
#        만든 β 를 쓰지 않는다 — 원문 "as of day t" 보다 엄격한 쪽으로 굳혔다.
#  C3  : 같은 기간 집계→적용 없음. 집계창 [t−10,t−5] ∩ 보유창 [t+1,…] = ∅.
#  C4  : 재무제표 미사용(일별 수익·거래대금·벤치마크뿐). 공시시차 이슈 자체가 없다.
#  C5  : 오버레이 없음(S0/S1 오버레이 금지 준수).
#  C6  : 유니버스 = 각 시그널일의 K200/KQ150 멤버십(PIT 시변). 최종 명부 주입 없음.
#        버킷 분위점 모집단도 **앵커일 당시** 멤버십이다(현재 명부 역주입 없음).
#  C7  : 자동탐지 idiom 0건.
#  C8  : FM weight 미사용.
#  C9  : DD/VT 미사용.
#  C10 : 유동성 = 20일 평균 거래대금의 by-Ticker shift(1) = t−1 값 ≥ 2e8. ADV252 도 동일.
#  C11 : 외부 매크로 시계열 미사용. BM_DT 는 동일 시장 일별 가격지수(보고시차 없음).
#  C13 : Factor DB 미소비 → 정렬 대상 없음. 부호는 논문의 페이드 방향에서 **사전(a priori)**
#        으로 나온다 — 측정된 IC 부호를 보고 정하지 않았다.
#  C15 : Factor DB parquet 직접 load 0건.
#  ★rawdata 의 Market 열 미사용(KOSDAQ 0건 날조 — 메모리 카드). 사이즈 축은 거래대금이다.
#
# ===== 산출 =====
#   FACTORS(Date, Ticker, Score) — Score = −(CAR(−5..0) − b_{k,t}).
#     **높을수록 = 사이즈버킷 대비 런업이 가장 음(−)이었다 = 페이드의 롱 후보.**
#     적격 전 종목에 발행한다(러너의 IC·FF3/FF5/Carhart·FMB 가 서도록).
#   러너 호출: portfolio_spec = list(construction="top_n_long", weighting="ew",
#              rebalance="monthly", top_n=25, n_long=25) · commission_paper = NULL
#              (논문 헤드라인 15.8%/SR 1.35 는 gross. 비용은 5/10/20bps per-side 민감도
#               메뉴로만 제시돼 단일 왕복비용 명시가 없다 → null.)
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

# 난수 미사용(결정론적 엔진)이지만 재현성 선언 고정.
set.seed(26081401L)

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(exists("BM_DT"),   is.data.table(BM_DT))
stopifnot(all(c("Date", "Ticker", "Close", "Vol", "Ret", "K200", "KQ150")
              %in% names(RAWDATA)))
stopifnot(all(c("Date", "BM_Ret") %in% names(BM_DT)))

# =============================================================================
# 상수 — 논문에서 온 것 / 우리 고정 축에서 온 것 / 유효성 가드
# =============================================================================
# ▸ 논문에서 온 것
.BETA_WIN  <- 252L   # "rolling 252-day OLS beta"
.BETA_MIN  <- 126L   # "minimum 126 observations"
.BETA_MISS <- 1.0    # "missing betas set to 1"
.ENTRY_OFF <- 5L     # 진입 = 이벤트 day +5 종가  → 시그널일 t ≡ day +5
.PRE_LEN   <- 6L     # 신호창 −5..0 의 거래일 수 (−5,−4,−3,−2,−1,0)
.NBUCKET   <- 3L     # "three equal-sized groups ... by dollar volume", 매년
.ADV_WIN   <- 252L   # 버킷 배정용 거래대금 창(연 단위 배정 → 1년 = 252거래일)
# 신호창을 후방 누적합 2개의 차로 표현: rows (i−10 … i−5) = rsum(k=11) − rsum(k=5)
.K_SHORT   <- .ENTRY_OFF                    # 5  = 버리는 +1..+5
.K_LONG    <- .ENTRY_OFF + .PRE_LEN         # 11 = +1..+5 와 −5..0 을 합친 길이

# ▸ 우리 고정 축
.LIQ        <- 2e8                      # adv20(t−1) 하한 (KRW)
.LIQWIN     <- 20L
.NMIN       <- 25L                      # 월 최소 횡단면 = 고정 축 종목수
.SIG_FROM   <- as.Date("2005-01-01")
.PANEL_FROM <- as.Date("2002-01-01")    # 패널 하한. 2005-01 시그널의 β(252) · 버킷
                                        #   앵커(2004 말의 ADV252)를 모두 덮는 여유.

# ▸ 유효성 가드 (모수가 아니다 — '값'과 '미측정'을 가르는 선)
.ADV_MIN   <- 60L   # ADV252 를 값으로 인정할 최소 관측일. 미만 = 미측정(NA).
.GAPMAX    <- 31    # 신호창 11행이 걸치는 달력일 상한. 초과 = 장기 거래정지로 창이
                    #   늘어난 것 → '6거래일 창'이 아니므로 배제.
.MINBUCKET <- 5L    # 버킷 셀 최소 인원. 미만이면 버킷평균이 자기 자신이 되어 ADJ≡0 이
                    #   되고 '중립'으로 위장한다 → 그 날짜 전체 평균으로 대체.
.MINANCH   <- 30L   # 앵커일 분위점 모집단 최소. 미만이면 분위점을 신뢰하지 않는다.

# 후방 누적합. `.rsum(x,k)[i] = Σ_{j=max(1,i−k+1)}^{i} x_j`.
#   ★i 보다 큰 인덱스를 읽는 경로가 구조적으로 존재하지 않는다(PIT 경계 ①).
#   ★frollsum 과 달리 선행 부분창을 NA 로 버리지 않고 expanding 으로 준다 —
#     논문의 "minimum 126 observations"(창 길이가 아니라 **관측 수** 조건)를 그대로
#     표현하려면 이쪽이 맞다. 관측 수는 별도 카운트로 센다.
.rsum <- function(x, k) {
  n <- length(x)
  if (n == 0L) return(numeric(0))
  cs <- c(0, cumsum(x))
  i  <- seq_len(n)
  cs[i + 1L] - cs[pmax(0L, i - k) + 1L]
}

# =============================================================================
# 1. 일별 패널 + 벤치마크 결합
# =============================================================================
.rd <- RAWDATA[Date >= .PANEL_FROM, .(Date, Ticker, Close, Vol, Ret, K200, KQ150)]
.rd <- .rd[is.finite(Close) & Close > 0]
setorder(.rd, Ticker, Date)

# (Date,Ticker) 중복 방어. 중복이 남으면 by-Ticker 누적합이 같은 날을 두 번 더해
#   창 길이가 조용히 늘어난다 — 에러 없이 신호가 바뀌는 침묵 실패다.
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[RP_AUTO_2608_14014] (Date,Ticker) 중복 %d행 — 첫 행만 남긴다\n", .ndup))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}

.bm <- unique(BM_DT[, .(Date, BM_Ret)], by = "Date")
if (!inherits(.bm$Date, "Date")) .bm[, Date := as.Date(Date)]
# 갱신 조인(merge 아님) — 8M행 패널의 복사본을 만들지 않는다. 미매칭일은 NA 로 남는다.
.rd[, BM_Ret := NA_real_]
.rd[.bm, BM_Ret := i.BM_Ret, on = "Date"]
setorder(.rd, Ticker, Date)           # ★모든 by-Ticker 롤링 전에 정렬을 다시 못박는다
.nbm <- .rd[!is.finite(BM_Ret), .N]
cat(sprintf("[RP_AUTO_2608_14014] 패널 %d행 · %d종 · %s~%s | BM 결측 %d행(%.3f%%)\n",
            nrow(.rd), uniqueN(.rd$Ticker),
            as.character(min(.rd$Date)), as.character(max(.rd$Date)),
            .nbm, 100 * .nbm / nrow(.rd)))

# =============================================================================
# 2. 거래대금 (C10 — 전부 t−1) : 유동성 하한 + 사이즈 버킷 축
# =============================================================================
.rd[, TV   := Close * Vol]
.rd[, TVOK := as.numeric(is.finite(TV) & TV > 0)]
.rd[!is.finite(TV), TV := 0]

.rd[, ADV20 := { s <- .rsum(TV, .LIQWIN); n <- .rsum(TVOK, .LIQWIN)
                 fifelse(n >= .LIQWIN, s / n, NA_real_) }, by = Ticker]
.rd[, ADV252 := { s <- .rsum(TV, .ADV_WIN); n <- .rsum(TVOK, .ADV_WIN)
                  fifelse(n >= .ADV_MIN, s / n, NA_real_) }, by = Ticker]
.rd[, ADV20_L1  := shift(ADV20,  1L), by = Ticker]
.rd[, ADV252_L1 := shift(ADV252, 1L), by = Ticker]
.rd[, c("ADV20", "ADV252", "TV", "TVOK", "Close", "Vol") := NULL]
gc(verbose = FALSE)

# =============================================================================
# 3. (K1) β = 252일 롤링 OLS · 최소 126관측 · 결측 = 1 → AR_t = r_t − β·r_m,t
# =============================================================================
# OLS 기울기를 후방 누적합 5개로 닫는다(창당 재적합 없이 O(N)):
#   β = [Σxy − ΣxΣy/n] / [Σyy − ΣyΣy/n],  x = 종목수익, y = 지수수익, 창 = 252행.
# ★쌍(pair)이 유효한 날만 센다 — 결측을 0 으로 채우고 카운트를 따로 들고 간다.
.rd[, PAIR := as.numeric(is.finite(Ret) & is.finite(BM_Ret))]
.rd[, RX := fifelse(PAIR > 0, Ret,    0)]
.rd[, RY := fifelse(PAIR > 0, BM_Ret, 0)]

.rd[, BETA := {
      n   <- .rsum(PAIR,    .BETA_WIN)
      sx  <- .rsum(RX,      .BETA_WIN)
      sy  <- .rsum(RY,      .BETA_WIN)
      sxy <- .rsum(RX * RY, .BETA_WIN)
      syy <- .rsum(RY * RY, .BETA_WIN)
      den <- syy - sy * sy / n
      b   <- (sxy - sx * sy / n) / den
      # 관측 수 미달 · 분모 퇴화(지수 무변동 창) = 값이 아니라 미측정 → NA (다음 줄에서 1)
      bad <- !(n >= .BETA_MIN) | !is.finite(den) | den <= 0 | !is.finite(b)
      bad[is.na(bad)] <- TRUE     # 판정 불능도 미측정 — 색인에 NA 를 남기지 않는다
      b[bad] <- NA_real_
      b
    }, by = Ticker]

# ★1일 지연. 원문은 "as of day t" 지만 그러면 AR_t 가 자기 자신을 포함해 적합된 β 를 쓴다.
#   창이 252일이라 값 차이는 O(1/252) 이고, 대신 C2(same-day 순환)가 구조적으로 소거된다.
.rd[, BETA_L1 := shift(BETA, 1L), by = Ticker]
.nbmiss <- .rd[PAIR > 0 & !is.finite(BETA_L1), .N]
.rd[!is.finite(BETA_L1), BETA_L1 := .BETA_MISS]     # (K1) "missing betas set to 1"

.rd[, AR := fifelse(PAIR > 0, Ret - BETA_L1 * BM_Ret, 0)]
.rd[, c("Ret", "BM_Ret", "RX", "RY", "BETA", "BETA_L1") := NULL]
gc(verbose = FALSE)
cat(sprintf("[RP_AUTO_2608_14014] β 산출 완료 | 결측 β(=1 대입) %d행 (%.2f%% of pair-valid)\n",
            .nbmiss, 100 * .nbmiss / max(1L, .rd[PAIR > 0, .N])))

# =============================================================================
# 4. (K2·K3) 신호창 CAR(−5..0) = 거래일 오프셋 [t−10, t−5] 의 누적 AR
# =============================================================================
#   rsum(AR, 11)[t] = Σ_{t−10..t} ,  rsum(AR, 5)[t] = Σ_{t−4..t}
#   차 = Σ_{t−10..t−5} = 정확히 6거래일 = 논문 −5..0.  버려지는 [t−4,t] = 논문 +1..+5.
.rd[, RIDX   := seq_len(.N), by = Ticker]
.rd[, GAP11  := as.numeric(Date - shift(Date, .K_LONG - 1L)), by = Ticker]
.rd[, CARPRE := .rsum(AR, .K_LONG) - .rsum(AR, .K_SHORT),     by = Ticker]
.rd[, NPRE   := .rsum(PAIR, .K_LONG) - .rsum(PAIR, .K_SHORT), by = Ticker]
.rd[, c("AR", "PAIR") := NULL]
gc(verbose = FALSE)

# =============================================================================
# 5. 시그널일(월말) · 적격 유니버스 (C6 · C10)
# =============================================================================
.rd[, MI := year(Date) * 12L + month(Date)]
.mend <- .rd[, .(SigDate = max(Date)), by = MI]
setorder(.mend, MI)
.SIGD <- .mend[SigDate >= .SIG_FROM]$SigDate
if (!length(.SIGD))
  stop("[RP_AUTO_2608_14014] 시그널일 0건 — RAWDATA 날짜 범위 확인")

.EL <- .rd[Date %in% .SIGD][
           (K200 | KQ150) &
           is.finite(ADV20_L1) & ADV20_L1 >= .LIQ &
           RIDX >= .K_LONG &
           is.finite(GAP11)  & GAP11 <= .GAPMAX &
           NPRE  >= .PRE_LEN &                    # 신호창 6일이 전부 유효한 종목만
           is.finite(CARPRE),
           .(SigDate = Date, Ticker, CARPRE, ADV252_L1)]
if (!nrow(.EL))
  stop("[RP_AUTO_2608_14014] 적격 종목 0건 — 멤버십/유동성/신호창 필터 확인")

# =============================================================================
# 6. (K6) 사이즈 버킷 — 거래대금 3분위, **매년**, 앵커 = 전년 마지막 거래일(PIT)
# =============================================================================
.EL[, YR := year(SigDate)]
.yrlast <- .rd[, .(D = max(Date)), by = .(Y = year(Date))]
.anch   <- .yrlast[, .(YR = Y + 1L, ANCH = D)]          # 연도 Y 의 앵커 = Y−1 마지막 거래일
.EL <- merge(.EL, .anch, by = "YR", all.x = TRUE, sort = FALSE)

# 앵커일 당시 멤버십·거래대금 (현재 명부 역주입 없음 — C6)
.AN <- .rd[Date %in% unique(.EL$ANCH) & (K200 | KQ150) & is.finite(ADV252_L1),
           .(ANCH = Date, Ticker, ADV_A = ADV252_L1)]
.BP <- .AN[, { q <- quantile(ADV_A, probs = seq_len(.NBUCKET - 1L) / .NBUCKET,
                             na.rm = TRUE, names = FALSE)
               .(B1 = q[1], B2 = q[2], N_ANCH = .N) }, by = ANCH]

.EL <- merge(.EL, .AN, by = c("ANCH", "Ticker"), all.x = TRUE, sort = FALSE)
.EL <- merge(.EL, .BP, by = "ANCH", all.x = TRUE, sort = FALSE)
# 앵커에 값이 없는 종목(그 해 신규 편입/상장)만 자기 t−1 ADV252 를 같은 분위점에 댄다.
.EL[, ADV_USE := fifelse(is.finite(ADV_A), ADV_A, ADV252_L1)]
.nfb <- .EL[!is.finite(ADV_A) & is.finite(ADV252_L1), .N]

.EL[, BUCKET := NA_integer_]
.EL[is.finite(ADV_USE) & is.finite(B1) & is.finite(B2) &
    is.finite(N_ANCH) & N_ANCH >= .MINANCH,
    BUCKET := fifelse(ADV_USE <= B1, 1L, fifelse(ADV_USE <= B2, 2L, 3L))]

# 셀이 너무 작으면 버킷평균이 자기 자신에 수렴해 ADJ≡0('중립')으로 위장한다 → 미측정 처리.
.EL[, NB := .N, by = .(SigDate, BUCKET)]
.EL[is.na(BUCKET) | NB < .MINBUCKET, BUCKET := NA_integer_]

# =============================================================================
# 7. (K5) 기저 차감  ADJ = CAR(−5..0) − b_{k,t}   → (K4) 페이드  Score = −ADJ
# =============================================================================
.EL[, BASE_K   := mean(CARPRE), by = .(SigDate, BUCKET)]   # b_{k,w} (버킷 횡단면)
.EL[, BASE_ALL := mean(CARPRE), by = SigDate]              # 버킷 미측정 시 폴백
.EL[, BASE := fifelse(is.na(BUCKET), BASE_ALL, BASE_K)]
.EL[, ADJ  := CARPRE - BASE]

# (K4) "positive → short, negative → long". 롱온리 축이므로 롱 다리만:
#   조정 런업이 가장 음(−)인 종목이 최고 점수.
.EL[, Score := -ADJ]

# 횡단면이 고정 축 종목수에 못 미치는 달은 '선택'이 성립하지 않는다 → 그 달 제외.
.EL[, NCS := .N, by = SigDate]
.EL <- .EL[NCS >= .NMIN & is.finite(Score)]
if (!nrow(.EL))
  stop("[RP_AUTO_2608_14014] 최소 횡단면 미달 — 유니버스/신호창 확인")

FACTORS <- .EL[, .(Date = SigDate, Ticker, Score)]
setorder(FACTORS, Date, -Score)

# =============================================================================
# 8. 진단
# =============================================================================
.bkdist <- .EL[, .N, by = BUCKET][order(BUCKET)]
.nmonth <- uniqueN(FACTORS$Date)
.ncs    <- .EL[, .N, by = SigDate]$N
cat(sprintf(paste0(
  "[RP_AUTO_2608_14014] adapted: 논문 이벤트시간을 달력에 정렬(t ≡ day +5) →\n",
  "  신호창 −5..0 = 거래일 [t−10, t−5] 6일 누적 AR(β 252d·min126·결측1, 1일지연)\n",
  "  − 사이즈버킷(거래대금 3분위·전년말 앵커) 횡단면 평균 b_k  → 페이드로 부호 반전.\n",
  "  월 %d개 (%s ~ %s) · 횡단면 중앙 %.0f (최소 %d / 최대 %d) · FACTORS %d행\n",
  "  버킷 분포 1/2/3/NA = %s | 앵커 폴백(신규) %d행\n",
  "  ★러너 호출: portfolio_spec=list(construction=\"top_n_long\", weighting=\"ew\",\n",
  "     rebalance=\"monthly\", top_n=25, n_long=25) · commission_paper=NULL(논문 gross)\n"),
  .nmonth, as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date)),
  median(.ncs), min(.ncs), max(.ncs), nrow(FACTORS),
  paste(sprintf("%s:%d", ifelse(is.na(.bkdist$BUCKET), "NA", as.character(.bkdist$BUCKET)),
                .bkdist$N), collapse = " / "),
  .nfb))
