cat("=== Horse Race v2: Walk-Forward First Iteration Diagnosis ===\n")
## 핵심아이디어: walk_forward() 첫 반복에서 정확히 무엇이 실패하는지 추적
## OPT-7/MC-P3: walk-forward expanding_window 진단 (MC1 준수)
## 이 스크립트는 진단 전용 — 전략 백테스트가 아님

t0 <- Sys.time()

# ─── 0. Environment ─────────────────────────────────────────────────────
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

TAU          <- 0.05
N_TOP        <- 20
TREE_N       <- 500
TREE_THREADS <- 4
LIQ_THRESH   <- 2e8
MI_TOP_N     <- 50

IS_HARD_START   <- as.Date("1990-01-04")
PILOT_OOS_START <- as.Date("2023-01-01")
PILOT_OOS_END   <- as.Date("2026-04-08")

# ─── 1. Load data (same as 05_horse_race_v2.R) ──────────────────────────
cat("[Step 1] Loading RAWDATA...\n")
raw <- read_parquet(file.path(CACHE_DIR, "rawdata.parquet")) |> as.data.table()
raw[, Date := as.Date(Date)]
keep_raw <- intersect(c("Date","Ticker","Close","Vol","Size","Ret","BM_Ret"), names(raw))
raw <- raw[, ..keep_raw]
setkey(raw, Ticker, Date)

SELECTED_FEATURES <- readRDS(file.path(HRV2_CACHE, "mi_prefilter_features.rds"))
TARGET_COL    <- "fwd_cvar05"
FEAT_COLS_USE <- SELECTED_FEATURES

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

fdb_monthly_files <- list.files(file.path(CACHE_DIR, "factor_db"),
                                pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
c19_dt <- open_dataset(fdb_monthly_files) |>
  dplyr::filter(Factor_Name == "C19_Composite_Earnings", Coverage == TRUE) |>
  dplyr::select(Date, Ticker, Z_Score) |>
  dplyr::collect() |>
  as.data.table()
c19_dt[, Date := as.Date(Date)]
setkey(c19_dt, Date, Ticker)

safe_fill_na <- function(X) { X[is.na(X)] <- 0; X }

cat("[data loaded]\n\n")

# ─── 2. Replicate walk_forward first OOS month exactly ──────────────────
cat("========================================================\n")
cat("Simulating walk_forward() first OOS iteration (2023-01)\n")
cat("========================================================\n\n")

# Get OOS months same as walk_forward
pilot_me <- raw[Date >= PILOT_OOS_START & Date <= PILOT_OOS_END,
                .(me=max(Date)), by=.(YM=format(Date,"%Y-%m"))][order(me), me]
mi <- 1
me <- as.Date(pilot_me[mi])
yr <- year(me)
mstr <- format(me, "%Y-%m")
last_yr <- -1L
mdls <- list(m1=NULL, m2=NULL, m3=NULL, m4=NULL, m5=NULL)

cat(sprintf("  me = %s, yr = %d, last_yr = %d\n", me, yr, last_yr))
cat(sprintf("  yr > last_yr = %s (should refit)\n", yr > last_yr))

# ─── REFIT block (lines 659-701 of 05_horse_race_v2.R) ──────────────────
cat(sprintf("\n  [REFIT %d] expanding_window IS: %s ~ %s\n",
            yr, format(IS_HARD_START,"%Y-%m"), format(me-1,"%Y-%m")))

raw_is <- raw[Date >= IS_HARD_START & Date < me]
liq_dt <- raw_is[, .(liq = mean(Vol*Close, na.rm=TRUE)), by=Ticker]
liq_ok <- liq_dt[liq >= LIQ_THRESH, Ticker]
cat(sprintf("    Liquid tickers: %d\n", length(liq_ok)))

is_me <- raw_is[Ticker %in% liq_ok,
                .(me_d=max(Date)), by=.(YM=format(Date,"%Y-%m"))][order(me_d), me_d]
is_me_use <- is_me[is_me >= me - 365*10]
if (length(is_me_use) < 24) is_me_use <- is_me
cat(sprintf("    Training month-ends: %d (non-overlapping obs)\n", length(is_me_use)))
cat(sprintf("    IS range: %s ~ %s\n", as.character(min(is_me_use)), as.character(max(is_me_use))))

# ─── build_training_matrix (NO tryCatch this time) ──────────────────────
cat("\n  [BUILD TRAINING MATRIX]\n")
month_ends <- is_me_use
selected_feats <- FEAT_COLS_USE
liq_tickers <- liq_ok

all_fdb_files <- list.files(FDB_DAILY_DIR, pattern="\\.parquet$", full.names=TRUE)
ym_set <- format(month_ends, "%Y%m")
ym_nums <- as.numeric(ym_set)
matched_files <- all_fdb_files[as.numeric(
  sub(".*fdb_daily_(\\d{6})\\.parquet$","\\1", basename(all_fdb_files))
) %in% ym_nums]
cat(sprintf("    Matched fdb_daily files: %d / %d month-ends\n",
            length(matched_files), length(month_ends)))

load_cols <- c("Date","Ticker", selected_feats)
me_chars  <- as.character(month_ends)

cat("    Loading fdb_daily files (this may take a while)...\n")
load_t0 <- Sys.time()
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
cat(sprintf("    fdb_daily loaded: %d rows in %.1f sec\n",
            nrow(fdb_sub), as.numeric(difftime(Sys.time(), load_t0, units="secs"))))

if (!is.null(liq_tickers)) {
  before <- nrow(fdb_sub)
  fdb_sub <- fdb_sub[Ticker %in% liq_tickers]
  cat(sprintf("    After liquidity filter: %d rows (removed %d)\n", nrow(fdb_sub), before - nrow(fdb_sub)))
}
setkey(fdb_sub, Date, Ticker)

# MRS
me_dt_tmp <- data.table(Date = as.Date(unique(fdb_sub$Date)))
setkey(me_dt_tmp, Date)
me_mrs <- mrs_map[me_dt_tmp, roll=TRUE, on="Date"][, .(Date, MRS_lag)]
fdb_sub <- merge(fdb_sub, me_mrs, by="Date", all.x=TRUE)
fdb_sub[is.na(MRS_lag), MRS_lag := 0]

# fwd CVaR
cat("    Computing fwd_cvar05...\n")
raw_fwd <- raw[Date > min(month_ends) & Date <= max(month_ends) + 40L]
cvar_tgt <- rbindlist(lapply(month_ends, function(me_d) {
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
cat(sprintf("    Training matrix: %d rows\n", nrow(tr_dt)))

# ─── Train M2 (XGBoost) WITHOUT tryCatch ────────────────────────────────
cat("\n  [TRAINING M2 — NO tryCatch]\n")
fc <- intersect(FEAT_COLS_USE, names(tr_dt))
cat(sprintf("    fc: %d features\n", length(fc)))
X  <- safe_fill_na(as.matrix(tr_dt[, ..fc]))
y  <- tr_dt[[TARGET_COL]]
ok <- !is.na(y) & is.finite(y)
cat(sprintf("    ok: %d/%d\n", sum(ok), length(ok)))
X <- X[ok, ]; y <- y[ok]
cat(sprintf("    X: %d rows x %d cols, y: %d\n", nrow(X), ncol(X), length(y)))

dtrain <- xgb.DMatrix(X, label=y)
params <- list(objective="reg:quantileerror", quantile_alpha=TAU,
               eta=0.02, max_depth=5, subsample=0.7, nthread=TREE_THREADS, verbose=0)
m2_model <- xgb.train(params, dtrain, nrounds=300, verbose=0)
m2_obj <- list(type="M2", model=m2_model, fc=fc)
cat(sprintf("    M2 trained. fc=%d\n", length(m2_obj$fc)))

# ─── Prediction block (lines 704-756 of 05_horse_race_v2.R) ─────────────
cat("\n  [PREDICTION — same as walk_forward]\n")

# C19 universe
c19_avail <- c19_dt[Date <= me]
c19_last  <- c19_avail[Date == max(Date)]
raw_pre   <- raw[Date >= me-40L & Date < me]
liq_now   <- raw_pre[, .(lq=mean(Vol*Close,na.rm=TRUE)), by=Ticker]
liq_ok_n  <- liq_now[lq >= LIQ_THRESH, Ticker]
c19_top   <- c19_last[Ticker %in% liq_ok_n & !is.na(Z_Score)][order(-Z_Score)][1:min(N_TOP,.N)]
univ      <- c19_top$Ticker
cat(sprintf("    Universe: %d tickers\n", length(univ)))

# pred_file
me_ym <- format(me, "%Y%m")
pred_file <- list.files(FDB_DAILY_DIR,
                        pattern=paste0("fdb_daily_", me_ym, "\\.parquet$"),
                        full.names=TRUE)

pred_dt <- tryCatch({
  pf <- read_parquet(pred_file[1]) |> as.data.table()
  pf[, Date := as.Date(Date)]
  pf_me <- pf[Date <= me][Date == max(Date)][Ticker %in% univ]
  load_f <- intersect(FEAT_COLS_USE, names(pf_me))
  pf_me[, c("Date","Ticker",load_f), with=FALSE]
}, error=function(e) data.table())

cat(sprintf("    pred_dt: %d rows, %d cols\n", nrow(pred_dt), ncol(pred_dt)))

# Fill missing features (same as v2 code)
for (fcc in FEAT_COLS_USE) {
  if (!fcc %in% names(pred_dt)) pred_dt[, (fcc) := 0]
}
mrs_now <- mrs_map[Date <= me][.N, MRS_lag]
pred_dt[, RE_MRS := if ("RE_MRS" %in% FEAT_COLS_USE) mrs_now else NULL]
pred_dt[is.na(pred_dt)] <- 0

cat(sprintf("    pred_dt after fill: %d rows, %d cols\n", nrow(pred_dt), ncol(pred_dt)))

# ─── CRITICAL: Call pred_m2 exactly as in v2 (WITH tryCatch) ─────────────
cat("\n  [PREDICTION — WITH tryCatch (as v2 does it)]\n")
pred_m2_v2 <- function(obj, pr) {
  tryCatch({
    if (is.null(obj)) return(rep(NA_real_, nrow(pr)))
    X <- safe_fill_na(as.matrix(pr[, obj$fc, with=FALSE]))
    predict(obj$model, xgb.DMatrix(X))
  }, error=function(e) {
    cat(sprintf("    >>> pred_m2 ERROR: %s\n", conditionMessage(e)))
    rep(NA_real_, nrow(pr))
  })
}

cv2_with_tc <- pred_m2_v2(m2_obj, pred_dt)
cat(sprintf("    cv2 (with tryCatch): %d values, all_NA=%s\n",
            length(cv2_with_tc), all(is.na(cv2_with_tc))))
if (!all(is.na(cv2_with_tc))) {
  cat(sprintf("    Range: [%.6f, %.6f]\n", min(cv2_with_tc,na.rm=TRUE), max(cv2_with_tc,na.rm=TRUE)))
}

# ─── ALSO: Call without tryCatch ─────────────────────────────────────────
cat("\n  [PREDICTION — WITHOUT tryCatch]\n")
X_raw <- safe_fill_na(as.matrix(pred_dt[, m2_obj$fc, with=FALSE]))
cv2_no_tc <- predict(m2_obj$model, xgb.DMatrix(X_raw))
cat(sprintf("    cv2 (no tryCatch): %d values, all_NA=%s\n",
            length(cv2_no_tc), all(is.na(cv2_no_tc))))
if (!all(is.na(cv2_no_tc))) {
  cat(sprintf("    Range: [%.6f, %.6f]\n", min(cv2_no_tc,na.rm=TRUE), max(cv2_no_tc,na.rm=TRUE)))
}

# ─── calc_pr test ────────────────────────────────────────────────────────
cat("\n  [calc_pr test]\n")
next_me <- as.Date(pilot_me[2])
mret    <- raw[Date > me & Date <= next_me & Ticker %in% univ,
               .(mret=prod(1+Ret,na.rm=TRUE)-1), by=Ticker]
cat(sprintf("    mret: %d tickers\n", nrow(mret)))

calc_pr_debug <- function(cv_vec) {
  cat(sprintf("      cv_vec: %d values, all_NA=%s, null=%s\n",
              length(cv_vec), all(is.na(cv_vec)), is.null(cv_vec)))
  if (is.null(cv_vec) || all(is.na(cv_vec))) { cat("      -> early return NA (null or all-NA)\n"); return(NA_real_) }
  ok <- !is.na(cv_vec) & pred_dt$Ticker %in% mret$Ticker
  cat(sprintf("      ok: %d/%d TRUE\n", sum(ok), length(ok)))
  if (sum(ok) < 3) { cat("      -> early return NA (ok < 3)\n"); return(NA_real_) }
  tks_ok <- pred_dt$Ticker[ok]; cv_ok <- cv_vec[ok]
  cat(sprintf("      tks_ok: %d, cv_ok range: [%.6f, %.6f]\n",
              length(tks_ok), min(cv_ok), max(cv_ok)))
  w <- tryCatch({
    acv <- abs(cv_ok); acv[is.na(acv)] <- max(acv, na.rm=TRUE); acv[acv==0] <- 1e-6
    ww <- 1/acv; ww <- pmax(pmin(ww/sum(ww), 0.15), 0.02); ww/sum(ww) |> setNames(tks_ok)
  }, error=function(e) { cat(sprintf("      >>> cvar2w ERROR: %s\n", conditionMessage(e))); setNames(numeric(0), character(0)) })
  cat(sprintf("      weights: %d, sum=%.4f\n", length(w), sum(w)))
  if (length(w) == 0) { cat("      -> early return NA (empty weights)\n"); return(NA_real_) }
  mr <- mret[Ticker %in% names(w)]
  cat(sprintf("      mret matched: %d\n", nrow(mr)))
  result <- sum(w[mr$Ticker] * mr$mret, na.rm=TRUE)
  cat(sprintf("      result: %.6f\n", result))
  result
}

cat("    Testing calc_pr with cv2 (no tryCatch predictions):\n")
r2 <- calc_pr_debug(cv2_no_tc)
cat(sprintf("    Final M2 return: %.6f (NA=%s)\n\n", r2, is.na(r2)))

# ─── Check if MRS_lag is added to tr_dt during build_training_matrix ────
# but NOT expected by models that only use FEAT_COLS_USE
cat("\n  [MRS_lag column analysis]\n")
cat(sprintf("    'MRS_lag' in names(tr_dt): %s\n", "MRS_lag" %in% names(tr_dt)))
cat(sprintf("    'MRS_lag' in FEAT_COLS_USE: %s\n", "MRS_lag" %in% FEAT_COLS_USE))
cat(sprintf("    'MRS_lag' in m2_obj$fc: %s\n", "MRS_lag" %in% m2_obj$fc))
cat(sprintf("    fc = intersect(FEAT_COLS_USE, names(tr_dt)) includes MRS_lag: %s\n",
            "MRS_lag" %in% intersect(FEAT_COLS_USE, names(tr_dt))))

# ─── FINAL: Replicate the EXACT pred_m2 call from within walk_forward ───
cat("\n\n========================================================\n")
cat("CRITICAL: Replicate pred_m2(mdls$m2, pred_dt) exactly\n")
cat("========================================================\n\n")

# In walk_forward, mdls$m2 is assigned from train_m2(tr_dt)
# Let's call train_m2 exactly:
train_m2_exact <- function(tr) {
  tryCatch({
    fc <- intersect(FEAT_COLS_USE, names(tr))
    X  <- safe_fill_na(as.matrix(tr[, ..fc]))
    y  <- tr[[TARGET_COL]]
    ok <- !is.na(y) & is.finite(y)
    if (sum(ok) < 50) return(NULL)
    X <- X[ok, ]; y <- y[ok]
    dtrain <- xgb.DMatrix(X, label=y)
    params <- list(objective="reg:quantileerror", quantile_alpha=TAU,
                   eta=0.02, max_depth=5, subsample=0.7,
                   nthread=TREE_THREADS, verbose=0)
    list(type="M2", model=xgb.train(params, dtrain, nrounds=300, verbose=0), fc=fc)
  }, error=function(e) { cat("  [M2 ERR]", conditionMessage(e), "\n"); NULL })
}

mdls_m2 <- train_m2_exact(tr_dt)
cat(sprintf("  mdls$m2 from train_m2: null=%s\n", is.null(mdls_m2)))
if (!is.null(mdls_m2)) {
  cat(sprintf("  mdls$m2$fc: %d features\n", length(mdls_m2$fc)))

  # Now pred_m2 exactly:
  pred_m2_exact <- function(obj, pr) {
    tryCatch({
      if (is.null(obj)) return(rep(NA_real_, nrow(pr)))
      X <- safe_fill_na(as.matrix(pr[, obj$fc, with=FALSE]))
      predict(obj$model, xgb.DMatrix(X))
    }, error=function(e) {
      cat(sprintf("  >>> EXACT pred_m2 ERROR: %s\n", conditionMessage(e)))
      cat(sprintf("  >>> Error class: %s\n", paste(class(e), collapse=", ")))
      rep(NA_real_, nrow(pr))
    })
  }

  cv2_exact <- pred_m2_exact(mdls_m2, pred_dt)
  cat(sprintf("  cv2_exact: %d values, all_NA=%s\n", length(cv2_exact), all(is.na(cv2_exact))))
  if (!all(is.na(cv2_exact))) {
    cat(sprintf("  Range: [%.6f, %.6f]\n", min(cv2_exact,na.rm=TRUE), max(cv2_exact,na.rm=TRUE)))
  }
}

elapsed <- as.numeric(difftime(Sys.time(), t0, units="secs"))
cat(sprintf("\n=== Walk-forward diagnosis complete in %.1f sec ===\n", elapsed))
