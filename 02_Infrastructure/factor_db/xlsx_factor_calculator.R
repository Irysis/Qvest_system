#==============================================================================
# xlsx_factor_calculator.R — Fundamental Factors from xlsx Raw Items (2000~2026)
#
# Computes quality, accrual, value, growth, leverage, and Piotroski F-Score
# factors DIRECTLY from fundamental_xlsx.parquet (41 raw items), bypassing
# DART-derived columns that only cover 2016+.
#
# Function:
#   compute_xlsx_fundamentals(RAWDATA, sig_date)
#
# Returns: data.table(Ticker, Factor_Name, Raw_Value)
#   All factor names prefixed with "XF_" to distinguish from existing Factor DB.
#
# PIT Rules:
#   - Factor_Date <= sig_date (most recent per Ticker x Item)
#   - Growth factors: two consecutive periods within same Ticker
#   - Value factors: denominator uses sig_date Close from RAWDATA
#   - Period_Date is NEVER used (reporting date = future info)
#
# C1~C11 Compliance:
#   C1: No full-sample stats. C2: No same-day circular. C3: No same-period
#   aggregate-then-apply. C4: Financial lag enforced via Factor_Date.
#   C11: Data time-axis verified (Factor_Date = availability date).
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

# ─── Path resolution ─────────────────────────────────────────────────────────
.xlsx_self_dir <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) {
    if (exists("FUNC_PATH")) FUNC_PATH
    else file.path(
      Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
      "02_Infrastructure"
    )
  }
)

if (!exists("CACHE_DIR")) {
  .xlsx_proj <- dirname(.xlsx_self_dir)
  CACHE_DIR <- file.path(.xlsx_proj, ".cache")
}

XLSX_FUND_PATH <- file.path(CACHE_DIR, "fundamental_xlsx.parquet")

# ─── Safe division helper ────────────────────────────────────────────────────
.xf_sdiv <- function(num, den, min_den = 1e-8) {
  fifelse(!is.na(num) & !is.na(den) & abs(den) > min_den,
          num / den, NA_real_)
}

# ─── Safe column extractor ───────────────────────────────────────────────────
.xf_col <- function(dt, col) {
  if (col %in% names(dt)) dt[[col]] else rep(NA_real_, nrow(dt))
}

#==============================================================================
# Main function
#==============================================================================

#' Compute fundamental-derived factors from xlsx raw items
#'
#' @param RAWDATA data.table with Date, Ticker, Close, Size, Ret, Vol, etc.
#' @param sig_date Date. Signal date — all data must be available by this date.
#' @param FUND Ignored. Present for compatibility with .run_module() calling convention.
#' @param CONSENSUS Ignored. Present for compatibility with .run_module() calling convention.
#' @return data.table(Ticker, Factor_Name, Raw_Value) with XF_ prefix
compute_xlsx_fundamentals <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {

  sig_d <- as.Date(sig_date)
  results <- list()

  # ── 1. Load xlsx parquet ──────────────────────────────────────────────────
  if (!file.exists(XLSX_FUND_PATH)) {
    cat("[xlsx_factor_calc] fundamental_xlsx.parquet not found:", XLSX_FUND_PATH, "\n")
    return(data.table(Ticker = character(), Factor_Name = character(),
                      Raw_Value = numeric()))
  }

  xlsx_raw <- as.data.table(read_parquet(XLSX_FUND_PATH))
  cat(sprintf("[xlsx_factor_calc] Loaded %s rows from xlsx parquet\n",
              format(nrow(xlsx_raw), big.mark = ",")))

  # ── 2. PIT filter: Factor_Date <= sig_date ────────────────────────────────
  xlsx_pit <- xlsx_raw[Factor_Date <= sig_d]
  if (nrow(xlsx_pit) == 0L) {
    cat("[xlsx_factor_calc] No data available before", as.character(sig_d), "\n")
    return(data.table(Ticker = character(), Factor_Name = character(),
                      Raw_Value = numeric()))
  }

  cat(sprintf("[xlsx_factor_calc] PIT filter: %s rows (Factor_Date <= %s)\n",
              format(nrow(xlsx_pit), big.mark = ","), sig_d))

  # ── 3. Most recent per Ticker x Item (current period) ────────────────────
  setorder(xlsx_pit, Ticker, Item, -Factor_Date)
  curr_long <- xlsx_pit[, .SD[1L], by = .(Ticker, Item)]

  # Also get the second-most-recent (previous period) for growth/Piotroski
  prev_long <- xlsx_pit[, {
    if (.N >= 2L) .SD[2L] else NULL
  }, by = .(Ticker, Item)]

  # ── 4. Pivot to wide (current) ───────────────────────────────────────────
  curr_wide <- dcast(curr_long, Ticker ~ Item, value.var = "Value")

  # Ensure all 41 items exist as columns (fill missing with NA)
  all_items <- c("AccountsPay", "AccountsRecv", "CapitalStock", "CashAndEquiv",
                 "COGS", "CurrentAssets", "CurrentLiab", "DepAmort", "Dividends",
                 "FCF1", "FCF2", "FinanceCF", "GrossProfit", "IntangibleAssets",
                 "InterestExp", "InterestIncome", "Inventory", "InvestCF", "ISSD",
                 "LongTermBorr", "LongTermPay", "LongTermRecv", "NetInterestExp",
                 "NonCurrentAssets", "NonCurrentLiab", "OperatingCF",
                 "OperatingProfit", "OrdRandD", "PretaxIncome", "RandD",
                 "RetainedEarnings", "Revenue", "SBB", "SGAExpense",
                 "ShortTermBorr", "TangibleAssets", "TaxExpense", "TotalAssets",
                 "TotalEquity", "TotalLiab", "TotalNetInterestExp")
  for (col_nm in all_items) {
    if (!col_nm %in% names(curr_wide)) curr_wide[, (col_nm) := NA_real_]
  }

  # Pivot previous period to wide
  prev_wide <- NULL
  if (!is.null(prev_long) && nrow(prev_long) > 0L) {
    prev_wide <- dcast(prev_long, Ticker ~ Item, value.var = "Value")
    for (col_nm in all_items) {
      if (!col_nm %in% names(prev_wide)) prev_wide[, (col_nm) := NA_real_]
    }
  }

  # ── 5. Derive NetIncome ──────────────────────────────────────────────────
  curr_wide[, NetIncome := fifelse(!is.na(PretaxIncome) & !is.na(TaxExpense),
                                   PretaxIncome - TaxExpense, NA_real_)]

  # ── 6. Price snapshot from RAWDATA (for value factors) ───────────────────
  avail_dates <- sort(unique(RAWDATA[Date <= sig_d & !is.na(Close) & Close > 0]$Date),
                      decreasing = TRUE)
  snap <- NULL
  if (length(avail_dates) > 0L) {
    snap_date <- avail_dates[1L]
    snap <- RAWDATA[Date == snap_date & !is.na(Close) & Close > 0,
                    .(Ticker, Close, Size)]
    snap[, MarketCap := Close * Size]
    snap <- snap[MarketCap > 0]
  }

  # =========================================================================
  # QUALITY FACTORS (XF_Q01 ~ XF_Q08)
  # =========================================================================
  dt <- copy(curr_wide)

  # XF_Q01: GPA = GrossProfit / TotalAssets
  dt[, xf_gpa := .xf_sdiv(GrossProfit, TotalAssets)]
  results[["XF_Q01_GPA"]] <- dt[!is.na(xf_gpa),
    .(Ticker, Factor_Name = "XF_Q01_GPA", Raw_Value = xf_gpa)]

  # XF_Q02: ROE = NetIncome / TotalEquity
  dt[, xf_roe := .xf_sdiv(NetIncome, TotalEquity)]
  results[["XF_Q02_ROE"]] <- dt[!is.na(xf_roe),
    .(Ticker, Factor_Name = "XF_Q02_ROE", Raw_Value = xf_roe)]

  # XF_Q03: ROA = NetIncome / TotalAssets
  dt[, xf_roa := .xf_sdiv(NetIncome, TotalAssets)]
  results[["XF_Q03_ROA"]] <- dt[!is.na(xf_roa),
    .(Ticker, Factor_Name = "XF_Q03_ROA", Raw_Value = xf_roa)]

  # XF_Q04: Asset Turnover = Revenue / TotalAssets
  dt[, xf_at := .xf_sdiv(Revenue, TotalAssets)]
  results[["XF_Q04_Asset_Turnover"]] <- dt[!is.na(xf_at),
    .(Ticker, Factor_Name = "XF_Q04_Asset_Turnover", Raw_Value = xf_at)]

  # XF_Q05: Gross Margin = GrossProfit / Revenue
  dt[, xf_gm := .xf_sdiv(GrossProfit, Revenue)]
  results[["XF_Q05_Gross_Margin"]] <- dt[!is.na(xf_gm),
    .(Ticker, Factor_Name = "XF_Q05_Gross_Margin", Raw_Value = xf_gm)]

  # XF_Q06: Operating Margin = OperatingProfit / Revenue
  dt[, xf_om := .xf_sdiv(OperatingProfit, Revenue)]
  results[["XF_Q06_Op_Margin"]] <- dt[!is.na(xf_om),
    .(Ticker, Factor_Name = "XF_Q06_Op_Margin", Raw_Value = xf_om)]

  # XF_Q07: Net Margin = NetIncome / Revenue
  dt[, xf_nm := .xf_sdiv(NetIncome, Revenue)]
  results[["XF_Q07_Net_Margin"]] <- dt[!is.na(xf_nm),
    .(Ticker, Factor_Name = "XF_Q07_Net_Margin", Raw_Value = xf_nm)]

  # XF_Q08: Interest Coverage = OperatingProfit / InterestExp (when InterestExp > 0)
  dt[, xf_ic := fifelse(!is.na(OperatingProfit) & !is.na(InterestExp) & InterestExp > 1e-8,
                         OperatingProfit / InterestExp, NA_real_)]
  results[["XF_Q08_Interest_Coverage"]] <- dt[!is.na(xf_ic) & is.finite(xf_ic),
    .(Ticker, Factor_Name = "XF_Q08_Interest_Coverage", Raw_Value = xf_ic)]

  # =========================================================================
  # ACCRUAL FACTORS (XF_A01 ~ XF_A02)
  # =========================================================================

  # XF_A01: Accrual = (NetIncome - OperatingCF) / TotalAssets
  dt[, xf_accrual := .xf_sdiv(NetIncome - OperatingCF, TotalAssets)]
  results[["XF_A01_Accrual"]] <- dt[!is.na(xf_accrual),
    .(Ticker, Factor_Name = "XF_A01_Accrual", Raw_Value = xf_accrual)]

  # XF_A02: NOA = (TotalAssets - CashAndEquiv - (TotalLiab - ShortTermBorr - LongTermBorr)) / TotalAssets
  # NOA = (Operating Assets - Operating Liabilities) / TotalAssets
  dt[, xf_oa := TotalAssets - fifelse(is.na(CashAndEquiv), 0, CashAndEquiv)]
  dt[, xf_ol := TotalLiab - fifelse(is.na(ShortTermBorr), 0, ShortTermBorr) -
                             fifelse(is.na(LongTermBorr), 0, LongTermBorr)]
  dt[, xf_noa := .xf_sdiv(xf_oa - xf_ol, TotalAssets)]
  results[["XF_A02_NOA"]] <- dt[!is.na(xf_noa),
    .(Ticker, Factor_Name = "XF_A02_NOA", Raw_Value = xf_noa)]

  # =========================================================================
  # VALUE FACTORS (XF_V01 ~ XF_V04) — need price from RAWDATA
  # =========================================================================

  if (!is.null(snap) && nrow(snap) > 0L) {
    vdt <- merge(dt, snap[, .(Ticker, MarketCap)], by = "Ticker", all.x = FALSE)

    if (nrow(vdt) > 0L) {
      # XF_V01: BM = TotalEquity / MarketCap
      vdt[, xf_bm := .xf_sdiv(TotalEquity, MarketCap)]
      results[["XF_V01_BM"]] <- vdt[!is.na(xf_bm),
        .(Ticker, Factor_Name = "XF_V01_BM", Raw_Value = xf_bm)]

      # XF_V02: EP = NetIncome / MarketCap
      vdt[, xf_ep := .xf_sdiv(NetIncome, MarketCap)]
      results[["XF_V02_EP"]] <- vdt[!is.na(xf_ep),
        .(Ticker, Factor_Name = "XF_V02_EP", Raw_Value = xf_ep)]

      # XF_V03: CFP = OperatingCF / MarketCap
      vdt[, xf_cfp := .xf_sdiv(OperatingCF, MarketCap)]
      results[["XF_V03_CFP"]] <- vdt[!is.na(xf_cfp),
        .(Ticker, Factor_Name = "XF_V03_CFP", Raw_Value = xf_cfp)]

      # XF_V04: SP = Revenue / MarketCap
      vdt[, xf_sp := .xf_sdiv(Revenue, MarketCap)]
      results[["XF_V04_SP"]] <- vdt[!is.na(xf_sp),
        .(Ticker, Factor_Name = "XF_V04_SP", Raw_Value = xf_sp)]
    }
  }

  # =========================================================================
  # GROWTH FACTORS (XF_G01 ~ XF_G03) — need previous period
  # =========================================================================

  if (!is.null(prev_wide) && nrow(prev_wide) > 0L) {
    # Derive NetIncome for previous period
    prev_wide[, NetIncome := fifelse(!is.na(PretaxIncome) & !is.na(TaxExpense),
                                     PretaxIncome - TaxExpense, NA_real_)]

    # Merge current and previous
    gdt <- merge(curr_wide, prev_wide, by = "Ticker", suffixes = c("", "_prev"),
                 all = FALSE)

    if (nrow(gdt) > 0L) {
      # XF_G01: Asset Growth = (TA_curr - TA_prev) / TA_prev
      gdt[, xf_ag := .xf_sdiv(TotalAssets - TotalAssets_prev, abs(TotalAssets_prev))]
      results[["XF_G01_Asset_Growth"]] <- gdt[!is.na(xf_ag) & is.finite(xf_ag),
        .(Ticker, Factor_Name = "XF_G01_Asset_Growth", Raw_Value = xf_ag)]

      # XF_G02: Revenue Growth = (Rev_curr - Rev_prev) / abs(Rev_prev)
      gdt[, xf_rg := .xf_sdiv(Revenue - Revenue_prev, abs(Revenue_prev))]
      results[["XF_G02_Revenue_Growth"]] <- gdt[!is.na(xf_rg) & is.finite(xf_rg),
        .(Ticker, Factor_Name = "XF_G02_Revenue_Growth", Raw_Value = xf_rg)]

      # XF_G03: Earnings Growth = (NI_curr - NI_prev) / abs(NI_prev)
      gdt[, xf_eg := .xf_sdiv(NetIncome - NetIncome_prev, pmax(abs(NetIncome_prev), 1e-8))]
      results[["XF_G03_Earnings_Growth"]] <- gdt[!is.na(xf_eg) & is.finite(xf_eg),
        .(Ticker, Factor_Name = "XF_G03_Earnings_Growth", Raw_Value = xf_eg)]

      # =====================================================================
      # GROWTH DEEP (XF_GD01 ~ XF_GD04) — also needs previous period
      # =====================================================================

      # XF_GD01: Gross Profit Growth = dGP / |GP_prev|
      gdt[, xf_gd_gp := .xf_sdiv(GrossProfit - GrossProfit_prev,
                                    pmax(abs(GrossProfit_prev), 1e-8))]
      results[["XF_GD01_GrossProfit_Growth"]] <- gdt[!is.na(xf_gd_gp) & is.finite(xf_gd_gp),
        .(Ticker, Factor_Name = "XF_GD01_GrossProfit_Growth", Raw_Value = xf_gd_gp)]

      # XF_GD02: Operating Profit Growth = dOP / |OP_prev|
      gdt[, xf_gd_op := .xf_sdiv(OperatingProfit - OperatingProfit_prev,
                                    pmax(abs(OperatingProfit_prev), 1e-8))]
      results[["XF_GD02_OpProfit_Growth"]] <- gdt[!is.na(xf_gd_op) & is.finite(xf_gd_op),
        .(Ticker, Factor_Name = "XF_GD02_OpProfit_Growth", Raw_Value = xf_gd_op)]

      # XF_GD03: Operating CF Growth = dOCF / |OCF_prev|
      gdt[, xf_gd_ocf := .xf_sdiv(OperatingCF - OperatingCF_prev,
                                     pmax(abs(OperatingCF_prev), 1e-8))]
      results[["XF_GD03_OCF_Growth"]] <- gdt[!is.na(xf_gd_ocf) & is.finite(xf_gd_ocf),
        .(Ticker, Factor_Name = "XF_GD03_OCF_Growth", Raw_Value = xf_gd_ocf)]

      # XF_GD04: Dividend Growth = dDiv / |Div_prev|
      gdt[, xf_gd_div := .xf_sdiv(Dividends - Dividends_prev,
                                     pmax(abs(Dividends_prev), 1e-8))]
      results[["XF_GD04_Dividend_Growth"]] <- gdt[!is.na(xf_gd_div) & is.finite(xf_gd_div),
        .(Ticker, Factor_Name = "XF_GD04_Dividend_Growth", Raw_Value = xf_gd_div)]
    }
  }

  # =========================================================================
  # LEVERAGE FACTORS (XF_L01 ~ XF_L02)
  # =========================================================================

  # XF_L01: Debt to Equity = (ShortTermBorr + LongTermBorr) / TotalEquity
  dt[, xf_de := .xf_sdiv(
    fifelse(is.na(ShortTermBorr), 0, ShortTermBorr) +
    fifelse(is.na(LongTermBorr), 0, LongTermBorr),
    TotalEquity)]
  results[["XF_L01_Debt_to_Equity"]] <- dt[!is.na(xf_de) & is.finite(xf_de),
    .(Ticker, Factor_Name = "XF_L01_Debt_to_Equity", Raw_Value = xf_de)]

  # XF_L02: Current Ratio = CurrentAssets / CurrentLiab
  dt[, xf_cr := .xf_sdiv(CurrentAssets, CurrentLiab)]
  results[["XF_L02_Current_Ratio"]] <- dt[!is.na(xf_cr) & is.finite(xf_cr),
    .(Ticker, Factor_Name = "XF_L02_Current_Ratio", Raw_Value = xf_cr)]

  # =========================================================================
  # DUPONT DECOMPOSITION (XF_DU01 ~ XF_DU03)
  # =========================================================================

  # XF_DU01: Net Margin = (PretaxIncome - TaxExpense) / Revenue
  dt[, xf_du_nm := .xf_sdiv(NetIncome, Revenue)]
  results[["XF_DU01_NetMargin"]] <- dt[!is.na(xf_du_nm),
    .(Ticker, Factor_Name = "XF_DU01_NetMargin", Raw_Value = xf_du_nm)]

  # XF_DU02: Asset Turnover = Revenue / TotalAssets
  dt[, xf_du_at := .xf_sdiv(Revenue, TotalAssets)]
  results[["XF_DU02_AssetTurnover"]] <- dt[!is.na(xf_du_at),
    .(Ticker, Factor_Name = "XF_DU02_AssetTurnover", Raw_Value = xf_du_at)]

  # XF_DU03: Equity Multiplier = TotalAssets / TotalEquity
  dt[, xf_du_em := .xf_sdiv(TotalAssets, TotalEquity)]
  results[["XF_DU03_EquityMultiplier"]] <- dt[!is.na(xf_du_em),
    .(Ticker, Factor_Name = "XF_DU03_EquityMultiplier", Raw_Value = xf_du_em)]

  # =========================================================================
  # LEVERAGE / LIQUIDITY (XF_LL01 ~ XF_LL05)
  # =========================================================================

  # Precompute total borrowings (reused across factors)
  dt[, xf_total_borr := fifelse(is.na(ShortTermBorr), 0, ShortTermBorr) +
                         fifelse(is.na(LongTermBorr), 0, LongTermBorr)]

  # XF_LL01: Debt to Capital = TotalBorr / (TotalEquity + TotalBorr)
  dt[, xf_ll_dc := .xf_sdiv(xf_total_borr, TotalEquity + xf_total_borr)]
  results[["XF_LL01_DebtToCapital"]] <- dt[!is.na(xf_ll_dc) & is.finite(xf_ll_dc),
    .(Ticker, Factor_Name = "XF_LL01_DebtToCapital", Raw_Value = xf_ll_dc)]

  # XF_LL02: Net Debt = TotalBorr - CashAndEquiv (raw value, to be cross-sectionally normalized)
  dt[, xf_ll_nd := xf_total_borr - fifelse(is.na(CashAndEquiv), 0, CashAndEquiv)]
  results[["XF_LL02_NetDebt"]] <- dt[!is.na(xf_ll_nd) & is.finite(xf_ll_nd),
    .(Ticker, Factor_Name = "XF_LL02_NetDebt", Raw_Value = xf_ll_nd)]

  # XF_LL03: Cash Ratio = CashAndEquiv / CurrentLiab
  dt[, xf_ll_cashr := .xf_sdiv(CashAndEquiv, CurrentLiab)]
  results[["XF_LL03_CashRatio"]] <- dt[!is.na(xf_ll_cashr) & is.finite(xf_ll_cashr),
    .(Ticker, Factor_Name = "XF_LL03_CashRatio", Raw_Value = xf_ll_cashr)]

  # XF_LL04: Quick Ratio = (CurrentAssets - Inventory) / CurrentLiab
  dt[, xf_ll_qr := .xf_sdiv(CurrentAssets - fifelse(is.na(Inventory), 0, Inventory),
                              CurrentLiab)]
  results[["XF_LL04_QuickRatio"]] <- dt[!is.na(xf_ll_qr) & is.finite(xf_ll_qr),
    .(Ticker, Factor_Name = "XF_LL04_QuickRatio", Raw_Value = xf_ll_qr)]

  # XF_LL05: Working Capital Ratio = (CurrentAssets - CurrentLiab) / TotalAssets
  dt[, xf_ll_wc := .xf_sdiv(CurrentAssets - CurrentLiab, TotalAssets)]
  results[["XF_LL05_WorkingCapital"]] <- dt[!is.na(xf_ll_wc) & is.finite(xf_ll_wc),
    .(Ticker, Factor_Name = "XF_LL05_WorkingCapital", Raw_Value = xf_ll_wc)]

  # =========================================================================
  # PROFITABILITY DEEP (XF_PR01 ~ XF_PR05)
  # =========================================================================

  # XF_PR01: EBITDA Margin = (OperatingProfit + DepAmort) / Revenue
  dt[, xf_pr_ebitdam := .xf_sdiv(OperatingProfit + fifelse(is.na(DepAmort), 0, DepAmort),
                                   Revenue)]
  results[["XF_PR01_EBITDA_Margin"]] <- dt[!is.na(xf_pr_ebitdam),
    .(Ticker, Factor_Name = "XF_PR01_EBITDA_Margin", Raw_Value = xf_pr_ebitdam)]

  # XF_PR02: Retained Earnings Ratio = RetainedEarnings / TotalEquity
  dt[, xf_pr_rer := .xf_sdiv(RetainedEarnings, TotalEquity)]
  results[["XF_PR02_RetainedEarnings_Ratio"]] <- dt[!is.na(xf_pr_rer) & is.finite(xf_pr_rer),
    .(Ticker, Factor_Name = "XF_PR02_RetainedEarnings_Ratio", Raw_Value = xf_pr_rer)]

  # XF_PR03: Effective Tax Rate = TaxExpense / PretaxIncome
  dt[, xf_pr_tr := fifelse(!is.na(TaxExpense) & !is.na(PretaxIncome) & PretaxIncome > 1e-8,
                            TaxExpense / PretaxIncome, NA_real_)]
  results[["XF_PR03_TaxRate"]] <- dt[!is.na(xf_pr_tr) & is.finite(xf_pr_tr),
    .(Ticker, Factor_Name = "XF_PR03_TaxRate", Raw_Value = xf_pr_tr)]

  # XF_PR04: Net Interest Margin = NetInterestExp / TotalAssets
  dt[, xf_pr_nim := .xf_sdiv(NetInterestExp, TotalAssets)]
  results[["XF_PR04_NetInterestMargin"]] <- dt[!is.na(xf_pr_nim) & is.finite(xf_pr_nim),
    .(Ticker, Factor_Name = "XF_PR04_NetInterestMargin", Raw_Value = xf_pr_nim)]

  # XF_PR05: EBITDA to Assets = (OperatingProfit + DepAmort) / TotalAssets
  dt[, xf_pr_ebitda_ta := .xf_sdiv(OperatingProfit + fifelse(is.na(DepAmort), 0, DepAmort),
                                     TotalAssets)]
  results[["XF_PR05_EBITDA_to_Assets"]] <- dt[!is.na(xf_pr_ebitda_ta),
    .(Ticker, Factor_Name = "XF_PR05_EBITDA_to_Assets", Raw_Value = xf_pr_ebitda_ta)]

  # =========================================================================
  # EFFICIENCY (XF_EF01 ~ XF_EF04)
  # =========================================================================

  # XF_EF01: Inventory Turnover = COGS / Inventory
  dt[, xf_ef_invt := .xf_sdiv(COGS, Inventory)]
  results[["XF_EF01_InventoryTurnover"]] <- dt[!is.na(xf_ef_invt) & is.finite(xf_ef_invt),
    .(Ticker, Factor_Name = "XF_EF01_InventoryTurnover", Raw_Value = xf_ef_invt)]

  # XF_EF02: Days Payable = AccountsPay / (COGS / 365)
  dt[, xf_ef_dp := .xf_sdiv(AccountsPay, COGS / 365)]
  results[["XF_EF02_DaysPayable"]] <- dt[!is.na(xf_ef_dp) & is.finite(xf_ef_dp),
    .(Ticker, Factor_Name = "XF_EF02_DaysPayable", Raw_Value = xf_ef_dp)]

  # XF_EF03: Days Receivable = AccountsRecv / (Revenue / 365)
  dt[, xf_ef_dr := .xf_sdiv(AccountsRecv, Revenue / 365)]
  results[["XF_EF03_DaysReceivable"]] <- dt[!is.na(xf_ef_dr) & is.finite(xf_ef_dr),
    .(Ticker, Factor_Name = "XF_EF03_DaysReceivable", Raw_Value = xf_ef_dr)]

  # XF_EF04: Cash Conversion Cycle = DaysReceivable + DaysInventory - DaysPayable
  dt[, xf_ef_di := .xf_sdiv(Inventory, COGS / 365)]   # Days Inventory
  dt[, xf_ef_ccc := xf_ef_dr + xf_ef_di - xf_ef_dp]
  results[["XF_EF04_CCC"]] <- dt[!is.na(xf_ef_ccc) & is.finite(xf_ef_ccc),
    .(Ticker, Factor_Name = "XF_EF04_CCC", Raw_Value = xf_ef_ccc)]

  # =========================================================================
  # R&D / INVESTMENT (XF_RI01 ~ XF_RI03)
  # =========================================================================

  # XF_RI01: R&D to Revenue = RandD / Revenue
  dt[, xf_ri_rnd := .xf_sdiv(RandD, Revenue)]
  results[["XF_RI01_RnD_to_Revenue"]] <- dt[!is.na(xf_ri_rnd) & is.finite(xf_ri_rnd),
    .(Ticker, Factor_Name = "XF_RI01_RnD_to_Revenue", Raw_Value = xf_ri_rnd)]

  # XF_RI02: CapEx proxy = -InvestCF / TotalAssets (InvestCF is negative for spending)
  dt[, xf_ri_capex := .xf_sdiv(-InvestCF, TotalAssets)]
  results[["XF_RI02_CapEx_proxy"]] <- dt[!is.na(xf_ri_capex) & is.finite(xf_ri_capex),
    .(Ticker, Factor_Name = "XF_RI02_CapEx_proxy", Raw_Value = xf_ri_capex)]

  # XF_RI03: SGA to Revenue = SGAExpense / Revenue
  dt[, xf_ri_sga := .xf_sdiv(SGAExpense, Revenue)]
  results[["XF_RI03_SGA_to_Revenue"]] <- dt[!is.na(xf_ri_sga) & is.finite(xf_ri_sga),
    .(Ticker, Factor_Name = "XF_RI03_SGA_to_Revenue", Raw_Value = xf_ri_sga)]

  # =========================================================================
  # PIOTROSKI F-SCORE (XF_P01) — 9 components, all from xlsx
  # =========================================================================

  if (!is.null(prev_wide) && nrow(prev_wide) > 0L) {
    # Derive NetIncome for previous if not already done
    if (!"NetIncome" %in% names(prev_wide)) {
      prev_wide[, NetIncome := fifelse(!is.na(PretaxIncome) & !is.na(TaxExpense),
                                       PretaxIncome - TaxExpense, NA_real_)]
    }

    # Get tickers with both periods
    piot_tickers <- intersect(curr_wide$Ticker, prev_wide$Ticker)

    if (length(piot_tickers) > 0L) {
      # Vectorized Piotroski using merge
      pc <- copy(curr_wide[Ticker %in% piot_tickers])
      pp <- copy(prev_wide[Ticker %in% piot_tickers])

      # Set keys for aligned merge
      setkey(pc, Ticker)
      setkey(pp, Ticker)

      # Merge with suffixes
      pdt <- merge(pc, pp, by = "Ticker", suffixes = c("", "_p"), all = FALSE)

      if (nrow(pdt) > 0L) {
        # Derive ratios — current period
        pdt[, roa_c := .xf_sdiv(NetIncome, TotalAssets)]
        pdt[, ocf_c := OperatingCF]
        pdt[, debt_ta_c := .xf_sdiv(
          fifelse(is.na(ShortTermBorr), 0, ShortTermBorr) +
          fifelse(is.na(LongTermBorr), 0, LongTermBorr),
          TotalAssets)]
        pdt[, cr_c := .xf_sdiv(CurrentAssets, CurrentLiab)]
        pdt[, gm_c := .xf_sdiv(GrossProfit, Revenue)]
        pdt[, at_c := .xf_sdiv(Revenue, TotalAssets)]

        # Derive ratios — previous period
        pdt[, roa_p := .xf_sdiv(NetIncome_p, TotalAssets_p)]
        pdt[, debt_ta_p := .xf_sdiv(
          fifelse(is.na(ShortTermBorr_p), 0, ShortTermBorr_p) +
          fifelse(is.na(LongTermBorr_p), 0, LongTermBorr_p),
          TotalAssets_p)]
        pdt[, cr_p := .xf_sdiv(CurrentAssets_p, CurrentLiab_p)]
        pdt[, gm_p := .xf_sdiv(GrossProfit_p, Revenue_p)]
        pdt[, at_p := .xf_sdiv(Revenue_p, TotalAssets_p)]

        # 9 Components (each yields 0 or 1, NA-safe)
        # 1. ROA > 0
        pdt[, f1 := fifelse(!is.na(roa_c) & roa_c > 0, 1L, 0L)]
        # 2. OperatingCF > 0
        pdt[, f2 := fifelse(!is.na(ocf_c) & ocf_c > 0, 1L, 0L)]
        # 3. ROA change > 0
        pdt[, f3 := fifelse(!is.na(roa_c) & !is.na(roa_p) & (roa_c - roa_p) > 0, 1L, 0L)]
        # 4. OperatingCF > NetIncome (accrual quality)
        pdt[, f4 := fifelse(!is.na(ocf_c) & !is.na(NetIncome) & ocf_c > NetIncome, 1L, 0L)]
        # 5. Debt-to-Assets decrease
        pdt[, f5 := fifelse(!is.na(debt_ta_c) & !is.na(debt_ta_p) & (debt_ta_c - debt_ta_p) < 0, 1L, 0L)]
        # 6. Current Ratio increase
        pdt[, f6 := fifelse(!is.na(cr_c) & !is.na(cr_p) & (cr_c - cr_p) > 0, 1L, 0L)]
        # 7. No new equity issuance (ISSD == 0 or decreased)
        pdt[, f7 := fifelse(!is.na(ISSD) & !is.na(ISSD_p) & ISSD <= ISSD_p, 1L,
                     fifelse(!is.na(ISSD) & ISSD == 0, 1L, 0L))]
        # 8. Gross Margin increase
        pdt[, f8 := fifelse(!is.na(gm_c) & !is.na(gm_p) & (gm_c - gm_p) > 0, 1L, 0L)]
        # 9. Asset Turnover increase
        pdt[, f9 := fifelse(!is.na(at_c) & !is.na(at_p) & (at_c - at_p) > 0, 1L, 0L)]

        # Total F-Score
        pdt[, f_score := f1 + f2 + f3 + f4 + f5 + f6 + f7 + f8 + f9]

        results[["XF_P01_Piotroski_F"]] <- pdt[,
          .(Ticker, Factor_Name = "XF_P01_Piotroski_F", Raw_Value = as.numeric(f_score))]
      }
    }
  }

  # =========================================================================
  # Combine all results
  # =========================================================================
  results <- results[!sapply(results, is.null)]
  results <- results[sapply(results, function(x) nrow(x) > 0L)]

  if (length(results) == 0L) {
    cat("[xlsx_factor_calc] No factors computed\n")
    return(data.table(Ticker = character(), Factor_Name = character(),
                      Raw_Value = numeric()))
  }

  out <- rbindlist(results, use.names = TRUE)

  # Remove any infinite values
  out <- out[is.finite(Raw_Value)]

  # Summary
  n_factors <- uniqueN(out$Factor_Name)
  n_tickers <- uniqueN(out$Ticker)
  cat(sprintf("[xlsx_factor_calc] Done: %d factors x %d tickers = %s rows\n",
              n_factors, n_tickers, format(nrow(out), big.mark = ",")))

  # Per-factor summary
  factor_summary <- out[, .(N = .N,
                            Mean = round(mean(Raw_Value, na.rm = TRUE), 4),
                            Median = round(median(Raw_Value, na.rm = TRUE), 4)),
                        by = Factor_Name][order(Factor_Name)]
  cat("  Factor coverage:\n")
  print(factor_summary)

  return(out)
}

cat("[factor_db] xlsx_factor_calculator.R loaded (44 factors: XF_Q01~Q08, XF_A01~A02, XF_V01~V04, XF_G01~G03, XF_L01~L02, XF_P01, XF_DU01~DU03, XF_LL01~LL05, XF_PR01~PR05, XF_EF01~EF04, XF_GD01~GD04, XF_RI01~RI03)\n")
