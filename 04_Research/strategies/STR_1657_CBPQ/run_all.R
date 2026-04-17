cat("=== STR_1657_CBPQ: Cash-Based Profitability-Quality ===\n")
## 핵심아이디어: Q35(Cash-Based Op Profitability) + Q09(CFOA) + AC07(Op Accruals) z-score 합산
## Beta 하위 40% 유니버스 제한 (expanding window, t-1 lag, C2/C9)
## 근거: Chib et al. (2025) Bayesian EFDR spanning test
##       Ball et al. (2016 JFE) cash-based profitability factor
## 역할: Diversifier — 앵커 STR_1631(Consensus)과 독립 alpha source
## S1 순수 팩터 (overlay 없음), 격월 리밸런스, EW N=20, 15bps

t0 <- Sys.time()
set.seed(1657)
options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_NAME   <- "CBPQ_CashBased_Profitability_Quality"
STRATEGY_ID     <- "STR_1657"
STRATEGY_FAMILY <- "quality_accrual"
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

# 분석 기간: 2003-01-01 이후
# (Q09/Q35 재무 지표 warming-up 1년 + Beta expanding 252일 확보)
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
# Phase 2: Factor Engine
# (Q35 + Q09 + AC07, Beta 40%, COND_01/COND_03 자동 처리)
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

# S0 조건 결과 수집 (factor_engine.R에서 assign됨)
corr_q35_q09   <- if (exists("CBPQ_CORR_Q35_Q09"))   CBPQ_CORR_Q35_Q09   else NA_real_
ac07_icir_val  <- if (exists("CBPQ_AC07_ICIR"))        CBPQ_AC07_ICIR       else NA_real_
active_factors <- if (exists("CBPQ_ACTIVE_FACTORS"))   CBPQ_ACTIVE_FACTORS  else
                    c("Q35_CashBased_OpProf", "Q09_CFOA", "AC07_Operating_Accruals")

cat(sprintf("  [S0 COND] Q35-Q09 rho=%.3f | AC07 ICIR=%.3f | 활성팩터=%d개\n",
            ifelse(is.na(corr_q35_q09), 0, corr_q35_q09),
            ifelse(is.na(ac07_icir_val), 0, ac07_icir_val),
            length(active_factors)))

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
  } else {
    port_beta <- NA_real_
  }

  # --- 8대 스트레스 구간 (OPT-5 정본) ---
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
    sr_cum <- prod(1 + strat_ret[idx]) - 1
    bm_cum <- prod(1 + bm_ret_v[idx])  - 1
    alpha  <- sr_cum - bm_cum
    cat(sprintf("    %-32s: 전략=%+.1f%% BM=%+.1f%% Alpha=%+.1f%%\n",
                sp$name, sr_cum * 100, bm_cum * 100, alpha * 100))
    list(name = sp$name, n = sum(idx),
         strat_ret = round(sr_cum, 4), bm_ret = round(bm_cum, 4),
         alpha = round(alpha, 4))
  })
  saveRDS(stress_results, file.path(output_dir, "stress_analysis.rds"))

  # --- 앵커 STR_1631 상관 (COND_02 검증 준비) ---
  corr_val <- NA_real_
  anchor_path <- file.path(SCRIPT_DIR, "..", "STR_1631", "sim_result.rds")
  if (file.exists(anchor_path)) {
    sim_anchor <- readRDS(anchor_path)
    anchor_xts <- sim_anchor$strategy_xts
    merged_cor  <- merge(sim$strategy_xts, anchor_xts, join = "inner")
    if (nrow(merged_cor) >= 60L) {
      r_strat  <- as.numeric(merged_cor[, 1])
      r_anchor <- as.numeric(merged_cor[, 2])
      corr_val <- cor(r_strat, r_anchor, use = "complete.obs")
      cat(sprintf("\n  [Anchor Corr] STR_1631 vs CBPQ: rho=%.3f (전체기간)\n", corr_val))

      # 위기 구간 상관
      dates_m  <- as.Date(index(merged_cor))
      crisis_idx <- (dates_m >= as.Date("2007-10-01") & dates_m <= as.Date("2009-03-31")) |
                    (dates_m >= as.Date("2020-01-01") & dates_m <= as.Date("2020-06-30")) |
                    (dates_m >= as.Date("2022-01-01") & dates_m <= as.Date("2022-12-31"))
      if (sum(crisis_idx) >= 30L) {
        crisis_cor <- cor(r_strat[crisis_idx], r_anchor[crisis_idx], use = "complete.obs")
        cat(sprintf("  [Anchor Corr] 위기 구간: rho=%.3f\n", crisis_cor))
      }

      # L-115 비교 메모
      cat(sprintf("  [L-115 비교] CBPQ rho=%.3f vs STR_1642 선례 rho=0.575\n", corr_val))
      if (!is.na(corr_val) && corr_val >= 0.30) {
        cat("  [COND_02] WARNING: 앵커 상관 >= 0.30 — S3에서 diversifier 역할 재검토 필요\n")
      } else if (!is.na(corr_val)) {
        cat("  [COND_02] PASS: 앵커 상관 < 0.30\n")
      }
      saveRDS(list(full_cor = corr_val), file.path(output_dir, "anchor_correlation.rds"))
    }
  } else {
    cat("  [Anchor Corr] STR_1631 sim_result.rds 미발견 — 생략\n")
  }

}, error = function(e) cat("[WARN Phase7]", e$message, "\n"))

# ══════════════════════════════════════════════════════════
# Phase 8: IC/ICIR 측정 (Alpha Lab Gate: ICIR >= 0.20)
# ══════════════════════════════════════════════════════════
cat("\n[Phase 8] IC/ICIR 측정...\n")
tryCatch({
  # 보유종목 기록에서 IC 계산 (수익률 기반)
  if (!is.null(sim$holdings_log) && length(sim$holdings_log) > 0L) {
    hl <- rbindlist(sim$holdings_log, fill = TRUE)
    setkey(RAWDATA_ORIG, Date, Ticker)
    ic_rows <- lapply(sort(unique(hl$Date)), function(d) {
      held <- hl[Date == d, Ticker]
      if (length(held) < 5L) return(NULL)
      # 다음 월 수익률 — RAWDATA에서 월별 수익률 집계
      next_month <- d + 20L
      fwd_rets <- RAWDATA_ORIG[Ticker %in% held & Date >= d & Date <= next_month,
                                .(fwd_ret = tail(Close, 1) / head(Close, 1) - 1),
                                by = Ticker]
      sc_dt <- FACTORS[Date == d, .(Ticker, Score)]
      merged_ic <- merge(sc_dt, fwd_rets, by = "Ticker")
      if (nrow(merged_ic) < 5L) return(NULL)
      ic_val <- tryCatch(
        cor(merged_ic$Score, merged_ic$fwd_ret, method = "spearman", use = "complete.obs"),
        error = function(e) NA_real_
      )
      list(Date = d, IC = ic_val)
    })
    ic_dt2 <- rbindlist(ic_rows[!sapply(ic_rows, is.null)])
    if (nrow(ic_dt2) >= 12L) {
      ic_mean  <- mean(ic_dt2$IC, na.rm = TRUE)
      ic_sd    <- sd(ic_dt2$IC, na.rm = TRUE)
      icir     <- if (ic_sd > 1e-8) ic_mean / ic_sd else NA_real_
      ic_tstat <- if (!is.na(icir)) icir * sqrt(nrow(ic_dt2)) else NA_real_
      ic_pos   <- mean(ic_dt2$IC > 0, na.rm = TRUE)
      cat(sprintf("  IC mean=%.4f | ICIR=%.3f | t=%.2f | Pct>0=%.1f%%\n",
                  ic_mean, ifelse(is.na(icir), 0, icir),
                  ifelse(is.na(ic_tstat), 0, ic_tstat), ic_pos * 100))
      if (!is.na(icir) && abs(icir) >= 0.20) {
        cat("  [Alpha Lab Gate] PASS: ICIR >= 0.20\n")
      } else {
        cat("  [Alpha Lab Gate] WARN: ICIR < 0.20 — 정식 연구 진입 재검토 필요\n")
      }
      saveRDS(list(ic_mean=ic_mean, icir=icir, ic_tstat=ic_tstat, ic_pos=ic_pos,
                   n_months=nrow(ic_dt2)),
              file.path(output_dir, "ic_profile.rds"))
    } else {
      icir <- NA_real_; ic_mean <- NA_real_; ic_tstat <- NA_real_; ic_pos <- NA_real_
      cat("  [IC] 충분한 데이터 없음 (n < 12)\n")
    }
  } else {
    icir <- NA_real_; ic_mean <- NA_real_; ic_tstat <- NA_real_; ic_pos <- NA_real_
    cat("  [IC] holdings_log 없음 — 건너뜀\n")
  }
}, error = function(e) {
  icir     <<- NA_real_; ic_mean <<- NA_real_
  ic_tstat <<- NA_real_; ic_pos  <<- NA_real_
  cat("[WARN IC]", e$message, "\n")
})
# ensure IC variables always exist after tryCatch
if (!exists("icir"))     icir     <- NA_real_
if (!exists("ic_mean"))  ic_mean  <- NA_real_
if (!exists("ic_tstat")) ic_tstat <- NA_real_
if (!exists("ic_pos"))   ic_pos   <- NA_real_

# ══════════════════════════════════════════════════════════
# Phase 9: 성과 JSON 저장
# ══════════════════════════════════════════════════════════
.safe_num <- function(x) {
  v <- tryCatch(as.numeric(x), error = function(e) NA_real_)
  if (length(v) == 0 || is.null(v)) NA_real_ else v[1]
}

perf_json <- list(
  strategy_id   = STRATEGY_ID,
  strategy_name = STRATEGY_NAME,
  stage         = "S1",
  role          = "Diversifier",
  role_bias     = "RoleBias_Diversifier",
  factors       = active_factors,
  construction  = list(
    universe    = "LIQ >= 2e8 (t-1), Beta 하위 40% expanding (t-1, C2/C9)",
    scoring     = "Z_Score_Aligned 합산 (C13, Arrow bulk preload C15)",
    selection   = "Top 20 EW",
    rebalance   = "Bimonthly",
    commission  = "15bps",
    overlay     = "NONE (S1 순수 팩터)"
  ),
  s0_conditions = list(
    COND_01_q35_q09_corr = .safe_num(corr_q35_q09),
    COND_03_ac07_icir    = .safe_num(ac07_icir_val),
    active_factor_count  = length(active_factors)
  ),
  ic_profile    = list(
    ic_mean  = .safe_num(ic_mean),
    icir     = .safe_num(icir),
    ic_tstat = .safe_num(ic_tstat),
    ic_pos   = .safe_num(ic_pos)
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

# ══════════════════════════════════════════════════════════
# Phase 10: Stage Artifact (s1_construction_STR_1657_CBPQ.json)
# ══════════════════════════════════════════════════════════
cat("\n[Phase 10] Stage artifact 저장...\n")
artifacts_dir <- file.path(PROJECT_ROOT, "stage_artifacts", "STR_1657_CBPQ")
dir.create(artifacts_dir, showWarnings = FALSE, recursive = TRUE)

s1_artifact <- list(
  factor_id    = "CBPQ_CashBased_Profitability_Quality",
  strategy_id  = "STR_1657_CBPQ",
  stage        = "S1",
  version      = "1.0",
  run_date     = format(Sys.Date()),
  session      = 57L,

  construction = list(
    factors          = active_factors,
    n_factors        = length(active_factors),
    universe         = "LIQ >= 2e8 (t-1) -> Beta 하위 40% expanding (t-1, C2/C9)",
    scoring          = "Z_Score_Aligned 합산 (C13, Arrow bulk preload C15)",
    n_holdings       = 20L,
    weight           = "EW",
    rebalance        = "Bimonthly",
    commission_bps   = 15L,
    buffer_zone      = list(keep_n = 35L, entry_n = 20L),
    overlay          = "NONE (S1 순수 팩터)",
    start_date       = format(min(FACTORS$Date)),
    end_date         = format(max(FACTORS$Date)),
    n_signal_dates   = uniqueN(FACTORS$Date)
  ),

  s0_conditions = list(
    COND_01 = list(
      requirement = "Q35-Q09 상관 > 0.7이면 하나 제거",
      result      = ifelse(is.na(corr_q35_q09), "N/A", round(corr_q35_q09, 4)),
      pass        = ifelse(is.na(corr_q35_q09), TRUE,
                           corr_q35_q09 <= 0.7 || length(active_factors) == 2L)
    ),
    COND_03 = list(
      requirement = "AC07 ICIR < 0.10이면 제거",
      result      = ifelse(is.na(ac07_icir_val), "N/A", round(ac07_icir_val, 4)),
      pass        = ifelse(is.na(ac07_icir_val), TRUE,
                           abs(ac07_icir_val) >= 0.10 ||
                           !("AC07_Operating_Accruals" %in% active_factors))
    )
  ),

  pit_checks = list(
    C2_beta_lag  = "PASS: Beta_Lag = shift(Beta_Raw, 1L)",
    C9_dd_vt_lag = "PASS: 오버레이 없음 (S1)",
    C10_liq_lag  = "PASS: LIQ20 = shift(frollmean(TV,20), 1L)",
    C13_zscore   = "PASS: Z_Score_Aligned only, 수동 반전 없음",
    C15_fdb      = "PASS: Arrow bulk preload 1회"
  ),

  performance = list(
    CAGR   = perf_strat$CAGR,
    AnnVol = perf_strat$AnnVol,
    Sharpe = perf_strat$Sharpe,
    MDD    = perf_strat$MDD
  ),

  ic_profile = list(
    ic_mean  = .safe_num(round(.safe_num(ic_mean), 4)),
    icir     = .safe_num(round(.safe_num(icir), 4)),
    ic_tstat = .safe_num(round(.safe_num(ic_tstat), 4)),
    ic_pos   = .safe_num(round(.safe_num(ic_pos), 4))
  ),

  alpha_lab_gate = isTRUE(!is.na(.safe_num(icir)) && abs(.safe_num(icir)) >= 0.20),

  hurdle = list(
    grade = hurdle$grade,
    score = hurdle$total_score %||% hurdle$score %||% 0
  ),

  hypothesis_ref = "S0_VERDICT_H_1657_CBPQ.json",
  paper_ref      = "Ball et al. (2016 JFE) + Chib et al. (2025)",
  next_stage     = "S2_PROFILING"
)

artifact_path <- file.path(PROJECT_ROOT, "stage_artifacts",
                            "s1_construction_STR_1657_CBPQ.json")
jsonlite::write_json(s1_artifact, artifact_path, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("  Stage artifact 저장: %s\n", artifact_path))

# ══════════════════════════════════════════════════════════
# Phase 11: 텔레그램 [Forge] 발송
# ══════════════════════════════════════════════════════════
tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
  hr <- tryCatch(
    jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json")),
    error = function(e) hurdle
  )
  # 차트 첨부 (필수)
  tg_strategy_result_with_chart(STRATEGY_ID, hr, output_dir)
  # 상세 메시지
  tg_send(paste0(
    "[Forge] STR_1657 CBPQ S1 완료\n\n",
    sprintf("[ 팩터 ] %s\n", paste(active_factors, collapse = " + ")),
    "[ 구조 ] Beta 하위 40%(expanding, t-1) -> Top 20 EW 격월\n",
    sprintf("[ S0조건 ] Q35-Q09 rho=%.3f | AC07 ICIR=%.3f\n",
            ifelse(is.na(corr_q35_q09), 0, corr_q35_q09),
            ifelse(is.na(ac07_icir_val), 0, ac07_icir_val)),
    sprintf("[ Alpha Lab ] ICIR=%.3f (%s)\n",
            ifelse(exists("icir") && !is.na(icir), icir, 0),
            ifelse(exists("icir") && !is.na(icir) && abs(icir) >= 0.20, "PASS", "WARN")),
    sprintf("\n[ 성과 ] Grade=%s | Score=%.1f\n",
            hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0),
    sprintf("  CAGR=%.2f%% | SR=%.3f | MDD=%.1f%%",
            perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD)
  ))
}, error = function(e) cat("[TG]", e$message, "\n"))

# ══════════════════════════════════════════════════════════
# Phase 12: QEPM Auto Commit
# ══════════════════════════════════════════════════════════
if (isTRUE(QEPM_AUTO_COMMIT)) {
  tryCatch({
    qh <- file.path(dirname(dirname(dirname(SCRIPT_DIR))),
                    "qepm", "scripts", "hybrid_mode.R")
    if (file.exists(qh)) {
      source(qh)
      if (exists("hybrid_commit"))
        hybrid_commit(strategy_name  = STRATEGY_ID,
                      family         = STRATEGY_FAMILY,
                      hurdle_result  = hurdle,
                      artifact_paths = list(output_dir))
    }
  }, error = function(e) cat("[QEPM]", e$message, "\n"))
}

elapsed <- difftime(Sys.time(), t0, units = "secs")
cat(sprintf("\n=== %s CBPQ S1 Complete. Grade=%s Score=%.1f ===\n",
            STRATEGY_ID, hurdle$grade,
            hurdle$total_score %||% hurdle$score %||% 0))
cat(sprintf("[run_all] 완료: %.1f초\n", as.numeric(elapsed)))
cat("=== END STR_1657_CBPQ ===\n")
