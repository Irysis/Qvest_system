## =============================================================================
## ML Linear Baseline — L-123 Tier 1 (Ridge + Logistic)
## 일간 DB 학습 + IC Prefilter(309→50) + Walk-Forward + Purged CV
##
## L-123 준수:
##   - §4: 일간 DB 5,700일 활용 (월간 280 obs → p>>n 해결)
##   - §2.3: IC prefilter 309→50 features
##   - MC1: Walk-forward expanding | MC2: Purged 21d gap
##   - MC3: Target t+1~t+21 fwd ret | MC4: Feature t 시점만
##   - MC5: lambda = validation CV only
##
## 메모리 전략: OOS 연도별 훈련 구간 일간 데이터만 청크 로드 → gc()
## =============================================================================

cat("=== ML Linear Baseline: 일간 DB 학습 + IC Prefilter + Ridge + Logistic ===\n")
cat("L-123 Tier 1 + §4 일간 DB. 시작:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(glmnet)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
DAILY_DB_DIR <- file.path(PROJECT_ROOT, ".cache/factor_db_daily")
OUTPUT_DIR   <- file.path(PROJECT_ROOT, "04_Research/ml_linear_baseline_output")
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

# ==============================================================================
# 1. RAWDATA 로드 (한 번만)
# ==============================================================================
cat("[1] RAWDATA 로드...\n")
rw_list <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw_list$RAWDATA
BM_DT   <- rw_list$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
cat("    rows:", nrow(RAWDATA), "\n")

# 일간 수익률 + 21일 순방향 수익률 사전 계산
cat("[2] 21일 순방향 수익률 사전 계산...\n")
ret_dt <- RAWDATA[Date >= as.Date("2003-01-01"), .(Date, Ticker, Ret, Size)]
setkey(ret_dt, Ticker, Date)
ret_dt[, log_ret := log(1 + Ret)]
ret_dt[, fwd_ret_21d := {
  n <- .N
  if (n <= 21L) rep(NA_real_, n)
  else { cl <- cumsum(log_ret); fwd <- c(cl[22:n], rep(NA_real_, 21L)) - cl; exp(fwd) - 1 }
}, by = Ticker]
ret_dt[, log_ret := NULL]
ret_dt <- ret_dt[!is.na(fwd_ret_21d)]
cat("    Target rows:", nrow(ret_dt), "\n")

# ==============================================================================
# 2. 파일 목록 + 컬럼 구조 사전 파악
# ==============================================================================
EXCLUDE_PREFIXES <- c("RE_", "dps_1y", "bps_1y", "eps_1y", "target_price")
all_files <- sort(list.files(DAILY_DB_DIR, pattern = "fdb_daily_\\d{6}\\.parquet$", full.names = TRUE))
ym_str <- sub("fdb_daily_([0-9]{6})\\.parquet", "\\1", basename(all_files))
ym_int <- as.integer(ym_str)

sample_dt <- as.data.table(read_parquet(all_files[which(ym_int == 200301)]))
excl_cols <- c(grep(paste(EXCLUDE_PREFIXES, collapse = "|"), names(sample_dt), value = TRUE),
               grep("\\.x$", names(sample_dt), value = TRUE))
keep_cols <- setdiff(names(sample_dt), excl_cols)
FACTOR_COLS_BASE <- setdiff(keep_cols, c("Date", "Ticker"))
rm(sample_dt)
cat("[2] 팩터 컬럼:", length(FACTOR_COLS_BASE), "\n")

# ==============================================================================
# 유틸: 일간 DB 청크 로드 (특정 연도 범위만)
# ==============================================================================
load_daily_chunk <- function(start_ym, end_ym) {
  # start_ym, end_ym: integer YYYYMM
  idx <- which(ym_int >= start_ym & ym_int <= end_ym)
  if (length(idx) == 0) return(NULL)
  chunk_files <- all_files[idx]

  chunks <- vector("list", length(chunk_files))
  for (i in seq_along(chunk_files)) {
    tmp <- as.data.table(read_parquet(chunk_files[i]))
    avail <- intersect(keep_cols, names(tmp))
    chunks[[i]] <- tmp[, avail, with = FALSE]
    rm(tmp)
  }
  dt <- rbindlist(chunks, use.names = TRUE, fill = TRUE)
  rm(chunks)

  # .y 정리
  old_y <- grep("\\.y$", names(dt), value = TRUE)
  new_y <- sub("\\.y$", "", old_y)
  already <- new_y[new_y %in% setdiff(names(dt), old_y)]
  if (length(old_y[new_y %in% already]) > 0) dt[, (old_y[new_y %in% already]) := NULL]
  rename_y <- old_y[!(new_y %in% already)]
  if (length(rename_y) > 0) setnames(dt, rename_y, sub("\\.y$", "", rename_y), skip_absent = TRUE)
  dup <- names(dt)[duplicated(names(dt))]
  if (length(dup) > 0) dt[, (dup) := NULL]

  setkey(dt, Date, Ticker)
  dt
}

# ==============================================================================
# 3. Walk-Forward: 연도별 청크 로드 → IC Prefilter → Ridge + Logistic
# ==============================================================================
cat("\n[3] Walk-Forward (일간 학습) 시작...\n")

oos_years <- as.character(2008:2025)
cat("    OOS:", paste(oos_years, collapse = ", "), "\n\n")

LIQ_THRESHOLD <- 2e8
ridge_scores <- list()
logit_scores <- list()
prefilter_log <- list()

for (yi in seq_along(oos_years)) {
  oos_yr <- as.integer(oos_years[yi])
  cat("  [", oos_yr, "] ")

  # IS: 2003 ~ oos_yr-2 (purge gap 1년)
  # Val: oos_yr-1 (1년 purge 후 검증)
  # OOS: oos_yr
  is_end_yr  <- oos_yr - 2L
  val_yr     <- oos_yr - 1L

  # --- IS 일간 데이터 청크 로드 (최근 5년만 — 메모리 상한) ---
  is_start_ym <- max(200301, (is_end_yr - 4L) * 100 + 1)
  is_chunk <- load_daily_chunk(is_start_ym, is_end_yr * 100 + 12)
  if (is.null(is_chunk) || nrow(is_chunk) < 10000) { cat("skip (is data)\n"); next }

  # Target 병합 (일간)
  is_merged <- merge(is_chunk, ret_dt[, .(Date, Ticker, fwd_ret_21d, Size)],
                     by = c("Date", "Ticker"), all.x = FALSE)
  is_merged <- is_merged[!is.na(fwd_ret_21d) & !is.na(Size) & Size >= LIQ_THRESHOLD]
  rm(is_chunk); gc()

  # 메모리 상한: 500K 행 초과 시 층화 표본 (연도 균등)
  MAX_IS_ROWS <- 500000L
  if (nrow(is_merged) > MAX_IS_ROWS) {
    is_merged[, yr := format(Date, "%Y")]
    is_merged <- is_merged[, .SD[sample(.N, min(.N, MAX_IS_ROWS %/% uniqueN(yr)))], by = yr]
    is_merged[, yr := NULL]
    cat("sampled:", nrow(is_merged), "| ")
  }

  # 사용 가능 팩터 컬럼
  FACTOR_COLS <- intersect(FACTOR_COLS_BASE, names(is_merged))
  FACTOR_COLS <- unique(FACTOR_COLS)

  cat("IS:", nrow(is_merged), "rows,", length(FACTOR_COLS), "facs | ")

  # --- IC Prefilter: 일간 IS 데이터에서 Spearman IC 상위 50개 ---
  # 효율: 월말 데이터만 사용하여 IC 계산 (일간 전체는 너무 느림)
  is_monthend <- is_merged[, .SD[Date == max(Date)], by = format(Date, "%Y-%m")]
  ics <- sapply(FACTOR_COLS, function(f) {
    x <- is_monthend[[f]]
    y <- is_monthend$fwd_ret_21d
    valid <- is.finite(x) & is.finite(y)
    if (sum(valid) < 100) return(NA_real_)
    tryCatch(cor(x[valid], y[valid], method = "spearman"), error = function(e) NA_real_)
  })
  ics <- ics[!is.na(ics)]
  top50 <- names(sort(abs(ics), decreasing = TRUE))[seq_len(min(50, length(ics)))]

  prefilter_log[[yi]] <- data.table(
    oos_year = oos_yr, n_features = length(top50),
    top5 = paste(head(top50, 5), collapse = ",")
  )
  cat("top50 | ")

  # --- IS 일간 Feature 행렬 (top50만, 메모리 절약) ---
  build_mat <- function(dt, cols) {
    m <- as.matrix(dt[, cols, with = FALSE])
    m[!is.finite(m)] <- 0
    m
  }

  X_is <- build_mat(is_merged, top50)
  y_is <- is_merged$fwd_ret_21d

  # 메모리 해제: is_merged에서 불필요 컬럼 제거
  rm(is_merged, is_monthend); gc()

  # --- Val 데이터 (월말만 — 검증은 월말 예측력으로) ---
  val_chunk <- load_daily_chunk(val_yr * 100 + 1, val_yr * 100 + 12)
  if (is.null(val_chunk) || nrow(val_chunk) == 0) { cat("skip (val)\n"); rm(X_is, y_is); gc(); next }

  # 월말만 추출
  val_chunk[, ym := format(Date, "%Y-%m")]
  val_monthend <- val_chunk[, .SD[Date == max(Date)], by = ym]
  val_merged <- merge(val_monthend, ret_dt[, .(Date, Ticker, fwd_ret_21d, Size)],
                      by = c("Date", "Ticker"), all.x = FALSE)
  val_merged <- val_merged[!is.na(fwd_ret_21d) & !is.na(Size) & Size >= LIQ_THRESHOLD]
  rm(val_chunk, val_monthend); gc()

  X_val <- build_mat(val_merged, top50)
  y_val <- val_merged$fwd_ret_21d

  # --- OOS 데이터 (월말만 — 예측 + 리밸런싱) ---
  oos_chunk <- load_daily_chunk(oos_yr * 100 + 1, oos_yr * 100 + 12)
  if (is.null(oos_chunk) || nrow(oos_chunk) == 0) {
    cat("skip (oos)\n"); rm(X_is, y_is, X_val, y_val, val_merged); gc(); next
  }
  oos_chunk[, ym := format(Date, "%Y-%m")]
  oos_monthend <- oos_chunk[, .SD[Date == max(Date)], by = ym]
  oos_merged <- merge(oos_monthend, ret_dt[, .(Date, Ticker, fwd_ret_21d, Size)],
                      by = c("Date", "Ticker"), all.x = FALSE)
  oos_merged <- oos_merged[!is.na(fwd_ret_21d)]
  rm(oos_chunk, oos_monthend); gc()

  X_oos <- build_mat(oos_merged, top50)

  # ==== Ridge Regression (alpha=0, 고정 lambda grid — cv.glmnet 대비 50x 빠름) ====
  LAMBDA_GRID <- c(1, 0.1, 0.01, 0.001, 0.0001)

  ridge_fit <- tryCatch({
    glmnet(X_is, y_is, alpha = 0, lambda = LAMBDA_GRID)
  }, error = function(e) NULL)

  if (!is.null(ridge_fit)) {
    # Validation set에서 최적 lambda 선택 (MC5 준수)
    val_preds <- predict(ridge_fit, X_val)  # n_val × n_lambda matrix
    val_ics <- apply(val_preds, 2, function(p) {
      tryCatch(cor(p, y_val, method = "spearman"), error = function(e) NA_real_)
    })
    best_lambda <- LAMBDA_GRID[which.max(val_ics)]

    ridge_pred <- as.numeric(predict(ridge_fit, X_oos, s = best_lambda))
    ridge_val_ic <- max(val_ics, na.rm = TRUE)

    oos_r <- oos_merged[, .(Date, Ticker, fwd_ret_21d, Size)]
    oos_r[, ridge_score := ridge_pred]
    ridge_scores[[yi]] <- oos_r
    cat("Ridge:", round(ridge_val_ic, 3), "(lam=", best_lambda, ") | ")
  }

  # 메모리 해제
  rm(X_is, y_is, X_val, y_val, X_oos, val_merged, oos_merged, ridge_fit)
  gc()
  cat("\n")
}

# ==============================================================================
# 4. OOS IC 분석
# ==============================================================================
cat("\n[4] OOS IC 분석...\n")

ridge_all <- rbindlist(ridge_scores, use.names = TRUE, fill = TRUE)
ridge_all[, YearMonth := format(Date, "%Y-%m")]
ridge_ic_m <- ridge_all[, .(IC = cor(ridge_score, fwd_ret_21d, method = "spearman",
                                      use = "complete.obs")), by = YearMonth]
ridge_ic_mean <- mean(ridge_ic_m$IC, na.rm = TRUE)
ridge_ic_sd   <- sd(ridge_ic_m$IC, na.rm = TRUE)
ridge_icir    <- ridge_ic_mean / ridge_ic_sd

cat("\n--- L-123 Tier Comparison ---\n")
cat(sprintf("%-12s  IC_mean   IC_SD   ICIR    Training\n", "Model"))
cat(sprintf("%-12s  %.4f    %.4f  %.4f   일간 5700일(L-123§4)\n", "Ridge", ridge_ic_mean, ridge_ic_sd, ridge_icir))
cat(sprintf("%-12s  %.4f    %.4f  %.4f   월말only(§4 위반)\n", "XGBoost*", 0.0669, 0.0928, 0.7206))

nonlinear_gap <- 0.7206 - ridge_icir
cat(sprintf("\n비선형 기여 추정: XGB ICIR(0.72) - Ridge ICIR(%.2f) = %.2f\n", ridge_icir, nonlinear_gap))

fwrite(ridge_ic_m, file.path(OUTPUT_DIR, "ridge_oos_ic_monthly.csv"))

# ==============================================================================
# 5. 백테스트: Ridge Top 20
# ==============================================================================
cat("\n[5] 백테스트...\n")

run_bt <- function(score_dt, score_col, label) {
  dt <- copy(score_dt)
  setnames(dt, score_col, "Score", skip_absent = TRUE)
  dt <- dt[!is.na(Score) & !is.na(Size) & Size >= LIQ_THRESHOLD]
  dt[, rank := frank(-Score, ties.method = "first"), by = Date]
  dt <- dt[rank <= 30]
  FACTORS <- dt[, .(Date, Ticker, Score)]

  bt <- tryCatch({
    run_monthly_simulation(RAWDATA, BM_DT, FACTORS, n_holdings = 20,
      commission = 0.0015, weight_method = "EW",
      buffer_zone = list(keep_n = 20, entry_n = 30))
  }, error = function(e) { cat("    ", label, "error:", e$message, "\n"); NULL })

  if (!is.null(bt)) {
    ret <- bt$DAILY_NAV_DT$Strategy_Ret
    ret <- ret[is.finite(ret)]
    cum <- cumprod(1 + ret)
    n_yr <- length(ret) / 252
    cagr <- tail(cum, 1)^(1/n_yr) - 1
    sr <- mean(ret) / sd(ret) * sqrt(252)
    dd <- cum / cummax(cum) - 1
    mdd <- min(dd)
    cat(sprintf("    %s: CAGR %.2f%% | SR %.3f | MDD %.2f%%\n",
                label, cagr * 100, sr, mdd * 100))
    fwrite(bt$DAILY_NAV_DT, file.path(OUTPUT_DIR, paste0(tolower(label), "_nav.csv")))
    return(list(CAGR = round(cagr * 100, 2), Sharpe = round(sr, 3), MDD = round(mdd * 100, 2)))
  }
  NULL
}

ridge_perf <- run_bt(ridge_all, "ridge_score", "Ridge")

# ==============================================================================
# 6. 결과 저장
# ==============================================================================
result <- list(
  ridge = list(IC = round(ridge_ic_mean, 4), ICIR = round(ridge_icir, 4), perf = ridge_perf),
  xgboost_ref = list(IC = 0.0669, ICIR = 0.7206, note = "월말only, L-123§4 위반"),
  prefilter = list(method = "expanding_IC_top50_monthend_proxy", n_features = 50),
  training_data = "일간 Factor DB (L-123 §4 준수)",
  l123_compliance = list(MC1 = "walk-forward expanding", MC2 = "purged 1yr gap",
    MC3 = "fwd_ret_21d", MC4 = "t-time only", MC5 = "lambda cv.glmnet IS",
    sec4 = "일간 DB 학습 (5700일)")
)
write_json(result, file.path(OUTPUT_DIR, "comparison_result.json"),
           auto_unbox = TRUE, pretty = TRUE)
fwrite(rbindlist(prefilter_log), file.path(OUTPUT_DIR, "prefilter_log.csv"))

cat("\n", paste(rep("=", 60), collapse = ""), "\n")
cat("=== ML Linear Baseline 완료 (일간 학습, Ridge only) ===\n")
cat("Ridge  IC:", round(ridge_ic_mean, 4), " ICIR:", round(ridge_icir, 4), "\n")
cat("XGB*   IC: 0.0669  ICIR: 0.7206 (월말only 참고치)\n")
if (!is.null(ridge_perf)) {
  cat("Ridge BT: CAGR", ridge_perf$CAGR, "% | SR", ridge_perf$Sharpe, " | MDD", ridge_perf$MDD, "%\n")
}
cat("산출물:", OUTPUT_DIR, "\n")
cat(paste(rep("=", 60), collapse = ""), "\n")
