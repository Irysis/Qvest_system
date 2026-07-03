suppressMessages({library(jsonlite); library(data.table); library(arrow)})
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
B <- readRDS("/tmp/m33_base.rds"); res<-B$res_base; S<-B$S_base
G <- readRDS("/tmp/m33_grad.rds")
IC <- readRDS("/tmp/m33_ic.rds")
ortho <- readRDS("/tmp/m33_ortho.rds")
rank_ic <- mean(IC$ic,na.rm=TRUE); icir<-rank_ic/sd(IC$ic,na.rm=TRUE)
n_ic<-sum(!is.na(IC$ic)); ic_t<-rank_ic/(sd(IC$ic,na.rm=TRUE)/sqrt(n_ic))

latest <- max(S$Date)
lat <- S[Date==latest & !is.na(score)]
av <- setNames(round(lat$score * 0.0, 6), lat$Ticker)
score_vec <- setNames(round(lat$score,4), lat$Ticker)
conf <- setNames(rep(0.15, nrow(lat)), lat$Ticker)

ortho_row <- list()
for(fn in c("M01_Mom_12_1","M04_Mom_1","M11_ST_Reversal","M29_Mom_5d","M30_Mom_10d","L39_Overnight_Spread")){
  v<-ortho[[fn]]; v<-v[is.finite(v)]; ortho_row[[fn]]<-round(mean(v),3)
}

pkg <- list(
  task_id="WT-D20260621_008",
  as_of_date="2026-05-29",
  forecast_horizon="1M",
  wt_type="discovery",
  hypothesis_title="Overnight Return Momentum (M33)",
  metric_type="canonical_screen",
  selection_objective="rank_ic",
  verdict="SCREEN_ROUTE_NONE",
  verdict_detail="Clean negative. Real, orthogonal NEW construct (overnight-leg momentum) but NO harvestable long-only alpha: top-decile flat, PORT_t -0.57 (best-of-grid +0.46, hurdle 2.95). Not graduate-candidate; not even screen-route (no signal in any leg/decile to overlay/FR/DPL). One campaign data point, NOT a structural limit.",
  alpha_vector=as.list(av),
  ir_score_vector=as.list(score_vec),
  confidence_vector=as.list(conf),
  signal_matrix_ref="stage_artifacts/WT_WT-D20260621_008/alpha_scores.parquet",
  alpha_scores_artifact="stage_artifacts/WT_WT-D20260621_008/alpha_scores.parquet (Date x Ticker x score time-series, 80078 rows, 256 dates, 824 tickers)",
  codex_round=list(
    stance="REVISE", veto_flag=FALSE, model="gpt-5.5 xhigh",
    summary="Codex confirmed no-harvest verdict directionally; REVISE for auditability not verdict. 7 concerns: C1(scores snapshot)=FIXED, C2(AX-008/missing risk-opt)=PARTIAL+REBUTTAL(role-boundary), C3(no-softening)=ACCEPT, C4(liq leakage)=REBUTTAL(0 sub-2e8 audited), C5(turnover unit)=ACCEPT(1141pct two-way corrected), C6(repro code)=ACCEPT(shipped), C7(grid wording)=ACCEPT. See challenge_note.md.",
    escalate_to_qlead=FALSE,
    escalate_reason="No PIT-C1 lockbox/lookahead violation; AX hard FAIL=0; stance REVISE not REJECT; veto false."
  ),
  factor_specs=list(list(
    factor_family="Momentum_Microstructure",
    proxy="Overnight-leg cumulative return momentum (IR_score)",
    formula="z_xs(SUM overnight_d over (t-126,t-21]) - 0.5*z_xs(SUM intraday_d last 21d); overnight_d=ln(Open_t/Close_{t-1}), intraday_d=ln(Close_t/Open_t)",
    lag_rule="price t-1; overnight uses Close_{d-1} and Open_d; eligibility/liquidity t-1 snapshot",
    winsorization="cross-sectional [1pct,99pct] per sig_date",
    neutralization="none (pure microstructure; cross-sectional z only)",
    economic_rationale="Lou-Polk-Skouras (2019) overnight/intraday tug-of-war: overnight returns persist due to institutional/clientele demand concentrated at open; intraday mean-reverts (retail). Hypothesis: overnight sub-component is TOP-concentrated where total-return momentum is not. TESTED FALSE in KR: the 09:00 single call-auction does not concentrate informed flow the way the US continuous open does; overnight leg carries no cross-sectional long-only predictive content.",
    redundancy_cluster_id="overnight_microstructure (distinct from total-return momentum M01/M04/M29/M30 and from L39 single-day negated gap)",
    weight_theta=1.0,
    references=c("Lou, Polk, Skouras (2019) JFE: overnight versus intraday expected returns","Berkman, Koch, Tuttle, Zhang (2012) JFQA: overnight returns","Bogousslavsky (2021): intraday/overnight return dynamics")
  )),
  diagnostics=list(
    rank_ic=round(rank_ic,4),
    rank_ic_metric_type="advisory",
    icir=round(icir,3),
    rank_ic_t=round(ic_t,2),
    portfolio_alpha_t_nw_lag3=round(res$portfolio_alpha_t_nw_lag3,3),
    portfolio_alpha_t_metric_type="canonical_screen (forge-authoritative style, decision metric)",
    net_sr=round(res$net_sr,3),
    information_ratio=round(res$information_ratio,3),
    alpha_annualized=round(res$alpha_annualized,4),
    turnover_proxy=round(res$turnover_annual,2),
    turnover_pct_twoway=round(res$turnover_annual*100,0),
    turnover_pct_oneway=round(res$turnover_annual*100/2,0),
    turnover_note="turnover_annual=11.41 is two-way (sum|dw|, buy+sell) = 1141pct, which EXCEEDS the 1100pct two-way screening cap. One-way = 570pct. Moot: PORT_t fails hard regardless. Corrected per Codex C5 (prior 'under cap' claim was wrong).",
    oos_retention_v2=round(G$oos_ret,3),
    oos_retention_note="2.54 is an artifact of a near-zero IS denominator (ratios 2.5/12/-11.8 across splits); NOT evidence of robustness - with no signal the ratio is undefined.",
    calmar=round(G$calmar,3),
    subperiod_stability=round(G$subperiod_stab,2),
    subperiod_era_srs=round(G$sub$sr,3),
    monotonicity=0.0,
    monotonicity_note="decile active-return monotonicity absent: D10 t=0.15, D10-D1 spread t=0.35, D10-D9 gap negative.",
    post_neutralization_ic=NA
  ),
  decile_concentration=list(
    top_decile_active_t=0.149,
    d10_minus_d9_gap_monthly=-0.00047,
    d10_minus_d1_spread_monthly=0.00131,
    long_short_d10_d1_t=0.354,
    concentration_verdict="FLAT - neither TOP-concentrated nor short/mid-concentrated. No decile carries significant active return. Even the best decile (D6 t=0.45) is noise. Unlike C23/C24/C25 (real signal in short/mid), M33 has no exploitable signal anywhere.",
    microstructure_check="net_SR ~0 after 15bps; edge is NOT a tradeable bid-ask-bounce artifact because there is no edge. Winsor+skip+ADV>=2e8+coverage>=0.8 guards applied; signal flat regardless. Turnover 1141pct two-way (570pct one-way) brushes/exceeds the 1100pct two-way screening cap - flagged, but moot (PORT_t fails hard).",
    liquidity_audit="Backtest CLEAN under 2e8 floor: 0 top-20 obs sub-2e8, 0 adv-NA bypass (adv computed for 100pct of eligible obs). canonical_screen_bt applies filter BEFORE top-N (line 54-58). See liquidity_audit.json. Rebuts Codex C4 (which reconstructed top-20 without the pre-filter)."
  ),
  orthogonality=ortho_row,
  orthogonality_basis="cross-sectional Spearman, Z_Score_Aligned (C13), NW-month-averaged over 256 months",
  orthogonality_verdict="GENUINELY ORTHOGONAL/NEW construct: |corr|<target for all (M01 0.196, M04 0.345, M11 0.174, M29 0.174, M30 0.245; L39 -0.378 = sign+horizon flip confirmed). But orthogonal != profitable (measurement-graduation §6): a clean novel sleeve with no PORT_t is not book-relevant.",
  grid_sweep=list(
    n_cells_total=54,
    n_cells_run=26,
    n_cells_run_note="22 of 54 via full sweep (process killed at cell 22 - OneDrive paging/memory) + 4 bracketing single-config runs (L189 and L126/skip21). Coverage spans all L,skip,lambda,top_n extremes.",
    port_t_max_over_run=0.464,
    port_t_max_cell="L=189 skip=21 lambda=0 top_n=25 (argmax of sweep, DSR-deflated meaningless)",
    port_t_base=-0.565,
    cells_port_t_ge_2_95=0,
    lambda_effect="intraday-reversal subtraction (lambda>0) consistently HURTS (every lambda>0 cell negative); pure overnight momentum (lambda=0) hovers at zero.",
    selection_type="sweep (54-cell grid) - DSR HARD if argmax-selected; reported as sensitivity surface, BASE pre-registered.",
    grid_completeness_note="26 of 54 cells run (22 via full sweep before process kill at cell 22 from OneDrive paging/memory + 4 bracketing single-config runs). The 26 cells span ALL parameter extremes (L 63/126/189, skip 0/5/21, lambda 0/0.5/1.0, top_n 20/25); every one has PORT_t<0.5. Conclusion robust; this is NOT a fully-deflated exhaustive grid audit (per Codex C7). DSR deflation moot: argmax PORT_t +0.46 << 2.95.",
    dsr_ledger="argmax-cell PORT_t=0.464 (net_SR 0.07); even pre-deflation it misses 2.95 by ~6x, so any DSR penalty is academic."
  ),
  hard_gates=list(
    portfolio_alpha_t_nw_2_95=list(value=round(res$portfolio_alpha_t_nw_lag3,3), pass=FALSE, severity="hard"),
    oos_retention_0_7=list(value=round(G$oos_ret,3), pass="undefined (near-zero IS denom)", severity="hard"),
    calmar_0_64=list(value=round(G$calmar,3), pass=FALSE, severity="hard")
  ),
  open_data_quality=list(
    open_coverage_eligible=0.99937,
    open_na_frac_eligible=0.00063,
    decomposition_max_err=2.8e-16,
    decomposition_rows_gt_1e6=70,
    decomposition_total_rows=10378856,
    corr_ret_c2c=1.0,
    verdict="Open data RELIABLE for overnight construction. 99.94pct coverage on K200|KQ150; overnight+intraday=log(1+Ret) to machine precision except 70/10.4M corporate-action edge rows (caught by |overnight|>0.6 guard). KR open prices NOT a blocker."
  ),
  honest_risks_realized=list(
    "RISK 2/3 CONFIRMED: KR 09:00 single call-auction does not transfer the Lou-Polk US-continuous-open mechanism (kr_fit=4 hypothesis FALSIFIED).",
    "RISK 1 CONFIRMED: published US overnight effect does not yield KR long-only alpha at K200|KQ150 level (capacity/structure).",
    "measurement-graduation §3 rank-IC-vs-PORT_t trap: here BOTH flat/negative, consistent (no false-positive).",
    "NOT a structural limit per AX-000 amended - one data point in ongoing momentum-hunt campaign."
  ),
  method_shopping_log=list(candidates_tried=1, parallel_exec=FALSE,
    method_log=list(list(name="M33_OvernightMom_IR", rank_ic=round(rank_ic,4), selected=TRUE, note="single construct per spec; lookback grid is sensitivity not method-shop"))),
  challenge_flags=list(
    "CF-1 [HIGH]: PORT_t -0.57 (BASE), best-of-grid +0.46 << 2.95 hurdle. No graduate-candidate.",
    "CF-2 [MEDIUM]: signal FLAT across all deciles (not even short/mid like prior campaign concepts) - no screen-route target.",
    "CF-3 [INFO]: construct is genuinely orthogonal/novel (all |corr|<target) but orthogonal != profitable (§6).",
    "CF-4 [INFO]: 28/54 grid cells not run (process killed); 26 run cover all parameter extremes, all <0.5 PORT_t. Pattern robust."
  )
)
final_path <- "qepm/mailbox/worktask/WT-D20260621_008/alpha_package.json"
write_json(pkg, final_path, pretty=TRUE, auto_unbox=TRUE, na="null", digits=8)
cat("FINAL alpha_package.json WRITTEN | PORT_t base:", round(res$portfolio_alpha_t_nw_lag3,3),
    "| rank_ic:", round(rank_ic,4),"\n")

# lineage (after write_json, per L-194)
tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id="WT-D20260621_008",
    package_type="alpha_package",
    method_selected="M33 Overnight-leg return momentum (IR_score) - canonical_screen_bt",
    input_file_paths=c(".cache/rawdata.parquet", ".cache/benchmark.parquet",
      "stage_artifacts/WT_WT-D20260621_008/alpha_scores.parquet"))
  cat("lineage recorded\n")
}, error=function(e) cat("lineage skipped:", conditionMessage(e),"\n"))
