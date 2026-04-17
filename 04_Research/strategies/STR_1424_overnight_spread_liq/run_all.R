cat("=== STR_1424: Overnight Spread Liquidity Baseline ===\n")
cat("## 핵심아이디어: L39_Overnight_Spread 단독 baseline (FC-1a + WD-A1)\n")
cat("## EN_04 4th sleeve 후보. Liquidity cluster 독립 alpha source.\n")
cat("## IC 0.082, ICIR 0.437 (recent 36M). Phase 1 필수 baseline.\n")

set.seed(1424); options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
STRATEGY_NAME   <- "OvernightSpreadLiq"
STRATEGY_ID     <- "STR_1424"
STRATEGY_FAMILY <- "liquidity_overnight"
QEPM_AUTO_COMMIT <- TRUE

# ---- Path resolution (Korean path safe) ----
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
    "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
    "02_Infrastructure"
  )
}

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(dplyr)
  library(jsonlite)
})

source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))

tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
}, error = function(e) cat("[TG] Not available:", e$message, "\n"))

tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", e$message, "\n"))

cat(sprintf("\n=== %s: %s ===\n\n", STRATEGY_ID, STRATEGY_NAME))

# ============================================================================
# Constants
# ============================================================================
LIQ_THRESHOLD <- 2e8
N_STOCKS      <- 30
FACTOR_NAME   <- "L39_Overnight_Spread"
FDB_DIR       <- file.path(PROJECT_ROOT, ".cache", "factor_db")

# ============================================================================
# Phase 0: Load data
# ============================================================================
cat("[Phase 0] Loading RAWDATA...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
rm(res); gc(verbose = FALSE)
setkey(RAWDATA, Date, Ticker)

# Load Factor DB via Arrow (predicate pushdown — only L39)
cat("[Phase 0] Loading Factor DB (L39 only via Arrow)...\n")
ds <- open_dataset(FDB_DIR, format = "parquet")
FDB <- ds |>
  filter(Factor_Name == FACTOR_NAME) |>
  select(Date, Ticker, Factor_Name, Z_Score) |>
  collect() |>
  as.data.table()
setkey(FDB, Date, Ticker)
cat("[Phase 0] FDB loaded:", nrow(FDB), "rows,", uniqueN(FDB$Date), "months\n")

# ============================================================================
# Phase 1: Factor Engine — Build FACTORS data.table
# ============================================================================
cat("[Phase 1] Building FACTORS (Score = Z_Score with liquidity filter)...\n")

# Compute lagged liquidity filter (t-1)
# For each monthly signal date, use previous 20 trading days' avg TV
monthly_dates <- sort(unique(FDB$Date))
all_trade_dates <- sort(unique(RAWDATA$Date))

# Pre-compute 20d avg trading value per ticker per month (lagged)
cat("[Phase 1] Computing lagged liquidity filter...\n")
liq_list <- lapply(monthly_dates, function(sig_d) {
  prev_dates <- all_trade_dates[all_trade_dates < sig_d]
  if (length(prev_dates) < 20) return(NULL)
  liq_start <- prev_dates[max(1, length(prev_dates) - 19)]
  liq_dt <- RAWDATA[Date >= liq_start & Date < sig_d,
                     .(AvgTV20 = mean(Vol * Close, na.rm = TRUE)),
                     by = Ticker]
  liq_dt[, Date := sig_d]
  liq_dt[AvgTV20 >= LIQ_THRESHOLD, .(Date, Ticker)]
})
liq_pass <- rbindlist(liq_list)
setkey(liq_pass, Date, Ticker)

# Build FACTORS: merge FDB Z_Score with liquidity filter
FACTORS <- merge(FDB[, .(Date, Ticker, Score = Z_Score)], liq_pass, by = c("Date", "Ticker"))
FACTORS <- FACTORS[!is.na(Score)]
cat("[Phase 1] FACTORS:", nrow(FACTORS), "rows,", uniqueN(FACTORS$Date), "months,",
    "avg", round(FACTORS[, .N, by = Date][, mean(N)], 1), "stocks/month\n")

# ============================================================================
# Phase 2: Backtest simulation (EW baseline, FC-1a + WD-A1)
# ============================================================================
cat("[Phase 2] Running backtest...\n")
sim_result <- run_monthly_simulation(
  RAWDATA       = RAWDATA,
  BM_DT         = BM_DT,
  FACTORS       = FACTORS,
  n_holdings    = N_STOCKS,
  commission    = 0.003,
  weight_method = "ew",
  buffer_zone   = list(keep_n = N_STOCKS, entry_n = N_STOCKS)
)

# Save sim_result
saveRDS(sim_result, file.path(SCRIPT_DIR, "sim_result.rds"))

# ============================================================================
# Phase 3: Analysis + Hurdle Gate
# ============================================================================
cat("[Phase 3] Running analysis + hurdle gate...\n")

OUTPUT_DIR <- file.path(SCRIPT_DIR, "output")
if (!dir.exists(OUTPUT_DIR)) dir.create(OUTPUT_DIR, recursive = TRUE)

# Strategy analyzer
tryCatch({
  source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  run_analysis(
    sim = sim_result,
    FACTORS = FACTORS,
    RAWDATA = RAWDATA,
    BM_DT = BM_DT,
    output_dir = OUTPUT_DIR,
    strategy_id = STRATEGY_ID
  )
}, error = function(e) cat("[Analyzer]", e$message, "\n"))

# Hurdle gate
hurdle <- tryCatch({
  source(file.path(INFRA_DIR, "hurdle_gate.R"))
  h <- run_hurdle_gate(
    sim_result    = sim_result,
    FACTORS       = FACTORS,
    strategy_name = STRATEGY_ID,
    output_dir    = OUTPUT_DIR
  )
  cat("[Hurdle] Grade:", h$grade, "| Score:", h$total_score, "\n")
  cat("[Hurdle] SR:", h$metrics$Sharpe, "| CAGR:", h$metrics$CAGR,
      "| MDD:", h$metrics$MDD, "\n")
  h
}, error = function(e) {
  cat("[Hurdle]", e$message, "\n")
  NULL
})

# ============================================================================
# Phase 4: QEPM hybrid commit
# ============================================================================
tryCatch({
  source(file.path(PROJECT_ROOT, "qepm", "scripts", "hybrid_mode.R"))
  if (!is.null(hurdle)) {
    hybrid_commit(
      strategy = STRATEGY_ID,
      family = STRATEGY_FAMILY,
      hurdle_result = hurdle
    )
  } else {
    cat("[QEPM] Hurdle result NULL, reading from file...\n")
    hf <- file.path(OUTPUT_DIR, "hurdle_result.json")
    if (file.exists(hf)) {
      h_json <- fromJSON(hf)
      hybrid_commit(strategy = STRATEGY_ID, family = STRATEGY_FAMILY, hurdle_result = h_json)
    }
  }
}, error = function(e) cat("[QEPM]", e$message, "\n"))

cat("\n=== STR_1424 Complete ===\n")
