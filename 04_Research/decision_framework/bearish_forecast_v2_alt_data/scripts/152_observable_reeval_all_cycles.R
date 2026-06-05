#==============================================================================
# 152_observable_reeval_all_cycles.R — Cycle 54D Phase 3+4
#
# Goal:
#   Re-evaluate ALL q126 prediction files against observable-only labels
#   (NaN-propagated targets, no phantom-0 contamination).
#
# Method:
#   For each prediction file p_<model>:
#     1. Load original predictions (Date, p_*, y, ...)
#     2. Merge with targets_long_horizon_observable.parquet (y_obs)
#     3. Compute orig PR-AUC + IC vs y (buggy phantom-0 labels)
#     4. Compute observable PR-AUC + IC vs y_obs (excludes NA)
#     5. Report delta + n_phantom_0_excluded
#
# Affected cycles (from brief):
#   - 53B v5b PatchTST q126           (orig 0.3456)
#   - 53E v5d_sweep 11 variants
#   - 53H v5e q126 + US macro         (orig 0.4012)
#   - 53I v5f q126 + ECOS             (orig 0.1998)
#   - 54A v5d_FIXED 11 variants (4 available)
#   - v5e q126 multiseed (4 seeds)
#   - v6a MoE q126 (multi-expert)
#   - v6b megamulti q126 (3 models)
#   - v6c 2stage q126 (4 stage predictions)
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS  <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
MOD <- file.path(WS, "outputs/03_models")
TGT <- file.path(WS, "outputs/02_targets")
EVAL <- file.path(WS, "outputs/04_evaluation")

cat("\n========== Cycle 54D Phase 3+4: Observable-only re-evaluation ==========\n")

# ── Helpers ─────────────────────────────────────────────────────
pr_auc <- function(pred, actual) {
  ok <- !is.na(pred) & !is.na(actual)
  pred <- pred[ok]; actual <- actual[ok]
  n_clean <- length(pred); n_pos <- sum(actual == 1)
  if (n_clean < 30 || n_pos < 5) {
    return(list(pr_auc = NA_real_, n = n_clean, events = n_pos,
                base_rate = if (n_clean > 0) n_pos / n_clean else NA_real_))
  }
  ord <- order(pred, decreasing = TRUE)
  labels_ord <- actual[ord]
  prec <- cumsum(labels_ord) / seq_along(labels_ord)
  rec  <- cumsum(labels_ord) / sum(labels_ord)
  k <- length(prec)
  pr_v <- sum(diff(rec) * (prec[-1] + prec[-k]) / 2)
  list(pr_auc = pr_v, n = n_clean, events = n_pos, base_rate = n_pos/n_clean)
}

ic_spearman <- function(pred, actual) {
  ok <- !is.na(pred) & !is.na(actual)
  pred <- pred[ok]; actual <- actual[ok]
  if (length(pred) < 30) return(NA_real_)
  suppressWarnings(cor(pred, actual, method = "spearman"))
}

# ── Load observable targets ─────────────────────────────────────
obs_path <- file.path(TGT, "targets_long_horizon_observable.parquet")
stopifnot(file.exists(obs_path))
tgt_obs <- as.data.table(read_parquet(obs_path))
tgt_obs[, Date := as.Date(Date)]
setorder(tgt_obs, Date)
cat(sprintf("[obs] loaded %s — %d rows\n", basename(obs_path), nrow(tgt_obs)))

# Restrict observable target columns we need
tgt_q126_obs <- tgt_obs[, .(Date, y_q126_obs = y_tail_q126)]

# ── Discover all q126 prediction files ──────────────────────────
discover_predictions <- function() {
  # Subdirs and patterns for q126 predictions
  cycle_specs <- list(
    list(cycle = "53B_v5b",        dir = "v5b_patchtst_q126",
         pattern = "predictions_patchtst_v5b_y_tail_q126.parquet"),
    list(cycle = "53E_v5d_sweep",  dir = "v5d_patchtst_q126_sweep",
         pattern = "predictions_patchtst_v[0-9]+_y_tail_q126.parquet"),
    list(cycle = "53H_v5e_usmacro", dir = "v5e_patchtst_q126_usmacro",
         pattern = "predictions_patchtst_v5e_y_tail_q126.parquet"),
    list(cycle = "53I_v5f_ecos",   dir = "v5f_patchtst_q126_ecos",
         pattern = "predictions_patchtst_v5f_y_tail_q126.parquet"),
    list(cycle = "54A_v5d_FIXED",  dir = "v5d_FIXED",
         pattern = "predictions_patchtst_v[0-9]+_y_tail_q126.parquet"),
    list(cycle = "v5e_multiseed",  dir = "v5e_q126_multiseed",
         pattern = "predictions_patchtst_v5e_seed[0-9]+_y_tail_q126.parquet"),
    list(cycle = "v6a_MoE",        dir = "v6a_moe_q126",
         pattern = ".*_y_tail_q126.parquet"),
    list(cycle = "v6b_megamulti",  dir = "v6b_megamulti_q126",
         pattern = "predictions_.*_y_tail_q126.parquet"),
    list(cycle = "v6c_2stage",     dir = "v6c_2stage_q126",
         pattern = "predictions_.*_y_tail_q126.parquet")
  )
  files <- list()
  for (s in cycle_specs) {
    fdir <- file.path(MOD, s$dir)
    if (!dir.exists(fdir)) next
    fs <- list.files(fdir, pattern = s$pattern, full.names = TRUE)
    for (f in fs) {
      files[[length(files) + 1]] <- list(cycle = s$cycle, file = f, name = basename(f))
    }
  }
  files
}

prediction_files <- discover_predictions()
cat(sprintf("\n[discover] %d q126 prediction files found\n", length(prediction_files)))

# ── Re-eval each prediction file ────────────────────────────────
results <- list()

for (pf in prediction_files) {
  pred <- tryCatch(
    as.data.table(read_parquet(pf$file)),
    error = function(e) NULL
  )
  if (is.null(pred) || nrow(pred) == 0) {
    cat(sprintf("[SKIP] %s — empty or read fail\n", pf$name))
    next
  }

  # Standardize Date column
  pred[, Date := as.Date(Date)]

  # Find probability column
  pcol <- intersect(c("p_patchtst", "p_bear", "p", "pred", "p_meta", "p_v1_naive",
                     "p_v2_blend", "p_v3_alpha", "p_stage2", "p_stage1",
                     "p_expert", "p_dlinear", "p_informer", "p_timesnet",
                     "p_augmented", "p_blend", "p_naive"),
                   colnames(pred))[1]
  if (is.na(pcol)) {
    # Try any numeric prob-like col
    num_cols <- colnames(pred)[sapply(pred, is.numeric)]
    pcol <- setdiff(num_cols, c("y", "y_resolved", "split", "target", "variant_id",
                                "adopted_seed", "collapsed", "all_collapsed",
                                "fold", "fold_id"))[1]
  }
  if (is.na(pcol)) {
    cat(sprintf("[SKIP] %s — no probability column found\n", pf$name))
    next
  }

  # Merge with observable target
  merged <- merge(pred[, .SD, .SDcols = c("Date", pcol, "y")],
                  tgt_q126_obs, by = "Date", all.x = TRUE)
  setnames(merged, pcol, "p_pred")

  # Original (buggy) evaluation
  pr_orig <- pr_auc(merged$p_pred, merged$y)
  ic_orig <- ic_spearman(merged$p_pred, merged$y)

  # Observable-only evaluation
  pr_obs <- pr_auc(merged$p_pred, merged$y_q126_obs)
  ic_obs <- ic_spearman(merged$p_pred, merged$y_q126_obs)

  # Phantom-0 exclusion count
  n_phantom_excl <- sum(is.na(merged$y_q126_obs) & !is.na(merged$y))

  delta_pr <- if (!is.na(pr_orig$pr_auc) && !is.na(pr_obs$pr_auc)) {
    pr_obs$pr_auc - pr_orig$pr_auc
  } else NA_real_

  rel_change_pct <- if (!is.na(delta_pr) && !is.na(pr_orig$pr_auc) && pr_orig$pr_auc != 0) {
    100 * delta_pr / pr_orig$pr_auc
  } else NA_real_

  results[[length(results) + 1]] <- list(
    cycle              = pf$cycle,
    file               = pf$name,
    n_total            = nrow(merged),
    n_phantom_excluded = n_phantom_excl,
    orig_pr_auc        = pr_orig$pr_auc,
    obs_pr_auc         = pr_obs$pr_auc,
    delta_pr_auc       = delta_pr,
    rel_change_pct     = rel_change_pct,
    orig_ic            = ic_orig,
    obs_ic             = ic_obs,
    orig_events        = pr_orig$events,
    obs_events         = pr_obs$events,
    orig_base_rate     = pr_orig$base_rate,
    obs_base_rate      = pr_obs$base_rate
  )

  cat(sprintf("[eval] %-50s  orig=%.4f  obs=%.4f  Δ=%+.4f (%+.1f%%) phantom_excl=%d\n",
              substr(pf$name, 1, 50),
              pr_orig$pr_auc, pr_obs$pr_auc, delta_pr, rel_change_pct,
              n_phantom_excl))
}

# ── Save evaluation table ───────────────────────────────────────
dt <- rbindlist(results, fill = TRUE)
setorder(dt, -obs_pr_auc)

eval_out <- file.path(EVAL, "cycle54d_observable_reeval.json")
write_json(list(
  cycle = "54D_Phase3_4",
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  n_files = nrow(dt),
  observable_target_path = obs_path,
  notes = paste(
    "Observable PR-AUC computed against y_tail_q126 with NaN propagation",
    "(unresolved forward-126d labels excluded).",
    "Δ = obs - orig. Negative Δ = phantom-0 inflation (bug)"
  ),
  table = dt
), eval_out, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[saved] %s\n", eval_out))

# ── Phase 4: Corrected forward leaderboard ──────────────────────
cat("\n========== Phase 4: Observable-only LEADERBOARD ==========\n")
lb <- dt[!is.na(obs_pr_auc)]
lb[, rank := frank(-obs_pr_auc, ties.method = "min")]
setcolorder(lb, c("rank", "cycle", "file", "orig_pr_auc", "obs_pr_auc",
                  "delta_pr_auc", "rel_change_pct", "n_phantom_excluded",
                  "obs_events", "obs_base_rate", "orig_ic", "obs_ic"))

cat(sprintf("\n%-4s  %-20s  %-50s  %8s  %8s  %8s  %5s\n",
            "rank", "cycle", "file", "orig_PR", "obs_PR", "Δ", "excl"))
cat(strrep("-", 130), "\n")
for (i in seq_len(min(nrow(lb), 30))) {
  cat(sprintf("%-4d  %-20s  %-50s  %8.4f  %8.4f  %+8.4f  %5d\n",
              lb$rank[i], lb$cycle[i], substr(lb$file[i], 1, 50),
              lb$orig_pr_auc[i], lb$obs_pr_auc[i],
              lb$delta_pr_auc[i], lb$n_phantom_excluded[i]))
}

lb_out <- file.path(EVAL, "cycle54d_observable_leaderboard.json")
write_json(list(
  cycle = "54D_Phase4",
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  ranking_metric = "observable_pr_auc_descending",
  observable_target = obs_path,
  leaderboard = lb
), lb_out, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[saved] %s\n", lb_out))

#----------------------------------------------------------------------
# Summary statistics
#----------------------------------------------------------------------
cat("\n========== Summary statistics ==========\n")
cat(sprintf("Files evaluated: %d\n", nrow(lb)))
cat(sprintf("Median Δ PR-AUC: %+.4f\n", median(lb$delta_pr_auc, na.rm = TRUE)))
cat(sprintf("Mean Δ PR-AUC:   %+.4f\n", mean(lb$delta_pr_auc, na.rm = TRUE)))
cat(sprintf("Min Δ:           %+.4f\n", min(lb$delta_pr_auc, na.rm = TRUE)))
cat(sprintf("Max Δ:           %+.4f\n", max(lb$delta_pr_auc, na.rm = TRUE)))
cat(sprintf("Median |Δ|:      %.4f\n", median(abs(lb$delta_pr_auc), na.rm = TRUE)))

cat(sprintf("\nFiles with Δ < -0.02 (significant inflation): %d / %d\n",
            sum(lb$delta_pr_auc < -0.02, na.rm = TRUE), nrow(lb)))
cat(sprintf("Files with Δ < -0.05 (major inflation):       %d / %d\n",
            sum(lb$delta_pr_auc < -0.05, na.rm = TRUE), nrow(lb)))

cat("\n========== Phase 3+4 DONE ==========\n")
