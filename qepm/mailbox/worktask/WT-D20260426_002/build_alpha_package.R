#==============================================================================
# WT-D20260426_002 Iter 8 — alpha_package.json builder
# Critical: write_json → record_package_lineage 순서 (L-194 fix)
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID    <- "WT-D20260426_002"
ART_DIR  <- file.path("stage_artifacts", "WT_D20260426_002")
WT_DIR   <- file.path("qepm/mailbox/worktask", WT_ID)
DRAFT    <- as.logical(Sys.getenv("ALPHA_DRAFT_ONLY", "FALSE"))

# Load alpha + diagnostics
alpha_dt <- as.data.table(read_parquet(file.path(ART_DIR, "alpha_scores.parquet")))
diag <- fromJSON(file.path(ART_DIR, "alpha_validation.json"), simplifyVector = FALSE)

# Latest snapshot for alpha_vector cross-section (as_of_date = max sig_date)
as_of <- max(alpha_dt$Date)
last_xs <- alpha_dt[Date == as_of]
cat("[Pkg] as_of_date =", as.character(as_of), "| N tickers =", nrow(last_xs), "\n")

alpha_vector_ls <- as.list(setNames(last_xs$alpha, last_xs$Ticker))
confidence_vector_ls <- as.list(setNames(last_xs$confidence, last_xs$Ticker))

# Diagnostics - flatten
ic_active <- diag$ic_active_BULLNORMAL
specs_dt <- rbindlist(lapply(names(diag$spec_5_robustness), function(nm) {
  rec <- diag$spec_5_robustness[[nm]]
  data.table(spec = rec$spec, ic = rec$ic, t = rec$t, n = rec$n)
}))
n_pass_harvey <- sum(specs_dt$t > 3.0, na.rm = TRUE)

# Graduation evaluation
grad_pass <- list(
  rank_ic       = ic_active$rank_ic_mean >= 0.04,
  icir          = ic_active$icir >= 0.20,
  subperiod     = diag$subperiod_sign_consistency >= 0.50,
  harvey        = diag$harvey_t_active >= 3.0,
  dsr           = diag$dsr_post_penalty >= 0.5,
  tdc_lt_030    = diag$tdc_vs_str1700$tdc_avg < 0.30,
  spec5_harvey  = n_pass_harvey >= 4
)
grad_overall <- all(unlist(grad_pass))
cat("[Pkg] Graduation gate:", if (grad_overall) "PASS" else "FAIL", "\n")
cat("[Pkg] Detail:\n"); print(grad_pass)

honest_verdict <- paste0(
  "Iter 8 L01_Amihud regime-conditional sleeve alpha graduation: ",
  if (grad_overall) "MET. " else "NOT MET. ",
  sprintf("Active (BULL+NORMAL) rank_IC=%.4f / ICIR=%.3f / Harvey t=%.3f / DSR=%.3f / TDC vs STR_1700=%.3f. ",
          ic_active$rank_ic_mean, ic_active$icir,
          diag$harvey_t_active, diag$dsr_post_penalty,
          diag$tdc_vs_str1700$tdc_avg),
  sprintf("Regime split: BULL ICIR=%.3f (negative — flight-to-quality 가설 invalid), NORMAL ICIR=%.3f (positive, hypothesis 부분 입증). ",
          diag$ic_by_regime$BULL$icir,
          diag$ic_by_regime$NORMAL$icir),
  "Lesson: Liquidity premium (Amihud 2002) regime-conditional sleeve in KR market — NORMAL only positive (ICIR ~0.20 boundary), BULL reverse, subperiod 2008-14 negative dominates. Multi-sleeve with cash overlay TDC=0.17 cross-family achieved BUT alpha source 자체 미입증. ",
  "Recommendation: Sprint 종결 + L-209 적립 (단일 L01 axis insufficient; regime-conditional alone cannot rescue weak signal). Next pivot: Iter 9 cross-family Growth × Investor_Flow residualized 또는 admission cycle re-sequence."
)

# Method shopping log (R2-C 강제)
method_log <- list(
  list(name = "L01_Amihud_unconditional", rank_ic = NA, selected = FALSE,
       reason = "Iter 7 (4-axis Liquidity composite) IC=-0.05; unconditional fail. baseline reference."),
  list(name = "L01_Amihud_regime_conditional_70_30",
       rank_ic = ic_active$rank_ic_mean,
       icir = ic_active$icir,
       selected = TRUE,
       reason = "Iter 8 hypothesis: BULL/NORMAL only positive premium. regime panel lag-1 PIT-safe.")
)

candidates_tried <- length(method_log)

alpha_package <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  agent = "alpha",
  schema_version = "v1.2",
  as_of_date = format(as_of, "%Y-%m-%d"),
  forecast_horizon = "1M",
  selection_objective = "icir",  # role-specific: Alpha uses predictive power only
  alpha_vector = alpha_vector_ls,
  confidence_vector = confidence_vector_ls,
  signal_matrix_ref = paste0("file://", file.path(ART_DIR, "alpha_scores.parquet")),

  factor_specs = list(
    list(
      factor_family = "Liquidity_Risk",
      proxy = "L01_Amihud (Z_Score_Aligned)",
      formula = "regime_conditional( BULL/NORMAL: 0.70 * z_norm(Amihud), CAUTION/CRISIS: 0 )",
      lag_rule = "monthly factor (Usable_Date <= sig_date) + regime_state lag-1",
      winsorization = "3std cross-sectional",
      neutralization = "none (baseline single-axis)",
      economic_rationale = "Amihud (2002) illiquidity premium — KR market에서 unconditional negative IC 입증 (Iter 7). 가설: BULL/NORMAL only positive premium (Pastor-Stambaugh 2003 패턴), CAUTION/CRISIS는 flight-to-liquidity reverse 회피. Regime panel KR internals + expanding percentile (PIT-safe).",
      weight_theta = 0.70,
      source = "db_existing",
      references = c("Amihud (2002) JFM",
                     "Pastor-Stambaugh (2003) JPE",
                     "Kyle (1985) Econometrica")
    ),
    list(
      factor_family = "Cash_Sleeve",
      proxy = "regime cash overlay (alpha=0)",
      formula = "regime_state in {CAUTION, CRISIS} → alpha=0; else 30% baseline cash",
      lag_rule = "regime_state lag-1 (PIT-safe)",
      winsorization = "n/a",
      neutralization = "n/a",
      economic_rationale = "AX-007 EXCEPTION#1 multi-sleeve compliance + downside avoidance via regime-conditional cash. crisis_alpha hypothesis: BULL/NORMAL liquidity premium concentrated, CAUTION/CRISIS volatility avoid.",
      weight_theta = 0.30,
      source = "regime_overlay"
    )
  ),

  diagnostics = list(
    rank_ic = ic_active$rank_ic_mean,
    rank_ic_overall = diag$ic_overall$rank_ic_mean,
    icir = ic_active$icir,
    icir_overall = diag$ic_overall$icir,
    monotonicity = diag$monotonicity,
    subperiod_stability = diag$subperiod_sign_consistency,
    turnover_proxy = diag$turnover_proxy,
    harvey_t_stat = diag$harvey_t_active,
    dsr_post_penalty = diag$dsr_post_penalty,
    post_neutralization_ic = ic_active$rank_ic_mean,  # no neutralization applied
    n_specs_harvey_pass = n_pass_harvey,
    spec_5_robustness = lapply(seq_len(nrow(specs_dt)), function(i) {
      list(spec = specs_dt$spec[i], ic = specs_dt$ic[i],
           t = specs_dt$t[i], n = specs_dt$n[i])
    }),
    ic_by_regime = list(
      BULL = list(icir = diag$ic_by_regime$BULL$icir,
                  rank_ic = diag$ic_by_regime$BULL$rank_ic_mean,
                  N = diag$ic_by_regime$BULL$N),
      NORMAL = list(icir = diag$ic_by_regime$NORMAL$icir,
                    rank_ic = diag$ic_by_regime$NORMAL$rank_ic_mean,
                    N = diag$ic_by_regime$NORMAL$N),
      CAUTION = list(icir = NA, rank_ic = NA, alpha_zero = TRUE,
                     note = "cash sleeve, alpha=0"),
      CRISIS  = list(icir = NA, rank_ic = NA, alpha_zero = TRUE,
                     note = "cash sleeve, alpha=0")
    ),
    tdc_vs_str1700 = diag$tdc_vs_str1700,
    method_log = method_log,
    candidates_tried = candidates_tried,
    parallel_exec = TRUE,
    n_workers = min(8L, parallel::detectCores() - 1L),
    rcpp_used = FALSE,
    n_sig_dates_active = ic_active$n_periods,
    n_sig_dates_total = length(unique(alpha_dt$Date))
  ),

  ax_compliance = list(
    AX_003 = list(check = "EXCLUSION", note = "no value EP_STANDALONE used"),
    AX_004 = list(check = "EXCLUSION", note = "no quality_profitability single-axis used"),
    AX_005 = list(check = "EXCLUSION", note = "Liquidity_Risk family — NOT BAB/low-beta. L01_Amihud is illiquidity, not low-volatility."),
    AX_007 = list(check = "EXCEPTION#1",
                  note = "multi-sleeve: Liquidity sleeve (BULL/NORMAL 70%) + Cash sleeve (CAUTION/CRISIS 100%). single-sleeve top20 unconditional 회피.",
                  exception_id = 1)
  ),

  graduation = list(
    overall = grad_overall,
    detail = grad_pass,
    honest_verdict = honest_verdict
  ),

  challenge_flags = list(
    list(id = "RF-A1", severity = "MEDIUM",
         reason = "Subperiod 2008-14 sign reverse (rank_IC=-0.025 vs 2015-19 +0.044, 2020-23 +0.030). Sign consistency 67%."),
    list(id = "GRADUATION_FAIL", severity = "HIGH",
         reason = "Active rank_IC=0.0036 << 0.04 / Harvey t=0.32 << 3.0 / DSR=0.19 << 0.5 / Monotonicity=-0.42. Iter 8 hypothesis NOT MET."),
    list(id = "REGIME_ASYMMETRY", severity = "HIGH",
         reason = "BULL ICIR=-0.093 (가설과 reverse), NORMAL ICIR=0.203 (가설 부분 입증). regime-conditional sleeve가 BULL에서 negative 회피 못함."),
    list(id = "TDC_PASS", severity = "INFO",
         reason = "TDC vs STR_1700 = 0.173 < 0.30 (cross-family 입증). xs_corr = -0.06 거의 직교."),
    list(id = "SPRINT_TERMINATION_RECOMMENDED", severity = "HIGH",
         reason = "Iter 7 (composite) + Iter 8 (single-axis regime-conditional) 둘 다 graduation FAIL → Liquidity_Risk family alpha 단일 origin 한계 명백. L-209 적립 + Sprint 종결 또는 Iter 9 cross-family pivot 권고.")
  ),

  alternatives_recorded = list(
    pivot_a = list(
      family = "Growth × Investor_Flow",
      method = "earnings growth residualized by foreign investor net flow (DART quarterly + investor_wide.parquet)",
      rationale = "cross-family + KR domestic flow signal — NOT in STR_1700 (Analyst+Quality+Mom+Distress)."
    ),
    pivot_b = list(
      family = "Skewness Forensics",
      method = "rolling 12M return skewness × CFO accrual quality (Chen-Hong-Stein 2001 + Sloan 1996)",
      rationale = "tail-risk meets earnings quality. multi-axis 회피 + new-designed factor 가능."
    ),
    sprint_termination = list(
      action = "L-209 적립: 'KR Liquidity_Risk family (L01 single + L01-L11-L12-R13 composite) — unconditional fail + regime-conditional partial fail. NORMAL only ICIR=0.20 보더라인.'",
      next_step = "Sprint 종결 권고. WT-D20260427_001 새 sprint Growth × Investor_Flow."
    )
  )
)

# === Step 1: write alpha_package.json ===
out_path <- if (DRAFT) {
  file.path(WT_DIR, "alpha_package_draft.json")
} else {
  file.path(WT_DIR, "alpha_package.json")
}
write_json(alpha_package, out_path, pretty = TRUE,
           auto_unbox = TRUE, digits = 6, na = "null")
cat("[Pkg] Saved:", out_path, "\n")

if (!DRAFT) {
  # === Step 2: lineage record (post write) ===
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = WT_ID,
    package_type = "alpha_package",
    method_selected = "L01_Amihud_regime_conditional_70_30_multi_sleeve",
    input_file_paths = c(
      "stage_artifacts/WT_D20260426_002/alpha_scores.parquet",
      "stage_artifacts/WT_D20260426_002/alpha_validation.json",
      "stage_artifacts/WT_D20260425_007/regime_panel.parquet",
      "stage_artifacts/WT_D20260425_011/alpha_scores.parquet"
    )
  )
  cat("[Pkg] Lineage recorded.\n")
}

cat("[Pkg] DONE.\n")
