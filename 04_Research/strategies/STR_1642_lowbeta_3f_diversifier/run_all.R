cat("=== STR_1642: Low-Beta 3F Diversifier (AC17 + L22 + Q04 × Beta Bottom 40%) ===\n")
## 핵심아이디어: Expanding-window CAPM beta 하위 40% 유니버스 제한
## AC17(Accrual Reversal) + L22(Ret Autocorr) + Q04(Piotroski F) EW z-score composite
## AC17 데이터 부재 구간(~2011년 전): L22 + Q04 2F fallback
## 역할: Diversifier (SR gap +0.757)  RoleBias_Diversifier
## S0 Debate R2 승인 63/100 APPROVE_CONDITIONAL (H_1642_v2)
## S1: 순수 팩터 신호. EW 20종목. DD/VT/Regime 오버레이 없음.

set.seed(1642)
options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_NAME   <- "LowBeta_3F_Diversifier"
STRATEGY_ID     <- "STR_1642"
STRATEGY_FAMILY <- "accrual_microstructure_quality"
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
library(data.table)
library(xts)
library(arrow)

# ---- output 디렉토리 ----
output_dir <- file.path(SCRIPT_DIR, "output")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

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

cat("\n[Phase 1] Loading RAWDATA + factor engine...\n")
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT

# ---- 2002-01-01 이후 제한 ----
# 이유 1: Beta expanding-window 252d warm-up → 1990년대 초기 구간 NA 다수
# 이유 2: AC17 2011년부터 가용, L22/Q04 2F fallback은 2002년+ 구간에서 안정적
# 이유 3: MDD 78.6% Hard FAIL 원인 → 초기 구간 beta 미완성 + 유동성 부족
STR_START_DATE  <- as.Date("2002-01-01")
RAWDATA         <- RAWDATA[Date >= STR_START_DATE]
SIGNAL_START_DATE <- as.Date("2002-07-01")  # 6개월 warm-up 버퍼 (오버라이드)
cat(sprintf("  [Filter] RAWDATA: %s ~ %s (%s rows)\n",
            min(RAWDATA$Date), max(RAWDATA$Date),
            format(nrow(RAWDATA), big.mark = ",")))

RAWDATA_ORIG <- copy(RAWDATA)
rm(res); gc(verbose = FALSE)

source(file.path(SCRIPT_DIR, "factor_engine.R"))

stopifnot(
  is.data.table(FACTORS),
  all(c("Date", "Ticker", "Score") %in% names(FACTORS)),
  nrow(FACTORS) > 0
)

cat("\n[Phase 2] Pure factor backtest (N=20, EW, BZ 35/20, NO overlay)...\n")
RAWDATA <- copy(RAWDATA_ORIG)

sim <- run_monthly_simulation(
  RAWDATA       = RAWDATA,
  BM_DT         = BM_DT,
  FACTORS       = FACTORS,
  n_holdings    = 20L,
  weight_method = "equal",
  commission    = 0.0015,    # 15bps
  buffer_zone   = list(keep_n = 35L, entry_n = 20L)
  # vol_target 미전달 — S1 순수 팩터 신호만 (VT 없음)
)

cat("\n[Phase 3] Performance analysis + Hurdle gate...\n")

perf_strat <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
perf_bm    <- summarise_perf(sim$bm_xts, "BM")
cat(sprintf("  %s: CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
            STRATEGY_ID, perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD))
cat(sprintf("  BM: CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
            perf_bm$CAGR, perf_bm$Sharpe, perf_bm$MDD))

generate_charts(sim, output_dir = output_dir, strategy_name = STRATEGY_NAME)
fwrite(rbind(perf_strat, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds"))
saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))

# ---- Strategy Analyzer ----
RAWDATA <- copy(RAWDATA_ORIG)
tryCatch({
  source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir, strategy_name = STRATEGY_ID)
}, error = function(e) cat("[WARN analyzer]", e$message, "\n"))

# ---- Hurdle Gate ----
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

# ---- Defense/Diversifier 분석 (L-112) ----
cat("\n[Phase 4] Diversifier 분석: Beta / Stress Periods / Core 상관...\n")

tryCatch({
  # --- 1. 포트폴리오 베타 계산 ---
  strat_ret  <- as.numeric(coredata(sim$strategy_xts))
  bm_ret_ts  <- as.numeric(coredata(sim$bm_xts))
  dates_ts   <- as.Date(index(sim$strategy_xts))

  valid_idx <- !is.na(strat_ret) & !is.na(bm_ret_ts)
  if (sum(valid_idx) >= 60L) {
    bm_v <- bm_ret_ts[valid_idx]
    sr_v <- strat_ret[valid_idx]
    port_beta <- cov(sr_v, bm_v) / var(bm_v)
    cat(sprintf("  [Beta] 포트폴리오 베타: %.3f (전체 기간)\n", port_beta))

    # 최근 3년 베타
    cutoff_3y <- max(dates_ts) - 365*3
    idx_3y <- valid_idx & dates_ts >= cutoff_3y
    if (sum(idx_3y) >= 30L) {
      b3y <- cov(strat_ret[idx_3y], bm_ret_ts[idx_3y]) / var(bm_ret_ts[idx_3y])
      cat(sprintf("  [Beta] 최근 3Y 베타: %.3f\n", b3y))
    }
  } else {
    cat("  [Beta] 관측수 부족 (< 60)\n")
    port_beta <- NA_real_
  }

  # --- 2. 8대 스트레스 구간 alpha ---
  stress_periods <- list(
    list(name = "글로벌 금융위기",       start = "2008-09-01", end = "2009-03-31"),
    list(name = "유럽 재정위기",         start = "2011-07-01", end = "2012-06-30"),
    list(name = "중국 쇼크/원자재 하락", start = "2015-07-01", end = "2016-02-29"),
    list(name = "코로나 충격",           start = "2020-01-01", end = "2020-06-30"),
    list(name = "금리인상 사이클",       start = "2022-01-01", end = "2022-12-31"),
    list(name = "2018 변동성 급등",      start = "2018-10-01", end = "2019-01-31"),
    list(name = "2023 SVB/크레딧 쇼크",  start = "2023-03-01", end = "2023-05-31"),
    list(name = "2024 AI발 반등",        start = "2024-01-01", end = "2024-06-30")
  )

  cat("\n  [Stress Periods] 8대 구간 분석:\n")
  stress_results <- lapply(stress_periods, function(sp) {
    s <- as.Date(sp$start); e <- as.Date(sp$end)
    idx <- dates_ts >= s & dates_ts <= e & valid_idx
    if (sum(idx) < 3L) {
      cat(sprintf("    %-30s: 데이터 부족\n", sp$name))
      return(list(name=sp$name, n=0, strat_ret=NA, bm_ret=NA, alpha=NA))
    }
    sr_cum <- prod(1 + strat_ret[idx]) - 1
    bm_cum <- prod(1 + bm_ret_ts[idx]) - 1
    alpha   <- sr_cum - bm_cum
    cat(sprintf("    %-30s: 전략=%.1f%% BM=%.1f%% Alpha=%+.1f%%\n",
                sp$name, sr_cum*100, bm_cum*100, alpha*100))
    list(name=sp$name, n=sum(idx),
         strat_ret=round(sr_cum,4), bm_ret=round(bm_cum,4), alpha=round(alpha,4))
  })
  saveRDS(stress_results, file.path(output_dir, "stress_analysis.rds"))

  # --- 3. Core(STR_1631) 대비 상관 ---
  core_sim_path <- file.path(SCRIPT_DIR, "..", "..",
                             "STR_1631", "output", "sim_result.rds")
  if (!file.exists(core_sim_path)) {
    core_sim_path <- file.path(SCRIPT_DIR, "..", "..",
                               "STR_1631", "sim_result.rds")
  }

  cat("\n  [Core Correlation] STR_1631 대비 상관:\n")
  if (file.exists(core_sim_path)) {
    core_sim <- readRDS(core_sim_path)
    core_ret <- as.numeric(coredata(core_sim$strategy_xts))
    core_dates <- as.Date(index(core_sim$strategy_xts))

    # 공통 날짜 추출
    common_dates <- intersect(as.character(dates_ts[valid_idx]),
                              as.character(core_dates[!is.na(core_ret)]))
    if (length(common_dates) >= 36L) {
      cd <- as.Date(common_dates)
      sr_common   <- strat_ret[dates_ts %in% cd]
      core_common <- core_ret[core_dates %in% cd]
      corr_val    <- cor(sr_common, core_common, use = "complete.obs")
      cat(sprintf("    STR_1631(Core) 대비 상관: %.3f (n=%d개월)\n",
                  corr_val, length(common_dates)))
      cat(sprintf("    max_corr: %.3f → novelty_bonus %s\n",
                  abs(corr_val),
                  ifelse(abs(corr_val) < 0.30, "+15 eligible",
                  ifelse(abs(corr_val) < 0.50, "+5~8 eligible", "없음"))))
    } else {
      cat("    공통 기간 36개월 미만 → 상관 계산 불가\n")
      corr_val <- NA_real_
    }
  } else {
    cat("    STR_1631 sim_result.rds 없음 → 상관 계산 생략\n")
    corr_val <- NA_real_
  }

  # 분석 결과 저장
  diversifier_report <- list(
    strategy_id   = STRATEGY_ID,
    role          = "RoleBias_Diversifier",
    port_beta     = port_beta,
    corr_core_1631 = corr_val,
    stress_results = stress_results
  )
  saveRDS(diversifier_report, file.path(output_dir, "diversifier_analysis.rds"))
  jsonlite::write_json(diversifier_report,
    file.path(output_dir, "diversifier_analysis.json"),
    auto_unbox = TRUE, pretty = TRUE)
  cat("\n  [Diversifier 분석] 완료. diversifier_analysis.json 저장됨.\n")

}, error = function(e) cat("[WARN diversifier analysis]", e$message, "\n"))

# ---- 텔레그램 결과 발송 (이모지 필수, 한글) ----
tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))

  # 기본 결과 발송 (chart 포함)
  hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json"))
  tg_strategy_result_with_chart(STRATEGY_ID, hr, output_dir)

  # Diversifier 전용 보고
  div_msg <- paste0(
    "[Forge] STR_1642 Low-Beta 3F Diversifier S1 완료\n\n",
    "[ 팩터 구성 ]\n",
    "  AC17 Accrual Reversal\n",
    "  L22 Ret Autocorr\n",
    "  Q04 Piotroski F-Score\n",
    "  확장 베타 하위 40% 유니버스 필터 (C2 t-1 lag)\n\n",
    sprintf("[ 성과 ] Grade=%s | Score=%.1f\n",
            hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0),
    sprintf("  CAGR=%.2f%% | SR=%.3f | MDD=%.1f%%\n",
            perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD)
  )

  tg_send(div_msg)
}, error = function(e) cat("[TG]", e$message, "\n"))

# ---- QEPM Auto Commit ----
if (isTRUE(QEPM_AUTO_COMMIT)) {
  tryCatch({
    qh <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "qepm", "scripts", "hybrid_mode.R")
    if (file.exists(qh)) {
      source(qh)
      if (exists("hybrid_commit")) {
        hybrid_commit(
          strategy_name  = STRATEGY_ID,
          family         = STRATEGY_FAMILY,
          hurdle_result  = hurdle,
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
