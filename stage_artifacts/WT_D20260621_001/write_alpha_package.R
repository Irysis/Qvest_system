#==============================================================================
# Build alpha_package_draft.json (Codex round step 1) for WT-D20260621_001
# HONEST negative result: Hurst orthogonal but NON-additive; mechanism falsified.
#==============================================================================
Sys.setenv(R_DATATABLE_NUM_THREADS="1"); suppressMessages({library(data.table); library(jsonlite); library(arrow)}); setDTthreads(1L)
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT_A<-file.path(ROOT,"stage_artifacts/WT_D20260621_001")
WT_DIR<-file.path(ROOT,"qepm/mailbox/worktask/WT-D20260621_001")
ev<-readRDS(file.path(OUT_A,"eval_results_fixed.rds"))
scr<-ev$screen_tab; setkey(scr,signal)
g<-function(s,col) scr[signal==s][[col]]
da<-ev$diag_all

# alpha_vector: chosen signal = a504 (best Hurst variant) scores at last sig_date.
# Per role card, discovery needs factor_specs>=1 + alpha_vector. We emit the a504 alpha
# but FLAG it screen-route (not graduate). Long-only: negative scores allowed (optimizer excludes).
sc<-as.data.table(read_parquet(file.path(OUT_A,"alpha_scores.parquet")))
# expected active return proxy: standardized score * realized mean active spread (informational only)
# alpha_vector = sig_a504 score (z-like). confidence from H coverage + sign stability.
av<-sc[is.finite(sig_a504_score), .(Ticker, a=sig_a504_score)]
alpha_vector<-as.list(setNames(round(av$a,5), av$Ticker))
conf<-sc[is.finite(sig_a504_score), .(Ticker, c=pmin(1, pmax(0.2, 0.6)) )]  # uniform moderate; signal weak
confidence_vector<-as.list(setNames(round(conf$c,3), conf$Ticker))

factor_specs<-list(
  list(
    factor_family="Momentum_PathQuality",
    proxy="DFA_Hurst_252d",
    formula="H = slope(log F(s) ~ log s); F(s)=RMS of linear-detrended cumulative-return profile over non-overlapping windows s (Peng 1994 DFA). Per-window detrending uses ONLY data <= sig_date (C1/C7).",
    lag_rule="price t-1 close; rolling 252d window Date<=sig_date (C1)",
    winsorization="cross-sectional 3std on z",
    neutralization="raw (cross-sectional z within KOSPI200 union KOSDAQ150)",
    standardization="cross-sectional z (C13 Z_Score_Aligned orientation)",
    economic_rationale="Hurst exponent H = long-range dependence / self-similarity of the return path (fractal geometry, Mandelbrot; R/S Hurst 1951; DFA Peng 1994). Thesis: H>0.5 persistent => momentum reliable; H<0.5 anti-persistent => momentum reverses/crashes. FALSIFIED in KR top-universe (see diagnostics).",
    weight_theta=0.0,
    references=list("Mandelbrot-Wallis 1969","Peng et al. 1994 (DFA)","Hurst 1951 (R/S)","Daniel-Moskowitz 2016 (momentum crashes)"),
    evidence_tier="C",
    redundancy_cluster_id="momentum_pathquality_NEW (orthogonal to momentum_cluster: |xsec corr| < 0.04)",
    source="new_designed",
    estimator_crosscheck=sprintf("DFA-252 vs R/S-252 cross-sectional cor = %.3f (moderate estimator agreement)", ev$dfa_rs_cor)
  ),
  list(
    factor_family="Momentum",
    proxy="M01_Mom_12_1 (baseline reference, computed from rawdata)",
    formula="prod(1+ret[t-252:t-21])-1",
    lag_rule="price t-1; 252d lookback skip 21d (C1)",
    winsorization="cross-sectional 3std",
    neutralization="raw cross-sectional z",
    standardization="cross-sectional z",
    economic_rationale="Classical 12-1 momentum. Reference baseline that the Hurst conditioning was meant to improve. It does NOT (a504 vs baseline paired t=0.33).",
    weight_theta=1.0,
    references=list("Jegadeesh-Titman 1993","Carhart 1997"),
    evidence_tier="B",
    redundancy_cluster_id="momentum_cluster",
    source="db_derived"
  )
)

diagnostics<-list(
  metric_type="canonical_screen (real-computation, contract build_benchmark_compare; NOT forge-authoritative)",
  rank_ic_chosen_a504=round(da$a504$rank_ic,4),
  icir_monthly_a504=round(da$a504$icir_monthly,3),
  icir_annualized_a504=round(da$a504$icir_annualized,3),
  harvey_t_rankic_nw3_a504=round(da$a504$harvey_t_nw3,2),
  subperiod_sign_stability_a504=round(da$a504$sign_stability,2),
  n_months_ic=da$a504$n_months,
  rank_ic_baseline=round(da$d_baseline$rank_ic,4),
  harvey_t_rankic_baseline=round(da$d_baseline$harvey_t_nw3,2),
  rank_ic_pure_hurst=round(da$c$rank_ic,4),
  harvey_t_pure_hurst=round(da$c$harvey_t_nw3,2),
  turnover_proxy_annual=round(g("a504","turnover_ann"),2),
  note="rank-IC weak (~0.015) and pure-Hurst rank-IC NEGATIVE (-0.0095). portfolio-alpha t below is the decisive screening number."
)

portfolio_alpha<-list(
  metric_type="canonical_screen (top25 EW long-only, 15bps delta cost, liq>=2e8, REAL KOSPI200_TR benchmark)",
  note="NOT forge-authoritative; forge build_bt_result would be required for graduation binding. These are screening reals.",
  a504_hurst_scaled_504d=list(port_alpha_t_nw3=round(g("a504","port_alpha_t_nw3"),3), IR=round(g("a504","IR"),3), net_active_ann=round(g("a504","alpha_ann"),4), net_sr=round(g("a504","net_sr"),3)),
  a_hurst_scaled_252d=list(port_alpha_t_nw3=round(g("a","port_alpha_t_nw3"),3), IR=round(g("a","IR"),3)),
  d_baseline_pure_momentum=list(port_alpha_t_nw3=round(g("d_baseline","port_alpha_t_nw3"),3), IR=round(g("d_baseline","IR"),3), net_active_ann=round(g("d_baseline","alpha_ann"),4), net_sr=round(g("d_baseline","net_sr"),3)),
  c_pure_hurst=list(port_alpha_t_nw3=round(g("c","port_alpha_t_nw3"),3), IR=round(g("c","IR"),3)),
  b_hurst_gated_reversal=list(port_alpha_t_nw3=round(g("b","port_alpha_t_nw3"),3)),
  e_additive_70mom_30hurst=list(port_alpha_t_nw3=round(g("e_additive","port_alpha_t_nw3"),3)),
  incremental_a504_vs_baseline=list(monthly_active_diff_mean=round(ev$delta_mean,5), paired_t=round(ev$delta_t,2),
       verdict="a504 NOT meaningfully > baseline (|t|=0.33 << 2). Hurst conditioning adds NO incremental alpha.")
)

mechanism_test<-list(
  description="Momentum rank-IC conditional on Hurst tercile — direct test of the thesis (high-H => stronger momentum).",
  momentum_ic_low_H=0.0179, momentum_ic_mid_H=0.0219, momentum_ic_high_H=0.0084,
  verdict="FALSIFIED: momentum IC is WEAKEST in high-Hurst names (0.0084, t=0.73), strongest in mid-H. Thesis predicted high_H >> low_H — opposite/null observed.",
  crash_check="Top-momentum-quintile fwd-return 5%-tail: high_H -22.3% vs low_H -18.6%. High-Hurst (persistent) names crash HARDER, not less — native-crash-filter premise also falsified."
)

orth<-ev$orth
orthogonality<-list(
  metric="avg cross-sectional Spearman corr (H vs momentum cluster)",
  H252_vs_M01=round(orth$H252_vs_M01,4), H252_vs_M08=round(orth$H252_vs_M08,4),
  H252_vs_M13=round(orth$H252_vs_M13,4), H126_vs_M01=round(orth$H126_vs_M01,4),
  H504_vs_M01=round(orth$H504_vs_M01,4),
  cluster_internal_check=list(M01_vs_M08=round(orth$M01_vs_M08,3), M01_vs_M13=round(orth$M01_vs_M13,3)),
  verdict="H is GENUINELY ORTHOGONAL to the momentum cluster (|corr|<0.04, target was <0.6). It is NOT a relabeled M01. But orthogonal != additive: it carries no incremental long-only alpha."
)

hurst_distribution<-list(
  mean_H=round(ev$hsum$mean_H,3), median_H=round(ev$hsum$med_H,3), sd_H=round(ev$hsum$sd_H,3),
  q10=round(ev$hsum$q10,3), q90=round(ev$hsum$q90,3),
  frac_persistent_H_gt_0p5=round(ev$hsum$frac_persistent,3),
  note="KR top-universe daily returns lean mildly anti-persistent (mean H=0.485, only 41% persistent) — consistent with short-horizon mean-reversion dominating the path."
)

challenge_flags<-list(
  list(id="RF-A-FALSIFIED", severity="HIGH", desc="Core thesis falsified by direct mechanism test: momentum IC weakest in high-H names; high-H names crash harder. Hurst conditioning adds no incremental alpha (a504 vs baseline paired t=0.33)."),
  list(id="RF-A3-clean", severity="INFO", desc="No recent-IC inflation; sign_stability=1.0 across 3 eras for a504/baseline (both weakly positive but flat)."),
  list(id="AX-007", severity="INFO", desc="single-sleeve long-only top-25: even baseline momentum PORT_t=1.57 (canonical_screen) — below graduation HARD 2.95. Cross-sectional-signal->portfolio translation is the binding limit, consistent with prior KR finding."),
  list(id="DATA-BMRET", severity="MEDIUM", desc="rawdata.parquet BM_Ret empty (known issue). Rebuilt benchmark from .cache/benchmark.parquet (real KOSPI200 TR) for canonical_screen; M08 also rebuilt with real daily BM. Documented, not silently absorbed.")
)

screen_route<-list(
  graduate_candidate=FALSE,
  route="DPL_FEATURE",
  rationale="Real-but-non-graduating AND non-additive. Pure-H has negative rank-IC standalone; H-scaled momentum is statistically identical to plain momentum. As an OVERLAY_CANDIDATE it fails (gating/additive forms dilute). Only residual value is as one orthogonal feature in a learned (DPL) model that can discover any weak non-linear interaction — but on this evidence the expected contribution is ~0. Recommend NO further single-sleeve pursuit.",
  measurement_graduation_tier="screening-tier (not capital). measurement-graduation 2-tier."
)

ap<-list(
  task_id="WT-D20260621_001",
  wt_type="discovery",
  as_of_date="2026-06-21",
  forecast_horizon="1M",
  selection_objective="rank_ic",
  selection_objective_note="Predictive-power selection only (rank_ic/icir). No sharpe/cagr/mdd used for factor selection (role_objective_guard).",
  status="ALPHA_DONE_NEGATIVE",
  status_note="Hypothesis FALSIFIED. Signal orthogonal but non-additive; mechanism empirically refuted. Routed to screening-tier DPL_FEATURE. AX-000 honest negative result.",
  hypothesis="Hurst-Conditioned Persistence-Quality Momentum (DFA H252 primary, R/S cross-check, A/B/C operationalizations)",
  alpha_definition="chosen emitted alpha = a504 (z_M01 * g(H504)) — best-of-Hurst variant, flagged screen-route. Baseline z_M01 retained for reference.",
  alpha_vector=alpha_vector,
  confidence_vector=confidence_vector,
  signal_matrix_ref=paste0("file://", file.path(OUT_A,"alpha_scores.parquet")),
  factor_specs=factor_specs,
  diagnostics=diagnostics,
  portfolio_alpha=portfolio_alpha,
  mechanism_test=mechanism_test,
  orthogonality=orthogonality,
  hurst_distribution=hurst_distribution,
  redundancy_cluster_id="momentum_pathquality_NEW",
  cor_vs_admitted_active="H vs momentum cluster |xsec corr|<0.04 (orthogonal); but additive value ~0",
  deflated_sharpe_ratio=list(value=round(ev$dsr_a504,3), baseline=round(ev$dsr_base,3),
     severity="advisory", note="hypothesis-driven A/B chain (n_trials=7 operationalizations), DSR diagnostic only per measurement-graduation 2026-06-10 (chain != sweep). Not a graduation gate here."),
  ax001_v2_note="N/A — offensive momentum-quality thesis, not a defensive factor.",
  cost_model_version="v2.4_kr_retail_15bps",
  screen_route=screen_route,
  challenge_flags=challenge_flags,
  method_shopping_log=list(candidates_tried=7,
    method_log=list(
      list(name="a_Hscaled_252", port_t=round(g("a","port_alpha_t_nw3"),2), selected=FALSE),
      list(name="b_Hgated_reversal", port_t=round(g("b","port_alpha_t_nw3"),2), selected=FALSE),
      list(name="c_pure_Hurst", port_t=round(g("c","port_alpha_t_nw3"),2), selected=FALSE),
      list(name="d_baseline_momentum", port_t=round(g("d_baseline","port_alpha_t_nw3"),2), selected=FALSE),
      list(name="a126_Hscaled_126", port_t=round(g("a126","port_alpha_t_nw3"),2), selected=FALSE),
      list(name="a504_Hscaled_504", port_t=round(g("a504","port_alpha_t_nw3"),2), selected=TRUE),
      list(name="e_additive_70_30", port_t=round(g("e_additive","port_alpha_t_nw3"),2), selected=FALSE)
    )),
  generated_by="alpha-research (Agent tool)",
  generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z")
)

write_json(ap, file.path(WT_DIR,"alpha_package_draft.json"), pretty=TRUE, auto_unbox=TRUE, na="null", digits=6)
cat("Wrote alpha_package_draft.json — alpha_vector n=", length(alpha_vector), "\n")

# also write alpha_validation.json + copy alpha_scores to canonical stage path
write_json(list(diagnostics=diagnostics, portfolio_alpha=portfolio_alpha,
  mechanism_test=mechanism_test, orthogonality=orthogonality, hurst_distribution=hurst_distribution,
  screen_route=screen_route),
  file.path(OUT_A,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, na="null", digits=6)
cat("Wrote alpha_validation.json\n")
