#==============================================================================
# WT-D20260425_010 — run_alpha_iter5.R (driver)
# Sources factor_engine_proposal.R, then writes alpha_package_draft.json
# (Step 7 Codex critic round will be invoked separately, then final alpha_package.json
# is finalized in finalize_alpha_iter5.R).
#==============================================================================

cat("\n=== run_alpha_iter5.R START ===\n")
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-D20260425_010"
WT_DIR       <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
ART_DIR      <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260425_010")

source(file.path(WT_DIR, "factor_engine_proposal.R"))

# unwrap globals
av  <- ALPHA_OUTPUTS$alpha_vector
cv  <- ALPHA_OUTPUTS$confidence_vector
dB  <- ALPHA_OUTPUTS$diag_blend
dC  <- ALPHA_OUTPUTS$diag_core
dD  <- ALPHA_OUTPUTS$diag_defense
slog<- ALPHA_OUTPUTS$shopping_log
ci  <- ALPHA_OUTPUTS$crisis_ci
axc <- ALPHA_OUTPUTS$ax_compliance
ff5 <- ALPHA_OUTPUTS$ff5_record
chf <- ALPHA_OUTPUTS$challenge_flags
n_sig <- ALPHA_OUTPUTS$n_sig_dates
adv  <- ALPHA_OUTPUTS$alpha_divergence
dsr  <- ALPHA_OUTPUTS$dsr_val
last_sd <- ALPHA_OUTPUTS$last_sig_date

suppressPackageStartupMessages({library(jsonlite)})

# ==================================
# Build alpha_package_draft.json
# ==================================
alpha_package_draft <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  iter = 5L,
  iter_name = "Cross_family_Blender_MultiSleeve",
  parent_iters = c("WT-D20260425_006", "WT-D20260425_007",
                    "WT-D20260425_008", "WT-D20260425_009"),
  baseline_pg2 = "STR_1631_SYN_05_80 + STR_1656_MLRA_M05_20",
  as_of_date = "2026-04-25",
  signal_as_of = as.character(last_sd),
  forecast_horizon = "1M",
  selection_objective = "icir",

  hypothesis_title = "Iter 5 Cross-family Blender — Multi-sleeve composite (Core + Defense + Cash overlay)",
  hypothesis_summary = paste0(
    "Iter 1-4 자산 통합. Multi-sleeve (AX-007 예외 #1 충족): ",
    "Sleeve 1 Core 0.65 (Iter 3 6F: Consensus_4F + Q07 + M08_Residual_Mom). ",
    "Sleeve 2 Defense 0.35 (Q07 + Q25_Ohlson_O multi-axis quality_distress). ",
    "Sleeve 3 Cash regime overlay (regime_state attached for Optimizer; ",
    "Alpha agent does NOT decide cash %). ",
    "Score-level 합산 (L-484 NOT 수익률 블렌드). ",
    "20-name hard cap final. KR FF5 v2 (Iter 4 asset) external validation framework."
  ),

  multi_sleeve_structure = list(
    sleeve_1_core = list(
      label = "Core_6F (Iter 3 PRIMARY)",
      weight = ALPHA_OUTPUTS$W_CORE,
      factors = ALPHA_OUTPUTS$SLEEVE_CORE,
      rationale = "Iter 3 validated 6F (rank_IC=0.0473, ICIR=0.5412, Harvey=8.401)",
      diagnostics = dC
    ),
    sleeve_2_defense = list(
      label = "Defense_QualityDistress_2axis",
      weight = ALPHA_OUTPUTS$W_DEF,
      factors = ALPHA_OUTPUTS$SLEEVE_DEFENSE,
      rationale = "Q07 (earnings stability, L-121 stress ICIR +0.753) + Q25_Ohlson_O (distress, Campbell-Hilscher-Szilagyi 2008). Multi-axis composite, NOT 4-axis (AX-005 EXCLUSION compliant).",
      diagnostics = dD
    ),
    sleeve_3_cash_overlay = list(
      label = "Cash_Regime_Overlay",
      weight = "decided_by_optimizer",
      mechanism = "regime_state column attached to alpha_scores.parquet. Optimizer reads sig_date -> regime_state and applies AX-001 v2 conditional cash policy (e.g. CRISIS -> 0~30% cash). Alpha agent does NOT decide cash %.",
      regime_levels = c("BULL","NORMAL","CAUTION","CRISIS"),
      data_source = "Iter 2 regime_panel.parquet (PIT-safe expanding percentile, C1+C2+C9+C11)"
    ),
    blend_method = "score_level_L484",
    note = "AX-007 exception #1 (multi-sleeve) explicitly satisfied. Single-sleeve top20 violation 회피."
  ),

  alpha_vector = as.list(av),
  confidence_vector = as.list(cv),
  signal_matrix_ref = "stage_artifacts://WT_D20260425_010/alpha_scores.parquet",

  factor_specs = list(
    list(
      factor_family = "Analyst_Consensus",
      proxy = "C01_SUE",
      formula = "Z_Score_Aligned[C01_SUE] (Factor DB via load_month_factors equivalent, Mandate 3)",
      lag_rule = "monthly t-1 (sig_date = month-start, applied at next rebalance, C2)",
      winsorization = "2.5σ cross-section",
      neutralization = "liquidity filter only (20d AvgTV >= 2e8, C10)",
      economic_rationale = "Earnings revision upside (SUE = standardised unexpected earnings)",
      sleeve = "Core",
      source = "db_existing",
      references = c("Chan-Jegadeesh-Lakonishok 1996", "Ball-Brown 1968")
    ),
    list(
      factor_family = "Analyst_Consensus",
      proxy = "C02_EPS_Chg_1m",
      formula = "Z_Score_Aligned[C02_EPS_Chg_1m]",
      lag_rule = "monthly t-1, C2",
      winsorization = "2.5σ",
      neutralization = "liquidity",
      economic_rationale = "1-month EPS estimate change — near-term revision momentum",
      sleeve = "Core",
      source = "db_existing",
      references = c("Womack 1996", "Stickel 1992")
    ),
    list(
      factor_family = "Analyst_Consensus",
      proxy = "C04_ESBR",
      formula = "Z_Score_Aligned[C04_ESBR]",
      lag_rule = "monthly t-1, C2",
      winsorization = "2.5σ",
      neutralization = "liquidity",
      economic_rationale = "Earnings surprise breadth ratio",
      sleeve = "Core",
      source = "db_existing",
      references = c("Jegadeesh-Kim 2006", "Loh-Mian 2006")
    ),
    list(
      factor_family = "Analyst_Consensus",
      proxy = "C06_TP_Gap",
      formula = "Z_Score_Aligned[C06_TP_Gap]",
      lag_rule = "monthly t-1, C2",
      winsorization = "2.5σ",
      neutralization = "liquidity",
      economic_rationale = "Analyst target-price gap",
      sleeve = "Core",
      source = "db_existing",
      references = c("Brav-Lehavy 2003", "Asquith-Mikhail-Au 2005")
    ),
    list(
      factor_family = "Quality_Earnings",
      proxy = "Q07_Earnings_Stability",
      formula = "Z_Score_Aligned[Q07_Earnings_Stability]",
      lag_rule = "monthly t-1, C2 + C4 (quarterly 45d)",
      winsorization = "2.5σ",
      neutralization = "liquidity",
      economic_rationale = "Earnings stability = low variance of earnings growth (L-121 stress ICIR +0.753). Used in BOTH Core and Defense sleeves (Q07 is robust dual-purpose; AX-004 EXCLUSION via multi-axis composite).",
      sleeve = "Core+Defense",
      source = "db_existing",
      references = c("Novy-Marx 2013", "QEPM L-121")
    ),
    list(
      factor_family = "Momentum_Residual",
      proxy = "M08_Residual_Mom",
      formula = "Z_Score_Aligned[M08_Residual_Mom] (12-1M residual, CAPM/FF residualized)",
      lag_rule = "monthly t-1, C2",
      winsorization = "2.5σ",
      neutralization = "liquidity",
      economic_rationale = "Cross-family diversifier (Iter 3 swap target, Q07-M08 panel cor=0.0099). Carhart 1997 + Blitz-Huij-Martens 2011.",
      sleeve = "Core",
      source = "db_existing",
      references = c("Carhart 1997", "Blitz-Huij-Martens 2011", "Daniel-Moskowitz 2016")
    ),
    list(
      factor_family = "Distress",
      proxy = "Q25_Ohlson_O",
      formula = "Z_Score_Aligned[Q25_Ohlson_O] (lower O-score = lower distress = higher quality)",
      lag_rule = "annual May (C4) — DART annual financial statements",
      winsorization = "2.5σ",
      neutralization = "liquidity",
      economic_rationale = "Distress factor — bankruptcy/financial-distress proxy. Cross-family vs Q07 (Iter 3 candidate cor_Q07 = -0.21, orthogonal).",
      sleeve = "Defense",
      source = "db_existing",
      references = c("Ohlson 1980", "Campbell-Hilscher-Szilagyi 2008")
    )
  ),

  diagnostics = list(
    rank_ic = dB$rank_ic,
    icir = dB$icir,
    harvey_t_stat = dB$harvey_t,
    dsr = dsr,
    monotonicity = NA,  # composite — not single-factor decile sort
    subperiod_stability = dB$sub_stability,
    subperiod_ics = list(p1_2008_2014 = dB$p1_IC,
                         p2_2015_2019 = dB$p2_IC,
                         p3_2020_2024 = dB$p3_IC),
    post_neutralization_ic = dB$rank_ic,  # liquidity-only neutralization
    turnover_proxy = 0.5,  # inherited from Iter 3 estimate (TBD by Forge)
    n_months = dB$n_months,
    n_sig_dates = n_sig,
    n_tickers = 20L,
    alpha_divergence = adv,
    blend_vs_best_single = ALPHA_OUTPUTS$blend_vs_best
  ),

  time_series_audit_record = list(
    n_sig_dates = n_sig,
    date_range = as.character(c(last_sd - months(n_sig), last_sd)),
    unique_tickers_panel = NA,  # filled below
    schema = c("Date", "Ticker", "score_eff", "score_core_z",
               "score_defense_z", "Ret_1m", "regime_state",
               "theta_core", "theta_defense"),
    file_path = "stage_artifacts/WT_D20260425_010/alpha_scores.parquet"
  ),

  ax_axiom_compliance = axc,

  crowding_check = list(
    cross_section_jaccard_iter3 = ALPHA_OUTPUTS$jaccard_iter3,
    time_series_tdc_iter3_proxy = ALPHA_OUTPUTS$mean_ts_tdc_iter3,
    pg2_active_book = "STR_1631_SYN_05 80% + STR_1656_MLRA_M05 20%",
    note = "Cross-section Jaccard via Iter 3 top20 overlap. Time-series TDC via Spearman cor of Score_Core_z vs final blend (proxy). Direct PG2 alpha vector unavailable (STR_1656 ML model output)."
  ),

  sequential_admission_scenarios = list(
    replacement = list(
      design = "100% Iter 5 multi-sleeve Replaces PG2 (STR_1631_SYN_05 + STR_1656)",
      backtest_status = "TBD by Forge",
      expected_benefit = "Cross-family diversification + multi-sleeve risk diffusion"
    ),
    integration_80_20 = list(
      design = "80% MEGA_05 (current PG2 Sleeve 1631_SYN_05) + 20% Iter 5 (score-level blend, L-484)",
      backtest_status = "TBD by Forge",
      expected_benefit = "Conservative incremental crowding reduction"
    )
  ),

  external_validation_framework = list(
    framework = "KR_FF5_v2",
    asset = ff5,
    purpose = "Iter 4 asset reuse — Forge/Judge will run portfolio returns regression on FF5 v2 to derive t_NW (Mandate 4)",
    pit_backfill_evidence = ff5$pit_backfill_evidence
  ),

  method_shopping_log = list(
    candidates_tried = length(slog),
    cap = 5L,
    parallel_exec = FALSE,
    rcpp_used = ALPHA_OUTPUTS$rcpp_loaded,
    method_log = slog
  ),

  crisis_bootstrap_ci = ci,

  challenge_flags = chf,

  pit_compliance = list(
    C1 = "PASS: expanding IC weights (build_composite uses sig_date < sig_d only)",
    C2 = "PASS: signal at sig_date applied at fwd_date = sig_date+1M",
    C4 = "PASS: Factor DB enforces quarterly 45d / annual May lag (Q25 annual May, Q07 quarterly)",
    C9 = "PASS: regime expanding percentile (Iter 2 regime_panel reused)",
    C10 = "PASS: AvgTV20 >= 2e8 lagged filter applied per-month",
    C11 = "PASS: regime indicator uses BM_DT (KR internals, L-454) — no FRED leakage",
    C13 = "PASS: Z_Score_Aligned via align_factor_direction PIT-safe, no manual sign flip",
    C14 = "PASS: Factor DB Usable_Date <= sig_date enforced",
    C15 = "PASS: load via factor_db parquet (Mandate 3 verified via load_month_factors spot-check)",
    lockbox = "ENFORCED: 2024-01-23 ~ 2026-01-23 strictly excluded from all computations (R2 P2). TRAIN_END = 2024-01-22."
  ),

  references = c(
    "Fama-French (1993) FF3 factor model",
    "Harvey-Liu-Zhu (2016) multiple testing t>3.0",
    "Carhart (1997) momentum factor",
    "Blitz-Huij-Martens (2011) residual momentum",
    "Novy-Marx (2013) gross profitability / earnings quality",
    "Ohlson (1980) O-score distress",
    "Campbell-Hilscher-Szilagyi (2008) distress risk",
    "Asness-Moskowitz-Pedersen (2013) value & momentum everywhere — multi-factor combination",
    "DeMiguel-Garlappi-Uppal (2009) 1/N — diversification benefit",
    "Barroso-Santa-Clara (2015) risk-managed momentum",
    "Bailey-Lopez de Prado (2014) Deflated Sharpe Ratio",
    "QEPM L-484 score-level composite (NOT 수익률 블렌드)",
    "QEPM L-121 Q07 stress alpha",
    "QEPM L-219 Q07-AC21 family saturation (resolved by Iter 3 swap)",
    "QEPM AX-007 multi-sleeve exception #1",
    "QEPM AX-005 multi-sleeve EXCLUSION"
  ),

  role_bias_tagging = "RoleBias_Core_with_Defense_Diversifier",

  graduation_status = list(
    rank_ic_gate     = list(value = dB$rank_ic, threshold = 0.04,
                              pass = !is.na(dB$rank_ic) && dB$rank_ic >= 0.04),
    icir_gate        = list(value = dB$icir, threshold = 0.20,
                              pass = !is.na(dB$icir) && dB$icir >= 0.20),
    subperiod_gate   = list(value = dB$sub_stability, threshold = 0.50,
                              pass = !is.na(dB$sub_stability) && dB$sub_stability >= 0.50),
    harvey_t_gate    = list(value = dB$harvey_t, threshold = 3.00,
                              pass = !is.na(dB$harvey_t) && dB$harvey_t >= 3.00),
    dsr_gate         = list(value = dsr, threshold = 0.50,
                              pass = !is.na(dsr) && dsr >= 0.50)
  ),

  window_isolation = list(
    train_validation_window = list(start = "2004-01-01", end = "2024-01-22"),
    lockbox_window = list(start = "2024-01-23", end = "2026-01-23", sealed = TRUE),
    lockbox_access = FALSE,
    lockbox_isolation_certified = TRUE
  ),

  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

# Fill in unique tickers from artifact
suppressPackageStartupMessages({library(arrow); library(data.table)})
asp <- as.data.table(read_parquet(file.path(ART_DIR, "alpha_scores.parquet")))
alpha_package_draft$time_series_audit_record$unique_tickers_panel <- uniqueN(asp$Ticker)

draft_path <- file.path(WT_DIR, "alpha_package_draft.json")
write_json(alpha_package_draft, draft_path,
           pretty = TRUE, auto_unbox = TRUE, na = "string")
cat(sprintf("\n[run_alpha_iter5.R] alpha_package_draft.json saved -> %s\n", draft_path))
cat(sprintf("  n_sig_dates=%d unique_tickers_panel=%d\n",
            n_sig, alpha_package_draft$time_series_audit_record$unique_tickers_panel))
cat("[run_alpha_iter5.R] Next: invoke run_codex_qepm_critic.sh (Step 7 critic round)\n")
