#==============================================================================
# WT-D20260508_005 — Step 6: Finalize alpha_package.json (post-Codex)
#
# Incorporates remediation from c13_audit / c15_infeasibility / DSR N=17/27 /
# long-only top-20 / universe v2 / rationalization rephrase.
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(digest)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260508_005"
OUT  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_005")
MBOX <- file.path(PROJ, "qepm/mailbox/worktask", WT_ID)

# Read draft + remediation
draft <- read_json(file.path(MBOX, "alpha_package_draft.json"), simplifyVector = FALSE)
remed <- read_json(file.path(OUT, "codex_remediation_aggregate.json"), simplifyVector = FALSE)
codex_resp <- read_json(file.path(MBOX, "codex_critic_response_alpha.json"), simplifyVector = FALSE)

# ---- Apply Codex remediation patches ----

# Patch (1) Update factor_specs neutralization framing (R4 rationalization → acknowledgment)
draft$factor_specs[[1]]$neutralization <- "raw + sector-neutral variant tested; primary = raw because sector-neutral IC ~0.008 vs raw 0.019 is RF-A4 active (only 42% IC retention) — SIGNAL CARRIES SECTOR-LEVEL MACRO TILT COMPONENT, not pure cross-section stock selection. Acknowledged in challenge_flags."

# Patch (2) Update factor_specs candidates_tried (12 → 17 to match method_shopping_log)
draft$factor_specs[[1]]$candidates_tried_total <- 17L

# Patch (3) Update orthogonality notes (rephrase "naturally")
# (orthogonality_vs_hybrid.json embedded in diagnostics) — already factual

# Patch (4) Add c13_audit + c15_infeasibility refs
draft$diagnostics$pit_c13_status <- "PARTIAL_REBUTTAL — new factor not in Factor DB; sign inferred via expanding |IC| (PIT-safe). Post-burnin (2014-04+) sign stable at -1 for 145+ consecutive months. EQUIVALENT_DYNAMIC_PIT_SAFE per c13_audit.json. Method conceptually compliant with C13 intent (no look-ahead, sign by data not analyst)."
draft$diagnostics$pit_c15_status <- "ACCEPT_WITH_INFEASIBILITY_REPORT — c15_infeasibility_report.json written (Charter v1.4 §10 documented exception). New factor not in Factor DB → load_month_factors() not applicable. PIT-safety established via WT_004 inherited audited pipeline + WT_005 lag verification."

# Patch (5) Update universe_v2_diag with actual run results
draft$diagnostics$universe_v2_diag <- list(
  l227_trigger = "ICIR_1M 0.183 < 0.20 (graduation threshold)",
  v1_default_top342 = list(
    icir_1m = 0.183, ic_1m = 0.0193, icir_12m = 0.310, n_periods = 160, avg_n = 334),
  v2_top500_freefloat = list(
    icir_1m = 0.184, ic_1m = 0.0196, icir_12m = 0.347, n_periods = 160, avg_n = 305),
  delta_1m_icir = 0.001,
  delta_12m_icir = 0.037,
  conclusion = "v2 marginally better at 1M (+0.001 ICIR negligible); v2 +0.037 at 12M (modest improvement). Universe restriction is NOT the binding constraint at 1M. 12M shows modest mid-cap signal."
)

# Patch (6) Update DSR with N=17/27 recompute
draft$diagnostics$deflated_sharpe_ratio_blp_strict <- 6.973  # N=12 original retained
draft$diagnostics$deflated_sharpe_ratio_blp_n17 <- round(remed$c5_dsr_recompute$n_trials_options$n17_codex_fix$z_analytical, 3)
draft$diagnostics$deflated_sharpe_ratio_blp_n27_conservative <- round(remed$c5_dsr_recompute$n_trials_options$n27_conservative$z_analytical, 3)
draft$diagnostics$deflated_sharpe_ratio_method <- "Bailey-Lopez de Prado (2014) strict; recomputed at N=12/17/27 trials (Codex C5). All three N values PASS strict z>=0.5 threshold."

# Patch (7) Add long-only top-20 informational
draft$diagnostics$long_only_top20_informational <- list(
  sr_gross_annual = round(remed$c6_long_only_top20$sr_gross, 3),
  sr_net_15bps = round(remed$c6_long_only_top20$sr_net_after_15bps, 3),
  monthly_turnover = round(remed$c6_long_only_top20$monthly_turnover_proxy, 3),
  annual_turnover_pct = round(remed$c6_long_only_top20$annual_turnover_pct, 1),
  active_return_pct_yr_vs_bm = round(remed$c6_long_only_top20$active_return_pct_yr, 2),
  ir_vs_bm = round(remed$c6_long_only_top20$information_ratio_vs_bm, 3),
  feasibility_status = remed$c6_long_only_top20$feasibility_status,
  note = "Implementable form per max_names=20 mandate (signal feasibility check). Full backtest = Forge agent's role. Long-only profile shows positive but weak performance (IR 0.19 vs BM)."
)

# Patch (8) Replace challenge_flags with rephrased + Codex remediation flags
new_flags <- c(
  unlist(draft$challenge_flags),
  "CODEX_C2_PARTIAL_REBUTTAL: sign alignment is data-driven (expanding |IC|), not manual flip; post-burnin (2014-04+) sign stable at -1 for 145+ months. EQUIVALENT_DYNAMIC_PIT_SAFE per c13_audit.json.",
  "CODEX_C3_ACCEPT: c15_infeasibility_report.json written for Factor DB bypass (new factor); Charter v1.4 §10 documented exception with PIT-safety evidence.",
  "CODEX_C5_ACCEPT_DSR_RECOMPUTE: N=17 z=6.81, N=27 z=6.61 (analytical); all > 0.5 strict graduation; bootstrap N=17 z=1.93, N=27 z=1.59 (fat-tail robust).",
  "CODEX_C6_PARTIAL_LONG_ONLY: top-20 SR_gross=0.486 / SR_net=0.479 / IR_vs_BM=0.191 / TO_yr=60% / cost_drag=0.18%/yr — WEAK_LONG_ONLY_PROFILE (informational, full backtest = Forge).",
  "UNIVERSE_V2_RUN: KR_TOP500_FREEFLOAT ICIR 0.184 vs default 0.183 (delta 0.001 negligible at 1M); 12M delta +0.037 modest. Universe not binding at 1M.",
  "RATIONALIZATION_AUDIT_PASS: 0 hits for 미미/관행적/실무적/보수적이면/대부분 결과 동일/이미 반영 in finalized fields."
)
draft$challenge_flags <- as.list(new_flags)

# Patch (9) Update graduation_summary with Codex disposition reference
draft$graduation_summary$codex_critic_round_summary <- list(
  stance = "REJECT",
  veto_flag = FALSE,
  concerns_total = 7,
  concerns_high = 4,
  concerns_medium = 3,
  agent_disposition = list(
    accept = 4,
    partial = 2,
    partial_rebuttal = 1
  ),
  rationalization_red_flags_audit = list(
    accept_rephrased = 3,
    accept_run = 1,
    keep_factual = 1
  ),
  q_lead_escalate_triggered = FALSE,
  challenge_note_ref = "qepm/mailbox/worktask/WT-D20260508_005/challenge_note.md",
  codex_response_ref = "qepm/mailbox/worktask/WT-D20260508_005/codex_critic_response_alpha.json"
)

# Patch (10) Update method_shopping_summary candidate count
draft$method_shopping_summary$candidates_tried <- 17L

# Patch (11) Add codex_critic_status (final block)
draft$codex_critic_status <- list(
  stance = "REJECT",
  veto_flag = FALSE,
  response_file = "codex_critic_response_alpha.json",
  challenge_note_file = "challenge_note.md",
  concerns_total = 7,
  concerns_high = 4,
  concerns_medium = 3,
  accept_count = 4,
  partial_count = 2,
  rebuttal_count = 1,
  rationalization_red_flags_addressed = 5,
  rationalization_phrases_corrected = 3,
  rationalization_phrases_kept_factual = 1,
  rationalization_phrases_run_diagnostics = 1,
  q_lead_escalate_recommended = FALSE,
  q_lead_escalate_trigger_status = "NOT_TRIGGERED — HIGH<5, no AX hard FAIL, no PIT C1 violation, mixed disposition (not all rebuttal)"
)

# Patch (12) Update graduation_summary.rationale with full disposition
draft$graduation_summary$rationale <- paste0(
  "Single-factor KR_TermSpread β alpha at 1M horizon misses graduation criteria: ",
  "ICIR=0.183 < 0.20, Harvey-NW=2.14 < 3.0, subperiod strict 1/3 < 2. ",
  "PASSES: subperiod sign 3/3, DSR analytical N=12/17/27 all z>6.6, ",
  "DSR bootstrap (fat-tail robust) z=1.59~1.93, orthogonality vs Hybrid max |cor|=0.137. ",
  "12M ICIR=0.310 stronger but Harvey-NW=1.90 still <3.0. ",
  "Long-only top-20 SR_net=0.479 / IR=0.19 vs BM = WEAK_LONG_ONLY_PROFILE. ",
  "Improvement over WT_004 composite ICIR 0.110 → 0.183 resolves RF-A2 dilution thesis ",
  "(single-factor > composite by +0.073 ICIR). RF-A4 active: sector-neutral retention 0.42 ",
  "→ signal carries sector-mediated macro tilt component. ",
  "Codex Critic Round: REJECT (4 HIGH + 3 MEDIUM concerns), agent disposition: 4 ACCEPT + 2 PARTIAL + 1 REBUTTAL ",
  "+ all 5 rationalization flags addressed. challenge_note.md written. AX-008 N/A for archived_discovery."
)

# ---- Write final alpha_package.json ----
final_path <- file.path(MBOX, "alpha_package.json")
write_json(draft, final_path, auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
cat(sprintf("[06] alpha_package.json (final) written → %s\n", final_path))

# ---- Update lineage ----
source(file.path(PROJ, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = WT_ID,
  package_type = "alpha_package",
  method_selected = "single-factor KR_TermSpread β + EMA3 sign-aligned (post-Codex finalized)",
  input_file_paths = c(
    file.path(PROJ, "stage_artifacts/WT_D20260508_004/macro_betas_monthly.parquet"),
    file.path(PROJ, "stage_artifacts/WT_D20260508_004/panel_monthly.parquet"),
    file.path(PROJ, "stage_artifacts/WT_D20260508_004/macro_shocks_monthly.parquet"),
    file.path(PROJ, ".cache/ecos_bond_rates.parquet"),
    file.path(PROJ, ".cache/rawdata.parquet"),
    file.path(PROJ, "qepm/mailbox/worktask/WT-D20260508_005/codex_critic_response_alpha.json"),
    file.path(PROJ, "qepm/mailbox/worktask/WT-D20260508_005/challenge_note.md")
  )
)

# ---- Update status.json ----
status_new <- list(
  task_id = WT_ID,
  current_phase = "ALPHA_DONE_REJECT_GRADUATION",
  graduation_status = "REJECT_GRADUATION",
  classification = "ARCHIVED_DISCOVERY",
  updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  blocker = NULL,
  codex_critic_round = "completed_REJECT_4ACCEPT_2PARTIAL_1REBUTTAL",
  next_action = "ARCHIVE — no Risk Agent spawn (graduation REJECT). Inheritance value: composite dilution thesis confirmed, 12M long-horizon variant for Iter 9 family pivot, sector-mediated reframe option."
)
write_json(status_new, file.path(MBOX, "status.json"),
           auto_unbox = TRUE, pretty = TRUE)

# ---- Update governance_log ----
gov_log <- read_json(file.path(MBOX, "governance_log.json"), simplifyVector = FALSE)
gov_log$events <- c(gov_log$events, list(
  list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    agent = "alpha-research",
    action = "ALPHA_DONE_REJECT_GRADUATION",
    summary = "Single-factor KR_TermSpread β alpha REJECT_GRADUATION at 1M (ICIR 0.183<0.20, Harvey-NW 2.14<3.0). Sign 3/3 + DSR N=27 z=6.61 + Orthogonality |cor|<0.14 + 12M ICIR 0.310 stronger but Harvey 1.90<3. Codex REJECT (7 concerns) → 4 ACCEPT + 2 PARTIAL + 1 REBUTTAL. challenge_note.md written. ARCHIVED_DISCOVERY for Iter 9 inheritance."
  )
))
write_json(gov_log, file.path(MBOX, "governance_log.json"),
           auto_unbox = TRUE, pretty = TRUE)

cat("[06] status.json + governance_log.json updated\n")
cat("[06] DONE\n")
