# =============================================================================
# engine.R — RP_AUTO_2511_12129
# "A Practical Machine Learning Approach for Dynamic Stock Recommendation"
#   Hongyang Yang, Xiao-Yang Liu, Qingwei Wu (arXiv:2511.12129, 2025-11-15)
#   전문: arxiv.org/html/2511.12129v1 (초록 · Table I 20지표 · Table II MSE ·
#        Table III 예측/선정 · Fig.1 training-testing-trading cycle)
#
# ★fidelity = FAITHFUL. ★선언 정본 = FIDELITY.json (이 주석은 사본이다)
#
# ===== 원문 대조 (그대로 옮긴 것) =============================================
#   초록   "our basic idea is to buy and hold the top 20% stocks dynamically"
#   데이터 "in order to build a sector-neutral portfolio, we split the dataset by
#          the Global Industry Classification Standard (GICS) sectors ...
#          We finish these steps for all eleven GICS sectors."
#   Table I 20개 재무비율 (Revenue Growth · EPS · ROA · ROE · Net/Gross/Operating
#          margin · P/E · P/S · P/B · P/CF · Enterprise multiple · EV/CF ·
#          Long term debt to total assets · Debt to equity · Cash ratio ·
#          Quick ratio · Working capital ratio · Days sales of inventory ·
#          Days payable outstanding)
#   목표변수 "1-quarter forward log-returns"  ln(S_{T+f,i} / S_{T,i})
#   창     "Rolling windows for training ranges from 16-quarter (4-year) to a
#          maximum of 40-quarter (10-year). This training rolling window is
#          followed by an one-year window for testing."
#   절차   1) "Train and test the model to get the MSE for each of the five models."
#          2) "Choose the model that has the lowest MSE in that certain period."
#          3) "Use the predicted return in the selected model to pick up top 20%
#             stocks from each sector."
#   모형 5 linear regression / ridge regression / stepwise regression /
#          random forest / generalized boosted regression
#   리밸   "we extend the trade date by two months lag beyond the standard quarter
#          end date ... for the quarter between 04/01 and 06/30, our trade date is
#          adjusted to 09/01"  → 거래일 = 3/1 · 6/1 · 9/1 · 12/1, 보유 3개월
#   배분   equally weighted / mean-variance / minimum-variance 3종 보고,
#          저자 결론 = "min-variance portfolio is a better method"
#          제약 = long-only · fully invested · 5% maximum position
#   공분산 "Covariance matrix: use 1 year historical daily return."
#   비용   "1/1000 of the value of that trade"  → commission_paper = 0.001
#
# ===== 산출 형태 ==============================================================
#   PORTFOLIO(Date, Ticker, Weight, Leg) — 논문 비중(min-variance)이므로 이 형태.
#   FIDELITY.json 의 portfolio_spec = construction "engine_direct".
#   FACTORS(Date, Ticker, Score) 도 함께 낸다 — 섹터 내 예측수익 백분위(진단 전용).
#   측정에 들어가는 비중은 PORTFOLIO 뿐이다 (러너 :296 engine_direct 분기).
#
# ===== 리밸 격자가 논문과 어떻게 맞는가 ========================================
#   하네스 집행일 = get_execution_date(시그널일) = **익월 첫 거래일**
#   (backtest_harness.R:316-323). 따라서 2/5/8/11월 말일을 시그널일로 내면
#   집행이 3/1 · 6/1 · 9/1 · 12/1 이 되어 논문의 거래일 규약과 정확히 일치하고,
#   replication_harness.R:86-88 이 다음 시그널 집행일 전날까지 보유하므로
#   보유기간도 논문의 3개월이 된다. 분기 격자는 하네스 수정 0으로 얻어진다.
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) ==
#   시간 경계: 시그널일 d = 2/5/8/11월 마지막 거래일. 집행 E = 익월 첫 거래일.
#     모든 특성·목표·공분산 창의 종점이 d 이하이므로 종점 = t-1 (t = 보유 첫날).
#   C1  전 표본 통계 0건. 통계는 (a) 과거로 닫힌 학습창 k_train (b) 과거로 닫힌
#       평가창 k_test (c) 그 날짜 하나의 횡단면 (d) (d-365, d] 일간 공분산 창 뿐.
#       ★모형 선택(5개 중 argmin MSE)이 소비하는 MSE 는 **거래 이전에 이미 실현된**
#       4분기 평가창에서만 나온다. 실행 시점 assert 가 max(k_test)+1 <= n 을 강제한다.
#       ★결측률 5% 규칙도 전 표본이 아니라 그 시점의 (학습+평가) 창에서만 잰다.
#       scale() · 전표본 mean/sd/quantile 0건.
#   C2  same-day 순환참조 없음 — 목표는 k → k+1 구간 수익이고 학습은 k <= n-1 만.
#   C3  같은 기간 집계 → 적용 없음.
#   C4  회계 가용일 = 패널의 Factor_Date (분기 5/15·8/15·11/15 · 사업연도 익년 3/31).
#       ★XLSX 분기 경로의 12월 결산분은 원본이 +45d(≈익년 2/14)로 공격적이므로
#       (pit.md C4 경고) 엔진이 익년 3/31 로 **되늦춘다**. 보수 방향 전용 lag 강화.
#       매핑은 Factor_Date <= 시그널일 rolling join(뒤로만 구른다) + 730일 stale 컷.
#   C5  오버레이 없음.
#   C6  유니버스 = 그 날짜 행에 기록된 K200/KQ150 멤버십(시변). 목표수익 가격은
#       멤버십과 무관한 전 종목 가격패널에서 가져와 라벨 생존편향을 없앴다.
#   C7  음수 shift · lead() · 수동 미래 인덱싱 0건. 다음 거래일 가격은 원천 쪽
#       인덱스를 k-1 로 **내려** 붙인다(미래를 당기지 않는다).
#   C8/C9  FM · VT · DD 미사용.
#   C10 유동성 스크린 미적용 (FIDELITY changed 참조) — 당일 거래량 소비 0건.
#   C11 외부 매크로 미사용.
#   C13 부호 반전 0건 — 예측수익 그대로 내림차순.
#   C14 IC 미소비.
#   C15 팩터 DB 미접근 — 회계 원값 패널만 읽는다(커넥터 대상 아님).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

.TAG <- "[2511.12129]"

# ── 논문 명시 상수 ────────────────────────────────────────────────────────────
.N_TEST_Q    <- 4L      # "one-year window for testing"
.TRAIN_MIN_Q <- 16L     # "ranges from 16-quarter (4-year)"
.TRAIN_MAX_Q <- 40L     # "to a maximum of 40-quarter (10-year)"
.TOP_FRAC    <- 0.20    # "top 20% stocks from each sector"
.W_CAP       <- 0.05    # "5% maximum position size"
.COV_WIN_D   <- 365L    # "use 1 year historical daily return"

# ── 논문이 주지 않아 내가 정한 값 (전부 FIDELITY.json 의 changed 에 신고) ──────
.MISS_MAX    <- 0.05    # 논문 규칙 "factor with >5% missing is deleted" 의 as-of 판
.MIN_FEAT    <- 5L      # 생존 특성이 이보다 적으면 그 섹터-분기는 건너뜀
.MIN_TRAIN_N <- 40L     # 학습 행 하한
.MIN_TEST_N  <- 20L     # 평가 행 하한
.MIN_HIST_D  <- 120L    # 직전 252 거래행 중 유한수익 최소 관측(공분산 추정 가능성)
.MIN_COV_ROW <- 30L     # 공분산 창 최소 일수 (미달이면 동일비중)
.STALE_D     <- 730     # 회계 가용일이 시그널일보다 이만큼 오래되면 결측 처리
.RF_TREES    <- 100L
.GBM_TREES   <- 100L
.RIDGE_LAM   <- seq(0, 50, by = 0.5)
.SEED        <- 20251115L
.COV_EPS     <- 1e-6    # 공분산 수치 안정화 (평균 분산 대비 비율)

.FEAT <- c("RevGrowth", "EPS", "ROA", "ROE", "NetMargin", "GrossMargin",
           "OperMargin", "PE", "PS", "PB", "PCF", "EntMult", "EVtoCF",
           "LTDebtToAsset", "DebtToEquity", "CashRatio", "QuickRatio",
           "WorkCapRatio", "DaysInv", "DaysPay")          # Table I = 20종
stopifnot(length(.FEAT) == 20L)

# 분모 가드: 분모가 유한하고 부호 조건을 만족할 때만 값을 낸다(아니면 NA).
.dv  <- function(a, b) fifelse(is.finite(a) & is.finite(b) & b > 0,  a / b, NA_real_)
.dvs <- function(a, b) fifelse(is.finite(a) & is.finite(b) & b != 0, a / b, NA_real_)

# =============================================================================
# 1. 일간 패널 — RAWDATA 비파괴 복사본
#    열 정체: Close = 수정주가 · Size = 시가총액(KRW) · Sector = WI26 대분류
# =============================================================================
.need <- c("Date", "Ticker", "Close", "Size", "K200", "KQ150")
stopifnot(all(.need %in% names(RAWDATA)))
.has_sec <- "Sector" %in% names(RAWDATA)
.has_ret <- "Ret"    %in% names(RAWDATA)
.cols <- c(.need, if (.has_sec) "Sector", if (.has_ret) "Ret")
.rd <- RAWDATA[, .cols, with = FALSE]
if (!inherits(.rd$Date, "Date")) .rd[, Date := as.Date(Date)]
.rd[, Ticker := as.character(Ticker)]
.rd <- .rd[is.finite(Close) & Close > 0]
.rd <- unique(.rd, by = c("Ticker", "Date"))
setorder(.rd, Ticker, Date)
.rd[, MEM := (K200 %in% TRUE) | (KQ150 %in% TRUE)]
if (.has_sec) .rd[, SEC := as.character(Sector)] else .rd[, SEC := NA_character_]
.rd[is.na(SEC) | !nzchar(SEC), SEC := "UNKNOWN"]
# 수익률: 인프라 열이 있으면 그대로, 없으면 종가비 — shift 는 뒤로만 (t-1)
if (.has_ret) .rd[, Ret := as.numeric(Ret)] else .rd[, Ret := Close / shift(Close, 1L) - 1, by = Ticker]

# 보유 가능성(공분산 추정 가능성): 직전 252 거래행 안의 유한수익 관측 수
.rd[, okr := as.integer(is.finite(Ret))]
.rd[, nhist := frollsum(okr, 252L, align = "right"), by = Ticker]

# =============================================================================
# 2. 거래일 격자 — 2/5/8/11월 마지막 거래일 (→ 집행 3/1 · 6/1 · 9/1 · 12/1)
# =============================================================================
.rd[, MI := year(Date) * 12L + month(Date)]
.mev <- .rd[, .(MEnd = max(Date)), by = MI]
setorder(.mev, MI)
.mev <- .mev[MI < max(MI)]                                  # 진행 중 부분월 제외
.mev[, MO := ((MI - 1L) %% 12L) + 1L]
.TD <- sort(.mev[MO %in% c(2L, 5L, 8L, 11L)]$MEnd)
if (length(.TD) < (.TRAIN_MIN_Q + .N_TEST_Q + 2L))
  stop(sprintf("%s 거래일 격자 %d개 — RAWDATA 날짜 범위 확인", .TAG, length(.TD)))
.TDIX <- data.table(Date = .TD, k = seq_along(.TD))

# =============================================================================
# 3. 적격 집합 + 목표변수 (1분기 forward log-return)
# =============================================================================
.elig <- .rd[Date %in% .TD & MEM %in% TRUE & is.finite(Size) & Size > 0 &
               is.finite(nhist) & nhist >= .MIN_HIST_D,
             .(Date, Ticker, Close, Size, SEC)]
.elig <- merge(.elig, .TDIX, by = "Date")

# 다음 거래일 종가: 멤버십과 무관한 전 종목 가격패널에서(라벨 생존편향 제거).
#   원천의 인덱스를 k-1 로 **내려** 붙인다 — lead · 음수 shift 없이 같은 뜻이 된다.
.pxa <- merge(.rd[Date %in% .TD, .(Date, Ticker, Close)], .TDIX, by = "Date")
.nxp <- .pxa[, .(Ticker, k = k - 1L, C_end = Close)]
.elig <- merge(.elig, .nxp, by = c("Ticker", "k"), all.x = TRUE)
.elig[, y := log(C_end / Close)]
.elig[!is.finite(y), y := NA_real_]
.elig[, C_end := NULL]
rm(.pxa, .nxp)

# =============================================================================
# 4. 회계 원값 패널 (3원천) → (Ticker, 가용일 FD) 단위 TTM 행
#    ★세 원천은 주기가 다르므로 TTM · 전년비를 **각자의 주기 안에서** 먼저 만든 뒤
#      합친다. 이음매에서 분기합과 1년치 값을 섞지 않기 위해서다.
# =============================================================================
.ROOT  <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", ""))
.CACHE <- file.path(.ROOT, ".cache")
.P_MRG <- file.path(.CACHE, "fundamental_merged.parquet")
.P_DQT <- file.path(.CACHE, "fundamental_dart_quarterly.parquet")
if (!file.exists(.P_MRG)) stop(sprintf("%s 회계 패널 부재: %s", .TAG, .P_MRG))
if (!file.exists(.P_DQT)) stop(sprintf("%s 회계 패널 부재: %s", .TAG, .P_DQT))

.ITEMS <- c("Revenue", "COGS", "GrossProfit", "OperatingProfit", "PretaxIncome",
            "TaxExpense", "NetIncome", "DepAmort", "OperatingCF", "TotalAssets",
            "CurrentAssets", "CashAndEquiv", "Inventory", "TotalLiab",
            "CurrentLiab", "AccountsPay", "TotalEquity")
.FLOW  <- c("Revenue", "COGS", "GrossProfit", "OperatingProfit", "PretaxIncome",
            "TaxExpense", "NetIncome", "DepAmort", "OperatingCF")
.FLOWT <- paste0(.FLOW, "_T")

.fm <- as.data.table(read_parquet(
  .P_MRG, col_select = c("Ticker", "Period", "Period_Date", "Factor_Date",
                         "Item", "Value", "Source")))
.fm <- .fm[Item %in% .ITEMS & is.finite(Value)]
.fm[, Ticker := as.character(Ticker)]
.fm[, PD  := as.Date(Period_Date)]
.fm[, FDv := as.Date(Factor_Date)]
.fm <- .fm[!is.na(PD) & !is.na(FDv)]
# 같은 (Ticker, Period, Item) 이 원천별로 겹치면 원값(XLSX) 우선, 파생은 보충
.fm[, pri := fifelse(Source %in% "XLSX", 1L, 2L)]
setorder(.fm, Ticker, Period, Item, pri)
.fm <- unique(.fm, by = c("Ticker", "Period", "Item"))

.wide_of <- function(src) {
  d <- .fm[Source %in% src]
  if (!nrow(d)) return(NULL)
  fdt <- d[, .(FDv = max(FDv), PD = max(PD)), by = .(Ticker, Period)]
  w <- dcast(d, Ticker + Period ~ Item, value.var = "Value",
             fun.aggregate = function(v) v[1])
  w <- merge(w, fdt, by = c("Ticker", "Period"))
  for (cc in .ITEMS) if (!cc %in% names(w)) set(w, j = cc, value = NA_real_)
  w[]
}

# ---- 4a. XLSX 분기 원값 (단일분기 유량 전제 — 저장소 규약) -------------------
.wx <- .wide_of(c("XLSX", "xlsx_derived"))
if (!is.null(.wx)) {
  .wx <- .wx[month(PD) %in% c(3L, 6L, 9L, 12L)]
  .wx[, QI := year(PD) * 4L + ((month(PD) - 1L) %/% 3L)]
  .wx <- unique(.wx, by = c("Ticker", "QI"))
  setorder(.wx, Ticker, QI)
  for (cc in .FLOW) .wx[, (paste0(cc, "_T")) := frollsum(get(cc), 4L, align = "right"), by = Ticker]
  .wx[, QI3 := shift(QI, 3L), by = Ticker]
  .bad <- which(!(is.finite(.wx$QI3) & (.wx$QI - .wx$QI3) %in% 3L))
  for (cc in .FLOWT) set(.wx, .bad, cc, NA_real_)
  .wx[, RevPY := shift(Revenue_T, 4L), by = Ticker]
  .wx[, QI4 := shift(QI, 4L), by = Ticker]
  .wx[!(is.finite(QI4) & (QI - QI4) %in% 4L), RevPY := NA_real_]
  # 12월 결산분 가용일 보수화: 원본 +45d(≈익년 2/14) → 익년 3/31 (C4 lag 강화)
  .wx[, FD := FDv]
  .wx[month(PD) %in% 12L, FD := as.Date(sprintf("%d-03-31", year(PD) + 1L))]
}

# ---- 4b. DART 사업연도 원값 — 유량이 이미 1년치 ------------------------------
.wa <- .wide_of("DART")
if (!is.null(.wa)) {
  .wa[, YI := year(PD)]
  .wa <- unique(.wa, by = c("Ticker", "YI"))
  setorder(.wa, Ticker, YI)
  for (cc in .FLOW) .wa[, (paste0(cc, "_T")) := get(cc)]
  .wa[, RevPY := shift(Revenue_T, 1L), by = Ticker]
  .wa[, YI1 := shift(YI, 1L), by = Ticker]
  .wa[!(is.finite(YI1) & (YI - YI1) %in% 1L), RevPY := NA_real_]
  .wa[, FD := as.Date(sprintf("%d-03-31", YI + 1L))]   # 사업보고서 가용일 (C4)
}

# ---- 4c. DART 분기 TTM 패널 — 유량이 이미 trailing 4개분기 합 ----------------
.dq <- as.data.table(read_parquet(.P_DQT))
.dq[, Ticker := as.character(Ticker)]
for (cc in .ITEMS) if (!cc %in% names(.dq)) set(.dq, j = cc, value = NA_real_)
.dq[, FD := as.Date(Factor_Date)]
.dq <- .dq[!is.na(FD)]
.dq[, QI := as.integer(bsns_year) * 4L + (as.integer(quarter) - 1L)]
.dq <- unique(.dq, by = c("Ticker", "QI"))
setorder(.dq, Ticker, QI)
for (cc in .FLOW) .dq[, (paste0(cc, "_T")) := get(cc)]
.dq[, RevPY := shift(Revenue_T, 4L), by = Ticker]
.dq[, QI4 := shift(QI, 4L), by = Ticker]
.dq[!(is.finite(QI4) & (QI - QI4) %in% 4L), RevPY := NA_real_]

# ---- 4d. 통합 ----------------------------------------------------------------
.slim <- function(d, pri) {
  if (is.null(d) || !nrow(d)) return(NULL)
  data.table(
    Ticker = d$Ticker, FD = d$FD, PRI = pri,
    REV = d$Revenue_T, CGS = d$COGS_T, GPR = d$GrossProfit_T,
    OPR = d$OperatingProfit_T, PTI = d$PretaxIncome_T, TAX = d$TaxExpense_T,
    NIR = d$NetIncome_T, DAM = d$DepAmort_T, OCF = d$OperatingCF_T,
    REVPY = d$RevPY, TA = d$TotalAssets, CA = d$CurrentAssets,
    CSH = d$CashAndEquiv, IVT = d$Inventory, TL = d$TotalLiab,
    CL = d$CurrentLiab, APY = d$AccountsPay, EQ = d$TotalEquity)[!is.na(FD)]
}
.FDP <- rbindlist(Filter(Negate(is.null), list(
  .slim(.dq, 1L), .slim(.wx, 2L), .slim(.wa, 3L))), use.names = TRUE)
if (!nrow(.FDP)) stop(sprintf("%s 회계 패널 통합 결과 0행", .TAG))
setorder(.FDP, Ticker, FD, PRI)
.FDP <- unique(.FDP, by = c("Ticker", "FD"))
.FDP[, PRI := NULL]
# 순이익: 원값 우선, 없으면 세전이익 − 법인세비용 (XLSX 원항목 규약)
.FDP[, NIT := fifelse(is.finite(NIR), NIR,
                      fifelse(is.finite(PTI) & is.finite(TAX), PTI - TAX, NA_real_))]
.FDP[, GPT := fifelse(is.finite(GPR), GPR,
                      fifelse(is.finite(REV) & is.finite(CGS), REV - CGS, NA_real_))]
.FDP[, c("NIR", "PTI", "TAX", "GPR") := NULL]
.FDP[, FD_src := FD]
rm(.fm, .wx, .wa, .dq)
invisible(gc(verbose = FALSE))

# =============================================================================
# 5. 회계 → 거래일 매핑 (가용일 <= 시그널일 · 뒤로만 구르는 rolling join)
# =============================================================================
.gr <- unique(.elig[, .(Ticker, Date)])
setkey(.FDP, Ticker, FD)
setkey(.gr, Ticker, Date)
.mp <- .FDP[.gr, on = .(Ticker, FD = Date), roll = TRUE]
setnames(.mp, "FD", "Date")
.mp <- .mp[!is.na(FD_src) & as.numeric(Date - FD_src) <= .STALE_D]
.mp[, FD_src := NULL]
.elig <- merge(.elig, .mp, by = c("Ticker", "Date"))
if (!nrow(.elig)) stop(sprintf("%s 회계 매핑 후 0행", .TAG))

# =============================================================================
# 6. Table I 20지표 산출 (전부 그 행 하나 안에서 — 횡단면 · 시계열 통계 미사용)
# =============================================================================
.elig[, SH := .dv(Size, Close)]                              # 수정주가 기준 주식수
.elig[, EV := fifelse(is.finite(Size) & is.finite(TL) & is.finite(CSH),
                      Size + TL - CSH, NA_real_)]
.elig[, EBTD := fifelse(is.finite(OPR), OPR + fifelse(is.finite(DAM), DAM, 0), NA_real_)]

.elig[, RevGrowth     := fifelse(is.finite(REV) & is.finite(REVPY) & REVPY > 0, REV / REVPY - 1, NA_real_)]
.elig[, EPS           := .dv(NIT, SH)]
.elig[, ROA           := .dv(NIT, TA)]
.elig[, ROE           := .dv(NIT, EQ)]
.elig[, NetMargin     := .dv(NIT, REV)]
.elig[, GrossMargin   := .dv(GPT, REV)]
.elig[, OperMargin    := .dv(OPR, REV)]
.elig[, PE            := .dvs(Size, NIT)]
.elig[, PS            := .dv(Size, REV)]
.elig[, PB            := .dv(Size, EQ)]
.elig[, PCF           := .dvs(Size, OCF)]
.elig[, EntMult       := .dvs(EV, EBTD)]
.elig[, EVtoCF        := .dvs(EV, OCF)]
.elig[, LTDebtToAsset := fifelse(is.finite(TL) & is.finite(CL) & is.finite(TA) & TA > 0,
                                 (TL - CL) / TA, NA_real_)]
.elig[, DebtToEquity  := .dv(TL, EQ)]
.elig[, CashRatio     := .dv(CSH, CL)]
.elig[, QuickRatio    := fifelse(is.finite(CA) & is.finite(IVT) & is.finite(CL) & CL > 0,
                                 (CA - IVT) / CL, NA_real_)]
.elig[, WorkCapRatio  := .dv(CA, CL)]
.elig[, DaysInv       := fifelse(is.finite(IVT) & is.finite(CGS) & CGS > 0, 365 * IVT / CGS, NA_real_)]
.elig[, DaysPay       := fifelse(is.finite(APY) & is.finite(CGS) & CGS > 0, 365 * APY / CGS, NA_real_)]

for (f in .FEAT) set(.elig, which(!is.finite(.elig[[f]])), f, NA_real_)
MT <- .elig[, c("Date", "k", "Ticker", "SEC", "y", .FEAT), with = FALSE]
.SECLV <- sort(unique(MT$SEC))
setkey(MT, k)

cat(sprintf("%s 패널: 거래일 %d개 (%s ~ %s) · 적격행 %s · 종목 %d · 섹터 %d\n",
            .TAG, length(.TD), as.character(min(.TD)), as.character(max(.TD)),
            format(nrow(MT), big.mark = ","), uniqueN(MT$Ticker), length(.SECLV)))

# =============================================================================
# 7. 모형 5종 — 학습창 적합 → 평가창 MSE → argmin 선택 → 당기 예측
#    ★모든 적합은 k <= n-1 인, 목표가 이미 실현된 과거 관측 위에서만 일어난다.
# =============================================================================
.mfit <- function(m, dtr, dte, dcu, sd_i) {
  if (identical(m, "lm")) {
    f <- stats::lm(y ~ ., data = dtr)
    return(list(te = as.numeric(stats::predict(f, newdata = dte)),
                cu = as.numeric(stats::predict(f, newdata = dcu))))
  }
  if (identical(m, "stepwise")) {
    f <- stats::step(stats::lm(y ~ ., data = dtr), direction = "both", trace = 0L)
    return(list(te = as.numeric(stats::predict(f, newdata = dte)),
                cu = as.numeric(stats::predict(f, newdata = dcu))))
  }
  if (identical(m, "ridge")) {
    f  <- MASS::lm.ridge(y ~ ., data = dtr, lambda = .RIDGE_LAM)
    cf <- stats::coef(f)[which.min(f$GCV), ]
    return(list(te = as.numeric(cbind(1, as.matrix(dte)) %*% cf),
                cu = as.numeric(cbind(1, as.matrix(dcu)) %*% cf)))
  }
  if (identical(m, "randomforest")) {
    set.seed(sd_i)
    f <- randomForest::randomForest(x = dtr[, -1L, drop = FALSE], y = dtr$y,
                                    ntree = .RF_TREES)
    return(list(te = as.numeric(stats::predict(f, newdata = dte)),
                cu = as.numeric(stats::predict(f, newdata = dcu))))
  }
  if (identical(m, "gbm")) {
    set.seed(sd_i)
    f <- gbm::gbm.fit(x = dtr[, -1L, drop = FALSE], y = dtr$y, distribution = "gaussian",
                      n.trees = .GBM_TREES, interaction.depth = 1L, shrinkage = 0.1,
                      bag.fraction = 0.5, n.minobsinnode = 10L, verbose = FALSE)
    return(list(te = as.numeric(stats::predict(f, newdata = dte, n.trees = .GBM_TREES)),
                cu = as.numeric(stats::predict(f, newdata = dcu, n.trees = .GBM_TREES))))
  }
  NULL
}
.MODELS <- c("lm", "ridge", "stepwise", "randomforest", "gbm")

.pick <- vector("list", length(.TD))     # 선정 종목 (Date, Ticker)
.scor <- vector("list", length(.TD))     # 진단용 점수 (Date, Ticker, Score)
.selcnt <- setNames(integer(length(.MODELS)), .MODELS)
.mfail  <- setNames(integer(length(.MODELS)), .MODELS)   # 모형별 적합 실패 — 침묵시키지 않는다
.n_cell <- 0L; .n_skip <- 0L

for (n in seq_along(.TD)) {
  if (n < (.TRAIN_MIN_Q + .N_TEST_Q + 1L)) next
  k_test <- (n - .N_TEST_Q):(n - 1L)
  L      <- min(.TRAIN_MAX_Q, n - .N_TEST_Q - 1L)
  if (L < .TRAIN_MIN_Q) next
  k_train <- (n - .N_TEST_Q - L):(n - .N_TEST_Q - 1L)
  # ★PIT 경계 — 평가창 마지막 관측의 목표가 실현되는 시점이 현재 시그널일 이하
  stopifnot(max(k_test) + 1L <= n, max(k_train) < min(k_test))

  cur_all <- MT[.(n), nomatch = 0L]
  if (!nrow(cur_all)) next
  tr_all <- MT[.(k_train), nomatch = 0L][is.finite(y)]
  te_all <- MT[.(k_test),  nomatch = 0L][is.finite(y)]
  if (!nrow(tr_all) || !nrow(te_all)) next

  for (sc in sort(unique(cur_all$SEC))) {
    cu0 <- cur_all[SEC %in% sc]
    tr0 <- tr_all[SEC %in% sc]
    te0 <- te_all[SEC %in% sc]
    if (!nrow(cu0) || !nrow(tr0) || !nrow(te0)) { .n_skip <- .n_skip + 1L; next }

    # ── 논문 결측 규칙의 as-of 판: 결측률은 그 시점의 (학습+평가) 창에서만 잰다
    wn <- rbind(tr0[, .FEAT, with = FALSE], te0[, .FEAT, with = FALSE])
    mr <- vapply(.FEAT, function(f) mean(is.na(wn[[f]])), numeric(1))
    keep <- .FEAT[is.finite(mr) & mr <= .MISS_MAX]
    if (length(keep) < .MIN_FEAT) { .n_skip <- .n_skip + 1L; next }

    trc <- tr0[stats::complete.cases(tr0[, keep, with = FALSE])]
    tec <- te0[stats::complete.cases(te0[, keep, with = FALSE])]
    cuc <- cu0[stats::complete.cases(cu0[, keep, with = FALSE])]
    if (!nrow(cuc)) { .n_skip <- .n_skip + 1L; next }
    if (nrow(trc) < .MIN_TRAIN_N || uniqueN(trc$k) < .TRAIN_MIN_Q) { .n_skip <- .n_skip + 1L; next }
    if (nrow(tec) < .MIN_TEST_N  || uniqueN(tec$k) < .N_TEST_Q)    { .n_skip <- .n_skip + 1L; next }

    # 학습창에서 분산 0인 열 제거 (lm/step/ridge 특이행렬 방지)
    sdv  <- vapply(keep, function(f) stats::sd(trc[[f]]), numeric(1))
    keep <- keep[is.finite(sdv) & sdv > 0]
    if (length(keep) < .MIN_FEAT) { .n_skip <- .n_skip + 1L; next }

    dtr <- data.frame(y = trc$y, as.matrix(trc[, keep, with = FALSE]))
    dte <- data.frame(as.matrix(tec[, keep, with = FALSE]))
    dcu <- data.frame(as.matrix(cuc[, keep, with = FALSE]))
    sd_i <- .SEED + n * 1000L + match(sc, .SECLV)

    res <- vector("list", length(.MODELS))
    mse <- rep(NA_real_, length(.MODELS))
    for (mi in seq_along(.MODELS)) {
      r <- tryCatch(.mfit(.MODELS[mi], dtr, dte, dcu, sd_i), error = function(e) NULL)
      if (is.null(r) || !all(is.finite(r$te)) || !all(is.finite(r$cu))) {
        .mfail[mi] <- .mfail[mi] + 1L; next
      }
      res[[mi]] <- r
      mse[mi]   <- mean((r$te - tec$y)^2)
    }
    if (!any(is.finite(mse))) { .n_skip <- .n_skip + 1L; next }

    # 2) "choose the model that has the lowest MSE in that certain period"
    sel_i <- which.min(mse)
    .selcnt[sel_i] <- .selcnt[sel_i] + 1L
    .n_cell <- .n_cell + 1L
    pr <- res[[sel_i]]$cu

    # 3) "pick up top 20% stocks from each sector" — 동값은 종목코드로 결정론적 분해
    ordi <- order(-pr, cuc$Ticker)
    kk   <- max(1L, as.integer(ceiling(.TOP_FRAC * nrow(cuc))))
    .pick[[n]] <- rbind(.pick[[n]],
                        data.table(Date = .TD[n], Ticker = cuc$Ticker[ordi[seq_len(kk)]]))
    .scor[[n]] <- rbind(.scor[[n]],
                        data.table(Date = .TD[n], Ticker = cuc$Ticker,
                                   Score = (frank(pr, ties.method = "average") - 0.5) / length(pr)))
  }
}

PICK <- rbindlist(Filter(Negate(is.null), .pick), use.names = TRUE)
if (!nrow(PICK)) stop(sprintf("%s 선정 종목 0건 — 학습창 요건 확인", .TAG))
FACTORS <- rbindlist(Filter(Negate(is.null), .scor), use.names = TRUE)[, .(Date, Ticker, Score)]

cat(sprintf("%s 섹터-분기 셀 %d (건너뜀 %d) · 모형 선택 빈도 %s\n", .TAG, .n_cell, .n_skip,
            paste(sprintf("%s:%d", names(.selcnt), .selcnt), collapse = " ")))
cat(sprintf("%s 모형별 적합 실패 %s (0이 아니면 그 모형은 그만큼 선택 후보에서 빠졌다)\n",
            .TAG, paste(sprintf("%s:%d", names(.mfail), .mfail), collapse = " ")))

# =============================================================================
# 8. 배분 = minimum-variance (논문 결론 칸) · long-only · Σw = 1 · w <= 5%
#    공분산 = (시그널일 − 365d, 시그널일] 일간수익 — 창의 종점이 t-1 이다.
# =============================================================================
.RETD <- .rd[, .(Date, Ticker, Ret)]
setkey(.RETD, Ticker, Date)
.dts <- sort(unique(PICK$Date))
.wl <- vector("list", length(.dts))
.qp_fb <- 0L

for (.i in seq_along(.dts)) {
  d  <- .dts[.i]
  tk <- sort(unique(PICK[Date %in% d]$Ticker))
  if (length(tk) < 2L) {
    .wl[[.i]] <- data.table(Date = d, Ticker = tk, Weight = 1, Leg = "long"); next
  }
  w0 <- .RETD[.(tk), nomatch = 0L][Date > (d - .COV_WIN_D) & Date <= d]
  wm <- if (nrow(w0)) dcast(w0, Date ~ Ticker, value.var = "Ret") else NULL
  if (is.null(wm) || nrow(wm) < .MIN_COV_ROW || ncol(wm) < 3L) {
    .qp_fb <- .qp_fb + 1L
    .wl[[.i]] <- data.table(Date = d, Ticker = tk, Weight = 1 / length(tk), Leg = "long"); next
  }
  Rm <- as.matrix(wm[, -1L, with = FALSE])
  Rm[!is.finite(Rm)] <- 0                                   # 미거래일 = 가격 불변
  nm <- colnames(Rm); N <- length(nm)
  # 창 안 표본공분산 (창의 종점 = 시그널일) + 수치 안정화 대각
  Cv <- stats::cov(Rm, use = "everything")
  Sg <- Cv + (.COV_EPS * mean(diag(Cv)) + 1e-12) * diag(N)
  cap <- max(.W_CAP, 1 / N + 1e-9)
  sol <- tryCatch(quadprog::solve.QP(Dmat = Sg, dvec = rep(0, N),
                                     Amat = cbind(rep(1, N), diag(N), -diag(N)),
                                     bvec = c(1, rep(0, N), rep(-cap, N)), meq = 1L),
                  error = function(e) NULL)
  w <- if (is.null(sol)) rep(1 / N, N) else pmax(sol$solution, 0)
  if (is.null(sol) || !all(is.finite(w)) || sum(w) <= 0) { .qp_fb <- .qp_fb + 1L; w <- rep(1 / N, N) }
  dtw <- data.table(Date = d, Ticker = nm, Weight = w, Leg = "long")[Weight > 1e-8]
  dtw[, Weight := Weight / sum(Weight)]                     # 미소 비중 제거 후 재정규화
  .wl[[.i]] <- dtw
}

PORTFOLIO <- rbindlist(Filter(Negate(is.null), .wl), use.names = TRUE)
PORTFOLIO <- PORTFOLIO[is.finite(Weight) & Weight > 0]
setorder(PORTFOLIO, Date, -Weight)
FACTORS <- FACTORS[Date %in% unique(PORTFOLIO$Date)]

.nb <- PORTFOLIO[, .(n = .N, sw = sum(Weight), mx = max(Weight)), by = Date]
cat(sprintf("%s PORTFOLIO %s행 · 리밸 %d회 (%s ~ %s) · 보유 중앙 %.0f · 최대 %d · Sw [%.4f, %.4f] · 최대비중 %.3f · QP 폴백 %d\n",
            .TAG, format(nrow(PORTFOLIO), big.mark = ","), nrow(.nb),
            as.character(min(.nb$Date)), as.character(max(.nb$Date)),
            stats::median(.nb$n), max(.nb$n), min(.nb$sw), max(.nb$sw), max(.nb$mx), .qp_fb))
cat(sprintf("%s FACTORS %s행 (섹터 내 예측수익 백분위 — 진단 전용, 측정은 PORTFOLIO)\n",
            .TAG, format(nrow(FACTORS), big.mark = ",")))

rm(.rd, .elig, .mp, .gr, .FDP, .RETD, .wl, .pick, .scor, PICK, MT)
invisible(gc(verbose = FALSE))
