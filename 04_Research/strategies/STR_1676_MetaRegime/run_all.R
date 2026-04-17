## =============================================================================
## STR_1676_MetaRegime: Regime-Augmented XGBoost — S1 Implementation
## 핵심 아이디어: XGBoost 3-seed ensemble + MI prefilter(top50, daily factors)
##               + Regime context features (PC1~PC5 + prob_1~prob_5 = 10 extra)
##               21일 refit expanding window + Purged CV (21d embargo)
##               월말 scoring + 월간 리밸런싱 (buffer keep=40, entry=25)
##               EW 30종목 + 15bps commission + 유동성 2억원
##
## Phase 3: Regime-Augmented XGBoost
##   Phase 1: .cache/ic_matrix_expanding.parquet (252 months x 281 factors)
##   Phase 2: .cache/regime_factor_pca.parquet (PC1~PC5)
##            .cache/regime_factor_clusters.parquet (cluster_id, prob_1~prob_5)
##   Phase 3: augment X_train/X_test with regime context features
##
## STR_1675 대비 변경:
##   - 분기 리밸런싱 -> 월간 리밸런싱 (신호-보유 미스매치 해소)
##   - buffer keep=45/entry=28 -> keep=40/entry=25 (월간 전환 시 적절한 완충)
##   - top-50 factor features -> top-50 + PC1~PC5 + prob_1~prob_5 (60 total)
##   - Regime features: 시장 수준(date별 1개값), 모든 ticker에 broadcast
##   - IC 측정: 월말 기준
##
## PIT 준수 (C1-C15):
##   C1  : expanding window only -- 전체 샘플 통계 금지
##   C2  : OOS > IS (21d purge gap) -- same-day circular 금지
##   C9  : DD/VT S1에서 미사용 (순수 팩터 신호)
##   C13 : Z_Score_Aligned (일간 DB 이미 정규화, 추가 확인)
##   C14 : fwd_ret = t+1~t+21 (IS target 전용, month-end only)
##   C15 : 일간 DB Arrow open_dataset 직접
##   Regime: expanding PCA/Kmeans -> t-1 IC만 반영 -> 미래참조 없음
##
## OPT 준수:
##   OPT-1: Arrow open_dataset predicate pushdown (모든 parquet 포함)
##   OPT-2: load_rawdata(use_cache=TRUE)
##   Regime parquet: open_dataset -> collect() 1회 (스크립트 시작 시)
## =============================================================================

cat("=== STR_1676_MetaRegime: Regime-Augmented XGBoost ===\n")
cat("시작:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(dplyr)
  library(jsonlite)
  library(ggplot2)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0L && !is.na(a[[1L]])) a[[1L]] else b

# =============================================================================
# 경로 (normalizePath 금지 -- WSL 한글 경로 버그)
# =============================================================================
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
STRATEGY_DIR <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1676_MetaRegime")
OUTPUT_DIR   <- file.path(STRATEGY_DIR, "output")
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
DAILY_DB_DIR  <- file.path(PROJECT_ROOT, ".cache/factor_db_daily")
CACHE_DIR     <- file.path(PROJECT_ROOT, ".cache")

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

# =============================================================================
# CONFIG
# =============================================================================
LIQ_THRESHOLD  <- 2e8
N_HOLDINGS     <- 30L
COMMISSION     <- 0.0015
MI_TOP_N       <- 50L
N_REGIME_FEAT  <- 10L          # PC1~PC5 + prob_1~prob_5
PURGE_DAYS     <- 21L
XGB_SEEDS      <- c(42L, 123L, 456L)
REFIT_DAYS     <- 21L          # refit 주기 (거래일)
MI_REFRESH     <- 63L          # MI prefilter 갱신 주기 (거래일)
MACRO_PAT      <- "^(RE_|RE0|RE1)"   # 조건부 팩터 패턴 (S1에서 제외)
XGB_MAX_ROWS   <- 80000L
OOS_START      <- as.Date("2009-05-01")   # cluster data 가용 시점 이후
OOS_END        <- as.Date("2025-12-31")
IS_START       <- as.Date("2003-01-01")
BUFFER_KEEP    <- 40L          # 월간 리밸런싱 (STR_1675 45 -> 40)
BUFFER_ENTRY   <- 25L          # 월간 리밸런싱 (STR_1675 28 -> 25)

# Regime feature 컬럼명
PCA_FEATS   <- paste0("PC", 1:5)
PROB_FEATS  <- paste0("prob_", 1:5)
REGIME_COLS <- c(PCA_FEATS, PROB_FEATS)

cat(sprintf("[CONFIG] N=%d | MI=%d | regime=%d | seeds=%s | refit=%dd | MI_refresh=%dd\n",
            N_HOLDINGS, MI_TOP_N, N_REGIME_FEAT, paste(XGB_SEEDS, collapse = ","),
            REFIT_DAYS, MI_REFRESH))
cat(sprintf("         buffer keep=%d entry=%d | OOS %s~%s\n",
            BUFFER_KEEP, BUFFER_ENTRY, OOS_START, OOS_END))
cat(sprintf("         Regime cols: %s\n", paste(REGIME_COLS, collapse = ", ")))

xgb_ok <- tryCatch({ library(xgboost); TRUE }, error = function(e) FALSE)
if (!xgb_ok) stop("xgboost 패키지 필요")

# =============================================================================
# [0] Regime 데이터 로드 (OPT-1: open_dataset -> collect 1회, 루프 외부)
#     PIT: regime features = expanding PCA/Kmeans on IC through t-1 month
#          -> 미래 IC 정보 미포함, C1 준수
# =============================================================================
cat("[0] Regime context 로드 (open_dataset -> collect)...\n")

# OPT-1 준수: open_dataset + collect() 방식으로 parquet 로드 (루프 외부 1회)
load_regime_table <- function(fname, keep_cols) {
  ds <- tryCatch(
    open_dataset(file.path(CACHE_DIR, fname), format = "parquet"),
    error = function(e) { cat("  dataset 오픈 실패:", fname, e$message, "\n"); NULL }
  )
  if (is.null(ds)) return(NULL)
  need <- intersect(keep_cols, schema(ds)$names)
  ds |> select(all_of(c("Date", need))) |> collect() |> as.data.table()
}

pca_dt   <- load_regime_table("regime_factor_pca.parquet",      PCA_FEATS)
clust_dt <- load_regime_table("regime_factor_clusters.parquet",  PROB_FEATS)

if (is.null(pca_dt) || is.null(clust_dt)) {
  stop("Regime 데이터 로드 실패. Phase 2 완료 확인 필요.")
}
setkey(pca_dt,   Date)
setkey(clust_dt, Date)

# 두 테이블 merge (inner -- 겹치는 날짜만 사용)
regime_dt <- merge(pca_dt, clust_dt, by = "Date")
setkey(regime_dt, Date)
cat(sprintf("    PCA rows: %d (%s ~ %s)\n", nrow(pca_dt), min(pca_dt$Date), max(pca_dt$Date)))
cat(sprintf("    Cluster rows: %d (%s ~ %s)\n", nrow(clust_dt), min(clust_dt$Date), max(clust_dt$Date)))
cat(sprintf("    Regime merged rows: %d (%s ~ %s)\n", nrow(regime_dt), min(regime_dt$Date), max(regime_dt$Date)))

REGIME_DATES <- regime_dt$Date

# Regime lookup 함수:
#   주어진 날짜 d 이전(<=d)의 가장 최근 regime row를 반환
#   PIT 준수: 윈도우 시작일 기준 가장 최근 month-end regime 사용
get_regime_row <- function(d) {
  avail <- REGIME_DATES[REGIME_DATES <= d]
  if (length(avail) == 0L) return(NULL)
  regime_dt[Date == max(avail)]
}

# =============================================================================
# [1] RAWDATA 1회 로드 (OPT-2)
# =============================================================================
cat("\n[1] RAWDATA...\n")
rw <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw$RAWDATA; BM_DT <- rw$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
cat(sprintf("    %d rows | %s ~ %s\n", nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date)))

# =============================================================================
# [2] 21d forward return (C14: t+1~t+21, 월말 only -- 학습용)
# =============================================================================
cat("[2] 21d fwd return (month-end)...\n")
ret_dt <- RAWDATA[!is.na(Ret) & is.finite(Ret) & Date >= IS_START,
                  .(Date, Ticker, Ret, Size)]
setkey(ret_dt, Ticker, Date)
ret_dt[, logR := log(1 + pmax(Ret, -0.99))]
ret_dt[, fwd_ret_21d := {
  n <- .N; cl <- cumsum(logR)
  if (n <= 21L) rep(NA_real_, n)
  else { fwd <- c(cl[22:n], rep(NA_real_, 21L)) - cl; exp(fwd) - 1 }
}, by = Ticker]
ret_dt[, logR := NULL]
ret_dt <- ret_dt[!is.na(fwd_ret_21d)]

# 월말 날짜 (학습 데이터 + MI prefilter 기준)
RAWDATA[, ym__ := format(Date, "%Y-%m")]
ALL_ME_DATES <- RAWDATA[, .(me_date = max(Date)), by = ym__][order(me_date)]$me_date
RAWDATA[, ym__ := NULL]

# 전체 거래일 벡터
ALL_TRADE_DATES <- sort(unique(RAWDATA$Date))
ALL_OOS_DATES   <- ALL_TRADE_DATES[ALL_TRADE_DATES >= OOS_START &
                                    ALL_TRADE_DATES <= OOS_END]

# OOS 월말 날짜 (IC 측정 기준 + 리밸런싱 기준)
OOS_ME_DATES <- ALL_ME_DATES[ALL_ME_DATES >= OOS_START & ALL_ME_DATES <= OOS_END]

cat(sprintf("    fwd rows: %d | ME dates: %d | OOS dates: %d | OOS ME: %d\n",
            nrow(ret_dt), length(ALL_ME_DATES), length(ALL_OOS_DATES), length(OOS_ME_DATES)))

# SIZE_DT 유지, 대형 객체 해제
SIZE_DT <- RAWDATA[Date >= IS_START, .(Date, Ticker, Size)]
setkey(SIZE_DT, Date, Ticker)
ret_dt[, c("Ret", "Size") := NULL]
setkey(ret_dt, Date, Ticker)
rm(RAWDATA, BM_DT, rw); gc()

# =============================================================================
# [3] Arrow Dataset + 팩터 정리 (NonRE only -- S1 순수 팩터)
#     OPT-1: open_dataset 한 번 열고 루프 내에서 filter/collect만 사용
# =============================================================================
cat("[3] Arrow Dataset (OPT-1: open_dataset once)...\n")
pq_files  <- list.files(DAILY_DB_DIR, pattern = "\\.parquet$", full.names = TRUE)
ds_daily  <- open_dataset(pq_files, format = "parquet")
ds_cols   <- schema(ds_daily)$names
EXCL      <- c("Date", "Ticker",
               grep("^(dps_1y|bps_1y|eps_1y|target_price)", ds_cols, value = TRUE),
               grep("\\.x$|\\.y$", ds_cols, value = TRUE),
               grep(MACRO_PAT, ds_cols, value = TRUE))  # S1: 조건부 팩터 제외
USE_FCOLS <- setdiff(ds_cols, EXCL)
cat(sprintf("    사용 팩터=%d (조건부 제외)\n", length(USE_FCOLS)))

# OPT-1: 루프 내에서는 ds_daily filter/collect만 사용 (새 파일 열기 금지)
arrow_collect <- function(fcols, dates_vec = NULL, d0 = NULL, d1 = NULL) {
  need <- intersect(c("Date", "Ticker", fcols), ds_cols)
  q <- ds_daily
  if (!is.null(dates_vec)) q <- q |> filter(Date %in% dates_vec)
  else q <- q |> filter(Date >= d0, Date <= d1)
  q |> select(all_of(need)) |> collect() |> as.data.table() |>
    (\(x) { setkey(x, Date, Ticker); x })()
}

build_mat <- function(dt, cols) {
  m <- as.matrix(dt[, intersect(cols, names(dt)), with = FALSE])
  m[!is.finite(m)] <- 0; m
}

# C13 강제: per-date cross-sectional z-score (Z_Score_Aligned 보장)
zscore_by_date <- function(dt, fcols) {
  dt <- copy(dt)
  for (f in intersect(fcols, names(dt))) {
    dt[, (f) := {
      x <- get(f); s <- sd(x, na.rm = TRUE)
      if (!is.na(s) && s > 0) (x - mean(x, na.rm = TRUE)) / s else 0
    }, by = Date]
  }
  dt
}

# =============================================================================
# [3b] Chunked MI prefilter (USE_FCOLS -> 60개씩 분할 -> top50)
# =============================================================================
mi_prefilter_chunked <- function(d0, d1, fcols, n_top = 50L) {
  me_vec <- ALL_ME_DATES[ALL_ME_DATES >= d0 & ALL_ME_DATES <= d1]
  if (length(me_vec) == 0L) return(character(0))
  chunk_sz <- 60L
  f_chunks <- split(fcols, ceiling(seq_along(fcols) / chunk_sz))
  all_ics  <- numeric(0)
  for (ch in f_chunks) {
    ch_dt <- tryCatch(arrow_collect(ch, dates_vec = me_vec), error = function(e) NULL)
    if (is.null(ch_dt) || nrow(ch_dt) == 0L) next
    ch_dt <- zscore_by_date(ch_dt, ch)  # C13: z-score 강제
    ch_dt <- merge(ch_dt, ret_dt[, .(Date, Ticker, fwd_ret_21d)], by = c("Date", "Ticker"))
    ch_dt <- ch_dt[!is.na(fwd_ret_21d)]
    y <- ch_dt$fwd_ret_21d
    for (f in ch) {
      x <- ch_dt[[f]]; v <- is.finite(x) & is.finite(y)
      if (sum(v) < 100L) next
      all_ics[f] <- tryCatch(abs(cor(x[v], y[v], method = "spearman")),
                              error = function(e) NA_real_)
    }
    rm(ch_dt); gc(FALSE)
  }
  valid <- all_ics[!is.na(all_ics)]
  if (!length(valid)) return(character(0))
  names(sort(valid, decreasing = TRUE))[seq_len(min(n_top, length(valid)))]
}

# =============================================================================
# [4] Regime feature augmentation 함수
#     date d 기준으로 d 이전 가장 최근 regime row를 모든 ticker에 broadcast
#     PIT: expanding IC -> t-1 month -> safe (C1 준수)
# =============================================================================
augment_regime <- function(dt, ref_date) {
  reg_row <- get_regime_row(ref_date)
  if (is.null(reg_row) || nrow(reg_row) == 0L) {
    for (col in REGIME_COLS) dt[, (col) := 0]
    return(dt)
  }
  for (col in REGIME_COLS) {
    val <- reg_row[[col]]
    dt[, (col) := if (is.numeric(val) && is.finite(val)) val else 0]
  }
  dt
}

# =============================================================================
# [5] XGBoost 3-seed: train once, score many
#     Feature dim: MI top-50 + 10 regime = 60 total
# =============================================================================
XGB_PARAMS <- list(booster = "gbtree", objective = "reg:squarederror",
                   eta = 0.02, max_depth = 5L, subsample = 0.7,
                   colsample_bytree = 0.5, min_child_weight = 10L,
                   lambda = 1, alpha = 0.1, nthread = 2L)

xgb3_train <- function(X_tr, y_tr, seeds = XGB_SEEDS, max_rows = XGB_MAX_ROWS) {
  if (nrow(X_tr) > max_rows) {
    idx <- sample(nrow(X_tr), max_rows)
    X_tr <- X_tr[idx, , drop = FALSE]; y_tr <- y_tr[idx]
  }
  models <- lapply(seeds, function(sd) {
    set.seed(sd)
    tryCatch({
      dtr <- xgb.DMatrix(data = X_tr, label = y_tr)
      m   <- xgb.train(XGB_PARAMS, dtr, 300L, verbose = 0L)
      rm(dtr); gc(FALSE); m
    }, error = function(e) { cat("    xgb train err:", e$message, "\n"); NULL })
  })
  Filter(Negate(is.null), models)
}

xgb3_score <- function(models, X_te) {
  if (!length(models) || nrow(X_te) < 1L) return(rep(0, nrow(X_te)))
  dtest <- xgb.DMatrix(data = X_te)
  preds <- lapply(models, function(m) tryCatch(predict(m, dtest), error = function(e) NULL))
  rm(dtest)
  valid <- Filter(Negate(is.null), preds)
  if (!length(valid)) return(rep(0, nrow(X_te)))
  n_te <- nrow(X_te)
  rmat <- vapply(valid, function(p) frank(p, ties.method = "average") / n_te, numeric(n_te))
  if (is.null(dim(rmat))) rmat else rowMeans(rmat)
}

# =============================================================================
# [6] Refit 스케줄
# =============================================================================
cat("\n[6] Refit schedule...\n")

refit_starts   <- seq(1L, length(ALL_OOS_DATES), by = REFIT_DAYS)
refit_windows  <- lapply(refit_starts, function(i) {
  end_i <- min(i + REFIT_DAYS - 1L, length(ALL_OOS_DATES))
  ALL_OOS_DATES[i:end_i]
})
cat(sprintf("    Refit windows: %d (each ~%d days)\n", length(refit_windows), REFIT_DAYS))
cat(sprintf("    OOS ME dates (monthly rebal): %d (%s ~ %s)\n",
            length(OOS_ME_DATES), min(OOS_ME_DATES), max(OOS_ME_DATES)))

# =============================================================================
# [7] Walk-Forward: 21-day refit loop
#     핵심 변경: regime features augmentation + 월말 only scoring
# =============================================================================
cat("\n[7] Walk-Forward (21d refit + regime augmentation)...\n")
cat("    총 windows:", length(refit_windows), "| 예상 소요: ~90-130분\n\n")

all_me_scores  <- list()
all_ic_recs    <- list()
mi_cache       <- NULL
mi_last_refresh <- 0L
t0_loop        <- Sys.time()

for (wi in seq_along(refit_windows)) {
  win_dates   <- refit_windows[[wi]]
  win_start_d <- min(win_dates)
  win_end_d   <- max(win_dates)
  is_end_d    <- win_start_d - PURGE_DAYS

  if (is_end_d < IS_START + 365L) next

  # 진행 로그 (10 windows마다)
  if (wi %% 10 == 1) {
    elapsed <- as.numeric(difftime(Sys.time(), t0_loop, units = "mins"))
    eta_min <- if (wi > 1L) elapsed / (wi - 1L) * (length(refit_windows) - wi + 1L) else NA
    cat(sprintf("  [%d/%d] win %s~%s | IS->%s | %.1f min | ETA ~%.0f min\n",
                wi, length(refit_windows), win_start_d, win_end_d, is_end_d,
                elapsed, eta_min %||% 0))
  }

  # --- MI prefilter (63일마다 갱신) ---
  mi_last_refresh <- mi_last_refresh + length(win_dates)
  if (is.null(mi_cache) || mi_last_refresh >= MI_REFRESH) {
    if (wi %% 10 == 1) cat("    MI prefilter refresh...\n")
    mi_cache <- mi_prefilter_chunked(IS_START, is_end_d, USE_FCOLS, MI_TOP_N)
    mi_last_refresh <- 0L
  }
  top_f <- mi_cache
  if (length(top_f) < 5L) next

  # 전체 feature 컬럼 = 팩터 + regime
  all_feat_cols <- c(top_f, REGIME_COLS)

  # --- IS 학습 데이터: 월말 + regime augmentation ---
  #     PIT: is_end_d <= win_start_d - PURGE_DAYS (미래 없음)
  #          regime: get_regime_row(me_date) -> me_date 이전 최신 month-end
  is_me_d <- ALL_ME_DATES[ALL_ME_DATES >= IS_START & ALL_ME_DATES <= is_end_d]
  if (length(is_me_d) < 24L) next

  is_dt <- tryCatch(arrow_collect(top_f, dates_vec = is_me_d), error = function(e) NULL)
  if (is.null(is_dt) || nrow(is_dt) < 1000L) next
  is_dt <- zscore_by_date(is_dt, top_f)  # C13: z-score 강제

  # IS Regime augmentation: 각 월말 date에 해당 regime row broadcast
  # (date별로 같은 값이 모든 ticker에 반복 -- 시장 상태 임베딩)
  # PIT: 각 month-end date의 regime = 해당 month-end 이전 expanding IC 기반
  is_dt_list <- lapply(unique(is_dt$Date), function(d) {
    sub_dt <- is_dt[Date == d]
    augment_regime(sub_dt, d)   # get_regime_row(d) -> d 이전 최신 regime
  })
  is_dt <- rbindlist(is_dt_list)
  rm(is_dt_list)

  is_dt <- merge(is_dt, ret_dt[, .(Date, Ticker, fwd_ret_21d)], by = c("Date", "Ticker"))
  is_dt <- merge(is_dt, SIZE_DT, by = c("Date", "Ticker"), all.x = TRUE)
  is_dt <- is_dt[!is.na(fwd_ret_21d) & !is.na(Size) & Size >= LIQ_THRESHOLD]

  X_tr <- build_mat(is_dt, all_feat_cols)
  y_tr <- is_dt$fwd_ret_21d
  rm(is_dt); gc(FALSE)
  if (nrow(X_tr) < 500L) { rm(X_tr, y_tr); next }

  # --- 모델 1회 학습 (윈도우 전체에 재사용) ---
  models <- xgb3_train(X_tr, y_tr)
  rm(X_tr, y_tr); gc(FALSE)
  if (!length(models)) next

  # --- 월말 scoring only (이 윈도우 내 OOS 월말 날짜) ---
  win_me_dates <- win_dates[win_dates %in% OOS_ME_DATES]
  if (length(win_me_dates) == 0L) { rm(models); gc(FALSE); next }

  oos_me_data <- tryCatch(
    arrow_collect(top_f, dates_vec = win_me_dates),
    error = function(e) NULL
  )
  if (is.null(oos_me_data) || nrow(oos_me_data) == 0L) {
    rm(models); gc(FALSE); next
  }
  oos_me_data <- zscore_by_date(oos_me_data, top_f)  # C13

  # OOS Regime augmentation
  # PIT: win_start_d 기준 regime (학습 윈도우 시작일 이전 정보만)
  oos_me_list <- lapply(unique(oos_me_data$Date), function(d) {
    sub_dt <- oos_me_data[Date == d]
    augment_regime(sub_dt, win_start_d)  # win_start_d 이전 최신 regime
  })
  oos_me_data <- rbindlist(oos_me_list)
  rm(oos_me_list)

  oos_me_data <- merge(oos_me_data, SIZE_DT, by = c("Date", "Ticker"), all.x = TRUE)
  oos_me_data <- oos_me_data[!is.na(Size) & Size >= LIQ_THRESHOLD]

  # 날짜별 scoring
  scored_list <- list()
  for (d in unique(oos_me_data$Date)) {
    day_dt <- oos_me_data[Date == d]
    X_te   <- build_mat(day_dt, all_feat_cols)
    if (nrow(X_te) < 10L) next
    pB     <- xgb3_score(models, X_te)
    scored_list[[as.character(d)]] <- day_dt[, .(Date, Ticker, Size, Score = pB)]
  }

  if (length(scored_list) > 0L) {
    win_me_scores <- rbindlist(scored_list)
    all_me_scores[[wi]] <- win_me_scores

    # IC 기록 (월말별)
    for (d in unique(win_me_scores$Date)) {
      d_scores <- win_me_scores[Date == d]
      d_ret    <- ret_dt[Date == d, .(Date, Ticker, fwd_ret_21d)]
      ic_merge <- merge(d_scores, d_ret, by = c("Date", "Ticker"))
      ic_merge <- ic_merge[!is.na(fwd_ret_21d) & !is.na(Score)]
      if (nrow(ic_merge) >= 30L) {
        ic_val <- tryCatch(
          cor(ic_merge$Score, ic_merge$fwd_ret_21d,
              method = "spearman", use = "complete.obs"),
          error = function(e) NA_real_)
        all_ic_recs[[length(all_ic_recs) + 1L]] <-
          data.table(Date = as.Date(d), ym = format(as.Date(d), "%Y-%m"),
                     IC = ic_val, variant = "MetaRegime_monthly")
      }
    }
    rm(win_me_scores, scored_list)
  }

  rm(models, oos_me_data); gc(FALSE)
}

elapsed_total <- as.numeric(difftime(Sys.time(), t0_loop, units = "mins"))
cat(sprintf("\n  Walk-forward 완료: %.1f분\n", elapsed_total))

# =============================================================================
# [8] Score 통합 + IC 분석
# =============================================================================
cat("\n[8] Score 통합 + IC...\n")

me_scores_all <- rbindlist(Filter(Negate(is.null), all_me_scores), fill = TRUE)
cat(sprintf("    월말 Score rows: %s (%d dates)\n",
            format(nrow(me_scores_all), big.mark = ","),
            uniqueN(me_scores_all$Date)))

ic_all <- rbindlist(Filter(Negate(is.null), all_ic_recs), fill = TRUE)
if (nrow(ic_all) > 0L) {
  ic_mean <- mean(ic_all$IC, na.rm = TRUE)
  ic_sd   <- sd(ic_all$IC, na.rm = TRUE)
  icir    <- if (ic_sd > 0) ic_mean / ic_sd else NA_real_
  ic_3y   <- ic_all[Date >= (OOS_END - 365 * 3)]
  icir_3y <- if (nrow(ic_3y) > 4L) mean(ic_3y$IC, na.rm = TRUE) / sd(ic_3y$IC, na.rm = TRUE) else NA
  cat(sprintf("    IC mean=%.4f | ICIR=%.4f | N=%d | 3Y ICIR=%.4f\n",
              ic_mean, icir, nrow(ic_all), icir_3y %||% NA))
  gate_pass <- !is.na(icir) && icir >= 0.20
  cat(sprintf("    Alpha Lab Gate (ICIR >= 0.20): %s\n", ifelse(gate_pass, "PASS", "FAIL")))
} else {
  ic_mean <- NA; icir <- NA; icir_3y <- NA; gate_pass <- FALSE
  cat("    IC 데이터 없음\n")
}

# =============================================================================
# [9] 백테스트 (run_monthly_simulation -- 월간 리밸런싱)
# =============================================================================
cat("\n[9] 백테스트 (월간 리밸런싱)...\n")

rw2 <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw2$RAWDATA; BM_DT <- rw2$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
rm(rw2); gc()

FAC <- me_scores_all[!is.na(Score), .(Date, Ticker, Score)]
setkey(FAC, Date, Ticker)
cat(sprintf("    Signal dates: %d | Tickers: %d\n",
            uniqueN(FAC$Date), uniqueN(FAC$Ticker)))

bt <- tryCatch(
  run_monthly_simulation(
    RAWDATA       = RAWDATA,
    BM_DT         = BM_DT,
    FACTORS       = FAC,
    n_holdings    = N_HOLDINGS,
    commission    = COMMISSION,
    weight_method = "EW",
    buffer_zone   = list(keep_n = BUFFER_KEEP, entry_n = BUFFER_ENTRY)
  ),
  error = function(e) { cat("    BT err:", e$message, "\n"); NULL }
)

bt_CAGR <- NA; bt_Sharpe <- NA; bt_MDD <- NA; hard_fail <- TRUE
if (!is.null(bt)) {
  r <- bt$DAILY_NAV_DT$Strategy_Ret; r <- r[is.finite(r)]
  cum <- cumprod(1 + r); nyr <- length(r) / 252
  bt_CAGR   <- round((tail(cum, 1)^(1/nyr) - 1) * 100, 2)
  bt_Sharpe <- round(mean(r) / sd(r) * sqrt(252), 4)
  bt_MDD    <- round(min(cum / cummax(cum) - 1) * 100, 2)
  hard_fail <- abs(bt_MDD) > 45
  cat(sprintf("  >> CAGR %.1f%% | SR %.4f | MDD %.1f%% | Hard Fail: %s\n",
              bt_CAGR, bt_Sharpe, bt_MDD, hard_fail))
  cat(sprintf("  >> vs STR_1675 baseline: ICIR %.4f(base 0.94) | SR %.4f(base 0.72)\n",
              icir %||% NA, bt_Sharpe))
} else {
  cat("  백테스트 실패\n")
}

# =============================================================================
# [10] 차트
# =============================================================================
cat("\n[10] 차트...\n")
chart_paths <- list()
tryCatch({
  if (!is.null(bt)) {
    eq_dt <- copy(bt$DAILY_NAV_DT)[, .(Date = as.Date(Date), ret = Strategy_Ret)]
    eq_dt <- eq_dt[is.finite(ret)]
    eq_dt[, cum := cumprod(1 + ret)]
    eq_dt[, label := "MetaRegime"]

    bm <- BM_DT[order(Date), .(Date = as.Date(Date), BM_Ret)]
    bm[, cum := cumprod(1 + fifelse(is.finite(BM_Ret), BM_Ret, 0))]
    bm[, label := "KOSPI BM"]
    eq_all <- rbind(eq_dt[, .(Date, cum, label)], bm[, .(Date, cum, label)], fill = TRUE)

    subtitle_txt <- sprintf(
      "XGB 3-seed | 21d refit | Monthly rebal | EW30 | SR %.3f | CAGR %.1f%% | MDD %.1f%%\nICIR %.3f | Features: top-50 MI + PC1-5 + prob1-5 (60 total) | OOS %s~%s",
      bt_Sharpe, bt_CAGR, bt_MDD, icir %||% NA, OOS_START, OOS_END)

    p1 <- ggplot(eq_all, aes(x = Date, y = cum, color = label, linetype = label)) +
      geom_line(linewidth = 0.8) + scale_y_log10(labels = scales::comma) +
      scale_color_manual(values = c("MetaRegime" = "#d62728", "KOSPI BM" = "#7f7f7f")) +
      scale_linetype_manual(values = c("MetaRegime" = "solid", "KOSPI BM" = "dotted")) +
      labs(title = "STR_1676_MetaRegime — Equity Curve (Regime-Augmented XGBoost)",
           subtitle = subtitle_txt,
           x = NULL, y = "Cumulative (Log)", color = NULL, linetype = NULL) +
      theme_minimal(base_size = 12) + theme(legend.position = "bottom")
    ep <- file.path(OUTPUT_DIR, "equity_curve.png")
    ggsave(ep, p1, width = 14, height = 6, dpi = 150)
    chart_paths$equity <- ep
    cat("  equity_curve.png\n")

    ar <- copy(bt$DAILY_NAV_DT)[, .(Date = as.Date(Date), ret = Strategy_Ret)]
    ar <- ar[is.finite(ret)]
    ar[, yr := as.integer(format(Date, "%Y"))]
    ar <- ar[, .(annual_ret = prod(1 + ret) - 1), by = yr]
    p2 <- ggplot(ar, aes(x = factor(yr), y = annual_ret * 100,
                         fill = ifelse(annual_ret >= 0, "pos", "neg"))) +
      geom_col(width = 0.7) +
      scale_fill_manual(values = c("pos" = "#d62728", "neg" = "#1f77b4"), guide = "none") +
      geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
      labs(title = "STR_1676_MetaRegime — Annual Returns",
           x = NULL, y = "Return (%)") +
      theme_minimal(base_size = 11) +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
    ap <- file.path(OUTPUT_DIR, "annual_returns.png")
    ggsave(ap, p2, width = 14, height = 6, dpi = 150)
    chart_paths$annual <- ap
    cat("  annual_returns.png\n")
  }

  if (nrow(ic_all) > 0L) {
    ic_all[, dt := as.Date(paste0(ym, "-01"))]
    p3 <- ggplot(ic_all, aes(x = dt, y = IC)) +
      geom_line(alpha = 0.5, color = "#d62728") +
      geom_smooth(se = FALSE, method = "loess", span = 0.3,
                  linewidth = 1.1, color = "#1f77b4") +
      geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
      geom_hline(yintercept = c(-0.05, 0.05), linetype = "dotted", color = "grey60") +
      labs(title = "STR_1676_MetaRegime — Monthly IC Time Series",
           subtitle = sprintf("ICIR=%.3f | 3Y ICIR=%.3f | N=%d months",
                              icir %||% NA, icir_3y %||% NA, nrow(ic_all)),
           x = NULL, y = "Spearman IC") +
      theme_minimal(base_size = 11)
    ip <- file.path(OUTPUT_DIR, "ic_timeseries.png")
    ggsave(ip, p3, width = 14, height = 5, dpi = 150)
    chart_paths$ic <- ip
    cat("  ic_timeseries.png\n")
  }
}, error = function(e) cat("  차트 오류:", e$message, "\n"))

# =============================================================================
# [11] 결과 저장
# =============================================================================
cat("\n[11] 결과 저장...\n")

perf <- list(
  strategy_id = "STR_1676_MetaRegime",
  variant     = "MetaRegime_monthly",
  timestamp   = as.character(Sys.time()),
  phase       = "Phase3_RegimeAugmentedXGB",

  performance = list(
    ICIR       = round(icir %||% NA, 4),
    IC_mean    = round(ic_mean %||% NA, 5),
    N_months   = nrow(ic_all),
    ICIR_3y    = round(icir_3y %||% NA, 4),
    gate_pass  = gate_pass,
    CAGR       = bt_CAGR,
    Sharpe     = bt_Sharpe,
    MDD        = bt_MDD,
    hard_fail  = hard_fail
  ),

  vs_baseline_STR1675 = list(
    baseline_ICIR   = 0.94,
    baseline_SR     = 0.72,
    this_ICIR       = round(icir %||% NA, 4),
    this_SR         = bt_Sharpe,
    ICIR_delta      = round((icir %||% NA) - 0.94, 4),
    SR_delta        = round(bt_Sharpe - 0.72, 4)
  ),

  alpha_lab_gate = list(
    pass      = gate_pass,
    ICIR      = round(icir %||% NA, 4),
    threshold = 0.20
  ),

  regime_context = list(
    pca_rows     = nrow(pca_dt),
    cluster_rows = nrow(clust_dt),
    merged_rows  = nrow(regime_dt),
    regime_cols  = REGIME_COLS,
    pca_date_range   = c(as.character(min(pca_dt$Date)), as.character(max(pca_dt$Date))),
    clust_date_range = c(as.character(min(clust_dt$Date)), as.character(max(clust_dt$Date)))
  ),

  pit_checks = list(
    C1     = "expanding window only",
    C2     = "21d purge gap, no same-day",
    C9     = "DD/VT not used (S1 pure factor)",
    C13    = "Z_Score_Aligned enforced",
    C14    = "fwd t+1~t+21 IS target only",
    C15    = "Arrow open_dataset (OPT-1)",
    regime = "open_dataset collect once; expanding PCA/Kmeans to t-1 IC; no future leakage"
  ),

  config = list(
    seeds         = XGB_SEEDS,
    mi_top_n      = MI_TOP_N,
    n_regime_feat = N_REGIME_FEAT,
    total_feat    = MI_TOP_N + N_REGIME_FEAT,
    refit_days    = REFIT_DAYS,
    mi_refresh    = MI_REFRESH,
    purge_days    = PURGE_DAYS,
    n_holdings    = N_HOLDINGS,
    commission    = COMMISSION,
    liq           = LIQ_THRESHOLD,
    buffer        = list(keep = BUFFER_KEEP, entry = BUFFER_ENTRY),
    rebal         = "monthly"
  ),

  runtime_min = round(elapsed_total, 1)
)

write_json(perf, file.path(OUTPUT_DIR, "performance.json"), auto_unbox = TRUE, pretty = TRUE)
cat("  performance.json 저장\n")

if (nrow(ic_all) > 0L)        fwrite(ic_all,          file.path(OUTPUT_DIR, "ic_timeseries.csv"))
if (!is.null(bt))              fwrite(bt$DAILY_NAV_DT, file.path(OUTPUT_DIR, "nav_monthly.csv"))
if (nrow(me_scores_all) > 0L)  fwrite(me_scores_all,  file.path(OUTPUT_DIR, "me_scores.csv"))
cat("  CSV 저장 완료\n")

cat(sprintf("\n=== STR_1676_MetaRegime 완료 (%s) | 총 %.1f분 ===\n",
            Sys.time(), elapsed_total))
cat(sprintf("    ICIR=%.4f | SR=%.4f | CAGR=%.1f%% | MDD=%.1f%%\n",
            icir %||% NA, bt_Sharpe %||% NA, bt_CAGR %||% NA, bt_MDD %||% NA))
cat(sprintf("    vs STR_1675: ICIR delta=%.4f | SR delta=%.4f\n",
            (icir %||% NA) - 0.94, (bt_Sharpe %||% NA) - 0.72))
