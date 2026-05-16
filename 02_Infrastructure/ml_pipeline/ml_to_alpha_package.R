#==============================================================================
# ml_to_alpha_package.R -- Python ML pipeline → R alpha-research bridge
#
# 7 QEPM Modern Trends Phase 1 통합 path
# Constitutional SOT: qvest_research_philosophy.md (L-321)
#
# Inputs (from `02_Infrastructure/ml_pipeline/run_ml_cycle.py` outputs):
#   stage_artifacts/{WT_ID}/predictions.parquet           (base, 5+Ensemble)
#   stage_artifacts/{WT_ID}/predictions_with_ci.parquet   (Phase 1.A optional)
#   stage_artifacts/{WT_ID}/summary_metrics.json
#   stage_artifacts/{WT_ID}/manifest.json
#
# Outputs:
#   qepm/mailbox/worktask/{WT_ID}/alpha_package_draft.json   (Codex Round 1단계)
#   qepm/mailbox/worktask/{WT_ID}/alpha_features.parquet     (sig_date × Ticker × alpha_score)
#
# Flow:
#   Python ML cycle → predictions/predictions_with_ci → R bridge → alpha_package_draft.json
#   → PostToolUse Codex auto-spawn (codex_round_auto_trigger.sh)
#   → codex_critic_response_alpha.json
#   → challenge_note.md (Q-Lead)
#   → alpha_package.json (final, codex_round_pre_enforcer.sh PASS)
#==============================================================================
suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

ml_to_alpha_package <- function(ml_out_dir,
                                  wt_id,
                                  preferred_model = "M6_Ensemble",
                                  use_uncertainty_discount = FALSE,
                                  k_discount = 1.0,
                                  exclude_lockbox_from_alpha = TRUE,
                                  mailbox_dir = "qepm/mailbox/worktask") {

  ml_out <- normalizePath(ml_out_dir, mustWork = TRUE)
  pred_path <- file.path(ml_out, "predictions.parquet")
  ci_path <- file.path(ml_out, "predictions_with_ci.parquet")
  summary_path <- file.path(ml_out, "summary_metrics.json")
  manifest_path <- file.path(ml_out, "manifest.json")
  stopifnot(file.exists(pred_path))

  pred <- as.data.table(read_parquet(pred_path))
  summ <- fromJSON(summary_path, simplifyVector = FALSE)
  manifest <- if (file.exists(manifest_path)) fromJSON(manifest_path, simplifyVector = FALSE) else list()

  # ---- 1) Select alpha scores from preferred model ----
  alpha_scores <- pred[model == preferred_model]
  if (exclude_lockbox_from_alpha) {
    alpha_scores <- alpha_scores[mode != "lockbox"]
  }
  if (nrow(alpha_scores) == 0L) {
    stop(sprintf("No alpha scores for model='%s' (lockbox excluded=%s)",
                  preferred_model, exclude_lockbox_from_alpha))
  }

  # ---- 2) Optional uncertainty discount overlay (Phase 1.A) ----
  if (use_uncertainty_discount && file.exists(ci_path)) {
    ci <- as.data.table(read_parquet(ci_path))
    # ci contains pred_mean / pred_std / pred_discounted / etc.
    alpha_scores <- merge(alpha_scores,
                           ci[, .(sig_date, Ticker, pred_std, pred_discounted)],
                           by = c("sig_date", "Ticker"), all.x = TRUE)
    # If uncertainty data available, use discounted score; else fall back to model score
    alpha_scores[!is.na(pred_discounted), score := pred_discounted]
    used_discount <- mean(!is.na(alpha_scores$pred_discounted))
  } else {
    used_discount <- 0
  }

  # ---- 3) Save alpha_features.parquet ----
  mailbox <- file.path(mailbox_dir, wt_id)
  dir.create(mailbox, showWarnings = FALSE, recursive = TRUE)
  alpha_feat_path <- file.path(mailbox, "alpha_features.parquet")
  write_parquet(alpha_scores[, .(sig_date, Ticker, alpha_score = score, model, fold_id, mode)],
                  alpha_feat_path)

  # ---- 4) Extract graduation gates from summary ----
  key_lockbox <- paste0(preferred_model, "_lockbox")
  lockbox_stats <- summ[[key_lockbox]]
  key_all <- paste0(preferred_model, "_all")
  all_stats <- summ[[key_all]]
  if (is.null(lockbox_stats)) {
    warning(sprintf("summary_metrics.json missing key '%s' — gates incomplete", key_lockbox))
    lockbox_stats <- list()
  }

  # ---- 5) Build alpha_package_draft.json ----
  alpha_package <- list(
    wt_id = wt_id,
    role = "alpha-research",
    status = "draft",
    source = "python_ml_pipeline",
    pipeline_manifest = manifest,
    model_used = preferred_model,
    factor_specs = list(
      list(
        factor_family = "ML_LARGE_SCALE_ENSEMBLE",
        factor_name = paste0("ML_", preferred_model),
        feature_count = manifest$n_features %||% NA,
        train_window_months = manifest$bootstraps %||% NA,
        gates = list(
          rank_IC = lockbox_stats$rank_ic %||% NA,
          ICIR = lockbox_stats$icir %||% NA,
          NW_t_lag6 = lockbox_stats$t_nw_lag6 %||% NA,
          DSR_z_n5 = lockbox_stats$dsr_z_n5 %||% NA,
          monotonicity = lockbox_stats$monotonicity %||% NA,
          gross_port_sr = lockbox_stats$gross_port_sr %||% NA,
          net_port_sr = lockbox_stats$net_port_sr %||% NA,
          cost_drag_pp = lockbox_stats$cost_drag_pp %||% NA,
          annualized_turnover = lockbox_stats$annualized_turnover %||% NA
        ),
        gates_all = list(
          rank_IC = all_stats$rank_ic %||% NA,
          ICIR = all_stats$icir %||% NA,
          NW_t_lag6 = all_stats$t_nw_lag6 %||% NA,
          monotonicity = all_stats$monotonicity %||% NA
        ),
        mechanism_text = paste0(
          "ML ensemble (", preferred_model, ") trained on ", manifest$n_features %||% "?", " features ",
          "via walk-forward CV (", manifest$lockbox_folds %||% 2, " lockbox folds). ",
          "Kelly-Malamud-Zhou 2024 'Virtue of Complexity' 정통 — high-dim regularization. ",
          if (use_uncertainty_discount) sprintf("Uncertainty-discounted (Liao 2025 RFS, k=%.2f, applied to %.0f%% of scores).",
                                                  k_discount, used_discount * 100) else "Point estimate.",
          if (!is.null(manifest$gamma) && manifest$gamma > 0)
            sprintf(" Cost-aware (Jensen-Kelly 2022, γ=%.4f).", manifest$gamma) else ""
        ),
        economic_rationale = paste0(
          "Cross-sectional ML alpha. Validation > Discovery (7 trends Principle 1). ",
          "Walk-forward CV strict PIT, lockbox OOS held out from model selection."
        )
      )
    ),
    alpha_features_path = alpha_feat_path,
    phase1_extensions = list(
      uncertainty_aware_enabled = isTRUE(manifest$phase1_uncertainty_enabled) || use_uncertainty_discount,
      cost_aware_enabled = isTRUE(manifest$phase1_cost_aware_enabled),
      k_discount = if (use_uncertainty_discount) k_discount else NA_real_,
      gamma = manifest$gamma
    ),
    codex_round_required = TRUE,
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )

  draft_path <- file.path(mailbox, "alpha_package_draft.json")
  write(toJSON(alpha_package, pretty = TRUE, auto_unbox = TRUE, na = "null"),
        file = draft_path)

  cat(sprintf("✓ alpha_package_draft.json written: %s\n", draft_path))
  cat(sprintf("✓ alpha_features.parquet written: %s\n", alpha_feat_path))
  cat(sprintf("✓ model: %s | lockbox NW_t = %s | mono = %s\n",
               preferred_model,
               format(lockbox_stats$t_nw_lag6, digits = 3),
               format(lockbox_stats$monotonicity, digits = 3)))
  cat("Next: PostToolUse codex_round_auto_trigger.sh will fire on draft Write.\n")
  cat("      Then: challenge_note.md → alpha_package.json (final, no _draft).\n")

  invisible(alpha_package)
}

# null-coalesce helper for older R versions
`%||%` <- function(a, b) if (is.null(a)) b else a
