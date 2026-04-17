cat("=== Phase 3 Optimized Batch Runner ===\n")
cat("=== G1-03 + G4-01 + INT-01 + G8-01b 순차 실행 (최적화) ===\n")
t0_total <- Sys.time()

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/backtest_harness.R")
  source("02_Infrastructure/factor_db_connector.R")
})
library(data.table); library(arrow)

FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")

# ══════════════════════════════════════════════════════════════════
# SHARED DATA — 1회 로드, 전 테스트 공유
# ══════════════════════════════════════════════════════════════════
cat("[OPT] Step 0: Shared data loading...\n")

# RAWDATA + BM
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res)
setkey(RAWDATA, Ticker, Date)
cat(sprintf("  RAWDATA: %s rows\n", format(nrow(RAWDATA), big.mark = ",")))

# Monthly dates
RAWDATA[, YM := format(Date, "%Y%m")]
monthly_last <- RAWDATA[, .(sig_date = max(Date)), by = YM]
setkey(monthly_last, YM)
month_ends <- sort(monthly_last$sig_date)
month_ends <- month_ends[month_ends >= as.Date("2006-01-01")]
ym_list <- format(month_ends, "%Y%m")

# Forward return 사전 계산
MONTHLY_RET <- RAWDATA[, .(Fwd_Ret = sum(Ret, na.rm = TRUE)), by = .(Ticker, YM)]
setkey(MONTHLY_RET, Ticker, YM)

# LIQ 필터 사전 계산 (C10 준수: 전월 기준. 당월 거래량 사용 금지)
RAWDATA[, TV := Close * Vol]
LIQ_RAW <- RAWDATA[, .(
  AvgTV20 = mean(tail(TV, 20), na.rm = TRUE)
), by = .(Ticker, YM)]
# 1개월 lag: sig_date(YM)에 대해 전월(YM_prev)의 AvgTV20 사용
ym_all <- sort(unique(LIQ_RAW$YM))
ym_shift <- data.table(YM_prev = ym_all[-length(ym_all)],
                       YM_use  = ym_all[-1])
LIQ_MONTHLY <- merge(LIQ_RAW, ym_shift, by.x = "YM", by.y = "YM_prev",
                     allow.cartesian = FALSE)
# YM_use = sig_date가 속한 월, AvgTV20 = 전월 값
LIQ_MONTHLY <- LIQ_MONTHLY[, .(Ticker, YM = YM_use, AvgTV20)]
setkey(LIQ_MONTHLY, Ticker, YM)
rm(LIQ_RAW, ym_shift)
cat(sprintf("[OPT] LIQ filter: t-1 month lag applied (C10 compliant). %d rows\n",
            nrow(LIQ_MONTHLY)))

# Cleanup temp cols
RAWDATA[, c("YM", "TV") := NULL]
gc(verbose = FALSE)

# Factor DB 프리로드 (필요 팩터만)
ALL_NEEDED <- c("C19_Composite_Earnings", "Q01_GPA", "Q08_Composite_Quality",
                "Q04_Piotroski_F", "Q24_Altman_Z", "D01_IdioVol")
cat("[OPT] Bulk-loading Factor DB (6 factors)...\n")
fdb_files <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
FDB_ALL <- rbindlist(lapply(fdb_files, function(f) {
  dt <- as.data.table(read_parquet(f))
  dt[, YM := gsub(".*factor_db_(\\d{6})\\.parquet", "\\1", f)]
  dt[Factor_Name %in% ALL_NEEDED]
}), fill = TRUE)
registry <- jsonlite::fromJSON(file.path(CACHE_DIR, "factor_db", "factor_registry.json"))
FDB_ALL <- align_factor_direction(FDB_ALL, registry)
setkey(FDB_ALL, YM, Ticker, Factor_Name)
cat(sprintf("  FDB: %.1fMB, %d months, %d factors\n",
            object.size(FDB_ALL) / 1e6, uniqueN(FDB_ALL$YM),
            uniqueN(FDB_ALL$Factor_Name)))

# MAX_Ret 사전 계산 (G1-03용)
cat("[OPT] Pre-computing MAX_Ret...\n")
setkey(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y%m")]
MAX_RET_MONTHLY <- RAWDATA[, .(
  MAX_Ret = max(Ret, na.rm = TRUE)
), by = .(Ticker, YM)]
setkey(MAX_RET_MONTHLY, Ticker, YM)
RAWDATA[, YM := NULL]

ram_mb <- as.numeric(system("free -m | awk '/Mem:/ {print $3}'", intern = TRUE))
cat(sprintf("[OPT] Shared data loaded. RAM: %dMB\n\n", ram_mb))

# Helper: FDB → wide format for a given YM
get_wide_factors <- function(ym, factors = ALL_NEEDED) {
  fdt <- FDB_ALL[YM == ym & Factor_Name %in% factors]
  if (nrow(fdt) == 0) return(NULL)
  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  liq <- LIQ_MONTHLY[YM == ym]
  fdt_wide <- merge(fdt_wide, liq, by = "Ticker")
  fdt_wide[!is.na(AvgTV20) & AvgTV20 >= 2e8]
}

# ══════════════════════════════════════════════════════════════════
# TEST 1: G1-03 High-Risk Exclusion (4 variants)
# ══════════════════════════════════════════════════════════════════
cat("━━━ G1-03: High-Risk Exclusion (4 variants) ━━━\n")
t0 <- Sys.time()

build_g103_factors <- function(exclude_type) {
  factor_list <- lapply(ym_list, function(ym) {
    fdt_wide <- get_wide_factors(ym, c("C19_Composite_Earnings", "D01_IdioVol"))
    if (is.null(fdt_wide) || nrow(fdt_wide) < 30) return(NULL)

    # MAX_Ret merge
    max_r <- MAX_RET_MONTHLY[YM == ym]
    fdt_wide <- merge(fdt_wide, max_r, by = "Ticker", all.x = TRUE)

    # Exclusion
    qualified <- copy(fdt_wide)
    if (exclude_type %in% c("idiovol", "both") &&
        "D01_IdioVol" %in% names(qualified) &&
        sum(!is.na(qualified$D01_IdioVol)) > 10) {
      cutoff <- quantile(qualified$D01_IdioVol, 0.80, na.rm = TRUE)
      qualified <- qualified[is.na(D01_IdioVol) | D01_IdioVol < cutoff]
    }
    if (exclude_type %in% c("max", "both") &&
        sum(!is.na(qualified$MAX_Ret)) > 10) {
      cutoff <- quantile(qualified$MAX_Ret, 0.80, na.rm = TRUE)
      qualified <- qualified[is.na(MAX_Ret) | MAX_Ret < cutoff]
    }

    if (nrow(qualified) < 20 ||
        !("C19_Composite_Earnings" %in% names(qualified))) return(NULL)

    qualified[, Score := frank(C19_Composite_Earnings, na.last = "keep",
                               ties.method = "average") /
                sum(!is.na(C19_Composite_Earnings))]
    sig_date <- monthly_last[YM == ym, sig_date]
    qualified[!is.na(Score), .(Date = sig_date, Ticker, Score)]
  })
  rbindlist(factor_list[!sapply(factor_list, is.null)])
}

g103_results <- list()
for (v in c("none", "idiovol", "max", "both")) {
  cat(sprintf("  [G1-03] %s...", v))
  FACTORS_v <- build_g103_factors(v)
  if (nrow(FACTORS_v) == 0) { cat(" SKIP\n"); next }
  setorder(FACTORS_v, Date, -Score)

  sim <- tryCatch(
    run_monthly_simulation(RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS_v,
                           n_holdings = 30L, weight_method = "equal",
                           commission = 0.0015,
                           buffer_zone = list(keep_n = 50L, entry_n = 25L)),
    error = function(e) { cat(sprintf(" ERROR: %s\n", e$message)); NULL }
  )

  if (!is.null(sim)) {
    perf <- summarise_perf(sim$strategy_xts, paste0("G103_", v))
    g103_results[[v]] <- data.table(variant = v, CAGR = perf$CAGR,
                                     Sharpe = perf$Sharpe, MDD = perf$MDD)
    cat(sprintf(" SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n",
                perf$Sharpe, perf$CAGR, perf$MDD))
    out_dir <- sprintf("04_Research/korea_research/G1_03_output/%s", v)
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(sim, file.path(out_dir, "sim_result.rds"))
    tryCatch(generate_charts(sim, output_dir = out_dir,
                             strategy_name = paste0("G103_", v)),
             error = function(e) NULL)
  }
  rm(FACTORS_v, sim); gc(verbose = FALSE)
}

comp <- rbindlist(g103_results)
if (nrow(comp) > 0) {
  out_main <- "04_Research/korea_research/G1_03_output"
  dir.create(out_main, recursive = TRUE, showWarnings = FALSE)
  fwrite(comp, file.path(out_main, "comparison.csv"))
  cat("[G1-03] comparison.csv saved\n")
  print(comp)
}
cat(sprintf("[G1-03] Done in %.1f min\n\n", difftime(Sys.time(), t0, units = "mins")))

# ══════════════════════════════════════════════════════════════════
# TEST 2: G4-01 Consensus TO Break-Even
# ══════════════════════════════════════════════════════════════════
cat("━━━ G4-01: Consensus Turnover Break-Even ━━━\n")
t0 <- Sys.time()

# C19 FACTORS 1회 생성
cat("  Building C19 FACTORS...\n")
C19_FACTORS <- rbindlist(lapply(ym_list, function(ym) {
  fdt_wide <- get_wide_factors(ym, "C19_Composite_Earnings")
  if (is.null(fdt_wide) || nrow(fdt_wide) < 30) return(NULL)
  fdt_wide[, Score := frank(C19_Composite_Earnings, na.last = "keep",
                             ties.method = "average") /
              sum(!is.na(C19_Composite_Earnings))]
  sig_date <- monthly_last[YM == ym, sig_date]
  fdt_wide[!is.na(Score), .(Date = sig_date, Ticker, Score)]
}))
setorder(C19_FACTORS, Date, -Score)

g401_results <- list()
for (bps in c(5, 10, 15, 20, 30, 50)) {
  cat(sprintf("  [G4-01] commission=%dbps...", bps))
  sim <- tryCatch(
    run_monthly_simulation(RAWDATA = RAWDATA, BM_DT = BM_DT,
                           FACTORS = C19_FACTORS,
                           n_holdings = 30L, weight_method = "equal",
                           commission = bps / 10000,
                           buffer_zone = list(keep_n = 50L, entry_n = 25L)),
    error = function(e) { cat(sprintf(" ERROR: %s\n", e$message)); NULL }
  )
  if (!is.null(sim)) {
    perf <- summarise_perf(sim$strategy_xts, sprintf("C19_%dbps", bps))
    g401_results[[as.character(bps)]] <- data.table(
      commission_bps = bps, CAGR = perf$CAGR,
      Sharpe = perf$Sharpe, MDD = perf$MDD)
    cat(sprintf(" SR=%.3f CAGR=%.2f%%\n", perf$Sharpe, perf$CAGR))
  }
  rm(sim); gc(verbose = FALSE)
}

g401_comp <- rbindlist(g401_results)
if (nrow(g401_comp) > 0) {
  out_dir <- "04_Research/korea_research/G4_01_output"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  fwrite(g401_comp, file.path(out_dir, "to_breakeven.csv"))
  cat("[G4-01] to_breakeven.csv saved\n")
  print(g401_comp)
}
rm(C19_FACTORS); gc(verbose = FALSE)
cat(sprintf("[G4-01] Done in %.1f min\n\n", difftime(Sys.time(), t0, units = "mins")))

# ══════════════════════════════════════════════════════════════════
# TEST 3: INT-01 Quality-Gated Low-Risk
# ══════════════════════════════════════════════════════════════════
cat("━━━ INT-01: Quality-Gated Low-Risk ━━━\n")
t0 <- Sys.time()

int01_variants <- list(
  "D01_raw"    = list(gate = FALSE),
  "D01_Qgate"  = list(gate = TRUE)
)

int01_results <- list()
for (vname in names(int01_variants)) {
  use_gate <- int01_variants[[vname]]$gate
  cat(sprintf("  [INT-01] %s...", vname))

  FACTORS_v <- rbindlist(lapply(ym_list, function(ym) {
    fdt_wide <- get_wide_factors(ym, c("D01_IdioVol", "Q01_GPA", "Q08_Composite_Quality"))
    if (is.null(fdt_wide) || nrow(fdt_wide) < 30) return(NULL)

    # Low-risk: D01 하위 50% (Z_Score_Aligned에서 높은 값 = 낮은 IdioVol)
    if ("D01_IdioVol" %in% names(fdt_wide)) {
      d01_med <- median(fdt_wide$D01_IdioVol, na.rm = TRUE)
      qualified <- fdt_wide[!is.na(D01_IdioVol) & D01_IdioVol >= d01_med]
    } else return(NULL)

    # Quality gate
    if (use_gate && "Q01_GPA" %in% names(qualified)) {
      gpa_med <- median(qualified$Q01_GPA, na.rm = TRUE)
      qualified <- qualified[!is.na(Q01_GPA) & Q01_GPA >= gpa_med]
    }

    if (nrow(qualified) < 20) return(NULL)
    qualified[, Score := D01_IdioVol]
    sig_date <- monthly_last[YM == ym, sig_date]
    qualified[!is.na(Score), .(Date = sig_date, Ticker, Score)]
  }))

  if (nrow(FACTORS_v) == 0) { cat(" SKIP\n"); next }
  setorder(FACTORS_v, Date, -Score)

  sim <- tryCatch(
    run_monthly_simulation(RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS_v,
                           n_holdings = 30L, weight_method = "equal",
                           commission = 0.0015,
                           buffer_zone = list(keep_n = 50L, entry_n = 25L)),
    error = function(e) { cat(sprintf(" ERROR: %s\n", e$message)); NULL }
  )

  if (!is.null(sim)) {
    perf <- summarise_perf(sim$strategy_xts, vname)
    int01_results[[vname]] <- data.table(variant = vname, CAGR = perf$CAGR,
                                          Sharpe = perf$Sharpe, MDD = perf$MDD)
    cat(sprintf(" SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n",
                perf$Sharpe, perf$CAGR, perf$MDD))
    out_dir <- sprintf("04_Research/korea_research/INT_01_output/%s", vname)
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(sim, file.path(out_dir, "sim_result.rds"))
    tryCatch(generate_charts(sim, output_dir = out_dir, strategy_name = vname),
             error = function(e) NULL)
  }
  rm(FACTORS_v, sim); gc(verbose = FALSE)
}

int01_comp <- rbindlist(int01_results)
if (nrow(int01_comp) > 0) {
  out_dir <- "04_Research/korea_research/INT_01_output"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  fwrite(int01_comp, file.path(out_dir, "comparison.csv"))
  cat("[INT-01] comparison.csv saved\n")
  print(int01_comp)
}
cat(sprintf("[INT-01] Done in %.1f min\n\n", difftime(Sys.time(), t0, units = "mins")))

# ══════════════════════════════════════════════════════════════════
# TEST 4: G8-01b Samsara Logic Backtest
# ══════════════════════════════════════════════════════════════════
cat("━━━ G8-01b: Samsara Protocol Logic ━━━\n")
t0 <- Sys.time()
library(TTR)
cat("  Computing Samsara factors on RAWDATA...\n")

setorder(RAWDATA, Ticker, Date)
wp <- 20L; wb <- 60L

# Beta
RAWDATA[, Beta_s := {
  if (.N >= wb) runCov(Ret, BM_Ret, n = wb) / (runVar(BM_Ret, n = wb) + 1e-8)
  else rep(NA_real_, .N)
}, by = Ticker]

# Residual
RAWDATA[, Residual := Ret - (Beta_s * BM_Ret)]

# Aleph
RAWDATA[, Aleph := {
  if (sum(!is.na(Residual)) >= wp && .N >= wp)
    abs(runSum(Residual, n = wp)) / (runSum(abs(Residual), n = wp) + 1e-6)
  else rep(NA_real_, .N)
}, by = Ticker]

# Volatility + Mean_Res
RAWDATA[, Vol_s := {
  if (sum(!is.na(Residual)) >= wp && .N >= wp) runSD(Residual, n = wp)
  else rep(NA_real_, .N)
}, by = Ticker]
RAWDATA[, Mean_Res := {
  if (sum(!is.na(Residual)) >= wp && .N >= wp) runMean(Residual, n = wp)
  else rep(NA_real_, .N)
}, by = Ticker]

# Psi, STP, Gravity, LHI
RAWDATA[, Mean_Close := {
  if (.N >= wp) runMean(Close, n = wp) else rep(NA_real_, .N)
}, by = Ticker]
RAWDATA[, SD_Close := {
  if (.N >= wp) runSD(Close, n = wp) else rep(NA_real_, .N)
}, by = Ticker]
RAWDATA[, Momentum := {
  if (.N >= wp) (Close / shift(Close, n = wp)) - 1 else rep(NA_real_, .N)
}, by = Ticker]

RAWDATA[, Psi := (Residual - Mean_Res) / (Vol_s + 1e-6)]
RAWDATA[, STP := (Close - (Mean_Close + 2 * SD_Close)) / Close]
RAWDATA[, Gravity := abs(Momentum) * Aleph]
RAWDATA[, LHI := {
  if (sum(!is.na(Vol_s)) >= wp && .N >= wp) runSD(Vol_s, n = wp)
  else rep(NA_real_, .N)
}, by = Ticker]

# Cleanup intermediates
for (col in c("Beta_s", "Residual", "Vol_s", "Mean_Res",
              "Mean_Close", "SD_Close", "Momentum"))
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]

cat("  Samsara factors computed.\n")

# Build Samsara FACTORS
RAWDATA[, YM := format(Date, "%Y%m")]
RAWDATA[, TV2 := Close * Vol]
RAWDATA[, AvgTV20_s := shift(frollmean(TV2, n = 20L, align = "right"),
                              n = 1L, type = "lag"), by = Ticker]

SAMSARA_FACTORS <- rbindlist(lapply(ym_list, function(ym) {
  sig_d <- monthly_last[YM == ym, sig_date]
  snap <- RAWDATA[Date == sig_d & !is.na(Psi) & !is.na(Aleph) &
                    !is.na(STP) & !is.na(Gravity) & !is.na(LHI)]
  snap <- snap[!is.na(AvgTV20_s) & AvgTV20_s >= 2e8]
  if (nrow(snap) < 20) return(NULL)

  avg_aleph <- mean(snap$Aleph, na.rm = TRUE)
  avg_gravity <- mean(snap$Gravity, na.rm = TRUE)

  # Buddha: cash
  if (avg_aleph < 0.15) return(NULL)
  # Event Horizon: skip (이전 달 유지 — 단순화: NULL 반환 → buffer_zone이 처리)

  # STP > 0 + Gravity Top 20
  candidates <- snap[STP > 0]
  if (nrow(candidates) < 5) { setorder(snap, -STP); candidates <- head(snap, 20) }
  setorder(candidates, -Gravity)
  top <- head(candidates, 20L)

  # 1/LHI 역카오스 가중 → Score로 변환
  top[, Score := (1 / (LHI + 1e-6))]
  top[, Score := Score / sum(Score)]  # 정규화

  top[, .(Date = sig_d, Ticker, Score)]
}))

# Samsara 임시 컬럼 정리
for (col in c("YM", "TV2", "AvgTV20_s", "Psi", "STP", "Gravity", "Aleph", "LHI"))
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
gc(verbose = FALSE)

if (nrow(SAMSARA_FACTORS) > 0) {
  setorder(SAMSARA_FACTORS, Date, -Score)
  cat(sprintf("  SAMSARA FACTORS: %d rows, %d months\n",
              nrow(SAMSARA_FACTORS), uniqueN(SAMSARA_FACTORS$Date)))

  sim <- tryCatch(
    run_monthly_simulation(RAWDATA = RAWDATA, BM_DT = BM_DT,
                           FACTORS = SAMSARA_FACTORS,
                           n_holdings = 20L, weight_method = "score",
                           commission = 0.0015,
                           buffer_zone = list(keep_n = 30L, entry_n = 15L)),
    error = function(e) { cat(sprintf("  ERROR: %s\n", e$message)); NULL }
  )

  if (!is.null(sim)) {
    out_dir <- "04_Research/korea_research/G8_01b_output"
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    perf <- summarise_perf(sim$strategy_xts, "Samsara_Logic")
    cat(sprintf("  SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n",
                perf$Sharpe, perf$CAGR, perf$MDD))
    generate_charts(sim, output_dir = out_dir, strategy_name = "Samsara_Logic")
    fwrite(data.table(t(unlist(perf))), file.path(out_dir, "performance.csv"))
    saveRDS(sim, file.path(out_dir, "sim_result.rds"))

    source("02_Infrastructure/hurdle_gate.R")
    hurdle <- run_hurdle_gate(sim_result = sim, FACTORS = SAMSARA_FACTORS,
                              strategy_name = "G8_01b_Samsara_Logic",
                              output_dir = out_dir)
    jsonlite::write_json(hurdle, file.path(out_dir, "hurdle_result.json"),
                         auto_unbox = TRUE, pretty = TRUE)
    cat(sprintf("  Grade: %s\n", hurdle$grade))
  }
} else {
  cat("  SAMSARA FACTORS empty — all months Buddha filtered\n")
}
rm(SAMSARA_FACTORS); gc(verbose = FALSE)
cat(sprintf("[G8-01b] Done in %.1f min\n\n", difftime(Sys.time(), t0, units = "mins")))

# ══════════════════════════════════════════════════════════════════
cat(sprintf("━━━ Phase 3 Batch Complete: %.1f min total ━━━\n",
            difftime(Sys.time(), t0_total, units = "mins")))
