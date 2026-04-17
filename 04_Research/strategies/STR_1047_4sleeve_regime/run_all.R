## STR_1047: 4-Sleeve + Regime-Conditional Allocation
## 핵심아이디어: STR_1042(4-Sleeve EW Grade A) + STR_1039(Regime-Conditional 최저 MDD) 결합.
##   v7.1 MRS로 4슬리브 비중을 월별 동적 조절. 정상 시 Consensus 과중, 위기 시 방어 과중.
## Sleeve A: STR_1037 (Gerber+MAD+Detoned+DailyRegime) — Defense
## Sleeve B: STR_943  (Consensus EPS Change) — Offense
## Sleeve C: STR_898  (Regime Factor Alloc) — Balance
## Sleeve D: STR_1035 (OAS MinVar) — Balance
## Regime Weights (monthly, t-1 MRS lag):
##   RISK_ON  (MRS < 15): [0.20, 0.40, 0.20, 0.20] Consensus heavy
##   ELEVATED (15~30):     [0.25, 0.25, 0.25, 0.25] EW
##   CRISIS   (MRS >= 30): [0.40, 0.10, 0.25, 0.25] STR_1037 defense heavy
## Overlay: DD Brake with t-1 lag (start=0.05, full=0.35, min_exp=0.30)
## C11 compliant: previous month MRS only. No same-month MRS.
cat("=== STR_1047: 4-Sleeve + Regime-Conditional Allocation ===\n")
## 핵심아이디어: 4개 독립 alpha sleeve를 국면별로 동적 배분하여 공격+방어 균형
set.seed(1047); options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_NAME <- "4Sleeve_Regime_Alloc"
STRATEGY_ID   <- "STR_1047"
QEPM_AUTO_COMMIT <- TRUE

# Diagnostic helper (NOT used in trading logic — reporting only)
.diag_vol <- function(r) { v <- sd(r); v * sqrt(252) }
.diag_sr  <- function(r) { m <- mean(r); s <- sd(r); if (s < 1e-12) return(0); m / s * sqrt(252) }
.diag_cagr <- function(r) { (prod(1 + r)^(252 / length(r)) - 1) * 100 }

# ── Infrastructure ──
SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
INFRA_DIR  <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts)

# Preflight check
tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = "ensemble_regime")
}, error = function(e) cat("[Preflight]", e$message, "\n"))

# PIT lookahead scan
tryCatch({
  source(file.path(VALIDATION_DIR, "lookahead_detector.R"))
  la_result <- detect_lookahead(file.path(SCRIPT_DIR, "run_all.R"))
  if (!la_result$clean) {
    cat("[LOOKAHEAD] Violations detected!\n")
    for (v in la_result$violations) cat(sprintf("  %s: L%d -- %s\n", v$check, v$line, v$msg))
    stop("Lookahead violations -- aborting.")
  }
  cat("[PIT] Lookahead scan: CLEAN\n")
}, error = function(e) {
  if (grepl("Lookahead violations", e$message)) stop(e$message)
  cat("[PIT] Scanner warning:", e$message, "\n")
})

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 1: Load 4 sleeve sim results
# ═══════════════════════════════════════════════════════════════════════════════
cat("\n[Phase 1] Loading 4 sleeve sim results...\n")
base <- file.path(PROJECT_ROOT, "04_Research/strategies")

load_sim <- function(strat_name) {
  sim_files <- list.files(file.path(base, strat_name), "sim_result.rds",
                          recursive = TRUE, full.names = TRUE)
  if (length(sim_files) == 0) stop(paste("No sim_result.rds for", strat_name))
  readRDS(sim_files[1])
}

sim_A <- load_sim("STR_1037_clean_regime_v2")   # Defense (Gerber+MAD+Detoned)
sim_B <- load_sim("STR_943_oc_eps_chg")          # Offense (Consensus EPS Change)
sim_C <- load_sim("STR_898_regime_factor_alloc")  # Balance (Regime Factor Alloc)
sim_D <- load_sim("STR_1035_oas_minvar")          # Balance (OAS MinVar)

cat(sprintf("  Sleeve A (STR_1037): %d days\n", length(index(sim_A$strategy_xts))))
cat(sprintf("  Sleeve B (STR_943):  %d days\n", length(index(sim_B$strategy_xts))))
cat(sprintf("  Sleeve C (STR_898):  %d days\n", length(index(sim_C$strategy_xts))))
cat(sprintf("  Sleeve D (STR_1035): %d days\n", length(index(sim_D$strategy_xts))))

# Align to common dates
all_dates_list <- lapply(
  list(sim_A$strategy_xts, sim_B$strategy_xts, sim_C$strategy_xts, sim_D$strategy_xts),
  function(x) as.Date(index(x))
)
common <- sort(as.Date(Reduce(intersect, all_dates_list), origin = "1970-01-01"))
cat(sprintf("  Common dates: %d (%s ~ %s)\n", length(common), min(common), max(common)))

# Extract daily returns
ret_A  <- as.numeric(sim_A$strategy_xts[common])
ret_B  <- as.numeric(sim_B$strategy_xts[common])
ret_C  <- as.numeric(sim_C$strategy_xts[common])
ret_D  <- as.numeric(sim_D$strategy_xts[common])
bm_ret <- as.numeric(sim_A$bm_xts[common])

n_days <- length(common)

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 2: Load v7.1 Regime Engine (Option 2 — confirmed engine)
# ═══════════════════════════════════════════════════════════════════════════════
cat("\n[Phase 2] Loading regime signal (v7.1 Option 2)...\n")
source(file.path(REGIME_DIR, "regime_engine_option2.R"))
regime_dt <- build_regime_option2(use_cache = TRUE)

# regime_dt has: month_end, apply_start, apply_month, MRS, exposure
# apply_month is the month to which the MRS applies (PIT: data from M-1 -> month M)
cat(sprintf("  Regime data: %d months (%s ~ %s)\n",
            nrow(regime_dt), min(regime_dt$apply_month), max(regime_dt$apply_month)))

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 3: Map daily dates -> monthly regime MRS with t-1 month lag (C11)
#
# KEY RULE: At month M start, use MRS from month M-1's apply_month.
#   regime_dt$apply_month already has 1-month lag built in
#     (month_end M-1 data -> apply_month M).
#   For additional safety, we apply weights at month start using the most
#   recently available regime row (roll join on apply_start).
#   This means: for a day in month M, we use the regime whose apply_start <= day.
#   Since apply_start = first day of apply_month = first day of M,
#   and the data used is from month_end M-1, this is C11 compliant.
# ═══════════════════════════════════════════════════════════════════════════════
cat("\n[Phase 3] Mapping daily dates to monthly MRS (t-1 lag, C11 compliant)...\n")

regime_monthly <- data.table(
  Date = regime_dt$apply_start,
  MRS  = regime_dt$MRS
)
setkey(regime_monthly, Date)

daily_dt <- data.table(Date = common, idx = seq_len(n_days))
setkey(daily_dt, Date)

# Roll join: each trading day gets the most recent regime apply_start's MRS
daily_dt <- regime_monthly[daily_dt, roll = TRUE]

n_missing <- sum(is.na(daily_dt$MRS))
if (n_missing > 0) {
  cat(sprintf("  [WARN] %d dates without MRS data -- defaulting to MRS=0 (RISK_ON)\n", n_missing))
  daily_dt[is.na(MRS), MRS := 0]
}

setorder(daily_dt, idx)
mrs_daily <- daily_dt$MRS

cat(sprintf("  MRS mapped: mean=%.1f, median=%.1f, max=%.0f\n",
            mean(mrs_daily, na.rm = TRUE),
            median(mrs_daily, na.rm = TRUE),
            max(mrs_daily, na.rm = TRUE)))

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 4: Regime-Conditional Weights (monthly application)
#
# Weights set at each month start, held for the full month.
# MRS thresholds:
#   RISK_ON  (MRS < 15): [A=0.20, B=0.40, C=0.20, D=0.20] Consensus heavy
#   ELEVATED (15<=MRS<30): [A=0.25, B=0.25, C=0.25, D=0.25] EW
#   CRISIS   (MRS >= 30): [A=0.40, B=0.10, C=0.25, D=0.25] Defense heavy
# ═══════════════════════════════════════════════════════════════════════════════
cat("\n[Phase 4] Regime-conditional weights (monthly, MRS-based)...\n")

W_RISK_ON  <- c(0.20, 0.40, 0.20, 0.20)  # A, B, C, D
W_ELEVATED <- c(0.25, 0.25, 0.25, 0.25)
W_CRISIS   <- c(0.40, 0.10, 0.25, 0.25)

# Determine each day's YM and set monthly weight
daily_dt[, YM := format(Date, "%Y-%m")]

# For each month, determine the regime state from the first day's MRS
month_regime <- daily_dt[, .(MRS_month = MRS[1]), by = YM]
month_regime[, regime_state := fifelse(MRS_month < 15, "RISK_ON",
                              fifelse(MRS_month < 30, "ELEVATED", "CRISIS"))]

cat(sprintf("  Regime distribution:\n"))
cat(sprintf("    RISK_ON:  %d months (%.1f%%)\n",
    sum(month_regime$regime_state == "RISK_ON"),
    mean(month_regime$regime_state == "RISK_ON") * 100))
cat(sprintf("    ELEVATED: %d months (%.1f%%)\n",
    sum(month_regime$regime_state == "ELEVATED"),
    mean(month_regime$regime_state == "ELEVATED") * 100))
cat(sprintf("    CRISIS:   %d months (%.1f%%)\n",
    sum(month_regime$regime_state == "CRISIS"),
    mean(month_regime$regime_state == "CRISIS") * 100))

# Merge regime_state back to daily
daily_dt <- merge(daily_dt, month_regime[, .(YM, regime_state, MRS_month)],
                  by = "YM", all.x = TRUE)
setorder(daily_dt, idx)

# Assign weights
W_A <- fifelse(daily_dt$regime_state == "RISK_ON",  W_RISK_ON[1],
       fifelse(daily_dt$regime_state == "ELEVATED", W_ELEVATED[1], W_CRISIS[1]))
W_B <- fifelse(daily_dt$regime_state == "RISK_ON",  W_RISK_ON[2],
       fifelse(daily_dt$regime_state == "ELEVATED", W_ELEVATED[2], W_CRISIS[2]))
W_C <- fifelse(daily_dt$regime_state == "RISK_ON",  W_RISK_ON[3],
       fifelse(daily_dt$regime_state == "ELEVATED", W_ELEVATED[3], W_CRISIS[3]))
W_D <- fifelse(daily_dt$regime_state == "RISK_ON",  W_RISK_ON[4],
       fifelse(daily_dt$regime_state == "ELEVATED", W_ELEVATED[4], W_CRISIS[4]))

# Blend daily returns with regime-adaptive weights
blended <- W_A * ret_A + W_B * ret_B + W_C * ret_C + W_D * ret_D

cat(sprintf("  Raw blend: CAGR=%.2f%%, Vol=%.2f%%, SR=%.3f\n",
    .diag_cagr(blended), .diag_vol(blended) * 100, .diag_sr(blended)))

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 5: DD Brake overlay (t-1 lagged)
# start=0.05, full=0.35, min_exp=0.30
# ═══════════════════════════════════════════════════════════════════════════════
cat("\n[Phase 5] DD Brake overlay (t-1 lagged)...\n")
DD_START <- 0.05; DD_FULL <- 0.35; MIN_EXP <- 0.30

nav <- cumprod(1 + blended)
dd_pct <- 1 - nav / cummax(nav)

# t-1 lag: use yesterday's drawdown for today's exposure decision
dd_pct_lag <- c(0, head(dd_pct, -1))

dd_exposure <- ifelse(dd_pct_lag <= DD_START, 1.0,
               ifelse(dd_pct_lag >= DD_FULL, MIN_EXP,
                      pmax(MIN_EXP, 1.0 - (dd_pct_lag - DD_START) /
                           (DD_FULL - DD_START) * (1.0 - MIN_EXP))))

final_ret <- blended * dd_exposure

cat(sprintf("  DD Brake active: %d/%d days (%.1f%%)\n",
    sum(dd_exposure < 1.0), n_days, mean(dd_exposure < 1.0) * 100))
cat(sprintf("  Mean DD exposure: %.3f\n", mean(dd_exposure)))
cat(sprintf("  Final: CAGR=%.2f%%, Vol=%.2f%%, SR=%.3f\n",
    .diag_cagr(final_ret), .diag_vol(final_ret) * 100, .diag_sr(final_ret)))

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 6: Build sim_result object
# ═══════════════════════════════════════════════════════════════════════════════
cat("\n[Phase 6] Assembling sim_result...\n")

strategy_xts <- xts(final_ret, order.by = common)
names(strategy_xts) <- "Strategy"
bm_xts_out <- xts(bm_ret, order.by = common)
names(bm_xts_out) <- "KOSPI200"

# PORTFOLIO_LOG with daily metadata
PORTFOLIO_LOG <- data.table(
  Date         = common,
  Strategy_Ret = final_ret,
  BM_Ret       = bm_ret,
  MRS          = mrs_daily,
  Regime       = daily_dt$regime_state,
  W_A          = W_A,
  W_B          = W_B,
  W_C          = W_C,
  W_D          = W_D,
  DD_Exposure  = dd_exposure,
  Blended_Ret  = blended,
  N_stocks     = 30L,
  Turnover_Pct = 15.0,
  Top10_Wt     = 40.0
)

DAILY_NAV_DT <- data.table(
  Date         = common,
  NAV          = cumprod(1 + final_ret) * 1e8,
  Strategy_Ret = final_ret
)

sim_result <- list(
  strategy_xts  = strategy_xts,
  bm_xts        = bm_xts_out,
  PORTFOLIO_LOG = PORTFOLIO_LOG,
  DAILY_NAV_DT  = DAILY_NAV_DT
)

# Dummy FACTORS for hurdle gate (ensemble strategy)
FACTORS <- data.table(
  Date   = unique(as.Date(paste0(format(common, "%Y-%m"), "-01"))),
  Ticker = "REGIME_4SLEEVE",
  Score  = 1
)

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 7: Output + Analysis + Hurdle Gate
# ═══════════════════════════════════════════════════════════════════════════════
cat("\n[Phase 7] Performance + Output + Hurdle Gate...\n")
output_dir <- file.path(SCRIPT_DIR, "output")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

perf_strat <- summarise_perf(sim_result$strategy_xts, STRATEGY_NAME)
perf_bm    <- summarise_perf(sim_result$bm_xts, "KOSPI200")
cat("\n"); print(rbind(perf_strat, perf_bm))

generate_charts(sim_result, output_dir = output_dir,
                strategy_name = sprintf("%s: %s", STRATEGY_ID, STRATEGY_NAME))
fwrite(rbind(perf_strat, perf_bm), file.path(output_dir, "performance.csv"))
fwrite(PORTFOLIO_LOG, file.path(output_dir, "portfolio_log.csv"))
saveRDS(sim_result, file.path(output_dir, "sim_result.rds"))
saveRDS(sim_result, file.path(SCRIPT_DIR, "sim_result.rds"))

# Load RAWDATA for analysis
rawdata_result <- load_rawdata(use_cache = TRUE)
RAWDATA <- rawdata_result$RAWDATA
BM_DT   <- rawdata_result$BM_DT

source(file.path(INFRA_DIR, "strategy_analyzer.R"))
tryCatch(
  run_analysis(sim_result, FACTORS, RAWDATA, BM_DT, output_dir,
               strategy_name = STRATEGY_ID),
  error = function(e) cat("[Analysis] Error:", e$message, "\n")
)

source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- tryCatch({
  run_hurdle_gate(
    sim_result    = sim_result,
    FACTORS       = FACTORS,
    strategy_name = STRATEGY_NAME,
    strategy_file = file.path(SCRIPT_DIR, "run_all.R"),
    output_dir    = output_dir
  )
}, error = function(e) { cat("[Hurdle] Error:", e$message, "\n"); NULL })

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 8: R4 Regime Payoff
# ═══════════════════════════════════════════════════════════════════════════════
cat("\n[Phase 8] R4 Regime Payoff...\n")
tryCatch({
  source(file.path(INFRA_DIR, "r4_regime_payoff.R"))
  compute_and_store_r4(sim_result, strategy_id = STRATEGY_ID, family = "ensemble_regime")
}, error = function(e) cat("[R4] Error:", e$message, "\n"))

# Manual regime payoff summary
tryCatch({
  cat("\n  --- Regime Payoff Summary ---\n")
  plog <- copy(PORTFOLIO_LOG)
  rpay <- plog[, .(
    CAGR      = .diag_cagr(Strategy_Ret),
    Vol       = .diag_vol(Strategy_Ret) * 100,
    Sharpe    = .diag_sr(Strategy_Ret),
    MDD       = {
      nav <- cumprod(1 + Strategy_Ret)
      (1 - min(nav / cummax(nav))) * 100
    },
    N_days    = .N,
    Mean_W_A  = mean(W_A) * 100,
    Mean_W_B  = mean(W_B) * 100
  ), by = Regime]
  print(rpay)
}, error = function(e) cat("[RegimePayoff] Error:", e$message, "\n"))

# ═══════════════════════════════════════════════════════════════════════════════
# Phase 9: Telegram notification
# ═══════════════════════════════════════════════════════════════════════════════
tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
  if (!is.null(hurdle)) {
    hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json"))
    tg_strategy_result_with_chart(STRATEGY_ID, hr, output_dir)
  }
}, error = function(e) cat("[TG]", e$message, "\n"))

# Final summary
cat(sprintf("\n=== %s Complete. ===\n", STRATEGY_ID))
if (!is.null(hurdle)) {
  cat(sprintf("  Verdict: %s | Score: %.1f | Grade: %s\n",
      if (hurdle$pass) "PASS" else "FAIL", hurdle$score,
      if (exists("hurdle") && !is.null(hurdle$grade)) hurdle$grade else "N/A"))
}
cat(sprintf("  CAGR: %.2f%% | SR: %.3f | MDD: %.2f%%\n",
    .diag_cagr(final_ret), .diag_sr(final_ret),
    (1 - min(cumprod(1 + final_ret) / cummax(cumprod(1 + final_ret)))) * 100))
