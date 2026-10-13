#!/usr/bin/env Rscript
#==============================================================================
# program_paper_sync.R — 논문 라우팅 산출(v5) → 리서치 프로그램 재료 큐 (v10.01 · 2026-10-13)
#
# 왜: v10.01 에서 논문은 리서치 단위가 아니라 세 엔진 프로그램의 재료다. 트리아지(LLM · paper_router_prompt.md v5)는
#   엔진만 분류하고 등록부는 쓰지 않는다 — 쓰기는 이 결정론 단계가 한다(LLM 은 제안, 기록은 R).
# 무엇을: stage_artifacts/paper_recharge/alpha_search_route_*.json 중 schema paper_router_v5 의 papers 에서
#   engine ∈ {return, defense, construction} ∧ verdict ∈ {testable, data_pipeline_required} 인 논문을
#   P1_RETURN / P2_DEFENSE / P3_CONSTRUCTION 큐에 넣는다. 멱등 — 큐 · 소비 기록에 있는 key 는 다시 넣지 않는다.
#   v4 이하 산출(엔진 필드 없음)은 건너뛴다(재분류는 별도 백필 단계).
# 사용: Rscript 02_Infrastructure/programs/program_paper_sync.R [--dry-run]
# 검사: 08_Tests/programs/test_program_paper_sync.R
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })

PPS_ENGINE_PROGRAM <- c(return = "P1_RETURN", defense = "P2_DEFENSE", construction = "P3_CONSTRUCTION")
PPS_VERDICTS <- c("testable", "data_pipeline_required")

.pps_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

#' 라우팅 산출 파일들 → 큐에 넣을 항목 목록(순수 함수 — 쓰기 없음)
pps_collect <- function(route_files) {
  out <- list()
  for (f in route_files) {
    d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(d) || !identical(d$schema_version, "paper_router_v5")) next
    for (p in .pps_or(d$papers, list())) {
      eng <- .pps_or(p$engine, "")
      if (!(eng %in% names(PPS_ENGINE_PROGRAM))) next
      if (!(.pps_or(p$verdict, "") %in% PPS_VERDICTS)) next
      k <- .pps_or(p$paper_key, "")
      if (!nzchar(k)) next
      out[[length(out) + 1L]] <- list(program = unname(PPS_ENGINE_PROGRAM[eng]), item = list(
        key = k, kind = "paper", title = .pps_or(p$title, ""), id = .pps_or(p$id, ""),
        source = .pps_or(p$source, ""), engine = eng, engine_secondary = .pps_or(p$engine_secondary, list()),
        verdict = p$verdict, crisis_evidence = .pps_or(p$crisis_evidence, "n/a"),
        reason = substr(.pps_or(p$reason, ""), 1L, 400L), route_date = .pps_or(d$date, ""),
        route_file = basename(f)))
    }
  }
  out
}

pps_run <- function(root = NULL, dry_run = FALSE, registry_path = NULL) {
  rt <- .pps_or(root, Sys.getenv("QM_ROOT", getwd()))
  if (!exists("pr_enqueue_many", mode = "function"))
    source(file.path(rt, "02_Infrastructure/programs/program_registry.R"))
  files <- sort(Sys.glob(file.path(rt, "stage_artifacts/paper_recharge/alpha_search_route_*.json")))
  items <- pps_collect(files)
  if (dry_run) {
    cat(sprintf("[program_paper_sync] dry-run: 후보 %d건(파일 %d개) — 쓰지 않음\n", length(items), length(files)))
    return(invisible(items))
  }
  added <- pr_enqueue_many(items, root = rt, path = registry_path)
  cat(sprintf("[program_paper_sync] 후보 %d건 · 새로 넣음 %s\n", length(items),
              if (length(added)) paste(sprintf("%s %d", names(added), added), collapse = " · ") else "0"))
  invisible(added)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  ## --root <dir>: ~/.Renviron 의 QM_ROOT 가 호출자 환경변수를 덮으므로 루트는 인자로 명시한다(10-13 재발)
  ri <- match("--root", args); rt <- if (!is.na(ri) && length(args) > ri) args[ri + 1L] else NULL
  pps_run(root = rt, dry_run = "--dry-run" %in% args)
}
