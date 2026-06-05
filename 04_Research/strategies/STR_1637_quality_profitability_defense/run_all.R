cat("=== STR_1637: Quality-Profitability Defense (GPA + Gross Margin) ===\n")
## 핵심아이디어: Q01_GPA(50%) + Q10_Gross_Margin(50%) EW z-score blend
## 수익성 상위 기업 = 경기 방어력 확보. 상위 20% MAX 제외 (고변동 방어).
## S1 순수 팩터 신호. DD/VT/Regime overlay 없음.
## Novy-Marx (2013) gross profitability premium + GPA 가설.

set.seed(20240408)
t0 <- Sys.time()

# ═══════════════════════════════════════════════════════════════════
# 0. Environment
# ═══════════════════════════════════════════════════════════════════
.root_candidates <- c(
  Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
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

STRATEGY_ID   <- "STR_1637"
STRATEGY_FAM  <- "quality_defense"
N_HOLD        <- 30L
LIQ_THRESHOLD <- 2e8
COMMISSION    <- 0.0015   # 15bps
MAX21D_EXCL   <- 0.80     # 상위 20% 변동성 제외

cat(sprintf("[setup] PROJECT_ROOT: %s\n", PROJECT_ROOT))
cat(sprintf("[setup] OUT_DIR: %s\n", OUT_DIR))

# ═══════════════════════════════════════════════════════════════════
# 1. Preflight
# ═══════════════════════════════════════════════════════════════════
source(file.path(FUNC_PATH, "validation", "preflight_memory.R"))
preflight_check(STRATEGY_ID, family = STRATEGY_FAM)

# ═══════════════════════════════════════════════════════════════════
# 2. Load RAWDATA (C15: load_rawdata once)
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

# 불필요 컬럼 제거
drop_cols <- intersect(c("Open", "High", "Low", "source", "Market"), names(RAWDATA))
if (length(drop_cols) > 0) RAWDATA[, (drop_cols) := NULL]

# 유동성 (rolling 20d)
setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradVal := Close * Vol]
RAWDATA[, LIQ_20d := frollmean(TradVal, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
RAWDATA[, TradVal := NULL]

# MAX21d (t-1 lag) — C9 준수
# Rcpp-accelerated rolling max via backtest_harness (already loaded)
# Fast path: cumulative rolling max using data.table shift chain
RAWDATA[, Ret_abs := abs(Ret)]
# Build 21-element window max with shift: max of lags 0..20
RAWDATA[, MAX21d_raw := Reduce(pmax, lapply(0:20, function(k) {
  shift(Ret_abs, n = k, type = "lag", fill = NA)
})), by = Ticker]
RAWDATA[, MAX21d := shift(MAX21d_raw, n = 1L, type = "lag"), by = Ticker]
RAWDATA[, c("Ret_abs", "MAX21d_raw") := NULL]

# 시그널 날짜 목록
RAWDATA[, YM := format(Date, "%Y-%m")]
sig_dates_dt <- RAWDATA[, .(sig_date = max(Date)), by = YM]
setorder(sig_dates_dt, sig_date)
sig_dates_dt <- sig_dates_dt[sig_date >= SIGNAL_START_DATE]
SIG_DATES <- sig_dates_dt$sig_date

# 스냅샷
SIG_SNAP <- RAWDATA[Date %in% SIG_DATES & !is.na(Close),
                    .(Date, Ticker, Close, LIQ_20d, MAX21d)]
setkey(SIG_SNAP, Date, Ticker)

# RAWDATA 정리 (LIQ/MAX 컬럼 제거)
RAWDATA[, c("LIQ_20d", "MAX21d", "YM") := NULL]
setkey(RAWDATA, Date, Ticker)
gc(verbose = FALSE)

cat(sprintf("[Step 2] RAWDATA: %s rows | %d tickers | %d signal dates\n",
            format(nrow(RAWDATA), big.mark = ","),
            uniqueN(RAWDATA$Ticker),
            length(SIG_DATES)))

# ═══════════════════════════════════════════════════════════════════
# 3. Load Factor DB (C15: load_month_factors 경유)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 3] Building monthly factor signals via load_month_factors()...\n")
source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

TARGET_FACTORS <- c("Q01_GPA", "Q10_Gross_Margin")

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

  # 유니버스 필터
  univ <- SIG_SNAP[Date == sd_i & !is.na(LIQ_20d) & LIQ_20d >= LIQ_THRESHOLD]
  if (nrow(univ) < N_HOLD) next

  # MAX21d 상위 20% 제외
  max21_q80 <- quantile(univ$MAX21d, MAX21D_EXCL, na.rm = TRUE)
  univ <- univ[is.na(MAX21d) | MAX21d <= max21_q80]
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
  fdb_sub <- fdb[Factor_Name %in% TARGET_FACTORS & Ticker %in% univ$Ticker]
  if (nrow(fdb_sub) == 0) next

  # Wide 변환
  fdb_wide <- dcast(fdb_sub, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  fdb_wide <- merge(fdb_wide, univ[, .(Ticker)], by = "Ticker")

  # 필요 컬럼 확인
  miss_cols <- setdiff(TARGET_FACTORS, names(fdb_wide))
  if (length(miss_cols) > 0) {
    for (mc in miss_cols) fdb_wide[, (mc) := NA_real_]
  }

  # Composite: EW 50/50 z-score blend (C13: Z_Score_Aligned 사용)
  fdb_wide[, z_GPA       := z_safe(Q01_GPA)]
  fdb_wide[, z_GrossMargin := z_safe(Q10_Gross_Margin)]

  # 두 팩터 모두 사용 가능한 종목만
  valid <- fdb_wide[!is.na(z_GPA) & !is.na(z_GrossMargin)]
  if (nrow(valid) < N_HOLD) {
    # 단일 팩터 fallback
    valid <- fdb_wide[!is.na(z_GPA) | !is.na(z_GrossMargin)]
    valid[is.na(z_GPA), z_GPA := 0]
    valid[is.na(z_GrossMargin), z_GrossMargin := 0]
  }
  if (nrow(valid) < N_HOLD) next

  valid[, Composite := 0.5 * z_GPA + 0.5 * z_GrossMargin]
  setorder(valid, -Composite)
  top <- head(valid, N_HOLD)

  FACTORS_list[[i]] <- data.table(
    Date   = sd_i,
    Ticker = top$Ticker,
    Score  = top$Composite
  )
}

FACTORS <- rbindlist(FACTORS_list[!sapply(FACTORS_list, is.null)])
rm(FACTORS_list, SIG_SNAP); gc(verbose = FALSE)

cat(sprintf("[Step 3] FACTORS built: %d rows | %d signal months | %s ~ %s\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            min(FACTORS$Date), max(FACTORS$Date)))

if (nrow(FACTORS) == 0) stop("[ABORT] No factor signals generated.")

# ═══════════════════════════════════════════════════════════════════
# 4. Backtest — EW, S1 순수 신호 (overlay 없음)
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

perf_strat <- summarise_perf(sim$strategy_xts, "STR_1637_QualProfit")
perf_bm    <- summarise_perf(sim$bm_xts, "KOSPI200")
to_ann     <- calc_turnover(sim$PORTFOLIO_LOG, sim$DAILY_NAV_DT)

cat("\n")
cat("================================================================\n")
cat("   STR_1637 Quality-Profitability Defense — S1 결과\n")
cat("================================================================\n")
print(rbind(perf_strat, perf_bm))
cat(sprintf("  Turnover (ann.): %.1f%%\n", to_ann))
cat("================================================================\n")

# ═══════════════════════════════════════════════════════════════════
# 5. Beta Estimation (vs KOSPI200, rolling 36m)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 5] Beta estimation...\n")

strat_ret <- as.numeric(sim$strategy_xts)
bm_ret    <- as.numeric(sim$bm_xts)
dates_ret <- index(sim$strategy_xts)

# OLS beta (full period)
valid_idx <- !is.na(strat_ret) & !is.na(bm_ret)
if (sum(valid_idx) > 12) {
  lm_fit  <- lm(strat_ret[valid_idx] ~ bm_ret[valid_idx])
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
                strategy_name = "STR_1637 Quality-Profitability Defense")

# ═══════════════════════════════════════════════════════════════════
# 7. Save Results
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 7] Saving results...\n")

fwrite(FACTORS, file.path(OUT_DIR, "factors.csv"))
fwrite(sim$DAILY_NAV_DT, file.path(OUT_DIR, "daily_nav.csv"))

perf_json <- list(
  strategy      = STRATEGY_ID,
  description   = "Quality-Profitability Defense: Q01_GPA(50%) + Q10_Gross_Margin(50%) EW blend",
  hypothesis    = "H_1637: 수익성 상위 기업의 방어적 알파 (Novy-Marx 2013)",
  stage         = "S1",
  factors_used  = TARGET_FACTORS,
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

## 8a. 위기 구간 성과 (stress_test 활용)
stress_tbl <- stress_test(sim$strategy_xts, sim$bm_xts)
cat("\n-- 위기 구간 성과 --\n")
print(stress_tbl)

## 8b. bad_ic / normal_ic ratio (월별 IC proxy: 전략수익률 vs 다음달 수익률)
# 월별 포트 수익률 대 KOSPI200 초과수익 관계로 beta 조건부 분기
strat_monthly <- sim$strategy_xts
bm_monthly    <- sim$bm_xts
both_idx      <- index(strat_monthly)

# GFC + COVID + Rate 구간 = "bad regime"
bad_dates <- (both_idx >= as.Date("2007-10-01") & both_idx <= as.Date("2009-03-31")) |
             (both_idx >= as.Date("2020-01-01") & both_idx <= as.Date("2020-06-30")) |
             (both_idx >= as.Date("2022-01-01") & both_idx <= as.Date("2022-12-31"))

strat_vec <- as.numeric(strat_monthly)
bm_vec    <- as.numeric(bm_monthly)
excess_vec <- strat_vec - bm_vec

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

## 8d. 조건부 성과 요약 저장
conditional_perf <- list(
  strategy      = STRATEGY_ID,
  beta_full     = beta_full,
  bad_ic_ratio  = bad_ic_ratio,
  corr_core_alpha = corr_core,
  stress_periods  = stress_tbl
)
saveRDS(conditional_perf, file.path(OUT_DIR, "conditional_perf.rds"))

# 업데이트된 JSON에 조건부 성과 포함
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
cat(sprintf("\n[DONE] STR_1637 complete in %.1f seconds.\n", elapsed))
cat("================================================================\n")
cat("   STR_1637 Quality-Profitability Defense — 최종 요약\n")
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
cat("=== END STR_1637 ===\n")
