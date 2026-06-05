cat("=== STR_1439: STR_1047 + Smoothed Regime Transitions (TO Fix) ===\n")
## 핵심아이디어: STR_1047(SR 1.532, MDD 18.9%, TO 3702%)의 TO를 체제전환 스무딩으로 200% 이하 제어
## 접근: regime weight 전환 시 max 10%p/month 변동 → TO 급감
set.seed(1439); options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
STRATEGY_NAME <- "EV_STR1047_TO_FIX"; STRATEGY_ID <- "STR_1439"
STRATEGY_FAMILY <- "ev_1047_to_fix"; QEPM_AUTO_COMMIT <- TRUE

SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
INFRA_DIR <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R")))
  INFRA_DIR <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
                          "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts)

tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", e$message, "\n"))

# ============================================================================
# Phase 1: Load 4 sub-sims (same as parent STR_1047)
# ============================================================================
cat("[Phase 1] Loading 4 sub-sims...\n")
base <- file.path(PROJECT_ROOT, "04_Research/strategies")
load_sim <- function(sname) {
  ff <- list.files(file.path(base, sname), "sim_result.rds", recursive = TRUE, full.names = TRUE)
  if (length(ff) == 0) stop(paste("No sim_result.rds for", sname))
  readRDS(ff[1])
}

sim_A <- load_sim("STR_1037_clean_regime_v2")
sim_B <- load_sim("STR_943_oc_eps_chg")
sim_C <- load_sim("STR_898_regime_factor_alloc")
sim_D <- load_sim("STR_1035_oas_minvar")

common <- sort(as.Date(Reduce(intersect, lapply(
  list(sim_A$strategy_xts, sim_B$strategy_xts, sim_C$strategy_xts, sim_D$strategy_xts),
  function(x) as.Date(index(x))))))
n_days <- length(common)

ret_A <- as.numeric(sim_A$strategy_xts[common])
ret_B <- as.numeric(sim_B$strategy_xts[common])
ret_C <- as.numeric(sim_C$strategy_xts[common])
ret_D <- as.numeric(sim_D$strategy_xts[common])

# ============================================================================
# Phase 2: Regime Engine (same as parent, Option 2)
# ============================================================================
cat("[Phase 2] Regime engine (daily v7.1)...\n")
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
daily_regime <- build_daily_regime(common)

daily_dt <- data.table(Date = common, idx = seq_len(n_days))
daily_dt <- merge(daily_dt, daily_regime[, .(Date, MRS)], by = "Date", all.x = TRUE)
daily_dt[is.na(MRS), MRS := 0]
setorder(daily_dt, idx)

# ============================================================================
# Phase 3: SMOOTHED Regime Weights (max 10%p change/month → TO reduction)
# ============================================================================
cat("[Phase 3] Smoothed regime weights (max 10%p/month)...\n")
W_RISK_ON  <- c(0.20, 0.40, 0.20, 0.20)
W_ELEVATED <- c(0.25, 0.25, 0.25, 0.25)
W_CRISIS   <- c(0.40, 0.10, 0.25, 0.25)
MAX_W_CHANGE <- 0.10  # max 10%p weight change per month

daily_dt[, YM := format(Date, "%Y-%m")]
month_regime <- daily_dt[, .(MRS_month = MRS[1]), by = YM]

# Target weights based on regime
get_target_w <- function(mrs) {
  if (mrs < 15) W_RISK_ON else if (mrs < 30) W_ELEVATED else W_CRISIS
}

# Smooth transitions
current_w <- W_ELEVATED  # start neutral
w_mat <- matrix(0, nrow = n_days, ncol = 4)
prev_ym <- ""
for (i in seq_len(n_days)) {
  ym <- daily_dt$YM[i]
  if (ym != prev_ym) {
    target_w <- get_target_w(daily_dt$MRS[i])
    delta <- target_w - current_w
    delta <- pmin(pmax(delta, -MAX_W_CHANGE), MAX_W_CHANGE)
    current_w <- current_w + delta
    current_w <- current_w / sum(current_w)  # normalize
    prev_ym <- ym
  }
  w_mat[i, ] <- current_w
}

# ============================================================================
# Phase 4: Weighted return blend
# ============================================================================
combined_ret <- w_mat[, 1] * ret_A + w_mat[, 2] * ret_B +
                w_mat[, 3] * ret_C + w_mat[, 4] * ret_D

# DD Brake 5/35 (same as parent, t-1 lag)
cat("[Phase 4] DD Brake 5/35 (t-1)...\n")
nav_dd <- cumprod(1 + combined_ret)
dd_pct <- 1 - nav_dd / cummax(nav_dd)
DD_START <- 0.05; DD_FULL <- 0.35; DD_MIN_EXP <- 0.30
dd_pct_lagged <- c(0, dd_pct[-n_days])
dd_exp_lagged <- fifelse(dd_pct_lagged <= DD_START, 1.0,
  fifelse(dd_pct_lagged >= DD_FULL, DD_MIN_EXP,
    pmax(DD_MIN_EXP, 1.0 - (dd_pct_lagged - DD_START) /
           (DD_FULL - DD_START) * (1 - DD_MIN_EXP))))
final_ret <- combined_ret * dd_exp_lagged

# ============================================================================
# Phase 5: Assembly + Output
# ============================================================================
combined_xts <- xts(final_ret, order.by = common); names(combined_xts) <- "Strategy"
sim <- sim_A; sim$strategy_xts <- combined_xts; sim$bm_xts <- sim_A$bm_xts[common]
sim$DAILY_NAV_DT <- data.table(Date = common, NAV = cumprod(1 + final_ret) * 10000, Strategy_Ret = final_ret)

output_dir <- file.path(SCRIPT_DIR, "output")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

perf_strat <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
perf_bm    <- summarise_perf(sim$bm_xts, "BM")
cat(sprintf("  %s: CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
            STRATEGY_ID, perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD))
generate_charts(sim, output_dir = output_dir, strategy_name = STRATEGY_NAME)
fwrite(rbind(perf_strat, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds"))
saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))

tryCatch({ source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  run_analysis(sim, data.table(), data.table(), data.table(), output_dir, strategy_name = STRATEGY_ID)
}, error = function(e) cat("[WARN]", e$message, "\n"))

source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result = sim, strategy_name = STRATEGY_NAME, output_dir = output_dir)
jsonlite::write_json(hurdle, file.path(output_dir, "hurdle_result.json"), auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("  Grade: %s Score: %.1f\n", hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0))

tryCatch({ source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
  hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json"))
  tg_strategy_result_with_chart(STRATEGY_ID, hr, output_dir)
}, error = function(e) cat("[TG]", e$message, "\n"))

cat(sprintf("=== %s Complete ===\n", STRATEGY_ID))
