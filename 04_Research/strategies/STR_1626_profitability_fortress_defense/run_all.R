cat("=== STR_1626: Q01_GPA + Q04_Piotroski Defense ===\n")
## 핵심아이디어: 재무건전성 이중 방어선 — GPA(수익성) 30% + F-Score(재무강건성) 70%
## Novy-Marx(2013) + Piotroski(2000) 결합: 수익성 지속성 × 재무 개선 방향성
## S1 순수 팩터 테스트 (Overlay 없음 — S5에서 추가 예정)
## N=20, EW, 15bps, LIQ 2억원 (전월 기준), defense 역할 확인
set.seed(1626); options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_NAME   <- "Profitability_Fortress_Defense"
STRATEGY_ID     <- "STR_1626"
STRATEGY_FAMILY <- "quality"
QEPM_AUTO_COMMIT <- TRUE

# ── 경로 설정 (normalizePath 금지, 한글 경로 대응) ──
SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
INFRA_DIR  <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R"))) {
  INFRA_DIR <- file.path(
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
    "02_Infrastructure"
  )
}

# ── 인프라 로드 ──
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts); library(arrow)

# ── RAM 체크 (원칙 7) ──
ram_pct <- tryCatch(
  as.numeric(system("free | awk '/Mem:/ {printf \"%.0f\", ($2-$7)/$2*100}'",
                    intern = TRUE)),
  error = function(e) 50
)
cat(sprintf("[OPT] RAM 사용률: %d%%\n", ram_pct))
if (ram_pct > 70) {
  cat("[WARN] RAM > 70%%. gc() 실행 + 대형 객체 제거 권장\n")
  gc(verbose = FALSE)
}

# ── Preflight Check ──
tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", e$message, "\n"))

# ── Lookahead Detector (C1~C11) ──
tryCatch({
  source(file.path(VALIDATION_DIR, "lookahead_detector.R"))
  la1 <- detect_lookahead(file.path(SCRIPT_DIR, "run_all.R"))
  la2 <- detect_lookahead(file.path(SCRIPT_DIR, "factor_engine.R"))
  if (!la1$clean || !la2$clean) stop("Lookahead violations -- aborting.")
  cat("[PIT] run_all.R + factor_engine.R: CLEAN\n")
}, error = function(e) {
  if (grepl("Lookahead", e$message)) stop(e$message)
  cat("[PIT]", e$message, "\n")
})

LIQ_THRESHOLD <- 2e8

# ── Phase 1: RAWDATA 1회 로드 ──
cat("\n[Phase 1] Loading RAWDATA (1회만 로드, use_cache=TRUE)...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
# backtest_harness.R이 Name/Sector 컬럼 사용 시 대비
if (!"Name"   %in% names(RAWDATA)) RAWDATA[, Name   := NA_character_]
if (!"Sector" %in% names(RAWDATA)) RAWDATA[, Sector := NA_character_]
setkey(RAWDATA, Ticker, Date)  # merge 가속 (원칙 2)
RAWDATA_ORIG <- copy(RAWDATA)
rm(res); gc(verbose = FALSE)
cat(sprintf("[Phase 1] RAWDATA: %s rows\n", format(nrow(RAWDATA), big.mark = ",")))

# ── Phase 2: Factor Engine — Q01_GPA + Q04_Piotroski_F bulk-load ──
cat("\n[Phase 2] Factor engine (bulk-load: Q01+Q04 only)...\n")
source(file.path(SCRIPT_DIR, "factor_engine.R"))
stopifnot(
  is.data.table(FACTORS),
  all(c("Date", "Ticker", "Score") %in% names(FACTORS)),
  nrow(FACTORS) > 0
)
cat(sprintf("[Phase 2] FACTORS ready: %s rows, %d months\n",
            format(nrow(FACTORS), big.mark = ","),
            uniqueN(FACTORS$Date)))

# ── Phase 3: 순수 팩터 백테스트 (N=20, EW, BZ 35/20, NO overlay) ──
cat("\n[Phase 3] Pure factor backtest (N=20, EW, 15bps, NO overlay)...\n")
RAWDATA <- copy(RAWDATA_ORIG)
sim <- run_monthly_simulation(
  RAWDATA       = RAWDATA,
  BM_DT         = BM_DT,
  FACTORS       = FACTORS,
  n_holdings    = 20L,
  weight_method = "equal",
  commission    = 0.0015,
  buffer_zone   = list(keep_n = 35L, entry_n = 20L)
)

# ── Phase 4: 성과 분석 + 차트 ──
cat("\n[Phase 4] Performance analysis + charts...\n")
output_dir <- file.path(SCRIPT_DIR, "output")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

perf_strat <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
perf_bm    <- summarise_perf(sim$bm_xts, "BM_KOSPI200")

cat(sprintf("  %s: CAGR=%.2f%% | SR=%.3f | MDD=%.1f%%\n",
            STRATEGY_ID, perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD))
cat(sprintf("  BM(KOSPI200): CAGR=%.2f%% | SR=%.3f | MDD=%.1f%%\n",
            perf_bm$CAGR, perf_bm$Sharpe, perf_bm$MDD))

generate_charts(sim, output_dir = output_dir, strategy_name = STRATEGY_NAME)
fwrite(rbind(perf_strat, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds"))
saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))

# ── Strategy Analyzer (부가 분석) ──
RAWDATA <- copy(RAWDATA_ORIG)
tryCatch({
  source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir, strategy_name = STRATEGY_ID)
}, error = function(e) cat("[WARN strategy_analyzer]", e$message, "\n"))

# ── Phase 5: Hurdle Gate ──
cat("\n[Phase 5] Hurdle gate evaluation...\n")
source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(
  sim_result    = sim,
  FACTORS       = FACTORS,
  strategy_name = STRATEGY_NAME,
  strategy_file = file.path(SCRIPT_DIR, "factor_engine.R"),
  output_dir    = output_dir
)
jsonlite::write_json(hurdle, file.path(output_dir, "hurdle_result.json"),
                     auto_unbox = TRUE, pretty = TRUE)

grade_val <- hurdle$grade %||% "N/A"
score_val <- hurdle$total_score %||% hurdle$score %||% 0
cat(sprintf("  Grade: %s | Score: %.1f\n", grade_val, score_val))

# ── 비교 참조 ──
cat("\n[Ref] 비교 기준 (S1 순수 팩터):\n")
cat(sprintf("  STR_1625 (C19+MAX, N=20)    : 기준 전략 (Core Alpha)\n"))
cat(sprintf("  STR_1626 (Q01+Q04, N=20, EW): CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
            perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD))
cat(sprintf("  Defense 역할 확인 필요 — 낮은 MDD + Bear 국면 방어력 우수 시 Grade 상향 가능\n"))

# ── Telegram ──
tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
  hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json"))
  tg_strategy_result_with_chart(STRATEGY_ID, hr, output_dir)
}, error = function(e) cat("[TG]", e$message, "\n"))

# ── QEPM Auto Commit ──
if (isTRUE(QEPM_AUTO_COMMIT)) tryCatch({
  qh <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "qepm", "scripts", "hybrid_mode.R")
  if (file.exists(qh)) {
    source(qh)
    if (exists("hybrid_commit"))
      hybrid_commit(
        strategy_name  = STRATEGY_ID,
        family         = STRATEGY_FAMILY,
        hurdle_result  = hurdle,
        artifact_paths = list(output_dir)
      )
  }
}, error = function(e) cat("[QEPM]", e$message, "\n"))

cat(sprintf("\n=== %s Complete. Grade=%s Score=%.1f ===\n",
            STRATEGY_ID, grade_val, score_val))
