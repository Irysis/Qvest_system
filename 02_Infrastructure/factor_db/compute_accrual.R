#==============================================================================
# compute_accrual.R -- Accrual Factor Module (AC01~AC25)
#
# compute_accrual(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL)
#   RAWDATA:    data.table(Date, Ticker, Close, Ret, Vol, Size, Sector, BM_Ret)
#   sig_date:   signal date (Date class)
#   FUND:       fundamentals long format (Ticker, Item, Value, Factor_Date)
#   CONSENSUS:  not used (signature kept for consistency)
#
# Returns: data.table(Ticker, Factor_Name, Raw_Value)
#
# PIT: Factor_Date <= sig_date only. Expanding window. No future data.
#      C1-C11 compliant.
#
# References:
#   Sloan (1996), Richardson et al. (2005), Hirshleifer et al. (2004),
#   Thomas & Zhang (2002), Xie (2001), Allen Larson Sloan (2009),
#   Palmon et al. (2008), Shi & Zhang, Larson Sloan Giedt (2018)
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

compute_accrual <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {

  sig_d <- as.Date(sig_date)
  results <- list()

  if (is.null(FUND) || nrow(FUND) == 0L) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  # ---- Fundamental data prep (PIT: Factor_Date <= sig_date) ----
  # FUND is pre-filtered (FUND_pit) by builder — minimal copy cost
  fund <- copy(FUND)
  if ("Factor_Date" %in% names(fund) && !isTRUE(attr(FUND, "pit_filtered"))) {
    fund <- fund[Factor_Date <= sig_d]
  } else if ("Date" %in% names(fund) && !isTRUE(attr(FUND, "pit_filtered"))) {
    fund <- fund[Date <= sig_d]
    setnames(fund, "Date", "Factor_Date")
  } else if (!"Factor_Date" %in% names(fund) && "Date" %in% names(fund)) {
    setnames(fund, "Date", "Factor_Date")
  }
  if (nrow(fund) == 0L) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  # ---- Detect long vs wide format ----
  is_long <- "Item" %in% names(fund)

  # ---- PRE-COMPUTE date_rank ONCE (avoids repeated frank() per factor call) ----
  # This is the main optimization: instead of calling frank() for each of 25 factors,
  # we compute date_rank once for the entire fund and cache curr/prev wide tables.
  if (is_long) {
    # Rank once per (Ticker, Item) — single pass
    setorder(fund, Ticker, Item, Factor_Date)
    fund[, date_rank := frank(-as.numeric(Factor_Date)), by = .(Ticker, Item)]
    .fund_curr_long <- fund[date_rank == 1, .(Ticker, Item, V_curr = Value)]
    .fund_prev_long <- fund[date_rank == 2, .(Ticker, Item, V_prev = Value)]
    # Wide tables (all items at once) — dcast once
    .fund_curr_wide_all <- dcast(.fund_curr_long, Ticker ~ Item, value.var = "V_curr")
    .fund_prev_wide_all <- dcast(.fund_prev_long, Ticker ~ Item, value.var = "V_prev")
  } else {
    setorder(fund, Ticker, Factor_Date)
    fund[, date_rank := frank(-as.numeric(Factor_Date)), by = Ticker]
    .fund_curr_wide_all <- fund[date_rank == 1]
    .fund_prev_wide_all <- fund[date_rank == 2]
  }

  # ---- Helper: get two most recent periods — now uses pre-computed tables ----
  .get_two_periods <- function(fund_dt, items_needed) {
    if (is_long) {
      # Use pre-computed wide tables; select only items present
      cols_c <- intersect(c("Ticker", items_needed), names(.fund_curr_wide_all))
      cols_p <- intersect(c("Ticker", items_needed), names(.fund_prev_wide_all))
      w_curr <- .fund_curr_wide_all[, ..cols_c]
      w_prev <- .fund_prev_wide_all[, ..cols_p]
      return(list(curr = w_curr, prev = w_prev))
    } else {
      if (!all(items_needed %in% names(fund_dt))) return(NULL)
      return(list(curr = .fund_curr_wide_all, prev = .fund_prev_wide_all))
    }
  }

  # ---- Helper: get latest PIT fundamental (wide) — uses pre-computed curr ----
  .get_latest_wide <- function(fund_dt, items_needed) {
    if (is_long) {
      cols <- intersect(c("Ticker", items_needed), names(.fund_curr_wide_all))
      .fund_curr_wide_all[, ..cols]
    } else {
      .fund_curr_wide_all
    }
  }

  # ---- Helper: safe column access ----
  .sc <- function(dt, col) {
    if (col %in% names(dt)) dt[[col]] else rep(NA_real_, nrow(dt))
  }

  # ---- Helper: safe divide ----
  .sdiv <- function(num, den) {
    fifelse(!is.na(num) & !is.na(den) & abs(den) > 1e-8, num / den, NA_real_)
  }

  # ---- Price snapshot for AC25 (size interaction) ----
  snap <- NULL
  if ("Size" %in% names(RAWDATA)) {
    snap <- RAWDATA[Date == sig_d & !is.na(Close) & Close > 0, .(Ticker, MarketCap = Close * Size)]
    snap <- snap[MarketCap > 0]
  }

  # ==========================================================================
  # AC01: Total Accruals (Sloan 1996, CF Statement method)
  # TA = (NI - OCF) / TotalAssets  -- negate: low accruals = good
  # ==========================================================================
  items_ac01 <- c("NetIncome", "OperatingCF", "TotalAssets")
  fw <- .get_latest_wide(fund, items_ac01)
  if (!is.null(fw)) {
    ni  <- .sc(fw, "NetIncome")
    ocf <- .sc(fw, "OperatingCF")
    ta  <- .sc(fw, "TotalAssets")
    fw[, AC01 := .sdiv(-(ni - ocf), ta)]
    results[["AC01"]] <- fw[!is.na(AC01), .(Ticker, Factor_Name = "AC01_Total_Accruals_CF", Raw_Value = AC01)]
  }

  # ==========================================================================
  # AC02: Total Accruals (Sloan 1996, Balance Sheet method)
  # TA_BS = (dCA - dCash) - (dCL - dSTD - dTP) - DEP, scaled by avg TA
  # ==========================================================================
  items_ac02 <- c("CurrentAssets", "CashAndEquiv", "CurrentLiabilities",
                   "ShortTermBorr", "TaxPayable", "DepAmort", "TotalAssets")
  tp <- .get_two_periods(fund, items_ac02)
  if (!is.null(tp)) {
    m <- merge(tp$curr, tp$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
    if (nrow(m) > 0L) {
      dCA   <- .sc(m, "CurrentAssets")   - .sc(m, "CurrentAssets_p")
      dCash <- .sc(m, "CashAndEquiv")    - .sc(m, "CashAndEquiv_p")
      dCL   <- .sc(m, "CurrentLiabilities") - .sc(m, "CurrentLiabilities_p")
      dSTD  <- .sc(m, "ShortTermBorr")   - .sc(m, "ShortTermBorr_p")
      dTP   <- .sc(m, "TaxPayable")      - .sc(m, "TaxPayable_p")
      dep   <- .sc(m, "DepAmort")
      ta_c  <- .sc(m, "TotalAssets")
      ta_p  <- .sc(m, "TotalAssets_p")
      avg_ta <- (ta_c + ta_p) / 2
      # Replace NA deltas with 0 for optional items (STD, TP)
      dSTD[is.na(dSTD)] <- 0
      dTP[is.na(dTP)]   <- 0
      dep[is.na(dep)]   <- 0
      bs_acc <- (dCA - dCash) - (dCL - dSTD - dTP) - dep
      m[, AC02 := .sdiv(-bs_acc, avg_ta)]
      results[["AC02"]] <- m[!is.na(AC02), .(Ticker, Factor_Name = "AC02_Total_Accruals_BS", Raw_Value = AC02)]
    }
  }

  # ==========================================================================
  # AC03: Working Capital Accruals (Richardson et al. 2005)
  # WCACC = d(CA - Cash) - d(CL - STD - TP), scaled by avg TA
  # ==========================================================================
  if (!is.null(tp) && nrow(merge(tp$curr, tp$prev, by = "Ticker", all = FALSE)) > 0L) {
    m <- merge(tp$curr, tp$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
    dCA   <- .sc(m, "CurrentAssets")   - .sc(m, "CurrentAssets_p")
    dCash <- .sc(m, "CashAndEquiv")    - .sc(m, "CashAndEquiv_p")
    dCL   <- .sc(m, "CurrentLiabilities") - .sc(m, "CurrentLiabilities_p")
    dSTD  <- .sc(m, "ShortTermBorr")   - .sc(m, "ShortTermBorr_p")
    dTP   <- .sc(m, "TaxPayable")      - .sc(m, "TaxPayable_p")
    dSTD[is.na(dSTD)] <- 0
    dTP[is.na(dTP)]   <- 0
    ta_c  <- .sc(m, "TotalAssets")
    ta_p  <- .sc(m, "TotalAssets_p")
    avg_ta <- (ta_c + ta_p) / 2
    wc_acc <- (dCA - dCash) - (dCL - dSTD - dTP)
    m[, AC03 := .sdiv(-wc_acc, avg_ta)]
    results[["AC03"]] <- m[!is.na(AC03), .(Ticker, Factor_Name = "AC03_WC_Accruals", Raw_Value = AC03)]
  }

  # ==========================================================================
  # AC04: Noncurrent Operating Accruals (Richardson et al. 2005)
  # NCO_ACC = d(TA - CA - Investments) - d(TL - CL - LTD), scaled by avg TA
  # ==========================================================================
  items_ac04 <- c("TotalAssets", "CurrentAssets", "Investments",
                   "TotalLiabilities", "CurrentLiabilities", "LongTermBorr")
  tp4 <- .get_two_periods(fund, items_ac04)
  if (!is.null(tp4)) {
    m4 <- merge(tp4$curr, tp4$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
    if (nrow(m4) > 0L) {
      inv_c  <- .sc(m4, "Investments"); inv_p  <- .sc(m4, "Investments_p")
      inv_c[is.na(inv_c)] <- 0; inv_p[is.na(inv_p)] <- 0
      ltd_c  <- .sc(m4, "LongTermBorr"); ltd_p  <- .sc(m4, "LongTermBorr_p")
      ltd_c[is.na(ltd_c)] <- 0; ltd_p[is.na(ltd_p)] <- 0
      nco_a_c <- (.sc(m4, "TotalAssets") - .sc(m4, "CurrentAssets") - inv_c)
      nco_a_p <- (.sc(m4, "TotalAssets_p") - .sc(m4, "CurrentAssets_p") - inv_p)
      nco_l_c <- (.sc(m4, "TotalLiabilities") - .sc(m4, "CurrentLiabilities") - ltd_c)
      nco_l_p <- (.sc(m4, "TotalLiabilities_p") - .sc(m4, "CurrentLiabilities_p") - ltd_p)
      nco_acc <- (nco_a_c - nco_a_p) - (nco_l_c - nco_l_p)
      avg_ta <- (.sc(m4, "TotalAssets") + .sc(m4, "TotalAssets_p")) / 2
      m4[, AC04 := .sdiv(-nco_acc, avg_ta)]
      results[["AC04"]] <- m4[!is.na(AC04), .(Ticker, Factor_Name = "AC04_NCO_Accruals", Raw_Value = AC04)]
    }
  }

  # ==========================================================================
  # AC05: Net Operating Assets (Hirshleifer et al. 2004)
  # NOA = (OA - OL) / TA. OA = TA - Cash. OL = TA - STD - LTD - MI - PE - CE
  # Negate: low NOA = good
  # ==========================================================================
  items_ac05 <- c("TotalAssets", "CashAndEquiv", "ShortTermBorr", "LongTermBorr",
                   "MinorityInterest", "PreferredStock", "TotalEquity")
  fw5 <- .get_latest_wide(fund, items_ac05)
  if (!is.null(fw5)) {
    ta  <- .sc(fw5, "TotalAssets")
    cas <- .sc(fw5, "CashAndEquiv"); cas[is.na(cas)] <- 0
    std <- .sc(fw5, "ShortTermBorr"); std[is.na(std)] <- 0
    ltd <- .sc(fw5, "LongTermBorr"); ltd[is.na(ltd)] <- 0
    mi  <- .sc(fw5, "MinorityInterest"); mi[is.na(mi)] <- 0
    ps  <- .sc(fw5, "PreferredStock"); ps[is.na(ps)] <- 0
    ce  <- .sc(fw5, "TotalEquity"); ce[is.na(ce)] <- 0
    oa  <- ta - cas
    ol  <- ta - std - ltd - mi - ps - ce
    fw5[, AC05 := .sdiv(-(oa - ol), ta)]
    results[["AC05"]] <- fw5[!is.na(AC05), .(Ticker, Factor_Name = "AC05_NOA", Raw_Value = AC05)]
  }

  # ==========================================================================
  # AC06: Comprehensive Accruals (COMPACC, Larson Sloan Giedt 2018)
  # COMPACC = d(CommonEquity) - d(Cash), scaled by avg TA
  # ==========================================================================
  items_ac06 <- c("TotalEquity", "CashAndEquiv", "TotalAssets")
  tp6 <- .get_two_periods(fund, items_ac06)
  if (!is.null(tp6)) {
    m6 <- merge(tp6$curr, tp6$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
    if (nrow(m6) > 0L) {
      d_eq   <- .sc(m6, "TotalEquity")   - .sc(m6, "TotalEquity_p")
      d_cash <- .sc(m6, "CashAndEquiv")   - .sc(m6, "CashAndEquiv_p")
      avg_ta <- (.sc(m6, "TotalAssets") + .sc(m6, "TotalAssets_p")) / 2
      m6[, AC06 := .sdiv(-(d_eq - d_cash), avg_ta)]
      results[["AC06"]] <- m6[!is.na(AC06), .(Ticker, Factor_Name = "AC06_Comprehensive_Accruals", Raw_Value = AC06)]
    }
  }

  # ==========================================================================
  # AC07: Operating Accruals (OPACC subset of COMPACC)
  # OPACC = d(NonCashOA) - d(OL), scaled by avg TA
  # NonCashOA = TA - Cash - Investments
  # OL = TL - Debt
  # ==========================================================================
  items_ac07 <- c("TotalAssets", "CashAndEquiv", "Investments",
                   "TotalLiabilities", "ShortTermBorr", "LongTermBorr")
  tp7 <- .get_two_periods(fund, items_ac07)
  if (!is.null(tp7)) {
    m7 <- merge(tp7$curr, tp7$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
    if (nrow(m7) > 0L) {
      .zna <- function(x) { x[is.na(x)] <- 0; x }
      ncoa_c <- .sc(m7, "TotalAssets") - .zna(.sc(m7, "CashAndEquiv")) - .zna(.sc(m7, "Investments"))
      ncoa_p <- .sc(m7, "TotalAssets_p") - .zna(.sc(m7, "CashAndEquiv_p")) - .zna(.sc(m7, "Investments_p"))
      ol_c   <- .sc(m7, "TotalLiabilities") - .zna(.sc(m7, "ShortTermBorr")) - .zna(.sc(m7, "LongTermBorr"))
      ol_p   <- .sc(m7, "TotalLiabilities_p") - .zna(.sc(m7, "ShortTermBorr_p")) - .zna(.sc(m7, "LongTermBorr_p"))
      opacc  <- (ncoa_c - ncoa_p) - (ol_c - ol_p)
      avg_ta <- (.sc(m7, "TotalAssets") + .sc(m7, "TotalAssets_p")) / 2
      m7[, AC07 := .sdiv(-opacc, avg_ta)]
      results[["AC07"]] <- m7[!is.na(AC07), .(Ticker, Factor_Name = "AC07_Operating_Accruals", Raw_Value = AC07)]
    }
  }

  # ==========================================================================
  # AC08: Financial Accruals (FINACC = COMPACC - OPACC)
  # ==========================================================================
  if ("AC06" %in% names(results) && "AC07" %in% names(results)) {
    comp <- merge(results[["AC06"]][, .(Ticker, compacc = Raw_Value)],
                  results[["AC07"]][, .(Ticker, opacc = Raw_Value)],
                  by = "Ticker", all = FALSE)
    if (nrow(comp) > 0L) {
      comp[, AC08 := compacc - opacc]
      results[["AC08"]] <- comp[!is.na(AC08), .(Ticker, Factor_Name = "AC08_Financial_Accruals", Raw_Value = AC08)]
    }
  }

  # ==========================================================================
  # AC09: Net New Investments (Richardson et al. 2005 broad measure)
  # NNI = d(TA - Cash) - d(TL - Debt), scaled by avg TA
  # ==========================================================================
  items_ac09 <- c("TotalAssets", "CashAndEquiv", "TotalLiabilities",
                   "ShortTermBorr", "LongTermBorr")
  tp9 <- .get_two_periods(fund, items_ac09)
  if (!is.null(tp9)) {
    m9 <- merge(tp9$curr, tp9$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
    if (nrow(m9) > 0L) {
      .zna <- function(x) { x[is.na(x)] <- 0; x }
      nca_c <- .sc(m9, "TotalAssets") - .zna(.sc(m9, "CashAndEquiv"))
      nca_p <- .sc(m9, "TotalAssets_p") - .zna(.sc(m9, "CashAndEquiv_p"))
      nl_c  <- .sc(m9, "TotalLiabilities") - .zna(.sc(m9, "ShortTermBorr")) - .zna(.sc(m9, "LongTermBorr"))
      nl_p  <- .sc(m9, "TotalLiabilities_p") - .zna(.sc(m9, "ShortTermBorr_p")) - .zna(.sc(m9, "LongTermBorr_p"))
      nni   <- (nca_c - nca_p) - (nl_c - nl_p)
      avg_ta <- (.sc(m9, "TotalAssets") + .sc(m9, "TotalAssets_p")) / 2
      m9[, AC09 := .sdiv(-nni, avg_ta)]
      results[["AC09"]] <- m9[!is.na(AC09), .(Ticker, Factor_Name = "AC09_NNI", Raw_Value = AC09)]
    }
  }

  # ==========================================================================
  # AC10: Percent Accruals (% of earnings from accruals vs cash)
  # Pct_Acc = (NI - OCF) / |NI|. Negate: lower = better
  # ==========================================================================
  items_ac10 <- c("NetIncome", "OperatingCF")
  fw10 <- .get_latest_wide(fund, items_ac10)
  if (!is.null(fw10)) {
    ni  <- .sc(fw10, "NetIncome")
    ocf <- .sc(fw10, "OperatingCF")
    fw10[, AC10 := .sdiv(-(ni - ocf), pmax(abs(ni), 1e-8))]
    results[["AC10"]] <- fw10[!is.na(AC10) & is.finite(AC10),
                               .(Ticker, Factor_Name = "AC10_Pct_Accruals", Raw_Value = AC10)]
  }

  # ==========================================================================
  # AC11: Accruals to Assets (simple version)
  # ACC/TA = (NI - OCF) / TA, negated. (Broader cross-section than BS method)
  # ==========================================================================
  # Already computed as AC01, but this uses Value (not TTM_Value) if available
  # Keep AC01 as primary. AC11 = duplicate for completeness.
  if ("AC01" %in% names(results)) {
    ac11 <- copy(results[["AC01"]])
    ac11[, Factor_Name := "AC11_Accruals_to_Assets"]
    results[["AC11"]] <- ac11
  }

  # ==========================================================================
  # AC12: Inventory Accruals (Thomas & Zhang 2002)
  # dInventory / avg TA. Negated.
  # ==========================================================================
  items_ac12 <- c("Inventories", "TotalAssets")
  tp12 <- .get_two_periods(fund, items_ac12)
  if (!is.null(tp12)) {
    m12 <- merge(tp12$curr, tp12$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
    if (nrow(m12) > 0L) {
      d_inv  <- .sc(m12, "Inventories") - .sc(m12, "Inventories_p")
      avg_ta <- (.sc(m12, "TotalAssets") + .sc(m12, "TotalAssets_p")) / 2
      m12[, AC12 := .sdiv(-d_inv, avg_ta)]
      results[["AC12"]] <- m12[!is.na(AC12), .(Ticker, Factor_Name = "AC12_Inventory_Accruals", Raw_Value = AC12)]
    }
  }

  # ==========================================================================
  # AC13: Abnormal Accruals (Modified Jones Model, Xie 2001)
  # Cross-sectional regression of TA on dRev and PPE.
  # Residual = abnormal (discretionary) accruals. Negate.
  # ==========================================================================
  items_ac13 <- c("NetIncome", "OperatingCF", "TotalAssets", "Revenue", "PPE")
  fw13 <- .get_latest_wide(fund, items_ac13)
  tp13 <- .get_two_periods(fund, c("Revenue", "TotalAssets"))
  if (!is.null(fw13) && !is.null(tp13)) {
    m13rev <- merge(tp13$curr, tp13$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
    m13rev[, dRev := .sc(m13rev, "Revenue") - .sc(m13rev, "Revenue_p")]
    m13rev[, lag_TA := .sc(m13rev, "TotalAssets_p")]
    m13 <- merge(fw13, m13rev[, .(Ticker, dRev, lag_TA)], by = "Ticker", all.x = TRUE)
    ni  <- .sc(m13, "NetIncome")
    ocf <- .sc(m13, "OperatingCF")
    ta  <- .sc(m13, "TotalAssets")
    ppe <- .sc(m13, "PPE")
    m13[, total_acc := .sdiv(ni - ocf, lag_TA)]
    m13[, inv_ta := .sdiv(1, lag_TA)]
    m13[, dRev_sc := .sdiv(dRev, lag_TA)]
    m13[, PPE_sc := .sdiv(ppe, lag_TA)]
    # Cross-sectional regression: total_acc = a0*inv_ta + a1*dRev_sc + a2*PPE_sc + eps
    valid <- m13[!is.na(total_acc) & !is.na(inv_ta) & !is.na(dRev_sc) & !is.na(PPE_sc)]
    if (nrow(valid) >= 30L) {
      X <- cbind(valid$inv_ta, valid$dRev_sc, valid$PPE_sc)
      y <- valid$total_acc
      fit <- tryCatch(lm.fit(X, y), error = function(e) NULL)
      if (!is.null(fit)) {
        valid[, abnormal_acc := fit$residuals]
        results[["AC13"]] <- valid[!is.na(abnormal_acc),
                                    .(Ticker, Factor_Name = "AC13_Abnormal_Accruals", Raw_Value = -abnormal_acc)]
      }
    }
  }

  # ==========================================================================
  # AC14: Discretionary Accruals (Jones Model residual proxy)
  # Same as AC13 but with simplified approach: abs(abnormal_acc) as magnitude
  # Higher magnitude = more earnings management = worse
  # ==========================================================================
  if ("AC13" %in% names(results)) {
    ac14 <- copy(results[["AC13"]])
    ac14[, Raw_Value := -abs(Raw_Value)]  # negate abs: low magnitude = good
    ac14[, Factor_Name := "AC14_Discretionary_Accruals"]
    results[["AC14"]] <- ac14
  }

  # ==========================================================================
  # AC15: Non-Discretionary Accruals (predicted from Jones Model)
  # Predicted part = Total - Abnormal. Higher = more operational need, less concerning
  # ==========================================================================
  # Requires AC01 and AC13
  if ("AC01" %in% names(results) && "AC13" %in% names(results)) {
    nd <- merge(results[["AC01"]][, .(Ticker, total = Raw_Value)],
                results[["AC13"]][, .(Ticker, abnormal = Raw_Value)],
                by = "Ticker", all = FALSE)
    if (nrow(nd) > 0L) {
      # total = -TA/TA, abnormal = -abnormal_acc => non-disc = total - abnormal
      nd[, AC15 := total - abnormal]
      results[["AC15"]] <- nd[!is.na(AC15), .(Ticker, Factor_Name = "AC15_NonDiscretionary_Accruals", Raw_Value = AC15)]
    }
  }

  # ==========================================================================
  # AC16: Balance Sheet vs CF Accruals Difference (Shi & Zhang)
  # |BS Accruals - CF Accruals| as measure of non-articulation. Negate: lower = better
  # ==========================================================================
  if ("AC01" %in% names(results) && "AC02" %in% names(results)) {
    bscf <- merge(results[["AC01"]][, .(Ticker, cf_acc = Raw_Value)],
                  results[["AC02"]][, .(Ticker, bs_acc = Raw_Value)],
                  by = "Ticker", all = FALSE)
    if (nrow(bscf) > 0L) {
      bscf[, AC16 := -abs(cf_acc - bs_acc)]
      results[["AC16"]] <- bscf[!is.na(AC16), .(Ticker, Factor_Name = "AC16_BS_vs_CF_Diff", Raw_Value = AC16)]
    }
  }

  # ==========================================================================
  # AC17: Accrual Reversal Propensity (Allen, Larson, Sloan 2009)
  # Magnitude of current-period accrual reversal (change in accruals). Negate abs.
  # ==========================================================================
  items_ac17 <- c("NetIncome", "OperatingCF", "TotalAssets")
  if (is_long) {
    sub17 <- fund[Item %in% items_ac17]
    if (nrow(sub17) > 0L) {
      sub17[, date_rank := frank(-as.numeric(Factor_Date)), by = .(Ticker, Item)]
      # Need 3 periods for reversal
      p1 <- sub17[date_rank == 1]; p2 <- sub17[date_rank == 2]; p3 <- sub17[date_rank == 3]
      w1 <- dcast(p1, Ticker ~ Item, value.var = "Value")
      w2 <- dcast(p2, Ticker ~ Item, value.var = "Value")
      w3 <- dcast(p3, Ticker ~ Item, value.var = "Value")
      m17 <- Reduce(function(a, b) merge(a, b, by = "Ticker", suffixes = c("", paste0("_", ncol(b))), all = FALSE),
                     list(w1, w2, w3))
      # Simplified: compute accrual ratio for last 2 periods, take difference
      if (nrow(m17) > 0L && all(c("NetIncome", "OperatingCF", "TotalAssets") %in% names(w1)) &&
          all(c("NetIncome", "OperatingCF", "TotalAssets") %in% names(w2))) {
        # Merge properly
        a1 <- w1[, .(Ticker, acc1 = fifelse(TotalAssets != 0, (NetIncome - OperatingCF) / TotalAssets, NA_real_))]
        a2 <- w2[, .(Ticker, acc2 = fifelse(TotalAssets != 0, (NetIncome - OperatingCF) / TotalAssets, NA_real_))]
        rev17 <- merge(a1, a2, by = "Ticker", all = FALSE)
        rev17[, AC17 := -abs(acc1 - acc2)]
        results[["AC17"]] <- rev17[!is.na(AC17), .(Ticker, Factor_Name = "AC17_Accrual_Reversal", Raw_Value = AC17)]
      }
    }
  }

  # ==========================================================================
  # AC18: Accrual Component of Quality (QMJ, Asness 2019)
  # ACC = -(NI - OCF) / TA  (identical to AC01 by construction)
  # ==========================================================================
  if ("AC01" %in% names(results)) {
    ac18 <- copy(results[["AC01"]])
    ac18[, Factor_Name := "AC18_Accrual_Quality"]
    results[["AC18"]] <- ac18
  }

  # ==========================================================================
  # AC19: Receivables Accruals (dAR / avg TA, negated)
  # ==========================================================================
  items_ac19 <- c("AccountsReceivable", "TotalAssets")
  tp19 <- .get_two_periods(fund, items_ac19)
  if (!is.null(tp19)) {
    m19 <- merge(tp19$curr, tp19$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
    if (nrow(m19) > 0L) {
      d_ar   <- .sc(m19, "AccountsReceivable") - .sc(m19, "AccountsReceivable_p")
      avg_ta <- (.sc(m19, "TotalAssets") + .sc(m19, "TotalAssets_p")) / 2
      m19[, AC19 := .sdiv(-d_ar, avg_ta)]
      results[["AC19"]] <- m19[!is.na(AC19), .(Ticker, Factor_Name = "AC19_Receivables_Accruals", Raw_Value = AC19)]
    }
  }

  # ==========================================================================
  # AC20: Payables Accruals (dAP / avg TA, positive = good, raw sign)
  # Increasing payables = cash conservation = positive signal
  # ==========================================================================
  items_ac20 <- c("AccountsPayable", "TotalAssets")
  tp20 <- .get_two_periods(fund, items_ac20)
  if (!is.null(tp20)) {
    m20 <- merge(tp20$curr, tp20$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
    if (nrow(m20) > 0L) {
      d_ap   <- .sc(m20, "AccountsPayable") - .sc(m20, "AccountsPayable_p")
      avg_ta <- (.sc(m20, "TotalAssets") + .sc(m20, "TotalAssets_p")) / 2
      m20[, AC20 := .sdiv(d_ap, avg_ta)]
      results[["AC20"]] <- m20[!is.na(AC20), .(Ticker, Factor_Name = "AC20_Payables_Accruals", Raw_Value = AC20)]
    }
  }

  # ==========================================================================
  # AC21: Cash Flow to Accruals Ratio
  # OCF / |NI - OCF|. Higher = more cash-backed earnings = better
  # ==========================================================================
  items_ac21 <- c("NetIncome", "OperatingCF")
  fw21 <- .get_latest_wide(fund, items_ac21)
  if (!is.null(fw21)) {
    ni  <- .sc(fw21, "NetIncome")
    ocf <- .sc(fw21, "OperatingCF")
    acc_abs <- abs(ni - ocf)
    fw21[, AC21 := fifelse(acc_abs > 1e-8, ocf / acc_abs, NA_real_)]
    results[["AC21"]] <- fw21[!is.na(AC21) & is.finite(AC21),
                               .(Ticker, Factor_Name = "AC21_CF_to_Accrual_Ratio", Raw_Value = AC21)]
  }

  # ==========================================================================
  # AC22: Accrual Volatility (sd of accruals over available periods, negated)
  # ==========================================================================
  if (is_long) {
    sub22 <- fund[Item %in% c("NetIncome", "OperatingCF", "TotalAssets")]
    if (nrow(sub22) > 0L) {
      w22 <- dcast(sub22, Ticker + Factor_Date ~ Item, value.var = "Value")
      w22 <- w22[!is.na(NetIncome) & !is.na(OperatingCF) & !is.na(TotalAssets) & TotalAssets != 0]
      w22[, acc_ratio := (NetIncome - OperatingCF) / TotalAssets]
      vol22 <- w22[, .(n = .N, acc_vol = sd(acc_ratio, na.rm = TRUE)), by = Ticker]
      vol22 <- vol22[n >= 3L & !is.na(acc_vol)]
      if (nrow(vol22) > 0L) {
        results[["AC22"]] <- vol22[, .(Ticker, Factor_Name = "AC22_Accrual_Volatility", Raw_Value = -acc_vol)]
      }
    }
  }

  # ==========================================================================
  # AC23: Accrual Persistence (AR1 coefficient of accruals, higher = more persistent = worse)
  # ==========================================================================
  if (is_long) {
    sub23 <- fund[Item %in% c("NetIncome", "OperatingCF", "TotalAssets")]
    if (nrow(sub23) > 0L) {
      w23 <- dcast(sub23, Ticker + Factor_Date ~ Item, value.var = "Value")
      setorder(w23, Ticker, Factor_Date)
      w23 <- w23[!is.na(NetIncome) & !is.na(OperatingCF) & !is.na(TotalAssets) & TotalAssets != 0]
      w23[, acc_ratio := (NetIncome - OperatingCF) / TotalAssets]
      ar1_dt <- w23[, {
        if (.N >= 4L) {
          y <- acc_ratio[-1]
          x <- acc_ratio[-.N]
          if (sd(x, na.rm = TRUE) > 1e-8) {
            fit <- tryCatch(lm.fit(cbind(1, x), y), error = function(e) NULL)
            if (!is.null(fit)) {
              .(ar1 = fit$coefficients[2])
            } else {
              .(ar1 = NA_real_)
            }
          } else {
            .(ar1 = NA_real_)
          }
        } else {
          .(ar1 = NA_real_)
        }
      }, by = Ticker]
      ar1_dt <- ar1_dt[!is.na(ar1)]
      if (nrow(ar1_dt) > 0L) {
        # High persistence of accruals = bad. Negate.
        results[["AC23"]] <- ar1_dt[, .(Ticker, Factor_Name = "AC23_Accrual_Persistence", Raw_Value = -ar1)]
      }
    }
  }

  # ==========================================================================
  # AC24: Growth in NOA (dNOA / lag TA, negated)
  # Richardson Sloan Soliman Tuna (2006): growth in NOA subsumes accrual anomaly
  # ==========================================================================
  items_ac24 <- c("TotalAssets", "CashAndEquiv", "ShortTermBorr", "LongTermBorr",
                   "MinorityInterest", "PreferredStock", "TotalEquity")
  tp24 <- .get_two_periods(fund, items_ac24)
  if (!is.null(tp24)) {
    m24 <- merge(tp24$curr, tp24$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
    if (nrow(m24) > 0L) {
      .zna <- function(x) { x[is.na(x)] <- 0; x }
      noa_c <- (.sc(m24, "TotalAssets") - .zna(.sc(m24, "CashAndEquiv"))) -
               (.sc(m24, "TotalAssets") - .zna(.sc(m24, "ShortTermBorr")) - .zna(.sc(m24, "LongTermBorr")) -
                .zna(.sc(m24, "MinorityInterest")) - .zna(.sc(m24, "PreferredStock")) - .zna(.sc(m24, "TotalEquity")))
      noa_p <- (.sc(m24, "TotalAssets_p") - .zna(.sc(m24, "CashAndEquiv_p"))) -
               (.sc(m24, "TotalAssets_p") - .zna(.sc(m24, "ShortTermBorr_p")) - .zna(.sc(m24, "LongTermBorr_p")) -
                .zna(.sc(m24, "MinorityInterest_p")) - .zna(.sc(m24, "PreferredStock_p")) - .zna(.sc(m24, "TotalEquity_p")))
      lag_ta <- .sc(m24, "TotalAssets_p")
      m24[, AC24 := .sdiv(-(noa_c - noa_p), lag_ta)]
      results[["AC24"]] <- m24[!is.na(AC24), .(Ticker, Factor_Name = "AC24_NOA_Growth", Raw_Value = AC24)]
    }
  }

  # ==========================================================================
  # AC25: Accrual-Size Interaction (Palmon et al. 2008)
  # = AC01 * z(-MarketCap). Small firms with income-decreasing accruals outperform.
  # ==========================================================================
  if ("AC01" %in% names(results) && !is.null(snap) && nrow(snap) > 0L) {
    ac_sz <- merge(results[["AC01"]][, .(Ticker, acc_val = Raw_Value)],
                   snap, by = "Ticker", all = FALSE)
    if (nrow(ac_sz) > 0L) {
      mc_vals <- ac_sz$MarketCap
      mc_sd <- sd(mc_vals, na.rm = TRUE)
      if (!is.na(mc_sd) && mc_sd > 1e-8) {
        z_neg_mc <- -(mc_vals - mean(mc_vals, na.rm = TRUE)) / mc_sd
        ac_sz[, AC25 := acc_val * z_neg_mc]
        results[["AC25"]] <- ac_sz[!is.na(AC25), .(Ticker, Factor_Name = "AC25_Accrual_Size_Interaction", Raw_Value = AC25)]
      }
    }
  }

  # ---- Combine all ----
  if (length(results) == 0L) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }
  out <- rbindlist(results, use.names = TRUE, fill = TRUE)
  out[, .(Ticker, Factor_Name, Raw_Value)]
}

cat("[factor_db] compute_accrual.R loaded (AC01~AC25)\n")
