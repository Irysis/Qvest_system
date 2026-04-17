cat("=== STR_1638: Enhanced Quality Defense (Cross-Exposure Filter) ===\n")
## 핵심아이디어: Q01_GPA 단독 + Value Trap 제거(V01_BM 하위 20%) + Momentum Crash 방어(M01 하위 20%)
## 가치함정 + 모멘텀 하락주 동시 제거 → 수익성이 높으면서 건전한 주식만 보유.
## S1 순수 팩터 신호. DD/VT/Regime overlay 없음.
## Fama-French Quality (2015) + Daniel-Titman (1997) momentum crash 방어.

set.seed(20240408)
t0 <- Sys.time()

# ═══════════════════════════════════════════════════════════════════
# 0. Environment
# ═══════════════════════════════════════════════════════════════════
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR  <- file.path(PROJECT_ROOT, ".cache")
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR    <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(xts)
  library(zoo)
  library(PerformanceAnalytics)
  library(ggplot2)
  library(scales)
  library(jsonlite)
})

options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_ID   <- "STR_1638"
STRATEGY_FAM  <- "quality_defense"
N_HOLD        <- 30L
LIQ_THRESHOLD <- 2e8
COMMISSION    <- 0.0015   # 15bps
BM_EXCL_PCTL  <- 0.20     # V01_BM 하위 20% 제외 (value trap)
MOM_EXCL_PCTL <- 0.20     # M01 하위 20% 제외 (momentum crash)

cat(sprintf("[setup] PROJECT_ROOT: %s\n", PROJECT_ROOT))
cat(sprintf("[setup] OUT_DIR: %s\n", OUT_DIR))

# ═══════════════════════════════════════════════════════════════════
# 1. Preflight
# ═══════════════════════════════════════════════════════════════════
source(file.path(FUNC_PATH, "validation", "preflight_memory.R"))
preflight_check(STRATEGY_ID, family = STRATEGY_FAM)

# ═══════════════════════════════════════════════════════════════════
# 2. Load RAWDATA
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 2] Loading RAWDATA...\n")
source(file.path(FUNC_PATH, "backtest_harness.R"))
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)

RAWDATA[, Date := as.Date(Date)]
BM_DT[, Date   := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]
BM_DT   <- BM_DT[Date >= ANALYSIS_START_DATE]

drop_cols <- intersect(c("Open", "High", "Low", "source", "Market"), names(RAWDATA))
if (length(drop_cols) > 0) RAWDATA[, (drop_cols) := NULL]

# 유동성 rolling 20d
setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradVal := Close * Vol]
RAWDATA[, LIQ_20d := frollmean(TradVal, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
RAWDATA[, TradVal := NULL]

# 시그널 날짜
RAWDATA[, YM := format(Date, "%Y-%m")]
sig_dates_dt <- RAWDATA[, .(sig_date = max(Date)), by = YM]
setorder(sig_dates_dt, sig_date)
sig_dates_dt <- sig_dates_dt[sig_date >= SIGNAL_START_DATE]
SIG_DATES <- sig_dates_dt$sig_date

SIG_SNAP <- RAWDATA[Date %in% SIG_DATES & !is.na(Close),
                    .(Date, Ticker, Close, LIQ_20d)]
setkey(SIG_SNAP, Date, Ticker)

RAWDATA[, c("LIQ_20d", "YM") := NULL]
setkey(RAWDATA, Date, Ticker)
gc(verbose = FALSE)

cat(sprintf("[Step 2] RAWDATA: %s rows | %d tickers | %d signal dates\n",
            format(nrow(RAWDATA), big.mark = ","),
            uniqueN(RAWDATA$Ticker),
            length(SIG_DATES)))

# ═══════════════════════════════════════════════════════════════════
# 3. Load Factor DB — Q01_GPA + V01_BM + M01_Mom_12_1 (C15)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 3] Building monthly factor signals via load_month_factors()...\n")
source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

# 필요 팩터: 알파(Q01) + 필터용(V01, M01)
TARGET_FACTORS  <- c("Q01_GPA")
FILTER_FACTORS  <- c("V01_BM", "M01_Mom_12_1")
ALL_FACTORS     <- c(TARGET_FACTORS, FILTER_FACTORS)

z_safe <- function(x) {
  n_valid <- sum(!is.na(x))
  if (n_valid < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm = TRUE)
  s  <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x)))
  (x - mu) / s
}

FACTORS_list <- vector("list", length(SIG_DATES))

for (i in seq_along(SIG_DATES)) {
  sd_i <- SIG_DATES[i]

  univ <- SIG_SNAP[Date == sd_i & !is.na(LIQ_20d) & LIQ_20d >= LIQ_THRESHOLD]
  if (nrow(univ) < N_HOLD) next

  # Factor DB 로드 (C15, C14 준수)
  fdb <- tryCatch(
    load_month_factors(sd_i, coverage_min = 0.05),
    error = function(e) {
      cat(sprintf("  [WARN] %s: factor DB load failed: %s\n", sd_i, conditionMessage(e)))
      NULL
    }
  )
  if (is.null(fdb) || nrow(fdb) == 0) next

  # 필요 팩터만 추출
  fdb_sub <- fdb[Factor_Name %in% ALL_FACTORS & Ticker %in% univ$Ticker]
  if (nrow(fdb_sub) == 0) next

  fdb_wide <- dcast(fdb_sub, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  fdb_wide <- merge(fdb_wide, univ[, .(Ticker)], by = "Ticker")

  # 없는 컬럼 NA로 초기화
  for (col in ALL_FACTORS) {
    if (!col %in% names(fdb_wide)) fdb_wide[, (col) := NA_real_]
  }

  # Cross-Exposure 필터 적용 (Z_Score_Aligned 기준)
  # V01_BM 하위 20% 제외: Z_Score_Aligned가 낮을수록 BM이 낮음 (value trap)
  if (!all(is.na(fdb_wide$V01_BM))) {
    bm_q20   <- quantile(fdb_wide$V01_BM, BM_EXCL_PCTL, na.rm = TRUE)
    fdb_wide <- fdb_wide[is.na(V01_BM) | V01_BM >= bm_q20]
  }

  # M01_Mom_12_1 하위 20% 제외: 모멘텀 하락주 제거 (momentum crash 방어)
  if (!all(is.na(fdb_wide$M01_Mom_12_1))) {
    mom_q20  <- quantile(fdb_wide$M01_Mom_12_1, MOM_EXCL_PCTL, na.rm = TRUE)
    fdb_wide <- fdb_wide[is.na(M01_Mom_12_1) | M01_Mom_12_1 >= mom_q20]
  }

  if (nrow(fdb_wide) < N_HOLD) next

  # Q01_GPA z-score (C13: Z_Score_Aligned 사용)
  fdb_wide[, z_GPA := z_safe(Q01_GPA)]
  valid <- fdb_wide[!is.na(z_GPA)]
  if (nrow(valid) < N_HOLD) next

  setorder(valid, -z_GPA)
  top <- head(valid, N_HOLD)

  FACTORS_list[[i]] <- data.table(
    Date   = sd_i,
    Ticker = top$Ticker,
    Score  = top$z_GPA
  )
}

FACTORS <- rbindlist(FACTORS_list[!sapply(FACTORS_list, is.null)])
rm(FACTORS_list, SIG_SNAP); gc(verbose = FALSE)

cat(sprintf("[Step 3] FACTORS built: %d rows | %d signal months | %s ~ %s\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            min(FACTORS$Date), max(FACTORS$Date)))

if (nrow(FACTORS) == 0) stop("[ABORT] No factor signals generated.")

# ═══════════════════════════════════════════════════════════════════
# 4. Backtest — EW, S1 순수 신호
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 4] Running S1 backtest (EW, no overlay)...\n")

sim <- run_monthly_simulation(
  RAWDATA,
  BM_DT,
  FACTORS,
  n_holdings    = N_HOLD,
  weight_method = "equal",
  commission    = COMMISSION,
  buffer_zone   = list(keep_n = 35L, entry_n = 30L)
)

perf_strat <- summarise_perf(sim$strategy_xts, "STR_1638_EnhancedQuality")
perf_bm    <- summarise_perf(sim$bm_xts, "KOSPI200")
to_ann     <- calc_turnover(sim$PORTFOLIO_LOG, sim$DAILY_NAV_DT)

cat("\n")
cat("================================================================\n")
cat("   STR_1638 Enhanced Quality Defense — S1 결과\n")
cat("================================================================\n")
print(rbind(perf_strat, perf_bm))
cat(sprintf("  Turnover (ann.): %.1f%%\n", to_ann))
cat("================================================================\n")

# ═══════════════════════════════════════════════════════════════════
# 5. Beta Estimation
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 5] Beta estimation...\n")

strat_ret <- as.numeric(sim$strategy_xts)
bm_ret    <- as.numeric(sim$bm_xts)
valid_idx <- !is.na(strat_ret) & !is.na(bm_ret)

if (sum(valid_idx) > 12) {
  lm_fit    <- lm(strat_ret[valid_idx] ~ bm_ret[valid_idx])
  beta_full <- coef(lm_fit)[2]
  cat(sprintf("  Full-period beta: %.3f\n", beta_full))
} else {
  beta_full <- NA_real_
}

# ═══════════════════════════════════════════════════════════════════
# 6. Charts
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 6] Generating charts...\n")
generate_charts(sim, output_dir = OUT_DIR,
                strategy_name = "STR_1638 Enhanced Quality Defense")

# ═══════════════════════════════════════════════════════════════════
# 7. Save Results
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 7] Saving results...\n")

fwrite(FACTORS, file.path(OUT_DIR, "factors.csv"))
fwrite(sim$DAILY_NAV_DT, file.path(OUT_DIR, "daily_nav.csv"))

perf_json <- list(
  strategy      = STRATEGY_ID,
  description   = "Enhanced Quality: Q01_GPA + V01_BM bottom-20% excl + M01 bottom-20% excl",
  hypothesis    = "H_1638: Cross-Exposure Filter로 가치함정·모멘텀 하락주 제거",
  stage         = "S1",
  factors_used  = ALL_FACTORS,
  filters_applied = list(
    value_trap_excl   = sprintf("V01_BM bottom %.0f%%", BM_EXCL_PCTL * 100),
    momentum_crash_excl = sprintf("M01 bottom %.0f%%", MOM_EXCL_PCTL * 100)
  ),
  perf_strategy = as.list(perf_strat),
  perf_bm       = as.list(perf_bm),
  beta_full     = beta_full,
  turnover_ann  = to_ann,
  n_signal_months = uniqueN(FACTORS$Date),
  s1_pass       = list(
    sr_ok     = as.numeric(perf_strat[["Sharpe"]]) > 0.40,
    mdd_ok    = abs(as.numeric(perf_strat[["MDD"]])) < 0.55,
    beta_ok   = !is.na(beta_full) && beta_full < 0.85
  ),
  run_time_secs = as.numeric(difftime(Sys.time(), t0, units = "secs"))
)

write_json(perf_json, file.path(OUT_DIR, "performance.json"),
           pretty = TRUE, auto_unbox = TRUE)

# ═══════════════════════════════════════════════════════════════════
# 8. Defense Conditional Performance (L-112 요구사항)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 8] Defense conditional performance analysis...\n")

## 8a. 위기 구간 성과
stress_tbl <- stress_test(sim$strategy_xts, sim$bm_xts)
cat("\n-- 위기 구간 성과 --\n")
print(stress_tbl)

## 8b. bad_ic_ratio
both_idx  <- index(sim$strategy_xts)
strat_vec <- as.numeric(sim$strategy_xts)
bm_vec    <- as.numeric(sim$bm_xts)
excess_vec <- strat_vec - bm_vec

bad_dates <- (both_idx >= as.Date("2007-10-01") & both_idx <= as.Date("2009-03-31")) |
             (both_idx >= as.Date("2020-01-01") & both_idx <= as.Date("2020-06-30")) |
             (both_idx >= as.Date("2022-01-01") & both_idx <= as.Date("2022-12-31"))

bad_excess  <- excess_vec[bad_dates  & !is.na(excess_vec)]
norm_excess <- excess_vec[!bad_dates & !is.na(excess_vec)]

bad_ic_ratio <- NA_real_
if (length(bad_excess) >= 3 && length(norm_excess) >= 3) {
  bad_sr  <- mean(bad_excess,  na.rm = TRUE) / (sd(bad_excess,  na.rm = TRUE) + 1e-8)
  norm_sr <- mean(norm_excess, na.rm = TRUE) / (sd(norm_excess, na.rm = TRUE) + 1e-8)
  bad_ic_ratio <- bad_sr / (norm_sr + 1e-8)
  cat(sprintf("\n  bad_IC_ratio (bad_SR / normal_SR): %.3f\n", bad_ic_ratio))
  cat(sprintf("  (> 1이면 위기 시 초과수익 상대적으로 우수)\n"))
}

## 8c. Core Alpha(STR_1550) 상관 분석
core_nav_path <- file.path(PROJECT_ROOT, "04_Research", "strategies",
                            "STR_1550_quality_composite_v2", "output", "daily_nav.csv")
corr_core <- NA_real_
if (file.exists(core_nav_path)) {
  core_nav <- fread(core_nav_path)
  if ("Date" %in% names(core_nav) && "Strategy_Ret" %in% names(core_nav)) {
    core_nav[, Date := as.Date(Date)]
    strat_nav <- sim$DAILY_NAV_DT[, .(Date, Strategy_Ret)]
    merged_corr <- merge(strat_nav, core_nav[, .(Date, Core_Ret = Strategy_Ret)],
                         by = "Date", all = FALSE)
    if (nrow(merged_corr) >= 12) {
      corr_core <- cor(merged_corr$Strategy_Ret, merged_corr$Core_Ret,
                       use = "complete.obs")
      cat(sprintf("\n  Correlation vs Core Alpha (STR_1550): %.3f\n", corr_core))
    }
  }
} else {
  cat("  [INFO] Core Alpha STR_1550 daily_nav.csv not found. Skipping correlation.\n")
}

## 8d. 조건부 성과 저장
conditional_perf <- list(
  strategy      = STRATEGY_ID,
  beta_full     = beta_full,
  bad_ic_ratio  = bad_ic_ratio,
  corr_core_alpha = corr_core,
  stress_periods  = stress_tbl
)
saveRDS(conditional_perf, file.path(OUT_DIR, "conditional_perf.rds"))

perf_json$conditional <- list(
  beta_full       = beta_full,
  bad_ic_ratio    = bad_ic_ratio,
  corr_core_alpha = corr_core
)
write_json(perf_json, file.path(OUT_DIR, "performance.json"),
           pretty = TRUE, auto_unbox = TRUE)

# ═══════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════════════════════════════
elapsed <- difftime(Sys.time(), t0, units = "secs")
cat(sprintf("\n[DONE] STR_1638 complete in %.1f seconds.\n", elapsed))
cat("================================================================\n")
cat("   STR_1638 Enhanced Quality Defense — 최종 요약\n")
cat("================================================================\n")
cat(sprintf("  SR: %.3f | CAGR: %.1f%% | MDD: %.1f%%\n",
            as.numeric(perf_strat[["Sharpe"]]),
            as.numeric(perf_strat[["CAGR"]]) * 100,
            as.numeric(perf_strat[["MDD"]]) * 100))
cat(sprintf("  TO: %.1f%% | Beta: %.3f\n", to_ann, beta_full))
cat(sprintf("  bad_IC_ratio: %s\n",
            ifelse(is.na(bad_ic_ratio), "NA", sprintf("%.3f", bad_ic_ratio))))
cat(sprintf("  Corr vs Core: %s\n",
            ifelse(is.na(corr_core), "NA", sprintf("%.3f", corr_core))))
cat("================================================================\n")
cat("=== END STR_1638 ===\n")
