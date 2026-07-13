suppressMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
OUT <- "stage_artifacts/WT_D20260713_007"
S  <- readRDS(file.path(OUT,"target.rds"))
TR <- readRDS(file.path(OUT,"test_results.rds"))
rh <- TR$RES$hardened; rf <- TR$RES$pureflag; sp <- TR$SPL$hardened; hz <- TR$HZ

# ---- alpha_scores.parquet (event-prediction panel; NOT a portfolio) ----
Fh <- copy(S$Fhard)
scores <- Fh[, .(Ticker, ym, date=as.Date(sprintf("%d-%02d-01", ym%/%100, ym%%100)),
                 delay_suspect=susp, decile=dec, worst_decile_pred=pred,
                 severe_event_fwd12m=E, size_z, liq_z, K200, KQ150)]
write_parquet(scores, file.path(OUT,"alpha_scores.parquet"))

# ---- label-hardening cross table ----
au <- S$au
gm <- au[match_type=="hardened", gap_m]
hard_tbl <- list(
  au_onsets_total = nrow(au),
  covered_by_disc_ck = sum(au$covered),
  hardened_matched_within_12m = sum(au$match_type=="hardened"),
  gap_months_flag_minus_designation = list(
    min=min(gm), q25=as.numeric(quantile(gm,.25)), median=median(gm), mean=round(mean(gm),3),
    q75=as.numeric(quantile(gm,.75)), max=max(gm),
    share_flag_leads_lookahead_risk=round(mean(gm<0),3),
    share_same_month=round(mean(gm==0),3),
    share_flag_lags_safe=round(mean(gm>0),3)),
  interpretation = "Flag onset aligns to actual public designation month in 89% of matchable cases (median gap 0). No systematic backdating -> RAWDATA flag onset is PIT-clean as a designation-date proxy. Coverage is low (36/2492) because disc_ck is a survivor-biased 348-stock archive; non-covered events retain flag onset. Because matched hardening months equal flag months in ~89% of cases, hardened target == pure-flag target (identical base rate & event count) -> hardening confirms PIT cleanliness but does not move the verdict."
)

# ---- alpha_validation.json ----
val <- list(
  wt_id="WT-D20260713_007", fq_id="FQ-036", iteration="R23",
  prereg_sha256=readLines(file.path(OUT,"preregistration.sha256"))[1],
  study_type="event_prediction_validity_stage1",
  note="This is a discrete-event prediction study (Stage 1), NOT a portfolio. canonical_port_t / SR / weights are N/A by construction (no portfolio formed). Selection objective = controlled residual OR on a pre-registered severe-event target.",
  target="severe adverse event onset {Delisting U AdminStock-designation U UnfaithfulDisc-designation} in forward [t+1,t+12]; transient LongHalt excluded",
  feature="F3 filing delay worst decile (FROZEN R22 threshold)",
  n_obs=rh$n, base_rate=round(rh$base,5), worst_decile_n=rh$n1, worst_decile_events=rh$x1,
  primary_hardened=list(
    lift=round(rh$lift,3), lift_wilson95=round(rh$lift_wilson,3), lift_bootTicker95=round(rh$lift_boot,3),
    auc=round(as.numeric(rh$auc["auc"]),4), auc_ci95=round(as.numeric(rh$auc[c("lo","hi")]),4),
    or_raw=round(rh$or_raw,3), or_ctrl=round(rh$or_ctrl,3), or_ctrl_ci95=round(rh$or_ctrl_ci,3),
    or_ctrl_p_clusterrobust=round(rh$or_ctrl_p,5)),
  robustness_pureflag=list(or_ctrl=round(rf$or_ctrl,3), or_ctrl_p=round(rf$or_ctrl_p,5),
    note="identical to hardened (hardening did not move target)"),
  stability=list(
    pre2016=list(estimable=sp$pre2016$estimable, worst_decile_n=sp$pre2016$n1, events=sp$pre2016$ev1,
      note="NOT estimable: delay feature coverage is post-2016-heavy; <5 pre-2016 worst-decile events"),
    post2016=list(estimable=sp$post2016$estimable, lift=round(sp$post2016$lift,2),
      or_ctrl=round(sp$post2016$or_ctrl,3), p=round(sp$post2016$p,5),
      note="all signal lives post-2016 (alpha-decay regime); temporal robustness UNESTABLISHED not disproven")),
  aux_delisting_hazard=list(or_per_sd_continuous_dayslate=round(hz$or,3), p=round(hz$p,4), delist_hits=hz$n_del,
    note="continuous days-late does NOT predict delisting (p=0.62). Signal is EXTREME-TAIL concentrated, NOT monotonic (confirms R22)."),
  fragility=list(
    distinct_tickers_carrying_worst_decile_events=6,
    events_per_ticker=c("A016790"=12,"A001570"=11,"A290510"=11,"A036490"=7,"A084990"=5,"A001440"=1),
    monthly_overlap_note="12-month hold => one late-filing episode generates up to 12 monthly 'events' for the same firm => 47 monthly hits reduce to ~6 independent company-episodes",
    leave_one_ticker_out="removing ANY of {A001570, A016790, A290510} pushes controlled OR p>=0.05 (3/6 event-tickers individually decisive)",
    cluster_robust_validity="cluster-robust SE requires many clusters; with 6 event-carrying clusters the nominal p=0.011 is anti-conservative / not trustworthy",
    placebo_month_permuted_or=list(median=0.781, q99=1.365, p_ge_obs=0,
      note="placebo confirms the association is not a within-month artifact, but does not rescue the few-cluster problem")),
  label_hardening=hard_tbl,
  per_type_worst_decile_lift=list(Delisting=6.38, AdminStock=4.24, UnfaithfulDisc=3.82,
    note="identical to R22 D1 decomposition -> pipeline internal-consistency confirmed"),
  selection_objective="controlled_residual_or_severe_event",
  n_trials=1, selection_type="chain",
  challenge_flags=c(
    "FRAGILITY_HIGH: 47 worst-decile hits = ~6 company-episodes; ticker-bootstrap CI [0.95,7.25] includes 1; LOO 3/6 kill significance; cluster-robust p invalid at 6 clusters",
    "TEMPORAL: all signal post-2016; pre-2016 non-estimable -> robustness unestablished",
    "NON_MONOTONIC: continuous days-late flat (p=0.62); signal only in extreme tail",
    "UNIVERSE_POWER: K200uKQ150 large-caps rarely file late -> too few late-filer episodes; proper power needs full DART filer universe"))
write_json(val, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)
cat("[05] alpha_scores.parquet rows:", nrow(scores), " + alpha_validation.json written\n")
