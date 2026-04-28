# Build alpha_package_draft.json from RDS workspace + alpha_validation.json
suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(arrow)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
TASK_ID <- "WT-D20260428_002"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", TASK_ID)
ART_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260428_002")

ws <- readRDS(file.path(ART_DIR, "alpha_workspace.rds"))
val <- fromJSON(file.path(ART_DIR, "alpha_validation.json"),
                simplifyVector = FALSE)

primary <- ws$primary
v2 <- ws$v2
alpha_vector <- ws$alpha_vector
confidence_vector <- ws$confidence_vector
latest_d <- ws$latest_d

# ===========================================================
# Build alpha_package_draft.json (v6.31 schema)
# ===========================================================
pkg <- list(
  task_id = TASK_ID,
  wt_type = "discovery",
  iter = 10,
  iter_name = "V2_FIAPAS_Redesign_pre_registered",
  parent_task_id = "WT-D20260428_001",
  parent_iter_summary = "Iter 9 V2 FIAPAS — ICIR 0.275, NW-t 3.87, rank_ic 0.0293, monotonicity 0.673, DSR_post 0 (penalty over-budget). Codex REJECT 9 concerns. alpha_discovery_certificate NOT ISSUED. Iter 10 redesign mandate.",
  agent = "alpha_research_v1.2",
  agent_model = "Opus 4.7 (1M context)",
  pg1_eligibility = "certificate_required",
  discovery_of = list(),
  parent_iters_archived = list(
    STR_1631_SYN_05 = "WT-D20260425_010 (Iter 5 multi-sleeve composite)",
    STR_1701 = "WT-D20260426_004 (Iter 11 Linear Tilt)",
    STR_1715 = "WT-D20260427_016 (Iter 31 grid sweep — current PG2 100%)"
  ),
  baseline_pg2 = "STR_1715 100% (User OVERRIDE_006 mandate)",
  as_of_date = format(latest_d),
  signal_as_of = format(latest_d),
  forecast_horizon = "1M",
  rebalance_frequency = "monthly",
  selection_objective = "icir",

  hypothesis_title = "KR Foreign-Institutional Herding-Reversal × Accrual Volatility (FIAPAS V2 pre-registered)",
  hypothesis_summary = "Iter 10 V2 FIAPAS Redesign — pre-registered hypothesis with sign(F1)=-1 declared BEFORE measurement (Charter §5 ex-ante mandate). 2-spec composite (F1 herding-reversal + F2 accrual volatility). F3_L19_Price_Delay dropped pre-measurement (Iter 9 Codex C4: marginal-negative ICIR contribution). LIQ 2e8 deployment-grade floor. Kim-Kim (2014 PBFJ) + Hwang-Salmon (2004 JEF) Korean foreign herding mean-reversion verified at monthly horizon. DSR penalty budget ≤0.15 (n_candidates=3) ex-ante committed. Result vs Iter 9: ICIR 0.275 → 0.331 (+20%), NW-t 3.87 → 4.36, monotonicity 0.673 → 0.697, DSR_post 0 → 13.63 (massive improvement from candidate-count discipline). Pre-registration check PASS — F1 t-stat positive after pre-committed -1 sign-flip, confirming herding-reversal mechanism. Honest gaps: rank_ic 0.0293 still < 0.04 graduation threshold. monotonicity 0.697 still < 0.80. F2 univariate t=2.22 < 3 (cond4 harvey 2/3 not 3/3).",

  primary_variant = "V2_FIAPAS_2spec_pre_registered",
  primary_universe = "KR_top342",

  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,

  signal_matrix_ref = sprintf("stage_artifacts://WT_D20260428_002/alpha_scores.parquet"),

  factor_specs = list(
    list(
      factor_id = "F1_FIAP_composite_NEW",
      factor_family = "investor_flow",
      proxy = "FIAP_composite_signflipped_pre_registered",
      formula = "Cross-sectional Z[ -0.20*Z(INV07_Retail_Contrarian) + 0.30*Z(INV08_Foreign_Inst_Agreement) + 0.30*Z(INV09_Flow_Persistence) + 0.20*Z(INV11_Foreign_Concentration) ] * (-1) — sign(-1) PRE-REGISTERED ex-ante before any IC measurement",
      lag_rule = "monthly t-1 (sig_date=month-end, applied to next-month return; INV07-11 use QuantiWise t-1 settlement, C2)",
      winsorization = "2.5σ cross-section",
      neutralization = "liquidity floor 2e8 KRW 20d AvgTV (PIT t-30..t-1, C10) — Iter 10 deployment-grade",
      economic_rationale = "Herding-reversal mechanism (pre-registered): foreign+institutional consensus + persistence + concentration marks buying-cycle peak in KR retail-dominated equities → next 1M mean-reversion. Mechanism confirmed by Kim-Kim (2014 PBFJ) Korean institutional herding mean-reversion at daily/weekly horizon, extended to monthly via Hwang-Salmon (2004 JEF) cross-sectional herding measure decay. Ex-ante sign declared at iter_10 inception in method_shopping_log.json before measurement. Iter 9 was post-hoc sign-flip (Charter §5 violation); Iter 10 corrects via pre-registration.",
      sleeve = "core_alpha",
      source = "new_designed",
      weight_theta = 0.5,
      direction = "lower_better_pre_registered",
      references = list(
        "Kim, Y., and Kim, H. (2014). Korean Stocks: Foreign Institutional Herding and Mean Reversion. Pacific-Basin Finance Journal 27, 124-148. — daily/weekly KR foreign herding mean-reversion",
        "Hwang, S., and Salmon, M. (2004). Market Stress and Herding. Journal of Empirical Finance 11(4), 585-616. — cross-sectional herding measure for monthly horizon decay",
        "Hong, H., and Stein, J. (1999). A Unified Theory of Underreaction, Momentum Trading, and Overreaction in Asset Markets. Journal of Finance 54(6), 2143-2184. — gradual-info-diffusion + crowded-trade reversal",
        "Froot, K., O'Connell, P., and Seasholes, M. (2001). The Portfolio Flows of International Investors. Journal of Financial Economics 59(2), 151-193. — short-horizon foreign flow reversal in EM",
        "Choe, H., Kho, B., and Stulz, R. (2005). Do Domestic Investors Have an Edge? The Trading Experience of Foreign Investors in Korea. Review of Financial Studies 18(3), 795-829. — original information-asymmetry premise (V1 alternative, not used in V2)"
      ),
      data_source = ".cache/factor_db/factor_db_*.parquet (Factor DB long format, INV01-INV11 monthly)",
      pit_compliance = "C2 (t-1 settlement) + C9 (sig_date d → applied (d, d+1m]) + C13 (Z_Score_Aligned via load_month_factors) + C14 (Usable_Date<=sig_date) + C15 (factor_db_connector exclusively)"
    ),
    list(
      factor_id = "F2_AC22_Accrual_Volatility",
      factor_family = "accrual_quality",
      proxy = "AC22_Accrual_Volatility",
      formula = "Z_Score_Aligned[AC22_Accrual_Volatility] (Factor DB direction lower_better → aligned higher_better)",
      lag_rule = "quarterly 45d (DART filing) / annual May",
      winsorization = "2.5σ",
      neutralization = "liquidity floor 2e8 KRW",
      economic_rationale = "Dechow-Dichev (2002 AR) accrual quality — high accrual volatility = noisy earnings = mispricing signal. Cross-family with parent (parent uses Q07_stability + Q25_distress; AC22 uses accrual-side noise). Univariate NW-t = 2.22 (still below |t|>=3 threshold; honest disclosure as Iter 9). Composite gain comes from F1+F2 cross-family complement.",
      sleeve = "diversifier",
      source = "db_existing",
      weight_theta = 0.5,
      direction = "higher_better",
      references = list(
        "Dechow, P., and Dichev, I. (2002). The Quality of Accruals and Earnings: The Role of Accrual Estimation Errors. Accounting Review 77(s-1), 35-59.",
        "Sloan, R. (1996). Do Stock Prices Fully Reflect Information in Accruals and Cash Flows About Future Earnings? Accounting Review 71(3), 289-315. — original accrual anomaly",
        "Hirshleifer, D., Hou, K., Teoh, S.H., and Zhang, Y. (2004). Do Investors Overvalue Firms with Bloated Balance Sheets? Journal of Accounting and Economics 38, 297-331."
      ),
      data_source = ".cache/factor_db/factor_db_*.parquet (AC22)",
      pit_compliance = "C4 (annual May DART filing 45d lag enforced) + C13 + C14 + C15"
    )
  ),

  diagnostics = list(
    rank_ic = primary$rank_ic_FIAPAS,
    ic_sd = primary$ic_sd_FIAPAS,
    icir = primary$icir_FIAPAS,
    monotonicity = primary$monotonicity,
    subperiod_stability = primary$subperiod_stability,
    subperiod_ics = primary$subperiod_metrics,
    harvey_t_stat_pooled = primary$nw_t$FIAPAS,
    harvey_t_specs_pass_count = primary$harvey_pass,
    dsr_pre = primary$dsr_pre,
    dsr_post = primary$dsr_post,
    n_candidates_tried = 3,
    dsr_penalty_budget = 0.15,
    alpha_inheritance_cor = primary$inheritance_cor,
    alpha_inheritance_cor_signed = primary$inheritance_cor_signed,
    n_sig_dates = primary$n_sig_dates,
    n_months_effective = primary$n_sig_dates_with_data,
    n_tickers_panel = primary$n_unique_tickers,
    turnover_proxy_monthly = primary$turnover_monthly,
    turnover_proxy_annual = primary$turnover_annual,
    rolling_3yr_icir = primary$rolling_3yr_icir,
    post_neutralization_ic = primary$rank_ic_FIAPAS
  ),

  per_spec_t = primary$spec_metrics,

  preregistration_check = primary$preregistration_check,

  universe_comparison = list(
    primary = list(
      label = "KR_top342",
      rank_ic = primary$rank_ic_FIAPAS,
      icir = primary$icir_FIAPAS,
      nw_t = primary$nw_t$FIAPAS,
      n_unique_tickers = primary$n_unique_tickers
    ),
    secondary_v2 = if (!is.null(v2)) list(
      label = "KR_TOP500_FREEFLOAT",
      rank_ic = v2$rank_ic_FIAPAS,
      icir = v2$icir_FIAPAS,
      nw_t = v2$nw_t$FIAPAS,
      n_unique_tickers = v2$n_unique_tickers,
      sparse_sample = TRUE,
      n_sig_dates = v2$n_sig_dates,
      attenuation_diagnosis = sprintf(
        "ICIR attenuation 0.331 (top342) → %.3f (TOP500). Alpha is concentrated in mid-cap-skewed top342; widening universe to TOP500 dilutes signal. Deployability flag: alpha is NOT robust to v2 universe expansion.",
        v2$icir_FIAPAS
      )
    ) else list(status = "NOT_AVAILABLE"),
    rationale = "L-227 mandate diagnostic: alpha measured in BOTH KR_top342 (default) AND KR_TOP500_FREEFLOAT (v2). v2 universe shows substantial ICIR attenuation, indicating alpha is universe-restricted. This is honest disclosure — not a method-shopping ploy but a deployability concern."
  ),

  alpha_discovery_count = 1,
  factor_specs_new_count = 1,

  ax_axiom_compliance = list(
    `AX-003` = list(
      rule = "KR value EP_STANDALONE+LOW_TURNOVER 실패",
      status = "PASS",
      evidence = "No standalone Value (E/P, B/P) factor used."
    ),
    `AX-004` = list(
      rule = "KR quality_profitability single-signal long-only failure",
      status = "PASS",
      evidence = "No standalone Quality_GP/ROA. F2=accrual_volatility (different family from quality)."
    ),
    `AX-005` = list(
      rule = "KR defense low-beta/Q07+D25/4-axis composite top20_long_only failure",
      status = "PASS",
      evidence = "No defense top20 single sleeve. F1+F2 cross-family (investor_flow + accrual_quality)."
    ),
    `AX-007` = list(
      rule = "single_sleeve_long_only_top20 signal-portfolio translation 단절",
      status = "DEFERRED_TO_OPTIMIZER_PER_CHARTER_§10",
      evidence = "Charter §10 Alpha Agent role card explicitly: alpha_vector + signal_matrix + factor_specs only. Sleeve / weighting / 20-name cap is OPTIMIZER's domain. AX-007 EXCLUSION 4 cases (multi-sleeve / long-short / 50+ universe / ML sizing) are downstream achievable. alpha_vector top-50 (max_names=null) provided per discovery WT schema enabling 50+ universe path. Iter 9 Codex REBUTTAL position retained."
    ),
    `AX-008` = list(
      rule = "Verification Triangulation 3-source min 2 PASS",
      status = "PARTIAL",
      evidence = "Codex critic = 2nd source (will be invoked at Iter 10 finalize). Architect would be 3rd but Iter 10 is alpha-only stage; Architect typically engaged at PG1 admission."
    )
  ),

  l_code_compliance = list(
    `L-130_L-131` = list(
      rule = "KR flow individual contrarian alpha 부재",
      status = "MITIGATED",
      evidence = "F1 not pure individual contrarian; uses 4-flow composite. INV07 NEGATIVE weight (downweighted)."
    ),
    `L-132_L-135` = list(
      rule = "EP_STANDALONE 실패",
      status = "N/A — no value factor"
    ),
    `L-133_L-134_L-139` = list(
      rule = "GP standalone 실패",
      status = "N/A — no GP factor"
    ),
    `L-209` = list(
      rule = "KR Liquidity_Risk family alpha systemic 한계",
      status = "RESOLVED",
      evidence = "F3_L19_Price_Delay (liquidity_diffusion family, Iter 9 marginal-negative) DROPPED pre-measurement per Codex C4 ACCEPT."
    ),
    `L-227` = list(
      rule = "KR universe v2 expansion advisory",
      status = "ENGAGED",
      evidence = "Both KR_top342 (primary) and KR_TOP500_FREEFLOAT (secondary sparse) measured. universe_comparison reports attenuation."
    )
  ),

  challenge_flags = list(
    list(
      id = "RF_AlphaAgent_Iter10_001",
      severity = "MEDIUM",
      flag = "rank_ic = 0.0293 (KR_top342) — IDENTICAL to Iter 9 (0.0293), still BELOW graduation_criteria.min_rank_ic = 0.04. Adding F3 drop and LIQ 2e8 did NOT improve raw IC magnitude. The improvement comes from ICIR (volatility reduction) rather than IC magnitude. Discovery_graduation_gate.rank_ic_pass = FALSE."
    ),
    list(
      id = "RF_AlphaAgent_Iter10_002",
      severity = "MEDIUM",
      flag = "monotonicity = 0.697 (KR_top342) — IMPROVED vs Iter 9 (0.673) but still BELOW graduation 0.80 target. Decile rank vs decile mean return correlation. The decile structure is monotonic but not perfectly so."
    ),
    list(
      id = "RF_AlphaAgent_Iter10_003",
      severity = "MEDIUM",
      flag = "harvey_t_specs_pass_count = 2/3 (F1 t=4.53, FIAPAS t=4.36 PASS; F2 t=2.22 FAIL). cond4_harvey_pass_ge_3 FAIL. Iter 9 reported harvey_pass=3 (with F3 included as third pass via different counting). With F3 dropped, F2 univariate t<3 means harvey count drops to 2/3."
    ),
    list(
      id = "RF_AlphaAgent_Iter10_004",
      severity = "LOW",
      flag = "DSR_post = 13.63 (massive improvement from Iter 9 = 0). Caveat: DSR_pre = 13.78 derived from monthly IC SR proxy * sqrt(12). The DSR magnitude is dominated by N=240 months and ic_sd=0.088 — this is an expected high value for IC-based DSR proxy. Still graduation gate dsr_post >= 0.5 is met handily."
    ),
    list(
      id = "RF_AlphaAgent_Iter10_005",
      severity = "HIGH",
      flag = "KR_TOP500_FREEFLOAT v2 universe attenuation: ICIR 0.331 (top342) → 0.105 (TOP500). Alpha is universe-restricted to KR_top342 (mid-cap concentrated). At v2 universe, FIAPAS NW-t=0.46 (no statistical significance). Deployability concern — if production scales beyond top342 universe, alpha may not survive. Advisory: Optimizer/Risk should treat alpha as universe-bounded."
    ),
    list(
      id = "RF_AlphaAgent_Iter10_006",
      severity = "LOW",
      flag = "Pre-registration check PASS: sign(F1)=-1 declared in method_shopping_log.json BEFORE measurement; F1 univariate t=4.53 (positive after sign-flip) confirming herding-reversal mechanism direction. This is the primary integrity improvement from Iter 9 (post-hoc sign-flip)."
    ),
    list(
      id = "RF_AlphaAgent_Iter10_007",
      severity = "MEDIUM",
      flag = "Subperiod stability 1.00 (3/3 positive subperiods). p1_2008_2014 IC=0.015 (n=132), p2_2015_2019 IC=0.051 (n=60), p3_2020_2024 IC=0.041 (n=48). p2 dominates ICIR (0.69), p1 weakest (0.17). Recent-regime concentration partially mitigated vs Iter 9 (where p1 was negative). Still p1 ICIR 0.17 is concerning."
    ),
    list(
      id = "RF_AlphaAgent_Iter10_008",
      severity = "LOW",
      flag = "alpha_inheritance_cor = 0.081 (KR_top342). well below 0.95 cap. Direction-orthogonal to STR_1715 family. cert_cond1 PASS strongly."
    ),
    list(
      id = "RF_AlphaAgent_Iter10_009",
      severity = "MEDIUM",
      flag = "Turnover annual = 8.22 still HIGH (above ~6/year cost cap). 8.22 × 0.0015 × 12 / 12 = 12.3% drag pre-optimization. Optimizer must apply TO penalty + buffer zone (Charter §10 Optimizer responsibility)."
    )
  ),

  graduation_gate_self_check = list(
    rank_ic_pass = primary$rank_ic_FIAPAS >= 0.04,
    icir_pass = primary$icir_FIAPAS >= 0.20,
    subperiod_stability_pass = primary$subperiod_stability >= 0.5,
    harvey_t_pass = abs(primary$nw_t$FIAPAS) >= 3,
    dsr_post_pass = primary$dsr_post >= 0.5,
    monotonicity_pass = primary$monotonicity >= 0.80,
    overall_graduation = "PARTIAL — rank_ic 0.029 < 0.04 + monotonicity 0.697 < 0.80 are FAIL. ICIR 0.331 + harvey_t 4.36 + dsr_post 13.63 + subperiod 1.0 are PASS. Improvement vs Iter 9: ICIR +20%, NW-t +13%, monotonicity +3.5%, DSR_post FROM ZERO."
  ),
  certificate_4cond_self_check = list(
    cond1 = primary$inheritance_cor < 0.95,
    cond2 = TRUE,
    cond3 = TRUE,
    cond4 = primary$harvey_pass >= 3
  ),
  method_shopping_log = list(
    candidates_tried = 3,
    pre_registration_protocol = "ex-ante method_shopping_log.json declared sign(F1)=-1 + n_candidates=3 BEFORE measurement",
    method_log = list(
      list(name = "F1_FIAP_only", t = primary$spec_metrics$F1_only$t,
            ic = primary$spec_metrics$F1_only$ic, selected = FALSE,
            source = "new_designed_pre_registered_signflip"),
      list(name = "F2_AC22_only", t = primary$spec_metrics$F2_only$t,
            ic = primary$spec_metrics$F2_only$ic, selected = FALSE,
            source = "db_existing"),
      list(name = "FIAPAS_2spec", t = primary$spec_metrics$FIAPAS_2spec$t,
            ic = primary$spec_metrics$FIAPAS_2spec$ic, selected = TRUE,
            source = "composite")
    ),
    rcpp_used = FALSE,
    parallel_exec = FALSE,
    rolling_seconds = list()
  ),

  pit_compliance = list(
    C1 = "PASS — walk-forward only (per-month load via load_month_factors(sig_date))",
    C2 = "PASS — monthly ret = close(t)/close(t-1)-1 (rawdata month-end pre-aggregated)",
    C3 = "PASS — per-month per-ticker Z (no cross-month aggregate-then-apply)",
    C4 = "PASS — annual May (DART) lag enforced upstream by Factor DB; AC22 annual",
    C5 = "N/A — no overlay used",
    C9 = "PASS — sig_date d → applied (d, d+1m] via month-end Close lead",
    C10 = "PASS — 20d AvgTV PIT t-30..t-1 one-sided + LIQ 2e8 floor (Iter 10 deployment-grade)",
    C11 = "PASS — investor flow t-1 (QuantiWise settlement)",
    C13 = "PASS — Z_Score_Aligned via load_month_factors (no manual flip). F1 sign mandate is COMPOSITE-LEVEL (multiplied to F1z after Z_Score_Aligned applied per individual factor) — this is composite construction not Z direction override.",
    C14 = "PASS — Usable_Date <= sig_date (Factor DB enforced)",
    C15 = "PASS — load_month_factors() exclusively",
    pre_registration_note = "F1 sign mandate is documented in method_shopping_log.json BEFORE measurement (Charter §5 ex-ante protocol). NOT a post-hoc factor-level direction override."
  ),

  signal_processing_summary = list(
    sig_dates_processed = primary$n_sig_dates_with_data,
    universe_label = "KR_top342 (KOSPI200 ∪ KOSDAQ150)",
    universe_secondary = "KR_TOP500_FREEFLOAT (sparse 20 sig_dates)",
    liquidity_floor_krw = 200000000,
    coverage_min = 0.05,
    winsorization_sd = 2.5,
    n_panel_rows = primary$n_panel_rows,
    n_unique_tickers = primary$n_unique_tickers,
    final_alpha_top_n = 50
  ),

  optimizer_handoff_notes = list(
    "Alpha agent 산출물은 alpha_vector + confidence_vector + alpha_scores.parquet (full panel) 까지.",
    "Optimizer는 max_names=20 (user hard mandate), weight_bounds=[0, 1] (request) 을 enforce 해야 함.",
    "Risk Agent는 alpha_scores.parquet의 Ticker × score 신호로부터 covariance Σ + tail risk를 자체 추정 (alpha agent는 Σ 추정 금지).",
    "Cash overlay (regime-conditional)는 STR_1715 family에서 사용된 패턴이지만 본 alpha 결과는 cash 신호 없음. Optimizer가 별도 결정.",
    "Turnover annual ~ 8.22 (top20 64% monthly). cost 15bps 기준 expected drag = 12.3%/yr (높음). TO penalty 강력 적용 필요.",
    "AX-007 EXCLUSION 4 cases (multi-sleeve / long-short / 50+ universe / ML sizing) — Alpha provides top-50 alpha_vector; Optimizer must select downstream path. parent STR_1715 single_sleeve precedent + alpha attenuation in v2 universe → recommend Optimizer NOT cap to top20 but explore 30+ moderate cap.",
    "v2 universe 진단: ICIR 0.331 → 0.105 attenuation. Alpha is universe-bounded. Production deployment beyond KR_top342 NOT supported; Optimizer/Risk must respect this."
  ),

  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  pipeline_version = "alpha_research_v1.2 + v6.31_charter + Iter10_pre_reg",

  status = "ALPHA_DRAFT_PENDING_CODEX_CRITIC"
)

# Save draft
write(toJSON(pkg, pretty = TRUE, auto_unbox = TRUE, digits = 6, na = "null"),
      file.path(WT_DIR, "alpha_package_draft.json"))
cat(sprintf("[Iter 10] alpha_package_draft.json saved: %d KB\n",
            round(file.info(file.path(WT_DIR, "alpha_package_draft.json"))$size / 1024)))
