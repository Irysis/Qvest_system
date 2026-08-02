# emit_package.R — WT-D20260803_004 alpha_package.json 발행 + lineage (L-194 순서 준수)
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
MB <- "qepm/mailbox/worktask/WT-D20260803_004"
vec <- fromJSON(file.path(Sys.getenv("WT004_SCRATCH"), "vec.json"))

pkg <- list(
  task_id = "WT-D20260803_004",
  strategy_id = "WT_D20260803_004_FQ121_GATE_OOS",
  as_of_date = "2026-08-03",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  pit = list(sig_date = "2026-06-30", decision_ts = "2026-08-03"),
  hypothesis = list(
    statement = "조합 자격 게이트('성분별 canonical PORT_t>0')를 IS 구간(2001-12~2014-02)에만 걸고 OOS(2014-03~2026-06)에서 조합을 확인하면, WT-021의 in-sample 편향(POS2 회복 126%) 없이 '조합은 전이-양성끼리만' 설계 원칙이 성립하는가. primary = 방법론 검증(성과 개선 아님). 사전등록 stage_artifacts/WT_D20260803_004/preregistration.json (측정 전 고정).",
    mechanism = list(
      agent = "정적 IS 게이트에 의존하는 조합 설계자(스크리너) — 12년 IS canonical PORT_t 부호로 성분의 slot 배분 자격을 판정하는 배합 주체",
      friction = "top-25 long-only 구현은 합성 분포의 극단 우측 꼬리만 소비 + KR 공매도 제약으로 음-전이 성분을 상쇄 포지션으로 중화 불가 → 성분 자격 오판이 즉시 slot 잠식 손실로 전이(WT-021 실측 기전)",
      path = "IS 양-전이 성분만 EW 합성 → OOS에서 음-전이 성분의 slot 잠식이 제거 → 게이트 조합이 무게이트(ALL5)·단일 최강 대비 우위 — 가 가설 경로. 실측: 성분 자격 자체가 비정상(IS→OOS 부호 안정 2/5)이라 경로 미성립"
    ),
    falsification = list(
      list(observation = "IS 통과 성분의 OOS 전이 부호 유지율이 우연 수준 이하면 '정적 게이트' 기전 자체가 기각 — 실측: IS 통과 4성분 중 3개(V01_SECREL/Q01_EB/V06_EB) OOS 음전(유지 1/4). 기전 기각 확정",
           fields = c("V01_BM", "M01_Mom_12_1", "Q01_GPA", "V06_fDY")),
      list(observation = "게이트가 유효하면 OOS에서 A1(게이트)−A3(무게이트) paired 격차가 양(+)이어야 — 실측 +3.21%/yr(t +1.26): 방향 성립·유의 미달",
           fields = c("M01_Mom_12_1", "D03_RealVol"))
    ),
    regime_scope = list(
      holds_in = c("neutral", "recovery"),
      weakens_or_reverses_in = c("mega_cap_concentration", "crisis"),
      boundary_rationale = "cap-w 벤치 집중 국면(post-2014 KR mega-cap)에서는 무작위 EW 25픽조차 벤치에 짐(placebo 중심 −1.69) — 게이트 판별력이 벤치-구성 벽에 흡수됨. dual-basis(EW-uni t +1.67 vs cap-w −0.03) 실측과 정합"
    )
  ),
  factors = list(
    list(factor_id = "A1_GATE_IS_COMPOSITE",
         role = "피검체 — IS 게이트 통과 4성분(V01_SECREL+M01_PATHQ+Q01_EB+V06_EB) 재-z EW",
         restatement_exposure = 2L,
         ast = list(op = "CS_ZSCORE", args = list(list(
           leaf = "STORED_SCORE", field = "wt009_tuned_panel_gated4_ew_mean_z",
           embedded_data_through = "2026-06-30",
           provenance = list(
             store_build_hash = "stage_artifacts/WT_D20260802_009/{base,tuned}_panel.parquet (WT-021 동일 vintage)",
             generator_code_path = "stage_artifacts/WT_D20260802_009/run_wt009_tuned.R (walk-forward)",
             production_parity_verified = "N/A — 내부 arm 대조 라운드(book-marginal ΔIR 주장 없음). fast-path vs canonical parity 0.00e+00 별도 검증")))),
    list(factor_id = "A4_SINGLE_IS",
         role = "대조군 — IS argmax 단일(V01_SECREL)",
         restatement_exposure = 0L,
         ast = list(op = "CS_ZSCORE", args = list(list(
           leaf = "STORED_SCORE", field = "wt009_panel_V01_SECREL",
           embedded_data_through = "2026-06-30",
           provenance = list(
             store_build_hash = "stage_artifacts/WT_D20260802_009/base_panel.parquet",
             generator_code_path = "stage_artifacts/WT_D20260802_009 (WT-009 walk-forward)",
             production_parity_verified = "N/A — 동일"))))
  ),
  combination_rule = "z_score_aligned_equal_weight",
  combination_note = "게이트 통과 성분 재-z EW (WT-021 build_zl 동일 규칙: 월 재-z + 월 커버리지>=100 + 성분수>=2)",
  verdict = "designed",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "stage_artifacts/WT_D20260802_009/{base,tuned}_panel.parquet",
           availability_rule = "walk-forward 산출 패널 재소비(WT-009 lag1 스트레스 실증 승계). 저장 파생 패널 provenance 명시(§4-1). embedded_data_through 2026-06-30 <= t_d-1. 본 라운드 추가 방어 = IS/OOS 위반 주입(누출 게이트 +0.74 t 이득 실증 = 분리 실질 구속)",
           restatement_prone = TRUE),
      list(leaf = "A1_rawdata:Ret/Close (build_monthly_forward_returns)",
           availability_rule = "t-1 close, 신호월 t → 홀딩월 t+1 forward return 컨벤션 (WT-021 동일)",
           restatement_prone = FALSE)
    ),
    verdict = "clean"
  ),
  alpha_vector = vec$alpha,
  alpha_vector_note = "2026-06-30 신호월 A1_GATE_IS 합성 z 상위 40 (스케일 0.002·z). ★자본 후보 아님 — OOS canonical PORT_t −0.03, 방법론 검증 라운드 산출물. Optimizer 소비 금지 권고",
  confidence_vector = vec$conf,
  confidence_vector_note = "일괄 0.25 — 성분 전이 부호 비정상성(안정 2/5) 실측을 반영한 low-confidence 정직 라벨",
  signal_matrix_ref = "stage_artifacts/WT_D20260803_004/alpha_scores.parquet",
  factor_specs = list(
    list(factor_family = "composite_gated", proxy = "IS-gated 4-factor EW (V01_SECREL+M01_PATHQ+Q01_EB+V06_EB)",
         formula = "mean of within-month re-z of component scores, coverage>=100/month, nf>=2",
         lag_rule = "WT-009 패널 walk-forward 승계 (월말 신호 → 익월 수익)",
         winsorization = "패널 생성단 승계", neutralization = "none (성분 자체가 튜닝 패널)",
         economic_rationale = "WT-021 확정 기전(음-전이 성분의 slot 잠식) 제거를 IS-only 정보로 기계화 — 전이-양성 성분만 slot 배분권 부여",
         weight_theta = 0.25, references = c("WT-D20260802_021 (FQ-116)", "Harvey-Liu-Zhu 2016", "McLean-Pontiff 2016"))
  ),
  diagnostics = list(
    canonical_port_t_nw_lag3 = -0.029,
    canonical_port_t_pvalue = NA,
    canonical_n_months = 148L,
    canonical_note = "A1_GATE_IS OOS(2014-03~2026-06) canonical 실측 (metric_type=canonical_screen). 전 arm: A2_POS2 +0.44 / A3_ALL5 −0.58 / A4_SINGLE_IS −0.39. 성분 IS/OOS 표·판별·강건성 전체 = stage_artifacts/WT_D20260803_004/alpha_validation.json",
    metric_type = "canonical_screen",
    prereg_decision_a = "NOT_ESTABLISHED — t(A1−A3)=+1.26 < 2.0 (방향 양성)",
    prereg_decision_b = "NOT_ESTABLISHED — t(A1−A4)=+0.69, 양 arm OOS 알파 0 근방 (조합 존재 이유 성립 실패)",
    component_sign_stability = "2/5 (IS 12년으로도 OOS 전이 부호 3/5 오판)",
    injection_fired = TRUE,
    turnover_annual = 5.39,
    subperiod_stability = NA,
    n_iterations = 1L
  ),
  selection_objective = "canonical_port_t",
  alpha_discovery_count = 0L,
  method_shopping_log = list(alpha_agent = list(candidates_tried = 1L, method_log = list(
    list(name = "FQ121_IS_OOS_GATE_VALIDATION", canonical_port_t = -0.029, selected = TRUE,
         note = "단일 사전등록 검증 라운드 — 분할 1개 고정·arm 4종 고정·argmax 없음. 위반 주입(누출 게이트) 별도 2 arm은 게이트 실효 검증 전용")))),
  challenge_flags = list(
    list(id = "CF-01", severity = "MEDIUM", flag = "OOS는 기열람 표본 위 경계 — 제거한 편향은 '성분 선별의 IS-only 재현' 하나. A2_POS2는 full-sample 지식 arm이라 판정 근거 배제 (challenge C1)"),
    list(id = "CF-02", severity = "HIGH", flag = "지배 발견: 성분 자격(tail-전이 부호) 시계열 비정상 — IS 최강 V01(+2.63)이 OOS 음전(−0.39), 부호 안정 2/5. WT-021 P1 정적 게이트 원칙은 기계화 불가 실측 (문턱 상향으로 해결 안 됨, challenge C3 REBUTTAL)"),
    list(id = "CF-03", severity = "MEDIUM", flag = "placebo 중심 −1.69 ≠ 0 — cap-w 벤치-구성 아티팩트(무작위 EW 픽이 벤치에 지는 post-2014). 양성 증거 승격 금지, dual-basis 진단으로만 소비 (challenge C4)"),
    list(id = "CF-04", severity = "INFO", flag = "lag1 무붕괴이나 base≈0이라 검사력 낮음 — PIT 방어 실질은 walk-forward 패널 승계 + 위반 주입 발화 (challenge C5)"),
    list(id = "CF-05", severity = "INFO", flag = "게이트 통과 집합이 precheck 예상(3개)과 다른 4개(Q01_EB 편입) — 통과 집합 자체의 표본 민감성이 비정상성의 1차 증거")
  ),
  verdict_summary = "다팩터 조합 lane 재개 조건 미충족 — 현 config(WT-009 5팩터·cap-w·top-25)에서 닫힘(config-scoped). (a) 게이트 유효성 미확립(+1.26) / (b) 조합 존재 이유 성립 실패(+0.69, 양 arm 0 근방) / 지배 발견 = 성분 전이 부호 비정상성(안정 2/5). next_probe 3건 + 부활 조건 3건 = alpha_validation.json"
)

write_json(pkg, file.path(MB, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE,
           digits = 6, null = "null", na = "null")
cat("[emit] alpha_package.json written\n")

# Step 2: lineage (반드시 write 후 — L-194)
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260803_004",
  package_type = "alpha_package",
  method_selected = "FQ121 IS/OOS gate validation — A1_GATE_IS(V01+M01+Q01+V06 EW) vs A3_ALL5 vs A4_SINGLE_IS(V01), OOS 148m canonical",
  input_file_paths = c(
    "stage_artifacts/WT_D20260802_009/base_panel.parquet",
    "stage_artifacts/WT_D20260802_009/tuned_panel.parquet",
    "stage_artifacts/WT_D20260802_009/size_panel.parquet",
    ".cache/RAWDATA.parquet",
    "stage_artifacts/WT_D20260803_004/preregistration.json"
  )
)
cat("[emit] lineage recorded\n")

# governance_log append + status
gl_path <- file.path(MB, "governance_log.json")
gl <- fromJSON(gl_path, simplifyVector = FALSE)
gl$events <- c(gl$events, list(list(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  agent = "alpha-research",
  action = "ALPHA_DONE",
  summary = "FQ-121 IS/OOS 게이트 검증 완료: (a) 미확립 t+1.26 / (b) 성립 실패 t+0.69 (양 arm OOS 알파 0 근방). 지배 발견 = 성분 전이 부호 비정상(안정 2/5, IS 최강 V01 OOS 음전). 위반 주입 발화(누출 +0.74 t). parity 0.00e+00. Self-Adversarial 5건. 자본 주장 없음, alpha_discovery_count=0"
)))
write_json(gl, gl_path, pretty = TRUE, auto_unbox = TRUE)
st <- fromJSON(file.path(MB, "status.json"), simplifyVector = FALSE)
st$current_phase <- "ALPHA_DONE"
st$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900")
write_json(st, file.path(MB, "status.json"), pretty = TRUE, auto_unbox = TRUE)
cat("[emit] governance_log + status updated\n")
