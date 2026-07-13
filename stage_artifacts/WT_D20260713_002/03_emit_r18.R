#==============================================================================
# WT-D20260713_002 R18 — Step 03: emit alpha_scores.parquet + alpha_validation.json
#   + alpha_package.json + mandate charts (sweep bar + equity). Exact numbers from RDS.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260713_002")
MB   <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260713_002")
source(file.path(ROOT,"02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT,"02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(ROOT,"02_Infrastructure/telegram/tg_chart_pack.R"))

res <- readRDS(file.path(OUT,"canon_results.rds"))
pan <- readRDS(file.path(OUT,"panels.rds")); returns_all<-pan$returns_all; bench_all<-pan$bench_all; size_all<-pan$size_all; liq_all<-pan$liq_all
FA<-as.data.table(read_parquet(file.path(OUT,"scores_FA.parquet")))
FB<-as.data.table(read_parquet(file.path(OUT,"scores_FB.parquet")))

run_canon <- function(sc,tag) canonical_screen_bt(sc[,.(Date,Ticker,score)], returns_all, bench_all, top_n=25L,
  cost_bps_oneway=15, liq_dt=liq_all, liq_min=2e8, size_dt=size_all, diag_dual_basis=FALSE,
  run_id=paste0("r18emit_",tag), strategy_id=tag)
cfa <- run_canon(FA,"FA"); cfb <- run_canon(FB,"FB")

# ---- charts (mandate: 실측 보고 = 차트 첨부, 원칙 9) ----
# 1) equity curve of best factor (FB) vs BM
prb <- as.data.frame(cfb$period_returns); names(prb)[names(prb)=="benchmark_ret"] <- "benchmark_ret"
ch_eq <- tg_chart_pack(prb, out_dir=OUT, title="R18 F-B Benford FSD (best PORT_t 0.57) vs KOSPI200",
                       ret_col="ret_net", bm_col="benchmark_ret", bm_label="KOSPI200", prefix="fb_")
# 2) sweep bar: cap-w PORT_t vs EW-uni PORT_t vs hurdle
labs <- c("F-A cap-w","F-A EW-uni","F-B cap-w","F-B EW-uni")
vals <- c(res$FA$port_t_full, res$FA$ew_t, res$FB$port_t_full, res$FB$ew_t)
ch_sw <- tg_chart_sweep(labs, vals, out_dir=OUT,
          title="R18 canonical PORT_t (NW lag3) — both << 2.95 hurdle", prefix="portt_")
charts <- c(ch_sw, ch_eq[1])
cat("charts:", paste(basename(charts),collapse=", "),"\n")

# ---- alpha_scores.parquet (combined FA+FB long panel) ----
comb <- rbindlist(list(FA[, .(Date,Ticker,factor="F-A_ModJones_DiscAccr",score,raw)],
                       FB[, .(Date,Ticker,factor="F-B_Benford_FSD",score,raw)]))
write_parquet(comb, file.path(OUT,"alpha_scores.parquet"))

# ---- alpha_vector (latest as_of month, primary=FB best PORT_t) ----
as_of <- max(FB$Date)
av <- FB[Date==as_of, .(Ticker, score)]
alpha_vector <- setNames(as.list(round(av$score,4)), av$Ticker)
conf <- setNames(as.list(rep(0.10, nrow(av))), av$Ticker)  # low confidence — null-vs-placebo

# ---- alpha_validation.json ----
val <- list(
  wt_id="WT-D20260713_002", frontier_id="FQ-031", as_of_date=as.character(as_of),
  verdict="config-scoped negative (both) — no survivor. F-A redundant w/ AC13; F-B null-vs-placebo.",
  universe="KR_top342 (K200 U KQ150)", benchmark="cap-w KOSPI200 (HARD authoritative)",
  n_months=res$FA$n_months, period="2009-06..2025-06 (frozen membership panel)",
  hard_gates_3=list(portfolio_alpha_t_nw_ge_2p95=FALSE, oos_retention_ge_0p7=FALSE, calmar_ge_0p64=FALSE),
  factors=list(
    FA=list(name="Modified-Jones Discretionary Accruals", score_sign=-1,
      canonical=list(port_t_capw=res$FA$port_t_full, port_p=res$FA$port_p, port_t_IS=res$FA$port_t_IS,
        port_t_OOS=res$FA$port_t_OOS, net_sr=res$FA$net_sr, calmar=res$FA$calmar, turnover_annual=res$FA$turnover),
      dual_basis=list(ew_uni_t=res$FA$ew_t, ew_post2017_t=res$FA$ew_post2017_t, ew_oos_retention_approx=res$FA$ew_oos_ret,
        cap_tier_weight=list(MEGA=res$FA$mega_w, MID=res$FA$mid_w, OTHER=res$FA$other_w)),
      advisory=list(rank_ic=res$FA$rank_ic, icir=res$FA$icir, rank_ic_t=res$FA$ric_t),
      robustness=list(placebo_p=res$FA$placebo_p, placebo_base=res$FA$placebo_base, szpartial_port_t=res$FA$szpartial_port_t),
      incrementality=list(corr_vs_AC13ref=res$incrementality$FA_vs_AC13ref$mean, corr_vs_FB=res$incrementality$FA_vs_FB$mean,
        corr_vs_Size=res$incrementality$FA_vs_Size$mean,
        note="corr_vs_AC13ref=0.991 => modified-Jones ~ original Jones in KR; dREC adjustment immaterial; redundant w/ AC13 (standalone LO top25 FAILED 2026-06-06 PORT_t 0.227 Grade F)"),
      verdict="config-scoped negative + frontier: standalone dead & redundant w/ AC13. route = quality/accrual composite supporting feature only (DIST-QPM-003/006).",
      next_probe=c("multi-sleeve component within earnings-quality composite (not standalone)",
                   "worst-decile EXCLUSION overlay (envelope-safe consumption) rather than long-selection")),
    FB=list(name="Benford First-Digit Deviation (FSD MAD, Amiram 2015)", score_sign=-1, virgin_family=TRUE,
      canonical=list(port_t_capw=res$FB$port_t_full, port_p=res$FB$port_p, port_t_IS=res$FB$port_t_IS,
        port_t_OOS=res$FB$port_t_OOS, net_sr=res$FB$net_sr, calmar=res$FB$calmar, turnover_annual=res$FB$turnover),
      dual_basis=list(ew_uni_t=res$FB$ew_t, ew_post2017_t=res$FB$ew_post2017_t, ew_oos_retention_approx=res$FB$ew_oos_ret,
        cap_tier_weight=list(MEGA=res$FB$mega_w, MID=res$FB$mid_w, OTHER=res$FB$other_w)),
      advisory=list(rank_ic=res$FB$rank_ic, icir=res$FB$icir, rank_ic_t=res$FB$ric_t),
      robustness=list(placebo_p=res$FB$placebo_p, placebo_base=res$FB$placebo_base, szpartial_port_t=res$FB$szpartial_port_t,
        placebo_note="placebo p=0.160 => PORT_t within shuffle noise = NO genuine signal structure"),
      incrementality=list(corr_vs_Size=res$incrementality$FB_vs_Size$mean,
        note="corr_vs_Size=0.006 => NOT a size/item-count proxy (Self-Adversarial concern cleared). But null: rank-IC wrong sign & insignificant, placebo p=0.16."),
      verdict="config-scoped negative + frontier: clean null in KR large-cap (most-audited segment). NEW knowledge (first Benford measurement in system).",
      next_probe=c("micro/small-cap universe (higher manipulation variance) — screen-tier/RAMP only, out of deployment envelope",
                   "quarterly-filing FSD (more digits per firm) + composite w/ F-A residual as forensic EXCLUSION screen"))
  ),
  dsr=list(selection_type="sweep", n_trials=2, e_max_2z=round((1-0.5772)*qnorm(1-1/2)+0.5772*qnorm(1-1/(2*exp(1))),3),
    note="best PORT_t=0.57 (F-B) << E[max_2 z]=0.52-adjusted hurdle & << 2.95 — DSR moot (no candidate near threshold)."),
  step0_field_audit=list(result="PASS (both feasible, no estimation-substitution)",
    FA_fields="all present: NetIncome,OperatingCF,TotalAssets,Revenue,AccountsRecv(dREC),TangibleAssets(PPE) — fundamental_merged.parquet",
    FB_items="raw-monetary whitelist 43 items; 98.7% firm-years >=15, median 33; source QW<=2015/DART2016+ (flagged)"),
  dual_basis_conclusion="BOTH fail on EW-universe basis too (F-A ew_t -0.33, F-B ew_t -0.30) => NOT a cap-w benchmark artifact. Genuine absence of alpha."
)
write_json(val, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=5, na="null")

# ---- alpha_package.json (schema) ----
pkg <- list(task_id="WT-D20260713_002", as_of_date=as.character(as_of), forecast_horizon="1M",
  wt_type="discovery", selection_objective="canonical_port_t", selection_type="sweep", n_trials=2,
  alpha_vector=alpha_vector, confidence_vector=conf,
  signal_matrix_ref="stage_artifacts/WT_D20260713_002/alpha_scores.parquet",
  factor_specs=list(
    list(factor_family="EarningsQuality_Forensic", proxy="Modified-Jones Discretionary Accruals (residual)",
      formula="eps of per-FY xsec reg TA/A ~ 1/A + (dRev-dREC)/A + PPE/A ; TA=NI-OCF", lag_rule="annual, Factor_Date<=sig_date (+1m hold)",
      winsorization="1/99 per-FY", neutralization="cross-sectional z; Size-partial robustness",
      economic_rationale="discretionary (managed) accruals proxy earnings management -> negative forward (Sloan 1996, Xie 2001)",
      weight_theta=0.0, references=c("Jones 1991","Dechow-Sloan-Sweeney 1995","Xie 2001"),
      canonical_port_t_nw_lag3=res$FA$port_t_full, redundancy_cluster_id="accrual_AC13 (corr 0.991)"),
    list(factor_family="EarningsQuality_Forensic", proxy="Benford First-Digit Deviation (FSD MAD)",
      formula="mean_d |p_obs(d)-log10(1+1/d)| over 43 raw-monetary line-items, >=15 items", lag_rule="annual, Factor_Date<=sig_date (+1m hold)",
      winsorization="none (bounded MAD)", neutralization="cross-sectional z; Size-partial robustness (corr_vs_Size 0.006)",
      economic_rationale="deviation from Benford = manipulation fingerprint -> lower quality -> negative forward (Amiram 2015)",
      weight_theta=0.0, references=c("Amiram-Bozanic-Rouen 2015","Benford 1938","Nigrini 2012"),
      canonical_port_t_nw_lag3=res$FB$port_t_full, redundancy_cluster_id="benford_virgin (corr_vs_Size 0.006)")
  ),
  diagnostics=list(canonical_port_t_nw_lag3=res$FB$port_t_full, canonical_port_t_pvalue=res$FB$port_p,
    canonical_n_months=res$FB$n_months, rank_ic=res$FB$rank_ic, icir=res$FB$icir,
    monotonicity=NA, subperiod_stability=NA, turnover_proxy=res$FB$turnover, harvey_t_stat=res$FB$ric_t,
    post_neutralization_ic=res$FB$szpartial_port_t,
    note="primary diagnostics = best factor F-B. Full per-factor metrics in alpha_validation.json."),
  graduation=list(passed=FALSE, hard_gates_3=list(port_t_2p95=FALSE, oos_retention_0p7=FALSE, calmar_0p64=FALSE)),
  challenge_flags=c(
    "F-A redundant with existing AC13 (xsec corr 0.991) — modified-Jones dREC adjustment immaterial in KR; AC13 already FAILED standalone (PORT_t 0.227, Grade F).",
    "F-B null vs placebo (p=0.160) — no genuine signal structure; rank-IC wrong sign & insignificant.",
    "BOTH fail on EW-universe basis too (dual-basis) => NOT a benchmark artifact; genuine absence of alpha in KR large-cap.",
    "cap-tier: both ~90-95% OTHER (small-cap localized) — same cap-w trap family; large-cap segment signal-dead.",
    "K-IFRS 2011 + source break 2016 (QW->DART) structural breaks flagged; mitigated by monthly xsec-z (level removed).",
    "coverage 2009-06+ (frozen panel), not 2005+ — shorter than alpha-search mandate; consistent w/ sibling R17."),
  verdict="config-scoped negative (both) — screen-tier/feature. F-A -> quality composite supporting feature; F-B -> forensic EXCLUSION overlay probe or small-cap (RAMP). No add_factor."
)
write_json(pkg, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=5, na="null")

# ---- lineage (after write) ----
tryCatch({
  source(file.path(ROOT,"02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(task_id="WT-D20260713_002", package_type="alpha_package",
    method_selected="F-A ModJones DiscAccr + F-B Benford FSD (both config-scoped negative)",
    input_file_paths=c(file.path(ROOT,".cache/fundamental_merged.parquet"),
                       file.path(ROOT,"stage_artifacts/WT_D20260711_002/monthly_panel.rds")))
}, error=function(e) cat("lineage skip:", conditionMessage(e),"\n"))

cat("[03] DONE — alpha_package/validation/scores + charts emitted\n")
cat("charts:\n"); cat(paste0("  ",charts,collapse="\n"),"\n")
