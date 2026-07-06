# emit_package.R — WT-D20260706_006 dividend-signaling alpha_package emission (VALIDATED_NEGATIVE)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1L)
PR<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT<-file.path(PR,"stage_artifacts/dividend_signaling_wt006")
MBX<-file.path(PR,"qepm/mailbox/worktask/WT-D20260706_006")
SA <-file.path(PR,"stage_artifacts/WT-D20260706_006"); dir.create(SA, showWarnings=FALSE, recursive=TRUE)

res <- fromJSON(file.path(OUT,"dividend_result.json"))
scores <- as.data.table(read_parquet(file.path(OUT,"div_scores.parquet"))); scores[,Date:=as.Date(Date)]

# alpha_vector = latest sig-date cross-sectional z-score of div_yoy (payers), higher=bigger increase
last_dt <- max(scores[is.finite(div_yoy)]$Date)
lastsc <- scores[Date==last_dt & is.finite(div_yoy), .(Ticker, div_yoy)]
mu<-mean(lastsc$div_yoy); sdv<-sd(lastsc$div_yoy)
lastsc[, z := (div_yoy-mu)/sdv]
lastsc[, z := pmin(pmax(z,-3),3)]  # winsorize 3std for the vector
alpha_vector <- setNames(as.list(round(lastsc$z,6)), lastsc$Ticker)
# confidence: inverse of |z| extremity + payer coverage; simple bounded proxy (signal is dead so all low)
lastsc[, conf := pmax(0.02, pmin(0.4, 0.15*exp(-abs(z)/2)))]
confidence_vector <- setNames(as.list(round(lastsc$conf,4)), lastsc$Ticker)

# alpha_scores.parquet (full panel: Date, Ticker, div_yoy, div_yoy_wins, div_increased, tier, mcap_rank)
asc <- scores[is.finite(div_yoy), .(Date, Ticker, div_yoy, div_yoy_wins, div_increased, div_initiate, tier, mcap_rank, Size)]
write_parquet(asc, file.path(SA,"alpha_scores.parquet"))

ct <- res$canonical_top25_div_yoy
tier <- res$cap_tier_longshort
cg <- res$closet_guard

pkg <- list(
  task_id="WT-D20260706_006", wt_type="discovery", as_of_date="2026-07-06",
  forecast_horizon="1M",
  verdict="VALIDATED_NEGATIVE",
  escape_verdict="NO_ESCAPE — dividend-signaling has zero/negative picking edge in every cap-tier; mega-tier is actively negative (LS t=-1.51 raw / -1.41 binary). NOT closet-index (active-share 0.925, mega weight in book 3.5%): it genuinely picks small-cap dividend-increasers, and those picks LOSE. Information-escape thesis (that holds for INSIDER, ICIR 1.31) does NOT generalize to the dividend channel. dividend != insider.",
  verdict_summary=paste0("KR dividend-change signaling (Lintner) 정식 canonical PORT_t 실측 = 신호 부재 확정. div_yoy top-25 EW long-only PORT_t=", ct$port_t_nw_full, " (IR ", ct$information_ratio, ", rank-IC ", ct$rank_ic, "≈0), 전기간 post-2017(2016-05~2026-05, ", ct$n_months, "개월). 신호 구성 3변형(raw/winsorized/binary '배당증가') 전부 음(-1.90/-1.90/-1.22) -> outlier 아티팩트 아님. ★cap-tier 분해: mega LS t=", tier$mega$ls_t_full, " (음), mid ", tier$mid$ls_t_full, ", small ", tier$small$ls_t_full, " — 어느 tier도 양의 엣지 없고 mega는 능동적 음. mega-escape 반증. distinctness: corr(div_yoy, level)~0.21 -> value/quality proxy 아닌 distinct 신호가 genuinely dead. insider(정보신호, large-cap lead)와 달리 배당 signaling은 트랩 탈출 실패 -> 정보-신호 일반화 thesis 좁혀짐(insider-특수)."),
  alpha_vector=alpha_vector,
  confidence_vector=confidence_vector,
  signal_matrix_ref=paste0("file://", file.path(SA,"alpha_scores.parquet")),
  selection_objective="rank_ic",
  alpha_discovery_count=0L,
  alpha_discovery_note="VALIDATED_NEGATIVE: no deployable alpha discovered. div_yoy signal is dead in all cap-tiers. alpha_vector emitted for completeness (latest-date z-score) but carries no admission claim.",
  factor_specs=list(list(
    factor_family="DividendPolicy_Signaling",
    proxy="DividendGrowthYoY_Lintner",
    formula="div_yoy = annual_cash_dividends_paid[fy] / annual_cash_dividends_paid[fy-1] - 1. Source: DART CF-statement DividendsPaid (ifrs-full_DividendsPaid / dart_AnnualDividendsPaid / 배당금지급 / 연차배당 / 현금배당), abs, CFS-preferred, dedup 1 line/firm-year. Excludes DividendsReceived/StockDividends/HybridBond/Noncontrolling. Initiation dummy = 1 if div_paid[fy]>0 & div_paid[fy-1]==0.",
    lag_rule="annual May (fy report filed ~Mar fy+1, usable_ym=(fy+1)-05, held to (fy+2)-04). C4 + C1 rolling + C14 usable<=sig. liq t-1 ADV20 C10.",
    winsorization="3std on emitted z-vector; robustness tested raw/clip[-0.9,3.0]/binary",
    neutralization="none (raw cross-sectional rank); distinctness vs level checked (corr~0.21)",
    economic_rationale="Lintner (1956) signaling: managers raise dividends only when confident of sustainable future earnings -> dividend INCREASES should predict positive returns. CHANGE/signaling channel, distinct from dividend-yield LEVEL (value, dead in KR) and profitability LEVEL (quality, dead). Tested specifically for mega-tier trap-escape (information signal in large-caps where price signals die).",
    weight_theta=0.0,
    references=c("Lintner 1956","Michaely-Thaler-Womack 1995 (dividend initiations/omissions drift)","Grullon-Michaely-Swaminathan 2002")
  )),
  diagnostics=list(
    metric_type_authoritative="canonical_screen (portfolio_alpha_t_nw_lag3, NW lag-3). NOT forge build_bt_result — screening 실측, admission binding 아님.",
    signal_window=res$signal_window,
    n_months=ct$n_months,
    port_t_nw_full=ct$port_t_nw_full,
    port_t_pre2017=ct$port_t_pre2017,
    port_t_post2017=ct$port_t_post2017,
    information_ratio=ct$information_ratio,
    net_sr=ct$net_sr,
    alpha_annualized=ct$alpha_annualized,
    turnover_annual=ct$turnover_annual,
    oos_retention=ct$oos_retention,
    rank_ic=ct$rank_ic,
    icir=ct$icir,
    harvey_t_rankic=ct$harvey_t_rankic,
    rank_ic_post2017=ct$rank_ic_post2017,
    rank_ic_vs_port_t_note="rank-IC(신호력)와 portfolio-alpha t(실현) 구분: 둘 다 음/null 일관.",
    robustness_variants=list(
      div_yoy_raw_port_t=-1.904,
      div_yoy_winsorized_port_t=-1.904,
      div_increased_binary_port_t=-1.215,
      note="3 constructions all negative -> not an outlier artifact"
    ),
    cap_tier_longshort=list(
      mega=list(ls_t_full=tier$mega$ls_t_full, ls_t_post2017=tier$mega$ls_t_post2017, ls_t_post2020=tier$mega$ls_t_post2020, avg_names=tier$mega$avg_names),
      mid =list(ls_t_full=tier$mid$ls_t_full,  ls_t_post2017=tier$mid$ls_t_post2017,  ls_t_post2020=tier$mid$ls_t_post2020,  avg_names=tier$mid$avg_names),
      small=list(ls_t_full=tier$small$ls_t_full, ls_t_post2017=tier$small$ls_t_post2017, ls_t_post2020=tier$small$ls_t_post2020, avg_names=tier$small$avg_names)
    ),
    mega_top4_longonly=res$mega_top4_longonly,
    initiation_book=res$dividend_initiation_book,
    closet_guard=cg,
    distinctness=res$distinctness
  ),
  graduation_gate_check=list(
    port_t_hard_2p95=ct$port_t_nw_full, port_t_pass=(ct$port_t_nw_full>=2.95),
    oos_retention_hard_0p7=ct$oos_retention,
    verdict="FAIL — PORT_t -1.90 << 2.95, negative alpha. No screen_route (dead in all tiers; not OVERLAY/FR/DPL candidate since sign is negative everywhere)."
  ),
  universe="KR_top342 (KOSPI200 ∪ KOSDAQ150, liq>=2e8)",
  period=res$signal_window,
  rebalance="monthly (annual signal, held 12mo)",
  cost_model_version="v2.4_kr_retail_15bps",
  differentiation_vs_prior="Distinct from prior FAILs: (1) NOT value (corr w/ dividend level 0.21) (2) NOT price/return-derived (accounting signaling channel) (3) tests dividend as the last information-signal escape candidate after insider(ICIR 1.31) motivated the thesis. Result: dividend != insider — information-escape does NOT generalize.",
  challenge_flags=list(
    list(id="SELF-1", severity="MEDIUM", concern="div_yoy = value/quality proxy (dead family)", disposition="ACCEPT->resolved: corr(div_yoy,level)~0.21 -> distinct signal, genuine negative"),
    list(id="SELF-2", severity="MEDIUM", concern="extreme outliers (max 8583x) drive garbage top-25", disposition="ACCEPT->resolved: binary '배당증가' variant (outlier-immune) also negative -1.22"),
    list(id="SELF-3", severity="MEDIUM", concern="annual->May lag wrong (lookahead or suppression)", disposition="ACCEPT->resolved: filing-calendar-derived usable date, PIT-clean; lookahead would help not hurt"),
    list(id="SELF-4", severity="MEDIUM", concern="post-2017 mega edge = specific-firm artifact", disposition="ACCEPT->resolved: mega negative under 3 encodings, no positive to attribute"),
    list(id="SELF-5", severity="LOW", concern="low mega breadth (~7/10) underpowers mega test", disposition="PARTIAL: mega thin but powered tiers (full 207, ex-mega) also negative; underpower cannot rescue a thesis needing a positive")
  ),
  posterior="dividend-signaling (Lintner change channel) = VALIDATED_NEGATIVE in KR top-342, all cap-tiers, 2016-2026. Retry low-EV. Information-escape thesis now insider-specific (not a general 'information signals escape mega' law). Non-return frontier narrows: insider historical parse remains the highest-EV escape candidate.",
  next_step_recommendation="Close dividend channel. Do NOT proceed to risk/optimizer (negative alpha, no book contribution). The information-escape thesis is confirmed insider-specific. Highest remaining EV = DART insider historical backfill (elestock document-parse, in progress per MEMORY)."
)

write_json(pkg, file.path(MBX,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)
write_json(pkg, file.path(MBX,"alpha_package_draft.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)

# alpha_validation.json (diagnostics + universe_comparison placeholder + gates)
val <- list(
  task_id="WT-D20260706_006", as_of="2026-07-06", metric_type="canonical_screen",
  verdict="VALIDATED_NEGATIVE", escape="NO_ESCAPE (dividend != insider)",
  canonical=ct, cap_tier=tier, closet_guard=cg, distinctness=res$distinctness,
  robustness=list(raw=-1.904, winsorized=-1.904, binary=-1.215),
  graduation_gates=res$graduation_gates,
  universe_comparison=list(note="KR_top342 only; v2 (TOP500_FREEFLOAT) not run — signal dead in base universe with clear negative sign, universe expansion cannot flip a negative alpha to >2.95. attenuation not the issue (rank-IC ~0)."),
  coverage=list(payers_with_yoy_per_month_median=207, mega_payers_per_month_median=7,
    signal_window="2016-05..2026-05 (108 forward months, entirely post-2017)",
    dart_annual_history="bsns_year 2015-2024 (annual DART financials start 2015; first YoY 2016 vs 2015 usable 2017-05)")
)
write_json(val, file.path(MBX,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)
file.copy(file.path(MBX,"alpha_validation.json"), file.path(SA,"alpha_validation.json"), overwrite=TRUE)

# lineage (after write, per L-194 order)
tryCatch({
  source(file.path(PR,"02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(task_id="WT-D20260706_006", package_type="alpha_package",
    method_selected="dividend-signaling Lintner div_yoy (VALIDATED_NEGATIVE)",
    input_file_paths=c(file.path(OUT,"div_scores.parquet"), file.path(OUT,"dividend_result.json")))
}, error=function(e) cat("[lineage] skipped:", conditionMessage(e), "\n"))

cat("[emit] alpha_package.json + alpha_validation.json + alpha_scores.parquet written\n")
cat(sprintf("[emit] verdict=VALIDATED_NEGATIVE  PORT_t=%.3f  mega_LS_t=%.3f  active_share=%.3f\n",
    ct$port_t_nw_full, tier$mega$ls_t_full, cg$avg_active_share))
