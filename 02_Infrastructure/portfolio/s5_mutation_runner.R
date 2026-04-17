## S5 Mutation Runner — Generic mutation executor for Forge
## Usage: Set MUTATION_CONFIG list before sourcing, or pass via JSON file
## Required: MUTATION_CONFIG$strategy_id, $mutation_id, $factors, $weighting, $overlay, etc.

cat(sprintf("=== S5 Mutation: %s / %s ===\n", MUTATION_CONFIG$strategy_id, MUTATION_CONFIG$mutation_id))
set.seed(as.integer(gsub("\\D", "", MUTATION_CONFIG$strategy_id)) + as.integer(gsub("\\D", "", MUTATION_CONFIG$mutation_id)))
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_ID   <- MUTATION_CONFIG$strategy_id
MUTATION_ID   <- MUTATION_CONFIG$mutation_id
STRATEGY_NAME <- paste0(STRATEGY_ID, "_", MUTATION_ID)
FACTORS_NEEDED <- MUTATION_CONFIG$factors
WEIGHTING     <- MUTATION_CONFIG$weighting %||% "equal"
OVERLAY_DD    <- MUTATION_CONFIG$overlay_dd    # NULL or c(trigger, recovery) e.g. c(8, 25)
OVERLAY_REGIME <- MUTATION_CONFIG$overlay_regime %||% FALSE
SECTOR_NEUTRAL <- MUTATION_CONFIG$sector_neutral %||% TRUE  # default TRUE (base pattern)
SMOOTHING_MO   <- MUTATION_CONFIG$smoothing_months %||% 0L
REBAL_FREQ     <- MUTATION_CONFIG$rebalance %||% "monthly"
IVOL_WEIGHT    <- MUTATION_CONFIG$ivol_weight %||% FALSE
N_HOLDINGS     <- MUTATION_CONFIG$n_holdings %||% 30L
COMMISSION     <- MUTATION_CONFIG$commission %||% 0.0015

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
INFRA_DIR    <- file.path(PROJECT_ROOT, "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts); library(arrow)

LIQ_THRESHOLD <- 2e8

## Output directory
STR_DIR    <- file.path(PROJECT_ROOT, "04_Research", "strategies", STRATEGY_ID)
OUTPUT_DIR <- file.path(STR_DIR, "output", paste0("s5_", MUTATION_ID))
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)

## ---- Factor Engine (generic) ----
cat("[Phase 1] Loading data + factors...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; RAWDATA_ORIG <- copy(RAWDATA); rm(res); gc(verbose = FALSE)

source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
FDB_DIR <- file.path(PROJECT_ROOT, ".cache", "factor_db")
ds <- open_dataset(FDB_DIR, format = "parquet")
FDB_RAW <- ds |> dplyr::filter(Factor_Name %in% FACTORS_NEEDED) |> dplyr::collect() |> as.data.table()
cat(sprintf("  Loaded: %s rows for %d factors\n", format(nrow(FDB_RAW), big.mark = ","), length(FACTORS_NEEDED)))
registry <- .load_registry()
FDB_ALL <- align_factor_direction(FDB_RAW, registry)
FDB_ALL[, Date := as.Date(Date)]; setkey(FDB_ALL, Date, Ticker)
rm(FDB_RAW, ds); gc(verbose = FALSE)

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM][, sort(Signal_Date)]
signal_dates <- signal_dates[signal_dates >= SIGNAL_START_DATE]

## Quarterly filter
if (REBAL_FREQ == "quarterly") {
  sig_ym <- format(signal_dates, "%Y-%m")
  quarter_months <- sig_ym[substr(sig_ym, 6, 7) %in% c("03", "06", "09", "12")]
  signal_dates <- signal_dates[sig_ym %in% quarter_months]
  cat(sprintf("  Quarterly: %d signal dates\n", length(signal_dates)))
}

RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, 20L, align = "right"), 1L, type = "lag"), by = Ticker]

## IVol computation (if needed)
if (isTRUE(IVOL_WEIGHT)) {
  cat("  Computing IVol for weighting...\n")
  RAWDATA[, ret_d := Close / shift(Close, 1L) - 1, by = Ticker]
  RAWDATA[, ivol_20 := shift(frollapply(ret_d, 20L, sd, align = "right"), 1L, type = "lag"), by = Ticker]
}

## Smoothing history (if needed)
if (SMOOTHING_MO > 0L) {
  cat(sprintf("  %d-month signal smoothing enabled\n", SMOOTHING_MO))
}

factor_list <- vector("list", length(signal_dates))
n_done <- 0L; n_skip <- 0L

for (i in seq_along(signal_dates)) {
  sig_d <- as.Date(signal_dates[i])
  snap <- RAWDATA[Date == sig_d, .(Ticker, Close, AvgTV20, Sector)]
  if (isTRUE(IVOL_WEIGHT)) {
    snap <- merge(snap, RAWDATA[Date == sig_d, .(Ticker, ivol_20)], by = "Ticker", all.x = TRUE)
  }
  snap <- snap[!is.na(Close) & Close > 0 & !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(snap) < N_HOLDINGS) { n_skip <- n_skip + 1L; next }

  fdt <- FDB_ALL[Date == sig_d & Factor_Name %in% FACTORS_NEEDED, .(Ticker, Factor_Name, Z_Score_Aligned)]
  if (nrow(fdt) == 0) { n_skip <- n_skip + 1L; next }

  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  dt <- merge(snap, fdt_wide, by = "Ticker")

  fcols <- intersect(FACTORS_NEEDED, names(dt))
  if (length(fcols) == 0) { n_skip <- n_skip + 1L; next }

  ## Score: equal-weight mean of Z_Score_Aligned
  dt[, Score := rowMeans(.SD, na.rm = TRUE), .SDcols = fcols]
  dt <- dt[!is.na(Score)]

  ## Sector neutral
  if (isTRUE(SECTOR_NEUTRAL)) {
    dt[, Score := Score - mean(Score, na.rm = TRUE), by = Sector]
  }

  dt[, Date := sig_d]
  factor_list[[i]] <- dt[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
for (col in c("TradingValue", "AvgTV20", "ret_d", "ivol_20"))
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
rm(FDB_ALL); gc(verbose = FALSE)
cat(sprintf("  FACTORS: %s rows | %d dates (skip %d)\n", format(nrow(FACTORS), big.mark = ","), n_done, n_skip))

## Signal smoothing (3-month rolling average)
if (SMOOTHING_MO > 0L && nrow(FACTORS) > 0) {
  cat(sprintf("  Applying %d-month signal smoothing...\n", SMOOTHING_MO))
  FACTORS[, score_raw := Score]
  setorder(FACTORS, Ticker, Date)
  FACTORS[, Score := frollmean(score_raw, SMOOTHING_MO, align = "right"), by = Ticker]
  FACTORS <- FACTORS[!is.na(Score)]
  FACTORS[, score_raw := NULL]
  setorder(FACTORS, Date, -Score)
}

## ---- Backtest ----
cat("\n[Phase 2] Backtesting...\n")
RAWDATA <- copy(RAWDATA_ORIG)

wm <- if (isTRUE(IVOL_WEIGHT)) "ivol" else WEIGHTING
sim <- run_monthly_simulation(
  RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
  n_holdings = N_HOLDINGS, weight_method = wm,
  commission = COMMISSION, buffer_zone = list(keep_n = 50L, entry_n = 25L)
)

## ---- Overlay: DD Brake ----
if (!is.null(OVERLAY_DD) && length(OVERLAY_DD) == 2) {
  cat(sprintf("  Applying DD Brake %.0f/%.0f...\n", OVERLAY_DD[1], OVERLAY_DD[2]))
  source(file.path(REGIME_DIR, "dd_brake.R"), local = TRUE)
  dd_trig <- OVERLAY_DD[1] / 100
  dd_recv <- OVERLAY_DD[2] / 100
  strat_xts <- sim$strategy_xts
  nav <- cumprod(1 + strat_xts)
  peak <- cummax(nav)
  dd_pct <- as.numeric((nav - peak) / peak)
  ## t-1 lag (C9)
  dd_lag <- c(0, dd_pct[-length(dd_pct)])
  brake_on <- dd_lag <= -dd_trig
  brake_off <- dd_lag >= -dd_recv  # actually recovered
  ## state machine
  in_brake <- FALSE
  adj <- rep(1, length(strat_xts))
  for (t in seq_along(adj)) {
    if (!in_brake && brake_on[t]) in_brake <- TRUE
    if (in_brake && dd_lag[t] > -dd_recv) in_brake <- FALSE
    if (in_brake) adj[t] <- 0.5  # reduce exposure 50%
  }
  sim$strategy_xts <- strat_xts * adj
  cat(sprintf("  DD Brake: %d days braked\n", sum(adj < 1)))
}

## ---- Overlay: Regime v7.1 ----
if (isTRUE(OVERLAY_REGIME)) {
  tryCatch({
    cat("  Applying Regime v7.1...\n")
    source(file.path(REGIME_DIR, "regime_engine.R"), local = TRUE)
    regime_sig <- get_regime_signal(index(sim$strategy_xts))
    if (!is.null(regime_sig)) {
      ## t-1 lag (C5)
      regime_lag <- c(1, head(as.numeric(regime_sig), -1))
      sim$strategy_xts <- sim$strategy_xts * regime_lag
      cat(sprintf("  Regime: %d days hedged\n", sum(regime_lag < 1)))
    }
  }, error = function(e) cat("[Regime]", e$message, "\n"))
}

## ---- Analysis ----
cat("\n[Phase 3] Analysis + Hurdle...\n")
perf_strat <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
perf_bm    <- summarise_perf(sim$bm_xts, "BM")
cat(sprintf("  %s: CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n", STRATEGY_NAME, perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD))

generate_charts(sim, output_dir = OUTPUT_DIR, strategy_name = STRATEGY_NAME)
fwrite(rbind(perf_strat, perf_bm), file.path(OUTPUT_DIR, "performance.csv"))
saveRDS(sim, file.path(OUTPUT_DIR, "sim_result.rds"))

RAWDATA <- copy(RAWDATA_ORIG)
tryCatch({
  source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, OUTPUT_DIR, strategy_name = STRATEGY_NAME)
}, error = function(e) cat("[WARN]", e$message, "\n"))

source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(
  sim_result = sim, FACTORS = FACTORS, strategy_name = STRATEGY_NAME,
  strategy_file = "", output_dir = OUTPUT_DIR
)
jsonlite::write_json(hurdle, file.path(OUTPUT_DIR, "hurdle_result.json"), auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("  Grade: %s | Score: %.1f\n", hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0))

## Return result for batch runner
MUTATION_RESULT <- list(
  strategy_id = STRATEGY_ID, mutation_id = MUTATION_ID,
  grade = hurdle$grade, score = hurdle$total_score %||% hurdle$score %||% 0,
  sharpe = perf_strat$Sharpe, cagr = perf_strat$CAGR, mdd = perf_strat$MDD,
  output_dir = OUTPUT_DIR
)
cat(sprintf("\n=== %s / %s Complete. Grade=%s Score=%.1f ===\n",
    STRATEGY_ID, MUTATION_ID, hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0))
