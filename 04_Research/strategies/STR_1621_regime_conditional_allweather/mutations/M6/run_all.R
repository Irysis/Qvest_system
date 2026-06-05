cat("=== STR_1621_M6: Regime Score → Expanding Percentile 정규화 ===\n")
## C1 준수: expanding percentile은 sig_d 이전 데이터만 (full-sample 금지)
## Ang & Timmermann 2012: non-stationary regime score → percentile 변환으로 스케일 불변성
set.seed(1621); options(scipen=999); Sys.setenv(TZ="Asia/Seoul")
STRATEGY_NAME <- "STR_1621_M6_RegimePercentile"; STRATEGY_ID <- "STR_1621_M6"

PROJ_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
INFRA_DIR <- file.path(PROJ_ROOT, "02_Infrastructure")
CACHE_DIR <- file.path(PROJ_ROOT, ".cache")
STR_DIR   <- file.path(PROJ_ROOT, "04_Research/strategies/STR_1621_regime_conditional_allweather")
OUTPUT_DIR <- file.path(STR_DIR, "mutations/M6/output")
dir.create(OUTPUT_DIR, recursive=TRUE, showWarnings=FALSE)

source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
suppressPackageStartupMessages(library(data.table))
suppressPackageStartupMessages(library(dplyr))

LIQ_THRESHOLD <- 2e8; N_STOCKS <- 30L
CORE_FACTORS    <- c("C19_Composite_Earnings", "V14_EBIT_EV")
DEFENSE_FACTORS <- c("D01_IdioVol", "D44_Kurtosis")
NEEDED_FACTORS  <- c(CORE_FACTORS, DEFENSE_FACTORS)

source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
source(file.path(REGIME_DIR, "regime_signal.R"))
regime_dt <- tryCatch({
  r <- load_regime_signal()
  if (is.null(r) || nrow(r) == 0L) build_regime_signal_table() else r
}, error = function(e) build_regime_signal_table())
regime_dt[, Date := as.Date(Date)]
setorder(regime_dt, Date)
# t-1 lag: Regime_Score_Lag
regime_dt[, Regime_Score_Lag := shift(Regime_Score, n = 1L, type = "lag")]
setkey(regime_dt, Date)

# C1: Expanding percentile 계산 — full-sample 금지
# 각 시점 t에서 t-1까지의 Regime_Score_Lag 분포에서 percentile 계산
# 최소 관측치 12개 이상 시만 percentile 적용, 미만 시 0.5(NEUTRAL) 사용
regime_dt_ordered <- regime_dt[!is.na(Regime_Score_Lag)]
setorder(regime_dt_ordered, Date)
n_regime <- nrow(regime_dt_ordered)

# Expanding percentile (C1 준수: 시점 i에서는 1:(i-1) 데이터만)
regime_dt_ordered[, p_score_lag := {
  p <- rep(NA_real_, .N)
  for (idx in seq_len(.N)) {
    if (idx < 13L) {
      p[idx] <- 0.5  # 데이터 부족 시 NEUTRAL
    } else {
      # idx-1까지 데이터로 percentile 계산 (C1: 현재 시점 제외)
      hist_scores <- Regime_Score_Lag[1:(idx - 1L)]
      cur_score   <- Regime_Score_Lag[idx]
      p[idx] <- mean(hist_scores < cur_score, na.rm = TRUE)
    }
  }
  p
}]
setkey(regime_dt_ordered, Date)

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

factor_list <- vector("list", length(monthly_dates))
n_done <- 0L; n_skipped <- 0L

for (i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i])
  fdt <- tryCatch(load_month_factors(sig_d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }
  fdt <- fdt[Factor_Name %in% NEEDED_FACTORS]
  if (nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }

  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  liq <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20)]
  fdt_wide <- merge(fdt_wide, liq, by = "Ticker")
  fdt_wide <- fdt_wide[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(fdt_wide) < 20L) { n_skipped <- n_skipped + 1L; next }

  # Regime percentile (t-1 lag + expanding — C1 준수)
  valid_dates <- regime_dt_ordered$Date[regime_dt_ordered$Date <= sig_d & !is.na(regime_dt_ordered$p_score_lag)]
  p_score <- if (length(valid_dates) > 0L) {
    rd <- max(valid_dates)
    v <- regime_dt_ordered[Date == rd, p_score_lag]
    if (is.na(v) || length(v) == 0L) 0.5 else v
  } else 0.5

  # core_w = max(0.2, 1 - p_score) (C5: t-1 lag 적용된 p_score 사용)
  core_w <- max(0.2, 1 - p_score); def_w <- 1 - core_w

  core_score <- rep(0.0, nrow(fdt_wide)); n_core_valid <- 0L
  for (fn in CORE_FACTORS) {
    if (fn %in% names(fdt_wide) && sum(!is.na(fdt_wide[[fn]])) > 10L) {
      rnk <- frank(fdt_wide[[fn]], na.last = "keep", ties.method = "average") / sum(!is.na(fdt_wide[[fn]]))
      core_score <- core_score + ifelse(is.na(rnk), 0, rnk); n_core_valid <- n_core_valid + 1L
    }
  }
  if (n_core_valid > 0L) core_score <- core_score / n_core_valid

  def_score <- rep(0.0, nrow(fdt_wide)); n_def_valid <- 0L
  for (fn in DEFENSE_FACTORS) {
    if (fn %in% names(fdt_wide) && sum(!is.na(fdt_wide[[fn]])) > 10L) {
      rnk <- frank(fdt_wide[[fn]], na.last = "keep", ties.method = "average") / sum(!is.na(fdt_wide[[fn]]))
      def_score <- def_score + ifelse(is.na(rnk), 0, rnk); n_def_valid <- n_def_valid + 1L
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
for (col in c("TradingValue", "AvgTV20")) { if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL] }
gc(verbose = FALSE)
cat(sprintf("  FACTORS: %s rows | %d dates\n", format(nrow(FACTORS), big.mark=","), n_done))

sim <- run_monthly_simulation(
  RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
  n_holdings = N_STOCKS, weight_method = "equal", commission = 0.0015,
  buffer_zone = list(keep_n = 50L, entry_n = 25L)
)

perf_strat <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
perf_bm    <- summarise_perf(sim$bm_xts, "BM")
cat(sprintf("  %s: CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n", STRATEGY_ID, perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD))
generate_charts(sim, output_dir=OUTPUT_DIR, strategy_name=STRATEGY_NAME)
fwrite(rbind(perf_strat, perf_bm), file.path(OUTPUT_DIR, "performance.csv"))
saveRDS(sim, file.path(OUTPUT_DIR, "sim_result.rds"))

source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result=sim, FACTORS=FACTORS, strategy_name=STRATEGY_NAME,
                          strategy_file=file.path(STR_DIR, "factor_engine.R"), output_dir=OUTPUT_DIR)
jsonlite::write_json(hurdle, file.path(OUTPUT_DIR, "hurdle_result.json"), auto_unbox=TRUE, pretty=TRUE)

cat(sprintf("[STR_1621_M6] Grade=%s | Score=%.1f | SR=%.3f | CAGR=%.1f%% | MDD=%.1f%%\n",
    hurdle$grade %||% "N/A", hurdle$total_score %||% hurdle$score %||% 0,
    hurdle$metrics$sharpe_ratio %||% perf_strat$Sharpe,
    (hurdle$metrics$cagr %||% perf_strat$CAGR / 100) * 100,
    (hurdle$metrics$max_drawdown %||% perf_strat$MDD / 100) * 100))
cat("=== STR_1621_M6 Complete ===\n")
