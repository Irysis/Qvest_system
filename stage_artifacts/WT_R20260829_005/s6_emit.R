# S6 — alpha_package.json + alpha_validation.json 발행 (AST v1.1 3층)
suppressWarnings(suppressMessages({library(data.table); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
MBX <- file.path(ROOT, "qepm/mailbox/worktask/WT-R20260829_005")

H  <- fromJSON(file.path(MBX, "alpha_hypothesis.json"), simplifyVector = FALSE)
F1 <- fromJSON(file.path(OUT, "s2_fal1.json"), simplifyVector = FALSE)
PW <- fromJSON(file.path(OUT, "s3_power.json"), simplifyVector = FALSE)
C4 <- fromJSON(file.path(OUT, "s4_candidate.json"), simplifyVector = FALSE)
S5 <- readRDS(file.path(OUT, "s5_objects.rds")); DG <- S5$diag; AV <- S5$AV

## ── AST (dual dialect: args + children — 검증기/스키마 양쪽 순회 보장) ──────
nd <- function(op, ...) { a <- list(...); list(op = op, args = a, children = a) }
## 스칼라 파라미터는 children 이 아니라 노드 속성으로 (ast_verify 계약: TS_MEAN.window / TS_LAG.k)
nd_p <- function(op, ..., .p = list()) { a <- list(...); c(list(op = op, args = a, children = a), .p) }
lf_val <- list(leaf = "REGISTRY", factor = "V01_BM")
lf_mom <- list(leaf = "SPECIAL_OP",
  escape_contract = list(escape_type = "SPECIAL_OP",
    op_code_path = "stage_artifacts/WT_R20260829_005/s1_panel.R (MOM 블록 — 캘린더월 복리 log(1+mr), 형성창 t-2..t-7; 기저 stage_artifacts/replication/_pilot/fe_jt1993_momentum.R 승계)",
    walk_forward = TRUE),
  op_code_path = "stage_artifacts/WT_R20260829_005/s1_panel.R", walk_forward = TRUE)
lf_k200 <- list(leaf = "FIELD", group_id = "A1_RAWDATA_OHLCVS_daily", field = "K200")
lf_kq   <- list(leaf = "FIELD", group_id = "A1_RAWDATA_OHLCVS_daily", field = "KQ150")
lf_vol  <- list(leaf = "FIELD", group_id = "A1_RAWDATA_OHLCVS_daily", field = "Vol")
lf_cls  <- list(leaf = "FIELD", group_id = "A1_RAWDATA_OHLCVS_daily", field = "Close")

ast_value <- nd("CS_RANK", lf_val)
ast_mom   <- nd("CS_RANK", lf_mom)
## 고정 50/50 랭크평균: ADD(rank_v, rank_m) 은 (rank_v+rank_m)/2 와 순서동치(양의 상수배) —
## 자유 파라미터 0 을 식 자체로 표현한다(가중 탐색 불가 = 설계 combination_rule 강제).
ast_liq   <- nd_p("TS_MEAN", nd_p("TS_LAG", nd("MUL", lf_vol, lf_cls), .p = list(k = 1L, unit = "d")),
                  .p = list(window = 20L))
ast_gate  <- nd("ADD", lf_k200, lf_kq)
ast_combo <- nd("WHERE", nd("ADD", ast_value, ast_mom), nd("ADD", ast_gate, ast_liq))

factors <- list(
  list(factor_id = "F1_value_BEME_contemporaneousME", ast = ast_value, role = "core_signal",
       restatement_exposure = 1L),
  list(factor_id = "F2_momentum_6_1_skip1", ast = ast_mom, role = "core_signal",
       restatement_exposure = 1L),
  list(factor_id = "F3_universe_liquidity_gate", ast = nd("ADD", ast_gate, ast_liq),
       role = "eligibility_gate", restatement_exposure = 1L))

self_pit <- list(performed = TRUE, leaves_checked = list(
  list(leaf = "REGISTRY:V01_BM", restatement_prone = TRUE,
       availability_rule = "regulatory: quarterly+45d ; annual = 익년 3/31 (factor_registry V01_BM availability, C4 2026-07-25 확정). load_month_factors() 가 Factor_Date <= sig_date 슬라이스를 강제하고 align_factor_direction 이 Usable_Date <= sig_date 확장창 IC 로 부호를 정한다(C14/C13/C15)."),
  list(leaf = "SPECIAL_OP:momentum_6_1", restatement_prone = FALSE,
       availability_rule = "코드 경로 escape — 형성창 t-2..t-7 월 수익만 입력(shift 로 과거 참조). 당월·t-1 월 미참조."),
  list(leaf = "A1_RAWDATA_OHLCVS_daily:K200", restatement_prone = FALSE,
       availability_rule = "fixed t1 — 월말 시변 멤버십 스냅샷(C6 survivorship: 각 sig_date 의 당시 편입 명부만)"),
  list(leaf = "A1_RAWDATA_OHLCVS_daily:KQ150", restatement_prone = FALSE, availability_rule = "fixed t1 — 동일"),
  list(leaf = "A1_RAWDATA_OHLCVS_daily:Vol", restatement_prone = TRUE,
       availability_rule = "fixed t1 — 20일 평균 거래대금은 t-1 까지만(C10, build_adv20_t1)"),
  list(leaf = "A1_RAWDATA_OHLCVS_daily:Close", restatement_prone = TRUE,
       availability_rule = "fixed t1 — 동일 (수정주가 원장이라 액면분할·배당 시 과거 재작성 = restatement_prone)")),
  verdict = "warn_restatement",
  notes = paste("V01_BM 은 registry restatement_prone=true(재무 정정) 이고 RAWDATA 는 수정주가 원장이다.",
    "본 라운드는 단일 스냅샷에서 전 산출을 동시에 냈으므로 내부 정합은 같은 vintage 위에 있다.",
    "다중 라운드 비교 시 pin_cache 의무(measurement-graduation §7). 재무 리프의 C4 급소:",
    "fundamental_merged 의 xlsx 경로가 Q4 를 일률 +45d(익년 ~2/14)로 잡아 연간 3/31 대비 공격적이라는",
    "기지 결함(pit.md C4 각주)이 V01_BM 상류에 존재한다 — 본 라운드가 만든 결함이 아니며 수리 대상으로 승계 보고한다."))

## ── 벡터 ───────────────────────────────────────────────────────────────────
alpha_vector      <- setNames(as.list(round(AV$alpha_hat, 8)), AV$Ticker)
alpha_lb_vector   <- setNames(as.list(round(AV$alpha_lb,  8)), AV$Ticker)
confidence_vector <- setNames(as.list(round(AV$confidence, 6)), AV$Ticker)

cand <- C4$candidate
fac_specs <- list(
  list(factor_family = "Value", proxy = "BE/ME (V01_BM)",
       formula = "TotalEquity(Factor_Date <= sig_date) / MarketCap(sig_date, contemporaneous ME)",
       lag_rule = "quarterly +45d ; annual = 익년 3/31 (C4)",
       winsorization = "factor_db 표준(Z_Score 산출 시 적용) — 본 단계 추가 winsorize 없음",
       neutralization = "시장-내(K200/KQ150) 백분위 랭크 — sector/size 중립화 미적용(진단으로만 병기)",
       economic_rationale = "기관 벤치마크-추종 배분이 장부가 대비 저평가·지수비중 낮은 종목의 소외를 유지시킨다(설계 mechanism.agent ②). 공매도 제약으로 롱 사이드에만 잔존.",
       weight_theta = 0.5, redundancy_cluster_id = "value_cluster (factor_registry V01_BM labels.correlation_group)",
       references = c("Asness-Moskowitz-Pedersen 2013 JF 68(3):929-985 §I.B p.936",
                      "Fama-French 1992/1993", "Lakonishok-Shleifer-Vishny 1994"),
       source = "db_existing"),
  list(factor_family = "Momentum", proxy = "6-1 (J=6 형성 · 최근 1개월 skip)",
       formula = "sum_{k=2..7} log(1 + r_{t-k})  (캘린더월 복리)",
       lag_rule = "t-2..t-7 월만 (당월·t-1 월 미참조)",
       winsorization = "없음 (랭크 변환이 이상치를 흡수)",
       neutralization = "시장-내(K200/KQ150) 백분위 랭크",
       economic_rationale = "개인 추세추종 순매수 군집의 과소반응→과잉반응 경로(설계 mechanism.agent ①). KR 낮은 individualism 이 프리미엄을 약화시킨다는 국가패널 진단(CTW2010)이 기저 F 의 배경.",
       weight_theta = 0.5, redundancy_cluster_id = "momentum_cluster (factor_registry M02_Mom_6_1)",
       references = c("Jegadeesh-Titman 1993 JF 48(1):65-91 (기저)",
                      "Asness-Moskowitz-Pedersen 2013 §I.B p.936 (MOM2-12 원정의 — 지평 민감도로 병기)"),
       source = "db_derived"))

diagnostics <- list(
  canonical_port_t_nw_lag3 = cand$portfolio_alpha_t_nw_lag3,
  canonical_port_t_pvalue  = cand$portfolio_alpha_t_pvalue,
  canonical_n_months = cand$n_months,
  metric_type = "canonical_screen",
  metric_type_note = "canonical_screen_bt() 실측. 판정 권위 아님 — authoritative = forge build_bt_result + essence_score.R.",
  beta_controlled_alpha_ann = cand$beta_controlled_alpha$alpha_ann,
  beta_controlled_alpha_t   = cand$beta_controlled_alpha$t_alpha,
  beta = cand$beta_controlled_alpha$beta, beta_t = cand$beta_controlled_alpha$t_beta,
  beta_contribution_ann = cand$beta_controlled_alpha$beta_contrib_ann,
  beta_reading = "beta 0.869 < 1 — measurement-graduation §2 거울상: PORT_t 가 alpha 를 **과소** 표시한다(활성수익 = alpha + (beta-1)E[bm], 후항이 음수). 알파 존재 주장은 t(alpha) 로만 한다.",
  information_ratio = cand$information_ratio, net_sr_active = cand$net_sr_active,
  mean_active_net_ann = cand$mean_active_net_ann,
  rank_ic = DG$rank_ic, icir = DG$icir, rank_ic_t_nw_lag3 = DG$ic_t_nw_lag3,
  harvey_t_stat = DG$harvey_t_stat,
  rank_ic_vs_portfolio_alpha_t_note = "rank-IC t(3.798)와 portfolio-alpha t(1.196)는 다른 양이다 — 후자가 롱온리 top-25 의 실현 초과수익 권위(Cycle 2 교훈, measurement-graduation §2). 본 후보는 그 전이 벽의 전형이다.",
  monotonicity = DG$monotonicity, decile_profile = DG$decile_profile,
  subperiod_stability = DG$subperiod_stability, subperiod = DG$subperiod,
  post_neutralization_ic = DG$post_neutralization_ic,
  post_neutralization_spec = DG$post_neutralization_spec,
  turnover_proxy = cand$turnover_annual, turnover_annual = cand$turnover_annual,
  n_names_max = cand$n_names_max, n_names_median = cand$n_names_median,
  kq150_share = cand$kq150_share,
  total_return_coords = cand$total_return_coords, benchmark_coords = cand$benchmark_coords,
  diag_ew_universe = cand$diag_ew_universe, diag_cap_tier = cand$diag_cap_tier,
  oos_retention_approx = C4$oos_retention_approx,
  deflated_sharpe_ratio = NULL,
  dsr_note = "selection_type='chain' (1논문 1스펙, 가중 탐색 0, 열거 trial 집합 없음) — DSR 게이트 부적용(measurement-graduation §3). n_trials=1.",
  liq_ruler = cand$liq_ruler, liq_ruler_source = cand$liq_ruler_source)

pkg <- list(
  task_id = "WT-R20260829_005",
  strategy_id = "AMP2013_valmom_rankavg_top25",
  as_of_date = DG$as_of_date, forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  pit = list(sig_date = DG$as_of_date,
             decision_ts = as.character(as.Date(DG$as_of_date) + 1L),
             timing_convention = paste(
               "점수는 신호월 t 의 월말 종가 기준으로 산출되고 포트폴리오는 **홀딩월 t+1 시작에** 편성된다.",
               "따라서 의사결정 시각은 t 가 아니라 t+1 일이며, t 시점 자료(유니버스 멤버십 K200/KQ150 스냅샷 포함)는",
               "그 시점에 이미 가용하다. period_returns 의 date 컬럼은 **신호월 t** 라벨이고 수익은 t+1 월의 실현치다.",
               "decision_ts 를 t 로 두면 ast_verify 의 t1 규칙(avail = t+1d)이 당일 멤버십을 미래참조로 표시하는데,",
               "그것은 코드가 미래를 본 것이 아니라 decision_ts 라벨이 실제 편성시점보다 하루 이른 데서 온다.")),
  hypothesis = list(
    statement = H$selected$hypothesis_description,
    mechanism = H$selected$mechanism,
    falsification = H$selected$falsification$observables[[1]]$reject_if,
    falsification_full = H$selected$falsification,
    regime_scope = H$selected$regime_scope,
    inheritance_note = "mechanism / falsification / regime_scope 는 alpha-hypothesis 승계분이며 재작성하지 않았다(Charter 원칙 8 No Silent Override). 이의는 challenge_flags 에 기록."),
  ast = ast_combo,
  factors = factors,
  combination_rule = "rank_average",
  verdict = "designed",
  self_pit_check = self_pit,
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  alpha_lower_bound_vector = alpha_lb_vector,
  alpha_vector_note = paste(
    "alpha_hat_{i,t} = lambda_t * z(score)_{i,t}. lambda_t = **t 이전 월 단면 기울기의 확장창 평균**",
    "(Fama-MacBeth 1단계 · burn-in 36개월 · 당월 단면 미사용 = PIT C1/C2).",
    "단위 = 기대 1개월 **활성**수익(벤치 대비, 소수). alpha_lower_bound_vector = alpha_hat - 1.0*SE(alpha_hat)",
    "(uncertainty-aware, Liao et al. 2025 RFS 취지 — 점추정 아닌 하한 병기). as_of 는 forward 수익 패널의 종점월이다."),
  signal_matrix_ref = "stage_artifacts/WT_R20260829_005/alpha_scores.parquet",
  factor_specs = fac_specs,
  diagnostics = diagnostics,
  selection_objective = "canonical_port_t",
  n_trials = 1L, n_iterations = 1L, selection_type = "chain",
  alpha_discovery_count = 1L,
  universe_and_timing_contract = list(
    universe = "KOSPI200 ∪ KOSDAQ150 (PIT 시변 멤버십, C6)",
    universe_label = "KR_top342", median_names_per_month = 340,
    liquidity_filter = "20일 평균 거래대금(t-1) >= 2e8 KRW — 랭킹 前 적용",
    rebalance = "monthly (월말 시그널 -> 익월 보유)",
    signal_timing = "score at month-end t (sig_date) -> holding month t+1. period_returns 의 date 컬럼 = **신호월 t** 라벨.",
    cost_model = "v2.4_kr_retail_15bps (one-way, delta 기반)",
    long_only = TRUE, max_names = 25L, weight_sum = 1.0, per_name_cap = "없음 (v10)",
    n_months = cand$n_months, window = "2005-01-31 ~ 2026-07-31"),
  step0_A_value_definition_verified = list(
    source = "AMP2013 원문 PDF §I.B p.936-937 직접 판독(pdftotext)",
    verbatim_stocks = "For individual stocks, we use the common value signal of the ratio of the book value of equity to market value of equity, or book-to-market ratio, BE/ME ... Book values are lagged 6 months to ensure data availability to investors at the time, and the most recent market values are used to compute the ratios.",
    verbatim_five_year = "For commodities, we define value as the log of the spot price 5 years ago (actually, the average spot price from 4.5 to 5.5 years ago), divided by the most recent spot price ... Similarly, for currencies ... For bonds, we use the 5-year change in the yields of 10-year bonds",
    resolution = "5년 시점 정의는 commodities/currencies/bonds 전용이며 개별주식에는 해당하지 않는다. WT 지시문 전제는 정정됐고 설계 에이전트의 정정이 원문과 일치한다. 5년 lag 로 구현했다면 value 가 아니라 장기반전(DeBondt-Thaler 1985 계열) 팩터가 됐을 것이다.",
    implemented = "BE = TotalEquity, Factor_Date <= sig_date (KR C4 규약 = quarterly +45d / annual 익년 3/31 — 논문의 6개월 lag 보다 보수적이므로 고정 축이 이긴다). ME = contemporaneous(sig_date 시가총액). = V01_BM 정의와 동일.",
    paper_assumption_adjusted = "book lag: 논문 6M -> KR C4 규약(더 보수적). momentum: 논문 MOM2-12 -> 기저 승계 6-1 을 primary 로, MOM2-12 를 지평 민감도로 병기(부호 일치 확인)."),
  step0_B_mandatory_prior_run_disclosure = list(
    obligation = "설계 mandatory_prior_run_disclosure — 병기 없이 결합 성과만 새로 보고하면 settled-negative 재포장이다.",
    prior_runs = list(
      list(strategy_id = "STR_AS_20260605_221011_31932", title = "STR_valmom_AMP2013", date = "2026-06-05",
           spec = "value(BM)+momentum(12-1) z-combo 50/50 · ~20종 EW · K200∪KQ150 · 월간",
           grade = "F", grade_basis = "proxy_diagnostic (run_hurdle_gate) — 2026-05-31 DEMOTED. 권위 등급(essence_score.R) 미산출.",
           sharpe = 0.825, cagr_pct = 20.76, mdd_pct = 60.4, ir = 0.653, calmar = 0.344,
           l_code = "L-AS-20260605_221011_31932"),
      list(strategy_id = "STR_AS_20260610_213712_20276", title = "valmom_AMP2013_winz_smoke", date = "2026-06-10",
           spec = "동일 50/50 composite — winsorize DB 재측정 스모크",
           grade = "F", grade_basis = "proxy_diagnostic — DEMOTED. 권위 등급 미산출.",
           sharpe = 0.799, cagr_pct = 20.09, mdd_pct = 60.72, ir = 0.628, calmar = 0.331,
           oos_retention = 0.757, turnover_ann_pct = 208.8, ic_mean = 0.0284, icir = 0.203,
           ff3_alpha_ann_pct = 7.79, ff3_alpha_t = 2.235, fm_lambda_nw_t = 3.347,
           fail_reason_then = "MDD 60.7% > 45% (당시 규칙 — v9.21 에서 MDD 직접 문턱 폐기, 현행 위험 축은 Calmar 하나)",
           fmt = c("FMT-01 구조적 MDD", "FMT-04 국면맹목 MDD>35% ∧ BM상관 0.80",
                   "FMT-07 발표후 감쇠 활성SR pre2017 1.15 -> post2017 -0.11"),
           l_code = "L-AS-20260610_213712_20276")),
    self_report_repackaging = list(
      this_round = list(sharpe_total = cand$total_return_coords$sr_total,
                        cagr_pct = 100*cand$total_return_coords$cagr,
                        mdd_pct = 100*cand$total_return_coords$mdd,
                        calmar = cand$total_return_coords$calmar,
                        oos_retention_median = C4$oos_retention_approx$median,
                        turnover_ann_x = cand$turnover_annual),
      verdict = "NOT_NUMERICALLY_IDENTICAL — 그러나 형태는 겹친다. 좌표가 선행 2건보다 **낮다**(CAGR 13.4% vs 20.1~20.8% · SR 0.62 vs 0.80~0.83 · Calmar 0.253 vs 0.331~0.344 · OOS retention -0.561 vs 0.757). 구성 차이 = 시장-내 pct-rank 결합 · 25종(선행 ~20종) · 유동성 2e8 사전필터 · 2005~2026 창 · 6-1 모멘텀(선행 12-1). 성과 축에서 새 발견은 없다 — 본 라운드의 산출 가치는 FAL-1 전제검정과 권위 경로 좌표에 있다.",
      honesty_note = "선행 런의 CAGR/SR 이 더 높다는 사실을 숨기지 않는다. 결합 축이 기저를 개선했다는 주장은 하지 않는다.")),
  step0_C_preregistered_power_contract = PW,
  preregistered_verdicts = list(
    FAL_1_negative_correlation_premise = list(
      status = "REPORTED_BEFORE_PERFORMANCE (설계 handoff 착수순서 (1) 준수)",
      envelope = "포트폴리오 envelope 미적용 — 팩터 신호·수익 수준 통계(설계 premise_test_exemption)",
      signal_level = list(rho_a_contemporaneousME = F1$verdict$rho_a_signal,
                          rho_b_pricelaggedME = F1$verdict$rho_b_signal,
                          verdict = F1$verdict$signal_level),
      return_level_paper_basis = list(rho_a = F1$verdict$rho_a_return, rho_b = F1$verdict$rho_b_return,
                          ratio = F1$verdict$ratio_return, verdict = F1$verdict$return_level,
                          paper_japan_factor = -0.64),
      tail_cuts = F1$signal_level$tail_cuts,
      conclusion = "AMP2013 이 8개 시장에서 -0.43~-0.65 로 실측한 value-momentum 음(-)상관은 KR 에서 **구성 아티팩트**다. 가격을 공유하지 않는 사양(b)에서 신호수준 상관은 부호가 뒤집혀 +0.085 이고(전제 완전 기각 조건 rho_b >= 0 충족), 수익수준 상관은 -0.466 -> -0.011 로 소멸한다(|rho_b|/|rho_a| = 0.024 << 0.5). 즉 결합의 근거로 인용된 분산효과는 ME 분모와 momentum 분자가 공유하는 가격항의 산술 귀결이다.",
      disposition = "결합에서 어떤 개선이 나오든 'AMP2013 의 분산효과가 KR 에서 재현됐다'로 보고할 수 없다 — 개선분은 construction_effect 로 재라벨한다(설계 FAL-1 reject_if 그대로)."),
    FAL_2_treatment_delivery = list(status = "CANCELLED_BY_COORDINATOR_2026-08-29",
      note = "arm 대비 폐지 지시로 보유중첩 처치전달 확인은 취소됐다. 본 라운드는 단일 후보 측정이므로 대조군이 없다."),
    FAL_3_funding_liquidity = list(status = "NOT_RUN — 설계가 비구속 probe 로 강등(저자 p.931 단일시장 식별불가 명시). 취소된 arm 배터리와 함께 미실행.",
      disposition = "underpowered_by_authors_own_statement"),
    axis_A_alpha_level = list(status = "NOT_TESTABLE_UNDER_SINGLE_CANDIDATE_DISCIPLINE",
      note = "value 단독 대조 arm 이 폐지되어 '증분' 을 정의할 대상이 없다. 사전등록 문구는 고치지 않았고 미실행으로 기록한다(사후 축 교체 아님)."),
    axis_B_risk_adjusted = list(status = "NOT_TESTABLE_UNDER_SINGLE_CANDIDATE_DISCIPLINE", note = "동일 사유."),
    axis_C_gate_relevant_descriptive = list(status = "REPORTED",
      calmar = cand$total_return_coords$calmar, threshold_grade_A = 0.64,
      prior_runs_calmar = c(0.331, 0.344),
      ex_ante_prediction = "설계가 측정 전에 '1계층 결합은 Calmar 를 고치지 못한다'고 선언했다(boundary_rationale ③ — 논문의 분산축소가 beta~0 롱숏 위에서 측정됐고 롱온리 top-25 는 beta~1 을 유지하므로 비상속).",
      outcome = "적중. Calmar 0.253 으로 문턱 0.64 는 물론 선행 런 0.331/0.344 에도 못 미친다. 사후 발견으로 보고하지 않는다.")),
  layer_boundary_selfcheck = list(
    tripwire_1_two_or_more_module_ids_as_input = FALSE,
    tripwire_2_final_return_is_weighted_sum_of_two_portfolio_returns = FALSE,
    tripwire_3_weights_are_function_of_regime_label = FALSE,
    conclusion = "3항 전부 미해당 — 1계층(점수수준 결합 · 단일 신호공간 · 단일 top-25 · 단일 수익시계열)."),
  discipline_change_2026_08_29 = list(
    directive = "도훈 지시 — arm 배터리 폐지, 한 시도 = 실투형 후보 하나.",
    cancelled = c("결합 vs value 단독 증분 대비(1급 성과 검정)", "FAL-2 보유중첩 처치전달",
                  "세션이 얹던 무신호 대조", "기존 최상위 2건 대비 상관", "논문 식 (3) COMBO 참조 arm",
                  "EW-유니버스·cap-tier 의 arm 별 산출"),
    retained = c("Step 0 (A) value 정의 원문 재확인", "Step 0 (B) 선행 런 좌표 병기",
                 "Step 0 (C) 사전 검정력(일본 factor basis dSR +0.11)", "음(-)상관 전제 검정",
                 "PIT C1~C15", "period_returns 저장"),
    design_points_that_no_longer_hold = "설계의 preregistered_primary axis_A/axis_B 는 **대조 arm 을 전제로 정의된 검정**이라 단일 후보 규율 아래서는 정의 자체가 성립하지 않는다. 문구를 고치지 않고 status='NOT_TESTABLE_UNDER_SINGLE_CANDIDATE_DISCIPLINE' 로 기록했다(No Silent Override). EW-유니버스·cap-tier 는 canonical_screen_bt 가 **내부에서** 산출하는 값이라 폐지 대상(arm 별 별도 산출)에 해당하지 않아 그대로 실었다."),
  challenge_flags = list(
    "[HIGH · 1급 전제 붕괴] FAL-1 이 AMP2013 음(-)상관 전제를 KR 에서 기각했다 — 신호수준 rho_b = +0.085(부호 반전), 수익수준 rho_b = -0.011(소멸, |rho_b|/|rho_a| = 0.024). 두 판정 모두 설계가 사전등록한 기각선을 넘는다. 결합의 논문적 근거가 KR 에서는 성립하지 않으므로 본 후보는 'AMP2013 의 KR 이식' 이 아니라 '두 팩터의 동일가중 랭크결합' 으로만 서술해야 한다.",
    "[HIGH · 검정력] Step 0 (C) ratio = 0.166 · 기대 t = 0.466 · 검정력 6.8%. 착수금지선(0.15)은 넘었으나 조건부 구간이며 **미결이 최빈 결말**이다. 비유의 결과를 '효과 없음' 으로 승격 금지.",
    "[HIGH · OOS] anchored 3분할 활성 SR retention = -0.485 / -0.561 / -0.626, 중앙값 -0.561. oos_retention 하한 0.5 를 **부호부터** 밑돈다 — forge 층에서 hard FAIL 이 예상된다. 선행 런의 FMT-07(활성 SR pre2017 1.15 -> post2017 -0.11)이 본 후보에서도 재현되는 지문이다.",
    "[HIGH · cap-tier] 보유 비중의 92.7% 가 OTHER tier(MEGA top-10·MID 11-30 외). 양(+) 좌표가 신호인지 소형주 노출인지 본 라운드는 분리하지 못했다 — 무신호 대조가 지시로 취소됐기 때문이다. 이 미분리를 결과 해석에 반드시 달 것.",
    "[MEDIUM · RF-A? 전이 벽] rank-IC t 3.798 인데 portfolio-alpha t 1.196 — 횡단면 순위력이 롱온리 top-25 실현 초과수익으로 전이되지 않는 전형(measurement-graduation §2). 등급 판정은 후자 계열로만.",
    "[MEDIUM · C4 상류 결함 승계] fundamental_merged 의 xlsx 경로가 Q4 를 일률 +45d(익년 ~2/14)로 잡아 연간 3/31 규약보다 공격적이다(pit.md C4 각주 기지 항목). V01_BM 이 이 원장을 쓰므로 본 후보도 그 노출을 승계한다 — 본 라운드가 만든 결함이 아니며 수리는 하네스 소관.",
    "[MEDIUM · beta<1 거울상] beta 0.869 이라 PORT_t(1.196)가 t(alpha)(1.792)보다 **작다**. 알파 존재 서술은 t(alpha) 로만 하고, 게이트 판정은 PORT_t 로 한다(두 규칙이 다르다).",
    "[대안 보관 C5] value 잔차화 모멘텀 — FAL-1 이 두 축의 음상관을 기계적 산물로 판정했으므로, '직교화된 momentum 을 value 코어에 가산' 하는 C5 는 이제 **가장 직접적인 후속**이다(기계적 공유항을 제거한 뒤에도 momentum 이 기여하는가). 6/20 1순위.",
    "[설계 이의 · No Silent Override] 하달 1급(axis_A, alpha 수준)은 AMP2013 이 KR-유사 시장(일본)에서 하지 않은 주장을 검정한다(일본 함의 증분 -6.2%p). 설계가 이 이의를 기록했고 본 에이전트도 문구를 고치지 않았다.",
    "[병렬 WT] WT-R20260829_004/006/007 병렬 진행 — 본 에이전트는 005 mailbox 와 stage_artifacts/WT_R20260829_005 만 기록했다."),
  handoff_to_risk = list(
    alpha_vector_units = "expected 1M active return (decimal, 벤치 = KOSPI200 total return)",
    coverage = length(alpha_vector), confidence_range = c(min(AV$confidence), max(AV$confidence)),
    full_panel = "stage_artifacts/WT_R20260829_005/alpha_scores.parquet (Date x Ticker x score/alpha_hat/alpha_se/alpha_lb/confidence, 259 months)",
    period_returns = "stage_artifacts/WT_R20260829_005/period_returns_production.csv (signal_date/signal_ym/holding_ym/ret_net/benchmark_ret/active_net)",
    covariance = "미산출 — Risk Agent 소관(역할 경계)",
    weights = "미산출 — Optimizer Agent 소관(역할 경계)",
    chain_obligation = "체인 완주 의무(도훈 2026-08-29): 본 라운드의 음성 판정은 체인을 멈추는 근거가 아니다. risk -> optimizer -> forge 로 진행해 essence 등급을 발행할 것."),
  validation_ref = "stage_artifacts/WT_R20260829_005/alpha_validation.json")

write_json(pkg, file.path(MBX, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, digits = 10, na = "null")

val <- list(wt_id = "WT-R20260829_005", generated_at = as.character(Sys.time()),
  step0_A = pkg$step0_A_value_definition_verified,
  step0_B = pkg$step0_B_mandatory_prior_run_disclosure,
  step0_C_power_contract = PW,
  fal1_premise_test_full = F1,
  candidate_measurement_full = C4,
  signal_diagnostics_full = DG,
  preregistered_verdicts = pkg$preregistered_verdicts,
  discipline_change = pkg$discipline_change_2026_08_29,
  layer_boundary_selfcheck = pkg$layer_boundary_selfcheck,
  challenge_flags = pkg$challenge_flags,
  scripts = c("s1_panel.R","s2_fal1.R","s3_power.R","s4_candidate.R","s5_alpha.R","s6_emit.R","s7_astverify.R"))
write_json(val, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = 10, na = "null")

source(file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(task_id = "WT-R20260829_005", package_type = "alpha_package",
  method_selected = "AMP2013 value(BE/ME contemporaneous ME) + momentum(6-1) 시장-내 pct-rank 고정 50/50 랭크결합 · 단일 top-25 롱온리",
  input_file_paths = c(file.path(OUT, "alpha_scores.parquet"), file.path(OUT, "alpha_validation.json"),
                       file.path(OUT, "s2_fal1.json"), file.path(OUT, "s3_power.json"),
                       file.path(OUT, "s4_candidate.json")))
cat(sprintf("[S6] emitted alpha_package.json (alpha_vector %d) + alpha_validation.json\n", length(alpha_vector)))
