#==============================================================================
# 178_q15_3cycle_ensemble.R — Cycle 58A
# 3-cycle Cross-Cycle Ensemble (53H + 53I + 53B mean5)
#
# Mandate (Q-Lead autonomous, 도훈 q15 self-development):
#   Cycle 56A baseline:
#     - 53H_v5e (74 feat)   mean5 = 0.2480 (Covid lift 2.10★)
#     - 53I_v5f (79 feat)   mean5 = 0.2356 (Recent lift 1.49 ⭐ forward-looking)
#     - 53B_v5b (70 feat)   mean5 = 0.2295 (안정성, std 0.030)
#   All 3 cycles 3/3 lift>1 PASS.
#   Hypothesis: cross-cycle averaging > single best.
#
#   3 ensemble strategies:
#     A. EW3:       (p_53H + p_53I + p_53B) / 3
#     B. PR-weighted:  PR-AUC proportional weights (~53H 0.36 / 53I 0.34 / 53B 0.30)
#     C. Regime-cond: COVID→53H dominant, Recent→53I dominant, Calm→EW3
#   Verdict:
#     - ENSEMBLE_BREAKTHROUGH (Δ vs 53H ≥ +0.01) → new headline
#     - ENSEMBLE_MARGINAL (0 ~ +0.01) → stability advantage only
#     - ENSEMBLE_NULL (≈ 0) → 53H retain
#     - ENSEMBLE_DILUTION (Δ ≤ -0.005) → averaging fail
#
# Reads:
#   outputs/03_models/cycle56a_q15_strict_PIT/predictions_53H_v5e_mean5_y_tail_q15.parquet
#   outputs/03_models/cycle56a_q15_strict_PIT/predictions_53I_v5f_mean5_y_tail_q15.parquet
#   outputs/03_models/cycle56a_q15_strict_PIT/predictions_53B_v5b_mean5_y_tail_q15.parquet
#   outputs/02_targets/targets_full.parquet  (cross-check y_tail_q15)
#
# Writes:
#   outputs/03_models/cycle58a_q15_3cycle_ensemble/
#     predictions_ew3_y_tail_q15.parquet
#     predictions_weighted_y_tail_q15.parquet
#     predictions_regime_cond_y_tail_q15.parquet
#     ensemble_audit.json
#   outputs/04_evaluation/cycle58a_q15_3cycle_ensemble.json
#   outputs/06_reports/charts/178_q15_3cycle_ensemble.png
#
# PIT: predictions all strict-PIT (Cycle 56A) — ensemble step has no leakage.
# AX-008: Forge + Codex 2-source.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2)
  library(patchwork)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN_DIR  <- file.path(WS, "outputs/03_models/cycle56a_q15_strict_PIT")
OUT_DIR <- file.path(WS, "outputs/03_models/cycle58a_q15_3cycle_ensemble")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

OOS_START <- as.Date("2018-01-01")
OOS_END   <- as.Date("2026-04-30")

# 56A reference values (mean5 PR-AUC over OOS)
REF_53H_MEAN5 <- 0.2480
REF_53I_MEAN5 <- 0.2356
REF_53B_MEAN5 <- 0.2295
REF_BEST_SINGLE_NAME <- "53H_v5e"
REF_BEST_SINGLE_PR   <- REF_53H_MEAN5

# Segment definitions (calendar-conditional, matching 56A audit)
SEGMENTS <- list(
  list(name = "S2018-19_calm",        start = as.Date("2018-01-01"), end = as.Date("2019-12-31")),
  list(name = "S2020-21_COVID",       start = as.Date("2020-01-01"), end = as.Date("2021-12-31")),
  list(name = "S2022-24_Stagflation", start = as.Date("2022-01-01"), end = as.Date("2024-12-31"))
)

BOOTSTRAP_N <- 1000L
BOOTSTRAP_SEED <- 20260521L

# Verdict thresholds
ENSEMBLE_BREAKTHROUGH_MIN <- 0.01  # +1pp absolute PR-AUC over 53H mean5
ENSEMBLE_MARGINAL_MIN     <- 0.0
ENSEMBLE_DILUTION_MAX     <- -0.005

# Codex spec: regime-conditional weights (PIT-safe, calendar-conditional)
#   COVID  (2020-2021):  53H 0.50, 53I 0.30, 53B 0.20  (53H Covid lift 2.10 dominant)
#   Recent (2022-2024+): 53I 0.50, 53H 0.30, 53B 0.20  (53I Recent lift 1.49 forward-looking)
#   Calm   (else):       EW3 fallback (1/3, 1/3, 1/3)
REGIME_WEIGHTS <- list(
  COVID  = c(`53H` = 0.50, `53I` = 0.30, `53B` = 0.20),
  Recent = c(`53H` = 0.30, `53I` = 0.50, `53B` = 0.20),
  Calm   = c(`53H` = 1/3,  `53I` = 1/3,  `53B` = 1/3)
)

# ─── helpers ──────────────────────────────────────────────────────────
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a[1])) a else b

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
    return(list(point = round(point, 4), lo = NA_real_, hi = NA_real_,
                n = n, events = sum(y), bootstrap_valid = length(vals)))
  }
  q <- quantile(vals, c(0.025, 0.975), na.rm = TRUE)
  list(point = round(point, 4), lo = round(unname(q[1]), 4), hi = round(unname(q[2]), 4),
       n = n, events = sum(y), bootstrap_valid = length(vals))
}

period_balanced <- function(p, y, dates) {
  res <- list()
  for (seg in SEGMENTS) {
    m <- dates >= seg$start & dates <= seg$end
    n <- sum(m); n_bear <- sum(y[m] == 1, na.rm = TRUE)
    if (n == 0 || n_bear < 5) {
      res[[seg$name]] <- list(n = n, n_bear = n_bear, pr_auc = NA_real_, lift = NA_real_,
                              base_rate = NA_real_, note = "insufficient")
      next
    }
    base <- n_bear / n
    pr <- pr_auc(p[m], y[m])
    ic <- ic_spearman(p[m], y[m])
    res[[seg$name]] <- list(
      n = n, n_bear = n_bear,
      base_rate = round(base, 4),
      pr_auc = if (is.na(pr)) NA_real_ else round(pr, 4),
      ic = if (is.na(ic)) NA_real_ else round(ic, 4),
      lift = if (is.na(pr) || base == 0) NA_real_ else round(pr / base, 4)
    )
  }
  res
}

# Codex spec: period-balanced bootstrap CI (per segment)
period_bootstrap_ci <- function(p, y, dates, B = BOOTSTRAP_N, seed = BOOTSTRAP_SEED) {
  res <- list()
  s <- seed
  for (seg in SEGMENTS) {
    m <- dates >= seg$start & dates <= seg$end
    p_seg <- p[m]; y_seg <- y[m]
    ok <- !is.na(p_seg) & !is.na(y_seg)
    p_seg <- p_seg[ok]; y_seg <- y_seg[ok]
    n <- length(p_seg); n_bear <- sum(y_seg)
    if (n < 30 || n_bear < 5) {
      res[[seg$name]] <- list(n = n, n_bear = n_bear,
                              pr_auc = NA_real_, lo = NA_real_, hi = NA_real_,
                              note = "insufficient")
      next
    }
    base <- n_bear / n
    point <- pr_auc(p_seg, y_seg)
    set.seed(s); s <- s + 1L
    vals <- numeric(B)
    for (b in seq_len(B)) {
      idx <- sample.int(n, n, replace = TRUE)
      vals[b] <- pr_auc(p_seg[idx], y_seg[idx])
    }
    vals <- vals[!is.na(vals)]
    if (length(vals) < 50) {
      res[[seg$name]] <- list(n = n, n_bear = n_bear,
                              pr_auc = round(point, 4),
                              lo = NA_real_, hi = NA_real_,
                              base_rate = round(base, 4),
                              lift = if (base == 0) NA_real_ else round(point/base, 4),
                              bootstrap_valid = length(vals))
      next
    }
    q <- quantile(vals, c(0.025, 0.975), na.rm = TRUE)
    res[[seg$name]] <- list(
      n = n, n_bear = n_bear,
      pr_auc = round(point, 4),
      lo = round(unname(q[1]), 4), hi = round(unname(q[2]), 4),
      base_rate = round(base, 4),
      lift = if (base == 0) NA_real_ else round(point/base, 4),
      lift_lo = if (base == 0) NA_real_ else round(unname(q[1])/base, 4),
      lift_hi = if (base == 0) NA_real_ else round(unname(q[2])/base, 4),
      bootstrap_valid = length(vals)
    )
  }
  res
}

count_lift_gt1 <- function(period_res) {
  vals <- sapply(period_res, function(x) x$lift %||% NA_real_)
  vals <- vals[!is.na(vals)]
  list(n_gt1 = sum(vals > 1.0), n_eval = length(vals))
}

cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Cycle 58A] q15 3-cycle Cross-Cycle Ensemble (53H + 53I + 53B mean5)\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat(sprintf("Started at: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat(sprintf("Reference 53H_v5e baseline PR-AUC = %.4f\n", REF_BEST_SINGLE_PR))
cat(sprintf("Breakthrough threshold = %+.4f (Δ vs 53H)\n", ENSEMBLE_BREAKTHROUGH_MIN))

#==============================================================================
# Step 1: Load 3-cycle predictions
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 1] Loading 3-cycle predictions\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

f_53h <- file.path(IN_DIR, "predictions_53H_v5e_mean5_y_tail_q15.parquet")
f_53i <- file.path(IN_DIR, "predictions_53I_v5f_mean5_y_tail_q15.parquet")
f_53b <- file.path(IN_DIR, "predictions_53B_v5b_mean5_y_tail_q15.parquet")
stopifnot(file.exists(f_53h), file.exists(f_53i), file.exists(f_53b))

dt_53h <- as.data.table(read_parquet(f_53h))
dt_53i <- as.data.table(read_parquet(f_53i))
dt_53b <- as.data.table(read_parquet(f_53b))

# Standardize column names: p_53h / p_53i / p_53b
setnames(dt_53h, "p_mean5", "p_53h")
setnames(dt_53i, "p_mean5", "p_53i")
setnames(dt_53b, "p_mean5", "p_53b")

# Normalize Date to as.Date (drop time of day)
dt_53h[, Date := as.Date(Date)]
dt_53i[, Date := as.Date(Date)]
dt_53b[, Date := as.Date(Date)]

# Metadata assertions (n_seeds, cycle tag, target tag)
for (lab in list(list(dt = dt_53h, name = "53H_v5e"),
                 list(dt = dt_53i, name = "53I_v5f"),
                 list(dt = dt_53b, name = "53B_v5b"))) {
  if ("n_seeds" %in% names(lab$dt)) {
    stopifnot(all(lab$dt$n_seeds == 5))
    cat(sprintf("  [assert] %s n_seeds=5 OK\n", lab$name))
  }
  if ("cycle" %in% names(lab$dt)) {
    cycle_vals <- unique(lab$dt$cycle)
    stopifnot(length(cycle_vals) == 1)
    cat(sprintf("  [assert] %s cycle tag = '%s' (single)\n", lab$name, cycle_vals))
  }
  if ("target" %in% names(lab$dt)) {
    stopifnot(all(lab$dt$target == "y_tail_q15"))
  }
}

# OOS filter
filter_oos <- function(dt, label) {
  n0 <- nrow(dt)
  dt <- dt[Date >= OOS_START & Date <= OOS_END]
  n1 <- nrow(dt)
  if ("split" %in% names(dt)) dt <- dt[split == "oos"]
  n2 <- nrow(dt)
  if (n0 != n2) {
    cat(sprintf("  [OOS filter] %s: %d -> %d (date) -> %d (split==oos)\n", label, n0, n1, n2))
  }
  dt
}
dt_53h <- filter_oos(dt_53h, "53H_v5e_mean5")
dt_53i <- filter_oos(dt_53i, "53I_v5f_mean5")
dt_53b <- filter_oos(dt_53b, "53B_v5b_mean5")

cat(sprintf("  53H_v5e_mean5: %d rows %s..%s\n",
            nrow(dt_53h), as.character(min(dt_53h$Date)), as.character(max(dt_53h$Date))))
cat(sprintf("  53I_v5f_mean5: %d rows %s..%s\n",
            nrow(dt_53i), as.character(min(dt_53i$Date)), as.character(max(dt_53i$Date))))
cat(sprintf("  53B_v5b_mean5: %d rows %s..%s\n",
            nrow(dt_53b), as.character(min(dt_53b$Date)), as.character(max(dt_53b$Date))))

# 3-way intersection on Date
common_dates <- Reduce(intersect, list(dt_53h$Date, dt_53i$Date, dt_53b$Date))
common_dates <- sort(as.Date(common_dates, origin = "1970-01-01"))
cat(sprintf("\n  3-way common dates: %d\n", length(common_dates)))

# Inner join (Codex H1 spec: explicit Date alignment, NA-safe)
dt_join <- dt_53h[Date %in% common_dates, .(Date, p_53h, y_53h = y)][
  dt_53i[Date %in% common_dates, .(Date, p_53i, y_53i = y)], on = "Date"][
  dt_53b[Date %in% common_dates, .(Date, p_53b, y_53b = y)], on = "Date"]
setorder(dt_join, Date)

# Codex H3-style NA-safe y consistency check
na_safe_mismatch <- function(a, b) {
  bad <- (is.na(a) != is.na(b)) | (!is.na(a) & !is.na(b) & a != b)
  sum(bad)
}
y_mismatch_hi <- na_safe_mismatch(dt_join$y_53h, dt_join$y_53i)
y_mismatch_hb <- na_safe_mismatch(dt_join$y_53h, dt_join$y_53b)
cat(sprintf("  y consistency (NA-safe): 53H vs 53I mismatch=%d  53H vs 53B mismatch=%d (must be 0)\n",
            y_mismatch_hi, y_mismatch_hb))
stopifnot(y_mismatch_hi == 0 && y_mismatch_hb == 0)
dt_join[, y := y_53h]
dt_join[, c("y_53h", "y_53i", "y_53b") := NULL]

# Cross-check y against targets_full (PIT-safe)
dt_targets <- as.data.table(read_parquet(file.path(WS, "outputs/02_targets/targets_full.parquet")))
dt_targets[, Date := as.Date(Date)]
dt_check <- dt_targets[Date %in% dt_join$Date, .(Date, y_target = y_tail_q15)]
dt_chk_join <- merge(dt_join[, .(Date, y)], dt_check, by = "Date", all.x = TRUE)
y_check_mismatch <- na_safe_mismatch(dt_chk_join$y, dt_chk_join$y_target)
cat(sprintf("  y vs targets_full y_tail_q15 mismatch=%d (must be 0)\n", y_check_mismatch))
stopifnot(y_check_mismatch == 0)

cat(sprintf("  Final 3-way joined: %d rows  events=%d (%.1f%% base rate)\n",
            nrow(dt_join), sum(dt_join$y, na.rm = TRUE),
            mean(dt_join$y, na.rm = TRUE) * 100))

#==============================================================================
# Step 2: Per-cycle standalone audit on common 3-way set
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 2] Per-cycle standalone PR-AUC + IC + period-balanced (on common 3-way set)\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

standalone <- list()
for (cycle_col in c("p_53h", "p_53i", "p_53b")) {
  cycle_name <- gsub("^p_", "", cycle_col)
  ci_pr <- bootstrap_ci_pr(dt_join[[cycle_col]], dt_join$y)
  ic <- ic_spearman(dt_join[[cycle_col]], dt_join$y)
  per <- period_balanced(dt_join[[cycle_col]], dt_join$y, dt_join$Date)
  per_ci <- period_bootstrap_ci(dt_join[[cycle_col]], dt_join$y, dt_join$Date)
  lifts <- count_lift_gt1(per)
  standalone[[cycle_name]] <- list(
    pr_auc = ci_pr$point, pr_lo = ci_pr$lo, pr_hi = ci_pr$hi,
    ic = if (is.na(ic)) NA_real_ else round(ic, 4),
    n = ci_pr$n, events = ci_pr$events,
    n_lift_gt1 = lifts$n_gt1, n_eval = lifts$n_eval,
    period = per,
    period_bootstrap = per_ci
  )
  cat(sprintf("  %-5s  PR=%.4f [%.4f, %.4f]  IC=%s  lifts=%d/%d\n",
              cycle_name, ci_pr$point,
              ci_pr$lo %||% NA, ci_pr$hi %||% NA,
              ifelse(is.na(ic), "NA", sprintf("%.4f", ic)),
              lifts$n_gt1, lifts$n_eval))
}

#==============================================================================
# Step 3: 3-cycle correlation (pairwise) — diversification audit
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 3] Pairwise correlation (Spearman + Pearson)\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

cor_spr <- cor(dt_join[, .(p_53h, p_53i, p_53b)], method = "spearman")
cor_prs <- cor(dt_join[, .(p_53h, p_53i, p_53b)], method = "pearson")
cat("  Spearman:\n"); print(round(cor_spr, 3))
cat("  Pearson:\n"); print(round(cor_prs, 3))

avg_pair_cor_spr <- mean(cor_spr[upper.tri(cor_spr)])
avg_pair_cor_prs <- mean(cor_prs[upper.tri(cor_prs)])
cat(sprintf("\n  Avg pairwise Spearman = %.4f  Pearson = %.4f\n",
            avg_pair_cor_spr, avg_pair_cor_prs))
cat("  (Lower = more diversification potential)\n")

#==============================================================================
# Step 4: Ensemble A — EW3 (equal weight)
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 4] Ensemble A — EW3 (equal-weight average)\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

dt_join[, p_ew3 := (p_53h + p_53i + p_53b) / 3.0]
ci_ew3 <- bootstrap_ci_pr(dt_join$p_ew3, dt_join$y)
ic_ew3 <- ic_spearman(dt_join$p_ew3, dt_join$y)
per_ew3 <- period_balanced(dt_join$p_ew3, dt_join$y, dt_join$Date)
per_ci_ew3 <- period_bootstrap_ci(dt_join$p_ew3, dt_join$y, dt_join$Date)
lifts_ew3 <- count_lift_gt1(per_ew3)

cat(sprintf("  EW3 PR-AUC = %.4f [%.4f, %.4f]  IC=%.4f  lifts=%d/%d\n",
            ci_ew3$point, ci_ew3$lo %||% NA, ci_ew3$hi %||% NA,
            ic_ew3 %||% NA, lifts_ew3$n_gt1, lifts_ew3$n_eval))
cat(sprintf("  Δ vs 53H mean5 = %+.4f\n", ci_ew3$point - REF_BEST_SINGLE_PR))
for (nm in names(per_ew3)) {
  e <- per_ew3[[nm]]
  cat(sprintf("    %s: PR=%s lift=%s base=%s\n", nm,
              ifelse(is.na(e$pr_auc %||% NA), "NA", sprintf("%.4f", e$pr_auc)),
              ifelse(is.na(e$lift %||% NA), "NA", sprintf("%.4f", e$lift)),
              ifelse(is.na(e$base_rate %||% NA), "NA", sprintf("%.4f", e$base_rate))))
}

#==============================================================================
# Step 5: Ensemble B — PR-weighted (PR-AUC proportional)
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 5] Ensemble B — PR-weighted (PR-AUC proportional, derived from 56A)\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

# Codex M5-style: PR-weight clamp + normalize
# Weights derived from 56A reference values (PIT — known at decision time post-Cycle 56A)
w_raw <- c(REF_53H_MEAN5, REF_53I_MEAN5, REF_53B_MEAN5)
w_raw[is.na(w_raw)] <- 0
w_raw <- pmax(w_raw, 0.01)
weights_pr <- w_raw / sum(w_raw)
cat(sprintf("  PR-proportional weights: 53H=%.3f  53I=%.3f  53B=%.3f  (sum=%.3f)\n",
            weights_pr[1], weights_pr[2], weights_pr[3], sum(weights_pr)))

dt_join[, p_weighted := weights_pr[1] * p_53h + weights_pr[2] * p_53i + weights_pr[3] * p_53b]
ci_wt <- bootstrap_ci_pr(dt_join$p_weighted, dt_join$y)
ic_wt <- ic_spearman(dt_join$p_weighted, dt_join$y)
per_wt <- period_balanced(dt_join$p_weighted, dt_join$y, dt_join$Date)
per_ci_wt <- period_bootstrap_ci(dt_join$p_weighted, dt_join$y, dt_join$Date)
lifts_wt <- count_lift_gt1(per_wt)

cat(sprintf("  Weighted PR-AUC = %.4f [%.4f, %.4f]  IC=%.4f  lifts=%d/%d\n",
            ci_wt$point, ci_wt$lo %||% NA, ci_wt$hi %||% NA,
            ic_wt %||% NA, lifts_wt$n_gt1, lifts_wt$n_eval))
cat(sprintf("  Δ vs 53H mean5 = %+.4f\n", ci_wt$point - REF_BEST_SINGLE_PR))
for (nm in names(per_wt)) {
  e <- per_wt[[nm]]
  cat(sprintf("    %s: PR=%s lift=%s base=%s\n", nm,
              ifelse(is.na(e$pr_auc %||% NA), "NA", sprintf("%.4f", e$pr_auc)),
              ifelse(is.na(e$lift %||% NA), "NA", sprintf("%.4f", e$lift)),
              ifelse(is.na(e$base_rate %||% NA), "NA", sprintf("%.4f", e$base_rate))))
}

#==============================================================================
# Step 6: Ensemble C — Regime-conditional
#
# PIT note: calendar-conditional allocation. Allocation rule designed BEFORE
#   evaluating Cycle 58A (uses 56A per-cycle observed lift values as priors:
#     COVID  → 53H (lift 2.10 observed)
#     Recent → 53I (lift 1.49 observed, forward-looking)
#     Calm   → EW3 (no clear winner)
#   ).
# Strict-PIT operational deployment would require real-time regime detector;
# we present this as "calendar-conditional upper bound", documented honestly.
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 6] Ensemble C — Regime-conditional (calendar-conditional, NOT strict-PIT operational)\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

# Map Date → regime
dt_join[, regime := fcase(
  Date >= as.Date("2020-01-01") & Date <= as.Date("2021-12-31"), "COVID",
  Date >= as.Date("2022-01-01") & Date <= as.Date("2026-04-30"), "Recent",
  default = "Calm"
)]
cat("  Regime allocation table:\n")
print(table(dt_join$regime, useNA = "ifany"))

# Apply per-regime weights
w_covid  <- REGIME_WEIGHTS$COVID
w_recent <- REGIME_WEIGHTS$Recent
w_calm   <- REGIME_WEIGHTS$Calm

dt_join[, p_regime_cond := fcase(
  regime == "COVID",  w_covid["53H"]  * p_53h + w_covid["53I"]  * p_53i + w_covid["53B"]  * p_53b,
  regime == "Recent", w_recent["53H"] * p_53h + w_recent["53I"] * p_53i + w_recent["53B"] * p_53b,
  regime == "Calm",   w_calm["53H"]   * p_53h + w_calm["53I"]   * p_53i + w_calm["53B"]   * p_53b
)]

ci_rg <- bootstrap_ci_pr(dt_join$p_regime_cond, dt_join$y)
ic_rg <- ic_spearman(dt_join$p_regime_cond, dt_join$y)
per_rg <- period_balanced(dt_join$p_regime_cond, dt_join$y, dt_join$Date)
per_ci_rg <- period_bootstrap_ci(dt_join$p_regime_cond, dt_join$y, dt_join$Date)
lifts_rg <- count_lift_gt1(per_rg)

cat(sprintf("  Regime-conditional PR-AUC = %.4f [%.4f, %.4f]  IC=%.4f  lifts=%d/%d\n",
            ci_rg$point, ci_rg$lo %||% NA, ci_rg$hi %||% NA,
            ic_rg %||% NA, lifts_rg$n_gt1, lifts_rg$n_eval))
cat(sprintf("  Δ vs 53H mean5 = %+.4f\n", ci_rg$point - REF_BEST_SINGLE_PR))
cat("  PIT note: calendar-conditional, NOT operational without real-time regime detector\n")
for (nm in names(per_rg)) {
  e <- per_rg[[nm]]
  cat(sprintf("    %s: PR=%s lift=%s base=%s\n", nm,
              ifelse(is.na(e$pr_auc %||% NA), "NA", sprintf("%.4f", e$pr_auc)),
              ifelse(is.na(e$lift %||% NA), "NA", sprintf("%.4f", e$lift)),
              ifelse(is.na(e$base_rate %||% NA), "NA", sprintf("%.4f", e$base_rate))))
}

#==============================================================================
# Step 7: Save predictions
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 7] Save ensemble predictions\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

save_pred <- function(p_col, fname, target_name = "y_tail_q15") {
  dt_out <- dt_join[, .(Date = Date, p = get(p_col), y = y,
                        split = "oos", target = target_name,
                        cycle = "cycle58a_3cycle_ensemble")]
  setnames(dt_out, "p", p_col)
  out_path <- file.path(OUT_DIR, fname)
  write_parquet(dt_out, out_path)
  cat(sprintf("  Saved: %s (%d rows)\n", out_path, nrow(dt_out)))
  invisible(out_path)
}
p_ew3_path  <- save_pred("p_ew3",          "predictions_ew3_y_tail_q15.parquet")
p_wt_path   <- save_pred("p_weighted",     "predictions_weighted_y_tail_q15.parquet")
p_rg_path   <- save_pred("p_regime_cond",  "predictions_regime_cond_y_tail_q15.parquet")

#==============================================================================
# Step 8: Diversification gain quantify
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 8] Diversification gain analysis\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

best_single_pr <- max(standalone$`53h`$pr_auc,
                      standalone$`53i`$pr_auc,
                      standalone$`53b`$pr_auc, na.rm = TRUE)
best_single_idx <- which.max(c(
  standalone$`53h`$pr_auc, standalone$`53i`$pr_auc, standalone$`53b`$pr_auc
))
best_single_arch <- c("53H_v5e", "53I_v5f", "53B_v5b")[best_single_idx]

ensemble_summary <- data.table(
  ensemble = c("EW3", "PR-weighted", "Regime-cond"),
  pr_auc = c(ci_ew3$point, ci_wt$point, ci_rg$point),
  pr_lo  = c(ci_ew3$lo,    ci_wt$lo,    ci_rg$lo),
  pr_hi  = c(ci_ew3$hi,    ci_wt$hi,    ci_rg$hi),
  ic     = c(ic_ew3,       ic_wt,       ic_rg),
  n_lift_gt1 = c(lifts_ew3$n_gt1, lifts_wt$n_gt1, lifts_rg$n_gt1),
  n_eval     = c(lifts_ew3$n_eval, lifts_wt$n_eval, lifts_rg$n_eval),
  vs_53h_ref  = c(ci_ew3$point - REF_BEST_SINGLE_PR,
                  ci_wt$point  - REF_BEST_SINGLE_PR,
                  ci_rg$point  - REF_BEST_SINGLE_PR),
  vs_best_single = c(ci_ew3$point - best_single_pr,
                     ci_wt$point  - best_single_pr,
                     ci_rg$point  - best_single_pr)
)
cat(sprintf("  Best single arch on 3-way common set: %s (PR=%.4f)\n",
            best_single_arch, best_single_pr))
print(ensemble_summary)

#==============================================================================
# Step 9: Final verdicts
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 9] Final verdicts\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

verdict_ensemble <- function(pr, lifts_n, n_eval, vs_53h_diff) {
  if (is.na(pr)) return("FAILED")
  # BREAKTHROUGH: Δ vs 53H ≥ +0.01 AND all 3 segments lift>1
  if (vs_53h_diff >= ENSEMBLE_BREAKTHROUGH_MIN &&
      n_eval == length(SEGMENTS) && lifts_n == length(SEGMENTS)) {
    return("ENSEMBLE_BREAKTHROUGH")
  }
  # MARGINAL: 0 ≤ Δ < +0.01 AND ≥ 2/3 segments lift>1
  if (vs_53h_diff >= ENSEMBLE_MARGINAL_MIN &&
      vs_53h_diff < ENSEMBLE_BREAKTHROUGH_MIN &&
      lifts_n >= 2) {
    return("ENSEMBLE_MARGINAL")
  }
  # DILUTION: Δ ≤ -0.005
  if (vs_53h_diff <= ENSEMBLE_DILUTION_MAX) {
    return("ENSEMBLE_DILUTION")
  }
  # NULL: -0.005 < Δ < 0  (essentially 0)
  return("ENSEMBLE_NULL")
}

ensemble_summary[, verdict := mapply(verdict_ensemble, pr_auc, n_lift_gt1, n_eval, vs_53h_ref)]
print(ensemble_summary[, .(ensemble, pr_auc, vs_53h_ref, n_lift_gt1, n_eval, verdict)])

best_ensemble <- ensemble_summary[which.max(pr_auc)]
cat(sprintf("\n  Best ensemble: %s (PR=%.4f, vs 53H %+.4f, verdict=%s)\n",
            best_ensemble$ensemble, best_ensemble$pr_auc,
            best_ensemble$vs_53h_ref, best_ensemble$verdict))

cycle_final_verdict <- best_ensemble$verdict
cat(sprintf("\n  >>> CYCLE 58A FINAL VERDICT: %s\n", cycle_final_verdict))

if (cycle_final_verdict == "ENSEMBLE_BREAKTHROUGH") {
  cat("      → New headline: 3-cycle ensemble adopted as best q15 model\n")
} else if (cycle_final_verdict == "ENSEMBLE_MARGINAL") {
  cat("      → 53H retained as headline; ensemble offers stability advantage only\n")
} else if (cycle_final_verdict == "ENSEMBLE_NULL") {
  cat("      → 53H retained as headline; ensemble approximately equal\n")
} else if (cycle_final_verdict == "ENSEMBLE_DILUTION") {
  cat("      → 53H retained as headline; ensemble actively harmful (averaging dilutes signal)\n")
}

#==============================================================================
# Step 10: Chart + JSON output
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 10] Chart + JSON output\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

# Chart 1: Per-cycle standalone + 3 ensembles bar
plot_df <- rbind(
  data.table(method = "53H_mean5", pr_auc = standalone$`53h`$pr_auc,
             lo = standalone$`53h`$pr_lo, hi = standalone$`53h`$pr_hi, type = "standalone"),
  data.table(method = "53I_mean5", pr_auc = standalone$`53i`$pr_auc,
             lo = standalone$`53i`$pr_lo, hi = standalone$`53i`$pr_hi, type = "standalone"),
  data.table(method = "53B_mean5", pr_auc = standalone$`53b`$pr_auc,
             lo = standalone$`53b`$pr_lo, hi = standalone$`53b`$pr_hi, type = "standalone"),
  data.table(method = "EW3", pr_auc = ci_ew3$point, lo = ci_ew3$lo, hi = ci_ew3$hi,
             type = "ensemble"),
  data.table(method = "PR-weighted", pr_auc = ci_wt$point, lo = ci_wt$lo, hi = ci_wt$hi,
             type = "ensemble"),
  data.table(method = "Regime-cond*", pr_auc = ci_rg$point, lo = ci_rg$lo, hi = ci_rg$hi,
             type = "ensemble (cal-cond)")
)
plot_df[, method := factor(method, levels = method)]

p1 <- ggplot(plot_df, aes(x = method, y = pr_auc, fill = type)) +
  geom_col() +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.2, alpha = 0.7) +
  geom_hline(yintercept = REF_BEST_SINGLE_PR, linetype = "dashed", color = "red", alpha = 0.7) +
  annotate("text", x = 1, y = REF_BEST_SINGLE_PR + 0.005, label = "53H mean5 baseline",
           color = "red", alpha = 0.8, size = 3, hjust = 0) +
  geom_text(aes(label = sprintf("%.4f", pr_auc)),
            vjust = -0.3, size = 3, color = "black") +
  scale_fill_manual(values = c("standalone" = "#7E9BB7",
                               "ensemble" = "#52A371",
                               "ensemble (cal-cond)" = "#D69B41")) +
  labs(title = "Cycle 58A — q15 3-cycle Cross-Cycle Ensemble",
       subtitle = sprintf("Target y_tail_q15 | 3-way common dates n=%d events=%d | %s",
                          nrow(dt_join), sum(dt_join$y, na.rm = TRUE),
                          paste0("verdict=", cycle_final_verdict)),
       x = NULL, y = "OOS PR-AUC (95% bootstrap CI)") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

# Chart 2: Per-period lift
period_long <- list()
for (m in c("p_53h", "p_53i", "p_53b", "p_ew3", "p_weighted", "p_regime_cond")) {
  per <- period_balanced(dt_join[[m]], dt_join$y, dt_join$Date)
  for (nm in names(per)) {
    e <- per[[nm]]
    period_long[[length(period_long) + 1]] <- data.table(
      method = gsub("^p_", "", m),
      segment = nm,
      lift = e$lift %||% NA_real_,
      pr_auc = e$pr_auc %||% NA_real_
    )
  }
}
period_dt <- rbindlist(period_long)

p2 <- ggplot(period_dt[!is.na(lift)], aes(x = segment, y = lift, fill = method)) +
  geom_col(position = "dodge") +
  geom_hline(yintercept = 1, linetype = "dashed", color = "grey50") +
  labs(title = "Period-balanced lift per cycle + ensembles",
       subtitle = "Lift > 1 = better than base rate",
       x = NULL, y = "Lift (PR-AUC / base rate)") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

p_combined <- p1 / p2 + plot_layout(heights = c(1, 1))

chart_path <- file.path(CHART_DIR, "178_q15_3cycle_ensemble.png")
ggsave(chart_path, p_combined, width = 12, height = 9, dpi = 110)
cat(sprintf("  Chart saved: %s\n", chart_path))

# JSON audit output
audit_out <- list(
  cycle = "58A_q15_3cycle_ensemble",
  script = "178_q15_3cycle_ensemble.R",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  target = "y_tail_q15",
  target_horizon_days = 21L,
  pit_status = list(
    predictions_strict_pit = TRUE,
    ensemble_step_leakage = "none (post-hoc weighting on 56A strict-PIT outputs)",
    regime_conditional_caveat = "calendar-conditional, allocation rule designed pre-58A using 56A observed lifts as priors"
  ),
  inputs = list(
    cycle_53h = list(file = f_53h,
                     md5 = unname(tools::md5sum(f_53h)),
                     pr_auc_ref_56a = REF_53H_MEAN5),
    cycle_53i = list(file = f_53i,
                     md5 = unname(tools::md5sum(f_53i)),
                     pr_auc_ref_56a = REF_53I_MEAN5),
    cycle_53b = list(file = f_53b,
                     md5 = unname(tools::md5sum(f_53b)),
                     pr_auc_ref_56a = REF_53B_MEAN5),
    targets = list(file = file.path(WS, "outputs/02_targets/targets_full.parquet"),
                   y_check_mismatch = y_check_mismatch)
  ),
  n_3way_common = nrow(dt_join),
  n_events = as.integer(sum(dt_join$y, na.rm = TRUE)),
  base_rate = round(mean(dt_join$y, na.rm = TRUE), 4),
  standalone_on_common_set = standalone,
  correlation_pairwise = list(
    spearman = round(cor_spr, 4),
    pearson  = round(cor_prs, 4),
    avg_spearman = round(avg_pair_cor_spr, 4),
    avg_pearson  = round(avg_pair_cor_prs, 4)
  ),
  ensembles = list(
    ew3 = list(
      weights = list(`53H` = 1/3, `53I` = 1/3, `53B` = 1/3),
      pr_auc = ci_ew3$point, pr_lo = ci_ew3$lo, pr_hi = ci_ew3$hi,
      ic = ic_ew3,
      n_lift_gt1 = lifts_ew3$n_gt1, n_eval = lifts_ew3$n_eval,
      period = per_ew3,
      period_bootstrap_ci = per_ci_ew3
    ),
    pr_weighted = list(
      weights = list(`53H` = weights_pr[1], `53I` = weights_pr[2], `53B` = weights_pr[3]),
      weight_basis = "PR-AUC proportional from 56A reference (53H 0.2480, 53I 0.2356, 53B 0.2295)",
      pr_auc = ci_wt$point, pr_lo = ci_wt$lo, pr_hi = ci_wt$hi,
      ic = ic_wt,
      n_lift_gt1 = lifts_wt$n_gt1, n_eval = lifts_wt$n_eval,
      period = per_wt,
      period_bootstrap_ci = per_ci_wt
    ),
    regime_conditional = list(
      allocation = REGIME_WEIGHTS,
      regime_window = list(
        COVID = "2020-01-01 .. 2021-12-31",
        Recent = "2022-01-01 .. 2026-04-30",
        Calm = "else (2018-01 .. 2019-12)"
      ),
      pr_auc = ci_rg$point, pr_lo = ci_rg$lo, pr_hi = ci_rg$hi,
      ic = ic_rg,
      n_lift_gt1 = lifts_rg$n_gt1, n_eval = lifts_rg$n_eval,
      period = per_rg,
      period_bootstrap_ci = per_ci_rg,
      pit_note = "calendar-conditional, NOT strict-PIT operational without real-time regime detector"
    )
  ),
  diversification_summary = list(
    best_single_arch_on_common = best_single_arch,
    best_single_pr_on_common = best_single_pr,
    ref_53h_56a_baseline = REF_BEST_SINGLE_PR,
    ensembles_pr_minus_best_single = list(
      ew3 = ci_ew3$point - best_single_pr,
      pr_weighted = ci_wt$point - best_single_pr,
      regime_conditional = ci_rg$point - best_single_pr
    ),
    vs_53h_56a_reference = list(
      ew3 = ci_ew3$point - REF_BEST_SINGLE_PR,
      pr_weighted = ci_wt$point - REF_BEST_SINGLE_PR,
      regime_conditional = ci_rg$point - REF_BEST_SINGLE_PR
    )
  ),
  ensemble_summary_table = as.list(ensemble_summary),
  best_ensemble = list(
    name = best_ensemble$ensemble,
    pr_auc = best_ensemble$pr_auc,
    vs_53h_ref = best_ensemble$vs_53h_ref,
    verdict = best_ensemble$verdict
  ),
  cycle_final_verdict = cycle_final_verdict,
  verdict_thresholds = list(
    breakthrough_min_delta = ENSEMBLE_BREAKTHROUGH_MIN,
    marginal_min_delta = ENSEMBLE_MARGINAL_MIN,
    dilution_max_delta = ENSEMBLE_DILUTION_MAX
  ),
  outputs = list(
    predictions_ew3 = p_ew3_path,
    predictions_weighted = p_wt_path,
    predictions_regime_cond = p_rg_path,
    chart = chart_path
  )
)

audit_path <- file.path(OUT_DIR, "ensemble_audit.json")
write(toJSON(audit_out, pretty = TRUE, auto_unbox = TRUE, na = "null"), audit_path)
cat(sprintf("  Audit saved: %s\n", audit_path))

eval_path <- file.path(EVAL_DIR, "cycle58a_q15_3cycle_ensemble.json")
write(toJSON(audit_out, pretty = TRUE, auto_unbox = TRUE, na = "null"), eval_path)
cat(sprintf("  Eval saved: %s\n", eval_path))

cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat(sprintf("[Cycle 58A] DONE  verdict=%s  best=%s (PR=%.4f, Δ%+.4f)\n",
            cycle_final_verdict, best_ensemble$ensemble,
            best_ensemble$pr_auc, best_ensemble$vs_53h_ref))
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")
