# WT-D20260621_006 — assemble alpha_package_draft.json + alpha_validation.json + lineage
suppressMessages({library(data.table); library(jsonlite); library(arrow); library(dplyr)})
arrow::set_io_thread_count(2L); setDTthreads(1L)
PROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(PROOT)
OUT <- file.path(PROOT,"stage_artifacts/WT-D20260621_006")
MBX <- file.path(PROOT,"qepm/mailbox/worktask/WT-D20260621_006")
dir.create(MBX, recursive=TRUE, showWarnings=FALSE)

diag <- readRDS(file.path(OUT,"diag_primary.rds"))
scr  <- readRDS(file.path(OUT,"screen_primary.rds"))
extra<- readRDS(file.path(OUT,"extra_diag.rds"))
grid <- tryCatch(fread(file.path(OUT,"grid_is_ic.csv")), error=function(e) NULL)
ortho<- tryCatch(fread(file.path(OUT,"orthogonality.csv")), error=function(e) NULL)
top  <- fread(file.path(OUT,"latest_top20.csv"))

ric <- diag$rank_ic; dp <- diag$decile
r20 <- scr[tag=="primary_n20"]; r25 <- scr[tag=="primary_n25"]
d10 <- dp[dec=="10", mean_active]; d9 <- dp[dec=="9", mean_active]; d1 <- dp[dec=="1", mean_active]

# names for alpha_vector
ds <- open_dataset(".cache/rawdata.parquet")
nm <- ds %>% filter(Date==as.Date("2026-06-19")) %>% select(Ticker,Name) %>% collect() %>% as.data.table()
top <- merge(top, nm, by="Ticker", all.x=TRUE); setorder(top, -score)
alpha_vector <- setNames(as.list(top$alpha_hat), top$Ticker)
conf_vector  <- setNames(as.list(round(pmin(abs(top$score)/3,1),3)), top$Ticker)

# orthogonality verdict
ortho_max_am_abs <- if(!is.null(ortho)) max(ortho[factor!="score", mean_abs_corr], na.rm=TRUE) else NA_real_
L10_corr <- if(!is.null(ortho)) ortho[grepl("L10",factor), mean_corr] else NA_real_
L29_corr <- if(!is.null(ortho)) ortho[grepl("L29",factor), mean_corr] else NA_real_
ortho_clears <- !is.null(ortho) && abs(L10_corr)<0.40 && abs(L29_corr)<0.40

# ---- VERDICT logic ----
PORT_T <- r20$port_t_nw
graduates <- PORT_T >= 2.95 && r20$oos_retention >= 0.7 && r20$calmar >= 0.64
# screen_pass: top-concentrated + positive alpha but fails graduation
screen_pass <- (d10 - d9 > 0) && d10 > 0 && r20$alpha_ann > 0
verdict <- if (graduates) "GRADUATE_CANDIDATE_handoff_risk_research" else
           if (screen_pass) "SCREEN_ROUTE_OVERLAY_FR_RCMA_candidate" else "CLEAN_NEGATIVE"

pkg <- list(
  task_id = "WT-D20260621_006",
  wt_type = "discovery",
  agent = "alpha-research",
  as_of_date = "2026-06-21",
  forecast_horizon = "1M",
  hypothesis_title = "Liquidity Improvement Trend Momentum",
  selection_objective = "long_only_top20_EW_monthly",
  metric_type = "canonical_screen",
  alpha_vector = alpha_vector,
  confidence_vector = conf_vector,
  alpha_vector_note = "latest sig_date 2026-06-19, top-20 by cross-sectional z of -slope(log-Amihud,126d), liq>=2e8. alpha_hat = modest score-proportional tilt (alpha-hat only; NO weights/cov — agent_role_guard).",
  signal_matrix_ref = "stage_artifacts/WT-D20260621_006/scores_primary.rds (258 months, 2005-01..2026-06)",
  factor_specs = list(list(
    factor_family = "liquidity_dynamics",
    proxy = "LiquidityImprovementTrend",
    formula = "SIGNAL = -OLS_slope( log(winsor(|Ret_d|/(Close_d*Vol_d),1/99)) ~ standardized_time_tau ) over trailing W=126 trading days <= sig_date; higher = liquidity improving (illiquidity falling). Cross-sectional z, winsor +/-3sd.",
    lag_rule = "all signal data Date<=sig_date (C1 rolling); liquidity ADV filter t-1 (C10); volume t-1.",
    winsorization = "per-ticker-window ILLIQ 1/99; cross-sectional z +/-3sd",
    neutralization = "none (raw cross-sectional z; Size orthogonality REPORTED not neutralized)",
    economic_rationale = "A name whose price-impact cost is structurally falling becomes investable for liquidity-gated capital (foreign/institutional/pension ADV-floor mandates, index/ETF inclusion screens) and front-runs that flow. Slow-moving, distinct from level-illiquidity premium (already priced) and from return momentum (zero microstructure info).",
    weight_theta = 1.0,
    redundancy_cluster_id = "liquidity_amihud_dynamics (vs L01/L09 level, L10/L29 2-point ratio)",
    references = c("Amihud 2002 JFM", "Acharya-Pedersen 2005 (liquidity-adjusted CAPM)", "kr-novel-momentum-hunt backlog Tier-A")
  )),
  diagnostics = list(
    rank_ic = round(ric$ic_mean,5),
    icir = round(ric$icir,4),
    harvey_t_stat = round(ric$harvey_t,3),
    harvey_t_note = "rank-IC NW lag-3 t. NOT portfolio-alpha t. Near-zero: cross-sectional ranking power flat across mid-deciles; edge lives in TAILS.",
    portfolio_alpha_t_nw_lag3 = round(PORT_T,4),
    portfolio_alpha_t_top25 = round(r25$port_t_nw,4),
    net_sr = round(r20$net_sr,4),
    information_ratio = round(r20$IR,4),
    alpha_annualized = round(r20$alpha_ann,5),
    turnover_traded_bothlegs = round(r20$turnover,3),
    turnover_oneway_approx = round(r20$turnover/2,3),
    oos_retention_v2 = round(r20$oos_retention,4),
    calmar = round(r20$calmar,4),
    subperiod_stability = extra$subperiod_stability,
    era_ic = extra$era_ic,
    icir_recent3y_ratio = extra$icir_recent3y_ratio,
    monotonicity_decile_spearman = extra$monotonicity_decile_spearman,
    top20_illiquid_share = extra$top20_illiquid_share,
    metric_type = "canonical_screen",
    n_months = r20$n_months
  ),
  decile_concentration = list(
    note = "CRITICAL (C23/AX-007 lesson). Decile mean ACTIVE return (vs EW universe), 257 months.",
    decile_active = as.list(setNames(round(dp$mean_active,5), paste0("D",dp$dec))),
    decile_t = as.list(setNames(round(dp$t_active,3), paste0("D",dp$dec))),
    D10_active = round(d10,5),
    D9_active  = round(d9,5),
    D1_active  = round(d1,5),
    D10_minus_D9_gap = round(d10-d9,5),
    edge_location = if (d10-d9 > 0 && d10>0) "TOP-CONCENTRATED (D10 strongest long decile; top-20 long-only CAN capture it). Distinct from C23 mid-decile." else "mid-decile/flat -> screen-route only",
    interpretation = "Monotonicity 0.964 (highly monotone) but magnitude weak. The single SIGNIFICANT decile is the SHORT leg D1 (active -0.485%, t -2.48: 'deteriorating-liquidity' names underperform). Long leg D10 (+0.342%, t +1.47) is positive but not individually significant -> long-only harvests only the weaker half -> PORT_t 1.11."
  ),
  orthogonality = list(
    note = "Cross-sectional Spearman vs Factor DB factors (load_month_factors, C14/C15), pooled-by-date mean, every-6th-month sample.",
    matrix = if(!is.null(ortho)) lapply(seq_len(nrow(ortho[factor!="score"])), function(i){ r<-ortho[factor!="score"][i]; list(factor=r$factor, mean_corr=round(r$mean_corr,3), mean_abs_corr=round(r$mean_abs_corr,3)) }) else list(),
    L10_Amihud_Ratio_corr = round(L10_corr,3),
    L29_Illiq_Change_corr = round(L29_corr,3),
    max_abs_corr = round(ortho_max_am_abs,3),
    clears_L10_L29 = ortho_clears,
    redundancy_verdict = if(ortho_clears) "DISTINCT from L10/L29 2-point ratios (|corr|<0.40) — slope estimator adds info beyond ratios." else "REDUNDANCY RISK — does not clear L10/L29 at 0.40; reclassify as refinement."
  ),
  grid_chain = list(
    selection_type = "chain",
    selection_note = "Pre-registered hypothesis-driven chain (NOT sweep). Variant choice by IS-only rank-IC. DSR gate NOT applicable (measurement-graduation §3). PORT_t/oos/calmar are binding.",
    n_iterations = if(!is.null(grid)) nrow(grid) else NA,
    is_rank_ic_by_variant = if(!is.null(grid)) lapply(seq_len(nrow(grid)), function(i) as.list(grid[i])) else list(),
    primary_config = "W=126, OLS-std, recency>=10, frac>=0.60, DolVol, monthly, top_n=20"
  ),
  pit_c15_exception = list(
    rawdata_carveout = "Signal built from .cache/rawdata.parquet (raw daily OHLCV panel), NOT Factor DB monthly parquet. C15 governs load_month_factors() for Factor DB; raw OHLCV panel is the spec-sanctioned carve-out (backlog data_inputs + pit_notes C15; python-policy §3). Orthogonality factors ARE pulled via load_month_factors (C14 PIT-safe).",
    c13_compliance = "No NEGATE/FLIP cross-sectional. The -slope is a within-ticker DEFINITIONAL construction (improvement direction), cross-section uses higher=better z only.",
    c14_compliance = "Orthogonality Factor pulls enforce Usable_Date<=sig_date via load_month_factors direction alignment."
  ),
  verdict = verdict,
  honest_summary = sprintf(
    "Liquidity-improvement-trend (-slope of 126d log-Amihud): TOP-CONCENTRATED (D10 +%.3f%%/mo strongest long decile, D10-D9 gap +%.3f%%, monotonicity 0.964) — the OPPOSITE failure-mode from C23 (which was mid-decile). BUT realized PORT_t only %.2f (<2.95), oos_retention %.2f (FAIL), calmar %.2f (FAIL). Long-only captures only the weaker long half; the one SIGNIFICANT decile is the SHORT leg D1 (t -2.48), unusable long-only. Real positive alpha (+%.1f%%/yr, IR %.2f) but small-cap-tilted (53%% below-median ADV) and weak. Graduation HARD 3 all FAIL -> SCREEN_ROUTE. A clean, honestly-reported non-graduating positive; one data point.",
    d10*100, (d10-d9)*100, PORT_T, r20$oos_retention, r20$calmar, r20$alpha_ann*100, r20$IR)
)

write_json(pkg, file.path(MBX,"alpha_package_draft.json"), auto_unbox=TRUE, pretty=TRUE, na="null")
cat("draft written:", file.path(MBX,"alpha_package_draft.json"), "\n")
cat("VERDICT:", verdict, "\n")
cat("PORT_t:", round(PORT_T,3), " D10-D9:", round(d10-d9,5), " ortho_clears_L10L29:", ortho_clears, "\n")

# alpha_validation.json
val <- list(
  task_id="WT-D20260621_006", metric_type="canonical_screen",
  graduation_hard_gates = list(
    portfolio_alpha_t_nw = list(value=round(PORT_T,4), threshold=2.95, pass=(PORT_T>=2.95)),
    oos_retention = list(value=round(r20$oos_retention,4), threshold=0.7, pass=(r20$oos_retention>=0.7)),
    calmar = list(value=round(r20$calmar,4), threshold=0.64, pass=(r20$calmar>=0.64))
  ),
  graduation = graduates,
  screen_pass = screen_pass,
  verdict = verdict,
  pit = list(c1="rolling window only", c10="ADV t-1", c13="no flip", c14="ortho via load_month_factors", c15="rawdata OHLCV carve-out documented"),
  dsr_applicability = "NOT applicable (selection_type=chain; advisory-only; binding gates = PORT_t/oos/calmar)",
  universe = "KOSPI200 u KOSDAQ150, 2005-01..2026-06, prod liq 2e8"
)
write_json(val, file.path(MBX,"alpha_validation.json"), auto_unbox=TRUE, pretty=TRUE, na="null")
cat("validation written\n")

# alpha_scores.parquet (full signal panel) for stage_artifacts
sc_full <- readRDS(file.path(OUT,"scores_primary.rds"))
write_parquet(sc_full[,.(Date,Ticker,score)], file.path(OUT,"alpha_scores.parquet"))
cat("alpha_scores.parquet written (", nrow(sc_full), "rows )\n")

# artifact_lineage.json
lin <- list(task_id="WT-D20260621_006", canonical_path="stage_artifacts/WT-D20260621_006/",
  artifacts=c("scores_primary.rds","alpha_scores.parquet","returns_dt.rds","bench_dt.rds","liq_dt.rds",
              "diag_primary.rds","extra_diag.rds","screen_primary.csv","grid_is_ic.csv","orthogonality.csv"),
  mailbox=c("alpha_package_draft.json","alpha_validation.json"),
  note="Hyphen path WT-D20260621_006 is canonical (matches mailbox dir). No underscore variant.")
write_json(lin, file.path(MBX,"artifact_lineage.json"), auto_unbox=TRUE, pretty=TRUE)
cat("=== build_package.R DONE ===\n")
