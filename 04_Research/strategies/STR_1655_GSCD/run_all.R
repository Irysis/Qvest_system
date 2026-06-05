cat("=== STR_1655 GSCD: Growth-Stability Composite Diversifier ===\n")
## 핵심아이디어: GR02(이익성장) + Q07(이익안정성) + Q28(현금전환) z-score 합산
## Beta 하위 40% 유니버스 제한 (expanding window t-1 lag)
## Growth family 최초 전략화 (L-117: 0% 활용). Q07 양쪽 위기 통과 (L-121).
## 역할: Diversifier — 앵커 STR_1631(Consensus)과 독립 alpha source
## S1 순수 팩터 (overlay 없음), 격월 리밸런스, EW N=20, 15bps

t0 <- Sys.time()
set.seed(1655)
options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_NAME   <- "GSCD_Growth_Stability_Composite_Diversifier"
STRATEGY_ID     <- "STR_1655"
STRATEGY_FAMILY <- "growth_quality"
QEPM_AUTO_COMMIT <- TRUE

# ---- 경로 설정 (normalizePath 금지 — WSL 한글 경로 버그) ----
SCRIPT_DIR <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) getwd()
)
INFRA_DIR <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R"))) {
  INFRA_DIR <- file.path(
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
    "02_Infrastructure"
  )
}

source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(xts)
  library(zoo)
  library(PerformanceAnalytics)
  library(ggplot2)
  library(scales)
  library(lubridate)
  library(jsonlite)
})

output_dir <- file.path(SCRIPT_DIR, "output")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

LIQ_THRESHOLD <- 2e8

# ---- Preflight Check ----
tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", e$message, "\n"))

# ---- Lookahead Detector (C1~C15) ----
tryCatch({
  source(file.path(VALIDATION_DIR, "lookahead_detector.R"))
  la1 <- detect_lookahead(file.path(SCRIPT_DIR, "run_all.R"))
  la2 <- detect_lookahead(file.path(SCRIPT_DIR, "factor_engine.R"))
  if (!la1$clean || !la2$clean) stop("Lookahead violations — aborting.")
  cat("[PIT] CLEAN\n")
}, error = function(e) {
  if (grepl("Lookahead", e$message)) stop(e$message)
  cat("[PIT]", e$message, "\n")
})

# ══════════════════════════════════════════════════════════
# Phase 1: RAWDATA 로드 (1회, use_cache=TRUE)
# ══════════════════════════════════════════════════════════
cat("\n[Phase 1] RAWDATA 로드...\n")
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)

# 분석 기간: 2003-01-01 이후 (Q07 5Y rolling warm-up 확보)
ANALYSIS_START_DATE <- as.Date("2003-01-01")
SIGNAL_START_DATE   <- as.Date("2004-01-01")   # 1년 추가 warm-up

RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]
BM_DT   <- BM_DT[Date   >= ANALYSIS_START_DATE]
RAWDATA_ORIG <- copy(RAWDATA)

setkey(RAWDATA, Date, Ticker)
cat(sprintf("  RAWDATA: %s ~ %s | %s rows\n",
            min(RAWDATA$Date), max(RAWDATA$Date),
            format(nrow(RAWDATA), big.mark = ",")))

# ══════════════════════════════════════════════════════════
# Phase 2: Factor Engine (GR02 + Q07 + Q28, Beta 40%)
# ══════════════════════════════════════════════════════════
cat("\n[Phase 2] Factor engine 실행...\n")
RAWDATA <- copy(RAWDATA_ORIG)
source(file.path(SCRIPT_DIR, "factor_engine.R"))

stopifnot(
  is.data.table(FACTORS),
  all(c("Date", "Ticker", "Score") %in% names(FACTORS)),
  nrow(FACTORS) > 0
)
cat(sprintf("  FACTORS: %d dates, %s rows\n",
            uniqueN(FACTORS$Date),
            format(nrow(FACTORS), big.mark = ",")))

# ══════════════════════════════════════════════════════════
# Phase 3: 백테스트 (EW N=20, 15bps, BZ 35/20, 격월)
# ══════════════════════════════════════════════════════════
cat("\n[Phase 3] Backtest — S1 순수 팩터 (overlay 없음)...\n")
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

# ══════════════════════════════════════════════════════════
# Phase 4: 성과 요약
# ══════════════════════════════════════════════════════════
cat("\n[Phase 4] 성과 요약...\n")
perf_strat <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
perf_bm    <- summarise_perf(sim$bm_xts, "KOSPI200")

cat(sprintf("  %s: CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
            STRATEGY_ID,
            perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD))
cat(sprintf("  BM: CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
            perf_bm$CAGR, perf_bm$Sharpe, perf_bm$MDD))

generate_charts(sim, output_dir = output_dir, strategy_name = STRATEGY_NAME)
fwrite(rbind(perf_strat, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds"))
saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))

# ══════════════════════════════════════════════════════════
# Phase 5: Strategy Analyzer
# ══════════════════════════════════════════════════════════
RAWDATA <- copy(RAWDATA_ORIG)
tryCatch({
  source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir, strategy_name = STRATEGY_ID)
}, error = function(e) cat("[WARN analyzer]", e$message, "\n"))

# ══════════════════════════════════════════════════════════
# Phase 6: Hurdle Gate
# ══════════════════════════════════════════════════════════
cat("\n[Phase 6] Hurdle gate...\n")
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
  auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("  Grade: %s | Score: %.1f\n",
            hurdle$grade,
            hurdle$total_score %||% hurdle$score %||% 0))

# ══════════════════════════════════════════════════════════
# Phase 7: Diversifier 분석 (Beta + 8대 스트레스 + 앵커 상관)
# ══════════════════════════════════════════════════════════
cat("\n[Phase 7] Diversifier 분석...\n")

tryCatch({
  strat_ret  <- as.numeric(coredata(sim$strategy_xts))
  bm_ret_v   <- as.numeric(coredata(sim$bm_xts))
  dates_v    <- as.Date(index(sim$strategy_xts))
  valid_idx  <- !is.na(strat_ret) & !is.na(bm_ret_v)

  # --- 포트폴리오 베타 ---
  if (sum(valid_idx) >= 60L) {
    bv <- bm_ret_v[valid_idx]; sv <- strat_ret[valid_idx]
    port_beta <- cov(sv, bv) / var(bv)
    cat(sprintf("  [Beta] 전체기간: %.3f", port_beta))
    cutoff_3y <- max(dates_v) - 365 * 3
    idx_3y    <- valid_idx & dates_v >= cutoff_3y
    if (sum(idx_3y) >= 30L) {
      b3y <- cov(strat_ret[idx_3y], bm_ret_v[idx_3y]) / var(bm_ret_v[idx_3y])
      cat(sprintf(" | 최근 3Y: %.3f", b3y))
    }
    cat("\n")
  }

  # --- 8대 스트레스 구간 (OPT-5 정본: 6개 필수 날짜 포함) ---
  stress_periods <- list(
    list(name = "9/11 테러",              start = "2001-09-01", end = "2001-12-31"),
    list(name = "글로벌 금융위기(GFC)",   start = "2007-10-01", end = "2009-03-31"),
    list(name = "유럽 재정위기",           start = "2011-07-01", end = "2012-06-30"),
    list(name = "중국쇼크/원자재 하락",   start = "2015-07-01", end = "2016-02-29"),
    list(name = "미중 무역전쟁",           start = "2018-03-01", end = "2019-01-31"),
    list(name = "코로나 충격",             start = "2020-01-01", end = "2020-06-30"),
    list(name = "금리인상 사이클",         start = "2022-01-01", end = "2022-12-31"),
    list(name = "이란전쟁/지정학 쇼크",   start = "2026-02-01", end = "2026-04-09")
  )

  cat("\n  [Stress] 8대 구간 (총수익률, 연환산 금지):\n")
  stress_results <- lapply(stress_periods, function(sp) {
    s   <- as.Date(sp$start); e <- as.Date(sp$end)
    idx <- dates_v >= s & dates_v <= e & valid_idx
    if (sum(idx) < 3L) {
      cat(sprintf("    %-32s: 데이터 부족\n", sp$name))
      return(list(name = sp$name, n = 0L,
                  strat_ret = NA_real_, bm_ret = NA_real_, alpha = NA_real_))
    }
    sr_cum <- prod(1 + strat_ret[idx]) - 1   # 총수익률 (연환산 금지)
    bm_cum <- prod(1 + bm_ret_v[idx])  - 1
    alpha  <- sr_cum - bm_cum
    cat(sprintf("    %-32s: 전략=%+.1f%% BM=%+.1f%% Alpha=%+.1f%%\n",
                sp$name, sr_cum * 100, bm_cum * 100, alpha * 100))
    list(name = sp$name, n = sum(idx),
         strat_ret = round(sr_cum, 4), bm_ret = round(bm_cum, 4),
         alpha = round(alpha, 4))
  })
  saveRDS(stress_results, file.path(output_dir, "stress_analysis.rds"))

  # --- 앵커 STR_1631 상관 ---
  anchor_path <- file.path(SCRIPT_DIR, "..", "STR_1631", "sim_result.rds")
  if (file.exists(anchor_path)) {
    sim_anchor <- readRDS(anchor_path)
    anchor_xts <- sim_anchor$strategy_xts
    merged_cor  <- merge(sim$strategy_xts, anchor_xts, join = "inner")
    if (nrow(merged_cor) >= 60L) {
      r_strat  <- as.numeric(merged_cor[, 1])
      r_anchor <- as.numeric(merged_cor[, 2])
      full_cor <- cor(r_strat, r_anchor, use = "complete.obs")
      cat(sprintf("\n  [Anchor Corr] STR_1631 vs GSCD: rho=%.3f (전체기간)\n", full_cor))

      # 위기 구간 상관
      dates_m <- as.Date(index(merged_cor))
      crisis_idx <- (dates_m >= as.Date("2007-10-01") & dates_m <= as.Date("2009-03-31")) |
                    (dates_m >= as.Date("2020-01-01") & dates_m <= as.Date("2020-06-30")) |
                    (dates_m >= as.Date("2022-01-01") & dates_m <= as.Date("2022-12-31"))
      if (sum(crisis_idx) >= 30L) {
        crisis_cor <- cor(r_strat[crisis_idx], r_anchor[crisis_idx], use = "complete.obs")
        cat(sprintf("  [Anchor Corr] 위기 구간: rho=%.3f\n", crisis_cor))
      }
      saveRDS(list(full_cor = full_cor), file.path(output_dir, "anchor_correlation.rds"))
    }
  } else {
    cat("  [Anchor Corr] STR_1631 sim_result.rds 미발견 — 생략\n")
  }

  # --- STR_1650(C19) 단독 비교 ---
  c19_path <- file.path(SCRIPT_DIR, "..", "STR_1650_C19_AC21_CR05_blend", "sim_result.rds")
  if (file.exists(c19_path)) {
    sim_c19   <- readRDS(c19_path)
    merged_c19 <- merge(sim$strategy_xts, sim_c19$strategy_xts, join = "inner")
    if (nrow(merged_c19) >= 60L) {
      r_c19_cor <- cor(as.numeric(merged_c19[, 1]),
                       as.numeric(merged_c19[, 2]), use = "complete.obs")
      cat(sprintf("  [C19 Corr] STR_1650 vs GSCD: rho=%.3f\n", r_c19_cor))
    }
  }

}, error = function(e) cat("[WARN Phase7]", e$message, "\n"))

# ══════════════════════════════════════════════════════════
# Phase 8: 성과 JSON 저장
# ══════════════════════════════════════════════════════════
perf_json <- list(
  strategy_id   = STRATEGY_ID,
  strategy_name = STRATEGY_NAME,
  stage         = "S1",
  role          = "Diversifier",
  role_bias     = "RoleBias_Diversifier",
  factors       = c("GR02_Earnings_Growth", "Q07_Earnings_Stability", "Q28_Cash_Conversion"),
  construction  = list(
    universe    = "LIQ >= 2e8, Beta 하위 40% (expanding, t-1)",
    scoring     = "Z_Score_Aligned 합산 (C13)",
    selection   = "Top 20 EW",
    rebalance   = "Bimonthly",
    commission  = "15bps",
    overlay     = "NONE (S1)"
  ),
  performance   = as.list(perf_strat),
  benchmark     = as.list(perf_bm),
  hurdle        = list(
    grade       = hurdle$grade,
    score       = hurdle$total_score %||% hurdle$score %||% 0
  ),
  run_date      = format(Sys.Date()),
  elapsed_sec   = as.numeric(difftime(Sys.time(), t0, units = "secs"))
)
jsonlite::write_json(perf_json,
  file.path(output_dir, "performance.json"),
  auto_unbox = TRUE, pretty = TRUE)

elapsed <- difftime(Sys.time(), t0, units = "secs")
cat(sprintf("\n[run_all] STR_1655 완료: %.1f초\n", as.numeric(elapsed)))
cat("=== END STR_1655 ===\n")
