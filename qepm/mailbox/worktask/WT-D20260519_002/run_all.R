# ============================================================================
# WT-D20260519_002 — Forge Stage Pure Function (v6.1)
# Bear Regime Prediction Engine v1.0 — 5-model Ensemble Train + Path A/B Backtest
# ============================================================================
# Boundary (HARD): 3-package (alpha/risk/optimization) read-only.
#   Allowed write: run_all.R (this), backtest_result/*, judge_ready/*, output/*
# Charter §10 v1.8 discovery_design_phase_a — alpha agent명시 위임 + Forge empirical execution.
# Substitute flags (honest declaration):
#   - LightGBM unavailable → xgboost substitute (gradient boosting equivalent paradigm)
#   - LSTM/keras unavailable → 5-lag explicit-lag glmnet sequential proxy
#   - 32 features design → 21 features actual buildable from local cache (FRED + rawdata)
#     11 features deferred to Phase B (VKOSPI / SEIBro / KR credit / KR LEI direct fetch)
# ============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(glmnet)
  library(ranger)
  library(xgboost)
  library(depmixS4)
  library(PerformanceAnalytics)
  library(jsonlite)
  library(xts)
  library(zoo)
})

set.seed(20260518)

# --- Path setup ---
PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260519_002"
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts/WT_D20260519_002")
OUTPUT_DIR <- file.path(WT_DIR, "output")
BTRES_DIR <- file.path(WT_DIR, "backtest_result")
JUDGE_DIR <- file.path(WT_DIR, "judge_ready")

dir.create(OUTPUT_DIR, showWarnings=FALSE, recursive=TRUE)
dir.create(BTRES_DIR, showWarnings=FALSE, recursive=TRUE)
dir.create(JUDGE_DIR, showWarnings=FALSE, recursive=TRUE)

LOG_FILE <- file.path(OUTPUT_DIR, "run_log.txt")
log_msg <- function(...) {
  msg <- paste0("[", format(Sys.time(), "%H:%M:%S"), "] ", paste0(...))
  cat(msg, "\n")
  cat(msg, "\n", file=LOG_FILE, append=TRUE)
}

cat("", file=LOG_FILE)
log_msg("=== Forge Stage Start: ", WT_ID, " ===")
log_msg("Working dir: ", WT_DIR)

# --- Start hash record (Pure Function audit) ---
pkg_files <- c("alpha_package.json", "risk_package.json", "optimization_package.json")
start_hash <- sapply(pkg_files, function(f) {
  fp <- file.path(WT_DIR, f)
  if(file.exists(fp)) digest::digest(file=fp, algo="md5") else "MISSING"
})
log_msg("Start hash: ", paste0(names(start_hash), "=", start_hash, collapse="; "))

# ============================================================================
# STAGE 1: PIT-clean feature panel build (~5800 daily obs 2004-02 ~ 2026-04)
# ============================================================================
log_msg("--- STAGE 1: PIT feature panel build ---")

# Load FRED macro (wide format)
fred <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/fred_macro_wide.parquet")))
fred[, Date := as.Date(Date)]
setorder(fred, Date)
log_msg("FRED loaded: nrow=", nrow(fred), " ncol=", ncol(fred),
        " range=", as.character(min(fred$Date)), "~", as.character(max(fred$Date)))

# Load rawdata for BM_Ret + investor flow + Sector
rawdata <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/rawdata.parquet")))
rawdata[, Date := as.Date(Date)]
# KOSPI200 daily benchmark return for F14, F17
bm_daily <- unique(rawdata[!is.na(BM_Ret), .(Date, BM_Ret)])
setorder(bm_daily, Date)
log_msg("BM daily loaded: nrow=", nrow(bm_daily),
        " range=", as.character(min(bm_daily$Date)), "~", as.character(max(bm_daily$Date)))

# --- Daily date spine 2004-01-01 ~ 2026-05-15 ---
date_spine <- data.table(Date = seq.Date(as.Date("2004-01-01"), as.Date("2026-05-15"), by="day"))
date_spine <- date_spine[Date %in% bm_daily$Date]  # trading days only
log_msg("Date spine (trading days only): nrow=", nrow(date_spine))

# Merge FRED + BM
panel <- merge(date_spine, fred, by="Date", all.x=TRUE)
panel <- merge(panel, bm_daily, by="Date", all.x=TRUE)
# Forward-fill FRED (publish lag covered by t-1 shift later)
fred_cols <- setdiff(names(fred), "Date")
for(col in fred_cols) {
  setnafill(panel, type="locf", cols=col)
}
log_msg("Panel after FRED+BM merge + locf: nrow=", nrow(panel), " ncol=", ncol(panel))

# --- Build 21 dedicated features (PIT-strict, t-1 lag enforced) ---
# F01 US 10y-2y spread
panel[, F01_YC_US_10y_2y := shift(US_10Y_Yield - US_2Y_Yield, 1)]
# F02 US 10y-FF (3m proxy, DGS3MO not in cache)
panel[, F02_YC_US_10y_FF := shift(US_10Y_Yield - Fed_Funds_Rate, 1)]
# F03 US YC inv dummy (10y-2y < 0)
panel[, F03_YC_US_inv_dummy := shift(as.numeric((US_10Y_Yield - US_2Y_Yield) < 0), 1)]
# F05 YC slope dynamics 12m (252d) change
panel[, yc_spread := US_10Y_Yield - US_2Y_Yield]
panel[, F05_YC_slope_12m_chg := shift(yc_spread - shift(yc_spread, 252), 1)]
# F06 US Ind Prod 3m MoM
panel[, indprod_log := log(US_IndProd)]
panel[, F06_LEI_IndProd_3m := shift(indprod_log - shift(indprod_log, 63), 1)]
# F07 Housing Permits YoY
panel[, F07_LEI_Housing_yoy := shift(log(Housing_Permits) - shift(log(Housing_Permits), 252), 1)]
# F08 Initial Claims z52w
panel[, ic_z52 := (Init_Claims - frollmean(Init_Claims, 252)) / frollapply(Init_Claims, 252, sd)]
panel[, F08_LEI_InitClaims_z52w := shift(ic_z52, 1)]
# F09 UMich Sentiment z12m
panel[, um_z := (UMich_Sentiment - frollmean(UMich_Sentiment, 252)) / frollapply(UMich_Sentiment, 252, sd)]
panel[, F09_LEI_UMich_z12m := shift(um_z, 1)]
# F11 VIX level
panel[, F11_VIX_level := shift(VIX, 1)]
# F12 VIX z252d
panel[, vix_z := (VIX - frollmean(VIX, 252)) / frollapply(VIX, 252, sd)]
panel[, F12_VIX_z252d := shift(vix_z, 1)]
# F14 KOSPI realized vol 60d zscore
panel[, kospi_rv60 := frollapply(BM_Ret, 60, sd) * sqrt(252)]
panel[, kospi_rv60_z := (kospi_rv60 - frollmean(kospi_rv60, 252)) / frollapply(kospi_rv60, 252, sd)]
panel[, F14_KOSPI_RV60_z := shift(kospi_rv60_z, 1)]
# F17 KOSPI-USD correlation 60d (down-market focus) — use rolling cor as proxy
panel[, krw_ret := shift(KRW_USD, 0) / shift(KRW_USD, 1) - 1]
panel[, kospi_krw_cor60 := frollapply(.SD, 60, function(x) {
  if(any(is.na(x[,1]) | is.na(x[,2]))) return(NA_real_)
  suppressWarnings(cor(x[,1], x[,2], use="pairwise.complete.obs"))
}, .SDcols=c("BM_Ret","krw_ret"))]
# Simpler: rolling cor via zoo
panel[, F17_KOSPI_KRW_cor60 := shift(rollapplyr(
  as.matrix(.SD), width=60, FUN=function(m) {
    if(nrow(m) < 30 || any(!is.finite(m))) return(NA_real_)
    cor(m[,1], m[,2])
  }, by.column=FALSE, fill=NA_real_), 1),
  .SDcols=c("BM_Ret","krw_ret")]
panel[, kospi_krw_cor60 := NULL]
# F18 KRW_USD z252d
panel[, krw_z := (KRW_USD - frollmean(KRW_USD, 252)) / frollapply(KRW_USD, 252, sd)]
panel[, F18_KRW_USD_z252d := shift(krw_z, 1)]
# F19 KRW_USD vol 60d
panel[, F19_KRW_USD_vol60 := shift(frollapply(krw_ret, 60, sd) * sqrt(252), 1)]
# F20 NFCI (Chi Fed)
panel[, F20_NFCI := shift(Chi_Fin_Cond, 1)]
# F21 StL Fin Stress
panel[, F21_StL_FSI := shift(StL_Fin_Stress, 1)]
# F22 Bank Lending Std
panel[, F22_Bank_Lending_Std := shift(Bank_Lending_Std, 1)]
# F24 HY-IG spread
panel[, F24_HY_IG_spread := shift(HY_Spread - BBB_Spread, 1)]
# F31 Defensive vs Cyclical spread — build from rawdata Sector_Lv2
# Defensive: 가스/전기/유틸/통신/건강관리/식음료/담배. Cyclical: 자동차/조선/기계/반도체
DEFENSIVE_SECTORS <- c("가스","전기,전자","전기,유틸리티","통신서비스","건강관리장비,서비스",
                       "음식료품","담배","제약,바이오","유틸리티","전기유틸리티")
CYCLICAL_SECTORS <- c("자동차,부품","조선","기계","반도체","건설,건축제품,건축자재","기타자본재")
sec_ret <- rawdata[!is.na(Sector_Lv2) & !is.na(Ret) & K200 == 1,
                   .(sec_ret_mean = mean(Ret, na.rm=TRUE)),
                   by=.(Date, Sector_Lv2)]
def_ret <- sec_ret[Sector_Lv2 %in% DEFENSIVE_SECTORS, .(def_ret = mean(sec_ret_mean, na.rm=TRUE)), by=Date]
cyc_ret <- sec_ret[Sector_Lv2 %in% CYCLICAL_SECTORS, .(cyc_ret = mean(sec_ret_mean, na.rm=TRUE)), by=Date]
panel <- merge(panel, def_ret, by="Date", all.x=TRUE)
panel <- merge(panel, cyc_ret, by="Date", all.x=TRUE)
panel[, def_cum60 := frollsum(def_ret, 60)]
panel[, cyc_cum60 := frollsum(cyc_ret, 60)]
panel[, F31_DefVsCyc_spread := shift(def_cum60 - cyc_cum60, 1)]

# F32 Defensive rotation zscore 60d
panel[, def_cyc_chg := shift(F31_DefVsCyc_spread - shift(F31_DefVsCyc_spread, 60), 1)]
panel[, F32_DefRotation_z60d := (def_cyc_chg - frollmean(def_cyc_chg, 252)) /
       frollapply(def_cyc_chg, 252, sd)]

# Investor flow F29 (foreign net buy intensity)
# rawdata has Vol + Size + KQ150 — investor flow needs separate source.
# Check if available in factor_db_daily
fdb_files <- list.files(file.path(PROJ_ROOT, ".cache/factor_db_daily/"),
                       pattern="^fdb_daily_2024.*parquet$", full.names=TRUE)
if(length(fdb_files) > 0) {
  fdb_sample <- as.data.table(read_parquet(fdb_files[1]))
  log_msg("factor_db_daily 2024 sample cols (first 20): ",
          paste(head(names(fdb_sample), 20), collapse=", "))
}
# F29/F30 deferred (separate KRX foreign flow fetch required) — flag as Phase B
panel[, F29_Foreign_NetSell_z := NA_real_]
panel[, F30_Foreign_Reversal := NA_real_]

# Built-feature list
feature_cols <- c(
  "F01_YC_US_10y_2y", "F02_YC_US_10y_FF", "F03_YC_US_inv_dummy", "F05_YC_slope_12m_chg",
  "F06_LEI_IndProd_3m", "F07_LEI_Housing_yoy", "F08_LEI_InitClaims_z52w", "F09_LEI_UMich_z12m",
  "F11_VIX_level", "F12_VIX_z252d", "F14_KOSPI_RV60_z", "F17_KOSPI_KRW_cor60",
  "F18_KRW_USD_z252d", "F19_KRW_USD_vol60", "F20_NFCI", "F21_StL_FSI", "F22_Bank_Lending_Std",
  "F24_HY_IG_spread", "F31_DefVsCyc_spread", "F32_DefRotation_z60d"
)

# Restrict to 2004-02-01 onward (panel start mandate)
panel_built <- panel[Date >= as.Date("2004-02-01")]

# Drop rows with > 50% NA across features
n_features <- length(feature_cols)
panel_built[, n_na := rowSums(is.na(.SD)), .SDcols=feature_cols]
n_before <- nrow(panel_built)
panel_built <- panel_built[n_na <= n_features * 0.3]
n_after <- nrow(panel_built)
log_msg("Feature panel rows: ", n_before, " → ", n_after,
        " (dropped ", n_before - n_after, " with >30% NA)")

# Final feature panel
feat_panel <- panel_built[, c("Date", "BM_Ret", feature_cols), with=FALSE]

# Forward-fill remaining NA via locf
for(col in feature_cols) {
  setnafill(feat_panel, type="locf", cols=col)
}
# Then backward-fill the start
for(col in feature_cols) {
  setnafill(feat_panel, type="nocb", cols=col)
}
# Any leftover NA → median impute
for(col in feature_cols) {
  if(anyNA(feat_panel[[col]])) {
    med <- median(feat_panel[[col]], na.rm=TRUE)
    feat_panel[is.na(get(col)), (col) := med]
  }
}

# Compute label: bad_month = forward 1-month BM return < -5%
# Aggregate daily BM_Ret to monthly (by realized_ym)
feat_panel[, ym := format(Date, "%Y-%m")]
monthly_bm <- feat_panel[, .(monthly_ret = prod(1 + BM_Ret) - 1), by=ym]
# Forward shift: label at sig_date_t = month-end of M_t predicts M_{t+1}
monthly_bm[, ym_next := format(seq.Date(as.Date(paste0(ym[1], "-01")),
                                         by="month", length.out=.N+1)[-1], "%Y-%m"),
            .(seq_along(ym))]
# Simpler: shift monthly_ret forward 1 row to create target for previous month
setorder(monthly_bm, ym)
monthly_bm[, target_fwd_ret := shift(monthly_ret, -1)]
monthly_bm[, bad_label := as.integer(target_fwd_ret < -0.05)]
log_msg("Monthly aggregation: ", nrow(monthly_bm), " months; bad_label sum=",
        sum(monthly_bm$bad_label, na.rm=TRUE), " /", sum(!is.na(monthly_bm$bad_label)))

# Merge label back to daily panel
feat_panel <- merge(feat_panel, monthly_bm[, .(ym, bad_label, target_fwd_ret, monthly_ret)],
                    by="ym", all.x=TRUE)
setorder(feat_panel, Date)

# Save feature panel
write_parquet(feat_panel, file.path(OUTPUT_DIR, "feature_panel_daily.parquet"))
log_msg("Stage 1 done. Panel saved: feature_panel_daily.parquet ",
        "n=", nrow(feat_panel), " features_built=", length(feature_cols))

# ============================================================================
# STAGE 2: Walk-forward window split (W1~W5)
# ============================================================================
log_msg("--- STAGE 2: Walk-forward split ---")

# Per request.json: W1: 2015~2017, W2: 2018~2020, W3: 2021~2022, W4: 2023~2024, W5: 2025~2026
# But data starts 2004-02; use rolling expanding window for train, fixed window for test.
windows <- list(
  W1 = list(train_end="2014-12-31", test_start="2015-01-01", test_end="2017-12-31"),
  W2 = list(train_end="2017-12-31", test_start="2018-01-01", test_end="2020-12-31"),
  W3 = list(train_end="2020-12-31", test_start="2021-01-01", test_end="2022-12-31"),
  W4 = list(train_end="2022-12-31", test_start="2023-01-01", test_end="2024-12-31"),
  W5 = list(train_end="2024-12-31", test_start="2025-01-01", test_end="2026-04-30")
)
log_msg("5 walk-forward windows defined (expanding train + 2~3y test)")

# ============================================================================
# STAGE 3: 5-model ensemble train per window
# ============================================================================
log_msg("--- STAGE 3: 5-model ensemble train (Logistic L1 + xgboost + RF + lag-GLM + MarkovSwitching) ---")

# Helper: train one window
train_window <- function(fp, train_end, test_start, test_end, win_name) {
  tr <- fp[Date <= as.Date(train_end) & !is.na(bad_label)]
  te <- fp[Date >= as.Date(test_start) & Date <= as.Date(test_end) & !is.na(bad_label)]

  if(nrow(tr) < 100 || nrow(te) < 30) {
    log_msg(win_name, ": insufficient data train=", nrow(tr), " test=", nrow(te))
    return(NULL)
  }

  X_tr <- as.matrix(tr[, ..feature_cols])
  y_tr <- tr$bad_label
  X_te <- as.matrix(te[, ..feature_cols])
  y_te <- te$bad_label

  preds <- list()

  # M1: Logistic L1 (glmnet)
  fit_lr <- tryCatch({
    cv <- cv.glmnet(X_tr, y_tr, family="binomial", alpha=1, nfolds=5)
    p <- predict(cv, X_te, s="lambda.min", type="response")[,1]
    p
  }, error=function(e) {log_msg(win_name, " LR err: ", e$message); rep(0.5, nrow(te))})
  preds$logistic_l1 <- as.numeric(fit_lr)

  # M2: xgboost (LightGBM substitute)
  fit_xgb <- tryCatch({
    dtr <- xgb.DMatrix(X_tr, label=y_tr)
    bst <- xgb.train(
      params = list(objective="binary:logistic", eval_metric="auc", eta=0.05,
                    max_depth=4, subsample=0.8, colsample_bytree=0.8, verbosity=0),
      data = dtr, nrounds = 200,
      verbose=0
    )
    p <- predict(bst, X_te)
    p
  }, error=function(e) {log_msg(win_name, " XGB err: ", e$message); rep(0.5, nrow(te))})
  preds$xgboost <- as.numeric(fit_xgb)

  # M3: Random Forest (ranger)
  fit_rf <- tryCatch({
    df_tr <- data.frame(y=as.factor(y_tr), X_tr)
    df_te <- data.frame(X_te)
    rf <- ranger(y ~ ., data=df_tr, num.trees=500, probability=TRUE,
                 min.node.size=10, max.depth=10, num.threads=2)
    p <- predict(rf, df_te)$predictions[,2]
    p
  }, error=function(e) {log_msg(win_name, " RF err: ", e$message); rep(0.5, nrow(te))})
  preds$random_forest <- as.numeric(fit_rf)

  # M4: 5-lag GLM (LSTM substitute, sequential proxy)
  # Build 5-lag matrix
  build_lag_X <- function(d, n_lag=5) {
    M_full <- as.matrix(d[, ..feature_cols])
    n_obs <- nrow(M_full)
    cols_new <- list()
    for(L in 0:(n_lag-1)) {
      shifted <- rbind(matrix(NA, L, ncol(M_full)), M_full[seq_len(n_obs-L),])
      colnames(shifted) <- paste0(feature_cols, "_l", L)
      cols_new[[L+1]] <- shifted
    }
    Xlag <- do.call(cbind, cols_new)
    keep <- complete.cases(Xlag)
    list(X=Xlag[keep,], keep=keep)
  }
  lag_tr <- build_lag_X(tr)
  lag_te <- build_lag_X(te)
  fit_lag <- tryCatch({
    cv2 <- cv.glmnet(lag_tr$X, y_tr[lag_tr$keep], family="binomial", alpha=0.5, nfolds=5)
    p_full <- rep(0.5, nrow(te))
    p_full[lag_te$keep] <- predict(cv2, lag_te$X, s="lambda.min", type="response")[,1]
    p_full
  }, error=function(e) {log_msg(win_name, " LAG err: ", e$message); rep(0.5, nrow(te))})
  preds$lag_glm <- as.numeric(fit_lag)

  # M5: Markov Switching (depmixS4 2-state on F11_VIX + F20_NFCI + F21_StL_FSI proxy)
  # depmixS4 model the BM_Ret directly with state-dependent mean+var,
  # then use posterior P(state=high_vol) as bear probability proxy.
  fit_ms <- tryCatch({
    bm_tr <- tr$BM_Ret
    bm_tr <- bm_tr[!is.na(bm_tr)]
    mod <- depmix(BM_Ret ~ 1, data=data.frame(BM_Ret=bm_tr), nstates=2,
                  family=gaussian())
    set.seed(20260518)
    fitms <- depmixS4::fit(mod, verbose=FALSE)
    # State means
    pars <- getpars(fitms)
    # State 1 mean idx and state 2 mean idx
    # pars layout depends on depmix; alternate approach: predict states for test set
    # Use posterior() for full chain — extend with test set
    full_tr_te <- rbind(tr[, .(BM_Ret)], te[, .(BM_Ret)])
    mod_full <- depmix(BM_Ret ~ 1, data=as.data.frame(full_tr_te), nstates=2, family=gaussian())
    # Use train fit's parameters
    mod_full <- setpars(mod_full, getpars(fitms))
    # Compute Viterbi or posterior
    post <- posterior(mod_full, type="filtering")
    # Identify high-vol state (higher variance)
    bm_full <- as.numeric(c(tr$BM_Ret, te$BM_Ret))
    state_vars <- c(
      var(bm_full[post$state == 1], na.rm=TRUE),
      var(bm_full[post$state == 2], na.rm=TRUE)
    )
    high_vol_state <- which.max(state_vars)
    bear_prob_full <- post[, paste0("S", high_vol_state)]
    p_te <- tail(bear_prob_full, nrow(te))
    p_te
  }, error=function(e) {log_msg(win_name, " MS err: ", e$message); rep(0.5, nrow(te))})
  preds$markov_switch <- as.numeric(fit_ms)

  # Sanitize all predictions
  for(m in names(preds)) {
    preds[[m]][is.na(preds[[m]]) | !is.finite(preds[[m]])] <- 0.5
    preds[[m]] <- pmin(pmax(preds[[m]], 1e-6), 1 - 1e-6)
  }

  # Ensemble (simple average)
  ens <- Reduce("+", preds) / length(preds)

  # AUC per model
  auc_one <- function(pred, y) {
    if(length(unique(y)) < 2) return(NA_real_)
    # Mann-Whitney U via rank
    r <- rank(pred)
    n_pos <- sum(y == 1)
    n_neg <- sum(y == 0)
    auc <- (sum(r[y == 1]) - n_pos * (n_pos + 1) / 2) / (n_pos * n_neg)
    auc
  }
  brier_one <- function(pred, y) mean((pred - y)^2)

  aucs <- sapply(c(preds, list(ensemble=ens)), auc_one, y_te)
  briers <- sapply(c(preds, list(ensemble=ens)), brier_one, y_te)

  log_msg(win_name, " n_tr=", nrow(tr), " n_te=", nrow(te),
          " bad_te=", sum(y_te), " AUC ens=", round(aucs["ensemble"], 4),
          " Brier ens=", round(briers["ensemble"], 4))
  log_msg("  per-model AUC: ",
          paste0(names(aucs)[1:5], "=", round(aucs[1:5], 3), collapse=" "))

  list(
    win = win_name,
    test_dt = te$Date,
    test_label = y_te,
    preds = preds,
    ensemble = ens,
    aucs = aucs,
    briers = briers,
    n_tr = nrow(tr), n_te = nrow(te), n_bad_te = sum(y_te)
  )
}

# Run all windows
win_results <- list()
for(wn in names(windows)) {
  w <- windows[[wn]]
  win_results[[wn]] <- train_window(feat_panel, w$train_end, w$test_start, w$test_end, wn)
}

# Concatenate test-set predictions across windows
collect_dt <- rbindlist(lapply(names(win_results), function(wn) {
  r <- win_results[[wn]]
  if(is.null(r)) return(NULL)
  data.table(
    win = wn,
    Date = r$test_dt,
    bad_label = r$test_label,
    p_logistic_l1 = r$preds$logistic_l1,
    p_xgboost = r$preds$xgboost,
    p_random_forest = r$preds$random_forest,
    p_lag_glm = r$preds$lag_glm,
    p_markov_switch = r$preds$markov_switch,
    p_ensemble = r$ensemble
  )
}))

write_parquet(collect_dt, file.path(OUTPUT_DIR, "bear_prob_daily_walk_forward.parquet"))
log_msg("Stage 3 done. Test predictions saved: bear_prob_daily_walk_forward.parquet n=",
        nrow(collect_dt))

# AUC summary table
auc_summary <- data.table()
for(wn in names(win_results)) {
  r <- win_results[[wn]]
  if(is.null(r)) next
  auc_summary <- rbind(auc_summary, data.table(
    window = wn,
    n_test = r$n_te,
    n_bad = r$n_bad_te,
    auc_logistic_l1 = r$aucs["logistic_l1"],
    auc_xgboost = r$aucs["xgboost"],
    auc_random_forest = r$aucs["random_forest"],
    auc_lag_glm = r$aucs["lag_glm"],
    auc_markov_switch = r$aucs["markov_switch"],
    auc_ensemble = r$aucs["ensemble"],
    brier_ensemble = r$briers["ensemble"]
  ))
}
fwrite(auc_summary, file.path(OUTPUT_DIR, "auc_by_window.csv"))
log_msg("auc_by_window.csv saved")

# ============================================================================
# STAGE 4: bear_prob monthly aggregation (267 sig_date)
# ============================================================================
log_msg("--- STAGE 4: Monthly aggregation ---")

# Out-of-sample period only — 2015 ~ 2026-04
collect_dt[, ym := format(Date, "%Y-%m")]
monthly_bear <- collect_dt[, .(
  p_bad_max = max(p_ensemble, na.rm=TRUE),
  p_bad_mean = mean(p_ensemble, na.rm=TRUE),
  p_bad_last = tail(p_ensemble, 1),
  bad_label = max(bad_label, na.rm=TRUE),
  n_days = .N
), by=ym]
monthly_bear[, sig_date := as.Date(paste0(ym, "-01"))]
setorder(monthly_bear, sig_date)
fwrite(monthly_bear, file.path(OUTPUT_DIR, "bear_prob_monthly_oos.csv"))
log_msg("Monthly bear_prob (OOS): ", nrow(monthly_bear), " months 2015~2026")

# Bridge to full 267m schedule: 2004-02 ~ 2026-04
# IS portion (2004-02 ~ 2014-12) uses design-phase placeholder (regime mapping inherit)
overlay_csv <- file.path(STAGE_DIR, "overlay_schedule.csv")
overlay <- fread(overlay_csv)
overlay[, as_of_date := as.Date(as_of_date)]

# Map OOS empirical bear_prob to overlay schedule
overlay_with_emp <- copy(overlay)
overlay_with_emp[, sig_date := as_of_date]
overlay_with_emp <- merge(overlay_with_emp,
                          monthly_bear[, .(sig_date, p_bad_emp_max=p_bad_max,
                                          p_bad_emp_mean=p_bad_mean)],
                          by="sig_date", all.x=TRUE)

# Use max (more conservative) for β_bear empirical mapping
emp_p_to_bucket <- function(p) {
  fifelse(is.na(p), NA_character_,
    fifelse(p < 0.3, "lt_0_3",
      fifelse(p < 0.5, "0_3_to_0_5",
        fifelse(p < 0.7, "0_5_to_0_7", "gt_0_7"))))
}
emp_bucket_to_beta <- function(b) {
  fifelse(is.na(b), NA_real_,
    fifelse(b == "lt_0_3", 1.0,
      fifelse(b == "0_3_to_0_5", 0.7,
        fifelse(b == "0_5_to_0_7", 0.5, 0.3))))
}

overlay_with_emp[, p_bad_bucket_emp := emp_p_to_bucket(p_bad_emp_max)]
overlay_with_emp[, beta_bear_emp_raw := emp_bucket_to_beta(p_bad_bucket_emp)]
# OOS empirical (where available)
overlay_with_emp[, beta_bear_emp := beta_bear_emp_raw]
# Fall back to design-phase β_bear for IS portion
overlay_with_emp[is.na(beta_bear_emp), beta_bear_emp := beta_bear]

# Anti-flicker 1m persistence (same rule)
setorder(overlay_with_emp, as_of_date)
overlay_with_emp[, beta_bear_emp_prev := shift(beta_bear_emp, 1, fill=1.0)]
overlay_with_emp[, beta_bear_emp_smoothed := beta_bear_emp]
overlay_with_emp[seq_len(.N) > 1, beta_bear_emp_smoothed := fifelse(
  beta_bear_emp != beta_bear_emp_prev, beta_bear_emp_prev, beta_bear_emp
)]

write_parquet(overlay_with_emp, file.path(OUTPUT_DIR, "bear_prob_monthly_267m.parquet"))
log_msg("267m bridged schedule emit. OOS empirical rows=",
        sum(!is.na(overlay_with_emp$p_bad_emp_max)),
        " IS design-phase rows=", sum(is.na(overlay_with_emp$p_bad_emp_max)))

# ============================================================================
# STAGE 5: Path A + Path B backtest
# ============================================================================
log_msg("--- STAGE 5: Path A (DPL_KR_v3 inject design-phase) + Path B (5-layer overlay backtest) ---")

# Path A — DPL_KR_v3 inject ΔAUC: cross-WT empirical not available (WT-D20260519_001 lifecycle separate)
# Report design-phase delta_AUC_estimate based on OOS ensemble AUC quality + DPL_KR_v3 80-feature inherit
# This is design-phase only; actual integration test is WT-D20260519_001 Forge cycle binding
path_a <- list(
  status = "DESIGN_PHASE_ONLY",
  rationale = "DPL_KR_v3 (WT-D20260519_001) has independent Forge lifecycle. Integration test (re-train DPL_KR_v3 with bear_prob as 81st feature) is owned by WT_019_001 Forge cycle.",
  delta_auc_threshold = 0.05,
  oos_ensemble_auc_mean = mean(auc_summary$auc_ensemble, na.rm=TRUE),
  oos_ensemble_auc_each_window = as.list(setNames(auc_summary$auc_ensemble, auc_summary$window)),
  decision = "DEFER_TO_WT_019_001_FORGE_CYCLE_INTEGRATION_TEST"
)

# Path B — 5-layer overlay backtest using STR_1715 PG2 weights_267m_timeseries
log_msg("Path B backtest: STR_1715 PG2 base × m4 × β_AR × β_R05 × β_bear")

# Load STR_1715 PG2 weights schedule
str1715_weights <- fread(file.path(PROJ_ROOT,
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/weights_267m_timeseries.csv"))
str1715_weights[, as_of_date := as.Date(as_of_date)]

# Load STR_1715 alpha_scores (268m) for monthly NAV reconstruction
alpha_scores <- as.data.table(read_parquet(file.path(PROJ_ROOT,
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet")))
log_msg("STR_1715 alpha_scores: nrow=", nrow(alpha_scores), " cols=",
        paste(head(names(alpha_scores), 10), collapse=", "))

# Determine monthly BM (KOSPI200) returns from rawdata
bm_monthly <- bm_daily[, .(monthly_ret = prod(1 + BM_Ret) - 1), by=.(ym = format(Date, "%Y-%m"))]
bm_monthly[, sig_date := as.Date(paste0(ym, "-01"))]
setorder(bm_monthly, sig_date)

# For Path B NAV reconstruction we need STR_1715 base monthly returns (already in lineage).
# STR_1715 PG2 production has bt_result.rds with monthly returns. Try load.
str1715_bt_path <- file.path(PROJ_ROOT,
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/bt_result.rds")
if(file.exists(str1715_bt_path)) {
  str1715_bt <- readRDS(str1715_bt_path)
  log_msg("STR_1715 PG2 bt_result loaded. Components: ",
          paste(names(str1715_bt), collapse=", "))
  if("nav" %in% names(str1715_bt)) {
    log_msg("nav class=", class(str1715_bt$nav)[1], " length/n=",
            if(is.xts(str1715_bt$nav)) nrow(str1715_bt$nav) else length(str1715_bt$nav))
  }
} else {
  log_msg("STR_1715 bt_result.rds not found at ", str1715_bt_path)
  str1715_bt <- NULL
}

# Alternative: reconstruct STR_1715 base monthly returns from weights + alpha_scores
# Use base_str1715_weight = 1 (regime-untouched base) × benchmark BM_Ret as conservative proxy
# vs production weights × actual top-20 holdings.
# Best: read STR_1715 monthly_returns.csv if exist in production
str1715_ret_files <- list.files(file.path(PROJ_ROOT,
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/"),
  full.names=TRUE)
log_msg("STR_1715 production backtest files:\n", paste("  -", str1715_ret_files, collapse="\n"))

stage5_path_b_progress <- "path_b_data_assembly"

# Save Path A summary
writeLines(toJSON(path_a, auto_unbox=TRUE, pretty=TRUE),
           file.path(OUTPUT_DIR, "path_a_summary.json"))
log_msg("Path A design-phase summary saved")

# Save stage 5 progress (continue in next R block)
saveRDS(list(
  win_results=win_results,
  auc_summary=auc_summary,
  monthly_bear=monthly_bear,
  overlay_with_emp=overlay_with_emp,
  feature_cols=feature_cols,
  path_a=path_a,
  stage5_progress=stage5_path_b_progress
), file.path(OUTPUT_DIR, "stage_1_to_4_state.rds"))

log_msg("=== Stage 1~4 complete + Stage 5 Path A design-phase. Path B backtest continues. ===")

cat("\n[ENTERING STAGE 5 PATH B BACKTEST]\n")
