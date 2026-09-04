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
# 결합의 형태 — estimand(재료 1) / estimator(재료 2) 의 역할 분담
# =============================================================================
# 두 재료의 스코어를 각각 만들어 섞는 지점이 이 파일에 없다. 산출은 하나뿐이고,
# 재료 1 이 **무엇을 재는가**를, 재료 2 가 **어떻게 재는가**를 통째로 공급한다.
#
#   재료 1 이 정하는 것 (estimand) — 전부 원문 명시값
#     · Eq.1  CID_t = (1/N) sum_i |R_i,t - R_MKT,t|   (VW 산업, 소속 >=10사,
#             R_MKT = 전 상장종목 VW)  ← **월간**
#     · Eq.2  d(CID_t) = g0 + g1*d(CID_{t-1}) + g2*CID_{t-1} + u_t
#             잔차 u_t 가 논문의 operative 변수다
#     · 창    "two years of monthly excess returns" = 24개월
#     · 단면  "I winsorize beta_CID at 1% and 99% percentiles"
#     · 방향  **사전 선언** — 고민감 = 저수익 (Q1 0.79% > Q2 0.63 > Q3 0.58 >
#             Q4 0.45 > Q5 0.30 · L/S -49bps t=-3.19)
#     · 리밸  "rebalance portfolios every month"
#
#   재료 2 가 정하는 것 (estimator) — 재료 1 의 Eq.3 선형 기울기를 대체한다
#     · "Limiting to max depth = 1"                         → 계단 1개
#     · "a single model capable of predicting simultaneously n stocks is built"
#       "correlation information enters the tree structure" → **공통 임계값 1개**
#     · "Min for all split points  Sum_i (y_i - prediction(y_i))^2"
#       "all input variables and all possible split points are evaluated and
#        chosen in a greedy algorithm"                      → 전 분기점 joint SSE
#     · 종목별 표준화 없음 ('dominant stock' 은 제거 대상이 아니라 설계의 성질)
#
#   결합 산출:
#       Delta_i = E[ eps_i | u > c* ] - E[ eps_i | u <= c* ]
#       Score_i = -Delta_i          (부호 = 재료 1 의 사전 선언)
#     c*    = 그 창의 전 종목 SSE 합을 최소화하는 **공통** u 임계값 하나 (재료 2)
#     eps_i = 창 안 시장모형 잔차 (아래 "시장을 왜 뺐나")
#
# =============================================================================
# 왜 이 형태인가 — 재료 1 의 Eq.3 이 KR 에서 무엇에 죽었나
# =============================================================================
# 재료 1 의 민감도 추정식은 단변량 OLS 다:  R_i,t = a + beta*u_t + e.
#   beta_i = sum_t (u_t - ubar)(R_i,t - Rbar_i) / sum_t (u_t - ubar)^2
# 즉 **월 t 의 가중치가 (u_t - ubar) 에 비례**한다. u 가 두꺼운 꼬리를 가지면
# 한 달이 분모·분자를 동시에 지배해 beta_i 의 단면 순위가 그 한 달의 단면 수익
# 순위로 붕괴한다. 그리고 사내 실측(RP_2301_09173_CID/NOTES.md)이 KR 에서 그 달이
# 무엇인지 특정했다: cor(u, KOSPI200 월수익) = **+0.43**(2022-26 +0.63), 최대 u 달 =
# 2026-05(시장 +35%) · 2025-10(+22%) · 2026-04(+33%) — 분산 급등이 하락장이 아니라
# **반도체 주도 급등**에서 온다. 그래서 beta_CID 정렬이 시장베타 정렬로 변질됐고
# (L/S 일간 beta -0.39), FF 알파 9~12% 는 역베타의 회계였다(raw CAGR 0.6% · Grade F).
#
# ★그런데 이건 재료 1 자신의 estimand 가 아니다. 논문 Table 5 는 5분위의 시장 로딩을
#   Q1 1.07 · Q5 1.11, **L/S 스프레드 0.04** 로 보고하고 "Controlling for market beta
#   does not have significant effect on the CID premium" 이라고 쓴다. 즉 US 에서
#   공짜로 성립하던 성질(시장베타 중립)이 KR 충실구현에서 깨진 것이지, 논문이 시장
#   베팅을 요구한 적이 없다. 시장을 회귀 통제항으로 넣는 것은 **논문이 보고하는 성질을
#   KR 에서 강제로 복원**하는 조치다(재료 2 도 같은 자리를 가리킨다 — 시장초과수익이
#   "always the most informative factor" 라면 그것을 뺀 단변량 적합의 잔차에 시장이
#   통째로 남고, 시장과 상관된 축의 기울기가 그 잔차를 주워 담는다).
#
# 그 위에서 재료 2 의 계단이 남은 절반을 닫는다: 잎 평균은 잎 안의 모든 관측을 1/n 로
# 실으므로 **어떤 한 달도 Delta 를 지배할 수 없다**(잎 최소 3개월). 기울기의
# (u_t - ubar) 가중 → 계단의 균등 가중이 이 결합의 핵심 수술이다.
#
# =============================================================================
# 왜 각 재료 단독보다 나을 것이라 보는가 (반증 형태 = FIDELITY.json changed ②)
# =============================================================================
#  ▸ 재료 1 단독(다중검정 t 1.228 · 충실구현 Grade F): 위 기전. 이 엔진은 (i) 창 안
#    OLS 라 cov(eps, 시장) = 0 이 **구조적으로** 성립하고 (ii) 균등가중 잎 평균이라
#    단일 극단월 지배가 원리상 불가능하다. 두 사인을 각각 닫는다.
#  ▸ 재료 2 단독(다중검정 t 1.11): 산출이 잎의 **수준**(예측 기대수익)이라 긴 창에서
#    그 종목의 장기 평균수익과 같아진다 — 조건부 구조를 회수해 놓고 무조건부 수준을
#    발행한 셈이다. 이 엔진의 산출은 두 잎의 **차**이고, eps 의 창 내 평균이 0 이라
#    수준 성분이 두 겹으로 제거된다(5년 모멘텀 별칭이 원리상 불가능). 또 재료 2 는
#    방향을 주지 않지만(그래서 단독 구현은 부호를 고르길 거부했다) 재료 1 이 사전
#    선언한 부호를 공급한다.
#  ▸ 남는 주장은 하나다: **KR 에서 CID 민감도의 단면 분산은 전부 시장베타인가,
#    아니면 시장을 통제하고 선형을 계단으로 바꾼 뒤에도 남는가.** 아래 §8 계기가 판정한다.
#
# =============================================================================
# 해상도 — CID 는 월간 그대로, 잎은 일간 (무엇을 바꾸고 무엇을 안 바꿨나)
# =============================================================================
#  · **상태변수는 월간이다.** Eq.1·Eq.2 를 논문 그대로 월간으로 계산한다. 일간 CID 는
#    산업 일간 분산(변동성 계열)이지 논문이 실업률로 검증한 그 변수가 아니다 — 논문의
#    거시 검증은 분기 축이고 기전은 "sectoral reallocation" 이라는 저빈도 사건이다.
#    (이 지점을 일간으로 바꾸면 estimand 가 통째로 갈린다. 바꾸지 않았다.)
#  · **잎 평균과 시장 통제만 일간이다.** 창의 시간 길이는 재료 1 의 24개월 그대로이고,
#    그 안에서 관측을 일간으로 읽는다. 이유는 둘 다 추정 정밀도이지 취향이 아니다:
#      - 시장베타를 24 관측으로 추정하면 통제항 자체가 잡음이라 통제가 성립하지 않는다.
#        같은 창 일간 ~490 관측이면 통제가 실제로 발화한다(계기 (b) 가 검증).
#      - 재료 2 의 표본이 1,259 daily returns 이고, joint SSE 스캔은 그 해상도를 전제한다.
#    ★잎 경계는 여전히 **월 단위**다(u 가 월간이므로 잎 = 월들의 합집합). 그래서
#      후보 분기점은 24개 월값 사이의 23곳뿐이고, joint SSE 는 그 23곳에서만 평가된다.
#      이 축약은 근사가 아니라 정확하다: sum_{d in leaf} eps = sum_{m in leaf} (월별 합).
#  · 대가(정직 기록): 잎 대비의 **유효 표본은 여전히 월 수**다(월 안 일간 수익은 그 달의
#    공통 성분을 공유한다). 일간화가 사는 것은 시장베타의 정밀도이지 잎 대비의 검정력이
#    아니다. 이 엔진은 후자를 개선했다고 주장하지 않는다.
#
# =============================================================================
# 미명시값 보충 — 전부 출처를 적는다
# =============================================================================
#  · AR(Eq.2) = **expanding window**. 논문은 전표본 1회 추정이나 C1 위반이라 PIT 가
#    논문 문자를 이긴다. burn-in 60개월 = RP_2301_09173_CID 선례 승계.
#  · 창 유효 개월 >= 18/24 = 같은 선례(같은 estimand)의 최소 유효관측 승계.
#  · 잎 최소 **3개월**(양쪽). 논문 둘 다 하한을 주지 않는다. 3 은 성과에서 온 값이 아니라
#    수치 타당성 하한이다 — 2모수 계단모형에서 어느 잎도 (모수+2) 미만 관측 위에 서지
#    않게 하고, 어떤 한 달도 잎 평균의 1/3 을 넘지 못하게 한다(= 이 결합이 고치려는
#    '단일 월 지배' 를 계단 쪽에서 재발시키지 않는 하한). 재료 2 의 Table 2c 에서
#    **joint** 트리 임계값이 solo(1-99% 까지 극단)보다 훨씬 덜 극단적으로 수렴한다는
#    점(-70bp ≈ 일간 -0.5sd)이 이 하한이 상시 구속되지 않으리라는 근거이고, 실제
#    binding 여부는 매월 로그로 드러낸다(계기 (c)).
#  · 산업분류·가중 = **전월말** Sector_Lv2(48군 — FF49 의 최근접 아날로그) / 전월말 시총.
#    월 t 의 산업 귀속은 t 시작 전에 알려져 있어야 한다.
#  · rf 미사용. 재료 1 은 초과수익을 쓰지만 (i) 산출이 두 잎 평균의 **차**이고 rf 는
#    잎 간 거의 상수라 차분에서 소거되며 (ii) 단면 순위가 불변이다. 시장변수도 재료 1 이
#    Eq.1 에서 직접 만드는 R_MKT(전 상장종목 VW)를 쓴다 — 외부 캐시 의존 0.
#  · |일간 Ret| > 1.0 = 결측. KRX 가격제한폭 ±30% 하에서 한 세션에 불가능한 값이므로
#    액면/재상장 단위 아티팩트다. 전략 파라미터가 아니라 거래소 규칙 근거의 위생 조치.
#  · 종목수·비중 = 고정 축(top-25 롱온리 EW). 두 논문 규약이 충돌하기 때문이다: 재료 2 는
#    포트폴리오가 아예 없고("only done for demonstration purposes and not for statistical
#    inference"), 재료 1 의 5분위 VW 는 레그당 ~70종이며 KR 에서 숏 레그를 삼성전자 39%
#    + 하이닉스 29% 가 지배했다(선례 실측). **리밸 주기(월간)만 재료 1 명시값 그대로.**
#
# =============================================================================
# PIT (C1~C15) — 구조로 보장한다. detect_lookahead 통과를 근거로 삼지 않는다.
# =============================================================================
#  ▸ 구조 경계 1 — 창: 창은 `.wm` 이 [m-23, m] 인 월 AND `.rdt <= D` 로만 잘린다.
#    형성일 인덱스를 넘는 인덱싱·음수 shift·lead 가 코드에 0건.
#  ▸ 구조 경계 2 — 가중치/산업: `ymi_w = ymi - 1L` 한 줄로 만들어진다. 동월 시총·동월
#    섹터를 쓰는 경로가 코드에 **존재하지 않는다**(막는 검사가 아니라 표현 불가능한 배치).
#  ▸ 구조 경계 3 — AR: expanding 누적 교차곱이 k 까지만 더해진다. u_k 는 <=k 정보만.
#  ▸ 구조 경계 4 — 상태 이월 없음: 형성일 루프 반복이 서로 독립이다. 시장모형 계수·
#    임계값·잎 평균이 전부 그 창 안에서만 계산된다.
#  C1  : rolling/expanding 만. 전표본 mean/quantile/cov/lm 0건. winsorize 는 그 형성일
#        단면 벡터 내부에서만(시계열 미래 미참조).
#  C2  : same-day 순환참조 없음. D 종가까지 쓰고 집행은 익 거래일(하네스).
#  C3  : 같은 기간 집계->적용 없음. 신호 컷오프(월 m 말) < 보유월(m+1) 시작.
#  C4  : 재무제표 패널 미사용.
#  C5  : 오버레이 없음(S0/S1 오버레이 금지 준수).
#  C6  : 유니버스 = 각 D 의 K200/KQ150 멤버십(PIT 시변). 최종 명부 주입 없음. 창 커버리지
#        요건은 **과거** 데이터 요건이라 생존편의를 만들지 않는다.
#  C7  : shift(-N)·lead()·수동 미래 인덱싱 0건. shift 는 전부 +1(과거 방향).
#  C9  : DD/VT 미사용.
#  C10 : 유동성 = D **직전 20 거래일** 평균 거래대금. `(ip-20):(ip-1)` 로 당일 배제.
#  C11 : 외부 매크로 0건(rf·FRED·팩터 캐시·BM_DT 미사용).
#  C13 : Factor DB 미소비 -> 정렬 대상 없음. 부호는 재료 1 의 **사전 선언**(고민감 =
#        저수익)이지 사후 반전이 아니다.
#  C15 : Factor DB parquet 직접 load 0건.
#  ★rawdata 의 Market 열 미사용(KOSDAQ 0건 날조 — 사내 기록). 시장 구분은 K200/KQ150
#    멤버십 플래그로만 한다.
#
# ===== 산출 =====
#   FACTORS(Date, Ticker, Score) — Score = -Delta. 클수록 롱.
#   러너 호출: portfolio_spec = list(construction="top_n_long", weighting="ew",
#              rebalance="monthly", n_long=25, n_max=25) · commission_paper = NULL
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

set.seed(23010917L)   # 난수 미사용(결정론적 엔진) — 재현성 선언 고정

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.RQ <- c("Date", "Ticker", "Close", "Vol", "Ret", "Size", "Sector_Lv2", "K200", "KQ150")
if (!all(.RQ %in% names(RAWDATA)))
  stop(sprintf("[COMBO_CIDSTEP] RAWDATA 열 부족: %s",
               paste(setdiff(.RQ, names(RAWDATA)), collapse = ", ")))

# =============================================================================
# 0. 상수 — 전부 출처 표기
# =============================================================================
# ▸ 재료 1 (Pinchuk 2301.09173) 명시값
.MIN_FIRMS <- 10L          # "industries with at least 10 firms"
.WIN_M     <- 24L          # "two years of monthly excess returns"
.WINS_LO   <- 0.01         # "winsorize beta_CID at 1% and 99% percentiles"
.WINS_HI   <- 0.99
# ▸ 재료 2 (Polimenis 2007.08115): depth=1 · 공통 임계값 1개 · 전 분기점 greedy ·
#   종목별 표준화 없음. 수치 파라미터는 joint 성립 하한 하나뿐이다(논문 표본 5종).
.MIN_STK   <- 2L
# ▸ 수치 타당성 하한 (성과에서 오지 않은 값 — 위 "미명시값 보충" 에 근거)
.LEAF_MO   <- 3L           # 잎 최소 개월(양쪽) — 2모수 계단의 자유도 + 단일월 지배 차단
# ▸ 사내 선례 승계 (RP_2301_09173_CID — 같은 estimand 의 기존 구현)
.AR_BURN   <- 60L          # AR expanding burn-in (개월)
.MIN_MO    <- 18L          # 창 24개월 중 유효 >= 18
.COV       <- 0.75         # 창 일간 커버리지 하한 (= 18/24)
.RET_CAP   <- 1.0          # |일간수익| > 100% = 데이터 아티팩트 (KRX 가격제한폭 ±30%)
# ▸ 축(도훈 고정)
.LIQ       <- 2e8          # adv20(t-1) 하한 (KRW)
.LIQ_WIN   <- 20L          # 거래일 (D 직전 20 거래일, 종점 = D-1)
.START     <- as.Date("2005-01-01")

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

if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]

# =============================================================================
# 1. 일간 기저 패널 — 전월말 시총/산업라벨 부착 (구조 경계 2)
# =============================================================================
# ★유니버스 치환(K200∪KQ150)은 **정렬 대상(test asset)** 에만 걸린다. CID·시장은 재료 1 이
#   "value-weighted market return across all firms" 라 한 거시 변수라 전 상장종목에서 만든다.
.AD  <- data.table(Date = sort(unique(RAWDATA$Date)))
.AD[, ymi := year(Date) * 12L + month(Date)]
.MEA <- .AD[, .(me = max(Date)), by = ymi]$me                   # 시장 전체 월말 거래일
# ★섹터 라벨을 여기서 거르지 않는다. 재료 1 의 R_MKT 는 "all firms" 이고 산업 라벨은
#   **산업 포트폴리오에만** 필요하다(§2 IPF). 여기서 걸면 라벨 없는 종목이 시장에서도
#   빠져 Eq.1 의 시장 다리가 논문 정의보다 좁아진다.
.EOM <- RAWDATA[Date %in% .MEA & is.finite(Size) & Size > 0,
                .(Ticker, ymi_w = year(Date) * 12L + month(Date),
                  w = as.numeric(Size), ind = Sector_Lv2)]
.EOM <- unique(.EOM, by = c("Ticker", "ymi_w"))
rm(.AD, .MEA); gc(verbose = FALSE)
if (!nrow(.EOM)) stop("[COMBO_CIDSTEP] 월말 시총 관측 0건 — Size 확인")
if (all(is.na(.EOM$ind)))
  stop("[COMBO_CIDSTEP] 월말 산업라벨 0건 — Sector_Lv2 확인 (Eq.1 산업 다리 불가)")

.DD <- RAWDATA[is.finite(Ret), .(Date, Ticker, rr = as.numeric(Ret))]
.DD <- .DD[abs(rr) <= .RET_CAP]            # rr 은 위에서 finite 로 걸러져 NA 첨자가 없다
.DD[, ymi := year(Date) * 12L + month(Date)]
.DD[, ymi_w := ymi - 1L]                                        # ★전월말 (동월 경로 없음)
.DD[.EOM, on = .(Ticker, ymi_w), c("w", "ind") := .(i.w, i.ind)]
.DD <- .DD[is.finite(w) & w > 0]              # 가중치만 요구 — 산업 라벨은 IPF 에서만 건다
if (!nrow(.DD)) stop("[COMBO_CIDSTEP] 전월말 가중치 결합 후 0행 — 월말 격자 확인")

# 일간 VW 시장 (>=10사 필터 **전**, 전 상장종목) — 시장 통제항의 원천
MKTD <- .DD[, .(r_mkt = sum(w * rr) / sum(w), n_all = .N), by = Date]
setorder(MKTD, Date)

# =============================================================================
# 2. 재료 1 Eq.1 — **월간** CID (상태변수는 논문 그대로 월간이다)
# =============================================================================
MON <- .DD[, .(mret = prod(1 + rr) - 1, nd = .N, w = w[1], ind = ind[1]),
           by = .(Ticker, ymi)]
rm(.DD); gc(verbose = FALSE)

# 산업 다리만 라벨을 요구한다("industries with at least 10 firms"). 시장 다리는 전 상장종목.
IPF  <- MON[!is.na(ind), .(r_ind = sum(w * mret) / sum(w), nf = .N),
            by = .(ymi, ind)][nf >= .MIN_FIRMS]
MKTM <- MON[, .(r_mktm = sum(w * mret) / sum(w)), by = ymi]
CIDM <- merge(IPF[, .(ymi, r_ind)], MKTM, by = "ymi")
CIDM <- CIDM[, .(CID = mean(abs(r_ind - r_mktm)), n_ind = .N), by = ymi]
setorder(CIDM, ymi)
rm(IPF); gc(verbose = FALSE)
if (nrow(CIDM) < (.AR_BURN + .WIN_M + 12L))
  stop(sprintf("[COMBO_CIDSTEP] 월간 CID %d개월 — 표본 부족", nrow(CIDM)))
cat(sprintf("[COMBO_CIDSTEP] Eq.1 월간 CID %d개월 · 산업수 중앙 %.0f · 평균 %.4f sd %.4f\n",
            nrow(CIDM), .med(CIDM$n_ind), mean(CIDM$CID), stats::sd(CIDM$CID)))

# =============================================================================
# 3. 재료 1 Eq.2 — CID 충격 u_t (expanding window AR · PIT 보정)
# =============================================================================
#   d(CID_t) = g0 + g1*d(CID_{t-1}) + g2*CID_{t-1} + u_t
#   expanding OLS 를 누적 교차곱으로 정확히 구현한다(lm 반복과 수치 동일 · O(n)).
#   구조 경계 3: 각 k 의 계수는 1..k 만 더한 X'X, X'y 에서 나온다.
CIDM[, dC := CID - shift(CID)]
CIDM[, `:=`(dC_l1 = shift(dC), C_l1 = shift(CID))]
CIDM[, u := NA_real_]
.rw <- which(is.finite(CIDM$dC) & is.finite(CIDM$dC_l1) & is.finite(CIDM$C_l1))
if (length(.rw) < (.AR_BURN + .WIN_M))
  stop("[COMBO_CIDSTEP] AR 적합 가능 개월 부족")
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
  stop("[COMBO_CIDSTEP] CID 충격 u 유효 개월 부족 — AR 적합 실패")
.uok <- CIDM[is.finite(u)]
cat(sprintf("[COMBO_CIDSTEP] Eq.2 충격 u: 유효 %d개월 · sd %.5f · 1-lag 자기상관 %+.3f (논문 US: -0.05)\n",
            nrow(.uok), stats::sd(.uok$u), .sp(.uok$u[-1L], .uok$u[-nrow(.uok)])))
rm(.uok)

# =============================================================================
# 4. 테스트 자산 — K200∪KQ150 일간/월간 수익 wide 행렬
# =============================================================================
.tk <- unique(RAWDATA[.tru(K200) | .tru(KQ150), Ticker])
if (!length(.tk)) stop("[COMBO_CIDSTEP] K200/KQ150 멤버십 0건 — RAWDATA 확인")

.gd <- MKTD$Date                                        # 시장이 정의된 거래일 격자
.rs <- RAWDATA[Ticker %chin% .tk & Date %in% .gd & is.finite(Ret), .(Date, Ticker, r = as.numeric(Ret))]
.rs <- .rs[abs(r) <= .RET_CAP]             # r 은 위에서 finite 로 걸러져 NA 첨자가 없다
.nd <- sum(duplicated(.rs, by = c("Ticker", "Date")))
if (.nd > 0L) {
  cat(sprintf("[COMBO_CIDSTEP] (Date,Ticker) 중복 %d행 — 첫 행만 남긴다\n", .nd))
  .rs <- unique(.rs, by = c("Ticker", "Date"))
}
.RW  <- dcast(.rs, Date ~ Ticker, value.var = "r")
setorder(.RW, Date)
.rdt <- .RW$Date
RETD <- as.matrix(.RW[, -1L, with = FALSE])
.tick <- colnames(RETD)
rm(.RW, .rs); gc(verbose = FALSE)
.rym <- year(.rdt) * 12L + month(.rdt)

setkey(MKTD, Date)
.mvec <- MKTD[.(.rdt), r_mkt]
if (anyNA(.mvec)) stop("[COMBO_CIDSTEP] 시장 계열 정렬 실패 — 격자 불일치")

# 월간 wide (계기 (a) 전용 — 재료 1 Eq.3 원판을 같은 창/같은 유니버스에서 재현)
.MW  <- dcast(MON[Ticker %chin% .tick, .(ymi, Ticker, mret)], ymi ~ Ticker, value.var = "mret")
setorder(.MW, ymi)
.mym <- .MW$ymi
.MWm <- as.matrix(.MW[, -1L, with = FALSE])
# ★열 정렬은 **이름으로** 채운다. match(.tick, colnames) 은 월간 패널에 없는 종목에서
#   NA 첨자를 만들고(일간엔 있지만 전월말 시총이 한 번도 없던 종목), NA 첨자 인덱싱은
#   진단 한 줄 때문에 라운드를 통째로 죽일 수 있다. 없는 열은 NA 로 남기면 (a) 계기가
#   그 종목에서만 조용히 빠진다(.sp 가 비유한값을 버린다).
RETM <- matrix(NA_real_, nrow(.MWm), length(.tick), dimnames = list(NULL, .tick))
.hit <- intersect(.tick, colnames(.MWm))
if (length(.hit)) RETM[, .hit] <- .MWm[, .hit, drop = FALSE]
rm(.MW, .MWm); gc(verbose = FALSE)

.SEC <- unique(.EOM[, .(Ticker, ymi_w, ind)], by = c("Ticker", "ymi_w"))
setkey(.SEC, ymi_w, Ticker)
rm(.EOM); gc(verbose = FALSE)

cat(sprintf("[COMBO_CIDSTEP] 테스트 자산 %d거래일 x %d종 (%s ~ %s) · 일간 결측 %.1f%%\n",
            nrow(RETD), ncol(RETD), as.character(min(.rdt)), as.character(max(.rdt)),
            100 * mean(is.na(RETD))))

# =============================================================================
# 5. 형성일(월말 거래일) · 유동성 창 · 자격
# =============================================================================
.GD   <- data.table(Date = .rdt, ymi = .rym)
.ME   <- .GD[, .(Date = max(Date)), by = ymi]
setorder(.ME, Date)
.FORM <- .ME[Date >= .START, Date]
if (!length(.FORM)) stop("[COMBO_CIDSTEP] 형성일 0건 — RAWDATA 날짜 범위 확인")

.LW <- rbindlist(lapply(seq_along(.FORM), function(k) {
  D  <- .FORM[k]
  ip <- match(D, .rdt)
  if (is.na(ip) || (ip - .LIQ_WIN) < 1L) return(NULL)
  data.table(Date = .rdt[(ip - .LIQ_WIN):(ip - 1L)], FormDate = D)   # 종점 = D-1 (C10)
}), use.names = TRUE)
if (!nrow(.LW)) stop("[COMBO_CIDSTEP] 유동성 창 구성 실패 — 거래일 수 부족")
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

setkey(CIDM, ymi)

# =============================================================================
# 6. 형성일 루프 — 시장 통제 -> joint depth=1 계단 -> Delta -> winsorize -> Score
# =============================================================================
# joint SSE 목적함수 (원문 "Min sum_i (y_i - prediction(y_i))^2" 와 정확히 동치):
#   SSE(k) = sum_i [ TSS_i - CS_i(k)^2/CN_i(k) - (TS_i-CS_i(k))^2/(TN_i-CN_i(k)) ]
#   TSS_i 는 k 에 무관하므로 SSE 최소화 = 아래 gain 최대화. **종목별 표준화는 하지
#   않는다** — 재료 2 의 joint 트리가 그렇고 'dominant stock' 이 그 설계의 성질이다.
#   u 가 월간이라 잎 경계는 월이고, 후보 분기점은 창 안 월값 사이 (nM-1) 곳뿐이다.
.OUT  <- vector("list", length(.FORM))
.LOG  <- vector("list", length(.FORM))
.skip <- 0L

for (kk in seq_along(.FORM)) {
  D  <- .FORM[kk]
  fy <- .fym[kk]

  # ── 창: 형성월 m 으로 끝나는 24개월, 유효 u 가 있는 월만 (구조 경계 1) ──
  wm <- CIDM[.(seq.int(fy - .WIN_M + 1L, fy)), .(ymi, u), nomatch = 0L]
  wm <- wm[is.finite(u)]
  nM <- nrow(wm)
  if (nM < .MIN_MO || nM < (2L * .LEAF_MO + 1L)) { .skip <- .skip + 1L; next }

  wi <- which(.rym %in% wm$ymi & .rdt <= D)                 # 창 거래일
  nw <- length(wi)
  if (nw < (nM * 10L)) { .skip <- .skip + 1L; next }

  cand <- .ELG[.(D), Ticker, nomatch = 0L]
  cand <- intersect(cand, .tick)
  if (length(cand) < .MIN_STK) { .skip <- .skip + 1L; next }
  ci <- match(cand, .tick)

  Y  <- RETD[wi, ci, drop = FALSE]
  mw <- .mvec[wi]

  # ── 창 안 시장모형 (일간 ~490 관측) — 통제항이 잡음이 되지 않게 ──
  Ms  <- matrix(as.numeric(!is.na(Y)), nw, ncol(Y))
  Xs  <- Y; Xs[is.na(Xs)] <- 0
  n_i <- colSums(Ms); Sy <- colSums(Xs)
  Sm  <- colSums(Ms * mw); Smm <- colSums(Ms * mw^2); Smy <- colSums(Xs * mw)
  den <- n_i * Smm - Sm * Sm
  b_m <- ifelse(is.finite(den) & den > 0, (n_i * Smy - Sm * Sy) / den, NA_real_)
  a_m <- (Sy - b_m * Sm) / n_i

  keep <- (n_i >= .COV * nw) & is.finite(b_m) & is.finite(a_m) & !is.na(Y[nw, ])
  if (sum(keep) < .MIN_STK) { .skip <- .skip + 1L; next }
  Y <- Y[, keep, drop = FALSE]; Ms <- Ms[, keep, drop = FALSE]; Xs <- Xs[, keep, drop = FALSE]
  nm <- .tick[ci][keep]; b_m <- b_m[keep]; a_m <- a_m[keep]
  nc <- ncol(Y)

  # 잔차: sum_d eps = 0 이고 cov(eps, mkt) = 0 — 수준 성분과 선형 시장 성분이 구조적으로 제거
  E  <- Y - matrix(a_m, nw, nc, byrow = TRUE) - outer(mw, b_m)
  Xe <- E; Xe[is.na(Xe)] <- 0

  # ── 월별 집계 (잎 경계 = 월. 이 축약은 근사가 아니라 정확하다) ──
  gm  <- .rym[wi]
  MS  <- rowsum(Xe, gm, reorder = TRUE)                     # 행 = ymi 오름차순
  MN  <- rowsum(Ms, gm, reorder = TRUE)
  MSr <- rowsum(Xs, gm, reorder = TRUE)                     # 통제 전(양성 대조용)
  gu  <- as.integer(rownames(MS))
  uu  <- wm$u[match(gu, wm$ymi)]
  if (anyNA(uu) || nrow(MS) < (2L * .LEAF_MO + 1L)) { .skip <- .skip + 1L; next }

  # ── 재료 2 의 joint depth=1 스캔: 축 = u, 전 분기점 greedy, 공통 임계값 1개 ──
  o   <- order(uu)
  us  <- uu[o]
  MSp <- MS[o, , drop = FALSE]; MNp <- MN[o, , drop = FALSE]; MSq <- MSr[o, , drop = FALSE]
  nMo <- nrow(MSp)
  CS  <- matrix(apply(MSp, 2L, cumsum), nMo, nc)
  CN  <- matrix(apply(MNp, 2L, cumsum), nMo, nc)
  CQ  <- matrix(apply(MSq, 2L, cumsum), nMo, nc)
  CI  <- matrix(apply(MNp > 0, 2L, cumsum), nMo, nc)        # 잎별 **개월** 수
  TS  <- CS[nMo, ]; TN <- CN[nMo, ]; TQ <- CQ[nMo, ]; TI <- CI[nMo, ]

  RS <- matrix(TS, nMo, nc, byrow = TRUE) - CS
  RN <- matrix(TN, nMo, nc, byrow = TRUE) - CN
  LT <- CS^2 / CN; RT <- RS^2 / RN
  LT[!is.finite(LT)] <- 0; RT[!is.finite(RT)] <- 0           # 잎에 관측 없는 종목 = 기여 0
  gv <- rowSums(LT + RT)
  g0 <- TS^2 / TN; g0[!is.finite(g0)] <- 0                   # 무분기(root) 기준값

  ki <- seq_len(nMo)
  ok <- c(us[-nMo] < us[-1L], FALSE) & (ki >= .LEAF_MO) & ((nMo - ki) >= .LEAF_MO)
  if (!any(ok)) { .skip <- .skip + 1L; next }
  gv[!ok] <- -Inf
  ks <- as.integer(which.max(gv))
  if (!is.finite(gv[ks])) { .skip <- .skip + 1L; next }
  cstar <- as.numeric(us[ks] + us[ks + 1L]) / 2

  # ── Delta = E[eps | u > c*] - E[eps | u <= c*] ──
  cl <- CN[ks, ]; ch <- TN - cl
  ml <- CI[ks, ]; mh <- TI - ml                              # 잎별 개월 수(종목별)
  dl <- (TS - CS[ks, ]) / ch - CS[ks, ] / cl
  dq <- (TQ - CQ[ks, ]) / ch - CQ[ks, ] / cl                 # 통제 전 Delta (양성 대조)
  good <- is.finite(dl) & ml >= .LEAF_MO & mh >= .LEAF_MO
  if (sum(good) < .MIN_STK) { .skip <- .skip + 1L; next }

  # ── 단면 winsorize 1%/99% (재료 1 명시) ──
  dv <- as.numeric(dl[good])
  qq <- stats::quantile(dv, c(.WINS_LO, .WINS_HI), na.rm = TRUE, names = FALSE)
  dw <- pmin(pmax(dv, qq[1]), qq[2])

  # ── 부호 = 재료 1 의 사전 선언(고민감 = 저수익) ──
  tk_g <- nm[good]
  .OUT[[kk]] <- data.table(Date = D, Ticker = tk_g, Score = -dw)

  # ── 계기 (a)~(f) ──────────────────────────────────────────────────────────
  # (a) 재료 1 Eq.3 원판: 같은 창·같은 유니버스의 **월간 단변량 OLS** beta_CID
  mi   <- match(wm$ymi, .mym)
  b_ol <- rep(NA_real_, nc)
  if (!anyNA(mi)) {
    Ym <- RETM[mi, ci, drop = FALSE][, keep, drop = FALSE]
    Mm <- matrix(as.numeric(!is.na(Ym)), nrow(Ym), nc); Xm <- Ym; Xm[is.na(Xm)] <- 0
    uwm <- wm$u
    nn2 <- colSums(Mm); Su <- colSums(Mm * uwm); Suu <- colSums(Mm * uwm^2)
    Sy2 <- colSums(Xm); Suy <- colSums(Xm * uwm)
    d2  <- nn2 * Suu - Su * Su
    b_ol <- ifelse(is.finite(d2) & d2 > 0 & nn2 >= .MIN_MO,
                   (nn2 * Suy - Su * Sy2) / d2, NA_real_)
  }
  mu_w <- ifelse(TN > 0, (colSums(Xs)) / TN, NA_real_)       # 창 무조건부 평균(수준 별칭 검사)
  # (f) 롱 상위 25 의 최대 섹터 점유율 — 재료 1 의 기전(산업 재배치의 패자)이 보이는가
  sc_g   <- -dw                                              # 발행 Score
  sec_sh <- NA_real_
  if (length(sc_g) >= 25L) {
    tp <- tk_g[order(-sc_g)][seq_len(25L)]                   # Score 내림차순 상위 25
    sv <- .SEC[.(fy - 1L, tp), ind]
    sv <- sv[!is.na(sv)]
    if (length(sv) >= 10L) sec_sh <- 100 * max(table(sv)) / length(sv)
  }
  usd <- stats::sd(us)
  # ★분기 이득은 **잔차 총제곱합 대비**로 잰다. root 대비로 재면 안 된다 —
  #   eps 는 창 안 OLS 잔차라 열합이 0 이고 root 기준값 g0 = TS^2/TN 이 0 이므로
  #   분모가 소멸한다(0 으로 나눠 무한대가 나온다).
  tss <- sum(Xe * Xe)
  .LOG[[kk]] <- data.table(
    Date = D, n_mo = nMo, n_day = nw, n_stock = sum(good),
    thr_z    = if (is.finite(usd) && usd > 0) as.numeric(cstar / usd) else NA_real_,
    thr_pct  = 100 * ks / nMo,                               # c* 가 u 분포의 몇 %ile 인가
    mo_hi    = nMo - ks,                                     # 고-u 잎 개월수
    gain_r   = if (is.finite(tss) && tss > 0)
                 as.numeric((gv[ks] - sum(g0)) / tss) else NA_real_,
    rho_ols  = .sp(dv, b_ol[good]),                          # (a) 추정기 치환이 하중을 받는가
    rho_bm   = .sp(sc_g, b_m[good]),                         # (b) 시장베타 오염 — 통제 후
    rho_bm0  = .sp(-as.numeric(dq[good]), b_m[good]),        # (b') 양성 대조 — 통제 전
    rho_lvl  = .sp(sc_g, mu_w[good]),                        # (c) 창 수준(모멘텀) 별칭
    # (e) 상태분기 vs 시간분기 — ★**캘린더 순서**의 ymi 와 잎 소속을 잰다.
    #     정렬된 us 로 재면 정의상 +1 이 나와 계기가 죽는다.
    t_deg    = .sp(gu, as.numeric(uu > cstar)),
    sec_sh   = sec_sh)                                       # (f) 롱 사이드 섹터 집중
}

FACTORS <- rbindlist(Filter(Negate(is.null), .OUT), use.names = TRUE)
if (!nrow(FACTORS))
  stop("[COMBO_CIDSTEP] FACTORS 0행 — 창 유효개월/유니버스/커버리지/잎 하한 확인")
setorder(FACTORS, Date, -Score)

# =============================================================================
# 7. 회수된 구조 + 반증 계기 보고
# =============================================================================
LOGDT <- rbindlist(Filter(Negate(is.null), .LOG), use.names = TRUE)
setorder(LOGDT, Date)
LOGDT[, thr_jump := abs(thr_z - shift(thr_z))]     # (e) 겹치는 창(23/24 공통)의 임계값 안정성
LOGDT[, yr := year(Date)]

.byyr <- LOGDT[, .(n_m = .N, n_stock = as.integer(.med(n_stock)),
                   thr_pct = round(.med(thr_pct)), mo_hi = round(.med(mo_hi), 1),
                   rho_ols = round(.med(rho_ols), 2), rho_bm = round(.med(rho_bm), 2),
                   rho_bm0 = round(.med(rho_bm0), 2), rho_lvl = round(.med(rho_lvl), 2)), by = yr]
setorder(.byyr, yr)
cat("[COMBO_CIDSTEP] 연도별 joint depth=1 계단 (축 = Eq.2 월간 충격 u · y = 창 안 시장모형 잔차):\n")
cat("      연도 | 월수 종목  c*%ile 고u잎(월)  rho(D,Eq.3beta)  rho(S,bmkt) [통제전]  rho(S,창평균)\n")
for (i in seq_len(nrow(.byyr)))
  cat(sprintf("      %4d |  %2d  %3d   %3.0f%%     %4.1f          %+6.2f         %+6.2f  [%+6.2f]      %+6.2f\n",
              .byyr$yr[i], .byyr$n_m[i], .byyr$n_stock[i], .byyr$thr_pct[i], .byyr$mo_hi[i],
              .byyr$rho_ols[i], .byyr$rho_bm[i], .byyr$rho_bm0[i], .byyr$rho_lvl[i]))

.nmn <- FACTORS[, .N, by = Date]
.scv <- as.numeric(FACTORS[["Score"]])   # ★벡터로 뽑아 잰다(quantile(DT$col) = C1b 오탐)
.bind <- 100 * mean(LOGDT$mo_hi <= .LEAF_MO | (LOGDT$n_mo - LOGDT$mo_hi) <= .LEAF_MO)
cat(sprintf(paste0(
  "[COMBO_CIDSTEP] combination — 재료1 의 estimand(Eq.1 월간 CID -> Eq.2 충격 u -> 24개월\n",
  "  민감도 -> 1%%/99%% winsorize -> 고민감=저수익 -> 월간 리밸)를 재료2 의 estimator\n",
  "  (joint depth=1 · 전 종목 SSE 합의 공통 임계값 1개 · 전 분기점 greedy · 표준화 없음)로\n",
  "  추정한다. 시장은 경쟁 분기변수가 아니라 회귀 통제항 — 재료1 Table 5 가 보고하는\n",
  "  성질(5분위 시장로딩 스프레드 0.04)을 KR 에서 강제 복원하는 자리다.\n",
  "  형성 %d개월(skip %d) · %s ~ %s · FACTORS %s행 · 월 종목 중앙 %d (min %d / max %d)\n",
  "  창 = 유효 %.0f개월 / 일간 %.0f거래일 (창의 시간 길이는 재료1 의 24개월 그대로)\n",
  "  ── 반증 계기 (전 기간 중앙값) ───────────────────────────────────────────────\n",
  "  (a) rho(Delta, Eq.3 원판 월간 OLS beta) %+5.2f\n",
  "      → +1 근방이면 추정기 치환이 무하중 = 이 엔진은 CID 단독의 재실행이고 결합이 아니다.\n",
  "  (b) rho(Score, 창 시장베타) %+5.2f   [양성 대조 = 통제 전 %+5.2f]\n",
  "      → 두 값이 같으면 시장 통제가 발화하지 않은 것(CID 단독을 죽인 역베타 채널 재현).\n",
  "        통제 후만 0 에 붙어야 수술이 성립한다.\n",
  "  (c) rho(Score, 창 무조건부 평균) %+5.2f\n",
  "      → ±1 쪽이면 수준(장기 모멘텀) 별칭 — 재료2 단독의 사인이 살아남은 것.\n",
  "  (d) c* 위치 %.0f%%ile · 고-u 잎 %.1f개월 · 잎 하한(%d개월) 구속 %.0f%%\n",
  "      → 하한 상시 구속 또는 c*가 50%%ile 근방이면 계단이 구조가 아니다(에피소드 없음).\n",
  "  (e) |c* 변화| 중앙 %.2f sd(u)  · 시간퇴화 |rho(시간, 잎)| %.2f\n",
  "      → 겹치는 창(23/24 공통)인데 c*가 튀면 임계값이 표본 산물 · |rho|~1 이면 시간분기.\n",
  "  (f) 롱 상위25 의 최대 섹터 점유율 %.0f%% (기전 확인: 재배치 국면의 산업 편중)\n",
  "  ── 구조 요약 ────────────────────────────────────────────────────────────────\n",
  "  c* 중앙 %+.2f sd(u) · 계단이 설명하는 잔차분산 %.2f%%\n",
  "  Score = -Delta (계단형 CID 민감도의 음수 · 중앙 %.2fbp · IQR %.2f~%.2fbp)\n",
  "  ★러너 호출: portfolio_spec = list(construction=\"top_n_long\", weighting=\"ew\",\n",
  "                                    rebalance=\"monthly\", n_long=25, n_max=25)\n",
  "              commission_paper = NULL (양 논문 비용 무명시) · %.1f분\n"),
  nrow(LOGDT), .skip,
  as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date)),
  format(nrow(FACTORS), big.mark = ","),
  as.integer(.med(.nmn$N)), min(.nmn$N), max(.nmn$N),
  .med(LOGDT$n_mo), .med(LOGDT$n_day),
  .med(LOGDT$rho_ols),
  .med(LOGDT$rho_bm), .med(LOGDT$rho_bm0),
  .med(LOGDT$rho_lvl),
  .med(LOGDT$thr_pct), .med(LOGDT$mo_hi), .LEAF_MO, .bind,
  .med(LOGDT$thr_jump), .med(abs(LOGDT$t_deg)),
  .med(LOGDT$sec_sh),
  .med(LOGDT$thr_z), 100 * .med(LOGDT$gain_r),
  1e4 * stats::median(.scv),
  1e4 * as.numeric(stats::quantile(.scv, 0.25, names = FALSE)),
  1e4 * as.numeric(stats::quantile(.scv, 0.75, names = FALSE)),
  as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
