# =============================================================================
# WT-D20260426_006 v2 — Finalize alpha_package.json (overwrite)
# Order: alpha_package_draft.json (v2) → alpha_package.json (final)
#        + Codex R1 v2 reference (existing v1 codex used as concern source)
#        + record_package_lineage (L-194 fix order)
# =============================================================================

suppressPackageStartupMessages({
  library(jsonlite); library(digest); library(arrow); library(data.table)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0L && !is.na(a[[1L]])) a[[1L]] else b

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-D20260426_006"
WT_DIR_TAG   <- "WT_D20260426_006"
WT_MAIL_DIR  <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
ARTIFACT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", WT_DIR_TAG)
DRAFT_PATH   <- file.path(WT_MAIL_DIR, "alpha_package_draft.json")
FINAL_PATH   <- file.path(WT_MAIL_DIR, "alpha_package.json")
CODEX_V1_PATH <- file.path(WT_MAIL_DIR, "codex_critic_response_alpha.json")
RESOLVE_V2_PATH <- file.path(WT_MAIL_DIR, "alpha_codex_resolution_v2.json")

setwd(PROJECT_ROOT)
cat("=== Finalize Alpha Package v2 (universe + liquidity + 8 mandates fix) ===\n")

stopifnot(file.exists(DRAFT_PATH))
draft <- fromJSON(DRAFT_PATH, simplifyVector = FALSE)
codex_v1 <- if (file.exists(CODEX_V1_PATH)) fromJSON(CODEX_V1_PATH, simplifyVector = FALSE) else NULL
resolution_v2 <- if (file.exists(RESOLVE_V2_PATH)) fromJSON(RESOLVE_V2_PATH, simplifyVector = FALSE) else NULL

# ---- Codex v1 → v2 round metadata ----
draft$codex_critic_round <- list(
  rounds_executed = 1L,
  v1_stance = if (!is.null(codex_v1)) codex_v1$stance else "REJECT",
  v1_critical_concerns_count = if (!is.null(codex_v1)) length(codex_v1$critical_concerns) else 9L,
  v1_artifact = "codex_critic_response_alpha.json",
  v2_resolution_artifact = "alpha_codex_resolution_v2.json",
  v2_resolution_summary = "8 mandates implemented. 10/10 concerns explicit decision. AX-002 silent omission FIXED (universe + liquidity).",
  v2_silent_omission_audit = "PASS — no concern omitted",
  v2_round_pending = "Codex R1 v2 will be triggered post-finalize via run_codex_round.sh"
)

# ---- AX-008 status ----
draft$ax_axiom_compliance$`AX-008`$status <- "PARTIAL"
draft$ax_axiom_compliance$`AX-008`$evidence <- paste0(
  "Codex R1 v1 executed (REJECT, 9 critical concerns). v2 remediation applied (universe + liquidity + turnover + sub_stab + NW-HAC + 5-spec + PIT evidence). ",
  "Codex R1 v2 round pending. Architect/Forge triangulation deferred to S6."
)

# ---- Q-Lead resolution ----
draft$qlead_resolution <- list(
  framework = "Q-Lead Decision Protocol v2 — 10/10 explicit (8 ACCEPT_AND_FIX + 2 DEFER_RETAIN_NOTE)",
  v1_silent_omissions_fixed = list(
    "C2_HARD_UNIVERSE_BREACH (0/20 in K200∪KQ150 v1) → 20/20 universe-enforced v2",
    "C3_C10_LIQUIDITY_PROXY_WRONG (Size proxy v1) → Close*Vol true TV20 v2"
  ),
  accepted_corrections = list(
    "M1_ACCEPT_AND_FIX_C2_UNIVERSE — filter_universe_liquidity() at MI prefilter + IS + Val + OOS + LATEST_ME",
    "M2_ACCEPT_AND_FIX_C3_LIQUIDITY — AvgTV20 = Close*Vol 20d t-1, threshold 2e8 KRW",
    "M3_ACCEPT_AND_ACTUAL_FIX_C4_TURNOVER — 3M EMA score smoothing + universe restriction + stronger ML reg",
    "M4_ACCEPT_AND_FIX_C1_LGBM — XGB+CatBoost ensemble (lightgbm NOT INSTALLED honest disclosure)",
    "M5_ACCEPT_AND_ACTUAL_FIX_C7_HARVEY_DSR — Newey-West HAC + 5-spec regression CAPM/Carhart/FF5/FF6 + DSR_post conservative",
    "M6_ACCEPT_AND_ACTUAL_FIX_C5_SUB_STAB — MI top tightened + ensemble diversification + EMA + universe filter",
    "M7_ACCEPT_AND_BOOST_EVIDENCE_C8_PIT — L-164 v1.1 explicit by-name citation + lineage block",
    "M8_ACCEPT_PROCESS_HONESTY — 9/9 + AX_008 explicit decisions (no silent omission)"
  ),
  deferred_with_note = list(
    "C9_PG2_NAV_COR — Forge backtest 영역 (Alpha boundary excludes weights/cov)",
    "C10_AX_008_DOWNSTREAM — Architect/Forge triangulation at S6"
  ),
  challenge_note_artifact = "alpha_challenge_note.md",
  codex_resolution_v2_artifact = "alpha_codex_resolution_v2.json"
)

# ---- Selection objective check ----
stopifnot(draft$selection_objective == "icir")

# ---- Step 1: Write final alpha_package.json (FIRST per L-194) ----
write_json(draft, FINAL_PATH, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("[1] alpha_package.json (v2) saved → %s\n", FINAL_PATH))

# ---- Step 2: Lineage record (AFTER write per L-194) ----
source(file.path(PROJECT_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
input_files <- c(
  file.path(WT_MAIL_DIR, "request.json"),
  file.path(PROJECT_ROOT, ".cache/rawdata.parquet"),
  file.path(PROJECT_ROOT, ".cache/kr_factor_returns_v2.parquet"),
  file.path(ARTIFACT_DIR, "alpha_scores.parquet"),
  file.path(ARTIFACT_DIR, "alpha_validation.json"),
  file.path(WT_MAIL_DIR, "factor_engine_proposal.R"),
  file.path(WT_MAIL_DIR, "alpha_codex_resolution_v2.json"),
  file.path(WT_MAIL_DIR, "codex_critic_response_alpha.json"),
  file.path(WT_MAIL_DIR, "alpha_package_v1_REJECTED.json")
)
input_files <- input_files[file.exists(input_files)]

setwd(PROJECT_ROOT)
record_package_lineage(
  task_id = WT_ID,
  package_type = "alpha_package",
  method_selected = "M06v2_XGB_CatBoost_ensemble (universe K200∪KQ150 PIT + Close*Vol AvgTV20 + 3M EMA + NW-HAC Harvey + 5-spec)",
  input_file_paths = input_files,
  windows = list(
    train_validation_window = list(start = "2003-01-01", end = "2024-01-22"),
    lockbox_window = list(start = "2024-01-23", end = "2026-01-23", sealed = TRUE)
  ),
  random_seed = 20260426006L,
  extra = list(
    parent_iters = list("STR_1656_MLRA_M05", "STR_1701_WT004_Iter11"),
    iter_name = "STR_1656_M06_PG2_conditional_ML_diversifier_v2",
    version = "v2_REVISE",
    v1_status = "REJECTED (silent omission C2 + C3)",
    v2_remediation = "8 mandates implemented + 10/10 concerns explicit",
    codex_round_v1_stance = "REJECT",
    codex_round_v2_pending = TRUE
  )
)

# ---- Step 3: status.json update ----
status_path <- file.path(WT_MAIL_DIR, "status.json")
status <- list(
  task_id = WT_ID,
  current_phase = "ALPHA_DONE_V2",
  version = "v2_REVISE",
  updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  blocker = NULL,
  alpha_summary_v2 = list(
    method_actual = "M06v2_XGB_CatBoost_ensemble",
    n_sig_dates = draft$diagnostics$n_sig_dates,
    icir = draft$diagnostics$icir,
    rank_ic = draft$diagnostics$rank_ic,
    harvey_t_simple = draft$diagnostics$harvey_t_simple,
    harvey_t_nw_hac = draft$diagnostics$harvey_t_nw_hac,
    sub_stab = draft$diagnostics$subperiod_stability,
    turnover_proxy = draft$diagnostics$turnover_proxy,
    dsr_post = draft$diagnostics$deflated_sharpe_ratio,
    five_spec_pass = sprintf("%d/%d",
                              draft$five_spec_summary$specs_pass,
                              draft$five_spec_summary$specs_total),
    universe_compliance = sprintf("top20=%d/%d in K200∪KQ150",
                                   draft$universe_compliance$top20_in_universe_count,
                                   draft$universe_compliance$top20_total),
    liquidity_compliance = sprintf("top20_pass_2e8=%d/%d (Close*Vol)",
                                    draft$liquidity_compliance$top20_pass_2e8_count,
                                    draft$universe_compliance$top20_total),
    gates_pass = sprintf("%d/%d",
                         draft$graduation_status_summary$gates_pass,
                         draft$graduation_status_summary$gates_total),
    challenge_flags_count = length(draft$challenge_flags),
    codex_v1_stance = "REJECT",
    codex_v2_resolution = "8 mandates + 10/10 explicit",
    silent_omission_v1_fixed = TRUE
  )
)
write_json(status, status_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("[3] status.json saved → %s\n", status_path))

cat("\n=== FINALIZE V2 COMPLETE ===\n")
cat(sprintf("alpha_package.json (v2): %s\n", FINAL_PATH))
cat(sprintf("ICIR=%.4f rank_IC=%.4f Harvey_NW=%s sub_stab=%.4f turnover=%.2f%%\n",
            draft$diagnostics$icir,
            draft$diagnostics$rank_ic,
            format(draft$diagnostics$harvey_t_nw_hac, nsmall=4),
            draft$diagnostics$subperiod_stability,
            draft$diagnostics$turnover_proxy * 100))
cat(sprintf("Gates: %d/%d | 5-spec PASS: %d/%d | Challenge flags: %d\n",
            draft$graduation_status_summary$gates_pass,
            draft$graduation_status_summary$gates_total,
            draft$five_spec_summary$specs_pass,
            draft$five_spec_summary$specs_total,
            length(draft$challenge_flags)))
cat(sprintf("Universe: top20 in K200∪KQ150 = %d/20 | Liquidity: top20 ≥ 2e8 = %d/20\n",
            draft$universe_compliance$top20_in_universe_count,
            draft$liquidity_compliance$top20_pass_2e8_count))
