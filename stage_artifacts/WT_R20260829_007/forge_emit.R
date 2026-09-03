#==============================================================================
# WT-R20260829_007 — authoritative_remeasure.json 발행
#   권위 등급 = essence_score.R (contracts). hurdle proxy 인용 0.
#==============================================================================
Sys.setenv(QM_ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- Sys.getenv("QM_ROOT")
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
STAGE <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
WT_DIR <- file.path(ROOT, "qepm/mailbox/worktask/WT-R20260829_007")

bt   <- readRDS(file.path(STAGE, "bt_result.rds"))
es   <- readRDS(file.path(STAGE, "forge_essence.rds"))
fe   <- readRDS(file.path(STAGE, "forge_env.rds"))
diag <- fromJSON(file.path(STAGE, "forge_diag.json"), simplifyVector = FALSE)
pitb <- fromJSON(file.path(STAGE, "forge_pit_bidirectional.json"), simplifyVector = FALSE)
opt  <- fromJSON(file.path(WT_DIR, "optimization_package.json"), simplifyVector = FALSE)
alp  <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = FALSE)

M  <- as.data.table(bt$metrics); BC <- as.data.table(bt$benchmark_compare)
AU <- as.data.table(bt$audit)
gm <- function(n) { v <- M[metric_name == n, metric_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
gb <- function(n) { v <- BC[metric_name == n, active_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }

S <- es$sweep
gp <- S$graduation_params
port_t <- gb("Portfolio_Alpha_t_NW_lag3"); sr <- gm("Sharpe"); cagr <- gm("CAGR")
calmar <- gm("Calmar"); mdd <- gm("MDD"); net_ir <- gb("Information_Ratio")
oos <- as.numeric(S$essence$oos_retention); dsr <- as.numeric(S$essence$dsr)

A5 <- list(
  cond1_port_t     = list(metric = "Portfolio_Alpha_t_NW_lag3", value = port_t,
                          threshold = gp$port_t_min, op = ">=", pass = isTRUE(port_t >= gp$port_t_min)),
  cond2_oos_retention = list(metric = "oos_retention (essence v2, anchored 55/65/75 중앙값)",
                          value = oos, threshold = gp$oos_min, op = ">=",
                          pass = isTRUE(oos >= gp$oos_min),
                          splits = S$oos_retention_splits, band_status = S$oos_band_status),
  cond3_sharpe     = list(metric = "Sharpe (net)", value = sr, threshold = gp$sharpe_min,
                          op = ">=", pass = isTRUE(sr >= gp$sharpe_min)),
  cond4_cagr       = list(metric = "CAGR (net)", value = cagr, threshold = gp$cagr_min,
                          op = ">=", pass = isTRUE(cagr >= gp$cagr_min)),
  cond5_calmar     = list(metric = "Calmar", value = calmar, threshold = gp$calmar_min,
                          op = ">=", pass = isTRUE(calmar >= gp$calmar_min)))
A5_pass <- sum(vapply(A5, function(x) isTRUE(x$pass), TRUE))

out <- list(
  schema = "authoritative_remeasure/v1",
  wt_id = "WT-R20260829_007",
  wt_type = "reinforcement",
  axis = "multifactor",
  agent = "forge",
  emitted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  strategy_id = "WTR20260829_007_GH2004_52WHIGH_EW25_BUF50",
  strategy_name = paste("GH2004 52-week high proximity top-25 EW + no-trade band 50",
                        "(alpha=GH2004 proximity / optimizer=M2_EW25_buffer50)"),

  #-------------------------------------------------------------- 권위 등급
  essence_grade = S$grade,
  essence_grade_chain_framing = es$chain$grade,
  grade_basis = "authoritative_essence_score_v1 (02_Infrastructure/contracts/essence_score.R)",
  authoritative = TRUE,
  metric_type = S$metric_type,
  grade_A_conditions = A5,
  grade_A_conditions_passed = sprintf("%d/5", A5_pass),
  reasons = S$reasons,
  proxy_citation_policy = "hurdle_result.json proxy 등급 인용 0건 — 2026-05-31 DEMOTED 규약 준수",

  #--------------------------------------------------------- MDD / 라벨 규약
  structural_drawdown = S$structural_drawdown,
  hard_fail = S$hard_fail,
  hard_fail_source = S$hard_fail_source,
  mdd_policy_note = paste(
    sprintf("MDD %.4f 는 graduation_params$mdd_hard(%.2f)를 넘지만 hard_fail=FALSE 다.", mdd, gp$mdd_hard),
    "★MDD 는 등급을 접지 않는다(v9.21 도훈 지시) — 위험 축은 Calmar 하나.",
    "structural_drawdown 은 라벨이며 본 후보는 FALSE(drawdown_profile$structural_hard_fail = 0)."),
  drawdown_profile = S$essence[grep("^drawdown_profile", names(S$essence))],

  #-------------------------------------------------------------- 권위 수치
  metrics_authoritative = list(
    CAGR = cagr, Sharpe = sr, Sortino = gm("Sortino"), MDD = mdd, Calmar = calmar,
    Annualized_Volatility = gm("Annualized_Volatility"),
    Total_Return = gm("Total_Return"),
    Skewness = gm("Skewness"), Kurtosis = gm("Kurtosis"),
    CVaR_99_daily = gm("CVaR_99"),
    net_IR = net_ir, Tracking_Error = gb("Tracking_Error"),
    Portfolio_Alpha_t_NW_lag3 = port_t, Portfolio_Alpha_t_pvalue = gb("Portfolio_Alpha_t_pvalue"),
    Alpha_Annualized = gb("Alpha_Annualized"),
    Beta_to_Benchmark = as.numeric(BC[metric_name == "Beta_to_Benchmark", strategy_value][1]),
    Up_Capture = as.numeric(BC[metric_name == "Up_Capture", strategy_value][1]),
    Down_Capture = as.numeric(BC[metric_name == "Down_Capture", strategy_value][1]),
    oos_retention = oos, dsr = dsr,
    Annualized_Turnover_one_way = gm("Annualized_Turnover"),
    Average_N_Holdings = gm("Average_N_Holdings"),
    observation_days = 5319L, rebalances = 259L),

  measurement_basis_primary = "forge_realized_share_based",
  measurement_note = paste(
    "weights.csv 260 as_of_date 를 as-is 소비 -> t+1 종가 정수주 집행 -> 일별 share-based NAV.",
    "재선택 0회 · alpha_scores.parquet holdings 재산출 0회 (Schedule Fidelity Mandate).",
    "비용 v2.4_kr_retail_15bps one-way delta. 벤치 = production KOSPI200 BM_Ret."),

  #------------------------------------------------- 하드 제약 forge 재검증
  hard_constraints_forge_reverified = list(
    max_names_25 = list(observed_max = fe$n_max_weights, pass = fe$n_max_weights <= 25,
                        audit_check = AU[check_name == "holdings_cap", status]),
    long_only = list(negative_rows = fe$n_negative, pass = fe$n_negative == 0L),
    sum_w_1 = list(max_abs_dev = fe$max_sumw_dev, pass = fe$max_sumw_dev <= 1e-6),
    weight_cap = list(applies = FALSE, note = "v10 2026-08-29 종목별 비중 상한 폐지"),
    turnover_cap_11_0 = list(
      forge_annualized_one_way = gm("Annualized_Turnover"),
      forge_annualized_two_way = 2 * gm("Annualized_Turnover"),
      cap_two_way = 11.0,
      pass = isTRUE(2 * gm("Annualized_Turnover") <= 11.0),
      optimizer_reported_two_way = opt$turnover_annual_2way,
      cross_layer_agreement = "forge 독립 재측정 10.11 vs optimizer 10.35 — 정수주/집행일 차이 범위 내 일치")),

  #----------------------------------------- ★이 라운드의 특수 사정 (필수 기록)
  upstream_constraint_incident = list(
    incident = paste("alpha 가 넘긴 사양(근접도 top-25 등가중)은 연 양방향 회전 15.31 로",
                     "constraint_defaults.json::turnover_hard_fail_annual = 11.0 을 **이미 위반**한 상태였다."),
    consequence_for_citation = paste(
      "따라서 alpha 단계 좌표(PORT_t 0.929 · β-통제 α +6.99%/yr · 활성 net +3.91%/yr)는",
      "**제약을 넘는 포트폴리오 위의 값**이다. 본 권위 수치는 제약을 지키는 구성(M2_buffer50)의 것이므로",
      "alpha 좌표와 직접 비교하지 않는다."),
    resolution = "optimizer no-trade band(rank<=50) 도입 -> 10.35. 제약 완화·예외 0건.",
    measured_exchange = list(
      turnover_2way = "15.31 -> 10.35 (-32.4%)",
      cost_per_year = "-74bp",
      gross_active_alpha = "-127bp",
      net_active = "-52bp",
      breakeven_one_way_bps = "40.5 -> 47.7",
      capacity_median_krw = "14.9억 -> 24.0억",
      verdict = "비용 절감(74bp)보다 알파 손실(127bp)이 크다 — optimizer 는 알파를 더하지 못했다."),
    predeclaration_ambiguity_record = list(
      note = paste("사전 선언 사다리 조항을 문언 그대로 읽으면 M5_BUF40(net_IR 0.0932)이 유일 적격이고,",
                   "optimizer 는 '계열별 최소 feasible B'로 읽어 M2_B50(0.2370)을 택했다.",
                   "두 해석의 결과가 모두 optimization_package 에 실려 있다."),
      forge_action = "채택된 M2_B50 만 측정했다. M5 로 갈아타지 않았다(사후 재해석 금지).",
      b60_not_adopted = paste("B=60 은 net_IR 0.2863 으로 더 높지만 사전 선언이 '게이트를 만족하는 최소 B'였다.",
                              "그 미채택 자체가 B 사다리가 성과로 오염되지 않았다는 직접 증거다.",
                              "forge 도 B=60 으로 갈아타지 않았다."))),

  #-------------------------------------------------- 벤치 basis 귀속 (필수)
  benchmark_basis_attribution = diag$benchmark_basis_attribution,
  benchmark_basis_verdict = paste(
    "상류 PORT_t 0.929 와 forge 권위 PORT_t 0.636 은 **다른 양**이다.",
    "2x2 분해(공통 259개월): 벤치 계열만 교체 -> Δt = -0.358 / 전략 계열만 교체 -> Δt = -0.052.",
    "지배항은 **벤치 계열**(6.9배). 동일 259개월 누적 B_prod 7.934 vs B_alpha 6.271 —",
    "production KOSPI200 이 alpha 자체 cap-w 프록시보다 강해 같은 전략의 활성 t 가 내려간다.",
    "★5/20 forge 라운드와 동일 기전·동일 벤치 수치(7.934 / 6.271)가 재현됐다."),

  #------------------------------------- OOS retention — optimizer 관측 확인
  oos_retention_cross_check = list(
    authoritative_essence = oos,
    essence_splits = S$oos_retention_splits,
    forge_recompute_vs_production_BM = diag$oos_retention$forge_vs_prodBM_median,
    forge_recompute_vs_alpha_BM = diag$oos_retention$forge_vs_alphaBM_median,
    alpha_M1_vs_alpha_BM_reproduced = diag$oos_retention$alpha_M1_vs_alphaBM_median,
    optimizer_proxy_M1 = -0.38305051,
    optimizer_proxy_M2_B50 = -0.425,
    level_confirms = TRUE,
    level_note = paste("모든 basis 에서 OOS retention 이 음(-)이다 (-0.36 ~ -1.23).",
                       "optimizer 진단 '병은 회전이 아니라 후반부 신호 붕괴' 를 권위 층에서 확인한다.",
                       "부기간 활성수익: 2005-14 +11.03%/yr(SR 0.768) -> 2015-19 -3.61% -> 2020-26 -6.53%."),
    direction_confirms = FALSE,
    direction_note = paste(
      "★정직 보고 — optimizer 가 관측한 '회전 제어가 retention 을 악화시킨다'(M1 -0.384 -> M2_B50 -0.425)의",
      "**방향은 forge 재측정에서 재현되지 않았다**. 동일 벤치(alpha BM)·동일 정의로 재계산하면",
      sprintf("M1 %.4f -> forge M2_B50 %.4f 로 오히려 소폭 개선이다.",
              diag$oos_retention$alpha_M1_vs_alphaBM_median, diag$oos_retention$forge_vs_alphaBM_median),
      "M1 proxy(-0.38305)는 forge 가 소수점까지 재현했으므로 불일치는 M2 계열 측정 경로에서 온다:",
      "optimizer 는 자체 월별 엔진, forge 는 일별 정수주 share-based 재구성이다.",
      "**level(깊은 음수)은 두 층이 일치하고, M1->M2 변화의 부호는 층 간 불일치다.**",
      "따라서 '회전 제어가 retention 을 악화시켰다'는 명제는 측정 경로 의존이며 확정 진술이 아니다.")),

  subperiod_decomposition = diag$subperiod,
  regime_decomposition = diag$regime,

  #--------------------------------------------------- 선행 런 대비 좌표
  prior_run_comparison = list(
    prior_strategy_id = "STR_AS_20260612_132740_321992",
    prior_disclosure = "alpha 가 PARTIAL_REPACKAGING 으로 자기신고",
    prior = list(essence_grade = "C", port_t = 0.303, oos_retention = -1.131,
                 calmar = 0.188, turnover_annual_one_way = 6.64),
    current = list(essence_grade = S$grade, port_t = port_t, oos_retention = oos,
                   calmar = calmar, turnover_annual_one_way = gm("Annualized_Turnover")),
    delta = list(port_t = port_t - 0.303, oos_retention = oos - (-1.131),
                 calmar = calmar - 0.188,
                 turnover_annual_one_way = gm("Annualized_Turnover") - 6.64),
    verdict = paste("등급은 **동일 C**. 좌표는 4축 모두 개선 방향이나 어느 것도 문턱을 넘지 않는다:",
                    sprintf("PORT_t 0.303 -> %.3f (문턱 2.95), retention -1.131 -> %.3f (문턱 0.70),", port_t, oos),
                    sprintf("Calmar 0.188 -> %.3f (문턱 0.64), 회전 6.64 -> %.3f (편도).", calmar, gm("Annualized_Turnover")),
                    "개선의 상당부분은 신호 교체(JT1993 -> GH2004 52w-high)와 회전 제어에서 왔고,",
                    "후반부 신호 붕괴라는 병은 그대로다.")),

  #------------------------------------------------------------ PIT / 검출기
  pit = list(
    checklist = list(
      C1 = "PASS — 결정경로에 full-sample 통계 0. 비중은 weights.csv 발행값 as-is.",
      C2 = "PASS — sig_date 신호 -> t+1(get_execution_date) 종가 집행. same-day 선별 0.",
      C3 = "PASS — 같은 기간 집계->적용 없음.",
      C4 = "N/A — 재무제표 직접 소비 0 (alpha 승계).",
      C5 = "N/A — 오버레이 미적용 (S0/S1 금지 준수).",
      C6 = "PASS — full RAWDATA 패널 + alpha PIT 시변 멤버십 승계. ever-member 확장 0.",
      C7 = "PASS(제한적) — detect_lookahead CLEAN. ★아래 양방향 대조로 의미를 좁힘.",
      C8 = "N/A — FM weight 미사용 (alpha 발행 lambda_FM 그대로 승계).",
      C9 = "N/A — VT/DD 오버레이 미적용.",
      C10 = "PASS — 유동성은 alpha 승계 t-1 ADV20. forge 재계산 0.",
      C11 = "N/A — 외부 시차 데이터 미사용.",
      C13 = "PASS — 부호 반전 0.",
      C14 = "N/A — IC 접근 0.",
      C15 = "PASS — Factor DB parquet 직접 load 0 (audit Check 14 실제 실행: lmf=0/align=0 hits)."),
    detect_lookahead_bidirectional = list(
      baseline_clean = pitb$baseline_clean,
      baseline_violations = pitb$baseline_violations,
      positive_control_fired = sprintf("%s/%s", pitb$positive_control_fired, pitb$positive_control_n),
      coverage_probe_fired = sprintf("%s/%s", pitb$coverage_probe_fired, pitb$coverage_probe_n),
      dialect_split_record = pitb$dialect_split_record,
      verdict = paste(
        "양성 대조 5/5 발화(C7a scale / C7b fwd_ret rank / C15 direct parquet / C13 negate / C12 best_sharpe)",
        "-> 검출기는 이 파일 위에서 **살아있다**.",
        "커버리지 반증 0/4 발화(R 음수 shift / 전표본 cov() / 전표본 mean() 재정규화 / 수동 미래 인덱싱)",
        "-> 이 4종은 전부 실제 look-ahead 인데 한 건도 잡히지 않는다.",
        "★따라서 CLEAN 은 **선언 idiom 부재의 증거**일 뿐 PIT 증명이 아니다.",
        "실제 PIT 논거는 구조다: 비중이 forge 밖(weights.csv)에서 결정되고 forge 는 재선택을 하지 않으므로",
        "미래정보가 종목선택에 들어갈 경로 자체가 없다.")),
    detector_defect_recorded = paste(
      "1차 시도에서 Python 방언 idiom 을 양성 대조로 썼더니 0/3 미발화였다.",
      "detect_lookahead 는 is_python 으로 분기하고 PY_* 패턴은 .py 전용이다.",
      "그 결과 **R 분기에는 음수 shift 대응 패턴이 아예 없다** — shift(Close, -1L) 이 미검출이다.",
      "우회하지 않고 기록만 한다(축을 옮기면 양성 대조도 옮겨라).")),

  #------------------------------------------------- schedule fidelity 재도출
  schedule_fidelity = list(
    hook_status = "schedule_fidelity_check.sh 는 .claude/settings.json 미등록 + 필드명 불일치로 무발화 (인계 확인)",
    forge_rederived = fe$schedule,
    weights_csv_unique_dates = 260L,
    executable_sig_dates = 259L,
    density_ratio = 259 / 260,
    density_note = paste("260번째 행(2026-08-28)은 실현수익이 없는 배포 스냅숏이라 t+1 집행일이 없다.",
                         "따라서 실현 측정은 259개월 — optimizer 실측(260/259)과 정합."),
    reselection_events = 0L,
    reselection_evidence = "run_all.R 에 alpha_scores.parquet read 0건 · setorder/head top-N 재선택 0건",
    deploy_extension_days = fe$deploy_extension_days,
    deploy_extension_note = "마지막 리밸 집행일 이후 18거래일은 frozen weights buy-and-hold 로 NAV 연장 측정됨"),

  #-------------------------------------------------------------- 감사 결과
  audit = list(
    total = nrow(AU), pass = sum(AU$status == "PASS"),
    fail = sum(AU$status == "FAIL"), warn = sum(AU$status == "WARN"),
    checks = AU[, .(check_group, check_name, status, details)],
    check14_c15_executed = TRUE, check15_selfscan_executed = TRUE,
    factor_engine_path_wired = TRUE,
    factor_engine_path_note = paste("factor_engine_path 를 처음부터 배선했다 —",
                                    "미배선이면 Check 8/14/15 가 WARN skip 으로 내려앉고 그건 '위반 없음'이 아니라 '미측정'이다."),
    check13_note = "t_plus_1_cadence_consistency = PASS 이지만 details 는 'T+1 미선언, skip' — 문자열 매칭 기반이라 실질 판정은 아니다(기록)"),

  #------------------------------------------------------ pure function 증명
  pure_function = list(
    hash_start = as.list(fe$hash_start), hash_end = as.list(fe$hash_end),
    hash_identical = fe$hash_identical,
    pure_function_violation = FALSE,
    writes_outside_scope = 0L,
    scope = "stage_artifacts/WT_R20260829_007/ 만 씀. WT-R20260829_004 / _006 접근 0."),

  n_trials_cumulative = S$n_trials_cumulative,
  n_trials_basis = "alpha n_trials 1 (chain) + optimizer method_shopping_log$candidates_tried 11 (sweep) = 12",
  selection_type_primary = "sweep",
  dsr = dsr, dsr_gate_applied = S$dsr_gate_applied,

  #-------------------------------------------------------------- 상류 인용
  upstream_citations = list(
    beta_not_a_risk_proxy = paste("β 를 위험 대리로 쓰지 않았다. risk 1급 경고: 무조건부 β 0.737 · Σ-예측 0.441 인데",
                                  "COVID 국면 실측 β 0.946, 평균 pairwise 상관 평시 0.141 -> 위기 0.342,",
                                  "하방 tail dependence 0.545. 시장 노출이 작은 게 아니라 꼬리로 옮겨간 것이다.",
                                  sprintf("forge 실측 β(전기간, 일별) = %.4f 도 같은 이유로 안전 근거가 아니다.",
                                          as.numeric(BC[metric_name == "Beta_to_Benchmark", strategy_value][1]))),
    tail_via_EVT_only = paste("꼬리는 EVT 로만: GPD ξ 0.144 · ES99(월) 0.2123 (risk),",
                              "optimizer 독립 재현 0.216905 · 손익분기 40.5bp (교차층 양성 대조).",
                              sprintf("forge 산출 CVaR_99(일별) %.4f 는 정규 가정 산출이므로 꼬리 판정에 쓰지 않는다.",
                                      gm("CVaR_99"))),
    axis_exposure_is_identity = paste("축 노출은 신호의 정체성이지 회전의 부산물이 아니다:",
                                      "SIZE -0.435->-0.391 · LIQ +0.377->+0.339 · VOL +0.104->+0.070.",
                                      "as-of 스냅숏 VOL -0.963 은 표본평균 +0.070 과 부호가 반대이므로 단일 스냅숏 판정 금지 — 양쪽 병기."),
    D_floor_no_effect = "risk D floor 는 대형·저변동 3종을 월평균 6.06% 상향시키나 채택 M2 는 Σ-free 라 발행 비중 영향 0.",
    RF_O2_thin_margin = "순활성 3.38%/yr vs 2x비용 3.11%/yr = 2.18배. 여유 27bp. optimizer 시행수 11 을 DSR 에 반영했다."),

  handoff = list(
    judge_spawn = FALSE,
    judge_reason = "Judge 는 Grade A 확정 후에만 스폰. 본 라운드 등급 = C.",
    governor_called = FALSE,
    book_state_written = FALSE,
    grade_declared_by_hand = FALSE,
    next_probes = list(
      paste("병은 회전이 아니라 후반부 신호 붕괴다(2005-14 활성 +11.03%/yr -> 2020-26 -6.53%/yr).",
            "다음 축은 비중이 아니라 **국면 조건부 소비**이거나 신호 자체의 재정의여야 한다."),
      paste("벤치 basis 가 PORT_t 격차의 지배항(6.9배)이다. 상류 층이 자체 cap-w 프록시로 보고하는 한",
            "층 간 좌표가 계속 어긋난다 — 상류 basis 를 production BM 으로 통일하는 것이 별도 태스크."),
      paste("detect_lookahead R 분기에 음수 shift 패턴 부재 — 검출기 커버리지 수리 태스크(우회 아님, 기록).")),
    known_issues_carried = list(
      "schema.json:17 task_id 정규식에 v10 접두 R 없음 (미수리 확인, 우회 0)",
      "schema.json wt_type enum 에 reinforcement 없음 (미수리 확인)",
      "schedule_fidelity_check.sh .claude/settings.json 미등록 + 필드명 불일치로 무발화 — forge 가 밀도를 직접 재도출함")),

  artifacts = list(
    run_all = "stage_artifacts/WT_R20260829_007/run_all.R",
    bt_result = "stage_artifacts/WT_R20260829_007/bt_result.rds",
    contract_csv_10component = paste0("stage_artifacts/WT_R20260829_007/",
      c("00_manifest.csv","01_strategy_spec.csv","02_nav.csv","03_period_returns.csv","04_holdings.csv",
        "05_benchmark_returns.csv","06_metrics.csv","07_benchmark_compare.csv","08_rolling_metrics.csv",
        "09_drawdowns.csv","10_audit.csv")),
    diagnostics = "stage_artifacts/WT_R20260829_007/forge_diag.json",
    pit_bidirectional = "stage_artifacts/WT_R20260829_007/forge_pit_bidirectional.json",
    charts = paste0("stage_artifacts/WT_R20260829_007/output/",
                    c("equity_curve.png","annual_returns.png","oos_zoom_chart.png","regime_decomposition.png")))
)

writeLines(toJSON(out, auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null"),
           file.path(STAGE, "authoritative_remeasure.json"))
cat(sprintf("essence_grade = %s | A조건 %d/5 | structural_drawdown = %s | hard_fail = %s\n",
            S$grade, A5_pass, S$structural_drawdown, S$hard_fail))
cat("wrote authoritative_remeasure.json\n")
