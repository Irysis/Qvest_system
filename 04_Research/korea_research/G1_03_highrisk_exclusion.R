cat("=== TEST-KR-G1-03: High-Risk Exclusion (IdioVol/MAX Top 20%) ===\n")
cat("=== 근거: KR-002 (박종원 2024 — 롱온리 숏사이드 의존) ===\n")
cat("=== 가설: C19 포트폴리오에서 고위험 종목 제거 시 MDD 개선 ===\n")

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/backtest_harness.R")
})
library(data.table); library(arrow)

# ── 1. 데이터 ─────────────────────────────────────────────────────
cat("[G1-03] Step 1: Loading data...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
rm(res); gc(verbose = FALSE)
cat(sprintf("  RAWDATA: %s rows\n", format(nrow(RAWDATA), big.mark = ",")))

# ── 2. Factor 준비 (4 variants) ──────────────────────────────────
cat("[G1-03] Step 2: Building FACTORS for 4 variants...\n")

source("02_Infrastructure/factor_db_connector.R")
LIQ_THRESHOLD <- 2e8

NEEDED_FACTORS <- c("C19_Composite_Earnings", "D01_IdioVol")

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y%m")]
monthly_dates <- sort(RAWDATA[, .(SD = max(Date)), by = YM]$SD)
all_dates <- sort(unique(RAWDATA$Date))
monthly_dates <- monthly_dates[monthly_dates >= all_dates[min(253L, length(all_dates))]]

# Liquidity: TradingValue + AvgTV20 on RAWDATA (before ORIG copy)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]
# Keep AvgTV20 in ORIG so sim copies also have it
RAWDATA_ORIG <- copy(RAWDATA)

build_factors_variant <- function(exclude_type) {
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

    # MAX_Ret: 직전 21거래일 최대 수익률 (C9 준수: sig_d 이전)
    max_window <- RAWDATA[
      Ticker %in% fdt_wide$Ticker & Date < sig_d & Date >= sig_d - 30,
      .(MAX_Ret = max(Ret, na.rm = TRUE)),
      by = Ticker
    ]
    fdt_wide <- merge(fdt_wide, max_window, by = "Ticker", all.x = TRUE)

    # Exclusion
    if (exclude_type == "none") {
      qualified <- copy(fdt_wide)
    } else if (exclude_type == "idiovol") {
      if ("D01_IdioVol" %in% names(fdt_wide) &&
          sum(!is.na(fdt_wide$D01_IdioVol)) > 10L) {
        cutoff <- quantile(fdt_wide$D01_IdioVol, 0.80, na.rm = TRUE)
        qualified <- fdt_wide[is.na(D01_IdioVol) | D01_IdioVol < cutoff]
      } else {
        qualified <- copy(fdt_wide)
      }
    } else if (exclude_type == "max") {
      if (sum(!is.na(fdt_wide$MAX_Ret)) > 10L) {
        cutoff <- quantile(fdt_wide$MAX_Ret, 0.80, na.rm = TRUE)
        qualified <- fdt_wide[is.na(MAX_Ret) | MAX_Ret < cutoff]
      } else {
        qualified <- copy(fdt_wide)
      }
    } else if (exclude_type == "both") {
      qualified <- copy(fdt_wide)
      if ("D01_IdioVol" %in% names(fdt_wide) &&
          sum(!is.na(fdt_wide$D01_IdioVol)) > 10L) {
        iv_cut <- quantile(fdt_wide$D01_IdioVol, 0.80, na.rm = TRUE)
        qualified <- qualified[is.na(D01_IdioVol) | D01_IdioVol < iv_cut]
      }
      if (sum(!is.na(qualified$MAX_Ret)) > 10L) {
        mx_cut <- quantile(qualified$MAX_Ret, 0.80, na.rm = TRUE)
        qualified <- qualified[is.na(MAX_Ret) | MAX_Ret < mx_cut]
      }
    }

    if (nrow(qualified) < 20L) { n_skipped <- n_skipped + 1L; next }

    # Score: C19
    if ("C19_Composite_Earnings" %in% names(qualified) &&
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
  cat(sprintf("  [%s] FACTORS: %s rows | %d dates (skip %d)\n",
              exclude_type, format(nrow(FACTORS), big.mark = ","), n_done, n_skipped))
  FACTORS
}

# ── 3. 4가지 백테스트 ─────────────────────────────────────────────
cat("[G1-03] Step 3: Running 4 variants...\n")
variants <- c("none", "idiovol", "max", "both")
results <- list()

for (v in variants) {
  cat(sprintf("  Variant: %s...\n", v))
  FACTORS_v <- build_factors_variant(v)

  if (nrow(FACTORS_v) == 0L) {
    cat("    SKIP: no FACTORS built\n")
    next
  }

  RAWDATA <- copy(RAWDATA_ORIG)
  sim <- tryCatch(
    run_monthly_simulation(
      RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS_v,
      n_holdings = 30L, weight_method = "equal",
      commission = 0.0015,
      buffer_zone = list(keep_n = 50L, entry_n = 25L)
    ),
    error = function(e) {
      cat(sprintf("    ERROR: %s\n", e$message))
      NULL
    }
  )

  if (!is.null(sim)) {
    strat_name <- sprintf("G1_03_%s", v)
    perf <- summarise_perf(sim$strategy_xts, strat_name)
    results[[v]] <- data.table(
      variant = v,
      CAGR = perf$CAGR,
      Sharpe = perf$Sharpe,
      MDD = perf$MDD,
      TO = if ("TO" %in% names(perf)) perf$TO else NA_real_
    )
    cat(sprintf("    SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n",
                perf$Sharpe, perf$CAGR, perf$MDD))

    out_dir <- sprintf("04_Research/korea_research/G1_03_output/%s", v)
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(sim, file.path(out_dir, "sim_result.rds"))
    tryCatch(
      generate_charts(sim, output_dir = out_dir, strategy_name = strat_name),
      error = function(e) cat(sprintf("    Chart error: %s\n", e$message))
    )
  }
}

# ── 4. 비교 테이블 ───────────────────────────────────────────────
cat("\n[G1-03] Step 4: Comparison table\n")
comparison <- rbindlist(results)
print(comparison)

if (nrow(comparison) >= 2 && "none" %in% comparison$variant) {
  baseline_mdd <- comparison[variant == "none"]$MDD
  comparison[, MDD_improvement := baseline_mdd - MDD]
  cat("\n=== MDD Improvement vs Baseline ===\n")
  print(comparison[, .(variant, MDD, MDD_improvement)])
}

out_dir_main <- "04_Research/korea_research/G1_03_output"
dir.create(out_dir_main, recursive = TRUE, showWarnings = FALSE)
fwrite(comparison, file.path(out_dir_main, "comparison.csv"))
cat("\n[G1-03] Complete.\n")
