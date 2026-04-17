cat("=== S5 MUTATION: VT 18% + DD 7/22 overlay ===\n")
set.seed(42); options(scipen=999); Sys.setenv(TZ="Asia/Seoul")
SCRIPT_DIR <- tryCatch({d<-dirname(sys.frame(1)$ofile); if(d==".") getwd() else d}, error=function(e) getwd())
INFRA_DIR <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R")))
  INFRA_DIR <- file.path("/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot", "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts)

sim_parent <- readRDS(file.path(SCRIPT_DIR, "sim_result.rds"))
raw_ret <- as.numeric(sim_parent$strategy_xts)
raw_ret[is.na(raw_ret)] <- 0
raw_dates <- as.Date(index(sim_parent$strategy_xts))
n_f <- length(raw_ret)
cat(sprintf("  Loaded: %d days\n", n_f))

## VT 18% (expanding, t-1)
VT_TARGET <- 0.18
expanding_vol <- numeric(n_f)
for (i in 2:n_f) {
  vol_i <- sd(raw_ret[1:(i-1)]) * sqrt(252)
  expanding_vol[i] <- if (is.na(vol_i) || vol_i < 1e-8) VT_TARGET else vol_i
}
expanding_vol[1] <- VT_TARGET
vt_scalar <- fifelse(expanding_vol > 0, VT_TARGET / expanding_vol, 1.0)
vt_scalar <- pmin(pmax(vt_scalar, 0.3), 1.5)
vt_lagged <- c(1.0, head(vt_scalar, -1))
after_vt <- raw_ret * vt_lagged

## DD 7/22 (t-1)
nav_dd <- cumprod(1 + after_vt)
dd_pct <- 1 - nav_dd / cummax(nav_dd)
dd_lag <- c(0, dd_pct[-n_f])
dd_exp <- fifelse(dd_lag <= 0.07, 1.0,
  fifelse(dd_lag >= 0.22, 0.30,
    pmax(0.30, 1.0 - (dd_lag - 0.07) / 0.15 * 0.70)))
final_ret <- after_vt * dd_exp

combined_xts <- xts(final_ret, order.by=raw_dates); names(combined_xts) <- "Strategy"
sim <- sim_parent; sim$strategy_xts <- combined_xts
sim$bm_xts <- sim_parent$bm_xts[raw_dates]
sim$DAILY_NAV_DT <- data.table(Date=raw_dates, NAV=cumprod(1+final_ret)*10000, Strategy_Ret=final_ret)

output_dir <- file.path(SCRIPT_DIR, "output_s5")
dir.create(output_dir, showWarnings=FALSE, recursive=TRUE)

perf <- summarise_perf(sim$strategy_xts, "S5_Mutation"); perf_bm <- summarise_perf(sim$bm_xts, "BM")
cat(sprintf("  S5: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n", perf$Sharpe, perf$CAGR, perf$MDD))
generate_charts(sim, output_dir=output_dir, strategy_name="S5_Mutation")
fwrite(rbind(perf, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds"))

source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result=sim, strategy_name="S5_Mutation", output_dir=output_dir)
jsonlite::write_json(hurdle, file.path(output_dir, "hurdle_result.json"), auto_unbox=TRUE, pretty=TRUE)
cat(sprintf("  Grade: %s Score: %.1f\n", hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0))

tryCatch({ source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
  hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json"))
  tg_strategy_result_with_chart(paste0("S5_", basename(SCRIPT_DIR)), hr, output_dir)
}, error=function(e) cat("[TG]", e$message, "\n"))

cat("=== S5 Mutation Complete ===\n")
