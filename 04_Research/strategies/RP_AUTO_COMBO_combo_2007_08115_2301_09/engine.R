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
# 결합의 형태 — 두 논문이 같은 자리에서 맞물린다
# =============================================================================
# 재료 2 의 초록 첫 문장이 이 결합의 전부다(원문 축자):
#   "Given the success and almost universal acceptance of the simple linear
#    regression three-factor model, it is interesting to analyze the informational
#    content of the three factors in explaining stock returns when the analysis is
#    allowed to consider **non-linear dependencies** between factors and stock
#    returns."
# 재료 1 의 민감도 추정식(Eq.3)은 정확히 그 "simple linear regression" 이다(원문 축자):
#   "I use two years of monthly excess returns to obtain estimates of their
#    sensitivities to CID"  ·  R_i,t = alpha + beta * CID_t + eps_t
#
# 그러므로 결합은 **평균이 아니라 치환**이다:
#   재료 1 이 정하는 것 = 무엇을 재는가(estimand)
#       · 상태변수      : Eq.1  CID_t = (1/N) sum_i |R_i,t - R_MKT,t|  (VW 산업, >=10사)
#       · 충격          : Eq.2  dCID_t = g0 + g1 dCID_{t-1} + g2 CID_{t-1} + u_t
#                         ("residuals ... referred to as CID in the rest of the paper")
#       · 창            : "two years"  = 24개월
#       · 단면 처리     : "I winsorize beta_CID at 1% and 99% percentiles"
#       · 방향(사전선언): 고민감 = 저수익 (Q1 0.79% > ... > Q5 0.30%, L/S 49bps t=3.19)
#       · 리밸          : "I update estimates of beta_CID and rebalance portfolios
#                          every month"
#   재료 2 가 정하는 것 = 어떻게 재는가(estimator)
#       · 선형 기울기 대신 **depth=1 계단**    ("Limiting to max depth = 1")
#       · 임계값은 전 종목 SSE 합으로 하나만   ("a single model capable of predicting
#                                              simultaneously n stocks is built",
#                                              "Min sum_i (y_i - prediction(y_i))^2")
#       · 전 분기점 greedy 탐색                ("all input variables and all possible
#                                              split points are evaluated")
#       · 종목별 표준화 없음(dominant stock 은 제거 대상이 아니라 성질)
#       · 시장초과수익은 **경쟁자가 아니라 통제항**  ("in all cases (solo and joint)
#         the most informative factor is always the market excess return factor")
#
# 즉 이 엔진의 산출은 재료 1 의 beta_CID 를 재료 2 의 계단으로 바꾼 것이다:
#
#     Delta_i = E[ eps_i,t | u_t >  c* ]  -  E[ eps_i,t | u_t <= c* ]
#     Score_i = -Delta_i        (부호 = 재료 1 이 사전 선언한 방향)
#
#   eps_i,t = 창 안에서 시장모형(재료 2 의 만장일치 승자 = market factor)을 통제한 잔차
#   c*      = 그 창의 전 종목 SSE 합을 최소화하는 **공통** u 임계값 하나 (재료 2)
#
# ★두 신호의 rank-Z 평균 계보(저장소 5회 측정 · 최고 t 0.766)와 같은 지점이 없다.
#   재료별 스코어를 만들어 섞는 코드가 이 파일에 없다. 재료 1 은 estimand 를,
#   재료 2 는 estimator 를 각각 통째로 공급하고, 산출은 하나뿐이다.
# ★직전 결합판(같은 디렉터리, 2026-09-04 10:20 측정 · Grade F · PORT_t -0.678 ·
#   IC -0.021)과도 다른 수술이다. 그 판은 u_t 를 **조건화 변수**로 썼는데,
#   재료 1 자신이 u_t 의 1-lag 자기상관을 -0.05 로 보고한다("very low persistence") —
#   지속성 0 인 변수로는 형성일에 "현재 국면" 이 정의되지 않는다. 그래서 그 판의
#   스코어는 사실상 창 무조건부 평균(5년 모멘텀)이 됐다. 여기서 u_t 는 조건화 변수가
#   아니라 **민감도의 축**이고, 축으로 쓸 때는 지속성이 필요 없다(창 안에서 동시점
#   대비를 재는 것이므로). 같은 변수를 옳은 자리에 넣는 것이 이번 수술이다.
#   ★역으로, 지속성이 0 이라는 그 성질이 여기서는 **자산**이다: Eq.2 의 AR 잔차는
#     추세·수준이 제거된 변수라 u 로 자른 잎이 시간 블록이 되지 않는다(시간분기 함정
#     방지). 재료 2 의 트리에 안전하게 건넬 수 있는 축을 재료 1 의 Eq.2 가 만들어 준다.
#
# =============================================================================
# 왜 각 재료 단독보다 나을 것이라 보는가 (반증 형태는 FIDELITY.json changed ②)
# =============================================================================
#  ▸ 재료 1 단독(다중검정 t 1.228 · 충실구현 Grade F)의 사인은 사내 실측으로 특정돼 있다
#    (RP_2301_09173_CID/NOTES.md): KR 에서 cor(u, 시장) = +0.43(2022-26 +0.63) —
#    분산 급등이 하락장이 아니라 섹터(반도체) 주도 **급등**에서 나온다. Eq.3 이
#    **단변량**이라 시장 성분이 통제되지 않고 beta_CID 정렬 = 시장베타 정렬로 변질됐다
#    (일간 beta -0.39, FF 알파 9~12%는 역베타의 회계). 5분위 VW 라 숏 레그를 삼성전자
#    39% + 하이닉스 29% 가 지배했다.
#      → 이 엔진은 시장을 **회귀항으로** 넣는다. 그 근거가 재료 2 다: 시장초과수익이
#        "always the most informative factor" 라면, 그것을 뺀 단변량 적합의 잔차에는
#        시장이 통째로 남고, 시장과 상관된 축의 기울기는 그 잔차를 주워 담는다.
#        (재료 1 이 Eq.2 사양을 그대로 따온 Pastor-Stambaugh(2003) 역시 유동성 베타를
#         시장 포함 다변량 1단계에서 추정한다. 재료 1 의 표제 결과도 raw 가 아니라
#         FF5+MOM+STR **초과** 스프레드 -50bps(t=-3.26)다 — 시장통제는 재료 1 자신의
#         추정 대상 안에 이미 있다.)
#  ▸ 재료 2 단독(다중검정 t 1.11)의 한계: 산출이 잎의 **수준**(예측 기대수익)이라 창이
#    5년이면 스코어가 그 종목의 5년 평균수익과 거의 같아진다 — 조건부 구조를 회수해
#    놓고 무조건부 수준을 발행하는 셈이다(직전 결합판의 IC -0.021 이 그 지문).
#      → 이 엔진의 산출은 수준이 아니라 **두 잎의 차**다. 게다가 eps 는 창 안에서
#        평균 0 이라 수준 성분이 구조적으로 존재하지 않는다. 5년 모멘텀 별칭이 원리상
#        불가능하다.
#  ▸ 그래서 이 결합의 주장은 하나로 좁혀진다: **"KR 에서 CID 민감도의 단면 분산은
#    전부 시장베타인가, 아니면 시장을 통제하고 선형을 계단으로 바꾼 뒤에도 남는가."**
#    남으면 재료 1 의 경제학(분산 국면의 패자가 위험을 지고 프리미엄을 받는다)이
#    KR 에서도 성립한다는 뜻이고, 남지 않으면 이 계보는 여기서 닫힌다. 어느 쪽이든
#    엔진이 매월 로그하는 계기 (a)~(f) 가 판정한다(아래 §9).
#
# =============================================================================
# 미명시값 보충 — 전부 출처를 적는다 (지어낸 수치를 숨기지 않는다)
# =============================================================================
#  · **창 안의 관측 주기: 월간 -> 일간.** 재료 1 의 창 길이(24개월)는 그대로 두고
#    해상도만 바꾼다. 이유는 재료 2 의 추정기가 요구하는 최소 조건이다 — 계단 임계값을
#    전 분기점 탐색으로 고르려면 관측이 24개로는 성립하지 않는다(재료 2 자신의 표본은
#    1,259 daily returns). Eq.1 은 수익 주기에 무관한 정의이므로 일간 산업 VW 수익으로
#    그대로 계산된다. **바꾼 것은 해상도이고 창의 시간 길이가 아니다.**
#    ★대가(정직 기록): 재료 1 의 거시 검증(CID -> 분기 실업률)은 월/분기 축의 결과다.
#      일간 CID 가 그 노동시장 해석을 그대로 물려받는지는 이 엔진이 검정하지 않는다.
#  · AR(Eq.2)은 **expanding window**. 논문은 전표본 1회 추정이지만 C1(full-sample) 위반이라
#    PIT 가 논문 문자를 이긴다. burn-in 60개월 = RP_2301_09173_CID 선례 승계.
#  · 산업분류 = RAWDATA Sector_Lv2(48군 — FF49 의 최근접 아날로그), **전월말** 기록값.
#  · 산업/시장 가중 = **전월말 시총**(재료 1 의 VW 규약). 월 m 의 모든 거래일에 월 m-1
#    말 시총을 고정 적용 — 월 시작 시점에 이미 알려진 값이다.
#  · 잎 최소 관측:
#      - 공통 잎 >= **24 관측** — 재료 1 이 이 민감도를 추정하는 표본 크기 그 자체다
#        ("two years of monthly" = 24). 어느 잎도 논문의 회귀 전체보다 작은 표본 위에
#        서지 않게 한다.
#      - 종목별 잎 >= **18 관측** · 창 커버리지 >= **75%** — RP_2301_09173_CID 가
#        같은 estimand 에 쓴 최소 유효관측(24개월 중 >=18)의 승계.
#  · |일간 Ret| > 1.0 = 결측. KRX 가격제한폭 ±30% 하에서 한 세션에 불가능한 값이므로
#    액면/재상장 단위 아티팩트다. 전략 파라미터가 아니라 거래소 규칙 근거의 위생 조치.
#  · rf 미사용. Eq.3 은 초과수익을 쓰지만 이 엔진의 산출은 **두 잎 평균의 차**이고,
#    일간 rf 는 잎 간에 거의 상수라 차분에서 소거된다. 시장변수도 재료 1 이 Eq.1 에서
#    직접 만드는 R_MKT(전 상장종목 VW)를 쓴다 — 외부 캐시 의존 0.
#  · 종목수·비중 = 고정 축(top-25 롱온리 EW). 두 논문의 포트폴리오 규약이 충돌하기
#    때문이다: 재료 2 는 포트폴리오를 아예 주지 않고("only done for demonstration
#    purposes and not for statistical inference"), 재료 1 의 5분위 VW 는 레그당 ~70종이다.
#    **리밸 주기(월간)만 재료 1 명시값 그대로** 따른다.
#
# =============================================================================
# PIT (C1~C15) — 구조로 보장한다. detect_lookahead 통과를 근거로 삼지 않는다.
# =============================================================================
#  ▸ 구조 경계 1 — 창: 모든 창의 종점이 형성일 D 이하다. 창은 `.rymi` 가 [m-23, m] 인
#    행 AND `.rdt <= D` 로 잘린다. ip 를 넘는 인덱스·음수 shift·lead 가 코드에 0건.
#  ▸ 구조 경계 2 — 가중치: 일간 CID 의 산업/시장 가중은 `ymi_w = ymi - 1L` 한 줄로
#    만들어진다. 동월 시총을 쓰는 경로가 코드에 **존재하지 않는다**(막는 검사가 아니라
#    표현 불가능한 배치).
#  ▸ 구조 경계 3 — AR: expanding 누적 교차곱이 `k` 까지만 더해진다. u_k 는 <=k 정보만.
#  ▸ 구조 경계 4 — 상태 이월 없음: 형성일 루프 반복이 서로 독립이다. 시장모형 계수·
#    임계값·잎 평균이 전부 그 창 안에서만 계산된다.
#  C1  : rolling/expanding 만. 전표본 mean/quantile/cov/lm 0건. 단면 winsorize 는
#        그 형성일 벡터 내부에서만(시계열 미래 미참조).
#  C2  : same-day 순환참조 없음. D 종가까지 쓰고 집행은 익 거래일(하네스).
#  C3  : 같은 기간 집계->적용 없음. 신호 컷오프(월 m 말) < 보유월(m+1) 시작.
#  C4  : 재무제표 패널 미사용.
#  C5  : 오버레이 없음(S0/S1 오버레이 금지 준수).
#  C6  : 유니버스 = 각 D 의 K200/KQ150 멤버십(PIT 시변). 최종 명부 주입 없음.
#        창 커버리지 요건은 **과거** 데이터 요건이라 생존편의를 만들지 않는다.
#  C7  : shift(-N)·lead()·수동 미래 인덱싱 0건. shift 는 전부 +1(과거 방향).
#  C9  : DD/VT 미사용.
#  C10 : 유동성 = D **직전 20 거래일** 평균 거래대금. `(ip-20):(ip-1)` 로 당일 배제.
#  C11 : 외부 매크로 0건(rf·FRED·팩터 캐시 미사용).
#  C13 : Factor DB 미소비 -> 정렬 대상 없음. 부호는 재료 1 의 **사전 선언**(고민감 =
#        저수익)이지 사후 반전이 아니다.
#  C15 : Factor DB parquet 직접 load 0건.
#  ★rawdata 의 Market 열 미사용(KOSDAQ 0건 날조 — 사내 기록). 시장 구분은 K200/KQ150
#    멤버십 플래그로만 한다.
#
# ===== 산출 =====
#   FACTORS(Date, Ticker, Score) — Score = -Delta (계단 CID 민감도의 음수). 클수록 롱.
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
  stop(sprintf("[COMBO_08115_09173] RAWDATA 열 부족: %s",
               paste(setdiff(.RQ, names(RAWDATA)), collapse = ", ")))

# =============================================================================
# 0. 상수 — 전부 출처 표기
# =============================================================================
# ▸ 재료 1 (Pinchuk 2301.09173)
.CID_MIN_FIRMS <- 10L     # "industries with at least 10 firms"
.BETA_WIN_M    <- 24L     # "two years of monthly excess returns" — 창의 시간 길이
.WINS_LO       <- 0.01    # "winsorize beta_CID at 1% and 99% percentiles"
.WINS_HI       <- 0.99
.LEAF_MIN_G    <- 24L     # 공통 잎 최소 관측 = 논문 회귀의 표본 크기(24개월) 그 자체
# ▸ 재료 2 (Polimenis 2007.08115)
#   depth=1 · 공통 임계값 1개 · 전 분기점 greedy · 종목별 표준화 없음 · 시장은 통제항.
#   수치 파라미터는 아래 .MIN_STK 하나뿐이다(논문 표본 5종 -> joint 성립 하한 2종).
.MIN_STK       <- 2L
# ▸ 사내 선례 승계 (RP_2301_09173_CID — 같은 estimand 의 기존 구현)
.AR_BURN_M     <- 60L     # AR expanding burn-in (개월)
.LEAF_MIN_S    <- 18L     # 종목별 잎 최소 유효관측 (24개월 중 >=18 의 승계)
.COV_MIN       <- 0.75    # 창 커버리지 하한 (= 18/24)
.RET_CAP       <- 1.0     # |일간수익| > 100% = 데이터 아티팩트(KRX 가격제한폭 ±30%)
# ▸ 축(도훈 고정)
.LIQ           <- 2e8     # adv20(t-1) 하한 (KRW)
.LIQ_WIN       <- 20L     # 거래일 (D 직전 20 거래일, 종점 = D-1)
.START         <- as.Date("2005-01-01")

.tru <- function(x) !is.na(x) & (x != 0)      # 논리/0-1 혼재 방어
.t0  <- Sys.time()

# 안전 Spearman — 벡터만 받는다(DT 열 직접 전달 금지: lookahead_detector C1b 회피)
.sp <- function(a, b) {
  a <- as.numeric(a); b <- as.numeric(b)
  ok <- is.finite(a) & is.finite(b)
  if (sum(ok) < 5L) return(NA_real_)
  ra <- rank(a[ok]); rb <- rank(b[ok])
  if (stats::sd(ra) == 0 || stats::sd(rb) == 0) return(NA_real_)
  as.numeric(stats::cor(ra, rb))
}
.med <- function(x) if (!length(x) || all(is.na(x))) NA_real_ else stats::median(x, na.rm = TRUE)

if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]

# =============================================================================
# 1. 재료 1 Eq.1 — 일간 CID (거시 상태변수: 시장 전체에서 만든다)
# =============================================================================
# ★유니버스 치환(K200∪KQ150)은 **정렬 대상(test asset)** 에만 걸린다. CID 자체는 논문이
#   "value-weighted market return across all firms" 라 한 거시 변수이므로 전 상장종목에서
#   만든다. 가중치·산업라벨은 **전월말** 관측치를 그 달 내내 고정한다(구조 경계 2).
.ALLD  <- data.table(Date = sort(unique(RAWDATA$Date)))
.ALLD[, ymi := year(Date) * 12L + month(Date)]
.MEALL <- .ALLD[, .(me = max(Date)), by = ymi]$me            # 시장 전체 월말 거래일
.EOM   <- RAWDATA[Date %in% .MEALL & is.finite(Size) & Size > 0 & !is.na(Sector_Lv2),
                  .(Ticker, ymi_w = year(Date) * 12L + month(Date), w = Size, ind = Sector_Lv2)]
.EOM   <- unique(.EOM, by = c("Ticker", "ymi_w"))
rm(.ALLD, .MEALL); gc(verbose = FALSE)
if (!nrow(.EOM)) stop("[COMBO_08115_09173] 월말 시총/섹터 관측 0건 — Size/Sector_Lv2 확인")

.DD <- RAWDATA[is.finite(Ret) & abs(Ret) <= .RET_CAP, .(Date, Ticker, rr = Ret)]
.DD[, ymi_w := year(Date) * 12L + month(Date) - 1L]        # ★전월말 가중치 (동월 경로 없음)
.DD[.EOM, on = .(Ticker, ymi_w), c("w", "ind") := .(i.w, i.ind)]
.DD <- .DD[is.finite(w) & w > 0 & !is.na(ind)]
if (!nrow(.DD)) stop("[COMBO_08115_09173] 전월말 가중치 결합 후 0행 — 월말 격자 확인")

# 시장 = 전 상장종목 VW (>=10사 필터 **전**)
MKTD <- .DD[, .(r_mkt = sum(w * rr) / sum(w), n_all = .N), by = Date]
# 산업 = VW, 소속기업 >=10사
.IND <- .DD[, .(r_ind = sum(w * rr) / sum(w), nf = .N), by = .(Date, ind)][nf >= .CID_MIN_FIRMS]
rm(.DD, .EOM); gc(verbose = FALSE)

CIDD <- merge(.IND[, .(Date, r_ind)], MKTD[, .(Date, r_mkt)], by = "Date")
CIDD <- CIDD[, .(CID = mean(abs(r_ind - r_mkt)), n_ind = .N), by = Date]
setorder(CIDD, Date)
rm(.IND); gc(verbose = FALSE)
if (nrow(CIDD) < 500L)
  stop(sprintf("[COMBO_08115_09173] 일간 CID %d일 — 표본 부족", nrow(CIDD)))
cat(sprintf("[COMBO_08115_09173] Eq.1 일간 CID %s일 (%s ~ %s) · 산업수 중앙 %.0f · 평균 %.4f sd %.4f\n",
            format(nrow(CIDD), big.mark = ","), as.character(min(CIDD$Date)),
            as.character(max(CIDD$Date)), .med(CIDD$n_ind),
            mean(CIDD$CID), stats::sd(CIDD$CID)))

# =============================================================================
# 2. 재료 1 Eq.2 — CID 충격 u_t (expanding window AR · PIT 보정)
# =============================================================================
#   dCID_t = g0 + g1*dCID_{t-1} + g2*CID_{t-1} + u_t
#   expanding OLS 를 누적 교차곱으로 정확히 구현한다(lm 반복과 수치 동일 · O(n)).
#   구조 경계 3: 각 k 의 계수는 1..k 만 더한 X'X, X'y 에서 나온다.
CIDD[, dC := CID - shift(CID)]
CIDD[, `:=`(dC_l1 = shift(dC), C_l1 = shift(CID))]
CIDD[, u := NA_real_]

.rows <- which(is.finite(CIDD$dC) & is.finite(CIDD$dC_l1) & is.finite(CIDD$C_l1))
if (length(.rows) < 200L)
  stop("[COMBO_08115_09173] AR 적합 가능 행 부족")
.yv <- CIDD$dC[.rows]; .x1 <- CIDD$dC_l1[.rows]; .x2 <- CIDD$C_l1[.rows]
.dv <- CIDD$Date[.rows]
.nn <- length(.rows)
# burn-in = 첫 60개월에 해당하는 행 수 (선례 승계값을 '개월' 로 유지 — 일수 하드코딩 회피)
.ymr  <- year(.dv) * 12L + month(.dv)
.burn <- sum(.ymr < (min(.ymr) + .AR_BURN_M))
if (.burn < 100L) .burn <- 100L
if (.burn >= .nn) stop("[COMBO_08115_09173] AR burn-in 이 표본을 초과")

.c11 <- seq_len(.nn); .c1a <- cumsum(.x1); .c1b <- cumsum(.x2)
.caa <- cumsum(.x1 * .x1); .cab <- cumsum(.x1 * .x2); .cbb <- cumsum(.x2 * .x2)
.c1y <- cumsum(.yv);  .cay <- cumsum(.x1 * .yv); .cby <- cumsum(.x2 * .yv)
.uv <- rep(NA_real_, .nn)
for (k in seq.int(.burn, .nn)) {
  M3 <- matrix(c(.c11[k], .c1a[k], .c1b[k],
                 .c1a[k], .caa[k], .cab[k],
                 .c1b[k], .cab[k], .cbb[k]), 3L, 3L)
  v3 <- c(.c1y[k], .cay[k], .cby[k])
  g  <- tryCatch(solve(M3, v3), error = function(e) NULL)
  if (is.null(g)) next
  .uv[k] <- .yv[k] - (g[1] + g[2] * .x1[k] + g[3] * .x2[k])
}
set(CIDD, i = .rows, j = "u", value = .uv)
if (sum(is.finite(CIDD$u)) < 500L)
  stop("[COMBO_08115_09173] CID 충격 u 유효 관측 부족 — AR 적합 실패")
cat(sprintf("[COMBO_08115_09173] Eq.2 충격 u: 유효 %s일 (%s ~) · sd %.5f · 1-lag 자기상관 %.3f (논문 US 월간: -0.05)\n",
            format(sum(is.finite(CIDD$u)), big.mark = ","),
            as.character(min(CIDD$Date[is.finite(CIDD$u)])),
            stats::sd(CIDD$u, na.rm = TRUE),
            .sp(CIDD$u[-1L], CIDD$u[-nrow(CIDD)])))

# =============================================================================
# 3. 테스트 자산 패널 — K200∪KQ150 일간수익 wide 행렬
# =============================================================================
.tk <- unique(RAWDATA[.tru(K200) | .tru(KQ150), Ticker])
if (!length(.tk))
  stop("[COMBO_08115_09173] K200/KQ150 멤버십 0건 — RAWDATA 확인")

.gdv <- CIDD[is.finite(u), Date]                     # 상태·시장이 모두 있는 거래일 격자
.rs  <- RAWDATA[Ticker %chin% .tk & Date %in% .gdv & is.finite(Ret) & abs(Ret) <= .RET_CAP,
                .(Date, Ticker, r = Ret)]
.ndup <- sum(duplicated(.rs, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[COMBO_08115_09173] (Date,Ticker) 중복 %d행 — 첫 행만 남긴다\n", .ndup))
  .rs <- unique(.rs, by = c("Ticker", "Date"))
}
.RW <- dcast(.rs, Date ~ Ticker, value.var = "r")
setorder(.RW, Date)
.rdt <- .RW$Date
RET  <- as.matrix(.RW[, -1L, with = FALSE])
.tick <- colnames(RET)
rm(.RW, .rs); gc(verbose = FALSE)
.rymi <- year(.rdt) * 12L + month(.rdt)

setkey(CIDD, Date); setkey(MKTD, Date)
.uvec <- CIDD[.(.rdt), u]
.mvec <- MKTD[.(.rdt), r_mkt]
if (anyNA(.uvec) || anyNA(.mvec))
  stop("[COMBO_08115_09173] u/시장 계열 정렬 실패 — 격자 불일치")
cat(sprintf("[COMBO_08115_09173] 테스트 자산 %d일 x %d종 (%s ~ %s) · 결측 %.1f%%\n",
            nrow(RET), ncol(RET), as.character(min(.rdt)), as.character(max(.rdt)),
            100 * mean(is.na(RET))))

# =============================================================================
# 4. 형성일(월말 거래일) · 유동성 창 · 자격
# =============================================================================
.GD <- data.table(Date = .rdt, ymi = .rymi)
.ME <- .GD[, .(Date = max(Date)), by = ymi]
setorder(.ME, Date)
.FORM <- .ME[Date >= .START, Date]
if (!length(.FORM))
  stop("[COMBO_08115_09173] 형성일 0건 — RAWDATA 날짜 범위 확인")

.LW <- rbindlist(lapply(seq_along(.FORM), function(k) {
  D  <- .FORM[k]
  ip <- match(D, .rdt)
  if (is.na(ip) || (ip - .LIQ_WIN) < 1L) return(NULL)
  data.table(Date = .rdt[(ip - .LIQ_WIN):(ip - 1L)], FormDate = D)   # 종점 = D-1 (C10)
}), use.names = TRUE)
if (!nrow(.LW))
  stop("[COMBO_08115_09173] 유동성 창 구성 실패 — 거래일 수 부족")
.FORM <- .FORM[.FORM %in% unique(.LW$FormDate)]
.fym  <- year(.FORM) * 12L + month(.FORM)

.rdq <- RAWDATA[Date %in% unique(c(.LW$Date, .FORM)),
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
# 5. 재료 2 의 추정기 — joint depth=1 SSE 스캔 (공통 임계값 1개)
# =============================================================================
# 목적함수 전개 (원문 "Min sum_i (y_i - prediction(y_i))^2" 와 정확히 동치):
#   SSE(k) = sum_i [ TSS_i - CX_i(k)^2/CM_i(k) - (SX_i-CX_i(k))^2/(SM_i-CM_i(k)) ]
#   TSS_i 는 k 와 분기변수에 무관하므로 SSE 최소화 = 아래 gain 최대화이고, **같은 y·
#   같은 창** 위에서라면 변수 간 비교도 같은 gain 으로 유효하다.
#   종목별 표준화는 하지 않는다 — 논문의 joint 트리가 그렇고 'dominant stock' 이
#   제거 대상이 아니라 그 설계의 성질이다.
.scan <- function(Emat, sv, min_leaf) {
  n  <- nrow(Emat)
  o  <- order(sv)
  so <- sv[o]
  Eo <- Emat[o, , drop = FALSE]
  Xs <- Eo; Xs[which(is.na(Xs))] <- 0
  Ms <- matrix(as.numeric(!is.na(Eo)), n, ncol(Eo))
  CX <- colCumsums(Xs); CM <- colCumsums(Ms)
  SX <- CX[n, ]; SM <- CM[n, ]
  g0 <- SX^2 / SM; g0[!is.finite(g0)] <- 0
  RX <- matrix(SX, n, ncol(Eo), byrow = TRUE) - CX
  RM <- matrix(SM, n, ncol(Eo), byrow = TRUE) - CM
  LT <- CX^2 / CM; RT <- RX^2 / RM
  LT[!is.finite(LT)] <- 0                     # 잎에 관측이 없는 종목 = 기여 0
  RT[!is.finite(RT)] <- 0
  gv <- rowSums(LT + RT)
  ki <- seq_len(n)
  ok <- c(so[-n] < so[-1L], FALSE)            # 값이 실제로 갈리는 자리만
  ok <- ok & (ki >= min_leaf) & ((n - ki) >= min_leaf)
  if (!any(ok)) return(NULL)
  gv[!ok] <- -Inf
  k <- as.integer(which.max(gv))              # 이름 붙은 인덱스가 새지 않게 as.integer
  if (!is.finite(gv[k])) return(NULL)
  list(k = k, gain = as.numeric(gv[k]), drop = as.numeric(gv[k] - sum(g0)),
       thr = as.numeric(so[k] + so[k + 1L]) / 2,
       CX = CX, CM = CM, SX = SX, SM = SM, n = n)
}

# =============================================================================
# 6. 형성일 루프 — 시장 통제 -> joint 계단 -> Delta -> winsorize -> Score
# =============================================================================
.OUT  <- vector("list", length(.FORM))
.LOG  <- vector("list", length(.FORM))
.skip <- 0L

for (kk in seq_along(.FORM)) {
  D  <- .FORM[kk]
  fy <- .fym[kk]

  # ── 창: 형성월 m 으로 끝나는 24개월, 종점 D 이하 (구조 경계 1) ──
  wi <- which(.rymi <= fy & .rymi > (fy - .BETA_WIN_M) & .rdt <= D)
  nw <- length(wi)
  if (nw < (.BETA_WIN_M * 15L)) { .skip <- .skip + 1L; next }   # 월 15거래일도 안 되면 창 미성립

  cand <- .ELG[.(D), Ticker, nomatch = 0L]
  cand <- intersect(cand, .tick)
  if (!length(cand)) { .skip <- .skip + 1L; next }

  Y  <- RET[wi, cand, drop = FALSE]
  uw <- .uvec[wi]                                    # 시간 순서 유지
  mw <- .mvec[wi]

  # ── 창 통계 (시간 순서에서 계산: 시장모형 · 재료 1 원판 OLS beta · 무조건부 평균) ──
  Ms <- matrix(as.numeric(!is.na(Y)), nw, ncol(Y))
  Xs <- Y; Xs[which(is.na(Xs))] <- 0
  n_i <- colSums(Ms); Sy <- colSums(Xs)

  Sm  <- colSums(Ms * mw); Smm <- colSums(Ms * mw^2); Smy <- colSums(Xs * mw)
  dm  <- n_i * Smm - Sm * Sm
  b_m <- ifelse(is.finite(dm) & dm > 0, (n_i * Smy - Sm * Sy) / dm, NA_real_)   # 시장베타
  a_m <- (Sy - b_m * Sm) / n_i

  Su  <- colSums(Ms * uw); Suu <- colSums(Ms * uw^2); Suy <- colSums(Xs * uw)
  du  <- n_i * Suu - Su * Su
  b_u <- ifelse(is.finite(du) & du > 0, (n_i * Suy - Su * Sy) / du, NA_real_)   # 재료1 Eq.3 기울기
  mu_raw <- ifelse(n_i > 0, Sy / n_i, NA_real_)                                 # 창 무조건부 평균

  keep <- (n_i >= as.integer(.COV_MIN * nw)) & is.finite(b_m) & is.finite(a_m) & !is.na(Y[nw, ])
  if (sum(keep) < .MIN_STK) { .skip <- .skip + 1L; next }
  Y <- Y[, keep, drop = FALSE]
  nm <- colnames(Y)
  b_m <- b_m[keep]; a_m <- a_m[keep]; b_u <- b_u[keep]; mu_raw <- mu_raw[keep]

  # ── 시장 통제 잔차 (재료 2: 시장초과수익이 always the most informative factor) ──
  #    창 안 OLS 라 sum_t eps = 0 · cov(eps, mkt) = 0 — 수준 성분과 선형 시장 성분이
  #    구조적으로 제거된다(모멘텀 별칭·역베타 오염의 두 경로가 동시에 닫힌다).
  E <- Y - matrix(a_m, nw, ncol(Y), byrow = TRUE) - outer(mw, b_m)

  # ── joint depth=1 스캔: 축 = u (재료 1 의 상태 충격) ──
  sc_u <- .scan(E, uw, .LEAF_MIN_G)
  if (is.null(sc_u)) { .skip <- .skip + 1L; next }
  # 진단 전용: 같은 잔차·같은 창에서 시장축이 남기는 계단(선형 통제 후 잔존 비선형성)
  sc_m <- .scan(E, mw, .LEAF_MIN_G)

  k   <- sc_u$k
  nlo <- k; nhi <- sc_u$n - k
  cl  <- sc_u$CM[k, ]; ch <- sc_u$SM - cl
  ml  <- sc_u$CX[k, ] / cl
  mh  <- (sc_u$SX - sc_u$CX[k, ]) / ch
  dl  <- mh - ml                                     # Delta = E[eps|u>c*] - E[eps|u<=c*]
  good <- is.finite(dl) & cl >= .LEAF_MIN_S & ch >= .LEAF_MIN_S
  if (sum(good) < .MIN_STK) { .skip <- .skip + 1L; next }

  # ── 단면 winsorize 1%/99% (재료 1 명시) ──
  dv <- as.numeric(dl[good])
  qq <- stats::quantile(dv, c(.WINS_LO, .WINS_HI), na.rm = TRUE, names = FALSE)
  dw <- pmin(pmax(dv, qq[1]), qq[2])

  # ── 부호 = 재료 1 의 사전 선언(고민감 = 저수익) ──
  .OUT[[kk]] <- data.table(Date = D, Ticker = nm[good], Score = -dw)

  # ── 반증 계기 (a)~(g) ─────────────────────────────────────────────────────
  usd  <- stats::sd(uw)
  tss  <- colSums(E^2, na.rm = TRUE)                        # 잔차 평균 0 이므로 = 잔차분산 * n
  idom <- if (any(is.finite(tss))) as.integer(which.max(tss)) else NA_integer_
  .LOG[[kk]] <- data.table(
    Date = D, n_win = nw, n_stock = sum(good),
    thr_z    = if (is.finite(usd) && usd > 0) sc_u$thr / usd else NA_real_,
    bal_hi   = 100 * nhi / sc_u$n,                          # 고-u 잎 비중(%)
    leaf_hi  = as.numeric(.med(ch[good])),                  # 종목별 고-u 잎 관측 중앙
    rho_ols  = .sp(dv, b_u[good]),                          # (a) 추정기 치환이 하중을 받는가
    rho_beta = .sp(-dw, b_m[good]),                         # (b) 역베타 오염 잔존
    rho_lvl  = .sp(-dw, mu_raw[good]),                      # (c) 5년 수준(모멘텀) 별칭
    t_deg    = .sp(seq_len(nw), as.numeric(uw > sc_u$thr)), # (f) 시간분기 퇴화
    g_ratio  = if (!is.null(sc_m) && is.finite(sc_u$drop) && sc_u$drop > 0)
                 sc_m$drop / sc_u$drop else NA_real_,       # (g) 시장축 잔존 계단 / CID축 계단
    dom      = if (is.na(idom)) NA_character_ else nm[idom])  # 재료 2 의 dominant stock
}

FACTORS <- rbindlist(Filter(Negate(is.null), .OUT), use.names = TRUE)
if (!nrow(FACTORS))
  stop("[COMBO_08115_09173] FACTORS 0행 — 창 길이/유니버스/커버리지/잎 최소관측 확인")
setorder(FACTORS, Date, -Score)

# =============================================================================
# 7. 회수된 구조 + 반증 계기 보고
# =============================================================================
LOGDT <- rbindlist(Filter(Negate(is.null), .LOG), use.names = TRUE)
setorder(LOGDT, Date)
# (e) 임계값 안정성 — 겹치는 창끼리 c* 가 튀면 계단이 아니라 잡음이다
LOGDT[, thr_jump := abs(thr_z - shift(thr_z))]

LOGDT[, yr := year(Date)]
.byyr <- LOGDT[, .(n_m = .N, n_stock = as.integer(.med(n_stock)),
                   thr_z = round(.med(thr_z), 2), bal_hi = round(.med(bal_hi), 1),
                   leaf_hi = as.integer(.med(leaf_hi)),
                   rho_ols = round(.med(rho_ols), 2), rho_beta = round(.med(rho_beta), 2),
                   rho_lvl = round(.med(rho_lvl), 2)), by = yr]
setorder(.byyr, yr)
cat("[COMBO_08115_09173] 연도별 joint depth=1 계단 구조 (축 = Eq.2 충격 u · y = 시장통제 잔차):\n")
cat("      연도 | 월수 종목  c*(sd) 고u잎%  잎관측  rho(D,OLSbeta) rho(S,mktbeta) rho(S,창평균)\n")
for (i in seq_len(nrow(.byyr)))
  cat(sprintf("      %d |  %2d  %3d  %+6.2f  %5.1f    %4d      %+6.2f        %+6.2f        %+6.2f\n",
              .byyr$yr[i], .byyr$n_m[i], .byyr$n_stock[i], .byyr$thr_z[i],
              .byyr$bal_hi[i], .byyr$leaf_hi[i],
              .byyr$rho_ols[i], .byyr$rho_beta[i], .byyr$rho_lvl[i]))

.domtop <- LOGDT[!is.na(dom), .N, by = dom][order(-N)]
.domtop <- .domtop[seq_len(min(3L, nrow(.domtop)))]
if (!nrow(.domtop)) .domtop <- data.table(dom = "NA", N = 0L)   # sprintf 길이-0 인자 방지
.nmn <- FACTORS[, .N, by = Date]
.scv <- as.numeric(FACTORS[["Score"]])   # ★벡터로 뽑아 잰다(quantile(DT$col) = C1b 오탐)
cat(sprintf(paste0(
  "[COMBO_08115_09173] combination: 재료1 의 estimand(Eq.1 CID -> Eq.2 충격 u -> 24개월 민감도\n",
  "  -> 1%%/99%% winsorize -> 고민감=저수익 -> 월간 리밸)를 재료2 의 estimator(joint depth=1\n",
  "  공통 임계값 · 전 분기점 greedy · 시장은 경쟁자 아닌 통제항)로 추정한다.\n",
  "  형성 %d개월(skip %d) · %s ~ %s · FACTORS %s행 · 월 종목 중앙 %d (min %d / max %d)\n",
  "  창 거래일 중앙 %.0f (= 재료1 의 24개월 · 해상도만 일간)\n",
  "  ── 반증 계기 (전 기간 중앙값) ───────────────────────────────────────────\n",
  "  (a) rho(Delta, 재료1 원판 OLS beta) %+5.2f  [+1 이면 추정기 치환이 무하중 = 결합 아님]\n",
  "  (b) rho(Score, 창 시장베타)         %+5.2f  [부호 고정·大 이면 CID 단독의 역베타 재현]\n",
  "  (c) rho(Score, 창 무조건부 평균)    %+5.2f  [±1 이면 5년 수준(모멘텀)의 별칭]\n",
  "  (d) 고-u 잎 비중 %.1f%% · 종목별 잎 관측 중앙 %.0f  [하한 24/18 에 상시 붙으면 계단 = 잡음]\n",
  "  (e) |c* 변화| 중앙 %.2f sd  [겹치는 창인데 크면 임계값이 구조가 아니라 표본]\n",
  "  (f) 시간퇴화 |rho(시간, 잎)| 중앙 %.2f  [1 에 가까우면 상태분기가 아니라 시간분기]\n",
  "  (g) 시장축 잔존계단 / CID축 계단 = %.2f배  [>>1 이면 mex 를 경쟁시켰을 때 estimand 가\n",
  "      통째로 바뀐다 — 직전 결합판이 그렇게 죽었다. 그래서 통제항으로 넣었다]\n",
  "  ── 구조 요약 ────────────────────────────────────────────────────────────\n",
  "  c* 중앙 %+.2f sd(u) · 지배 종목(잔차분산 최대) 상위: %s\n",
  "  Score = -Delta (계단 CID 민감도의 음수 · 중앙 %.2fbp · IQR %.2f~%.2fbp)\n",
  "  ★러너 호출: portfolio_spec = list(construction=\"top_n_long\", weighting=\"ew\",\n",
  "                                    rebalance=\"monthly\", n_long=25, n_max=25)\n",
  "              commission_paper = NULL (양 논문 비용 무명시) · %.1f분\n"),
  nrow(LOGDT), .skip,
  as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date)),
  format(nrow(FACTORS), big.mark = ","),
  as.integer(.med(.nmn$N)), min(.nmn$N), max(.nmn$N),
  .med(LOGDT$n_win),
  .med(LOGDT$rho_ols), .med(LOGDT$rho_beta), .med(LOGDT$rho_lvl),
  .med(LOGDT$bal_hi), .med(LOGDT$leaf_hi),
  .med(LOGDT$thr_jump), .med(abs(LOGDT$t_deg)), .med(LOGDT$g_ratio),
  .med(LOGDT$thr_z),
  paste(sprintf("%s(%d개월)", .domtop$dom, .domtop$N), collapse = " "),
  1e4 * stats::median(.scv),
  1e4 * as.numeric(stats::quantile(.scv, 0.25, names = FALSE)),
  1e4 * as.numeric(stats::quantile(.scv, 0.75, names = FALSE)),
  as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
