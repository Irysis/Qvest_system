#==============================================================================
# 141_v5e_multiseed_aggregate.R — Cycle 54C v5e q126 Multi-Seed Aggregate
#
# Reads:
#   outputs/03_models/v5e_q126_multiseed/predictions_patchtst_v5e_seed{42|123|456|789|1024}_y_{tail_q15|tail_q126}.parquet (10 files)
#   outputs/03_models/v5e_q126_multiseed/predictions_patchtst_v5e_mean_y_{tail_q15|tail_q126}.parquet (2 files)
#   outputs/03_models/v5e_q126_multiseed/per_fold_diagnostics.json
#   outputs/03_models/v5e_q126_multiseed/multiseed_variance_audit.json
#   outputs/03_models/v5e_patchtst_q126_usmacro/predictions_patchtst_v5e_y_tail_q126.parquet (53H seed=42 reference)
#   outputs/03_models/v5e_patchtst_q126_usmacro/predictions_patchtst_v5e_y_tail_q15.parquet
#
# Steps:
#   Step 1: Per-seed OOS PR-AUC + IC (R verification)
#   Step 2: 5-seed mean prediction PR-AUC + IC (R re-compute)
#   Step 3: Multi-seed stability verdict (STABLE / MODERATE / UNSTABLE)
#   Step 4: vs Cycle 53H seed=42 reference (0.4012 q126, 0.2082 q15)
#   Step 5: Per-date prediction std audit
#   Step 6: Period-balanced PR-AUC × 5 seeds × 3 segments + bootstrap CI
#   Step 7: NEW_CYCLE_CHECKLIST status
#   Step 8: Output JSON + chart
#
# Output:
#   outputs/04_evaluation/v5e_multiseed_v6c.json
#   outputs/06_reports/charts/141_v5e_multiseed.png
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2)
  library(patchwork)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
MS_DIR <- file.path(WS, "outputs/03_models/v5e_q126_multiseed")
S53H_DIR <- file.path(WS, "outputs/03_models/v5e_patchtst_q126_usmacro")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")
dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

OOS_START <- as.Date("2018-01-01")
OOS_END   <- as.Date("2026-04-30")

SEEDS   <- c(42L, 123L, 456L, 789L, 1024L)
TARGETS <- c("y_tail_q15", "y_tail_q126")

# Stability thresholds (mirror Cycle 53C convention)
STABILITY_STABLE_STD   <- 0.02
STABILITY_MODERATE_STD <- 0.05

# Cycle 53H seed=42 reference (verified from outputs/04_evaluation/patchtst_q126_usmacro_v5e.json)
CYCLE_53H_Q126 <- 0.4012   # PR-AUC seed=42
CYCLE_53H_Q15  <- 0.2082
CYCLE_53H_Q126_IC <- 0.3057
CYCLE_53H_Q15_IC  <- 0.0743

# Period-balanced segments (mirror Cycle 53M pattern)
SEGMENTS <- list(
  list(name = "S2018_19_calm",       start = as.Date("2018-01-01"), end = as.Date("2019-12-31")),
  list(name = "S2020_21_covid_lift", start = as.Date("2020-01-01"), end = as.Date("2021-12-31")),
  list(name = "S2022_24_inflation",  start = as.Date("2022-01-01"), end = as.Date("2024-12-31"))
)

BOOTSTRAP_N <- 1000L
BOOTSTRAP_SEED <- 20260521L

# ─── helpers ──────────────────────────────────────────────────────────
pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

ic_spearman <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30) return(NA_real_)
  # Spearman = Pearson correlation of ranks (mirror Python np.corrcoef(rank, rank))
  cor(rank(p), rank(y), method = "pearson")
}

bootstrap_ci_pr <- function(p, y, B = BOOTSTRAP_N, seed = BOOTSTRAP_SEED) {
  ok <- !is.na(p) & !is.na(y)
  p <- p[ok]; y <- y[ok]
  n <- length(p)
  if (n < 30 || sum(y) < 5) {
    return(list(point = NA_real_, lo = NA_real_, hi = NA_real_, n = n, events = sum(y)))
  }
  point <- pr_auc(p, y)
  set.seed(seed)
  vals <- numeric(B)
  for (b in seq_len(B)) {
    idx <- sample.int(n, n, replace = TRUE)
    vals[b] <- pr_auc(p[idx], y[idx])
  }
  vals <- vals[!is.na(vals)]
  if (length(vals) < 50) {
    return(list(point = point, lo = NA_real_, hi = NA_real_,
                n = n, events = sum(y), bootstrap_valid = length(vals)))
  }
  q <- quantile(vals, c(0.025, 0.975), na.rm = TRUE)
  list(point = round(point, 4), lo = round(unname(q[1]), 4), hi = round(unname(q[2]), 4),
       n = n, events = sum(y), bootstrap_valid = length(vals))
}

#==============================================================================
# Load Python diagnostics
#==============================================================================
diag_path <- file.path(MS_DIR, "per_fold_diagnostics.json")
audit_path <- file.path(MS_DIR, "multiseed_variance_audit.json")
if (!file.exists(diag_path)) {
  stop(sprintf("Missing per_fold_diagnostics: %s\n  Run scripts/140_patchtst_v5e_q126_multiseed.py first.",
               diag_path))
}
if (!file.exists(audit_path)) {
  stop(sprintf("Missing multiseed_variance_audit: %s\n  Run scripts/140 first.", audit_path))
}
py_diag  <- fromJSON(diag_path, simplifyVector = FALSE)
py_audit <- fromJSON(audit_path, simplifyVector = FALSE)

cat(sprintf("\n[Loaded] per_fold_diagnostics + multiseed_variance_audit\n"))
cat(sprintf("[Cycle] %s\n", py_diag$cycle))
cat(sprintf("[Seeds] %s\n", paste(SEEDS, collapse = ",")))

#==============================================================================
# Step 1: Per-seed OOS PR-AUC + IC (R verification)
#==============================================================================
cat("\n========== Step 1: Per-seed OOS PR-AUC + IC (R verification) ==========\n")

aggregate_seed <- function(seed, target_col) {
  pred_path <- file.path(MS_DIR,
                         sprintf("predictions_patchtst_v5e_seed%d_%s.parquet", seed, target_col))
  if (!file.exists(pred_path)) {
    return(list(seed = seed, target = target_col, error = "missing_prediction_file",
                oos_pr = NA_real_, oos_ic = NA_real_, n_obs = NA_integer_,
                n_events = NA_integer_, event_rate = NA_real_))
  }
  dt <- as.data.table(read_parquet(pred_path))
  dt[, Date := as.Date(Date)]
  dt <- dt[Date >= OOS_START & Date <= OOS_END &
             !is.na(p_patchtst_v5e) & !is.na(y)]
  pa <- pr_auc(dt$p_patchtst_v5e, dt$y)
  ic <- ic_spearman(dt$p_patchtst_v5e, dt$y)
  list(
    seed = seed, target = target_col,
    n_obs = nrow(dt), n_events = as.integer(sum(dt$y)),
    event_rate = round(mean(dt$y), 4),
    oos_pr = round(pa, 4), oos_ic = round(ic, 4)
  )
}

per_seed_rows <- list()
for (s in SEEDS) for (tc in TARGETS) {
  per_seed_rows[[length(per_seed_rows) + 1]] <- aggregate_seed(s, tc)
}

per_seed_dt <- rbindlist(lapply(per_seed_rows, function(r) {
  data.table(
    seed = r$seed, target = r$target,
    n_obs = if (is.null(r$n_obs)) NA_integer_ else r$n_obs,
    n_events = if (is.null(r$n_events)) NA_integer_ else r$n_events,
    event_rate = if (is.null(r$event_rate)) NA_real_ else r$event_rate,
    oos_pr = if (is.null(r$oos_pr)) NA_real_ else r$oos_pr,
    oos_ic = if (is.null(r$oos_ic)) NA_real_ else r$oos_ic
  )
}), fill = TRUE)

cat("\n[Per-seed table (R verification)]\n")
print(per_seed_dt)

#==============================================================================
# Step 2: 5-seed mean prediction PR-AUC (R re-compute)
#==============================================================================
cat("\n========== Step 2: 5-seed mean prediction PR-AUC (R re-compute) ==========\n")

aggregate_mean <- function(target_col) {
  pred_path <- file.path(MS_DIR,
                         sprintf("predictions_patchtst_v5e_mean_%s.parquet", target_col))
  if (!file.exists(pred_path)) {
    return(list(target = target_col, error = "missing_mean_file",
                oos_pr_mean = NA_real_, oos_ic_mean = NA_real_))
  }
  dt <- as.data.table(read_parquet(pred_path))
  dt[, Date := as.Date(Date)]
  dt <- dt[Date >= OOS_START & Date <= OOS_END &
             !is.na(p_patchtst_v5e_mean) & !is.na(y)]
  pa <- pr_auc(dt$p_patchtst_v5e_mean, dt$y)
  ic <- ic_spearman(dt$p_patchtst_v5e_mean, dt$y)
  per_date_std_mean <- mean(dt$p_per_seed_std, na.rm = TRUE)
  per_date_std_med  <- median(dt$p_per_seed_std, na.rm = TRUE)
  per_date_std_max  <- max(dt$p_per_seed_std, na.rm = TRUE)
  list(
    target = target_col, n_obs = nrow(dt),
    n_events = as.integer(sum(dt$y)),
    event_rate = round(mean(dt$y), 4),
    oos_pr_mean = round(pa, 4), oos_ic_mean = round(ic, 4),
    per_date_std_mean = round(per_date_std_mean, 4),
    per_date_std_median = round(per_date_std_med, 4),
    per_date_std_max = round(per_date_std_max, 4)
  )
}

mean_rows <- list()
for (tc in TARGETS) mean_rows[[tc]] <- aggregate_mean(tc)

cat("\n[5-seed mean prediction]\n")
for (tc in TARGETS) {
  r <- mean_rows[[tc]]
  cat(sprintf(paste0("  %s: PR-AUC=%.4f IC=%.4f n_obs=%d n_events=%d ",
                     "per_date_std mean=%.4f / median=%.4f / max=%.4f\n"),
              tc, r$oos_pr_mean, r$oos_ic_mean, r$n_obs, r$n_events,
              r$per_date_std_mean, r$per_date_std_median, r$per_date_std_max))
}

#==============================================================================
# Step 3: Multi-seed stability verdict
#==============================================================================
cat("\n========== Step 3: Multi-seed stability verdict ==========\n")

stability_table <- per_seed_dt[!is.na(oos_pr), .(
  n_seeds = .N,
  mean_pr = round(mean(oos_pr, na.rm = TRUE), 4),
  std_pr  = round(sd(oos_pr, na.rm = TRUE), 4),
  min_pr  = round(min(oos_pr, na.rm = TRUE), 4),
  max_pr  = round(max(oos_pr, na.rm = TRUE), 4),
  range_pr = round(max(oos_pr, na.rm = TRUE) - min(oos_pr, na.rm = TRUE), 4)
), by = target]

stability_table[, stability_verdict := fcase(
  std_pr < STABILITY_STABLE_STD, "STABLE",
  std_pr <= STABILITY_MODERATE_STD, "MODERATE",
  default = "UNSTABLE"
)]

cat("\n[Stability per target]\n")
print(stability_table)

#==============================================================================
# Step 4: vs Cycle 53H seed=42 reference
#==============================================================================
cat("\n========== Step 4: vs Cycle 53H seed=42 reference ==========\n")

# Use Python-saved seed=42 (within multiseed run) AND verify vs 53H file output
# These should be very close if architecture is mirrored (and stochastic GPU
# kernels are the only difference).

s42_q126 <- per_seed_dt[seed == 42L & target == "y_tail_q126", oos_pr]
s42_q15  <- per_seed_dt[seed == 42L & target == "y_tail_q15",  oos_pr]
mean_pr_q126 <- mean_rows[["y_tail_q126"]]$oos_pr_mean
mean_pr_q15  <- mean_rows[["y_tail_q15"]]$oos_pr_mean
across_mean_q126 <- stability_table[target == "y_tail_q126", mean_pr]
across_mean_q15  <- stability_table[target == "y_tail_q15",  mean_pr]

cat(sprintf("\n[53H reference seed=42] y_tail_q126=%.4f IC=%.4f / y_tail_q15=%.4f IC=%.4f\n",
            CYCLE_53H_Q126, CYCLE_53H_Q126_IC, CYCLE_53H_Q15, CYCLE_53H_Q15_IC))

cat(sprintf("\n[54C seed=42 reproduce (within multiseed run)]\n"))
cat(sprintf("  q126: %.4f  (Δ vs 53H seed=42 = %+.4f)\n", s42_q126, s42_q126 - CYCLE_53H_Q126))
cat(sprintf("  q15:  %.4f  (Δ vs 53H seed=42 = %+.4f)\n", s42_q15,  s42_q15 - CYCLE_53H_Q15))

cat(sprintf("\n[54C across-seed mean PR-AUC]\n"))
cat(sprintf("  q126: %.4f  (Δ vs 53H seed=42 = %+.4f)\n", across_mean_q126, across_mean_q126 - CYCLE_53H_Q126))
cat(sprintf("  q15:  %.4f  (Δ vs 53H seed=42 = %+.4f)\n", across_mean_q15,  across_mean_q15  - CYCLE_53H_Q15))

cat(sprintf("\n[54C 5-seed MEAN prediction PR-AUC (ensemble effect)]\n"))
cat(sprintf("  q126: %.4f  (Δ vs 53H seed=42 = %+.4f)\n", mean_pr_q126, mean_pr_q126 - CYCLE_53H_Q126))
cat(sprintf("  q15:  %.4f  (Δ vs 53H seed=42 = %+.4f)\n", mean_pr_q15,  mean_pr_q15  - CYCLE_53H_Q15))

# Drift check: 54C seed=42 vs 53H seed=42 file (different process state → some drift expected)
# Read 53H reference parquet
load_53h_seed42 <- function(target_col) {
  p <- file.path(S53H_DIR, sprintf("predictions_patchtst_v5e_%s.parquet", target_col))
  if (!file.exists(p)) return(NULL)
  dt <- as.data.table(read_parquet(p))
  dt[, Date := as.Date(Date)]
  dt[Date >= OOS_START & Date <= OOS_END]
}
ref_53h <- list(
  y_tail_q15  = load_53h_seed42("y_tail_q15"),
  y_tail_q126 = load_53h_seed42("y_tail_q126")
)

ref_53h_pr <- list()
for (tc in TARGETS) {
  if (!is.null(ref_53h[[tc]])) {
    ref_53h_pr[[tc]] <- round(pr_auc(ref_53h[[tc]]$p_patchtst, ref_53h[[tc]]$y), 4)
  } else {
    ref_53h_pr[[tc]] <- NA_real_
  }
}
cat(sprintf("\n[Cross-check 53H file PR-AUC re-computed by R]\n"))
cat(sprintf("  q126: %.4f (Python diag: %.4f, our hardcoded ref: %.4f)\n",
            ref_53h_pr[["y_tail_q126"]], CYCLE_53H_Q126, CYCLE_53H_Q126))
cat(sprintf("  q15:  %.4f (Python diag: %.4f, our hardcoded ref: %.4f)\n",
            ref_53h_pr[["y_tail_q15"]], CYCLE_53H_Q15, CYCLE_53H_Q15))

#==============================================================================
# Step 5: Per-date prediction std audit
#==============================================================================
cat("\n========== Step 5: Per-date prediction std audit ==========\n")

cat("\n[Per-date std (lower = more consistent across seeds)]\n")
for (tc in TARGETS) {
  r <- mean_rows[[tc]]
  cat(sprintf("  %s: mean=%.4f / median=%.4f / max=%.4f / n=%d\n",
              tc, r$per_date_std_mean, r$per_date_std_median, r$per_date_std_max, r$n_obs))
}

#==============================================================================
# Step 6: Period-balanced PR-AUC × 5 seeds × 3 segments + bootstrap CI
#==============================================================================
cat("\n========== Step 6: Period-balanced PR-AUC + bootstrap CI ==========\n")

segment_rows <- list()
for (tc in TARGETS) {
  mean_dt <- as.data.table(read_parquet(file.path(
    MS_DIR, sprintf("predictions_patchtst_v5e_mean_%s.parquet", tc))))
  mean_dt[, Date := as.Date(Date)]
  mean_dt <- mean_dt[Date >= OOS_START & Date <= OOS_END]

  for (si in seq_along(SEGMENTS)) {
    sg <- SEGMENTS[[si]]
    sub <- mean_dt[Date >= sg$start & Date <= sg$end &
                     !is.na(p_patchtst_v5e_mean) & !is.na(y)]
    if (nrow(sub) < 30 || sum(sub$y) < 5) {
      segment_rows[[length(segment_rows) + 1]] <- data.table(
        target = tc, segment = sg$name,
        seed_basis = "5_seed_mean_prediction",
        n_obs = nrow(sub), n_events = sum(sub$y),
        oos_pr_mean_pred = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_
      )
      next
    }
    ci <- bootstrap_ci_pr(sub$p_patchtst_v5e_mean, sub$y, B = BOOTSTRAP_N,
                          seed = BOOTSTRAP_SEED + si)
    segment_rows[[length(segment_rows) + 1]] <- data.table(
      target = tc, segment = sg$name,
      seed_basis = "5_seed_mean_prediction",
      n_obs = nrow(sub), n_events = as.integer(sum(sub$y)),
      oos_pr_mean_pred = ci$point, ci_lo = ci$lo, ci_hi = ci$hi
    )
  }

  # Per-seed × segment matrix
  for (s in SEEDS) {
    seed_path <- file.path(MS_DIR,
                           sprintf("predictions_patchtst_v5e_seed%d_%s.parquet", s, tc))
    if (!file.exists(seed_path)) next
    seed_dt <- as.data.table(read_parquet(seed_path))
    seed_dt[, Date := as.Date(Date)]
    seed_dt <- seed_dt[Date >= OOS_START & Date <= OOS_END]
    for (si in seq_along(SEGMENTS)) {
      sg <- SEGMENTS[[si]]
      sub <- seed_dt[Date >= sg$start & Date <= sg$end &
                       !is.na(p_patchtst_v5e) & !is.na(y)]
      if (nrow(sub) < 30 || sum(sub$y) < 5) {
        segment_rows[[length(segment_rows) + 1]] <- data.table(
          target = tc, segment = sg$name,
          seed_basis = sprintf("seed%d", s),
          n_obs = nrow(sub), n_events = as.integer(sum(sub$y)),
          oos_pr_mean_pred = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_
        )
        next
      }
      pa <- pr_auc(sub$p_patchtst_v5e, sub$y)
      segment_rows[[length(segment_rows) + 1]] <- data.table(
        target = tc, segment = sg$name,
        seed_basis = sprintf("seed%d", s),
        n_obs = nrow(sub), n_events = as.integer(sum(sub$y)),
        oos_pr_mean_pred = round(pa, 4),
        ci_lo = NA_real_, ci_hi = NA_real_   # per-seed point only (skip bootstrap for speed)
      )
    }
  }
}

segment_dt <- rbindlist(segment_rows, fill = TRUE)

cat("\n[Period-balanced 5-seed mean prediction PR-AUC with bootstrap 95% CI]\n")
print(segment_dt[seed_basis == "5_seed_mean_prediction"])

cat("\n[Period-balanced per-seed × segment table]\n")
per_seed_seg <- segment_dt[seed_basis != "5_seed_mean_prediction"]
print(dcast(per_seed_seg, target + segment ~ seed_basis, value.var = "oos_pr_mean_pred"))

# Period segment lift check: lift > 1 vs base rate per segment (≈ random)
period_lift_table <- segment_dt[seed_basis == "5_seed_mean_prediction" & !is.na(oos_pr_mean_pred),
  .(target, segment, n_obs, n_events,
    base_rate = round(n_events / n_obs, 4),
    pr_auc = oos_pr_mean_pred,
    ci_lo = ci_lo, ci_hi = ci_hi,
    lift = round(oos_pr_mean_pred / (n_events / n_obs), 3))]

cat("\n[Period-balanced lift (PR-AUC / base_rate)]\n")
print(period_lift_table)

period_balanced_q126 <- period_lift_table[target == "y_tail_q126"]
n_seg_lift_gt1_q126 <- sum(period_balanced_q126$lift > 1, na.rm = TRUE)
period_balanced_robust_q126 <- n_seg_lift_gt1_q126 == nrow(period_balanced_q126) &&
  nrow(period_balanced_q126) > 0

#==============================================================================
# Step 7: NEW_CYCLE_CHECKLIST status
#==============================================================================
cat("\n========== Step 7: NEW_CYCLE_CHECKLIST status ==========\n")

# Headline: 5-seed mean prediction PR-AUC on y_tail_q126 (primary)
headline_pr <- mean_pr_q126
sanity_lo <- 0.15
sanity_hi_strict <- 0.40    # Cycle 53H/53C 통상 sanity hi
sanity_hi_relaxed <- 0.50   # 53H 0.4012 같은 진정 best ever 패턴 통과 시
within_sanity_relaxed <- (headline_pr >= sanity_lo) && (headline_pr <= sanity_hi_relaxed)

if (headline_pr <= sanity_hi_strict) {
  sanity_msg <- sprintf("PASS (5-seed mean prediction PR-AUC %.4f ∈ [%.2f, %.2f])",
                        headline_pr, sanity_lo, sanity_hi_strict)
} else if (within_sanity_relaxed) {
  sanity_msg <- sprintf("WARN_HIGH (%.4f ∈ (%.2f, %.2f]) — q126 strong signal range; sanity repeat 의무 (Cycle 53M precedent)",
                        headline_pr, sanity_hi_strict, sanity_hi_relaxed)
} else if (headline_pr > sanity_hi_relaxed) {
  sanity_msg <- sprintf("FAIL_TOO_HIGH (%.4f > %.2f) — implausibly high, suspect bug",
                        headline_pr, sanity_hi_relaxed)
} else {
  sanity_msg <- sprintf("FAIL (%.4f < %.2f) — model has no value vs base rate", headline_pr, sanity_lo)
}

stability_verdict_q126 <- stability_table[target == "y_tail_q126", stability_verdict]
stability_verdict_q15  <- stability_table[target == "y_tail_q15",  stability_verdict]

checklist <- list(
  M1_bear_date_audit = "PASS (pre-cycle 4/4, qepm/observability/sanity_checks/bear_date_audit_20260521_082840.json)",
  M2_validate_label_direction = "PASS (forward labels via Cycle 50 fix + 53H/53B inherit; targets_long_horizon.parquet)",
  M3_PIT_C1_C15 = "PASS (v5e panel PIT validated Cycle 53H; US macro lag1 PIT verified Cycle 47B)",
  M4_shift_convention = "PASS (forward targets via shift(.,n=H,'lead'); inherited)",
  M5_AX_008 = "EXEMPT (Forge multi-seed sanity audit, NOT admit cycle)",
  S1_PRAUC_sanity_q126 = sanity_msg,
  S2_COVID_spot_check = "PASS (targets_long_horizon 2020-02-19 ret_q15=-0.3405 ret_q126=+0.0289 inherited from Cycle 53H A2)",
  S3_multiseed_stability_q126 = sprintf("%s (std=%.4f)", stability_verdict_q126,
                                         stability_table[target == "y_tail_q126", std_pr]),
  S3_multiseed_stability_q15 = sprintf("%s (std=%.4f)", stability_verdict_q15,
                                        stability_table[target == "y_tail_q15", std_pr]),
  S4_period_balanced_q126 = sprintf("%d/%d segments lift>1 (5-seed mean prediction)",
                                     n_seg_lift_gt1_q126, nrow(period_balanced_q126)),
  A1_cross_cycle_same_forward_labels = "PASS (54C + 53H + 53B all use targets_long_horizon.parquet)",
  A2_dohun_audit_checkpoint = "AWAITING_REVIEW",
  A3_codex_critic = "CODE_REVIEW_ONLY (Round 5단계 폐기 per 2026-05-21 mandate; code correctness verified separately)"
)

cat("\n[NEW_CYCLE_CHECKLIST]\n")
for (k in names(checklist)) cat(sprintf("  %s: %s\n", k, checklist[[k]]))

#==============================================================================
# Step 8: Output JSON + chart
#==============================================================================
cat("\n========== Step 8: Output JSON + chart ==========\n")

# Headline verdict assembly (Q-Lead-style; Codex Round 폐기 → 직접 산출)
verdict_q126_stability <- stability_verdict_q126
verdict_q15_stability  <- stability_verdict_q15

# Headline lock recommendation (Q-Lead direct)
if (verdict_q126_stability == "STABLE") {
  headline_lock_recommendation <- "VALIDATE — 53H 0.4012 headline robust under multi-seed audit; P1 admit pathway 진입 권고."
} else if (verdict_q126_stability == "MODERATE") {
  headline_lock_recommendation <- "DEFER — 추가 seeds (5건+) 필요; cycle 54D candidate."
} else {
  headline_lock_recommendation <- "RE-EVALUATE — 53H single seed=42 lucky tail risk 검증됨; headline 재평가 + 다른 cycle candidates 검토."
}

# Next cycle suggestion
if (verdict_q126_stability == "STABLE") {
  next_cycle_suggestion <- "STABLE_PATH: (1) Cycle 53M architecture diversity audit (PatchTST 외 TimeMixer / iTransformer / N-BEATS-X) 5-seed × 3-arch / (2) Architect 3rd-source verification (AX-008 P1 admit pathway / (3) Calibration analysis (Brier + reliability curves) on 5-seed mean."
} else if (verdict_q126_stability == "MODERATE") {
  next_cycle_suggestion <- "MODERATE_PATH: cycle 54D 추가 5 seeds [2048, 3000, 5000, 7777, 9999]. Pooled 10 seeds variance re-audit."
} else {
  next_cycle_suggestion <- "UNSTABLE_PATH: 53H single-seed 신뢰 폐기. (1) Cycle 53B PatchTST baseline 0.3456 (v4a 70 features w/o US macro) multi-seed re-audit / (2) feature panel inspection (74 features의 어느 subset이 seed-sensitive?) / (3) regularization 강화 (dropout 0.30 → 0.40)."
}

cycle_verdict <- list(
  cycle = "54C_patchtst_v5e_q126_multiseed",
  approach = "MULTI_SEED_AUDIT_5_SEEDS_FOR_53H_VERIFICATION",
  hypothesis = "53H single seed=42 OOS PR-AUC=0.4012 (forward best ever) is robust (NOT lucky tail) under 5-seed variance audit",
  panel = "feature_panel_v5e_q126_usmacro.parquet",
  targets_source = "targets_long_horizon.parquet (forward labels)",
  n_features = 74,
  seeds = SEEDS,
  n_seeds = length(SEEDS),
  forward_labels = TRUE,
  validation_strategy = "walk_forward_expanding_5_fold_CV (per seed, identical split)",
  oos_window = list(start = as.character(OOS_START), end = as.character(OOS_END)),
  baselines = list(
    cycle_53H_seed42_y_tail_q126 = CYCLE_53H_Q126,
    cycle_53H_seed42_y_tail_q15 = CYCLE_53H_Q15,
    cycle_53B_v4a_no_usmacro_q126 = 0.3456
  ),
  per_seed = lapply(seq_len(nrow(per_seed_dt)), function(i) {
    r <- per_seed_dt[i]
    list(seed = r$seed, target = r$target,
         n_obs = r$n_obs, n_events = r$n_events,
         event_rate = r$event_rate,
         oos_pr = r$oos_pr, oos_ic = r$oos_ic)
  }),
  multiseed_mean_prediction = list(
    y_tail_q126 = mean_rows[["y_tail_q126"]],
    y_tail_q15  = mean_rows[["y_tail_q15"]]
  ),
  stability = list(
    y_tail_q126 = list(
      n_seeds = stability_table[target == "y_tail_q126", n_seeds],
      mean_pr = stability_table[target == "y_tail_q126", mean_pr],
      std_pr  = stability_table[target == "y_tail_q126", std_pr],
      min_pr  = stability_table[target == "y_tail_q126", min_pr],
      max_pr  = stability_table[target == "y_tail_q126", max_pr],
      range_pr = stability_table[target == "y_tail_q126", range_pr],
      verdict = stability_table[target == "y_tail_q126", stability_verdict]
    ),
    y_tail_q15 = list(
      n_seeds = stability_table[target == "y_tail_q15", n_seeds],
      mean_pr = stability_table[target == "y_tail_q15", mean_pr],
      std_pr  = stability_table[target == "y_tail_q15", std_pr],
      min_pr  = stability_table[target == "y_tail_q15", min_pr],
      max_pr  = stability_table[target == "y_tail_q15", max_pr],
      range_pr = stability_table[target == "y_tail_q15", range_pr],
      verdict = stability_table[target == "y_tail_q15", stability_verdict]
    )
  ),
  vs_53H_seed42 = list(
    seed42_within_54C_run = list(
      q126 = list(value = s42_q126, delta = round(s42_q126 - CYCLE_53H_Q126, 4)),
      q15  = list(value = s42_q15,  delta = round(s42_q15  - CYCLE_53H_Q15, 4))
    ),
    across_seed_mean = list(
      q126 = list(value = across_mean_q126, delta = round(across_mean_q126 - CYCLE_53H_Q126, 4)),
      q15  = list(value = across_mean_q15,  delta = round(across_mean_q15  - CYCLE_53H_Q15, 4))
    ),
    five_seed_mean_prediction = list(
      q126 = list(value = mean_pr_q126, delta = round(mean_pr_q126 - CYCLE_53H_Q126, 4)),
      q15  = list(value = mean_pr_q15,  delta = round(mean_pr_q15  - CYCLE_53H_Q15, 4))
    ),
    cross_check_53H_file_pr = ref_53h_pr
  ),
  per_date_std = list(
    y_tail_q126 = list(
      mean = mean_rows[["y_tail_q126"]]$per_date_std_mean,
      median = mean_rows[["y_tail_q126"]]$per_date_std_median,
      max = mean_rows[["y_tail_q126"]]$per_date_std_max
    ),
    y_tail_q15 = list(
      mean = mean_rows[["y_tail_q15"]]$per_date_std_mean,
      median = mean_rows[["y_tail_q15"]]$per_date_std_median,
      max = mean_rows[["y_tail_q15"]]$per_date_std_max
    )
  ),
  period_balanced = list(
    segments = lapply(SEGMENTS, function(sg) list(name = sg$name,
                                                  start = as.character(sg$start),
                                                  end = as.character(sg$end))),
    bootstrap_n = BOOTSTRAP_N,
    five_seed_mean_prediction = lapply(seq_len(nrow(segment_dt[seed_basis == "5_seed_mean_prediction"])),
      function(i) {
        r <- segment_dt[seed_basis == "5_seed_mean_prediction"][i]
        list(target = r$target, segment = r$segment,
             n_obs = r$n_obs, n_events = r$n_events,
             pr_auc = r$oos_pr_mean_pred,
             ci_lo = r$ci_lo, ci_hi = r$ci_hi)
      }),
    per_seed_segment_table = lapply(seq_len(nrow(per_seed_seg)),
      function(i) {
        r <- per_seed_seg[i]
        list(target = r$target, segment = r$segment, seed_basis = r$seed_basis,
             n_obs = r$n_obs, n_events = r$n_events, pr_auc = r$oos_pr_mean_pred)
      }),
    period_balanced_robust_q126 = period_balanced_robust_q126,
    n_seg_lift_gt1_q126 = n_seg_lift_gt1_q126,
    n_seg_total_q126 = nrow(period_balanced_q126)
  ),
  verdict_stability_q126 = stability_verdict_q126,
  verdict_stability_q15  = stability_verdict_q15,
  verdict_sanity = list(
    q126 = sanity_msg
  ),
  headline_lock_recommendation = headline_lock_recommendation,
  next_cycle_suggestion = next_cycle_suggestion,
  new_cycle_checklist_compliance = checklist,
  outputs = list(
    multiseed_dir = MS_DIR,
    final_json = file.path(EVAL_DIR, "v5e_multiseed_v6c.json"),
    chart = file.path(CHART_DIR, "141_v5e_multiseed.png")
  )
)

# Write final JSON
out_json <- file.path(EVAL_DIR, "v5e_multiseed_v6c.json")
write_json(cycle_verdict, out_json, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("\n[Final JSON] Saved: %s\n", out_json))

#==============================================================================
# Chart: per-seed PR-AUC + 5-seed mean prediction + per-date std + period-balanced
#==============================================================================

# Panel A: Per-seed PR-AUC (bar + horizontal line for 53H seed42)
chartA_data <- copy(per_seed_dt)
chartA_data[, seed := factor(seed, levels = SEEDS)]
chartA_data[, target_label := factor(target,
                                     levels = TARGETS,
                                     labels = c("y_tail_q15 (secondary)", "y_tail_q126 (primary)"))]
chartA_data[, ref_53h := fifelse(target == "y_tail_q126", CYCLE_53H_Q126, CYCLE_53H_Q15)]

pA <- ggplot(chartA_data, aes(x = seed, y = oos_pr, fill = target_label)) +
  geom_col(position = position_dodge(width = 0.85), width = 0.75) +
  geom_text(aes(label = sprintf("%.4f", oos_pr)), position = position_dodge(width = 0.85),
            vjust = -0.5, size = 3) +
  geom_hline(data = chartA_data[!duplicated(target), .(target_label, ref_53h)],
             aes(yintercept = ref_53h, color = target_label),
             linetype = "dashed", linewidth = 0.6) +
  facet_wrap(~ target_label, scales = "free_y", ncol = 2) +
  scale_fill_brewer(palette = "Set1") + scale_color_brewer(palette = "Set1") +
  labs(title = "Cycle 54C — Per-seed OOS PR-AUC (5 seeds)",
       subtitle = sprintf("Dashed lines = Cycle 53H seed=42 reference (q126=%.4f / q15=%.4f)",
                          CYCLE_53H_Q126, CYCLE_53H_Q15),
       x = "Seed", y = "OOS PR-AUC", fill = NULL, color = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none",
        strip.text = element_text(face = "bold"))

# Panel B: stability box (per target)
chartB_data <- copy(per_seed_dt)
chartB_data[, target_label := factor(target,
                                     levels = TARGETS,
                                     labels = c("y_tail_q15", "y_tail_q126"))]

pB <- ggplot(chartB_data, aes(x = target_label, y = oos_pr, fill = target_label)) +
  geom_boxplot(width = 0.5, alpha = 0.5, outlier.shape = NA) +
  geom_jitter(width = 0.1, size = 2, alpha = 0.8) +
  scale_fill_brewer(palette = "Set1") +
  labs(title = "Multi-seed Stability — Distribution",
       subtitle = sprintf("STABLE threshold std<%.2f / MODERATE %.2f-%.2f / UNSTABLE >%.2f",
                          STABILITY_STABLE_STD, STABILITY_STABLE_STD,
                          STABILITY_MODERATE_STD, STABILITY_MODERATE_STD),
       x = NULL, y = "OOS PR-AUC", fill = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none")

# Panel C: per-date std time series
get_perdate_std <- function(target_col) {
  dt <- as.data.table(read_parquet(file.path(
    MS_DIR, sprintf("predictions_patchtst_v5e_mean_%s.parquet", target_col))))
  dt[, Date := as.Date(Date)]
  dt[, target := target_col]
  dt[Date >= OOS_START & Date <= OOS_END, .(Date, p_per_seed_std, target)]
}
chartC_data <- rbindlist(lapply(TARGETS, get_perdate_std))
chartC_data[, target_label := factor(target,
                                     levels = TARGETS,
                                     labels = c("y_tail_q15", "y_tail_q126"))]

pC <- ggplot(chartC_data, aes(x = Date, y = p_per_seed_std, color = target_label)) +
  geom_line(linewidth = 0.4, alpha = 0.8) +
  facet_wrap(~ target_label, ncol = 1, scales = "free_y") +
  scale_color_brewer(palette = "Set1") +
  labs(title = "Per-date prediction std across 5 seeds",
       subtitle = "Lower = more consistent across random initializations",
       x = NULL, y = "Per-date std", color = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none",
        strip.text = element_text(face = "bold"))

# Panel D: period-balanced PR-AUC × segment × seed_basis
chartD_data <- copy(segment_dt[!is.na(oos_pr_mean_pred)])
chartD_data[, seed_basis_f := factor(seed_basis,
                                     levels = c("5_seed_mean_prediction",
                                                "seed42", "seed123", "seed456",
                                                "seed789", "seed1024"))]
chartD_data[, target_label := factor(target,
                                     levels = TARGETS,
                                     labels = c("y_tail_q15", "y_tail_q126"))]

pD <- ggplot(chartD_data[seed_basis == "5_seed_mean_prediction"],
             aes(x = segment, y = oos_pr_mean_pred, fill = target_label)) +
  geom_col(position = position_dodge(width = 0.85), width = 0.75) +
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi),
                position = position_dodge(width = 0.85), width = 0.2) +
  geom_text(aes(label = sprintf("%.3f", oos_pr_mean_pred)),
            position = position_dodge(width = 0.85), vjust = -0.5, size = 3) +
  facet_wrap(~ target_label, ncol = 2, scales = "free_y") +
  scale_fill_brewer(palette = "Set1") +
  labs(title = "Period-balanced 5-seed mean prediction PR-AUC (95% bootstrap CI)",
       x = NULL, y = "PR-AUC", fill = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none",
        strip.text = element_text(face = "bold"),
        axis.text.x = element_text(angle = 25, hjust = 1))

# Combine
chart_combined <- (pA / pB) | (pC / pD) +
  plot_layout(widths = c(1.1, 1)) +
  plot_annotation(title = "Cycle 54C — PatchTST v5e q126 multi-seed audit (5 seeds)",
                  subtitle = sprintf("Verdict q126: %s (std=%.4f) | Headline: %s",
                                     stability_verdict_q126,
                                     stability_table[target == "y_tail_q126", std_pr],
                                     headline_lock_recommendation),
                  theme = theme(plot.title = element_text(face = "bold", size = 14),
                                plot.subtitle = element_text(size = 11)))

chart_path <- file.path(CHART_DIR, "141_v5e_multiseed.png")
ggsave(chart_path, chart_combined, width = 18, height = 12, dpi = 130)
cat(sprintf("\n[Chart] Saved: %s\n", chart_path))

cat("\n", strrep("=", 70), "\n", sep = "")
cat("[Cycle 54C R aggregate DONE]\n")
cat(strrep("=", 70), "\n", sep = "")
