cat("=== S5-M3: VT 15% + DD 8/20 ===\n")
set.seed(1424); options(scipen=999); Sys.setenv(TZ="Asia/Seoul")
SCRIPT_DIR <- tryCatch({d<-dirname(sys.frame(1)$ofile); if(d==".") getwd() else d}, error=function(e) getwd())
INFRA_DIR <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R")))
  INFRA_DIR <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R")); source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts)
sim_parent <- readRDS(file.path(SCRIPT_DIR, "sim_result.rds"))
raw_ret <- as.numeric(sim_parent$strategy_xts); raw_ret[is.na(raw_ret)] <- 0
raw_dates <- as.Date(index(sim_parent$strategy_xts)); n_f <- length(raw_ret)
VT_TARGET <- 0.15; expanding_vol <- numeric(n_f)
for (i in 2:n_f) { vol_i <- sd(raw_ret[1:(i-1)])*sqrt(252); expanding_vol[i] <- if(is.na(vol_i)||vol_i<1e-8) VT_TARGET else vol_i }
expanding_vol[1] <- VT_TARGET
vt_scalar <- fifelse(expanding_vol>0, VT_TARGET/expanding_vol, 1.0); vt_scalar <- pmin(pmax(vt_scalar,0.3),1.5)
vt_lagged <- c(1.0, head(vt_scalar,-1)); after_vt <- raw_ret*vt_lagged
DD_START <- 0.08; DD_FULL <- 0.20; DD_MIN_EXP <- 0.30
nav_dd <- cumprod(1+after_vt); dd_pct <- 1-nav_dd/cummax(nav_dd); dd_lag <- c(0, dd_pct[-n_f])
dd_exp <- fifelse(dd_lag<=DD_START,1.0,fifelse(dd_lag>=DD_FULL,DD_MIN_EXP,pmax(DD_MIN_EXP,1.0-(dd_lag-DD_START)/(DD_FULL-DD_START)*(1-DD_MIN_EXP))))
final_ret <- after_vt*dd_exp
combined_xts <- xts(final_ret, order.by=raw_dates); names(combined_xts) <- "Strategy"
sim <- sim_parent; sim$strategy_xts <- combined_xts; sim$bm_xts <- sim_parent$bm_xts[raw_dates]
sim$DAILY_NAV_DT <- data.table(Date=raw_dates, NAV=cumprod(1+final_ret)*10000, Strategy_Ret=final_ret)
output_dir <- file.path(SCRIPT_DIR, "output_s5_m3"); dir.create(output_dir, showWarnings=FALSE, recursive=TRUE)
perf <- summarise_perf(sim$strategy_xts, "S5_M3_VT15_DD8_20"); perf_bm <- summarise_perf(sim$bm_xts, "BM")
cat(sprintf("  M3: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n", perf$Sharpe, perf$CAGR, perf$MDD))
generate_charts(sim, output_dir=output_dir, strategy_name="S5_M3_VT15_DD8_20")
fwrite(rbind(perf, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds"))
source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result=sim, strategy_name="S5_M3_VT15_DD8_20", output_dir=output_dir)
jsonlite::write_json(hurdle, file.path(output_dir, "hurdle_result.json"), auto_unbox=TRUE, pretty=TRUE)
cat(sprintf("  Grade: %s Score: %.1f\n", hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0))
tryCatch({ source(file.path(TELEGRAM_DIR, "telegram_notify.R")); hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json")); tg_strategy_result_with_chart("S5_M3_TailRisk", hr, output_dir) }, error=function(e) cat("[TG]", e$message, "\n"))
cat("=== S5-M3 Complete ===\n")
