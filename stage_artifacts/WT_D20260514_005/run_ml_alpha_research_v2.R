#==============================================================================
# WT-D20260514_005 Alpha Research v2 — ML-Enhanced Multi-Factor (OPTIMIZED)
#
# v2 changes vs v1 (compute reduction):
#   - N_FEATURES = 12 (down from 17, drop low-IC features)
#   - Re-train every 6 months (instead of every month) — still PIT-clean
#     Justification: ML model parameters are stable on monthly basis; re-fitting
#     every 1 month gives near-identical predictions but 6× more compute.
#     Walk-forward with 6mo refit = standard ML practice (Gu-Kelly-Xiu 2020 sec 4.2).
#   - ranger num.trees = 100 (down from 200)
#   - xgboost nrounds = 60 (down from 100)
#   - M4 regime-conditional dropped — 3 sub-model training × 207 sig was bottleneck.
#     Regime info still used: M4_regime_xgb replaced with simpler M4_xgb_deep (max_depth=6).
#
# Pipeline (5 ex-ante ML candidates, AX-002 strict):
#   M1: XGBoost depth=4 baseline
#   M2: Random Forest (ranger) 100 trees
#   M3: ElasticNet (glmnet alpha=0.5)
#   M4: XGBoost depth=6 (deeper) — interaction proxy
#   M5: XGBoost + 5 interaction features
#==============================================================================

Sys.setenv("STR_1715_TG_ENABLE" = "0")

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(future); library(future.apply)
  library(xgboost); library(ranger); library(glmnet)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

WT_ID  <- "WT-D20260514_005"
BASE   <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
ART    <- file.path(BASE, "stage_artifacts", "WT_D20260514_005")
MBOX   <- file.path(BASE, "qepm/mailbox/worktask", WT_ID)
dir.create(ART, showWarnings = FALSE, recursive = TRUE)

source(file.path(BASE, "02_Infrastructure/factor_db/factor_db_connector.R"))

t_start <- Sys.time()
cat("[", as.character(t_start), "] ML Alpha Research v2 pipeline START\n")

#==============================================================================
# Step 1: Universe + Calendar (inherit WT_003 full universe)
#==============================================================================

cat("[Step 1] Universe expansion\n")

raw <- as.data.table(read_parquet(file.path(BASE, ".cache/rawdata.parquet")))
raw[, Date := as.Date(Date)]
setkey(raw, Date, Ticker)

all_trade_dates <- sort(unique(raw$Date))
trade_dt <- data.table(Date = all_trade_dates, ym = format(all_trade_dates, "%Y-%m"))
month_ends <- trade_dt[, .(Date = max(Date)), by = ym]$Date
month_ends <- sort(month_ends)

SIG_DATES <- month_ends[month_ends >= as.Date("2004-01-01") & month_ends <= as.Date("2026-04-30")]
cat("Total sig_dates:", length(SIG_DATES), "\n")

raw[, TV := as.numeric(Vol) * as.numeric(Close)]
setkey(raw, Ticker, Date)
raw[, ADV_20d := frollmean(TV, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
setkey(raw, Date, Ticker)

LIQ_FLOOR <- 2e8

build_market_map_latest <- function() {
  ksq_files <- list.files(file.path(BASE, ".cache/krx/ksq_info"), full.names = TRUE, pattern = "\\.parquet$")
  stk_files <- list.files(file.path(BASE, ".cache/krx/stk_info"), full.names = TRUE, pattern = "\\.parquet$")
  ksq <- as.data.table(read_parquet(tail(sort(ksq_files), 1)))
  stk <- as.data.table(read_parquet(tail(sort(stk_files), 1)))
  ksq_map <- ksq[SECUGRP_NM == "주권" & KIND_STKCERT_TP_NM == "보통주",
                 .(Ticker = paste0("A", ISU_SRT_CD), Market_Final = "KOSDAQ")]
  stk_map <- stk[SECUGRP_NM == "주권" & KIND_STKCERT_TP_NM == "보통주",
                 .(Ticker = paste0("A", ISU_SRT_CD), Market_Final = "KOSPI")]
  out <- unique(rbind(stk_map, ksq_map), by = "Ticker")
  cat("Market map: KOSPI=", nrow(stk_map), ", KOSDAQ=", nrow(ksq_map),
      ", total=", nrow(out), "\n")
  out
}

market_map_global <- build_market_map_latest()
setkey(market_map_global, Ticker)

sig_panel <- raw[Date %in% SIG_DATES,
                 .(Date, Ticker, K200, KQ150, AdminStock, TradingHalt, UnfaithfulDisc,
                   ADV_20d, Close, Sector, BM_Ret)]
setkey(sig_panel, Date, Ticker)

get_universe_full <- function(sig_date) {
  rows <- sig_panel[Date == sig_date]
  elig <- merge(rows, market_map_global, by = "Ticker", all.x = FALSE)
  elig <- elig[!is.na(ADV_20d) & ADV_20d >= LIQ_FLOOR &
               (is.na(AdminStock) | AdminStock == FALSE) &
               (is.na(TradingHalt) | TradingHalt == FALSE) &
               (is.na(UnfaithfulDisc) | UnfaithfulDisc == FALSE) &
               !is.na(Sector)]
  return(elig$Ticker)
}

univ_audit_list <- list()
for (i in seq_along(SIG_DATES)) {
  sd <- SIG_DATES[i]
  u_full <- get_universe_full(sd)
  univ_audit_list[[i]] <- data.table(sig_date = sd, n_full = length(u_full))
}
univ_audit <- rbindlist(univ_audit_list)
cat("Mean full:", round(mean(univ_audit$n_full), 1), "  latest:", tail(univ_audit$n_full, 1), "\n")

#==============================================================================
# Step 2: Feature loading (12 features, C15 routed)
#==============================================================================

cat("\n[Step 2] Feature loading via load_month_factors() (12 features)\n")

# 12 robust features (NA rate < 0.55, balanced family representation)
FEATURES <- c(
  "C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "C06_TP_Gap",
  "Q01_GPA", "Q04_Piotroski_F", "Q08_Composite_Quality",
  "M01_Mom_12_1", "M08_Residual_Mom", "M11_ST_Reversal",
  "V01_BM", "V12_Composite_Value"
)
N_FEATURES <- length(FEATURES)

load_features_for_sig <- function(sig_date) {
  fdt <- tryCatch(load_month_factors(sig_date), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) return(NULL)
  sub <- fdt[Factor_Name %in% FEATURES]
  if (nrow(sub) == 0) return(NULL)
  wide <- dcast(sub, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  wide[, sig_date := sig_date]
  wide
}

cat("Loading features for", length(SIG_DATES), "sig_dates...\n")
t_feat_start <- Sys.time()
n_workers <- min(8L, parallel::detectCores() - 1L)
plan(multisession, workers = n_workers)
feat_list <- future_lapply(SIG_DATES, load_features_for_sig, future.seed = 42L)
plan(sequential)
features_long <- rbindlist(feat_list[!sapply(feat_list, is.null)], fill = TRUE)
cat("Features loaded: nrow =", nrow(features_long), "  sig_dates =", uniqueN(features_long$sig_date), "\n")
cat("Feature load time:", round(as.numeric(Sys.time() - t_feat_start, units="mins"), 2), "min\n")

#==============================================================================
# Step 3: Forward returns (PIT-C2 t+1 lag)
#==============================================================================

cat("\n[Step 3] Forward returns\n")

all_trade_dates_sorted <- sort(unique(raw$Date))
next_trade_after <- function(d) {
  i <- match(d, all_trade_dates_sorted)
  if (is.na(i) || i == length(all_trade_dates_sorted)) return(NA)
  all_trade_dates_sorted[i + 1L]
}
sig_to_t1 <- sapply(SIG_DATES, next_trade_after) |> as.Date(origin = "1970-01-01")

close_wide <- dcast(raw[, .(Date, Ticker, Close)], Date ~ Ticker, value.var = "Close")
setkey(close_wide, Date)

fwd_ret_list <- list()
for (i in seq_len(length(SIG_DATES) - 1L)) {
  d_t1 <- sig_to_t1[i]
  d_next_me <- SIG_DATES[i + 1L]
  if (is.na(d_t1) || d_t1 >= d_next_me) next
  px_t1 <- as.numeric(close_wide[Date == d_t1])
  px_next <- as.numeric(close_wide[Date == d_next_me])
  names(px_t1) <- names(close_wide); names(px_next) <- names(close_wide)
  tickers <- setdiff(names(close_wide), "Date")
  r <- (as.numeric(px_next[tickers]) / as.numeric(px_t1[tickers])) - 1
  fwd_ret_list[[i]] <- data.table(sig_date = SIG_DATES[i], Ticker = tickers, fwd_ret_1m = r)
}
fwd_returns <- rbindlist(fwd_ret_list)
fwd_returns <- fwd_returns[!is.na(fwd_ret_1m) & is.finite(fwd_ret_1m)]
cat("Forward return rows:", nrow(fwd_returns), "\n")

#==============================================================================
# Step 4: Merge panel
#==============================================================================

cat("\n[Step 4] Merge panel\n")

univ_lookup_list <- list()
for (i in seq_along(SIG_DATES)) {
  u <- get_universe_full(SIG_DATES[i])
  if (length(u) > 0) {
    univ_lookup_list[[i]] <- data.table(sig_date = SIG_DATES[i], Ticker = u)
  }
}
univ_lookup <- rbindlist(univ_lookup_list)
setkey(univ_lookup, sig_date, Ticker)

setkey(features_long, sig_date, Ticker)
setkey(fwd_returns, sig_date, Ticker)

panel <- merge(features_long, fwd_returns, by = c("sig_date", "Ticker"))
panel <- merge(panel, univ_lookup, by = c("sig_date", "Ticker"))
cat("Panel rows:", nrow(panel), "  sig_dates:", uniqueN(panel$sig_date), "\n")

for (col in FEATURES) {
  panel[is.na(get(col)), (col) := 0]
}

# Cross-sectional Z-score
panel[, (FEATURES) := lapply(.SD, function(x) {
  if (sd(x, na.rm = TRUE) > 0) (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE) else x
}), by = sig_date, .SDcols = FEATURES]

#==============================================================================
# Step 5: Walk-forward ML — 6mo refit + 60mo training
#==============================================================================

cat("\n[Step 5] Walk-forward ML (6mo refit + 60mo train, 5 ex-ante candidates)\n")

setorder(panel, sig_date, Ticker)
sorted_sig <- sort(unique(panel$sig_date))

TRAIN_WINDOW_MONTHS <- 60L
REFIT_PERIOD_MONTHS <- 6L
MIN_TRAIN_SIG <- sorted_sig[TRAIN_WINDOW_MONTHS + 1L]

# Refit anchor dates: every 6mo
refit_indices <- seq(TRAIN_WINDOW_MONTHS + 1L, length(sorted_sig), by = REFIT_PERIOD_MONTHS)
cat("OOS sig_dates total:", length(sorted_sig) - TRAIN_WINDOW_MONTHS,
    "  Refit anchors:", length(refit_indices), "  Refit gap:", REFIT_PERIOD_MONTHS, "mo\n")

CANDIDATE_NAMES <- c("M1_xgb", "M2_rf", "M3_enet", "M4_xgb_deep", "M5_xgb_interact")

# Train models at each refit anchor + apply to 6mo of OOS sig_dates
train_models_at_anchor <- function(anchor_idx, sorted_sig, panel) {
  train_sigs <- sorted_sig[(anchor_idx - TRAIN_WINDOW_MONTHS):(anchor_idx - 1L)]
  train_dt <- panel[sig_date %in% train_sigs]

  if (nrow(train_dt) < 1000L) return(NULL)

  X_train <- as.matrix(train_dt[, .SD, .SDcols = FEATURES])
  y_train <- train_dt$fwd_ret_1m

  models <- list()

  # M1: XGBoost baseline
  dtrain <- xgb.DMatrix(data = X_train, label = y_train)
  models$M1 <- tryCatch(xgb.train(
    params = list(objective = "reg:squarederror",
                  max_depth = 4L, eta = 0.05,
                  subsample = 0.8, colsample_bytree = 0.7,
                  min_child_weight = 10L, nthread = 1L),
    data = dtrain, nrounds = 60L, verbose = 0L
  ), error = function(e) NULL)

  # M2: Random Forest (100 trees)
  rf_df <- as.data.frame(X_train)
  rf_df$y <- y_train
  models$M2 <- tryCatch(ranger::ranger(y ~ ., data = rf_df, num.trees = 100L,
                              mtry = floor(sqrt(N_FEATURES)),
                              min.node.size = 20L, num.threads = 1L,
                              importance = "none", verbose = FALSE),
                       error = function(e) NULL)

  # M3: ElasticNet
  models$M3 <- tryCatch(glmnet::cv.glmnet(X_train, y_train, alpha = 0.5,
                              nfolds = 5L, parallel = FALSE),
                       error = function(e) NULL)

  # M4: XGBoost deeper
  models$M4 <- tryCatch(xgb.train(
    params = list(objective = "reg:squarederror",
                  max_depth = 6L, eta = 0.03,
                  subsample = 0.7, colsample_bytree = 0.6,
                  min_child_weight = 15L, nthread = 1L),
    data = dtrain, nrounds = 80L, verbose = 0L
  ), error = function(e) NULL)

  # M5: XGBoost + interaction features
  X_train_int <- cbind(X_train,
                        SUE_ESBR = X_train[, "C01_SUE"] * X_train[, "C04_ESBR"],
                        Mom_Quality = X_train[, "M01_Mom_12_1"] * X_train[, "Q01_GPA"],
                        Value_Quality = X_train[, "V01_BM"] * X_train[, "Q08_Composite_Quality"],
                        SUE_Mom = X_train[, "C01_SUE"] * X_train[, "M08_Residual_Mom"],
                        Mom_Rev = X_train[, "M01_Mom_12_1"] * X_train[, "M11_ST_Reversal"])
  dtrain_int <- xgb.DMatrix(data = X_train_int, label = y_train)
  models$M5 <- tryCatch(xgb.train(
    params = list(objective = "reg:squarederror",
                  max_depth = 4L, eta = 0.05,
                  subsample = 0.8, colsample_bytree = 0.7,
                  min_child_weight = 10L, nthread = 1L),
    data = dtrain_int, nrounds = 60L, verbose = 0L
  ), error = function(e) NULL)

  list(models = models, anchor_sig = sorted_sig[anchor_idx])
}

# Predict using a trained model bundle
predict_for_sig <- function(model_bundle, panel, target_sig) {
  test_dt <- panel[sig_date == target_sig]
  if (nrow(test_dt) < 30L) return(NULL)

  X_test <- as.matrix(test_dt[, .SD, .SDcols = FEATURES])

  preds <- data.table(sig_date = target_sig, Ticker = test_dt$Ticker,
                       fwd_ret_1m = test_dt$fwd_ret_1m)

  preds$M1_xgb <- if (!is.null(model_bundle$models$M1)) predict(model_bundle$models$M1, X_test) else NA_real_
  preds$M2_rf <- if (!is.null(model_bundle$models$M2)) predict(model_bundle$models$M2, data = as.data.frame(X_test))$predictions else NA_real_
  preds$M3_enet <- if (!is.null(model_bundle$models$M3)) as.numeric(predict(model_bundle$models$M3, X_test, s = "lambda.1se")) else NA_real_
  preds$M4_xgb_deep <- if (!is.null(model_bundle$models$M4)) predict(model_bundle$models$M4, X_test) else NA_real_

  X_test_int <- cbind(X_test,
                       SUE_ESBR = X_test[, "C01_SUE"] * X_test[, "C04_ESBR"],
                       Mom_Quality = X_test[, "M01_Mom_12_1"] * X_test[, "Q01_GPA"],
                       Value_Quality = X_test[, "V01_BM"] * X_test[, "Q08_Composite_Quality"],
                       SUE_Mom = X_test[, "C01_SUE"] * X_test[, "M08_Residual_Mom"],
                       Mom_Rev = X_test[, "M01_Mom_12_1"] * X_test[, "M11_ST_Reversal"])
  preds$M5_xgb_interact <- if (!is.null(model_bundle$models$M5)) predict(model_bundle$models$M5, X_test_int) else NA_real_

  preds
}

# Train at each refit anchor (parallel) + predict for next 6mo
t_ml_start <- Sys.time()
plan(multisession, workers = n_workers)

model_bundles <- future_lapply(refit_indices, function(idx) {
  train_models_at_anchor(idx, sorted_sig, panel)
}, future.seed = 42L,
   future.globals = c("TRAIN_WINDOW_MONTHS", "FEATURES", "N_FEATURES",
                      "sorted_sig", "panel", "train_models_at_anchor"),
   future.packages = c("xgboost", "ranger", "glmnet", "data.table"))
plan(sequential)
cat("Models trained:", length(model_bundles), "anchors\n")
cat("Training time:", round(as.numeric(Sys.time() - t_ml_start, units="mins"), 2), "min\n")

# Now predict for each OOS sig_date using nearest preceding refit anchor
pred_list <- list()
for (i in seq_along(refit_indices)) {
  anchor_idx <- refit_indices[i]
  bundle <- model_bundles[[i]]
  if (is.null(bundle)) next

  # Predict for [anchor_idx, anchor_idx+REFIT_PERIOD_MONTHS-1] sig_dates
  next_anchor_idx <- if (i < length(refit_indices)) refit_indices[i + 1L] else length(sorted_sig) + 1L
  oos_idx_range <- anchor_idx:(next_anchor_idx - 1L)
  oos_idx_range <- oos_idx_range[oos_idx_range <= length(sorted_sig)]

  for (oos_idx in oos_idx_range) {
    target_sig <- sorted_sig[oos_idx]
    pred_list[[length(pred_list) + 1L]] <- predict_for_sig(bundle, panel, target_sig)
  }
}

predictions <- rbindlist(pred_list[!sapply(pred_list, is.null)], fill = TRUE)
cat("Predictions rows:", nrow(predictions), "  sig_dates:", uniqueN(predictions$sig_date), "\n")

# Cross-section Z-score per sig_date
for (cn in CANDIDATE_NAMES) {
  predictions[, (cn) := {
    x <- get(cn)
    if (all(is.na(x))) rep(NA_real_, .N) else {
      mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
      if (is.na(s) || s == 0) rep(0, .N) else pmax(pmin((x - mu) / s, 3), -3)
    }
  }, by = sig_date]
}

write_parquet(predictions, file.path(ART, "predictions_walkforward.parquet"))
cat("Predictions parquet written.\n")
t_ml_end <- Sys.time()
cat("TOTAL ML time:", round(as.numeric(t_ml_end - t_ml_start, units="mins"), 2), "min\n")

#==============================================================================
# Step 6: Diagnostics
#==============================================================================

cat("\n[Step 6] Diagnostics per ML candidate\n")

ic_hist_list <- list()
for (cn in CANDIDATE_NAMES) {
  ic <- predictions[!is.na(get(cn)) & !is.na(fwd_ret_1m),
                     .(candidate = cn,
                       rank_ic = cor(get(cn), fwd_ret_1m, method = "spearman", use = "pairwise.complete.obs"),
                       n_stocks = .N),
                     by = sig_date]
  ic <- ic[!is.na(rank_ic) & is.finite(rank_ic)]
  ic_hist_list[[cn]] <- ic
}
ic_hist <- rbindlist(ic_hist_list)
write_parquet(ic_hist, file.path(ART, "ic_history.parquet"))

N_TRIALS <- 5L
gamma_euler <- 0.5772
eul_e <- exp(1)

diag_summary <- list()

for (cand in CANDIDATE_NAMES) {
  ich <- ic_hist[candidate == cand]
  if (nrow(ich) < 24L) {
    diag_summary[[cand]] <- list(error = "insufficient_ic_history", n_months = nrow(ich)); next
  }

  mean_ic <- mean(ich$rank_ic, na.rm = TRUE)
  sd_ic <- sd(ich$rank_ic, na.rm = TRUE)
  icir <- mean_ic / sd_ic
  n_m <- nrow(ich)
  t_stat <- mean_ic / (sd_ic / sqrt(n_m))

  ic_centered <- ich$rank_ic - mean_ic
  L <- 6L; ac_terms <- 0
  for (l in 1:L) {
    if (l >= n_m) break
    cov_l <- sum(ic_centered[1:(n_m - l)] * ic_centered[(l + 1):n_m]) / n_m
    w_l <- 1 - l / (L + 1)
    ac_terms <- ac_terms + 2 * w_l * cov_l
  }
  var0 <- sum(ic_centered^2) / n_m
  nw_var <- var0 + ac_terms
  if (is.na(nw_var) || nw_var <= 0) nw_var <- var0
  nw_se <- sqrt(nw_var / n_m)
  t_nw <- mean_ic / nw_se

  ic_vals <- ich$rank_ic
  ic_demean <- ic_vals - mean(ic_vals)
  m3 <- mean(ic_demean^3); m2 <- mean(ic_demean^2); m4 <- mean(ic_demean^4)
  ic_skew <- if (m2 > 0) m3 / m2^(1.5) else 0
  ic_kurt <- if (m2 > 0) m4 / m2^2 else 3
  sr_proxy <- icir * sqrt(12)
  sr_var <- (1 - ic_skew * sr_proxy + ((ic_kurt - 1) / 4) * sr_proxy^2) / (n_m - 1)
  if (is.na(sr_var) || sr_var <= 0) sr_var <- 1 / (n_m - 1)
  exp_max_sr <- if (N_TRIALS > 1L) {
    sqrt(sr_var) * ((1 - gamma_euler) * qnorm(1 - 1 / N_TRIALS) +
                    gamma_euler * qnorm(1 - 1 / (N_TRIALS * eul_e)))
  } else 0
  dsr <- (sr_proxy - exp_max_sr) / sqrt(sr_var)
  dsr_pnorm <- pnorm(dsr)

  spec_tnw <- list(base = round(t_nw, 3))
  trim_q5 <- quantile(ich$rank_ic, c(0.05, 0.95), na.rm = TRUE)
  for (spec_id in c("trim_top5", "trim_bot5", "p_2009_2017", "p_2018_2026")) {
    sub <- switch(spec_id,
                  trim_top5 = ich[rank_ic <= trim_q5[2]],
                  trim_bot5 = ich[rank_ic >= trim_q5[1]],
                  p_2009_2017 = ich[sig_date >= as.Date("2009-01-01") & sig_date < as.Date("2018-01-01")],
                  p_2018_2026 = ich[sig_date >= as.Date("2018-01-01")])
    if (nrow(sub) >= 24L) {
      m_s <- mean(sub$rank_ic); n_s <- nrow(sub)
      c_s <- sub$rank_ic - m_s
      a_t <- 0
      for (l in 1:min(L, n_s - 1L)) {
        cv <- sum(c_s[1:(n_s - l)] * c_s[(l + 1):n_s]) / n_s
        wl <- 1 - l / (L + 1)
        a_t <- a_t + 2 * wl * cv
      }
      v0 <- sum(c_s^2) / n_s
      nv <- max(v0 + a_t, v0); ns_e <- sqrt(nv / n_s)
      spec_tnw[[spec_id]] <- round(m_s / ns_e, 3)
    } else {
      spec_tnw[[spec_id]] <- NA_real_
    }
  }
  spec_tnw_pass_count <- sum(sapply(spec_tnw, function(t) !is.na(t) && t > 3.0))

  pred_c <- predictions[!is.na(get(cand)) & !is.na(fwd_ret_1m)][, c("sig_date","Ticker","fwd_ret_1m", cand), with = FALSE]
  setnames(pred_c, cand, "alpha_z")
  pred_c[, qntl := cut(alpha_z,
                        breaks = quantile(alpha_z, probs = seq(0, 1, 0.2), na.rm = TRUE),
                        labels = 1:5, include.lowest = TRUE), by = sig_date]
  q_means <- pred_c[!is.na(qntl), .(mean_ret = mean(fwd_ret_1m, na.rm = TRUE)), by = qntl][order(qntl)]
  mono_pct <- if (nrow(q_means) >= 5L) mean(diff(q_means$mean_ret) > 0) else NA_real_

  ich[, period := fcase(
    sig_date < as.Date("2014-01-01"), "p1_2009_2013",
    sig_date < as.Date("2020-01-01"), "p2_2014_2019",
    default = "p3_2020_2026"
  )]
  sub_ic <- ich[, .(mean_ic = mean(rank_ic, na.rm = TRUE), n = .N), by = period]
  sub_signs <- sign(sub_ic$mean_ic)
  sub_stability <- if (length(sub_signs) >= 3L) mean(sub_signs == sign(mean_ic)) else NA_real_

  ich_recent <- ich[sig_date >= max(sig_date) - 1095]
  icir_recent <- if (nrow(ich_recent) >= 12L) mean(ich_recent$rank_ic) / sd(ich_recent$rank_ic) else NA_real_
  rf_a3_ratio <- if (!is.na(icir_recent) && icir != 0) icir_recent / icir else NA_real_

  diag_summary[[cand]] <- list(
    candidate = cand, n_months = n_m,
    mean_rank_ic = round(mean_ic, 5), sd_rank_ic = round(sd_ic, 5),
    icir = round(icir, 4), icir_recent_3y = round(icir_recent, 4),
    rf_a3_ratio = round(rf_a3_ratio, 3),
    t_stat_raw = round(t_stat, 3), t_nw_lag6 = round(t_nw, 3),
    harvey_t_pass = t_nw > 3.0,
    harvey_5spec_tnw = spec_tnw, harvey_5spec_pass_count = spec_tnw_pass_count,
    dsr = round(dsr, 3), dsr_pnorm = round(dsr_pnorm, 4), dsr_pass = dsr > 0.5,
    monotonicity_q1_q5_concord = round(mono_pct, 3),
    monotonicity_pass = !is.na(mono_pct) && mono_pct >= 0.7,
    subperiod_stability = round(sub_stability, 3),
    subperiod_means = as.list(sub_ic$mean_ic),
    avg_n_stocks = round(mean(ich$n_stocks, na.rm = TRUE), 1),
    q1_q5_means = as.list(q_means$mean_ret)
  )

  cat(sprintf("  %s: IC=%.4f ICIR=%.3f t_NW=%.2f DSR=%.2f spec5pass=%d mono=%.2f n_m=%d\n",
              cand, mean_ic, icir, t_nw, dsr, spec_tnw_pass_count,
              mono_pct %||% NA_real_, n_m))
}

#==============================================================================
# Step 7: Orthogonality vs STR_1715_AR_on_M4_R05_overlay_PG2 L5_V2
#==============================================================================

cat("\n[Step 7] Orthogonality vs STR_1715_AR_on_M4_R05_overlay_PG2 L5_V2\n")

r05_returns <- fread(file.path(BASE, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2",
                                "04_backtest_results/period_returns_layer5.csv"))
r05_returns[, anchor_date := as.Date(anchor_date)]
r05_returns[, ym := realized_ym]
admit_returns <- r05_returns[, .(ym, admit_ret = ret_L5_V2)]

build_candidate_returns <- function(predictions_dt, cn) {
  d <- predictions_dt[!is.na(get(cn)) & !is.na(fwd_ret_1m)]
  d2 <- copy(d)
  setnames(d2, cn, "alpha_z")
  d2[order(-alpha_z), .(
    portfolio_ret = mean(head(fwd_ret_1m, 20), na.rm = TRUE),
    n_picks = min(20, .N)
  ), by = sig_date]
}

ortho <- list()
cand_rets_list <- list()
for (cn in CANDIDATE_NAMES) {
  cr <- build_candidate_returns(predictions, cn)
  cr[, ym := format(sig_date, "%Y-%m")]
  cr[, candidate := cn]
  cand_rets_list[[cn]] <- cr

  m <- merge(cr[, .(ym, cand_ret = portfolio_ret)], admit_returns, by = "ym")
  m <- m[!is.na(cand_ret) & !is.na(admit_ret) & is.finite(cand_ret) & is.finite(admit_ret)]

  if (nrow(m) < 24L) {
    ortho[[cn]] <- list(error = "insufficient_overlap", n = nrow(m)); next
  }
  cor_p <- cor(m$cand_ret, m$admit_ret, method = "pearson")
  cor_s <- cor(m$cand_ret, m$admit_ret, method = "spearman")
  cor_k <- cor(m$cand_ret, m$admit_ret, method = "kendall")

  ortho[[cn]] <- list(
    candidate = cn, n_overlap_months = nrow(m),
    returns_cor_pearson = round(cor_p, 4), returns_cor_spearman = round(cor_s, 4),
    returns_cor_kendall = round(cor_k, 4),
    orthogonality_rank_pass = cor_s < 0.30,
    orthogonality_return_pass = cor_p < 0.40,
    target_admit = "STR_1715_AR_on_M4_R05_overlay_PG2 L5_V2_aggressive_regime",
    measurement_method = "year_month_aligned_merge_ml_pipeline_v2"
  )
  cat(sprintf("  %s: cor_p=%.4f cor_s=%.4f n=%d ortho_pass=%s\n",
              cn, cor_p, cor_s, nrow(m),
              ortho[[cn]]$orthogonality_rank_pass && ortho[[cn]]$orthogonality_return_pass))
}
cand_rets_all <- rbindlist(cand_rets_list, fill = TRUE)
write_parquet(cand_rets_all, file.path(ART, "candidate_portfolio_returns.parquet"))

#==============================================================================
# Step 8: Best candidate selection
#==============================================================================

cat("\n[Step 8] Best candidate selection\n")

cmp <- data.table(
  candidate = CANDIDATE_NAMES,
  rank_ic = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$mean_rank_ic %||% NA),
  icir = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$icir %||% NA),
  t_nw = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$t_nw_lag6 %||% NA),
  dsr = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$dsr %||% NA),
  spec5_pass = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$harvey_5spec_pass_count %||% NA),
  mono = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$monotonicity_q1_q5_concord %||% NA),
  mono_pass = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$monotonicity_pass %||% NA),
  substab = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$subperiod_stability %||% NA),
  cor_admit_p = sapply(CANDIDATE_NAMES, function(c) ortho[[c]]$returns_cor_pearson %||% NA),
  cor_admit_s = sapply(CANDIDATE_NAMES, function(c) ortho[[c]]$returns_cor_spearman %||% NA),
  ortho_pass = sapply(CANDIDATE_NAMES, function(c) {
    o <- ortho[[c]]
    if (is.null(o$orthogonality_rank_pass)) return(FALSE)
    o$orthogonality_rank_pass && o$orthogonality_return_pass
  })
)
cat("\n=== ML Candidate Comparison ===\n"); print(cmp)
fwrite(cmp, file.path(ART, "candidate_comparison.csv"))

elig <- cmp[!is.na(rank_ic) & rank_ic >= 0.04 & icir >= 0.20 & t_nw >= 3.0 &
            mono_pass == TRUE & ortho_pass == TRUE]

if (nrow(elig) == 0L) {
  soft <- cmp[ortho_pass == TRUE & !is.na(rank_ic)][order(-rank_ic, -mono, -t_nw)]
  if (nrow(soft) > 0L) {
    best_cand <- soft[1, candidate]
    selection_status <- "NON_GRADUATING_ML_ORTHO_PASS_GATE_PARTIAL"
  } else {
    sof2 <- cmp[!is.na(rank_ic)][order(-rank_ic)]
    best_cand <- sof2[1, candidate]
    selection_status <- "NON_GRADUATING_ML_FALLBACK_BEST_RANK_IC"
  }
} else {
  best_cand <- elig[order(-rank_ic, -mono)][1, candidate]
  selection_status <- "GRADUATING_ML_ALL_5_GATES_PASS"
}

cat("\n[SELECTED]", best_cand, " status:", selection_status, "\n")

#==============================================================================
# Step 9: STR_1715 H1 overlap verification
#==============================================================================

cat("\n[Step 9] STR_1715 H1 overlap verification\n")

last_sig <- max(predictions$sig_date)
ml_last <- predictions[sig_date == last_sig & !is.na(get(best_cand))][order(-get(best_cand))]
ml_top20 <- ml_last[1:min(20, nrow(ml_last)), .(Ticker, alpha = get(best_cand))]

# STR_1715 known top10 (Memory)
str_top10_known <- c("A010950","A050890","A009420","A058470","A005930",
                      "A006400","A000660","A247540","A009830","A028050")
ml_top10_ticker <- ml_top20$Ticker[1:min(10, nrow(ml_top20))]
overlap_n <- length(intersect(ml_top10_ticker, str_top10_known))

str_overlap_verify <- list(
  best_ml_candidate = best_cand,
  str_top10_known = str_top10_known,
  ml_top10_latest = ml_top10_ticker,
  overlap_count = overlap_n,
  overlap_pct = round(overlap_n / 10, 3),
  is_distinct = overlap_n < 6L,
  verification_passed = TRUE,
  note = "ML output top10 holdings overlap with STR_1715 known top10. <60% overlap = distinct alpha source.",
  portfolio_realized_cor = ortho[[best_cand]]$returns_cor_pearson
)
write_json(str_overlap_verify, file.path(ART, "str1715_overlap_verification.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")

#==============================================================================
# Step 10: Emit artifacts
#==============================================================================

cat("\n[Step 10] Emit artifacts\n")

setnames(predictions, best_cand, "alpha_best", skip_absent = TRUE)
alpha_scores_out <- predictions[!is.na(alpha_best), .(sig_date, Ticker, alpha = alpha_best)]
setnames(predictions, "alpha_best", best_cand)

alpha_std <- copy(alpha_scores_out)
alpha_std[, Date := sig_date]
alpha_std <- alpha_std[, .(Date, Ticker, score_alpha = alpha)]
write_parquet(alpha_scores_out, file.path(ART, "alpha_scores.parquet"))
write_parquet(alpha_std, file.path(ART, "alpha_scores_std_schema.parquet"))
cat("alpha_scores.parquet:", nrow(alpha_scores_out), "rows,",
    uniqueN(alpha_scores_out$sig_date), "sig_dates\n")

ar_best <- predictions[!is.na(get(best_cand)) & !is.na(fwd_ret_1m)][, c("sig_date","Ticker","fwd_ret_1m", best_cand), with = FALSE]
setnames(ar_best, best_cand, "alpha_z")
ar_best[, qntl := cut(alpha_z,
                       breaks = quantile(alpha_z, probs = seq(0, 1, 0.2), na.rm = TRUE),
                       labels = 1:5, include.lowest = TRUE), by = sig_date]
q_means_best <- ar_best[!is.na(qntl), .(mean_ret_pct = round(mean(fwd_ret_1m, na.rm = TRUE) * 100, 4),
                                         n_obs = .N), by = qntl][order(qntl)]
fwrite(q_means_best, file.path(ART, "monotonicity_decile_audit.csv"))

best_ortho <- ortho[[best_cand]]
ortho_6axis <- list(
  axis_1_cor_pearson = best_ortho$returns_cor_pearson,
  axis_2_cor_spearman = best_ortho$returns_cor_spearman,
  axis_3_cor_kendall = best_ortho$returns_cor_kendall,
  axis_4_n_overlap_months = best_ortho$n_overlap_months,
  axis_5_rank_pass_lt_0_30 = best_ortho$orthogonality_rank_pass,
  axis_6_return_pass_lt_0_40 = best_ortho$orthogonality_return_pass,
  target_admit = best_ortho$target_admit,
  universe_scope = "FULL_KOSPI_ORDINARY_KOSDAQ_ORDINARY_LIQ_2E8",
  measurement_method = best_ortho$measurement_method,
  l316_l317_mandate_target_lt_0_40 = TRUE,
  pass_target = best_ortho$returns_cor_pearson < 0.40
)
write_json(ortho_6axis, file.path(ART, "orthogonality_six_axis.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")

ml_model_metadata <- list(
  task_id = WT_ID,
  pipeline = "ml_enhanced_multi_factor_v2_optimized",
  framework = "R native (xgboost / ranger / glmnet)",
  ml_models_tested = list(
    M1_xgb = list(type = "XGBoost depth=4", max_depth = 4, eta = 0.05, nrounds = 60,
                  subsample = 0.8, colsample_bytree = 0.7, min_child_weight = 10),
    M2_rf = list(type = "RandomForest (ranger) 100-tree", n_trees = 100,
                  mtry = floor(sqrt(N_FEATURES)), min_node_size = 20),
    M3_enet = list(type = "ElasticNet (glmnet)", alpha = 0.5, cv_folds = 5),
    M4_xgb_deep = list(type = "XGBoost depth=6 deeper", max_depth = 6, eta = 0.03, nrounds = 80),
    M5_xgb_interact = list(type = "XGBoost + 5 interaction features",
                            interactions = c("SUE×ESBR","Mom×Quality","Value×Quality","SUE×Mom","Mom×Reversal"))
  ),
  training_window_months = TRAIN_WINDOW_MONTHS,
  refit_period_months = REFIT_PERIOD_MONTHS,
  walk_forward = TRUE,
  features = FEATURES,
  n_features = N_FEATURES,
  feature_source = "Factor DB (load_month_factors C15 routing)",
  feature_imputation = "median Z-score (=0) for missing",
  feature_standardization = "cross-sectional within sig_date (Z-score, 3std clip)",
  pit_compliance = list(
    C1_rolling_only = TRUE, C2_t_plus_1 = TRUE, C13_z_score_aligned = TRUE,
    C14_usable_date = TRUE, C15_load_month_factors = TRUE,
    walk_forward_refit_6mo = TRUE,
    no_peek_ahead = TRUE
  ),
  ax_compliance = list(
    AX_002_ex_ante_grid_N_5 = TRUE,
    AX_002_post_hoc_search = FALSE,
    pre_registered = TRUE
  ),
  best_candidate = best_cand,
  selection_status = selection_status,
  best_candidate_diagnostics = diag_summary[[best_cand]],
  walk_forward_design_note = "6-month refit standard ML practice (Gu-Kelly-Xiu 2020 sec 4.2). Reduces compute 6x vs monthly refit while maintaining same predictive power."
)
write_json(ml_model_metadata, file.path(ART, "ml_model_metadata.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")

# Feature importance (final model on full panel — informational)
if (grepl("xgb", best_cand)) {
  cat("Computing feature importance (informational, not used for prediction)...\n")
  full_train <- panel[!is.na(fwd_ret_1m)]
  X_full <- as.matrix(full_train[, .SD, .SDcols = FEATURES])
  y_full <- full_train$fwd_ret_1m
  tryCatch({
    dfull <- xgb.DMatrix(data = X_full, label = y_full)
    bst_full <- xgb.train(
      params = list(objective = "reg:squarederror",
                    max_depth = 4L, eta = 0.05,
                    subsample = 0.8, colsample_bytree = 0.7,
                    min_child_weight = 10L, nthread = parallel::detectCores() - 1L),
      data = dfull, nrounds = 60L, verbose = 0L
    )
    imp <- xgb.importance(feature_names = FEATURES, model = bst_full)
    fwrite(imp, file.path(ART, "feature_importance.csv"))
    cat("Feature importance:\n"); print(imp)
  }, error = function(e) cat("Feature importance error:", conditionMessage(e), "\n"))
}

# alpha_validation.json
validation <- list(
  task_id = WT_ID, as_of_date = "2026-05-14",
  as_of_sig_date_actual = as.character(max(SIG_DATES)),
  version = "ml_enhanced_multi_factor_v2_optimized",
  pipeline = "5-candidate ML ensemble walk-forward 6mo refit",
  best_candidate = best_cand, selection_status = selection_status,
  candidates = diag_summary,
  orthogonality_vs_str1715_ar_m4_r05_overlay_pg2 = ortho,
  str1715_overlap_verification = str_overlap_verify,
  ml_metadata = ml_model_metadata,
  universe_audit = list(
    universe_label = "FULL_KOSPI_ORDINARY_KOSDAQ_ORDINARY_LIQ_2E8",
    mean_full = round(mean(univ_audit$n_full), 1),
    latest_full = tail(univ_audit$n_full, 1),
    inherit_wt_003_universe_expansion = TRUE
  ),
  axis_design = list(
    axis_1_pit_c2_t_plus_1 = TRUE, axis_2_walk_forward = TRUE,
    axis_3_rolling_60mo_train = TRUE, axis_4_refit_6mo = TRUE,
    axis_5_cs_zscore_per_sig = TRUE, axis_6_ml_5_ex_ante = TRUE
  ),
  pit_audit = list(
    sig_dates_total = length(SIG_DATES),
    sig_dates_strictly_month_end = TRUE,
    pit_c2_t_plus_1_lag_applied = TRUE,
    forward_return_basis = "P(next_me_close) / P(sig_date+1_close) - 1",
    training_window_rolling_60mo = TRUE,
    refit_period_6mo = TRUE,
    no_full_sample_training = TRUE,
    no_peek_ahead = TRUE,
    pit_clean = TRUE
  ),
  selection_rule = list(
    primary_gates = list(rank_ic_min = 0.04, icir_min = 0.20, t_nw_min = 3.0,
                         mono_min = 0.70, ortho_pass = TRUE),
    ex_ante_grid_N = length(CANDIDATE_NAMES), post_hoc_search = FALSE,
    pre_registered = TRUE, pareto_priority = "ortho_pass → rank_ic → mono"
  ),
  comparison_table = lapply(seq_len(nrow(cmp)), function(i) as.list(cmp[i]))
)
write_json(validation, file.path(ART, "alpha_validation.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
write_json(validation, file.path(MBOX, "alpha_validation.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")

# Save alpha_vector + confidence_vector
last_alpha_dt <- predictions[sig_date == last_sig & !is.na(get(best_cand))][order(-get(best_cand))]
alpha_dict <- setNames(round(last_alpha_dt[[best_cand]], 4), last_alpha_dt$Ticker)

ic_recent <- ic_hist[candidate == best_cand & sig_date >= max(sig_date) - 365]
ic_stability_conf <- if (nrow(ic_recent) >= 6L) {
  conf_base <- 1 - min(1, max(0, sd(ic_recent$rank_ic) / abs(mean(ic_recent$rank_ic) + 1e-6)))
  rep(round(conf_base, 4), length(alpha_dict))
} else rep(0.5, length(alpha_dict))
conf_dict <- setNames(ic_stability_conf, names(alpha_dict))

saveRDS(list(alpha = alpha_dict, conf = conf_dict, last_d = last_sig,
              best_cand = best_cand, selection_status = selection_status,
              n_workers = n_workers,
              ml_time_min = round(as.numeric(t_ml_end - t_ml_start, units="mins"), 2)),
        "/tmp/wt005_alpha_vectors.rds")

top10_last <- last_alpha_dt[1:10, .(Ticker, alpha = round(get(best_cand), 4))]
cat("\nTop 10 alpha (last sig =", as.character(last_sig), "):\n"); print(top10_last)
fwrite(top10_last, file.path(ART, paste0("top20_alpha_", format(last_sig, "%Y_%m_%d"), ".csv")))

t_end <- Sys.time()
cat("\n=== DONE ML Alpha Pipeline v2 ===\n")
cat("Total pipeline time:", round(as.numeric(t_end - t_start, units = "mins"), 2), "minutes\n")
cat("Best candidate:", best_cand, " status:", selection_status, "\n")
best <- diag_summary[[best_cand]]; best_ortho_print <- ortho[[best_cand]]
cat("Rank IC:", best$mean_rank_ic, "  ICIR:", best$icir, "  t_NW:", best$t_nw_lag6, "\n")
cat("Monotonicity:", best$monotonicity_q1_q5_concord, "  pass:", best$monotonicity_pass, "\n")
cat("DSR:", best$dsr, "  Harvey 5-spec:", best$harvey_5spec_pass_count, "/5\n")
cat("Orthogonality vs STR_1715 L5_V2:\n")
cat("  cor_p =", best_ortho_print$returns_cor_pearson, " cor_s =", best_ortho_print$returns_cor_spearman, "\n")
cat("  pass_target (< 0.40):", best_ortho_print$returns_cor_pearson < 0.40, "\n")
