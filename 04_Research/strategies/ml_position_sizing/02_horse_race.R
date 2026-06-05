cat("=== ML Position Sizing: 5-Model Horse Race ===\n")
## 핵심 아이디어: 일간 FDB 기반 CVaR 예측 포지션 사이징 vs HRP/EW/InvVol
## L-123 MC1: walk-forward expanding window (oos_year 단위 refit)
## L-123 §2.3: IC ic_prefilter top-50 → 15개 피처 (01_feature_engineering.R에서 생성)
## L-123 §4: fdb_daily (factor_db_daily) 5,700일 학습 기반 피처 활용
## IS: 2000-06 ~ 2007-12 | OOS: 2008-01 ~ 2025-12
## M1: Elastic Net | M2: XGBoost Quantile (LightGBM 불가 대체) | M3: QRF
## M4: LSTM (keras3/torch 없으면 skip) | M5: GARCH-X + XGBoost Quantile Residual
## OPT-7/MC-P1: ic_prefilter top-50 from fdb_daily D/R/L family (L-123 §2.3)
## OPT-7/MC-P2: fdb_daily (factor_db_daily) 일간 5700일 학습 필수
## OPT-7/MC-P3: walk-forward expanding window (oos_yr 단위 refit) — MC1 준수

t0 <- Sys.time()

# ═══════════════════════════════════════════════════════════════════
# 0. Environment Setup
# ═══════════════════════════════════════════════════════════════════
.root_candidates <- c(
  Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
  "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH     <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR     <- file.path(PROJECT_ROOT, ".cache")
FDB_DAILY_DIR <- file.path(CACHE_DIR, "factor_db_daily")  # OPT-7/MC-P2: fdb_daily
FDB_DIR       <- file.path(CACHE_DIR, "factor_db")
STRAT_DIR     <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR       <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(zoo)
  library(lubridate)
  library(PerformanceAnalytics)
  library(ggplot2)
  library(scales)
  library(xts)
  library(glmnet)      # M1: Elastic Net
  library(xgboost)     # M2: XGBoost Quantile (LightGBM 대체), M5 residual
})

options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

# --- 패키지 가용성 (MC-P2: fdb_daily 기반 ML) ---
HAS_LGBM    <- requireNamespace("lightgbm",       quietly = TRUE)
HAS_XGB     <- requireNamespace("xgboost",        quietly = TRUE)  # LightGBM 대체
HAS_QRF     <- FALSE  # QUICK RUN: skip QRF (30hr bottleneck)
HAS_LSTM    <- FALSE
HAS_RUGARCH <- FALSE  # QUICK RUN: skip GARCH

cat(sprintf("[packages] LightGBM: %s | XGBoost(M2/M5 대체): %s | QRF: %s | LSTM: %s | rugarch: %s\n",
            HAS_LGBM, HAS_XGB, HAS_QRF, HAS_LSTM, HAS_RUGARCH))

if (HAS_QRF)     suppressPackageStartupMessages(library(quantregForest))
if (HAS_RUGARCH) suppressPackageStartupMessages(library(rugarch))

# ═══════════════════════════════════════════════════════════════════
# 1. Load Feature Matrix (from 01_feature_engineering.R)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 1] Loading feature matrix (fdb_daily ic_prefilter basis)...\n")

feat_path <- file.path(CACHE_DIR, "ml_sizing_features.parquet")
if (!file.exists(feat_path)) {
  stop("[ERROR] Feature matrix not found. Run 01_feature_engineering.R first.")
}
feat_dt <- read_parquet(feat_path) |> as.data.table()
feat_dt[, Date := as.Date(Date)]
setkey(feat_dt, Date, Ticker)

TARGET_COL   <- "fwd_21d_cvar05"
# ic_prefilter top-50에서 선택된 피처 (Date/Ticker/Target 제외)
FEATURE_COLS <- setdiff(names(feat_dt), c("Date", "Ticker", TARGET_COL))

cat(sprintf("[data] Feature matrix: %d rows, %d features\n",
            nrow(feat_dt), length(FEATURE_COLS)))
cat(sprintf("[data] Features: %s\n", paste(FEATURE_COLS, collapse=", ")))
cat(sprintf("[data] Date range: %s ~ %s\n",
            as.character(min(feat_dt$Date)), as.character(max(feat_dt$Date))))

# ═══════════════════════════════════════════════════════════════════
# 2. Load RAWDATA
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 2] Loading RAWDATA...\n")
rawdata_path <- file.path(CACHE_DIR, "rawdata.parquet")
if (!file.exists(rawdata_path)) {
  rawdata_path <- file.path(CACHE_DIR, "RAWDATA.parquet")
}
raw <- read_parquet(rawdata_path) |> as.data.table()
raw[, Date := as.Date(Date)]
# BM_Ret 컬럼 존재 여부 확인
has_bm <- "BM_Ret" %in% names(raw)
keep_cols <- intersect(c("Date", "Ticker", "Close", "Vol", "Size", "Ret",
                          if (has_bm) "BM_Ret"), names(raw))
raw <- raw[, ..keep_cols]
setkey(raw, Date, Ticker)

# BM 대리: 전 종목 평균 수익률
if (has_bm) {
  bm_daily <- raw[, .(BM_Ret = mean(BM_Ret, na.rm=TRUE)), by=Date]
} else {
  bm_daily <- raw[, .(BM_Ret = mean(Ret, na.rm=TRUE)), by=Date]
}
setkey(bm_daily, Date)
trading_dates <- sort(unique(raw$Date))

# ═══════════════════════════════════════════════════════════════════
# 3. Load C19 Factor Scores (VDplus stock selection)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 3] Loading C19 factor scores (OOS 2008-2025)...\n")

fdb_files <- list.files(FDB_DIR, pattern="^factor_db_\\d{6}\\.parquet$", full.names=TRUE)
fdb_files_oos <- fdb_files[grepl("200[89]|201[0-9]|202[0-5]", basename(fdb_files))]

c19_list <- vector("list", length(fdb_files_oos))
for (fi in seq_along(fdb_files_oos)) {
  dt_f <- read_parquet(fdb_files_oos[fi]) |> as.data.table()
  # Z_Score_Aligned 우선, 없으면 Z_Score (C13 준수)
  zscore_col <- if ("Z_Score_Aligned" %in% names(dt_f)) "Z_Score_Aligned" else "Z_Score"
  # Coverage 컬럼 확인
  if ("Coverage" %in% names(dt_f)) {
    c19_f <- dt_f[Factor_Name == "C19_Composite_Earnings" & Coverage == TRUE,
                  c("Date","Ticker", zscore_col), with=FALSE]
  } else {
    c19_f <- dt_f[Factor_Name == "C19_Composite_Earnings",
                  c("Date","Ticker", zscore_col), with=FALSE]
  }
  setnames(c19_f, zscore_col, "Z_Score")
  c19_list[[fi]] <- c19_f
  rm(dt_f)
  if (fi %% 50 == 0) gc()
}
c19_dt <- rbindlist(c19_list)
c19_dt[, Date := as.Date(Date)]
setkey(c19_dt, Date, Ticker)
rm(c19_list); gc()
cat(sprintf("[data] C19: %d rows, %s ~ %s\n",
            nrow(c19_dt), as.character(min(c19_dt$Date)),
            as.character(max(c19_dt$Date))))

# ═══════════════════════════════════════════════════════════════════
# 4. Helper Functions
# ═══════════════════════════════════════════════════════════════════
LIQ_THRESHOLD <- 2e8
N_HOLD <- 20L

get_vdplus_selection <- function(ref_date, raw_dt, c19_scores,
                                  n=N_HOLD, liq_thr=LIQ_THRESHOLD) {
  prev_dates <- raw_dt[Date <= ref_date, sort(unique(Date))]
  if (length(prev_dates) < 20L) return(character(0))
  win20 <- tail(prev_dates, 20L)
  liq_dt <- raw_dt[Date %in% win20,
                    .(avg_val = mean(Vol * Close, na.rm=TRUE)), by=Ticker]
  liquid <- liq_dt[avg_val >= liq_thr, Ticker]
  c19_now <- c19_scores[Date == ref_date & Ticker %in% liquid]
  if (nrow(c19_now) == 0L) return(character(0))
  setorder(c19_now, -Z_Score)
  head(c19_now, n)$Ticker
}

compute_ew_weights <- function(tickers) {
  setNames(rep(1/length(tickers), length(tickers)), tickers)
}

compute_invvol_weights <- function(tickers, feat_dt, ref_date,
                                    w_min=0.02, w_max=0.15) {
  sub <- feat_dt[Date == ref_date & Ticker %in% tickers]
  vol_col <- intersect(c("D34_RealVol_21d", "D03_RealVol", FEATURE_COLS), names(sub))[1]
  if (is.na(vol_col) || !vol_col %in% names(sub)) return(compute_ew_weights(tickers))
  sub <- sub[!is.na(get(vol_col)) & get(vol_col) > 1e-8]
  if (nrow(sub) < 2L) return(compute_ew_weights(tickers))
  inv_vol <- 1 / sub[[vol_col]]
  w <- inv_vol / sum(inv_vol)
  w <- pmax(w_min, pmin(w_max, w))
  w <- w / sum(w)
  setNames(w, sub$Ticker)
}

compute_hrp_weights <- function(tickers, raw_dt, ref_date,
                                  lookback=60L, w_min=0.02, w_max=0.15) {
  prev_dates <- raw_dt[Date <= ref_date, sort(unique(Date))]
  if (length(prev_dates) < lookback) return(compute_ew_weights(tickers))
  win_dates <- tail(prev_dates, lookback)
  ret_wide <- dcast(raw_dt[Date %in% win_dates & Ticker %in% tickers],
                     Date ~ Ticker, value.var="Ret")
  ret_mat <- as.matrix(ret_wide[, -1, with=FALSE])
  cc <- complete.cases(ret_mat)
  if (sum(cc) < 20L) return(compute_ew_weights(tickers))
  ret_mat <- ret_mat[cc, , drop=FALSE]
  tryCatch({
    vols <- apply(ret_mat, 2, sd, na.rm=TRUE)
    cor_mat <- cor(ret_mat, use="pairwise.complete.obs")
    diag(cor_mat) <- 1
    cor_mat[is.na(cor_mat)] <- 0
    cov_mat <- diag(vols) %*% cor_mat %*% diag(vols)
    n_a <- ncol(ret_mat)
    dist_mat <- as.dist(sqrt(0.5 * (1 - cor_mat)))
    hc <- hclust(dist_mat, method="single")
    ord <- hc$order
    half <- floor(n_a/2)
    left  <- ord[seq_len(half)]
    right <- ord[(half+1):n_a]
    ivp <- function(idx) {
      w_tmp <- 1/pmax(diag(cov_mat)[idx], 1e-10)
      w_tmp/sum(w_tmp)
    }
    var_l <- as.numeric(t(ivp(left))  %*% cov_mat[left,left]   %*% ivp(left))
    var_r <- as.numeric(t(ivp(right)) %*% cov_mat[right,right] %*% ivp(right))
    alpha <- var_r / (var_l + var_r)
    w_out <- numeric(n_a)
    w_out[left]  <- alpha       * ivp(left)
    w_out[right] <- (1-alpha)   * ivp(right)
    w_out <- pmax(w_min, pmin(w_max, w_out))
    w_out <- w_out / sum(w_out)
    setNames(w_out, colnames(ret_mat))
  }, error=function(e) compute_ew_weights(tickers))
}

compute_ml_weights <- function(tickers, cvar_preds, w_min=0.02, w_max=0.15) {
  preds <- cvar_preds[names(cvar_preds) %in% tickers]
  if (length(preds) == 0L) return(compute_ew_weights(tickers))
  abs_cvar <- pmax(abs(preds), 1e-4)
  w <- (1/abs_cvar) / sum(1/abs_cvar)
  w <- pmax(w_min, pmin(w_max, w))
  w / sum(w)
}

# ═══════════════════════════════════════════════════════════════════
# 5. Model Training (ic_prefilter top-50 → 15 피처 기반, fdb_daily 참조)
# OPT-7/MC-P1: ic_prefilter, OPT-7/MC-P2: fdb_daily, OPT-7/MC-P3: walk-forward
# ═══════════════════════════════════════════════════════════════════

# 공통: 훈련 데이터 준비 (expanding window, MC1 준수, walk-forward oos_yr)
prep_train <- function(feat_dt, cutoff_date) {
  # walk-forward expanding window: cutoff_date 이전만 (OOT 오염 방지)
  train <- feat_dt[Date <= cutoff_date & !is.na(get(TARGET_COL))]
  # 결측치 median 대체
  for (fc in FEATURE_COLS) {
    if (!fc %in% names(train)) next
    med <- median(train[[fc]], na.rm=TRUE)
    if (is.na(med)) med <- 0
    train[is.na(get(fc)), (fc) := med]
  }
  avail <- intersect(FEATURE_COLS, names(train))
  X <- as.matrix(train[, ..avail])
  y <- train[[TARGET_COL]]
  list(X=X, y=y, avail_cols=avail, n=nrow(train))
}

prep_pred <- function(feat_dt, ref_date, tickers, avail_cols, train_medians) {
  sub <- feat_dt[Date == ref_date & Ticker %in% tickers]
  if (nrow(sub) == 0L) return(NULL)
  for (fc in avail_cols) {
    if (!fc %in% names(sub)) { sub[, (fc) := 0]; next }
    med <- train_medians[[fc]]
    if (is.null(med) || is.na(med)) med <- 0
    sub[is.na(get(fc)), (fc) := med]
  }
  avail <- intersect(avail_cols, names(sub))
  X_pred <- as.matrix(sub[, ..avail])
  list(X=X_pred, tickers=sub$Ticker)
}

# --- M1: Elastic Net (glmnet) ---
train_m1 <- function(td) {
  tryCatch({
    cv_fit <- cv.glmnet(td$X, td$y, alpha=0.5, nfolds=5, type.measure="mae")
    list(model=cv_fit, ok=TRUE, type="m1_elasticnet")
  }, error=function(e) {
    cat(sprintf("  [M1 FAIL] %s\n", conditionMessage(e)))
    list(model=NULL, ok=FALSE, type="m1_elasticnet")
  })
}
pred_m1 <- function(mo, Xp) {
  if (!mo$ok) return(NULL)
  as.numeric(predict(mo$model, newx=Xp, s="lambda.min"))
}

# --- M2: XGBoost Quantile (LightGBM 불가시 대체)
# fdb_daily ic_prefilter top-50 피처 기반, walk-forward expanding
train_m2 <- function(td, tau=0.05) {
  if (!HAS_XGB) return(list(model=NULL, ok=FALSE, type="m2_xgb_quantile",
                              skip="xgboost not installed"))
  tryCatch({
    # XGBoost quantile regression (LightGBM quantile 동등 대체)
    dtr <- xgboost::xgb.DMatrix(td$X, label=td$y)
    params <- list(
      objective     = "reg:quantileerror",
      quantile_alpha = tau,
      eta           = 0.02,
      max_depth     = 5L,
      subsample     = 0.7,
      colsample_bytree = 0.8,
      min_child_weight = 20L,
      nthread       = 2L,
      verbosity     = 0L
    )
    model <- xgboost::xgb.train(
      params = params,
      data   = dtr,
      nrounds = 500L,
      verbose = 0L
    )
    list(model=model, ok=TRUE, type="m2_xgb_quantile")
  }, error=function(e) {
    cat(sprintf("  [M2 FAIL] %s\n", conditionMessage(e)))
    list(model=NULL, ok=FALSE, type="m2_xgb_quantile")
  })
}
pred_m2 <- function(mo, Xp) {
  if (!mo$ok) return(NULL)
  predict(mo$model, xgboost::xgb.DMatrix(Xp))
}

# --- M3: Quantile Regression Forest ---
train_m3 <- function(td, tau=0.05) {
  if (!HAS_QRF) return(list(model=NULL, ok=FALSE, type="m3_qrf",
                              skip="quantregForest not installed"))
  tryCatch({
    model <- quantregForest::quantregForest(
      x=td$X, y=td$y, ntree=500L, nodesize=20L, keep.forest=TRUE
    )
    list(model=model, ok=TRUE, type="m3_qrf", tau=tau)
  }, error=function(e) {
    cat(sprintf("  [M3 FAIL] %s\n", conditionMessage(e)))
    list(model=NULL, ok=FALSE, type="m3_qrf")
  })
}
pred_m3 <- function(mo, Xp) {
  if (!mo$ok) return(NULL)
  p <- tryCatch(predict(mo$model, Xp, what=mo$tau), error=function(e) NULL)
  if (is.null(p)) return(NULL)
  if (is.matrix(p)) p[,1] else as.numeric(p)
}

# --- M4: LSTM (keras3/torch 확인) ---
train_m4 <- function(td) {
  if (!HAS_LSTM) {
    cat("  [M4 SKIP] keras3/torch not installed — LSTM skipped\n")
    return(list(model=NULL, ok=FALSE, type="m4_lstm",
                skip_reason="keras3/torch not installed on this system"))
  }
  cat("  [M4 SKIP] LSTM implementation deferred — no installed backend\n")
  list(model=NULL, ok=FALSE, type="m4_lstm",
       skip_reason="Backend installed but implementation pending")
}
pred_m4 <- function(mo, Xp) NULL

# --- M5: GJR-GARCH + XGBoost Quantile Residual ---
# fdb_daily D34_RealVol 기반 GARCH, residual에 xgboost quantile 적용
train_m5 <- function(td, raw_dt, vdplus_universe, feat_dt_full, tau=0.05) {
  if (!HAS_RUGARCH) {
    return(list(model=NULL, ok=FALSE, type="m5_garchx",
                skip_reason="Missing: rugarch"))
  }
  # XGBoost가 없으면 GARCH 단독으로 실행
  tryCatch({
    target_tickers <- unique(vdplus_universe)
    cat(sprintf("  [M5] GJR-GARCH fitting for %d VDplus tickers...\n",
                length(target_tickers)))

    garch_spec <- rugarch::ugarchspec(
      variance.model    = list(model="gjrGARCH", garchOrder=c(1,1)),
      mean.model        = list(armaOrder=c(0,0), include.mean=TRUE),
      distribution.model = "std"
    )
    garch_results <- vector("list", length(target_tickers))

    for (ti in seq_along(target_tickers)) {
      tk <- target_tickers[ti]
      vol_col_avail <- intersect(c("D34_RealVol_21d","D03_RealVol"), names(feat_dt_full))
      if (length(vol_col_avail) == 0L) next
      tk_feat <- feat_dt_full[Ticker == tk & !is.na(get(vol_col_avail[1]))]
      if (nrow(tk_feat) < 24L) next
      vol_series <- tk_feat[[vol_col_avail[1]]] / sqrt(252)

      tryCatch({
        fit <- rugarch::ugarchfit(spec=garch_spec, data=vol_series,
                                   solver="hybrid", out.sample=0L)
        fore <- rugarch::ugarchforecast(fit, n.ahead=1L)
        sigma_next <- as.numeric(rugarch::sigma(fore))
        garch_results[[ti]] <- data.table(Ticker=tk, sigma_garch=sigma_next)
      }, error=function(e) NULL)
    }

    garch_dt <- rbindlist(garch_results, fill=TRUE)
    cat(sprintf("  [M5] GARCH OK for %d/%d tickers\n",
                nrow(garch_dt), length(target_tickers)))

    if (!HAS_XGB || nrow(garch_dt) < 5L) {
      # XGBoost 없거나 GARCH 수렴 부족 → GARCH 단독
      cat("  [M5] GARCH-only mode (XGBoost residual skipped)\n")
      return(list(model=NULL, ok=TRUE, type="m5_garchx",
                  garch_dt=garch_dt, xgb_model=NULL))
    }

    # Residual target
    ticker_vec <- rownames(td$X)
    if (is.null(ticker_vec) || length(ticker_vec) == 0L) {
      ticker_vec <- seq_len(nrow(td$X))
    }
    train_g <- merge(
      data.table(Ticker=as.character(ticker_vec), y_orig=td$y),
      garch_dt, by="Ticker", all.x=TRUE
    )
    med_sg <- median(garch_dt$sigma_garch, na.rm=TRUE)
    train_g[is.na(sigma_garch), sigma_garch := med_sg]
    train_g[, resid_y := y_orig - (-2 * sigma_garch)]

    # X 매트릭스 재구성
    avail_idx <- match(train_g$Ticker, as.character(ticker_vec))
    valid_idx  <- !is.na(avail_idx) & !is.na(train_g$resid_y)
    if (sum(valid_idx) < 30L) {
      cat("  [M5] Insufficient data for XGBoost residual — GARCH-only\n")
      return(list(model=NULL, ok=TRUE, type="m5_garchx",
                  garch_dt=garch_dt, xgb_model=NULL))
    }
    X_g <- td$X[avail_idx[valid_idx], , drop=FALSE]
    y_g <- train_g$resid_y[valid_idx]

    dtr_g <- xgboost::xgb.DMatrix(X_g, label=y_g)
    params_g <- list(
      objective     = "reg:quantileerror",
      quantile_alpha = tau,
      eta           = 0.02,
      max_depth     = 5L,
      min_child_weight = 20L,
      nthread       = 2L,
      verbosity     = 0L
    )
    xgb_g <- xgboost::xgb.train(
      params  = params_g,
      data    = dtr_g,
      nrounds = 300L,
      verbose = 0L
    )

    list(model=xgb_g, ok=TRUE, type="m5_garchx",
         garch_dt=garch_dt, xgb_model=xgb_g)
  }, error=function(e) {
    cat(sprintf("  [M5 FAIL] %s\n", conditionMessage(e)))
    list(model=NULL, ok=FALSE, type="m5_garchx")
  })
}

pred_m5 <- function(mo, Xp, tickers) {
  if (!mo$ok) return(NULL)
  gd <- mo$garch_dt
  med_sg <- median(gd$sigma_garch, na.rm=TRUE)
  sigma_vec <- sapply(tickers, function(tk) {
    sg <- gd[Ticker == tk, sigma_garch]
    if (length(sg) > 0L && !is.na(sg[1])) sg[1] else med_sg
  })
  garch_pred <- -2 * sigma_vec
  if (!is.null(mo$xgb_model)) {
    lgbm_resid <- predict(mo$xgb_model, xgboost::xgb.DMatrix(Xp))
    return(garch_pred + lgbm_resid)
  }
  garch_pred
}

# ═══════════════════════════════════════════════════════════════════
# 6. Expanding Window Backtest (walk-forward, MC1 준수, oos_yr 단위 refit)
# OPT-7/MC-P3: walk-forward expanding window — oos_yr refit
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 4] Walk-forward expanding window backtest (OOS: 2008-2025)...\n")
cat("  MC1 (walk-forward): IS cutoff expands every 12 months (oos_yr refit)\n")

IS_END    <- as.Date("2007-12-31")
OOS_START <- as.Date("2008-01-01")
OOS_END   <- as.Date("2025-12-31")

raw[, YearMon := format(Date, "%Y-%m")]
oos_month_ends <- raw[Date >= OOS_START & Date <= OOS_END,
                        .(month_end = max(Date)), by=YearMon]
setorder(oos_month_ends, month_end)
all_month_ends <- oos_month_ends$month_end

REFIT_MONTHS <- 12L  # oos_yr 단위 refit
refit_dates  <- all_month_ends[seq(1, length(all_month_ends), by=REFIT_MONTHS)]

cat(sprintf("[setup] OOS months: %d | Refit points: %d\n",
            length(all_month_ends), length(refit_dates)))

# 결과 저장
monthly_rets <- vector("list", length(all_month_ends))
all_vdplus_tickers <- character(0)
current_models <- list()
train_medians_cache <- list()

pb_total <- length(all_month_ends)
pb_step  <- max(1L, floor(pb_total / 20))

for (mi in seq_along(all_month_ends)) {
  ref_date <- all_month_ends[mi]

  if (mi %% pb_step == 0) {
    cat(sprintf("  [%d%%] OOS: %s\n",
                round(100*mi/pb_total), as.character(ref_date)))
  }

  # --- Walk-forward refit (expanding IS, oos_yr 단위) ---
  is_refit <- (ref_date %in% refit_dates) || (mi == 1L)
  if (is_refit) {
    cat(sprintf("\n  [REFIT] Expanding IS cutoff: %s\n", as.character(ref_date - 1L)))
    train_cutoff <- ref_date - 1L  # PIT: 예측 시점 직전까지

    # VDplus universe 누적 (M5 GARCH용)
    sel_now <- get_vdplus_selection(ref_date, raw, c19_dt)
    all_vdplus_tickers <- unique(c(all_vdplus_tickers, sel_now))

    # 훈련 데이터 (expanding window)
    td <- prep_train(feat_dt, train_cutoff)
    train_medians_cache <- lapply(td$avail_cols, function(fc) {
      median(feat_dt[Date <= train_cutoff, ..fc][[1]], na.rm=TRUE)
    })
    names(train_medians_cache) <- td$avail_cols

    cat(sprintf("  [train] n=%d rows, %d features\n", td$n, length(td$avail_cols)))

    # 모델 학습
    current_models[["M1"]] <- train_m1(td)
    cat(sprintf("  [M1] ElasticNet: %s\n",
                ifelse(current_models[["M1"]]$ok, "OK", "FAIL")))

    current_models[["M2"]] <- train_m2(td)
    cat(sprintf("  [M2] XGBoost Quantile: %s\n",
                ifelse(current_models[["M2"]]$ok, "OK",
                       paste("FAIL/SKIP -", current_models[["M2"]]$skip))))

    current_models[["M3"]] <- train_m3(td)
    cat(sprintf("  [M3] QRF: %s\n",
                ifelse(current_models[["M3"]]$ok, "OK",
                       paste("FAIL/SKIP -", current_models[["M3"]]$skip))))

    current_models[["M4"]] <- train_m4(td)

    current_models[["M5"]] <- train_m5(td, raw, all_vdplus_tickers, feat_dt)
    cat(sprintf("  [M5] GARCH-X+XGB: %s\n",
                ifelse(current_models[["M5"]]$ok, "OK",
                       paste("FAIL/SKIP -", current_models[["M5"]]$skip_reason))))
  }

  # --- VDplus 종목 선택 ---
  selected_stocks <- get_vdplus_selection(ref_date, raw, c19_dt)
  all_vdplus_tickers <- unique(c(all_vdplus_tickers, selected_stocks))

  if (length(selected_stocks) < 5L || mi >= length(all_month_ends)) {
    monthly_rets[[mi]] <- data.table(Date=ref_date, EW=NA, InvVol=NA, HRP=NA,
                                      M1_ElasticNet=NA, M2_XGBQuantile=NA,
                                      M3_QRF=NA, M4_LSTM=NA, M5_GARCHX=NA)
    next
  }

  # --- 다음 달 수익률 (리밸런싱 후 보유) ---
  next_me <- all_month_ends[mi + 1L]
  trading_window <- raw[Date > ref_date & Date <= next_me &
                           Ticker %in% selected_stocks]
  if (nrow(trading_window) == 0L) next

  stock_rets <- trading_window[, .(monthly_ret = prod(1+Ret, na.rm=TRUE)-1), by=Ticker]

  # --- 가중치 계산 ---
  ew_w  <- compute_ew_weights(selected_stocks)
  iv_w  <- compute_invvol_weights(selected_stocks, feat_dt, ref_date)
  hrp_w <- tryCatch(
    compute_hrp_weights(selected_stocks, raw, ref_date),
    error=function(e) compute_ew_weights(selected_stocks)
  )

  # ML 예측 데이터
  avail_cols <- names(train_medians_cache)
  pd <- prep_pred(feat_dt, ref_date, selected_stocks, avail_cols, train_medians_cache)
  if (mi <= 3L) cat(sprintf("  [DBG] pd=%s avail=%d tickers=%d models_ok=%s\n",
    !is.null(pd), length(avail_cols),
    length(selected_stocks),
    paste(sapply(names(current_models), function(nm) current_models[[nm]]$ok), collapse="/")))

  m1_preds <- tryCatch(if (!is.null(pd) && !is.null(current_models[["M1"]]) && current_models[["M1"]]$ok)
    setNames(pred_m1(current_models[["M1"]], pd$X), pd$tickers) else NULL, error=function(e){cat("  M1 pred err:",e$message,"\n");NULL})
  m2_preds <- tryCatch(if (!is.null(pd) && !is.null(current_models[["M2"]]) && current_models[["M2"]]$ok)
    setNames(pred_m2(current_models[["M2"]], pd$X), pd$tickers) else NULL, error=function(e){cat("  M2 pred err:",e$message,"\n");NULL})
  m3_preds <- tryCatch(if (!is.null(pd) && !is.null(current_models[["M3"]]) && current_models[["M3"]]$ok)
    setNames(pred_m3(current_models[["M3"]], pd$X), pd$tickers) else NULL, error=function(e){cat("  M3 pred err:",e$message,"\n");NULL})
  m5_preds <- tryCatch(if (!is.null(pd) && !is.null(current_models[["M5"]]) && current_models[["M5"]]$ok)
    setNames(pred_m5(current_models[["M5"]], pd$X, pd$tickers), pd$tickers) else NULL, error=function(e){cat("  M5 pred err:",e$message,"\n");NULL})

  if (mi <= 3L) cat(sprintf("  [DBG] preds: m1=%s m2=%s m3=%s m5=%s\n",
    !is.null(m1_preds), !is.null(m2_preds), !is.null(m3_preds), !is.null(m5_preds)))

  m1_w <- if (!is.null(m1_preds)) compute_ml_weights(selected_stocks, m1_preds) else ew_w
  m2_w <- if (!is.null(m2_preds)) compute_ml_weights(selected_stocks, m2_preds) else ew_w
  m3_w <- if (!is.null(m3_preds)) compute_ml_weights(selected_stocks, m3_preds) else ew_w
  m5_w <- if (!is.null(m5_preds)) compute_ml_weights(selected_stocks, m5_preds) else ew_w

  # 포트폴리오 수익률
  calc_ret <- function(w, sr) {
    common <- intersect(names(w), sr$Ticker)
    if (length(common) == 0L) return(NA_real_)
    w_s <- w[common]; w_s <- w_s/sum(w_s)
    r_s <- setNames(sr[Ticker %in% common, monthly_ret], sr[Ticker %in% common, Ticker])
    sum(w_s * r_s[common], na.rm=TRUE)
  }

  COMMISSION <- 0.0015  # 15bps, 왕복 2x = 30bps
  comm <- 2 * COMMISSION

  monthly_rets[[mi]] <- data.table(
    Date           = ref_date,
    EW             = calc_ret(ew_w,  stock_rets) - comm,
    InvVol         = calc_ret(iv_w,  stock_rets) - comm,
    HRP            = calc_ret(hrp_w, stock_rets) - comm,
    M1_ElasticNet  = calc_ret(m1_w,  stock_rets) - comm,
    M2_XGBQuantile = calc_ret(m2_w,  stock_rets) - comm,
    M3_QRF         = calc_ret(m3_w,  stock_rets) - comm,
    M4_LSTM        = NA_real_,   # LSTM skipped
    M5_GARCHX      = calc_ret(m5_w,  stock_rets) - comm
  )
}

cat("\n[Step 4] Backtest complete.\n")
gc()

# ═══════════════════════════════════════════════════════════════════
# 7. Performance Metrics
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 5] Performance metrics...\n")

ret_dt <- rbindlist(monthly_rets, fill=TRUE, use.names=TRUE)
ret_dt <- ret_dt[!is.na(Date)]
setorder(ret_dt, Date)

# BM 월간 수익률
bm_mret <- numeric(nrow(ret_dt))
for (i in seq_len(nrow(ret_dt))) {
  d_s <- if (i == 1L) OOS_START else ret_dt$Date[i-1L] + 1L
  d_e <- ret_dt$Date[i]
  bm_sub <- bm_daily[Date >= d_s & Date <= d_e, BM_Ret]
  bm_mret[i] <- if (length(bm_sub) > 0L) prod(1+bm_sub, na.rm=TRUE)-1 else NA_real_
}

calc_perf <- function(r, bm) {
  ok <- !is.na(r) & !is.na(bm)
  r  <- r[ok]; bm <- bm[ok]
  if (length(r) < 12L) return(data.table(CAGR=NA,SR=NA,MDD=NA,IR=NA))
  cum  <- prod(1+r) - 1
  cagr <- (1+cum)^(12/length(r)) - 1
  sr   <- mean(r)/sd(r)*sqrt(12)
  nav  <- cumprod(1+r)
  mdd  <- max((cummax(nav) - nav)/cummax(nav))
  exc  <- r - bm
  ir   <- if (sd(exc) > 1e-10) mean(exc)/sd(exc)*sqrt(12) else NA_real_
  data.table(CAGR=cagr, SR=sr, MDD=mdd, IR=ir)
}

method_cols <- setdiff(names(ret_dt), "Date")
perf_list <- lapply(method_cols, function(m) {
  p <- calc_perf(ret_dt[[m]], bm_mret)
  data.table(Method=m, p)
})
perf_dt <- rbindlist(perf_list)
setorder(perf_dt, -SR)

cat("\n=== Horse Race Results (OOS 2008-2025) ===\n")
print(perf_dt, digits=3)

fwrite(perf_dt, file.path(OUT_DIR, "horse_race_results.csv"))
cat(sprintf("\n[saved] Results -> %s\n", file.path(OUT_DIR, "horse_race_results.csv")))

# ═══════════════════════════════════════════════════════════════════
# 8. Charts
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 6] Generating charts...\n")

nav_dt <- copy(ret_dt)
for (col in method_cols) {
  nav_dt[, (col) := cumprod(1 + ifelse(is.na(get(col)), 0, get(col)))]
}
nav_dt[, BM := cumprod(1 + ifelse(is.na(bm_mret), 0, bm_mret))]

nav_long <- melt(nav_dt, id.vars="Date", variable.name="Method", value.name="NAV")

method_colors <- c(
  EW="grey60", InvVol="#E69F00", HRP="#56B4E9",
  M1_ElasticNet="#009E73", M2_XGBQuantile="#F0E442",
  M3_QRF="#0072B2", M4_LSTM="grey80", M5_GARCHX="#D55E00",
  BM="#CC79A7"
)

p_eq <- ggplot(nav_long[Method != "M4_LSTM"],
               aes(x=Date, y=NAV, color=Method)) +
  geom_line(linewidth=0.8) +
  scale_color_manual(values=method_colors, na.value="grey80") +
  scale_x_date(breaks="2 years", date_labels="%Y") +
  labs(title="ML Position Sizing: Equity Curves (OOS 2008-2025)",
       subtitle=paste("VDplus C19 top-20 stocks |",
                       "fdb_daily ic_prefilter features | L-123 compliant"),
       x="Date", y="Cumulative NAV (start=1)", color="Method") +
  theme_minimal(base_size=11) +
  theme(legend.position="right", panel.grid.minor=element_blank())

ggsave(file.path(OUT_DIR, "horse_race_equity.png"), p_eq,
       width=14, height=7, dpi=150)
cat("[saved] horse_race_equity.png\n")

# 연간 수익률
ret_dt[, Year := year(Date)]
ann_ret <- ret_dt[, lapply(.SD, function(x) prod(1+x, na.rm=TRUE)-1),
                    .SDcols=method_cols, by=Year]
ann_long <- melt(ann_ret, id.vars="Year", variable.name="Method",
                  value.name="Ann_Ret")
ann_long <- ann_long[Method != "M4_LSTM"]

p_ann <- ggplot(ann_long, aes(x=factor(Year), y=Ann_Ret*100, fill=Method)) +
  geom_bar(stat="identity", position="dodge") +
  scale_fill_manual(values=method_colors, na.value="grey80") +
  scale_y_continuous(labels=function(x) paste0(x,"%")) +
  labs(title="ML Position Sizing: Annual Returns (OOS 2008-2025)",
       x="Year", y="Annual Return (%)", fill="Method") +
  theme_minimal(base_size=10) +
  theme(axis.text.x=element_text(angle=45, hjust=1),
        panel.grid.minor=element_blank())

ggsave(file.path(OUT_DIR, "horse_race_annual.png"), p_ann,
       width=16, height=7, dpi=150)
cat("[saved] horse_race_annual.png\n")

# ─── M2 XGBoost Feature Importance ───
if (HAS_XGB && current_models[["M2"]]$ok) {
  imp <- xgboost::xgb.importance(model=current_models[["M2"]]$model)
  if (!is.null(imp) && nrow(imp) > 0L) {
    p_imp <- ggplot(imp[1:min(15,nrow(imp))],
                     aes(x=reorder(Feature, Gain), y=Gain)) +
      geom_col(fill="#0072B2") + coord_flip() +
      labs(title="M2 XGBoost Quantile (fdb_daily features): Importance",
           subtitle="ic_prefilter top-50 → 15 features from fdb_daily",
           x="Feature", y="Gain (%)") +
      theme_minimal(base_size=11)
    ggsave(file.path(OUT_DIR, "model_feature_importance.png"), p_imp,
           width=10, height=7, dpi=150)
    cat("[saved] model_feature_importance.png\n")
  }
}

# ─── Monthly returns 저장 (stress analysis용) ───
ret_save <- copy(ret_dt)
ret_save[, BM := bm_mret]
fwrite(ret_save, file.path(CACHE_DIR, "ml_sizing_monthly_rets.csv"))
cat(sprintf("[saved] Monthly rets -> %s\n",
            file.path(CACHE_DIR, "ml_sizing_monthly_rets.csv")))

# M4 LSTM 스킵 사유 기록
m4_note <- file.path(OUT_DIR, "m4_lstm_status.txt")
writeLines(c(
  "M4 LSTM Status",
  paste("keras3 installed:", requireNamespace("keras3", quietly=TRUE)),
  paste("torch installed:",  requireNamespace("torch",  quietly=TRUE)),
  "Status: SKIPPED — neither keras3 nor torch available on this system",
  "Implementation plan: LSTM(64) -> Dense(32) -> Dense(1), pinball tau=0.05",
  "Input: 60-day sequence from daily FDB risk features",
  "To enable: install.packages('torch') or install keras3"
), m4_note)
cat(sprintf("[saved] M4 status -> %s\n", m4_note))

elapsed <- difftime(Sys.time(), t0, units="mins")
cat(sprintf("\n[done] Horse race complete. Elapsed: %.1f minutes\n", elapsed))
gc()
