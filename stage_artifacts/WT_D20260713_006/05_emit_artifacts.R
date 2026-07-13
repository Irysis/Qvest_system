suppressMessages({library(data.table); library(arrow); library(jsonlite)})
setDTthreads(1); arrow::set_io_thread_count(2)
OUT <- "stage_artifacts/WT_D20260713_006"
P <- readRDS(file.path(OUT,"panels.rds"))
TR <- readRDS(file.path(OUT,"test_results.rds"))
RES<-TR$RES; SPL<-TR$SPL

# --- save merged analytic panel (event target + feature predictors) ---
mk <- function(fp,nm) fp[,.(Ticker,ym,feature=nm,suspect=susp,worst_decile=pred,E12=E,
                            log_size,liq_z,K200=fifelse(is.na(K200),0L,K200),KQ150=fifelse(is.na(KQ150),0L,KQ150))]
panel <- rbindlist(list(mk(P$F1,"benford"),mk(P$F2,"m1"),mk(P$F3,"delay"),mk(P$ST,"stack")), use.names=TRUE)
write_parquet(panel, file.path(OUT,"alpha_scores.parquet"))
cat("[saved] alpha_scores.parquet rows=",nrow(panel),"\n")

num <- function(x) if(is.null(x)||length(x)==0) NA else as.numeric(x)
mkres <- function(nm){ r<-RES[[nm]]; s<-SPL[[nm]]
  list(n=r$n, base_rate=round(r$base,5), worst_decile_n=r$n1, worst_decile_evrate=round(r$evr1,5),
       lift=round(r$lift,3), lift_wilson95=round(as.numeric(r$lift_wilson),3),
       lift_boot_ticker95=round(as.numeric(r$lift_boot),3),
       auc=round(num(r$auc["auc"]),4), auc_ci95=c(round(num(r$auc["lo"]),4),round(num(r$auc["hi"]),4)),
       or_raw=round(r$or_raw,3), or_ctrl=round(r$or_ctrl,3), or_ctrl_ci95=round(as.numeric(r$or_ctrl_ci),3),
       or_ctrl_p_clusterrobust=signif(r$or_ctrl_p,4),
       stability=list(pre2016=list(lift=round(num(s$pre2016$lift),3),or_ctrl=round(num(s$pre2016$or_ctrl),3),p=signif(num(s$pre2016$p),4),n=s$pre2016$n),
                      post2016=list(lift=round(num(s$post2016$lift),3),or_ctrl=round(num(s$post2016$or_ctrl),3),p=signif(num(s$post2016$p),4),n=s$post2016$n)))
}
results <- lapply(c("F1","F2","F3","ST"), mkres); names(results)<-c("benford_F1","m1_F2","delay_F3","stack")

verdict <- list(
  wt_id="WT-D20260713_006", fq_id="FQ-035", iteration="R22",
  prereg_sha256=readLines(file.path(OUT,"preregistration.sha256"))[1],
  verdict="CONFIG_SCOPED_NEGATIVE",
  stage="STAGE_1_PREDICTION_VALIDITY_ONLY",
  headline="Forensic stack does NOT clear the pre-registered event-prediction bar (no predictor: controlled OR p<0.05 full-sample AND pre/post-2016 stable). BUT delay(F3) is a size-robust, severe-event-specific sub-threshold signal (frontier open); Benford/m1/stack are flat nulls (terminate).",
  prereg_rule_outcome=list(
    predicts_holds=FALSE,
    reason="F1/F2/stack: controlled OR~1, p>0.6, AUC~0.51-0.52 (flat null). F3 delay: controlled OR 2.06 p=0.0745 (fails p<0.05 on power) + pre-2016 not estimable (delay coverage post-2016 only) => stability clause unmet.",
    bonferroni_x4_min_p=0.298),
  disposition=list(
    benford_F1="EVENT_PREDICTOR_TERMINATE (flat null; feature preserved for prior return-overlay use only)",
    m1_F2="EVENT_PREDICTOR_TERMINATE (flat null + sign-unstable pre/post; m1 retains OVERLAY_CANDIDATE return status from WT-D20260711_002)",
    stack="TERMINATE (dominated by two null features; dilutes delay)",
    delay_F3="CONFIG_SCOPED_NEGATIVE + FRONTIER_OPEN (size-robust extreme-tail late-filing signal; under-powered on union-target/decile config)"),
  size_disguise_check=list(
    concern="lift could be a small-cap base-rate artifact",
    resolution="F3 controlled OR (2.06) ~ raw OR (2.18): Size/tier/liq controls barely attenuate => NOT size-disguise. F1/F2 have no lift to disguise.",
    authoritative=TRUE),
  delay_event_type_decomposition=list(
    note="F3 delay worst-decile lift by event type (why union masks the signal)",
    Delisting=6.38, AdminStock=4.24, UnfaithfulDisc=3.82, LongHalt_transient=1.80,
    interpretation="Signal is severe-event-specific; transient LongHalt (largest base) dilutes union lift 2.07."),
  tail_monotonicity=list(continuous_days_late_OR_perSD=1.074, continuous_p=0.396,
    top_quintile_OR=1.363, top_quintile_p=0.342,
    interpretation="Signal lives in the EXTREME tail (top decile), NOT monotonic. Widening threshold dilutes => power must come from severity-restricted target / longer window / larger filer universe, not wider threshold."),
  results=results,
  next_probe=list(
    P1="Severity-restricted target: pre-register + re-run delay(F3) extreme tail vs target={Delisting U AdminStock U UnfaithfulDisc} (drop transient LongHalt). D1 predicts 4-6x tail lift; may clear p<0.05 with the same tail. NEW pre-registered round (do NOT post-hoc this round).",
    P2="Power via coverage not threshold: keep extreme top-decile; grow n by (a) 24m forward window, (b) pooling delay across full DART filing universe (delay computable for all filers, not just K200∪KQ150), (c) discrete-time delisting-hazard model with continuous days-late x severity.",
    P3="Event-label PIT hardening: obtain actual designation announcement dates (vs rawdata flag onset) to rule out any backdating look-ahead before any capital use."),
  two_stage_discipline="Stage-2 (exclusion filter redesign) NOT opened — pre-registered bar not cleared. Severity-restricted re-run is a NEW pre-registered round, not a post-hoc extension of this frozen prereg."
)
write_json(verdict, file.path(OUT,"verdict.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)
cat("[saved] verdict.json\n")

validation <- list(
  wt_id="WT-D20260713_006", iteration="R22", metric_type="event_prediction_diagnostic",
  canonical_port_t_nw_lag3=NULL,
  canonical_port_t_reason="N/A — this is an event-classification study (feature->12m adverse-event lift), not a top-25 long-only portfolio screen. No portfolio-alpha computed by design (2-stage prereg: prediction validity only).",
  availability_audit=list(
    rawdata_flags=list(
      UnfaithfulDisc=list(exists=TRUE, coverage="2009+", monthly_onsets=843, note="binary state flag; onset=monthly 0->1"),
      AdminStock=list(exists=TRUE, coverage="1990+", monthly_onsets=1649),
      TradingHalt=list(exists=TRUE, coverage="1993+", values="0/1/2 state", long_halt_onsets_ge20d=2788),
      Delisting=list(exists="DERIVED (last-obs < data_end-180d, no relisting; C6)", events=1105,
        survivorship_caveat="rawdata (K200/KQ150 support universe) may under-retain fully-delisted micro-caps => fewer events observed => HARDER to detect => CONSERVATIVE for a positive verdict")),
    features=list(
      benford_FSD=list(source="WT-D20260713_002 F-B_Benford_FSD", window="2009-06..2025-06", tickers=728),
      m1_obfuscation=list(source="WT-D20260711_002 signal_panel.rds (m1 sentence length)", window="2011-04..2025-04", tickers=667, caveat="alpha_scores.parquet is single-month(202504); longitudinal panel is signal_panel.rds"),
      delay=list(source="WT-D20260713_001 F-B (days late vs 90d deadline)", window="2010-04..2025-03", tickers=670,
        coverage_caveat="effectively post-2016 (pre-2016 worst-decile events <10 => stability clause not estimable pre-2016)"))),
  pit=list(feature_month="t", event_window="[t+1,t+12]", censor="decision months t>202507 dropped (12m forward observable)",
           label_pit_caveat="flag onset = rawdata designation date (forward-looking). If rawdata backdates AdminStock to cause-date, mild look-ahead would INFLATE predictability; direction noted, verdict largely null so robust."),
  n_trials=4, selection_type="sweep(4 enumerated)", multiple_testing="Bonferroni x4 => none<0.05",
  dsr_context="metric is AUC/OR not Sharpe; DSR-analog = multiple-testing correction (reported). No candidate near threshold post-correction.",
  prereg_sha256=readLines(file.path(OUT,"preregistration.sha256"))[1]
)
write_json(validation, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)
cat("[saved] alpha_validation.json\n")
