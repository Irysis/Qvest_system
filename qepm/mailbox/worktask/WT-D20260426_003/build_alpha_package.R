#==============================================================================
# WT-D20260426_003 Iter 9 — alpha_package.json builder
# Build draft 또는 final based on ALPHA_DRAFT_ONLY env var.
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID    <- "WT-D20260426_003"
ART_DIR  <- file.path("stage_artifacts", "WT_D20260426_003")
WT_DIR   <- file.path("qepm/mailbox/worktask", WT_ID)
DRAFT    <- as.logical(Sys.getenv("ALPHA_DRAFT_ONLY", "FALSE"))

# Load
alpha_dt <- as.data.table(read_parquet(file.path(ART_DIR, "alpha_scores.parquet")))
diag <- fromJSON(file.path(ART_DIR, "alpha_validation.json"), simplifyVector = FALSE)

# Latest snapshot
as_of <- max(alpha_dt$Date)
last_xs <- alpha_dt[Date == as_of]
cat("[Pkg] as_of_date =", as.character(as_of), "| N tickers =", nrow(last_xs), "\n")

alpha_vector_ls <- as.list(setNames(last_xs$alpha, last_xs$Ticker))
confidence_vector_ls <- as.list(setNames(last_xs$confidence, last_xs$Ticker))

# Diagnostics flatten
ic_active <- diag$ic_active
ic_overall <- diag$ic_overall
specs_dt <- rbindlist(lapply(names(diag$spec_5_robustness), function(nm) {
  rec <- diag$spec_5_robustness[[nm]]
  data.table(spec = rec$spec, ic = rec$ic %||% NA_real_,
             t = rec$t %||% NA_real_, n = rec$n %||% 0L)
}))
n_pass_harvey <- sum(specs_dt$t > 3.0, na.rm = TRUE)

# Helper for null
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# Graduation
grad_pass <- list(
  rank_ic       = (ic_overall$rank_ic_mean %||% 0) >= 0.04,
  icir          = (ic_overall$icir %||% 0) >= 0.20,
  subperiod     = (diag$subperiod_sign_consistency %||% 0) >= 0.50,
  harvey        = (diag$harvey_t_overall %||% 0) >= 3.0,
  dsr           = (diag$dsr_post_penalty %||% 0) >= 0.5,
  tdc_lt_030    = (diag$tdc_vs_str1700$tdc_avg %||% 1) < 0.30,
  spec5_harvey  = n_pass_harvey >= 4,
  standalone_sr = (diag$standalone_sr_proxy_overall %||% 0) >= 1.0
)
grad_overall <- all(unlist(grad_pass))
cat("[Pkg] Graduation gate:", if (grad_overall) "PASS" else "FAIL", "\n")
cat("[Pkg] Detail:\n"); print(grad_pass)

# Component IC
comp_ic <- diag$component_ic

honest_verdict <- paste0(
  "Iter 9 Growth × Investor_Flow residualized cross-family alpha graduation: ",
  if (grad_overall) "MET. " else "NOT MET. ",
  sprintf("Overall rank_IC=%.4f / ICIR=%.3f / Harvey t=%.3f / DSR=%.3f / TDC vs STR_1700=%.3f / SR proxy=%.3f. ",
          ic_overall$rank_ic_mean, ic_overall$icir,
          diag$harvey_t_overall, diag$dsr_post_penalty,
          diag$tdc_vs_str1700$tdc_avg,
          diag$standalone_sr_proxy_overall),
  sprintf("Component decomposition: growth_z IC=%.4f (t=%.2f, ICIR=%.3f); flow_resid_z IC=%.4f (t=%.2f, ICIR=%.3f, NEGATIVE — KR post-flow reversal); interact_z IC=%.4f (t=%.2f). ",
          comp_ic$growth_z$mean_ic %||% 0, comp_ic$growth_z$t_stat %||% 0, comp_ic$growth_z$icir %||% 0,
          comp_ic$flow_resid_z$mean_ic %||% 0, comp_ic$flow_resid_z$t_stat %||% 0, comp_ic$flow_resid_z$icir %||% 0,
          comp_ic$interact_z$mean_ic %||% 0, comp_ic$interact_z$t_stat %||% 0),
  sprintf("Regime split: BULL ICIR=%.3f (positive — hypothesis 부분 입증), NORMAL ICIR=%.3f, CAUTION ICIR=%.3f. Subperiod sign consistency=%.2f (2015-19/2020-23 negative drift). ",
          diag$ic_by_regime$BULL$icir %||% 0,
          diag$ic_by_regime$NORMAL$icir %||% 0,
          diag$ic_by_regime$CAUTION$icir %||% 0,
          diag$subperiod_sign_consistency),
  "Honest finding: KR market에서 INV02/INV04 60d net buy는 negative IC (post-flow reversal — Lee-Liu 2014, Choe-Kho-Stulz 1999 후속). Growth signal (GR06+GR01+C17) 단독 IC=0.014 (modest positive, t=2.03 < 3.0). 두 source 결합 시 상호 cancellation으로 composite IC near-zero. ",
  "Iter 9 conclusion: cross-family Growth+Flow 가설은 KR top-universe에서 'flow direction reversal' 때문에 simple-additive composite로는 alpha 부재. INV13_Foreign_Resid_*는 daily-only로 monthly DB 부재. ",
  "Recommendation: Sprint 종결 + L-210 적립. Next pivot: ML sizing (XGBoost/RF) 으로 Growth × Flow nonlinear interaction 추출 — 현 linear residualization으로 미흡. 또는 Skewness Forensics × CFO accrual (Iter 8 alpha agent alternative recommendation 잔여)."
)

# Method shopping log (R2-C 강제)
method_log <- list(
  list(name = "Growth_only_3factor_composite",
       rank_ic = comp_ic$growth_z$mean_ic %||% NA,
       icir = comp_ic$growth_z$icir %||% NA,
       t_stat = comp_ic$growth_z$t_stat %||% NA,
       selected = FALSE,
       reason = "Single-axis Growth IC=0.014 (t=2.03, t<3 FAIL). standalone candidate baseline reference."),
  list(name = "Flow_resid_only_3factor_composite",
       rank_ic = comp_ic$flow_resid_z$mean_ic %||% NA,
       icir = comp_ic$flow_resid_z$icir %||% NA,
       t_stat = comp_ic$flow_resid_z$t_stat %||% NA,
       selected = FALSE,
       reason = "Flow IC=-0.015 (NEGATIVE, t=-2.23). KR post-flow reversal 입증. AX-002 honest report — NOT discarded as failure but documented as evidence."),
  list(name = "Growth_x_FlowResid_composite_50_30_20",
       rank_ic = ic_overall$rank_ic_mean,
       icir = ic_overall$icir,
       t_stat = diag$harvey_t_overall,
       selected = TRUE,
       reason = "Iter 9 hypothesis: cross-family Growth + Flow_resid + interaction. 50/30/20 weight. graduation FAIL 입증 (composite cancellation). honest finalize."),
  list(name = "Multi_sleeve_regime_overlay",
       sleeve_config = "BULL/NORMAL: 80% alpha + 20% cash; CAUTION: 50%+50%; CRISIS: 0%+100%",
       selected = TRUE,
       reason = "AX-007 EXCEPTION#1 multi-sleeve compliance. BULL ICIR=0.272 입증 (regime-conditional partial alpha). CRISIS cash 회피 = downside protection.")
)

candidates_tried <- length(method_log)

alpha_package <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  agent = "alpha",
  schema_version = "v1.2",
  as_of_date = format(as_of, "%Y-%m-%d"),
  forecast_horizon = "1M",
  selection_objective = "icir",
  alpha_vector = alpha_vector_ls,
  confidence_vector = confidence_vector_ls,
  signal_matrix_ref = paste0("file://", file.path(ART_DIR, "alpha_scores.parquet")),

  factor_specs = list(
    list(
      factor_family = "Growth",
      proxy = "GR06_OCF_Growth + GR01_Revenue_Growth + C17_OP_Revision composite (Z_Score_Aligned, mean)",
      formula = "growth_z = xs_zscore( mean( z(GR06), z(GR01), z(C17) ) )",
      lag_rule = "monthly factor (Usable_Date <= sig_date) — fundamental 45d/annual May (factor DB 강제)",
      winsorization = "3std cross-sectional",
      neutralization = "none baseline; flow residualized vs growth (orthogonalization step)",
      economic_rationale = "Operating Cash Flow Growth (GR06) + Revenue Growth (GR01) — actuals YoY growth (Cooper-Gulen-Schill 2008 inverse direction); Operating Profit consensus revision (C17) — forward growth signal (Chan-Jegadeesh-Lakonishok 1996). 3-axis covers actuals + forecast revision growth.",
      weight_theta = 0.50,
      source = "db_existing_composite",
      references = c("Cooper Gulen Schill (2008) JF",
                     "Chan Jegadeesh Lakonishok (1996) JF — earnings momentum",
                     "Lakonishok Shleifer Vishny (1994)")
    ),
    list(
      factor_family = "Investor_Flow",
      proxy = "INV02_Foreign_NetBuy_60d + INV04_Inst_NetBuy_60d + INV08_Foreign_Inst_Agreement composite, residualized vs Growth",
      formula = "flow_resid_z = xs_zscore( residual( mean( z(INV02), z(INV04), z(INV08) ) ~ growth_z ) )",
      lag_rule = "monthly factor (Usable_Date <= sig_date) — investor flow t-1 settlement",
      winsorization = "3std cross-sectional",
      neutralization = "OLS residualized vs growth_z (cross-family orthogonality)",
      economic_rationale = "Foreign + Institutional 60d net buy intensity — KR market에서 외인+기관은 정보 우위 (Choe-Kho-Stulz 1999). Foreign-Inst Agreement = 동조 매수 신호. Residualization vs growth는 fundamental-driven flow 제거.",
      weight_theta = 0.30,
      source = "db_existing_composite_residualized",
      references = c("Choe Kho Stulz (1999) JFE — foreign vs domestic info edge",
                     "Lee Liu (2014) JFQA — KR investor reversal",
                     "Sias (2004) RFS — institutional herding")
    ),
    list(
      factor_family = "Cross_Family_Interaction",
      proxy = "sign(growth_z) * |flow_resid_z| z-scored",
      formula = "interact_z = xs_zscore( sign(growth_z) * abs(flow_resid_z) )",
      lag_rule = "derived from above two (no additional lag)",
      winsorization = "3std cross-sectional",
      neutralization = "n/a (already orthogonalized)",
      economic_rationale = "Growth-direction-amplified information edge (Hong-Stein 1999 정보 비대칭). Positive Growth + High Flow magnitude = strongest signal.",
      weight_theta = 0.20,
      source = "db_derived",
      references = c("Hong Stein (1999) JF — gradual information diffusion")
    ),
    list(
      factor_family = "Cash_Overlay",
      proxy = "regime cash overlay (alpha=0)",
      formula = "BULL/NORMAL: 20% baseline cash; CAUTION: 50%; CRISIS: 100%",
      lag_rule = "regime_state lag-1 (PIT-safe)",
      winsorization = "n/a",
      neutralization = "n/a",
      economic_rationale = "AX-007 EXCEPTION#1 multi-sleeve compliance + crisis avoidance.",
      weight_theta = 0.0,
      source = "regime_overlay"
    )
  ),

  diagnostics = list(
    rank_ic = ic_overall$rank_ic_mean,
    rank_ic_overall = ic_overall$rank_ic_mean,
    icir = ic_overall$icir,
    icir_overall = ic_overall$icir,
    monotonicity = diag$monotonicity,
    subperiod_stability = diag$subperiod_sign_consistency,
    turnover_proxy = diag$turnover_proxy,
    harvey_t_stat = diag$harvey_t_overall,
    dsr_post_penalty = diag$dsr_post_penalty,
    post_neutralization_ic = ic_overall$rank_ic_mean,
    n_specs_harvey_pass = n_pass_harvey,
    standalone_sr_proxy = diag$standalone_sr_proxy_overall,
    spec_5_robustness = lapply(seq_len(nrow(specs_dt)), function(i) {
      list(spec = specs_dt$spec[i], ic = specs_dt$ic[i],
           t = specs_dt$t[i], n = specs_dt$n[i])
    }),
    component_ic = comp_ic,
    ic_by_regime = list(
      BULL = list(icir = diag$ic_by_regime$BULL$icir,
                  rank_ic = diag$ic_by_regime$BULL$rank_ic_mean,
                  N = diag$ic_by_regime$BULL$N),
      NORMAL = list(icir = diag$ic_by_regime$NORMAL$icir,
                    rank_ic = diag$ic_by_regime$NORMAL$rank_ic_mean,
                    N = diag$ic_by_regime$NORMAL$N),
      CAUTION = list(icir = diag$ic_by_regime$CAUTION$icir,
                     rank_ic = diag$ic_by_regime$CAUTION$rank_ic_mean,
                     N = diag$ic_by_regime$CAUTION$N),
      CRISIS  = list(icir = NA, rank_ic = NA, alpha_zero = TRUE,
                     note = "cash sleeve, alpha=0")
    ),
    tdc_vs_str1700 = diag$tdc_vs_str1700,
    method_log = method_log,
    candidates_tried = candidates_tried,
    parallel_exec = TRUE,
    n_workers = min(8L, parallel::detectCores() - 1L),
    rcpp_used = FALSE,
    n_sig_dates_active = ic_active$n_periods %||% 0,
    n_sig_dates_total = length(unique(alpha_dt$Date)),
    schema_compliance = list(
      time_series_alpha = TRUE,
      load_month_factors_used = TRUE,
      n_sig_dates_ge_60 = length(unique(alpha_dt$Date)) >= 60
    )
  ),

  ax_compliance = list(
    AX_003 = list(check = "EXCLUSION", note = "no value EP_STANDALONE used. Growth + Flow only."),
    AX_004 = list(check = "EXCLUSION", note = "no quality_profitability single-axis. Growth (GR-series) is YoY growth, not single-axis quality."),
    AX_005 = list(check = "EXCLUSION", note = "Growth + Investor_Flow cross-family. NOT BAB/low-beta. Multi-sleeve regime overlay."),
    AX_007 = list(check = "EXCEPTION#1",
                  note = "multi-sleeve: Alpha sleeve (Growth+Flow+Interaction) + Cash sleeve (regime-conditional 20-50-100%). BULL/NORMAL: 80/20; CAUTION: 50/50; CRISIS: 0/100.",
                  exception_id = 1),
    AX_002 = list(check = "PASS", note = "honest negative reporting — flow_resid_z negative IC documented as KR post-flow reversal evidence (Lee-Liu 2014), NOT silently dropped.")
  ),

  graduation = list(
    overall = grad_overall,
    detail = grad_pass,
    honest_verdict = honest_verdict
  ),

  challenge_flags = list(
    list(id = "RF-A1", severity = "HIGH",
         reason = sprintf("Subperiod sign consistency = %.2f (2008-14 +0.012 / 2015-19 -0.009 / 2020-23 -0.020). Recent 8년 negative drift — flow component dominates negatively in 2015+. ALPHA NOT robust across regimes.",
                          diag$subperiod_sign_consistency)),
    list(id = "GRADUATION_FAIL", severity = "HIGH",
         reason = sprintf("Composite rank_IC=%.4f << 0.04 / ICIR=%.3f << 0.20 / Harvey t=%.3f << 3.0 / DSR=%.3f / SR proxy=%.3f << 1.0. graduation gate 8/8 미달 except subperiod 0.33<0.50.",
                          ic_overall$rank_ic_mean, ic_overall$icir,
                          diag$harvey_t_overall, diag$dsr_post_penalty,
                          diag$standalone_sr_proxy_overall)),
    list(id = "FLOW_REVERSAL_KR", severity = "HIGH",
         reason = sprintf("flow_resid_z 단독 IC=%.4f (t=%.2f). KR market post-flow reversal (Lee-Liu 2014) 입증 — Foreign+Inst 60d net buy 종목이 다음달 underperform. 가설의 'flow → 정보 우위 alpha'는 KR top-universe 60d horizon에서 invalid. C13 강제 (Z_Score_Aligned only) 하에 flow signal direction 변경 불가.",
                          comp_ic$flow_resid_z$mean_ic %||% 0, comp_ic$flow_resid_z$t_stat %||% 0)),
    list(id = "COMPOSITE_CANCELLATION", severity = "HIGH",
         reason = "growth_z (+0.014) + flow_resid_z (-0.015) → composite IC ≈ 0. Naïve linear additive composite으로 두 source 합산 시 상호 cancellation. nonlinear (XGBoost/Kalman) sizing 필요."),
    list(id = "DATA_GAP_DAILY_ONLY", severity = "MEDIUM",
         reason = "INV13_Foreign_Resid_Individual_*는 daily-only factor (monthly DB 부재). v2에서 INV02+INV04+INV08 monthly composite로 fallback. residualization은 동일하게 적용했으나 daily-resolution residualization 정밀도 손실. monthly Factor DB에 INV13 monthly 변형 추가 권고 (factor_db pipeline upgrade)."),
    list(id = "REGIME_PARTIAL_ALPHA", severity = "INFO",
         reason = sprintf("BULL ICIR=%.3f (positive — hypothesis 부분 입증), NORMAL ICIR=%.3f (negative), CAUTION ICIR=%.3f (negative). BULL only sub-strategy IC=0.024 (t=2.5 borderline). regime-conditional Growth+Flow potential.",
                          diag$ic_by_regime$BULL$icir %||% 0,
                          diag$ic_by_regime$NORMAL$icir %||% 0,
                          diag$ic_by_regime$CAUTION$icir %||% 0)),
    list(id = "TDC_PASS", severity = "INFO",
         reason = sprintf("TDC vs STR_1700 = %.3f < 0.30 (cross-family orthogonality 입증). xs_corr = %.3f (≈0). STR_1700 Analyst_Consensus + Quality + Mom + Distress와 zero overlap (STR_1700 factor list 7개 중 0건 사용). Sequential Admission 자격 BUT alpha 자체 미입증으로 ensemble 부적격.",
                          diag$tdc_vs_str1700$tdc_avg,
                          diag$tdc_vs_str1700$cross_sectional_corr_mean)),
    list(id = "SPRINT_TERMINATION_RECOMMENDED", severity = "HIGH",
         reason = "Iter 7 (Liquidity composite 4-axis) + Iter 8 (Liquidity single-axis regime-conditional) + Iter 9 (cross-family Growth × Flow) 3건 연속 graduation FAIL → KR top-universe (max_names=500, liq 50M won) 에서 simple linear composite (single + multi-axis + cross-family) 모두 alpha 부재. L-210 적립 + Sprint 종결 또는 ML/nonlinear sizing pivot 권고.")
  ),

  alternatives_recorded = list(
    pivot_a = list(
      family = "Growth × Flow ML Sizing",
      method = "XGBoost (Growth_z + Flow_z + Interact_z + regime + size + sector dummies → 1M return) Walk-forward 12M training. SHAP feature importance + cross-validation.",
      rationale = "Linear additive 50/30/20 composite 시 cancellation. Nonlinear interaction (Hong-Stein 1999 information diffusion 수식적 nonlinearity) ML로 추출. KR market 비대칭 정보 비선형 효과 잠재."
    ),
    pivot_b = list(
      family = "Skewness Forensics × CFO Accrual",
      method = "12M return skewness (Chen-Hong-Stein 2001) × CFO/NI accrual quality (Sloan 1996) cross-family. tail-risk meets earnings quality.",
      rationale = "Iter 8 alpha agent alternative recommendation 잔여. multi-axis 회피 + new-designed factor 가능."
    ),
    pivot_c = list(
      family = "BULL-only Growth+Flow Sub-strategy",
      method = "Regime-conditional restriction: BULL only active (ICIR=0.272 입증). NORMAL/CAUTION/CRISIS = full cash. effective alpha 약 35% of months.",
      rationale = "BULL regime sub-period에서 Growth+Flow 가설 부분 입증. 그러나 35% only active period로는 standalone PG candidate 부적격."
    ),
    sprint_termination = list(
      action = "L-210 적립: 'KR top-universe (n=500, liq 50M) cross-family Growth (GR01/GR06/C17) × Investor_Flow (INV02/INV04/INV08) 60d-horizon residualized: linear additive composite으로 alpha 부재 — flow component KR post-flow reversal로 negative IC, growth +0.014 modest insufficient. composite cancellation 패턴.'",
      next_step = "Sprint 종결 권고. WT-D20260427_001 새 sprint = Growth × Flow ML sizing (XGBoost) 또는 Skewness × CFO accrual."
    )
  )
)

# === Step 1: write alpha_package(_draft).json ===
out_path <- if (DRAFT) {
  file.path(WT_DIR, "alpha_package_draft.json")
} else {
  file.path(WT_DIR, "alpha_package.json")
}
write_json(alpha_package, out_path, pretty = TRUE,
           auto_unbox = TRUE, digits = 6, na = "null")
cat("[Pkg] Saved:", out_path, "\n")

if (!DRAFT) {
  # === Step 2: lineage record ===
  tryCatch({
    source("02_Infrastructure/worktask/lineage_utils.R")
    record_package_lineage(
      task_id = WT_ID,
      package_type = "alpha_package",
      method_selected = "Growth_x_FlowResid_composite_50_30_20_multi_sleeve",
      input_file_paths = c(
        "stage_artifacts/WT_D20260426_003/alpha_scores.parquet",
        "stage_artifacts/WT_D20260426_003/alpha_validation.json",
        "stage_artifacts/WT_D20260425_007/regime_panel.parquet",
        "stage_artifacts/WT_D20260425_011/alpha_scores.parquet"
      )
    )
    cat("[Pkg] Lineage recorded.\n")
  }, error = function(e) {
    cat("[Pkg] Lineage record failed (non-blocking):", conditionMessage(e), "\n")
  })
}

cat("[Pkg] DONE.\n")
