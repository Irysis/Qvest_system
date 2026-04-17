#==============================================================================
# Grade A Strategies × Cascade+BCS Overlay — Batch Comparison
# Runs 3 representative Grade A strategies with regime overlay
# and compares vs original MRS≥30 binary results
#==============================================================================
library(data.table); library(arrow); library(xts)
source("02_Infrastructure/config.R")
source("02_Infrastructure/backtest_harness.R")
source("02_Infrastructure/regime_signal.R")
source("02_Infrastructure/telegram_notify.R")

cat("=== Grade A × Cascade+BCS Batch Test ===\n\n")

# ── Load shared data ──
res <- load_rawdata(); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
REGIME_DT <- load_regime_signal()
BCS_DT <- load_bcs_signal()

# BCS monthly
BCS_DT[, YM := format(Date, "%Y-%m")]
BCS_MONTHLY <- BCS_DT[, .(BCS = tail(BCS, 1),
                            BCS_Q = as.character(tail(BCS_Q, 1))),
                        by = YM]
setkey(BCS_MONTHLY, YM)

# DART
DART_FACTOR_CACHE <- file.path(CACHE_DIR, "fundamental_dart.parquet")
FUND_DT <- as.data.table(read_parquet(DART_FACTOR_CACHE))
setnames(FUND_DT, "bsns_year", "biz_year", skip_absent = TRUE)
FUND_DT[, Factor_Date := as.Date(Factor_Date)]

# Macro regime (for original comparison)
macro_regime_dt <- as.data.table(read_parquet(FRED_REGIME_CACHE))
macro_regime_dt[, YM := substr(Date, 1, 7)]
setkey(macro_regime_dt, YM)

# Shared setup
setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
all_dates <- sort(unique(RAWDATA$Date))
bm_daily <- unique(RAWDATA[, .(Date, BM_Ret)])
setorder(bm_daily, Date)

LOOKBACK <- 252L; MIN_OBS <- 200L; VOL_FLOOR_Q <- 0.05

# ================================================================
# Factor computation function (shared for all variants)
# ================================================================
compute_factors <- function(quarterly_dates, ivol_w, beta_w,
                             gate_type = "none", gate_q = 0.90,
                             use_cascade_bcs = FALSE) {

  factor_list <- list()
  regime_log <- list()

  for (sig_d in quarterly_dates) {
    sig_d <- as.Date(sig_d)
    sig_ym <- format(sig_d, "%Y-%m")
    idx <- which(all_dates == sig_d)

    # Regime handling
    total_cash <- 0
    if (use_cascade_bcs) {
      regime_row <- get_regime_at_date(sig_d, REGIME_DT)
      bcs_row <- BCS_MONTHLY[YM == sig_ym]
      bcs_overlay <- if (nrow(bcs_row) > 0 && !is.na(bcs_row$BCS_Q[1]))
        get_bcs_cash_overlay(bcs_row$BCS_Q[1]) else 0
      total_cash <- pmin(1, regime_row$Cash_Pct + bcs_overlay)
      regime_log[[length(regime_log) + 1]] <- data.table(
        Date = sig_d, YM = sig_ym, Total_Cash = total_cash)
    } else {
      # Original MRS>=30 binary
      macro_row <- macro_regime_dt[YM == sig_ym]
      risk_score <- if (nrow(macro_row) > 0 && !is.na(macro_row$Macro_Risk_Score[1]))
        macro_row$Macro_Risk_Score[1] else 0
      buddha_mode <- if (nrow(macro_row) > 0 && !is.na(macro_row$Buddha_Mode[1]))
        macro_row$Buddha_Mode[1] else FALSE
      vix_regime <- if (nrow(macro_row) > 0 && !is.na(macro_row$VIX_Regime[1]))
        macro_row$VIX_Regime[1] else "normal"
      hard_cashout <- buddha_mode || (risk_score >= 30) ||
                      (vix_regime %in% c("extreme","crisis"))
      if (hard_cashout) next
      regime_log[[length(regime_log) + 1]] <- data.table(
        Date = sig_d, YM = sig_ym, Total_Cash = 0)
    }

    if (total_cash >= 1.0) {
      regime_log[[length(regime_log) + 1]] <- data.table(
        Date = sig_d, YM = sig_ym, Total_Cash = 1)
      next
    }

    # Factor computation
    lb_start <- all_dates[max(1, idx - LOOKBACK)]
    window <- RAWDATA[Date >= lb_start & Date <= sig_d]

    stats <- window[!is.na(Ret) & !is.na(Close), {
      n <- .N
      if (n < MIN_OBS) list(idiovol = NA_real_, beta_raw = NA_real_,
                             avg_vol = NA_real_, ret_12m = NA_real_)
      else {
        bm_w <- bm_daily[Date >= lb_start & Date <= sig_d]
        merged <- merge(data.table(Date = Date, Ret = Ret), bm_w, by = "Date", all.x = TRUE)
        merged <- merged[!is.na(Ret) & !is.na(BM_Ret)]
        if (nrow(merged) < MIN_OBS)
          list(idiovol = NA_real_, beta_raw = NA_real_,
               avg_vol = mean(tail(Vol, 20), na.rm = TRUE),
               ret_12m = prod(1 + Ret, na.rm = TRUE) - 1)
        else {
          fit <- .lm.fit(cbind(1, merged$BM_Ret), merged$Ret)
          list(idiovol = sd(fit$residuals), beta_raw = fit$coefficients[2],
               avg_vol = mean(tail(Vol, 20), na.rm = TRUE),
               ret_12m = prod(1 + Ret, na.rm = TRUE) - 1)
        }
      }
    }, by = Ticker]

    stats <- stats[!is.na(idiovol) & !is.na(beta_raw)]
    stats[, vol_rank := frank(avg_vol, ties.method = "average") / .N]
    stats <- stats[vol_rank > VOL_FLOOR_Q & ret_12m > -0.40]

    # Gate
    if (gate_type != "none") {
      avail_fd <- sort(unique(FUND_DT$Factor_Date))
      valid_fd <- avail_fd[avail_fd <= sig_d]
      if (length(valid_fd) > 0) {
        latest_fd <- max(valid_fd)
        gate_col <- switch(gate_type,
          ccc = "CCC", ag = "AssetGrowth", gpa = "GPA",
          stop("Unknown gate: ", gate_type))

        fund_snap <- FUND_DT[Factor_Date == latest_fd & !is.na(get(gate_col)),
                              .(Ticker, gate_val = get(gate_col))]
        stats <- merge(stats, fund_snap, by = "Ticker", all.x = TRUE)
        n_with <- sum(!is.na(stats$gate_val))
        if (n_with > 50) {
          if (gate_type %in% c("ccc", "ag")) {
            # Remove top 10% (high CCC/AG = bad)
            threshold <- quantile(stats$gate_val[!is.na(stats$gate_val)], gate_q)
            stats <- stats[is.na(gate_val) | gate_val <= threshold]
          } else if (gate_type == "gpa") {
            # Remove bottom 10% (low GPA = bad)
            threshold <- quantile(stats$gate_val[!is.na(stats$gate_val)], 1 - gate_q)
            stats <- stats[is.na(gate_val) | gate_val >= threshold]
          }
        }
      }
    }

    if (nrow(stats) < 30) next

    stats[, beta_shrunk := 0.6 * beta_raw + 0.4 * 1.0]
    .w <- function(x) { q <- quantile(x, c(0.01, 0.99), na.rm = TRUE); pmin(pmax(x, q[1]), q[2]) }
    stats[, idiovol_w := .w(idiovol)]
    stats[, beta_w2 := .w(beta_shrunk)]
    stats[, z_idiovol := -(idiovol_w - mean(idiovol_w)) / sd(idiovol_w)]
    stats[, z_beta := -(beta_w2 - mean(beta_w2)) / sd(beta_w2)]
    stats[, score_raw := z_idiovol * ivol_w + z_beta * beta_w]

    sector_info <- unique(RAWDATA[Date == sig_d, .(Ticker, Sector)])
    stats <- merge(stats, sector_info, by = "Ticker", all.x = TRUE)
    stats[, Score := score_raw - mean(score_raw, na.rm = TRUE), by = Sector]

    stats[, Date := sig_d]
    factor_list[[length(factor_list) + 1]] <- stats[!is.na(Score), .(Date, Ticker, Score)]
  }

  list(FACTORS = rbindlist(factor_list),
       REGIME_LOG = rbindlist(regime_log))
}

# ================================================================
# Define strategy variants
# ================================================================
sig_dates_all <- RAWDATA[, .(Signal_Date = max(Date)), by = YM]
sig_dates_all[, Month := as.integer(substr(YM, 6, 7))]
quarterly_dates <- sort(sig_dates_all[Month %in% c(3, 6, 9, 12)]$Signal_Date)
min_start <- all_dates[min(LOOKBACK + 1L, length(all_dates))]
quarterly_dates <- quarterly_dates[quarterly_dates >= min_start]

strategies <- list(
  list(name = "STR_316", desc = "CCC Q [MRS binary]",
       ivol = 0.5, beta = 0.5, gate = "ccc", cascade = FALSE),
  list(name = "STR_374", desc = "CCC Q [Cascade+BCS]",
       ivol = 0.5, beta = 0.5, gate = "ccc", cascade = TRUE),
  list(name = "STR_303", desc = "AG Q [MRS binary]",
       ivol = 0.4, beta = 0.6, gate = "ag", cascade = FALSE),
  list(name = "STR_375", desc = "AG Q [Cascade+BCS]",
       ivol = 0.4, beta = 0.6, gate = "ag", cascade = TRUE),
  list(name = "STR_269_approx", desc = "NoGate Q [MRS binary]",
       ivol = 0.4, beta = 0.6, gate = "none", cascade = FALSE),
  list(name = "STR_376", desc = "NoGate Q [Cascade+BCS]",
       ivol = 0.4, beta = 0.6, gate = "none", cascade = TRUE)
)

# ================================================================
# Run all variants
# ================================================================
results <- list()

for (s in strategies) {
  cat(sprintf("\n══════ %s: %s ══════\n", s$name, s$desc))

  out <- compute_factors(quarterly_dates, s$ivol, s$beta, s$gate, 0.90, s$cascade)
  FACTORS <- out$FACTORS
  REGIME_LOG <- out$REGIME_LOG

  if (nrow(FACTORS) == 0) {
    cat("  [SKIP] No factors generated.\n")
    next
  }
  setorder(FACTORS, Date, -Score)

  cat(sprintf("  FACTORS: %d rows | %d dates\n", nrow(FACTORS), uniqueN(FACTORS$Date)))

  sim <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS,
                                 n_holdings = 30,
                                 weight_method = "equal",
                                 commission = 0.0015)

  # Apply graduated cash overlay for cascade variants
  if (s$cascade && nrow(REGIME_LOG) > 0) {
    str_xts <- sim$strategy_xts
    str_monthly <- data.table(Date = as.Date(index(str_xts)), Ret = as.numeric(str_xts))
    str_monthly[, YM := format(Date, "%Y-%m")]

    REGIME_LOG[, Signal_YM := YM]
    all_months <- sort(unique(str_monthly$YM))
    signal_yms <- sort(REGIME_LOG$Signal_YM)

    month_cash <- data.table(YM = all_months)
    month_cash[, Cash_Pct := sapply(YM, function(ym) {
      prev <- signal_yms[signal_yms <= ym]
      if (length(prev) == 0) return(0)
      REGIME_LOG[Signal_YM == max(prev)]$Total_Cash[1]
    })]

    str_monthly <- merge(str_monthly, month_cash, by = "YM", all.x = TRUE)
    str_monthly[is.na(Cash_Pct), Cash_Pct := 0]
    str_monthly[, Adj_Ret := Ret * (1 - Cash_Pct)]

    sim$strategy_xts <- xts(str_monthly$Adj_Ret, order.by = str_monthly$Date)
  }

  perf <- summarise_perf(sim$strategy_xts, s$name)
  bm_perf <- summarise_perf(sim$bm_xts, "BM")

  results[[s$name]] <- data.table(
    Strategy = s$name, Desc = s$desc,
    CAGR = perf$CAGR, Sharpe = perf$Sharpe,
    MDD = perf$MDD, AnnVol = perf$AnnVol)

  cat(sprintf("  → CAGR=%.1f%% | Sharpe=%.3f | MDD=%.1f%%\n",
              perf$CAGR, perf$Sharpe, perf$MDD))
}

# ================================================================
# Comparison table
# ================================================================
result_dt <- rbindlist(results)

cat("\n\n═══════════════════════════════════════════════════\n")
cat("          GRADE A × REGIME OVERLAY COMPARISON\n")
cat("═══════════════════════════════════════════════════\n\n")
print(result_dt[, .(Strategy, Desc,
                     CAGR = round(CAGR, 1),
                     Sharpe = round(Sharpe, 3),
                     MDD = round(MDD, 1))])

# Paired comparison
cat("\n=== Paired Comparison (MRS binary → Cascade+BCS) ===\n")
pairs <- list(
  c("STR_316","STR_374"),
  c("STR_303","STR_375"),
  c("STR_269_approx","STR_376")
)
for (p in pairs) {
  if (p[1] %in% result_dt$Strategy && p[2] %in% result_dt$Strategy) {
    r1 <- result_dt[Strategy == p[1]]
    r2 <- result_dt[Strategy == p[2]]
    cat(sprintf("  %s → %s: CAGR %+.1f%%p | Sharpe %+.3f | MDD %+.1f%%p\n",
                p[1], p[2],
                r2$CAGR - r1$CAGR, r2$Sharpe - r1$Sharpe, r2$MDD - r1$MDD))
  }
}

# Save
fwrite(result_dt, file.path(RESEARCH_OUTPUT, "regime_comparison/output/grade_a_cascade_comparison.csv"))

# Telegram
tg_msg <- sprintf(
'<b>📊 Grade A × Cascade+BCS 일괄 비교</b>

<b>CCC Gate (STR_316 base):</b>
  MRS binary: CAGR %.1f%% | Sharpe %.3f | MDD %.1f%%
  Cascade+BCS: CAGR %.1f%% | Sharpe %.3f | MDD %.1f%%

<b>AG Gate (STR_303 base):</b>
  MRS binary: CAGR %.1f%% | Sharpe %.3f | MDD %.1f%%
  Cascade+BCS: CAGR %.1f%% | Sharpe %.3f | MDD %.1f%%

<b>No Gate (STR_269 base):</b>
  MRS binary: CAGR %.1f%% | Sharpe %.3f | MDD %.1f%%
  Cascade+BCS: CAGR %.1f%% | Sharpe %.3f | MDD %.1f%%

<b>패턴:</b> Cascade+BCS = Sharpe↑ + MDD↓ but CAGR↓',
  result_dt[Strategy=="STR_316"]$CAGR, result_dt[Strategy=="STR_316"]$Sharpe, result_dt[Strategy=="STR_316"]$MDD,
  result_dt[Strategy=="STR_374"]$CAGR, result_dt[Strategy=="STR_374"]$Sharpe, result_dt[Strategy=="STR_374"]$MDD,
  result_dt[Strategy=="STR_303"]$CAGR, result_dt[Strategy=="STR_303"]$Sharpe, result_dt[Strategy=="STR_303"]$MDD,
  result_dt[Strategy=="STR_375"]$CAGR, result_dt[Strategy=="STR_375"]$Sharpe, result_dt[Strategy=="STR_375"]$MDD,
  result_dt[Strategy=="STR_269_approx"]$CAGR, result_dt[Strategy=="STR_269_approx"]$Sharpe, result_dt[Strategy=="STR_269_approx"]$MDD,
  result_dt[Strategy=="STR_376"]$CAGR, result_dt[Strategy=="STR_376"]$Sharpe, result_dt[Strategy=="STR_376"]$MDD)
tg_send(tg_msg)

cat("\n=== Batch Complete ===\n")
RAWDATA[, YM := NULL]
