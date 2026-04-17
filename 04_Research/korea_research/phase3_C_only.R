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
# PHASE C
# ══════════════════════════════════════════════════════════════════

# ── G3-02: SJM 프로토타입 (간소) ─────────────────────────────────
cat("\n━━━ G3-02: SJM Prototype ━━━\n")
# 간소화: 팩터 IC의 expanding percentile로 국면 분류 후 조건부 가중
# 5개 대표 팩터의 rolling 12m IC → high/low IC 국면별 가중
cat("  (SJM full implementation은 별도. 여기서는 IC momentum proxy)\n")
FACTORS_v <- rbindlist(lapply(ym_list, function(ym) {
  fw <- get_wide(ym, c("C19_Composite_Earnings", "V14_EBIT_EV", "Q01_GPA",
                        "M05_Trended_Mom", "D01_IdioVol"))
  if (is.null(fw) || nrow(fw) < 30) return(NULL)
  avail <- intersect(c("C19_Composite_Earnings", "V14_EBIT_EV", "Q01_GPA",
                        "M05_Trended_Mom", "D01_IdioVol"), names(fw))
  if (length(avail) < 3) return(NULL)
  # Equal weight (SJM 국면 가중은 Phase C 확장)
  mat <- as.matrix(fw[, ..avail])
  mat[is.na(mat)] <- 0
  fw[, Score := rowMeans(mat)]
  sig_d <- monthly_last[YM == ym, sig_date]
  fw[!is.na(Score), .(Date = sig_d, Ticker, Score)]
}))
run_and_save(FACTORS_v, "G302_SJM_proxy",
             "04_Research/korea_research/G3_02_output")
rm(FACTORS_v); gc(verbose = FALSE)

# ── G8-02: Alpha191 A046 (Mean Reversion Ratio) ──────────────────
cat("\n━━━ G8-02: Alpha191 A046 (MRR) ━━━\n")
# A046 = (Close - delay(Close, 10)) / delay(Close, 10)의 20d 합 역수
# 논문: mean reversion intensity의 역수 = t=3.68, Harvey 통과
RAWDATA[, YM := format(Date, "%Y%m")]
setorder(RAWDATA, Ticker, Date)
RAWDATA[, Close_lag10 := shift(Close, 10L), by = Ticker]
RAWDATA[, MRR_daily := (Close - Close_lag10) / (Close_lag10 + 1e-8)]
RAWDATA[, MRR_20d := frollsum(MRR_daily, n = 20L, align = "right"), by = Ticker]
# 월말 시점의 MRR을 팩터로 사용 (t-1: shift 1)
RAWDATA[, MRR_lag := shift(MRR_20d, 1L), by = Ticker]

A046_FACTORS <- rbindlist(lapply(ym_list, function(ym) {
  sig_d <- monthly_last[YM == ym, sig_date]
  snap <- RAWDATA[Date == sig_d & !is.na(MRR_lag)]
  liq <- LIQ_MONTHLY[YM == ym]
  snap <- merge(snap, liq, by = "Ticker")
  snap <- snap[!is.na(AvgTV20) & AvgTV20 >= 2e8]
  if (nrow(snap) < 30) return(NULL)
  # 역수: MRR이 음수(과매도) = 높은 점수
  snap[, Score := frank(-MRR_lag, na.last = "keep", ties.method = "average") /
         sum(!is.na(MRR_lag))]
  snap[!is.na(Score), .(Date = sig_d, Ticker, Score)]
}))
RAWDATA[, c("YM", "Close_lag10", "MRR_daily", "MRR_20d", "MRR_lag") := NULL]
gc(verbose = FALSE)

run_and_save(A046_FACTORS, "G802_A046_MRR",
             "04_Research/korea_research/G8_02_output")
rm(A046_FACTORS); gc(verbose = FALSE)

# ── G9-02: Macro Conditional Factor Return ────────────────────────
cat("\n━━━ G9-02: Macro Conditional Returns ━━━\n")
# FRED 데이터 기반 매크로 국면 분류
# regime_v7에서 이미 분류됨 → G3-01 결과 재사용
regime_4r <- tryCatch(fread(file.path(CACHE_DIR, "conditional_ic_matrix_4regime.csv")),
                      error = function(e) NULL)
if (!is.null(regime_4r)) {
  out_dir <- "04_Research/korea_research/G9_02_output"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  # Top 10 per regime
  for (reg in c("CALM", "NORMAL", "CAUTION", "CRISIS")) {
    col <- paste0("mean_ic_", reg)
    if (col %in% names(regime_4r)) {
      top10 <- head(regime_4r[order(-get(col))], 10)
      cat(sprintf("  %s top 5: %s\n", reg,
                  paste(head(top10$factor_id, 5), collapse = ", ")))
    }
  }
  fwrite(regime_4r, file.path(out_dir, "regime_factor_ranking.csv"))
  cat("[G9-02] Saved regime_factor_ranking.csv\n")
}

# ── INT-02: Regime-Conditional Quality Defense ────────────────────
cat("\n━━━ INT-02: Regime Quality Defense ━━━\n")
# 위기 국면에서만 Quality 과중, 정상 시 C19 기본
regime_dt <- tryCatch({
  as.data.table(read_parquet(file.path(CACHE_DIR, "regime_daily_v2.parquet")))
}, error = function(e) NULL)

if (!is.null(regime_dt)) {
  regime_dt[, Date := as.Date(Date)]
  regime_dt[, regime_q := cut(MRS, breaks = quantile(MRS, c(0, .25, .5, .75, 1), na.rm = TRUE),
                               labels = c("CALM", "NORMAL", "CAUTION", "CRISIS"),
                               include.lowest = TRUE)]

  FACTORS_v <- rbindlist(lapply(ym_list, function(ym) {
    fw <- get_wide(ym, c("C19_Composite_Earnings", "Q08_Composite_Quality", "Q01_GPA"))
    if (is.null(fw) || nrow(fw) < 30) return(NULL)

    sig_d <- monthly_last[YM == ym, sig_date]
    reg_row <- regime_dt[Date <= sig_d][.N]
    regime <- if (nrow(reg_row) > 0) as.character(reg_row$regime_q) else "NORMAL"

    if (regime %in% c("CRISIS", "CAUTION")) {
      # Quality 과중: C19 50% + Q01 30% + Q08 20%
      s1 <- fw$C19_Composite_Earnings; s1[is.na(s1)] <- 0
      s2 <- if ("Q01_GPA" %in% names(fw)) fw$Q01_GPA else 0; s2[is.na(s2)] <- 0
      s3 <- if ("Q08_Composite_Quality" %in% names(fw)) fw$Q08_Composite_Quality else 0; s3[is.na(s3)] <- 0
      fw[, Score := 0.5 * s1 + 0.3 * s2 + 0.2 * s3]
    } else {
      fw[, Score := C19_Composite_Earnings]
    }
    fw[!is.na(Score), .(Date = sig_d, Ticker, Score)]
  }))
  run_and_save(FACTORS_v, "INT02_regime_quality",
               "04_Research/korea_research/INT_02_output")
  rm(FACTORS_v); gc(verbose = FALSE)
}

# ── INT-04: C19 + Momentum 직교성 ────────────────────────────────
cat("\n━━━ INT-04: C19 + Momentum ━━━\n")
FACTORS_v <- rbindlist(lapply(ym_list, function(ym) {
  fw <- get_wide(ym, c("C19_Composite_Earnings", "M05_Trended_Mom"))
  if (is.null(fw) || nrow(fw) < 30) return(NULL)
  s1 <- fw$C19_Composite_Earnings; s1[is.na(s1)] <- 0
  s2 <- if ("M05_Trended_Mom" %in% names(fw)) fw$M05_Trended_Mom else 0; s2[is.na(s2)] <- 0
  fw[, Score := 0.7 * s1 + 0.3 * s2]
  sig_d <- monthly_last[YM == ym, sig_date]
  fw[!is.na(Score), .(Date = sig_d, Ticker, Score)]
}))
run_and_save(FACTORS_v, "INT04_c19_mom",
             "04_Research/korea_research/INT_04_output")
rm(FACTORS_v); gc(verbose = FALSE)

# ── INT-05: Bounded Tilt + Defense Regime ─────────────────────────
cat("\n━━━ INT-05: Bounded Tilt + Defense ━━━\n")
if (!is.null(regime_dt)) {
  FACTORS_v <- rbindlist(lapply(ym_list, function(ym) {
    fw <- get_wide(ym, c("C19_Composite_Earnings", "Q01_GPA"))
    if (is.null(fw) || nrow(fw) < 30) return(NULL)

    sig_d <- monthly_last[YM == ym, sig_date]
    reg_row <- regime_dt[Date <= sig_d][.N]
    regime <- if (nrow(reg_row) > 0) as.character(reg_row$regime_q) else "NORMAL"

    z <- fw$C19_Composite_Earnings; z[is.na(z)] <- 0
    z_bounded <- pmax(-0.5, pmin(1.5, z))

    # Regime-dependent lambda
    lambda <- switch(regime, CRISIS = 0.1, CAUTION = 0.2, NORMAL = 0.3, CALM = 0.4, 0.3)
    fw[, Score := 1 + lambda * z_bounded]
    fw[, Score := Score / sum(Score, na.rm = TRUE)]
    fw[!is.na(Score), .(Date = sig_d, Ticker, Score)]
  }))
  run_and_save(FACTORS_v, "INT05_tilt_regime",
               "04_Research/korea_research/INT_05_output")
  rm(FACTORS_v); gc(verbose = FALSE)
}

# ══════════════════════════════════════════════════════════════════
cat(sprintf("\n━━━ Phase C Complete: %.1f min ━━━\n", difftime(Sys.time(), t0_total, units = "mins")))
