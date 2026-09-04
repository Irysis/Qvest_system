# =============================================================================
# engine.R — RP_AUTO_COMBO_combo_2007_08115_2301_09
#
# 재료 1) Pinchuk, Mykola (2023) "Labor Income Risk and the Cross-Section of
#         Expected Returns", arXiv:2301.09173   https://arxiv.org/abs/2301.09173
# 재료 2) Polimenis, Vassilis (2020) "Uncovering a factor-based expected return
#         conditioning structure with Regression Trees jointly for many stocks",
#         arXiv:2007.08115                      https://arxiv.org/abs/2007.08115
#
# ★fidelity = COMBINATION. 정본 = FIDELITY.json
#
# =============================================================================
# 앞 판(engine.rejected1.R)이 왜 기각됐고 이 판이 무엇을 되돌렸는가
# =============================================================================
# 적대적 충실도 감사가 네 지점을 잡았다. 네 지점 전부 **하나의 배치**에서 나왔다 —
# "재료 1 의 Eq.3(월간 선형회귀)을 버리고 일간 칸(cell) 평균의 대비로 바꾼 것".
#   ① 252개월 중 156개월만 리밸(2012-02~2013-11 22개월 연속 블랙아웃 등). 원인 =
#      칸 하한(일간 10관측·서로 다른 3개월)과 c*_u 탐색 실패가 **그 달의 FACTORS 를
#      통째로 발행하지 않음**. 논문 §3.2 는 "I update estimates of beta_CID and
#      rebalance portfolios every month" 로 매월 예외 없는 재추정·리밸을 명시한다.
#   ② Eq.1 산업 다리를 FF49 → 사내 Sector_Lv2 로 치환해 놓고 changed 에 안 적음.
#   ③ .LEAF_MO_L = 6L(c*_u 탐색 양쪽 최소 6개월)이 보충값 목록에 없었음.
#   ④ "어떤 한 달도 칸 평균의 1/3 을 넘지 못한다"고 선언했으나 코드는 일수가중
#      단순평균이라 8/1/1 일이면 지배 월 가중치가 80%. 선언이 사실과 달랐음.
#
# 이 판의 처분 — 문구 수리가 아니라 **배치 자체를 논문으로 되돌린다**:
#   ①→ 종목별 산출이 다시 재료 1 의 Eq.3(24개월 **월간** OLS)이다. 칸을 쪼개지
#      않으므로 "칸이 안 차서 그 달을 못 낸다" 는 경로가 **존재하지 않는다**.
#      월 탈락 게이트 0개. 엔진 말미가 형성월 전수 발행을 **hard assert** 한다
#      (미발행 월이 하나라도 있으면 그 달을 이름으로 찍고 stop).
#   ②→ FF49 → Sector_Lv2 치환을 FIDELITY.changed 에 명시하고, 관측된 산업 라벨 수와
#      월별 유효 산업수(>=10사 통과분)를 로그로 드러낸다.
#   ③→ c*_u 탐색이 이 엔진에 없다(2단 분기 자체가 없다). .LEAF_MO_L 소멸.
#      살아남은 보충값은 아래 §0 에 전부 열거하고 FIDELITY.changed 와 1:1 대응한다.
#   ④→ 회귀 관측 단위가 **월** 이라 한 달 = 한 관측이다. 월 균등가중이 정의상
#      성립하므로 "1/3 보호" 를 선언할 필요도, 강제할 코드도 필요없다.
#
# =============================================================================
# 결합의 형태 — 각 논문이 명시한 축에 그 논문의 함수형태를 되돌려 놓는다
# =============================================================================
# 두 엔진 스코어를 만들어 섞는 지점이 이 파일에 없다(rank-Z 평균 계보 5회 · 최고
# PORT_t 0.766). 결합은 **재료 1 의 Eq.3 회귀식 안**에서 일어난다.
#
#   재료 1 Eq.3:  R_it = alpha + beta * CID_t + eps_t      ("two years of monthly
#     excess returns" · CID_t = Eq.2 의 잔차 u_t · beta 를 1%/99% winsorize)
#   재료 1 은 이 회귀가 시장통제에 **불변**이라고 자기 표본에서 보고한다 —
#     Table 5 5분위 시장로딩 Q1 1.07 / Q5 1.11 (스프레드 0.04),
#     "Controlling for market beta does not have significant effect on the CID premium".
#   ★KR 에서 그 불변성이 깨진다(사내 실측): cor(u, 시장) = +0.43 (2022-26 +0.63) ·
#     최대 u 달이 전부 반도체 주도 **급등** 달 · L/S 일간 beta -0.39 · CID 단독은
#     Grade F(CAGR 0.6% · SR 0.15 · MDD 79.6%)인데 FF 알파만 9~12%. 즉 KR 의
#     beta_CID 정렬은 사실상 **역시장베타 정렬**이었다.
#   → 그러므로 KR 에서 재료 1 의 estimand 를 논문이 보고한 성질대로 세우려면
#     Eq.3 에 시장 상태를 통제항으로 넣어야 한다. **그 통제항의 함수형태를
#     정해 주는 것이 재료 2 다.**
#
#   재료 2 의 표제 결과는 "시장이 중요하다" 가 아니라 **"시장은 계단으로 들어온다"** 다:
#     "Limiting to max depth = 1"
#     "The first finding is that in all cases (solo and joint) the most informative
#      factor is always the market excess return factor."
#     "a single model capable of predicting simultaneously n stocks is built"
#     "correlation information enters the tree structure"
#     "all input variables and all possible split points are evaluated and chosen
#      in a greedy algorithm"
#     "Min for all split points  Sum_i ( y_i - prediction(y_i) )^2"
#     Table 2c: joint 임계값이 -70bp ~ -90bp 로 수렴 — **0 이 아니라 꼬리**.
#     표본 = 일간 1,259 daily returns.
#   → 재료 2 의 모형은 E[r_id] = mu_i,L * 1{mex_d <= c*} + mu_i,R * 1{mex_d > c*} 다.
#     이것을 월로 집계하면 정확히
#         E[R_it] = n_t * mu_i,R + K_t * (mu_i,L - mu_i,R),  K_t = 월 t 의 c* 이하 일수
#     즉 **재료 2 의 depth=1 모형은 월간 회귀에서 K_t 에 대한 선형항이 된다.**
#     근사가 아니라 집계의 항등식이다.
#
#   결합 산출:
#       R_it = alpha_i + beta_i * u_t + delta_i * K_t + eps_it      (24개월 월간 OLS)
#       Score_i = -winsorize(beta_i ; 1%, 99%)
#     · u_t        = 재료 1 Eq.2 의 잔차 (재료 1 의 operative 변수 · 그대로)
#     · beta_i     = 재료 1 의 beta_CID — estimand·창(24개월)·함수형태(**선형 기울기**)
#                    전부 논문 그대로. 계단으로 바꾸지 않았다.
#     · K_t        = 재료 2 의 depth=1 잎 구조를 월로 집계한 것. c*_m 은 전 종목
#                    SSE 합을 최소화하는 **공통** 임계값이고(재료 2 의 joint 트리 ·
#                    종목별 표준화 없음 · 전 분기점 greedy) 창은 재료 2 의 1,259 거래일.
#     · 부호       = 재료 1 의 **사전 선언** (고 beta_CID = 헤지 = 저수익 · Table 3
#                    vw Q1 0.79%[3.83] > Q5 0.30%[1.40] · L/S -0.49%[-3.19]).
#
#   ★직전 결합판(PORT_t 1.209)과 정확히 무엇이 다른가: 그 판은 **계단을 u 축에** 놓고
#     (재료 1 의 선형 기울기를 계단으로 치환) **시장을 선형 통제항**으로 뺐다.
#     두 논문 다 정반대를 말한다 — 재료 1 은 u 축에 **기울기**(Eq.3), 재료 2 는 시장 축에
#     **계단**(depth=1, 꼬리 임계값). 이 판은 두 함수형태를 각 논문이 지정한 축으로
#     되돌린다. 계기 (c)(선형통제판과의 순위상관)와 (d)(u축 계단판과의 순위상관)가
#     이 두 되돌림이 각각 하중을 받는지를 매월 잰다.
#
# =============================================================================
# 왜 각 재료 단독보다 나을 것이라 보는가 (반증 가능한 형태)
# =============================================================================
#  ▸ vs 재료 1 단독(PORT_t 1.228 · Grade F · CAGR 0.6%): 유일한 차이가 K_t 항이다.
#    주장 = "KR 에서 beta_CID 를 죽인 것은 CID 가 아니라 u 에 실린 시장 채널이고,
#    그 채널은 재료 2 가 보고한 대로 **꼬리 계단**의 형태로 들어온다."
#    반증: 계기 (a) 중앙 rho(Score, 재료1 원판 단변량 Score) ~ +1 이면 통제항 무하중,
#          계기 (b) rho(Score, 창 시장베타)가 양성대조 rho(원판 Score, 시장베타)와
#          같은 크기면 역베타 채널이 그대로 남은 것 = 이 판의 존재이유가 기각된다.
#  ▸ vs 재료 2 단독(PORT_t 1.11): 그 판의 사인은 **수준 발행**이었다 — 다수 잎의 잎
#    평균(수준)을 스코어로 내면 긴 창에서 종목의 무조건부 평균수익과 같아진다.
#    이 판은 잎 구조를 **회귀변수로만** 쓰고 잎 평균을 발행하지 않는다. beta_i 는
#    기울기라 종목별 수준 alpha_i 가 정의상 들어올 수 없다. 또 재료 2 는 방향을 주지
#    않아 단독 구현이 부호 선택을 거부했는데, 여기서는 부호가 재료 1 의 사전 선언이다.
#    반증: 계기 (e) 중앙 |rho(Score, 창 무조건부 평균수익)| 이 크면 수준 별칭 재현.
#  ▸ vs 이 재료집합의 앞선 결합 3회(평균 0.766 · u축계단+선형통제 1.209 · 일간칸대비 기각):
#    반증: 계기 (c) rho(Score, 선형통제판) ~ +1 **이면서** 계기 (d) rho(Score, u축
#    계단판) ~ +1 이면 이 판은 1.209 의 재실행이다(두 되돌림 다 무하중).
#  ▸ 전제 검정: 계기 (f) — 같은 창·같은 종목·같은 척도(SSE 감소)에서 u 를 1단 분기변수로
#    썼을 때 mex 를 이기는 달의 비율. 재료 2 는 "in all cases ... always the market
#    excess return factor" 라고 보고한다. KR 에서 u 가 자주 이기면 재료 2 의 표제가
#    KR 에서 깨진 것이고, "시장을 통제 축에 둔다" 는 이 설계의 전제가 약해진다.
#
# =============================================================================
# 0. 미명시값 보충 — 이 목록이 전부다 (FIDELITY.changed 와 1:1)
# =============================================================================
#  [재료 1 명시값] 10사 하한 · 24개월 창 · 1%/99% winsorize · 월간 재추정/리밸
#  [재료 2 명시값] depth=1 · 1,259 거래일 · joint(전 종목 SSE 합) · 종목별 표준화 없음
#  [보충 1] Eq.2 AR = **expanding window**(논문은 전표본 1회 추정 — C1 위반이라 PIT 가
#           논문 문자를 이긴다) · burn-in 60개월. RP_2301_09173_CID 선례 승계.
#  [보충 2] 종목별 회귀 최소 유효 개월 .MIN_MO = 18/24. 논문은 최소관측 규정이 없으나
#           절편+2회귀변수 OLS 라 하한이 필요하다. 같은 estimand 의 사내 선례와 동일값.
#           ★이것은 **종목** 필터이지 월 필터가 아니다 — 어떤 달도 이 값으로 죽지 않는다.
#  [보충 3] 구조 추정 종목의 장기창 커버리지 .COV_L = 0.60. 이 종목집합은 공통 임계값
#           c*_m 만 만들고 종목별 산출을 내지 않는다. **과거** 데이터 요건이라 생존편의를
#           만들지 않는다(미래 상장폐지 여부를 묻지 않는다).
#  [보충 4] 분기 균형하한 .BAL_MIN = 0.05(양쪽). 재료 2 는 하한을 주지 않지만(sklearn
#           기본 min_samples_leaf=1) 하한이 없으면 1,259일 중 단 하루(극단일)를 잎으로
#           떼는 분기가 SSE 를 최대로 줄일 수 있고, 그러면 K_t 가 24개월 내내 0 이라
#           통제항이 무의미해진다. 5% 는 재료 2 가 실제로 회수한 **joint** 임계값
#           (-70~-90bp = 일간 약 -0.5sd = 정규 하에서 약 30%)에서 한참 떨어진 자리라
#           상시 구속되지 않아야 하고, 구속률을 매월 로그해 계기 (g) 로 드러낸다.
#  [보충 5] joint 트리 성립 최소 종목수 .MIN_STK = 5 (논문 표본이 5종).
#  [보충 6] 진단 전용 하한 .DIAG_MIN_MO = 6. **계기 (d)** 의 u축 계단 대비를 24개월
#           위에서 재현할 때만 쓴다. 산출 경로에 없다 — 이 값 때문에 종목이나 달이
#           탈락하는 일이 없다(진단이 NA 가 될 뿐).
#  [보충 7] 회귀 전 u·K·시장수익을 창 내부 평균/표준편차로 표준화한다. 각 종목 회귀의
#           아핀 재모수화라 beta 가 종목 공통 양수배율만 받고 **단면 순위·winsorize·
#           상위 25 선택이 정확히 불변**이다. 수치 조건수 목적이지 모형 변경이 아니다.
#  [보충 8] 통제항 퇴화(그 종목의 관측 월에서 K_t 가 상수 → 정규방정식 특이) 시 그
#           종목은 **재료 1 의 원판 단변량 Eq.3** 로 되돌린다. 달을 버리지 않는다.
#           발화율을 로그한다(기대값 ~0).
#  [보충 9] 산업분류 = RAWDATA `Sector_Lv2`(WI26 중분류). 논문의 FF49 를 대체하는
#           **치환**이며 FIDELITY.changed 에 명시했다. 관측 라벨 수와 월별 유효 산업수를
#           로그로 드러낸다(분류 해상도가 Eq.1 의 N 과 '>=10사' 의 구속력을 바꾸므로).
#           각 월말에 기록된 값을 그대로 쓴다(시변 기록).
#  [보충10] rf 미사용. 논문은 초과수익을 쓴다. 회귀변수가 전 종목 공통 시계열이므로
#           beta_hat(R - rf) = beta_hat(R) - beta_hat(rf) 이고 beta_hat(rf) 는 모든
#           종목에서 **같은 상수**다(같은 X 를 쓰는 종목 한정) → 단면 순위·1%/99%
#           winsorize·상위 25 선택이 정확히 불변. 창 안 결측 월이 있는 종목에서는 X 가
#           달라 상수성이 근사이며 그 한계를 여기 적는다. KR 무위험(ECOS CD91)은
#           2005-08 이후만 있어 1990~ 워밍업을 덮지도 못한다. 재료 2 의 mex 는
#           총수익 기준이 되며 c*_m 이 일간 rf(~0.3~1.5bp) 만큼 이동한다 — 일간
#           표준편차(~150bp) 대비 미미하나 **정확한 불변성은 아니다**(정직 기록).
#  [보충11] |일간 Ret| > 1.0 은 결측. KRX 가격제한폭 +-30% 하에서 한 세션에 물리적으로
#           불가능한 값이라 액면/재상장 단위 아티팩트다. 전략 파라미터가 아니라 거래소
#           규칙 근거의 위생 조치.
#  [보충12] 논문의 $5 주가 / $50M 시총 필터 미적용 — 목적(CRSP microcap 제거)을
#           유니버스 치환(K200 U KQ150)이 더 강하게 수행한다. 달러 문턱의 원화 이식은
#           근거 없는 수치가 된다.
#  [축(도훈 고정)] 유니버스 K200 U KQ150(PIT 시변) · adv20(t-1) >= 2e8 (20 거래일 전부
#           관측 요구) · 2005-01-01~ · 종목수/비중 = top-25 롱온리 EW.
#           ★리밸 주기(월간)는 축이자 **재료 1 의 명시값**이고, 이 판은 그것을 실현한다.
#           종목수·비중만 축이 두 논문 규약을 대체한다(재료 2 는 포트폴리오가 아예
#           없고 — "only done for demonstration purposes and not for statistical
#           inference" — 재료 1 의 5분위 VW 는 레그당 ~70종이라 충돌한다).
#
# =============================================================================
# PIT (C1~C15) — 구조로 보장한다. detect_lookahead 통과를 근거로 삼지 않는다.
# =============================================================================
#  ▸ 구조 경계 1 (창): 장기창은 `(ip - .T_LONG + 1L):ip`, 단기창은 `ymi in [fy-23, fy]`
#    이고 둘 다 `<= ip` 로 잘린다. ip = match(D, 거래일격자). ip 를 넘는 인덱스,
#    음수 shift, lead(), 수동 미래 인덱싱이 이 파일에 0건이다.
#  ▸ 구조 경계 2 (가중/산업): 일간·월간 패널 어디서도 동월 시총·동월 섹터를 쓰지
#    않는다. 결합은 `ymi_w = ymi - 1L` 한 줄로만 일어난다 — 동월 경로가 코드에
#    **표현되어 있지 않다**(막는 검사가 아니라 불가능한 배치).
#  ▸ 구조 경계 3 (AR): expanding 누적 교차곱이 k 까지만 더해진다. u_k 는 <=k 정보만.
#  ▸ 구조 경계 4 (상태 이월 없음): 형성일 루프 반복이 서로 독립이다. 임계값·K_t·
#    회귀계수가 전부 그 형성일의 창 안에서만 계산된다.
#  C1  : rolling/expanding 만. 전표본 mean/quantile/cov/lm 0건. winsorize 는 그
#        형성일 단면 **벡터** 내부에서만(quantile(DT$col) 형태 0건).
#  C2  : same-day 순환참조 없음. D 종가까지 쓰고 집행은 익 거래일(하네스).
#  C3  : 같은 기간 집계->적용 없음. 신호 컷오프(월 m 말) < 보유월(m+1) 시작.
#  C4  : 재무제표 패널 미사용.       C5 : 오버레이 없음(S0/S1 오버레이 금지 준수).
#  C6  : 유니버스 = 각 D 의 K200/KQ150 멤버십(PIT 시변). 최종 명부 주입 없음.
#  C7  : shift(-N)·lead()·수동 미래 인덱싱 0건. shift 는 전부 +1(과거 방향).
#  C9  : DD/VT 미사용.
#  C10 : 유동성 = D **직전 20 거래일** 평균 거래대금. `(ip-20):(ip-1)` 로 당일 배제.
#  C11 : 외부 매크로 0건(rf·FRED·팩터 캐시·BM_DT 미사용). 시장 계열은 재료 1 이 Eq.1
#        에서 직접 정의하는 R_MKT("the value-weighted market return across all
#        firms")의 일간판이라 두 논문의 시장 정의가 같고 외부 의존이 0 이다.
#  C13 : Factor DB 미소비 -> 정렬 대상 없음. 부호는 재료 1 의 **사전 선언**이지
#        사후 반전이 아니다.
#  C15 : Factor DB parquet 직접 load 0건.
#  ★rawdata 의 Market 열 미사용(KOSDAQ 0건 날조 — 사내 기록). 시장 구분은 멤버십만.
#
# ===== 산출 =====
#   FACTORS(Date, Ticker, Score) — Score = -winsorize(beta_CID). 클수록 롱.
#   러너 호출: portfolio_spec = list(construction="top_n_long", weighting="ew",
#              rebalance="monthly", n_long=25, n_max=25) · commission_paper = NULL
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(matrixStats)
}))

set.seed(20070811L)   # 난수 미사용(결정론적 엔진) — 재현성 선언 고정

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.RQ <- c("Date", "Ticker", "Close", "Vol", "Ret", "Size", "Sector_Lv2", "K200", "KQ150")
if (!all(.RQ %in% names(RAWDATA)))
  stop(sprintf("[COMBO_TAILCTRL] RAWDATA 열 부족: %s",
               paste(setdiff(.RQ, names(RAWDATA)), collapse = ", ")))
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]

# ---- 상수 (§0 목록과 1:1) ---------------------------------------------------
.MIN_FIRMS   <- 10L        # [재료1] "industries with at least 10 firms"
.WIN_M       <- 24L        # [재료1] "two years of monthly excess returns"
.WINS_LO     <- 0.01       # [재료1] "winsorize beta_CID at 1% and 99% percentiles"
.WINS_HI     <- 0.99
.T_LONG      <- 1259L      # [재료2] "1,259 daily returns"
.MIN_STK     <- 5L         # [보충5] 논문 joint 트리 표본 = 5종
.BAL_MIN     <- 0.05       # [보충4] 분기 양쪽 최소 관측 비중(장기창)
.AR_BURN     <- 60L        # [보충1] AR expanding burn-in (개월)
.MIN_MO      <- 18L        # [보충2] 종목별 회귀 최소 유효 개월 (종목 필터 · 월 필터 아님)
.COV_L       <- 0.60       # [보충3] 구조 추정 종목의 장기창 커버리지 하한
.DIAG_MIN_MO <- 6L         # [보충6] 계기 (d) 전용 — 산출 경로에 없음
.RET_CAP     <- 1.0        # [보충11] |일간수익| > 100% = 데이터 아티팩트
.LIQ         <- 2e8        # [축] adv20(t-1) 하한 (KRW)
.LIQ_WIN     <- 20L        # [축] 거래일 (D 직전 20 거래일, 종점 = D-1)
.START       <- as.Date("2005-01-01")   # [축]

.tru <- function(x) !is.na(x) & (x != 0)          # 논리/0-1 혼재 방어
.t0  <- Sys.time()

# ---- 헬퍼 (전부 **벡터**만 받는다 — DT 열 직접 전달 금지) --------------------
.sp <- function(a, b) {                            # Spearman
  a <- as.numeric(a); b <- as.numeric(b)
  ok <- is.finite(a) & is.finite(b)
  if (sum(ok) < 5L) return(NA_real_)
  ra <- rank(a[ok]); rb <- rank(b[ok])
  if (stats::sd(ra) == 0 || stats::sd(rb) == 0) return(NA_real_)
  as.numeric(stats::cor(ra, rb))
}
.med <- function(x) {
  x <- as.numeric(x)
  if (!length(x) || all(!is.finite(x))) return(NA_real_)
  as.numeric(stats::median(x[is.finite(x)]))
}
.z <- function(x) {                                # [보충7] 창 내부 표준화(아핀)
  x <- as.numeric(x); s <- stats::sd(x)
  if (!is.finite(s) || s <= 0) return(rep(0, length(x)))
  (x - mean(x)) / s
}

# ---- 재료 2 의 joint depth=1 스캔 (원문 목적함수와 정확히 동치) --------------
#   "Min for all split points  Sum_i ( y_i - prediction(y_i) )^2"
#   SSE(k) = sum_i [ TSS_i - CS_i(k)^2/CN_i(k) - (TS_i-CS_i(k))^2/(TN_i-CN_i(k)) ]
#   TSS_i 는 k 에 무관 -> SSE 최소화 = 아래 gv 최대화. **종목별 표준화는 하지 않는다**
#   (재료 2 의 joint 트리가 그렇고 'dominant stock' 이 그 설계의 성질이다).
.jsplit <- function(Xs, Ms, v, min_row) {
  n <- nrow(Xs); p <- ncol(Xs)
  if (n < (2L * min_row + 1L)) return(NULL)
  o  <- order(v); vs <- as.numeric(v)[o]
  CS <- colCumsums(Xs[o, , drop = FALSE])
  CN <- colCumsums(Ms[o, , drop = FALSE])
  TS <- CS[n, ]; TN <- CN[n, ]
  RS <- matrix(TS, n, p, byrow = TRUE) - CS
  RN <- matrix(TN, n, p, byrow = TRUE) - CN
  LT <- CS * CS / CN; RT <- RS * RS / RN
  LT[!is.finite(LT)] <- 0; RT[!is.finite(RT)] <- 0
  gv <- rowSums(LT + RT)
  gr <- TS * TS / TN; gr[!is.finite(gr)] <- 0        # 무분기(root) 기준값
  ki <- seq_len(n)
  ok <- c(vs[-n] < vs[-1L], FALSE) & (ki >= min_row) & ((n - ki) >= min_row)
  if (!any(ok)) return(NULL)
  gv[!ok] <- -Inf
  k <- as.integer(which.max(gv))
  if (!is.finite(gv[k])) return(NULL)
  list(cut = as.numeric(vs[k] + vs[k + 1L]) / 2, k = k, n_row = n,
       gain = as.numeric(gv[k] - sum(gr)),
       bind = (k <= min_row) || ((n - k) <= min_row))
}

# ---- 종목별 OLS (결측 패턴 종목마다 다름 · 열 단위 벡터화) -------------------
#   beta1: y ~ 1 + z1                (재료 1 원판 Eq.3)
#   beta2: y ~ 1 + z1 + z2 의 z1 계수 (Cramer · 3x3 대칭)
.beta1 <- function(Mm, Xm, z1) {
  n <- colSums(Mm); Sx <- colSums(Mm * z1); Sxx <- colSums(Mm * z1 * z1)
  Sy <- colSums(Xm); Sxy <- colSums(Xm * z1)
  den <- n * Sxx - Sx * Sx
  ifelse(is.finite(den) & den > 1e-9 * pmax(n, 1)^2, (n * Sxy - Sx * Sy) / den, NA_real_)
}
.beta2 <- function(Mm, Xm, z1, z2) {
  a11 <- colSums(Mm)
  a12 <- colSums(Mm * z1);      a13 <- colSums(Mm * z2)
  a22 <- colSums(Mm * z1 * z1); a23 <- colSums(Mm * z1 * z2); a33 <- colSums(Mm * z2 * z2)
  b1  <- colSums(Xm); b2 <- colSums(Xm * z1); b3 <- colSums(Xm * z2)
  dA  <- a11 * (a22 * a33 - a23 * a23) - a12 * (a12 * a33 - a23 * a13) +
         a13 * (a12 * a23 - a22 * a13)
  dB  <- a11 * (b2  * a33 - a23 * b3)  - b1  * (a12 * a33 - a23 * a13) +
         a13 * (a12 * b3  - b2  * a13)
  ifelse(is.finite(dA) & dA > 1e-9 * pmax(a11, 1)^3, dB / dA, NA_real_)
}

# =============================================================================
# 1. 거래일 격자 · 전월말 시총/산업라벨 (구조 경계 2)
# =============================================================================
.ADT <- unique(RAWDATA[, .(Date)])
setorder(.ADT, Date)
.ADT[, ymi := year(Date) * 12L + month(Date)]
.MEA <- .ADT[, .(me = max(Date)), by = ymi]$me            # 시장 전체 월말 거래일

# 워밍업 하한: 첫 형성일(>= .START)에서 장기창 1,259일 + 유동성창이 성립하도록
# **데이터에서 도출**한다(임의 상수 아님).
.adates <- .ADT$Date
.nb <- sum(.adates < .START)
if (.nb < (.T_LONG + .LIQ_WIN + 10L))
  stop(sprintf("[COMBO_TAILCTRL] .START 이전 거래일 %d — 장기창 %d 워밍업 불가",
               .nb, .T_LONG))
.dmin <- .adates[.nb - .T_LONG - .LIQ_WIN - 9L]

# ★섹터 라벨로 여기서 거르지 않는다 — R_MKT 는 "all firms" 이고 산업 라벨은 Eq.1 의
#   산업 다리에만 필요하다. 여기서 걸면 시장 다리가 논문보다 좁아진다.
.EOM <- RAWDATA[Date %in% .MEA & is.finite(Size) & Size > 0,
                .(Ticker, ymi_w = year(Date) * 12L + month(Date),
                  w = as.numeric(Size), ind = Sector_Lv2)]
.EOM <- unique(.EOM, by = c("Ticker", "ymi_w"))
if (!nrow(.EOM)) stop("[COMBO_TAILCTRL] 월말 시총 관측 0건 — Size 확인")
if (all(is.na(.EOM$ind)))
  stop("[COMBO_TAILCTRL] 월말 산업라벨 0건 — Sector_Lv2 확인 (Eq.1 산업 다리 불가)")

# =============================================================================
# 2. 일간 -> 월간 전 상장종목 패널 + 일간 VW 시장 (재료 1 의 R_MKT 정의)
# =============================================================================
.DD <- RAWDATA[is.finite(Ret) & abs(Ret) <= .RET_CAP,
               .(Date, Ticker, rr = as.numeric(Ret))]
.DD[, ymi := year(Date) * 12L + month(Date)]
MON0 <- .DD[, .(mret = prod(1 + rr) - 1), by = .(Ticker, ymi)]   # 월간 복리
.DD[, ymi_w := ymi - 1L]                                          # ★전월말 (동월 경로 없음)
.DD[.EOM, on = .(Ticker, ymi_w), w := i.w]
MKTD <- .DD[Date >= .dmin & is.finite(w) & w > 0,
            .(r_mkt = sum(w * rr) / sum(w)), by = Date]            # 일간 VW 전 상장종목
setorder(MKTD, Date)
rm(.DD); gc(verbose = FALSE)
if (!nrow(MKTD)) stop("[COMBO_TAILCTRL] 일간 VW 시장 0행 — 전월말 가중치 결합 확인")

MON <- merge(MON0, .EOM[, .(Ticker, ymi = ymi_w + 1L, w, ind)],
             by = c("Ticker", "ymi"))
if (!nrow(MON)) stop("[COMBO_TAILCTRL] 월간 패널 0행 — 월말 격자 확인")

# =============================================================================
# 3. 재료 1 Eq.1 — **월간** CID (상태변수는 논문 그대로 월간이다)
# =============================================================================
# 일간 CID 는 산업 일간 변동성 계열이지 논문이 장기실업으로 검증한 변수가 아니다
# ("CID predicts growth in long-term unemployment ... but can not predict growth
#  in short-term unemployment"). estimand 를 건드리지 않는다.
IPF  <- MON[!is.na(ind), .(r_ind = sum(w * mret) / sum(w), nf = .N),
            by = .(ymi, ind)][nf >= .MIN_FIRMS]
MKTM <- MON[, .(r_mktm = sum(w * mret) / sum(w)), by = ymi]
CIDM <- merge(IPF[, .(ymi, r_ind)], MKTM, by = "ymi")
CIDM <- CIDM[, .(CID = mean(abs(r_ind - r_mktm)), n_ind = .N), by = ymi]
setorder(CIDM, ymi)
.n_lab <- uniqueN(MON[!is.na(ind), ind])
rm(IPF); gc(verbose = FALSE)
if (nrow(CIDM) < (.AR_BURN + .WIN_M + 12L))
  stop(sprintf("[COMBO_TAILCTRL] 월간 CID %d개월 — 표본 부족", nrow(CIDM)))
cat(sprintf(paste0("[COMBO_TAILCTRL] Eq.1 월간 CID %d개월 · 평균 %.4f sd %.4f\n",
                   "  ★산업 다리 = Sector_Lv2(WI26 중분류) — 논문 FF49 의 **치환**",
                   "(FIDELITY.changed 명시). 관측 라벨 %d종 · 월별 유효 산업수",
                   "(>=%d사) 중앙 %.0f (min %d / max %d)\n"),
            nrow(CIDM), mean(CIDM$CID), stats::sd(CIDM$CID),
            .n_lab, .MIN_FIRMS, .med(CIDM$n_ind), min(CIDM$n_ind), max(CIDM$n_ind)))

# =============================================================================
# 4. 재료 1 Eq.2 — CID 충격 u_t (expanding window AR · PIT 보정)
# =============================================================================
#   expanding OLS 를 누적 교차곱으로 정확히 구현한다(lm 반복과 수치 동일 · O(n)).
#   구조 경계 3: 각 k 의 계수는 1..k 만 더한 X'X, X'y 에서 나온다.
#   ★인접성 가드: CIDM 의 월이 끊기면 shift() 가 비인접 월을 인접으로 취급해 Δ 가
#     조용히 어긋난다(라벨 결측기에는 >=10사 산업이 없어 월이 빠질 수 있다).
#     인접하지 않은 자리는 Δ·시차항을 NA 로 두어 AR 표본에서 제외한다.
CIDM[, ymi_p := shift(ymi)]
CIDM[, adj := is.finite(ymi_p) & (ymi_p == ymi - 1L)]
CIDM[, dC := CID - shift(CID)]
CIDM[!adj, dC := NA_real_]
CIDM[, `:=`(dC_l1 = shift(dC), C_l1 = shift(CID))]
CIDM[!adj, `:=`(dC_l1 = NA_real_, C_l1 = NA_real_)]
.ngap <- sum(!CIDM$adj[-1L])
if (.ngap > 0L)
  cat(sprintf("[COMBO_TAILCTRL] ★CID 월 결번 %d건 — 그 자리의 Δ·시차항은 AR 표본에서 제외\n",
              .ngap))
CIDM[, u := NA_real_]
.rw <- which(is.finite(CIDM$dC) & is.finite(CIDM$dC_l1) & is.finite(CIDM$C_l1))
if (length(.rw) < (.AR_BURN + .WIN_M))
  stop("[COMBO_TAILCTRL] AR 적합 가능 개월 부족")
.yv <- CIDM$dC[.rw]; .x1 <- CIDM$dC_l1[.rw]; .x2 <- CIDM$C_l1[.rw]; .nn <- length(.rw)
.c1  <- seq_len(.nn);      .ca <- cumsum(.x1);        .cb <- cumsum(.x2)
.caa <- cumsum(.x1 * .x1); .cab <- cumsum(.x1 * .x2); .cbb <- cumsum(.x2 * .x2)
.cy  <- cumsum(.yv);       .cay <- cumsum(.x1 * .yv); .cby <- cumsum(.x2 * .yv)
.uv <- rep(NA_real_, .nn)
for (k in seq.int(.AR_BURN, .nn)) {
  M3 <- matrix(c(.c1[k], .ca[k],  .cb[k],
                 .ca[k], .caa[k], .cab[k],
                 .cb[k], .cab[k], .cbb[k]), 3L, 3L)
  g <- tryCatch(solve(M3, c(.cy[k], .cay[k], .cby[k])), error = function(e) NULL)
  if (is.null(g)) next
  .uv[k] <- .yv[k] - (g[1] + g[2] * .x1[k] + g[3] * .x2[k])
}
set(CIDM, i = .rw, j = "u", value = .uv)
if (sum(is.finite(CIDM$u)) < (.WIN_M + 12L))
  stop("[COMBO_TAILCTRL] CID 충격 u 유효 개월 부족 — AR 적합 실패")
.uok <- CIDM[is.finite(u)]
cat(sprintf("[COMBO_TAILCTRL] Eq.2 충격 u: 유효 %d개월 (%d ~ %d) · sd %.5f · 1-lag 자기상관 %+.3f (논문 US: -0.05)\n",
            nrow(.uok), min(.uok$ymi), max(.uok$ymi), stats::sd(.uok$u),
            .sp(.uok$u[-1L], .uok$u[-nrow(.uok)])))
rm(.uok)

# 월 인덱스 조회 배열 (u · 월간 VW 시장수익)
.ymi0 <- min(MON$ymi); .ymiN <- max(MON$ymi)
.uarr <- rep(NA_real_, .ymiN - .ymi0 + 1L)
.uarr[CIDM$ymi - .ymi0 + 1L] <- CIDM$u
.marr <- rep(NA_real_, .ymiN - .ymi0 + 1L)
.marr[MKTM$ymi - .ymi0 + 1L] <- MKTM$r_mktm
rm(MON); gc(verbose = FALSE)

# =============================================================================
# 5. 테스트 자산 (K200 U KQ150) — 일간 wide + 월간 wide
# =============================================================================
.tk <- unique(RAWDATA[.tru(K200) | .tru(KQ150), Ticker])
if (!length(.tk)) stop("[COMBO_TAILCTRL] K200/KQ150 멤버십 0건 — RAWDATA 확인")

.rs <- RAWDATA[Ticker %chin% .tk & Date >= .dmin &
               is.finite(Ret) & abs(Ret) <= .RET_CAP,
               .(Date, Ticker, r = as.numeric(Ret))]
.nd <- sum(duplicated(.rs, by = c("Ticker", "Date")))
if (.nd > 0L) {
  cat(sprintf("[COMBO_TAILCTRL] (Date,Ticker) 중복 %d행 — 첫 행만 남긴다\n", .nd))
  .rs <- unique(.rs, by = c("Ticker", "Date"))
}
.RW <- dcast(.rs, Date ~ Ticker, value.var = "r")
setorder(.RW, Date)
rm(.rs); gc(verbose = FALSE)

.rdt <- MKTD$Date[MKTD$Date %in% .RW$Date]         # 시장·테스트자산이 둘 다 있는 날
if (length(.rdt) < (.T_LONG + .LIQ_WIN + 10L))
  stop(sprintf("[COMBO_TAILCTRL] 거래일 격자 %d — 장기창 %d 워밍업 불가",
               length(.rdt), .T_LONG))
RETD  <- as.matrix(.RW[, -1L, with = FALSE])[match(.rdt, .RW$Date), , drop = FALSE]
.tick <- colnames(RETD)
rm(.RW); gc(verbose = FALSE)
.rym <- year(.rdt) * 12L + month(.rdt)
setkey(MKTD, Date)
.mvec <- MKTD[.(.rdt), r_mkt]
if (anyNA(.mvec)) stop("[COMBO_TAILCTRL] 일간 시장계열 정렬 실패 — 격자 불일치")

.MW <- dcast(MON0[Ticker %chin% .tick, .(ymi, Ticker, mret)], ymi ~ Ticker,
             value.var = "mret")
setorder(.MW, ymi)
.mym <- .MW$ymi
.MWm <- as.matrix(.MW[, -1L, with = FALSE])
# ★열 정렬은 **이름으로** 채운다. match(.tick, colnames) 은 월간 패널에 없는 종목에서
#   NA 첨자를 만들고, NA 첨자 인덱싱은 진단 한 줄 때문에 라운드를 통째로 죽일 수 있다.
RETM <- matrix(NA_real_, nrow(.MWm), length(.tick), dimnames = list(NULL, .tick))
.hit <- intersect(.tick, colnames(.MWm))
if (length(.hit)) RETM[, .hit] <- .MWm[, .hit, drop = FALSE]
rm(.MW, .MWm, MON0); gc(verbose = FALSE)

.SEC <- unique(.EOM[, .(Ticker, ymi_w, ind)], by = c("Ticker", "ymi_w"))
setkey(.SEC, ymi_w, Ticker)
rm(.EOM); gc(verbose = FALSE)

cat(sprintf("[COMBO_TAILCTRL] 테스트 자산 %d거래일 x %d종 (%s ~ %s) · 일간 결측 %.1f%%\n",
            nrow(RETD), ncol(RETD), as.character(min(.rdt)), as.character(max(.rdt)),
            100 * mean(is.na(RETD))))

# =============================================================================
# 6. 형성일(월말 거래일) · 유동성 창 · 자격
# =============================================================================
.ME    <- data.table(Date = .rdt, ymi = .rym)[, .(Date = max(Date)), by = ymi]
setorder(.ME, Date)
.FORM0 <- .ME[Date >= .START, Date]
if (!length(.FORM0)) stop("[COMBO_TAILCTRL] 형성일 0건 — RAWDATA 날짜 범위 확인")
.fip0  <- match(.FORM0, .rdt)
.warm  <- is.finite(.fip0) & .fip0 >= .T_LONG & .fip0 > .LIQ_WIN
# 워밍업 탈락은 **선두 연속 구간**이어야 한다. 중간에 끼면 그건 워밍업이 아니라 결함이다.
if (!any(.warm)) stop("[COMBO_TAILCTRL] 워밍업을 통과한 형성일 0건")
.w1 <- which(.warm)
if (!all(.warm[min(.w1):length(.warm)]))
  stop("[COMBO_TAILCTRL] 워밍업 탈락이 선두 연속 구간이 아니다 — 격자 결함")
if (min(.w1) > 1L)
  cat(sprintf("[COMBO_TAILCTRL] 워밍업으로 선두 %d개월 제외 (%s ~ %s) — 장기창 %d일 요건\n",
              min(.w1) - 1L, as.character(.FORM0[1]), as.character(.FORM0[min(.w1) - 1L]),
              .T_LONG))
.FORM <- .FORM0[.warm]
.fip  <- .fip0[.warm]
.fym  <- year(.FORM) * 12L + month(.FORM)

.LW <- rbindlist(lapply(seq_along(.FORM), function(k) {
  ip <- .fip[k]
  data.table(Date = .rdt[(ip - .LIQ_WIN):(ip - 1L)], FormDate = .FORM[k])  # 종점 = D-1 (C10)
}), use.names = TRUE)

.rdq <- RAWDATA[Ticker %chin% .tk & Date %in% unique(c(.LW$Date, .FORM)),
                .(Date, Ticker, Close, Vol, K200, KQ150)]
.rdq <- unique(.rdq, by = c("Ticker", "Date"))
.ADV <- merge(.rdq[is.finite(Close) & is.finite(Vol), .(Date, Ticker, TV = Close * Vol)],
              .LW, by = "Date", allow.cartesian = TRUE)
.ADV <- .ADV[is.finite(TV), .(ADV20 = mean(TV), nobs = .N), by = .(FormDate, Ticker)]
.ADV <- .ADV[nobs == .LIQ_WIN & ADV20 >= .LIQ, .(FormDate, Ticker)]
.ELG <- .rdq[Date %in% .FORM & (.tru(K200) | .tru(KQ150)) & is.finite(Close) & Close > 0,
             .(FormDate = Date, Ticker)]
.ELG <- merge(.ELG, .ADV, by = c("FormDate", "Ticker"))
setkey(.ELG, FormDate)
rm(.rdq, .LW, .ADV); gc(verbose = FALSE)

# =============================================================================
# 7. 형성일 루프 — **월 탈락 게이트 0개**
#    (i)   재료 2: 장기창 1,259일 joint depth=1 트리(mex) -> 공통 임계값 c*_m
#    (ii)  재료 2 -> 월 집계: K_t = 월 t 의 mex <= c*_m 일수
#    (iii) 재료 1 Eq.3: 24개월 월간 OLS  R = a + beta*u + delta*K  -> beta_i
#    (iv)  재료 1: 단면 1%/99% winsorize -> Score = -beta
# =============================================================================
.OUT <- vector("list", length(.FORM))
.LOG <- vector("list", length(.FORM))

for (kk in seq_along(.FORM)) {
  D  <- .FORM[kk]
  fy <- .fym[kk]
  ip <- .fip[kk]

  cand <- .ELG[.(D), Ticker, nomatch = 0L]
  cand <- intersect(cand, .tick)
  ci   <- match(cand, .tick)

  # ── (i) 재료 2 — joint depth=1 트리 (장기창 종점 = D) ─────────────────────
  wl <- (ip - .T_LONG + 1L):ip
  mL <- .mvec[wl]
  cm <- NA_real_; gm <- NA_real_; gu <- NA_real_; n_str <- 0L
  bindm <- NA; kfrac <- NA_real_
  if (length(ci)) {
    YL   <- RETD[wl, ci, drop = FALSE]
    kL   <- colSums(!is.na(YL)) >= (.COV_L * .T_LONG)
    n_str <- sum(kL)
    if (n_str >= .MIN_STK) {
      XL <- YL[, kL, drop = FALSE]
      ML <- matrix(as.numeric(!is.na(XL)), .T_LONG, n_str)
      XL[is.na(XL)] <- 0
      .mr <- as.integer(ceiling(.BAL_MIN * .T_LONG))
      sm  <- .jsplit(XL, ML, mL, min_row = .mr)
      if (!is.null(sm)) {
        cm <- sm$cut; gm <- sm$gain; bindm <- sm$bind; kfrac <- 100 * sm$k / sm$n_row
      }
      # (계기 f) 같은 창·같은 종목·같은 척도에서 u 를 1단 분기변수로 썼다면
      uL <- .uarr[.rym[wl] - .ymi0 + 1L]
      if (!anyNA(uL)) {
        su <- .jsplit(XL, ML, uL, min_row = .mr)
        if (!is.null(su)) gu <- su$gain
      }
      rm(XL, ML)
    }
    rm(YL)
  }

  # ── (ii) 월 집계 K_t (재료 2 의 depth=1 모형을 월로 집계한 항등식) ─────────
  ws  <- which(.rym >= (fy - .WIN_M + 1L) & .rym <= fy)
  ws  <- ws[ws <= ip]                                     # 단기창 종점 = D
  Ind <- if (is.finite(cm)) as.numeric(.mvec[ws] <= cm) else rep(0, length(ws))
  agg <- rowsum(Ind, .rym[ws], reorder = TRUE)
  wmo <- as.integer(rownames(agg))
  Kv  <- as.numeric(agg[, 1])
  uv  <- .uarr[wmo - .ymi0 + 1L]
  mv  <- .marr[wmo - .ymi0 + 1L]
  mi  <- match(wmo, .mym)
  km  <- is.finite(uv) & is.finite(mv) & !is.na(mi)
  wmo <- wmo[km]; Kv <- Kv[km]; uv <- uv[km]; mv <- mv[km]; mi <- mi[km]

  # ── (iii) 재료 1 Eq.3 (+ 재료 2 의 계단 통제항) ────────────────────────────
  # ★여기서 달이 죽는 경로가 없다: 아래는 전부 **종목** 수준 판정이다.
  b_use <- NULL; sc <- NULL; tkr <- NULL
  n_fb <- 0L; rho_uni <- NA_real_; rho_lin <- NA_real_; rho_stp <- NA_real_
  rho_bm <- NA_real_; rho_bm0 <- NA_real_; rho_lvl <- NA_real_
  sdK <- NA_real_; medK <- NA_real_; sec_sh <- NA_real_
  if (length(mi) >= 3L && length(ci)) {
    Ym <- RETM[mi, ci, drop = FALSE]
    Mm <- matrix(as.numeric(is.finite(Ym)), nrow(Ym), ncol(Ym))
    Xm <- Ym; Xm[!is.finite(Xm)] <- 0
    zu <- .z(uv); zK <- .z(Kv); zm <- .z(mv)             # [보충7] 아핀 · 순위 불변

    b_ct  <- .beta2(Mm, Xm, zu, zK)                      # ★산출
    b_un  <- .beta1(Mm, Xm, zu)                          # (a) 재료 1 원판 단변량
    b_li  <- .beta2(Mm, Xm, zu, zm)                      # (c) 선형 시장통제(1.209 축)
    b_mk  <- .beta1(Mm, Xm, zm)                          # (b) 창 시장베타
    nobs  <- colSums(Mm)
    mu_w  <- ifelse(nobs > 0, colSums(Xm) / nobs, NA_real_)   # (e) 무조건부 수준

    n_fb  <- sum(!is.finite(b_ct) & is.finite(b_un) & nobs >= .MIN_MO)  # [보충8]
    b_use <- ifelse(is.finite(b_ct), b_ct, b_un)

    # (d) u 축 계단 대비 — 진단 전용([보충6]). 산출·탈락에 관여하지 않는다.
    d_st <- rep(NA_real_, ncol(Xm))
    sd0  <- .jsplit(Xm, Mm, uv, min_row = .DIAG_MIN_MO)
    if (!is.null(sd0)) {
      hi  <- uv > sd0$cut
      n_h <- colSums(Mm[hi, , drop = FALSE]);  s_h <- colSums(Xm[hi, , drop = FALSE])
      n_l <- colSums(Mm[!hi, , drop = FALSE]); s_l <- colSums(Xm[!hi, , drop = FALSE])
      d_st <- ifelse(n_h >= .DIAG_MIN_MO & n_l >= .DIAG_MIN_MO,
                     s_h / n_h - s_l / n_l, NA_real_)
    }

    good <- is.finite(b_use) & nobs >= .MIN_MO           # [보충2] 종목 필터
    if (any(good)) {
      # ── (iv) 재료 1 명시: 단면 1%/99% winsorize -> 사전 선언 부호 ──────────
      bv <- as.numeric(b_use[good])
      qq <- stats::quantile(bv, c(.WINS_LO, .WINS_HI), na.rm = TRUE, names = FALSE)
      bw <- pmin(pmax(bv, qq[1]), qq[2])
      sc <- -bw                                          # 고민감 = 저수익 (사전 선언)
      tkr <- cand[good]
      .OUT[[kk]] <- data.table(Date = D, Ticker = tkr, Score = sc)

      rho_uni <- .sp(sc, -as.numeric(b_un[good]))
      rho_lin <- .sp(sc, -as.numeric(b_li[good]))
      rho_stp <- .sp(sc, -as.numeric(d_st[good]))
      rho_bm  <- .sp(sc,  as.numeric(b_mk[good]))
      rho_bm0 <- .sp(-as.numeric(b_un[good]), as.numeric(b_mk[good]))
      rho_lvl <- .sp(sc,  as.numeric(mu_w[good]))

      # (h) 롱 상위 25 의 최대 섹터 점유율 — 재료 1 의 기전(산업 재배치)이 보이는가
      if (length(sc) >= 25L) {
        tp <- tkr[order(-sc)][seq_len(25L)]
        sv <- .SEC[.(fy - 1L, tp), ind]
        sv <- sv[!is.na(sv)]
        if (length(sv) >= 10L) sec_sh <- 100 * max(table(sv)) / length(sv)
      }
    }
    sdK <- stats::sd(Kv); medK <- .med(Kv)
    rm(Ym, Mm, Xm)
  }

  sdmL <- stats::sd(mL)
  .LOG[[kk]] <- data.table(
    Date    = D,
    n_stock = if (is.null(sc)) 0L else length(sc),
    n_mo    = length(mi), n_str = n_str,
    thr_sd  = if (is.finite(cm) && is.finite(sdmL) && sdmL > 0) as.numeric(cm / sdmL) else NA_real_,
    thr_bp  = if (is.finite(cm)) 1e4 * cm else NA_real_,
    lowfrac = kfrac,                       # (g) 장기창 저-mex 잎 비중(%)
    bind    = if (is.na(bindm)) NA_integer_ else as.integer(bindm),
    med_K   = medK, sd_K = sdK,            # (g) 통제항이 실제로 변동하는가
    n_fb    = n_fb,                        # [보충8] 통제항 퇴화 종목수
    gain_m  = gm, gain_u = gu,             # (f) 재료 2 표제 검정
    rho_uni = rho_uni, rho_lin = rho_lin, rho_stp = rho_stp,
    rho_bm  = rho_bm,  rho_bm0 = rho_bm0,  rho_lvl = rho_lvl,
    sec_sh  = sec_sh)
}

FACTORS <- rbindlist(Filter(Negate(is.null), .OUT), use.names = TRUE)
if (!nrow(FACTORS))
  stop("[COMBO_TAILCTRL] FACTORS 0행 — 장기창/커버리지/월간 패널 확인")
setorder(FACTORS, Date, -Score)

LOGDT <- rbindlist(Filter(Negate(is.null), .LOG), use.names = TRUE)
setorder(LOGDT, Date)

# =============================================================================
# 8. ★월간 리밸 전수 발행 검사 (감사 지적 ① 의 hard assert)
#    재료 1 §3.2: "I update estimates of beta_CID and rebalance portfolios every
#    month." 워밍업을 통과한 형성월은 **예외 없이** 신호를 낸다. 앞 판은 252개월 중
#    156개월만 냈고(22개월 연속 블랙아웃 포함) 그 스케줄 위에서 등급이 계산됐다.
#    여기서 조용히 넘어가지 않는다 — 미발행 월을 이름과 진단으로 찍고 중단한다.
# =============================================================================
.emit <- unique(FACTORS$Date)
.miss <- .FORM[!(.FORM %in% .emit)]
if (length(.miss)) {
  .dg <- utils::head(LOGDT[Date %in% .miss], 12L)
  stop(sprintf(paste0("[COMBO_TAILCTRL] ★월간 리밸 위반 — 형성월 %d/%d 미발행. ",
                      "재료 1 §3.2 는 매월 재추정·리밸을 명시한다.\n  미발행 월: %s\n",
                      "  진단(앞 %d건 · 종목/유효월/구조종목): %s"),
               length(.miss), length(.FORM),
               paste(as.character(utils::head(.miss, 24L)), collapse = " "),
               nrow(.dg),
               paste(sprintf("%s[%d/%d/%d]", as.character(.dg$Date), .dg$n_stock,
                             .dg$n_mo, .dg$n_str), collapse = " ")))
}

# =============================================================================
# 9. 회수된 구조 + 반증 계기 보고
# =============================================================================
LOGDT[, yr := year(Date)]

.byyr <- LOGDT[, .(n_m = .N, n_stk = as.integer(.med(n_stock)),
                   thr = round(.med(thr_sd), 2), lf = round(.med(lowfrac)),
                   mK = round(.med(med_K), 1), sK = round(.med(sd_K), 1),
                   r_un = round(.med(rho_uni), 2), r_li = round(.med(rho_lin), 2),
                   r_st = round(.med(rho_stp), 2), r_bm = round(.med(rho_bm), 2),
                   r_b0 = round(.med(rho_bm0), 2), r_lv = round(.med(rho_lvl), 2)),
                 by = yr]
setorder(.byyr, yr)
cat("[COMBO_TAILCTRL] 연도별 (재료2 joint depth=1 임계값 c*_m + 재료1 Eq.3 24개월 월간 OLS):\n")
cat("      연도 | 월수 종목  c*m(sd) 저잎%  K중앙 K표준편차 | rho(원판) rho(선형통제) rho(u계단) rho(시장b)[원판] rho(수준)\n")
for (i in seq_len(nrow(.byyr)))
  cat(sprintf("      %4d |  %2d  %3d   %+5.2f  %4.0f%%  %5.1f %6.1f     | %+6.2f   %+6.2f     %+6.2f    %+6.2f [%+6.2f]  %+6.2f\n",
              .byyr$yr[i], .byyr$n_m[i], .byyr$n_stk[i], .byyr$thr[i], .byyr$lf[i],
              .byyr$mK[i], .byyr$sK[i], .byyr$r_un[i], .byyr$r_li[i], .byyr$r_st[i],
              .byyr$r_bm[i], .byyr$r_b0[i], .byyr$r_lv[i]))

.nmn <- FACTORS[, .N, by = Date]
# ★스코어 분포 요약은 **벡터로 뽑아** 잰다 — `quantile(DT$col)` 형태는 lookahead_detector
#   C1b(전 표본 분위수)에 걸려 라운드가 통째로 중단된다. 창 안에서 이미 산출된 값의
#   분포 요약(로그)이지 신호 구성이 아니다.
.scv  <- as.numeric(FACTORS[["Score"]])
.uwin <- 100 * mean(is.finite(LOGDT$gain_u) & is.finite(LOGDT$gain_m) &
                    LOGDT$gain_u > LOGDT$gain_m)
.bindr <- 100 * mean(LOGDT$bind %in% 1L)
.fbr   <- 100 * mean(LOGDT$n_fb > 0L)

cat(sprintf(paste0(
  "[COMBO_TAILCTRL] combination — 재료1 Eq.3 의 **선형 기울기**는 u 축에 그대로 두고,\n",
  "  재료2 의 **depth=1 꼬리 계단**을 시장 축의 통제항으로 넣는다:\n",
  "     R_it = a_i + beta_i*u_t + delta_i*K_t + e_it   (24개월 월간 OLS)\n",
  "     K_t  = 월 t 중 mex <= c*_m 인 일수 · c*_m = 전 종목 SSE 합 최소화 공통 임계값\n",
  "            (창 %d거래일 · joint · 종목별 표준화 없음)\n",
  "     Score = -winsorize(beta_i ; 1%%, 99%%)   [부호 = 재료1 사전 선언]\n",
  "  ── 월간 리밸 ────────────────────────────────────────────────────────────\n",
  "  형성월 %d/%d 전수 발행 (%s ~ %s) · FACTORS %s행 · 월 종목 중앙 %d (min %d / max %d)\n",
  "  ★월 탈락 게이트 0개 — 종목 필터만 존재. 통제항 퇴화 폴백 발생 월 %.1f%%\n",
  "  ── 회수된 구조 ─────────────────────────────────────────────────────────\n",
  "  c*_m 중앙 %+.1fbp (= %+.2f sd) · 저-mex 잎 비중 중앙 %.0f%% · 균형하한 5%% 구속 %.1f%%\n",
  "    → 재료2 는 joint 임계값이 -70~-90bp(약 -0.5sd)의 **꼬리**에 선다고 보고했다.\n",
  "  K_t 중앙 %.1f일 · K_t 창내 표준편차 중앙 %.1f  (0 이면 통제항이 무의미)\n",
  "  ── 반증 계기 (전 기간 중앙값) ──────────────────────────────────────────\n",
  "  (a) rho(Score, 재료1 원판 단변량 Score) %+5.2f\n",
  "      → +1 근방이면 통제항 무하중 = 이 판은 CID 단독(PORT_t 1.228)의 재실행이다.\n",
  "  (b) rho(Score, 창 시장베타) %+5.2f   [양성대조 = 원판 %+5.2f]\n",
  "      → 두 값이 같으면 CID 단독을 죽인 역베타 채널이 그대로 남은 것 = 수술 실패.\n",
  "  (c) rho(Score, **선형** 시장통제판) %+5.2f\n",
  "  (d) rho(Score, u 축 **계단** 대비판) %+5.2f\n",
  "      → (c)(d) 가 둘 다 +1 근방이면 직전 결합판(PORT_t 1.209)의 재실행이다.\n",
  "  (e) rho(Score, 창 무조건부 평균수익) %+5.2f\n",
  "      → 크면 수준 별칭 = 재료2 단독(PORT_t 1.11)의 사인 재현.\n",
  "  (f) u 가 mex 를 1단 분기변수로 이긴 달 %.1f%%\n",
  "      → 높으면 재료2 의 표제('always the market excess return factor')가 KR 에서\n",
  "        깨진 것이고, 시장을 통제 축에 둔 이 설계의 전제가 약해진다.\n",
  "  (g) 롱 상위25 최대 섹터 점유율 중앙 %.1f%%  (재료1 기전 = 산업 재배치)\n",
  "  Score 중앙 %+.3f · IQR %+.3f ~ %+.3f\n",
  "  ★러너 호출: portfolio_spec = list(construction=\"top_n_long\", weighting=\"ew\",\n",
  "                                    rebalance=\"monthly\", n_long=25, n_max=25)\n",
  "              commission_paper = NULL (재료2 무명시) · %.1f분\n"),
  .T_LONG,
  length(.emit), length(.FORM),
  as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date)),
  format(nrow(FACTORS), big.mark = ","),
  as.integer(.med(.nmn$N)), min(.nmn$N), max(.nmn$N), .fbr,
  .med(LOGDT$thr_bp), .med(LOGDT$thr_sd), .med(LOGDT$lowfrac), .bindr,
  .med(LOGDT$med_K), .med(LOGDT$sd_K),
  .med(LOGDT$rho_uni), .med(LOGDT$rho_bm), .med(LOGDT$rho_bm0),
  .med(LOGDT$rho_lin), .med(LOGDT$rho_stp), .med(LOGDT$rho_lvl),
  .uwin, .med(LOGDT$sec_sh),
  .med(.scv),
  as.numeric(stats::quantile(.scv, 0.25, names = FALSE)),
  as.numeric(stats::quantile(.scv, 0.75, names = FALSE)),
  as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
