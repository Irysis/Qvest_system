## STR_1333: Value-Earnings Synergy
## 핵심아이디어: BM(V01) + ESBR(C04) 시너지. ESBR gate로 value trap 제거 후 BM scoring.
##   BM Crisis positive + ESBR momentum = 국면 보완. Value family 최초 Grade A 후보.
## Parent: S0_2026-03-24_002 (Scout 설계)
## Academic: Asness et al.(2013), Novy-Marx(2013), Piotroski & So(2012)
## PIT: C4(BM 45d lag, ESBR Date<=sig_d), C13(Z_Score_Aligned), C14(Usable_Date), C15(load_month_factors)
cat("=== STR_1333: Value-Earnings Synergy ===\n")
set.seed(1333); options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
STRATEGY_NAME  <- "ValueEarningsSynergy"
STRATEGY_ID    <- "STR_1333"
STRATEGY_FAMILY <- "value_catalyst"
QEPM_AUTO_COMMIT <- TRUE

# ============================================================================
# Step 0: Path Resolution
# ============================================================================
SCRIPT_DIR <- tryCatch({
  d <- dirname(sys.frame(1)$ofile)
  if (d == ".") getwd() else d
}, error = function(e) {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    p <- sub("--file=", "", file_arg[1])
    p <- gsub("~+~", " ", p, fixed = TRUE)
    dirname(p)
  } else getwd()
})

INFRA_DIR <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))

tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight] ", e$message, "\n"))

# Factor DB connector (C15: load_month_factors() 전용)
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

cat(sprintf("\n=== %s: %s ===\n\n", STRATEGY_ID, STRATEGY_NAME))

# ============================================================================
# Constants
# ============================================================================
LIQ_THRESHOLD   <- 2e8
N_HOLDINGS      <- 30L
ESBR_GATE_PCT   <- 0.50     # ESBR top 50% gate
BM_WEIGHT       <- 1.0       # Score = z(BM) + 0.3 * z(ESBR)
ESBR_WEIGHT     <- 0.3
SECTOR_NEUTRAL  <- TRUE

# ============================================================================
# Phase 1: Load Data
# ============================================================================
cat("[Phase 1] Loading data...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
rm(res); gc(verbose = FALSE)

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
all_dates <- sort(unique(RAWDATA$Date))
all_signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM]$Signal_Date
all_signal_dates <- sort(all_signal_dates)

# Minimum start: Factor DB 가용 시점 이후
monthly_dates <- all_signal_dates[all_signal_dates >= as.Date("2006-01-01")]

# Liquidity filter: t-1 lagged (C10)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]

# ============================================================================
# Phase 2: Factor Construction — BM(V01) gated by ESBR(C04)
# ============================================================================
cat("[Phase 2] Loading Factor DB factors (BM + ESBR)...\n")

z_safe <- function(x) {
  s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-8) return(rep(0, length(x)))
  (x - mean(x, na.rm = TRUE)) / s
}

factor_list <- list()
n_done <- 0L; n_skipped <- 0L

for (sig_d in monthly_dates) {
  sig_d <- as.Date(sig_d)
  gc(verbose = FALSE)

  # C15: load_month_factors() 사용
  fdb <- tryCatch(
    load_month_factors(sig_d),
    error = function(e) NULL
  )
  if (is.null(fdb) || nrow(fdb) == 0) { n_skipped <- n_skipped + 1L; next }

  # Extract BM (V01) and ESBR (C04)
  bm_dt  <- fdb[Factor_Name == "V01_BM", .(Ticker, z_bm = Z_Score_Aligned)]
  esbr_dt <- fdb[Factor_Name == "C04_ESBR", .(Ticker, z_esbr = Z_Score_Aligned)]

  if (nrow(bm_dt) < 50 || nrow(esbr_dt) < 30) { n_skipped <- n_skipped + 1L; next }

  # Merge factors
  scores <- merge(bm_dt, esbr_dt, by = "Ticker", all = FALSE)
  if (nrow(scores) < 30) { n_skipped <- n_skipped + 1L; next }

  # Liquidity filter (C10: t-1 lagged)
  liq_snap <- RAWDATA[Date == sig_d & !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD,
                      .(Ticker, Sector)]
  scores <- merge(scores, liq_snap, by = "Ticker", all = FALSE)
  if (nrow(scores) < 30) { n_skipped <- n_skipped + 1L; next }

  # ESBR Gate: top 50% only (value trap removal)
  esbr_median <- median(scores$z_esbr, na.rm = TRUE)
  scores <- scores[z_esbr >= esbr_median]
  if (nrow(scores) < 20) { n_skipped <- n_skipped + 1L; next }

  # Composite Score: z(BM) + 0.3 * z(ESBR)  (additive only, L-398)
  scores[, Score := BM_WEIGHT * z_bm + ESBR_WEIGHT * z_esbr]

  # Sector neutralization
  if (SECTOR_NEUTRAL) {
    scores[!is.na(Sector), Score := Score - mean(Score, na.rm = TRUE), by = Sector]
  }

  scores[, Date := sig_d]
  factor_list[[length(factor_list) + 1L]] <- scores[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list)
setorder(FACTORS, Date, -Score)
cat(sprintf("[Phase 2] %d dates scored, %d skipped | %s factor rows\n",
            n_done, n_skipped, format(nrow(FACTORS), big.mark = ",")))

# Cleanup
for (col in c("TradingValue", "AvgTV20", "YM"))
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
rm(fdb, bm_dt, esbr_dt, scores, liq_snap, factor_list); gc(verbose = FALSE)

# ============================================================================
# Phase 3: Backtest — S4 Phase 1 Baseline (EW + EW)
# ============================================================================
cat("[Phase 3] Running backtest (Phase 1: EW+EW baseline)...\n")
sim <- run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS,
  n_holdings    = N_HOLDINGS,
  weight_method = "equal",
  commission    = 0.0015,
  buffer_zone   = list(keep_n = 50L, entry_n = 25L),
  vol_target    = 0.20,
  vol_lookback  = 60L
)

# ============================================================================
# Phase 4: DD Brake (t-1 lagged, C2/C5)
# ============================================================================
cat("[Phase 4] DD Brake...\n")
strat_ret   <- as.numeric(sim$strategy_xts)
n_f         <- length(strat_ret)
strat_dates <- as.Date(index(sim$strategy_xts))

nav_vec <- cumprod(1 + strat_ret)
dd_vec  <- 1 - nav_vec / cummax(nav_vec)

DD_START <- 0.15; DD_FULL <- 0.35; DD_MIN_EXP <- 0.30
dd_exposure <- ifelse(dd_vec <= DD_START, 1.0,
                      ifelse(dd_vec >= DD_FULL, DD_MIN_EXP,
                             pmax(DD_MIN_EXP, 1.0 - (dd_vec - DD_START) / (DD_FULL - DD_START) * (1.0 - DD_MIN_EXP))))
dd_exp_lagged <- c(1.0, head(dd_exposure, -1))
after_dd <- strat_ret * dd_exp_lagged

# ============================================================================
# Phase 5: MRS Overlay (Regime Engine v7.1)
# ============================================================================
cat("[Phase 5] MRS Overlay (v7.1)...\n")
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
daily_regime <- build_daily_regime(strat_dates)

MRS_LOW <- 15; MRS_HIGH <- 30; MRS_MIN_EXP <- 0.30
soft_mrs_exp <- numeric(n_f)
for (i in seq_len(n_f)) {
  mrs_val <- daily_regime[Date == strat_dates[i], MRS]
  if (length(mrs_val) == 0 || is.na(mrs_val)) mrs_val <- 0
  if (mrs_val < MRS_LOW)       soft_mrs_exp[i] <- 1.0
  else if (mrs_val >= MRS_HIGH) soft_mrs_exp[i] <- MRS_MIN_EXP
  else soft_mrs_exp[i] <- 1.0 - (mrs_val - MRS_LOW) / (MRS_HIGH - MRS_LOW) * (1.0 - MRS_MIN_EXP)
}
final_ret <- after_dd * soft_mrs_exp

# ============================================================================
# Phase 6: Final Assembly
# ============================================================================
cat("[Phase 6] Final assembly...\n")
combined_xts <- xts::xts(final_ret, order.by = strat_dates)
names(combined_xts) <- "Strategy"

sim$strategy_xts <- combined_xts
sim$bm_xts <- sim$bm_xts[strat_dates]
sim$DAILY_NAV_DT <- data.table(
  Date         = strat_dates,
  NAV          = cumprod(1 + final_ret) * 10000,
  Strategy_Ret = final_ret
)

perf    <- summarise_perf(combined_xts, STRATEGY_ID)
bm_perf <- summarise_perf(sim$bm_xts, "KOSPI200")

cat(sprintf("\n  %s Results\n", STRATEGY_ID))
cat(sprintf("  CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n",
            perf$CAGR, perf$Sharpe, perf$MDD))
print(rbind(perf, bm_perf))

# ============================================================================
# Phase 7: Output + Analysis + Hurdle + Telegram
# ============================================================================
out_dir <- file.path(SCRIPT_DIR, "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))
fwrite(rbind(perf, bm_perf), file.path(out_dir, "performance.csv"))

generate_charts(sim, output_dir = out_dir,
                strategy_name = sprintf("%s: %s", STRATEGY_ID, STRATEGY_NAME))

tryCatch({
  source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, out_dir,
               strategy_name = STRATEGY_ID)
}, error = function(e) cat("[Analysis]", e$message, "\n"))

hurdle <- tryCatch({
  source(file.path(INFRA_DIR, "hurdle_gate.R"))
  run_hurdle_gate(sim_result = sim, strategy_name = STRATEGY_ID,
                  output_dir = out_dir)
}, error = function(e) { cat("Hurdle error:", e$message, "\n"); NULL })

tryCatch({
  if (!is.null(hurdle)) {
    hr <- jsonlite::fromJSON(file.path(out_dir, "hurdle_result.json"))
    tg_strategy_result_with_chart(STRATEGY_ID, hr, out_dir)
  }
}, error = function(e) cat("[TG]", e$message, "\n"))

if (isTRUE(QEPM_AUTO_COMMIT) && exists("hybrid_commit")) {
  tryCatch({
    hybrid_commit(strategy_name = STRATEGY_ID, family = STRATEGY_FAMILY,
                  hurdle_result = hurdle, artifact_paths = list(out_dir))
  }, error = function(e) cat("[QEPM]", e$message, "\n"))
}

cat(sprintf("\n[%s] Complete.\n", STRATEGY_ID))
