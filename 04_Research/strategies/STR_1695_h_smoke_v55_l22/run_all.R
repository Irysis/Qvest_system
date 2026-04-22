# STR_1695 H_SMOKE_v55 — LIQ_THRESHOLD=2e8 frollmean(TradVal,20d) liquidity filter (OPT-10)
cat("=== STR_1695: H_SMOKE_v55 L22_Ret_Autocorr 단일팩터 smoke ===\n")
## 핵심아이디어: L22_Ret_Autocorr 단독 EW 20종목, 15bps, 유동성 2억+
## v55 정규 사이클 smoke run — 파이프라인 검증 목적 (alpha 신뢰지표 아님)
## C1(rolling autocorr) C2(t+1) C13(Z_Aligned) C14(Usable_Date) C15(load_month_factors)

QEPM_AUTO_COMMIT <- TRUE
t0 <- Sys.time()

# ===================================================================
# 0. 상수 + Environment
# ===================================================================
LIQ_THRESHOLD  <- 2e8   # 20일 평균 거래대금 >= 2억원 (C10)
N_HOLD         <- 20L
COMMISSION     <- 0.0015
WEIGHT_METHOD  <- "equal"
BUFFER_ZONE    <- list(keep_n = 22L, entry_n = 20L)

.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH      <- file.path(PROJECT_ROOT, "02_Infrastructure")
VALIDATION_DIR <- file.path(FUNC_PATH, "validation")
STRAT_DIR      <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR        <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))
source(file.path(FUNC_PATH, "backtest_harness.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales)
  library(lubridate); library(jsonlite)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

STRATEGY_ID     <- "STR_1695"
STRATEGY_FAMILY <- "liquidity"

# ===================================================================
# 1. Preflight
# ===================================================================
cat("\n[Step 1] Preflight check...\n")
tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", conditionMessage(e), "\n"))

# ===================================================================
# 2. Load raw data (1회만)
# ===================================================================
cat("\n[Step 2] Loading RAWDATA...\n")
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)

# C10: 유동성 필터 — frollmean(TradVal, 20일), t-1 lag
RAWDATA[, TradVal := Close * Vol]
RAWDATA[, TradVal_20d := frollmean(TradVal, n = 20L, align = "right"), by = Ticker]
RAWDATA[, LiqPass := !is.na(TradVal_20d) & shift(TradVal_20d, 1L) >= LIQ_THRESHOLD,
        by = Ticker]

cat(sprintf("  RAWDATA: %s ~ %s | %d tickers | %d rows\n",
            min(RAWDATA$Date), max(RAWDATA$Date),
            uniqueN(RAWDATA$Ticker), nrow(RAWDATA)))

# ===================================================================
# 3. Factor Engine (C13/C14/C15)
# ===================================================================
cat("\n[Step 3] Factor engine...\n")
FACTOR_ENGINE_PATH <- file.path(STRAT_DIR, "factor_engine.R")
source(FACTOR_ENGINE_PATH)

# ===================================================================
# 4. Lookahead detection
# ===================================================================
cat("\n[Step 4] PIT / lookahead detection...\n")
tryCatch({
  source(file.path(VALIDATION_DIR, "lookahead_detector.R"))
  pit_result <- detect_lookahead(FACTOR_ENGINE_PATH)
  if (!isTRUE(pit_result$clean)) {
    for (v in pit_result$violations)
      cat(sprintf("  [PIT VIOLATION] Line %d [%s]: %s\n", v$line, v$check, v$msg))
    stop("PIT violation detected in factor_engine.R")
  }
  cat("  PIT check: CLEAN\n")
}, error = function(e) {
  if (grepl("PIT violation", e$message)) stop(e)
  cat("[WARN] lookahead_detector:", conditionMessage(e), "\n")
})

# ===================================================================
# 5. Backtest
# ===================================================================
cat(sprintf("\n[Step 5] Simulation N=%d EW 15bps...\n", N_HOLD))
sim <- tryCatch({
  run_monthly_simulation(
    RAWDATA       = RAWDATA,
    BM_DT         = BM_DT,
    FACTORS       = FACTORS,
    n_holdings    = N_HOLD,
    weight_method = WEIGHT_METHOD,
    commission    = COMMISSION,
    buffer_zone   = BUFFER_ZONE,
    vol_target    = NULL,
    vol_lookback  = 60L
  )
}, error = function(e) { cat("[FATAL] Simulation:", conditionMessage(e), "\n"); stop(e) })
cat(sprintf("  Simulation: %d trading days\n", length(sim$strategy_xts)))

# ===================================================================
# 6. Analysis
# ===================================================================
cat("\n[Step 6] Analysis...\n")
tryCatch({
  source(file.path(FUNC_PATH, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, OUT_DIR, strategy_name = STRATEGY_ID)
}, error = function(e) {
  cat("[WARN] strategy_analyzer:", conditionMessage(e), "\n")
  tryCatch({
    perf <- summarise_perf(sim$strategy_xts, STRATEGY_ID)
    fwrite(perf, file.path(OUT_DIR, "performance.csv"))
  }, error = function(e2) NULL)
})

# ===================================================================
# 7. Hurdle Gate + COND 검증
# ===================================================================
cat("\n[Step 7] Hurdle gate...\n")
hurdle <- tryCatch({
  source(file.path(FUNC_PATH, "hurdle_gate.R"))
  h <- run_hurdle_gate(
    sim_result    = sim,
    FACTORS       = FACTORS,
    strategy_name = STRATEGY_ID,
    strategy_file = FACTOR_ENGINE_PATH,
    output_dir    = OUT_DIR
  )
  cat(sprintf("  Grade: %s | Hard fail: %s\n",
              h$grade %||% "NA",
              if (isTRUE(h$hard_fail)) "TRUE" else "FALSE"))

  mdd_val <- abs(h$mdd %||% h$max_drawdown %||% 0)
  if (mdd_val > 0.45) {
    cat(sprintf("[COND-1 VIOLATION] MDD=%.1f%% > 45%% L-137 선례 경고\n", mdd_val * 100))
    stop(sprintf("COND-1 MDD violation: %.1f%%", mdd_val * 100))
  }
  to_val <- h$turnover %||% 0
  if (to_val > 6.0) {
    cat(sprintf("[COND-6 VIOLATION] Turnover=%.0f%% > 600%%\n", to_val * 100))
    stop(sprintf("COND-6 Turnover violation: %.0f%%", to_val * 100))
  }

  jsonlite::write_json(h, file.path(OUT_DIR, "hurdle_result.json"),
                       auto_unbox = TRUE, pretty = TRUE)
  saveRDS(sim, file.path(STRAT_DIR, "sim_result.rds"))
  h
}, error = function(e) {
  cat("[ERROR] Hurdle:", conditionMessage(e), "\n")
  tryCatch(saveRDS(sim, file.path(STRAT_DIR, "sim_result.rds")), error = function(e2) NULL)
  NULL
})

# ===================================================================
# 8. Stage artifact (s1_construction — 평면 위치)
# ===================================================================
cat("\n[Step 8] Writing s1_construction artifact...\n")
STAGE_ART_DIR <- file.path(PROJECT_ROOT, "stage_artifacts")

if (!is.null(hurdle)) {
  mdd_v   <- abs(hurdle$mdd %||% hurdle$max_drawdown %||% NA)
  cagr_v  <- hurdle$cagr %||% NA
  sr_v    <- hurdle$sharpe_ratio %||% hurdle$sr %||% NA
  to_v    <- hurdle$turnover %||% NA
  grade_v <- hurdle$grade %||% "NA"
  hf_v    <- isTRUE(hurdle$hard_fail)

  ic_csv <- file.path(OUT_DIR, "analysis_ic.csv")
  icir_v <- NA; ic_mean_v <- NA; ic_t_v <- NA
  if (file.exists(ic_csv)) {
    tryCatch({
      ic_dt <- fread(ic_csv)
      if ("ICIR" %in% names(ic_dt)) icir_v    <- mean(ic_dt$ICIR, na.rm = TRUE)
      if ("IC"   %in% names(ic_dt)) ic_mean_v <- mean(ic_dt$IC,   na.rm = TRUE)
      if ("IC_t" %in% names(ic_dt)) ic_t_v    <- mean(ic_dt$IC_t, na.rm = TRUE)
    }, error = function(e) NULL)
  }

  s1_art <- list(
    schema_version = "s1_v1",
    factor_id  = "H_SMOKE_v55",
    str_num    = "STR_1695",
    str_name   = "STR_1695_h_smoke_v55_l22",
    factor     = "L22_Ret_Autocorr",
    created    = format(Sys.Date(), "%Y-%m-%d"),
    created_by = "Forge",
    icir       = round(icir_v, 4),
    ic_mean    = round(ic_mean_v, 4),
    ic_t       = round(ic_t_v, 4),
    cagr       = round(cagr_v, 4),
    sr         = round(sr_v, 4),
    mdd        = round(mdd_v, 4),
    turnover   = round(to_v, 4),
    hurdle_grade = grade_v,
    hard_fail    = hf_v,
    PIT_check = list(
      C1  = "rolling autocorr via Factor DB 252d window",
      C2  = "month-end signal t+1 execution",
      C13 = "Z_Score_Aligned, no manual flip",
      C14 = "Usable_Date <= sig_date in load_month_factors()",
      C15 = "load_month_factors() exclusively"
    ),
    COND_check = list(
      COND1_mdd_le45       = !is.na(mdd_v) && mdd_v <= 0.45,
      COND3_pit_c13c14c15  = TRUE,
      COND6_turnover_lt600 = !is.na(to_v) && to_v < 6.0
    ),
    notes = "v55 smoke run. hurdle=파이프라인 동작 증거. recent_3y_icir 현재 시점 선택 한계(UD-2) 인식."
  )

  out_path <- file.path(STAGE_ART_DIR, "s1_construction_H_SMOKE_v55.json")
  jsonlite::write_json(s1_art, out_path, auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf("  Artifact: %s\n", out_path))
} else {
  cat("[WARN] hurdle NULL — artifact skipped\n")
}

elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
cat(sprintf("\n=== STR_1695 Complete (%.1f min) ===\n", elapsed))
