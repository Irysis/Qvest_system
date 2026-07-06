# run_axiom_weekly.R — 주간 사이클 단일 진입 (2026-07-04 엔진 재설계 §5)
#
# ★2026-07-06 정정(도훈 confirm — 중복 통합): 이 스크립트는 MANUAL/DEBUG 전용이며 자동 트리거 없음.
#   (구 헤더가 "Cleaner가 이 스크립트를 호출한다"고 적었으나 거짓 — Cleaner step 3.5는
#    engine-core 스크립트(harvester/cluster/promote)를 *직접* 호출한다. bootstrap도 이제
#    Cleaner(weekly_cleaner_sweep.R)를 실행하지 이 스크립트를 호출하지 않는다.)
#   정규 주간경로 = weekly_cleaner_sweep.R step[3.5] (bootstrap 7일게이트 + Qvest_WeeklyCleaner Sat).
#   이 스크립트/ops/axiom_weekly.sh는 동일 파이프라인의 수동 재현 — 디버그·수동 재실행 시만.
#
# harvester → cluster_extractor(+distilled) → promote 전 후보 순회 → 진단 JSON.
#
# 산출: .cache/axiom_weekly_diag.json
#   { n_candidates, n_promoted, n_failed, failing_axis_histogram,
#     near_miss: [1축만 미달 후보 — /cleaner 정제 우선순위],
#     confirm_flags: [주간 리포트 도훈 confirm 대상] }
#
# 불변: 5축 hurdle 수치·INV-1~7·AX-008 2/3 전부 그대로 (promote.R 소관 — 본 스크립트는
#   오케스트레이션 + 진단만). mode-local 자동 승격은 documented까지 (INV-2).
#
# Usage: Rscript 02_Infrastructure/axiom/run_axiom_weekly.R [--no-harvest]

suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

.aw_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot", getwd())
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}

.aw_py <- function() {
  cands <- c(Sys.getenv("QVEST_PY", ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe",
             "C:/Users/99922/AppData/Local/Programs/Python/Python312/python.exe")
  for (p in cands) if (nzchar(p) && file.exists(p)) return(p)
  stop("python interpreter not found (bare python 금지 — QVEST_PY 또는 venv)")
}

run_axiom_weekly <- function(root = .aw_root(), harvest = TRUE, verbose = TRUE) {
  ax_dir <- file.path(root, "02_Infrastructure", "axiom")
  py <- .aw_py()
  Sys.setenv(CLAUDE_PROJECT_DIR = root, PYTHONUTF8 = "1")

  step_log <- list()
  .step <- function(name, expr) {
    r <- tryCatch({ expr; "OK" }, error = function(e) sprintf("FAIL: %s", conditionMessage(e)))
    step_log[[name]] <<- r
    if (verbose) cat(sprintf("[axiom_weekly] step %-18s %s\n", name, r))
    r
  }

  # [1] harvest (Ledger → corpus)
  if (harvest) .step("harvester", {
    rc <- system2(py, c(file.path(ax_dir, "lcode_harvester.py"), "--project-dir", root),
                  stdout = TRUE, stderr = TRUE)
    if (!is.null(attr(rc, "status")) && attr(rc, "status") != 0) stop(paste(tail(rc, 2), collapse = " "))
  })

  # [2] cluster + distilled (corpus → CAND + DIST 초안 + distilled_knowledge.json)
  .step("cluster_distill", {
    rc <- system2(py, c(file.path(ax_dir, "cluster_extractor.py"), "--project-dir", root),
                  stdout = TRUE, stderr = TRUE)
    if (!is.null(attr(rc, "status")) && attr(rc, "status") != 0) stop(paste(tail(rc, 2), collapse = " "))
  })

  # [3] promote 전 후보 순회 (fail-soft — 후보 1건 crash가 사이클을 죽이지 않게)
  Sys.setenv(PROMOTE_SOURCED = "1")
  source(file.path(ax_dir, "promote.R"), local = TRUE)
  cand_dir <- file.path(root, "qepm", "memory", "axioms", "candidates")
  cands <- list.files(cand_dir, pattern = "^CAND_.*\\.json$", full.names = TRUE)
  results <- list(); axis_fail_hist <- c(); near_miss <- list(); confirm_flags <- list()
  n_promoted <- 0L; n_failed <- 0L; n_crash <- 0L
  for (cf in cands) {
    rep <- tryCatch(promote_to_axiom(cf), error = function(e) {
      cat(sprintf("[axiom_weekly][CRASH] %s: %s\n", basename(cf), conditionMessage(e))); NULL })
    if (is.null(rep)) { n_crash <- n_crash + 1L; next }
    failing <- names(rep$hurdle_pass)[!unlist(rep$hurdle_pass)]
    if (isTRUE(rep$passed)) n_promoted <- n_promoted + 1L else n_failed <- n_failed + 1L
    for (fx in failing) axis_fail_hist[fx] <- (axis_fail_hist[fx] %||% 0) + 1
    if (!isTRUE(rep$passed) && length(failing) == 1L)
      near_miss[[length(near_miss) + 1L]] <- list(
        candidate_id = rep$candidate_id, failing_axis = failing,
        weighted_score = rep$weighted_score, mode = rep$mode, polarity = rep$polarity)
    # conditional direction_consistency 재정의(2026-07-04) 사용 후보 → 도훈 confirm 플래그
    dc_def <- rep$axes$independence$direction_consistency_definition %||% ""
    if (grepl("within_condition_axis", dc_def))
      confirm_flags[[length(confirm_flags) + 1L]] <- list(
        candidate_id = rep$candidate_id, item = "conditional direction_consistency 재정의 적용",
        detail = dc_def)
    results[[length(results) + 1L]] <- list(candidate_id = rep$candidate_id,
      passed = rep$passed, weighted = rep$weighted_score, failing = failing)
  }

  # [4] distilled 인덱스/truths 블록 최신화 (정제분 반영)
  .step("distilled_sync", {
    source(file.path(ax_dir, "distilled.R"), local = TRUE)
    rebuild_distilled_index(root, verbose = FALSE)
    update_strategic_truths_distilled_block(root)
  })

  diag <- list(
    schema_version = "axiom_weekly_diag_v1",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    steps = step_log,
    axiom_candidates = list(
      n_pending = length(cands), n_promoted = n_promoted, n_failed = n_failed,
      n_crash = n_crash,
      failing_axis_histogram = as.list(axis_fail_hist),
      near_miss = near_miss),
    confirm_flags = confirm_flags,
    note = paste("Cleaner step 3.5 소비용. near_miss = 1축만 미달 — /cleaner 세션 정제",
                 "(statement_refined / falsification 구조체 보강) 우선순위.",
                 "승격 문턱·INV-1~7 불변 — 이 파일은 진단 전용."))
  dp <- file.path(root, ".cache", "axiom_weekly_diag.json")
  dir.create(dirname(dp), showWarnings = FALSE, recursive = TRUE)
  write_json(diag, dp, pretty = TRUE, auto_unbox = TRUE, null = "null")
  if (verbose) {
    cat(sprintf("[axiom_weekly] done — pending=%d promoted=%d failed=%d crash=%d near_miss=%d → %s\n",
                length(cands), n_promoted, n_failed, n_crash, length(near_miss), dp))
    if (length(axis_fail_hist))
      cat("  failing_axis_histogram:", paste(sprintf("%s=%d", names(axis_fail_hist), axis_fail_hist), collapse = " "), "\n")
  }
  invisible(diag)
}

if (sys.nframe() == 0 && !interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  run_axiom_weekly(harvest = !("--no-harvest" %in% args))
}
