cat("=== STR_1465 S5: DD 6/20 + VT 20% Dual Overlay ===\n")
set.seed(14651); options(scipen=999); Sys.setenv(TZ="Asia/Seoul")
STRATEGY_NAME <- "VWAP_Spread_Construction_DD_VT"; STRATEGY_ID <- "STR_1465"; STRATEGY_FAMILY <- "s5_dd_vt"
QEPM_AUTO_COMMIT <- TRUE
SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error=function(e) getwd())
INFRA_DIR <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R"))) INFRA_DIR <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R")); source(file.path(INFRA_DIR, "backtest_harness.R")); library(data.table); library(xts)
sim_parent <- readRDS(file.path(SCRIPT_DIR, "sim_result.rds"))
raw_ret <- as.numeric(sim_parent$strategy_xts); raw_ret[is.na(raw_ret)] <- 0
raw_dates <- as.Date(index(sim_parent$strategy_xts)); n_f <- length(raw_ret)
DD_START <- 0.06; DD_FULL <- 0.20; DD_MIN_EXP <- 0.30
nav_dd <- cumprod(1 + raw_ret); dd_pct <- 1 - nav_dd / cummax(nav_dd)
dd_lag <- c(0, dd_pct[-n_f])
dd_exp <- fifelse(dd_lag <= DD_START, 1.0, fifelse(dd_lag >= DD_FULL, DD_MIN_EXP, pmax(DD_MIN_EXP, 1.0 - (dd_lag - DD_START)/(DD_FULL - DD_START)*(1 - DD_MIN_EXP))))
VOL_TARGET <- 0.20; cum_vol <- numeric(n_f); cum_vol[1:23] <- NA_real_
for (i in 24:n_f) cum_vol[i] <- sd(raw_ret[1:i]) * sqrt(12)
vt_exp <- rep(1.0, n_f)
for (i in 25:n_f) vt_exp[i] <- pmin(1.0, VOL_TARGET / cum_vol[i-1])
final_exp <- pmin(dd_exp, vt_exp)
final_ret <- raw_ret * final_exp
combined_xts <- xts(final_ret, order.by = raw_dates); names(combined_xts) <- "Strategy"
sim <- sim_parent; sim$strategy_xts <- combined_xts; sim$bm_xts <- sim_parent$bm_xts[raw_dates]
sim$DAILY_NAV_DT <- data.table(Date=raw_dates, NAV=cumprod(1+final_ret)*10000, Strategy_Ret=final_ret)
output_dir <- file.path(SCRIPT_DIR, "output_s5_dd_vt"); dir.create(output_dir, showWarnings=FALSE, recursive=TRUE)
perf_strat <- summarise_perf(sim$strategy_xts, STRATEGY_NAME); perf_bm <- summarise_perf(sim$bm_xts, "BM")
cat(sprintf("  %s: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n", STRATEGY_ID, perf_strat$Sharpe, perf_strat$CAGR, perf_strat$MDD))
generate_charts(sim, output_dir=output_dir, strategy_name=STRATEGY_NAME)
fwrite(rbind(perf_strat, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds"))
LIQ_THRESHOLD <- 2e8
res <- load_rawdata(use_cache=TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose=FALSE)
source(file.path(SCRIPT_DIR, "factor_engine.R"))
tryCatch({ source(file.path(INFRA_DIR, "strategy_analyzer.R")); run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir, strategy_name=paste0(STRATEGY_ID,"_DD_VT")) }, error=function(e) cat("[WARN]", e$message, "\n"))
source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result=sim, FACTORS=FACTORS, strategy_name=STRATEGY_NAME, strategy_file=file.path(SCRIPT_DIR,"factor_engine.R"), output_dir=output_dir)
jsonlite::write_json(hurdle, file.path(output_dir, "hurdle_result.json"), auto_unbox=TRUE, pretty=TRUE)
cat(sprintf("  Grade: %s | Score: %.1f\n", hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0))
tryCatch({ source(file.path(TELEGRAM_DIR, "telegram_notify.R")); hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json")); tg_strategy_result_with_chart(paste0(STRATEGY_ID,"_DD_VT"), hr, output_dir) }, error=function(e) cat("[TG]", e$message, "\n"))
if (isTRUE(QEPM_AUTO_COMMIT)) tryCatch({ qh <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "qepm", "scripts", "hybrid_mode.R"); if(file.exists(qh)) { source(qh); if(exists("hybrid_commit")) hybrid_commit(strategy_name=paste0(STRATEGY_ID,"_DD_VT"), family=STRATEGY_FAMILY, hurdle_result=hurdle, artifact_paths=list(output_dir)) } }, error=function(e) cat("[QEPM]", e$message, "\n"))
cat(sprintf("\n=== %s S5 DD+VT Complete. Grade=%s Score=%.1f ===\n", STRATEGY_ID, hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0))
