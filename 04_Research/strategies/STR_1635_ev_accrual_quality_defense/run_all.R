cat("=== STR_1635: EV-Accrual Quality Defense ===\n")
## 핵심아이디어: V15(NetDebt Adj EP) + AC21(CF/Accrual Ratio) + C10(SUE Persistence)
## 3팩터 EW z-score blend → defense sleeve (MDD 축소 목표)
## S1: 순수 팩터 신호만. EW 30종목. DD/VT/Regime 오버레이 없음.
## 기대: SR 0.75~1.0, MDD 22~28%, TO 80~150%

set.seed(1635)
options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_NAME   <- "EV_Accrual_Quality_Defense"
STRATEGY_ID     <- "STR_1635"
STRATEGY_FAMILY <- "accrual_quality"
QEPM_AUTO_COMMIT <- TRUE

# ---- 경로 설정 (normalizePath 금지 — WSL 한글 경로 버그) ----
SCRIPT_DIR <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) getwd()
)
INFRA_DIR <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R"))) {
  INFRA_DIR <- file.path(
    "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
    "02_Infrastructure"
  )
}

source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table)
library(xts)
library(arrow)

# ---- Preflight Check ----
tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", e$message, "\n"))

# ---- Lookahead Detector (PIT C1~C11) ----
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

# ---- 상수 ----
LIQ_THRESHOLD <- 2e8  # 20일 평균 거래대금 >= 2억원

cat("\n[Phase 1] Loading data + factor engine...\n")
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA)
rm(res); gc(verbose = FALSE)

source(file.path(SCRIPT_DIR, "factor_engine.R"))

stopifnot(
  is.data.table(FACTORS),
  all(c("Date", "Ticker", "Score") %in% names(FACTORS)),
  nrow(FACTORS) > 0
)

cat("\n[Phase 2] Pure factor backtest (N=30, EW, BZ 45/30, NO overlay)...\n")
RAWDATA <- copy(RAWDATA_ORIG)

sim <- run_monthly_simulation(
  RAWDATA       = RAWDATA,
  BM_DT         = BM_DT,
  FACTORS       = FACTORS,
  n_holdings    = 30L,
  weight_method = "equal",
  commission    = 0.0015,   # 15bps
  buffer_zone   = list(keep_n = 45L, entry_n = 30L)
  # vol_target 미전달 — S1 순수 팩터 신호만
)

cat("\n[Phase 3] Analysis + Hurdle...\n")
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

RAWDATA <- copy(RAWDATA_ORIG)
tryCatch({
  source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir, strategy_name = STRATEGY_ID)
}, error = function(e) cat("[WARN]", e$message, "\n"))

source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(
  sim_result    = sim,
  FACTORS       = FACTORS,
  strategy_name = STRATEGY_NAME,
  strategy_file = file.path(SCRIPT_DIR, "factor_engine.R"),
  output_dir    = output_dir
)
jsonlite::write_json(hurdle,
  file.path(output_dir, "hurdle_result.json"),
  auto_unbox = TRUE, pretty = TRUE
)
cat(sprintf("  Grade: %s | Score: %.1f\n",
            hurdle$grade,
            hurdle$total_score %||% hurdle$score %||% 0))

# ---- 텔레그램 결과 발송 ----
tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
  hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json"))
  tg_strategy_result_with_chart(STRATEGY_ID, hr, output_dir)
}, error = function(e) cat("[TG]", e$message, "\n"))

# ---- QEPM Auto Commit ----
if (isTRUE(QEPM_AUTO_COMMIT)) {
  tryCatch({
    qh <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "qepm", "scripts", "hybrid_mode.R")
    if (file.exists(qh)) {
      source(qh)
      if (exists("hybrid_commit")) {
        hybrid_commit(
          strategy_name = STRATEGY_ID,
          family        = STRATEGY_FAMILY,
          hurdle_result = hurdle,
          artifact_paths = list(output_dir)
        )
      }
    }
  }, error = function(e) cat("[QEPM]", e$message, "\n"))
}

cat(sprintf(
  "\n=== %s Pure Factor Complete. Grade=%s Score=%.1f ===\n",
  STRATEGY_ID,
  hurdle$grade,
  hurdle$total_score %||% hurdle$score %||% 0
))
