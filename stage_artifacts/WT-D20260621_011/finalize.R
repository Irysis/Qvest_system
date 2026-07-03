# WT-D20260621_011 — finalize alpha_package.json (post-Codex REVISE) + lineage
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT-D20260621_011")
MBX  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260621_011")

pkg <- fromJSON(file.path(MBX,"alpha_package_draft.json"), simplifyVector=FALSE)
RM  <- readRDS(file.path(OUT,"revise_metrics.rds"))

# --- C13 correction: score is NOT always >=0; 1+lambda*footprint can be negative ---
pkg$pit_handling$checks <- "C1 (xs zscore per month, IS-only grid select), C2/C5 (score uses m-1 observables, forward return from m+1), C10 (liq adv t-1 21d), C13 (CORRECTED: score = exp(-age/tau)*(1+lambda*footprint); decay>0 always but (1+lambda*footprint) can be <0 when footprint<-1/lambda -> 6.2% of scores negative. NO NEGATE/FLIP applied; score is direction-aligned by construction (higher=fresher/higher-footprint). Earlier 'score>=0 always' claim was WRONG and is retracted.), C14/C15 (RAWDATA+membership carve-out per spec pit_notes C15: price+membership panel are raw, not Factor DB -> load_month_factors not required; documented in artifact_lineage)."

# add Codex-requested diagnostics
pkg$diagnostics$sector_neutral_pt_nw      <- round(RM$sn_pt,3)
pkg$diagnostics$sector_neutral_net_sr     <- round(RM$sn_sr,3)
pkg$diagnostics$sector_neutral_note       <- "within-month sector-demeaned score; pt still negative -> not a sector-composition artifact (RF-A4 closed)."
pkg$diagnostics$held_top25_illiquid_frac  <- round(RM$illiq_frac,3)
pkg$diagnostics$rf_a5_illiquidity_note    <- "0.024 < 0.5 threshold -> NOT an illiquidity artifact (RF-A5 PASS)."
pkg$diagnostics$recent_36m_pt_nw          <- round(RM$recent_pt,3)
pkg$diagnostics$rf_a3_note                <- "recent-36m pt=-1.38 is WORSE than full -0.885 -> no recent-period overfit (RF-A3 not triggered); consistent with index-effect arbitraged-away over time."
pkg$diagnostics$decile_monotonicity_spearman <- round(RM$monotonicity,3)
pkg$diagnostics$decile_monotonicity_note  <- "Spearman(decile, mean_active)=-0.248 -> NEGATIVE monotonicity (higher score=lower return), confirming top-concentration inversion."
pkg$diagnostics$alpha_scores_n_dates      <- RM$n_score_dates
pkg$diagnostics$alpha_scores_negative_frac<- round(RM$neg_frac,4)

# selection_objective honesty (Codex C3): clarify argmax-of-negatives = conservative
pkg$selection_objective <- "subperiod_stability"
pkg$selection_objective_note <- "Grid select used argmax(portfolio_alpha_t) ONLY to pick the LEAST-negative PIT-valid config (best-case). Since all 72 PIT-valid configs are negative, this makes the NEGATIVE verdict conservative (best case still fails). selection_objective metric for any future positive use = subperiod_stability. DSR multiple-testing inflation is moot for a negative finding (it would only further weaken a positive)."

# AX-008 / triangulation note (Codex C2)
pkg$ax_008_note <- "AX-008 verification triangulation (forge+codex+architect, 2/3) applies at GRADUATION/admission. This is an alpha-stage NEGATIVE finding NOT seeking admission -> risk/optimization packages legitimately absent. Codex critic round completed (REVISE->addressed). Forge/architect not invoked (no graduation pursued). artifact_lineage.json added."

# codex round record
pkg$codex_critic <- list(
  stance="REVISE", veto_flag=FALSE, model="gpt-5.5",
  response_file="qepm/mailbox/worktask/WT-D20260621_011/codex_critic_response_alpha.json",
  resolution="See challenge_note.md. C1(alpha_scores full panel) ACCEPT+fixed; C4/C13(score>=0 claim) ACCEPT+retracted; C5/RF-A4-A5(sector-neutral+illiq+recent) ACCEPT+computed (all confirm negative); C2/AX-008 PARTIAL(lineage added, full-triangulation N/A to negative alpha-stage); C3/RF-A6(selection) REBUTTAL(argmax-of-negatives=conservative); C15 REBUTTAL(spec-granted carve-out); C6/AX-007 ACCEPTED-as-labeled(negative finding).")

write_json(pkg, file.path(MBX,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, na="null")
cat("WROTE alpha_package.json (finalized)\n")

# lineage
src <- "02_Infrastructure/worktask/lineage_utils.R"
if(file.exists(file.path(ROOT,src))){
  tryCatch({
    source(file.path(ROOT,src))
    record_package_lineage(task_id="WT-D20260621_011", package_type="alpha_package",
      method_selected="IndexInclusion freshness-decay x passive-footprint (A_lag=1, A_max=9, tau=2, lambda=0.5) — NEGATIVE_VALIDATED",
      input_file_paths=c(".cache/universe_support/us_k200.parquet",".cache/universe_support/us_kq150.parquet",
                         ".cache/RAWDATA.parquet",".cache/benchmark.parquet"))
    cat("lineage recorded\n")
  }, error=function(e) cat("lineage WARN:", conditionMessage(e),"\n"))
} else cat("lineage_utils.R not found — skipped\n")
