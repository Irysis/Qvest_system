## =============================================================================
## ML Overnight Research — L-123 Full Pipeline
## 데이터 1회 로드 → 5개 모델 순차 → 리스크 엔진 → 비교 → S0 자동 판정
##
## Models: Ridge / ElasticNet / XGBoost / Random Forest / Ensemble
## L-123: IC prefilter(50) + 일간 5yr window + walk-forward + purged CV
## Risk: tail_risk_suite + stress period + regime correlation
## =============================================================================

cat("=== ML OVERNIGHT RESEARCH START ===\n")
cat("시작:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(glmnet)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
DAILY_DB_DIR <- file.path(PROJECT_ROOT, ".cache/factor_db_daily")
OUTPUT_BASE  <- file.path(PROJECT_ROOT, "04_Research/ml_overnight_output")
dir.create(OUTPUT_BASE, showWarnings = FALSE, recursive = TRUE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

# Risk engine
TAIL_RISK_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure/portfolio/tail_risk_engine.R")
if (file.exists(TAIL_RISK_PATH)) {
  tryCatch(source(TAIL_RISK_PATH), error = function(e) cat("WARN: tail_risk load:", e$message, "\n"))
}

LIQ_THRESHOLD <- 2e8
LAMBDA_GRID <- c(1, 0.1, 0.01, 0.001, 0.0001)
OOS_YEARS <- as.character(2008:2025)

# ==============================================================================
# 1. RAWDATA + Target 사전 계산 (1회)
# ==============================================================================
cat("[LOAD] RAWDATA...\n")
rw_list <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw_list$RAWDATA; BM_DT <- rw_list$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)

cat("[LOAD] 21d forward returns...\n")
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
# 2. Factor DB 컬럼 구조 + 파일 인덱스
# ==============================================================================
EXCLUDE_PREFIXES <- c("RE_", "dps_1y", "bps_1y", "eps_1y", "target_price")
all_files <- sort(list.files(DAILY_DB_DIR, pattern = "fdb_daily_\\d{6}\\.parquet$", full.names = TRUE))
ym_int <- as.integer(sub("fdb_daily_([0-9]{6})\\.parquet", "\\1", basename(all_files)))

sample_dt <- as.data.table(read_parquet(all_files[which(ym_int == 200301)]))
excl_cols <- c(grep(paste(EXCLUDE_PREFIXES, collapse = "|"), names(sample_dt), value = TRUE),
               grep("\\.x$", names(sample_dt), value = TRUE))
keep_cols <- setdiff(names(sample_dt), excl_cols)
FACTOR_COLS_BASE <- setdiff(keep_cols, c("Date", "Ticker"))
rm(sample_dt); gc()
cat("[LOAD] Factor columns:", length(FACTOR_COLS_BASE), "\n")

# ==============================================================================
# 유틸 함수들
# ==============================================================================
load_daily_chunk <- function(start_ym, end_ym) {
  idx <- which(ym_int >= start_ym & ym_int <= end_ym)
  if (length(idx) == 0) return(NULL)
  chunks <- lapply(all_files[idx], function(f) {
    tmp <- as.data.table(read_parquet(f))
    avail <- intersect(keep_cols, names(tmp))
    tmp[, avail, with = FALSE]
  })
  dt <- rbindlist(chunks, use.names = TRUE, fill = TRUE)
  rm(chunks)
  # .y cleanup
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

ic_prefilter <- function(dt, fcols, n_top = 50) {
  me <- dt[, .SD[Date == max(Date)], by = format(Date, "%Y-%m")]
  ics <- sapply(fcols, function(f) {
    x <- me[[f]]; y <- me$fwd_ret_21d
    v <- is.finite(x) & is.finite(y)
    if (sum(v) < 100) return(NA_real_)
    tryCatch(cor(x[v], y[v], method = "spearman"), error = function(e) NA_real_)
  })
  ics <- ics[!is.na(ics)]
  names(sort(abs(ics), decreasing = TRUE))[seq_len(min(n_top, length(ics)))]
}

build_mat <- function(dt, cols) {
  m <- as.matrix(dt[, cols, with = FALSE])
  m[!is.finite(m)] <- 0
  m
}

run_bt_from_scores <- function(score_dt, label) {
  dt <- copy(score_dt)
  if (!"Score" %in% names(dt)) return(NULL)
  dt <- dt[!is.na(Score) & !is.na(Size) & Size >= LIQ_THRESHOLD]
  dt[, rank := frank(-Score, ties.method = "first"), by = Date]
  dt <- dt[rank <= 30]
  FACTORS <- dt[, .(Date, Ticker, Score)]
  bt <- tryCatch({
    run_monthly_simulation(RAWDATA, BM_DT, FACTORS, n_holdings = 20,
      commission = 0.0015, weight_method = "EW",
      buffer_zone = list(keep_n = 20, entry_n = 30))
  }, error = function(e) { cat("    ", label, "BT error:", e$message, "\n"); NULL })
  if (is.null(bt)) return(NULL)
  ret <- bt$DAILY_NAV_DT$Strategy_Ret
  ret <- ret[is.finite(ret)]
  cum <- cumprod(1 + ret)
  n_yr <- length(ret) / 252
  list(
    CAGR = round((tail(cum,1)^(1/n_yr)-1)*100, 2),
    Sharpe = round(mean(ret)/sd(ret)*sqrt(252), 3),
    MDD = round(min(cum/cummax(cum)-1)*100, 2),
    nav_dt = bt$DAILY_NAV_DT
  )
}

# ==============================================================================
# 3. Walk-Forward Loop: 모든 모델을 데이터 1회 로드로 실행
# ==============================================================================
cat("\n[RESEARCH] Walk-Forward 18 OOS years × 4 models\n")
cat("Models: Ridge / ElasticNet / XGBoost / RandomForest\n\n")

# XGBoost 패키지 로드
xgb_ok <- tryCatch({ library(xgboost); TRUE }, error = function(e) FALSE)
rf_ok  <- tryCatch({ library(ranger); TRUE }, error = function(e) {
  tryCatch({ library(randomForest); TRUE }, error = function(e2) FALSE)
})

results <- list(
  ridge = list(), enet = list(), xgb = list(), rf = list(), logit = list()
)
ic_records <- list()

# 중간저장 디렉토리
INTERIM_DIR <- file.path(OUTPUT_BASE, "interim")
dir.create(INTERIM_DIR, showWarnings = FALSE, recursive = TRUE)

for (yi in seq_along(OOS_YEARS)) {
  oos_yr <- as.integer(OOS_YEARS[yi])
  cat("=== OOS", oos_yr, "===\n")

  # IS: 최근 5년 일간
  is_end_yr <- oos_yr - 2L
  is_start_ym <- max(200301, (is_end_yr - 4L) * 100 + 1)
  val_yr <- oos_yr - 1L

  # IS chunk load
  is_chunk <- tryCatch(load_daily_chunk(is_start_ym, is_end_yr * 100 + 12),
                       error = function(e) NULL)
  if (is.null(is_chunk) || nrow(is_chunk) < 10000) { cat("  skip\n"); next }

  is_merged <- merge(is_chunk, ret_dt[, .(Date, Ticker, fwd_ret_21d, Size)],
                     by = c("Date", "Ticker"), all.x = FALSE)
  is_merged <- is_merged[!is.na(fwd_ret_21d) & !is.na(Size) & Size >= LIQ_THRESHOLD]
  rm(is_chunk); gc()

  FACTOR_COLS <- intersect(FACTOR_COLS_BASE, names(is_merged))

  # IC prefilter (50개)
  top50 <- ic_prefilter(is_merged, FACTOR_COLS, 50)
  cat("  IS:", nrow(is_merged), "| top50 |")

  X_is <- build_mat(is_merged, top50)
  y_is <- is_merged$fwd_ret_21d

  # Val chunk (월말만)
  val_chunk <- tryCatch(load_daily_chunk(val_yr * 100 + 1, val_yr * 100 + 12),
                        error = function(e) NULL)
  if (is.null(val_chunk)) { cat(" skip(val)\n"); rm(X_is, y_is, is_merged); gc(); next }
  val_chunk[, ym := format(Date, "%Y-%m")]
  val_me <- val_chunk[, .SD[Date == max(Date)], by = ym]
  val_merged <- merge(val_me, ret_dt[, .(Date, Ticker, fwd_ret_21d, Size)],
                      by = c("Date", "Ticker"), all.x = FALSE)
  val_merged <- val_merged[!is.na(fwd_ret_21d) & !is.na(Size) & Size >= LIQ_THRESHOLD]
  rm(val_chunk, val_me); gc()
  X_val <- build_mat(val_merged, top50)
  y_val <- val_merged$fwd_ret_21d

  # OOS chunk (월말만)
  oos_chunk <- tryCatch(load_daily_chunk(oos_yr * 100 + 1, oos_yr * 100 + 12),
                        error = function(e) NULL)
  if (is.null(oos_chunk)) { cat(" skip(oos)\n"); rm(X_is, y_is, X_val, y_val, val_merged, is_merged); gc(); next }
  oos_chunk[, ym := format(Date, "%Y-%m")]
  oos_me <- oos_chunk[, .SD[Date == max(Date)], by = ym]
  oos_merged <- merge(oos_me, ret_dt[, .(Date, Ticker, fwd_ret_21d, Size)],
                      by = c("Date", "Ticker"), all.x = FALSE)
  oos_merged <- oos_merged[!is.na(fwd_ret_21d)]
  rm(oos_chunk, oos_me); gc()
  X_oos <- build_mat(oos_merged, top50)
  oos_base <- oos_merged[, .(Date, Ticker, fwd_ret_21d, Size)]

  # ---- Model A: Ridge (alpha=0) ----
  tryCatch({
    fit <- glmnet(X_is, y_is, alpha = 0, lambda = LAMBDA_GRID)
    vp <- predict(fit, X_val)
    vic <- apply(vp, 2, function(p) tryCatch(cor(p, y_val, method="spearman"), error=function(e) NA))
    best_l <- LAMBDA_GRID[which.max(vic)]
    pred <- as.numeric(predict(fit, X_oos, s = best_l))
    dt_r <- copy(oos_base); dt_r[, Score := pred]
    results$ridge[[yi]] <- dt_r
    cat(" R:", round(max(vic, na.rm=TRUE), 3))
  }, error = function(e) cat(" R:err"))

  # ---- Model B: ElasticNet (alpha=0.5) ----
  tryCatch({
    fit <- glmnet(X_is, y_is, alpha = 0.5, lambda = LAMBDA_GRID)
    vp <- predict(fit, X_val)
    vic <- apply(vp, 2, function(p) tryCatch(cor(p, y_val, method="spearman"), error=function(e) NA))
    best_l <- LAMBDA_GRID[which.max(vic)]
    pred <- as.numeric(predict(fit, X_oos, s = best_l))
    dt_e <- copy(oos_base); dt_e[, Score := pred]
    results$enet[[yi]] <- dt_e
    cat(" E:", round(max(vic, na.rm=TRUE), 3))
  }, error = function(e) cat(" E:err"))

  # ---- Model C: XGBoost ----
  if (xgb_ok) tryCatch({
    dtrain <- xgb.DMatrix(data = X_is, label = y_is)
    dval <- xgb.DMatrix(data = X_val, label = y_val)
    xgb_params <- list(booster="gbtree", objective="reg:squarederror",
                       eta=0.02, max_depth=5, subsample=0.7,
                       colsample_bytree=0.5, min_child_weight=10, lambda=1, alpha=0.1)
    m <- xgb.train(params=xgb_params, data=dtrain, nrounds=300,
                   evals=list(val=dval), early_stopping_rounds=30, verbose=0)
    pred <- predict(m, xgb.DMatrix(X_oos))
    vic <- tryCatch(cor(predict(m, dval), y_val, method="spearman"), error=function(e) NA)
    dt_x <- copy(oos_base); dt_x[, Score := pred]
    results$xgb[[yi]] <- dt_x
    cat(" X:", round(vic, 3))
    rm(dtrain, dval, m)
  }, error = function(e) cat(" X:err"))

  # ---- Model D: Random Forest (ranger, 경량화) ----
  if (rf_ok) tryCatch({
    # 메모리 절약: IS 서브샘플 300K + trees 100
    rf_idx <- if (nrow(X_is) > 300000) sample(nrow(X_is), 300000) else seq_len(nrow(X_is))
    df_is <- data.frame(y = y_is[rf_idx], X_is[rf_idx, , drop = FALSE])
    rf_m <- ranger(y ~ ., data = df_is, num.trees = 100, max.depth = 8,
                   min.node.size = 20, mtry = 15, num.threads = 2, verbose = FALSE)
    pred <- predict(rf_m, data.frame(X_oos))$predictions
    vic <- tryCatch({
      vp <- predict(rf_m, data.frame(X_val))$predictions
      cor(vp, y_val, method = "spearman")
    }, error = function(e) NA)
    dt_f <- copy(oos_base); dt_f[, Score := pred]
    results$rf[[yi]] <- dt_f
    cat(" F:", round(vic, 3))
    rm(df_is, rf_m, rf_idx)
  }, error = function(e) cat(" F:err"))

  # ---- Model E: Logistic Regression (binomial, 서브샘플 200K) ----
  tryCatch({
    lg_idx <- if (nrow(X_is) > 200000) sample(nrow(X_is), 200000) else seq_len(nrow(X_is))
    y_bin <- as.integer(y_is[lg_idx] >= quantile(y_is[lg_idx], 0.80, na.rm = TRUE))
    lg_fit <- glmnet(X_is[lg_idx, , drop = FALSE], y_bin,
                     alpha = 0.5, family = "binomial",
                     lambda = c(0.1, 0.01, 0.001, 0.0001, 0.00001))
    vp <- predict(lg_fit, X_val, type = "response")
    vic <- apply(vp, 2, function(p) tryCatch(cor(p, y_val, method="spearman"), error=function(e) NA))
    best_l <- c(0.1, 0.01, 0.001, 0.0001, 0.00001)[which.max(vic)]
    pred <- as.numeric(predict(lg_fit, X_oos, s = best_l, type = "response"))
    dt_l <- copy(oos_base); dt_l[, Score := pred]
    results$logit[[yi]] <- dt_l
    cat(" L:", round(max(vic, na.rm=TRUE), 3))
    rm(lg_idx, lg_fit, y_bin)
  }, error = function(e) cat(" L:err"))

  # IC record
  for (mn in names(results)) {
    d <- results[[mn]][[yi]]
    if (!is.null(d) && nrow(d) > 0) {
      d[, YearMonth := format(Date, "%Y-%m")]
      ic_m <- d[, .(IC = tryCatch(cor(Score, fwd_ret_21d, method="spearman", use="complete.obs"),
                                   error=function(e) NA)), by = YearMonth]
      ic_m[, model := mn]; ic_m[, oos_year := oos_yr]
      ic_records[[length(ic_records)+1]] <- ic_m
    }
  }

  # 연도별 중간저장 (OOM 시에도 결과 보존)
  for (mn in names(results)) {
    d <- results[[mn]][[yi]]
    if (!is.null(d) && nrow(d) > 0) {
      fwrite(d, file.path(INTERIM_DIR, sprintf("%s_%d.csv", mn, oos_yr)))
    }
  }
  cat(" [saved]")

  # Memory cleanup
  rm(X_is, y_is, X_val, y_val, X_oos, is_merged, val_merged, oos_merged, oos_base)
  gc()
  cat("\n")
}

# ==============================================================================
# 4. IC 분석
# ==============================================================================
cat("\n[ANALYSIS] OOS IC Summary\n")

ic_all <- rbindlist(ic_records, fill = TRUE)
ic_summary <- ic_all[, .(
  IC_mean = mean(IC, na.rm = TRUE),
  IC_sd   = sd(IC, na.rm = TRUE),
  ICIR    = mean(IC, na.rm = TRUE) / sd(IC, na.rm = TRUE),
  N       = sum(!is.na(IC))
), by = model]
ic_summary <- ic_summary[order(-ICIR)]

cat("\n--- Model ICIR Ranking ---\n")
print(ic_summary[, .(model, IC = round(IC_mean, 4), ICIR = round(ICIR, 4), N)])

fwrite(ic_all, file.path(OUTPUT_BASE, "ic_all_models.csv"))
fwrite(ic_summary, file.path(OUTPUT_BASE, "ic_summary.csv"))

# ==============================================================================
# 5. 백테스트: 전 모델
# ==============================================================================
cat("\n[BACKTEST] All models\n")

bt_results <- list()
for (mn in ic_summary$model) {
  cat("  ", mn, "...")
  score_all <- rbindlist(results[[mn]], fill = TRUE)
  if (nrow(score_all) == 0) { cat(" no data\n"); next }
  # Size merge
  score_all <- merge(score_all, RAWDATA[, .(Date, Ticker, Size)],
                     by = c("Date", "Ticker"), all.x = TRUE, suffixes = c("", ".raw"))
  if ("Size.raw" %in% names(score_all)) {
    score_all[is.na(Size), Size := Size.raw]
    score_all[, Size.raw := NULL]
  }
  perf <- run_bt_from_scores(score_all, mn)
  if (!is.null(perf)) {
    cat(" CAGR:", perf$CAGR, "% SR:", perf$Sharpe, " MDD:", perf$MDD, "%\n")
    bt_results[[mn]] <- perf
    fwrite(perf$nav_dt, file.path(OUTPUT_BASE, paste0(mn, "_nav.csv")))
  } else {
    cat(" failed\n")
  }
}

# ==============================================================================
# 6. Ensemble (상위 2개 모델 평균)
# ==============================================================================
cat("\n[ENSEMBLE] Top 2 model average\n")

top2 <- head(ic_summary$model, 2)
if (length(top2) == 2) {
  ens_scores <- list()
  for (yi in seq_along(OOS_YEARS)) {
    d1 <- results[[top2[1]]][[yi]]
    d2 <- results[[top2[2]]][[yi]]
    if (is.null(d1) || is.null(d2)) next
    m <- merge(d1[, .(Date, Ticker, S1 = Score, fwd_ret_21d, Size)],
               d2[, .(Date, Ticker, S2 = Score)],
               by = c("Date", "Ticker"))
    # Rank normalize then average
    m[, R1 := frank(S1, ties.method="average") / .N, by = Date]
    m[, R2 := frank(S2, ties.method="average") / .N, by = Date]
    m[, Score := (R1 + R2) / 2]
    ens_scores[[yi]] <- m[, .(Date, Ticker, Score, fwd_ret_21d, Size)]
  }
  ens_all <- rbindlist(ens_scores, fill = TRUE)
  if (nrow(ens_all) > 0) {
    ens_all[, YearMonth := format(Date, "%Y-%m")]
    ens_ic <- ens_all[, .(IC = cor(Score, fwd_ret_21d, method="spearman", use="complete.obs")),
                      by = YearMonth]
    ens_icir <- mean(ens_ic$IC, na.rm=TRUE) / sd(ens_ic$IC, na.rm=TRUE)
    cat("  Ensemble(", paste(top2, collapse="+"), ") ICIR:", round(ens_icir, 4), "\n")

    ens_perf <- run_bt_from_scores(ens_all, "Ensemble")
    if (!is.null(ens_perf)) {
      cat("  CAGR:", ens_perf$CAGR, "% SR:", ens_perf$Sharpe, " MDD:", ens_perf$MDD, "%\n")
      bt_results$ensemble <- ens_perf
      fwrite(ens_perf$nav_dt, file.path(OUTPUT_BASE, "ensemble_nav.csv"))
      ic_summary <- rbind(ic_summary, data.table(
        model = "ensemble", IC_mean = mean(ens_ic$IC, na.rm=TRUE),
        IC_sd = sd(ens_ic$IC, na.rm=TRUE), ICIR = ens_icir, N = nrow(ens_ic)
      ))
    }
  }
}

# ==============================================================================
# 7. Risk Engine Tests (tail_risk_suite)
# ==============================================================================
cat("\n[RISK] Tail Risk Engine Tests\n")

if (exists("compute_tail_risk_suite")) {
  for (mn in names(bt_results)) {
    nav_dt <- bt_results[[mn]]$nav_dt
    if (is.null(nav_dt)) next
    cat("  ", mn, "...")
    tr <- tryCatch({
      compute_tail_risk_suite(
        sim_result = list(daily_returns = nav_dt$Strategy_Ret),
        output_dir = OUTPUT_BASE,
        strategy_id = paste0("ML_", mn)
      )
    }, error = function(e) { cat(" err:", e$message, "\n"); NULL })
    if (!is.null(tr)) {
      cat(" CDaR:", round(tr$summary$cdar_95 %||% NA, 4),
          " EVT-VaR:", round(tr$summary$evt_var_99 %||% NA, 4),
          " xi:", round(tr$summary$tail_shape_xi %||% NA, 3), "\n")
      # Save per-model tail risk
      write_json(tr, file.path(OUTPUT_BASE, paste0(mn, "_tail_risk.json")),
                 auto_unbox = TRUE, pretty = TRUE)
    }
  }
} else {
  cat("  tail_risk_engine not loaded — skipping\n")
}

# ==============================================================================
# 8. Anchor Correlation (STR_1631)
# ==============================================================================
cat("\n[CORRELATION] vs STR_1631 anchor\n")

anchor_path <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1631/output/daily_nav.csv")
if (file.exists(anchor_path)) {
  anchor <- fread(anchor_path)
  if ("Date" %in% names(anchor) && "NAV" %in% names(anchor)) {
    setkey(anchor, Date)
    anchor[, ret_a := NAV / shift(NAV) - 1]

    for (mn in names(bt_results)) {
      nav_dt <- bt_results[[mn]]$nav_dt
      if (is.null(nav_dt)) next
      nav_dt[, Date := as.Date(Date)]
      nav_dt[, ret_m := Strategy_Ret]
      m <- merge(anchor[!is.na(ret_a), .(Date, ret_a)],
                 nav_dt[!is.na(ret_m), .(Date, ret_m)], by = "Date")
      if (nrow(m) > 100) {
        cr <- cor(m$ret_a, m$ret_m, use = "complete.obs")
        cat("  ", mn, "vs STR_1631:", round(cr, 4), "\n")
      }
    }
  }
} else {
  cat("  STR_1631 NAV not found\n")
}

# ==============================================================================
# 9. Final Comparison Table + S0 Auto-Judgment
# ==============================================================================
cat("\n[FINAL] Model Comparison\n")

final_table <- data.table(model = character(), IC = numeric(), ICIR = numeric(),
                          CAGR = numeric(), SR = numeric(), MDD = numeric())
for (mn in ic_summary$model) {
  row <- data.table(
    model = mn,
    IC = round(ic_summary[model == mn, IC_mean], 4),
    ICIR = round(ic_summary[model == mn, ICIR], 4),
    CAGR = bt_results[[mn]]$CAGR %||% NA,
    SR = bt_results[[mn]]$Sharpe %||% NA,
    MDD = bt_results[[mn]]$MDD %||% NA
  )
  final_table <- rbind(final_table, row)
}
final_table <- final_table[order(-ICIR)]

cat("\n")
print(final_table)

# S0 자동 판정
best <- final_table[1]
cat("\n--- S0 Auto-Judgment ---\n")
cat("Best model:", best$model, "\n")
cat("ICIR:", best$ICIR, "(gate: 0.20)\n")

if (!is.na(best$ICIR) && best$ICIR >= 0.20) {
  cat("PASS: Alpha Lab Gate\n")
  if (!is.na(best$MDD) && abs(best$MDD) > 45) {
    cat("WARN: MDD", best$MDD, "% > 45% hard fail. S5 overlay 필수.\n")
  }
  if (!is.na(best$SR) && best$SR >= 0.6) {
    cat("PASS: Standalone SR >= 0.6\n")
  }
  cat("RECOMMENDATION: S0 APPROVE_CONDITIONAL → S1 구현 진행\n")
} else {
  cat("FAIL: ICIR < 0.20. 추가 연구 필요.\n")
}

# Save final
write_json(as.list(final_table), file.path(OUTPUT_BASE, "final_comparison.json"),
           auto_unbox = TRUE, pretty = TRUE)
fwrite(final_table, file.path(OUTPUT_BASE, "final_comparison.csv"))

# ==============================================================================
# 10. Charts + Telegram Notification
# ==============================================================================
cat("\n[CHARTS] Generating equity curves...\n")

# 차트 생성
chart_paths <- list()
tryCatch({
  library(ggplot2)

  # --- Equity Curve: 전 모델 ---
  eq_data <- list()
  for (mn in names(bt_results)) {
    nav_dt <- bt_results[[mn]]$nav_dt
    if (is.null(nav_dt)) next
    dt <- copy(nav_dt)[, .(Date = as.Date(Date), ret = Strategy_Ret)]
    dt <- dt[!is.na(ret)]
    dt[, cum := cumprod(1 + ret)]
    dt[, model := mn]
    eq_data[[mn]] <- dt[, .(Date, cum, model)]
  }
  if (length(eq_data) > 0) {
    eq_all <- rbindlist(eq_data)
    p1 <- ggplot(eq_all, aes(x = Date, y = cum, color = model)) +
      geom_line(linewidth = 0.7) +
      scale_y_log10() +
      labs(title = "ML Overnight — Equity Curves (Log Scale)",
           subtitle = paste("OOS Walk-Forward 2008-2025 | L-123 Pipeline"),
           x = NULL, y = "Cumulative Return", color = "Model") +
      theme_minimal(base_size = 12) +
      theme(legend.position = "bottom")
    eq_path <- file.path(OUTPUT_BASE, "equity_curve.png")
    ggsave(eq_path, p1, width = 10, height = 6, dpi = 150)
    chart_paths$equity <- eq_path
    cat("  equity_curve.png saved\n")
  }

  # --- Annual Returns Bar ---
  ar_data <- list()
  for (mn in names(bt_results)) {
    nav_dt <- bt_results[[mn]]$nav_dt
    if (is.null(nav_dt)) next
    dt <- copy(nav_dt)[, .(Date = as.Date(Date), ret = Strategy_Ret)]
    dt <- dt[!is.na(ret)]
    dt[, year := as.integer(format(Date, "%Y"))]
    ann <- dt[, .(annual_ret = prod(1 + ret) - 1), by = year]
    ann[, model := mn]
    ar_data[[mn]] <- ann
  }
  if (length(ar_data) > 0) {
    ar_all <- rbindlist(ar_data)
    p2 <- ggplot(ar_all, aes(x = factor(year), y = annual_ret * 100, fill = model)) +
      geom_col(position = "dodge", width = 0.7) +
      geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
      labs(title = "ML Overnight — Annual Returns by Model",
           x = NULL, y = "Return (%)", fill = "Model") +
      theme_minimal(base_size = 11) +
      theme(axis.text.x = element_text(angle = 45, hjust = 1),
            legend.position = "bottom")
    ar_path <- file.path(OUTPUT_BASE, "annual_returns.png")
    ggsave(ar_path, p2, width = 12, height = 6, dpi = 150)
    chart_paths$annual <- ar_path
    cat("  annual_returns.png saved\n")
  }
}, error = function(e) cat("  Chart error:", e$message, "\n"))

# --- Telegram 발송 ---
cat("\n[TELEGRAM] Sending results...\n")
tryCatch({
  source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

  # 결과 테이블 텍스트
  tbl_lines <- sprintf("%-10s | IC %6s | ICIR %6s | CAGR %6s%% | SR %5s | MDD %6s%%",
                        final_table$model,
                        format(round(final_table$IC, 4), nsmall = 4),
                        format(round(final_table$ICIR, 4), nsmall = 4),
                        format(round(final_table$CAGR, 1), nsmall = 1),
                        format(round(final_table$SR, 3), nsmall = 3),
                        format(round(final_table$MDD, 1), nsmall = 1))

  best_m <- final_table[1]
  verdict <- if (!is.na(best_m$ICIR) && best_m$ICIR >= 0.20) "PASS" else "FAIL"
  hard_fail <- if (!is.na(best_m$MDD) && abs(best_m$MDD) > 45) " | MDD Hard Fail" else ""

  msg <- paste0(
    "\U0001F916 [Forge] ML Overnight Research Complete\n\n",
    "\U0001F4CA <b>Model Comparison (OOS Walk-Forward)</b>\n",
    "<pre>", paste(tbl_lines, collapse = "\n"), "</pre>\n\n",
    "\U0001F3AF <b>Best:</b> ", best_m$model,
    " (ICIR ", round(best_m$ICIR, 3), ")\n",
    "\U0001F6A6 <b>Alpha Lab Gate:</b> ", verdict, hard_fail, "\n",
    "\U0001F4C5 5 models x 18yr OOS | L-123 Pipeline\n",
    "\U0001F553 ", as.character(Sys.time())
  )

  tg_send(msg)
  cat("  Summary sent\n")

  # 차트 발송
  if (!is.null(chart_paths$equity) && file.exists(chart_paths$equity)) {
    tg_send_photo(chart_paths$equity,
                  caption = "\U0001F4C8 ML Overnight — Equity Curves (Log Scale)")
    cat("  equity_curve.png sent\n")
  }
  if (!is.null(chart_paths$annual) && file.exists(chart_paths$annual)) {
    tg_send_photo(chart_paths$annual,
                  caption = "\U0001F4CA ML Overnight — Annual Returns by Model")
    cat("  annual_returns.png sent\n")
  }
}, error = function(e) cat("  Telegram error:", e$message, "\n"))

cat("\n", paste(rep("=", 60), collapse = ""), "\n")
cat("=== ML OVERNIGHT RESEARCH COMPLETE ===\n")
cat("종료:", as.character(Sys.time()), "\n")
cat("산출물:", OUTPUT_BASE, "\n")
cat(paste(rep("=", 60), collapse = ""), "\n")
