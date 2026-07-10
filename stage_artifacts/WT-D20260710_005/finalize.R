# Finalize WT-D20260710_005: alpha_scores.parquet + alpha_package.json + alpha_validation.json + lineage
suppressMessages({library(data.table); library(arrow); library(jsonlite)})
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT,"stage_artifacts/WT-D20260710_005")
MBX  <- file.path(ROOT,"qepm/mailbox/worktask/WT-D20260710_005")
SA   <- file.path(ROOT,"stage_artifacts/WT-D20260710_005")
dir.create(SA, showWarnings=FALSE, recursive=TRUE)

R <- readRDS(file.path(OUT,"ha_results.rds"))
pm <- readRDS(file.path(OUT,"ha_panel_merged.rds")); P <- pm$P
P <- P[is.finite(score_eff)&is.finite(Ret_1m)]

# --- cor vs admitted (score_eff) for primary quality signal q_rate24 (has_hist only) ---
Pv <- P[has_hist==1]
cor_vs_seff <- Pv[, .(rc=if(.N>=15) suppressWarnings(cor(-rate_24, score_eff, method="spearman")) else NA), by=ym][is.finite(rc), mean(rc)]

# --- alpha_scores.parquet: primary signal (as_of latest month) + full panel record ---
as_of <- max(P$sdate)
latest <- Pv[sdate==as_of, .(Date=as.character(sdate), Ticker, score_quality=-rate_24,
                             restate_rate_24=rate_24, restate_cnt_24=cnt_24,
                             confidence=pmin(1, fil_24/24))]
write_parquet(Pv[, .(Date=as.character(sdate), Ticker, score_quality=-rate_24,
                     restate_rate_24=rate_24, restate_cnt_24=as.integer(cnt_24),
                     fil_24=as.integer(fil_24), has_hist)],
              file.path(SA,"alpha_scores.parquet"))

bk <- R$book; ic <- R$icA; cs <- R$canon; pb <- R$placebo
g <- function(x, d=NA) if(is.null(x)||length(x)==0||!is.finite(x)) d else round(as.numeric(x),4)

# --- alpha_package.json ---
alpha_package <- list(
  task_id = "WT-D20260710_005",
  as_of_date = as.character(as_of),
  forecast_horizon = "1M",
  wt_type = "discovery",
  alpha_discovery_certificate = "NOT_ISSUED",
  certificate_reason = "Screening FAIL: standalone canonical cap-w PORT_t=0.444 (<2.95), rank-IC null (t=0.63), book-marginal exclusion negative (size-proxy). No usable alpha in either direction.",
  selection_objective = "canonical_port_t",
  alpha_vector = as.list(setNames(round(latest$score_quality,6), latest$Ticker)),
  confidence_vector = as.list(setNames(round(latest$confidence,3), latest$Ticker)),
  signal_matrix_ref = "stage_artifacts/WT-D20260710_005/alpha_scores.parquet",
  factor_specs = list(list(
    factor_family = "DisclosureQuality",
    proxy = "restatement_frequency_24M",
    formula = "quality = -(count(정정 filings, trailing 24M) / count(all filings, trailing 24M)); DART list.json report_nm '정정' prefix; PIT rcept_dt<=sig_date",
    lag_rule = "rcept_dt (공시 접수일, public timestamp) <= month-end t; forward = t+1",
    winsorization = "none (rate in [0,1])",
    neutralization = "tested raw + size-residualized (log Size)",
    economic_rationale = "Hypothesized: frequent restatement = poor disclosure quality/internal-control weakness -> underperformance (Palmrose-Richardson-Scholz 2004; Hribar-Jenkins 2004). MEASURED-NEGATIVE in KR K200uKQ150: restatement frequency is a disclosure-volume/size proxy (spearman(cnt,logSize)=+0.30; top restaters=Samsung/Hynix/KoreaZinc), so exclusion removes momentum winners. Size-neutralized version also null.",
    redundancy_cluster_id = "disclosure_meta (sibling: earliness STR_AS_20260611_154820 FAIL; this=quality/content dim, virgin restatement axis)",
    weight_theta = 0,
    references = c("Palmrose-Richardson-Scholz 2004 JAE","Hribar-Jenkins 2004 RAS","DART OpenAPI list.json (기존 인프라)")
  )),
  diagnostics = list(
    canonical_port_t_nw_lag3 = g(cs$portfolio_alpha_t_nw_lag3),
    canonical_n_months = if(!is.null(cs$n_months)) as.integer(cs$n_months) else NA,
    canonical_ir = g(cs$information_ratio),
    canonical_net_sr = g(cs$net_sr),
    canonical_turnover_annual = g(cs$turnover_annual),
    diag_ew_universe_port_t = g(cs$diag_ew_universe$portfolio_alpha_t_nw_lag3),
    diag_ew_universe_post2017_t = g(cs$diag_ew_universe$post2017_t_nw_lag3),
    rank_ic = g(ic$q_rate24$full$mean_ic),
    rank_ic_t = g(ic$q_rate24$full$t),
    rank_ic_2017plus_t = g(ic$q_rate24$y2017$t),
    icir = g(ic$q_rate24$full$icir),
    harvey_t_stat = g(ic$q_rate24$full$t),
    subperiod_stability_note = "sp1(05-11) sp2(12-18) sp3(19-26) all |t|<1.3; 2017+ t=0.50 -> unstable/null",
    size_neutral_rank_ic_t = 0.91,
    portfolio_alpha_t_note = "canonical cap-w PORT_t (screening authority) = 0.444 << 2.95. rank-IC t and portfolio-alpha t both null. Judge authority = forge (not invoked; screening FAIL upstream).",
    book_marginal_ex_q80_nwt = g(bk$q80$nwt),
    book_marginal_ex_q80_dIR = g(bk$q80$dIR),
    book_marginal_ex_cnt3_nwt = g(bk$cnt3$nwt),
    n_trials = as.integer(R$n_trials),
    max_abs_t = g(R$max_abs_t),
    placebo_null_q95 = g(quantile(abs(pb$dist),0.95)),
    cor_vs_admitted_score_eff = round(cor_vs_seff,4),
    dsr_note = "hypothesis-family sweep n_trials=7; DSR diagnostic only (chain/negative-result; no positive to deflate)"
  ),
  challenge_flags = list(
    "RF: standalone canonical PORT_t 0.444 << 2.95 (screening FAIL)",
    "RF: rank-IC null full t=0.63, 2017+ t=0.50 (no cross-sectional predictive power)",
    "book-marginal exclusion NEGATIVE (ex_cnt3 NWt=-4.63) = restatement freq is size/activity proxy, not governance; excluding removes momentum winners (88.5% of book, incl Samsung/Hynix)",
    "size-neutralized version also null (rank-IC t=0.91) -> axis carries no exploitable alpha",
    "H-b (bad-news flags) redundant-by-construction: distress flags 0.4% of book holdings, unfaith 3/6675",
    "verdict=VALIDATED_NEGATIVE for disclosure-quality exclusion/quality-long; data depth excellent (2005, PIT-clean) but signal absent"
  ),
  status = "SCREEN_FAIL_NEGATIVE"
)
write_json(alpha_package, file.path(MBX,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, na="null", digits=6)

# --- alpha_validation.json ---
alpha_validation <- list(
  task_id = "WT-D20260710_005",
  theme = "non-price disclosure-quality signals (DART metadata)",
  verdict = "VALIDATED_NEGATIVE",
  data_availability = list(
    H_a_restatement = list(source="DART OpenAPI list.json (corp-scoped, 348 firms K200uKQ150)",
      rows=506874, tickers=348, date_range="2005-01-03..2026-07-10",
      firms_history_to_2005 = 213, median_filings_per_firm = 950,
      restatement_filings = 46149, restatement_strict_prefix = 44011,
      pit = "rcept_dt (public receipt timestamp) <= sig_date; forward t+1; lag1-stress passed",
      fetch_quota_events = 0, note="insider crawl 무간섭 준수(quota_events=0); heavy month-sweep 회피, corp-scoped memory-safe"),
    H_b_badnews = list(source="RAWDATA existing flags UnfaithfulDisc/AdminStock/TradingHalt (no fetch)",
      per_month_avg_in_universe = list(unfaith=0.09, admin=0.19, halt=0.85, anybad=1.09, trailing12M=6.62),
      note="settled per Q-Lead: redundant-by-construction")
  ),
  H_a_measurement = list(
    rank_ic_advisory = list(q_rate24_full_t=g(ic$q_rate24$full$t), q_rate24_2017_t=g(ic$q_rate24$y2017$t),
      q_rate12_full_t=g(ic$q_rate12$full$t), q_cnt24_full_t=g(ic$q_cnt24$full$t),
      q_rates24_strict_full_t=g(ic$q_rates24$full$t), size_neutral_t=0.91,
      verdict="null (all |t|<1)"),
    standalone_canonical_dual_basis = list(
      capw_port_t_nw_lag3 = g(cs$portfolio_alpha_t_nw_lag3), capw_ir=g(cs$information_ratio),
      capw_net_sr=g(cs$net_sr), n_months=if(!is.null(cs$n_months)) as.integer(cs$n_months) else NA,
      diag_ew_universe_port_t = g(cs$diag_ew_universe$portfolio_alpha_t_nw_lag3),
      diag_ew_universe_post2017_t = g(cs$diag_ew_universe$post2017_t_nw_lag3),
      verdict="null/negative (cap-w 0.44, EW -1.44); no standalone alpha"),
    book_marginal_exclusion = list(
      metric="paired NW-t(lag3) of (excluded_active - base_active) vs STR_1715 score_eff top-25; dIR=net_active IR delta",
      ex_q80_topquintile_rate = list(nwt=g(bk$q80$nwt), IS_nwt=g(bk$q80$nwt_is), OOS_nwt=g(bk$q80$nwt_oos), dIR=g(bk$q80$dIR), changed=bk$q80$changed, verdict="null (within placebo q95=2.0, emp_p=0.275)"),
      ex_any_ge2 = list(nwt=g(bk$any$nwt), dIR=g(bk$any$dIR), verdict="strongly NEGATIVE (size-proxy)"),
      ex_cnt3_ge3 = list(nwt=g(bk$cnt3$nwt), dIR=g(bk$cnt3$dIR), verdict="strongly NEGATIVE; excludes 88.5% of book incl mega-caps"),
      lag1_stress = list(ex_q80_lag1_nwt=g(bk$lag1$nwt), note="negative sign held -> PIT clean, not look-ahead"),
      size_neutral_exclusion = list(nwt=-1.28, IS_nwt=-1.66, OOS_nwt=0.34, verdict="null/inconsistent -> not a size-masked governance signal")),
    placebo_null = list(n_draws=length(pb$dist), q95_abs_nwt=g(quantile(abs(pb$dist),0.95)), ex_q80_emp_p=g(pb$emp_p)),
    confound_mechanism = list(spearman_cnt_logsize=0.299, top25_cnt3_share=0.885,
      top_restaters=c("A005930 Samsung","A000660 SK Hynix","A010130 Korea Zinc"),
      interpretation="restatement frequency = disclosure-volume/size proxy (big active firms file+correct more); exclusion removes momentum winners. NOT governance-negative."),
    n_trials=as.integer(R$n_trials), max_abs_t=g(R$max_abs_t),
    selection_type="hypothesis-family sweep; DSR diagnostic (negative result, nothing to deflate)"
  ),
  universe_comparison = list(default="KR_top342 (K200uKQ150, liq 5e7)",
    note="v2 KR_TOP500 미실행 — 신호 방향 자체가 null/negative라 universe 확장이 구제 불가(size-proxy는 확장 시 오히려 강화)."),
  quality_criteria_5 = list(non_price="PASS (DART metadata)", mechanism_clear="PASS (restatement->governance thesis, but inverts empirically)",
    long_history="PASS (2005, 213/348 firms)", pit_clean="PASS (rcept_dt + lag1)", low_crowding="PASS (KR-native, virgin restatement axis)",
    overall="입력 5기준 충족하나 신호(alpha) 부재 — 양질 재료 != 양질 신호"),
  final_verdict = "VALIDATED_NEGATIVE: disclosure-quality axis (H-a restatement exclusion + H-b bad-news flags) carries no exploitable cross-sectional alpha in deployable K200uKQ150. H-a exclusion actively harmful (size-proxy). Honest negative map. forge authoritative 미소환(screening FAIL upstream). graduation 선언 없음.",
  spawn_recommendation = "H-c/H-d deferred to Q-Lead. Restatement event-time short-window + type-split (실적정정 vs 형식정정) untested (needs document.xml parse = insider-grade heavy wall). Not a family verdict (INV-7)."
)
write_json(alpha_validation, file.path(SA,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, na="null", digits=6)

# --- lineage (after write) ---
tryCatch({
  source(file.path(ROOT,"02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(task_id="WT-D20260710_005", package_type="alpha_package",
    method_selected="H-a restatement disclosure-quality (VALIDATED_NEGATIVE)",
    input_file_paths=c(file.path(OUT,"ha_disc_panel.rds"), file.path(OUT,"ha_panel_merged.rds"),
                       file.path(ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet")))
  cat("lineage recorded\n")
}, error=function(e) cat("lineage skip:", conditionMessage(e),"\n"))

cat("FINALIZE DONE\n")
cat("cor_vs_score_eff=", round(cor_vs_seff,4), " as_of=", as.character(as_of), " latest_names=", nrow(latest), "\n")
