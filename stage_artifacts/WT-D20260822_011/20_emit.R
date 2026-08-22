## WT-D20260822_011 — 산출 (관문 FAIL · 처치 백테스트 미실행)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_011")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260822_011")
say <- function(f, ...) cat(sprintf(paste0("[e] ", f, "\n"), ...))

PC <- fromJSON(file.path(OUT, "00_precheck.json"))
DG <- fromJSON(file.path(OUT, "11_diag.json"))
FX <- fromJSON(file.path(OUT, "12_falsify.json"))
GC <- fromJSON(file.path(OUT, "13_gatecheck.json"))
HY <- fromJSON(file.path(MB, "alpha_hypothesis.json"))
PG <- fromJSON(file.path(OUT, "PREREG_GATE.json"))

## ── alpha_validation.json ──────────────────────────────────────────────────
V <- list(
  task_id = "WT-D20260822_011",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  round_outcome = "PRE_MEASUREMENT_GATE_FAIL — 처치(tie-break) 백테스트 미실행",
  measurement_executed = list(
    treatment_backtest = FALSE,
    weighted_screen_bt_calls = "1회 (base anchor 재현 STOP 검증 전용)",
    rationale = "request.json 명문 + PREREG_GATE.gate_arithmetic.pass_rule — 순 함의/MDE80 < 1/10 이면 측정하지 않고 산술과 함께 중단."),
  prereg = list(file = "stage_artifacts/WT-D20260822_011/PREREG_GATE.json",
    sealed_before_run = TRUE, epsilon_single_fixed = TRUE, selection_type = "chain",
    dsr_gate_applicable = FALSE,
    dsr_rationale = "sweep 아님 — epsilon 을 1개만 사전 고정했고, 설계공간 상한 격자는 백테스트 0회·구성 승계 0건의 필요조건 검사다(measurement-graduation §3 selection_type=chain)."),

  base_anchor = PC$base_anchor,
  base_reproduction = PC$base_reproduction,
  object_inheritance = PC$inheritance,

  epsilon = PC$epsilon,
  design_property = list(
    margin_bound_verified = PC$gate$margin_bound_ok,
    margin_bound_max_observed = PC$gate$margin_bound_max,
    epsilon = PC$gate$eps,
    realized_margin_mean = PC$gate$realized_margin_mean,
    reading = paste0("★설계는 작동했다 — 밀려난 종목과 편입 종목의 score_eff 최대 격차 ",
      sprintf("%.6f", PC$gate$margin_bound_max), " < epsilon ", sprintf("%.6f", PC$gate$eps),
      " 가 전 월에서 성립. 실현 평균 격차 ", sprintf("%.6f", PC$gate$realized_margin_mean),
      ". 즉 '여백 손실이 구조적으로 epsilon 에 갇힌다'는 설계 주장은 검증됐다. 실패한 것은 그 다음 — 여백을 지키면 기전 함의도 함께 줄어든다는 상충이다.")),

  gate = list(
    fixed_epsilon = PC$gate, threshold = 0.10,
    feasibility_bound = PC$feasibility_bound,
    conductivity_check = GC,
    verdict = "FAIL — 사전 고정 epsilon ratio 0.0089 · 설계공간 상한(어떤 epsilon 이든) 0.04~0.05 대 < 0.10"),

  falsification = FX,
  diagnostics = DG,
  wt010_gate_recheck = PC$wt010_gate_recheck,
  pit = PC$pit,

  labels = list(
    detection_axis = "미결(underpowered) 이 아니라 **크기 부족** — 기전-함의가 이 창의 MDE80 의 1/11(사전 고정 epsilon) ~ 1/19(설계공간 상한)이라 어떤 검정으로도 이 소비 형태에서 기전을 분리할 수 없다.",
    capital_gate_axis = "미충족 — 측정하지 않았으므로 ΔIR 점추정 자체가 없다. transition_gates 미충족(협상 없음).",
    masked_check = "가려짐 아님 — 동일 산술이 기측정 양성(MAX5, ΔIR +0.1642)에 ratio 0.2838 을, 무작위 음성 대조에 -0.0308 을 부여한다(13_gatecheck.json). 관문은 눈멀지 않았다.",
    conductivity_ceiling = PG$conductivity_ceiling$statement),

  key_findings = list(
    list(id = "K1", title = "설계는 작동했으나 편익과 손실이 같은 축에 실려 있다",
      detail = "여백 손실은 실제로 epsilon 에 갇혔다(상한 검증 전 월 통과). 그런데 근접쌍 조건화 시 꼬리 격차가 pooled 0.00805 -> 0.00210 으로 줄고 월별 스프레드 NW t = +0.211(미결)이다 — 여백을 지우면 기전 격차도 같이 지워진다. epsilon 은 편익과 손실을 **분리하는 레버가 아니라 둘을 동시에 조절하는 레버**였다."),
    list(id = "K2", title = "top-25 경계에서 base score 는 국소 단조가 아니다",
      detail = "월별 횡단면 slope of Ret_1m ~ score_eff: 랭크 1-25 +0.009103 (NW t +1.93) / **랭크 20-40 -0.043437 (NW t -2.42)** / 1-100 +0.008788 (t +4.21). 경계 대역에서 기울기가 음수·유의다 — '랭킹 여백에 지킬 알파가 있다'는 WT-010 의 손실 귀속 서술이 그 대역에서는 성립하지 않는다. advisory 진단(대역 4개 조회, 다중비교 미보정)."),
    list(id = "K3", title = "WT-010 관문은 편익 대비항을 잘못 잡아 통과했다",
      detail = "대비항을 '배제군 vs 잔류군'(0.00805)에서 '배제군 vs 대체편입군'(0.00310)으로, 산포를 WT-009 상수(0.01595)에서 실현치(0.02023)로 정정하면 0.1465 -> 0.0445 로 문턱 아래다. 두 정정 모두 측정 전 계산 가능했다(대체편입군 = 랭킹으로 결정되는 결정론적 집합)."),
    list(id = "K4", title = "부수 census 관측은 판정이 아니다",
      detail = DG$incidental_swap_census$label)),

  next_probe = list(
    list(id = "NP1", priority = 1,
      title = "관문 편익항 표준화 — 대비항은 '대체편입군', 산포는 교체 census 실측",
      detail = "WT-009(1/26 사후 발견) · WT-010(0.1465 통과 후 실측 역방향) · WT-011(0.0089) 세 라운드가 같은 관문을 세 가지 다른 방식으로 계산했다. gate_of() 를 계약 함수로 승격해 (a)대체편입군 대비 (b)census sd (c)양성/음성 대조 동반을 강제하면, '배제/후순위' 계열 소비 형태는 착수 전에 백테 0회로 걸러진다. 본 라운드가 이미 3구성(tie-break/MAX5/random)에서 작동 실증.",
      consumption_surface = "QEPM alpha 착수 관문 · 02_Infrastructure/contracts/"),
    list(id = "NP2", priority = 2,
      title = "top-25 경계 국소 비단조(K2)의 소비 형태 — cut point 자체를 묻는다",
      detail = "랭크 20-40 slope -0.0434 (t -2.42) 가 재현되면, 소비 형태는 '표식 종목을 미는 것'이 아니라 '경계를 어디에 둘 것인가'다(top-25 hard 는 고정 축이므로 완화 대상 아님 — 대신 25종 안에서 랭크 20-25 를 다른 후보로 바꾸는 규칙). 사전등록 필요: 다중비교 보정된 대역 profile + 명목-일치 교체 설계 + 자체 검정력.",
      consumption_surface = "팩터 랭킹 · 선별 라벨"),
    list(id = "NP3", priority = 3,
      title = "직교화 표식의 risk-input 소비 (WT-009 C2 보관분)",
      detail = "3라운드(009 raw 배제 / 010 직교 배제 / 011 tie-break)가 전부 **선정 규칙** 면에서 소비했고 전부 관문 또는 게이트에 걸렸다. 남은 미측정 소비면 = risk 입력(공분산·꼬리 예산). 표식의 N2 지지(하락일 개인지지 NW t -14.59)는 강한데 선정 면 전이가 안 되는 패턴은 '랭킹이 아니라 위험 예산으로 쓰라'는 신호일 수 있다. ★역할 경계: 이 라운드는 risk-research 소관이며 alpha 가 수행하지 않는다.",
      consumption_surface = "위험모델 · beta 예산"),
    list(id = "NP4", priority = 4,
      title = "명목-일치(weight-matched) 교체 설계의 사전등록",
      detail = "009(2.30배) -> 010(1.14배) -> 011(1.32배) 로 교체 양 다리의 명목 비대칭이 세 라운드 모두 남았다. cap_norm(Size) 가 편입 종목에 더 큰 비중을 주기 때문이다. 비대칭을 제거한 설계(동일 명목 교체)가 있어야 '교체효과'와 '순노출 이동'이 분리된다. ★비중 조작은 optimizer 소관 — alpha 는 요구사항만 이관.",
      consumption_surface = "optimizer 인터페이스")),

  revival_conditions = list(
    "관문 편익항이 NP1 로 표준화되고, 그 표준 하에서 어떤 소비 형태가 ratio >= 0.10 을 내면 그 형태로 재개",
    "N4(근접쌍 꼬리 판별력)가 다른 창 또는 다른 표식 정의에서 NW-t >= +2.0 로 지지되면 tie-break 재시험",
    "top-25 경계 국소 slope(K2)가 다중비교 보정 후에도 음수 유의면 NP2 로 재개",
    "표식의 risk-input 소비(NP3)에서 양성이 나오면 선정-면 소비를 다시 묻는다"),
  scope_note = "config-scoped negative — 이 판정은 (표식 = NP2 직교화 하위 20%) x (소비 = epsilon tie-break) x (base = STR_1715 cleanT1 cap-w top-25) x (창 268월) 구성에 한정된다. 기전 자체의 판결이 아니다(N2 지지 NW t -14.59 유지, 반증 4축 발화 0)."
)
write_json(V, file.path(OUT, "alpha_validation.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
saveRDS(V, file.path(OUT, "alpha_validation.rds"))
say("alpha_validation.json 기록")

## ── alpha_package.json ─────────────────────────────────────────────────────
AP <- list(
  task_id = "WT-D20260822_011",
  as_of_date = "2026-08-22",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  pit = list(sig_date = "2026-03-31", decision_ts = "2026-03-31"),
  hypothesis = HY$hypothesis,
  hypothesis_source = list(file = "qepm/mailbox/worktask/WT-D20260822_011/alpha_hypothesis.json",
    designed_by = "alpha-hypothesis", inherited_verbatim = TRUE,
    note = "mechanism / falsification / regime_scope 재작성 없음(Charter 원칙 8). N4 는 alpha-hypothesis 가 신설한 축이며 본 에이전트가 실측만 수행했다."),
  inherited_from = "WT-D20260822_010 (기전 CONFIRMED · 배제 소비형태 ΔIR -0.0899) → 소비 형태만 교체",
  consumption_gate_precheck = list(
    executed = TRUE, passed = FALSE,
    fixed_epsilon_ratio = PC$gate$ratio, design_space_sup_ceiling = PC$feasibility_bound$sup_ceiling_ratio,
    threshold = 0.10, conductivity_verified = GC$verdict$gate_conductive,
    action = "처치 백테스트 미실행 · 중단 보고 (request.json 명문 + PREREG_GATE)"),
  factors = list(list(
    factor_id = "F1_epsilon_tiebreak_on_base_score",
    ast = list(op = "SUBTRACT", args = list(
      list(leaf = "STORED_SCORE",
        provenance = list(
          store_build_hash = "alpha_scores_str1715_268m_cleanT1 / anchor screen_cap_w_top25 port_t_nw_lag3 = 3.05833912319022 (본 라운드 재현 STOP 통과)",
          generator_code_path = "05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/01_reproducible_code/_recompute_alpha_asof.R",
          generated_at = "2026-07-14 17:57:33", production_parity_verified = TRUE),
        production_parity_verified = TRUE,
        escape_contract = list(escape_type = "STORED_SCORE",
          provenance = list(
            store_build_hash = "alpha_scores_str1715_268m_cleanT1 / anchor 3.05833912319022",
            generator_code_path = "05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/01_reproducible_code/_recompute_alpha_asof.R",
            generated_at = "2026-07-14 17:57:33", production_parity_verified = TRUE),
          production_parity_verified = TRUE)),
      list(op = "MULTIPLY", args = list(
        PC$gate$eps,
        list(op = "WHERE", args = list(
          list(op = "CS_RANK_PCT", args = list(list(leaf = "SPECIAL_OP",
            op_code_path = "stage_artifacts/WT-D20260822_010/00_precheck.R (score_orth = z(resid(lm(winsor(absorb_raw) ~ z(rank(win_vol)) + z(rank(log_size))))) by Date, 계약 distribution_target_screen.R::.dts_orthogonalize_by_date) — absorb_raw 원천 = stage_artifacts/WT-D20260813_006/01_build_features.py (absorb = -corr_win(Individual_d, Ret_d), 3개월 창, d0 당일 차감). 본 라운드는 해당 산출물을 verbatim 승계(md5 대조)했고 재구현하지 않았다.",
            walk_forward = TRUE,
            escape_contract = list(escape_type = "SPECIAL_OP",
              op_code_path = "stage_artifacts/WT-D20260822_010/00_precheck.R + 02_Infrastructure/contracts/distribution_target_screen.R::.dts_orthogonalize_by_date",
              walk_forward = TRUE)))),
          0.20)))))),
    role = "core_signal",
    restatement_exposure = 1,
    restatement_note = "STORED_SCORE 리프가 ast_field_map 미등재 → 보수 표시(WARN_RESTATEMENT). 상류 factor_db vintage 를 본 라운드가 증명하지 않았으므로 '확인 불가'를 '확인 완료'로 내려앉히지 않는다(WT-010 승계).")),
  combination_rule = "single_factor",
  verdict = "designed",
  ast_expressiveness_note = "epsilon tie-break 은 𝒪 안에서 표현된다 — 저장 base score 에서 (epsilon x 표식 지시자)를 빼는 산술. blocked_by_capability 아님. 𝒪 확장 요구 없음.",
  self_pit_check = list(performed = TRUE, leaves_checked = list(
    list(leaf = "STORED_SCORE:alpha_scores_str1715_268m_cleanT1.score_eff",
      availability_rule = "fixed: production 컨벤션 label = T-1 산출 · label월 보유. §7b production_parity_verified stopifnot + anchor PORT_t 3.05833912319022 재현 STOP 통과(실측 일치).",
      restatement_prone = FALSE),
    list(leaf = "SPECIAL_OP:orth_absorb_3m",
      availability_rule = "fixed: 일별 investor_wide(T+1 정산) + RAWDATA 를 창 {m-2,m-1,m} 집계, 신호일 d0 당일 관측 차감(strict Date < d0). 직교화는 동월 횡단면만(pooled/full-sample 회귀 경로 없음 — 계약이 물리 차단). 홀딩월 = m+1, 컷오프 = 홀딩월 1일. assert_overlay_pit 268/268 PASS + 위반 주입 0/268(검사기 생존 확인).",
      restatement_prone = FALSE)),
    verdict = "clean",
    notes = "저장 파생 패널을 FIELD 리프로 위장하지 않았다(§4-1). epsilon 은 상수(자유 파라미터 1개)이며 수익 정보로 조율되지 않았다 — 도출식 입력은 WT-010 기측정치와 base 패널 기울기뿐."),
  alpha_vector = setNames(list(), character(0)),
  alpha_vector_note = "빈 객체 = 본 라운드는 착수 전 관문에서 중단해 배포용 alpha 를 산출하지 않았다. 값을 채우면 '측정하지 않은 알파'를 산출한 것처럼 보이므로 비운다(fail-closed).",
  confidence_vector = setNames(list(), character(0)),
  signal_matrix_ref = "stage_artifacts/WT-D20260822_011/00_precheck_objects.rds (SEL/Wb/EPS — 처치 스코어 패널 미발행)",
  factor_specs = list(list(
    factor_family = "Flow_Behavioral_Orthogonalized",
    proxy = "epsilon tie-break on low-orth absorb flag (X=0.20, epsilon = 0.23052149958407 score_eff units)",
    formula = "sc_adj = score_eff - epsilon * 1{CS_RANK_PCT(orth_absorb_3m) <= 0.20} ; top-25 by sc_adj, cap_norm(Size)",
    lag_rule = "signal from months {m-2,m-1,m} with strict Date < d0; holding month m+1 (assert_overlay_pit 268/268)",
    winsorization = "회귀 좌변 [0.01,0.99] (NP2 계약 verbatim)",
    neutralization = "win_vol + log_size (월별 횡단면 rank-OLS 잔차, NP2 계약)",
    economic_rationale = "behavioral",
    weight_theta = 1.0,
    references = list("Miller 1977 (공매도 제약 하 의견 분산)",
      "Harvey, Liu & Zhu 2016 (다중검정 hurdle — 관문 문턱의 근거)",
      "Bailey & Lopez de Prado (DSR — 관측 후 게이트 재정의 금지)"))),
  diagnostics = list(
    canonical_port_t_nw_lag3 = NULL,
    canonical_port_t_note = "null = **미산출**. 착수 전 관문 FAIL 로 처치 백테스트를 실행하지 않았다 — 사유는 challenge_flags 및 alpha_validation.json$gate 참조. base anchor(cap-w weighted_screen) 3.05833912319022 는 재현 검증용이며 처치 수치가 아니다.",
    canonical_n_months = NULL,
    weighted_screen_port_t_base = PC$base_anchor$port_t,
    rank_ic = DG$base_advisory$rank_ic,
    rank_ic_note = "base score_eff 의 IC (처치 아님). advisory — measurement-graduation §3.",
    icir = DG$base_advisory$icir,
    rank_ic_t = DG$base_advisory$ic_nw_t,
    alpha_inheritance_cor = DG$inheritance$pearson_sc_adj_vs_sc,
    alpha_inheritance_note = "Pearson 0.993025 / Spearman 0.990067 > 0.95 → v1.2 Charter §10 wt_type 재분류 권고 대상. 본 라운드는 신규 alpha 가 아니라 동일 alpha 의 소비 형태 변경이며 alpha_discovery_certificate 미발급이 정상.",
    turnover_proxy = PC$gate$turnover_delta_annual,
    turnover_note = "census 산술(traded_t = sum|w_t - w_{t-1}|, weighted_screen_bt 규약 동일). tie-break 은 회전을 오히려 -4.9%p/yr 줄인다 — 완전 배제(+24.8%p)와 반대 방향."),
  alpha_discovery_count = 0L,
  alpha_discovery_count_note = "0 = 착수 전 관문 FAIL 로 alpha 미산출. wt_type=discovery 이나 certificate 미발급이 정상 동작(passive deny).",
  selection_objective = "canonical_port_t",
  selection_objective_note = "선택 권위는 canonical/weighted PORT_t 이나 본 라운드는 후보 선택 자체를 하지 않았다(관문 중단). epsilon 은 성과가 아니라 구조 산술로 도출한 단일 사전 고정값.",
  n_trials = 1L,
  selection_type = "chain",
  method_shopping_log = list(candidates_tried = 1L, method_log = list(
    list(name = "epsilon_tiebreak(eps=0.23052149958407, X=0.20)", gate_ratio = PC$gate$ratio, selected = FALSE,
         note = "관문 FAIL — 백테스트 미실행"))),
  verdict_summary = paste0("PRE_MEASUREMENT_GATE_FAIL — 사전 고정 epsilon ratio ",
    sprintf("%.4f", PC$gate$ratio), ", 설계공간 상한(어떤 epsilon 이든) ",
    sprintf("%.4f", PC$feasibility_bound$sup_ceiling_ratio), " < 문턱 0.10. 관문 전도성 검증됨(양성 대조 0.2838 / 음성 대조 -0.0308). transition_gates 미충족 — 협상 없이 config-scoped negative."),
  challenge_flags = list(
    "[HIGH] epsilon 도출식 결함(C1) — beta_hat 을 랭크 1-40 에서 쟀는데 교체 대역(20-40) 실측 기울기는 -0.043437 (NW t -2.42) 로 음수·유의. 교체 대역에서 쟀다면 epsilon 이 음수가 되어 식이 정의되지 않는다. 기울기 역수 앵커 규칙 폐기 권고. 결론 영향 없음(설계공간 상한이 epsilon 무관).",
    "[HIGH] top-25 경계 국소 비단조(K2) — 랭크 20-40 slope 음수 유의. WT-010 의 '랭킹 여백 강제 소비' 손실 귀속이 그 대역에서는 성립하지 않는다. advisory(대역 4개 조회, 다중비교 미보정) — NP2 로 사전등록 후 재확인 필요.",
    "[MEDIUM] WT-010 관문 재검(K3) — 편익 대비항/산포 정정 시 0.1465 -> 0.0445 로 문턱 아래. 그 라운드는 통과하지 말았어야 했다. 두 정정 모두 측정 전 계산 가능.",
    "[MEDIUM] 부수 census 관측 — 명목일치 연 +1.019%p (NW t +1.19). 기전-함의의 25.2배라 기전 귀속 불가 · 양성 대조는 같은 census 에서 t +2.43 · 명목 비대칭 1.32배 미제거. 판정 아님, NP4 로 이관.",
    "[MEDIUM] alpha_inheritance_cor 0.993 > 0.95 — wt_type 재분류 권고(governance_log reclassify_proposal 기록).",
    "[LOW] 설계공간 상한 격자의 dtail 이 작은 epsilon 구간에서 불안정(-0.029 ~ +0.006). sup 0.0522 를 정밀 수치로 인용하지 말 것 — 안정 구간 상한은 0.042.",
    "[LOW] sd_gate 가 재정규화 채널 제외 — 대형 epsilon 점에서 census sd 0.0214 vs WT-010 실측 0.0202(+5.9%, MDE80 을 키우는 방향). 소규모 교체 구간의 잔여 불확실성은 미검증으로 표기.",
    "[LOW] basis 3종 병기 / lag1 / strict-PIT A/B 는 처치 측정이 있어야 산출된다 — 관문 중단으로 미산출(부재 사유 명시). PIT 정적 검사는 수행: assert 268/268 PASS · 위반 주입 0/268.",
    "[전도성 상한] 이 창·이 소비 형태에서 양성 대조조차 paired NW t 1.566 — 유의성 수준 판정은 원리적으로 불가하며 ΔIR 점추정 게이트만 유효(모든 판정 서술에 병기)."),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
write_json(AP, file.path(MB, "alpha_package.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
say("alpha_package.json 기록")

source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(task_id = "WT-D20260822_011", package_type = "alpha_package",
  method_selected = "epsilon tie-break (X=0.20, eps=0.23052149958407) — 착수 전 관문 FAIL, 처치 백테 미실행",
  input_file_paths = c(
    "stage_artifacts/WT-D20260822_010/00_precheck_objects.rds",
    "stage_artifacts/WT_D20260714_004/screen_inputs.rds",
    "stage_artifacts/WT-D20260813_006/alpha_scores.parquet",
    "stage_artifacts/WT_D20260802_010/ot_panel.parquet",
    "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet",
    "qepm/mailbox/worktask/WT-D20260822_011/alpha_hypothesis.json"))
say("lineage 기록 완료")

## ── status / governance ────────────────────────────────────────────────────
ts <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
write_json(list(task_id = "WT-D20260822_011",
  current_phase = "ALPHA_DONE_NON_GRADUATING", updated_at = ts,
  blocker = paste0("착수 전 관문(NP4 규약 3판) FAIL — 사전 고정 epsilon ratio ",
    sprintf("%.4f", PC$gate$ratio), " / 설계공간 상한 ", sprintf("%.4f", PC$feasibility_bound$sup_ceiling_ratio),
    " < 문턱 0.10. 처치 백테스트 미실행. 관문 전도성 검증됨(양성 대조 0.2838). 반증 4축 발화 0 — 실패 지점은 기전이 아니라 편익과 여백손실이 같은 축에 실려 epsilon 이 둘을 분리하지 못한다는 점.")),
  file.path(MB, "status.json"), auto_unbox = TRUE, pretty = TRUE)
G <- fromJSON(file.path(MB, "governance_log.json"), simplifyVector = FALSE)
G$events <- c(G$events, list(
  list(timestamp = ts, agent = "alpha-research", action = "PRE_MEASUREMENT_GATE_FAIL",
    summary = paste0("epsilon tie-break 착수 전 관문 FAIL. ratio ", sprintf("%.4f", PC$gate$ratio),
      " (설계공간 상한 ", sprintf("%.4f", PC$feasibility_bound$sup_ceiling_ratio),
      ") < 0.10. 처치 백테 미실행 — request.json 명문 준수. 관문 전도성 양방향 검증(양성 MAX5 0.2838 / 음성 random -0.0308).")),
  list(timestamp = ts, agent = "alpha-research", action = "reclassify_proposal",
    summary = "wt_type=discovery 이나 alpha_inheritance_cor Pearson 0.993025 / Spearman 0.990067 > 0.95 — v1.2 Charter §10 재분류 권고(동일 alpha 의 소비 형태 변경). alpha_discovery_certificate 미발급이 정상. 도훈 confirm 후 wt_advance."),
  list(timestamp = ts, agent = "alpha-research", action = "SELF_ADVERSARIAL_CHALLENGE",
    summary = "concern 7건 — ACCEPT 2(C1 epsilon 도출식 결함 / C5 wt_type 재분류) · PARTIAL 3(C3 sd 채널 / C4 74% 서술적 / C6 격자 불안정) · REBUTTAL 2(C2 부수관측 미측정 / C7 WT-010 관문 정정). HIGH 1건 < 5, AX hard FAIL 0, PIT C1 위반 0 → 자동 escalate 미충족. challenge_note.md 기록.")))
write_json(G, file.path(MB, "governance_log.json"), auto_unbox = TRUE, pretty = TRUE)
say("status/governance 갱신 — done")
