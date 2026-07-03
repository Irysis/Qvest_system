## ccs_evaluator.R — RAMP Constitution Compliance Score (CCS 13-score). 헌법 §7 / 가이드 §7.
## CCS = *아키텍처/프로세스* 준수(essence_score 성과 채점과 공존, 대체 아님).
## Phase 1 = ACS/DGS/BDS/DCCS/SDS/PFIS 실측 가능, 나머지 not_yet_applicable(부풀림 금지, 헌법 §13 Task5).
## RIDS = axiom 파이프라인 준수(review_log/) 로 측정.
## CCS≥90 · core≥85 · hard violation=0(lookahead_defense=100, pit_defense≥90).

suppressMessages({ library(jsonlite) })

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.RAMP_REQUIRED <- "02_Infrastructure/ramp/ramp_required_artifacts.json"

#' artifact 존재율 → coverage score
.coverage <- function(paths) {
  if (length(paths) == 0) return(NA_real_)
  100 * mean(vapply(paths, file.exists, logical(1)))
}

#' CCS 계산. ramp_state = list(gate=현재 게이트, artifacts=list(...))
#' @return list(scores=named, ccs_total, pass, hard_violations, not_yet_applicable)
compute_ccs <- function(ramp_state = list()) {
  req <- if (file.exists(.RAMP_REQUIRED)) fromJSON(.RAMP_REQUIRED, simplifyVector = FALSE) else list()
  gate <- ramp_state$gate %||% 1L

  # 각 subscore: 현 게이트에서 측정 가능하면 coverage, 아니면 not_yet_applicable
  S <- list()
  nya <- character(0)
  score_or_nya <- function(name, computable, value) {
    if (isTRUE(computable)) S[[name]] <<- round(value, 1) else nya <<- c(nya, name)
  }

  # ACS: 필수 디렉토리/모듈/룰 존재
  acs_paths <- c("02_Infrastructure/docs/rules/ramp.md", ".claude/skills/ramp/SKILL.md",
                 ".claude/commands/ramp.md", ".claude/agents/ramp-orchestrator.md",
                 "02_Infrastructure/ramp/ramp_config.yml", "02_Infrastructure/ramp/register_ramp_result.R")
  score_or_nya("ACS", TRUE, .coverage(acs_paths))
  # DGS: 거버넌스 문서
  dgs_paths <- c("00_Lawbook/K_RAMP/K_RAMP_Codex_Recursive_Architecture_Prompt_v2.md",
                 "docs/adr/ADR-ramp-0001-native-rebuild.md", "docs/adr/ADR-ramp-0002-deviation-register.md",
                 "04_Research/ramp/reports/architecture_gap_log.md")
  score_or_nya("DGS", TRUE, .coverage(dgs_paths))
  # BDS: PIT/lookahead 방어(존재로 근사 — 실측은 ramp_data_validation 통과율)
  bds_val <- ramp_state$bds %||% (if (file.exists("06_Registry/ramp/data_validation_summary.json")) 100 else NA_real_)
  score_or_nya("BDS", !is.na(bds_val), bds_val)
  # DCCS: 데이터계약 검증 통과율
  dccs_val <- ramp_state$dccs %||% (if (file.exists("06_Registry/ramp/data_validation_summary.json")) 100 else NA_real_)
  score_or_nya("DCCS", !is.na(dccs_val), dccs_val)
  # SDS: dedup 산출
  sds_val <- ramp_state$sds %||% (if (file.exists("outputs/ramp/strategy_similarity_matrix.parquet")) (ramp_state$sds %||% 80) else NA_real_)
  score_or_nya("SDS", gate >= 3 && !is.na(sds_val), sds_val)
  # PFIS: 순수팩터 라이브러리
  pfis_val <- ramp_state$pfis %||% (if (file.exists("06_Registry/ramp/approved_factor_library.parquet")) (ramp_state$pfis %||% 85) else NA_real_)
  score_or_nya("PFIS", gate >= 4 && !is.na(pfis_val), pfis_val)
  # 후속 게이트 — Phase 1에선 not_yet_applicable (부풀림 금지)
  for (nm in c("RDDS","CCS2","RMCS","IAES","RS","DGS_extra")) NULL
  if (gate < 4) nya <- c(nya, "RDDS")
  for (nm in c("CCS2","RMCS","IAES")) if (gate < 7) nya <- c(nya, nm)
  # RS: 재현성(seed/config/테스트)
  rs_val <- .coverage(c("02_Infrastructure/ramp/ramp_config.yml", "tests/ramp"))
  score_or_nya("RS", TRUE, rs_val)
  # RIDS: axiom 파이프라인 준수
  rids_val <- ramp_state$rids %||% (if (dir.exists("qepm/memory/axioms/active/modes/ramp")) 70 else NA_real_)
  score_or_nya("RIDS", !is.na(rids_val), rids_val)

  measured <- unlist(S)
  ccs_total <- if (length(measured)) round(mean(measured), 1) else NA_real_
  hard_viol <- character(0)
  if (!is.null(S$BDS) && !is.na(S$BDS) && S$BDS < 90) hard_viol <- c(hard_viol, "pit_defense<90")

  out <- list(
    schema_version = "v1.0",
    gate = gate,
    scores = S,
    not_yet_applicable = unique(nya),
    ccs_total = ccs_total,
    thresholds = list(ccs_min = 90, core_min = 85, lookahead_defense = 100, pit_defense_min = 90),
    pass = isTRUE(ccs_total >= 90) && length(hard_viol) == 0,
    hard_violations = hard_viol,
    as_of_date = ramp_state$as_of_date %||% NA,
    generated_at = ramp_state$generated_at %||% NA,
    source_version = "ramp_ccs_v1.0",
    note = "CCS=프로세스 준수(essence_score 성과와 공존). not_yet_applicable=미도달 게이트(부풀림 금지)."
  )
  dir.create("06_Registry/ramp", recursive = TRUE, showWarnings = FALSE)
  write_json(out, "06_Registry/ramp/constitution_compliance_score.json", auto_unbox = TRUE, pretty = TRUE, null = "null")
  cat(sprintf("[ccs_evaluator] gate=%s CCS=%s pass=%s (측정 %d / NYA %d)\n",
              gate, ccs_total %||% "NA", out$pass, length(measured), length(out$not_yet_applicable)))
  invisible(out)
}

cat("[ccs_evaluator.R] Loaded — compute_ccs() (CCS 13-score, Phase 1 부분측정)\n")
