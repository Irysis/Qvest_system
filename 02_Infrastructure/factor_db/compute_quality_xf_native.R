#==============================================================================
# compute_quality_xf_native.R — DART-native version of 25 unmapped XF factors
#
# Purpose: Fill the DART-side gap for factors only computed by xlsx_factor_calculator
# (DuPont / Leverage·Liquidity / Profitability / Efficiency / Growth divisions /
#  R&D·Investment).
#
# Source: fundamental_merged.parquet (DART, with builder-applied aliases).
#
# Output factor_name uses the same XF_xxx labels as xlsx_factor_calculator —
# builder dedups per (Ticker, Factor_Name) with DART preferred (this module
# is called before xlsx_fund in the module pipeline).
#
# Dohoon mandate (2026-05-23):
#   "DART에 대응 factor 없는 영역이라도 데이터가 있다면 직접 계산해서 채워라"
#==============================================================================

suppressPackageStartupMessages({ library(data.table) })

compute_quality_xf_native <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {

  sig_d <- as.Date(sig_date)
  empty <- function() data.table(Ticker = character(),
                                 Factor_Name = character(),
                                 Raw_Value = numeric())

  if (is.null(FUND) || nrow(FUND) == 0L) return(empty())
  if (!("Item" %in% names(FUND))) return(empty())

  # PIT filter (defensive — builder already pre-slices but verify)
  fp <- FUND[Factor_Date <= sig_d]
  if (nrow(fp) == 0L) return(empty())

  # Pivot to latest value per (Ticker, Item) — most recent ≤ sig_d
  setorder(fp, Ticker, Item, Factor_Date)
  fp_latest <- fp[, .SD[.N], by = .(Ticker, Item), .SDcols = "Value"]

  # Helper: get latest value for a given Item across tickers
  .pull <- function(item) {
    sub <- fp_latest[Item == item, .(Ticker, val = Value)]
    sub
  }

  # Helper: get YoY (curr vs prev period) for an Item
  .pull_yoy <- function(item) {
    sub <- fp[Item == item]
    if (nrow(sub) == 0L) return(NULL)
    sub[, rk := frank(-as.numeric(Factor_Date), ties.method = "dense"), by = Ticker]
    curr <- sub[rk == 1L, .(Ticker, val_c = Value)]
    prev <- sub[rk == 2L, .(Ticker, val_p = Value)]
    m <- merge(curr, prev, by = "Ticker", all = FALSE)
    m[!is.na(val_c) & !is.na(val_p) & abs(val_p) > 1e-8,
       .(Ticker, growth = (val_c - val_p) / abs(val_p))]
  }

  # Helper: emit results entry — only positive nrow
  .emit <- function(results, key, dt) {
    if (!is.null(dt) && nrow(dt) > 0L) {
      results[[key]] <- dt
    }
    results
  }

  results <- list()

  # ── DuPont (XF_DU01~03) ──────────────────────────────────────────────────
  # NetMargin = NetIncome / Revenue
  netmargin <- .pull("NetMargin")
  if (nrow(netmargin) > 0L) {
    results <- .emit(results, "XF_DU01_NetMargin",
      netmargin[!is.na(val), .(Ticker,
                                Factor_Name = "XF_DU01_NetMargin",
                                Raw_Value = val)])
  }
  # AssetTurnover = Revenue / TotalAssets
  at <- .pull("AssetTurnover")
  if (nrow(at) > 0L) {
    results <- .emit(results, "XF_DU02_AssetTurnover",
      at[!is.na(val), .(Ticker,
                         Factor_Name = "XF_DU02_AssetTurnover",
                         Raw_Value = val)])
  }
  # EquityMultiplier = TotalAssets / TotalEquity
  em <- .pull("EquityMultiplier")
  if (nrow(em) > 0L) {
    results <- .emit(results, "XF_DU03_EquityMultiplier",
      em[!is.na(val), .(Ticker,
                         Factor_Name = "XF_DU03_EquityMultiplier",
                         Raw_Value = val)])
  }

  # ── Leverage·Liquidity (XF_LL01~05) ──────────────────────────────────────
  # LL01 DebtToCapital = TotalDebt / (TotalDebt + TotalEquity)
  td <- .pull("TotalDebt"); te <- .pull("TotalEquity")
  if (nrow(td) > 0L && nrow(te) > 0L) {
    m <- merge(td[, .(Ticker, td_v = val)], te[, .(Ticker, te_v = val)],
               by = "Ticker", all = FALSE)
    m <- m[!is.na(td_v) & !is.na(te_v) & (td_v + te_v) > 1e-8]
    if (nrow(m) > 0L) {
      results <- .emit(results, "XF_LL01_DebtToCapital",
        m[, .(Ticker, Factor_Name = "XF_LL01_DebtToCapital",
              Raw_Value = td_v / (td_v + te_v))])
    }
  }
  # LL02 NetDebt = pre-computed
  nd <- .pull("NetDebt")
  if (nrow(nd) > 0L) {
    results <- .emit(results, "XF_LL02_NetDebt",
      nd[!is.na(val), .(Ticker, Factor_Name = "XF_LL02_NetDebt", Raw_Value = val)])
  }
  # LL03 CashRatio = pre-computed
  cr <- .pull("CashRatio")
  if (nrow(cr) > 0L) {
    results <- .emit(results, "XF_LL03_CashRatio",
      cr[!is.na(val), .(Ticker, Factor_Name = "XF_LL03_CashRatio", Raw_Value = val)])
  }
  # LL04 QuickRatio = pre-computed
  qr <- .pull("QuickRatio")
  if (nrow(qr) > 0L) {
    results <- .emit(results, "XF_LL04_QuickRatio",
      qr[!is.na(val), .(Ticker, Factor_Name = "XF_LL04_QuickRatio", Raw_Value = val)])
  }
  # LL05 WorkingCapital = pre-computed (or CurrentAssets - CurrentLiabilities)
  wc <- .pull("WorkingCapital")
  if (nrow(wc) > 0L) {
    results <- .emit(results, "XF_LL05_WorkingCapital",
      wc[!is.na(val), .(Ticker, Factor_Name = "XF_LL05_WorkingCapital", Raw_Value = val)])
  }

  # ── Profitability (XF_PR01~05) ───────────────────────────────────────────
  # PR01 EBITDA_Margin = pre-computed
  em_m <- .pull("EBITDA_Margin")
  if (nrow(em_m) > 0L) {
    results <- .emit(results, "XF_PR01_EBITDA_Margin",
      em_m[!is.na(val), .(Ticker, Factor_Name = "XF_PR01_EBITDA_Margin", Raw_Value = val)])
  }
  # PR02 RetainedEarnings_Ratio = RetainedEarnings / TotalAssets
  re_v <- .pull("RetainedEarnings"); ta_v <- .pull("TotalAssets")
  if (nrow(re_v) > 0L && nrow(ta_v) > 0L) {
    m <- merge(re_v[, .(Ticker, re = val)], ta_v[, .(Ticker, ta = val)],
               by = "Ticker", all = FALSE)
    m <- m[!is.na(re) & !is.na(ta) & ta > 1e-8]
    if (nrow(m) > 0L) {
      results <- .emit(results, "XF_PR02_RetainedEarnings_Ratio",
        m[, .(Ticker, Factor_Name = "XF_PR02_RetainedEarnings_Ratio",
              Raw_Value = re / ta)])
    }
  }
  # PR03 TaxRate = EffectiveTaxRate
  tax <- .pull("EffectiveTaxRate")
  if (nrow(tax) > 0L) {
    results <- .emit(results, "XF_PR03_TaxRate",
      tax[!is.na(val), .(Ticker, Factor_Name = "XF_PR03_TaxRate", Raw_Value = val)])
  }
  # PR04 NetInterestMargin = pre-computed
  nim <- .pull("NetInterestMargin")
  if (nrow(nim) > 0L) {
    results <- .emit(results, "XF_PR04_NetInterestMargin",
      nim[!is.na(val), .(Ticker, Factor_Name = "XF_PR04_NetInterestMargin", Raw_Value = val)])
  }
  # PR05 EBITDA_to_Assets = EBITDA / TotalAssets
  ebitda_v <- .pull("EBITDA")
  if (nrow(ebitda_v) > 0L && nrow(ta_v) > 0L) {
    m <- merge(ebitda_v[, .(Ticker, eb = val)], ta_v[, .(Ticker, ta = val)],
               by = "Ticker", all = FALSE)
    m <- m[!is.na(eb) & !is.na(ta) & ta > 1e-8]
    if (nrow(m) > 0L) {
      results <- .emit(results, "XF_PR05_EBITDA_to_Assets",
        m[, .(Ticker, Factor_Name = "XF_PR05_EBITDA_to_Assets",
              Raw_Value = eb / ta)])
    }
  }

  # ── Efficiency (XF_EF01~04) ──────────────────────────────────────────────
  # EF01 InventoryTurnover = Revenue / Inventories (Inventories alias from builder)
  inv_v <- .pull("Inventories"); rev_v <- .pull("Revenue")
  if (nrow(inv_v) > 0L && nrow(rev_v) > 0L) {
    m <- merge(rev_v[, .(Ticker, rv = val)], inv_v[, .(Ticker, iv = val)],
               by = "Ticker", all = FALSE)
    m <- m[!is.na(rv) & !is.na(iv) & iv > 1e-8]
    if (nrow(m) > 0L) {
      results <- .emit(results, "XF_EF01_InventoryTurnover",
        m[, .(Ticker, Factor_Name = "XF_EF01_InventoryTurnover", Raw_Value = rv / iv)])
    }
  }
  # EF02 DaysPayable = pre-computed
  dp <- .pull("DaysPayable")
  if (nrow(dp) > 0L) {
    results <- .emit(results, "XF_EF02_DaysPayable",
      dp[!is.na(val), .(Ticker, Factor_Name = "XF_EF02_DaysPayable", Raw_Value = val)])
  }
  # EF03 DaysReceivable = pre-computed
  dr <- .pull("DaysReceivable")
  if (nrow(dr) > 0L) {
    results <- .emit(results, "XF_EF03_DaysReceivable",
      dr[!is.na(val), .(Ticker, Factor_Name = "XF_EF03_DaysReceivable", Raw_Value = val)])
  }
  # EF04 CCC = pre-computed
  ccc <- .pull("CCC")
  if (nrow(ccc) > 0L) {
    results <- .emit(results, "XF_EF04_CCC",
      ccc[!is.na(val), .(Ticker, Factor_Name = "XF_EF04_CCC", Raw_Value = val)])
  }

  # ── Growth Divisions (XF_GD01~04) ────────────────────────────────────────
  # GD01 GrossProfit_Growth = YoY GrossProfit
  gd01 <- .pull_yoy("GrossProfit")
  if (!is.null(gd01) && nrow(gd01) > 0L) {
    results <- .emit(results, "XF_GD01_GrossProfit_Growth",
      gd01[!is.na(growth) & is.finite(growth),
            .(Ticker, Factor_Name = "XF_GD01_GrossProfit_Growth", Raw_Value = growth)])
  }
  # GD02 OpProfit_Growth = pre-computed (OPGrowth)
  opg <- .pull("OPGrowth")
  if (nrow(opg) > 0L) {
    results <- .emit(results, "XF_GD02_OpProfit_Growth",
      opg[!is.na(val), .(Ticker, Factor_Name = "XF_GD02_OpProfit_Growth", Raw_Value = val)])
  }
  # GD03 OCF_Growth = pre-computed (OCFGrowth)
  ocg <- .pull("OCFGrowth")
  if (nrow(ocg) > 0L) {
    results <- .emit(results, "XF_GD03_OCF_Growth",
      ocg[!is.na(val), .(Ticker, Factor_Name = "XF_GD03_OCF_Growth", Raw_Value = val)])
  }
  # GD04 Dividend_Growth = YoY Dividends
  gd04 <- .pull_yoy("Dividends")
  if (!is.null(gd04) && nrow(gd04) > 0L) {
    results <- .emit(results, "XF_GD04_Dividend_Growth",
      gd04[!is.na(growth) & is.finite(growth),
            .(Ticker, Factor_Name = "XF_GD04_Dividend_Growth", Raw_Value = growth)])
  }

  # ── R&D & Investment (XF_RI01~03) ────────────────────────────────────────
  # RI01 RnD_to_Revenue = RandDIntensity (pre-computed = RandD / Revenue)
  rdi <- .pull("RandDIntensity")
  if (nrow(rdi) > 0L) {
    results <- .emit(results, "XF_RI01_RnD_to_Revenue",
      rdi[!is.na(val), .(Ticker, Factor_Name = "XF_RI01_RnD_to_Revenue", Raw_Value = val)])
  }
  # RI02 CapEx_proxy = |InvestCF| / TotalAssets (proxy)
  ic <- .pull("InvestCF")
  if (nrow(ic) > 0L && nrow(ta_v) > 0L) {
    m <- merge(ic[, .(Ticker, icf = val)], ta_v[, .(Ticker, ta = val)],
               by = "Ticker", all = FALSE)
    m <- m[!is.na(icf) & !is.na(ta) & ta > 1e-8]
    if (nrow(m) > 0L) {
      results <- .emit(results, "XF_RI02_CapEx_proxy",
        m[, .(Ticker, Factor_Name = "XF_RI02_CapEx_proxy",
              Raw_Value = abs(icf) / ta)])
    }
  }
  # RI03 SGA_to_Revenue = SGAEfficiency (pre-computed)
  sga <- .pull("SGAEfficiency")
  if (nrow(sga) > 0L) {
    results <- .emit(results, "XF_RI03_SGA_to_Revenue",
      sga[!is.na(val), .(Ticker, Factor_Name = "XF_RI03_SGA_to_Revenue", Raw_Value = val)])
  }

  # ── Combine ──────────────────────────────────────────────────────────────
  if (length(results) == 0L) return(empty())
  rbindlist(results, use.names = TRUE)
}

cat("[factor_db] compute_quality_xf_native.R loaded (25 DART-native versions of XF_DU/LL/PR/EF/GD/RI)\n")
