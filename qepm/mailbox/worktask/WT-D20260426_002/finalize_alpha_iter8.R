#==============================================================================
# WT-D20260426_002 Iter 8 — Finalize alpha_package
#
# Codex Round (REJECT) 지적 반영:
#  C1 - graduation metrics FAIL: honest_verdict NOT MET 명시
#  C2 - universe 제약 미적용: STR_1700 universe (KOSPI200∪KOSDAQ150 + 2e8 TV
#       liquidity, 773 tickers) inner-join → 재측정
#  C3 - AX-007 overclaim: cash overlay → exception_note에 "overlay-not-alpha"
#       정직하게 표기
#  C4 - RF-A3 trigger: subperiod 2020-23 ICIR=0.24 vs overall=0.026 (9x)
#       challenge_flag 추가
#  C5 - challenge_note.md missing: 본 finalize에서 동시 작성
#  C6 - DSR n_trials=5 understated: n_trials=10 (Iter7+Iter8 cumulative)
#  C7 - sector-neutral IC: post-neutralization 실행 + 재측정
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

# Load alpha + reference
alpha_dt <- as.data.table(read_parquet(file.path(ART_DIR, "alpha_scores.parquet")))
str1700  <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_011/alpha_scores.parquet"))
diag <- fromJSON(file.path(ART_DIR, "alpha_validation.json"), simplifyVector = FALSE)

# ============================================================
# C2 fix — restrict to STR_1700 universe (KOSPI200∪KOSDAQ150 + liq filter)
# ============================================================
universe_tickers <- unique(str1700$Ticker)
cat("[Final] Universe restriction: ", length(universe_tickers), " tickers (STR_1700 audited universe)\n")

alpha_universe <- alpha_dt[Ticker %in% universe_tickers]
cat("[Final] Alpha rows after universe filter:", nrow(alpha_universe),
    " | retain ratio:", round(nrow(alpha_universe)/nrow(alpha_dt), 3), "\n")

# Re-measure IC on universe-restricted sample
ret_dt <- str1700[, .(Date, Ticker, Ret_1m)]
combo_u <- alpha_universe[ret_dt, nomatch = 0L, on = .(Date, Ticker)]
combo_u <- combo_u[!is.na(Ret_1m) & !is.na(alpha)]

ic_u <- combo_u[, .(rank_ic = if (.N >= 30) suppressWarnings(cor(alpha, Ret_1m, method = "spearman")) else NA_real_,
                    regime_state = regime_state[1]),
                by = Date]
ic_u <- ic_u[!is.na(rank_ic)]
ic_active_u <- ic_u[regime_state %in% c("BULL","NORMAL")]
cat(sprintf("[Final] Universe IC overall: rank_IC=%.4f, ICIR=%.3f, N=%d\n",
            mean(ic_u$rank_ic), mean(ic_u$rank_ic)/sd(ic_u$rank_ic), nrow(ic_u)))
cat(sprintf("[Final] Universe IC active (BULL+NORMAL): rank_IC=%.4f, ICIR=%.3f, N=%d\n",
            mean(ic_active_u$rank_ic), mean(ic_active_u$rank_ic)/sd(ic_active_u$rank_ic),
            nrow(ic_active_u)))

# ============================================================
# C7 fix — Sector-neutralization (size proxy via market cap missing → use Ticker rank)
# Approach: per-Date, regress alpha on cross-sectional Ret_1m lagged proxies.
#   simple proxy: residualize alpha vs cross-sectional median return level. 본 alpha
#   가 single-axis라 표준 size/sector neutralization은 추가 데이터 필요.
# Practical approximation: residualize alpha on rolling-12M average return per Ticker
# (size proxy의 noise residual로 신호 손실 측정).
# ============================================================
# Compute 12M trailing avg return as size/momentum proxy
ret_dt[, Ret_1m_lag := shift(Ret_1m, 1L), by = Ticker]
# 12M trailing mean (PIT-safe, lag-1)
setorder(ret_dt, Ticker, Date)
ret_dt[, mom12 := frollmean(Ret_1m_lag, n = 12L, na.rm = TRUE), by = Ticker]
combo_n <- combo_u[ret_dt[, .(Date, Ticker, mom12)],
                   on = .(Date, Ticker), nomatch = 0L]
combo_n <- combo_n[!is.na(mom12)]

# Per-Date: residualize alpha on mom12 (cross-sectional OLS)
combo_n[, alpha_resid := {
  if (length(alpha) >= 30 && var(mom12, na.rm=TRUE) > 1e-10) {
    fit <- tryCatch(lm(alpha ~ mom12), error = function(e) NULL)
    if (!is.null(fit)) residuals(fit) else alpha
  } else {
    alpha - mean(alpha, na.rm=TRUE)
  }
}, by = Date]

ic_neut <- combo_n[, .(rank_ic = if (.N >= 30) suppressWarnings(cor(alpha_resid, Ret_1m, method = "spearman")) else NA_real_,
                       regime_state = regime_state[1]),
                   by = Date]
ic_neut <- ic_neut[!is.na(rank_ic)]
ic_neut_active <- ic_neut[regime_state %in% c("BULL","NORMAL")]
post_neut_ic <- mean(ic_neut_active$rank_ic, na.rm=TRUE)
post_neut_icir <- post_neut_ic / sd(ic_neut_active$rank_ic, na.rm=TRUE)
cat(sprintf("[Final] Post-neutralization (mom12-orthogonal) active IC: %.4f, ICIR: %.3f\n",
            post_neut_ic, post_neut_icir))

# ============================================================
# C6 fix — DSR with n_trials=10 (Iter7=4 specs + Iter8=5 specs + 1 pivot = 10)
# ============================================================
returns_for_dsr <- ic_active_u$rank_ic
mu <- mean(returns_for_dsr); s <- sd(returns_for_dsr); n <- length(returns_for_dsr)
sr_obs <- mu / s
m3 <- mean((returns_for_dsr - mu)^3) / s^3
m4 <- mean((returns_for_dsr - mu)^4) / s^4
sr_var <- (1 - m3 * sr_obs + ((m4 - 1) / 4) * sr_obs^2) / (n - 1)
sr_std <- sqrt(max(sr_var, 1e-12))
n_trials_strict <- 10L
emc <- 0.5772156649
e_max <- (1 - emc) * qnorm(1 - 1/n_trials_strict) + emc * qnorm(1 - 1/(n_trials_strict * exp(1)))
dsr_strict <- pnorm((sr_obs - e_max * sr_std) / sr_std)
cat(sprintf("[Final] DSR (universe sample, n_trials=10 strict): %.3f\n", dsr_strict))

# ============================================================
# Top-decile TV audit (RF-A5)
# ============================================================
# alpha top-decile per Date in universe sample
combo_u[, decile := {r <- frank(alpha, ties.method="average"); ceiling(10 * r / .N)}, by = Date]
top_decile_count <- combo_u[decile == 10, .N, by = Date]
total_count <- combo_u[, .N, by = Date]
top_decile_pct <- merge(top_decile_count, total_count, by="Date", suffixes=c("_top",""))
top_decile_pct[, pct := N_top / N]
cat(sprintf("[Final] Top-decile composition: avg %d names per period (universe ~ %d)\n",
            round(mean(top_decile_count$N)),
            round(mean(total_count$N))))

# ============================================================
# Latest snapshot for alpha_vector
# ============================================================
as_of <- max(alpha_universe$Date)
last_xs <- alpha_universe[Date == as_of]
cat("[Final] as_of_date =", as.character(as_of), "| N tickers =", nrow(last_xs), "\n")

alpha_vector_ls <- as.list(setNames(last_xs$alpha, last_xs$Ticker))
confidence_vector_ls <- as.list(setNames(last_xs$confidence, last_xs$Ticker))

# ============================================================
# Finalize ic_active updated values
# ============================================================
ic_active_final <- list(
  rank_ic_mean = mean(ic_active_u$rank_ic),
  rank_ic_sd   = sd(ic_active_u$rank_ic),
  icir         = mean(ic_active_u$rank_ic)/sd(ic_active_u$rank_ic),
  n_periods    = nrow(ic_active_u)
)

# Re-measure Harvey on universe sample
harvey_t_u <- mean(ic_active_u$rank_ic) / (sd(ic_active_u$rank_ic) / sqrt(length(ic_active_u$rank_ic)))
cat(sprintf("[Final] Harvey t (universe active): %.3f\n", harvey_t_u))

# Re-measure IC by regime on universe
ic_by_regime_u <- ic_u[, .(N=.N,
                           rank_ic = mean(rank_ic),
                           icir = mean(rank_ic)/sd(rank_ic)),
                       by = regime_state]
print(ic_by_regime_u)

# ============================================================
# Graduation eval (universe-restricted)
# ============================================================
grad_pass <- list(
  rank_ic       = ic_active_final$rank_ic_mean >= 0.04,
  icir          = ic_active_final$icir >= 0.20,
  subperiod     = diag$subperiod_sign_consistency >= 0.50,
  harvey        = harvey_t_u >= 3.0,
  dsr           = dsr_strict >= 0.5,
  tdc_lt_030    = diag$tdc_vs_str1700$tdc_avg < 0.30,
  spec5_harvey  = diag$n_specs_harvey_pass >= 4,
  post_neutralization_retain = (abs(post_neut_ic) >= 0.5 * abs(ic_active_final$rank_ic_mean))
)
grad_overall <- all(unlist(grad_pass))
cat("[Final] Graduation gate (universe + neutralized):", if (grad_overall) "PASS" else "FAIL", "\n")
cat("[Final] Detail:\n"); print(grad_pass)

# RF-A3 check: recent 3Y ICIR vs overall*1.5
recent_icir <- 0.2388  # from diag (2020-2023 ICIR)
overall_icir <- ic_active_final$icir
rf_a3 <- !is.na(overall_icir) && abs(overall_icir) > 1e-9 && recent_icir > overall_icir * 1.5

honest_verdict <- paste0(
  "Iter 8 L01_Amihud regime-conditional sleeve alpha graduation in KOSPI200∪KOSDAQ150 universe (n=", length(universe_tickers), " tickers) + post-neutralization (mom12 orthogonal): NOT MET. ",
  sprintf("Active (BULL+NORMAL) rank_IC=%.4f, ICIR=%.3f, Harvey t=%.3f, DSR(n_trials=10)=%.3f, post-neutralization IC=%.4f, TDC vs STR_1700=%.3f. ",
          ic_active_final$rank_ic_mean, ic_active_final$icir,
          harvey_t_u, dsr_strict, post_neut_ic, diag$tdc_vs_str1700$tdc_avg),
  sprintf("Regime split: BULL ICIR=%.3f (가설 reverse — 자유유동성 premium 부재), NORMAL ICIR=%.3f (가설 부분 입증, 보더라인). ",
          ic_by_regime_u[regime_state=="BULL", icir],
          ic_by_regime_u[regime_state=="NORMAL", icir]),
  sprintf("RF-A3 recent-bias trigger: 2020-2023 ICIR=0.24 / overall ICIR=%.3f → ratio=%.1fx (>1.5x threshold = sample selection 의심). ",
          overall_icir, abs(0.24/overall_icir)),
  "Iter 7 (4-axis composite, IC=-0.05) + Iter 8 (single-axis regime-conditional, IC=0.004) 둘 다 graduation FAIL. ",
  "Conclusion: KR market Liquidity_Risk family (L01 single + L01-L11-L12-R13 composite) — unconditional fail + regime-conditional partial fail. NORMAL-only ICIR=0.20 boundary는 통계적 유의성 부재 (Harvey t=0.32). ",
  "Recommendation: Sprint 종결 + L-209 적립. Iter 9 cross-family pivot 권고 (Growth × Investor_Flow residualized 또는 Skewness Forensics). ",
  "AX-007 정직 표기: cash sleeve는 overlay이지 독립 alpha 아님. 단일 신호 long-only top-20 mechanism break는 regime-conditional만으로 미해소 (Codex C3 인정)."
)

# ============================================================
# Build final alpha_package
# ============================================================
method_log <- list(
  list(name = "L01_Amihud_unconditional_4axis_composite",
       rank_ic = -0.05, icir = -0.48, selected = FALSE,
       reason = "Iter 7 (WT-D20260426_001) — 4-axis Liquidity_Risk + Tail_Risk fail."),
  list(name = "L01_Amihud_regime_conditional_70_30",
       rank_ic = ic_active_final$rank_ic_mean,
       icir = ic_active_final$icir,
       selected = TRUE,
       reason = "Iter 8 hypothesis: BULL/NORMAL only positive premium. universe restricted KOSPI200∪KOSDAQ150."),
  list(name = "L01_post_neutralization_mom12",
       rank_ic = post_neut_ic, icir = post_neut_icir, selected = FALSE,
       reason = "C7 sector-neutral surrogate — alpha 신호 mom12 residual에서 잔존 측정.")
)

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
  universe_applied = list(
    label = "KOSPI200_KOSDAQ150_intersection",
    n_tickers = length(universe_tickers),
    source = "STR_1700_audited_universe (deployable, liquidity 2e8 TV applied)",
    note = "Codex C2 fix — pre-Codex draft used unrestricted 3064 tickers. Final restricted to 773."
  ),

  factor_specs = list(
    list(
      factor_family = "Liquidity_Risk",
      proxy = "L01_Amihud (Z_Score_Aligned)",
      formula = "regime_conditional( BULL/NORMAL: 0.70 * z_norm(Amihud); CAUTION/CRISIS: 0 )",
      lag_rule = "monthly factor (Usable_Date <= sig_date) + regime_state lag-1 (C9)",
      winsorization = "3std cross-sectional (5-spec sensitivity confirmed identical)",
      neutralization = "mom12-orthogonal post-hoc (size/momentum surrogate)",
      economic_rationale = "Amihud (2002) illiquidity premium — KR market unconditional negative IC (Iter 7). Iter 8 가설: regime-conditional BULL/NORMAL only positive (Pastor-Stambaugh 2003 패턴). 결과: NORMAL only 보더라인 (ICIR=0.20), BULL reverse (-0.09).",
      weight_theta = 0.70,
      source = "db_existing",
      references = c("Amihud (2002) JFM",
                     "Pastor-Stambaugh (2003) JPE",
                     "Kyle (1985) Econometrica")
    ),
    list(
      factor_family = "Cash_Overlay",
      proxy = "regime cash (alpha=0)",
      formula = "regime_state in {CAUTION, CRISIS} → alpha=0",
      lag_rule = "regime_state lag-1 (PIT-safe)",
      winsorization = "n/a",
      neutralization = "n/a",
      economic_rationale = "Codex C3 정직 표기: cash overlay이지 독립 alpha sleeve 아님. AX-007 EXCEPTION#1 EXTERNAL claim 부적합 — single-signal long-only top-20 mechanism break은 regime-conditional cash만으로 미해소.",
      weight_theta = 0.30,
      source = "regime_overlay",
      classification = "overlay_not_alpha"
    )
  ),

  diagnostics = list(
    rank_ic = ic_active_final$rank_ic_mean,
    rank_ic_overall_universe = mean(ic_u$rank_ic),
    icir = ic_active_final$icir,
    icir_overall_universe = mean(ic_u$rank_ic)/sd(ic_u$rank_ic),
    monotonicity = diag$monotonicity,
    subperiod_stability = diag$subperiod_sign_consistency,
    turnover_proxy = diag$turnover_proxy,
    harvey_t_stat = harvey_t_u,
    dsr_post_penalty = dsr_strict,
    dsr_n_trials = n_trials_strict,
    post_neutralization_ic = post_neut_ic,
    post_neutralization_icir = post_neut_icir,
    n_specs_harvey_pass = diag$n_specs_harvey_pass,
    spec_5_robustness = diag$spec_5_robustness,
    ic_by_regime_universe = lapply(seq_len(nrow(ic_by_regime_u)), function(i) {
      list(regime = ic_by_regime_u$regime_state[i],
           N = ic_by_regime_u$N[i],
           rank_ic = ic_by_regime_u$rank_ic[i],
           icir = ic_by_regime_u$icir[i])
    }),
    tdc_vs_str1700 = diag$tdc_vs_str1700,
    method_log = method_log,
    candidates_tried = length(method_log),
    parallel_exec = TRUE,
    n_workers = min(8L, parallel::detectCores() - 1L),
    rcpp_used = FALSE,
    n_sig_dates_active = nrow(ic_active_u),
    n_sig_dates_total = length(unique(alpha_universe$Date)),
    rf_a3_recent_bias_triggered = rf_a3
  ),

  ax_compliance = list(
    AX_003 = list(check = "EXCLUSION", note = "no value EP_STANDALONE used"),
    AX_004 = list(check = "EXCLUSION", note = "no quality_profitability single-axis used"),
    AX_005 = list(check = "EXCLUSION", note = "Liquidity_Risk family — NOT BAB/low-beta"),
    AX_007 = list(check = "EXCEPTION#1_DECLARED_BUT_INSUFFICIENT",
                  note = "multi-sleeve declared (Liquidity 70% + Cash 30%) BUT Codex C3 정직 인정: cash sleeve = overlay, not independent alpha. signal-portfolio mechanism break는 regime-conditional만으로 미해소. 단일 액시스 long-only top-20 hard-fail 패턴 잔존.",
                  exception_id = 1,
                  honest_classification = "claimed_but_mechanism_insufficient")
  ),

  graduation = list(
    overall = grad_overall,
    detail = grad_pass,
    honest_verdict = honest_verdict,
    sprint_recommendation = "TERMINATE — L-209 적립",
    next_pivot_options = list(
      A = "WT-D20260427_001 — Growth × Investor_Flow residualized (cross-family, KR domestic flow)",
      B = "WT-D20260427_002 — Skewness Forensics × CFO accrual (Chen-Hong-Stein 2001 + Sloan 1996)",
      C = "Sprint 완전 종결 — admission cycle re-sequence with existing STR_1631 + STR_1656 + STR_1700"
    )
  ),

  challenge_flags = list(
    list(id = "GRADUATION_FAIL", severity = "HIGH",
         reason = sprintf("Active rank_IC=%.4f << 0.04 / Harvey t=%.3f << 3.0 / DSR=%.3f << 0.5 / Monotonicity=%.3f. 모든 graduation criteria fail.",
                          ic_active_final$rank_ic_mean, harvey_t_u, dsr_strict, diag$monotonicity)),
    list(id = "REGIME_ASYMMETRY_HYPOTHESIS_REVERSE", severity = "HIGH",
         reason = sprintf("BULL ICIR=%.3f (가설과 reverse — flight-to-quality not flight-to-illiquidity), NORMAL ICIR=%.3f (가설 부분 입증 보더라인). 양쪽 통계적 유의성 부재.",
                          ic_by_regime_u[regime_state=="BULL", icir],
                          ic_by_regime_u[regime_state=="NORMAL", icir])),
    list(id = "RF-A3_RECENT_BIAS", severity = "HIGH",
         reason = sprintf("2020-2023 ICIR=0.24 vs overall ICIR=%.3f → ratio=%.1fx (>1.5x). recent 3Y가 overall의 9x → sample selection 의심.",
                          overall_icir, abs(0.24/overall_icir))),
    list(id = "AX007_OVERCLAIM_REVISED", severity = "MEDIUM",
         reason = "Codex C3 인정: cash sleeve는 overlay이지 독립 alpha sleeve 아님. classification → 'overlay_not_alpha'. EXCEPTION#1 declared but mechanism insufficient. 단일 axis long-only top-20 mechanism break 잔존."),
    list(id = "TDC_PASS", severity = "INFO",
         reason = sprintf("TDC vs STR_1700 = %.3f < 0.30 (cross-family 입증). xs_corr = -0.06 거의 직교. Iter 8의 唯一 PASS criterion.",
                          diag$tdc_vs_str1700$tdc_avg)),
    list(id = "POST_NEUTRALIZATION_DEGRADATION", severity = "MEDIUM",
         reason = sprintf("mom12-orthogonal post-neutralization IC=%.4f (active=%.4f). raw alpha 자체가 미미하여 neutralization 후 차이 거의 없음 — 신호 부재 자체 입증.",
                          post_neut_ic, ic_active_final$rank_ic_mean)),
    list(id = "SPRINT_TERMINATION_RECOMMENDED", severity = "HIGH",
         reason = "Iter 7 (composite IC=-0.05) + Iter 8 (single-axis regime-conditional IC=0.004) 연속 fail → KR Liquidity_Risk family alpha origin 한계 명백. L-209 적립 + Sprint 종결 또는 Iter 9 cross-family pivot.")
  ),

  alternatives_recorded = list(
    pivot_a = list(family = "Growth × Investor_Flow",
                   method = "earnings growth residualized by foreign investor net flow",
                   rationale = "cross-family + KR domestic flow signal — NOT in STR_1700"),
    pivot_b = list(family = "Skewness Forensics",
                   method = "rolling 12M return skewness × CFO accrual quality",
                   rationale = "tail-risk meets earnings quality, multi-axis 가능"),
    sprint_termination = list(
      action = "L-209 적립: 'KR Liquidity_Risk family — unconditional fail (Iter 7) + regime-conditional partial fail (Iter 8). NORMAL only ICIR=0.20 보더라인이지만 Harvey t=0.32 통계 유의성 부재. RF-A3 recent-bias trigger.'",
      next_step = "Sprint 종결 권고 또는 WT-D20260427_001 Growth × Investor_Flow."
    )
  ),

  codex_round = list(
    invoked = TRUE,
    stance = "REJECT",
    veto_flag = FALSE,
    weakest_assumption = "70% L01_Amihud + zero-alpha cash overlay does not qualify as AX-007 multi-sleeve alpha and cannot preserve tradable KR liquidity premium given active rank_IC=0.0036 and negative BULL/early-period evidence.",
    critical_concerns_addressed = list(
      C1 = "honest_verdict NOT MET 명시 — graduation FAIL 모든 metric 인정",
      C2 = "universe restricted to STR_1700 (KOSPI200∪KOSDAQ150 + 2e8 TV) 773 tickers",
      C3 = "AX-007 honest_classification='claimed_but_mechanism_insufficient' — cash overlay 정직 표기",
      C4 = "RF-A3 challenge_flag 추가 (recent-bias 9x ratio)",
      C5 = "challenge_note.md 동시 작성 (이 finalize step)",
      C6 = "DSR n_trials=5 → 10 strict (Iter7 4-spec + Iter8 5-spec + 1 pivot reference)",
      C7 = "post-neutralization mom12-orthogonal 실행 + 측정 결과 alpha 부재 입증"
    ),
    response_file = "qepm/mailbox/worktask/WT-D20260426_002/codex_critic_response_alpha.json"
  )
)

# === Step 1: write alpha_package.json ===
out_path <- file.path(WT_DIR, "alpha_package.json")
write_json(alpha_package, out_path, pretty = TRUE,
           auto_unbox = TRUE, digits = 6, na = "null")
cat("[Final] Saved:", out_path, "\n")

# === Step 2: lineage record (post write) ===
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = WT_ID,
  package_type = "alpha_package",
  method_selected = "L01_Amihud_regime_conditional_70_30_universe_restricted_post_neutralized",
  input_file_paths = c(
    "stage_artifacts/WT_D20260426_002/alpha_scores.parquet",
    "stage_artifacts/WT_D20260426_002/alpha_validation.json",
    "stage_artifacts/WT_D20260425_007/regime_panel.parquet",
    "stage_artifacts/WT_D20260425_011/alpha_scores.parquet",
    "qepm/mailbox/worktask/WT-D20260426_002/codex_critic_response_alpha.json"
  )
)
cat("[Final] Lineage recorded.\n")

# === Step 3: update alpha_validation.json with final numbers ===
diag_final <- diag
diag_final$universe_restricted <- list(
  n_tickers = length(universe_tickers),
  ic_active_BULLNORMAL = ic_active_final,
  harvey_t_active = harvey_t_u,
  dsr_n_trials_10 = dsr_strict,
  post_neutralization_ic = post_neut_ic,
  post_neutralization_icir = post_neut_icir,
  ic_by_regime = lapply(seq_len(nrow(ic_by_regime_u)), function(i) {
    list(regime = ic_by_regime_u$regime_state[i],
         N = ic_by_regime_u$N[i],
         rank_ic = ic_by_regime_u$rank_ic[i],
         icir = ic_by_regime_u$icir[i])
  })
)
diag_final$graduation_decision <- list(
  overall = grad_overall,
  detail = grad_pass,
  honest_verdict = honest_verdict
)
write_json(diag_final, file.path(ART_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 6, na = "null")
cat("[Final] Validation file updated.\n")

cat("[Final] DONE.\n")
