# =============================================================================
# engine.R — RP_AUTO_COMBO_combo_1403_8125_2007_081   (4판 · 2026-09-13 · 재료 5편 중 [A]·[B] 두 편을 쓴다)
#
#   [A] Choi · Choi · Kang, "Maximum drawdown, recovery, and momentum" (arXiv:1403.8125)
#       https://arxiv.org/abs/1403.8125   전문 = arxiv.org/html/1403.8125v1  (본 세션 직접 판독)
#       → **순위**를 정한다: Score = CM = C − MDD (Table 1 (1,2,1) · 6개월 일별 로그가격 경로 · 월간 최우수 규칙)
#   [B] Polimenis, "Uncovering a factor-based expected return conditioning structure with Regression Trees
#       jointly for many stocks" (arXiv:2007.08115)   https://arxiv.org/abs/2007.08115
#       전문 = r.jina.ai/https://arxiv.org/pdf/2007.08115 (본 세션 직접 판독 2회 · html 판 없음)
#       → **자격**을 정한다: 전 종목 공동(joint) depth=1 회귀트리가 1,259 거래일 창에서 시장초과수익(mex)에
#         고른 공통 임계값 c* 의 **왼쪽 잎(시장 급락일)** 위에서, 종목의 시장 대비 초과수익 평균이 0 이상인
#         종목만 발행한다. 잎 평균은 스코어에 들어가지 않는다 — 문턱(자격)이다.
#   [H] Borri · Chetverikov · Liu · Tsyvinski, "One Factor to Bind the Cross-Section of Returns" (arXiv:2404.08129)
#       — **이 판에 코드가 없다.** 모형·§2 3단계 추정·예측수익·§5.7 5분위 어느 것도 구현하지 않는다 (FIDELITY changed ③ (1))
#   [C] Pinchuk, "Labor Income Risk and the Cross-Section of Expected Returns" (arXiv:2301.09173) — 미사용 (③ (2))
#   [D] André · Coqueret, "Dirichlet policies for reinforced factor portfolios" (arXiv:2011.05381) — 미사용 (③ (3))
#
# ★fidelity = COMBINATION. 선언 정본 = FIDELITY.json (이 주석은 사본이지 통로가 아니다)
#
# =============================================================================
# 한 문장 요약 — 무엇이 맞물리는가
# =============================================================================
#   [A] 의 CM 은 종목 **자기 경로**의 6개월 낙폭을 뺀다. 그런데 이 저장소의 실측에서 CM 계열 롱온리 25종은
#   깊은 위기에서 벤치보다 더 깨진다(1판 GFC −47% · 3판 −42% vs KOSPI200 −36% · 2022 −36% vs −26% · MDD 57~61%).
#   기전: 형성창 6개월이 조용하면 CM 은 종목의 **시장 급락일 민감도**를 볼 수 없다(낙폭이 아직 없다) —
#   그래서 위기 직전의 CM 승자는 고β 승자다. [B] 는 그 민감도를 재는 장치를 준다: 5년 창 위의 공동 트리가
#   "시장 급락일" 집합을 데이터에서 고르고(임계값은 꼬리에 선다 — [B] Table 2c · joint −70bp), 각 종목의
#   그 날들 위 조건부 기대수익(왼쪽 잎 평균 — "On the left branch, IBM returns are expected to have ER = −180bp
#   versus ER = 30bp for the right")이 나온다. 이 판은 그 왼쪽 잎 위에서 시장을 밑돌지 않은 종목만 [A] 로 줄 세운다.
#
#       발행 대상  = { i : e_L,i ≥ 0 },  e_L,i = mean_{d ∈ L, i 관측} ( r_i,d − r_m,d ),  L = { d : mex_d < c* }
#       Score_i    = CM_i = 1·R_I + 2·R_II + 1·R_III  (6개월 일별 로그가격 경로 · [A] Table 1 CM)
#
#   1판([A]+[B] · Score = CM + R_II^sys · C 0.691)과의 차이: 1판은 [B] 를 **6개월 창 안의 급락일 라벨**로만 써서
#   창이 조용하면 신호가 0 이었고(GFC 직전이 정확히 그 경우), 잎 평균(종목의 꼬리 민감도)은 쓰지 않았다.
#   이 판은 잎 평균을 **5년 창**에서 재고 그것을 스코어에 더하지 않고 **자격**으로 쓴다 — 스코어 층 평균·가중 0.
#
# =============================================================================
# §1. [A] 원문 대조  (arxiv.org/html/1403.8125v1 · 따옴표 안 = 축자)
# =============================================================================
#  (A1) "MDD=maxτ∈(0,T)(maxt∈(0,τ)(P(t)−P(τ)))" · "R=R(t∗,T) where t∗ is the moment for the end of the maximum
#       drawdown formation." · "C=RI+RII+RIII=PP−MDD+R where PP is the log-return during the pre-peak period."
#  (A2) "Taking weighted average with more weights on certain specific period is one way of construction." ·
#       Table 1: C(1,1,1) · M(0,1,0) · R(0,0,1) · RM(0,1,1) · **CM(1,2,1) 'Cumulative return-MDD'** · CR(1,1,2) · CMR(1,2,2)
#       ★단일 규칙 순위라 가중합/가중평균은 상수배(1/4) — 순위 불변(3판 감사가 지적한 척도 문제는 두 규칙을 뺄셈으로
#         결합할 때 생겼다. 이 판은 규칙 하나만 쓰므로 그 문제가 없다).
#  (A3) "Based on given selection rules during 6 months (weeks) of estimation period, assets in market universes are
#       sorted in ascending order." · "In the cases of the S&P 500 and KOSPI 200 universes, numbers of groups are 10" ·
#       "After 6 months (weeks) of the holding period, each basket is liquidated. The portfolio is constructed at the
#       beginning of every month, i.e. it is the overlapping portfolio."
#  (A4) Table 3 (monthly 6/6 momentum, KOSPI 200) 승자/패자/W−L 월평균(σ): C 1.6292(8.7334)/0.2987/1.3305(6.8258) ·
#       M 1.3075(5.5705)/0.2841/1.0234 · R 1.3299/0.9559/0.3740 · RM 1.5416/0.2613/1.2803 ·
#       **CM 1.7005(8.0623)/0.2676(9.1117)/1.4330(7.0357)** · CR 1.5449/0.4421/1.1028 · CMR 1.5557/0.2451/1.3106
#  (A5) 결론: "In monthly scale, the maximum drawdown associated strategies outperform the traditional momentum
#       strategy, i.e. smaller maximum drawdown gives stronger momentum." · §4 "The portfolios are less riskier in
#       every risk measures than the other portfolios by alternative ranking rules including the cumulative return."
#  (A6) 원문이 침묵하는 것: 형성창 내부 표본주기 · 동값 · 거래비용(자기 분석 미적용) · 유동성 필터.
#
# =============================================================================
# §2. [B] 원문 대조  (r.jina.ai/https://arxiv.org/pdf/2007.08115 · 본 세션 직접 판독 2회 · 따옴표 안 = 축자)
# =============================================================================
#  (B1) 트리: "Limiting to max depth = 1" · 비용함수 "Σi(y i – prediction(y i)) 2" (sum squared error) ·
#       "all input variables and all possible split points are evaluated and chosen in a greedy algorithm."
#  (B2) 공동 적합: "a single model capable of predicting simultaneously n stocks is built" ·
#       "correlation information enters the tree structure" → 다출력 단일 트리 · 분기점 하나를 전 종목 SSE 합으로.
#       종목별 표준화 없음 — "the dominant stock in a joint regression tree" 는 설계의 성질(제거 대상 아님).
#  (B3) 자료: "5 years of daily stock return data for 5 major US companies ... 1/5/2015 to 30/4/2020 ...
#       The sample comprises 1259 daily returns." · 설명변수 = FF3 (mex · SMB · HML).
#  (B4) 결과: "in all cases (solo and joint) the most informative factor is the market excess return factor"
#  (B5) 잎의 뜻(시장 조건): "On the left branch, IBM returns are expected to have ER = -180bp versus ER=30bp for the
#       right." · KO −490bp vs 10bp · BK −260bp vs 30bp · GOOG −140bp vs 50bp · PG 0 vs 500bp(solo 우측 분기).
#       Table 2c joint 분기: KO −70bp(13.66–86.34%) · BK −90bp(10.5–89.5%) · PG −70bp · GOOG −70bp — 임계값은
#       0 이 아니라 **왼쪽 꼬리**에 서고 잎은 극단 불균형이다.
#  (B6) "only done for demonstration purposes and not for statistical inference" · 포트폴리오·비용·종목수·리밸 전무.
#
# =============================================================================
# §3. 결합 연산자 — 무엇을 어떻게 붙였나 (평균이 아니다 · 두 엔진 신호의 rank-Z 0건 · 스코어 층 가중 0건)
# =============================================================================
#   형성일 f = 매월 마지막 거래일(격자 = RAWDATA 거래일 ∩ 시장계열 거래일). 집행 = 익 거래일(러너).
#   ▸ [B] 창 W_B = f 로 끝나는 1,259 거래일(B3). mex_d = 시장 일간수익 − rf_d(전월 CD91 · 전월 거래일수로 일할).
#     적격 종목(f 의 K200∪KQ150 멤버십 ∧ adv20(t−1) ≥ 2e8) 중 창 커버리지 ≥ 80% ∧ f 관측 종목의 일간수익을
#     목적변수로 공동 depth=1 트리를 mex 에 greedy SSE 로 적합 → c* (B1·B2·B4). 왼쪽 잎 L = { d ∈ W_B : mex_d < c* }.
#   ▸ 자격: 적격 종목 i 마다 e_L,i = L 위에서 i 가 관측된 날들의 (r_i,d − r_m,d) 평균 (r_m = 시장 일간수익 원값).
#     조건 = 관측 급락일 수 n_L,i ≥ ceiling(n_L / 2)  ∧  e_L,i ≥ 0.   (0 = 시장과 같은 급락일 손실 = 문턱의 자연 영점)
#     ★c* ≥ 0 인 달(공동 분기가 오른쪽 꼬리)은 [B] 의 급락일 구조가 그 창에 없는 것이므로 자격을 걸지 않고 [A] 만
#       발행한다(건수 인쇄). 트리 미성립(후보 부족)도 같다.
#   ▸ [A] 창 W_A = (me[k−6], f] 6개월 일별 종가 로그가격 경로 · path = log P − log P_0 · dd = path − cummax(path) ·
#     t* = argmin dd · peak = argmax path[1..t*] · CM = R_I + 2·R_II + R_III = C − MDD  (충실구현 판과 같은 함수).
#   ▸ 산출 = FACTORS(Date = f, Ticker, Score = CM), **자격 통과 종목만**. 러너가 top-25 롱온리 EW 월간(FIDELITY portfolio_spec).
#   ★퇴화 경계: 자격이 순위를 못 바꾸면(F1: 통과자 top-25 vs 전체 top-25 겹침 중앙 ≥ 0.80, 또는 F2: 통과율 중앙 ≥ 0.95)
#     이 판은 [A] 월간의 재라벨이다 — 결과와 무관하게 설계 실패로 기록한다. F3: rho(e_L, 창 β) 중앙 |·| ≥ 0.90 이면
#     자격은 저β 스크린과 같다(CM+BAB 0.5/0.5 = B1_2 PORT_t −0.018 의 실측 계보) — 그 경우도 설계 실패다.
#
# =============================================================================
# §4. PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다)
# =============================================================================
#   ▸ 구조 경계 1: 모든 창의 종점이 f 이하다. [B] 창 = 행 (ip − 1258):ip (ip = f 의 행) · [A] 창 = 격자 > me[k−6] ∧ ≤ f.
#     ip 를 넘는 인덱스 · 음수 shift · lead · 전표본 통계 0건(shift 는 +1 한 번 — adv20 의 t−1 · 시장 종가 수익 1회).
#   ▸ 구조 경계 2: c* · 잎 · e_L · CM · 진단이 전부 그 형성일의 창 **안에서만** 계산된다. 형성일 간 상태 이월 0건.
#   ▸ 구조 경계 3: 자격(멤버십·유동성)은 f 시점 관측이고 유동성 창 종점은 f−1.
#   C1 rolling 만 · C2 f 종가까지 · C3 형성창 종점 f < 보유월 · C4 재무 미사용 · C5 오버레이 없음(c*·e_L 은 과거 창의
#   횡단면 자격이지 실현수익 스케일러가 아니다) · C6 유니버스 = f 의 K200/KQ150 플래그(PIT 시변) · C7 shift +1 뿐 ·
#   C9 DD/VT 미사용 · C10 adv20 = frollmean 후 shift(1) · C11 rf = **전월** CD91 마지막 호가 / **전월** 거래일수(당월
#   거래일수는 그 달이 끝나야 확정) · C13 NEGATE/FLIP 0건(방향 = [A] 오름차순 승자 롱 하나) · C15 팩터 DB 미접근 ·
#   rawdata Market 열 미사용.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(arrow)
  library(matrixStats)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.TAG <- "[COMBO_CM_TAIL]"
.REQ <- c("Date", "Ticker", "Close", "Vol", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("%s RAWDATA 열 부족: %s", .TAG, paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))
.t0 <- Sys.time()

# =============================================================================
# 0. 상수 — 출처가 넷뿐이다: (a) [A] 명시값 (b) [B] 명시값 (c) 지시된 고정 축 (d) 규약·진단(전부 FIDELITY 신고)
# =============================================================================
# ▸ (a) [A] 명시값
.W_CM      <- c(1, 2, 1)       # Table 1 CM = (R_I, R_II, R_III) 가중 = C − MDD (월간 최우수 규칙, Table 3)
.FORM_M    <- 6L               # §3.2 "6 months ... of estimation period" — 월말 격자 6스텝
# ▸ (b) [B] 명시값
.T_WIN     <- 1259L            # "The sample comprises 1259 daily returns" — 트리 창 (거래일)
# ▸ (c) 지시된 고정 축 (두 논문에 없다)
.LIQ       <- 2e8              # adv20(t−1) 하한 (KRW)
.LIQ_WIN   <- 20L              # 유동성 창 (거래일) · 뒤의 shift(1) 이 종점을 f−1 로 만든다
# ▸ (d) 규약 — Score 값이 아니라 정의역·데이터 위생·자격 문턱 (FIDELITY changed ③ 전수 신고)
.MIN_LEAF  <- 2L               # 잎이 성립하는 최소 관측(평균의 정의역 — [B] 단독구현·1판 관례)
.MIN_STK   <- 2L               # 공동 트리가 성립하는 최소 참여 종목수([B] 표본은 5종 · 단독구현 관례)
.MIN_COV   <- 0.80             # 트리 **적합 참여** 커버리지 하한 = 5년 창 중 4년치 ([B] 단독구현·1판 관례)
.RET_CAP   <- 1.0              # 트리 목적변수 전용 아티팩트 제거 — KRX 가격제한폭 ±30% 하에 |일간수익|>100% 는 물리 불가
.LEAF_FRAC <- 0.5              # 자격 정의역: 종목이 관측된 급락일 수 ≥ ceiling(0.5 × n_L) — 같은 날들 위의 평균이어야 비교 가능
.E_MIN     <- 0                # 자격 문턱: 급락일 시장 대비 초과 평균 ≥ 0 (영점 = 시장과 같은 손실)
.PCT       <- 100              # CD91 호가 = 연 % → 소수
.MPY       <- 12L              # 연 → 월 (rf 월간화)
# ▸ 진단 전용 — Score·자격에 쓰이지 않는다
.NTOP      <- 25L              # 고정 축 종목수 — top-25 겹침 진단의 n
.DIAG_MIN  <- 5L               # 순위상관을 계산하는 최소 횡단면(그 아래는 NA)
.OVL_MAX   <- 0.80             # F1 재라벨 판정 문턱(통과자 top-25 vs 전체 top-25 겹침 중앙 ≥ 0.80 = 자격 무작동)
.PASS_MAX  <- 0.95             # F2 자격 무작동 판정 문턱(통과율 중앙 ≥ 0.95)
.RHO_MAX   <- 0.90             # F3 저β 스크린 동치 판정 문턱(|rho(e_L, β)| 중앙 ≥ 0.90)
.RANGE0    <- as.Date("2005-01-01")   # F4 월 결번 진단의 분모 범위(측정구간 시작 = 러너 start_date)

# =============================================================================
# 1. 보조 함수
# =============================================================================
.as_flag <- function(x) {                     # 멤버십 플래그: 논리/0-1/문자 혼재 방어
  if (is.logical(x)) return(x %in% TRUE)
  if (is.numeric(x)) return(is.finite(x) & x != 0)
  toupper(trimws(as.character(x))) %in% c("TRUE", "T", "1", "Y", "YES")
}
.med <- function(x) { x <- as.numeric(x); x <- x[is.finite(x)]; if (length(x)) median(x) else NA_real_ }

# ---- [A] 형성창 로그가격 경로 → C / MDD / 3-국면 (창 내부 통계만, C1) ----------
#   RP_AUTO_1403_8125/engine.R 의 .mdd_stats 와 동일(그 판은 감사 faithful). cl = 창 안 그 종목의 거래일 종가(Date 오름차순).
#   ★경로는 미처리다: path = log(P) − log(P_0). 절단·winsorize·clip 없음. cummax 는 t≤τ 포함형(단조 상승 = MDD 0). n<2 = 정의역 밖.
.path_stats <- function(cl) {
  n <- length(cl)
  if (n < 2L)
    return(list(C = NA_real_, MDD = NA_real_, RI = NA_real_, RII = NA_real_, RIII = NA_real_, nobs = n))
  path <- log(cl) - log(cl[1L])                 # 상대 로그가격 경로 (미처리)
  dd   <- path - cummax(path)                   # <= 0
  ts   <- which.min(dd)                         # trough t* (동값이면 최초)
  tp   <- which.max(path[seq_len(ts)])          # trough 이전(포함) peak
  list(C = path[n], MDD = -dd[ts], RI = path[tp], RII = path[ts] - path[tp], RIII = path[n] - path[ts], nobs = n)
}

# ---- [B] 공동 depth=1 회귀트리 — 분기변수 mex 하나, 목적변수 = 창 안 참여 종목의 일간수익 행렬 -------
#   RP_AUTO_2007_08115/engine.R 의 적합 블록과 동일 산술(1판도 같은 블록). SSE 최소화 = 아래 gain 최대화 (TSS 는 분기점 무관).
#   종목별 표준화 없음(B2 — dominant stock 은 설계의 성질). 결측 셀은 마스크로 제외(그 잎에 기여 0).
#   반환: c* = 인접 두 mex 의 중점(sklearn 규약) · left_rows = 왼쪽 잎(mex 가 작은 쪽) 의 **창 내 행 위치**.
.joint_split <- function(Y, mexw, min_leaf) {
  o   <- order(mexw)
  ms  <- mexw[o]
  Ys  <- Y[o, , drop = FALSE]
  Mk  <- matrix(as.numeric(!is.na(Ys)), nrow = nrow(Ys))
  Xs  <- Ys; Xs[is.na(Xs)] <- 0
  CX  <- colCumsums(Xs)
  CN  <- colCumsums(Mk)
  Tn  <- nrow(Xs); Mn <- ncol(Xs)
  SX  <- CX[Tn, ]; SN <- CN[Tn, ]
  RXm <- matrix(SX, Tn, Mn, byrow = TRUE) - CX
  RNm <- matrix(SN, Tn, Mn, byrow = TRUE) - CN
  LTm <- CX^2  / CN
  RTm <- RXm^2 / RNm
  LTm[!is.finite(LTm)] <- 0                     # 잎에 관측이 없는 종목 = 기여 0
  RTm[!is.finite(RTm)] <- 0
  gain <- rowSums(LTm + RTm)
  ok <- c(ms[-Tn] < ms[-1L], FALSE)             # 값이 실제로 갈리는 자리만 유효 분기점
  ok[seq_len(min_leaf - 1L)] <- FALSE           # 양쪽 잎 최소 관측
  ok[(Tn - min_leaf + 1L):Tn] <- FALSE
  if (!any(ok)) return(NULL)
  gain[!ok] <- -Inf
  ks <- which.max(gain)
  list(cstar = (ms[ks] + ms[ks + 1L]) / 2, ks = ks, Tn = Tn, left_rows = o[seq_len(ks)])
}

# =============================================================================
# 2. 시장 계열 — 일간수익 원값(r_m) · rf(전월 CD91) · mex = r_m − rf   (B4: 분기변수 = 시장초과수익)
# =============================================================================
.bm <- NULL
if (exists("BM_DT") && is.data.table(BM_DT) && nrow(BM_DT)) {
  .b <- copy(BM_DT)
  if (!inherits(.b$Date, "Date")) .b[, Date := as.Date(Date)]
  setorder(.b, Date)
  if (!"BM_Ret" %in% names(.b) && "BM_Close" %in% names(.b))
    .b[, BM_Ret := BM_Close / shift(BM_Close, 1L) - 1]         # shift = 과거 방향(직전 거래일 종가)
  if ("BM_Ret" %in% names(.b)) .bm <- unique(.b[is.finite(BM_Ret), .(Date, MKT = BM_Ret)], by = "Date")
  rm(.b)
}
if ((is.null(.bm) || !nrow(.bm)) && "BM_Ret" %in% names(RAWDATA))
  .bm <- unique(RAWDATA[is.finite(BM_Ret), .(Date, MKT = BM_Ret)], by = "Date")
if (is.null(.bm) || !nrow(.bm))
  stop(sprintf("%s 시장 일간수익 계열 부재 — BM_DT(BM_Ret/BM_Close) 확인", .TAG))
if (!inherits(.bm$Date, "Date")) .bm[, Date := as.Date(Date)]
setorder(.bm, Date)

# rf 원천 = ECOS KR_CD91 일별 호가(연 %). 월 m 의 일간 rf = (m−1 월 마지막 호가 / 100 / 12) / (m−1 월 거래일수).
#   분자·분모 모두 전월 확정치 — 당월 거래일수는 그 달이 끝나야 확정되므로 분모로 쓰면 월초에 모르는 값이 들어간다(C11).
#   파일 부재·열 부재·0행이면 rf = 0 으로 측정하고 인쇄한다(침묵 폴백 아님 — [B] 정의(excess)와의 차이를 로그로 드러낸다).
.rf_path <- local({
  cd <- if (exists("CACHE_DIR", inherits = TRUE)) as.character(get("CACHE_DIR", inherits = TRUE))[1L] else ""
  if (!nzchar(cd)) {
    root <- Sys.getenv("QM_ROOT", "")
    if (!nzchar(root)) root <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
    if (!nzchar(root) && exists("PROJECT_ROOT", inherits = TRUE)) root <- as.character(get("PROJECT_ROOT", inherits = TRUE))[1L]
    if (!nzchar(root)) root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
    cd <- file.path(root, ".cache")
  }
  file.path(cd, "ecos_bond_rates.parquet")
})
.rfm <- NULL                                                     # data.table(ym, RF_M) — 그 달 마지막 CD91 호가의 월간 소수
if (file.exists(.rf_path)) {
  .ec <- tryCatch(as.data.table(read_parquet(.rf_path)), error = function(e) NULL)
  if (!is.null(.ec) && all(c("Date", "Value", "Series") %in% names(.ec))) {
    .ec <- .ec[Series == "KR_CD91" & is.finite(Value)]
    if (nrow(.ec)) {
      .ec[, Date := as.Date(Date, tz = "Asia/Seoul")]              # POSIXct 면 KST 로 날짜화(UTC 자정 경계 이월 방지)
      setorder(.ec, Date)
      .ec[, ym := year(Date) * 12L + month(Date)]
      .rfm <- .ec[, .(RF_M = Value[.N] / .PCT / .MPY), by = ym]  # 그 달 마지막 관측 호가
      setorder(.rfm, ym)
    }
  }
  rm(.ec)
}
if (is.null(.rfm)) cat(sprintf("%s rf 원천(KR_CD91) 없음/열 부재 — mex = 시장수익(rf=0)으로 측정한다 (논문 정의 excess 와의 차이 · PIT 문제 아님)\n", .TAG))

# =============================================================================
# 3. 거래일 격자 = RAWDATA ∩ 시장계열 (mex 가 정의되는 날만 · 유령 거래일 배제) · rf 일할 · mex
# =============================================================================
.rd <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]
if (!inherits(.rd$Date, "Date")) .rd[, Date := as.Date(Date)]
.rd[, Ticker := as.character(Ticker)]
.rd <- .rd[is.finite(Close) & Close > 0]
.rd[, MEM := .as_flag(K200) | .as_flag(KQ150)]
.rd[, c("K200", "KQ150") := NULL]

.gdv <- as.Date(sort(intersect(unique(.rd$Date), .bm$Date)), origin = "1970-01-01")
if (length(.gdv) < (.T_WIN + 200L))
  stop(sprintf("%s 거래일 격자 %d일 — 창 %d일 + 워밍업에 못 미침", .TAG, length(.gdv), .T_WIN))
.GD <- data.table(Date = .gdv)
.GD[, ym := year(Date) * 12L + month(Date)]
.GD[, rf := 0]
.n_rf0 <- NA_integer_
if (!is.null(.rfm)) {
  .nd <- .GD[, .(nd = as.numeric(.N)), by = ym]
  .rm <- merge(.rfm, .nd, by = "ym", all.x = TRUE)
  setorder(.rm, ym)
  .rm[, ym_p := shift(ym, 1L)]                                   # 직전 행(과거 방향)
  .rm[, RF_p := shift(RF_M, 1L)]
  .rm[, nd_p := shift(nd, 1L)]
  .rm[is.na(ym_p) | ym_p != (ym - 1L), c("RF_p", "nd_p") := list(NA_real_, NA_real_)]   # 결번 월은 인정하지 않는다
  .rm[, rf_d := fifelse(is.finite(RF_p) & is.finite(nd_p) & nd_p > 0, RF_p / nd_p, 0)]
  .GD <- merge(.GD, .rm[, .(ym, rf_d)], by = "ym", all.x = TRUE)
  .GD[, rf := fifelse(is.finite(rf_d), rf_d, 0)]
  .GD[, rf_d := NULL]
  setorder(.GD, Date)
  .n_rf0 <- sum(.GD$rf == 0)
  rm(.nd, .rm)
}
.GD <- merge(.GD, .bm, by = "Date")
setorder(.GD, Date)
.GD[, mex := MKT - rf]

# 월말 거래일 격자 (격자 위 그 달 마지막 거래일). RAWDATA 의 마지막(진행 중) 달도 격자에 있다 — 그 형성은 익월 집행이 없다.
.me_dates <- sort(.GD[, .(f = max(Date)), by = ym]$f)

# =============================================================================
# 4. 종목 패널 — 유동성 adv20(t−1) · Date 키 · 일간수익 행렬(트리 목적변수 · 잎 통계 · β 진단)
# =============================================================================
setorder(.rd, Ticker, Date)
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("%s (Ticker,Date) 중복 %d행 — 첫 행만 유지\n", .TAG, .ndup))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}
.rd[, TV := Close * fifelse(is.finite(as.numeric(Vol)), as.numeric(Vol), 0)]   # 거래량 결측 = 그날 회전 0
.rd[, ADV20_L1 := shift(frollmean(TV, .LIQ_WIN, align = "right"), 1L), by = Ticker]   # 종점 = t−1 (C10)
.rd[, c("TV", "Vol") := NULL]
.rd <- .rd[Date %in% .gdv]                                       # 격자 밖 날짜(시장계열 없는 날) 제외
setkey(.rd, Date)

# 관심 종목 = 표본 기간 중 한 번이라도 K200 또는 KQ150 이었던 종목 (f 시점 자격 술어의 상위집합 — 동치)
.tk <- unique(.rd[MEM == TRUE, Ticker])
if (!length(.tk)) stop(sprintf("%s K200/KQ150 멤버십 0건", .TAG))
.px <- .rd[Ticker %chin% .tk, .(Date, Ticker, Close)]
.CW <- dcast(.px, Date ~ Ticker, value.var = "Close")
setorder(.CW, Date)
.cdates <- .CW$Date
.PXM <- as.matrix(.CW[, -1L, with = FALSE])
.tick <- colnames(.PXM)
rm(.CW, .px); gc(verbose = FALSE)
.nr <- nrow(.PXM)
RET <- .PXM[-1L, , drop = FALSE] / .PXM[-.nr, , drop = FALSE] - 1   # 행 t = 격자 t−1 → t 의 수익 (과거 방향)
.rdt <- .cdates[-1L]
RET[!is.finite(RET)] <- NA_real_
RET[which(abs(RET) > .RET_CAP)] <- NA_real_                      # 트리 목적변수·잎 통계 전용 위생 (가격제한폭 근거)
rm(.PXM); gc(verbose = FALSE)

setkey(.GD, Date)
.mexv <- .GD[.(.rdt), mex]
.mktv <- .GD[.(.rdt), MKT]
if (anyNA(.mexv) || anyNA(.mktv)) stop(sprintf("%s mex/시장수익 정렬 실패 — 격자/시장계열 불일치", .TAG))

cat(sprintf("%s 격자 %d일 (%s~%s) · 월말 %d개 · 수익 행렬 %d일 × %d종 · 결측 %.1f%% · rf 원천 %s%s\n",
            .TAG, length(.gdv), as.character(min(.gdv)), as.character(max(.gdv)), length(.me_dates),
            nrow(RET), ncol(RET), 100 * mean(is.na(RET)),
            if (is.null(.rfm)) "없음(rf=0)" else "KR_CD91 전월",
            if (is.finite(.n_rf0)) sprintf(" · rf=0 인 격자일 %d", .n_rf0) else ""))
cat(sprintf("%s 상수: CM(%s) · [A] 창 %d개월 · [B] 창 %d거래일 · 트리 참여 커버리지 ≥ %.2f · 잎 최소 %d · 자격 n_L,i ≥ ceiling(%.1f·n_L) ∧ e_L ≥ %g · adv20(t−1) ≥ %.0e\n",
            .TAG, paste(.W_CM, collapse = ","), .FORM_M, .T_WIN, .MIN_COV, .MIN_LEAF, .LEAF_FRAC, .E_MIN, .LIQ))

# =============================================================================
# 5. 형성월 루프 — [B] 공동 트리 → 급락일 잎 → 자격 · [A] CM 순위 → FACTORS(자격 통과자만)
# =============================================================================
.OUT <- vector("list", length(.me_dates)); .LOG <- vector("list", length(.me_dates))
.skip_warm <- 0L; .skip_win <- 0L; .skip_def <- 0L
.n_noscreen_tree <- 0L; .n_noscreen_sign <- 0L
for (k in seq_along(.me_dates)) {
  if (k <= .FORM_M) { .skip_warm <- .skip_warm + 1L; next }        # me_dates[k−6] 필요 ([A] 워밍업)
  f  <- .me_dates[k]
  ip <- match(f, .rdt)
  if (is.na(ip) || ip < .T_WIN) { .skip_win <- .skip_win + 1L; next }   # [B] 창 1,259일 필요

  # ---- 자격 1단: f 의 K200/KQ150 멤버십 + 지시 축 adv20(t−1) 하한 (C6 · C10) — f 에 종가가 있는 종목만 ----
  rf_  <- .rd[.(f), .(Ticker, MEM, ADV20_L1), nomatch = 0L]
  elig <- rf_[MEM & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ, Ticker]
  elig <- intersect(elig, .tick)
  if (!length(elig)) { .skip_def <- .skip_def + 1L; next }

  # ---- [A] 6개월 경로 → CM (적격 전원 — 자격 통과 여부와 무관하게 계산: 겹침 진단의 기준) ----
  w0   <- .me_dates[k - .FORM_M]
  wd_m <- .gdv[.gdv > w0 & .gdv <= f]                              # 6개월 일별 격자 (종점 = f)
  if (!length(wd_m)) { .skip_def <- .skip_def + 1L; next }
  pm <- .rd[.(wd_m), .(Date, Ticker, Close), nomatch = 0L][Ticker %chin% elig]
  if (!nrow(pm)) { .skip_def <- .skip_def + 1L; next }
  setorder(pm, Ticker, Date)
  sm <- pm[, .path_stats(Close), by = Ticker]
  sm[, cm := .W_CM[1] * RI + .W_CM[2] * RII + .W_CM[3] * RIII]     # CM = C − MDD (승자 = 큰 값 롱)
  st <- sm[is.finite(cm), .(Ticker, cm, MDD_m = MDD, C_m = C, n_m = nobs)]
  if (!nrow(st)) { .skip_def <- .skip_def + 1L; next }

  # ---- [B] 창: 행 (ip − 1258):ip (종점 = f) · 후보 = 적격 종목 전원 · 트리 참여 = 커버리지 ≥ 80% ∧ f 관측 ----
  wi   <- (ip - .T_WIN + 1L):ip
  mexw <- .mexv[wi]
  mktw <- .mktv[wi]
  Y    <- RET[wi, elig, drop = FALSE]
  Mw   <- !is.na(Y)
  cov_n <- colSums(Mw)
  keep  <- (cov_n >= as.integer(.MIN_COV * .T_WIN)) & Mw[.T_WIN, ]
  sp <- if (sum(keep) >= .MIN_STK) .joint_split(Y[, keep, drop = FALSE], mexw, .MIN_LEAF) else NULL

  # ---- 창 β (진단 전용 — F3: 자격이 저β 스크린과 같은가) · 관측일 짝맞춤 OLS ----
  Xw  <- Y; Xw[!Mw] <- 0
  n_i <- cov_n
  Sx  <- colSums(Xw); Sm <- colSums(Mw * mktw); Sxm <- colSums(Xw * mktw); Smm <- colSums(Mw * mktw^2)
  bet <- (n_i * Sxm - Sx * Sm) / (n_i * Smm - Sm^2)
  bet[!is.finite(bet)] <- NA_real_

  # ---- 자격 2단: 왼쪽 잎(급락일) 위 시장 대비 초과 평균 ≥ 0 ∧ 관측 급락일 수 ≥ ceiling(n_L / 2) ----
  screen_on <- !is.null(sp) && is.finite(sp$cstar) && sp$cstar < 0
  if (is.null(sp)) .n_noscreen_tree <- .n_noscreen_tree + 1L
  else if (!screen_on) .n_noscreen_sign <- .n_noscreen_sign + 1L
  eL <- rep(NA_real_, length(elig)); nLi <- rep(0L, length(elig)); names(eL) <- elig; names(nLi) <- elig
  n_L <- NA_integer_; cstar <- NA_real_; n_tree <- sum(keep)
  if (screen_on) {
    L    <- sp$left_rows
    n_L  <- length(L)
    cstar <- sp$cstar
    ML   <- Mw[L, , drop = FALSE]
    XL   <- Xw[L, , drop = FALSE]
    nLi  <- colSums(ML)
    eL   <- (colSums(XL) - colSums(ML * mktw[L])) / nLi            # 관측된 급락일 위 (r_i − r_m) 평균 · nLi = 0 → NaN
    eL[!is.finite(eL)] <- NA_real_
    pass_v <- is.finite(eL) & nLi >= ceiling(.LEAF_FRAC * n_L) & eL >= .E_MIN
  } else {
    pass_v <- rep(TRUE, length(elig)); names(pass_v) <- elig         # [B] 구조 부재 달 = [A] 만 (건수 인쇄)
  }
  st[, e_L := eL[Ticker]]
  st[, n_L_i := as.integer(nLi[Ticker])]
  st[, beta := bet[Ticker]]
  st[, pass := pass_v[Ticker] %in% TRUE]
  setorder(st, -cm, Ticker)                                        # 결정론적 동값 처리 (cm 내림, Ticker 오름)

  out <- st[pass == TRUE]
  if (nrow(out)) .OUT[[k]] <- data.table(Date = f, Ticker = out$Ticker, Score = out$cm)

  # ---- 진단 (전부 이 형성일 단면·창 내부 통계 — 미래참조 0) ----
  N <- nrow(st); nt <- min(.NTOP, N); npass <- nrow(out)
  top_all  <- st$Ticker[seq_len(nt)]
  top_pass <- out$Ticker[seq_len(min(.NTOP, npass))]
  ok_rho <- is.finite(st$e_L) & is.finite(st$beta)
  .LOG[[k]] <- data.table(
    f = f, N_elig = length(elig), N_cm = N, n_tree = n_tree, screen = screen_on,
    cstar_bp = 1e4 * cstar, n_L = n_L, bal_L = if (is.finite(n_L)) n_L / .T_WIN else NA_real_,
    n_undef = if (screen_on) sum(!is.finite(st$e_L) | st$n_L_i < ceiling(.LEAF_FRAC * n_L)) else 0L,
    n_pass = npass, pass_rate = if (N > 0L) npass / N else NA_real_,
    ovl = if (length(top_pass)) length(intersect(top_pass, top_all)) / nt else NA_real_,
    rho_e_beta = if (sum(ok_rho) >= .DIAG_MIN) suppressWarnings(cor(st$e_L[ok_rho], st$beta[ok_rho], method = "spearman")) else NA_real_,
    e_top = .med(out$e_L[seq_len(min(.NTOP, npass))]), e_all = .med(st$e_L),
    beta_top = .med(out$beta[seq_len(min(.NTOP, npass))]), beta_all = .med(st$beta),
    cm_top = .med(out$cm[seq_len(min(.NTOP, npass))]), cm_top_all = .med(st$cm[seq_len(nt)]),
    mdd_top = .med(out$MDD_m[seq_len(min(.NTOP, npass))]), mdd_all = .med(st$MDD_m),
    cov_m = .med(st$n_m) / length(wd_m))
}

FACTORS <- rbindlist(Filter(Negate(is.null), .OUT), use.names = TRUE)
if (!nrow(FACTORS))
  stop(sprintf("%s FACTORS 0행 — 워밍업 skip %d · 창 미달 skip %d · 정의역 skip %d", .TAG, .skip_warm, .skip_win, .skip_def))
setorder(FACTORS, Date, -Score)
if (anyDuplicated(FACTORS, by = c("Date", "Ticker")) > 0L) stop(sprintf("%s FACTORS (Date,Ticker) 중복", .TAG))
rm(RET); gc(verbose = FALSE)

# =============================================================================
# 6. 보고 — 구성 요약 + 엔진이 스스로 인쇄하는 반증 5종 (성과 수치 선언 아님 · 등급은 계약이 낸다)
# =============================================================================
LG <- rbindlist(Filter(Negate(is.null), .LOG), use.names = TRUE)
LG[, yr := year(f)]
.byyr <- LG[, .(n_m = .N, cstar_bp = round(.med(cstar_bp), 1), bal = round(100 * .med(bal_L), 1),
                pass = round(100 * .med(pass_rate), 0), n_pass = as.integer(.med(n_pass)),
                ovl = round(.med(ovl), 2), rho = round(.med(rho_e_beta), 2)), by = yr]
setorder(.byyr, yr)
cat(sprintf("%s 연도별 [B] 공동 분기·자격 (분기변수 = mex 단일 · 잎 = 왼쪽):\n", .TAG))
for (i in seq_len(nrow(.byyr)))
  cat(sprintf("    %d | 월 %2d · c* %7.1fbp · 좌잎 %5.1f%% · 통과율 %3.0f%% · 통과 %3d종 · top-25 겹침 %.2f · rho(e_L,β) %+.2f\n",
              .byyr$yr[i], .byyr$n_m[i], .byyr$cstar_bp[i], .byyr$bal[i], .byyr$pass[i], .byyr$n_pass[i], .byyr$ovl[i], .byyr$rho[i]))

# F4 — ★세기 전에 범위를 선언한다: 분모 = 측정구간(.RANGE0~)의 월말 중 워밍업·창 요건을 만족하는 것.
.cand_f <- .me_dates[.me_dates >= .RANGE0 & seq_along(.me_dates) > .FORM_M]
.cidx   <- match(.cand_f, .rdt)                                   # 벡터 match (Date vs Date) — 원소 순회는 Date 클래스를 벗긴다
.cand_f <- .cand_f[!is.na(.cidx) & .cidx >= .T_WIN]
.got_f  <- unique(FACTORS$Date[FACTORS$Date >= .RANGE0])
.miss   <- !(.cand_f %in% .got_f)
.rl     <- rle(.miss)
.gapmax <- if (any(.miss)) max(.rl$lengths[.rl$values]) else 0L
.f1 <- .med(LG$ovl); .f2 <- .med(LG$pass_rate); .f3 <- .med(LG$rho_e_beta)
.nmn <- FACTORS[, .N, by = Date]

cat(sprintf(paste0(
  "%s combination: 순위 = [A] CM(6개월 경로 · Table 1 (1,2,1)) · 자격 = [B] 공동 depth=1 트리(창 %d일) 왼쪽 잎(시장 급락일) 위 시장 대비 초과 평균 ≥ %g\n",
  "  형성 %d개월(%s~%s · 워밍업 skip %d · 창 미달 skip %d · 정의역 skip %d) · 자격 미적용 달: 트리 미성립 %d · c* ≥ 0 %d\n",
  "  FACTORS %s행 · 발행 종목/월 중앙 %d (min %d / max %d) · 적격 중앙 %d · 트리 참여 중앙 %d · 급락일 n_L 중앙 %d (좌잎 %.1f%%) · c* 중앙 %.1fbp\n",
  "  [진단·비스크린] 자격 정의역 밖(급락일 관측 부족) 중앙 %d종 · e_L 중앙 통과 top-25 %+.4f / 전체 %+.4f · 창 β 중앙 top-25 %.2f / 전체 %.2f\n",
  "  top-25 CM 중앙 통과자 %.3f vs 전체 %.3f · 창내 MDD 중앙 top-25 %.1f%% / 전체 %.1f%% · [A] 창 커버리지 중앙 %.2f\n"),
  .TAG, .T_WIN, .E_MIN,
  nrow(LG), as.character(min(LG$f)), as.character(max(LG$f)), .skip_warm, .skip_win, .skip_def,
  .n_noscreen_tree, .n_noscreen_sign,
  format(nrow(FACTORS), big.mark = ","), as.integer(.med(.nmn$N)), min(.nmn$N), max(.nmn$N),
  as.integer(.med(LG$N_elig)), as.integer(.med(LG$n_tree)), as.integer(.med(LG$n_L)), 100 * .med(LG$bal_L), .med(LG$cstar_bp),
  as.integer(.med(LG$n_undef)), .med(LG$e_top), .med(LG$e_all), .med(LG$beta_top), .med(LG$beta_all),
  .med(LG$cm_top), .med(LG$cm_top_all), 100 * .med(LG$mdd_top), 100 * .med(LG$mdd_all), .med(LG$cov_m)))

cat(sprintf(paste0(
  "%s 반증 (전부 형성일 단면 통계 · 미래참조 0):\n",
  "  F1 [A]월간 재라벨 아님 : 통과자 top-25 vs 전체 top-25 겹침 중앙 %.3f → %s (기준 < %.2f — 자격이 순위를 바꿨는가)\n",
  "  F2 자격 무작동 아님     : 통과율 중앙 %.3f → %s (기준 < %.2f)\n",
  "  F3 저β 스크린 아님      : rho(e_L, 창 β) 단면 중앙 %+.3f → %s (기준 |rho| < %.2f — 같으면 CM+BAB 계보(B1_2 −0.018)와 동치)\n",
  "  F4 월 결번 0            : [범위 = %s~ ∧ 워밍업·창 요건 이후] 후보 %d · 산출 %d · 최대 연속 결번 %d → %s\n",
  "  F5 자격 적용 비율       : %d/%d 형성월 (미적용 달은 [A] 단독 — 위 두 계수 참조)\n",
  "  ★러너 사양 = FIDELITY.json 의 portfolio_spec (top_n_long · ew · monthly · n_max %d) · commission_paper = null · %.1f분\n"),
  .TAG,
  .f1, if (is.finite(.f1) && .f1 < .OVL_MAX) "PASS" else "FAIL", .OVL_MAX,
  .f2, if (is.finite(.f2) && .f2 < .PASS_MAX) "PASS" else "FAIL", .PASS_MAX,
  .f3, if (is.finite(.f3) && abs(.f3) < .RHO_MAX) "PASS" else "FAIL", .RHO_MAX,
  as.character(.RANGE0), length(.cand_f), sum(.cand_f %in% .got_f), .gapmax,
  if (length(.cand_f) && all(.cand_f %in% .got_f) && .gapmax == 0L) "PASS" else "FAIL",
  sum(LG$screen), nrow(LG),
  .NTOP, as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
