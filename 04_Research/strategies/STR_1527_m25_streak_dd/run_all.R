cat("=== STR_1527: M25 Earnings Streak + DD Overlay ===\n")
## 핵심아이디어: M25_Earnings_Mom_Streak + V24_Residual_Income (OOS>1.8) + DD brake로 MDD 억제
## STR_1519 base (F, Score 41.6, MDD>60%) → DD overlay로 MDD<25% 목표
## S5 Mutation: DD 10/25 (moderate) + DD 15/35 (gentle) 2 variants
set.seed(1527); options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
STRATEGY_NAME <- "M25_Streak_DD"; STRATEGY_ID <- "STR_1527"
STRATEGY_FAMILY <- "momentum_value_dd"; QEPM_AUTO_COMMIT <- TRUE
SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
INFRA_DIR <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R")))
  INFRA_DIR <- file.path("/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot", "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts); library(arrow)
tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", e$message, "\n"))
tryCatch({
  source(file.path(VALIDATION_DIR, "lookahead_detector.R"))
  la1 <- detect_lookahead(file.path(SCRIPT_DIR, "run_all.R"))
  la2 <- detect_lookahead(file.path(SCRIPT_DIR, "factor_engine.R"))
  if (!la1$clean || !la2$clean) stop("Lookahead violations -- aborting.")
  cat("[PIT] CLEAN\n")
}, error = function(e) {
  if (grepl("Lookahead", e$message)) stop(e$message)
  cat("[PIT]", e$message, "\n")
})

LIQ_THRESHOLD <- 2e8

## Phase 1: Load data + factor engine
cat("\n[Phase 1] Loading data + factor engine...\n")
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA); rm(res); gc(verbose = FALSE)
source(file.path(SCRIPT_DIR, "factor_engine.R"))
stopifnot(is.data.table(FACTORS), all(c("Date", "Ticker", "Score") %in% names(FACTORS)), nrow(FACTORS) > 0)

## Phase 2: Base backtest (no overlay) — shared across variants
cat("\n[Phase 2] Base backtest (N=30, EW, BZ 50/25, NO overlay)...\n")
RAWDATA <- copy(RAWDATA_ORIG)
sim_base <- run_monthly_simulation(
  RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
  n_holdings = 30L, weight_method = "equal", commission = 0.0015,
  buffer_zone = list(keep_n = 50L, entry_n = 25L)
)
raw_ret   <- as.numeric(sim_base$strategy_xts)
raw_dates <- as.Date(index(sim_base$strategy_xts))
n_f       <- length(raw_ret)

## ===================================================================
## DD Brake helper — applies t-1 lagged drawdown brake (C2 compliant)
## dd_start: drawdown % to begin braking
## dd_full:  drawdown % at maximum brake
## dd_min_exp: minimum exposure at full brake (0.30 = 30%)
## ===================================================================
apply_dd_brake <- function(ret, dd_start, dd_full, dd_min_exp = 0.30) {
  nav   <- cumprod(1 + ret)
  dd    <- 1 - nav / cummax(nav)
  n     <- length(ret)
  ## t-1 lag (C2: same-day circular 금지)
  dd_lagged <- c(0, dd[-n])
  exposure  <- fifelse(
    dd_lagged <= dd_start, 1.0,
    fifelse(dd_lagged >= dd_full, dd_min_exp,
      pmax(dd_min_exp, 1.0 - (dd_lagged - dd_start) / (dd_full - dd_start) * (1 - dd_min_exp))
    )
  )
  ret * exposure
}

## ===================================================================
## Helper: build sim object + analysis + hurdle for a DD variant
## ===================================================================
run_dd_variant <- function(variant_label, dd_start, dd_full, output_subdir) {
  cat(sprintf("\n[%s] DD Brake %.0f/%.0f (t-1 lagged)...\n", variant_label, dd_start * 100, dd_full * 100))
  final_ret    <- apply_dd_brake(raw_ret, dd_start, dd_full, dd_min_exp = 0.30)
  combined_xts <- xts(final_ret, order.by = raw_dates)
  names(combined_xts) <- "Strategy"

  sim <- sim_base
  sim$strategy_xts <- combined_xts
  sim$bm_xts       <- sim_base$bm_xts[raw_dates]
  sim$DAILY_NAV_DT <- data.table(
    Date         = raw_dates,
    NAV          = cumprod(1 + final_ret) * 10000,
    Strategy_Ret = final_ret
  )

  out_dir <- file.path(SCRIPT_DIR, output_subdir)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  perf_s <- summarise_perf(sim$strategy_xts, variant_label)
  perf_b <- summarise_perf(sim$bm_xts, "BM")
  cat(sprintf("  %s: CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
              variant_label, perf_s$CAGR, perf_s$Sharpe, perf_s$MDD))
  generate_charts(sim, output_dir = out_dir, strategy_name = variant_label)
  fwrite(rbind(perf_s, perf_b), file.path(out_dir, "performance.csv"))
  saveRDS(sim, file.path(out_dir, "sim_result.rds"))

  RAWDATA <<- copy(RAWDATA_ORIG)
  tryCatch({
    source(file.path(INFRA_DIR, "strategy_analyzer.R"))
    run_analysis(sim, FACTORS, RAWDATA, BM_DT, out_dir, strategy_name = variant_label)
  }, error = function(e) cat("[WARN]", e$message, "\n"))

  source(file.path(INFRA_DIR, "hurdle_gate.R"))
  hurdle <- run_hurdle_gate(
    sim_result    = sim,
    FACTORS       = FACTORS,
    strategy_name = variant_label,
    strategy_file = file.path(SCRIPT_DIR, "factor_engine.R"),
    output_dir    = out_dir
  )
  jsonlite::write_json(hurdle, file.path(out_dir, "hurdle_result.json"),
                       auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf("  Grade: %s | Score: %.1f\n",
              hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0))
  hurdle
}

## Phase 3: Variant A — DD 10/25 (moderate)
hurdle_a <- run_dd_variant("M25_DD1025", dd_start = 0.10, dd_full = 0.25, "output_dd1025")

## Phase 4: Variant B — DD 15/35 (gentle)
hurdle_b <- run_dd_variant("M25_DD1535", dd_start = 0.15, dd_full = 0.35, "output_dd1535")

## Phase 5: Also save base (no overlay) for comparison
cat("\n[Phase 5] Saving base (no overlay) for reference...\n")
out_base <- file.path(SCRIPT_DIR, "output_base")
dir.create(out_base, showWarnings = FALSE, recursive = TRUE)
perf_base <- summarise_perf(sim_base$strategy_xts, "M25_Base")
perf_bm   <- summarise_perf(sim_base$bm_xts, "BM")
cat(sprintf("  Base: CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
            perf_base$CAGR, perf_base$Sharpe, perf_base$MDD))
generate_charts(sim_base, output_dir = out_base, strategy_name = "M25_Base")
fwrite(rbind(perf_base, perf_bm), file.path(out_base, "performance.csv"))
saveRDS(sim_base, file.path(out_base, "sim_result.rds"))

## Phase 6: Telegram report (best variant)
tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
  best_h <- if ((hurdle_a$total_score %||% hurdle_a$score %||% 0) >=
                (hurdle_b$total_score %||% hurdle_b$score %||% 0)) {
    list(hurdle = hurdle_a, dir = file.path(SCRIPT_DIR, "output_dd1025"), label = "DD1025")
  } else {
    list(hurdle = hurdle_b, dir = file.path(SCRIPT_DIR, "output_dd1535"), label = "DD1535")
  }
  tg_strategy_result_with_chart("STR_1527", best_h$hurdle, best_h$dir)
}, error = function(e) cat("[TG]", e$message, "\n"))

## QEPM commit
if (isTRUE(QEPM_AUTO_COMMIT)) tryCatch({
  qh <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "qepm", "scripts", "hybrid_mode.R")
  if (file.exists(qh)) {
    source(qh)
    if (exists("hybrid_commit")) hybrid_commit(
      strategy_name = STRATEGY_ID, family = STRATEGY_FAMILY,
      hurdle_result = hurdle_a, artifact_paths = list(file.path(SCRIPT_DIR, "output_dd1025"))
    )
  }
}, error = function(e) cat("[QEPM]", e$message, "\n"))

cat(sprintf("\n=== STR_1527 Complete ===\n"))
cat(sprintf("  DD 10/25: Grade=%s Score=%.1f\n", hurdle_a$grade, hurdle_a$total_score %||% hurdle_a$score %||% 0))
cat(sprintf("  DD 15/35: Grade=%s Score=%.1f\n", hurdle_b$grade, hurdle_b$total_score %||% hurdle_b$score %||% 0))
