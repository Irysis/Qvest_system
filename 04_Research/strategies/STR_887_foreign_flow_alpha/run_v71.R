## STR_887: Foreign Investor Flow Alpha — v7.1 Regime Rebuild
## CHANGES from original:
##   1. Phase 2: factor_engine_v71.R (replaces old MRS gating with regime_engine_v7)
##   2. Phase 6: v7.1 regime exposure overlay (replaces old Soft MRS from FRED_REGIME_CACHE)
##   3. Phase 3: C10 liquidity fix — shift(1L) on AvgTradeVal_20d
##   4. Output to output_v71/
## Original run_all.R is UNTOUCHED.
set.seed(8871)

STRATEGY_NAME <- "Foreign_Flow_Alpha_v71"
STRATEGY_ID   <- "STR_887"

SCRIPT_DIR <- tryCatch({ d <- dirname(sys.frame(1)$ofile); if (d == ".") getwd() else d },
  error = function(e) { args <- commandArgs(trailingOnly = FALSE); file_arg <- grep("--file=", args, value = TRUE)
    if (length(file_arg) > 0) { p <- sub("--file=", "", file_arg[1]); p <- gsub("~+~", " ", p, fixed = TRUE); dirname(p) } else getwd() })
INFRA_DIR <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
cat(sprintf("=== %s: %s ===\n\n", STRATEGY_ID, STRATEGY_NAME))

LIQ_THRESHOLD <- 2e8
N_HOLDINGS <- 20L
VOL_TARGET <- 0.18

# ═══ Phase 1: Load RAWDATA ═══
cat("[Phase 1] Loading RAWDATA...\n")
res <- load_rawdata()
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA); BM_DT_ORIG <- copy(BM_DT)

# ═══ Phase 2: Factor Engine (v7.1 — no old MRS) ═══
cat("[Phase 2] Running factor_engine_v71.R (regime_engine_v7 gating)...\n")
source(file.path(SCRIPT_DIR, "factor_engine_v71.R"))

# ═══ Phase 3: Liquidity Filter (C10 fix: shift(1L)) ═══
cat("[Phase 3] Applying liquidity filter (C10 fix)...\n")
RAWDATA_LIQ <- copy(RAWDATA_ORIG)
RAWDATA_LIQ[, TradeVal := Close * Vol]
setorder(RAWDATA_LIQ, Ticker, Date)
# C10 fix: use LAGGED 20d average (shift 1 day) to avoid same-day liquidity
RAWDATA_LIQ[, AvgTradeVal_20d_raw := frollmean(TradeVal, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
RAWDATA_LIQ[, AvgTradeVal_20d := shift(AvgTradeVal_20d_raw, n = 1L, type = "lag"), by = Ticker]
RAWDATA_LIQ[, YM := format(Date, "%Y-%m")]
liq_monthly <- RAWDATA_LIQ[, .(AvgTradeVal = tail(AvgTradeVal_20d[!is.na(AvgTradeVal_20d)], 1)), by = .(YM, Ticker)]
setkey(liq_monthly, YM, Ticker)

# Apply liquidity filter to FACTORS
FACTORS[, YM := format(Date, "%Y-%m")]
fac_dates <- sort(unique(FACTORS$Date))
filtered_list <- list()
for (dt in fac_dates) {
  dt <- as.Date(dt); ym <- format(dt, "%Y-%m")
  fac_d <- FACTORS[Date == dt]
  liq_m <- liq_monthly[YM == ym]
  if (nrow(liq_m) > 0) {
    liquid <- liq_m[AvgTradeVal >= LIQ_THRESHOLD, Ticker]
    fac_d <- fac_d[Ticker %in% liquid]
  }
  if (nrow(fac_d) >= N_HOLDINGS) {
    filtered_list[[length(filtered_list) + 1]] <- fac_d
  }
}
FACTORS <- rbindlist(filtered_list)
FACTORS[, YM := NULL]
setorder(FACTORS, Date, -Score)
cat(sprintf("  After liquidity filter: %d rows | %d dates\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
rm(RAWDATA_LIQ, liq_monthly); gc()

# ═══ Phase 4: Simulation ═══
cat("[Phase 4] Running monthly simulation...\n")
RAWDATA_sim <- copy(RAWDATA_ORIG); BM_sim <- copy(BM_DT_ORIG)
sim <- run_monthly_simulation(
  RAWDATA_sim, BM_sim, FACTORS,
  n_holdings    = N_HOLDINGS,
  weight_method = "equal",
  commission    = 0.0015,
  buffer_zone   = list(keep_n = 40L, entry_n = 20L),
  vol_target    = 0.25,    # Pre-overlay VT (loose)
  vol_lookback  = 60L
)

# ═══ Phase 5: VT + DD Brake ═══
cat("[Phase 5] Applying VT + DD Brake...\n")
raw_ret   <- as.numeric(sim$strategy_xts)
raw_dates <- as.Date(index(sim$strategy_xts))
n_f       <- length(raw_ret)

# Vol targeting to 18%
port_vol <- zoo::rollapply(raw_ret, width = 60, FUN = sd, fill = NA, align = "right") * sqrt(252)
vt_scale <- ifelse(is.na(port_vol) | port_vol < 0.01, 1.0, pmin(1.0, VOL_TARGET / port_vol))
vt_scale_lagged <- c(1.0, head(vt_scale, -1))  # 1-day lag (C2/C5 fix)
after_vt <- raw_ret * vt_scale_lagged

# DD Brake: start 4%, full 35%, min_exp 30%
nav <- cumprod(1 + after_vt)
dd  <- 1 - nav / cummax(nav)
DD_BRAKE_START <- 0.04; DD_BRAKE_FULL <- 0.35; MIN_EXPOSURE <- 0.30
dd_exp <- ifelse(dd <= DD_BRAKE_START, 1.0,
          ifelse(dd >= DD_BRAKE_FULL, MIN_EXPOSURE,
                 pmax(MIN_EXPOSURE, 1.0 - (dd - DD_BRAKE_START) / (DD_BRAKE_FULL - DD_BRAKE_START) * (1.0 - MIN_EXPOSURE))))
dd_exp_lagged <- c(1.0, head(dd_exp, -1))  # 1-day lag (C2/C5 fix)
after_dd <- after_vt * dd_exp_lagged

# ═══ Phase 6: Regime Engine v7.1 Overlay (REPLACES old Soft MRS) ═══
cat("[Phase 6] Regime Engine v7.1 overlay (replaces old MRS)...\n")

# Load v7 regime (already cached from factor_engine_v71.R)
source(file.path(REGIME_DIR, "regime_engine_v7.R"))
regime_v7 <- build_regime_v7(use_cache = TRUE)

# Build monthly exposure map from v7
regime_exp_map <- regime_v7[, .(apply_month, exposure_v7 = exposure)]
setkey(regime_exp_map, apply_month)

# Map daily dates to monthly regime exposure
daily_ym_f <- format(raw_dates, "%Y-%m")

v7_exposure <- numeric(n_f)
for (i in seq_len(n_f)) {
  exp_row <- regime_exp_map[apply_month == daily_ym_f[i]]
  if (nrow(exp_row) > 0) {
    v7_exposure[i] <- exp_row$exposure_v7[1]
  } else {
    v7_exposure[i] <- 1.0  # No regime data = full exposure (normal)
  }
}

# t-1 lag on regime exposure (C5: overlay signal must be lagged)
v7_exposure_lagged <- c(1.0, head(v7_exposure, -1))

combined_ret <- after_dd * v7_exposure_lagged
combined_xts <- xts(combined_ret, order.by = raw_dates)
names(combined_xts) <- "Strategy"

# Log regime distribution
cat(sprintf("  v7 exposure: mean=%.3f | hedged days (exp<1)=%d/%d (%.1f%%)\n",
            mean(v7_exposure, na.rm = TRUE),
            sum(v7_exposure < 1.0),
            n_f,
            100 * sum(v7_exposure < 1.0) / n_f))

# Rebuild sim object
sim$strategy_xts <- combined_xts
sim$bm_xts <- sim$bm_xts[raw_dates]
sim$DAILY_NAV_DT <- data.table(Date = raw_dates, NAV = cumprod(1 + combined_ret) * 10000, Strategy_Ret = combined_ret)

# ═══ Phase 7: Performance Summary ═══
perf <- summarise_perf(combined_xts, STRATEGY_ID)
cat(sprintf("\n  ═══ %s (v7.1) Results ═══\n", STRATEGY_ID))
cat(sprintf("  CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n", perf$CAGR, perf$Sharpe, perf$MDD))

# ═══ Phase 8: Output + Hurdle ═══
out_dir <- file.path(SCRIPT_DIR, "output_v71", STRATEGY_ID)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
generate_charts(sim, output_dir = out_dir, strategy_name = sprintf("%s: %s (v7.1)", STRATEGY_ID, STRATEGY_NAME))
RAWDATA_a <- copy(RAWDATA_ORIG); FACTORS_a <- copy(FACTORS)
source(file.path(INFRA_DIR, "strategy_analyzer.R"))
run_analysis(sim, FACTORS_a, RAWDATA_a, BM_DT_ORIG, out_dir, strategy_name = STRATEGY_ID)
source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result = sim, strategy_name = STRATEGY_ID, output_dir = out_dir)

tryCatch({
  hr <- jsonlite::fromJSON(file.path(out_dir, "hurdle_result.json"))
  tg_strategy_result_with_chart(STRATEGY_ID, hr, out_dir)
}, error = function(e) cat("[TG]", e$message, "\n"))

cat(sprintf("\n[%s v7.1] Complete.\n", STRATEGY_ID))
