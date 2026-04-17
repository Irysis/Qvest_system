#==============================================================================
# compute_risk.R -- Risk Factor Module (R01~R19)
#
# compute_risk(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL)
#   RAWDATA:    data.table(Date, Ticker, Close, Ret, Vol, Size, Sector, BM_Ret,
#                          Open, High, Low)
#   sig_date:   signal date (Date class)
#   FUND:       fundamentals (for leverage factors)
#   CONSENSUS:  not used (signature kept for consistency)
#
# Returns: data.table(Ticker, Factor_Name, Raw_Value)
#
# PIT: Date <= sig_date, expanding/rolling lookback. No future data.
#      C1-C11 compliant.
#
# References:
#   Ang Chen Xing (2006) co-skewness, VaR/CVaR, Bhandari (1988) leverage,
#   Chen Hong Stein (2001) crash risk NCSKEW/DUVOL
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

compute_risk <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {

  sig_d <- as.Date(sig_date)
  results <- list()

  # ---- Price data prep (PIT: Date <= sig_date, 252d lookback) ----
  rd <- copy(RAWDATA)
  rd[, Date := as.Date(Date)]
  lookback_start <- sig_d - 365  # ~252 trading days
  rd <- rd[Date <= sig_d & Date >= lookback_start]

  if (nrow(rd) == 0L) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  if (!all(c("Ticker", "Date", "Ret", "BM_Ret") %in% names(rd))) {
    warning("[compute_risk] Missing required columns: Ticker, Date, Ret, BM_Ret")
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  setkey(rd, Ticker, Date)

  MIN_OBS     <- 120L
  MIN_OBS_VAR <- 60L

  tickers <- unique(rd$Ticker)

  # ---- BM daily returns for market-relative calculations ----
  bm_daily <- unique(rd[, .(Date, BM_Ret)])
  setorder(bm_daily, Date)

  # ---- Helper: safe divide ----
  .sdiv <- function(num, den) {
    fifelse(!is.na(num) & !is.na(den) & abs(den) > 1e-8, num / den, NA_real_)
  }

  # ==========================================================================
  # Per-ticker calculations (R01~R16) — vectorized by=Ticker (replaces lapply)
  # ==========================================================================
  risk_dt <- rd[!is.na(Ret), {
    n <- .N
    rets    <- Ret
    bm_rets <- BM_Ret

    r01 <- r02 <- r03 <- r04 <- r05 <- r06 <- r07 <- r08 <- NA_real_
    r09 <- r10 <- r11 <- r12 <- r13 <- r14 <- r15 <- r16 <- NA_real_

    if (n >= MIN_OBS_VAR) {
      # R01/R02: Historical VaR
      var_95 <- quantile(rets, probs = 0.05, na.rm = TRUE)
      var_99 <- quantile(rets, probs = 0.01, na.rm = TRUE)
      r01 <- -var_95
      r02 <- -var_99

      # R03/R04: CVaR
      bv95 <- rets[rets <= var_95]
      if (length(bv95) >= 3L) r03 <- -mean(bv95, na.rm = TRUE)
      bv99 <- rets[rets <= var_99]
      if (length(bv99) >= 2L) r04 <- -mean(bv99, na.rm = TRUE)

      # R05: Tail Risk
      mean_r <- mean(rets, na.rm = TRUE)
      if (!is.na(mean_r) && abs(mean_r) > 1e-8) r05 <- -abs(var_95 / mean_r)

      # R06: MDD (from cumulative returns, Close may not be in rd)
      cum_ret_p <- cumprod(1 + pmax(rets, -0.99))
      mdd <- min((cum_ret_p - cummax(cum_ret_p)) / cummax(cum_ret_p), na.rm = TRUE)
      if (is.finite(mdd)) r06 <- -abs(mdd)

      # R07/R08: Downside Dev / Semi-Variance
      neg_r <- rets[rets < 0]
      if (length(neg_r) >= 10L) {
        dd_val <- sqrt(mean(neg_r^2, na.rm = TRUE))
        r07 <- -dd_val
        r08 <- -var(neg_r, na.rm = TRUE)
        # R15: Sortino
        if (!is.na(mean_r) && dd_val > 1e-8) r15 <- mean_r / dd_val
      }

      # R09~R14: CAPM-residual based (single lm.fit for R09-R14)
      if (n >= MIN_OBS) {
        ok <- !is.na(rets) & !is.na(bm_rets)
        if (sum(ok) >= MIN_OBS) {
          r_ok <- rets[ok]; b_ok <- bm_rets[ok]
          fit <- tryCatch(lm.fit(cbind(1, b_ok), r_ok), error = function(e) NULL)
          if (!is.null(fit)) {
            e_i <- r_ok - mean(r_ok); e_m <- b_ok - mean(b_ok)
            vi <- var(e_i, na.rm=TRUE); vm <- var(e_m, na.rm=TRUE)
            # R09: Coskewness
            if (!is.na(vi) && !is.na(vm) && vi > 0 && vm > 0) {
              num9 <- mean(e_i * e_m^2, na.rm=TRUE)
              den9 <- sqrt(vi) * vm
              if (den9 > 1e-12) r09 <- num9 / den9
              # R10: Cokurtosis
              num10 <- mean(e_i * e_m^3, na.rm=TRUE)
              den10 <- sqrt(vi) * vm^(3/2)
              if (den10 > 1e-12) r10 <- -num10 / den10
            }
            # R11/R12: Systematic/Idiosyncratic Risk
            ss_res <- sum(fit$residuals^2)
            ss_tot <- sum((r_ok - mean(r_ok))^2)
            if (ss_tot > 1e-12) r11 <- -(1 - ss_res / ss_tot)
            r12 <- -sd(fit$residuals, na.rm = TRUE)
            # R13: NCSKEW
            e_res <- fit$residuals; nn <- length(e_res)
            s2 <- sum(e_res^2); s3 <- sum(e_res^3)
            if (s2 > 1e-12)
              r13 <- -( -(nn * (nn-1)^1.5 * s3) / ((nn-1) * (nn-2) * s2^1.5) )
            # R14: DUVOL
            up_e <- e_res[e_res > 0]; dn_e <- e_res[e_res <= 0]
            n_u <- length(up_e); n_d <- length(dn_e)
            if (n_u >= 10L && n_d >= 10L && sum(up_e^2) > 1e-12) {
              r14 <- -log(((n_u-1) * sum(dn_e^2)) / ((n_d-1) * sum(up_e^2)))
            }
          }
        }
      }

      # R16: Calmar
      if (!is.na(r06) && abs(r06) > 1e-8)
        r16 <- (mean_r * 252) / abs(r06)
    }
    list(R01=r01, R02=r02, R03=r03, R04=r04, R05=r05, R06=r06,
         R07=r07, R08=r08, R09=r09, R10=r10, R11=r11, R12=r12,
         R13=r13, R14=r14, R15=r15, R16=r16)
  }, by = Ticker]

  # Unpack risk_dt into results
  .add_r <- function(col, fname) {
    sub <- risk_dt[!is.na(get(col)), .(Ticker, Factor_Name=fname, Raw_Value=get(col))]
    if (nrow(sub) > 0) results[[fname]] <<- sub
  }
  .add_r("R01","R01_VaR_95"); .add_r("R02","R02_VaR_99")
  .add_r("R03","R03_CVaR_95"); .add_r("R04","R04_CVaR_99")
  .add_r("R05","R05_Tail_Risk"); .add_r("R06","R06_MDD")
  .add_r("R07","R07_Downside_Dev"); .add_r("R08","R08_Semi_Variance")
  .add_r("R09","R09_Coskewness"); .add_r("R10","R10_Cokurtosis")
  .add_r("R11","R11_Systematic_Risk"); .add_r("R12","R12_Idiosyncratic_Risk")
  .add_r("R13","R13_NCSKEW"); .add_r("R14","R14_DUVOL")
  .add_r("R15","R15_Sortino"); .add_r("R16","R16_Calmar")

  # ==========================================================================
  # R17: Market Leverage = Total Debt / MarketCap (Bhandari 1988)
  # ==========================================================================
  if (!is.null(FUND) && nrow(FUND) > 0L) {
    fund <- copy(FUND)
    if ("Factor_Date" %in% names(fund)) {
      fund <- fund[Factor_Date <= sig_d]
    } else if ("Date" %in% names(fund)) {
      fund <- fund[Date <= sig_d]
      setnames(fund, "Date", "Factor_Date")
    }
    is_long <- "Item" %in% names(fund)

    snap <- RAWDATA[Date == sig_d & !is.na(Close) & Close > 0,
                    .(Ticker, Close, Size)]
    snap[, MarketCap := Close * Size]
    snap <- snap[MarketCap > 0]

    if (is_long) {
      items_lev <- c("ShortTermBorr", "LongTermBorr", "TotalAssets")
      lev_dt <- fund[Item %in% items_lev]
      if (nrow(lev_dt) > 0L) {
        setorder(lev_dt, Ticker, Item, Factor_Date)
        latest <- lev_dt[, .SD[.N], by = .(Ticker, Item)]
        lev_wide <- dcast(latest, Ticker ~ Item, value.var = "Value")
      } else {
        lev_wide <- NULL
      }
    } else {
      setorder(fund, Ticker, Factor_Date)
      lev_wide <- fund[, .SD[.N], by = Ticker]
    }

    if (!is.null(lev_wide) && nrow(lev_wide) > 0L) {
      .sc_lw <- function(col) if (col %in% names(lev_wide)) lev_wide[[col]] else rep(NA_real_, nrow(lev_wide))
      std <- .sc_lw("ShortTermBorr"); std[is.na(std)] <- 0
      ltd <- .sc_lw("LongTermBorr"); ltd[is.na(ltd)] <- 0
      lev_wide[, TotalDebt := std + ltd]

      lev_m <- merge(lev_wide[, .(Ticker, TotalDebt)], snap[, .(Ticker, MarketCap)],
                     by = "Ticker", all = FALSE)
      if (nrow(lev_m) > 0L) {
        lev_m[, R17 := fifelse(MarketCap > 0, -TotalDebt / MarketCap, NA_real_)]
        results[["R17"]] <- lev_m[!is.na(R17), .(Ticker, Factor_Name = "R17_Market_Leverage", Raw_Value = R17)]
      }

      # ---- R18: Book Leverage = TotalDebt / TotalAssets ----
      ta_vec <- .sc_lw("TotalAssets")
      lev_wide[, R18 := fifelse(!is.na(ta_vec) & ta_vec > 0, -(std + ltd) / ta_vec, NA_real_)]
      results[["R18"]] <- lev_wide[!is.na(R18), .(Ticker, Factor_Name = "R18_Book_Leverage", Raw_Value = R18)]
    }
  }

  # ==========================================================================
  # R19: Composite Risk Score = mean(z(R01), z(R07), z(R13), z(R17))
  # ==========================================================================
  all_res <- rbindlist(results, use.names = TRUE, fill = TRUE)
  if (nrow(all_res) > 0L) {
    comp_factors <- c("R01_VaR_95", "R07_Downside_Dev", "R13_NCSKEW")
    if ("R17_Market_Leverage" %in% all_res$Factor_Name) {
      comp_factors <- c(comp_factors, "R17_Market_Leverage")
    }
    comp_dt <- all_res[Factor_Name %in% comp_factors]
    if (nrow(comp_dt) > 0L) {
      # Cross-sectional z-score per factor
      comp_dt[, z_val := {
        m <- mean(Raw_Value, na.rm = TRUE)
        s <- sd(Raw_Value, na.rm = TRUE)
        if (is.na(s) || s < 1e-8) NA_real_ else (Raw_Value - m) / s
      }, by = Factor_Name]
      comp_agg <- comp_dt[!is.na(z_val), .(n_comp = .N, z_mean = mean(z_val, na.rm = TRUE)), by = Ticker]
      comp_agg <- comp_agg[n_comp >= 2L]
      if (nrow(comp_agg) > 0L) {
        r19 <- comp_agg[, .(Ticker, Factor_Name = "R19_Composite_Risk", Raw_Value = z_mean)]
        results[["R19"]] <- r19
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

cat("[factor_db] compute_risk.R loaded (R01~R19)\n")
