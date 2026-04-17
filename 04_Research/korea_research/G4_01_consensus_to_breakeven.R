cat("=== TEST-KR-G4-01: Consensus Factor Turnover Break-Even ===\n")
cat("=== 근거: Gap 4 (Turnover), KR-019 (Bounded Tilt TO 내장 통제) ===\n")
cat("=== 가설: Consensus 팩터 신호 안정성이 높아 TO break-even 15bps 달성 가능 ===\n")

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/backtest_harness.R")
})
library(data.table); library(arrow)

# ── 1. 데이터 ─────────────────────────────────────────────────────
cat("[G4-01] Step 1: Loading data...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA)
rm(res); gc(verbose = FALSE)

source("02_Infrastructure/factor_db_connector.R")
LIQ_THRESHOLD <- 2e8

# ── 2. 3가지 팩터 비교 (C19 vs C02 vs SE02) ──────────────────────
cat("[G4-01] Step 2: Building FACTORS for 3 consensus variants...\n")

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y%m")]
monthly_dates <- sort(RAWDATA[, .(SD = max(Date)), by = YM]$SD)
all_dates <- sort(unique(RAWDATA$Date))
monthly_dates <- monthly_dates[monthly_dates >= all_dates[min(253L, length(all_dates))]]
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]
RAWDATA_ORIG <- copy(RAWDATA)

build_single_factor <- function(factor_name) {
  factor_list <- vector("list", length(monthly_dates))
  n_done <- 0L; n_skipped <- 0L

  for (i in seq_along(monthly_dates)) {
    sig_d <- as.Date(monthly_dates[i])
    fdt <- tryCatch(load_month_factors(sig_d, coverage_min = 0.05),
                    error = function(e) NULL)
    if (is.null(fdt) || nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }
    fdt <- fdt[Factor_Name == factor_name]
    if (nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }

    fdt_wide <- fdt[, .(Ticker, Score_raw = Z_Score_Aligned)]
    liq <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20)]
    fdt_wide <- merge(fdt_wide, liq, by = "Ticker")
    fdt_wide <- fdt_wide[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
    if (nrow(fdt_wide) < 30L) { n_skipped <- n_skipped + 1L; next }

    fdt_wide[, Score := frank(Score_raw, na.last = "keep",
                               ties.method = "average") /
                sum(!is.na(Score_raw))]
    fdt_wide[, Date := sig_d]
    factor_list[[i]] <- fdt_wide[!is.na(Score), .(Date, Ticker, Score)]
    n_done <- n_done + 1L
  }

  result <- rbindlist(factor_list[!sapply(factor_list, is.null)])
  setorder(result, Date, -Score)
  cat(sprintf("  [%s] %s rows | %d dates\n", factor_name,
              format(nrow(result), big.mark = ","), n_done))
  result
}

test_factors <- c("C19_Composite_Earnings", "C02_EPS_Chg_1m", "SE02_Consensus_Revision")

# ── 3. 순차 백테스트 + TO 분석 ────────────────────────────────────
cat("[G4-01] Step 3: Running backtests...\n")
results <- list()

for (fn in test_factors) {
  cat(sprintf("  Factor: %s\n", fn))
  FACTORS <- build_single_factor(fn)
  if (nrow(FACTORS) == 0L) { cat("    SKIP\n"); next }

  RAWDATA <- copy(RAWDATA_ORIG)
  sim <- tryCatch(
    run_monthly_simulation(
      RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
      n_holdings = 30L, weight_method = "equal",
      commission = 0.0015,
      buffer_zone = list(keep_n = 50L, entry_n = 25L)
    ),
    error = function(e) { cat(sprintf("    ERROR: %s\n", e$message)); NULL }
  )

  if (!is.null(sim)) {
    perf <- summarise_perf(sim$strategy_xts, fn)
    # TO 계산
    to_ann <- if ("Turnover_Ann" %in% names(perf)) perf$Turnover_Ann else NA_real_

    # Break-even: 15bps per round-trip
    gross_perf <- summarise_perf(sim$strategy_xts, fn)
    cat(sprintf("    SR=%.3f CAGR=%.2f%% MDD=%.1f%% TO=%.0f%%\n",
                perf$Sharpe, perf$CAGR, perf$MDD, to_ann))

    results[[fn]] <- data.table(
      factor = fn, CAGR = perf$CAGR, Sharpe = perf$Sharpe,
      MDD = perf$MDD, Turnover_Ann = to_ann
    )

    out_dir <- sprintf("04_Research/korea_research/G4_01_output/%s",
                       gsub("[^A-Za-z0-9]", "_", fn))
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(sim, file.path(out_dir, "sim_result.rds"))
    tryCatch(generate_charts(sim, output_dir = out_dir, strategy_name = fn),
             error = function(e) NULL)
  }
}

# ── 4. 비교 ──────────────────────────────────────────────────────
cat("\n[G4-01] Step 4: TO Break-Even Analysis\n")
comparison <- rbindlist(results)
# Break-even: 15bps = 0.0015. TO costs = Turnover * commission
comparison[, TO_Cost_bps := Turnover_Ann * 15]
comparison[, Gross_Alpha_bps := (CAGR - 9.6) * 100]  # vs BM ~9.6%
comparison[, Break_Even := fifelse(Gross_Alpha_bps > TO_Cost_bps,
                                    "PASS", "FAIL")]
print(comparison)

out_dir_main <- "04_Research/korea_research/G4_01_output"
dir.create(out_dir_main, recursive = TRUE, showWarnings = FALSE)
fwrite(comparison, file.path(out_dir_main, "comparison.csv"))
cat("\n[G4-01] Complete.\n")
