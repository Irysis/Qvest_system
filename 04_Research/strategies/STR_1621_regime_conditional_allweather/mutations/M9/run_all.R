cat("=== STR_1621_M9: Synthesis — D01+D44+D18_BAB_Rank + 5단계 Regime + DD Brake 6/20 ===\n")
## synthesis_tested=TRUE: M3(Low Beta defense) + M5(5단계 Regime) + M8(DD Brake 6/20)
## C9: dd_lag <- c(0, dd_pct[-n]) — same-day DD 절대 금지
set.seed(1621); options(scipen=999); Sys.setenv(TZ="Asia/Seoul")
STRATEGY_NAME <- "STR_1621_M9_Synthesis"; STRATEGY_ID <- "STR_1621_M9"

PROJ_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
INFRA_DIR <- file.path(PROJ_ROOT, "02_Infrastructure")
CACHE_DIR <- file.path(PROJ_ROOT, ".cache")
STR_DIR   <- file.path(PROJ_ROOT, "04_Research/strategies/STR_1621_regime_conditional_allweather")
MUTATION_DIR <- file.path(STR_DIR, "mutations/M9")
OUTPUT_DIR   <- file.path(MUTATION_DIR, "output")
dir.create(OUTPUT_DIR, recursive=TRUE, showWarnings=FALSE)

source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
suppressPackageStartupMessages(library(data.table))
suppressPackageStartupMessages(library(dplyr))

LIQ_THRESHOLD <- 2e8
N_STOCKS <- 30L
CORE_FACTORS    <- c("C19_Composite_Earnings", "V14_EBIT_EV")
DEFENSE_FACTORS <- c("D01_IdioVol", "D44_Kurtosis", "D18_BAB_Rank")  # M3: 저베타 추가
NEEDED_FACTORS  <- c(CORE_FACTORS, DEFENSE_FACTORS)

# C15: Factor DB 로드
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
fdb_files <- list.files(file.path(CACHE_DIR, "factor_db"),
                        pattern = "^factor_db_\\d{6}\\.parquet$", full.names = FALSE)
fdb_dates_ym <- sort(gsub("factor_db_(\\d{6})\\.parquet", "\\1", fdb_files))
cat(sprintf("  Factor DB: %d monthly files (latest: %s)\n",
            length(fdb_dates_ym), if (length(fdb_dates_ym) > 0) tail(fdb_dates_ym, 1) else "NONE"))

# Regime signal (t-1 lag)
cat("  Loading regime signal...\n")
source(file.path(REGIME_DIR, "regime_signal.R"))
regime_dt <- tryCatch({
  r <- load_regime_signal()
  if (is.null(r) || nrow(r) == 0L) build_regime_signal_table() else r
}, error = function(e) build_regime_signal_table())
regime_dt[, Date := as.Date(Date)]
setorder(regime_dt, Date)
regime_dt[, Regime_Score_Lag := shift(Regime_Score, n = 1L, type = "lag")]
setkey(regime_dt, Date)
cat(sprintf("  Regime signal: %d months\n", nrow(regime_dt)))

# RAWDATA 로드
cat("[Phase 1] Loading RAWDATA...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
if (!"Name"   %in% names(RAWDATA)) RAWDATA[, Name   := NA_character_]
if (!"Sector" %in% names(RAWDATA)) RAWDATA[, Sector := NA_character_]

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
monthly_dates <- sort(RAWDATA[, .(SD = max(Date)), by = YM]$SD)
all_dates <- sort(unique(RAWDATA$Date))
monthly_dates <- monthly_dates[monthly_dates >= all_dates[min(253L, length(all_dates))]]
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]

# Factor engine
cat("[Phase 2] Building factor scores (5단계 Regime + D01+D44+M12)...\n")
factor_list <- vector("list", length(monthly_dates))
n_done <- 0L; n_skipped <- 0L

for (i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i])

  fdt <- tryCatch(
    load_month_factors(sig_d, coverage_min = 0.05),
    error = function(e) { cat(sprintf("  [SKIP %s] %s\n", sig_d, e$message)); NULL }
  )
  if (is.null(fdt) || nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }
  fdt <- fdt[Factor_Name %in% NEEDED_FACTORS]
  if (nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }

  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  liq <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20)]
  fdt_wide <- merge(fdt_wide, liq, by = "Ticker")
  fdt_wide <- fdt_wide[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(fdt_wide) < 20L) { n_skipped <- n_skipped + 1L; next }

  # Regime: t-1 lag (Regime_Score_Lag)
  valid_regime_dates <- regime_dt$Date[regime_dt$Date <= sig_d & !is.na(regime_dt$Regime_Score_Lag)]
  if (length(valid_regime_dates) > 0L) {
    rd <- max(valid_regime_dates)
    rsc <- regime_dt[Date == rd, Regime_Score_Lag]
    if (is.na(rsc) || length(rsc) == 0L) rsc <- 0
  } else {
    rsc <- 0
  }

  # M5: 5단계 계단식 core_w (Regime_Score_Lag 사용)
  core_w <- if (rsc < 20) 0.80 else if (rsc < 40) 0.65 else if (rsc < 60) 0.50 else if (rsc < 80) 0.35 else 0.20
  def_w  <- 1 - core_w

  # Core sleeve score
  core_score <- rep(0.0, nrow(fdt_wide)); n_core_valid <- 0L
  for (fn in CORE_FACTORS) {
    if (fn %in% names(fdt_wide) && sum(!is.na(fdt_wide[[fn]])) > 10L) {
      rnk <- frank(fdt_wide[[fn]], na.last = "keep", ties.method = "average") /
             sum(!is.na(fdt_wide[[fn]]))
      core_score <- core_score + ifelse(is.na(rnk), 0, rnk)
      n_core_valid <- n_core_valid + 1L
    }
  }
  if (n_core_valid > 0L) core_score <- core_score / n_core_valid

  # Defense sleeve score (M3: 3팩터)
  def_score <- rep(0.0, nrow(fdt_wide)); n_def_valid <- 0L
  for (fn in DEFENSE_FACTORS) {
    if (fn %in% names(fdt_wide) && sum(!is.na(fdt_wide[[fn]])) > 10L) {
      rnk <- frank(fdt_wide[[fn]], na.last = "keep", ties.method = "average") /
             sum(!is.na(fdt_wide[[fn]]))
      def_score <- def_score + ifelse(is.na(rnk), 0, rnk)
      n_def_valid <- n_def_valid + 1L
    }
  }
  if (n_def_valid > 0L) def_score <- def_score / n_def_valid

  fdt_wide[, Score := core_w * core_score + def_w * def_score]
  fdt_wide[, Date := sig_d]
  factor_list[[i]] <- fdt_wide[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
for (col in c("TradingValue", "AvgTV20")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
gc(verbose = FALSE)
cat(sprintf("  FACTORS: %s rows | %d dates (skip %d)\n",
            format(nrow(FACTORS), big.mark = ","), n_done, n_skipped))

# Phase 2a: Base simulation for DD reference NAV (C9: t-1 lag)
cat("[Phase 3] Base sim for DD Brake NAV reference...\n")
RAWDATA_ORIG <- copy(RAWDATA)
base_sim <- run_monthly_simulation(
  RAWDATA = RAWDATA, BM_DT = BM_DT,
  FACTORS = FACTORS,
  n_holdings = N_STOCKS,
  weight_method = "equal",
  commission = 0.0015,
  buffer_zone = list(keep_n = 50L, entry_n = 25L)
)
port_nav <- base_sim$DAILY_NAV_DT
setorder(port_nav, Date)

# C9: DD Brake with t-1 lag
dd_window <- 6L  # months (~126 trading days)
nav_vals <- port_nav$NAV
n_nav <- length(nav_vals)
cum_ret <- nav_vals / nav_vals[1] - 1

rolling_dd_fn <- function(cr, w_days) {
  sapply(seq_along(cr), function(i) {
    start <- max(1L, i - w_days + 1L)
    peak <- max(cr[start:i])
    if (peak <= -1) return(0)
    cur <- cr[i]
    dd <- (peak - cur) / (1 + peak)
    max(0, dd)
  })
}
# 6개월 = 약 126 거래일
dd_pct_daily <- rolling_dd_fn(cum_ret, 126L)
# C9: t-1 lag — same-day DD 사용 금지
dd_lag_daily <- c(0, dd_pct_daily[-n_nav])

DD_THRESHOLD <- 0.20
DD_SCALE <- 0.50
port_nav[, dd_lag := dd_lag_daily]
port_nav[, dd_scale := ifelse(dd_lag > DD_THRESHOLD, DD_SCALE, 1.0)]

# DD scale을 FACTORS의 월별 날짜에 매핑 (sig_d 기준 t-1 lag 방식)
signal_dates <- sort(unique(FACTORS$Date))
FACTORS[, dd_position_size := 1.0]  # default: full

for (sd in signal_dates) {
  sd_date <- as.Date(sd)
  # sig_d 이전 마지막 거래일의 dd_scale 사용 (t-1: sig_d 당일 제외)
  prev_rows <- port_nav[Date < sd_date]
  if (nrow(prev_rows) > 0L) {
    last_scale <- tail(prev_rows$dd_scale, 1L)
    FACTORS[Date == sd_date, dd_position_size := last_scale]
  }
}

# DD scale을 Score에 반영 (scale=0.5 → 낮은 Score 그룹으로 push)
# 방법: Score를 dd_position_size로 scaling → 0.5 시 score가 낮아져 사실상 포지션 감소
# 대안: N 컬럼으로 종목수 조절 (dd=0.5 → N_STOCKS * 0.5 = 15)
FACTORS[, N := as.integer(ceiling(N_STOCKS * dd_position_size))]
FACTORS[, N := pmax(N, 1L)]  # 최소 1종목

cat(sprintf("  DD Brake: %.1f%% of periods fully invested, %.1f%% at %.0f%% scale\n",
            100 * mean(FACTORS$dd_position_size == 1.0, na.rm = TRUE),
            100 * mean(FACTORS$dd_position_size < 1.0, na.rm = TRUE),
            100 * DD_SCALE))

# Phase 2b: Final backtest with DD-adjusted N
cat("[Phase 4] Final backtest with DD Brake...\n")
RAWDATA <- copy(RAWDATA_ORIG)
sim <- run_monthly_simulation(
  RAWDATA = RAWDATA, BM_DT = BM_DT,
  FACTORS = FACTORS,
  n_holdings = N_STOCKS,
  weight_method = "equal",
  commission = 0.0015,
  buffer_zone = list(keep_n = 50L, entry_n = 25L)
)

# Results
cat("[Phase 5] Hurdle evaluation...\n")
perf_strat <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
perf_bm    <- summarise_perf(sim$bm_xts, "BM")
cat(sprintf("  %s: CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
            STRATEGY_ID, perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD))

generate_charts(sim, output_dir = OUTPUT_DIR, strategy_name = STRATEGY_NAME)
fwrite(rbind(perf_strat, perf_bm), file.path(OUTPUT_DIR, "performance.csv"))
saveRDS(sim, file.path(OUTPUT_DIR, "sim_result.rds"))

source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(
  sim_result = sim, FACTORS = FACTORS,
  strategy_name = STRATEGY_NAME,
  strategy_file = file.path(STR_DIR, "factor_engine.R"),
  output_dir = OUTPUT_DIR
)
jsonlite::write_json(hurdle, file.path(OUTPUT_DIR, "hurdle_result.json"),
                     auto_unbox = TRUE, pretty = TRUE)

cat(sprintf("[STR_1621_M9] Grade=%s | Score=%.1f | SR=%.3f | CAGR=%.1f%% | MDD=%.1f%%\n",
    hurdle$grade %||% "N/A",
    hurdle$total_score %||% hurdle$score %||% 0,
    hurdle$metrics$sharpe_ratio %||% perf_strat$Sharpe,
    (hurdle$metrics$cagr %||% perf_strat$CAGR / 100) * 100,
    (hurdle$metrics$max_drawdown %||% perf_strat$MDD / 100) * 100))

cat("=== STR_1621_M9 Complete (synthesis_tested=TRUE) ===\n")
