## ══════════════════════════════════════════════════════════════════════════════
## STR_686: Multi-Sleeve D70/M30 + Momentum VT15%
## Base: STR_680 (D70/M30 equal-vol blending)
## Change: Momentum sleeve vol_target 0.25 → 0.15 (tighter VT to curb MDD)
## Defense sleeve: vol_target 0.25 unchanged
## Ref: Asness et al. (2013), Moreira & Muir (2017) Volatility-Managed Portfolios
## ══════════════════════════════════════════════════════════════════════════════
set.seed(42)
W_DEF <- 0.70   # Defense sleeve capital allocation
W_MOM <- 0.30   # Momentum sleeve capital allocation

SCRIPT_DIR <- tryCatch({ d <- dirname(sys.frame(1)$ofile); if (d == ".") getwd() else d },
  error = function(e) { args <- commandArgs(trailingOnly = FALSE); file_arg <- grep("--file=", args, value = TRUE)
    if (length(file_arg) > 0) { p <- sub("--file=", "", file_arg[1]); p <- gsub("~+~", " ", p, fixed = TRUE); dirname(p) } else getwd() })
INFRA_DIR <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R")); source(file.path(INFRA_DIR, "backtest_harness.R")); source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
cat("=== STR_686: Multi-Sleeve D70/M30 + Momentum VT15% ===\n")

## ── Load raw data ──
res <- load_rawdata(); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA)
BM_DT_ORIG   <- copy(BM_DT)

## ══════════════════════════════════════════════════════════════════════════════
## Sleeve A: Defense (Golden Formula — STR_654) — VT 0.25 (unchanged)
## ══════════════════════════════════════════════════════════════════════════════
cat("\n────────────────────────────────────────\n")
cat("[Sleeve A] Defense (Golden Formula) — VT 0.25...\n")
cat("────────────────────────────────────────\n")
source(file.path(SCRIPT_DIR, "defense_sleeve.R"))
FACTORS_DEF <- copy(FACTORS)

sim_def <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS_DEF, n_holdings = 30, weight_method = "equal",
                                   commission = 0.0015, buffer_zone = list(keep_n = 50L, entry_n = 25L),
                                   vol_target = 0.25, vol_lookback = 60L)
perf_def <- summarise_perf(sim_def$strategy_xts, "Defense_Sleeve")
cat("\n[Defense Sleeve Performance]\n"); print(perf_def)

## ══════════════════════════════════════════════════════════════════════════════
## Sleeve B: Momentum (12-1M) — VT 0.15 (tighter than STR_680's 0.25)
## ══════════════════════════════════════════════════════════════════════════════
cat("\n────────────────────────────────────────\n")
cat("[Sleeve B] Momentum (12-1M) — VT 0.15 (tighter)...\n")
cat("────────────────────────────────────────\n")
RAWDATA <- copy(RAWDATA_ORIG)
BM_DT   <- copy(BM_DT_ORIG)
source(file.path(SCRIPT_DIR, "momentum_sleeve.R"))
FACTORS_MOM <- copy(FACTORS)

sim_mom <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS_MOM, n_holdings = 30, weight_method = "equal",
                                   commission = 0.0015, buffer_zone = list(keep_n = 50L, entry_n = 25L),
                                   vol_target = 0.15, vol_lookback = 60L)
perf_mom <- summarise_perf(sim_mom$strategy_xts, "Momentum_Sleeve")
cat("\n[Momentum Sleeve Performance]\n"); print(perf_mom)

## ══════════════════════════════════════════════════════════════════════════════
## Portfolio Combination: Equity-Curve Blending
## ══════════════════════════════════════════════════════════════════════════════
cat("\n════════════════════════════════════════\n")
cat("[Portfolio] Combining sleeves...\n")
cat("════════════════════════════════════════\n")

## Align dates
common_idx <- as.Date(intersect(index(sim_def$strategy_xts), index(sim_mom$strategy_xts)))
common_idx <- sort(common_idx)
ret_def <- as.numeric(sim_def$strategy_xts[common_idx])
ret_mom <- as.numeric(sim_mom$strategy_xts[common_idx])

## Sleeve-level diagnostics
vol_def <- sd(ret_def, na.rm = TRUE) * sqrt(252)
vol_mom <- sd(ret_mom, na.rm = TRUE) * sqrt(252)
cor_val <- cor(ret_def, ret_mom, use = "complete.obs")
cat(sprintf("  Defense AnnVol : %.2f%%\n", vol_def * 100))
cat(sprintf("  Momentum AnnVol: %.2f%%\n", vol_mom * 100))
cat(sprintf("  Correlation    : %.3f\n", cor_val))

## Equal-vol scaling: scale momentum to match defense volatility
scale_mom <- vol_def / vol_mom
cat(sprintf("  Momentum scale factor: %.3f (equal-vol to defense)\n", scale_mom))

## Weighted combination (equal-vol scaled)
combined_ret <- W_DEF * ret_def + W_MOM * (ret_mom * scale_mom)
combined_xts <- xts(combined_ret, order.by = common_idx)
names(combined_xts) <- "Strategy"

## Also test raw blend (no vol scaling) for comparison
raw_combined_ret <- W_DEF * ret_def + W_MOM * ret_mom
raw_combined_xts <- xts(raw_combined_ret, order.by = common_idx)
perf_raw <- summarise_perf(raw_combined_xts, "Raw_Blend_70_30")

## Create synthetic sim object for hurdle gate compatibility
sim <- sim_def
sim$strategy_xts <- combined_xts
sim$bm_xts <- sim_def$bm_xts[common_idx]
sim$DAILY_NAV_DT <- data.table(
  Date = common_idx,
  NAV = cumprod(1 + combined_ret) * 10000,
  Strategy_Ret = combined_ret
)

## ── Output ──
output_dir <- file.path(SCRIPT_DIR, "output")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

perf <- summarise_perf(combined_xts, "STR_686")
bm_perf <- summarise_perf(sim$bm_xts, "KOSPI200")

cat("\n╔══════════════════════════════════════════╗\n")
cat("║  STR_686 Multi-Sleeve Results            ║\n")
cat("╚══════════════════════════════════════════╝\n")
print(rbind(perf, perf_def, perf_mom, perf_raw, bm_perf))
cat(sprintf("\nSleeve Correlation: %.3f\n", cor_val))
cat(sprintf("Equal-vol scaled: D %.0f%% + M %.0f%% (M scaled by %.3f)\n",
            W_DEF * 100, W_MOM * 100, scale_mom))
cat(sprintf("\n[Key Change] Momentum VT: 0.25 → 0.15 (tighter vol targeting)\n"))

## Charts + Analysis
generate_charts(sim, output_dir = output_dir, strategy_name = "STR_686: Multi-Sleeve D70/M30 + Momentum VT15%")

RAWDATA <- copy(RAWDATA_ORIG)
FACTORS <- FACTORS_DEF   # Use defense FACTORS for analysis
source(file.path(INFRA_DIR, "strategy_analyzer.R"))
run_analysis(sim, FACTORS, RAWDATA, BM_DT_ORIG, output_dir, strategy_name = "STR_686")

source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result = sim, strategy_name = "STR_686", output_dir = output_dir)

## Save all performance data
fwrite(rbind(perf, perf_def, perf_mom, perf_raw, bm_perf), file.path(output_dir, "performance.csv"))
if (nrow(sim_def$HOLDINGS_LOG) > 0) fwrite(sim_def$HOLDINGS_LOG, file.path(output_dir, "holdings_defense.csv"))
if (nrow(sim_mom$HOLDINGS_LOG) > 0) fwrite(sim_mom$HOLDINGS_LOG, file.path(output_dir, "holdings_momentum.csv"))

## Telegram
tg_strategy_result_with_chart("STR_686", hurdle, output_dir)
cat("\n[STR_686] Complete.\n")
