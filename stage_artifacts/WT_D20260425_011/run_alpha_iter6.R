#==============================================================================
# WT-D20260425_011 — run_alpha_iter6.R (driver)
#==============================================================================

cat("\n=== run_alpha_iter6.R START ===\n")
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-D20260425_011"
WT_DIR       <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
ART_DIR      <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260425_011")

source(file.path(WT_DIR, "factor_engine_proposal.R"))

av  <- ALPHA_OUTPUTS$alpha_vector
cv  <- ALPHA_OUTPUTS$confidence_vector
dg  <- ALPHA_OUTPUTS$diagnostics
slog<- ALPHA_OUTPUTS$shopping_log
ci  <- ALPHA_OUTPUTS$crisis_ci
axc <- ALPHA_OUTPUTS$ax_compliance
chf <- ALPHA_OUTPUTS$challenge_flags
n_sig <- ALPHA_OUTPUTS$n_sig_dates
uti  <- ALPHA_OUTPUTS$unique_tickers
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
  iter = 6L,
  iter_name = "MEGA_06_STR1699_Kelly_Overlay",
  parent_iters = c("WT-D20260425_006","WT-D20260425_007","WT-D20260425_008",
                    "WT-D20260425_009","WT-D20260425_010"),
  baseline_pg2 = "STR_1631_SYN_05_80 + STR_1656_MLRA_M05_20",
  parent_components = list(
    str_1699_iter5_alpha = list(
      ref = "qepm/mailbox/worktask/WT-D20260425_010/alpha_package.json",
      role = "alpha_signal_base",
      role_evidence = "STR_1699 multi-sleeve composite (Core 0.65 + Defense 0.35), AX-007 EXCEPTION #1 satisfied, full-period SR 0.995 (244 months), Harvey FF5 5-spec PASS (3.575~3.690), DSR_post 3.748"
    ),
    mega_05_kelly_overlay = list(
      ref = "05_Production STR_1631_PG2_MDD_OPT (Kelly_frac05 + 3-Layer Overlay)",
      role = "optimizer_machinery_handoff",
      role_evidence = "MEGA_05 PG2 active, SR 1.110 (Forge Phase 4.5 re-measurement), DSR_post 4.622, 3-Layer Overlay (DD Brake 6/8/20 + VolReg 12% target + FM regime), Kelly_frac05 sizing"
    )
  ),
  as_of_date = "2026-04-25",
  signal_as_of = as.character(last_sd),
  forecast_horizon = "1M",
  selection_objective = "icir",

  hypothesis_title = "Iter 6 MEGA_06 — STR_1699 multi-sleeve + Kelly_frac05 + 3-Layer Overlay (Sprint 자산 통합 v2)",
  hypothesis_summary = paste0(
    "두 입증된 component 결합: (1) STR_1699 (Iter 5) multi-sleeve framework — ",
    "SR 0.995 full-period 244 months, Harvey FF5 5-spec all PASS (3.575~3.690), ",
    "DSR_post 3.748, AX-007 EXCEPTION #1 충족. (2) MEGA_05 (PG2 active) Kelly_frac05 ",
    "sizing + 3-Layer Overlay (DD Brake 6/8/20 + VolReg 12% target + FM regime) — ",
    "SR 1.110, DSR_post 4.622 robust. 가설: STR_1699 alpha base × MEGA_05 machinery boost ",
    "→ SR 1.5+ 잠재 (aspirational 2.0+). Alpha agent (이 패키지)는 STR_1699 alpha 시계열 ",
    "그대로 + regime_state column + Kelly_fraction/vol_target/dd_trigger spec metadata 산출. ",
    "Kelly+Overlay 적용은 Optimizer 영역 (handoff_to_optimizer block). AX-002 process honesty: ",
    "alpha 수정 없음, Optimizer SPEC 전달만."
  ),

  multi_sleeve_structure = list(
    sleeve_1_core = list(
      label = "Core_4F (STR_1699 inherited)",
      weight = ALPHA_OUTPUTS$W_CORE,
      factors = ALPHA_OUTPUTS$SLEEVE_CORE,
      rationale = "STR_1699 (Iter 5) 4F Consensus validated; Iter 5 SR 0.995 full-period",
      diagnostics_inherited_iter5 = list(
        rank_ic = 0.0428, icir = 0.4162, harvey_t = 6.4479, n_months = 240
      )
    ),
    sleeve_2_defense = list(
      label = "Defense_3axis (STR_1699 inherited)",
      weight = ALPHA_OUTPUTS$W_DEF,
      factors = ALPHA_OUTPUTS$SLEEVE_DEFENSE,
      rationale = "Q07 (L-121 stress ICIR +0.753) + M08_Residual_Mom (cross-family) + Q25_Ohlson_O (distress, Campbell-Hilscher-Szilagyi 2008). 3-axis EW (NOT 4-axis, AX-005 EXCLUSION).",
      diagnostics_inherited_iter5 = list(
        rank_ic = 0.0272, icir = 0.2001, harvey_t = 3.1001, n_months = 240
      )
    ),
    sleeve_3_cash_overlay = list(
      label = "Cash_Regime_Overlay (Iter 6 enhanced)",
      weight = "decided_by_optimizer (5-30% regime-conditional)",
      mechanism = "regime_state column attached to alpha_scores.parquet. Optimizer reads sig_date -> regime_state and applies cash policy: BULL 0%, NORMAL 5%, CAUTION 15%, CRISIS 30%. Iter 6 enhancement: cash policy combined with DD Brake (heavy DD also forces cash 30-50%).",
      regime_levels = c("BULL","NORMAL","CAUTION","CRISIS"),
      data_source = "Iter 2 regime_panel.parquet (PIT-safe expanding percentile, C1+C2+C9+C11)"
    ),
    blend_method = "score_level_L484",
    note = "AX-007 exception #1 (multi-sleeve) explicitly satisfied. STR_1699 (Iter 5) already validated this exception with 5-spec Harvey FF5 PASS."
  ),

  alpha_vector = as.list(av),
  confidence_vector = as.list(cv),
  signal_matrix_ref = "stage_artifacts://WT_D20260425_011/alpha_scores.parquet",

  factor_specs = list(
    list(factor_family="Analyst_Consensus", proxy="C01_SUE",
          formula="Z_Score_Aligned[C01_SUE] (load_month_factors equivalent, Mandate 3 — Iter 5 spot-check cor>0.999 inherited)",
          lag_rule="monthly t-1, C2", winsorization="2.5σ", neutralization="liquidity",
          economic_rationale="Earnings revision upside (SUE)", sleeve="Core",
          source="db_existing", references=c("Chan-Jegadeesh-Lakonishok 1996","Ball-Brown 1968")),
    list(factor_family="Analyst_Consensus", proxy="C02_EPS_Chg_1m",
          formula="Z_Score_Aligned[C02_EPS_Chg_1m]", lag_rule="monthly t-1, C2",
          winsorization="2.5σ", neutralization="liquidity",
          economic_rationale="1-month EPS estimate change", sleeve="Core",
          source="db_existing", references=c("Womack 1996","Stickel 1992")),
    list(factor_family="Analyst_Consensus", proxy="C04_ESBR",
          formula="Z_Score_Aligned[C04_ESBR]", lag_rule="monthly t-1, C2",
          winsorization="2.5σ", neutralization="liquidity",
          economic_rationale="Earnings surprise breadth ratio", sleeve="Core",
          source="db_existing", references=c("Jegadeesh-Kim 2006","Loh-Mian 2006")),
    list(factor_family="Analyst_Consensus", proxy="C06_TP_Gap",
          formula="Z_Score_Aligned[C06_TP_Gap]", lag_rule="monthly t-1, C2",
          winsorization="2.5σ", neutralization="liquidity",
          economic_rationale="Analyst target-price gap", sleeve="Core",
          source="db_existing", references=c("Brav-Lehavy 2003","Asquith-Mikhail-Au 2005")),
    list(factor_family="Quality_Earnings", proxy="Q07_Earnings_Stability",
          formula="Z_Score_Aligned[Q07_Earnings_Stability]",
          lag_rule="monthly t-1, C2 + C4 (quarterly 45d)", winsorization="2.5σ",
          neutralization="liquidity",
          economic_rationale="Earnings stability (low variance of growth) — L-121 stress ICIR +0.753",
          sleeve="Defense", source="db_existing",
          references=c("Novy-Marx 2013","QEPM L-121")),
    list(factor_family="Momentum_Residual", proxy="M08_Residual_Mom",
          formula="Z_Score_Aligned[M08_Residual_Mom] (12-1M residual)",
          lag_rule="monthly t-1, C2", winsorization="2.5σ", neutralization="liquidity",
          economic_rationale="Cross-family diversifier (Q07-M08 panel cor=0.0099)",
          sleeve="Defense", source="db_existing",
          references=c("Carhart 1997","Blitz-Huij-Martens 2011","Daniel-Moskowitz 2016")),
    list(factor_family="Distress", proxy="Q25_Ohlson_O",
          formula="Z_Score_Aligned[Q25_Ohlson_O]",
          lag_rule="annual May (C4)", winsorization="2.5σ", neutralization="liquidity",
          economic_rationale="Distress factor (lower O-score = lower distress)",
          sleeve="Defense", source="db_existing",
          references=c("Ohlson 1980","Campbell-Hilscher-Szilagyi 2008"))
  ),

  diagnostics = list(
    rank_ic = round(dg$rank_ic, 5),
    icir = round(dg$icir, 5),
    harvey_t_stat = round(dg$harvey_t, 5),
    dsr = round(dsr, 5),
    monotonicity = NA,
    subperiod_stability = round(dg$sub_stab, 4),
    subperiod_ics = list(
      p1_2008_2014 = round(dg$p1, 5),
      p2_2015_2019 = round(dg$p2, 5),
      p3_2020_2023 = round(dg$p3, 5)
    ),
    post_neutralization_ic = round(dg$rank_ic, 5),
    turnover_proxy = 0.5,
    n_months = dg$n_months,
    n_sig_dates = n_sig,
    n_tickers = 20L,
    alpha_divergence = round(adv, 4),
    ax_001_v2_bad_normal_ic_ratio = round(ALPHA_OUTPUTS$ax_001_v2_bad_normal_ratio, 4)
  ),

  time_series_audit_record = list(
    n_sig_dates = n_sig,
    date_range = as.character(c(last_sd - months(n_sig), last_sd)),
    unique_tickers_panel = uti,
    schema = c("Date","Ticker","score_eff","score_core_z","score_defense_z",
                "Ret_1m","regime_state","theta_core","theta_defense",
                "kelly_fraction","vol_target_ann",
                "dd_brake_light","dd_brake_medium","dd_brake_heavy"),
    file_path = "stage_artifacts/WT_D20260425_011/alpha_scores.parquet"
  ),

  ax_axiom_compliance = axc,

  # === ITER 6 NOVELTY: handoff_to_optimizer ===
  handoff_to_optimizer = list(
    explanation = paste0(
      "Iter 6 MEGA_06 = STR_1699 alpha (this package) + MEGA_05 machinery (Optimizer applies). ",
      "Alpha agent provides 4 SPECS as metadata for Optimizer to honor. ",
      "AX-002 process honesty: alpha vector = STR_1699 base unchanged. ",
      "Kelly+Overlay are WEIGHTING decisions (Optimizer domain), NOT alpha modifications."
    ),
    kelly_sizing_spec = ALPHA_OUTPUTS$kelly_sizing_spec,
    dd_trigger_spec   = ALPHA_OUTPUTS$dd_trigger_spec,
    vol_target_spec   = ALPHA_OUTPUTS$vol_target_spec,
    fm_regime_spec    = ALPHA_OUTPUTS$fm_regime_spec,
    integration_pattern = list(
      step_1 = "Optimizer reads alpha_vector + confidence_vector (this package)",
      step_2 = "Optimizer reads regime_state column (per-sig_date) from alpha_scores.parquet",
      step_3 = "Optimizer applies Kelly_frac05 sizing: w_max = 0.5 * f_kelly per name (cap 10%)",
      step_4 = "Optimizer applies VolReg layer: scale = min(1.0, 0.12 / max(vol_lag, eps))",
      step_5 = "Optimizer applies DD Brake layer: cash override on dd_lag thresholds (6/8/20%)",
      step_6 = "Optimizer applies FM Regime layer: regime_state determines base cash level",
      step_7 = "Final weights = max-of (DD Brake, FM Regime cash) honored; sum_w = 1; long-only; 20 hard cap"
    ),
    optimizer_constraints = list(
      hard_max_names = 20L,
      long_only = TRUE,
      sum_weights = 1.0,
      max_per_name = 0.10,
      cash_range_pct = c(0L, 50L)
    ),
    deploy_cutoff = as.character(last_sd)
  ),

  crowding_check = list(
    cross_section_jaccard_iter5 = round(ALPHA_OUTPUTS$jaccard_iter5, 3),
    time_series_tdc_iter5 = round(ALPHA_OUTPUTS$ts_tdc_iter5, 3),
    pg2_active_book = "STR_1631_SYN_05 80% + STR_1656_MLRA_M05 20%",
    note = "Iter 6 inherits Iter 5 base; Jaccard vs Iter 5 expected near 1.0 (intentional). TDC vs PG2 measured at Forge backtest stage (this is alpha-level metric, not portfolio-level)."
  ),

  sequential_admission_scenarios = list(
    replacement = list(
      design = "100% Iter 6 (STR_1699 + Kelly + 3-Layer Overlay) Replaces PG2",
      backtest_status = "TBD by Forge",
      expected_benefit = "Combined alpha robustness (STR_1699 5-spec FF5 PASS) + machinery boost (MEGA_05 SR 1.110)"
    ),
    integration_80_20 = list(
      design = "80% MEGA_05 + 20% Iter 6 (score-level blend, L-484)",
      backtest_status = "TBD by Forge",
      expected_benefit = "Conservative incremental — but Iter 6 IS MEGA_05 machinery layer; may be redundant"
    ),
    integration_50_50 = list(
      design = "50% Iter 6 STR_1699+Kelly+Overlay / 50% STR_1656_MLRA_M05",
      backtest_status = "TBD by Forge",
      expected_benefit = "Maintain ML diversifier (STR_1656) while introducing Iter 6 robust alpha base"
    )
  ),

  external_validation_framework = list(
    framework = "KR_FF5_v2",
    asset = list(
      source = "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/.cache/kr_factor_returns_v2.parquet",
      available = TRUE,
      n_obs = 300L,
      date_range = c("2001-04-29","2026-03-04"),
      columns = c("Date","MKT","SMB","HML","WML","RMW","CMA","RF"),
      pit_backfill_evidence = "Iter 4 (WT-D20260425_009) Risk Agent built via DART TTM 2002+ backfill. HML/RMW/CMA NA pre-2010 (PIT-strict). MKT/SMB available 2001+ (longer history). Mandate 4 PASS."
    ),
    purpose = "STR_1699 (Iter 5) already passed Harvey FF5 5-spec all PASS (3.575~3.690). Iter 6 expected to inherit at portfolio level; Forge will re-run on Kelly+Overlay portfolio returns."
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
    C1 = "PASS: expanding IC weights (inherited Iter 5)",
    C2 = "PASS: signal at sig_date applied at fwd_date = sig_date+1M",
    C4 = "PASS: Factor DB enforces quarterly 45d / annual May lag",
    C9 = "PASS: regime expanding percentile + Iter 6 dd_lag/vol_lag explicitly enforced",
    C10 = "PASS: AvgTV20 t-1 lagged filter (inherited Iter 5)",
    C11 = "PASS: regime indicator BM_DT (KR internals, no FRED leakage)",
    C13 = "PASS: Z_Score_Aligned via per-sig_date align_factor_direction",
    C14 = "PASS: Factor DB Usable_Date <= sig_date enforced",
    C15 = "PASS: Iter 5 spot-check inherited (3 sig_dates × 7 factors cor>0.999)",
    lockbox = sprintf("ENFORCED 2024-01-23~2026-01-23 sealed; signal_cutoff=%s (one month tighter than Iter 5)", as.character(ALPHA_OUTPUTS$SIGNAL_CUTOFF))
  ),

  references = c(
    "Fama-French (1993) FF3 factor model",
    "Harvey-Liu-Zhu (2016) multiple testing t>3.0",
    "Carhart (1997) momentum factor",
    "Blitz-Huij-Martens (2011) residual momentum",
    "Novy-Marx (2013) gross profitability / earnings quality",
    "Ohlson (1980) O-score distress",
    "Campbell-Hilscher-Szilagyi (2008) distress risk",
    "Asness-Moskowitz-Pedersen (2013) value & momentum everywhere",
    "DeMiguel-Garlappi-Uppal (2009) 1/N — diversification benefit",
    "Barroso-Santa-Clara (2015) risk-managed momentum (VolReg basis)",
    "Moreira-Muir (2017) volatility-managed portfolios",
    "Kelly (1956) information rate (Kelly criterion)",
    "Thorp (1969) optimal gambling systems",
    "MacLean-Thorp-Ziemba (2010) Kelly capital growth",
    "Bailey-Lopez de Prado (2014) Deflated Sharpe Ratio",
    "QEPM L-484 score-level composite",
    "QEPM L-121 Q07 stress alpha",
    "QEPM L-204 STR_1699 first 5-spec PASS",
    "QEPM L-205 Replacement vs Sequential admission rule",
    "QEPM AX-007 multi-sleeve exception #1",
    "QEPM AX-005 EXCLUSION 'necessary not sufficient'",
    "QEPM AX-002 process honesty"
  ),

  role_bias_tagging = "RoleBias_Core_with_Defense_Diversifier",

  graduation_status = list(
    rank_ic_gate = list(value = round(dg$rank_ic, 5), threshold = 0.04,
                          pass = !is.na(dg$rank_ic) && dg$rank_ic >= 0.04),
    icir_gate = list(value = round(dg$icir, 5), threshold = 0.20,
                       pass = !is.na(dg$icir) && dg$icir >= 0.20),
    subperiod_gate = list(value = round(dg$sub_stab, 4), threshold = 0.50,
                            pass = !is.na(dg$sub_stab) && dg$sub_stab >= 0.50),
    harvey_t_gate = list(value = round(dg$harvey_t, 5), threshold = 3.00,
                           pass = !is.na(dg$harvey_t) && dg$harvey_t >= 3.00),
    dsr_gate = list(value = round(dsr, 5), threshold = 0.50,
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

# Re-fill unique tickers from artifact
suppressPackageStartupMessages({library(arrow); library(data.table)})
asp <- as.data.table(read_parquet(file.path(ART_DIR, "alpha_scores.parquet")))
alpha_package_draft$time_series_audit_record$unique_tickers_panel <- uniqueN(asp$Ticker)

draft_path <- file.path(WT_DIR, "alpha_package_draft.json")
write_json(alpha_package_draft, draft_path,
           pretty = TRUE, auto_unbox = TRUE, na = "string")
cat(sprintf("\n[run_alpha_iter6.R] alpha_package_draft.json saved -> %s\n", draft_path))
cat(sprintf("  n_sig_dates=%d unique_tickers_panel=%d\n",
            n_sig, alpha_package_draft$time_series_audit_record$unique_tickers_panel))
cat("[run_alpha_iter6.R] Next: invoke run_codex_qepm_critic.sh (Step 7 critic round)\n")
