suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
source("02_Infrastructure/config.R")
TMP <- "C:/Users/99922/AppData/Local/Temp/claude"; OUT <- "stage_artifacts/WT-D20260706_008"
MB <- "qepm/mailbox/worktask/WT-D20260706_008"
scores <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
# alpha_vector: basis_pct-based active expectation proxy (documentation only — NOT admission-grade)
# scale z_basis to a small expected active (bps) — clearly labeled proxy
av <- setNames(as.list(round(scores$z_basis * 0.002, 5)), scores$Ticker)  # ~0.2%/z illustrative
cv <- setNames(as.list(round(pmin(1, pmax(0.1, 0.5 + 0.1*scores$z_basis)),3)), scores$Ticker)

pkg <- list(
  task_id = "WT-D20260706_008",
  as_of_date = "2026-07-06",
  forecast_horizon = "1M",
  wt_type = "discovery",
  alpha_discovery_certificate = "NOT_ISSUED",
  certificate_reason = "NEGATIVE result — portfolio_alpha_t (canonical, clean bench) = +0.01..+0.39 << 2.95 hard gate. Signal real & PIT-clean but NOT long-side harvestable (short-side-driven + fast-decay + turnover 1875%). Route=DPL_FEATURE.",
  selection_objective = "icir",
  alpha_vector = av,
  confidence_vector = cv,
  signal_matrix_ref = "stage_artifacts/WT-D20260706_008/alpha_scores.parquet",
  factor_specs = list(list(
    factor_family = "Derivatives_Positioning",
    proxy = "single_stock_futures_basis_pct",
    formula = "(front_month_futures_close - spot_close) / spot_close * 100, cross-sectional z-score, winsorized 3std",
    source = "new_designed",
    data_source = "KRX Open API /drv/eqsfu_stk_bydd_trd + /drv/eqkfu_ksq_bydd_trd (NOVEL — first swarm use)",
    lag_rule = "signal @ month-end close (t); forward return t->t+1; PIT clean (lag-1 test confirms no look-ahead)",
    winsorization = "3std cross-sectional",
    neutralization = "none (raw + liq-filtered adv>=2e8)",
    economic_rationale = "Futures premium (rich basis) reflects bullish positioning / hard-to-borrow / short-squeeze pressure; discount (cheap basis) reflects short-side / bearish positioning. Rich->higher fwd return. Forward-looking positioning signal, distinct from all backward-looking realized-return factors.",
    weight_theta = 1.0,
    redundancy_cluster_id = "positioning_derivatives_NEW (no prior swarm coverage; distinct from short-interest /srt path and forward-macro)",
    references = list("KRX single-stock futures", "basis/positioning literature (futures premium & carry)")
  )),
  diagnostics = list(
    rank_ic = 0.0446, icir = 0.485, harvey_t_stat = 5.46,
    rank_ic_post2018 = 0.0382, harvey_t_post2018 = 4.40,
    monotonicity = 0.4,  # Q1 negative, Q2-Q5 flat = LOW monotonicity (short-side driven)
    subperiod_stability = 0.75,  # IC positive full+pre+post
    turnover_proxy = 18.75,  # 1875% annual = fast-decay signal
    lag1_rank_ic = 0.0101, lag1_harvey_t = 1.35,
    portfolio_alpha_t_canonical_clean = 0.01,
    portfolio_alpha_t_canonical_raw = -1.04,
    ew_universe_relative_t = 2.65,
    metric_note = "rank_ic (spearman) vs portfolio_alpha_t (canonical top-25 EW NW lag3) DIVERGE sharply: IC t=5.5 but PORT_t~0. Judge authoritative = portfolio_alpha_t (forge). This is the Cycle-2 lesson in action."
  ),
  ic_vs_portfolio_alpha = list(
    rank_ic_harvey_t = 5.46,
    portfolio_alpha_t_authoritative = 0.01,
    interpretation = "Strong rank-IC does NOT translate to harvestable long-only portfolio alpha. Edge is short-side (Q1) + fast-decay, unavailable long-only monthly."
  ),
  challenge_flags = list(
    list(id="RF-HARVEST", severity="HIGH", note="short-side-driven: Q1 only differentiated quintile; long-only top-25 has no selection edge (Q2-Q5 flat)"),
    list(id="RF-DECAY", severity="HIGH", note="lag-1 rank-IC collapses 0.045->0.010 (t 5.5->1.35): fast ~1mo-decay signal, wrong frequency for monthly rebalance"),
    list(id="RF-TURNOVER", severity="HIGH", note="1875% annual turnover > 1100% hard-fail ceiling; 3M smoothing (TO 1059%) destroys signal (PORT_t -1.04->-1.56)"),
    list(id="RF-BENCH", severity="MEDIUM", note="raw PORT_t -1.04 partly benchmark-glitch artifact (6 impossible 2026 bench months); clean-bench +0.01 but still <<2.95"),
    list(id="RF-EWFLATTERY", severity="MEDIUM", note="ew-universe-relative t=2.65 flatters mid-cap tilt ~+1.3t vs cap-weight (ref kr-2025-megacap-semi-regime); cap-weighted authoritative = fail")
  ),
  route = "DPL_FEATURE",
  verdict = "NEGATIVE_SCREEN_TIER — no risk/optimizer handoff. Honest negative. Data path NOVEL & reusable for future derivatives-positioning work.",
  method_shopping_log = list(candidates_tried=3, method_log=list(
    list(name="basis_pct", rank_ic=0.0446, selected=TRUE),
    list(name="oi_change", rank_ic=-0.0291, selected=FALSE),
    list(name="basis_mom", rank_ic=0.0273, selected=FALSE)))
)
write_json(pkg, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)
cat("alpha_package.json written to mailbox.\n")

# lineage (after package write)
tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(task_id="WT-D20260706_008", package_type="alpha_package",
    method_selected="single_stock_futures_basis_pct (NEGATIVE — not harvestable)",
    input_file_paths=c("stage_artifacts/WT-D20260706_008/stockfut_monthend_raw.parquet",
                       ".cache/RAWDATA.parquet", ".cache/benchmark.parquet"))
  cat("lineage recorded.\n")
}, error=function(e) cat("lineage skip:", e$message,"\n"))
