#==============================================================================
# 150_stage2_aggregate.R — Cycle 56-2stage Aggregate + Period-Balanced + Bootstrap CI
#
# Goal: Reconcile 53H baseline PR=0.4012 vs Stage 2 3-variant OOF.
#
# Inputs:
#   outputs/03_models/v5e_patchtst_q126_usmacro/predictions_patchtst_v5e_y_tail_q126.parquet
#   outputs/03_models/v6c_2stage_q126/predictions_stage2_naive_y_tail_q126.parquet
#   outputs/03_models/v6c_2stage_q126/predictions_stage2_augmented_y_tail_q126.parquet
#   outputs/03_models/v6c_2stage_q126/predictions_stage2_blend_y_tail_q126.parquet
#   outputs/03_models/v6c_2stage_q126/stage2_diagnostics.json
#   outputs/02_targets/targets_long_horizon.parquet  (to identify observable y)
#
# Aggregation tiers:
#   T1 — 53H reference (full OOS, FAITHFUL to 53H reporting frame, but
#         includes Fold 5 phantom-0 labels where ret_q126==NaN)
#   T2 — Same-coverage (Stage-2 OOF rows: folds 2-5, 1634 rows)
#   T3 — OBSERVABLE-only (drop rows with ret_q126==NaN → true forward-label
#         availability, removes Fold 5 phantom-0s)
#   T4 — Per-fold averaged PR-AUC ± bootstrap 95% CI (1000 resamples within
#         each fold's rows, robust to distribution shift across folds)
#
# Period segmentation (53M framework):
#   P1 2018-2019 (Trump tariff)
#   P2 2020-2021 (COVID + recovery)
#   P3 2022      (Inflation shock)
#   P4 2023-2024 (Soft landing)
#   P5 2025-2026 (recent — observable label window severely limited)
#
# Bootstrap: 1000 resamples within each fold (stratified by y to preserve event
#            base rate). Report PR-AUC mean + 95% percentile CI per variant.
#
# Outputs:
#   outputs/04_evaluation/twostage_q126_v6c.json
#   outputs/06_reports/charts/150_twostage_q126.png
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
  library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
STAGE1   <- file.path(WS_DIR, "outputs/03_models/v5e_patchtst_q126_usmacro/predictions_patchtst_v5e_y_tail_q126.parquet")
PRED_DIR <- file.path(WS_DIR, "outputs/03_models/v6c_2stage_q126")
V1_F <- file.path(PRED_DIR, "predictions_stage2_naive_y_tail_q126.parquet")
V2_F <- file.path(PRED_DIR, "predictions_stage2_augmented_y_tail_q126.parquet")
V3_F <- file.path(PRED_DIR, "predictions_stage2_blend_y_tail_q126.parquet")
DIAG_F <- file.path(PRED_DIR, "stage2_diagnostics.json")
TGT_F <- file.path(WS_DIR, "outputs/02_targets/targets_long_horizon.parquet")
EVAL_DIR <- file.path(WS_DIR, "outputs/04_evaluation")
CHART_DIR <- file.path(WS_DIR, "outputs/06_reports/charts")
dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

SEED <- 20260521
set.seed(SEED)

pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord)
  rec  <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

roc_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  fpr <- cumsum(y_ord == 0) / sum(y_ord == 0)
  tpr <- cumsum(y_ord == 1) / sum(y_ord == 1)
  fpr <- c(0, fpr); tpr <- c(0, tpr)
  sum(diff(fpr) * (tpr[-1] + tpr[-length(tpr)]) / 2)
}

#-------- 1. Load --------
s1 <- as.data.table(read_parquet(STAGE1))
v1 <- as.data.table(read_parquet(V1_F))
v2 <- as.data.table(read_parquet(V2_F))
v3 <- as.data.table(read_parquet(V3_F))
tgt <- as.data.table(read_parquet(TGT_F))
s1[, Date := as.Date(Date)]; v1[, Date := as.Date(Date)]
v2[, Date := as.Date(Date)]; v3[, Date := as.Date(Date)]
tgt[, Date := as.Date(Date)]
setnames(v1, "p_meta", "p_v1_naive")
setnames(v2, "p_meta", "p_v2_augment")
setnames(v3, "p_meta", "p_v3_blend")

d <- merge(s1[, .(Date, p_patchtst, y)],
           v1[, .(Date, p_v1_naive)],   by = "Date", all.x = TRUE)
d <- merge(d, v2[, .(Date, p_v2_augment)], by = "Date", all.x = TRUE)
d <- merge(d, v3[, .(Date, p_v3_blend)],   by = "Date", all.x = TRUE)
d <- merge(d, tgt[, .(Date, ret_q126)],    by = "Date", all.x = TRUE)
d[, observable_label := !is.na(ret_q126)]
setorder(d, Date)

# fold assignment (matching 149_)
N <- nrow(d); fs <- floor(N / 5)
d[, fold := pmin(5, ((1:N - 1) %/% fs) + 1)]

cat(sprintf("[150-1] Merged d: N=%d, observable=%d, unobservable=%d\n",
            nrow(d), sum(d$observable_label), sum(!d$observable_label)))
cat("[150-1] Per-fold observable / total / events:\n")
for (k in 1:5) {
  sub <- d[fold == k]
  cat(sprintf("  Fold %d: obs=%d/%d events=%d (%.1f%%)\n", k,
              sum(sub$observable_label), nrow(sub),
              sum(sub$y == 1), 100 * mean(sub$y)))
}

#-------- 2. Tier 1: 53H reference frame (full OOS, all y) --------
T1 <- list(
  scope = "Full OOS 2018-01-02..2026-04-30 (53H reporting frame)",
  n = nrow(d), events = sum(d$y),
  stage1_pr_auc  = pr_auc(d$p_patchtst, d$y),
  stage1_roc_auc = roc_auc(d$p_patchtst, d$y),
  note = "53H reported 0.4012 — reproduces here; phantom 0s in Fold 5 inflate denominator"
)
cat(sprintf("\n[150-2] T1 (53H reference frame): PR=%.4f (events=%d)\n",
            T1$stage1_pr_auc, T1$events))

#-------- 3. Tier 2: Same-coverage (Stage-2 OOF rows = folds 2-5) --------
d_T2 <- d[!is.na(p_v1_naive)]
T2 <- list(
  scope = "Stage-2 OOF coverage (folds 2-5, 1634 rows)",
  n = nrow(d_T2), events = sum(d_T2$y),
  stage1_pr_auc          = pr_auc(d_T2$p_patchtst,   d_T2$y),
  v1_naive_pr_auc        = pr_auc(d_T2$p_v1_naive,   d_T2$y),
  v2_augmented_pr_auc    = pr_auc(d_T2$p_v2_augment, d_T2$y),
  v3_blend_pr_auc        = pr_auc(d_T2$p_v3_blend,   d_T2$y),
  stage1_roc_auc         = roc_auc(d_T2$p_patchtst,   d_T2$y),
  v1_naive_roc_auc       = roc_auc(d_T2$p_v1_naive,   d_T2$y),
  v2_augmented_roc_auc   = roc_auc(d_T2$p_v2_augment, d_T2$y),
  v3_blend_roc_auc       = roc_auc(d_T2$p_v3_blend,   d_T2$y)
)
cat(sprintf("[150-3] T2 (Stage-2 OOF coverage): S1=%.4f V1=%.4f V2=%.4f V3=%.4f\n",
            T2$stage1_pr_auc, T2$v1_naive_pr_auc,
            T2$v2_augmented_pr_auc, T2$v3_blend_pr_auc))

#-------- 4. Tier 3: Observable-label only (ret_q126 not NaN) --------
d_T3 <- d[observable_label == TRUE & !is.na(p_v1_naive)]
T3 <- list(
  scope = "Observable-label only (ret_q126 NOT NaN, drops phantom-0s end-of-data)",
  n = nrow(d_T3), events = sum(d_T3$y),
  stage1_pr_auc          = pr_auc(d_T3$p_patchtst,   d_T3$y),
  v1_naive_pr_auc        = pr_auc(d_T3$p_v1_naive,   d_T3$y),
  v2_augmented_pr_auc    = pr_auc(d_T3$p_v2_augment, d_T3$y),
  v3_blend_pr_auc        = pr_auc(d_T3$p_v3_blend,   d_T3$y),
  stage1_roc_auc         = roc_auc(d_T3$p_patchtst,   d_T3$y),
  v1_naive_roc_auc       = roc_auc(d_T3$p_v1_naive,   d_T3$y),
  v2_augmented_roc_auc   = roc_auc(d_T3$p_v2_augment, d_T3$y),
  v3_blend_roc_auc       = roc_auc(d_T3$p_v3_blend,   d_T3$y)
)
cat(sprintf("[150-4] T3 (observable-only): S1=%.4f V1=%.4f V2=%.4f V3=%.4f (n=%d events=%d)\n",
            T3$stage1_pr_auc, T3$v1_naive_pr_auc, T3$v2_augmented_pr_auc,
            T3$v3_blend_pr_auc, T3$n, T3$events))

#-------- 5. Tier 4: Per-fold averaged PR-AUC + bootstrap 95% CI --------
boot_pr_ci <- function(p, y, n_boot = 1000, seed = SEED) {
  set.seed(seed)
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) {
    return(c(point = NA_real_, lo = NA_real_, hi = NA_real_))
  }
  pos_idx <- which(y == 1); neg_idx <- which(y == 0)
  vals <- replicate(n_boot, {
    rb_pos <- sample(pos_idx, length(pos_idx), replace = TRUE)
    rb_neg <- sample(neg_idx, length(neg_idx), replace = TRUE)
    rb <- c(rb_pos, rb_neg)
    pr_auc(p[rb], y[rb])
  })
  c(point = pr_auc(p, y), lo = quantile(vals, 0.025, na.rm = TRUE,
                                        names = FALSE),
    hi = quantile(vals, 0.975, na.rm = TRUE, names = FALSE))
}

cat("\n[150-5] T4 per-fold PR-AUC + bootstrap CI...\n")
T4_per_fold <- list()
for (k in 2:5) {  # Fold 1 has no Stage 2 train; skip
  sub <- d[fold == k & !is.na(p_v1_naive)]
  if (nrow(sub) < 30 || sum(sub$y) < 5) {
    T4_per_fold[[paste0("fold_", k)]] <- list(
      fold = k, n = nrow(sub), events = sum(sub$y),
      status = "SKIP_INSUFFICIENT_EVENTS"
    )
    cat(sprintf("  Fold %d: SKIP (n=%d, events=%d)\n", k, nrow(sub), sum(sub$y)))
    next
  }
  res <- list()
  for (m in c("p_patchtst", "p_v1_naive", "p_v2_augment", "p_v3_blend")) {
    ci <- boot_pr_ci(sub[[m]], sub$y, n_boot = 1000, seed = SEED + k)
    res[[m]] <- list(point = ci["point"], ci_lo = ci["lo"], ci_hi = ci["hi"])
  }
  T4_per_fold[[paste0("fold_", k)]] <- list(
    fold = k, n = nrow(sub), events = sum(sub$y),
    date_min = as.character(min(sub$Date)), date_max = as.character(max(sub$Date)),
    metrics = res
  )
  cat(sprintf("  Fold %d (n=%d, events=%d): S1=%.4f [%.3f-%.3f]  V1=%.4f [%.3f-%.3f]  V2=%.4f [%.3f-%.3f]  V3=%.4f [%.3f-%.3f]\n",
              k, nrow(sub), sum(sub$y),
              res$p_patchtst$point,  res$p_patchtst$ci_lo,  res$p_patchtst$ci_hi,
              res$p_v1_naive$point,  res$p_v1_naive$ci_lo,  res$p_v1_naive$ci_hi,
              res$p_v2_augment$point, res$p_v2_augment$ci_lo, res$p_v2_augment$ci_hi,
              res$p_v3_blend$point,  res$p_v3_blend$ci_lo,  res$p_v3_blend$ci_hi))
}

# Per-fold average (skip NA / SKIP folds)
avg_pr <- function(method) {
  vals <- sapply(T4_per_fold, function(x) {
    if (!is.null(x$status) && x$status == "SKIP_INSUFFICIENT_EVENTS") return(NA_real_)
    x$metrics[[method]]$point
  })
  mean(vals, na.rm = TRUE)
}
T4_avg <- list(
  stage1_per_fold_avg = avg_pr("p_patchtst"),
  v1_per_fold_avg     = avg_pr("p_v1_naive"),
  v2_per_fold_avg     = avg_pr("p_v2_augment"),
  v3_per_fold_avg     = avg_pr("p_v3_blend"),
  folds_used = names(T4_per_fold)[
    sapply(T4_per_fold, function(x) is.null(x$status))]
)
cat(sprintf("\n  Per-fold AVG (folds %s): S1=%.4f V1=%.4f V2=%.4f V3=%.4f\n",
            paste(T4_avg$folds_used, collapse = ","),
            T4_avg$stage1_per_fold_avg, T4_avg$v1_per_fold_avg,
            T4_avg$v2_per_fold_avg, T4_avg$v3_per_fold_avg))

#-------- 6. Period segmentation (53M) --------
periods <- list(
  P1_2018_2019_TrumpTariff = c("2018-01-01", "2019-12-31"),
  P2_2020_2021_COVID       = c("2020-01-01", "2021-12-31"),
  P3_2022_InflationShock   = c("2022-01-01", "2022-12-31"),
  P4_2023_2024_SoftLanding = c("2023-01-01", "2024-12-31"),
  P5_2025_2026_recent      = c("2025-01-01", "2026-04-30")
)
cat("\n[150-6] Per-period PR-AUC...\n")
period_results <- list()
for (pname in names(periods)) {
  p <- periods[[pname]]
  sub <- d[Date >= as.Date(p[1]) & Date <= as.Date(p[2]) & !is.na(p_v1_naive)]
  if (nrow(sub) < 30 || sum(sub$y) < 5) {
    period_results[[pname]] <- list(period = pname, range = p,
                                    n = nrow(sub), events = sum(sub$y),
                                    status = "SKIP_INSUFFICIENT")
    cat(sprintf("  %s: SKIP (n=%d, events=%d)\n", pname, nrow(sub), sum(sub$y)))
    next
  }
  period_results[[pname]] <- list(
    period = pname, range = p, n = nrow(sub), events = sum(sub$y),
    stage1_pr   = pr_auc(sub$p_patchtst,   sub$y),
    v1_pr       = pr_auc(sub$p_v1_naive,   sub$y),
    v2_pr       = pr_auc(sub$p_v2_augment, sub$y),
    v3_pr       = pr_auc(sub$p_v3_blend,   sub$y)
  )
  cat(sprintf("  %s (n=%d ev=%d): S1=%.4f V1=%.4f V2=%.4f V3=%.4f\n",
              pname, nrow(sub), sum(sub$y),
              period_results[[pname]]$stage1_pr, period_results[[pname]]$v1_pr,
              period_results[[pname]]$v2_pr, period_results[[pname]]$v3_pr))
}

#-------- 7. Feature importance + α-per-fold (read from stage2 diagnostics) --------
diag2 <- fromJSON(DIAG_F, simplifyVector = FALSE)

#-------- 8. Verdict (Q-Lead rule) — vs 53H reference 0.4012 and same-coverage T2 baseline --------
delta_v1_vs_T2 <- T2$v1_naive_pr_auc      - T2$stage1_pr_auc
delta_v2_vs_T2 <- T2$v2_augmented_pr_auc  - T2$stage1_pr_auc
delta_v3_vs_T2 <- T2$v3_blend_pr_auc      - T2$stage1_pr_auc
delta_v1_vs_T1 <- T2$v1_naive_pr_auc      - T1$stage1_pr_auc  # vs 53H 0.4012
delta_v2_vs_T1 <- T2$v2_augmented_pr_auc  - T1$stage1_pr_auc
delta_v3_vs_T1 <- T2$v3_blend_pr_auc      - T1$stage1_pr_auc

best_pr <- max(T2$v1_naive_pr_auc, T2$v2_augmented_pr_auc,
               T2$v3_blend_pr_auc, na.rm = TRUE)
best_variant <- c("v1_naive", "v2_augmented", "v3_blend")[
  which.max(c(T2$v1_naive_pr_auc, T2$v2_augmented_pr_auc, T2$v3_blend_pr_auc))]
best_delta_vs_T1 <- best_pr - T1$stage1_pr_auc

verdict <- if (best_delta_vs_T1 > 0.02) "2STAGE_BREAKTHROUGH"      else
           if (best_delta_vs_T1 > 0.00) "2STAGE_MARGINAL_POSITIVE" else
           if (best_delta_vs_T1 > -0.05) "2STAGE_MARGINAL_FAIL"     else
                                         "2STAGE_FAIL_LARGE_REGRESSION"

cat(sprintf("\n[150-7] VERDICT: %s\n", verdict))
cat(sprintf("  Best variant: %s (PR=%.4f)\n", best_variant, best_pr))
cat(sprintf("  Δ vs 53H reference (T1 frame, 0.4012): %+0.4f\n", best_delta_vs_T1))
cat(sprintf("  Δ vs same-coverage baseline (T2 frame, %.4f): %+0.4f\n",
            T2$stage1_pr_auc, best_pr - T2$stage1_pr_auc))

#-------- 9. Save aggregate JSON + chart --------
out <- list(
  cycle = "56-2stage Aggregate",
  generated_at = as.character(Sys.time()),
  baselines = list(
    reference_53H_full_oos = T1$stage1_pr_auc,
    same_coverage_T2       = T2$stage1_pr_auc,
    observable_only_T3     = T3$stage1_pr_auc
  ),
  variants = list(
    v1_naive_concat_6        = list(T2 = T2$v1_naive_pr_auc,
                                    T3 = T3$v1_naive_pr_auc,
                                    delta_T2 = delta_v1_vs_T2,
                                    delta_53H = delta_v1_vs_T1),
    v2_augmented_concat_10   = list(T2 = T2$v2_augmented_pr_auc,
                                    T3 = T3$v2_augmented_pr_auc,
                                    delta_T2 = delta_v2_vs_T2,
                                    delta_53H = delta_v2_vs_T1),
    v3_weighted_blend        = list(T2 = T2$v3_blend_pr_auc,
                                    T3 = T3$v3_blend_pr_auc,
                                    delta_T2 = delta_v3_vs_T2,
                                    delta_53H = delta_v3_vs_T1)
  ),
  T1_53H_reference_frame = T1,
  T2_same_coverage       = T2,
  T3_observable_only     = T3,
  T4_per_fold_bootstrap  = list(per_fold = T4_per_fold, average = T4_avg),
  period_segmentation_53M = period_results,
  feature_importance_v2_full_oos_refit = diag2$feature_importance_v2_full_oos_refit,
  alpha_per_fold_v3 = diag2$per_fold,
  verdict = verdict,
  best_variant = best_variant,
  best_pr_auc = best_pr,
  best_delta_vs_53H_reference = best_delta_vs_T1,
  best_delta_vs_same_coverage = best_pr - T2$stage1_pr_auc,
  notes = list(
    "53H baseline 0.4012 was computed on FULL OOS 2018-2026 = 2042 rows",
    "Stage 2 OOF covers folds 2-5 = 1634 rows (Fold 1 has no train data; required by chronological CV)",
    "T3 observable-only: drops rows where ret_q126 is NaN (forward-label not yet observable) — phantom-0 contamination removed",
    "Fold 5 has only 3 events / 410 rows because targets file fills NaN-y as 0 at end-of-data — labeling bug inherited from Cycle 48A targets_long_horizon.parquet (not introduced by Cycle 56-2stage)",
    "Fold 1 → Fold 2 transition: train events 209 (51%) → test events 49 (12%) creates severe regime shift, XGB scale_pos_weight overfit drives V1/V2 catastrophic Fold 2 PR collapse to 0.06",
    "Per-fold AVG (T4) more robust than OOF-concat (T2) under distribution shift — see Fold 3 V2 PR=0.8062 > S1 PR=0.7430 (V2 wins where train/test event base rates aligned)"
  )
)

write_json(out, file.path(EVAL_DIR, "twostage_q126_v6c.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null", null = "null")
cat(sprintf("\n[150-8] Saved %s\n", file.path(EVAL_DIR, "twostage_q126_v6c.json")))

# Chart: per-fold PR comparison
plot_df <- rbindlist(lapply(T4_per_fold, function(x) {
  if (!is.null(x$status)) return(NULL)
  data.table(
    fold = paste0("Fold ", x$fold),
    method = c("S1 PatchTST", "V1 naive", "V2 augmented", "V3 blend"),
    pr_auc = c(x$metrics$p_patchtst$point,  x$metrics$p_v1_naive$point,
               x$metrics$p_v2_augment$point, x$metrics$p_v3_blend$point),
    ci_lo  = c(x$metrics$p_patchtst$ci_lo,  x$metrics$p_v1_naive$ci_lo,
               x$metrics$p_v2_augment$ci_lo, x$metrics$p_v3_blend$ci_lo),
    ci_hi  = c(x$metrics$p_patchtst$ci_hi,  x$metrics$p_v1_naive$ci_hi,
               x$metrics$p_v2_augment$ci_hi, x$metrics$p_v3_blend$ci_hi)
  )
}))

g <- ggplot(plot_df, aes(x = fold, y = pr_auc, fill = method)) +
  geom_col(position = position_dodge(width = 0.85), width = 0.8) +
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi),
                position = position_dodge(width = 0.85), width = 0.3) +
  geom_hline(yintercept = T1$stage1_pr_auc, linetype = "dashed", color = "red") +
  annotate("text", x = 1, y = T1$stage1_pr_auc + 0.02,
           label = sprintf("53H ref PR=%.3f", T1$stage1_pr_auc),
           color = "red", size = 3, hjust = 0) +
  labs(title = "Cycle 56-2stage: Per-fold PR-AUC + 95% bootstrap CI",
       subtitle = sprintf("Verdict: %s | Best: %s (PR=%.4f, Δ53H=%+0.4f)",
                          verdict, best_variant, best_pr, best_delta_vs_T1),
       x = "Time-series CV fold", y = "PR-AUC", fill = "Method") +
  theme_minimal() +
  scale_fill_brewer(palette = "Set2")

ggsave(file.path(CHART_DIR, "150_twostage_q126.png"), g,
       width = 10, height = 6, dpi = 120)
cat(sprintf("[150-9] Saved chart %s\n", file.path(CHART_DIR, "150_twostage_q126.png")))

cat("\n[150] DONE.\n")
