#==============================================================================
# 05_validation_suite.R — Phase 1 forecast validity FULL IMPL
#   5 performance gates + 1 uncertainty report + 1 aux conditional
#
# Plan v0.4.2 (Codex round 3 final 정합):
#   GATE 1: DM test (Diebold-Mariano log loss vs baseline, HAC lag ≥ 21) — p < 0.05
#   GATE 2: Brier Skill Score — > 0 (baseline 대비)
#   GATE 3: Calibration (intercept + slope + ECE) — slope ∈ [0.8, 1.2], ECE < 0.05
#   GATE 4: Event-level recall @ fixed alert-days — baseline +20%
#   GATE 5: PR-AUC — baseline +20%
#   REPORT: Bootstrap CI on p_bear (block bootstrap 12m, N=1000)
#   AUX:    Spearman(p_bear, Y_tail) regime conditional bad/normal > 1
#
# Phase 2 이동 lock (의무): Harvey-t / DSR / AX-001 crisis_alpha / Net-of-cost
#   → 본 script 호출 시 명시 stop() block
#
# Input:
#   predictions_path : forge agent 산출물 (Date, p_bear, model_name)
#   targets_path     : 02_target_builder.R 산출물 targets_full.parquet
#
# Output: outputs/04_evaluation/{
#   dm_test.json, brier_skill.csv, calibration_curve.png,
#   event_recall.json, pr_auc.csv, bootstrap_ci.csv, spearman_regime.csv,
#   validation_summary.md
# }
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
OUT_DIR <- file.path(WS_DIR, "outputs/04_evaluation")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

H <- 21L  # purge / HAC lag horizon

# ── Helper 1: Diebold-Mariano test (HAC NW) ────────────────────
#' DM test on log-loss difference (model vs baseline)
#' One-sided: H0 = no difference, H1 = model better
dm_test_hac <- function(pred_model, pred_baseline, actual, hac_lag = H) {
  # log loss element-wise
  ll_m <- -(actual * log(pmax(pred_model, 1e-15)) + (1 - actual) * log(pmax(1 - pred_model, 1e-15)))
  ll_b <- -(actual * log(pmax(pred_baseline, 1e-15)) + (1 - actual) * log(pmax(1 - pred_baseline, 1e-15)))
  d <- ll_b - ll_m   # positive = model better
  d <- d[!is.na(d)]
  if (length(d) < 30) return(list(p_value = NA, stat = NA, n = length(d)))
  mean_d <- mean(d)
  # NW HAC variance
  resid <- d - mean_d
  gamma_0 <- mean(resid^2)
  hac_var <- gamma_0
  for (k in 1:hac_lag) {
    gamma_k <- mean(resid[(k+1):length(resid)] * resid[1:(length(resid)-k)])
    weight <- 1 - k / (hac_lag + 1)
    hac_var <- hac_var + 2 * weight * gamma_k
  }
  se <- sqrt(hac_var / length(d))
  stat <- mean_d / se
  p_value <- pnorm(-stat)  # one-sided: model better
  list(p_value = p_value, stat = stat, n = length(d), mean_diff = mean_d, se = se)
}

# ── Helper 2: Brier Skill Score ────────────────────────────────
#' BSS = 1 - BS_model / BS_baseline (positive = better)
brier_skill <- function(pred_model, pred_baseline, actual) {
  bs_m <- mean((pred_model - actual)^2, na.rm = TRUE)
  bs_b <- mean((pred_baseline - actual)^2, na.rm = TRUE)
  bss <- 1 - bs_m / bs_b
  list(BS_model = bs_m, BS_baseline = bs_b, BSS = bss)
}

# ── Helper 3: Calibration (intercept + slope + ECE) ────────────
calibration_check <- function(pred, actual, n_bins = 10) {
  # Logit slope/intercept regression
  eps <- 1e-15
  logit_p <- log(pmax(pmin(pred, 1-eps), eps) / (1 - pmax(pmin(pred, 1-eps), eps)))
  fit <- glm(actual ~ logit_p, family = binomial())
  intercept <- coef(fit)[1]
  slope <- coef(fit)[2]
  # ECE
  bins <- cut(pred, breaks = seq(0, 1, length.out = n_bins + 1), include.lowest = TRUE)
  ece_df <- data.table(pred = pred, actual = actual, bin = bins)
  bin_summary <- ece_df[, .(mean_pred = mean(pred, na.rm=TRUE),
                            mean_actual = mean(actual, na.rm=TRUE),
                            n = .N), by = bin]
  bin_summary[, abs_gap := abs(mean_pred - mean_actual)]
  ece <- sum(bin_summary$n * bin_summary$abs_gap, na.rm = TRUE) / sum(bin_summary$n)
  list(intercept = unname(intercept), slope = unname(slope), ECE = ece,
       bin_summary = bin_summary)
}

# ── Helper 4: Event-level recall @ fixed alert-days ────────────
#' alert_days = top-k% 시점에서 alert. recall = actual events caught
event_recall <- function(pred, actual, alert_pct = 0.2) {
  k <- ceiling(length(pred) * alert_pct)
  alert_idx <- order(pred, decreasing = TRUE)[1:k]
  events_caught <- sum(actual[alert_idx] == 1, na.rm = TRUE)
  total_events <- sum(actual == 1, na.rm = TRUE)
  recall <- events_caught / total_events
  precision <- events_caught / k
  list(alert_pct = alert_pct, k_alerts = k, events_caught = events_caught,
       total_events = total_events, recall = recall, precision = precision)
}

# ── Helper 5: PR-AUC (manual, no PRROC dependency) ────────────
pr_auc_compute <- function(pred, actual) {
  ok <- !is.na(pred) & !is.na(actual)
  pred <- pred[ok]; actual <- actual[ok]
  if (length(pred) < 30 || sum(actual == 1) < 5) {
    return(list(pr_auc = NA_real_, baseline = mean(actual, na.rm = TRUE)))
  }
  ord <- order(pred, decreasing = TRUE)
  labels_ord <- actual[ord]
  prec <- cumsum(labels_ord) / seq_along(labels_ord)
  rec  <- cumsum(labels_ord) / sum(labels_ord)
  n <- length(prec)
  pr_auc <- sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
  list(pr_auc = pr_auc, baseline = mean(actual))
}

# ── Helper 6: Bootstrap CI (block bootstrap 12m, N=1000) ──────
bootstrap_ci_pred <- function(pred, actual, n_boot = 1000, block_months = 12) {
  block_days <- block_months * 21
  n <- length(pred)
  n_blocks <- ceiling(n / block_days)
  bss_boot <- numeric(n_boot)
  for (b in 1:n_boot) {
    block_starts <- sample(seq(1, n - block_days + 1, by = 1), n_blocks, replace = TRUE)
    boot_idx <- unlist(lapply(block_starts, function(s) s:(s + block_days - 1)))
    boot_idx <- boot_idx[boot_idx <= n]
    p <- pred[boot_idx]
    a <- actual[boot_idx]
    # Baseline = mean prevalence
    baseline_p <- mean(a, na.rm = TRUE)
    bs_m <- mean((p - a)^2, na.rm = TRUE)
    bs_b <- mean((baseline_p - a)^2, na.rm = TRUE)
    bss_boot[b] <- 1 - bs_m / bs_b
  }
  list(BSS_mean = mean(bss_boot, na.rm = TRUE),
       BSS_lower = quantile(bss_boot, 0.025, na.rm = TRUE),
       BSS_upper = quantile(bss_boot, 0.975, na.rm = TRUE),
       n_boot = n_boot)
}

# ── Helper 7: Spearman regime conditional (AUX) ────────────────
spearman_regime <- function(pred, target, regime_mask) {
  bad_idx <- which(regime_mask == "bad")
  normal_idx <- which(regime_mask == "normal")
  s_bad <- if (length(bad_idx) > 10)
    suppressWarnings(cor(pred[bad_idx], target[bad_idx], method = "spearman", use = "complete.obs")) else NA
  s_normal <- if (length(normal_idx) > 10)
    suppressWarnings(cor(pred[normal_idx], target[normal_idx], method = "spearman", use = "complete.obs")) else NA
  ratio <- if (!is.na(s_bad) && !is.na(s_normal) && s_normal != 0) s_bad / s_normal else NA
  list(spearman_bad = s_bad, spearman_normal = s_normal, ratio = ratio)
}

# ── 메인 실행 ─────────────────────────────────────────────────
run_validation_suite <- function(predictions_path = NULL, targets_path = NULL,
                                  target_col = "y_onset", regime_col = NULL) {

  if (is.null(predictions_path)) {
    predictions_path <- file.path(WS_DIR, "outputs/03_models/stacking_ensemble/predictions_final.parquet")
  }
  if (is.null(targets_path)) {
    targets_path <- file.path(WS_DIR, "outputs/02_targets/targets_full.parquet")
  }

  if (!file.exists(predictions_path)) {
    cat("[validation_suite] predictions_path missing — forge agent S5/S6/S8 결과 대기\n")
    cat("  expected:", predictions_path, "\n")
    return(invisible(NULL))
  }
  if (!file.exists(targets_path)) stop("targets_path missing")

  preds <- as.data.table(read_parquet(predictions_path))
  targets <- as.data.table(read_parquet(targets_path))

  # Filter preds to current target + rename prob_final → p_bear (forge agent schema)
  if ("target" %in% names(preds)) {
    preds <- preds[target == target_col]
  }
  if ("prob_final" %in% names(preds) && !"p_bear" %in% names(preds)) {
    setnames(preds, "prob_final", "p_bear")
  }
  # OOS only filter (split == "oos" if column exists)
  if ("split" %in% names(preds)) {
    preds_oos <- preds[split == "oos"]
    cat(sprintf("[validation_suite] OOS subset: %d rows (full %d)\n",
                nrow(preds_oos), nrow(preds)))
    if (nrow(preds_oos) > 0) preds <- preds_oos
  }

  # Merge on Date
  df <- merge(preds, targets[, c("Date", target_col), with = FALSE], by = "Date", all = FALSE)
  setnames(df, target_col, "actual")
  df <- df[!is.na(actual) & !is.na(p_bear)]

  # Baseline = constant prevalence (학습기간 평균)
  baseline_p <- mean(df$actual)
  df[, baseline := baseline_p]

  cat(sprintf("[validation_suite] N = %d / events = %d (%.2f%%) / target = %s\n",
              nrow(df), sum(df$actual), 100 * baseline_p, target_col))

  # ── Gate 1: DM test ──
  dm <- dm_test_hac(df$p_bear, df$baseline, df$actual, hac_lag = H)
  cat(sprintf("[Gate 1] DM test: stat=%.3f / p=%.4f / n=%d %s\n",
              dm$stat, dm$p_value, dm$n,
              ifelse(!is.na(dm$p_value) && dm$p_value < 0.05, "✅ PASS", "❌ FAIL")))
  write_json(dm, file.path(OUT_DIR, "dm_test.json"), auto_unbox = TRUE, pretty = TRUE)

  # ── Gate 2: Brier Skill ──
  bss <- brier_skill(df$p_bear, df$baseline, df$actual)
  cat(sprintf("[Gate 2] Brier Skill: BSS=%.4f %s\n", bss$BSS,
              ifelse(bss$BSS > 0, "✅ PASS", "❌ FAIL")))
  fwrite(as.data.table(bss[c("BS_model","BS_baseline","BSS")]),
         file.path(OUT_DIR, "brier_skill.csv"))

  # ── Gate 3: Calibration ──
  cal <- calibration_check(df$p_bear, df$actual)
  cal_pass <- (cal$slope >= 0.8 && cal$slope <= 1.2) && (cal$ECE < 0.05)
  cat(sprintf("[Gate 3] Calibration: intercept=%.3f / slope=%.3f / ECE=%.4f %s\n",
              cal$intercept, cal$slope, cal$ECE,
              ifelse(cal_pass, "✅ PASS", "❌ FAIL")))
  fwrite(cal$bin_summary, file.path(OUT_DIR, "calibration_bins.csv"))

  # ── Gate 4: Event-level recall ──
  rec_20 <- event_recall(df$p_bear, df$actual, alert_pct = 0.2)
  rec_baseline_recall <- 0.2  # random alert 20% → recall ≈ 20%
  rec_lift <- rec_20$recall - rec_baseline_recall
  cat(sprintf("[Gate 4] Event recall @ top 20%%: recall=%.3f / lift=%.3f %s\n",
              rec_20$recall, rec_lift,
              ifelse(rec_lift > 0.2, "✅ PASS", "❌ FAIL")))
  write_json(rec_20, file.path(OUT_DIR, "event_recall.json"), auto_unbox = TRUE, pretty = TRUE)

  # ── Gate 5: PR-AUC ──
  pr <- pr_auc_compute(df$p_bear, df$actual)
  pr_lift <- (pr$pr_auc - pr$baseline) / pr$baseline
  cat(sprintf("[Gate 5] PR-AUC: %.4f (baseline %.4f, lift %.2f%%) %s\n",
              pr$pr_auc, pr$baseline, 100 * pr_lift,
              ifelse(pr_lift > 0.2, "✅ PASS", "❌ FAIL")))
  fwrite(as.data.table(pr), file.path(OUT_DIR, "pr_auc.csv"))

  # ── Report: Bootstrap CI ──
  bci <- bootstrap_ci_pred(df$p_bear, df$actual, n_boot = 1000, block_months = 12)
  cat(sprintf("[Report] Bootstrap CI (block 12m, N=1000): BSS=%.4f [%.4f, %.4f]\n",
              bci$BSS_mean, bci$BSS_lower, bci$BSS_upper))
  fwrite(as.data.table(bci), file.path(OUT_DIR, "bootstrap_ci.csv"))

  # ── AUX: Spearman regime conditional (if regime_col provided) ──
  if (!is.null(regime_col) && regime_col %in% names(df)) {
    sp <- spearman_regime(df$p_bear, df$actual, df[[regime_col]])
    cat(sprintf("[AUX] Spearman regime: bad=%.3f / normal=%.3f / ratio=%.3f %s\n",
                sp$spearman_bad, sp$spearman_normal, sp$ratio,
                ifelse(!is.na(sp$ratio) && sp$ratio > 1, "✅ PASS", "⚠ WARN")))
    fwrite(as.data.table(sp), file.path(OUT_DIR, "spearman_regime.csv"))
  }

  # ── Summary markdown ──
  summary_md <- sprintf(
"# Plan v0.4.2 Phase 1 Validation Summary

**Target**: %s
**N**: %d (events %d / %.2f%%)
**Date**: %s

## Gates

| # | Gate | Result | Status |
|---|---|---|---|
| 1 | DM test (HAC lag ≥21) | stat=%.3f / p=%.4f | %s |
| 2 | Brier Skill Score | BSS=%.4f | %s |
| 3 | Calibration | slope=%.3f / ECE=%.4f | %s |
| 4 | Event-level recall (top 20%%) | recall=%.3f / lift=%.3f | %s |
| 5 | PR-AUC | %.4f (lift %.2f%%) | %s |

## Uncertainty Report
- Bootstrap CI (block 12m, N=1000): BSS = %.4f [%.4f, %.4f]

## Phase 2 이동 lock (의무)
- Harvey-t (NW) — portfolio return 적용
- DSR (Bailey-LdP)
- AX-001 v2 crisis_alpha
- Net-of-cost simulation

**Phase 1 = forecast validity only. Trading alpha로 해석 금지.**
",
    target_col, nrow(df), sum(df$actual), 100 * baseline_p, format(Sys.time()),
    dm$stat, dm$p_value, ifelse(!is.na(dm$p_value) && dm$p_value < 0.05, "✅ PASS", "❌ FAIL"),
    bss$BSS, ifelse(bss$BSS > 0, "✅ PASS", "❌ FAIL"),
    cal$slope, cal$ECE, ifelse(cal_pass, "✅ PASS", "❌ FAIL"),
    rec_20$recall, rec_lift, ifelse(rec_lift > 0.2, "✅ PASS", "❌ FAIL"),
    pr$pr_auc, 100 * pr_lift, ifelse(pr_lift > 0.2, "✅ PASS", "❌ FAIL"),
    bci$BSS_mean, bci$BSS_lower, bci$BSS_upper
  )
  writeLines(summary_md, file.path(OUT_DIR, "validation_summary.md"))

  cat("\n[validation_suite] DONE. Summary saved to validation_summary.md\n")
  invisible(list(dm = dm, bss = bss, cal = cal, rec_20 = rec_20, pr = pr, bci = bci))
}

if (!interactive() && identical(sys.nframe(), 0L)) {
  run_validation_suite()
}
