## STR_1333 S5 Variant Runner
## 9개 변형 배치 실행 (A1+B2+C2+D1+E1+F2 = 9 variants)
## Base: STR_1333 (CAGR 13.4%, SR 0.857, MDD 34.3%)
cat("=== STR_1333 S5 Variant Runner ===\n")
set.seed(1333); options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

# ============================================================================
# Path & Infra
# ============================================================================
SCRIPT_DIR <- tryCatch({
  d <- dirname(sys.frame(1)$ofile)
  if (d == ".") getwd() else d
}, error = function(e) {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("--file=", args, value = TRUE)
  if (length(file_arg) > 0) dirname(sub("--file=", "", file_arg[1]))
  else getwd()
})

INFRA_DIR <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

# ============================================================================
# Phase 1: Load Data (shared across all variants)
# ============================================================================
cat("[Phase 1] Loading data (shared)...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA_ORIG <- res$RAWDATA; BM_DT <- res$BM_DT
rm(res); gc(verbose = FALSE)

setorder(RAWDATA_ORIG, Ticker, Date)
RAWDATA_ORIG[, YM := format(Date, "%Y-%m")]
all_dates <- sort(unique(RAWDATA_ORIG$Date))
all_signal_dates <- RAWDATA_ORIG[, .(Signal_Date = max(Date)), by = YM]$Signal_Date
monthly_dates <- sort(all_signal_dates[all_signal_dates >= as.Date("2006-01-01")])

RAWDATA_ORIG[, TradingValue := Close * Vol]
RAWDATA_ORIG[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                                 n = 1L, type = "lag"), by = Ticker]

# ============================================================================
# Phase 2: Build FACTORS (shared — same factor construction for all variants)
# ============================================================================
cat("[Phase 2] Building BM+ESBR factors (shared)...\n")
LIQ_THRESHOLD <- 2e8

z_safe <- function(x) {
  s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-8) return(rep(0, length(x)))
  (x - mean(x, na.rm = TRUE)) / s
}

# Build factors with different ESBR weights for F1 variant
build_factors <- function(bm_w = 1.0, esbr_w = 0.3, sector_neutral = TRUE) {
  factor_list <- list()
  n_done <- 0L

  for (sig_d in monthly_dates) {
    sig_d <- as.Date(sig_d)
    fdb <- tryCatch(load_month_factors(sig_d), error = function(e) NULL)
    if (is.null(fdb) || nrow(fdb) == 0) next

    bm_dt  <- fdb[Factor_Name == "V01_BM", .(Ticker, z_bm = Z_Score_Aligned)]
    esbr_dt <- fdb[Factor_Name == "C04_ESBR", .(Ticker, z_esbr = Z_Score_Aligned)]
    if (nrow(bm_dt) < 50 || nrow(esbr_dt) < 30) next

    scores <- merge(bm_dt, esbr_dt, by = "Ticker", all = FALSE)
    if (nrow(scores) < 30) next

    liq_snap <- RAWDATA_ORIG[Date == sig_d & !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD,
                             .(Ticker, Sector)]
    scores <- merge(scores, liq_snap, by = "Ticker", all = FALSE)
    if (nrow(scores) < 30) next

    # ESBR Gate: top 50%
    esbr_median <- median(scores$z_esbr, na.rm = TRUE)
    scores <- scores[z_esbr >= esbr_median]
    if (nrow(scores) < 20) next

    scores[, Score := bm_w * z_bm + esbr_w * z_esbr]
    if (sector_neutral) {
      scores[!is.na(Sector), Score := Score - mean(Score, na.rm = TRUE), by = Sector]
    }
    scores[, Date := sig_d]
    factor_list[[length(factor_list) + 1L]] <- scores[!is.na(Score), .(Date, Ticker, Score)]
    n_done <- n_done + 1L
  }
  FACTORS <- rbindlist(factor_list)
  setorder(FACTORS, Date, -Score)
  cat(sprintf("  Factors built: %d dates | %s rows\n", n_done, format(nrow(FACTORS), big.mark = ",")))
  return(FACTORS)
}

# Standard factors (shared for most variants)
FACTORS_STD <- build_factors(bm_w = 1.0, esbr_w = 0.3, sector_neutral = TRUE)

# ============================================================================
# DD + MRS overlay function
# ============================================================================
apply_overlay <- function(sim, dd_start = 0.15, dd_full = 0.35, dd_min = 0.30,
                          mrs_low = 15, mrs_high = 30, mrs_min = 0.30) {
  strat_ret   <- as.numeric(sim$strategy_xts)
  n_f         <- length(strat_ret)
  strat_dates <- as.Date(index(sim$strategy_xts))

  # DD Brake (t-1 lagged)
  nav_vec <- cumprod(1 + strat_ret)
  dd_vec  <- 1 - nav_vec / cummax(nav_vec)
  dd_exp <- ifelse(dd_vec <= dd_start, 1.0,
                   ifelse(dd_vec >= dd_full, dd_min,
                          pmax(dd_min, 1.0 - (dd_vec - dd_start) / (dd_full - dd_start) * (1.0 - dd_min))))
  dd_exp_lagged <- c(1.0, head(dd_exp, -1))
  after_dd <- strat_ret * dd_exp_lagged

  # MRS Overlay
  source(file.path(REGIME_DIR, "regime_engine_daily.R"))
  daily_regime <- build_daily_regime(strat_dates)
  mrs_exp <- numeric(n_f)
  for (i in seq_len(n_f)) {
    mrs_val <- daily_regime[Date == strat_dates[i], MRS]
    if (length(mrs_val) == 0 || is.na(mrs_val)) mrs_val <- 0
    if (mrs_val < mrs_low)       mrs_exp[i] <- 1.0
    else if (mrs_val >= mrs_high) mrs_exp[i] <- mrs_min
    else mrs_exp[i] <- 1.0 - (mrs_val - mrs_low) / (mrs_high - mrs_low) * (1.0 - mrs_min)
  }
  final_ret <- after_dd * mrs_exp

  combined_xts <- xts::xts(final_ret, order.by = strat_dates)
  names(combined_xts) <- "Strategy"
  sim$strategy_xts <- combined_xts
  sim$bm_xts <- sim$bm_xts[strat_dates]
  sim$DAILY_NAV_DT <- data.table(Date = strat_dates, NAV = cumprod(1 + final_ret) * 10000,
                                  Strategy_Ret = final_ret)
  return(sim)
}

# ============================================================================
# Variant Definitions
# ============================================================================
variants <- list(
  # A1: DD brake 강화 (10/25 → MDD 축소 기대)
  list(id = "A1_DD_tight", n = 30L, wm = "equal", bz = list(keep_n=50L, entry_n=25L),
       vt = 0.20, dd_start = 0.10, dd_full = 0.25, dd_min = 0.30,
       mrs_low = 15, mrs_high = 30, factors = "std", sector_neutral = TRUE),

  # B1: IC-Weighted (ivol as proxy for IC weighting)
  list(id = "B1_ICWeight", n = 30L, wm = "ivol", bz = list(keep_n=50L, entry_n=25L),
       vt = 0.20, dd_start = 0.15, dd_full = 0.35, dd_min = 0.30,
       mrs_low = 15, mrs_high = 30, factors = "std", sector_neutral = TRUE),

  # B2: Risk Parity
  list(id = "B2_RP", n = 30L, wm = "riskparity", bz = list(keep_n=50L, entry_n=25L),
       vt = 0.20, dd_start = 0.15, dd_full = 0.35, dd_min = 0.30,
       mrs_low = 15, mrs_high = 30, factors = "std", sector_neutral = TRUE),

  # C1: MRS tighter 12/25
  list(id = "C1_MRS1225", n = 30L, wm = "equal", bz = list(keep_n=50L, entry_n=25L),
       vt = 0.20, dd_start = 0.15, dd_full = 0.35, dd_min = 0.30,
       mrs_low = 12, mrs_high = 25, factors = "std", sector_neutral = TRUE),

  # C2: MRS aggressive 10/20
  list(id = "C2_MRS1020", n = 30L, wm = "equal", bz = list(keep_n=50L, entry_n=25L),
       vt = 0.20, dd_start = 0.15, dd_full = 0.35, dd_min = 0.30,
       mrs_low = 10, mrs_high = 20, factors = "std", sector_neutral = TRUE),

  # D1: BZ tighter 40/20
  list(id = "D1_BZ4020", n = 30L, wm = "equal", bz = list(keep_n=40L, entry_n=20L),
       vt = 0.20, dd_start = 0.15, dd_full = 0.35, dd_min = 0.30,
       mrs_low = 15, mrs_high = 30, factors = "std", sector_neutral = TRUE),

  # E1: Sector neutral OFF
  list(id = "E1_NoSectNeut", n = 30L, wm = "equal", bz = list(keep_n=50L, entry_n=25L),
       vt = 0.20, dd_start = 0.15, dd_full = 0.35, dd_min = 0.30,
       mrs_low = 15, mrs_high = 30, factors = "nosect", sector_neutral = FALSE),

  # F1: ESBR weight 0.5 (stronger catalyst signal)
  list(id = "F1_ESBR05", n = 30L, wm = "equal", bz = list(keep_n=50L, entry_n=25L),
       vt = 0.20, dd_start = 0.15, dd_full = 0.35, dd_min = 0.30,
       mrs_low = 15, mrs_high = 30, factors = "esbr05", sector_neutral = TRUE),

  # F2: Concentrated 20 holdings
  list(id = "F2_N20", n = 20L, wm = "equal", bz = list(keep_n=30L, entry_n=15L),
       vt = 0.20, dd_start = 0.15, dd_full = 0.35, dd_min = 0.30,
       mrs_low = 15, mrs_high = 30, factors = "std", sector_neutral = TRUE)
)

# Pre-build special factor sets
cat("\n[S5] Building special factor variants...\n")
FACTORS_NOSECT <- build_factors(bm_w = 1.0, esbr_w = 0.3, sector_neutral = FALSE)
FACTORS_ESBR05 <- build_factors(bm_w = 1.0, esbr_w = 0.5, sector_neutral = TRUE)

get_factors <- function(ftype) {
  switch(ftype,
    "std" = FACTORS_STD,
    "nosect" = FACTORS_NOSECT,
    "esbr05" = FACTORS_ESBR05,
    FACTORS_STD
  )
}

# ============================================================================
# Run all variants
# ============================================================================
results <- list()

for (v in variants) {
  cat(sprintf("\n=== Variant %s ===\n", v$id))
  RAWDATA <- copy(RAWDATA_ORIG)
  for (col in c("TradingValue", "AvgTV20", "YM"))
    if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]

  FACTORS <- get_factors(v$factors)

  tryCatch({
    sim <- run_monthly_simulation(
      RAWDATA, BM_DT, FACTORS,
      n_holdings    = v$n,
      weight_method = v$wm,
      commission    = 0.0015,
      buffer_zone   = v$bz,
      vol_target    = v$vt,
      vol_lookback  = 60L
    )

    sim <- apply_overlay(sim, dd_start = v$dd_start, dd_full = v$dd_full, dd_min = v$dd_min,
                         mrs_low = v$mrs_low, mrs_high = v$mrs_high, mrs_min = 0.30)

    perf <- summarise_perf(sim$strategy_xts, v$id)
    results[[v$id]] <- perf
    cat(sprintf("  %s: CAGR=%.2f%% | SR=%.3f | MDD=%.1f%%\n",
                v$id, perf$CAGR, perf$Sharpe, perf$MDD))

    # Save variant sim_result
    v_dir <- file.path(SCRIPT_DIR, paste0("variant_", v$id))
    dir.create(v_dir, showWarnings = FALSE, recursive = TRUE)
    saveRDS(sim, file.path(v_dir, "sim_result.rds"))

    # Hurdle gate for promising variants
    if (perf$Sharpe >= 0.8) {
      tryCatch({
        v_out <- file.path(v_dir, "output")
        dir.create(v_out, showWarnings = FALSE, recursive = TRUE)
        fwrite(perf, file.path(v_out, "performance.csv"))
        generate_charts(sim, output_dir = v_out,
                        strategy_name = sprintf("STR_1333_%s", v$id))
        source(file.path(INFRA_DIR, "hurdle_gate.R"))
        hr <- run_hurdle_gate(sim_result = sim,
                              strategy_name = sprintf("STR_1333_%s", v$id),
                              output_dir = v_out)
        cat(sprintf("  Hurdle: %s (Score %.1f)\n", hr$verdict, hr$score))
      }, error = function(e) cat("  Hurdle error:", e$message, "\n"))
    }
  }, error = function(e) {
    cat(sprintf("  ERROR: %s\n", e$message))
    results[[v$id]] <<- NULL
  })
}

# ============================================================================
# Summary Table
# ============================================================================
cat("\n\n=== STR_1333 S5 VARIANT SUMMARY ===\n")
cat(sprintf("%-20s %8s %8s %8s %8s\n", "Variant", "CAGR%", "Sharpe", "MDD%", "Calmar"))
cat(paste(rep("-", 60), collapse = ""), "\n")
cat(sprintf("%-20s %8.2f %8.3f %8.1f %8.3f\n", "BASE", 13.43, 0.857, 34.3, 0.392))

for (nm in names(results)) {
  p <- results[[nm]]
  if (!is.null(p)) {
    cat(sprintf("%-20s %8.2f %8.3f %8.1f %8.3f\n", nm, p$CAGR, p$Sharpe, p$MDD, p$Calmar))
  }
}

# Telegram summary
tryCatch({
  msg_lines <- c("[Forge] STR_1333 S5 Variants Complete\nBASE: SR 0.857, MDD 34.3%")
  for (nm in names(results)) {
    p <- results[[nm]]
    if (!is.null(p))
      msg_lines <- c(msg_lines, sprintf("%s: SR %.3f MDD %.1f%%", nm, p$Sharpe, p$MDD))
  }
  tg_send(paste(msg_lines, collapse = "\n"), parse_mode = "")
}, error = function(e) cat("[TG]", e$message, "\n"))

cat("\n[STR_1333 S5] Complete.\n")
