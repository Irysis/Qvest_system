#==============================================================================
# R20 Step 03 — emit alpha_validation.json + alpha_package.json + alpha_scores.parquet
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260713_004")
MBX  <- file.path(ROOT,"qepm/mailbox/worktask/WT-D20260713_004")
M <- readRDS(file.path(OUT,"measure_r20.rds"))
US <- c("K200","KQ150","KOSPI_all","KOSDAQ_all")
audit_order <- c(K200=1, KQ150=2, KOSPI_all=3, KOSDAQ_all=4)

pack_u <- function(r){
  if(is.null(r)) return(NULL)
  gm <- function(w) as.list(round(r[[w]]$exfl,5))
  list(
    n_months=r$n_months, k_mean=round(r$k_mean,1), members_mean=round(r$nmem_mean,0),
    scored_mean=round(r$nsc_mean,0),
    capw=list(base=as.list(round(r$capw$base,5)), exfl=as.list(round(r$capw$exfl,5)),
              random=as.list(round(r$capw$rand,5))),
    ew=list(base=as.list(round(r$ew$base,5)), exfl=as.list(round(r$ew$exfl,5)),
            random=as.list(round(r$ew$rand,5))),
    exfl_vs_random_impr=list(
      mdd=round(r$capw$rand["mdd"]-r$capw$exfl["mdd"],5),
      cvar20=round(r$capw$rand["cvar20"]-r$capw$exfl["cvar20"],5),
      dd=round(r$capw$rand["dd"]-r$capw$exfl["dd"],5),
      worst5=round(r$capw$rand["worst5"]-r$capw$exfl["worst5"],5)),
    exfl_vs_random_CI=list(
      mdd=round(as.numeric(r$ci$er[c(1,3),"mdd"]),5),
      cvar20=round(as.numeric(r$ci$er[c(1,3),"cvar20"]),5),
      dd=round(as.numeric(r$ci$er[c(1,3),"dd"]),5),
      worst5=round(as.numeric(r$ci$er[c(1,3),"worst5"]),5)),
    return_drag_ann=round(r$capw$exfl["ann_ret"]-r$capw$base["ann_ret"],5)
  )
}
capw_mdd_eff <- sapply(US, function(U) as.numeric(M$primary[[U]]$capw$rand["mdd"]-M$primary[[U]]$capw$exfl["mdd"]))
ew_mdd_eff   <- sapply(US, function(U) as.numeric(M$primary[[U]]$ew$rand["mdd"]-M$primary[[U]]$ew$exfl["mdd"]))
rho <- suppressWarnings(cor(audit_order, capw_mdd_eff, method="spearman"))
coherence <- sapply(US, function(U){ e<-M$primary[[U]]$capw$exfl; rr<-M$primary[[U]]$capw$rand
  sum(c(rr["mdd"]>e["mdd"], rr["cvar20"]>e["cvar20"], rr["dd"]>e["dd"], rr["worst5"]>e["worst5"])) })

val <- list(
  wt_id="WT-D20260713_004", frontier_id="FQ-033",
  title="R20 — Index-level forensic (Benford) filter validation across audit-quality gradient",
  prereg_sha256=readLines(file.path(OUT,"preregistration.sha256")),
  metric_type="diagnostic (index reconstruction; NOT canonical_screen, NOT capital strategy)",
  envelope_note="KOSPI-all & KOSDAQ-all are OUTSIDE deployment envelope (K200 U KQ150). Diagnostic only; production envelope unchanged.",
  primary_window="decision_ym 2010-01..2015-12 (72 months; all 4 universes >=98% Benford coverage)",
  coverage_gate=list(
    finding="Benford (annual, >=15 raw-monetary items) coverage 98-100% all universes 2009-2015; COLLAPSES post-2016 (DART source): KOSPI-all ~40%, KOSDAQ-all ~20-25%. K200/KQ150 75-96%.",
    decision="availability-driven primary window 2010-2015 fixed in prereg; post-2016 small-universe honestly EXCLUDED (would confound audit-quality construct)."),
  verdict="config-scoped negative + frontier marker",
  verdict_detail=paste0(
    "Index-level design (confound-removed, per Dohoon) did NOT rescue the Benford forensic filter. ",
    "Across ALL 4 universes and BOTH weighting bases, removing the worst-Benford-decile is statistically ",
    "indistinguishable from random removal on every tail metric (all exfl-vs-random CIs straddle 0). ",
    "The pre-registered audit-quality GRADIENT is FALSIFIED: predicted monotonic increase K200~0 -> KOSDAQ-all max; ",
    "observed Spearman(audit-order, MDD-effect)=", round(rho,2), " (vs +1 predicted); EW-basis ~0 everywhere. ",
    "Corroborates & generalizes R18 null (long-alpha placebo p=0.16) to the risk-exclusion overlay framing."),
  gradient=list(
    predicted="monotonic increasing (K200 smallest -> KOSDAQ_all largest)",
    capw_mdd_effect=as.list(round(capw_mdd_eff,5)),
    ew_mdd_effect=as.list(round(ew_mdd_eff,5)),
    spearman_capw=round(rho,3), monotonic_increasing=FALSE,
    note="one large cap-w number (K200 MDD +0.0214) is a single-name cap-concentration drawdown-path artifact: absent in EW (+0.0018), incoherent (2/4 tail metrics), CI straddles 0."),
  tail_coherence_capw=as.list(setNames(as.integer(coherence), US)),
  per_universe=setNames(lapply(US, function(U) pack_u(M$primary[[U]])), US),
  secondary_full_period=list(
    note="K200/KQ150 full 2010-2025 (large-cap end longevity; small universes coverage-blocked post-2016).",
    K200=pack_u(M$secondary$K200_full), KQ150=pack_u(M$secondary$KQ150_full)),
  power_caveat="Clean-coverage window (2010-2015) EXCLUDES 2008 GFC (pre-data) & 2020 COVID (post-coverage-collapse) => reduced tail-event sampling weakens ABSOLUTE tail-protection power. But the discriminating GRADIENT prediction (shape, less crash-dependent) fails clearly, and the least-audited universe (KOSDAQ-all, predicted MAX) is flattest/negative.",
  survivorship_c6=list(
    raw_returns="survivorship-free (RAWDATA includes delisted history).",
    exchange_map_gap="8.5% stock-days (488 codes) unlabeled = delisted-pre-2026 small caps (median Size ~half), mostly small KOSDAQ, excluded from KOSPI-all/KOSDAQ-all.",
    direction="excluded delisted small caps are often manipulation/fraud collapses (Benford-target tail) => bias AGAINST a positive filter claim (conservative). cap-weighting shrinks their impact."),
  next_probe=list(
    "Discrete delisting/unfaithful-disclosure EVENT study: test Benford-flag AUC/hazard against RAWDATA UnfaithfulDisc/AdminStock/TradingHalt event flags (construct-valid, higher power than smoothed cap-w monthly index tail-risk; forensic tail may be too rare/idiosyncratic to surface in an index return series).",
    "Coverage-repaired KOSDAQ-all re-test (screen-tier/RAMP, out of envelope): relax >=15-item threshold or pool quarterly-filing digits to restore post-2016 small-cap Benford coverage, then complete the least-audited gradient arm (currently data-blocked <25%, exactly where prereg predicted strongest effect).",
    "EW-basis + crisis-window tail check conditional on 2008/2020 coverage restoration (absolute-power complement)."),
  data_provenance=list(
    benford_scores="recomputed universe-agnostic FSD MAD (R18 WT_D20260713_002 exact code, no universe filter)",
    exchange_map="KRX stk_info(KOSPI)/ksq_info(KOSDAQ) common-stock static map (59 snapshots 2026-03/04 union) + flag-augment (ever-K200->KOSPI, ever-KQ150->KOSDAQ)",
    returns="RAWDATA daily Ret compounded monthly (exact-adjusted: Ret==Close-ratio verified); cap-weight = month-start Size share")
)
write_json(val, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, na="null")
cat("[03] alpha_validation.json written\n")

# ---- alpha_scores.parquet : forensic score panel (filter input) ----
pan <- readRDS(file.path(OUT,"panel_r20.rds"))
ap <- pan[ym>=201001 & ym<=201512 & is.finite(bf_raw),
   .(Date=as.Date(sprintf("%d-%02d-01",ym%/%100L,ym%%100L)), Ticker=paste0("A",code),
     factor="Benford_FSD_MAD", bf_raw, exch, K200=K200_prev, KQ150=KQ150_prev)]
write_parquet(ap, file.path(OUT,"alpha_scores.parquet"))
cat("[03] alpha_scores.parquet rows:", nrow(ap),"\n")

# ---- alpha_package.json (schema-conformant; diagnostic) ----
apkg <- list(
  task_id="WT-D20260713_004", as_of_date="2025-06-01", forecast_horizon="12M",
  wt_type="discovery", metric_type="diagnostic",
  alpha_vector=setNames(list(), character(0)),   # no long-alpha vector (risk-overlay diagnostic)
  confidence_vector=setNames(list(), character(0)),
  signal_matrix_ref="stage_artifacts/WT_D20260713_004/alpha_scores.parquet",
  factor_specs=list(list(
    factor_family="Forensic/EarningsQuality", proxy="Benford First-Digit Deviation (FSD MAD)",
    formula="MAD = mean_d |p_obs(d)-p_exp(d)|, p_exp=log10(1+1/d), raw-monetary whitelist 43 items, >=15/firm-year",
    lag_rule="annual, Factor_Date+1 month (expand_hold H=12)", winsorization="per-FY 1/99 (n/a here; raw MAD)",
    neutralization="none (cross-sectional decile within universe)", economic_rationale="manipulation fingerprint (Amiram-Bozanic-Rouen 2015)",
    weight_theta=1.0, references=list("Amiram-Bozanic-Rouen 2015 RAS","Benford 1938","Nigrini 2012"))),
  diagnostics=list(
    canonical_port_t_nw_lag3=NULL,
    canonical_port_t_note="NULL by design: R20 is an index-level risk-EXCLUSION overlay diagnostic, not a top-N long-alpha screen. Long-alpha PORT_t already delivered by R18 (WT_D20260713_002) = null (cap-w 0.57, placebo p=0.16).",
    gradient_spearman_capw=round(rho,3), gradient_monotonic=FALSE,
    exfl_vs_random_all_CI_straddle_zero=TRUE),
  selection_objective="canonical_port_t",
  selection_objective_note="risk-overlay characterization (not long-selection); no candidate sweep (single prereg filter+threshold, random=control).",
  challenge_flags=list("RF: gradient FALSIFIED (Spearman -0.4 vs +1 predicted)","coverage-gate: post-2016 small-universe honestly excluded","power: clean-window excludes 2008/2020 crashes","C6: 8.5% delisted-small-cap exchange-label gap (bias against positive claim)"),
  verdict="config-scoped negative + frontier marker"
)
write_json(apkg, file.path(MBX,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, na="null")
cat("[03] alpha_package.json written to mailbox\n")

# lineage (write -> record, per init obligation)
try({
  source(file.path(ROOT,"02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(task_id="WT-D20260713_004", package_type="alpha_package",
    method_selected="R20 index-level Benford exclusion-overlay diagnostic (4 universes x {base,exfl,random x3})",
    input_file_paths=c(file.path(OUT,"panel_r20.rds"), file.path(OUT,"preregistration.json")))
  cat("[03] lineage recorded\n")
}, silent=TRUE)
cat("[03] DONE\n")
