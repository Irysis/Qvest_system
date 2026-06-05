cat("=== STR_1654: Beta-Conditioned Sector-Neutral Accrual (BCSNA) ===\n")
## 핵심아이디어: Expanding-window CAPM beta 하위 40% 유니버스 →
##   AC21(CF-to-Accrual Ratio) + AC22(Accrual Volatility) + AC17(Accrual Reversal)
##   WICS 업종별 Score 상위 3종목 x 10업종 = 최대 30종목 Sector-Neutral 포트폴리오
## 역할: Diversifier  RoleBias_Diversifier
## 근거: Sloan(1996) accrual anomaly, Richardson et al.(2005) accrual volatility
## S1: 순수 팩터 신호. EW. DD/VT/Regime 오버레이 없음.
##
## OPT-1: Factor DB arrow::open_dataset 1회 bulk preload → 메모리 내 필터
##        루프 내 일체의 parquet I/O 없음 (factor_engine.R도 동일)
## OPT-2: load_rawdata(use_cache=TRUE) 1회
## OPT-5: stress_periods 8대 정본
##        (2001-09 / 2007-10 / 2011-07 / 2015-06 / 2018-03 / 2020-01 / 2022-01 / 2026-02)
##
## PIT: C2(Beta t-1 lag), C9(no DD/VT), C10(AvgTV20 t-1 lag),
##      C13(Z_Score_Aligned), C14(Usable_Date), C15(Factor DB 경유)

set.seed(1654)
options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_NAME    <- "BCSNA_Sector_Neutral_Accrual"
STRATEGY_ID      <- "STR_1654"
STRATEGY_FAMILY  <- "accrual"
QEPM_AUTO_COMMIT <- TRUE

# ── 경로 설정 (normalizePath 금지 — WSL 한글 경로 버그) ─────────
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
  library(xts)
  library(arrow)
  library(dplyr, warn.conflicts = FALSE)
})

output_dir <- file.path(SCRIPT_DIR, "output")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# ── Preflight Check ─────────────────────────────────────────────
tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", e$message, "\n"))

# ── Lookahead Detector ──────────────────────────────────────────
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

LIQ_THRESHOLD <- 2e8

# ── Phase 1: RAWDATA 로드 (OPT-2: use_cache=TRUE 1회) ───────────
cat("\n[Phase 1] Loading RAWDATA...\n")
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT

STR_START_DATE    <- as.Date("2003-01-01")
SIGNAL_START_DATE <- as.Date("2004-01-01")
RAWDATA           <- RAWDATA[Date >= STR_START_DATE]
cat(sprintf("  RAWDATA: %s ~ %s (%s rows)\n",
            min(RAWDATA$Date), max(RAWDATA$Date),
            format(nrow(RAWDATA), big.mark = ",")))

RAWDATA_ORIG <- copy(RAWDATA)
rm(res); gc(verbose = FALSE)

# ── Phase 2: Factor DB Bulk Preload (OPT-1) ─────────────────────
# arrow::open_dataset 단 1회 호출 — 이후 모든 조회는 메모리 내 FDB_BULK 사용
# factor_engine.R 포함 어디에서도 파일 I/O 없음
cat("\n[Phase 2] Factor DB bulk preload (AC17 + AC21 + AC22)...\n")

NEEDED_FACTORS <- c("AC17_Accrual_Reversal",
                    "AC21_CF_to_Accrual_Ratio",
                    "AC22_Accrual_Volatility")

fdb_dir_path  <- file.path(CACHE_DIR, "factor_db")
fdb_files_all <- list.files(fdb_dir_path,
                             pattern = "^factor_db_\\d{6}\\.parquet$",
                             full.names = TRUE)
# STR_START_DATE(2003-01-01) 이후 파일만 사용
# 파일명 전체에서 6자리 숫자(yyyymm) 추출 → 정수 비교
fdb_ym_nums   <- as.integer(regmatches(basename(fdb_files_all),
                              regexpr("\\d{6}", basename(fdb_files_all))))
fdb_files_use <- fdb_files_all[!is.na(fdb_ym_nums) & fdb_ym_nums >= 200301L]
cat(sprintf("  parquet 파일: %d개\n", length(fdb_files_use)))

# open_dataset 스키마로 컬럼 확인 (단순 파일 로드 없이)
ds_schema <- tryCatch(
  arrow::open_dataset(fdb_files_use, format = "parquet")$schema$names,
  error = function(e) character(0)
)
.z_col <- if ("Z_Score_Aligned" %in% ds_schema) "Z_Score_Aligned" else "Z_Score"
cat(sprintf("  Z-score 컬럼: %s\n", .z_col))

FDB_BULK <- tryCatch({
  raw <- arrow::open_dataset(fdb_files_use, format = "parquet") |>
    dplyr::filter(Factor_Name %in% NEEDED_FACTORS, Coverage == TRUE) |>
    dplyr::select(dplyr::all_of(c("Date", "Ticker", "Factor_Name", .z_col))) |>
    dplyr::collect() |>
    as.data.table()
  raw[, Date := as.Date(Date)]
  setnames(raw, .z_col, "Z_Score_Aligned")
  setkey(raw, Date, Ticker)
  gc(verbose = FALSE)
  cat(sprintf("  FDB_BULK: %s rows | %d dates | factors: %s\n",
              format(nrow(raw), big.mark = ","),
              uniqueN(raw$Date),
              paste(sort(unique(raw$Factor_Name)), collapse = ", ")))
  raw
}, error = function(e) {
  stop(sprintf("[Phase 2] Factor DB bulk load 실패: %s", conditionMessage(e)))
})

# ── Phase 3: factor_engine 실행 ─────────────────────────────────
# FDB_BULK 메모리 객체를 factor_engine.R에서 직접 참조
# factor_engine.R 내부에서 lapply 기반 처리 (루프 내 파일 I/O 없음)
cat("\n[Phase 3] Factor engine — sector-neutral scoring...\n")
source(file.path(SCRIPT_DIR, "factor_engine.R"))

stopifnot(
  is.data.table(FACTORS),
  all(c("Date", "Ticker", "Score") %in% names(FACTORS)),
  nrow(FACTORS) > 0
)

# ── Phase 4: 백테스트 (Rcpp run_monthly_simulation 23x) ─────────
# 섹터-뉴트럴 설계: 10 대분류 x 3종목 = 30종목 고정
# FACTORS에는 이미 대분류별 Top3만 포함 → n_holdings=30, buffer_zone=30/35
actual_n <- as.integer(median(FACTORS[, .N, by = Date]$N))
cat(sprintf("\n[Phase 4] Backtest — sector-neutral EW N~30 (median=%d), NO overlay...\n",
            actual_n))

RAWDATA <- copy(RAWDATA_ORIG)

sim <- run_monthly_simulation(
  RAWDATA       = RAWDATA,
  BM_DT         = BM_DT,
  FACTORS       = FACTORS,
  n_holdings    = 30L,
  weight_method = "equal",
  commission    = 0.0015,
  buffer_zone   = list(keep_n = 35L, entry_n = 30L)
)

# ── Phase 5: 성과 분석 ─────────────────────────────────────────
cat("\n[Phase 5] Performance analysis...\n")
perf_strat <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
perf_bm    <- summarise_perf(sim$bm_xts, "BM")
to_val     <- tryCatch(
  calc_turnover(sim$PORTFOLIO_LOG, sim$DAILY_NAV_DT),
  error = function(e) NA_real_
)

cat(sprintf("  %s: CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
            STRATEGY_ID, perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD))
cat(sprintf("  BM: CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
            perf_bm$CAGR, perf_bm$Sharpe, perf_bm$MDD))
if (!is.na(to_val)) cat(sprintf("  Turnover(ann.): %.1f%%\n", to_val))

generate_charts(sim, output_dir = output_dir, strategy_name = STRATEGY_NAME)
fwrite(rbind(perf_strat, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds"))
saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))

RAWDATA <- copy(RAWDATA_ORIG)
tryCatch({
  source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir, strategy_name = STRATEGY_ID)
}, error = function(e) cat("[WARN analyzer]", e$message, "\n"))

# ── Phase 6: Hurdle Gate ────────────────────────────────────────
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

# ── Phase 7: Diversifier 분석 ──────────────────────────────────
cat("\n[Phase 7] Diversifier 분석...\n")

tryCatch({
  strat_ret <- as.numeric(coredata(sim$strategy_xts))
  bm_ret_ts <- as.numeric(coredata(sim$bm_xts))
  dates_ts  <- as.Date(index(sim$strategy_xts))
  valid_idx <- !is.na(strat_ret) & !is.na(bm_ret_ts)

  port_beta <- NA_real_
  if (sum(valid_idx) >= 60L) {
    bv <- bm_ret_ts[valid_idx]; sv <- strat_ret[valid_idx]
    port_beta <- cov(sv, bv) / var(bv)
    cat(sprintf("  [Beta] 실현: %.3f (목표 < 0.40)\n", port_beta))
    idx_3y <- valid_idx & dates_ts >= (max(dates_ts) - 365*3)
    if (sum(idx_3y) >= 30L) {
      b3y <- cov(strat_ret[idx_3y], bm_ret_ts[idx_3y]) / var(bm_ret_ts[idx_3y])
      cat(sprintf("  [Beta] 최근 3Y: %.3f\n", b3y))
    }
  }

  # 8대 스트레스 구간 정본 (OPT-5 — reference_stress_periods.md)
  stress_periods <- list(
    list(label = "9/11",       start = "2001-09-01", end = "2001-12-31"),
    list(label = "GFC",        start = "2007-10-01", end = "2009-03-31"),
    list(label = "EuDebt",     start = "2011-07-01", end = "2011-12-31"),
    list(label = "ChinaShock", start = "2015-06-01", end = "2016-02-29"),
    list(label = "TradeWar",   start = "2018-03-01", end = "2018-12-31"),
    list(label = "COVID",      start = "2020-01-01", end = "2020-06-30"),
    list(label = "RateHike",   start = "2022-01-01", end = "2022-12-31"),
    list(label = "IranWar",    start = "2026-02-01", end = "2026-04-30")
  )

  cat("\n  [Stress] 8대 스트레스 구간 총수익률:\n")
  stress_results <- lapply(stress_periods, function(sp) {
    s   <- as.Date(sp$start); e <- as.Date(sp$end)
    idx <- dates_ts >= s & dates_ts <= e & valid_idx
    if (sum(idx) < 3L) {
      cat(sprintf("    %-14s: 데이터 부족\n", sp$label))
      return(list(label = sp$label, n = 0L,
                  strat_ret = NA_real_, bm_ret = NA_real_, alpha = NA_real_))
    }
    sr_cum <- prod(1 + strat_ret[idx]) - 1
    bm_cum <- prod(1 + bm_ret_ts[idx]) - 1
    alpha  <- sr_cum - bm_cum
    cat(sprintf("    %-14s: 전략=%+.1f%% BM=%+.1f%% Alpha=%+.1f%%\n",
                sp$label, sr_cum*100, bm_cum*100, alpha*100))
    list(label = sp$label, n = sum(idx),
         strat_ret = round(sr_cum, 4), bm_ret = round(bm_cum, 4),
         alpha = round(alpha, 4))
  })
  saveRDS(stress_results, file.path(output_dir, "stress_analysis.rds"))

  corr_val <- NA_real_
  core_candidates <- c("STR_1631", "STR_1555", "STR_1550")
  found_corr <- FALSE
  vapply(core_candidates, function(core_id) {
    if (found_corr) return(invisible(NULL))
    core_path <- file.path(SCRIPT_DIR, "..", "..", core_id, "output", "sim_result.rds")
    if (!file.exists(core_path))
      core_path <- file.path(SCRIPT_DIR, "..", "..", core_id, "sim_result.rds")
    if (!file.exists(core_path)) return(invisible(NULL))
    core_sim   <- readRDS(core_path)
    core_ret   <- as.numeric(coredata(core_sim$strategy_xts))
    core_dates <- as.Date(index(core_sim$strategy_xts))
    common_d   <- intersect(as.character(dates_ts[valid_idx]),
                            as.character(core_dates[!is.na(core_ret)]))
    if (length(common_d) < 36L) return(invisible(NULL))
    cd <- as.Date(common_d)
    cv <- cor(strat_ret[dates_ts %in% cd],
              core_ret[core_dates %in% cd], use = "complete.obs")
    corr_val  <<- cv
    found_corr <<- TRUE
    cat(sprintf("  [C19 상관] %s 대비: %.3f (n=%d) → %s\n",
                core_id, cv, length(common_d),
                ifelse(abs(cv) < 0.30, "+15 eligible",
                ifelse(abs(cv) < 0.50, "+5~8 eligible", "no bonus"))))
    invisible(NULL)
  }, FUN.VALUE = logical(0L))

  div_report <- list(strategy_id = STRATEGY_ID, role = "RoleBias_Diversifier",
                     port_beta = port_beta, corr_core = corr_val,
                     stress_results = stress_results)
  saveRDS(div_report, file.path(output_dir, "diversifier_analysis.rds"))
  jsonlite::write_json(div_report,
    file.path(output_dir, "diversifier_analysis.json"),
    auto_unbox = TRUE, pretty = TRUE)
  cat("  [Diversifier] 완료.\n")

}, error = function(e) cat("[WARN diversifier]", e$message, "\n"))

# ── 텔레그램 ───────────────────────────────────────────────────
tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
  hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json"))
  tg_strategy_result_with_chart(STRATEGY_ID, hr, output_dir)
  tg_send(paste0(
    "[Forge] STR_1654 BCSNA S1 완료\n\n",
    "[ 팩터 ] AC21 + AC22 + AC17 (Accrual 3F)\n",
    "[ 구조 ] Beta 하위 40%(expanding, t-1) -> 업종별 Top3\n\n",
    sprintf("[ 성과 ] Grade=%s | Score=%.1f\n",
            hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0),
    sprintf("  CAGR=%.2f%% | SR=%.3f | MDD=%.1f%%",
            perf_strat$CAGR, perf_strat$Sharpe, perf_strat$MDD)
  ))
}, error = function(e) cat("[TG]", e$message, "\n"))

# ── QEPM Auto Commit ───────────────────────────────────────────
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

cat(sprintf("\n=== %s BCSNA S1 Complete. Grade=%s Score=%.1f ===\n",
            STRATEGY_ID, hurdle$grade,
            hurdle$total_score %||% hurdle$score %||% 0))
