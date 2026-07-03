#==============================================================================
# Strategy Diagnostic Analyzer
# strategy_analyzer.R
#
# Usage (in any strategy directory after backtest):
#   source("02_Infrastructure/strategy_analyzer.R")
#   run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir)
#
# Produces:
#   output/analysis_ic.csv          — Factor IC / ICIR by signal date
#   output/analysis_rolling.csv     — Rolling 1/2/3yr Sharpe, CAGR, MDD
#   output/analysis_stress.csv      — Stress period performance
#   output/analysis_sector.csv      — Sector concentration over time
#   output/analysis_holdings.csv    — Holdings turnover rate
#   output/analysis_report.md       — Markdown summary (for SPMR)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(xts)
  library(PerformanceAnalytics)
})

# --- Rcpp 가속: hurdle_gate_perf.cpp (rolling_sharpe_cpp, rolling_mdd_cpp, stress_periods_cpp) ---
# strategy_analyzer.R는 hurdle_gate.R와 독립적으로 source() 가능 → 자체 로드
if (!exists("rolling_sharpe_cpp")) {
  tryCatch({
    suppressPackageStartupMessages(library(Rcpp))
    .sa_infra_dir <- if (exists("PROJECT_ROOT") && nzchar(PROJECT_ROOT)) {
      file.path(PROJECT_ROOT, "02_Infrastructure")
    } else {
      tryCatch(dirname(sys.frame(1)$ofile),
               error = function(e) file.path(
                 Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
                 "02_Infrastructure"
               ))
    }
    .sa_cpp_path <- file.path(.sa_infra_dir, "hurdle_gate_perf.cpp")
    if (file.exists(.sa_cpp_path)) {
      Rcpp::sourceCpp(.sa_cpp_path, verbose = FALSE, rebuild = FALSE)
      cat("[strategy_analyzer] Rcpp 가속 로드 완료\n")
    }
  }, error = function(e) {
    warning("[strategy_analyzer] Rcpp 로드 실패 — R fallback 사용: ", conditionMessage(e))
  })
}

run_analysis <- function(sim, FACTORS, RAWDATA, BM_DT,
                         output_dir, strategy_name = "Strategy") {

  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  cat(sprintf("[analyzer] Running diagnostic analysis for: %s\n", strategy_name))

  strat_xts <- sim$strategy_xts
  bm_xts    <- sim$bm_xts
  port_log  <- sim$PORTFOLIO_LOG
  hold_log  <- sim$HOLDINGS_LOG

  report <- list()
  all_dates <- sort(unique(RAWDATA$Date))
  raw_cols <- intersect(c("Date", "Ticker", "Ret", "Size", "Vol", "Close"), names(RAWDATA))
  raw_tickers <- unique(FACTORS$Ticker)
  RAWDATA <- RAWDATA[Ticker %in% raw_tickers, ..raw_cols]
  data.table::setindexv(RAWDATA, c("Ticker", "Date"))
  data.table::setindexv(RAWDATA, c("Date", "Ticker"))
  gc(verbose = FALSE)

  # ── 1. Factor IC / ICIR ──────────────────────────────────────────────────
  # IC = rank correlation between Score and next-period return
  ic_rows <- list()
  signal_dates <- sort(unique(FACTORS$Date))

  for (i in seq_along(signal_dates)) {
    sig_d <- signal_dates[i]
    # Find execution date (next month's first trading day)
    exec_d <- all_dates[all_dates > sig_d][1]
    if (is.na(exec_d)) next

    # Next rebalance date for return window
    next_sig  <- if (i < length(signal_dates)) signal_dates[i + 1] else NA_Date_
    if (is.na(next_sig)) next
    next_exec <- all_dates[all_dates > next_sig][1]
    if (is.na(next_exec)) next

    fac   <- FACTORS[Date == sig_d, .(Ticker, Score)]
    # Compute return from exec_d to next_exec
    rets <- RAWDATA[Date >= exec_d & Date <= next_exec & Ticker %in% fac$Ticker,
                    .(Period_Ret = prod(1 + Ret, na.rm=TRUE) - 1), by = Ticker]
    merged <- merge(fac, rets, by = "Ticker")
    if (nrow(merged) < 10) next

    ic_val <- tryCatch(
      cor(rank(merged$Score), rank(merged$Period_Ret), method = "spearman"),
      error = function(e) NA_real_
    )
    ic_rows[[length(ic_rows) + 1]] <- data.table(
      Signal_Date = sig_d, N_stocks = nrow(merged), IC = ic_val
    )
  }
  IC_DT <- rbindlist(ic_rows)
  if (nrow(IC_DT) > 0) {
    IC_DT[, IC_MA6 := frollmean(IC, n = 6, align = "right", na.rm = TRUE)]
    icir <- IC_DT[, mean(IC, na.rm=TRUE) / sd(IC, na.rm=TRUE)]
    ic_mean <- IC_DT[, mean(IC, na.rm=TRUE)]
    report$IC_Mean <- round(ic_mean, 4)
    report$ICIR    <- round(icir, 4)
    report$IC_Pos_Rate <- round(IC_DT[, mean(IC > 0, na.rm=TRUE)], 4)
    fwrite(IC_DT, file.path(output_dir, "analysis_ic.csv"))
    cat(sprintf("  IC: %.4f (ICIR: %.3f, pos_rate: %.1f%%)\n",
                ic_mean, icir, report$IC_Pos_Rate * 100))
  }

  # ── 1B. Fama-MacBeth Cross-Sectional Regression ─────────────────────────
  # Ret_forward ~ Score + ln(Size) + Ret_12m, with Newey-West t-stats
  fmb_rows <- list()
  all_dates_fmb <- all_dates

  for (i in seq_along(signal_dates)) {
    sig_d <- signal_dates[i]
    exec_d <- all_dates_fmb[all_dates_fmb > sig_d][1]
    if (is.na(exec_d)) next
    next_sig <- if (i < length(signal_dates)) signal_dates[i + 1] else NA_Date_
    if (is.na(next_sig)) next
    next_exec <- all_dates_fmb[all_dates_fmb > next_sig][1]
    if (is.na(next_exec)) next

    fac <- FACTORS[Date == sig_d, .(Ticker, Score)]
    rets <- RAWDATA[Date >= exec_d & Date <= next_exec & Ticker %in% fac$Ticker,
                    .(Period_Ret = prod(1 + Ret, na.rm=TRUE) - 1), by = Ticker]

    # Controls: ln(Size) at signal date, trailing 12M return
    size_dt <- RAWDATA[Date == sig_d & Ticker %in% fac$Ticker, .(Ticker, Size)]
    idx_fmb <- which(all_dates_fmb == sig_d)
    lb_fmb  <- all_dates_fmb[max(1, idx_fmb - 252)]
    mom_dt  <- RAWDATA[Date >= lb_fmb & Date <= sig_d & Ticker %in% fac$Ticker,
                       .(Ret_12m = prod(1 + Ret, na.rm=TRUE) - 1), by = Ticker]

    m <- merge(fac, rets, by = "Ticker")
    m <- merge(m, size_dt, by = "Ticker", all.x = TRUE)
    m <- merge(m, mom_dt, by = "Ticker", all.x = TRUE)
    m <- m[!is.na(Period_Ret) & !is.na(Score) & !is.na(Size) & Size > 0 & !is.na(Ret_12m)]
    if (nrow(m) < 30) next

    m[, ln_Size := log(Size)]
    # Standardize for comparability
    m[, Score_z  := (Score - mean(Score)) / max(sd(Score), 1e-8)]
    m[, Size_z   := (ln_Size - mean(ln_Size)) / max(sd(ln_Size), 1e-8)]
    m[, Mom_z    := (Ret_12m - mean(Ret_12m)) / max(sd(Ret_12m), 1e-8)]

    fit <- tryCatch(lm(Period_Ret ~ Score_z + Size_z + Mom_z, data = m), error = function(e) NULL)
    if (is.null(fit)) next

    coefs <- coef(fit)
    fmb_rows[[length(fmb_rows) + 1]] <- data.table(
      Signal_Date = sig_d, N = nrow(m),
      Lambda_Intercept = coefs[1], Lambda_Score = coefs[2],
      Lambda_Size = coefs[3], Lambda_Mom = coefs[4],
      R2 = summary(fit)$r.squared
    )
  }

  FMB_DT <- rbindlist(fmb_rows)
  if (nrow(FMB_DT) > 5) {
    # Newey-West t-stat (Bartlett kernel, lag = floor(T^(1/3)))
    .nw_tstat <- function(x) {
      x <- x[!is.na(x)]; T_n <- length(x)
      if (T_n < 5) return(NA_real_)
      x_bar <- mean(x)
      L <- max(1, floor(T_n^(1/3)))
      gamma_0 <- var(x)
      nw_var <- gamma_0
      for (j in seq_len(L)) {
        g_j <- cov(x[1:(T_n-j)], x[(j+1):T_n])
        nw_var <- nw_var + 2 * (1 - j/(L+1)) * g_j
      }
      x_bar / sqrt(max(nw_var / T_n, 1e-20))
    }

    fmb_summary <- data.table(
      Variable = c("Intercept", "Score", "Size", "Momentum"),
      Lambda_Mean = c(mean(FMB_DT$Lambda_Intercept, na.rm=TRUE),
                      mean(FMB_DT$Lambda_Score, na.rm=TRUE),
                      mean(FMB_DT$Lambda_Size, na.rm=TRUE),
                      mean(FMB_DT$Lambda_Mom, na.rm=TRUE)),
      t_stat_NW = c(.nw_tstat(FMB_DT$Lambda_Intercept),
                     .nw_tstat(FMB_DT$Lambda_Score),
                     .nw_tstat(FMB_DT$Lambda_Size),
                     .nw_tstat(FMB_DT$Lambda_Mom)),
      Avg_R2 = mean(FMB_DT$R2, na.rm=TRUE)
    )
    fmb_summary[, Significant := abs(t_stat_NW) >= 1.96]

    fwrite(FMB_DT, file.path(output_dir, "analysis_fmb.csv"))
    fwrite(fmb_summary, file.path(output_dir, "analysis_fmb_summary.csv"))

    report$FMB_Score_Lambda <- round(fmb_summary[Variable == "Score"]$Lambda_Mean, 6)
    report$FMB_Score_tstat  <- round(fmb_summary[Variable == "Score"]$t_stat_NW, 3)
    report$FMB_Avg_R2       <- round(mean(FMB_DT$R2, na.rm=TRUE), 4)

    sig_mark <- ifelse(fmb_summary[Variable == "Score"]$Significant, "*", "")
    cat(sprintf("  FMB: Score lambda=%.5f (NW t=%.2f%s) | Size t=%.2f | Mom t=%.2f | R2=%.3f\n",
                fmb_summary[Variable=="Score"]$Lambda_Mean,
                fmb_summary[Variable=="Score"]$t_stat_NW, sig_mark,
                fmb_summary[Variable=="Size"]$t_stat_NW,
                fmb_summary[Variable=="Momentum"]$t_stat_NW,
                mean(FMB_DT$R2, na.rm=TRUE)))
  }

  # ── 2. Rolling Performance ───────────────────────────────────────────────
  # 최적화: rollapply(O(N*window)) → hurdle_gate_perf.cpp / R frollmean 벡터화
  # Rcpp 가용 시: rolling_sharpe_cpp + rolling_mdd_cpp (O(N) / O(N*window) but C++)
  # Rcpp 미가용 시: frollsum + frollapply (R fallback)
  .sa_rcpp_ok <- exists("rolling_sharpe_cpp") && is.function(rolling_sharpe_cpp)

  compute_rolling <- function(ret_xts, window_days) {
    n <- length(ret_xts)
    if (n < window_days) return(NULL)
    ret_v <- as.numeric(ret_xts)
    dates_v <- index(ret_xts)

    if (.sa_rcpp_ok) {
      # Rcpp O(N) rolling Sharpe + O(N*window) rolling MDD in C++
      roll_sharpe_v <- rolling_sharpe_cpp(ret_v, window_days, ann_factor = 252)
      roll_mdd_v    <- rolling_mdd_cpp(ret_v, window_days)
    } else {
      # data.table 벡터화 (frollsum for log-CAGR, frollapply for MDD)
      log1r       <- log1p(pmax(ret_v, -0.9999))
      sum_log     <- data.table::frollsum(log1r, n = window_days, na.rm = TRUE, align = "right")
      cagr_v      <- expm1(sum_log * 252 / window_days)
      # frollapply: N 우선 (data.table >= 1.15), n fallback
      .froll_sd <- tryCatch(
        data.table::frollapply(ret_v, N = window_days, align = "right",
                               FUN = function(v) sd(v, na.rm = TRUE)),
        error = function(e)
          data.table::frollapply(ret_v, n = window_days, align = "right",
                                 FUN = function(v) sd(v, na.rm = TRUE))
      )
      ann_vol_v     <- .froll_sd * sqrt(252)
      roll_sharpe_v <- ifelse(!is.na(ann_vol_v) & ann_vol_v > 1e-8,
                              cagr_v / ann_vol_v, NA_real_)
      .mdd_fn <- function(v) {
        nav <- cumprod(1 + v); pk <- cummax(nav)
        max((pk - nav) / pk, na.rm = TRUE)
      }
      roll_mdd_v <- tryCatch(
        data.table::frollapply(ret_v, N = window_days, align = "right", FUN = .mdd_fn),
        error = function(e)
          data.table::frollapply(ret_v, n = window_days, align = "right", FUN = .mdd_fn)
      )
    }

    data.table(Date   = dates_v,
               Sharpe = as.numeric(roll_sharpe_v),
               MDD    = as.numeric(roll_mdd_v))
  }

  roll_1y <- compute_rolling(strat_xts, 252)
  roll_3y <- compute_rolling(strat_xts, 756)
  if (!is.null(roll_1y)) {
    report$Rolling1Y_Sharpe_Mean <- round(mean(roll_1y$Sharpe, na.rm=TRUE), 3)
    report$Rolling1Y_Sharpe_PosRate <- round(mean(roll_1y$Sharpe > 0, na.rm=TRUE), 3)
  }
  if (!is.null(roll_3y)) {
    report$Rolling3Y_Sharpe_Mean <- round(mean(roll_3y$Sharpe, na.rm=TRUE), 3)
  }

  # Combine and save
  if (!is.null(roll_1y) && !is.null(roll_3y)) {
    setnames(roll_1y, c("Sharpe","MDD"), c("Sharpe_1Y","MDD_1Y"))
    setnames(roll_3y, c("Sharpe","MDD"), c("Sharpe_3Y","MDD_3Y"))
    roll_dt <- merge(roll_1y, roll_3y[, .(Date, Sharpe_3Y, MDD_3Y)], by="Date", all=TRUE)
    fwrite(roll_dt, file.path(output_dir, "analysis_rolling.csv"))
  }

  # ── 3. Stress Period Analysis ────────────────────────────────────────────
  stress_periods <- list(
    list(name="GFC_2008",    start="2007-10-01", end="2009-03-31"),
    list(name="COVID_2020",  start="2020-01-01", end="2020-06-30"),
    list(name="Rate_2022",   start="2022-01-01", end="2022-12-31"),
    list(name="DotCom_2002", start="2001-09-01", end="2002-12-31"),
    list(name="EuDebt_2011", start="2010-12-01", end="2012-03-31")
  )
  stress_rows <- list()
  for (sp in stress_periods) {
    s <- as.Date(sp$start); e <- as.Date(sp$end)
    r_s <- strat_xts[paste0(s, "/", e)]
    r_b <- bm_xts[paste0(s, "/", e)]
    if (length(r_s) < 20) next
    cumr_s <- prod(1 + r_s, na.rm=TRUE) - 1
    cumr_b <- prod(1 + r_b, na.rm=TRUE) - 1
    mdd_s  <- as.numeric(maxDrawdown(r_s))
    stress_rows[[length(stress_rows)+1]] <- data.table(
      Period   = sp$name,
      Start    = s, End = e,
      Strat_Ret  = round(cumr_s * 100, 2),
      BM_Ret     = round(cumr_b * 100, 2),
      Alpha      = round((cumr_s - cumr_b) * 100, 2),
      Strat_MDD  = round(mdd_s * 100, 2),
      Outperform = cumr_s > cumr_b
    )
  }
  if (length(stress_rows) > 0) {
    stress_dt <- rbindlist(stress_rows)
    report$Stress_Outperform_Rate <- round(mean(stress_dt$Outperform), 2)
    fwrite(stress_dt, file.path(output_dir, "analysis_stress.csv"))
    cat("  Stress Periods:\n")
    for (r in seq_len(nrow(stress_dt))) {
      cat(sprintf("    %s: Strat %.1f%% vs BM %.1f%% | Alpha %.1f%%\n",
                  stress_dt$Period[r], stress_dt$Strat_Ret[r],
                  stress_dt$BM_Ret[r], stress_dt$Alpha[r]))
    }
  }

  # ── 4. Sector Concentration ──────────────────────────────────────────────
  if (!is.null(hold_log) && nrow(hold_log) > 0 &&
      all(c("Signal_Date","Sector","Weight") %in% names(hold_log))) {
    sector_dt <- hold_log[, .(
      Total_Weight = sum(Weight, na.rm=TRUE),
      N_stocks     = .N
    ), by = .(Signal_Date, Sector)]
    sector_dt[, HHI := sum(Total_Weight^2, na.rm=TRUE), by = Signal_Date]
    fwrite(sector_dt, file.path(output_dir, "analysis_sector.csv"))
    report$Avg_Sector_HHI <- round(sector_dt[, mean(HHI, na.rm=TRUE)], 4)
  }

  # ── 5. Turnover Rate (from holdings log) ─────────────────────────────────
  if (!is.null(hold_log) && nrow(hold_log) > 0) {
    dates_seq <- sort(unique(hold_log$Signal_Date))
    turnover_rows <- list()
    for (i in seq(2, length(dates_seq))) {
      d_prev <- dates_seq[i-1]; d_curr <- dates_seq[i]
      t_prev <- hold_log[Signal_Date == d_prev]$Ticker
      t_curr <- hold_log[Signal_Date == d_curr]$Ticker
      n_common <- length(intersect(t_prev, t_curr))
      n_total  <- length(union(t_prev, t_curr))
      turnover_rows[[i]] <- data.table(
        Date = d_curr,
        Turnover_Rate = 1 - n_common / max(length(t_prev), 1),
        N_New = length(setdiff(t_curr, t_prev)),
        N_Out = length(setdiff(t_prev, t_curr))
      )
    }
    to_dt <- rbindlist(turnover_rows, fill=TRUE)
    to_dt <- to_dt[!is.na(Date)]
    report$Avg_Turnover_Rate <- round(mean(to_dt$Turnover_Rate, na.rm=TRUE), 3)
    fwrite(to_dt, file.path(output_dir, "analysis_holdings.csv"))
  }

  # ── 6. Multi-Factor Regression (FF3 / FF5 / Carhart 4F) ─────────────────
  mf_results <- NULL
  kr_factor_file <- file.path(FUNC_PATH %||% dirname(sys.frame(1)$ofile %||% "."),
                               "factor_portfolios.R")
  if (!exists("FUNC_PATH")) {
    kr_factor_file <- file.path(dirname(dirname(output_dir)), "02_Infrastructure", "factor_portfolios.R")
  }
  if (file.exists(kr_factor_file)) {
    tryCatch({
      source(kr_factor_file, local = TRUE)
      if (file.exists(KR_FACTOR_CACHE)) {
        factor_dt <- load_kr_factor_returns()
        mf_results <- run_multifactor_regression(strat_xts, bm_xts, factor_dt)

        if (!is.null(mf_results)) {
          # Save detailed results
          mf_rows <- list()
          for (nm in names(mf_results)) {
            r <- mf_results[[nm]]
            mf_rows[[nm]] <- data.table(
              Model = r$model,
              Alpha_Monthly = r$alpha,
              Alpha_Annual_Pct = r$alpha * 12 * 100,
              Alpha_tstat = r$alpha_tstat,
              Alpha_pval = r$alpha_pval,
              Adj_R2 = r$adj_r2,
              N_obs = r$n_obs
            )
          }
          mf_summary <- rbindlist(mf_rows)
          fwrite(mf_summary, file.path(output_dir, "analysis_multifactor.csv"))

          # Store best alpha for report
          best <- mf_results[[names(mf_results)[1]]]
          report$MF_Alpha_Ann <- round(best$alpha * 12 * 100, 2)
          report$MF_Alpha_tstat <- round(best$alpha_tstat, 3)
          report$MF_Best_Model <- best$model
          report$MF_Adj_R2 <- round(best$adj_r2, 4)
        }
      } else {
        cat("  [multifactor] Factor cache not built yet. Run build_kr_factor_returns() first.\n")
      }
    }, error = function(e) {
      cat(sprintf("  [multifactor] Skipped: %s\n", e$message))
    })
  }

  # ── 7. Risk Audit — Lawbook v1.4.2 Ch.07 D/F/G ──────────────────────────

  # (D) Liquidity Check: flag holdings with low trading volume
  if (!is.null(hold_log) && nrow(hold_log) > 0 && "Ticker" %in% names(hold_log)) {
    tryCatch({
      liq_rows <- list()
      for (sd in sort(unique(hold_log$Signal_Date))) {
        sd_date <- as.Date(sd, origin = "1970-01-01")
        tickers <- hold_log[Signal_Date == sd_date, Ticker]

        # 20-day average volume at signal date
        vol_20d <- RAWDATA[Ticker %in% tickers & Date <= sd_date][
          order(Date), tail(.SD, 20), by = Ticker][
          , .(AvgVol20 = mean(Vol, na.rm = TRUE),
              AvgTurnover20 = mean(Vol * Close, na.rm = TRUE)), by = Ticker]

        if (nrow(vol_20d) > 0) {
          # Flag: bottom 10% of volume → illiquid
          q10 <- quantile(vol_20d$AvgVol20, 0.10, na.rm = TRUE)
          vol_20d[, Illiquid := AvgVol20 <= q10]
          n_illiq <- sum(vol_20d$Illiquid)
          liq_rows[[length(liq_rows) + 1]] <- data.table(
            Signal_Date = sd_date,
            N_Holdings = length(tickers),
            N_Illiquid = n_illiq,
            Illiq_Pct  = round(n_illiq / max(length(tickers), 1) * 100, 1),
            Median_AvgVol20 = median(vol_20d$AvgVol20, na.rm = TRUE)
          )
        }
      }
      if (length(liq_rows) > 0) {
        liq_dt <- rbindlist(liq_rows)
        report$Avg_Illiquid_Pct <- round(mean(liq_dt$Illiq_Pct, na.rm = TRUE), 1)
        fwrite(liq_dt, file.path(output_dir, "analysis_liquidity.csv"))
        cat(sprintf("  Liquidity: avg %.1f%% illiquid holdings\n", report$Avg_Illiquid_Pct))
      }
    }, error = function(e) cat(sprintf("  [liquidity] Skipped: %s\n", e$message)))
  }

  # (F) Crowding / Factor Popularity Risk
  # Measure: overlap of portfolio holdings with popular factor ETFs / indices
  # Proxy: how many of the portfolio's top-N holdings appear in >50% of rebalances
  if (!is.null(hold_log) && nrow(hold_log) > 0) {
    tryCatch({
      all_dates <- sort(unique(hold_log$Signal_Date))
      if (length(all_dates) >= 6) {
        ticker_freq <- hold_log[, .(Appearances = .N), by = Ticker]
        n_periods <- length(all_dates)
        ticker_freq[, Freq_Pct := Appearances / n_periods]

        # Persistent holdings (appear >75% of time) = potential crowded names
        n_persistent <- sum(ticker_freq$Freq_Pct > 0.75)
        n_common     <- sum(ticker_freq$Freq_Pct > 0.50)

        report$N_Persistent_75 <- n_persistent
        report$N_Common_50     <- n_common
        report$Crowding_Risk   <- if (n_persistent > 15) "HIGH" else if (n_persistent > 8) "MEDIUM" else "LOW"

        fwrite(ticker_freq[order(-Freq_Pct)],
               file.path(output_dir, "analysis_crowding.csv"))
        cat(sprintf("  Crowding: %d persistent (>75%%), %d common (>50%%) → %s risk\n",
                    n_persistent, n_common, report$Crowding_Risk))
      }
    }, error = function(e) cat(sprintf("  [crowding] Skipped: %s\n", e$message)))
  }

  # (G) Sample Alignment Check: verify strategy and benchmark date ranges match
  tryCatch({
    strat_dates <- index(strat_xts)
    bm_dates    <- index(bm_xts)
    overlap     <- intersect(as.character(strat_dates), as.character(bm_dates))
    strat_only  <- setdiff(as.character(strat_dates), as.character(bm_dates))
    bm_only     <- setdiff(as.character(bm_dates), as.character(strat_dates))

    report$Sample_Overlap   <- length(overlap)
    report$Sample_StratOnly <- length(strat_only)
    report$Sample_BMOnly    <- length(bm_only)
    report$Sample_Aligned   <- length(strat_only) == 0 && length(bm_only) == 0

    sample_dt <- data.table(
      Metric = c("Strat_Start", "Strat_End", "BM_Start", "BM_End",
                  "Overlap_Days", "Strat_Only", "BM_Only", "Aligned"),
      Value = c(as.character(min(strat_dates)), as.character(max(strat_dates)),
                as.character(min(bm_dates)), as.character(max(bm_dates)),
                length(overlap), length(strat_only), length(bm_only),
                length(strat_only) == 0 && length(bm_only) == 0)
    )
    fwrite(sample_dt, file.path(output_dir, "analysis_sample_alignment.csv"))

    if (length(strat_only) > 0 || length(bm_only) > 0) {
      cat(sprintf("  Sample: %d overlap, %d strat-only, %d bm-only → MISALIGNED\n",
                  length(overlap), length(strat_only), length(bm_only)))
    } else {
      cat(sprintf("  Sample: %d days fully aligned\n", length(overlap)))
    }
  }, error = function(e) cat(sprintf("  [sample] Skipped: %s\n", e$message)))

  # ── 7B. Defense Analysis ─────────────────────────────────────────────────
  # role_label == "defense" 또는 호출 시 defense_mode = TRUE 시 실행
  # 출력: analysis_defense.csv (8구간 stress alpha, CAPM beta, bad_ic_ratio, core 상관)
  defense_mode <- isTRUE(getOption("analyzer.defense_mode")) ||
    (exists("role_label") && identical(role_label, "defense"))

  if (defense_mode) {
    cat("  [defense] Running defense-specific analysis...\n")
    def_rows <- list()

    # ── 8대 스트레스 구간 alpha ─────────────────────────────────────────────
    def_stress_periods <- list(
      list(name = "Terror_9_11",    start = "2001-09-01", end = "2001-12-31"),
      list(name = "GFC",            start = "2007-10-01", end = "2009-03-31"),
      list(name = "Euro_Debt",      start = "2011-07-01", end = "2011-12-31"),
      list(name = "China_Shock",    start = "2015-06-01", end = "2016-02-29"),
      list(name = "US_China_Trade", start = "2018-03-01", end = "2018-12-31"),
      list(name = "COVID",          start = "2020-01-01", end = "2020-06-30"),
      list(name = "Rate_Hike",      start = "2022-01-01", end = "2022-12-31"),
      list(name = "Iran_War",       start = "2026-02-01", end = "2026-04-30")
    )

    for (sp in def_stress_periods) {
      s <- as.Date(sp$start); e <- as.Date(sp$end)
      r_s <- strat_xts[paste0(s, "/", e)]
      r_b <- bm_xts[paste0(s, "/", e)]
      if (length(r_s) < 10) {
        def_rows[[length(def_rows) + 1]] <- data.table(
          Period = sp$name, Start = s, End = e,
          Strat_Ret = NA_real_, BM_Ret = NA_real_, Alpha = NA_real_,
          Strat_MDD = NA_real_, Outperform = NA, Obs = 0L
        )
        next
      }
      cumr_s <- prod(1 + r_s, na.rm = TRUE) - 1
      cumr_b <- prod(1 + r_b, na.rm = TRUE) - 1
      mdd_s  <- as.numeric(maxDrawdown(r_s))
      def_rows[[length(def_rows) + 1]] <- data.table(
        Period     = sp$name,
        Start      = s, End = e,
        Strat_Ret  = round(cumr_s * 100, 2),
        BM_Ret     = round(cumr_b * 100, 2),
        Alpha      = round((cumr_s - cumr_b) * 100, 2),
        Strat_MDD  = round(mdd_s * 100, 2),
        Outperform = (cumr_s > cumr_b),
        Obs        = length(r_s)
      )
    }
    def_stress_dt <- rbindlist(def_rows, fill = TRUE)

    # ── CAPM beta (expanding window, PIT 준수) ──────────────────────────────
    # C9: t-1 lag 불필요 (방향측정용 통계, grade 판정용 아님)
    capm_beta <- tryCatch({
      m_xts <- merge(strat_xts, bm_xts)
      m_xts <- m_xts[complete.cases(as.data.frame(m_xts)), ]
      if (nrow(m_xts) >= 60) {
        coef(lm(as.numeric(m_xts[, 1]) ~ as.numeric(m_xts[, 2])))[2]
      } else NA_real_
    }, error = function(e) NA_real_)

    # ── Bad IC ratio (IC < 0 비율, 방어 팩터는 낮을수록 좋음) ──────────────
    bad_ic_ratio <- if (exists("IC_DT") && nrow(IC_DT) > 0) {
      round(mean(IC_DT$IC < 0, na.rm = TRUE), 3)
    } else NA_real_

    # ── Core 전략 상관 (HOLDINGS_LOG 기반 overlap) ──────────────────────────
    # Grade A core 전략 catalog에서 상관 추정 (ticker 레벨 overlap)
    core_overlap <- NA_real_
    tryCatch({
      catalog_path <- file.path(
        dirname(dirname(output_dir)), "04_Research", "grade_a_catalog.json"
      )
      if (!file.exists(catalog_path)) {
        catalog_path <- file.path(
          Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
          "04_Research", "grade_a_catalog.json"
        )
      }
      if (file.exists(catalog_path) && !is.null(hold_log) && nrow(hold_log) > 0) {
        catalog <- tryCatch(jsonlite::fromJSON(catalog_path, simplifyVector = FALSE),
                            error = function(e) list())
        core_entries <- Filter(function(x) identical(x$role, "core"), catalog)
        if (length(core_entries) > 0) {
          # 최근 리밸런스 기준 ticker overlap 계산
          last_date <- max(hold_log$Signal_Date, na.rm = TRUE)
          def_tickers <- hold_log[Signal_Date == last_date, Ticker]
          overlaps <- numeric(0)
          for (ce in core_entries) {
            ce_dir <- ce$output_dir %||% ""
            hold_path <- file.path(ce_dir, "holdings_detail.csv")
            if (file.exists(hold_path)) {
              core_hold <- tryCatch(fread(hold_path), error = function(e) NULL)
              if (!is.null(core_hold) && "Ticker" %in% names(core_hold)) {
                last_core_d <- max(core_hold$Signal_Date, na.rm = TRUE)
                core_tickers <- core_hold[Signal_Date == last_core_d, Ticker]
                n_common <- length(intersect(def_tickers, core_tickers))
                n_union  <- length(union(def_tickers, core_tickers))
                if (n_union > 0) overlaps <- c(overlaps, n_common / n_union)
              }
            }
          }
          if (length(overlaps) > 0) core_overlap <- round(mean(overlaps), 3)
        }
      }
    }, error = function(e) NULL)

    # ── 집계 & 저장 ───────────────────────────────────────────────────────
    outperf_rate <- mean(def_stress_dt$Outperform, na.rm = TRUE)
    def_summary <- data.table(
      CAPM_Beta          = round(capm_beta, 4),
      Bad_IC_Ratio       = bad_ic_ratio,
      Core_Ticker_Overlap = core_overlap,
      Stress_8_Outperf_Rate = round(outperf_rate, 3),
      Stress_8_N_Outperf = sum(def_stress_dt$Outperform, na.rm = TRUE),
      Stress_8_N_Total   = sum(!is.na(def_stress_dt$Outperform)),
      Grade_Eligible_ADEF  = (!is.na(outperf_rate) && outperf_rate >= 5/8),
      Grade_Eligible_BDEF  = (!is.na(outperf_rate) && outperf_rate >= 3/8)
    )

    fwrite(def_stress_dt, file.path(output_dir, "analysis_defense.csv"))
    fwrite(def_summary,   file.path(output_dir, "analysis_defense_summary.csv"))

    report$Defense_CAPM_Beta          <- round(capm_beta, 4)
    report$Defense_Bad_IC_Ratio       <- bad_ic_ratio
    report$Defense_Core_Overlap       <- core_overlap
    report$Defense_Stress_Outperf     <- round(outperf_rate, 3)
    report$Defense_Grade_Eligible     <- if (!is.na(outperf_rate) && outperf_rate >= 5/8) {
      "A_DEF"
    } else if (!is.na(outperf_rate) && outperf_rate >= 3/8) {
      "B_DEF"
    } else {
      "Below_B_DEF"
    }

    cat(sprintf("  Defense: beta=%.3f | bad_IC=%.1f%% | overlap=%.3f | stress_outperf=%.1f%% → %s\n",
                capm_beta %||% 0, (bad_ic_ratio %||% 0) * 100,
                core_overlap %||% 0, outperf_rate * 100,
                report$Defense_Grade_Eligible))
    cat("  Stress 8-period detail:\n")
    for (r_i in seq_len(nrow(def_stress_dt))) {
      if (!is.na(def_stress_dt$Obs[r_i]) && def_stress_dt$Obs[r_i] > 0) {
        cat(sprintf("    %-18s: Strat %+.1f%% vs BM %+.1f%% | Alpha %+.1f%% | MDD %.1f%%\n",
                    def_stress_dt$Period[r_i],
                    def_stress_dt$Strat_Ret[r_i], def_stress_dt$BM_Ret[r_i],
                    def_stress_dt$Alpha[r_i], def_stress_dt$Strat_MDD[r_i]))
      } else {
        cat(sprintf("    %-18s: (데이터 미확보 — 구간 제외)\n", def_stress_dt$Period[r_i]))
      }
    }
  }

  # ── 8. Markdown Report ───────────────────────────────────────────────────
  lines <- c(
    sprintf("# Strategy Diagnostic Report: %s", strategy_name),
    sprintf("Generated: %s\n", format(Sys.Date())),
    "## Factor Signal Quality",
    sprintf("- **IC Mean:** %.4f | **ICIR:** %.3f | **IC > 0 rate:** %.1f%%",
            report$IC_Mean %||% 0, report$ICIR %||% 0,
            (report$IC_Pos_Rate %||% 0) * 100),
    "",
    "## Rolling Sharpe",
    sprintf("- **1Y Rolling Sharpe (avg):** %.3f | **Positive rate:** %.1f%%",
            report$Rolling1Y_Sharpe_Mean %||% 0,
            (report$Rolling1Y_Sharpe_PosRate %||% 0) * 100),
    sprintf("- **3Y Rolling Sharpe (avg):** %.3f", report$Rolling3Y_Sharpe_Mean %||% 0),
    "",
    "## Stress Periods",
    sprintf("- **Outperform rate vs BM:** %.1f%%",
            (report$Stress_Outperform_Rate %||% 0) * 100),
    "(See analysis_stress.csv for details)",
    "",
    "## Fama-MacBeth Regression",
    sprintf("- **Score lambda:** %.5f | **NW t-stat:** %.3f %s",
            report$FMB_Score_Lambda %||% 0, report$FMB_Score_tstat %||% 0,
            if (!is.null(report$FMB_Score_tstat) && abs(report$FMB_Score_tstat) >= 1.96) "(significant)" else "(not significant)"),
    sprintf("- **Avg Cross-sectional R²:** %.4f", report$FMB_Avg_R2 %||% 0),
    "",
    "## Multi-Factor Alpha",
    sprintf("- **Best Model:** %s | **Alpha:** %.2f%%/yr (t=%.3f) %s | **Adj R²:** %.4f",
            report$MF_Best_Model %||% "N/A",
            report$MF_Alpha_Ann %||% 0, report$MF_Alpha_tstat %||% 0,
            if (!is.null(report$MF_Alpha_tstat) && abs(report$MF_Alpha_tstat) >= 1.96) "(significant)" else "",
            report$MF_Adj_R2 %||% 0),
    "",
    "## Portfolio Characteristics",
    sprintf("- **Avg Sector HHI:** %.4f (lower = more diversified)",
            report$Avg_Sector_HHI %||% 0),
    sprintf("- **Avg Period Turnover:** %.1f%%",
            (report$Avg_Turnover_Rate %||% 0) * 100),
    "",
    "## Risk Audit (Ch.07 D/F/G)",
    sprintf("- **Avg Illiquid Holdings:** %.1f%%",
            report$Avg_Illiquid_Pct %||% 0),
    sprintf("- **Crowding Risk:** %s (persistent>75%%: %d, common>50%%: %d)",
            report$Crowding_Risk %||% "N/A",
            report$N_Persistent_75 %||% 0,
            report$N_Common_50 %||% 0),
    sprintf("- **Sample Aligned:** %s (overlap: %d, strat-only: %d, bm-only: %d)",
            if (isTRUE(report$Sample_Aligned)) "YES" else "NO",
            report$Sample_Overlap %||% 0,
            report$Sample_StratOnly %||% 0,
            report$Sample_BMOnly %||% 0),
    "",
    "## Failure Mode Diagnosis (for SPMR)",
    "- [ ] FMT-01: Structural MDD",
    "- [ ] FMT-02: Factor Degeneration",
    "- [ ] FMT-03: Ensemble Dilution",
    "- [ ] FMT-04: Regime Blindness",
    "- [ ] FMT-05: Turnover Toxicity",
    "- [ ] FMT-06: Korea-Specific Signal Inversion",
    "- [ ] FMT-07: Publication Decay",
    "- [ ] FMT-08: Regime Overfit"
  )

  # Defense 섹션 추가 (defense_mode 활성 시)
  if (isTRUE(defense_mode)) {
    lines <- c(lines, "",
      "## Defense Analysis",
      sprintf("- **CAPM Beta:** %s", if (!is.na(report$Defense_CAPM_Beta %||% NA)) sprintf("%.4f", report$Defense_CAPM_Beta) else "N/A"),
      sprintf("- **Bad IC Ratio (IC<0):** %.1f%%", (report$Defense_Bad_IC_Ratio %||% 0) * 100),
      sprintf("- **Core Ticker Overlap:** %s", if (!is.na(report$Defense_Core_Overlap %||% NA)) sprintf("%.3f", report$Defense_Core_Overlap) else "N/A"),
      sprintf("- **8-Period Stress Outperf:** %.1f%% → Grade Eligible: **%s**",
              (report$Defense_Stress_Outperf %||% 0) * 100,
              report$Defense_Grade_Eligible %||% "N/A"),
      "(See analysis_defense.csv for 8-period detail)"
    )
  }

  writeLines(lines, file.path(output_dir, "analysis_report.md"))
  cat(sprintf("[analyzer] Done. Reports saved to %s/\n", output_dir))
  invisible(report)
}

# Null-coalescing operator (if not already loaded)
if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a)) a else b

cat("[strategy_analyzer] Loaded. Use: run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir)\n")
