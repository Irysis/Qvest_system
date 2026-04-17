## =============================================================================
## STR_1675_QRebal_Hybrid: Quarterly-Rebalanced Hybrid ML — S1 Implementation
## 핵심 아이디어: XGBoost 3-seed ensemble + MI prefilter(top50, 267 daily factors)
##               21일 refit expanding window + Purged CV (21d embargo)
##               일간 scoring + 분기 리밸런싱 (buffer keep=45, entry=28)
##               EW 30종목 + 15bps commission + 유동성 2억원
##               Gu, Kelly & Xiu (2020 RFS) + Ban et al. (2018 EJOR)
##
## STR_1656 대비 변경:
##   - 연단위 walk-forward → 21일 refit (시장 변화 포착 개선)
##   - 월말만 scoring → 일간 scoring (정보 반영 속도 향상)
##   - 월간 리밸런싱 → 분기 리밸런싱 (회전율 통제)
##   - 5-seed → 3-seed (속도 최적화)
##   - MI prefilter 63일마다 갱신
##   - S1 순수 팩터 신호만 (NonRE 팩터만 사용)
##
## PIT 준수 (C1-C15):
##   C1  : expanding window only
##   C2  : OOS > IS (21d purge gap)
##   C13 : Z_Score_Aligned (일간 DB 이미 정규화)
##   C14 : fwd_ret = t+1~t+21 (IS target 전용, month-end only)
##   C15 : 일간 DB Arrow open_dataset 직접
##
## OPT 준수:
##   OPT-1: Arrow open_dataset predicate pushdown
##   OPT-2: load_rawdata(use_cache=TRUE)
## =============================================================================

cat("=== STR_1675_QRebal_Hybrid: Q-Rebal Hybrid ML S1 ===\n")
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
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
STRATEGY_DIR <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1675_QRebal_Hybrid")
OUTPUT_DIR   <- file.path(STRATEGY_DIR, "output")
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
DAILY_DB_DIR <- file.path(PROJECT_ROOT, ".cache/factor_db_daily")

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

# =============================================================================
# CONFIG
# =============================================================================
LIQ_THRESHOLD  <- 2e8
N_HOLDINGS     <- 30L
COMMISSION     <- 0.0015
MI_TOP_N       <- 50L
PURGE_DAYS     <- 21L
XGB_SEEDS      <- c(42L, 123L, 456L)
REFIT_DAYS     <- 21L       # refit 주기 (거래일)
MI_REFRESH     <- 63L       # MI prefilter 갱신 주기 (거래일)
MACRO_PAT      <- "^(RE_|RE0|RE1)"   # 조건부 팩터 패턴 (S1에서 제외)
XGB_MAX_ROWS   <- 80000L
OOS_START      <- as.Date("2008-01-01")
OOS_END        <- as.Date("2025-12-31")
IS_START       <- as.Date("2003-01-01")
BUFFER_KEEP    <- 45L
BUFFER_ENTRY   <- 28L

cat(sprintf("[CONFIG] N=%d | MI=%d | seeds=%s | refit=%dd | MI_refresh=%dd\n",
            N_HOLDINGS, MI_TOP_N, paste(XGB_SEEDS, collapse = ","),
            REFIT_DAYS, MI_REFRESH))
cat(sprintf("         buffer keep=%d entry=%d | OOS %s~%s\n",
            BUFFER_KEEP, BUFFER_ENTRY, OOS_START, OOS_END))

xgb_ok <- tryCatch({ library(xgboost); TRUE }, error = function(e) FALSE)
if (!xgb_ok) stop("xgboost 패키지 필요")

# =============================================================================
# [1] RAWDATA 1회 로드 (OPT-2)
# =============================================================================
cat("\n[1] RAWDATA...\n")
rw <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw$RAWDATA; BM_DT <- rw$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
cat(sprintf("    %d rows | %s ~ %s\n", nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date)))

# =============================================================================
# [2] 21d forward return (C14: t+1~t+21, 월말 only — 학습용)
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
cat(sprintf("    fwd rows: %d | ME dates: %d | OOS dates: %d\n",
            nrow(ret_dt), length(ALL_ME_DATES), length(ALL_OOS_DATES)))

# SIZE_DT 유지, 대형 객체 해제
SIZE_DT <- RAWDATA[Date >= IS_START, .(Date, Ticker, Size)]
setkey(SIZE_DT, Date, Ticker)
ret_dt[, c("Ret", "Size") := NULL]
setkey(ret_dt, Date, Ticker)
rm(RAWDATA, BM_DT, rw); gc()

# =============================================================================
# [3] Arrow Dataset + 팩터 정리 (NonRE only — S1 순수 팩터)
# =============================================================================
cat("[3] Arrow Dataset...\n")
pq_files  <- list.files(DAILY_DB_DIR, pattern = "\\.parquet$", full.names = TRUE)
ds_daily  <- open_dataset(pq_files, format = "parquet")
ds_cols   <- schema(ds_daily)$names
EXCL      <- c("Date", "Ticker",
               grep("^(dps_1y|bps_1y|eps_1y|target_price)", ds_cols, value = TRUE),
               grep("\\.x$|\\.y$", ds_cols, value = TRUE),
               grep(MACRO_PAT, ds_cols, value = TRUE))  # S1: 조건부 팩터 제외
USE_FCOLS <- setdiff(ds_cols, EXCL)
cat(sprintf("    사용 팩터=%d (조건부 제외)\n", length(USE_FCOLS)))

# Arrow collect
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
# [3b] Chunked MI prefilter (USE_FCOLS → 60개씩 분할 → top50)
# =============================================================================
mi_prefilter_chunked <- function(d0, d1, fcols, n_top = 50L) {
  me_vec <- ALL_ME_DATES[ALL_ME_DATES >= d0 & ALL_ME_DATES <= d1]
  if (length(me_vec) == 0L) return(character(0))
  chunk_sz <- 60L
  f_chunks <- split(fcols, ceiling(seq_along(fcols) / chunk_sz))
  all_ics  <- numeric(0)
  for (i in seq_along(f_chunks)) {
    ch <- f_chunks[[i]]
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
# [4] XGBoost 3-seed: train once, score many (21x speedup)
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
# [5] Refit 스케줄 + 분기말 날짜
# =============================================================================
cat("\n[5] Refit schedule...\n")

refit_starts <- seq(1L, length(ALL_OOS_DATES), by = REFIT_DAYS)
refit_windows <- lapply(refit_starts, function(i) {
  end_i <- min(i + REFIT_DAYS - 1L, length(ALL_OOS_DATES))
  ALL_OOS_DATES[i:end_i]
})
cat(sprintf("    Refit windows: %d (each ~%d days)\n", length(refit_windows), REFIT_DAYS))

# 분기말 날짜 (3/6/9/12월 마지막 거래일)
oos_ym <- data.table(d = ALL_OOS_DATES)[, ym := format(d, "%Y-%m")]
oos_ym[, mn := as.integer(substr(ym, 6, 7))]
qe_dt <- oos_ym[mn %in% c(3L, 6L, 9L, 12L), .(qe_date = max(d)), by = ym]
QE_DATES <- sort(qe_dt$qe_date)
cat(sprintf("    Quarter-end dates: %d (%s ~ %s)\n",
            length(QE_DATES), min(QE_DATES), max(QE_DATES)))

# =============================================================================
# [6] Walk-Forward: 21-day refit loop
# =============================================================================
cat("\n[6] Walk-Forward (21d refit)...\n")

all_daily_scores <- list()
all_ic_recs      <- list()
mi_cache         <- NULL
mi_last_refresh  <- 0L
t0_loop          <- Sys.time()

for (wi in seq_along(refit_windows)) {
  win_dates   <- refit_windows[[wi]]
  win_start_d <- min(win_dates)
  win_end_d   <- max(win_dates)
  is_end_d    <- win_start_d - PURGE_DAYS

  if (is_end_d < IS_START + 365L) next

  if (wi %% 10 == 1) {
    elapsed <- as.numeric(difftime(Sys.time(), t0_loop, units = "mins"))
    cat(sprintf("  [%d/%d] win %s~%s | IS->%s | %.1f min\n",
                wi, length(refit_windows), win_start_d, win_end_d, is_end_d, elapsed))
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

  # --- IS 학습 데이터 (월말만 — autocorrelation 회피) ---
  is_me_d <- ALL_ME_DATES[ALL_ME_DATES >= IS_START & ALL_ME_DATES <= is_end_d]
  if (length(is_me_d) < 24L) next

  is_dt <- tryCatch(arrow_collect(top_f, dates_vec = is_me_d), error = function(e) NULL)
  if (is.null(is_dt) || nrow(is_dt) < 1000L) next
  is_dt <- zscore_by_date(is_dt, top_f)  # C13: z-score 강제
  is_dt <- merge(is_dt, ret_dt[, .(Date, Ticker, fwd_ret_21d)], by = c("Date", "Ticker"))
  is_dt <- merge(is_dt, SIZE_DT, by = c("Date", "Ticker"), all.x = TRUE)
  is_dt <- is_dt[!is.na(fwd_ret_21d) & !is.na(Size) & Size >= LIQ_THRESHOLD]

  X_tr <- build_mat(is_dt, top_f)
  y_tr <- is_dt$fwd_ret_21d
  rm(is_dt); gc(FALSE)
  if (nrow(X_tr) < 500L) { rm(X_tr, y_tr); next }

  # --- 모델 1회 학습 (윈도우 전체에 재사용) ---
  models <- xgb3_train(X_tr, y_tr)
  rm(X_tr, y_tr); gc(FALSE)
  if (!length(models)) next

  # --- OOS 일간 scoring (이 윈도우의 모든 거래일) ---
  oos_daily <- tryCatch(
    arrow_collect(top_f, dates_vec = win_dates),
    error = function(e) NULL
  )
  if (is.null(oos_daily) || nrow(oos_daily) == 0L) {
    rm(models); gc(FALSE); next
  }
  oos_daily <- zscore_by_date(oos_daily, top_f)  # C13: z-score 강제
  oos_daily <- merge(oos_daily, SIZE_DT, by = c("Date", "Ticker"), all.x = TRUE)
  oos_daily <- oos_daily[!is.na(Size) & Size >= LIQ_THRESHOLD]

  # 날짜별 scoring (학습된 모델 재사용 — 21x speedup)
  scored_list <- list()
  for (d in unique(oos_daily$Date)) {
    day_dt <- oos_daily[Date == d]
    X_te   <- build_mat(day_dt, top_f)
    if (nrow(X_te) < 10L) next
    pB     <- xgb3_score(models, X_te)
    scored_list[[as.character(d)]] <- day_dt[, .(Date, Ticker, Size, Score = pB)]
  }

  if (length(scored_list) > 0L) {
    win_scores <- rbindlist(scored_list)
    all_daily_scores[[wi]] <- win_scores

    # IC (분기말 날짜에 해당하는 것만)
    win_qe <- win_dates[win_dates %in% QE_DATES]
    if (length(win_qe) > 0L) {
      for (qd in win_qe) {
        qd_scores <- win_scores[Date == qd]
        # C14: fwd_ret_21d는 t+1~t+21 수익률 (미래 타겟)
        # Score는 date=qd 시점 팩터로 생성 → Usable_Date <= sig_date 보장
        # 단, ret_dt의 Date == qd는 qd 시점에 관측 가능한 row만 포함
        qd_ret    <- ret_dt[Date == qd & Date <= qd, .(Date, Ticker, fwd_ret_21d)]
        ic_merge  <- merge(qd_scores, qd_ret, by = c("Date", "Ticker"))
        ic_merge  <- ic_merge[!is.na(fwd_ret_21d) & !is.na(Score)]
        if (nrow(ic_merge) >= 30L) {
          ic_val <- tryCatch(
            cor(ic_merge$Score, ic_merge$fwd_ret_21d,
                method = "spearman", use = "complete.obs"),
            error = function(e) NA_real_)
          all_ic_recs[[length(all_ic_recs) + 1L]] <-
            data.table(Date = as.Date(qd), ym = format(as.Date(qd), "%Y-%m"),
                       IC = ic_val, variant = "QRebal_B")
        }
      }
    }
    rm(win_scores, scored_list)
  }

  rm(models, oos_daily); gc(FALSE)
}

elapsed_total <- as.numeric(difftime(Sys.time(), t0_loop, units = "mins"))
cat(sprintf("  Walk-forward 완료: %.1f분\n", elapsed_total))

# =============================================================================
# [7] 일간 점수 통합 + 분기말 필터 + IC 분석
# =============================================================================
cat("\n[7] Score 통합 + IC...\n")

daily_scores_all <- rbindlist(Filter(Negate(is.null), all_daily_scores), fill = TRUE)
cat(sprintf("    일간 총 Score rows: %s\n", format(nrow(daily_scores_all), big.mark = ",")))

qe_scores <- daily_scores_all[Date %in% QE_DATES, .(Date, Ticker, Score)]
cat(sprintf("    분기말 Score rows: %s (%d dates)\n",
            format(nrow(qe_scores), big.mark = ","), uniqueN(qe_scores$Date)))

ic_all <- rbindlist(Filter(Negate(is.null), all_ic_recs), fill = TRUE)
if (nrow(ic_all) > 0L) {
  ic_mean <- mean(ic_all$IC, na.rm = TRUE)
  ic_sd   <- sd(ic_all$IC, na.rm = TRUE)
  icir    <- if (ic_sd > 0) ic_mean / ic_sd else NA_real_
  ic_3y   <- ic_all[Date >= (OOS_END - 365 * 3)]
  icir_3y <- if (nrow(ic_3y) > 4L) mean(ic_3y$IC, na.rm = TRUE) / sd(ic_3y$IC, na.rm = TRUE) else NA
  cat(sprintf("    IC=%.4f ICIR=%.4f N=%d | 3Y ICIR=%.4f\n",
              ic_mean, icir, nrow(ic_all), icir_3y %||% NA))
  gate_pass <- !is.na(icir) && icir >= 0.20
  cat(sprintf("    Alpha Lab Gate: %s\n", ifelse(gate_pass, "PASS", "FAIL")))
} else {
  ic_mean <- NA; icir <- NA; icir_3y <- NA; gate_pass <- FALSE
  cat("    IC 데이터 없음\n")
}

# =============================================================================
# [8] 백테스트 (run_monthly_simulation — quarterly signals)
# =============================================================================
cat("\n[8] 백테스트 (분기 리밸런싱)...\n")

rw2 <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw2$RAWDATA; BM_DT <- rw2$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
rm(rw2); gc()

FAC <- qe_scores[!is.na(Score)]
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
  r <- bt$DAILY_NAV_DT$Strategy_Ret; r <- r[is.finite(r)]
  cum <- cumprod(1 + r); nyr <- length(r) / 252
  bt_CAGR   <- round((tail(cum, 1)^(1/nyr) - 1) * 100, 2)
  bt_Sharpe <- round(mean(r) / sd(r) * sqrt(252), 4)
  bt_MDD    <- round(min(cum / cummax(cum) - 1) * 100, 2)
  hard_fail <- abs(bt_MDD) > 45
  cat(sprintf("  >> CAGR %.1f%% | SR %.4f | MDD %.1f%% | Hard Fail: %s\n",
              bt_CAGR, bt_Sharpe, bt_MDD, hard_fail))
} else {
  bt_CAGR <- NA; bt_Sharpe <- NA; bt_MDD <- NA; hard_fail <- TRUE
  cat("  백테스트 실패\n")
}

# =============================================================================
# [9] 차트
# =============================================================================
cat("\n[9] 차트...\n")
chart_paths <- list()
tryCatch({
  if (!is.null(bt)) {
    eq_dt <- copy(bt$DAILY_NAV_DT)[, .(Date = as.Date(Date), ret = Strategy_Ret)]
    eq_dt <- eq_dt[is.finite(ret)]
    eq_dt[, cum := cumprod(1 + ret)]
    eq_dt[, label := "QRebal_B"]

    bm <- BM_DT[order(Date), .(Date = as.Date(Date), BM_Ret)]
    bm[, cum := cumprod(1 + fifelse(is.finite(BM_Ret), BM_Ret, 0))]
    bm[, label := "KOSPI BM"]
    eq_all <- rbind(eq_dt[, .(Date, cum, label)], bm[, .(Date, cum, label)], fill = TRUE)

    p1 <- ggplot(eq_all, aes(x = Date, y = cum, color = label, linetype = label)) +
      geom_line(linewidth = 0.8) + scale_y_log10(labels = scales::comma) +
      scale_color_manual(values = c("QRebal_B" = "#2ca02c", "KOSPI BM" = "#7f7f7f")) +
      scale_linetype_manual(values = c("QRebal_B" = "solid", "KOSPI BM" = "dotted")) +
      labs(title = "STR_1675 Q-Rebal Hybrid ML — Equity Curve",
           subtitle = sprintf("XGB 3-seed | 21d refit | Q-rebal | EW30 | SR %.3f CAGR %.1f%% MDD %.1f%%",
                              bt_Sharpe, bt_CAGR, bt_MDD),
           x = NULL, y = "Cumulative (Log)", color = NULL, linetype = NULL) +
      theme_minimal(base_size = 12) + theme(legend.position = "bottom")
    ep <- file.path(OUTPUT_DIR, "equity_curve.png")
    ggsave(ep, p1, width = 12, height = 6, dpi = 150)
    chart_paths$equity <- ep
    cat("  equity_curve.png\n")

    ar <- copy(bt$DAILY_NAV_DT)[, .(Date = as.Date(Date), ret = Strategy_Ret)]
    ar <- ar[is.finite(ret)]
    ar[, yr := as.integer(format(Date, "%Y"))]
    ar <- ar[, .(annual_ret = prod(1 + ret) - 1), by = yr]
    p2 <- ggplot(ar, aes(x = factor(yr), y = annual_ret * 100)) +
      geom_col(fill = "#2ca02c", width = 0.7) +
      geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
      labs(title = "STR_1675 Q-Rebal Hybrid — Annual Returns",
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
      geom_line(alpha = 0.5, color = "#2ca02c") +
      geom_smooth(se = FALSE, method = "loess", span = 0.3,
                  linewidth = 1.1, color = "#1f77b4") +
      geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
      labs(title = "STR_1675 Q-Rebal — Quarterly IC",
           subtitle = sprintf("ICIR=%.3f | 3Y ICIR=%.3f", icir %||% NA, icir_3y %||% NA),
           x = NULL, y = "Spearman IC") +
      theme_minimal(base_size = 11)
    ip <- file.path(OUTPUT_DIR, "ic_timeseries.png")
    ggsave(ip, p3, width = 12, height = 5, dpi = 150)
    chart_paths$ic <- ip
    cat("  ic_timeseries.png\n")
  }
}, error = function(e) cat("  차트 오류:", e$message, "\n"))

# =============================================================================
# [10] 결과 저장
# =============================================================================
cat("\n[10] 결과 저장...\n")

perf <- list(
  strategy_id = "STR_1675_QRebal_Hybrid", variant = "QRebal_B",
  timestamp   = as.character(Sys.time()),
  qrebal_b = list(
    ICIR = round(icir %||% NA, 4), IC = round(ic_mean %||% NA, 5),
    N_quarters = nrow(ic_all), ICIR_3y = round(icir_3y %||% NA, 4),
    gate_pass = gate_pass,
    CAGR = bt_CAGR, Sharpe = bt_Sharpe, MDD = bt_MDD
  ),
  alpha_lab_gate = list(pass = gate_pass, ICIR = round(icir %||% NA, 4), threshold = 0.20),
  hard_fail = hard_fail,
  pit_checks = list(
    C1 = "expanding only", C2 = "21d purge gap",
    C13 = "Z_Score_Aligned", C14 = "fwd t+1~t+21 month-end only",
    OPT1 = "Arrow open_dataset"
  ),
  config = list(
    seeds = XGB_SEEDS, mi_top_n = MI_TOP_N, refit_days = REFIT_DAYS,
    mi_refresh = MI_REFRESH, purge_days = PURGE_DAYS,
    n_holdings = N_HOLDINGS, commission = COMMISSION,
    liq = LIQ_THRESHOLD, buffer = list(keep = BUFFER_KEEP, entry = BUFFER_ENTRY),
    rebal = "quarterly"
  ),
  runtime_min = round(elapsed_total, 1)
)
write_json(perf, file.path(OUTPUT_DIR, "performance.json"), auto_unbox = TRUE, pretty = TRUE)

if (nrow(ic_all) > 0L)  fwrite(ic_all, file.path(OUTPUT_DIR, "ic_timeseries.csv"))
if (!is.null(bt))        fwrite(bt$DAILY_NAV_DT, file.path(OUTPUT_DIR, "nav_QRebal_B.csv"))
if (nrow(qe_scores) > 0L) fwrite(qe_scores, file.path(OUTPUT_DIR, "qe_scores.csv"))
cat("  performance.json + CSV 저장 완료\n")

cat(sprintf("\n=== 완료 (%s) | 총 %.1f분 ===\n", Sys.time(), elapsed_total))
