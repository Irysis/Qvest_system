# =============================================================================
# engine.R — RP_AUTO_COMBO_combo_1403_8125_2007_081
#
#   [A] Jaehyung Choi, Sungsoo Choi, Wonseok Kang, "Maximum drawdown, recovery,
#       and momentum" (arXiv:1403.8125)          https://arxiv.org/abs/1403.8125
#   [B] Vassilis Polimenis, "Uncovering a factor-based expected return
#       conditioning structure with Regression Trees jointly for many stocks"
#       (arXiv:2007.08115)                       https://arxiv.org/abs/2007.08115
#   [C] Mykola Pinchuk, "Labor Income Risk and the Cross-Section of Expected
#       Returns" (arXiv:2301.09173)              — **미사용**(사유는 FIDELITY.changed ③)
#
# ★fidelity = COMBINATION. 선언 정본 = FIDELITY.json (이 주석은 사본이지 통로가 아니다)
#
# =============================================================================
# 한 문장 요약
# =============================================================================
#   [A] 의 최우수 규칙 CM = C - MDD 는 **자기 경로 낙폭**을 뺀다. 그런데 그 낙폭이
#   시장 전체가 무너진 날들에서 온 것인지(체계적 = 25종목으로 분산되지 않는다),
#   그 종목만 무너진 날들에서 온 것인지(고유 = 분산된다) [A] 는 구분하지 못한다.
#   [B] 는 그 구분을 만드는 유일한 장치를 준다 — 전 종목 공동적합 depth=1 트리가
#   고르는 **공통 악화국면 경계 c\***.
#   ▸ Score = CM + R_II^sys  =  (C - MDD) + (낙폭 구간 중 공통 악화일에 난 손실)
#     = [A] Table 1 문법("문제라고 보는 다리에 가중 1을 더한다")을 [B] 가 비로소
#       보이게 만든 다리(낙폭의 체계 성분)에 한 번 더 적용한 것.
#
# =============================================================================
# §1. [A] 원문 대조  (arxiv.org/html/1403.8125v1 · 2026-09-05 본 세션 직접 확인)
# =============================================================================
#  (A1) 식(1) "MDD = max_{tau in (0,T)} ( max_{t in (0,tau)} ( P(t) - P(tau) ) )"
#       [로그가격 경로의 peak->trough 최악 낙폭]
#  (A2) 분해  "C = R_I + R_II + R_III = PP - MDD + R"
#       R_I = 시작->peak · R_II = peak->trough(= -MDD) · R_III = trough->말일(회복)
#  (A3) Table 1 — 7 규칙의 (R_I,R_II,R_III) 정수 가중:
#       C(1,1,1) · M(0,1,0) · R(0,0,1) · RM(0,1,1) · **CM(1,2,1)** · CR(1,1,2) · CMR(1,2,2)
#       ★Table 1 의 문법 = "중요하다고 보는 다리에 가중을 1 더한다"(C->CM 은 R_II 에,
#         CM->CMR 은 R_III 에 정확히 +1). 본 엔진의 결합 연산자가 이 문법이다.
#  (A4) 형성창  "Based on given selection rules during 6 months (weeks) of
#       estimation period" → 월간 축 = 6개월.
#  (A5) 정렬    "assets in market universes are sorted in ascending order" ·
#       "The group 1 is for losers ... the last group is for the best performers"
#       → 오름차순 · 스코어 큰 쪽이 승자 = 롱. 수동 부호반전 0건(C13).
#       "except for the maximum drawdown" 는 부호로 자동 처리된다(R_II = -MDD < 0).
#  (A6) §4.4  "For momentum portfolio construction, the maximum drawdown related
#       measures are the best stock selection rules."
#       → 월간 축에서 CM 을 고른 것은 논문 자신의 결과다(성과를 보고 고른 값이 아니다).
#  (A7) §4.4/Table 3 — KOSPI 200 월간, CM 이 최우수: 월평균 **1.433%**, sigma **7.036%**.
#       ★교차확인됨: 선행 단독구현 RP_AUTO_1403_8125 헤더가 다른 세션에서 같은 값을
#         독립 확보했다. 이 두 수치만 2-source 다.
#  (A8) [단일 판독 · 미교차확인] Table 3 의 나머지 6 규칙(C 1.331%/6.826% ·
#       M 1.023%/6.577% · R 0.374%/4.082% · RM 1.280%/6.241% · CR 1.103%/6.596% ·
#       CMR 1.311%/6.729%)과 "recovery portfolios ... less riskier in every risk
#       measures" 는 **본 세션 1회 판독**이다. ★이 엔진의 어떤 수치도 (A8)에서 오지
#       않는다 — 동기 서술일 뿐이고, 위험 축이 구속이라는 판단의 1급 근거는 논문이
#       아니라 이 저장소의 실측(§3)이다.
#
# =============================================================================
# §2. [B] 원문 대조  (★저장소 승계 인용 — 이 세션이 직접 검증하지 않았다)
# =============================================================================
#   arXiv 는 2020년 투고분의 HTML 판을 만들지 않는다(/html · ar5iv 404/redirect).
#   아래 축자 인용은 선행 세션이 PDF 전문 렌더로 확보해 RP_AUTO_2007_08115/engine.R
#   헤더 Q1~Q6 에 남긴 것을 승계했다. 그 축만 미검증으로 분리한다.
#  (B1) "Limiting to max depth = 1"
#  (B2) "The cost function that is minimized when choosing split points is the sum
#        squared error across all training samples against their sub-region
#        prediction" · "all input variables and all possible split points are
#        evaluated and chosen in a greedy algorithm."
#  (B3) "a single model capable of predicting simultaneously n stocks is built" ·
#       "correlation information enters the tree structure"
#       → 종목별 개별 트리가 아니라 **다출력 단일 트리**. 분기점 하나를 전 종목 SSE
#         합으로 고른다. 종목별 표준화 없음("the dominant stock in a joint
#         regression tree" 는 제거 대상이 아니라 설계의 일부).
#  (B4) "in all cases (solo and joint) the most informative factor is always the
#        market excess return factor"  → 분기변수 = mex.
#  (B5) 표본 = 미국 대형주 5종 · **1,259 daily returns**(2015-01-05~2020-04-30).
#  (B6) Table 2c — 임계값이 0 이 아니라 꼬리(-70bp 근방으로 joint 수렴), balance 는
#       1-99% ~ 22-78% 로 극단 불균형. 저자 스스로 "only done for demonstration
#       purposes and not for statistical inference".
#  (B7) 매매전략·백테스트·비용·종목수·비중·리밸 주기 = 전무 → commission_paper = null.
#
# =============================================================================
# §3. 이 결합이 겨냥하는 것 — 저장소 실측 (인용 정본, 손계산 아님)
# =============================================================================
#   [A] 를 **본 엔진과 같은 고정 축**(top-25 롱온리 EW · 월간 · K200∪KQ150 · 2005-01~
#   · 15bps)에서 잰 값 = 06_Registry/reinforce_ledger_l1.json ·
#   entry `RP_20260904_163647_18444_rescued_rulefast` · attempt n=1 · cell B1_1:
#       PORT_t 0.925 · SR 0.631 · CAGR 0.138 · MDD 0.577 · Calmar 0.240 · Grade C
#   ★프롬프트가 라벨한 "단독 t 2.567"(cell B3_12)은 **다른 축**이다 — 유니버스
#     KQ150 단독 · NAV 2010-02 시작(200개월, 2008 급락 제외). 그 원장 항목 자신이
#     "PORT_t·Calmar 를 기저와 직접 비교하지 말 것" 이라고 적어 두었다. 따라서
#     본 판의 반증 문턱은 2.567/0.517/0.499 가 아니라 **0.925/0.577/0.240** 이다.
#   ▸ 그 칸에서 구속된 것: 5조건 중 0 충족. 위험 축(Calmar 0.240 vs 0.64)과
#     t 축(0.925 vs 2.95)이 함께 막혀 있고, 둘 다 **분산 축소로 동시에 움직인다**
#     (PORT_t 와 SR 은 평균/변동성 비율이다). [A] 의 CM 은 Table 3 에서 7 규칙 중
#     sigma 가 가장 큰 규칙이다(A7·A8) — 줄일 여지가 그 규칙 안에 있다.
#
# =============================================================================
# §4. 결합 연산자 — 무엇을 어떻게 붙였나 (평균이 아니다)
# =============================================================================
#   형성창 W = (me[k-6], f]  (거래일 격자, 종점 = 형성일 f)
#   [A] 경로 분해:  path_i(t) = log P_i(t) - log P_i(첫관측)  (미처리 — [A] 규약)
#                   t_p = trough 이전 peak · t_s = trough
#                   R_II,i = path_i(t_s) - path_i(t_p) = -MDD_i  (<= 0)
#   [B] 국면 분할:  f 에서 끝나는 1,259 거래일 창 위에서 전 종목 공동 depth=1 트리를
#                   mex 에 greedy SSE 로 적합 → 공통 임계값 c*
#                   ADV = { d : mex_d <= c* }   (전 종목에 대해 **같은 날들**)
#   체계 성분:      R_II^sys_i = sum_{ t_p < m <= t_s , m in ADV } lr_i(m)
#                   (낙폭 구간 안에서 공통 악화일에 난 증분만 합한 것)
#                   항등식: R_II^sys + R_II^idio = R_II  (같은 창·같은 증분)
#
#   ▸ **Score_i = 1*R_I + 2*R_II + 1*R_III + R_II^sys = (C_i - MDD_i) + R_II^sys_i**
#
#   ★자유 파라미터 0 —  가중 (1,2,1) = [A] Table 1 CM(논문 헤드라인 규칙) ·
#     추가 +1 = [A] Table 1 자신의 증분 문법(A3) · 분할 c* = [B] 의 greedy SSE 가
#     매달 데이터에서 고른다 · 창 6개월 = [A](A4) · 창 1,259일 = [B](B5).
#     내가 고른 수치가 없다.
#
#   ★퇴화 경계가 양쪽 다 막혀 있다(선행 결합판이 여기서 갈렸다):
#     · c* 가 깊은 꼬리 → ADV 가 희소 → R_II^sys -> 0 → Score -> **[A] 의 CM 그 자체**
#       (재료 최고 단독 규칙. 퇴화의 바닥이 논문의 최우수 규칙이다)
#     · c* 가 중앙 → ADV 가 절반 → R_II^sys ~ R_II 의 상당 부분 → Score ~ C + 2*R_II
#       (Table 1 격자 바깥이지만 CM 과 같은 방향으로 유계)
#     어느 쪽에서도 스코어가 순수 하방베타나 순수 C 로 붕괴하지 않는다. 이것이
#     "두 신호의 rank-Z 평균"(이 저장소 5회 · 최고 PORT_t 0.766)과 다른 지점이다 —
#     스코어 층에 평균·블렌딩이 없고, [B] 는 스코어를 만들지 않고 **날짜를 가른다**.
#
# =============================================================================
# §5. PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다)
# =============================================================================
#  ▸ 구조 경계 1: 모든 창의 종점이 f 이하다. 창은 `(ip - .T_WIN + 1L):ip` ·
#    `.gdv > w0 & .gdv <= f` 로만 잘린다. ip 를 넘는 인덱스·음수 shift·lead 0건.
#  ▸ 구조 경계 2: c* · 잎 경계 · 경로 통계 · 진단이 전부 그 형성일의 창 **안에서만**
#    계산된다. 형성일 간 상태 이월 0건(루프 반복 독립). 전 표본 통계 0건.
#  ▸ 구조 경계 3: 자격(멤버십·유동성)은 f 시점 관측이고 유동성 창 종점은 f-1.
#  C1 : rolling only. 전 표본 mean/quantile/cov 0건.
#  C2 : same-day 순환참조 없음(f 종가까지 사용, 집행은 러너가 익 거래일).
#  C3 : 신호창 종점(f) < 보유월 시작.
#  C4 : 재무 패널 미사용(가격·거래대금만).
#  C5 : 오버레이 없음. c* 는 **과거 창의 횡단면 신호 구성 요소**이지 실현수익
#       스케일러가 아니다(C5/C9 의 소비 지점과 무관).
#  C6 : 유니버스 = 각 f 의 K200/KQ150 멤버십(PIT 시변). 최종 명부 주입 없음.
#       성능 사전필터(한 번이라도 편입)는 f 시점 자격 술어의 **상위집합**이라 동치.
#  C7 : shift(-N)/lead()/수동 미래 인덱싱 0건. shift 는 +1(과거 방향) 1회.
#  C10: 유동성 = f **직전** 20 거래일 평균 거래대금(frollmean 후 shift(1)).
#  C11: 외부 매크로 미사용. rf 는 **전월** 확정치 / **전월** 거래일수(당월 거래일수는
#       그 달이 끝나야 확정되므로 분모로 쓰면 월초에 모르는 값이 들어간다).
#  C13: NEGATE/FLIP 0건. 방향은 [A](A5)가 사전 선언한 오름차순 하나뿐.
#  C15: Factor DB parquet 직접 load 0건. rawdata 의 Market 열 미사용(KOSDAQ 0건 날조).
#
# =============================================================================
# §6. 산출
# =============================================================================
#   FACTORS(Date, Ticker, Score) — Score = (C - MDD) + R_II^sys. 클수록 롱.
#   러너 호출: portfolio_spec = list(construction="top_n_long", weighting="ew",
#              rebalance="monthly", n_long=25, n_max=25) · commission_paper = NULL
#   기간 절단(2005-01-01~)은 엔진이 아니라 러너가 적용한다.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(arrow)
  library(matrixStats)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.REQ <- c("Date", "Ticker", "Close", "Vol", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("[COMBO_1403_2007] RAWDATA 열 부족: %s",
               paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))

.tru <- function(x) !is.na(x) & (x != 0)     # 논리/0-1 혼재 방어
.t0  <- Sys.time()

# =============================================================================
# 0. 상수 — 출처가 셋뿐이다: [A] 명시값 · [B] 명시값 · 지시된 고정 축
# =============================================================================
# ▸ [A] 에서 온 것
.FORM_M   <- 6L            # (A4) "during 6 months of estimation period"
.W        <- c(1, 2, 1)    # (A3) Table 1 · CM = Cumulative return-MDD
# ▸ [B] 에서 온 것
.T_WIN    <- 1259L         # (B5) 1,259 daily returns — [B] 의 유일한 수치 파라미터
# ▸ 지시된 고정 축 (두 논문에 없다)
.LIQ      <- 2e8           # adv20(t-1) 하한 (KRW)
.LIQ_WIN  <- 20L
# ▸ 정의의 정의역 / 데이터 위생 — 성과를 보고 고른 값이 아니다
.MIN_LEAF <- 2L            # 잎이 성립하는 최소 관측([B] 단독구현 관례)
.MIN_STK  <- 2L            # joint 트리가 성립하는 최소 계열수([B] 표본은 5종)
.MIN_COV  <- 0.80          # **트리 적합 참여** 커버리지 하한([B] 단독구현 관례).
                           #   ★스코어 자격이 아니다 — 이력이 짧은 종목은 국면 경계
                           #     추정에 참여하지 않을 뿐, [A] 경로 점수는 받는다.
.RET_CAP  <- 1.0           # **트리 목적변수 전용** 아티팩트 제거. KRX 가격제한폭
                           #   +-30% 하에 한 세션 |수익|>100% 는 물리적으로 불가능.
                           #   비표준화 joint SSE(B3)는 단위 아티팩트 한 건에 전 분기를
                           #   빼앗긴다. ★[A] 경로 통계에는 캡을 걸지 않는다([A] 규약).

# =============================================================================
# 1. 시장 계열 mex = 시장 일간수익 - rf   (B4)
# =============================================================================
.bm <- NULL
if (exists("BM_DT") && is.data.table(BM_DT) && nrow(BM_DT)) {
  .b <- copy(BM_DT)
  if (!inherits(.b$Date, "Date")) .b[, Date := as.Date(Date)]
  setorder(.b, Date)
  if (!"BM_Ret" %in% names(.b) && "BM_Close" %in% names(.b))
    .b[, BM_Ret := BM_Close / shift(BM_Close, 1L) - 1]
  if ("BM_Ret" %in% names(.b))
    .bm <- unique(.b[is.finite(BM_Ret), .(Date, MKT = BM_Ret)], by = "Date")
  rm(.b)
}
if ((is.null(.bm) || !nrow(.bm)) && "BM_Ret" %in% names(RAWDATA))
  .bm <- unique(RAWDATA[is.finite(BM_Ret), .(Date, MKT = BM_Ret)], by = "Date")
if (is.null(.bm) || !nrow(.bm))
  stop("[COMBO_1403_2007] 시장 일간수익 계열 부재 — BM_DT(BM_Ret/BM_Close) 확인")
if (!inherits(.bm$Date, "Date")) .bm[, Date := as.Date(Date)]
setorder(.bm, Date)

# rf: 월간 KR 팩터 캐시의 RF 를 전월값/전월 거래일수로 일할 (부재·단위이상 = 0 폴백)
.rf_load <- function() {
  cand <- c(Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""),
            if (exists("PROJECT_ROOT")) as.character(PROJECT_ROOT)[1] else "")
  for (p in cand) {
    if (!nzchar(p)) next
    for (fn in c("kr_factor_returns_v2.parquet", "kr_factor_returns.parquet")) {
      fp <- file.path(p, ".cache", fn)
      if (!file.exists(fp)) next
      d <- tryCatch(as.data.table(read_parquet(fp)), error = function(e) NULL)
      if (is.null(d) || !all(c("Date", "RF") %in% names(d))) next
      d <- d[, .(Date = as.Date(Date), RF = as.numeric(RF))][is.finite(RF)]
      if (!nrow(d)) next
      md <- as.numeric(stats::median(d$RF))
      if (!is.finite(md) || md < 0 || md > 0.02) {   # 월간 무위험의 소수 표기 범위
        cat(sprintf("[COMBO_1403_2007] rf 캐시 단위 이상(median %.6f) — 폴백: %s\n", md, fn))
        next
      }
      return(d)
    }
  }
  NULL
}
.rf_monthly <- .rf_load()

# =============================================================================
# 2. 거래일 격자 = RAWDATA ∩ 시장계열 (mex 가 정의되는 날만 · 유령 거래일 배제)
# =============================================================================
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
.gdv <- as.Date(sort(intersect(unique(RAWDATA$Date), .bm$Date)), origin = "1970-01-01")
if (length(.gdv) < (.T_WIN + 200L))
  stop(sprintf("[COMBO_1403_2007] 거래일 격자 %d일 — 창 %d일 + 워밍업에 못 미침",
               length(.gdv), .T_WIN))

.GD <- data.table(Date = .gdv)
.GD[, ym := year(Date) * 12L + month(Date)]
.GD[, rf := 0]
if (!is.null(.rf_monthly)) {
  .rm <- copy(.rf_monthly)
  setorder(.rm, Date)
  .rm[, ym := year(Date) * 12L + month(Date)]
  .rm <- .rm[, .(RF = RF[.N]), by = ym]
  .nd <- .GD[, .(nd = as.numeric(.N)), by = ym]
  .rm <- merge(.rm, .nd, by = "ym", all.x = TRUE)
  setorder(.rm, ym)
  .rm[, `:=`(ym_p = shift(ym, 1L), RF_p = shift(RF, 1L), nd_p = shift(nd, 1L))]
  .rm[is.na(ym_p) | ym_p != (ym - 1L), c("RF_p", "nd_p") := list(NA_real_, NA_real_)]
  .rm[, rf_d := fifelse(is.finite(RF_p) & is.finite(nd_p) & nd_p > 0, RF_p / nd_p, 0)]
  .GD <- merge(.GD, .rm[, .(ym, rf_d)], by = "ym", all.x = TRUE)
  .GD[, rf := fifelse(is.finite(rf_d), rf_d, 0)][, rf_d := NULL]
  setorder(.GD, Date)
  cat(sprintf("[COMBO_1403_2007] rf 적용: 격자 %.1f%% (일평균 %.2fbp)\n",
              100 * mean(.GD$rf != 0), 1e4 * mean(.GD$rf)))
  rm(.rm, .nd)
} else {
  cat("[COMBO_1403_2007] rf 캐시 없음 — mex = 시장수익(rf=0). 논문 정의(excess)와의 차이이지 PIT 문제가 아니다\n")
}
.GD <- merge(.GD, .bm, by = "Date")
setorder(.GD, Date)
.GD[, mex := MKT - rf]

# =============================================================================
# 3. 가격 패널 (비파괴) · 유동성 adv20(t-1) · 월말 형성일 격자
# =============================================================================
# 성능 사전필터: 표본 기간 중 한 번이라도 K200/KQ150 이었던 종목만 싣는다.
#   f 시점 자격 술어의 상위집합이므로 자격 판정이 바뀌지 않는다(C6 동치 보존).
.tk <- unique(RAWDATA[.tru(K200) | .tru(KQ150), Ticker])
if (!length(.tk)) stop("[COMBO_1403_2007] K200/KQ150 멤버십 0건 — RAWDATA 확인")

.rd <- RAWDATA[Ticker %chin% .tk & Date %in% .gdv,
               .(Date, Ticker, Close, Vol, K200, KQ150)]
.rd <- .rd[is.finite(Close) & Close > 0]
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[COMBO_1403_2007] (Date,Ticker) 중복 %d행 — 첫 행만 남긴다\n", .ndup))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}
setorder(.rd, Ticker, Date)
# 거래대금(거래량 결측 = 그날 회전 0). adv20 후 shift(1) → 종점 t-1 (C10)
.rd[, TV := Close * fifelse(is.finite(as.numeric(Vol)), as.numeric(Vol), 0)]
.rd[, ADV20_L1 := shift(frollmean(TV, .LIQ_WIN, align = "right"), 1L), by = Ticker]

.me <- .GD[, .(f = max(Date)), by = ym][order(f), f]     # 월말 거래일
setkey(.rd, Date)

cat(sprintf("[COMBO_1403_2007] 패널 %s행 · %d종 · %s~%s · 월말 %d개\n",
            format(nrow(.rd), big.mark = ","), uniqueN(.rd$Ticker),
            as.character(min(.gdv)), as.character(max(.gdv)), length(.me)))

# =============================================================================
# 4. 일간수익 wide 행렬 — **트리 목적변수 전용**(캡 적용)
#    ★[A] 경로 통계는 이 행렬을 쓰지 않는다(.rd 의 미처리 종가에서 직접 낸다).
# =============================================================================
.CW <- dcast(.rd[, .(Date, Ticker, Close)], Date ~ Ticker, value.var = "Close")
setorder(.CW, Date)
.cdates <- .CW$Date
.PXM    <- as.matrix(.CW[, -1L, with = FALSE])
.tick   <- colnames(.PXM)
rm(.CW); gc(verbose = FALSE)

.nr  <- nrow(.PXM)
RET  <- .PXM[-1L, , drop = FALSE] / .PXM[-.nr, , drop = FALSE] - 1
.rdt <- .cdates[-1L]                                   # RET 각 행의 날짜
RET[!is.finite(RET)] <- NA_real_
# which() 로 감싼다 — 논리 첨자에 NA 가 섞이면 대입이 에러다(위에서 NA 를 채운 뒤라 반드시 섞인다)
RET[which(abs(RET) > .RET_CAP)] <- NA_real_
rm(.PXM); gc(verbose = FALSE)
cat(sprintf("[COMBO_1403_2007] 트리 목적변수 행렬 %d일 x %d종 (%s~%s) · 결측 %.1f%%\n",
            nrow(RET), ncol(RET), as.character(min(.rdt)), as.character(max(.rdt)),
            100 * mean(is.na(RET))))

.MX <- .GD[Date %in% .rdt, .(Date, mex)]
setkey(.MX, Date)
.mexv <- .MX[.(.rdt), mex]
if (anyNA(.mexv)) stop("[COMBO_1403_2007] mex 정렬 실패 — 격자/시장계열 불일치")

# =============================================================================
# 5. [A] 경로 분해 + 체계 성분 (창 내부 통계만 · 미처리 로그가격 경로)
#    cl   = 형성창 내 그 종목의 거래일 종가(Date 오름차순, 미처리)
#    advf = 같은 날짜 벡터의 ADV 지시자(1/0). 증분 lr[j-1] 은 **끝나는 날** j 의 잎에
#           귀속된다(거래정지를 건너뛴 수익은 재개일의 국면으로 들어간다).
# =============================================================================
.leg_stats <- function(cl, advf) {
  n <- length(cl)
  if (n < 2L)                                    # 로그가격 경로가 성립하는 정의역 밖
    return(list(C = NA_real_, MDD = NA_real_, RI = NA_real_, RII = NA_real_,
                RIII = NA_real_, RII_sys = NA_real_, nobs = n))
  lg   <- log(cl)
  lr   <- lg[-1L] - lg[-n]                       # 미처리 증분 ([A] 규약 — 캡·윈저 0)
  path <- c(0, cumsum(lr))                       # = log P - log P_0 · path[1] = 0
  dd   <- path - cummax(path)                    # <= 0 (포함형 cummax: 신고점에서 0)
  ts_i <- which.min(dd)                          # trough (동값이면 최초)
  tp_i <- which.max(path[seq_len(ts_i)])         # trough 이전(포함) peak
  # R_II 를 구성하는 증분 = 인덱스 (tp_i, ts_i] 에서 끝나는 것 = lr[tp_i:(ts_i-1)]
  rii_sys <- if (ts_i > tp_i)
    sum(lr[tp_i:(ts_i - 1L)] * advf[(tp_i + 1L):ts_i]) else 0
  list(C = path[n], MDD = -dd[ts_i], RI = path[tp_i],
       RII = path[ts_i] - path[tp_i], RIII = path[n] - path[ts_i],
       RII_sys = rii_sys, nobs = n)
}

# =============================================================================
# 6. 형성일 루프 — [B] joint depth=1 트리로 c* → ADV → [A] 분해 → Score
#    [B] 목적함수 전개 (B2 의 SSE 최소화와 동치):
#      SSE(k) = sum_i [ TSS_i - CX_i(k)^2/CM_i(k) - (SX_i-CX_i(k))^2/(SM_i-CM_i(k)) ]
#      TSS_i 는 k 에 무관 → SSE 최소화 = 아래 gain 최대화.
#      종목별 표준화는 하지 않는다 — [B] 의 joint 트리가 그렇고 'dominant stock'
#      이 그 성질이다(B3).
# =============================================================================
.OUT  <- vector("list", length(.me))
.LOG  <- vector("list", length(.me))
.skip_warm <- 0L      # 창(6개월 또는 1259일)이 아직 안 잡히는 워밍업 달
.skip_def  <- 0L      # 창은 잡히나 자격/정의역이 비는 달

for (k in seq_along(.me)) {
  if (k <= .FORM_M) { .skip_warm <- .skip_warm + 1L; next }
  f  <- .me[k]
  ip <- match(f, .rdt)
  if (is.na(ip))        { .skip_def  <- .skip_def  + 1L; next }  # 격자에 없는 월말(데이터 결손)
  if (ip < .T_WIN)      { .skip_warm <- .skip_warm + 1L; next }  # [B] 창이 아직 안 잡힘

  w0     <- .me[k - .FORM_M]
  wdates <- .rdt[.rdt > w0 & .rdt <= f]                  # [A] 6개월 창 (종점 = f)
  if (length(wdates) < 2L) { .skip_def <- .skip_def + 1L; next }

  # ---- 자격: f 의 멤버십 + adv20(t-1) 하한 (C6 · C10) ----------------------
  rf_ <- .rd[.(f), .(Ticker, K200, KQ150, ADV20_L1), nomatch = 0L]
  elig <- rf_[(.tru(K200) | .tru(KQ150)) &
                is.finite(ADV20_L1) & ADV20_L1 >= .LIQ, Ticker]
  if (!length(elig)) { .skip_def <- .skip_def + 1L; next }

  # ---- [B] joint depth=1 트리 (창: f 에서 끝나는 1,259 거래일) --------------
  twi   <- (ip - .T_WIN + 1L):ip
  mexw  <- .mexv[twi]
  cand  <- intersect(elig, .tick)
  cstar <- NA_real_; adv_share_tree <- NA_real_
  mu_major <- NULL; nm_fit <- NULL; dom_tk <- NA_character_
  if (length(cand) >= .MIN_STK) {
    Y     <- RET[twi, cand, drop = FALSE]
    cov_n <- colSums(!is.na(Y))
    keepc <- (cov_n >= as.integer(.MIN_COV * .T_WIN)) & !is.na(Y[.T_WIN, ])
    if (sum(keepc) >= .MIN_STK) {
      Y   <- Y[, keepc, drop = FALSE]
      nmk <- colnames(Y)
      o   <- order(mexw)                                  # 동값은 같은 쪽으로
      ms  <- mexw[o]
      Ys  <- Y[o, , drop = FALSE]
      Msk <- matrix(as.numeric(!is.na(Ys)), nrow = nrow(Ys))
      Xs  <- Ys; Xs[is.na(Xs)] <- 0
      CXm <- colCumsums(Xs); CMm <- colCumsums(Msk)
      Tn  <- nrow(Xs); Mn <- ncol(Xs)
      SX  <- CXm[Tn, ]; SM <- CMm[Tn, ]
      RXm <- matrix(SX, Tn, Mn, byrow = TRUE) - CXm
      RMm <- matrix(SM, Tn, Mn, byrow = TRUE) - CMm
      LTm <- CXm^2  / CMm
      RTm <- RXm^2 / RMm
      LTm[!is.finite(LTm)] <- 0                           # 잎에 관측 없는 종목 = 기여 0
      RTm[!is.finite(RTm)] <- 0
      gn  <- rowSums(LTm + RTm)
      rm(RXm, RMm, LTm, RTm)
      okv <- c(ms[-Tn] < ms[-1L], FALSE)                  # 값이 실제로 갈리는 자리만
      okv[seq_len(.MIN_LEAF - 1L)] <- FALSE
      okv[(Tn - .MIN_LEAF + 1L):Tn] <- FALSE
      if (any(okv)) {
        gn[!okv] <- -Inf
        ks    <- which.max(gn)
        cstar <- (ms[ks] + ms[ks + 1L]) / 2               # sklearn 규약: 인접 중점
        adv_share_tree <- ks / Tn                         # 악화잎(mex <= c*) 비중
        # [B] 단독구현의 스코어(다수-잎 예측 일간수익) = F2 대조군 전용
        lmaj <- ks > (Tn - ks)
        numv <- if (lmaj) CXm[ks, ] else (SX - CXm[ks, ])
        denv <- if (lmaj) CMm[ks, ] else (SM - CMm[ks, ])
        gdv2 <- is.finite(numv / denv) & denv >= .MIN_LEAF
        if (any(gdv2)) { mu_major <- (numv / denv)[gdv2]; nm_fit <- nmk[gdv2] }
        tss    <- colSums(Xs^2) - SX^2 / pmax(SM, 1)      # 비표준화 목적함수의 지배 종목
        dom_tk <- nmk[which.max(tss)]
      }
      rm(CXm, CMm, Xs, Ys, Msk, Y)
    }
  }

  # ---- ADV 라벨 (트리 실패 시 공집합 → Score = CM 그 자체. 월 결번 아님) -----
  advd <- if (is.finite(cstar)) wdates[.mexv[match(wdates, .rdt)] <= cstar] else wdates[0L]

  # ---- [A] 경로 분해 + 체계 성분 -------------------------------------------
  wd <- .rd[.(wdates), .(Date, Ticker, Close), nomatch = 0L][Ticker %chin% elig]
  if (!nrow(wd)) { .skip_def <- .skip_def + 1L; next }
  setorder(wd, Ticker, Date)                              # 그룹 내 Date 오름차순 보장
  wd[, advf := as.numeric(Date %in% advd)]
  st <- wd[, .leg_stats(Close, advf), by = Ticker]
  st[, cm    := .W[1] * RI + .W[2] * RII + .W[3] * RIII]  # = C - MDD  ([A] Table 1 CM)
  st[, score := cm + RII_sys]                             # + 체계 성분 1단위 ([A] 증분 문법)
  st <- st[is.finite(score) & is.finite(cm)]
  if (!nrow(st)) { .skip_def <- .skip_def + 1L; next }

  .OUT[[k]] <- data.table(Date = f, Ticker = st$Ticker, Score = st$score)

  # ---- 진단 (전부 창 안 통계 — 미래참조 0) ----------------------------------
  n25   <- min(25L, nrow(st))
  t_sc  <- st$Ticker[order(-st$score, st$Ticker)][seq_len(n25)]
  t_cm  <- st$Ticker[order(-st$cm,    st$Ticker)][seq_len(n25)]
  rho_cm <- if (nrow(st) >= 5L)
    suppressWarnings(stats::cor(st$score, st$cm, method = "spearman")) else NA_real_
  rho_b <- NA_real_
  if (!is.null(mu_major)) {
    mm <- data.table(Ticker = nm_fit, mu = as.numeric(mu_major))
    jj <- merge(st[, .(Ticker, score)], mm, by = "Ticker")
    if (nrow(jj) >= 5L)
      rho_b <- suppressWarnings(stats::cor(jj$score, jj$mu, method = "spearman"))
  }
  dws <- st[RII < -1e-8, RII_sys / RII]                   # 낙폭의 체계 성분 비중
  .LOG[[k]] <- data.table(
    f = f, N = nrow(st), n_win = length(wdates),
    tree_ok = is.finite(cstar), split_bp = 1e4 * cstar,
    adv_share_tree = adv_share_tree,
    adv_share_win  = length(advd) / length(wdates),
    sys_share = if (length(dws)) as.numeric(stats::median(dws, na.rm = TRUE)) else NA_real_,
    rho_cm = as.numeric(rho_cm), rho_b = as.numeric(rho_b),
    ovl25 = length(intersect(t_sc, t_cm)) / n25,
    mdd_med = as.numeric(stats::median(st$MDD)),
    C_med   = as.numeric(stats::median(st$C)),
    dom = dom_tk)
}

FACTORS <- rbindlist(Filter(Negate(is.null), .OUT), use.names = TRUE)
if (!nrow(FACTORS))
  stop("[COMBO_1403_2007] FACTORS 0행 — 창 길이/유니버스/자격 확인")
setorder(FACTORS, Date, -Score)

# =============================================================================
# 7. 보고 — 구성 요약 + 엔진이 스스로 인쇄하는 반증 5종
#    (성과 수치 선언 아님. 등급·성과는 계약이 낸다.)
# =============================================================================
LG <- rbindlist(Filter(Negate(is.null), .LOG), use.names = TRUE)
.med <- function(x) { x <- as.numeric(x); x <- x[is.finite(x)]
                      if (length(x)) stats::median(x) else NA_real_ }

# F5 — ★세기 전에 범위를 선언한다: 분모는 **측정 구간**(러너가 적용하는 2005-01-01~)이다.
#   [B] 창 1,259일이 아직 안 잡히는 워밍업 월말은 결번이 아니라 정의역 밖이므로 분모가 아니다.
#   (엔진은 기간을 선택하지 않는다 — FACTORS 는 가용 전 구간을 낸다. 이건 진단의 범위 선언일 뿐이다.)
.RANGE0 <- as.Date("2005-01-01")
.mpos   <- match(.me, .rdt)
.cand_f <- .me[seq_along(.me) > .FORM_M & !is.na(.mpos) & .mpos >= .T_WIN & .me >= .RANGE0]
.got_f  <- LG$f[LG$f >= .RANGE0]
.cand_k <- length(.cand_f)
.miss   <- !(.cand_f %in% .got_f)
.rl     <- rle(.miss)
.gapmax <- if (any(.miss)) max(.rl$lengths[.rl$values]) else 0L
.f1 <- .med(LG$ovl25); .f2 <- .med(LG$rho_b); .f3 <- .med(LG$adv_share_tree)
.f4a <- .med(LG$sys_share); .f4b <- .med(LG$rho_cm)

cat(sprintf(paste0(
  "[COMBO_1403_2007] combination: Score = (C - MDD) + R_II^sys\n",
  "  [A] CM(1,2,1) 6개월 경로분해  x  [B] joint depth=1 tree on mex (창 %d거래일)\n",
  "  형성 %d개월(%s~%s · 워밍업 skip %d · 정의역 skip %d) · FACTORS %s행 · 횡단면 중앙 %d종\n",
  "  트리 적합 성공 %d/%d개월 · 임계값 중앙 %.1fbp · 악화잎 비중(트리창) 중앙 %.3f\n",
  "  형성창 악화일 비중 중앙 %.3f · 창내 MDD 중앙 %.1f%% · C 중앙 %.1f%% · 지배종목 최빈 %s\n"),
  .T_WIN,
  nrow(LG), as.character(min(LG$f)), as.character(max(LG$f)), .skip_warm, .skip_def,
  format(nrow(FACTORS), big.mark = ","), as.integer(.med(LG$N)),
  sum(LG$tree_ok), nrow(LG), .med(LG$split_bp), .f3,
  .med(LG$adv_share_win), 100 * .med(LG$mdd_med), 100 * .med(LG$C_med),
  { .d <- LG[!is.na(dom), .N, by = dom][order(-N)]
    if (nrow(.d)) sprintf("%s(%d개월)", .d$dom[1], .d$N[1]) else "n/a" }))

cat(sprintf(paste0(
  "[COMBO_1403_2007] 반증 (창 안 통계 · 미래참조 0):\n",
  "  F1 [A] 재라벨 아님 : top-25 겹침(vs CM 단독) 중앙 %.3f   → %s (기준 < 0.80)\n",
  "  F2 [B] 재라벨 아님 : rho(Score, [B] 다수잎) 중앙 %.3f    → %s (기준 < 0.95)\n",
  "  F3 [B] 꼬리 주장 전이: 악화잎 비중 중앙 %.3f            → %s ([0.40,0.60] 밖이라야 꼬리)\n",
  "     ★설계는 F3 결과에 의존하지 않는다 — 꼬리면 Score -> CM, 중앙이면 -> C+2*R_II.\n",
  "       어느 쪽도 퇴화가 아니고, 실패하면 그건 [B] 의 KR 전이 실패이지 이 판의 무효가 아니다.\n",
  "  F4 추가 다리 하중  : 낙폭의 체계 성분 비중 중앙 %.3f · rho(Score, CM) 중앙 %.4f → %s (기준 rho < 0.99)\n",
  "  F5 월 결번 0       : [범위 = 측정구간 2005-01-01~] 후보 %d · 산출 %d · 최대 연속 결번 %d → %s\n",
  "  ★러너 호출: portfolio_spec = list(construction=\"top_n_long\", weighting=\"ew\",\n",
  "                                    rebalance=\"monthly\", n_long=25, n_max=25)\n",
  "              commission_paper = NULL ([A]·[B] 둘 다 비용 무명시) · %.1f분\n"),
  .f1,  if (is.finite(.f1)  && .f1  < 0.80) "PASS" else "FAIL",
  .f2,  if (is.finite(.f2)  && .f2  < 0.95) "PASS" else "FAIL",
  .f3,  if (is.finite(.f3)  && (.f3 < 0.40 || .f3 > 0.60)) "TAIL" else "MID",
  .f4a, .f4b, if (is.finite(.f4b) && .f4b < 0.99) "PASS" else "FAIL",
  .cand_k, length(.got_f), .gapmax,
  if (length(.got_f) == .cand_k && .gapmax == 0L) "PASS" else "FAIL",
  as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
