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
# 0. 원문 접근 신고 — 지어내지 않기 위한 전제
# =============================================================================
#  [A] arXiv HTML 전문 확보(https://arxiv.org/html/2301.09173v1 · v1 2023-01-22).
#      A1~A8 은 그 전문에서 이 세션이 직접 확인했다.
#  [B] 2020년 투고분이라 arXiv 가 HTML 판을 만들지 않는다(/html·ar5iv 404/redirect).
#      /abs 초록은 이 세션이 직접 확인했고, 방법론 축자 인용(B1~B5)은 **저장소 승계
#      인용**이다 — 선행 세션이 PDF 전문을 텍스트 렌더러로 읽어 확보해 둔 문장을
#      04_Research/strategies/RP_AUTO_2007_08115/engine.R 헤더 Q1~Q6 에서 승계했다.
#      ★[B] 의 축자 인용은 이 세션이 직접 검증한 것이 아니다(그 축만 미검증 분리).
#      다만 승계 인용의 핵심 4항은 직접 확인한 초록 문면과 정합한다:
#        "the most informative factor is always the market excess return factor" /
#        "a) the balance of a depth=1 tree as it relates to properties of the stock
#         return distribution, b) the mechanism behind depth=1 tree balance in a
#         joint regression tree and c) the dominant stock in a joint regression tree"
#
# --- [A] 논문 명시값 ---------------------------------------------------------
#  A1 CID_t = (1/N) * sum_i |R_i,t - R_MKT,t|                              (Eq.1)
#     "I use monthly value-weighted returns of Fama-French 49 industry portfolios"
#     "across the industries with at least 10 firms" (로버스트니스가 아니라 baseline)
#     R_MKT = "the value-weighted market return across all firms from CRSP (vwretd)"
#  A2 d(CID_t) = g0 + g1*d(CID_{t-1}) + g2*CID_{t-1} + u_t                 (Eq.2)
#     "Abusing notation, I refer to the residual u_hat_t as CID_t" · 전표본 1회 추정
#     "1-lag autocorrelation of CID is -0.05, implying very low persistence"
#  A3 R_it = a + b*CID_t + e_t · "two years of monthly excess returns"      (Eq.3)
#     최소 관측수 규정 없음.
#  A4 "I winsorize beta_CID at 1% and 99% percentiles"
#  A5 "Every month, I sort the stocks into quintile portfolios based on their
#      beta_CID. I update estimates of beta_CID and rebalance portfolios every
#      month." · 전월말 시총가중 · Table 3 vw Q1 0.79%[3.83] → Q5 0.30%[1.40] ·
#      L/S(Q5-Q1) -0.49%[-3.19]
#  A6 방향(사전 선언) "Stocks with negative covariance with CID are riskier, since
#      they tend to fall when the risk of losing high-skill industry-immobile jobs
#      is large" → 低 beta_CID 가 高수익(Q1). 매수 우선순위 = 低민감도.
#  A7 ★Table 5 — 이 엔진의 설계 근거가 되는 논문 자신의 진단:
#      5분위 시장로딩 Q1 **1.07** / Q5 **1.11** (L/S 스프레드 0.04) ·
#      "Controlling for market beta does not have significant effect on the CID
#       premium." → US 에서 beta_CID 정렬은 **시장 중립이 공짜로 성립**한다.
#  A8 표본 1963-2018 · 전년말 주가 >$5 · 시총 >$50M · 비용 명시 없음.
#
# --- [B] 논문 명시값 (승계 인용 — §0 신고) -----------------------------------
#  B1 "Limiting to max depth = 1"
#  B2 "The cost function that is minimized when choosing split points is the sum
#      squared error across all training samples against their sub-region
#      prediction  Min for all split points  Sum_i ( y_i - prediction(y_i) )^2" ·
#     "all input variables and all possible split points are evaluated and chosen
#      in a greedy algorithm. The algorithm maximizes the drop in that value"
#  B3 "a single model capable of predicting simultaneously n stocks is built" ·
#     "correlation information enters the tree structure" → 종목별 표준화 없는
#     다출력 단일 트리. 그래서 **"the dominant stock in a joint regression tree"**
#     가 논문의 세 논점 중 (c) 로 따로 다뤄진다.
#  B4 일간수익 **1,259 daily returns** (US 대형주 5종 · 2015-01-05~2020-04-30).
#     회수 구조: 분기변수는 언제나 mex · 임계값은 꼬리(-350bp~+300bp) ·
#     balance 1-99% ~ 22-78%.
#  B5 포트폴리오·비용·종목수·비중·리밸 = 전무("only done for demonstration
#     purposes and not for statistical inference").
#
# =============================================================================
# 1. 이 재료집합의 기측정 — 무엇이 이미 소진됐고 이 판은 어디를 건드리는가
# =============================================================================
#  (저장소 기록 · 04_Research/strategies/RP_AUTO_COMBO_.../engine.rejected1.R 헤더,
#   fidelity_audit.json, 06_Registry/reinforce_ledger_l1.json)
#   M1 두 엔진 스코어의 rank-Z 평균 — 5회 · 계보 최고 PORT_t 0.766
#   M2 estimand/estimator 치환: [A] 의 선형 기울기를 u 축 계단으로 바꾸고
#      **시장은 응답 쪽 회귀 통제항** — PORT_t 1.209 (단독 최고 1.228 미달)
#   M3 깊이 2 joint 트리: 1단 mex 분기 후 **같은 시장 잎 안에서** u 대비
#      — fidelity_audit verdict "misdeclared"(월 156/252 리밸 · FF49 치환 미신고 ·
#        미신고 상수 6개월 · 코드가 강제하지 않는 성질을 선언)
#   ※ 단독 최고 = [A] 1.228 · [B] 1.11. 합격선 PORT_t 2.95.
#
#  ★M1~M3 은 전부 **estimand 를 고정한 채 추정기/조건화만** 바꿨다. 셋 다 상태변수
#    u 를 [A] 원문 그대로 두고, 시장 오염을 **사후에** 뺐다(평균/회귀통제/잎 조건화).
#    그래서 셋 다 "고-CID 국면" 이 여전히 **반도체 급등月의 집합**이었다 — 잎 분할
#    자체가 시장 국면 분할이었고, 뺀 것은 그 위에 얹힌 계수뿐이다.
#
#  이 판이 건드리는 곳은 **상태 그 자체**다. 아래 §2 (변경 1).
#
# =============================================================================
# 2. 결합 설계 — 무엇을 어떻게 맞물렸나
# =============================================================================
#  ▸ [A] 가 대는 것 = 상태변수(Eq.1 CID · Eq.2 충격) · 정렬 방향(A6) ·
#    단면 1%/99% winsorize(A4) · 월간 리밸(A5) · 그리고 **A7(Table 5)** —
#    이 판의 설계 근거가 되는 논문 자신의 진단.
#  ▸ [B] 가 대는 것 = 추정기. joint(다출력) depth=1 회귀트리 · 전 계열 SSE 합의
#    greedy 최소화 · 모든 분기점 전수 탐색 · 공통 임계값 하나 + 계열별 잎 평균 ·
#    창 1,259 거래일 · 그리고 **B3 의 논점 (c) 'dominant stock'** — 이 판의 두 번째
#    변경 근거.
#
#  ── 변경 1 (핵심) · 상태를 시장직교로 만든다: Eq.2 에 동시점 시장항 한 개 ──
#    d(CID_t) = g0 + g1*d(CID_{t-1}) + g2*CID_{t-1} + **g3*R_MKT,t** + u_perp_t
#    근거는 [A] 자신이다. A7 은 US 에서 beta_CID 5분위의 시장로딩이 1.07/1.11
#    (스프레드 0.04)이고 "Controlling for market beta does not have significant
#    effect on the CID premium" 이라고 보고한다 — 즉 **시장중립성은 [A] 가 전제하고
#    실측한 성질**이다. KR 은 이 성질이 깨진다(사내 실측: cor(u, KOSPI200 월수익)
#    = +0.43 · 2022-26 +0.63 · 최대 u 달 2026-05 시장 +35% / 2025-10 +22% /
#    2026-04 +33% — 분산 급등이 하락이 아니라 반도체 주도 **급등**에서 온다.
#    그래서 L/S 일간 beta -0.39, raw CAGR 0.6% 인데 FF3 8.9%~Carhart4 12.3%).
#    Eq.2 는 원래부터 **CID 에서 정보 없는 변동을 벗겨 내는 자리**다(g1·g2 가 지속
#    성분을 벗긴다). 여기에 동시점 시장항을 한 개 더해 '시장이 움직여서 생긴 분산'
#    을 벗기면, 남는 u_perp 는 **시장 움직임으로 설명되지 않는 산업 발산** = [A] 가
#    말하는 sectoral reallocation 그 자체다. 이것은 계수를 고치는 것이 아니라
#    **어느 달이 고-CID 국면인가를 바꾸는** 변경이다(M2/M3 과 갈리는 지점).
#    ★대가: u_perp 는 [A] 의 Eq.2 그대로가 아니다. 그래서 엔진은 원본 u 도 함께
#      추정해 두 상태의 **꼬리 잎 월집합 Jaccard** 를 매월 계산해 인쇄한다 — 이 값이
#      높으면 변경 1 은 아무 일도 하지 않은 것이고 이 판은 M2 로 붕괴한다(§3 (d)).
#
#  ── 변경 2 · joint SSE 목적함수를 계열별 표준화한다 ([B] 논점 (c) 대응) ──
#    [B] 의 joint 트리는 표준화가 없어 **분산이 가장 큰 종목이 분기를 지배**한다.
#    [B] 의 표본은 분산이 1.39~2.97bp 로 고른 미국 대형주 5종이라 그 지배가 온건한
#    성질로 남지만, KR 유니버스 ~350종은 분산이 자릿수로 벌어지고 **그 최상단이
#    바로 CID 를 만드는 반도체 종목들**이다 — 그러면 임계값이 "그 몇 종목이 크게
#    움직인 달" 로 결정되어 Eq.1 의 구성과 순환한다. 그래서 **임계값 탐색에 한해**
#    각 종목 열을 창내 표준편차로 나눈다. 임계값이 소수 지배 종목의 것이 아니라
#    전 종목 합의가 된다. ★잎 평균 delta 는 **표준화하지 않은 원단위**에서 계산한다
#    — 표준화를 산출에까지 끌면 횡단면 변환이 하나 더 섞이므로, 변경 2 의 효과를
#    임계값 선택에만 가둔다.
#
#  ── 유지 (M2 에서 승계 · 항등식이라 설계 선택이 아니다) ──
#    응답 = 같은 창의 시장모형 잔차 e_i,t = r_i,t - (a_i + b_i*MKT_t).
#    잎 대비의 항등식: {잔차 잎 대비} = {원수익 잎 대비} - b_i*{잎간 MKT 평균차}
#    → beta_i*MKT 기여가 정확히 소거되고, 역베타의 **수준** 성분 a_i 는 두 잎에
#      같은 상수로 들어가 차분에서 사라진다(잎 balance 와 무관하게 성립).
#    u_perp 의 직교성은 선형이고 잎 소속은 비선형이라 얇은 꼬리 잎에서는 실현
#    시장차가 남을 수 있다 — 이 항등식이 그 잔여까지 닫는다. 둘은 대체재가 아니다.
#
#  ── 산출 ──
#    delta_i = mu(hi-u_perp 잎)_i - mu(lo 잎)_i   ([A] beta_CID 의 트리 대응물)
#    → 매월 단면 1%/99% winsorize(A4) → **Score_i = -delta_i** (A6 사전 선언 방향)
#    → 월간 리밸(A5).
#
#  ★쓰지 않은 것: [B] 의 SMB/HML. 인프라의 KR FF3 는 월간뿐이라 일간 패널이 없고,
#    KR 일간 SMB/HML 을 내가 만들면 장부가 정의·절단점·형성주기를 논문 밖에서
#    지어내야 한다. [B] 자신이 mex 만장일치 우세를 보고하므로 제거되는 것은 결과가
#    이미 알려진 경마다. 대가: KR 에서 SMB/HML 이 이겼을 가능성은 미검정이다.
#
# =============================================================================
# 3. 반증 조건 — 엔진이 계산해 FAIL/pass 로 인쇄한다 (선언은 검사 가능해야 한다)
# =============================================================================
#  (a) 시장채널: Score 와 창내 시장베타 b_i 의 월별 스피어만 |rho| 중앙값 > 0.30
#      → 시장채널 차단 주장이 거짓.
#  (b) 꼬리 국면: hi 잎 balance 중앙값이 40~60% 구간 → "[A] 의 위험은 꼬리 국면이고
#      [B] 의 계단이 그것을 찾는다"는 전제가 거짓.
#  (c) 조건부 정보: **원수익** 위에서 u_perp-트리의 SSE 감소가 MKT-트리보다 작으면
#      (drop_u/drop_mkt 중앙값 < 1) CID 는 시장 대비 추가 조건부 정보가 없다.
#      ※ 이 경마는 u 에 불리하게 기울어 있다(u 잎 최소단위 = 1개월 vs MKT 잎 2일).
#  (d) ★변경 1 의 하중: hi 잎 **월집합** Jaccard(u_perp vs 원본 u) 중앙값 >= 0.80
#      → 상태 재정의가 아무 일도 하지 않았고 이 판은 기측정 M2 로 붕괴한다.
#  (e) 리밸 스케줄: [A] A5 는 "예외 없는 매월" 이다. 실현 형성월/후보월 비율과
#      **최장 연속 결번**을 인쇄한다. 결번이 있으면 'monthly' 선언은 그만큼 거짓이다
#      (선행 판 M3 이 252개월 중 156개월만 리밸하고도 'monthly' 로 선언해 misdeclared
#       판정을 받았다 — 그 재발을 막는 자리).
#  셋(a~d) 중 하나라도 성립하면 이 설계는 재료 단독보다 나을 이유가 없다.
#  ★엔진은 balance 하한 외에 "어느 한 달도 잎을 지배하지 못한다" 같은 성질을
#    **강제하지 않는다**. 대신 hi 잎의 최대 단일월 일수 비중을 인쇄한다(선언 대신 관측).
#
# =============================================================================
# 4. PIT (C1~C15) — 구조로 보장한다 (detect_lookahead 통과를 근거로 삼지 않는다)
# =============================================================================
#  ▸ 경계 1 — 모든 창의 종점이 형성일 D(월 T 마지막 거래일) 이하. 창은 항상
#    `(ip - .T_WIN + 1L):ip`, ip = match(D, 수익일자). ip 초과 인덱스·음수 shift·
#    lead·수동 미래 인덱싱 0건.
#  ▸ 경계 2 — 월간 상태변수를 일별로 펼치되 **그 달의 CID 확정일 <= D** 인 달만
#    펼친다(.cid_me <= D). 창 안의 모든 상태값이 D 시점 기지값이고, 보유월 T+1 의
#    상태는 어디에도 쓰이지 않는다. (창 내부에서 u_m 이 월 m 의 앞쪽 날들과 동시점인
#    것은 [A] Eq.3 이 동시점 회귀인 것과 같다 — 추정 대상이 동시점 조건부 구조이고
#    산출은 그 구조의 함수일 뿐 미래 상태를 필요로 하지 않는다.)
#  ▸ 경계 3 — AR(Eq.2·Eq.2') 은 expanding(<=t). 트리 임계값·잎 평균·시장베타·
#    표준편차가 전부 그 형성일의 창 안에서만 계산된다. 형성일 간 상태 이월 0건.
#  C1  rolling/expanding 만. [A] 는 Eq.2 를 전표본 1회 추정하나 그것은 C1 위반이라
#      PIT 가 논문 문자를 이긴다(burn-in 60개월). 전 표본 통계 0건.
#  C2  same-day 순환참조 없음. D 종가까지 쓰고 집행은 익 거래일(하네스).
#  C3  같은 기간 집계->적용 없음. 신호창 종점(D) < 보유월(T+1) 시작.
#  C4  재무 패널 미사용.               C5  오버레이 없음(S0/S1 금지 준수).
#  C6  유니버스 = 각 D 의 K200/KQ150 멤버십(PIT 시변). 최종 명부 주입 없음.
#      창 커버리지 요건은 **과거** 데이터 요건이라 생존편의를 만들지 않는다.
#  C7  shift(-N)·lead() 0건. shift 는 전부 +1(과거 방향).
#  C8  FM weight 미사용.               C9  DD/VT 미사용.
#  C10 유동성 = D **직전 20 거래일** 평균 거래대금. `lo:(ip - 1L)` 로 당일 배제.
#  C11 외부 매크로 미사용. 시장 계열은 [A] Eq.1 이 직접 만드는 R_MKT(전 상장 VW,
#      월간)와 벤치마크 일간수익만 — 외부 캐시(FRED·rf parquet) 의존 0.
#  C13 Factor DB 미소비 → 부호 정렬 대상 없음. 수동 부호 반전 0건 —
#      Score = -delta 는 A6 가 **사전 선언한** 방향이다.
#  C14 IC 접근 없음.                    C15 Factor DB parquet 직접 load 0건.
#  ★rawdata 의 Market 열 미사용(KOSDAQ 0건 날조 — 사내 기록). 시장 구분은
#    K200/KQ150 멤버십 플래그로만 한다.
#
# =============================================================================
# 5. 산출
# =============================================================================
#   FACTORS(Date, Ticker, Score) — Score = -delta_w (클수록 롱 = [A] 의 Q1 다리)
#   러너 권장 호출([A] A5 명시값 그대로):
#     portfolio_spec = list(construction = "quantile_long_short", weighting = "vw",
#                           long_frac = 0.20, short_frac = 0.20,
#                           rebalance = "monthly", n_max = 1000L)
#     commission_paper = NULL (양 논문 비용 무명시 → gross 병기, 등급은 15bps 판)
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
# 6. 상수 — 전부 출처를 적는다. 성과를 보고 고른 값이 하나도 없다.
#    ★이 블록의 모든 항목이 FIDELITY.changed 의 보충값 목록과 1:1 대응한다
#      (선행 판 M3 은 `.LEAF_MO_L <- 6L` 을 이 목록에서 빠뜨려 misdeclared 판정).
# =============================================================================
# ▸ [A] 에서 온 것
.CID_MIN_FIRMS <- 10L        # A1  "at least 10 firms"
.WINS_LO       <- 0.01       # A4  단면 winsorize 하단
.WINS_HI       <- 0.99       # A4  단면 winsorize 상단
.A_STATE_MIN   <- 24L        # A3  "two years of monthly" — 여기서는 창이 담아야 할
                             #     **상태 draw 최소 개수**로만 쓴다(창 길이 아님)
# ▸ [B] 에서 온 것
.T_WIN         <- 1259L      # B4  1,259 daily returns
.MIN_LEAF      <- 2L         # B2/B3 잎 평균이 성립하는 종목별 관측 하한
.MIN_STK       <- 5L         # B4  joint 트리가 성립하는 계열 수(논문 표본 n = 5)
# ▸ 고정 축(도훈)
.LIQ           <- 2e8        # adv20(t-1) 하한 (KRW)
.LIQ_WIN       <- 20L        # 거래일 (D 직전 20 거래일 · 종점 = D-1)
.START         <- as.Date("2005-01-01")
# ▸ 타당성 하한 (전략 파라미터 아님)
.MIN_COV       <- 0.80       # 창 커버리지 = 5년 중 4년. 거래정지 며칠로 전 이력이
                             #   버려지는 것을 막는 자리.
.MIN_EPI       <- 2L         # 잎당 **서로 다른 달** 최소 개수. 잎 평균이 단일 에피
                             #   소드가 되지 않는 산술 하한. ★이 하한은 지배월의
                             #   비중을 **제한하지 않는다** — 잎 평균은 일수 가중이다.
                             #   그래서 지배월 비중을 강제 대신 **인쇄**한다(§3).
                             #   [B] 가 1-99% 분할을 보고하므로 balance 강제 금지.
.CID_AR_BURNIN <- 60L        # Eq.2 expanding 최소 관측([A] 는 전표본 1회 — PIT 보정)
.RET_CAP       <- 1.0        # |일간수익| > 100% = 데이터 아티팩트. KRX 가격제한폭이
                             #   ±30% 라 한 세션에 물리적으로 불가능(수정주가 실패
                             #   지문). 윈저라이즈가 아니라 결측 처리.
.SD_FLOOR      <- 1e-8       # 변경 2 표준화의 0-나눗셈 방어(수치 하한)

.tru <- function(x) !is.na(x) & (x != 0)      # 논리/0-1 혼재 방어
.t0  <- Sys.time()

if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]

# =============================================================================
# 7. 벤치마크 일간수익 + 거래일 격자 (유령 거래일 배제)
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
# 8. [A] Eq.1 — CID (산업 VW 월간수익의 시장 대비 평균절대편차)
#    ★CID 는 거시 상태변수라 [A] 대로 **시장 전체**(전 상장종목)에서 만든다.
#      유니버스 치환(K200∪KQ150)은 정렬 대상(test asset)에만 걸린다.
#    ★산업 분류 = 사내 Sector_Lv2(48군). [A] 의 FF49 는 KR 에 존재하지 않는다 —
#      이것은 **changed 항목**이고 FIDELITY 에 그렇게 적혀 있다(kept 아님).
#      분류 해상도는 Eq.1 의 N 과 ">=10사" 필터의 구속력을 동시에 바꾼다.
# =============================================================================
DD <- RAWDATA[, .(Date, Ticker, Ret, Size, Sector_Lv2)]
DD[, rr := Ret]
DD[!is.finite(rr) | abs(rr) > .RET_CAP, rr := NA_real_]
DD[, ymi := year(Date) * 12L + month(Date)]

.CME <- DD[, .(cid_me = max(Date)), by = ymi]      # 그 달 CID 가 확정되는 날짜
setkey(.CME, ymi)

MON <- DD[, .(mret = if (sum(is.finite(rr)) >= 1L) prod(1 + rr[is.finite(rr)]) - 1 else NA_real_),
          by = .(Ticker, ymi)]
# 각 cid_me 는 자기 달 안에만 있으므로 `Date %in% cid_me` = '그 달의 월말 행'
EOM <- DD[Date %in% .CME$cid_me, .(Ticker, ymi, size_end = Size, ind = Sector_Lv2)]
EOM <- unique(EOM, by = c("Ticker", "ymi"))
MON <- merge(MON, EOM, by = c("Ticker", "ymi"))

setorder(MON, Ticker, ymi)                          # A1 가중치 = 전월말 시총
MON[, `:=`(size_prev = shift(size_end, 1L), ymi_prev = shift(ymi, 1L)), by = Ticker]
MON[!is.finite(ymi_prev) | ymi_prev != ymi - 1L, size_prev := NA_real_]

VAL <- MON[is.finite(mret) & is.finite(size_prev) & size_prev > 0 & !is.na(ind)]
IP  <- VAL[, .(nf = .N, r_ind = sum(mret * size_prev) / sum(size_prev)),
           by = .(ymi, ind)][nf >= .CID_MIN_FIRMS]
MKTM <- MON[is.finite(mret) & is.finite(size_prev) & size_prev > 0,
            .(r_mkt = sum(mret * size_prev) / sum(size_prev)), by = ymi]   # A1 vwretd 대응
CIDT <- merge(IP, MKTM, by = "ymi")[, .(CID = mean(abs(r_ind - r_mkt)), n_ind = .N), by = ymi]
CIDT <- merge(CIDT, MKTM, by = "ymi")               # Eq.2' 의 시장항
setorder(CIDT, ymi)
rm(DD, VAL, IP, EOM); gc(verbose = FALSE)

# =============================================================================
# 9. [A] Eq.2 (원본) 과 Eq.2' (변경 1 · 시장직교) 를 **둘 다** expanding 으로
#    원본 u 는 산출에 쓰이지 않는다 — §3 (d) 반증 계기의 대조군으로만 쓴다.
# =============================================================================
CIDT[, dC := CID - shift(CID, 1L)]
CIDT[, `:=`(dC_l1 = shift(dC, 1L), C_l1 = shift(CID, 1L))]
CIDT[, `:=`(u = NA_real_, u_raw = NA_real_)]
.fit_rows <- which(is.finite(CIDT$dC) & is.finite(CIDT$dC_l1) &
                   is.finite(CIDT$C_l1) & is.finite(CIDT$r_mkt))
if (length(.fit_rows) < .CID_AR_BURNIN)
  stop("[COMBO_2007_2301] CID 월 수가 AR burn-in 에 못 미침")
for (kk in seq.int(.CID_AR_BURNIN, length(.fit_rows))) {
  sub <- CIDT[.fit_rows[seq_len(kk)]]                        # <= t 만 (expanding)
  f1  <- stats::lm(dC ~ dC_l1 + C_l1 + r_mkt, data = sub)    # Eq.2' (변경 1)
  f0  <- stats::lm(dC ~ dC_l1 + C_l1,         data = sub)    # Eq.2  (원본 · 대조군)
  r1  <- stats::residuals(f1); r0 <- stats::residuals(f0)
  set(CIDT, i = .fit_rows[kk], j = "u",     value = as.numeric(r1[length(r1)]))
  set(CIDT, i = .fit_rows[kk], j = "u_raw", value = as.numeric(r0[length(r0)]))
}
.uv1 <- as.numeric(CIDT[["u"]]); .uv0 <- as.numeric(CIDT[["u_raw"]])
.mkm <- as.numeric(CIDT[["r_mkt"]])
.ok2 <- is.finite(.uv1) & is.finite(.uv0) & is.finite(.mkm)
cat(sprintf(paste0(
  "[COMBO_2007_2301] [A]Eq.1 · CID 월 %d (충격 유효 %d) · 산업수 중앙 %.0f · CID 1-lag 자기상관 %.3f (논문 US -0.05)\n",
  "[COMBO_2007_2301] 변경 1 검사 · cor(u_raw, R_MKT) = %+.3f  ->  cor(u_perp, R_MKT) = %+.3f  (US A7: 시장중립이 공짜)\n"),
  nrow(CIDT), sum(.ok2), stats::median(CIDT$n_ind, na.rm = TRUE),
  stats::cor(CIDT$CID[-1], CIDT$CID[-nrow(CIDT)], use = "complete.obs"),
  stats::cor(.uv0[.ok2], .mkm[.ok2]), stats::cor(.uv1[.ok2], .mkm[.ok2])))

UM <- merge(CIDT[is.finite(u) & is.finite(u_raw), .(ymi, u, u_raw)], .CME, by = "ymi")
setkey(UM, ymi)

# =============================================================================
# 10. 형성일(격자 월말) · 유동성 창(종점 = D-1)
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
# 11. 일간 수익 wide 행렬 (test asset 후보 = K200∪KQ150 이력 보유 종목)
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

.MXD <- .GD[Date %in% .rdt, .(Date, MKT, ymi)]
setkey(.MXD, Date)
.mktv <- .MXD[.(.rdt), MKT]
.ymiv <- .MXD[.(.rdt), ymi]
if (anyNA(.mktv) || anyNA(.ymiv))
  stop("[COMBO_2007_2301] 시장계열/월인덱스 정렬 실패 — 격자 불일치")

# 일별 상태값(월간 → 그 달의 거래일) + 그 값이 확정된 날짜
.uday   <- UM[.(.ymiv), u]
.uday0  <- UM[.(.ymiv), u_raw]
.uconf  <- UM[.(.ymiv), cid_me]

# =============================================================================
# 12. 유동성·멤버십 자격 (D 단면)
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
# 13. [B] joint depth=1 트리 — 다출력 · greedy SSE · 공통 임계값
#     SSE(k) = sum_j [ TSS_j - CX_j(k)^2/CM_j(k) - (SX_j-CX_j(k))^2/(SM_j-CM_j(k)) ]
#     TSS_j 는 k 에 무관 → SSE 최소화 = gain 최대화. drop = SSE 감소량(B2).
#     min_dv = 잎당 서로 다른 분기변수 값(월간 상태변수면 '달') 최소 개수.
#     ★분할 선택은 이 함수가, 잎 평균은 .leaf_means() 가 한다 — 변경 2(표준화)를
#       임계값 선택에만 가두기 위해 두 단계를 분리했다.
# =============================================================================
.tree_split <- function(Ymat, sv, min_dv) {
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

  dv  <- cumsum(c(TRUE, ss[-1L] != ss[-n]))     # 정렬 위치별 '서로 다른 값' 순번
  ndv <- dv[n]
  ok  <- c(ss[-n] < ss[-1L], FALSE) & (dv >= min_dv) & ((ndv - dv) >= min_dv)
  if (!any(ok)) return(NULL)
  gn[!ok] <- -Inf
  k <- which.max(gn)
  if (!is.finite(gn[k])) return(NULL)

  list(k = k, ord = o, cstar = (ss[k] + ss[k + 1L]) / 2,
       n_lo = k, n_hi = n - k, dv_lo = dv[k], dv_hi = ndv - dv[k], n_dv = ndv,
       drop = gn[k] - sum(bv))
}

# 같은 분할(ord, k) 위에서 **원단위** 잎 평균을 낸다.
.leaf_means <- function(Ymat, ord, k) {
  Ys <- Ymat[ord, , drop = FALSE]
  n  <- nrow(Ys)
  Lo <- Ys[seq_len(k), , drop = FALSE]
  Hi <- Ys[(k + 1L):n, , drop = FALSE]
  nl <- colSums(!is.na(Lo)); nh <- colSums(!is.na(Hi))
  list(mu_lo = colSums(Lo, na.rm = TRUE) / nl, mu_hi = colSums(Hi, na.rm = TRUE) / nh,
       nb_lo = nl, nb_hi = nh)
}

# =============================================================================
# 14. 형성일 루프
# =============================================================================
.OUT  <- vector("list", length(.FORM))
.LOG  <- vector("list", length(.FORM))
.skip <- 0L
.cand_month <- 0L        # 창 요건을 만족한 '후보' 형성월 (§3 (e) 분모)

for (kk in seq_along(.FORM)) {
  D  <- .FORM[kk]
  ip <- match(D, .rdt)
  if (is.na(ip) || ip < .T_WIN) { .skip <- .skip + 1L; next }

  wi <- (ip - .T_WIN + 1L):ip                     # 종점 = D. ip 초과 인덱스 없음.
  cw <- .uconf[wi]
  # ★경계 2: 그 달의 CID 가 D 이후에야 확정되는 날은 창에서 제거한다.
  vr <- which(is.finite(.uday[wi]) & is.finite(.uday0[wi]) & !is.na(cw) & cw <= D)
  if (length(vr) < as.integer(.MIN_COV * .T_WIN)) { .skip <- .skip + 1L; next }
  wi <- wi[vr]
  uw <- .uday[wi]; u0w <- .uday0[wi]; mw <- .mktv[wi]; ymw <- .ymiv[wi]
  n  <- length(wi)
  if (length(unique(uw)) < .A_STATE_MIN) { .skip <- .skip + 1L; next }
  .cand_month <- .cand_month + 1L

  cand <- .ELG[.(D), Ticker, nomatch = 0L]
  cand <- intersect(cand, .tick)
  if (length(cand) < .MIN_STK) { .skip <- .skip + 1L; next }

  Y  <- RET[wi, cand, drop = FALSE]
  Mk <- !is.na(Y)
  # 커버리지 + **D 당일 거래**(창 말행이 아니라 ip 행 — 월 T 가 창에서 빠져도 자격은 D 기준)
  kp <- (colSums(Mk) >= as.integer(.MIN_COV * n)) & !is.na(RET[ip, cand])
  if (sum(kp) < .MIN_STK) { .skip <- .skip + 1L; next }
  Y  <- Y[, kp, drop = FALSE]; Mk <- Mk[, kp, drop = FALSE]
  nm <- colnames(Y); p <- ncol(Y)

  # ---- 시장모형 잔차 (창 내 OLS · 종목별 결측 패턴은 마스크 합으로) ----
  M1  <- Mk * 1.0
  Y0  <- Y; Y0[!Mk] <- 0
  nj  <- colSums(M1)
  Sy  <- colSums(Y0)
  Sm  <- as.numeric(crossprod(mw, M1))
  Smm <- as.numeric(crossprod(mw * mw, M1))
  Smy <- as.numeric(crossprod(mw, Y0))
  den <- nj * Smm - Sm * Sm
  okb <- is.finite(den) & den > 0
  bj  <- rep(NA_real_, p)
  bj[okb] <- ((nj * Smy - Sm * Sy) / den)[okb]
  aj  <- (Sy - bj * Sm) / nj
  gb  <- is.finite(aj) & is.finite(bj)
  if (sum(gb) < .MIN_STK) { .skip <- .skip + 1L; next }
  Y <- Y[, gb, drop = FALSE]; nm <- nm[gb]; bj <- bj[gb]; aj <- aj[gb]
  E <- Y - (matrix(aj, n, length(aj), byrow = TRUE) + outer(mw, bj))

  # ---- 변경 2: 임계값 탐색만 계열별 표준화 ([B] 논점 (c)) ----
  sdv <- colSds(E, na.rm = TRUE)
  sdv[!is.finite(sdv) | sdv < .SD_FLOOR] <- NA_real_
  gs  <- is.finite(sdv)
  if (sum(gs) < .MIN_STK) { .skip <- .skip + 1L; next }
  Z <- E[, gs, drop = FALSE] * matrix(1 / sdv[gs], n, sum(gs), byrow = TRUE)

  # ---- 분할(표준화 위) → 잎 평균(원단위 위) ----
  tr <- .tree_split(Z, uw, .MIN_EPI)
  if (is.null(tr)) { .skip <- .skip + 1L; next }
  lm1 <- .leaf_means(E, tr$ord, tr$k)
  dl  <- lm1$mu_hi - lm1$mu_lo
  # gs: 잔차 분산이 0 인 퇴화 종목은 임계값 탐색에서도 산출에서도 제외한다.
  gd  <- is.finite(dl) & gs & lm1$nb_lo >= .MIN_LEAF & lm1$nb_hi >= .MIN_LEAF
  if (sum(gd) < .MIN_STK) { .skip <- .skip + 1L; next }

  .OUT[[kk]] <- data.table(Date = D, Ticker = nm[gd], delta = as.numeric(dl[gd]),
                           mbeta = as.numeric(bj[gd]))

  # ---- 계기 ----
  # (d) 상태 재정의가 꼬리 잎의 **월집합**을 실제로 바꿨나 (대조군 = 원본 u)
  tr0 <- .tree_split(Z, u0w, .MIN_EPI)
  hi1 <- unique(ymw[uw >  tr$cstar])
  jac <- NA_real_
  if (!is.null(tr0)) {
    hi0 <- unique(ymw[u0w > tr0$cstar])
    uni <- length(union(hi1, hi0))
    if (uni > 0L) jac <- length(intersect(hi1, hi0)) / uni
  }
  # (c) 원수익 위 경마 ([B] 의 실험 — u_perp 를 입력집합에 추가한 것)
  tu <- .tree_split(Y, uw, .MIN_EPI)
  tm <- .tree_split(Y, mw, .MIN_LEAF)
  # 잎간 시장 평균차 + hi 잎 지배월 비중 (강제 대신 관측)
  ms  <- mw[tr$ord]; yms <- ymw[tr$ord]
  hidx <- (tr$k + 1L):n
  domsh <- max(tabulate(match(yms[hidx], unique(yms[hidx])))) / length(hidx)

  .LOG[[kk]] <- data.table(
    Date = D, n_stock = sum(gd), n_day = n, n_month = tr$n_dv,
    bal_hi = 100 * tr$n_hi / n, mo_hi = tr$dv_hi, dom_share = 100 * domsh,
    mkt_gap_bp = 1e4 * (mean(ms[hidx]) - mean(ms[seq_len(tr$k)])),
    jaccard = jac,
    drop_u = if (is.null(tu)) NA_real_ else tu$drop,
    drop_m = if (is.null(tm)) NA_real_ else tm$drop,
    m_split_bp = if (is.null(tm)) NA_real_ else 1e4 * tm$cstar)
  rm(Y, Y0, Mk, M1, E, Z, tr, tr0, tu, tm, lm1)
}

RAW <- rbindlist(Filter(Negate(is.null), .OUT), use.names = TRUE)
if (!nrow(RAW)) stop("[COMBO_2007_2301] 스코어 0행 — 창 길이/유니버스/커버리지 확인")

# =============================================================================
# 15. [A] A4 단면 winsorize(1%/99%) + A6 방향 → FACTORS
#     ★임계값 c* 가 전 종목 공통(joint)이라 delta 에 공통 스칼라를 곱해
#       '단위 u 당 기울기' 로 바꿔도 단면 순위는 불변이다 — 정렬은 재척도에 무관.
# =============================================================================
RAW[, delta_w := {
  qq <- stats::quantile(delta, c(.WINS_LO, .WINS_HI), na.rm = TRUE, names = FALSE)
  pmin(pmax(delta, qq[1]), qq[2])
}, by = Date]

# A6: CID 민감도 高 = 기대수익 低 → 매수 우선순위 = 低민감도(논문의 Q1 다리).
FACTORS <- RAW[is.finite(delta_w), .(Date, Ticker, Score = -delta_w)]
setorder(FACTORS, Date, -Score)

# =============================================================================
# 16. 반증 계기 인쇄 (§3)
# =============================================================================
LOGDT <- rbindlist(Filter(Negate(is.null), .LOG), use.names = TRUE)

.med <- function(v) { v <- as.numeric(v); v <- v[is.finite(v)]
                      if (length(v)) stats::median(v) else NA_real_ }
.mk  <- function(f) if (isTRUE(f)) "FAIL" else "pass"

# (a) Score vs 창내 시장베타 — 월별 스피어만
.RC <- RAW[is.finite(delta_w) & is.finite(mbeta),
           .(rho = { xv <- as.numeric(-delta_w); yv <- as.numeric(mbeta)
                     if (length(xv) >= 5L) as.numeric(stats::cor(xv, yv, method = "spearman"))
                     else NA_real_ }), by = Date]
.a_med  <- .med(abs(as.numeric(.RC[["rho"]])))
.a_fail <- is.finite(.a_med) && .a_med > 0.30
# (b) 잎 balance
.b_med  <- .med(LOGDT[["bal_hi"]])
.b_fail <- is.finite(.b_med) && .b_med >= 40 && .b_med <= 60
# (c) 원수익 경마
.c_med  <- .med(as.numeric(LOGDT[["drop_u"]]) / as.numeric(LOGDT[["drop_m"]]))
.c_fail <- is.finite(.c_med) && .c_med < 1
# (d) 상태 재정의의 하중 — 꼬리 잎 월집합 Jaccard
.d_med  <- .med(LOGDT[["jaccard"]])
.d_fail <- is.finite(.d_med) && .d_med >= 0.80
# (e) 리밸 스케줄 — 실현 형성월 / 후보월 + 최장 연속 결번
.fm  <- sort(unique(year(LOGDT$Date) * 12L + month(LOGDT$Date)))
.gap <- if (length(.fm) > 1L) { d <- diff(.fm); if (any(d > 1L)) max(d) - 1L else 0L } else 0L
.e_fail <- .gap > 0L || (.cand_month > 0L && nrow(LOGDT) < .cand_month)

LOGDT[, yr := year(Date)]
.byyr <- LOGDT[, .(n_m = .N, n_stk = as.integer(stats::median(n_stock)),
                   n_mo = as.integer(stats::median(n_month)),
                   bal  = round(stats::median(bal_hi), 1),
                   dom  = round(stats::median(dom_share), 1),
                   gap  = round(stats::median(mkt_gap_bp), 1),
                   jac  = round(stats::median(jaccard, na.rm = TRUE), 3),
                   rat  = round(stats::median(drop_u / drop_m, na.rm = TRUE), 3)), by = yr]
setorder(.byyr, yr)
cat("[COMBO_2007_2301] 연도별 회수 구조 (분기변수 = u_perp · 응답 = 시장모형 잔차 · 임계값 탐색만 표준화):\n")
cat("    연도 | 월  종목  창월수  hi잎%  hi잎지배월%  잎간MKT차  Jaccard(vs 원본u)  drop_u/drop_mkt\n")
for (r in seq_len(nrow(.byyr)))
  cat(sprintf("    %d | %2d  %4d   %3d   %5.1f%%    %5.1f%%    %7.1fbp        %6.3f          %6.3f\n",
              .byyr$yr[r], .byyr$n_m[r], .byyr$n_stk[r], .byyr$n_mo[r], .byyr$bal[r],
              .byyr$dom[r], .byyr$gap[r], .byyr$jac[r], .byyr$rat[r]))

.nmn <- FACTORS[, .N, by = Date]
cat(sprintf(paste0(
  "[COMBO_2007_2301] combination = [A]2301.09173 상태변수 x [B]2007.08115 추정기 (변경 1 = 상태 시장직교 · 변경 2 = 임계값 탐색 표준화)\n",
  "  형성 %d개월 / 후보 %d개월(skip %d) · %s ~ %s · FACTORS %s행 · 월 종목 중앙 %d (min %d / max %d) · 창 %d거래일\n",
  "  ── 반증 조건 (§3 · a~d 중 하나라도 FAIL 이면 설계 근거 소멸) ──\n",
  "  (a) |rho(Score, 창내 시장베타)| 중앙 %.3f      (>0.30 이면 시장채널 차단 실패)      -> %s\n",
  "  (b) hi 잎 balance 중앙 %.1f%% (hi 잎 달 수 중앙 %d / 창 %d달)  (40~60%%면 꼬리 전제 실패) -> %s\n",
  "  (c) 원수익 SSE감소 비 drop_u/drop_mkt 중앙 %.3f  (<1 이면 시장 대비 조건부 정보 없음)  -> %s\n",
  "  (d) 꼬리 잎 월집합 Jaccard(u_perp vs 원본 u) 중앙 %.3f  (>=0.80 이면 변경 1 무하중 = M2 붕괴) -> %s\n",
  "  (e) 리밸 스케줄: 형성 %d / 후보 %d 개월 · 최장 연속 결번 %d개월  ([A] A5 = 예외 없는 매월) -> %s\n",
  "  ── 참고(강제하지 않고 관측만) ── hi 잎 지배월 일수비중 중앙 %.1f%% · 잎간 MKT 평균차 중앙 %.1fbp · MKT-트리 임계값 중앙 %.1fbp\n",
  "  ※ (c) 는 u 에 불리하게 기울어 있다: u 잎 최소단위 = 1개월(약 21일) vs MKT 잎 최소 2일\n",
  "  ★러너 권장: portfolio_spec = list(construction=\"quantile_long_short\", weighting=\"vw\",\n",
  "               long_frac=0.20, short_frac=0.20, rebalance=\"monthly\", n_max=1000L)  ([A] A5 명시값)\n",
  "               commission_paper = NULL (양 논문 비용 무명시) · %.1f분\n"),
  nrow(LOGDT), .cand_month, .skip,
  as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date)),
  format(nrow(FACTORS), big.mark = ","),
  as.integer(stats::median(.nmn$N)), min(.nmn$N), max(.nmn$N), .T_WIN,
  .a_med, .mk(.a_fail),
  .b_med, as.integer(.med(LOGDT[["mo_hi"]])), as.integer(.med(LOGDT[["n_month"]])), .mk(.b_fail),
  .c_med, .mk(.c_fail),
  .d_med, .mk(.d_fail),
  nrow(LOGDT), .cand_month, .gap, .mk(.e_fail),
  .med(LOGDT[["dom_share"]]), .med(LOGDT[["mkt_gap_bp"]]), .med(LOGDT[["m_split_bp"]]),
  as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
