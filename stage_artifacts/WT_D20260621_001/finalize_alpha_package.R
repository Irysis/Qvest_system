#==============================================================================
# Finalize alpha_package.json (post-Codex revisions) for WT-D20260621_001.
# Revisions: C1(repoint signal_matrix_ref), C2(C15 exception+lineage),
#            C3(RF-A3 corrected to HIGH), C4(DPL reframe), C5(sector-neutral IC),
#            C7(DSR language tightened).
#==============================================================================
Sys.setenv(R_DATATABLE_NUM_THREADS="1"); suppressMessages({library(data.table);library(jsonlite);library(arrow)}); setDTthreads(1L)
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT_A<-file.path(ROOT,"stage_artifacts/WT_D20260621_001")
WT_DIR<-file.path(ROOT,"qepm/mailbox/worktask/WT-D20260621_001")
ev<-readRDS(file.path(OUT_A,"eval_results_fixed.rds"))
rv<-readRDS(file.path(OUT_A,"revise_checks.rds"))
scr<-ev$screen_tab; g<-function(s,col) scr[signal==s][[col]]
da<-ev$diag_all

# C1 fix: rename snapshot, ensure full-ts is canonical reference
snap_src<-file.path(OUT_A,"alpha_scores.parquet")
snap_dst<-file.path(OUT_A,"alpha_scores_lastmonth.parquet")
if (file.exists(snap_src) && !file.exists(snap_dst)) file.copy(snap_src,snap_dst,overwrite=TRUE)
# canonical alpha_scores.parquet = FULL time series (Date x Ticker x score) — overwrite snapshot
full<-as.data.table(read_parquet(file.path(OUT_A,"alpha_scores_fullts.parquet")))
setnames(full, "score_a504", "score", skip_absent=TRUE)
write_parquet(full, snap_src)  # now Date x Ticker x score (RF-A7 resolved)
# mirror to qepm canonical stage path
qstage<-file.path(ROOT,"qepm/stage_artifacts/WT_WT-D20260621_001"); dir.create(qstage,showWarnings=FALSE,recursive=TRUE)
file.copy(snap_src, file.path(qstage,"alpha_scores.parquet"), overwrite=TRUE)

# alpha_vector from last month of full-ts
last_d<-max(full$Date); av<-full[Date==last_d & is.finite(score), .(Ticker, a=score)]
alpha_vector<-as.list(setNames(round(av$a,5), av$Ticker))
confidence_vector<-as.list(setNames(rep(0.4, nrow(av)), av$Ticker))  # low-moderate; signal weak

factor_specs<-list(
  list(factor_family="Momentum_PathQuality", proxy="DFA_Hurst_252d",
    formula="H = slope(log F(s) ~ log s); F(s)=RMS of linear-detrended cumulative-return profile over non-overlapping windows s (Peng 1994 DFA). Per-window detrend uses ONLY data <= sig_date (C1/C7).",
    lag_rule="price t-1 close; rolling 252d (also 126/504) window Date<=sig_date (C1)",
    winsorization="cross-sectional 3std on z", neutralization="raw cross-sectional z (sector-neutral IC tested, see RF-A4)",
    standardization="cross-sectional z (C13 orientation); manual zc() not Factor DB Z_Score_Aligned -> documented new-factor exception",
    economic_rationale="Hurst H = long-range dependence/self-similarity of the return path (Mandelbrot; R/S Hurst 1951; DFA Peng 1994). Thesis: H>0.5 persistent=>momentum reliable; H<0.5 anti-persistent=>momentum reverses/crashes. FALSIFIED in KR top-universe.",
    weight_theta=0.0,
    references=list("Mandelbrot-Wallis 1969","Peng et al. 1994 (DFA)","Hurst 1951 (R/S)","Daniel-Moskowitz 2016"),
    evidence_tier="C", redundancy_cluster_id="momentum_pathquality_NEW (|xsec corr vs momentum cluster|<0.04)",
    source="new_designed",
    c15_exception="NEW-FACTOR carve-out: Hurst computed from .cache/rawdata.parquet Close/Ret per task brief (request.json PIT: 'compute from rawdata via compute_momentum.R pattern'). Not in Factor DB; load_month_factors() not applicable. PIT Date<=sig_date enforced in-code. Analogous to ML daily-parquet C15 carve-out.",
    estimator_crosscheck=sprintf("DFA-252 vs R/S-252 xsec cor = %.3f", ev$dfa_rs_cor)),
  list(factor_family="Momentum", proxy="M01_Mom_12_1 (baseline reference)",
    formula="prod(1+ret[t-252:t-21])-1", lag_rule="price t-1; 252d skip 21d (C1)",
    winsorization="3std", neutralization="raw z", standardization="cross-sectional z",
    economic_rationale="Classical 12-1 momentum baseline the Hurst conditioning was meant to improve. It does NOT (a504 vs baseline paired t=0.33).",
    weight_theta=1.0, references=list("Jegadeesh-Titman 1993","Carhart 1997"),
    evidence_tier="B", redundancy_cluster_id="momentum_cluster",
    source="rawdata_derived",
    c15_note="M01/M08/M13 recomputed from rawdata (NOT load_month_factors) because factor_db_daily is CRITICAL-stale per task DATA NOTE. metric_type=rawdata_recomputed.")
)

diagnostics<-list(
  metric_type="canonical_screen + rank-IC screening (real-computation; NOT forge-authoritative)",
  rank_ic_chosen_a504=round(da$a504$rank_ic,4), icir_monthly_a504=round(da$a504$icir_monthly,3),
  icir_annualized_a504=round(da$a504$icir_annualized,3), harvey_t_rankic_nw3_a504=round(da$a504$harvey_t_nw3,2),
  subperiod_sign_stability_a504=round(da$a504$sign_stability,2), n_months_ic=da$a504$n_months,
  rank_ic_baseline=round(da$d_baseline$rank_ic,4), harvey_t_rankic_baseline=round(da$d_baseline$harvey_t_nw3,2),
  rank_ic_pure_hurst=round(da$c$rank_ic,4), harvey_t_pure_hurst=round(da$c$harvey_t_nw3,2),
  turnover_proxy_annual=round(g("a504","turnover_ann"),2),
  rf_a4_sector_neutral_ic=list(a504_raw_ic=rv$sn_ic_raw, a504_sector_neutral_ic=rv$sn_ic,
     a504_retention_pct=round(100*rv$sn_retention,0),
     pure_hurst_raw=rv$pureH_raw, pure_hurst_sector_neutral=rv$pureH_sn,
     note="a504 SN retention 42% (half is sector structure). pure-H SN ~0/neg -> H is NOT a sector artifact, just no signal."),
  rf_a3_recent_ic=list(full_icir_monthly=rv$rfa3_full_icir, recent_3y_icir=rv$rfa3_recent_icir,
     ratio=rv$rfa3_ratio, recent_3y_rank_ic=rv$rfa3_recent_ic, triggered=TRUE,
     interpretation="RF-A3 TRIGGERED (3.41x > 1.5x). Corrected from draft 'clean' per Codex C3. Recent-window favorable noise on a weak signal, NOT a robust improvement — additional evidence against the thesis."),
  note="rank-IC weak (~0.015); pure-Hurst rank-IC NEGATIVE (-0.0095). portfolio-alpha t (below) is decisive screening number."
)

portfolio_alpha<-list(
  metric_type="canonical_screen (top25 EW long-only, 15bps delta cost, liq>=2e8, REAL KOSPI200_TR benchmark from .cache/benchmark.parquet)",
  note="NOT forge-authoritative. forge build_bt_result required for graduation binding. Screening reals only.",
  a504_hurst_scaled_504d=list(port_alpha_t_nw3=round(g("a504","port_alpha_t_nw3"),3), IR=round(g("a504","IR"),3), net_active_ann=round(g("a504","alpha_ann"),4), net_sr=round(g("a504","net_sr"),3)),
  a_hurst_scaled_252d=list(port_alpha_t_nw3=round(g("a","port_alpha_t_nw3"),3), IR=round(g("a","IR"),3)),
  d_baseline_pure_momentum=list(port_alpha_t_nw3=round(g("d_baseline","port_alpha_t_nw3"),3), IR=round(g("d_baseline","IR"),3), net_active_ann=round(g("d_baseline","alpha_ann"),4), net_sr=round(g("d_baseline","net_sr"),3)),
  c_pure_hurst=list(port_alpha_t_nw3=round(g("c","port_alpha_t_nw3"),3), IR=round(g("c","IR"),3)),
  b_hurst_gated_reversal=list(port_alpha_t_nw3=round(g("b","port_alpha_t_nw3"),3)),
  e_additive_70mom_30hurst=list(port_alpha_t_nw3=round(g("e_additive","port_alpha_t_nw3"),3)),
  incremental_a504_vs_baseline=list(monthly_active_diff_mean=round(ev$delta_mean,5), paired_t=round(ev$delta_t,2),
     verdict="a504 NOT meaningfully > baseline (|t|=0.33 << 2). Hurst conditioning adds NO incremental alpha."),
  graduation_gate_check=list(hard_port_t_threshold=2.95, best_variant_a504_port_t=round(g("a504","port_alpha_t_nw3"),3),
     baseline_port_t=round(g("d_baseline","port_alpha_t_nw3"),3),
     verdict="ALL variants below HARD 2.95 (best 1.65). Even baseline momentum 1.57. NON-GRADUATING.")
)

mechanism_test<-list(
  description="Momentum rank-IC conditional on Hurst tercile — DIRECT test of the thesis (high-H => stronger momentum). This is the decisive falsification.",
  momentum_ic_low_H=0.0179, momentum_ic_low_H_t=1.42,
  momentum_ic_mid_H=0.0219, momentum_ic_mid_H_t=1.84,
  momentum_ic_high_H=0.0084, momentum_ic_high_H_t=0.73,
  verdict="FALSIFIED: momentum IC is WEAKEST in high-Hurst names (t=0.73), strongest in mid-H. Thesis predicted high_H >> low_H — opposite/null observed.",
  crash_check=list(top_mom_quintile_fwd_q05=list(low_H=-0.1863, mid_H=-0.1913, high_H=-0.2229),
     verdict="High-Hurst (persistent-path) names crash HARDER (q05 -22.3% vs low-H -18.6%) — the native-crash-filter premise is ALSO falsified.")
)

orth<-ev$orth
orthogonality<-list(metric="avg cross-sectional Spearman corr (H vs momentum cluster)",
  H252_vs_M01=round(orth$H252_vs_M01,4), H252_vs_M08=round(orth$H252_vs_M08,4),
  H252_vs_M13=round(orth$H252_vs_M13,4), H126_vs_M01=round(orth$H126_vs_M01,4), H504_vs_M01=round(orth$H504_vs_M01,4),
  cluster_internal_check=list(M01_vs_M08=round(orth$M01_vs_M08,3), M01_vs_M13=round(orth$M01_vs_M13,3),
     note="momentum cluster is internally collinear (0.89/0.97) — confirms metric works"),
  verdict="H is GENUINELY ORTHOGONAL to momentum cluster (|corr|<0.04, target <0.6). NOT a relabeled M01. But orthogonal != additive: no incremental long-only alpha.")

hurst_distribution<-list(mean_H=round(ev$hsum$mean_H,3), median_H=round(ev$hsum$med_H,3),
  sd_H=round(ev$hsum$sd_H,3), q10=round(ev$hsum$q10,3), q90=round(ev$hsum$q90,3),
  frac_persistent_H_gt_0p5=round(ev$hsum$frac_persistent,3),
  note="KR top-universe daily returns lean mildly anti-persistent (mean H=0.485, 41% persistent).")

challenge_flags<-list(
  list(id="RF-A-FALSIFIED", severity="HIGH", desc="Core thesis falsified by direct mechanism test (momentum IC weakest in high-H, t=0.73; high-H names crash harder) and paired incremental test (a504 vs baseline t=0.33)."),
  list(id="RF-A3", severity="HIGH", desc="CORRECTED per Codex C3: recent-3Y a504 ICIR 0.291 vs full 0.085 = 3.41x (>1.5x trigger). Recent favorable noise on weak signal — evidence AGAINST thesis, not for it."),
  list(id="RF-A4", severity="MEDIUM", desc="a504 sector-neutral IC retention 42% — half is sector structure. pure-H SN stays ~0 (not a sector artifact, just no signal)."),
  list(id="RF-A2", severity="MEDIUM", desc="a504 essentially same rank-IC as baseline; paired active t=0.33. Non-additive."),
  list(id="AX-007", severity="INFO", desc="single-sleeve long-only top-25: even baseline momentum canonical_screen PORT_t=1.57 < HARD 2.95. Cross-sectional->portfolio translation is binding limit."),
  list(id="DATA-BMRET", severity="MEDIUM", desc="rawdata.parquet BM_Ret empty (known issue). Rebuilt benchmark from .cache/benchmark.parquet (real KOSPI200 TR); M08 rebuilt with real daily BM. Documented."),
  list(id="C15-EXCEPTION", severity="INFO", desc="Hurst computed direct from rawdata per task brief new-factor carve-out; momentum cluster recomputed from rawdata (factor_db_daily CRITICAL-stale). Lineage recorded.")
)

screen_route<-list(graduate_candidate=FALSE, route="DPL_FEATURE",
  expected_contribution="approximately 0 on current evidence",
  rationale="Real-but-non-graduating AND non-additive. pure-H has NEGATIVE standalone rank-IC; H-scaled momentum is statistically identical to plain momentum (t=0.33); gating/additive forms DILUTE. As OVERLAY_CANDIDATE: fails. As FR_RCMA regime input: no regime-conditional edge found. Residual value is at most ONE orthogonal feature in a learned (DPL) model — but expected contribution approximately 0. Recommend NO further single-sleeve pursuit; do not re-test as standalone alpha.",
  measurement_graduation_tier="screening-tier (not capital).")

ap<-list(task_id="WT-D20260621_001", wt_type="discovery", as_of_date="2026-06-21",
  forecast_horizon="1M", selection_objective="rank_ic",
  selection_objective_note="Predictive-power selection only. No sharpe/cagr/mdd used for factor selection.",
  status="ALPHA_DONE_NEGATIVE",
  status_note="Hypothesis FALSIFIED (mechanism + incremental tests). Signal orthogonal but non-additive. Screening-tier DPL_FEATURE, expected contribution ~0. AX-000 honest negative result. Codex round REVISE -> 5 ACCEPT + 1 PARTIAL(C15) + 1 REBUTTAL(AX-008 downstream); all revisions made result MORE negative.",
  hypothesis="Hurst-Conditioned Persistence-Quality Momentum (DFA H252 primary, R/S cross-check, A/B/C operationalizations, 2005-2026 257 months)",
  alpha_definition="emitted alpha = a504 (z_M01 * g(H504)), best-of-Hurst variant, FLAGGED screen-route non-additive. Baseline z_M01 retained for reference.",
  alpha_vector=alpha_vector, confidence_vector=confidence_vector,
  signal_matrix_ref=paste0("file://", file.path(OUT_A,"alpha_scores.parquet"),
                           " (Date x Ticker x score, 257 sig_dates 2005-2026; RF-A7 resolved per Codex C1)"),
  factor_specs=factor_specs, diagnostics=diagnostics, portfolio_alpha=portfolio_alpha,
  mechanism_test=mechanism_test, orthogonality=orthogonality, hurst_distribution=hurst_distribution,
  redundancy_cluster_id="momentum_pathquality_NEW",
  cor_vs_admitted_active="H vs momentum cluster |xsec corr|<0.04 (orthogonal); additive value ~0",
  deflated_sharpe_ratio=list(value=round(ev$dsr_a504,3), baseline=round(ev$dsr_base,3),
     severity="advisory_diagnostic_only",
     note="hypothesis-driven A/B chain (7 operationalizations, sequential mechanism-driven). DSR reported as a diagnostic number ONLY, not used as any pass signal. Verdict is negative independent of DSR. measurement-graduation 2026-06-10: chain != sweep."),
  ax001_v2_note="N/A — offensive momentum-quality thesis, not defensive.",
  cost_model_version="v2.4_kr_retail_15bps",
  data_provenance=list(rawdata=".cache/rawdata.parquet (fresh, 2026-06-19)",
     benchmark=".cache/benchmark.parquet (real KOSPI200 TR; rawdata BM_Ret empty - known issue)",
     universe="KOSPI200 union KOSDAQ150 PIT membership flags; 2005-01 to 2026-05; liq 2e8 at screen"),
  screen_route=screen_route, challenge_flags=challenge_flags,
  codex_round=list(stance="REVISE", critic_model="gpt-5.5", agreement_on_conclusion=TRUE,
     concerns_total=7, accepted=5, partial=1, rebuttal=1,
     challenge_note="qepm/mailbox/worktask/WT-D20260621_001/challenge_note.md",
     net_effect="all revisions made the negative conclusion more honest; no silent override"),
  method_shopping_log=list(candidates_tried=7, selection_type="chain",
    method_log=list(
      list(name="a_Hscaled_252", port_t=round(g("a","port_alpha_t_nw3"),2), selected=FALSE),
      list(name="b_Hgated_reversal", port_t=round(g("b","port_alpha_t_nw3"),2), selected=FALSE),
      list(name="c_pure_Hurst", port_t=round(g("c","port_alpha_t_nw3"),2), selected=FALSE),
      list(name="d_baseline_momentum", port_t=round(g("d_baseline","port_alpha_t_nw3"),2), selected=FALSE),
      list(name="a126_Hscaled_126", port_t=round(g("a126","port_alpha_t_nw3"),2), selected=FALSE),
      list(name="a504_Hscaled_504", port_t=round(g("a504","port_alpha_t_nw3"),2), selected=TRUE),
      list(name="e_additive_70_30", port_t=round(g("e_additive","port_alpha_t_nw3"),2), selected=FALSE))),
  generated_by="alpha-research (Agent tool, Opus 4.8)",
  generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"))

# Step 1: write final alpha_package.json (L-194: write BEFORE lineage)
write_json(ap, file.path(WT_DIR,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, na="null", digits=6)
cat("Wrote alpha_package.json — alpha_vector n=", length(alpha_vector), " status=", ap$status, "\n")

# refresh alpha_validation.json
write_json(list(diagnostics=diagnostics, portfolio_alpha=portfolio_alpha, mechanism_test=mechanism_test,
  orthogonality=orthogonality, hurst_distribution=hurst_distribution, screen_route=screen_route),
  file.path(OUT_A,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, na="null", digits=6)
file.copy(file.path(OUT_A,"alpha_validation.json"), file.path(WT_DIR,"alpha_validation.json"), overwrite=TRUE)

# Step 2: lineage (after final write)
lu<-file.path(ROOT,"02_Infrastructure/worktask/lineage_utils.R")
if (file.exists(lu)) {
  tryCatch({ source(lu)
    record_package_lineage(task_id="WT-D20260621_001", package_type="alpha_package",
      method_selected="Hurst-conditioned momentum (DFA H504-scaled a504) — FALSIFIED negative result",
      input_file_paths=c(".cache/rawdata.parquet",".cache/benchmark.parquet",
        file.path(OUT_A,"panel_fixed.rds"), file.path(OUT_A,"alpha_scores.parquet")))
    cat("lineage recorded\n")
  }, error=function(e) cat("lineage WARN:", conditionMessage(e), "\n"))
} else cat("lineage_utils.R absent\n")
cat("FINALIZE DONE\n")
