#==============================================================================
# WT-D20260528_003 Hypothesis D — Telegram Brief
# v6.5 tg_agent_brief() single-entrypoint mandate
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ)
source("02_Infrastructure/telegram/telegram_notify.R")

WT_ID  <- "WT-D20260528_003"
HYP    <- "Hypothesis D — ML Daily-Informed Monthly Model (XGBoost)"
PKG    <- file.path("qepm/mailbox/worktask", WT_ID, "alpha_package_D_ML.json")
CV_RES <- "stage_artifacts/WT_D20260528_003_overnight_D_ML/cv_results.json"

if (!file.exists(PKG)) {
  cat("alpha_package_D_ML.json not found — using draft\n")
  PKG <- file.path("qepm/mailbox/worktask", WT_ID, "alpha_package_draft_D_ML.json")
}
pkg <- fromJSON(PKG, simplifyVector = FALSE)
cv  <- fromJSON(CV_RES, simplifyVector = FALSE)

# Diagnostics
om <- cv$overall_metrics
gc <- pkg$graduation_criteria_check

# Top 5 features by importance
top_feat <- pkg$top_features_by_importance[1:min(5, length(pkg$top_features_by_importance))]
top_feat_df <- data.table(
  Feature = sapply(top_feat, function(x) x$feature),
  Importance = sapply(top_feat, function(x) sprintf("%.3f", x$importance))
)

# Graduation table (2-col: Metric, Actual+PASS combined)
grad_df <- data.table(
  Metric = c("Rank IC (>=0.04)", "ICIR (>=0.20)", "Harvey-t HAC (>=3.0)",
             "Subperiod (>=0.5)", "DSR (>=0.5)", "AX-001 v2 (>=0.5)"),
  `Actual / PASS` = c(
    sprintf("%.4f %s", om$rank_ic_mean, if (gc$min_rank_ic$PASS) "PASS" else "FAIL"),
    sprintf("%.3f %s", om$icir, if (gc$min_icir$PASS) "PASS" else "FAIL"),
    sprintf("%.2f %s", om$t_hac_newey_west, if (gc$min_harvey_t_stat$PASS) "PASS" else "FAIL"),
    sprintf("%.2f %s", cv$subperiod_stability_fraction, if (gc$min_subperiod_stability$PASS) "PASS" else "FAIL"),
    sprintf("%.3f %s",
            if (!is.null(cv$dsr_simplified)) cv$dsr_simplified else 0.0,
            if (isTRUE(gc$min_deflated_sharpe_ratio$PASS)) "PASS" else "FAIL"),
    sprintf("%.3f %s", cv$ax001_v2$ratio_bad_over_normal, if (gc$ax001_v2$PASS) "PASS" else "FAIL")
  )
)

# Challenges (≤ 78 chars, 한글 위주)
chal_items <- c(
  "[HIGH] 디플레이티드 Sharpe Ratio fail 0.25 < 0.5 (multi-test 보정)",
  "[HIGH] Codex critic — 회전율 16.4 연배 > 6.0 cap (forge 단계 binding)",
  "[MED] Codex critic — PIT C13 / C15 카브아웃 binding L-code 권고",
  "[MED] Codex critic — 5-spec robustness matrix forge 단계 binding",
  "[MED] Codex critic — 트라이앵귤레이션 2/3 source 현재"
)

# Build sections
sections <- list(
  list(
    emoji = "📊",
    heading = "ML Model 결과 (Walk-Forward Purged CV)",
    type = "table",
    df = data.frame(grad_df),
    max_col_width = 14L,
    notes = c(
      sprintf("Folds: %d  / Optuna trials: %d  / Features: %d  / Panel rows: %d",
              cv$n_folds, cv$n_optuna_trials, cv$n_features, cv$panel_rows),
      sprintf("Lockbox: %s  / Embargo: %dd  / Min train: %dy",
              cv$lockbox_cutoff, cv$embargo_days, cv$min_train_years)
    )
  ),
  list(
    emoji = "🔬",
    heading = "Top 5 Features by Importance",
    type = "table",
    df = data.frame(top_feat_df),
    max_col_width = 30L
  ),
  list(
    emoji = "🚨",
    heading = "Challenge Flags",
    type = "bullet",
    items = chal_items
  )
)

verdict_summary <- if (gc$min_rank_ic$PASS && gc$min_icir$PASS && gc$min_harvey_t_stat$PASS) {
  "PROCEED"
} else if (gc$min_icir$PASS && cv$subperiod_stability_fraction >= 0.5) {
  "PARTIAL — ICIR/subperiod OK but Harvey/IC fail"
} else {
  "TERMINATE candidate"
}

footer <- sprintf("Verdict: %s  /  Next: Codex Round 5단계 (필수)", verdict_summary)

res <- tg_agent_brief(
  agent = "Alpha",
  title = sprintf("%s 완료 (D ML)", WT_ID),
  as_of = "2026-05-28",
  sections = sections,
  footer = footer,
  lock_scope = "Alpha_D_ML_WT-D20260528_003"
)

cat("\n=== Telegram brief sent ===\n")
print(res)
