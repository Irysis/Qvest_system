# 08_emit.R — alpha_package.json + alpha_validation.json + lineage
suppressMessages({library(data.table); library(arrow); library(jsonlite); library(dplyr)})
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260706_007")
MB   <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260706_007")
E  <- readRDS(file.path(OUT,"experiment_results.rds"))
D  <- readRDS(file.path(OUT,"alpha_diag.rds"))
tab <- fread(file.path(OUT,"variant_summary.csv"))
ls_full <- fread(file.path(OUT,"longshort_decomp.csv"))
ls_cond <- fread(file.path(OUT,"longshort_decomp_conditional.csv"))

cc <- D$cur
raw <- as.data.table(open_dataset(file.path(ROOT,".cache/RAWDATA.parquet")) %>%
  dplyr::select(Date,Ticker,Name) %>% dplyr::filter(Date>=as.Date("2026-06-01")) %>% dplyr::collect())
nm <- unique(raw[order(-Date)], by="Ticker")[, .(Ticker, Name)]
cc <- merge(cc, nm, by="Ticker", all.x=TRUE)
setorder(cc, -val_z)

n_univ_avg <- round(nrow(readRDS(file.path(OUT,"panel_universe_ret.rds"))$me)/266,0)

pkg <- list(
  task_id = "WT-D20260706_007",
  wt_type = "discovery",
  as_of_date = "2026-07-06",
  forecast_horizon = "1M",
  selection_objective = "rank_ic",
  verdict = "FAIL",
  verdict_summary = "value/quality spread-reversion conditional activation FAIL. conditional(B/C/D) 전부 unconditional(A) 대비 PORT_t delta 음수. reversion은 spread-level 실재하나 payoff short-side 주도 -> long-only 미하베스트(세션 벽 재확인). best full PORT_t=1.77<2.95 hurdle, 모든 2017+ PORT_t 음수.",
  spread_diagnostics = list(
    definition = "BM(book/price) p80/p20 median ratio, winsor 1-99, expanding percentile (C1)",
    current_ym = D$cur_ym,
    current_spread_ratio = round(D$cur_spread_ratio,2),
    current_expanding_percentile = round(D$cur_spread_pctile,3),
    current_expanding_z = 6.99,
    all_time_max = TRUE,
    all_time_max_note = "current spread ratio 274.7 = expanding pctile 1.000 = z +6.99 (역대최대). cheap-quintile BM ~275x expensive-quintile. DIST-QPM-006 retry_condition 1 (사상최대 spread) 확증.",
    mean_ratio = round(mean(E$spr$spread_ratio,na.rm=TRUE),2),
    cur_over_mean = round(D$cur_spread_ratio/mean(E$spr$spread_ratio,na.rm=TRUE),2)
  ),
  variant_results = lapply(seq_len(nrow(tab)), function(i) as.list(tab[i])),
  longshort_decomposition = list(
    note = "JUDGMENT LENS: long_side_t = Q5(cheapest) net-active t = HARVESTABLE long-only; short_side_t = neg(Q1 expensive active) = profit only if could short (NOT harvestable). LS_spread_t = academic long-short.",
    full_period = lapply(seq_len(nrow(ls_full)), function(i) as.list(ls_full[i])),
    within_extreme_spread_months = lapply(seq_len(nrow(ls_cond)), function(i) as.list(ls_cond[i])),
    verdict = "reversion payoff is SHORT-SIDE. 2017+ value long_side_t=-1.18 (value trap, cheap stocks fall) vs short_side_t=+1.21. Within extreme-spread months: long_side -0.34 (-4.18pct/yr) vs short_side +1.71 (+21.46pct/yr). Long-only cannot harvest."
  ),
  diagnostics = list(
    rank_ic = round(D$ic_val$mean_ic,4),
    icir = round(D$ic_val$icir,3),
    harvey_t_stat = round(D$ic_val$t,2),
    rank_ic_n_months = D$ic_val$n,
    rank_ic_vs_portfolio_alpha_t = "rank-IC t=5.47 (STRONG, passes 3.0) BUT portfolio-alpha t=1.77 (FAIL 2.95). Divergence: rank-IC driven by expensive-half (short-side) — cheap-half IC t=2.6 full / 1.07 2017+ (weak). Cycle-2 lesson confirmed.",
    subperiod_stability = list(
      p1_2005_2014_ic_t = 5.04, p2_2015_2019_ic_t = 1.35, p3_2020_2026_ic_t = 3.17,
      note = "cross-sec IC recovers p3 but long-side portfolio alpha does NOT (short-side driven)"
    ),
    portfolio_alpha_t_nw_lag3_best = tab[which.max(full_port_t), full_port_t],
    portfolio_alpha_t_2017_max = max(tab$rec2017_port_t),
    placebo_p_spread_timing = 0.899,
    placebo_note = "spread-timing NO better than random (p=0.899). real ON-month mean active +0.0005 < random subset +0.0072.",
    trap_vs_reversion = "reversion real at spread level (extreme-spread months: 6M spread change -3.8pct, 65pct narrow vs baseline +8.3pct) BUT achieved via short-side (expensive falling), not long-side."
  ),
  factor_specs = list(
    list(factor_family="Value", proxy="composite (BM/EP/FCF_Yield/EBIT_EV/SP mean-Z)",
         formula="mean(Z_Score_aligned) across V01_BM,V02_EP,V10_FCF_Yield,V14_EBIT_EV,V20_SP",
         lag_rule="quarterly 45d / annual May", winsorization="1-99 on BM raw for spread",
         neutralization="none (cross-sectional Z per month)", economic_rationale="risk_premium / value_spread_reversion (Cohen-Polk-Vuolteenaho 2003)",
         weight_theta=1.0, references=list("Cohen-Polk-Vuolteenaho 2003 JF The Value Spread","Asness value timing","Arnott AQR value-is-cheap")),
    list(factor_family="Quality", proxy="composite (GPA/ROE/CompQ/ROIC mean-Z)",
         formula="mean(Z_Score_aligned) across Q01_GPA,Q02_ROE,Q08_Composite_Quality,Q17_ROIC",
         lag_rule="quarterly 45d", winsorization="none", neutralization="none",
         economic_rationale="profitability_reversion (DIST-QPM-003 frontier)", weight_theta=0.0,
         references=list("Novy-Marx 2013","Fama-French 2015"))
  ),
  spread_condition_spec = list(
    trigger="value spread expanding percentile >= threshold (0.80/0.90) or continuous scaled",
    live_trigger_current="spread pctile=1.000 (all-time max) => value tilt would be ON now",
    but="conditioning does NOT improve realized long-only alpha (delta vs unconditional all negative)"
  ),
  method_shopping_log = list(alpha_agent=list(candidates_tried=9, selection_type="chain",
    method_log=lapply(seq_len(nrow(tab)), function(i) list(name=tab$label[i], port_t=tab$full_port_t[i], selected=FALSE)))),
  emit_to_axiom = list(
    cards = c("DIST-QPM-006","DIST-QPM-003"),
    polarity = "supporting_negative",
    message = "value/quality spread-reversion conditional activation TESTED and FAILED. DIST-QPM-006 retry_condition 1 (value spread mean-reversion 실측, 사상최대 spread) now MEASURED: reversion is real at spread level but SHORT-SIDE driven -> long-only cannot harvest. Conditioning worsens vs unconditional (placebo p=0.899). Strengthens both cards as supporting (reversion angle exhausted for long-only). NOT a revival."
  ),
  challenge_flags = list(
    list(id="RF_forward_analog_sparse", severity="MEDIUM", note="current spread (274.7, pctile 1.000, z+6.99) is all-time max — historical analog for THIS extreme is essentially unique (202512-202607). backtest is weak-form test of extreme-spread months; forward reversion at this exact level is out-of-sample. honestly flagged."),
    list(id="RF_short_side_wall", severity="HIGH", note="reversion payoff short-side driven (2017+ long_side_t -1.18 vs short +1.21) — long-only cannot harvest. session wall (short-side x no-short) NOT bypassed."),
    list(id="RF_rank_ic_portfolio_divergence", severity="MEDIUM", note="rank-IC t=5.47 STRONG but portfolio-alpha t=1.77 — rank-IC driven by expensive-half (short-side). Do NOT graduate on rank-IC.")
  )
)
top <- head(cc, 60)
pkg$alpha_vector <- setNames(round(top$alpha_hat,5), top$Ticker)
pkg$confidence_vector <- setNames(round(top$confidence,3), top$Ticker)
pkg$alpha_vector_note <- "top 60 by value score shown; full top-universe scores in stage_artifacts/WT_D20260706_007/alpha_scores.parquet. NOTE verdict=FAIL — these are current-month value-tilt scores for reference; not recommended for admission."
pkg$current_top_names <- lapply(seq_len(min(10,nrow(top))), function(i) list(ticker=top$Ticker[i], name=top$Name[i], val_z=round(top$val_z[i],2)))

write_json(pkg, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, null="null")
cat("[written] alpha_package.json\n")

val <- list(
  task_id="WT-D20260706_007",
  metric_type="canonical_screen",
  metric_type_note="canonical_screen_bt top-25 EW long-only 15bps NW lag-3. admission-binding 아님(forge authoritative). screening-grade.",
  graduation_check = list(
    portfolio_alpha_t_nw_best = tab[which.max(full_port_t), full_port_t], hurdle=2.95, pass=FALSE,
    rank_ic=round(D$ic_val$mean_ic,4), rank_ic_pass=TRUE,
    icir=round(D$ic_val$icir,3), icir_pass=TRUE,
    harvey_t=round(D$ic_val$t,2), harvey_pass=TRUE,
    portfolio_alpha_2017_max=max(tab$rec2017_port_t), portfolio_2017_pass=FALSE,
    verdict="FAIL — cross-sectional gates pass (rank_ic/icir/harvey) but portfolio-alpha t FAIL (short-side driven). advisory gates green, hard gate red."
  ),
  universe_comparison = list(
    universe="KR_top342 (K200 or KQ150, adv20>=2e8)",
    n_months=258, n_tickers_avg=n_univ_avg,
    note="single universe (default). ICIR strong (0.34) so universe-restriction attenuation not the binding issue — binding issue is long-only harvestability of a short-side signal, invariant to universe size."
  ),
  pit_audit = list(
    expanding_percentile_C1="PASS (mean(spread[1:i]<=spread[i]))",
    lag1_stress="PASS (spread condition lag-1 does not collapse — concurrent 0.06 vs lag1 0.92, both < unconditional 1.77)",
    forward_return_alignment="signal ym -> return ym+1 (no concurrent)",
    liquidity_filter="t-1 20d ADV >= 2e8 (C10)",
    factor_direction="registry higher_better + connector aligned Z"
  ),
  emit=pkg$emit_to_axiom
)
write_json(val, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, null="null")
cat("[written] alpha_validation.json\n")

tryCatch({
  source(file.path(ROOT,"02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(task_id="WT-D20260706_007", package_type="alpha_package",
    method_selected="value/quality spread-reversion conditional (9 variants, chain) FAIL",
    input_file_paths=c(file.path(ROOT,".cache/RAWDATA.parquet"), file.path(ROOT,".cache/benchmark.parquet")))
  cat("[lineage] recorded\n")
}, error=function(e) cat("[lineage] skip:", conditionMessage(e), "\n"))
cat("[done]\n")
