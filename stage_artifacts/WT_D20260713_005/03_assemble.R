# R21 assemble: alpha_package.json + alpha_validation.json + combined alpha_scores.parquet
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT<-"stage_artifacts/WT_D20260713_005"; MB<-"qepm/mailbox/worktask/WT_D20260713_005"
armA<-fromJSON(file.path(OUT,"armA_crisis_tilt_summary.json"))
armB<-fromJSON(file.path(OUT,"armB_ivol_summary.json"))
red<-tryCatch(fromJSON(file.path(OUT,"armB_redundancy.json")),error=function(e)NULL)

# combined alpha_scores.parquet (armB IVOL scores + armA weights, labelled)
scB<-as.data.table(read_parquet(file.path(OUT,"armB_scores.parquet")))
wA<-as.data.table(read_parquet(file.path(OUT,"armA_weights.parquet")))
write_parquet(scB, file.path(OUT,"alpha_scores.parquet"))   # canonical alpha_scores = arm B factor scores

# as_of alpha_vector = IVOL_K standardized scores at last sig_date
as_of<-max(scB[arm=="ivolK",Date]); av<-scB[arm=="ivolK" & Date==as_of]
alpha_vector<-setNames(as.list(round(av$score,4)), av$Ticker)
conf<-setNames(as.list(rep(0.25,nrow(av))), av$Ticker)   # low confidence: screen-tier negative

diagnostics<-list(
  canonical_port_t_nw_lag3 = armB$arm_K_ivolK$portfolio_alpha_t_nw_lag3,   # arm B standalone (canonical)
  canonical_port_t_pvalue  = armB$arm_K_ivolK$portfolio_alpha_t_pvalue,
  canonical_n_months       = armB$arm_K_ivolK$n_months,
  rank_ic                  = armB$arm_K_ivolK$rank_ic$rank_ic,
  icir                     = armB$arm_K_ivolK$rank_ic$icir,
  harvey_t_stat            = armB$arm_K_ivolK$rank_ic$harvey_t,
  diag_ew_universe_port_t  = armB$arm_K_ivolK$diag_ew_universe_port_t,
  diag_ew_universe_post2017_t = armB$arm_K_ivolK$diag_ew_universe_post2017_t,
  armB_estimator_marginal_paired_nw_t = armB$estimator_marginal$paired_nw_t,
  armB_prediag_rank_corr_mean = armB$prediag_ranking_corr$mean_rho,
  armA_base_port_t = armA$arms$base$port_t,
  armA_K_port_t    = armA$arms$armA_K$port_t,
  armA_kalman_marginal_KvsO_nw_t = armA$paired$K_vs_O_kalman_marginal$nw_t,
  armA_crisis_tilt_KvsBase_crisis_nw_t = armA$paired$K_vs_base_crisis$nw_t,
  armA_crisis_months_n = armA$paired$K_vs_base_crisis$n,
  armA_mdd_relief = armA$ax001v2_conditional$mdd_relief,
  armA_placebo_shift_nw_t = armA$paired$placebo_vs_base_full$nw_t)

factor_specs<-list(
  list(factor_family="LowRisk_Residual", proxy="IVOL_Kalman",
    formula="60d sd of (Ret_d - beta_kalman_t*BM_Ret_d), month-end beta constant over window",
    lag_rule="daily t-1; beta dlmFilter filtered value only", winsorization="3std",
    neutralization="none (cross-sectional z of -IVOL)", economic_rationale="low idiosyncratic-vol premium (Ang-Hodrick-Xing-Zhang 2006, KR variant)",
    weight_theta=0.0, references=c("Ang-Hodrick-Xing-Zhang 2006","R19 WT-D20260713_003"),
    verdict="config-scoped negative — PORT_t -1.58; estimator-indifferent (rank corr 0.999 vs OLS); redundant with D35_RealVol_63d |rho|0.97"),
  list(factor_family="Defense_Construction", proxy="crisis_conditional_lowbeta_tilt(Kalman)",
    formula="within STR_1715 top-20 sleeve, crisis months tilt w_base×sqrt(1+0.5*z(-beta_kalman))",
    lag_rule="regime pre-holding-month (C5); beta filtered value", winsorization="n/a",
    neutralization="within-sleeve reweight only (cash overlay invariant)", economic_rationale="crisis-conditional beta de-risking within held names (AX-001v2 defensive)",
    weight_theta=0.0, references=c("AX-001v2","R19 crisis_active_t 1.935"),
    verdict="config-scoped negative — Kalman marginal insignificant (K-vs-O NW_t 0.99); crisis benefit weak/small-sample (NW_t 1.27, n=18); MDD relief 0.0002"))

challenge_flags<-c(
  "SC3 CONFIRMED: arm B IVOL redundant with existing LowRisk (D35_RealVol_63d |rho|0.97, D01_IdioVol/R12 0.80) — not novel",
  "arm B IC->PORT_t wall: rank-IC 0.049 harvey_t 4.57 (advisory good) but PORT_t -1.58 (authoritative negative)",
  "SC1: arm A crisis benefit small-sample (regime-crisis n=18); crisis NW_t 1.27 not significant",
  "Kalman estimator INERT across all 3 risk-consumption channels (R19 low-beta factor / arm A tilt / arm B IVOL): estimator washes out (residual idiosyncratic-dominated) + low-beta = small-cap negative-alpha style + book already de-risks via cash overlay (SC4)",
  "SC2: placebo shift-12m tilt NEGATIVE (NW_t -1.16) -> arm A tiny crisis effect is not a time-invariant style artifact, but too small to matter")

pkg<-list(task_id="WT-D20260713_005", as_of_date=as.character(as_of), forecast_horizon="1M",
  wt_type="discovery", alpha_vector=alpha_vector, confidence_vector=conf,
  signal_matrix_ref="stage_artifacts/WT_D20260713_005/alpha_scores.parquet",
  factor_specs=factor_specs, diagnostics=diagnostics,
  selection_objective="canonical_port_t", n_trials=4, selection_type="sweep",
  verdict="BOTH ARMS config-scoped negative (frontier marked). Kalman accuracy does not transfer to risk-consumption.",
  challenge_flags=challenge_flags)
write_json(pkg, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, null="null", digits=6)

# alpha_validation.json
val<-list(wt_id="WT-D20260713_005", fq_id="FQ-034",
  verdict_lexicon="config-scoped negative + frontier (both arms). next_probe>=2 per arm.",
  arm_A=list(finding="within-sleeve crisis low-beta tilt adds ~0 to book",
    base_port_t=armA$arms$base$port_t, K_port_t=armA$arms$armA_K$port_t, O_port_t=armA$arms$armA_O$port_t,
    kalman_marginal_KvsO_nw_t=armA$paired$K_vs_O_kalman_marginal$nw_t,
    crisis_tilt_KvsBase_full_nw_t=armA$paired$K_vs_base_full$nw_t,
    crisis_tilt_KvsBase_crisis_nw_t=armA$paired$K_vs_base_crisis$nw_t, crisis_n=armA$paired$K_vs_base_crisis$n,
    placebo_shift12m_nw_t=armA$paired$placebo_vs_base_full$nw_t,
    mdd_relief=armA$ax001v2_conditional$mdd_relief,
    ax001v2_regime_crisis_active=list(base=armA$ax001v2_conditional$base_regime_crisis_active,K=armA$ax001v2_conditional$K_regime_crisis_active),
    scoring="AX-001v2 conditional (full-period SR not used as reject)",
    next_probe=c("crisis-conditional tilt with ORTHOGONAL defensive signal (quality/low-distress) not low-beta (book already low-beta via M08+overlay)",
                 "test tilt on OFFENSE sleeve/non-defensive book where low-beta not saturated")),
  arm_B=list(finding="Kalman-residual IVOL = estimator-indifferent + redundant + negative",
    K_port_t=armB$arm_K_ivolK$portfolio_alpha_t_nw_lag3, O_port_t=armB$arm_O_ivolO$portfolio_alpha_t_nw_lag3,
    estimator_marginal_nw_t=armB$estimator_marginal$paired_nw_t,
    prediag_rank_corr=armB$prediag_ranking_corr,
    rank_ic_advisory=armB$arm_K_ivolK$rank_ic,
    ic_port_t_wall="rank-IC 0.049 harvey_t 4.57 advisory-good but PORT_t -1.58 authoritative-negative",
    redundancy_vs_lowrisk=red,
    next_probe=c("consume residual-vol as OVERLAY_CANDIDATE feature (crowding/exclusion) not standalone long factor",
                 "test IVOL INNOVATION (dIVOL surprise) not level — less redundant with D35_RealVol_63d")),
  meta_conclusion="Kalman beta-accuracy edge (realized-beta RMSE -10.3%, R19) is INERT across 3 risk-consumption channels. Binding wall: (a) residual idiosyncratic variance dominates -> estimator washes out (rank corr 0.999), (b) low-beta = small-cap negative-alpha style (R19 ~91% OTHER tier), (c) book already de-risks via cash overlay in crisis.",
  universe_comparison="KR_top342 only (default). ICIR not <0.15 attenuation case requiring v2; both arms clearly negative on cap-w authoritative + EW-universe diag (armB EWuni -2.19).",
  cost_model_version="v2.4_kr_retail_15bps",
  rawdata_pin_tag="RAWDATA_mtime20260713-000411_size421258666")
write_json(val, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, null="null", digits=6)

# lineage
tryCatch({source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(task_id="WT-D20260713_005", package_type="alpha_package",
    method_selected="R21 dual-arm: crisis-conditional lowbeta tilt + kalman-residual IVOL (both config-scoped negative)",
    input_file_paths=c("stage_artifacts/WT_D20260713_003/beta_kalman_tuned.parquet",
      "stage_artifacts/WT_D20260713_003/beta_monthly.parquet",".cache/RAWDATA.parquet"))
}, error=function(e) cat("lineage skip:",conditionMessage(e),"\n"))
cat("[assemble] DONE -> alpha_package.json + alpha_validation.json + alpha_scores.parquet\n")
