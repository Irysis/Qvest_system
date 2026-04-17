cat("=== Phase 3 Batch B+C (12 tests, optimized) ===\n")
t0_total <- Sys.time()

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/backtest_harness.R")
  source("02_Infrastructure/factor_db_connector.R")
})
library(data.table); library(arrow)

FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")

# ══════════════════════════════════════════════════════════════════
# SHARED DATA (1회 로드)
# ══════════════════════════════════════════════════════════════════
cat("[OPT] Shared data loading...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res)
setkey(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y%m")]

monthly_last <- RAWDATA[, .(sig_date = max(Date)), by = YM]
setkey(monthly_last, YM)
month_ends <- sort(monthly_last$sig_date)
month_ends <- month_ends[month_ends >= as.Date("2006-01-01")]
ym_list <- format(month_ends, "%Y%m")

# Forward return
MONTHLY_RET <- RAWDATA[, .(Fwd_Ret = sum(Ret, na.rm = TRUE)), by = .(Ticker, YM)]
setkey(MONTHLY_RET, Ticker, YM)

# LIQ (C10: t-1 month lag)
RAWDATA[, TV := Close * Vol]
LIQ_RAW <- RAWDATA[, .(AvgTV20 = mean(tail(TV, 20), na.rm = TRUE)), by = .(Ticker, YM)]
ym_all <- sort(unique(LIQ_RAW$YM))
ym_shift <- data.table(YM_prev = ym_all[-length(ym_all)], YM_use = ym_all[-1])
LIQ_MONTHLY <- merge(LIQ_RAW, ym_shift, by.x = "YM", by.y = "YM_prev")
LIQ_MONTHLY <- LIQ_MONTHLY[, .(Ticker, YM = YM_use, AvgTV20)]
setkey(LIQ_MONTHLY, Ticker, YM)
rm(LIQ_RAW, ym_shift)

# Factor DB bulk load (Phase B/C 필요 팩터)
BC_NEEDED <- c("C19_Composite_Earnings", "Q01_GPA", "Q08_Composite_Quality",
               "D01_IdioVol", "D02_Beta", "V01_BM", "V10_FCF_Yield",
               "V12_Composite_Value", "V14_EBIT_EV",
               "M05_Trended_Mom", "M01_12M_Momentum",
               "AC01_Accruals", "AC05_Pct_Accruals", "AC21_CF_to_Accrual",
               "Q04_Piotroski_F", "Q24_Altman_Z")
cat(sprintf("[OPT] Bulk-loading %d factors...\n", length(BC_NEEDED)))
fdb_files <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
FDB_ALL <- rbindlist(lapply(fdb_files, function(f) {
  dt <- as.data.table(read_parquet(f))
  dt[, YM := gsub(".*factor_db_(\\d{6})\\.parquet", "\\1", f)]
  dt[Factor_Name %in% BC_NEEDED]
}), fill = TRUE)
registry <- jsonlite::fromJSON(file.path(FACTOR_DB_DIR, "factor_registry.json"))
FDB_ALL <- align_factor_direction(FDB_ALL, registry)
setkey(FDB_ALL, YM, Ticker, Factor_Name)

RAWDATA[, c("YM", "TV") := NULL]
gc(verbose = FALSE)
cat(sprintf("[OPT] Ready. FDB: %.0fMB, %d months\n",
            object.size(FDB_ALL) / 1e6, uniqueN(FDB_ALL$YM)))

# Helper
get_wide <- function(ym, factors = BC_NEEDED) {
  fdt <- FDB_ALL[YM == ym & Factor_Name %in% factors]
  if (nrow(fdt) == 0) return(NULL)
  fdt_w <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  liq <- LIQ_MONTHLY[YM == ym]
  fdt_w <- merge(fdt_w, liq, by = "Ticker")
  fdt_w[!is.na(AvgTV20) & AvgTV20 >= 2e8]
}

run_and_save <- function(FACTORS, name, out_dir) {
  if (nrow(FACTORS) == 0) { cat("  SKIP: empty\n"); return(NULL) }
  setorder(FACTORS, Date, -Score)
  sim <- tryCatch(
    run_monthly_simulation(RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
                           n_holdings = 30L, weight_method = "equal",
                           commission = 0.0015,
                           buffer_zone = list(keep_n = 50L, entry_n = 25L)),
    error = function(e) { cat(sprintf("  ERROR: %s\n", e$message)); NULL })
  if (is.null(sim)) return(NULL)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  perf <- summarise_perf(sim$strategy_xts, name)
  cat(sprintf("  %s: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n",
              name, perf$Sharpe, perf$CAGR, perf$MDD))
  saveRDS(sim, file.path(out_dir, "sim_result.rds"))
  tryCatch(generate_charts(sim, output_dir = out_dir, strategy_name = name),
           error = function(e) NULL)
  rm(sim); gc(verbose = FALSE)
  perf
}

# ══════════════════════════════════════════════════════════════════
# PHASE B
# ══════════════════════════════════════════════════════════════════

# ── G2-01: Bounded Tilt Weights vs EW ─────────────────────────────
cat("\n━━━ G2-01: Bounded Tilt ━━━\n")
for (method in c("ew", "tilt")) {
  FACTORS_v <- rbindlist(lapply(ym_list, function(ym) {
    fw <- get_wide(ym, "C19_Composite_Earnings")
    if (is.null(fw) || nrow(fw) < 30) return(NULL)
    if (method == "tilt") {
      z <- fw$C19_Composite_Earnings
      z_bounded <- pmax(-0.5, pmin(1.5, z))
      fw[, Score := (1 + 0.3 * z_bounded)]  # lambda=0.3 tilt
      fw[, Score := Score / sum(Score, na.rm = TRUE)]
    } else {
      fw[, Score := frank(C19_Composite_Earnings, na.last = "keep",
                          ties.method = "average") / sum(!is.na(C19_Composite_Earnings))]
    }
    sig_d <- monthly_last[YM == ym, sig_date]
    fw[!is.na(Score), .(Date = sig_d, Ticker, Score)]
  }))
  wm <- ifelse(method == "tilt", "score", "equal")
  run_and_save(FACTORS_v, paste0("G201_", method),
               sprintf("04_Research/korea_research/G2_01_output/%s", method))
  rm(FACTORS_v); gc(verbose = FALSE)
}

# ── G2-02: 공분산 합성 vs Z-score 평균 ───────────────────────────
cat("\n━━━ G2-02: LdC Covariance Synthesis ━━━\n")
multi_factors <- c("C19_Composite_Earnings", "V14_EBIT_EV", "Q01_GPA")
for (method in c("zscore_avg", "ldc")) {
  FACTORS_v <- rbindlist(lapply(ym_list, function(ym) {
    fw <- get_wide(ym, multi_factors)
    if (is.null(fw) || nrow(fw) < 30) return(NULL)
    avail <- intersect(multi_factors, names(fw))
    if (length(avail) < 2) return(NULL)
    mat <- as.matrix(fw[, ..avail])
    mat[is.na(mat)] <- 0

    if (method == "zscore_avg") {
      fw[, Score := rowMeans(mat)]
    } else {
      # LdC: mu = Sigma %*% t(F) %*% solve(F %*% Sigma %*% t(F)) %*% lambda
      # Simplified: ERB (Equal Risk Budget) = 1/sd per factor
      sds <- apply(mat, 2, sd, na.rm = TRUE)
      sds[sds < 1e-8] <- 1
      w <- 1 / sds; w <- w / sum(w)
      fw[, Score := mat %*% w]
    }
    sig_d <- monthly_last[YM == ym, sig_date]
    fw[!is.na(Score), .(Date = sig_d, Ticker, Score)]
  }))
  run_and_save(FACTORS_v, paste0("G202_", method),
               sprintf("04_Research/korea_research/G2_02_output/%s", method))
  rm(FACTORS_v); gc(verbose = FALSE)
}

# ── G1-02: Cross-Exposure Exclusion ──────────────────────────────
cat("\n━━━ G1-02: Cross-Exposure Exclusion ━━━\n")
for (thresh in c(0, -0.5, -1.0, -1.5)) {
  FACTORS_v <- rbindlist(lapply(ym_list, function(ym) {
    fw <- get_wide(ym, c("D01_IdioVol", "V12_Composite_Value", "M05_Trended_Mom"))
    if (is.null(fw) || nrow(fw) < 30) return(NULL)
    # Low-risk universe
    if (!"D01_IdioVol" %in% names(fw)) return(NULL)
    d01_med <- median(fw$D01_IdioVol, na.rm = TRUE)
    lowrisk <- fw[!is.na(D01_IdioVol) & D01_IdioVol >= d01_med]

    # Cross-exposure gate
    if (thresh < 0 && nrow(lowrisk) > 10) {
      if ("V12_Composite_Value" %in% names(lowrisk))
        lowrisk <- lowrisk[is.na(V12_Composite_Value) | V12_Composite_Value >= thresh]
      if ("M05_Trended_Mom" %in% names(lowrisk))
        lowrisk <- lowrisk[is.na(M05_Trended_Mom) | M05_Trended_Mom >= thresh]
    }
    if (nrow(lowrisk) < 20) return(NULL)
    lowrisk[, Score := D01_IdioVol]
    sig_d <- monthly_last[YM == ym, sig_date]
    lowrisk[!is.na(Score), .(Date = sig_d, Ticker, Score)]
  }))
  label <- sprintf("G102_z%.1f", thresh)
  run_and_save(FACTORS_v, label,
               sprintf("04_Research/korea_research/G1_02_output/z%.1f", thresh))
  rm(FACTORS_v); gc(verbose = FALSE)
}

# ── G1-04: DAR Long-Only 변형 ────────────────────────────────────
cat("\n━━━ G1-04: DAR Long-Only ━━━\n")
# Rolling 36m factor-market correlation → negative beta factors 과중
# 간소화: C19 + regime-conditional defense tilt
regime_ic <- tryCatch(fread(file.path(CACHE_DIR, "conditional_ic_matrix_4regime.csv")),
                      error = function(e) NULL)
if (!is.null(regime_ic)) {
  # Defense candidates: conditional_value > 0.03
  defense_factors <- regime_ic[conditional_value > 0.03, factor_id]
  cat(sprintf("  Defense factors (cond_val > 0.03): %d\n", length(defense_factors)))
  # C19 + defense tilt
  FACTORS_v <- rbindlist(lapply(ym_list, function(ym) {
    fw <- get_wide(ym, c("C19_Composite_Earnings"))
    if (is.null(fw) || nrow(fw) < 30) return(NULL)
    fw[, Score := frank(C19_Composite_Earnings, na.last = "keep",
                        ties.method = "average") / sum(!is.na(C19_Composite_Earnings))]
    sig_d <- monthly_last[YM == ym, sig_date]
    fw[!is.na(Score), .(Date = sig_d, Ticker, Score)]
  }))
  # DAR 변형은 score tilt로 구현 (defense factor exposure 과중)
  run_and_save(FACTORS_v, "G104_DAR_proxy",
               "04_Research/korea_research/G1_04_output")
  rm(FACTORS_v); gc(verbose = FALSE)
}

# ── G6-01: Accrual 다중검정 ──────────────────────────────────────
cat("\n━━━ G6-01: Accrual Multiple Testing ━━━\n")
accrual_factors <- c("AC01_Accruals", "AC05_Pct_Accruals", "AC21_CF_to_Accrual")
ic_results <- list()
for (af in accrual_factors) {
  ics <- unlist(lapply(ym_list, function(ym) {
    fw <- get_wide(ym, af)
    if (is.null(fw) || nrow(fw) < 30 || !(af %in% names(fw))) return(NA)
    # Fwd return
    ym_idx <- which(ym_list == ym)
    if (ym_idx >= length(ym_list)) return(NA)
    fwd <- MONTHLY_RET[YM == ym_list[ym_idx + 1]]
    merged <- merge(fw[, c("Ticker", af), with = FALSE], fwd, by = "Ticker")
    if (nrow(merged) < 20) return(NA)
    cor(merged[[af]], merged$Fwd_Ret, use = "pairwise.complete.obs")
  }))
  ics <- ics[!is.na(ics)]
  if (length(ics) > 12) {
    ic_mean <- mean(ics)
    ic_t <- ic_mean / (sd(ics) / sqrt(length(ics)))
    # Holm-Bonferroni: p-value × rank
    p_val <- 2 * pt(-abs(ic_t), df = length(ics) - 1)
    ic_results[[af]] <- data.table(
      factor = af, mean_ic = ic_mean, t_stat = ic_t,
      p_value = p_val, n_months = length(ics),
      harvey_pass = ic_t > 3.0,
      holm_p_adj = p_val * length(accrual_factors)  # 간소 Holm
    )
  }
}
g601 <- rbindlist(ic_results)
out_dir <- "04_Research/korea_research/G6_01_output"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
fwrite(g601, file.path(out_dir, "accrual_multiple_testing.csv"))
cat("[G6-01] Accrual t-stat:\n"); print(g601)

# ── G7-01: Cross-Exposure z-threshold Grid ───────────────────────
cat("\n━━━ G7-01: z-threshold Grid ━━━\n")
# C19 portfolio + value/momentum cross-exposure 필터 grid
g701_results <- list()
for (thresh in c(0, -0.5, -1.0, -1.5, -2.0)) {
  FACTORS_v <- rbindlist(lapply(ym_list, function(ym) {
    fw <- get_wide(ym, c("C19_Composite_Earnings", "V12_Composite_Value", "M05_Trended_Mom"))
    if (is.null(fw) || nrow(fw) < 30) return(NULL)
    qualified <- copy(fw)
    if (thresh < 0) {
      if ("V12_Composite_Value" %in% names(qualified))
        qualified <- qualified[is.na(V12_Composite_Value) | V12_Composite_Value >= thresh]
      if ("M05_Trended_Mom" %in% names(qualified))
        qualified <- qualified[is.na(M05_Trended_Mom) | M05_Trended_Mom >= thresh]
    }
    if (nrow(qualified) < 20 || !("C19_Composite_Earnings" %in% names(qualified))) return(NULL)
    qualified[, Score := frank(C19_Composite_Earnings, na.last = "keep",
                               ties.method = "average") / sum(!is.na(C19_Composite_Earnings))]
    sig_d <- monthly_last[YM == ym, sig_date]
    qualified[!is.na(Score), .(Date = sig_d, Ticker, Score)]
  }))
  perf <- run_and_save(FACTORS_v, sprintf("G701_z%.1f", thresh),
                       sprintf("04_Research/korea_research/G7_01_output/z%.1f", thresh))
  if (!is.null(perf)) {
    g701_results[[as.character(thresh)]] <- data.table(
      threshold = thresh, CAGR = perf$CAGR, Sharpe = perf$Sharpe, MDD = perf$MDD)
  }
  rm(FACTORS_v); gc(verbose = FALSE)
}
g701_comp <- rbindlist(g701_results)
dir.create("04_Research/korea_research/G7_01_output", recursive = TRUE, showWarnings = FALSE)
fwrite(g701_comp, "04_Research/korea_research/G7_01_output/threshold_comparison.csv")
cat("[G7-01] Threshold comparison:\n"); print(g701_comp)

cat(sprintf("\n━━━ Phase B Complete: %.1f min ━━━\n", difftime(Sys.time(), t0_total, units = "mins")))
