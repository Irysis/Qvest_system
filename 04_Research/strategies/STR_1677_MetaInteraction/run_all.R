## =============================================================================
## STR_1677_MetaInteraction: Regime x Factor Interaction XGBoost — S1 Implementation
## 핵심 아이디어: XGBoost 3-seed ensemble + MI prefilter(top50) +
##               Regime x Factor Interaction terms (z_fi * prob_k, 25항)
##               21일 refit expanding window + 월간 리밸런싱
##               EW 30종목 + 15bps commission + 유동성 2억원
##
## Phase 3b 수정 근거:
##   STR_1676 실패: regime probs는 날짜별 동일값 -> 종목 랭킹 불변
##   해결: interaction terms = z_fi(종목별) x prob_k(날짜별)
##         -> 종목마다 값이 달라 XGBoost가 국면별 팩터 중요도 학습 가능
##   월간 리밸런싱: interaction으로 종목 차별화 가능 -> 월간도 유효
##
## 학술 근거:
##   Gu, Kelly & Xiu (2020, RFS): XGBoost for asset pricing
##   Barroso & Santa-Clara (2015, JFE): Risk-managed momentum
##   Kan & Zhang (1999, JF): useless factors in cross-section
##
## PIT 준수 (C1-C15):
##   C1  : expanding window only
##   C2  : 21d purge gap; 월말 signal -> 익일 실행
##   C9  : regime probs: lookup Date-1 + roll=TRUE => Date < d (t-1 보장)
##   C13 : zscore_by_date 강제 (Z_Score_Aligned)
##   C14 : fwd_ret IS target 월말만
##   Interaction PIT: z_score(종목별, date d) x prob(시장, t-1) -> 둘 다 PIT 안전
##
## OPT 준수:
##   OPT-1: Arrow open_dataset predicate pushdown. 루프 내 parquet 로드 없음.
##   OPT-2: load_rawdata(use_cache=TRUE) 1회
##   Regime: open_dataset + collect 1회 (소파일 ~200 rows, 루프 밖)
## =============================================================================

cat("=== STR_1677_MetaInteraction: Regime x Factor Interaction XGBoost ===\n")
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
# 경로 (normalizePath 금지 — WSL 한글 경로 버그)
# =============================================================================
PROJECT_ROOT        <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
STRATEGY_DIR        <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1677_MetaInteraction")
OUTPUT_DIR          <- file.path(STRATEGY_DIR, "output")
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
DAILY_DB_DIR        <- file.path(PROJECT_ROOT, ".cache/factor_db_daily")
REGIME_PARQUET_PATH <- file.path(PROJECT_ROOT, ".cache/regime_factor_clusters.parquet")

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

# =============================================================================
# CONFIG
# =============================================================================
LIQ_THRESHOLD     <- 2e8
N_HOLDINGS        <- 30L
COMMISSION        <- 0.0015
MI_TOP_N          <- 50L
INTERACTION_TOP_N <- 5L
N_REGIME_PROBS    <- 5L
PURGE_DAYS        <- 21L
XGB_SEEDS         <- c(42L, 123L, 456L)
REFIT_DAYS        <- 21L
MI_REFRESH        <- 63L
MACRO_PAT         <- "^(RE_|RE0|RE1)"
XGB_MAX_ROWS      <- 80000L
OOS_START         <- as.Date("2009-06-01")
OOS_END           <- as.Date("2025-12-31")
IS_START          <- as.Date("2003-01-01")
BUFFER_KEEP       <- 45L
BUFFER_ENTRY      <- 28L

N_INTERACTION <- INTERACTION_TOP_N * N_REGIME_PROBS   # 5 x 5 = 25
N_TOTAL_FEAT  <- MI_TOP_N + N_INTERACTION              # 50 + 25 = 75
PROB_COLS     <- paste0("prob_", seq_len(N_REGIME_PROBS))

cat(sprintf("[CONFIG] N=%d | MI=%d | interaction=%dx%d=%d | total_feat=%d\n",
            N_HOLDINGS, MI_TOP_N, INTERACTION_TOP_N, N_REGIME_PROBS,
            N_INTERACTION, N_TOTAL_FEAT))
cat(sprintf("         seeds=%s | refit=%dd | rebal=monthly\n",
            paste(XGB_SEEDS, collapse = ","), REFIT_DAYS))

xgb_ok <- tryCatch({ library(xgboost); TRUE }, error = function(e) FALSE)
if (!xgb_ok) stop("xgboost 패키지 필요")

# =============================================================================
# [0] Regime 데이터 1회 로드 (OPT-1: open_dataset + collect, 루프 밖 단 1회)
#     주의: 파일 로드 함수는 open_dataset만 사용 (다른 로드 함수 금지)
# =============================================================================
cat("\n[0] Regime 데이터 로드...\n")
REGIME_DT <- tryCatch({
  ds_r  <- open_dataset(REGIME_PARQUET_PATH, format = "parquet")
  r_cols <- schema(ds_r)$names
  keep_r <- intersect(c("Date", "cluster_id", PROB_COLS), r_cols)
  dt <- ds_r |> select(all_of(keep_r)) |> collect() |> as.data.table()
  dt[, Date := as.Date(Date)]
  setkey(dt, Date)
  dt
}, error = function(e) {
  cat("  Regime 로드 실패:", e$message, "\n"); NULL
})
if (is.null(REGIME_DT) || nrow(REGIME_DT) == 0L) stop("Regime 로드 실패")
cat(sprintf("    rows=%d | %s ~ %s\n",
            nrow(REGIME_DT), min(REGIME_DT$Date), max(REGIME_DT$Date)))

# Rolling join 헬퍼 (C9: Date < query_date 보장)
# lookup Date - 1L 트릭: roll=TRUE는 Date <= lookup 이므로
# lookup = query - 1 => 반환 regime Date <= query - 1 = Date < query
build_regime_map_roll <- function(dates_vec) {
  lookup  <- data.table(orig_date = as.Date(dates_vec),
                        Date      = as.Date(dates_vec) - 1L)
  setkey(lookup, Date)
  joined  <- REGIME_DT[lookup, roll = TRUE, on = "Date"]
  joined[, Date := orig_date][, orig_date := NULL]
  joined
}

# =============================================================================
# [1] RAWDATA 1회 로드 (OPT-2)
# =============================================================================
cat("\n[1] RAWDATA...\n")
rw      <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw$RAWDATA; BM_DT_SAVED <- rw$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
cat(sprintf("    %d rows | %s ~ %s\n", nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date)))

# =============================================================================
# [2] 21d forward return (C14: t+1~t+21, 월말 only)
# =============================================================================
cat("[2] 21d fwd return...\n")
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

RAWDATA[, ym__ := format(Date, "%Y-%m")]
ALL_ME_DATES <- RAWDATA[, .(me_date = max(Date)), by = ym__][order(me_date)]$me_date
RAWDATA[, ym__ := NULL]

ALL_TRADE_DATES <- sort(unique(RAWDATA$Date))
ALL_OOS_DATES   <- ALL_TRADE_DATES[ALL_TRADE_DATES >= OOS_START &
                                     ALL_TRADE_DATES <= OOS_END]
OOS_ME_DATES    <- ALL_ME_DATES[ALL_ME_DATES >= OOS_START & ALL_ME_DATES <= OOS_END]

cat(sprintf("    fwd rows: %d | OOS ME dates: %d\n", nrow(ret_dt), length(OOS_ME_DATES)))

SIZE_DT <- RAWDATA[Date >= IS_START, .(Date, Ticker, Size)]
setkey(SIZE_DT, Date, Ticker)
ret_dt[, c("Ret", "Size") := NULL]
setkey(ret_dt, Date, Ticker)
rm(RAWDATA, rw); gc()

# =============================================================================
# [3] Arrow Dataset (OPT-1: open_dataset, 루프 밖)
# =============================================================================
cat("[3] Arrow Dataset...\n")
pq_files <- list.files(DAILY_DB_DIR, pattern = "\\.parquet$", full.names = TRUE)
ds_daily <- open_dataset(pq_files, format = "parquet")
ds_cols  <- schema(ds_daily)$names
EXCL     <- c("Date", "Ticker",
               grep("^(dps_1y|bps_1y|eps_1y|target_price)", ds_cols, value = TRUE),
               grep("\\.x$|\\.y$", ds_cols, value = TRUE),
               grep(MACRO_PAT, ds_cols, value = TRUE))
USE_FCOLS <- setdiff(ds_cols, EXCL)
cat(sprintf("    사용 팩터=%d\n", length(USE_FCOLS)))

arrow_collect <- function(fcols, dates_vec = NULL, d0 = NULL, d1 = NULL) {
  need <- intersect(c("Date", "Ticker", fcols), ds_cols)
  q    <- ds_daily
  if (!is.null(dates_vec)) q <- q |> filter(Date %in% dates_vec)
  else                     q <- q |> filter(Date >= d0, Date <= d1)
  q |> select(all_of(need)) |> collect() |> as.data.table() |>
    (\(x) { setkey(x, Date, Ticker); x })()
}

build_mat <- function(dt, cols) {
  m <- as.matrix(dt[, intersect(cols, names(dt)), with = FALSE])
  m[!is.finite(m)] <- 0; m
}

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
# [3b] MI prefilter (chunked)
# =============================================================================
mi_prefilter_chunked <- function(d0, d1, fcols, n_top = 50L) {
  me_vec   <- ALL_ME_DATES[ALL_ME_DATES >= d0 & ALL_ME_DATES <= d1]
  if (length(me_vec) == 0L) return(list(top_f = character(0), top5_f = character(0)))
  chunk_sz <- 60L
  f_chunks <- split(fcols, ceiling(seq_along(fcols) / chunk_sz))
  all_ics  <- numeric(0)
  for (i in seq_along(f_chunks)) {
    ch    <- f_chunks[[i]]
    ch_dt <- tryCatch(arrow_collect(ch, dates_vec = me_vec), error = function(e) NULL)
    if (is.null(ch_dt) || nrow(ch_dt) == 0L) next
    ch_dt <- zscore_by_date(ch_dt, ch)
    ch_dt <- merge(ch_dt, ret_dt[, .(Date, Ticker, fwd_ret_21d)],
                   by = c("Date", "Ticker"))
    ch_dt <- ch_dt[!is.na(fwd_ret_21d)]
    y     <- ch_dt$fwd_ret_21d
    for (f in ch) {
      x <- ch_dt[[f]]; v <- is.finite(x) & is.finite(y)
      if (sum(v) < 100L) next
      all_ics[f] <- tryCatch(abs(cor(x[v], y[v], method = "spearman")),
                              error = function(e) NA_real_)
    }
    rm(ch_dt); gc(FALSE)
  }
  valid  <- all_ics[!is.na(all_ics)]
  if (!length(valid)) return(list(top_f = character(0), top5_f = character(0)))
  ranked <- names(sort(valid, decreasing = TRUE))
  list(top_f  = ranked[seq_len(min(n_top, length(ranked)))],
       top5_f = ranked[seq_len(min(INTERACTION_TOP_N, length(ranked)))])
}

# =============================================================================
# [4] Interaction feature 생성 (벡터화: merge + 벡터 곱)
#     루프 없음. data.table merge 후 열별 벡터 곱.
# =============================================================================
add_interaction_features <- function(X_dt, regime_map, top5_f) {
  regime_sub <- regime_map[, c("Date", PROB_COLS), with = FALSE]
  Xm         <- merge(X_dt, regime_sub, by = "Date", all.x = TRUE)
  int_cols   <- character(0)
  for (fi in top5_f) {
    if (!fi %in% names(Xm)) next
    z_fi <- Xm[[fi]]
    for (k in seq_len(N_REGIME_PROBS)) {
      pk   <- PROB_COLS[k]
      cn   <- paste0("int__", fi, "__p", k)
      pk_v <- Xm[[pk]]
      Xm[, (cn) := fifelse(is.finite(z_fi) & is.finite(pk_v), z_fi * pk_v, 0)]
      int_cols <- c(int_cols, cn)
    }
  }
  Xm[, (PROB_COLS) := NULL]
  list(dt = Xm, int_cols = int_cols)
}

# =============================================================================
# [5] XGBoost 3-seed
# =============================================================================
XGB_PARAMS <- list(booster = "gbtree", objective = "reg:squarederror",
                   eta = 0.02, max_depth = 5L, subsample = 0.7,
                   colsample_bytree = 0.5, min_child_weight = 10L,
                   lambda = 1, alpha = 0.1, nthread = 2L)

xgb3_train <- function(X_tr, y_tr, seeds = XGB_SEEDS, max_rows = XGB_MAX_ROWS) {
  if (nrow(X_tr) > max_rows) {
    idx  <- sample(nrow(X_tr), max_rows)
    X_tr <- X_tr[idx, , drop = FALSE]; y_tr <- y_tr[idx]
  }
  models <- lapply(seeds, function(sd) {
    set.seed(sd)
    tryCatch({
      dtr <- xgb.DMatrix(data = X_tr, label = y_tr)
      m   <- xgb.train(XGB_PARAMS, dtr, 300L, verbose = 0L)
      rm(dtr); gc(FALSE); m
    }, error = function(e) { cat("    xgb err:", e$message, "\n"); NULL })
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
  n_te  <- nrow(X_te)
  rmat  <- vapply(valid, function(p) frank(p, ties.method = "average") / n_te, numeric(n_te))
  if (is.null(dim(rmat))) rmat else rowMeans(rmat)
}

# =============================================================================
# [6] Refit 스케줄
# =============================================================================
cat("\n[6] Refit schedule...\n")
refit_starts  <- seq(1L, length(ALL_OOS_DATES), by = REFIT_DAYS)
refit_windows <- lapply(refit_starts, function(i) {
  end_i <- min(i + REFIT_DAYS - 1L, length(ALL_OOS_DATES))
  ALL_OOS_DATES[i:end_i]
})
OOS_ME_SET <- as.integer(OOS_ME_DATES)
cat(sprintf("    Refit windows: %d | Signal dates (ME): %d\n",
            length(refit_windows), length(OOS_ME_DATES)))

# =============================================================================
# [7] Walk-Forward: 21-day refit + 월말 scoring + interaction
# =============================================================================
cat("\n[7] Walk-Forward (21d refit + 월말 scoring + interaction)...\n")
all_me_scores <- list()
all_ic_recs   <- list()
mi_cache      <- NULL
mi_last_ref   <- 0L
t0_loop       <- Sys.time()

for (wi in seq_along(refit_windows)) {
  win_dates   <- refit_windows[[wi]]
  win_start_d <- min(win_dates)
  win_end_d   <- max(win_dates)
  is_end_d    <- win_start_d - PURGE_DAYS

  if (is_end_d < IS_START + 365L) next
  if (win_start_d < OOS_START)    next

  win_me <- win_dates[as.integer(win_dates) %in% OOS_ME_SET]
  if (length(win_me) == 0L) next

  if (wi %% 10 == 1) {
    el <- as.numeric(difftime(Sys.time(), t0_loop, units = "mins"))
    cat(sprintf("  [%d/%d] %s~%s IS->%s ME:%d | %.1f min\n",
                wi, length(refit_windows),
                win_start_d, win_end_d, is_end_d, length(win_me), el))
  }

  # MI prefilter (63일마다 갱신)
  mi_last_ref <- mi_last_ref + length(win_dates)
  if (is.null(mi_cache) || mi_last_ref >= MI_REFRESH) {
    if (wi %% 10 == 1) cat("    MI refresh...\n")
    mi_cache  <- mi_prefilter_chunked(IS_START, is_end_d, USE_FCOLS, MI_TOP_N)
    mi_last_ref <- 0L
  }
  top_f  <- mi_cache$top_f
  top5_f <- mi_cache$top5_f
  if (length(top_f) < 5L) next

  # IS 날짜
  is_me_d <- ALL_ME_DATES[ALL_ME_DATES >= IS_START & ALL_ME_DATES <= is_end_d]
  if (length(is_me_d) < 24L) next

  # IS regime map (C9: t-1)
  is_regime_map <- build_regime_map_roll(is_me_d)

  # IS 데이터 수집
  is_dt <- tryCatch(arrow_collect(top_f, dates_vec = is_me_d), error = function(e) NULL)
  if (is.null(is_dt) || nrow(is_dt) < 1000L) next
  is_dt <- zscore_by_date(is_dt, top_f)
  is_dt <- merge(is_dt, ret_dt[, .(Date, Ticker, fwd_ret_21d)],
                 by = c("Date", "Ticker"))
  is_dt <- merge(is_dt, SIZE_DT, by = c("Date", "Ticker"), all.x = TRUE)
  is_dt <- is_dt[!is.na(fwd_ret_21d) & !is.na(Size) & Size >= LIQ_THRESHOLD]

  # IS interaction features (벡터화)
  is_int   <- add_interaction_features(is_dt, is_regime_map, top5_f)
  is_aug   <- is_int$dt
  int_cols <- is_int$int_cols
  all_feat <- c(top_f, int_cols)

  X_tr <- build_mat(is_aug, all_feat)
  y_tr <- is_aug$fwd_ret_21d
  rm(is_dt, is_aug, is_int); gc(FALSE)
  if (nrow(X_tr) < 500L) { rm(X_tr, y_tr); next }

  models <- xgb3_train(X_tr, y_tr)
  rm(X_tr, y_tr); gc(FALSE)
  if (!length(models)) next

  # OOS 월말 regime map (C9: t-1)
  oos_me_regime <- build_regime_map_roll(win_me)

  # OOS 월말 데이터 수집
  oos_me <- tryCatch(arrow_collect(top_f, dates_vec = win_me), error = function(e) NULL)
  if (is.null(oos_me) || nrow(oos_me) == 0L) { rm(models); gc(FALSE); next }
  oos_me <- zscore_by_date(oos_me, top_f)
  oos_me <- merge(oos_me, SIZE_DT, by = c("Date", "Ticker"), all.x = TRUE)
  oos_me <- oos_me[!is.na(Size) & Size >= LIQ_THRESHOLD]

  # OOS interaction features (벡터화)
  oos_int <- add_interaction_features(oos_me, oos_me_regime, top5_f)
  oos_aug <- oos_int$dt
  rm(oos_me, oos_int)

  # 날짜별 scoring
  scored_list <- list()
  for (d in unique(oos_aug$Date)) {
    day_dt <- oos_aug[Date == d]
    X_te   <- build_mat(day_dt, all_feat)
    if (nrow(X_te) < 10L) next
    scored_list[[as.character(d)]] <-
      day_dt[, .(Date, Ticker, Size, Score = xgb3_score(models, X_te))]
  }
  rm(oos_aug); gc(FALSE)

  if (length(scored_list) > 0L) {
    win_scores <- rbindlist(scored_list)
    all_me_scores[[wi]] <- win_scores

    # IC 기록
    for (d in unique(win_scores$Date)) {
      d_scores <- win_scores[Date == d]
      d_ret    <- ret_dt[Date == d, .(Date, Ticker, fwd_ret_21d)]
      ic_m     <- merge(d_scores, d_ret, by = c("Date", "Ticker"))
      ic_m     <- ic_m[!is.na(fwd_ret_21d) & !is.na(Score)]
      if (nrow(ic_m) >= 30L) {
        ic_val <- tryCatch(cor(ic_m$Score, ic_m$fwd_ret_21d,
                               method = "spearman", use = "complete.obs"),
                            error = function(e) NA_real_)
        all_ic_recs[[length(all_ic_recs) + 1L]] <-
          data.table(Date = as.Date(d), ym = format(as.Date(d), "%Y-%m"),
                     IC = ic_val, variant = "MetaInteraction_Monthly")
      }
    }
    rm(win_scores, scored_list)
  }

  rm(models, int_cols, all_feat); gc(FALSE)
}

elapsed_total <- as.numeric(difftime(Sys.time(), t0_loop, units = "mins"))
cat(sprintf("  Walk-forward 완료: %.1f분\n", elapsed_total))

# =============================================================================
# [8] Score 통합 + IC
# =============================================================================
cat("\n[8] Score 통합 + IC...\n")
me_scores_all <- rbindlist(Filter(Negate(is.null), all_me_scores), fill = TRUE)
cat(sprintf("    월말 Score rows: %s (%d dates)\n",
            format(nrow(me_scores_all), big.mark = ","), uniqueN(me_scores_all$Date)))

ic_all <- rbindlist(Filter(Negate(is.null), all_ic_recs), fill = TRUE)
if (nrow(ic_all) > 0L) {
  ic_mean <- mean(ic_all$IC, na.rm = TRUE)
  ic_sd   <- sd(ic_all$IC, na.rm = TRUE)
  icir    <- if (ic_sd > 0) ic_mean / ic_sd else NA_real_
  ic_3y   <- ic_all[Date >= (OOS_END - 365 * 3)]
  icir_3y <- if (nrow(ic_3y) > 4L)
    mean(ic_3y$IC, na.rm = TRUE) / sd(ic_3y$IC, na.rm = TRUE) else NA
  cat(sprintf("    IC=%.4f ICIR=%.4f N=%d | 3Y ICIR=%.4f\n",
              ic_mean, icir, nrow(ic_all), icir_3y %||% NA))
  gate_pass <- !is.na(icir) && icir >= 0.20
  cat(sprintf("    Alpha Lab Gate: %s\n", ifelse(gate_pass, "PASS", "FAIL")))
} else {
  ic_mean <- NA; icir <- NA; icir_3y <- NA; gate_pass <- FALSE
  cat("    IC 없음\n")
}

# =============================================================================
# [9] 백테스트 (월간 리밸런싱)
# =============================================================================
cat("\n[9] 백테스트 (월간)...\n")
rw2     <- load_rawdata(use_cache = TRUE)
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

if (!is.null(bt)) {
  r   <- bt$DAILY_NAV_DT$Strategy_Ret; r <- r[is.finite(r)]
  cum <- cumprod(1 + r); nyr <- length(r) / 252
  bt_CAGR   <- round((tail(cum, 1)^(1/nyr) - 1) * 100, 2)
  bt_Sharpe <- round(mean(r) / sd(r) * sqrt(252), 4)
  bt_MDD    <- round(min(cum / cummax(cum) - 1) * 100, 2)
  hard_fail <- abs(bt_MDD) > 45
  cat(sprintf("  >> CAGR %.1f%% | SR %.4f | MDD %.1f%% | Hard Fail: %s\n",
              bt_CAGR, bt_Sharpe, bt_MDD, hard_fail))
  cat(sprintf("  >> 베이스라인: STR_1675 Q-rebal SR=0.72 | 이번 SR=%.4f\n", bt_Sharpe))
} else {
  bt_CAGR <- NA; bt_Sharpe <- NA; bt_MDD <- NA; hard_fail <- TRUE
}

# =============================================================================
# [10] 차트
# =============================================================================
cat("\n[10] 차트...\n")
chart_paths <- list()
tryCatch({
  if (!is.null(bt)) {
    eq_dt <- copy(bt$DAILY_NAV_DT)[, .(Date = as.Date(Date), ret = Strategy_Ret)]
    eq_dt <- eq_dt[is.finite(ret)][, cum := cumprod(1 + ret)][, label := "MetaInteraction"]

    bm_v  <- BM_DT[order(Date), .(Date = as.Date(Date), BM_Ret)]
    bm_v[, cum := cumprod(1 + fifelse(is.finite(BM_Ret), BM_Ret, 0))][, label := "KOSPI BM"]
    eq_all <- rbind(eq_dt[, .(Date, cum, label)], bm_v[, .(Date, cum, label)])

    p1 <- ggplot(eq_all, aes(x = Date, y = cum, color = label, linetype = label)) +
      geom_line(linewidth = 0.8) + scale_y_log10(labels = scales::comma) +
      scale_color_manual(values = c("MetaInteraction" = "#d62728", "KOSPI BM" = "#7f7f7f")) +
      scale_linetype_manual(values = c("MetaInteraction" = "solid", "KOSPI BM" = "dotted")) +
      labs(title = "STR_1677 MetaInteraction — Regime x Factor Interaction",
           subtitle = sprintf("top5 MI x 5 regime probs | 21d refit | Monthly | EW30 | SR %.3f CAGR %.1f%% MDD %.1f%%",
                              bt_Sharpe %||% NA, bt_CAGR %||% NA, bt_MDD %||% NA),
           x = NULL, y = "Cumulative (Log)", color = NULL, linetype = NULL) +
      theme_minimal(base_size = 12) + theme(legend.position = "bottom")
    ep <- file.path(OUTPUT_DIR, "equity_curve.png")
    ggsave(ep, p1, width = 12, height = 6, dpi = 150)
    chart_paths$equity <- ep; cat("  equity_curve.png\n")

    ar <- copy(bt$DAILY_NAV_DT)[, .(Date = as.Date(Date), ret = Strategy_Ret)]
    ar <- ar[is.finite(ret)][, yr := as.integer(format(Date, "%Y"))]
    ar <- ar[, .(annual_ret = prod(1 + ret) - 1), by = yr]
    p2 <- ggplot(ar, aes(x = factor(yr), y = annual_ret * 100, fill = annual_ret >= 0)) +
      geom_col(width = 0.7) +
      scale_fill_manual(values = c("TRUE" = "#d62728", "FALSE" = "#1f77b4"), guide = "none") +
      geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
      labs(title = "STR_1677 MetaInteraction — Annual Returns",
           x = NULL, y = "Return (%)") +
      theme_minimal(base_size = 11) +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
    ap <- file.path(OUTPUT_DIR, "annual_returns.png")
    ggsave(ap, p2, width = 14, height = 6, dpi = 150)
    chart_paths$annual <- ap; cat("  annual_returns.png\n")
  }

  if (nrow(ic_all) > 0L) {
    ic_all[, dt := as.Date(paste0(ym, "-01"))]
    p3 <- ggplot(ic_all, aes(x = dt, y = IC)) +
      geom_line(alpha = 0.5, color = "#d62728") +
      geom_smooth(se = FALSE, method = "loess", span = 0.3,
                  linewidth = 1.1, color = "#1f77b4") +
      geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
      labs(title = "STR_1677 MetaInteraction — Monthly IC",
           subtitle = sprintf("ICIR=%.3f | 3Y ICIR=%.3f", icir %||% NA, icir_3y %||% NA),
           x = NULL, y = "Spearman IC") +
      theme_minimal(base_size = 11)
    ip <- file.path(OUTPUT_DIR, "ic_timeseries.png")
    ggsave(ip, p3, width = 12, height = 5, dpi = 150)
    chart_paths$ic <- ip; cat("  ic_timeseries.png\n")
  }
}, error = function(e) cat("  차트 오류:", e$message, "\n"))

# =============================================================================
# [11] 결과 저장
# =============================================================================
cat("\n[11] 결과 저장...\n")
perf <- list(
  strategy_id = "STR_1677_MetaInteraction",
  variant     = "MetaInteraction_Monthly",
  timestamp   = as.character(Sys.time()),
  results = list(
    ICIR = round(icir %||% NA, 4), IC = round(ic_mean %||% NA, 5),
    N_months = nrow(ic_all), ICIR_3y = round(icir_3y %||% NA, 4),
    gate_pass = gate_pass, CAGR = bt_CAGR,
    Sharpe = bt_Sharpe, MDD = bt_MDD, hard_fail = hard_fail
  ),
  baseline = list(
    STR_1675_quarterly = list(SR = 0.72),
    STR_1676_monthly   = list(SR = NA, note = "regime 직접 사용 실패"),
    STR_1677_monthly   = list(SR = bt_Sharpe %||% NA)
  ),
  alpha_lab_gate = list(pass = gate_pass, ICIR = round(icir %||% NA, 4), threshold = 0.20),
  interaction_design = list(
    mi_top_n = MI_TOP_N, interaction_top_n = INTERACTION_TOP_N,
    n_regime_probs = N_REGIME_PROBS, n_interaction = N_INTERACTION,
    n_total_features = N_TOTAL_FEAT,
    vectorization = "data.table merge + vectorized multiply (no per-date loop)",
    regime_join = "build_regime_map_roll: lookup=Date-1, roll=TRUE => Date < d (C9)"
  ),
  pit_checks = list(
    C1 = "expanding window", C2 = "21d purge; month-end signal -> next day",
    C9 = "regime Date < d: lookup=query-1 + roll=TRUE",
    C13 = "zscore_by_date", C14 = "fwd_ret IS month-end only",
    interaction = "z(stock,d) x prob(market,t-1) — both PIT safe"
  ),
  config = list(
    seeds = XGB_SEEDS, mi_top_n = MI_TOP_N, refit_days = REFIT_DAYS,
    mi_refresh = MI_REFRESH, purge_days = PURGE_DAYS,
    n_holdings = N_HOLDINGS, commission = COMMISSION, liq = LIQ_THRESHOLD,
    buffer = list(keep = BUFFER_KEEP, entry = BUFFER_ENTRY), rebal = "monthly"
  ),
  runtime_min = round(elapsed_total, 1)
)
write_json(perf, file.path(OUTPUT_DIR, "performance.json"), auto_unbox = TRUE, pretty = TRUE)
if (nrow(ic_all) > 0L)        fwrite(ic_all, file.path(OUTPUT_DIR, "ic_timeseries.csv"))
if (!is.null(bt))              fwrite(bt$DAILY_NAV_DT, file.path(OUTPUT_DIR, "nav.csv"))
if (nrow(me_scores_all) > 0L) fwrite(me_scores_all, file.path(OUTPUT_DIR, "me_scores.csv"))
cat("  저장 완료\n")

cat(sprintf("\n=== 완료 (%s) | %.1f분 ===\n", Sys.time(), elapsed_total))
cat(sprintf("=== STR_1677: ICIR=%.4f | SR=%.4f | CAGR=%.1f%% | MDD=%.1f%% ===\n",
            icir %||% NA, bt_Sharpe %||% NA, bt_CAGR %||% NA, bt_MDD %||% NA))
cat(sprintf("=== 베이스라인: STR_1675(Q) SR=0.72 → STR_1677(M+Interaction) SR=%.4f ===\n",
            bt_Sharpe %||% NA))
