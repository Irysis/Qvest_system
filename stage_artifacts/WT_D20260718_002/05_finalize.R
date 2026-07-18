# WT-D20260718_002 — emit alpha_validation.json, alpha_package.json, alpha_scores.parquet
suppressWarnings(suppressMessages({library(arrow); library(data.table); library(jsonlite)}))
setDTthreads(1)
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT <- file.path(R, "stage_artifacts/WT_D20260718_002")
MBX <- file.path(R, "qepm/mailbox/worktask/WT-D20260718_002")
res <- read_json(file.path(OUT,"exclusion_ab_results.json"), simplifyVector=TRUE)
sw  <- as.data.table(arrow::read_parquet(file.path(OUT,"sweep_results.parquet")))

# alpha_scores.parquet = the tested exclusion signal (primary si_off_6) per Date/Ticker
base <- as.data.table(arrow::read_parquet(file.path(OUT,"base_panel.parquet")))
ins  <- as.data.table(arrow::read_parquet(file.path(OUT,"insider_sell_panel.parquet")))
sc <- merge(base[,.(Date,ym,Ticker,mom_score,Size)], ins[,.(ym,Ticker,cnv_off_6)], by=c("ym","Ticker"), all.x=TRUE)
sc[is.na(cnv_off_6), cnv_off_6:=0]
sc[, sell_intensity_off6 := -cnv_off_6/Size]   # >0 = net officer selling rel to mcap (exclusion signal)
sc[, exclusion_score := -sell_intensity_off6]  # higher = more preferred (less selling); for schema
arrow::write_parquet(sc[,.(Date,Ticker,mom_score,sell_intensity_off6,exclusion_score)],
                     file.path(OUT,"alpha_scores.parquet"))

n_neg_sweep <- sum(sw$paired_t_nw3 < 0)
alpha_validation <- list(
  task_id="WT-D20260718_002",
  as_of_date="2026-07-18",
  hypothesis="Insider-selling universe EXCLUSION filter (Miller-1977 long-only overvaluation harvest)",
  design="exclusion overlay paired A/B — base mom_12_1 top-25 EW vs base with insider net-seller tickers removed; canonical_screen_bt cap-w PORT_t 1급; top_n=25, liq 2e8, 15bps delta cost; period 2004-12..2026-06 (259 mo)",
  verdict="FALSIFIED",
  pin_tag=res$pin_tag,
  metric_type="canonical_screen",
  canonical_paired = list(
    base_port_t_capw = res$A$port_t_capw,
    treatment_port_t_capw = res$primary$port_t_capw_B,
    paired_diff_annualized = res$primary$paired_diff_ann,
    paired_t_nw_lag3 = res$primary$paired_t_nw3,
    interpretation = "exclusion DEGRADES base momentum (paired diff negative, t=-1.35). Kill criterion (paired_t<2) met — in fact negative.",
    avg_excluded_per_month = res$primary$avg_excl_per_month,
    n_months = res$primary$n_months
  ),
  sweep_robustness = list(
    n_cells = nrow(sw),
    n_cells_negative_t = n_neg_sweep,
    all_negative = (n_neg_sweep == nrow(sw)),
    best_cell_paired_t = max(sw$paired_t_nw3),
    note = "18 sweep cells (scope off/all x L 3/6/12 x P 5/10/20) + 3 alt-intensity (gross/breadth/gross-P20) = 21/21 negative paired_t"
  ),
  dual_basis = list(
    base_ew_uni_port_t = res$A$ew_uni_port_t,
    treatment_ew_uni_port_t = res$primary$ew_uni_B_port_t,
    negative_holds_in_ew_basis = TRUE,
    excluded_median_size_pct = res$dual_basis$excl_median_size_pct,
    excluded_tier_mix = res$dual_basis$excl_tier_mix,
    conclusion = "excluded names upper-third by size (median size-pct 0.284), NOT small-cap-localized; negative holds in both cap-w (1.171->0.771) and EW-uni (1.857->1.442) => not a benchmark-construction artifact"
  ),
  ax001_v2 = list(
    crisis_diff_annualized = res$ax001v2$crisis_diff_ann,
    normal_diff_annualized = res$ax001v2$normal_diff_ann,
    crisis_defense = FALSE,
    note = "crisis-period paired diff still negative (-0.99%/yr); exclusion provides no defensive value"
  ),
  is_oos = res$is_oos,
  pit = list(
    overlay_pit_guard = "PASS (formation month-end < holding-month start)",
    lag1_stress = list(lag1_diff_ann=res$lag1$paired_diff_ann, lag1_t=res$lag1$paired_t_nw3,
                       lookahead_suspected=res$lag1$lookahead_suspected,
                       note="primary MORE negative than lag1 => no upward look-ahead; signal genuinely lagged"),
    signal_timing="rcept_dt month <= formation month; holding = formation+1; C5 clean"
  ),
  differentiation = "R9 = insider as long-side SELECTION signal (config-scoped neg); R33/R37 = MONITORING per-holding hold-safety (sell direction t~0); THIS = EXCLUSION from base universe (Miller harvest). Distinct mechanism, convergent null => triangulation.",
  selection_objective="canonical_port_t",
  kill_registered = TRUE
)
write_json(alpha_validation, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, na="null")
file.copy(file.path(OUT,"alpha_validation.json"), file.path(MBX,"alpha_validation.json"), overwrite=TRUE)

# alpha_package.json (schema-shaped; terminal negative — no admittable alpha)
alpha_package <- list(
  task_id="WT-D20260718_002",
  as_of_date="2026-07-18",
  forecast_horizon="1M",
  wt_type="discovery",
  status="ALPHA_DONE_NEGATIVE",
  alpha_discovery_certificate="NOT_ISSUED",
  certificate_rationale="exclusion filter FALSIFIED — no positive PORT_t contribution; paired diff negative across 21/21 configs",
  alpha_vector=NULL,
  confidence_vector=NULL,
  alpha_vector_note="No standalone selection alpha emitted — hypothesis was an EXCLUSION overlay, which is falsified. alpha_scores.parquet holds the tested exclusion signal (sell_intensity_off6) for audit.",
  factor_specs=list(list(
    factor_family="Insider_Trading",
    proxy="officer on-market net-sell intensity (exclusion filter)",
    formula="sell_intensity = -sum(qty_change*price over L=6mo, officer 장내 trades)/market_cap; exclude top-P% net sellers from universe",
    lag_rule="rcept_dt month <= formation month (C5 overlay timing)",
    winsorization="none (raw net value)",
    neutralization="none (universe exclusion, not cross-sectional score)",
    economic_rationale="Miller-1977: KR short-sale constraint prevents short-side correction of insider-signalled overvaluation; excluding heavy insider sellers from long-only universe hypothesized to harvest avoided overvaluation. FALSIFIED — insider-sold momentum names outperform replacements.",
    weight_theta=0,
    references=list("Miller 1977 JF","Cohen-Malloy-Pomorski 2012 (routine vs opportunistic)","R9/R33 internal (KR insider frames)")
  )),
  diagnostics=list(
    canonical_port_t_nw_lag3 = alpha_validation$canonical_paired$treatment_port_t_capw,
    base_canonical_port_t_nw_lag3 = alpha_validation$canonical_paired$base_port_t_capw,
    paired_diff_t_nw_lag3 = alpha_validation$canonical_paired$paired_t_nw_lag3,
    canonical_n_months = 259,
    sweep_all_negative = TRUE,
    metric_type="canonical_screen"
  ),
  selection_objective="canonical_port_t",
  challenge_flags=list(
    "FALSIFIED: exclusion degrades base momentum PORT_t (paired t=-1.35, 21/21 configs negative)",
    "R33 sell-side t~0 triangulated across selection/monitoring/exclusion frames",
    "SCOPE-LIMIT (frontier): exclusion untested on value/incumbent multi-factor base",
    "no crisis defense (AX-001 v2 crisis diff still negative)"
  ),
  next_probe=list(
    "value/incumbent-book base exclusion (different overvaluation clustering than momentum) — low prior given base-agnostic null",
    "insider-sell as DOWN-WEIGHT (soft) rather than hard exclusion within a sleeve — but that re-enters R9 selection wall",
    "non-return, non-insider frontier per layer_bottleneck_map (momentum decay bottleneck unresolved by insider material)"
  ),
  revival_condition="if a future KR short-sale regime change or a insider-sell frame shows forward-underperformance signal (currently null across 3 frames), revisit exclusion.",
  pin_tag=res$pin_tag
)
write_json(alpha_package, file.path(MBX,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, na="null")

# lineage
tryCatch({
  source(file.path(R,"02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(task_id="WT-D20260718_002", package_type="alpha_package",
    method_selected="insider net-sell EXCLUSION overlay paired A/B (FALSIFIED)",
    input_file_paths=c(file.path(OUT,"base_panel.parquet"),
                       file.path(OUT,"insider_sell_panel.parquet"),
                       file.path(OUT,"exclusion_ab_results.json")))
  cat("[lineage] recorded\n")
}, error=function(e) cat("[lineage] skipped:", conditionMessage(e), "\n"))

cat("[DONE] alpha_package.json + alpha_validation.json + alpha_scores.parquet emitted\n")
cat("  MBX:", MBX, "\n")
