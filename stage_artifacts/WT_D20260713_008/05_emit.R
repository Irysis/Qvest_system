# R24 Step 05 — emit alpha_scores.parquet + alpha_validation.json + alpha_package.json + lineage
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260713_008")
MB   <- file.path(ROOT,"qepm/mailbox/worktask/WT-D20260713_008")
dir.create(MB, showWarnings=FALSE, recursive=TRUE)
S  <- readRDS(file.path(OUT,"episode_panel.rds")); TR <- readRDS(file.path(OUT,"test_results.rds"))
rf<-TR$RES$hardened; rs<-TR$RES$diag_wd_strict

# alpha_scores.parquet = episode-level prediction panel (feature + treatment + label)
sc <- S$Ehard[, .(Ticker, sc, fy, rcept_ym, delay_d,
                  worst_decile_late_FROZEN=worst_decile_late, wd_strict_DIAG=wd_strict, late30_DIAG=late30,
                  size_z, adv_z, KOSPI, severe_event_fwd12m=E)]
write_parquet(sc, file.path(OUT,"alpha_scores.parquet"))

# alpha_validation.json
av <- list(
  wt_id="WT-D20260713_008", fq_id="FQ-037", iteration="R24",
  round_type="STAGE_1_KNOWLEDGE_ROUND", metric_type="event_prediction_OR_lift (NOT portfolio; canonical PORT_t N/A)",
  prereg_sha256="e13d4251f0be30023307d82e91c8e2f0c2752b7f23aeaec2359a2496568d4291",
  verdict="CONFIG_SCOPED_NEGATIVE", frontier="OPEN",
  universe_scope=list(
    measurable_universe=677, label="DART_FILING_COVERED_UNIVERSE_677",
    rawdata_full_universe=3914,
    honest_reduction="full ~2500 KOSPI+KOSDAQ filer universe unreachable without DART API this round; scope frozen at 677 (historical K200uKQ150 union with full annual filing history).",
    note="universe_comparison mandate (KR_top342 vs v2) N/A: this is an event-prediction study, not a factor screen; the relevant comparison is R23 monthly-K200uKQ150-panel vs R24 episode-677-universe, reported below."),
  design=list(level="episode (ticker x fiscal-year filing)", n_episodes=nrow(sc), base_rate=mean(sc$severe_event_fwd12m)),
  frozen_primary_hardened=list(
    treatment="per-fy p90 & delay>0 (collapsed to any-late, 1105 ep / 528 firms)",
    lift=rf$lift, lift_firmboot95=as.numeric(rf$lift_boot),
    or_ctrl_yearFE=rf$or_fe, or_ctrl_yearFE_ci=as.numeric(rf$ci_fe), or_ctrl_yearFE_p=rf$p_fe,
    or_ctrl_noFE=rf$or_no, or_ctrl_noFE_p=rf$p_no,
    outcome="PREDICTION_NOT_ESTABLISHED (bootCI includes 1; year-FE p=0.051)"),
  extreme_tail_diagnostic_nonauthoritative=list(
    treatment="per-fy rank top-decile & delay>0 (29 ep / 27 firms / 6 events)",
    lift=rs$lift, lift_firmboot95=as.numeric(rs$lift_boot),
    or_ctrl_yearFE=rs$or_fe, or_ctrl_yearFE_p=rs$p_fe, or_ctrl_noFE=rs$or_no, or_ctrl_noFE_p=rs$p_no,
    loo=TR$loo_summary,
    note="robust (boot CI excludes 1, LOO all-survive) but non-authoritative; routes to pre-registered extreme-tail round."),
  size_tier=list(events_by_tier=list(small=6,mid=0,large=0), small_lift=12.22,
    finding="all 6 extreme-tail severe events small-cap => small-cap-confined; structural deployment-universe starvation, deployment-conservative."),
  aux_continuous_delay=list(or_per_sd=TR$AUX$or, p=TR$AUX$p, note="flat => non-monotonic extreme-tail concentration (R22 D2/R23 replicated)"),
  power_comparison_R23_to_R24=list(independent_event_firms_R23=6, independent_extreme_tail_firms_R24=27,
    note="episode design + universe expansion resolved R23's power/inference wall at the extreme tail."),
  pit=list(dart_api_calls=0, hardening="disc_ck 36/2492 matched, hardened==pureflag, 89% same-month (R23), residual direction conservative"),
  charts=file.path("charts", list.files(file.path(OUT,"charts"), pattern="png$"))
)
write_json(av, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)

# alpha_package.json (Stage-1 knowledge; no capital alpha_vector; canonical PORT_t null w/ reason)
ap <- list(
  task_id="WT-D20260713_008", as_of_date="2026-07-13", forecast_horizon="12M_event",
  round_type="STAGE_1_KNOWLEDGE_ROUND",
  alpha_vector=NULL, confidence_vector=NULL,
  signal_matrix_ref="stage_artifacts/WT_D20260713_008/alpha_scores.parquet",
  factor_specs=list(list(
    factor_family="Disclosure/Governance forensics",
    proxy="사업보고서 filing delay extreme tail (days late vs 90d legal deadline)",
    formula="delay_d = rcept_dt - (Dec-FYE+90d); worst_decile_late = per-fy p90 & delay>0 (FROZEN primary); wd_strict = per-fy rank top-decile & delay>0 (diagnostic)",
    lag_rule="filing month rcept_ym; outcome strictly forward [rcept_ym+1, rcept_ym+12] (C5)",
    winsorization="none (rank/threshold-based)", neutralization="logSize_z + logADV_z + KOSPI + year-FE (regression controls)",
    economic_rationale="firms in governance distress delay mandatory annual filings; the EXTREME tail of lateness precedes delisting/관리종목/불성실공시 designation — but only among small-caps (large/mid late filers do not fail). Not a return factor; an adverse-event early-warning signal.",
    weight_theta=NA, references=list("R22 WT-D20260713_006","R23 WT-D20260713_007")
  )),
  diagnostics=list(
    canonical_port_t_nw_lag3=NULL,
    canonical_port_t_null_reason="Stage-1 knowledge round: event-prediction (OR/lift), NOT a long-only portfolio. canonical_screen_bt N/A — no capital/PORT_t claim by design.",
    frozen_primary_lift=rf$lift, frozen_primary_or_yearFE=rf$or_fe, frozen_primary_p=rf$p_fe,
    extreme_tail_lift=rs$lift, extreme_tail_or_yearFE=rs$or_fe, extreme_tail_p=rs$p_fe,
    n_episodes=nrow(sc), base_rate=mean(sc$severe_event_fwd12m)),
  selection_objective="event_prediction_controlled_OR",
  selection_type="chain", n_trials=1,
  challenge_flags=list(
    "FROZEN primary p90 collapsed to any-late (dilution) => NOT ESTABLISHED",
    "signal is small-cap-confined (all 6 extreme-tail events small-cap; 0 mid/large) => structural deployment starvation",
    "extreme-tail robust (27 firms, LOO-survive, bootCI excl 1) but non-authoritative + event-count modest (6)",
    "universe honestly reduced to 677 (no DART API); NOT full filer universe",
    "NO capital/PORT_t/filter claim (Stage-1)"),
  verdict="CONFIG_SCOPED_NEGATIVE", frontier="OPEN"
)
write_json(ap, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, null="null")

cat("[05] alpha_scores.parquet rows:", nrow(sc), "\n")
cat("[05] alpha_validation.json + alpha_package.json written\n")

# lineage (write_json done above; record after files exist — L-194 order)
lin <- tryCatch({ source(file.path(ROOT,"02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(task_id="WT-D20260713_008", package_type="alpha_package",
    method_selected="episode-level late-filing extreme-tail -> severe-event prediction (Stage-1 knowledge)",
    input_file_paths=c(file.path(OUT,"census.rds"), file.path(OUT,"episode_panel.rds"),
      "stage_artifacts/WT_D20260711_002/filings_inventory.parquet",
      "stage_artifacts/WT-D20260710_005/disc_ck")); "ok" },
  error=function(e) paste("lineage skipped:", conditionMessage(e)))
cat("[05] lineage:", lin, "\n[05] DONE\n")
