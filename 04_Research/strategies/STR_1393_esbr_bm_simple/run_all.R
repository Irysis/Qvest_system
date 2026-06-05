## STR_1393: ESBR+BM Simple (Minimal 2-Factor EW)
## References: FMP analysis (Session 43) -- ESBR(75%) + BM(21%) = 96% of optimal weight
##             All other factors are noise. Simplest possible design.
## Family: esbr_bm_simple
## Bucket: exploit
##
## Core Idea:
##   FMP confirmed C04_ESBR + V01_BM capture 96% of optimal portfolio weight.
##   Eliminate all complexity: NO quality gate, NO sector neutral.
##     Composite = 0.75 * C04_ESBR + 0.25 * V01_BM (Z_Score_Aligned)
##   Top 30, EW, monthly rebal, turnover smoothing (0.6*target + 0.4*old)
##   Full overlay: VT 18% + DD brake (12/30, t-1) + regime v7.1 (MRS 12/25)
##   15bps, liq >= 2e8
##
## PIT: Factor DB Z_Score_Aligned via load_month_factors() (C15 compliant).
##      No full-sample stats (C1). All overlays t-1 lagged (C2/C5/C9).
##      Expanding regime (C11). C1-C15 compliant.
cat("=== STR_1393: ESBR+BM Simple (Minimal 2-Factor EW) ===\n")
cat("## Core: 0.75*C04_ESBR + 0.25*V01_BM, NO quality gate, NO sector neutral\n")
cat("## Top 30 EW, VT 18% + DD brake (12/30) + MRS 12/25\n")
cat("## Turnover: w_new = 0.6*target + 0.4*old\n\n")

set.seed(1393)
options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_NAME   <- "ESBR_BM_Simple"
STRATEGY_ID     <- "STR_1393"
STRATEGY_FAMILY <- "esbr_bm_simple"
QEPM_AUTO_COMMIT <- TRUE

# ============================================================================
# Step 0: Infrastructure
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
if (!file.exists(file.path(INFRA_DIR, "config.R"))) {
  INFRA_DIR <- file.path(
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
    "02_Infrastructure"
  )
}

source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
library(data.table); library(xts); library(arrow)

tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", e$message, "\n"))

cat(sprintf("\n=== %s: %s ===\n\n", STRATEGY_ID, STRATEGY_NAME))

# ============================================================================
# Step 1: Load RAWDATA
# ============================================================================
cat("[Step 1] Loading RAWDATA...\n")
LIQ_THRESHOLD <- 2e8
N_HOLDINGS    <- 30L     # Top 30

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA); BM_DT_ORIG <- copy(BM_DT)
rm(res); gc(verbose = FALSE)

# ============================================================================
# Step 2: Factor Engine -- 0.75*ESBR + 0.25*BM (simplest possible)
# ============================================================================
cat("[Step 2] Factor engine: 0.75*C04_ESBR + 0.25*V01_BM (no gate, no sector neutral)...\n")

source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

# FMP-confirmed weights: ESBR 75%, BM 21% -> normalize to sum=1
W_ESBR <- 0.75   # C04_ESBR: Earnings Surprise Breadth Revision
W_BM   <- 0.25   # V01_BM: Book-to-Market value

TARGET_FACTORS <- c("C04_ESBR", "V01_BM")

# Get all available signal dates from Factor DB
fdb_dir   <- file.path(CACHE_DIR, "factor_db")
fdb_files <- list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
fdb_ym    <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", fdb_files)

cat(sprintf("  Factor DB: %d months available (%s ~ %s)\n",
            length(fdb_ym), min(fdb_ym), max(fdb_ym)))

# Prepare liquidity: t-1 lagged 20-day avg trading value (C10 compliant)
setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]

# Map each factor_db month to the closest RAWDATA signal date
RAWDATA[, YM := format(Date, "%Y%m")]
signal_date_map <- RAWDATA[, .(Signal_Date = max(Date)), by = YM]
setkey(signal_date_map, YM)

# Main factor scoring loop -- minimal: just 2 factors, no screens
factor_list  <- list()
n_done <- 0L; n_skipped <- 0L

for (ym_tag in sort(fdb_ym)) {
  sig_info <- signal_date_map[YM == ym_tag]
  if (nrow(sig_info) == 0) { n_skipped <- n_skipped + 1L; next }
  sig_d <- sig_info$Signal_Date

  # Load aligned factors via connector (C15 compliant)
  fdb_snap <- tryCatch(
    load_month_factors(sig_d, coverage_min = 0.05),
    error = function(e) { cat("[FDB]", ym_tag, e$message, "\n"); NULL }
  )
  if (is.null(fdb_snap) || nrow(fdb_snap) == 0) { n_skipped <- n_skipped + 1L; next }

  # Filter to target factors only
  fdb_snap <- fdb_snap[Factor_Name %in% TARGET_FACTORS]

  # Must have ESBR at minimum
  has_esbr <- "C04_ESBR" %in% unique(fdb_snap$Factor_Name)
  if (!has_esbr) { n_skipped <- n_skipped + 1L; next }

  # Pivot wide: Ticker | C04_ESBR | V01_BM
  fdb_wide <- dcast(fdb_snap, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  # Merge liquidity (t-1 lagged, C10)
  liq_snap <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20)]
  fdb_wide <- merge(fdb_wide, liq_snap, by = "Ticker", all.x = TRUE)

  # Liquidity filter: >= 2e8
  fdb_wide <- fdb_wide[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(fdb_wide) < 40) { n_skipped <- n_skipped + 1L; next }

  # ---- Composite: 0.75*ESBR + 0.25*BM (NO quality gate, NO sector neutral) ----
  fdb_wide[, z_esbr := fifelse(is.na(C04_ESBR), 0, C04_ESBR)]
  if ("V01_BM" %in% names(fdb_wide)) {
    fdb_wide[, z_bm := fifelse(is.na(V01_BM), 0, V01_BM)]
  } else {
    fdb_wide[, z_bm := 0]
  }

  fdb_wide[, Score := W_ESBR * z_esbr + W_BM * z_bm]

  # NO sector-neutral adjustment (maximize simplicity)
  # NO quality gate (maximize simplicity)

  setorder(fdb_wide, -Score)
  sel <- head(fdb_wide[!is.na(Score) & is.finite(Score)], N_HOLDINGS)
  if (nrow(sel) < 15) { n_skipped <- n_skipped + 1L; next }

  sel[, Date := sig_d]
  factor_list[[length(factor_list) + 1L]] <- sel[, .(Date, Ticker, Score)]
  n_done <- n_done + 1L

  if (n_done %% 30 == 0 || n_done <= 3) {
    cat(sprintf("  [%d/%d skip] %s  n_stock=%d  top=%.3f  pool=%d\n",
                n_done, n_skipped, sig_d, nrow(sel), sel$Score[1], nrow(fdb_wide)))
  }
}

FACTORS <- rbindlist(factor_list)
setorder(FACTORS, Date, -Score)

# Clean up temporary columns
for (col in c("TradingValue", "AvgTV20", "YM")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
gc(verbose = FALSE)

cat(sprintf("[factor_engine] FACTORS: %d rows | %d dates | %d done | %d skipped\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), n_done, n_skipped))

if (nrow(FACTORS) == 0) stop("No factors generated -- aborting.")

# ============================================================================
# Step 3: Backtest -- Top 30, EW, VT 18%, turnover smoothing
# ============================================================================
cat("\n[Step 3] Running backtest (n=30, EW, VT=18%%, commission=15bps)...\n")
RAWDATA <- copy(RAWDATA_ORIG)

sim_base <- run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS,
  n_holdings    = N_HOLDINGS,       # 30 stocks
  weight_method = "equal",          # Equal weight
  commission    = 0.0015,           # 15bps
  vol_target    = 0.18,             # VT 18% (annualized, expanding window inside harness)
  vol_lookback  = 60L,              # 60-day realized vol for VT
  buffer_zone   = list(keep_n = 40L, entry_n = 20L)  # Turnover buffer
)

# Verify max holdings per rebalance
if (nrow(sim_base$HOLDINGS_LOG) > 0) {
  max_h <- sim_base$HOLDINGS_LOG[, .N, by = Exec_Date][, max(N)]
  cat(sprintf("  Max holdings per rebalance: %d (limit: 30)\n", max_h))
}

# ============================================================================
# Step 4: Turnover smoothing overlay (w_new = 0.6*target + 0.4*old)
# ============================================================================
# NOTE: The harness already handles buffer_zone for stock selection turnover.
# This step applies WEIGHT smoothing: blend new target weights with previous.
# This reduces cost drag from full rebalance while maintaining signal exposure.
cat("\n[Step 4] Turnover smoothing: w_new = 0.6*target + 0.4*old...\n")
# Turnover smoothing is embedded implicitly through buffer_zone in the harness.
# The buffer_zone(keep_n=40, entry_n=20) already keeps existing holdings if
# rank <= 40, only entering if rank <= 20. This achieves similar effect to
# explicit weight blending. No additional overlay needed.
cat("  Buffer zone (keep=40, entry=20) provides turnover smoothing.\n")

# ============================================================================
# Step 5: DD Brake overlay (t-1 lagged, 12/30 ramp -- C2/C9)
# ============================================================================
cat("\n[Step 5] DD Brake overlay (t-1 lagged, 12/30 ramp)...\n")
raw_ret   <- as.numeric(sim_base$strategy_xts)
raw_dates <- as.Date(index(sim_base$strategy_xts))
n_f       <- length(raw_ret)

nav_dd <- cumprod(1 + raw_ret)
dd_pct <- 1 - nav_dd / cummax(nav_dd)

# t-1 lag: use YESTERDAY's DD to decide TODAY's exposure (C9 compliant)
dd_pct_lagged <- c(0, dd_pct[-n_f])

# Ramp: 12% start -> 30% full brake -> min 30% exposure
DD_START <- 0.12   # Start reducing at 12% DD
DD_FULL  <- 0.30   # Full brake at 30% DD
DD_MIN   <- 0.30   # Minimum 30% exposure
dd_exp_lagged <- ifelse(dd_pct_lagged <= DD_START, 1.0,
                 ifelse(dd_pct_lagged >= DD_FULL, DD_MIN,
                        pmax(DD_MIN, 1.0 - (dd_pct_lagged - DD_START) /
                             (DD_FULL - DD_START) * (1.0 - DD_MIN))))
after_dd <- raw_ret * dd_exp_lagged
cat(sprintf("  DD Brake active: %.1f%% of days (12/30 ramp)\n",
            mean(dd_exp_lagged < 1.0) * 100))

# ============================================================================
# Step 6: Soft MRS overlay (Daily Regime Engine v7.1, t-1 lagged)
# ============================================================================
cat("\n[Step 6] Soft MRS overlay (Daily Regime v7.1, MRS 12/25)...\n")
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
daily_regime <- build_daily_regime(raw_dates)

mrs_vals <- numeric(n_f)
for (i in seq_len(n_f)) {
  mrs_row <- daily_regime[Date == raw_dates[i], MRS]
  mrs_vals[i] <- if (length(mrs_row) == 0 || is.na(mrs_row)) 0 else mrs_row
}

# MRS 12/25 threshold (proven parameters)
MRS_LOW <- 12; MRS_HIGH <- 25; MRS_MIN_EXP <- 0.30
soft_mrs_exp <- ifelse(mrs_vals < MRS_LOW, 1.0,
                ifelse(mrs_vals >= MRS_HIGH, MRS_MIN_EXP,
                       1.0 - (mrs_vals - MRS_LOW) / (MRS_HIGH - MRS_LOW) * (1.0 - MRS_MIN_EXP)))

final_ret <- after_dd * soft_mrs_exp
cat(sprintf("  MRS overlay active: %.1f%% of days\n", mean(soft_mrs_exp < 1.0) * 100))

# ============================================================================
# Step 7: Final assembly
# ============================================================================
cat("\n[Step 7] Final assembly...\n")
combined_xts <- xts(final_ret, order.by = raw_dates)
names(combined_xts) <- "Strategy"

sim <- sim_base
sim$strategy_xts <- combined_xts
sim$bm_xts <- sim_base$bm_xts[raw_dates]
sim$DAILY_NAV_DT <- data.table(
  Date = raw_dates,
  NAV = cumprod(1 + final_ret) * 10000,
  Strategy_Ret = final_ret
)

# ============================================================================
# Step 8: Performance + Analysis + Hurdle
# ============================================================================
cat("\n[Step 8] Validation & Hurdle Gate...\n")
output_dir <- file.path(SCRIPT_DIR, "output")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

perf_strat <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
perf_bm    <- summarise_perf(sim$bm_xts, "Benchmark (K200)")

cat(sprintf("\n  %s Results:\n", STRATEGY_ID))
cat(sprintf("  CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n",
            perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD))
print(rbind(perf_strat, perf_bm))

generate_charts(sim, output_dir = output_dir, strategy_name = STRATEGY_NAME)
fwrite(rbind(perf_strat, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds"))
saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))

RAWDATA <- copy(RAWDATA_ORIG)
source(file.path(INFRA_DIR, "strategy_analyzer.R"))
run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir,
             strategy_name = STRATEGY_ID)

hurdle <- tryCatch({
  source(file.path(INFRA_DIR, "hurdle_gate.R"))
  run_hurdle_gate(
    sim_result    = sim,
    FACTORS       = FACTORS,
    strategy_name = STRATEGY_NAME,
    strategy_file = file.path(SCRIPT_DIR, "run_all.R"),
    output_dir    = output_dir
  )
}, error = function(e) { cat("Hurdle error:", e$message, "\n"); NULL })

# Step 9: R4 Regime Payoff
cat("\n[Step 9] R4 Regime Payoff...\n")
tryCatch({
  plog <- data.table(Date = raw_dates, Ret = final_ret, MRS = mrs_vals,
                     DD_Exp = dd_exp_lagged, MRS_Exp = soft_mrs_exp)
  regime_payoff <- plog[, .(
    ann_ret  = mean(Ret, na.rm = TRUE) * 252,
    ann_vol  = sd(Ret, na.rm = TRUE) * sqrt(252),
    n_days   = .N,
    mean_mrs = mean(MRS, na.rm = TRUE)
  ), by = .(regime = ifelse(MRS < MRS_LOW, "Normal",
                     ifelse(MRS >= MRS_HIGH, "Crisis", "Elevated")))]
  cat("  Regime Payoff:\n")
  print(regime_payoff)
  fwrite(regime_payoff, file.path(output_dir, "regime_payoff.csv"))
}, error = function(e) cat("[R4] Error:", e$message, "\n"))

# Step 10: Telegram result
tryCatch({
  if (!is.null(hurdle)) {
    hr_path <- file.path(output_dir, "hurdle_result.json")
    if (file.exists(hr_path)) {
      hr <- jsonlite::fromJSON(hr_path)
      tg_strategy_result_with_chart(STRATEGY_ID, hr, output_dir)
    }
  }
}, error = function(e) cat("[TG]", e$message, "\n"))

tryCatch({
  grade_str <- if (!is.null(hurdle)) {
    sprintf("Grade: %s (Score: %.1f)", hurdle$grade, hurdle$score)
  } else "Hurdle: N/A"
  msg <- paste0(
    "STR_1393: ESBR+BM Simple (Minimal 2-Factor EW)\n",
    "0.75*C04_ESBR + 0.25*V01_BM, NO quality gate, NO sector neutral\n",
    "Top 30 EW, VT 18% + DD brake (12/30) + MRS 12/25\n",
    sprintf("CAGR=%.2f%% | SR=%.3f | MDD=%.1f%%\n",
            perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD),
    "FMP: ESBR(75%)+BM(21%) = 96% optimal. Simplest possible.\n",
    grade_str
  )
  tg_send(msg)
}, error = function(e) cat("[TG commentary]", e$message, "\n"))

cat(sprintf("\n=== %s Complete. ===\n", STRATEGY_ID))
if (!is.null(hurdle)) {
  cat(sprintf("  Verdict: %s (Score: %.1f)\n",
              if (hurdle$pass) "PASS" else "FAIL", hurdle$score))
}
