## ============================================================
## Cycle 56B Step 4 — MoE Aggregate + Period-balanced + Bootstrap CI
##
## Inputs:
##   outputs/03_models/v6a_moe_q126/predictions_expert_{BULL|NORMAL|FULL}_seed{S}_y_tail_q126.parquet
##   outputs/03_models/v6a_moe_q126/predictions_moe_mean_y_tail_q126.parquet
##   outputs/03_models/v6a_moe_q126/moe_audit.json
##
## Outputs:
##   outputs/04_evaluation/moe_q126_v6a.json (Q-Lead verdict)
##   outputs/06_reports/charts/145_moe_q126.png
##   outputs/04_evaluation/cycle56b_period_balanced_bootstrap.csv
##
## Period segments (53M framework):
##   S2018-19, S2020-21, S2022-24
##
## Bootstrap: 1000 reps × block_len=21 (monthly autocorr safety)
## ============================================================

cat("============================================================\n")
cat("Cycle 56B Step 4 — MoE Aggregate + Period-balanced Bootstrap\n")
cat("============================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(ggplot2)
})

BASE_DIR <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(BASE_DIR,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data")
MOE_DIR <- file.path(WS_DIR, "outputs/03_models/v6a_moe_q126")
EVAL_DIR <- file.path(WS_DIR, "outputs/04_evaluation")
CHART_DIR <- file.path(WS_DIR, "outputs/06_reports/charts")
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

TARGET <- "y_tail_q126"
SEEDS <- c(42, 123, 456, 789, 1024)
EXPERTS <- c("BULL", "NORMAL", "FULL")
BASELINE_53H <- 0.4012

# ============================================================
# Helpers
# ============================================================
pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y)
  p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(-p)
  y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord)
  rec <- cumsum(y_ord) / sum(y_ord)
  sum(diff(rec) * (prec[-1] + prec[-length(prec)]) / 2)
}

ic_spearman <- function(p, y) {
  ok <- !is.na(p) & !is.na(y)
  p <- p[ok]; y <- y[ok]
  if (length(p) < 30) return(NA_real_)
  cor(rank(p), rank(y))
}

block_bootstrap_pr <- function(p, y, B = 1000L, block_len = 21L, seed = 1L) {
  set.seed(seed)
  n <- length(p)
  if (n < block_len * 3) return(list(pr = pr_auc(p, y), lo = NA, hi = NA))
  n_blocks <- ceiling(n / block_len)
  prs <- numeric(B)
  for (b in seq_len(B)) {
    starts <- sample.int(n - block_len + 1, n_blocks, replace = TRUE)
    idx <- unlist(lapply(starts, function(s) s:(s + block_len - 1)))
    idx <- idx[seq_len(n)]
    prs[b] <- pr_auc(p[idx], y[idx])
  }
  prs <- prs[!is.na(prs)]
  if (length(prs) < 100) return(list(pr = pr_auc(p, y), lo = NA, hi = NA))
  list(pr = pr_auc(p, y),
       lo = quantile(prs, 0.025, na.rm = TRUE),
       hi = quantile(prs, 0.975, na.rm = TRUE),
       prs = prs)
}

# ============================================================
# 1. Load per-expert per-seed predictions
# ============================================================
cat("[1] Load per-expert per-seed predictions\n")

all_preds <- list()
for (e in EXPERTS) {
  for (s in SEEDS) {
    fp <- file.path(MOE_DIR,
      sprintf("predictions_expert_%s_seed%d_%s.parquet", e, s, TARGET))
    if (file.exists(fp)) {
      d <- as.data.table(read_parquet(fp))
      d[, Date := as.Date(Date)]
      all_preds[[sprintf("%s_seed%d", e, s)]] <- d
    } else {
      cat(sprintf("  [missing] %s\n", basename(fp)))
    }
  }
}
cat(sprintf("  Loaded %d expert × seed predictions\n", length(all_preds)))

# PIT FIX 2026-05-21: load horizon return for y_valid masking
tgt_path <- file.path(WS_DIR, "outputs/02_targets/targets_long_horizon.parquet")
tgt_dt <- as.data.table(read_parquet(tgt_path))
tgt_dt[, Date := as.Date(Date)]
y_valid_dt <- tgt_dt[, .(Date, ret_q126_resolved = !is.na(ret_q126))]
n_unresolved_total <- sum(!y_valid_dt$ret_q126_resolved)
cat(sprintf("  targets_long_horizon ret_q126: %d resolved / %d unresolved (total %d)\n",
            sum(y_valid_dt$ret_q126_resolved), n_unresolved_total, nrow(y_valid_dt)))

# Load MoE mean prediction
moe_mean_path <- file.path(MOE_DIR,
  sprintf("predictions_moe_mean_%s.parquet", TARGET))
stopifnot(file.exists(moe_mean_path))
moe_mean <- as.data.table(read_parquet(moe_mean_path))
moe_mean[, Date := as.Date(Date)]
cat(sprintf("  MoE mean: %d rows (raw)\n", nrow(moe_mean)))

# PIT FIX bug #2: filter unresolved q126 labels
moe_mean <- merge(moe_mean, y_valid_dt, by = "Date", all.x = TRUE)
moe_mean[is.na(ret_q126_resolved), ret_q126_resolved := FALSE]
n_filtered <- sum(!moe_mean$ret_q126_resolved)
cat(sprintf("  PIT FIX: filtering %d unresolved q126 rows from aggregate\n", n_filtered))
moe_mean <- moe_mean[ret_q126_resolved == TRUE]
cat(sprintf("  MoE mean after y_valid filter: %d rows\n", nrow(moe_mean)))

# Load 53H baseline reference (LEAKY PIT — for documentation only)
h53_path <- file.path(WS_DIR,
  "outputs/03_models/v5e_patchtst_q126_usmacro/predictions_patchtst_v5e_y_tail_q126.parquet")
h53 <- as.data.table(read_parquet(h53_path))
h53[, Date := as.Date(Date)]
cat(sprintf("  53H reference (leaky-PIT): %d rows\n", nrow(h53)))

# Load FULL expert (the strict-PIT fair baseline)
full_preds_list <- list()
for (s in SEEDS) {
  fp <- file.path(MOE_DIR,
    sprintf("predictions_expert_FULL_seed%d_%s.parquet", s, TARGET))
  if (file.exists(fp)) {
    d <- as.data.table(read_parquet(fp))
    d[, Date := as.Date(Date)]
    full_preds_list[[as.character(s)]] <- d
  }
}
if (length(full_preds_list) > 0) {
  # FULL 5-seed mean (the strict-PIT fair baseline)
  full_by_date <- full_preds_list[[1]][, .(Date, p_full_s1 = p_expert, y, regime)]
  for (i in seq_along(full_preds_list)[-1]) {
    s <- names(full_preds_list)[i]
    d <- full_preds_list[[i]][, .(Date, p_expert)]
    setnames(d, "p_expert", paste0("p_full_s", i))
    full_by_date <- merge(full_by_date, d, by = "Date")
  }
  pcols <- grep("^p_full_s", names(full_by_date), value = TRUE)
  full_by_date[, p_full_mean := rowMeans(.SD, na.rm = TRUE), .SDcols = pcols]
  full_by_date <- merge(full_by_date, y_valid_dt, by = "Date", all.x = TRUE)
  full_by_date <- full_by_date[ret_q126_resolved == TRUE]
  full_by_date <- full_by_date[Date %in% moe_mean$Date]
  cat(sprintf("  FULL expert (strict-PIT fair baseline): %d rows × %d seeds\n",
              nrow(full_by_date), length(full_preds_list)))
} else {
  full_by_date <- NULL
  cat("  [warn] FULL expert predictions missing — fair baseline unavailable\n")
}

# ============================================================
# 2. Per-expert OOS PR-AUC × seeds (in-regime + overall)
# ============================================================
cat("\n[2] Per-expert per-seed OOS PR-AUC (in-regime + overall)\n")

per_expert_seed <- list()
for (nm in names(all_preds)) {
  d <- all_preds[[nm]]
  parts <- strsplit(nm, "_seed")[[1]]
  e <- parts[1]; s <- as.integer(parts[2])
  overall_pr <- pr_auc(d$p_expert, d$y)
  overall_ic <- ic_spearman(d$p_expert, d$y)
  in_reg <- if (e %in% c("BULL", "NORMAL")) d[regime == e] else d
  in_reg_pr <- if (nrow(in_reg) >= 30) pr_auc(in_reg$p_expert, in_reg$y) else NA_real_
  per_expert_seed[[nm]] <- data.table(
    expert = e, seed = s,
    n_total = nrow(d),
    n_in_regime = nrow(in_reg),
    overall_pr = round(overall_pr, 6),
    overall_ic = round(overall_ic, 6),
    in_regime_pr = round(in_reg_pr, 6)
  )
}
pes_dt <- rbindlist(per_expert_seed)
setorder(pes_dt, expert, seed)
cat("\n  Per-expert per-seed table:\n")
print(pes_dt)

# Per-expert mean across seeds
per_expert_summary <- pes_dt[, .(
  n_seeds = .N,
  in_regime_pr_mean = round(mean(in_regime_pr, na.rm = TRUE), 6),
  in_regime_pr_std = round(sd(in_regime_pr, na.rm = TRUE), 6),
  in_regime_pr_min = round(min(in_regime_pr, na.rm = TRUE), 6),
  in_regime_pr_max = round(max(in_regime_pr, na.rm = TRUE), 6),
  overall_pr_mean = round(mean(overall_pr, na.rm = TRUE), 6),
  overall_pr_std = round(sd(overall_pr, na.rm = TRUE), 6)
), by = expert]
cat("\n  Per-expert summary across seeds:\n")
print(per_expert_summary)

# ============================================================
# 3. MoE mean ensemble — overall + period-balanced
# ============================================================
cat("\n[3] MoE mean ensemble — overall + period-balanced bootstrap\n")

moe_mean[, period := fcase(
  Date >= as.Date("2018-01-01") & Date <= as.Date("2019-12-31"), "S2018-19",
  Date >= as.Date("2020-01-01") & Date <= as.Date("2021-12-31"), "S2020-21",
  Date >= as.Date("2022-01-01") & Date <= as.Date("2024-12-31"), "S2022-24",
  default = "S2025-26")]
# PIT FIX 2026-05-21: re-merge h53 to ensure 1:1 with filtered moe_mean
moe_mean <- merge(moe_mean,
                   h53[, .(Date, h53_p = p_patchtst)],
                   by = "Date", all.x = TRUE)

# Add FULL strict-PIT fair baseline
if (!is.null(full_by_date)) {
  moe_mean <- merge(moe_mean,
                     full_by_date[, .(Date, p_full_mean_strict = p_full_mean)],
                     by = "Date", all.x = TRUE)
} else {
  moe_mean[, p_full_mean_strict := NA_real_]
}

overall_pr_moe <- pr_auc(moe_mean$p_moe_mean, moe_mean$y)
overall_ic_moe <- ic_spearman(moe_mean$p_moe_mean, moe_mean$y)
overall_pr_53h_leaky <- pr_auc(moe_mean$h53_p, moe_mean$y)
overall_pr_full_strict <- pr_auc(moe_mean$p_full_mean_strict, moe_mean$y)

delta_vs_53h_leaky <- overall_pr_moe - overall_pr_53h_leaky
delta_vs_full_strict <- overall_pr_moe - overall_pr_full_strict

cat(sprintf("  MoE mean overall OOS PR-AUC:                       %.4f (IC=%.4f)\n",
            overall_pr_moe, overall_ic_moe))
cat(sprintf("  53H baseline overall OOS PR-AUC (leaky-PIT):       %.4f\n",
            overall_pr_53h_leaky))
cat(sprintf("  FULL expert overall OOS PR-AUC (strict-PIT fair):  %.4f\n",
            overall_pr_full_strict))
cat(sprintf("  Delta vs 53H leaky-PIT:    %+.4f\n", delta_vs_53h_leaky))
cat(sprintf("  Delta vs FULL strict-PIT:  %+.4f  ← primary fair compare\n",
            delta_vs_full_strict))

# Per-period bootstrap CI (strict-PIT baseline = FULL expert)
per_period_results <- list()
for (pp in c("S2018-19", "S2020-21", "S2022-24")) {
  sub <- moe_mean[period == pp]
  if (nrow(sub) < 60) {
    per_period_results[[pp]] <- list(
      period = pp, n = nrow(sub), n_events = sum(sub$y),
      moe_pr = NA, moe_lo = NA, moe_hi = NA,
      h53_leaky_pr = NA,
      full_strict_pr = NA, full_strict_lo = NA, full_strict_hi = NA,
      delta_pr = NA, lift = NA
    )
    next
  }
  bs_moe <- block_bootstrap_pr(sub$p_moe_mean, sub$y,
                                B = 1000L, block_len = 21L, seed = 1L)
  bs_h53 <- block_bootstrap_pr(sub$h53_p, sub$y,
                                B = 1000L, block_len = 21L, seed = 1L)
  bs_full <- if (any(!is.na(sub$p_full_mean_strict))) {
    block_bootstrap_pr(sub$p_full_mean_strict, sub$y,
                        B = 1000L, block_len = 21L, seed = 1L)
  } else list(pr = NA, lo = NA, hi = NA)
  delta_pr <- if (!is.na(bs_full$pr)) bs_moe$pr - bs_full$pr else NA_real_
  lift <- if (!is.na(bs_full$pr) && bs_full$pr > 0) bs_moe$pr / bs_full$pr else NA_real_
  per_period_results[[pp]] <- list(
    period = pp,
    n = nrow(sub),
    n_events = sum(sub$y),
    bear_rate = round(mean(sub$y), 4),
    moe_pr = round(bs_moe$pr, 6),
    moe_lo = round(bs_moe$lo, 6),
    moe_hi = round(bs_moe$hi, 6),
    h53_leaky_pr = round(bs_h53$pr, 6),
    h53_leaky_lo = round(bs_h53$lo, 6),
    h53_leaky_hi = round(bs_h53$hi, 6),
    full_strict_pr = round(bs_full$pr, 6),
    full_strict_lo = round(bs_full$lo, 6),
    full_strict_hi = round(bs_full$hi, 6),
    delta_pr = round(delta_pr, 6),
    lift = round(lift, 4)
  )
}
per_period_dt <- rbindlist(lapply(per_period_results, as.data.table))
cat("\n  Per-period balanced bootstrap (B=1000, block_len=21):\n")
print(per_period_dt)

fwrite(per_period_dt,
       file.path(EVAL_DIR, "cycle56b_period_balanced_bootstrap.csv"))

# Period segment lift>1 count
seg_lift_gt1 <- sum(per_period_dt$lift > 1.0, na.rm = TRUE)
seg_lift_total <- sum(!is.na(per_period_dt$lift))
cat(sprintf("\n  Segment lift>1 count: %d / %d\n", seg_lift_gt1, seg_lift_total))

# ============================================================
# 4. Per-regime decomposition of MoE
# ============================================================
cat("\n[4] Per-regime MoE PR-AUC (sanity)\n")
regime_decomp <- moe_mean[, .(
  n = .N,
  n_events = sum(y, na.rm = TRUE),
  bear_rate = round(mean(y), 4),
  moe_pr = round(pr_auc(p_moe_mean, y), 6),
  full_strict_pr = round(pr_auc(p_full_mean_strict, y), 6),
  h53_leaky_pr = round(pr_auc(h53_p, y), 6),
  delta_vs_full = round(pr_auc(p_moe_mean, y) - pr_auc(p_full_mean_strict, y), 6)
), by = regime]
setorder(regime_decomp, regime)
print(regime_decomp)

# ============================================================
# 5. Verdict (primary = strict-PIT fair compare)
# ============================================================
cat("\n[5] Verdict (strict-PIT fair compare: MoE vs FULL_strict)\n")

verdict <- if (!is.na(delta_vs_full_strict)) {
  if (delta_vs_full_strict > 0.02) "MoE_BREAKTHROUGH"
  else if (delta_vs_full_strict > 0.0) "MoE_MARGINAL"
  else "MoE_FAIL"
} else "INDETERMINATE_NO_BASELINE"

cat(sprintf("  Strict-PIT compare: MoE %.4f vs FULL_strict %.4f → ΔPR = %+.4f → %s\n",
            overall_pr_moe, overall_pr_full_strict, delta_vs_full_strict, verdict))
cat(sprintf("  Leaky-PIT compare: MoE %.4f vs 53H_seed42 %.4f → ΔPR = %+.4f (documentation only)\n",
            overall_pr_moe, BASELINE_53H, overall_pr_moe - BASELINE_53H))
cat(sprintf("  Period-balanced segments lift>1 (vs FULL_strict): %d/%d\n",
            seg_lift_gt1, seg_lift_total))

# ============================================================
# 6. Chart
# ============================================================
cat("\n[6] Build chart\n")

plot_df <- copy(moe_mean)
plot_df[, NAV_dummy := 1]  # unused; we'll plot rolling PR

# Per-period bar chart (MoE vs FULL_strict, with CI)
per_period_dt_plot <- per_period_dt[!is.na(moe_pr)]
plot_long <- rbindlist(list(
  per_period_dt_plot[, .(period, model = "MoE", pr = moe_pr, lo = moe_lo, hi = moe_hi)],
  per_period_dt_plot[, .(period, model = "FULL_strict_PIT", pr = full_strict_pr,
                          lo = full_strict_lo, hi = full_strict_hi)]
))

p1 <- ggplot(plot_long, aes(x = period, y = pr, fill = model)) +
  geom_bar(stat = "identity", position = position_dodge(width = 0.8), width = 0.7) +
  geom_errorbar(aes(ymin = lo, ymax = hi),
                 position = position_dodge(width = 0.8), width = 0.25) +
  scale_fill_manual(values = c("MoE" = "steelblue", "FULL_strict_PIT" = "gray60")) +
  geom_hline(yintercept = BASELINE_53H, linetype = "dashed",
              color = "red", linewidth = 0.5) +
  labs(title = "Cycle 56B — MoE per Regime vs FULL strict-PIT baseline (per-period PR-AUC)",
       subtitle = sprintf("MoE: %.4f | FULL_strict: %.4f | Δ=%+.4f → %s  (red dashed = 53H leaky-PIT %.4f)",
                           overall_pr_moe, overall_pr_full_strict,
                           delta_vs_full_strict, verdict, BASELINE_53H),
       y = "OOS PR-AUC (block bootstrap 95% CI)", x = "Period segment") +
  theme_minimal() +
  theme(plot.title = element_text(size = 12, face = "bold"),
        plot.subtitle = element_text(size = 9))

ggsave(file.path(CHART_DIR, "145_moe_q126.png"), p1,
       width = 10, height = 6, dpi = 120)
cat(sprintf("  saved chart: %s\n", file.path(CHART_DIR, "145_moe_q126.png")))

# ============================================================
# 7. Save final aggregate JSON
# ============================================================
agg_result <- list(
  cycle = "56B_moe_per_regime_aggregate",
  target = TARGET,
  pit_fixes_applied = list(
    bug_1 = "Purged k-fold CV (train_idx t + H_business < valid_start)",
    bug_2 = "y_valid_mask = ret_q126 NOT NA (filter unresolved in train/valid/OOS)"
  ),
  baseline_53H_seed42_leaky_pit = list(
    value = BASELINE_53H,
    note = "53H baseline was computed under leaky-PIT (no purge + unresolved-y treated as 0). Listed for documentation. Strict-PIT fair compare uses FULL expert 5-seed mean computed within this cycle."
  ),
  per_expert_per_seed = lapply(seq_len(nrow(pes_dt)), function(i) as.list(pes_dt[i])),
  per_expert_summary = lapply(seq_len(nrow(per_expert_summary)),
                                function(i) as.list(per_expert_summary[i])),
  moe_overall = list(
    pr_auc = round(overall_pr_moe, 6),
    ic = round(overall_ic_moe, 6),
    n_obs = nrow(moe_mean),
    n_events = sum(moe_mean$y)
  ),
  full_strict_pit_overall = list(
    pr_auc = round(overall_pr_full_strict, 6),
    n_obs = nrow(moe_mean[!is.na(p_full_mean_strict)]),
    note = "FULL expert 5-seed mean — strict-PIT fair baseline (purged + y_valid)"
  ),
  h53_leaky_overall = list(
    pr_auc = round(overall_pr_53h_leaky, 6),
    n_obs = nrow(moe_mean[!is.na(h53_p)]),
    note = "53H_aligned to MoE OOS dates (leaky-PIT, for documentation only)"
  ),
  delta_vs_full_strict = round(delta_vs_full_strict, 6),
  delta_vs_53h_leaky = round(delta_vs_53h_leaky, 6),
  per_period_bootstrap = lapply(per_period_results, function(x) x),
  segment_lift_gt1 = seg_lift_gt1,
  segment_lift_total = seg_lift_total,
  per_regime_decomp = lapply(seq_len(nrow(regime_decomp)),
                              function(i) as.list(regime_decomp[i])),
  verdict = verdict,
  verdict_criteria = list(
    BREAKTHROUGH = "delta_vs_full_strict > +0.02",
    MARGINAL = "0 < delta_vs_full_strict ≤ +0.02",
    FAIL = "delta_vs_full_strict ≤ 0"
  ),
  outputs = list(
    chart = "outputs/06_reports/charts/145_moe_q126.png",
    per_period_csv = "outputs/04_evaluation/cycle56b_period_balanced_bootstrap.csv"
  )
)

write_json(agg_result, file.path(EVAL_DIR, "moe_q126_v6a.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("\n[done] outputs/04_evaluation/moe_q126_v6a.json\n"))
cat(sprintf("       outputs/06_reports/charts/145_moe_q126.png\n"))
cat(sprintf("       outputs/04_evaluation/cycle56b_period_balanced_bootstrap.csv\n"))
