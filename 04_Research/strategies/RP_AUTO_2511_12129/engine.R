# =============================================================================
# engine.R — RP_AUTO_2511_12129   ★재구현 2판 (1판은 engine.rejected1.R)
# "A Practical Machine Learning Approach for Dynamic Stock Recommendation"
#   arXiv:2511.12129  ·  전문 = arxiv.org/html/2511.12129v1
#
# ★선언 정본 = FIDELITY.json 이다. 이 주석은 사본이고, 주석과 FIDELITY 가 어긋나면
#   FIDELITY 가 맞다. (1판이 주석에 사실과 다른 문장을 남겨 감사에서 지적됐다.)
#
# ===== 논문 원문 (그대로 옮긴 것) =============================================
#   초록   "buy and hold the top 20% stocks dynamically"
#   §II-A  "Rolling windows for training ranges from 16-quarter (4-year) to a
#          maximum of 40-quarter (10-year). This training rolling window is
#          followed by an one-year window for testing."
#          "We also extend the trade date by two months lag beyond the standard
#          quarter end date ... Thus for the quarter between 04/01 and 06/30,
#          our trade date is adjusted to 09/01 (same method for other three
#          quarters)."                       → 거래일 3/1 · 6/1 · 9/1 · 12/1
#   §II-B  "We use all historical S&P 500 component stocks (about 1142 stocks)"
#          "we split the dataset by the Global Industry Classification Standard
#          (GICS) sectors"
#          "if one factor has more than 5% missing data, we delete this factor;
#          if a certain stock generates the most missing data, we delete this
#          stock ... Finally, we delete this 7% missing data."
#          ★명시된 레코드 삭제는 위 결측 규칙과 rdq>거래일 0.84% 둘뿐이다 —
#            **결산월 기준 삭제 조항은 없다**(1판이 넣었던 필터를 제거한 근거).
#   Table I 20개 재무비율
#   §II-C  식(1) r_{T+f,i} = ln(S_{T+f,i}/S_{T,i}) — 1분기 forward log-return
#          모형 5종 = linear / ridge / stepwise / random forest / GBM
#   §II-D  Step1 5모형 MSE → Step2 argmin → Step3 "pick up top 20% stocks from
#          each sector" → "We finish these steps for all eleven GICS sectors."
#   §III-A "Expected return: predicted return of next quarter" ·
#          "Covariance matrix: use 1 year historical daily return" ·
#          "Long only: upper bound 5% and Lower bound 0%" ·
#          "Fully invest our capital: sum of weights=100%" · "Take no leverage"
#          min-variance = "almost the same ... except that we set the expected
#          return to be 0"
#   §III-B 식(5) Σ|S_t,i − S_{t−1,i}|·P_i × 0.1%   → commission_paper = 0.001
#   §IV    "we choose the min-variance as our portfolio allocation method"
#
# ===== 1판 감사 지적에 대한 처분 (전부 FIDELITY.json 에 항목으로 재신고) ======
#   (a) [signal] EPS 분모 Size/Close = 시그널일 이후 액면분할로 결정되는 조정주식수
#       → **EPS 를 특성 집합에서 제거**했다. 이 저장소의 주식수 후보(Size/Close ·
#       ISSD '수정'발행주식수)는 전부 추출시점 기준으로 소급 조정돼 있고, 조정
#       패널에는 분할 사건 정보가 남지 않아(Size/Close 는 분할에 연속) 시그널일
#       기준 주식수를 복원할 방법이 없다. 대체 특성도 넣지 않았다(19종으로 적합).
#   (b) [timing] 3월 거래일의 실효 회계 lag 5개월 → 거래일 격자는 논문 그대로 두고
#       **그 귀결을 FIDELITY 에 명시**했다. KR 사업보고서 법정기한이 익년 3/31 이라
#       3/1 거래일에 12/31 분기 회계를 쓰는 것은 미래참조다(PIT 우선).
#   (c) [universe] KQ150 멤버십이 2010-01-29 부터 존재한다는 사실을 신고했다.
#   (d) [portfolio] 실현 breadth 의 기전을 정정 신고 + 섹터를 WICS 대분류 10군으로
#       롤업해(논문 GICS 11 에 대응) 선정집합이 20종 이하로 내려가 min-variance 가
#       등가중으로 붕괴하는 구조를 줄였다.
#   (e) [cost] 체결가가 사실상 시그널일 종가(close_d_legacy)라는 것, 비용 기준이
#       드리프트 전 목표비중이라는 것 — 둘 다 하네스 층 규약으로 신고했다.
#   (f) [undeclared] 결산월(month(Period_Date) ∈ {3,6,9,12}) 필터를 **삭제**했다.
#       분기 연속성은 달력 분기가 아니라 **월 인덱스 간격 3개월**로 판정한다.
#   (g) [undeclared] 실효 개시 시점을 날짜로 단정하지 않는다 — 규칙만 적는다.
#
# ===== 산출 형태 ==============================================================
#   PORTFOLIO(Date, Ticker, Weight, Leg) — 논문 비중(min-variance)이 곧 산출이다.
#     FIDELITY.portfolio_spec = {"construction":"engine_direct"}.
#   FACTORS(Date, Ticker, Score) — 섹터 내 예측수익 백분위(러너 IC/FF 진단 전용).
#     측정에 들어가는 비중은 PORTFOLIO 뿐이다(러너 engine_direct 분기).
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) ==
#   시간 경계: 시그널일 d = 2/5/8/11월 마지막 거래일. 집행 = 익월 첫 거래일.
#     모든 특성·목표·공분산 창의 **정보 종점이 d 이하**다. 1판에서 유일하게
#     이 명제가 깨진 자리(EPS 분모)는 그 특성을 제거해 닫았다.
#   C1  전 표본 통계 0건. 통계는 (a) 과거로 닫힌 학습창 (b) 과거로 닫힌 평가창
#       (c) 그 날짜 하나의 횡단면 (d) (d−365, d] 일간 공분산 창뿐이다.
#       모형 선택이 쓰는 MSE 는 **거래 이전에 목표가 이미 실현된** 4분기 평가창에서만
#       나온다(루프 안 stopifnot 이 강제). 결측률 5% 규칙도 그 시점 창에서만 잰다.
#       scale() · 전표본 mean/sd/quantile 0건.
#   C2  same-day 순환참조 없음 — 목표는 k→k+1 구간 수익이고 학습은 k ≤ n−1 만.
#   C3  같은 기간 집계 → 적용 없음.
#   C4  회계 가용일 = 분기말 + 45일, **12월 결산분은 익년 3/31**(pit.md C4 ·
#       parse_fundamental_xlsx.R:205-209 규약을 엔진 안에서 재현). 패널 Factor_Date
#       가 더 보수적이면 그쪽을 쓴다(pmax — 공격적 방향으로는 절대 안 간다).
#       비달력 분기말 기업은 사업연도 말 분기를 식별할 수 없어 전 분기에 90일을 건다.
#   C5  오버레이 없음.
#   C6  유니버스 = 그 날짜 행의 K200/KQ150 멤버십(시변). 목표수익 가격은 멤버십과
#       무관한 전 종목 가격패널에서 가져와 라벨 생존편향을 없앴다.
#   C7  음수 shift · lead() · 수동 미래 인덱싱 0건. 다음 거래일 가격은 원천 쪽
#       인덱스를 k−1 로 **내려** 붙인다(미래를 당기지 않는다).
#   C8/C9  FM · VT · DD 미사용.   C10 유동성 스크린 미적용(FIDELITY 참조).
#   C11 외부 매크로 미사용.       C13 부호 반전 0건 — 예측수익 그대로 내림차순.
#   C14 IC 미소비.                C15 팩터 DB 미접근 — 회계 원값 패널만 읽는다.
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
.W_CAP       <- 0.05    # "upper bound 5%"
.COV_WIN_D   <- 365L    # "use 1 year historical daily return"
.MISS_MAX    <- 0.05    # "if one factor has more than 5% missing data, we delete this factor"

# ── 논문이 주지 않아 내가 정한 값 (전부 FIDELITY.json changed 에 신고) ────────
.MIN_FEAT    <- 5L      # 생존 특성이 이보다 적으면 그 섹터-분기는 건너뜀
.MIN_TRAIN_N <- 40L     # 학습 행 하한
.MIN_TEST_N  <- 20L     # 평가 행 하한
.MIN_HIST_D  <- 120L    # 직전 252 거래행 중 유한수익 최소 관측(공분산 추정 가능성)
.MIN_COV_ROW <- 30L     # 공분산 창 최소 일수 (미달이면 동일비중)
.STALE_D     <- 730     # 회계 가용일이 시그널일보다 이만큼 오래되면 결측 처리
.Q_LAG_D     <- 45L     # KR 분기·반기보고서 법정기한
.ANN_LAG_D   <- 90L     # KR 사업보고서 법정기한
.RF_TREES    <- 100L
.GBM_TREES   <- 100L
.RIDGE_LAM   <- seq(0, 50, by = 0.5)
.SEED        <- 20251115L
.COV_EPS     <- 1e-6    # 공분산 수치 안정화 (평균 분산 대비 비율)

# Table I 20종 중 **EPS 를 뺀 19종** — 제거 사유는 파일 머리 (a) · FIDELITY changed
.FEAT <- c("RevGrowth", "ROA", "ROE", "NetMargin", "GrossMargin", "OperMargin",
           "PE", "PS", "PB", "PCF", "EntMult", "EVtoCF",
           "LTDebtToAsset", "DebtToEquity", "CashRatio", "QuickRatio",
           "WorkCapRatio", "DaysInv", "DaysPay")
stopifnot(length(.FEAT) == 19L)

# 분모 가드: 분모가 유한하고 부호 조건을 만족할 때만 값을 낸다(아니면 NA).
.dv  <- function(a, b) fifelse(is.finite(a) & is.finite(b) & b > 0,  a / b, NA_real_)
.dvs <- function(a, b) fifelse(is.finite(a) & is.finite(b) & b != 0, a / b, NA_real_)

# =============================================================================
# 0. 섹터 — WI26 26군 → WICS 대분류 10군 롤업
#    논문은 GICS 11 섹터로 나눈다. RAWDATA$Sector 는 WI26 26군이라 섹터당 종목이
#    논문의 1/4 로 얇아진다. 매핑표 출처 = 저장소 내
#    04_Research/strategies/STR_1654_BCSNA/factor_engine.R:33-72 (WICS 공표 계층).
#    ★그 원판의 '철강' 키는 U+CCCA 오탈자라 여기서는 U+CCA0(철강)으로 바로잡았다.
#    키는 코드포인트(intToUtf8)로 박아 이 파일의 인코딩에 의존하지 않게 한다 —
#    매핑이 통째로 빗나가면 전 종목이 한 섹터가 되어 논문의 섹터중립이 조용히
#    사라지므로, 아래 §1 끝에 **커버리지 하드 가드**를 둔다(침묵 실패 금지).
# =============================================================================
.cp <- function(...) intToUtf8(c(...))      # 유니코드 코드포인트 -> 문자열
.SEP3 <- paste0("[", .cp(0x00B7, 0x30FB, 0xFF65), "/]")   # 가운뎃점 3종 + 슬래시
.sec_key <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  x <- gsub("[[:space:]]", "", x)
  x <- gsub(.SEP3, ",", x)                         # 구분자 표기차 -> 쉼표
  x <- gsub(.cp(0xFF08), "(", x, fixed = TRUE)     # 전각 괄호 -> 반각
  gsub(.cp(0xFF09), ")", x, fixed = TRUE)
}
.SECMAP <- c(
  setNames("Energy",      .cp(0xC5D0, 0xB108, 0xC9C0)),                          # 에너지
  setNames("Materials",   .cp(0xD654, 0xD559)),                                  # 화학
  setNames("Materials",   .cp(0xCCA0, 0xAC15)),                                  # 철강
  setNames("Materials",   .cp(0xBE44, 0xCCA0, 0x2C, 0xBAA9, 0xC7AC, 0xB4F1)),    # 비철,목재등
  setNames("Industrials", .cp(0xAE30, 0xACC4)),                                  # 기계
  setNames("Industrials", .cp(0xC870, 0xC120)),                                  # 조선
  setNames("Industrials", .cp(0xAC74, 0xC124, 0x2C, 0xAC74, 0xCD95, 0xAD00, 0xB828)),  # 건설,건축관련
  setNames("Industrials", .cp(0xC0C1, 0xC0AC, 0x2C, 0xC790, 0xBCF8, 0xC7AC)),    # 상사,자본재
  setNames("Industrials", .cp(0xC6B4, 0xC1A1)),                                  # 운송
  setNames("ConsDisc",    .cp(0xC790, 0xB3D9, 0xCC28)),                          # 자동차
  setNames("ConsDisc",    .cp(0xD654, 0xC7A5, 0xD488, 0x2C, 0xC758, 0xB958, 0x2C, 0xC644, 0xAD6C)),  # 화장품,의류,완구
  setNames("ConsDisc",    .cp(0xD638, 0xD154, 0x2C, 0xB808, 0xC800, 0xC11C, 0xBE44, 0xC2A4)),        # 호텔,레저서비스
  setNames("ConsDisc",    .cp(0xC18C, 0xB9E4, 0x28, 0xC720, 0xD1B5, 0x29)),      # 소매(유통)
  setNames("ConsDisc",    .cp(0xBBF8, 0xB514, 0xC5B4, 0x2C, 0xAD50, 0xC721)),    # 미디어,교육
  setNames("ConsStaples", .cp(0xD544, 0xC218, 0xC18C, 0xBE44, 0xC7AC)),          # 필수소비재
  setNames("Healthcare",  .cp(0xAC74, 0xAC15, 0xAD00, 0xB9AC)),                  # 건강관리
  setNames("Financials",  .cp(0xC740, 0xD589)),                                  # 은행
  setNames("Financials",  .cp(0xBCF4, 0xD5D8)),                                  # 보험
  setNames("Financials",  .cp(0xC99D, 0xAD8C)),                                  # 증권
  setNames("IT",          .cp(0xC18C, 0xD504, 0xD2B8, 0xC6E8, 0xC5B4)),          # 소프트웨어
  setNames("IT",          .cp(0xBC18, 0xB3C4, 0xCCB4)),                          # 반도체
  setNames("IT",          .cp(0xB514, 0xC2A4, 0xD50C, 0xB808, 0xC774)),          # 디스플레이
  setNames("IT",          .cp(0x49, 0x54, 0xAC00, 0xC804)),                      # IT가전
  setNames("IT",          .cp(0xAC00, 0xC804, 0x49, 0x54)),                      # 가전IT
  setNames("IT",          .cp(0xAC00, 0xC804)),                                  # 가전
  setNames("IT",          .cp(0x49, 0x54, 0xD558, 0xB4DC, 0xC6E8, 0xC5B4)),      # IT하드웨어
  setNames("Telecom",     .cp(0xD1B5, 0xC2E0, 0xC11C, 0xBE44, 0xC2A4)),          # 통신서비스
  setNames("Utilities",   .cp(0xC720, 0xD2F8, 0xB9AC, 0xD2F0))                   # 유틸리티
)
names(.SECMAP) <- .sec_key(names(.SECMAP))   # 키도 같은 정규화를 통과시킨다

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

# 섹터 롤업 — 미매핑은 "Other" 단일 버킷으로 모으고 그 이름을 로그에 드러낸다
if (.has_sec) .rd[, SRAW := .sec_key(Sector)] else .rd[, SRAW := ""]
.rd[, SEC := .SECMAP[SRAW]]
.unmapped <- sort(unique(.rd[is.na(SEC) & nzchar(SRAW)]$SRAW))
.rd[is.na(SEC), SEC := "Other"]

# 수익률: 인프라 열이 있으면 그대로, 없으면 종가비 — shift 는 뒤로만 (t−1)
if (.has_ret) .rd[, Ret := as.numeric(Ret)] else .rd[, Ret := Close / shift(Close, 1L) - 1, by = Ticker]

# 보유 가능성(공분산 추정 가능성): 직전 252 거래행 안의 유한수익 관측 수
.rd[, okr := as.integer(is.finite(Ret))]
.rd[, nhist := frollsum(okr, 252L, align = "right"), by = Ticker]

.mem_rows <- .rd[MEM %in% TRUE]
.sec_cov  <- if (nrow(.mem_rows)) mean(.mem_rows$SEC != "Other") else 0
.sec_n    <- uniqueN(.mem_rows[SEC != "Other"]$SEC)
cat(sprintf("%s 섹터 롤업: 실현 %d군 · 매핑 커버리지 %.1f%% · 미매핑 WI26 라벨 %d종%s\n",
            .TAG, .sec_n, 100 * .sec_cov, length(.unmapped),
            if (length(.unmapped)) paste0(" [", paste(head(.unmapped, 12), collapse = "|"), "]") else ""))
# 하드 가드 — 매핑이 깨지면 전 종목이 한 섹터로 뭉쳐 논문의 섹터중립이 소멸한다.
#   문턱(5군 · 50%)은 논문값이 아니라 침묵 실패 차단용 하한이다(FIDELITY 신고).
if (.sec_n < 5L || .sec_cov < 0.50)
  stop(sprintf("%s 섹터 매핑 붕괴: 실현 %d군 · 커버리지 %.1f%% — RAWDATA$Sector 라벨 확인",
               .TAG, .sec_n, 100 * .sec_cov))
rm(.mem_rows)

# =============================================================================
# 2. 거래일 격자 — 2/5/8/11월 마지막 거래일
#    하네스 집행일 = get_execution_date(시그널일) = 익월 첫 거래일이므로 집행은
#    3/1 · 6/1 · 9/1 · 12/1 (논문 §II-A 거래일). ★다만 하네스가 보유 수익을
#    exec 당일부터 누적해 **경제적 체결가는 시그널일 종가**다 — FIDELITY cost 항 참조.
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
# 3. 적격 집합 + 목표변수 (1분기 forward log-return · 식(1))
# =============================================================================
.elig <- .rd[Date %in% .TD & MEM %in% TRUE & is.finite(Size) & Size > 0 &
               is.finite(nhist) & nhist >= .MIN_HIST_D,
             .(Date, Ticker, Close, Size, SEC)]
.elig <- merge(.elig, .TDIX, by = "Date")

# 다음 거래일 종가: 멤버십과 무관한 전 종목 가격패널에서(라벨 생존편향 제거).
#   원천의 인덱스를 k−1 로 **내려** 붙인다 — lead · 음수 shift 없이 같은 뜻이 된다.
.pxa <- merge(.rd[Date %in% .TD, .(Date, Ticker, Close)], .TDIX, by = "Date")
.nxp <- .pxa[, .(Ticker, k = k - 1L, C_end = Close)]
.elig <- merge(.elig, .nxp, by = c("Ticker", "k"), all.x = TRUE)
.elig[, y := log(C_end / Close)]
.elig[!is.finite(y), y := NA_real_]
.elig[, C_end := NULL]
rm(.pxa, .nxp)

# =============================================================================
# 4. 회계 원값 패널
#    주 원천 = .cache/fundamental_xlsx.parquet (QuantiWise 분기 원값, 전 구간)
#    보조     = .cache/fundamental_merged.parquet 의 Source="DART" 행 (사업연도)
#    ★1판은 merged 의 XLSX 행만 읽었는데, merged 는 (Ticker,Period,Item) 에서
#      DART 를 우선해 2016+ 구간의 XLSX 분기행이 대부분 제거돼 있다 — 그래서 최근
#      구간의 회계가 사실상 연간값 하나로 줄어든다. 원파일을 직접 읽어 닫는다.
#    ★결산월 기준 행 삭제는 하지 않는다(논문에 그런 조항이 없다). 분기 연속성은
#      달력 분기가 아니라 **월 인덱스 간격**으로 판정한다.
# =============================================================================
.ROOT  <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", ""))
.CACHE <- file.path(.ROOT, ".cache")
.P_XLS <- file.path(.CACHE, "fundamental_xlsx.parquet")
.P_MRG <- file.path(.CACHE, "fundamental_merged.parquet")
if (!file.exists(.P_XLS)) stop(sprintf("%s 회계 패널 부재: %s", .TAG, .P_XLS))

.rd_pq <- function(path, cols) {
  d <- tryCatch(as.data.table(read_parquet(path, col_select = cols)),
                error = function(e) NULL)
  if (is.null(d)) d <- as.data.table(read_parquet(path))
  d[, intersect(cols, names(d)), with = FALSE]
}

# 원항목 — 파생 정의를 원천별로 갈라 쓰지 않기 위해 **전 원천 공통 항목만** 읽는다.
#   순이익 = 세전이익 − 법인세비용 (XLSX 에 당기순이익 항목이 없다)
#   매출총이익 = 매출액 − 매출원가 (두 원천 모두 보유)
.ITEMS <- c("Revenue", "COGS", "OperatingProfit", "PretaxIncome", "TaxExpense",
            "DepAmort", "OperatingCF", "TotalAssets", "CurrentAssets",
            "CashAndEquiv", "Inventory", "TotalLiab", "CurrentLiab",
            "AccountsPay", "TotalEquity")
.FLOW  <- c("Revenue", "COGS", "OperatingProfit", "PretaxIncome", "TaxExpense",
            "DepAmort", "OperatingCF")
.FLOWT <- paste0(.FLOW, "_T")

.wide_of <- function(d) {
  if (is.null(d) || !nrow(d)) return(NULL)
  w <- dcast(d, Ticker + PD ~ Item, value.var = "Value",
             fun.aggregate = function(v) v[1])
  fd <- d[!is.na(FDp), .(FDp = max(FDp)), by = .(Ticker, PD)]
  w <- merge(w, fd, by = c("Ticker", "PD"), all.x = TRUE)
  for (cc in .ITEMS) if (!cc %in% names(w)) set(w, j = cc, value = NA_real_)
  w[]
}

# ---- 4a. XLSX 분기 원값 (단일분기 유량 전제 — 저장소 compute_ttm 규약) --------
.qx <- .rd_pq(.P_XLS, c("Ticker", "Period_Date", "Factor_Date", "Item", "Value"))
.qx <- .qx[Item %in% .ITEMS & is.finite(Value)]
.qx[, Ticker := as.character(Ticker)]
.qx[, PD  := as.Date(Period_Date)]
.qx[, FDp := as.Date(Factor_Date)]
.qx <- .qx[!is.na(PD)]
.wq <- .wide_of(.qx)
rm(.qx); invisible(gc(verbose = FALSE))
if (is.null(.wq)) stop(sprintf("%s XLSX 분기 회계 0행", .TAG))

# 가용일 = 저장소 C4 정본을 엔진 안에서 재현 + 패널이 더 보수적이면 그쪽(pmax)
.wq[, FDc := PD + .Q_LAG_D]
.wq[month(PD) %in% 12L, FDc := as.Date(sprintf("%d-03-31", year(PD) + 1L))]
# 비달력 분기말을 쓰는 기업은 사업연도 말 분기를 패널에서 식별할 수 없다
# (결산월 열 부재). 그 기업 전 분기에 사업보고서 기한(90일)을 걸어 보수화한다.
.wq[, offcal := any(!(month(PD) %in% c(3L, 6L, 9L, 12L))), by = Ticker]
.wq[offcal %in% TRUE, FDc := PD + .ANN_LAG_D]
.wq[, FD := FDc]
.wq[!is.na(FDp) & FDp > FDc, FD := FDp]

# 월 인덱스 기반 분기 연속성 (달력 분기 가정 없음)
.wq[, QM := year(PD) * 12L + month(PD)]
setorder(.wq, Ticker, QM)
.wq <- unique(.wq, by = c("Ticker", "QM"))
for (cc in .FLOW) .wq[, (paste0(cc, "_T")) := frollsum(get(cc), 4L, align = "right"), by = Ticker]
.wq[, QM3 := shift(QM, 3L), by = Ticker]
.bad <- which(!(is.finite(.wq$QM3) & (.wq$QM - .wq$QM3) %in% 9L))
for (cc in .FLOWT) set(.wq, .bad, cc, NA_real_)
.wq[, RevPY := shift(Revenue_T, 4L), by = Ticker]
.wq[, QM4 := shift(QM, 4L), by = Ticker]
.wq[!(is.finite(QM4) & (QM - QM4) %in% 12L), RevPY := NA_real_]

# ---- 4b. DART 사업연도 원값 — 유량이 이미 1년치 ------------------------------
.wa <- NULL
if (file.exists(.P_MRG)) {
  .mx <- .rd_pq(.P_MRG, c("Ticker", "Period_Date", "Factor_Date", "Item", "Value", "Source"))
  if ("Source" %in% names(.mx)) .mx <- .mx[Source %in% "DART"] else .mx <- .mx[0L]
  .mx <- .mx[Item %in% .ITEMS & is.finite(Value)]
  if (nrow(.mx)) {
    .mx[, Ticker := as.character(Ticker)]
    .mx[, PD  := as.Date(Period_Date)]
    .mx[, FDp := as.Date(Factor_Date)]
    .mx <- .mx[!is.na(PD)]
    .wa <- .wide_of(.mx)
  }
  rm(.mx); invisible(gc(verbose = FALSE))
}
if (!is.null(.wa)) {
  .wa[, YI := year(PD)]
  setorder(.wa, Ticker, YI)
  .wa <- unique(.wa, by = c("Ticker", "YI"))
  .wa[, FDc := as.Date(sprintf("%d-03-31", YI + 1L))]     # 사업보고서 기한 (C4)
  .wa[, FD := FDc]
  .wa[!is.na(FDp) & FDp > FDc, FD := FDp]
  for (cc in .FLOW) .wa[, (paste0(cc, "_T")) := get(cc)]
  .wa[, RevPY := shift(Revenue_T, 1L), by = Ticker]
  .wa[, YI1 := shift(YI, 1L), by = Ticker]
  .wa[!(is.finite(YI1) & (YI - YI1) %in% 1L), RevPY := NA_real_]
}

# ---- 4c. 통합 (같은 가용일이 겹치면 분기 원천 우선) --------------------------
.slim <- function(d, pri) {
  if (is.null(d) || !nrow(d)) return(NULL)
  data.table(
    Ticker = d$Ticker, FD = d$FD, PRI = pri,
    REV = d$Revenue_T, CGS = d$COGS_T, OPR = d$OperatingProfit_T,
    PTI = d$PretaxIncome_T, TAX = d$TaxExpense_T,
    DAM = d$DepAmort_T, OCF = d$OperatingCF_T, REVPY = d$RevPY,
    TA = d$TotalAssets, CA = d$CurrentAssets, CSH = d$CashAndEquiv,
    IVT = d$Inventory, TL = d$TotalLiab, CL = d$CurrentLiab,
    APY = d$AccountsPay, EQ = d$TotalEquity)[!is.na(FD)]
}
.FDP <- rbindlist(Filter(Negate(is.null), list(.slim(.wq, 1L), .slim(.wa, 2L))),
                  use.names = TRUE)
if (!nrow(.FDP)) stop(sprintf("%s 회계 패널 통합 결과 0행", .TAG))
setorder(.FDP, Ticker, FD, PRI)
.FDP <- unique(.FDP, by = c("Ticker", "FD"))
.FDP[, PRI := NULL]
# 전 원천 공통 파생 (정의를 원천별로 가르지 않는다)
.FDP[, NIT := fifelse(is.finite(PTI) & is.finite(TAX), PTI - TAX, NA_real_)]
.FDP[, GPT := fifelse(is.finite(REV) & is.finite(CGS), REV - CGS, NA_real_)]
.FDP[, c("PTI", "TAX") := NULL]
.FDP[, FD_src := FD]
cat(sprintf("%s 회계 패널: 분기행 %s · 연간행 %s · 통합 %s · 가용일 %s ~ %s\n",
            .TAG, format(nrow(.wq), big.mark = ","),
            format(if (is.null(.wa)) 0L else nrow(.wa), big.mark = ","),
            format(nrow(.FDP), big.mark = ","),
            as.character(min(.FDP$FD)), as.character(max(.FDP$FD))))
rm(.wq, .wa); invisible(gc(verbose = FALSE))

# =============================================================================
# 5. 회계 → 거래일 매핑 (가용일 <= 시그널일 · 뒤로만 구르는 rolling join)
# =============================================================================
.gr <- unique(.elig[, .(Ticker, Date)])
setkey(.FDP, Ticker, FD)
setkey(.gr, Ticker, Date)
.mp <- .FDP[.gr, on = .(Ticker, FD = Date), roll = TRUE]
setnames(.mp, "FD", "Date")
.mp <- .mp[!is.na(FD_src) & as.numeric(Date - FD_src) <= .STALE_D]
.mp[, age_d := as.numeric(Date - FD_src)]
.mp[, FD_src := NULL]
.elig <- merge(.elig, .mp, by = c("Ticker", "Date"))
if (!nrow(.elig)) stop(sprintf("%s 회계 매핑 후 0행", .TAG))
cat(sprintf("%s 회계 연령(시그널일 − 가용일, 일): 중앙 %.0f · 평균 %.0f · 최대 %.0f · 180일 초과 %.1f%%\n",
            .TAG, stats::median(.elig$age_d), mean(.elig$age_d), max(.elig$age_d),
            100 * mean(.elig$age_d > 180)))
.elig[, age_d := NULL]

# =============================================================================
# 6. Table I 19지표 산출 (전부 그 행 하나 안에서 — 횡단면·시계열 통계 미사용)
#    ★EPS 는 없다 — 파일 머리 (a). 대체 특성도 넣지 않았다.
# =============================================================================
.elig[, EV := fifelse(is.finite(Size) & is.finite(TL) & is.finite(CSH),
                      Size + TL - CSH, NA_real_)]
.elig[, EBTD := fifelse(is.finite(OPR), OPR + fifelse(is.finite(DAM), DAM, 0), NA_real_)]

.elig[, RevGrowth     := fifelse(is.finite(REV) & is.finite(REVPY) & REVPY > 0, REV / REVPY - 1, NA_real_)]
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

cat(sprintf("%s 패널: 거래일 %d개 (%s ~ %s) · 적격행 %s · 종목 %d · 섹터 %d · 특성 %d\n",
            .TAG, length(.TD), as.character(min(.TD)), as.character(max(.TD)),
            format(nrow(MT), big.mark = ","), uniqueN(MT$Ticker), length(.SECLV),
            length(.FEAT)))

# =============================================================================
# 7. 모형 5종 — 학습창 적합 → 평가창 MSE → argmin 선택 → 당기 예측
#    ★모든 적합은 k <= n−1 인, 목표가 이미 실현된 과거 관측 위에서만 일어난다.
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
.n_cell <- 0L; .n_skip <- 0L; .featdrop <- 0L

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
    .featdrop <- .featdrop + (length(.FEAT) - length(keep))
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

    # §II-D Step 2 — "choose the model that has the lowest MSE in that certain period"
    sel_i <- which.min(mse)
    .selcnt[sel_i] <- .selcnt[sel_i] + 1L
    .n_cell <- .n_cell + 1L
    pr <- res[[sel_i]]$cu

    # §II-D Step 3 — "pick up top 20% stocks from each sector"
    ordi <- order(-pr, cuc$Ticker)           # 동값은 종목코드로 결정론적 분해
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

.np <- PICK[, .(n = .N), by = Date]
cat(sprintf("%s 섹터-분기 셀 %d (건너뜀 %d) · 결측규칙 탈락 특성 누적 %d · 모형 선택 %s\n",
            .TAG, .n_cell, .n_skip, .featdrop,
            paste(sprintf("%s:%d", names(.selcnt), .selcnt), collapse = " ")))
cat(sprintf("%s 모형별 적합 실패 %s (0이 아니면 그 모형은 그만큼 선택 후보에서 빠졌다)\n",
            .TAG, paste(sprintf("%s:%d", names(.mfail), .mfail), collapse = " ")))
cat(sprintf("%s 선정집합 크기: 중앙 %.0f · 최소 %d · 최대 %d · 20종 이하 리밸일 %d/%d\n",
            .TAG, stats::median(.np$n), min(.np$n), max(.np$n),
            sum(.np$n <= 20L), nrow(.np)))

# =============================================================================
# 8. 배분 = minimum-variance (§III-A · §IV) · long-only · Σw = 1 · w <= 5%
#    공분산 = (시그널일 − 365d, 시그널일] 일간수익 — 창의 종점이 시그널일이다.
#    ★5% 상한 + Σw=1 은 **N > 20 에서만 비자명**하다. N <= 20 이면 제약집합이
#      공집합이라 상한을 1/N 으로 최소 완화하는데, 그러면 해가 한 점이라 배분이
#      정확히 등가중이 된다(논문이 §IV 에서 기각한 쪽). FIDELITY 에 신고했다.
# =============================================================================
.RETD <- .rd[, .(Date, Ticker, Ret)]
setkey(.RETD, Ticker, Date)
.dts <- sort(unique(PICK$Date))
.wl <- vector("list", length(.dts))
.qp_fb <- 0L; .cap_relax <- 0L

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
  if (cap > .W_CAP) .cap_relax <- .cap_relax + 1L
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
cat(sprintf("%s PORTFOLIO %s행 · 리밸 %d회 (%s ~ %s) · 보유 중앙 %.0f · [%d, %d] · Sw [%.4f, %.4f] · 최대비중 %.3f · 상한완화 %d · QP 폴백 %d\n",
            .TAG, format(nrow(PORTFOLIO), big.mark = ","), nrow(.nb),
            as.character(min(.nb$Date)), as.character(max(.nb$Date)),
            stats::median(.nb$n), min(.nb$n), max(.nb$n),
            min(.nb$sw), max(.nb$sw), max(.nb$mx), .cap_relax, .qp_fb))
cat(sprintf("%s FACTORS %s행 (섹터 내 예측수익 백분위 — 진단 전용, 측정은 PORTFOLIO)\n",
            .TAG, format(nrow(FACTORS), big.mark = ",")))

rm(.rd, .elig, .mp, .gr, .FDP, .RETD, .wl, .pick, .scor, PICK, MT)
invisible(gc(verbose = FALSE))
