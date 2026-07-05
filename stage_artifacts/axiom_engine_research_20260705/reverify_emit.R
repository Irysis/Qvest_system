# reverify_emit.R — Phase 1 re-verification of the crossfamily regime-cond composite ledger emit.
# dry_run = TRUE (idempotent; does NOT overwrite the on-disk consumed ledger). ASCII-only.
suppressWarnings(suppressMessages({
  library(data.table); try(setDTthreads(1), silent = TRUE)
  library(jsonlite)
}))
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
root <- gsub("\\\\", "/", root)
Sys.setenv(CLAUDE_PROJECT_DIR = root)
source(file.path(root, "02_Infrastructure", "axiom", "lcode_emit.R"), local = TRUE)

# On-disk values from research_result.json (verified, canonical_screen, backtested-tier).
r <- emit_lcode(
  mode = "qepm_legacy",
  strategy_id = "axeng_crossfamily_regimecond_composite",
  grade = "F",
  metric_type = "canonical_screen",
  l_code = "L-QPM-20260705_105130",
  construction_type = "cross_family_regime_conditional_composite",
  selection_type = "chain",
  portfolio_alpha_t = 0.8385,
  oos_retention = -0.5532,
  oos_months = 159,
  mechanism_hypothesis = "t-1 regime expanding-window conditional-IC family weighting attempts to bypass post-2017 decay regimes",
  falsification_attempts = list(
    list(test = "static regime-unconditional ICW baseline (paired NW-t)", result = "weakened",
         effect_retained = 0.5),
    list(test = "static equal-weight baseline (paired NW-t)", result = "weakened",
         effect_retained = 0.3),
    list(test = "lag1 concurrent-leak stress", result = "survived", effect_retained = 1),
    list(test = "post-2017 subperiod decay wall", result = "falsified", effect_retained = 0)
  ),
  lesson_text = "cross-family regime-conditional composite canonical FAIL; regime-conditional mechanism lifts vs static but paired NW-t insignificant; post-2017 decay wall not breached.",
  project_root = root,
  dry_run = TRUE
)
cat(sprintf("\nEMIT_CALLABLE:%s  l_code=%s  grade=%s  metric_type=%s  port_t=%s  oos_ret=%s\n",
            !is.null(r), r$l_code %||% "NA", r$grade %||% "NA",
            r$metric_type %||% "NA", r$portfolio_alpha_t %||% "NA",
            r$oos_retention %||% "NA"))
# confirm on-disk file exists and matches id (idempotency evidence)
p <- file.path(root, "stage_artifacts", "l_code", "qepm_legacy",
               "l_code_axeng_crossfamily_regimecond_composite.json")
cat(sprintf("ON_DISK_EXISTS:%s\n", file.exists(p)))
if (file.exists(p)) {
  d <- fromJSON(p, simplifyVector = FALSE)
  cat(sprintf("ON_DISK_ID:%s  MATCH:%s\n", d$l_code, identical(d$l_code, "L-QPM-20260705_105130")))
}
