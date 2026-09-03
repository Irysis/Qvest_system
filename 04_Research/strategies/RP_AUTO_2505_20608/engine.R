# =============================================================================
# engine.R — RP_AUTO_2505_20608
# "Replication of Reference-Dependent Preferences and the Risk-Return Trade-Off
#  in the Chinese Market"   arXiv:2505.20608   https://arxiv.org/abs/2505.20608
#  (원논문 = Wang, Yan, Yu (2017), "Reference-dependent preferences and the
#   risk-return trade-off". 이 논문은 그 미국 결과의 중국 A주 리플리케이션이다.)
#
# ★fidelity = ADAPTED (기전 이식). 정본 = FIDELITY.json — 이 주석은 사본이다.
#
# ===== 왜 faithful 이 아닌가 (판정 순서 1 → 2 → 3) =====
# 데이터는 전부 있다(§데이터 대응표) → ABORT 사유 없음. 신호식·정렬·비중·리밸은
# 논문 그대로다. 그런데도 faithful 이라 부르지 않는 이유는 넷이고, 그중 (A1) 이 본질이다.
#  (A1) **논문의 산출 형태가 전략이 아니다**. 논문은 5×5 이중정렬 표(25개 포트폴리오
#       평균수익)와 Fama-MacBeth 계수를 낼 뿐, "explicit long-short positions" 을
#       형성하지 않는다. 우리는 등급을 받을 **하나의 북**을 내야 하므로, 논문이 만든
#       그 25칸 중 **네 모서리**를 논문의 중심 추정량 β₃(PROXY×CGO)가 가리키는 방식으로
#       조립한다(§조립). 칸도 비중도 논문 것이고, 조립만 우리가 한다.
#  (A2) **위험 대리변수 5종 중 1종만 쓴다**. 논문 = Beta · RETVOL · IVOL · 1/AGE ·
#       CFVOL. 엔진 하나는 북 하나를 내므로 **Beta**(논문의 선두 대리변수이자
#       'risk-return trade-off' 의 정본 위험축, 이중정렬 표의 인용 수치가 이것)만 쓴다.
#       5종 합성은 논문이 하지 않는 조작이라 하지 않았다.
#  (A3) **유니버스 치환(고정 축)**: 중국 A주 1,928종 → K200∪KQ150(PIT 시변) +
#       adv20(t−1) ≥ 2e8 + 2005-01-01~. 논문의 중국 특수 스크린(ST/blacklist ·
#       거래정지 · 5위안 미만 · 상장 10년 미만 제외)은 유니버스 정의 자체가 대체한다.
#  (A4) **주간 회전율 V 의 정의역 절단**: 아래 (K1) 참조. 값 선택이 아니라 식의 정의역이다.
#
# ===== 데이터 대응표 (지어낸 것 0개 — 전부 보유 패널) =====
#   논문 P_t (weekly closing price)          → RAWDATA$Close 의 주간 마지막 거래일 값.
#       ★Close = 수정주가 원장(registry_migrate_ast_v11.py:17 "rawdata/price A1
#         수정주가 재작성=restatement true"). 분할·증자가 이미 반영돼 있어 5년 전
#         가격과 직접 비교 가능하다 — CGO 가 요구하는 바로 그 성질이다.
#   논문 V_t ("trading volume divided by shares outstanding")
#       → Vol × Close / Size. Size = 시가총액이므로 shares = Size/Close 이고
#         Vol/shares = Vol·Close/Size. ★이 저장소의 정본 회전율과 **같은 식**이다
#         (compute_liquidity.R:38 est_shares := Size/Close · :63 turnover := Vol/est_shares).
#         대리변수를 만든 게 아니라 이미 있는 정의를 쓴 것이다.
#   논문 CAPM 시장수익                        → BM_DT$BM_Ret (KOSPI200).
#   논문 value-weighted                       → RAWDATA$Size (시그널일 시총).
#
# ===== 무엇을 남기는가 (kept — 논문의 식·창·정렬 그대로) =====
#  (K1) **참조가격(원문 그대로)**: "At each week t, the reference price for each stock
#       is defined as: RP_t = (1/k) Σ(V_{t-n} ∏(1-V_{t-n+τ})) P_{t-n}" (n=1..T,
#       T=260 weeks (5 years), k normalizes weights to sum to one).
#       → 엔진은 이걸 **정확히 그 260주 절단합**으로 계산한다. 근사·무한창 대체 없음.
#       구현은 등가 재귀(§재귀)라 O(1)/주 이고 부동소수 안정적이다.
#       ★V 는 [0,1] 로 절단한다. (1−V) 는 "그 주에 손바뀜하지 않고 남은 지분" 이라
#       음수가 될 수 없다 — V>1 이면 곱이 부호를 뒤집어 식 자체가 무의미해진다.
#       이건 튜닝 값이 아니라 **식의 정의역**이고, V=1 은 "그 주에 전량 손바뀜 ⇒
#       그 이전 가격은 남지 않는다" 라는 식 자신의 극한이다.
#  (K2) **CGO(원문 그대로)**: "CGO_t = (P_{t-1} - RP_t) / P_{t-1}".
#       분자·분모의 P_{t-1} 과 RP_t 의 최신항이 같은 주(t−1)다 — 그대로 유지.
#  (K3) **주간→월간 변환(원문 그대로)**: "converts weekly values to monthly by
#       selecting the last-week CGO within each month".
#  (K4) **위험 대리변수(원문 그대로)**: Beta = "rolling 5-year regression of the CAPM
#       model". 5년 = **월간 60개월** 로 읽는다 — 같은 표의 RETVOL 이 "standard
#       deviation of the previous 5-year **monthly** returns" 로 정의돼 있어 이 논문의
#       '5-year' 가 월간 격자를 뜻한다는 것이 논문 내부에서 확정된다.
#  (K5) **종속 이중정렬(원문 그대로)**: "At the beginning of each month, we divide all
#       firms in our sample into five groups based on lagged CGO, and within each of
#       the CGO groups, we further divide firms into five portfolios based on various
#       lagged risk proxies. This results in a total of 25 portfolios."
#       → 5분위(CGO) × 그 안에서 다시 5분위(Beta) = 25칸. 독립정렬 아님.
#  (K6) **비중·보유(원문 그대로)**: "held for one month, value-weighted excess returns
#       calculated" → 칸 내부 **시총가중**, **월간 리밸**, **1개월 보유**.
#       ★종목수 상한을 걸지 않는다 — 논문은 칸에 든 전 종목을 담는다.
#  (K7) **논문의 자기반증까지 남긴다**: 이 논문은 중국에서 원논문이 **복제되지 않았다**고
#       보고한다 — 이중정렬 P5−P1 이 High-CGO 0.027%(t=0.05) · Low-CGO 0.913%(t=1.92),
#       FM 단독 CGO 계수 0.0023(t=0.89) vs 원논문 1.184(t=7.48), 그리고 **교차항
#       PROXY×CGO 가 대리변수 전반에서 음(−)** 으로 원논문의 유의한 양(+)과 반대다.
#       → 이 엔진은 **원논문 가설의 방향**(β₃>0)으로 북을 세운다. 한국에서 음이 나오면
#       그건 구현 실패가 아니라 중국 결과의 한국 표본외 확인이다. 중국에서 유의했던
#       쪽(Low-CGO 스프레드)을 골라 성과를 만드는 선택은 하지 않았다 — 그건 결과를
#       보고 고르는 것이고, 이 논문이 보고한 결과는 애초에 '복제 실패' 다.
#
# ===== 조립 (이식의 유일한 조작) =====
#   원논문 가설 = "negative risk-return relationships among low-CGO firms and positive
#   relationships among high-CGO firms", 교차항은 "always significant and positive".
#   FM 식(원문): R = α + β₁CGO + β₂PROXY + β₃PROXY×CGO + β₄PROXY×MOM(-12,-1)
#                  + β₅MOM(-1,0) + β₆MOM(-12,-1) + β₇TURNOVER + ε
#   β₃ 를 포트폴리오로 옮기면 25칸의 **네 모서리 이중차분(DiD)** 이다:
#       LONG  = (CGO Q5 ∩ Beta Q5)  +  (CGO Q1 ∩ Beta Q1)
#       SHORT = (CGO Q5 ∩ Beta Q1)  +  (CGO Q1 ∩ Beta Q5)
#       ⇒ 수익 = [High-CGO 의 P5−P1] − [Low-CGO 의 P5−P1] = 논문 표의 두 스프레드 차.
#   ★왜 단일 스프레드(예: High-CGO P5−P1)가 아닌가: 그 하나는 **무조건부 베타 프리미엄과
#     교차항이 섞인 양**이다. 논문이 분리해 재는 대상은 교차항이고, DiD 가 무조건부
#     베타 프리미엄을 차분으로 소거한다. 또한 다섯 CGO 분위 중 하나를 고르는 자의성이
#     없다 — 양 끝을 다 쓴다.
#   ★레버리지는 만들지 않는다: 롱 Σw=+1 · 숏 Σw=−1(이 저장소 롱숏 표준, 총 익스포저 2).
#     두 스프레드를 각각 0.5 씩 담아 합이 단위가 되게 했다. 논문은 스프레드 차를 수익률
#     차로만 보고하고 레버리지 규약을 주지 않으므로, 규약을 지어내지 않고 표준을 쓴다.
#
# ===== 재귀 (260주 절단합의 정확한 등가형 — 근사 아님) =====
#   N_j ← V_j·P_j + (1−V_j)·N_{j−1},   K_j ← V_j + (1−V_j)·K_{j−1},   N=K=0 에서 출발해
#   창의 **가장 오래된 주부터 최신 주(=t−1)까지** 260번 돌리면
#     P_{t−1} 의 가중치 = V_{t−1}
#     P_{t−1−m} 의 가중치 = V_{t−1−m}(1−V_{t−m})···(1−V_{t−1})  = 논문의 V∏(1−V)
#   그리고 K = Σ(가중치) = 논문의 정규화 상수 k 다. RP = N/K.
#   ★누적곱 c=∏(1−V) 을 명시적으로 들고 다니는 구현(=비율형)은 260주 뒤 c 가 언더플로해
#     0 으로 죽는다. 이 재귀는 모든 항이 [0,1] 볼록결합이라 그 실패 모드가 없다.
#   ★K 는 덤으로 진단이 된다: 1−K = ∏(1−V) = **260주 절단으로 버려진 가중치 비중**.
#     논문이 k 로 재정규화하므로 이건 논문 식의 일부지 우리 오차가 아니다 — 값을 찍는다.
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) =====
#  ▸ 구조 경계 ①: 시계열 연산은 **후방 누적합 `.rsum()`** 과 **오래된→최신 단방향 재귀**
#      뿐이다. `.rsum(x,k)[i] = Σ_{j=max(1,i−k+1)}^{i} x_j` 는 정의상 i 보다 큰 인덱스를
#      못 읽고, 재귀 루프의 상한은 앵커주 ia 로 고정돼 있다. shift 는 전부 양수(과거 방향).
#      shift(−n) · rev() · 미래 인덱싱 · future join 0건.
#  ▸ 구조 경계 ②: 횡단면 연산(분위 배정 · 시총가중)은 전부 `by = SigDate` 또는
#      `by = .(SigDate, ...)` 안에서만 돈다. 여러 날짜를 가로지르는 통계가 0건이다
#      (전 표본 quantile()·scale()·mean() 미사용 — 분위는 **그 날짜 내부 순위**로 낸다).
#  ▸ 구조 경계 ③: 주간 격자의 앵커는 **week_end ≤ 시그널일 d** 인 마지막 주다. 즉 d 를
#      포함하는 주가 d 이후로 더 이어지면 그 주는 통째로 버리고 직전 완결주를 쓴다.
#      쓰는 데이터는 전부 날짜 ≤ d 이고, 이 규칙은 신호를 **더 낡게만** 만들지 절대
#      더 새롭게 만들지 않는다(보수 방향 단조).
#  C1  : 전 표본 통계 0건. RP·Beta·ADV 전부 후방 고정창, 분위점은 단일 날짜 횡단면 순위.
#  C2  : same-day 순환 없음. CGO 의 최신 입력 = 완결주 종가(≤ d), Beta 의 최신 입력 =
#        시그널월 m 의 월수익(d 에 완결). 보유는 m+1 첫 거래일부터다.
#  C3  : 집계창 ∩ 보유창 = ∅. RP 창 = [주 ia−259, ia](전부 ≤ d), Beta 창 = 월 [m−59, m],
#        보유월 = m+1.
#  C4  : 재무제표 미사용(가격·거래량·시총·벤치마크뿐). 공시시차 이슈 자체가 없다.
#  C5  : 오버레이 없음(S0/S1 오버레이 금지 준수).
#  C6  : 유니버스 = 각 시그널일의 K200/KQ150 멤버십(PIT 시변). 최종 명부 역주입 없음.
#        ★단 하나의 전표본 조회 = 주간 행렬의 열 집합을 "한 번이라도 K200/KQ150 이었던
#        종목" 으로 제한한 것. 이건 **모든 시그널일 적격집합의 진부분집합이 아니라
#        진상위집합**이다(d 에 멤버면 ever-멤버이므로) — 어떤 날의 어떤 판정도 바뀌지
#        않고, 계산량만 준다. 값에 영향이 없다는 뜻에서 C6 무관.
#  C7  : 자동탐지 idiom 0건.
#  C8  : FM weight 미사용.        C9 : DD/VT 미사용.
#  C10 : 유동성 = 20일 평균 거래대금의 by-Ticker shift(1) = **t−1** 값 ≥ 2e8.
#  C11 : 외부 매크로 시계열 미사용. BM_DT = 동일 시장 일별 지수(보고시차 없음).
#  C13 : Factor DB 미소비 → 정렬 대상 없음. 부호는 **원논문 가설**(β₃>0)에서 사전
#        (a priori)으로 나온다 — 측정된 IC 부호를 보고 정하지 않았다.
#  C15 : Factor DB parquet 직접 load 0건.
#  ★rawdata 의 Market 열 미사용(KOSDAQ 0건 날조 — 기지의 패널 결함).
#  ★기지의 패널 결함 고지: KQ150 멤버십은 2015-07 이전이 백필 투영이라 퇴출 기록이 0이다.
#    이 라운드가 만든 문제가 아니고 유니버스 패널 전역 사안이지만, 이중정렬 횡단면의
#    코스닥 절반 구성이 그 영향을 받는다 — FIDELITY.json 에 caveat 로 남긴다.
#
# ===== 산출 =====
#   PORTFOLIO(Date, Ticker, Weight, Leg) ← **거래되는 북. 이게 논문 비중이다.**
#     러너 호출: portfolio_spec = list(construction="engine_direct")
#     ★engine_direct 가 아니면 러너가 숏 다리를 버리고 롱온리 top-N 으로 재구성한다.
#       그러면 DiD 가 사라져 논문과 비교 자체가 성립하지 않는다.
#   FACTORS(Date, Ticker, Score)         ← **진단 전용**(러너의 IC·FF3/FF5/Carhart·FMB
#     가 서도록). Score = 논문 β₃ 회귀항 PROXY×CGO 를 이중정렬 순위공간으로 옮긴 것 =
#     ((QC−3)/2)·((QB−3)/2). 최고점 = 롱 모서리, 최저점 = 숏 모서리로 북과 정합.
#     ★러너는 PORTFOLIO 가 있으면 construction 을 engine_direct 로 자동 판정하므로
#       (run_paper_replication.R:225) FACTORS 병행 산출이 북을 바꾸지 않는다.
#   commission_paper = NULL — 논문에 거래비용 명시가 없다(gross). 등급은 15bps 판.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

# 난수 미사용(결정론적 엔진)이지만 재현성 선언 고정.
set.seed(25052060L)

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(exists("BM_DT"),   is.data.table(BM_DT))
stopifnot(all(c("Date", "Ticker", "Close", "Vol", "Size", "Ret", "K200", "KQ150")
              %in% names(RAWDATA)))
stopifnot(all(c("Date", "BM_Ret") %in% names(BM_DT)))

# =============================================================================
# 상수 — 논문에서 온 것 / 우리 고정 축에서 온 것 / 유효성 가드
# =============================================================================
# ▸ 논문에서 온 것
.T_WEEKS  <- 260L    # "T=260 weeks (5-year lookback)"
.BETA_MON <- 60L     # "rolling 5-year regression of the CAPM model" (월간 격자 — K4)
.NQ       <- 5L      # "divide ... into five groups" × "five portfolios" = 25 칸

# ▸ 우리 고정 축
.LIQ        <- 2e8                    # adv20(t−1) 하한 (KRW)
.LIQWIN     <- 20L
.SIG_FROM   <- as.Date("2005-01-01")
.PANEL_FROM <- as.Date("1998-01-01")  # 2005-01 시그널의 260주 창(≈2000-01~)과
                                      #   60개월 Beta 창(2000-01~)을 모두 덮는 여유.
.WK_ANCHOR  <- as.Date("1997-12-29")  # 월요일. 주 격자를 연속 정수로 만들기 위한 기준점
                                      #   (ISO 연말·연초 경계 예외를 만들지 않는다).

# ▸ 유효성 가드 (모수가 아니다 — '포트폴리오'와 '한 종목 베팅'을 가르는 선)
.MIN_CS   <- 25L * 2L  # 5×5 종속정렬이 성립할 최소 횡단면. 25칸 × 2명 = 50.
                       #   ★논문 5×5 에서 파생된 수이지 고른 수가 아니다.
.MIN_CELL <- 3L        # 거래되는 네 모서리 칸의 최소 인원. 2명 이하의 시총가중 칸은
                       #   사실상 단일종목 베팅이라 '포트폴리오'가 아니다.
                       #   (논문 칸 평균 인원 = 1,928/25 ≈ 77.)

# 후방 누적합. `.rsum(x,k)[i] = Σ_{j=max(1,i−k+1)}^{i} x_j`.
#   ★i 보다 큰 인덱스를 읽는 경로가 구조적으로 존재하지 않는다(PIT 경계 ①).
#   ★선행 부분창을 NA 로 버리지 않고 expanding 으로 준다 — 관측 수 조건은 별도 카운트로.
.rsum <- function(x, k) {
  n <- length(x)
  if (n == 0L) return(numeric(0))
  cs <- c(0, cumsum(x))
  i  <- seq_len(n)
  cs[i + 1L] - cs[pmax(0L, i - k) + 1L]
}

# =============================================================================
# 1. 일별 패널 (C6 — ever-멤버 제한은 매 시그널일 적격집합의 상위집합. 판정 불변)
# =============================================================================
.evertk <- unique(RAWDATA[K200 == TRUE | KQ150 == TRUE, Ticker])
.rd <- RAWDATA[Date >= .PANEL_FROM & Ticker %in% .evertk,
               .(Date, Ticker, Close, Vol, Size, Ret, K200, KQ150)]
.rd <- .rd[is.finite(Close) & Close > 0]
setorder(.rd, Ticker, Date)

# (Date,Ticker) 중복 방어. 중복이 남으면 by-Ticker 누적합이 같은 날을 두 번 더해
#   창 길이가 조용히 늘어난다 — 에러 없이 신호가 바뀌는 침묵 실패다.
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[RP_AUTO_2505_20608] (Date,Ticker) 중복 %d행 — 첫 행만 남긴다\n", .ndup))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}
if (!nrow(.rd)) stop("[RP_AUTO_2505_20608] 패널 0행 — RAWDATA 범위/멤버십 확인")

cat(sprintf("[RP_AUTO_2505_20608] 패널 %d행 · %d종 · %s ~ %s\n",
            nrow(.rd), uniqueN(.rd$Ticker),
            as.character(min(.rd$Date)), as.character(max(.rd$Date))))

# =============================================================================
# 2. 유동성 (C10 — t−1) : adv20 은 **shift(1)** 로만 소비한다
# =============================================================================
.rd[, TV   := Close * Vol]
.rd[, TVOK := as.numeric(is.finite(TV) & TV > 0)]
.rd[!is.finite(TV), TV := 0]
.rd[, ADV20 := { s <- .rsum(TV, .LIQWIN); n <- .rsum(TVOK, .LIQWIN)
                 fifelse(n >= .LIQWIN, s / n, NA_real_) }, by = Ticker]
.rd[, ADV20_L1 := shift(ADV20, 1L), by = Ticker]     # ★t−1 (C10)
.rd[, ADV20 := NULL]

# =============================================================================
# 3. 주간 격자 — P(주 종가) · V(주 회전율)  [(K1) 의 입력]
# =============================================================================
# 주 인덱스 = 고정 월요일 기준 연속 정수. 종목별로 같은 격자를 쓴다.
.rd[, WK := as.integer((as.numeric(Date) - as.numeric(.WK_ANCHOR)) %/% 7L)]

# 일별 회전율 = Vol / (Size/Close) = Vol·Close/Size  (compute_liquidity.R 정본과 동일 식)
.rd[, TOD := 0]
.rd[is.finite(Vol) & Vol > 0 & is.finite(Size) & Size > 0, TOD := TV / Size]

# ★`Close[.N]` 로 쓴다 — 러너는 엔진 source 전에 xts 를 붙이고, `last()` 는 그때
#   data.table::last 가 아니라 xts::last 로 잡힐 수 있다(무해해 보이는 마스킹이
#   조용히 다른 값을 내는 계통). 정렬은 §1 setorder(Ticker, Date) 가 보장한다.
.wk <- .rd[, .(WEnd = max(Date), P = Close[.N], V = sum(TOD)), by = .(Ticker, WK)]
# ★V 절단은 식의 정의역이다 — (1−V) 는 '손바뀜하지 않고 남은 지분' 이라 음수 불가.
.wk[, V := pmin(pmax(V, 0), 1)]

# 시장 전체의 주별 마지막 거래일 (앵커 판정용 — 구조 경계 ③)
.wend <- .rd[, .(WEnd = max(Date)), by = WK]
setorder(.wend, WK)

# 조밀 격자로 재색인: 거래가 하나도 없는 주가 있어도 260주 창이 조용히 늘어나지 않게.
.wall <- seq.int(min(.wk$WK), max(.wk$WK))
.dP <- dcast(.wk, WK ~ Ticker, value.var = "P");  setkey(.dP, WK); .dP <- .dP[list(.wall)]
.dV <- dcast(.wk, WK ~ Ticker, value.var = "V");  setkey(.dV, WK); .dV <- .dV[list(.wall)]
stopifnot(identical(names(.dP), names(.dV)))

# ★행=종목 · 열=주 로 전치한다. 재귀가 주 단위로 260번 돌므로 열 추출이 연속 메모리가
#   되어야 한다(R 은 열 우선). 값은 바뀌지 않고 접근 패턴만 바뀐다.
.Pm <- t(as.matrix(.dP[, -1L, with = FALSE]))
.Vm <- t(as.matrix(.dV[, -1L, with = FALSE]))
.Vm[!is.finite(.Vm)] <- 0                 # 무거래 주 = 회전율 0 (가중치를 그대로 통과시킨다)
.TKS <- rownames(.Pm)
.NT  <- length(.TKS)
rm(.dP, .dV); gc(verbose = FALSE)

# 종목별 최초 유효 주 인덱스 — 260주 이력 요건(논문 5년 lookback)의 판정 근거
.FIRSTW <- apply(.Pm, 1L, function(x) { w <- which(is.finite(x))
                                        if (length(w)) w[1L] else NA_integer_ })

cat(sprintf("[RP_AUTO_2505_20608] 주간 격자 %d주 × %d종 (%s ~ %s)\n",
            ncol(.Pm), .NT, as.character(min(.wend$WEnd)), as.character(max(.wend$WEnd))))

# =============================================================================
# 4. 시그널일(월말) → 앵커주 ia  (구조 경계 ③)
# =============================================================================
.rd[, MI := year(Date) * 12L + month(Date)]
.mend <- .rd[, .(SigDate = max(Date)), by = MI]
setorder(.mend, MI)
.SIG <- copy(.mend[SigDate >= .SIG_FROM])
if (!nrow(.SIG)) stop("[RP_AUTO_2505_20608] 시그널일 0건 — RAWDATA 날짜 범위 확인")

# week_end ≤ d 인 마지막 주. d 를 품은 주가 d 이후로 이어지면 그 주는 버린다.
.pos <- findInterval(as.numeric(.SIG$SigDate), as.numeric(.wend$WEnd))
.SIG[, ANCHWK := ifelse(.pos >= 1L, .wend$WK[pmax(.pos, 1L)], NA_integer_)]
.SIG[, IA := ANCHWK - min(.wall) + 1L]

# =============================================================================
# 5. (K1·K2·K3) RP 260주 절단합 → CGO — 앵커주마다 재귀를 완주한다
# =============================================================================
.cgo_list <- vector("list", nrow(.SIG))
for (s in seq_len(nrow(.SIG))) {
  ia <- .SIG$IA[s]
  if (is.na(ia) || ia < .T_WEEKS) next            # 260주 창이 격자 안에 안 들어오면 미측정
  j0 <- ia - .T_WEEKS + 1L

  N <- numeric(.NT); K <- numeric(.NT); NV <- integer(.NT)
  for (j in j0:ia) {                              # ★오래된 주 → 최신 주(=t−1) 단방향
    p <- .Pm[, j]; v <- .Vm[, j]
    bad <- !is.finite(p) | !is.finite(v)
    p[bad] <- 0; v[bad] <- 0
    N  <- v * p + (1 - v) * N                     # 논문 Σ V∏(1−V) P 의 등가 재귀
    K  <- v     + (1 - v) * K                     # 논문 정규화 상수 k
    NV <- NV + as.integer(!bad)
  }

  pl <- .Pm[, ia]                                 # 논문 P_{t−1} = 최신 완결주 종가
  rp <- N / K                                     # 논문 RP_t = (1/k) Σ ...
  ok <- is.finite(pl) & pl > 0 & is.finite(K) & K > 0 & is.finite(rp) &
        is.finite(.FIRSTW) & .FIRSTW <= j0        # 260주 이력 요건
  if (!any(ok)) next

  .cgo_list[[s]] <- data.table(
    SigDate = .SIG$SigDate[s], MI = .SIG$MI[s], Ticker = .TKS[ok],
    CGO     = (pl[ok] - rp[ok]) / pl[ok],         # (K2) 원문 식 그대로
    KMASS   = K[ok], NWK = NV[ok])
}
.CGO <- rbindlist(Filter(Negate(is.null), .cgo_list), use.names = TRUE)
if (!nrow(.CGO)) stop("[RP_AUTO_2505_20608] CGO 0행 — 260주 이력/주간 격자 확인")
rm(.cgo_list, .Pm, .Vm); gc(verbose = FALSE)

# =============================================================================
# 6. (K4) Beta = 5년(60개월) 롤링 CAPM — 시그널월 m 까지, 보유는 m+1
# =============================================================================
.bm <- unique(BM_DT[, .(Date, BM_Ret)], by = "Date")
if (!inherits(.bm$Date, "Date")) .bm[, Date := as.Date(Date)]
.bmm <- .bm[is.finite(BM_Ret), .(RB = prod(1 + BM_Ret) - 1),
            by = .(MI = year(Date) * 12L + month(Date))]

.mo <- .rd[is.finite(Ret), .(RM = prod(1 + Ret) - 1), by = .(Ticker, MI)]
.mo[.bmm, RB := i.RB, on = "MI"]
setorder(.mo, Ticker, MI)

# 창이 달력 60개월을 정확히 덮는지 — 상장 중단·거래정지로 월이 비면 '60개월 창'이 아니다.
.mo[, GAPM := MI - shift(MI, .BETA_MON - 1L), by = Ticker]
.mo[, PAIR := as.numeric(is.finite(RM) & is.finite(RB))]
.mo[, X := fifelse(PAIR > 0, RM, 0)]
.mo[, Y := fifelse(PAIR > 0, RB, 0)]

# OLS 기울기를 후방 누적합 5개로 닫는다(창당 재적합 없이 O(N)):
#   β = [Σxy − ΣxΣy/n] / [Σyy − ΣyΣy/n],  x = 종목 월수익, y = 지수 월수익, 창 = 60행.
.mo[, BETA := {
      n   <- .rsum(PAIR,  .BETA_MON)
      sx  <- .rsum(X,     .BETA_MON)
      sy  <- .rsum(Y,     .BETA_MON)
      sxy <- .rsum(X * Y, .BETA_MON)
      syy <- .rsum(Y * Y, .BETA_MON)
      den <- syy - sy * sy / n
      b   <- (sxy - sx * sy / n) / den
      # 관측 수 미달 · 분모 퇴화 = 값이 아니라 미측정 → NA
      bad <- !(n >= .BETA_MON) | !is.finite(den) | den <= 0 | !is.finite(b)
      bad[is.na(bad)] <- TRUE
      b[bad] <- NA_real_
      b
    }, by = Ticker]
.mo[!is.finite(GAPM) | GAPM != (.BETA_MON - 1L), BETA := NA_real_]

# =============================================================================
# 7. 적격 횡단면 (C6 멤버십 · C10 유동성 · 이력요건)
# =============================================================================
.SNAP <- .rd[Date %in% .SIG$SigDate,
             .(SigDate = Date, MI, Ticker, Size, K200, KQ150, ADV20_L1)]
.EL <- merge(.CGO, .SNAP, by = c("SigDate", "MI", "Ticker"), sort = FALSE)
.EL <- merge(.EL, .mo[, .(Ticker, MI, BETA)], by = c("Ticker", "MI"), sort = FALSE)
.EL <- .EL[(K200 | KQ150) &
           is.finite(ADV20_L1) & ADV20_L1 >= .LIQ &
           is.finite(CGO) & is.finite(BETA) & is.finite(Size) & Size > 0]
if (!nrow(.EL)) stop("[RP_AUTO_2505_20608] 적격 종목 0건 — 멤버십/유동성/CGO/Beta 확인")

.EL[, NCS := .N, by = SigDate]
.EL <- .EL[NCS >= .MIN_CS]
if (!nrow(.EL)) stop("[RP_AUTO_2505_20608] 최소 횡단면(5×5 종속정렬) 미달 — 유니버스 확인")

# =============================================================================
# 8. (K5) 종속 이중정렬 5×5 — 분위는 **그 날짜 내부 순위**로만 낸다 (구조 경계 ②)
# =============================================================================
# 1단: lagged CGO 5분위. 2단: 각 CGO 군 **안에서** lagged Beta 5분위 (독립정렬 아님).
#   ceiling(i·5/n) 은 i=1..n 에 대해 거의 균등한 5군을 준다. 동점은 Ticker 로 확정.
setorder(.EL, SigDate, CGO, Ticker)
.EL[, QC := as.integer(pmin(.NQ, ceiling(seq_len(.N) * .NQ / .N))), by = SigDate]
setorder(.EL, SigDate, QC, BETA, Ticker)
.EL[, QB := as.integer(pmin(.NQ, ceiling(seq_len(.N) * .NQ / .N))), by = .(SigDate, QC)]

# =============================================================================
# 9. (조립) 네 모서리 이중차분 — β₃(PROXY×CGO)의 포트폴리오 표현
# =============================================================================
.CELL <- .EL[(QC == .NQ & QB == .NQ) | (QC == .NQ & QB == 1L) |
             (QC == 1L  & QB == .NQ) | (QC == 1L  & QB == 1L)]
.CELL[, CID  := QC * 10L + QB]
# 원논문 가설: high-CGO 에서 위험-수익 양(+), low-CGO 에서 음(−) ⇒ 교차항 β₃ > 0.
.CELL[, SIDE := fifelse((QC == .NQ & QB == .NQ) | (QC == 1L & QB == 1L), 1, -1)]
.CELL[, NCELL := .N, by = .(SigDate, CID)]

# 네 모서리가 모두 서고, 각 칸이 '한 종목 베팅'이 아닐 때만 그 달을 거래한다.
.chk  <- .CELL[, .(ncell = uniqueN(CID), nmin = min(NCELL)), by = SigDate]
.good <- .chk[ncell == 4L & nmin >= .MIN_CELL]$SigDate
.CELL <- .CELL[SigDate %in% .good]
if (!nrow(.CELL)) stop("[RP_AUTO_2505_20608] 네 모서리 칸을 모두 채운 달 0개")

# (K6) 칸 내부 시총가중. 두 롱 칸 0.5 씩 → Σw=+1 · 두 숏 칸 −0.5 씩 → Σw=−1.
#   ★레버리지를 만들지 않는다(총 익스포저 2 = 이 저장소 롱숏 표준).
.CELL[, WVW := Size / sum(Size), by = .(SigDate, CID)]
.CELL[, Weight := SIDE * 0.5 * WVW]

PORTFOLIO <- .CELL[, .(Date = SigDate, Ticker, Weight,
                       Leg = fifelse(Weight > 0, "long", "short"))]
setorder(PORTFOLIO, Date, -Weight)
# 네 칸은 서로소라 (Date,Ticker) 가 겹칠 수 없다 — 겹치면 정렬 로직이 깨진 것이다.
stopifnot(!any(duplicated(PORTFOLIO, by = c("Date", "Ticker"))))

# =============================================================================
# 10. FACTORS — 진단 전용. 논문 β₃ 회귀항을 이중정렬 순위공간으로 옮긴 것
# =============================================================================
.EL[, Score := ((QC - 3) / 2) * ((QB - 3) / 2)]
FACTORS <- .EL[SigDate %in% .good, .(Date = SigDate, Ticker, Score)]
setorder(FACTORS, Date, -Score)

# =============================================================================
# 11. 진단
# =============================================================================
.sidew <- PORTFOLIO[, .(gl = sum(Weight[Weight > 0]), gs = sum(Weight[Weight < 0]),
                        n = .N), by = Date]
.cs    <- .EL[SigDate %in% .good, .N, by = SigDate]$N
.cellN <- .CELL[, .(n = .N), by = .(Date = SigDate, CID)]$n
.trunc <- 1 - .CGO$KMASS
cat(sprintf(paste0(
  "[RP_AUTO_2505_20608] adapted: 논문 CGO(260주 회전율가중 참조가격) × Beta(60개월 CAPM)\n",
  "  종속 5×5 이중정렬 → 네 모서리 DiD(High-CGO 스프레드 − Low-CGO 스프레드), 칸내 시총가중.\n",
  "  월 %d개 (%s ~ %s) · 적격 횡단면 중앙 %.0f (최소 %d / 최대 %d)\n",
  "  모서리 칸 인원 중앙 %.0f (최소 %d) · 보유종목 중앙 %.0f (최소 %d / 최대 %d)\n",
  "  레그 총합 롱 %+.3f / 숏 %+.3f (전 리밸 동일해야 정상)\n",
  "  260주 절단 잔여가중 1−k: 중앙 %.2e / 최대 %.2e | 창내 유효주수 중앙 %.0f (최소 %d)\n",
  "  PORTFOLIO %d행 · FACTORS %d행\n",
  "  ★러너 호출: portfolio_spec=list(construction=\"engine_direct\") · commission_paper=NULL\n"),
  nrow(.sidew), as.character(min(PORTFOLIO$Date)), as.character(max(PORTFOLIO$Date)),
  median(.cs), min(.cs), max(.cs),
  median(.cellN), min(.cellN),
  median(.sidew$n), min(.sidew$n), max(.sidew$n),
  max(.sidew$gl), min(.sidew$gs),
  median(.trunc), max(.trunc), median(.CGO$NWK), min(.CGO$NWK),
  nrow(PORTFOLIO), nrow(FACTORS)))
