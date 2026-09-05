# =============================================================================
# engine.R — RP_AUTO_COMBO_combo_1403_8125_2007_08115
#
# 결합 재료 (2편 사용 / 1편 미사용 — 미사용 사유는 FIDELITY.changed 가 정본)
#   [A] Jaehyung Choi, Sungsoo Choi, Wonseok Kang (2014)
#       "Maximum drawdown, recovery, and momentum"  arXiv:1403.8125
#       원문 전문: https://arxiv.org/html/1403.8125v1  (§3.2 · Table 1 · 식(1)(2))
#   [B] Vassilis Polimenis (2020)
#       "Uncovering a factor-based expected return conditioning structure with
#        Regression Trees jointly for many stocks"  arXiv:2007.08115
#       (2020년 투고분이라 arXiv HTML 판이 없다 — 축자 인용은 저장소 승계.
#        승계 출처 = 04_Research/strategies/RP_AUTO_2007_08115/engine.R 헤더 Q1~Q6,
#        선행 세션이 PDF 전문 렌더로 확보한 것. ★이 세션이 직접 검증한 것이 아니며
#        그 축만 미검증으로 분리한다 — FIDELITY._notes.source_text_access 참조.)
#   [C] Pinchuk (2023) "Labor Income Risk and the Cross-Section of Expected
#       Returns" arXiv:2301.09173 — **쓰지 않는다**. 사유 = FIDELITY.changed ①.
#
# ★fidelity = COMBINATION. 선언 정본 = FIDELITY.json (이 주석은 사본이지 통로가 아니다)
#
# =============================================================================
# 1. 무엇을 결합했는가 — 한 문장
# =============================================================================
#   [A] 의 규칙(형성창을 국면으로 쪼개고 **악화 국면에 두 배 가중**)을 그대로 두고,
#   그 국면 경계만 [B] 의 joint depth=1 회귀트리가 **전 종목 공동으로** 고른 상태
#   임계값으로 바꾼다.
#
#   [A] 의 CM 규칙은 CM = 1·R_I + 2·R_II + 1·R_III = C − MDD 다(Table 1).
#   여기서 (R_I, R_II, R_III) 는 **그 종목 자신의** 경로에서 사후적으로 잡은
#   (시작→peak, peak→trough, trough→끝) 3구간이다. 즉 [A] 의 '악화 구간'은
#   종목마다 다른 시점이고, 종목마다 다른 길이이며, 그 종목의 최악 연속 구간이라는
#   정의상 **반드시** 최악이다(선택된 구간).
#
#   [B] 의 주장은 정반대 방향이다: 기대수익의 조건부 구조는 상태변수 위의
#   depth=1 계단이고, 그 계단은 종목별로 따로 세우는 게 아니라 **여러 종목에
#   동시에 적합해 공통 임계값 하나**로 세워야 한다("a single model capable of
#   predicting simultaneously n stocks is built" · "correlation information enters
#   the tree structure"). 그리고 그 계단은 0 이 아니라 **꼬리**에 선다(Table 2c).
#
#   결합 = [A] 의 가중을 [B] 의 분할 위에 얹는다.
#     · 형성창 W(6개월, [A] §3.2)의 각 거래일을 joint depth=1 트리가 mex 위
#       공통 임계값 c* 로 두 잎으로 가른다.  ADV = {mex <= c*}(악화 국면),
#       MOD = {mex >  c*}(모달 국면).
#     · R_adv = sum_{t in ADV} lr_it  ·  R_mod = sum_{t in MOD} lr_it
#       → 항등식 R_adv + R_mod = C = [A] 의 누적 로그수익 그 자체다(정확히 일치).
#     · Score_i = 1·R_mod + 2·R_adv = C + R_adv.
#       [A] Table 1 의 CM=(1,2,1) 을 2-국면 분할에 옮긴 것이다: R_I·R_III 는 둘 다
#       '악화가 아닌 국면'이라 가중 1, R_II 는 악화 국면이라 가중 2. 사상은 정확하다.
#
#   ★자유 파라미터가 0 이다. 가중 (1,2) 는 [A] Table 1 의 CM(논문 자신의 헤드라인
#     규칙), 분할은 [B] 의 greedy SSE 가 매달 데이터에서 고른다. 내가 고른 수치가 없다.
#
# =============================================================================
# 2. 원문 대조 — 남긴 것 (kept)
# =============================================================================
# [A] arXiv:1403.8125 (직접 확보)
#   (A1) Table 1 · CM = (R_I,R_II,R_III) 가중 (1,2,1) = C − MDD.
#        "The best strategy is the momentum portfolio by the composite rule of
#         cumulative return and maximum drawdown" — KOSPI 200 월평균 1.433%.
#        ▸ 이 규칙 선택은 논문 자신의 헤드라인 결과이고 선행 단독구현
#          (RP_AUTO_1403_8125)이 이미 고른 칸이다. 내가 성과를 보고 고른 값이 아니다.
#   (A2) 3-국면 분해 C = R_I + R_II + R_III (§3.2 식(1)(2) 아래).
#        본 판은 국면 **경계**만 [B] 로 바꾸고 분해-가중-합산 구조는 그대로 쓴다.
#   (A3) 형성창 6개월 — "during 6 months (weeks) of estimation period".
#        월말 격자 6스텝, 종점 = 형성일 f(그 달 마지막 거래일).
#   (A4) 정렬 방향 — "assets ... are sorted in ascending order" ·
#        "The group 1 is for losers ... the last group is for the best performers"
#        → 스코어 큰 쪽이 승자 = 롱. 본 판은 롱온리라 상위만 취한다.
#        ▸ 수동 부호반전 0건(C13). [A] 의 "except for the maximum drawdown" 은
#          여기서도 부호로 자동 처리된다 — R_adv 가 음수라 큰 손실 = 낮은 스코어.
#   (A5) 미처리 경로 — 원문 데이터·방법 절에 winsorize/truncate/clip·최소 거래일·
#        커버리지 요건·최소 종목수 언급이 **전무**하다. 본 판도 커버리지 스크린을
#        두지 않는다(선행 단독구현이 앞 판에서 제거한 것을 되살리지 않는다).
#
# [B] arXiv:2007.08115 (저장소 승계 인용 — 위 헤더 주의문 참조)
#   (B1) "Limiting to max depth = 1"
#   (B2) "The cost function that is minimized when choosing split points is the sum
#         squared error across all training samples against their sub-region
#         prediction  Min for all split points  Sum_i ( y_i - prediction(y_i) )^2"
#   (B3) "all input variables and all possible split points are evaluated and chosen
#         in a greedy algorithm. The algorithm maximizes the drop in that value when
#         moving from a node to its children."
#   (B4) "a single model capable of predicting simultaneously n stocks is built" ·
#        "correlation information enters the tree structure"
#        → 다출력(multi-output) 단일 트리. **종목별 표준화 없음** — 분산이 큰 종목이
#          분기를 지배하는 성질("the dominant stock in a joint regression tree")은
#          제거 대상이 아니라 설계의 일부다. 본 판도 표준화하지 않는다.
#   (B5) Table 2c — 회수된 구조는 임계값이 0 이 아니라 꼬리(-350bp~+300bp)에 서고
#        분할이 극단적으로 불균형하다(1-99% ~ 22-78%). 본 판은 balance 를 **강제하지
#        않고 인쇄**한다(강제하면 [B] 가 보고한 성질을 지우게 된다).
#   (B6) 초록 — "in all cases (solo and joint) the most informative factor is always
#        the market excess return factor" → 분기변수를 mex 하나로 둔 근거.
#
# =============================================================================
# 3. 바꾼 것 (changed) — 요약. 전문·사유는 FIDELITY.json 이 정본이다
# =============================================================================
#   ① [C](2301.09173) 미사용.
#   ② 추정 창: [B] 의 1,259 거래일 → [A] 의 6개월 형성창.
#      사유 (i) 항등식 R_adv+R_mod=C 는 두 합이 **같은 창**일 때만 성립한다.
#           (ii) 점수 창 위에서 트리를 적합하면 두 잎이 **구성상 반드시 비지 않는다**
#                → 월 단위 신호 소실이 원리상 불가능하다. (선행 결합판 M3 은 5년 창에서
#                뽑은 임계값을 2년 창에 적용해 252개월 중 156개월만 리밸했고 그것이
#                fidelity_audit misdeclared 의 첫 지적이었다 — 그 실패 형태를 구조로 막는다.)
#           (iii) 1,259 는 [B] 의 **표본 길이**(Q4 data 절)이지 방법론 요건이 아니다.
#   ③ 분기변수: [B] 의 FF3(mex·SMB·HML) → mex 하나. KR 일간 SMB/HML 패널 부재 +
#      (B6) 만장일치 결과. 선행 단독구현(RP_AUTO_2007_08115)과 같은 축소·같은 사유.
#   ④ 산출 형태: [A] 는 10-decile 롱숏 EW · 6개월 보유 J-T 오버래핑인데, 본 판은
#      **고정 축**(top-25 롱온리 EW · 월간)을 쓴다. 결합에는 '논문 그대로의 포트폴리오'가
#      존재하지 않으므로 파라미터는 고정 축에서 온다.
#   ⑤ |일간수익| > 1.0 을 결측 처리(.RET_CAP). [A] 단독구현은 캡을 두지 않았고
#      [B] 단독구현은 뒀다 — 본 판은 [B] 쪽을 따른다. 사유: joint SSE 목적함수가
#      **비표준화**((B4))라 단위 아티팩트 한 건이 전 횡단면의 분기를 통째로 가져간다.
#      경로 통계는 그것을 견디지만 추정기는 못 견딘다. 캡은 lr·sr 양쪽에 **동일하게**
#      적용하므로 C 는 '아티팩트 제외 로그수익 합'이다(끝점-끝점 로그수익과 다르다).
#   ⑥ 유니버스 K200∪KQ150(PIT 시변) + adv20(t-1) >= 2e8 · 기간 2005-01-01~ (고정 축.
#      기간 절단은 엔진이 아니라 러너가 적용한다).
#   ⑦ 거래일 격자 = RAWDATA ∩ 벤치마크 날짜(mex 가 정의되는 날만). [B] 단독구현 관례.
#   ⑧ 커버리지 스크린 없음 — [B] 단독구현의 .MIN_COV=0.80 을 버리고 [A] 의 무스크린
#      입장을 따른다(창이 5년이 아니라 6개월이라 구속력이 다르고, 트리의 SSE 마스크가
#      결측을 이미 처리한다). 대신 커버리지는 진단으로 인쇄한다.
#
# =============================================================================
# 4. PIT (C1~C15) — 구조로 보장한다 (detect_lookahead 통과를 근거로 삼지 않는다)
# =============================================================================
#  ▸ 구조 경계 1: 모든 창의 종점이 형성일 f 다. 창은 항상
#    `.all_dates > me[k-6] & <= f` 로 닫히고, f 를 넘는 인덱스가 코드에 없다
#    (음수 shift 0건 · lead 0건 · 수동 미래 인덱싱 0건).
#  ▸ 구조 경계 2: 임계값 c*·잎 경계·국면 합계·진단이 **전부 그 창 안에서만** 계산되고
#    형성일 간 상태 이월이 없다(루프 반복이 독립). 전 표본 통계 0건.
#  ▸ 구조 경계 3: 종목 자격(멤버십·유동성)도 f 시점 관측이고 유동성 창은 f-1 에서 끝난다.
#  C1  : rolling 만. 모든 평균·합은 길이 |W| 창의 부분집합 통계다. 전 표본 분위수 0건
#        (스코어 분포 요약도 벡터로만 잰다 — 테이블 열을 직접 분위수에 넣지 않는다).
#  C2  : same-day 순환참조 없음. f 종가까지 쓰고 집행은 익월 첫 거래일(하네스).
#  C3  : 같은 기간 집계→적용 없음. 신호창 종점(f) < 보유월 시작.
#  C4  : 재무 패널 미사용(가격·거래대금·벤치마크만).
#  C5  : 오버레이 없음. 여기 국면 분할은 **신호 구성**이지 노출 스케일러가 아니다.
#  C6  : 유니버스 = 각 f 의 K200/KQ150 멤버십(PIT 시변). 미래 명부 주입 없음.
#        성능 목적 사전필터(`한 번이라도 지수 편입`)는 f 시점 자격 술어의 상위집합이라
#        판정을 바꾸지 않는다(동치 보존).
#  C7  : shift 는 전부 +1(과거 방향). lead()·shift(-n) 0건.
#  C9  : DD/VT 오버레이 미사용. 여기 낙폭류 통계는 과거창 신호 통계이지 실현낙폭
#        스케일러가 아니다(C9 의 same-day DD 소비와 무관).
#  C10 : 유동성 = f **직전** 20 거래일 평균 거래대금(frollmean 후 shift(1) → 당일 배제).
#  C11 : 외부 매크로 미사용. rf 는 전월 확정치를 **전월 거래일수**로 나눠 쓴다 —
#        당월 거래일수는 그 달이 끝나야 확정되므로 분모로 쓰면 월초에 모르는 값이 신호에
#        들어간다. 캐시 부재·단위 이상이면 rf=0 폴백하고 로그로 드러낸다(침묵 금지).
#  C13 : Factor DB 미소비 → 부호 정렬 대상 없음. 수동 부호반전 0건. 방향은 (A4) 하나에서만.
#  C15 : Factor DB parquet 직접 load 0건.
#  ★rawdata 의 Market 열 미사용(KOSDAQ 0건 날조 — 사내 기록). 시장 구분은 K200/KQ150
#    멤버십 플래그로만 한다.
#
# =============================================================================
# 5. 산출
# =============================================================================
#   FACTORS(Date, Ticker, Score) — Score = 1·R_mod + 2·R_adv (클수록 롱).
#   러너 호출: portfolio_spec = list(construction="top_n_long", weighting="ew",
#              rebalance="monthly", top_n=25, n_long=25, n_max=25)
#   commission_paper = NULL ([A]·[B] 둘 다 비용 무명시 → gross)
#
#   ★엔진이 스스로 인쇄하는 반증 5종(F1~F5) = FIDELITY.changed (2) 의 검사 가능 형태.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(arrow)
  library(matrixStats)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.REQ <- c("Date", "Ticker", "Close", "Vol", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("[RP_COMBO_1403_2007] RAWDATA 열 부족: %s",
               paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))

.tru <- function(x) !is.na(x) & (x != 0)     # 논리/0-1 혼재 방어
.t0  <- Sys.time()

# =============================================================================
# 0. 상수 — 출처가 셋뿐이다: (a) 논문 명시값 (b) 지시된 고정 축 (c) 정의의 정의역
#    임의로 고른 수치는 없다.
# =============================================================================
# ▸ (a) 논문 명시값
.FORM_M   <- 6L        # [A] §3.2 "6 months of estimation period" (월말 격자 6스텝)
.W_MOD    <- 1         # [A] Table 1 CM=(1,2,1) → 악화가 아닌 국면(R_I·R_III) 가중
.W_ADV    <- 2         # [A] Table 1 CM=(1,2,1) → 악화 국면(R_II) 가중
# ▸ (b) 지시된 고정 축
.LIQ      <- 2e8       # adv20(t-1) 하한 (KRW)
.LIQ_WIN  <- 20L       # 유동성 창 (거래일, 종점 = f-1)
.TOP_N    <- 25L       # 고정 축 보유 상한 — 여기서는 **진단(F1 겹침률)** 에만 쓴다.
                       #   선택은 러너가 portfolio_spec 으로 한다.
# ▸ (c) 정의의 정의역 / [B] 구현 관례 (전부 FIDELITY 에 선언)
.MIN_LEAF <- 2L        # 잎 최소 거래일 — [B] 단독구현 관례(sklearn min_samples_leaf).
                       #   잎 평균이 성립하는 하한이지 balance 강제가 아니다.
.MIN_STK  <- 2L        # joint 트리가 성립하는 최소 계열수([B] 표본은 5종)
.RET_CAP  <- 1.0       # |일간수익| > 100% = 단위 아티팩트. KRX 가격제한폭 ±30% 하에서
                       #   한 세션에 물리적으로 불가능 → 윈저가 아니라 결측 처리.

# =============================================================================
# 1. 가격 패널 + 유동성 adv20(t-1)   (RAWDATA 비파괴)
# =============================================================================
# 성능 목적 사전필터: 한 번이라도 K200/KQ150 이었던 종목만. f 시점 자격 술어
#   (그 날 멤버십)의 상위집합이므로 자격 판정을 바꾸지 않는다(C6 동치 보존).
.tk_ever <- unique(RAWDATA[.tru(K200) | .tru(KQ150), Ticker])
if (!length(.tk_ever))
  stop("[RP_COMBO_1403_2007] K200/KQ150 멤버십 0건 — RAWDATA 확인")

.rd <- RAWDATA[Ticker %chin% .tk_ever, .(Date, Ticker, Close, Vol, K200, KQ150)]
if (!inherits(.rd$Date, "Date")) .rd[, Date := as.Date(Date)]
.rd <- .rd[is.finite(Close) & Close > 0]
.rd <- unique(.rd, by = c("Ticker", "Date"))
setorder(.rd, Ticker, Date)

# 거래대금(결측 거래량 = 그날 회전 0). adv20 후 shift(1) → t-1 (C10)
.rd[, TV := Close * fifelse(is.finite(as.numeric(Vol)), as.numeric(Vol), 0)]
.rd[, ADV20_L1 := shift(frollmean(TV, .LIQ_WIN, align = "right"), 1L), by = Ticker]

# =============================================================================
# 2. 시장 계열 mex = 벤치마크 일간수익 - rf   ([B] 의 분기변수)
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
  stop("[RP_COMBO_1403_2007] 시장 일간수익 계열 부재 — BM_DT(BM_Ret/BM_Close) 확인")
if (!inherits(.bm$Date, "Date")) .bm[, Date := as.Date(Date)]
setorder(.bm, Date)

# rf: 월간 KR 팩터 캐시의 RF 를 **전월값 / 전월 거래일수** 로 일할 (부재·이상 시 0 폴백)
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
      #   퍼센트 표기(또는 다른 축)이므로 쓰지 않는다 — 잘못 쓰면 임계값이 어긋난다.
      if (!is.finite(md) || md < 0 || md > 0.02) {
        cat(sprintf("[RP_COMBO_1403_2007] rf 캐시 단위 이상(median %.6f) — rf=0 폴백: %s\n", md, fn))
        next
      }
      return(d)
    }
  }
  NULL
}
.rf_monthly <- .rf_load()

# 거래일 격자 = RAWDATA ∩ 벤치마크 (mex 가 정의되는 날만 — 유령 거래일 배제)
.gd <- as.Date(intersect(unique(.rd$Date), .bm$Date), origin = "1970-01-01")
if (length(.gd) < 200L)
  stop(sprintf("[RP_COMBO_1403_2007] 거래일 격자 %d일 — 너무 짧다", length(.gd)))
.GD <- data.table(Date = .gd)
setorder(.GD, Date)
.GD[, ym := year(Date) * 12L + month(Date)]
.GD[, rf := 0]
if (!is.null(.rf_monthly)) {
  .rm <- copy(.rf_monthly)
  setorder(.rm, Date)                                   # RF[.N] = 그 달 마지막 관측
  .rm[, ym := year(Date) * 12L + month(Date)]
  .rm <- .rm[, .(RF = RF[.N]), by = ym]
  .nd <- .GD[, .(nd = as.numeric(.N)), by = ym]
  .rm <- merge(.rm, .nd, by = "ym", all.x = TRUE)
  setorder(.rm, ym)
  .rm[, `:=`(ym_p = shift(ym, 1L), RF_p = shift(RF, 1L), nd_p = shift(nd, 1L))]
  .rm[is.na(ym_p) | ym_p != (ym - 1L),                  # 결번 월이면 인정하지 않는다
      c("RF_p", "nd_p") := list(NA_real_, NA_real_)]
  .rm[, rf_d := fifelse(is.finite(RF_p) & is.finite(nd_p) & nd_p > 0, RF_p / nd_p, 0)]
  .GD <- merge(.GD, .rm[, .(ym, rf_d)], by = "ym", all.x = TRUE)
  .GD[, rf := fifelse(is.finite(rf_d), rf_d, 0)]
  .GD[, rf_d := NULL]
  setorder(.GD, Date)
  cat(sprintf("[RP_COMBO_1403_2007] rf 적용: 격자 %.1f%% (일평균 %.2fbp)\n",
              100 * mean(.GD$rf != 0), 1e4 * mean(.GD$rf)))
  rm(.rm, .nd)
} else {
  cat("[RP_COMBO_1403_2007] rf 캐시 없음 — mex = 시장수익(rf=0). [B] 의 excess 정의와의 차이이지 PIT 문제가 아니다\n")
}
.GD <- merge(.GD, .bm, by = "Date")
setorder(.GD, Date)
.GD[, mex := MKT - rf]

.all_dates <- .GD$Date
.me_dates  <- .GD[, .(f = max(Date)), by = ym][order(f), f]      # 월말 거래일 격자
setkey(.GD, Date)
setkey(.rd, Date)

cat(sprintf("[RP_COMBO_1403_2007] 패널 %s행 · 격자 %d일 %s~%s · 월말 %d개\n",
            format(nrow(.rd), big.mark = ","), length(.all_dates),
            as.character(min(.all_dates)), as.character(max(.all_dates)),
            length(.me_dates)))

# =============================================================================
# 3. [A] 단독 규칙 CM = C − MDD (진단·반증 F1 전용 — 스코어에 들어가지 않는다)
#    v = 시계열 순 로그수익. 경로 = c(0, cumsum(v)) → [A] 식(1)(2) 그대로.
#    cummax 는 t<=tau 포함형 — 단조 상승 경로에서 MDD=0 이 되어 비음수 규약과 일치.
# =============================================================================
.cm_plain <- function(v) {
  n <- length(v)
  if (n < 1L) return(NA_real_)
  pth <- c(0, cumsum(v))
  ddv <- pth - cummax(pth)                   # <= 0
  pth[n + 1L] + min(ddv)                     # = C − MDD
}

# 스피어만 (rank + 피어슨 — method 문자열 없이 동일)
.sp <- function(a, b) {
  ok <- is.finite(a) & is.finite(b)
  if (sum(ok) < 5L) return(NA_real_)
  av <- rank(a[ok]); bv <- rank(b[ok])
  if (stats::var(av) <= 0 || stats::var(bv) <= 0) return(NA_real_)
  as.numeric(stats::cor(av, bv))
}

# =============================================================================
# 4. 형성일 루프 — joint depth=1 트리로 국면을 가르고 [A] 의 CM 가중을 얹는다
#    목적함수 전개 ((B2) 의 SSE 최소화와 동치):
#      SSE(k) = Sum_i [ TSS_i - CX_i(k)^2/CM_i(k) - (SX_i-CX_i(k))^2/(SM_i-CM_i(k)) ]
#      TSS_i 는 k 에 무관 → SSE 최소화 = 아래 gn 최대화.
#    종목별 표준화는 하지 않는다 — (B4) 의 joint 트리가 그렇고 'dominant stock' 이
#    그 성질이다.
# =============================================================================
.OUT  <- vector("list", length(.me_dates))
.LOG  <- vector("list", length(.me_dates))
.skip <- 0L

for (k in seq_along(.me_dates)) {
  if (k <= .FORM_M) next                                   # me[k-6] 필요
  f  <- .me_dates[k]
  w0 <- .me_dates[k - .FORM_M]
  wd <- .all_dates[.all_dates > w0 & .all_dates <= f]      # [A] 6개월 일별 창 (종점 = f)
  Tn <- length(wd)
  if (Tn < (2L * .MIN_LEAF + 1L)) { .skip <- .skip + 1L; next }

  # 자격: f 의 K200/KQ150 멤버십 + 지시 축 adv20(t-1) 하한 (C6·C10)
  fr   <- .rd[.(f), .(Ticker, K200, KQ150, ADV20_L1), nomatch = 0L]
  elig <- fr[(.tru(K200) | .tru(KQ150)) & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ, Ticker]
  if (length(elig) < .MIN_STK) { .skip <- .skip + 1L; next }

  PW <- .rd[.(wd), .(Date, Ticker, Close), nomatch = 0L]
  PW <- PW[Ticker %chin% elig]
  if (!nrow(PW)) { .skip <- .skip + 1L; next }

  # 창 거래일을 mex 오름차순으로 세운다 (동값은 Date 로 결정론 정렬)
  DW <- .GD[.(wd), .(Date, mex), nomatch = 0L]
  if (nrow(DW) != Tn) { .skip <- .skip + 1L; next }
  setorder(DW, mex, Date)
  DW[, ord := .I]

  PW <- merge(PW, DW, by = "Date")
  setorder(PW, Ticker, Date)                               # 그룹 내 Date 오름차순 보장
  PW[, lr := log(Close) - log(shift(Close, 1L)), by = Ticker]
  PW[!is.finite(lr), lr := NA_real_]
  PW[, sr := exp(lr) - 1]
  PW[is.finite(sr) & abs(sr) > .RET_CAP, `:=`(lr = NA_real_, sr = NA_real_)]   # 위생(⑤)

  PV <- PW[is.finite(sr)]
  tk <- sort(unique(PV$Ticker))
  if (length(tk) < .MIN_STK) { .skip <- .skip + 1L; next }

  # ---- joint depth=1 트리 (B1~B4) ----
  Y <- matrix(NA_real_, nrow = Tn, ncol = length(tk))
  Y[cbind(PV$ord, match(PV$Ticker, tk))] <- PV$sr
  Msk <- matrix(as.numeric(!is.na(Y)), nrow = Tn)
  Xs  <- Y; Xs[is.na(Xs)] <- 0
  CX <- colCumsums(Xs); CMm <- colCumsums(Msk)
  np <- ncol(Xs)
  SX <- CX[Tn, ]; SM <- CMm[Tn, ]
  LTm <- CX^2 / CMm
  RTm <- (matrix(SX, Tn, np, byrow = TRUE) - CX)^2 / (matrix(SM, Tn, np, byrow = TRUE) - CMm)
  LTm[!is.finite(LTm)] <- 0                                # 잎에 관측이 없는 종목 = 기여 0
  RTm[!is.finite(RTm)] <- 0
  gn <- rowSums(LTm + RTm)

  ms  <- DW$mex
  okv <- c(ms[-Tn] < ms[-1L], FALSE)                       # 값이 실제로 갈리는 자리만
  okv[seq_len(.MIN_LEAF - 1L)] <- FALSE                    # 양쪽 잎 최소 거래일
  okv[(Tn - .MIN_LEAF + 1L):Tn] <- FALSE
  if (!any(okv)) { .skip <- .skip + 1L; next }
  gn[!okv] <- -Inf
  ks    <- which.max(gn)
  cstar <- (ms[ks] + ms[ks + 1L]) / 2                      # sklearn 규약: 인접 두 값의 중점

  # ---- [A] 의 CM 가중을 두 잎에 얹는다 ----
  #   ADV = ord <= ks  = {mex <= c*}  (악화 국면 = [A] 의 R_II 자리)
  #   MOD = ord >  ks  = {mex >  c*}  ([A] 의 R_I + R_III 자리)
  PW[, adv := ord <= ks]
  SC <- PW[is.finite(lr), {
    a <- adv
    list(n_lr  = .N,           n_adv = sum(a),
         R_adv = sum(lr[a]),   R_mod = sum(lr[!a]),
         s_adv = sum(sr[a]),   s_mod = sum(sr[!a]),
         Sx    = sum(mex),     Sy    = sum(sr),
         Sxy   = sum(mex * sr), Sxx  = sum(mex * mex),
         cm_p1 = .cm_plain(lr))
  }, by = Ticker]
  SC[, n_mod := n_lr - n_adv]
  # 정의의 정의역: 2-국면 분해는 두 국면이 다 관측돼야 정의된다
  #   ([A] 의 n>=2 와 같은 성격의 하한이지 스크린이 아니다)
  SC <- SC[n_adv >= 1L & n_mod >= 1L]
  if (nrow(SC) < .MIN_STK) { .skip <- .skip + 1L; next }

  SC[, Score := .W_MOD * R_mod + .W_ADV * R_adv]           # = C + R_adv
  SC[, C_win := R_mod + R_adv]                             # = [A] 의 누적 로그수익
  SC <- SC[is.finite(Score)]
  if (nrow(SC) < .MIN_STK) { .skip <- .skip + 1L; next }

  .OUT[[k]] <- data.table(Date = f, Ticker = SC$Ticker, Score = SC$Score)

  # ---- 진단 · 반증 재료 (전부 창 안 통계) ----
  left_major <- ks > (Tn - ks)                             # 다수 잎이 어느 쪽인가
  SC[, mu_maj := if (left_major) s_adv / n_adv else s_mod / n_mod]   # [B] 단독 스코어
  SC[, den := n_lr * Sxx - Sx * Sx]
  SC[, beta := fifelse(is.finite(den) & den > 0, (n_lr * Sxy - Sx * Sy) / den, NA_real_)]

  nkeep <- min(.TOP_N, nrow(SC))
  t_new <- SC$Ticker[order(-SC$Score)][seq_len(nkeep)]
  t_p1  <- SC$Ticker[order(-SC$cm_p1)][seq_len(nkeep)]

  .LOG[[k]] <- data.table(
    Date     = f,
    n_day    = Tn,
    n_stock  = nrow(SC),
    cov_med  = as.numeric(stats::median(SC$n_lr)) / Tn,
    adv_shr  = ks / Tn,
    split_bp = 1e4 * cstar,
    maj_side = if (left_major) "ADV" else "MOD",
    adv_mu   = if (sum(SC$n_adv) > 0) sum(SC$s_adv) / sum(SC$n_adv) else NA_real_,
    mod_mu   = if (sum(SC$n_mod) > 0) sum(SC$s_mod) / sum(SC$n_mod) else NA_real_,
    rho_p1   = .sp(SC$Score, SC$cm_p1),
    rho_p3   = .sp(SC$Score, SC$mu_maj),
    rho_C    = .sp(SC$Score, SC$C_win),
    rho_b_new = .sp(SC$Score, SC$beta),
    rho_b_p1  = .sp(SC$cm_p1, SC$beta),
    ovl25    = length(intersect(t_new, t_p1)) / nkeep)
}

FACTORS <- rbindlist(Filter(Negate(is.null), .OUT), use.names = TRUE)
if (!nrow(FACTORS))
  stop("[RP_COMBO_1403_2007] FACTORS 0행 — 창/유니버스/자격 확인")
setorder(FACTORS, Date, -Score)

# =============================================================================
# 5. 회수된 구조 + 반증 5종 (F1~F5)
#    ★성과 수치 선언이 아니다 — 등급은 계약이 낸다. 여기 있는 것은 전부 **창 안**
#      구조 통계이고, 각 F 는 FIDELITY.changed (2) 의 주장을 검사 가능한 형태로
#      바꾼 것이다. FAIL 이면 그 주장이 그만큼 거짓이다.
# =============================================================================
LOGDT <- rbindlist(Filter(Negate(is.null), .LOG), use.names = TRUE)

.med <- function(x) { v <- x[is.finite(x)]; if (!length(v)) NA_real_ else as.numeric(stats::median(v)) }

.m_rho_p1 <- .med(LOGDT$rho_p1)
.m_ovl    <- .med(LOGDT$ovl25)
.m_rho_p3 <- .med(LOGDT$rho_p3)
.m_advshr <- .med(LOGDT$adv_shr)
.m_rho_C  <- .med(LOGDT$rho_C)

# F5: 리밸 스케줄 — 형성 가능 월(창이 잡히는 월) 대비 실제 발행 월, 최장 연속 결번
.cand_k  <- seq_along(.me_dates)[-seq_len(.FORM_M)]
.cand_f  <- .me_dates[.cand_k]
.cand_f  <- .cand_f[.cand_f >= min(FACTORS$Date)]          # 워밍업 이후 구간에서 센다
.formed  <- sort(unique(FACTORS$Date))
.miss    <- setdiff(as.character(.cand_f), as.character(.formed))
.gapmax  <- 0L
if (length(.miss)) {
  hit <- as.integer(as.character(.cand_f) %in% as.character(.formed))
  rl  <- rle(hit)
  gz  <- rl$lengths[rl$values == 0L]
  .gapmax <- if (length(gz)) max(gz) else 0L
}

.f1 <- (is.finite(.m_rho_p1) && .m_rho_p1 < 0.95) && (is.finite(.m_ovl) && .m_ovl < 0.80)
.f2 <- is.finite(.m_rho_p3) && .m_rho_p3 < 0.95
.f3 <- is.finite(.m_advshr) && !(.m_advshr >= 0.40 && .m_advshr <= 0.60)
.f4 <- is.finite(.m_rho_C) && .m_rho_C < 0.98
.f5 <- (length(.miss) == 0L) && (.gapmax == 0L)
.vv <- function(b) if (isTRUE(b)) "pass" else "FAIL"

LOGDT[, yr := year(Date)]
.byyr <- LOGDT[, .(n_m = .N, n_stock = as.integer(stats::median(n_stock)),
                   split_bp = round(stats::median(split_bp), 1),
                   adv_shr  = round(100 * stats::median(adv_shr), 1),
                   rho_p1   = round(.med(rho_p1), 3)), by = yr]
setorder(.byyr, yr)
cat("[RP_COMBO_1403_2007] 연도별 회수 구조 (분기변수 = mex 단일 · depth=1 · joint):\n")
for (i in seq_len(nrow(.byyr)))
  cat(sprintf("    %d | 월 %2d · 종목 %3d · 임계값 %8.1fbp · 악화잎 %5.1f%% · rho([A]) %6.3f\n",
              .byyr$yr[i], .byyr$n_m[i], .byyr$n_stock[i],
              .byyr$split_bp[i], .byyr$adv_shr[i], .byyr$rho_p1[i]))

.scv <- as.numeric(FACTORS[["Score"]])       # ★벡터로 잰다 — 테이블 열 직접 분위수는 C1b
.nmn <- FACTORS[, .N, by = Date]
.sgn_ok <- mean(as.numeric(LOGDT$adv_mu < LOGDT$mod_mu), na.rm = TRUE)

cat(sprintf(paste0(
  "[RP_COMBO_1403_2007] combination: [A]1403.8125 CM(1,2,1) 가중 x [B]2007.08115 joint depth=1 분할\n",
  "  Score = 1*R_mod + 2*R_adv (= C + R_adv) · 형성창 %d개월 · 추정창 = 같은 창(항등식 R_adv+R_mod=C)\n",
  "  형성 %d개월(skip %d) · %s ~ %s · FACTORS %s행 · 월 종목 중앙 %d (min %d / max %d)\n",
  "  임계값 중앙 %.1fbp · 악화잎 비중 중앙 %.1f%% · 다수잎 = %s · 창 커버리지 중앙 %.2f\n",
  "  악화잎 평균수익 < 모달잎 평균수익 인 달 비율 %.3f (부호 확인 — 강제 아님)\n",
  "  Score 중앙 %.2f%% · IQR %.2f%% ~ %.2f%%\n",
  "  ---- 반증 5종 (FIDELITY.changed (2) 의 검사 가능 형태) ----\n",
  "  F1 [A] 재라벨 아님   : rho(Score, C-MDD) 중앙 %6.3f (<0.95) · top-%d 겹침 %5.3f (<0.80)  -> %s\n",
  "  F2 [B] 재라벨 아님   : rho(Score, 다수잎평균) 중앙 %6.3f (<0.95)                          -> %s\n",
  "  F3 계단이 꼬리에 섬  : 악화잎 비중 중앙 %5.3f (구간 [0.40,0.60] 밖이어야 함)             -> %s\n",
  "  F4 악화항이 하중받음 : rho(Score, C) 중앙 %6.3f (<0.98)                                   -> %s\n",
  "  F5 월 결번 0         : 후보 %d개월 중 결번 %d개 · 최장 연속 결번 %d                        -> %s\n",
  "  ★engine 산출 = FACTORS · portfolio_spec = top_n_long/ew/monthly/25 · commission_paper=NULL\n",
  "  ★기간축은 러너 적용(2005-01-01~) · 소요 %.1f분\n"),
  .FORM_M,
  nrow(LOGDT), .skip,
  as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date)),
  format(nrow(FACTORS), big.mark = ","),
  as.integer(stats::median(.nmn$N)), min(.nmn$N), max(.nmn$N),
  .med(LOGDT$split_bp) , 100 * .m_advshr,
  paste(sort(unique(LOGDT$maj_side)), collapse = "/"), .med(LOGDT$cov_med),
  .sgn_ok,
  100 * as.numeric(stats::median(.scv)),
  100 * as.numeric(stats::quantile(.scv, 0.25, names = FALSE)),
  100 * as.numeric(stats::quantile(.scv, 0.75, names = FALSE)),
  .m_rho_p1, .TOP_N, .m_ovl, .vv(.f1),
  .m_rho_p3, .vv(.f2),
  .m_advshr, .vv(.f3),
  .m_rho_C, .vv(.f4),
  length(.cand_f), length(.miss), .gapmax, .vv(.f5),
  as.numeric(difftime(Sys.time(), .t0, units = "mins"))))

cat(sprintf(paste0(
  "[RP_COMBO_1403_2007] 시장채널 진단(강제 아님 — 기전 서술의 근거):\n",
  "  rho(Score, 창내 시장베타) 중앙 %6.3f · rho(C-MDD, 창내 시장베타) 중앙 %6.3f\n",
  "  → 결합판의 위험 통제가 [A] 의 경로 MDD 보다 **공통 상태**에 명시적으로 걸려 있는가를 읽는 줄이다.\n"),
  .med(LOGDT$rho_b_new), .med(LOGDT$rho_b_p1)))
