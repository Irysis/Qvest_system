cat("=== STR_1571: C19+V14+D01+L22 4F Blend + DD 8/22 + Regime ===\n")
## STR_1555 M9에 L22 diversifier 추가. 4-factor score blend.
## C19(consensus) + V14(value) + D01(defense) + L22(microstructure diversifier)
## L22-C19 corr = -0.108 → 4th factor로 추가 시 SR 개선 가능?
set.seed(1571); options(scipen=999); Sys.setenv(TZ="Asia/Seoul")
STRATEGY_NAME <- "C19_V14_D01_L22_DD_Regime"; STRATEGY_ID <- "STR_1571"; STRATEGY_FAMILY <- "4f_score_blend"
QEPM_AUTO_COMMIT <- TRUE
SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error=function(e) getwd())
INFRA_DIR <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R")))
  INFRA_DIR <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R")); source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts); library(arrow)
tryCatch({ source(file.path(VALIDATION_DIR, "lookahead_detector.R")); la <- detect_lookahead(file.path(SCRIPT_DIR, "run_all.R")); if (!la$clean) stop("Lookahead"); cat("[PIT] CLEAN\n") }, error=function(e) { if (grepl("Lookahead", e$message)) stop(e$message); cat("[PIT]", e$message, "\n") })
LIQ_THRESHOLD <- 2e8

cat("\n[Phase 1] Loading data...\n")
res <- load_rawdata(use_cache=TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; RAWDATA_ORIG <- copy(RAWDATA); rm(res); gc(verbose=FALSE)

# Factor Engine: C19 40% + V14 25% + D01 15% + L22 20%
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
all_dates <- sort(unique(RAWDATA$Date))
RAWDATA[, YM_tmp := format(Date, "%Y-%m")]
sig_dates <- RAWDATA[, .(SigDate = max(Date)), by = YM_tmp][order(YM_tmp)]$SigDate
RAWDATA[, YM_tmp := NULL]
cat(sprintf("[Factor Engine] C19 40%% + V14 25%% + D01 15%% + L22 20%%, %d dates...\n", length(sig_dates)))

FACTORS <- rbindlist(lapply(sig_dates, function(sd) {
  fdt <- tryCatch(load_month_factors(sd, coverage_min = 0.01), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) return(NULL)
  c19 <- fdt[Factor_Name == "C19_Composite_Earnings" & !is.na(Z_Score_Aligned), .(Ticker, C19 = Z_Score_Aligned)]
  v14 <- fdt[Factor_Name == "V14_EBIT_EV" & !is.na(Z_Score_Aligned), .(Ticker, V14 = Z_Score_Aligned)]
  d01 <- fdt[Factor_Name == "D01_IdioVol" & !is.na(Z_Score_Aligned), .(Ticker, D01 = Z_Score_Aligned)]
  l22 <- fdt[Factor_Name == "L22_Ret_Autocorr" & !is.na(Z_Score_Aligned), .(Ticker, L22 = Z_Score_Aligned)]
  if (nrow(c19) == 0 || nrow(v14) == 0 || nrow(d01) == 0 || nrow(l22) == 0) return(NULL)
  blend <- Reduce(function(a, b) merge(a, b, by = "Ticker"), list(c19, v14, d01, l22))
  blend[, Score := 0.40 * C19 + 0.25 * V14 + 0.15 * D01 + 0.20 * L22]
  blend[, Date := sd]
  blend[, .(Date, Ticker, Score)]
}))
stopifnot(nrow(FACTORS) > 0)
cat(sprintf("[Factor Engine] FACTORS: %d rows, %d dates\n", nrow(FACTORS), length(unique(FACTORS$Date))))

cat("\n[Phase 2] Base backtest...\n")
RAWDATA <- copy(RAWDATA_ORIG)
sim_base <- run_monthly_simulation(RAWDATA=RAWDATA, BM_DT=BM_DT, FACTORS=FACTORS, n_holdings=30L, weight_method="equal", commission=0.0015, buffer_zone=list(keep_n=50L, entry_n=25L))
p_base <- summarise_perf(sim_base$strategy_xts, "Base")
cat(sprintf("  Base: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n", p_base$Sharpe, p_base$CAGR, p_base$MDD))

cat("\n[Phase 3] DD 8/22 + Regime overlay...\n")
rr <- as.numeric(sim_base$strategy_xts); rr[is.na(rr)] <- 0; nf <- length(rr)
nav <- cumprod(1+rr); dd <- 1-nav/cummax(nav); dd_lag <- c(0, dd[-nf])
dd_exp <- fifelse(dd_lag<=0.08,1,fifelse(dd_lag>=0.22,0.25,pmax(0.25,1-(dd_lag-0.08)/(0.22-0.08)*0.75)))

regime_exp <- rep(1, nf)
tryCatch({
  source(file.path(REGIME_DIR, "regime_signal.R")); sdt <- load_regime_signal()
  rd <- as.Date(index(sim_base$strategy_xts)); cash_pct <- numeric(nf)
  for(j in seq_len(nf)){row<-sdt[Date<=rd[j]];if(nrow(row)>0) cash_pct[j]<-tail(row$Cash_Pct,1)}
  cash_lag <- c(0, cash_pct[-nf]); regime_exp <- 1-cash_lag
}, error=function(e) cat("[Regime]", e$message, "\n"))

combined_exp <- dd_exp * regime_exp
overlay_ret <- rr * combined_exp
sim_overlay <- sim_base
sim_overlay$strategy_xts <- xts(overlay_ret, order.by=as.Date(index(sim_base$strategy_xts)))
names(sim_overlay$strategy_xts) <- "Strategy"

cat("\n[Phase 4] Analysis + Hurdle...\n")
output_dir <- file.path(SCRIPT_DIR, "output"); dir.create(output_dir, showWarnings=FALSE, recursive=TRUE)
perf <- summarise_perf(sim_overlay$strategy_xts, STRATEGY_NAME); perf_bm <- summarise_perf(sim_overlay$bm_xts, "BM")
cat(sprintf("  %s: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n", STRATEGY_ID, perf$Sharpe, perf$CAGR, perf$MDD))
generate_charts(sim_overlay, output_dir=output_dir, strategy_name=STRATEGY_NAME)
fwrite(rbind(perf, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim_overlay, file.path(output_dir, "sim_result.rds")); saveRDS(sim_overlay, file.path(SCRIPT_DIR, "sim_result.rds"))
RAWDATA <- copy(RAWDATA_ORIG)
tryCatch({ source(file.path(INFRA_DIR, "strategy_analyzer.R")); run_analysis(sim_overlay, FACTORS, RAWDATA, BM_DT, output_dir, strategy_name=STRATEGY_ID) }, error=function(e) cat("[WARN]", e$message, "\n"))
source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result=sim_overlay, FACTORS=FACTORS, strategy_name=STRATEGY_NAME, strategy_file=file.path(SCRIPT_DIR,"run_all.R"), output_dir=output_dir)
jsonlite::write_json(hurdle, file.path(output_dir, "hurdle_result.json"), auto_unbox=TRUE, pretty=TRUE)
cat(sprintf("  Grade: %s | Score: %.1f\n", hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0))
tryCatch({ source(file.path(TELEGRAM_DIR, "telegram_notify.R")); hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json")); tg_strategy_result_with_chart(STRATEGY_ID, hr, output_dir) }, error=function(e) cat("[TG]", e$message, "\n"))
if (isTRUE(QEPM_AUTO_COMMIT)) tryCatch({ qh <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "qepm", "scripts", "hybrid_mode.R"); if(file.exists(qh)) { source(qh); if(exists("hybrid_commit")) hybrid_commit(strategy_name=STRATEGY_ID, family=STRATEGY_FAMILY, hurdle_result=hurdle, artifact_paths=list(output_dir)) } }, error=function(e) cat("[QEPM]", e$message, "\n"))
cat(sprintf("\n=== %s Complete. Grade=%s Score=%.1f SR=%.3f CAGR=%.2f%% MDD=%.1f%% ===\n", STRATEGY_ID, hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0, perf$Sharpe, perf$CAGR, perf$MDD))
