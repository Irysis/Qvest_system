## s6_emit.R — WT-D20260813_003 산출 발행
##  (a) stage_artifacts/WT_D20260813_003/alpha_scores.parquet  = 노출 스케줄 신호 패널
##  (b) stage_artifacts/WT_D20260813_003/alpha_validation.json = 검증 배터리 통합
##  (c) qepm/mailbox/worktask/WT-D20260813_003/alpha_package.json = AST v1.1 3층
##  (d) record_package_lineage  ← ★반드시 (c) 이후 (L-194)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260813_003")
MBX <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260813_003")

HY <- fromJSON(file.path(MBX, "alpha_hypothesis.json"), simplifyVector = FALSE)
PR <- fromJSON(file.path(OUT, "prereg_VT.json"))
V2 <- fromJSON(file.path(OUT, "vt_result.json"))
V3 <- fromJSON(file.path(OUT, "vt_final.json"))
V4 <- fromJSON(file.path(OUT, "vt_scope.json"))
V5 <- fromJSON(file.path(OUT, "vt_rf_sensitivity.json"))
EV <- as.data.table(readRDS(file.path(OUT, "vt_panel.rds"))); setorder(EV, hold_start)

## ── (a) 신호 패널 ───────────────────────────────────────────────────────────
SP <- EV[, .(ym, hold_start, signal_cutoff = hold_start,
             sigma_hat_daily = sigma_d, sigma_hat_monthly = sigma_m, sigma_star,
             exposure_e = e, bind = e < 1 - 1e-12, at_floor = e <= 0.5 + 1e-12,
             bm_ret_holding_month = r, realized_vol_in_month = realized_vol)]
SP[, `:=`(panel_type = "time_series_market_exposure_schedule",
          metric_type = "mechanism_observation",
          cutoff_rule = "Date < first-day-of-holding-month (C5)",
          mapping = "e = clip(sigma_star / sigma_hat, 0.50, 1.00)")]
write_parquet(SP, file.path(OUT, "alpha_scores.parquet"))
cat(sprintf("[emit] alpha_scores.parquet  rows=%d cols=%d\n", nrow(SP), ncol(SP)))

## ── (b) alpha_validation.json ───────────────────────────────────────────────
val <- list(
  wt_id = "WT-D20260813_003", as_of_date = "2026-08-13",
  metric_type = "mechanism_observation",
  prereg = "stage_artifacts/WT_D20260813_003/prereg_VT.json",
  judgment_order = "VT1(record) -> VT2(1차) -> VT2b(결정 관문) -> VT3(무효조건) -> VT4(성과, 미착수)",
  verdict = V3$verdict, vt4_authorized = V3$vt4_authorized,
  n_months = V2$n_months, window = V2$window,
  inheritance = list(
    signal_panel = "stage_artifacts/WT_D20260813_002/alpha_scores.parquet",
    VOL_parity_spearman = PR$panel$inheritance_parity$spearman,
    VOL_parity_max_abs_diff = PR$panel$inheritance_parity$max_abs_diff,
    return_parity_max_abs_diff = V3$parity_inherited_returns$max_abs_diff,
    note = "매핑이 level 을 요구해 raw sigma_hat 을 동일 컷오프로 재산출. 승계 VOL(expanding-z)과 완전 일치(max|diff|=0) — 재구축이지 재설계 아님."),
  VT1 = V2$VT1, VT2 = V2$VT2, VT2b = V3$VT2b_final, VT3 = V2$VT3,
  VT3_relabel = V3$VT3c_relabel,
  era_decomposition = V3$era_decomposition,
  mechanism_segments = V3$mechanism_segments,
  bind_vs_clip = V3$bind_vs_clip,
  scope = V4, rf_sensitivity = V5,
  adversarial = tryCatch(fromJSON(file.path(OUT, "adversarial_numbers.json")), error = function(e) NULL),
  reject_scope_limit = "본 라운드가 닫는 범위 = **연속 비율 매핑(continuous ratio scaling) 형태**의 vol-target 노출 소비. 문턱형(expanding-percentile step)은 미검 — 두 형태가 선별하는 달이 실제로 다름을 실측(challenge_flags '매핑 형태' 항목). INV-7: '분산 예측기는 어디서도 안 통한다' 로 확대 금지.",
  subperiod_descriptive = V2$subperiod_descriptive,
  self_caught = V3$self_caught,
  universe_comparison = list(
    applicable = FALSE,
    reason = "본 라운드는 종목-횡단면 알파가 아니라 시장-레벨 노출 스케줄이다. 유니버스(KR_top342 vs KR_TOP500_FREEFLOAT)는 벤치 시계열과 무관하므로 v2 비교 mandate(L-227 ICIR attenuation 진단) 조건에 해당하지 않는다."),
  selection = list(type = "chain", n_trials = 1,
    note = "매핑 파라미터 grid 0회. DSR HARD 부적용(sweep 아님). s4 범위 진단도 격자 탐색이 아니라 매핑-무관 비모수 관계 관측."),
  cost_note = "VT2/VT2b 는 벤치-스케일 산술이라 거래비용이 개입하지 않는다. 회전(|Δe| 월평균)만 기록 — VT4 착수 시 15bps 부과 대상.",
  turnover_delta_e_monthly_mean = mean(abs(diff(EV$e))),
  turnover_delta_e_annual = mean(abs(diff(EV$e))) * 12
)
write_json(val, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = 6)
cat("[emit] alpha_validation.json\n")

## ── (c) alpha_package.json — AST v1.1 3층 ───────────────────────────────────
sel <- HY$selected
esc_sigma_star <- list(escape_type = "SPECIAL_OP",
  op_code_path = "stage_artifacts/WT_D20260813_003/s1_prereg.R::sigma_star = expanding median(sigma_d[1:m])",
  walk_forward = TRUE)
## e = CLIP( DIV( sigma_star , TS_STD(BM_Ret, 252) ), 0.50, 1.00 )
## ★연산자 계층 분열 실측: schema.json ast_node.op enum 은 "DIV_GUARD" 만,
##   02_Infrastructure/ast/operator_library.json 은 "DIV" 만 등재 —
##   나눗셈을 쓰는 패키지는 두 계층을 동시에 만족할 수 없다(ALB-005 동류).
##   실차단 계층(ast_spec_gate.sh -> operator_library)을 따라 DIV 를 채택하고
##   schema 불일치를 challenge_flags 에 결함으로 보고한다.
ast_e <- list(op = "CLIP", args = list(
  list(op = "DIV", args = list(
    list(leaf = "SPECIAL_OP", escape_contract = esc_sigma_star),
    list(op = "TS_STD", args = list(list(leaf = "A1_RAWDATA_OHLCVS_daily:BM_Ret"), 252)))),
  0.50, 1.00))

pkg <- list(
  task_id = "WT-D20260813_003", as_of_date = "2026-08-13", forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  pit = list(sig_date = "2026-08-07", decision_ts = "2026-08-13",
    note = "신호 가용 마지막 거래일(벤치 일별 원장 말단 0채움 2영업일 배제). 소비 컷오프 = Date < first-day-of-holding-month (C5). 평가 마지막 홀딩월 = 2026-07 (2026-08 은 미완료월로 배제)."),
  hypothesis = list(
    statement = sel$hypothesis_description,
    mechanism = list(agent = sel$mechanism$agent, friction = sel$mechanism$friction, path = sel$mechanism$path),
    falsification = list(
      list(field = "A4_benchmark_kospi200",
challenge = "VT1/VT2/VT2b 전부 이 리프(월간 홀딩월 수익 + 일별 원장의 월내 실현 vol)에서 산출. 승계 falsification.observable VT1·VT2 원문 적용.",
           inherited_rule = "VT2: e 계열 실현 vol 이 exposure-matched 통제 대비 추가로 낮은가 (순열 q95 초과 ∧ 상대 vol 이득 >= 2%)"),
      list(field = "A1_RAWDATA_OHLCVS_daily",
           challenge = "sigma_hat = trailing 252거래일 BM_Ret 표준편차. 원천 이중화 대조 + VT3 컷오프 간격 실증.",
           inherited_rule = "VT2b: mean((e - ebar) * r) 의 NW lag-3 t <= -2.0 이면 수익 희생으로 기각. 점추정 음수·비유의면 순효과 부호로 판정(tie_rule)."),
      list(field = "E5_msm_crisis_prob",
           challenge = "대조군 전용 — C1 전표본 디민 실측으로 피처 자격 없음(승계 규약). 본 라운드 피처 미사용."),
      list(field = "E6_sjm_bearprob",
           challenge = "대조군 전용 — 동일. s4 일반성 대조표에만 등장(순위-수익 공분산 부호 확인).")),
    regime_scope = sel$regime_scope),
  factors = list(list(
    factor_id = "VT1_voltarget_exposure", role = "exposure_scaler", restatement_exposure = 1,
    ast = ast_e,
    note = "종목-횡단면 팩터가 아니라 시장-레벨 노출 스케줄. sigma_star(expanding median)는 O 에 TS 분위/확장중앙값 연산자가 없어 SPECIAL_OP escape 로 표현(walk-forward). O 확장 후보 = TS_QUANTILE / TS_MEDIAN (expanding).")),
  combination_rule = "single_factor",
  verdict = "designed",
  self_pit_check = list(performed = TRUE, leaves_checked = list(
    list(leaf = "A1_RAWDATA_OHLCVS_daily:BM_Ret",
         availability_rule = "fixed: 거래일 종가 확정치 t-1. 소비 컷오프는 그보다 엄격 — Date < first-day-of-holding-month. 독립 원천(.cache/benchmark.parquet) 일별 cor 0.999931.",
         restatement_prone = TRUE),
    list(leaf = "A4_benchmark_kospi200",
         availability_rule = "fixed: 일배치 T-1 정합. 홀딩월 수익은 apply.monthly(Return.cumulative) 표준함수 경유, 승계 패널 bm_ret 과 max|diff|=0.",
         restatement_prone = TRUE),
    list(leaf = "SPECIAL_OP (expanding median sigma_star)",
         availability_rule = "walk-forward: m 시점 median(sigma_hat[1:m]) — 전 입력이 홀딩월 시작 전 가용. 자유 파라미터 아님.",
         restatement_prone = FALSE)),
    verdict = "clean",
    evidence = list(assert_overlay_pit = "PASS (sigma_hat / rf_asof)",
      violation_injection_fires = V2$VT3$guard_violation_injection_fires,
      lag1_retention = V2$VT3$lag1_retention,
      injected_leak_ab_inflation = V2$VT3$ab_inflation,
      true_ab_inflation = V3$VT3c_relabel$true_ab_inflation,
      clip_identity_max_abs = V2$VT3$clip_identity_max_abs)),
  alpha_vector = setNames(list(), character(0)),
  confidence_vector = setNames(list(), character(0)),
  alpha_discovery_count = 0,
  alpha_vector_note = "시장-레벨 시계열 노출 스케줄 — Ticker→기대초과수익 벡터가 정의되지 않으며 빈 객체가 정상 산출. 실제 산출 = signal_matrix_ref 의 exposure_e 계열.",
  signal_matrix_ref = "stage_artifacts/WT_D20260813_003/alpha_scores.parquet",
  factor_specs = list(list(
    factor_family = "Regime_VolTarget_Overlay",
    proxy = "e_m = clip(sigma_star_m / sigma_hat_m, 0.50, 1.00)",
    formula = "sigma_hat_m = sd(trailing 252 거래일 BM_Ret, Date < 홀딩월 1일); sigma_star_m = expanding median(sigma_hat[1:m])",
    lag_rule = "C5 overlay: 홀딩월 시작 전 데이터만 (assert_overlay_pit HARD PASS)",
    winsorization = "none (clip 0.50~1.00 이 매핑에 내장)", neutralization = "none",
    economic_rationale = "risk_premium",
    economic_rationale_detail = "변동성 군집 + 레버리지 제약 하 분산 관리. 승계 mechanism 3요건(agent/friction/path) 참조 — 재작성 금지.",
    weight_theta = 1.0,
    references = list("Moreira-Muniz 2017 (Volatility-Managed Portfolios)",
                      "Frazzini-Pedersen 2014 (Betting Against Beta — 레버리지 제약)",
                      "OVL_book_voltarget_R3 (내부 실측 negative, 2026-07-06)",
                      "PL_VolTargetFloored/Strict (내부 실측 negative, 2026-08-09)"),
    redundancy_cluster_id = "REGIME_VOLSTATE_TS",
    redundancy_note = "승계 WT-002 와 동일 클러스터(sigma_hat = 그 라운드 VOL 계열의 level 판). 신규 예측 원천 아님 — 신규성은 판정 분해에 있음(승계 자인).")),
  diagnostics = list(
    canonical_port_t_nw_lag3 = NULL, canonical_port_t_pvalue = NULL, canonical_n_months = NULL,
    canonical_null_reason = "사전등록 판정순서상 VT2b 기각 시 성과 측정 착수 금지. VT2b = REJECT 이므로 canonical_screen_bt / forge 미실행. 미산출이지 미달이 아니다.",
    rank_ic = V4$relation$spearman,
    rank_ic_basis = sprintf("★횡단면 아님 — 시계열 basis. spearman(sigma_hat_m, 홀딩월 벤치수익) over %d 개월 = %+.4f (p=%.4f). 시장-레벨 오버레이라 cross-sectional rank-IC 는 정의되지 않는다.",
                            V2$n_months, V4$relation$spearman, V4$relation$spearman_p),
    advisory_ic_family_note = "icir / monotonicity / subperiod_stability / harvey_t_stat / post_neutralization_ic 는 횡단면 알파 전용 지표라 시장-레벨 노출 스케줄에 정의되지 않는다. null 대신 키를 생략한다(schema 는 number 형을 요구 — null 기입이 형 위반).",
    turnover_proxy = mean(abs(diff(EV$e))) * 12,
    alpha_inheritance_cor = 0.0,
    alpha_inheritance_note = "parent 없음(discovery). 횡단면 alpha 0건 산출이므로 승계 상관 정의상 0. 신호 승계(WT-002 VOL)는 alpha_inheritance 가 아니라 예측기 승계 — parity spearman 1.000000 별도 기록.",
    vt1_spearman_sigma_realized = V2$VT1$spearman,
    vt2_G = V2$VT2$G, vt2_null_q95 = V2$VT2$null_q95, vt2_p_perm = V2$VT2$p_perm, vt2_pass = V2$VT2$pass,
    vt2b_mean_d_annual_pct = V3$VT2b_final$mean_d_annual_pct,
    vt2b_nw_lag3_t = V3$VT2b_final$nw_lag3_t,
    vt2b_variance_drag_gain_annual_pct = V3$VT2b_final$variance_drag_gain_annual_pct,
    vt2b_net_effect_annual_pct = V3$VT2b_final$net_effect_annual_pct,
    vt2b_boot_p_net_gt0 = V3$VT2b_final$bootstrap$p_net_gt0,
    vt_verdict = V3$verdict),
  selection_objective = "canonical_port_t",
  selection_objective_note = "선언값은 VT4 로 진행했을 경우의 선택 권위. 실제로는 선택이 0회 발생하지 않았다 — 사전등록된 단일 매핑의 통과/기각 판정이고 후보 열거·argmax 가 없다. selection_type=chain, n_trials=1.",
  vt_gate_objective = "VT2(분산 타이밍 이득, exposure-matched 통제 + circular block 순열) -> VT2b(cov(e,r) 수익 희생, NW lag-3 + tie_rule). selection_objective enum 밖이라 별도 필드로 기록(WT-002 선례).",
  challenge_flags = as.list(readLines(file.path(OUT, "_challenge_flags.txt"), warn = FALSE))
)
write_json(pkg, file.path(MBX, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, digits = 6, null = "null")
cat("[emit] alpha_package.json\n")

## ── (d) lineage — ★alpha_package.json write 이후 (L-194) ────────────────────
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260813_003", package_type = "alpha_package",
  method_selected = "vol-target exposure schedule e=clip(sigma*/sigma_hat, 0.50, 1.00); VT2 PASS / VT2b REJECT (tie_rule)",
  input_file_paths = c(".cache/RAWDATA.parquet", ".cache/benchmark.parquet",
                       ".cache/ecos_bond_rates.parquet",
                       "stage_artifacts/WT_D20260813_002/alpha_scores.parquet",
                       "qepm/mailbox/worktask/WT-D20260813_003/alpha_hypothesis.json",
                       "stage_artifacts/WT_D20260813_003/prereg_VT.json"))
cat("\n[done] emit complete\n")
