#==============================================================================
# compute_defense.R — Low Risk / Defense Factor 계산 모듈 (D01~D60)
#
# 함수: compute_defense(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL)
# 반환: data.table(Ticker, Factor_Name, Raw_Value)
#
# PIT 준수: Date <= sig_date, 252d lookback. Min 120 obs for regression.
# 모든 팩터 부호: 낮은 위험 = 높은 값 (방어적 = 좋음)
#
# D01~D05: Original factors
# D06~D33: Beta factors (28)
# D34~D60: Volatility factors (27)
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

compute_defense <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {
  sig_d <- as.Date(sig_date)
  results <- list()

  # --- 가격 데이터 준비 (PIT: Date <= sig_date, 252d lookback) ---
  rd <- copy(RAWDATA)
  rd[, Date := as.Date(Date)]
  lookback_start <- sig_d - 365  # ~252 trading days
  rd <- rd[Date <= sig_d & Date >= lookback_start]

  if (nrow(rd) == 0) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  # 필수 컬럼 확인
  if (!all(c("Ticker", "Date", "Ret", "BM_Ret") %in% names(rd))) {
    warning("[compute_defense] Missing required columns: Ticker, Date, Ret, BM_Ret")
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  setkey(rd, Ticker, Date)   # keyed access: rd[.(tk)] is O(log N) vs O(N) for rd[Ticker == tk]

  MIN_OBS_REG <- 120L  # 회귀 최소 관측수
  MIN_OBS_SD  <- 120L  # 표준편차 최소 관측수

  tickers <- unique(rd$Ticker)

  # --- D01/D02/D04: IdioVol / Beta / Downside Beta — data.table by = Ticker ──
  # Consolidate three lapply loops into one by = Ticker pass for 3× speedup
  rd_capm <- rd[!is.na(Ret) & !is.na(BM_Ret)]
  capm_dt <- rd_capm[, {
    n <- .N
    d01 <- d02 <- d04 <- NA_real_
    if (n >= MIN_OBS_REG) {
      fit <- tryCatch(lm.fit(cbind(1, BM_Ret), Ret), error = function(e) NULL)
      if (!is.null(fit)) {
        d01 <- -sd(fit$residuals, na.rm = TRUE)
        d02 <- -fit$coefficients[2L]
      }
      down_idx <- BM_Ret < 0
      n_down <- sum(down_idx)
      if (n_down >= 60L) {
        fit_d <- tryCatch(lm.fit(cbind(1, BM_Ret[down_idx]), Ret[down_idx]),
                          error = function(e) NULL)
        if (!is.null(fit_d)) d04 <- -fit_d$coefficients[2L]
      }
    }
    list(D01 = d01, D02 = d02, D04 = d04)
  }, by = Ticker]

  capm_long <- rbindlist(list(
    capm_dt[!is.na(D01), .(Ticker, Factor_Name = "D01_IdioVol",       Raw_Value = D01)],
    capm_dt[!is.na(D02), .(Ticker, Factor_Name = "D02_Beta",          Raw_Value = D02)],
    capm_dt[!is.na(D04), .(Ticker, Factor_Name = "D04_Downside_Beta", Raw_Value = D04)]
  ))
  capm_results <- capm_long  # keep name for downstream references (D07 uses D02/D04)
  if (nrow(capm_results) > 0) results[["CAPM"]] <- capm_results

  # --- D03: RealVol = -sd(Ret, 252d) ---
  d03 <- rd[!is.na(Ret), .(
    n = .N,
    sd_ret = sd(Ret, na.rm = TRUE)
  ), by = Ticker]
  d03 <- d03[n >= MIN_OBS_SD & !is.na(sd_ret)]
  if (nrow(d03) > 0) {
    results[["D03"]] <- d03[, .(Ticker, Factor_Name = "D03_RealVol",
                                Raw_Value = -sd_ret)]
  }

  # --- D05: MaxRet = -max(daily Ret in past 21d) ---
  # 21 trading days ~ 1 month
  recent_start <- sig_d - 35  # generous window for 21 trading days
  rd_recent <- rd[Date <= sig_d & Date >= recent_start]
  d05 <- rd_recent[!is.na(Ret), .(
    n = .N,
    max_ret = max(Ret, na.rm = TRUE)
  ), by = Ticker]
  d05 <- d05[n >= 10L & is.finite(max_ret)]  # at least 10 obs in ~21d window
  if (nrow(d05) > 0) {
    results[["D05"]] <- d05[, .(Ticker, Factor_Name = "D05_MaxRet",
                                Raw_Value = -max_ret)]
  }

  # =============================================================================
  # BETA FACTORS (D06~D33) — 28 factors
  # =============================================================================

  # =============================================================================
  # D06~D27 CONSOLIDATED: Single by=Ticker pass replaces 18 separate lapply loops
  # =============================================================================
  beta_block <- rd_capm[, {
    n <- .N
    d06 <- d08 <- d09 <- d11 <- d12 <- d13 <- d15 <- d16 <- d17 <- NA_real_
    d19 <- d20 <- d21 <- d24 <- d25 <- d26 <- d27 <- NA_real_

    if (n >= MIN_OBS_REG) {
      rets <- Ret; bm <- BM_Ret
      fit_full <- tryCatch(lm.fit(cbind(1, bm), rets), error = function(e) NULL)

      if (!is.null(fit_full)) {
        beta_full <- fit_full$coefficients[2L]
        alpha_full <- fit_full$coefficients[1L]
        resid_full <- fit_full$residuals
        total_var  <- var(rets, na.rm = TRUE)
        idio_var   <- var(resid_full, na.rm = TRUE)

        d21 <- alpha_full
        if (!is.na(total_var) && total_var >= 1e-12)
          d24 <- -(1 - idio_var / total_var)

        # D16: Coskewness
        rm2 <- bm^2
        cs_num <- mean(resid_full * rm2, na.rm = TRUE)
        cs_den <- sqrt(mean(resid_full^2, na.rm=TRUE)) * sqrt(mean(rm2^2, na.rm=TRUE))
        if (is.finite(cs_num) && is.finite(cs_den) && cs_den > 1e-12)
          d16 <- -cs_num / cs_den

        # D17: Cokurtosis
        rm3 <- bm^3
        ck_num <- mean(resid_full * rm3, na.rm=TRUE)
        ck_den <- sqrt(mean(resid_full^2, na.rm=TRUE)) * (mean(bm^4, na.rm=TRUE))^(3/4)
        if (is.finite(ck_num) && is.finite(ck_den) && ck_den > 1e-12)
          d17 <- -ck_num / ck_den
      }

      # D06: Upside Beta
      up_idx <- bm > 0
      if (sum(up_idx) >= 60L) {
        f <- tryCatch(lm.fit(cbind(1, bm[up_idx]), rets[up_idx]), error=function(e) NULL)
        if (!is.null(f)) d06 <- -f$coefficients[2L]
      }

      # D08: Tail Beta
      bm_sd <- sd(bm, na.rm=TRUE)
      if (!is.na(bm_sd) && bm_sd > 1e-8) {
        tail_idx <- abs(bm) > 2 * bm_sd
        if (sum(tail_idx) >= 20L) {
          f <- tryCatch(lm.fit(cbind(1, bm[tail_idx]), rets[tail_idx]), error=function(e) NULL)
          if (!is.null(f)) d08 <- -f$coefficients[2L]
        }
      }

      # D09: Dimson Beta
      if (n >= MIN_OBS_REG + 2L) {
        y_d  <- rets[2L:(n-1L)]
        x0_d <- bm[2L:(n-1L)]; xl_d <- bm[1L:(n-2L)]; xf_d <- bm[3L:n]
        f <- tryCatch(lm.fit(cbind(1, xl_d, x0_d, xf_d), y_d), error=function(e) NULL)
        if (!is.null(f)) d09 <- -sum(f$coefficients[2L:4L], na.rm=TRUE)
      }

      # D11: FP Beta
      sd_i <- sd(rets, na.rm=TRUE); sd_m <- sd(bm, na.rm=TRUE)
      if (!is.na(sd_i) && !is.na(sd_m) && sd_m > 1e-8) {
        rho <- cor(rets, bm, use="complete.obs")
        if (!is.na(rho)) d11 <- -(0.6 * rho * sd_i / sd_m + 0.4)
      }

      # D12: 126d Beta; D13: 63d Beta
      if (n >= 126L) {
        s126 <- seq(max(1L, n-125L), n)
        f <- tryCatch(lm.fit(cbind(1, bm[s126]), rets[s126]), error=function(e) NULL)
        if (!is.null(f)) d12 <- -f$coefficients[2L]
      }
      if (n >= 63L) {
        s63 <- seq(max(1L, n-62L), n)
        f <- tryCatch(lm.fit(cbind(1, bm[s63]), rets[s63]), error=function(e) NULL)
        if (!is.null(f)) d13 <- -f$coefficients[2L]
      }

      # D15: Conditional Bear Beta
      if (n >= MIN_OBS_REG) {
        recent_sum <- sum(bm[seq(max(1L,n-59L),n)], na.rm=TRUE)
        if (recent_sum >= 0) {
          down_idx <- bm < 0
          if (sum(down_idx) >= 60L) {
            f <- tryCatch(lm.fit(cbind(1, bm[down_idx]), rets[down_idx]), error=function(e) NULL)
            if (!is.null(f)) d15 <- -f$coefficients[2L]
          }
        } else {
          w_vec <- ifelse(bm < 0, 2.0, 1.0)
          X_mat <- cbind(1, bm)
          f <- tryCatch({
            XtW <- t(X_mat * w_vec)
            solve(XtW %*% X_mat, XtW %*% rets)
          }, error=function(e) NULL)
          if (!is.null(f)) d15 <- -f[2L]
        }
      }

      # D19: EW Beta (hl=63); D20: EW Beta (hl=126)
      .ew_beta <- function(hl) {
        lambda <- exp(-log(2)/hl)
        w <- lambda^(seq(n-1L,0L)); w <- w/sum(w)
        wm_r <- sum(w*rets); wm_b <- sum(w*bm)
        cv <- sum(w*(rets-wm_r)*(bm-wm_b)); vv <- sum(w*(bm-wm_b)^2)
        if (vv < 1e-12) return(NA_real_)
        -(cv/vv)
      }
      d19 <- .ew_beta(63L); d20 <- .ew_beta(126L)

      # D25: Left-Tail Beta; D26: Right-Tail Beta
      q5 <- quantile(bm, 0.05, na.rm=TRUE); q95 <- quantile(bm, 0.95, na.rm=TRUE)
      lt_idx <- bm <= q5; rt_idx <- bm >= q95
      if (sum(lt_idx) >= 10L) {
        f <- tryCatch(lm.fit(cbind(1, bm[lt_idx]), rets[lt_idx]), error=function(e) NULL)
        if (!is.null(f)) d25 <- -f$coefficients[2L]
      }
      if (sum(rt_idx) >= 10L) {
        f <- tryCatch(lm.fit(cbind(1, bm[rt_idx]), rets[rt_idx]), error=function(e) NULL)
        if (!is.null(f)) d26 <- -f$coefficients[2L]
      }

      # D27: Beta Stability (rolling 63d betas, monthly steps)
      if (n >= 189L) {
        win <- 63L
        starts <- seq(1L, n - win + 1L, by = 21L)
        betas_roll <- vapply(starts, function(s) {
          idx <- s:(s+win-1L)
          f <- tryCatch(lm.fit(cbind(1, bm[idx]), rets[idx]), error=function(e) NULL)
          if (is.null(f)) NA_real_ else f$coefficients[2L]
        }, numeric(1))
        betas_roll <- betas_roll[!is.na(betas_roll)]
        if (length(betas_roll) >= 3L) d27 <- -sd(betas_roll)
      }
    }

    list(D06=d06, D08=d08, D09=d09, D11=d11, D12=d12, D13=d13,
         D15=d15, D16=d16, D17=d17, D19=d19, D20=d20, D21=d21,
         D24=d24, D25=d25, D26=d26, D27=d27)
  }, by = Ticker]

  # Unpack beta_block into results
  .add_factor <- function(dt, col, fname) {
    sub <- dt[!is.na(get(col)), .(Ticker, Factor_Name = fname, Raw_Value = get(col))]
    if (nrow(sub) > 0) results[[fname]] <<- sub
  }
  .add_factor(beta_block, "D06", "D06_Upside_Beta")
  d06_results <- if (!is.null(results[["D06_Upside_Beta"]])) results[["D06_Upside_Beta"]]
                 else data.table(Ticker=character(), Factor_Name=character(), Raw_Value=numeric())
  results[["D06"]] <- d06_results
  results[["D06_Upside_Beta"]] <- NULL

  .add_factor(beta_block, "D08", "D08_Tail_Beta")
  .add_factor(beta_block, "D09", "D09_Dimson_Beta")
  .add_factor(beta_block, "D11", "D11_FP_Beta")
  .add_factor(beta_block, "D12", "D12_Beta_126d")
  .add_factor(beta_block, "D13", "D13_Beta_63d")
  .add_factor(beta_block, "D15", "D15_Cond_Bear_Beta")
  .add_factor(beta_block, "D16", "D16_Coskewness")
  .add_factor(beta_block, "D17", "D17_Cokurtosis")
  .add_factor(beta_block, "D19", "D19_EW_Beta_63")
  .add_factor(beta_block, "D20", "D20_EW_Beta_126")
  .add_factor(beta_block, "D21", "D21_CAPM_Alpha")
  .add_factor(beta_block, "D24", "D24_Systematic_Risk_Prop")
  .add_factor(beta_block, "D25", "D25_Left_Tail_Beta")
  .add_factor(beta_block, "D26", "D26_Right_Tail_Beta")
  .add_factor(beta_block, "D27", "D27_Beta_Stability")

  # --- D07: Beta Asymmetry (derived from D04/D06 already in results) ---
  if (!is.null(results[["D06"]]) && nrow(results[["D06"]]) > 0 &&
      !is.null(capm_results) && any(grepl("D04", capm_results$Factor_Name))) {
    d04_dt <- capm_results[Factor_Name == "D04_Downside_Beta"]
    d06_dt <- results[["D06"]]
    asym <- merge(d04_dt[, .(Ticker, down_val = Raw_Value)],
                  d06_dt[, .(Ticker, up_val = Raw_Value)], by = "Ticker")
    asym[, Raw_Value := -(up_val - down_val)]
    if (nrow(asym) > 0)
      results[["D07"]] <- asym[, .(Ticker, Factor_Name = "D07_Beta_Asymmetry", Raw_Value)]
  }

  # --- D10: Blume Adjusted Beta (derived from D02) ---
  if (!is.null(capm_results) && any(grepl("D02", capm_results$Factor_Name))) {
    d02_dt <- capm_results[Factor_Name == "D02_Beta"]
    d10 <- copy(d02_dt)
    d10[, raw_beta := -Raw_Value]
    d10[, Raw_Value := -(0.371 + 0.635 * raw_beta)]
    d10[, Factor_Name := "D10_Blume_Adj_Beta"]
    results[["D10"]] <- d10[, .(Ticker, Factor_Name, Raw_Value)]
  }

  # --- D14: Beta Change (derived from D13/D02) ---
  if (!is.null(results[["D13_Beta_63d"]]) && nrow(results[["D13_Beta_63d"]]) > 0 &&
      !is.null(capm_results) && any(grepl("D02", capm_results$Factor_Name))) {
    d02_dt <- capm_results[Factor_Name == "D02_Beta", .(Ticker, b252 = Raw_Value)]
    d13_dt <- results[["D13_Beta_63d"]][, .(Ticker, b63 = Raw_Value)]
    bc <- merge(d02_dt, d13_dt, by = "Ticker")
    bc[, Raw_Value := -(b252 - b63)]
    if (nrow(bc) > 0)
      results[["D14"]] <- bc[, .(Ticker, Factor_Name = "D14_Beta_Change", Raw_Value)]
  }

  # --- D18: BAB Rank (derived from D02) ---
  if (!is.null(capm_results) && any(grepl("D02", capm_results$Factor_Name))) {
    d02_dt <- capm_results[Factor_Name == "D02_Beta"]
    d18 <- copy(d02_dt)
    d18[, raw_beta := -Raw_Value]
    d18[, Raw_Value := -frank(raw_beta, ties.method = "average") / .N]
    d18[, Factor_Name := "D18_BAB_Rank"]
    results[["D18"]] <- d18[, .(Ticker, Factor_Name, Raw_Value)]
  }

  # --- D22: Tracking Error (by=Ticker, no lapply needed) ---
  d22 <- rd[!is.na(Ret) & !is.na(BM_Ret), .(
    n = .N, te = sd(Ret - BM_Ret, na.rm = TRUE)
  ), by = Ticker]
  d22 <- d22[n >= MIN_OBS_SD & !is.na(te)]
  if (nrow(d22) > 0)
    results[["D22"]] <- d22[, .(Ticker, Factor_Name = "D22_Tracking_Error", Raw_Value = -te)]

  # --- D23: Information Ratio (by=Ticker) ---
  d23 <- rd[!is.na(Ret) & !is.na(BM_Ret), .(
    n = .N, er = mean(Ret - BM_Ret, na.rm = TRUE), te = sd(Ret - BM_Ret, na.rm = TRUE)
  ), by = Ticker]
  d23 <- d23[n >= MIN_OBS_SD & !is.na(te) & te > 1e-8]
  if (nrow(d23) > 0)
    results[["D23"]] <- d23[, .(Ticker, Factor_Name = "D23_Info_Ratio", Raw_Value = er / te)]

  # Rename beta_block results to canonical keys expected downstream
  for (.nm in c("D08_Tail_Beta","D09_Dimson_Beta","D11_FP_Beta","D12_Beta_126d",
                "D13_Beta_63d","D15_Cond_Bear_Beta","D16_Coskewness","D17_Cokurtosis",
                "D19_EW_Beta_63","D20_EW_Beta_126","D21_CAPM_Alpha",
                "D24_Systematic_Risk_Prop","D25_Left_Tail_Beta","D26_Right_Tail_Beta",
                "D27_Beta_Stability")) {
    key <- sub("_.*", "", .nm)  # e.g. "D08"
    if (!is.null(results[[.nm]]) && nrow(results[[.nm]]) > 0)
      results[[key]] <- results[[.nm]]
    results[[.nm]] <- NULL
  }

  # --- D28: Leverage Beta (FUND needed) ---
  # Beta_unlevered = beta / (1 + D/E). Low levered beta = fundamentally less risky
  if (!is.null(FUND) && nrow(FUND) > 0 &&
      !is.null(capm_results) && any(grepl("D02", capm_results$Factor_Name))) {
    d02_dt <- capm_results[Factor_Name == "D02_Beta", .(Ticker, neg_beta = Raw_Value)]
    # FUND is already pre-filtered (FUND_pit) by builder — copy is still needed
    # to avoid in-place modification, but the copy is now smaller.
    fund_tmp <- copy(FUND)
    if ("Factor_Date" %in% names(fund_tmp) && !isTRUE(attr(fund_tmp, "pit_filtered"))) {
      fund_tmp <- fund_tmp[Factor_Date <= sig_d]
    } else if ("Date" %in% names(fund_tmp) && !isTRUE(attr(fund_tmp, "pit_filtered"))) {
      fund_tmp <- fund_tmp[Date <= sig_d]
    }
    if ("Item" %in% names(fund_tmp)) {
      # setorder + .SD[.N] replaces which.max for sorted data
      setorder(fund_tmp, Ticker, Factor_Date)
      debt_dt <- fund_tmp[Item == "TotalDebt", .SD[.N], by = Ticker][, .(Ticker, Debt = Value)]
      eq_dt <- fund_tmp[Item == "TotalEquity", .SD[.N], by = Ticker][, .(Ticker, Equity = Value)]
      lev_dt <- merge(debt_dt, eq_dt, by = "Ticker")
    } else if (all(c("TotalDebt", "TotalEquity") %in% names(fund_tmp))) {
      fund_tmp <- fund_tmp[!is.na(TotalDebt) & !is.na(TotalEquity)]
      if ("Factor_Date" %in% names(fund_tmp)) {
        setorder(fund_tmp, Ticker, Factor_Date)
        lev_dt <- fund_tmp[, .SD[.N], by = Ticker][, .(Ticker, Debt = TotalDebt, Equity = TotalEquity)]
      } else {
        lev_dt <- fund_tmp[, .(Ticker, Debt = TotalDebt, Equity = TotalEquity)]
      }
    } else {
      lev_dt <- data.table(Ticker = character(), Debt = numeric(), Equity = numeric())
    }
    if (nrow(lev_dt) > 0) {
      lev_dt <- lev_dt[Equity > 0]
      d28 <- merge(d02_dt, lev_dt, by = "Ticker")
      d28[, raw_beta := -neg_beta]
      d28[, unlev_beta := raw_beta / (1 + Debt / Equity)]
      d28 <- d28[!is.na(unlev_beta) & is.finite(unlev_beta)]
      if (nrow(d28) > 0) {
        results[["D28"]] <- d28[, .(Ticker, Factor_Name = "D28_Unlevered_Beta",
                                    Raw_Value = -unlev_beta)]
      }
    }
  }

  # --- D29: Accounting Beta = -cov(ROE_i, ROE_mkt) / var(ROE_mkt) ---
  # Beaver, Kettler & Scholes (1970). # DATA_NEEDED: multi-period firm ROE + market ROE
  # Requires FUND with multiple periods. Attempt if available.
  if (!is.null(FUND) && nrow(FUND) > 0) {
    d29 <- tryCatch({
      fund_tmp <- copy(FUND)
      if ("Factor_Date" %in% names(fund_tmp)) fund_tmp <- fund_tmp[Factor_Date <= sig_d]
      else if ("Date" %in% names(fund_tmp)) { fund_tmp <- fund_tmp[Date <= sig_d]; setnames(fund_tmp, "Date", "Factor_Date") }

      if ("Item" %in% names(fund_tmp)) {
        ni_dt <- fund_tmp[Item == "NetIncome", .(Ticker, Factor_Date, NI = Value)]
        eq_dt <- fund_tmp[Item == "TotalEquity", .(Ticker, Factor_Date, EQ = Value)]
        roe_dt <- merge(ni_dt, eq_dt, by = c("Ticker", "Factor_Date"))
        roe_dt <- roe_dt[EQ > 0]
        roe_dt[, ROE := NI / EQ]
      } else if (all(c("NetIncome", "TotalEquity") %in% names(fund_tmp))) {
        roe_dt <- fund_tmp[TotalEquity > 0, .(Ticker, Factor_Date, ROE = NetIncome / TotalEquity)]
      } else {
        roe_dt <- data.table()
      }
      if (nrow(roe_dt) < 2) return(NULL)
      # Market ROE = cross-sectional median each period
      mkt_roe <- roe_dt[, .(mkt_ROE = median(ROE, na.rm = TRUE)), by = Factor_Date]
      roe_dt <- merge(roe_dt, mkt_roe, by = "Factor_Date")
      acc_betas <- roe_dt[, {
        if (.N >= 3) {
          cv <- cov(ROE, mkt_ROE, use = "complete.obs")
          vr <- var(mkt_ROE, na.rm = TRUE)
          if (!is.na(vr) && vr > 1e-12) list(acc_beta = cv / vr) else list(acc_beta = NA_real_)
        } else list(acc_beta = NA_real_)
      }, by = Ticker]
      acc_betas <- acc_betas[!is.na(acc_beta)]
      if (nrow(acc_betas) > 0) {
        acc_betas[, .(Ticker, Factor_Name = "D29_Accounting_Beta", Raw_Value = -acc_beta)]
      } else NULL
    }, error = function(e) NULL)
    if (!is.null(d29) && nrow(d29) > 0) results[["D29"]] <- d29
  }

  # --- D30: Fama-MacBeth Beta = cross-sectionally estimated beta ---
  # DATA_NEEDED: Requires panel of multiple periods. Use latest cross-section regression
  # Simplified: use last 21d returns cross-sectionally
  rd_last21 <- rd[Date >= (sig_d - 35)]
  if (nrow(rd_last21) > 0) {
    cs_data <- rd_last21[!is.na(Ret) & !is.na(BM_Ret),
                         .(mean_ret = mean(Ret, na.rm = TRUE),
                           mean_bm = mean(BM_Ret, na.rm = TRUE)), by = Ticker]
    if (nrow(cs_data) >= 20L) {
      bm_var <- var(cs_data$mean_bm, na.rm = TRUE)
      if (!is.na(bm_var) && bm_var > 1e-12) {
        cs_data[, fm_beta := cov(mean_ret, mean_bm) / bm_var, by = .I]  # dummy by
        # Recalculate properly
        global_cov <- cov(cs_data$mean_ret, cs_data$mean_bm, use = "complete.obs")
        cs_data[, fm_beta := global_cov / bm_var]
        # Per-stock sensitivity: use within-ticker time-series
        d30_results <- rbindlist(lapply(cs_data$Ticker, function(tk) {
          sub <- rd_last21[Ticker == tk & !is.na(Ret) & !is.na(BM_Ret)]
          if (nrow(sub) < 10L) return(NULL)
          fit <- tryCatch(lm.fit(cbind(1, sub$BM_Ret), sub$Ret), error = function(e) NULL)
          if (is.null(fit)) return(NULL)
          b <- fit$coefficients[2]
          if (is.na(b)) return(NULL)
          data.table(Ticker = tk, Factor_Name = "D30_FM_Beta_21d", Raw_Value = -b)
        }), fill = TRUE)
        if (nrow(d30_results) > 0) results[["D30"]] <- d30_results
      }
    }
  }

  # --- D31: Relative Beta = beta_i / median(beta) cross-section ---
  if (!is.null(capm_results) && any(grepl("D02", capm_results$Factor_Name))) {
    d02_dt <- capm_results[Factor_Name == "D02_Beta"]
    d31 <- copy(d02_dt)
    d31[, raw_beta := -Raw_Value]
    med_beta <- median(d31$raw_beta, na.rm = TRUE)
    if (!is.na(med_beta) && abs(med_beta) > 1e-8) {
      d31[, Raw_Value := -(raw_beta / med_beta)]
      d31[, Factor_Name := "D31_Relative_Beta"]
      results[["D31"]] <- d31[, .(Ticker, Factor_Name, Raw_Value)]
    }
  }

  # --- D32: Beta VIX Sensitivity ---
  # DATA_NEEDED: VIX data (VKOSPI or ^VIX). Return NA if not in RAWDATA.
  # ★PIT C11 (2026-09-24 · 판정서 V-08): VIX 열은 빌더의 가용일 결합판만 받는다 — 표지 = 열 속성
  #   c11_avail(factor_db_builder.R .fdb_vix_asof_join 의 규칙 regime_key). 한국 d 행 VIX = 미국 날짜 < d
  #   인 최신값이라 회귀의 마지막 쌍(sig_d 수익 × sig_d 행 VIX 변화)도 sig_d 15:30 에 가용했다.
  #   표지 없는 VIX 열 = 출처 미상(구판 같은 날짜 결합판일 수 있다) → D32 미산출(fail-closed).
  #   VKOSPI 는 국내 지수라 해당 없음.
  .vix_c11 <- if ("VIX" %in% names(rd)) attr(rd[["VIX"]], "c11_avail", exact = TRUE) else NULL
  .vix_ok  <- is.character(.vix_c11) && length(.vix_c11) == 1L && !is.na(.vix_c11) && nzchar(.vix_c11)
  if ("VIX" %in% names(rd) && !.vix_ok && !("VKOSPI" %in% names(rd)))
    cat("  [compute_defense] !!! D32 거부 — VIX 열에 c11_avail 표지 없음(가용일 결합 미경유 · PIT C11 V-08)\n")
  if (.vix_ok || "VKOSPI" %in% names(rd)) {
    vix_col <- if ("VKOSPI" %in% names(rd)) "VKOSPI" else "VIX"
    d32_results <- rbindlist(lapply(tickers, function(tk) {
      sub <- rd[.(tk)][!is.na(Ret) & !is.na(get(vix_col))]
      if (nrow(sub) < MIN_OBS_REG) return(NULL)
      vix_chg <- diff(sub[[vix_col]]) / head(sub[[vix_col]], -1)
      if (length(vix_chg) < MIN_OBS_REG - 1) return(NULL)
      ret_sub <- sub$Ret[-1]
      valid <- !is.na(vix_chg) & !is.na(ret_sub) & is.finite(vix_chg)
      if (sum(valid) < 60L) return(NULL)
      fit <- tryCatch(lm.fit(cbind(1, vix_chg[valid]), ret_sub[valid]), error = function(e) NULL)
      if (is.null(fit)) return(NULL)
      b <- fit$coefficients[2]
      if (is.na(b)) return(NULL)
      # Positive vix_beta = stock goes up when vol rises = defensive
      data.table(Ticker = tk, Factor_Name = "D32_Beta_VIX", Raw_Value = b)
    }), fill = TRUE)
    if (nrow(d32_results) > 0) results[["D32"]] <- d32_results
  }
  # else: # DATA_NEEDED: VIX or VKOSPI column not in RAWDATA

  # --- D33: Beta Persistence = -abs(beta_first_half - beta_second_half) ---
  # Measures how stable/predictable beta is. Vectorized by=Ticker (replaces lapply).
  d33_dt <- rd_capm[, {
    n <- .N
    d33 <- NA_real_
    if (n >= 200L) {
      mid <- floor(n / 2)
      fit1 <- tryCatch(lm.fit(cbind(1, BM_Ret[1:mid]), Ret[1:mid]), error = function(e) NULL)
      fit2 <- tryCatch(lm.fit(cbind(1, BM_Ret[(mid+1L):n]), Ret[(mid+1L):n]), error = function(e) NULL)
      if (!is.null(fit1) && !is.null(fit2)) {
        b1 <- fit1$coefficients[2L]; b2 <- fit2$coefficients[2L]
        if (!is.na(b1) && !is.na(b2)) d33 <- -abs(b2 - b1)
      }
    }
    list(D33 = d33)
  }, by = Ticker]
  d33_dt <- d33_dt[!is.na(D33)]
  if (nrow(d33_dt) > 0)
    results[["D33"]] <- d33_dt[, .(Ticker, Factor_Name = "D33_Beta_Persistence", Raw_Value = D33)]

  # =============================================================================
  # VOLATILITY FACTORS (D34~D60) — 27 factors
  # =============================================================================

  # --- D34: RealVol 21d = -sd(Ret, 21d) ---
  d34 <- rd_recent[!is.na(Ret), .(n = .N, sd_ret = sd(Ret, na.rm = TRUE)), by = Ticker]
  d34 <- d34[n >= 10L & !is.na(sd_ret)]
  if (nrow(d34) > 0) {
    results[["D34"]] <- d34[, .(Ticker, Factor_Name = "D34_RealVol_21d",
                                Raw_Value = -sd_ret)]
  }

  # --- D35: RealVol 63d = -sd(Ret, 63d) ---
  rd_63d <- rd[Date >= (sig_d - 95)]  # generous for 63 trading days
  d35 <- rd_63d[!is.na(Ret), .(n = .N, sd_ret = sd(Ret, na.rm = TRUE)), by = Ticker]
  d35 <- d35[n >= 40L & !is.na(sd_ret)]
  if (nrow(d35) > 0) {
    results[["D35"]] <- d35[, .(Ticker, Factor_Name = "D35_RealVol_63d",
                                Raw_Value = -sd_ret)]
  }

  # --- D36: RealVol 126d = -sd(Ret, 126d) ---
  rd_126d <- rd[Date >= (sig_d - 190)]
  d36 <- rd_126d[!is.na(Ret), .(n = .N, sd_ret = sd(Ret, na.rm = TRUE)), by = Ticker]
  d36 <- d36[n >= 80L & !is.na(sd_ret)]
  if (nrow(d36) > 0) {
    results[["D36"]] <- d36[, .(Ticker, Factor_Name = "D36_RealVol_126d",
                                Raw_Value = -sd_ret)]
  }

  # --- D37: Parkinson Volatility = -sqrt(1/(4*N*ln2) * sum(ln(H/L)^2)) ---
  if (all(c("High", "Low") %in% names(rd))) {
    d37 <- rd[!is.na(High) & !is.na(Low) & High > 0 & Low > 0, {
      log_hl <- log(High / Low)
      n <- .N
      if (n >= MIN_OBS_SD) {
        park_vol <- sqrt(sum(log_hl^2) / (4 * n * log(2)))
        list(park_vol = park_vol)
      } else list(park_vol = NA_real_)
    }, by = Ticker]
    d37 <- d37[!is.na(park_vol)]
    if (nrow(d37) > 0) {
      results[["D37"]] <- d37[, .(Ticker, Factor_Name = "D37_Parkinson_Vol",
                                  Raw_Value = -park_vol)]
    }
  }

  # --- D38: Garman-Klass Volatility ---
  # GK = 0.5*(ln(H/L))^2 - (2*ln2-1)*(ln(C/O))^2
  if (all(c("High", "Low", "Close", "Open") %in% names(rd))) {
    d38 <- rd[!is.na(High) & !is.na(Low) & !is.na(Close) & !is.na(Open) &
                High > 0 & Low > 0 & Close > 0 & Open > 0, {
      n <- .N
      if (n >= MIN_OBS_SD) {
        gk_daily <- 0.5 * (log(High / Low))^2 - (2 * log(2) - 1) * (log(Close / Open))^2
        gk_vol <- sqrt(mean(gk_daily, na.rm = TRUE))
        if (is.nan(gk_vol) || !is.finite(gk_vol)) gk_vol <- NA_real_
        list(gk_vol = gk_vol)
      } else list(gk_vol = NA_real_)
    }, by = Ticker]
    d38 <- d38[!is.na(gk_vol)]
    if (nrow(d38) > 0) {
      results[["D38"]] <- d38[, .(Ticker, Factor_Name = "D38_GarmanKlass_Vol",
                                  Raw_Value = -gk_vol)]
    }
  }

  # --- D39: Rogers-Satchell Volatility ---
  # RS = sqrt(mean(ln(H/C)*ln(H/O) + ln(L/C)*ln(L/O)))
  if (all(c("High", "Low", "Close", "Open") %in% names(rd))) {
    d39 <- rd[!is.na(High) & !is.na(Low) & !is.na(Close) & !is.na(Open) &
                High > 0 & Low > 0 & Close > 0 & Open > 0, {
      n <- .N
      if (n >= MIN_OBS_SD) {
        rs_daily <- log(High / Close) * log(High / Open) + log(Low / Close) * log(Low / Open)
        rs_mean <- mean(rs_daily, na.rm = TRUE)
        rs_vol <- if (rs_mean > 0) sqrt(rs_mean) else NA_real_
        list(rs_vol = rs_vol)
      } else list(rs_vol = NA_real_)
    }, by = Ticker]
    d39 <- d39[!is.na(rs_vol)]
    if (nrow(d39) > 0) {
      results[["D39"]] <- d39[, .(Ticker, Factor_Name = "D39_RogersSatchell_Vol",
                                  Raw_Value = -rs_vol)]
    }
  }

  # --- D40: Yang-Zhang Volatility ---
  # Combines overnight, close-to-close, and Rogers-Satchell components.
  # Vectorized by=Ticker (replaces lapply).
  if (all(c("High", "Low", "Close", "Open") %in% names(rd))) {
    rd_ohlc <- rd[!is.na(High) & !is.na(Low) & !is.na(Close) & !is.na(Open) &
                    High > 0 & Low > 0 & Close > 0 & Open > 0]
    d40_dt <- rd_ohlc[, {
      n <- .N
      d40 <- NA_real_
      if (n >= MIN_OBS_SD) {
        overnight <- log(Open[-1] / Close[-n])
        cc        <- log(Close[-1] / Close[-n])
        rs        <- log(High / Close) * log(High / Open) +
                     log(Low / Close)  * log(Low / Open)
        rs_mean   <- mean(rs, na.rm = TRUE)
        k         <- 0.34 / (1.34 + (n + 1) / (n - 1))
        var_o     <- var(overnight, na.rm = TRUE)
        var_c     <- var(cc, na.rm = TRUE)
        yz_var    <- var_o + k * var_c + (1 - k) * rs_mean
        if (!is.na(yz_var) && yz_var > 0) d40 <- -sqrt(yz_var)
      }
      list(D40 = d40)
    }, by = Ticker]
    d40_dt <- d40_dt[!is.na(D40)]
    if (nrow(d40_dt) > 0)
      results[["D40"]] <- d40_dt[, .(Ticker, Factor_Name = "D40_YangZhang_Vol", Raw_Value = D40)]
  }

  # --- D41: Vol-of-Vol = -sd(rolling 21d volatility) ---
  # Vectorized by=Ticker via frollsum variance formula (replaces lapply inner loop).
  d41_dt <- rd[!is.na(Ret), {
    n <- .N
    d41 <- NA_real_
    if (n >= 84L) {
      # frollsum-based rolling SD over 21d (step=5 for speed)
      r <- Ret
      # Use all positions (step=1, fast with frollsum formula)
      r2 <- r^2
      win <- 21L
      # Inline rolling variance: var = (s2 - s1^2/n)/(n-1)
      s1 <- suppressWarnings(frollsum(r,  n = win, fill = NA_real_, align = "right", na.rm = FALSE))
      s2 <- suppressWarnings(frollsum(r2, n = win, fill = NA_real_, align = "right", na.rm = FALSE))
      vx <- (s2 - s1^2 / win) / (win - 1L)
      roll_vols <- sqrt(pmax(vx, 0))
      # Sample every 5 positions (weekly)
      idx <- seq(win, n, by = 5L)
      vols <- roll_vols[idx]
      vols <- vols[!is.na(vols) & is.finite(vols)]
      if (length(vols) >= 5L) d41 <- -sd(vols, na.rm = TRUE)
    }
    list(D41 = d41)
  }, by = Ticker]
  d41_dt <- d41_dt[!is.na(D41)]
  if (nrow(d41_dt) > 0)
    results[["D41"]] <- d41_dt[, .(Ticker, Factor_Name = "D41_Vol_of_Vol", Raw_Value = D41)]

  # --- D42: EWMA Volatility (lambda=0.94, RiskMetrics) ---
  # Vectorized by=Ticker via exponentially-weighted sum (replaces lapply + R loop).
  # Trick: EWMA_var_n = (1-lambda) * sum_{k=0}^{n-1} lambda^k * r_{n-k}^2
  # = weighted sum with exponentially decaying weights → dot product.
  d42_dt <- rd[!is.na(Ret), {
    n <- .N
    d42 <- NA_real_
    if (n >= 60L) {
      lambda <- 0.94
      r2 <- Ret^2
      # Weights: lambda^(n-1-k) for k=0..n-1, newest observation gets weight (1-lambda)
      # Recurrence is equivalent to: w_k = (1-lambda)*lambda^(n-1-k), normalized not needed
      # Efficient: use Reduce or cumulative trick
      # Rcpp not needed — this is a single pass with O(N) ops per ticker
      w <- (1 - lambda) * lambda^rev(seq_len(n) - 1L)
      var_ewma <- sum(w * r2, na.rm = FALSE)
      if (!is.na(var_ewma) && var_ewma > 0) d42 <- -sqrt(var_ewma)
    }
    list(D42 = d42)
  }, by = Ticker]
  d42_dt <- d42_dt[!is.na(D42)]
  if (nrow(d42_dt) > 0)
    results[["D42"]] <- d42_dt[, .(Ticker, Factor_Name = "D42_EWMA_Vol", Raw_Value = D42)]

  # --- D43: Return Skewness = -skew(Ret, 252d) ---
  # High positive skew = lottery-like, risky
  d43 <- rd[!is.na(Ret), {
    n <- .N
    if (n >= MIN_OBS_SD) {
      r <- Ret
      m <- mean(r, na.rm = TRUE)
      s <- sd(r, na.rm = TRUE)
      if (s > 1e-8) {
        skw <- mean(((r - m) / s)^3, na.rm = TRUE)
        list(skew = skw)
      } else list(skew = NA_real_)
    } else list(skew = NA_real_)
  }, by = Ticker]
  d43 <- d43[!is.na(skew)]
  if (nrow(d43) > 0) {
    results[["D43"]] <- d43[, .(Ticker, Factor_Name = "D43_Skewness", Raw_Value = -skew)]
  }

  # --- D44: Return Kurtosis = -kurt(Ret, 252d) ---
  # High kurtosis = fat tails = more extreme events
  d44 <- rd[!is.na(Ret), {
    n <- .N
    if (n >= MIN_OBS_SD) {
      r <- Ret
      m <- mean(r, na.rm = TRUE)
      s <- sd(r, na.rm = TRUE)
      if (s > 1e-8) {
        krt <- mean(((r - m) / s)^4, na.rm = TRUE) - 3  # excess kurtosis
        list(kurt = krt)
      } else list(kurt = NA_real_)
    } else list(kurt = NA_real_)
  }, by = Ticker]
  d44 <- d44[!is.na(kurt)]
  if (nrow(d44) > 0) {
    results[["D44"]] <- d44[, .(Ticker, Factor_Name = "D44_Kurtosis", Raw_Value = -kurt)]
  }

  # --- D45: Downside Deviation = -sqrt(mean(min(Ret,0)^2)) ---
  d45 <- rd[!is.na(Ret), {
    n <- .N
    if (n >= MIN_OBS_SD) {
      down_sq <- pmin(Ret, 0)^2
      dd <- sqrt(mean(down_sq, na.rm = TRUE))
      list(dd = dd)
    } else list(dd = NA_real_)
  }, by = Ticker]
  d45 <- d45[!is.na(dd)]
  if (nrow(d45) > 0) {
    results[["D45"]] <- d45[, .(Ticker, Factor_Name = "D45_Downside_Dev", Raw_Value = -dd)]
  }

  # --- D46: Sortino-like ratio = mean(Ret) / Downside Deviation ---
  d46 <- rd[!is.na(Ret), {
    n <- .N
    if (n >= MIN_OBS_SD) {
      down_sq <- pmin(Ret, 0)^2
      dd <- sqrt(mean(down_sq, na.rm = TRUE))
      mr <- mean(Ret, na.rm = TRUE)
      if (dd > 1e-8) list(sortino = mr / dd) else list(sortino = NA_real_)
    } else list(sortino = NA_real_)
  }, by = Ticker]
  d46 <- d46[!is.na(sortino)]
  if (nrow(d46) > 0) {
    results[["D46"]] <- d46[, .(Ticker, Factor_Name = "D46_Sortino", Raw_Value = sortino)]
  }

  # --- D47: CVaR 5% (Conditional Value-at-Risk) = -mean(Ret | Ret < VaR5%) ---
  d47 <- rd[!is.na(Ret), {
    n <- .N
    if (n >= MIN_OBS_SD) {
      var5 <- quantile(Ret, 0.05, na.rm = TRUE)
      tail_ret <- Ret[Ret <= var5]
      if (length(tail_ret) > 0) {
        list(cvar = mean(tail_ret, na.rm = TRUE))
      } else list(cvar = NA_real_)
    } else list(cvar = NA_real_)
  }, by = Ticker]
  d47 <- d47[!is.na(cvar)]
  if (nrow(d47) > 0) {
    # Higher CVaR (less negative) = less tail risk = more defensive
    results[["D47"]] <- d47[, .(Ticker, Factor_Name = "D47_CVaR_5pct", Raw_Value = cvar)]
  }

  # --- D48: VaR 5% = -5th percentile of return distribution ---
  d48 <- rd[!is.na(Ret), {
    n <- .N
    if (n >= MIN_OBS_SD) {
      list(var5 = quantile(Ret, 0.05, na.rm = TRUE))
    } else list(var5 = NA_real_)
  }, by = Ticker]
  d48 <- d48[!is.na(var5)]
  if (nrow(d48) > 0) {
    # Higher VaR (less negative) = less tail risk
    results[["D48"]] <- d48[, .(Ticker, Factor_Name = "D48_VaR_5pct", Raw_Value = var5)]
  }

  # --- D49: VaR 1% ---
  d49 <- rd[!is.na(Ret), {
    n <- .N
    if (n >= MIN_OBS_SD) {
      list(var1 = quantile(Ret, 0.01, na.rm = TRUE))
    } else list(var1 = NA_real_)
  }, by = Ticker]
  d49 <- d49[!is.na(var1)]
  if (nrow(d49) > 0) {
    results[["D49"]] <- d49[, .(Ticker, Factor_Name = "D49_VaR_1pct", Raw_Value = var1)]
  }

  # --- D50/D51: MaxDrawdown + Ulcer Index — single by=Ticker pass (replaces 2 lapply) ---
  d5051_dt <- rd[!is.na(Ret), {
    n <- .N
    d50 <- d51 <- NA_real_
    if (n >= 60L) {
      cum_ret     <- cumprod(1 + Ret)
      running_max <- cummax(cum_ret)
      dd          <- (cum_ret - running_max) / running_max
      max_dd      <- min(dd, na.rm = TRUE)
      if (is.finite(max_dd)) d50 <- max_dd
      dd_pct  <- 100 * dd
      ulcer   <- sqrt(mean(dd_pct^2, na.rm = TRUE))
      if (is.finite(ulcer)) d51 <- -ulcer
    }
    list(D50 = d50, D51 = d51)
  }, by = Ticker]

  d50_sub <- d5051_dt[!is.na(D50)]
  if (nrow(d50_sub) > 0)
    results[["D50"]] <- d50_sub[, .(Ticker, Factor_Name = "D50_MaxDrawdown", Raw_Value = D50)]
  d51_sub <- d5051_dt[!is.na(D51)]
  if (nrow(d51_sub) > 0)
    results[["D51"]] <- d51_sub[, .(Ticker, Factor_Name = "D51_Ulcer_Index", Raw_Value = D51)]

  # --- D52: Min Daily Return (252d) = min(Ret) ---
  d52 <- rd[!is.na(Ret), {
    n <- .N
    if (n >= MIN_OBS_SD) list(min_ret = min(Ret, na.rm = TRUE))
    else list(min_ret = NA_real_)
  }, by = Ticker]
  d52 <- d52[!is.na(min_ret) & is.finite(min_ret)]
  if (nrow(d52) > 0) {
    # Higher min return = less extreme loss = more defensive
    results[["D52"]] <- d52[, .(Ticker, Factor_Name = "D52_MinRet", Raw_Value = min_ret)]
  }

  # --- D53: Range Volatility = -mean(High - Low)/Close ---
  if (all(c("High", "Low", "Close") %in% names(rd))) {
    d53 <- rd[!is.na(High) & !is.na(Low) & !is.na(Close) & Close > 0, {
      n <- .N
      if (n >= MIN_OBS_SD) {
        range_pct <- (High - Low) / Close
        list(avg_range = mean(range_pct, na.rm = TRUE))
      } else list(avg_range = NA_real_)
    }, by = Ticker]
    d53 <- d53[!is.na(avg_range)]
    if (nrow(d53) > 0) {
      results[["D53"]] <- d53[, .(Ticker, Factor_Name = "D53_Range_Vol",
                                  Raw_Value = -avg_range)]
    }
  }

  # --- D54: Negative Return Proportion = -(count Ret < 0 / N) ---
  d54 <- rd[!is.na(Ret), {
    n <- .N
    if (n >= MIN_OBS_SD) {
      neg_prop <- sum(Ret < 0, na.rm = TRUE) / n
      list(neg_prop = neg_prop)
    } else list(neg_prop = NA_real_)
  }, by = Ticker]
  d54 <- d54[!is.na(neg_prop)]
  if (nrow(d54) > 0) {
    results[["D54"]] <- d54[, .(Ticker, Factor_Name = "D54_Neg_Ret_Prop",
                                Raw_Value = -neg_prop)]
  }

  # --- D55: Vol Trend = vol_63d / vol_252d (vol expansion = risky) ---
  if (!is.null(results[["D35"]]) && nrow(results[["D35"]]) > 0 &&
      !is.null(results[["D03"]]) && nrow(results[["D03"]]) > 0) {
    v63 <- results[["D35"]][, .(Ticker, vol63 = -Raw_Value)]  # un-negate
    v252 <- results[["D03"]][, .(Ticker, vol252 = -Raw_Value)]
    vt <- merge(v63, v252, by = "Ticker")
    vt <- vt[vol252 > 1e-8]
    if (nrow(vt) > 0) {
      results[["D55"]] <- vt[, .(Ticker, Factor_Name = "D55_Vol_Trend",
                                 Raw_Value = -(vol63 / vol252))]
    }
  }

  # --- D56: Up Volatility = -sd(Ret | Ret > 0) ---
  d56 <- rd[!is.na(Ret), {
    up_ret <- Ret[Ret > 0]
    if (length(up_ret) >= 30L) {
      list(up_vol = sd(up_ret, na.rm = TRUE))
    } else list(up_vol = NA_real_)
  }, by = Ticker]
  d56 <- d56[!is.na(up_vol)]
  if (nrow(d56) > 0) {
    results[["D56"]] <- d56[, .(Ticker, Factor_Name = "D56_Up_Vol", Raw_Value = -up_vol)]
  }

  # --- D57: Down Volatility = -sd(Ret | Ret < 0) ---
  d57 <- rd[!is.na(Ret), {
    dn_ret <- Ret[Ret < 0]
    if (length(dn_ret) >= 30L) {
      list(dn_vol = sd(dn_ret, na.rm = TRUE))
    } else list(dn_vol = NA_real_)
  }, by = Ticker]
  d57 <- d57[!is.na(dn_vol)]
  if (nrow(d57) > 0) {
    results[["D57"]] <- d57[, .(Ticker, Factor_Name = "D57_Down_Vol", Raw_Value = -dn_vol)]
  }

  # --- D58: Vol Asymmetry = -(DownVol - UpVol) ---
  if (!is.null(results[["D56"]]) && nrow(results[["D56"]]) > 0 &&
      !is.null(results[["D57"]]) && nrow(results[["D57"]]) > 0) {
    uv <- results[["D56"]][, .(Ticker, up_vol = -Raw_Value)]
    dv <- results[["D57"]][, .(Ticker, dn_vol = -Raw_Value)]
    va <- merge(uv, dv, by = "Ticker")
    if (nrow(va) > 0) {
      results[["D58"]] <- va[, .(Ticker, Factor_Name = "D58_Vol_Asymmetry",
                                 Raw_Value = -(dn_vol - up_vol))]
    }
  }

  # --- D59: IV Proxy (Implied Volatility proxy) ---
  # DATA_NEEDED: Options implied volatility data
  # Proxy: use Parkinson vol as closest available estimator (already in D37)
  # Marking as conceptual proxy; exact IV requires options data
  # Skip: covered by D37 (Parkinson) as proxy

  # --- D60: Leverage = -(TotalDebt / TotalEquity) ---
  # Low leverage = more defensive
  if (!is.null(FUND) && nrow(FUND) > 0) {
    d60 <- tryCatch({
      fund_tmp <- copy(FUND)
      if ("Factor_Date" %in% names(fund_tmp) && !isTRUE(attr(fund_tmp, "pit_filtered"))) {
        fund_tmp <- fund_tmp[Factor_Date <= sig_d]
      } else if ("Date" %in% names(fund_tmp) && !isTRUE(attr(fund_tmp, "pit_filtered"))) {
        fund_tmp <- fund_tmp[Date <= sig_d]
        setnames(fund_tmp, "Date", "Factor_Date")
      }

      if ("Item" %in% names(fund_tmp)) {
        setorder(fund_tmp, Ticker, Factor_Date)
        debt_dt <- fund_tmp[Item == "TotalDebt", .SD[.N], by = Ticker][, .(Ticker, Debt = Value)]
        eq_dt <- fund_tmp[Item == "TotalEquity", .SD[.N], by = Ticker][, .(Ticker, Equity = Value)]
        lev <- merge(debt_dt, eq_dt, by = "Ticker")
      } else if (all(c("TotalDebt", "TotalEquity") %in% names(fund_tmp))) {
        if ("Factor_Date" %in% names(fund_tmp)) {
          setorder(fund_tmp, Ticker, Factor_Date)
          lev <- fund_tmp[, .SD[.N], by = Ticker][, .(Ticker, Debt = TotalDebt, Equity = TotalEquity)]
        } else {
          lev <- fund_tmp[, .(Ticker, Debt = TotalDebt, Equity = TotalEquity)]
        }
      } else {
        lev <- data.table()
      }
      lev <- lev[!is.na(Debt) & !is.na(Equity) & Equity > 0]
      if (nrow(lev) == 0) return(NULL)
      lev[, .(Ticker, Factor_Name = "D60_Leverage", Raw_Value = -(Debt / Equity))]
    }, error = function(e) NULL)
    if (!is.null(d60) && nrow(d60) > 0) results[["D60"]] <- d60
  }

  # 결합
  if (length(results) == 0) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }
  out <- rbindlist(results, use.names = TRUE, fill = TRUE)
  out[, .(Ticker, Factor_Name, Raw_Value)]
}

cat("[factor_db] compute_defense.R loaded (D01~D60: 5 original + 28 Beta + 27 Volatility)\n")
