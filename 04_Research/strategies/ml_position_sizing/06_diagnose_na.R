cat("=== Horse Race v2: NA Prediction Diagnosis ===\n")
## 핵심아이디어: 05_horse_race_v2.R의 OOS 예측이 전부 NA인 원인 진단
## OPT-7/MC-P3: walk-forward expanding_window 진단 (MC1 준수)
## 이 스크립트는 진단 전용 — 전략 백테스트가 아님

t0 <- Sys.time()

# ─── 0. Environment (copied from 05_horse_race_v2.R Step 0) ─────────────
.root_candidates <- c(
  Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
  "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR  <- file.path(PROJECT_ROOT, ".cache")
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e)
  file.path(PROJECT_ROOT, "04_Research/strategies/ml_position_sizing"))
HRV2_CACHE <- file.path(CACHE_DIR, "hr_v2")
FDB_DAILY_DIR <- file.path(CACHE_DIR, "factor_db_daily")

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(zoo)
  library(lubridate)
  library(glmnet)
  library(xgboost)
  library(ranger)
  library(quantreg)
})
options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

TAU     <- 0.05
N_TOP   <- 20
MI_TOP_N <- 50
LIQ_THRESH <- 2e8

# ─── 1. Load RAWDATA ────────────────────────────────────────────────────
cat("[Step 1] Loading RAWDATA...\n")
raw <- read_parquet(file.path(CACHE_DIR, "rawdata.parquet")) |> as.data.table()
raw[, Date := as.Date(Date)]
keep_raw <- intersect(c("Date","Ticker","Close","Vol","Size","Ret","BM_Ret"), names(raw))
raw <- raw[, ..keep_raw]
setkey(raw, Ticker, Date)
cat(sprintf("  RAWDATA: %d rows\n", nrow(raw)))

# ─── 2. Load MI prefilter features (cached) ─────────────────────────────
cat("\n[Step 2] Loading MI prefilter features from cache...\n")
SELECTED_FEATURES <- readRDS(file.path(HRV2_CACHE, "mi_prefilter_features.rds"))
cat(sprintf("  SELECTED_FEATURES: %d features\n", length(SELECTED_FEATURES)))
cat(sprintf("  Names: %s\n", paste(SELECTED_FEATURES, collapse=", ")))

FEAT_COLS_USE <- SELECTED_FEATURES

# ─── 3. Load MRS ────────────────────────────────────────────────────────
cat("\n[Step 3] Loading MRS...\n")
reg_dt <- read_parquet(file.path(CACHE_DIR, "regime_v7.parquet")) |> as.data.table()
if ("month_end" %in% names(reg_dt)) {
  reg_dt[, Date := as.Date(month_end)]
} else {
  reg_dt[, Date := as.Date(paste0(apply_month, "-01")) %m+% months(1) - 1L]
}
reg_dt <- reg_dt[!is.na(Date)][order(Date)]
reg_dt[, MRS_lag := shift(MRS, 1L, type="lag")]
reg_dt[is.na(MRS_lag), MRS_lag := 0]
mrs_map <- reg_dt[, .(Date, MRS_lag)]
setkey(mrs_map, Date)

# ─── 4. Load C19 ────────────────────────────────────────────────────────
cat("\n[Step 4] Loading C19...\n")
fdb_monthly_files <- list.files(file.path(CACHE_DIR, "factor_db"),
                                pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
c19_dt <- open_dataset(fdb_monthly_files) |>
  dplyr::filter(Factor_Name == "C19_Composite_Earnings", Coverage == TRUE) |>
  dplyr::select(Date, Ticker, Z_Score) |>
  dplyr::collect() |>
  as.data.table()
c19_dt[, Date := as.Date(Date)]
setkey(c19_dt, Date, Ticker)

# ─── 5. Build a minimal training set (last 24 months of IS) ─────────────
cat("\n[Step 5] Building minimal training set (24 months)...\n")
IS_HARD_START <- as.Date("1990-01-04")
test_me_date  <- as.Date("2023-01-31")

is_end <- test_me_date - 1
is_start <- is_end - 730

raw_is <- raw[Date >= is_start & Date < test_me_date]
liq_dt <- raw_is[, .(liq = mean(Vol*Close, na.rm=TRUE)), by=Ticker]
liq_ok <- liq_dt[liq >= LIQ_THRESH, Ticker]
cat(sprintf("  Liquid tickers: %d\n", length(liq_ok)))

is_me <- raw_is[Ticker %in% liq_ok,
                .(me_d=max(Date)), by=.(YM=format(Date,"%Y-%m"))][order(me_d), me_d]
cat(sprintf("  Training month-ends: %d\n", length(is_me)))

# ─── 6. Build training matrix from fdb_daily ────────────────────────────
cat("\n[Step 6] Building training matrix from fdb_daily...\n")
safe_fill_na <- function(X) { X[is.na(X)] <- 0; X }
TARGET_COL <- "fwd_cvar05"

all_fdb_files <- list.files(FDB_DAILY_DIR, pattern="\\.parquet$", full.names=TRUE)
ym_set <- format(is_me, "%Y%m")
ym_nums <- as.numeric(ym_set)
matched_files <- all_fdb_files[as.numeric(
  sub(".*fdb_daily_(\\d{6})\\.parquet$","\\1", basename(all_fdb_files))
) %in% ym_nums]
cat(sprintf("  Matched fdb_daily files for IS: %d\n", length(matched_files)))

load_cols <- c("Date","Ticker", FEAT_COLS_USE)
me_chars  <- as.character(is_me)

fdb_sub <- rbindlist(lapply(matched_files, function(f) {
  tryCatch({
    dt <- read_parquet(f) |> as.data.table()
    dt[, Date := as.Date(Date)]
    dt_me <- dt[as.character(Date) %in% me_chars]
    if (nrow(dt_me) == 0) return(NULL)
    avail <- intersect(load_cols, names(dt_me))
    dt_me[, ..avail]
  }, error=function(e) NULL)
}), fill=TRUE)
fdb_sub[, Date := as.Date(Date)]
setkey(fdb_sub, Date, Ticker)
cat(sprintf("  fdb_sub rows: %d\n", nrow(fdb_sub)))

loaded_feats <- intersect(FEAT_COLS_USE, names(fdb_sub))
missing_feats_in_fdb <- setdiff(FEAT_COLS_USE, names(fdb_sub))
cat(sprintf("\n  === DIAGNOSIS A: Training feature availability ===\n"))
cat(sprintf("  Requested features: %d\n", length(FEAT_COLS_USE)))
cat(sprintf("  Actually loaded from fdb_daily: %d\n", length(loaded_feats)))
cat(sprintf("  Missing from fdb_daily: %d\n", length(missing_feats_in_fdb)))
if (length(missing_feats_in_fdb) > 0) {
  cat(sprintf("  Missing features: %s\n", paste(missing_feats_in_fdb, collapse=", ")))
}

# Add MRS + fwd_cvar05 target
me_dt_tmp <- data.table(Date = as.Date(unique(fdb_sub$Date)))
setkey(me_dt_tmp, Date); setkey(mrs_map, Date)
me_mrs <- mrs_map[me_dt_tmp, roll=TRUE, on="Date"][, .(Date, MRS_lag)]
fdb_sub <- merge(fdb_sub, me_mrs, by="Date", all.x=TRUE)
fdb_sub[is.na(MRS_lag), MRS_lag := 0]

raw_fwd <- raw[Date > min(is_me) & Date <= max(is_me) + 40L]
cvar_tgt <- rbindlist(lapply(is_me, function(me_d) {
  sub_r <- raw_fwd[Date > me_d & Date <= me_d + 35L]
  if (nrow(sub_r) == 0) return(NULL)
  sub_r[order(Ticker, Date)][,
    if (.N >= 5) .(fwd_cvar05 = quantile(Ret[1:min(21L,.N)], TAU, na.rm=TRUE), Date = me_d)
    else .(fwd_cvar05 = NA_real_, Date = me_d),
    by=Ticker][!is.na(fwd_cvar05)]
}), fill=TRUE)[!is.na(fwd_cvar05)]
rm(raw_fwd); gc()
setkey(cvar_tgt, Date, Ticker)

tr_dt <- merge(fdb_sub, cvar_tgt, by=c("Date","Ticker"), all=FALSE)
cat(sprintf("  Training rows: %d\n", nrow(tr_dt)))

# ─── 7. Train M2 (XGBoost) — NO tryCatch ────────────────────────────────
cat("\n[Step 7] Training M2 (XGBoost) WITHOUT tryCatch...\n")
fc_train <- intersect(FEAT_COLS_USE, names(tr_dt))
cat(sprintf("  Features used for training (intersect): %d\n", length(fc_train)))
cat(sprintf("  Training feature names: %s\n", paste(sort(fc_train), collapse=", ")))

X_train <- safe_fill_na(as.matrix(tr_dt[, ..fc_train]))
y_train <- tr_dt[[TARGET_COL]]
ok <- !is.na(y_train) & is.finite(y_train)
X_train <- X_train[ok, ]; y_train <- y_train[ok]
cat(sprintf("  Training X: %d rows x %d cols\n", nrow(X_train), ncol(X_train)))

dtrain <- xgb.DMatrix(X_train, label=y_train)
params <- list(objective="reg:quantileerror", quantile_alpha=TAU,
               eta=0.02, max_depth=5, subsample=0.7, nthread=4, verbose=0)
mdl_m2 <- xgb.train(params, dtrain, nrounds=300, verbose=0)
cat("  M2 trained successfully.\n")

m2_obj <- list(type="M2", model=mdl_m2, fc=fc_train)
cat(sprintf("  m2_obj$fc: %d features\n", length(m2_obj$fc)))

# ─── 8. Build prediction data for 2023-01 ───────────────────────────────
cat("\n[Step 8] Building pred_dt for 2023-01...\n")
me <- as.Date("2023-01-31")

c19_avail <- c19_dt[Date <= me]
c19_last  <- c19_avail[Date == max(Date)]
raw_pre   <- raw[Date >= me-40L & Date < me]
liq_now   <- raw_pre[, .(lq=mean(Vol*Close,na.rm=TRUE)), by=Ticker]
liq_ok_n  <- liq_now[lq >= LIQ_THRESH, Ticker]
c19_top   <- c19_last[Ticker %in% liq_ok_n & !is.na(Z_Score)][order(-Z_Score)][1:min(N_TOP,.N)]
univ      <- c19_top$Ticker
cat(sprintf("  Universe: %d tickers\n", length(univ)))

me_ym <- format(me, "%Y%m")
pred_file <- list.files(FDB_DAILY_DIR,
                        pattern=paste0("fdb_daily_", me_ym, "\\.parquet$"),
                        full.names=TRUE)
cat(sprintf("  pred_file found: %d (%s)\n", length(pred_file),
            if(length(pred_file)>0) basename(pred_file[1]) else "NONE"))

pf <- read_parquet(pred_file[1]) |> as.data.table()
pf[, Date := as.Date(Date)]
cat(sprintf("  Raw pred file: %d rows, %d cols\n", nrow(pf), ncol(pf)))
cat(sprintf("  Date range: %s ~ %s\n", as.character(min(pf$Date)), as.character(max(pf$Date))))

pf_me <- pf[Date <= me][Date == max(Date)][Ticker %in% univ]
cat(sprintf("  After month-end + universe filter: %d rows\n", nrow(pf_me)))

load_f <- intersect(FEAT_COLS_USE, names(pf_me))
missing_in_pred <- setdiff(FEAT_COLS_USE, names(pf_me))
cat(sprintf("\n  === DIAGNOSIS B: Prediction feature availability ===\n"))
cat(sprintf("  Requested features: %d\n", length(FEAT_COLS_USE)))
cat(sprintf("  Found in pred_dt: %d\n", length(load_f)))
cat(sprintf("  Missing from pred_dt: %d\n", length(missing_in_pred)))
if (length(missing_in_pred) > 0) {
  cat(sprintf("  Missing: %s\n", paste(missing_in_pred, collapse=", ")))
}

pred_dt <- pf_me[, c("Date","Ticker",load_f), with=FALSE]

for (fc in FEAT_COLS_USE) {
  if (!fc %in% names(pred_dt)) pred_dt[, (fc) := 0]
}
mrs_now <- mrs_map[Date <= me][.N, MRS_lag]
if ("MRS_lag" %in% FEAT_COLS_USE) pred_dt[, MRS_lag := mrs_now]
if ("RE_MRS" %in% FEAT_COLS_USE) pred_dt[, RE_MRS := mrs_now]
pred_dt[is.na(pred_dt)] <- 0

cat(sprintf("  pred_dt final: %d rows x %d cols\n", nrow(pred_dt), ncol(pred_dt)))

# ─── 9. CORE DIAGNOSIS: Compare feature names ───────────────────────────
cat("\n\n")
cat("========================================================\n")
cat("        CORE DIAGNOSIS: Feature Name Comparison\n")
cat("========================================================\n\n")

train_feats <- sort(m2_obj$fc)
pred_cols   <- sort(setdiff(names(pred_dt), c("Date","Ticker")))

cat(sprintf("[A] m2_obj$fc (training features): %d\n", length(train_feats)))
cat(sprintf("    %s\n", paste(train_feats, collapse=", ")))

cat(sprintf("\n[B] pred_dt columns (excl Date,Ticker): %d\n", length(pred_cols)))
cat(sprintf("    %s\n", paste(pred_cols, collapse=", ")))

in_train_not_pred <- setdiff(train_feats, pred_cols)
in_pred_not_train <- setdiff(pred_cols, train_feats)

cat(sprintf("\n[C] In TRAINING but NOT in pred_dt: %d\n", length(in_train_not_pred)))
if (length(in_train_not_pred) > 0) {
  cat(sprintf("    >>> %s\n", paste(in_train_not_pred, collapse=", ")))
}

cat(sprintf("\n[D] In pred_dt but NOT in training: %d\n", length(in_pred_not_train)))
if (length(in_pred_not_train) > 0) {
  cat(sprintf("    >>> %s\n", paste(in_pred_not_train, collapse=", ")))
}

exact_match <- identical(sort(train_feats), sort(intersect(train_feats, pred_cols)))
cat(sprintf("\n[E] Exact match (all training feats in pred_dt): %s\n", exact_match))

# ─── 10. Call pred_m2 WITHOUT tryCatch ───────────────────────────────────
cat("\n\n")
cat("========================================================\n")
cat("       ACTUAL PREDICTION CALL (no tryCatch)\n")
cat("========================================================\n\n")

cat("[Test 10a] Attempting: pr[, obj$fc, with=FALSE]\n")
cat(sprintf("  obj$fc length: %d\n", length(m2_obj$fc)))
cat(sprintf("  pred_dt names: %s\n", paste(names(pred_dt), collapse=", ")))

fc_in_pred <- m2_obj$fc %in% names(pred_dt)
cat(sprintf("  obj$fc in pred_dt: %d/%d TRUE\n", sum(fc_in_pred), length(fc_in_pred)))
if (any(!fc_in_pred)) {
  cat(sprintf("  MISSING: %s\n", paste(m2_obj$fc[!fc_in_pred], collapse=", ")))
}

cat("\n[Test 10b] Extracting feature matrix from pred_dt...\n")
X_pred <- safe_fill_na(as.matrix(pred_dt[, m2_obj$fc, with=FALSE]))
cat(sprintf("  X_pred: %d rows x %d cols\n", nrow(X_pred), ncol(X_pred)))
cat(sprintf("  X_pred colnames: %s\n", paste(colnames(X_pred), collapse=", ")))
cat(sprintf("  Any NA in X_pred: %s\n", any(is.na(X_pred))))
cat(sprintf("  Any NaN in X_pred: %s\n", any(is.nan(X_pred))))
cat(sprintf("  Any Inf in X_pred: %s\n", any(is.infinite(X_pred))))

cat("\n[Test 10c] Creating xgb.DMatrix...\n")
dtest <- xgb.DMatrix(X_pred)
cat(sprintf("  DMatrix created: %d rows x %d cols\n",
            nrow(X_pred), ncol(X_pred)))

cat("\n[Test 10d] Calling predict()...\n")
preds <- predict(m2_obj$model, dtest)
cat(sprintf("  Predictions: %d values\n", length(preds)))
cat(sprintf("  Any NA: %s\n", any(is.na(preds))))
cat(sprintf("  Range: [%.6f, %.6f]\n", min(preds, na.rm=TRUE), max(preds, na.rm=TRUE)))
cat(sprintf("  First 5: %s\n", paste(round(preds[1:min(5,length(preds))],6), collapse=", ")))

# ─── 11. Also test M1 and M3 without tryCatch ───────────────────────────
cat("\n\n")
cat("========================================================\n")
cat("       M1 (glmnet) and M3 (ranger) diagnosis\n")
cat("========================================================\n\n")

cat("[M1] Training glmnet...\n")
fc_m1 <- intersect(FEAT_COLS_USE, names(tr_dt))
X_m1  <- safe_fill_na(as.matrix(tr_dt[, ..fc_m1]))
y_m1  <- tr_dt[[TARGET_COL]]
ok_m1 <- !is.na(y_m1) & is.finite(y_m1) & apply(X_m1, 1, function(r) !any(is.nan(r) | is.infinite(r)))
X_m1  <- X_m1[ok_m1, ]; y_m1 <- y_m1[ok_m1]
xm <- colMeans(X_m1); xs <- apply(X_m1, 2, sd); xs[xs==0] <- 1
Xs_m1 <- sweep(sweep(X_m1, 2, xm, "-"), 2, xs, "/")
n_m1 <- length(y_m1)
if (n_m1 > 10000) {
  set.seed(42); idx <- sample(n_m1, 8000)
  Xs_sub <- Xs_m1[idx, ]; y_sub <- y_m1[idx]
} else {
  Xs_sub <- Xs_m1; y_sub <- y_m1
}
tau <- TAU
wt <- ifelse(y_sub < 0, tau, 1 - tau)
m1_model <- glmnet::cv.glmnet(Xs_sub, y_sub, weights=wt, alpha=0.5, nfolds=5)
m1_obj <- list(type="M1_glmnet", model=m1_model, xm=xm, xs=xs, fc=fc_m1)
cat(sprintf("  M1 trained. fc: %d\n", length(m1_obj$fc)))

cat("[M1] Predicting WITHOUT tryCatch...\n")
X_m1p  <- safe_fill_na(as.matrix(pred_dt[, m1_obj$fc, with=FALSE]))
Xs_m1p <- sweep(sweep(X_m1p, 2, m1_obj$xm, "-"), 2, m1_obj$xs, "/")
cat(sprintf("  Xs_m1p: %d x %d\n", nrow(Xs_m1p), ncol(Xs_m1p)))
cat(sprintf("  Any NA/NaN/Inf: %s / %s / %s\n",
            any(is.na(Xs_m1p)), any(is.nan(Xs_m1p)), any(is.infinite(Xs_m1p))))

m1_preds <- as.numeric(predict(m1_obj$model, newx=Xs_m1p, s="lambda.min"))
cat(sprintf("  M1 predictions: %d values, NA: %s\n", length(m1_preds), any(is.na(m1_preds))))
cat(sprintf("  Range: [%.6f, %.6f]\n", min(m1_preds,na.rm=TRUE), max(m1_preds,na.rm=TRUE)))

cat("\n[M3] Training ranger...\n")
fc_m3 <- intersect(FEAT_COLS_USE, names(tr_dt))
df_m3 <- as.data.frame(tr_dt[, c(fc_m3, TARGET_COL), with=FALSE])
for (cc in fc_m3) df_m3[[cc]][is.na(df_m3[[cc]])] <- 0
ok_m3 <- !is.na(df_m3[[TARGET_COL]]) & is.finite(df_m3[[TARGET_COL]])
df_m3 <- df_m3[ok_m3, ]
cat(sprintf("  M3 training data: %d rows\n", nrow(df_m3)))
fmla <- as.formula(paste(TARGET_COL, "~", paste(fc_m3, collapse="+")))
m3_model <- ranger(fmla, data=df_m3, num.trees=200, quantreg=TRUE,
                   min.node.size=20, num.threads=4, verbose=FALSE)
m3_obj <- list(type="M3", model=m3_model, fc=fc_m3)
cat(sprintf("  M3 trained. fc: %d\n", length(m3_obj$fc)))

cat("[M3] Predicting WITHOUT tryCatch...\n")
df_pred_m3 <- as.data.frame(pred_dt[, m3_obj$fc, with=FALSE])
for (cc in m3_obj$fc) df_pred_m3[[cc]][is.na(df_pred_m3[[cc]])] <- 0
cat(sprintf("  df_pred_m3: %d rows x %d cols\n", nrow(df_pred_m3), ncol(df_pred_m3)))
m3_preds_obj <- predict(m3_obj$model, data=df_pred_m3, type="quantiles", quantiles=TAU)
m3_vals <- as.numeric(m3_preds_obj$predictions)
cat(sprintf("  M3 predictions: %d values, NA: %s\n", length(m3_vals), any(is.na(m3_vals))))
cat(sprintf("  Range: [%.6f, %.6f]\n", min(m3_vals,na.rm=TRUE), max(m3_vals,na.rm=TRUE)))

# ─── 12. XGBoost feature importance ─────────────────────────────────────
cat("\n\n")
cat("========================================================\n")
cat("              XGBoost Feature Importance\n")
cat("========================================================\n\n")
imp <- xgb.importance(model=mdl_m2)
cat(sprintf("  Feature importance: %d features\n", nrow(imp)))
cat("  Top 10:\n")
print(head(imp, 10))

imp_feats <- imp$Feature
cat(sprintf("\n  imp$Feature in m2_obj$fc: %d/%d\n",
            sum(imp_feats %in% m2_obj$fc), length(imp_feats)))
diff_imp <- setdiff(imp_feats, m2_obj$fc)
if (length(diff_imp) > 0) {
  cat(sprintf("  In importance but NOT in fc: %s\n", paste(diff_imp, collapse=", ")))
}

# ─── 13. SUMMARY ────────────────────────────────────────────────────────
cat("\n\n")
cat("========================================================\n")
cat("                    SUMMARY\n")
cat("========================================================\n\n")

cat("--- Feature count ---\n")
cat(sprintf("  SELECTED_FEATURES (MI prefilter): %d\n", length(SELECTED_FEATURES)))
cat(sprintf("  Training fc (intersect with tr_dt): %d\n", length(fc_train)))
cat(sprintf("  pred_dt cols (excl Date,Ticker): %d\n", length(pred_cols)))
cat(sprintf("  Features in train NOT in pred: %d\n", length(in_train_not_pred)))
cat(sprintf("  Features in pred NOT in train: %d\n", length(in_pred_not_train)))

cat("\n--- Prediction results (no tryCatch) ---\n")
cat(sprintf("  M1 (glmnet): %d values, all_NA=%s\n", length(m1_preds), all(is.na(m1_preds))))
cat(sprintf("  M2 (XGBoost): %d values, all_NA=%s\n", length(preds), all(is.na(preds))))
cat(sprintf("  M3 (ranger): %d values, all_NA=%s\n", length(m3_vals), all(is.na(m3_vals))))

cat("\n--- Root cause analysis ---\n")
if (length(in_train_not_pred) > 0) {
  cat("  LIKELY CAUSE: Feature name mismatch between training and prediction.\n")
  cat(sprintf("  %d features present during training are MISSING in pred_dt.\n",
              length(in_train_not_pred)))
  cat(sprintf("  Missing: %s\n", paste(in_train_not_pred, collapse=", ")))
} else {
  cat("  Feature names match. Mismatch is NOT the root cause.\n")
}

if (all(is.na(m1_preds)) && all(is.na(preds)) && all(is.na(m3_vals))) {
  cat("  ALL MODELS produce NA -> likely data issue (all zeros, NaN propagation, etc.)\n")
} else {
  cat("  Some or all models produce valid predictions.\n")
  cat("  The tryCatch wrappers in v2 may be masking a different runtime error.\n")
}

cat("\n--- NaN propagation check ---\n")
zero_var_cols <- names(which(apply(X_train, 2, sd) == 0))
cat(sprintf("  Zero-variance training columns: %d\n", length(zero_var_cols)))
if (length(zero_var_cols) > 0) {
  cat(sprintf("  Columns: %s\n", paste(zero_var_cols, collapse=", ")))
}

pred_mat <- as.matrix(pred_dt[, ..FEAT_COLS_USE])
all_zero_cols <- names(which(apply(pred_mat, 2, function(x) all(x == 0))))
cat(sprintf("  All-zero pred_dt columns: %d\n", length(all_zero_cols)))
if (length(all_zero_cols) > 0) {
  cat(sprintf("  Columns: %s\n", paste(all_zero_cols, collapse=", ")))
}

cat(sprintf("\n  'MRS_lag' in FEAT_COLS_USE: %s\n", "MRS_lag" %in% FEAT_COLS_USE))
cat(sprintf("  'RE_MRS' in FEAT_COLS_USE: %s\n", "RE_MRS" %in% FEAT_COLS_USE))
cat(sprintf("  'MRS_lag' in tr_dt names: %s\n", "MRS_lag" %in% names(tr_dt)))
cat(sprintf("  'MRS_lag' in pred_dt names: %s\n", "MRS_lag" %in% names(pred_dt)))

elapsed <- as.numeric(difftime(Sys.time(), t0, units="secs"))
cat(sprintf("\n=== Diagnosis complete in %.1f sec ===\n", elapsed))
