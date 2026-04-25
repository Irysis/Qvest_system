#==============================================================================
# WT-D20260426_005 — Optimizer finalize (post-Codex R1 triage)
# Append codex_round + qlead_resolution metadata to optimization_package.json
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite)
})

WT_ID <- "WT-D20260426_005"
WT_DIR <- file.path("qepm/mailbox/worktask", WT_ID)
opt_path <- file.path(WT_DIR, "optimization_package.json")

opt_pkg <- fromJSON(opt_path, simplifyVector = FALSE)
codex_r1 <- fromJSON(file.path(WT_DIR, "codex_critic_response_optimizer.json"),
                       simplifyVector = FALSE)

opt_pkg$codex_round <- list(
  rounds_executed = 1L,
  codex_stance_r1 = codex_r1$stance,
  weakest_assumption = codex_r1$weakest_assumption,
  critical_concerns_count = length(codex_r1$critical_concerns %||% list()),
  triage_summary = "4 ACCEPT + 3 PARTIAL + 1 REBUTTAL = 8 total concerns",
  triage = list(
    ACCEPT = list(
      list(id = "C3_NO_OPTIMIZER_CHALLENGE_NOTE",
            severity = "HIGH",
            fix = "optimizer_challenge_note.md authored — R12 No Silent Override compliance"),
      list(id = "C2_RF_O11_CONFIDENCE_NOT_USED",
            severity = "MEDIUM",
            fix = "Honest disclosure: LinTilt+Kelly does not directly consume confidence_vector. MVO_Kelly_Overlay variant tested (netIR 0.604 < selected 0.644). RF-A1 mitigation: max_w 0.10 in CRISIS/CAUTION + 30% cash + DD Brake. Confidence-aware variant deferred to Iter 13 enhancement."),
      list(id = "C5_TASK_LEVEL_COVARIANCE_MISSING",
            severity = "MEDIUM",
            fix = "Iter 12 is Discovery WT inheriting alpha+risk from WT-D20260425_010. Optimizer applies Risk's lw_oracle / lw_constcor estimator class per-sig_date (not redefining method). Inherited covariance.parquet (cond=24) + pooled fallback (cond=100) both PSD-validated."),
      list(id = "C6_RF_O4_CONSTRAINT_SENSITIVITY",
            severity = "MEDIUM",
            fix = "Sensitivity from method_shopping log: λ=1.5 tilt → -9.6% IR, no Kelly → -17.7% IR, no overlay → +0.045 IR but +12pp MDD. Binding: weight_bound_upper, max_names_20, cash_overlay_30pct_crisis.")
    ),
    PARTIAL = list(
      list(id = "C1_DAILY_CVAR_DIRECT",
            severity = "HIGH",
            rationale = "Optimizer has only monthly Ret_1m. Daily CVaR computation requires daily KR returns (Factor DB / RAWDATA) — Forge's domain via pm_run(). Proxy 2.44% is QEPM convention (Risk handoff explicit). Selected method passes TO + CVaR-proxy caps; Forge daily verification is downstream gate."),
      list(id = "C4_PG2_TDC_SEQUENTIAL",
            severity = "HIGH",
            rationale = "Inherited from Risk handoff: STR_1656 ML model has no alpha trail; STR_1631 SYN_05 alpha vector not exposed. Cross-section Jaccard vs Iter 3 ancestor = 0.111 is best proxy. Portfolio-level TDC vs PG2 NAV requires NAV history — Forge backtest layer."),
      list(id = "C8_LIQUIDITY_PER_NAME",
            severity = "MEDIUM",
            rationale = "Liquidity filter (20d TV >= 2e8) enforced at Alpha agent (factor_specs[].neutralization = 'liquidity filter'). All 20 tickers + walk-forward universe pre-filtered. Optimizer inherits eligible universe; per-name TV evidence is structural property of alpha_scores.parquet.")
    ),
    REBUTTAL = list(
      list(id = "C7_BETA_DRIFT",
            severity = "MEDIUM",
            arguments = list(
              "Discovery WT scope (request.json wt_type='discovery') — beta-banding is Deployment WT concern.",
              "request.json has no explicit beta target; benchmark_definition only specifies regression baseline.",
              "Iter 12 inherits from Iter 5 pattern which deliberately omitted active beta target.",
              "Portfolio MKT exposure (20.5%) already documented at Risk layer (risk_summary.top_common_risks)."
            ),
            decision = "REBUTTAL_VALID. Beta hedging/banding is Forge + Governor admission concern.")
    )
  ),
  response_artifact = "codex_critic_response_optimizer.json",
  challenge_note_artifact = "optimizer_challenge_note.md"
)

# Add explicit AX-002 + AX-008 compliance statement
opt_pkg$ax_compliance_statement <- list(
  AX_002_process_honesty = list(
    status = "PASS",
    evidence = c(
      "optimizer_challenge_note.md authored with 8 concerns triaged",
      "Method shopping log full (10 candidates with metrics) preserved",
      "Selected method binding rule (only candidate passing both TO and CVaR caps) explicitly documented",
      "RF-O11 honest disclosure (confidence_vector not directly used by Linear Tilt) — not silently waived",
      "Discovery vs Deployment scope clarification (beta drift, daily CVaR, PG2 TDC deferred to Forge/Governor with named owners)"
    )
  ),
  AX_008_verification_triangulation = list(
    status = "PARTIAL",
    sources = list(
      optimizer_self = "PASS (10 candidates evaluated, hard constraints all green, infeasibility=null)",
      codex = "REVISE r1 → ACCEPT/PARTIAL/REBUTTAL r1 triage complete; r2 expected after this finalize",
      architect = "N/A (no infrastructure change)",
      forge = "TBD (backtest stage)"
    ),
    note = "AX-008 2-of-3 verification: Optimizer self-PASS + Codex post-triage = 2-of-3 minimum once R2 confirms. Forge backtest provides 3rd source at downstream stage."
  ),
  AX_001_v2_defense_conditional = list(
    status = "PASS",
    evidence = c(
      "Multi-sleeve structure inherited (Core 0.65 + Defense 0.35 + Cash overlay)",
      "Conditional cash policy 0/5/15/30% by regime (BULL/NORMAL/CAUTION/CRISIS)",
      "CRISIS small-sample shrink: max_w 0.10 enforced via pooled fallback Σ branch",
      "Cash 30% at as_of (CRISIS regime active)"
    )
  )
)

opt_pkg$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

write_json(opt_pkg, opt_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("[Optimizer Iter12 finalize] optimization_package.json updated with codex_round + ax_compliance_statement\n")

# Helper for null coalescence
`%||%` <- function(a, b) if (is.null(a)) b else a
