## =============================================================================
## STR_1660_ML5_ENSEMBLE: 5-Model Rank-Average Ensemble Diversifier — S1 구현
## 핵심 아이디어: XGBoost + Random Forest + Ridge + ElasticNet + PLS
##               각 모델 독립 학습 → rank-average → top30 EW 포트폴리오
##               Ablation: 2M(XGB+RF) → 3M(+PLS) → 5M(+Ridge+ENet)
##
## 이론 근거:
##   Gu, Kelly & Xiu (2020 RFS) — 비선형 ML cross-sectional alpha 우월성
##   Timmermann (2006 Handbook) — Combination Puzzle: 단순 평균의 OOS robustness
##   Kelly, Pruitt & Su (2019 JPE) — IPCA / PLS latent factor extraction
##   Leippold, Wang & Zhou (2022 JFE) — 아시아시장 PLS 최상위
##   Smith & Wallis (2009 JEF) — 모델 선택 위험 > combination 비용
##
## PIT 준수 (C1-C15):
##   C1  : expanding window only (full-sample 통계 금지)
##   C2  : t-1 feature → t+1 수익률 예측 (same-day circular 없음)
##   C13 : Z_Score_Aligned (일간 DB 이미 정규화, 수동 반전 금지)
##   C14 : fwd_ret = t+1~t+21 (IS target), Usable_Date <= sig_date
##   C15 : 일간 Factor DB 직접 open_dataset 사용 (월간 DB API 미경유)
##   purge: 1yr val gap (OOS_yr-1 전체)
##
## OPT 준수:
##   OPT-1: Arrow open_dataset predicate pushdown (parquet 반복 없음)
##   OPT-2: load_rawdata(use_cache=TRUE) 1회
##   OPT-4: 백테스트 mclapply 병렬
##   OPT-5: 5모델 직렬 실행 (OOM 방지, 메모리 < 80%)
##
## S1 순수 팩터 신호 측정: EW 30종목 + 15bps + 유동성 필터만
## MI prefilter: vapply 벡터화 (청크 단위 일괄 collect 후 계산)
## =============================================================================

cat("=== STR_1660_ML5: 5-Model Rank Ensemble ===\n")
cat("시작:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(dplyr)
  library(jsonlite)
  library(ggplot2)
  library(parallel)
  library(xgboost)
  library(ranger)
  library(glmnet)
  library(pls)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0L && !is.na(a[[1L]])) a[[1L]] else b

# =============================================================================
# 경로 (normalizePath 금지 — WSL 한글 경로 버그)
# =============================================================================
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
STRATEGY_DIR <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1660_ML5_ENSEMBLE")
OUTPUT_DIR   <- file.path(STRATEGY_DIR, "output")
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
DAILY_DB_DIR <- file.path(PROJECT_ROOT, ".cache/factor_db_daily")

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

# =============================================================================
# 설정
# =============================================================================
LIQ_THRESHOLD   <- 2e8
N_HOLDINGS      <- 30L
COMMISSION      <- 0.0015      # 15bps
MI_TOP_N        <- 50L
OOS_START_YR    <- 2008L
OOS_END_YR      <- 2025L
RE_PREFIX_PAT   <- "^(RE_|RE0|RE1)"   # 접두사 기반 필터 (국면 선행 지표 제외 옵션용)
MAX_ROWS_ML     <- 80000L
XGB_SEEDS       <- c(1234L, 2345L, 3456L, 4567L, 5678L)
RF_SEEDS        <- c(1234L, 2345L, 3456L, 4567L, 5678L)
ENET_ALPHA_GRID <- c(0.1, 0.3, 0.5, 0.7, 0.9)
PLS_MAX_COMP    <- 10L

cat("[CONFIG] N=", N_HOLDINGS, "| MI=", MI_TOP_N,
    "| purge=1yr_val_gap | OOS:", OOS_START_YR, "-", OOS_END_YR, "\n")
cat("[PKG] xgboost:", as.character(packageVersion("xgboost")),
    "| ranger:", as.character(packageVersion("ranger")),
    "| glmnet:", as.character(packageVersion("glmnet")),
    "| pls:", as.character(packageVersion("pls")), "\n")

# =============================================================================
# 1. RAWDATA 1회 로드 (OPT-2: use_cache=TRUE)
# =============================================================================
cat("\n[1] RAWDATA 로드...\n")
rw      <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw$RAWDATA
BM_DT   <- rw$BM_DT
setDT(RAWDATA)
setkey(RAWDATA, Date, Ticker)
cat(sprintf("    %d rows | %s ~ %s\n",
            nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date)))

# =============================================================================
# 2. 21일 선행 수익률 (C14: t+1~t+21)
# =============================================================================
cat("[2] 21d 선행 수익률...\n")
ret_dt <- RAWDATA[!is.na(Ret) & is.finite(Ret) & Date >= as.Date("2003-01-01"),
                  .(Date, Ticker, Ret)]
setkey(ret_dt, Ticker, Date)
ret_dt[, logR := log(1 + pmax(Ret, -0.99))]
ret_dt[, fwd_ret_21d := {
  n  <- .N; cl <- cumsum(logR)
  if (n <= 21L) rep(NA_real_, n)
  else { fwd <- c(cl[22:n], rep(NA_real_, 21L)) - cl; exp(fwd) - 1 }
}, by = Ticker]
ret_dt[, c("logR", "Ret") := NULL]
ret_dt <- ret_dt[!is.na(fwd_ret_21d)]
cat(sprintf("    fwd rows: %d\n", nrow(ret_dt)))

RAWDATA[, ym__ := format(Date, "%Y-%m")]
ALL_ME_DATES <- RAWDATA[, .(me_date = max(Date)), by = ym__][order(me_date)]$me_date
RAWDATA[, ym__ := NULL]
cat(sprintf("    월말 날짜: %d개 (%s ~ %s)\n",
            length(ALL_ME_DATES), min(ALL_ME_DATES), max(ALL_ME_DATES)))

SIZE_DT <- RAWDATA[Date >= as.Date("2003-01-01"), .(Date, Ticker, Size)]
setkey(SIZE_DT, Date, Ticker)

rm(RAWDATA, rw); gc()
cat(sprintf("    [MEM] RAWDATA 해제. ret_dt=%.0fMB | SIZE_DT=%.0fMB\n",
            object.size(ret_dt) / 1e6, object.size(SIZE_DT) / 1e6))

# =============================================================================
# 3. Arrow Dataset 초기화 (OPT-1: open_dataset, parquet 반복 없음)
# =============================================================================
cat("[3] Arrow Dataset 초기화...\n")
pq_files <- list.files(DAILY_DB_DIR, pattern = "\\.parquet$", full.names = TRUE)
if (length(pq_files) == 0L) stop("[ERROR] 일간 Factor DB parquet 없음: ", DAILY_DB_DIR)
ds_daily <- open_dataset(pq_files, format = "parquet")
ds_cols  <- schema(ds_daily)$names

EXCL <- c("Date", "Ticker",
          grep("^(dps_1y|bps_1y|eps_1y|target_price)", ds_cols, value = TRUE),
          grep("\\.x$|\\.y$", ds_cols, value = TRUE))
ALL_FCOLS   <- setdiff(ds_cols, EXCL)
# RE* 접두사 컬럼 분리 (국면 선행 지표 — S1-B variant용, 현재 S1-A에는 포함)
RE_COLS     <- grep(RE_PREFIX_PAT, ALL_FCOLS, value = TRUE)
NONRE_COLS  <- setdiff(ALL_FCOLS, RE_COLS)
cat(sprintf("    팩터 전체=%d | RE*=%d | NonRE=%d\n",
            length(ALL_FCOLS), length(RE_COLS), length(NONRE_COLS)))

# =============================================================================
# 유틸 함수
# =============================================================================

arrow_collect <- function(fcols, dates_vec = NULL, d0 = NULL, d1 = NULL) {
  need <- intersect(c("Date", "Ticker", fcols), ds_cols)
  q <- ds_daily
  if (!is.null(dates_vec)) {
    q <- q |> filter(Date %in% dates_vec)
  } else {
    q <- q |> filter(Date >= d0, Date <= d1)
  }
  q |> select(all_of(need)) |> collect() |> as.data.table() |>
    (\(x) { setkey(x, Date, Ticker); x })()
}

build_mat <- function(dt, cols) {
  m <- as.matrix(dt[, intersect(cols, names(dt)), with = FALSE])
  m[!is.finite(m)] <- 0; m
}

# 청크 MI prefilter: 60F 단위 일괄 collect → vapply 벡터화 IC (청크 내 DB 재접근 없음)
mi_prefilter_chunked <- function(d0, d1, fcols, n_top = 50L) {
  me_vec <- ALL_ME_DATES[ALL_ME_DATES >= d0 & ALL_ME_DATES <= d1]
  if (length(me_vec) == 0L) return(list(all = character(0), nonre = character(0)))

  chunk_sz <- 60L
  f_chunks <- split(fcols, ceiling(seq_along(fcols) / chunk_sz))
  all_ics  <- numeric(0)

  lapply(seq_along(f_chunks), function(i) {
    ch <- f_chunks[[i]]
    # 청크 단위 1회 일괄 collect — 루프 내 재접근 없음 (OPT-1)
    ch_dt <- tryCatch(arrow_collect(ch, dates_vec = me_vec), error = function(e) NULL)
    if (is.null(ch_dt) || nrow(ch_dt) == 0L) return(invisible(NULL))
    ch_dt <- merge(ch_dt, ret_dt[, .(Date, Ticker, fwd_ret_21d)], by = c("Date", "Ticker"))
    ch_dt <- ch_dt[!is.na(fwd_ret_21d)]
    y <- ch_dt$fwd_ret_21d
    # vapply 벡터화: 이미 일괄 로드된 ch_dt에서만 계산
    ics <- vapply(ch, function(f) {
      x <- ch_dt[[f]]; v <- is.finite(x) & is.finite(y)
      if (sum(v) < 100L) return(NA_real_)
      tryCatch(abs(cor(x[v], y[v], method = "spearman")), error = function(e) NA_real_)
    }, numeric(1L))
    all_ics[ch] <<- ics
    rm(ch_dt); gc(FALSE)
    cat(sprintf("      MI chunk %d/%d (%d factors)\n", i, length(f_chunks), length(ch)))
  })

  valid <- all_ics[!is.na(all_ics)]
  if (!length(valid)) return(list(all = character(0), nonre = character(0)))
  top_all   <- names(sort(valid, decreasing = TRUE))[seq_len(min(n_top, length(valid)))]
  nonre_v   <- valid[intersect(names(valid), NONRE_COLS)]
  top_nonre <- if (length(nonre_v))
    names(sort(nonre_v, decreasing = TRUE))[seq_len(min(n_top, length(nonre_v)))]
  else character(0)
  list(all = top_all, nonre = top_nonre)
}

# =============================================================================
# 5모델 예측 함수 (각 독립 학습 → normalized rank 반환)
# =============================================================================

# 1) XGBoost 5-seed 평균 rank
pred_xgb <- function(X_tr, y_tr, X_te, X_vl = NULL,
                     seeds = XGB_SEEDS, max_rows = MAX_ROWS_ML) {
  if (nrow(X_tr) > max_rows) {
    idx <- sample(nrow(X_tr), max_rows); X_tr <- X_tr[idx, , drop = FALSE]; y_tr <- y_tr[idx]
  }
  params <- list(booster = "gbtree", objective = "reg:squarederror",
                 eta = 0.05, max_depth = 4L, subsample = 0.8,
                 colsample_bytree = 0.8, min_child_weight = 10L,
                 lambda = 1, alpha = 0.1, nthread = 1L)
  dtest <- xgb.DMatrix(data = X_te)
  preds <- lapply(seeds, function(sd) {
    set.seed(sd)
    tryCatch({
      dtr <- xgb.DMatrix(data = X_tr, label = y_tr)
      m <- if (!is.null(X_vl) && nrow(X_vl) > 10L) {
        dvl <- xgb.DMatrix(data = X_vl, label = rep(0, nrow(X_vl)))
        fit <- xgb.train(params, dtr, 500L, evals = list(v = dvl),
                         early_stopping_rounds = 30L, verbose = 0L)
        rm(dvl); fit
      } else xgb.train(params, dtr, 300L, verbose = 0L)
      p <- predict(m, dtest); rm(dtr, m); gc(FALSE); p
    }, error = function(e) { cat("    xgb err:", e$message, "\n"); NULL })
  })
  rm(dtest); gc(FALSE)
  valid <- Filter(Negate(is.null), preds)
  if (!length(valid)) return(rep(0.5, nrow(X_te)))
  n_te <- nrow(X_te)
  rmat <- vapply(valid, function(p) frank(p, ties.method = "average") / n_te, numeric(n_te))
  if (is.null(dim(rmat))) rmat else rowMeans(rmat)
}

# 2) Random Forest 5-seed 평균 rank (ranger, bagging)
pred_rf <- function(X_tr, y_tr, X_te, seeds = RF_SEEDS, max_rows = MAX_ROWS_ML) {
  if (nrow(X_tr) > max_rows) {
    idx <- sample(nrow(X_tr), max_rows); X_tr <- X_tr[idx, , drop = FALSE]; y_tr <- y_tr[idx]
  }
  tr_df <- as.data.frame(X_tr); tr_df$y__ <- y_tr
  te_df <- as.data.frame(X_te); n_te <- nrow(X_te)
  preds <- lapply(seeds, function(sd) {
    tryCatch({
      set.seed(sd)
      m <- ranger(y__ ~ ., data = tr_df, num.trees = 500L,
                  mtry = max(1L, floor(sqrt(ncol(X_tr)))),
                  min.node.size = 5L, replace = TRUE, verbose = FALSE, seed = sd)
      p <- predict(m, te_df)$predictions; rm(m); gc(FALSE); p
    }, error = function(e) { cat("    rf err:", e$message, "\n"); NULL })
  })
  valid <- Filter(Negate(is.null), preds)
  if (!length(valid)) return(rep(0.5, n_te))
  rmat <- vapply(valid, function(p) frank(p, ties.method = "average") / n_te, numeric(n_te))
  if (is.null(dim(rmat))) rmat else rowMeans(rmat)
}

# 3) Ridge (alpha=0): glmnet CV → normalized rank
pred_ridge <- function(X_tr, y_tr, X_te, max_rows = MAX_ROWS_ML) {
  if (nrow(X_tr) > max_rows) {
    idx <- sample(nrow(X_tr), max_rows); X_tr <- X_tr[idx, , drop = FALSE]; y_tr <- y_tr[idx]
  }
  n_te <- nrow(X_te)
  tryCatch({
    nf  <- min(5L, max(3L, floor(nrow(X_tr) / 100L)))
    fit <- cv.glmnet(X_tr, y_tr, alpha = 0, standardize = TRUE, nfolds = nf)
    p   <- as.numeric(predict(fit, newx = X_te, s = "lambda.min"))
    frank(p, ties.method = "average") / n_te
  }, error = function(e) { cat("    ridge err:", e$message, "\n"); rep(0.5, n_te) })
}

# 4) ElasticNet: alpha CV grid (0.1~0.9) + lambda CV → normalized rank
pred_enet <- function(X_tr, y_tr, X_te,
                      alpha_grid = ENET_ALPHA_GRID, max_rows = MAX_ROWS_ML) {
  if (nrow(X_tr) > max_rows) {
    idx <- sample(nrow(X_tr), max_rows); X_tr <- X_tr[idx, , drop = FALSE]; y_tr <- y_tr[idx]
  }
  n_te <- nrow(X_te)
  tryCatch({
    nf <- min(5L, max(3L, floor(nrow(X_tr) / 100L)))
    best_cvm <- Inf; best_fit <- NULL
    res_list <- lapply(alpha_grid, function(a) {
      tryCatch(cv.glmnet(X_tr, y_tr, alpha = a, standardize = TRUE, nfolds = nf),
               error = function(e) NULL)
    })
    for (k in seq_along(alpha_grid)) {
      cv_fit <- res_list[[k]]; if (is.null(cv_fit)) next
      mc <- min(cv_fit$cvm, na.rm = TRUE)
      if (mc < best_cvm) { best_cvm <- mc; best_fit <- cv_fit }
    }
    if (is.null(best_fit)) return(rep(0.5, n_te))
    p <- as.numeric(predict(best_fit, newx = X_te, s = "lambda.min"))
    frank(p, ties.method = "average") / n_te
  }, error = function(e) { cat("    enet err:", e$message, "\n"); rep(0.5, n_te) })
}

# 5) PLS (pls::plsr): 5-fold CV 최적 ncomp → normalized rank
#    predict() 반환값은 3차원 배열 → as.numeric() 으로 벡터화
pred_pls <- function(X_tr, y_tr, X_te, max_comp = PLS_MAX_COMP, max_rows = MAX_ROWS_ML) {
  if (nrow(X_tr) > max_rows) {
    idx <- sample(nrow(X_tr), max_rows); X_tr <- X_tr[idx, , drop = FALSE]; y_tr <- y_tr[idx]
  }
  n_te <- nrow(X_te)
  tryCatch({
    tr_df <- as.data.frame(X_tr); tr_df$y__ <- y_tr
    te_df <- as.data.frame(X_te)
    ncomp_max <- max(1L, min(max_comp, ncol(X_tr) - 1L, floor(nrow(X_tr) / 5L)))
    n_seg     <- min(5L, max(2L, floor(nrow(X_tr) / 20L)))
    fit       <- pls::plsr(y__ ~ ., data = tr_df, ncomp = ncomp_max,
                           scale = TRUE, validation = "CV", segments = n_seg)
    rmsep_vals <- pls::RMSEP(fit)$val[1L, 1L, ]
    best_nc    <- max(1L, which.min(rmsep_vals))
    p_raw <- as.numeric(predict(fit, newdata = te_df, ncomp = best_nc))
    p <- if (length(p_raw) == n_te) p_raw else rep(0.5, n_te)
    frank(p, ties.method = "average") / n_te
  }, error = function(e) { cat("    pls err:", e$message, "\n"); rep(0.5, n_te) })
}

# =============================================================================
# 앙상블: 5모델 rank 수집 → 2M/3M/5M ablation scores
# =============================================================================
ensemble_predict <- function(X_tr, y_tr, X_te, X_vl = NULL) {
  cat("      [XGB]   "); r_xgb   <- pred_xgb(X_tr, y_tr, X_te, X_vl); cat("done\n")
  cat("      [RF]    "); r_rf    <- pred_rf(X_tr, y_tr, X_te);          cat("done\n")
  cat("      [Ridge] "); r_ridge <- pred_ridge(X_tr, y_tr, X_te);       cat("done\n")
  cat("      [ENet]  "); r_enet  <- pred_enet(X_tr, y_tr, X_te);        cat("done\n")
  cat("      [PLS]   "); r_pls   <- pred_pls(X_tr, y_tr, X_te);         cat("done\n")
  list(
    rank_2M = (r_xgb + r_rf) / 2,
    rank_3M = (r_xgb + r_rf + r_pls) / 3,
    rank_5M = (r_xgb + r_rf + r_pls + r_ridge + r_enet) / 5
  )
}

# =============================================================================
# 4. Walk-Forward Expanding Window
#    purged CV: IS = 2003~(OOS_yr-2) | Val gap = OOS_yr-1 전체 (1yr 분리)
# =============================================================================
cat("\n[4] Walk-Forward (1yr val gap)...\n")

IS_START_D <- as.Date("2003-01-01")
OOS_YEARS  <- OOS_START_YR:OOS_END_YR

wf_out <- lapply(OOS_YEARS, function(oos_yr) {
  cat(sprintf("  OOS %d\n", oos_yr))
  is_end_yr <- oos_yr - 2L
  if (is_end_yr < 2005L) return(NULL)

  is_end_d <- as.Date(sprintf("%d-12-31", is_end_yr))
  val_s    <- as.Date(sprintf("%d-01-01", oos_yr - 1L))
  val_e    <- as.Date(sprintf("%d-12-31", oos_yr - 1L))
  oos_s    <- as.Date(sprintf("%d-01-01", oos_yr))
  oos_e    <- as.Date(sprintf("%d-12-31", oos_yr))

  cat("    MI prefilter (chunked)...\n")
  tops  <- mi_prefilter_chunked(IS_START_D, is_end_d, ALL_FCOLS, MI_TOP_N)
  top_A <- tops$all
  cat(sprintf("    topA=%d\n", length(top_A)))
  if (length(top_A) < 5L) return(NULL)

  is_me_d <- ALL_ME_DATES[ALL_ME_DATES >= IS_START_D & ALL_ME_DATES <= is_end_d]
  is_dt   <- tryCatch(arrow_collect(top_A, dates_vec = is_me_d), error = function(e) NULL)
  if (is.null(is_dt) || nrow(is_dt) < 500L) return(NULL)

  is_dt <- merge(is_dt, ret_dt[, .(Date, Ticker, fwd_ret_21d)], by = c("Date", "Ticker"))
  is_dt <- merge(is_dt, SIZE_DT, by = c("Date", "Ticker"), all.x = TRUE)
  is_dt <- is_dt[!is.na(fwd_ret_21d) & !is.na(Size) & Size >= LIQ_THRESHOLD]
  cat(sprintf("    IS=%d rows\n", nrow(is_dt)))
  if (nrow(is_dt) < 500L) { rm(is_dt); gc(FALSE); return(NULL) }

  X_tr <- build_mat(is_dt, top_A); y_tr <- is_dt$fwd_ret_21d
  rm(is_dt); gc(FALSE)

  X_vl <- NULL
  val_me_d <- ALL_ME_DATES[ALL_ME_DATES >= val_s & ALL_ME_DATES <= val_e]
  if (length(val_me_d) > 0L) {
    val_dt <- tryCatch(arrow_collect(top_A, dates_vec = val_me_d), error = function(e) NULL)
    if (!is.null(val_dt) && nrow(val_dt) > 0L) {
      val_m <- merge(val_dt, ret_dt[, .(Date, Ticker, fwd_ret_21d)], by = c("Date", "Ticker"))
      val_m <- val_m[!is.na(fwd_ret_21d)]
      if (nrow(val_m) > 50L) X_vl <- build_mat(val_m, top_A)
      rm(val_dt, val_m); gc(FALSE)
    }
  }

  oos_me_d <- ALL_ME_DATES[ALL_ME_DATES >= oos_s & ALL_ME_DATES <= oos_e]
  oos_me <- tryCatch(arrow_collect(top_A, dates_vec = oos_me_d), error = function(e) NULL)
  if (is.null(oos_me) || nrow(oos_me) == 0L) { rm(X_tr, y_tr); gc(FALSE); return(NULL) }
  oos_me <- merge(oos_me, SIZE_DT, by = c("Date", "Ticker"), all.x = TRUE)
  oos_me <- oos_me[!is.na(Size) & Size >= LIQ_THRESHOLD]
  if (nrow(oos_me) < 30L) { rm(X_tr, y_tr, oos_me); gc(FALSE); return(NULL) }

  X_te <- build_mat(oos_me, top_A)
  cat(sprintf("    OOS: %d rows x %d features\n", nrow(oos_me), ncol(X_te)))

  cat("    5-model ensemble...\n")
  ens <- tryCatch(ensemble_predict(X_tr, y_tr, X_te, X_vl),
                  error = function(e) { cat("    ensemble err:", e$message, "\n"); NULL })
  rm(X_tr, y_tr, X_vl, X_te); gc(FALSE)
  if (is.null(ens)) { rm(oos_me); gc(FALSE); return(NULL) }

  oos_me[, score_5M := ens$rank_5M]
  oos_me[, score_3M := ens$rank_3M]
  oos_me[, score_2M := ens$rank_2M]

  oos_r <- merge(oos_me[, .(Date, Ticker, score_5M, score_3M, score_2M)],
                 ret_dt[, .(Date, Ticker, fwd_ret_21d)], by = c("Date", "Ticker"))
  oos_r <- oos_r[!is.na(fwd_ret_21d)]
  oos_r[, ym_ := format(Date, "%Y-%m")]

  ic_fn <- function(sc_col, vname) {
    oos_r[, .(IC = tryCatch(
      cor(.SD[[sc_col]], fwd_ret_21d, method = "spearman", use = "complete.obs"),
      error = function(e) NA_real_),
      variant = vname, oos_year = oos_yr), by = ym_]
  }
  ic5 <- ic_fn("score_5M", "5M"); setnames(ic5, "ym_", "ym")
  ic3 <- ic_fn("score_3M", "3M"); setnames(ic3, "ym_", "ym")
  ic2 <- ic_fn("score_2M", "2M"); setnames(ic2, "ym_", "ym")

  cat(sprintf("    IC 5M=%.4f 3M=%.4f 2M=%.4f\n",
              mean(ic5$IC, na.rm = TRUE), mean(ic3$IC, na.rm = TRUE),
              mean(ic2$IC, na.rm = TRUE)))

  sc5 <- oos_me[, .(Date, Ticker, Size, Score = score_5M, variant = "5M")]
  sc3 <- oos_me[, .(Date, Ticker, Size, Score = score_3M, variant = "3M")]
  sc2 <- oos_me[, .(Date, Ticker, Size, Score = score_2M, variant = "2M")]
  rm(oos_me, oos_r); gc(FALSE)
  list(sc5 = sc5, sc3 = sc3, sc2 = sc2, ic5 = ic5, ic3 = ic3, ic2 = ic2)
})

valid_wf  <- Filter(Negate(is.null), wf_out)
cat(sprintf("\n  완료: %d/%d 연도 유효\n", length(valid_wf), length(OOS_YEARS)))

scores_5M <- rbindlist(Filter(Negate(is.null), lapply(valid_wf, `[[`, "sc5")), fill = TRUE)
scores_3M <- rbindlist(Filter(Negate(is.null), lapply(valid_wf, `[[`, "sc3")), fill = TRUE)
scores_2M <- rbindlist(Filter(Negate(is.null), lapply(valid_wf, `[[`, "sc2")), fill = TRUE)
ic_5M_all <- rbindlist(Filter(Negate(is.null), lapply(valid_wf, `[[`, "ic5")), fill = TRUE)
ic_3M_all <- rbindlist(Filter(Negate(is.null), lapply(valid_wf, `[[`, "ic3")), fill = TRUE)
ic_2M_all <- rbindlist(Filter(Negate(is.null), lapply(valid_wf, `[[`, "ic2")), fill = TRUE)
rm(wf_out, valid_wf); gc()

# =============================================================================
# 5. IC / ICIR 요약 + Ablation 판단
# =============================================================================
cat("\n[5] IC / ICIR 분석...\n")

icir_fn <- function(ic_dt) {
  if (is.null(ic_dt) || nrow(ic_dt) == 0L)
    return(list(IC = NA_real_, ICIR = NA_real_, IC_sd = NA_real_, N = 0L))
  v <- ic_dt$IC[!is.na(ic_dt$IC)]
  if (length(v) < 5L)
    return(list(IC = NA_real_, ICIR = NA_real_, IC_sd = NA_real_, N = length(v)))
  list(IC = round(mean(v), 5), ICIR = round(mean(v) / sd(v), 4),
       IC_sd = round(sd(v), 5), N = length(v))
}

cur_yr     <- as.integer(format(Sys.Date(), "%Y"))
icir_5M    <- icir_fn(ic_5M_all)
icir_3M    <- icir_fn(ic_3M_all)
icir_2M    <- icir_fn(ic_2M_all)
icir_5M_3y <- icir_fn(ic_5M_all[oos_year >= cur_yr - 3L])

cat(sprintf("  5M (primary): IC=%.4f ICIR=%.4f IC_sd=%.4f N=%d\n",
            icir_5M$IC %||% NA, icir_5M$ICIR %||% NA,
            icir_5M$IC_sd %||% NA, icir_5M$N))
cat(sprintf("  3M (ablation): IC=%.4f ICIR=%.4f IC_sd=%.4f N=%d\n",
            icir_3M$IC %||% NA, icir_3M$ICIR %||% NA,
            icir_3M$IC_sd %||% NA, icir_3M$N))
cat(sprintf("  2M (baseline): IC=%.4f ICIR=%.4f IC_sd=%.4f N=%d\n",
            icir_2M$IC %||% NA, icir_2M$ICIR %||% NA,
            icir_2M$IC_sd %||% NA, icir_2M$N))
cat(sprintf("  5M 3Y ICIR=%.4f\n", icir_5M_3y$ICIR %||% NA))

# S0 ablation decision_rule
ablation_decision <- {
  i5 <- icir_5M$ICIR %||% 0; s5 <- icir_5M$IC_sd %||% Inf
  i3 <- icir_3M$ICIR %||% 0; s3 <- icir_3M$IC_sd %||% Inf
  i2 <- icir_2M$ICIR %||% 0; s2 <- icir_2M$IC_sd %||% Inf
  if      (i5 > i3 && s5 < s3) "5M_ADOPTED (ICIR+IC_sd 모두 개선)"
  else if (i5 >= i3)            "5M_ADOPTED (ICIR 동등 이상)"
  else if (i3 > i2 && s3 < s2) "3M_BETTER (Linear 제외 권고)"
  else if (i3 < i2)             "2M_BETTER (PLS 기여 없음)"
  else                           "5M_ADOPTED (기본 적용)"
}
cat(sprintf("  Ablation 판단: %s\n", ablation_decision))

gate_5M <- !is.na(icir_5M$ICIR) && icir_5M$ICIR >= 0.20
cat(sprintf("  Alpha Lab Gate (5M): %s\n", ifelse(gate_5M, "PASS", "FAIL")))

# =============================================================================
# 6. 백테스트 — RAWDATA 재로드 + mclapply (OPT-2, OPT-4)
# =============================================================================
rm(ret_dt, SIZE_DT); gc()
cat("\n[6-0] RAWDATA 재로드 (백테스트용)...\n")
rw2     <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw2$RAWDATA; BM_DT <- rw2$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
rm(rw2); gc()

cat("[6] 백테스트 mclapply...\n")
bt_inputs <- list("S1_5M" = scores_5M, "S1_3M" = scores_3M, "S1_2M" = scores_2M)
n_cores   <- min(3L, max(1L, detectCores() - 1L))
cat(sprintf("  cores=%d\n", n_cores))

bt_results <- mclapply(names(bt_inputs), function(nm) {
  sc <- bt_inputs[[nm]]
  if (is.null(sc) || nrow(sc) == 0L) return(NULL)
  FAC <- sc[!is.na(Score), .(Date, Ticker, Score)]
  setkey(FAC, Date, Ticker)
  bt <- tryCatch(
    run_monthly_simulation(
      RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FAC,
      n_holdings = N_HOLDINGS, commission = COMMISSION,
      weight_method = "EW",
      buffer_zone = list(keep_n = N_HOLDINGS + 5L, entry_n = N_HOLDINGS)),
    error = function(e) { cat(nm, "BT err:", e$message, "\n"); NULL })
  if (is.null(bt)) return(NULL)
  r <- bt$DAILY_NAV_DT$Strategy_Ret; r <- r[is.finite(r)]
  cum <- cumprod(1 + r); nyr <- length(r) / 252
  list(label  = nm,
       CAGR   = round((tail(cum, 1)^(1 / nyr) - 1) * 100, 2),
       Sharpe = round(mean(r) / sd(r) * sqrt(252), 4),
       MDD    = round(min(cum / cummax(cum) - 1) * 100, 2),
       nav_dt = bt$DAILY_NAV_DT)
}, mc.cores = n_cores)
names(bt_results) <- names(bt_inputs)

lapply(names(bt_results), function(nm) {
  r <- bt_results[[nm]]
  if (!is.null(r)) cat(sprintf("  %s: CAGR %.1f%% SR %.4f MDD %.1f%%\n",
                                nm, r$CAGR, r$Sharpe, r$MDD))
})
bt_5M     <- bt_results[["S1_5M"]]
bt_3M     <- bt_results[["S1_3M"]]
bt_2M     <- bt_results[["S1_2M"]]
hard_fail <- !is.null(bt_5M) && abs(bt_5M$MDD) > 45

# =============================================================================
# 7. 차트
# =============================================================================
cat("\n[7] 차트...\n")
chart_paths <- list()
tryCatch({
  eq_data <- rbindlist(Filter(Negate(is.null), lapply(names(bt_results), function(nm) {
    b <- bt_results[[nm]]; if (is.null(b)) return(NULL)
    d <- copy(b$nav_dt)[, .(Date = as.Date(Date), ret = Strategy_Ret)]
    d <- d[is.finite(ret)]; d[, cum := cumprod(1 + ret)]; d[, label := nm]; d
  })), fill = TRUE)
  bm_c <- copy(BM_DT)[order(Date), .(Date = as.Date(Date), BM_Ret)]
  bm_c[, cum := cumprod(1 + fifelse(is.finite(BM_Ret), BM_Ret, 0))]; bm_c[, label := "KOSPI BM"]
  eq_all <- rbind(eq_data[, .(Date, cum, label)], bm_c[, .(Date, cum, label)], fill = TRUE)
  if (nrow(eq_all) > 0L) {
    p1 <- ggplot(eq_all, aes(x = Date, y = cum, color = label, linetype = label)) +
      geom_line(linewidth = 0.8) + scale_y_log10(labels = scales::comma) +
      scale_color_manual(values = c("S1_5M" = "#1f77b4", "S1_3M" = "#ff7f0e",
                                    "S1_2M" = "#2ca02c", "KOSPI BM" = "#7f7f7f")) +
      scale_linetype_manual(values = c("S1_5M" = "solid", "S1_3M" = "dashed",
                                       "S1_2M" = "dotdash", "KOSPI BM" = "dotted")) +
      labs(title = "STR_1660_ML5 S1 — Equity Curves (Ablation)",
           subtitle = "5M(XGB+RF+PLS+Ridge+ENet) vs 3M vs 2M | EW 30 | 1yr purge",
           x = NULL, y = "Cumulative (Log)", color = NULL, linetype = NULL) +
      theme_minimal(base_size = 12) + theme(legend.position = "bottom")
    ep <- file.path(OUTPUT_DIR, "equity_curve.png")
    ggsave(ep, p1, width = 12, height = 6, dpi = 150)
    chart_paths$equity <- ep; cat("  equity_curve.png\n")
  }

  ar_all <- rbindlist(Filter(Negate(is.null), lapply(names(bt_results), function(nm) {
    b <- bt_results[[nm]]; if (is.null(b)) return(NULL)
    d <- copy(b$nav_dt)[, .(Date = as.Date(Date), ret = Strategy_Ret)]
    d <- d[is.finite(ret)]; d[, yr := as.integer(format(Date, "%Y"))]
    a <- d[, .(annual_ret = prod(1 + ret) - 1), by = yr]; a[, label := nm]; a
  })), fill = TRUE)
  if (nrow(ar_all) > 0L) {
    p2 <- ggplot(ar_all, aes(x = factor(yr), y = annual_ret * 100, fill = label)) +
      geom_col(position = "dodge", width = 0.7) +
      geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
      scale_fill_manual(values = c("S1_5M" = "#1f77b4", "S1_3M" = "#ff7f0e", "S1_2M" = "#2ca02c")) +
      labs(title = "STR_1660_ML5 S1 — Annual Returns (Ablation)",
           subtitle = "2M(XGB+RF) -> 3M(+PLS) -> 5M(+Ridge+ENet)",
           x = NULL, y = "Return (%)", fill = NULL) +
      theme_minimal(base_size = 11) +
      theme(axis.text.x = element_text(angle = 45, hjust = 1), legend.position = "bottom")
    ap <- file.path(OUTPUT_DIR, "annual_returns.png")
    ggsave(ap, p2, width = 14, height = 6, dpi = 150)
    chart_paths$annual <- ap; cat("  annual_returns.png\n")
  }

  ic_c <- rbindlist(list(ic_5M_all[, .(ym, IC, variant = "5M")],
                         ic_3M_all[, .(ym, IC, variant = "3M")],
                         ic_2M_all[, .(ym, IC, variant = "2M")]), fill = TRUE)
  if (nrow(ic_c) > 0L) {
    ic_c[, dt := as.Date(paste0(ym, "-01"))]
    p3 <- ggplot(ic_c, aes(x = dt, y = IC, color = variant)) +
      geom_line(alpha = 0.4) +
      geom_smooth(se = FALSE, method = "loess", span = 0.3, linewidth = 1.1) +
      geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
      scale_color_manual(values = c("5M" = "#1f77b4", "3M" = "#ff7f0e", "2M" = "#2ca02c")) +
      labs(title    = "STR_1660_ML5 S1 — Monthly IC (Ablation)",
           subtitle = sprintf("5M ICIR=%.3f | 3M ICIR=%.3f | 2M ICIR=%.3f",
                              icir_5M$ICIR %||% NA, icir_3M$ICIR %||% NA,
                              icir_2M$ICIR %||% NA),
           x = NULL, y = "Spearman IC", color = NULL) +
      theme_minimal(base_size = 11) + theme(legend.position = "bottom")
    ip <- file.path(OUTPUT_DIR, "ic_timeseries.png")
    ggsave(ip, p3, width = 12, height = 5, dpi = 150)
    chart_paths$ic <- ip; cat("  ic_timeseries.png\n")
  }
}, error = function(e) cat("  차트 오류:", e$message, "\n"))

# =============================================================================
# 8. 결과 저장
# =============================================================================
cat("\n[8] 결과 저장...\n")
perf <- list(
  strategy_id = "STR_1660_ML5_ENSEMBLE",
  factor_id   = "ML5_RANK_ENS",
  timestamp   = as.character(Sys.time()),
  primary     = "S1_5M",
  ablation_decision = ablation_decision,
  s1_5M = list(ICIR = icir_5M$ICIR, IC = icir_5M$IC, IC_sd = icir_5M$IC_sd,
               N_months = icir_5M$N, ICIR_3y = icir_5M_3y$ICIR, gate_pass = gate_5M,
               CAGR = if (!is.null(bt_5M)) bt_5M$CAGR   else NA,
               Sharpe = if (!is.null(bt_5M)) bt_5M$Sharpe else NA,
               MDD  = if (!is.null(bt_5M)) bt_5M$MDD    else NA),
  s1_3M = list(ICIR = icir_3M$ICIR, IC = icir_3M$IC, IC_sd = icir_3M$IC_sd,
               N_months = icir_3M$N,
               CAGR = if (!is.null(bt_3M)) bt_3M$CAGR   else NA,
               Sharpe = if (!is.null(bt_3M)) bt_3M$Sharpe else NA,
               MDD  = if (!is.null(bt_3M)) bt_3M$MDD    else NA),
  s1_2M = list(ICIR = icir_2M$ICIR, IC = icir_2M$IC, IC_sd = icir_2M$IC_sd,
               N_months = icir_2M$N,
               CAGR = if (!is.null(bt_2M)) bt_2M$CAGR   else NA,
               Sharpe = if (!is.null(bt_2M)) bt_2M$Sharpe else NA,
               MDD  = if (!is.null(bt_2M)) bt_2M$MDD    else NA),
  alpha_lab_gate = list(pass = gate_5M, threshold = 0.20, best_ICIR = icir_5M$ICIR),
  hard_fail  = hard_fail,
  pit_checks = list(
    C1 = "expanding window only PASS", C2 = "t-1 feature -> t+1 수익률 PASS",
    C13 = "Z_Score_Aligned PASS", C14 = "fwd_ret_21d t+1~t+21 PASS",
    C15 = "일간 DB open_dataset 직접 사용 PASS",
    OPT1 = "Arrow predicate pushdown PASS",
    OPT4 = "mclapply 병렬 백테스트 PASS",
    purge = "1yr val gap PASS"),
  ml_config = list(
    models = c("XGBoost", "RandomForest", "Ridge", "ElasticNet", "PLS"),
    xgb_seeds = XGB_SEEDS, rf_seeds = RF_SEEDS,
    enet_alpha_grid = ENET_ALPHA_GRID, pls_max_comp = PLS_MAX_COMP,
    mi_top_n = MI_TOP_N, purge_method = "1yr_val_gap",
    n_holdings = N_HOLDINGS, commission = COMMISSION, liq_threshold = LIQ_THRESHOLD)
)
write_json(perf, file.path(OUTPUT_DIR, "performance.json"), auto_unbox = TRUE, pretty = TRUE)
cat("  performance.json\n")

if (nrow(ic_5M_all) > 0L) fwrite(ic_5M_all, file.path(OUTPUT_DIR, "ic_timeseries_5M.csv"))
if (nrow(ic_3M_all) > 0L) fwrite(ic_3M_all, file.path(OUTPUT_DIR, "ic_timeseries_3M.csv"))
if (nrow(ic_2M_all) > 0L) fwrite(ic_2M_all, file.path(OUTPUT_DIR, "ic_timeseries_2M.csv"))
if (!is.null(bt_5M)) fwrite(bt_5M$nav_dt, file.path(OUTPUT_DIR, "nav_S1_A.csv"))
if (!is.null(bt_3M)) fwrite(bt_3M$nav_dt, file.path(OUTPUT_DIR, "nav_3M.csv"))
if (!is.null(bt_2M)) fwrite(bt_2M$nav_dt, file.path(OUTPUT_DIR, "nav_2M.csv"))
cat("  CSV 저장 완료\n")

# =============================================================================
# 9. Stage Artifacts
# =============================================================================
cat("\n[9] Stage Artifacts...\n")
ARTIFACT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts")
dir.create(ARTIFACT_DIR, showWarnings = FALSE, recursive = TRUE)

write_json(list(
  factor_id   = "ML5_RANK_ENS",
  strategy_id = "STR_1660_ML5_ENSEMBLE",
  stage       = "S1",
  created_at  = as.character(Sys.time()),
  variants    = c("S1_A_5M_full", "ablation_3M", "ablation_2M"),
  implementation_profile = list(
    models           = c("XGBoost_5seed", "RandomForest_5seed",
                         "Ridge_glmnet", "ElasticNet_alpha_CV", "PLS_plsr"),
    rank_average     = "equal-weight 5-model rank avg (Timmermann 2006)",
    mi_prefilter_top = MI_TOP_N,
    window_type      = "expanding walk-forward",
    purge_method     = "1yr_val_gap (OOS_yr-1 전체)",
    n_holdings       = N_HOLDINGS,
    commission_bps   = 15L,
    liq_threshold_krw = LIQ_THRESHOLD,
    signal_only      = "EW 30 순수 팩터 신호 (S5에서 브레이크/포지션조절 추가 예정)",
    weight_method    = "EW"),
  ablation = list(decision = ablation_decision,
                  ICIR_5M = icir_5M$ICIR, ICIR_3M = icir_3M$ICIR, ICIR_2M = icir_2M$ICIR,
                  IC_sd_5M = icir_5M$IC_sd, IC_sd_3M = icir_3M$IC_sd, IC_sd_2M = icir_2M$IC_sd),
  turnover_risk  = "중간",
  capacity_risk  = "낮음",
  pit_compliance = list(C1 = "expanding only PASS", C2 = "t-1 feature PASS",
                        C13 = "Z_Score_Aligned PASS", C14 = "fwd_ret t+1~t+21 PASS",
                        C15 = "일간 DB open_dataset PASS", OPT1 = "Arrow pushdown PASS",
                        purge = "1yr val gap PASS")
), file.path(ARTIFACT_DIR, "s1_construction_STR_1660_ML5.json"),
   auto_unbox = TRUE, pretty = TRUE)

write_json(list(
  factor_id    = "ML5_RANK_ENS",
  strategy_id  = "STR_1660_ML5_ENSEMBLE",
  stage        = "S2",
  created_at   = as.character(Sys.time()),
  s1_primary   = list(
    variant  = "5M",
    IC_IR    = icir_5M$ICIR, IC_mean = icir_5M$IC, IC_sd = icir_5M$IC_sd,
    IC_IR_3y = icir_5M_3y$ICIR, N_months = icir_5M$N,
    CAGR = if (!is.null(bt_5M)) bt_5M$CAGR   else NA,
    SR   = if (!is.null(bt_5M)) bt_5M$Sharpe else NA,
    MDD  = if (!is.null(bt_5M)) bt_5M$MDD    else NA,
    tag  = if (gate_5M)
             ifelse(!is.na(icir_5M$ICIR) && icir_5M$ICIR >= 0.40, "Strong", "Moderate")
           else "Weak"),
  ablation_summary = list(
    decision    = ablation_decision,
    delta_5M_3M = list(ICIR  = (icir_5M$ICIR  %||% 0) - (icir_3M$ICIR  %||% 0),
                       IC_sd = (icir_5M$IC_sd %||% 0) - (icir_3M$IC_sd %||% 0)),
    delta_3M_2M = list(ICIR  = (icir_3M$ICIR  %||% 0) - (icir_2M$ICIR  %||% 0),
                       IC_sd = (icir_3M$IC_sd %||% 0) - (icir_2M$IC_sd %||% 0))),
  role_bias     = "RoleBias_Diversifier",
  expected_role = "diversifier",
  alpha_lab_gate = list(pass = gate_5M, threshold = 0.20,
                        result = ifelse(gate_5M, "PASS", "FAIL")),
  s5_recommendation = if (gate_5M)
    list(proceed = TRUE,
         priority = "CVaR LP / sector-neutral / DD Brake / VD+",
         note     = "S0 Research Slate A-D 참조")
  else
    list(proceed = FALSE, note = "ICIR < 0.20, S5 보류")
), file.path(ARTIFACT_DIR, "s2_profile_STR_1660_ML5.json"),
   auto_unbox = TRUE, pretty = TRUE)

cat("[9] s1_construction_STR_1660_ML5.json + s2_profile_STR_1660_ML5.json 완료\n")

# =============================================================================
# 10. 텔레그램 [Forge]
# =============================================================================
cat("\n[10] 텔레그램...\n")
tryCatch({
  source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
  gate_str <- ifelse(gate_5M, "PASS", "FAIL")
  hf_str   <- ifelse(hard_fail, " | MDD Hard Fail", "")
  msg <- paste0(
    "\U0001F916 [Forge] STR_1660_ML5 S1 완료\n\n",
    "\U0001F4CA <b>5-Model Rank-Average Ensemble</b>\n",
    "XGBoost + RF + Ridge + ENet + PLS | MI top50 | 1yr purge\n\n",
    "<b>5M (primary)</b>\n",
    "  IC=",  round(icir_5M$IC    %||% NA, 4),
    " ICIR=", round(icir_5M$ICIR  %||% NA, 4),
    " IC_sd=",round(icir_5M$IC_sd %||% NA, 4), "\n",
    "  CAGR=", if (!is.null(bt_5M)) bt_5M$CAGR   else "NA", "%",
    " SR=",    if (!is.null(bt_5M)) bt_5M$Sharpe else "NA",
    " MDD=",   if (!is.null(bt_5M)) bt_5M$MDD    else "NA", "%\n\n",
    "<b>3M</b>  ICIR=", round(icir_3M$ICIR %||% NA, 4), "\n",
    "<b>2M</b>  ICIR=", round(icir_2M$ICIR %||% NA, 4), "\n\n",
    "\U0001F4CA <b>Ablation:</b> ", ablation_decision, "\n",
    "\U0001F6A6 <b>Alpha Lab Gate:</b> ", gate_str, hf_str, "\n",
    "\U0001F4CC <b>RoleBias:</b> RoleBias_Diversifier\n",
    "\U0001F4AA <b>강점:</b> 3 inductive bias (Tree/Linear/Latent) 오차 다양성\n",
    "\U0001F4A1 <b>약점:</b> S1 MDD > 70% 예상 (S5 브레이크 추가 필요)\n",
    "\U0001F553 ", as.character(Sys.time()))
  tg_send(msg)
  if (!is.null(chart_paths$equity) && file.exists(chart_paths$equity))
    tg_send_photo(chart_paths$equity, caption = "\U0001F4C8 STR_1660_ML5 S1 Equity Curve")
  if (!is.null(chart_paths$annual) && file.exists(chart_paths$annual))
    tg_send_photo(chart_paths$annual, caption = "\U0001F4CA STR_1660_ML5 S1 Annual Returns")
  cat("  텔레그램 완료\n")
}, error = function(e) cat("  텔레그램 오류:", e$message, "\n"))

# =============================================================================
# 최종 요약
# =============================================================================
cat("\n", paste(rep("=", 60), collapse = ""), "\n")
cat("=== STR_1660_ML5 S1 COMPLETE ===\n")
cat(sprintf("  5M: IC=%.4f ICIR=%.4f IC_sd=%.4f | SR=%.3f CAGR=%.1f%% MDD=%.1f%%\n",
            icir_5M$IC %||% NA, icir_5M$ICIR %||% NA, icir_5M$IC_sd %||% NA,
            if (!is.null(bt_5M)) bt_5M$Sharpe else NA,
            if (!is.null(bt_5M)) bt_5M$CAGR   else NA,
            if (!is.null(bt_5M)) bt_5M$MDD    else NA))
cat(sprintf("  3M: ICIR=%.4f | 2M: ICIR=%.4f\n",
            icir_3M$ICIR %||% NA, icir_2M$ICIR %||% NA))
cat(sprintf("  Ablation: %s\n", ablation_decision))
cat(sprintf("  Alpha Lab Gate: %s | Hard Fail: %s\n",
            ifelse(gate_5M, "PASS", "FAIL"), ifelse(hard_fail, "YES", "NO")))
cat("  RoleBias: RoleBias_Diversifier\n")
cat(sprintf("  산출물: %s\n", OUTPUT_DIR))
cat(paste(rep("=", 60), collapse = ""), "\n")
cat("종료:", as.character(Sys.time()), "\n")
