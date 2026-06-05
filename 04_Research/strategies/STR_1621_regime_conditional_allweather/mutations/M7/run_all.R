cat("=== STR_1621_M7: IVol 역가중 — Score Top30 선택 후 IVol 역가중 ===\n")
## C9: ivol_lag = t-1 rolling 60d vol. EW fallback on IVol NA.
## Leote de Carvalho et al. 2012: IVol weighting reduces MDD
set.seed(1621); options(scipen=999); Sys.setenv(TZ="Asia/Seoul")
STRATEGY_NAME <- "STR_1621_M7_IVolWeight"; STRATEGY_ID <- "STR_1621_M7"

PROJ_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
INFRA_DIR <- file.path(PROJ_ROOT, "02_Infrastructure")
CACHE_DIR <- file.path(PROJ_ROOT, ".cache")
STR_DIR   <- file.path(PROJ_ROOT, "04_Research/strategies/STR_1621_regime_conditional_allweather")
OUTPUT_DIR <- file.path(STR_DIR, "mutations/M7/output")
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
regime_dt[, Regime_Score_Lag := shift(Regime_Score, n = 1L, type = "lag")]
setkey(regime_dt, Date)

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

# C9: IVol = rolling 60d std(Ret), t-1 lag by Ticker
cat("  Computing IVol (rolling 60d, t-1 lag) by Ticker...\n")
RAWDATA[, IVol_60d := frollapply(Ret, n = 60L, FUN = sd, align = "right"), by = Ticker]
RAWDATA[, IVol_lag := shift(IVol_60d, n = 1L, type = "lag"), by = Ticker]

factor_list <- vector("list", length(monthly_dates))
n_done <- 0L; n_skipped <- 0L

for (i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i])
  fdt <- tryCatch(load_month_factors(sig_d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }
  fdt <- fdt[Factor_Name %in% NEEDED_FACTORS]
  if (nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }

  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  liq <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20, IVol_lag)]
  fdt_wide <- merge(fdt_wide, liq, by = "Ticker")
  fdt_wide <- fdt_wide[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(fdt_wide) < 20L) { n_skipped <- n_skipped + 1L; next }

  valid_regime_dates <- regime_dt$Date[regime_dt$Date <= sig_d & !is.na(regime_dt$Regime_Score_Lag)]
  rsc <- if (length(valid_regime_dates) > 0L) {
    rd <- max(valid_regime_dates); v <- regime_dt[Date == rd, Regime_Score_Lag]
    if (is.na(v) || length(v) == 0L) 0 else v
  } else 0
  core_w <- max(0.2, 1 - rsc / 100); def_w <- 1 - core_w

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

  # IVol 역가중: Score 기반 Top30 선택 후 IVol 역수 비례 가중
  # IVol_lag 컬럼을 Score 컬럼에 encoded: 역가중은 backtest_harness에서 직접 적용 불가
  # 대신 FACTORS에 Weight 컬럼을 추가하여 harness에서 활용 (ivol weighting mode)
  # backtest_harness의 "ivol" weight_method를 사용: RAWDATA에서 직접 계산
  # 여기서는 Score를 IVol 조정 Score로 변환 (고IVol 종목 score 감소)
  fdt_wide <- fdt_wide[!is.na(Score)]
  setorder(fdt_wide, -Score)
  top_n <- min(N_STOCKS, nrow(fdt_wide))
  fdt_top <- fdt_wide[1:top_n]

  # IVol 역가중 계산 (t-1 lag 이미 적용된 IVol_lag 사용)
  ivol_vals <- fdt_top$IVol_lag
  has_ivol <- !is.na(ivol_vals) & ivol_vals > 0
  if (sum(has_ivol) >= 5L) {
    inv_ivol <- ifelse(has_ivol, 1 / ivol_vals, 0)
    total_inv <- sum(inv_ivol)
    if (total_inv > 0) {
      w_raw <- inv_ivol / total_inv
      # Cap 10%
      w_capped <- pmin(w_raw, 0.10)
      w_capped <- w_capped / sum(w_capped)
      # IVol 가중 Score로 재변환: w_i * rank로 Score 재표현
      # Score에 w_capped 비례 반영 (순위 역할 유지)
      fdt_top[, Score := w_capped * 1000]  # 가중 점수
    }
  }
  # EW fallback: IVol 미충족 시 기존 Score 유지

  fdt_top[, Date := sig_d]
  factor_list[[i]] <- fdt_top[, .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
for (col in c("TradingValue", "AvgTV20", "IVol_60d", "IVol_lag")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
gc(verbose = FALSE)
cat(sprintf("  FACTORS: %s rows | %d dates\n", format(nrow(FACTORS), big.mark=","), n_done))

# IVol 역가중 전략: weight_method="ivol" 사용 (backtest_harness 내 계산)
sim <- run_monthly_simulation(
  RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
  n_holdings = N_STOCKS, weight_method = "ivol",  # M7: IVol 역가중
  commission = 0.0015,
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

cat(sprintf("[STR_1621_M7] Grade=%s | Score=%.1f | SR=%.3f | CAGR=%.1f%% | MDD=%.1f%%\n",
    hurdle$grade %||% "N/A", hurdle$total_score %||% hurdle$score %||% 0,
    hurdle$metrics$sharpe_ratio %||% perf_strat$Sharpe,
    (hurdle$metrics$cagr %||% perf_strat$CAGR / 100) * 100,
    (hurdle$metrics$max_drawdown %||% perf_strat$MDD / 100) * 100))
cat("=== STR_1621_M7 Complete ===\n")
