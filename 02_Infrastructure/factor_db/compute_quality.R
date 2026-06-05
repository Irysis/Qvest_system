#==============================================================================
# compute_quality.R — Quality Factor 계산 모듈 (Q01~Q35)
#
# 함수: compute_quality(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL)
# 반환: data.table(Ticker, Factor_Name, Raw_Value)
#
# PIT 준수: Factor_Date <= sig_date (재무제표), expanding z-score
# 미래참조 금지: C1~C11 체크리스트 준수
#
# Q01~Q08: Original factors
# Q09~Q35: New quality factors (27 additional)
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

compute_quality <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {
  sig_d <- as.Date(sig_date)
  results <- list()

  # --- Fundamental 데이터 준비 (PIT: Factor_Date <= sig_date) ---
  if (!is.null(FUND) && nrow(FUND) > 0) {
    fund <- copy(FUND)
    if ("Factor_Date" %in% names(fund)) {
      fund <- fund[Factor_Date <= sig_d]
    } else if ("Date" %in% names(fund)) {
      fund <- fund[Date <= sig_d]
      setnames(fund, "Date", "Factor_Date")
    }

    # 최신 재무 데이터 추출 (종목별 가장 최근 Factor_Date)
    # wide 형식(Item 컬럼 없이 직접 컬럼) vs long 형식(Item, Value) 분기
    if ("Item" %in% names(fund)) {
      # Long 형식 → wide pivot (prefer TTM_Value for P/L & CF items)
      # setorder + .SD[.N] is faster than .SD[which.max(Factor_Date)] for large tables
      setorder(fund, Ticker, Item, Factor_Date)
      fund_latest <- fund[, .SD[.N], by = .(Ticker, Item)]
      if ("TTM_Value" %in% names(fund_latest)) {
        fund_latest[, use_val := fifelse(!is.na(TTM_Value), TTM_Value, Value)]
      } else {
        fund_latest[, use_val := Value]
      }
      fund_wide <- dcast(fund_latest, Ticker ~ Item, value.var = "use_val")
    } else {
      # Wide 형식: 종목별 최신 행
      setorder(fund, Ticker, Factor_Date)
      fund_wide <- fund[, .SD[.N], by = Ticker]
    }

    # 컬럼 표준화: FUND Item names → compute_quality expected names
    # FUND uses: CurrentLiab, TotalLiab, ShortTermBorr, LongTermBorr, CashAndEquiv,
    #            OperatingProfit, InterestExp, AccountsRecv, SGAExpense, RandD, etc.
    # Code expects: CurrentLiabilities, TotalLiabilities, TotalDebt, LongTermDebt,
    #               Cash, OperatingIncome, InterestExpense, AccountsReceivable, SGA, RnD, etc.
    alias_map <- c(
      CurrentLiab       = "CurrentLiabilities",
      TotalLiab         = "TotalLiabilities",
      LongTermBorr      = "LongTermDebt",
      CashAndEquiv      = "Cash",
      OperatingProfit    = "OperatingIncome",
      InterestExp        = "InterestExpense",
      AccountsRecv       = "AccountsReceivable",
      SGAExpense         = "SGA",
      RandD              = "RnD",
      OrdRandD           = "RnDExpense",
      DepAmort           = "DepAmort",
      PretaxIncome       = "PretaxIncome",
      TaxExpense         = "TaxExpense"
    )
    for (from_nm in names(alias_map)) {
      to_nm <- alias_map[[from_nm]]
      if (from_nm %in% names(fund_wide) && !to_nm %in% names(fund_wide)) {
        setnames(fund_wide, from_nm, to_nm)
      }
    }
    # Derive TotalDebt = ShortTermBorr + LongTermDebt (if not already present)
    if (!"TotalDebt" %in% names(fund_wide)) {
      stb <- if ("ShortTermBorr" %in% names(fund_wide)) fund_wide$ShortTermBorr else 0
      ltd <- if ("LongTermDebt" %in% names(fund_wide)) fund_wide$LongTermDebt else 0
      fund_wide[, TotalDebt := fifelse(!is.na(stb) | !is.na(ltd),
                                       fifelse(is.na(stb), 0, stb) + fifelse(is.na(ltd), 0, ltd),
                                       NA_real_)]
    }
    # Derive NetIncome = PretaxIncome - TaxExpense (if not already present)
    if (!"NetIncome" %in% names(fund_wide)) {
      if (all(c("PretaxIncome", "TaxExpense") %in% names(fund_wide))) {
        fund_wide[, NetIncome := fifelse(!is.na(PretaxIncome) & !is.na(TaxExpense),
                                         PretaxIncome - TaxExpense, NA_real_)]
      }
    }
    # Derive Dividends if present under original name
    if (!"Dividends" %in% names(fund_wide)) fund_wide[, Dividends := NA_real_]

    # --- Q01: GPA (Gross Profit / Total Assets) ---
    if (all(c("GrossProfit", "TotalAssets") %in% names(fund_wide))) {
      q01 <- fund_wide[!is.na(GrossProfit) & !is.na(TotalAssets) & TotalAssets != 0,
                        .(Ticker, Factor_Name = "Q01_GPA",
                          Raw_Value = GrossProfit / TotalAssets)]
      results[["Q01"]] <- q01
    }

    # --- Q02: ROE (Net Income / Total Equity) ---
    if (all(c("NetIncome", "TotalEquity") %in% names(fund_wide))) {
      q02 <- fund_wide[!is.na(NetIncome) & !is.na(TotalEquity) & TotalEquity != 0,
                        .(Ticker, Factor_Name = "Q02_ROE",
                          Raw_Value = NetIncome / TotalEquity)]
      results[["Q02"]] <- q02
    }

    # --- Q03: ROA (Net Income / Total Assets) ---
    if (all(c("NetIncome", "TotalAssets") %in% names(fund_wide))) {
      q03 <- fund_wide[!is.na(NetIncome) & !is.na(TotalAssets) & TotalAssets != 0,
                        .(Ticker, Factor_Name = "Q03_ROA",
                          Raw_Value = NetIncome / TotalAssets)]
      results[["Q03"]] <- q03
    }

    # --- Q04: Piotroski F-Score (9-item) ---
    # 최근 2기간 필요 (delta 계산용)
    if ("Item" %in% names(FUND)) {
      q04 <- .compute_piotroski(FUND, sig_d)
      if (!is.null(q04) && nrow(q04) > 0) results[["Q04"]] <- q04
    } else {
      q04 <- .compute_piotroski_wide(FUND, sig_d)
      if (!is.null(q04) && nrow(q04) > 0) results[["Q04"]] <- q04
    }

    # --- Q05: Accrual = (NI - OCF) / TotalAssets (negate: lower=better) ---
    if (all(c("NetIncome", "OperatingCF", "TotalAssets") %in% names(fund_wide))) {
      q05 <- fund_wide[!is.na(NetIncome) & !is.na(OperatingCF) & !is.na(TotalAssets) & TotalAssets != 0,
                        .(Ticker, Factor_Name = "Q05_Accrual",
                          Raw_Value = -((NetIncome - OperatingCF) / TotalAssets))]
      results[["Q05"]] <- q05
    }

    # --- Q06: Asset Growth = delta(TA) / TA (negate: lower=better) ---
    if ("Item" %in% names(FUND)) {
      q06 <- .compute_asset_growth(FUND, sig_d)
      if (!is.null(q06) && nrow(q06) > 0) results[["Q06"]] <- q06
    } else {
      q06 <- .compute_asset_growth_wide(FUND, sig_d)
      if (!is.null(q06) && nrow(q06) > 0) results[["Q06"]] <- q06
    }

    # --- Q07: Earnings Stability = -sd(ROE over available periods) ---
    if ("Item" %in% names(FUND)) {
      q07 <- .compute_earnings_stability(FUND, sig_d)
      if (!is.null(q07) && nrow(q07) > 0) results[["Q07"]] <- q07
    } else {
      q07 <- .compute_earnings_stability_wide(FUND, sig_d)
      if (!is.null(q07) && nrow(q07) > 0) results[["Q07"]] <- q07
    }

    # --- Q08: Composite Quality = mean(z(Q01) + z(Q02) + z(-Q05) + z(-Q06)) ---
    # Q05/Q06 이미 부호 반전됨(negated), 다시 반전하지 않음
    # z-score는 cross-sectional (sig_date 시점)
    if (length(results) >= 4) {
      q08 <- .compute_composite_quality(results)
      if (!is.null(q08) && nrow(q08) > 0) results[["Q08"]] <- q08
    }

    # ==========================================================================
    # NEW QUALITY FACTORS (Q09~Q35) — 27 additional
    # ==========================================================================

    # --- Q09: CFOA (Cash Flow from Operations / Total Assets) ---
    if (all(c("OperatingCF", "TotalAssets") %in% names(fund_wide))) {
      q09 <- fund_wide[!is.na(OperatingCF) & !is.na(TotalAssets) & TotalAssets != 0,
                        .(Ticker, Factor_Name = "Q09_CFOA",
                          Raw_Value = OperatingCF / TotalAssets)]
      if (nrow(q09) > 0) results[["Q09"]] <- q09
    }

    # --- Q10: Gross Margin = GrossProfit / Revenue ---
    if (all(c("GrossProfit", "Revenue") %in% names(fund_wide))) {
      q10 <- fund_wide[!is.na(GrossProfit) & !is.na(Revenue) & Revenue != 0,
                        .(Ticker, Factor_Name = "Q10_Gross_Margin",
                          Raw_Value = GrossProfit / Revenue)]
      if (nrow(q10) > 0) results[["Q10"]] <- q10
    }

    # --- Q11: Net Profit Margin = NetIncome / Revenue ---
    if (all(c("NetIncome", "Revenue") %in% names(fund_wide))) {
      q11 <- fund_wide[!is.na(NetIncome) & !is.na(Revenue) & Revenue != 0,
                        .(Ticker, Factor_Name = "Q11_Net_Margin",
                          Raw_Value = NetIncome / Revenue)]
      if (nrow(q11) > 0) results[["Q11"]] <- q11
    }

    # --- Q12: Asset Turnover = Revenue / TotalAssets (DuPont) ---
    if (all(c("Revenue", "TotalAssets") %in% names(fund_wide))) {
      q12 <- fund_wide[!is.na(Revenue) & !is.na(TotalAssets) & TotalAssets != 0,
                        .(Ticker, Factor_Name = "Q12_Asset_Turnover",
                          Raw_Value = Revenue / TotalAssets)]
      if (nrow(q12) > 0) results[["Q12"]] <- q12
    }

    # --- Q13: Financial Leverage (DuPont) = TotalAssets / TotalEquity ---
    # Negate: lower leverage = higher quality
    if (all(c("TotalAssets", "TotalEquity") %in% names(fund_wide))) {
      q13 <- fund_wide[!is.na(TotalAssets) & !is.na(TotalEquity) & TotalEquity > 0,
                        .(Ticker, Factor_Name = "Q13_Fin_Leverage",
                          Raw_Value = -(TotalAssets / TotalEquity))]
      if (nrow(q13) > 0) results[["Q13"]] <- q13
    }

    # --- Q14: Current Ratio = CurrentAssets / CurrentLiabilities ---
    if (all(c("CurrentAssets", "CurrentLiabilities") %in% names(fund_wide))) {
      q14 <- fund_wide[!is.na(CurrentAssets) & !is.na(CurrentLiabilities) & CurrentLiabilities > 0,
                        .(Ticker, Factor_Name = "Q14_Current_Ratio",
                          Raw_Value = CurrentAssets / CurrentLiabilities)]
      if (nrow(q14) > 0) results[["Q14"]] <- q14
    }

    # --- Q15: Debt-to-Equity = -(TotalDebt / TotalEquity) ---
    if (all(c("TotalDebt", "TotalEquity") %in% names(fund_wide))) {
      q15 <- fund_wide[!is.na(TotalDebt) & !is.na(TotalEquity) & TotalEquity > 0,
                        .(Ticker, Factor_Name = "Q15_Debt_to_Equity",
                          Raw_Value = -(TotalDebt / TotalEquity))]
      if (nrow(q15) > 0) results[["Q15"]] <- q15
    }

    # --- Q16: Debt-to-Assets = -(TotalDebt / TotalAssets) ---
    if (all(c("TotalDebt", "TotalAssets") %in% names(fund_wide))) {
      q16 <- fund_wide[!is.na(TotalDebt) & !is.na(TotalAssets) & TotalAssets > 0,
                        .(Ticker, Factor_Name = "Q16_Debt_to_Assets",
                          Raw_Value = -(TotalDebt / TotalAssets))]
      if (nrow(q16) > 0) results[["Q16"]] <- q16
    }

    # --- Q17: ROIC = NOPAT / Invested Capital ---
    # NOPAT ≈ OperatingIncome * (1 - tax_rate), IC = TotalEquity + LongTermDebt - Cash
    # Simplified: use OperatingIncome / (TotalEquity + TotalDebt) if available
    if ("OperatingIncome" %in% names(fund_wide) &&
        all(c("TotalEquity", "TotalDebt") %in% names(fund_wide))) {
      q17 <- fund_wide[!is.na(OperatingIncome) & !is.na(TotalEquity) & !is.na(TotalDebt),
                        .(Ticker, ic = TotalEquity + TotalDebt, oi = OperatingIncome)]
      q17 <- q17[ic > 0]
      if (nrow(q17) > 0) {
        results[["Q17"]] <- q17[, .(Ticker, Factor_Name = "Q17_ROIC",
                                    Raw_Value = oi / ic)]
      }
    } else if (all(c("NetIncome", "TotalEquity", "TotalDebt") %in% names(fund_wide))) {
      # Fallback: use NetIncome as NOPAT proxy
      q17 <- fund_wide[!is.na(NetIncome) & !is.na(TotalEquity) & !is.na(TotalDebt),
                        .(Ticker, ic = TotalEquity + TotalDebt, ni = NetIncome)]
      q17 <- q17[ic > 0]
      if (nrow(q17) > 0) {
        results[["Q17"]] <- q17[, .(Ticker, Factor_Name = "Q17_ROIC",
                                    Raw_Value = ni / ic)]
      }
    }

    # --- Q18: Operating Leverage = (COGS + SGA) / TotalAssets ---
    # Novy-Marx (2011): higher oplex = higher exposure to systematic risk
    if ("COGS" %in% names(fund_wide) && "TotalAssets" %in% names(fund_wide)) {
      sga_col <- if ("SGA" %in% names(fund_wide)) "SGA" else NULL
      q18 <- fund_wide[!is.na(COGS) & !is.na(TotalAssets) & TotalAssets > 0]
      if (!is.null(sga_col)) {
        q18 <- q18[!is.na(get(sga_col))]
        q18[, oplev := (COGS + get(sga_col)) / TotalAssets]
      } else {
        q18[, oplev := COGS / TotalAssets]
      }
      q18 <- q18[!is.na(oplev)]
      if (nrow(q18) > 0) {
        results[["Q18"]] <- q18[, .(Ticker, Factor_Name = "Q18_Op_Leverage",
                                    Raw_Value = oplev)]  # higher oplex = risk premium (positive)
      }
    }

    # --- Q19: Cash-to-Assets = Cash / TotalAssets ---
    # Palazzo (2012): precautionary savings = safer
    if ("Cash" %in% names(fund_wide) && "TotalAssets" %in% names(fund_wide)) {
      q19 <- fund_wide[!is.na(Cash) & !is.na(TotalAssets) & TotalAssets > 0,
                        .(Ticker, Factor_Name = "Q19_Cash_to_Assets",
                          Raw_Value = Cash / TotalAssets)]
      if (nrow(q19) > 0) results[["Q19"]] <- q19
    }

    # --- Q20: Net Equity Issuance = -(change in SharesOutstanding / lagged SO) ---
    # Negative issuance = buyback = shareholder-friendly
    if ("Item" %in% names(FUND)) {
      q20 <- tryCatch({
        fund_tmp <- copy(FUND)
        if ("Factor_Date" %in% names(fund_tmp)) fund_tmp <- fund_tmp[Factor_Date <= sig_d]
        else if ("Date" %in% names(fund_tmp)) { fund_tmp <- fund_tmp[Date <= sig_d]; setnames(fund_tmp, "Date", "Factor_Date") }
        so <- fund_tmp[Item == "SharesOutstanding"]
        if (nrow(so) < 2) { NULL } else {
          so[, date_rank := frank(-as.numeric(Factor_Date)), by = Ticker]
          curr <- so[date_rank == 1, .(Ticker, SO_curr = Value)]
          prev <- so[date_rank == 2, .(Ticker, SO_prev = Value)]
          both <- merge(curr, prev, by = "Ticker")
          both <- both[SO_prev > 0]
          if (nrow(both) == 0) NULL
          else both[, .(Ticker, Factor_Name = "Q20_Net_Equity_Issuance",
                        Raw_Value = -((SO_curr - SO_prev) / SO_prev))]
        }
      }, error = function(e) NULL)
      if (!is.null(q20) && nrow(q20) > 0) results[["Q20"]] <- q20
    } else if ("SharesOutstanding" %in% names(fund_wide)) {
      # Wide format: need multiple periods
      q20 <- tryCatch({
        fund_tmp <- copy(FUND)
        if ("Factor_Date" %in% names(fund_tmp)) fund_tmp <- fund_tmp[Factor_Date <= sig_d]
        else if ("Date" %in% names(fund_tmp)) { fund_tmp <- fund_tmp[Date <= sig_d]; setnames(fund_tmp, "Date", "Factor_Date") }
        fund_tmp <- fund_tmp[!is.na(SharesOutstanding)]
        if (!"Factor_Date" %in% names(fund_tmp)) { NULL } else {
          fund_tmp[, date_rank := frank(-as.numeric(Factor_Date)), by = Ticker]
          curr <- fund_tmp[date_rank == 1, .(Ticker, SO_curr = SharesOutstanding)]
          prev <- fund_tmp[date_rank == 2, .(Ticker, SO_prev = SharesOutstanding)]
          both <- merge(curr, prev, by = "Ticker")
          both <- both[SO_prev > 0]
          if (nrow(both) == 0) NULL
          else both[, .(Ticker, Factor_Name = "Q20_Net_Equity_Issuance",
                        Raw_Value = -((SO_curr - SO_prev) / SO_prev))]
        }
      }, error = function(e) NULL)
      if (!is.null(q20) && nrow(q20) > 0) results[["Q20"]] <- q20
    }

    # --- Q21: Revenue Growth (YoY) ---
    if ("Item" %in% names(FUND)) {
      q21 <- .compute_yoy_growth(FUND, sig_d, "Revenue", "Q21_Revenue_Growth")
      if (!is.null(q21) && nrow(q21) > 0) results[["Q21"]] <- q21
    } else {
      q21 <- .compute_yoy_growth_wide(FUND, sig_d, "Revenue", "Q21_Revenue_Growth")
      if (!is.null(q21) && nrow(q21) > 0) results[["Q21"]] <- q21
    }

    # --- Q22: Earnings Growth (NI YoY) ---
    if ("Item" %in% names(FUND)) {
      q22 <- .compute_yoy_growth(FUND, sig_d, "NetIncome", "Q22_Earnings_Growth")
      if (!is.null(q22) && nrow(q22) > 0) results[["Q22"]] <- q22
    } else {
      q22 <- .compute_yoy_growth_wide(FUND, sig_d, "NetIncome", "Q22_Earnings_Growth")
      if (!is.null(q22) && nrow(q22) > 0) results[["Q22"]] <- q22
    }

    # --- Q23: Sustainable Growth Rate = ROE * (1 - payout) ---
    # Payout = Dividends / NetIncome. If dividends unavailable, use ROE * 0.5 as proxy
    if (all(c("NetIncome", "TotalEquity") %in% names(fund_wide))) {
      q23 <- fund_wide[!is.na(NetIncome) & !is.na(TotalEquity) & TotalEquity > 0]
      q23[, roe := NetIncome / TotalEquity]
      if ("Dividends" %in% names(fund_wide)) {
        q23[, payout := fifelse(!is.na(Dividends) & NetIncome > 0,
                                pmin(Dividends / NetIncome, 1), 0.5)]
      } else {
        q23[, payout := 0.5]  # assume 50% retention
      }
      q23[, sgr := roe * (1 - payout)]
      q23 <- q23[!is.na(sgr) & is.finite(sgr)]
      if (nrow(q23) > 0) {
        results[["Q23"]] <- q23[, .(Ticker, Factor_Name = "Q23_Sustainable_Growth",
                                    Raw_Value = sgr)]
      }
    }

    # --- Q24: Altman Z-Score ---
    # Z = 1.2*WC/TA + 1.4*RE/TA + 3.3*EBIT/TA + 0.6*MV_Equity/TL + 1.0*Sales/TA
    # Higher Z = lower bankruptcy risk = higher quality
    has_z_cols <- all(c("TotalAssets", "Revenue") %in% names(fund_wide))
    if (has_z_cols) {
      # Get market cap from RAWDATA (use latest trading date <= sig_date)
      rd_snap <- copy(RAWDATA)
      rd_snap[, Date := as.Date(Date)]
      avail_dates_q24 <- sort(unique(rd_snap[Date <= sig_d & !is.na(Close) & Close > 0]$Date), decreasing = TRUE)
      snap_date_q24 <- if (length(avail_dates_q24) > 0L) avail_dates_q24[1L] else sig_d
      snap <- rd_snap[Date == snap_date_q24 & !is.na(Close) & Close > 0]
      if ("Size" %in% names(snap)) snap[, MktCap := Close * Size]

      q24 <- copy(fund_wide)
      if (nrow(snap) > 0 && "MktCap" %in% names(snap)) {
        q24 <- merge(q24, snap[, .(Ticker, MktCap)], by = "Ticker", all.x = TRUE)
      } else {
        q24[, MktCap := NA_real_]
      }

      # Working Capital = CA - CL
      wc_ok <- all(c("CurrentAssets", "CurrentLiabilities") %in% names(q24))
      q24[, WC := if (wc_ok) fifelse(!is.na(CurrentAssets) & !is.na(CurrentLiabilities),
                                     CurrentAssets - CurrentLiabilities, NA_real_)
          else NA_real_]

      # Retained Earnings proxy: use TotalEquity if RE not available
      if ("RetainedEarnings" %in% names(q24)) {
        q24[, RE := RetainedEarnings]
      } else {
        q24[, RE := fifelse(!is.na(TotalEquity), TotalEquity * 0.7, NA_real_)]
      }

      # EBIT proxy
      if ("OperatingIncome" %in% names(q24)) {
        q24[, EBIT := OperatingIncome]
      } else if ("NetIncome" %in% names(q24)) {
        q24[, EBIT := NetIncome * 1.3]  # rough proxy
      } else {
        q24[, EBIT := NA_real_]
      }

      # Total Liabilities
      if ("TotalLiabilities" %in% names(q24)) {
        q24[, TL := TotalLiabilities]
      } else if (all(c("TotalAssets", "TotalEquity") %in% names(q24))) {
        q24[, TL := TotalAssets - TotalEquity]
      } else {
        q24[, TL := NA_real_]
      }

      q24 <- q24[TotalAssets > 0]
      q24[, z_score := 1.2 * fifelse(!is.na(WC), WC / TotalAssets, 0) +
            1.4 * fifelse(!is.na(RE), RE / TotalAssets, 0) +
            3.3 * fifelse(!is.na(EBIT), EBIT / TotalAssets, 0) +
            0.6 * fifelse(!is.na(MktCap) & !is.na(TL) & TL > 0, MktCap / TL, 0) +
            1.0 * fifelse(!is.na(Revenue), Revenue / TotalAssets, 0)]
      q24 <- q24[!is.na(z_score) & is.finite(z_score)]
      if (nrow(q24) > 0) {
        results[["Q24"]] <- q24[, .(Ticker, Factor_Name = "Q24_Altman_Z",
                                    Raw_Value = z_score)]
      }
    }

    # --- Q25: Ohlson O-Score (bankruptcy probability, negate) ---
    # O = -1.32 - 0.407*log(TA) + 6.03*(TL/TA) - 1.43*(WC/TA) + 0.076*(CL/CA)
    #     - 1.72*X - 2.37*(NI/TA) - 1.83*(FFO/TL) + 0.285*Y - 0.521*Z_ni
    # Simplified version with available data
    if (all(c("TotalAssets", "NetIncome") %in% names(fund_wide))) {
      q25 <- copy(fund_wide)
      q25 <- q25[TotalAssets > 0 & !is.na(NetIncome)]
      q25[, log_ta := log(TotalAssets)]

      if ("TotalLiabilities" %in% names(q25)) {
        q25[, tl_ta := TotalLiabilities / TotalAssets]
      } else if ("TotalEquity" %in% names(q25)) {
        q25[, tl_ta := 1 - TotalEquity / TotalAssets]
      } else {
        q25[, tl_ta := NA_real_]
      }

      wc_ok2 <- all(c("CurrentAssets", "CurrentLiabilities") %in% names(q25))
      q25[, wc_ta := if (wc_ok2) (CurrentAssets - CurrentLiabilities) / TotalAssets else NA_real_]

      q25[, ni_ta := NetIncome / TotalAssets]
      if ("OperatingCF" %in% names(q25)) {
        q25[, ffo_tl := fifelse(!is.na(tl_ta) & tl_ta > 0,
                                OperatingCF / (tl_ta * TotalAssets), NA_real_)]
      } else {
        q25[, ffo_tl := NA_real_]
      }

      # Simplified O-score
      q25[, o_score := -1.32 - 0.407 * log_ta +
            6.03 * fifelse(!is.na(tl_ta), tl_ta, 0.5) -
            1.43 * fifelse(!is.na(wc_ta), wc_ta, 0) -
            2.37 * ni_ta -
            1.83 * fifelse(!is.na(ffo_tl), ffo_tl, 0)]
      q25 <- q25[!is.na(o_score) & is.finite(o_score)]
      if (nrow(q25) > 0) {
        results[["Q25"]] <- q25[, .(Ticker, Factor_Name = "Q25_Ohlson_O",
                                    Raw_Value = -o_score)]  # lower O = less bankrupt = better
      }
    }

    # --- Q26: R&D Intensity = R&D / Revenue ---
    # DATA_NEEDED: R&D expense. Check if available.
    if ("RnD" %in% names(fund_wide) && "Revenue" %in% names(fund_wide)) {
      q26 <- fund_wide[!is.na(RnD) & !is.na(Revenue) & Revenue > 0,
                        .(Ticker, Factor_Name = "Q26_RnD_Intensity",
                          Raw_Value = RnD / Revenue)]
      if (nrow(q26) > 0) results[["Q26"]] <- q26
    } else if ("RnDExpense" %in% names(fund_wide) && "Revenue" %in% names(fund_wide)) {
      q26 <- fund_wide[!is.na(RnDExpense) & !is.na(Revenue) & Revenue > 0,
                        .(Ticker, Factor_Name = "Q26_RnD_Intensity",
                          Raw_Value = RnDExpense / Revenue)]
      if (nrow(q26) > 0) results[["Q26"]] <- q26
    }
    # else: # DATA_NEEDED: RnD or RnDExpense column in FUND

    # --- Q27: CapEx / Revenue (Investment Discipline) ---
    # Lower = more conservative = higher quality (CMA logic)
    # CapEx proxy: |InvestCF| if direct CapEx column absent
    if ("CapEx" %in% names(fund_wide) && "Revenue" %in% names(fund_wide)) {
      q27 <- fund_wide[!is.na(CapEx) & !is.na(Revenue) & Revenue > 0,
                        .(Ticker, Factor_Name = "Q27_CapEx_to_Rev",
                          Raw_Value = -(abs(CapEx) / Revenue))]
      if (nrow(q27) > 0) results[["Q27"]] <- q27
    } else if ("InvestCF" %in% names(fund_wide) && "Revenue" %in% names(fund_wide)) {
      # Proxy: |InvestCF| / Revenue (CapEx ≈ |InvestCF| for non-financial firms)
      q27 <- fund_wide[!is.na(InvestCF) & !is.na(Revenue) & Revenue > 0,
                        .(Ticker, Factor_Name = "Q27_CapEx_to_Rev",
                          Raw_Value = -(abs(InvestCF) / Revenue))]
      if (nrow(q27) > 0) results[["Q27"]] <- q27
    }

    # --- Q28: Cash Conversion = OperatingCF / NetIncome ---
    # Higher = earnings backed by cash = higher quality
    if (all(c("OperatingCF", "NetIncome") %in% names(fund_wide))) {
      q28 <- fund_wide[!is.na(OperatingCF) & !is.na(NetIncome) & abs(NetIncome) > 0,
                        .(Ticker, Factor_Name = "Q28_Cash_Conversion",
                          Raw_Value = OperatingCF / abs(NetIncome))]
      q28 <- q28[is.finite(Raw_Value) & abs(Raw_Value) < 10]  # cap extreme
      if (nrow(q28) > 0) results[["Q28"]] <- q28
    }

    # --- Q29: Inventory Turnover = Revenue / Inventory (or COGS / Inventory) ---
    # DATA_NEEDED: Inventory column
    if ("Inventory" %in% names(fund_wide) && "Revenue" %in% names(fund_wide)) {
      q29 <- fund_wide[!is.na(Inventory) & Inventory > 0 & !is.na(Revenue),
                        .(Ticker, Factor_Name = "Q29_Inventory_Turnover",
                          Raw_Value = Revenue / Inventory)]
      if (nrow(q29) > 0) results[["Q29"]] <- q29
    }
    # else: # DATA_NEEDED: Inventory column in FUND

    # --- Q30: Receivables Turnover = Revenue / AccountsReceivable ---
    # DATA_NEEDED: AccountsReceivable
    if ("AccountsReceivable" %in% names(fund_wide) && "Revenue" %in% names(fund_wide)) {
      q30 <- fund_wide[!is.na(AccountsReceivable) & AccountsReceivable > 0 & !is.na(Revenue),
                        .(Ticker, Factor_Name = "Q30_Receivables_Turnover",
                          Raw_Value = Revenue / AccountsReceivable)]
      if (nrow(q30) > 0) results[["Q30"]] <- q30
    }
    # else: # DATA_NEEDED: AccountsReceivable column in FUND

    # --- Q31: Working Capital / Total Assets ---
    if (all(c("CurrentAssets", "CurrentLiabilities", "TotalAssets") %in% names(fund_wide))) {
      q31 <- fund_wide[!is.na(CurrentAssets) & !is.na(CurrentLiabilities) &
                          !is.na(TotalAssets) & TotalAssets > 0,
                        .(Ticker, Factor_Name = "Q31_WC_to_Assets",
                          Raw_Value = (CurrentAssets - CurrentLiabilities) / TotalAssets)]
      if (nrow(q31) > 0) results[["Q31"]] <- q31
    }

    # --- Q32: Interest Coverage Ratio ---
    # DATA_NEEDED: InterestExpense
    if ("InterestExpense" %in% names(fund_wide)) {
      ebit_col <- if ("OperatingIncome" %in% names(fund_wide)) "OperatingIncome" else "NetIncome"
      if (ebit_col %in% names(fund_wide)) {
        q32 <- fund_wide[!is.na(get(ebit_col)) & !is.na(InterestExpense) & abs(InterestExpense) > 0,
                          .(Ticker, ebit = get(ebit_col), ie = InterestExpense)]
        q32[, Raw_Value := ebit / abs(ie)]
        q32 <- q32[is.finite(Raw_Value) & abs(Raw_Value) < 100]
        if (nrow(q32) > 0) {
          results[["Q32"]] <- q32[, .(Ticker, Factor_Name = "Q32_Interest_Coverage",
                                      Raw_Value)]
        }
      }
    }
    # else: # DATA_NEEDED: InterestExpense column in FUND

    # --- Q33: Earnings Persistence (autoregression coefficient of ROA) ---
    # Use multi-period ROA, estimate AR(1) coefficient
    if ("Item" %in% names(FUND)) {
      q33 <- .compute_earnings_persistence(FUND, sig_d)
      if (!is.null(q33) && nrow(q33) > 0) results[["Q33"]] <- q33
    } else {
      q33 <- .compute_earnings_persistence_wide(FUND, sig_d)
      if (!is.null(q33) && nrow(q33) > 0) results[["Q33"]] <- q33
    }

    # --- Q34: Gross Profit Growth (YoY) ---
    if ("Item" %in% names(FUND)) {
      q34 <- .compute_yoy_growth(FUND, sig_d, "GrossProfit", "Q34_GP_Growth")
      if (!is.null(q34) && nrow(q34) > 0) results[["Q34"]] <- q34
    } else {
      q34 <- .compute_yoy_growth_wide(FUND, sig_d, "GrossProfit", "Q34_GP_Growth")
      if (!is.null(q34) && nrow(q34) > 0) results[["Q34"]] <- q34
    }

    # --- Q35: Cash-Based Operating Profitability ---
    # Ball et al. (2016): (Revenue - COGS - SGA - Accruals) / TotalAssets
    # Accruals = NI - OCF
    if (all(c("Revenue", "NetIncome", "OperatingCF", "TotalAssets") %in% names(fund_wide))) {
      q35 <- fund_wide[!is.na(Revenue) & !is.na(NetIncome) & !is.na(OperatingCF) &
                          !is.na(TotalAssets) & TotalAssets > 0]
      q35[, accrual := NetIncome - OperatingCF]
      cogs_val <- if ("COGS" %in% names(q35)) q35$COGS else 0
      sga_val <- if ("SGA" %in% names(q35)) q35$SGA else 0
      q35[, cbop := (Revenue - fifelse(!is.na(..cogs_val), ..cogs_val, 0) -
                       fifelse(!is.na(..sga_val), ..sga_val, 0) - accrual) / TotalAssets]
      q35 <- q35[!is.na(cbop) & is.finite(cbop)]
      if (nrow(q35) > 0) {
        results[["Q35"]] <- q35[, .(Ticker, Factor_Name = "Q35_CashBased_OpProf",
                                    Raw_Value = cbop)]
      }
    }
  }

  # 결합
  if (length(results) == 0) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }
  out <- rbindlist(results, use.names = TRUE, fill = TRUE)
  out[, .(Ticker, Factor_Name, Raw_Value)]
}

# =============================================================================
# Internal helpers
# =============================================================================

#' Piotroski F-Score (long format FUND)
.compute_piotroski <- function(FUND, sig_d) {
  fund <- copy(FUND)
  if ("Factor_Date" %in% names(fund)) {
    fund <- fund[Factor_Date <= sig_d]
  } else if ("Date" %in% names(fund)) {
    fund <- fund[Date <= sig_d]
    setnames(fund, "Date", "Factor_Date")
  }

  # 종목×Item별 최근 2기간 필요
  items_needed <- c("NetIncome", "TotalAssets", "OperatingCF",
                    "LongTermDebt", "TotalDebt", "CurrentAssets",
                    "CurrentLiabilities", "SharesOutstanding",
                    "GrossProfit", "Revenue")
  fund_sub <- fund[Item %in% items_needed]
  if (nrow(fund_sub) == 0) return(NULL)

  # 종목별 최근 2 Factor_Date
  fund_sub[, date_rank := frank(-as.numeric(Factor_Date)), by = .(Ticker, Item)]
  curr <- fund_sub[date_rank == 1, .(Ticker, Item, Value_curr = Value)]
  prev <- fund_sub[date_rank == 2, .(Ticker, Item, Value_prev = Value)]

  both <- merge(curr, prev, by = c("Ticker", "Item"), all.x = TRUE)
  wide_c <- dcast(both, Ticker ~ Item, value.var = "Value_curr")
  wide_p <- dcast(both, Ticker ~ Item, value.var = "Value_prev")

  tickers_common <- intersect(wide_c$Ticker, wide_p$Ticker)
  if (length(tickers_common) == 0) return(NULL)

  # Vectorized: merge current + prev wide tables, then compute score per row
  both_w <- merge(
    wide_c[Ticker %in% tickers_common],
    wide_p[Ticker %in% tickers_common],
    by = "Ticker", suffixes = c("_c", "_p"), all = FALSE
  )
  if (nrow(both_w) == 0) return(NULL)

  # Helper: safe column accessor
  .gc <- function(dt, col) if (col %in% names(dt)) dt[[col]] else rep(NA_real_, nrow(dt))

  ni_c  <- .gc(both_w, "NetIncome_c");   ta_c <- .gc(both_w, "TotalAssets_c")
  ocf_c <- .gc(both_w, "OperatingCF_c")
  ni_p  <- .gc(both_w, "NetIncome_p");   ta_p <- .gc(both_w, "TotalAssets_p")

  roa_c <- ifelse(!is.na(ni_c) & !is.na(ta_c) & ta_c != 0, ni_c / ta_c, NA_real_)
  roa_p <- ifelse(!is.na(ni_p) & !is.na(ta_p) & ta_p != 0, ni_p / ta_p, NA_real_)

  debt_c <- .gc(both_w, "LongTermDebt_c"); debt_c[is.na(debt_c)] <- .gc(both_w, "TotalDebt_c")[is.na(debt_c)]
  debt_p <- .gc(both_w, "LongTermDebt_p"); debt_p[is.na(debt_p)] <- .gc(both_w, "TotalDebt_p")[is.na(debt_p)]
  lev_c  <- ifelse(!is.na(debt_c) & !is.na(ta_c) & ta_c != 0, debt_c / ta_c, NA_real_)
  lev_p  <- ifelse(!is.na(debt_p) & !is.na(ta_p) & ta_p != 0, debt_p / ta_p, NA_real_)

  ca_c   <- .gc(both_w, "CurrentAssets_c");      cl_c <- .gc(both_w, "CurrentLiabilities_c")
  ca_p   <- .gc(both_w, "CurrentAssets_p");      cl_p <- .gc(both_w, "CurrentLiabilities_p")
  cr_c   <- ifelse(!is.na(ca_c) & !is.na(cl_c) & cl_c != 0, ca_c / cl_c, NA_real_)
  cr_p   <- ifelse(!is.na(ca_p) & !is.na(cl_p) & cl_p != 0, ca_p / cl_p, NA_real_)

  sh_c   <- .gc(both_w, "SharesOutstanding_c"); sh_p <- .gc(both_w, "SharesOutstanding_p")
  gp_c   <- .gc(both_w, "GrossProfit_c");  rev_c <- .gc(both_w, "Revenue_c")
  gp_p   <- .gc(both_w, "GrossProfit_p");  rev_p <- .gc(both_w, "Revenue_p")
  gm_c   <- ifelse(!is.na(gp_c) & !is.na(rev_c) & rev_c != 0, gp_c / rev_c, NA_real_)
  gm_p   <- ifelse(!is.na(gp_p) & !is.na(rev_p) & rev_p != 0, gp_p / rev_p, NA_real_)
  at_c   <- ifelse(!is.na(rev_c) & !is.na(ta_c) & ta_c != 0, rev_c / ta_c, NA_real_)
  at_p   <- ifelse(!is.na(rev_p) & !is.na(ta_p) & ta_p != 0, rev_p / ta_p, NA_real_)

  score <- as.integer(!is.na(roa_c) & roa_c > 0) +
           as.integer(!is.na(roa_c) & !is.na(roa_p) & (roa_c - roa_p) > 0) +
           as.integer(!is.na(ocf_c) & ocf_c > 0) +
           as.integer(!is.na(ocf_c) & !is.na(ni_c) & !is.na(ta_c) & ta_c != 0 & ((ni_c - ocf_c) / ta_c) < 0) +
           as.integer(!is.na(lev_c) & !is.na(lev_p) & (lev_c - lev_p) < 0) +
           as.integer(!is.na(cr_c)  & !is.na(cr_p)  & (cr_c  - cr_p)  > 0) +
           as.integer(!is.na(sh_c)  & !is.na(sh_p)  & sh_c <= sh_p) +
           as.integer(!is.na(gm_c)  & !is.na(gm_p)  & (gm_c  - gm_p)  > 0) +
           as.integer(!is.na(at_c)  & !is.na(at_p)  & (at_c  - at_p)  > 0)

  data.table(Ticker = both_w$Ticker, Factor_Name = "Q04_Piotroski_F", Raw_Value = as.numeric(score))
}

#' Piotroski F-Score (wide format FUND — no Item column)
.compute_piotroski_wide <- function(FUND, sig_d) {
  fund <- copy(FUND)
  if ("Factor_Date" %in% names(fund)) {
    fund <- fund[Factor_Date <= sig_d]
  } else if ("Date" %in% names(fund)) {
    fund <- fund[Date <= sig_d]
    setnames(fund, "Date", "Factor_Date")
  }
  if (!"Factor_Date" %in% names(fund) || nrow(fund) == 0) return(NULL)

  # 종목별 최근 2기간
  fund[, date_rank := frank(-as.numeric(Factor_Date)), by = Ticker]
  curr <- fund[date_rank == 1]
  prev <- fund[date_rank == 2]

  tickers_common <- intersect(curr$Ticker, prev$Ticker)
  if (length(tickers_common) == 0) return(NULL)

  # Vectorized wide merge (replaces lapply per ticker).
  curr_w <- curr[Ticker %in% tickers_common]
  prev_w <- prev[Ticker %in% tickers_common]
  both_w <- merge(curr_w, prev_w, by = "Ticker", suffixes = c("_c", "_p"), all = FALSE)
  if (nrow(both_w) == 0) return(NULL)

  .gc2 <- function(col) if (col %in% names(both_w)) both_w[[col]] else rep(NA_real_, nrow(both_w))

  ni_c  <- .gc2("NetIncome_c");   ta_c <- .gc2("TotalAssets_c");  ocf_c <- .gc2("OperatingCF_c")
  ni_p  <- .gc2("NetIncome_p");   ta_p <- .gc2("TotalAssets_p")
  roa_c <- ifelse(!is.na(ni_c) & !is.na(ta_c) & ta_c != 0, ni_c / ta_c, NA_real_)
  roa_p <- ifelse(!is.na(ni_p) & !is.na(ta_p) & ta_p != 0, ni_p / ta_p, NA_real_)

  d_c   <- .gc2("LongTermDebt_c"); d_c[is.na(d_c)] <- .gc2("TotalDebt_c")[is.na(d_c)]
  d_p   <- .gc2("LongTermDebt_p"); d_p[is.na(d_p)] <- .gc2("TotalDebt_p")[is.na(d_p)]
  lev_c <- ifelse(!is.na(d_c) & !is.na(ta_c) & ta_c != 0, d_c / ta_c, NA_real_)
  lev_p <- ifelse(!is.na(d_p) & !is.na(ta_p) & ta_p != 0, d_p / ta_p, NA_real_)

  ca_c  <- .gc2("CurrentAssets_c"); cl_c <- .gc2("CurrentLiabilities_c")
  ca_p  <- .gc2("CurrentAssets_p"); cl_p <- .gc2("CurrentLiabilities_p")
  cr_c  <- ifelse(!is.na(ca_c) & !is.na(cl_c) & cl_c != 0, ca_c / cl_c, NA_real_)
  cr_p  <- ifelse(!is.na(ca_p) & !is.na(cl_p) & cl_p != 0, ca_p / cl_p, NA_real_)

  sh_c  <- .gc2("SharesOutstanding_c"); sh_p <- .gc2("SharesOutstanding_p")
  gp_c  <- .gc2("GrossProfit_c");  rev_c <- .gc2("Revenue_c")
  gp_p  <- .gc2("GrossProfit_p");  rev_p <- .gc2("Revenue_p")
  gm_c  <- ifelse(!is.na(gp_c) & !is.na(rev_c) & rev_c != 0, gp_c / rev_c, NA_real_)
  gm_p  <- ifelse(!is.na(gp_p) & !is.na(rev_p) & rev_p != 0, gp_p / rev_p, NA_real_)
  at_c  <- ifelse(!is.na(rev_c) & !is.na(ta_c) & ta_c != 0, rev_c / ta_c, NA_real_)
  at_p  <- ifelse(!is.na(rev_p) & !is.na(ta_p) & ta_p != 0, rev_p / ta_p, NA_real_)

  score <- as.integer(!is.na(roa_c) & roa_c > 0) +
           as.integer(!is.na(roa_c) & !is.na(roa_p) & (roa_c - roa_p) > 0) +
           as.integer(!is.na(ocf_c) & ocf_c > 0) +
           as.integer(!is.na(ocf_c) & !is.na(ni_c) & !is.na(ta_c) & ta_c != 0 & ((ni_c - ocf_c) / ta_c) < 0) +
           as.integer(!is.na(lev_c) & !is.na(lev_p) & (lev_c - lev_p) < 0) +
           as.integer(!is.na(cr_c)  & !is.na(cr_p)  & (cr_c  - cr_p) > 0) +
           as.integer(!is.na(sh_c)  & !is.na(sh_p)  & sh_c <= sh_p) +
           as.integer(!is.na(gm_c)  & !is.na(gm_p)  & (gm_c  - gm_p) > 0) +
           as.integer(!is.na(at_c)  & !is.na(at_p)  & (at_c  - at_p) > 0)

  data.table(Ticker = both_w$Ticker, Factor_Name = "Q04_Piotroski_F", Raw_Value = as.numeric(score))
}

#' Asset Growth (long format)
.compute_asset_growth <- function(FUND, sig_d) {
  fund <- copy(FUND)
  if ("Factor_Date" %in% names(fund)) {
    fund <- fund[Factor_Date <= sig_d]
  } else if ("Date" %in% names(fund)) {
    fund <- fund[Date <= sig_d]
    setnames(fund, "Date", "Factor_Date")
  }
  ta <- fund[Item == "TotalAssets"]
  if (nrow(ta) == 0) return(NULL)

  ta[, date_rank := frank(-as.numeric(Factor_Date)), by = Ticker]
  curr <- ta[date_rank == 1, .(Ticker, TA_curr = Value)]
  prev <- ta[date_rank == 2, .(Ticker, TA_prev = Value)]
  both <- merge(curr, prev, by = "Ticker")
  both <- both[TA_prev != 0]
  if (nrow(both) == 0) return(NULL)

  both[, .(Ticker, Factor_Name = "Q06_Asset_Growth",
           Raw_Value = -((TA_curr - TA_prev) / TA_prev))]
}

#' Asset Growth (wide format)
.compute_asset_growth_wide <- function(FUND, sig_d) {
  fund <- copy(FUND)
  if ("Factor_Date" %in% names(fund)) {
    fund <- fund[Factor_Date <= sig_d]
  } else if ("Date" %in% names(fund)) {
    fund <- fund[Date <= sig_d]
    setnames(fund, "Date", "Factor_Date")
  }
  if (!"TotalAssets" %in% names(fund) || !"Factor_Date" %in% names(fund)) return(NULL)

  fund <- fund[!is.na(TotalAssets)]
  fund[, date_rank := frank(-as.numeric(Factor_Date)), by = Ticker]
  curr <- fund[date_rank == 1, .(Ticker, TA_curr = TotalAssets)]
  prev <- fund[date_rank == 2, .(Ticker, TA_prev = TotalAssets)]
  both <- merge(curr, prev, by = "Ticker")
  both <- both[TA_prev != 0]
  if (nrow(both) == 0) return(NULL)

  both[, .(Ticker, Factor_Name = "Q06_Asset_Growth",
           Raw_Value = -((TA_curr - TA_prev) / TA_prev))]
}

#' Earnings Stability (long format) — -sd(ROE over available periods)
.compute_earnings_stability <- function(FUND, sig_d) {
  fund <- copy(FUND)
  if ("Factor_Date" %in% names(fund)) {
    fund <- fund[Factor_Date <= sig_d]
  } else if ("Date" %in% names(fund)) {
    fund <- fund[Date <= sig_d]
    setnames(fund, "Date", "Factor_Date")
  }

  ni <- fund[Item == "NetIncome", .(Ticker, Factor_Date, NI = Value)]
  te <- fund[Item == "TotalEquity", .(Ticker, Factor_Date, TE = Value)]
  both <- merge(ni, te, by = c("Ticker", "Factor_Date"))
  both <- both[TE != 0]
  both[, ROE := NI / TE]

  # 최소 3기간 필요
  stab <- both[, .(n = .N, sd_roe = sd(ROE, na.rm = TRUE)), by = Ticker]
  stab <- stab[n >= 3 & !is.na(sd_roe)]
  if (nrow(stab) == 0) return(NULL)

  stab[, .(Ticker, Factor_Name = "Q07_Earnings_Stability",
           Raw_Value = -sd_roe)]
}

#' Earnings Stability (wide format)
.compute_earnings_stability_wide <- function(FUND, sig_d) {
  fund <- copy(FUND)
  if ("Factor_Date" %in% names(fund)) {
    fund <- fund[Factor_Date <= sig_d]
  } else if ("Date" %in% names(fund)) {
    fund <- fund[Date <= sig_d]
    setnames(fund, "Date", "Factor_Date")
  }
  if (!all(c("NetIncome", "TotalEquity") %in% names(fund))) return(NULL)

  fund <- fund[!is.na(NetIncome) & !is.na(TotalEquity) & TotalEquity != 0]
  fund[, ROE := NetIncome / TotalEquity]

  stab <- fund[, .(n = .N, sd_roe = sd(ROE, na.rm = TRUE)), by = Ticker]
  stab <- stab[n >= 3 & !is.na(sd_roe)]
  if (nrow(stab) == 0) return(NULL)

  stab[, .(Ticker, Factor_Name = "Q07_Earnings_Stability",
           Raw_Value = -sd_roe)]
}

#' Composite Quality: mean of cross-sectional z-scores
.compute_composite_quality <- function(results) {
  # Need Q01, Q02, Q05 (already negated), Q06 (already negated)
  needed <- c("Q01", "Q02", "Q05", "Q06")
  available <- intersect(needed, names(results))
  if (length(available) < 2) return(NULL)

  # Combine available components
  parts <- rbindlist(results[available], use.names = TRUE)
  if (nrow(parts) == 0) return(NULL)

  # Cross-sectional z-score per factor
  parts[, z_val := {
    m <- mean(Raw_Value, na.rm = TRUE)
    s <- sd(Raw_Value, na.rm = TRUE)
    if (is.na(s) || s < 1e-8) NA_real_ else (Raw_Value - m) / s
  }, by = Factor_Name]

  # For Q01 and Q02: z as-is (higher = better)
  # For Q05 and Q06: already negated in Raw_Value, so z as-is
  composite <- parts[!is.na(z_val), .(z_mean = mean(z_val, na.rm = TRUE)), by = Ticker]
  composite <- composite[!is.na(z_mean)]
  if (nrow(composite) == 0) return(NULL)

  composite[, .(Ticker, Factor_Name = "Q08_Composite_Quality", Raw_Value = z_mean)]
}

# =============================================================================
# NEW Internal helpers for Q09~Q35
# =============================================================================

#' YoY Growth (long format FUND)
.compute_yoy_growth <- function(FUND, sig_d, item_name, factor_name) {
  fund <- copy(FUND)
  if ("Factor_Date" %in% names(fund)) {
    fund <- fund[Factor_Date <= sig_d]
  } else if ("Date" %in% names(fund)) {
    fund <- fund[Date <= sig_d]
    setnames(fund, "Date", "Factor_Date")
  }
  dt <- fund[Item == item_name]
  if (nrow(dt) == 0) return(NULL)

  dt[, date_rank := frank(-as.numeric(Factor_Date)), by = Ticker]
  curr <- dt[date_rank == 1, .(Ticker, V_curr = Value)]
  prev <- dt[date_rank == 2, .(Ticker, V_prev = Value)]
  both <- merge(curr, prev, by = "Ticker")
  both <- both[abs(V_prev) > 0]
  if (nrow(both) == 0) return(NULL)

  both[, .(Ticker, Factor_Name = factor_name,
           Raw_Value = (V_curr - V_prev) / abs(V_prev))]
}

#' YoY Growth (wide format FUND)
.compute_yoy_growth_wide <- function(FUND, sig_d, col_name, factor_name) {
  fund <- copy(FUND)
  if ("Factor_Date" %in% names(fund)) {
    fund <- fund[Factor_Date <= sig_d]
  } else if ("Date" %in% names(fund)) {
    fund <- fund[Date <= sig_d]
    setnames(fund, "Date", "Factor_Date")
  }
  if (!col_name %in% names(fund) || !"Factor_Date" %in% names(fund)) return(NULL)

  fund <- fund[!is.na(get(col_name))]
  fund[, date_rank := frank(-as.numeric(Factor_Date)), by = Ticker]
  curr <- fund[date_rank == 1, .(Ticker, V_curr = get(col_name))]
  prev <- fund[date_rank == 2, .(Ticker, V_prev = get(col_name))]
  both <- merge(curr, prev, by = "Ticker")
  both <- both[abs(V_prev) > 0]
  if (nrow(both) == 0) return(NULL)

  both[, .(Ticker, Factor_Name = factor_name,
           Raw_Value = (V_curr - V_prev) / abs(V_prev))]
}

#' Earnings Persistence AR(1) coefficient (long format)
.compute_earnings_persistence <- function(FUND, sig_d) {
  fund <- copy(FUND)
  if ("Factor_Date" %in% names(fund)) {
    fund <- fund[Factor_Date <= sig_d]
  } else if ("Date" %in% names(fund)) {
    fund <- fund[Date <= sig_d]
    setnames(fund, "Date", "Factor_Date")
  }
  ni <- fund[Item == "NetIncome", .(Ticker, Factor_Date, NI = Value)]
  ta <- fund[Item == "TotalAssets", .(Ticker, Factor_Date, TA = Value)]
  both <- merge(ni, ta, by = c("Ticker", "Factor_Date"))
  both <- both[TA > 0]
  both[, ROA := NI / TA]
  setorder(both, Ticker, Factor_Date)

  # AR(1) coefficient per ticker (need >= 4 observations)
  ar_coefs <- both[, {
    if (.N >= 4) {
      roa_lag <- ROA[-.N]
      roa_cur <- ROA[-1]
      if (length(roa_lag) >= 3 && var(roa_lag, na.rm = TRUE) > 1e-12) {
        fit <- tryCatch(lm.fit(cbind(1, roa_lag), roa_cur), error = function(e) NULL)
        if (!is.null(fit)) list(ar1 = fit$coefficients[2]) else list(ar1 = NA_real_)
      } else list(ar1 = NA_real_)
    } else list(ar1 = NA_real_)
  }, by = Ticker]
  ar_coefs <- ar_coefs[!is.na(ar1)]
  if (nrow(ar_coefs) == 0) return(NULL)
  ar_coefs[, .(Ticker, Factor_Name = "Q33_Earnings_Persistence", Raw_Value = ar1)]
}

#' Earnings Persistence AR(1) coefficient (wide format)
.compute_earnings_persistence_wide <- function(FUND, sig_d) {
  fund <- copy(FUND)
  if ("Factor_Date" %in% names(fund)) {
    fund <- fund[Factor_Date <= sig_d]
  } else if ("Date" %in% names(fund)) {
    fund <- fund[Date <= sig_d]
    setnames(fund, "Date", "Factor_Date")
  }
  if (!all(c("NetIncome", "TotalAssets") %in% names(fund))) return(NULL)
  if (!"Factor_Date" %in% names(fund)) return(NULL)

  fund <- fund[!is.na(NetIncome) & !is.na(TotalAssets) & TotalAssets > 0]
  fund[, ROA := NetIncome / TotalAssets]
  setorder(fund, Ticker, Factor_Date)

  ar_coefs <- fund[, {
    if (.N >= 4) {
      roa_lag <- ROA[-.N]
      roa_cur <- ROA[-1]
      if (length(roa_lag) >= 3 && var(roa_lag, na.rm = TRUE) > 1e-12) {
        fit <- tryCatch(lm.fit(cbind(1, roa_lag), roa_cur), error = function(e) NULL)
        if (!is.null(fit)) list(ar1 = fit$coefficients[2]) else list(ar1 = NA_real_)
      } else list(ar1 = NA_real_)
    } else list(ar1 = NA_real_)
  }, by = Ticker]
  ar_coefs <- ar_coefs[!is.na(ar1)]
  if (nrow(ar_coefs) == 0) return(NULL)
  ar_coefs[, .(Ticker, Factor_Name = "Q33_Earnings_Persistence", Raw_Value = ar1)]
}

cat("[factor_db] compute_quality.R loaded (Q01~Q35: 8 original + 27 new)\n")
