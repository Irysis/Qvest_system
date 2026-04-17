#==============================================================================
# build_fundamental_derived.R
# Compute 140 derived fundamental items from XLSX raw items (2000~2015)
# and merge into fundamental_merged.parquet for continuous 2000~2026 series.
#
# Logic:
#   1. Load fundamental_xlsx.parquet (41 raw items, long format)
#   2. Pivot to wide (Ticker x Period), compute averages, derive 140 items
#   3. Melt back to long, mark Source = "xlsx_derived"
#   4. Merge with existing fundamental_merged.parquet (DART priority 2016+)
#   5. Save updated fundamental_merged.parquet
#
# Formulas replicate data_collector_dart.R exactly.
# Growth/delta items use shift() by Ticker (need consecutive periods).
#==============================================================================

cat("=== build_fundamental_derived.R ===\n")
cat("Start:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

# ---- Paths ----
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
CACHE_DIR    <- file.path(PROJECT_ROOT, ".cache")
XLSX_PATH    <- file.path(CACHE_DIR, "fundamental_xlsx.parquet")
MERGED_PATH  <- file.path(CACHE_DIR, "fundamental_merged.parquet")
BACKUP_PATH  <- file.path(CACHE_DIR, "fundamental_merged_backup.parquet")

stopifnot(file.exists(XLSX_PATH), file.exists(MERGED_PATH))

# ---- 1. Load XLSX raw data ----
cat("[1/5] Loading fundamental_xlsx.parquet...\n")
xlsx_long <- as.data.table(read_parquet(XLSX_PATH))
cat(sprintf("  Rows: %s | Tickers: %d | Items: %d | Periods: %d\n",
            format(nrow(xlsx_long), big.mark = ","),
            uniqueN(xlsx_long$Ticker),
            uniqueN(xlsx_long$Item),
            uniqueN(xlsx_long$Period)))

# ---- 2. Pivot to wide format (Ticker x Period) ----
cat("[2/5] Pivoting to wide format...\n")
# Keep only necessary columns
xlsx_long <- xlsx_long[, .(Ticker, Period, Period_Date, Factor_Date, Item, Value)]

# Dcast: one row per Ticker x Period
wide <- dcast(xlsx_long, Ticker + Period + Period_Date + Factor_Date ~ Item,
              value.var = "Value", fun.aggregate = function(x) x[1])

cat(sprintf("  Wide: %s rows x %d cols\n",
            format(nrow(wide), big.mark = ","), ncol(wide)))

# Sort by Ticker, Period for shift() operations
setorder(wide, Ticker, Period)

# ---- Safe division helper ----
.safe_div <- function(num, denom, min_denom = 0) {
  fifelse(!is.na(num) & !is.na(denom) & denom > min_denom, num / denom, NA_real_)
}

# ---- 3. Compute averages (using shift by Ticker, same as DART) ----
cat("[3/5] Computing 140 derived items...\n")

# Average denominators (current + previous period average)
wide[, AvgAssets    := (TotalAssets   + shift(TotalAssets))   / 2, by = Ticker]
wide[, AvgEquity    := (TotalEquity   + shift(TotalEquity))   / 2, by = Ticker]
wide[, AvgInventory := (Inventory     + shift(Inventory))     / 2, by = Ticker]
wide[, AvgRecv      := (AccountsRecv  + shift(AccountsRecv))  / 2, by = Ticker]
wide[, AvgPay       := (AccountsPay   + shift(AccountsPay))   / 2, by = Ticker]

# ---- Derived raw intermediates ----
# GrossProfit may already exist, but fill gaps
wide[is.na(GrossProfit) & !is.na(Revenue) & !is.na(COGS),
     GrossProfit := Revenue - COGS]

wide[, EBITDA := fifelse(!is.na(OperatingProfit),
  OperatingProfit + fifelse(!is.na(DepAmort), DepAmort, 0), NA_real_)]

wide[, EBIT := OperatingProfit]  # alias

wide[, NetIncome := fifelse(!is.na(PretaxIncome) & !is.na(TaxExpense),
  PretaxIncome - TaxExpense, NA_real_)]

wide[, WorkingCapital := CurrentAssets - CurrentLiab]

wide[, TotalDebt := fifelse(!is.na(ShortTermBorr), ShortTermBorr, 0) +
                      fifelse(!is.na(LongTermBorr), LongTermBorr, 0)]

wide[, NetDebt := TotalDebt - fifelse(!is.na(CashAndEquiv), CashAndEquiv, 0)]

wide[, FCF := fifelse(!is.na(OperatingCF) & !is.na(InvestCF),
                       OperatingCF + InvestCF, NA_real_)]

wide[, NetInterest := fifelse(!is.na(InterestIncome), InterestIncome, 0) -
                        fifelse(!is.na(InterestExp), InterestExp, 0)]

wide[, NOPAT := fifelse(!is.na(OperatingProfit) & !is.na(TaxExpense) &
                          !is.na(PretaxIncome) & PretaxIncome != 0,
  OperatingProfit * (1 - TaxExpense / PretaxIncome), NA_real_)]

# =========================================================================
# A. PROFITABILITY (15 indicators)
# =========================================================================
wide[, GPA               := .safe_div(GrossProfit, AvgAssets)]
wide[, ROE               := .safe_div(NetIncome, AvgEquity)]
wide[, ROA               := .safe_div(NetIncome, AvgAssets)]
wide[, OPM               := .safe_div(OperatingProfit, Revenue)]
wide[, GrossMargin       := .safe_div(GrossProfit, Revenue)]
wide[, NetMargin          := .safe_div(NetIncome, Revenue)]
wide[, EBITDA_Margin      := .safe_div(EBITDA, Revenue)]
wide[, ROIC := .safe_div(NOPAT,
  fifelse(!is.na(TotalEquity) & !is.na(TotalDebt),
          TotalEquity + TotalDebt - fifelse(!is.na(CashAndEquiv), CashAndEquiv, 0),
          NA_real_))]
wide[, GrossProfit_to_Equity := .safe_div(GrossProfit, AvgEquity)]
wide[, EBIT_to_Assets    := .safe_div(EBIT, AvgAssets)]
wide[, OperatingROA      := .safe_div(OperatingProfit, AvgAssets)]
wide[, PreTaxROA         := .safe_div(PretaxIncome, AvgAssets)]
wide[, OCF_ROA           := .safe_div(OperatingCF, AvgAssets)]
wide[, FCF_Margin        := .safe_div(FCF, Revenue)]
wide[, CashEarningsRatio := .safe_div(OperatingCF, NetIncome)]

# =========================================================================
# B. EFFICIENCY (12 indicators)
# =========================================================================
wide[, AssetTurnover       := .safe_div(Revenue, AvgAssets)]
wide[, EquityTurnover      := .safe_div(Revenue, AvgEquity)]
wide[, InventoryTurnover   := .safe_div(COGS, AvgInventory)]
wide[, ReceivablesTurnover := .safe_div(Revenue, AvgRecv)]
wide[, PayablesTurnover    := .safe_div(COGS, AvgPay)]
wide[, DaysReceivable := fifelse(!is.na(ReceivablesTurnover) & ReceivablesTurnover > 0,
                                  365 / ReceivablesTurnover, NA_real_)]
wide[, DaysInventory := fifelse(!is.na(InventoryTurnover) & InventoryTurnover > 0,
                                 365 / InventoryTurnover, NA_real_)]
wide[, DaysPayable := fifelse(!is.na(PayablesTurnover) & PayablesTurnover > 0,
                               365 / PayablesTurnover, NA_real_)]
wide[, CCC := fifelse(!is.na(DaysReceivable) & !is.na(DaysInventory) & !is.na(DaysPayable),
                       DaysReceivable + DaysInventory - DaysPayable, NA_real_)]
wide[, FixedAssetTurnover := .safe_div(Revenue, TangibleAssets)]
wide[, WCTurnover := fifelse(!is.na(WorkingCapital) & WorkingCapital > 0,
                              Revenue / WorkingCapital, NA_real_)]
wide[, SGAEfficiency := .safe_div(SGAExpense, Revenue)]

# =========================================================================
# C. LEVERAGE & SOLVENCY (18 indicators)
# =========================================================================
wide[, DebtRatio            := .safe_div(TotalLiab, TotalEquity)]
wide[, DebtToAssets         := .safe_div(TotalLiab, TotalAssets)]
wide[, LongTermDebtToEquity := .safe_div(LongTermBorr, TotalEquity)]
wide[, TotalDebtToAssets    := .safe_div(TotalDebt, TotalAssets)]
wide[, NetDebtToEBITDA := fifelse(!is.na(NetDebt) & !is.na(EBITDA) & EBITDA > 0,
                                   NetDebt / EBITDA, NA_real_)]
wide[, NetDebtToAssets      := .safe_div(NetDebt, TotalAssets)]
wide[, EquityMultiplier     := .safe_div(TotalAssets, TotalEquity)]
wide[, InterestBurden       := .safe_div(InterestExp, Revenue)]
wide[, ICR := fifelse(!is.na(InterestExp) & InterestExp > 0 & !is.na(OperatingProfit),
                       OperatingProfit / InterestExp, NA_real_)]
wide[, EBITDA_ICR := fifelse(!is.na(InterestExp) & InterestExp > 0 & !is.na(EBITDA),
                              EBITDA / InterestExp, NA_real_)]
wide[, NetInterestMargin := .safe_div(NetInterest, Revenue)]
wide[, FinancialLeverage := .safe_div(AvgAssets, AvgEquity)]
wide[, ShortTermDebtRatio := fifelse(!is.na(TotalDebt) & TotalDebt > 0,
  fifelse(!is.na(ShortTermBorr), ShortTermBorr, 0) / TotalDebt, NA_real_)]
wide[, LiabToAssets         := .safe_div(TotalLiab, TotalAssets)]
wide[, DebtServiceCoverage := fifelse(!is.na(EBITDA) & !is.na(InterestExp) &
  InterestExp > 0, EBITDA / InterestExp, NA_real_)]
wide[, EquityRatio          := .safe_div(TotalEquity, TotalAssets)]
wide[, NonCurrentLiabRatio  := .safe_div(NonCurrentLiab, TotalAssets)]
wide[, BorrowingDependency  := .safe_div(TotalDebt, TotalAssets)]

# =========================================================================
# D. LIQUIDITY (8 indicators)
# =========================================================================
wide[, CurrentRatio := .safe_div(CurrentAssets, CurrentLiab)]
wide[, QuickRatio := fifelse(!is.na(CurrentAssets) & !is.na(CurrentLiab) & CurrentLiab > 0,
  (CurrentAssets - fifelse(!is.na(Inventory), Inventory, 0)) / CurrentLiab, NA_real_)]
wide[, CashRatio     := .safe_div(CashAndEquiv, CurrentLiab)]
wide[, CashToAssets  := .safe_div(CashAndEquiv, TotalAssets)]
wide[, WCToAssets    := .safe_div(WorkingCapital, TotalAssets)]
wide[, CurrentAssetRatio := .safe_div(CurrentAssets, TotalAssets)]
wide[, DefensiveInterval := fifelse(!is.na(CashAndEquiv) & !is.na(Revenue) & Revenue > 0,
  CashAndEquiv / (Revenue / 365), NA_real_)]
wide[, CashBurnRate := fifelse(!is.na(OperatingCF) & OperatingCF < 0 &
  !is.na(CashAndEquiv) & CashAndEquiv > 0,
  CashAndEquiv / abs(OperatingCF), NA_real_)]

# =========================================================================
# E. CASH FLOW QUALITY (10 indicators)
# =========================================================================
wide[, Accrual := fifelse(!is.na(AvgAssets) & AvgAssets > 0 &
  !is.na(NetIncome) & !is.na(OperatingCF),
  (NetIncome - OperatingCF) / AvgAssets, NA_real_)]
wide[, OCFToRevenue      := .safe_div(OperatingCF, Revenue)]
wide[, OCFToNI           := .safe_div(OperatingCF, NetIncome)]
wide[, FCFToAssets       := .safe_div(FCF, AvgAssets)]
wide[, FCFToEquity       := .safe_div(FCF, AvgEquity)]
wide[, InvestIntensity := fifelse(!is.na(InvestCF) & !is.na(Revenue) & Revenue > 0,
                                   abs(InvestCF) / Revenue, NA_real_)]
wide[, FinancingIntensity := fifelse(!is.na(FinanceCF) & !is.na(TotalAssets) & TotalAssets > 0,
                                      FinanceCF / TotalAssets, NA_real_)]
wide[, ReinvestmentRate := fifelse(!is.na(InvestCF) & !is.na(OperatingCF) & OperatingCF > 0,
                                    abs(InvestCF) / OperatingCF, NA_real_)]
wide[, OCFAccrualGap := fifelse(!is.na(OperatingCF) & !is.na(NetIncome),
                                 OperatingCF - NetIncome, NA_real_)]
wide[, CashGenerationEff := .safe_div(OperatingCF, EBITDA)]

# =========================================================================
# F. ASSET STRUCTURE (8 indicators)
# =========================================================================
wide[, TangibleAssetRatio  := .safe_div(TangibleAssets, TotalAssets)]
wide[, IntangibleAssetRatio := .safe_div(IntangibleAssets, TotalAssets)]
wide[, InventoryToAssets   := .safe_div(Inventory, TotalAssets)]
wide[, ReceivableToAssets  := .safe_div(AccountsRecv, TotalAssets)]
wide[, NonCurrentToTotal   := .safe_div(NonCurrentAssets, TotalAssets)]
wide[, CashToCurrentAssets := .safe_div(CashAndEquiv, CurrentAssets)]
wide[, RetainedToAssets    := .safe_div(RetainedEarnings, TotalAssets)]
wide[, CapitalIntensity    := .safe_div(TangibleAssets, Revenue)]

# =========================================================================
# G. R&D & INNOVATION (4 indicators)
# =========================================================================
wide[, RandDIntensity := .safe_div(RandD, Revenue)]
wide[, RandDToAssets  := .safe_div(RandD, TotalAssets)]
wide[, RandDToOP      := .safe_div(RandD, OperatingProfit)]
wide[, RandDToGP      := .safe_div(RandD, GrossProfit)]

# =========================================================================
# H. TAX & DISTRIBUTION (6 indicators)
# =========================================================================
wide[, EffectiveTaxRate := fifelse(!is.na(TaxExpense) & !is.na(PretaxIncome) & PretaxIncome > 0,
                                   TaxExpense / PretaxIncome, NA_real_)]
wide[, PayoutRatio := fifelse(!is.na(Dividends) & !is.na(NetIncome) & NetIncome > 0,
                               abs(Dividends) / NetIncome, NA_real_)]
wide[, RetentionRatio := fifelse(!is.na(PayoutRatio), 1 - PayoutRatio, NA_real_)]
wide[, DividendToAssets := fifelse(!is.na(Dividends) & !is.na(TotalAssets) & TotalAssets > 0,
                                    abs(Dividends) / TotalAssets, NA_real_)]
wide[, TaxBurden := .safe_div(NetIncome, PretaxIncome)]
wide[, SGR := fifelse(!is.na(ROE) & !is.na(RetentionRatio),
                       ROE * RetentionRatio, ROE)]

# =========================================================================
# I. COST STRUCTURE (5 indicators)
# =========================================================================
wide[, COGSToRevenue    := .safe_div(COGS, Revenue)]
wide[, SGAToGrossProfit := .safe_div(SGAExpense, GrossProfit)]
wide[, DepToAssets      := .safe_div(DepAmort, AvgAssets)]
wide[, DepToRevenue     := .safe_div(DepAmort, Revenue)]
wide[, TotalCostRatio := fifelse(!is.na(Revenue) & Revenue > 0 & !is.na(NetIncome),
                                  1 - NetIncome / Revenue, NA_real_)]

# =========================================================================
# J. DUPONT DECOMPOSITION (3 indicators)
# =========================================================================
wide[, DuPont_NPM := NetMargin]
wide[, DuPont_AT  := AssetTurnover]
wide[, DuPont_EM  := FinancialLeverage]

# =========================================================================
# K. GROWTH (12 indicators, YoY via shift by Ticker)
# =========================================================================
wide[, AssetGrowth := {
  prev <- shift(TotalAssets)
  (TotalAssets - prev) / ((TotalAssets + prev) / 2)
}, by = Ticker]
wide[, RevenueGrowth     := Revenue / shift(Revenue) - 1, by = Ticker]
wide[, GrossProfitGrowth := GrossProfit / shift(GrossProfit) - 1, by = Ticker]
wide[, OPGrowth          := OperatingProfit / shift(OperatingProfit) - 1, by = Ticker]
wide[, NIGrowth          := NetIncome / shift(NetIncome) - 1, by = Ticker]
wide[, EBITDAGrowth      := EBITDA / shift(EBITDA) - 1, by = Ticker]
wide[, EquityGrowth := {
  prev <- shift(TotalEquity)
  (TotalEquity - prev) / ((TotalEquity + prev) / 2)
}, by = Ticker]
wide[, OCFGrowth         := OperatingCF / shift(OperatingCF) - 1, by = Ticker]
wide[, InventoryGrowth   := Inventory / shift(Inventory) - 1, by = Ticker]
wide[, ReceivableGrowth  := AccountsRecv / shift(AccountsRecv) - 1, by = Ticker]
wide[, DebtGrowth        := TotalLiab / shift(TotalLiab) - 1, by = Ticker]
wide[, SGAGrowth         := SGAExpense / shift(SGAExpense) - 1, by = Ticker]

# =========================================================================
# L. YoY RATIO CHANGES (20 Delta_ indicators)
# =========================================================================
ratio_delta_cols <- c("GPA", "ROE", "ROA", "OPM", "GrossMargin", "NetMargin",
                       "EBITDA_Margin", "Accrual", "ICR", "DebtRatio",
                       "CurrentRatio", "CashToAssets", "AssetTurnover",
                       "EquityMultiplier", "OCFToRevenue", "SGAEfficiency",
                       "RandDIntensity", "TangibleAssetRatio", "DebtToAssets",
                       "PayoutRatio")
for (rc in ratio_delta_cols) {
  delta_name <- paste0("Delta_", rc)
  if (rc %in% names(wide)) {
    wide[, (delta_name) := get(rc) - shift(get(rc)), by = Ticker]
  }
}

# =========================================================================
# M. COMPOSITE SCORES
# =========================================================================

# M1. Piotroski F-Score (9 components)
wide[, F_ROA_pos := fifelse(!is.na(ROA) & ROA > 0, 1L, 0L)]
wide[, F_OCF_pos := fifelse(!is.na(OperatingCF) & OperatingCF > 0, 1L, 0L)]
wide[, F_ROA_up  := fifelse(!is.na(Delta_ROA) & Delta_ROA > 0, 1L, 0L)]
wide[, F_Accrual := fifelse(!is.na(Accrual) & Accrual < 0, 1L, 0L)]
wide[, F_LTDebt_down := {
  prev_dr <- shift(DebtToAssets)
  fifelse(!is.na(DebtToAssets) & !is.na(prev_dr) & DebtToAssets < prev_dr, 1L, 0L)
}, by = Ticker]
wide[, F_CR_up := {
  prev_cr <- shift(CurrentRatio)
  fifelse(!is.na(CurrentRatio) & !is.na(prev_cr) & CurrentRatio > prev_cr, 1L, 0L)
}, by = Ticker]
wide[, F_GM_up := fifelse(!is.na(Delta_GrossMargin) & Delta_GrossMargin > 0, 1L, 0L)]
wide[, F_AT_up := fifelse(!is.na(Delta_AssetTurnover) & Delta_AssetTurnover > 0, 1L, 0L)]
wide[, PiotroskiF := F_ROA_pos + F_OCF_pos + F_ROA_up + F_Accrual +
                       F_LTDebt_down + F_CR_up + 1L + F_GM_up + F_AT_up]  # +1 = assume no equity issue

# M2. Altman Z-Score
wide[, AltmanZ := fifelse(
  !is.na(WCToAssets) & !is.na(RetainedToAssets) & !is.na(EBIT_to_Assets) &
    !is.na(TotalEquity) & !is.na(TotalLiab) & TotalLiab > 0 & !is.na(AssetTurnover),
  1.2 * WCToAssets + 1.4 * RetainedToAssets + 3.3 * EBIT_to_Assets +
    0.6 * (TotalEquity / TotalLiab) + 1.0 * AssetTurnover,
  NA_real_)]

# M3. Quality Composite (multi-signal) — cross-sectional within each Period
wide[, QualityScore := fifelse(
  !is.na(GPA) & !is.na(Accrual) & !is.na(AssetGrowth),
  frank(GPA, ties.method = "average") / .N -
    frank(abs(Accrual), ties.method = "average") / .N -
    frank(AssetGrowth, ties.method = "average") / .N,
  NA_real_), by = Period]

cat("  Derived item computation complete.\n")

# ---- 4. Melt to long format ----
cat("[4/5] Melting to long format and merging...\n")

# Define the 140 derived item names (must match DART item names exactly)
derived_items <- c(
  # Intermediates that become items
  "NetIncome", "WorkingCapital", "TotalDebt", "NetDebt", "FCF", "NOPAT", "EBITDA", "EBIT",
  # A. Profitability
  "GPA", "ROE", "ROA", "OPM", "GrossMargin", "NetMargin", "EBITDA_Margin",
  "ROIC", "GrossProfit_to_Equity", "EBIT_to_Assets", "OperatingROA", "PreTaxROA",
  "OCF_ROA", "FCF_Margin", "CashEarningsRatio",
  # B. Efficiency
  "AssetTurnover", "EquityTurnover", "InventoryTurnover", "ReceivablesTurnover",
  "PayablesTurnover", "DaysReceivable", "DaysInventory", "DaysPayable", "CCC",
  "FixedAssetTurnover", "WCTurnover", "SGAEfficiency",
  # C. Leverage
  "DebtRatio", "DebtToAssets", "LongTermDebtToEquity", "TotalDebtToAssets",
  "NetDebtToEBITDA", "NetDebtToAssets", "EquityMultiplier", "InterestBurden",
  "ICR", "EBITDA_ICR", "NetInterestMargin", "FinancialLeverage",
  "ShortTermDebtRatio", "LiabToAssets", "DebtServiceCoverage", "EquityRatio",
  "NonCurrentLiabRatio", "BorrowingDependency",
  # D. Liquidity
  "CurrentRatio", "QuickRatio", "CashRatio", "CashToAssets", "WCToAssets",
  "CurrentAssetRatio", "DefensiveInterval", "CashBurnRate",
  # E. Cash Flow
  "Accrual", "OCFToRevenue", "OCFToNI", "FCFToAssets", "FCFToEquity",
  "InvestIntensity", "FinancingIntensity", "ReinvestmentRate",
  "OCFAccrualGap", "CashGenerationEff",
  # F. Asset Structure
  "TangibleAssetRatio", "IntangibleAssetRatio", "InventoryToAssets",
  "ReceivableToAssets", "NonCurrentToTotal", "CashToCurrentAssets",
  "RetainedToAssets", "CapitalIntensity",
  # G. R&D
  "RandDIntensity", "RandDToAssets", "RandDToOP", "RandDToGP",
  # H. Tax & Distribution
  "EffectiveTaxRate", "PayoutRatio", "RetentionRatio", "DividendToAssets",
  "TaxBurden", "SGR",
  # I. Cost Structure
  "COGSToRevenue", "SGAToGrossProfit", "DepToAssets", "DepToRevenue", "TotalCostRatio",
  # J. DuPont
  "DuPont_NPM", "DuPont_AT", "DuPont_EM",
  # K. Growth
  "AssetGrowth", "RevenueGrowth", "GrossProfitGrowth", "OPGrowth", "NIGrowth",
  "EBITDAGrowth", "EquityGrowth", "OCFGrowth", "InventoryGrowth",
  "ReceivableGrowth", "DebtGrowth", "SGAGrowth",
  # L. Deltas
  "Delta_GPA", "Delta_ROE", "Delta_ROA", "Delta_OPM", "Delta_GrossMargin",
  "Delta_NetMargin", "Delta_EBITDA_Margin", "Delta_Accrual", "Delta_ICR",
  "Delta_DebtRatio", "Delta_CurrentRatio", "Delta_CashToAssets",
  "Delta_AssetTurnover", "Delta_EquityMultiplier", "Delta_OCFToRevenue",
  "Delta_SGAEfficiency", "Delta_RandDIntensity", "Delta_TangibleAssetRatio",
  "Delta_DebtToAssets", "Delta_PayoutRatio",
  # M. Composites & F-Score components
  "F_ROA_pos", "F_OCF_pos", "F_ROA_up", "F_Accrual",
  "F_LTDebt_down", "F_CR_up", "F_GM_up", "F_AT_up",
  "PiotroskiF", "AltmanZ", "QualityScore"
)

# Keep only derived items that actually exist in wide
available_derived <- intersect(derived_items, names(wide))
cat(sprintf("  Available derived items: %d / %d\n", length(available_derived), length(derived_items)))

# ID columns for melt
id_cols <- c("Ticker", "Period", "Period_Date", "Factor_Date")

# Ensure all measure vars are double (avoid integer coercion warning)
for (col in available_derived) {
  if (!is.double(wide[[col]])) {
    wide[, (col) := as.double(get(col))]
  }
}

# Melt to long
derived_long <- melt(wide, id.vars = id_cols, measure.vars = available_derived,
                     variable.name = "Item", value.name = "Value",
                     variable.factor = FALSE)

# Remove NA values
derived_long <- derived_long[!is.na(Value)]

# Add Source column
derived_long[, Source := "xlsx_derived"]

cat(sprintf("  Derived long: %s rows\n", format(nrow(derived_long), big.mark = ",")))

# ---- 5. Rebuild merged from XLSX raw + DART + derived ----
cat("[5/5] Rebuilding merged from source data...\n")

# Strategy: rebuild from scratch to avoid corrupted file reads.
# Load DART and XLSX raw separately, then combine with derived.

# Load DART data
DART_PATH <- file.path(CACHE_DIR, "fundamental_dart.parquet")
if (file.exists(DART_PATH)) {
  dt_dart <- as.data.table(read_parquet(DART_PATH))
  cat(sprintf("  DART loaded: %s rows x %d cols\n", format(nrow(dt_dart), big.mark=","), ncol(dt_dart)))
  # DART: wide -> long
  dart_id <- c("Ticker", "bsns_year", "Factor_Date")
  dart_val <- setdiff(names(dt_dart), dart_id)
  dart_num <- dart_val[sapply(dart_val, function(x) is.numeric(dt_dart[[x]]))]
  # Coerce all to double before melt
  for (col in dart_num) {
    if (!is.double(dt_dart[[col]])) dt_dart[, (col) := as.double(get(col))]
  }
  dart_long <- melt(dt_dart, id.vars = dart_id, measure.vars = dart_num,
                    variable.name = "Item", value.name = "Value",
                    variable.factor = FALSE)
  dart_long <- dart_long[!is.na(Value)]
  dart_long[, Source := "DART"]
  dart_long[, Period := paste0(bsns_year, "12")]
  dart_long[, Period_Date := as.Date(paste0(bsns_year, "-12-31"))]
  dart_long[, bsns_year := NULL]
  cat(sprintf("  DART long: %s rows, %d items\n", format(nrow(dart_long), big.mark=","), uniqueN(dart_long$Item)))
} else {
  dart_long <- data.table(Ticker=character(), Period=character(), Period_Date=as.Date(character()),
                          Factor_Date=as.Date(character()), Item=character(), Value=numeric(), Source=character())
  cat("  DART: NOT FOUND (skipping)\n")
}

# Load XLSX raw data (already loaded as xlsx_long at top)
xlsx_raw <- copy(xlsx_long)
xlsx_raw[, Source := "XLSX"]
cat(sprintf("  XLSX raw: %s rows\n", format(nrow(xlsx_raw), big.mark=",")))

# DART takes priority: remove XLSX-derived rows that overlap with DART
# First, remove derived rows overlapping with DART (Ticker + Item + Factor_Date)
if (nrow(dart_long) > 0) {
  dart_keys <- unique(dart_long[, .(Ticker, Item, Factor_Date)])
  setkeyv(dart_keys, c("Ticker", "Item", "Factor_Date"))
  setkeyv(derived_long, c("Ticker", "Item", "Factor_Date"))
  n_before <- nrow(derived_long)
  derived_long <- derived_long[!dart_keys]
  n_removed <- n_before - nrow(derived_long)
  cat(sprintf("  Removed %s DART-overlapping derived rows\n", format(n_removed, big.mark=",")))
}

# Ensure consistent column set
cols_keep <- c("Ticker", "Period", "Period_Date", "Factor_Date", "Item", "Value", "Source")
xlsx_raw <- xlsx_raw[, ..cols_keep]
dart_out <- dart_long[, ..cols_keep]
derived_out <- derived_long[, ..cols_keep]

# Combine all three sources
merged <- rbindlist(list(xlsx_raw, dart_out, derived_out), use.names = TRUE)

# Deduplicate: same Ticker + Period + Item -> DART > xlsx_derived > XLSX
# Assign priority: DART=1, xlsx_derived=2, XLSX=3
merged[, src_priority := fifelse(Source == "DART", 1L,
                           fifelse(Source == "xlsx_derived", 2L, 3L))]
setorder(merged, Ticker, Period, Item, src_priority)
merged[, rank := seq_len(.N), by = .(Ticker, Period, Item)]
merged <- merged[rank == 1L]
merged[, c("src_priority", "rank") := NULL]
setorder(merged, Ticker, Item, Factor_Date)

cat(sprintf("  Final merged: %s rows | %d unique items | %d tickers\n",
            format(nrow(merged), big.mark = ","),
            uniqueN(merged$Item),
            uniqueN(merged$Ticker)))

# Verify derived items now have pre-2016 coverage
pre2016_derived <- merged[Source == "xlsx_derived" & Factor_Date < as.Date("2016-01-01")]
cat(sprintf("  Pre-2016 derived rows: %s\n", format(nrow(pre2016_derived), big.mark = ",")))
cat(sprintf("  Pre-2016 derived items: %d\n", uniqueN(pre2016_derived$Item)))

# Spot check key items
for (item in c("GPA", "ROE", "ROA", "Accrual", "PiotroskiF", "AltmanZ", "CurrentRatio")) {
  item_rows <- merged[Item == item]
  if (nrow(item_rows) > 0) {
    cat(sprintf("  %-15s: %s~%s (%s rows, %d tickers)\n",
                item,
                as.character(min(item_rows$Factor_Date)),
                as.character(max(item_rows$Factor_Date)),
                format(nrow(item_rows), big.mark = ","),
                uniqueN(item_rows$Ticker)))
  }
}

# Arrow has a thrift metadata size limit for single-parquet files.
# 19M rows exceeds this limit. Strategy:
#
# 1. Save ALL derived items to fundamental_xlsx_derived.parquet (backup/reference)
# 2. For fundamental_merged.parquet (used by factor_db_builder):
#    - Keep XLSX raw (41 items) + DART (181 items, 2016+)
#    - Add ONLY the key derived intermediates that compute_*.R modules actually
#      request from FUND via Item lookup: NetIncome, TotalDebt, NOPAT
#    - This keeps the file under the thrift limit while enabling all factor computation
#
# The compute modules (compute_quality.R, compute_accrual.R, etc.) compute
# GPA/ROE/Accrual etc. themselves from raw items. They only need raw FUND Items
# plus NetIncome (= PretaxIncome - TaxExpense) as a derived intermediate.

DERIVED_PATH <- file.path(CACHE_DIR, "fundamental_xlsx_derived.parquet")

# Save ALL 140 derived items separately (full reference file)
write_parquet(derived_out, DERIVED_PATH,
              compression = "zstd", compression_level = 3L,
              write_statistics = FALSE)
cat(sprintf("\n  Derived (all 140) saved to: %s (%.1f MB)\n",
            DERIVED_PATH, file.info(DERIVED_PATH)$size / 1024^2))

# For the merged file, include only items that compute modules need from FUND:
# - All 41 raw XLSX items (already in xlsx_raw)
# - Key derived intermediates the compute modules request by Item name
compute_needed_derived <- c("NetIncome", "TotalDebt", "NOPAT")
slim_derived <- derived_out[Item %in% compute_needed_derived]
cat(sprintf("  Slim derived (items compute modules need): %s rows\n",
            format(nrow(slim_derived), big.mark = ",")))

# Combine: XLSX raw + DART + slim derived
merged_slim <- rbindlist(list(xlsx_raw, dart_out, slim_derived), use.names = TRUE)

# Deduplicate
merged_slim[, src_priority := fifelse(Source == "DART", 1L,
                                fifelse(Source == "xlsx_derived", 2L, 3L))]
setorder(merged_slim, Ticker, Period, Item, src_priority)
merged_slim[, rank := seq_len(.N), by = .(Ticker, Period, Item)]
merged_slim <- merged_slim[rank == 1L]
merged_slim[, c("src_priority", "rank") := NULL]

cat(sprintf("  Slim merged: %s rows | %d items\n",
            format(nrow(merged_slim), big.mark = ","),
            uniqueN(merged_slim$Item)))

# Save
write_parquet(merged_slim, MERGED_PATH,
              compression = "zstd", compression_level = 5L,
              write_statistics = FALSE)
cat(sprintf("  Saved to: %s (%.1f MB)\n",
            MERGED_PATH, file.info(MERGED_PATH)$size / 1024^2))

cat("\n=== build_fundamental_derived.R COMPLETE ===\n")
cat("End:", as.character(Sys.time()), "\n")
