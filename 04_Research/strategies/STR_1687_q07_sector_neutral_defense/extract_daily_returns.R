cat("=== STR_1687 daily_returns.csv 추출 (S3 orthogonality용) ===\n")

.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
FUNC_PATH    <- file.path(PROJECT_ROOT, "02_Infrastructure")
STRAT_DIR    <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR      <- file.path(STRAT_DIR, "output")

source(file.path(FUNC_PATH, "config.R"))
source(file.path(FUNC_PATH, "backtest_harness.R"))
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts)
  library(PerformanceAnalytics); library(parallel); library(jsonlite)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

N_HOLD        <- 20L
LIQ_THRESHOLD <- 2e8
COMMISSION    <- 0.0015
BUFFER_ZONE   <- list(keep_n = 22L, entry_n = 20L)
WEIGHT_METHOD <- "equal"

cat("[1] Loading RAWDATA...\n")
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
setkey(RAWDATA, Date, Ticker)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"), 1L), by = Ticker]
RAWDATA[, LiqPass  := !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
cat(sprintf("[1] %s ~ %s | %d tickers\n", min(RAWDATA$Date), max(RAWDATA$Date), uniqueN(RAWDATA$Ticker)))

cat("[2] Factor engine...\n")
source(file.path(STRAT_DIR, "factor_engine.R"))
cat(sprintf("[2] FACTORS: %d rows\n", nrow(FACTORS)))

cat("[3] Simulation (V1 only)...\n")
sim <- tryCatch(
  run_monthly_simulation(
    FACTORS = FACTORS, RAWDATA = RAWDATA, BM_DT = BM_DT,
    n_holdings = N_HOLD, weight_method = WEIGHT_METHOD,
    commission = COMMISSION, buffer_zone = BUFFER_ZONE
  ),
  error = function(e) { cat("[FATAL]", conditionMessage(e), "\n"); NULL }
)
if (is.null(sim)) stop("Simulation failed")

cat(sprintf("[3] Sim done: %d trading days\n", length(sim$strategy_xts)))

# daily_returns.csv 저장
if (!is.null(sim$DAILY_NAV_DT)) {
  dr <- sim$DAILY_NAV_DT[, .(Date, Return = Strategy_Ret)]
  fwrite(dr, file.path(OUT_DIR, "daily_returns.csv"))
  cat(sprintf("[4] Saved daily_returns.csv: %d rows (%s ~ %s)\n",
              nrow(dr), min(dr$Date), max(dr$Date)))
} else {
  # strategy_xts fallback
  xts_dt <- data.table(Date = as.Date(index(sim$strategy_xts)),
                        Return = as.numeric(sim$strategy_xts))
  fwrite(xts_dt, file.path(OUT_DIR, "daily_returns.csv"))
  cat(sprintf("[4] Saved daily_returns.csv (from xts): %d rows\n", nrow(xts_dt)))
}

cat("[DONE]\n")
