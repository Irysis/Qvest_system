# =============================================================================
# engine.R — RP_AUTO_2505_16336
# Lin Li, "The Role of Intangible Investment in Predicting Stock Returns:
#   Six Decades of Evidence"  (arXiv:2505.16336 · Financial Management 55(1):99-119)
#   https://arxiv.org/abs/2505.16336
#
# ★fidelity = FAITHFUL (충실구현). 정본 = FIDELITY.json
#   복제 대상 = 논문의 **INTANFT 팩터** 자체. 이 논문은 시계열 회귀 논문이지만
#   설명변수 INTANFT 가 그 자체로 완결된 매매 가능 포트폴리오(2x3 정렬 롱숏)라서
#   판정순서 1(충실구현)에서 끝난다 — 기전 이식(2)로 내려갈 이유가 없다.
#
# ===== 원문 대조 (2026-09-03) =====
#   arXiv 는 이 논문의 HTML 판을 만들지 않았다(/html·ar5iv 둘 다 404/redirect —
#   LaTeX 소스 미제출). PDF 전문을 텍스트 렌더러 경유로 읽어 아래 문장을 축자 확보했다.
#   인용은 전부 원문 그대로다(요약이 아니다).
#
#   (Q1) 신호 정의 — 논문 2.1 / Appendix A
#     "INTAN is intangible capital investment, calculated as R&D expenses plus the
#      investment portion of selling, general & administrative (SG&A) expenses,
#      divided by average total assets."
#     "The investment portion of SG&A expenses is the difference between actual
#      SG&A expenses and the SG&A expenses predicted by model
#        SG&A it = a + b*Revenues it + g*Revenue_Decrease it + l*Loss it + e it"
#     "Regressions are performed by industry and year, based on 3-digit SIC codes."
#     "SG&A and Revenues are scaled by average total assets."
#     "R&D expense is obtained directly from the COMPUSTAT database, and observations
#      with missing data are treated as having zero value."
#
#   (Q2) 포트폴리오 — 논문 2.2 (p.11) · 문단 전문
#     "Specifically, in June of each year t for the periods 1963-1992 and 1993-2022,
#      all NYSE, Amex and NASDAQ stocks are divided into two groups, small and big
#      (S and B), based on the NYSE median market cap. We then break these stocks into
#      three intangible intensity groups for the bottom (Low), middle (Medium), and
#      top (High) of the ranked values of INTAN. Therefore, the intangible intensity
#      factor INTANFT is calculated as the difference, each month, between the simple
#      average of the returns on the two high-INTAN portfolios (S/H and B/H) and the
#      average of the returns on the two low-INTAN portfolios (S/L and B/L)."
#
#   (Q3) 비중 — 논문은 포트폴리오 **내부** 비중을 한 번도 명시하지 않는다. 유일한
#     비중 진술이 각주 6 이고, 그것이 등가중이 기준선임을 드러낸다:
#     "This table and subsequent results are robust if R(t) - RF(t) is computed as the
#      value-weighted return on the portfolio of all sample stocks minus the one-month
#      Treasury bill rate."  ← 시가가중은 **강건성 확인**, 기준선은 등가중.
#     → 본 엔진은 4개 코너 포트폴리오 내부를 **등가중**으로 둔다. 논문이 실제로
#       사용한다고 말한 유일한 가중이며, 결합은 논문 문장 그대로 "simple average"(1/2씩).
#     ★"each month ... simple average of the returns" = 월별로 등가중 평균을 다시
#       잡는다는 뜻이므로, 편입 명부는 6월에 고정하되 **비중은 월별 등가중 리셋**한다.
#       (러너 하네스는 리밸 사이를 buy-and-hold drift 로 굴리므로, 월별 시그널일을
#        내야 등가중이 매달 복원된다. 그 복원 회전은 실제로 발생하는 매매라 비용을
#        무는 것이 옳다 — 시가가중이었다면 drift 가 공짜여야 해서 정반대가 된다.)
#
#   (Q4) 논문이 말하지 않은 두 값 — 지어내지 않고 **뿌리 논문**에서 가져온다.
#     ① 3분위 절단점 백분율: 위 (Q2) 문장은 Fama & French (1993, JFE 33:3-56) p.9 의
#        문장과 어순·표현이 동일한데("...the bottom 30% (Low), middle 40% (Medium),
#        and top 30% (High) of the ranked values of ... for NYSE stocks") 괄호 안
#        백분율만 빠져 있다. 즉 FF(1993) 의 2x3 템플릿을 그대로 쓰고 있다.
#        → 30/40/30 을 FF(1993) 근거로 채택. 우리가 고른 수가 아니다.
#     ② 절단점 기준군: 논문은 size 절단점을 "NYSE median" 으로 못박는다. 즉 절단점은
#        **본시장(대형주 거래소) 분포**에서 잡고, 정렬 모집단은 전 거래소다.
#        KR 대응물 = K200(본시장) 분포에서 절단점, 정렬 모집단 = K200 U KQ150.
#        (FF 는 BE/ME 절단점도 NYSE 기준이라 INTAN 절단점도 같은 기준군을 쓴다.)
#
#   (Q5) 비용: 논문에 거래비용·회전율 언급이 **전혀 없다** → commission_paper = null.
#
# ===== 변경한 것 (유니버스 하나 + 그에 딸린 KR 대응물) =====
#   유니버스: NYSE/Amex/NASDAQ → K200 U KQ150 (PIT 시변 멤버십) + adv20(t-1) >= 2e8.
#   그 치환에서 자동으로 따라오는 것 3개 — 독립적인 설계 변경이 아니다:
#     - NYSE 기준군      → K200 기준군            (Q4-②)
#     - 3-digit SIC 산업 → RAWDATA$Sector(WI26 대분류). KR 에 SIC 가 없다. SIC 3자리를
#       한국 상장 모집단에 그대로 쓰면 산업-연도 셀이 1~3개 기업이 되어 회귀가 성립하지
#       않는다. 셀이 얇으면(<20) 그 해 전체 풀링 회귀로 폴백한다.
#     - COMPUSTAT        → fundamental_merged.parquet (DART + QuantiWise)
#   그 외 신호·종목수·비중·리밸 주기는 전부 논문 그대로다.
#
# ===== KR 데이터 한계 (스펙 변경이 아니라 커버리지 사실 — 로그로 드러낸다) =====
#   K-IFRS 이후 연구개발비는 손익계산서 독립 계정이 아니라 주석 항목이 되면서 KR
#   패널의 RandD 커버리지가 후반부에 크게 떨어진다(사내 선례: mohanram G6 가 같은
#   지점에서 1203 -> 42 종목). 논문 규약이 "missing R&D = 0" 이므로 규약대로 0 을
#   넣되, **형성연도별 R&D 실보유 비율을 매번 출력**한다. 침묵시키지 않는다.
#   (RandD 결측 시 OrdRandD(경상연구개발비)로 보완 — 같은 계정의 KR 표기 차이일 뿐,
#    data_collector_dart.R:462 가 이미 둘을 같은 RandD 로 매핑하고 있다.)
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) =====
#  ▸ 구조 경계 1: 회계 패널의 모든 소비 지점에 `FD <= D` 가 걸려 있다(FD = 그 회계연도
#    자료가 실제로 공시돼 쓸 수 있게 된 날 = Factor_Date, 12월 결산은 익년 3/31).
#    D = 형성일(6월 말 거래일). 즉 D 시점에 공시되지 않은 행은 코드가 볼 수 없다.
#  ▸ 구조 경계 2: 사용 회계연도를 fy = t-1 로 **고정**한다. t 년도 자료를 참조하는
#    지점이 코드에 없다(roll join 도 안 쓴다 — 우연히 미래 기수를 물어올 여지 제거).
#  ▸ 구조 경계 3: 6월에 정해진 버킷이 그 다음 6월까지의 월말에 그대로 실린다. 월별
#    가중치는 편입명부(6월 정보) + 그 달의 멤버십/거래가능 여부만 쓴다. 미래 없음.
#  C1  : 전 표본 통계 0건. median/quantile 은 전부 **형성일 D 한 단면**이고, SG&A
#        회귀도 D 시점에 공시 완료된 fy=t-1 단면 하나로만 적합한다(연도별 재적합).
#  C2  : same-day 순환참조 없음. 시그널일 종가까지만 쓰고 집행은 익 거래일(하네스).
#  C3  : 같은 기간 집계->적용 없음. 신호창의 종점이 보유월 시작 전이다.
#  C4  : 재무제표 시차 = Factor_Date 규약 그대로(12월 결산 -> 익년 3/31). 6월 말
#        형성일은 그 시차를 3개월 초과해 여유로 넘긴다. 시차를 우리가 새로 정하지 않는다.
#  C5  : 오버레이 없음(S0/S1 오버레이 금지 준수).
#  C6  : 유니버스 = 각 시점의 K200/KQ150 멤버십(PIT 시변). 최종 명부 주입 없음.
#  C7  : shift(-N)·미래 인덱싱 0건. shift 는 전부 +1(과거 방향).
#  C9  : DD/VT 미사용.
#  C10 : 유동성 = 형성일 **직전 20 거래일**(종점 t-1)의 평균 거래대금. 형성일 당일
#        거래량은 창에 들어가지 않는다 — `lo:(ip - 1L)` 로 구조적으로 배제.
#  C11 : 매크로·외부 시계열 미사용.
#  C13 : Factor DB 미소비 -> 부호 정렬 대상 없음. 롱=고INTAN 은 논문 정의(H - L)이지
#        측정된 IC 로 고른 방향이 아니다.
#  C15 : Factor DB parquet 직접 load 0건(Factor DB 를 쓰지 않는다).
#  ★rawdata 의 Market 열 미사용(KOSDAQ 0건 날조 — 사내 기록). 본/코스닥 구분은
#    K200/KQ150 멤버십 플래그로만 한다.
#
# ===== 산출 =====
#   PORTFOLIO(Date, Ticker, Weight, Leg) — 논문 비중 그대로.
#     long  = S/H U B/H, sum(w) = +1  (S/H 에 1/2, B/H 에 1/2, 각 버킷 내부 등가중)
#     short = S/L U B/L, sum(w) = -1
#   러너 호출: portfolio_spec = list(construction = "engine_direct")
#              commission_paper = NULL (논문 무명시)
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(arrow)
}))

# 난수 미사용(결정론적 엔진)이지만 재현성 선언 고정.
set.seed(25051633L)

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.RQ <- c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150", "Sector")
if (!all(.RQ %in% names(RAWDATA)))
  stop(sprintf("[RP_2505_16336] RAWDATA 열 부족: %s",
               paste(setdiff(.RQ, names(RAWDATA)), collapse = ", ")))

# ── 데이터 루트: 코드 루트가 아니라 데이터 루트를 잡는다(사내 선례 카드) ──
.PICK_ROOT <- function() {
  cand <- c(Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""),
            if (exists("PROJECT_ROOT")) as.character(PROJECT_ROOT)[1] else "")
  for (p in cand)
    if (nzchar(p) && file.exists(file.path(p, ".cache", "fundamental_merged.parquet")))
      return(p)
  ""
}
.ROOT <- .PICK_ROOT()
if (!nzchar(.ROOT))
  stop("[RP_2505_16336] fundamental_merged.parquet 을 못 찾음 — QM_ROOT 확인")
.FUND <- file.path(.ROOT, ".cache", "fundamental_merged.parquet")

# =============================================================================
# 0. 상수 — 논문에서 온 것 / 우리가 정한 것은 무엇인가
# =============================================================================
# ▸ 논문에서 온 것 (수치가 아니라 **구성**이 왔다):
#     2x3 정렬 · 6월 형성 · H 두 개의 단순평균 - L 두 개의 단순평균 · 코너 내부 등가중.
# ▸ 뿌리 논문에서 온 것 (원논문이 말하지 않아 FF(1993) 에서 가져옴 — 헤더 Q4):
.Q_LO     <- 0.30      # FF(1993) bottom 30% (Low)
.Q_HI     <- 0.70      # FF(1993) top 30% (High) -> 상위 절단점 = 70 백분위
# ▸ 축(도훈 고정)에서 온 것:
.LIQ      <- 2e8       # adv20(t-1) 하한 (KRW)
.LIQ_WIN  <- 20L       # 거래일 (형성일 직전 20 거래일, 종점 = t-1)
# ▸ 추정 타당성 하한 — 전략 파라미터가 아니라 추정량이 성립하는 최소 표본이다.
#   성과를 보고 고른 값이 아니고, 셀이 얇을 때 무엇으로 폴백하는지가 전부다.
.MIN_REG  <- 20L       # 산업 셀 회귀 최소 표본. 추정 계수 4개 x 5관측 = 20 (표준 하한).
                       #   미만이면 그 해 전체 풀링 회귀 잔차를 쓴다(버리지 않는다).
.MIN_BP   <- 30L       # 절단점 기준군(K200) 최소 종목수. 미만이면 정렬 모집단 전체로 폴백.
.MIN_POP  <- 50L       # 2x3(=6칸) 정렬이 의미를 갖는 모집단 하한. 미만인 해는 형성 생략.

.tru <- function(x) !is.na(x) & (x != 0)     # 논리/0-1 혼재 방어

# =============================================================================
# 1. 날짜 골격 — 형성일(6월 말) · 월말 · 유동성 창
# =============================================================================
.dates <- sort(unique(RAWDATA$Date))
.DT <- data.table(Date = .dates)
.DT[, ym := year(Date) * 12L + month(Date)]
.DT[, yr := year(Date)]

.ME <- .DT[, .(Date = max(Date)), by = ym]           # 월말 거래일
setorder(.ME, Date)

.FORM <- .DT[month(Date) == 6L, .(FormDate = max(Date)), by = yr]
setorder(.FORM, FormDate)
.FORM <- .FORM[FormDate >= as.Date("2005-01-01")]    # 축 시작(2005-01-01~)
if (nrow(.FORM) == 0L)
  stop("[RP_2505_16336] 6월 형성일 0건 — RAWDATA 날짜 범위 확인")

# 유동성 창: 형성일 **직전** 20 거래일. 종점이 t-1 이 되도록 lo:(ip - 1L) 로 자른다.
.LW <- rbindlist(lapply(seq_len(nrow(.FORM)), function(k) {
  ip <- match(.FORM$FormDate[k], .dates)
  if (is.na(ip) || (ip - .LIQ_WIN) < 1L) return(NULL)
  data.table(Date = .dates[(ip - .LIQ_WIN):(ip - 1L)], FormDate = .FORM$FormDate[k])
}), use.names = TRUE)
if (nrow(.LW) == 0L)
  stop("[RP_2505_16336] 유동성 창 구성 실패 — 거래일 수 부족")
.FORM <- .FORM[FormDate %in% unique(.LW$FormDate)]

# 월말 -> 그 달을 지배하는 형성일(직전 6월). findInterval = 최대 FormDate <= Date.
.MM <- .ME[Date >= min(.FORM$FormDate), .(Date)]
.MM[, FormDate := .FORM$FormDate[findInterval(Date, .FORM$FormDate)]]

# =============================================================================
# 2. 가격 패널 축소 (필요한 날짜만 — 메모리 경계)
# =============================================================================
.kd <- sort(unique(c(.LW$Date, .FORM$FormDate, .MM$Date)))
.rd <- RAWDATA[Date %in% .kd, .(Date, Ticker, Close, Vol, Size, K200, KQ150, Sector)]
.nd <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.nd > 0L) {
  cat(sprintf("[RP_2505_16336] (Date,Ticker) 중복 %d행 — 첫 행만 남긴다\n", .nd))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}

# adv20(t-1): 형성일 직전 20 거래일 평균 거래대금. 20일이 다 차야 통과시킨다
#   (frollmean(20) 이 결측 하나에도 NA 를 내는 사내 규약과 동일한 엄격도).
.ADV <- merge(.rd[, .(Date, Ticker, TV = Close * Vol)], .LW,
              by = "Date", allow.cartesian = TRUE)
.ADV <- .ADV[is.finite(TV), .(ADV20 = mean(TV), nobs = .N), by = .(FormDate, Ticker)]
.ADV <- .ADV[nobs == .LIQ_WIN & ADV20 >= .LIQ, .(FormDate, Ticker)]

# 정렬 모집단: 형성일의 K200 U KQ150 멤버 & 유동성 통과 & 시총 유효
.POP <- .rd[Date %in% .FORM$FormDate & (.tru(K200) | .tru(KQ150)) &
              is.finite(Size) & Size > 0,
            .(FormDate = Date, Ticker, Size, K200m = .tru(K200))]
.POP <- merge(.POP, .ADV, by = c("FormDate", "Ticker"))

# 회귀 표본용 산업 라벨: 형성일의 **전 종목** 단면(모집단보다 넓다 — 논문이 산업
#   비용함수를 전 상장기업으로 적합하는 것과 같은 자리).
.SEC <- .rd[Date %in% .FORM$FormDate, .(FormDate = Date, Ticker, Sector)]

# 월별 보유 자격: 그 달 말에 여전히 K200 U KQ150 이고 거래되는 종목
.MEM <- .rd[Date %in% .MM$Date & (.tru(K200) | .tru(KQ150)) &
              is.finite(Close) & Close > 0, .(Date, Ticker)]

rm(.LW); gc(verbose = FALSE)

# =============================================================================
# 3. 회계 패널 -> 회계연도 단위 값
# =============================================================================
# ★여기가 이 엔진에서 가장 조용히 틀릴 수 있는 지점이다.
#   fundamental_merged.parquet 은 두 원천이 섞여 있고 **손익 항목의 시간 단위가 다르다**:
#     Source = "XLSX" / "xlsx_derived" : 분기 개별값 (Period = YYYY03/06/09/12)
#     Source = "DART"                  : 1년치 값   (Period = YYYY12)
#   Period 가 YYYY12 라는 이유로 둘을 같은 축으로 읽으면 2015년 근처에서 매출/판관비가
#   4배 점프한다 — 에러 없이 신호만 바뀌는 침묵 실패다. 그래서 **항목별로** Source 를
#   보고 분기합/연간값을 갈라 쓴다. 병합 규약상 YYYY12 는 DART 우선이라 두 갈래는
#   서로 배타적이다(DART 가 있으면 XLSX 4분기 중 Q4 가 없어 nq==4 가 깨진다).
.ITEMS <- c("Revenue", "SGAExpense", "RandD", "OrdRandD",
            "NetIncome", "PretaxIncome", "TaxExpense", "TotalAssets")
.FLOWI <- setdiff(.ITEMS, "TotalAssets")

.fd <- as.data.table(read_parquet(
  .FUND, col_select = c("Ticker", "Period", "Factor_Date", "Item", "Value", "Source")))
if (!"Source" %in% names(.fd))
  stop("[RP_2505_16336] 패널에 Source 열이 없다 — 손익 항목의 시간 단위를 가릴 수 없어 중단")
.fd <- .fd[Item %chin% .ITEMS & is.finite(Value)]
if (!inherits(.fd$Factor_Date, "Date")) .fd[, Factor_Date := as.Date(Factor_Date)]
.pc <- as.character(.fd$Period)
.fd[, yv := as.integer(substr(.pc, 1L, 4L))]
.fd[, mv := as.integer(substr(.pc, 5L, 6L))]
rm(.pc)
.fd <- .fd[is.finite(yv) & is.finite(mv) & is.finite(Factor_Date) &
             yv >= (min(.FORM$yr) - 3L)]
.fd[, isd := Source %chin% "DART"]
cat(sprintf("[RP_2505_16336] 회계 패널 %s행 | 원천 %s\n",
            format(nrow(.fd), big.mark = ","),
            paste(sprintf("%s:%s", .fd[, .N, by = Source]$Source,
                          format(.fd[, .N, by = Source]$N, big.mark = ",")),
                  collapse = " ")))

# (a) 손익 항목: DART = 1년치 그대로 / 그 외 = 4개 분기 합(4개 다 있어야 채택)
.a1 <- .fd[isd == TRUE & mv == 12L & Item %chin% .FLOWI,
           .(V = Value[1], FD = max(Factor_Date), pr = 1L), by = .(Ticker, Item, yv)]
.a2 <- .fd[isd == FALSE & mv %in% c(3L, 6L, 9L, 12L) & Item %chin% .FLOWI,
           .(V = sum(Value), nq = .N, FD = max(Factor_Date)), by = .(Ticker, Item, yv)]
.a2 <- .a2[nq == 4L, .(Ticker, Item, yv, V, FD, pr = 2L)]
.FLW <- rbind(.a1, .a2, use.names = TRUE)

# (b) 재무상태 항목: 기말 잔액이므로 합산하지 않는다. YYYY12 값을 그대로.
.st <- .fd[Item %chin% "TotalAssets" & mv == 12L]
.st[, pr := fifelse(isd, 1L, 2L)]
setorder(.st, Ticker, yv, pr)
.st <- unique(.st, by = c("Ticker", "yv"))
.FLW <- rbind(.FLW, .st[, .(Ticker, Item, yv, V = Value, FD = Factor_Date, pr)],
              use.names = TRUE)

setorder(.FLW, Ticker, Item, yv, pr)
.FLW <- unique(.FLW, by = c("Ticker", "Item", "yv"))
rm(.fd, .a1, .a2, .st); gc(verbose = FALSE)

.FYW <- dcast(.FLW, Ticker + yv ~ Item, value.var = "V")
.FAV <- .FLW[, .(FD = max(FD)), by = .(Ticker, yv)]      # 그 기수가 쓸 수 있게 된 날
.FYW <- merge(.FYW, .FAV, by = c("Ticker", "yv"))
for (cc in .ITEMS) if (!cc %in% names(.FYW)) .FYW[, (cc) := NA_real_]
rm(.FLW, .FAV); gc(verbose = FALSE)

# 직전 기수 값 — 기수가 실제로 연속일 때만 인정한다(결번이 있으면 shift 가 엉뚱한
#   해를 물어온다. 평균자산·매출감소 지시자가 통째로 틀어지는 자리다).
setorder(.FYW, Ticker, yv)
.FYW[, yv_p := shift(yv), by = Ticker]
.FYW[, TA_p := shift(TotalAssets), by = Ticker]
.FYW[, RV_p := shift(Revenue), by = Ticker]
.FYW[is.na(yv_p) | yv_p != (yv - 1L), c("TA_p", "RV_p") := NA_real_]

.FYW[, NI := fifelse(is.finite(NetIncome), NetIncome,
                     fifelse(is.finite(PretaxIncome) & is.finite(TaxExpense),
                             PretaxIncome - TaxExpense, NA_real_))]
.FYW[, AA := fifelse(is.finite(TotalAssets) & is.finite(TA_p),
                     (TotalAssets + TA_p) / 2, NA_real_)]     # average total assets
# 논문 규약: R&D 결측 = 0. (KR 표기 차이 보완 = OrdRandD. 실보유 여부는 has_rd 로 로그.)
.FYW[, has_rd := is.finite(RandD) | is.finite(OrdRandD)]
.FYW[, RDV := fifelse(is.finite(RandD), RandD,
                      fifelse(is.finite(OrdRandD), OrdRandD, 0))]
.FYW[, sga_s := SGAExpense / AA]                              # scaled by avg total assets
.FYW[, rev_s := Revenue / AA]
.FYW[, rd_s  := RDV / AA]
.FYW[, RevDec := fifelse(is.finite(RV_p), as.integer(Revenue < RV_p), NA_integer_)]
.FYW[, Loss   := as.integer(NI < 0)]

# =============================================================================
# 4. 형성일 루프 — SG&A 투자성분 회귀 -> INTAN -> 2x3 버킷
# =============================================================================
.BK   <- vector("list", nrow(.FORM))
.skip <- 0L
.t0   <- Sys.time()

for (k in seq_len(nrow(.FORM))) {
  D  <- .FORM$FormDate[k]
  fy <- .FORM$yr[k] - 1L        # 논문/FF 규약: t년 6월 형성 <- t-1 회계연도

  # ★PIT 관문: 이 기수가 D 시점에 공시돼 있어야 한다(FD <= D). fy 를 고정했으므로
  #   미래 기수를 물어올 경로가 코드에 없다.
  S <- .FYW[yv == fy & FD <= D &
              is.finite(AA) & AA > 0 &
              is.finite(sga_s) & is.finite(rev_s) & is.finite(rd_s) &
              is.finite(RevDec) & is.finite(Loss),
            .(Ticker, sga_s, rev_s, RevDec, Loss, rd_s, has_rd)]
  if (nrow(S) < .MIN_REG) { .skip <- .skip + 1L; next }

  S <- merge(S, .SEC[FormDate == D, .(Ticker, Sector)], by = "Ticker", all.x = TRUE)

  # (1) 그 해 전체 풀링 적합 — 산업 셀이 얇은 종목의 폴백 잔차
  f0 <- tryCatch(lm(sga_s ~ rev_s + RevDec + Loss, data = S), error = function(e) NULL)
  if (is.null(f0)) { .skip <- .skip + 1L; next }
  r0 <- as.numeric(residuals(f0))
  if (length(r0) != nrow(S)) { .skip <- .skip + 1L; next }
  S[, e := r0]

  # (2) 산업 셀 적합 — 표본이 충분한 셀만 덮어쓴다. "by industry and year" 의 KR 판.
  S[, nsec := .N, by = Sector]
  .secs <- unique(S[!is.na(Sector) & nsec >= .MIN_REG, Sector])
  for (sc in .secs) {
    ix <- which(S$Sector == sc)
    fs <- tryCatch(lm(sga_s ~ rev_s + RevDec + Loss, data = S[ix]),
                   error = function(e) NULL)
    if (is.null(fs)) next
    rs <- as.numeric(residuals(fs))
    if (length(rs) == length(ix)) set(S, i = ix, j = "e", value = rs)
  }

  # (3) INTAN = R&D/평균자산 + SG&A 투자성분(잔차)
  S[, INTAN := rd_s + e]

  # (4) 2x3 정렬. 절단점은 K200(본시장) 기준군, 정렬 모집단은 K200 U KQ150.
  P <- merge(S[is.finite(INTAN), .(Ticker, INTAN, has_rd)],
             .POP[FormDate == D, .(Ticker, Size, K200m)], by = "Ticker")
  if (nrow(P) < .MIN_POP) { .skip <- .skip + 1L; next }
  ref <- P[K200m == TRUE]
  bpsrc <- "K200"
  if (nrow(ref) < .MIN_BP) { ref <- P; bpsrc <- "POP" }
  szv <- ref$Size
  ivv <- ref$INTAN
  szmed <- as.numeric(median(szv))
  qcut  <- as.numeric(quantile(ivv, c(.Q_LO, .Q_HI), names = FALSE, type = 7L))
  if (!all(is.finite(c(szmed, qcut))) || qcut[1] >= qcut[2]) { .skip <- .skip + 1L; next }

  P[, SZ := fifelse(Size <= szmed, "S", "B")]
  P[, IG := fifelse(INTAN <= qcut[1], "L", fifelse(INTAN > qcut[2], "H", "M"))]
  P <- P[IG != "M"]
  P[, Bucket := paste0(SZ, IG)]
  if (uniqueN(P[Bucket %chin% c("SH", "BH"), Bucket]) == 0L ||
      uniqueN(P[Bucket %chin% c("SL", "BL"), Bucket]) == 0L) { .skip <- .skip + 1L; next }

  .BK[[k]] <- P[, .(FormDate = D, Ticker, Bucket)]

  .cnt <- P[, .N, by = Bucket]
  cat(sprintf(paste0("[RP_2505_16336] %s (fy%d) | 회귀표본 %d(산업셀 %d개 적합) | ",
                     "모집단 %d | 절단점 %s | R&D 실보유 %.0f%% | %s\n"),
              as.character(D), fy, nrow(S), length(.secs), nrow(P), bpsrc,
              100 * mean(P$has_rd),
              paste(sprintf("%s=%d", .cnt$Bucket, .cnt$N), collapse = " ")))
}

BKT <- rbindlist(Filter(Negate(is.null), .BK), use.names = TRUE)
if (nrow(BKT) == 0L)
  stop("[RP_2505_16336] 버킷 0건 — 회계 커버리지/유니버스 확인")

# =============================================================================
# 5. 월별 비중 — 편입명부는 6월 고정, 등가중은 매달 복원 (논문 "each month" 규약)
# =============================================================================
W <- merge(BKT, .MM, by = "FormDate", allow.cartesian = TRUE)
W <- merge(W, .MEM, by = c("Date", "Ticker"))                  # 그 달에도 거래 가능한 것만
W[, side := fifelse(Bucket %chin% c("SH", "BH"), 1L, -1L)]
W[, nb := .N, by = .(Date, Bucket)]                            # 버킷 내부 종목수 -> 등가중
W[, kb := uniqueN(Bucket), by = .(Date, side)]                 # 그 다리에 살아있는 버킷 수
W[, ns := uniqueN(side), by = Date]
W <- W[ns == 2L]                                               # 양다리 다 서는 달만
if (nrow(W) == 0L)
  stop("[RP_2505_16336] 롱/숏 양다리가 동시에 서는 달이 없음")
W[, Weight := side * (1 / kb) / nb]                            # 다리 합 = +-1
W[, Leg := fifelse(side > 0L, "long", "short")]

PORTFOLIO <- W[order(Date, -Weight), .(Date, Ticker, Weight, Leg)]

# ── 검산: 다리별 합이 정확히 +-1 인가 (하네스가 GL/GS 로 그대로 받는다) ──
.chk <- PORTFOLIO[, .(sw = sum(Weight)), by = .(Date, Leg)]
.bad <- .chk[abs(abs(sw) - 1) > 1e-9]
if (nrow(.bad) > 0L)
  stop(sprintf("[RP_2505_16336] 다리 비중합 이상 %d건 (예: %s %s sum=%.6f)",
               nrow(.bad), as.character(.bad$Date[1]), .bad$Leg[1], .bad$sw[1]))

.nm <- PORTFOLIO[, .N, by = Date]
cat(sprintf(paste0("[RP_2505_16336] faithful: INTANFT (2x3 size x INTAN, 6월 형성, ",
                   "H 2개 단순평균 - L 2개 단순평균, 코너 내부 등가중)\n",
                   "  형성 %d회(skip %d) · 월 %d개 (%s ~ %s) · PORTFOLIO %s행\n",
                   "  보유 종목수 중앙 %d (min %d / max %d) · 롱 %s행 / 숏 %s행 · %.1f분\n",
                   "  ★러너 호출: portfolio_spec = list(construction = \"engine_direct\") · ",
                   "commission_paper = NULL (논문 무명시)\n"),
            uniqueN(BKT$FormDate), .skip, uniqueN(PORTFOLIO$Date),
            as.character(min(PORTFOLIO$Date)), as.character(max(PORTFOLIO$Date)),
            format(nrow(PORTFOLIO), big.mark = ","),
            as.integer(median(.nm$N)), min(.nm$N), max(.nm$N),
            format(nrow(PORTFOLIO[Leg == "long"]), big.mark = ","),
            format(nrow(PORTFOLIO[Leg == "short"]), big.mark = ","),
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
