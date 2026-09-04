# =============================================================================
# engine.R — RP_AUTO_COMBO_combo_2007_08115_2301_09
#   결합 전략 (fidelity = "combination". 정본 = FIDELITY.json)
#
#   [A] Pinchuk, Mykola (2023) "Labor Income Risk and the Cross-Section of
#       Expected Returns". arXiv:2301.09173   https://arxiv.org/abs/2301.09173
#   [B] Polimenis, Vassilis (2020) "Uncovering a factor-based expected return
#       conditioning structure with Regression Trees jointly for many stocks".
#       arXiv:2007.08115                      https://arxiv.org/abs/2007.08115
#
# =============================================================================
# 0. 원문 접근 신고 (지어내지 않기 위한 전제)
# =============================================================================
#  [A] arXiv HTML 전문 확보(https://arxiv.org/html/2301.09173v1, v1 2023-01-22).
#      아래 A1~A6 은 그 전문에서 축자 확인한 것이다.
#  [B] 2020년 투고분이라 arXiv 가 HTML 판을 만들지 않았다(/html·ar5iv 404/redirect).
#      /abs 초록만 1차 확보했고, 방법론 축자 인용(B1~B4)은 **저장소 승계 인용**이다 —
#      선행 세션이 PDF 전문을 텍스트 렌더러로 읽어 확보해 둔 문장을
#      04_Research/strategies/RP_AUTO_2007_08115/engine.R 헤더 Q1~Q6 에서 승계했다.
#      ★따라서 [B] 의 축자 인용은 이 세션이 직접 검증한 것이 아니다(그 축만 미검증으로
#      분리). 다만 초록은 직접 확인했고, 승계 인용의 핵심 3항(depth=1 · joint
#      multi-output · mex 가 언제나 최고 정보량)은 초록 문면과 정합한다:
#        "the most informative factor is always the market excess return factor",
#        "a) the balance of a depth=1 tree ... b) the mechanism behind depth=1 tree
#         balance in a joint regression tree c) the dominant stock in a joint
#         regression tree".
#
# --- [A] 논문 명시값 (전부 그대로 소비) --------------------------------------
#  A1 CID_t = (1/N) * sum_i |R_i,t - R_MKT,t|                            (Eq.1)
#       R_i,t = 산업 포트폴리오 월간수익(시총가중, 전월말 시총) · 49 산업
#       R_MKT,t = 전 상장기업 시총가중 시장수익
#       산업은 소속 기업 10개 이상인 것만("at least 10 firms")
#  A2 충격: d(CID_t) = g0 + g1*d(CID_{t-1}) + g2*CID_{t-1} + u_t         (Eq.2)
#       잔차 u_t 를 이후 회귀의 CID 로 사용. "1-lag autocorrelation of CID is -0.05"
#  A3 민감도: R_i,t = a + b*CID_t + e_t, "two years of monthly excess returns"
#  A4 b 를 단면 1%/99% winsorize ("winsorized at 1% and 99% percentiles")
#  A5 정렬: 매월 5분위 · 전월말 시총가중 · 월간 리밸. L/S = 연 5.9%p(월 49bps)
#  A6 방향(사전 선언): "Annualized returns of the stocks with high sensitivity to
#       CID are 5.9% lower than the returns of the stocks with low sensitivity."
#       → 매수 우선순위 = 低민감도. "CID peaks during periods of accelerated
#       sectoral reallocation and heightened uncertainty" (위험은 **꼭짓점 국면**)
#
# --- [B] 논문 명시값 (승계 인용 — 위 0. 신고 참조) ---------------------------
#  B1 "Limiting to max depth = 1"
#  B2 "The cost function that is minimized when choosing split points is the sum
#      squared error across all training samples against their sub-region
#      prediction  Min for all split points  Sum_i ( y_i - prediction(y_i) )^2"
#     "all input variables and all possible split points are evaluated and chosen
#      in a greedy algorithm. The algorithm maximizes the drop in that value"
#  B3 "a single model capable of predicting simultaneously n stocks is built" /
#     "correlation information enters the tree structure"
#     → 종목별 표준화 없는 **다출력 단일 트리**. 그래서 "the dominant stock in a
#       joint regression tree" 가 논점이 된다(제거 대상이 아니라 설계의 일부).
#  B4 데이터 = 일간수익 **1,259 daily returns** (5종 · 2015-01-05~2020-04-30).
#     회수된 구조: 분기변수는 언제나 mex, 임계값은 꼬리(-350bp~+300bp),
#     balance 는 1-99% ~ 22-78% 로 극단적 불균형.
#  B5 포트폴리오·비용·종목수·비중·리밸 = 논문에 전무(서술적 진단 연구).
#
# =============================================================================
# 1. 결합 설계 — 무엇을 어떻게 맞물렸나
# =============================================================================
#  이 저장소는 이 재료 집합에서 "두 엔진 신호의 rank-Z 평균" 기저를 5회 측정했고
#  전부 단독을 못 넘었다(그 계보 최고 다중검정 t 0.766). 그래서 **신호를 합치지
#  않는다**. 합치는 지점은 스코어가 아니라 **추정기 내부**다.
#
#  ▸ [A] 가 대는 것 = 상태변수. CID(Eq.1) → AR 잔차 충격 u(Eq.2). 그리고 정렬 방향
#    (A6: 민감도 高 = 기대수익 低)과 단면 winsorize(A4)와 월간 리밸(A5).
#  ▸ [B] 가 대는 것 = 그 상태변수를 읽는 **추정기**. joint(다출력) depth=1 회귀트리 ·
#    전 종목 SSE 합의 greedy 최소화 · 종목별 표준화 없음 · 창 1,259 거래일.
#  ▸ 맞물리는 자리 = [A] 의 β_CID(24개월 OLS **기울기**)를 [B] 의 **잎 평균 대비**로
#    갈아끼운다. delta_i = mu(hi-u leaf)_i - mu(lo-u leaf)_i. 임계값 c* 는 내가 고르지
#    않고 [B] 의 SSE 기준이 데이터에서 고른다. 스코어 = -delta_i (A6 의 사전 선언 방향).
#  ▸ 두 번째 맞물림 = [B] 의 결론("mex 가 언제나 가장 정보량이 큰 분기변수")을
#    **응답변수 전처리**로 소비한다. u 에게 무엇이 남았는지 묻기 전에 시장 채널을
#    먼저 응답에서 뺀다: e_i,t = r_i,t - (a_i + b_i * MKT_t), (a_i,b_i) = 같은 창의 OLS.
#    트리는 이 잔차 위에서 적합된다.
#
#  ★왜 이것이 각 재료 단독보다 나을 것이라 보는가 (반증 가능한 형태는 §2)
#   (1) [A] 단독의 KR 실패 기전은 이 저장소가 실측했다(RP_20260902_122546_22268 ·
#       RP_2301_09173_CID/NOTES.md): cor(u, KOSPI200 월수익) = +0.43(2022–26 +0.63).
#       분산 급등이 하락장이 아니라 반도체 주도 **급등**에서 나오므로 beta_CID 정렬이
#       시장베타 정렬로 붕괴한다(일간 beta vs BM −0.39 · raw CAGR 0.6% 인데 FF 알파
#       8.9~12.3% = 역베타의 회계). 결합은 이 채널을 **항등식으로** 닫는다:
#           mu(hi)_i - mu(lo)_i  [잔차]
#         = { mu(hi)_i - mu(lo)_i }[원수익]  -  b_i * { mean(MKT|hi) - mean(MKT|lo) }
#       즉 beta_i * MKT 기여가 정확히 소거된다. 역베타의 **수준** 성분 a_i 는 두 잎에
#       같은 상수로 들어가 차분에서 사라진다. 잎 balance 와 무관하게 성립한다.
#   (2) [B] 단독의 실패 기전은 분기변수가 시장수익 하나뿐이라 회수한 스코어가
#       "시장 국면별 기대수익 수준" = 베타의 재표현이었다는 것이다. 결합은 분기변수를
#       시장이 아닌 **산업분산 충격**으로 바꾸고, 시장 성분은 응답에서 이미 뺐다.
#   (3) 추정기 교체 자체의 근거: [A] 의 경제학은 꼭짓점 국면의 위험이다(A6 인용).
#       그런데 [A] 의 추정기(24개월 OLS 기울기)는 전 구간을 균등 가중한 **선형 평균**이다.
#       [B] 의 계단은 임계값을 데이터에서 찾고 그 임계값이 실증적으로 **꼬리에 선다**(B4).
#       [A] 의 변수에 [B] 의 추정기를 대면 "꼬리 국면에서의 상태 대비"를 재게 된다.
#   ▸ 부수 효과(주장 아님, 기록): 추정 표본이 24 monthly obs → 1,259 daily obs
#     (약 60 monthly states) 로 늘고, 시장베타 b_i 도 일간 1,259 관측에서 추정된다.
#
#  ★쓰지 않은 것: [B] 의 SMB/HML. 인프라의 KR FF3 는 월간뿐이라 일간 패널이 없고,
#    내가 KR 일간 SMB/HML 을 구성하면 장부가 정의·절단점·형성주기를 논문 밖에서
#    지어내야 한다. [B] 자신의 결론이 "in all cases the most informative factor is
#    always the market excess return factor" 이므로, 이 축소가 제거하는 것은 결과가
#    만장일치로 보고된 경마다. 대가는 정직하게: KR 에서 SMB/HML 이 이겼을 가능성을
#    이 엔진은 검정하지 않는다.
#
# =============================================================================
# 2. 반증 조건 — 엔진이 매월 계산해 로그에 인쇄한다
# =============================================================================
#  (a) 시장채널 차단: 스코어와 창내 시장베타 b_i 의 월별 스피어만 상관 |rho| 의
#      중앙값이 0.30 을 넘으면 (1) 의 주장은 거짓이다.
#  (b) 꼬리 국면: u-트리의 잎 balance(hi 잎 일수 비중) 중앙값이 40~60% 구간에 들면
#      "[A] 의 위험은 꼬리 국면이고 [B] 의 계단이 그것을 찾는다"는 전제가 거짓이다.
#  (c) 조건부 정보: **원수익** 위에서 u-트리의 SSE 감소가 MKT-트리보다 작으면
#      (drop_u / drop_mkt 중앙값 < 1) CID 는 시장 대비 추가 조건부 정보를 갖지
#      않으므로 결합의 근거가 소멸한다.
#      ※ 이 경마는 u 에 **불리하게** 기울어 있다: u 는 월간이라 잎 최소단위가
#        1개월(약 21일)인데 MKT 는 일간이라 최소 2일이다. u 가 그래도 이기면 강한 진술.
#  셋 중 하나라도 성립하면 이 설계는 재료 단독보다 나을 이유가 없다.
#
# =============================================================================
# 3. PIT (C1~C15) — 구조로 보장한다 (detect_lookahead 통과를 근거로 삼지 않는다)
# =============================================================================
#  ▸ 구조 경계 1 — 모든 창의 종점이 형성일 D(월 T 마지막 거래일) 이하다. 창은 항상
#    `(ip - .T_WIN + 1L):ip`, ip = match(D, 수익일자). ip 를 넘는 인덱스가 코드에 없고
#    음수 shift·lead·수동 미래 인덱싱 0건이다.
#  ▸ 구조 경계 2 — 분기변수 u 는 월간이라 일별로 펼치는데, **그 달의 CID 월말이 D 이하일
#    때만** 펼친다(.cid_me <= D). 그렇지 않은 달의 날은 창에서 제거된다. 즉 창 안의
#    모든 u 값이 D 시점에 이미 관측됐다. 보유월 T+1 의 u 는 어디에도 쓰이지 않는다.
#    (창 내부에서 u_m 이 월 m 의 앞쪽 날들과 동시점인 것은 [A] Eq.3 이 동시점 회귀인
#     것과 같다 — 추정 대상이 동시점 조건부 구조이고, 산출은 그 구조의 함수일 뿐
#     미래 상태를 필요로 하지 않는다.)
#  ▸ 구조 경계 3 — 트리 적합·임계값·잎 평균·시장베타가 전부 그 창 안에서만 계산된다.
#    형성일 간 상태 이월이 없다(루프 반복 독립). 전 표본 통계 0건.
#  C1  rolling/expanding 만. AR(Eq.2)은 expanding(<= t) — [A] 는 전표본 1회 추정이나
#      그것은 C1 위반이라 PIT 가 논문 문자를 이긴다(burn-in 60개월).
#      트리·시장모형의 모든 평균은 길이 .T_WIN 창 내부 부분집합 평균이다.
#  C2  same-day 순환참조 없음. D 종가까지 쓰고 집행은 익 거래일(하네스).
#  C3  같은 기간 집계->적용 없음. 신호창 종점(D) < 보유월(T+1) 시작.
#  C4  재무 패널 미사용.
#  C5  오버레이 없음(S0/S1 오버레이 금지 준수). 신호 컷오프 = D < 홀딩월 시작.
#  C6  유니버스 = 각 D 의 K200/KQ150 멤버십(PIT 시변). 최종 명부 주입 없음.
#      창 커버리지 요건은 **과거 데이터 요건**이라 생존편의를 만들지 않는다.
#  C7  shift(-N)·lead()·수동 미래 인덱싱 0건. shift 는 전부 +1(과거 방향).
#  C8  FM weight 미사용.  C9  DD/VT 미사용.
#  C10 유동성 = D **직전 20 거래일** 평균 거래대금. `lo:(ip - 1L)` 로 당일 배제.
#  C11 외부 매크로 미사용(FRED 등). CID 는 저장소 내부 패널에서 구성.
#  C13 Factor DB 미소비 → 부호 정렬 대상 없음. 수동 부호 반전 0건 —
#      Score = -delta 는 [A] A6 가 **사전 선언한** 방향이다.
#  C14 IC 접근 없음.   C15 Factor DB parquet 직접 load 0건.
#  ★rawdata 의 Market 열 미사용(KOSDAQ 0건 날조 — 사내 기록). 시장 구분은 K200/KQ150
#    멤버십 플래그로만 한다.
#
# =============================================================================
# 4. 산출
# =============================================================================
#   FACTORS(Date, Ticker, Score) — Score = -delta_w (클수록 롱 = [A] 의 Q1 다리)
#   러너 권장 호출([A] A5 명시값 그대로):
#     portfolio_spec = list(construction = "quantile_long_short", weighting = "vw",
#                           long_frac = 0.20, short_frac = 0.20,
#                           rebalance = "monthly", n_max = 1000L)
#     commission_paper = NULL ([A] 비용 무명시 · [B] 도 무명시 → gross 병기)
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(matrixStats)
}))

set.seed(20070811L)   # 난수 미사용(결정론적 엔진) — 재현성 선언 고정

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.RQ <- c("Date", "Ticker", "Ret", "Size", "Sector_Lv2", "Close", "Vol", "K200", "KQ150")
if (!all(.RQ %in% names(RAWDATA)))
  stop(sprintf("[COMBO_2007_2301] RAWDATA 열 부족: %s",
               paste(setdiff(.RQ, names(RAWDATA)), collapse = ", ")))

# =============================================================================
# 5. 상수 — 논문에서 온 것 / 고정 축에서 온 것 / 타당성 하한
# =============================================================================
# ▸ [A] 에서 온 것
.CID_MIN_FIRMS <- 10L        # A1  "at least 10 firms"
.WINS_LO       <- 0.01       # A4  단면 winsorize
.WINS_HI       <- 0.99       # A4
.A_BETA_MON    <- 24L        # A3  [A] 의 창 길이 — 여기서는 '상태 draw 최소 개수' 로만 쓴다
# ▸ [B] 에서 온 것
.T_WIN         <- 1259L      # B4  1,259 daily returns
.MIN_LEAF      <- 2L         # B2/B3 잎 평균이 성립하는 하한(종목별 관측)
.MIN_STK       <- 5L         # B4  joint 트리가 성립하는 종목수(논문 표본 n)
# ▸ 고정 축(도훈)
.LIQ           <- 2e8        # adv20(t-1) 하한 (KRW)
.LIQ_WIN       <- 20L        # 거래일 (D 직전 20 거래일, 종점 = D-1)
.START         <- as.Date("2005-01-01")
# ▸ 타당성 하한 — 전략 파라미터가 아니다(성과를 보고 고른 값이 아니다)
.MIN_COV       <- 0.80       # 창 커버리지 = 5년 중 4년. 거래정지 며칠로 전 이력이
                             #   버려지는 것을 막는 자리.
.MIN_EPI       <- 2L         # 잎당 **서로 다른 달** 최소 개수. 잎 평균이 단일 에피소드
                             #   인공물이 되지 않는 산술 하한(저장소 실측: 구속하는 건
                             #   월 수가 아니라 에피소드 수). [B] 가 1-99% 분할을 보고
                             #   하므로 balance 를 강제하지 않는다 — 하한만 둔다.
.CID_AR_BURNIN <- 60L        # AR expanding 최소 관측([A] 는 전표본 1회 — PIT 보정)
.RET_CAP       <- 1.0        # |일간수익| > 100% = 데이터 아티팩트. KRX 가격제한폭이
                             #   ±30% 라 한 세션에 물리적으로 불가능하다(수정주가 실패의
                             #   지문). 윈저라이즈가 아니라 결측 처리.

.tru <- function(x) !is.na(x) & (x != 0)      # 논리/0-1 혼재 방어
.t0  <- Sys.time()

if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]

# =============================================================================
# 6. 시장 일간수익 계열 + 거래일 격자 (유령 거래일 배제)
# =============================================================================
.bm <- NULL
if (exists("BM_DT") && is.data.table(BM_DT) && nrow(BM_DT)) {
  .b <- copy(BM_DT)
  if (!inherits(.b$Date, "Date")) .b[, Date := as.Date(Date)]
  setorder(.b, Date)
  if (!"BM_Ret" %in% names(.b) && "BM_Close" %in% names(.b))
    .b[, BM_Ret := BM_Close / shift(BM_Close, 1L) - 1]
  if ("BM_Ret" %in% names(.b)) .bm <- unique(.b[is.finite(BM_Ret), .(Date, MKT = BM_Ret)], by = "Date")
  rm(.b)
}
if ((is.null(.bm) || !nrow(.bm)) && "BM_Ret" %in% names(RAWDATA))
  .bm <- unique(RAWDATA[is.finite(BM_Ret), .(Date, MKT = BM_Ret)], by = "Date")
if (is.null(.bm) || !nrow(.bm))
  stop("[COMBO_2007_2301] 시장 일간수익 계열 부재 — BM_DT(BM_Ret/BM_Close) 확인")
setorder(.bm, Date)

.gd <- sort(intersect(unique(RAWDATA$Date), .bm$Date))
.gd <- as.Date(.gd, origin = "1970-01-01")
if (length(.gd) < (.T_WIN + 40L))
  stop(sprintf("[COMBO_2007_2301] 거래일 격자 %d일 — 창 %d일에 못 미침", length(.gd), .T_WIN))

.GD <- .bm[Date %in% .gd]
setorder(.GD, Date)
.GD[, ymi := year(Date) * 12L + month(Date)]

# =============================================================================
# 7. [A] Eq.1 — CID (산업 VW 월간수익의 시장 대비 평균절대편차)
#    ★CID 는 거시 상태변수라 [A] 대로 **시장 전체**(전 상장종목)에서 만든다.
#      "value-weighted market return across all firms from CRSP" — 유니버스 치환
#      (K200∪KQ150)은 정렬 대상(test asset)에만 걸린다.
# =============================================================================
DD <- RAWDATA[, .(Date, Ticker, Ret, Size, Sector_Lv2)]
DD[, rr := Ret]
DD[!is.finite(rr) | abs(rr) > .RET_CAP, rr := NA_real_]
DD[, ymi := year(Date) * 12L + month(Date)]

.CME <- DD[, .(cid_me = max(Date)), by = ymi]      # 그 달 CID 가 확정되는 날짜
setkey(.CME, ymi)

MON <- DD[, .(mret = if (sum(is.finite(rr)) >= 1L) prod(1 + rr[is.finite(rr)]) - 1 else NA_real_),
          by = .(Ticker, ymi)]
# 각 cid_me 는 자기 달 안에만 있으므로 `Date %in% cid_me` = '그 달의 월말 행' (조인 불필요)
EOM <- DD[Date %in% .CME$cid_me, .(Ticker, ymi, size_end = Size, ind = Sector_Lv2)]
EOM <- unique(EOM, by = c("Ticker", "ymi"))
MON <- merge(MON, EOM, by = c("Ticker", "ymi"))

setorder(MON, Ticker, ymi)                          # A1 가중치 = 전월말 시총
MON[, `:=`(size_prev = shift(size_end, 1L), ymi_prev = shift(ymi, 1L)), by = Ticker]
MON[!is.finite(ymi_prev) | ymi_prev != ymi - 1L, size_prev := NA_real_]

VAL <- MON[is.finite(mret) & is.finite(size_prev) & size_prev > 0 & !is.na(ind)]
IP  <- VAL[, .(nf = .N, r_ind = sum(mret * size_prev) / sum(size_prev)),
           by = .(ymi, ind)][nf >= .CID_MIN_FIRMS]
MKT <- MON[is.finite(mret) & is.finite(size_prev) & size_prev > 0,
           .(r_mkt = sum(mret * size_prev) / sum(size_prev)), by = ymi]
CIDT <- merge(IP, MKT, by = "ymi")[, .(CID = mean(abs(r_ind - r_mkt)), n_ind = .N), by = ymi]
setorder(CIDT, ymi)
rm(DD, VAL, IP, MKT, EOM); gc(verbose = FALSE)

# =============================================================================
# 8. [A] Eq.2 — CID 충격 u_t (expanding AR · PIT 보정)
#    각 u_k 는 '월 k 시점에 관측 가능한 정보만으로 적합한 회귀의 마지막 잔차' 다.
# =============================================================================
CIDT[, dC := CID - shift(CID, 1L)]
CIDT[, `:=`(dC_l1 = shift(dC, 1L), C_l1 = shift(CID, 1L))]
CIDT[, u := NA_real_]
.fit_rows <- which(is.finite(CIDT$dC) & is.finite(CIDT$dC_l1) & is.finite(CIDT$C_l1))
if (length(.fit_rows) < .CID_AR_BURNIN)
  stop("[COMBO_2007_2301] CID 월 수가 AR burn-in 에 못 미침")
for (kk in seq.int(.CID_AR_BURNIN, length(.fit_rows))) {
  sub <- CIDT[.fit_rows[seq_len(kk)]]                # <= t 만 (expanding)
  f   <- stats::lm(dC ~ dC_l1 + C_l1, data = sub)
  rsd <- stats::residuals(f)
  set(CIDT, i = .fit_rows[kk], j = "u", value = as.numeric(rsd[length(rsd)]))
}
.uac <- stats::cor(CIDT$CID[-1], CIDT$CID[-nrow(CIDT)], use = "complete.obs")
cat(sprintf("[COMBO_2007_2301] [A]Eq.1-2 · CID 월 %d (u 유효 %d) · 산업수 중앙 %.0f · CID 1-lag 자기상관 %.3f (논문 US −0.05)\n",
            nrow(CIDT), sum(is.finite(CIDT$u)), stats::median(CIDT$n_ind, na.rm = TRUE), .uac))

UM <- merge(CIDT[is.finite(u), .(ymi, u)], .CME, by = "ymi")   # u + 그 값이 확정된 날짜
setkey(UM, ymi)

# =============================================================================
# 9. 형성일(격자 월말) · 유동성 창(종점 = D-1)
# =============================================================================
.ME   <- .GD[, .(Date = max(Date)), by = ymi]
setorder(.ME, Date)
.FORM <- .ME[Date >= .START, Date]
if (!length(.FORM)) stop("[COMBO_2007_2301] 형성일 0건 — RAWDATA 날짜 범위 확인")

.gdv <- .GD$Date
.LW <- rbindlist(lapply(seq_along(.FORM), function(k) {
  D  <- .FORM[k]
  ip <- match(D, .gdv)
  if (is.na(ip) || (ip - .LIQ_WIN) < 1L) return(NULL)
  data.table(Date = .gdv[(ip - .LIQ_WIN):(ip - 1L)], FormDate = D)   # C10: 당일 배제
}), use.names = TRUE)
if (!nrow(.LW)) stop("[COMBO_2007_2301] 유동성 창 구성 실패 — 거래일 수 부족")
.FORM <- .FORM[.FORM %in% unique(.LW$FormDate)]

# =============================================================================
# 10. 일간 수익 wide 행렬 (test asset 후보 = K200∪KQ150 이력 보유 종목)
# =============================================================================
.tk <- unique(RAWDATA[.tru(K200) | .tru(KQ150), Ticker])
if (!length(.tk)) stop("[COMBO_2007_2301] K200/KQ150 멤버십 0건 — RAWDATA 확인")

.rw <- RAWDATA[Ticker %chin% .tk & Date %in% .gdv & is.finite(Ret),
               .(Date, Ticker, Ret = fifelse(abs(Ret) <= .RET_CAP, Ret, NA_real_))]
.rw <- unique(.rw, by = c("Ticker", "Date"))
.RWD <- dcast(.rw, Date ~ Ticker, value.var = "Ret")
setorder(.RWD, Date)
.rdt <- .RWD$Date
RET  <- as.matrix(.RWD[, -1L, with = FALSE])
RET[!is.finite(RET)] <- NA_real_
.tick <- colnames(RET)
rm(.rw, .RWD); gc(verbose = FALSE)
cat(sprintf("[COMBO_2007_2301] 수익 행렬 %d일 x %d종 (%s ~ %s) · 결측 %.1f%%\n",
            nrow(RET), ncol(RET), as.character(min(.rdt)), as.character(max(.rdt)),
            100 * mean(is.na(RET))))

# 시장수익을 RET 행에 정렬
.MXD <- .GD[Date %in% .rdt, .(Date, MKT, ymi)]
setkey(.MXD, Date)
.mktv <- .MXD[.(.rdt), MKT]
.ymiv <- .MXD[.(.rdt), ymi]
if (anyNA(.mktv) || anyNA(.ymiv))
  stop("[COMBO_2007_2301] 시장계열/월인덱스 정렬 실패 — 격자 불일치")

# 일별 u (월간 상태변수를 그 달의 거래일에 펼침) + 그 값이 확정된 날짜
.uv    <- UM[.(.ymiv), u]
.uconf <- UM[.(.ymiv), cid_me]

# =============================================================================
# 11. 유동성·멤버십 자격 (D 단면)
# =============================================================================
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
# 12. [B] joint depth=1 회귀트리 — 다출력 · 종목별 표준화 없음 · greedy SSE
#     SSE(k) = sum_j [ TSS_j - CX_j(k)^2/CM_j(k) - (SX_j-CX_j(k))^2/(SM_j-CM_j(k)) ]
#     TSS_j 는 k 에 무관 → SSE 최소화 = 아래 gain 최대화. drop = SSE 감소량(B2).
#     min_dv = 잎당 서로 다른 분기변수 값(= u 의 경우 '달') 최소 개수.
# =============================================================================
.joint_tree <- function(Ymat, sv, min_dv) {
  n <- nrow(Ymat); p <- ncol(Ymat)
  if (n < 4L || p < 1L) return(NULL)
  o  <- order(sv)
  ss <- sv[o]
  Ys <- Ymat[o, , drop = FALSE]
  Mk <- matrix(as.numeric(!is.na(Ys)), n, p)
  X0 <- Ys; X0[is.na(X0)] <- 0

  CX <- colCumsums(X0); CM <- colCumsums(Mk)
  SX <- CX[n, ];        SM <- CM[n, ]
  RX <- matrix(SX, n, p, byrow = TRUE) - CX
  RM <- matrix(SM, n, p, byrow = TRUE) - CM
  LT <- CX^2 / CM;  LT[!is.finite(LT)] <- 0
  RT <- RX^2 / RM;  RT[!is.finite(RT)] <- 0
  bv <- SX^2 / SM;  bv[!is.finite(bv)] <- 0
  gn <- rowSums(LT + RT)

  dv  <- cumsum(c(TRUE, ss[-1L] != ss[-n]))          # 정렬 위치별 '서로 다른 값' 순번
  ndv <- dv[n]
  ok  <- c(ss[-n] < ss[-1L], FALSE) & (dv >= min_dv) & ((ndv - dv) >= min_dv)
  if (!any(ok)) return(NULL)
  gn[!ok] <- -Inf
  k <- which.max(gn)
  if (!is.finite(gn[k])) return(NULL)

  list(k = k, ord = o, cstar = (ss[k] + ss[k + 1L]) / 2,
       n_lo = k, n_hi = n - k, dv_lo = dv[k], dv_hi = ndv - dv[k], n_dv = ndv,
       mu_lo = CX[k, ] / CM[k, ], mu_hi = RX[k, ] / RM[k, ],
       nb_lo = CM[k, ],           nb_hi = RM[k, ],
       drop  = gn[k] - sum(bv))
}

# =============================================================================
# 13. 형성일 루프
#     (i)  창 = D 로 끝나는 .T_WIN 거래일 중, u 가 D 시점에 확정된 달의 날들만
#     (ii) 응답 = 시장모형 잔차 e_i,t = r_i,t - (a_i + b_i*MKT_t)   [창 내 OLS]
#     (iii)[B] joint depth=1 트리를 u 위에 적합 → 공통 임계값 c*_u, 잎 평균
#     (iv) delta_i = mu_hi_i - mu_lo_i   ([A] beta_CID 의 트리 대응물)
#     (v)  진단: 원수익 위 u-트리 vs MKT-트리 SSE 감소 경마([B] Table 2c 확장)
# =============================================================================
.OUT  <- vector("list", length(.FORM))
.LOG  <- vector("list", length(.FORM))
.skip <- 0L

for (kk in seq_along(.FORM)) {
  D  <- .FORM[kk]
  ip <- match(D, .rdt)
  if (is.na(ip) || ip < .T_WIN) { .skip <- .skip + 1L; next }

  wi <- (ip - .T_WIN + 1L):ip                       # 종점 = D. ip 초과 인덱스 없음.
  uw <- .uv[wi]; cw <- .uconf[wi]
  # ★구조 경계 2: 그 달의 CID 가 D 이후에야 확정되는 날은 창에서 제거한다.
  vr <- which(is.finite(uw) & !is.na(cw) & cw <= D)
  if (length(vr) < as.integer(.MIN_COV * .T_WIN)) { .skip <- .skip + 1L; next }
  wi <- wi[vr]; uw <- uw[vr]
  mw <- .mktv[wi]
  n  <- length(wi)
  if (length(unique(uw)) < .A_BETA_MON) { .skip <- .skip + 1L; next }  # 상태 draw 하한

  cand <- .ELG[.(D), Ticker, nomatch = 0L]
  cand <- intersect(cand, .tick)
  if (length(cand) < .MIN_STK) { .skip <- .skip + 1L; next }

  Y  <- RET[wi, cand, drop = FALSE]
  Mk <- !is.na(Y)
  # 커버리지 + **D 당일 거래**(창 말행이 아니라 ip 행으로 본다 — 월 T 가 창에서 빠져도 자격은 D 기준)
  kp <- (colSums(Mk) >= as.integer(.MIN_COV * n)) & !is.na(RET[ip, cand])
  if (sum(kp) < .MIN_STK) { .skip <- .skip + 1L; next }
  Y  <- Y[, kp, drop = FALSE]; Mk <- Mk[, kp, drop = FALSE]
  nm <- colnames(Y)
  p  <- ncol(Y)

  # ---- (ii) 창 내 시장모형 OLS (종목별 결측 패턴을 마스크 합으로 처리) ----
  M1  <- Mk * 1.0
  Y0  <- Y; Y0[!Mk] <- 0
  nj  <- colSums(M1)
  Sy  <- colSums(Y0)
  Sm  <- as.numeric(crossprod(mw, M1))
  Smm <- as.numeric(crossprod(mw * mw, M1))
  Smy <- as.numeric(crossprod(mw, Y0))
  den <- nj * Smm - Sm * Sm
  bj  <- rep(NA_real_, p)
  bj[is.finite(den) & den > 0] <- ((nj * Smy - Sm * Sy) / den)[is.finite(den) & den > 0]
  aj  <- (Sy - bj * Sm) / nj
  gb  <- is.finite(aj) & is.finite(bj)
  if (sum(gb) < .MIN_STK) { .skip <- .skip + 1L; next }
  Y <- Y[, gb, drop = FALSE]; nm <- nm[gb]; bj <- bj[gb]; aj <- aj[gb]
  E <- Y - (matrix(aj, n, length(aj), byrow = TRUE) + outer(mw, bj))

  # ---- (iii)(iv) [B] 트리를 [A] 의 상태변수 위에 · 응답 = 시장 잔차 ----
  tr <- .joint_tree(E, uw, .MIN_EPI)
  if (is.null(tr)) { .skip <- .skip + 1L; next }
  dl <- tr$mu_hi - tr$mu_lo
  gd <- is.finite(dl) & tr$nb_lo >= .MIN_LEAF & tr$nb_hi >= .MIN_LEAF
  if (sum(gd) < .MIN_STK) { .skip <- .skip + 1L; next }

  .OUT[[kk]] <- data.table(Date = D, Ticker = nm[gd], delta = as.numeric(dl[gd]),
                           mbeta = as.numeric(bj[gd]))

  # ---- (v) 진단: 원수익 위 경마([B] 의 실험) + 잎 시장 불균형 + 잎 balance ----
  tu <- .joint_tree(Y, uw, .MIN_EPI)
  tm <- .joint_tree(Y, mw, .MIN_LEAF)
  ms <- mw[tr$ord]
  .LOG[[kk]] <- data.table(
    Date = D, n_stock = sum(gd), n_day = n, n_month = tr$n_dv,
    u_split = tr$cstar, bal_hi = 100 * tr$n_hi / n,
    mo_lo = tr$dv_lo, mo_hi = tr$dv_hi,
    mkt_gap_bp = 1e4 * (mean(ms[(tr$k + 1L):n]) - mean(ms[seq_len(tr$k)])),
    drop_u = if (is.null(tu)) NA_real_ else tu$drop,
    drop_m = if (is.null(tm)) NA_real_ else tm$drop,
    m_split_bp = if (is.null(tm)) NA_real_ else 1e4 * tm$cstar)
  rm(Y, Y0, Mk, M1, E, tr, tu, tm)
}

RAW <- rbindlist(Filter(Negate(is.null), .OUT), use.names = TRUE)
if (!nrow(RAW)) stop("[COMBO_2007_2301] 스코어 0행 — 창 길이/유니버스/커버리지 확인")

# =============================================================================
# 14. [A] A4 단면 winsorize(1%/99%) + A6 방향 → FACTORS
#     ★임계값 c* 가 전 종목 공통(joint)이므로, delta 에 공통 스칼라를 곱해
#       '단위 u 당 기울기' 로 바꿔도 단면 순위는 불변이다 — 정렬은 그 재척도에 무관.
# =============================================================================
RAW[, delta_w := {
  qq <- stats::quantile(delta, c(.WINS_LO, .WINS_HI), na.rm = TRUE, names = FALSE)
  pmin(pmax(delta, qq[1]), qq[2])
}, by = Date]

# A6: CID 민감도 高 = 기대수익 低 → 매수 우선순위 = 低민감도.
FACTORS <- RAW[is.finite(delta_w), .(Date, Ticker, Score = -delta_w)]
setorder(FACTORS, Date, -Score)

# =============================================================================
# 15. 반증 조건 3종 인쇄 (§2) + 회수된 구조 보고
# =============================================================================
LOGDT <- rbindlist(Filter(Negate(is.null), .LOG), use.names = TRUE)

# (a) 스코어 vs 창내 시장베타 — 월별 스피어만
.RC <- RAW[is.finite(delta_w) & is.finite(mbeta),
           .(rho = {
             xv <- as.numeric(-delta_w); yv <- as.numeric(mbeta)
             if (length(xv) >= 5L) as.numeric(stats::cor(xv, yv, method = "spearman")) else NA_real_
           }), by = Date]
.rhov <- as.numeric(.RC[["rho"]]); .rhov <- .rhov[is.finite(.rhov)]
.a_med <- if (length(.rhov)) stats::median(abs(.rhov)) else NA_real_
.a_fail <- is.finite(.a_med) && .a_med > 0.30

# (b) 잎 balance
.balv  <- as.numeric(LOGDT[["bal_hi"]]); .balv <- .balv[is.finite(.balv)]
.b_med <- if (length(.balv)) stats::median(.balv) else NA_real_
.b_fail <- is.finite(.b_med) && .b_med >= 40 && .b_med <= 60

# (c) 원수익 경마 — drop_u / drop_mkt
.ru <- as.numeric(LOGDT[["drop_u"]]); .rm2 <- as.numeric(LOGDT[["drop_m"]])
.rat <- .ru / .rm2; .rat <- .rat[is.finite(.rat)]
.c_med <- if (length(.rat)) stats::median(.rat) else NA_real_
.c_fail <- is.finite(.c_med) && .c_med < 1

LOGDT[, yr := year(Date)]
.byyr <- LOGDT[, .(n_m = .N, n_stk = as.integer(stats::median(n_stock)),
                   n_mo = as.integer(stats::median(n_month)),
                   bal = round(stats::median(bal_hi), 1),
                   mo_hi = as.integer(stats::median(mo_hi)),
                   gap = round(stats::median(mkt_gap_bp), 1),
                   rat = round(stats::median(drop_u / drop_m, na.rm = TRUE), 3)), by = yr]
setorder(.byyr, yr)
cat("[COMBO_2007_2301] 연도별 회수 구조 (분기변수 = [A] 의 CID 충격 u · 응답 = 시장모형 잔차):\n")
cat("    연도 | 월  종목  창월수  hi잎%  hi잎월수  잎간MKT평균차  drop_u/drop_mkt\n")
for (r in seq_len(nrow(.byyr)))
  cat(sprintf("    %d | %2d  %4d   %3d   %5.1f%%    %3d      %8.1fbp        %6.3f\n",
              .byyr$yr[r], .byyr$n_m[r], .byyr$n_stk[r], .byyr$n_mo[r],
              .byyr$bal[r], .byyr$mo_hi[r], .byyr$gap[r], .byyr$rat[r]))

.nmn <- FACTORS[, .N, by = Date]
.msp <- as.numeric(LOGDT[["m_split_bp"]]); .msp <- .msp[is.finite(.msp)]
cat(sprintf(paste0(
  "[COMBO_2007_2301] combination = [A]2301.09173 상태변수(CID 충격 u) x [B]2007.08115 추정기(joint depth=1 tree)\n",
  "  형성 %d개월(skip %d) · %s ~ %s · FACTORS %s행 · 월 종목 중앙 %d (min %d / max %d) · 창 %d거래일\n",
  "  ── 반증 조건 (§2 · 셋 중 하나라도 TRUE 면 설계 근거 소멸) ──\n",
  "  (a) |rho(Score, 창내 시장베타)| 중앙 %.3f  (>0.30 이면 시장채널 차단 실패)  → %s\n",
  "  (b) hi 잎 balance 중앙 %.1f%% (hi 잎 달 수 중앙 %d/%d)  (40~60%%면 꼬리 전제 실패) → %s\n",
  "  (c) 원수익 SSE감소 비 drop_u/drop_mkt 중앙 %.3f  (<1 이면 조건부 정보 없음)   → %s\n",
  "  ── 참고 ── MKT-트리 임계값 중앙 %.1fbp ([B] US 보고 −350~+300bp) · 잎간 MKT 평균차 중앙 %.1fbp\n",
  "  ※ (c) 는 u 에 불리하게 기울어 있다: u 잎 최소단위 = 1개월(약 21일) vs MKT 잎 최소 2일\n",
  "  ★러너 권장: portfolio_spec = list(construction=\"quantile_long_short\", weighting=\"vw\",\n",
  "               long_frac=0.20, short_frac=0.20, rebalance=\"monthly\", n_max=1000L)  ([A] A5 명시값)\n",
  "               commission_paper = NULL (양 논문 비용 무명시) · %.1f분\n"),
  nrow(LOGDT), .skip, as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date)),
  format(nrow(FACTORS), big.mark = ","),
  as.integer(stats::median(.nmn$N)), min(.nmn$N), max(.nmn$N), .T_WIN,
  .a_med, if (.a_fail) "FAIL" else "pass",
  .b_med, as.integer(stats::median(as.numeric(LOGDT[["mo_hi"]]))),
  as.integer(stats::median(as.numeric(LOGDT[["n_month"]]))),
  if (.b_fail) "FAIL" else "pass",
  .c_med, if (.c_fail) "FAIL" else "pass",
  if (length(.msp)) stats::median(.msp) else NA_real_,
  stats::median(as.numeric(LOGDT[["mkt_gap_bp"]]), na.rm = TRUE),
  as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
