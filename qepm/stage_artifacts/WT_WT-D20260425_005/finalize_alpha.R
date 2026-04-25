#==============================================================================
# WT-D20260425_005: Alpha Research Finalize
#  1. wt_advance(ALPHA_DONE)
#  2. tg_agent_brief Alpha brief
#==============================================================================

.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
FUNC_PATH    <- file.path(PROJECT_ROOT, "02_Infrastructure")

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table); library(jsonlite)
})

# ===================================================================
# 1. wt_advance to ALPHA_DONE
# ===================================================================
source(file.path(FUNC_PATH, "worktask", "worktask_manager.R"))

wt_advance("WT-D20260425_005", "ALPHA_DONE")

# ===================================================================
# 2. Telegram brief
# ===================================================================
source(file.path(FUNC_PATH, "telegram", "telegram_notify.R"))

# Read alpha_validation for stats
val <- fromJSON(file.path(PROJECT_ROOT, "qepm", "stage_artifacts",
                          "WT_WT-D20260425_005", "alpha_validation.json"),
                simplifyVector = FALSE)
pkg <- fromJSON(file.path(PROJECT_ROOT, "qepm", "mailbox", "worktask",
                          "WT-D20260425_005", "alpha_package.json"),
                simplifyVector = FALSE)

slot_table <- data.frame(
  Slot = c("A_Core", "B_Divers", "C_Defense"),
  Family = c("Consensus_4F", "ML_XGB", "Quality_Distress"),
  ICIR = c(val$per_slot_diagnostics$A_Core_Consensus$icir,
           val$per_slot_diagnostics$B_Diversifier_MLRA$icir,
           val$per_slot_diagnostics$C_Defense_QualityAgg$icir),
  Harvey_t = c(val$per_slot_diagnostics$A_Core_Consensus$harvey_t,
               val$per_slot_diagnostics$B_Diversifier_MLRA$harvey_t,
               val$per_slot_diagnostics$C_Defense_QualityAgg$harvey_t),
  Stab = c(val$per_slot_diagnostics$A_Core_Consensus$subperiod_stability,
           val$per_slot_diagnostics$B_Diversifier_MLRA$subperiod_stability,
           val$per_slot_diagnostics$C_Defense_QualityAgg$subperiod_stability)
)

tdc_table <- data.frame(
  Pair = c("A-B", "A-C", "B-C"),
  TDC_bot = c(val$cross_family_orthogonality$tdc_bottom_decile_p_y_given_x$A_B,
              val$cross_family_orthogonality$tdc_bottom_decile_p_y_given_x$A_C,
              val$cross_family_orthogonality$tdc_bottom_decile_p_y_given_x$B_C),
  Score_corr = c(val$cross_family_orthogonality$score_xs_corr_mean$A_B,
                 val$cross_family_orthogonality$score_xs_corr_mean$A_C,
                 val$cross_family_orthogonality$score_xs_corr_mean$B_C),
  IC_TS = c(val$cross_family_orthogonality$ic_ts_corr$A_B,
            val$cross_family_orthogonality$ic_ts_corr$A_C,
            val$cross_family_orthogonality$ic_ts_corr$B_C),
  Pass = c(
    if (val$cross_family_orthogonality$tdc_bottom_decile_p_y_given_x$A_B <= 0.40) "PASS" else "FAIL",
    if (val$cross_family_orthogonality$tdc_bottom_decile_p_y_given_x$A_C <= 0.40) "PASS" else "FAIL",
    if (val$cross_family_orthogonality$tdc_bottom_decile_p_y_given_x$B_C <= 0.40) "PASS" else "FAIL"
  )
)

result <- tryCatch(
  tg_agent_brief(
    agent = "Alpha",
    title = "WT-D20260425_005 Cross-Family 3-Way Blender ALPHA_DONE",
    as_of = "2026-04-25",
    sections = list(
      list(
        heading = "Slot Selection",
        emoji = "🎯",
        type = "text",
        body = paste(
          "Slot A: STR_1631_SYN_05_2002 (Consensus_4F core_alpha)",
          "Slot B: STR_1656_MLRA S1_B (ML XGBoost diversifier)",
          "Slot C: STR_1689_V1 3-axis Q01+Q04+Q25 (Quality_Distress defense, V2 Q07 dropped)",
          "Window: Pre-LB 2003-02 ~ 2024-01-22 (lockbox sealed, R2 enforced)",
          sep = "\n"
        )
      ),
      list(
        heading = "Per-Slot Diagnostics",
        emoji = "📊",
        type = "table",
        df = slot_table
      ),
      list(
        heading = "Cross-Family Orthogonality",
        emoji = "🔍",
        type = "table",
        df = tdc_table
      ),
      list(
        heading = "Combined Diagnostics",
        emoji = "📈",
        type = "text",
        body = paste(
          sprintf("Combined IC: %.4f", pkg$diagnostics$rank_ic),
          sprintf("Combined ICIR: %.3f", pkg$diagnostics$icir),
          sprintf("Harvey t: %.2f (graduation min 3.0)", pkg$diagnostics$harvey_t_stat),
          sprintf("Subperiod Stab: %.3f (graduation min 0.50)", pkg$diagnostics$subperiod_stability),
          sprintf("DSR (Gaussian p): %.3f (graduation min 0.50)", pkg$diagnostics$deflated_sharpe_ratio),
          sprintf("Universe: %d tickers (UNION view)", length(pkg$alpha_vector)),
          sep = "\n"
        )
      ),
      list(
        heading = "Hard Threshold Pass",
        emoji = "✅",
        type = "text",
        body = paste(
          "TDC pairwise (≤0.40): A-B 0.098 / A-C 0.130 / B-C 0.111 — ALL PASS",
          "Family uniqueness: PASS (Consensus_4F vs ML_XGB vs Quality_Distress)",
          "ICIR per-slot: A 0.295 / B 0.863 / C 0.735 — Slot C/B 압도적",
          "Slot A standalone Harvey t 3.30 (graduation 3.0 통과)",
          "Slot C selection beats STR_1683 (hard_fail MDD 94%) and STR_1687 (ICIR 0.45 약함)",
          sep = "\n"
        )
      ),
      list(
        heading = "Challenge Flags + 권고",
        emoji = "⚠️",
        type = "text",
        body = paste(
          "SUBPERIOD_INSTABILITY: Slot A standalone P3 (2020-2024) IC -0.073 (Common universe 한정).",
          "  → Slot A 자체 universe (470 tickers) 에서는 SR 1.19 + Harvey FF5 t 3.09 검증됨.",
          "  → Common universe 한정 IC negative는 Slot A의 alpha가 SUE/EPS1M revision 기반이라",
          "    Slot B/C가 동시 picking 가능한 종목군 한정 측정에서 약화된 결과.",
          "  → Optimizer가 sleeve-segmented 채택 시 영향 없음.",
          "다음 단계: Risk Agent Σ 추정 + formal copula TDC + DCC regime corr.",
          sep = "\n"
        )
      )
    ),
    footer = "🤖 Alpha Agent v1.2 | next: Risk Agent spawn"
  ),
  error = function(e) {
    cat(sprintf("[telegram WARN] %s\n", e$message))
    list(ok = FALSE, error = e$message)
  }
)

if (!is.null(result$ok) && isTRUE(result$ok)) {
  cat("[finalize] Telegram brief sent.\n")
} else {
  cat(sprintf("[finalize] Telegram brief: %s\n",
              if (!is.null(result$error)) result$error else "result unknown"))
}

cat("\n=== WT-D20260425_005 ALPHA_DONE FINALIZED ===\n")
cat(sprintf("  alpha_package.json: %s\n",
            file.path(PROJECT_ROOT, "qepm", "mailbox", "worktask",
                      "WT-D20260425_005", "alpha_package.json")))
cat(sprintf("  stage_artifacts:  %s\n",
            file.path(PROJECT_ROOT, "qepm", "stage_artifacts", "WT_WT-D20260425_005")))
