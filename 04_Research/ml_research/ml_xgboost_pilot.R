## =============================================================================
## ML XGBoost Pilot — 일간 Factor DB × Non-linear Alpha
## STR_1631 C19 앵커와 독립적인 ML signal 생성
##
## 핵심 아이디어:
##   일간 309팩터를 XGBoost walk-forward으로 학습, non-linear 조합을 통해
##   linear z-score 기반 전략이 놓치는 alpha 추출.
##   MC1~MC5 ML 규칙 + C1~C9 PIT 규칙 완전 준수.
##
## MC1: Walk-forward expanding window
## MC2: Purged CV (train/val 21일 gap)
## MC3: Target = t+1~t+21 수익률 (PIT: 미래 21거래일)
## MC4: Feature = t 시점까지 정보만 (lag 없음, daily DB가 이미 t-1 기준)
## MC5: 튜닝 = validation set에서만
##
## PIT 체크:
##   Q1: 일간 Factor DB 값은 해당 거래일 종가 기준으로 산출됨 → t 시점 알 수 있음
##   Q2: Target은 t+1 다음날부터 t+21까지 수익률 → 미래 영향 없음
##   Q3: Walk-forward expanding → full-sample 통계 없음
## =============================================================================

cat("=== ML XGBoost Pilot: 일간 Factor DB × Non-linear Alpha ===\n")
cat("PIT Rules: MC1~MC5 + C1~C9 완전 준수\n")
cat("시작 시각:", as.character(Sys.time()), "\n\n")

# ------------------------------------------------------------------------------
# 0. 라이브러리 로드
# ------------------------------------------------------------------------------
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(xgboost)
  library(jsonlite)
})

# 프로젝트 루트 (normalizePath 금지 — WSL 한글 경로 버그)
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
DAILY_DB_DIR <- file.path(PROJECT_ROOT, ".cache/factor_db_daily")
OUTPUT_DIR   <- file.path(PROJECT_ROOT, "04_Research/ml_xgboost_pilot_output")
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

# ------------------------------------------------------------------------------
# 1. RAWDATA 1회 로드 (use_cache=TRUE)
# ------------------------------------------------------------------------------
cat("[1] RAWDATA 로드...\n")
rw_list   <- load_rawdata(use_cache = TRUE)
RAWDATA   <- rw_list$RAWDATA
setDT(RAWDATA)
setkey(RAWDATA, Date, Ticker)

# Ret 컬럼 확인
stopifnot("Ret" %in% names(RAWDATA))
cat("    RAWDATA rows:", nrow(RAWDATA), "| 기간:", as.character(min(RAWDATA$Date)), "~", as.character(max(RAWDATA$Date)), "\n")

# ------------------------------------------------------------------------------
# 2. 일간 Factor DB 로드 (2003년 이후, 메모리 효율)
#    Wide format: Date × Ticker × 425컬럼
#    2003~2025 = 약 23년 × 12개월 = 276 파일
# ------------------------------------------------------------------------------
cat("[2] 일간 Factor DB 로드 (2003~2025)...\n")

# 사용할 팩터 컬럼: Date, Ticker + alpha factor들만 (RE_/raw 재무 제외)
EXCLUDE_PREFIXES <- c("RE_", "dps_1y", "bps_1y", "eps_1y", "target_price")
# Composite 컬럼 (.x/.y 중복 제거: .x는 raw, .y는 z-score로 가정)
# → .y 컬럼이 Z_Score_Aligned 기준 (C13 준수)

# 파일 목록 (2003년 1월 이후)
# 파일명: fdb_daily_YYYYMM.parquet → regex로 YYYYMM 추출
all_files <- sort(list.files(DAILY_DB_DIR, pattern = "fdb_daily_\\d{6}\\.parquet$", full.names = TRUE))
ym_str     <- sub("fdb_daily_([0-9]{6})\\.parquet", "\\1", basename(all_files))
ym_int     <- as.integer(ym_str)
# 2003년 1월 이후, 2026년 4월 이하만
target_files <- all_files[!is.na(ym_int) & ym_int >= 200301 & ym_int <= 202604]

cat("    로드할 파일 수:", length(target_files), "\n")

# 첫 파일에서 컬럼 구조 파악
sample_dt <- as.data.table(read_parquet(target_files[1]))
all_cols   <- names(sample_dt)

# 제외 컬럼 결정
excl_cols <- c(
  grep(paste(EXCLUDE_PREFIXES, collapse="|"), all_cols, value=TRUE),
  # .x 컬럼 제거 (z-score .y만 사용, C13)
  grep("\\.x$", all_cols, value=TRUE)
)

keep_cols <- setdiff(all_cols, excl_cols)
cat("    유지 컬럼 수:", length(keep_cols), "(Date, Ticker 포함)\n")

# 팩터 컬럼 (Date, Ticker 제외)
FACTOR_COLS <- setdiff(keep_cols, c("Date", "Ticker"))
cat("    팩터 컬럼 수:", length(FACTOR_COLS), "\n")

# 월말 마지막 거래일만 로드 (37.5GB → 1.76GB 메모리 최적화)
# XGBoost는 월말 데이터로 학습·예측하므로 일간 전체 불필요
gc_before <- gc(reset=TRUE)

fdb_list <- vector("list", length(target_files))
for (i in seq_along(target_files)) {
  tmp <- as.data.table(read_parquet(target_files[i]))
  # 월말 마지막 거래일만 추출 (일간→월말 압축)
  monthend_date <- max(tmp$Date)
  tmp <- tmp[Date == monthend_date]
  # 해당 파일에 존재하는 keep_cols만 선택
  avail <- intersect(keep_cols, names(tmp))
  fdb_list[[i]] <- tmp[, avail, with=FALSE]
  rm(tmp)
  if (i %% 60 == 0) cat("    ...", i, "/", length(target_files), "파일 로드 완료\n")
}

FDB <- rbindlist(fdb_list, use.names = TRUE, fill = TRUE)
rm(fdb_list); gc()

# .y 접미사 제거 (rename): 먼저 .y 컬럼을 rename, 그 후 중복 제거
old_y <- grep("\\.y$", names(FDB), value=TRUE)
new_y <- sub("\\.y$", "", old_y)
# 이미 동명 컬럼이 있는 경우 → .y 버전은 제거 (C13: Z_Score_Aligned .y가 이미 있을 경우 skip)
already_exists <- new_y[new_y %in% setdiff(names(FDB), old_y)]
remove_y_dups  <- old_y[new_y %in% already_exists]   # 이미 원본이 있으면 .y 제거
rename_y       <- old_y[!(new_y %in% already_exists)] # 원본 없는 경우만 rename
if (length(remove_y_dups) > 0) FDB[, (remove_y_dups) := NULL]
if (length(rename_y) > 0)      setnames(FDB, rename_y, sub("\\.y$", "", rename_y), skip_absent=TRUE)

# 중복 컬럼 최종 제거
dup_cols <- names(FDB)[duplicated(names(FDB))]
if (length(dup_cols) > 0) FDB[, (dup_cols) := NULL]

# FACTOR_COLS 재계산 (현재 FDB 컬럼 기준)
FACTOR_COLS <- setdiff(names(FDB), c("Date", "Ticker",
                 grep("^RE_", names(FDB), value=TRUE),
                 grep("dps_1y|bps_1y|eps_1y|target_price", names(FDB), value=TRUE)))
FACTOR_COLS <- unique(FACTOR_COLS)

setkey(FDB, Date, Ticker)
cat("    FDB rows:", nrow(FDB), "| 기간:", as.character(min(FDB$Date)), "~", as.character(max(FDB$Date)), "\n")
cat("    FDB 팩터 컬럼:", length(FACTOR_COLS), "\n")

# ------------------------------------------------------------------------------
# 3. Target 생성: t+1 ~ t+21 수익률 (PIT 완전 준수)
#    - signal_date = t (Factor DB 날짜)
#    - 다음날(t+1)부터 21거래일 누적 수익률
#    - C2 준수: same-day circular 완전 배제
# ------------------------------------------------------------------------------
cat("[3] Target 생성 (t+1~t+21 순방향 수익률)...\n")

# 종목별 일간 수익률
ret_dt <- RAWDATA[Date >= as.Date("2003-01-01"), .(Date, Ticker, Ret)]
setkey(ret_dt, Ticker, Date)

# 21거래일 순방향 누적 수익률 계산 (벡터화 — cumsum 역산 방식)
# PIT: Date = signal 시점 t, fwd_ret = (t+1 ~ t+21) 수익률
# cumlog[i+21] - cumlog[i] = sum(log(1+Ret)) from i+1 to i+21
ret_dt[, log_ret := log(1 + Ret)]
ret_dt[, fwd_ret_21d := {
  n <- .N
  if (n <= 21L) {
    rep(NA_real_, n)
  } else {
    cl  <- cumsum(log_ret)
    # cl[i+21] - cl[i] = sum(log(1+Ret)) from i+1 to i+21
    fwd <- c(cl[22:n], rep(NA_real_, 21L)) - cl
    exp(fwd) - 1
  }
}, by = Ticker]
ret_dt[, log_ret := NULL]

cat("    Target 계산 완료. NA 비율:", round(mean(is.na(ret_dt$fwd_ret_21d)), 3), "\n")

# ------------------------------------------------------------------------------
# 4. FDB + Target 병합
# ------------------------------------------------------------------------------
cat("[4] FDB + Target 병합...\n")

ml_data <- merge(FDB, ret_dt[, .(Date, Ticker, fwd_ret_21d)],
                 by = c("Date", "Ticker"), all.x = FALSE)

# 유동성 필터: Size (거래대금) >= 2억원
# FDB에 없으므로 RAWDATA에서 가져옴
liq_dt <- RAWDATA[, .(Date, Ticker, Size, Vol, Close)]
ml_data <- merge(ml_data, liq_dt, by = c("Date", "Ticker"), all.x = TRUE)

# 실제 사용 팩터 컬럼 (Size, Vol, Close는 target이므로 제외)
# FACTOR_COLS에서 이미 있는 것만 유지
FACTOR_COLS <- intersect(FACTOR_COLS, names(ml_data))
cat("    병합 후 팩터 컬럼 수:", length(FACTOR_COLS), "\n")
cat("    병합 후 데이터 rows:", nrow(ml_data), "\n")

# 타겟 없는 행 제거
ml_data <- ml_data[!is.na(fwd_ret_21d)]
cat("    Target 있는 rows:", nrow(ml_data), "\n")

# 날짜 기준 정렬
setkey(ml_data, Date, Ticker)

# ------------------------------------------------------------------------------
# 5. 월말 집약 (월간 리밸런싱 기준)
#    일간 ML score → 월말 마지막 거래일 평균 score → Top 20 선택
#    Walk-forward에서 학습은 일간 단위, 리밸런싱은 월말
# ------------------------------------------------------------------------------
cat("[5] 월말 날짜 인덱스 생성...\n")

ml_data[, YearMonth := format(Date, "%Y-%m")]
# 월말 마지막 거래일
monthend_dates <- ml_data[, .(monthend = max(Date)), by = YearMonth][order(YearMonth)]
cat("    월말 날짜 수:", nrow(monthend_dates), "\n")
# monthend_dates$monthend 벡터로 필터 (merge 대신 %in% 사용 → YearMonth 충돌 방지)
MONTHEND_SET <- monthend_dates$monthend

# ------------------------------------------------------------------------------
# 6. Walk-forward XGBoost 학습
#    - IS 최소: 2003~2007 (5년 = 60개월)
#    - 매년 1회 재학습 (연간 expanding)
#    - Validation: 직전 12개월 (IS에서 purged 21일 gap)
#    - OOS: 다음 12개월
#    - feature: 당월 말일 팩터 값
# ------------------------------------------------------------------------------
cat("[6] Walk-forward XGBoost 학습 시작...\n")
cat("    학습 구조: IS 최소 5년 → 매년 expanding → val 12개월 (21일 purge) → OOS 12개월\n\n")

# 월말 데이터만 추출 (학습·예측 feature) — %in% 필터로 YearMonth 충돌 방지
monthend_data <- ml_data[Date %in% MONTHEND_SET]
cat("    월말 데이터 rows:", nrow(monthend_data), "\n")

# 연도 목록
years_all <- unique(format(monthend_data$Date, "%Y"))
years_all <- sort(years_all)
# IS 시작: 2003, OOS 시작: 2008 (IS 5년 확보)
train_start_year <- "2003"
oos_start_year   <- "2008"

oos_year_list <- years_all[years_all >= oos_start_year & years_all <= "2025"]
cat("    OOS 연도:", paste(oos_year_list, collapse=", "), "\n\n")

# XGBoost 고정 파라미터 (MC5: val에서만 튜닝)
XGB_PARAMS <- list(
  booster            = "gbtree",
  objective          = "reg:squarederror",
  eta                = 0.02,
  max_depth          = 5,
  subsample          = 0.7,
  colsample_bytree   = 0.5,
  min_child_weight   = 10,
  lambda             = 1.0,
  alpha              = 0.1
)
XGB_NROUNDS <- 500
XGB_EARLY_STOP <- 50

# 결과 저장
oos_scores_list  <- vector("list", length(oos_year_list))
feature_imp_list <- vector("list", length(oos_year_list))
val_metrics_list <- vector("list", length(oos_year_list))

for (yi in seq_along(oos_year_list)) {
  oos_yr <- oos_year_list[yi]
  cat("  [OOS", oos_yr, "] 학습 중...\n")

  # IS 기간: 2003-01 ~ (oos_yr-2년) 12월
  is_end_yr   <- as.integer(oos_yr) - 2
  val_end_yr  <- as.integer(oos_yr) - 1
  is_end_ym   <- sprintf("%d-12", is_end_yr)

  # Validation 기간: (oos_yr-1년) 01 ~ (oos_yr-1년) 12
  #   단, IS 마지막 날로부터 21거래일 purge gap 적용 (MC2)
  val_start_ym <- sprintf("%d-02", as.integer(oos_yr) - 1)  # 1개월 추가 gap (실용적 purge)
  val_end_ym   <- sprintf("%d-12", val_end_yr)

  # OOS 기간: oos_yr-01 ~ oos_yr-12
  oos_start_ym <- sprintf("%s-01", oos_yr)
  oos_end_ym   <- sprintf("%s-12", oos_yr)

  # 데이터 분할
  is_dt  <- monthend_data[YearMonth <= is_end_ym]
  val_dt <- monthend_data[YearMonth >= val_start_ym & YearMonth <= val_end_ym]
  oos_dt <- monthend_data[YearMonth >= oos_start_ym & YearMonth <= oos_end_ym]

  if (nrow(is_dt) == 0 || nrow(val_dt) == 0 || nrow(oos_dt) == 0) {
    cat("    데이터 부족 - 건너뜀\n")
    next
  }

  cat("    IS rows:", nrow(is_dt), "| Val rows:", nrow(val_dt), "| OOS rows:", nrow(oos_dt), "\n")

  # Feature 행렬 생성
  build_xmat <- function(dt) {
    # 팩터 컬럼에서 Inf, NaN → NA로 정리
    feat_mat <- as.matrix(dt[, FACTOR_COLS, with=FALSE])
    feat_mat[!is.finite(feat_mat)] <- NA_real_
    # NA → 0 대체 (XGBoost na.rm 내장이지만 명시적으로)
    feat_mat[is.na(feat_mat)] <- 0
    feat_mat
  }

  X_is  <- build_xmat(is_dt)
  y_is  <- is_dt$fwd_ret_21d
  X_val <- build_xmat(val_dt)
  y_val <- val_dt$fwd_ret_21d
  X_oos <- build_xmat(oos_dt)

  # DMatrix
  dtrain <- xgb.DMatrix(data = X_is,  label = y_is)
  dval   <- xgb.DMatrix(data = X_val, label = y_val)
  doos   <- xgb.DMatrix(data = X_oos)

  # 학습 (MC5: early stopping on val)
  xgb_model <- tryCatch({
    xgb.train(
      params             = XGB_PARAMS,
      data               = dtrain,
      nrounds            = XGB_NROUNDS,
      evals              = list(val = dval),
      early_stopping_rounds = XGB_EARLY_STOP,
      verbose            = 0
    )
  }, error = function(e) {
    cat("    XGBoost 학습 오류:", e$message, "\n")
    NULL
  })

  if (is.null(xgb_model)) next

  best_iter <- xgb_model$best_iteration
  cat("    Best iter:", best_iter, "\n")

  # Validation 성능
  val_pred <- predict(xgb_model, dval)
  val_ic   <- tryCatch(cor(val_pred, y_val, method="spearman"), error=function(e) NA)
  cat("    Val IC (rank):", round(val_ic, 4), "\n")

  val_metrics_list[[yi]] <- data.table(
    oos_year = oos_yr,
    val_IC   = val_ic,
    best_iter = best_iter
  )

  # OOS 예측 (ML score)
  oos_pred <- predict(xgb_model, doos)
  oos_dt_score <- copy(oos_dt[, .(Date, Ticker, YearMonth, fwd_ret_21d)])
  oos_dt_score[, ml_score := oos_pred]

  oos_scores_list[[yi]] <- oos_dt_score

  # Feature importance (gain)
  imp <- xgb.importance(feature_names = FACTOR_COLS, model = xgb_model)
  imp[, oos_year := oos_yr]
  feature_imp_list[[yi]] <- imp

  # 모델 저장 (연도별)
  model_path <- file.path(OUTPUT_DIR, sprintf("xgb_model_%s.rds", oos_yr))
  saveRDS(xgb_model, model_path)
  cat("    모델 저장:", model_path, "\n\n")
}

# ------------------------------------------------------------------------------
# 7. OOS ML 스코어 통합
# ------------------------------------------------------------------------------
cat("[7] OOS ML 스코어 통합...\n")

oos_all <- rbindlist(oos_scores_list, use.names=TRUE, fill=TRUE)
cat("    OOS 총 rows:", nrow(oos_all), "\n")
cat("    OOS 기간:", as.character(min(oos_all$Date)), "~", as.character(max(oos_all$Date)), "\n")

# 월별 IC 계산 (OOS)
oos_ic_monthly <- oos_all[, .(
  IC = cor(ml_score, fwd_ret_21d, method="spearman", use="complete.obs"),
  N  = .N
), by = YearMonth]

overall_ic   <- mean(oos_ic_monthly$IC, na.rm=TRUE)
overall_icsd <- sd(oos_ic_monthly$IC, na.rm=TRUE)
overall_icir <- overall_ic / overall_icsd

cat("    OOS IC (월평균):", round(overall_ic, 4), "\n")
cat("    OOS IC_SD:", round(overall_icsd, 4), "\n")
cat("    OOS ICIR:", round(overall_icir, 4), "\n")

# 월별 IC 저장
fwrite(oos_ic_monthly, file.path(OUTPUT_DIR, "oos_ic_monthly.csv"))

# ------------------------------------------------------------------------------
# 8. 월말 Top 20 포트폴리오 구성
#    - 월말 마지막 거래일 ml_score 기준 상위 20종목
#    - 유동성 필터: Size >= 2억원
#    - buffer_zone(30, 20): 신규 진입 30위 이내, 유지 20위 이내
# ------------------------------------------------------------------------------
cat("[8] 월말 Top 20 포트폴리오 구성...\n")

# 유동성 필터 적용
oos_all_liq <- merge(
  oos_all,
  RAWDATA[, .(Date, Ticker, Size)],
  by = c("Date", "Ticker"),
  all.x = TRUE
)
# 20일 평균 거래대금 >= 2억원 필터 (Size 컬럼 = 거래대금)
# Size가 이미 일간 거래대금이라고 가정 (config.R 기준)
LIQ_THRESHOLD <- 2e8

# 월별 포트폴리오
monthly_port <- oos_all_liq[
  !is.na(ml_score) & !is.na(Size) & Size >= LIQ_THRESHOLD
][
  order(Date, -ml_score)
][
  , rank := seq_len(.N), by = .(Date, YearMonth)
][rank <= 30]  # buffer: 30위까지 후보

# 월별 선택 종목 저장
fwrite(monthly_port, file.path(OUTPUT_DIR, "monthly_portfolio_scores.csv"))
cat("    월별 포트폴리오 저장 완료\n")

# ------------------------------------------------------------------------------
# 9. 백테스트: run_monthly_simulation()
#    N=20, EW, commission=15bps, buffer_zone(30, 20)
# ------------------------------------------------------------------------------
cat("[9] 백테스트 실행...\n")

# 포트폴리오 시그널 (Date, Ticker, Score)
# monthly_port는 이미 유동성 필터 통과 + 상위 30위
signal_for_bt <- monthly_port[, .(Date, Ticker, Score = ml_score)]

bt_result <- tryCatch({
  run_monthly_simulation(
    signal_dt      = signal_for_bt,
    rawdata        = RAWDATA,
    n_stocks       = 20,
    weight_method  = "EW",
    commission     = 0.0015,
    buffer_zone    = list(keep_n = 20, entry_n = 30),
    start_date     = as.Date("2008-01-01"),
    end_date       = as.Date("2025-12-31"),
    verbose        = TRUE
  )
}, error = function(e) {
  cat("    백테스트 오류:", e$message, "\n")
  NULL
})

if (!is.null(bt_result)) {
  perf <- bt_result$performance
  cat("\n--- ML XGBoost 백테스트 결과 ---\n")
  cat("CAGR   :", round(perf$CAGR,   2), "%\n")
  cat("Sharpe :", round(perf$Sharpe, 3), "\n")
  cat("MDD    :", round(perf$MDD,    2), "%\n")
  cat("Calmar :", round(perf$Calmar, 3), "\n")
  cat("WinRate:", round(perf$WinRate, 1), "%\n")

  # NAV 저장
  if (!is.null(bt_result$nav)) {
    fwrite(bt_result$nav, file.path(OUTPUT_DIR, "nav.csv"))
  }

  # 성과 JSON 저장
  perf_out <- c(
    list(
      strategy    = "ML_XGBoost_Pilot",
      description = "일간 309팩터 XGBoost Walk-forward, OOS 2008~2025",
      IC_monthly  = round(overall_ic, 4),
      ICIR_monthly = round(overall_icir, 4)
    ),
    perf
  )
  write_json(perf_out, file.path(OUTPUT_DIR, "performance.json"), auto_unbox=TRUE, pretty=TRUE)
  cat("\n성과 저장:", file.path(OUTPUT_DIR, "performance.json"), "\n")
}

# ------------------------------------------------------------------------------
# 10. Feature Importance 분석 (SHAP 대체: XGBoost gain)
#     상위 20개 특성
# ------------------------------------------------------------------------------
cat("[10] Feature Importance 분석...\n")

if (length(feature_imp_list) > 0) {
  imp_all <- rbindlist(feature_imp_list, use.names=TRUE, fill=TRUE)
  # 연도별 평균 gain
  imp_avg <- imp_all[, .(
    mean_gain  = mean(Gain,  na.rm=TRUE),
    mean_cover = mean(Cover, na.rm=TRUE),
    n_years    = .N
  ), by = Feature][order(-mean_gain)]

  cat("\n--- Top 20 Feature (평균 Gain 기준) ---\n")
  print(head(imp_avg[, .(Feature, mean_gain, n_years)], 20))

  fwrite(imp_avg, file.path(OUTPUT_DIR, "feature_importance_avg.csv"))
  fwrite(imp_all, file.path(OUTPUT_DIR, "feature_importance_yearly.csv"))
}

# ------------------------------------------------------------------------------
# 11. STR_1631 앵커와의 상관 분석
#     STR_1631 daily_nav.csv와 ML NAV 비교
# ------------------------------------------------------------------------------
cat("[11] STR_1631 C19 앵커 독립성 분석...\n")

anchor_nav_path <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1631/output/daily_nav.csv")

if (file.exists(anchor_nav_path) && !is.null(bt_result) && !is.null(bt_result$nav)) {
  anchor_nav <- fread(anchor_nav_path)
  ml_nav     <- bt_result$nav

  # 공통 기간 병합
  if ("Date" %in% names(anchor_nav) && "NAV" %in% names(anchor_nav)) {
    setkey(anchor_nav, Date)
    setkey(ml_nav,     Date)

    combined <- merge(
      anchor_nav[, .(Date, NAV_anchor = NAV)],
      ml_nav[, .(Date, NAV_ml = NAV)],
      by = "Date"
    )

    # 일간 수익률 상관
    combined[, ret_anchor := NAV_anchor / shift(NAV_anchor) - 1]
    combined[, ret_ml     := NAV_ml     / shift(NAV_ml)     - 1]
    combined <- combined[!is.na(ret_anchor) & !is.na(ret_ml)]

    ret_corr <- cor(combined$ret_anchor, combined$ret_ml, use="complete.obs")
    cat("    STR_1631 vs ML XGBoost 일간 수익률 상관:", round(ret_corr, 4), "\n")

    if (abs(ret_corr) < 0.3) {
      cat("    -> max_corr < 0.3: Novelty Bonus +15 조건 충족 가능\n")
    } else if (abs(ret_corr) < 0.5) {
      cat("    -> max_corr < 0.5: Novelty Bonus +5~8 조건 충족 가능\n")
    } else {
      cat("    -> 상관 높음 (", round(ret_corr, 4), "). 독립성 부족.\n")
    }

    corr_result <- list(
      anchor_strategy = "STR_1631",
      ml_strategy     = "ML_XGBoost_Pilot",
      daily_ret_corr  = round(ret_corr, 4),
      n_obs           = nrow(combined),
      period_start    = as.character(min(combined$Date)),
      period_end      = as.character(max(combined$Date))
    )
    write_json(corr_result, file.path(OUTPUT_DIR, "anchor_correlation.json"),
               auto_unbox=TRUE, pretty=TRUE)
  } else {
    cat("    STR_1631 NAV 컬럼 구조 불일치 - 상관 분석 건너뜀\n")
    cat("    anchor_nav cols:", paste(names(anchor_nav), collapse=", "), "\n")
  }
} else {
  cat("    STR_1631 NAV 파일 없음 또는 백테스트 실패 - 상관 분석 건너뜀\n")
}

# ------------------------------------------------------------------------------
# 12. Validation 메트릭 요약
# ------------------------------------------------------------------------------
cat("[12] Validation 메트릭 요약...\n")

val_metrics_all <- rbindlist(val_metrics_list, use.names=TRUE, fill=TRUE)
if (nrow(val_metrics_all) > 0) {
  cat("\n--- Validation IC by OOS Year ---\n")
  print(val_metrics_all)
  fwrite(val_metrics_all, file.path(OUTPUT_DIR, "val_metrics_by_year.csv"))

  cat("\n평균 Val IC:", round(mean(val_metrics_all$val_IC, na.rm=TRUE), 4), "\n")
  cat("IS vs OOS IC gap 분석:\n")
  cat("  Val IC 평균:", round(mean(val_metrics_all$val_IC, na.rm=TRUE), 4), "\n")
  cat("  OOS IC 전체:", round(overall_ic, 4), "\n")
  cat("  IC gap:", round(mean(val_metrics_all$val_IC, na.rm=TRUE) - overall_ic, 4), "\n")
}

# ------------------------------------------------------------------------------
# 최종 요약
# ------------------------------------------------------------------------------
cat("\n", paste(rep("=", 60), collapse=""), "\n")
cat("=== ML XGBoost Pilot 완료 ===\n")
cat("완료 시각:", as.character(Sys.time()), "\n")
cat("OOS IC    :", round(overall_ic, 4), "\n")
cat("OOS ICIR  :", round(overall_icir, 4), "\n")
if (!is.null(bt_result)) {
  cat("CAGR      :", round(bt_result$performance$CAGR, 2), "%\n")
  cat("Sharpe    :", round(bt_result$performance$Sharpe, 3), "\n")
  cat("MDD       :", round(bt_result$performance$MDD, 2), "%\n")
}
cat("산출물 경로:", OUTPUT_DIR, "\n")
cat(paste(rep("=", 60), collapse=""), "\n")
