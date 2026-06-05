cat("=== STR_1652: Dynamic Factor Allocation v3 (C19+Q07+Q03+D29 Regime Switch) ===\n")
## 핵심아이디어: MRS 국면별 공격/방어 팩터 동적 배분 (Dual-Axis Risk Management)
## 근거: Dichtl et al.(2019 FAJ), Barroso&Santa-Clara(2015), Dichev&Tang(2009)
## S1: 순수 팩터 신호 측정, overlay 없음
## 비교: C19 단독 (STR_1631 base)과 동적 배분 간 성과 분해

t0 <- Sys.time()

# ═══════════════════════════════════════════════════════════════════
# 0. 환경 설정
# ═══════════════════════════════════════════════════════════════════
.root_candidates <- c(
  Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR  <- file.path(PROJECT_ROOT, ".cache")
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR    <- file.path(STRAT_DIR, "output")
FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(dplyr)
  library(xts)
  library(zoo)
  library(PerformanceAnalytics)
  library(ggplot2)
  library(scales)
  library(jsonlite)
})

options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

LIQ_THRESHOLD <- 2e8
N_HOLD        <- 20L
QEPM_AUTO_COMMIT <- TRUE

cat(sprintf("[setup] PROJECT_ROOT: %s\n", PROJECT_ROOT))
cat(sprintf("[setup] OUT_DIR: %s\n", OUT_DIR))

# ═══════════════════════════════════════════════════════════════════
# 1. RAWDATA 로드 (OPT-2: use_cache=TRUE, 1회만)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 1] Loading RAWDATA...\n")
source(file.path(FUNC_PATH, "backtest_harness.R"))
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)

RAWDATA[, Date := as.Date(Date)]
BM_DT[, Date   := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]
BM_DT   <- BM_DT[Date >= ANALYSIS_START_DATE]

drop_cols <- intersect(c("Open", "High", "Low", "source", "Size", "Market"), names(RAWDATA))
if (length(drop_cols) > 0L) RAWDATA[, (drop_cols) := NULL]
setkey(RAWDATA, Date, Ticker)

cat(sprintf("[Step 1] RAWDATA: %s rows | %d tickers\n",
            format(nrow(RAWDATA), big.mark = ","), uniqueN(RAWDATA$Ticker)))

# ═══════════════════════════════════════════════════════════════════
# 2. factor_db_connector 로드 (align_factor_direction, .load_registry)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 2] Loading factor_db_connector...\n")
source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

# ═══════════════════════════════════════════════════════════════════
# 3. MRS 로드 (build_daily_regime: 내부 shift(1) — C2 준수)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 3] Loading daily regime (MRS, t-1 lag enforced internally)...\n")
source(file.path(FUNC_PATH, "regime", "regime_engine_daily.R"))
REGIME_DT <- build_daily_regime(use_cache = TRUE)
REGIME_DT[, Date := as.Date(Date)]
setkey(REGIME_DT, Date)
cat(sprintf("[Step 3] REGIME_DT: %d rows | MRS range [%.1f, %.1f]\n",
            nrow(REGIME_DT),
            min(REGIME_DT$MRS, na.rm = TRUE),
            max(REGIME_DT$MRS, na.rm = TRUE)))

# ═══════════════════════════════════════════════════════════════════
# 4. factor_engine.R: Factor DB bulk load + 월별 신호 생성
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 4] Running factor_engine (bulk FDB + regime-weighted scoring)...\n")
source(file.path(STRAT_DIR, "factor_engine.R"))

if (!exists("FACTORS") || nrow(FACTORS) == 0L) {
  stop("[STR_1652] FACTORS가 비어 있습니다. factor_engine.R 확인 필요.")
}
cat(sprintf("[Step 4] FACTORS ready: %d rows | %d months | %s ~ %s\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            min(FACTORS$Date), max(FACTORS$Date)))

# ═══════════════════════════════════════════════════════════════════
# 5. 백테스트 실행 (OPT-3: run_monthly_simulation — Rcpp 23x speedup)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 5] Running backtest (run_monthly_simulation)...\n")

FACTORS_BT <- FACTORS[, .(Date, Ticker, Score)]

sim <- run_monthly_simulation(
  RAWDATA     = RAWDATA,
  BM_DT       = BM_DT,
  FACTORS     = FACTORS_BT,
  n_hold      = N_HOLD,
  commission  = 0.0015,
  buffer_zone = list(keep_n = 30L, entry_n = 20L)
)

if (is.null(sim) || is.null(sim$strategy_xts) || length(sim$strategy_xts) == 0L) {
  stop("[STR_1652] 백테스트 결과가 NULL입니다.")
}

# ═══════════════════════════════════════════════════════════════════
# 6. 성과 요약
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 6] Performance Summary...\n")

# sim 반환: list(DAILY_NAV_DT, PORTFOLIO_LOG, HOLDINGS_LOG, strategy_xts, bm_xts)
perf_dt <- summarise_perf(sim$strategy_xts, label = "STR_1652")

# Turnover 계산 (PORTFOLIO_LOG 기반)
# Turnover_Pct = 퍼센트 단위 (0~100), ann_turnover_pct = annualized
turnover_ann_pct <- tryCatch(
  calc_turnover(sim$PORTFOLIO_LOG, sim$DAILY_NAV_DT),
  error = function(e) NA_real_
)

# summarise_perf() 반환값: CAGR/MDD는 이미 퍼센트 (%, 예: 19.54, -31.20)
# WinRate도 이미 퍼센트 (%). Sharpe/Sortino/Calmar는 배율값.
cagr_val    <- as.numeric(perf_dt$CAGR)      # 이미 % (예: 19.54)
sr_val      <- as.numeric(perf_dt$Sharpe)
sortino_val <- as.numeric(perf_dt$Sortino)
mdd_val     <- as.numeric(perf_dt$MDD)       # 이미 % (예: -31.20, 양수면 손실크기)
calmar_val  <- as.numeric(perf_dt$Calmar)
wr_val      <- as.numeric(perf_dt$WinRate)   # 이미 % (예: 62.0)

cat(sprintf("\n=== STR_1652 S1 Performance ===\n"))
cat(sprintf("  CAGR     : %.2f%%\n",  cagr_val))
cat(sprintf("  Sharpe   : %.3f\n",    sr_val))
cat(sprintf("  Sortino  : %.3f\n",    sortino_val))
cat(sprintf("  MDD      : %.2f%%\n",  mdd_val))
cat(sprintf("  Turnover : %.1f%%/yr\n", turnover_ann_pct))
cat(sprintf("  Win Rate : %.1f%%\n",  wr_val))
cat(sprintf("  Calmar   : %.3f\n",    calmar_val))

# ═══════════════════════════════════════════════════════════════════
# 7. 국면별 성과 분해 (Normal / Caution / Crisis)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 7] Regime-conditional performance decomposition...\n")

nav_dt <- copy(sim$DAILY_NAV_DT)
nav_dt <- merge(nav_dt, REGIME_DT[, .(Date, MRS)], by = "Date", all.x = TRUE)
nav_dt[, Regime_label := dplyr::case_when(
  is.na(MRS) | MRS < 20 ~ "Normal",
  MRS < 50               ~ "Caution",
  TRUE                   ~ "Crisis"
)]

regime_perf <- nav_dt[!is.na(Strategy_Ret), .(
  N_days  = .N,
  Ann_Ret = mean(Strategy_Ret, na.rm = TRUE) * 252,
  Ann_Vol = sd(Strategy_Ret,   na.rm = TRUE) * sqrt(252),
  SR      = mean(Strategy_Ret, na.rm = TRUE) /
            sd(Strategy_Ret,   na.rm = TRUE) * sqrt(252)
), by = Regime_label]

cat("\n=== Regime-Conditional Performance ===\n")
print(regime_perf)

# ═══════════════════════════════════════════════════════════════════
# 8. 8대 스트레스 구간 성과
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 8] Stress period performance...\n")

# 8대 스트레스 구간 (reference_stress_periods.md 정본, defense-evaluation skill 통일)
stress_periods <- list(
  list(name = "9/11_Terror",             start = "2001-09-01", end = "2001-12-31"),
  list(name = "GFC",                     start = "2007-10-01", end = "2009-03-31"),
  list(name = "EU_Debt",                 start = "2011-07-01", end = "2011-12-31"),
  list(name = "China_Shock",             start = "2015-06-01", end = "2016-02-29"),
  list(name = "Trade_War",               start = "2018-03-01", end = "2018-12-31"),
  list(name = "COVID",                   start = "2020-01-01", end = "2020-06-30"),
  list(name = "Rate_Hike",               start = "2022-01-01", end = "2022-12-31"),
  list(name = "Iran_War",                start = "2026-02-01", end = "2026-04-30")
)

stress_results <- lapply(stress_periods, function(sp) {
  sub <- nav_dt[Date >= as.Date(sp$start) & Date <= as.Date(sp$end) &
                  !is.na(Strategy_Ret)]
  if (nrow(sub) < 5L) {
    return(data.table(Period = sp$name, Total_Ret_pct = NA_real_, MDD_pct = NA_real_))
  }
  # 구간 누적 수익률 (단순 합산, 짧은 구간이므로 annualize 하지 않음)
  cum_nav <- cumprod(1 + sub$Strategy_Ret)
  total_ret <- cum_nav[length(cum_nav)] / cum_nav[1] - 1
  # MDD: NAV 기준 peak-to-trough
  peak <- cummax(cum_nav)
  dd <- cum_nav / peak - 1
  mdd_s <- min(dd, na.rm = TRUE)
  data.table(Period = sp$name,
             Total_Ret_pct = round(total_ret * 100, 2),
             MDD_pct       = round(mdd_s * 100, 2))
})
stress_dt <- rbindlist(stress_results)
cat("\n=== Stress Period Performance ===\n")
print(stress_dt)

# ═══════════════════════════════════════════════════════════════════
# 9. 결과 저장
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 9] Saving results...\n")

# Equity curve CSV
fwrite(sim$DAILY_NAV_DT[, .(Date, NAV)],
       file.path(OUT_DIR, "equity_curve.csv"))

# Hurdle result JSON
# 주의: cagr_val/mdd_val/wr_val = 이미 % 단위 (summarise_perf 반환값)
# hard_fail 기준: MDD% > 45 (MDD가 퍼센트 값이므로), Turnover%/yr > 600
hurdle_result <- list(
  strategy_id   = "STR_1652",
  strategy_name = "Dynamic Factor Allocation v3",
  stage         = "S1",
  run_date      = format(Sys.Date(), "%Y-%m-%d"),
  CAGR_pct      = round(cagr_val,         2),
  Sharpe        = round(sr_val,           4),
  Sortino       = round(sortino_val,      4),
  MDD_pct       = round(mdd_val,          2),
  Turnover_ann_pct = round(turnover_ann_pct, 1),
  WinRate_pct   = round(wr_val,           1),
  hard_fail     = abs(mdd_val) > 45 || (!is.na(turnover_ann_pct) && turnover_ann_pct > 600),
  regime_decomp = as.list(regime_perf),
  stress_perf   = as.list(stress_dt),
  notes         = "S1: pure factor signal, no overlay. EW Top20 + buffer_zone(30/20) + LIQ>=2e8 + Cov>=3"
)
write_json(hurdle_result, file.path(OUT_DIR, "hurdle_result_S1.json"),
           pretty = TRUE, auto_unbox = TRUE)

# Regime log
fwrite(REGIME_LOG, file.path(OUT_DIR, "regime_allocation_log.csv"))

elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
cat(sprintf("\n[Done] STR_1652 S1 완료 (%.1f분)\n", elapsed))
cat(sprintf("  출력: %s\n", OUT_DIR))
cat(sprintf("  CAGR=%.2f%% | SR=%.3f | MDD=%.2f%%\n",
            cagr_val, sr_val, mdd_val))
