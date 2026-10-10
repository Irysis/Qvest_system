#==============================================================================
# prereg_l2v1.R — PR-L2-ROLESLEEVE-V1 사전등록 (평가 창 계산 전 · rf_prereg.R 스키마 · 초안 → 등록 시도)
#
# 순서: ①v1 산출물 부재 확인(결과 뒤 사전등록 금지) ②코드·설계·입력 지문(pins — 라벨 빌더·MC2·엔진·점검·드라이버·판정·lib) ③hypothesis_index
#       조회(읽기 전용) ④1계층 표식 상속 계수(원장 읽기 전용) ⑤초안 rf_prereg_write(kind="draft") — 덮어쓰기 거부·sha256 색인
#       ⑥등록 단계 검증 → 차단 사유 ⑦rf_prereg_register 시도(차단이면 쓰지 않고 실패) ⑧시도 기록 prereg_registration_attempt_v1.json
# 이 스크립트 뒤에만: build_l2v1_labels.R → mc2_l2v1.R → (PASS 시) sanity_l2v1.R → run_l2_v1.R → verdict_l2v1.R
# 실행: 이 디렉터리에서 Rscript --no-save -e 'source("prereg_l2v1.R")'
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.find_root <- function() {
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd(), dirname(getwd()), dirname(dirname(getwd())))) {
    if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))) return(normalizePath(p, winslash = "/"))
  }
  stop("[prereg_l2v1] 프로젝트 루트 미발견")
}
ROOT <- .find_root(); L2DIR <- file.path(ROOT, "04_Research/l2_role_rotation")
PREREG_ID <- "PR-L2-ROLESLEEVE-V1"
ATTEMPT <- file.path(L2DIR, "prereg_registration_attempt_v1.json")
if (file.exists(ATTEMPT)) stop("[prereg_l2v1] 이미 실행됐다(초안·등록 시도 기록 존재): ", ATTEMPT)
results_present <- c(file.exists(file.path(L2DIR, "work/l2v1_defensive_labels.parquet")), file.exists(file.path(L2DIR, "verdict_v1/mc2_v1.json")),
                     dir.exists(file.path(L2DIR, "sanity_v1")),
                     dir.exists(file.path(L2DIR, "runs_v1")) && length(list.files(file.path(L2DIR, "runs_v1"), pattern = "authoritative_remeasure", recursive = TRUE)) > 0L)
if (any(results_present)) stop("[prereg_l2v1] v1 산출물이 이미 있다 — 결과 뒤 사전등록 금지")
source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_prereg.R"))
cfg <- rf_prereg_config(ROOT)
sha <- function(p) digest::digest(file = p, algo = "sha256")
rel <- function(p) sub(paste0("^", ROOT, "/"), "", normalizePath(p, winslash = "/"))
now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
DESIGN <- fromJSON(file.path(L2DIR, "l2v1_design.json"), simplifyVector = FALSE)
pin <- function(p) list(path = rel(p), sha256 = sha(p))
L <- function(f) file.path(L2DIR, f); I <- function(f) file.path(ROOT, f)
PINS <- list(
  design = pin(L("l2v1_design.json")), lib = pin(L("lib_l2v1.R")), labels_builder = pin(L("build_l2v1_labels.R")), mc2 = pin(L("mc2_l2v1.R")),
  engine = pin(L("allocator_engine_v1.R")), sanity = pin(L("sanity_l2v1.R")), driver = pin(L("run_l2_v1.R")), verdict = pin(L("verdict_l2v1.R")),
  prereg_builder = pin(L("prereg_l2v1.R")),
  runner = pin(I("02_Infrastructure/alpha_search/run_paper_replication.R")), harness = pin(I("02_Infrastructure/replication/replication_harness.R")),
  contract_beta_controlled_alpha = pin(I("02_Infrastructure/contracts/beta_controlled_alpha.R")),
  contract_backtest_result = pin(I("02_Infrastructure/contracts/backtest_result_contract.R")),
  contract_strategy_role = pin(I("02_Infrastructure/contracts/strategy_role.R")), contract_essence = pin(I("02_Infrastructure/contracts/essence_score.R")),
  rf_diversification_gate = pin(I("02_Infrastructure/reinforcement/rf_diversification_gate.R")), rf_prereg = pin(I("02_Infrastructure/reinforcement/rf_prereg.R")),
  lookahead_detector = pin(I("02_Infrastructure/validation/lookahead_detector.R")),
  v0_candidates = pin(L("work/l2v0_candidates.csv")), v0_holdings_panel = pin(L("work/l2v0_module_holdings.parquet")),
  asof_roles = pin(L("asof_roles.parquet")), msm_asof_daily = pin(L("work/msm_asof_daily.parquet")),
  benchmark_at_lock = pin(I(".cache/benchmark.parquet")), strategy_role_cfg = pin(I("06_Registry/strategy_role.json")),
  rf_diversification_cfg = pin(I("06_Registry/rf_diversification_gate.json")), reinforce_program = pin(I("06_Registry/reinforce_program.json")),
  predictor_selection_IS = pin(L("predictor_selection_IS.json")))
cand <- fread(L("work/l2v0_candidates.csv")); setorder(cand, member_id)
SERIES <- lapply(seq_len(nrow(cand)), function(i) { p <- file.path(ROOT, cand$series_dir[i], "03_period_returns.csv"); list(member_id = cand$member_id[i], path = rel(p), sha256 = sha(p)) })
series_digest <- digest::digest(paste(vapply(SERIES, function(z) paste(z$member_id, z$sha256), ""), collapse = "\n"), algo = "sha256", serialize = FALSE)

# ── 1계층 표식 상속(v0 와 같은 방법 · 원장 읽기 전용 · 진단) ─────────────────────────
led <- fromJSON(I("06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
flag_hits <- setNames(vector("list", nrow(cand)), cand$member_id)
.walk <- function(o) {
  if (is.list(o)) {
    keys <- c("run_id", "strategy_id", "base_id", "artifacts", "out_dir", "artifact_dir")
    vals <- unlist(lapply(keys, function(k) if (is.character(o[[k]]) && length(o[[k]]) == 1L) o[[k]] else NULL))
    fl <- o$vintage_flags %||% o$flags %||% o$lineage_flags
    if (length(vals) && !is.null(fl)) {
      fls <- unique(unlist(lapply(fl, function(z) if (is.list(z)) z$flag else z)))
      for (id in cand$member_id) if (any(grepl(id, vals, fixed = TRUE))) flag_hits[[id]] <<- unique(c(flag_hits[[id]], as.character(fls)))
    }
    for (v in o) .walk(v)
  }
}
.walk(led$entries)
fl_any <- vapply(flag_hits, function(z) length(z) > 0L, logical(1))
fl_sel <- vapply(flag_hits, function(z) any(grepl("^selection_basis_full_sample", z)), logical(1))
fl_des <- vapply(flag_hits, function(z) any(grepl("cross_entry", z)), logical(1))
L1FLAGS <- list(method = "v0 와 같은 방법 — 06_Registry/reinforce_ledger_l1.json 재귀 탐색(run_id/strategy_id/base_id/artifacts 문자열에 후보 run id) · vintage_flags(읽기 전용 · 진단 · 누락 가능)",
                ledger_sha256 = sha(I("06_Registry/reinforce_ledger_l1.json")), n_candidates = nrow(cand), n_any_flag = sum(fl_any),
                n_selection_basis_full_sample_ic = sum(fl_sel), n_cross_entry_design_exposure = sum(fl_des), n_either_c1_type = sum(fl_sel | fl_des),
                by_member = lapply(flag_hits[fl_any], function(z) as.list(sort(z))))

LK <- rf_prereg_lookup(list(c("하방"), c("downside"), c("저베타"), c("방어"), c("로테이션"), c("BAB")), root = ROOT, max_rows = 6L)

T_HI <- stats::qnorm(0.975); T_LO <- stats::qnorm(0.025)
IE_ANN <- 0.01; IE <- IE_ANN / 252
COND <- list(require = "MC2_v1 PASS(verdict_v1/mc2_v1.json) ∧ sanity_v1 all_pass", resolved = FALSE,
             note = "단계 3 arm — MC2_v1 FAIL 이면 측정하지 않는다(사전등록 관문)")
spec_arm <- function(a, extra = list()) c(list(weights = DESIGN$arms[[a]]$weights, design = "04_Research/l2_role_rotation/l2v1_design.json#arms", design_key = a,
                                                defensive = "v1 — as-of 하방 베타 β− 하위 삼분위(l2v1_design.json#defensive_v1)",
                                                construction = "v0 와 같음(모듈 순합산 → K200∪KQ150·LIQ → 상위 25 → Σw=1)",
                                                runner = "run_paper_replication(engine_direct · data_cutoff 2026-09-30 · start_date 2015-09-01 · chain/2 · out_root runs_v1/<arm>)"), extra)
pr <- list(
  schema = "rf_prereg_v1", prereg_id = PREREG_ID, family_id = "FAM-PR-L2-ROLESLEEVE-02",
  status = "draft", draft_rev = 1L, layer = 2L,
  lever = "L2 역할 슬리브 로테이션 v1 — 방어 슬리브 = as-of 하방 베타(β−) 하위 삼분위 · MC2_v1 관문 → (PASS 시) v0 와 같은 배분 재측정",
  title = "2계층 리서치 1단위 #1 후속 — 역할 슬리브 로테이션 v1 (방어 재정의: as-of 하방 베타 · MC2_v1 → 조건부 H1 재측정)",
  created_at = now(), created_by = "Q (2계층 리서치 1단위 #1 후속 — 도훈 2026-10-10 우선순위 1 '방어 역할을 미래로 이어지게 재설계 → MC2 재측정' · 사양 = Q-Lead 지시)",
  plan_ref = "04_Research/l2_role_rotation/RESULT_v0.md §10-1 · 04_Research/l2_role_rotation/l2v1_design.json",
  decision_refs = list("도훈 2026-10-10 — v0 뒤 우선순위 1: 방어 역할을 미래로 이어지게 재설계한 뒤 MC2 재측정",
                       "도훈 2026-10-10 — 내게 묻지말고 자체판단으로 진행(위임 승계)",
                       "Q-Lead 2026-10-10 — v1 사양(ACX β− 하위 삼분위 · MC2_v1 1차 = 원수익 차 · 조건부 단계 3 · 이 사전등록)"),
  prior_prereg = list(prereg_id = "PR-L2-ROLESLEEVE-V0", draft = "06_Registry/prereg/drafts/PR-L2-ROLESLEEVE-V0.draft1.json",
                      draft_sha256 = "6f2781942c2187c706d92ee014c2b65c7fe5a700209acde398e11d84cb57c611",
                      verdict = "04_Research/l2_role_rotation/verdict/h1_verdict_v0.json (H1 undetermined t 0.28 · MC2 FAIL −0.25%/월 t −0.59 · MC3 0.117 · 5 arm C)",
                      relation = "v0 는 등록되지 않은 초안이라 revision_of(등록본 전용)를 쓸 수 없다 — 결과 뒤 개정 규칙(새 prereg_id·새 family)에 맞춰 새 가족으로 쓰고 선행 단위를 여기 적는다"),
  framing = "falsification_attempt",
  framing_note = "확증이 아니라 반증 시도 — MC2_v1 은 단계 3 진입 관문(기전 전제 조작 확인)이고, 라벨 4종은 H1 의 판정이지 등급이 아니다.",
  hypothesis = list(
    statement = paste0("방어 슬리브를 as-of 하방 베타(β−, 252일 창 t−1 끝) 하위 삼분위로 재정의한 v1 역할 슬리브(공격·반등·α 는 v0 as-of)를 ",
                       "MSM as-of 고분산 확률 P(t−1)로 기울인 T_var(P·{방어½,α½} + (1−P)·{공격⅓,반등⅓,α⅓})의 일간 순수익이, 같은 슬리브를 ",
                       "T_var 의 시간 평균 비중으로 고정한 K 보다 평균적으로 높다: E[r_T_var − r_K] > 0. 단 이 검정(단계 3)은 MC2_v1(방어 v1 슬리브가 ",
                       "평가 창 약세월에 후보 동일가중보다 덜 잃는다)이 통과할 때만 측정한다."),
    mechanism = paste0("v0 MC2 는 β 를 통제한 잔차로 방어를 쟀다 — 그러나 저β 슬리브는 β 를 통해(노출 축소로) 방어하고, Calmar 지향 배분이 필요한 것이 ",
                       "바로 그 노출 축소다. Ang, Chen & Xing (2006) 의 β− 는 시장 하락일(창 평균 미만)의 공변동만 잰다. β 는 지속적이다(Frazzini & ",
                       "Pedersen 2014: 사전 추정 β 가 사후 실현 β 를 예측) → 저 β− 모듈은 다음 약세월에도 덜 잃는다(MC2_v1). 그 위에서 Moreira & ",
                       "Muir (2017) 분산 상태 기울기가 고분산 국면에 노출을 줄인다(H1). ★사전 서술: M&M 의 1차 예측은 위험조정(분산 감소)이지 평균 ",
                       "증가가 아니고, 저β 방어는 비약세월에 상승을 덜 받는다 — H1(평균)은 v0 처럼 미결이 최빈이며 Calmar Δ(보조)가 다른 얼굴을 보일 수 있다."),
    prediction = "MC2_v1 PASS(약세월 mean(r_s − r_c) > 0 ∧ NW t ≥ 1.0) → h1_mean_delta(T_var−K) NW lag-3 t ≥ 1.96",
    alternatives = list(
      beta_nonpersistence = "β− 가 지속되지 않는다(하락일 ≈ 절반 표본 · 추정 잡음) → 약세월 실현 β 차 ≈ 0 · MC2_v1 FAIL",
      alpha_offset = "저 β− 모듈의 약세월 음(−) 잔차가 β 이득을 상쇄 → 실현 β 차 < 0 인데 d ≤ 0 · MC2_v1 FAIL(2차 β 차·v0식 지표로 구분)",
      defense_cost = "MC2_v1 PASS 이나 비약세월 방어 비용(저β 의 상승장 열위)으로 H1 평균 Δ ≈ 0 → undetermined(M&M 1차 예측과 정합 — Calmar Δ 보조)",
      wrong_sign = "고분산 직후 반등(Daniel & Moskowitz 2016 류)에서 공격·반등 슬리브가 이겨 T_var 가 진다 → failed",
      treatment_dilution = "슬리브 중복·상위 25 절단으로 종목 수준 처치 희석 → MC3b 작음 · 효과 희석")),
  differs_from_prior_negatives = list(
    PR_L2_ROLESLEEVE_V0 = "v0 방어 = 사후 확정 약세 국면 β-잔차 t(as-of) → 평가 창 약세월 β-잔차 −0.25%/월(NW t −0.59) MC2 FAIL. v1 방어 = 하방 공변동(β−) 자체 — 잔차가 아니라 노출로 방어한다(측정축도 원수익 차로 바뀐다 · v0식 지표는 병기)",
    DIST_FR_004 = "FR_003 계열(모듈별 국면 IR · softmax · 사후 대표 풀) 6 arm 전부 C — 이 단위는 v0 처럼 '국면 확률 → 역할 비중' 사상 하나만 쓴다",
    FR_series = "메모리 project-fr-series-invalid-rotation-adds-nothing — 배분기 EW 붕괴 → MC3(처치 전달량 ≥0.05)로 사전 판정(v0 실측 0.117)"),
  floors = list(list(id = "POOL65", ref = "없음 — 06_Registry/prereg/reference_floors_v2.json 은 1계층 바닥 전용 · L2 바닥 등재 경로 부재(v0 와 같음)",
                     status = "not_in_floor_registry", definition = "v0 후보 그대로 — 06_Registry/module_performance.json 65 close_t1 모듈 ∩ as-of 구성원 81(work/l2v0_candidates.csv)",
                     selection_basis = "full_sample_representatives(잔여 선택 편향 — 81 대표는 전기간 역할 t + 사후 PS 로 뽑혔다 · 공개)",
                     measurement_regime = list(exec_price = "close_t1"))),
  arms_frozen = TRUE,
  arms = list(
    list(id = "T_var", order = 1L, role = "treatment", on_floor = "POOL65", selection_basis = "as_of", conditional_on = COND,
         spec = spec_arm("T_var", list(P = "MSM as-of Crisis_Prob_asof at s_m(Date <= 시그널일) — v0 와 같은 계열"))),
    list(id = "K", order = 2L, role = "control", on_floor = "POOL65", selection_basis = "as_of", conditional_on = COND,
         spec = spec_arm("K", list(note = "노출 맞춤 정적 대조 — Pbar = 창 132개월 P 평균(v0 와 같은 값 0.1499). 실시간 불가(C1 성격) → 후보 아님·등급 진단 전용"))),
    list(id = "S", order = 3L, role = "control", on_floor = "POOL65", selection_basis = "as_of", conditional_on = COND,
         spec = spec_arm("S", list(lag = "P(s_{m−1}) — C5 lag-1 스트레스"))),
    list(id = "EW_all", order = 4L, role = "control", on_floor = "POOL65", selection_basis = "none", conditional_on = COND,
         spec = spec_arm("EW_all", list(note = "슬리브 무시 · 가용 후보 전부 동일가중 — v0 EW_all 과 같은 정의(같은 판본이면 같은 일간 수익 = 재현 대조)")))),
  deleted_arms = list(),
  contrasts = list(list(id = "T_var-K", a = "T_var", b = "K"), list(id = "S-K", a = "S", b = "K"), list(id = "T_var-S", a = "T_var", b = "S"),
                   list(id = "T_var-EW_all", a = "T_var", b = "EW_all")),
  se_cells = list(),
  metrics = list(
    list(id = "h1_mean_delta", tier = "primary", contract = "beta_controlled_alpha", direction = "increase", targets = list("T_var-K"), must_report = TRUE,
         field = "02_Infrastructure/contracts/beta_controlled_alpha.R::beta_controlled_alpha(r_T_var, r_K, periods_per_year=252, nw_lag=3) — t = port_t = mean(r_T_var − r_K) 의 NW lag-3 t · value = active_ann/252 · se = value/t · r = bt_result period_returns ret_net(15bps 순 · 같은 날 짝) — v0 와 같은 식(lib_l2v1.R::l2v1_contrast · v0 판정 재현 검사 통과)"),
    list(id = "h1_mean_delta_lag21", tier = "secondary", contract = "beta_controlled_alpha", direction = "report", targets = list("T_var-K"),
         field = "같은 계약 nw_lag=21(강건성 보고 전용)"),
    list(id = "lag1_stress_delta", tier = "secondary", contract = "beta_controlled_alpha", direction = "report", targets = list("S-K", "T_var-S"),
         field = "같은 계약 nw_lag=3 — S 가 T_var 대비 붕괴하면 동월 누출 의심(pit.md C5 lag1 스트레스)"),
    list(id = "mean_delta_boot", tier = "secondary", contract = "rf_prereg_paired_boot", direction = "increase", targets = list("T_var-K"),
         field = "rf_prereg.R::rf_prereg_paired_boot(stat='mean') — 설정 B·seed·블록·ci 0.90 · p_gt0"),
    list(id = "calmar_delta_boot", tier = "secondary", contract = "rf_prereg_paired_boot", direction = "increase", targets = list("T_var-K"),
         field = "rf_prereg_paired_boot(stat='calmar') — M&M 기전의 위험조정 얼굴(보고 · 판정 무관)"),
    list(id = "baseline_delta", tier = "secondary", contract = "beta_controlled_alpha", direction = "report", targets = list("T_var-EW_all"),
         field = "같은 계약 nw_lag=3 — 단순 결합 대비(보고)"),
    list(id = "essence", tier = "safety", contract = "essence_score", direction = "report", targets = list("T_var", "K", "S", "EW_all"), must_report = TRUE,
         field = "각 arm authoritative_remeasure.json essence_grade · essence(PORT_t·net_sharpe·cagr·mdd·calmar·oos_retention) — 대조 arm 은 선택 후보 아님")),
  decision_params = list(
    list(id = "t_crit_lo", value = T_LO, status = "fixed_by_instruction",
         source = "Q-Lead 지시 2026-10-10 'H1 = v0 규칙(t ≤ −1.96 failed)' — qnorm(0.025) · v0 초안과 같은 값. 산출물 출처 없음 → 등록 차단 사유"),
    list(id = "t_crit_hi", value = T_HI, status = "fixed_by_instruction",
         source = "Q-Lead 지시 2026-10-10 'H1 = v0 규칙(t ≥ 1.96 confirmed)' — qnorm(0.975) · v0 초안과 같은 값")),
  criteria = list(
    success = list(list(metric = "h1_mean_delta", target = "T_var-K", stat = "t", op = ">=", rhs = list(param = "t_crit_hi"))),
    failure = list(list(metric = "h1_mean_delta", target = "T_var-K", stat = "t", op = "<=", rhs = list(param = "t_crit_lo"))),
    text = list(gate_mc2_v1 = "단계 2 관문: MC2_v1 FAIL → 단위 종료(arm 미측정 · H1 라벨 없음 · status stopped:mc2_v1_fail) / PASS → 단계 3",
                success = "h1_mean_delta(T_var−K) NW lag-3 t ≥ 1.96 (∧ MC3 통과)", failure = "t ≤ −1.96",
                powered_null = "−1.96 < t < 1.96 ∧ (value − ie)/se ≤ −1.96 (ie = 1%/yr)",
                undetermined = "그 밖 · 또는 MC3 미달(처치 미전달)",
                invalid = "4 arm 판본(data_cutoff·지문·exec_price) 불일치 또는 잠금 전 측정 → 라벨 없음")),
  labels = cfg$labels,
  power = list(
    primary = list(metric = "h1_mean_delta", target = "T_var-K"), ci_level = cfg$bootstrap$ci_level,
    implied_effect = list(value = IE, annualized = IE_ANN, unit = "일평균 (r_T_var − r_K) 순수익",
                          source = "SESOI(Lakens 2017 https://doi.org/10.1177/1948550617697177) = 연 1%p — v0 와 같은 판단값(측정 결과로 역산 금지 — Hoenig & Heisey 2001)",
                          formula = "0.01 / 252"),
    se = list(value = NULL, source = list("block_bootstrap"), status = "not_computable_pre_measurement",
              note = "T_var−K(v1) 계열은 측정 전 없다 — v0 의 se(1.95%/yr)는 다른 처치의 값이라 이식하지 않는다(등록 차단 사유 · v0 와 같음)"),
    computed = NULL,
    calibration = list(kind = "null_t_quantile", params = list(t_lo = "t_crit_lo", t_hi = "t_crit_hi"),
                       note = "명목 정규 임계(지시) — 경험 귀무 교정 미산출(등록 차단 사유 · v0 와 같음)"),
    modal_outcome = "undetermined",
    leaves_behind = list("as-of 하방 베타 방어 라벨(work/l2v1_defensive_labels.parquet · 누출 음성 3종·양성 2종 대조 동봉) — 2계층 방어 슬리브 재사용 재료",
                         "MC2_v1(β 를 통한 방어의 지속성) 실측 + v0식 β-잔차 병기 — '방어 = 노출' 과 '방어 = 잔차' 의 분리",
                         "(PASS 시) 4 arm 권위 등급 · H1 판정 — v0 와 같은 틀에서 방어 정의만 바꾼 대조")),
  se_source = list(methods = list("block_bootstrap"), combine = cfg$se_sources$combine,
                   note = "1차 판정 통계는 NW lag-3 t(계약) · 블록 부트스트랩은 보조 CI·p_gt0"),
  budget = list(max_cells = 4L, counted = "arm 4(T_var·K·S·EW_all) — MC2_v1 PASS 일 때만 각 1회 · 재측정 금지 · FAIL 이면 0"),
  priors = list(mechanism = 0.25, success = list(lo = 0.05, hi = 0.12), grade_a = 0, mc2_v1_pass = 0.6,
                basis = paste0("판단값: MC2_v1 PASS 0.6 — β 지속성(FP 2014)으로 저 β− 슬리브의 약세월 손실이 작을 공산이 크나, β− 는 하락일 절반 표본이라 ",
                               "총 β 보다 잡음이 크고 저β 모듈의 잔차 알파가 음일 수 있다(v0 에서 β-잔차가 음) · H1 성공 0.05~0.12 — v0 t 0.28 · ",
                               "방어 정의 교체는 T_var−K 의 (P−Pbar)×(방어 v1 − 나머지) 공분산만 바꾼다 · M&M 1차 예측은 분산 · grade_a 0 = mechanism_only")),
  hypothesis_index_lookup = LK,
  pit = list(as_of_selection = TRUE, c_codes = list("C1", "C2", "C5", "C6", "C10", "C11", "C14"),
             statements = list(
               "C1·C14: 방어 v1 소속 = 결정일 dd(보유월 첫날)마다 β− 창 date < dd(끝 = 직전 거래일 = 시그널일 s_m) · 적격·삼분위는 그 결정일 단면만 · 전기간 통계·사후 PS·전기간 역할 등급 미사용. 빌더가 매 실행 누출 음성 대조 3종(dd 이후 잡음·충격·삭제 → 비트 동일) + 양성 대조 2종(1일·21일 누출 창 → β− 변화 = 계기 발화)을 집행 — 실패 시 중단",
               "C11: 시장 = .cache/benchmark.parquet BM_Ret(정본 KOSPI200 포인트판 · rfd_bench_daily) · 모듈 일간 = 각 계열 03_period_returns.csv ret_net(close_t1 재측정판 — 65 계열 벤치 달력 결손 0 · 잠금 전 날짜만 실측)",
               "C11·C14: P = msm_asof_daily Crisis_Prob_asof(pit_audit PIT-clean) · Date <= 시그널일. 운영 캐시 .cache/msm_daily_latest(C1 격리) 미사용",
               "C5: 시그널일 = 보유월 첫날 이전 마지막 거래일 · 집행 = 보유월 첫 거래일 종가(close_t1) · lag-1 스트레스 arm S 병행",
               "C2: 모듈 보유 = exec_date <= 집행일 마지막 스냅샷 · C6·C10: 시그널일 K200∪KQ150 시변 · 유동성 1일 지연(v0 와 같음)",
               "평가 표적: MC2_v1 의 약세월 = 사후 PS 연대기(06_Registry/strategy_role.json — '2계층 as-of 소비 금지') — 결정 입력이 아니라 평가 표적으로만 쓴다(v0 MC2 와 같음)",
               "진단(FP 총 β · v0 라벨)은 선택 입력 아님 — 대안 슬리브로 평가 창 성과를 재지 않는다(분기 경로 차단)",
               "C1(공개): arm K Pbar = 창 전체 P 평균(실시간 불가 대조) · 후보 65 = 사후 선정 81 대표의 부분집합 · 1계층 C1 표식 상속(L1FLAGS) — v0 와 같음",
               "Lockbox 폐지(v10) — 가용 전기간 사용 · essence IS/OOS anchored 분할은 측정 규율로 유지")),
  measurement_regime = list(exec_price = "close_t1", current_axis = "exec_v2_close_t1", pin_tag = NULL, data_cutoff = DESIGN$window$data_cutoff,
                            cost_model_version = "replication_weight_delta_v1/first_hold_day_multiplicative",
                            harness_md5 = unname(as.character(tools::md5sum(I("02_Infrastructure/replication/replication_harness.R")))),
                            benchmark_sha256_at_lock = PINS$benchmark_at_lock$sha256, module_series_digest_at_lock = series_digest,
                            vintage_note = "pin_cache 스냅샷 없음(등록 차단 사유) — 러너 data_cutoff 절단 + arm 별 data_fingerprint · 판정이 4 arm 지문 일치를 요구 · 라벨 원천(벤치·65 계열) 지문은 잠금 시점 값을 여기 · 생성 시점 값을 라벨 매니페스트에 싣는다"),
  selection_accounting = list(selection_type = "chain", n_family = 2L,
                              n_source = "v0 T_var(PR-L2-ROLESLEEVE-V0 · 측정됨 · C) → v1 T_var(방어 슬리브 재정의 · 이 사전등록) — 같은 처치 틀의 체인 2회 · 러너 n_trials_cumulative 2(chain = DSR 진단만)",
                              forking_paths = list(
                                defensive_redefinition = "★v0 MC2 FAIL 을 본 뒤 방어를 재정의했다. 정의는 문헌 1개(ACX 2006 β−)에서 골랐고 창 252일·삼분위·하위 1군·NW t 문턱 1.0 은 Q-Lead 지시로 고정 — 평가 창 결과로 고르지 않았다. 대안(FP 총 β·v0 라벨)은 진단 전용이며 평가 창 성과를 재지 않는다",
                                eval_window_reuse = "★v1 은 v0 와 같은 평가 창(2015-10~2026-09)을 재사용한다 — 완화 = 단일 사전 정의 · 1회 측정. 남는 위험 = 같은 창 두 번째 시도",
                                predictor = "v0 그대로 — IS 분산 AUC 최대(MSM_asof 0.840 > HMM2 0.815 > JM 0.756)",
                                target_switch = "v0 공개 승계 — 방향 표적 IS 실패 뒤 분산 표적 채택(M&M 2017 · Barroso & Santa-Clara 2015)",
                                oos_seen = "v0 공개 승계 — predictor_oos_diagnostic.json 이 OOS 분산 AUC 를 사전등록 전에 보였다(순위 불변)",
                                weights = "w_hi·w_lo = 역할 집합 1/N(DeMiguel et al. 2009) — v0 그대로"),
                              n_note = "DSR 미적용(chain) — 실효 시행 수는 2 보다 크다(v0 분기 경로 승계). 등록 단계 요구(sweep · n_family ≥ 2)와 다르다 → 등록 차단 사유"),
  dependencies = list(
    list(id = "L2-FLOOR-REGISTRY", what = "reference_floors_v2.json 에 L2 바닥(POOL65) 등재 경로", status = "unavailable",
         note = "v0 와 같음 — 2계층 사전등록은 구조적으로 등록 불가(초안 sha256 잠금으로 대체 · 공개)"),
    list(id = "ENGINE_V1", what = "allocator_engine_v1.R(PORTFOLIO 계약 · 방어 원천만 v1)", status = "available", file = PINS$engine$path, sha256 = PINS$engine$sha256),
    list(id = "LABELS_V1", what = "work/l2v1_defensive_labels.parquet(잠금 뒤 빌더가 생성 · 매니페스트에 sha256)", status = "build_after_lock",
         file = PINS$labels_builder$path, sha256 = PINS$labels_builder$sha256),
    list(id = "V0_INPUTS", what = "v0 동결 입력(후보 CSV · 보유 패널 · as-of 역할 · MSM)", status = "available", file = PINS$v0_candidates$path, sha256 = PINS$v0_candidates$sha256)),
  open_questions = list(),
  scope = list(label = "mechanism_only", a_eligible = FALSE, decision_ref = "L2V0-SCOPE 승계 (Q 위임 판단 2026-10-10)",
               statement = "후보 집합(65)이 전기간 통계로 뽑힌 대표의 부분집합이고 모듈 다수가 1계층 C1 표식을 상속한다 → 어느 arm 의 essence 가 Grade A 여도 A 후보가 아니다(Judge·BOOK 경로 없음 · 러너 judge_request 는 *.EXPERIMENT_HOLD.json). 라벨은 H1 기전의 판정일 뿐."),
  manipulation_checks = list(
    MC1 = list(rule = "IS 분산 AUC 95% CI 하한 > 0.5", source = "predictor_selection_IS.json results.MSM_asof_CrisisProb.variance.ci95 (IS 전용 · 기존 산출 · v0 와 같음)",
               known_before_registration = TRUE, value_ci95_lo = 0.718493691921139, auc = 0.839617768595041, pass = TRUE),
    MC2_v1 = list(
      rule = "평가 창 보유월 중 사후 PS 약세월에서 mean(r_s − r_c) > 0 ∧ NW lag-3 t ≥ 1.0",
      definitions = DESIGN$mc2_v1[c("months", "monthly_returns", "sleeve_return", "candidate_return", "bear_months", "primary")],
      nw_t_threshold = 1.0, nw_lag = 3L, threshold_basis = "v0 MC2 와 같은 문턱(비교 가능성 — Q-Lead 지시)",
      contract = "backtest_result_contract.R::.nw_t_mean(약세월 d · lag 3) — beta_controlled_alpha.R port_t 로 항등 교차 확인 · β 차 = beta_controlled_alpha(d, b)$beta",
      why_raw_difference = "v0 MC2 는 β 를 통제해 '노출로 하는 방어' 를 0 으로 쳤다. 저β 슬리브는 노출로 방어하고 Calmar 배분이 필요한 것이 그 노출 축소다 → 1차 = 원수익 차(β 미통제) · v0식 β-잔차는 2차 병기",
      secondary_report_only = DESIGN$mc2_v1$secondary_report_only,
      effect = "관문 — FAIL → 단계 2에서 종료(arm 미측정 · H1 라벨 없음 · status stopped:mc2_v1_fail) / PASS → 단계 3(sanity → arm 4 → H1 1회). H1 라벨 규칙은 바꾸지 않는다",
      computed_by = "mc2_l2v1.R(잠금 뒤 1회 · verdict_v1/mc2_v1.json 덮어쓰기 거부)"),
    MC3 = list(rule = "mean_m ½Σ_r |w_T_var,r(m) − w_K,r| ≥ 0.05 (슬리브 수준 처치 전달량)", threshold = 0.05,
               effect = "미달 → H1 = undetermined(treatment not delivered)", computed_by = "sanity_l2v1.R(단계 3 측정 전 · 비중만)",
               companion = "MC3b = 종목 수준 전달량(보고 전용)")),
  verdict_procedure = list(
    mc2_script = PINS$mc2, script = PINS$verdict,
    rule_executor = "verdict_l2v1.R — 초안 criteria·decision_params·power.implied_effect·MC3 문턱을 읽어 v0 규칙 그대로 집행(lib_l2v1.R::l2v1_h1_label — v0 라벨·수치 재현 검사 통과)",
    rf_prereg_verdict = "미사용 — 등록본 전용. 등록 차단이면 rf_record_decision 기록 없음 · 판정 파일 1회(덮어쓰기 거부)",
    vintage_rule = "4 arm 의 data_cutoff·data_fingerprint digest·exec_price 가 모두 같아야 판정(아니면 invalid:vintage_mismatch)",
    lock_rule = "arm remeasured_at > 이 초안 색인 written_at · 라벨 매니페스트 lock.draft_sha256 = 이 초안 sha256 · 코드 sha256 = pins",
    one_time = TRUE),
  run_plan = list(
    steps = list("1. 이 초안 쓰기(잠금) — 평가 창 계산 0",
                 "2. build_l2v1_labels.R(방어 v1 라벨 · 누출 대조) → mc2_l2v1.R(MC2_v1 1회) → FAIL 이면 여기서 종료",
                 "3. (PASS 시) sanity_l2v1.R(비중·MC3) → run_l2_v1.R(T_var·K·S·EW_all 순차 · 여유 RAM ≥ 8GB · 리프레시 배리어) → verdict_l2v1.R(H1 1회)"),
    order = list("T_var", "K", "S", "EW_all"), driver = PINS$driver,
    env = list(QVEST_RP_REGISTER = "0", QVEST_RP_NO_LCODE = "1", QVEST_NO_LEDGER_OPEN = "1", send_telegram = FALSE),
    memory_gate = "arm 마다 여유 RAM ≥ 8GB(PowerShell Get-CimInstance) · 리프레시 배리어 대기", out_root = "04_Research/l2_role_rotation/runs_v1/<arm>",
    a_route = "Grade A 시 러너 judge_request*.json → *.EXPERIMENT_HOLD.json(이 단위 A 자격 없음)",
    no_side_effects = "BOOK·Judge·등급 재표기·텔레그램 없음(Q-Lead 소관) · git commit 없음"),
  pins = c(PINS, list(module_series = list(digest = series_digest, n = length(SERIES), items = SERIES))),
  l1_flag_inheritance = L1FLAGS,
  disclosures = list(
    eval_window_reuse = "v1 은 v0 MC2 실패를 본 뒤 설계됐고 같은 평가 창(2015-10~2026-09)을 다시 쓴다. 완화 = 문헌(ACX 2006)에서 고른 단일 정의 · 창·삼분위·하위 1군은 지시로 고정 · 1회 측정",
    seen_before_design = "설계 전 열람: RESULT_v0.md · h1_verdict_v0.json · v0 MC2 파일 머리(v0 방어 슬리브 첫 몇 달). v1 슬리브의 평가 창 성과는 잠금 전 미계산 — 잠금 전 코드 검사는 ①합성 단위 검사 ②평가 창 앞 결정일(2012-01~2015-09) 라벨·MC2 드라이런(MC2 값 미출력) ③엔진 회귀(v0 라벨로 v0 비중 재현 · 비중만) ④판정 회귀(공개된 v0 arm 산출물로 v0 수치 재현)",
    pre_lock_label_diagnostics_seen = "드라이런(2012-01~2015-09 결정일) 라벨 수준 진단을 열람했다(β−·FP 총 β 순위상관 중앙 0.63 · 하위 삼분위 겹침 중앙 67% · v0 방어 소속과 겹침 중앙 0 · 슬리브 21~22) — 평가 창 이전 자료 · 정의 변경 없음",
    pre_lock_control_fix = "잠금 전 드라이런에서 1일 누출 양성 대조가 한 결정일(2013-11-01)에 발화하지 않았다(β− 는 상승일을 보지 않아 교란된 그날이 상승일로 남으면 불변) → 대조를 1일×충격 교체 · 21일×잡음 교체로 강화. 라벨 정의·계산 불변",
    candidate_selection = "v0 와 같음 — 후보 65 = 사후 선정 81 대표의 부분집합(낙관 방향 잔여 편향)",
    long_short_modules = "롱숏 모듈 2개(RP_20260902_122546_22268 · RP_20260907_101130_20668)는 β− 가 낮아 방어 v1 슬리브에 들 공산이 크다 — MC2_v1 슬리브 수익엔 그 모듈 수익이 그대로 · 배분 단계에선 음수 비중 순합산(v0 사양)",
    end_of_window_ineligibility = "2026-08-28 에 끝나는 계열 8개는 2026-09-01 결정일 창(~2026-08-31)이 252일을 못 채워 부적격 — 마지막 보유월 적격 57 · 하위 1군 19(예상)",
    rf_not_subtracted = "β− 는 원수익으로 잰다(ACX 는 초과수익) — 창 안 상수 무위험 차감은 cov·var·하락일 집합을 바꾸지 않는다(합성 검사로 확인)",
    mc2_sleeve_virtual = "MC2_v1 슬리브 수익 = 모듈 월수익 동일가중(가상 슬리브) — 배분 단계(합산·상위 25 절단)의 실현 방어와 다를 수 있다(MC3b·kept_share 로 보고)",
    stale_snapshots = "v0 와 같음 — 보유 스냅샷이 일찍 끝난 모듈은 마지막 스냅샷 보유(배분 단계)",
    k_noncausal = "K 의 Pbar = 창 전체 P 평균 — 실시간 불가 대조(v0 와 같음)",
    mean_vs_variance = "H1 은 평균 차를 묻는다 — M&M 1차 예측(분산 감소)은 calmar_delta_boot·arm MDD/Calmar 로 보고만",
    n_trials = "러너 n_trials_cumulative = 2(chain: v0 T_var → v1 T_var) — DSR 진단값만 바뀌고 등급(chain = DSR 관문 없음)은 불변. v0 는 1 로 측정",
    diversifier_excluded = "diversifier 역할 as-of 라벨 없음 — 제외(v0 와 같음)",
    family_new = "가족 FAM-PR-L2-ROLESLEEVE-02 — v0(FAM-…-01)는 미등록 초안이라 revision_of 불가 · 결과 뒤 개정 규칙(새 가족)에 맞춤 · 선행 단위는 prior_prereg"),
  reporting_obligations = list(
    "MC2_v1 1차 값·t·PASS/FAIL · 2차(약세월 β 차 · v0식 β-잔차 · 비약세월 d) · 슬리브 크기 추이",
    "PASS 시: 4 arm essence(PORT_t·SR·CAGR·MDD·Calmar·OOS) · H1 t·라벨 · MC3(+MC3b) · S−K·T−S · calmar_delta_boot · lag21 · EW_all v0 재현",
    "FAIL 시: 단계 2 종료 — arm 미측정 · H1 라벨 없음(미결을 벽으로 적립하지 않음 · AX-000)",
    "등록 차단 사유 전부(prereg_registration_attempt_v1.json) · scope mechanism_only"),
  not_a_grade = "등급은 essence 하나 — MC2_v1 은 관문, 라벨 4종은 H1 판정이다"
)

# ── 쓰기 · 등록 시도 ──────────────────────────────────────────────────────────────
v0c <- rf_prereg_validate(pr, "draft", ROOT, cfg)
if (!v0c$ok) stop("[prereg_l2v1] 초안 검증 실패:\n  - ", paste(v0c$errors, collapse = "\n  - "))
w <- rf_prereg_write(pr, "draft", ROOT, cfg)
d <- rf_prereg_load(pr$prereg_id, "draft", root = ROOT, cfg = cfg)
vr <- rf_prereg_validate(d, "registered", ROOT, cfg)
reg <- tryCatch({ r <- rf_prereg_register(pr$prereg_id, registered_by = "Q(2계층 단위 #1 v1 세션)", root = ROOT, cfg = cfg); list(ok = TRUE, result = r) },
                error = function(e) list(ok = FALSE, error = conditionMessage(e)))
idx <- Filter(function(r) identical(r$prereg_id, pr$prereg_id), rf_prereg_index(ROOT, cfg))
att <- list(schema = "l2v1_prereg_attempt_v1", prereg_id = pr$prereg_id, at = now(),
            draft = list(path = w$rel, sha256 = w$sha256, index_rows = idx),
            registration_blockers = as.list(vr$registration_blockers), registered = reg$ok, register_error = reg$error %||% NULL,
            conclusion = if (isTRUE(reg$ok)) "등록됨" else
              "등록 차단 — 결과 전 잠금 = 초안 sha256 + 색인 written_at(라벨·MC2·arm 은 이 뒤). 판정은 mc2_l2v1.R·verdict_l2v1.R 가 초안 규칙을 그대로 집행(rf_record_decision 기록 없음).",
            config_sha256 = attr(cfg, "sha256"))
writeLines(toJSON(att, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), ATTEMPT, useBytes = TRUE)
cat(sprintf("[prereg_l2v1] 초안 %s (sha256 %s) · 등록 %s · 차단 사유 %d건\n", w$rel, w$sha256, if (isTRUE(reg$ok)) "성공" else "차단", length(vr$registration_blockers)))
for (b in vr$registration_blockers) cat("  - ", b, "\n", sep = "")
