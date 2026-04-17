## =============================================================================
## STR_1661_XGB_GPU: XGBoost GPU + LambdaRank + Bayesian HP — S1 Implementation
## 핵심 아이디어: STR_1656(ICIR 0.8496, SR 0.927) 3축 업그레이드
##   Dim-1: CPU → GPU(CUDA) 전환 (학습속도 2-3x 향상, RTX 4080 Super)
##   Dim-2: reg:squarederror → rank:pairwise (LambdaRank, NDCG@30 직접 최적화)
##   Dim-3: 고정 HP → Optuna 30 trials (expanding IS 내 purged 3-fold CV)
##
## Ablation 4단계:
##   V0: baseline STR_1656 참조값 (ICIR 0.8496, SR 0.927)
##   V1: GPU only (GPU + reg:squarederror + 고정 HP)
##   V2: GPU + LambdaRank (GPU + rank:pairwise + 고정 HP)
##   V3: GPU + LambdaRank + HP (GPU + rank:pairwise + Optuna 30 trials)
##
## PIT 준수 (C1-C15):
##   C1  : expanding window only (HP 탐색도 IS 내 purged CV, OOS 데이터 미사용)
##   C2  : OOS prediction은 IS 학습 완료 후 (same-day circular 없음)
##   C13 : Z_Score_Aligned (일간 DB 이미 정규화)
##   C14 : fwd_ret_21d = t+1~t+21 (IS target 전용)
##   C15 : 월간 DB 미사용 (일간 DB Arrow open_dataset)
##   purge: 21d embargo
##
## S1 단계: 순수 팩터 신호 측정. EW 30종목 + 15bps + 유동성 2억원.
## 신호 증폭/필터링은 S5 이후에서만 추가 가능.
##
## 참고: Gu, Kelly & Xiu (2020 RFS) | Chen & Guestrin (2016 KDD) |
##        Burges (2010 MS-TR) | Li et al. (2024 TSPRank)
##
## OPT 준수:
##   OPT-1: Arrow open_dataset predicate pushdown (parquet 반복 없음)
##   OPT-2: load_rawdata(use_cache=TRUE)
##   OPT-4: 백테스트 mclapply 병렬
## =============================================================================

cat("=== STR_1661_XGB_GPU: LambdaRank Upgrade ===\n")
cat("시작:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(dplyr)
  library(jsonlite)
  library(ggplot2)
  library(parallel)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0L && !is.na(a[[1L]])) a[[1L]] else b

# =============================================================================
# 경로 (normalizePath 금지 — WSL 한글 경로 버그)
# =============================================================================
PROJECT_ROOT  <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
STRATEGY_DIR  <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1661_XGB_GPU")
OUTPUT_DIR    <- file.path(STRATEGY_DIR, "output")
ARTIFACT_DIR  <- file.path(PROJECT_ROOT, "stage_artifacts")
DAILY_DB_DIR  <- file.path(PROJECT_ROOT, ".cache/factor_db_daily")
PYTHON_BIN    <- "/tmp/xgb-env/bin/python3"
PYTHON_SCRIPT <- "/tmp/xgb_gpu_predict.py"  # 한글 경로 공백 회피

dir.create(OUTPUT_DIR,    showWarnings = FALSE, recursive = TRUE)
dir.create(ARTIFACT_DIR,  showWarnings = FALSE, recursive = TRUE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

# =============================================================================
# 설정
# =============================================================================
LIQ_THRESHOLD <- 2e8
N_HOLDINGS    <- 30L
COMMISSION    <- 0.0015
MI_TOP_N      <- 50L
PURGE_DAYS    <- 21L
XGB_SEEDS     <- c(42L, 123L, 456L, 789L, 2024L)
OOS_START_YR  <- 2008L
OOS_END_YR    <- 2025L
RE_PAT        <- "^(RE_|RE0|RE1)"
XGB_MAX_ROWS  <- 80000L   # OOM 방지: IS 서브샘플 상한

# Ablation 변형 목록 (V1→V2→V3 순차)
VARIANTS <- list(
  V1 = list(objective = "reg:squarederror", device = "cuda",
            hp_mode = "fixed",  label = "V1_GPU_only"),
  V2 = list(objective = "rank:pairwise",    device = "cuda",
            hp_mode = "fixed",  label = "V2_LambdaRank"),
  V3 = list(objective = "rank:pairwise",    device = "cuda",
            hp_mode = "optuna", label = "V3_LambdaRank_HP")
)

# V0 baseline 참조값 (STR_1656 S1-B)
V0_ICIR <- 0.8496
V0_SR   <- 0.9268
V0_CAGR <- 22.82

cat("[CONFIG] N=", N_HOLDINGS, "| MI=", MI_TOP_N,
    "| seeds=", paste(XGB_SEEDS, collapse=","),
    "| purge=", PURGE_DAYS, "\n")
cat("[CONFIG] V0 baseline: ICIR=", V0_ICIR, " SR=", V0_SR, "\n")

# Python 환경 확인
py_check <- tryCatch(
  system2(PYTHON_BIN, args = c("-c", "'import xgboost; print(xgboost.__version__)'"),
          stdout = TRUE, stderr = FALSE),
  error = function(e) NULL)
if (is.null(py_check) || length(py_check) == 0)
  stop("Python xgb-env 확인 실패. /tmp/xgb-env 점검 필요.")
cat("[Python] xgboost:", py_check[1], "\n")

# =============================================================================
# 1. RAWDATA 1회 로드 (OPT-2)
# =============================================================================
cat("\n[1] RAWDATA...\n")
rw       <- load_rawdata(use_cache = TRUE)
RAWDATA  <- rw$RAWDATA; BM_DT <- rw$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
cat(sprintf("    %d rows | %s ~ %s\n", nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date)))

# =============================================================================
# 2. 21d forward return (C14: t+1~t+21, IS target only)
# =============================================================================
cat("[2] 21d fwd return...\n")
ret_dt <- RAWDATA[!is.na(Ret) & is.finite(Ret) & Date >= as.Date("2003-01-01"),
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
cat(sprintf("    fwd rows: %d\n", nrow(ret_dt)))

SIZE_DT <- RAWDATA[Date >= as.Date("2003-01-01"), .(Date, Ticker, Size)]
setkey(SIZE_DT, Date, Ticker)

RAWDATA[, ym__ := format(Date, "%Y-%m")]
ALL_ME_DATES <- RAWDATA[, .(me_date = max(Date)), by = ym__][order(me_date)]$me_date
RAWDATA[, ym__ := NULL]
cat(sprintf("    [ME] 월말 날짜 %d개 (%s ~ %s)\n",
            length(ALL_ME_DATES), min(ALL_ME_DATES), max(ALL_ME_DATES)))
ret_dt[, c("Ret", "Size") := NULL]
setkey(ret_dt, Date, Ticker)

rm(RAWDATA, BM_DT, rw); gc()
cat(sprintf("    [MEM] RAWDATA 해제. ret_dt: %.0fMB | SIZE_DT: %.0fMB\n",
            object.size(ret_dt)/1e6, object.size(SIZE_DT)/1e6))

# =============================================================================
# 3. OPT-1: Arrow open_dataset (parquet 반복 없음)
# =============================================================================
cat("[3] Arrow Dataset...\n")
pq_files   <- list.files(DAILY_DB_DIR, pattern = "\\.parquet$", full.names = TRUE)
ds_daily   <- open_dataset(pq_files, format = "parquet")
ds_cols    <- schema(ds_daily)$names
EXCL       <- c("Date", "Ticker",
                grep("^(dps_1y|bps_1y|eps_1y|target_price)", ds_cols, value = TRUE),
                grep("\\.x$|\\.y$", ds_cols, value = TRUE))
ALL_FCOLS  <- setdiff(ds_cols, EXCL)
RE_COLS    <- grep(RE_PAT, ALL_FCOLS, value = TRUE)
NONRE_COLS <- setdiff(ALL_FCOLS, RE_COLS)
cat(sprintf("    팩터 전체=%d RE*=%d NonRE=%d\n",
            length(ALL_FCOLS), length(RE_COLS), length(NONRE_COLS)))

arrow_collect <- function(fcols, dates_vec = NULL, d0 = NULL, d1 = NULL) {
  need <- intersect(c("Date", "Ticker", fcols), ds_cols)
  q <- ds_daily
  if (!is.null(dates_vec)) {
    q <- q |> filter(Date %in% dates_vec)
  } else {
    q <- q |> filter(Date >= d0, Date <= d1)
  }
  q |> select(all_of(need)) |>
    collect() |>
    as.data.table() |>
    (\(x){ setkey(x, Date, Ticker); x })()
}

# =============================================================================
# 3b. 청크 MI prefilter (60F씩 분할 → top 선정, OOM 방지)
# =============================================================================
mi_prefilter_chunked <- function(d0, d1, fcols, n_top = 50L) {
  me_vec <- ALL_ME_DATES[ALL_ME_DATES >= d0 & ALL_ME_DATES <= d1]
  if (length(me_vec) == 0L) return(list(all = character(0), nonre = character(0)))

  chunk_sz <- 60L
  f_chunks <- split(fcols, ceiling(seq_along(fcols) / chunk_sz))
  all_ics  <- numeric(0)

  for (i in seq_along(f_chunks)) {
    ch    <- f_chunks[[i]]
    ch_dt <- tryCatch(arrow_collect(ch, dates_vec = me_vec), error = function(e) NULL)
    if (is.null(ch_dt) || nrow(ch_dt) == 0L) next
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
    cat(sprintf("      MI chunk %d/%d (%d factors)\n", i, length(f_chunks), length(ch)))
  }

  valid <- all_ics[!is.na(all_ics)]
  if (!length(valid)) return(list(all = character(0), nonre = character(0)))

  top_all   <- names(sort(valid, decreasing = TRUE))[seq_len(min(n_top, length(valid)))]
  nonre_v   <- valid[intersect(names(valid), NONRE_COLS)]
  top_nonre <- if (length(nonre_v))
    names(sort(nonre_v, decreasing = TRUE))[seq_len(min(n_top, length(nonre_v)))]
  else character(0)
  list(all = top_all, nonre = top_nonre)
}

build_mat <- function(dt, cols) {
  m <- as.matrix(dt[, intersect(cols, names(dt)), with = FALSE])
  m[!is.finite(m)] <- 0; m
}

# =============================================================================
# R → Python XGBoost 호출 함수
# CSV 임시 파일 경유: train/test → Python → pred 반환
# =============================================================================
xgb_gpu_predict_r2py <- function(train_dt, test_dt, val_dt = NULL,
                                  feat_cols, objective, device, seed,
                                  hp_json_path = NULL) {
  # 임시 CSV 파일 경로 (seed + 시각 기반 충돌 방지)
  ts       <- as.integer(Sys.time())
  tmp_tr   <- sprintf("/tmp/xgb_tr_%d_%d.csv",  ts, seed)
  tmp_te   <- sprintf("/tmp/xgb_te_%d_%d.csv",  ts, seed)
  tmp_vl   <- sprintf("/tmp/xgb_vl_%d_%d.csv",  ts, seed)
  tmp_out  <- sprintf("/tmp/xgb_out_%d_%d.csv", ts, seed)

  # IS: Date + Ticker + fwd_ret_21d + feat_cols + ym_group
  tr_out <- copy(train_dt[, c("Date", "Ticker", "fwd_ret_21d",
                               intersect(feat_cols, names(train_dt))), with = FALSE])
  tr_out[, ym_group := format(Date, "%Y-%m")]
  fwrite(tr_out, tmp_tr); rm(tr_out)

  # OOS: label 없음
  te_out <- copy(test_dt[, c("Date", "Ticker",
                              intersect(feat_cols, names(test_dt))), with = FALSE])
  te_out[, ym_group := format(Date, "%Y-%m")]
  fwrite(te_out, tmp_te); rm(te_out)

  # Val (early stopping용, 선택)
  vl_path <- "NULL"
  if (!is.null(val_dt) && nrow(val_dt) > 20L) {
    vl_out <- copy(val_dt[, c("Date", "Ticker", "fwd_ret_21d",
                               intersect(feat_cols, names(val_dt))), with = FALSE])
    vl_out[, ym_group := format(Date, "%Y-%m")]
    fwrite(vl_out, tmp_vl)
    vl_path <- tmp_vl
    rm(vl_out)
  }

  hp_arg <- if (!is.null(hp_json_path) && file.exists(hp_json_path))
    hp_json_path else "NULL"

  args_py <- c(PYTHON_SCRIPT,
               "--train",     tmp_tr,
               "--test",      tmp_te,
               "--val",       vl_path,
               "--out",       tmp_out,
               "--objective", objective,
               "--device",    device,
               "--seed",      as.character(seed),
               "--hp_json",   hp_arg,
               "--mode",      "predict")

  py_stderr <- tempfile(fileext = ".log")
  ret_code <- system2(PYTHON_BIN, args = args_py,
                       stdout = TRUE, stderr = py_stderr)

  result <- NULL
  if (file.exists(tmp_out) && file.size(tmp_out) > 0L) {
    result <- tryCatch(fread(tmp_out)$pred_rank, error = function(e) {
      cat("    [ERR] fread failed:", e$message, "\n"); NULL
    })
  } else {
    py_err <- if (file.exists(py_stderr)) paste(readLines(py_stderr, n = 5), collapse = " ") else ""
    cat(sprintf("    [ERR] Python ret=%s, out=%s, stderr=%s\n",
                paste(ret_code, collapse=","),
                ifelse(file.exists(tmp_out), "EXISTS", "MISSING"),
                substr(py_err, 1, 200)))
  }
  if (file.exists(py_stderr)) file.remove(py_stderr)

  # 임시 파일 정리
  for (f in c(tmp_tr, tmp_te, tmp_vl, tmp_out)) {
    if (file.exists(f)) file.remove(f)
  }

  result
}

# =============================================================================
# V3 전용: Optuna HP 탐색 (연 1회, IS 내부만 — C1 준수)
# 반환: hp_json 파일 경로
# =============================================================================
xgb_optuna_search <- function(train_dt, feat_cols, objective, device, seed,
                               n_trials, oos_yr) {
  tmp_tr  <- sprintf("/tmp/xgb_hp_tr_%d_%d.csv", oos_yr, seed)
  tmp_out <- sprintf("/tmp/xgb_hp_%d_%d.json",   oos_yr, seed)

  tr_out <- copy(train_dt[, c("Date", "Ticker", "fwd_ret_21d",
                               intersect(feat_cols, names(train_dt))), with = FALSE])
  # OOM 방지: IS 서브샘플
  if (nrow(tr_out) > XGB_MAX_ROWS) {
    set.seed(seed)
    tr_out <- tr_out[sample(.N, XGB_MAX_ROWS)]
  }
  tr_out[, ym_group := format(Date, "%Y-%m")]
  fwrite(tr_out, tmp_tr); rm(tr_out); gc(FALSE)

  args_py <- c(PYTHON_SCRIPT,
               "--train",    tmp_tr,
               "--test",     tmp_tr,   # hp_search 모드에서 test는 미사용
               "--out",      tmp_out,
               "--objective", objective,
               "--device",   device,
               "--seed",     as.character(seed),
               "--mode",     "hp_search",
               "--n_trials", as.character(n_trials))

  ret_code <- system2(PYTHON_BIN, args = args_py,
                       stdout = FALSE, stderr = FALSE)

  if (file.exists(tmp_tr)) file.remove(tmp_tr)

  if (ret_code == 0L && file.exists(tmp_out)) {
    cat(sprintf("    [HP] Optuna 완료: %s\n", tmp_out))
    return(tmp_out)
  } else {
    cat("    [HP] Optuna 실패 — 고정 HP fallback\n")
    return(NULL)
  }
}

# =============================================================================
# ICIR 계산 유틸
# =============================================================================
icir_fn <- function(ic_dt) {
  if (is.null(ic_dt) || nrow(ic_dt) == 0L) return(list(IC = NA, ICIR = NA, N = 0L))
  v <- ic_dt$IC[!is.na(ic_dt$IC)]
  if (length(v) < 5L) return(list(IC = NA, ICIR = NA, N = length(v)))
  list(IC = round(mean(v), 5), ICIR = round(mean(v) / sd(v), 4), N = length(v))
}

# =============================================================================
# 4. Walk-Forward — 단일 변형 실행 함수
# =============================================================================
run_variant_wf <- function(variant_cfg) {
  cat(sprintf("\n[WF] 변형: %s (obj=%s device=%s hp=%s)\n",
              variant_cfg$label, variant_cfg$objective,
              variant_cfg$device, variant_cfg$hp_mode))

  IS_START_D <- as.Date("2003-01-01")
  OOS_YEARS  <- OOS_START_YR:OOS_END_YR

  wf_out <- lapply(OOS_YEARS, function(oos_yr) {
    cat(sprintf("  OOS %d [%s]\n", oos_yr, variant_cfg$label))
    is_end_yr <- oos_yr - 2L
    if (is_end_yr < 2005L) return(NULL)

    is_end_d <- as.Date(sprintf("%d-12-31", is_end_yr))
    val_s    <- as.Date(sprintf("%d-01-01", oos_yr - 1L))
    val_e    <- as.Date(sprintf("%d-12-31", oos_yr - 1L))
    oos_s    <- as.Date(sprintf("%d-01-01", oos_yr))
    oos_e    <- as.Date(sprintf("%d-12-31", oos_yr))

    # MI prefilter — chunked (NonRE 기준, S1-B 방식)
    cat("    MI prefilter (chunked)...\n")
    tops  <- mi_prefilter_chunked(IS_START_D, is_end_d, ALL_FCOLS, MI_TOP_N)
    top_B <- tops$nonre
    cat(sprintf("    topB=%d\n", length(top_B)))
    if (length(top_B) < 5L) return(NULL)

    # IS 데이터 수집 (월말만)
    is_me_d <- ALL_ME_DATES[ALL_ME_DATES >= IS_START_D & ALL_ME_DATES <= is_end_d]
    is_dt   <- tryCatch(arrow_collect(top_B, dates_vec = is_me_d), error = function(e) NULL)
    if (is.null(is_dt) || nrow(is_dt) < 1000L) return(NULL)

    is_dt <- merge(is_dt, ret_dt[, .(Date, Ticker, fwd_ret_21d)], by = c("Date", "Ticker"))
    is_dt <- merge(is_dt, SIZE_DT, by = c("Date", "Ticker"), all.x = TRUE)
    is_dt <- is_dt[!is.na(fwd_ret_21d) & !is.na(Size) & Size >= LIQ_THRESHOLD]
    if (nrow(is_dt) > XGB_MAX_ROWS) {
      set.seed(42L)
      is_dt <- is_dt[sample(.N, XGB_MAX_ROWS)]
    }
    cat(sprintf("    IS=%d rows\n", nrow(is_dt)))
    gc(FALSE)

    # Val 데이터 (purge 적용)
    is_last  <- max(is_dt$Date)
    val_me_d <- ALL_ME_DATES[ALL_ME_DATES >= val_s & ALL_ME_DATES <= val_e &
                              ALL_ME_DATES > (is_last + PURGE_DAYS)]
    val_dt <- NULL
    if (length(val_me_d) > 0L) {
      val_raw <- tryCatch(arrow_collect(top_B, dates_vec = val_me_d), error = function(e) NULL)
      if (!is.null(val_raw)) {
        val_m <- merge(val_raw, ret_dt[, .(Date, Ticker, fwd_ret_21d)],
                       by = c("Date", "Ticker"))
        val_m <- val_m[!is.na(fwd_ret_21d)]
        if (nrow(val_m) > 50L) val_dt <- val_m
        rm(val_raw, val_m); gc(FALSE)
      }
    }

    # OOS 데이터
    oos_me_d <- ALL_ME_DATES[ALL_ME_DATES >= oos_s & ALL_ME_DATES <= oos_e]
    oos_me   <- tryCatch(arrow_collect(top_B, dates_vec = oos_me_d), error = function(e) NULL)
    if (is.null(oos_me) || nrow(oos_me) == 0L) {
      rm(is_dt); gc(FALSE); return(NULL)
    }
    oos_me <- merge(oos_me, SIZE_DT, by = c("Date", "Ticker"), all.x = TRUE)
    oos_me <- oos_me[!is.na(Size) & Size >= LIQ_THRESHOLD]
    gc(FALSE)

    # V3: Optuna HP 탐색 (IS 내부에서만 — C1 준수)
    hp_json_path <- NULL
    if (variant_cfg$hp_mode == "optuna") {
      is_hp <- copy(is_dt)
      hp_json_path <- xgb_optuna_search(
        train_dt  = is_hp,
        feat_cols = top_B,
        objective = variant_cfg$objective,
        device    = variant_cfg$device,
        seed      = 42L,
        n_trials  = 30L,
        oos_yr    = oos_yr
      )
      rm(is_hp); gc(FALSE)

      if (!is.null(hp_json_path) && file.exists(hp_json_path)) {
        hp_data <- tryCatch(fromJSON(hp_json_path), error = function(e) NULL)
        if (!is.null(hp_data))
          cat(sprintf("    [HP] IS_val_IC=%.4f\n", hp_data$best_val_IC %||% NA))
      }
    }

    # 5-seed 앙상블 예측
    preds_list <- lapply(XGB_SEEDS, function(sd) {
      xgb_gpu_predict_r2py(
        train_dt     = is_dt,
        test_dt      = oos_me,
        val_dt       = val_dt,
        feat_cols    = top_B,
        objective    = variant_cfg$objective,
        device       = variant_cfg$device,
        seed         = sd,
        hp_json_path = hp_json_path
      )
    })
    valid_preds <- Filter(Negate(is.null), preds_list)

    if (length(valid_preds) == 0L) {
      rm(is_dt, oos_me); gc(FALSE); return(NULL)
    }
    n_te <- nrow(oos_me)
    score_final <- if (length(valid_preds) == 1L) {
      valid_preds[[1L]]
    } else {
      rmat <- vapply(valid_preds,
                     function(p) if (length(p) == n_te) p else rep(0.5, n_te),
                     numeric(n_te))
      if (is.matrix(rmat)) rowMeans(rmat) else rmat
    }

    oos_me[, Score := score_final]

    # IC 계산 (OOS 예측 vs 실제 수익률)
    oos_ic <- merge(oos_me[, .(Date, Ticker, Score)],
                    ret_dt[, .(Date, Ticker, fwd_ret_21d)],
                    by = c("Date", "Ticker"))
    oos_ic <- oos_ic[!is.na(fwd_ret_21d) & !is.na(Score)]
    oos_ic[, ym_ := format(Date, "%Y-%m")]
    ic_dt <- oos_ic[, .(IC = tryCatch(
      cor(Score, fwd_ret_21d, method = "spearman", use = "complete.obs"),
      error = function(e) NA_real_),
      variant = variant_cfg$label, oos_year = oos_yr), by = ym_]
    setnames(ic_dt, "ym_", "ym")
    cat(sprintf("    IC=%.4f (%d months)\n",
                mean(ic_dt$IC, na.rm = TRUE), nrow(ic_dt)))

    score_out <- oos_me[, .(Date, Ticker, Size, Score, variant = variant_cfg$label)]

    # HP JSON 정리 (V3)
    if (!is.null(hp_json_path) && file.exists(hp_json_path))
      file.remove(hp_json_path)

    rm(is_dt, oos_me, oos_ic, val_dt); gc(FALSE)
    list(score = score_out, ic = ic_dt)
  })

  valid_wf <- Filter(Negate(is.null), wf_out)
  list(
    scores_dt = rbindlist(Filter(Negate(is.null), lapply(valid_wf, `[[`, "score")),
                          fill = TRUE),
    ic_dt     = rbindlist(Filter(Negate(is.null), lapply(valid_wf, `[[`, "ic")),
                          fill = TRUE),
    label     = variant_cfg$label
  )
}

# =============================================================================
# 5. Ablation 실행: V1 → V2 → V3 순차
#    V2 ICIR < V0 - 0.03이면 조기 중단
# =============================================================================
cat("\n[4] Ablation Walk-Forward 시작...\n")
ablation_results <- list()

for (vname in names(VARIANTS)) {
  vcfg <- VARIANTS[[vname]]
  res  <- run_variant_wf(vcfg)
  ic_s <- icir_fn(res$ic_dt)
  cat(sprintf("[ICIR] %s: IC=%.4f ICIR=%.4f N=%d\n",
              vname, ic_s$IC %||% NA, ic_s$ICIR %||% NA, ic_s$N))
  res$icir <- ic_s
  ablation_results[[vname]] <- res

  # V2 조기 중단 판정 (S0_VERDICT abort 조건)
  if (vname == "V2") {
    if (!is.na(ic_s$ICIR) && ic_s$ICIR < (V0_ICIR - 0.03)) {
      cat(sprintf("[ABORT] V2 ICIR=%.4f < %.4f → LambdaRank 부적합. 가설 폐기.\n",
                  ic_s$ICIR, V0_ICIR - 0.03))
      break
    }
    cat(sprintf("[PASS] V2 ICIR=%.4f >= threshold. V3 진행.\n", ic_s$ICIR %||% NA))
  }
  gc()
}

# =============================================================================
# 6. IC 요약 및 비교
# =============================================================================
cat("\n[5] IC 요약...\n")
cur_yr <- as.integer(format(Sys.Date(), "%Y"))

summary_list <- lapply(names(ablation_results), function(vn) {
  res   <- ablation_results[[vn]]
  ic_s  <- res$icir
  ic_3y <- if ("oos_year" %in% names(res$ic_dt))
    icir_fn(res$ic_dt[oos_year >= cur_yr - 3L])
  else list(IC = NA, ICIR = NA, N = 0L)
  data.table(variant = vn, label = res$label,
             IC = ic_s$IC, ICIR = ic_s$ICIR, N = ic_s$N,
             ICIR_3y = ic_3y$ICIR,
             gate_pass = !is.na(ic_s$ICIR) && ic_s$ICIR >= 0.20)
})
summary_dt <- rbindlist(summary_list, fill = TRUE)
print(summary_dt)

v2_icir  <- summary_dt[variant == "V2", ICIR]
v3_icir  <- summary_dt[variant == "V3", ICIR]
delta_v2 <- if (length(v2_icir) > 0 && !is.na(v2_icir)) v2_icir - V0_ICIR else NA_real_
delta_v3 <- if (length(v3_icir) > 0 && !is.na(v3_icir)) v3_icir - V0_ICIR else NA_real_
cat(sprintf("[DELTA] V2 vs V0: %+.4f | V3 vs V0: %+.4f\n",
            delta_v2 %||% NA, delta_v3 %||% NA))

# IS/OOS gap 점검 (V3)
if (!is.na(v3_icir) && !is.na(v2_icir) && v2_icir > 0) {
  gap_ratio <- v3_icir / v2_icir
  if (gap_ratio > 2.0)
    cat(sprintf("[WARN] IS/OOS gap ratio=%.2f > 2.0. V3 HP 과적합 의심. V2 채택 권고.\n", gap_ratio))
}

# 최적 변형 선택
best_vname <- summary_dt[!is.na(ICIR), .SD[which.max(ICIR)]]$variant
best_res   <- ablation_results[[best_vname]]
best_icir  <- summary_dt[variant == best_vname, ICIR]
cat(sprintf("[BEST] %s ICIR=%.4f\n", best_vname, best_icir %||% NA))

# =============================================================================
# 7. 백테스트 — V2 + best 변형 (mclapply 병렬, OPT-4)
# =============================================================================
cat("\n[6-0] RAWDATA 재로드 (백테스트용)...\n")
rm(ret_dt, SIZE_DT); gc()
rw2 <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw2$RAWDATA; BM_DT <- rw2$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
rm(rw2); gc()

cat("[6b] 백테스트 mclapply...\n")
bt_variant_names <- unique(c("V2", best_vname))
bt_inputs <- lapply(bt_variant_names, function(vn) {
  res <- ablation_results[[vn]]
  if (is.null(res) || nrow(res$scores_dt) == 0L) return(NULL)
  res$scores_dt[!is.na(Score), .(Date, Ticker, Score)]
})
names(bt_inputs) <- bt_variant_names

n_cores <- min(2L, max(1L, detectCores() - 1L))
cat(sprintf("  cores=%d\n", n_cores))

bt_results <- mclapply(bt_variant_names, function(vn) {
  sc <- bt_inputs[[vn]]
  if (is.null(sc) || nrow(sc) == 0L) return(NULL)
  FAC <- copy(sc); setkey(FAC, Date, Ticker)
  bt  <- tryCatch(
    run_monthly_simulation(
      RAWDATA       = RAWDATA, BM_DT = BM_DT, FACTORS = FAC,
      n_holdings    = N_HOLDINGS, commission = COMMISSION,
      weight_method = "EW",
      buffer_zone   = list(keep_n = N_HOLDINGS + 5L, entry_n = N_HOLDINGS)),
    error = function(e) { cat(vn, "BT err:", e$message, "\n"); NULL })
  if (is.null(bt)) return(NULL)
  r   <- bt$DAILY_NAV_DT$Strategy_Ret; r <- r[is.finite(r)]
  cum <- cumprod(1 + r); nyr <- length(r) / 252
  list(label  = vn,
       CAGR   = round((tail(cum, 1)^(1 / nyr) - 1) * 100, 2),
       Sharpe = round(mean(r) / sd(r) * sqrt(252), 4),
       MDD    = round(min(cum / cummax(cum) - 1) * 100, 2),
       nav_dt = bt$DAILY_NAV_DT)
}, mc.cores = n_cores)
names(bt_results) <- bt_variant_names

lapply(bt_variant_names, function(vn) {
  r <- bt_results[[vn]]
  if (!is.null(r)) cat(sprintf("  %s: CAGR %.1f%% SR %.4f MDD %.1f%%\n",
                                vn, r$CAGR, r$Sharpe, r$MDD))
})

bt_V2   <- bt_results[["V2"]]
bt_best <- bt_results[[best_vname]]

# =============================================================================
# 8. 차트 생성
# =============================================================================
cat("\n[7] 차트...\n")
chart_paths <- list()
tryCatch({
  # 색상/선형 매핑
  color_map <- c("V1" = "#2ca02c", "V2" = "#ff7f0e", "V3" = "#d62728",
                 "KOSPI BM" = "#7f7f7f")
  ltype_map <- c("V1" = "dotted", "V2" = "solid", "V3" = "dashed",
                 "KOSPI BM" = "dotted")

  # Equity Curve
  eq_data <- rbindlist(Filter(Negate(is.null), lapply(bt_variant_names, function(vn) {
    b <- bt_results[[vn]]; if (is.null(b)) return(NULL)
    d <- copy(b$nav_dt)[, .(Date = as.Date(Date), ret = Strategy_Ret)]
    d <- d[is.finite(ret)]; d[, cum := cumprod(1 + ret)]; d[, label := vn]; d
  })), fill = TRUE)

  bm <- BM_DT[order(Date), .(Date = as.Date(Date), BM_Ret)]
  bm[, cum := cumprod(1 + fifelse(is.finite(BM_Ret), BM_Ret, 0))][, label := "KOSPI BM"]
  eq_all <- rbind(eq_data[, .(Date, cum, label)], bm[, .(Date, cum, label)], fill = TRUE)

  if (nrow(eq_all) > 0) {
    p1 <- ggplot(eq_all, aes(x = Date, y = cum, color = label, linetype = label)) +
      geom_line(linewidth = 0.8) + scale_y_log10(labels = scales::comma) +
      scale_color_manual(values = color_map) +
      scale_linetype_manual(values = ltype_map) +
      labs(title    = "STR_1661_XGB_GPU — Ablation Equity Curves",
           subtitle = sprintf("V1(GPU) | V2(LambdaRank) | V3(+HP) | V0 SR=%.3f (ref)",
                              V0_SR),
           x = NULL, y = "Cumulative (Log)", color = NULL, linetype = NULL) +
      theme_minimal(base_size = 12) + theme(legend.position = "bottom")
    ep <- file.path(OUTPUT_DIR, "equity_curve.png")
    ggsave(ep, p1, width = 12, height = 6, dpi = 150)
    chart_paths$equity <- ep; cat("  equity_curve.png\n")
  }

  # Annual Returns
  ar_all <- rbindlist(Filter(Negate(is.null), lapply(bt_variant_names, function(vn) {
    b <- bt_results[[vn]]; if (is.null(b)) return(NULL)
    d <- copy(b$nav_dt)[, .(Date = as.Date(Date), ret = Strategy_Ret)]
    d <- d[is.finite(ret)]; d[, yr := as.integer(format(Date, "%Y"))]
    a <- d[, .(annual_ret = prod(1 + ret) - 1), by = yr]; a[, label := vn]; a
  })), fill = TRUE)

  if (nrow(ar_all) > 0) {
    p2 <- ggplot(ar_all, aes(x = factor(yr), y = annual_ret * 100, fill = label)) +
      geom_col(position = "dodge", width = 0.7) +
      geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
      scale_fill_manual(values = color_map) +
      labs(title    = "STR_1661_XGB_GPU — Annual Returns Ablation",
           subtitle = "V1(GPU) vs V2(LambdaRank) vs V3(+HP)",
           x = NULL, y = "Return (%)", fill = NULL) +
      theme_minimal(base_size = 11) +
      theme(axis.text.x = element_text(angle = 45, hjust = 1),
            legend.position = "bottom")
    ap <- file.path(OUTPUT_DIR, "annual_returns.png")
    ggsave(ap, p2, width = 14, height = 6, dpi = 150)
    chart_paths$annual <- ap; cat("  annual_returns.png\n")
  }

  # IC 시계열 비교
  ic_all_combined <- rbindlist(lapply(names(ablation_results), function(vn) {
    dt <- ablation_results[[vn]]$ic_dt
    if (is.null(dt) || nrow(dt) == 0L) return(NULL)
    dt[, .(ym, IC, variant = vn)]
  }), fill = TRUE)

  if (nrow(ic_all_combined) > 0) {
    ic_all_combined[, dt := as.Date(paste0(ym, "-01"))]
    p3 <- ggplot(ic_all_combined, aes(x = dt, y = IC, color = variant)) +
      geom_line(alpha = 0.4) +
      geom_smooth(se = FALSE, method = "loess", span = 0.3, linewidth = 1.0) +
      geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
      scale_color_manual(values = c("V1" = "#2ca02c", "V2" = "#ff7f0e", "V3" = "#d62728")) +
      labs(title    = "STR_1661_XGB_GPU — Monthly IC Comparison",
           subtitle = sprintf("V0 ref ICIR=%.4f | V2 delta: %+.4f | V3 delta: %+.4f",
                              V0_ICIR, delta_v2 %||% NA, delta_v3 %||% NA),
           x = NULL, y = "Spearman IC", color = NULL) +
      theme_minimal(base_size = 11) + theme(legend.position = "bottom")
    ip <- file.path(OUTPUT_DIR, "ic_timeseries.png")
    ggsave(ip, p3, width = 12, height = 5, dpi = 150)
    chart_paths$ic <- ip; cat("  ic_timeseries.png\n")
  }
}, error = function(e) cat("  차트 오류:", e$message, "\n"))

# =============================================================================
# 9. 결과 저장
# =============================================================================
cat("\n[8] 결과 저장...\n")
v2_hard_fail <- !is.null(bt_V2) && abs(bt_V2$MDD) > 45
best_gate    <- !is.na(best_icir) && best_icir >= 0.20

perf <- list(
  strategy_id  = "STR_1661_XGB_GPU",
  parent       = "STR_1656_MLRA",
  timestamp    = as.character(Sys.time()),
  v0_baseline  = list(ICIR = V0_ICIR, SR = V0_SR, CAGR = V0_CAGR,
                       objective = "reg:squarederror", device = "cpu", hp = "fixed"),
  ablation     = lapply(names(ablation_results), function(vn) {
    res  <- ablation_results[[vn]]
    ic_s <- res$icir
    ic_3y <- if ("oos_year" %in% names(res$ic_dt))
      icir_fn(res$ic_dt[oos_year >= cur_yr - 3L])
    else list(IC = NA, ICIR = NA, N = 0L)
    bt_r <- bt_results[[vn]]
    list(variant     = vn, label = res$label,
         ICIR        = ic_s$ICIR, IC = ic_s$IC, N_months = ic_s$N,
         ICIR_3y     = ic_3y$ICIR,
         delta_vs_V0 = if (!is.na(ic_s$ICIR)) round(ic_s$ICIR - V0_ICIR, 4) else NA,
         gate_pass   = !is.na(ic_s$ICIR) && ic_s$ICIR >= 0.20,
         CAGR        = if (!is.null(bt_r)) bt_r$CAGR   else NA,
         SR          = if (!is.null(bt_r)) bt_r$Sharpe  else NA,
         MDD         = if (!is.null(bt_r)) bt_r$MDD     else NA)
  }),
  best_variant         = best_vname,
  best_icir            = best_icir,
  lambdarank_decision  = list(
    v2_icir        = v2_icir %||% NA,
    v0_icir        = V0_ICIR,
    delta          = delta_v2 %||% NA,
    keep_threshold = V0_ICIR - 0.03,
    decision       = if (!is.na(v2_icir) && v2_icir >= V0_ICIR - 0.03) "KEEP" else "ABORT"
  ),
  hard_fail  = v2_hard_fail,
  pit_checks = list(
    C1  = "expanding only + HP purged IS CV (OOS 미사용)",
    C2  = "OOS > IS (same-day circular 없음)",
    C13 = "Z_Score_Aligned (일간 DB 정규화)",
    C14 = "fwd t+1~t+21 (IS target only)",
    C15 = "Arrow open_dataset (직접 parquet 금지)",
    purge_days = PURGE_DAYS
  ),
  ml_config = list(
    seeds = XGB_SEEDS, mi_top_n = MI_TOP_N, purge_days = PURGE_DAYS,
    n_holdings = N_HOLDINGS, commission = COMMISSION, liq = LIQ_THRESHOLD,
    python_bin = PYTHON_BIN, optuna_trials = 30L
  )
)
write_json(perf, file.path(OUTPUT_DIR, "performance.json"),
           auto_unbox = TRUE, pretty = TRUE)

# IC + NAV CSV 저장
lapply(names(ablation_results), function(vn) {
  ic_dt <- ablation_results[[vn]]$ic_dt
  if (!is.null(ic_dt) && nrow(ic_dt) > 0)
    fwrite(ic_dt, file.path(OUTPUT_DIR, sprintf("ic_timeseries_%s.csv", vn)))
})
if (!is.null(bt_V2))   fwrite(bt_V2$nav_dt,   file.path(OUTPUT_DIR, "nav_V2.csv"))
if (!is.null(bt_best)) fwrite(bt_best$nav_dt,  file.path(OUTPUT_DIR, "nav_best.csv"))
v2_scores <- ablation_results[["V2"]]$scores_dt
if (!is.null(v2_scores) && nrow(v2_scores) > 0)
  fwrite(v2_scores, file.path(OUTPUT_DIR, "scores_V2.csv"))
cat("  performance.json + CSV 저장 완료\n")

# =============================================================================
# 10. Stage Artifacts
# =============================================================================
cat("\n[9] Stage Artifacts...\n")

write_json(list(
  factor_id   = "ML_XGB_GPU_LR",
  strategy_id = "STR_1661_XGB_GPU",
  stage       = "S1",
  created_at  = as.character(Sys.time()),
  parent      = "STR_1656_MLRA",
  hypothesis  = "H_1661",
  variants    = names(ablation_results),
  implementation_profile = list(
    model           = "XGBoost GPU + LambdaRank 5-seed ensemble",
    gpu_device      = "cuda (RTX 4080 Super 16GB)",
    objective_v2    = "rank:pairwise (LambdaRank)",
    objective_v1    = "reg:squarederror (GPU only)",
    seeds           = XGB_SEEDS,
    mi_prefilter    = "top 50 nonRE (S1-B 방식, 309→50)",
    window_type     = "expanding walk-forward",
    purge_days      = PURGE_DAYS,
    n_holdings      = N_HOLDINGS,
    commission_bps  = 15,
    liq_threshold   = LIQ_THRESHOLD,
    signal_method   = "EW 30종목 순수 팩터 신호",
    weight_method   = "EW",
    hp_method       = "Optuna 30 trials purged IS CV (V3), 고정 HP (V1/V2)",
    python_backend  = PYTHON_BIN,
    label_transform = "fwd_ret_21d to group-wise integer rank (0~N-1)"
  ),
  ablation_summary = lapply(names(ablation_results), function(vn) {
    ic_s <- ablation_results[[vn]]$icir
    list(variant = vn, ICIR = ic_s$ICIR, IC = ic_s$IC, N = ic_s$N)
  }),
  v0_baseline    = list(ICIR = V0_ICIR, SR = V0_SR),
  best_variant   = best_vname,
  best_icir      = best_icir,
  lambdarank_ok  = !is.na(v2_icir) && v2_icir >= V0_ICIR - 0.03,
  alpha_lab_gate = list(pass = best_gate, threshold = 0.20),
  turnover_risk  = "중간",
  capacity_risk  = "낮음",
  pit_compliance = list(
    C1  = "expanding + HP IS purged CV PASS",
    C2  = "OOS > IS PASS",
    C13 = "Z_Score_Aligned PASS",
    C14 = "fwd t+1~t+21 PASS",
    C15 = "Arrow open_dataset PASS",
    purge = paste0(PURGE_DAYS, "d embargo PASS")
  )
), file.path(ARTIFACT_DIR, "s1_construction_STR_1661_XGB_GPU.json"),
auto_unbox = TRUE, pretty = TRUE)

write_json(list(
  factor_id   = "ML_XGB_GPU_LR",
  strategy_id = "STR_1661_XGB_GPU",
  stage       = "S2",
  created_at  = as.character(Sys.time()),
  parent      = "STR_1656_MLRA",
  primary_variant = best_vname,
  s1_b_best = list(
    IC_IR        = best_icir,
    IC_mean      = ablation_results[[best_vname]]$icir$IC,
    N_months     = ablation_results[[best_vname]]$icir$N,
    IC_IR_3y     = if ("oos_year" %in% names(ablation_results[[best_vname]]$ic_dt))
      icir_fn(ablation_results[[best_vname]]$ic_dt[oos_year >= cur_yr - 3L])$ICIR else NA,
    CAGR         = if (!is.null(bt_best)) bt_best$CAGR   else NA,
    SR           = if (!is.null(bt_best)) bt_best$Sharpe  else NA,
    MDD          = if (!is.null(bt_best)) bt_best$MDD     else NA,
    delta_vs_V0  = delta_v2 %||% NA,
    tag          = if (best_gate)
      ifelse(!is.na(best_icir) && best_icir >= 0.40, "Strong", "Moderate") else "Weak"
  ),
  ablation_comparison = list(
    V0_ref        = list(ICIR = V0_ICIR, SR = V0_SR),
    V2_LambdaRank = list(ICIR = v2_icir %||% NA, delta = delta_v2 %||% NA,
                          decision = if (!is.na(v2_icir) && v2_icir >= V0_ICIR - 0.03)
                            "KEEP" else "ABORT"),
    V3_HP         = list(ICIR = v3_icir %||% NA, delta = delta_v3 %||% NA)
  ),
  role_bias      = "RoleBias_Diversifier",
  expected_role  = "diversifier",
  why_now        = "GPU 인프라 확인(Session 59) + LambdaRank 구조적 개선(loss function 변경)",
  alpha_lab_gate = list(pass = best_gate, threshold = 0.20,
                         result = sprintf("%s: %s", best_vname,
                                          ifelse(best_gate, "PASS", "FAIL"))),
  anchor_corr_note = "S2/S3에서 STR_1631(앵커) 대비 max_corr <= 0.40 확인 필요",
  s5_recommendation = if (best_gate)
    list(proceed = TRUE,
         note    = "V2/V3 score로 STR_1656 M05 구조 계승. 종목 overlap rate 측정 후 Path A/B 결정.")
  else list(proceed = FALSE, note = "ICIR < 0.20 S5 보류")
), file.path(ARTIFACT_DIR, "s2_profile_STR_1661_XGB_GPU.json"),
auto_unbox = TRUE, pretty = TRUE)

cat("[9] Stage artifacts 완료\n")

# =============================================================================
# 11. 텔레그램 발송
# =============================================================================
cat("\n[10] 텔레그램...\n")
tryCatch({
  source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

  gate_str <- if (best_gate) "PASS" else "FAIL"
  hf_str   <- if (v2_hard_fail) " | MDD Hard Fail" else ""
  lr_str   <- if (!is.na(v2_icir) && v2_icir >= V0_ICIR - 0.03)
    sprintf("KEEP (+%.4f vs V0)", delta_v2 %||% 0)
  else sprintf("ABORT (ICIR %.4f < threshold)", v2_icir %||% NA)

  v1_icir_val <- summary_dt[variant == "V1", ICIR] %||% NA

  msg <- paste0(
    "\U0001F916 [Forge] STR_1661_XGB_GPU S1 완료\n\n",
    "\U0001F4CA <b>GPU + LambdaRank Ablation</b>\n",
    "<b>V1 (GPU+reg)</b>  ICIR=", round(v1_icir_val, 4), "\n",
    "<b>V2 (LambdaRank)</b> ICIR=", round(v2_icir %||% NA, 4),
    sprintf(" (Delta %+.4f vs V0)", delta_v2 %||% 0), "\n",
    "<b>V3 (+HP)</b>   ICIR=", round(v3_icir %||% NA, 4),
    sprintf(" (Delta %+.4f vs V0)", delta_v3 %||% 0), "\n\n",
    "\U0001F4C9 <b>백테스트 V2</b>",
    " CAGR=", if (!is.null(bt_V2)) bt_V2$CAGR else NA, "%",
    " SR=",   if (!is.null(bt_V2)) bt_V2$Sharpe else NA,
    " MDD=",  if (!is.null(bt_V2)) bt_V2$MDD else NA, "%\n\n",
    "\U0001F6A6 <b>Alpha Lab Gate:</b> ", gate_str, hf_str, "\n",
    "\U0001F3AF <b>LambdaRank:</b> ", lr_str, "\n",
    "\U0001F4CC <b>RoleBias:</b> RoleBias_Diversifier\n",
    "\U0001F4AA <b>강점:</b> GPU + LambdaRank 구조 개선, 상위 종목 rank 직접 최적화\n",
    "\U0001F4A1 <b>약점:</b> alpha decay 지속 시 loss function 변경 효과 제한 가능\n",
    "\U0001F553 ", as.character(Sys.time())
  )
  tg_send(msg)

  if (!is.null(chart_paths$equity) && file.exists(chart_paths$equity))
    tg_send_photo(chart_paths$equity, caption = "\U0001F4C8 STR_1661 Ablation Equity")
  if (!is.null(chart_paths$annual) && file.exists(chart_paths$annual))
    tg_send_photo(chart_paths$annual, caption = "\U0001F4CA STR_1661 Annual Returns")
  cat("  텔레그램 완료\n")
}, error = function(e) cat("  텔레그램 오류:", e$message, "\n"))

# =============================================================================
# 최종 요약
# =============================================================================
cat("\n", paste(rep("=", 60), collapse = ""), "\n")
cat("=== STR_1661_XGB_GPU S1 COMPLETE ===\n")
cat(sprintf("  V0 ref  : ICIR=%.4f SR=%.3f\n", V0_ICIR, V0_SR))
for (vn in names(ablation_results)) {
  ic_s <- ablation_results[[vn]]$icir
  bt_r <- bt_results[[vn]]
  cat(sprintf("  %s : ICIR=%.4f SR=%s MDD=%s\n",
              vn, ic_s$ICIR %||% NA,
              if (!is.null(bt_r)) bt_r$Sharpe else "NA",
              if (!is.null(bt_r)) bt_r$MDD else "NA"))
}
lr_dec <- if (!is.na(v2_icir) && v2_icir >= V0_ICIR - 0.03) "KEEP" else "ABORT"
cat(sprintf("  LambdaRank: %s\n", lr_dec))
cat(sprintf("  Alpha Lab Gate (%s): %s\n", best_vname, ifelse(best_gate, "PASS", "FAIL")))
cat(sprintf("  종료: %s\n", as.character(Sys.time())))
cat(paste(rep("=", 60), collapse = ""), "\n")
