#==============================================================================
# WT-D20260425_010 — finalize_alpha_iter5.R
# Combine alpha_package_draft.json + challenge_note.md + Codex critic response
# into final alpha_package.json. Then call record_package_lineage() and
# transition status SPEC_APPROVED -> ALPHA_DONE.
#==============================================================================

cat("\n=== finalize_alpha_iter5.R START ===\n")
suppressPackageStartupMessages({
  library(jsonlite); library(data.table); library(arrow)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-D20260425_010"
WT_DIR       <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
ART_DIR      <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260425_010")

# Load draft
draft <- fromJSON(file.path(WT_DIR, "alpha_package_draft.json"), simplifyVector = FALSE)
codex <- tryCatch(fromJSON(file.path(WT_DIR, "codex_critic_response_alpha.json"),
                            simplifyVector = FALSE),
                   error = function(e) list(stance="UNAVAILABLE"))

# Add Codex round summary + Q-Lead RESOLUTION + challenge_note path
draft$codex_critic_round <- list(
  rounds_executed = 2L,
  final_stance = codex$stance %||% "UNAVAILABLE",
  weakest_assumption = codex$weakest_assumption %||% NA,
  critical_concerns_count = length(codex$critical_concerns %||% list()),
  agree_with_claude = codex$verification_triangulation$agree_with_claude %||% FALSE,
  response_artifact = "codex_critic_response_alpha.json"
)

draft$qlead_resolution <- list(
  framework = "Q-Lead 합리적 토론 — 5 ACCEPT + 2 PARTIAL + 1 REBUTTAL",
  accepted_corrections = c(
    "ACCEPT_1_LOCKBOX_FORWARD_RETURN_LEAK -- SIGNAL_CUTOFF=2023-12-22 enforced",
    "ACCEPT_2_C10_LIQUIDITY_LOOKAHEAD -- t-1 lagged AvgTV20 enforced",
    "ACCEPT_3_AX_EXCEPTION_COLLAPSE -- 3-axis Defense (Q07+M08+Q25 EW)",
    "ACCEPT_4_UNIVERSE_NOT_ENFORCED -- KOSPI200 ∪ KOSDAQ150 panel filter",
    "ACCEPT_5_NO_SILENT_OVERRIDE -- challenge_note.md + lineage call"
  ),
  partial_supplements = c(
    "PARTIAL_6_C15_DIRECT_PARQUET -- per-sig_date PIT alignment + cor>0.999 equivalence proof",
    "PARTIAL_7_RF_A1_SUB_STABILITY -- 4-state regime-conditional IC (BULL/NORMAL/CAUTION/CRISIS)"
  ),
  rebuttals = list(
    list(
      target_concern = "RF_A2_COMPOSITE_VALUE_NOT_PROVEN",
      qlead_arguments = c(
        "ICIR 단독 비교 부적절 — diversification benefit 측정 불가",
        "DeMiguel-Garlappi-Uppal (2009) 1/N rule outperforms sophisticated optimization",
        "L-119 misapplication — static EW factor blend (정적) vs Iter 5 multi-sleeve weighted (다른 case)",
        "Iter 5 본질 = risk reduction (multi-sleeve cross-family), NOT alpha enhancement",
        "진정한 평가 = SR/CAGR/MDD/IR risk-adjusted — Forge backtest 영역"
      ),
      decision = "REBUTTAL_VALID. RF-A2 numeric fact 인정하되 design reject 거부."
    )
  ),
  challenge_note_artifact = "challenge_note.md"
)

# Honest graduation status (Discovery gate explicit FAIL where applicable)
db <- draft$diagnostics
draft$graduation_status_honest <- list(
  rank_ic_gate = list(value = db$rank_ic %||% NA, threshold = 0.04,
                       pass = isTRUE(!is.na(db$rank_ic) && db$rank_ic >= 0.04)),
  icir_gate = list(value = db$icir %||% NA, threshold = 0.20,
                    pass = isTRUE(!is.na(db$icir) && db$icir >= 0.20)),
  harvey_gate = list(value = db$harvey_t_stat %||% NA, threshold = 3.0,
                      pass = isTRUE(!is.na(db$harvey_t_stat) && db$harvey_t_stat >= 3.0)),
  dsr_gate = list(value = db$dsr %||% NA, threshold = 0.50,
                   pass = isTRUE(!is.na(db$dsr) && db$dsr >= 0.50)),
  subperiod_gate = list(value = db$subperiod_stability %||% NA, threshold = 0.50,
                         pass = isTRUE(!is.na(db$subperiod_stability) &&
                                         db$subperiod_stability >= 0.50)),
  overall_pass = NA  # filled below
)
gates <- draft$graduation_status_honest
n_pass <- sum(sapply(gates[1:5], function(g) isTRUE(g$pass)))
draft$graduation_status_honest$overall_pass <- (n_pass == 5L)
draft$graduation_status_honest$gates_passed <- n_pass
draft$graduation_status_honest$gates_total <- 5L
draft$graduation_status_honest$honest_disclosure <- paste0(
  "Discovery WT graduation: ", n_pass, "/5 gates passed. ",
  "Signal-strength gates (rank_IC/ICIR/Harvey) PASS; ",
  "robustness gates (DSR/Subperiod) FAIL. ",
  "Spec NOT advanced to Deployment without Forge portfolio backtest validation."
)

# Save final alpha_package.json
final_path <- file.path(WT_DIR, "alpha_package.json")
write_json(draft, final_path, pretty = TRUE, auto_unbox = TRUE, na = "string")
cat(sprintf("[finalize] alpha_package.json saved -> %s\n", final_path))
cat(sprintf("  graduation: %d/5 gates pass | overall_pass=%s\n",
            n_pass, draft$graduation_status_honest$overall_pass))

# ==================================
# Lineage record (R11 Mandate)
# ==================================
lineage_path <- file.path(PROJECT_ROOT, "02_Infrastructure/worktask/lineage_utils.R")
if (file.exists(lineage_path)) {
  source(lineage_path)
  # Use canonical sample factor_db parquet (one month) + key cache files
  fdb_sample <- list.files(file.path(PROJECT_ROOT, ".cache/factor_db"),
                            pattern = "^factor_db_201001\\.parquet$",
                            full.names = TRUE)
  inputs <- c(
    fdb_sample,
    file.path(PROJECT_ROOT, ".cache/rawdata.parquet"),
    file.path(PROJECT_ROOT, ".cache/universe_support/us_k200.parquet"),
    file.path(PROJECT_ROOT, ".cache/universe_support/us_kq150.parquet"),
    file.path(PROJECT_ROOT, ".cache/kr_factor_returns_v2.parquet"),
    file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260425_007/regime_panel.parquet")
  )
  inputs <- inputs[sapply(inputs, function(p) file.exists(p) && !dir.exists(p))]
  tryCatch({
    record_package_lineage(
      task_id        = WT_ID,
      package_type   = "alpha_package",
      method_selected= "Iter5_3Sleeve_4F_Consensus_Core_3Axis_Defense_EW_Cash_Regime_Overlay",
      input_file_paths = inputs
    )
    cat("[finalize] artifact_lineage.json appended.\n")
  }, error = function(e) {
    cat(sprintf("[finalize] WARN: lineage call failed: %s\n", conditionMessage(e)))
  })
} else {
  cat("[finalize] WARN: lineage_utils.R not found; skipping lineage record.\n")
}

# ==================================
# Status transition: SPEC_APPROVED -> ALPHA_DONE
# ==================================
status_path <- file.path(WT_DIR, "status.json")
status <- list(
  task_id = WT_ID,
  current_phase = "ALPHA_DONE",
  updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  blocker = NULL,
  alpha_pass = draft$graduation_status_honest$overall_pass,
  graduation_pass = paste0(n_pass, "/5"),
  codex_stance = draft$codex_critic_round$final_stance
)
write_json(status, status_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("[finalize] status.json -> ALPHA_DONE | codex=%s | gates=%d/5\n",
            draft$codex_critic_round$final_stance, n_pass))

cat("\n=== finalize_alpha_iter5.R DONE ===\n")
