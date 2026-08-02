# =============================================================================
# run_wt015_emit.R — WT-D20260802_015 AST v1.1 alpha_package + validation + lineage
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_015/run_wt015_emit.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_015")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_015")
`%||%` <- function(a, b) if (is.null(a)) b else a
num <- function(x, d = 4) if (is.null(x) || !is.finite(as.numeric(x))) NA else round(as.numeric(x), d)
say <- function(fmt, ...) cat(sprintf(paste0("[emit15] ", fmt, "\n"), ...))

R <- readRDS(file.path(OUT, "wt015_results.rds"))

# ── alpha_vector / confidence (primary composite 최종 횡단면) ────────────────
SC <- as.data.table(read_parquet(file.path(OUT, "alpha_scores.parquet")))
SC[, Date := as.Date(Date)]
last_d <- SC[, max(Date)]
LV <- SC[Date == last_d][order(-score)]
alpha_vector <- as.list(setNames(round(LV$score, 6), LV$Ticker))
cov_m <- SC[, .N, by = Ticker][, setNames(pmin(1, N / 120), Ticker)]
confidence_vector <- as.list(setNames(
  vapply(LV$Ticker, function(tk) round(max(0.3, min(1, as.numeric(cov_m[[tk]] %||% 0.5))), 3),
         numeric(1)), LV$Ticker))

arm_stats <- function(a) {
  b <- R$bt[[a]]; ew <- b$diag_ew_universe; ct <- b$diag_cap_tier
  out <- list(port_t = num(b$portfolio_alpha_t_nw_lag3, 3), net_sr = num(b$net_sr, 3),
       ir = num(b$information_ratio, 3), turnover_annual = num(b$turnover_annual, 2),
       n_months = b$n_months, selected_ret_coverage = num(b$selected_ret_coverage, 4))
  if (!is.null(ew)) {
    out$ew_uni_t <- num(ew$portfolio_alpha_t_nw_lag3, 3)
    out$ew_uni_post2017_t <- num(ew$post2017_t_nw_lag3, 3)
    out$ew_uni_oos_retention_approx <- num(ew$oos_retention_approx, 4)
  }
  if (!is.null(ct) && isTRUE(ct$available)) {
    out$cap_tier_weight_share <- ct$weight_share_avg
    out$cap_tier_contrib <- ct$contrib_gross_annualized
  }
  out
}
ARM <- lapply(setNames(c("PRIMARY", "C1_EW", "C2_BROT", "C3_SINGLE", "LAG1", "CONTAM"),
                       c("PRIMARY_ROT_TUNED", "C1_EW_STATIC_TUNED", "C2_ROT_BASE",
                         "C3_SINGLE_M01_PATHQ", "STRESS_REGIME_LAG1", "DIAG_CONTAMINATED_LOOKAHEAD")),
              arm_stats)
paired_of <- function(p) {
  x <- R$paired[[p]]
  list(paired_t_nw = num(x$t, 3), n_months = x$n,
       mean_d_annualized_pct = num(100 * x$mean_d_ann, 3),
       t_post2017 = num(x$t_post2017, 3))
}

# WT-009 tuned factor AST 재사용 (동일 세션 산출 패널 — provenance 명시)
pkg9 <- fromJSON(file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_009/alpha_package.json"),
                 simplifyVector = FALSE)
factors9 <- pkg9$factors
for (i in seq_along(factors9)) factors9[[i]]$role <- "rotation_input_tuned_wt009"

pkg <- list(
  task_id = "WT-D20260802_015",
  as_of_date = "2026-08-02",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  hypothesis = list(
    statement = paste0("국면(unified regime Category)별 expanding 조건부 IC에 비례해 튜닝 5팩터",
      "(WT-009) 배합 비중을 바꾸는 로테이션 합성이 EW 정적 합성 대비 실현 net active를 개선하고, ",
      "튜닝 입력(팩터 간 상관 0.209→0.145)이 base 입력 대비 로테이션 효익을 키운다(D1/D2). ",
      "사전등록 stage_artifacts/WT_D20260802_015/preregistration.json (측정 전 고정)."),
    mechanism = list(
      agent = "상수 배합 스크리너 관행 — 국면별 팩터 프리미엄 이질성(WT-009 AX-001 실측: 모멘텀 RISK_ON t+2.85 vs CRISIS -0.99, 배당 RISK_ON +2.43 vs NEUTRAL -1.36)을 소비하지 않는 정적 배합 주체",
      friction = "KR 공매도 제약 + 롱온리 상수 배합 고착 — 국면 전환기 재배합의 추정 불안정·회전 비용이 조건부 배분을 지연",
      path = "월말 국면 라벨 확정 → 그 국면에서 조건부 IC가 높았던 팩터로 비중 이동 → 익월 실현 active 개선"),
    falsification = paste0("성과-국소화 검정 2종 사전 프레임: (i) 국면 전환월에서 로테이션-정적 격차가 ",
      "발생하지 않으면 기전 기각 — 실측 전환월 69개월 t=-0.27 (비전환월 +1.50) = 기각. ",
      "(ii) 라벨 look-ahead판(r_{t+1}, regime 캐시 리프)이 clean판을 상회하지 않으면 라벨 축에 ",
      "착취 가능 조건부 정보 부재로 기각 — 실측 오염판 -15.7% 열위 = 기각."),
    regime_scope = list(
      holds_in = list("CRISIS", "CAUTION"),
      weakens_or_reverses_in = list("RISK_ON"),
      boundary_rationale = paste0("조건부 재배합의 기대 효익은 프리미엄 부호가 뒤집히는 위기·경계 국면에 ",
        "국소화되어야 함(기전상). RISK_ON 지배(212/295개월)에서는 조건부가 무조건부에 수렴. ",
        "실측: CRISIS active t +0.16으로 미실현 — 기전 자체가 기각됨"))),
  factors = factors9,
  combination_rule = "z_score_aligned_weighted_sum",
  combination_note = paste0("비중 = regime-conditional expanding IC clip0-비례 (무모수, 적합 파라미터 0, ",
    "m<=t-1 IC만, 조건부 n>=12 / 총 24개월 게이트, 전 팩터 clip0 시 EW — preregistration 고정 규칙). ",
    "월별 유니버스 재-z 후 가중평균, 종목별 비결측 팩터 >=3."),
  verdict = "designed",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "stage_artifacts/WT_D20260802_009/{base,tuned}_panel.parquet",
           availability_rule = "동일 세션(2026-08-02) walk-forward 산출 패널 재소비 — 생산 스크립트 run_wt009_tuned.R, WT-009 lag1 스트레스로 동월 누출 부재 실증. 저장 파생 패널 provenance 명시(§4-1)",
           restatement_prone = TRUE),
      list(leaf = ".cache/unified_regime_signal.parquet:Category",
           availability_rule = "월말 라벨. MSM 층 = expanding refit(msm_daily_refit.R) 확인. KTRI/VEA/FRED 층 vintage 전수 감사는 미수행(challenge_note C1 — negative 판정에 보수 방향)",
           restatement_prone = FALSE),
      list(leaf = "A1_rawdata:Ret/Close (build_monthly_forward_returns)",
           availability_rule = "fixed: t-1 종가 확정, forward 1M 실현수익", restatement_prone = TRUE)),
    verdict = "clean",
    verdict_rationale = paste0("C1: 비중 규칙 전체가 expanding(m<=t-1 IC만, full-sample 통계 0). ",
      "C5: assert_overlay_pit HARD PASS(295개월 컷오프<홀딩월 시작) + 위반 주입(r_{t+1}) 차단 발화 실증 + ",
      "lag1 무붕괴(+1.25>+0.90) + 오염판 열위(-15.7%) — look-ahead 의존 부재.")),
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = "stage_artifacts/WT_D20260802_015/alpha_scores.parquet",
  factor_specs = list(
    list(factor_family = "Composite_RegimeRotation",
         proxy = "V01_SECREL+M01_PATHQ+D03_EWMA+Q01_EB+V06_EB (WT-009 tuned)",
         formula = "sum_k w_k(regime_t) * z_k ; w_k ∝ max(0, E[IC_k | regime, expanding])",
         lag_rule = "라벨·IC 전부 신호월 말 이전 정보만 (m<=t-1)",
         winsorization = "입력 팩터 단계 3std (WT-009)",
         neutralization = "V01_SECREL만 섹터중립 (WT-009 정의)",
         economic_rationale = "국면별 팩터 프리미엄 이질성의 조건부 소비 (실측 기각 — 전환월 기여 0)",
         weight_theta = 1.0,
         references = list("Arnott-Beck-Kalesnik factor timing", "DIST-RAMP-006", "WT-D20260718_005/006"))),
  diagnostics = list(
    canonical_port_t_nw_lag3 = num(R$bt$PRIMARY$portfolio_alpha_t_nw_lag3, 3),
    canonical_port_t_pvalue = num(R$bt$PRIMARY$portfolio_alpha_t_pvalue, 4),
    canonical_n_months = R$bt$PRIMARY$n_months,
    metric_type = "canonical_screen",
    arm_stats = ARM,
    paired_tests = list(
      rerun_tunedRot_vs_baseRot = paired_of("rerun_tunedRot_vs_baseRot"),
      value_tunedRot_vs_ewStatic = paired_of("value_tunedRot_vs_ewStatic"),
      value_tunedRot_vs_single = paired_of("value_tunedRot_vs_single")),
    cond_only_supplement = list(
      note = "COND 215개월 한정(EW_INIT 24·MIXED 56 희석 반박 검정 — challenge_note C3)",
      rerun_cond_only_t = -0.56, value_vs_ew_cond_only_t = 0.36,
      switch_months_value_t = -0.27, nonswitch_months_value_t = 1.50, n_switch = 69),
    pit_verification = list(
      assert_overlay_pit = "PASS (295개월, clean r_t 컷오프 < 홀딩월 시작)",
      violation_injection = "r_{t+1} 주입 시 assert stop 발화 확인 (차단 실효)",
      regime_lag1_stress_port_t = num(R$bt$LAG1$portfolio_alpha_t_nw_lag3, 3),
      contaminated_diag_port_t = num(R$bt$CONTAM$portfolio_alpha_t_nw_lag3, 3),
      contamination_inflation = num(R$contam_ab$inflation, 4),
      strict_ab_note = "clean 타이밍이 곧 strict(라벨 월말<홀딩월 시작) — current=strict 동일, 인플레 0"),
    ax001_conditional = lapply(seq_len(nrow(R$ax001)), function(i) as.list(R$ax001[i])),
    label_vs_realized = lapply(seq_len(nrow(R$label_realized)), function(i) as.list(R$label_realized[i])),
    mdd_primary = num(R$mdd_primary, 4),
    oos_rough_diag = as.list(round(R$oos_rough, 3)),
    weight_path = list(l1_turnover_annual = num(R$w_l1_turnover, 3),
                       mode_distribution = as.list(table(R$rot_tuned$mode)),
                       mean_weights_by_regime = lapply(seq_len(nrow(R$w_by_reg)), function(i) as.list(R$w_by_reg[i]))),
    rank_ic = NA, icir = NA, monotonicity = NA, subperiod_stability = NA,
    turnover_proxy = num(R$bt$PRIMARY$turnover_annual, 2),
    harvey_t_stat = NA, post_neutralization_ic = NA,
    ast_sidecar_live_with_ast = R$sidecar,
    n_iterations = 1, n_trials = 1,
    selection_type = "chain",
    deflated_sharpe_ratio = NULL,
    dsr_note = "단일 사전등록 규칙(argmax/threshold-pick 없음) — DSR 게이트 비발동. 대조군 3종은 해석용(선택 아님)"),
  selection_objective = "canonical_port_t",
  alpha_discovery_count = 0,
  challenge_flags = list(
    list(id = "CF-01", severity = "MEDIUM",
         flag = "국면 라벨 KTRI/VEA/FRED 층 vintage 전수 미감사 — negative 판정에 보수 방향이나 라벨 무결 증명 아님 (challenge_note C1 ACCEPT)"),
    list(id = "CF-02", severity = "MEDIUM",
         flag = "단일 비중 규칙 config-scope — family 판결 아님 (C2 ACCEPT, INV-7). DIST-RAMP-006 posterior와 방향 일치"),
    list(id = "CF-03", severity = "INFO",
         flag = "조건부-IC 가중은 IC→PORT_t 전이 벽을 국면 축으로 재수입 (C4 — 본 라운드 핵심 기전 지식: IC 최상위 D03_EWMA(-1.73 PORT_t)에 NEUTRAL 0.33 비중 배정)"),
    list(id = "CF-04", severity = "INFO",
         flag = "라벨-실현 불일치 병기: CRISIS 25개월 벤치 연 +0.2%(2026 멜트업 오염 포함, WT-004 실측 정합) — 라벨 축 자체의 소비 가능성 의심")),
  verdict_summary = list(
    result = "NEGATIVE_config_scoped__rerun_verdict_D1_falsified",
    gate_eligible = FALSE,
    statement = paste0("재탕 판별 단답: 재탕 이하 — 튜닝판 로테이션(+0.90)이 base판 로테이션(+1.40) 대비 ",
      "열위(-1.91%/yr, t=-1.22). D1(상관 개선→로테이션 효익) 반증. 로테이션 자체 효익도 부재: ",
      "vs EW정적 +1.28(n.s.)이나 전환월 기여 t=-0.27 = 국면 전환이 아닌 지속 tilt 산물, post-2017 -1.59 역전. ",
      "최강 단일(M01_PATHQ +2.05)에도 열위. 기전 진단: 조건부-IC 비례 가중이 IC→PORT_t 전이 벽을 ",
      "국면 축으로 재수입(D03_EWMA anti-selection). DIST-RAMP-006·WT-005/006 posterior 정합 — ",
      "현 config 수렴 + next_probe 3건 + 부활 조건 명시."),
    consumption_scan_7 = list(
      factor_ranking = "비적합 — 로테이션 합성이 최강 단일에도 열위",
      universe_filter = "비적합 (배합 규칙 — 필터 신호 아님)",
      overlay_regime_input = "역정보 산출: 이 라벨 축은 팩터 로테이션 소비 불가(오염판조차 열위) — 라벨 재설계가 선행 조건이라는 실측 근거로 소비",
      risk_model_beta_budget = "WT-009 NP-2 승계 (EWMA vol → Sigma 입력) — 본 라운드 무변경",
      monitoring_signal = "국면별 비중 경로(w_by_reg)는 모니터링 참고 자료로만",
      screening_label = "screen_route 발급 없음 (screen_pass 미달)",
      cross_mode_transfer = "RAMP에 기전 지식 이식: 조건부-IC 가중의 전이 벽 재수입 — RAMP regime matrix 설계 시 IC 아닌 실현 active 조건화 권고"),
    next_probe = list(
      list(id = "NP-1", priority = "P2",
           probe = "조건화 통계량을 IC에서 조건부 실현 active(top-25 paired)로 교체한 1규칙 사전등록 재검 — 전이 벽 재수입 제거 확인. 단 DIST-RAMP-006 posterior상 기대값 낮음 — frontier 조건부(착수 전 큐 심사)",
           rationale = "C4 기전 진단의 직접 검증 경로"),
      list(id = "NP-2", priority = "P1",
           probe = "국면 라벨 재설계 실측: 라벨 축과 실현-하락 축 불일치(2026 CRISIS 멜트업)가 로테이션·오버레이 소비 전반의 상류 병목 — 실현-드로다운 정합 라벨(예: 벤치 실현 조건 결합)로 오염판-우위 검정(look-ahead판이 유의 양수가 되는 라벨이어야 착취 가능 정보 실재)",
           rationale = "본 라운드 부산물: 현 라벨은 미래를 알아도 못 버는 라벨 — 라벨 정보력이 선행 관문"),
      list(id = "NP-3", priority = "P2",
           probe = "WT-013(M01_PATHQ vol-잔차 순수판) 완주 후 생존 시, 양수-PORT_t 팩터만의 소풀(M01_PATHQ+V01_SECREL+V06_EB)로 정적 합성 재측정 — 로테이션 없이 breadth 효과만 분리 (WT-009 NP-4 연계)",
           rationale = "음수 팩터를 풀에서 제거하는 것이 로테이션보다 상류의 개선")),
    revival_conditions = list(
      "국면 라벨이 NP-2 기준(오염판-우위 유의 양수)을 통과해 착취 가능 조건부 정보의 실재가 선행 입증될 때",
      "팩터 풀에 canonical PORT_t 양수 sleeve가 3개 이상 확보되어 배분 대상 자체가 성립할 때 (현 tuned 5 중 2개만 양수)")),
  method_shopping_log = list(alpha_agent = list(
    candidates_tried = 1,
    method_log = list(list(name = "REGIME_COND_IC_ROTATION_TUNED5",
      canonical_port_t = num(R$bt$PRIMARY$portfolio_alpha_t_nw_lag3, 3),
      selected = TRUE,
      note = "단일 사전등록 규칙. 대조군 3종(EW정적/base로테이션/최강단일)은 해석용 — 선택/argmax 없음")))))

write_json(pkg, file.path(MB, "alpha_package.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", na = "null", digits = 8)
say("alpha_package.json 저장 (%d tickers)", length(alpha_vector))

# ── alpha_validation.json ────────────────────────────────────────────────────
val <- list(
  task_id = "WT-D20260802_015",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  metric_type = "canonical_screen",
  preregistration = "stage_artifacts/WT_D20260802_015/preregistration.json",
  prior_contrast_inv7 = list(
    old_configs = c("DIST-RAMP-006 (regime 배분 천장 ~2.85)",
                    "L-AR-20260718_232148 (factor timing: valuation/transformer FAIL, momentum screen-tier)",
                    "L-AR-20260718_235244 (외생 ML forecasting 6/6 FAIL)",
                    "regime-conditional 교차결합 settled-negative (2026-07-05)"),
    rerun_verdict = "재탕 이하 — D1(튜닝 입력 차별) 반증: 튜닝 로테이션이 base 로테이션 대비 -1.91%/yr (t=-1.22)"),
  arm_stats = ARM,
  paired_tests = pkg$diagnostics$paired_tests,
  cond_only_supplement = pkg$diagnostics$cond_only_supplement,
  pit_verification = pkg$diagnostics$pit_verification,
  ax001_conditional = pkg$diagnostics$ax001_conditional,
  label_vs_realized = pkg$diagnostics$label_vs_realized,
  weight_path = pkg$diagnostics$weight_path,
  universe_comparison = list(
    note = "배포 유니버스(K200∪KQ150) 직접 측정. dual-basis 병기 — cap-w 권위 불변",
    dual_basis_by_arm = lapply(ARM, function(a)
      list(cap_w = a$port_t, ew_uni = a$ew_uni_t %||% NA, ew_post2017 = a$ew_uni_post2017_t %||% NA))),
  graduation_hard_gates = list(
    portfolio_alpha_t_nw = list(required = 2.95, observed_primary = num(R$bt$PRIMARY$portfolio_alpha_t_nw_lag3, 3),
      status = "FAIL", note = "canonical screening 실측 — forge 미제출(자본 판정 아님)"),
    oos_retention = list(required = 0.7, observed_rough = num(R$oos_rough[["PRIMARY"]], 3),
      status = "DIAG_ONLY (음수 — post-2017 감쇠)", note = "진단 근사 — 권위는 essence_score"),
    calmar = list(required = 0.64, observed = NA, status = "NOT_COMPUTED", note = "forge 미제출")),
  production_constraints = list(turnover_annual_limit = 11.0,
    observed_primary = num(R$bt$PRIMARY$turnover_annual, 2),
    verdict = "회전 7.5/yr — 상한 이내 (로테이션 회전 증분은 EW 대비 +2.3/yr)"),
  repairs = list(
    r1_coverage_guard = paste0("canonical_screen_bt 선택분 Ret_1m 커버리지 warn-가드 추가 ",
      "(WT-009 CF-03 비유니버스 오염 침묵 붕괴 재발방지) + selected_ret_coverage 필드. ",
      "위반 주입: clean=미발화/오염=발화 실증 (repair_injection_result.rds)"),
    r2_contract_loader = paste0("canonical_screen_bt .CANON_DIR 해석 수리 — 중첩 source 시 ",
      "sys.frame(1)$ofile이 최상위 스크립트를 가리켜 계약 미로드 침묵(fallback dead). ",
      "marker 검증 + QM_ROOT resolver로 교체. 주입 증거: 수리 전 동일 테스트가 ",
      "could not find build_benchmark_compare로 사망 → 수리 후 로드 확인")),
  challenge_note = "qepm/mailbox/worktask/WT-D20260802_015/challenge_note.md (concern 5: ACCEPT 4 / REBUTTAL 1)",
  sidecar_live_with_ast = R$sidecar)
write_json(val, file.path(OUT, "alpha_validation.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", na = "null", digits = 8)
say("alpha_validation.json 저장")

# lineage (package write 이후 — L-194 순서)
try({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = "WT-D20260802_015", package_type = "alpha_package",
    method_selected = "regime-conditional expanding IC clip0-비례 로테이션 (tuned 5, 사전등록 단일 규칙)",
    input_file_paths = c(".cache/RAWDATA.parquet",
                         ".cache/unified_regime_signal.parquet",
                         "stage_artifacts/WT_D20260802_009/base_panel.parquet",
                         "stage_artifacts/WT_D20260802_009/tuned_panel.parquet",
                         file.path(OUT, "preregistration.json")))
  say("lineage 기록 완료")
}, silent = FALSE)

st <- list(task_id = "WT-D20260802_015", current_phase = "ALPHA_DONE",
           updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"), blocker = NULL)
write_json(st, file.path(MB, "status.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
gl <- fromJSON(file.path(MB, "governance_log.json"), simplifyVector = FALSE)
gl$events <- c(gl$events, list(list(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  agent = "alpha-research",
  action = "ALPHA_PACKAGE_EMITTED",
  summary = paste0("국면-조건부 로테이션 NEGATIVE config-scoped — 재탕 판별: 재탕 이하(D1 반증, ",
    "튜닝 로테이션 -1.91%/yr vs base 로테이션). 전환월 기여 t=-0.27 = 기전 기각. ",
    "PIT: assert PASS + 위반주입 차단 + lag1 무붕괴 + 오염판 열위. 수리 2건(커버리지 가드·계약 로더). ",
    "next_probe 3 + 부활 조건 2."))))
write_json(gl, file.path(MB, "governance_log.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
say("status/governance 갱신 완료")
