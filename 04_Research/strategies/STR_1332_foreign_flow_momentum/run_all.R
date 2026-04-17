## STR_1332: Foreign Flow Momentum
## 핵심아이디어: 외국인 순매수 21일 모멘텀 상위 + 외국인-개인 divergence.
##   Informed trading으로 alpha 존재. 개인 대비 외국인 divergence가 추가 신호.
## Parent: S0_2026-03-24_001 (Scout 설계)
## Academic: Froot et al.(2001), Choe, Kho & Stulz(2005) — 외국인 정보우위 한국시장
## PIT: C2(t-1 flow), C10(lagged liq), C11(investor_wide Date=거래일), C13(Z_Score_Aligned)
cat("=== STR_1332: Foreign Flow Momentum ===\n")
set.seed(1332); options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
STRATEGY_NAME  <- "ForeignFlowMom"
STRATEGY_ID    <- "STR_1332"
STRATEGY_FAMILY <- "investor_flow"
QEPM_AUTO_COMMIT <- TRUE

# ============================================================================
# Step 0: Path Resolution (한글 경로 안전)
# ============================================================================
SCRIPT_DIR <- tryCatch({
  d <- dirname(sys.frame(1)$ofile)
  if (d == ".") getwd() else d
}, error = function(e) {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    p <- sub("--file=", "", file_arg[1])
    p <- gsub("~+~", " ", p, fixed = TRUE)
    dirname(p)
  } else getwd()
})

INFRA_DIR <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))

tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight] ", e$message, "\n"))

cat(sprintf("\n=== %s: %s ===\n\n", STRATEGY_ID, STRATEGY_NAME))

# ============================================================================
# Constants
# ============================================================================
LIQ_THRESHOLD <- 2e8
N_HOLDINGS    <- 30L
FLOW_WINDOW   <- 21L       # 21일 순매수 rolling sum
LOOKBACK      <- 252L
MIN_OBS       <- 60L        # 최소 flow 관측 수
SECTOR_NEUTRAL <- TRUE

# ============================================================================
# Phase 1: Load Data
# ============================================================================
cat("[Phase 1] Loading data...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
rm(res); gc(verbose = FALSE)

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
all_dates <- sort(unique(RAWDATA$Date))
all_signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM]$Signal_Date
all_signal_dates <- sort(all_signal_dates)
min_start <- all_dates[min(LOOKBACK + 1L, length(all_dates))]
monthly_dates <- all_signal_dates[all_signal_dates >= min_start]

# Liquidity filter: t-1 lagged (C10)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]

# ============================================================================
# Phase 2: Load Investor Flow Data
# ============================================================================
cat("[Phase 2] Loading investor flow data...\n")
INV <- load_investor("wide")
setorder(INV, Ticker, Date)

# 외국인(Foreign) / 개인(Individual) 순매수 21d rolling sum
# C2: t-1 lag — 당일 수급은 사용 금지
INV[, Foreign_21d := frollsum(Foreign, n = FLOW_WINDOW, align = "right"), by = Ticker]
INV[, Individual_21d := frollsum(Individual, n = FLOW_WINDOW, align = "right"), by = Ticker]

# t-1 lag 적용 (C2: same-day circular 금지)
INV[, Foreign_21d_lag := shift(Foreign_21d, n = 1L, type = "lag"), by = Ticker]
INV[, Individual_21d_lag := shift(Individual_21d, n = 1L, type = "lag"), by = Ticker]

cat(sprintf("  Investor data: %s rows | %d tickers | %s ~ %s\n",
            format(nrow(INV), big.mark = ","), uniqueN(INV$Ticker),
            min(INV$Date), max(INV$Date)))

# ============================================================================
# Phase 3: Factor Construction — ForeignFlowMom21d + ForeignRetailDivergence
# ============================================================================
cat("[Phase 3] Computing factor scores...\n")

z_safe <- function(x) {
  s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-8) return(rep(0, length(x)))
  (x - mean(x, na.rm = TRUE)) / s
}

factor_list <- list()
n_done <- 0L; n_skipped <- 0L

for (sig_d in monthly_dates) {
  sig_d <- as.Date(sig_d)
  gc(verbose = FALSE)

  # Liquidity snapshot: t-1 기준 (C10)
  snap <- RAWDATA[Date == sig_d, .(Ticker, Close, AvgTV20, Sector)]
  snap <- snap[!is.na(Close) & Close > 0]
  snap <- snap[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(snap) < 50) { n_skipped <- n_skipped + 1L; next }

  # Investor flow snapshot: sig_d 기준 t-1 lagged values
  inv_snap <- INV[Date == sig_d & Ticker %in% snap$Ticker,
                  .(Ticker, Foreign_21d_lag, Individual_21d_lag)]
  inv_snap <- inv_snap[!is.na(Foreign_21d_lag)]
  if (nrow(inv_snap) < 50) { n_skipped <- n_skipped + 1L; next }

  # Merge sector info
  inv_snap <- merge(inv_snap, snap[, .(Ticker, Sector)], by = "Ticker", all.x = TRUE)

  # Factor 1: ForeignFlowMom21d — 외국인 21일 순매수 합계 z-score
  inv_snap[, z_ffm := z_safe(Foreign_21d_lag)]

  # Factor 2: ForeignRetailDivergence — z(외국인) - z(개인)
  inv_snap[, z_frd := z_safe(Foreign_21d_lag) - z_safe(Individual_21d_lag)]

  # Composite: EW 0.5 + 0.5 (Z_Score_Aligned: 높을수록 good)
  inv_snap[, Score := 0.5 * z_ffm + 0.5 * z_frd]

  # Sector neutralization
  if (SECTOR_NEUTRAL) {
    inv_snap[!is.na(Sector), Score := Score - mean(Score, na.rm = TRUE), by = Sector]
  }

  inv_snap[, Date := sig_d]
  factor_list[[length(factor_list) + 1L]] <- inv_snap[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list)
setorder(FACTORS, Date, -Score)
cat(sprintf("[Phase 3] %d dates scored, %d skipped | %s factor rows\n",
            n_done, n_skipped, format(nrow(FACTORS), big.mark = ",")))

# Cleanup
for (col in c("TradingValue", "AvgTV20", "YM"))
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
rm(INV, inv_snap, snap, factor_list); gc(verbose = FALSE)

# ============================================================================
# Phase 4: Backtest — S4 Phase 1 Baseline (EW + EW)
# ============================================================================
cat("[Phase 4] Running backtest (Phase 1: EW+EW baseline)...\n")
sim <- run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS,
  n_holdings    = N_HOLDINGS,
  weight_method = "equal",
  commission    = 0.0015,
  buffer_zone   = list(keep_n = 50L, entry_n = 25L),
  vol_target    = 0.20,
  vol_lookback  = 60L
)

# ============================================================================
# Phase 5: DD Brake (t-1 lagged, C2/C5)
# ============================================================================
cat("[Phase 5] DD Brake...\n")
strat_ret   <- as.numeric(sim$strategy_xts)
n_f         <- length(strat_ret)
strat_dates <- as.Date(index(sim$strategy_xts))

nav_vec <- cumprod(1 + strat_ret)
dd_vec  <- 1 - nav_vec / cummax(nav_vec)

DD_START <- 0.15; DD_FULL <- 0.35; DD_MIN_EXP <- 0.30
dd_exposure <- ifelse(dd_vec <= DD_START, 1.0,
                      ifelse(dd_vec >= DD_FULL, DD_MIN_EXP,
                             pmax(DD_MIN_EXP, 1.0 - (dd_vec - DD_START) / (DD_FULL - DD_START) * (1.0 - DD_MIN_EXP))))
# t-1 lag (C5: overlay signals t-1)
dd_exp_lagged <- c(1.0, head(dd_exposure, -1))
after_dd <- strat_ret * dd_exp_lagged

# ============================================================================
# Phase 6: MRS Overlay (Regime Engine v7.1)
# ============================================================================
cat("[Phase 6] MRS Overlay (v7.1)...\n")
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
daily_regime <- build_daily_regime(strat_dates)

MRS_LOW <- 15; MRS_HIGH <- 30; MRS_MIN_EXP <- 0.30
soft_mrs_exp <- numeric(n_f)
for (i in seq_len(n_f)) {
  mrs_val <- daily_regime[Date == strat_dates[i], MRS]
  if (length(mrs_val) == 0 || is.na(mrs_val)) mrs_val <- 0
  if (mrs_val < MRS_LOW)       soft_mrs_exp[i] <- 1.0
  else if (mrs_val >= MRS_HIGH) soft_mrs_exp[i] <- MRS_MIN_EXP
  else soft_mrs_exp[i] <- 1.0 - (mrs_val - MRS_LOW) / (MRS_HIGH - MRS_LOW) * (1.0 - MRS_MIN_EXP)
}
final_ret <- after_dd * soft_mrs_exp

# ============================================================================
# Phase 7: Final Assembly
# ============================================================================
cat("[Phase 7] Final assembly...\n")
combined_xts <- xts::xts(final_ret, order.by = strat_dates)
names(combined_xts) <- "Strategy"

sim$strategy_xts <- combined_xts
sim$bm_xts <- sim$bm_xts[strat_dates]
sim$DAILY_NAV_DT <- data.table(
  Date         = strat_dates,
  NAV          = cumprod(1 + final_ret) * 10000,
  Strategy_Ret = final_ret
)

perf    <- summarise_perf(combined_xts, STRATEGY_ID)
bm_perf <- summarise_perf(sim$bm_xts, "KOSPI200")

cat(sprintf("\n  %s Results\n", STRATEGY_ID))
cat(sprintf("  CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n",
            perf$CAGR, perf$Sharpe, perf$MDD))
print(rbind(perf, bm_perf))

# ============================================================================
# Phase 8: Output + Analysis + Hurdle + Telegram
# ============================================================================
out_dir <- file.path(SCRIPT_DIR, "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))
fwrite(rbind(perf, bm_perf), file.path(out_dir, "performance.csv"))

generate_charts(sim, output_dir = out_dir,
                strategy_name = sprintf("%s: %s", STRATEGY_ID, STRATEGY_NAME))

tryCatch({
  source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, out_dir,
               strategy_name = STRATEGY_ID)
}, error = function(e) cat("[Analysis]", e$message, "\n"))

hurdle <- tryCatch({
  source(file.path(INFRA_DIR, "hurdle_gate.R"))
  run_hurdle_gate(sim_result = sim, strategy_name = STRATEGY_ID,
                  output_dir = out_dir)
}, error = function(e) { cat("Hurdle error:", e$message, "\n"); NULL })

# Telegram: Forge 시작/완료 브리핑 (feedback_forge_telegram.md)
tryCatch({
  if (!is.null(hurdle)) {
    hr <- jsonlite::fromJSON(file.path(out_dir, "hurdle_result.json"))
    tg_strategy_result_with_chart(STRATEGY_ID, hr, out_dir)
  }
}, error = function(e) cat("[TG]", e$message, "\n"))

# QEPM hybrid_commit
if (isTRUE(QEPM_AUTO_COMMIT) && exists("hybrid_commit")) {
  tryCatch({
    hybrid_commit(strategy_name = STRATEGY_ID, family = STRATEGY_FAMILY,
                  hurdle_result = hurdle, artifact_paths = list(out_dir))
  }, error = function(e) cat("[QEPM]", e$message, "\n"))
}

cat(sprintf("\n[%s] Complete.\n", STRATEGY_ID))
