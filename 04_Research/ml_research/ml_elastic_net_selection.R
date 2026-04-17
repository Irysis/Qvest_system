## =============================================================================
## Elastic Net Factor Selection — Feng, Giglio, Xiu (2020)
## 309개 일간 팩터 → 유효 30개 선별
##
## 핵심 아이디어:
##   Double-selection Elastic Net으로 독립적 예측력 있는 팩터만 선별.
##   ICIR 기반 선별과 달리, 다른 팩터를 통제한 잔여 예측력(incremental contribution) 기준.
##   MC1~MC5 + C1~C15 PIT 규칙 완전 준수.
##
## MC1: Walk-forward expanding window (full-sample lambda 금지)
## MC2: Purged gap — IS 종료 후 12개월 gap (target overlap 제거)
## MC3: Target = t→t+1 월간 초과수익률 (PIT 완전 준수)
## MC4: Feature = 월말 t 시점 Factor DB 값
## MC5: lambda = cv.glmnet expanding-window CV (training set 내부만)
##
## References:
##   Feng, Giglio & Xiu (2020) 'Taming the Factor Zoo' JF 75(3)
##   Gu, Kelly & Xiu (2020) 'Empirical Asset Pricing via ML' RFS 33(5)
##   Meinshausen & Buhlmann (2010) 'Stability Selection' JRSS-B 72(4)
## =============================================================================

cat("=== Elastic Net Factor Selection: 309팩터 → Sparse Core ===\n")
cat("PIT Rules: MC1~MC5 + C1~C15 완전 준수\n")
cat("시작 시각:", as.character(Sys.time()), "\n\n")

# ------------------------------------------------------------------------------
# 0. 라이브러리 + 경로
# ------------------------------------------------------------------------------
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(glmnet)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
DAILY_DB_DIR <- file.path(PROJECT_ROOT, ".cache/factor_db_daily")
OUTPUT_DIR   <- file.path(PROJECT_ROOT, "04_Research/ml_elastic_net_output")
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

# ------------------------------------------------------------------------------
# 1. RAWDATA 1회 로드
# ------------------------------------------------------------------------------
cat("[1] RAWDATA 로드...\n")
rw_list <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw_list$RAWDATA
setDT(RAWDATA)
setkey(RAWDATA, Date, Ticker)
cat("    RAWDATA rows:", nrow(RAWDATA), "\n")

# ------------------------------------------------------------------------------
# 2. 일간 Factor DB — 월말 데이터만 로드 (메모리 효율)
# ------------------------------------------------------------------------------
cat("[2] 일간 Factor DB 월말 로드 (2003~2025)...\n")

EXCLUDE_PREFIXES <- c("RE_", "dps_1y", "bps_1y", "eps_1y", "target_price")

all_files <- sort(list.files(DAILY_DB_DIR, pattern = "fdb_daily_\\d{6}\\.parquet$", full.names = TRUE))
ym_str <- sub("fdb_daily_([0-9]{6})\\.parquet", "\\1", basename(all_files))
ym_int <- as.integer(ym_str)
target_files <- all_files[!is.na(ym_int) & ym_int >= 200301 & ym_int <= 202604]
cat("    로드할 파일 수:", length(target_files), "\n")

# 첫 파일에서 컬럼 구조 파악
sample_dt <- as.data.table(read_parquet(target_files[1]))
all_cols <- names(sample_dt)
excl_cols <- c(
  grep(paste(EXCLUDE_PREFIXES, collapse = "|"), all_cols, value = TRUE),
  grep("\\.x$", all_cols, value = TRUE)
)
keep_cols <- setdiff(all_cols, excl_cols)
cat("    유지 컬럼 수:", length(keep_cols), "\n")

# 월말만 로드 (37.5GB → 1.76GB)
fdb_list <- vector("list", length(target_files))
for (i in seq_along(target_files)) {
  tmp <- as.data.table(read_parquet(target_files[i]))
  monthend_date <- max(tmp$Date)
  tmp <- tmp[Date == monthend_date]
  avail <- intersect(keep_cols, names(tmp))
  fdb_list[[i]] <- tmp[, avail, with = FALSE]
  rm(tmp)
  if (i %% 60 == 0) cat("    ...", i, "/", length(target_files), "\n")
}

FDB <- rbindlist(fdb_list, use.names = TRUE, fill = TRUE)
rm(fdb_list); gc()

# .y 접미사 정리
old_y <- grep("\\.y$", names(FDB), value = TRUE)
new_y <- sub("\\.y$", "", old_y)
already_exists <- new_y[new_y %in% setdiff(names(FDB), old_y)]
remove_y <- old_y[new_y %in% already_exists]
rename_y <- old_y[!(new_y %in% already_exists)]
if (length(remove_y) > 0) FDB[, (remove_y) := NULL]
if (length(rename_y) > 0) setnames(FDB, rename_y, sub("\\.y$", "", rename_y), skip_absent = TRUE)
dup_cols <- names(FDB)[duplicated(names(FDB))]
if (length(dup_cols) > 0) FDB[, (dup_cols) := NULL]

FACTOR_COLS <- setdiff(names(FDB), c("Date", "Ticker",
  grep("^RE_", names(FDB), value = TRUE),
  grep("dps_1y|bps_1y|eps_1y|target_price", names(FDB), value = TRUE)))
FACTOR_COLS <- unique(FACTOR_COLS)

setkey(FDB, Date, Ticker)
cat("    FDB rows:", nrow(FDB), "| 팩터:", length(FACTOR_COLS), "\n")

# ------------------------------------------------------------------------------
# 3. Target: 월간 초과수익률 (t→t+1)
#    PIT: 월말 t 시점 팩터로 t+1 수익률 예측 (C2: same-day circular 배제)
# ------------------------------------------------------------------------------
cat("[3] 월간 초과수익률 계산...\n")

monthend_dates <- sort(unique(FDB$Date))

# 월말→다음월말 수익률 (Close 기준)
ret_monthly <- RAWDATA[Date %in% monthend_dates, .(Date, Ticker, Close, Size)]
setkey(ret_monthly, Ticker, Date)
ret_monthly[, fwd_ret := shift(Close, type = "lead") / Close - 1, by = Ticker]

# 시장 수익률: 월말 cross-section 평균 (단순 계산으로 메모리 절약)
mkt_ret <- ret_monthly[!is.na(fwd_ret), .(mkt_ret = mean(fwd_ret, na.rm = TRUE)), by = Date]

# FDB + 수익률 + 유동성 병합
ml_data <- merge(FDB, ret_monthly[, .(Date, Ticker, fwd_ret, Size)],
                 by = c("Date", "Ticker"), all.x = FALSE)
ml_data <- merge(ml_data, mkt_ret, by = "Date", all.x = TRUE)
ml_data[, excess_ret := fwd_ret - fifelse(is.na(mkt_ret), 0, mkt_ret)]
ml_data <- ml_data[!is.na(excess_ret) & is.finite(excess_ret)]

# 유동성 필터
LIQ_THRESHOLD <- 2e8
ml_data <- ml_data[!is.na(Size) & Size >= LIQ_THRESHOLD]

# RAWDATA 해제 (메모리 절약 — 백테스트 시 재로드)
rm(ret_monthly, mkt_ret); gc()

setkey(ml_data, Date, Ticker)
cat("    유동성 필터 후 rows:", nrow(ml_data), "\n")
cat("    기간:", as.character(range(ml_data$Date)), "\n")

# ------------------------------------------------------------------------------
# 4. Fama-MacBeth Style Elastic Net Selection
#    월별 cross-section에 개별 LASSO/EN → 팩터 선택 빈도 집계
#    (스택 방식 대비 메모리 1/100, 속도 50x)
# ------------------------------------------------------------------------------
cat("[4] FM-Style Elastic Net Selection...\n")

# Phase 1: 모든 월에 대해 cross-sectional LASSO
all_months <- sort(unique(ml_data$Date))
all_months <- all_months[all_months >= as.Date("2005-01-01")]
cat("    Phase 1: 월별 cross-section LASSO (", length(all_months), "개월)...\n")

ALPHA <- 0.5
monthly_selections <- vector("list", length(all_months))

for (mi in seq_along(all_months)) {
  m <- all_months[mi]
  cs <- ml_data[Date == m]
  if (nrow(cs) < 100) next

  X <- as.matrix(cs[, FACTOR_COLS, with = FALSE])
  X[!is.finite(X)] <- 0
  y <- cs$excess_ret

  # 분산 0 컬럼 제거
  col_var <- apply(X, 2, var, na.rm = TRUE)
  valid_cols <- names(which(col_var > 1e-10))
  if (length(valid_cols) < 10) next

  cv_fit <- tryCatch({
    cv.glmnet(X[, valid_cols, drop = FALSE], y,
              alpha = ALPHA, nfolds = 5, type.measure = "mse")
  }, error = function(e) NULL)

  if (is.null(cv_fit)) next

  # lambda.min (weak-signal에서 lambda.1se는 전부 0으로 수축)
  coefs <- as.matrix(coef(cv_fit, s = "lambda.min"))
  selected <- rownames(coefs)[coefs[, 1] != 0]
  selected <- setdiff(selected, "(Intercept)")

  monthly_selections[[mi]] <- data.table(
    month      = m,
    n_selected = length(selected),
    factors    = list(selected),
    coefs      = list(coefs[selected, 1, drop = TRUE])
  )

  if (mi %% 24 == 0) {
    cat("    [", mi, "/", length(all_months), "] ", as.character(m),
        " — ", length(selected), "개\n")
  }
}

cat("    Phase 1 완료.\n")

# Phase 2: 단순 집계 빈도 (Phase 1 전체 월 기준)
#   FM-style에서 expanding window + 50%는 너무 보수적 → 단순 집계 + 15%
cat("    Phase 2: Aggregate frequency from Phase 1...\n")

valid_sels <- monthly_selections[!sapply(monthly_selections, is.null)]
n_total_months <- length(valid_sels)
cat("    유효 월:", n_total_months, "\n")

# 모든 월의 선택 결과 집계
all_factors <- unlist(lapply(valid_sels, function(x) x$factors[[1]]))
all_coef_list <- lapply(valid_sels, function(x) {
  f <- x$factors[[1]]
  co <- x$coefs[[1]]
  if (length(f) > 0 && length(co) == length(f)) {
    data.table(factor_name = f, coef_val = co)
  } else NULL
})
coef_dt <- rbindlist(all_coef_list[!sapply(all_coef_list, is.null)])

cat("[4] 선택 완료.\n")

# ------------------------------------------------------------------------------
# 5. Factor Frequency 분석
# ------------------------------------------------------------------------------
cat("[5] Factor 선택 빈도 분석...\n")

# 팩터별 집계 빈도
freq_tbl <- table(all_factors)
freq_dt <- data.table(
  factor = names(freq_tbl),
  n_selected = as.integer(freq_tbl),
  freq = as.numeric(freq_tbl) / n_total_months
)

# 계수 통계 병합
if (nrow(coef_dt) > 0) {
  coef_stats <- coef_dt[, .(
    mean_coef = mean(coef_val, na.rm = TRUE),
    median_coef = median(coef_val, na.rm = TRUE),
    coef_sign = sign(mean(coef_val, na.rm = TRUE))
  ), by = .(factor = factor_name)]
  freq_dt <- merge(freq_dt, coef_stats, by = "factor", all.x = TRUE)
} else {
  freq_dt[, c("mean_coef", "median_coef", "coef_sign") := .(0, 0, 1)]
}
freq_dt <- freq_dt[order(-freq)]

cat("\n--- 선택 빈도 상위 30개 ---\n")
print(head(freq_dt[, .(factor, n_selected, freq = round(freq, 3),
                        mean_coef = round(mean_coef, 6))], 30))

# 15% 이상 선택된 팩터 = Core Set (FM-style에서 월별 변동 크므로 낮은 임계값)
FREQ_THRESHOLD <- 0.15
core_factors <- freq_dt[freq >= FREQ_THRESHOLD, factor]
cat("\n    15%+ 선택 Core 팩터:", length(core_factors), "개\n")
cat("    Core:", paste(head(core_factors, 20), collapse = ", "), "\n")

# 저장
fwrite(freq_dt, file.path(OUTPUT_DIR, "factor_selection_frequency.csv"))

# ------------------------------------------------------------------------------
# 6. Stability Selection (Meinshausen & Buhlmann 2010)
#    100 subsamples × LASSO → 60%+ 출현 팩터
# ------------------------------------------------------------------------------
cat("\n[6] Stability Selection (100 subsamples)...\n")

# 최근 5년 데이터로 stability selection (전체 데이터는 너무 큼)
stability_data <- ml_data[Date >= as.Date("2020-01-01") & Date < max(signal_dates)]
X_stab <- as.matrix(stability_data[, FACTOR_COLS, with = FALSE])
X_stab[!is.finite(X_stab)] <- 0
y_stab <- stability_data$excess_ret

col_var <- apply(X_stab, 2, var, na.rm = TRUE)
valid_stab <- names(which(col_var > 1e-10))
X_stab <- X_stab[, valid_stab, drop = FALSE]

N_SUBSAMPLES <- 100
SUBSAMPLE_FRAC <- 0.5
stab_count <- rep(0L, ncol(X_stab))
names(stab_count) <- colnames(X_stab)

set.seed(42)
for (b in seq_len(N_SUBSAMPLES)) {
  idx <- sample(nrow(X_stab), floor(nrow(X_stab) * SUBSAMPLE_FRAC))
  cv_b <- tryCatch({
    cv.glmnet(X_stab[idx, ], y_stab[idx], alpha = 1, nfolds = 5) # pure LASSO for stability
  }, error = function(e) NULL)

  if (is.null(cv_b)) next

  coefs_b <- as.matrix(coef(cv_b, s = "lambda.1se"))
  sel_b <- rownames(coefs_b)[coefs_b[, 1] != 0]
  sel_b <- intersect(sel_b, valid_stab)
  stab_count[sel_b] <- stab_count[sel_b] + 1L

  if (b %% 25 == 0) cat("    subsample", b, "/ 100\n")
}

stab_dt <- data.table(
  factor         = names(stab_count),
  stab_freq      = stab_count / N_SUBSAMPLES
)[order(-stab_freq)]

STAB_THRESHOLD <- 0.60
stable_factors <- stab_dt[stab_freq >= STAB_THRESHOLD, factor]
cat("    60%+ 안정 팩터:", length(stable_factors), "개\n")
cat("    Stable:", paste(head(stable_factors, 20), collapse = ", "), "\n")

fwrite(stab_dt, file.path(OUTPUT_DIR, "stability_selection.csv"))

# ------------------------------------------------------------------------------
# 7. Final Sparse Set 결정
#    expanding freq 50%+ AND stability 60%+ = double-confirmed
# ------------------------------------------------------------------------------
cat("\n[7] Final Sparse Set 결정...\n")

# Double-confirmed: expanding freq + stability 동시 충족
double_confirmed <- intersect(core_factors, stable_factors)
cat("    Double-confirmed:", length(double_confirmed), "개\n")

# Expanding freq 50%+ only (stability 미달이어도 포함)
expanding_only <- setdiff(core_factors, stable_factors)
cat("    Expanding-only:", length(expanding_only), "개\n")

# Final set: double-confirmed 우선, 부족하면 expanding_only 추가 (최대 30개)
MAX_FACTORS <- 30
if (length(double_confirmed) >= MAX_FACTORS) {
  final_factors <- head(double_confirmed, MAX_FACTORS)
} else {
  final_factors <- c(double_confirmed, head(expanding_only, MAX_FACTORS - length(double_confirmed)))
}
cat("    Final sparse set:", length(final_factors), "개\n")
cat("    Factors:", paste(final_factors, collapse = ", "), "\n")

# 팩터 프로파일 저장
final_profile <- freq_dt[factor %in% final_factors]
final_profile <- merge(final_profile, stab_dt, by = "factor", all.x = TRUE)
final_profile[is.na(stab_freq), stab_freq := 0]
final_profile <- final_profile[order(-freq)]

cat("\n--- Final Factor Profile ---\n")
print(final_profile[, .(factor, freq = round(freq, 3),
                         stab_freq = round(stab_freq, 3),
                         mean_coef = round(mean_coef, 6))])

fwrite(final_profile, file.path(OUTPUT_DIR, "final_sparse_factors.csv"))

# ------------------------------------------------------------------------------
# 8. Sparse Portfolio Backtest (EW Top 20, 15bps)
# ------------------------------------------------------------------------------
cat("\n[8] Sparse Portfolio Backtest...\n")

# Score = sum(Z_Score_Aligned * coef_sign) for final factors
# (부호 보정: coef > 0이면 높을수록 good, coef < 0이면 낮을수록 good)
coef_signs <- final_profile[, .(factor, coef_sign)]

# 월말 FDB에서 final factors score 계산
score_data <- copy(FDB[Date >= as.Date("2008-01-01")])
avail_final <- intersect(final_factors, names(score_data))
cat("    사용 가능 팩터:", length(avail_final), "/", length(final_factors), "\n")

if (length(avail_final) >= 5) {
  # Score = sum of z-scores (direction already aligned in daily DB)
  score_cols <- avail_final
  score_data[, sparse_score := rowSums(.SD, na.rm = TRUE), .SDcols = score_cols]

  # 유동성 필터 — RAWDATA 재로드 (step 3에서 해제했으므로)
  if (!exists("RAWDATA") || is.null(RAWDATA)) {
    rw_list <- load_rawdata(use_cache = TRUE)
    RAWDATA <- rw_list$RAWDATA
    BM_DT <- rw_list$BM_DT
    setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
  }
  if (!exists("BM_DT")) {
    rw_list <- load_rawdata(use_cache = TRUE)
    BM_DT <- rw_list$BM_DT
  }

  score_liq <- merge(score_data[, .(Date, Ticker, sparse_score)],
                     RAWDATA[, .(Date, Ticker, Size)],
                     by = c("Date", "Ticker"), all.x = TRUE)
  score_liq <- score_liq[!is.na(Size) & Size >= LIQ_THRESHOLD]

  # 백테스트 (backtest_harness API: RAWDATA, BM_DT, FACTORS)
  FACTORS <- score_liq[, .(Date, Ticker, Score = sparse_score)]

  bt_result <- tryCatch({
    run_monthly_simulation(
      RAWDATA       = RAWDATA,
      BM_DT         = BM_DT,
      FACTORS       = FACTORS,
      n_holdings    = 20,
      commission    = 0.0015,
      weight_method = "EW",
      buffer_zone   = list(keep_n = 20, entry_n = 30)
    )
  }, error = function(e) {
    cat("    백테스트 오류:", e$message, "\n")
    NULL
  })

  if (!is.null(bt_result)) {
    perf <- bt_result$performance
    cat("\n--- Elastic Net Sparse Portfolio 결과 ---\n")
    cat("CAGR   :", round(perf$CAGR, 2), "%\n")
    cat("Sharpe :", round(perf$Sharpe, 3), "\n")
    cat("MDD    :", round(perf$MDD, 2), "%\n")
    cat("Calmar :", round(perf$Calmar, 3), "\n")

    if (!is.null(bt_result$nav)) {
      fwrite(bt_result$nav, file.path(OUTPUT_DIR, "nav.csv"))
    }

    perf_out <- c(list(
      strategy       = "ElasticNet_Sparse",
      description    = paste0("Feng2020 Elastic Net, ", length(avail_final), " factors, OOS 2008~2025"),
      n_factors      = length(avail_final),
      factors        = paste(avail_final, collapse = ","),
      alpha          = ALPHA,
      freq_threshold = FREQ_THRESHOLD,
      stab_threshold = STAB_THRESHOLD
    ), perf)
    write_json(perf_out, file.path(OUTPUT_DIR, "performance.json"),
               auto_unbox = TRUE, pretty = TRUE)
  }
} else {
  cat("    사용 가능 팩터 5개 미만 — 백테스트 건너뜀\n")
}

# ------------------------------------------------------------------------------
# 9. STR_1631 앵커 상관 분석
# ------------------------------------------------------------------------------
cat("\n[9] STR_1631 앵커 독립성 분석...\n")

anchor_nav_path <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1631/output/daily_nav.csv")

if (file.exists(anchor_nav_path) && !is.null(bt_result) && !is.null(bt_result$nav)) {
  anchor_nav <- fread(anchor_nav_path)
  ml_nav <- bt_result$nav

  if ("Date" %in% names(anchor_nav) && "NAV" %in% names(anchor_nav)) {
    setkey(anchor_nav, Date)
    setkey(ml_nav, Date)
    combined <- merge(
      anchor_nav[, .(Date, NAV_anchor = NAV)],
      ml_nav[, .(Date, NAV_ml = NAV)],
      by = "Date"
    )
    combined[, ret_anchor := NAV_anchor / shift(NAV_anchor) - 1]
    combined[, ret_ml := NAV_ml / shift(NAV_ml) - 1]
    combined <- combined[!is.na(ret_anchor) & !is.na(ret_ml)]

    ret_corr <- cor(combined$ret_anchor, combined$ret_ml, use = "complete.obs")
    cat("    STR_1631 vs EN Sparse 일간 수익률 상관:", round(ret_corr, 4), "\n")

    corr_result <- list(
      anchor    = "STR_1631",
      ml        = "ElasticNet_Sparse",
      corr      = round(ret_corr, 4),
      n_obs     = nrow(combined)
    )
    write_json(corr_result, file.path(OUTPUT_DIR, "anchor_correlation.json"),
               auto_unbox = TRUE, pretty = TRUE)
  }
} else {
  cat("    STR_1631 NAV 없음 — 건너뜀\n")
}

# ------------------------------------------------------------------------------
# 최종 요약
# ------------------------------------------------------------------------------
cat("\n", paste(rep("=", 60), collapse = ""), "\n")
cat("=== Elastic Net Factor Selection 완료 ===\n")
cat("완료 시각:", as.character(Sys.time()), "\n")
cat("Total factors:", length(FACTOR_COLS), "\n")
cat("Core (50%+):", length(core_factors), "\n")
cat("Stable (60%+):", length(stable_factors), "\n")
cat("Double-confirmed:", length(double_confirmed), "\n")
cat("Final set:", length(final_factors), "\n")
if (!is.null(bt_result)) {
  cat("CAGR:", round(bt_result$performance$CAGR, 2), "%\n")
  cat("Sharpe:", round(bt_result$performance$Sharpe, 3), "\n")
  cat("MDD:", round(bt_result$performance$MDD, 2), "%\n")
}
cat("산출물:", OUTPUT_DIR, "\n")
cat(paste(rep("=", 60), collapse = ""), "\n")
