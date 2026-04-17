#==============================================================================
# compute_growth.R -- Growth + Investment + Market Factor Module
#   GR01~GR07 (Growth), IN01~IN06 (Investment), MK01 (Market)
#
# compute_growth(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL)
#   RAWDATA:    data.table(Date, Ticker, Close, Ret, Vol, Size, Sector, BM_Ret)
#   sig_date:   signal date (Date class)
#   FUND:       fundamentals long format (Ticker, Item, Value, Factor_Date)
#   CONSENSUS:  consensus data (for forward growth estimates)
#
# Returns: data.table(Ticker, Factor_Name, Raw_Value)
#
# PIT: Factor_Date <= sig_date. Expanding window. No future data.
#      C1-C11 compliant.
#
# References:
#   Cooper Gulen Schill (2008) asset growth, Titman Wei Xie (2004) investment,
#   Fama French (2015) CMA, Asness QMJ Growth, Bradshaw Richardson Sloan (2006)
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

compute_growth <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {

  sig_d <- as.Date(sig_date)
  results <- list()

  # ---- Helper: safe divide ----
  .sdiv <- function(num, den) {
    fifelse(!is.na(num) & !is.na(den) & abs(den) > 1e-8, num / den, NA_real_)
  }

  # ---- Helper: safe column access ----
  .sc <- function(dt, col) {
    if (col %in% names(dt)) dt[[col]] else rep(NA_real_, nrow(dt))
  }

  # ---- Detect FUND format ----
  is_long <- FALSE
  if (!is.null(FUND) && nrow(FUND) > 0L) {
    is_long <- "Item" %in% names(FUND)
  }

  # ---- Helper: get two most recent periods ----
  .get_two_periods <- function(fund_dt, items_needed) {
    if (is.null(fund_dt) || nrow(fund_dt) == 0L) return(NULL)
    fd <- copy(fund_dt)
    if ("Factor_Date" %in% names(fd)) {
      fd <- fd[Factor_Date <= sig_d]
    } else if ("Date" %in% names(fd)) {
      fd <- fd[Date <= sig_d]
      setnames(fd, "Date", "Factor_Date")
    }
    if (nrow(fd) == 0L) return(NULL)

    if (is_long) {
      sub <- fd[Item %in% items_needed]
      if (nrow(sub) == 0L) return(NULL)
      sub[, date_rank := frank(-as.numeric(Factor_Date)), by = .(Ticker, Item)]
      curr <- sub[date_rank == 1, .(Ticker, Item, V_curr = Value)]
      prev <- sub[date_rank == 2, .(Ticker, Item, V_prev = Value)]
      w_curr <- dcast(curr, Ticker ~ Item, value.var = "V_curr")
      w_prev <- dcast(prev, Ticker ~ Item, value.var = "V_prev")
      return(list(curr = w_curr, prev = w_prev))
    } else {
      fd[, date_rank := frank(-as.numeric(Factor_Date)), by = Ticker]
      w_curr <- fd[date_rank == 1]
      w_prev <- fd[date_rank == 2]
      return(list(curr = w_curr, prev = w_prev))
    }
  }

  # ---- Helper: get multiple historical periods ----
  .get_multi_periods <- function(fund_dt, items_needed, n_periods = 5L) {
    if (is.null(fund_dt) || nrow(fund_dt) == 0L) return(NULL)
    fd <- copy(fund_dt)
    if ("Factor_Date" %in% names(fd)) {
      fd <- fd[Factor_Date <= sig_d]
    } else if ("Date" %in% names(fd)) {
      fd <- fd[Date <= sig_d]
      setnames(fd, "Date", "Factor_Date")
    }
    if (nrow(fd) == 0L) return(NULL)

    if (is_long) {
      sub <- fd[Item %in% items_needed]
      if (nrow(sub) == 0L) return(NULL)
      sub[, date_rank := frank(-as.numeric(Factor_Date)), by = .(Ticker, Item)]
      sub <- sub[date_rank <= n_periods]
      return(sub)
    } else {
      fd[, date_rank := frank(-as.numeric(Factor_Date)), by = Ticker]
      fd <- fd[date_rank <= n_periods]
      return(fd)
    }
  }

  # ---- Helper: get latest PIT wide ----
  .get_latest_wide <- function(fund_dt, items_needed) {
    if (is.null(fund_dt) || nrow(fund_dt) == 0L) return(NULL)
    fd <- copy(fund_dt)
    if ("Factor_Date" %in% names(fd)) {
      fd <- fd[Factor_Date <= sig_d]
    } else if ("Date" %in% names(fd)) {
      fd <- fd[Date <= sig_d]
      setnames(fd, "Date", "Factor_Date")
    }
    if (nrow(fd) == 0L) return(NULL)

    if (is_long) {
      sub <- fd[Item %in% items_needed]
      if (nrow(sub) == 0L) return(NULL)
      setorder(sub, Ticker, Item, Factor_Date)
      latest <- sub[, .SD[.N], by = .(Ticker, Item)]
      dcast(latest, Ticker ~ Item, value.var = "Value")
    } else {
      setorder(fd, Ticker, Factor_Date)
      fd[, .SD[.N], by = Ticker]
    }
  }

  # ==========================================================================
  # GROWTH FACTORS (GR01~GR07)
  # ==========================================================================

  if (!is.null(FUND) && nrow(FUND) > 0L) {

    # ---- GR01: Revenue Growth (YoY) ----
    items_rev <- c("Revenue", "TotalAssets")
    tp_rev <- .get_two_periods(FUND, items_rev)
    if (!is.null(tp_rev)) {
      m <- merge(tp_rev$curr, tp_rev$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
      if (nrow(m) > 0L) {
        rev_c <- .sc(m, "Revenue")
        rev_p <- .sc(m, "Revenue_p")
        m[, GR01 := .sdiv(rev_c - rev_p, abs(rev_p))]
        results[["GR01"]] <- m[!is.na(GR01) & is.finite(GR01),
                                .(Ticker, Factor_Name = "GR01_Revenue_Growth", Raw_Value = GR01)]
      }
    }

    # ---- GR02: Earnings Growth (YoY, NI) ----
    items_ni <- c("NetIncome")
    tp_ni <- .get_two_periods(FUND, items_ni)
    if (!is.null(tp_ni)) {
      m <- merge(tp_ni$curr, tp_ni$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
      if (nrow(m) > 0L) {
        ni_c <- .sc(m, "NetIncome")
        ni_p <- .sc(m, "NetIncome_p")
        m[, GR02 := .sdiv(ni_c - ni_p, pmax(abs(ni_p), 1e-8))]
        results[["GR02"]] <- m[!is.na(GR02) & is.finite(GR02),
                                .(Ticker, Factor_Name = "GR02_Earnings_Growth", Raw_Value = GR02)]
      }
    }

    # ---- GR03: Asset Growth (Cooper Gulen Schill 2008) ----
    items_ag <- c("TotalAssets")
    tp_ag <- .get_two_periods(FUND, items_ag)
    if (!is.null(tp_ag)) {
      m <- merge(tp_ag$curr, tp_ag$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
      if (nrow(m) > 0L) {
        ta_c <- .sc(m, "TotalAssets")
        ta_p <- .sc(m, "TotalAssets_p")
        # Negate: low asset growth = better (conservative investment)
        m[, GR03 := .sdiv(-(ta_c - ta_p), abs(ta_p))]
        results[["GR03"]] <- m[!is.na(GR03) & is.finite(GR03),
                                .(Ticker, Factor_Name = "GR03_Asset_Growth", Raw_Value = GR03)]
      }
    }

    # ---- GR04: GPA Growth (Gross Profit / Assets, 5Y growth) ----
    items_gpa <- c("GrossProfit", "TotalAssets")
    multi_gpa <- .get_multi_periods(FUND, items_gpa, 5L)
    if (!is.null(multi_gpa) && nrow(multi_gpa) > 0L) {
      if (is_long) {
        w_gpa <- dcast(multi_gpa, Ticker + Factor_Date + date_rank ~ Item, value.var = "Value")
      } else {
        w_gpa <- multi_gpa
      }
      if (all(c("GrossProfit", "TotalAssets") %in% names(w_gpa))) {
        w_gpa <- w_gpa[!is.na(GrossProfit) & !is.na(TotalAssets) & TotalAssets != 0]
        w_gpa[, gpa := GrossProfit / TotalAssets]
        gr04 <- w_gpa[, {
          if (.N >= 3L) {
            newest <- gpa[which.min(date_rank)]
            oldest <- gpa[which.max(date_rank)]
            if (!is.na(oldest) && abs(oldest) > 1e-8) {
              .(GR04 = (newest - oldest) / abs(oldest))
            } else {
              .(GR04 = NA_real_)
            }
          } else {
            .(GR04 = NA_real_)
          }
        }, by = Ticker]
        gr04 <- gr04[!is.na(GR04) & is.finite(GR04)]
        if (nrow(gr04) > 0L) {
          results[["GR04"]] <- gr04[, .(Ticker, Factor_Name = "GR04_GPA_Growth", Raw_Value = GR04)]
        }
      }
    }

    # ---- GR05: ROE Growth (5Y growth) ----
    items_roe <- c("NetIncome", "TotalEquity")
    multi_roe <- .get_multi_periods(FUND, items_roe, 5L)
    if (!is.null(multi_roe) && nrow(multi_roe) > 0L) {
      if (is_long) {
        w_roe <- dcast(multi_roe, Ticker + Factor_Date + date_rank ~ Item, value.var = "Value")
      } else {
        w_roe <- multi_roe
      }
      if (all(c("NetIncome", "TotalEquity") %in% names(w_roe))) {
        w_roe <- w_roe[!is.na(NetIncome) & !is.na(TotalEquity) & TotalEquity != 0]
        w_roe[, roe := NetIncome / TotalEquity]
        gr05 <- w_roe[, {
          if (.N >= 3L) {
            newest <- roe[which.min(date_rank)]
            oldest <- roe[which.max(date_rank)]
            if (!is.na(oldest) && abs(oldest) > 1e-8) {
              .(GR05 = (newest - oldest) / abs(oldest))
            } else {
              .(GR05 = NA_real_)
            }
          } else {
            .(GR05 = NA_real_)
          }
        }, by = Ticker]
        gr05 <- gr05[!is.na(GR05) & is.finite(GR05)]
        if (nrow(gr05) > 0L) {
          results[["GR05"]] <- gr05[, .(Ticker, Factor_Name = "GR05_ROE_Growth", Raw_Value = GR05)]
        }
      }
    }

    # ---- GR06: Operating CF Growth (YoY) ----
    items_cf <- c("OperatingCF")
    tp_cf <- .get_two_periods(FUND, items_cf)
    if (!is.null(tp_cf)) {
      m <- merge(tp_cf$curr, tp_cf$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
      if (nrow(m) > 0L) {
        cf_c <- .sc(m, "OperatingCF")
        cf_p <- .sc(m, "OperatingCF_p")
        m[, GR06 := .sdiv(cf_c - cf_p, pmax(abs(cf_p), 1e-8))]
        results[["GR06"]] <- m[!is.na(GR06) & is.finite(GR06),
                                .(Ticker, Factor_Name = "GR06_OCF_Growth", Raw_Value = GR06)]
      }
    }

    # ---- GR07: Composite Growth Score = mean(z(GR01..GR06)) ----
    growth_names <- paste0("GR0", 1:6)
    avail_growth <- intersect(growth_names, names(results))
    if (length(avail_growth) >= 2L) {
      parts <- rbindlist(results[avail_growth], use.names = TRUE)
      if (nrow(parts) > 0L) {
        parts[, z_val := {
          m <- mean(Raw_Value, na.rm = TRUE)
          s <- sd(Raw_Value, na.rm = TRUE)
          if (is.na(s) || s < 1e-8) NA_real_ else (Raw_Value - m) / s
        }, by = Factor_Name]
        comp <- parts[!is.na(z_val), .(n_comp = .N, z_mean = mean(z_val, na.rm = TRUE)), by = Ticker]
        comp <- comp[n_comp >= 2L]
        if (nrow(comp) > 0L) {
          results[["GR07"]] <- comp[, .(Ticker, Factor_Name = "GR07_Composite_Growth", Raw_Value = z_mean)]
        }
      }
    }

    # ==========================================================================
    # INVESTMENT FACTORS (IN01~IN06)
    # ==========================================================================

    # ---- IN01: CapEx / Assets (Titman Wei Xie 2004) ----
    # Negate: low investment = conservative = better (CMA direction)
    items_capex <- c("InvestCF", "TotalAssets")
    fw_capex <- .get_latest_wide(FUND, items_capex)
    if (!is.null(fw_capex)) {
      inv_cf <- .sc(fw_capex, "InvestCF")
      ta <- .sc(fw_capex, "TotalAssets")
      # InvestCF is typically negative for capex; negate to get positive capex
      fw_capex[, IN01 := .sdiv(-(-inv_cf), ta)]  # = InvestCF / TA, negate: low capex = better
      # Actually: -CapEx/TA = InvestCF/TA (since InvestCF ~ -CapEx)
      fw_capex[, IN01 := .sdiv(inv_cf, ta)]  # InvestCF/TA: negative = high capex = bad
      results[["IN01"]] <- fw_capex[!is.na(IN01), .(Ticker, Factor_Name = "IN01_CapEx_to_Assets", Raw_Value = IN01)]
    }

    # ---- IN02: CapEx / Revenue ----
    items_cr <- c("InvestCF", "Revenue")
    fw_cr <- .get_latest_wide(FUND, items_cr)
    if (!is.null(fw_cr)) {
      inv_cf <- .sc(fw_cr, "InvestCF")
      rev <- .sc(fw_cr, "Revenue")
      fw_cr[, IN02 := .sdiv(inv_cf, rev)]  # negative = high capex relative to revenue
      results[["IN02"]] <- fw_cr[!is.na(IN02), .(Ticker, Factor_Name = "IN02_CapEx_to_Revenue", Raw_Value = IN02)]
    }

    # ---- IN03: R&D to Market (R&D intensity) ----
    # DATA_NEEDED: R&D expense item. Use approximation if available.
    items_rd <- c("RnDExpense")
    fw_rd <- .get_latest_wide(FUND, items_rd)
    if (!is.null(fw_rd) && "RnDExpense" %in% names(fw_rd)) {
      snap <- RAWDATA[Date == sig_d & !is.na(Close) & Close > 0, .(Ticker, MarketCap = Close * Size)]
      snap <- snap[MarketCap > 0]
      rd_m <- merge(fw_rd, snap, by = "Ticker", all = FALSE)
      if (nrow(rd_m) > 0L) {
        rd_m[, IN03 := .sdiv(RnDExpense, MarketCap)]
        results[["IN03"]] <- rd_m[!is.na(IN03), .(Ticker, Factor_Name = "IN03_RD_to_Market", Raw_Value = IN03)]
      }
    } else {
      # DATA_NEEDED: RnDExpense for IN03_RD_to_Market
    }

    # ---- IN04: Net Equity Issuance (Bradshaw Richardson Sloan 2006) ----
    # (Sale of Stock - Purchase of Stock) / TA. Negate: buyback = good
    items_ei <- c("SharesOutstanding", "TotalAssets")
    tp_ei <- .get_two_periods(FUND, items_ei)
    if (!is.null(tp_ei)) {
      m <- merge(tp_ei$curr, tp_ei$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
      if (nrow(m) > 0L) {
        sh_c <- .sc(m, "SharesOutstanding")
        sh_p <- .sc(m, "SharesOutstanding_p")
        ta   <- .sc(m, "TotalAssets")
        # Net issuance proxy: change in shares outstanding / shares outstanding
        m[, IN04 := .sdiv(-(sh_c - sh_p), pmax(abs(sh_p), 1e-8))]
        # Negate: decrease in shares (buyback) = positive = good
        results[["IN04"]] <- m[!is.na(IN04) & is.finite(IN04),
                                .(Ticker, Factor_Name = "IN04_Net_Equity_Issuance", Raw_Value = IN04)]
      }
    }

    # ---- IN05: Net Debt Issuance ----
    # Change in total debt / TA. Negate: deleveraging = good
    items_di <- c("ShortTermBorr", "LongTermBorr", "TotalAssets")
    tp_di <- .get_two_periods(FUND, items_di)
    if (!is.null(tp_di)) {
      m <- merge(tp_di$curr, tp_di$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
      if (nrow(m) > 0L) {
        .zna <- function(x) { x[is.na(x)] <- 0; x }
        debt_c <- .zna(.sc(m, "ShortTermBorr")) + .zna(.sc(m, "LongTermBorr"))
        debt_p <- .zna(.sc(m, "ShortTermBorr_p")) + .zna(.sc(m, "LongTermBorr_p"))
        ta     <- .sc(m, "TotalAssets")
        m[, IN05 := .sdiv(-(debt_c - debt_p), ta)]  # deleveraging = positive
        results[["IN05"]] <- m[!is.na(IN05), .(Ticker, Factor_Name = "IN05_Net_Debt_Issuance", Raw_Value = IN05)]
      }
    }

    # ---- IN06: Investment to Assets (dPPE + dInventories / lag TA) ----
    # Titman Wei Xie (2004), Xing (2008). Negate: low investment = better
    items_ia <- c("PPE", "Inventories", "TotalAssets")
    tp_ia <- .get_two_periods(FUND, items_ia)
    if (!is.null(tp_ia)) {
      m <- merge(tp_ia$curr, tp_ia$prev, by = "Ticker", suffixes = c("", "_p"), all = FALSE)
      if (nrow(m) > 0L) {
        .zna <- function(x) { x[is.na(x)] <- 0; x }
        d_ppe <- .zna(.sc(m, "PPE")) - .zna(.sc(m, "PPE_p"))
        d_inv <- .zna(.sc(m, "Inventories")) - .zna(.sc(m, "Inventories_p"))
        lag_ta <- .sc(m, "TotalAssets_p")
        m[, IN06 := .sdiv(-(d_ppe + d_inv), lag_ta)]  # negate: low investment = better
        results[["IN06"]] <- m[!is.na(IN06), .(Ticker, Factor_Name = "IN06_Investment_to_Assets", Raw_Value = IN06)]
      }
    }
  }

  # ==========================================================================
  # MARKET FACTOR (MK01)
  # ==========================================================================

  # ---- MK01: CAPM Beta (standalone, 252d) ----
  rd_mkt <- copy(RAWDATA)
  rd_mkt[, Date := as.Date(Date)]
  lookback_start <- sig_d - 365
  rd_mkt <- rd_mkt[Date <= sig_d & Date >= lookback_start]
  setorder(rd_mkt, Ticker, Date)

  if (nrow(rd_mkt) > 0L && all(c("Ret", "BM_Ret") %in% names(rd_mkt))) {
    mk01 <- rd_mkt[!is.na(Ret) & !is.na(BM_Ret), {
      if (.N >= 120L) {
        fit <- tryCatch(lm.fit(cbind(1, BM_Ret), Ret), error = function(e) NULL)
        if (!is.null(fit)) {
          .(Factor_Name = "MK01_CAPM_Beta", Raw_Value = fit$coefficients[2])
        } else {
          .(Factor_Name = "MK01_CAPM_Beta", Raw_Value = NA_real_)
        }
      } else {
        .(Factor_Name = "MK01_CAPM_Beta", Raw_Value = NA_real_)
      }
    }, by = Ticker]
    mk01 <- mk01[!is.na(Raw_Value)]
    if (nrow(mk01) > 0L) results[["MK01"]] <- mk01
  }

  # ---- Combine all ----
  if (length(results) == 0L) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }
  out <- rbindlist(results, use.names = TRUE, fill = TRUE)
  out[, .(Ticker, Factor_Name, Raw_Value)]
}

cat("[factor_db] compute_growth.R loaded (GR01~GR07, IN01~IN06, MK01)\n")
