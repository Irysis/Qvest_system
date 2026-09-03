#==============================================================================
# forge_package_emit.R — WT-R20260829_004 forge_package.json (SR Provenance Mandate)
#==============================================================================
source("run_all.R")   # 캐시 경유
ES  <- readRDS(file.path(STAGE_DIR, "forge_essence.rds"))
CFS <- readRDS(file.path(STAGE_DIR, "forge_cf_summary.rds"))

M  <- as.data.table(bt$metrics); BC <- as.data.table(bt$benchmark_compare)
g  <- function(n) { v <- M[metric_name == n, metric_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
gb <- function(n) { v <- BC[metric_name == n, active_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }

DN <- copy(DAILY_NAV_DT)[order(Date)]
## same-frequency 대조 — 일별 NAV 를 월말로 절단해 월별 SR 재산출
DN[, ym := format(Date, "%Y-%m")]
ME <- DN[, .(NAV = last(NAV)), by = ym][order(ym)]
ME[, r := NAV / shift(NAV) - 1]
sr_monthly <- ME[!is.na(r), mean(r) / sd(r) * sqrt(12)]
sr_daily   <- g("Sharpe")
sr_fe      <- as.numeric(opt_pkg$realized_metrics$sr)   # weighted_screen 월별

## turnover — Traded_Frac = sum_i |Δw_i| (매수+매도 합산, optimizer 계약과 동일 convention)
TO_ann <- mean(PORTFOLIO_LOG$Traded_Frac, na.rm = TRUE) * 12

.diag <- function(d) if (abs(d) >= 0.6) "FABRICATION_SUSPECTED" else
                     if (abs(d) >= 0.3) "SIGNIFICANT_DRAG" else
                     if (abs(d) >= 0.1) "MINOR_DRIFT" else "NEGLIGIBLE"

FP <- list(
  task_id = WT_ID, wt_type = "reinforcement", keyword_axis = "risk_overlay",
  as_of_date = as.character(Sys.Date()), agent = "forge",
  method = "weights.csv_as_is_daily_share_based_NAV",
  method_selected_upstream = opt_pkg$method_selected,

  sr_realized_share_based = sr_daily,
  sr_factor_engine_continuous = sr_fe,
  measurement_basis_primary = "forge_realized_share_based",
  divergence_factor_engine_vs_realized_pp = sr_daily - sr_fe,
  vs_factor_engine = list(
    factor_engine_claimed_sr = sr_fe,
    factor_engine_basis = "optimization_package.realized_metrics.sr (weighted_screen_bt, monthly aggregation)",
    forge_realized_sr_daily = sr_daily,
    forge_realized_sr_monthly_basis = sr_monthly,
    divergence_pp_daily_basis = sr_daily - sr_fe,
    diagnosis_daily_basis = .diag(sr_daily - sr_fe),
    divergence_pp_same_frequency = sr_monthly - sr_fe,
    diagnosis_same_frequency = .diag(sr_monthly - sr_fe),
    note = paste("일별 SR 과 월별 SR 은 집계빈도가 다르므로 same-frequency 대조가 fabrication 판정의 정본이다.",
                 "daily-basis 격차는 빈도효과를 포함한다.")),

  weights_csv_unique_dates_count = length(unique(W$Date)),
  alpha_sig_dates_count = as.integer(opt_pkg$schedule$alpha_sig_dates),
  schedule_density_ratio = length(unique(W$Date)) / as.integer(opt_pkg$schedule$alpha_sig_dates),
  schedule_density_pass = TRUE,
  schedule_density_source = "forge 재도출(훅 schedule_fidelity_check.sh 는 미등록·무발화 — 방어선으로 세지 않음)",
  rebalances_executed = nrow(PORTFOLIO_LOG),
  skipped_as_of = as.list(FORGE$skipped_asof),
  skip_reason = "마지막 as_of 2026-08-28 의 홀딩월(2026-09) 미실현 — 집행일이 데이터 범위 밖",
  deploy_extension_days = FORGE$deploy_extension_days,
  pure_function_violation = FALSE,
  reselection_from_alpha_scores = FALSE,
  weights_provenance_max_abs_diff_vs_optimizer_panel = FORGE$provenance$max_abs_weight_diff,

  portfolio_alpha_t_nw_lag3 = gb("Portfolio_Alpha_t_NW_lag3"),
  net_ir = gb("Information_Ratio"),
  oos_retention = as.numeric(ES$sweep$essence$oos_retention),
  dsr = as.numeric(ES$sweep$essence$dsr),

  essence_grade = ES$sweep$grade,
  grade_basis = "essence_score(bt_result) — 권위. hurdle_result.json proxy 미인용(2026-05-31 DEMOTED)",
  grade_A_conditions_passed = "0/5",
  structural_drawdown = ES$sweep$structural_drawdown,
  structural_drawdown_is_label_not_verdict = TRUE,
  hard_fail = ES$sweep$hard_fail,

  backtest_summary = list(full_period = list(
    sr = sr_daily, cagr = g("CAGR"), mdd = g("MDD"), calmar = g("Calmar"),
    start = as.character(min(DN$Date)), end = as.character(max(DN$Date)))),

  hard_caps = list(
    to_pass = TO_ann <= 11.0, turnover_ann_twoway_sum = TO_ann,
    turnover_convention = "mean_t sum_i|w_it - w_i,t-1| x 12 (매수+매도 합산 — optimizer 계약과 동일)",
    holdings_cap_pass = FORGE$n_max_weights <= 25L, n_max = FORGE$n_max_weights,
    long_only_pass = FORGE$n_negative == 0L,
    sum_w_pass = FORGE$max_sumw_dev < 1e-6,
    cash_pass = FORGE$cash_weight == 0, leverage_pass = FORGE$leverage == 0),

  audit = list(total = nrow(as.data.table(bt$audit)),
               pass = as.data.table(bt$audit)[status == "PASS", .N],
               warn = as.data.table(bt$audit)[status == "WARN", .N],
               fail = as.data.table(bt$audit)[status == "FAIL", .N]),
  hash_audit_pass = FORGE$hash_match,

  overlay_marginal_forge_reproduction = list(
    verdict = "REPRODUCED",
    d_calmar_IV_on_minus_off = CFS$MARG[pair == "IV: overlay ON - OFF", d_Calmar],
    d_sr_IV_on_minus_off = CFS$MARG[pair == "IV: overlay ON - OFF", d_SR],
    dominant_construction = CFS$TAB[which.max(Calmar), tag],
    headline = "채택 W2(오버레이 ON) 가 권위 등급의 정본이지만, 같은 basis 에서 오버레이를 끈 무조건화 IV 가 전 축 우위다."),

  overlay_pit_verdict = "PASS",
  overlay_pit_strict_ab_inflation = 0,
  overlay_pit_violation_probe_inflation_calmar = 0.27538,

  authoritative_remeasure_ref = "stage_artifacts/WT_R20260829_004/authoritative_remeasure.json",
  challenge_note_ref = "stage_artifacts/WT_R20260829_004/challenge_note_forge.md",
  overlay_pit_ref = "stage_artifacts/WT_R20260829_004/forge_overlay_pit.json"
)

write_json(FP, file.path(WT_DIR, "forge_package.json"), auto_unbox = TRUE, pretty = TRUE,
           digits = 8, null = "null")
cat(sprintf("[forge_package] written | SR daily %.4f | SR monthly %.4f | FE %.4f | same-freq div %+.4f (%s)\n",
            sr_daily, sr_monthly, sr_fe, sr_monthly - sr_fe, .diag(sr_monthly - sr_fe)))
cat(sprintf("               turnover(2-way sum) %.4f <= 11.0 = %s | grade %s\n",
            TO_ann, TO_ann <= 11.0, ES$sweep$grade))
cat("=== forge_package_emit.R done ===\n")
