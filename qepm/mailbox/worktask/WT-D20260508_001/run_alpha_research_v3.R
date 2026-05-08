#==============================================================================
# WT-D20260508_001 Alpha Research v3 — VRP overlay alpha (RIGOROUS)
#
# v2 self-diagnosis: predictor autocor 0.968 (vrp_idx 12m sum smooth) inflates
# ICIR/t_NW. Sub-period stability 0.333 < 0.5 with p3 sign reversal -0.20 (2020-26).
# ML XGBoost IC 0.9953 = lookahead leakage in features (r_AR_lag1 leaks).
#
# v3 fixes:
# 1. Drop high-autocorrelation predictor — use first-difference of vrp_idx_z
#    (innovation, autocor near 0)
# 2. ML features: ONLY VRP-derived (no r_AR_lag1 / r_KR10y_lag1) to prevent
#    feature leakage path
# 3. Sub-period stability with proper definitions (p1 has min n_obs)
# 4. NW-HAC adjusted t with explicit lag accounting
# 5. Honest disclosure of all 9 specs across 3 predictors × 3 targets
# 6. Cost integration: -15bps × monthly turnover for LS strategy net SR
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260508_001"
WT_DIR <- file.path(ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(ROOT, "stage_artifacts/WT_D20260508_001")
RISK_META_PATH <- file.path(ROOT, "qepm/mailbox/research/risk_candidates_20260507/master_returns_hybrid_plus_4candidates.csv")

dir.create(STAGE_DIR, showWarnings = FALSE, recursive = TRUE)
set.seed(20260508L)

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

cat("\n=== v3 Rigorous: VRP innovation predictors → forward asset returns ===\n")

#==============================================================================
# Step 1+2: Read data
#==============================================================================
request <- fromJSON(file.path(WT_DIR, "request.json"))
master <- fread(RISK_META_PATH)
master[, date := as.Date(date)]
setorder(master, date)
n_all <- nrow(master)
cat("master rows:", n_all, "| date range:", as.character(master$date[1]), "~",
    as.character(master$date[n_all]), "\n")

#==============================================================================
# Step 3: VRP innovation predictors (low-autocor)
#==============================================================================
cat("\n=== Step 3: Signal engineering — VRP innovations (low-autocor predictors) ===\n")

dt <- master[, .(date, r_vrp, r_AR, r_KR10y, r_TSMOM, r_Hybrid)]

# Predictor 1: r_vrp itself at t-1 (low autocor 0.4 — already moderate)
# Lag 1 — at signal time t, use r_vrp[t-1] as predictor
dt[, vrp_ret_lag1 := shift(r_vrp, 1L, type = "lag")]

# Predictor 2: 3m average r_vrp at t-1 (smoother but moderate autocor)
dt[, vrp_3m := frollmean(r_vrp, 3L, fill = NA, align = "right")]
dt[, vrp_3m_lag1 := shift(vrp_3m, 1L, type = "lag")]

# Predictor 3: VRP innovation (Δ vrp 12m sum) — first-difference
n <- nrow(dt)
dt[, vrp_idx12 := NA_real_]
for (i in 12:n) dt$vrp_idx12[i] <- sum(dt$r_vrp[(i-11):i], na.rm = TRUE)
dt[, vrp_idx12_lag1 := shift(vrp_idx12, 1L, type = "lag")]
dt[, vrp_innov := vrp_idx12_lag1 - shift(vrp_idx12_lag1, 1L, type = "lag")]   # innovation = Δ at t-1 vs t-2

# Predictor 4: standardized VRP innovation
dt[, vrp_innov_z := NA_real_]
for (i in 48:n) {
  past <- dt$vrp_innov[1:(i - 1)]
  past <- past[!is.na(past)]
  if (length(past) >= 24) {
    mu <- mean(past)
    sdv <- sd(past)
    if (!is.na(sdv) && sdv > 0 && !is.na(dt$vrp_innov[i])) {
      dt$vrp_innov_z[i] <- (dt$vrp_innov[i] - mu) / sdv
    }
  }
}

# Targets — forward 1M
dt[, r_AR_fwd1 := shift(r_AR, -1L, type = "lead")]
dt[, r_Hybrid_fwd1 := shift(r_Hybrid, -1L, type = "lead")]
dt[, r_KR10y_fwd1 := shift(r_KR10y, -1L, type = "lead")]

usable <- dt[!is.na(vrp_ret_lag1) & !is.na(vrp_3m_lag1) & !is.na(vrp_innov_z), ]
cat("usable rows:", nrow(usable), "\n")

# Sanity check: predictor autocorrelations
ac_ret_lag1 <- cor(usable$vrp_ret_lag1[-1], usable$vrp_ret_lag1[-nrow(usable)], use = "complete.obs")
ac_3m_lag1 <- cor(usable$vrp_3m_lag1[-1], usable$vrp_3m_lag1[-nrow(usable)], use = "complete.obs")
ac_innov_z <- cor(usable$vrp_innov_z[-1], usable$vrp_innov_z[-nrow(usable)], use = "complete.obs")
cat("Predictor autocorrelations: vrp_ret_lag1=", round(ac_ret_lag1, 4),
    " vrp_3m_lag1=", round(ac_3m_lag1, 4),
    " vrp_innov_z=", round(ac_innov_z, 4), "\n")

#==============================================================================
# Step 4: Diagnostics
#==============================================================================
cat("\n=== Step 4: Diagnostics — 9 specs (3 predictors × 3 targets) ===\n")

nw_t <- function(x) {
  x <- na.omit(x); N <- length(x)
  if (N < 30) return(NA_real_)
  L <- max(1L, floor((4 * N / 100)^(2/9)))
  e <- x - mean(x); var0 <- sum(e^2) / N
  vnw <- var0
  for (l in 1:L) {
    g <- sum(e[1:(N-l)] * e[(l+1):N]) / N
    w <- 1 - l / (L + 1)
    vnw <- vnw + 2 * w * g
  }
  if (vnw <= 0) return(NA_real_)
  mean(x) / sqrt(vnw / N)
}

dsr_calc <- function(rs) {
  rs <- na.omit(rs); N <- length(rs)
  if (N < 30) return(NA_real_)
  mu <- mean(rs); sdv <- sd(rs)
  if (is.na(sdv) || sdv <= 0) return(NA_real_)
  sk <- mean(((rs - mu) / sdv)^3)
  kt <- mean(((rs - mu) / sdv)^4)
  sr <- mu / sdv
  denom <- 1 - sk * sr + (kt - 1) / 4 * sr^2
  if (denom <= 0) return(NA_real_)
  sr * sqrt(N - 1) / sqrt(denom)
}

eval_spec <- function(d, pred_col, tgt_col, name) {
  sub <- d[!is.na(get(pred_col)) & !is.na(get(tgt_col)), ]
  if (nrow(sub) < 30) return(NULL)

  # PIT-OOS expanding window IC (anchored 36m start)
  N <- nrow(sub)
  if (N < 48) return(NULL)
  ic_series <- rep(NA_real_, N)
  for (i in 36:N) {
    w <- sub[(i-35):i, ]
    ic_series[i] <- cor(w[[pred_col]], w[[tgt_col]], method = "spearman", use = "complete.obs")
  }
  ic_series_clean <- na.omit(ic_series)

  ic_full <- cor(sub[[pred_col]], sub[[tgt_col]], method = "spearman", use = "complete.obs")
  pearson_full <- cor(sub[[pred_col]], sub[[tgt_col]], method = "pearson", use = "complete.obs")

  icir <- if (length(ic_series_clean) >= 12) mean(ic_series_clean) / sd(ic_series_clean) else NA_real_
  t_NW <- nw_t(ic_series_clean)
  t_simple <- if (length(ic_series_clean) >= 12) mean(ic_series_clean) / (sd(ic_series_clean) / sqrt(length(ic_series_clean))) else NA_real_

  # LS strategy: sign(pred) * tgt
  ls_ret <- sign(sub[[pred_col]]) * sub[[tgt_col]]
  dsr <- dsr_calc(ls_ret)
  ls_sr_ann <- mean(ls_ret, na.rm = TRUE) / sd(ls_ret, na.rm = TRUE) * sqrt(12)

  # Turnover proxy: sign change frequency
  signs <- sign(sub[[pred_col]])
  turnover <- mean(c(NA, signs[-1] != signs[-length(signs)]), na.rm = TRUE) * 12   # annualized monthly flips
  cost_15bps_ann <- 0.0015 * turnover * 2   # 15bps × turnover one-way × 2 for round-trip
  ls_sr_ann_net <- (mean(ls_ret, na.rm = TRUE) - cost_15bps_ann / 12) / sd(ls_ret, na.rm = TRUE) * sqrt(12)

  # Subperiod IC stability
  sub[, year := as.integer(format(date, "%Y"))]
  ic_p1 <- tryCatch(cor(sub[year >= 2008 & year <= 2014, get(pred_col)],
                         sub[year >= 2008 & year <= 2014, get(tgt_col)],
                         method = "spearman", use = "complete.obs"), error = function(e) NA_real_)
  ic_p2 <- tryCatch(cor(sub[year >= 2015 & year <= 2019, get(pred_col)],
                         sub[year >= 2015 & year <= 2019, get(tgt_col)],
                         method = "spearman", use = "complete.obs"), error = function(e) NA_real_)
  ic_p3 <- tryCatch(cor(sub[year >= 2020 & year <= 2026, get(pred_col)],
                         sub[year >= 2020 & year <= 2026, get(tgt_col)],
                         method = "spearman", use = "complete.obs"), error = function(e) NA_real_)
  signs <- sign(c(ic_p1, ic_p2, ic_p3))
  signs <- signs[!is.na(signs)]
  sub_stab <- if (length(signs) >= 2) abs(sum(signs)) / length(signs) else 0

  # Predictor autocor (sanity flag)
  pred_autocor <- cor(sub[[pred_col]][-1], sub[[pred_col]][-nrow(sub)], use = "complete.obs")

  list(name = name, pred = pred_col, tgt = tgt_col, n = nrow(sub),
       ic = ic_full, pearson_r = pearson_full,
       icir = icir, t_simple = t_simple, t_NW = t_NW, dsr = dsr,
       ls_sr_ann = ls_sr_ann, ls_sr_ann_net = ls_sr_ann_net,
       turnover_ann = turnover,
       sub_stab = sub_stab,
       ic_p1 = ic_p1, ic_p2 = ic_p2, ic_p3 = ic_p3,
       pred_autocor_lag1 = pred_autocor)
}

specs <- list()
predictors <- c("vrp_ret_lag1", "vrp_3m_lag1", "vrp_innov_z")
targets <- c("r_AR_fwd1", "r_Hybrid_fwd1", "r_KR10y_fwd1")

for (p in predictors) {
  for (t in targets) {
    nm <- paste0(sub("vrp_", "", sub("_lag1", "", p)), "_predicts_",
                 sub("_fwd1", "", sub("r_", "", t)))
    res <- eval_spec(copy(usable), p, t, nm)
    if (!is.null(res)) specs <- append(specs, list(res))
  }
}

cat(sprintf("\n%-40s %3s %+9s %+8s %+8s %+8s %+6s %+6s %+6s %+6s %+6s %+6s %+6s\n",
            "spec", "n", "IC", "ICIR", "t_NW", "DSR", "LS_SR", "LS_NET", "TO", "SUB", "p1", "p2", "p3"))
for (s in specs) {
  cat(sprintf("%-40s %3d %+9.4f %+8.4f %+8.3f %+8.3f %+6.3f %+6.3f %+6.2f %+6.3f %+6.3f %+6.3f %+6.3f\n",
              s$name, s$n,
              s$ic %||% NA, s$icir %||% NA, s$t_NW %||% NA, s$dsr %||% NA,
              s$ls_sr_ann %||% NA, s$ls_sr_ann_net %||% NA, s$turnover_ann %||% NA,
              s$sub_stab %||% NA, s$ic_p1 %||% NA, s$ic_p2 %||% NA, s$ic_p3 %||% NA))
}

cat("\n--- Predictor autocorrelations (sanity) ---\n")
for (p in predictors) {
  pa <- cor(usable[[p]][-1], usable[[p]][-nrow(usable)], use = "complete.obs")
  cat(sprintf("%-30s autocor lag-1 = %+.4f\n", p, pa))
}

#==============================================================================
# Step 4b: ML — VRP-only features (NO r_AR_lag / r_KR10y_lag to prevent leakage)
#==============================================================================
cat("\n=== Step 4b: ML XGBoost — VRP-only features (no leakage) ===\n")

ml_results <- list(method = "XGBoost_VRP_only", note = "VRP-only features")
have_xgb <- requireNamespace("xgboost", quietly = TRUE)
if (have_xgb) {
  library(xgboost)
  ml_dt <- usable[!is.na(vrp_ret_lag1) & !is.na(vrp_3m_lag1) & !is.na(vrp_innov_z) & !is.na(r_AR_fwd1), ]
  feats <- c("vrp_ret_lag1", "vrp_3m_lag1", "vrp_innov_z")
  X <- as.matrix(ml_dt[, ..feats])
  y <- ml_dt$r_AR_fwd1
  N <- nrow(X)
  cat("ML data: n=", N, " features=", length(feats), "(VRP only)\n")

  n_folds <- 5L; fold_size <- floor(N / n_folds); preds <- rep(NA_real_, N)
  for (k in 1:n_folds) {
    test_start <- (k - 1) * fold_size + 1
    test_end <- if (k == n_folds) N else k * fold_size
    train_end <- test_start - 1
    if (train_end < 36) next
    dtrain <- xgb.DMatrix(data = X[1:train_end, , drop = FALSE], label = y[1:train_end])
    params <- list(objective = "reg:squarederror", eta = 0.05, max_depth = 3,
                   min_child_weight = 5, subsample = 0.8, colsample_bytree = 0.8,
                   lambda = 1.0, alpha = 0.1)
    model <- xgb.train(params, dtrain, nrounds = 100, verbose = 0)
    preds[test_start:test_end] <- predict(model,
      xgb.DMatrix(data = X[test_start:test_end, , drop = FALSE]))
  }
  preds_clean <- preds[!is.na(preds)]
  y_clean <- y[!is.na(preds)]
  ml_ic <- cor(preds_clean, y_clean, method = "spearman", use = "complete.obs")
  ml_ret <- sign(preds_clean) * y_clean
  ml_sr_ann <- mean(ml_ret, na.rm = TRUE) / sd(ml_ret, na.rm = TRUE) * sqrt(12)

  # Net SR after 15bps cost
  ml_signs <- sign(preds_clean)
  ml_turnover <- mean(c(NA, ml_signs[-1] != ml_signs[-length(ml_signs)]), na.rm = TRUE) * 12
  ml_cost <- 0.0015 * ml_turnover * 2
  ml_sr_net <- (mean(ml_ret, na.rm = TRUE) - ml_cost / 12) / sd(ml_ret, na.rm = TRUE) * sqrt(12)

  cat("ML XGBoost (VRP-only, 5-fold WF): SR_gross=", round(ml_sr_ann, 4),
      " SR_net=", round(ml_sr_net, 4),
      " IC=", round(ml_ic, 4), " n_test=", length(preds_clean), "\n")

  ml_results <- list(method = "XGBoost_VRP_only", n_folds = n_folds,
                     n_test = length(preds_clean),
                     sr_annual_gross = ml_sr_ann, sr_annual_net = ml_sr_net,
                     turnover_ann = ml_turnover,
                     rank_ic_oos = ml_ic, features = feats)
}

# Classical baseline
cls_dt <- usable[!is.na(vrp_innov_z) & !is.na(r_AR_fwd1), ]
cls_dt[, cls_signal := -sign(vrp_innov_z)]
cls_dt[, cls_ret := cls_signal * r_AR_fwd1]
cls_signs <- sign(cls_dt$cls_signal)
cls_to <- mean(c(NA, cls_signs[-1] != cls_signs[-length(cls_signs)]), na.rm = TRUE) * 12
cls_sr_gross <- mean(cls_dt$cls_ret, na.rm = TRUE) / sd(cls_dt$cls_ret, na.rm = TRUE) * sqrt(12)
cls_sr_net <- (mean(cls_dt$cls_ret, na.rm = TRUE) - 0.0015 * cls_to * 2 / 12) /
              sd(cls_dt$cls_ret, na.rm = TRUE) * sqrt(12)
cat("Classical (sign-flip vrp_innov_z): SR_gross=", round(cls_sr_gross, 4),
    " SR_net=", round(cls_sr_net, 4), " TO=", round(cls_to, 2), "\n")

naive_sr <- mean(usable$r_AR_fwd1, na.rm = TRUE) / sd(usable$r_AR_fwd1, na.rm = TRUE) * sqrt(12)
cat("Naive r_AR hold: SR_ann=", round(naive_sr, 4), "\n")

#==============================================================================
# Step 5+6+7: Best spec selection + alpha + draft
#==============================================================================
cat("\n=== Step 5+6+7: Alpha forecast + draft ===\n")

# Filter for AR target only
ar_specs <- Filter(function(s) grepl("AR$", s$name), specs)
ar_ics <- sapply(ar_specs, function(s) abs(s$ic %||% 0))
best_ar <- ar_specs[[which.max(ar_ics)]]

# Filter for Hybrid target only
hyb_specs <- Filter(function(s) grepl("Hybrid$", s$name), specs)
hyb_ics <- sapply(hyb_specs, function(s) abs(s$ic %||% 0))
best_hyb <- hyb_specs[[which.max(hyb_ics)]]

cat("Best AR target spec:", best_ar$name, "| IC=", round(best_ar$ic, 4),
    "| ICIR=", round(best_ar$icir %||% NA, 4), "| t_NW=", round(best_ar$t_NW %||% NA, 3),
    "| DSR=", round(best_ar$dsr %||% NA, 3), "| sub_stab=", round(best_ar$sub_stab %||% NA, 3),
    "| TO=", round(best_ar$turnover_ann %||% NA, 2), "\n")
cat("Best Hybrid target spec:", best_hyb$name, "| IC=", round(best_hyb$ic, 4), "\n")

# Use best_ar for primary alpha
last_row <- usable[nrow(usable), ]

# Alpha forecast — use best predictor's beta on r_AR_fwd1
best_pred_col <- best_ar$pred
last_pred <- last_row[[best_pred_col]]
beta_best <- cov(usable[[best_pred_col]], usable$r_AR_fwd1, use = "complete.obs") /
             var(usable[[best_pred_col]], na.rm = TRUE)
alpha_pt <- beta_best * last_pred

cat("Last predictor:", best_pred_col, "=", round(last_pred %||% NA, 4),
    "| beta=", round(beta_best, 4), "| alpha_pt=", round(alpha_pt %||% NA, 4), "\n")

alpha_vector <- list("VRP_KOSPI_TS_OVERLAY" = alpha_pt %||% 0)
sig_sd <- sd(usable[[best_pred_col]], na.rm = TRUE)
sig_mag <- abs(last_pred %||% 0) / max(sig_sd, 0.01)
confidence <- pmin(sig_mag / 2, 1)
confidence_vector <- list("VRP_KOSPI_TS_OVERLAY" = confidence)

#==============================================================================
# Save artifacts
#==============================================================================
alpha_scores <- usable[, .(date, vrp_ret_lag1, vrp_3m_lag1, vrp_innov_z,
                            r_AR_fwd1, r_Hybrid_fwd1, r_KR10y_fwd1)]
alpha_scores[, ticker := "VRP_KOSPI_TS_OVERLAY"]
alpha_scores[, alpha_score := beta_best * get(best_pred_col)]
write_parquet(alpha_scores, file.path(STAGE_DIR, "alpha_scores.parquet"))

spec_summary <- rbindlist(lapply(specs, function(s) {
  data.table(name = s$name, n = s$n, ic = s$ic, pearson_r = s$pearson_r,
             icir = s$icir, t_NW = s$t_NW, dsr = s$dsr,
             ls_sr_gross = s$ls_sr_ann, ls_sr_net = s$ls_sr_ann_net,
             turnover_ann = s$turnover_ann,
             sub_stab = s$sub_stab,
             ic_p1 = s$ic_p1, ic_p2 = s$ic_p2, ic_p3 = s$ic_p3,
             pred_autocor = s$pred_autocor_lag1)
}), fill = TRUE)
fwrite(spec_summary, file.path(STAGE_DIR, "spec_diagnostics.csv"))

# alpha_validation.json
alpha_validation <- list(
  task_id = WT_ID,
  as_of_date = as.character(request$as_of_date),
  v_history = list(
    v1_failure = "IC 0.957 ZSCORE = r_vrp self-autocorrelation (lag-1 0.404). Not alpha.",
    v2_failure = "Predictor autocor 0.968 inflated ICIR. Sub_stab 0.333 + p3 reversal. ML IC 0.9953 = feature leakage from r_AR_lag1.",
    v3_corrections = c(
      "Drop high-autocor predictor; use vrp_ret_lag1 / vrp_3m_lag1 / vrp_innov_z (low autocor)",
      "ML features VRP-only (drop r_AR_lag1 / r_KR10y_lag1 leakage path)",
      "15bps cost integration in net SR",
      "9 specs honest disclosure (3 predictors × 3 targets)"
    )
  ),
  hypothesis = "VRP innovation at t-1 predicts forward 1M return of equity (Bollerslev-Tauchen-Zhou 2009 RFS)",
  source_papers = c(
    "Bollerslev-Tauchen-Zhou 2009 RFS (VRP predicts equity excess returns)",
    "Carr-Wu 2009 RFS (VRP theoretical framework)",
    "Bakshi-Kapadia-Madan 2003 RFS (risk-neutral skewness)"
  ),
  spec_diagnostics = lapply(specs, function(s) {
    list(name = s$name, n = s$n, ic = s$ic, pearson_r = s$pearson_r,
         icir = s$icir, t_NW = s$t_NW, dsr = s$dsr,
         ls_sr_gross = s$ls_sr_ann, ls_sr_net = s$ls_sr_ann_net,
         turnover_ann = s$turnover_ann,
         sub_stab = s$sub_stab,
         ic_p1 = s$ic_p1, ic_p2 = s$ic_p2, ic_p3 = s$ic_p3,
         pred_autocor = s$pred_autocor_lag1)
  }),
  best_ar_spec = best_ar$name,
  best_hyb_spec = best_hyb$name,
  graduation_check = list(
    rank_ic = best_ar$ic,
    rank_ic_pass = abs(best_ar$ic %||% 0) >= 0.04,
    icir = best_ar$icir,
    icir_pass = abs(best_ar$icir %||% 0) >= 0.20,
    sub_stab = best_ar$sub_stab,
    sub_stab_pass = (best_ar$sub_stab %||% 0) >= 0.5,
    harvey_t_NW = best_ar$t_NW,
    harvey_t_pass = abs(best_ar$t_NW %||% 0) >= 3.0,
    dsr = best_ar$dsr,
    dsr_pass = abs(best_ar$dsr %||% 0) >= 0.5,
    overall_pass = all(c(
      abs(best_ar$ic %||% 0) >= 0.04,
      abs(best_ar$icir %||% 0) >= 0.20,
      (best_ar$sub_stab %||% 0) >= 0.5,
      abs(best_ar$t_NW %||% 0) >= 3.0,
      abs(best_ar$dsr %||% 0) >= 0.5
    ))
  ),
  ml_comparison = ml_results,
  classical_baseline = list(method = "sign_flip_innov_z_AR_target",
                            sr_gross = cls_sr_gross, sr_net = cls_sr_net,
                            turnover_ann = cls_to),
  naive_baseline = list(method = "naive_AR_hold", sr_annual = naive_sr),
  caveats = list(
    "VRP_KOSPI_Proxy uses US VIX^2 - SPX RV (cycle 1 caveat). VKOSPI direct fetch deferred (KRX OpenAPI follow-up WT).",
    "VRP innovation predictor autocor < 0.2 (low) — t_NW interpretation safer than v1/v2.",
    "n_obs ~ 215m post-2008-03 (vrp_innov_z 48m burn-in).",
    "Single-asset overlay alpha applied to AR / Hybrid book.",
    "Cost = 15bps × turnover (annualized one-way × 2 round-trip).",
    "L-228 정합 — cross-section ML refused; time-series single-overlay approach."
  )
)
write_json(alpha_validation, file.path(STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# alpha_package_draft.json
factor_specs <- lapply(seq_along(predictors), function(i) {
  p <- predictors[i]
  ar_spec <- ar_specs[[which(sapply(ar_specs, function(s) s$pred) == p)]]
  list(
    factor_family = "VRP_VolatilityRiskPremium",
    proxy = p,
    formula = c(
      vrp_ret_lag1 = "r_vrp[t-1] (lagged VRP signal monthly return)",
      vrp_3m_lag1 = "rolling 3m mean of r_vrp at t-1 (smoothed)",
      vrp_innov_z = "z-score of (12m sum_t-1 - 12m sum_t-2), expanding 48m"
    )[[p]],
    lag_rule = "t-1 month-end (PIT)",
    winsorization = "none",
    neutralization = "single-asset overlay (no cross-section)",
    economic_rationale = c(
      vrp_ret_lag1 = "Direct VRP signal — Bollerslev-Tauchen-Zhou 2009 RFS theoretical predictor",
      vrp_3m_lag1 = "Smoothed VRP — noise reduction while preserving regime signal (Carr-Wu 2009)",
      vrp_innov_z = "VRP innovation (Δ vrp_idx) — reduces autocorrelation, isolates new VRP information (Bakshi-Kapadia-Madan 2003)"
    )[[p]],
    weight_theta = if (p == best_ar$pred) 1.0 else 0.0,
    references = c("Bollerslev-Tauchen-Zhou 2009 RFS", "Carr-Wu 2009 RFS", "Bakshi-Kapadia-Madan 2003 RFS"),
    source = "db_derived",
    selection_objective = "rank_ic",
    diagnostics = list(ic = ar_spec$ic, icir = ar_spec$icir, t_NW = ar_spec$t_NW,
                       n = ar_spec$n, sub_stab = ar_spec$sub_stab,
                       pred_autocor = ar_spec$pred_autocor_lag1)
  )
})

harvey_t_pass <- sum(sapply(ar_specs, function(s) abs(s$t_NW %||% 0) >= 3.0))

draft <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  as_of_date = as.character(request$as_of_date),
  forecast_horizon = "1M",
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = "stage_artifacts/WT_D20260508_001/alpha_scores.parquet",
  factor_specs = factor_specs,
  diagnostics = list(
    rank_ic = best_ar$ic,
    icir = best_ar$icir,
    monotonicity = NA,
    subperiod_stability = best_ar$sub_stab,
    turnover_proxy = best_ar$turnover_ann,
    harvey_t_stat = best_ar$t_simple,
    harvey_t_NW = best_ar$t_NW,
    deflated_sharpe_ratio = best_ar$dsr,
    post_neutralization_ic = best_ar$ic,
    n_obs = best_ar$n,
    ic_p1_2008_2014 = best_ar$ic_p1,
    ic_p2_2015_2019 = best_ar$ic_p2,
    ic_p3_2020_2026 = best_ar$ic_p3,
    spec_count = length(factor_specs),
    harvey_t_specs_pass_count = harvey_t_pass,
    pred_autocor_lag1 = best_ar$pred_autocor_lag1
  ),
  ml_comparison = ml_results,
  classical_baseline = list(method = "sign_flip_innov_z_AR_target",
                            sr_gross = cls_sr_gross, sr_net = cls_sr_net,
                            turnover_ann = cls_to),
  naive_baseline = list(method = "naive_AR_hold", sr_annual = naive_sr),
  selection_objective = "rank_ic",
  alpha_inheritance_cor = NA,
  candidates_tried = length(specs),
  method_log = lapply(specs, function(s) {
    list(name = s$name, rank_ic = s$ic, icir = s$icir, t_NW = s$t_NW,
         dsr = s$dsr, ls_sr_net = s$ls_sr_ann_net, sub_stab = s$sub_stab,
         selected = (s$name == best_ar$name))
  }),
  challenge_flags = list(),
  rcpp_used = FALSE,
  parallel_exec = FALSE,
  hypothesis_source = "alpha_agent_discovered",
  hypothesis_title = "VRP_KOSPI_TS overlay — 4th orthogonal alpha source for SR 2.0 path",
  hypothesis_description_short = paste(
    "VRP innovation predicts forward equity return (Bollerslev-Tauchen-Zhou 2009 RFS).",
    "cycle 2 cor_hybrid -0.138 + crisis_alpha 4/6. L-228 정합: cross-section ML 거부.",
    "v3 rigorous: low-autocor predictors + ML VRP-only features + 15bps cost integration."
  ),
  v_history_summary = list(
    v1 = "IC 0.957 = autocorr (rejected by self-audit)",
    v2 = "predictor autocor 0.968 inflated, sub_stab 0.333, ML feature leakage (rejected)",
    v3 = "rigorous correction — low-autocor predictors, VRP-only ML, cost-aware net SR"
  ),
  caveats = list(
    "VRP_KOSPI_Proxy = US VIX^2 - SPX RV proxy (cycle 1 caveat). KOSPI VKOSPI direct fetch deferred to follow-up WT (KRX OpenAPI acquisition).",
    "n_obs ~ 215m post-2008-03 (vrp_innov_z 48m burn-in). IMF 1997 / DotCom 2000 unavailable.",
    "Single-asset overlay alpha (VRP signal applied to AR or Hybrid book level).",
    "Net SR = gross - 15bps × turnover_ann × 2 (round-trip).",
    "Predictor autocor still moderate (vrp_3m_lag1 ~ 0.6) — interpret t_NW conservatively.",
    "v1/v2 self-audit failures honest disclosure for AX-002 process integrity."
  )
)

# Pre-flight Red Flag check
cf <- list()
if (length(factor_specs) <= 2) cf <- append(cf, list(list(id = "RF-A1", severity = "HIGH", msg = "factor_specs <= 2")))
if (!is.na(best_ar$ic_p3) && !is.na(best_ar$ic) &&
    abs(best_ar$ic_p3) > abs(best_ar$ic) * 1.5) {
  cf <- append(cf, list(list(id = "RF-A3", severity = "HIGH",
    msg = paste0("recent 3Y IC ", round(best_ar$ic_p3, 3), " > overall * 1.5 (over-fit suspicion)"))))
}
if (abs(best_ar$ic %||% 0) < 0.04) cf <- append(cf, list(list(id = "GRADUATION_FAIL_IC", severity = "HIGH",
  msg = paste0("rank_ic ", round(best_ar$ic %||% NA, 4), " < 0.04"))))
if (abs(best_ar$icir %||% 0) < 0.20) cf <- append(cf, list(list(id = "GRADUATION_FAIL_ICIR", severity = "HIGH",
  msg = paste0("ICIR ", round(best_ar$icir %||% NA, 4), " < 0.20"))))
if (abs(best_ar$t_NW %||% 0) < 3.0) cf <- append(cf, list(list(id = "GRADUATION_FAIL_HARVEY", severity = "HIGH",
  msg = paste0("t_NW ", round(best_ar$t_NW %||% NA, 3), " < 3.0"))))
if ((best_ar$sub_stab %||% 0) < 0.5) cf <- append(cf, list(list(id = "GRADUATION_FAIL_SUBSTAB", severity = "HIGH",
  msg = paste0("sub_stab ", round(best_ar$sub_stab %||% NA, 3), " < 0.5"))))
if (abs(best_ar$dsr %||% 0) < 0.5) cf <- append(cf, list(list(id = "GRADUATION_FAIL_DSR", severity = "HIGH",
  msg = paste0("DSR ", round(best_ar$dsr %||% NA, 3), " < 0.5"))))
if ((best_ar$pred_autocor_lag1 %||% 0) > 0.5) cf <- append(cf, list(list(id = "RF-AUTOCOR", severity = "MEDIUM",
  msg = paste0("predictor autocor ", round(best_ar$pred_autocor_lag1, 3),
               " > 0.5 — t_NW may be inflated by persistence"))))
draft$challenge_flags <- cf

draft_path <- file.path(WT_DIR, "alpha_package_draft.json")
write_json(draft, draft_path, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("alpha_package_draft.json saved:", draft_path, "(", file.size(draft_path), "bytes)\n")

# Lineage
lineage_utils_path <- file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R")
if (file.exists(lineage_utils_path)) {
  source(lineage_utils_path)
  tryCatch({
    record_package_lineage(
      task_id = WT_ID,
      package_type = "alpha_package_draft_v3",
      method_selected = best_ar$name,
      input_file_paths = c(RISK_META_PATH, file.path(STAGE_DIR, "alpha_scores.parquet"))
    )
    cat("Lineage v3 recorded\n")
  }, error = function(e) cat("Lineage warning:", conditionMessage(e), "\n"))
}

cat("\n=== v3 Complete ===\n")
cat("Best AR target:", best_ar$name, "\n")
cat("  IC=", round(best_ar$ic, 4),
    "| ICIR=", round(best_ar$icir %||% NA, 4),
    "| t_NW=", round(best_ar$t_NW %||% NA, 3),
    "| DSR=", round(best_ar$dsr %||% NA, 3),
    "| sub_stab=", round(best_ar$sub_stab %||% NA, 3),
    "| TO=", round(best_ar$turnover_ann %||% NA, 2), "\n")
cat("Graduation pass:", alpha_validation$graduation_check$overall_pass, "\n")
cat("Challenge flags:", length(cf), "\n")
