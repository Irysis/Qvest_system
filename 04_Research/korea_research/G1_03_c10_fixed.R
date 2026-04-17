cat("=== G1-03 C10 Fixed: High-Risk Exclusion (t-1 LIQ) ===\n")
cat("=== C10 준수: 유동성 필터 = 전월 AvgTV20 ===\n")
t0 <- Sys.time()

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/backtest_harness.R")
  source("02_Infrastructure/factor_db_connector.R")
})
library(data.table); library(arrow)

FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")

# ── 1. Shared data ───────────────────────────────────────────────
cat("[G1-03] Loading shared data...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res)
setkey(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y%m")]

# Monthly dates
monthly_last <- RAWDATA[, .(sig_date = max(Date)), by = YM]
setkey(monthly_last, YM)
month_ends <- sort(monthly_last$sig_date)
month_ends <- month_ends[month_ends >= as.Date("2006-01-01")]
ym_list <- format(month_ends, "%Y%m")

# Factor DB (C19 + D01만)
NEEDED <- c("C19_Composite_Earnings", "D01_IdioVol")
fdb_files <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$",
                        full.names = TRUE)
FDB_ALL <- rbindlist(lapply(fdb_files, function(f) {
  dt <- as.data.table(read_parquet(f))
  dt[, YM := gsub(".*factor_db_(\\d{6})\\.parquet", "\\1", f)]
  dt[Factor_Name %in% NEEDED]
}), fill = TRUE)
registry <- jsonlite::fromJSON(file.path(FACTOR_DB_DIR, "factor_registry.json"))
FDB_ALL <- align_factor_direction(FDB_ALL, registry)
setkey(FDB_ALL, YM, Ticker, Factor_Name)

# ── C10 준수 LIQ: 전월(t-1) AvgTV20 ─────────────────────────────
RAWDATA[, TV := Close * Vol]
LIQ_RAW <- RAWDATA[, .(AvgTV20 = mean(tail(TV, 20), na.rm = TRUE)),
                   by = .(Ticker, YM)]
ym_all <- sort(unique(LIQ_RAW$YM))
ym_shift <- data.table(YM_prev = ym_all[-length(ym_all)],
                       YM_use  = ym_all[-1])
LIQ_MONTHLY <- merge(LIQ_RAW, ym_shift, by.x = "YM", by.y = "YM_prev",
                     allow.cartesian = FALSE)
LIQ_MONTHLY <- LIQ_MONTHLY[, .(Ticker, YM = YM_use, AvgTV20)]
setkey(LIQ_MONTHLY, Ticker, YM)
rm(LIQ_RAW, ym_shift)
cat(sprintf("  LIQ: t-1 lag. %d rows\n", nrow(LIQ_MONTHLY)))

# MAX_Ret 사전 계산
MAX_RET <- RAWDATA[, .(MAX_Ret = max(Ret, na.rm = TRUE)), by = .(Ticker, YM)]
setkey(MAX_RET, Ticker, YM)

RAWDATA[, c("YM", "TV") := NULL]
gc(verbose = FALSE)

# ── 2. Helper ────────────────────────────────────────────────────
get_factors_wide <- function(ym) {
  fdt <- FDB_ALL[YM == ym & Factor_Name %in% NEEDED]
  if (nrow(fdt) == 0) return(NULL)
  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  liq <- LIQ_MONTHLY[YM == ym]  # C10: 전월 LIQ
  fdt_wide <- merge(fdt_wide, liq, by = "Ticker")
  fdt_wide[!is.na(AvgTV20) & AvgTV20 >= 2e8]
}

# ── 3. 4 variants ────────────────────────────────────────────────
build_factors <- function(exclude_type) {
  rbindlist(lapply(ym_list, function(ym) {
    fw <- get_factors_wide(ym)
    if (is.null(fw) || nrow(fw) < 30) return(NULL)

    # MAX_Ret merge (당월 것 — MAX는 가격 데이터이므로 sig_date 이전 21일 기준)
    mx <- MAX_RET[YM == ym]
    fw <- merge(fw, mx, by = "Ticker", all.x = TRUE)

    qualified <- copy(fw)
    if (exclude_type %in% c("idiovol", "both") &&
        "D01_IdioVol" %in% names(qualified) &&
        sum(!is.na(qualified$D01_IdioVol)) > 10) {
      cut_iv <- quantile(qualified$D01_IdioVol, 0.80, na.rm = TRUE)
      qualified <- qualified[is.na(D01_IdioVol) | D01_IdioVol < cut_iv]
    }
    if (exclude_type %in% c("max", "both") &&
        sum(!is.na(qualified$MAX_Ret)) > 10) {
      cut_mx <- quantile(qualified$MAX_Ret, 0.80, na.rm = TRUE)
      qualified <- qualified[is.na(MAX_Ret) | MAX_Ret < cut_mx]
    }

    if (nrow(qualified) < 20 ||
        !("C19_Composite_Earnings" %in% names(qualified))) return(NULL)

    qualified[, Score := frank(C19_Composite_Earnings, na.last = "keep",
                               ties.method = "average") /
                sum(!is.na(C19_Composite_Earnings))]
    sig_d <- monthly_last[YM == ym, sig_date]
    qualified[!is.na(Score), .(Date = sig_d, Ticker, Score)]
  }))
}

# ── 4. 실행 ──────────────────────────────────────────────────────
cat("[G1-03] Running 4 variants (C10 fixed)...\n")
results <- list()
for (v in c("none", "idiovol", "max", "both")) {
  cat(sprintf("  %s...", v))
  FACTORS_v <- build_factors(v)
  if (nrow(FACTORS_v) == 0) { cat(" SKIP\n"); next }
  setorder(FACTORS_v, Date, -Score)

  sim <- tryCatch(
    run_monthly_simulation(RAWDATA = RAWDATA, BM_DT = BM_DT,
                           FACTORS = FACTORS_v,
                           n_holdings = 30L, weight_method = "equal",
                           commission = 0.0015,
                           buffer_zone = list(keep_n = 50L, entry_n = 25L)),
    error = function(e) { cat(sprintf(" ERROR: %s\n", e$message)); NULL }
  )
  if (!is.null(sim)) {
    perf <- summarise_perf(sim$strategy_xts, paste0("G103_", v))
    results[[v]] <- data.table(variant = v, CAGR = perf$CAGR,
                                Sharpe = perf$Sharpe, MDD = perf$MDD)
    cat(sprintf(" SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n",
                perf$Sharpe, perf$CAGR, perf$MDD))
    out_dir <- sprintf("04_Research/korea_research/G1_03_c10_output/%s", v)
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(sim, file.path(out_dir, "sim_result.rds"))
    tryCatch(generate_charts(sim, output_dir = out_dir,
                             strategy_name = paste0("G103_c10_", v)),
             error = function(e) NULL)
  }
  rm(FACTORS_v, sim); gc(verbose = FALSE)
}

comp <- rbindlist(results)
out_main <- "04_Research/korea_research/G1_03_c10_output"
dir.create(out_main, recursive = TRUE, showWarnings = FALSE)
fwrite(comp, file.path(out_main, "comparison.csv"))
cat("\n[G1-03 C10] comparison:\n")
print(comp)
cat(sprintf("\n[G1-03 C10] Done in %.1f min\n",
            difftime(Sys.time(), t0, units = "mins")))
