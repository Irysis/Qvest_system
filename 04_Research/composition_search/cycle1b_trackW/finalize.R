# =============================================================================
# finalize.R — Track W: merge results, deltas vs baseline, IS-only selection,
#   OOS non-degradation confirm, ALIVE/CLOSED verdict, DSR diagnostics,
#   weighting_results.{csv,json} + DONE_TRACKW marker.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
TRACKW_DIR <- file.path(PROJECT_ROOT, "04_Research/composition_search/cycle1b_trackW")
INT_DIR <- file.path(TRACKW_DIR, "intermediate")

res <- rbindlist(lapply(c("S1","S2","S3","B"), function(s)
  fread(file.path(INT_DIR, sprintf("results_%s.csv", s)))), fill = TRUE)

baseline_id <- c(S1 = "W01", S2 = "W01", S3 = "W01", B = "B03")
res[, is_baseline := method_id == baseline_id[substrate]]

bl <- res[is_baseline == TRUE,
          .(substrate, bl_is_sr = is_net_sr, bl_oos_sr = oos_net_sr,
            bl_full_sr = full_net_sr, bl_full_mdd = full_mdd, bl_is_port_t = is_port_t_nw3)]
res <- merge(res, bl, by = "substrate")
res[, d_is_sr   := is_net_sr  - bl_is_sr]
res[, d_oos_sr  := oos_net_sr - bl_oos_sr]
res[, d_full_sr := full_net_sr - bl_full_sr]
res[, d_full_mdd_pp := (full_mdd - bl_full_mdd) * 100]
res[, alive_a := d_is_sr >= 0.10]
res[, alive_b := d_oos_sr >= 0]
res[, alive_c := d_full_mdd_pp <= 2]
res[, alive_all := alive_a & alive_b & alive_c & !is_baseline]

# IS-only selection per substrate (argmax IS net SR, tie-break IS PORT_t)
sel_rows <- res[, .SD[order(-is_net_sr, -is_port_t_nw3)][1], by = substrate]
sel_rows[, selected_is := TRUE]

verdicts <- list()
for (s in unique(res$substrate)) {
  rs <- res[substrate == s]
  best <- sel_rows[substrate == s]
  challengers <- rs[is_baseline == FALSE]
  alive_any <- any(challengers$alive_all, na.rm = TRUE)
  verdicts[[s]] <- list(
    baseline = baseline_id[[s]],
    is_argmax = best$method_id,
    is_argmax_label = best$method_label,
    is_argmax_is_sr = best$is_net_sr,
    is_argmax_d_is_sr = best$d_is_sr,
    is_argmax_d_oos_sr = best$d_oos_sr,
    is_argmax_is_baseline = as.logical(best$is_baseline),
    oos_nondegradation_of_argmax = isTRUE(best$d_oos_sr >= 0),
    n_alive = sum(challengers$alive_all, na.rm = TRUE),
    alive_ids = challengers[alive_all == TRUE, method_id],
    axis_verdict = if (alive_any) "ALIVE" else "CLOSED_on_this_substrate"
  )
}

axis_alive_overall <- any(vapply(verdicts, function(v) v$axis_verdict == "ALIVE", logical(1)))

out_csv <- file.path(TRACKW_DIR, "weighting_results.csv")
fwrite(res, out_csv)

meta <- list(
  artifact = "TRACKW_WEIGHTING_RESULTS_v1",
  prereg = "TRACKW_WEIGHTING_PREREG_v1 (FROZEN 2026-06-11 15:33 KST)",
  generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  metric_type = "canonical_screen",
  metric_type_note = paste(
    "All 77 trials on ONE engine: PerformanceAnalytics::Return.portfolio (monthly",
    "weights @ month-end t, forward returns @ month-end t+1, b1_step3 precedent)",
    "+ per-name |dW|x15bps both-leg delta cost (= v2.4_delta semantics in weight",
    "space, drift-aware via BOP/EOP) + contracts build_benchmark_compare PORT_t",
    "NW lag-3 (forge-identical function). NOT forge build_bt_result 'backtested'.",
    "Weighting method carried in SEPARATE weighting_method column. Label schema",
    "corrected 2026-06-12 (Q-Lead approval): metric_type restored to enum value",
    "'canonical_screen' ('canonical_screen_weighted' was outside the enum;",
    "measurement numbers unchanged)."),
  label_schema = list(
    metric_type_enum = c("canonical_screen", "backtested", "estimated", "proxy"),
    weighting_method_column = "per-trial weighting method (was wrongly encoded in metric_type)"),
  cost_model = "v2.4_kr_retail_15bps delta-equivalent (monthly weight-space)",
  selection_protocol = list(
    selection_type = "sweep", n_trials_this_track = nrow(res),
    n_trials_cumulative_weighting_axis = 86,
    is_window = "common_start ~ formation 2018-12", oos_window = "formation 2019-01 ~",
    rule = "argmax IS net SR only; OOS used solely for non-degradation confirm"),
  protocol_deviations = list(
    engine = paste(
      "Prereg named run_monthly_simulation; its dispatch cannot express 17/22",
      "registered methods without modifying 02_Infrastructure (hardcoded 150d",
      "lookback < 756d HRP window; lambda-tilt absent; W09/HRP-grid/B06-11 absent).",
      "Per prereg identical-months comparability rule, ALL trials run on the",
      "contract-blessed Return.portfolio monthly pattern instead. Reported, not",
      "silently absorbed."),
    common_start = paste(
      "Prereg expected S1/S2 ~2005-03, S3 ~2008-02 under premise 'RAWDATA from",
      "2002-03'. Actual RAWDATA cache spans 1990-01~. Registered RULE (756d window",
      "available AND scores exist) applied literally -> S1 2004-01, S2 2002-03+,",
      "S3 2005-02+, B = first month with 36m sleeve history."),
    s2_liquidity = "ADV(20d Close*Vol, t-1) >= 2e8 added at selection (immutable constraint; original module used share-volume percentile only)",
    s3_capping = "top-25 plain (original n=30 + buffer_zone 50/25 dropped; prereg-registered cap)",
    window_basis = "IS/OOS/2017+ cut on FORMATION month (w_idx); IS returns realize through 2019-01",
    s3_identity_period = paste(
      "S3 trial months held to registered substrate identity (registry 2005-02~,",
      "'scores from 2005-02' premise in prereg common_start_rule). 2026-06-10",
      "factor-db rebuild extended C19 scores to 2000-04, which would silently",
      "widen the substrate and leave 2000-04~2004 cov windows truncated",
      "(ret_s3 slice from 2001-09). Formation w_idx >= 2005-02-01. Decided",
      "PRE-measurement, documented (registration_rule compliance)."),
    forward_month_completeness = paste(
      "S2/S3 formation months kept only where the forward month is fully",
      "realized (w_idx <= 2026-04-30; RAWDATA ends mid-month 2026-06-12).",
      "Prevents fabricated all-zero final month (Ret_1m NA->0) and a",
      "partial-month forward return. S1/B end 2026-03/2026-02 naturally.",
      "Decided PRE-measurement, documented."),
    s3_factor_db_env_shim = paste(
      "prep_s1b_s3.R: unqualified open_dataset() shadowed during VERBATIM",
      "source of STR_1550 factor_engine.R - .cache/factor_db gained",
      "build_hash.txt (Gate 13.1, 2026-06-11) which breaks arrow schema",
      "inference on the directory; shim passes the explicit factor_db_*.parquet",
      "file list (identical files). No factor value changed.")
  ),
  verdicts = verdicts,
  axis_alive_overall = axis_alive_overall,
  alive_criteria = "IS dSR>=+0.10 AND OOS dSR>=0 AND full dMDD<=+2pp vs same-substrate baseline",
  results = res
)
write_json(meta, file.path(TRACKW_DIR, "weighting_results.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")

writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), file.path(TRACKW_DIR, "DONE_TRACKW"))
cat("FINALIZE_OK\n")
print(res[, .(substrate, method_id, is_net_sr, oos_net_sr, d_is_sr, d_oos_sr,
              full_mdd, d_full_mdd_pp, full_port_t_nw3, alive_all)])
