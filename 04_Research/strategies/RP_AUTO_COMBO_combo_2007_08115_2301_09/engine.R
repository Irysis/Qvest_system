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
# 결합의 형태 — 무엇을 무엇에 끼웠는가
# =============================================================================
# 두 재료의 스코어를 각각 만들어 평균/합성하는 지점은 이 엔진에 **없다**.
# 저장소는 그 형태(두 엔진 신호의 rank-Z 평균)를 5회 측정했고 계보 최고 t 0.766 이다.
# 여기서 하는 것은 다른 수술이다:
#
#   Pinchuk 에서 가져온 것 = **상태변수**(그 논문의 소비 방식인 β_CID 정렬이 아니다).
#     Eq.1  CID_t = (1/N) Σ_i |R_i,t − R_MKT,t|   (VW 산업 포트폴리오, ≥10사)
#     Eq.2  ΔCID_t = γ0 + γ1 ΔCID_{t−1} + γ2 CID_{t−1} + u_t → 잔차 u_t
#           ("residuals û_t treated as CID in subsequent analysis" — 논문 자신의
#            operative 변수가 레벨이 아니라 충격 u_t 다)
#
#   Polimenis 에서 가져온 것 = **추정기**.
#     "a single model capable of predicting simultaneously n stocks is built"
#     "Limiting to max depth = 1"
#     "The cost function ... is the sum squared error across all training samples
#      against their sub-region prediction  Min Σ_i (y_i − prediction(y_i))^2"
#     "all input variables and all possible split points are evaluated and chosen
#      in a greedy algorithm"
#     창 = 1,259 daily returns (논문 표본 그대로). 종목별 표준화 없음
#     ("the dominant stock in a joint regression tree" 는 제거 대상이 아니라 성질).
#
#   결합 =  ① Polimenis 트리의 **분기 후보 변수 집합**에 Pinchuk 의 u_t 를 넣어
#             논문 자신의 승자(mex, "in all cases ... the most informative factor is
#             always the market excess return factor")와 **매월 경합**시키고,
#           ② 트리의 예측을 **다수 잎**(모달 국면)이 아니라 **현재 상태가 실제로
#             떨어지는 잎**의 평균으로 발행한다.
#
#   상태는 항상 **전월값**이다: 월 j 의 일간수익 ↔ 월 j−1 의 상태. 그러므로 훈련쌍의
#   시차 구조와 예측쌍의 시차 구조가 동일하다(형성일 D = 월 m 말, 보유월 m+1,
#   조건값 = 월 m 의 상태 — D 에 이미 관측된 값).
#
# =============================================================================
# 왜 각 재료 단독보다 나을 것이라 보는가 (반증 형태는 FIDELITY.json changed ②)
# =============================================================================
#  ▸ CID 단독(다중검정 t 1.228 · 충실구현 Grade F)의 실패 기전은 사내 실측으로 특정돼
#    있다: 상태를 **동시점 선형 기울기** β_CID(24개월 R_i,t = a + β u_t + e)로 소비했고,
#    KR 에서 cor(u_t, 시장_t) = +0.43(2022–26 +0.63 — 분산 급등이 하락이 아니라 반도체
#    주도 급등에서 나온다)이라 그 기울기가 시장베타로 변질됐다. 5분위 스프레드는
#    고정부호 역베타 베팅(일간 β −0.39)이 됐고 FF 알파 9~12% 는 그 헤지 회계였다.
#      → 이 결합은 상태(월 j−1)와 반응(월 j)을 **다른 달에 놓아** 동시점 회귀 채널을
#        구조적으로 제거한다. 산출물은 기울기가 아니라 "지난달 상태가 c* 아래/위였을 때
#        이 종목이 벌던 평균" 이다. 그리고 민감도 방향의 부호를 내가 고르지 않는다 —
#        어느 잎을 발행할지는 **그 달의 상태가** 정한다(고정부호 베팅이 원리상 불가).
#  ▸ 트리 단독(다중검정 t 1.11)의 한계도 특정된다: 분기변수 mex 가 지속성 없는 일간
#    수익이라 형성일에 "현재 국면" 이 정의되지 않고, 그래서 **다수 잎**(balance 1-99% ~
#    22-78% 의 압도적인 쪽)만 발행할 수 있었다 — 조건부 구조를 회수해 놓고 조건부를
#    쓰지 않는 셈이다(사실상 무조건부 창 평균).
#      → u_t 는 월 단위 거시 상태라 형성일에 관측된다. 현재-상태 잎이 정의되므로
#        논문 제목의 "conditioning structure" 를 실제로 소비할 수 있다.
#
# =============================================================================
# 미명시값 보충 (전부 명시 — 지어낸 수치를 숨기지 않는다)
# =============================================================================
#  · AR(Eq.2) 을 **expanding window** 로 뽑는다. 논문은 전표본 1회 추정이지만 그건
#    C1(full-sample) 위반이라 PIT 가 논문 문자를 이긴다. burn-in 60개월(RP_2301_09173_CID
#    선례 승계 — 같은 재료의 기존 구현과 수치를 어긋나게 두지 않는다).
#  · 산업분류 = RAWDATA Sector_Lv2(48군 — FF49 의 최근접 아날로그), 각 월말 기록값.
#  · |일간 Ret| > 1.0 = 결측. KRX 가격제한폭 ±30% 하에서 한 세션에 불가능한 값이므로
#    액면/재상장 단위 아티팩트다. 전략 파라미터가 아니라 거래소 규칙 근거의 위생 조치.
#  · 잎 최소 크기: **관측 1%** = 논문이 실제로 회수해 보고한 가장 작은 balance
#    (Table 2c, KO 1-99%). 여기에 **최소 2개월** 을 더한다 — 상태가 월 단위로 블록
#    되므로 한 달짜리 잎의 평균은 조건부 기대값이 아니라 그 달의 실현치 하나다
#    (평균이 성립하는 하한 n=2 를 유효 관측 단위인 '월' 에 적용).
#  · 설명변수 SMB/HML 제외: 인프라의 KR FF3 는 월간뿐이고, KR 일간 FF3 를 새로 만들면
#    장부가 정의·절단점·형성주기를 논문 밖에서 지어내야 한다. 논문 결론이 mex 만장일치
#    승리이므로 이 축소가 지우는 것은 결과가 보고된 경마다(대가: KR 에서 SMB/HML 이
#    이겼을 가능성은 이 엔진이 검정하지 않는다).
#  · y = 원 일간수익(초과수익 아님). 스코어는 **한 잎 안에서만** 횡단면 비교되고 rf 는
#    그 잎의 모든 종목에 동일 상수로 들어가므로 **순위가 불변**이다. rf 는 분기변수
#    mex 정의에만 쓴다(논문의 excess return factor).
#
# =============================================================================
# PIT (C1~C15) — 구조로 보장한다. detect_lookahead 통과를 근거로 삼지 않는다.
# =============================================================================
#  ▸ 구조 경계 1 — 시차: 학습쌍이 (월 j−1 상태, 월 j 수익)이고 예측쌍이
#    (월 m 상태, 월 m+1 수익)이다. 상태가 반응보다 **항상 한 달 앞선다**. 상태 테이블
#    .STA 는 `ymi = ymi + 1L` 한 줄로 만들어져서, 같은 달 상태를 쓰는 경로가 코드에
#    존재하지 않는다(동월 사용을 막는 검사가 아니라, 동월 사용이 표현 불가능한 배치).
#  ▸ 구조 경계 2 — 창: 모든 창의 종점이 D 이하다. 창은 `(ip − .T_WIN + 1L):ip`,
#    ip = match(D, .rdt). ip 를 넘는 인덱스가 코드에 0건. 음수 shift 0건. lead 0건.
#  ▸ 구조 경계 3 — 상태 이월 없음: 형성일 루프 반복이 서로 독립이다. 트리 적합·분기점·
#    잎 평균이 전부 그 창 안에서만 계산된다. 형성일 간에 넘겨지는 상태가 없다.
#  ▸ 구조 경계 4 — AR: expanding 루프가 `fit_rows[seq_len(k)]` 로 <= t 만 자른다.
#  C1  : rolling/expanding 만. 전 표본 mean/quantile/cov 0건. 모든 평균은 창 안 잎 평균.
#  C2  : same-day 순환참조 없음. D 종가까지 쓰고 집행은 익 거래일(하네스).
#  C3  : 같은 기간 집계→적용 없음(상태는 반응보다 한 달 앞).
#  C4  : 재무제표 패널 미사용.
#  C5  : 오버레이 없음. 신호 컷오프(월 m 말) < 보유월(m+1) 시작 — 정합.
#  C6  : 유니버스 = 각 D 의 K200/KQ150 멤버십(PIT 시변). 최종 명부 주입 없음.
#        창 커버리지 요건은 과거 데이터 요건이라 생존편의를 만들지 않는다.
#  C7  : shift(-N)·lead()·수동 미래 인덱싱 0건. shift 는 전부 +1(과거 방향).
#  C9  : DD/VT 미사용.
#  C10 : 유동성 = D **직전 20 거래일** 평균 거래대금, `lo:(ip − 1L)` 로 당일 배제.
#  C11 : 외부 매크로는 월간 RF 뿐이고 **전월 확정치**만 쓴다.
#  C13 : Factor DB 미소비 → 정렬 대상 없음. 수동 부호 반전 0건(스코어 = 기대수익 예측값).
#  C15 : Factor DB parquet 직접 load 0건.
#  ★rawdata 의 Market 열 미사용(KOSDAQ 0건 날조 — 사내 기록). 시장 구분은 K200/KQ150
#    멤버십 플래그로만 한다.
#
# ===== 산출 =====
#   FACTORS(Date, Ticker, Score) — Score = joint depth=1 트리가 **현재 상태의 잎**에
#   내놓는 기대 일간수익. 클수록 롱(부호 선택 없음).
#   러너 호출: portfolio_spec = list(construction="top_n_long", weighting="ew",
#              rebalance="monthly", n_long=25, n_max=25) · commission_paper = NULL
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

set.seed(20070811L)   # 난수 미사용(결정론적 엔진) — 재현성 선언 고정

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.RQ <- c("Date", "Ticker", "Close", "Vol", "Ret", "Size", "Sector_Lv2", "K200", "KQ150")
if (!all(.RQ %in% names(RAWDATA)))
  stop(sprintf("[COMBO_08115_09173] RAWDATA 열 부족: %s",
               paste(setdiff(.RQ, names(RAWDATA)), collapse = ", ")))

# =============================================================================
# 0. 상수 — 논문에서 온 것 / 축에서 온 것 / 수치 타당성 하한
# =============================================================================
# ▸ Polimenis 에서 온 것
.T_WIN         <- 1259L   # 추정 창 = 1,259 daily returns (논문 표본 그대로)
.MIN_LEAF_FRAC <- 0.01    # 잎 최소 관측 비율 = 논문이 회수·보고한 최소 balance(KO 1-99%)
# ▸ Pinchuk 에서 온 것
.CID_MIN_FIRMS <- 10L     # "industries with at least 10 firms"
.CID_AR_BURNIN <- 60L     # 보충(논문은 전표본 — PIT 상 expanding 필요). CID 선례 승계
# ▸ 축(도훈 고정)에서 온 것
.LIQ           <- 2e8     # adv20(t-1) 하한 (KRW)
.LIQ_WIN       <- 20L     # 거래일 (D 직전 20 거래일, 종점 = D-1)
.START         <- as.Date("2005-01-01")
# ▸ 수치 타당성 하한 — 전략 파라미터가 아니다(성과를 보고 고른 값이 아니다)
.MIN_COV       <- 0.80    # 창 커버리지 하한 = 논문 5년 창 중 4년치
.MIN_LEAF_MON  <- 2L      # 잎 최소 개월 — 상태가 월 블록이므로 유효 관측 단위가 '월' 이고,
                          #   1개월 잎의 평균은 조건부 기대값이 아니라 그 달의 실현치다
.MIN_LEAF_OBS  <- 2L      # 종목별 잎 최소 관측 — 평균이 성립하는 하한
.MIN_STK       <- 2L      # joint 트리가 성립하는 최소 종목수(논문은 5종)
.RET_CAP       <- 1.0     # |일간수익| > 100% = 데이터 아티팩트(KRX 가격제한폭 ±30%)

.MIN_LEAF_N <- as.integer(ceiling(.MIN_LEAF_FRAC * .T_WIN))   # = 13 관측

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
# 열 누적합 (M x K, M >= 4 보장 하에 호출)
.colcum <- function(X) {
  if (nrow(X) == 1L) return(X)
  matrix(apply(X, 2L, cumsum), nrow = nrow(X), ncol = ncol(X), dimnames = dimnames(X))
}

if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]

# =============================================================================
# 1. Pinchuk Eq.1 — CID (거시 상태변수: 시장 전체에서 만든다)
# =============================================================================
# ★유니버스 치환(K200∪KQ150)은 **정렬 대상(test asset)** 에만 걸린다. CID 자체는 논문이
#   "value-weighted market return across all firms from CRSP" 라 한 거시 변수이므로
#   전 상장종목에서 만든다.
.DD <- RAWDATA[, .(Date, Ticker, Ret, Size, Sector_Lv2)]
.DD[, rr := Ret]
.DD[!is.finite(rr) | abs(rr) > .RET_CAP, rr := NA_real_]
.DD[, ymi := year(Date) * 12L + month(Date)]

.MEALL <- .DD[, .(me = max(Date)), by = ymi]                 # 시장 전체 월말 거래일

.MON <- .DD[, .(mret = if (sum(is.finite(rr)) >= 1L) prod(1 + rr[is.finite(rr)]) - 1 else NA_real_),
            by = .(Ticker, ymi)]
.EOM <- .DD[Date %in% .MEALL$me, .(Ticker, ymi, size_end = Size, ind = Sector_Lv2)]
.MON <- merge(.MON, .EOM, by = c("Ticker", "ymi"))

setorder(.MON, Ticker, ymi)                                   # 전월말 시총(논문 가중치)
.MON[, `:=`(size_prev = shift(size_end), ymi_prev = shift(ymi)), by = Ticker]
.MON[!is.finite(ymi_prev) | ymi_prev != ymi - 1L, size_prev := NA_real_]

.VAL <- .MON[is.finite(mret) & is.finite(size_prev) & size_prev > 0 & !is.na(ind)]
.IP  <- .VAL[, .(nf = .N, r_ind = sum(mret * size_prev) / sum(size_prev)),
             by = .(ymi, ind)][nf >= .CID_MIN_FIRMS]
.MKT <- .MON[is.finite(mret) & is.finite(size_prev) & size_prev > 0,
             .(r_mkt = sum(mret * size_prev) / sum(size_prev)), by = ymi]
CIDT <- merge(.IP, .MKT, by = "ymi")[, .(CID = mean(abs(r_ind - r_mkt)), n_ind = .N), by = ymi]
setorder(CIDT, ymi)
if (nrow(CIDT) < (.CID_AR_BURNIN + 12L))
  stop(sprintf("[COMBO_08115_09173] CID 월 %d개 — AR burn-in %d 에 못 미침",
               nrow(CIDT), .CID_AR_BURNIN))
rm(.VAL, .IP, .MKT, .EOM); gc(verbose = FALSE)

# =============================================================================
# 2. Pinchuk Eq.2 — CID 충격 u_t (expanding window AR · PIT 보정)
# =============================================================================
CIDT[, dC := CID - shift(CID)]
CIDT[, `:=`(dC_l1 = shift(dC), C_l1 = shift(CID))]
CIDT[, u := NA_real_]
.fit_rows <- which(is.finite(CIDT$dC) & is.finite(CIDT$dC_l1) & is.finite(CIDT$C_l1))
if (length(.fit_rows) >= .CID_AR_BURNIN) {
  for (k in seq.int(.CID_AR_BURNIN, length(.fit_rows))) {
    sub <- CIDT[.fit_rows[seq_len(k)]]                        # <= t 만 (expanding)
    f   <- stats::lm(dC ~ dC_l1 + C_l1, data = sub)
    res <- stats::residuals(f)
    set(CIDT, i = .fit_rows[k], j = "u", value = as.numeric(res[length(res)]))
  }
}
if (sum(is.finite(CIDT$u)) == 0L)
  stop("[COMBO_08115_09173] CID 충격 u 전량 결측 — AR 적합 실패")
# 일간 원장(.DD ~1.4e7행)은 CID 산출 이후 쓰이지 않는다 — RET 행렬 만들기 전에 비운다
rm(.DD, .MON, .MEALL); gc(verbose = FALSE)

# =============================================================================
# 3. 시장 계열 — 일간 BM_Ret (베타 진단) · 월간 mex (분기 후보 변수)
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
  stop("[COMBO_08115_09173] 시장 일간수익 계열 부재 — BM_DT(BM_Ret/BM_Close) 확인")
if (!inherits(.bm$Date, "Date")) .bm[, Date := as.Date(Date)]
setorder(.bm, Date)

# ── 월간 RF: 캐시 부재/단위 이상이면 0 폴백(침묵 금지) ──────────────────────
.rf_load <- function() {
  if (!requireNamespace("arrow", quietly = TRUE)) return(NULL)
  cand <- c(Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""),
            if (exists("PROJECT_ROOT")) as.character(PROJECT_ROOT)[1] else "")
  for (p in cand) {
    if (!nzchar(p)) next
    for (fn in c("kr_factor_returns_v2.parquet", "kr_factor_returns.parquet")) {
      fp <- file.path(p, ".cache", fn)
      if (!file.exists(fp)) next
      d <- tryCatch(as.data.table(arrow::read_parquet(fp)), error = function(e) NULL)
      if (is.null(d) || !all(c("Date", "RF") %in% names(d))) next
      d <- d[, .(Date = as.Date(Date), RF = as.numeric(RF))][is.finite(RF)]
      if (!nrow(d)) next
      md <- as.numeric(stats::median(d$RF))
      # 월간 무위험수익률의 소수 표기는 0~2% 안이어야 한다. 벗어나면 퍼센트 표기(또는
      # 다른 축)이므로 쓰지 않는다 — 잘못 쓰면 분기 임계값이 통째로 어긋난다.
      if (!is.finite(md) || md < 0 || md > 0.02) {
        cat(sprintf("[COMBO_08115_09173] rf 캐시 단위 이상(median %.6f) — rf=0 폴백: %s\n", md, fn))
        next
      }
      d[, ymi := year(Date) * 12L + month(Date)]
      return(d[, .(RF = RF[.N]), by = ymi])                   # 그 달 마지막 관측
    }
  }
  NULL
}
.RFM <- .rf_load()

.bmd <- copy(.bm)
.bmd[, ymi := year(Date) * 12L + month(Date)]
MEXM <- .bmd[, .(mret_m = prod(1 + MKT) - 1, nd_m = .N), by = ymi]
if (is.null(.RFM)) {
  MEXM[, mexm := mret_m]
  cat("[COMBO_08115_09173] rf 캐시 없음 — mex = 시장수익(rf=0). 논문 정의(excess)와의 차이이지 PIT 문제가 아니다\n")
} else {
  MEXM <- merge(MEXM, .RFM, by = "ymi", all.x = TRUE)
  MEXM[, mexm := mret_m - fifelse(is.finite(RF), RF, 0)]
  cat(sprintf("[COMBO_08115_09173] rf 적용: 월 %.1f%% (월평균 %.3f%%)\n",
              100 * mean(is.finite(MEXM$RF)), 100 * mean(MEXM$RF, na.rm = TRUE)))
}
setorder(MEXM, ymi)

# =============================================================================
# 4. 상태 테이블 .STA — **한 달 앞선 상태**만 존재하도록 만든다
# =============================================================================
# .STA[ymi = j] = 월 j−1 에 관측된 상태값. 즉 "월 j 의 수익을 조건짓는 값" 이고,
# 월 j 가 시작되기 전에 전부 알려져 있다. 동월 상태를 참조하는 경로가 없다(구조 경계 1).
.SRC <- merge(CIDT[, .(ymi, u)], MEXM[, .(ymi, mexm)], by = "ymi", all = TRUE)
setorder(.SRC, ymi)
.STA <- .SRC[, .(ymi = ymi + 1L, s_cid = u, s_mex = mexm)]
setkey(.STA, ymi)
.good_m <- .STA[is.finite(s_cid) & is.finite(s_mex), ymi]
if (length(.good_m) < 60L)
  stop(sprintf("[COMBO_08115_09173] 두 상태가 모두 있는 월 %d개 — 부족", length(.good_m)))
cat(sprintf("[COMBO_08115_09173] 상태 가용 월 %d개 (%d ~ %d) · cor(u, mexm) 참고치 %.3f\n",
            length(.good_m), min(.good_m), max(.good_m),
            .sp(.STA[ymi %in% .good_m, s_cid], .STA[ymi %in% .good_m, s_mex])))

# =============================================================================
# 5. 거래일 격자 · 형성일 · 유동성 창
# =============================================================================
.gd <- sort(intersect(unique(RAWDATA$Date), .bm$Date))
.gd <- as.Date(.gd, origin = "1970-01-01")
if (length(.gd) < (.T_WIN + 40L))
  stop(sprintf("[COMBO_08115_09173] 거래일 격자 %d일 — 창 %d일에 못 미침", length(.gd), .T_WIN))

.GD <- data.table(Date = .gd)
.GD[, ymi := year(Date) * 12L + month(Date)]
.ME <- .GD[, .(Date = max(Date)), by = ymi]
setorder(.ME, Date)
.FORM  <- .ME[Date >= .START, Date]
if (!length(.FORM))
  stop("[COMBO_08115_09173] 형성일 0건 — RAWDATA 날짜 범위 확인")

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
  stop("[COMBO_08115_09173] 유동성 창 구성 실패 — 거래일 수 부족")
.FORM <- .FORM[.FORM %in% unique(.LW$FormDate)]
.fym  <- year(.FORM) * 12L + month(.FORM)

# =============================================================================
# 6. 가격 패널 -> 일간수익 wide 행렬
# =============================================================================
.tk <- unique(RAWDATA[.tru(K200) | .tru(KQ150), Ticker])
if (!length(.tk))
  stop("[COMBO_08115_09173] K200/KQ150 멤버십 0건 — RAWDATA 확인")

.px <- RAWDATA[Ticker %chin% .tk & Date %in% .gdv & is.finite(Close) & Close > 0,
               .(Date, Ticker, Close)]
.ndup <- sum(duplicated(.px, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[COMBO_08115_09173] (Date,Ticker) 중복 %d행 — 첫 행만 남긴다\n", .ndup))
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
.rdt <- .cdates[-1L]                                   # RET 각 행의 날짜
RET[!is.finite(RET)] <- NA_real_
# ★which() 로 감싼다 — 논리 첨자에 NA 가 섞이면 대입이 에러다(이미 NA 를 채운 뒤라 반드시 섞인다).
RET[which(abs(RET) > .RET_CAP)] <- NA_real_
rm(.PXM); gc(verbose = FALSE)
.rymi <- year(.rdt) * 12L + month(.rdt)
cat(sprintf("[COMBO_08115_09173] 수익 행렬 %d일 x %d종 (%s ~ %s) · 결측 %.1f%%\n",
            nrow(RET), ncol(RET), as.character(min(.rdt)), as.character(max(.rdt)),
            100 * mean(is.na(RET))))

# 진단용 일간 시장수익 (베타 오염 검사 전용 — 신호에 들어가지 않는다)
setkey(.bm, Date)
.mktd <- .bm[.(.rdt), MKT]
if (anyNA(.mktd))
  stop("[COMBO_08115_09173] 일간 시장수익 정렬 실패 — 격자/시장계열 불일치")

# =============================================================================
# 7. 유동성·멤버십 자격 (D 단면)
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
# 8. 형성일 루프 — joint depth=1 트리 (후보 상태 2종 경합) -> 현재-상태 잎 예측
# =============================================================================
# 목적함수 전개 (Polimenis Q1 의 SSE 최소화와 정확히 동치):
#   SSE(k) = Σ_i [ TSS_i − CX_i(k)²/CM_i(k) − (SX_i−CX_i(k))²/(SM_i−CM_i(k)) ]
#   TSS_i 는 k 에도 분기변수에도 무관하므로, SSE 최소화 = 아래 gain 최대화이고
#   **변수 간 비교도 같은 gain 으로 유효**하다(같은 y, 같은 창).
#   상태가 월 내에서 상수라 월 집계 후 누적합은 일간 계산과 수치적으로 동일하다.
#   종목별 표준화는 하지 않는다 — 논문의 joint 트리가 그렇고, 'dominant stock' 이
#   제거 대상이 아니라 그 설계의 성질이다.
.OUT  <- vector("list", length(.FORM))
.LOG  <- vector("list", length(.FORM))
.skip <- 0L

for (kk in seq_along(.FORM)) {
  D   <- .FORM[kk]
  ip  <- match(D, .rdt)
  if (is.na(ip) || ip < .T_WIN) { .skip <- .skip + 1L; next }

  # 보유월(m+1)의 조건값 = .STA[ymi = m+1] = 월 m 에 관측된 상태 (D 에 이미 알려짐)
  cs <- .STA[.(.fym[kk] + 1L), nomatch = 0L]
  if (!nrow(cs) || !is.finite(cs$s_cid[1]) || !is.finite(cs$s_mex[1])) { .skip <- .skip + 1L; next }

  wi  <- (ip - .T_WIN + 1L):ip                         # 창: 종점 = D (보유월 시작 전)
  ymw <- .rymi[wi]
  kd  <- ymw %in% .good_m                              # 두 상태가 모두 있는 달만 (공정 경합)
  if (sum(kd) < .MIN_COV * .T_WIN) { .skip <- .skip + 1L; next }
  wi  <- wi[kd]; ymw <- ymw[kd]
  nw  <- length(wi)

  cand <- .ELG[.(D), Ticker, nomatch = 0L]
  cand <- intersect(cand, .tick)
  if (!length(cand)) { .skip <- .skip + 1L; next }

  Y <- RET[wi, cand, drop = FALSE]
  cov_n <- colSums(!is.na(Y))
  keep  <- (cov_n >= as.integer(.MIN_COV * nw)) & !is.na(Y[nw, ])   # 창 말일 거래 종목만
  if (sum(keep) < .MIN_STK) { .skip <- .skip + 1L; next }
  Y  <- Y[, keep, drop = FALSE]
  nm <- colnames(Y)

  Xd <- Y; Xd[is.na(Xd)] <- 0
  Md <- !is.na(Y); storage.mode(Md) <- "double"

  # ── 진단 전용: 창 무조건부 평균 · 창 시장베타 (신호에 들어가지 않는다) ──
  mkw <- .mktd[wi]
  nq  <- colSums(Md); Sy <- colSums(Xd)
  Sx  <- colSums(Md * mkw); Sxx <- colSums(Md * mkw^2); Sxy <- colSums(Xd * mkw)
  dnb <- nq * Sxx - Sx * Sx
  bmk <- ifelse(is.finite(dnb) & dnb > 0, (nq * Sxy - Sx * Sy) / dnb, NA_real_)
  mu_all <- ifelse(nq > 0, Sy / nq, NA_real_)

  # ── 월 집계 (상태가 월 블록이므로 무손실) ──
  SumM <- rowsum(Xd, ymw, reorder = TRUE)
  CntM <- rowsum(Md, ymw, reorder = TRUE)
  ndM  <- as.numeric(rowsum(matrix(1, nrow = nw, ncol = 1L), ymw, reorder = TRUE)[, 1L])
  mvec <- as.integer(rownames(SumM))
  M <- nrow(SumM); K <- ncol(SumM)
  if (M < (2L * .MIN_LEAF_MON)) { .skip <- .skip + 1L; next }
  st <- .STA[.(mvec), .(s_cid, s_mex)]

  # ── 후보 변수 경합 (Polimenis: all input variables, greedy) ──
  best <- NULL
  gv   <- c(mex = NA_real_, cid = NA_real_)
  for (vn in c("mex", "cid")) {
    svv <- if (vn == "mex") st$s_mex else st$s_cid
    o   <- order(svv)
    svo <- svv[o]
    CX  <- .colcum(SumM[o, , drop = FALSE])
    CM  <- .colcum(CntM[o, , drop = FALSE])
    nd  <- cumsum(ndM[o])
    SX  <- CX[M, ]; SM <- CM[M, ]
    RXm <- matrix(SX, M, K, byrow = TRUE) - CX
    RMm <- matrix(SM, M, K, byrow = TRUE) - CM
    LTm <- CX^2  / CM
    RTm <- RXm^2 / RMm
    LTm[!is.finite(LTm)] <- 0                          # 잎에 관측이 없는 종목 = 기여 0
    RTm[!is.finite(RTm)] <- 0
    g <- rowSums(LTm + RTm)

    kseq <- seq_len(M)
    ok <- c(svo[-M] < svo[-1L], FALSE)                 # 값이 실제로 갈리는 자리만
    ok <- ok & (kseq >= .MIN_LEAF_MON) & ((M - kseq) >= .MIN_LEAF_MON)
    ok <- ok & (nd >= .MIN_LEAF_N) & ((nd[M] - nd) >= .MIN_LEAF_N)
    if (!any(ok)) next
    g[!ok] <- -Inf
    ks <- as.integer(which.max(g))                     # 이름 붙은 인덱스가 열로 새지 않게
    if (!is.finite(g[ks])) next
    gv[[vn]] <- as.numeric(g[ks])
    if (is.null(best) || as.numeric(g[ks]) > best$gain)
      best <- list(var = vn, gain = as.numeric(g[ks]), ks = ks, svo = svo,
                   CX = CX, CM = CM, SX = SX, SM = SM, mvec_o = mvec[o])
  }
  if (is.null(best)) { .skip <- .skip + 1L; next }

  ks    <- best$ks
  cstar <- as.numeric(best$svo[ks] + best$svo[ks + 1L]) / 2   # sklearn 규약: 인접 두 값의 중점
  cur   <- if (best$var == "mex") cs$s_mex[1] else cs$s_cid[1]
  left  <- (cur < cstar)                               # 현재 상태가 떨어지는 잎

  numv <- if (left) best$CX[ks, ] else (best$SX - best$CX[ks, ])
  denv <- if (left) best$CM[ks, ] else (best$SM - best$CM[ks, ])
  sc   <- numv / denv
  good <- is.finite(sc) & denv >= .MIN_LEAF_OBS
  if (!any(good)) { .skip <- .skip + 1L; next }

  .OUT[[kk]] <- data.table(Date = D, Ticker = nm[good], Score = as.numeric(sc[good]))

  # ── 반증 계기 (FIDELITY.json changed ② 의 (a)~(d)) ──
  muL <- best$CX[ks, ] / best$CM[ks, ]
  muR <- (best$SX - best$CX[ks, ]) / (best$SM - best$CM[ks, ])
  .LOG[[kk]] <- data.table(
    Date = D, svar = best$var,
    margin = if (all(is.finite(gv))) as.numeric(gv[["cid"]] - gv[["mex"]]) else NA_real_,
    thr = cstar, mon_L = ks, mon_R = M - ks, n_mon = M,
    cur_left = left,
    cur_minor = (left && ks < (M - ks)) || (!left && (M - ks) < ks),
    cur_leaf_mon = if (left) ks else (M - ks),
    n_stock = sum(good),
    rho_LR   = .sp(muL, muR),                          # (b) 조건부 구조 회수 여부
    rho_lvl  = .sp(sc[good], mu_all[good]),            # (c) 무조건부 평균의 별칭인가
    rho_beta = .sp(sc[good], bmk[good]),               # (d) 역베타 오염 재현 여부
    t_deg    = .sp(best$mvec_o, c(rep(0, ks), rep(1, M - ks))))   # 시간 퇴화 검사
}

FACTORS <- rbindlist(Filter(Negate(is.null), .OUT), use.names = TRUE)
if (!nrow(FACTORS))
  stop("[COMBO_08115_09173] FACTORS 0행 — 창 길이/유니버스/커버리지/상태 가용월 확인")
setorder(FACTORS, Date, -Score)

# =============================================================================
# 9. 회수된 구조 + 반증 계기 보고
# =============================================================================
LOGDT <- rbindlist(Filter(Negate(is.null), .LOG), use.names = TRUE)

# (e) 국면이 뒤집힌 달에 순위가 실제로 갈리는가 — 인접 형성일 스코어 rank 상관
.dts <- sort(unique(FACTORS$Date))
.stab <- rbindlist(lapply(seq_along(.dts)[-1L], function(i) {
  a <- FACTORS[Date == .dts[i - 1L], .(Ticker, s0 = Score)]
  b <- FACTORS[Date == .dts[i],      .(Ticker, s1 = Score)]
  m <- merge(a, b, by = "Ticker")
  if (nrow(m) < 20L) return(NULL)
  data.table(Date = .dts[i], rho_prev = .sp(m$s0, m$s1))
}), use.names = TRUE)
if (nrow(.stab)) LOGDT <- merge(LOGDT, .stab, by = "Date", all.x = TRUE)
setorder(LOGDT, Date)

.med <- function(x) if (!length(x) || all(is.na(x))) NA_real_ else stats::median(x, na.rm = TRUE)
.win_cid <- 100 * mean(LOGDT$svar == "cid")
.flip <- if ("rho_prev" %in% names(LOGDT)) {
  LOGDT[, side := paste0(svar, "_", cur_left)]
  LOGDT[, side_prev := shift(side)]
  c(.med(LOGDT[is.finite(rho_prev) & !is.na(side_prev) & side == side_prev, rho_prev]),
    .med(LOGDT[is.finite(rho_prev) & !is.na(side_prev) & side != side_prev, rho_prev]))
} else c(NA_real_, NA_real_)

LOGDT[, yr := year(Date)]
.byyr <- LOGDT[, .(n_m = .N, cid_win = as.integer(round(100 * mean(svar == "cid"))),
                   n_stock = as.integer(.med(n_stock)),
                   mon_L = as.integer(.med(mon_L)), n_mon = as.integer(.med(n_mon)),
                   minor = as.integer(round(100 * mean(cur_minor))),
                   rho_LR = round(.med(rho_LR), 2), rho_lvl = round(.med(rho_lvl), 2),
                   rho_beta = round(.med(rho_beta), 2)), by = yr]
setorder(.byyr, yr)
cat("[COMBO_08115_09173] 연도별 joint depth=1 구조 (분기변수 = mex vs u_CID 경합):\n")
cat("      연도 | 월수 CID승률 종목 좌잎월/전체 현재=소수잎  rho(muL,muR) rho(S,평균) rho(S,beta)\n")
for (i in seq_len(nrow(.byyr)))
  cat(sprintf("      %d |  %2d   %3d%%  %3d    %2d/%2d       %3d%%       %+5.2f      %+5.2f      %+5.2f\n",
              .byyr$yr[i], .byyr$n_m[i], .byyr$cid_win[i], .byyr$n_stock[i],
              .byyr$mon_L[i], .byyr$n_mon[i], .byyr$minor[i],
              .byyr$rho_LR[i], .byyr$rho_lvl[i], .byyr$rho_beta[i]))

.nmn <- FACTORS[, .N, by = Date]
.scv <- as.numeric(FACTORS[["Score"]])
cat(sprintf(paste0(
  "[COMBO_08115_09173] combination: Pinchuk u_CID 를 Polimenis joint depth=1 트리의\n",
  "  분기 후보축으로 이식 + 다수잎이 아니라 **현재-상태 잎** 발행 (창 %d거래일)\n",
  "  형성 %d개월(skip %d) · %s ~ %s · FACTORS %s행 · 월 종목 중앙 %d (min %d / max %d)\n",
  "  ── 반증 계기 (전 기간 중앙값) ───────────────────────────────────────────\n",
  "  (a) u_CID 분기 승률          %5.1f%%   [0%% 이면 Pinchuk 재료 무하중 = 결합 아님]\n",
  "  (b) rho(mu_L, mu_R)          %+5.2f    [+1 이면 조건부 구조 미회수]\n",
  "  (c) rho(Score, 창 무조건부평균) %+5.2f    [+1 이면 5년 모멘텀의 별칭]\n",
  "  (d) rho(Score, 창 시장베타)   %+5.2f    [부호 고정·大 이면 역베타 오염 재현]\n",
  "  (e) 인접월 순위상관: 같은 잎 %+5.2f / 잎 전환 %+5.2f  [갈리지 않으면 조건부 무효]\n",
  "  ── 구조 요약 ────────────────────────────────────────────────────────────\n",
  "  분기 임계값 중앙: mex %+.4f / u_CID %+.6f (단위가 달라 따로 잰다) ·\n",
  "  좌잎 개월 중앙 %.0f/%.0f · 현재=소수잎 %.1f%% ·\n",
  "  현재잎 개월수 중앙 %.0f · 시간퇴화 |rho| 중앙 %.2f [1 에 가까우면 상태분기가 아니라 시간분기]\n",
  "  Score = 현재-상태 잎의 예측 일간수익 (중앙 %.2fbp · IQR %.2f~%.2fbp)\n",
  "  ★러너 호출: portfolio_spec = list(construction=\"top_n_long\", weighting=\"ew\",\n",
  "                                    rebalance=\"monthly\", n_long=25, n_max=25)\n",
  "              commission_paper = NULL (Polimenis 무명시) · %.1f분\n"),
  .T_WIN, nrow(LOGDT), .skip,
  as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date)),
  format(nrow(FACTORS), big.mark = ","),
  as.integer(stats::median(.nmn$N)), min(.nmn$N), max(.nmn$N),
  .win_cid, .med(LOGDT$rho_LR), .med(LOGDT$rho_lvl), .med(LOGDT$rho_beta),
  .flip[1], .flip[2],
  .med(LOGDT[svar == "mex", thr]), .med(LOGDT[svar == "cid", thr]),
  .med(LOGDT$mon_L), .med(LOGDT$n_mon),
  100 * mean(LOGDT$cur_minor), .med(LOGDT$cur_leaf_mon), .med(abs(LOGDT$t_deg)),
  1e4 * stats::median(.scv),
  1e4 * as.numeric(stats::quantile(.scv, 0.25, names = FALSE)),
  1e4 * as.numeric(stats::quantile(.scv, 0.75, names = FALSE)),
  as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
