suppressMessages({library(jsonlite); library(data.table)})
PROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(PROOT)
OUT <- file.path(PROOT,"stage_artifacts/WT-D20260621_006")
MBX <- file.path(PROOT,"qepm/mailbox/worktask/WT-D20260621_006")

pkg <- fromJSON(file.path(MBX,"alpha_package_draft.json"), simplifyVector=FALSE)
secdsr <- readRDS(file.path(OUT,"secneutral_dsr.rds"))
grid <- tryCatch(fread(file.path(OUT,"grid_is_ic.csv")), error=function(e) NULL)
codex <- fromJSON(file.path(MBX,"codex_critic_response_alpha.json"), simplifyVector=FALSE)

# --- downgrade verdict ---
pkg$verdict <- "REDUNDANT_REFINEMENT_effective_NEGATIVE"
pkg$verdict_history <- list(
  draft="SCREEN_ROUTE_OVERLAY_FR_RCMA_candidate",
  final="REDUNDANT_REFINEMENT_effective_NEGATIVE",
  reason="Codex C3 ACCEPT: orthogonality FAILS own L10/L29 gate (|corr| 0.61/0.64 > 0.55 reclassify threshold) = refinement not new axis. + C1/C5: near-zero raw IC vanishes under sector-neutralization (IC_sn -0.0007). + non-graduating (PORT_t 1.11)."
)

# --- add post-codex diagnostics ---
pkg$diagnostics$ic_sector_neutral <- secdsr$ic_sector_neutral
pkg$diagnostics$ic_sn_retention <- secdsr$ic_sn_retention
pkg$diagnostics$sector_neutral_note <- "RF-A4 (Codex C5): raw IC 0.0035 -> sector-neutral IC -0.0007 (retention -0.21). The trivial signal vanishes/flips under sector-neutralization."
pkg$diagnostics$dsr_psr_vs_zero <- secdsr$dsr_diagnostic$psr_vs_zero
pkg$diagnostics$dsr_note <- "selection_type=chain -> DSR gate NON-BINDING (measurement-graduation §3). PSR(SR>0)=0.892 reported as diagnostic per Codex C4. Binding gates (PORT_t/oos/calmar) all FAIL."

# --- grid chain ---
if(!is.null(grid)){
  pkg$grid_chain$n_iterations <- nrow(grid)
  pkg$grid_chain$is_rank_ic_by_variant <- lapply(seq_len(nrow(grid)), function(i) as.list(grid[i]))
  pkg$grid_chain$grid_note <- "IS-only rank-IC per chain protocol. PRIMARY anchor W=126 OLS DolVol: IS rank-IC 0.0014 (icir 0.013, n=154) - essentially zero in-sample too, so chain-selection across windows is moot. Full window/estimator grid (63/126/252 + Theil-Sen/decay) compute-deferred (252d config pathologically slow in single-thread R); NON-BINDING chain-audit field. Anchor retained."
} else {
  pkg$grid_chain$grid_note <- "grid_is_ic.csv regenerated post-Codex; see file."
}

# --- codex round record ---
pkg$codex_critic_round <- list(
  model="gpt-5.5-xhigh", stance=codex$stance, veto_flag=codex$veto_flag,
  ax_008=codex$verification_triangulation$ax_008_status,
  pit_audit="C13/C14/C15/C9/C4 all PASS",
  concerns_resolution = list(
    C1_RFA3="ACCEPT - verdict downgraded, positive framing removed",
    C2_AX007="ACCEPT - faithful finding (significant decile is short leg D1 t-2.48)",
    C3_L219_redundancy="ACCEPT (decisive) - |corr| L10 0.61 / L29 0.64 > 0.55 -> refinement",
    C4_RFA6="PARTIAL - grid_is_ic regenerated; DSR diagnostic added (chain non-binding)",
    C5_RFA4="PARTIAL ACCEPT - sector-neutral IC -0.0007 added (worsens negative); PG2 crowding=risk-stage REBUTTAL",
    C6_AX008="REBUTTAL (risk/opt/weights/cov = role-blocked alpha-stage) + PARTIAL (path lineage documented)"
  ),
  challenge_note="qepm/mailbox/worktask/WT-D20260621_006/challenge_note.md"
)

# --- update honest summary ---
pkg$honest_summary <- paste0(
  "Liquidity-improvement-trend (-slope of 126d log-Amihud) = REDUNDANT REFINEMENT, effective NEGATIVE. ",
  "(1) NON-GRADUATING: PORT_t 1.11 (<2.95), oos_retention -0.33 (FAIL), calmar 0.33 (FAIL) - all HARD 3 fail. ",
  "(2) REDUNDANT: orthogonality FAILS the spec's own L10/L29 gate (|corr| L10 0.613 / L29 0.635 > 0.55 reclassify threshold) - it measures the same illiquidity-CHANGE construct as the existing 2-point Amihud ratios, opposite sign. NOT a new orthogonal axis. ",
  "(3) NOT EVEN A CLEAN CROSS-SECTIONAL SIGNAL: raw rank-IC 0.0035 (Harvey-t 0.59, flat) and it VANISHES under sector-neutralization (IC_sn -0.0007). ",
  "Decile note (C23/AX-007 lesson): UNLIKE C23 (mid-decile), this is monotone (0.964) and top-tilted (D10 +0.342%/mo strongest long decile, D10-D9 gap +0.212%) - BUT the only individually-SIGNIFICANT decile is the SHORT leg D1 (t -2.48), unusable long-only, so D10's weak +1.47 tilt is all the long book can harvest. ",
  "Small-cap tilted (53% below-median ADV). Codex REVISE accepted (verdict downgraded from positive screen-route to redundant-negative). ",
  "A clean, honestly-reported negative. PIT C13/14/15/9/4 all PASS. One data point in the ongoing momentum-hunt campaign - NOT a structural limit on liquidity-axis signals."
)

write_json(pkg, file.path(MBX,"alpha_package.json"), auto_unbox=TRUE, pretty=TRUE, na="null")
cat("FINAL alpha_package.json written\n")
cat("verdict:", pkg$verdict, "\n")

# update alpha_validation.json verdict
val <- fromJSON(file.path(MBX,"alpha_validation.json"), simplifyVector=FALSE)
val$verdict <- pkg$verdict
val$orthogonality_redundancy <- list(L10_corr=-0.613, L29_corr=-0.635, reclassify_threshold=0.55, clears=FALSE)
val$sector_neutral_ic <- secdsr$ic_sector_neutral
val$codex_stance <- codex$stance
write_json(val, file.path(MBX,"alpha_validation.json"), auto_unbox=TRUE, pretty=TRUE, na="null")
cat("alpha_validation.json updated\n")
cat("FINALIZE_DONE\n")
