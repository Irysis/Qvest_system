cat("=== TEST-KR-INT01: Quality-Gated Low-Risk Defense ===\n")
cat("=== 근거: KR-001 (Kim 2021, PBFJ) x KR-002 (박종원 2024) ===\n")
cat("=== 가설: Quality Gate + Low-risk = 순수 롱온리 defense alpha ===\n")

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/backtest_harness.R")
})
library(data.table); library(arrow)

# ── 1. 데이터 ─────────────────────────────────────────────────────
cat("[INT-01] Step 1: Loading data...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA)
rm(res); gc(verbose = FALSE)

source("02_Infrastructure/factor_db_connector.R")
LIQ_THRESHOLD <- 2e8

NEEDED_FACTORS <- c("Q08_Composite_Quality", "Q01_GPA", "D01_IdioVol", "D03_RealVol")

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y%m")]
monthly_dates <- sort(RAWDATA[, .(SD = max(Date)), by = YM]$SD)
all_dates <- sort(unique(RAWDATA$Date))
monthly_dates <- monthly_dates[monthly_dates >= all_dates[min(253L, length(all_dates))]]
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]
RAWDATA_ORIG <- copy(RAWDATA)

# ── 2. 3가지 변형 Factor 구성 ────────────────────────────────────
cat("[INT-01] Step 2: Building 3 variants (A: ungated lowrisk, B: quality-gated lowrisk, C: pure quality)...\n")

build_variant <- function(variant) {
  # variant: "A" = pure lowrisk, "B" = quality-gated lowrisk, "C" = pure quality
  factor_list <- vector("list", length(monthly_dates))
  n_done <- 0L; n_skipped <- 0L

  for (i in seq_along(monthly_dates)) {
    sig_d <- as.Date(monthly_dates[i])

    fdt <- tryCatch(load_month_factors(sig_d, coverage_min = 0.05),
                    error = function(e) NULL)
    if (is.null(fdt) || nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }
    fdt <- fdt[Factor_Name %in% NEEDED_FACTORS]
    if (nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }

    fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

    liq <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20)]
    fdt_wide <- merge(fdt_wide, liq, by = "Ticker")
    fdt_wide <- fdt_wide[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
    if (nrow(fdt_wide) < 30L) { n_skipped <- n_skipped + 1L; next }

    if (variant == "B") {
      # Quality Gate: Q08 or Q01 하위 30% 제외
      q_col <- if ("Q08_Composite_Quality" %in% names(fdt_wide)) {
        "Q08_Composite_Quality"
      } else if ("Q01_GPA" %in% names(fdt_wide)) {
        "Q01_GPA"
      } else { NULL }

      if (!is.null(q_col) && sum(!is.na(fdt_wide[[q_col]])) > 20L) {
        q30 <- quantile(fdt_wide[[q_col]], 0.30, na.rm = TRUE)
        fdt_wide <- fdt_wide[is.na(get(q_col)) | get(q_col) >= q30]
      }
      if (nrow(fdt_wide) < 30L) { n_skipped <- n_skipped + 1L; next }
    }

    # Score
    if (variant == "C") {
      # Pure quality: rank by Q01_GPA
      score_col <- if ("Q01_GPA" %in% names(fdt_wide)) "Q01_GPA" else
        if ("Q08_Composite_Quality" %in% names(fdt_wide)) "Q08_Composite_Quality" else NULL
      if (is.null(score_col) || sum(!is.na(fdt_wide[[score_col]])) < 20L) {
        n_skipped <- n_skipped + 1L; next
      }
      fdt_wide[, Score := frank(get(score_col), na.last = "keep",
                                 ties.method = "average") /
                  sum(!is.na(get(score_col)))]
    } else {
      # Low-risk: D01_IdioVol (낮을수록 좋음 → Z_Score_Aligned 이미 방향 정렬)
      lr_col <- if ("D01_IdioVol" %in% names(fdt_wide)) "D01_IdioVol" else
        if ("D03_RealVol" %in% names(fdt_wide)) "D03_RealVol" else NULL
      if (is.null(lr_col) || sum(!is.na(fdt_wide[[lr_col]])) < 20L) {
        n_skipped <- n_skipped + 1L; next
      }
      fdt_wide[, Score := frank(get(lr_col), na.last = "keep",
                                 ties.method = "average") /
                  sum(!is.na(get(lr_col)))]
    }

    fdt_wide[, Date := sig_d]
    factor_list[[i]] <- fdt_wide[!is.na(Score), .(Date, Ticker, Score)]
    n_done <- n_done + 1L
  }

  result <- rbindlist(factor_list[!sapply(factor_list, is.null)])
  setorder(result, Date, -Score)
  cat(sprintf("  [Variant %s] %s rows | %d dates (skip %d)\n",
              variant, format(nrow(result), big.mark = ","), n_done, n_skipped))
  result
}

# ── 3. 순차 백테스트 ─────────────────────────────────────────────
cat("\n[INT-01] Step 3: Running backtests...\n")
variant_names <- c(A = "Ungated_LowRisk", B = "QualityGated_LowRisk", C = "Pure_Quality")
results <- list()

for (v in c("A", "B", "C")) {
  cat(sprintf("  Variant %s (%s)...\n", v, variant_names[v]))
  FACTORS <- build_variant(v)
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
    strat_name <- variant_names[v]
    perf <- summarise_perf(sim$strategy_xts, strat_name)
    cat(sprintf("    SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n",
                perf$Sharpe, perf$CAGR, perf$MDD))

    results[[v]] <- data.table(
      variant = v, name = strat_name,
      CAGR = perf$CAGR, Sharpe = perf$Sharpe, MDD = perf$MDD
    )

    out_dir <- sprintf("04_Research/korea_research/INT_01_output/%s", v)
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(sim, file.path(out_dir, "sim_result.rds"))
    tryCatch(generate_charts(sim, output_dir = out_dir, strategy_name = strat_name),
             error = function(e) NULL)

    # Stress analysis
    tryCatch({
      source("02_Infrastructure/strategy_analyzer.R")
      run_analysis(sim, FACTORS, copy(RAWDATA_ORIG), BM_DT, out_dir,
                   strategy_name = strat_name)
    }, error = function(e) cat(sprintf("    Analyzer: %s\n", e$message)))
  }
}

# ── 4. 비교 분석 ─────────────────────────────────────────────────
cat("\n[INT-01] Step 4: Comparison\n")
comparison <- rbindlist(results)
print(comparison)

if ("A" %in% comparison$variant && "B" %in% comparison$variant) {
  a_row <- comparison[variant == "A"]
  b_row <- comparison[variant == "B"]
  cat(sprintf("\n=== Quality Gate Effect ===\n"))
  cat(sprintf("  SR improvement:  %.3f → %.3f (%+.3f)\n",
              a_row$Sharpe, b_row$Sharpe, b_row$Sharpe - a_row$Sharpe))
  cat(sprintf("  MDD improvement: %.1f%% → %.1f%% (%+.1f%%p)\n",
              a_row$MDD, b_row$MDD, b_row$MDD - a_row$MDD))
  cat(sprintf("  CAGR:            %.2f%% → %.2f%% (%+.2f%%p)\n",
              a_row$CAGR, b_row$CAGR, b_row$CAGR - a_row$CAGR))
}

out_dir_main <- "04_Research/korea_research/INT_01_output"
dir.create(out_dir_main, recursive = TRUE, showWarnings = FALSE)
fwrite(comparison, file.path(out_dir_main, "comparison.csv"))

cat("\n[INT-01] Complete.\n")
