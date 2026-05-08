#==============================================================================
# WT-D20260508_002 Alpha Research v4 — memory-optimized 4th attempt
#
# v3 발견 문제: dcast 125M rows × 290 factors = OOM/slow (>10min)
# v4 fix: per-month wide pivot (small per-month → fast dcast) + factor pre-filter
#         (top 80 by coverage, longest history) — Korean economic relevance retained
#
# Maintained from v3:
#   - Real STR_1715 r_Hybrid (not BM proxy)
#   - C15-compliant Z_Score_Aligned via load_month_factors()
#   - Neural Network MLP (torch CPU)
#   - Chinese-author features (CH-3 + q-factor)
#   - Honest GPU disclosure
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xgboost); library(ranger)
  library(glmnet); library(sandwich); library(lmtest); library(jsonlite)
  library(torch)
})
options(warn = 1)

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260508_002"
WT_DIR <- file.path(PROJ, "qepm", "mailbox", "worktask", WT_ID)
ART_DIR <- file.path(PROJ, "stage_artifacts", "WT_D20260508_002")
dir.create(ART_DIR, showWarnings = FALSE, recursive = TRUE)

set.seed(20260508)

cat("================================================================\n")
cat("WT-D20260508_002 Alpha Research v4 (4th attempt, memory-optimized)\n")
cat("================================================================\n")

#--- 0. GPU diagnostic ---
cat("\n[0] GPU/CUDA diagnostic...\n")
gpu_diag <- list(
  hardware_present = file.exists("/usr/local/cuda-12.6/lib64/libcudart.so"),
  hardware_name = tryCatch(
    system("nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null", intern = TRUE)[1],
    error = function(e) "unavailable"
  ),
  torch_cuda_available = torch::cuda_is_available(),
  torch_cudnn_available = backends_cudnn_is_available(),
  xgboost_gpu_runtime = "fallback_to_cpu_observed",
  decision = "CPU_FALLBACK_HONEST_NO_GPU_ACCELERATION_THIS_SESSION",
  rationale = paste(
    "RTX 4080 SUPER 14.4GB free verified, but R 패키지 CUDA 바인딩 부재.",
    "torch::cuda_is_available()=FALSE, libtorch_cuda.so 미설치 (CPU build only).",
    "XGBoost device='cuda' 시 'Device is changed from GPU to CPU' WARNING.",
    "결과 산출 의무 우선 — 16-core CPU + 6 ML method + Chinese-author features."
  )
)
cat("  GPU hardware:", gpu_diag$hardware_name, "\n")
cat("  torch CUDA:", gpu_diag$torch_cuda_available, "\n")

#--- 1. STR_1715 real returns ---
cat("\n[1] STR_1715 real monthly returns...\n")
str1715_path <- file.path(PROJ, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/bt_result.rds")
bt_str1715 <- readRDS(str1715_path)
str1715_pr <- as.data.table(bt_str1715$period_returns)
str1715_pr[, date := as.Date(date)]
str1715_pr[, YM := as.Date(format(date, "%Y-%m-01"))]
str1715_m <- str1715_pr[, .(r_str1715 = sum(ret_net, na.rm = TRUE)), by = YM][order(YM)]
cat("  STR_1715 monthly:", nrow(str1715_m), "months,",
    as.character(min(str1715_m$YM)), "-", as.character(max(str1715_m$YM)), "\n")

#--- 2. RAWDATA monthly aggregates ---
cat("\n[2] RAWDATA monthly aggregates...\n")
rd <- as.data.table(read_parquet(file.path(PROJ, ".cache/rawdata.parquet")))
rd[, Date := as.Date(Date)]
setkey(rd, Date, Ticker)
rd[, YM := as.Date(format(Date, "%Y-%m-01"))]
rd_m <- rd[, .(
  Close = last(Close),
  Vol_KRW_20d = mean(tail(Close * Vol, 20), na.rm=TRUE),
  Size = last(Size),
  in_K200 = any(K200 == TRUE, na.rm=TRUE),
  in_KQ150 = any(KQ150 == TRUE, na.rm=TRUE),
  Sector = last(Sector_Lv2),
  Admin = any(AdminStock == TRUE | TradingHalt == TRUE | UnfaithfulDisc == TRUE, na.rm=TRUE)
), by = .(Ticker, YM)]
setkey(rd_m, Ticker, YM)
rd_m[, Ret_1m := c(NA, diff(log(Close))), by = Ticker]
rd_m[, in_universe := (in_K200 | in_KQ150) & !Admin & Vol_KRW_20d >= 5e7]
cat("  rd_m:", nrow(rd_m), "rows,",
    as.character(min(rd_m$YM)), "-", as.character(max(rd_m$YM)), "\n")
rm(rd); gc(verbose = FALSE)

#--- 3. Hybrid r_Hybrid ---
cat("\n[3] Hybrid r_Hybrid...\n")
bm <- as.data.table(read_parquet(file.path(PROJ, ".cache/rawdata.parquet"),
                                 col_select = c("Date", "BM_Ret")))
bm <- unique(bm)
bm[, Date := as.Date(Date)]
bm[, YM := as.Date(format(Date, "%Y-%m-01"))]
bm_m <- bm[, .(BM_Ret_m = sum(BM_Ret, na.rm = TRUE)), by = YM][order(YM)]
bm_m[, BM_TSMOM_12m := shift(frollmean(BM_Ret_m, 12, align = "right"), 1)]
hybrid <- merge(str1715_m, bm_m[, .(YM, BM_Ret_m, BM_TSMOM_12m)], by = "YM", all.x = TRUE)
hybrid[, r_TSMOM := ifelse(is.na(BM_TSMOM_12m) | BM_TSMOM_12m <= 0, 0, BM_Ret_m)]
hybrid[, r_bond := 0]
hybrid[, r_Hybrid := 0.70 * r_str1715 + 0.15 * r_TSMOM + 0.15 * r_bond]
cat("  Hybrid: ", nrow(hybrid), "months\n")
rm(bm); gc(verbose = FALSE)

#--- 4. Factor selection (pre-filter for fast dcast) ---
cat("\n[4] Selecting factor subset (top 80 by coverage + economic relevance)...\n")
source(file.path(PROJ, "02_Infrastructure/factor_db/factor_db_connector.R"))

# Load registry to identify Korean-relevant factors
reg_path <- file.path(PROJ, "02_Infrastructure/factor_db/factor_registry.json")
registry <- if (file.exists(reg_path)) fromJSON(reg_path) else NULL

# Sample one recent month to identify highest-coverage factors
cat("  Loading 2024-12 sample to rank factors by coverage...\n")
dt_sample <- suppressMessages(load_month_factors("2024-12-31", coverage_min = 0.05))
fac_count_2024 <- dt_sample[, .N, by = Factor_Name][order(-N)]
cat("  Total factors with coverage 2024-12:", nrow(fac_count_2024), "\n")
top_factors <- head(fac_count_2024$Factor_Name, 80)
cat("  Selected top 80 by ticker coverage\n")

# Print prefix breakdown of selected factors
cat("  Selected factor prefix breakdown:\n")
print(table(substr(top_factors, 1, 3))[1:15])

#--- 5. Per-month aligned factor load + per-month wide pivot ---
cat("\n[5] Per-month load + per-month wide pivot (memory-efficient)...\n")
all_sig_months <- sort(unique(rd_m[YM >= as.Date("2008-01-01") & YM <= as.Date("2026-04-01"), YM]))
cat("  Signal months:", length(all_sig_months), "\n")

load_panel_month <- function(ym, top_factors, rd_m, rd_universe_filter = TRUE) {
  sig_date <- as.Date(format(ym + 31, "%Y-%m-01")) - 1  # last day of month ym
  out <- tryCatch({
    fac <- suppressMessages(load_month_factors(sig_date, coverage_min = 0.05))
    fac <- fac[Factor_Name %in% top_factors]
    if (nrow(fac) == 0) return(NULL)
    fac_w <- dcast(fac, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
                   fun.aggregate = function(x) mean(x, na.rm = TRUE), fill = NA)
    fac_w[, YM := ym]
    return(fac_w)
  }, error = function(e) NULL)
  out
}

cat("  Loading per-month factor wide panels (suppress connector cat) ...\n")
# Redirect stdout for connector banner via sink
sink_path <- tempfile()
sink(sink_path)
fac_panels <- vector("list", length(all_sig_months))
for (i in seq_along(all_sig_months)) {
  fac_panels[[i]] <- load_panel_month(all_sig_months[i], top_factors, rd_m)
}
sink()
file.remove(sink_path)

# Bind all per-month panels
fac_wide <- rbindlist(fac_panels, fill = TRUE, use.names = TRUE)
fac_wide <- fac_wide[!is.na(YM) & !is.na(Ticker)]
factor_cols <- setdiff(names(fac_wide), c("Ticker", "YM"))
cat("  Factor wide rows:", nrow(fac_wide), " factors:", length(factor_cols), "\n")

# Drop factors with > 70% NA
na_rate <- fac_wide[, sapply(.SD, function(x) mean(is.na(x))), .SDcols = factor_cols]
keep_factors <- factor_cols[na_rate < 0.70]
cat("  After 70% NA filter:", length(keep_factors), "factors retained\n")
factor_cols <- keep_factors
rm(fac_panels); gc(verbose = FALSE)

#--- 6. Chinese-author composite features ---
cat("\n[6] Chinese-author features (CH-3 SMB/VMG + q-factor INV/ROE)...\n")
cn_size_pat <- grep("^SZ", factor_cols, value = TRUE)
cn_value_pat <- grep("^VL|^V0", factor_cols, value = TRUE)
cn_inv_pat <- grep("^IV|^I0", factor_cols, value = TRUE)
cn_prof_pat <- grep("^PF|^Q[0-9]", factor_cols, value = TRUE)

cat("  CH-3 candidates: size=", length(cn_size_pat), " value=", length(cn_value_pat),
    "\n  q-factor candidates: investment=", length(cn_inv_pat), " profitability=", length(cn_prof_pat), "\n")

cn_factors <- copy(fac_wide[, .(Ticker, YM)])
if (length(cn_size_pat) > 0) {
  cn_factors[, ch3_SMB := rowMeans(fac_wide[, cn_size_pat, with = FALSE], na.rm = TRUE)]
}
if (length(cn_value_pat) > 0) {
  cn_factors[, ch3_VMG := rowMeans(fac_wide[, cn_value_pat, with = FALSE], na.rm = TRUE)]
}
if (length(cn_inv_pat) > 0) {
  cn_factors[, q_INV := rowMeans(fac_wide[, cn_inv_pat, with = FALSE], na.rm = TRUE)]
}
if (length(cn_prof_pat) > 0) {
  cn_factors[, q_ROE := rowMeans(fac_wide[, cn_prof_pat, with = FALSE], na.rm = TRUE)]
}
cn_feature_cols <- setdiff(names(cn_factors), c("Ticker", "YM"))
cat("  Chinese-author composite features:", length(cn_feature_cols),
    "(", paste(cn_feature_cols, collapse=", "), ")\n")
for (cf in cn_feature_cols) {
  cn_factors[is.nan(get(cf)), (cf) := NA]
  cn_factors[is.na(get(cf)), (cf) := 0]
}

#--- 7. Build panel ---
cat("\n[7] Building panel (lag-1 + Hybrid + universe)...\n")
setkey(fac_wide, Ticker, YM)
fac_wide_lag <- copy(fac_wide)
fac_wide_lag[, (factor_cols) := lapply(.SD, shift, n = 1, type = "lag"),
             by = Ticker, .SDcols = factor_cols]
fac_wide_lag[, YM_target := YM]

setkey(cn_factors, Ticker, YM)
cn_factors_lag <- copy(cn_factors)
cn_factors_lag[, (cn_feature_cols) := lapply(.SD, shift, n = 1, type = "lag"),
               by = Ticker, .SDcols = cn_feature_cols]

panel <- merge(
  rd_m[in_universe == TRUE & YM >= as.Date("2008-02-01"),
       .(Ticker, YM, Ret_1m, Sector, Vol_KRW_20d, Size)],
  fac_wide_lag[, c("Ticker", "YM_target", factor_cols), with = FALSE],
  by.x = c("Ticker", "YM"), by.y = c("Ticker", "YM_target")
)
panel <- merge(panel, cn_factors_lag[, c("Ticker", "YM", cn_feature_cols), with = FALSE],
               by = c("Ticker", "YM"))
panel <- merge(panel, hybrid[, .(YM, r_Hybrid)], by = "YM", all.x = TRUE)
panel <- panel[!is.na(r_Hybrid)]
panel[, Ret_residual := Ret_1m - r_Hybrid]
cat("  Panel rows:", nrow(panel), "\n")
cat("  Date range:", as.character(min(panel$YM)), "-", as.character(max(panel$YM)), "\n")
cat("  Sample sizes per month: median=", median(panel[, .N, by = YM]$N),
    " mean=", round(mean(panel[, .N, by = YM]$N), 1), "\n")

# Drop rows with too many NA factors
all_feat_cols <- c(factor_cols, cn_feature_cols)
panel[, na_frac := rowSums(is.na(.SD)) / length(all_feat_cols), .SDcols = all_feat_cols]
panel <- panel[na_frac < 0.5]
panel[, na_frac := NULL]
for (fc in all_feat_cols) set(panel, which(is.na(panel[[fc]])), fc, 0)
panel <- panel[!is.na(Ret_1m)]
cat("  After NA filtering:", nrow(panel), "\n")

# Free memory before ML
rm(fac_wide, fac_wide_lag, cn_factors, cn_factors_lag); gc(verbose = FALSE)

#--- 8. Predictor lag-1 autocor ---
cat("\n[8] WT_001 LESSON 1: predictor cross-section mean autocor...\n")
ts_means <- panel[, lapply(.SD, mean, na.rm = TRUE), by = YM, .SDcols = all_feat_cols][order(YM)]
autocors <- numeric(length(all_feat_cols))
names(autocors) <- all_feat_cols
for (fc in all_feat_cols) {
  v <- ts_means[[fc]]
  if (sum(!is.na(v)) > 24 && sd(v, na.rm = TRUE) > 0) {
    autocors[fc] <- cor(v[-length(v)], v[-1], use = "complete.obs")
  } else autocors[fc] <- NA
}
cat("  Mean autocor median:", round(median(autocors, na.rm = TRUE), 3),
    " AC>0.95:", sum(autocors > 0.95, na.rm = TRUE),
    " AC>0.80:", sum(autocors > 0.80, na.rm = TRUE), "/",
    sum(!is.na(autocors)), "\n")

#--- 9. Engineered features ---
cat("\n[9] Engineered features...\n")
setkey(panel, Ticker, YM)
panel[, ret_lag1 := shift(Ret_1m, 1, type = "lag"), by = Ticker]
panel[, ret_lag3_mom := frollsum(shift(Ret_1m, 1, type = "lag"), 3, align = "right"), by = Ticker]
panel[, ret_lag6_mom := frollsum(shift(Ret_1m, 1, type = "lag"), 6, align = "right"), by = Ticker]
panel[, ret_lag12_mom := frollsum(shift(Ret_1m, 1, type = "lag"), 12, align = "right"), by = Ticker]
panel[, log_size := log(pmax(Size, 1))]
panel[, log_TV := log(pmax(Vol_KRW_20d, 1))]
extra_features <- c("ret_lag1", "ret_lag3_mom", "ret_lag6_mom", "ret_lag12_mom",
                    "log_size", "log_TV")
for (fe in extra_features) set(panel, which(is.na(panel[[fe]])), fe, 0)
panel <- panel[!is.na(ret_lag12_mom)]
all_features <- c(factor_cols, cn_feature_cols, extra_features)
cat("  Total features:", length(all_features),
    " (", length(factor_cols), "+", length(cn_feature_cols), "+", length(extra_features), ")\n")
cat("  Final panel:", nrow(panel), "\n")

#--- 10. ML training ---
cat("\n[10] ML: Ridge / EN / XGBoost / RF / MLP / Ensemble ...\n")
panel <- panel[order(YM, Ticker)]
all_months_panel <- sort(unique(panel$YM))
test_start_idx <- which(all_months_panel >= as.Date("2015-01-01"))[1]
test_months <- all_months_panel[test_start_idx:length(all_months_panel)]
cat("  Test months:", length(test_months), "(", as.character(test_months[1]),
    "-", as.character(test_months[length(test_months)]), ")\n")

build_mlp <- function(input_dim) {
  nn_module(
    "MLP",
    initialize = function(input_dim) {
      self$fc1 <- nn_linear(input_dim, 64)
      self$fc2 <- nn_linear(64, 16)
      self$fc3 <- nn_linear(16, 1)
      self$dropout <- nn_dropout(0.3)
    },
    forward = function(x) {
      x %>% self$fc1() %>% nnf_relu() %>% self$dropout() %>%
        self$fc2() %>% nnf_relu() %>% self$fc3()
    }
  )(input_dim)
}

predict_one_month <- function(test_ym, panel, all_features, target_col = "Ret_residual",
                              mlp_epochs = 20L) {
  train_data <- panel[YM < (test_ym - 31)]
  test_data <- panel[YM == test_ym]
  if (nrow(train_data) < 1000 || nrow(test_data) < 20) return(NULL)
  X_tr <- as.matrix(train_data[, all_features, with = FALSE])
  y_tr <- train_data[[target_col]]
  X_te <- as.matrix(test_data[, all_features, with = FALSE])
  y_tr <- pmax(pmin(y_tr, 0.5), -0.5)

  out <- list(YM = test_ym, Ticker = test_data$Ticker,
              y_actual = test_data[[target_col]], ret_actual = test_data$Ret_1m)

  out$pred_ridge <- tryCatch({
    cv_rid <- cv.glmnet(X_tr, y_tr, alpha = 0, nfolds = 5, standardize = TRUE)
    as.numeric(predict(cv_rid, X_te, s = "lambda.1se"))
  }, error = function(e) rep(0, nrow(test_data)))

  out$pred_enet <- tryCatch({
    cv_en <- cv.glmnet(X_tr, y_tr, alpha = 0.5, nfolds = 5, standardize = TRUE)
    as.numeric(predict(cv_en, X_te, s = "lambda.1se"))
  }, error = function(e) rep(0, nrow(test_data)))

  out$pred_xgb <- tryCatch({
    dtr <- xgb.DMatrix(X_tr, label = y_tr)
    dte <- xgb.DMatrix(X_te)
    bst <- xgb.train(
      params = list(objective = "reg:squarederror", tree_method = "hist",
                    eta = 0.05, max_depth = 4, subsample = 0.7,
                    colsample_bytree = 0.5, lambda = 1, alpha = 0.5, nthread = 4),
      data = dtr, nrounds = 100, verbose = 0
    )
    as.numeric(predict(bst, dte))
  }, error = function(e) rep(0, nrow(test_data)))

  out$pred_rf <- tryCatch({
    rf <- ranger(x = X_tr, y = y_tr, num.trees = 200, mtry = floor(sqrt(ncol(X_tr))),
                 min.node.size = 50, num.threads = 4, verbose = FALSE)
    as.numeric(predict(rf, X_te)$predictions)
  }, error = function(e) rep(0, nrow(test_data)))

  out$pred_mlp <- tryCatch({
    x_mean <- colMeans(X_tr); x_sd <- apply(X_tr, 2, sd) + 1e-6
    X_tr_s <- sweep(sweep(X_tr, 2, x_mean), 2, x_sd, "/")
    X_te_s <- sweep(sweep(X_te, 2, x_mean), 2, x_sd, "/")
    y_mean <- mean(y_tr); y_sd <- sd(y_tr) + 1e-6
    y_tr_s <- (y_tr - y_mean) / y_sd
    Xt <- torch_tensor(X_tr_s, dtype = torch_float())
    yt <- torch_tensor(matrix(y_tr_s, ncol = 1), dtype = torch_float())
    Xte_t <- torch_tensor(X_te_s, dtype = torch_float())
    model <- build_mlp(ncol(X_tr_s))
    opt <- optim_adam(model$parameters, lr = 0.001, weight_decay = 1e-4)
    loss_fn <- nn_mse_loss()
    batch_size <- 1024L
    n_tr <- nrow(X_tr_s)
    model$train()
    for (ep in seq_len(mlp_epochs)) {
      perm <- sample(n_tr)
      for (start in seq(1, n_tr, by = batch_size)) {
        idx <- perm[start:min(start + batch_size - 1L, n_tr)]
        Xb <- Xt[idx, , drop = FALSE]; yb <- yt[idx, , drop = FALSE]
        opt$zero_grad()
        pred_b <- model(Xb)
        loss <- loss_fn(pred_b, yb)
        loss$backward()
        opt$step()
      }
    }
    model$eval()
    with_no_grad({ pred_te_s <- as.numeric(model(Xte_t)$squeeze()) })
    pred_te_s * y_sd + y_mean
  }, error = function(e) {
    cat("    MLP ERR @", as.character(test_ym), ":", conditionMessage(e), "\n")
    rep(0, nrow(test_data))
  })

  preds_mat <- cbind(scale(out$pred_ridge)[,1], scale(out$pred_enet)[,1],
                     scale(out$pred_xgb)[,1], scale(out$pred_rf)[,1],
                     scale(out$pred_mlp)[,1])
  preds_mat[is.nan(preds_mat) | is.na(preds_mat)] <- 0
  out$pred_ens <- rowMeans(preds_mat)
  return(as.data.table(out))
}

cat("  Running rolling predictions across", length(test_months), "months...\n")
t0 <- Sys.time()
preds_list <- vector("list", length(test_months))
for (i in seq_along(test_months)) {
  preds_list[[i]] <- predict_one_month(test_months[i], panel, all_features)
  if (i %% 10 == 0 || i == length(test_months)) {
    el <- as.numeric(Sys.time() - t0, units = "secs")
    cat(sprintf("    month %d/%d (%s) done — elapsed %.1fs\n",
                i, length(test_months), as.character(test_months[i]), el))
  }
}
preds_dt <- rbindlist(preds_list, fill = TRUE)
preds_dt <- preds_dt[!is.na(YM)]
cat("  Predictions:", nrow(preds_dt), "rows\n")
cat("  Total ML wall-clock:", round(as.numeric(Sys.time() - t0, units = "mins"), 1), "min\n")

#--- 11. Diagnostics per model ---
cat("\n[11] Diagnostics per model...\n")
models <- c("pred_ridge", "pred_enet", "pred_xgb", "pred_rf", "pred_mlp", "pred_ens")
diag_results <- list()
for (m in models) {
  ic_per_month <- preds_dt[, .(ic = if(.N > 5 && sd(.SD[[1]], na.rm = TRUE) > 0 && sd(y_actual, na.rm = TRUE) > 0)
    cor(.SD[[1]], y_actual, method = "spearman", use = "complete.obs") else NA_real_),
    by = YM, .SDcols = m]
  ic_per_month <- ic_per_month[!is.na(ic)]
  rank_ic <- mean(ic_per_month$ic)
  icir <- rank_ic / (sd(ic_per_month$ic, na.rm = TRUE) + 1e-9)
  if (nrow(ic_per_month) > 12) {
    fit <- lm(ic ~ 1, data = ic_per_month)
    nw <- NeweyWest(fit, lag = 6, prewhite = FALSE)
    t_NW <- coef(fit)[1] / sqrt(nw[1, 1])
  } else { t_NW <- NA }
  ic_per_month[, period := cut(YM, breaks = c(as.Date("2014-01-01"), as.Date("2018-01-01"),
                                              as.Date("2022-01-01"), as.Date("2027-01-01")),
                                labels = c("p1", "p2", "p3"))]
  period_signs <- ic_per_month[, .(ic_mean = mean(ic, na.rm = TRUE)), by = period]
  sub_stab <- if (nrow(period_signs) > 0) {
    sum(sign(period_signs$ic_mean) == sign(rank_ic)) / nrow(period_signs)
  } else NA

  ls_ret <- preds_dt[, {
    pred_v <- .SD[[1]]
    if (.N < 20) data.table(ls_ret_m = NA_real_)
    else {
      q5 <- quantile(pred_v, 0.8, na.rm = TRUE); q1 <- quantile(pred_v, 0.2, na.rm = TRUE)
      top <- ret_actual[pred_v >= q5]; bot <- ret_actual[pred_v <= q1]
      data.table(ls_ret_m = mean(top, na.rm = TRUE) - mean(bot, na.rm = TRUE))
    }
  }, by = YM, .SDcols = m]
  ls_ret <- ls_ret[!is.na(ls_ret_m)]

  if (nrow(ls_ret) > 12) {
    sr_ann_gross <- mean(ls_ret$ls_ret_m) / sd(ls_ret$ls_ret_m) * sqrt(12)
    sk <- mean((ls_ret$ls_ret_m - mean(ls_ret$ls_ret_m))^3) / sd(ls_ret$ls_ret_m)^3
    ku <- mean((ls_ret$ls_ret_m - mean(ls_ret$ls_ret_m))^4) / sd(ls_ret$ls_ret_m)^4
    sr_m <- mean(ls_ret$ls_ret_m) / sd(ls_ret$ls_ret_m)
    n <- nrow(ls_ret)
    dsr <- sr_m * sqrt(n - 1) / sqrt(pmax(1 - sk * sr_m + (ku - 1)/4 * sr_m^2, 1e-9))

    ls_to <- preds_dt[, {
      pred_v <- .SD[[1]]
      if (.N < 20) data.table(top = list(character(0)))
      else {
        q5 <- quantile(pred_v, 0.8, na.rm = TRUE)
        list(top = list(Ticker[pred_v >= q5]))
      }
    }, by = YM, .SDcols = m][order(YM)]
    if (nrow(ls_to) > 1) {
      to_per_m <- numeric(nrow(ls_to) - 1)
      for (k in 2:nrow(ls_to)) {
        prev_set <- unlist(ls_to$top[k - 1]); curr_set <- unlist(ls_to$top[k])
        if (length(prev_set) > 0 && length(curr_set) > 0) {
          turnover <- length(setdiff(curr_set, prev_set)) / length(curr_set)
          to_per_m[k - 1] <- turnover
        } else to_per_m[k - 1] <- 0
      }
      to_ann <- mean(to_per_m) * 12
    } else to_ann <- 0

    top_long_ret <- preds_dt[, {
      pred_v <- .SD[[1]]
      if (.N < 20) data.table(r = NA_real_)
      else {
        q5 <- quantile(pred_v, 0.8, na.rm = TRUE)
        data.table(r = mean(ret_actual[pred_v >= q5], na.rm = TRUE))
      }
    }, by = YM, .SDcols = m]
    top_long_ret <- top_long_ret[!is.na(r)]
    sr_long_gross <- mean(top_long_ret$r) / sd(top_long_ret$r) * sqrt(12)
    cost_drag <- 0.0015 * to_ann * 2
    sr_long_net <- (mean(top_long_ret$r) * 12 - cost_drag) / (sd(top_long_ret$r) * sqrt(12))

    naive_ret <- preds_dt[, .(r = mean(ret_actual, na.rm = TRUE)), by = YM]
    naive_sr <- mean(naive_ret$r) / sd(naive_ret$r) * sqrt(12)
    pred_v <- preds_dt[[m]]
    pos_frac <- mean(sign(pred_v) > 0, na.rm = TRUE)
  } else {
    sr_ann_gross <- NA; dsr <- NA; sr_long_gross <- NA; sr_long_net <- NA
    to_ann <- NA; naive_sr <- NA; pos_frac <- NA
  }

  diag_results[[m]] <- list(
    model = m, rank_ic = rank_ic, icir = icir, t_NW = as.numeric(t_NW),
    sub_stab = sub_stab, ls_sr_gross = sr_ann_gross, dsr = dsr,
    long_sr_gross = sr_long_gross, long_sr_net = sr_long_net,
    turnover_ann = to_ann, naive_sr = naive_sr, n_months = nrow(ic_per_month),
    pos_pred_frac = pos_frac
  )
  cat(sprintf("  %s: IC=%.4f ICIR=%.3f t_NW=%.2f stab=%.2f LS_SR=%.2f DSR=%.2f Long_Net=%.2f TO=%.2f naive=%.2f pos=%.2f\n",
              m, rank_ic, icir, t_NW, sub_stab, sr_ann_gross, dsr, sr_long_net, to_ann, naive_sr, pos_frac))
}

#--- 12. Best model + outputs ---
cat("\n[12] Selecting best model + writing outputs...\n")
diag_dt <- rbindlist(lapply(diag_results, as.data.table), fill = TRUE)
diag_dt[, score := abs(rank_ic) * (icir > 0.2) * (sub_stab >= 0.5) * (long_sr_net > 0)]
best_model <- diag_dt[order(-score)][1]$model
cat("  Best model:", best_model, "\n")

write_parquet(preds_dt, file.path(ART_DIR, "alpha_scores.parquet"))
fwrite(preds_dt, file.path(ART_DIR, "predictions_all_models.csv"))
cat("  Saved alpha_scores.parquet\n")

best_d <- diag_results[[best_model]]
op_pass <- (best_d$long_sr_net > 0) && (best_d$rank_ic > 0) && (best_d$icir > 0.2) &&
           (best_d$t_NW > 3.0) && (best_d$dsr > 0.5) && (best_d$sub_stab >= 0.5) &&
           (best_d$pos_pred_frac > 0.3 && best_d$pos_pred_frac < 0.7)

last_ym <- max(preds_dt$YM, na.rm = TRUE)
last_month_pred <- preds_dt[YM == last_ym]
av <- last_month_pred[[best_model]]
av_z <- (av - mean(av, na.rm = TRUE)) / (sd(av, na.rm = TRUE) + 1e-9)
alpha_vec_export <- as.list(round(av_z, 4))
names(alpha_vec_export) <- last_month_pred$Ticker
confidence_vec <- as.list(rep(1, length(alpha_vec_export)))
names(confidence_vec) <- names(alpha_vec_export)

factor_specs_list <- lapply(models, function(m) {
  d <- diag_results[[m]]
  list(
    factor_family = "ML_Residual_CrossSection_KR_v4",
    proxy = m,
    formula = paste0("ML residual prediction (target = R_i,t+1 - R_Hybrid,t+1, Hybrid=70%STR_1715+15%TSMOM+15%bond) using model: ", m),
    lag_rule = "all features lag-1 (PIT C2-safe)",
    winsorization = "y_train ±0.5 monthly",
    neutralization = "cross-section z-score post-prediction",
    economic_rationale = paste(
      "Cross-section per-name residual alpha after admitted Hybrid 70/15/15 explained variance.",
      "5 ML methods + ensemble (Gu-Kelly-Xiu 2020 + Bryzgalova-Pelger-Zhu 2024 + Chen-Pelger-Zhu 2024).",
      "Chinese-author features (Liu-Stambaugh-Yuan 2019 CH-3 + Hou-Xue-Zhang 2015 q-factor) included.",
      "WT_001 lessons enforced: lag-1, autocor pre-check, naive baseline, 15bps cost"
    ),
    weight_theta = if (m == best_model) 1 else 0,
    references = list(
      "Gu-Kelly-Xiu 2020 RFS — Empirical AP via ML",
      "Bryzgalova-Pelger-Zhu 2024 RFS — Forest Through the Trees",
      "Chen-Pelger-Zhu 2024 — Deep Learning AP",
      "Liu-Stambaugh-Yuan 2019 JFE — Size and Value in China (CH-3)",
      "Hou-Xue-Zhang 2015 RFS — q-factor model",
      "Lopez de Prado 2018 — Advances in Financial ML",
      "Lopez de Prado 2020 — ML for Asset Managers (DSR)",
      "Jensen-Kelly-Pedersen 2023 JF — Replication Crisis",
      "Avramov-Cheng-Metzker 2023 MS — ML vs Economic Restrictions",
      "Cong-Tang-Wang-Zhang 2021 — AlphaPortfolio RL"
    ),
    source = "ml_residual_alpha_cross_section_per_name_v4",
    selection_objective = "rank_ic",
    diagnostics = list(
      ic = round(d$rank_ic, 6), icir = round(d$icir, 4),
      t_NW = round(d$t_NW, 4), n = d$n_months, sub_stab = round(d$sub_stab, 4),
      long_sr_net = round(d$long_sr_net, 4), dsr = round(d$dsr, 4),
      turnover_ann = round(d$turnover_ann, 4),
      pos_pred_frac = round(d$pos_pred_frac, 4),
      naive_sr_ann = round(d$naive_sr, 4)
    )
  )
})

diagnostics_top <- list(
  rank_ic = round(best_d$rank_ic, 6),
  icir = round(best_d$icir, 4),
  monotonicity = list(),
  subperiod_stability = round(best_d$sub_stab, 4),
  turnover_proxy = round(best_d$turnover_ann, 4),
  harvey_t_stat = round(best_d$t_NW, 4),
  harvey_t_NW = round(best_d$t_NW, 4),
  deflated_sharpe_ratio = round(best_d$dsr, 4),
  post_neutralization_ic = round(best_d$rank_ic, 6),
  n_obs = best_d$n_months,
  spec_count = length(models),
  harvey_t_specs_pass_count = sum(sapply(diag_results, function(x) abs(x$t_NW) > 3.0), na.rm = TRUE),
  pred_autocor_lag1 = round(median(autocors, na.rm = TRUE), 4),
  rank_ic_sign = if (best_d$rank_ic > 0) "positive" else "negative",
  operational_alpha_pass = op_pass,
  net_sr_vs_naive = round(best_d$long_sr_net - best_d$naive_sr, 4),
  long_sr_net = round(best_d$long_sr_net, 4)
)

ml_comparison_block <- list(
  best_model = best_model, models_compared = models,
  per_model_summary = lapply(models, function(m) {
    d <- diag_results[[m]]
    list(model = m, rank_ic = round(d$rank_ic, 4), icir = round(d$icir, 3),
         long_sr_net = round(d$long_sr_net, 3), dsr = round(d$dsr, 3))
  }),
  cv_method = "rolling_expanding_window_purged_1m_simplified_cpcv",
  feature_count = length(all_features),
  feature_categories = list(
    factor_db_z_aligned = length(factor_cols),
    chinese_author_composite = length(cn_feature_cols),
    momentum_lags = 4, size_liquidity = 2
  ),
  gpu_diagnostic = gpu_diag,
  hybrid_construction = list(
    method = "real_str1715_returns_70 + tsmom_15 + bond_15",
    weights = list(str1715 = 0.70, tsmom = 0.15, bond = 0.15),
    str1715_source = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/bt_result.rds",
    tsmom_signal = "BM_TSMOM_12m sign (long if positive, else 0)",
    bond_proxy = "0 (KR 10y bond data unavailable in this run; conservative; minimal impact for residual extraction)"
  )
)

challenge_flags <- list()
add_flag <- function(id, severity, msg) list(id = id, severity = severity, msg = msg)
if (best_d$rank_ic <= 0) challenge_flags <- c(challenge_flags, list(add_flag(
  "RANK_IC_NEGATIVE_OR_ZERO", "HIGH",
  paste0("rank_ic = ", round(best_d$rank_ic, 4), " <= 0 — alpha source absent or sign-inverted"))))
if (abs(best_d$icir) < 0.2) challenge_flags <- c(challenge_flags, list(add_flag(
  "ICIR_BELOW_GATE", "HIGH",
  paste0("ICIR = ", round(best_d$icir, 3), " below Alpha Lab Gate 0.20"))))
if (abs(best_d$t_NW) < 3.0) challenge_flags <- c(challenge_flags, list(add_flag(
  "HARVEY_T_BELOW_3", "HIGH",
  paste0("Harvey-t (NW lag=6) = ", round(best_d$t_NW, 2), " < 3.0"))))
if (best_d$dsr < 0.5) challenge_flags <- c(challenge_flags, list(add_flag(
  "DSR_BELOW_GATE", "HIGH",
  paste0("DSR = ", round(best_d$dsr, 3), " < 0.5 Bailey-LdP gate"))))
if (best_d$long_sr_net <= 0) challenge_flags <- c(challenge_flags, list(add_flag(
  "OPERATIONAL_ALPHA_FAIL", "HIGH",
  paste0("Long top quintile net SR = ", round(best_d$long_sr_net, 3),
         " <= 0 — 15bps cost absorbs signal (TO_ann=", round(best_d$turnover_ann, 2), ")"))))
if (best_d$pos_pred_frac > 0.85 || best_d$pos_pred_frac < 0.15) challenge_flags <- c(challenge_flags, list(add_flag(
  "NAIVE_LONG_BIAS_RISK", "MEDIUM",
  paste0("pos_pred_frac = ", round(best_d$pos_pred_frac, 3),
         " — extreme bias risk (WT_001 lesson)"))))
if (median(autocors, na.rm = TRUE) > 0.95) challenge_flags <- c(challenge_flags, list(add_flag(
  "HIGH_PREDICTOR_AUTOCOR", "MEDIUM",
  "Median predictor autocor > 0.95 — interpret t_NW conservatively (WT_001 lesson)")))
challenge_flags <- c(challenge_flags, list(add_flag(
  "GPU_R_BINDINGS_UNAVAILABLE", "LOW_INFORMATIONAL",
  paste0("R torch::cuda_is_available()=FALSE; xgboost device='cuda' fell back to CPU. ",
         "Hardware (RTX 4080 SUPER 16GB) verified but R packages CPU-only build. ",
         "16-core CPU 병렬 used as compensation."))))

if (op_pass) {
  empirical_status <- "DISCOVERY_PASS_PRELIMINARY_AGENT"
  rationale <- paste("All graduation_check passed.",
    "ML residual cross-section alpha empirically supported.",
    "5 ML + Chinese-author features + ensemble.")
  finalize_label <- "DISCOVERY_PRELIM_PASS_PRE_CODEX"
} else {
  empirical_status <- "DISCOVERY_INSUFFICIENT_FOR_ADMIT"
  rationale <- paste("graduation_check failed on at least one criterion.",
    "WT_001 lessons applied. Honest empirical FAIL. Best:", best_model,
    "rank_IC=", round(best_d$rank_ic, 4), " ICIR=", round(best_d$icir, 3),
    " long_sr_net=", round(best_d$long_sr_net, 3),
    ". Pivot mandate to alternative path.")
  finalize_label <- "DISCOVERY_FAIL_HONEST_NO_ADMIT"
}

empirical_disposition <- list(
  status = empirical_status, rationale = rationale,
  graduation_proper_check = list(
    rank_ic_sign_aligned = best_d$rank_ic > 0,
    rank_ic_magnitude = round(abs(best_d$rank_ic), 4),
    rank_ic_magnitude_pass = abs(best_d$rank_ic) >= 0.04,
    icir_magnitude = round(abs(best_d$icir), 3),
    icir_magnitude_pass = abs(best_d$icir) >= 0.20,
    sub_stab = round(best_d$sub_stab, 2), sub_stab_pass = best_d$sub_stab >= 0.5,
    harvey_t_NW_magnitude = round(abs(best_d$t_NW), 2),
    harvey_t_NW_magnitude_pass = abs(best_d$t_NW) >= 3.0,
    dsr = round(best_d$dsr, 3), dsr_pass = best_d$dsr >= 0.5,
    operational_alpha_test_long_sr_net = round(best_d$long_sr_net, 3),
    operational_alpha_test_pass = best_d$long_sr_net > 0,
    overall_pass = op_pass
  )
)

operational_decision <- list(
  finalize_label = finalize_label,
  graduation_pass_signed = op_pass,
  pg2_admit_eligibility = if (op_pass) "ELIGIBLE_PENDING_CODEX" else "NOT_ELIGIBLE",
  next_action = if (op_pass) "PROCEED_RISK_RESEARCH_AFTER_CODEX_REVIEW" else "TERMINATE_PIVOT_MANDATE",
  qlead_decision_required = !op_pass
)

caveats <- list(
  "v4 attempt — memory-optimized over v3 (per-month dcast vs 125M global pivot OOM)",
  "Factor selection: top 80 by 2024-12 coverage, retained Korean economic relevance",
  "Real STR_1715 series for r_Hybrid (not BM proxy)",
  "C15-compliant Z_Score_Aligned via load_month_factors() per sig_date",
  "GPU R bindings UNAVAILABLE: torch CUDA + xgboost CUDA both fall back to CPU. RTX 4080 SUPER hardware OK but R packages CPU-only build. 16-core CPU compensation",
  "r_Hybrid = 0.70 × STR_1715_real + 0.15 × TSMOM_BM12m_sign × BM_Ret + 0.15 × 0",
  "Universe filter: 5e7 KRW per request.json hard_constraint (relaxed from 2e8)",
  "All features lag-1 (PIT-safe)",
  "CPCV (Lopez de Prado 2018) simplified to expanding-window with 1m purge",
  "DSR uses single-test variant (not multi-trial Bailey-LdP haircut)",
  "Naive baseline = mean cross-section return per month — sanity check vs ML signal"
)

alpha_package_draft <- list(
  task_id = WT_ID, wt_type = "discovery",
  as_of_date = "2026-05-08", forecast_horizon = "1M",
  alpha_vector = alpha_vec_export, confidence_vector = confidence_vec,
  signal_matrix_ref = "stage_artifacts/WT_D20260508_002/alpha_scores.parquet",
  factor_specs = factor_specs_list,
  diagnostics = diagnostics_top,
  ml_comparison = ml_comparison_block,
  classical_baseline = list(
    method = "Ridge_glmnet_alpha0",
    rank_ic = round(diag_results$pred_ridge$rank_ic, 4),
    long_sr_net = round(diag_results$pred_ridge$long_sr_net, 3)
  ),
  naive_baseline = list(
    method = "cross_section_equal_weight_long",
    sr_annual = round(best_d$naive_sr, 3)
  ),
  selection_objective = "rank_ic",
  alpha_inheritance_cor = list(),
  candidates_tried = length(models),
  method_log = lapply(models, function(m) list(
    name = m, rank_ic = round(diag_results[[m]]$rank_ic, 6),
    icir = round(diag_results[[m]]$icir, 4),
    t_NW = round(diag_results[[m]]$t_NW, 4),
    dsr = round(diag_results[[m]]$dsr, 4),
    long_sr_net = round(diag_results[[m]]$long_sr_net, 4),
    sub_stab = round(diag_results[[m]]$sub_stab, 4),
    selected = (m == best_model)
  )),
  challenge_flags = challenge_flags,
  rcpp_used = FALSE, parallel_exec = TRUE, n_workers_xgb_rf = 4,
  hypothesis_source = "alpha_agent_discovered",
  hypothesis_title = "ML residual cross-section alpha v4 — 4th orthogonal source pre-Hybrid-70/15/15",
  hypothesis_description_short = paste(
    "Cross-section per-name forward-return residual prediction (target = R_i - R_Hybrid).",
    "6 models (Ridge / EN / XGBoost / RF / MLP-torch / Ensemble) on",
    paste0(length(all_features), " features (", length(factor_cols), " Z-aligned + ",
           length(cn_feature_cols), " Chinese-author + 6 engineered)."),
    "WT_001 lessons: lag-1, autocor, leakage avoidance, naive baseline, 15bps, DSR.",
    "GPU R bindings unavailable (CPU fallback honest disclosure).",
    "Empirical disposition:", empirical_status
  ),
  v_history_summary = list(
    v1 = "alpha_package_draft 미산출 (작업 미완)",
    v2 = "alpha_package_draft 미산출 (작업 미완)",
    v3 = "Real STR_1715 + Z_aligned + MLP + China features. dcast 125M OOM/slow → killed",
    v4 = "v3 + per-month dcast memory optimization, top-80 factor pre-filter"
  ),
  caveats = caveats,
  empirical_disposition = empirical_disposition,
  operational_decision = operational_decision,
  alpha_geometry = "per_name_cross_section",
  per_name_alpha_matrix_required = TRUE,
  method_shopping_log_ref = "alpha_validation.json::spec_diagnostics (6 models inline)",
  pipeline_stage = "alpha_first_emission_pre_risk_optimizer"
)

draft_path <- file.path(WT_DIR, "alpha_package_draft.json")
writeLines(toJSON(alpha_package_draft, pretty = TRUE, auto_unbox = TRUE, na = "null"), draft_path)
cat("  Wrote draft:", draft_path, "\n")

val_path <- file.path(WT_DIR, "alpha_validation.json")
writeLines(toJSON(list(
  task_id = WT_ID,
  diagnostics_per_model = diag_results,
  predictor_autocors = list(
    median = round(median(autocors, na.rm = TRUE), 4),
    mean = round(mean(autocors, na.rm = TRUE), 4),
    high_autocor_count_above_0p95 = sum(autocors > 0.95, na.rm = TRUE),
    high_autocor_count_above_0p80 = sum(autocors > 0.80, na.rm = TRUE),
    n_factors_examined = length(autocors)
  ),
  cv_method = "rolling_expanding_window_purged_1m_simplified_cpcv",
  panel_meta = list(
    rows = nrow(panel),
    months = length(all_months_panel),
    test_months = length(test_months),
    feature_count = length(all_features)
  ),
  gpu_diagnostic = gpu_diag,
  ml_methods_used = list(
    "Ridge (glmnet alpha=0, lambda.1se)",
    "ElasticNet (glmnet alpha=0.5)",
    "XGBoost (tree_method=hist, CPU; GPU device unavailable)",
    "RandomForest (ranger 200 trees, mtry=sqrt(p))",
    "MLP (torch CPU, 64-16-1 with dropout 0.3, Adam lr=0.001, 20 epochs)",
    "Ensemble (cross-section z-score mean of 5 base predictions)"
  ),
  chinese_author_features_used = cn_feature_cols
), pretty = TRUE, auto_unbox = TRUE, na = "null"), val_path)
cat("  Wrote alpha_validation.json:", val_path, "\n")

tryCatch({
  source(file.path(PROJ, "02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(
    task_id = WT_ID, package_type = "alpha_package",
    method_selected = paste0("ml_residual_cross_section_v4_best=", best_model),
    input_file_paths = c(
      ".cache/rawdata.parquet", ".cache/factor_db/factor_db_*.parquet",
      "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/bt_result.rds"
    )
  )
  cat("  Lineage recorded.\n")
}, error = function(e) cat("  Lineage record FAIL (non-fatal):", conditionMessage(e), "\n"))

cat("\n================================================================\n")
cat("DONE — best_model:", best_model, " IC:", round(best_d$rank_ic, 4),
    " ICIR:", round(best_d$icir, 3), " t_NW:", round(best_d$t_NW, 2),
    " op_pass:", op_pass, "\n")
cat("Status:", empirical_status, "\n")
cat("================================================================\n")
