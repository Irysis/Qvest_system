## run_09_finalize.R — alpha_vector / confidence / alpha_validation.json 산출 + lineage 기록
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setDTthreads(2); QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
TD <- "stage_artifacts/WT_D20260802_002"
MB <- "qepm/mailbox/worktask/WT-D20260802_002"

## ★ 대상 파일을 read 하지 않는다 — Windows arrow mmap 이 열려 있으면 같은 경로 write 가
##   IOError 1224 로 실패한다(실측). run_04 와 동일 레시피로 원천에서 재구성한다.
SI0 <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
.liq <- as.data.table(SI0$liqf); .fwd <- as.data.table(SI0$fwd_ret)
A <- as.data.table(read_parquet(file.path(TD, "gate_panel.parquet"))); A[, Date := as.Date(Date)]
A <- merge(A, .liq[, .(Date, Ticker, adv2 = adv)], by = c("Date", "Ticker"), all.x = TRUE)
A <- A[is.na(adv2) | adv2 >= 2e8][is.finite(score) & is.finite(fa_share_l0)]; A[, adv2 := NULL]
A <- merge(A, .fwd[, .(Date, Ticker, Ret_1m_f = Ret_1m)], by = c("Date", "Ticker"), all.x = TRUE)
if ("Ret_1m" %in% names(A)) A[, Ret_1m := NULL]
setnames(A, "Ret_1m_f", "Ret_1m")
A[, gate := frank(-fa_share_l0, ties.method = "first") <= ceiling(.N / 2), by = Date]
setnames(A, "score", "alpha_score_base")
A <- A[, .(Date, Ticker, alpha_score_base, fa_share_l0, fa_share_l1, gate, adv, Size, Ret_1m)]
AR <- readRDS(file.path(TD, "arms_results.rds")); DG <- readRDS(file.path(TD, "diagnostics.rds"))
AD <- readRDS(file.path(TD, "adversarial.rds")); AT <- readRDS(file.path(TD, "ast_run.rds"))
GB <- readRDS(file.path(TD, "gate_build_diag.rds"))

## confidence: 0.5*커버리지(스코어 유한=1) + 0.3*순위안정성(1-|Δpctile|) + 0.2*유동성 충족
setorder(A, Ticker, Date)
A[, pct := frank(alpha_score_base, ties.method = "first") / .N, by = Date]
A[, pct_prev := shift(pct), by = Ticker]
A[, rank_stab := fifelse(is.na(pct_prev), 0.5, 1 - abs(pct - pct_prev))]
A[, liq_ok := as.numeric(is.finite(adv) & adv >= 2e8)]
A[, conf := pmin(1, pmax(0, 0.5 * 1 + 0.3 * rank_stab + 0.2 * liq_ok))]
A[, c("pct_prev") := NULL]
write_parquet(A, file.path(TD, "alpha_scores.parquet"))

d_last <- max(A$Date)
cs <- A[Date == d_last][order(-alpha_score_base)]
av <- list(
  as_of_sig_date = as.character(d_last),
  basis = "score_eff (STR_1715 core, cleanT1 production_parity_verified) — 본 라운드 미가공 상속",
  n_names = nrow(cs),
  gate_pass_n = sum(cs$gate),
  alpha_vector = setNames(as.list(round(cs$alpha_score_base, 6)), cs$Ticker),
  confidence_vector = setNames(as.list(round(cs$conf, 4)), cs$Ticker),
  gate_flag = setNames(as.list(cs$gate), cs$Ticker),
  units = "cross-sectional composite z (기대초과수익 순서통계 — 수익률 단위 아님)",
  downstream_note = "verdict = config-scoped negative. 게이트 미적용판이 base 이며 downstream 소비 권고 없음."
)
write_json(av, file.path(TD, "alpha_vector_2026_04_30.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat(sprintf("[alpha_vector] %s  n=%d  gate_pass=%d\n", d_last, nrow(cs), sum(cs$gate)))

sm <- AR$summ
gv <- function(a, b) sm[arm == a & basis == b, port_t]
VAL <- list(
  task_id = "WT-D20260802_002", fq_id = "FQ-084",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  metric_type = "canonical_screen",
  instrument = "02_Infrastructure/contracts/canonical_screen_bt.R::canonical_screen_bt (top_n=25, 15bps, liq 2e8)",
  window = list(n_months = 268L, from = "2004-01", to = "2026-04",
                selection_type = "chain", n_trials = 1L, is_only_selection = TRUE,
                holdout_consumed = FALSE),
  preregistration = "stage_artifacts/WT_D20260802_002/preregistration.json",
  primary_result = list(
    A_base_capw = gv("A_base", "capw"), B_gate_capw = gv("B_gate", "capw"),
    A_base_ewuni = gv("A_base", "ewuni"), B_gate_ewuni = gv("B_gate", "ewuni"),
    prereg_necessary_criterion = "B_gate > A_base",
    prereg_outcome = "FAILED_IN_REVERSE_DIRECTION",
    dual_basis_agreement = TRUE),
  full_arms = sm,
  paired_vs_base = AR$paired,
  placebo = list(n_draws = 20L, mean = mean(AR$placebo), sd = sd(AR$placebo),
                 min = AD$placebo_min, n_at_or_below_gate = AD$placebo_rank_below,
                 onesided_p = AD$placebo_onesided_p),
  cap_tier = AR$cap_tier,
  advisory_battery = list(
    A_base = DG$batt_all[c("rank_ic","icir","ic_nw_t","monotonicity","subperiod_stability",
                           "post_neutralization_ic","post_neut_retention","n_months")],
    B_gate = DG$batt_gate[c("rank_ic","icir","ic_nw_t","monotonicity","subperiod_stability",
                            "post_neutralization_ic","post_neut_retention","n_months")]),
  mechanism_diagnostics = list(
    ic_by_fa_quartile = DG$by_fa_quartile,
    top25_gate_pass_rate = DG$top25_pass,
    top25_pass_minus_drop_monthly = DG$top25_diff_mo,
    top25_pass_minus_drop_nw_t = DG$top25_diff_t,
    fa_share_standalone_rank_ic = DG$fa_ic, fa_share_standalone_ic_nw_t = DG$fa_ic_t),
  adversarial = list(
    C1_denominator_convention = list(
      concern = "Close(수정주가) x Vol(원거래량) 혼용 → 분할 종목 분모 왜곡",
      test = "fa_share 를 adv 에 대해 횡단 잔차화한 게이트 재측정",
      result_port_t = AD$pt_resid_adv, verdict = "CONCERN_PARTIALLY_VALID_CONCLUSION_UNCHANGED"),
    C2_construct_validity = list(
      concern = "|net| 은 '참여'가 아니라 '순불균형' — 참여 지표로서 구성타당도 결함",
      test = "fa_breadth(외국인 순매수 비영(非零) 거래일 비율) 분포 실측",
      breadth_saturation_at_1 = AD$breadth_sat,
      verdict = "ACCEPTED_PREMISE_VOID",
      detail = "배포 유니버스(K200∪KQ150 ∩ liq 2e8)에서 breadth 가 94.3% 종목-월에서 1.000 — 외국인이 사실상 모든 종목을 매일 거래한다. '외국인 활동이 희박한 종목'이라는 가설 전제가 이 유니버스에 존재하지 않는다."),
    C3_placebo_rank = list(concern = "음성 결과가 우연 아닌가",
      result = sprintf("B_gate(%.3f) < placebo 20 draw 전부(min %.3f), 단측 p <= %.3f",
                       gv("B_gate","capw"), AD$placebo_min, AD$placebo_onesided_p),
      verdict = "HARM_CONFIRMED"),
    C7_size_confound = list(
      concern = "★ IC 사분위 단조 기울기가 cap-tier(size) 효과의 재표현 아닌가",
      test = "size 5분위 x 외국인활동 반분 이중정렬, 월별 (저활동−고활동) IC gap NW t",
      gap_mean = AD$gap_mean, gap_nw_t = AD$gap_nw_t, gap_months = AD$gap_months,
      gap_by_size_quintile = AD$gap_by_size,
      verdict = "ACCEPTED_MECHANISM_CLAIM_DOWNGRADED",
      detail = "size 통제 후 gap NW t = 1.11 (비유의) 이고 최소 size 분위에서는 부호 역전. 원시 사분위 기울기의 상당분은 size 효과. 포트 수준 손해(E_gate_sizeneut 2.425 < placebo min 2.488)는 견고하나, 그 손해의 *설명*으로 내세운 'IC 국소화'는 기각 — 기전 귀속 미해결.")
  ),
  pit_checks = list(
    file_vintage = GB$vintage, file_vintage_consistent = GB$vintage_ok,
    gate_var_vs_adv_spearman = GB$cor_fa_adv, gate_var_vs_size_spearman = GB$cor_fa_size,
    coverage = GB$coverage_l0,
    lag1_stress_port_t = gv("B_gate_lag1", "capw"),
    lag1_note = "1개월 추가 지연판 2.725 — 원판 2.198 보다 오히려 나음. 양성 결과가 없으므로 동월 누출 부풀림 대상 자체가 없음."),
  ast = list(
    compiler_features = AT$features, operator_counts = AT$op_counts,
    compiler_vs_handbuilt = AT$verify,
    ast_path_port_t = list(A_base = AT$ast_port_t_base, B_gate = AT$ast_port_t_gate),
    verify_verdict_file = "stage_artifacts/WT_D20260802_002/ast_verify_verdict.json"),
  verdict = "CONFIG_SCOPED_NEGATIVE",
  verdict_detail = "사전등록 가설 반증. 게이트는 개선이 아니라 통계적으로 유의한 손해이며, 유동성/사이즈 대조군·무작위 축소 귀무분포와 모두 구분된다. 전제(외국인 희박 종목의 존재)가 배포 유니버스에서 성립하지 않는다는 것이 가장 중요한 실측.",
  graduation_claim = "NONE — canonical screening 실측이며 forge-authoritative 값이 아니다. HARD 3종 판정 대상 아님."
)
write_json(VAL, file.path(TD, "alpha_validation.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
cat("[SAVED] alpha_validation.json\n")

## lineage (alpha_package.json write 이후 호출 — L-194 순서 규약 준수)
ok <- tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = "WT-D20260802_002", package_type = "alpha_package",
    method_selected = "universe conditioning gate (FA_share_3m top-50%) on inherited STR_1715 core score — prereg chain, n_trials=1",
    input_file_paths = c(
      "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet",
      "stage_artifacts/WT_D20260714_004/screen_inputs.rds",
      ".cache/investor_stock/investor_wide.parquet",
      ".cache/rawdata.parquet"))
  TRUE
}, error = function(e) { cat("[lineage] 실패:", conditionMessage(e), "\n"); FALSE })
cat(sprintf("[lineage] recorded=%s\n", ok))
cat("[DONE]\n")
