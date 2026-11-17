#==============================================================================
# build_fundamental_caches.R — 재무 캐시 두 개(분기 · 연간) 생산기 (2026-11-16 도훈 지시)
#
# 도훈 11-16: '펀더멘털 데이터 캐시는 분기파일, 연간파일 하나씩 만들고 여기에 맞춰서 인프라 파일도 수정해' ·
#   '112개 항목으로 계산가능한 모든 파생지표들도 캐시에 넣어줘' · '올슨 O 스코어도 추가' · 원천 = 퀀티 단독(FUNDAMENTAL-QW-ONLY-NO-DART-20261116).
#
# 입력(읽기 전용): .cache/fundamental_v2/fund_v2_quarterly.parquet(build_fundamental_v2.py · 퀀티 재무 v2 112개 항목 · 분기 단독 값 ·
#   행마다 Factor_Date = 쓸 수 있는 첫날 = max(법정기한 + 45일 뒤 첫 거래일, 퀀티 공시일 뒤 첫 거래일)) · .cache/qw_fund_v2/fiscal_month.parquet
# 출력(원자적 교체):
#   .cache/fundamental_quarterly.parquet — 결산 분기마다 한 행(종목 × 기간) · '최근 1년' 기준:
#       잔액 항목 = 그 분기 말 값 · 흐름 항목 = 최근 4분기 합(TTM — 네 분기가 연속으로 다 있을 때만) ·
#       흐름 항목의 분기 단독 값 = 이름 뒤 '_Q' · 파생지표 전부(같은 이름 · TTM 기준 · 1년 전 = 4분기 전)
#   .cache/fundamental_annual.parquet    — 회계연도 말 분기 행만(결산월 = fiscal_month) · 흐름 = 그 회계연도 네 분기 합 ·
#       잔액 = 연말 값 · 파생지표 전부(같은 이름 · 회계연도 기준 · 1년 전 = 직전 회계연도) · 열 FY 를 더한다
#   열(long): Ticker · Period(YYYYMM) · Period_Date · Factor_Date · Item · Value · Kind(raw | raw_q | derived) [· FY]
# 날짜(PIT · pit.md C4): 행의 Factor_Date = 그 값에 들어간 모든 분기 행 Factor_Date 의 최댓값(TTM = 네 분기 · 1년 전 비교 = 1년 전 행 ·
#   다년 지표 = 쓰인 모든 해). 날짜 순서 계약(build_fundamental_merged_v2.R 과 같은 규칙): (종목, 항목) 안에서 Factor_Date 는 기간 순서대로
#   엄격히 는다 — 늦게 도착한 옛 기간(뒤 기간이 더 일찍 쓰일 수 있었다) = 버린다 · 같은 날 도착 = 새 기간을 하루씩 늦춘다(늦추기만 한다).
# 지표 정의 정본 = 이 파일의 fc_derive() (항목 · 공식 · 근거). 근거 논문은 지표 옆 주석.
# 실행: Rscript build_fundamental_caches.R [--root R] [--in F] [--fm F] [--out-q F] [--out-a F]
# 종료: 0 성공 · 1 오류 · 3 입력 없음
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
args <- commandArgs(trailingOnly = TRUE)
argv <- function(flag, default) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
ROOT <- argv("--root", gsub("\\\\", "/", Sys.getenv("QM_ROOT", getwd())))
IN   <- argv("--in",   file.path(ROOT, ".cache", "fundamental_v2", "fund_v2_quarterly.parquet"))
FMP  <- argv("--fm",   file.path(ROOT, ".cache", "qw_fund_v2", "fiscal_month.parquet"))
OUTQ <- argv("--out-q", file.path(ROOT, ".cache", "fundamental_quarterly.parquet"))
OUTA <- argv("--out-a", file.path(ROOT, ".cache", "fundamental_annual.parquet"))
say <- function(...) cat(sprintf("[fund-caches] %s\n", sprintf(...)))
for (p in c(IN, FMP)) if (!file.exists(p)) { say("입력 없음: %s", p); quit(status = 3) }
t0 <- Sys.time()

# ---- 0. 항목 분류 ------------------------------------------------------------------------------
# 잔액(시점 값) = 재무상태표 전부 + 투하자본 · 직원 수 · 주식 수(기말 · 평균 · 우선주 · 자기주식). 나머지 = 흐름(그 분기에 일어난 양).
STOCK_EXTRA <- c("InvestedCapital", "Employees", "SharesCommonOutAdj", "SharesCommonAvgAdj", "SharesCommonAdj",
                 "SharesPrefAdj", "TreasuryShares")
q <- as.data.table(read_parquet(IN, col_select = c("Ticker", "Period", "Period_Date", "Factor_Date", "Item", "Value", "Db")))
q[, P := as.integer(Period)]
BS <- unique(q[Db == "FundV2_BS", Item])
STOCKS <- union(BS, STOCK_EXTRA)
ITEMS <- sort(unique(q$Item))
FLOWS <- setdiff(ITEMS, STOCKS)
say("입력 %s행 · 종목 %d · 항목 %d(잔액 %d · 흐름 %d)", format(nrow(q), big.mark = ","), uniqueN(q$Ticker), length(ITEMS),
    length(intersect(ITEMS, STOCKS)), length(FLOWS))

# ---- 1. 넓은 표(종목 × 분기) ---------------------------------------------------------------------------
fd_row <- q[, .(Factor_Date = max(as.Date(Factor_Date)), Period_Date = as.Date(Period_Date[1])), by = .(Ticker, P)]
W <- dcast(q, Ticker + P ~ Item, value.var = "Value", fun.aggregate = function(x) x[1])
W <- fd_row[W, on = .(Ticker, P)]
for (it in setdiff(c(STOCKS, FLOWS), names(W))) set(W, j = it, value = NA_real_)
setorder(W, Ticker, P)
W[, mi := (P %/% 100L) * 12L + (P %% 100L)]
W[, fdn := as.numeric(Factor_Date)]
fm <- as.data.table(read_parquet(FMP))[, .(Ticker, FiscalMonth = suppressWarnings(as.integer(FiscalMonth)))]
fm[is.na(FiscalMonth), FiscalMonth := 12L]
W <- fm[W, on = .(Ticker)]
W[is.na(FiscalMonth), FiscalMonth := 12L]
rm(q); invisible(gc())

# 연속 분기 지연: k 행 전이 정확히 3k 개월 전일 때만 그 값(아니면 NA)
lagq <- function(x, k, mi, tk) fifelse(shift(mi, k) == mi - 3L * k & shift(tk, k) == tk, shift(x, k), NA)

# ---- 2. TTM(흐름 = 최근 4분기 합 · 넷 다 있을 때만) · 분기 단독 값 '_Q' ---------------------------------------------
tk <- W$Ticker; mi <- W$mi
ok4 <- !is.na(lagq(mi, 1L, mi, tk)) & !is.na(lagq(mi, 2L, mi, tk)) & !is.na(lagq(mi, 3L, mi, tk))
for (f in FLOWS) {
  x <- W[[f]]
  set(W, j = paste0(f, "_Q"), value = x)
  s <- x + lagq(x, 1L, mi, tk) + lagq(x, 2L, mi, tk) + lagq(x, 3L, mi, tk)
  set(W, j = f, value = fifelse(ok4, s, NA_real_))
}
# TTM 행 날짜 = 네 분기 가운데 가장 늦은 날(흐름이 하나라도 있는 행 · 잔액만 있는 행도 같은 규칙 — 보수)
f1 <- lagq(W$fdn, 1L, mi, tk); f2 <- lagq(W$fdn, 2L, mi, tk); f3 <- lagq(W$fdn, 3L, mi, tk)
W[, fd0 := pmax(fdn, f1, f2, f3, na.rm = TRUE)]
say("TTM: 네 분기 연속 행 %s / %s", format(sum(ok4), big.mark = ","), format(nrow(W), big.mark = ","))

# ---- 3. 파생지표 ------------------------------------------------------------------------------------------------
# D = 표(종목 · 기간 순 정렬) · yl = 1년 전 지연(분기 표 = 4행 전 · 12개월 / 연간 표 = 1행 전 · 12개월)
fc_derive <- function(D, yl) {
  sdv <- function(n, d) fifelse(is.finite(n) & is.finite(d) & d > 0, n / d, NA_real_)          # 분모 양수만
  sda <- function(n, d) fifelse(is.finite(n) & is.finite(d) & d != 0, n / abs(d), NA_real_)    # 부호 있는 분모 → 절댓값
  gr  <- function(x) { p <- yl(x); fifelse(is.finite(x) & is.finite(p) & p != 0, (x - p) / abs(p), NA_real_) }  # 부호 뒤집힘 없는 성장률
  avg <- function(x) { p <- yl(x); fifelse(is.finite(x) & is.finite(p), (x + p) / 2, x) }       # 1년 평균(1년 전 없으면 기말)
  dlt <- function(x) x - yl(x)
  z0 <- function(x) fifelse(is.na(x), 0, x)
  # ---- 3-1. 중간 항목 ----
  D[, ShortTermDebt := fifelse(is.na(CurrentBorr) & is.na(CurrentBonds), NA_real_, z0(CurrentBorr) + z0(CurrentBonds))]
  D[, LongTermDebt  := fifelse(is.na(LongTermBorr) & is.na(Bonds), NA_real_, z0(LongTermBorr) + z0(Bonds))]
  D[, TotalDebt     := fifelse(is.na(ShortTermDebt) & is.na(LongTermDebt), NA_real_, z0(ShortTermDebt) + z0(LongTermDebt))]
  # (2026-11-16 도훈 '나' · OP-20261116-DEBT-ZEROFILL) 퀀티는 차입금이 없는 회사에 0 행을 주지 않는다 — 총차입금이 있는 기간이면 없는 줄 = 0
  #   (옛 병합 표 규칙 · TotalDebt 는 이미 z0 합 · 2014Q4 기준 단기 있고 장기 없음 730곳 → 장기부채 비율 · PF_dLever · d_LongTermDebt 가 NA 였다)
  D[is.finite(TotalDebt) & is.na(ShortTermDebt), ShortTermDebt := 0][is.finite(TotalDebt) & is.na(LongTermDebt), LongTermDebt := 0]
  D[, NetDebtCalc   := TotalDebt - CashAndEquiv]
  D[, WorkingCapital := CurrentAssets - CurrentLiab]
  D[, NWC_NonCash   := (CurrentAssets - CashAndEquiv) - (CurrentLiab - z0(ShortTermDebt))]
  D[, BookEquity    := fifelse(!is.na(EquityParent), EquityParent, TotalEquity - z0(NonControllingInt)) - z0(PreferredCapital)]  # Fama-French(1993) 장부가치 — 우선주 제외
  D[, TangibleEquity := BookEquity - z0(Intangibles)]
  D[, FCF           := OperatingCF - Capex]
  D[, TaxRate       := fifelse(is.finite(PretaxIncome) & PretaxIncome > 0, pmin(pmax(TaxExpense / PretaxIncome, 0), 1), NA_real_)]
  D[, NOPAT         := OperatingProfit * (1 - fifelse(is.na(TaxRate), 0, TaxRate))]
  D[, NIp           := fifelse(!is.na(NetIncomeParent), NetIncomeParent, NetIncome)]                        # 지배주주 순이익(없으면 연결)
  D[, AvgAssets := avg(TotalAssets)][, AvgEquity := avg(BookEquity)][, AvgInventory := avg(Inventory)]
  D[, AvgRecv := avg(AccountsRecv)][, AvgPay := avg(AccountsPay)][, AvgInvestedCapital := avg(InvestedCapital)][, AvgPPE := avg(PPE)]
  # ---- 3-2. 수익성 ----
  D[, GrossMargin := sdv(GrossProfit, Revenue)][, OPM := sdv(OperatingProfit, Revenue)][, NetMargin := sdv(NIp, Revenue)]
  D[, PretaxMargin := sdv(PretaxIncome, Revenue)][, EBITDA_Margin := sdv(EBITDA, Revenue)][, EBIT_Margin := sdv(EBIT, Revenue)]
  D[, ROE := sdv(NIp, AvgEquity)][, ROE_End := sdv(NIp, BookEquity)]
  D[, ROA := sdv(NetIncome, AvgAssets)][, ROA_End := sdv(NetIncome, TotalAssets)]
  D[, ROIC := sdv(NOPAT, AvgInvestedCapital)][, ROIC_NOPLAT := sdv(NOPLAT, AvgInvestedCapital)]
  D[, GPA := sdv(GrossProfit, TotalAssets)]                                          # Novy-Marx(2013) 총이익 / 총자산
  D[, OPA := sdv(OperatingProfit, TotalAssets)]
  D[, OP_BE := sdv(OperatingProfit - z0(InterestExp), BookEquity)]                   # Fama-French(2015) 영업수익성
  D[, CashOP := sdv(OperatingCF, TotalAssets)]                                       # Ball et al.(2016) 현금 수익성
  D[, ComprehensiveROE := sdv(CompIncParent, AvgEquity)]
  D[, EBITDA_Assets := sdv(EBITDA, TotalAssets)]
  # ---- 3-3. 효율성 ----
  D[, AssetTurnover := sdv(Revenue, AvgAssets)][, FixedAssetTurnover := sdv(Revenue, AvgPPE)]
  D[, InventoryTurnover := sdv(COGS, AvgInventory)][, ReceivableTurnover := sdv(Revenue, AvgRecv)][, PayableTurnover := sdv(COGS, AvgPay)]
  D[, DaysInventory := sdv(365, InventoryTurnover)][, DaysReceivable := sdv(365, ReceivableTurnover)][, DaysPayable := sdv(365, PayableTurnover)]
  D[, CCC := DaysInventory + DaysReceivable - DaysPayable]
  D[, WorkingCapitalTurnover := sda(Revenue, WorkingCapital)]
  D[, RevenuePerEmployee := sdv(Revenue, Employees)][, OPPerEmployee := sdv(OperatingProfit, Employees)]
  # ---- 3-4. 안정성 · 부채 ----
  D[, DebtRatio := sdv(TotalLiab, TotalEquity)][, LiabToAssets := sdv(TotalLiab, TotalAssets)]
  D[, DebtToAssets := sdv(TotalDebt, TotalAssets)][, DebtToEquity := sdv(TotalDebt, BookEquity)]
  D[, IBDebtToAssets := sdv(InterestBearingDebt, TotalAssets)]
  D[, NetDebtToEquity := sdv(NetDebt, BookEquity)][, NetDebtToEBITDA := sdv(NetDebt, EBITDA)][, NetDebtToAssets := sdv(NetDebt, TotalAssets)]
  D[, EquityMultiplier := sdv(TotalAssets, TotalEquity)][, EquityRatio := sdv(TotalEquity, TotalAssets)]
  D[, LongTermDebtRatio := sdv(LongTermDebt, TotalAssets)][, ShortDebtShare := sdv(ShortTermDebt, TotalDebt)]
  D[, InterestCoverage := sda(OperatingProfit, InterestExp)][, EBITDA_Coverage := sda(EBITDA, InterestExp)]
  D[, ImpliedInterestRate := sdv(InterestExp, avg(TotalDebt))][, FinanceCostToRevenue := sdv(FinanceCost, Revenue)]
  # ---- 3-5. 유동성 · 자산 구성 ----
  D[, CurrentRatio := sdv(CurrentAssets, CurrentLiab)][, QuickRatio := sdv(QuickAssets, CurrentLiab)][, CashRatio := sdv(CashAndEquiv, CurrentLiab)]
  D[, CashToAssets := sdv(CashAndEquiv, TotalAssets)][, WorkingCapitalToAssets := sdv(WorkingCapital, TotalAssets)]
  D[, TangibleAssetRatio := sdv(PPE, TotalAssets)][, IntangibleRatio := sdv(Intangibles, TotalAssets)]
  D[, NonCurrentAssetRatio := sdv(NonCurrentAssets, TotalAssets)][, InvestmentsToAssets := sdv(Investments, TotalAssets)]
  D[, InventoryToAssets := sdv(Inventory, TotalAssets)][, RecvToAssets := sdv(AccountsRecv, TotalAssets)]
  # ---- 3-6. 현금흐름 · 발생액 ----
  D[, OCFToRevenue := sdv(OperatingCF, Revenue)][, OCFToNI := sda(OperatingCF, NIp)][, OCFToLiab := sdv(OperatingCF, TotalLiab)]
  D[, OCFToDebt := sdv(OperatingCF, TotalDebt)]
  D[, FCFToRevenue := sdv(FCF, Revenue)][, FCFToAssets := sdv(FCF, TotalAssets)][, FCFToEquity := sdv(FCF, BookEquity)]
  D[, CapexToRevenue := sdv(Capex, Revenue)][, CapexToAssets := sdv(Capex, AvgAssets)][, CapexToDep := sdv(Capex, DepAmortCF)]
  D[, Accrual := sdv(NetIncome - OperatingCF, AvgAssets)]                            # Sloan(1996) 현금흐름 방식 발생액
  D[, PercentAccrual := sda(NetIncome - OperatingCF, NetIncome)]                     # Hafzalla, Lundholm & Van Winkle(2011)
  D[, AccrualBS := sdv(dlt(NWC_NonCash) - z0(DepAmortCF), AvgAssets)]                # Sloan(1996) 재무상태표 방식
  D[, NOA := sdv((TotalAssets - CashAndEquiv) - (TotalLiab - z0(TotalDebt)), yl(TotalAssets))]  # Hirshleifer et al.(2004) 순영업자산
  D[, CashEarningsToNI := sda(CashEarnings, NIp)]
  # ---- 3-7. 주주환원 · 주식 수 ----
  D[, PayoutRatio := sdv(CashDivCommon, NIp)][, DividendToEquity := sdv(CashDivCommon, BookEquity)]
  D[, DividendsPaidToOCF := sdv(DividendsPaid, OperatingCF)]
  D[, SharesGrowth := gr(SharesCommonOutAdj)]                                        # 순주식발행(Pontiff & Woodgate 2008 · 1년 로그 대신 비율)
  D[, NetShareIssuance := fifelse(is.finite(SharesCommonOutAdj) & is.finite(yl(SharesCommonOutAdj)) & yl(SharesCommonOutAdj) > 0,
                                  log(SharesCommonOutAdj / yl(SharesCommonOutAdj)), NA_real_)]
  D[, BuybackRatio := sdv(BuybackShares, SharesCommonOutAdj)][, TreasuryShareRatio := sdv(TreasuryShares, SharesCommonAdj)]
  # ---- 3-8. 비용 구조 ----
  D[, COGSRatio := sdv(COGS, Revenue)][, SGARatio := sdv(SGAExpense, Revenue)][, RandDIntensity := sdv(RandD, Revenue)]
  D[, RandDToAssets := sdv(RandD, TotalAssets)][, LaborCostRatio := sdv(LaborCost, Revenue)][, AdvertisingRatio := sdv(ExpAdvertising, Revenue)]
  D[, DepAmortRatio := sdv(DepAmortCF, Revenue)][, EffectiveTaxRate := TaxRate][, NetInterestToRevenue := sdv(NetInterestExp, Revenue)]
  D[, SGAEfficiency := sdv(GrossProfit, SGAExpense)]
  # ---- 3-9. 주당 · 규모 ----
  D[, BPS := sdv(BookEquity, SharesCommonOutAdj)][, EPS := sdv(NIp, SharesCommonAvgAdj)][, SPS := sdv(Revenue, SharesCommonAvgAdj)]
  D[, CFPS := sdv(OperatingCF, SharesCommonAvgAdj)][, DPS := AdjDPS][, LogAssets := fifelse(TotalAssets > 0, log(TotalAssets), NA_real_)]
  # ---- 3-10. 성장(1년 전 대비 · 부호 뒤집힘 없음) ----
  for (it in c("Revenue", "GrossProfit", "OperatingProfit", "NetIncome", "NIp", "EBITDA", "OperatingCF", "FCF", "TotalAssets",
               "BookEquity", "Capex", "CashDivCommon", "Employees", "InvestedCapital", "Inventory", "AccountsRecv", "PPE", "TotalDebt",
               "RandD", "SGAExpense", "EPSParentAdj", "AdjDPS")) {
    if (it %in% names(D)) set(D, j = paste0(it, "_Growth"), value = gr(D[[it]]))
  }
  D[, AssetGrowth := sdv(dlt(TotalAssets), yl(TotalAssets))]                         # Cooper, Gulen & Schill(2008) · FF(2015) 투자
  D[, InvestmentFF := AssetGrowth]
  D[, PPE_InvGrowth := sdv(dlt(PPE) + dlt(Inventory), yl(TotalAssets))]              # Lyandres, Sun & Zhang(2008)
  D[, DebtGrowthToAssets := sdv(dlt(TotalDebt), yl(TotalAssets))]
  # ---- 3-11. 1년 변화(Δ) ----
  for (it in c("GPA", "ROE", "ROA", "OPM", "GrossMargin", "NetMargin", "EBITDA_Margin", "Accrual", "InterestCoverage", "DebtRatio",
               "CurrentRatio", "CashToAssets", "AssetTurnover", "EquityMultiplier", "OCFToRevenue", "SGAEfficiency", "RandDIntensity",
               "TangibleAssetRatio", "DebtToAssets", "PayoutRatio", "CashOP", "OP_BE", "LongTermDebtRatio")) {
    set(D, j = paste0("Delta_", it), value = dlt(D[[it]]))
  }
  # ---- 3-11b. 원계정 · 중간 항목의 1년 변화(d_) · 1년 전 총자산 · 5년 변화 — 팩터 층(발생액 · 투자 · 성장)이 최신 값 하나로 쓰게 ----
  D[, NOA_Level := (TotalAssets - CashAndEquiv) - (TotalLiab - z0(TotalDebt))]       # Hirshleifer et al.(2004) 순영업자산(수준)
  D[, NCO_Level := (NonCurrentAssets - z0(Investments)) - (NonCurrentLiab - z0(LongTermDebt))]  # Richardson et al.(2005) 비유동 영업자산
  for (it in c("WorkingCapital", "NWC_NonCash", "CurrentAssets", "CashAndEquiv", "CurrentLiab", "ShortTermDebt", "LongTermDebt",
               "TotalDebt", "NonCurrentAssets", "NonCurrentLiab", "Investments", "Inventory", "AccountsRecv", "AccountsPay",
               "BookEquity", "TotalEquity", "PPE", "Revenue", "TotalAssets", "TotalLiab", "NOA_Level", "NCO_Level", "NetIncome",
               "OperatingCF", "SharesCommonOutAdj")) {
    set(D, j = paste0("d_", it), value = dlt(D[[it]]))
  }
  D[, Lag_TotalAssets := yl(TotalAssets)][, Lag_NOA_Level := yl(NOA_Level)][, Lag_Accrual := yl(Accrual)]
  y5 <- function(x) Reduce(function(a, b) yl(a), 1:5, x)
  D[, GPA_Delta5 := GPA - y5(GPA)][, ROE_Delta5 := ROE_End - y5(ROE_End)]
  D[, Accrual_SD5 := NA_real_]   # 아래 3-13 에서 채운다
  # ---- 3-12. 종합 점수 ----
  # Piotroski(2000) F-score 9개 신호(1년 전 대비)
  D[, PF_ROA := as.numeric(ROA_End > 0)][, PF_CFO := as.numeric(OperatingCF > 0)][, PF_dROA := as.numeric(dlt(ROA_End) > 0)]
  D[, PF_Accrual := as.numeric(OperatingCF > NetIncome)][, PF_dLever := as.numeric(dlt(sdv(LongTermDebt, AvgAssets)) < 0)]
  D[, PF_dLiquid := as.numeric(dlt(CurrentRatio) > 0)][, PF_EqIssue := as.numeric(!(SharesCommonOutAdj > yl(SharesCommonOutAdj)))]
  D[, PF_dMargin := as.numeric(dlt(GrossMargin) > 0)][, PF_dTurn := as.numeric(dlt(sdv(Revenue, yl(TotalAssets))) > 0)]
  pf <- c("PF_ROA", "PF_CFO", "PF_dROA", "PF_Accrual", "PF_dLever", "PF_dLiquid", "PF_EqIssue", "PF_dMargin", "PF_dTurn")
  D[, PiotroskiF := fifelse(rowSums(is.na(.SD)) == 0L, rowSums(.SD), NA_real_), .SDcols = pf]
  # Altman(1983) Z' (장부가 판 — 시가총액 판은 팩터 층이 RAWDATA 시가로 만든다)
  D[, AltmanZ_Book := 0.717 * sdv(WorkingCapital, TotalAssets) + 0.847 * sdv(RetainedEarnings, TotalAssets) +
                      3.107 * sdv(EBIT, TotalAssets) + 0.420 * sdv(BookEquity, TotalLiab) + 0.998 * sdv(Revenue, TotalAssets)]
  # Ohlson(1980) O-score Model 1 — O = -1.32 - 0.407 SIZE + 6.03 TLTA - 1.43 WCTA + 0.0757 CLCA - 1.72 OENEG - 2.37 NITA - 1.83 FUTL
  #   + 0.285 INTWO - 0.521 CHIN (Ohlson, J. A. 1980, 'Financial Ratios and the Probabilistic Prediction of Bankruptcy', JAR 18(1) 109-131,
  #   https://doi.org/10.2307/2490395). SIZE = ln(총자산) — 원문은 GNP 물가지수로 나눈다: 같은 날 전 종목에 같은 상수라 횡단면 순위 · Z 에는
  #   영향이 없어 뺐다(퀀티 단독 · 외부 물가지수 없음). FUTL = 퀀티 CashEarnings(순이익 + 비현금 항목 ≈ 원문 funds from operations) / 총부채 · 없으면 영업현금흐름.
  #   INTWO = 직전 2년 순이익이 모두 음수면 1 · CHIN = (NI_t − NI_{t−1}) / (|NI_t| + |NI_{t−1}|).
  D[, O_SIZE := LogAssets][, O_TLTA := sdv(TotalLiab, TotalAssets)][, O_WCTA := sdv(WorkingCapital, TotalAssets)]
  D[, O_CLCA := sdv(CurrentLiab, CurrentAssets)][, O_OENEG := as.numeric(TotalLiab > TotalAssets)][, O_NITA := sdv(NetIncome, TotalAssets)]
  D[, O_FUTL := sdv(fifelse(is.finite(CashEarnings), CashEarnings, OperatingCF), TotalLiab)][, O_INTWO := as.numeric(NetIncome < 0 & yl(NetIncome) < 0)]
  D[, O_CHIN := fifelse(is.finite(NetIncome) & is.finite(yl(NetIncome)) & (abs(NetIncome) + abs(yl(NetIncome))) > 0,
                        (NetIncome - yl(NetIncome)) / (abs(NetIncome) + abs(yl(NetIncome))), NA_real_)]
  D[, OhlsonO := -1.32 - 0.407 * O_SIZE + 6.03 * O_TLTA - 1.43 * O_WCTA + 0.0757 * O_CLCA - 1.72 * O_OENEG - 2.37 * O_NITA -
                 1.83 * O_FUTL + 0.285 * O_INTWO - 0.521 * O_CHIN]
  # (O 확률 = 1/(1+e^{-O}) 은 싣지 않는다 — SIZE 에 물가지수가 없어 절대 수준이 원문과 다르다 · 순위 · Z 만 뜻이 있다)
  # ---- 3-13. 다년 안정성(1년 간격 5개 해 · 3개 이상 · 지속성 = 10개 해 AR(1) · 4개 이상) ----
  lagmat <- function(x, n) { M <- matrix(NA_real_, length(x), n); cur <- x; M[, 1L] <- x
    if (n > 1L) for (k in 2:n) { cur <- yl(cur); M[, k] <- cur }; M }
  roll_sd <- function(x, n = 5L, mn = 3L) {                                          # 1년 간격 n 개 해의 표본 표준편차(유한값 mn 개 이상)
    M <- lagmat(x, n); ok <- is.finite(M); cnt <- rowSums(ok); M[!ok] <- 0
    m <- rowSums(M) / pmax(cnt, 1); v <- (rowSums(M^2) - cnt * m^2) / pmax(cnt - 1, 1)
    fifelse(cnt >= mn, sqrt(pmax(v, 0)), NA_real_)
  }
  ar1 <- function(x, n = 10L, mn = 4L) {                                             # ROA_t = a + b ROA_{t-1} 의 b(1년 간격 n 개 해 · 쌍 mn-1 개 이상)
    M <- lagmat(x, n); Y <- M[, -n, drop = FALSE]; X <- M[, -1L, drop = FALSE]
    ok <- is.finite(Y) & is.finite(X); cnt <- rowSums(ok); Y[!ok] <- 0; X[!ok] <- 0
    mx <- rowSums(X) / pmax(cnt, 1); my <- rowSums(Y) / pmax(cnt, 1)
    sxy <- rowSums(X * Y) - cnt * mx * my; sxx <- rowSums(X^2) - cnt * mx^2
    fifelse(cnt >= mn - 1L & sxx > 1e-12, sxy / sxx, NA_real_)
  }
  D[, ROE_SD5 := roll_sd(ROE_End)][, ROA_SD5 := roll_sd(ROA_End)][, GrossMargin_SD5 := roll_sd(GrossMargin)]
  D[, Revenue_Growth_SD5 := roll_sd(Revenue_Growth)][, OPM_SD5 := roll_sd(OPM)]
  D[, EarningsPersistence := ar1(ROA_End)]
  D[, Accrual_SD5 := roll_sd(Accrual)][, AccrualPersistence := ar1(Accrual)]
  D[]
}

DERIVED_FD_RULE <- "derived 행 Factor_Date = max(그 행, 1년 전 행, … 다년 지표가 쓴 모든 해) — 3-10 이후 지표 · 평균 분모가 1년 전 행을 쓴다"

run_table <- function(T, yl_k, label) {
  setorder(T, Ticker, P)
  tkT <- T$Ticker; miT <- T$mi
  yl <- function(x) fifelse(shift(miT, yl_k) == miT - 12L & shift(tkT, yl_k) == tkT, shift(x, yl_k), NA)
  base_cols <- copy(names(T))   # copy — data.table 의 names() 는 := 가 제자리에서 늘린다
  T <- fc_derive(T, yl)
  der <- setdiff(names(T), base_cols)
  der <- der[!der %in% c("NIp")]
  # 날짜: 원계정(raw · raw_q) = 그 행 fd0 · 파생 = 다년 창(10개 해) 안의 최댓값 — 보수적으로 한 규칙(쓰인 해 ⊆ 10개 해)
  f_yr <- T$fd0
  f_all <- f_yr; cur <- f_yr
  for (k in 1:9) { cur <- yl(cur); f_all <- pmax(f_all, cur, na.rm = TRUE) }
  T[, fd_der := f_all]
  # 회계 베타(연간 표만 · D29): 회사 ROE(기말) 를 시장 ROE(그 회계연도 전 종목 중앙값)에 10개 해 회귀한 기울기(쌍 4개 이상)
  #   — Beaver, Kettler & Scholes(1970) 회계 베타. 시장 중앙값은 그해 대부분이 공시한 뒤에야 안다 → 날짜 = max(행 파생 날짜,
  #   창 안 각 해의 그해 종목 Factor_Date 95% 분위). 분기 표에는 만들지 않는다.
  ab_cols <- character(0)
  if (yl_k == 1L) {
    T[, FYc := P %/% 100L]
    # (PIT 수리 11-16 /simplify) 중앙값은 그 날짜(95% 분위)까지 공시된 회사만으로 — 늦게 낸 5% 의 값이 날짜보다 먼저 섞이지 않게
    mk_t <- T[is.finite(ROE_End), { q <- as.numeric(quantile(fd0, 0.95, type = 1)); .(MktROE = median(ROE_End[fd0 <= q]), mkt_fd = q) }, by = FYc]
    T[mk_t, on = .(FYc), `:=`(MktROE = i.MktROE, mkt_fd = i.mkt_fd)]
    n <- 10L; Y <- matrix(NA_real_, nrow(T), n); X <- Y; FDm <- Y
    cy <- T$ROE_End; cx <- T$MktROE; cf <- T$mkt_fd
    for (k in 1:n) { if (k > 1L) { cy <- yl(cy); cx <- yl(cx); cf <- yl(cf) }; Y[, k] <- cy; X[, k] <- cx; FDm[, k] <- cf }
    ok <- is.finite(Y) & is.finite(X); cnt <- rowSums(ok); Y[!ok] <- 0; X[!ok] <- 0
    mx <- rowSums(X) / pmax(cnt, 1); my <- rowSums(Y) / pmax(cnt, 1)
    sxy <- rowSums(X * Y) - cnt * mx * my; sxx <- rowSums(X^2) - cnt * mx^2
    T[, AccountingBeta := fifelse(cnt >= 4L & sxx > 1e-12, sxy / sxx, NA_real_)]
    FDm[!ok] <- -Inf
    T[, fd_ab := pmax(fd_der, apply(FDm, 1L, max), na.rm = TRUE)]
    T[, c("FYc", "MktROE", "mkt_fd") := NULL]
    ab_cols <- "AccountingBeta"
  }
  raw_items <- intersect(c(STOCKS, FLOWS), names(T))
  rawq <- intersect(paste0(FLOWS, "_Q"), names(T))
  mk <- function(cols, kind, fdcol) {
    L <- melt(T[, c("Ticker", "P", "Period_Date", fdcol, cols), with = FALSE], id.vars = c("Ticker", "P", "Period_Date", fdcol),
              variable.name = "Item", value.name = "Value", variable.factor = FALSE)[is.finite(Value)]
    setnames(L, fdcol, "fdn2"); L[, Kind := kind]; L
  }
  L <- rbindlist(list(mk(raw_items, "raw", "fd0"), if (yl_k == 4L) mk(rawq, "raw_q", "fd0"), mk(der, "derived", "fd_der"),
                      if (length(ab_cols)) mk(ab_cols, "derived", "fd_ab")), use.names = TRUE)   # 연간 표엔 분기 단독 값을 싣지 않는다
  der <- c(der, ab_cols)
  # 날짜 순서 계약(종목, 항목) — 늦게 도착한 옛 기간 버림 · 같은 날 = 하루씩 늦춤
  setorder(L, Ticker, Item, P)
  L[, later_min := rev(cummin(rev(c(fdn2[-1L], Inf)))), by = .(Ticker, Item)]
  n_drop <- L[fdn2 >= later_min, .N]
  L <- L[fdn2 < later_min]
  L[, fdn2 := { v <- fdn2; if (length(v) > 1L) for (i in 2:length(v)) if (v[i] <= v[i - 1L]) v[i] <- v[i - 1L] + 1; v }, by = .(Ticker, Item)]
  L[, Factor_Date := as.Date(fdn2, origin = "1970-01-01")]
  bad <- L[is.na(Factor_Date) | Factor_Date <= Period_Date, .N]
  if (bad > 0L) { say("오류: %s — Factor_Date 없거나 기간 말 이전 %d행", label, bad); quit(status = 1) }
  say("%s: 행 %s · 종목 %d · 항목 %d(원계정 %d · 분기 단독 %d · 파생 %d) · 순서 계약 버림 %s",
      label, format(nrow(L), big.mark = ","), uniqueN(L$Ticker), uniqueN(L$Item), length(raw_items), length(rawq), length(der),
      format(n_drop, big.mark = ","))
  L[, Period := as.character(P)]
  out <- L[, .(Ticker, Period, Period_Date, Factor_Date, Item, Value, Kind)]
  list(out = out, derived = der, raw = raw_items, rawq = rawq, dropped = n_drop)
}
write_atomic <- function(D, path) {
  setorder(D, Ticker, Item, Factor_Date); setindex(D, NULL)
  tmp <- paste0(path, ".tmp", Sys.getpid())
  write_parquet(D, tmp, compression = "zstd", compression_level = 5L)
  if (file.exists(path)) unlink(path)
  if (!file.rename(tmp, path)) { say("오류: 이름 바꾸기 실패 %s", tmp); quit(status = 1) }
}

QT <- copy(W)
rq <- run_table(QT, 4L, "분기(TTM)")
AT <- W[(P %% 100L) == FiscalMonth]
ra <- run_table(AT, 1L, "연간")
ra$out[, FY := as.integer(substr(Period, 1, 4))]
write_atomic(rq$out, OUTQ)
write_atomic(ra$out, OUTA)
rep <- list(schema = "fundamental_caches_report/v1", built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
            source = "quantiwise_v2_only(FUNDAMENTAL-QW-ONLY-NO-DART-20261116)", input = IN,
            quarterly = list(path = OUTQ, rows = nrow(rq$out), tickers = uniqueN(rq$out$Ticker), raw = length(rq$raw),
                             raw_q = length(rq$rawq), derived = length(rq$derived), order_dropped = rq$dropped),
            annual = list(path = OUTA, rows = nrow(ra$out), tickers = uniqueN(ra$out$Ticker), raw = length(ra$raw),
                          derived = length(ra$derived), order_dropped = ra$dropped),
            stocks = sort(intersect(ITEMS, STOCKS)), flows = sort(FLOWS), derived_items = sort(rq$derived),
            date_rule = DERIVED_FD_RULE, seconds = round(as.numeric(difftime(Sys.time(), t0, units = "secs"))))
writeLines(toJSON(rep, auto_unbox = TRUE, pretty = TRUE), file.path(dirname(OUTQ), "fundamental_caches_report.json"), useBytes = TRUE)
say("끝 · %.0f초", as.numeric(difftime(Sys.time(), t0, units = "secs")))
