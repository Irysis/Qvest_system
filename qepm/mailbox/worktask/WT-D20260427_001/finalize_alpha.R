# =============================================================================
# WT-D20260427_001 Iter 17 — Finalize alpha_package.json
#   Order: alpha_package_draft.json → alpha_package.json (final)
#          + record_package_lineage (L-194 fix order)
#          + status.json update
# =============================================================================

suppressPackageStartupMessages({
  library(jsonlite); library(digest); library(arrow); library(data.table)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0L && !is.na(a[[1L]])) a[[1L]] else b

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-D20260427_001"
WT_DIR_TAG   <- "WT_D20260427_001"
WT_MAIL_DIR  <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
ARTIFACT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", WT_DIR_TAG)
DRAFT_PATH   <- file.path(WT_MAIL_DIR, "alpha_package_draft.json")
FINAL_PATH   <- file.path(WT_MAIL_DIR, "alpha_package.json")

setwd(PROJECT_ROOT)
cat("=== Finalize Alpha Package WT-D20260427_001 (Iter 17) ===\n")

stopifnot(file.exists(DRAFT_PATH))
draft <- fromJSON(DRAFT_PATH, simplifyVector = FALSE)

# Sanity checks
stopifnot(draft$selection_objective == "icir")
stopifnot(draft$task_id == WT_ID)
stopifnot(length(draft$alpha_vector) == 20L)
stopifnot(length(draft$confidence_vector) == 20L)

# Step 1: Write final alpha_package.json (FIRST per L-194)
write_json(draft, FINAL_PATH, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("[1] alpha_package.json saved → %s\n", FINAL_PATH))

# Step 2: Lineage record (AFTER write per L-194)
source(file.path(PROJECT_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
input_files <- c(
  file.path(WT_MAIL_DIR, "request.json"),
  file.path(PROJECT_ROOT, ".cache/rawdata.parquet"),
  file.path(PROJECT_ROOT, ".cache/kr_factor_returns_v2.parquet"),
  file.path(PROJECT_ROOT, ".cache/investor_stock/investor_wide.parquet"),
  file.path(ARTIFACT_DIR, "alpha_scores.parquet"),
  file.path(ARTIFACT_DIR, "alpha_validation.json"),
  file.path(WT_MAIL_DIR, "factor_engine_proposal.R"),
  file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260426_004/alpha_scores.parquet"),
  file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260426_006/alpha_scores.parquet")
)
input_files <- input_files[file.exists(input_files)]

setwd(PROJECT_ROOT)
record_package_lineage(
  task_id = WT_ID,
  package_type = "alpha_package",
  method_selected = "M07_XGBoost_depth4_interaction (4 explicit factors NCSKEW/Q05_Accrual/Q07/Q09_CFOA + foreign_flow_resid + KR FF5 v2 lagged 6F, 5-seed ensemble + early stop + L1/L2)",
  input_file_paths = input_files,
  windows = list(
    train_validation_window = list(start = "2003-01-01", end = "2024-01-22"),
    lockbox_window = list(start = "2024-01-23", end = "2026-01-23", sealed = TRUE)
  ),
  random_seed = 20260427001L,
  extra = list(
    parent_iters = list("STR_1701_WT004_Iter11", "STR_1656_M06_v2_REVISE"),
    iter_name = "STR_1701_M07_iter17_xgb_d4_nonlinear_crossfamily",
    factor_formula_hash = draft$alpha_factor_formula_hash,
    selection_objective = draft$selection_objective,
    role = "diversifier",
    cross_family_target_str1701 = "<0.30",
    cross_family_target_str1656 = "<0.30"
  )
)

# Step 3: status.json update
status_path <- file.path(WT_MAIL_DIR, "status.json")
status <- list(
  task_id = WT_ID,
  current_phase = "ALPHA_DONE",
  version = "v1",
  updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  blocker = NULL,
  alpha_summary = list(
    method = "M07_XGBoost_depth4_interaction",
    n_sig_dates = draft$diagnostics$n_sig_dates,
    icir = draft$diagnostics$icir,
    rank_ic = draft$diagnostics$rank_ic,
    harvey_t_nw_hac = draft$diagnostics$harvey_t_nw_hac,
    sub_stab = draft$diagnostics$subperiod_stability,
    turnover_proxy = draft$diagnostics$turnover_proxy,
    dsr_post = draft$diagnostics$deflated_sharpe_ratio,
    five_spec_pass = sprintf("%d/%d",
                              draft$five_spec_summary$specs_pass,
                              draft$five_spec_summary$specs_total),
    cor_vs_str1701 = draft$cross_family_correlation$vs_str1701_pearson,
    cor_vs_str1656 = draft$cross_family_correlation$vs_str1656_pearson,
    cor_vs_str1701_pass = draft$cross_family_correlation$vs_str1701_pass,
    cor_vs_str1656_pass = draft$cross_family_correlation$vs_str1656_pass,
    universe_compliance = sprintf("top20=%d/%d",
                                   draft$universe_compliance$top20_in_universe_count,
                                   draft$universe_compliance$top20_total),
    liquidity_compliance = sprintf("top20_pass_2e8=%d/%d",
                                    draft$liquidity_compliance$top20_pass_2e8_count,
                                    draft$universe_compliance$top20_total),
    gates_pass = sprintf("%d/%d",
                         draft$graduation_status_summary$gates_pass,
                         draft$graduation_status_summary$gates_total),
    challenge_flags_count = length(draft$challenge_flags)
  )
)
write_json(status, status_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("[3] status.json saved → %s\n", status_path))

cat("\n=== FINALIZE COMPLETE ===\n")
cat(sprintf("alpha_package.json: %s\n", FINAL_PATH))
cat(sprintf("ICIR=%.4f rank_IC=%.4f Harvey_NW=%s sub_stab=%.4f turnover=%.2f%%\n",
            draft$diagnostics$icir,
            draft$diagnostics$rank_ic,
            format(draft$diagnostics$harvey_t_nw_hac, nsmall=4),
            draft$diagnostics$subperiod_stability,
            draft$diagnostics$turnover_proxy * 100))
cat(sprintf("Cor vs STR_1701: %.4f (mandate<0.30, pass=%s) | vs STR_1656: %.4f (pass=%s)\n",
            draft$cross_family_correlation$vs_str1701_pearson,
            draft$cross_family_correlation$vs_str1701_pass,
            draft$cross_family_correlation$vs_str1656_pearson,
            draft$cross_family_correlation$vs_str1656_pass))
cat(sprintf("Gates: %d/%d | 5-spec: %d/%d | Universe: top20=%d/20 | Liq: %d/20\n",
            draft$graduation_status_summary$gates_pass,
            draft$graduation_status_summary$gates_total,
            draft$five_spec_summary$specs_pass,
            draft$five_spec_summary$specs_total,
            draft$universe_compliance$top20_in_universe_count,
            draft$liquidity_compliance$top20_pass_2e8_count))
cat(sprintf("Challenge flags: %d\n", length(draft$challenge_flags)))
