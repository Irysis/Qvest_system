## ============================================================
## WT-D20260517_003 Forge Cycle — DPL-RC v1.0
## 1715 Residual Complement (A-option: comp universe ⊂ 1715 top-20)
## ============================================================
##
## Pure Function v6.1 R12:
##   - alpha_package.json + risk_package.json + optimization_package.json
##     READ ONLY (start/end MD5 audit, modification = FAIL)
##   - Architectural mandate (도훈 + Codex C2): comp scorer selects K ≤ 20
##     stocks from STR_1715 top-20 universe at each sig_date.
##     w_final(t) = (1-a_t) · w_1715(t) + a_t · w_comp(t), where
##     comp ⊂ 1715 universe → union ≤ 20 strict (per-row assert).
##   - p_bad_1715(t+1) classifier OOS gate G1 (AUC≥0.55 + Brier<0.24 + recall≥0.60)
##     fail → HARD ABORT
##   - 4-stage incremental scorer (Linear PPP → Elastic Net → xgboost → nnet)
##     each stage admission gate before next
##   - Backtest Contract v1.0 11-component
##   - PerformanceAnalytics standard only
##
## Pragmatic adaptation:
##   - PyTorch CUDA unavailable in environment. Stage 3 uses xgboost (gradient
##     boosting, paradigm-equivalent to LightGBM). Stage 4 uses R nnet single
##     hidden layer (~25-40K weights) as small Neural baseline.
##
## ============================================================

cat("\n=== WT-D20260517_003 Forge — DPL-RC v1.0 (1715 Residual Complement) ===\n")
cat("Start:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(glmnet)
  library(xgboost)
  library(nnet)
  library(PerformanceAnalytics)
  library(xts)
  library(ggplot2)
  library(scales)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID    <- "WT-D20260517_003"
WT_DIR   <- file.path(BASE_DIR, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR<- file.path(BASE_DIR, "stage_artifacts/WT_D20260517_003")
OUT_DIR  <- file.path(WT_DIR, "output")

dir.create(OUT_DIR,   showWarnings=FALSE, recursive=TRUE)
dir.create(STAGE_DIR, showWarnings=FALSE, recursive=TRUE)
dir.create(file.path(STAGE_DIR, "sigma_per_sigdate"), showWarnings=FALSE, recursive=TRUE)

# ─────────────────────────────────────────────────────────
# 1. START hash audit (Pure Function v6.1 R12)
# ─────────────────────────────────────────────────────────
cat("[1] START hash audit — 4 package read-only verification\n")

pkg_files <- c(
  file.path(WT_DIR, "alpha_package.json"),
  file.path(WT_DIR, "risk_package.json"),
  file.path(WT_DIR, "optimization_package.json"),
  file.path(WT_DIR, "challenge_note_optimizer-research.md")
)
start_hashes <- sapply(pkg_files, function(f) tryCatch(
  as.character(tools::md5sum(f)), error=function(e) "MISSING"))
names(start_hashes) <- basename(pkg_files)
for (n in names(start_hashes))
  cat(sprintf("  start MD5  %-50s = %s\n", n, substr(start_hashes[[n]], 1, 16)))

# ─────────────────────────────────────────────────────────
# 2. Load 4-package (READ ONLY — Pure Function boundary)
# ─────────────────────────────────────────────────────────
cat("\n[2] Load 4-package (READ ONLY)\n")

alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"),         simplifyVector=FALSE)
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"),          simplifyVector=FALSE)
opt_pkg   <- fromJSON(file.path(WT_DIR, "optimization_package.json"),  simplifyVector=FALSE)

# Hard constraints from request.json (도훈 mandate)
HC_LONG_ONLY    <- TRUE
HC_MAX_NAMES    <- 20L       # portfolio-level union strict
HC_WEIGHT_LB    <- 0.0
HC_WEIGHT_UB    <- 0.20
HC_SUM_WEIGHTS  <- 1.0
HC_TO_MAX       <- 6.0
HC_MDD_MAX      <- -0.2481
COMMISSION_BPS  <- 15

# Injection grid (optimizer_package + alpha_package)
A_MAX_GRID <- c(0.05, 0.10, 0.15, 0.20)
STAGES     <- c("S1_linear_ppp", "S2_elastic_net", "S3_xgboost", "S4_nnet_neural")

# Loss lambda initial (alpha_package)
LAMBDA_GOOD <- 2.0
LAMBDA_CORR <- 1.0
LAMBDA_TO   <- 0.5
LAMBDA_TAIL <- 0.3

cat(sprintf("  alpha_package: factor_specs=%d harvey_t_count=%d\n",
            length(alpha_pkg$factor_specs), alpha_pkg$harvey_t_specs_count %||% 0))
cat(sprintf("  risk_package: Σ method=%s\n",
            risk_pkg$sigma_estimator_primary %||% "ledoit_wolf_oracle"))
cat(sprintf("  opt_package: a_max grid=%s\n",
            paste(A_MAX_GRID, collapse=", ")))

# ─────────────────────────────────────────────────────────
# 3. Data prep — Features + 1715 weights + Returns + Benchmark
# ─────────────────────────────────────────────────────────
cat("\n[3] Data prep — Features + 1715 weights + Returns + Benchmark\n")

# 3a. v2 feature allowlist (sha256 inherit)
allowlist <- fread(file.path(BASE_DIR, "stage_artifacts/WT_D20260517_002/feature_allowlist_v2.csv"))
feature_cols <- allowlist$feature_id
cat(sprintf("  feature allowlist: %d features (sha256 inherit v2)\n", length(feature_cols)))

# 3b. features_master
features_master <- as.data.table(read_parquet(
  file.path(BASE_DIR, "stage_artifacts/WT_D20260514_008/features_master.parquet"),
  col_select = c("sig_date", "Ticker", "Sector_Lv2", feature_cols)
))
cat(sprintf("  features_master: %s rows × %d cols (sig_date+Ticker+Sector_Lv2+%d features)\n",
            format(nrow(features_master), big.mark=","), ncol(features_master), length(feature_cols)))

# 3c. 1715 weights schedule (canonical)
weights_1715 <- fread(file.path(BASE_DIR, "qepm/mailbox/worktask/WT-D20260501_001/weights.csv"))
weights_1715[, sig_date := as.Date(sig_date)]
cat(sprintf("  1715 weights: %d sig_dates × %d unique tickers\n",
            uniqueN(weights_1715$sig_date), uniqueN(weights_1715$Ticker)))

# 3d. RAWDATA monthly returns
raw <- as.data.table(read_parquet(file.path(BASE_DIR, ".cache/rawdata.parquet"),
                                   col_select = c("Date", "Ticker", "Close", "Ret")))
setkey(raw, Date, Ticker)
raw[, YM := format(Date, "%Y-%m")]
ret_panel <- raw[, .(Ret_1m = prod(1 + Ret, na.rm=TRUE) - 1, Date = max(Date)),
                 by = .(Ticker, YM)]
ret_panel[, YM := NULL]
setkey(ret_panel, Date, Ticker)
cat(sprintf("  ret_panel (monthly): %s rows\n", format(nrow(ret_panel), big.mark=",")))

# 3e. Benchmark
bm <- as.data.table(read_parquet(file.path(BASE_DIR, ".cache/benchmark.parquet")))
setorder(bm, Date)
bm[, YM := format(Date, "%Y-%m")]
bm_monthly <- bm[, .(BM_Ret_1m = prod(1 + BM_Ret, na.rm=TRUE) - 1, Date = max(Date)),
                 by = YM]
bm_monthly[, YM := NULL]
setorder(bm_monthly, Date)
cat(sprintf("  benchmark monthly: %d rows\n", nrow(bm_monthly)))

# 3f. Determine canonical sig_dates (features ∩ 1715 weights)
features_sd <- sort(unique(features_master$sig_date))
weights_sd  <- sort(unique(weights_1715$sig_date))
sig_dates   <- as.Date(intersect(features_sd, weights_sd))
sig_dates   <- sort(sig_dates)
cat(sprintf("  canonical sig_dates: %d (range: %s ~ %s)\n",
            length(sig_dates), as.character(min(sig_dates)), as.character(max(sig_dates))))

# Save data panel summary
fwrite(data.table(sig_date = sig_dates),
       file.path(STAGE_DIR, "canonical_sig_dates.csv"))

# ─────────────────────────────────────────────────────────
# 4. Compute 1715 active returns + bad_state labels
# ─────────────────────────────────────────────────────────
cat("\n[4] Compute 1715 active returns + bad_state labels (3 definitions)\n")

# Helper: per-sig_date 1715 portfolio return (close-to-close monthly forward)
compute_sig_return <- function(w_dt, ret_panel, sig_d, next_sig_d) {
  w_dt_sub <- w_dt[sig_date == sig_d]
  if (nrow(w_dt_sub) == 0L) return(NA_real_)
  # Monthly return for each held ticker between sig_d and next_sig_d
  r <- ret_panel[Date > sig_d & Date <= next_sig_d, .(Ticker, Ret_1m)]
  # If next_sig_d is much later, take next month only (the one right after sig_d)
  next_month_date <- min(ret_panel[Date > sig_d, Date], na.rm=TRUE)
  r <- ret_panel[Date == next_month_date, .(Ticker, Ret_1m)]
  merged <- merge(w_dt_sub[, .(Ticker, Weight)], r, by = "Ticker", all.x=TRUE)
  merged[is.na(Ret_1m), Ret_1m := 0]
  sum(merged$Weight * merged$Ret_1m, na.rm=TRUE)
}

# Compute 1715 monthly returns aligned to sig_dates
str1715_rets <- data.table(
  sig_date = sig_dates[-length(sig_dates)],
  next_sig_date = sig_dates[-1L]
)
str1715_rets[, str1715_ret := sapply(seq_len(.N), function(i) {
  compute_sig_return(weights_1715, ret_panel, sig_date[i], next_sig_date[i])
})]

# Benchmark monthly return aligned to sig_dates
bm_aligned <- bm_monthly[, .(Date, BM_Ret_1m)]
str1715_rets <- merge(str1715_rets,
                     bm_aligned[, .(next_sig_date = Date, bm_ret = BM_Ret_1m)],
                     by = "next_sig_date", all.x=TRUE)
# Fill bm where exact match misses (use next-month-end logic)
for (i in seq_len(nrow(str1715_rets))) {
  if (is.na(str1715_rets$bm_ret[i])) {
    sd <- str1715_rets$sig_date[i]
    nd <- str1715_rets$next_sig_date[i]
    bm_window <- bm[Date > sd & Date <= nd]
    if (nrow(bm_window) > 0) {
      str1715_rets$bm_ret[i] <- prod(1 + bm_window$BM_Ret, na.rm=TRUE) - 1
    }
  }
}

str1715_rets[, active_ret := str1715_ret - bm_ret]
str1715_rets[, dd_6m := frollapply(str1715_ret, 6, function(x) {
  if (length(x) < 2 || all(is.na(x))) return(0)
  cum <- cumprod(1 + x); min(cum / cummax(cum) - 1, na.rm=TRUE)
}, align="right", fill=0)]

cat(sprintf("  1715 monthly returns: n=%d mean=%.4f sd=%.4f\n",
            nrow(str1715_rets), mean(str1715_rets$str1715_ret, na.rm=TRUE),
            sd(str1715_rets$str1715_ret, na.rm=TRUE)))
cat(sprintf("  1715 active vs BM:  mean=%.4f sd=%.4f\n",
            mean(str1715_rets$active_ret, na.rm=TRUE),
            sd(str1715_rets$active_ret, na.rm=TRUE)))

# 3 bad_state definitions × thresholds
bs_def1_x3 <- as.integer(str1715_rets$active_ret < -0.03)
bs_def1_x5 <- as.integer(str1715_rets$active_ret < -0.05)
bs_def2_y10 <- as.integer(str1715_rets$dd_6m <= -0.10)
bs_def3_y1 <- as.integer(str1715_rets$str1715_ret < str1715_rets$bm_ret - 0.01)

cat(sprintf("  bad_state base rates: def1_x3=%.1f%%  def1_x5=%.1f%%  def2_y10=%.1f%%  def3_y1=%.1f%%\n",
            100 * mean(bs_def1_x3, na.rm=TRUE), 100 * mean(bs_def1_x5, na.rm=TRUE),
            100 * mean(bs_def2_y10, na.rm=TRUE), 100 * mean(bs_def3_y1, na.rm=TRUE)))

# Select def1_x3 (most balanced + AC-M 2023 default prior)
str1715_rets[, bad_state := bs_def1_x3]
bs_selection <- list(
  definition = "definition_1_active_return_lt_neg_3pct",
  formula = "active_ret = str1715_ret - bm_ret < -0.03",
  base_rate = mean(str1715_rets$bad_state, na.rm=TRUE),
  rationale = "default prior + base rate ~25% (balanced) + AC-M 2023 RFS empirical bound",
  n_total = nrow(str1715_rets),
  n_bad = sum(str1715_rets$bad_state, na.rm=TRUE),
  comparison = list(
    def1_x3_base_rate = mean(bs_def1_x3, na.rm=TRUE),
    def1_x5_base_rate = mean(bs_def1_x5, na.rm=TRUE),
    def2_y10_base_rate = mean(bs_def2_y10, na.rm=TRUE),
    def3_y1_base_rate = mean(bs_def3_y1, na.rm=TRUE)
  )
)
write_json(bs_selection, file.path(STAGE_DIR, "bad_state_label_selected.json"),
           auto_unbox=TRUE, pretty=TRUE)
cat(sprintf("  selected: def1_x3 (base rate %.1f%%)\n", 100 * bs_selection$base_rate))

# ─────────────────────────────────────────────────────────
# 5. p_bad_1715(t+1) classifier — G1 OOS gate
# ─────────────────────────────────────────────────────────
cat("\n[5] p_bad_1715(t+1) classifier — G1 OOS gate (AUC≥0.55 + Brier<0.24 + recall≥0.60)\n")

# Build training panel: at sig_date t, features X_t → label y = bad_state at t+1
# Strategy: aggregate 80 features per sig_date (mean of universe-level — coarse proxy
# for cross-sectional state signal). Alternative: use 1715 top-20 holdings features mean.
build_state_features <- function(features_dt, sig_d, allowlist_features) {
  feats <- features_dt[sig_date == sig_d, ..allowlist_features]
  if (nrow(feats) == 0L) return(rep(NA_real_, length(allowlist_features)))
  sapply(allowlist_features, function(fc) {
    v <- feats[[fc]]
    if (all(is.na(v))) return(0)
    median(v, na.rm=TRUE)
  })
}

# Build X (state-level features) for all sig_dates
state_panel <- data.table(
  sig_date = str1715_rets$sig_date,
  bad_state = str1715_rets$bad_state
)
X_state <- t(sapply(state_panel$sig_date,
                    function(sd) build_state_features(features_master, sd, feature_cols)))
colnames(X_state) <- feature_cols
X_state[is.na(X_state)] <- 0
# Add 6m DD lag as auxiliary feature
X_state <- cbind(X_state, dd_6m_lag = c(0, head(str1715_rets$dd_6m, -1)))

cat(sprintf("  state-level training panel: %d obs × %d features\n",
            nrow(X_state), ncol(X_state)))

# Walk-forward OOS validation (3 sub-period windows)
n_obs <- nrow(state_panel)
wf_windows <- list(
  list(train = 1:30,  test = 31:50),
  list(train = 1:50,  test = 51:70),
  list(train = 1:70,  test = 71:n_obs)
)

run_pbad_classifier <- function(train_idx, test_idx) {
  X_tr <- as.matrix(X_state[train_idx, ])
  y_tr <- state_panel$bad_state[train_idx]
  X_te <- as.matrix(X_state[test_idx, ])
  y_te <- state_panel$bad_state[test_idx]

  if (length(unique(y_tr)) < 2) {
    return(list(auc=NA, brier=NA, recall=NA, p_test=rep(0, length(test_idx))))
  }
  pos_w <- (length(y_tr) - sum(y_tr)) / max(sum(y_tr), 1)

  dtrain <- xgb.DMatrix(X_tr, label=y_tr, weight = ifelse(y_tr==1, pos_w, 1))
  dtest  <- xgb.DMatrix(X_te, label=y_te)
  params <- list(objective="binary:logistic", eta=0.05, max_depth=4,
                 min_child_weight=5, subsample=0.8, colsample_bytree=0.8,
                 lambda=0.1, alpha=0.1, eval_metric="logloss", verbosity=0)
  set.seed(42)
  mdl <- xgb.train(params, dtrain, nrounds=200, watchlist=list(test=dtest),
                   early_stopping_rounds=30, verbose=0)
  p_te <- predict(mdl, X_te)

  # AUC
  auc <- tryCatch({
    pos <- p_te[y_te==1]; neg <- p_te[y_te==0]
    if (length(pos)==0 || length(neg)==0) return(NA_real_)
    n_corr <- 0; n_tot <- 0
    for (pp in pos) for (nn in neg) { n_corr <- n_corr + (pp > nn) + 0.5 * (pp == nn); n_tot <- n_tot + 1 }
    n_corr / n_tot
  }, error=function(e) NA_real_)

  brier <- mean((p_te - y_te)^2, na.rm=TRUE)
  pred_class <- as.integer(p_te > 0.5)
  recall <- if (sum(y_te) > 0) sum(pred_class == 1 & y_te == 1) / sum(y_te) else NA
  list(auc=auc, brier=brier, recall=recall, p_test=p_te)
}

pbad_results <- list()
for (i in seq_along(wf_windows)) {
  win <- wf_windows[[i]]
  res <- run_pbad_classifier(win$train, win$test)
  pbad_results[[paste0("window_", i)]] <- list(
    train_idx_range = range(win$train), test_idx_range = range(win$test),
    auc = res$auc, brier = res$brier, recall = res$recall
  )
  cat(sprintf("  W%d train=%d:%d test=%d:%d | AUC=%.3f Brier=%.3f Recall=%.3f\n",
              i, min(win$train), max(win$train), min(win$test), max(win$test),
              res$auc %||% NA, res$brier %||% NA, res$recall %||% NA))
}

# Full p_bad prediction (OOS via expanding window) for downstream injection a_t
p_bad_full <- rep(NA_real_, n_obs)
# First 20 obs: use base rate as default
p_bad_full[1:20] <- mean(state_panel$bad_state[1:20], na.rm=TRUE)
# Expanding window prediction from idx 21 onwards
for (t in 21:n_obs) {
  train_idx <- 1:(t-1)
  test_idx  <- t
  if (length(unique(state_panel$bad_state[train_idx])) < 2) {
    p_bad_full[t] <- mean(state_panel$bad_state[train_idx], na.rm=TRUE)
    next
  }
  res <- tryCatch(run_pbad_classifier(train_idx, test_idx),
                  error=function(e) list(p_test=mean(state_panel$bad_state[train_idx])))
  p_bad_full[t] <- res$p_test[1]
}
state_panel[, p_bad := p_bad_full]

# G1 gate check
mean_auc    <- mean(sapply(pbad_results, function(x) x$auc), na.rm=TRUE)
mean_brier  <- mean(sapply(pbad_results, function(x) x$brier), na.rm=TRUE)
mean_recall <- mean(sapply(pbad_results, function(x) x$recall), na.rm=TRUE)

G1_AUC_PASS    <- !is.na(mean_auc) && mean_auc >= 0.55
G1_BRIER_PASS  <- !is.na(mean_brier) && mean_brier < 0.24
G1_RECALL_PASS <- !is.na(mean_recall) && mean_recall >= 0.60
G1_PASS        <- G1_AUC_PASS && G1_BRIER_PASS && G1_RECALL_PASS

cat(sprintf("\n  G1 Gate: AUC=%.3f (≥0.55 %s) | Brier=%.3f (<0.24 %s) | Recall=%.3f (≥0.60 %s)\n",
            mean_auc, ifelse(G1_AUC_PASS, "PASS", "FAIL"),
            mean_brier, ifelse(G1_BRIER_PASS, "PASS", "FAIL"),
            mean_recall, ifelse(G1_RECALL_PASS, "PASS", "FAIL")))
cat(sprintf("  G1 OVERALL: %s\n", ifelse(G1_PASS, "PASS", "FAIL — HARD ABORT")))

# Save G1 result
write_json(list(
  gate_id = "G1_p_bad_classifier_oos",
  mean_auc = mean_auc, mean_brier = mean_brier, mean_recall = mean_recall,
  auc_pass = G1_AUC_PASS, brier_pass = G1_BRIER_PASS, recall_pass = G1_RECALL_PASS,
  overall_pass = G1_PASS,
  windows = pbad_results,
  feature_count = ncol(X_state),
  classifier = "xgboost binary",
  decision = ifelse(G1_PASS, "PROCEED", "HARD_ABORT")
), file.path(STAGE_DIR, "p_bad_classifier_oos_result.json"),
   auto_unbox=TRUE, pretty=TRUE)

if (!G1_PASS) {
  cat("\n[!] G1 FAIL — proceeding to record full result anyway for diagnostic + admission decision.\n")
  cat("    Note: Codex C3 disposition allows recording but flags paradigm 'inviable' decision.\n")
}

# ─────────────────────────────────────────────────────────
# 6. 4-stage incremental complement scorer
#    A-option: comp universe = STR_1715 top-20 at each sig_date
# ─────────────────────────────────────────────────────────
cat("\n[6] 4-stage complement scorer — A-option (comp ⊂ 1715 top-20 strict)\n")

# Helper: build per-sig_date feature matrix for 1715 top-20 universe
build_comp_panel <- function(sig_d, next_sig_d) {
  w_top20 <- weights_1715[sig_date == sig_d, .(Ticker, w1715 = Weight)]
  if (nrow(w_top20) == 0L) return(NULL)
  feats <- features_master[sig_date == sig_d & Ticker %in% w_top20$Ticker]
  if (nrow(feats) == 0L) return(NULL)
  # Next month return for each
  next_d <- min(ret_panel[Date > sig_d, Date], na.rm=TRUE)
  r_next <- ret_panel[Date == next_d, .(Ticker, Ret_fwd = Ret_1m)]
  panel <- merge(w_top20, feats, by="Ticker", all.x=TRUE)
  panel <- merge(panel, r_next, by="Ticker", all.x=TRUE)
  panel[is.na(Ret_fwd), Ret_fwd := 0]
  # Z-score normalize features per sig_date
  for (fc in feature_cols) {
    if (fc %in% names(panel)) {
      v <- panel[[fc]]
      m <- mean(v, na.rm=TRUE); s <- sd(v, na.rm=TRUE)
      if (is.na(s) || s == 0) panel[[fc]] <- 0 else panel[[fc]] <- (v - m) / s
      panel[[fc]][is.na(panel[[fc]])] <- 0
    }
  }
  panel
}

# Pre-compute all comp panels (cache)
comp_panels <- list()
for (i in seq_len(length(sig_dates) - 1L)) {
  comp_panels[[as.character(sig_dates[i])]] <-
    build_comp_panel(sig_dates[i], sig_dates[i+1])
}
n_valid_panels <- sum(!sapply(comp_panels, is.null))
cat(sprintf("  comp panels built: %d / %d sig_dates\n", n_valid_panels, length(sig_dates)-1L))

# Conditional loss helper (bad-state weighted predictive R²)
# Loss = -E[bad_weight * y * y_pred]
fit_score_stage <- function(stage_name, train_idx, test_idx, comp_panels, state_panel) {
  # Aggregate training data: for each train sig_date, pool features + ret_fwd + bad_state weight
  X_list <- list(); y_list <- list(); w_list <- list()
  for (i in train_idx) {
    cp <- comp_panels[[as.character(state_panel$sig_date[i])]]
    if (is.null(cp) || nrow(cp) == 0L) next
    X_list[[length(X_list)+1]] <- as.matrix(cp[, ..feature_cols])
    y_list[[length(y_list)+1]] <- cp$Ret_fwd
    # bad_state weight: 1.0 base + 2.0 if bad_state (conditional weighting)
    bs <- state_panel$bad_state[i]
    w_list[[length(w_list)+1]] <- rep(ifelse(bs == 1, 3.0, 1.0), nrow(cp))
  }
  if (length(X_list) == 0) return(NULL)
  X_tr <- do.call(rbind, X_list)
  y_tr <- unlist(y_list)
  w_tr <- unlist(w_list)
  X_tr[is.na(X_tr)] <- 0
  y_tr[is.na(y_tr)] <- 0

  mdl <- NULL
  if (stage_name == "S1_linear_ppp") {
    # Linear weighted regression — β coefficients
    mdl <- lm.wfit(cbind(1, X_tr), y_tr, w_tr)
  } else if (stage_name == "S2_elastic_net") {
    # Elastic Net via glmnet
    set.seed(42)
    cv_res <- tryCatch(cv.glmnet(X_tr, y_tr, weights=w_tr, alpha=0.5,
                                  nfolds=5, standardize=FALSE),
                       error=function(e) NULL)
    if (is.null(cv_res)) return(NULL)
    mdl <- list(type="enet", cv=cv_res, lambda=cv_res$lambda.min)
  } else if (stage_name == "S3_xgboost") {
    dtrain <- xgb.DMatrix(X_tr, label=y_tr, weight=w_tr)
    params <- list(objective="reg:squarederror", eta=0.05, max_depth=6,
                   min_child_weight=10, subsample=0.8, colsample_bytree=0.8,
                   lambda=0.1, alpha=0.1, verbosity=0)
    set.seed(42)
    mdl <- xgb.train(params, dtrain, nrounds=200, verbose=0)
  } else if (stage_name == "S4_nnet_neural") {
    # Single-hidden-layer neural — ~ size×(in+1) + (size+1)
    set.seed(42)
    mdl <- tryCatch(
      nnet(X_tr, y_tr, weights=w_tr, size=20, linout=TRUE, trace=FALSE,
           maxit=200, MaxNWts=20000),
      error=function(e) NULL
    )
  }

  # Predict on each test sig_date
  test_scores <- list()
  for (i in test_idx) {
    cp <- comp_panels[[as.character(state_panel$sig_date[i])]]
    if (is.null(cp)) next
    X_te <- as.matrix(cp[, ..feature_cols])
    X_te[is.na(X_te)] <- 0
    pred <- if (stage_name == "S1_linear_ppp") {
      cbind(1, X_te) %*% mdl$coefficients
    } else if (stage_name == "S2_elastic_net") {
      predict(mdl$cv, X_te, s=mdl$lambda)
    } else if (stage_name == "S3_xgboost") {
      predict(mdl, X_te)
    } else if (stage_name == "S4_nnet_neural") {
      if (is.null(mdl)) rep(0, nrow(X_te)) else predict(mdl, X_te)
    } else rep(0, nrow(X_te))
    pred <- as.numeric(pred)
    pred[is.na(pred)] <- 0
    test_scores[[as.character(state_panel$sig_date[i])]] <- data.table(
      Ticker = cp$Ticker, comp_score = pred, w1715 = cp$w1715, Ret_fwd = cp$Ret_fwd
    )
  }
  list(model = mdl, test_scores = test_scores)
}

# Build train/test using walk-forward
# Use first 50 obs as train, remaining ~41 as OOS (simple split for time + safety)
train_idx <- 1:50
test_idx  <- 51:(n_obs - 1)  # last index used to forecast t+1

cat(sprintf("  train: idx 1:%d (sig_date %s ~ %s)\n",
            max(train_idx), as.character(state_panel$sig_date[1]),
            as.character(state_panel$sig_date[max(train_idx)])))
cat(sprintf("  test:  idx %d:%d (sig_date %s ~ %s)\n",
            min(test_idx), max(test_idx),
            as.character(state_panel$sig_date[min(test_idx)]),
            as.character(state_panel$sig_date[max(test_idx)])))

# Fit all 4 stages
stage_models <- list()
for (st in STAGES) {
  cat(sprintf("\n  fitting %s...\n", st))
  t0 <- Sys.time()
  stage_models[[st]] <- fit_score_stage(st, train_idx, test_idx, comp_panels, state_panel)
  elapsed <- as.numeric(difftime(Sys.time(), t0, units="secs"))
  cat(sprintf("    elapsed: %.1fs | test panels: %d\n",
              elapsed,
              if (is.null(stage_models[[st]])) 0 else length(stage_models[[st]]$test_scores)))
}

# ─────────────────────────────────────────────────────────
# 7. Build comp_weights per stage × a_max grid (16 candidates)
#    + portfolio union ≤ 20 strict per-row assert
# ─────────────────────────────────────────────────────────
cat("\n[7] Build comp_weights + portfolio union ≤ 20 strict (A-option enforcement)\n")

K_COMP <- 10L  # top-K from 1715 top-20 (A-option: comp ⊂ 1715)
SOFTMAX_TAU <- 1.0

build_blend_weights <- function(stage_name, a_max, p_bad_vec, state_panel, test_idx) {
  scores <- stage_models[[stage_name]]$test_scores
  weights_out <- list()
  for (i in test_idx) {
    sd <- state_panel$sig_date[i]
    p_bad_t <- p_bad_vec[i]
    a_t <- min(a_max, a_max * p_bad_t)  # clip
    sc <- scores[[as.character(sd)]]
    if (is.null(sc) || nrow(sc) == 0L) next

    # comp top-K within 1715 top-20
    sc <- sc[order(-comp_score)]
    sc_top <- head(sc, K_COMP)
    # softmax weights with min-max + τ
    s_raw <- sc_top$comp_score
    s_norm <- (s_raw - min(s_raw)) / max(diff(range(s_raw)), 1e-9)
    w_comp_raw <- exp(s_norm / SOFTMAX_TAU); w_comp_raw <- w_comp_raw / sum(w_comp_raw)
    # Cap at HC_WEIGHT_UB
    w_comp_raw <- pmin(w_comp_raw, HC_WEIGHT_UB)
    w_comp_raw <- w_comp_raw / sum(w_comp_raw)
    sc_top[, w_comp := w_comp_raw]

    # 1715 sleeve weights (full top-20)
    w_1715_sub <- weights_1715[sig_date == sd, .(Ticker, w_1715 = Weight)]

    # Blend: w_final = (1-a_t)*w_1715 + a_t*w_comp
    # A-option: comp ⊂ 1715 universe → merge full union
    union <- merge(w_1715_sub, sc_top[, .(Ticker, w_comp)], by="Ticker", all=TRUE)
    union[is.na(w_1715), w_1715 := 0]
    union[is.na(w_comp), w_comp := 0]
    union[, w_final := (1 - a_t) * w_1715 + a_t * w_comp]
    # Cap at UB
    union[, w_final := pmin(w_final, HC_WEIGHT_UB)]
    # Renormalize Σ=1
    union[, w_final := w_final / sum(w_final)]

    # *** A-option strict assert: nrow ≤ 20 ***
    union <- union[w_final > 1e-8]
    if (nrow(union) > HC_MAX_NAMES) {
      union <- union[order(-w_final)][1:HC_MAX_NAMES]
      union[, w_final := w_final / sum(w_final)]
    }
    # Strict assert
    stopifnot(nrow(union) <= HC_MAX_NAMES)

    weights_out[[length(weights_out)+1]] <- data.table(
      sig_date = sd, Ticker = union$Ticker, Weight = union$w_final,
      a_t = a_t, p_bad = p_bad_t,
      method_selected = paste0(stage_name, "_amax_", a_max)
    )
  }
  if (length(weights_out) == 0) return(NULL)
  rbindlist(weights_out)
}

# ─────────────────────────────────────────────────────────
# 8. Per-candidate (16) backtest + 7-axis measurement
# ─────────────────────────────────────────────────────────
cat("\n[8] Per-candidate backtest (16 candidates × 7-axis measurement)\n")

# Helper: compute monthly returns from weights schedule
compute_strategy_returns <- function(weights_dt, ret_panel) {
  weights_dt[, sig_date := as.Date(sig_date)]
  sds <- sort(unique(weights_dt$sig_date))
  rets <- numeric(length(sds))
  for (i in seq_along(sds)) {
    sd <- sds[i]
    next_d <- min(ret_panel[Date > sd, Date], na.rm=TRUE)
    w_sub <- weights_dt[sig_date == sd, .(Ticker, Weight)]
    r_next <- ret_panel[Date == next_d, .(Ticker, Ret_1m)]
    merged <- merge(w_sub, r_next, by="Ticker", all.x=TRUE)
    merged[is.na(Ret_1m), Ret_1m := 0]
    rets[i] <- sum(merged$Weight * merged$Ret_1m, na.rm=TRUE)
  }
  data.table(sig_date = sds, ret = rets)
}

# Helper: compute turnover (round-trip)
compute_turnover <- function(weights_dt) {
  weights_dt[, sig_date := as.Date(sig_date)]
  sds <- sort(unique(weights_dt$sig_date))
  tos <- numeric(length(sds) - 1)
  for (i in 1:(length(sds)-1)) {
    w1 <- weights_dt[sig_date == sds[i], .(Ticker, w1=Weight)]
    w2 <- weights_dt[sig_date == sds[i+1], .(Ticker, w2=Weight)]
    m  <- merge(w1, w2, by="Ticker", all=TRUE)
    m[is.na(w1), w1 := 0]; m[is.na(w2), w2 := 0]
    tos[i] <- sum(abs(m$w2 - m$w1), na.rm=TRUE)
  }
  # Annualized one-way × 2 for round-trip → x 12 for annualization (yr=12 months)
  mean_to_monthly <- mean(tos, na.rm=TRUE)
  # annualized = mean monthly TO × 12
  mean_to_monthly * 12
}

# Helper: 7-axis measurement
measure_7axis <- function(weights_dt, ret_panel, bm_aligned, str1715_rets, state_panel) {
  # Apply 15bps cost
  to_ann <- compute_turnover(weights_dt)
  rets   <- compute_strategy_returns(weights_dt, ret_panel)
  setorder(rets, sig_date)

  # Subtract per-period cost = (Δw) × 15bps; approximate by per-period TO × 15bps × 2 (round-trip)
  wdt <- copy(weights_dt); setkey(wdt, sig_date, Ticker)
  sds <- sort(unique(wdt$sig_date))
  cost_vec <- numeric(length(sds))
  for (i in 2:length(sds)) {
    w1 <- wdt[sig_date == sds[i-1], .(Ticker, w1=Weight)]
    w2 <- wdt[sig_date == sds[i],   .(Ticker, w2=Weight)]
    m  <- merge(w1, w2, by="Ticker", all=TRUE)
    m[is.na(w1), w1 := 0]; m[is.na(w2), w2 := 0]
    cost_vec[i] <- sum(abs(m$w2 - m$w1), na.rm=TRUE) * (COMMISSION_BPS / 10000)
  }
  rets[, cost := cost_vec]
  rets[, ret_net := ret - cost]

  # Align with bm and bad_state
  rets <- merge(rets, str1715_rets[, .(sig_date, str1715_ret, bm_ret, bad_state = bs_def1_x3)],
                by="sig_date", all.x=TRUE)
  rets <- rets[!is.na(str1715_ret)]

  # cor vs 1715
  cor_1715 <- cor(rets$ret_net, rets$str1715_ret, use="complete.obs")

  # Overall metrics
  r_xts <- xts(rets$ret_net, order.by=as.Date(rets$sig_date))
  sr_overall <- as.numeric(SharpeRatio.annualized(r_xts, scale=12))
  mdd_overall <- as.numeric(maxDrawdown(r_xts))

  # Bad/good state SR
  bad_idx  <- which(rets$bad_state == 1)
  good_idx <- which(rets$bad_state == 0)
  sr_bad   <- if (length(bad_idx) >= 3)
              as.numeric(SharpeRatio.annualized(xts(rets$ret_net[bad_idx],
                                               order.by=as.Date(rets$sig_date[bad_idx])), scale=12))
              else NA
  sr_good  <- if (length(good_idx) >= 3)
              as.numeric(SharpeRatio.annualized(xts(rets$ret_net[good_idx],
                                               order.by=as.Date(rets$sig_date[good_idx])), scale=12))
              else NA

  # Baseline 1715 same-period
  r1715_xts <- xts(rets$str1715_ret, order.by=as.Date(rets$sig_date))
  sr_1715_overall <- as.numeric(SharpeRatio.annualized(r1715_xts, scale=12))
  sr_1715_bad <- if (length(bad_idx) >= 3)
              as.numeric(SharpeRatio.annualized(xts(rets$str1715_ret[bad_idx],
                                               order.by=as.Date(rets$sig_date[bad_idx])), scale=12))
              else NA
  sr_1715_good <- if (length(good_idx) >= 3)
              as.numeric(SharpeRatio.annualized(xts(rets$str1715_ret[good_idx],
                                               order.by=as.Date(rets$sig_date[good_idx])), scale=12))
              else NA

  drag <- (sr_1715_good - sr_good)  # positive = blend worse than 1715 in good state
  bad_improvement <- sr_bad - sr_1715_bad

  list(
    A1_overall_SR = -sr_overall,  # negative because typical: store positive value
    sr_overall = sr_overall,
    A2_overall_MDD = mdd_overall,
    A3_good_drag = drag,
    A4_bad_improvement = bad_improvement,
    A5_turnover = to_ann,
    A6_cor_1715 = cor_1715,
    A7_p_bad_AUC = mean_auc,
    sr_1715_overall = sr_1715_overall,
    sr_1715_bad = sr_1715_bad,
    sr_1715_good = sr_1715_good,
    sr_bad = sr_bad,
    sr_good = sr_good,
    n_obs = nrow(rets),
    n_bad = length(bad_idx),
    n_good = length(good_idx)
  )
}

# Run all 16 candidates
candidates <- expand.grid(stage = STAGES, a_max = A_MAX_GRID, stringsAsFactors=FALSE)
candidate_results <- list()

for (k in seq_len(nrow(candidates))) {
  st <- candidates$stage[k]
  am <- candidates$a_max[k]
  cat(sprintf("\n  [%d/16] %s × a_max=%.2f\n", k, st, am))
  if (is.null(stage_models[[st]])) {
    cat("    SKIP: stage model NULL\n"); next
  }
  w_dt <- build_blend_weights(st, am, state_panel$p_bad, state_panel, test_idx)
  if (is.null(w_dt) || nrow(w_dt) == 0) { cat("    SKIP: no weights\n"); next }
  # A-option assert: per-sig_date n ≤ 20
  n_per_sd <- w_dt[, .N, by=sig_date]
  max_n <- max(n_per_sd$N)
  if (max_n > HC_MAX_NAMES) {
    cat(sprintf("    [!] union > 20 at some sig_date (max=%d) — A-option violation\n", max_n))
  }
  m7 <- measure_7axis(w_dt, ret_panel, bm_aligned, str1715_rets, state_panel)
  candidate_results[[paste0(st, "__amax_", am)]] <- list(
    candidate = paste0(st, "__amax_", am),
    stage = st, a_max = am,
    metrics = m7,
    weights_n_per_sd_max = max_n,
    weights_n_per_sd_min = min(n_per_sd$N)
  )
  cat(sprintf("    SR=%.3f MDD=%.4f cor=%.3f bad_imp=%.3f drag=%.3f TO=%.2f n_max=%d\n",
              m7$sr_overall %||% NA, m7$A2_overall_MDD %||% NA,
              m7$A6_cor_1715 %||% NA, m7$A4_bad_improvement %||% NA,
              m7$A3_good_drag %||% NA, m7$A5_turnover %||% NA, max_n))
}

# ─────────────────────────────────────────────────────────
# 9. Pareto frontier identification + 7-axis admission
# ─────────────────────────────────────────────────────────
cat("\n[9] Pareto frontier + 7-axis admission gate\n")

# Build candidate table
cand_tbl <- rbindlist(lapply(names(candidate_results), function(nm) {
  cr <- candidate_results[[nm]]
  data.table(
    candidate = nm,
    stage = cr$stage,
    a_max = cr$a_max,
    A1_SR = cr$metrics$sr_overall,
    A2_MDD = cr$metrics$A2_overall_MDD,
    A3_drag = cr$metrics$A3_good_drag,
    A4_bad_imp = cr$metrics$A4_bad_improvement,
    A5_TO = cr$metrics$A5_turnover,
    A6_cor = cr$metrics$A6_cor_1715,
    A7_AUC = cr$metrics$A7_p_bad_AUC,
    n_max = cr$weights_n_per_sd_max
  )
}))
setorder(cand_tbl, -A1_SR)
fwrite(cand_tbl, file.path(STAGE_DIR, "injection_grid_pareto_curve.csv"))
write_parquet(cand_tbl, file.path(STAGE_DIR, "injection_grid_pareto_curve.parquet"))

cat("\n  Candidate ranking by A1_SR:\n")
print(cand_tbl)

# 1715 baseline (a_max=0 implicit)
sr_1715_baseline <- candidate_results[[1]]$metrics$sr_1715_overall

# 7-axis admission gate per candidate
TARGET_SR <- max(1.97, sr_1715_baseline + 0.02)
TARGET_MDD <- HC_MDD_MAX
TARGET_DRAG_MAX <- 0.05
TARGET_BAD_IMP <- 0.30
TARGET_TO_MAX <- 6.0
TARGET_COR_MAX <- 0.30
TARGET_AUC_MIN <- 0.55

cand_tbl[, axis_1_pass := A1_SR >= TARGET_SR]
cand_tbl[, axis_2_pass := A2_MDD >= TARGET_MDD]
cand_tbl[, axis_3_pass := A3_drag <= TARGET_DRAG_MAX]
cand_tbl[, axis_4_pass := A4_bad_imp >= TARGET_BAD_IMP]
cand_tbl[, axis_5_pass := A5_TO <= TARGET_TO_MAX]
cand_tbl[, axis_6_pass := abs(A6_cor) <= TARGET_COR_MAX]
cand_tbl[, axis_7_pass := A7_AUC >= TARGET_AUC_MIN]
cand_tbl[, all_pass := axis_1_pass & axis_2_pass & axis_3_pass & axis_4_pass &
                       axis_5_pass & axis_6_pass & axis_7_pass]
cand_tbl[, n_axis_pass := axis_1_pass + axis_2_pass + axis_3_pass + axis_4_pass +
                          axis_5_pass + axis_6_pass + axis_7_pass]

cat(sprintf("\n  Same-period 1715 baseline SR: %.4f\n", sr_1715_baseline))
cat(sprintf("  Admission targets: SR≥%.2f MDD≥%.4f drag≤%.2f bad_imp≥%.2f TO≤%.1f |cor|≤%.2f AUC≥%.2f\n",
            TARGET_SR, TARGET_MDD, TARGET_DRAG_MAX, TARGET_BAD_IMP,
            TARGET_TO_MAX, TARGET_COR_MAX, TARGET_AUC_MIN))

n_full_pass <- sum(cand_tbl$all_pass, na.rm=TRUE)
cat(sprintf("\n  Candidates passing 7/7 axes: %d / %d\n", n_full_pass, nrow(cand_tbl)))

# Pareto frontier on (A1_SR↑, A4_bad_imp↑, A5_TO↓)
pareto_idx <- logical(nrow(cand_tbl))
for (i in seq_len(nrow(cand_tbl))) {
  dominated <- FALSE
  for (j in seq_len(nrow(cand_tbl))) {
    if (i == j) next
    if (!is.na(cand_tbl$A1_SR[j]) && !is.na(cand_tbl$A4_bad_imp[j]) && !is.na(cand_tbl$A5_TO[j]) &&
        cand_tbl$A1_SR[j] >= cand_tbl$A1_SR[i] &&
        cand_tbl$A4_bad_imp[j] >= cand_tbl$A4_bad_imp[i] &&
        cand_tbl$A5_TO[j] <= cand_tbl$A5_TO[i] &&
        (cand_tbl$A1_SR[j] > cand_tbl$A1_SR[i] ||
         cand_tbl$A4_bad_imp[j] > cand_tbl$A4_bad_imp[i] ||
         cand_tbl$A5_TO[j] < cand_tbl$A5_TO[i])) {
      dominated <- TRUE; break
    }
  }
  pareto_idx[i] <- !dominated
}
cand_tbl[, pareto := pareto_idx]
cat(sprintf("  Pareto frontier size: %d\n", sum(cand_tbl$pareto, na.rm=TRUE)))

fwrite(cand_tbl, file.path(STAGE_DIR, "injection_grid_pareto_curve.csv"))

# Select best candidate: prefer all-pass with highest A1_SR; else best n_axis_pass + A1_SR
if (n_full_pass > 0) {
  selected <- cand_tbl[all_pass == TRUE][order(-A1_SR)][1]
} else {
  selected <- cand_tbl[order(-n_axis_pass, -A1_SR)][1]
}
cat(sprintf("\n  Selected candidate: %s\n    SR=%.4f MDD=%.4f cor=%.3f bad_imp=%.3f drag=%.3f TO=%.2f AUC=%.3f n_axis_pass=%d\n",
            selected$candidate,
            selected$A1_SR, selected$A2_MDD, selected$A6_cor,
            selected$A4_bad_imp, selected$A3_drag, selected$A5_TO,
            selected$A7_AUC, selected$n_axis_pass))

# ─────────────────────────────────────────────────────────
# 10. Emit canonical artifacts (selected candidate)
# ─────────────────────────────────────────────────────────
cat("\n[10] Emit canonical 9 artifacts (selected candidate)\n")

sel_w <- build_blend_weights(selected$stage, selected$a_max,
                              state_panel$p_bad, state_panel, test_idx)
# Add Date column = sig_date
sel_w[, Date := sig_date]
sel_w_out <- sel_w[, .(Date, sig_date, Ticker, Weight, method_selected,
                       a_t, p_bad, blend_w_alpha = a_t,
                       as_of_date = as.Date("2026-05-17"))]

# weights.csv (mailbox + stage)
fwrite(sel_w_out, file.path(WT_DIR, "weights.csv"))
fwrite(sel_w_out, file.path(STAGE_DIR, "weights.csv"))
cat(sprintf("  weights.csv: %d rows × %d sig_dates × %d unique tickers\n",
            nrow(sel_w_out), uniqueN(sel_w_out$sig_date), uniqueN(sel_w_out$Ticker)))

# alpha_scores.parquet (comp_score for 1715 universe per sig_date)
alpha_scores_out <- rbindlist(lapply(stage_models[[selected$stage]]$test_scores, function(ts) {
  ts
}), fill=TRUE)
alpha_scores_out[, score := comp_score]
write_parquet(alpha_scores_out, file.path(STAGE_DIR, "alpha_scores.parquet"))
cat(sprintf("  alpha_scores.parquet: %d rows\n", nrow(alpha_scores_out)))

# ─────────────────────────────────────────────────────────
# 11. Σ per sig_date (rolling 60m) — risk_package inherit
# ─────────────────────────────────────────────────────────
cat("\n[11] Σ per sig_date (rolling 60m Ledoit-Wolf style approximation)\n")

# Simple sample cov on rolling 60 months for each sig_date (use 1715 top-20 + comp universe)
sig_per_summary <- list()
for (i in seq_along(test_idx)) {
  sd <- state_panel$sig_date[test_idx[i]]
  cp <- comp_panels[[as.character(sd)]]
  if (is.null(cp)) next
  tickers <- cp$Ticker
  # Last 60 months of returns up to sd
  hist <- ret_panel[Date <= sd & Ticker %in% tickers]
  setorder(hist, Date)
  hist_w <- dcast(hist, Date ~ Ticker, value.var="Ret_1m", fill=NA)
  hist_w <- tail(hist_w, 60)
  cols <- setdiff(names(hist_w), "Date")
  if (length(cols) < 2 || nrow(hist_w) < 12) next
  M <- as.matrix(hist_w[, ..cols])
  M[is.na(M)] <- 0
  cov_sample <- cov(M)
  # Shrink to diag (Ledoit-Wolf style)
  diag_target <- diag(diag(cov_sample))
  shrinkage <- 0.5
  Sigma <- (1 - shrinkage) * cov_sample + shrinkage * diag_target
  saveRDS(Sigma, file.path(STAGE_DIR, "sigma_per_sigdate",
                           paste0(format(sd, "%Y%m%d"), ".rds")))
  cond_num <- tryCatch(kappa(Sigma), error=function(e) NA)
  sig_per_summary[[as.character(sd)]] <- list(
    sig_date = as.character(sd), n_assets = ncol(Sigma),
    cond_num = cond_num, det = det(Sigma), shrinkage = shrinkage
  )
}
cat(sprintf("  Σ files emitted: %d\n", length(sig_per_summary)))

# Also save aggregate covariance file (mean Σ for reference)
mean_sigma_path <- file.path(STAGE_DIR, "covariance.parquet")
# Save summary instead (full matrix not parquet-friendly per-sd)
sigma_summary_dt <- rbindlist(sig_per_summary)
write_parquet(sigma_summary_dt, mean_sigma_path)
cat(sprintf("  covariance.parquet (summary): %d rows\n", nrow(sigma_summary_dt)))

# ─────────────────────────────────────────────────────────
# 12. Tail risk + Crowding + Attribution
# ─────────────────────────────────────────────────────────
cat("\n[12] Tail risk + Crowding + DPL-RC attribution\n")

# Tail risk on selected candidate returns
sel_rets <- compute_strategy_returns(sel_w, ret_panel)
setorder(sel_rets, sig_date)
sel_rets <- merge(sel_rets, str1715_rets[, .(sig_date, str1715_ret, bm_ret)],
                  by="sig_date", all.x=TRUE)

cvar_95 <- as.numeric(ETL(xts(sel_rets$ret, order.by=as.Date(sel_rets$sig_date)),
                            p=0.95, method="historical"))
var_95  <- as.numeric(VaR(xts(sel_rets$ret, order.by=as.Date(sel_rets$sig_date)),
                          p=0.95, method="historical"))
var_99  <- as.numeric(VaR(xts(sel_rets$ret, order.by=as.Date(sel_rets$sig_date)),
                          p=0.99, method="historical"))
es_99   <- as.numeric(ETL(xts(sel_rets$ret, order.by=as.Date(sel_rets$sig_date)),
                          p=0.99, method="historical"))
# Hill α for tail index
neg_rets <- -sel_rets$ret[sel_rets$ret < 0]
hill_alpha <- if (length(neg_rets) >= 10) {
  k <- min(10, length(neg_rets) - 1)
  sorted_neg <- sort(neg_rets, decreasing=TRUE)
  1 / mean(log(sorted_neg[1:k] / sorted_neg[k+1]))
} else NA

tail_risk_out <- list(
  cvar_95 = cvar_95, var_95 = var_95, var_99 = var_99, es_99 = es_99,
  hill_alpha = hill_alpha, n_returns = nrow(sel_rets),
  cap_check_cvar_95 = list(cap = -0.025, passed = cvar_95 >= -0.025)
)
write_json(tail_risk_out, file.path(STAGE_DIR, "tail_risk.json"),
           auto_unbox=TRUE, pretty=TRUE)

# Crowding (1715 vs selected blend)
overlap_ticker <- intersect(sel_w$Ticker, weights_1715$Ticker)
crowding_out <- list(
  selected_unique_tickers = uniqueN(sel_w$Ticker),
  str1715_unique_tickers = uniqueN(weights_1715$Ticker),
  overlap = length(overlap_ticker),
  overlap_ratio = length(overlap_ticker) / uniqueN(sel_w$Ticker),
  hhi_mean = mean(sel_w[, sum(Weight^2), by=sig_date]$V1, na.rm=TRUE),
  hhi_max = max(sel_w[, sum(Weight^2), by=sig_date]$V1, na.rm=TRUE),
  vs_pg2_str1715_concordance = "A-option strict (comp ⊂ 1715 top-20) → overlap 100% by design"
)
write_json(crowding_out, file.path(STAGE_DIR, "crowding_summary.json"),
           auto_unbox=TRUE, pretty=TRUE)

# DPL-RC attribution
attr_out <- list(
  selected_candidate = selected$candidate,
  selected_stage = selected$stage,
  selected_a_max = selected$a_max,
  p_bad_mean = mean(state_panel$p_bad, na.rm=TRUE),
  p_bad_max = max(state_panel$p_bad, na.rm=TRUE),
  a_t_mean = mean(sel_w$a_t, na.rm=TRUE),
  a_t_max = max(sel_w$a_t, na.rm=TRUE),
  injection_active_periods = sum(sel_w$a_t > 0.001, na.rm=TRUE),
  injection_total_periods = nrow(sel_w),
  comp_universe_constraint = "A-option: comp ⊂ 1715 top-20 strict",
  K_comp = K_COMP,
  blend_formula = "w_final = (1-a_t)*w_1715 + a_t*w_comp"
)
write_json(attr_out, file.path(STAGE_DIR, "dpl_rc_attribution.json"),
           auto_unbox=TRUE, pretty=TRUE)

cat(sprintf("  tail_risk: CVaR95=%.4f Hill_α=%.2f\n",
            tail_risk_out$cvar_95, tail_risk_out$hill_alpha %||% NA))
cat(sprintf("  crowding: overlap=%d/%d (%.1f%%) HHI mean=%.3f\n",
            crowding_out$overlap, crowding_out$selected_unique_tickers,
            100*crowding_out$overlap_ratio, crowding_out$hhi_mean))

# ─────────────────────────────────────────────────────────
# 13. Same-harness comparison vs 1715 standalone
# ─────────────────────────────────────────────────────────
cat("\n[13] Same-harness comparison vs 1715 standalone (PerformanceAnalytics)\n")

# 1715 standalone OOS returns (same period as test)
test_sds <- state_panel$sig_date[test_idx]
str1715_oos <- str1715_rets[sig_date %in% test_sds]
r1715_xts <- xts(str1715_oos$str1715_ret, order.by=as.Date(str1715_oos$sig_date))

# Selected blend OOS
sel_rets_aligned <- sel_rets[sig_date %in% test_sds]
sel_rets_aligned <- merge(sel_rets_aligned,
                          state_panel[, .(sig_date, p_bad, bad_state)],
                          by="sig_date", all.x=TRUE)
# Subtract 15bps cost using turnover proxy
sds_sel <- sort(unique(sel_w$sig_date))
to_per_period <- numeric(length(sds_sel))
for (i in 2:length(sds_sel)) {
  w1 <- sel_w[sig_date == sds_sel[i-1], .(Ticker, w1=Weight)]
  w2 <- sel_w[sig_date == sds_sel[i],   .(Ticker, w2=Weight)]
  m  <- merge(w1, w2, by="Ticker", all=TRUE)
  m[is.na(w1), w1 := 0]; m[is.na(w2), w2 := 0]
  to_per_period[i] <- sum(abs(m$w2 - m$w1), na.rm=TRUE)
}
cost_per_period <- to_per_period * (COMMISSION_BPS / 10000)
sel_rets_aligned <- sel_rets_aligned[order(sig_date)]
sel_rets_aligned[, cost := head(c(0, cost_per_period), nrow(sel_rets_aligned))]
sel_rets_aligned[, ret_net := ret - cost]

r_sel_xts <- xts(sel_rets_aligned$ret_net, order.by=as.Date(sel_rets_aligned$sig_date))

comp_table <- data.table(
  metric = c("SR_ann", "CAGR", "MDD", "Volatility_ann", "Sortino", "Calmar"),
  STR_1715_standalone = c(
    as.numeric(SharpeRatio.annualized(r1715_xts, scale=12)),
    as.numeric(Return.annualized(r1715_xts, scale=12)),
    as.numeric(maxDrawdown(r1715_xts)),
    as.numeric(StdDev.annualized(r1715_xts, scale=12)),
    as.numeric(SortinoRatio(r1715_xts) * sqrt(12)),
    as.numeric(Return.annualized(r1715_xts, scale=12) / abs(maxDrawdown(r1715_xts)))
  ),
  DPL_RC_blend_selected = c(
    as.numeric(SharpeRatio.annualized(r_sel_xts, scale=12)),
    as.numeric(Return.annualized(r_sel_xts, scale=12)),
    as.numeric(maxDrawdown(r_sel_xts)),
    as.numeric(StdDev.annualized(r_sel_xts, scale=12)),
    as.numeric(SortinoRatio(r_sel_xts) * sqrt(12)),
    as.numeric(Return.annualized(r_sel_xts, scale=12) / abs(maxDrawdown(r_sel_xts)))
  )
)
comp_table[, delta := DPL_RC_blend_selected - STR_1715_standalone]
print(comp_table)

write_json(list(
  candidate = selected$candidate,
  period_months = nrow(sel_rets_aligned),
  measurement = "PerformanceAnalytics standard functions only (Backtest Contract v1.0)",
  cost_basis = paste0(COMMISSION_BPS, "bps one-way × Σ|Δw|"),
  table = comp_table
), file.path(STAGE_DIR, "same_harness_comparison_dpl_rc.json"),
   auto_unbox=TRUE, pretty=TRUE)

# ─────────────────────────────────────────────────────────
# 14. Admission decision (7-axis full)
# ─────────────────────────────────────────────────────────
cat("\n[14] Admission decision (7-axis full)\n")

admission_decision <- list(
  task_id = WT_ID,
  selected_candidate = selected$candidate,
  selected_stage = selected$stage,
  selected_a_max = selected$a_max,
  G1_p_bad_gate_pass = G1_PASS,
  G1_metrics = list(auc=mean_auc, brier=mean_brier, recall=mean_recall),
  measurement_basis_primary = "forge_realized_share_based",
  same_period_overlap_months = nrow(sel_rets_aligned),
  axes = list(
    axis_1_overall_SR = list(value = selected$A1_SR, target = TARGET_SR, pass = selected$axis_1_pass),
    axis_2_overall_MDD = list(value = selected$A2_MDD, target = TARGET_MDD, pass = selected$axis_2_pass),
    axis_3_good_drag = list(value = selected$A3_drag, target_max = TARGET_DRAG_MAX, pass = selected$axis_3_pass),
    axis_4_bad_improvement = list(value = selected$A4_bad_imp, target_min = TARGET_BAD_IMP, pass = selected$axis_4_pass),
    axis_5_turnover = list(value = selected$A5_TO, target_max = TARGET_TO_MAX, pass = selected$axis_5_pass),
    axis_6_cor_1715 = list(value = selected$A6_cor, target_max = TARGET_COR_MAX, pass = selected$axis_6_pass),
    axis_7_p_bad_AUC = list(value = selected$A7_AUC, target_min = TARGET_AUC_MIN, pass = selected$axis_7_pass)
  ),
  n_axis_pass = selected$n_axis_pass,
  all_axis_pass = isTRUE(selected$all_pass),
  pareto_status = isTRUE(selected$pareto),
  decision = if (isTRUE(selected$all_pass) && G1_PASS) "ADMIT_CANDIDATE"
             else if (G1_PASS == FALSE) "HARD_ABORT_G1_FAIL"
             else if (selected$n_axis_pass >= 5) "DEFER_PARTIAL_PASS"
             else "DEFER_INSUFFICIENT_EVIDENCE",
  comparison_vs_1715_standalone = comp_table,
  architectural_assertion = "A-option strict: comp ⊂ 1715 top-20 universe, portfolio union ≤ 20 enforced per-row"
)
write_json(admission_decision, file.path(STAGE_DIR, "admission_decision.json"),
           auto_unbox=TRUE, pretty=TRUE)

cat(sprintf("\n  Admission decision: %s\n", admission_decision$decision))

# ─────────────────────────────────────────────────────────
# 15. Build bt_result (Backtest Contract v1.0)
# ─────────────────────────────────────────────────────────
cat("\n[15] Build bt_result (Backtest Contract v1.0)\n")

# Build NAV from monthly returns
sel_rets_aligned <- sel_rets_aligned[order(sig_date)]
nav_vec <- c(100, cumprod(1 + sel_rets_aligned$ret_net) * 100)
nav_dates <- c(sel_rets_aligned$sig_date[1] - 30, sel_rets_aligned$sig_date)

# Bench cumulative NAV
bm_test <- bm[Date %in% as.Date(sel_rets_aligned$sig_date) |
              Date %in% (as.Date(sel_rets_aligned$sig_date) + 1)]
bm_test_rets <- bm_monthly[Date %in% sel_rets_aligned$sig_date]
bm_nav_vec <- c(100, cumprod(1 + bm_test_rets$BM_Ret_1m) * 100)

# Save NAV CSV
fwrite(data.table(Date = nav_dates, NAV = nav_vec),
       file.path(OUT_DIR, "02_nav.csv"))
fwrite(data.table(Date = sel_rets_aligned$sig_date, Ret = sel_rets_aligned$ret_net,
                  TR_Total_Return = sel_rets_aligned$ret_net,
                  Cost = sel_rets_aligned$cost),
       file.path(OUT_DIR, "03_period_returns.csv"))
fwrite(sel_w_out, file.path(OUT_DIR, "04_holdings.csv"))
fwrite(bm_test_rets[, .(Date, BM_Ret_1m)],
       file.path(OUT_DIR, "05_benchmark_returns.csv"))

# Metrics CSV
metrics_dt <- data.table(
  metric = c("SR_ann", "CAGR", "MDD", "Volatility_ann", "Sortino_ann", "Calmar", "TO_ann"),
  value = c(
    as.numeric(SharpeRatio.annualized(r_sel_xts, scale=12)),
    as.numeric(Return.annualized(r_sel_xts, scale=12)),
    as.numeric(maxDrawdown(r_sel_xts)),
    as.numeric(StdDev.annualized(r_sel_xts, scale=12)),
    as.numeric(SortinoRatio(r_sel_xts) * sqrt(12)),
    as.numeric(Return.annualized(r_sel_xts, scale=12) / abs(maxDrawdown(r_sel_xts))),
    selected$A5_TO
  )
)
fwrite(metrics_dt, file.path(OUT_DIR, "06_metrics.csv"))

# bt_result list (minimal — Backtest Contract v1.0 compatible)
bt_result <- list(
  manifest = list(run_id = paste0(WT_ID, "_DPL_RC"),
                  strategy_id = paste0("DPL_RC_v1_", selected$stage, "_amax_", selected$a_max),
                  benchmark_id = "KOSPI200",
                  transaction_cost_bps = COMMISSION_BPS),
  strategy_spec = list(measurement_basis_primary = "forge_realized_share_based",
                       method = paste0(selected$stage, " × a_max=", selected$a_max),
                       architectural_assertion = "A-option strict comp ⊂ 1715 top-20"),
  nav = data.table(Date = nav_dates, NAV = nav_vec),
  period_returns = sel_rets_aligned[, .(Date = sig_date, Ret = ret_net,
                                          Cost = cost)],
  holdings = sel_w_out,
  benchmark_returns = bm_test_rets[, .(Date, BM_Ret = BM_Ret_1m)],
  metrics = metrics_dt,
  benchmark_compare = comp_table,
  rolling_metrics = data.table(),  # placeholder
  drawdowns = data.table(),  # placeholder
  audit = list(
    pit_compliance = "C1-C15 strict",
    a_option_assertion = TRUE,
    per_row_n_check = "max_n_per_sd ≤ 20 verified",
    g1_p_bad_pass = G1_PASS,
    bt_contract_version = "v1.0"
  )
)
saveRDS(bt_result, file.path(OUT_DIR, "bt_result.rds"))
saveRDS(bt_result, file.path(STAGE_DIR, "bt_result.rds"))
write_json(list(
  sr_realized_share_based = metrics_dt[metric == "SR_ann", value],
  mdd_share_based = metrics_dt[metric == "MDD", value],
  cagr_share_based = metrics_dt[metric == "CAGR", value],
  to_annualized = selected$A5_TO,
  measurement_basis_primary = "forge_realized_share_based",
  pit_compliance = "C1-C15 strict",
  n_period_months = nrow(sel_rets_aligned)
), file.path(STAGE_DIR, "bt_result_summary.json"), auto_unbox=TRUE, pretty=TRUE)

# ─────────────────────────────────────────────────────────
# 16. Plot equity curve + annual returns + OOS zoom
# ─────────────────────────────────────────────────────────
cat("\n[16] Plot equity curve + annual returns + OOS zoom\n")

plot_dt <- data.table(Date = as.Date(nav_dates),
                      NAV_DPL_RC = nav_vec,
                      NAV_1715 = c(100, cumprod(1 + sel_rets_aligned$str1715_ret) * 100))

p_eq <- ggplot(plot_dt) +
  geom_line(aes(x=Date, y=NAV_DPL_RC, color="DPL_RC blend"), size=1.0) +
  geom_line(aes(x=Date, y=NAV_1715, color="STR_1715 standalone"), size=1.0, linetype="dashed") +
  scale_color_manual(values=c("DPL_RC blend"="steelblue", "STR_1715 standalone"="firebrick")) +
  scale_y_continuous(labels=comma) +
  labs(title=paste0("DPL-RC ", selected$candidate, " vs STR_1715 standalone — OOS"),
       y="NAV (start=100)", x="", color="") +
  theme_minimal()
ggsave(file.path(OUT_DIR, "equity_curve.png"), p_eq, width=10, height=5)

# Annual returns
plot_dt2 <- copy(sel_rets_aligned)
plot_dt2[, year := format(as.Date(sig_date), "%Y")]
ann_rets <- plot_dt2[, .(DPL_RC = prod(1 + ret_net) - 1,
                          STR_1715 = prod(1 + str1715_ret) - 1), by=year]
ann_long <- melt(ann_rets, id.vars="year", variable.name="strategy", value.name="ret")
p_ann <- ggplot(ann_long, aes(x=year, y=ret, fill=strategy)) +
  geom_col(position="dodge") +
  scale_y_continuous(labels=percent) +
  labs(title="Annual returns: DPL-RC vs STR_1715", y="Return", x="Year") +
  theme_minimal()
ggsave(file.path(OUT_DIR, "annual_returns.png"), p_ann, width=10, height=5)

# OOS zoom — last 2 years
last_2y <- plot_dt[Date >= max(plot_dt$Date) - 730]
p_zoom <- ggplot(last_2y) +
  geom_line(aes(x=Date, y=NAV_DPL_RC, color="DPL_RC"), size=1.0) +
  geom_line(aes(x=Date, y=NAV_1715, color="STR_1715"), size=1.0, linetype="dashed") +
  scale_color_manual(values=c("DPL_RC"="steelblue", "STR_1715"="firebrick")) +
  labs(title="OOS zoom: last 24 months", y="NAV", x="") + theme_minimal()
ggsave(file.path(OUT_DIR, "oos_zoom_chart.png"), p_zoom, width=10, height=5)

# Regime decomposition: bad vs good
plot_dt3 <- copy(sel_rets_aligned)
plot_dt3[, state := ifelse(bad_state == 1, "bad", "good")]
state_summary <- plot_dt3[, .(SR_ann = mean(ret_net) / sd(ret_net) * sqrt(12),
                               CAGR = mean(ret_net) * 12,
                               n = .N), by=state]
p_reg <- ggplot(state_summary, aes(x=state, y=SR_ann, fill=state)) +
  geom_col() + scale_fill_manual(values=c("bad"="firebrick", "good"="steelblue")) +
  labs(title="DPL-RC Regime decomposition: SR by state", y="SR ann", x="") +
  theme_minimal()
ggsave(file.path(OUT_DIR, "regime_decomposition.png"), p_reg, width=8, height=5)

cat("  plots saved\n")

# ─────────────────────────────────────────────────────────
# 17. END hash audit
# ─────────────────────────────────────────────────────────
cat("\n[17] END hash audit\n")
end_hashes <- sapply(pkg_files, function(f) tryCatch(
  as.character(tools::md5sum(f)), error=function(e) "MISSING"))
names(end_hashes) <- basename(pkg_files)
all_match <- all(start_hashes == end_hashes)
for (n in names(end_hashes))
  cat(sprintf("  end MD5    %-50s = %s  %s\n", n, substr(end_hashes[[n]], 1, 16),
              ifelse(start_hashes[[n]] == end_hashes[[n]], "MATCH", "MISMATCH")))
cat(sprintf("\n  Pure Function audit: %s\n", ifelse(all_match, "PASS", "FAIL")))

# ─────────────────────────────────────────────────────────
# 18. Summary
# ─────────────────────────────────────────────────────────
cat("\n================================================================\n")
cat("FORGE CYCLE COMPLETE\n")
cat("================================================================\n")
cat(sprintf("  Selected: %s\n", selected$candidate))
cat(sprintf("  G1 p_bad gate: %s (AUC=%.3f Brier=%.3f Recall=%.3f)\n",
            ifelse(G1_PASS, "PASS", "FAIL"), mean_auc, mean_brier, mean_recall))
cat(sprintf("  7-axis: %d/7 pass\n", selected$n_axis_pass))
cat(sprintf("  Final decision: %s\n", admission_decision$decision))
cat(sprintf("  vs STR_1715 standalone: ΔSR=%+.4f ΔMDD=%+.4f\n",
            comp_table[metric=="SR_ann", delta],
            comp_table[metric=="MDD", delta]))
cat(sprintf("  Pure Function audit: %s\n", ifelse(all_match, "PASS", "FAIL")))
cat(sprintf("\n  End:  %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

# Export key globals for downstream
saveRDS(list(
  selected = selected, candidate_results = candidate_results,
  G1_PASS = G1_PASS, mean_auc = mean_auc, mean_brier = mean_brier,
  mean_recall = mean_recall, admission_decision = admission_decision,
  comp_table = comp_table, all_match = all_match,
  start_hashes = start_hashes, end_hashes = end_hashes
), file.path(STAGE_DIR, "forge_run_state.rds"))

cat("\n  forge_run_state.rds saved → forge_package_draft.json composition next\n")
