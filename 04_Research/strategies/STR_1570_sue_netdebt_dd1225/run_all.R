cat("=== STR_1570: SUE×NetDebt-EP + DD Brake 12/25 (S5 M-DD) ===\n")
## STR_1453 S5 Mutation: DD Brake 12/25 overlay (wider than 8/20)
## Parent: STR_1453 (SR 1.005, CAGR 22.2%, MDD 55.4% — hard fail by 10.4%)
## Hypothesis: L-802 lesson — 8% trigger too tight for Korean market. Wider 12/25
##   reduces whipsaw while still capping tail drawdowns below 45%
## C9 compliant: dd_lag uses t-1 values only
set.seed(1570); options(scipen=999); Sys.setenv(TZ="Asia/Seoul")
STRATEGY_NAME <- "SUE_NetDebt_DD1225"; STRATEGY_ID <- "STR_1570"; STRATEGY_FAMILY <- "sue_netdebt_ep"
QEPM_AUTO_COMMIT <- TRUE

cat("## 핵심아이디어: STR_1453(SUE×NetDebt-EP)에 DD 12/25 wide overlay 적용\n")
cat("## L-802 근거: 한국 시장 변동성 감안, 8% trigger는 과도하게 자주 발동\n")

SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error=function(e) getwd())
INFRA_DIR <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R")))
  INFRA_DIR <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R")); source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts)
tryCatch({ source(file.path(VALIDATION_DIR, "preflight_memory.R")); preflight_check(STRATEGY_ID, family=STRATEGY_FAMILY) }, error=function(e) cat("[Preflight]", e$message, "\n"))
tryCatch({ source(file.path(VALIDATION_DIR, "lookahead_detector.R")); la1 <- detect_lookahead(file.path(SCRIPT_DIR, "run_all.R")); la2 <- detect_lookahead(file.path(SCRIPT_DIR, "factor_engine.R")); if (!la1$clean || !la2$clean) stop("Lookahead violations -- aborting."); cat("[PIT] CLEAN\n") }, error=function(e) { if (grepl("Lookahead", e$message)) stop(e$message); cat("[PIT]", e$message, "\n") })
LIQ_THRESHOLD <- 2e8

## === DD Brake Parameters (S5 overlay — WIDER per L-802) ===
DD_SHORT <- 12   # short-term DD threshold (%) — wider than 8%
DD_LONG  <- 25   # long-term DD threshold (%) — wider than 20%

## Try loading parent sim_result first (memory efficient), otherwise run full backtest
PARENT_DIR <- file.path(SCRIPT_DIR, "..", "STR_1453_sue_netdebt_ep")
parent_sim_path <- file.path(PARENT_DIR, "sim_result.rds")

if (file.exists(parent_sim_path)) {
  cat("\n[Phase 1] Loading parent sim_result from STR_1453...\n")
  sim <- readRDS(parent_sim_path)
  cat("[Phase 1] Loaded. Skipping factor engine + simulation (signal unchanged).\n")

  ## Also load FACTORS from parent for hurdle gate
  cat("[Phase 1] Loading data for hurdle gate...\n")
  res <- load_rawdata(use_cache=TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; RAWDATA_ORIG <- copy(RAWDATA); rm(res); gc(verbose=FALSE)
  library(arrow)
  source(file.path(SCRIPT_DIR, "factor_engine.R"))
  stopifnot(is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)), nrow(FACTORS) > 0)
} else {
  cat("\n[Phase 1] Loading data + factor engine (no parent sim found)...\n")
  res <- load_rawdata(use_cache=TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; RAWDATA_ORIG <- copy(RAWDATA); rm(res); gc(verbose=FALSE)
  library(arrow)
  source(file.path(SCRIPT_DIR, "factor_engine.R"))
  stopifnot(is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)), nrow(FACTORS) > 0)

  cat("\n[Phase 2] Pure factor backtest (N=30, EW, BZ 50/25, NO overlay)...\n")
  RAWDATA <- copy(RAWDATA_ORIG)
  sim <- run_monthly_simulation(RAWDATA=RAWDATA, BM_DT=BM_DT, FACTORS=FACTORS,
                                n_holdings=30L, weight_method="equal",
                                commission=0.0015,
                                buffer_zone=list(keep_n=50L, entry_n=25L))
}

cat("\n[Phase 3] DD Brake 12/25 overlay (C9: t-1 lag)...\n")
## Extract raw strategy returns
raw_ret <- as.numeric(sim$strategy_xts)
n <- length(raw_ret)

## Compute drawdown from NAV
nav <- cumprod(1 + raw_ret)
peak <- cummax(nav)
dd_pct <- (peak - nav) / peak * 100

## C9 COMPLIANT: t-1 lag — use yesterday's drawdown for today's scaling
dd_lag <- c(0, dd_pct[-n])

## DD scaling: linear ramp from 1.0 (dd<12%) to 0.0 (dd>=25%)
dd_scale <- ifelse(dd_lag >= DD_LONG, 0.0,
            ifelse(dd_lag >= DD_SHORT, 1 - (dd_lag - DD_SHORT) / (DD_LONG - DD_SHORT),
            1.0))

## Apply DD brake to returns
adjusted_ret <- raw_ret * dd_scale

## Rebuild strategy_xts with DD-adjusted returns
sim$strategy_xts <- xts(adjusted_ret, order.by=index(sim$strategy_xts))
colnames(sim$strategy_xts) <- "Strategy"

cat(sprintf("  DD brake active days: %d / %d (%.1f%%)\n",
            sum(dd_scale < 1), n, 100 * sum(dd_scale < 1) / n))
cat(sprintf("  DD fully braked (0%%): %d days\n", sum(dd_scale == 0)))

cat("\n[Phase 4] Analysis + Hurdle...\n")
output_dir <- file.path(SCRIPT_DIR, "output"); dir.create(output_dir, showWarnings=FALSE, recursive=TRUE)
perf_strat <- summarise_perf(sim$strategy_xts, STRATEGY_NAME); perf_bm <- summarise_perf(sim$bm_xts, "BM")
cat(sprintf("  %s: CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n", STRATEGY_ID, perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD))
generate_charts(sim, output_dir=output_dir, strategy_name=STRATEGY_NAME)
fwrite(rbind(perf_strat, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds")); saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))
if (!exists("RAWDATA_ORIG")) { res <- load_rawdata(use_cache=TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; RAWDATA_ORIG <- copy(RAWDATA); rm(res); gc(verbose=FALSE) }
RAWDATA <- copy(RAWDATA_ORIG)
tryCatch({ source(file.path(INFRA_DIR, "strategy_analyzer.R")); run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir, strategy_name=STRATEGY_ID) }, error=function(e) cat("[WARN]", e$message, "\n"))
source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result=sim, FACTORS=FACTORS, strategy_name=STRATEGY_NAME,
                          strategy_file=file.path(SCRIPT_DIR,"factor_engine.R"), output_dir=output_dir)
jsonlite::write_json(hurdle, file.path(output_dir, "hurdle_result.json"), auto_unbox=TRUE, pretty=TRUE)
cat(sprintf("  Grade: %s | Score: %.1f\n", hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0))

## Before/After comparison
cat(sprintf("\n--- Before/After ---\n"))
cat(sprintf("  STR_1453 (no DD):    SR=1.005, CAGR=22.2%%, MDD=55.4%% [HARD FAIL]\n"))
cat(sprintf("  STR_1570 (DD 12/25): SR=%.3f, CAGR=%.1f%%, MDD=%.1f%% [%s]\n",
            perf_strat$Sharpe, perf_strat$CAGR, perf_strat$MDD, hurdle$grade))

tryCatch({ source(file.path(TELEGRAM_DIR, "telegram_notify.R")); hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json")); tg_strategy_result_with_chart(STRATEGY_ID, hr, output_dir) }, error=function(e) cat("[TG]", e$message, "\n"))
if (isTRUE(QEPM_AUTO_COMMIT)) tryCatch({ qh <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "qepm", "scripts", "hybrid_mode.R"); if(file.exists(qh)) { source(qh); if(exists("hybrid_commit")) hybrid_commit(strategy_name=STRATEGY_ID, family=STRATEGY_FAMILY, hurdle_result=hurdle, artifact_paths=list(output_dir)) } }, error=function(e) cat("[QEPM]", e$message, "\n"))
cat(sprintf("\n=== %s Complete. Grade=%s Score=%.1f ===\n", STRATEGY_ID, hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0))
