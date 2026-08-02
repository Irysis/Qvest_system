#==============================================================================
# Factor DB — Value Factors (V01~V12)
#
# compute_value(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL)
#   RAWDATA:    data.table(Date, Ticker, Close, Ret, Vol, Size, Sector, BM_Ret)
#   sig_date:   signal date (Date class)
#   FUND:       fundamentals long format (Ticker, Item, Value, TTM_Value, Factor_Date)
#   CONSENSUS:  named list of data.tables, each with Date, Ticker, {metric}
#               Keys: eps_1y, bps_1y, dps_1y, etc.
#
# Returns: data.table(Ticker, Factor_Name, Raw_Value)
#
# PIT: Fund uses Factor_Date <= sig_date only. Price uses sig_date only.
#      No future data leakage.
#==============================================================================

suppressPackageStartupMessages(library(data.table))

compute_value <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {

  sig_date <- as.Date(sig_date)
  results <- list()

  # ---- Price snapshot on latest trading date <= sig_date ----
  # RAWDATA is pre-sliced (Date <= sig_d) and setkey(Date, Ticker) by builder.
  # Take the maximum Date directly without sort(unique(...)) full scan.
  snap_date <- max(RAWDATA$Date[!is.na(RAWDATA$Close) & RAWDATA$Close > 0],
                   na.rm = TRUE)
  if (is.na(snap_date) || snap_date > sig_date) snap_date <- sig_date
  snap <- RAWDATA[Date == snap_date & !is.na(Close) & Close > 0,
                  .(Ticker, Close, Size)]
  if (nrow(snap) == 0L) return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  # RAWDATA$Size IS market cap, not share count (compute_size.R:38 documents this:
  # "Size = Market Cap (RAWDATA의 Size 컬럼은 시가총액)"; factor_db_builder.R:350
  # derives SharesOutstanding as Size/Close).  The former `Close * Size` here
  # yielded Close × MarketCap — inflated ~5e3× per name — which swamped every
  # additive fundamental term (EV's TotalDebt/Cash, Tobin's Q's TotalLiab) into
  # numerical irrelevance and injected price level into every /MarketCap ratio.
  # Verified 2026-08-02: back-solving MarketCap out of the stored V18_AM/V08_PSR
  # matched Close*Size at 100%/99.78%; A005930 Size = 1952.7e12 KRW = its actual
  # market cap, Size/Close = 5.85e9 = its actual share count.
  snap[, MarketCap := Size]
  snap[, SharesOut := fifelse(Close > 0, Size / Close, NA_real_)]
  snap <- snap[MarketCap > 0]

  # ---- Helper: get latest PIT fundamental (wide) ----
  fund_wide <- NULL
  if (!is.null(FUND) && nrow(FUND) > 0L) {
    # FUND may already be pre-filtered (FUND_pit from builder), or full FUND.
    # Either way, apply PIT filter then take latest per Ticker×Item.
    fund_pit <- if ("Factor_Date" %in% names(FUND)) FUND[Factor_Date <= sig_date]
                else if ("Date" %in% names(FUND)) FUND[Date <= sig_date]
                else FUND
    if (nrow(fund_pit) > 0L) {
      # For P/L and CF items, prefer TTM_Value; for B/S items, use Value
      # setorder + .SD[.N] avoids O(N) which.max scan per group
      if ("Factor_Date" %in% names(fund_pit)) {
        setorder(fund_pit, Ticker, Item, Factor_Date)
      }
      fund_latest <- fund_pit[, .SD[.N], by = .(Ticker, Item)]
      if ("TTM_Value" %in% names(fund_latest)) {
        fund_latest[, use_val := fifelse(!is.na(TTM_Value), TTM_Value, Value)]
      } else {
        fund_latest[, use_val := Value]
      }
      fund_wide <- dcast(fund_latest, Ticker ~ Item, value.var = "use_val")
    }
  }

  # ---- Helper: get consensus snapshot (latest row <= sig_date per Ticker) ----
  # CONSENSUS is a named list of data.tables (e.g., CONSENSUS$eps_1y, CONSENSUS$bps_1y, ...)
  cs_snap <- NULL
  if (!is.null(CONSENSUS) && is.list(CONSENSUS) && length(CONSENSUS) > 0L) {
    cs_parts <- list()
    for (cs_nm in intersect(names(CONSENSUS), c("eps_1y", "bps_1y", "dps_1y"))) {
      cs_dt <- CONSENSUS[[cs_nm]]
      if (!is.null(cs_dt) && is.data.table(cs_dt) && nrow(cs_dt) > 0L && "Date" %in% names(cs_dt)) {
        cs_pit <- cs_dt[Date <= sig_date]
        if (nrow(cs_pit) > 0L) {
          setorder(cs_pit, Ticker, -Date)
          latest <- cs_pit[, .SD[1L], by = Ticker]
          # Keep only Ticker and the metric column (exclude Date)
          metric_col <- setdiff(names(latest), c("Date", "Ticker"))
          if (length(metric_col) >= 1L) {
            cs_parts[[cs_nm]] <- latest[, c("Ticker", metric_col[1L]), with = FALSE]
          }
        }
      }
    }
    if (length(cs_parts) > 0L) {
      cs_snap <- cs_parts[[1L]]
      if (length(cs_parts) > 1L) {
        for (i in 2:length(cs_parts)) {
          cs_snap <- merge(cs_snap, cs_parts[[i]], by = "Ticker", all = TRUE)
        }
      }
    }
  }

  # ---- Merge fund + price ----
  dt <- copy(snap)
  if (!is.null(fund_wide)) {
    dt <- merge(dt, fund_wide, by = "Ticker", all.x = TRUE)
  }
  # Ensure fundamental columns exist
  fund_cols_needed <- c("TotalEquity", "PretaxIncome", "TaxExpense",
                        "OperatingCF", "Revenue", "OperatingProfit",
                        "DepAmort", "ShortTermBorr", "LongTermBorr",
                        "CashAndEquiv", "InvestCF", "Dividends")
  for (fc in fund_cols_needed) {
    if (!fc %in% names(dt)) dt[, (fc) := NA_real_]
  }

  # ---- Derived fundamentals ----
  dt[, NetIncome := fifelse(!is.na(PretaxIncome) & !is.na(TaxExpense),
                            PretaxIncome - TaxExpense, NA_real_)]
  dt[, EBITDA := fifelse(!is.na(OperatingProfit) & !is.na(DepAmort),
                         OperatingProfit + DepAmort, NA_real_)]
  # TotalDebt / Cash: absent input => NA (uncovered), never a silently zeroed term.
  # A firm that reported neither borrowing line has UNKNOWN debt, not zero debt;
  # zeroing it made EV collapse onto MarketCap and manufactured false coverage.
  # A firm that reported at least one line is treated as having zero on the other
  # (KR filings omit nil balances), but the all-absent case propagates NA.
  dt[, debt_reported := (!is.na(ShortTermBorr)) + (!is.na(LongTermBorr))]
  dt[, TotalDebt := fifelse(debt_reported > 0L,
                            fifelse(!is.na(ShortTermBorr), ShortTermBorr, 0) +
                              fifelse(!is.na(LongTermBorr), LongTermBorr, 0),
                            NA_real_)]
  dt[, Cash := CashAndEquiv]   # no substitution: unreported cash stays NA
  # CapEx approximation: -InvestCF (investment CF is typically negative)
  dt[, CapEx := fifelse(!is.na(InvestCF), -InvestCF, NA_real_)]

  # ---- Merge consensus ----
  if (!is.null(cs_snap)) {
    cs_cols <- intersect(names(cs_snap), c("Ticker", "eps_1y", "bps_1y", "dps_1y"))
    if (length(cs_cols) >= 2L) {
      dt <- merge(dt, cs_snap[, ..cs_cols], by = "Ticker", all.x = TRUE)
    }
  }
  for (cc in c("eps_1y", "bps_1y", "dps_1y")) {
    if (!cc %in% names(dt)) dt[, (cc) := NA_real_]
  }

  # ==== V01: BM (Book-to-Market) ====
  # TotalEquity / MarketCap.  MarketCap = Size (RAWDATA); SharesOut = Size / Close.
  dt[, V01 := fifelse(!is.na(TotalEquity) & TotalEquity > 0,
                      TotalEquity / MarketCap, NA_real_)]
  results[["V01_BM"]] <- dt[!is.na(V01), .(Ticker, Factor_Name = "V01_BM", Raw_Value = V01)]

 # ==== V02: EP (Earnings-to-Price) ====
  dt[, V02 := fifelse(!is.na(NetIncome), NetIncome / MarketCap, NA_real_)]
  results[["V02_EP"]] <- dt[!is.na(V02), .(Ticker, Factor_Name = "V02_EP", Raw_Value = V02)]

  # ==== V03: CFP (Cash Flow-to-Price) ====
  dt[, V03 := fifelse(!is.na(OperatingCF), OperatingCF / MarketCap, NA_real_)]
  results[["V03_CFP"]] <- dt[!is.na(V03), .(Ticker, Factor_Name = "V03_CFP", Raw_Value = V03)]

  # ==== V04: fPER (Forward PER) ====
  # Close / consensus eps_1y.  Only when eps_1y > 0 (positive earnings).
  dt[, V04 := fifelse(!is.na(eps_1y) & eps_1y > 0, Close / eps_1y, NA_real_)]
  results[["V04_fPER"]] <- dt[!is.na(V04), .(Ticker, Factor_Name = "V04_fPER", Raw_Value = V04)]

  # ==== V05: fPBR (Forward PBR) ====
  dt[, V05 := fifelse(!is.na(bps_1y) & bps_1y > 0, Close / bps_1y, NA_real_)]
  results[["V05_fPBR"]] <- dt[!is.na(V05), .(Ticker, Factor_Name = "V05_fPBR", Raw_Value = V05)]

  # ==== V06: fDY (Forward Dividend Yield) ====
  dt[, V06 := fifelse(!is.na(dps_1y) & dps_1y > 0, dps_1y / Close, NA_real_)]
  results[["V06_fDY"]] <- dt[!is.na(V06), .(Ticker, Factor_Name = "V06_fDY", Raw_Value = V06)]

  # ==== V07: EV/EBITDA ====
  # EV = MarketCap + TotalDebt - Cash.  Only when EBITDA > 0.
  # NA in TotalDebt or Cash propagates to EV by design: an EV factor whose debt or
  # cash input is absent is UNCOVERED, not "EV == MarketCap".  Collapsing it to
  # MarketCap is what made V13_EV_Sales rank-identical to V08_PSR.
  dt[, EV := MarketCap + TotalDebt - Cash]
  dt[, V07 := fifelse(!is.na(EBITDA) & EBITDA > 0, EV / EBITDA, NA_real_)]
  results[["V07_EV_EBITDA"]] <- dt[!is.na(V07), .(Ticker, Factor_Name = "V07_EV_EBITDA", Raw_Value = V07)]

  # ==== V08: PSR (Price-to-Sales) ====
  dt[, V08 := fifelse(!is.na(Revenue) & Revenue > 0, MarketCap / Revenue, NA_real_)]
  results[["V08_PSR"]] <- dt[!is.na(V08), .(Ticker, Factor_Name = "V08_PSR", Raw_Value = V08)]

  # ==== V09: PEG ====
  # fPER / EPS growth rate.  EPS growth = (eps_1y - trailing EPS) / |trailing EPS|.
  # Trailing EPS = NetIncome / SharesOut.  (Size is market cap, NOT share count —
  # dividing by Size yielded an earnings *yield* that was then differenced against
  # a per-share consensus EPS, inflating eps_growth by ~1e5.)
  dt[, trailing_eps := fifelse(!is.na(NetIncome) & !is.na(SharesOut) & SharesOut > 0,
                               NetIncome / SharesOut, NA_real_)]
  dt[, eps_growth := fifelse(!is.na(eps_1y) & !is.na(trailing_eps) & abs(trailing_eps) > 1e-6,
                             (eps_1y - trailing_eps) / abs(trailing_eps), NA_real_)]
  dt[, V09 := fifelse(!is.na(V04) & !is.na(eps_growth) & eps_growth > 0.01,
                      V04 / (eps_growth * 100), NA_real_)]  # PEG = PER / (growth%)
  results[["V09_PEG"]] <- dt[!is.na(V09) & is.finite(V09),
                             .(Ticker, Factor_Name = "V09_PEG", Raw_Value = V09)]

  # ==== V10: FCF Yield ====
  # (OperatingCF - CapEx) / MarketCap
  dt[, V10 := fifelse(!is.na(OperatingCF) & !is.na(CapEx),
                      (OperatingCF - CapEx) / MarketCap, NA_real_)]
  results[["V10_FCF_Yield"]] <- dt[!is.na(V10), .(Ticker, Factor_Name = "V10_FCF_Yield", Raw_Value = V10)]

  # ==== V11: Shareholder Yield ====
  # (Dividends + Buybacks) / MarketCap
  # SBB (stock buyback) is share count, not amount — approximate buyback value = 0 if unavailable
  # Dividends from fundamentals (cash flow item)
  dt[, V11 := fifelse(!is.na(Dividends) & Dividends > 0,
                      Dividends / MarketCap, NA_real_)]
  results[["V11_Shareholder_Yield"]] <- dt[!is.na(V11),
                                           .(Ticker, Factor_Name = "V11_Shareholder_Yield", Raw_Value = V11)]

  # ==== V12: Composite Value ====
  # mean(z(-fPER) + z(-fPBR) + z(fDY) + z(CFP))
  # Compute z-scores across the cross-section
  z_safe <- function(x) {
    s <- sd(x, na.rm = TRUE)
    if (is.na(s) || s < 1e-8) return(rep(NA_real_, length(x)))
    (x - mean(x, na.rm = TRUE)) / s
  }

  # Need tickers that have all 4 components
  dt[, z_neg_fPER := fifelse(!is.na(V04) & V04 > 0, z_safe(-V04), NA_real_)]
  dt[, z_neg_fPBR := fifelse(!is.na(V05) & V05 > 0, z_safe(-V05), NA_real_)]
  dt[, z_fDY      := fifelse(!is.na(V06), z_safe(V06), NA_real_)]
  dt[, z_CFP      := fifelse(!is.na(V03), z_safe(V03), NA_real_)]

  # Count non-NA components per ticker; require at least 2
  dt[, n_comp := (!is.na(z_neg_fPER)) + (!is.na(z_neg_fPBR)) +
                 (!is.na(z_fDY)) + (!is.na(z_CFP))]
  dt[n_comp >= 2L, V12 := rowMeans(.SD, na.rm = TRUE),
     .SDcols = c("z_neg_fPER", "z_neg_fPBR", "z_fDY", "z_CFP")]
  results[["V12_Composite_Value"]] <- dt[!is.na(V12),
                                         .(Ticker, Factor_Name = "V12_Composite_Value", Raw_Value = V12)]

  # ==========================================================================
  # V13~V24: Additional Value Factors (from extraction report)
  # ==========================================================================

  # ---- Ensure additional fundamental columns exist ----
  extra_fund_cols <- c("TotalAssets", "COGS", "GrossProfit", "SGAExpense",
                       "TotalLiab", "CurrentAssets", "CurrentLiab",
                       "RetainedEarnings", "InterestExp", "NOPAT",
                       "CapitalStock")
  for (fc in extra_fund_cols) {
    if (!fc %in% names(dt)) dt[, (fc) := NA_real_]
  }

  # ==== V13: EV/Sales (Enterprise Value to Sales) ====
  # EV = MarketCap + TotalDebt - Cash.  Inverse of Sales/EV.
  # Low EV/Sales = cheap on revenue basis.  Loughran-Wellman (2011) variant.
  dt[, V13 := fifelse(!is.na(Revenue) & Revenue > 0, EV / Revenue, NA_real_)]
  results[["V13_EV_Sales"]] <- dt[!is.na(V13) & is.finite(V13),
                                  .(Ticker, Factor_Name = "V13_EV_Sales", Raw_Value = V13)]

  # ==== V14: EBIT/EV (Earnings yield on enterprise value) ====
  # Greenblatt Magic Formula component.  EBIT = OperatingProfit.
  dt[, V14 := fifelse(!is.na(OperatingProfit) & EV > 0,
                      OperatingProfit / EV, NA_real_)]
  results[["V14_EBIT_EV"]] <- dt[!is.na(V14) & is.finite(V14),
                                  .(Ticker, Factor_Name = "V14_EBIT_EV", Raw_Value = V14)]

  # ==== V15: Net Debt-Adjusted EP ====
  # (NetIncome + InterestExp) / (MarketCap + NetDebt)
  # Adjusts earnings yield for capital structure differences.
  dt[, NetDebt := TotalDebt - Cash]
  dt[, V15 := fifelse(!is.na(NetIncome) & !is.na(InterestExp) & (MarketCap + NetDebt) > 0,
                      (NetIncome + fifelse(!is.na(InterestExp), InterestExp, 0)) /
                        (MarketCap + NetDebt), NA_real_)]
  results[["V15_NetDebt_Adj_EP"]] <- dt[!is.na(V15) & is.finite(V15),
                                         .(Ticker, Factor_Name = "V15_NetDebt_Adj_EP", Raw_Value = V15)]

  # ==== V16: Tobin's Q proxy ====
  # (MarketCap + TotalLiab) / TotalAssets.  Low Q = undervalued vs replacement cost.
  dt[, V16 := fifelse(!is.na(TotalAssets) & TotalAssets > 0 & !is.na(TotalLiab),
                      (MarketCap + TotalLiab) / TotalAssets, NA_real_)]
  results[["V16_Tobins_Q"]] <- dt[!is.na(V16) & is.finite(V16),
                                   .(Ticker, Factor_Name = "V16_Tobins_Q", Raw_Value = V16)]

  # ==== V17: Dividend Payout Ratio (trailing) ====
  # Dividends / NetIncome.  Higher payout = more shareholder-friendly value signal.
  dt[, V17 := fifelse(!is.na(Dividends) & Dividends > 0 & !is.na(NetIncome) & NetIncome > 0,
                      Dividends / NetIncome, NA_real_)]
  results[["V17_Payout_Ratio"]] <- dt[!is.na(V17) & is.finite(V17),
                                       .(Ticker, Factor_Name = "V17_Payout_Ratio", Raw_Value = V17)]

  # ==== V18: Total Assets to Market (AM) ====
  # Fama-French (1992) alternative value measure using total assets.
  dt[, V18 := fifelse(!is.na(TotalAssets) & TotalAssets > 0,
                      TotalAssets / MarketCap, NA_real_)]
  results[["V18_AM"]] <- dt[!is.na(V18) & is.finite(V18),
                             .(Ticker, Factor_Name = "V18_AM", Raw_Value = V18)]

  # ==== V19: Debt-to-Market ====
  # Bhandari (1988). High leverage firms earn higher returns cross-sectionally.
  dt[, V19 := fifelse(TotalDebt > 0,
                      TotalDebt / MarketCap, NA_real_)]
  results[["V19_Debt_to_Market"]] <- dt[!is.na(V19) & is.finite(V19),
                                         .(Ticker, Factor_Name = "V19_Debt_to_Market", Raw_Value = V19)]

  # ==== V20: Sales-to-Price (SP) ====
  # Inverse of PSR. Barbee, Mukherji, Raines (1996). Revenue / MarketCap.
  dt[, V20 := fifelse(!is.na(Revenue) & Revenue > 0,
                      Revenue / MarketCap, NA_real_)]
  results[["V20_SP"]] <- dt[!is.na(V20) & is.finite(V20),
                             .(Ticker, Factor_Name = "V20_SP", Raw_Value = V20)]

  # ==== V21: Composite Equity Issuance ====
  # log(ME_t / ME_{t-5yr}) - log(1 + R_{t-5yr}).
  # Captures net equity issuance; needs 5-year price history from RAWDATA.
  # Approximation: use 1260 trading days (~5 years).
  price_hist <- RAWDATA[Date <= sig_date & !is.na(Close) & Close > 0 & !is.na(Size)]
  setorder(price_hist, Ticker, Date)
  cei_dt <- price_hist[, {
    n <- .N
    cei_val <- NA_real_
    if (n >= 252L) {  # at least 1 year
      lookback <- min(n, 1260L)
      # ME = market cap = Size directly.  The former `Close * Size` made the Close
      # ratio cancel against log(1 + cum_ret) below, silently reducing CEI to plain
      # market-cap growth and deleting the issuance signal the factor exists for.
      me_now  <- Size[n]
      me_past <- Size[n - lookback + 1L]
      if (me_now > 0 && me_past > 0) {
        cum_ret <- Close[n] / Close[n - lookback + 1L] - 1
        cei_val <- log(me_now / me_past) - log(1 + cum_ret)
      }
    }
    list(V21 = cei_val)
  }, by = Ticker]
  dt <- merge(dt, cei_dt, by = "Ticker", all.x = TRUE)
  results[["V21_Composite_Equity_Issuance"]] <- dt[!is.na(V21) & is.finite(V21),
    .(Ticker, Factor_Name = "V21_Composite_Equity_Issuance", Raw_Value = V21)]

  # ==== V22: FCFF/EV (Free Cash Flow to Firm yield on EV) ====
  # FCFF = OperatingCF - CapEx.  FCFF/EV is a capital-structure-neutral value measure.
  dt[, V22 := fifelse(!is.na(OperatingCF) & !is.na(CapEx) & EV > 0,
                      (OperatingCF - CapEx) / EV, NA_real_)]
  results[["V22_FCFF_EV"]] <- dt[!is.na(V22) & is.finite(V22),
                                  .(Ticker, Factor_Name = "V22_FCFF_EV", Raw_Value = V22)]

  # ==== V23: Fundamental Indexation Weight (RAFI proxy) ====
  # Arnott et al. Composite of sales, CF, book value, dividends relative to universe total.
  # Computed as average of (Revenue/Sum, OCF/Sum, TotalEquity/Sum, Dividends/Sum).
  rev_sum <- sum(dt$Revenue, na.rm = TRUE)
  ocf_sum <- sum(dt$OperatingCF, na.rm = TRUE)
  bv_sum  <- sum(dt$TotalEquity, na.rm = TRUE)
  div_sum <- sum(dt$Dividends, na.rm = TRUE)

  dt[, rafi_rev := fifelse(!is.na(Revenue) & rev_sum > 0, Revenue / rev_sum, NA_real_)]
  dt[, rafi_ocf := fifelse(!is.na(OperatingCF) & ocf_sum > 0, OperatingCF / ocf_sum, NA_real_)]
  dt[, rafi_bv  := fifelse(!is.na(TotalEquity) & bv_sum > 0, TotalEquity / bv_sum, NA_real_)]
  dt[, rafi_div := fifelse(!is.na(Dividends) & div_sum > 0, Dividends / div_sum, NA_real_)]
  dt[, rafi_n := (!is.na(rafi_rev)) + (!is.na(rafi_ocf)) + (!is.na(rafi_bv)) + (!is.na(rafi_div))]
  dt[rafi_n >= 2L, V23 := rowMeans(.SD, na.rm = TRUE),
     .SDcols = c("rafi_rev", "rafi_ocf", "rafi_bv", "rafi_div")]
  results[["V23_RAFI_Weight"]] <- dt[!is.na(V23) & is.finite(V23),
                                      .(Ticker, Factor_Name = "V23_RAFI_Weight", Raw_Value = V23)]

  # ==== V24: Residual Income proxy ====
  # RI = NetIncome - (Equity * CoE).  CoE proxy = risk-free + 5% equity premium.
  # Uses 5% as simple equity premium assumption (no CAPM beta here).
  # Scaled by MarketCap for cross-section comparability.
  # DATA_NEEDED: risk_free_rate (using 3% as static proxy if unavailable)
  COE_PROXY <- 0.08  # 3% rf + 5% ERP
  dt[, V24 := fifelse(!is.na(NetIncome) & !is.na(TotalEquity) & TotalEquity > 0,
                      (NetIncome - TotalEquity * COE_PROXY) / MarketCap, NA_real_)]
  results[["V24_Residual_Income"]] <- dt[!is.na(V24) & is.finite(V24),
                                          .(Ticker, Factor_Name = "V24_Residual_Income", Raw_Value = V24)]

  # ---- Combine all ----
  out <- rbindlist(results, use.names = TRUE)
  return(out)
}
