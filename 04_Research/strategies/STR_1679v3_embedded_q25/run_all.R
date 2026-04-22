cat("=== STR_1679v3: Earnings+Ohlson Quality Embedded Blend (C19+Q25_inv+Q07) ===\n")
## 핵심아이디어: C19 earnings composite + Q25 Ohlson downside quality embedded (no physical sleeve)
## v2 DROP 이유: Defense COSMETIC, Overlay 의존 → v3: signal-level downside protection
## LIQ_THRESHOLD=2e8 C10 C13 C15

QEPM_AUTO_COMMIT <- TRUE
t0 <- Sys.time()

# ── 0. Environment ──────────────────────────────────────────────────────────────
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR    <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))
source(file.path(FUNC_PATH, "backtest_harness.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales)
  library(lubridate); library(jsonlite)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_ID     <- "STR_1679v3"
HYPOTHESIS_ID   <- "H_1679v3_embedded_q25"
STRATEGY_FAMILY <- "earnings_composite"
N_HOLD          <- 20L
LIQ_THRESHOLD   <- 2e8
COMMISSION      <- 0.0015
BUFFER_ZONE     <- list(keep_n = 22L, entry_n = 20L)
REBAL_MONTHS    <- 2L

# ── 1. Preflight ────────────────────────────────────────────────────────────────
cat("\n[Step 1] Preflight check...\n")
tryCatch({
  source(file.path(FUNC_PATH, "validation", "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", conditionMessage(e), "\n"))

# ── 2. RAWDATA (1회) ────────────────────────────────────────────────────────────
cat("\n[Step 2] Loading RAWDATA...\n")
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)

setkey(RAWDATA, Date, Ticker)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20  := shift(frollmean(TradingValue, n = 20L, align = "right"), 1L), by = Ticker]
RAWDATA[, LiqPass  := !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
cat(sprintf("[Step 2] %s ~ %s | %d tickers\n",
  min(RAWDATA$Date), max(RAWDATA$Date), uniqueN(RAWDATA$Ticker)))

# ── 3. Factor Engine ────────────────────────────────────────────────────────────
cat("\n[Step 3] Factor engine...\n")
source(file.path(STRAT_DIR, "factor_engine.R"))
stopifnot(is.data.table(FACTORS), all(c("Date", "Ticker", "Score") %in% names(FACTORS)))
cat(sprintf("[Step 3] %d periods | %d rows\n", uniqueN(FACTORS$Date), nrow(FACTORS)))

# ── 4. 백테스트 ─────────────────────────────────────────────────────────────────
cat("\n[Step 4] Backtest...\n")
sim_result <- run_monthly_simulation(
  RAWDATA      = RAWDATA,
  BM_DT        = BM_DT,
  FACTORS      = FACTORS,
  n_holdings   = N_HOLD,
  commission   = COMMISSION,
  buffer_zone  = BUFFER_ZONE,
  weight_method = "equal"
)

# ── 5. Hurdle Gate ──────────────────────────────────────────────────────────────
cat("\n[Step 5] Hurdle gate...\n")
source(file.path(FUNC_PATH, "hurdle_gate.R"))
hurdle <- tryCatch(
  run_hurdle_gate(sim_result, strategy_name = STRATEGY_ID, output_dir = OUT_DIR),
  error = function(e) { cat("[WARN hurdle]", conditionMessage(e), "\n"); list(grade="ERR", score=0) }
)
cat(sprintf("\n[%s] Grade: %s | Score: %.0f\n",
  STRATEGY_ID, hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)))

jsonlite::write_json(hurdle, file.path(OUT_DIR, "hurdle_result.json"), auto_unbox = TRUE)

# ── 6. Tail Risk ────────────────────────────────────────────────────────────────
cat("\n[Step 6] Tail risk...\n")
tryCatch({
  source(file.path(FUNC_PATH, "portfolio", "tail_risk_engine.R"))
  tail_result <- compute_tail_risk(sim_result$returns)
  jsonlite::write_json(tail_result, file.path(OUT_DIR, "tail_risk_result.json"), auto_unbox = TRUE)
  cat(sprintf("[tail_risk] CVaR95: %.3f | CDaR: %.3f\n",
    tail_result$cvar_95, tail_result$cdar))
}, error = function(e) cat("[tail_risk] ERROR:", conditionMessage(e), "\n"))

# ── 7. 차트 저장 ────────────────────────────────────────────────────────────────
tryCatch({
  generate_charts(sim_result, strategy_id = STRATEGY_ID, output_dir = OUT_DIR)
}, error = function(e) cat("[charts] ERROR:", conditionMessage(e), "\n"))

cat(sprintf("\n[STR_1679v3] 완료. %.1f분 소요. output → %s\n",
  as.numeric(difftime(Sys.time(), t0, units = "mins")), OUT_DIR))
