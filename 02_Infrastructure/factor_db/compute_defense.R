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

  # --- D28: Leverage Beta — 부채 · 자기자본 = 재무 분기 캐시 최신(2026-11-16 · fund_access.R) ---
  # Beta_unlevered = beta / (1 + D/E). Low levered beta = fundamentally less risky
  if (exists("fa_latest") && !is.null(capm_results) && any(grepl("D02", capm_results$Factor_Name))) {
    d02_dt <- capm_results[Factor_Name == "D02_Beta", .(Ticker, neg_beta = Raw_Value)]
    lev_dt <- tryCatch(fa_latest(sig_d, "q", c("TotalDebt", "BookEquity")), error = function(e) NULL)
    if (!is.null(lev_dt) && nrow(lev_dt) > 0) {
      lev_dt <- lev_dt[is.finite(TotalDebt) & is.finite(BookEquity) & BookEquity > 0, .(Ticker, Debt = TotalDebt, Equity = BookEquity)]
      d28 <- merge(d02_dt, lev_dt, by = "Ticker")
      d28[, raw_beta := -neg_beta]
      d28[, unlev_beta := raw_beta / (1 + Debt / Equity)]
      d28 <- d28[!is.na(unlev_beta) & is.finite(unlev_beta)]
      if (nrow(d28) > 0) {
        results[["D28"]] <- d28[, .(Ticker, Factor_Name = "D28_Unlevered_Beta", Raw_Value = -unlev_beta)]
      }
    }
  }

  # --- D29: Accounting Beta = 재무 연간 캐시 AccountingBeta(회사 ROE 를 시장 중앙값 ROE 에 10개 해 회귀 · 4쌍 이상 ·
  #   Beaver, Kettler & Scholes 1970 · build_fundamental_caches.R) 의 음수 — 구판은 분기 · 연간이 섞인 행으로 계산했다(2026-11-16)
  if (exists("fa_latest")) {
    ab <- tryCatch(fa_latest(sig_d, "a", "AccountingBeta"), error = function(e) NULL)
    if (!is.null(ab) && nrow(ab) > 0) {
      ab <- ab[is.finite(AccountingBeta)]
      if (nrow(ab) > 0) results[["D29"]] <- ab[, .(Ticker, Factor_Name = "D29_Accounting_Beta", Raw_Value = -AccountingBeta)]
    }
  }

  # Marking as conceptual proxy; exact IV requires options data
  # Skip: covered by D37 (Parkinson) as proxy

  # --- D60: Leverage = -(TotalDebt / BookEquity) — 재무 분기 캐시 DebtToEquity(2026-11-16) ---
  # Low leverage = more defensive
  if (exists("fa_latest")) {
    lv <- tryCatch(fa_latest(sig_d, "q", "DebtToEquity"), error = function(e) NULL)
    if (!is.null(lv) && nrow(lv) > 0) {
      lv <- lv[is.finite(DebtToEquity)]
      if (nrow(lv) > 0) results[["D60"]] <- lv[, .(Ticker, Factor_Name = "D60_Leverage", Raw_Value = -DebtToEquity)]
    }
  }

  # 결합
  if (length(results) == 0) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }
  out <- rbindlist(results, use.names = TRUE, fill = TRUE)
  out[, .(Ticker, Factor_Name, Raw_Value)]
}

cat("[factor_db] compute_defense.R loaded (D01~D60: 5 original + 28 Beta + 27 Volatility)\n")
