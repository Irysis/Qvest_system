suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
source("02_Infrastructure/config.R")
TMP <- "C:/Users/99922/AppData/Local/Temp/claude"; OUT <- "stage_artifacts/WT-D20260706_008"
pl <- readRDS(file.path(TMP,"wt008_pl.rds")); setDT(pl); setorder(pl, Ticker, ym)
pl[, oi_chg := tot_oi/shift(tot_oi,1)-1, by=Ticker]

# alpha_scores.parquet: latest month cross-section (basis_pct as alpha proxy) for the record
latest_ym <- max(pl$ym)
last_snap <- pl[ym==latest_ym, .(Ticker, name=underlying, mkt, basis_pct, tot_oi, oi_chg,
                                  z_basis=z_basis_pct, adv_m, as_of=as.character(me_date))]
setorder(last_snap, -z_basis)
write_parquet(last_snap, file.path(OUT,"alpha_scores.parquet"))
cat("alpha_scores.parquet:", nrow(last_snap),"names @", latest_ym,"\n")

# validation JSON with all measured numbers (metric_type labels mandatory)
val <- list(
  task_id = "WT-D20260706_008",
  as_of_date = "2026-07-06",
  verdict = "NEGATIVE_SCREEN_TIER",
  feasibility = "GO",
  data_path = list(
    endpoint_kospi = "/drv/eqsfu_stk_bydd_trd",
    endpoint_kosdaq = "/drv/eqkfu_ksq_bydd_trd",
    tier = "accessible (HTTP 200)",
    fields = "SPOT_PRC(현물)+TDD_CLSPRC(선물)->basis; ACC_OPNINT_QTY(OI); ACC_TRDVAL(val)",
    collected = "127 month-ends 2015-12..2026-06 (temp RDS, crash-isolated per-process fetch)",
    coverage_curve = "2010:25 names -> 2016:78 -> 2018:116 -> 2020:123 -> 2026:284 underlyings (usable cross-section starts ~2016)",
    name_ticker_match = "18809/21178 (88.8%) via static latest-date normalized-name map + alias table",
    median_names_per_month = 129L
  ),
  signal_diagnostics = list(
    basis_pct = list(rank_ic_full=0.0446, icir_full=0.485, harvey_t_full=5.46,
                     rank_ic_post2018=0.0382, harvey_t_post2018=4.40, n_months=127L,
                     metric_type="rank_ic_spearman", note="signal@t vs fwd 1M return, liq-filtered"),
    oi_change = list(rank_ic_full=-0.0291, harvey_t_full=-3.24, rank_ic_post2018=-0.0219,
                     metric_type="rank_ic_spearman", note="contrarian: OI build -> lower fwd return"),
    basis_mom = list(rank_ic_full=0.0273, harvey_t_full=3.65, metric_type="rank_ic_spearman"),
    quintile_fwd_pct = list(Q1=-0.055, Q2=1.154, Q3=1.103, Q4=1.382, Q5=1.369,
                            note="Q1 (cheap basis) only negative; Q2-Q5 flat = short-side-driven"),
    lag1_decay = list(rank_ic=0.0101, harvey_t=1.35, metric_type="rank_ic_spearman",
                      note="CRITICAL: signal decays to insignificance at lag-1 = fast-decay ~1mo effect")
  ),
  portfolio_alpha_authoritative = list(
    metric_type = "canonical_screen (top-25 EW long-only 15bps, PORT_t NW lag-3)",
    hard_gate_port_t = 2.95,
    bench_raw_kospi200 = list(
      A_richest_basis=list(port_t=-1.04, net_sr=-0.39, turnover_pct=1875, alpha_ann_pct=1.74),
      B_basis_mom=list(port_t=-1.24, turnover_pct=2240),
      C_neg_oi=list(port_t=-1.30), D_composite=list(port_t=-1.11),
      E_liq_baseline=list(port_t=-0.53), F_excl_cheap20=list(port_t=-0.08), G_excl_cheap40=list(port_t=-0.65),
      A_post2018=list(port_t=-1.09), note="raw includes 6 benchmark-glitch months (2026 +27/33/35% impossible)"),
    bench_clean_glitch_removed = list(
      A_richest_basis=list(port_t=0.01, net_sr=0.00, alpha_ann_pct=1.52, n=121),
      F_excl_cheap20=list(port_t=0.39, net_sr=0.12, n=121),
      note="6 glitch fwd-bench months removed; PORT_t rises to ~0 but still << 2.95 gate"),
    ew_universe_relative = list(top25_basis_active_pct_mo=0.445, t=2.65, n=121,
      metric_type="ew_universe_relative (ADVISORY — flatters small-cap tilt ~+1.3t vs cap-weight, ref kr-2025-megacap-semi-regime)")
  ),
  turnover = list(raw_basis_annual_pct=1875, smoothed_3m_annual_pct=1059,
                  hard_fail_ceiling_pct=1100, verdict="FAIL (raw>ceiling; smoothing kills signal)"),
  harvestability = list(
    long_side_harvestable = FALSE,
    reason = "short-side-driven (Q1 only differentiated) + fast-decay (lag1 IC 0.010) + turnover 1875%; cheap-basis exclusion lifts book marginally but PORT_t stays <<gate",
    productive_leg = "short (unavailable under no-short KR mandate)"
  ),
  pit = list(status="CLEAN", checks="signal @ month-end close (t), fwd return t->t+1 (strictly future); lag-1 test confirms no look-ahead; futures basis/OI observed at close"),
  graduation_gate = list(port_t_2.95="FAIL", oos_retention_0.7="n/a (port_t fail precludes)", calmar_0.64="n/a", note="hard gate PORT_t fails under both raw and clean benchmark"),
  route = "DPL_FEATURE (fast positioning signal for daily/multi-signal ML layer, not standalone monthly book)",
  dedup = "CONFIRMED novel — hypothesis_index 0-coverage for option/futures/basis/VKOSPI/implied. Distinct from prior short-interest (/srt 404) — this used a working DIFFERENT endpoint /drv/eqsfu. Distinct from forward-macro-null (that was yield-curve/credit, not derivatives-implied).",
  challenge_note = "challenge_note.md (5 concerns, all ACCEPT, no escalation, PIT clean)"
)
write_json(val, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)
cat("alpha_validation.json written.\n")
