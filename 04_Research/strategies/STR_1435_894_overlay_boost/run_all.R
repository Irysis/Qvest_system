cat("=== STR_1435: STR_894 Overlay Boost (VT tune + DD tighter) ===\n")
## 핵심아이디어: STR_894(R3Y SR 2.418, SR 1.159, MDD 20.7%)의 VT+DD 미세 조정으로 SR 개선
## CR08 Factor DB 미구축 → VT/DD 파라미터 최적화에 집중
set.seed(1435); options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
STRATEGY_NAME <- "EV_STR894_OVR_BOOST"; STRATEGY_ID <- "STR_1435"
STRATEGY_FAMILY <- "ev_894_overlay_boost"; QEPM_AUTO_COMMIT <- TRUE

SCRIPT_DIR <- tryCatch({d <- dirname(sys.frame(1)$ofile); if (d == ".") getwd() else d},
                        error = function(e) getwd())
INFRA_DIR <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R")))
  INFRA_DIR <- file.path("/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
                          "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts)

tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", e$message, "\n"))

# ============================================================================
# Phase 1: Load parent STR_894 sim_result
# ============================================================================
cat("[Phase 1] Loading parent STR_894...\n")
PARENT_DIR <- file.path(SCRIPT_DIR, "..", "STR_894_886_v1_overlay")
sim_parent <- readRDS(file.path(PARENT_DIR, "sim_result.rds"))

raw_ret   <- as.numeric(sim_parent$strategy_xts)
raw_ret[is.na(raw_ret)] <- 0
raw_dates <- as.Date(index(sim_parent$strategy_xts))
n_f       <- length(raw_ret)
cat(sprintf("  Loaded: %d days, mean_ret=%.5f\n", n_f, mean(raw_ret)))

# ============================================================================
# Phase 2: VT 16% (tighter than parent's 18%) + expanding vol (t-1)
# ============================================================================
cat("[Phase 2] VT 16% (tighter, expanding, t-1)...\n")
VT_TARGET <- 0.16
expanding_vol <- numeric(n_f)
for (i in 2:n_f) {
  vol_i <- sd(raw_ret[1:(i - 1)]) * sqrt(252)
  expanding_vol[i] <- if (is.na(vol_i) || vol_i < 1e-8) VT_TARGET else vol_i
}
expanding_vol[1] <- VT_TARGET
vt_scalar <- fifelse(expanding_vol > 0, VT_TARGET / expanding_vol, 1.0)
vt_scalar <- pmin(pmax(vt_scalar, 0.3), 1.5)
vt_scalar_lagged <- c(1.0, head(vt_scalar, -1))
after_vt <- raw_ret * vt_scalar_lagged

# ============================================================================
# Phase 3: DD Brake 5/18 (tighter: early entry, fast full hedge)
# ============================================================================
cat("[Phase 3] DD 5/18 (tighter, t-1)...\n")
nav_dd <- cumprod(1 + after_vt)
dd_pct <- 1 - nav_dd / cummax(nav_dd)
DD_START <- 0.05; DD_FULL <- 0.18; DD_MIN_EXP <- 0.30
dd_pct_lagged <- c(0, dd_pct[-n_f])
dd_exp_lagged <- fifelse(dd_pct_lagged <= DD_START, 1.0,
  fifelse(dd_pct_lagged >= DD_FULL, DD_MIN_EXP,
    pmax(DD_MIN_EXP, 1.0 - (dd_pct_lagged - DD_START) /
           (DD_FULL - DD_START) * (1 - DD_MIN_EXP))))
final_ret <- after_vt * dd_exp_lagged

# ============================================================================
# Phase 4: Assembly + Output
# ============================================================================
combined_xts <- xts(final_ret, order.by = raw_dates); names(combined_xts) <- "Strategy"
sim <- sim_parent; sim$strategy_xts <- combined_xts; sim$bm_xts <- sim_parent$bm_xts[raw_dates]
sim$DAILY_NAV_DT <- data.table(Date = raw_dates, NAV = cumprod(1 + final_ret) * 10000, Strategy_Ret = final_ret)

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
