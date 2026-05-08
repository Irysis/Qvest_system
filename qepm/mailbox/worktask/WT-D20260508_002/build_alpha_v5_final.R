#==============================================================================
# WT-D20260508_002 v5 final — post-Codex remediation + alpha_package.json
#
# Codex 7 concerns remediation (post-Codex round, this file):
#   C1 ACCEPT: empirical fail already declared (no admit) → confirm
#   C2 ACCEPT: max-20 TO 10.60 hurdle fail already declared (no admit) → confirm
#   C3 PARTIAL: RF-A3 recent 3Y ICIR concentration → add to challenge_flags
#   C4 ACCEPT: sector-neutral on pred_xgb (selected, not pred_ens) → compute + add
#   C5 PARTIAL: missing weights.csv/covariance.parquet — document scope = alpha-only
#                run_all.R reference removed from lineage
#   C6 ACCEPT: alpha_vector nullified (set to NA) when op_pass=FALSE +
#               no_deploy_flag=true machine-readable
#   C7 ACCEPT: page-level references downgraded to mechanism background
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})
options(warn = 1)

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260508_002"
WT_DIR <- file.path(PROJ, "qepm", "mailbox", "worktask", WT_ID)
ART_DIR <- file.path(PROJ, "stage_artifacts", "WT_D20260508_002")

cat("================================================================\n")
cat("WT-D20260508_002 v5 FINAL — post-Codex remediation\n")
cat("================================================================\n")

# Load Phase 3 cache
ph3 <- readRDS(file.path(WT_DIR, "phase3_cache.rds"))
diag_results <- ph3$diag_results
max20_results <- ph3$max20_results
dsr_log <- ph3$dsr_log
gate_summary <- ph3$gate_summary
best_model <- ph3$best_model
fwd_preds <- ph3$fwd_preds

# Load draft + Codex response
draft <- fromJSON(file.path(WT_DIR, "alpha_package_v5_draft.json"), simplifyVector = FALSE)
codex_resp <- fromJSON(file.path(WT_DIR, "codex_critic_response_alpha_v5.json"), simplifyVector = FALSE)
cat("Codex stance:", codex_resp$stance, "\n")
cat("Codex critical_concerns:", length(codex_resp$critical_concerns), "\n")

#--- Codex C4: sector-neutral pred_xgb (the selected model, not pred_ens) ---
cat("\n[1] Codex C4 remediation: sector-neutral pred_xgb diagnostics...\n")
preds <- as.data.table(read_parquet(file.path(ART_DIR, "predictions_v5_all_models.parquet")))
preds[, YM_target := as.Date(YM_target)]
preds[YM_target == as.Date("2026-05-01"), `:=`(y_actual = NA_real_, ret_actual = NA_real_)]
realized <- preds[!is.na(y_actual)]

# Sector demean pred_xgb per month
realized[, sec := ifelse(is.na(Sector) | Sector == "", "UNKNOWN", as.character(Sector))]
realized[, pred_xgb_secneutral := pred_xgb - mean(pred_xgb, na.rm = TRUE), by = .(YM_target, sec)]

# IC of sector-neutral pred_xgb
ic_per_month_xgb_sn <- realized[, .(
  ic = if (.N >= 5 && sd(pred_xgb_secneutral, na.rm = TRUE) > 0 && sd(y_actual, na.rm = TRUE) > 0)
         cor(pred_xgb_secneutral, y_actual, method = "spearman", use = "complete.obs")
       else NA_real_
), by = YM_target][!is.na(ic)]
xgb_sn_rank_ic <- mean(ic_per_month_xgb_sn$ic)
xgb_sn_icir <- xgb_sn_rank_ic / (sd(ic_per_month_xgb_sn$ic, na.rm = TRUE) + 1e-9)
xgb_raw_ic <- diag_results$pred_xgb$rank_ic
xgb_neutral_retention <- xgb_sn_rank_ic / max(abs(xgb_raw_ic), 1e-9)
xgb_rf_a4_flag <- abs(xgb_sn_rank_ic) < 0.3 * abs(xgb_raw_ic)

cat(sprintf("  pred_xgb raw_ic: %.4f\n  pred_xgb sector-neutral IC: %.4f\n  retention: %.1f%%\n  RF-A4 flag (< 30%%): %s\n",
            xgb_raw_ic, xgb_sn_rank_ic, xgb_neutral_retention * 100, xgb_rf_a4_flag))

#--- Codex C3 remediation: recent 3Y ICIR concentration (RF-A3) ---
cat("\n[2] Codex C3 remediation: RF-A3 recent-3Y concentration test...\n")
ic_per_month_xgb <- realized[, .(
  ic = if (.N >= 5) cor(pred_xgb, y_actual, method = "spearman", use = "complete.obs") else NA_real_
), by = YM_target][!is.na(ic)]
recent_36m <- tail(ic_per_month_xgb, 36)
recent_3y_icir <- mean(recent_36m$ic) / (sd(recent_36m$ic) + 1e-9)
full_icir <- xgb_raw_ic / (sd(ic_per_month_xgb$ic) + 1e-9)
rf_a3_flag <- recent_3y_icir > full_icir * 1.5
cat(sprintf("  Recent 36m ICIR: %.4f\n  Full-sample ICIR x 1.5: %.4f\n  RF-A3 concentration flag: %s\n",
            recent_3y_icir, full_icir * 1.5, rf_a3_flag))

# 2018-2021 subperiod check
sub_2018_2021 <- ic_per_month_xgb[YM_target >= as.Date("2018-01-01") & YM_target < as.Date("2022-01-01")]
sub_neg_period <- mean(sub_2018_2021$ic, na.rm = TRUE)
cat(sprintf("  2018-2021 subperiod IC: %.4f\n", sub_neg_period))

#--- Codex C6: nullify alpha_vector + no_deploy_flag ---
cat("\n[3] Codex C6 remediation: nullify alpha_vector when op_pass=FALSE...\n")
op_pass_v5 <- gate_summary[[best_model]]$pass_all
cat("  op_pass_v5:", op_pass_v5, "\n")

# Codex C6: alpha_vector should be NULL/zero or no_deploy flag set when fail
n_tickers <- length(draft$alpha_vector)
alpha_vec_nullified <- as.list(rep(NA_real_, n_tickers))
names(alpha_vec_nullified) <- names(draft$alpha_vector)
conf_zeroed <- as.list(rep(0, n_tickers))
names(conf_zeroed) <- names(draft$alpha_vector)

cat(sprintf("  Nullified %d-ticker alpha_vector (NA) + confidence_vector (0)\n", n_tickers))
cat("  no_deploy_flag = TRUE (Codex C6 + AX-002 governance)\n")

#--- Build final alpha_package ---
cat("\n[4] Build alpha_package.json (v5 final)...\n")

# Update challenge_flags with new Codex-driven entries
new_flags <- draft$challenge_flags
add_flag <- function(id, severity, msg) list(id = id, severity = severity, msg = msg)

new_flags <- c(new_flags, list(add_flag(
  "CODEX_C3_RF_A3_RECENT_3Y_CONCENTRATION", "MEDIUM",
  paste0("Recent 36m ICIR=", round(recent_3y_icir, 3), " > full ICIR x 1.5 = ",
         round(full_icir * 1.5, 3),
         ". 2018-2021 subperiod IC=", round(sub_neg_period, 4),
         " (negative regime). RF-A3 overfit/regime-concentration warning. ",
         "Empirical FAIL already overrides admission, but informational."))))

new_flags <- c(new_flags, list(add_flag(
  "CODEX_C4_SECTOR_NEUTRAL_PRED_XGB", "MEDIUM",
  paste0("Sector-neutral diagnostics on selected pred_xgb (Codex C4 specific): ",
         "raw_ic=", round(xgb_raw_ic, 4), ", sector-neutral_ic=", round(xgb_sn_rank_ic, 4),
         ", retention=", round(xgb_neutral_retention * 100, 1), "%. ",
         "RF-A4 flag: ", xgb_rf_a4_flag,
         ". Earlier sector-neutral was on pred_ens, this is the selected-model audit."))))

new_flags <- c(new_flags, list(add_flag(
  "CODEX_C5_ARTIFACT_SCOPE_ALPHA_ONLY", "LOW_INFORMATIONAL",
  paste0("This WT scope = alpha-only (per Charter v1.7 §10 discovery role card). ",
         "No weights.csv / covariance.parquet / risk_package / optimization_package. ",
         "Risk + Optimizer + Forge stages skipped because op_pass_v5=FALSE → no admit. ",
         "Pre-LB/Lockbox/Combined 3-way report not applicable (not promoted to deployment)."))))

new_flags <- c(new_flags, list(add_flag(
  "CODEX_C6_ALPHA_VECTOR_NULLIFIED_NO_DEPLOY", "HIGH",
  paste0("alpha_vector and confidence_vector NULLIFIED (alpha=NA, conf=0) per Codex C6 governance ",
         "(machine-enforced no-deploy when op_pass=FALSE). no_deploy_flag=TRUE. ",
         "Forward-2026-05 raw predictions still in stage_artifacts/predictions_v5_all_models.parquet ",
         "for forensic audit only — NOT for downstream consumption."))))

# Mark Codex stance + verdict in package
codex_summary <- list(
  invoked = TRUE,
  stance = codex_resp$stance,
  veto_flag = codex_resp$veto_flag,
  critical_concerns_count = length(codex_resp$critical_concerns),
  highest_severity = "HIGH",
  agreement = "Codex agrees no-admit (verification_triangulation.agree_with_claude = TRUE direction). REJECT verdict targets artifact governance, not the empirical FAIL diagnosis.",
  remediation_classification = list(
    C1_alpha_gates_fail = "ACCEPT — empirical FAIL already declared in package; no remediation needed beyond confirmation.",
    C2_max20_TO_hurdle_fail = "ACCEPT — empirical FAIL already declared in challenge_flags.",
    C3_RF_A3_recent_3Y_concentration = "PARTIAL — added challenge_flag CODEX_C3_RF_A3_RECENT_3Y_CONCENTRATION informational",
    C4_sector_neutral_pred_xgb = "ACCEPT — computed selected-model sector-neutral diagnostics, added challenge_flag.",
    C5_artifact_governance = "PARTIAL — documented scope=alpha-only WT; risk/optimizer/forge stages skipped because op_pass_v5=FALSE. lineage path corrected.",
    C6_alpha_vector_governance = "ACCEPT — alpha_vector nullified to NA + confidence_vector zeroed + no_deploy_flag=TRUE (machine-enforced).",
    C7_page_level_references = "ACCEPT — academic references downgraded to mechanism background (admission moot post-FAIL)."
  )
)

# Final alpha_package
alpha_package_final <- draft
alpha_package_final$alpha_vector <- alpha_vec_nullified
alpha_package_final$confidence_vector <- conf_zeroed
alpha_package_final$no_deploy_flag <- TRUE
alpha_package_final$no_deploy_rationale <- paste0(
  "op_pass_v5=FALSE (Codex REJECT confirmed). All graduation gates fail. ",
  "alpha_vector NA + confidence 0 prevents downstream consumption. ",
  "Forward 2026-05 raw predictions retained in stage_artifacts for forensic audit only."
)
alpha_package_final$challenge_flags <- new_flags
alpha_package_final$codex_round <- codex_summary

# Add post-Codex addenda
alpha_package_final$post_codex_addenda <- list(
  pred_xgb_sector_neutral = list(
    raw_ic = round(xgb_raw_ic, 6),
    sector_neutral_ic = round(xgb_sn_rank_ic, 6),
    sector_neutral_icir = round(xgb_sn_icir, 4),
    neutral_retention_pct = round(xgb_neutral_retention * 100, 1),
    rf_a4_flag = xgb_rf_a4_flag
  ),
  rf_a3_recent_concentration = list(
    recent_36m_icir = round(recent_3y_icir, 4),
    full_icir = round(full_icir, 4),
    threshold_full_x_1p5 = round(full_icir * 1.5, 4),
    rf_a3_flag = rf_a3_flag,
    subperiod_2018_2021_mean_ic = round(sub_neg_period, 6),
    interpretation = "Recent 3Y ICIR exceeds full×1.5 → regime concentration risk. 2018-2021 subperiod negative IC → period-specific bear regime. Empirical FAIL on full-sample prevents regime-conditional admission."
  ),
  artifact_scope = list(
    wt_type = "discovery",
    wt_scope = "alpha-only",
    artifacts_intentionally_absent = list(
      "weights.csv (Optimizer artifact, not produced)",
      "covariance.parquet (Risk artifact, not produced)",
      "risk_package.json (Risk-Research stage skipped — op_pass=FALSE)",
      "optimization_package.json (Optimizer stage skipped — op_pass=FALSE)",
      "Pre-LB/Lockbox/Combined 3-way report (deployment artifact, N/A pre-admit)"
    ),
    rationale = paste0(
      "WT-D20260508_002 = discovery role card. Alpha agent emits package. ",
      "op_pass=FALSE → graduation_gate fails → no Risk/Optimizer/Forge spawn. ",
      "Charter v1.7 §10 Role Card 4×5 cert inheritance: not applicable when discovery_pass=false."
    )
  )
)

# Update v_history_summary with v5 final tag
alpha_package_final$v_history_summary$v5 <- paste0(
  "v4 8-concern full remediation. PIT-rolling factor universe + GPU. IC ",
  round(xgb_raw_ic, 4), " (DISCOVERY_FAIL_HONEST_PIT_PROPER). ",
  "Codex round REJECT (artifact governance) → 7 concerns ACCEPT/PARTIAL. ",
  "alpha_vector nullified, no_deploy_flag=TRUE."
)

alpha_package_final$pipeline_stage <- "alpha_v5_final_post_codex_no_admit"
alpha_package_final$finalize_label <- "DISCOVERY_FAIL_HONEST_PIT_PROPER_POST_CODEX_REJECT_GOVERNANCE_REMEDIATED"

# Write final
final_path <- file.path(WT_DIR, "alpha_package.json")
writeLines(toJSON(alpha_package_final, pretty = TRUE, auto_unbox = TRUE, na = "null"), final_path)
cat(sprintf("\n[5] Wrote alpha_package.json (%d bytes)\n", file.info(final_path)$size))

# Update lineage
tryCatch({
  source(file.path(PROJ, "02_Infrastructure/worktask/lineage_utils.R"))
  setwd(PROJ)
  record_package_lineage(
    task_id = WT_ID,
    package_type = "alpha_package_final_v5_post_codex",
    method_selected = paste0("ml_residual_pit_proper_v5_FAIL_no_admit_codex_remediated_best=", best_model),
    input_file_paths = c(
      ".cache/rawdata.parquet",
      ".cache/factor_db/factor_db_*.parquet",
      "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/bt_result.rds",
      "stage_artifacts/WT_D20260508_002/predictions_v5_all_models.parquet",
      paste0("qepm/mailbox/worktask/", WT_ID, "/codex_critic_response_alpha_v5.json")
    ),
    wt_root = "qepm/mailbox/worktask"
  )
  cat("  Lineage recorded\n")
}, error = function(e) cat("  Lineage record FAIL (non-fatal):", conditionMessage(e), "\n"))

cat("\n================================================================\n")
cat("alpha_package.json finalized (v5 post-Codex). Disposition: DISCOVERY_FAIL_HONEST_PIT_PROPER\n")
cat("================================================================\n")
