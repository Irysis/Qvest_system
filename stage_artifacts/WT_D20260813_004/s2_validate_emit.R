# WT-D20260813_004 — s2: alpha_package schema 검증 + alpha_validation.json 발행 + lineage 기록
# ★lineage 순서 계약(L-194): alpha_package.json write -> record_package_lineage (역순 금지).
#   본 스크립트는 패키지가 이미 기록된 뒤 실행된다.
suppressMessages({library(jsonlite); library(data.table)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
WT   <- "WT-D20260813_004"
MB   <- file.path(ROOT, "qepm/mailbox/worktask", WT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260813_004")
PKG  <- file.path(MB, "alpha_package.json")

pkg <- fromJSON(PKG, simplifyVector = FALSE)
iv  <- fromJSON(file.path(OUT, "inherit_verify.json"), simplifyVector = FALSE)
V   <- list()

## ── 1. schema 검증 ──────────────────────────────────────────────────────────
schema_ok <- NA; schema_msg <- "jsonvalidate 미설치 — 수기 required 검사로 대체"
if (requireNamespace("jsonvalidate", quietly = TRUE)) {
  s <- fromJSON("02_Infrastructure/worktask/schema.json", simplifyVector = FALSE)
  s$`$ref` <- NULL
  sub <- list(`$schema` = s$`$schema`, definitions = s$definitions,
              `$ref` = "#/definitions/alpha_package")
  res <- try(jsonvalidate::json_validate(toJSON(pkg, auto_unbox = TRUE, null = "null"),
                                         toJSON(sub, auto_unbox = TRUE, null = "null"),
                                         engine = "ajv", verbose = TRUE), silent = TRUE)
  if (!inherits(res, "try-error")) {
    schema_ok <- as.logical(res)
    schema_msg <- if (isTRUE(schema_ok)) "PASS (ajv, #/definitions/alpha_package)" else
      paste(utils::capture.output(print(attr(res, "errors"))), collapse = " | ")
  } else schema_msg <- paste("jsonvalidate 실행 실패:", as.character(res))
}
# 수기 required 검사 (스키마 검증기 유무와 무관하게 항상 수행 — 이중 확인)
req_top  <- c("task_id","as_of_date","forecast_horizon","alpha_vector","factor_specs","diagnostics")
req_ast  <- c("hypothesis","verdict","pit")                       # spec_version=ast_v1.1 conditional
req_des  <- c("factors","combination_rule","self_pit_check")      # verdict=designed conditional
req_diag <- c("rank_ic","alpha_inheritance_cor","canonical_port_t_nw_lag3")
miss <- c(setdiff(req_top, names(pkg)), setdiff(req_ast, names(pkg)), setdiff(req_des, names(pkg)),
          paste0("diagnostics.", setdiff(req_diag, names(pkg$diagnostics))))
miss <- miss[!grepl("^diagnostics\\.$", miss)]
V$schema_check <- list(
  validator = schema_msg, validator_pass = schema_ok,
  manual_required_missing = if (length(miss)) miss else list(),
  manual_required_pass = length(miss) == 0,
  conditional_branches_applied = c("spec_version=ast_v1.1 -> hypothesis/verdict/pit",
                                   "verdict=designed -> factors/combination_rule/self_pit_check"),
  mechanism_3fields = all(c("agent","friction","path") %in% names(pkg$hypothesis$mechanism)),
  falsification_n = length(pkg$hypothesis$falsification),
  regime_scope_nonempty = length(pkg$hypothesis$regime_scope$holds_in) >= 1 &&
                          length(pkg$hypothesis$regime_scope$weakens_or_reverses_in) >= 1
)

## ── 2. 승계·인터페이스 실측 승계 (재계산 아님 — s1 산출 인용) ───────────────
V$inheritance <- iv$inheritance_parity
V$axis        <- iv$axis
V$missing     <- iv$missing
V$join_003_002<- iv$join_003_002
V$pit_lag     <- iv$pit_lag
V$consumer_join <- iv$consumer_join
V$emitted     <- iv$emitted

## ── 2b. PIT 근거 정정 (s3/s4 위반 주입 결과 반영 — 초판 주장 철회) ──────────
inj <- fromJSON(file.path(OUT, "pit_violation_injection.json"), simplifyVector = FALSE)
pwr <- fromJSON(file.path(OUT, "detector_power.json"), simplifyVector = FALSE)
V$pit_lag$direction_test_status <- "RETRACTED_NO_POWER"
V$pit_lag$retraction_note <- paste0(
  "초판은 pit_direction_test PASS 를 PIT 근거로 실었다. 위반 주입 결과 오염 판도 PASS 해 판별력 0. ",
  "대안 통계량 2종도 실패. PIT 근거를 구성-수준 재현 + assert_overlay_pit 으로 교체했다.")
V$pit_evidence <- list(
  accepted = list(
    construction_reproduction = list(
      claim = "승계 패널이 strict 컷오프(Date < hold_start)로 구성됐음을 원천 재구축으로 재현",
      max_abs_diff = 0, n = 366, source = "inherit_verify.json::inheritance_parity.level_parity_sigma_hat"),
    assert_overlay_pit = "WT-003 s1_prereg.R:44 HARD 통과 (승계)"
  ),
  rejected = list(
    statistical_timing_diagnostics = list(
      reason = "위반 주입에 발화하지 않음 — 판별력 0",
      violation_injection = inj$arms, detector_verdict = inj$detector_verdict,
      alternatives_tested = pwr$statistics)
  ),
  residual_risk = "구성 재현은 오늘 시점 원장 기준 — 향후 restatement 는 배제하지 않음(pin 의무로 덮음)."
)

## ── 3. 라운드 라벨 (정직 라벨 의무) ─────────────────────────────────────────
V$round_labels <- list(
  metric_type_of_this_artifact = "interface_verification",
  performance_measured = FALSE,
  covariance_estimated = FALSE,
  weights_proposed = FALSE,
  new_factor_sourced = FALSE,
  alpha_discovery_count = 0,
  alpha_inheritance_cor = 1,
  capital_claim = FALSE,
  note = "본 문서의 어떤 수치도 성과(SR/alpha/PORT_t) 통계량이 아니다. 상관 계열 2건(pit_lag, consumer_join)은 각각 PIT 방향 진단과 조인 축 식별용이며 metric_type 을 명시했다."
)

## ── 4. 게이트 관문 요약 (본 라운드에 적용되는 것만) ─────────────────────────
V$gates <- list(
  applicable = list(
    ast_spec_gate = "PASS — 최초 write 시 falsification 리프가 field_dictionary 밖(group_id:field 형)이라 block 되어 bare group_id 로 수정 후 통과. 게이트 차단 실효 실증.",
    role_objective_guard = "PASS — selection_objective 미기재(후보 선택 0건). 금지값 미사용.",
    role_boundary = "PASS — cov/weight/성과 산출 0"
  ),
  not_applicable = list(
    discovery_graduation_gate = "미적용 — graduation HARD 3종(PORT_t/oos_retention/calmar)은 forge-authoritative 값 대상. 본 라운드는 forge 미경유·성과 미산출.",
    DSR = "미적용 — selection_type=chain, 후보 선택 0건이라 sweep 성립 불가",
    rank_ic_advisory = "산출 불가 — 시장-레벨 1계열(횡단면 분산 0). 정의상 부재이지 측정 실패 아님"
  )
)

writeLines(toJSON(V, auto_unbox = TRUE, pretty = TRUE, digits = 10, na = "null"),
           file.path(OUT, "alpha_validation.json"))
cat("[emit] alpha_validation.json 기록\n")
cat(sprintf("[schema] validator=%s | manual_required_pass=%s | missing=%s\n",
            schema_msg, V$schema_check$manual_required_pass,
            paste(unlist(V$schema_check$manual_required_missing), collapse = ",")))

## ── 5. lineage (패키지 write 이후 — L-194 순서 준수) ────────────────────────
lu <- file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R")
if (file.exists(lu)) {
  source(lu)
  r <- try(record_package_lineage(
    task_id = WT,
    package_type = "alpha_package",
    method_selected = "inheritance_only: sigma_hat_market_252d (WT-D20260813_003 verbatim) + risk-research interface spec",
    input_file_paths = c("stage_artifacts/WT_D20260813_003/alpha_scores.parquet",
                         "stage_artifacts/WT_D20260813_002/alpha_scores.parquet",
                         "qepm/mailbox/worktask/WT-D20260813_004/alpha_hypothesis.json",
                         ".cache/RAWDATA.parquet")), silent = TRUE)
  cat(if (inherits(r, "try-error")) paste("[lineage] 실패:", as.character(r)) else "[lineage] record_package_lineage 완료\n")
} else cat("[lineage] lineage_utils.R 부재 — 기록 생략\n")
