cat("=== STR_1622_M8_dd_brake_620: IC-Weighted Statistical Blend 5F + DD Brake 6/20 ===\n")
## Mutation M8: 기본 5F IC-weighted + DD Brake. position_size=0.5 if dd_lag>0.20 else 1.0.
## C9 필수: dd_lag <- c(0, dd_pct[-n]) — same-day DD 사용 금지.
## Arnott et al. 2019 + DeMiguel et al. 2009.
set.seed(1622); options(scipen=999); Sys.setenv(TZ="Asia/Seoul")
STRATEGY_NAME <- "IC_Weighted_5F_DD_Brake"; STRATEGY_ID <- "STR_1622_M8_dd_brake_620"; STRATEGY_FAMILY <- "core_alpha"
QEPM_AUTO_COMMIT <- TRUE
SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error=function(e) getwd())
INFRA_DIR <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R")))
  INFRA_DIR <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R")); source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts); library(arrow); library(dplyr)
tryCatch({ source(file.path(VALIDATION_DIR, "preflight_memory.R")); preflight_check(STRATEGY_ID, family=STRATEGY_FAMILY) }, error=function(e) cat("[Preflight]", e$message, "\n"))
tryCatch({ source(file.path(VALIDATION_DIR, "lookahead_detector.R")); la1 <- detect_lookahead(file.path(SCRIPT_DIR, "run_all.R")); la2 <- detect_lookahead(file.path(SCRIPT_DIR, "factor_engine.R")); if (!la1$clean || !la2$clean) stop("Lookahead violations -- aborting."); cat("[PIT] CLEAN\n") }, error=function(e) { if (grepl("Lookahead", e$message)) stop(e$message); cat("[PIT]", e$message, "\n") })
LIQ_THRESHOLD <- 2e8
cat("\n[Phase 1] Loading data + factor engine (5F IC-weighted)...\n")
res <- load_rawdata(use_cache=TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; RAWDATA_ORIG <- copy(RAWDATA); rm(res); gc(verbose=FALSE)
source(file.path(SCRIPT_DIR, "factor_engine.R"))
stopifnot(is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)), nrow(FACTORS) > 0)
cat("\n[Phase 2] DD Brake backtest (N=30, EW, BZ 50/25, DD Brake entry=6% exit=20%)...\n")
RAWDATA <- copy(RAWDATA_ORIG)

# --- DD Brake: 내장 harness dd_brake 파라미터 사용 (C9 준수 harness 내장) ---
# entry_pct=0.06: 6% DD 시 선형 축소 시작
# exit_pct=0.20:  20% DD 시 완전 현금화 (노출도 0%)
# 6~20% 구간에서 노출도 1.0→0.0 선형 감소 → 20% DD 근방에서 ~50% 노출
# backtest_harness.R 내장 C9: peak NAV는 전일 기준 (t-1 lag 자동 적용)
sim <- run_monthly_simulation(RAWDATA=RAWDATA, BM_DT=BM_DT, FACTORS=FACTORS,
                               n_holdings=30L, weight_method="equal",
                               commission=0.0015,
                               buffer_zone=list(keep_n=50L, entry_n=25L),
                               dd_brake=list(entry_pct=0.06, exit_pct=0.20))

cat("\n[Phase 3] Analysis + Hurdle...\n")
output_dir <- file.path(SCRIPT_DIR, "output"); dir.create(output_dir, showWarnings=FALSE, recursive=TRUE)
perf_strat <- summarise_perf(sim$strategy_xts, STRATEGY_NAME); perf_bm <- summarise_perf(sim$bm_xts, "BM")
cat(sprintf("  %s: CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n", STRATEGY_ID, perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD))
generate_charts(sim, output_dir=output_dir, strategy_name=STRATEGY_NAME)
fwrite(rbind(perf_strat, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds")); saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))
RAWDATA <- copy(RAWDATA_ORIG)
tryCatch({ source(file.path(INFRA_DIR, "strategy_analyzer.R")); run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir, strategy_name=STRATEGY_ID) }, error=function(e) cat("[WARN]", e$message, "\n"))
source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result=sim, FACTORS=FACTORS, strategy_name=STRATEGY_NAME, strategy_file=file.path(SCRIPT_DIR,"factor_engine.R"), output_dir=output_dir)
jsonlite::write_json(hurdle, file.path(output_dir, "hurdle_result.json"), auto_unbox=TRUE, pretty=TRUE)
cat(sprintf("  Grade: %s | Score: %.1f\n", hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0))
tryCatch({ source(file.path(TELEGRAM_DIR, "telegram_notify.R")); hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json")); tg_strategy_result_with_chart(STRATEGY_ID, hr, output_dir) }, error=function(e) cat("[TG]", e$message, "\n"))
if (isTRUE(QEPM_AUTO_COMMIT)) tryCatch({ qh <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "qepm", "scripts", "hybrid_mode.R"); if(file.exists(qh)) { source(qh); if(exists("hybrid_commit")) hybrid_commit(strategy_name=STRATEGY_ID, family=STRATEGY_FAMILY, hurdle_result=hurdle, artifact_paths=list(output_dir)) } }, error=function(e) cat("[QEPM]", e$message, "\n"))
cat(sprintf("\n=== %s Complete. Grade=%s Score=%.1f ===\n", STRATEGY_ID, hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0))
