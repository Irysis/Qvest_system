# Assemble alpha_scores.parquet + alpha_validation.json + alpha_package_draft.json
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a

OUT_STAGE <- "stage_artifacts/WT-D20260614_002"
OUT_WT    <- "qepm/mailbox/worktask/WT-D20260614_002"
dir.create(OUT_WT, showWarnings=FALSE, recursive=TRUE)

I  <- readRDS(file.path(OUT_STAGE,"_alpha_intermediate.rds"))
OV <- readRDS(file.path(OUT_STAGE,"_overlap.rds"))
comp <- I$comp; fic <- I$fic; ic <- I$ic

# ---- alpha_scores.parquet (per-name) ----
scores <- comp[, .(Ticker, as_of_date="2026-05-31",
                   alpha_z=round(alpha_z,5),
                   alpha_monthly_active=round(alpha_monthly_active,6),
                   alpha_annual_active=round(alpha_annual_active,6),
                   confidence=confidence, n_cov,
                   defense_z=round(defense_z,4), momentum_z=round(momentum_z,4),
                   quality_z=round(quality_z,4), value_z=round(value_z,4))]
setorder(scores, -alpha_z)
write_parquet(scores, file.path(OUT_STAGE,"alpha_scores.parquet"))
cat("[assemble] alpha_scores.parquet:", nrow(scores), "names\n")

# alpha_vector + confidence_vector (top universe full; expose top 60 in JSON, full in parquet)
topN <- scores[1:60]
alpha_vector <- setNames(as.list(round(topN$alpha_annual_active,5)), topN$Ticker)
confidence_vector <- setNames(as.list(topN$confidence), topN$Ticker)

# ---- per-factor specs ----
fic_map <- setNames(fic$ICIR, fic$Factor_Name)
fic_ic  <- setNames(fic$Mean_IC, fic$Factor_Name)
fic_n   <- setNames(fic$N_Months, fic$Factor_Name)
AXIS <- c(D01_IdioVol="defense", D02_Beta="defense",
          M07_IndMom="momentum", M01_Mom_12_1="momentum", M05_Trended_Mom="momentum",
          Q01_GPA="quality", Q04_Piotroski_F="quality", Q09_CFOA="quality",
          Q07_Earnings_Stability="quality", V01_BM="value")
DIR <- c(D01_IdioVol="lower_better", D02_Beta="lower_better", M07_IndMom="higher_better",
         M01_Mom_12_1="higher_better", M05_Trended_Mom="higher_better", Q01_GPA="higher_better",
         Q04_Piotroski_F="higher_better", Q09_CFOA="higher_better",
         Q07_Earnings_Stability="higher_better", V01_BM="higher_better")
LAG <- c(D01_IdioVol="daily, Date<=sig_d (252d idio vol)", D02_Beta="daily, Date<=sig_d (252d beta)",
         M07_IndMom="daily, Date<=sig_d (industry 12-1 mom)", M01_Mom_12_1="daily, Date<=sig_d (12-1 price mom)",
         M05_Trended_Mom="daily, Date<=sig_d (trended mom)", Q01_GPA="quarterly 45d / annual May",
         Q04_Piotroski_F="quarterly 45d / annual May", Q09_CFOA="quarterly 45d / annual May",
         Q07_Earnings_Stability="annual May (multi-yr earnings var)", V01_BM="quarterly 45d / annual May")
RAT <- c(
  D01_IdioVol="저변동성 이상현상 — 고유변동성 낮은 종목 위험조정 초과수익 (Ang 2006; KR evidence_tier A). 방어축 주력.",
  D02_Beta="저베타 이상현상 (BAB) — 레버리지 제약 하 저베타 알파 (Frazzini-Pedersen 2014). KR top-univ ICIR 약함(0.10).",
  M07_IndMom="산업 모멘텀 — 섹터 수익 지속성 (Moskowitz-Grinblatt 1999). KR ICIR 약함(0.11).",
  M01_Mom_12_1="12-1 가격 모멘텀 (Jegadeesh-Titman 1993). KR top-univ 약함(ICIR 0.14, 잘 알려진 KR momentum 취약).",
  M05_Trended_Mom="추세 모멘텀 — 추세강도 가중 모멘텀. KR ICIR 약함(0.12).",
  Q01_GPA="총자산이익률(GPA) — Novy-Marx 2013 gross profitability. 퀄리티축, KR tier A.",
  Q04_Piotroski_F="Piotroski F-score — 재무건전성 9지표 (Piotroski 2000). KR ICIR 최강(0.96).",
  Q09_CFOA="영업현금흐름/자산 — 현금흐름 질. 퀄리티축 ICIR 0.69.",
  Q07_Earnings_Stability="이익 안정성 — 이익 변동성 역수. 방어적 퀄리티, ICIR 0.77.",
  V01_BM="장부가/시가 (B/M) — value premium (Fama-French 1993). 밸류축, KR tier A, ICIR 0.58.")

factor_specs <- lapply(names(AXIS), function(f) {
  list(
    factor_id = f,
    factor_family = unname(AXIS[f]),
    axis = unname(AXIS[f]),
    direction = unname(DIR[f]),
    lag_rule = unname(LAG[f]),
    winsorization = "3std (builder-level)",
    standardization = "cross-sectional Z-score, direction-aligned (Z_Score_Aligned, higher=better)",
    neutralization = "raw (no sector/size neutralization in this composite)",
    combination = "equal-weight (theta=0.10 each, 1/10)",
    weight_theta = 0.10,
    icir_expanding_pit = round(unname(fic_map[f]) %||% NA_real_, 3),
    mean_ic_expanding_pit = round(unname(fic_ic[f]) %||% NA_real_, 4),
    ic_n_months = unname(fic_n[f]) %||% NA_integer_,
    economic_rationale = unname(RAT[f]),
    selection_objective = "icir",
    source = "db_existing",
    load_path = "load_month_factors() [C15-compliant]"
  )
})

# ---- diagnostics ----
diagnostics <- list(
  rank_ic = round(ic$mean,4),
  rank_ic_sd = round(ic$sd,4),
  icir = round(ic$icir,3),
  ic_hit_rate = round(ic$hit,3),
  ic_n_months = ic$n,
  harvey_t_rank_ic_naive = round(ic$t_naive,3),
  harvey_t_rank_ic_haircut066 = round(ic$t_harvey,3),
  subperiod_ic = list(`2005_2013`=round(ic$sp[1],4), `2014_2019`=round(ic$sp[2],4), `2020_2026`=round(ic$sp[3],4)),
  subperiod_stability = round(ic$sp_pos,2),
  monotonicity_note = "decile monotonicity not recomputed; composite IC>0 rate 63.3% (analysis_report)",
  turnover_proxy_annual = 1.216,
  fm_nw_t = 2.086,
  fm_score_lambda = 0.00293,
  ff3_alpha_annual = 0.0865, ff3_alpha_t = 2.613,
  carhart4_alpha_annual = 0.0454, carhart4_alpha_t = 1.789,
  ff5_alpha_annual = 0.0774, ff5_alpha_t = 2.318,
  metric_type_rank_ic = "canonical_screen",
  metric_type_portfolio_alpha = "backtested_forge_authoritative"
)

# ---- portfolio-level authoritative (from RC_16 backtest, NOT alpha-computed) ----
portfolio_authoritative <- list(
  source = "stage_artifacts/alpha_search/20260613_021015_217222 (RC_16 de-contaminated runner, build_bt_result+essence_score)",
  metric_type = "backtested",
  net_sharpe = 0.848,
  net_ir = 0.393,
  portfolio_alpha_t_nw_lag3 = 1.694,
  portfolio_alpha_t_pvalue = 0.090,
  alpha_annualized = 0.0861,
  beta_to_bm = 0.776,
  bm_correlation = 0.754,
  cagr = 0.172,
  mdd = 0.484,
  calmar = 0.356,
  oos_retention = -0.516,
  dsr = NA,
  dsr_gate_applied = FALSE,
  selection_type = "chain",
  essence_grade = "C",
  up_capture = 0.805, down_capture = 0.726,
  skewness = -0.295, kurtosis = 5.97,
  note = "portfolio_alpha_t_nw_lag3=1.694 << 2.95 HARD graduation gate. rank-IC harvey-t(naive 3.58) MISLEADS vs realized 1.69 — Cycle 2 교훈 정합."
)

# ---- incumbent overlap ----
incumbent_overlap <- list(
  incumbent = "STR_1715_AR_on_M4_R05_overlay_PG2 (deployed variant L5_V4_R05_adaptive, book IR 1.5754, 100% weight)",
  basis_note = "active = total_net - KOSPI200_TR. corr computed on 255 common months 2005-02~2026-04.",
  corr_total_net = round(OV$cor_total,4),
  corr_active_vs_bm = round(OV$cor_active,4),
  corr_total_net_vs_L4_precedent = round(OV$cor_total_l4,4),
  corr_active_vs_L4_precedent = round(OV$cor_active_l4,4),
  rolling36m_active_corr = list(min=round(OV$roll_active$min,3), median=round(OV$roll_active$median,3), max=round(OV$roll_active$max,3)),
  subperiod_active_corr = list(
    `2005_2013`=round(OV$sp$cor_active_v4[OV$sp$period=="2005-2013"],3),
    `2014_2019`=round(OV$sp$cor_active_v4[OV$sp$period=="2014-2019"],3),
    `2020_2026`=round(OV$sp$cor_active_v4[OV$sp$period=="2020-2026"],3)),
  core_monthly_cagr = round(OV$core_cagr,3), core_monthly_sr = round(OV$core_sr,3),
  incumbent_monthly_cagr = round(OV$inc_cagr,3), incumbent_monthly_sr = round(OV$inc_sr,3),
  request_claim_corr_core = 1.00,
  measured_correction = "★REFUTES request premise. Measured active corr = 0.265 (NOT 1.0). corr_core 1.00 in 409-batch = self-referential/contaminated metric (corr to batch's OWN core-composite reference family = near-self). Parallels FR-Cycle3 self-correction [[project-fr-cycle3-batch434-nogo]] (book 대비 total-basis 0.08 artifact vs active-basis 0.42~0.49).",
  book_marginal_implication = "standalone book-marginal ΔIR NOT structurally ~0. active corr 0.265 << 0.95 cor-cap → real diversification potential. governor/optimizer 판정 입력: 'CORE는 incumbent와 다른 스트림'. 단, standalone SR 0.85 << incumbent 1.61이므로 100%-weight admit은 여전히 불가 — 가치는 blend marginal IR에서 발생."
)

# ---- challenge_flags ----
challenge_flags <- list(
  list(id="RF-A1", severity="MEDIUM",
       note="rank-IC harvey-t haircut(0.66)=2.36 < 3.0 advisory gate; naive 3.58 inflated by composite. portfolio_alpha_t 1.69 << 2.95 HARD."),
  list(id="FMT-07", severity="HIGH",
       note="Publication decay: active SR pre-2017 0.96 -> post-2017 -0.40. oos_retention -0.516 (<0.5 무조건 FAIL band). graduation/자본 tier 불가."),
  list(id="FMT-01", severity="HIGH",
       note="Structural MDD 48.4% (>45%). 방어 2팩터(D01/D02) 포함에도 위기 동반급락. risk/optimizer overlay 없이는 자본 부적격."),
  list(id="FMT-04", severity="MEDIUM",
       note="Regime blindness: MDD 48% & BM corr 0.75. 국면필터 부재 — overlay candidate(screen_route)."),
  list(id="AXIS-MOM-WEAK", severity="MEDIUM",
       note="모멘텀 3팩터(M01/M05/M07) ICIR 0.11~0.14 + D02_Beta 0.10 매우 약함. Carhart-4 alpha t=1.79(무의미) — 알파의 momentum 기여 거의 없음. EW 10팩터 중 4팩터가 노이즈 희석(Factor Zoo 축소 관점: 6팩터 defense+quality+value가 실질). REVISE 후보: 4약팩터 제거 ablation 권고."),
  list(id="PREMISE-CORR", severity="HIGH",
       note="★request 'corr_core 1.00' 실측 반박: active corr 0.265. 본 WT 핵심 정정. incumbent와 동일 스트림 아님.")
)

method_log <- list(
  alpha_agent = list(
    candidates_tried = 1,
    selection_type = "chain",
    method_log = list(list(name="CORE_COMPOSITE_10f_EW", rank_ic=0.0384, icir=0.224, selected=TRUE,
                           note="pre-discovered cluster12 RC_16 de-contaminated; not a fresh search")),
    parallel_exec = FALSE, n_workers = 1
  )
)

# ---- assemble package ----
pkg <- list(
  task_id = "WT-D20260614_002",
  wt_type = "discovery",
  as_of_date = "2026-06-14",
  signal_date = "2026-05-31",
  forecast_horizon = "1M",
  hypothesis_title = "QEPM409-CORE_COMPOSITE: 10-factor EW composite (cluster12 RC_16 de-contaminated)",
  recipe = list(
    factors = names(AXIS),
    axes = list(defense=c("D01_IdioVol","D02_Beta"),
                momentum=c("M07_IndMom","M01_Mom_12_1","M05_Trended_Mom"),
                quality=c("Q01_GPA","Q04_Piotroski_F","Q09_CFOA","Q07_Earnings_Stability"),
                value=c("V01_BM")),
    combination="equal-weight z-score composite", n_holdings_recipe=30, rebalance="monthly",
    universe="KOSPI200 union KOSDAQ150 (KR_top342, PIT time-varying), 2005-01~",
    label_contamination_note="409-batch label 'Dispersion x Vol' = codegen contamination [[project-batch434-codegen-contamination]]. TRUE signal = FACTOR_NAMES of runner. This WT uses de-contaminated recipe as authoritative alpha definition."
  ),
  selection_objective = "icir",
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  alpha_scores_full_ref = "stage_artifacts/WT-D20260614_002/alpha_scores.parquet (2554 names)",
  n_names_scored = nrow(scores),
  factor_specs = factor_specs,
  diagnostics = diagnostics,
  portfolio_authoritative = portfolio_authoritative,
  incumbent_overlap = incumbent_overlap,
  redundancy_cluster_id = "cluster12_RC_16_disp_vol_dual",
  cost_model_version = "v2.4_kr_retail_15bps",
  cost_aware_note = "net-of-cost 15bps already in authoritative metrics (delta-based v2.4). gross alpha annual ~8.6%+cost; net IR 0.393, net SR 0.848. TO 121.6%/yr → ~18bps/yr drag.",
  weaknesses_carry = list(
    "MDD 48.4% structural (방어팩터 포함에도)",
    "standalone net SR 0.848 << 2.5 목표",
    "portfolio_alpha_t 1.694 << 2.95 HARD graduation gate (DSR gate N/A=chain)",
    "oos_retention -0.516 (<0.5 FAIL) = post-2017 publication decay",
    "incumbent active corr 0.265 (NOT 1.0 as claimed) — diversification 있으나 standalone SR 열위로 100% admit 불가"
  ),
  honest_value_statement = "신규 alpha mechanism 아님. 본 WT의 정직한 가치 = (1) 'corr_core 1.00' 오염 반박(active 0.265) (2) 알파 실질 동인 = defense(D01 IdioVol)+quality(Q04 Piotroski), momentum 4팩터는 노이즈 (3) standalone 자본 부적격(PORT_t 1.69, oos -0.52) 확정 — risk/optimizer가 overlay/risk-budget로 risk-adjusted 개선 가능한지가 다음 판정.",
  method_shopping_log = method_log,
  challenge_flags = challenge_flags,
  research_philosophy_compliance = list(
    p1_factor_zoo = "10팩터 중 6팩터(defense+quality+value)가 ICIR>0.5, momentum 4팩터 약함 — ablation 권고. redundancy_cluster_id 명시.",
    p2_cost_aware = "모든 SR/IR net-of-cost 15bps. gross-only 보고 없음.",
    p3_uncertainty = "rank-IC harvey-t 분포 3 subperiod + naive/haircut 2축. portfolio_alpha_t와 명시 구분(1.69 vs naive 3.58)."
  )
)

# Step 1: write draft package
write_json(pkg, file.path(OUT_WT,"alpha_package_draft.json"), pretty=TRUE, auto_unbox=TRUE, na="null")
cat("[assemble] alpha_package_draft.json written.\n")

# alpha_validation.json
validation <- list(
  task_id="WT-D20260614_002",
  validated_at=as.character(Sys.time()),
  pit_compliance=list(c1_c15="all factors via load_month_factors() (C15) + Z_Score_Aligned IC-dir PIT Usable_Date<=sig (C14) + quarterly/annual lag (C4)", status="PASS"),
  graduation_gate=list(
    portfolio_alpha_t_nw=list(value=1.694, threshold=2.95, severity="hard", verdict="FAIL"),
    dsr=list(value=NA, threshold=0.5, severity="hard_sweep_only", applied=FALSE, selection_type="chain", verdict="N/A"),
    oos_retention=list(value=-0.516, threshold=0.7, band_fail=0.5, verdict="FAIL_HARD"),
    calmar=list(value=0.356, threshold=0.64, severity="hard", verdict="FAIL"),
    rank_ic=list(value=0.0384, threshold=0.04, severity="advisory", verdict="MARGINAL_FAIL"),
    icir=list(value=0.224, threshold=0.20, severity="advisory", verdict="PASS"),
    harvey_t=list(value_naive=3.58, value_haircut=2.36, threshold=3.0, severity="advisory", verdict="MARGINAL"),
    subperiod_stability=list(value=1.00, threshold=0.50, severity="advisory", verdict="PASS")
  ),
  screening_tier=list(
    screen_pass=FALSE,
    reason="oos_retention -0.516 + structural MDD; but SR 0.848>=0.7 신호력 존재 → screen_route candidate",
    screen_route="OVERLAY_CANDIDATE / DPL_FEATURE (incumbent active corr 0.265 → blend marginal 가치)"
  ),
  universe_comparison=list(
    note="KR_top342 default used. ICIR 0.224 not <0.15 attenuation 영역 → v2 KR_TOP500_FREEFLOAT mandate 미발동. (L-227 trigger 불충족)",
    v2_run=FALSE
  ),
  axiom_check=list(
    ax001_v2="D01/D02 defense 포함 — 조건부 평가 대상이나 standalone 전기간 SR으로 판정 안 함(crisis_alpha 별도). N/A standalone admit.",
    ax002="모든 수치 harness/contract 경유 실측. proxy graduation 선언 없음.",
    ax004="quality multi-axis composite(Q01/Q04/Q07/Q09) — single-signal 아님, AX-004 EXCLUSION 정합."
  ),
  verdict="STANDALONE_GRADUATION_FAIL (PORT_t 1.69 / oos -0.52 / calmar 0.36). screening 신호력 존재 → risk/optimizer overlay 개선 + blend marginal IR 판정으로 진행."
)
write_json(validation, file.path(OUT_STAGE,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, na="null")
cat("[assemble] alpha_validation.json written.\n")
cat("\n[assemble] DONE.\n")
