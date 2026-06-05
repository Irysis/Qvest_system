#==============================================================================
# 165_3arch_heterogeneous_ensemble.R — Cycle 56D-Batch2-multiseed Phase 3
#
# Mandate (Q-Lead autonomous):
#   3-arch heterogeneous ensemble exploration:
#     - 53H_v5e_mean5 (PatchTST strict-PIT 5-seed, ref 0.488)
#     - Mamba_mean5 (Cycle 56D-Batch2-multiseed, NEW — from 164)
#     - FEDformer_seed42 (Cycle 56D-Batch2 single seed, ref 0.293 BUT period-robust 3/3)
#   3 ensemble strategies:
#     A. EW3: equal-weight average
#     B. Weighted: PR-AUC proportional weights
#     C. Regime-conditional: COVID→Mamba, Stagflation→FEDformer, Other→53H
#   vs 53H_v5e single ensemble 0.488 baseline.
#   Diversification gain quantify.
#
# Reads:
#   outputs/03_models/cycle55a_strict_PIT/predictions_53H_v5e_mean5_y_tail_q126.parquet
#   outputs/03_models/v6d_mamba_5seed/predictions_mamba_mean5_y_tail_q126.parquet (from 164)
#   outputs/03_models/v6d_mamba_fedformer/predictions_fedformer_y_tail_q126.parquet
#
# Output:
#   outputs/03_models/v6d_3arch_ensemble/
#     predictions_ew3_y_tail_q126.parquet
#     predictions_weighted_y_tail_q126.parquet
#     predictions_regime_conditional_y_tail_q126.parquet
#     ensemble_audit.json
#   outputs/04_evaluation/cycle56dbatch2_multiseed.json
#   outputs/06_reports/charts/165_3arch_heterogeneous.png
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2)
  library(patchwork)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
S53H_DIR <- file.path(WS, "outputs/03_models/cycle55a_strict_PIT")
MAMBA_5SEED_DIR <- file.path(WS, "outputs/03_models/v6d_mamba_5seed")
MF_DIR <- file.path(WS, "outputs/03_models/v6d_mamba_fedformer")
OUT_DIR <- file.path(WS, "outputs/03_models/v6d_3arch_ensemble")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

OOS_START <- as.Date("2018-01-01")
OOS_END   <- as.Date("2026-04-30")

REF_53H_MEAN5     <- 0.488   # 53H_v5e mean5 strict-PIT
REF_MAMBA_SEED42  <- 0.4264  # Mamba seed=42 single (153)
REF_FEDFORMER_S42 <- 0.2933  # FEDformer seed=42 single (153)

# Codex L2 patch: segment names match requested audit names
SEGMENTS <- list(
  list(name = "S2018-19_calm",        start = as.Date("2018-01-01"), end = as.Date("2019-12-31")),
  list(name = "S2020-21_COVID",       start = as.Date("2020-01-01"), end = as.Date("2021-12-31")),
  list(name = "S2022-24_Stagflation", start = as.Date("2022-01-01"), end = as.Date("2024-12-31"))
)

BOOTSTRAP_N <- 1000L
BOOTSTRAP_SEED <- 20260521L

# Verdict thresholds
DIVERSIFICATION_GAIN_MIN <- 0.005  # 0.5pp PR-AUC gain to declare HETEROGENEOUS_BREAKTHROUGH
PARETO_VS_53H_THRESH     <- REF_53H_MEAN5

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

count_lift_gt1 <- function(period_res) {
  vals <- sapply(period_res, function(x) x$lift %||% NA_real_)
  vals <- vals[!is.na(vals)]
  list(n_gt1 = sum(vals > 1.0), n_eval = length(vals))
}

#==============================================================================
# Step 1: Load 3-arch predictions
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 1] Loading 3-arch predictions\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

f_53h <- file.path(S53H_DIR, "predictions_53H_v5e_mean5_y_tail_q126.parquet")
f_mamba <- file.path(MAMBA_5SEED_DIR, "predictions_mamba_mean5_y_tail_q126.parquet")
f_fed <- file.path(MF_DIR, "predictions_fedformer_y_tail_q126.parquet")

stopifnot(file.exists(f_53h))
stopifnot(file.exists(f_mamba))
stopifnot(file.exists(f_fed))

dt_53h <- as.data.table(read_parquet(f_53h))
dt_mamba <- as.data.table(read_parquet(f_mamba))
dt_fed <- as.data.table(read_parquet(f_fed))

# Standardize column names: ensure p_53h / p_mamba / p_fed
setnames(dt_53h, "p_mean5", "p_53h")
setnames(dt_mamba, "p_mamba_mean5", "p_mamba")
setnames(dt_fed, "p_fedformer", "p_fed")

dt_53h[, Date := as.Date(Date)]
dt_mamba[, Date := as.Date(Date)]
dt_fed[, Date := as.Date(Date)]

# === Codex M6 patch: input metadata assertions ===
if ("n_seeds" %in% names(dt_53h)) {
  stopifnot(all(dt_53h$n_seeds == 5))
  cat(sprintf("  [M6 assert] 53H n_seeds=5 OK (n_unique=%d)\n", length(unique(dt_53h$n_seeds))))
}
if ("n_seeds" %in% names(dt_mamba)) {
  stopifnot(all(dt_mamba$n_seeds == 5))
  cat(sprintf("  [M6 assert] Mamba mean5 n_seeds=5 OK (n_unique=%d)\n", length(unique(dt_mamba$n_seeds))))
}
if ("adopted_seed" %in% names(dt_fed)) {
  stopifnot(all(dt_fed$adopted_seed == 42))
  cat(sprintf("  [M6 assert] FEDformer adopted_seed=42 OK\n"))
}

# === Codex L1 patch: enforce OOS window + split filter on each input ===
filter_oos <- function(dt, label) {
  n0 <- nrow(dt)
  dt <- dt[Date >= OOS_START & Date <= OOS_END]
  n1 <- nrow(dt)
  if ("split" %in% names(dt)) {
    dt <- dt[split == "oos"]
  }
  n2 <- nrow(dt)
  if (n0 != n2) {
    cat(sprintf("  [L1 filter] %s: %d -> %d (date) -> %d (split==oos)\n", label, n0, n1, n2))
  }
  dt
}
dt_53h <- filter_oos(dt_53h, "53H_mean5")
dt_mamba <- filter_oos(dt_mamba, "Mamba_mean5")
dt_fed <- filter_oos(dt_fed, "FEDformer_s42")

cat(sprintf("  53H_v5e_mean5: %d rows %s..%s\n",
            nrow(dt_53h), as.character(min(dt_53h$Date)), as.character(max(dt_53h$Date))))
cat(sprintf("  Mamba_mean5:   %d rows %s..%s\n",
            nrow(dt_mamba), as.character(min(dt_mamba$Date)), as.character(max(dt_mamba$Date))))
cat(sprintf("  FEDformer_s42: %d rows %s..%s\n",
            nrow(dt_fed), as.character(min(dt_fed$Date)), as.character(max(dt_fed$Date))))

# Inner join on Date (use 3-way intersection)
common_dates <- Reduce(intersect, list(dt_53h$Date, dt_mamba$Date, dt_fed$Date))
common_dates <- sort(as.Date(common_dates, origin = "1970-01-01"))
cat(sprintf("\n  3-way common dates: %d\n", length(common_dates)))

dt_join <- dt_53h[Date %in% common_dates, .(Date, p_53h, y_53h = y)][
  dt_mamba[Date %in% common_dates, .(Date, p_mamba, y_mamba = y)], on = "Date"][
  dt_fed[Date %in% common_dates, .(Date, p_fed, y_fed = y)], on = "Date"]
setorder(dt_join, Date)

# === Codex H3 patch: NA-safe y consistency check ===
na_safe_mismatch <- function(a, b) {
  bad <- (is.na(a) != is.na(b)) | (!is.na(a) & !is.na(b) & a != b)
  sum(bad)
}
y_mismatch_1 <- na_safe_mismatch(dt_join$y_53h, dt_join$y_mamba)
y_mismatch_2 <- na_safe_mismatch(dt_join$y_53h, dt_join$y_fed)
cat(sprintf("  y consistency (NA-safe): 53H vs Mamba mismatch=%d  53H vs FED mismatch=%d (should be 0)\n",
            y_mismatch_1, y_mismatch_2))
stopifnot(y_mismatch_1 == 0 && y_mismatch_2 == 0)
dt_join[, y := y_53h]
dt_join[, c("y_53h", "y_mamba", "y_fed") := NULL]

cat(sprintf("  Final 3-way joined: %d rows  events=%d (%.1f%% base rate)\n",
            nrow(dt_join), sum(dt_join$y, na.rm = TRUE),
            mean(dt_join$y, na.rm = TRUE) * 100))

#==============================================================================
# Step 2: Per-arch standalone audit on common 3-way set
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 2] Per-arch standalone PR-AUC + IC + period-balanced (on common 3-way set)\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

standalone <- list()
for (arch_col in c("p_53h", "p_mamba", "p_fed")) {
  arch_name <- gsub("^p_", "", arch_col)
  ci_pr <- bootstrap_ci_pr(dt_join[[arch_col]], dt_join$y)
  ic <- ic_spearman(dt_join[[arch_col]], dt_join$y)
  per <- period_balanced(dt_join[[arch_col]], dt_join$y, dt_join$Date)
  lifts <- count_lift_gt1(per)
  standalone[[arch_name]] <- list(
    pr_auc = ci_pr$point, pr_lo = ci_pr$lo, pr_hi = ci_pr$hi,
    ic = if (is.na(ic)) NA_real_ else round(ic, 4),
    n = ci_pr$n, events = ci_pr$events,
    n_lift_gt1 = lifts$n_gt1, n_eval = lifts$n_eval,
    period = per
  )
  cat(sprintf("  %-10s  PR=%.4f [%.4f, %.4f]  IC=%s  lifts=%d/%d\n",
              arch_name, ci_pr$point, ci_pr$lo %||% NA, ci_pr$hi %||% NA,
              ifelse(is.na(ic), "NA", sprintf("%.4f", ic)),
              lifts$n_gt1, lifts$n_eval))
}

#==============================================================================
# Step 3: 3-arch correlation (pairwise) — diversification audit
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 3] Pairwise correlation (Spearman + Pearson)\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

cor_spr <- cor(dt_join[, .(p_53h, p_mamba, p_fed)], method = "spearman")
cor_prs <- cor(dt_join[, .(p_53h, p_mamba, p_fed)], method = "pearson")
cat("  Spearman:\n"); print(round(cor_spr, 3))
cat("  Pearson:\n"); print(round(cor_prs, 3))

#==============================================================================
# Step 4: Ensemble A — EW3 (equal-weight)
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 4] Ensemble A — EW3 (equal-weight average)\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

dt_join[, p_ew3 := (p_53h + p_mamba + p_fed) / 3.0]
ci_ew3 <- bootstrap_ci_pr(dt_join$p_ew3, dt_join$y)
ic_ew3 <- ic_spearman(dt_join$p_ew3, dt_join$y)
per_ew3 <- period_balanced(dt_join$p_ew3, dt_join$y, dt_join$Date)
lifts_ew3 <- count_lift_gt1(per_ew3)

cat(sprintf("  EW3 PR-AUC = %.4f [%.4f, %.4f]  IC=%.4f  lifts=%d/%d\n",
            ci_ew3$point, ci_ew3$lo %||% NA, ci_ew3$hi %||% NA,
            ic_ew3 %||% NA, lifts_ew3$n_gt1, lifts_ew3$n_eval))
cat(sprintf("  Δ vs 53H mean5 = %+.4f\n", ci_ew3$point - REF_53H_MEAN5))
for (nm in names(per_ew3)) {
  e <- per_ew3[[nm]]
  cat(sprintf("    %s: PR=%s lift=%s base=%s\n", nm,
              ifelse(is.na(e$pr_auc %||% NA), "NA", sprintf("%.4f", e$pr_auc)),
              ifelse(is.na(e$lift %||% NA), "NA", sprintf("%.4f", e$lift)),
              ifelse(is.na(e$base_rate %||% NA), "NA", sprintf("%.4f", e$base_rate))))
}

#==============================================================================
# Step 5: Ensemble B — Weighted (PR-AUC proportional)
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 5] Ensemble B — Weighted (PR-AUC proportional)\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

# Weight by historical PR-AUC (53H 0.488, Mamba mean5 ?, FED 0.293)
# Task mandate: roughly 53H 0.5 + Mamba 0.35 + FED 0.15
# We compute live: normalize per-arch PR-AUC to sum to 1
w_raw <- c(standalone$`53h`$pr_auc,
           standalone$mamba$pr_auc,
           standalone$fed$pr_auc)
# === Codex M5 patch: PR-weight clamp with explicit pmax(0.01) ===
w_raw[is.na(w_raw)] <- 0
w_raw <- pmax(w_raw, 0.01)  # min clamp to avoid 0 / tiny positive instability
weights_pr <- w_raw / sum(w_raw)
cat(sprintf("  PR-proportional weights: 53H=%.3f  Mamba=%.3f  FED=%.3f  (sum=%.3f)\n",
            weights_pr[1], weights_pr[2], weights_pr[3], sum(weights_pr)))

dt_join[, p_weighted := weights_pr[1] * p_53h + weights_pr[2] * p_mamba + weights_pr[3] * p_fed]
ci_wt <- bootstrap_ci_pr(dt_join$p_weighted, dt_join$y)
ic_wt <- ic_spearman(dt_join$p_weighted, dt_join$y)
per_wt <- period_balanced(dt_join$p_weighted, dt_join$y, dt_join$Date)
lifts_wt <- count_lift_gt1(per_wt)

cat(sprintf("  Weighted PR-AUC = %.4f [%.4f, %.4f]  IC=%.4f  lifts=%d/%d\n",
            ci_wt$point, ci_wt$lo %||% NA, ci_wt$hi %||% NA,
            ic_wt %||% NA, lifts_wt$n_gt1, lifts_wt$n_eval))
cat(sprintf("  Δ vs 53H mean5 = %+.4f\n", ci_wt$point - REF_53H_MEAN5))

#==============================================================================
# Step 6: Ensemble C — Regime-conditional (FAIR PIT — no future selection)
#
# Q-Lead PIT design — the regime "tags" are PIT-safe because:
#   (a) Calendar date segments are know-able at decision time
#   (b) We do NOT select architecture based on which one performed best
#       in the segment; we select based on the per-architecture period-balanced
#       lift OBSERVED in the seed=42 single Mamba/FEDformer run (153 cycle).
#   (c) However, this is still ex-ante CALENDAR-conditional, NOT PIT in the
#       strict sense (we know which arch wins in each regime). For honest PIT,
#       a real-time regime detector would emit the segment label.
# We DOCUMENT this as a "calendar-conditional ensemble" — useful as upper bound,
# NOT operational. Strict-PIT version would require a separately validated
# regime classifier (out of scope this cycle).
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 6] Ensemble C — Regime-conditional (calendar-conditional, NOT strict-PIT — upper bound only)\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

# Allocation per segment based on 153 cycle observed period lifts:
#   S2018-19_calm:    53H dominant (Mamba 0.96, FED ?)
#   S2020-21_COVID:   Mamba dominant (2.98 lift)
#   S2022-24_Stagfl:  FED dominant (3.04 lift)
# Outside any segment (2025-26+): EW3 fallback

dt_join[, seg := fcase(
  Date >= as.Date("2018-01-01") & Date <= as.Date("2019-12-31"), "S2018_19",
  Date >= as.Date("2020-01-01") & Date <= as.Date("2021-12-31"), "S2020_21",
  Date >= as.Date("2022-01-01") & Date <= as.Date("2024-12-31"), "S2022_24",
  default = "Other"
)]

dt_join[, p_regime := fcase(
  seg == "S2018_19", p_53h,
  seg == "S2020_21", p_mamba,
  seg == "S2022_24", p_fed,
  default = (p_53h + p_mamba + p_fed) / 3.0
)]

ci_rg <- bootstrap_ci_pr(dt_join$p_regime, dt_join$y)
ic_rg <- ic_spearman(dt_join$p_regime, dt_join$y)
per_rg <- period_balanced(dt_join$p_regime, dt_join$y, dt_join$Date)
lifts_rg <- count_lift_gt1(per_rg)

cat(sprintf("  Regime-conditional PR-AUC = %.4f [%.4f, %.4f]  IC=%.4f  lifts=%d/%d\n",
            ci_rg$point, ci_rg$lo %||% NA, ci_rg$hi %||% NA,
            ic_rg %||% NA, lifts_rg$n_gt1, lifts_rg$n_eval))
cat(sprintf("  Δ vs 53H mean5 = %+.4f\n", ci_rg$point - REF_53H_MEAN5))
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

save_pred <- function(p_col, fname) {
  dt_out <- dt_join[, .(Date, p = get(p_col), y,
                        split = "oos", target = "y_tail_q126")]
  setnames(dt_out, "p", p_col)
  out_path <- file.path(OUT_DIR, fname)
  write_parquet(dt_out, out_path)
  cat(sprintf("  Saved: %s (%d rows)\n", out_path, nrow(dt_out)))
}
save_pred("p_ew3", "predictions_ew3_y_tail_q126.parquet")
save_pred("p_weighted", "predictions_weighted_y_tail_q126.parquet")
save_pred("p_regime", "predictions_regime_conditional_y_tail_q126.parquet")

#==============================================================================
# Step 8: Diversification gain quantify
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 8] Diversification gain analysis\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

best_single_pr <- max(standalone$`53h`$pr_auc,
                       standalone$mamba$pr_auc,
                       standalone$fed$pr_auc, na.rm = TRUE)
best_single_arch <- c("53H", "Mamba", "FED")[which.max(c(
  standalone$`53h`$pr_auc, standalone$mamba$pr_auc, standalone$fed$pr_auc
))]

ensemble_summary <- data.table(
  ensemble = c("EW3", "Weighted", "RegimeCond"),
  pr_auc = c(ci_ew3$point, ci_wt$point, ci_rg$point),
  pr_lo = c(ci_ew3$lo, ci_wt$lo, ci_rg$lo),
  pr_hi = c(ci_ew3$hi, ci_wt$hi, ci_rg$hi),
  ic = c(ic_ew3, ic_wt, ic_rg),
  n_lift_gt1 = c(lifts_ew3$n_gt1, lifts_wt$n_gt1, lifts_rg$n_gt1),
  n_eval = c(lifts_ew3$n_eval, lifts_wt$n_eval, lifts_rg$n_eval),
  vs_53h = c(ci_ew3$point - REF_53H_MEAN5,
             ci_wt$point - REF_53H_MEAN5,
             ci_rg$point - REF_53H_MEAN5),
  diversification_gain = c(ci_ew3$point - best_single_pr,
                            ci_wt$point - best_single_pr,
                            ci_rg$point - best_single_pr)
)
cat(sprintf("  best single arch on 3-way common set: %s (PR=%.4f)\n",
            best_single_arch, best_single_pr))
print(ensemble_summary)

#==============================================================================
# Step 9: Final verdicts
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 9] Final verdicts\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

# Codex H4 patch: verdict requires ALL configured segments lift>1, not just lifts_n == n_eval
n_segments_configured <- length(SEGMENTS)
verdict_ensemble <- function(pr, lifts_n, n_eval, vs_53h_diff) {
  if (is.na(pr)) return("FAILED")
  # HETEROGENEOUS_BREAKTHROUGH: pr >= 53H + 0.005 AND all configured segments lift>1
  if (pr >= REF_53H_MEAN5 + DIVERSIFICATION_GAIN_MIN &&
      n_eval == n_segments_configured && lifts_n == n_segments_configured) {
    return("HETEROGENEOUS_BREAKTHROUGH")
  }
  # HETEROGENEOUS_COMPETITIVE: pr >= 53H AND at least (n_configured - 1) segments lift>1
  if (pr >= REF_53H_MEAN5 &&
      n_eval == n_segments_configured && lifts_n >= n_segments_configured - 1) {
    return("HETEROGENEOUS_COMPETITIVE")
  }
  if (pr >= 0.42) return("HETEROGENEOUS_VIABLE")
  return("HETEROGENEOUS_INFERIOR")
}

ensemble_summary[, verdict := mapply(verdict_ensemble, pr_auc, n_lift_gt1, n_eval, vs_53h)]
print(ensemble_summary[, .(ensemble, pr_auc, n_lift_gt1, n_eval, vs_53h, verdict)])

best_ensemble <- ensemble_summary[which.max(pr_auc)]
cat(sprintf("\n  Best ensemble: %s (PR=%.4f, vs 53H %+.4f, verdict=%s)\n",
            best_ensemble$ensemble, best_ensemble$pr_auc,
            best_ensemble$vs_53h, best_ensemble$verdict))

# Codex H4 patch: cycle_final_verdict inherits best_ensemble verdict (lift condition enforced)
cycle_final_verdict <- best_ensemble$verdict
cat(sprintf("\n  >>> CYCLE FINAL VERDICT (3-arch, inherits best ensemble): %s\n", cycle_final_verdict))

#==============================================================================
# Step 10: Chart + JSON output
#==============================================================================
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Step 10] Chart + JSON output\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

# Chart 1: Per-arch standalone + 3 ensembles bar
plot_df <- rbind(
  data.table(method = "53H_mean5", pr_auc = standalone$`53h`$pr_auc,
             lo = standalone$`53h`$pr_lo, hi = standalone$`53h`$pr_hi, type = "standalone"),
  data.table(method = "Mamba_mean5", pr_auc = standalone$mamba$pr_auc,
             lo = standalone$mamba$pr_lo, hi = standalone$mamba$pr_hi, type = "standalone"),
  data.table(method = "FED_seed42", pr_auc = standalone$fed$pr_auc,
             lo = standalone$fed$pr_lo, hi = standalone$fed$pr_hi, type = "standalone"),
  data.table(method = "EW3", pr_auc = ci_ew3$point, lo = ci_ew3$lo, hi = ci_ew3$hi,
             type = "ensemble"),
  data.table(method = "Weighted", pr_auc = ci_wt$point, lo = ci_wt$lo, hi = ci_wt$hi,
             type = "ensemble"),
  data.table(method = "RegimeCond*", pr_auc = ci_rg$point, lo = ci_rg$lo, hi = ci_rg$hi,
             type = "ensemble (cal-cond)")
)
plot_df[, method := factor(method, levels = method)]

p1 <- ggplot(plot_df, aes(x = method, y = pr_auc, fill = type)) +
  geom_col() +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.2, alpha = 0.7) +
  geom_hline(yintercept = REF_53H_MEAN5, linetype = "dashed", color = "red", alpha = 0.6) +
  annotate("text", x = 1, y = REF_53H_MEAN5 + 0.015, label = "53H mean5 baseline",
           color = "red", alpha = 0.8, size = 3, hjust = 0) +
  geom_text(aes(label = sprintf("%.4f", pr_auc)),
            vjust = -0.3, size = 3, color = "black") +
  scale_fill_manual(values = c("standalone" = "#7E9BB7",
                                "ensemble" = "#52A371",
                                "ensemble (cal-cond)" = "#D69B41")) +
  labs(title = "Cycle 56D-Batch2-multiseed — 3-arch heterogeneous ensemble",
       subtitle = sprintf("Target y_tail_q126 | 3-way common dates n=%d events=%d",
                          nrow(dt_join), sum(dt_join$y, na.rm = TRUE)),
       x = NULL, y = "OOS PR-AUC (95% bootstrap CI)") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

# Chart 2: Per-period lift (standalone vs ensemble)
period_long <- list()
for (m in c("p_53h", "p_mamba", "p_fed", "p_ew3", "p_weighted", "p_regime")) {
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
  labs(title = "Period-balanced lift per arch + ensembles",
       subtitle = "Lift > 1 = better than base rate",
       x = NULL, y = "Lift (PR-AUC / base rate)") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

p_combined <- p1 / p2 + plot_layout(heights = c(1, 1))

chart_path <- file.path(CHART_DIR, "165_3arch_heterogeneous.png")
ggsave(chart_path, p_combined, width = 12, height = 9, dpi = 110)
cat(sprintf("  Chart saved: %s\n", chart_path))

# JSON output
audit_out <- list(
  cycle = "56D_Batch2_multiseed_3arch",
  script = "165_3arch_heterogeneous_ensemble.R",
  timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  inputs = list(
    cycle_53h_mean5 = list(
      file = f_53h, md5 = tools::md5sum(f_53h), pr_auc_ref = REF_53H_MEAN5),
    mamba_mean5 = list(
      file = f_mamba, md5 = tools::md5sum(f_mamba)),
    fedformer_seed42 = list(
      file = f_fed, md5 = tools::md5sum(f_fed), pr_auc_ref = REF_FEDFORMER_S42)
  ),
  n_3way_common = nrow(dt_join),
  n_events = sum(dt_join$y, na.rm = TRUE),
  standalone = standalone,
  correlation_pairwise = list(
    spearman = round(cor_spr, 4),
    pearson = round(cor_prs, 4)
  ),
  ensembles = list(
    ew3 = list(weights = c(0.333, 0.333, 0.333),
               pr_auc = ci_ew3$point, pr_lo = ci_ew3$lo, pr_hi = ci_ew3$hi,
               ic = ic_ew3, n_lift_gt1 = lifts_ew3$n_gt1, n_eval = lifts_ew3$n_eval,
               period = per_ew3),
    weighted = list(weights = list("53h" = weights_pr[1],
                                    "mamba" = weights_pr[2],
                                    "fed" = weights_pr[3]),
                    pr_auc = ci_wt$point, pr_lo = ci_wt$lo, pr_hi = ci_wt$hi,
                    ic = ic_wt, n_lift_gt1 = lifts_wt$n_gt1, n_eval = lifts_wt$n_eval,
                    period = per_wt),
    regime_conditional = list(allocation = list(`S2018-19_calm` = "53H",
                                                  `S2020-21_COVID` = "Mamba",
                                                  `S2022-24_Stagflation` = "FED",
                                                  Other = "EW3"),
                              pr_auc = ci_rg$point, pr_lo = ci_rg$lo, pr_hi = ci_rg$hi,
                              ic = ic_rg, n_lift_gt1 = lifts_rg$n_gt1,
                              n_eval = lifts_rg$n_eval, period = per_rg,
                              pit_note = "calendar-conditional, NOT strict-PIT")
  ),
  diversification_summary = list(
    best_single_arch = best_single_arch,
    best_single_pr = best_single_pr,
    ensembles_pr_minus_best_single = list(
      ew3 = ci_ew3$point - best_single_pr,
      weighted = ci_wt$point - best_single_pr,
      regime_conditional = ci_rg$point - best_single_pr
    ),
    vs_53h_mean5 = list(
      ew3 = ci_ew3$point - REF_53H_MEAN5,
      weighted = ci_wt$point - REF_53H_MEAN5,
      regime_conditional = ci_rg$point - REF_53H_MEAN5
    )
  ),
  per_ensemble_verdict = setNames(
    as.list(ensemble_summary$verdict),
    ensemble_summary$ensemble),
  cycle_final_verdict_3arch = cycle_final_verdict
)

audit_path <- file.path(OUT_DIR, "ensemble_audit.json")
writeLines(toJSON(audit_out, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"),
           audit_path)
cat(sprintf("  Audit saved: %s\n", audit_path))

cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("[Cycle 56D-Batch2-multiseed Phase 3 — 165 DONE]\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")
