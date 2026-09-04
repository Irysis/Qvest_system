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
# 결합의 형태 — 재료 2 는 "어디를 보라", 재료 1 은 "무엇을 어느 부호로 보라"
# =============================================================================
# 두 엔진 스코어를 만들어 섞는 지점이 이 파일에 없다(rank-Z 평균 계보 5회 · 최고
# PORT_t 0.766 과 다른 수술이다). 또한 **직전 판(estimand/estimator 치환 — 재료 1 의
# 선형 기울기를 u 축 계단으로 바꾸고 시장은 회귀 통제항)과도 다르다**. 그 판은
# PORT_t 1.209 로 이 재료집합 최고 단독(1.228)을 넘지 못했다. 즉 "u 축에서 기울기를
# 계단으로 바꾸는 것"은 이미 측정됐고 하중을 받지 못했다.
#
# 이 판이 바꾸는 것은 **조건화 변수의 집합**이다.
#
#   재료 2 의 표제 결과는 트리 자체가 아니라 **어느 변수가 조건화를 담는가**이다:
#     "The first finding is that in all cases (solo and joint) the most informative
#      factor is always the market excess return factor."
#     "the analysis is allowed to consider non-linear dependencies between factors
#      and stock returns"
#     "Limiting to max depth = 1" · "a single model capable of predicting
#      simultaneously n stocks is built" · "correlation information enters the
#      tree structure" · "all input variables and all possible split points are
#      evaluated and chosen in a greedy algorithm"
#     "Min for all split points  Sum_i ( y_i - prediction(y_i) )^2"
#   → 재료 2 는 **입력변수들을 경쟁시켜** 조건화 구조를 회수하는 절차이고, 그 절차가
#     내놓은 답이 '시장초과수익' 이다. 재료 2 가 가진 적 없는 입력변수가 하나 있다 —
#     재료 1 의 CID 충격 u. 그 변수를 재료 2 의 입력집합에 **추가**하는 것이 결합이다.
#
#   재료 1 은 그 위에서 **무엇을 재고 어느 부호로 쓰는지**를 전부 공급한다:
#     Eq.1  CID_t = (1/N) sum_i |R_it - R_MKT,t|   (VW 산업 >=10사 · R_MKT = 전 상장 VW)
#     Eq.2  d(CID_t) = g0 + g1*d(CID_{t-1}) + g2*CID_{t-1} + u_t   (잔차 u 가 operative)
#     Eq.3  R_it = a + beta*CID_t + e_t  ·  "two years of monthly excess returns"
#     단면  "I winsorize beta_CID at 1% and 99% percentiles"
#     방향  **사전 선언** — "Stocks with negative covariance with CID are riskier,
#           since they tend to fall when the risk of losing high-skill
#           industry-immobile jobs is large" (Q1 0.79% > Q5 0.30% · L/S -49bps t -3.19)
#     리밸  "I update estimates of beta_CID and rebalance portfolios every month"
#
#   결합 산출 — 입력집합 {mex, u} 위의 **깊이 2** joint 트리에서 나오는 한 칸의 대비:
#       A       = { d : mex_d <= c*_m }              1단 분기 (재료 2 의 표제 변수)
#       Delta_i = E[ r_i | A , u > c*_u ] - E[ r_i | A , u <= c*_u ]     2단 분기 (재료 1 의 변수)
#       Score_i = -Delta_i                            (부호 = 재료 1 의 사전 선언)
#     c*_m, c*_u 는 둘 다 **전 종목 SSE 합을 최소화하는 공통 임계값**(재료 2), 표준화 없음.
#
# =============================================================================
# 왜 이 형태인가 — 두 단독의 사인이 서로 다르고, 이 배치가 각각을 구조로 닫는다
# =============================================================================
#  ▸ 재료 1 단독(KR 충실구현 Grade F · CAGR 0.6%)의 사인 = **u 가 시장이다.**
#    사내 실측: cor(u, 시장) = +0.43(2022-26 +0.63) · 최대 u 달 = 2026-05(시장 +35%)
#    2025-10(+22%) 2026-04(+33%) — 분산 급등이 하락이 아니라 **반도체 주도 급등**에서
#    온다. 그래서 beta_CID 정렬이 시장베타 정렬로 변질됐다(L/S 일간 beta -0.39).
#    ★논문 자신은 이 성질을 갖지 않는다 — Table 5 의 5분위 시장로딩 Q1 1.07 / Q5 1.11,
#      **L/S 스프레드 0.04**, "Controlling for market beta does not have significant
#      effect on the CID premium". 즉 US 에서 공짜로 성립하던 시장중립성이 KR 에서
#      깨진 것이다. 직전 판은 이를 **선형 회귀 통제**로 복원하려 했고 PORT_t 1.209 에
#      그쳤다. 이 판은 통제하지 않는다 — **비교 자체를 같은 시장 국면 안으로 넣는다.**
#      대비되는 두 칸이 모두 A(같은 시장 잎) 안이므로 시장 방향이 설계상 정합되고,
#      남는 불일치는 잎 **내부** 변동뿐이다(계기 (c) 가 그 크기를 매월 잰다).
#  ▸ 재료 2 단독(PORT_t 1.11)의 사인 = **수준 발행.** 다수 잎의 예측 기대수익(잎 평균의
#    수준)을 스코어로 냈으므로 긴 창에서 그 종목의 장기 평균수익과 같아진다 — 조건부
#    구조를 회수해 놓고 무조건부 수준을 발행한 셈이다. 이 판의 산출은 **같은 창 같은
#    종목의 두 칸 평균의 차**라 수준 성분 mu_i 가 정의상 소거된다. 또 재료 2 는 방향을
#    주지 않아 단독 구현이 부호 선택을 거부했는데, 재료 1 이 사전 선언한 부호를 공급한다.
#  ▸ 직전 결합판(PORT_t 1.209)과의 차이 = **조건화 변수 집합.** 그 판의 입력은 {u}
#    하나였고 시장은 y 쪽 통제항이었다. 이 판의 입력은 {mex, u} 이고 시장은 **1단
#    분기변수**다 — 재료 2 가 실제로 보고한 배치 그대로. 계기 (a) 가 이 차이가 하중을
#    받는지를 단독으로 판정한다.
#
# =============================================================================
# 창 — 각 논문의 명시값이 그 논문이 정의한 객체를 지배한다
# =============================================================================
#  · **구조(임계값 c*_m, c*_u) = 재료 2 의 창 1,259 거래일.** 임계값은 전 종목이 공유하는
#    공통 모수이고, 재료 2 가 그 창(2015-01-05~2020-04-30 · "1,259 daily returns")에서
#    joint 로 추정한 바로 그 객체다.
#  · **민감도(잎 평균, 종목별) = 재료 1 의 창 24개월.** "two years of monthly excess
#    returns" — 종목별 민감도는 최근 2년이어야 한다는 것이 재료 1 의 명시값이다.
#  · 이 역할 분담은 통계적으로도 옳다: 공통 모수는 길게, 종목별 모수는 짧고 최근으로.
#    두 창 다 종점이 D(월말 형성일)이므로 PIT 는 어느 쪽에서도 열리지 않는다.
#  · 대가(정직 기록): 두 칸(A∧고u / A∧저u)의 유효 표본은 24개월 안 A 일수의 절반이다.
#    이 엔진은 검정력을 올렸다고 주장하지 않는다 — 주장은 **비교의 정합성**(같은 시장
#    국면 안에서만 대비)과 **수준 소거**뿐이고, 그 둘이 순위를 실제로 바꿨는지는 계기가 잰다.
#
# =============================================================================
# 미명시값 보충 — 전부 출처를 적는다 (성과를 보고 고른 값이 하나도 없다)
# =============================================================================
#  · AR(Eq.2) = **expanding window**. 논문은 전표본 1회 추정이나 C1 위반이라 PIT 가
#    논문 문자를 이긴다. burn-in 60개월 = RP_2301_09173_CID 선례 승계(같은 estimand).
#  · 창 유효 개월 >= 18/24, 일간 커버리지 75%(단기창)·60%(장기창) = 같은 선례 승계.
#    장기창 커버리지가 더 느슨한 이유: 그 창은 **공통 임계값**만 만들고 종목별 산출을
#    내지 않는다. 커버리지 요건은 전부 **과거** 데이터 요건이라 생존편의를 만들지 않는다.
#  · 분기 균형 하한 .BAL_MIN = 5%(양쪽). 재료 2 는 하한을 주지 않지만(sklearn 기본
#    min_samples_leaf=1), 이 판은 임계값을 5년 창에서 만들고 잎 평균을 2년 창에서
#    재므로 5년에서 1% 잎이 나오면 2년에서 빈 칸이 된다. 5% 는 재료 2 가 실제로 회수한
#    **joint** 임계값(-70bp ~ -90bp ≈ 일간 -0.5sd, 정규 하에서 약 30%)에서 한참 떨어진
#    자리라 상시 구속되지 않아야 하고, 구속 여부는 계기 (e) 로 매월 드러낸다.
#  · 칸 하한 = 일간 10관측 + **서로 다른 3개월**(양쪽). 3개월은 이 결합이 고치려는 병
#    (단일 월 지배)을 계단 쪽에서 재발시키지 않는 하한이다 — 어떤 한 달도 칸 평균의
#    1/3 을 넘지 못한다. 재료 2 의 joint 성립 최소 종목수는 논문 표본 그대로 5종.
#  · rf 미사용. 재료 1·2 다 초과수익을 쓰지만 (i) 산출이 같은 종목 두 칸 평균의 **차**라
#    rf 가 소거되고 (ii) 일간 rf(~1bp)는 mex 로 날짜를 **정렬**하는 순서를 사실상 바꾸지
#    않아 잎 소속이 불변이다. 시장 계열은 재료 1 이 Eq.1 에서 직접 만드는 R_MKT
#    (전 상장종목 VW)를 쓴다 — 두 논문의 시장 정의가 같고(VW all firms) 외부 캐시 의존 0.
#  · 산업분류·가중 = **전월말** Sector_Lv2(48군 — FF49 의 최근접 아날로그) / 전월말 시총.
#  · |일간 Ret| > 1.0 = 결측. KRX 가격제한폭 +-30% 하에서 한 세션에 불가능한 값이므로
#    액면/재상장 단위 아티팩트다. 전략 파라미터가 아니라 거래소 규칙 근거의 위생 조치.
#  · 논문의 $5 주가 / $50M 시총 필터 미적용 — 그 목적(microcap 제거)은 유니버스 치환
#    (K200∪KQ150)이 더 강하게 수행한다. 달러 문턱을 원화로 옮기면 근거 없는 수치가 된다.
#  · 종목수·비중 = 고정 축(top-25 롱온리 EW). 두 논문 규약이 충돌한다: 재료 2 는
#    포트폴리오가 아예 없고("only done for demonstration purposes and not for
#    statistical inference"), 재료 1 의 5분위 VW 는 레그당 ~70종이며 KR 숏 레그를
#    삼성전자 39% + 하이닉스 29% 가 지배했다(선례 실측). **리밸(월간)만 재료 1 명시값.**
#
# =============================================================================
# PIT (C1~C15) — 구조로 보장한다. detect_lookahead 통과를 근거로 삼지 않는다.
# =============================================================================
#  ▸ 구조 경계 1 — 창: 장기창은 `(ip-1258):ip`, 단기창은 `ymi in [fy-23, fy]` 이고
#    둘 다 `<= ip` 로 잘린다. ip 를 넘는 인덱스·음수 shift·lead 가 코드에 0건.
#  ▸ 구조 경계 2 — 가중/산업: `ymi_w = ymi - 1L` 한 줄로만 결합된다. 동월 시총·동월
#    섹터를 쓰는 경로가 **존재하지 않는다**(막는 검사가 아니라 표현 불가능한 배치).
#  ▸ 구조 경계 3 — AR: expanding 누적 교차곱이 k 까지만 더해진다. u_k 는 <=k 정보만.
#  ▸ 구조 경계 4 — 상태 이월 없음: 형성일 루프 반복이 서로 독립이다. 임계값·잎 평균·
#    시장베타가 전부 그 형성일의 창 안에서만 계산된다.
#  C1  : rolling/expanding 만. 전표본 mean/quantile/cov/lm 0건. winsorize 는 그 형성일
#        단면 **벡터** 내부에서만.
#  C2  : same-day 순환참조 없음. D 종가까지 쓰고 집행은 익 거래일(하네스).
#  C3  : 같은 기간 집계->적용 없음. 신호 컷오프(월 m 말) < 보유월(m+1) 시작.
#  C4  : 재무제표 패널 미사용.        C5 : 오버레이 없음(S0/S1 오버레이 금지 준수).
#  C6  : 유니버스 = 각 D 의 K200/KQ150 멤버십(PIT 시변). 최종 명부 주입 없음.
#  C7  : shift(-N)·lead()·수동 미래 인덱싱 0건. shift 는 전부 +1(과거 방향).
#  C9  : DD/VT 미사용.
#  C10 : 유동성 = D **직전 20 거래일** 평균 거래대금. `(ip-20):(ip-1)` 로 당일 배제.
#  C11 : 외부 매크로 0건(rf·FRED·팩터 캐시·BM_DT 미사용).
#  C13 : Factor DB 미소비 -> 정렬 대상 없음. 부호는 재료 1 의 **사전 선언**이지 사후 반전 아님.
#  C15 : Factor DB parquet 직접 load 0건.
#  ★rawdata 의 Market 열 미사용(KOSDAQ 0건 날조 — 사내 기록). 시장 구분은 멤버십 플래그로만.
#
# ===== 산출 =====
#   FACTORS(Date, Ticker, Score) — Score = -Delta. 클수록 롱.
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
  stop(sprintf("[COMBO_XSTATE] RAWDATA 열 부족: %s",
               paste(setdiff(.RQ, names(RAWDATA)), collapse = ", ")))

# =============================================================================
# 0. 상수 — 전부 출처 표기
# =============================================================================
# ▸ 재료 1 (Pinchuk 2301.09173) 명시값
.MIN_FIRMS   <- 10L        # "industries with at least 10 firms"
.WIN_M       <- 24L        # "two years of monthly excess returns"
.WINS_LO     <- 0.01       # "winsorize beta_CID at 1% and 99% percentiles"
.WINS_HI     <- 0.99
# ▸ 재료 2 (Polimenis 2007.08115) 명시값
.T_LONG      <- 1259L      # "1,259 daily returns" — 공통 구조(임계값) 추정 창
.MIN_STK     <- 5L         # 논문 joint 트리 표본 = 5종
# ▸ 수치 타당성 하한 (성과에서 오지 않은 값 — 위 "미명시값 보충" 에 근거)
.BAL_MIN     <- 0.05       # 분기 양쪽 최소 관측 비중(장기창)
.LEAF_MO_L   <- 6L         # 장기창 u 분기 양쪽 최소 개월
.MIN_CELL_D  <- 10L        # 단기창 칸별 최소 일간 관측(종목별)
.MIN_CELL_MO <- 3L         # 단기창 칸별 최소 개월 — 단일 월 지배 차단
# ▸ 사내 선례 승계 (RP_2301_09173_CID — 같은 estimand 의 기존 구현)
.AR_BURN     <- 60L        # AR expanding burn-in (개월)
.MIN_MO      <- 18L        # 단기창 24개월 중 유효 >= 18
.COV_S       <- 0.75       # 단기창 일간 커버리지 하한 (= 18/24)
.COV_L       <- 0.60       # 장기창 커버리지 하한 (구조 추정 전용 — 종목별 산출 없음)
.RET_CAP     <- 1.0        # |일간수익| > 100% = 데이터 아티팩트 (KRX 가격제한폭 +-30%)
# ▸ 축(도훈 고정)
.LIQ         <- 2e8        # adv20(t-1) 하한 (KRW)
.LIQ_WIN     <- 20L        # 거래일 (D 직전 20 거래일, 종점 = D-1)
.START       <- as.Date("2005-01-01")

.tru <- function(x) !is.na(x) & (x != 0)          # 논리/0-1 혼재 방어
.t0  <- Sys.time()

# 안전 헬퍼 — 전부 **벡터**만 받는다(DT 열 직접 전달 금지: lookahead_detector C1b 회피)
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

# ---- 재료 2 의 joint depth=1 스캔 (원문 목적함수와 정확히 동치) ---------------
#   "Min for all split points  Sum_i ( y_i - prediction(y_i) )^2"
#   SSE(k) = sum_i [ TSS_i - CS_i(k)^2/CN_i(k) - (TS_i-CS_i(k))^2/(TN_i-CN_i(k)) ]
#   TSS_i 는 k 에 무관 -> SSE 최소화 = 아래 gv 최대화. **종목별 표준화는 하지 않는다**
#   (재료 2 의 joint 트리가 그렇고 'dominant stock' 이 그 설계의 성질이다).
#   ★Xs/Ms 를 월 단위로 rowsum 해 넣어도 **정확**하다: 잎 통계는 (일간 합, 일간 개수)로만
#     정해지고 rowsum 이 그 둘을 보존한다. 그래서 일간 분기(mex)와 월간 분기(u)의
#     gain 이 같은 척도 위에 있고 직접 비교된다(계기 (f) 의 근거).
.jsplit <- function(Xs, Ms, v, min_row, wrow = NULL, min_w = 0) {
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
  gr <- TS * TS / TN; gr[!is.finite(gr)] <- 0     # 무분기(root) 기준값
  ki <- seq_len(n)
  ok <- c(vs[-n] < vs[-1L], FALSE) & (ki >= min_row) & ((n - ki) >= min_row)
  if (!is.null(wrow)) {
    cw <- cumsum(as.numeric(wrow)[o]); tw <- cw[n]
    ok <- ok & (cw >= min_w) & ((tw - cw) >= min_w)
  }
  if (!any(ok)) return(NULL)
  gv[!ok] <- -Inf
  k <- as.integer(which.max(gv))
  if (!is.finite(gv[k])) return(NULL)
  list(cut = as.numeric(vs[k] + vs[k + 1L]) / 2, k = k, n_row = n,
       gain = as.numeric(gv[k] - sum(gr)))
}

if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]

# =============================================================================
# 1. 일간 기저 패널 — 전월말 시총/산업라벨 부착 (구조 경계 2) + 일간 VW 시장
# =============================================================================
# ★유니버스 치환(K200∪KQ150)은 **정렬 대상(test asset)** 에만 걸린다. CID·시장은 재료 1 이
#   "value-weighted market return across all firms" 라 한 거시 변수라 전 상장종목에서 만든다.
.AD  <- data.table(Date = sort(unique(RAWDATA$Date)))
.AD[, ymi := year(Date) * 12L + month(Date)]
.MEA <- .AD[, .(me = max(Date)), by = ymi]$me                   # 시장 전체 월말 거래일
# ★섹터 라벨을 여기서 거르지 않는다 — R_MKT 는 "all firms" 이고 산업 라벨은 산업
#   포트폴리오(Eq.1 의 산업 다리)에만 필요하다. 여기서 걸면 시장 다리가 논문보다 좁아진다.
.EOM <- RAWDATA[Date %in% .MEA & is.finite(Size) & Size > 0,
                .(Ticker, ymi_w = year(Date) * 12L + month(Date),
                  w = as.numeric(Size), ind = Sector_Lv2)]
.EOM <- unique(.EOM, by = c("Ticker", "ymi_w"))
rm(.AD, .MEA); gc(verbose = FALSE)
if (!nrow(.EOM)) stop("[COMBO_XSTATE] 월말 시총 관측 0건 — Size 확인")
if (all(is.na(.EOM$ind)))
  stop("[COMBO_XSTATE] 월말 산업라벨 0건 — Sector_Lv2 확인 (Eq.1 산업 다리 불가)")

.DD <- RAWDATA[is.finite(Ret), .(Date, Ticker, rr = as.numeric(Ret))]
.DD <- .DD[abs(rr) <= .RET_CAP]            # rr 은 위에서 finite 로 걸러져 NA 첨자가 없다
.DD[, ymi := year(Date) * 12L + month(Date)]
.DD[, ymi_w := ymi - 1L]                                        # ★전월말 (동월 경로 없음)
.DD[.EOM, on = .(Ticker, ymi_w), c("w", "ind") := .(i.w, i.ind)]
.DD <- .DD[is.finite(w) & w > 0]              # 가중치만 요구 — 산업 라벨은 IPF 에서만 건다
if (!nrow(.DD)) stop("[COMBO_XSTATE] 전월말 가중치 결합 후 0행 — 월말 격자 확인")

MKTD <- .DD[, .(r_mkt = sum(w * rr) / sum(w)), by = Date]       # 일간 VW 전 상장종목
setorder(MKTD, Date)

# =============================================================================
# 2. 재료 1 Eq.1 — **월간** CID (상태변수는 논문 그대로 월간이다)
# =============================================================================
# 일간 CID 는 산업 일간 변동성 계열이지 논문이 장기실업으로 검증한 변수가 아니다
# ("CID strongly predicts long-term unemployment but has little relation with its
#  short-term component"). estimand 를 건드리지 않는다.
MON <- .DD[, .(mret = prod(1 + rr) - 1, w = w[1], ind = ind[1]), by = .(Ticker, ymi)]
rm(.DD); gc(verbose = FALSE)

IPF  <- MON[!is.na(ind), .(r_ind = sum(w * mret) / sum(w), nf = .N),
            by = .(ymi, ind)][nf >= .MIN_FIRMS]
MKTM <- MON[, .(r_mktm = sum(w * mret) / sum(w)), by = ymi]
CIDM <- merge(IPF[, .(ymi, r_ind)], MKTM, by = "ymi")
CIDM <- CIDM[, .(CID = mean(abs(r_ind - r_mktm)), n_ind = .N), by = ymi]
setorder(CIDM, ymi)
rm(IPF); gc(verbose = FALSE)
if (nrow(CIDM) < (.AR_BURN + .WIN_M + 12L))
  stop(sprintf("[COMBO_XSTATE] 월간 CID %d개월 — 표본 부족", nrow(CIDM)))
cat(sprintf("[COMBO_XSTATE] Eq.1 월간 CID %d개월 · 산업수 중앙 %.0f · 평균 %.4f sd %.4f\n",
            nrow(CIDM), .med(CIDM$n_ind), mean(CIDM$CID), stats::sd(CIDM$CID)))

# =============================================================================
# 3. 재료 1 Eq.2 — CID 충격 u_t (expanding window AR · PIT 보정)
# =============================================================================
#   expanding OLS 를 누적 교차곱으로 정확히 구현한다(lm 반복과 수치 동일 · O(n)).
#   구조 경계 3: 각 k 의 계수는 1..k 만 더한 X'X, X'y 에서 나온다.
CIDM[, dC := CID - shift(CID)]
CIDM[, `:=`(dC_l1 = shift(dC), C_l1 = shift(CID))]
CIDM[, u := NA_real_]
.rw <- which(is.finite(CIDM$dC) & is.finite(CIDM$dC_l1) & is.finite(CIDM$C_l1))
if (length(.rw) < (.AR_BURN + .WIN_M))
  stop("[COMBO_XSTATE] AR 적합 가능 개월 부족")
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
  stop("[COMBO_XSTATE] CID 충격 u 유효 개월 부족 — AR 적합 실패")
.uok <- CIDM[is.finite(u)]
cat(sprintf("[COMBO_XSTATE] Eq.2 충격 u: 유효 %d개월 · sd %.5f · 1-lag 자기상관 %+.3f (논문 US: -0.05)\n",
            nrow(.uok), stats::sd(.uok$u), .sp(.uok$u[-1L], .uok$u[-nrow(.uok)])))
rm(.uok)

# =============================================================================
# 4. 테스트 자산 — K200∪KQ150 일간 수익 wide + 일별 u/mex 정렬
# =============================================================================
.tk <- unique(RAWDATA[.tru(K200) | .tru(KQ150), Ticker])
if (!length(.tk)) stop("[COMBO_XSTATE] K200/KQ150 멤버십 0건 — RAWDATA 확인")

# 격자 = 시장이 정의되고 **u 가 유효한** 거래일만 (두 분기변수가 모두 살아있는 날)
.uofm <- CIDM[is.finite(u), .(ymi, u)]
.GG <- data.table(Date = MKTD$Date, r_mkt = MKTD$r_mkt)
.GG[, ymi := year(Date) * 12L + month(Date)]
.GG <- merge(.GG, .uofm, by = "ymi")
setorder(.GG, Date)
if (nrow(.GG) < (.T_LONG + 250L))
  stop(sprintf("[COMBO_XSTATE] 유효 거래일 %d — 장기창 %d 에 못 미침", nrow(.GG), .T_LONG))

.rs <- RAWDATA[Ticker %chin% .tk & Date %in% .GG$Date & is.finite(Ret),
               .(Date, Ticker, r = as.numeric(Ret))]
.rs <- .rs[abs(r) <= .RET_CAP]             # r 은 위에서 finite 로 걸러져 NA 첨자가 없다
.nd <- sum(duplicated(.rs, by = c("Ticker", "Date")))
if (.nd > 0L) {
  cat(sprintf("[COMBO_XSTATE] (Date,Ticker) 중복 %d행 — 첫 행만 남긴다\n", .nd))
  .rs <- unique(.rs, by = c("Ticker", "Date"))
}
.RW <- dcast(.rs, Date ~ Ticker, value.var = "r")
setorder(.RW, Date)
.rdt  <- .RW$Date
RETD  <- as.matrix(.RW[, -1L, with = FALSE])
.tick <- colnames(RETD)
rm(.RW, .rs); gc(verbose = FALSE)
.rym <- year(.rdt) * 12L + month(.rdt)

setkey(.GG, Date)
.mvec <- .GG[.(.rdt), r_mkt]
.uday <- .GG[.(.rdt), u]
if (anyNA(.mvec) || anyNA(.uday))
  stop("[COMBO_XSTATE] 시장/충격 계열 정렬 실패 — 격자 불일치")

# 월간 wide (계기 (g) 전용 — 재료 1 Eq.3 원판을 같은 창·같은 유니버스에서 재현)
.MW  <- dcast(MON[Ticker %chin% .tick, .(ymi, Ticker, mret)], ymi ~ Ticker, value.var = "mret")
setorder(.MW, ymi)
.mym <- .MW$ymi
.MWm <- as.matrix(.MW[, -1L, with = FALSE])
# ★열 정렬은 **이름으로** 채운다. match(.tick, colnames) 은 월간 패널에 없는 종목에서
#   NA 첨자를 만들고, NA 첨자 인덱싱은 진단 한 줄 때문에 라운드를 통째로 죽일 수 있다.
RETM <- matrix(NA_real_, nrow(.MWm), length(.tick), dimnames = list(NULL, .tick))
.hit <- intersect(.tick, colnames(.MWm))
if (length(.hit)) RETM[, .hit] <- .MWm[, .hit, drop = FALSE]
rm(.MW, .MWm); gc(verbose = FALSE)

.SEC <- unique(.EOM[, .(Ticker, ymi_w, ind)], by = c("Ticker", "ymi_w"))
setkey(.SEC, ymi_w, Ticker)
rm(.EOM); gc(verbose = FALSE)

cat(sprintf("[COMBO_XSTATE] 테스트 자산 %d거래일 x %d종 (%s ~ %s) · 일간 결측 %.1f%%\n",
            nrow(RETD), ncol(RETD), as.character(min(.rdt)), as.character(max(.rdt)),
            100 * mean(is.na(RETD))))

# =============================================================================
# 5. 형성일(월말 거래일) · 유동성 창 · 자격
# =============================================================================
.GD   <- data.table(Date = .rdt, ymi = .rym)
.ME   <- .GD[, .(Date = max(Date)), by = ymi]
setorder(.ME, Date)
.FORM <- .ME[Date >= .START, Date]
if (!length(.FORM)) stop("[COMBO_XSTATE] 형성일 0건 — RAWDATA 날짜 범위 확인")

.LW <- rbindlist(lapply(seq_along(.FORM), function(k) {
  D  <- .FORM[k]
  ip <- match(D, .rdt)
  if (is.na(ip) || (ip - .LIQ_WIN) < 1L) return(NULL)
  data.table(Date = .rdt[(ip - .LIQ_WIN):(ip - 1L)], FormDate = D)   # 종점 = D-1 (C10)
}), use.names = TRUE)
if (!nrow(.LW)) stop("[COMBO_XSTATE] 유동성 창 구성 실패 — 거래일 수 부족")
.FORM <- .FORM[.FORM %in% unique(.LW$FormDate)]
.fym  <- year(.FORM) * 12L + month(.FORM)

.rdq <- RAWDATA[Date %in% unique(c(.LW$Date, .FORM)), .(Date, Ticker, Close, Vol, K200, KQ150)]
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
# 6. 형성일 루프
#    (i)  장기창 1,259일: 전 종목 SSE 합으로 mex 공통 임계값 c*_m  [재료 2]
#    (ii) 그 A 잎 안에서 같은 기준으로 u 공통 임계값 c*_u          [재료 2 x 재료 1]
#    (iii)단기창 24개월: 종목별 두 칸 평균의 차 Delta               [재료 1]
#    (iv) 단면 1%/99% winsorize -> Score = -Delta                    [재료 1]
# =============================================================================
.OUT  <- vector("list", length(.FORM))
.LOG  <- vector("list", length(.FORM))
.skip <- 0L

for (kk in seq_along(.FORM)) {
  D  <- .FORM[kk]
  fy <- .fym[kk]
  ip <- match(D, .rdt)
  if (is.na(ip) || ip < .T_LONG) { .skip <- .skip + 1L; next }

  wl <- (ip - .T_LONG + 1L):ip                                  # 장기창 (종점 = D)
  ws <- which(.rym >= (fy - .WIN_M + 1L) & .rym <= fy)
  ws <- ws[ws <= ip]                                            # 단기창 (종점 = D)
  nS <- length(ws)
  if (nS < (.MIN_MO * 10L) || length(unique(.rym[ws])) < .MIN_MO) { .skip <- .skip + 1L; next }

  cand <- .ELG[.(D), Ticker, nomatch = 0L]
  cand <- intersect(cand, .tick)
  if (length(cand) < .MIN_STK) { .skip <- .skip + 1L; next }
  ci <- match(cand, .tick)

  # ── (i) 구조 추정용 종목집합 = 장기창 커버리지 충족 (종목별 산출 없음) ──
  YL   <- RETD[wl, ci, drop = FALSE]
  covL <- colSums(!is.na(YL))
  kL   <- covL >= (.COV_L * .T_LONG)
  if (sum(kL) < .MIN_STK) { .skip <- .skip + 1L; next }
  nStr <- sum(kL)                                               # 구조 추정 종목수
  YL <- YL[, kL, drop = FALSE]
  ML <- matrix(as.numeric(!is.na(YL)), .T_LONG, ncol(YL))
  XL <- YL; XL[is.na(XL)] <- 0
  rm(YL)

  mL <- .mvec[wl]; uL <- .uday[wl]; yL <- .rym[wl]
  TSv <- colSums(XL); TNv <- colSums(ML)
  gRt <- TSv * TSv / TNv; gRt[!is.finite(gRt)] <- 0
  tssL <- sum(XL * XL) - sum(gRt)

  # 1단 분기 = mex (재료 2 의 표제 변수). 후보 = 전 분기점 greedy.
  sm <- .jsplit(XL, ML, mL, min_row = as.integer(ceiling(.BAL_MIN * .T_LONG)))
  if (is.null(sm)) { .skip <- .skip + 1L; next }
  cm <- sm$cut

  # (f) 계기 = 재료 2 의 표제 주장을 KR 에서 재는 자리:
  #     같은 창·같은 종목·같은 척도에서 u 를 1단 분기로 썼다면 얼마나 벌었나.
  #     (월 단위 rowsum 은 잎 통계 (일간합, 일간개수)를 보존하므로 gain 이 직접 비교된다.)
  MSa <- rowsum(XL, yL, reorder = TRUE); MNa <- rowsum(ML, yL, reorder = TRUE)
  yA  <- as.integer(rownames(MSa))
  uA  <- uL[match(yA, yL)]
  wA  <- as.numeric(rowsum(rep(1, .T_LONG), yL, reorder = TRUE))
  su0 <- .jsplit(MSa, MNa, uA, min_row = .LEAF_MO_L,
                 wrow = wA, min_w = .BAL_MIN * .T_LONG)
  rm(MSa, MNa)

  # ── (ii) A 잎(mex <= c*_m) 안에서 u 공통 임계값 ──
  inA <- mL <= cm
  nA  <- sum(inA)
  if (nA < (2L * .MIN_CELL_D)) { .skip <- .skip + 1L; next }
  MSA <- rowsum(XL[inA, , drop = FALSE], yL[inA], reorder = TRUE)
  MNA <- rowsum(ML[inA, , drop = FALSE], yL[inA], reorder = TRUE)
  yAA <- as.integer(rownames(MSA))
  uAA <- uL[match(yAA, yL)]
  wAA <- as.numeric(rowsum(rep(1, nA), yL[inA], reorder = TRUE))
  su <- .jsplit(MSA, MNA, uAA, min_row = .LEAF_MO_L,
                wrow = wAA, min_w = .BAL_MIN * nA)
  rm(MSA, MNA, XL, ML)
  if (is.null(su)) { .skip <- .skip + 1L; next }
  cu <- su$cut

  # ── (iii) 단기창 24개월 · 종목별 두 칸 평균의 차 ──
  YS <- RETD[ws, ci, drop = FALSE]
  kS <- (colSums(!is.na(YS)) >= (.COV_S * nS)) & !is.na(YS[nS, ])
  if (sum(kS) < .MIN_STK) { .skip <- .skip + 1L; next }
  YS <- YS[, kS, drop = FALSE]
  nmS <- cand[kS]
  MS <- matrix(as.numeric(!is.na(YS)), nS, ncol(YS))
  XS <- YS; XS[is.na(XS)] <- 0
  rm(YS)

  mS <- .mvec[ws]; uS <- .uday[ws]; yS <- .rym[ws]
  aS <- mS <= cm; hS <- uS > cu
  c1 <- aS & hS; c2 <- aS & !hS                    # A 잎: 고-u / 저-u  (스코어)
  b1 <- !aS & hS; b2 <- !aS & !hS                  # B 잎: 위약(placebo)
  if (sum(c1) < .MIN_CELL_D || sum(c2) < .MIN_CELL_D ||
      length(unique(yS[c1])) < .MIN_CELL_MO ||
      length(unique(yS[c2])) < .MIN_CELL_MO) { .skip <- .skip + 1L; next }

  n1 <- colSums(MS[c1, , drop = FALSE]); s1 <- colSums(XS[c1, , drop = FALSE])
  n2 <- colSums(MS[c2, , drop = FALSE]); s2 <- colSums(XS[c2, , drop = FALSE])
  nb1 <- colSums(MS[b1, , drop = FALSE]); sb1 <- colSums(XS[b1, , drop = FALSE])
  nb2 <- colSums(MS[b2, , drop = FALSE]); sb2 <- colSums(XS[b2, , drop = FALSE])

  dl   <- s1 / n1 - s2 / n2                                    # Delta (A 잎)
  good <- is.finite(dl) & n1 >= .MIN_CELL_D & n2 >= .MIN_CELL_D
  if (sum(good) < .MIN_STK) { .skip <- .skip + 1L; next }

  # ── (iv) 단면 winsorize 1%/99% (재료 1 명시) + 사전 선언 부호 ──
  dv <- as.numeric(dl[good])
  qq <- stats::quantile(dv, c(.WINS_LO, .WINS_HI), na.rm = TRUE, names = FALSE)
  dw <- pmin(pmax(dv, qq[1]), qq[2])
  sc <- -dw                                                    # 고민감 = 저수익
  tk <- nmS[good]
  .OUT[[kk]] <- data.table(Date = D, Ticker = tk, Score = sc)

  # ── 반증 계기 ─────────────────────────────────────────────────────────────
  # (a) 시장 조건화가 하중을 받는가 — 시장 분기를 빼고 u 만으로 잰 판(직전 결합판의 축)
  d_un <- (s1 + sb1) / (n1 + nb1) - (s2 + sb2) / (n2 + nb2)
  # (b) 위약 — 같은 대비를 **B 잎**(mex > c*_m)에서 잰 판
  d_bn <- rep(NA_real_, length(dl))
  if (sum(b1) >= .MIN_CELL_D && sum(b2) >= .MIN_CELL_D)
    d_bn <- ifelse(nb1 >= .MIN_CELL_D & nb2 >= .MIN_CELL_D, sb1 / nb1 - sb2 / nb2, NA_real_)
  # (c) 두 칸의 시장 정합도 — 같은 A 잎 안이면 이 격차가 작아야 한다
  sdm  <- stats::sd(mS)
  dmex <- if (is.finite(sdm) && sdm > 0) (mean(mS[c1]) - mean(mS[c2])) / sdm else NA_real_
  dmx0 <- if (is.finite(sdm) && sdm > 0) (mean(mS[hS]) - mean(mS[!hS])) / sdm else NA_real_
  # 시장베타(단기창) · 창 무조건부 평균
  Sm  <- colSums(MS * mS); Smm <- colSums(MS * mS^2); Smy <- colSums(XS * mS)
  ny  <- colSums(MS);      Sy  <- colSums(XS)
  dnm <- ny * Smm - Sm * Sm
  b_m <- ifelse(is.finite(dnm) & dnm > 0, (ny * Smy - Sm * Sy) / dnm, NA_real_)
  mu_w <- ifelse(ny > 0, Sy / ny, NA_real_)
  # (g) 재료 1 Eq.3 원판: 같은 24개월 · 같은 유니버스의 월간 단변량 OLS beta_CID
  wmo  <- sort(unique(yS))
  mi   <- match(wmo, .mym)
  b_ol <- rep(NA_real_, length(dl))
  if (!anyNA(mi)) {
    Ym  <- RETM[mi, ci, drop = FALSE][, kS, drop = FALSE]
    Mm  <- matrix(as.numeric(!is.na(Ym)), nrow(Ym), ncol(Ym)); Xm <- Ym; Xm[is.na(Xm)] <- 0
    uwm <- .uday[ws][match(wmo, yS)]
    n2m <- colSums(Mm); Su <- colSums(Mm * uwm); Suu <- colSums(Mm * uwm^2)
    Sy2 <- colSums(Xm); Suy <- colSums(Xm * uwm)
    d2m <- n2m * Suu - Su * Su
    b_ol <- ifelse(is.finite(d2m) & d2m > 0 & n2m >= .MIN_MO,
                   (n2m * Suy - Su * Sy2) / d2m, NA_real_)
  }
  # (h) 롱 상위 25 의 최대 섹터 점유율 — 재료 1 의 기전(산업 재배치)이 보이는가
  sec_sh <- NA_real_
  if (length(sc) >= 25L) {
    tp <- tk[order(-sc)][seq_len(25L)]
    sv <- .SEC[.(fy - 1L, tp), ind]
    sv <- sv[!is.na(sv)]
    if (length(sv) >= 10L) sec_sh <- 100 * max(table(sv)) / length(sv)
  }
  sdmL <- stats::sd(mL); sduL <- stats::sd(uAA)

  .LOG[[kk]] <- data.table(
    Date     = D,
    n_stock  = sum(good), n_day_s = nS, n_str = nStr,
    thr_m_sd = if (is.finite(sdmL) && sdmL > 0) as.numeric(cm / sdmL) else NA_real_,
    frac_A   = 100 * nA / .T_LONG,                       # (e) 시장 잎의 balance
    thr_u_sd = if (is.finite(sduL) && sduL > 0) as.numeric(cu / sduL) else NA_real_,
    frac_hi  = 100 * (su$n_row - su$k) / su$n_row,       # (e) A 안 고-u 잎 개월 비중
    gain_m   = if (is.finite(tssL) && tssL > 0) 100 * sm$gain / tssL else NA_real_,
    gain_u0  = if (!is.null(su0) && is.finite(tssL) && tssL > 0) 100 * su0$gain / tssL else NA_real_,
    n_c1     = sum(c1), n_c2 = sum(c2),
    mo_c1    = length(unique(yS[c1])), mo_c2 = length(unique(yS[c2])),
    rho_unc  = .sp(sc, -as.numeric(d_un[good])),         # (a) 시장 조건화의 하중
    rho_pla  = .sp(sc, -as.numeric(d_bn[good])),         # (b) 위약(B 잎)
    dmex     = dmex, dmex0 = dmx0,                       # (c) 칸 간 시장 정합도
    rho_bm   = .sp(sc, b_m[good]),                       # (c) 시장베타 오염 — 조건화 후
    rho_bm0  = .sp(-as.numeric(d_un[good]), b_m[good]),  # (c) 양성 대조 — 조건화 전
    rho_lvl  = .sp(sc, mu_w[good]),                      # (d) 수준 별칭(재료 2 단독의 사인)
    rho_ols  = .sp(dv, b_ol[good]),                      # (g) 재료 1 원판과 같은 것인가
    sec_sh   = sec_sh)                                   # (h) 산업 편중
}

FACTORS <- rbindlist(Filter(Negate(is.null), .OUT), use.names = TRUE)
if (!nrow(FACTORS))
  stop("[COMBO_XSTATE] FACTORS 0행 — 장기창/칸 하한/커버리지 확인")
setorder(FACTORS, Date, -Score)

# =============================================================================
# 7. 회수된 구조 + 반증 계기 보고
# =============================================================================
LOGDT <- rbindlist(Filter(Negate(is.null), .LOG), use.names = TRUE)
setorder(LOGDT, Date)
LOGDT[, thr_jump := abs(thr_m_sd - shift(thr_m_sd))]
LOGDT[, yr := year(Date)]

.byyr <- LOGDT[, .(n_m = .N, n_stk = as.integer(.med(n_stock)),
                   fA = round(.med(frac_A)), thm = round(.med(thr_m_sd), 2),
                   thu = round(.med(thr_u_sd), 2),
                   c1 = as.integer(.med(n_c1)), c2 = as.integer(.med(n_c2)),
                   r_un = round(.med(rho_unc), 2), r_pl = round(.med(rho_pla), 2),
                   r_bm = round(.med(rho_bm), 2), r_b0 = round(.med(rho_bm0), 2),
                   r_lv = round(.med(rho_lvl), 2)), by = yr]
setorder(.byyr, yr)
cat("[COMBO_XSTATE] 연도별 depth=2 joint 트리 (1단 = mex · 2단 = Eq.2 충격 u · y = 일간 종목수익):\n")
cat("      연도 | 월수 종목  A잎%  c*m(sd) c*u(sd)  칸(고u/저u)  rho(무조건화) rho(위약)  rho(bmkt)[조건화전]  rho(수준)\n")
for (i in seq_len(nrow(.byyr)))
  cat(sprintf("      %4d |  %2d  %3d  %4.0f%%  %+6.2f %+6.2f   %3d/%3d      %+6.2f     %+6.2f     %+6.2f [%+6.2f]     %+6.2f\n",
              .byyr$yr[i], .byyr$n_m[i], .byyr$n_stk[i], .byyr$fA[i], .byyr$thm[i], .byyr$thu[i],
              .byyr$c1[i], .byyr$c2[i], .byyr$r_un[i], .byyr$r_pl[i],
              .byyr$r_bm[i], .byyr$r_b0[i], .byyr$r_lv[i]))

.nmn  <- FACTORS[, .N, by = Date]
.scv  <- as.numeric(FACTORS[["Score"]])   # ★벡터로 뽑아 잰다(quantile(DT$col) = C1b 오탐)
.bindm <- 100 * mean(LOGDT$frac_A <= (100 * .BAL_MIN + 0.5) |
                     LOGDT$frac_A >= (100 * (1 - .BAL_MIN) - 0.5))
.winu <- 100 * mean(is.finite(LOGDT$gain_u0) & LOGDT$gain_u0 > LOGDT$gain_m)
cat(sprintf(paste0(
  "[COMBO_XSTATE] combination — 재료2 의 조건화 절차(입력변수 경쟁 · joint depth 트리 ·\n",
  "  전 종목 SSE 합의 공통 임계값 · 표준화 없음)에 재료1 이 갖고 온 입력변수 u 를 더한\n",
  "  깊이 2 구조다. 1단 = mex(재료2 의 표제 답), 2단 = u(재료1 의 상태변수), 산출은\n",
  "  **A 잎 안 두 칸 평균의 차** Delta = E[r|A,u>c*u] - E[r|A,u<=c*u] · Score = -Delta\n",
  "  (부호 = 재료1 사전 선언 — 고민감 = 저수익). 구조 창 = 재료2 의 %d거래일,\n",
  "  민감도 창 = 재료1 의 %d개월. 시장은 통제항이 아니라 **분기변수**다.\n",
  "  형성 %d개월(skip %d) · %s ~ %s · FACTORS %s행 · 월 종목 중앙 %d (min %d / max %d)\n",
  "  ── 반증 계기 (전 기간 중앙값) ───────────────────────────────────────────────\n",
  "  (a) rho(Score, 시장분기 없는 u-대비) %+5.2f\n",
  "      → +1 근방이면 1단 분기가 무하중 = 이 판은 직전 결합판(PORT_t 1.209)의 재실행이다.\n",
  "  (b) rho(Score, 위약 = B잎에서 잰 같은 대비) %+5.2f\n",
  "      → +1 근방이면 기전이 상태-특이적이지 않다 = 'A 잎에서 재라' 는 주장이 기각된다.\n",
  "  (c) 두 칸의 시장 격차 %+.2f sd  [조건화 전 %+.2f sd] · rho(Score, 시장베타) %+5.2f\n",
  "      [양성 대조 = 조건화 전 %+5.2f]\n",
  "      → 격차가 조건화 전과 같은 크기로 남거나 rho 두 개가 같으면 CID 단독을 죽인\n",
  "        역베타 채널이 재현된 것이다(조건화 후만 0 에 붙어야 수술이 성립).\n",
  "  (d) rho(Score, 창 무조건부 평균) %+5.2f\n",
  "      → ±1 쪽이면 수준(장기 모멘텀) 별칭 — 재료2 단독의 사인이 살아남은 것.\n",
  "  (e) c*_m %+.2f sd(mex) · A 잎 %.0f%% (균형하한 %.0f%% 구속 %.0f%%) · c*_u %+.2f sd(u)\n",
  "      A 안 고-u 잎 %.0f%%월 · 단기창 칸 %d/%d일 %d/%d개월 · |c*_m 변화| 중앙 %.2f sd\n",
  "      → 재료2 는 임계값이 **꼬리**에 선다고 보고한다(joint -70~-90bp ≈ -0.5sd). c*_m 이\n",
  "        중앙값 근처면 회수된 것이 꼬리 구조가 아니고, 겹치는 창인데 c*_m 이 튀면 표본 산물.\n",
  "  (f) 재료2 표제 주장 검정 — 1단 분기 설명력: mex %.2f%% vs u %.2f%% (u 승 %.0f%% 개월)\n",
  "      → 재료2 는 'in all cases the most informative factor is always the market excess\n",
  "        return factor' 라 했다. KR 에서 u 가 자주 이기면 그 주장이 KR 에서 깨진 것이고,\n",
  "        1단/2단 순서를 고정한 이 설계의 전제가 약해진다(관측 가능한 반증).\n",
  "  (g) rho(Delta, 재료1 Eq.3 원판 월간 OLS beta) %+5.2f\n",
  "      → +1 근방이면 추정 구조가 무하중 = CID 단독의 재실행이고 결합이 아니다.\n",
  "  (h) 롱 상위25 의 최대 섹터 점유율 %.0f%%\n",
  "      → 재료1 의 기전은 '재배치 국면의 산업' 이다. 편중이 **없으면** 잡은 것이 그 기전이\n",
  "        아니다 — 이 계기만 '작으면 기각' 이다.\n",
  "  ── 구조 요약 ────────────────────────────────────────────────────────────────\n",
  "  Score = -Delta (중앙 %.2fbp · IQR %.2f~%.2fbp)\n",
  "  ★러너 호출: portfolio_spec = list(construction=\"top_n_long\", weighting=\"ew\",\n",
  "                                    rebalance=\"monthly\", n_long=25, n_max=25)\n",
  "              commission_paper = NULL (양 논문 비용 무명시) · %.1f분\n"),
  .T_LONG, .WIN_M,
  nrow(LOGDT), .skip,
  as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date)),
  format(nrow(FACTORS), big.mark = ","),
  as.integer(.med(.nmn$N)), min(.nmn$N), max(.nmn$N),
  .med(LOGDT$rho_unc),
  .med(LOGDT$rho_pla),
  .med(LOGDT$dmex), .med(LOGDT$dmex0), .med(LOGDT$rho_bm), .med(LOGDT$rho_bm0),
  .med(LOGDT$rho_lvl),
  .med(LOGDT$thr_m_sd), .med(LOGDT$frac_A), 100 * .BAL_MIN, .bindm, .med(LOGDT$thr_u_sd),
  .med(LOGDT$frac_hi), as.integer(.med(LOGDT$n_c1)), as.integer(.med(LOGDT$n_c2)),
  as.integer(.med(LOGDT$mo_c1)), as.integer(.med(LOGDT$mo_c2)), .med(LOGDT$thr_jump),
  .med(LOGDT$gain_m), .med(LOGDT$gain_u0), .winu,
  .med(LOGDT$rho_ols),
  .med(LOGDT$sec_sh),
  1e4 * stats::median(.scv),
  1e4 * as.numeric(stats::quantile(.scv, 0.25, names = FALSE)),
  1e4 * as.numeric(stats::quantile(.scv, 0.75, names = FALSE)),
  as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
