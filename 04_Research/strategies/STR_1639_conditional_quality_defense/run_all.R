cat("=== STR_1639: Conditional Quality Defense (GPA + Piotroski F) ===\n")
## 핵심아이디어: Q01_GPA(50%) + Q04_Piotroski_F(50%) EW z-score blend
## 수익성(GPA) + 재무건전성(Piotroski) 이중 필터 → 실적 기반 방어주.
## S1 정적 blend. S5에서 Regime 연동 예정.
## Piotroski (2000) F-score + Novy-Marx (2013) GPA 결합.

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

STRATEGY_ID   <- "STR_1639"
STRATEGY_FAM  <- "quality_defense"
N_HOLD        <- 30L
LIQ_THRESHOLD <- 2e8
COMMISSION    <- 0.0015   # 15bps

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
# 3. Load Factor DB — Q01_GPA + Q04_Piotroski_F (C15)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 3] Building monthly factor signals via load_month_factors()...\n")
source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

TARGET_FACTORS <- c("Q01_GPA", "Q04_Piotroski_F")

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

  fdb_sub <- fdb[Factor_Name %in% TARGET_FACTORS & Ticker %in% univ$Ticker]
  if (nrow(fdb_sub) == 0) next

  fdb_wide <- dcast(fdb_sub, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  fdb_wide <- merge(fdb_wide, univ[, .(Ticker)], by = "Ticker")

  # 없는 컬럼 NA로 초기화
  for (col in TARGET_FACTORS) {
    if (!col %in% names(fdb_wide)) fdb_wide[, (col) := NA_real_]
  }

  # Composite: 50/50 EW blend (C13: Z_Score_Aligned 사용)
  fdb_wide[, z_GPA    := z_safe(Q01_GPA)]
  fdb_wide[, z_Piotr  := z_safe(Q04_Piotroski_F)]

  # 두 팩터 모두 있는 종목 우선, 없으면 단일 팩터 허용
  valid_both   <- fdb_wide[!is.na(z_GPA) & !is.na(z_Piotr)]
  valid_single <- fdb_wide[(!is.na(z_GPA) | !is.na(z_Piotr))]

  if (nrow(valid_both) >= N_HOLD) {
    valid <- valid_both
    valid[, Composite := 0.5 * z_GPA + 0.5 * z_Piotr]
  } else if (nrow(valid_single) >= N_HOLD) {
    valid <- valid_single
    valid[is.na(z_GPA),   z_GPA   := 0]
    valid[is.na(z_Piotr), z_Piotr := 0]
    valid[, Composite := 0.5 * z_GPA + 0.5 * z_Piotr]
  } else {
    next
  }

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

perf_strat <- summarise_perf(sim$strategy_xts, "STR_1639_CondQuality")
perf_bm    <- summarise_perf(sim$bm_xts, "KOSPI200")
to_ann     <- calc_turnover(sim$PORTFOLIO_LOG, sim$DAILY_NAV_DT)

cat("\n")
cat("================================================================\n")
cat("   STR_1639 Conditional Quality Defense — S1 결과\n")
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
                strategy_name = "STR_1639 Conditional Quality Defense")

# ═══════════════════════════════════════════════════════════════════
# 7. Save Results
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 7] Saving results...\n")

fwrite(FACTORS, file.path(OUT_DIR, "factors.csv"))
fwrite(sim$DAILY_NAV_DT, file.path(OUT_DIR, "daily_nav.csv"))

perf_json <- list(
  strategy      = STRATEGY_ID,
  description   = "Conditional Quality: Q01_GPA(50%) + Q04_Piotroski_F(50%) EW blend",
  hypothesis    = "H_1639: 수익성(GPA) + 재무건전성(Piotroski F) 이중 방어 (S5 Regime 연동 예정)",
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

elapsed <- difftime(Sys.time(), t0, units = "secs")
cat(sprintf("\n[DONE] STR_1639 complete in %.1f seconds.\n", elapsed))
cat(sprintf("  SR: %.3f | CAGR: %.1f%% | MDD: %.1f%% | TO: %.1f%% | Beta: %.3f\n",
            as.numeric(perf_strat[["Sharpe"]]),
            as.numeric(perf_strat[["CAGR"]]) * 100,
            as.numeric(perf_strat[["MDD"]]) * 100,
            to_ann,
            beta_full))
cat("=== END STR_1639 ===\n")
