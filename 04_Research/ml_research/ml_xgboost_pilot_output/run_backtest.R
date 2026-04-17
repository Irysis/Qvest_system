## XGBoost Pilot — 백테스트 재실행 (모델 재학습 없이)
## 저장된 monthly_portfolio_scores.csv + oos_ic_monthly.csv 활용

cat("=== XGBoost Pilot Backtest (resume) ===\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(xgboost)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUTPUT_DIR <- file.path(PROJECT_ROOT, "04_Research/ml_xgboost_pilot_output")

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

# RAWDATA + BM_DT
cat("[1] RAWDATA 로드...\n")
rw_list <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw_list$RAWDATA
BM_DT <- rw_list$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)

# OOS IC
oos_ic_monthly <- fread(file.path(OUTPUT_DIR, "oos_ic_monthly.csv"))
overall_ic <- mean(oos_ic_monthly$IC, na.rm = TRUE)
overall_icsd <- sd(oos_ic_monthly$IC, na.rm = TRUE)
overall_icir <- overall_ic / overall_icsd
cat("    OOS IC:", round(overall_ic, 4), "| ICIR:", round(overall_icir, 4), "\n")

# 포트폴리오 스코어
cat("[2] 포트폴리오 스코어 로드...\n")
monthly_port <- fread(file.path(OUTPUT_DIR, "monthly_portfolio_scores.csv"))
LIQ_THRESHOLD <- 2e8
monthly_port <- monthly_port[!is.na(Size) & Size >= LIQ_THRESHOLD]
cat("    rows:", nrow(monthly_port), "\n")

# FACTORS: Date, Ticker, Score (backtest_harness API)
FACTORS <- monthly_port[, .(Date, Ticker, Score = ml_score)]
FACTORS[, Date := as.Date(Date)]

cat("[3] 백테스트 실행...\n")
bt_result <- tryCatch({
  run_monthly_simulation(
    RAWDATA       = RAWDATA,
    BM_DT         = BM_DT,
    FACTORS       = FACTORS,
    n_holdings    = 20,
    commission    = 15,
    weight_method = "EW",
    buffer_zone   = list(keep_n = 20, entry_n = 30)
  )
}, error = function(e) {
  cat("    백테스트 오류:", e$message, "\n")
  NULL
})

if (!is.null(bt_result)) {
  perf <- bt_result$performance
  cat("\n--- ML XGBoost 백테스트 결과 ---\n")
  cat("CAGR   :", round(perf$CAGR, 2), "%\n")
  cat("Sharpe :", round(perf$Sharpe, 3), "\n")
  cat("MDD    :", round(perf$MDD, 2), "%\n")
  cat("Calmar :", round(perf$Calmar, 3), "\n")
  if (!is.null(perf$WinRate)) cat("WinRate:", round(perf$WinRate, 1), "%\n")
  if (!is.null(perf$Turnover)) cat("TO     :", round(perf$Turnover, 1), "%\n")

  if (!is.null(bt_result$nav)) {
    fwrite(bt_result$nav, file.path(OUTPUT_DIR, "nav.csv"))
  }

  perf_out <- c(list(
    strategy     = "ML_XGBoost_Pilot",
    description  = "일간 300팩터 XGBoost Walk-forward, OOS 2008~2025",
    IC_monthly   = round(overall_ic, 4),
    ICIR_monthly = round(overall_icir, 4)
  ), perf)
  write_json(perf_out, file.path(OUTPUT_DIR, "performance.json"),
             auto_unbox = TRUE, pretty = TRUE)
}

# Feature Importance (xgb.importance column: Feature or feature)
cat("\n[4] Feature Importance...\n")
imp_files <- sort(list.files(OUTPUT_DIR, pattern = "xgb_model_\\d{4}\\.rds$",
                             full.names = TRUE))
if (length(imp_files) > 0) {
  imp_list <- lapply(imp_files, function(f) {
    yr <- sub(".*xgb_model_(\\d{4})\\.rds$", "\\1", f)
    model <- readRDS(f)
    imp <- tryCatch(xgb.importance(model = model), error = function(e) NULL)
    if (!is.null(imp) && nrow(imp) > 0) {
      # Normalize column names (xgboost 3.x uses 'Feature')
      if (!"Feature" %in% names(imp) && "feature" %in% names(imp))
        setnames(imp, "feature", "Feature")
      imp[, oos_year := yr]
    }
    imp
  })
  imp_all <- rbindlist(imp_list[!sapply(imp_list, is.null)],
                       use.names = TRUE, fill = TRUE)

  if ("Feature" %in% names(imp_all)) {
    imp_avg <- imp_all[, .(
      mean_gain  = mean(Gain, na.rm = TRUE),
      mean_cover = mean(Cover, na.rm = TRUE),
      n_years    = .N
    ), by = Feature][order(-mean_gain)]

    cat("\n--- Top 20 Feature (Gain) ---\n")
    print(head(imp_avg[, .(Feature,
                           gain = round(mean_gain, 4),
                           n_years)], 20))

    fwrite(imp_avg, file.path(OUTPUT_DIR, "feature_importance_avg.csv"))
    fwrite(imp_all, file.path(OUTPUT_DIR, "feature_importance_yearly.csv"))
  } else {
    cat("    Feature column not found in importance\n")
    cat("    Available columns:", paste(names(imp_all), collapse = ", "), "\n")
  }
}

# STR_1631 앵커 상관
cat("\n[5] STR_1631 앵커 독립성...\n")
anchor_nav_path <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1631/output/daily_nav.csv")

if (file.exists(anchor_nav_path) && !is.null(bt_result) && !is.null(bt_result$nav)) {
  anchor_nav <- fread(anchor_nav_path)
  ml_nav <- bt_result$nav
  if ("Date" %in% names(anchor_nav) && "NAV" %in% names(anchor_nav)) {
    setkey(anchor_nav, Date); setkey(ml_nav, Date)
    combined <- merge(
      anchor_nav[, .(Date, NAV_anchor = NAV)],
      ml_nav[, .(Date, NAV_ml = NAV)], by = "Date")
    combined[, ret_anchor := NAV_anchor / shift(NAV_anchor) - 1]
    combined[, ret_ml := NAV_ml / shift(NAV_ml) - 1]
    combined <- combined[!is.na(ret_anchor) & !is.na(ret_ml)]
    ret_corr <- cor(combined$ret_anchor, combined$ret_ml, use = "complete.obs")
    cat("    상관:", round(ret_corr, 4), "\n")
    corr_result <- list(anchor = "STR_1631", ml = "ML_XGBoost_Pilot",
                        corr = round(ret_corr, 4), n_obs = nrow(combined))
    write_json(corr_result, file.path(OUTPUT_DIR, "anchor_correlation.json"),
               auto_unbox = TRUE, pretty = TRUE)
  }
} else {
  cat("    STR_1631 NAV 없음\n")
}

cat("\n=== 백테스트 완료 ===\n")
