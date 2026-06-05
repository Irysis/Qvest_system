#==============================================================================
# 153_robust_leaderboard.R — Cycle 54D Phase 4 supplement
#
# Goal:
#   Combine 3-criteria strict robustness filter:
#     (1) Observable-only PR-AUC (152 result) ≥ threshold
#     (2) Strict determinism: non-collapsed adopted seed (from v5d_FIXED only)
#     (3) Period-balanced: geometric-mean PR across S2018-19 + S2020-21 + S2022-24
#
#   For non-v5d_FIXED cycles (no period_metrics available), report observable
#   PR-AUC only as best-effort indicator.
#
# Output: outputs/04_evaluation/cycle54d_robust_leaderboard.json
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS  <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
EVAL <- file.path(WS, "outputs/04_evaluation")

cat("\n========== Cycle 54D 3-criteria robust leaderboard ==========\n")

# ── 1) Observable-only PR-AUC from 152 result ─────────────
lb_obs <- fromJSON(file.path(EVAL, "cycle54d_observable_leaderboard.json"))$leaderboard
setDT(lb_obs)
cat(sprintf("[obs] %d entries\n", nrow(lb_obs)))

# ── 2) Add strict det + period-balanced where available (v5d_FIXED) ──
diag_fixed <- fromJSON(file.path(WS, "outputs/03_models/v5d_FIXED/variant_diagnostics.json"))
res_fixed  <- diag_fixed$results

geom_mean <- function(x) {
  x <- x[!is.na(x) & x > 0]
  if (length(x) == 0) return(NA_real_)
  exp(mean(log(x)))
}

fixed_rows <- list()
for (vname in names(res_fixed)) {
  r <- res_fixed[[vname]]
  pm <- r$period_metrics
  # Strip "_y_tail_q126" suffix; map back to filename
  v_id <- r$variant_id
  filename <- sprintf("predictions_patchtst_v%d_y_tail_q126.parquet", v_id)
  pb <- geom_mean(c(
    pm$"S2018-19_calm"$pr_auc,
    pm$"S2020-21_COVID"$pr_auc,
    pm$"S2022-24_Stagflation"$pr_auc
  ))
  fixed_rows[[length(fixed_rows) + 1]] <- list(
    cycle = "54A_v5d_FIXED",  # only v5d_FIXED has these period metrics
    file = filename,
    period_balanced_pr_geomean = pb,
    all_collapsed = r$all_collapsed,
    adopted_seed  = r$adopted_seed,
    s2018_19_pr   = pm$"S2018-19_calm"$pr_auc,
    s2020_21_pr   = pm$"S2020-21_COVID"$pr_auc,
    s2022_24_pr   = pm$"S2022-24_Stagflation"$pr_auc
  )
}
dt_fixed <- rbindlist(fixed_rows)

# Join observable leaderboard with strict det + period-balanced ON cycle+file
# (53E and 54A share file names but are different runs — strict det only applies to 54A)
lb <- merge(lb_obs, dt_fixed, by = c("cycle", "file"), all.x = TRUE)

# Apply 3-criteria filter
lb[, is_strict_det := !is.na(all_collapsed) & all_collapsed == FALSE]
lb[, has_period_balanced := !is.na(period_balanced_pr_geomean)]
lb[, robust_candidate :=
   is_strict_det &
   has_period_balanced &
   period_balanced_pr_geomean >= 0.30 &
   obs_pr_auc >= 0.30]

# Composite score = pmin(obs_pr_auc, period_balanced)
lb[, composite_robust_score :=
   pmin(obs_pr_auc, period_balanced_pr_geomean, na.rm = FALSE)]
setorder(lb, -composite_robust_score, na.last = TRUE)

cat("\n========== 3-criteria ROBUST CANDIDATES (TRUE forward best) ==========\n")
cands <- lb[robust_candidate == TRUE]
if (nrow(cands) > 0) {
  cat(sprintf("\n%-30s  %-8s  %-8s  %-8s  %-8s  %-8s  %-8s\n",
              "file", "obs_PR", "PB_geo", "S18-19", "S20-21", "S22-24", "score"))
  cat(strrep("-", 100), "\n")
  for (i in seq_len(nrow(cands))) {
    cat(sprintf("%-30s  %8.4f  %8.4f  %8.4f  %8.4f  %8.4f  %8.4f\n",
                substr(cands$file[i], 1, 30),
                cands$obs_pr_auc[i],
                cands$period_balanced_pr_geomean[i],
                cands$s2018_19_pr[i],
                cands$s2020_21_pr[i],
                cands$s2022_24_pr[i],
                cands$composite_robust_score[i]))
  }
} else {
  cat("[!] No candidate passed 3-criteria. Showing top 10 ranked by composite score:\n")
}

cat("\n========== Top 10 ranked by composite_robust_score ==========\n")
top10 <- head(lb, 10)
cat(sprintf("\n%-30s  %-8s  %-8s  %-10s  %-8s  %-12s\n",
            "file", "obs_PR", "PB_geo", "strict_det", "score", "robust_pass"))
cat(strrep("-", 100), "\n")
for (i in seq_len(nrow(top10))) {
  cat(sprintf("%-30s  %8.4f  %8s  %-10s  %8s  %-12s\n",
              substr(top10$file[i], 1, 30),
              top10$obs_pr_auc[i],
              if (!is.na(top10$period_balanced_pr_geomean[i])) sprintf("%.4f", top10$period_balanced_pr_geomean[i]) else "N/A",
              if (!is.na(top10$is_strict_det[i]) && top10$is_strict_det[i]) "PASS" else "N/A",
              if (!is.na(top10$composite_robust_score[i])) sprintf("%.4f", top10$composite_robust_score[i]) else "N/A",
              if (!is.na(top10$robust_candidate[i]) && top10$robust_candidate[i]) "ROBUST" else "WEAK"))
}

# Save robust leaderboard
robust_out <- file.path(EVAL, "cycle54d_robust_leaderboard.json")
write_json(list(
  cycle = "54D_Phase4_robust",
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  criteria = list(
    obs_pr_auc_threshold = 0.30,
    period_balanced_pr_geomean_threshold = 0.30,
    strict_det_required = TRUE,
    periods_required = c("S2018-19_calm", "S2020-21_COVID", "S2022-24_Stagflation")
  ),
  robust_candidates = cands,
  full_leaderboard = lb,
  notes = paste(
    "v5d_FIXED variants (n=6) have strict det + period-balanced metrics.",
    "Other cycles (35 entries) marked as 'has_period_balanced=FALSE' since",
    "they were trained before strict det infra (v5d_FIXED) was introduced.",
    "Composite_score = pmin(obs_pr_auc, period_balanced_pr_geomean)."
  )
), robust_out, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[saved] %s\n", robust_out))

cat("\n========== DONE ==========\n")
