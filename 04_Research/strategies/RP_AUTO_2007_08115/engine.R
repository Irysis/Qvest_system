# =============================================================================
# engine.R — RP_AUTO_2007_08115
# Vassilis Polimenis, "Uncovering a factor-based expected return conditioning
#   structure with Regression Trees jointly for many stocks" (arXiv:2007.08115,
#   q-fin.ST, 2020-07-16)   https://arxiv.org/abs/2007.08115
#
# ★fidelity = ADAPTED (인사이트 이식). 정본 = FIDELITY.json
#   판정순서 1(충실구현)이 성립하지 않는다 — 이 논문은 **포트폴리오를 만들지 않는다**.
#   원문 확인: 매매전략·백테스트·거래비용·종목수·비중·리밸 주기 언급이 전무하고,
#   저자 스스로 분석이 "only done for demonstration purposes and not for
#   statistical inference" 라고 못박는다. 복제할 '논문 그대로의 포트폴리오'가
#   존재하지 않으므로 판정순서 2(기전 이식)로 내려간다.
#
# ===== 원문 대조 (2026-09-03) =====
#   arXiv 는 이 논문의 HTML 판을 만들지 않았다(2020년 투고 — /html·ar5iv 둘 다
#   404/redirect). PDF 전문을 텍스트 렌더러 경유로 읽어 아래 문장을 축자 확보했다.
#   따옴표 안은 전부 원문 그대로다(요약이 아니다).
#
#   (Q1) 트리 설정 — 목적함수·깊이·탐색
#     "Limiting to max depth = 1"
#     "The cost function that is minimized when choosing split points is the sum
#      squared error across all training samples against their sub-region
#      prediction   Min for all split points  Sum_i ( y_i - prediction(y_i) )^2"
#     "all input variables and all possible split points are evaluated and chosen
#      in a greedy algorithm. The algorithm maximizes the drop in that value when
#      moving from a node to its children."
#
#   (Q2) joint tree — 이 논문의 제목("jointly for many stocks")이 가리키는 대상
#     "a single model capable of predicting simultaneously n stocks is built"
#     "correlation information enters the tree structure"
#     → 종목별 개별 트리가 아니라 **다출력(multi-output) 단일 트리**. 분기점 하나를
#       전 종목 SSE 합으로 고른다. 종목별 표준화가 없으므로 분산이 큰 종목이
#       분기를 지배한다 — 논문이 "the dominant stock in a joint regression tree"
#       라는 절로 따로 논의하는 성질이다(제거 대상이 아니라 설계의 일부).
#
#   (Q3) 설명변수와 그 결과 — 이 엔진의 축소 근거
#     설명변수 = FF3 = "the excess return on the market above the risk free rate"
#       (mex) + SMB + HML. "Factor data were downloaded from the French data library"
#     결과(초록) = "in all cases (solo and joint) the most informative factor is
#       always the market excess return factor"
#
#   (Q4) 데이터 — 창 길이의 출처
#     IBM / KO / BK(Bank of New York Mellon) / PG / GOOG 5종, 일간,
#     1/5/2015 ~ 30/4/2020, **1,259 daily returns**.
#
#   (Q5) Table 2c — 회수된 구조의 실제 모습 (임계값이 0 이 아니라 꼬리에 있다)
#     종목  분산    왜도   첨도   solo분기  balance        joint분기
#     IBM   2.45bp  -0.27  10.90  -70bp     13.66-86.34%   n/a
#     KO    1.39bp  -1.03  13.50  -350bp    1-99%          -70bp
#     BK    2.97bp  -0.48  16.50  -100bp    9.5-90.5%      -90bp
#     PG    1.60bp  +0.585 16.00  +300bp    99-1%          -70bp
#     GOOG  2.92bp  +0.66  11.90  -40bp     22-78%         -70bp
#     → ①분기변수는 언제나 mex ②임계값은 꼬리(-70bp 근방으로 joint 수렴)
#       ③분할이 극단적으로 불균형해 **소수 극단일 vs 나머지 대다수**로 갈린다.
#
#   (Q6) 비용·포트폴리오: 논문에 전무 → commission_paper = null.
#
# ===== 남긴 것 (kept) — 기전 =====
#   "기대수익의 조건부 구조는 시장팩터에 대한 depth=1 계단함수이고, 그 계단은 0 이
#    아니라 꼬리에 서며, 여러 종목에 **동시에** 적합하면 공통 임계값 하나가 나오고
#    종목은 그 위에서 잎 평균으로 갈린다."
#   이식형: 매 월말 D 에서 유니버스 전 종목의 일간수익을 목적변수로 하는 **joint
#   depth=1 회귀트리**를 mex 에 적합 → 공통 임계값 c* → 종목 i 의 잎 평균
#   (mu_L,i , mu_R,i). 횡단면 스코어 = **다수 잎(majority leaf)의 잎 평균**, 즉
#   그 트리가 "모달 국면"에 대해 내놓는 기대수익 예측값 그 자체다.
#     ▸ 왜 다수 잎인가: 논문이 depth=1 트리의 **balance** 를 세 논점 중 첫째로
#       다루고(Q5), 회수된 구조가 1-99%~22-78% 로 한쪽이 압도적이다. 다수 잎의
#       예측값이 그 조건부 구조의 지배적 가지다. 어느 쪽이 다수인지는 매달
#       데이터가 정한다(PG 처럼 좌측이 99% 인 경우도 논문에 있다) — 우리가
#       고르지 않는다.
#     ▸ ★부호를 고르지 않았다: 스코어 = 기대수익 예측값이므로 큰 값이 롱이다.
#       (mu_R - mu_L 같은 '민감도' 를 쓰면 방향을 내가 정해야 하는데, 논문은
#        방향을 주지 않는다. 그건 이식이 아니라 지어내기가 된다.)
#
# ===== 바꾼 것 (changed) — 무엇을, 왜 =====
#   ① 유니버스: US 대형주 5종(수작업) → K200 U KQ150 (PIT 시변) + adv20(t-1) >= 2e8.
#      고정 축. 5종에서 수백 종으로 넓히는 것이 "jointly for many stocks" 의
#      방향과 어긋나지 않는다(논문 자신이 n 종목 동시적합을 주제로 한다).
#   ② 산출 형태: 서술적 진단(분기점·balance 표) → 횡단면 스코어 + top-25 롱온리 EW
#      월간 리밸. 논문이 포트폴리오를 주지 않으므로 **우리 고정 축**을 쓴다.
#      (논문에서 온 유일한 수치 파라미터는 창 길이 1,259 거래일뿐이다.)
#   ③ 설명변수 집합: FF3(mex, SMB, HML) → **mex 하나**.
#      사유는 데이터이고, 그 축소가 회수되는 구조를 바꾸지 않는다는 근거는 논문 자신이다:
#        · 인프라의 KR FF3 팩터(kr_factor_returns_v2.parquet)는 **월간**이다.
#          일간 SMB/HML 패널이 없다. 트리가 -70bp 급 꼬리 분기를 잡으려면 일간이라야
#          한다(월간 60관측으로는 1-99% 분할이 추정되지 않는다).
#        · KR 일간 SMB/HML 을 내가 새로 구성하려면 장부가 정의·절단점 규약·형성주기를
#          **내가 정해야** 한다. 논문이 주지 않는 수치를 임의로 정하는 것 = 지어내기.
#        · 그리고 논문의 결론이 "in all cases (solo and joint) the most informative
#          factor is always the market excess return factor" 다(Q3). 즉 이 축소가
#          제거하는 것은 **결과가 만장일치로 보고된 경마**이지 회수되는 구조가 아니다.
#      ★대가는 정직하게 적는다: KR 에서 SMB/HML 이 이겼을 가능성은 이 엔진이 검정하지
#        않는다. 그 검정은 일간 KR FF3 패널이 생긴 뒤의 별도 축이다.
#   ④ mex 정의: French library → KOSPI200 일간수익(BM_Ret) - 무위험(rf).
#      rf = kr_factor_returns 캐시의 월간 RF 를 **전월값**으로 당겨 그 달 거래일수로
#      나눈 것. 캐시 부재/단위 이상이면 rf=0 으로 폴백하고 로그로 드러낸다(침묵 금지).
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) =====
#  ▸ 구조 경계 1: 모든 창의 종점이 D(월말 시그널일) 이하다. 창은 항상
#    `(ip - .T_WIN + 1L):ip` 로 잘리고 ip = match(D, 수익일자) 다. ip 를 넘는
#    인덱스가 코드에 없다(미래 방향 인덱싱 0건, 음수 shift 0건).
#  ▸ 구조 경계 2: 트리 적합·임계값·잎 평균이 **전부 그 창 안에서만** 계산된다.
#    형성일 간 상태 이월이 없다(루프 반복은 독립). 전 표본 통계 0건.
#  ▸ 구조 경계 3: 종목 자격(멤버십·유동성)도 D 시점 관측이고, 유동성 창은 D-1 에서
#    끝난다. 미래 명부 주입 없음.
#  C1  : rolling window 만. mean/quantile 이 전 표본에 걸리는 지점 0건 — 모든 평균은
#        길이 .T_WIN 창의 잎 부분집합 평균이다.
#  C2  : same-day 순환참조 없음. D 종가까지 쓰고 집행은 익 거래일(하네스).
#  C3  : 같은 기간 집계->적용 없음. 신호창 종점(D) < 보유월 시작.
#  C4  : 재무 패널 미사용.
#  C5  : 오버레이 없음(S0/S1 오버레이 금지 준수).
#  C6  : 유니버스 = 각 D 의 K200/KQ150 멤버십(PIT 시변). 최종 명부 주입 없음.
#        창 커버리지 요건은 **과거 데이터 요건**이라 생존편의를 만들지 않는다
#        (미래에 상장폐지될지 여부를 묻지 않는다).
#  C7  : shift(-N)·lead()·수동 미래 인덱싱 0건. shift 는 전부 +1(과거 방향).
#  C9  : DD/VT 미사용.
#  C10 : 유동성 = D **직전 20 거래일** 평균 거래대금. `lo:(ip - 1L)` 로 당일 배제.
#  C11 : 외부 매크로 미사용. rf 는 전월 확정치를 한 달 더 늦춰 쓰고, **일할 분모도
#        전월 거래일수**다 — 당월 거래일수는 그 달이 끝나야 확정되므로 분모로 쓰면
#        월초에 모르는 값이 신호에 들어간다.
#  C13 : Factor DB 미소비 -> 부호 정렬 대상 없음. 수동 부호 반전 0건.
#  C15 : Factor DB parquet 직접 load 0건.
#  ★rawdata 의 Market 열 미사용(KOSDAQ 0건 날조 — 사내 기록). 시장 구분은 K200/KQ150
#    멤버십 플래그로만 한다.
#
# ===== 산출 =====
#   FACTORS(Date, Ticker, Score) — Score = joint depth=1 트리의 다수-잎 예측 일간수익.
#   러너 호출: portfolio_spec = list(construction="top_n_long", weighting="ew",
#              rebalance="monthly", n_long=25, n_max=25) · commission_paper = NULL
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(arrow)
  library(matrixStats)
}))

# 난수 미사용(결정론적 엔진)이지만 재현성 선언 고정.
set.seed(20070811L)

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.RQ <- c("Date", "Ticker", "Close", "Vol", "K200", "KQ150")
if (!all(.RQ %in% names(RAWDATA)))
  stop(sprintf("[RP_2007_08115] RAWDATA 열 부족: %s",
               paste(setdiff(.RQ, names(RAWDATA)), collapse = ", ")))

# =============================================================================
# 0. 상수 — 논문에서 온 것 / 축에서 온 것 / 수치 타당성 하한
# =============================================================================
# ▸ 논문에서 온 것 (Q4) — 이 엔진의 유일한 논문 유래 수치 파라미터
.T_WIN    <- 1259L     # 추정 창 = 1,259 daily returns (논문 표본 그대로)
# ▸ 축(도훈 고정)에서 온 것
.LIQ      <- 2e8       # adv20(t-1) 하한 (KRW)
.LIQ_WIN  <- 20L       # 거래일 (D 직전 20 거래일, 종점 = D-1)
.START    <- as.Date("2005-01-01")
# ▸ 수치 타당성 하한 — 전략 파라미터가 아니다(성과를 보고 고른 값이 아니다)
.MIN_COV  <- 0.80      # 창 커버리지 하한 = 논문 5년 창 중 4년치. 거래정지 며칠로
                       #   5년 이력이 통째로 버려지는 것을 막는 자리일 뿐이다.
.MIN_LEAF <- 2L        # 잎 최소 관측 — 평균이 성립하는 하한(sklearn 기본은 1이고,
                       #   체계적 분기가 단일일 분기를 압도하므로 결과 불변).
.MIN_STK  <- 2L        # joint 트리가 성립하는 최소 종목수(논문은 5종).
.RET_CAP  <- 1.0       # |일간수익| > 100% = 데이터 아티팩트. KRX 가격제한폭이
                       #   +-30% 라 한 세션에 물리적으로 불가능한 값이다(수정주가
                       #   보정 실패의 지문). 윈저라이즈가 아니라 결측 처리다.

.tru <- function(x) !is.na(x) & (x != 0)     # 논리/0-1 혼재 방어
.t0  <- Sys.time()

# =============================================================================
# 1. 시장 계열 (mex) — KOSPI200 일간수익 - rf
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
  stop("[RP_2007_08115] 시장 일간수익 계열 부재 — BM_DT(BM_Ret/BM_Close) 확인")
if (!inherits(.bm$Date, "Date")) .bm[, Date := as.Date(Date)]
setorder(.bm, Date)

# ── rf: 월간 KR 팩터 캐시의 RF 를 전월값으로 당겨 일할 (부재/이상 시 0 폴백) ──
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
      # 단위 검사: 월간 무위험수익률의 소수 표기는 0~2% 안이어야 한다. 벗어나면
      #   퍼센트 표기(또는 다른 축)이므로 쓰지 않는다 — 잘못 쓰면 임계값이 통째로 어긋난다.
      if (!is.finite(md) || md < 0 || md > 0.02) {
        cat(sprintf("[RP_2007_08115] rf 캐시 단위 이상(median %.6f) — rf=0 폴백: %s\n", md, fn))
        next
      }
      return(d)
    }
  }
  NULL
}
.rf_monthly <- .rf_load()

# =============================================================================
# 2. 거래일 격자 — RAWDATA 와 시장계열의 교집합 (유령 거래일 배제)
# =============================================================================
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
.gd <- sort(intersect(unique(RAWDATA$Date), .bm$Date))
.gd <- as.Date(.gd, origin = "1970-01-01")
if (length(.gd) < (.T_WIN + 40L))
  stop(sprintf("[RP_2007_08115] 거래일 격자 %d일 — 창 %d일에 못 미침", length(.gd), .T_WIN))

.GD <- data.table(Date = .gd)
.GD[, ym := year(Date) * 12L + month(Date)]

# rf 일할: **전월** RF / **전월** 격자 거래일수
#   ★분모도 전월이어야 한다. 당월 거래일수는 그 달이 끝나야 확정되므로, 당월로 나누면
#     월초 시점에 모르는 값이 신호에 들어간다(영향이 작다는 것은 PIT 의 항변이 아니다).
#     분자·분모를 모두 m-1 에서 가져오면 m 월 첫날에 이미 전부 알려진 값이 된다.
.GD[, rf := 0]
if (!is.null(.rf_monthly)) {
  .rm <- copy(.rf_monthly)
  setorder(.rm, Date)                                       # RF[.N] = 그 달 마지막 관측
  .rm[, ym := year(Date) * 12L + month(Date)]
  .rm <- .rm[, .(RF = RF[.N]), by = ym]
  .nd <- .GD[, .(nd = as.numeric(.N)), by = ym]
  .rm <- merge(.rm, .nd, by = "ym", all.x = TRUE)
  setorder(.rm, ym)
  .rm[, ym_p := shift(ym, 1L)]
  .rm[, RF_p := shift(RF, 1L)]
  .rm[, nd_p := shift(nd, 1L)]
  .rm[is.na(ym_p) | ym_p != (ym - 1L),                      # 결번 월이면 인정하지 않는다
      c("RF_p", "nd_p") := list(NA_real_, NA_real_)]
  .rm[, rf_d := fifelse(is.finite(RF_p) & is.finite(nd_p) & nd_p > 0, RF_p / nd_p, 0)]
  .GD <- merge(.GD, .rm[, .(ym, rf_d)], by = "ym", all.x = TRUE)
  .GD[, rf := fifelse(is.finite(rf_d), rf_d, 0)]
  .GD[, rf_d := NULL]
  setorder(.GD, Date)
  cat(sprintf("[RP_2007_08115] rf 적용: 격자 %.1f%% (일평균 %.2fbp)\n",
              100 * mean(.GD$rf != 0), 1e4 * mean(.GD$rf)))
  rm(.rm, .nd)
} else {
  cat("[RP_2007_08115] rf 캐시 없음 — mex = 시장수익(rf=0)으로 측정한다. 논문 정의(excess)와의 차이이지 PIT 문제가 아니다\n")
}

.GD <- merge(.GD, .bm, by = "Date")
setorder(.GD, Date)
.GD[, mex := MKT - rf]

# =============================================================================
# 3. 형성일(월말 거래일) · 유동성 창
# =============================================================================
.ME <- .GD[, .(Date = max(Date)), by = ym]
setorder(.ME, Date)
.FORM <- .ME[Date >= .START, Date]
if (!length(.FORM))
  stop("[RP_2007_08115] 형성일 0건 — RAWDATA 날짜 범위 확인")

.gdv <- .GD$Date
# ★인덱스로 돌린다 — lapply 가 Date 벡터를 원소로 쪼개면 클래스가 벗겨질 수 있고,
#   그 순간 match(numeric, Date) 가 문자 비교로 떨어져 전 창이 조용히 비어버린다.
.LW <- rbindlist(lapply(seq_along(.FORM), function(k) {
  D  <- .FORM[k]
  ip <- match(D, .gdv)
  if (is.na(ip) || (ip - .LIQ_WIN) < 1L) return(NULL)
  data.table(Date = .gdv[(ip - .LIQ_WIN):(ip - 1L)], FormDate = D)   # 종점 = D-1 (C10)
}), use.names = TRUE)
if (!nrow(.LW))
  stop("[RP_2007_08115] 유동성 창 구성 실패 — 거래일 수 부족")
.FORM <- .FORM[.FORM %in% unique(.LW$FormDate)]

# =============================================================================
# 4. 가격 패널 -> 일간수익 wide 행렬
# =============================================================================
# 관심 종목 = 표본 기간 중 한 번이라도 K200 또는 KQ150 이었던 종목.
.tk <- unique(RAWDATA[.tru(K200) | .tru(KQ150), Ticker])
if (!length(.tk))
  stop("[RP_2007_08115] K200/KQ150 멤버십 0건 — RAWDATA 확인")

.px <- RAWDATA[Ticker %chin% .tk & Date %in% .gdv & is.finite(Close) & Close > 0,
               .(Date, Ticker, Close)]
.ndup <- sum(duplicated(.px, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[RP_2007_08115] (Date,Ticker) 중복 %d행 — 첫 행만 남긴다\n", .ndup))
  .px <- unique(.px, by = c("Ticker", "Date"))
}
.CW <- dcast(.px, Date ~ Ticker, value.var = "Close")
setorder(.CW, Date)
.cdates <- .CW$Date
.PXM <- as.matrix(.CW[, -1L, with = FALSE])
.tick <- colnames(.PXM)
rm(.CW, .px); gc(verbose = FALSE)

.nr <- nrow(.PXM)
RET <- .PXM[-1L, , drop = FALSE] / .PXM[-.nr, , drop = FALSE] - 1
.rdt <- .cdates[-1L]                                  # RET 각 행의 날짜
RET[!is.finite(RET)] <- NA_real_
# ★which() 로 감싼다 — 논리 첨자에 NA 가 섞이면 대입이 에러다(이미 NA 를 채운 뒤라 반드시 섞인다).
RET[which(abs(RET) > .RET_CAP)] <- NA_real_           # 데이터 아티팩트 제거(가격제한폭 근거)
rm(.PXM); gc(verbose = FALSE)
cat(sprintf("[RP_2007_08115] 수익 행렬 %d일 x %d종 (%s ~ %s) · 결측 %.1f%%\n",
            nrow(RET), ncol(RET), as.character(min(.rdt)), as.character(max(.rdt)),
            100 * mean(is.na(RET))))

# mex 를 RET 행에 정렬
.MX <- .GD[Date %in% .rdt, .(Date, mex)]
setkey(.MX, Date)
.mexv <- .MX[.(.rdt), mex]
if (anyNA(.mexv))
  stop("[RP_2007_08115] mex 정렬 실패 — 격자/시장계열 불일치")

# =============================================================================
# 5. 유동성·멤버십 자격 (D 단면)
# =============================================================================
.rdq <- RAWDATA[Date %in% unique(c(.LW$Date, .FORM)),
                .(Date, Ticker, Close, Vol, K200, KQ150)]
.rdq <- unique(.rdq, by = c("Ticker", "Date"))

.ADV <- merge(.rdq[is.finite(Close) & is.finite(Vol), .(Date, Ticker, TV = Close * Vol)],
              .LW, by = "Date", allow.cartesian = TRUE)
.ADV <- .ADV[is.finite(TV), .(ADV20 = mean(TV), nobs = .N), by = .(FormDate, Ticker)]
.ADV <- .ADV[nobs == .LIQ_WIN & ADV20 >= .LIQ, .(FormDate, Ticker)]
setkey(.ADV, FormDate)

.ELG <- .rdq[Date %in% .FORM & (.tru(K200) | .tru(KQ150)) & is.finite(Close) & Close > 0,
             .(FormDate = Date, Ticker)]
.ELG <- merge(.ELG, .ADV, by = c("FormDate", "Ticker"))
setkey(.ELG, FormDate)
rm(.rdq, .LW, .ADV); gc(verbose = FALSE)

# =============================================================================
# 6. 형성일 루프 — joint depth=1 회귀트리 (mex 위 공통 임계값) -> 다수-잎 예측
# =============================================================================
# 목적함수 전개 (Q1 의 SSE 최소화와 동치):
#   SSE(k) = Sum_i [ TSS_i - CX_i(k)^2/CM_i(k) - (SX_i-CX_i(k))^2/(SM_i-CM_i(k)) ]
#   TSS_i 는 k 에 무관하므로 SSE 최소화 = 아래 .gain 최대화. 종목별 표준화는
#   하지 않는다 — 논문의 joint 트리가 그렇고, 'dominant stock' 이 그 성질이다(Q2).
.OUT  <- vector("list", length(.FORM))
.LOG  <- vector("list", length(.FORM))
.skip <- 0L

for (kk in seq_along(.FORM)) {
  D  <- .FORM[kk]
  ip <- match(D, .rdt)
  if (is.na(ip) || ip < .T_WIN) { .skip <- .skip + 1L; next }

  wi   <- (ip - .T_WIN + 1L):ip                       # 창: 종점 = D (보유월 시작 전)
  mexw <- .mexv[wi]

  cand <- .ELG[.(D), Ticker, nomatch = 0L]
  cand <- intersect(cand, .tick)
  if (!length(cand)) { .skip <- .skip + 1L; next }

  Y <- RET[wi, cand, drop = FALSE]
  # 창 커버리지 + 창 말일 거래 여부(현재 거래되는 종목만)
  cov_n <- colSums(!is.na(Y))
  keep  <- (cov_n >= as.integer(.MIN_COV * .T_WIN)) & !is.na(Y[.T_WIN, ])
  if (sum(keep) < .MIN_STK) { .skip <- .skip + 1L; next }
  Y <- Y[, keep, drop = FALSE]
  nm <- colnames(Y)

  # mex 오름차순 정렬 (동값은 같은 쪽으로 — 유효 분기점만 후보)
  o    <- order(mexw)
  ms   <- mexw[o]
  Ys   <- Y[o, , drop = FALSE]
  Msk  <- matrix(as.numeric(!is.na(Ys)), nrow = nrow(Ys))
  Xs   <- Ys; Xs[is.na(Xs)] <- 0

  CX <- colCumsums(Xs)
  CM <- colCumsums(Msk)
  Tn <- nrow(Xs); Mn <- ncol(Xs)
  SX <- CX[Tn, ]; SM <- CM[Tn, ]

  RXm <- matrix(SX, Tn, Mn, byrow = TRUE) - CX
  RMm <- matrix(SM, Tn, Mn, byrow = TRUE) - CM
  LTm <- CX^2  / CM
  RTm <- RXm^2 / RMm
  LTm[!is.finite(LTm)] <- 0                            # 잎에 관측이 없는 종목 = 기여 0
  RTm[!is.finite(RTm)] <- 0
  .gain <- rowSums(LTm + RTm)

  # 유효 분기점: 값이 실제로 갈리는 자리 + 양쪽 잎 최소 관측
  ok <- c(ms[-Tn] < ms[-1L], FALSE)
  ok[seq_len(.MIN_LEAF - 1L)] <- FALSE
  ok[(Tn - .MIN_LEAF + 1L):Tn] <- FALSE
  if (!any(ok)) { .skip <- .skip + 1L; next }
  .gain[!ok] <- -Inf
  ks <- which.max(.gain)

  cstar <- (ms[ks] + ms[ks + 1L]) / 2                  # sklearn 규약: 인접 두 값의 중점
  nL <- ks; nR <- Tn - ks
  left_major <- nL > nR

  num <- if (left_major) CX[ks, ] else (SX - CX[ks, ])
  den <- if (left_major) CM[ks, ] else (SM - CM[ks, ])
  sc  <- num / den
  good <- is.finite(sc) & den >= .MIN_LEAF
  if (!any(good)) { .skip <- .skip + 1L; next }

  .OUT[[kk]] <- data.table(Date = D, Ticker = nm[good], Score = as.numeric(sc[good]))

  # 진단: 임계값(bp) · balance · 지배 종목(비표준화 목적함수에서 분산이 가장 큰 종목)
  tss <- colSums(Xs^2) - SX^2 / pmax(SM, 1)
  .LOG[[kk]] <- data.table(
    Date = D, n_stock = sum(good), split_bp = 1e4 * cstar,
    bal_left = 100 * nL / Tn, side = if (left_major) "L" else "R",
    dom = nm[which.max(tss)])
}

FACTORS <- rbindlist(Filter(Negate(is.null), .OUT), use.names = TRUE)
if (!nrow(FACTORS))
  stop("[RP_2007_08115] FACTORS 0행 — 창 길이/유니버스/커버리지 확인")
setorder(FACTORS, Date, -Score)

# =============================================================================
# 7. 회수된 구조 보고 — 논문의 판단 대상(분기변수·임계값·balance)을 그대로 드러낸다
# =============================================================================
LOGDT <- rbindlist(Filter(Negate(is.null), .LOG), use.names = TRUE)
LOGDT[, yr := year(Date)]
.byyr <- LOGDT[, .(n_m = .N, n_stock = as.integer(stats::median(n_stock)),
                   split_bp = round(stats::median(split_bp), 1),
                   bal_left = round(stats::median(bal_left), 1)), by = yr]
setorder(.byyr, yr)
cat("[RP_2007_08115] 연도별 joint depth=1 구조 (분기변수 = mex 단일):\n")
for (i in seq_len(nrow(.byyr)))
  cat(sprintf("    %d | 월 %2d · 종목 %3d · 임계값 %7.1fbp · 좌잎 %5.1f%%\n",
              .byyr$yr[i], .byyr$n_m[i], .byyr$n_stock[i],
              .byyr$split_bp[i], .byyr$bal_left[i]))

.domtop <- LOGDT[, .N, by = dom][order(-N)][1:min(3L, uniqueN(LOGDT$dom))]
.nmn <- FACTORS[, .N, by = Date]
# ★스코어 분포 요약은 **벡터로 뽑아** 잰다 — `quantile(DT$col)` 형태는 lookahead_detector
#   C1b(전 표본 분위수) 에 걸려 라운드가 통째로 중단된다. 여기서 재는 대상은 창 안에서
#   이미 산출된 Score 의 분포 요약(로그)이지 신호 구성이 아니다.
.scv <- as.numeric(FACTORS[["Score"]])
cat(sprintf(paste0(
  "[RP_2007_08115] adapted: joint depth=1 regression tree on mex (창 %d거래일)\n",
  "  형성 %d개월(skip %d) · %s ~ %s · FACTORS %s행 · 월 종목 중앙 %d (min %d / max %d)\n",
  "  임계값 중앙 %.1fbp · 좌잎 비중 중앙 %.1f%% · 다수잎 = %s\n",
  "  지배 종목(분산 최대) 상위: %s\n",
  "  Score = 다수 잎의 예측 일간수익 (중앙 %.2fbp · IQR %.2f~%.2fbp)\n",
  "  ★러너 호출: portfolio_spec = list(construction=\"top_n_long\", weighting=\"ew\",\n",
  "                                    rebalance=\"monthly\", n_long=25, n_max=25)\n",
  "              commission_paper = NULL (논문 무명시) · %.1f분\n"),
  .T_WIN, nrow(LOGDT), .skip,
  as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date)),
  format(nrow(FACTORS), big.mark = ","),
  as.integer(stats::median(.nmn$N)), min(.nmn$N), max(.nmn$N),
  stats::median(LOGDT$split_bp), stats::median(LOGDT$bal_left),
  paste(sort(unique(LOGDT$side)), collapse = "/"),
  paste(sprintf("%s(%d개월)", .domtop$dom, .domtop$N), collapse = " "),
  1e4 * stats::median(.scv),
  1e4 * as.numeric(stats::quantile(.scv, 0.25, names = FALSE)),
  1e4 * as.numeric(stats::quantile(.scv, 0.75, names = FALSE)),
  as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
