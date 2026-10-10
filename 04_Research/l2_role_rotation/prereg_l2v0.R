#==============================================================================
# prereg_l2v0.R — PR-L2-ROLESLEEVE-V0 사전등록 (측정 전 · rf_prereg.R 스키마 · 초안 → 등록 시도)
#
# 순서: ①동결 입력·코드 지문 ②hypothesis_index 조회(rf_prereg_lookup · 읽기 전용) ③1계층 표식 상속 계수(원장 읽기 전용)
#       ④초안 rf_prereg_write(kind="draft") — 덮어쓰기 거부·sha256 색인 ⑤등록 단계 검증(rf_prereg_validate "registered")으로
#       차단 사유 산출 ⑥rf_prereg_register 시도(차단이면 아무것도 쓰지 않고 실패한다) ⑦시도 기록 prereg_registration_attempt_v0.json
# 측정(run_l2_v0.R)은 이 스크립트가 초안을 쓴 **뒤에만** 한다. 수익률 미열람.
# 실행: 이 디렉터리에서 Rscript --no-save -e 'source("prereg_l2v0.R")'
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.find_root <- function() {
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd(), dirname(getwd()), dirname(dirname(getwd())))) {
    if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))) return(normalizePath(p, winslash = "/"))
  }
  stop("[prereg_l2v0] 프로젝트 루트 미발견")
}
ROOT <- .find_root(); L2DIR <- file.path(ROOT, "04_Research/l2_role_rotation")
ATTEMPT <- file.path(L2DIR, "prereg_registration_attempt_v0.json")
if (file.exists(ATTEMPT)) stop("[prereg_l2v0] 이미 실행됐다(초안·등록 시도 기록 존재): ", ATTEMPT)
if (dir.exists(file.path(L2DIR, "runs")) && length(list.files(file.path(L2DIR, "runs"), pattern = "authoritative_remeasure", recursive = TRUE)))
  stop("[prereg_l2v0] 측정 산출물이 이미 있다 — 결과 뒤 사전등록 금지")
source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_prereg.R"))
cfg <- rf_prereg_config(ROOT)
sha <- function(p) digest::digest(file = p, algo = "sha256")
rel <- function(p) sub(paste0("^", ROOT, "/"), "", normalizePath(p, winslash = "/"))
now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
DESIGN <- fromJSON(file.path(L2DIR, "l2v0_design.json"), simplifyVector = FALSE)
MAN <- fromJSON(file.path(L2DIR, "work/l2v0_inputs_manifest.json"), simplifyVector = FALSE)
pin <- function(p) list(path = rel(p), sha256 = sha(p))
PINS <- list(design = pin(file.path(L2DIR, "l2v0_design.json")), inputs_manifest = pin(file.path(L2DIR, "work/l2v0_inputs_manifest.json")),
             engine = pin(file.path(L2DIR, "allocator_engine.R")), driver = pin(file.path(L2DIR, "run_l2_v0.R")),
             sanity = pin(file.path(L2DIR, "sanity_l2v0.R")), verdict = pin(file.path(L2DIR, "verdict_l2v0.R")),
             inputs_builder = pin(file.path(L2DIR, "build_l2v0_inputs.R")), prereg_builder = pin(file.path(L2DIR, "prereg_l2v0.R")),
             runner = pin(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R")),
             harness = pin(file.path(ROOT, "02_Infrastructure/replication/replication_harness.R")),
             contract_beta_controlled_alpha = pin(file.path(ROOT, "02_Infrastructure/contracts/beta_controlled_alpha.R")),
             contract_strategy_role = pin(file.path(ROOT, "02_Infrastructure/contracts/strategy_role.R")),
             contract_essence = pin(file.path(ROOT, "02_Infrastructure/contracts/essence_score.R")))

# ── ③ 1계층 표식 상속(후보 65 의 원장 vintage_flags — 읽기 전용 · 진단) ─────────────────────
cand <- fread(file.path(ROOT, MAN$files$candidates$path))
led <- fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
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
L1FLAGS <- list(method = "06_Registry/reinforce_ledger_l1.json 를 재귀 탐색 — run_id/strategy_id/base_id/artifacts 문자열에 후보 run id 가 든 객체의 vintage_flags(읽기 전용 · 진단 · 누락 가능)",
                ledger_sha256 = sha(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json")),
                n_candidates = nrow(cand), n_any_flag = sum(fl_any), n_selection_basis_full_sample_ic = sum(fl_sel),
                n_cross_entry_design_exposure = sum(fl_des), n_either_c1_type = sum(fl_sel | fl_des),
                by_member = lapply(flag_hits[fl_any], function(z) as.list(sort(z))))

# ── ② hypothesis_index 조회 ────────────────────────────────────────────────────
LK <- rf_prereg_lookup(list(c("로테이션"), c("국면"), c("FR_003"), c("MSM"), c("volatility"), c("역할")), root = ROOT, max_rows = 6L)

T_HI <- stats::qnorm(0.975); T_LO <- stats::qnorm(0.025)
IE_ANN <- 0.01; IE <- IE_ANN / 252
spec_arm <- function(a, extra = list()) c(list(weights = DESIGN$arms[[a]]$weights, design = "04_Research/l2_role_rotation/l2v0_design.json#arms", design_key = a,
                                                construction = "design.construction(모듈 순합산 → K200∪KQ150·LIQ → 상위 25 → Σw=1)",
                                                runner = "run_paper_replication(engine_direct · data_cutoff 2026-09-30 · start_date 2015-09-01 · chain/1)"), extra)
pr <- list(
  schema = "rf_prereg_v1", prereg_id = "PR-L2-ROLESLEEVE-V0", family_id = "FAM-PR-L2-ROLESLEEVE-01",
  status = "draft", draft_rev = 1L, layer = 2L,
  lever = "L2 역할 슬리브 로테이션 v0 — as-of 역할 슬리브 × MSM as-of 고분산 확률 기울기",
  title = "2계층 리서치 1단위 #1 — 역할 슬리브 로테이션 v0 (분산 상태 기울기 T_var vs 노출 맞춤 정적 K)",
  created_at = now(), created_by = "Q (2계층 리서치 1단위 #1 — 도훈 위임 '내게 묻지말고 자체판단으로 진행' 2026-10-10 · 사양 = Q-Lead 지시)",
  plan_ref = "04_Research/01_reports/l2_role_rotation_redesign_20261010/README.md §2·§3 · 04_Research/l2_role_rotation/README.md(as-of 라벨)",
  decision_refs = list("도훈 2026-10-08 — 2계층은 1계층 전략별 라벨을 이용", "도훈 2026-10-10 — 내게 묻지말고 자체판단으로 진행", "Q-Lead 2026-10-10 — 2계층 리서치 단위 #1 사양(이 사전등록)"),
  framing = "falsification_attempt",
  framing_note = "확증이 아니라 반증 시도 — 라벨 4종은 H1(분산 상태 타이밍이 노출 맞춤 정적 혼합 대비 일평균 수익을 올리는가)의 판정이지 등급이 아니다.",
  hypothesis = list(
    statement = "as-of 역할 슬리브(방어·공격·반등·α · 65 close_t1 모듈)를 MSM as-of 고분산(위기) 확률 P(t−1)로 기울인 T_var(P·{방어½,α½} + (1−P)·{공격⅓,반등⅓,α⅓})의 일간 순수익이, 같은 슬리브를 T_var 의 시간 평균 비중으로 고정한 K 보다 평균적으로 높다: E[r_T_var − r_K] > 0.",
    mechanism = "Moreira & Muir (2017): 실현 분산은 지속적이고 기대수익은 분산에 비례해 오르지 않는다 → 고분산 상태에서 위험(고β·공격·반등) 노출을 줄이고 방어·α 쪽으로 옮기면 위험 대비 수익이 오른다. Barroso & Santa-Clara (2015): 모멘텀류는 자기 분산이 높을 때 붕괴 위험이 크다(평균 경로). ★주의(사전 서술): M&M 기전의 1차 예측은 '분산 감소·위험조정 수익 개선'이지 '평균 수익 증가'가 아니다 — H1(평균)이 기각돼도 Calmar Δ(보조)가 기전의 다른 얼굴을 보일 수 있다. 예측기 방향 판별(MC1 방향)은 IS 에서 실패했으므로 이 처치는 '방향'이 아니라 '분산 상태'를 쓴다.",
    prediction = "h1_mean_delta(T_var−K) NW lag-3 t ≥ 1.96",
    alternatives = list(
      no_timing_value = "분산 상태가 슬리브 간 평균 수익 차를 예측하지 못한다(M&M 의 평탄한 위험-수익 관계가 슬리브 대비에도 성립) → t 가 0 근처 · powered_null 또는 undetermined",
      wrong_sign = "고분산 국면 직후 반등(Daniel & Moskowitz 2016 류)에서 공격·반등 슬리브가 이겨 T_var 가 진다 → failed",
      treatment_dilution = "슬리브가 같은 종목을 크게 공유해 슬리브 비중 차가 종목 비중 차로 전달되지 않는다 → MC3b(종목 수준) 작음 · 효과 희석",
      label_nonpersistence = "as-of 방어 라벨이 다음 약세 구간으로 이어지지 않는다 → MC2 실패 · 기전 전제 붕괴")),
  differs_from_prior_negatives = list(
    DIST_FR_004 = "FR_003 계열(module_dispatcher softmax · 모듈별 국면 IR · 사후 대표 풀)은 6 arm 전부 C, 좁은 풀이 지배. 이 단위는 모듈별 국면 IR 추정을 없애고 '국면 확률 → 역할 비중' 사상 하나만 쓴다(결정 변수 축소 · 설계 §1).",
    FR_series = "메모리 project-fr-series-invalid-rotation-adds-nothing — 배분기가 입장 집합 EW 로 붕괴(추적오차 0.03~0.27%) → 이 단위는 MC3(슬리브 처치 전달량 ≥0.05)로 처치 전달을 사전 판정한다.",
    predictor = "과거 국면 예측기는 방향이 아니라 분산을 예측(메모리 regime-predictors-predict-variance) — 이 단위는 그 사실을 처치로 쓴다(분산 표적)."),
  floors = list(list(id = "POOL65", ref = "없음 — 06_Registry/prereg/reference_floors_v2.json 은 1계층 바닥(F1·F1p·F2·F3) 전용 · L2 바닥(후보 풀) 등재 경로 부재",
                     status = "not_in_floor_registry", definition = "06_Registry/module_performance.json 65 close_t1 모듈 ∩ asof_roles.parquet 구성원(work/l2v0_candidates.csv)",
                     selection_basis = "full_sample_representatives(잔여 선택 편향 — 81 대표는 전기간 역할 t + 사후 PS 로 뽑혔다 · 공개)",
                     measurement_regime = list(exec_price = "close_t1"))),
  arms_frozen = TRUE,
  arms = list(
    list(id = "T_var", order = 1L, role = "treatment", on_floor = "POOL65", selection_basis = "as_of", spec = spec_arm("T_var", list(P = "MSM as-of Crisis_Prob_asof at s_m(Date <= 시그널일)"))),
    list(id = "K", order = 2L, role = "control", on_floor = "POOL65", selection_basis = "as_of",
         spec = spec_arm("K", list(note = "노출 맞춤 정적 대조 — Pbar = 창 132개월 P 평균(P 계열만 · 성과 미열람). 전기간 P 평균을 써서 실시간 실행 불가(C1 성격) → 후보 아님·등급 진단 전용"))),
    list(id = "K_eq", order = 3L, role = "control", on_floor = "POOL65", selection_basis = "as_of", spec = spec_arm("K_eq")),
    list(id = "S", order = 4L, role = "control", on_floor = "POOL65", selection_basis = "as_of", spec = spec_arm("S", list(lag = "P(s_{m−1}) — C5 lag-1 스트레스"))),
    list(id = "EW_all", order = 5L, role = "control", on_floor = "POOL65", selection_basis = "none", spec = spec_arm("EW_all", list(note = "슬리브 무시 · 가용 후보 전부 동일가중 — 후보 집합 자체의 잔여 사후 선택은 공개 사항")))),
  deleted_arms = list(),
  contrasts = list(list(id = "T_var-K", a = "T_var", b = "K"), list(id = "S-K", a = "S", b = "K"), list(id = "T_var-S", a = "T_var", b = "S"),
                   list(id = "T_var-K_eq", a = "T_var", b = "K_eq"), list(id = "T_var-EW_all", a = "T_var", b = "EW_all")),
  se_cells = list(),
  metrics = list(
    list(id = "h1_mean_delta", tier = "primary", contract = "beta_controlled_alpha", direction = "increase", targets = list("T_var-K"), must_report = TRUE,
         field = "02_Infrastructure/contracts/beta_controlled_alpha.R::beta_controlled_alpha(r_T_var, r_K, periods_per_year=252, nw_lag=3) — t = port_t = mean(r_T_var − r_K) 의 Newey-West lag-3 t(PORT_t 와 같은 규약 · measurement-graduation §2) · value = active_ann/252(일평균 Δ) · se = value/t · r = 각 arm bt_result period_returns ret_net(15bps 순 · 같은 날 짝)"),
    list(id = "h1_mean_delta_lag21", tier = "secondary", contract = "beta_controlled_alpha", direction = "report", targets = list("T_var-K"),
         field = "같은 계약 nw_lag=21(약 1개월 · 강건성 보고 전용 · 판정 무관)"),
    list(id = "lag1_stress_delta", tier = "secondary", contract = "beta_controlled_alpha", direction = "report", targets = list("S-K", "T_var-S"),
         field = "같은 계약 nw_lag=3 — S(P 1개월 추가 지연)가 T_var 대비 붕괴하면 동월 누출 의심(pit.md C5 lag1 스트레스)"),
    list(id = "mean_delta_boot", tier = "secondary", contract = "rf_prereg_paired_boot", direction = "increase", targets = list("T_var-K"),
         field = "rf_prereg.R::rf_prereg_paired_boot(r_T_var, r_K, stat='mean') — 설정 B·seed·블록(auto)·ci 0.90 · p_gt0"),
    list(id = "calmar_delta_boot", tier = "secondary", contract = "rf_prereg_paired_boot", direction = "increase", targets = list("T_var-K"),
         field = "rf_prereg_paired_boot(stat='calmar') — M&M 기전의 위험조정 얼굴(보고 · 판정 무관)"),
    list(id = "baseline_delta", tier = "secondary", contract = "beta_controlled_alpha", direction = "report", targets = list("T_var-K_eq", "T_var-EW_all"),
         field = "같은 계약 nw_lag=3 — 단순 결합 대비(보고)"),
    list(id = "essence", tier = "safety", contract = "essence_score", direction = "report", targets = list("T_var", "K", "K_eq", "S", "EW_all"), must_report = TRUE,
         field = "각 arm authoritative_remeasure.json essence_grade · essence(portfolio_alpha_t_nw_lag3·net_sharpe·cagr·mdd·calmar·oos_retention) — 러너 chain/1 · 대조 arm 은 선택 후보 아님(등급 진단)")),
  decision_params = list(
    list(id = "t_crit_lo", value = T_LO, status = "fixed_by_instruction",
         source = "Q-Lead 지시 2026-10-10 'NW t ≤ −1.96 → failed' — 양측 5% 정규 임계 qnorm(0.025)(NW t 의 점근 정규). 산출물·derive 출처 없음 → rf_prereg 등록 차단 사유"),
    list(id = "t_crit_hi", value = T_HI, status = "fixed_by_instruction",
         source = "Q-Lead 지시 2026-10-10 'NW t ≥ 1.96 → confirmed' — qnorm(0.975)")),
  criteria = list(
    success = list(list(metric = "h1_mean_delta", target = "T_var-K", stat = "t", op = ">=", rhs = list(param = "t_crit_hi"))),
    failure = list(list(metric = "h1_mean_delta", target = "T_var-K", stat = "t", op = "<=", rhs = list(param = "t_crit_lo"))),
    text = list(success = "h1_mean_delta(T_var−K) NW lag-3 t ≥ 1.96 (∧ MC3 통과)", failure = "t ≤ −1.96",
                powered_null = "−1.96 < t < 1.96 ∧ (value − ie)/se ≤ −1.96 (ie = 1%/yr — rf_prereg null_t_quantile 판정식)",
                undetermined = "그 밖 · 또는 MC3 미달(처치 미전달)")),
  labels = cfg$labels,
  power = list(
    primary = list(metric = "h1_mean_delta", target = "T_var-K"), ci_level = cfg$bootstrap$ci_level,
    implied_effect = list(value = IE, annualized = IE_ANN, unit = "일평균 (r_T_var − r_K) 순수익",
                          source = "SESOI(최소 관심 효과 · Lakens 2017 https://doi.org/10.1177/1948550617697177) = 연 1%p — 판단값. 근거: 평균 수익에 대한 문헌 함의 크기가 없다(M&M 기전은 분산 감소가 1차 예측) · 회전 층을 정적 혼합 위에 얹을 경제적 하한. 측정 결과로 역산 금지(Hoenig & Heisey 2001)",
                          formula = "0.01 / 252"),
    se = list(value = NULL, source = list("block_bootstrap"), status = "not_computable_pre_measurement",
              note = "T_var−K 계열은 측정 전 존재하지 않는다 — 슬리브 수익으로 SE 를 미리 재면 처치 효과(공분산)를 사실상 엿본다 → 측정 전 미산출 = rf_prereg 등록 차단 사유(power_gate 판정 불가 · 보고는 '미산출')"),
    computed = NULL,
    calibration = list(kind = "null_t_quantile", params = list(t_lo = "t_crit_lo", t_hi = "t_crit_hi"),
                       note = "명목 정규 임계(Q-Lead 지시). 설정 PREREG-POWERED-NULL-CALIBRATION 은 경험 귀무 교정을 요구 → 등록 차단 사유로 기록(판정은 지시대로 명목 임계)"),
    modal_outcome = "undetermined",
    leaves_behind = list("as-of 역할 슬리브 배분 엔진(allocator_engine.R · PORTFOLIO 계약 · 25종 실투형) — 2계층 다음 단위의 기저",
                         "5 arm 권위 등급(T_var·K·K_eq·S·EW_all) — 2계층 단순 결합 기준선",
                         "MC2(as-of 방어 라벨 지속성)·MC3/MC3b(처치 전달량) 실측 — 슬리브 설계의 다음 수리 지점")),
  se_source = list(methods = list("block_bootstrap"), combine = cfg$se_sources$combine,
                   note = "1차 판정 통계는 NW lag-3 t(계약). 블록 부트스트랩(rf_prereg_paired_boot)은 보조 CI·p_gt0"),
  budget = list(max_cells = 5L, counted = "arm 5(T_var·K·K_eq·S·EW_all) — 각 1회 측정 · 재측정 금지"),
  priors = list(mechanism = 0.25, success = list(lo = 0.05, hi = 0.15), grade_a = 0,
                basis = "판단값: FR_001~003 전부 C·국면 배분 = 정적 EW 대비 0/음수(메모리 09-24) · M&M 기전의 1차 예측은 평균이 아니라 분산 · 슬리브 중복이 커 종목 수준 처치 희석 예상 · 11년 일간 창(검정력 중간) → 기전 0.25 · 성공(t≥1.96) 0.05~0.15. grade_a 0 = scope mechanism_only(A 자격 없음) — essence A 자체의 사전확률은 ≈0.02(참고)."),
  hypothesis_index_lookup = LK,
  pit = list(as_of_selection = TRUE, c_codes = list("C1", "C2", "C5", "C6", "C10", "C11", "C14"),
             statements = list(
               "C1·C14: 슬리브 소속 = asof_roles.parquet(decision_date = 보유월 첫날 · 자료 date < 그 날만 · 끝 부분월 제외 → 일간 계열 T−2) — 전기간 역할 등급·사후 대표 배정(pool_rep_roles_fullsample) 미사용",
               "C11·C14: P = msm_asof_daily Crisis_Prob_asof(필터 확률 · 모수 = fit_date(직전 연말) 이하 MLE · pit_audit PIT-clean) · Date <= 시그널일 마지막 값. 운영 캐시 .cache/msm_daily_latest(전기간 모수 C1 오염) 미사용",
               "C5: 시그널일 = 보유월 첫날 이전 마지막 거래일 · 집행 = 보유월 첫 거래일 종가(close_t1) · lag-1 스트레스 arm S 병행",
               "C2: 모듈 보유 = exec_date <= 집행일인 마지막 스냅샷(모듈 자신의 시그널일 <= 시그널일) — 같은 날 가격 체결 없음(close_t1)",
               "C6·C10: 유니버스 = 시그널일 K200∪KQ150 시변 플래그 · 유동성 = shift(frollmean(Close×Vol,20),1) ≥ fixed_axes.liq_adv20_min",
               "C1(공개): arm K 의 Pbar = 창 전체 P 평균 → K 는 실시간 실행 불가 대조(후보 아님). 후보 집합 65 = 전기간 통계로 뽑힌 81 대표의 부분집합(잔여 선택 편향). 모듈 다수가 1계층 C1 표식(전기간 IC 선정·교차 entry 설계 노출)을 상속 — L1FLAGS",
               "Lockbox 폐지(v10) — 가용 전기간 사용 · IS/OOS anchored 분할(essence oos_retention)은 측정 규율로 유지")),
  measurement_regime = list(exec_price = "close_t1", current_axis = "exec_v2_close_t1", pin_tag = NULL, data_cutoff = DESIGN$window$data_cutoff,
                            cost_model_version = "replication_weight_delta_v1/first_hold_day_multiplicative",
                            harness_md5 = unname(as.character(tools::md5sum(file.path(ROOT, "02_Infrastructure/replication/replication_harness.R")))),
                            vintage_note = "pin_cache 스냅샷 없음(등록 차단 사유) — 러너 data_cutoff 절단 + data_fingerprint(pin_fp_v2)를 arm 마다 산출물에 싣고, 판정이 5 arm 지문 일치를 요구한다"),
  selection_accounting = list(selection_type = "chain", n_family = 1L, n_source = "Q-Lead 지시 — 주 처치 T_var 단일(chain/1) · 대조 4 arm 은 선택 후보 아님",
                              forking_paths = list(
                                predictor = "예측기 = IS(2005-01~2015-12) 분산 AUC 최대(MSM_asof 0.840 > HMM2_asof 0.815 > JM 0.756 · 적격 3후보) — IS 전용 규칙",
                                target_switch = "★표적 전환 공개: 사전 규칙(predictor_selection_IS.json)은 '방향' 표적이었고 MC1 방향이 IS 에서 실패(JM AUC 0.675 · CI 하한 0.487)한 **뒤** 분산 표적을 채택했다. 분산 표적의 선험 근거 = Moreira & Muir (2017) · Barroso & Santa-Clara (2015).",
                                oos_seen = "★predictor_oos_diagnostic.json(21:21 작성 · 이 사전등록 이전)이 OOS 분산 AUC(MSM 0.790/0.804 · HMM2 0.739/0.743 · JM 0.609)를 이미 보였다 — IS 순위와 같아 선택은 바뀌지 않지만 OOS 정보가 선택 시점에 열람 가능했다(분기 경로 위험 공개).",
                                weights = "w_hi·w_lo = 역할 집합 1/N(DeMiguel et al. 2009) — 최적화 없음"),
                              n_note = "DSR 미적용(chain) — 위 분기 경로를 감안하면 실효 시행 수는 1 보다 크다(최소 3 예측기 × 2 표적). 등록 단계 요구(sweep · n_family ≥ 2)와 다르다 → 등록 차단 사유"),
  dependencies = list(
    list(id = "L2-FLOOR-REGISTRY", what = "06_Registry/prereg/reference_floors_v2.json 에 L2 바닥(후보 풀 POOL65) 등재 경로", status = "unavailable",
         note = "rf_floor_v2.R 는 1계층 칸 바닥만 만든다 — 2계층 사전등록은 구조적으로 등록 불가(이 단위는 초안 sha256 잠금으로 대체 · 공개)"),
    list(id = "ENGINE", what = "allocator_engine.R(PORTFOLIO 계약)", status = "available", file = PINS$engine$path, sha256 = PINS$engine$sha256),
    list(id = "INPUTS", what = "동결 입력(work/l2v0_inputs_manifest.json)", status = "available", file = PINS$inputs_manifest$path, sha256 = PINS$inputs_manifest$sha256)),
  open_questions = list(),
  scope = list(label = "mechanism_only", a_eligible = FALSE, decision_ref = "L2V0-SCOPE (Q 위임 판단 2026-10-10)",
               statement = "후보 집합(65)이 전기간 통계로 뽑힌 대표의 부분집합이고 모듈 다수가 1계층 C1 표식을 상속한다 → 어느 arm 의 essence 가 Grade A 여도 A 후보가 아니다(Judge·BOOK 경로 없음 · 러너 judge_request 는 *.EXPERIMENT_HOLD.json 으로 보류). 라벨은 H1 기전의 판정일 뿐."),
  manipulation_checks = list(
    MC1 = list(rule = "IS 분산 AUC 95% CI 하한 > 0.5", source = "predictor_selection_IS.json results.MSM_asof_CrisisProb.variance.ci95 (IS 전용 · 기존 산출 · 블록 12 · B=5000)",
               known_before_registration = TRUE, value_ci95_lo = 0.718493691921139, auc = 0.839617768595041, pass = TRUE,
               note = "등록 전 이미 알려진 값(재계산 없음). 미달이었다면 T_var 미측정"),
    MC2 = list(rule = "as-of 방어 슬리브(동일가중 · 65 후보 교집합)의 창 안 약세월(사후 PS — 평가 표적 전용) β-잔차 평균 > 0 ∧ NW lag-3 t ≥ 1.0",
               nw_t_threshold = 1.0, contract = "strategy_role.R::sr_card + backtest_result_contract.R::.nw_t_mean",
               effect = "H1 라벨을 바꾸지 않는다 — 기전 해석(라벨 지속성) 판정. 실패 = '방어 라벨이 다음 약세로 이어지지 않는다'"),
    MC3 = list(rule = "mean_m ½Σ_r |w_T_var,r(m) − w_K,r| ≥ 0.05 (슬리브 수준 처치 전달량)", threshold = 0.05,
               effect = "미달 → H1 = undetermined(treatment not delivered) · 구 FR 의 EW 붕괴 재발 감지", computed_by = "sanity_l2v0.R(측정 전 · 비중만)",
               companion = "MC3b = 종목 수준 전달량 mean_m ½Σ_i |W_T,i − W_K,i| (보고 전용 · 판정 무관)")),
  verdict_procedure = list(
    script = PINS$verdict, rule_executor = "verdict_l2v0.R — 초안 criteria·decision_params·power.implied_effect·manipulation_checks 를 읽어 그대로 집행",
    rf_prereg_verdict = "미사용 예정 — 등록본 전용(초안 판정 거부). 등록이 차단되면 rf_record_decision 기록 없음 · 판정 파일 1회(덮어쓰기 거부)",
    vintage_rule = "5 arm 의 data_cutoff·data_fingerprint digest·exec_price 가 모두 같아야 판정(다르면 invalid:vintage_mismatch)",
    lock_rule = "arm 산출물 remeasured_at > 이 초안 색인 written_at 이어야 판정(아니면 invalid:measured_before_lock)",
    one_time = TRUE),
  run_plan = list(order = list("T_var", "K", "K_eq", "S", "EW_all"), driver = PINS$driver,
                  env = list(QVEST_RP_REGISTER = "0", QVEST_RP_NO_LCODE = "1", QVEST_NO_LEDGER_OPEN = "1", send_telegram = FALSE),
                  memory_gate = "arm 마다 여유 RAM ≥ 8GB(PowerShell Get-CimInstance) · 리프레시 배리어 대기", out_root = "04_Research/l2_role_rotation/runs/<arm>",
                  a_route = "Grade A 시 러너 judge_request*.json → *.EXPERIMENT_HOLD.json(2계층 Judge 경로 별도)"),
  pins = PINS,
  l1_flag_inheritance = L1FLAGS,
  disclosures = list(
    candidate_selection = "후보 65 = module_performance.json(close_t1 · 10-10 수리판) ∩ as-of 구성원 81. 81 대표는 전기간 역할 t + 사후 PS 연대기로 뽑혔다(README §6-1) — 라벨은 as-of 여도 후보 집합에 사후 선택 편향이 남는다(낙관 방향).",
    long_short_modules = "롱숏 모듈 2개(RP_20260902_122546_22268 · RP_20260907_101130_20668)의 음수 비중은 순합산에 그대로 들어간다(사양 문언) — 다른 모듈 롱을 상쇄하는 틸트로 작동",
    stale_snapshots = "보유 스냅샷이 2026-08-03(25 모듈)·2025-12-01(2)·2026-07-01(분기 5)에서 끝나는 모듈은 마지막 스냅샷을 그대로 보유(모듈 자신의 마지막 결정 · PIT 안전 · 낡음)",
    k_noncausal = "K 의 Pbar 는 창 전체 P 평균 — 실시간 불가 대조. T_var−K = (P−Pbar)×(w_hi−w_lo) 슬리브 대비의 시간 공분산(타이밍 기여)을 재는 장치",
    mean_vs_variance = "H1 은 평균 차를 묻는다. M&M 기전의 1차 예측(분산 감소)은 calmar_delta_boot·arm 별 MDD/Calmar 로 보고만 한다.",
    rebound_sleeve_size = "반등 슬리브는 창 중 2~43(중앙 13) — 작을 때는 소수 모듈이 w_lo 의 ⅓ 을 진다",
    diversifier_excluded = "diversifier 역할은 as-of 라벨이 없어 제외(README §2.3)"),
  reporting_obligations = list(
    "scope = mechanism_only — A 후보·Judge·BOOK 아님(러너 judge_request 보류 표식)",
    "H1 t · 라벨 · MC1/MC2/MC3(+MC3b) · 5 arm essence(PORT_t·SR·CAGR·MDD·Calmar·OOS)",
    "S−K·T−S(lag-1 스트레스) · calmar_delta_boot · nw_lag 21 강건성",
    "등록 차단 사유 전부(prereg_registration_attempt_v0.json) — 이 단위의 결과 전 잠금은 초안 sha256 + 색인 written_at",
    "모든 결과 = 반증 시도 · 미결을 벽으로 적립하지 않음(AX-000)"),
  not_a_grade = "등급은 essence 하나 — 이 사전등록의 라벨은 등급을 대체하지 않는다"
)

# ── ④ 초안 쓰기 ────────────────────────────────────────────────────────────────
v0 <- rf_prereg_validate(pr, "draft", ROOT, cfg)
if (!v0$ok) stop("[prereg_l2v0] 초안 검증 실패:\n  - ", paste(v0$errors, collapse = "\n  - "))
w <- rf_prereg_write(pr, "draft", ROOT, cfg)
# ── ⑤ 등록 단계 검증 · ⑥ 등록 시도 ─────────────────────────────────────────────
d <- rf_prereg_load(pr$prereg_id, "draft", root = ROOT, cfg = cfg)
vr <- rf_prereg_validate(d, "registered", ROOT, cfg)
reg <- tryCatch({ r <- rf_prereg_register(pr$prereg_id, registered_by = "Q(2계층 단위 #1 세션)", root = ROOT, cfg = cfg); list(ok = TRUE, result = r) },
                error = function(e) list(ok = FALSE, error = conditionMessage(e)))
idx <- Filter(function(r) identical(r$prereg_id, pr$prereg_id), rf_prereg_index(ROOT, cfg))
att <- list(schema = "l2v0_prereg_attempt_v1", prereg_id = pr$prereg_id, at = now(),
            draft = list(path = w$rel, sha256 = w$sha256, index_rows = idx),
            registration_blockers = as.list(vr$registration_blockers), registered = reg$ok,
            register_error = reg$error %||% NULL,
            conclusion = if (isTRUE(reg$ok)) "등록됨 — 판정은 rf_prereg_verdict 로" else
              "등록 차단 — 결과 전 잠금 = 초안 sha256 + 색인 written_at(측정은 이 뒤). 판정은 verdict_l2v0.R 가 초안 규칙을 그대로 집행(rf_record_decision 기록 없음).",
            config_sha256 = attr(cfg, "sha256"))
writeLines(toJSON(att, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), ATTEMPT, useBytes = TRUE)
cat(sprintf("[prereg_l2v0] 초안 %s (sha256 %s) · 등록 %s · 차단 사유 %d건\n", w$rel, substr(w$sha256, 1, 12),
            if (isTRUE(reg$ok)) "성공" else "차단", length(vr$registration_blockers)))
for (b in vr$registration_blockers) cat("  - ", b, "\n", sep = "")
