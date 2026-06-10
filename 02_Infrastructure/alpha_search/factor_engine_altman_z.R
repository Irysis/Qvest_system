# =============================================================================
# factor_engine_altman_z.R — Altman (1968, JF) Z-Score 완전 복제 (KR)
# =============================================================================
# "Financial Ratios, Discriminant Analysis and the Prediction of Corporate
#  Bankruptcy" (Journal of Finance, 1968). Altman 5-variable bankruptcy
#  discriminant. 高 Z = 저distress(우량·safe) → long-only top-N.
#
# === Altman 1968 Z-Score (계수 논문 원전 그대로) ===
#   Z = 1.2·X1 + 1.4·X2 + 3.3·X3 + 0.6·X4 + 1.0·X5
#     X1 = Working Capital / Total Assets   (운전자본/총자산)
#          = (CurrentAssets - CurrentLiab) / TotalAssets        [stock]
#     X2 = Retained Earnings / Total Assets (이익잉여금/총자산)
#          = RetainedEarnings / TotalAssets                     [stock]
#     X3 = EBIT / Total Assets              (EBIT/총자산)
#          = OperatingProfit_ttm / TotalAssets                  [flow→TTM]
#     X4 = Market Value of Equity / Total Liabilities (시가총액/총부채)
#          = MarketCap(Size) / TotalLiab                        [stock+market]
#          ★원전 1968 Z = market equity / book total liab (Z'' 변형의 book equity 아님).
#     X5 = Sales / Total Assets             (매출/총자산)
#          = Revenue_ttm / TotalAssets                          [flow→TTM]
#   부호: 高 Z = bankruptcy 위험 낮음 = safe zone(Z>2.99) = 우량 → long(매수 우선).
#
#   ★ 복제 충실도 한계 (명시):
#     - X3 EBIT: KR fundamental DB의 raw `EBIT` Item은 2015-12~만 존재(narrow,
#       2005 시작 백테 불가) → 표준 EBIT proxy인 **OperatingProfit(영업이익)** 사용
#       (2000-03~ 광역). 영업이익 = 영업단계 이익 = Altman EBIT의 통용 KR 대용
#       (Altman 원전 EBIT은 이자·세금 차감 전 — 영업이익이 가장 근사).
#       OperatingProfit 결측 분기는 PretaxIncome + InterestExp fallback(세전+이자).
#     - X4 분모 Total Liabilities = TotalLiab(총부채, book). 분자는 시가(MarketCap=Size).
#       원전 정의(market equity / book liab) 그대로.
#     - flow(EBIT/Sales)는 분기 discrete → TTM(trailing 4Q) 합. 분기 4개 미만 NA.
#
# === 데이터 ===
#   재무: .cache/fundamental_merged.parquet (long: Ticker/Period/Period_Date/
#     Factor_Date/Item/Value). Factor_Date = PIT 가용일(이미 lag 반영, C4 충족).
#   시총: RAWDATA$Size (월말, MarketCap).
#   Item push-down 1회 로드(매 run arrow 0회 — Piotroski/Mohanram 캐시 슬라이스 동일).
#
# === PIT ===
#   Factor_Date <= sig_date 만 사용(C4 재무 lag 이미 반영). 동일시점 순환 없음.
#   월말 sig_date 각각에 "Factor_Date<=sig_date 중 최신 분기"의 Z-Score 사용(rolling join).
#   시총(Size)은 sig_date 시점 월말값(횡단면, lookahead 아님). X4는 동시점 시총/직전 가용 부채.
#
# universe(K200_KQ150)·start_date(2005~)·top-N 선택은 run_alpha_search가 처리.
# 산출: FACTORS(Date, Ticker, Score=Z). 高 Z = 매수 우선.
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
suppressMessages({library(arrow); library(data.table)})

.FUND_PQ <- file.path(Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"), ".cache", "fundamental_merged.parquet")
stopifnot(file.exists(.FUND_PQ))

# ---- 1. 필요한 raw 항목만 1회 로드 (OOM 회피: Item push-down) -----------------
.items_need <- c("TotalAssets", "TotalLiab", "RetainedEarnings", "Revenue",
                 "CurrentAssets", "CurrentLiab",
                 "OperatingProfit", "PretaxIncome", "InterestExp")
.fd <- as.data.table(read_parquet(
  .FUND_PQ,
  col_select = c("Ticker", "Period", "Period_Date", "Factor_Date", "Item", "Value")))
.fd <- .fd[Item %in% .items_need & is.finite(Value)]
# 동일 (Ticker,Period,Item) 복수 Source → Factor_Date 가장 이른(=가장 먼저 가용) 행 1개
setorder(.fd, Ticker, Item, Period, Factor_Date)
.fd <- .fd[, .SD[1], by = .(Ticker, Item, Period)]

# wide: 한 행 = (Ticker, Period) 모든 항목 + 그 Period의 Factor_Date(가용일)
.fad <- .fd[, .(Factor_Date = max(Factor_Date)), by = .(Ticker, Period, Period_Date)]
.w   <- dcast(.fd, Ticker + Period ~ Item, value.var = "Value")
.w   <- merge(.w, .fad, by = c("Ticker", "Period"))
setorder(.w, Ticker, Period)

# 누락 항목 NA 컬럼 보장
for (cc in .items_need) if (!cc %in% names(.w)) .w[[cc]] <- NA_real_

# ---- 2. TTM flow (trailing 4Q 합): EBIT(영업이익)·Sales -----------------------
.flow <- c("OperatingProfit", "Revenue", "PretaxIncome", "InterestExp")
for (cc in .flow)
  .w[, (paste0(cc, "_ttm")) := frollsum(get(cc), 4L, align = "right"), by = Ticker]

# EBIT(TTM): OperatingProfit 우선, 결측 시 PretaxIncome + InterestExp fallback(세전+이자)
.w[, EBIT_ttm := fifelse(is.finite(OperatingProfit_ttm), OperatingProfit_ttm,
                         PretaxIncome_ttm + InterestExp_ttm)]

# ---- 3. 5 variables (Altman 1968 정의) ---------------------------------------
.w[, X1 := (CurrentAssets - CurrentLiab) / TotalAssets]   # 운전자본/총자산
.w[, X2 := RetainedEarnings / TotalAssets]                # 이익잉여금/총자산
.w[, X3 := EBIT_ttm / TotalAssets]                        # EBIT(영업이익TTM)/총자산
# X4(시가/부채)는 시총(RAWDATA Size)이 필요 → 매핑 후 계산. 여기선 TotalLiab만 보존.
.w[, X5 := Revenue_ttm / TotalAssets]                     # 매출(TTM)/총자산

# ---- 4. PIT-safe 분기 레코드 (Factor_Date 유효 + 핵심 분모 유효) ---------------
.AZq <- .w[is.finite(Factor_Date) & is.finite(TotalAssets) & TotalAssets > 0 &
           is.finite(TotalLiab)  & TotalLiab  > 0,
           .(Ticker, Factor_Date, Period, X1, X2, X3, X5, TotalLiab)]
setorder(.AZq, Ticker, Factor_Date)

# ---- 5. 월말 sig_date 추출 ----------------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)

# ---- 6. 각 sig_date에 PIT-safe 최신 분기 매핑 (Factor_Date <= sig_date 중 최신) -
.grid <- CJ(Ticker = unique(.AZq$Ticker), Date = .month_ends)
setkey(.AZq, Ticker, Factor_Date)
setkey(.grid, Ticker, Date)
.mapped <- .AZq[.grid, on = .(Ticker, Factor_Date = Date), roll = TRUE,
                .(Ticker, Date = Factor_Date, X1, X2, X3, X5, TotalLiab)]
.mapped <- .mapped[is.finite(X1) & is.finite(X2) & is.finite(X3) & is.finite(X5)]

# ---- 7. 시총(Size) 결합 → X4 = 시가총액 / 총부채 ------------------------------
.mc <- unique(RAWDATA[Date %in% .month_ends & is.finite(Size), .(Date, Ticker, MC = Size)])
.mapped <- merge(.mapped, .mc, by = c("Date", "Ticker"))
.mapped <- .mapped[is.finite(MC) & MC > 0]
.mapped[, X4 := MC / TotalLiab]                            # 시가총액/총부채

# ---- 8. Z-Score = Altman 1968 계수 (원전 그대로) ------------------------------
.mapped[, Z := 1.2 * X1 + 1.4 * X2 + 3.3 * X3 + 0.6 * X4 + 1.0 * X5]
.AZ <- .mapped[is.finite(Z), .(Date, Ticker, Z)]

# ---- 9. FACTORS 산출 (유동성 통과 종목만) -------------------------------------
.liq <- RAWDATA[Date %in% .month_ends & LiqPass == TRUE, .(Date, Ticker)]
FACTORS <- merge(.AZ, .liq, by = c("Date", "Ticker"))[, .(Date, Ticker, Score = Z)]

RAWDATA[, .ym := NULL]
cat(sprintf("[altman_z] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
# 진단(신호 구성과 무관 — Z는 위 1.2*X1+..로 이미 종목별 산출 완료. 횡단면 분포 요약만):
.zs <- FACTORS$Score
cat(sprintf("[altman_z] Z range min=%.2f mean=%.2f max=%.2f | safe(Z>2.99)=%.1f%% distress(Z<1.81)=%.1f%%\n",
            min(.zs), mean(.zs), max(.zs),
            100 * mean(.zs > 2.99), 100 * mean(.zs < 1.81)))
