cat("=== TEST-KR-G1-01: Quality-as-Defense Gate Filter ===\n")
cat("=== 근거: KR-009 (220년 방어), KR-012 (MDD 감소 순차필터) ===\n")
cat("=== 가설: Quality gate(Q08+Q04+Q24) 적용 시 위기 IC 개선 + MDD 감소 ===\n")

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/backtest_harness.R")
})
library(data.table); library(arrow)

# ── 1. 데이터 로드 ────────────────────────────────────────────────
cat("[G1-01] Step 1: Loading data...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA)
rm(res); gc(verbose = FALSE)
cat(sprintf("  RAWDATA: %s rows\n", format(nrow(RAWDATA), big.mark = ",")))

# ── 2. Quality Gate Factor Engine ─────────────────────────────────
cat("[G1-01] Step 2: Building FACTORS with quality gate...\n")

source("02_Infrastructure/factor_db_connector.R")
LIQ_THRESHOLD <- 2e8

NEEDED_FACTORS <- c(
  "Q08_Composite_Quality", "Q04_Piotroski_F", "Q24_Altman_Z",
  "Q01_GPA", "C19_Composite_Earnings"
)

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y%m")]
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

  # C15: load_month_factors() 경유
  fdt <- tryCatch(
    load_month_factors(sig_d, coverage_min = 0.05),
    error = function(e) NULL
  )
  if (is.null(fdt) || nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }
  fdt <- fdt[Factor_Name %in% NEEDED_FACTORS]
  if (nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }

  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  # Liquidity filter (t-1 lag)
  liq <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20)]
  fdt_wide <- merge(fdt_wide, liq, by = "Ticker")
  fdt_wide <- fdt_wide[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(fdt_wide) < 30L) { n_skipped <- n_skipped + 1L; next }

  # Quality Gate 1: Q08 >= median (cross-sectional, 당월 기준)
  if ("Q08_Composite_Quality" %in% names(fdt_wide)) {
    q08_med <- median(fdt_wide$Q08_Composite_Quality, na.rm = TRUE)
    fdt_wide[, pass_q08 := !is.na(Q08_Composite_Quality) &
               Q08_Composite_Quality >= q08_med]
  } else {
    fdt_wide[, pass_q08 := TRUE]
  }

  # Quality Gate 2: Piotroski Z >= 0 AND Altman Z >= 0 (상위 50%)
  fdt_wide[, pass_q2 := TRUE]
  if ("Q04_Piotroski_F" %in% names(fdt_wide)) {
    fdt_wide[!is.na(Q04_Piotroski_F) & Q04_Piotroski_F < 0, pass_q2 := FALSE]
  }
  if ("Q24_Altman_Z" %in% names(fdt_wide)) {
    fdt_wide[!is.na(Q24_Altman_Z) & Q24_Altman_Z < 0, pass_q2 := FALSE]
  }

  # Gate 적용
  qualified <- fdt_wide[pass_q08 == TRUE & pass_q2 == TRUE]
  if (nrow(qualified) < 30L) qualified <- fdt_wide[pass_q08 == TRUE]
  if (nrow(qualified) < 20L) { n_skipped <- n_skipped + 1L; next }

  # Score: Q01_GPA 우선, 없으면 C19
  if ("Q01_GPA" %in% names(qualified) &&
      sum(!is.na(qualified$Q01_GPA)) > 10L) {
    qualified[, Score := frank(Q01_GPA, na.last = "keep",
                               ties.method = "average") /
                sum(!is.na(Q01_GPA))]
  } else if ("C19_Composite_Earnings" %in% names(qualified) &&
             sum(!is.na(qualified$C19_Composite_Earnings)) > 10L) {
    qualified[, Score := frank(C19_Composite_Earnings, na.last = "keep",
                               ties.method = "average") /
                sum(!is.na(C19_Composite_Earnings))]
  } else {
    n_skipped <- n_skipped + 1L; next
  }

  qualified[, Date := sig_d]
  factor_list[[i]] <- qualified[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)

# Cleanup
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
for (col in c("TradingValue", "AvgTV20")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
gc(verbose = FALSE)
cat(sprintf("  FACTORS: %s rows | %d dates (skip %d)\n",
            format(nrow(FACTORS), big.mark = ","), n_done, n_skipped))

# ── 3. 백테스트 실행 ──────────────────────────────────────────────
cat("[G1-01] Step 3: Running backtest (N=30, EW, 15bps)...\n")
RAWDATA <- copy(RAWDATA_ORIG)
sim <- run_monthly_simulation(
  RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
  n_holdings = 30L, weight_method = "equal",
  commission = 0.0015,
  buffer_zone = list(keep_n = 50L, entry_n = 25L)
)

# ── 4. 성과 분석 ─────────────────────────────────────────────────
cat("[G1-01] Step 4: Performance analysis...\n")
STRATEGY_NAME <- "G1_01_Quality_Defense_Gate"
out_dir <- "04_Research/korea_research/G1_01_output"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

perf_strat <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
perf_bm <- summarise_perf(sim$bm_xts, "BM")
cat(sprintf("  %s: CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
            STRATEGY_NAME, perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD))
cat(sprintf("  BM:     CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
            perf_bm$CAGR, perf_bm$Sharpe, perf_bm$MDD))
generate_charts(sim, output_dir = out_dir, strategy_name = STRATEGY_NAME)
fwrite(rbind(perf_strat, perf_bm), file.path(out_dir, "performance.csv"))
saveRDS(sim, file.path(out_dir, "sim_result.rds"))

# Strategy analyzer
RAWDATA <- copy(RAWDATA_ORIG)
tryCatch({
  source("02_Infrastructure/strategy_analyzer.R")
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, out_dir,
               strategy_name = STRATEGY_NAME)
}, error = function(e) cat("[WARN] Analyzer:", e$message, "\n"))

# ── 5. 허들 게이트 ───────────────────────────────────────────────
cat("[G1-01] Step 5: Hurdle gate...\n")
source("02_Infrastructure/hurdle_gate.R")
hurdle <- run_hurdle_gate(
  sim_result = sim, FACTORS = FACTORS,
  strategy_name = STRATEGY_NAME,
  strategy_file = "04_Research/korea_research/G1_01_quality_defense_gate.R",
  output_dir = out_dir
)
jsonlite::write_json(hurdle, file.path(out_dir, "hurdle_result.json"),
                     auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("  Grade: %s | Score: %.1f\n",
            hurdle$grade, hurdle$verdict$total_score %||% hurdle$score %||% 0))

cat(sprintf("\n[G1-01] Complete. Output: %s\n", out_dir))
