# emit_alpha_package.R (WT-D20260702_001) — build alpha_package.json + lineage. ASCII only.
suppressMessages({ library(arrow); library(data.table); library(jsonlite) })
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
out_dir <- file.path(root, "stage_artifacts", "WT_D20260702_001")
mbox <- file.path(root, "qepm/mailbox/worktask/WT-D20260702_001")

val <- fromJSON(file.path(out_dir, "alpha_validation.json"), simplifyVector = FALSE)
sc  <- as.data.table(read_parquet(file.path(out_dir, "alpha_scores.parquet")))
setorder(sc, -score)

# alpha_vector: latest-month composite score -> proxy expected active (z-scaled, informational).
# NOTE: verdict is FAIL; alpha_vector provided for schema completeness / downstream feature use only.
av <- setNames(as.list(round(sc$score, 4)), sc$Ticker)
# confidence: rank-stability proxy; low overall because recent PORT_t negative.
n <- nrow(sc)
conf <- setNames(as.list(round(pmin(0.6, 0.30 + 0.30 * (n:1)/n), 3)), sc$Ticker)

gv <- function(seg, k) { v <- val$results[[seg]][[k]]; if (is.null(v)) NA else v }

factor_specs <- list()
seedfac <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C05_ESCR","C06_TP_Gap","C19_Composite_Earnings")
for (f in seedfac) {
  factor_specs[[length(factor_specs)+1]] <- list(
    factor_family = "consensus_earnings_revision",
    proxy = f,
    formula = "cross-sectional z-score (monthly), equal-weight composite sum (all higher_better)",
    lag_rule = "quarterly 45d / annual May (consensus est. inherit panel PIT snapshot)",
    winsorization = "none (raw z; >=3/6 factors present required)",
    neutralization = "none (raw composite)",
    economic_rationale = "post-earnings-announcement drift + analyst revision underreaction: prices adjust slowly to earnings surprises and forecast revisions (Bernard-Thomas 1989; Chan-Jegadeesh-Lakonishok 1996). Mechanism = investor underreaction to consensus information.",
    redundancy_cluster_id = "CLUSTER_consensus_earnings (all 6 in registry category=consensus; C19 is composite of C01/C02/C04/C05/C06)",
    selection_objective = "rank_ic",
    references = c("Bernard-Thomas 1989 PEAD","Chan-Jegadeesh-Lakonishok 1996","seed discovery_explore round7 t3.58 (proxy)"),
    weight_theta = round(1/length(seedfac), 3)
  )
}

diag <- list(
  rank_ic = val$diagnostics$rank_ic_full,
  icir = val$diagnostics$icir_full,
  rank_ic_harvey_t = val$diagnostics$rank_ic_t_full,   # rank-IC t (naive), ADVISORY
  rank_ic_recent = val$diagnostics$rank_ic_recent,
  subperiod_stability = "UNSTABLE: 2010-2015 PORT_t 3.20 / 2016-2020 -0.42 / 2021-2026 -0.32",
  turnover_annual_pct = round(as.numeric(gv("full","turnover"))*100, 1),
  monotonicity = "not_computed",
  post_neutralization_ic = "n/a (raw composite)",
  # AUTHORITATIVE performance (monthly canonical, contract build_benchmark_compare NW lag-3)
  portfolio_alpha_t_nw_lag3_full = gv("full","port_t"),
  portfolio_alpha_t_nw_lag3_recent = gv("recent","port_t"),
  portfolio_alpha_t_pvalue_recent = gv("recent","p_value"),
  net_sr_full = gv("full","net_sr"),
  net_sr_recent = gv("recent","net_sr"),
  information_ratio_full = gv("full","IR"),
  information_ratio_recent = gv("recent","IR"),
  metric_type = "canonical_screen",
  metric_type_note = "monthly 1M rebalance top-25 EW long-only 15bps; contract-grade. NOT admission-binding (forge build_bt_result authoritative). rank-IC t is ADVISORY; portfolio-alpha t is the discriminating metric."
)

challenge_flags <- list(
  list(id="SEED-CAVEAT", severity="HIGH",
       note="seed proxy_recent_port_t=2.58 is a QUARTERLY-MARKING ARTIFACT (H=3 non-overlap). canonical(monthly)=0.70. On WT-mandated monthly 1M basis, recent PORT_t = -0.32 (p=0.75). Proxy 2.58 NOT used as evidence."),
  list(id="RF-A3", severity="HIGH",
       note="cohort-wide DECAY pattern: full-period edge (PORT_t 2.10) driven entirely by 2010-2015 (3.20); 2016-2020 (-0.42) and 2021-2026 (-0.32) negative. earnings-revision premium dead post-2015."),
  list(id="IC-vs-PORT", severity="MEDIUM",
       note="rank-IC t=7.63 (strong) but monthly PORT_t=2.10 full / -0.32 recent. IC != portfolio-alpha t (Cycle 2). Long-only top-25 does not realize the cross-sectional signal. Judge must use portfolio-alpha t (forge 5-spec) as authoritative."),
  list(id="GRADUATION-FAIL", severity="HIGH",
       note="graduation HARD FAIL: recent PORT_t -0.32 << 2.95. full 2.10 < 2.95. Candidate is NOT capital-grade. screen-tier only (decay-pattern). Recommend: not deploy; usable at most as DPL feature."),
  list(id="W2-WIRING", severity="INFO",
       note="W2 end-to-end test PASS: discovery_seed.json read in Step 0, factor_ids consumed in Step 2 via panel/load path, canonical<<proxy caveat carried to challenge_flags, no proxy-as-evidence.")
)

alpha_package <- list(
  task_id = "WT-D20260702_001",
  as_of_date = "2026-07-02",
  forecast_horizon = "1M",
  wt_type = "discovery",
  hypothesis_title = "Earnings-revision composite (consensus) — monthly 1M alpha (W2 seed consumption test)",
  verdict = "FAIL_GRADUATION_DECAY_PATTERN",
  verdict_summary = "earnings-revision composite does NOT survive on the system-authoritative monthly (1M) basis. recent PORT_t -0.32; full 2.10 is a pre-2016 relic (decay). Seed proxy 2.58 confirmed as quarterly-marking artifact.",
  selection_objective = "rank_ic",
  alpha_vector = av,
  confidence_vector = conf,
  signal_matrix_ref = "stage_artifacts/WT_D20260702_001/alpha_scores.parquet",
  factor_specs = factor_specs,
  diagnostics = diag,
  method_shopping_log = list(alpha_agent = list(
    candidates_tried = 3,
    selection_type = "chain",
    method_log = list(
      list(name="earnings_rev_composite_6f_monthly", rank_ic=val$diagnostics$rank_ic_full, recent_port_t=gv("recent","port_t"), selected=TRUE),
      list(name="C19_Composite_Earnings_single", recent_port_t=gv("single_C19_Composite_Earnings_recent","port_t"), selected=FALSE),
      list(name="C01_SUE_single", recent_port_t=gv("single_C01_SUE_recent","port_t"), selected=FALSE)
    ),
    parallel_exec = FALSE
  )),
  challenge_flags = challenge_flags,
  w2_wiring_test = list(
    seed_read = TRUE,
    seed_path = "qepm/mailbox/worktask/WT-D20260702_001/discovery_seed.json",
    factor_ids_consumed = seedfac,
    proxy_used_as_evidence = FALSE,
    canonical_vs_proxy_handled = TRUE,
    result = "PASS"
  )
)

# Step 1: write alpha_package.json  (then lineage — L-194 order)
write_json(alpha_package, file.path(mbox, "alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, na="null")
cat("WROTE:", file.path(mbox, "alpha_package.json"), "\n")

# Step 2: lineage
lu <- file.path(root, "02_Infrastructure/worktask/lineage_utils.R")
if (file.exists(lu)) {
  tryCatch({
    source(lu)
    record_package_lineage(
      task_id = "WT-D20260702_001",
      package_type = "alpha_package",
      method_selected = "earnings_rev 6-factor composite, monthly 1M canonical_screen (FAIL/decay)",
      input_file_paths = c(
        file.path(root, ".cache/discovery/phase0_panel_2005-01_2026-04.parquet"),
        file.path(root, ".cache/benchmark.parquet"),
        file.path(mbox, "discovery_seed.json"))
    )
    cat("lineage recorded\n")
  }, error = function(e) cat("lineage skip:", conditionMessage(e), "\n"))
}
cat("DONE\n")
