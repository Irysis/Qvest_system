## WT-D20260822_003 / FQ-234 NP2 — 산출물 발행
##  ① alpha_scores_ref.json (패널 **복제 금지** — 포인터 + sha256)
##  ② alpha_package.json (Lane B hypothesis/factors **그대로 승계**, 재작성 없음)
##  ③ governance_log reclassify_proposal (inheritance_cor = 1.0)
##  ④ lineage 기록 — ★반드시 alpha_package.json write **이후** (L-194)
suppressMessages({ library(jsonlite); library(digest) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
SRC <- file.path(ROOT, "stage_artifacts/WT-D20260813_006")
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_003")
MBX <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260822_003")
dir.create(MBX, recursive = TRUE, showWarnings = FALSE)

PANEL <- file.path(SRC, "alpha_scores.parquet")
ref <- list(
  wt_id = "WT-D20260822_003",
  role = "alpha_scores 포인터 — 본 WT 는 패널을 복제하지 않는다",
  points_to = "stage_artifacts/WT-D20260813_006/alpha_scores.parquet",
  sha256 = digest(PANEL, algo = "sha256", file = TRUE),
  size_bytes = file.info(PANEL)$size,
  alpha_inheritance_cor = 1.0,
  rationale = paste0(
    "본 라운드는 동일 바이트 패널의 **재판정**이다. 새 WT id 로 같은 내용을 재발행하면 ",
    "이명 복제(2026-08-20 batch_434 계통 — catalog 130/275 가 실산출물 30개의 이명이었던 사건)를 ",
    "재생산한다. 포인터 + 해시로 동일성을 증명하고 원본 하나만 남긴다."),
  emitted_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
write_json(ref, file.path(OUT, "alpha_scores_ref.json"), auto_unbox = TRUE, pretty = TRUE, na = "null")

LB  <- fromJSON(file.path(SRC, "../../qepm/mailbox/worktask/WT-D20260813_006/alpha_package.json"),
                simplifyVector = FALSE)
SUM <- fromJSON(file.path(OUT, "np2_summary.json"), simplifyVector = FALSE)
VAL <- fromJSON(file.path(OUT, "alpha_validation.json"), simplifyVector = FALSE)

pkg <- list(
  task_id = "WT-D20260822_003",
  fq_ref = "FQ-234 NP2",
  produced_by = "alpha-research",
  as_of_date = "2026-08-22",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  round_type = "re-adjudication",

  prereg_ref = "stage_artifacts/WT-D20260822_003/PREREG_NP2.json",
  challenge_note_ref = "qepm/mailbox/worktask/WT-D20260822_003/challenge_note.md",
  validation_ref = "stage_artifacts/WT-D20260822_003/alpha_validation.json",

  ## ── 승계 (재작성 금지, Charter 원칙 8) ─────────────────────────────────────
  hypothesis = LB$hypothesis,
  factors = LB$factors,
  combination_rule = LB$combination_rule,
  self_pit_check = LB$self_pit_check,
  inheritance = list(
    source = "qepm/mailbox/worktask/WT-D20260813_006/alpha_package.json",
    fields_inherited_verbatim = c("hypothesis", "factors", "combination_rule", "self_pit_check"),
    modification = "NONE — mechanism / falsification / regime_scope 및 AST 전량 무수정 복제.",
    alpha_inheritance_cor = 1.0,
    alpha_discovery_count = 0,
    note = paste0("본 라운드는 신규 알파를 설계하지 않았다. 동일 score 패널을 신설 분포-표적 ",
                  "계약으로 재판정했을 뿐이다.")),

  ## ── 본 라운드가 실제로 산출한 것 ───────────────────────────────────────────
  verdict = "designed",
  verdict_note = paste0("verdict enum 은 AST 설계 상태를 가리키며 승계분 그대로 'designed'. ",
                        "본 라운드의 판정은 아래 route_gate 이다 — 알파 채택 판정이 아니다."),
  distribution_screen = list(
    metric_type = "distribution_screen",
    contract_version = SUM$contract_version,
    capital_eligible = FALSE,
    route = "DISTRIBUTION_TARGET",
    eligible = TRUE,
    binding_run = "R1_PRIMARY (rank 2축 통제 / 비중첩 2창 2015-12-01 / 고정 문턱 +-0.20)",
    survived_axes_any_window = SUM$R1_primary_binding$survived_any,
    survived_axes_all_windows = SUM$R1_primary_binding$survived_all,
    strength_grading_ref = "alpha_validation.json::strength_grading",
    invariant_core_axis = "tail_dn_prob_diff",
    artifacts = SUM$prereg),

  selection_type = "chain",
  n_trials_cumulative = 1,
  selection_objective = "canonical_port_t",
  selection_objective_note = paste0(
    "본 라운드는 후보 선택을 수행하지 않았다(재판정 1건). selection_objective 는 ",
    "승계 라운드의 값을 그대로 기록한 것이며, 분포 통계량을 선택 목적함수로 쓰지 않았다."),

  diagnostics = list(
    canonical_port_t_nw_lag3 = -0.318,
    canonical_port_t_source = "Lane B 승계 (metric_type=canonical_screen, long 315m). 본 라운드 재산출 없음.",
    canonical_n_months = 315,
    rank_ic = -0.0315,
    icir = -0.239,
    harvey_t_stat = -4.243,
    advisory_note = "rank-IC 계열 전량 사전등록 방향 대비 음수 — 부호 반전 주장 금지(C13).",
    mean_space_label = "NEGATIVE_POWERED (효과 검출 축)",
    capital_grade_label = "INCONCLUSIVE_UNDERPOWERED (자본 등급 축 — 이 창에서 2.95 도달 불가, 양성 대조 상한 1.674)"),

  challenge_flags = list(
    list(id = "CF1", severity = "HIGH",
         flag = "증거 강도가 통제 사양에 종속 — 최강 통제(raw+rank 동시 4축)에서 후반 창 붕괴, 두 창 생존 축 4개 -> 1개",
         disposition = "ACCEPT — challenge_note C2, alpha_validation strength_grading 에 표로 기재"),
    list(id = "CF2", severity = "HIGH",
         flag = "사전등록이 블라인드가 아님 — 착수 전 동일 계약의 비중첩 창 산출물(eligible=true)이 존재했고 열람함",
         disposition = "ACCEPT — PREREG_NP2 §contamination_disclosure 에 축별 수치까지 봉인, challenge_note C5"),
    list(id = "CF3", severity = "MEDIUM",
         flag = "왜도 축은 2010년 이후 국한 — 3창 진단에서 2000~2010 부호 반대(+0.48/+0.96)",
         disposition = "PARTIAL — 결론 주축을 좌측 꼬리 축으로 좁힘, next_probe NP2-P3"),
    list(id = "CF4", severity = "MEDIUM",
         flag = "사전등록 정당화 문장('rank 가 항상 더 강한 통제')이 자체 진단에 반증됨",
         disposition = "ACCEPT — 문장 철회, challenge_note C1"),
    list(id = "CF5", severity = "LOW",
         flag = "꼬리 확률 축이 문턱 규약 종속 (rolling 문턱에서 tail_dn late -1.875)",
         disposition = "ACCEPT — 문턱 무관 축(qspread_p10) 병기, challenge_note C7"),
    list(id = "CF6", severity = "LOW",
         flag = "계약 API 공백 — control_transform 이 단일값이라 최강 통제가 호출자 관례에 숨는다",
         disposition = "보고만 — 계약 임의 확장 금지, next_probe NP2-P5")),

  capital_prohibition_attestation = paste0(
    "본 패키지는 PORT_t / oos_retention / calmar / SR / IR / MDD 를 **산출하지 않았다**. ",
    "diagnostics.canonical_port_t_nw_lag3 는 Lane B 승계 기록치이며 본 라운드의 분포 통계로 ",
    "대체·근사한 값이 아니다. DISTRIBUTION_TARGET 은 screening tier 라벨이며 자본 자격이 아니다 ",
    "(.claude/rules/measurement-graduation.md §1·§3)."),

  next_probe = VAL$next_probe,
  revival_conditions = VAL$revival_conditions,

  alpha_vector_ref = "stage_artifacts/WT-D20260822_003/alpha_scores_ref.json",
  alpha_discovery_count = 0,
  handoff = paste0("Risk/Optimizer 진행 대상 아님 — screening tier 라우트 발급 라운드. ",
                   "소비는 distribution_target_queue 원장 경유."),
  emitted_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))

## ── Step 1: alpha_package.json write ─────────────────────────────────────────
write_json(pkg, file.path(MBX, "alpha_package.json"), auto_unbox = TRUE, pretty = TRUE,
           digits = NA, na = "null", null = "null")
cat("[ok] alpha_package.json\n")

## ── Step 2: governance_log — wt_type 재분류 권고 ─────────────────────────────
gl_path <- file.path(MBX, "governance_log.json")
gl <- if (file.exists(gl_path)) fromJSON(gl_path, simplifyVector = FALSE) else list()
entry <- list(
  ts = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  by = "alpha-research",
  type = "reclassify_proposal",
  from = "discovery", to = "re_adjudication (or sizing_only-equivalent)",
  measured_alpha_inheritance_cor = 1.0,
  evidence = "score 패널이 Lane B 와 **동일 파일**(sha256 대조) — 신규 factor 0건, alpha_discovery_count 0",
  rule = "alpha_research_init.md <role_cards_by_wt_type> Reverse case — wt_type=discovery 인데 inheritance_cor > 0.95 이면 재분류 권고 후 사용자 confirm",
  consequence = "alpha_discovery_certificate 미발급이 **정상**. PG1 admission 자격 주장 없음.",
  status = "PROPOSED — 도훈/Q-Lead confirm 대기")
gl$np2_reclassify_proposal <- entry
write_json(gl, gl_path, auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null")
cat("[ok] governance_log reclassify_proposal\n")

## ── Step 3: lineage (★ package write 이후, L-194) ────────────────────────────
lu <- file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R")
if (file.exists(lu)) {
  source(lu)
  ok <- try(record_package_lineage(
    task_id = "WT-D20260822_003",
    package_type = "alpha_package",
    method_selected = "distribution_target_screen re-adjudication (rank 2-axis control, disjoint windows @2015-12-01)",
    input_file_paths = c(PANEL,
                         file.path(SRC, "fwd.rds"),
                         file.path(OUT, "PREREG_NP2.json"),
                         file.path(OUT, "PREREG_NP2_transform_decision.json"))), silent = TRUE)
  cat("[lineage]", if (inherits(ok, "try-error")) paste("FAILED:", conditionMessage(attr(ok, "condition"))) else "recorded", "\n")
} else cat("[lineage] lineage_utils.R 부재 — 기록 불가(사실 그대로 보고)\n")
cat("[done]\n")
