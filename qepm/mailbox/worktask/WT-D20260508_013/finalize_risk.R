#==============================================================================
# WT-D20260508_013 — Risk Package Finalize
# Read draft → add Codex Round result + challenge_note ref → write final risk_package.json
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite); library(data.table)
})
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(ROOT)
WT <- "WT-D20260508_013"
MB_DIR <- file.path("qepm/mailbox/worktask", WT)

draft <- fromJSON(file.path(MB_DIR, "risk_package_draft.json"))

# Add codex round summary
codex_resp <- fromJSON(file.path(MB_DIR, "codex_critic_response_risk.json"))

# concerns may be list or data.frame depending on jsonlite reading
concerns_dt <- codex_resp$critical_concerns
if (is.data.frame(concerns_dt)) {
  high_count <- sum(concerns_dt$severity == "HIGH")
  concerns_n <- nrow(concerns_dt)
} else {
  high_count <- sum(sapply(concerns_dt, function(x) x[["severity"]] == "HIGH"))
  concerns_n <- length(concerns_dt)
}

draft$codex_critic_round_summary <- list(
  round = 1L,
  stance_received = codex_resp$stance,
  weakest_assumption = codex_resp$weakest_assumption,
  concerns_total = concerns_n,
  high_severity_count = high_count,
  classification = list(
    ACCEPT = c("C3_crisis_n5", "C6_ax001_v2_partial", "C7_artifact_paths", "C8_dates_freshness"),
    PARTIAL = c("C1_LW_degenerate_factor_overlay", "C2_long_short_HML_translation",
                "C4_BM_proxy_active_book_Forge", "C5_long_short_to_long_only_Forge"),
    REBUTTAL = c()
  ),
  high_severity_resolved = c("C1_factor_model_overlay", "C3_pooled_fallback"),
  high_severity_partial = c("C2_long_short_translation", "C4_BM_proxy_caveat",
                             "C5_long_only_form_Forge"),
  pit_critique_response = "Codex C2/C9/C11 PIT FAIL claims relate to regime engine layer (unified_regime_signal.parquet construction) — already PIT ZERO certified per L-442 v7.1. Risk agent consumes regime labels at month-end schedule.",
  silent_override = FALSE,
  escalate_to_q_lead = TRUE,
  escalate_rationale = "HIGH severity = 5 (>= 5 trigger), but no AX hard FAIL and no PIT C1 lockbox violation. Decision: escalate to Q-Lead for telemetry/Telegram brief; risk agent self-resolves within scope. Final admit decision pending Forge long-only form + Architect 3rd-source.",
  response_file = "qepm/mailbox/worktask/WT-D20260508_013/codex_critic_response_risk.json",
  challenge_note_file = "qepm/mailbox/worktask/WT-D20260508_013/challenge_note_risk.md",
  final_stance = "APPROVE_CONDITIONAL_DIVERSIFIER",
  final_stance_basis = "AX-001 v2 strict gate 2 FAIL (ratio CI [-126, 151] unstable); DEFENSE classification withdrawn. Σ provided in two paths (LW μI conservative / factor model B Ω B' + D non-degenerate cond=1055.4). 8-period stress: 6 feasible, 50% sleeve outperform vs BM. Slow-burn crisis (Inflation 2022 +30pp / VolShock 2018 +16pp / China 2015 +13pp) excellent. Flash crash (GFC -24pp / EuDebt -21pp / COVID -17pp) deferred to Forge long-only form re-test."
)

# Risk-final stance + recommendation
draft$risk_agent_final <- list(
  stance = "APPROVE_CONDITIONAL_DIVERSIFIER",
  role_recommendation = "DIVERSIFIER_NOT_DEFENSE",
  weight_band_pct = "5-15% incremental admission within Hybrid 70/15/15",
  rationale = "Diversification source qualified (cor BM 0.025 full + 0.121 recent60m + TDC 0.22 lower-5% + σ-reduction -9% at w=10%). Defense FAIL (CRISIS pooled HML -1.55%/m + ratio CI [-126, 151] unstable). Mechanism-consistent: chronic bad-news drift uplift (Atilgan-Bali-Demirtas-Gunaydin 2020 JFE Sec 4) but flash-crash protection absent.",
  next_agent = "optimizer-research",
  optimizer_mandate_summary = c(
    "Choose Σ method: LW μI (cond 1) / factor model (cond 1055) per estimation_quality preference",
    "Sleeve weight 5-15% admission to Hybrid 70/15/15 → 4th source (e.g. 65/15/15/5 / 60/15/10/15)",
    "Long-only top20 sleeve form realization for production",
    "Markowitz σ-reduction target ≥ -0.5%"
  ),
  forge_mandate_summary = c(
    "Long-only top20 sleeve crisis_alpha verification (Black Monday 2008 / VolMageddon 2018 / COVID 2020 / Inflation 2022)",
    "Core MDD attenuation vs Hybrid 70/15/15 baseline (current MDD -16.6%)",
    "Multi-sleeve Hybrid (70/15/15 + alpha 5-15%) backtest 2010~2026",
    "ΔSharpe ≥ +0.05 / ΔMDD ≤ -2pp",
    "Long-only sleeve CVaR / MDD re-measurement (long-short HML CVaR -16.93% / CDaR -71% are signal-side, NOT production-side)"
  ),
  architect_mandate_summary = c(
    "Independent VaR + Mom factor implementation reproduction (alpha-side)",
    "ICIR ±0.05 confirmation",
    "Independent factor model Σ verification (risk-side)",
    "AX-008 triangulation 3rd source"
  )
)

# Convert challenge_flags to plain list (jsonlite default rbinds to data.frame)
if (is.data.frame(draft$challenge_flags)) {
  draft$challenge_flags <- lapply(seq_len(nrow(draft$challenge_flags)), function(i) {
    as.list(draft$challenge_flags[i, ])
  })
}

# Save final
write_json(draft, file.path(MB_DIR, "risk_package.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[Finalize] risk_package.json saved.\n")

# Append lineage for final
tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = WT,
    package_type = "risk_package",
    method_selected = paste(draft$method_log$method_log_entries[draft$method_log$method_log_entries[, "selected"] == TRUE, "name"], collapse = ","),
    input_file_paths = c(file.path(MB_DIR, "alpha_package.json"),
                         file.path(MB_DIR, "codex_critic_response_risk.json"),
                         file.path(MB_DIR, "challenge_note_risk.md"),
                         file.path("stage_artifacts", WT, "alpha_scores.parquet"),
                         ".cache/rawdata.parquet",
                         ".cache/unified_regime_signal.parquet"),
    windows = list(
      list(name = "sigma_window", asof = "2026-05-08", days = 252L),
      list(name = "stress_window", from = "1997-07-01", to = "2026-04-30"),
      list(name = "ax001_v2_window", from = "2005-05-31", to = "2026-04-30")
    )
  )
  cat("[Finalize] lineage recorded.\n")
}, error = function(e) {
  cat("[warn] lineage failed:", conditionMessage(e), "\n")
})

# Update status.json
status <- fromJSON(file.path(MB_DIR, "status.json"))
status$current_phase <- "RISK_DONE"
status$next_agent <- "optimizer-research"
status$risk_completion_timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
status$risk_package_path <- file.path(MB_DIR, "risk_package.json")
status$risk_artifacts_dir <- "stage_artifacts/WT-D20260508_013/risk/"
status$risk_codex_round_1 <- list(
  stance = "REJECT",
  response = "qepm/mailbox/worktask/WT-D20260508_013/codex_critic_response_risk.json",
  challenge_note = "qepm/mailbox/worktask/WT-D20260508_013/challenge_note_risk.md"
)
status$risk_agent_final_stance <- "APPROVE_CONDITIONAL_DIVERSIFIER"
status$risk_agent_role_recommendation <- "DIVERSIFIER_NOT_DEFENSE"
status$risk_agent_assessment <- "Σ two paths (LW μI / factor model cond 1055). 8-period stress: feasible 6/8, outperform 3/6 (slow-burn crisis +12~+30pp / flash-crash -16~-24pp). Defense classification withdrawn (CRISIS pooled HML -1.55%/m + ratio CI [-126, 151] unstable). DIVERSIFIER honest: σ-reduction -9% at w=10%, TDC 0.22, cor 0.025 (full)."

write_json(status, file.path(MB_DIR, "status.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[Finalize] status.json updated.\n")
