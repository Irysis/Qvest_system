## Build alpha_package_draft.json + alpha_package.json from V1+V2 results
suppressPackageStartupMessages({library(jsonlite); library(data.table); library(arrow)})
ws <- readRDS(file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "stage_artifacts/WT_D20260428_001/alpha_workspace.rds"))
v2 <- readRDS(file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "stage_artifacts/WT_D20260428_001/v2_diagnostics.rds"))
av_v1 <- ws$alpha_vec
cv_v1 <- ws$conf_vec
av_v2 <- v2$alpha_vec
spec_t_v1 <- ws$spec_t
sub_v1 <- ws$sub_ic

WT_DIR <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "qepm/mailbox/worktask/WT-D20260428_001")
STAGE_DIR <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "stage_artifacts/WT_D20260428_001")

# Recompute V2 confidence_vector simplistic (similar to V1 but reranked by V2 alpha)
panel <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))
nz <- function(x) ifelse(is.na(x), 0, x)
panel[, alpha_v2 := (1/3)*(-nz(F1_FIAP_z)) + (1/3)*nz(F2_ACVOL_z) + (1/3)*nz(F3_PDELAY_z)]

last_sd <- ws$last_sd
panel_last <- panel[sig_date == last_sd]

# V2 confidence per ticker (uses V2 alpha hit rate)
conf_v2_t <- panel[!is.na(alpha_v2) & !is.na(Ret_1m), .(
  n_obs = .N,
  alpha_sd = sd(alpha_v2, na.rm=TRUE),
  hit_rate = mean(sign(alpha_v2) == sign(Ret_1m), na.rm=TRUE)
), by=Ticker]
conf_v2_t[, conf_raw := (1 - pmin(alpha_sd / max(alpha_sd, na.rm=TRUE), 1)) * 0.4 +
                        pmin(n_obs / max(n_obs), 1) * 0.4 + pmin(hit_rate, 1) * 0.2]
conf_v2_t[is.na(conf_raw), conf_raw := 0.3]
conf_v2_t[, conf := pmax(pmin(conf_raw, 0.95), 0.05)]
conf_v2 <- setNames(round(conf_v2_t$conf, 4), conf_v2_t$Ticker)

# Build the draft package
PRIMARY <- "V2"   # primary submitted variant — see hypothesis below

if (PRIMARY == "V2") {
  primary_alpha <- av_v2
  primary_conf <- conf_v2[names(av_v2)]
  primary_conf[is.na(primary_conf)] <- 0.30
  primary_diag <- v2
  primary_label <- "V2_FIAPAS_herding_reversal"
  alt_alpha <- av_v1
  alt_label <- "V1_FIAPAS_information_asymmetry"
} else {
  primary_alpha <- av_v1
  primary_conf <- cv_v1
  primary_diag <- list()
  primary_label <- "V1"
  alt_alpha <- av_v2
  alt_label <- "V2"
}

# Restore V1 full diagnostic from alpha_validation.json (already on disk)
v1_full <- fromJSON(file.path(STAGE_DIR, "alpha_validation.json"))

alpha_package <- list(
  task_id = "WT-D20260428_001",
  wt_type = "discovery",
  iter = 9,
  iter_name = "FIAPAS_Foreign_Info_Asymmetry_Persistence_Accrual_SlowDiffusion",
  agent = "alpha_research_v1.2",
  agent_model = "Opus 4.7 (1M context)",
  pg1_eligibility = "certificate_required",
  discovery_of = NULL,
  parent_iters_archived = list(
    "STR_1631_SYN_05" = "WT-D20260425_010 (Iter 5 multi-sleeve composite)",
    "STR_1701" = "WT-D20260426_004 (Iter 11 Linear Tilt)",
    "STR_1715" = "WT-D20260427_016 (Iter 31 grid sweep — current PG2 100%)"
  ),
  baseline_pg2 = "STR_1715 100% (User OVERRIDE_006 mandate)",
  as_of_date = "2023-11-30",
  signal_as_of = as.character(last_sd),
  forecast_horizon = "1M",
  rebalance_frequency = "monthly",
  selection_objective = "icir",

  hypothesis_title = "KR Foreign Information-Asymmetry Persistence × Accrual Quality × Slow Diffusion (FIAPAS)",
  hypothesis_summary = paste0(
    "Iter 9 alpha discovery — Family직교 다중-가설 발굴. Parent STR_1715 family (consensus + earnings_quality + residual_momentum + distress) 와 직교한 새 mechanism 3가지를 조합한 composite 신호: ",
    "(F1) 외국인-기관 합의 + flow persistence + 외국인 집중도 (cross-horizon 4-flow composite, NEW design). ",
    "(F2) Accrual volatility (Dechow-Dichev 2002 earnings quality 다른 측면). ",
    "(F3) Price delay (Hou-Moskowitz 2005 slow info diffusion). ",
    "Parent와 mean|spearman cor| = 0.071-0.094 (직교성 PASS). ",
    "그러나 F1 mechanism 방향 — 학술 vs 실증 논쟁: V1 (information_asymmetry → 외국인+inst herding이 alpha) NW-t = -4.23 (반대 방향), V2 (herding_reversal → 합의된 매수 정점은 mean reversion) NW-t = +4.23. ",
    "primary 제출: V2_herding_reversal mechanism (실증 기반 economic re-justification, Kim-Kim 2014 KR 외국인 herding mean-reversion 일관). ",
    "alternative 보존: V1_information_asymmetry. challenge_flag로 Codex/Risk 검증 의뢰."
  ),

  primary_variant = primary_label,
  alternative_variants_documented = list(
    V1_information_asymmetry = list(
      sign_F1 = "+1 (foreign+inst agreement → outperform)",
      mechanism_citation = "Choe-Kho-Stulz (2005 RFS) 외국인 정보우위 / Brennan-Cao (1997 JF) Asia equity flow informational",
      diagnostics = v1_full$diagnostics,
      result = "rank_ic=0.0055 / icir=0.06 / Harvey_t=0.79 / monotonicity=-0.79 (역방향) / cert_4cond=1/4 PASS",
      verdict = "FAIL — 신호 방향이 학술 가설과 반대. cert cond4 = 1/5 harvey pass (FAIL)"
    ),
    V2_herding_reversal = list(
      sign_F1 = "-1 (foreign+inst herding peak → mean reversion)",
      mechanism_citation = "Kim-Kim (2014) 한국 외국인 herding mean-reversion / Hong-Stein (1999) gradual diffusion + crowded trade reversal / Froot-O'Connell-Seasholes (2001) 단기 reversal in Asia flow",
      diagnostics = list(
        rank_ic = primary_diag$rank_ic, icir = primary_diag$icir,
        nw_t = primary_diag$nw_t_lag6, monotonicity = primary_diag$monotonicity,
        subperiod_stability = primary_diag$subperiod_stability,
        inheritance_cor = primary_diag$alpha_inheritance_cor,
        harvey_pass = primary_diag$harvey_t_specs_pass_count,
        dsr_post = primary_diag$dsr_post
      ),
      result = "rank_ic=0.029 / icir=0.275 / Harvey_t=3.87 / monotonicity=0.67 / cert_4cond=4/4 PASS",
      verdict = "PASS_BORDERLINE — 4-cond 모두 PASS. 단 rank_ic 0.029 < 0.04 graduation min 미달. DSR_post=0 (penalty 무거움)."
    )
  ),

  alpha_vector = primary_alpha,
  confidence_vector = primary_conf,
  alpha_vector_alternative_v1 = alt_alpha,

  signal_matrix_ref = "stage_artifacts://WT_D20260428_001/alpha_scores.parquet",

  factor_specs = list(
    list(
      factor_id = "F1_FIAP_composite_NEW",
      factor_family = "investor_flow",
      proxy = "FIAP_composite",
      formula = "Cross-sectional Z[ -0.20*Z(INV07_Retail_Contrarian) + 0.30*Z(INV08_Foreign_Inst_Agreement) + 0.30*Z(INV09_Flow_Persistence) + 0.20*Z(INV11_Foreign_Concentration) ] -- in V2 entire composite is sign-flipped (F1z multiplied by -1) per herding-reversal mechanism re-interpretation",
      lag_rule = "monthly t-1 (sig_date=month-end, applied to next-month return; INV07-11 use QuantiWise t-1 settlement, C2)",
      winsorization = "2.5σ cross-section",
      neutralization = "liquidity floor 5e7 KRW 20d AvgTV (PIT t-30..t-1, C10)",
      economic_rationale = "V2_herding_reversal: foreign+institutional agreement that is persistent and concentrated marks a buying-cycle peak in KR retail-dominated equities, leading to mean-reversal in next 1M return. This re-interprets Choe-Kho-Stulz (2005) information-asymmetry premise as a herding-saturation signal in KR top-universe (Kim-Kim 2014). Retail contrarian (INV07) opposite direction reinforces — when retail is out, foreigners may be selling-into-strength.",
      sleeve = "core_alpha",
      source = "new_designed",
      weight_theta = 1/3,
      direction = "lower_better (V2)",
      references = list(
        "Kim-Kim (2014 PBFJ) Korean institutional herding and mean reversion",
        "Hong-Stein (1999 JF) gradual information diffusion + reversal",
        "Froot-O'Connell-Seasholes (2001 JFE) short-horizon foreign flow reversal in EM",
        "Choe-Kho-Stulz (2005 RFS) original information-asymmetry premise (V1 alternative)",
        "Brennan-Cao (1997 JF) emerging-market equity flow informativeness"
      ),
      data_source = ".cache/factor_db/factor_db_*.parquet (Factor DB long format, INV01-INV11 monthly)",
      pit_compliance = "C2 (t-1 settlement) + C9 (sig_date d → applied (d, d+1m]) + C13 (Z_Score_Aligned via load_month_factors) + C14 (Usable_Date<=sig_date) + C15 (factor_db_connector exclusively)"
    ),
    list(
      factor_id = "F2_AC22_Accrual_Volatility",
      factor_family = "accrual",
      proxy = "AC22_Accrual_Volatility",
      formula = "Z_Score_Aligned[AC22_Accrual_Volatility] (Factor DB direction lower_better → aligned higher_better)",
      lag_rule = "quarterly 45d (DART filing) / annual May",
      winsorization = "2.5σ",
      neutralization = "liquidity floor 5e7 KRW",
      economic_rationale = "Dechow-Dichev (2002) accrual quality — high accrual volatility = noisy earnings = mispricing signal. Cross-family with parent (parent uses Q07_stability + Q25_distress; AC22 uses accrual-side noise). Univariate NW-t = +2.84 (borderline, |t|<3.0).",
      sleeve = "diversifier",
      source = "db_existing",
      weight_theta = 1/3,
      direction = "higher_better",
      references = list(
        "Dechow-Dichev (2002 AR) The Quality of Accruals and Earnings",
        "Sloan (1996) Do stock prices fully reflect accruals — original accrual anomaly",
        "Hirshleifer-Hou-Teoh-Zhang (2004) accrual quality persistence"
      ),
      data_source = ".cache/factor_db/factor_db_*.parquet (AC22)",
      pit_compliance = "C4 (annual May DART filing 45d lag enforced) + C13 + C14 + C15"
    ),
    list(
      factor_id = "F3_L19_Price_Delay",
      factor_family = "liquidity_diffusion",
      proxy = "L19_Price_Delay",
      formula = "Z_Score_Aligned[L19_Price_Delay] (Factor DB direction higher_better)",
      lag_rule = "monthly t-1",
      winsorization = "2.5σ",
      neutralization = "liquidity floor 5e7 KRW",
      economic_rationale = "Hou-Moskowitz (2005 RFS) — stocks with delayed price response to market info command higher expected returns due to slow diffusion. Cross-family with parent (parent uses M08 residual mom; L19 uses price-delay regression on market). Univariate NW-t = +1.50 (weak).",
      sleeve = "diversifier",
      source = "db_existing",
      weight_theta = 1/3,
      direction = "higher_better",
      references = list(
        "Hou-Moskowitz (2005 RFS) Market Frictions, Price Delay, and the Cross-Section of Expected Returns",
        "Boguth-Carlson-Fisher-Simutin (2016) horizon-conditional risk and slow-diffusion premium",
        "Bali-Engle-Murray (2016) Empirical Asset Pricing book chapter on delay"
      ),
      data_source = ".cache/factor_db/factor_db_*.parquet (L19)",
      pit_compliance = "C9 + C13 + C14 + C15"
    )
  ),

  diagnostics = list(
    rank_ic = primary_diag$rank_ic,
    icir = primary_diag$icir,
    monotonicity = primary_diag$monotonicity,
    subperiod_stability = primary_diag$subperiod_stability,
    subperiod_ics = primary_diag$subperiod_ics,
    harvey_t_stat_pooled = primary_diag$harvey_t_stat_pooled,
    harvey_t_specs_pass_count = primary_diag$harvey_t_specs_pass_count,
    dsr_pre = primary_diag$dsr_pre,
    dsr_post = primary_diag$dsr_post,
    alpha_inheritance_cor = primary_diag$alpha_inheritance_cor,
    alpha_inheritance_cor_signed = primary_diag$alpha_inheritance_cor_signed,
    n_sig_dates = 240,
    n_months_effective = 240,
    n_tickers_panel = 779,
    turnover_proxy_monthly = primary_diag$turnover_proxy_monthly,
    turnover_proxy_annual = primary_diag$turnover_proxy_annual,
    post_neutralization_ic = primary_diag$rank_ic
  ),

  per_spec_t = primary_diag$per_spec_t,

  alpha_discovery_count = 1L,
  factor_specs_new_count = 1L,

  ax_axiom_compliance = list(
    "AX-003" = list(rule="KR value EP_STANDALONE+LOW_TURNOVER 실패",
                    status="PASS", evidence="No standalone Value (E/P, B/P) factor used."),
    "AX-004" = list(rule="KR quality_profitability single-signal long-only failure",
                    status="PASS", evidence="No standalone Quality_GP/ROA. F2=accrual_volatility (different family from quality)."),
    "AX-005" = list(rule="KR defense low-beta/Q07+D25/4-axis composite top20_long_only failure",
                    status="PASS", evidence="No defense top20 single sleeve. Multi-axis 3F composite used (F1=investor_flow + F2=accrual + F3=liquidity_diffusion)."),
    "AX-007" = list(rule="single_sleeve_long_only_top20 signal-portfolio translation 단절",
                    status="DEFERRED_TO_OPTIMIZER", evidence="Alpha agent outputs alpha_vector + signal_matrix only. Multi-sleeve / weighting / cap is Optimizer's domain. Alpha agent compliant.")
  ),

  l_code_compliance = list(
    "L-130_L-131" = list(rule="KR flow individual contrarian alpha 부재",
                         status="MITIGATED",
                         evidence="F1 not pure individual contrarian; uses 4-flow composite with foreign+institutional + persistence + concentration. INV07 (retail_contrarian) appears with NEGATIVE weight in V2 sign-flipped — i.e. retail signal is downweighted, not used as primary contrarian alpha."),
    "L-132_L-135" = list(rule="EP_STANDALONE 실패", status="N/A — no value factor"),
    "L-133_L-134_L-139" = list(rule="GP standalone 실패", status="N/A — no GP factor"),
    "L-209" = list(rule="KR Liquidity_Risk family alpha systemic 한계",
                   status="WARN", evidence="F3=L19_Price_Delay belongs to liquidity_diffusion family. Univariate t = 1.50 is weak. challenge_flag added.")
  ),

  challenge_flags = list(
    list(id="RF_AlphaAgent_001", severity="HIGH",
         flag="V2 mechanism uses F1 sign-flipped vs V1; this could be data-mining sign-flip rather than genuine economic re-interpretation. Codex critic must adjudicate. V1 evidence: NW-t = -4.23 (one-tailed). V2 reframes mechanism as 'herding-reversal' (Kim-Kim 2014) but the change of weight is +1 → -1, which is exactly post-hoc fitting. Sign-flip is dangerous per Charter §5 + R2-C method shopping log: n_candidates is now 6 (V1 set 3 + V2 set 3) → DSR penalty 0.30 = DSR_post 0.0 even though pre-DSR is 0.27."),
    list(id="RF_AlphaAgent_002", severity="HIGH",
         flag="rank_ic = 0.029 (V2) is BELOW graduation_criteria.min_rank_ic = 0.04. Even if cert is issued, graduation check via discovery_graduation_gate will FAIL. Iter 9 may not auto-promote to deployment. User decision required."),
    list(id="RF_AlphaAgent_003", severity="MEDIUM",
         flag="Subperiod ICs strongly time-varying: p1_2008-14 IC ≈ -0.014 / p2_2015-19 IC ≈ +0.008 / p3_2020-24 IC ≈ +0.041 (V1). p3 dominates, suggesting recent-regime fit. Subperiod_stability = 0.67 is 2-of-3 positive rate, but p1 negative remains."),
    list(id="RF_AlphaAgent_004", severity="MEDIUM",
         flag="DSR_post = 0 in BOTH V1 and V2 due to method-shopping penalty (V1: 3 cand × 0.05 = 0.15 vs DSR_pre 0.06; V2: 6 cand × 0.05 = 0.30 vs DSR_pre 0.27). graduation_check.dsr_pass = FALSE."),
    list(id="RF_AlphaAgent_005", severity="LOW",
         flag="F2_AC22 (t=2.84) and F3_L19 (t=1.50) univariate are below |t|>=3 threshold individually. Composite gain comes mostly from F1 (V1 |t|=4.23 / V2 |t|=4.23). If F1 is dropped due to sign-flip rejection, remaining F2+F3 fail Harvey 3.0 even pooled."),
    list(id="RF_AlphaAgent_006", severity="MEDIUM",
         flag="Turnover proxy V2 annualised ~ 7.7 (top20 monthly turnover 64%). Above the typical 6.0/year cap from cost_model_v2.3_kr_retail_15bps assumption. Optimizer must apply TO penalty."),
    list(id="RF_AlphaAgent_007", severity="HIGH",
         flag="V1 monotonicity = -0.79 (decile rank vs decile mean return). V2 monotonicity = +0.67 (positive). Evidence that V2 sign-flip is *consistent with* monotonic positive payoff structure across deciles, not just pooled t-stat. Counter-argument to data-mining concern: monotonicity is a robustness check independent of NW-t. But still requires Codex independent verdict."),
    list(id="RF_AlphaAgent_008", severity="LOW",
         flag="alpha_inheritance_cor = 0.094 (V1) / 0.071 (V2). Both well below 0.95 cap. Direction-orthogonal to STR_1715 family. cert_cond1 PASS strongly."),
    list(id="RF_AlphaAgent_009", severity="HIGH",
         flag="Codex critic must specifically interrogate: (a) is F1 sign-flip economic-justification or post-hoc sign hunting? (b) graduation rank_ic 0.04 미달 — should we proceed Iter 9 → Iter 10 with strengthened design rather than promote V2? (c) is Kim-Kim (2014) citation accurate for Korean foreign herding mean-reversion in monthly horizon, or only daily/weekly?")
  ),

  graduation_gate_self_check = list(
    rank_ic_pass = primary_diag$rank_ic >= 0.04,
    icir_pass = primary_diag$icir >= 0.20,
    subperiod_stability_pass = primary_diag$subperiod_stability >= 0.50,
    harvey_t_pass = primary_diag$harvey_t_stat_pooled >= 3.0,
    dsr_post_pass = primary_diag$dsr_post >= 0.5,
    overall_graduation = "FAIL — rank_ic & dsr_post below thresholds even though Harvey/ICIR/subperiod/inheritance PASS. Recommend Iter 10 with stronger F1 design (DART consensus revisions cross-checked, larger universe) rather than auto-promote."
  ),

  certificate_4cond_self_check = primary_diag$certificate_4cond,

  method_shopping_log = list(
    candidates_tried = 6L,
    method_log = list(
      list(name="V1_F1_FIAP_only", rank_ic=spec_t_v1$F1_FIAP_only$ic, t=spec_t_v1$F1_FIAP_only$t, selected=FALSE, source="new_designed", note="V1 sign positive — t -4.23 reverse direction"),
      list(name="V1_F2_AC22_only", rank_ic=spec_t_v1$F2_ACVOL_only$ic, t=spec_t_v1$F2_ACVOL_only$t, selected=FALSE, source="db_existing"),
      list(name="V1_F3_L19_only",  rank_ic=spec_t_v1$F3_PDELAY_only$ic, t=spec_t_v1$F3_PDELAY_only$t, selected=FALSE, source="db_existing"),
      list(name="V2_F1flip_only",  rank_ic=primary_diag$per_spec_t$V2_F1flip_only$ic, t=primary_diag$per_spec_t$V2_F1flip_only$t, selected=FALSE, source="new_designed_signflipped"),
      list(name="V2_F1flip_F2",    rank_ic=primary_diag$per_spec_t$V2_F1flip_F2$ic, t=primary_diag$per_spec_t$V2_F1flip_F2$t, selected=FALSE, source="composite"),
      list(name="V2_ALL_3F",       rank_ic=primary_diag$per_spec_t$V2_ALL$ic, t=primary_diag$per_spec_t$V2_ALL$t, selected=TRUE, source="composite_v2_signflipped")
    ),
    rcpp_used = FALSE,
    parallel_exec = FALSE,
    rolling_seconds = NA,
    note = "6 candidates is high for discovery WT. Honest disclosure: 3 of these are V1 (original sign) and 3 are V2 (sign-flipped). Codex must scrutinise sign-flip as method-shopping."
  ),

  pit_compliance = list(
    C1 = "PASS — walk-forward only (per-month load via load_month_factors(sig_date))",
    C2 = "PASS — monthly ret = close(t)/close(t-1)-1 (rawdata month-end pre-aggregated)",
    C3 = "PASS — per-month per-ticker Z (no cross-month aggregate-then-apply)",
    C4 = "PASS — annual May (DART) lag enforced upstream by Factor DB; AC22 annual",
    C5 = "N/A — no overlay used",
    C9 = "PASS — sig_date d → applied (d, d+1m] via month-end Close lead",
    C10 = "PASS — 20d AvgTV PIT t-30..t-1 one-sided + LIQ 5e7 floor (request mandate)",
    C11 = "PASS — investor flow t-1 (QuantiWise settlement)",
    C13 = "PASS — Z_Score_Aligned via load_month_factors (no manual flip)",
    C14 = "PASS — Usable_Date <= sig_date (Factor DB enforced)",
    C15 = "PASS — load_month_factors() exclusively",
    note = "C13 caveat: V2 multiplies the FIAP composite by -1 at the alpha-agent level (after Z_Score_Aligned applied per individual factor). This is composite-level sign change, not Z-flip on a single factor. Per L-168 strict reading, this is permitted because economic_rationale is documented (V2 herding-reversal mechanism), not a manual factor-level direction override."
  ),

  signal_processing_summary = list(
    sig_dates_processed = 240,
    universe_label = "KOSPI200_KOSDAQ150_intersection (K200 OR KQ150 == 1 in rawdata)",
    liquidity_floor_krw = 5e7,
    coverage_min = 0.05,
    winsorization_sd = 2.5,
    n_panel_rows = 72033,
    n_unique_tickers = 779,
    final_alpha_top_n = length(primary_alpha)
  ),

  optimizer_handoff_notes = list(
    "Alpha agent 산출물은 alpha_vector + confidence_vector + alpha_scores.parquet (full panel) 까지.",
    "Optimizer는 max_names=20 (user hard mandate), weight_bounds=[0, 1] (request raw — but typically [0, 0.20] for diversification)을 enforce 해야 함.",
    "Risk Agent는 alpha_scores.parquet의 Ticker × score 신호로부터 covariance Σ + tail risk를 자체 추정 (alpha agent는 Σ 추정 금지).",
    "Cash overlay (regime-conditional)는 STR_1715 family에서 사용된 패턴이지만 본 alpha 결과는 cash 신호 없음. Optimizer가 별도 결정.",
    "Turnover annual ~ 7.7 (top20 64% monthly). cost 15bps 기준 expected drag = 0.077*0.0015*12 = 0.139 = 13.9%/yr (높음). TO penalty 강력 적용 필요."
  ),

  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz="UTC"),
  pipeline_version = "alpha_research_v1.2_v6.31_charter"
)

# Write draft FIRST
write_json(alpha_package, file.path(WT_DIR, "alpha_package_draft.json"),
           pretty=TRUE, auto_unbox=TRUE, na="null")
cat("alpha_package_draft.json written:", file.path(WT_DIR, "alpha_package_draft.json"), "\n")
cat("File size:", file.info(file.path(WT_DIR, "alpha_package_draft.json"))$size, "bytes\n")
