#==============================================================================
# v8_readiness_gate.R — Qvest v8.0 Design Readiness Gate
#
# 핵심 질문: "현재 Qvest는 v8.0 설계를 시작해도 될 만큼 안정적인가?"
#
# 14 checks (test infrastructure, kernel, schema, legacy, residue, observability,
# release metadata, soak record).
#
# 호출:
#   source("02_Infrastructure/validation/v8_readiness_gate.R")
#   res <- run_v8_readiness_gate(strict = FALSE, write_report = FALSE, no_write = TRUE)
#
# CLI: 02_Infrastructure/tools/qvest_v8_ready
# Plan: v8.0 Design Readiness Gate prompt (도훈 명시)
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# ─────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────

resolve_tool <- function(tool_name, project_root = ".") {
  candidates <- list(
    "qvest_search" = c(
      "02_Infrastructure/tools/qvest_search",
      "02_Infrastructure/search/qvest_search"
    ),
    "qvest_wt" = c(
      "02_Infrastructure/tools/qvest_wt",
      "02_Infrastructure/observability/qvest_wt"
    ),
    "qvest_observe" = c(
      "02_Infrastructure/tools/qvest_observe",
      "02_Infrastructure/observability/qvest_observe"
    )
  )
  paths <- candidates[[tool_name]] %||% character()
  for (rel in paths) {
    abs_path <- file.path(project_root, rel)
    if (file.exists(abs_path)) {
      return(list(found = TRUE, path = abs_path, rel = rel))
    }
  }
  list(found = FALSE, path = NA_character_, rel = NA_character_,
       candidates = paths)
}

file_hash <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  tryCatch(tools::md5sum(path)[[1]], error = function(e) NA_character_)
}

run_cmd <- function(cmd, args = character(), env = character(),
                     timeout_sec = 60L, wd = NULL) {
  tmp_out <- tempfile()
  tmp_err <- tempfile()
  on.exit({
    unlink(tmp_out)
    unlink(tmp_err)
  }, add = TRUE)
  if (!is.null(wd) && dir.exists(wd)) {
    old_wd <- getwd()
    setwd(wd)
    on.exit(setwd(old_wd), add = TRUE)
    # CLAUDE_PROJECT_DIR env 추가 X — 한글 path가 env string으로 child shell에 전달 시
    # 공백 escape 깨짐 ("화면/Quant_Module_Moltbot: not found"). setwd만으로 child 동일 wd.
  }
  rc <- tryCatch(
    system2(cmd, args = args, stdout = tmp_out, stderr = tmp_err,
             env = env, timeout = timeout_sec),
    error = function(e) -1L
  )
  list(
    rc = rc,
    stdout = if (file.exists(tmp_out)) paste(readLines(tmp_out, warn = FALSE),
                                              collapse = "\n") else "",
    stderr = if (file.exists(tmp_err)) paste(readLines(tmp_err, warn = FALSE),
                                              collapse = "\n") else ""
  )
}

mk_check <- function(id, name, status, details = "", evidence_path = NULL) {
  list(
    id = id, name = name, status = status,
    details = as.character(details),
    evidence_path = evidence_path %||% NA_character_
  )
}

# ─────────────────────────────────────────────────────────────────
# 14 Checks
# ─────────────────────────────────────────────────────────────────

check_hook_dryrun <- function(project_root, no_write = FALSE) {
  results_path <- file.path(project_root, "08_Tests/hooks/results.json")
  hook_runner <- file.path(project_root, "08_Tests/hooks/run_all_hooks.sh")
  if (!file.exists(hook_runner)) {
    return(mk_check("hook_dryrun", "Hook dry-run 30/30",
                    "FAIL", "run_all_hooks.sh 부재"))
  }
  if (no_write) {
    if (file.exists(results_path)) {
      data <- tryCatch(fromJSON(results_path, simplifyVector = TRUE),
                        error = function(e) NULL)
      if (!is.null(data) && is.numeric(data$total_fail) &&
          data$total_fail == 0 && (data$total_pass %||% 0) >= 30) {
        return(mk_check("hook_dryrun", "Hook dry-run 30/30",
                        "PASS",
                        sprintf("cached results.json: %d/%d (no_write — re-run skip)",
                                data$total_pass, data$total_pass + data$total_fail),
                        results_path))
      }
    }
    return(mk_check("hook_dryrun", "Hook dry-run 30/30",
                    "WARN", "no_write — runner skip + cached results 검증 불충분"))
  }
  out <- run_cmd("bash", c(hook_runner), timeout_sec = 120L)
  if (!file.exists(results_path)) {
    return(mk_check("hook_dryrun", "Hook dry-run 30/30",
                    "FAIL", "results.json 생성 실패"))
  }
  data <- tryCatch(fromJSON(results_path, simplifyVector = TRUE),
                    error = function(e) NULL)
  if (is.null(data)) {
    return(mk_check("hook_dryrun", "Hook dry-run 30/30",
                    "FAIL", "results.json parse 실패", results_path))
  }
  total_pass <- data$total_pass %||% 0
  total_fail <- data$total_fail %||% -1
  if (total_fail == 0 && total_pass >= 30) {
    return(mk_check("hook_dryrun", "Hook dry-run 30/30",
                    "PASS", sprintf("%d pass / 0 fail", total_pass),
                    results_path))
  }
  mk_check("hook_dryrun", "Hook dry-run 30/30",
           "FAIL",
           sprintf("%d pass / %d fail (요구: fail=0, pass>=30)",
                   total_pass, total_fail),
           results_path)
}

check_e2e_kernel <- function(project_root, no_write = FALSE) {
  e2e_rel <- "08_Tests/integration/test_wt_lifecycle_e2e.R"
  e2e_abs <- file.path(project_root, e2e_rel)
  if (!file.exists(e2e_abs)) {
    return(mk_check("e2e_kernel", "E2E kernel 4 시나리오",
                    "FAIL", "test_wt_lifecycle_e2e.R 부재"))
  }
  if (no_write) {
    return(mk_check("e2e_kernel", "E2E kernel 4 시나리오",
                    "SKIP", "no_write — E2E rerun skip"))
  }
  # Production hash before
  guard_files <- c(
    "qepm/mailbox/governor/book_state.json",
    "06_Registry/strategy_registry.json",
    "06_Registry/strategy_grades.json"
  )
  before <- sapply(guard_files,
                    function(p) file_hash(file.path(project_root, p)))

  evidence <- file.path(project_root,
                         "qepm/observability/readiness/e2e_output.log")
  dir.create(dirname(evidence), recursive = TRUE, showWarnings = FALSE)
  # Relative path + setwd(project_root) — 한글 absolute path shell escape 회피
  out <- run_cmd("Rscript", c(e2e_rel), timeout_sec = 300L,
                  wd = project_root)
  writeLines(paste(c(out$stdout, "---STDERR---", out$stderr),
                    collapse = "\n"), evidence)

  # Always cleanup synthetic residue post-e2e (e2e 내부 cleanup이 한글 path
  # system2로 실패할 수 있어 책임을 명확히 — gate가 직접 cleanup_guard 호출)
  guard_rel <- "08_Tests/integration/_e2e_cleanup_guard.sh"
  guard_abs <- file.path(project_root, guard_rel)
  if (file.exists(guard_abs)) {
    run_cmd("bash", c(guard_rel, "--force"), wd = project_root)
  }

  # Production hash after
  after <- sapply(guard_files,
                   function(p) file_hash(file.path(project_root, p)))
  changed <- guard_files[!is.na(before) & before != after]
  if (length(changed) > 0) {
    return(mk_check("e2e_kernel", "E2E kernel 4 시나리오",
                    "FAIL",
                    sprintf("production guard violation: %s",
                            paste(changed, collapse = ", ")),
                    evidence))
  }

  # Synthetic residue check
  wt_root <- file.path(project_root, "qepm/mailbox/worktask")
  residue <- if (dir.exists(wt_root)) {
    list.files(wt_root, pattern = "^WT-D9999", include.dirs = TRUE)
  } else character()
  if (length(residue) > 0) {
    return(mk_check("e2e_kernel", "E2E kernel 4 시나리오",
                    "FAIL",
                    sprintf("synthetic residue %d건 (e2e cleanup guard 실패)",
                            length(residue)),
                    evidence))
  }

  # Parse pass count
  matches <- regmatches(out$stdout,
                          regexec("FINAL: (\\d+) pass / (\\d+) fail",
                                  out$stdout))
  pass_n <- 0L
  fail_n <- -1L
  if (length(matches[[1]]) >= 3) {
    pass_n <- as.integer(matches[[1]][2])
    fail_n <- as.integer(matches[[1]][3])
  }
  if (out$rc == 0 && fail_n == 0 && pass_n >= 4) {
    return(mk_check("e2e_kernel", "E2E kernel 4 시나리오",
                    "PASS",
                    sprintf("%d pass / 0 fail (e2e+production guards)", pass_n),
                    evidence))
  }
  mk_check("e2e_kernel", "E2E kernel 4 시나리오",
           "FAIL",
           sprintf("rc=%d pass=%d fail=%d", out$rc, pass_n, fail_n),
           evidence)
}

check_router_selftest <- function(project_root, no_write = FALSE) {
  router_rel <- "02_Infrastructure/hooks/qvest_hook_router.py"
  router_abs <- file.path(project_root, router_rel)
  if (!file.exists(router_abs)) {
    return(mk_check("router_selftest", "Router selftest",
                    "FAIL", "qvest_hook_router.py 부재"))
  }
  out <- run_cmd("python3", c(router_rel, "selftest"), wd = project_root)
  status <- if (out$rc == 0) "PASS" else "FAIL"
  mk_check("router_selftest", "Router selftest",
           status,
           sprintf("rc=%d", out$rc))
}

check_state_machine_selftest <- function(project_root, no_write = FALSE) {
  sm_rel <- "02_Infrastructure/worktask/state_machine.R"
  sm_abs <- file.path(project_root, sm_rel)
  if (!file.exists(sm_abs)) {
    return(mk_check("state_machine_selftest", "State machine selftest",
                    "FAIL", "state_machine.R 부재"))
  }
  # Temp R script (system2 -e shell escape 우회 — `;` parsing 이슈 회피)
  script_tmp <- tempfile(fileext = ".R")
  on.exit(unlink(script_tmp), add = TRUE)
  writeLines(c(
    sprintf("source('%s')", sm_rel),
    "ok <- qvest_state_machine_selftest()",
    "if (!isTRUE(ok)) quit(status = 1)"
  ), script_tmp)
  out <- run_cmd("Rscript", c(script_tmp), wd = project_root)
  status <- if (out$rc == 0) "PASS" else "FAIL"
  mk_check("state_machine_selftest", "State machine selftest",
           status, sprintf("rc=%d", out$rc))
}

check_cert_rules_selftest <- function(project_root, no_write = FALSE,
                                        strict = TRUE) {
  cr_rel <- "02_Infrastructure/worktask/cert_rules.R"
  cr_abs <- file.path(project_root, cr_rel)
  if (!file.exists(cr_abs)) {
    s <- if (strict) "FAIL" else "WARN"
    return(mk_check("cert_rules_selftest", "Cert rules selftest",
                    s, "cert_rules.R 부재"))
  }
  # Temp R script (system2 -e shell escape 우회)
  script_tmp <- tempfile(fileext = ".R")
  on.exit(unlink(script_tmp), add = TRUE)
  writeLines(c(
    sprintf("source('%s')", cr_rel),
    "ok <- qvest_cert_rules_selftest()",
    "if (!isTRUE(ok)) quit(status = 1)"
  ), script_tmp)
  out <- run_cmd("Rscript", c(script_tmp), wd = project_root)
  status <- if (out$rc == 0) "PASS" else if (strict) "FAIL" else "WARN"
  mk_check("cert_rules_selftest", "Cert rules selftest",
           status, sprintf("rc=%d", out$rc))
}

check_schema_active_wt <- function(project_root, no_write = FALSE) {
  router <- file.path(project_root,
                        "02_Infrastructure/hooks/qvest_hook_router.py")
  if (!file.exists(router)) {
    return(mk_check("schema_active_wt", "Active WT schema validation",
                    "FAIL", "router 부재"))
  }
  wt_root <- file.path(project_root, "qepm/mailbox/worktask")
  if (!dir.exists(wt_root)) {
    return(mk_check("schema_active_wt", "Active WT schema validation",
                    "WARN", "WT mailbox 부재"))
  }
  # Find recent 3 WT (by status.json mtime)
  status_files <- list.files(wt_root, pattern = "^status\\.json$",
                              full.names = TRUE, recursive = TRUE)
  if (length(status_files) == 0) {
    return(mk_check("schema_active_wt", "Active WT schema validation",
                    "WARN", "active WT 없음"))
  }
  mtimes <- file.info(status_files)$mtime
  recent <- status_files[order(mtimes, decreasing = TRUE)][1:min(3, length(status_files))]
  validated <- 0L
  failed <- 0L
  details <- character()
  for (sf in recent) {
    wt_dir <- dirname(sf)
    wt_id <- basename(wt_dir)
    if (grepl("^WT-D9999", wt_id)) next  # synthetic skip
    # L-314 follow-up: ARCHIVED/REJECT lifecycle WT는 schema 검증 무의미 (이미 처분 완료)
    status_data <- tryCatch(jsonlite::fromJSON(sf, simplifyVector = FALSE),
                            error = function(e) NULL)
    if (!is.null(status_data) && !is.null(status_data$current_phase)) {
      if (grepl("^ARCHIVED_|^REJECT_|_REJECT_|^REJECTED", status_data$current_phase)) next
    }
    # Try alpha_package validation if present
    alpha_pkg_abs <- file.path(wt_dir, "alpha_package.json")
    if (file.exists(alpha_pkg_abs)) {
      # Relative path from project_root (한글 absolute path 회피)
      alpha_pkg_rel <- sub(paste0(project_root, "/?"), "", alpha_pkg_abs)
      router_rel2 <- "02_Infrastructure/hooks/qvest_hook_router.py"
      out <- run_cmd("python3",
                      c(router_rel2, "validate-schema",
                        "--schema", "alpha_package",
                        "--package", alpha_pkg_rel), wd = project_root)
      if (out$rc == 0) {
        validated <- validated + 1L
      } else {
        failed <- failed + 1L
        details <- c(details, sprintf("%s: alpha INVALID", wt_id))
      }
    }
  }
  if (validated == 0 && failed == 0) {
    return(mk_check("schema_active_wt", "Active WT schema validation",
                    "WARN", "validable WT 없음 (alpha_package 부재)"))
  }
  status <- if (failed == 0) "PASS" else "FAIL"
  mk_check("schema_active_wt", "Active WT schema validation",
           status,
           sprintf("validated=%d failed=%d %s",
                   validated, failed,
                   if (length(details) > 0) paste(details, collapse = "; ") else ""))
}

check_legacy_active_hook_zero <- function(project_root, no_write = FALSE) {
  settings <- file.path(project_root, ".claude/settings.json")
  if (!file.exists(settings)) {
    return(mk_check("legacy_active_hook_zero", "Legacy hook 등록 0건",
                    "WARN", "settings.json 부재"))
  }
  content <- paste(readLines(settings, warn = FALSE), collapse = "\n")
  patterns <- c("s0_debate", "s0_verdict", "cash_sleeve_validator",
                "_archive_v55", "_archive_4_6")
  hits <- character()
  for (p in patterns) {
    if (grepl(p, content, fixed = TRUE)) {
      hits <- c(hits, p)
    }
  }
  if (length(hits) == 0) {
    return(mk_check("legacy_active_hook_zero", "Legacy hook 등록 0건",
                    "PASS", "0 hits", settings))
  }
  mk_check("legacy_active_hook_zero", "Legacy hook 등록 0건",
           "FAIL",
           sprintf("hits: %s", paste(hits, collapse = ", ")),
           settings)
}

check_synthetic_residue_zero <- function(project_root, no_write = FALSE,
                                           strict = TRUE) {
  wt_root <- file.path(project_root, "qepm/mailbox/worktask")
  if (!dir.exists(wt_root)) {
    return(mk_check("synthetic_residue_zero", "Synthetic WT residue 0건",
                    "WARN", "WT mailbox 부재"))
  }
  residue <- list.files(wt_root, pattern = "^WT-D9999",
                          full.names = FALSE, include.dirs = TRUE)
  if (length(residue) == 0) {
    return(mk_check("synthetic_residue_zero", "Synthetic WT residue 0건",
                    "PASS", "0 residue ✅"))
  }
  status <- if (strict) "FAIL" else "WARN"
  mk_check("synthetic_residue_zero", "Synthetic WT residue 0건",
           status,
           sprintf("%d residue: %s", length(residue),
                   paste(residue, collapse = ", ")))
}

check_qvest_search <- function(project_root, no_write = FALSE) {
  tool <- resolve_tool("qvest_search", project_root)
  if (!tool$found) {
    return(mk_check("qvest_search", "qvest_search CLI",
                    "FAIL",
                    sprintf("not found in candidates: %s",
                            paste(tool$candidates, collapse = ", "))))
  }
  index_path <- file.path(project_root,
                            "qepm/observability/search_index.jsonl")
  if (!file.exists(index_path)) {
    return(mk_check("qvest_search", "qvest_search CLI",
                    "WARN", "search_index.jsonl 부재 (첫 build 필요)",
                    tool$path))
  }
  out <- run_cmd("bash",
                  c(tool$rel, "governor", "--limit", "3", "--no-auto-rebuild"),
                  env = "QVEST_SEARCH_AUTO_REBUILD=0", wd = project_root)
  if (out$rc != 0) {
    return(mk_check("qvest_search", "qvest_search CLI",
                    "FAIL", sprintf("rc=%d", out$rc), tool$path))
  }
  parsed <- tryCatch(fromJSON(out$stdout, simplifyVector = TRUE),
                      error = function(e) NULL)
  cnt <- parsed$count %||% 0
  status <- if (cnt > 0) "PASS" else "WARN"
  mk_check("qvest_search", "qvest_search CLI",
           status,
           sprintf("path=%s count=%s", tool$rel, cnt),
           tool$path)
}

check_qvest_wt <- function(project_root, no_write = FALSE) {
  tool <- resolve_tool("qvest_wt", project_root)
  if (!tool$found) {
    return(mk_check("qvest_wt", "qvest_wt CLI",
                    "FAIL",
                    sprintf("not found in candidates: %s",
                            paste(tool$candidates, collapse = ", "))))
  }
  out <- run_cmd("bash", c(tool$rel, "--recent", "3"), timeout_sec = 60L, wd = project_root)
  if (out$rc != 0) {
    return(mk_check("qvest_wt", "qvest_wt CLI",
                    "FAIL", sprintf("rc=%d stderr=%s",
                                     out$rc, substr(out$stderr, 1, 100)),
                    tool$path))
  }
  if (grepl("WT-D9999", out$stdout)) {
    return(mk_check("qvest_wt", "qvest_wt CLI",
                    "FAIL", "WT-D9999 leak in --recent default output",
                    tool$path))
  }
  recent_count <- length(grep("WT-[DPSH]", strsplit(out$stdout, "\n")[[1]]))
  status <- if (recent_count > 0) "PASS" else "WARN"
  mk_check("qvest_wt", "qvest_wt CLI",
           status,
           sprintf("path=%s recent=%d (synthetic 자동 제외)",
                   tool$rel, recent_count),
           tool$path)
}

check_timeline_generation <- function(project_root, no_write = FALSE) {
  wt_timeline_rel <- "02_Infrastructure/observability/wt_timeline.R"
  wt_timeline <- file.path(project_root, wt_timeline_rel)
  if (!file.exists(wt_timeline)) {
    return(mk_check("timeline_generation", "Timeline generation",
                    "FAIL", "wt_timeline.R 부재"))
  }
  # Find recent 1 non-synthetic WT
  wt_root <- file.path(project_root, "qepm/mailbox/worktask")
  if (!dir.exists(wt_root)) {
    return(mk_check("timeline_generation", "Timeline generation",
                    "WARN", "WT mailbox 부재"))
  }
  candidates <- list.dirs(wt_root, full.names = FALSE, recursive = FALSE)
  candidates <- candidates[!grepl("^WT-D9999", candidates)]
  if (length(candidates) == 0) {
    return(mk_check("timeline_generation", "Timeline generation",
                    "WARN", "non-synthetic WT 없음"))
  }
  # Sort by status mtime
  status_paths <- file.path(wt_root, candidates, "status.json")
  exists_idx <- file.exists(status_paths)
  if (!any(exists_idx)) {
    return(mk_check("timeline_generation", "Timeline generation",
                    "WARN", "status.json 가진 WT 없음"))
  }
  candidates <- candidates[exists_idx]
  status_paths <- status_paths[exists_idx]
  mtimes <- file.info(status_paths)$mtime
  wt_id <- candidates[which.max(mtimes)]

  # Check --dry-run support
  has_dry_run <- FALSE
  script_lines <- readLines(wt_timeline, warn = FALSE)
  has_dry_run <- any(grepl("--dry-run", script_lines, fixed = TRUE))

  if (!has_dry_run && no_write) {
    return(mk_check("timeline_generation", "Timeline generation",
                    "SKIP",
                    sprintf("no --dry-run support + no_write — skip (WT=%s)", wt_id)))
  }

  # Relative path + setwd(wd) — 한글 absolute path 회피
  args <- if (has_dry_run) {
    c(wt_timeline_rel, "--wt-id", wt_id, "--dry-run")
  } else {
    c(wt_timeline_rel, "--wt-id", wt_id)
  }
  out <- run_cmd("Rscript", args, timeout_sec = 60L, wd = project_root)
  if (out$rc != 0) {
    return(mk_check("timeline_generation", "Timeline generation",
                    "FAIL", sprintf("rc=%d stderr=%s",
                                     out$rc, substr(out$stderr, 1, 100))))
  }
  status <- if (grepl("OK|saved", out$stdout)) "PASS" else "WARN"
  mk_check("timeline_generation", "Timeline generation",
           status,
           sprintf("wt_id=%s dry_run=%s", wt_id, has_dry_run))
}

check_registry_integrity <- function(project_root, no_write = FALSE) {
  required <- c(
    "06_Registry/strategy_registry.json"
  )
  optional <- c(
    "06_Registry/strategy_grades.json",
    "qepm/mailbox/governor/book_state.json"
  )
  fail_list <- character()
  warn_list <- character()
  for (rel in required) {
    p <- file.path(project_root, rel)
    if (!file.exists(p)) {
      fail_list <- c(fail_list, sprintf("%s missing", rel))
      next
    }
    parsed <- tryCatch(fromJSON(p, simplifyVector = FALSE),
                        error = function(e) NULL)
    if (is.null(parsed)) {
      fail_list <- c(fail_list, sprintf("%s parse fail", rel))
    }
  }
  for (rel in optional) {
    p <- file.path(project_root, rel)
    if (!file.exists(p)) {
      warn_list <- c(warn_list, sprintf("%s missing (optional)", rel))
      next
    }
    parsed <- tryCatch(fromJSON(p, simplifyVector = FALSE),
                        error = function(e) NULL)
    if (is.null(parsed)) {
      fail_list <- c(fail_list, sprintf("%s parse fail", rel))
    }
  }
  if (length(fail_list) > 0) {
    return(mk_check("registry_integrity", "Registry/book_state integrity",
                    "FAIL",
                    paste(c(fail_list, warn_list), collapse = "; ")))
  }
  status <- if (length(warn_list) > 0) "WARN" else "PASS"
  mk_check("registry_integrity", "Registry/book_state integrity",
           status,
           if (length(warn_list) > 0) paste(warn_list, collapse = "; ")
           else "all parse OK")
}

check_release_metadata <- function(project_root, no_write = FALSE,
                                     strict = TRUE) {
  required_tags <- c("v7.0.1", "v7.1.0")
  out <- run_cmd("git", c("tag", "--list"), wd = project_root)
  tags <- if (out$rc == 0) strsplit(out$stdout, "\n")[[1]] else character()
  missing_tags <- setdiff(required_tags, tags)
  changelog <- file.path(project_root, "CHANGELOG.md")
  has_v701 <- FALSE
  has_v710 <- FALSE
  if (file.exists(changelog)) {
    cl <- paste(readLines(changelog, warn = FALSE), collapse = "\n")
    has_v701 <- grepl("v7\\.0\\.1", cl)
    has_v710 <- grepl("v7\\.1\\.0", cl)
  }
  problems <- character()
  if (length(missing_tags) > 0) {
    problems <- c(problems, sprintf("missing tags: %s",
                                      paste(missing_tags, collapse = ", ")))
  }
  if (!file.exists(changelog)) {
    problems <- c(problems, "CHANGELOG.md 부재")
  } else {
    if (!has_v701) problems <- c(problems, "CHANGELOG v7.0.1 entry 부재")
    if (!has_v710) problems <- c(problems, "CHANGELOG v7.1.0 entry 부재")
  }
  if (length(problems) == 0) {
    return(mk_check("release_metadata", "Release metadata (tags + CHANGELOG)",
                    "PASS",
                    sprintf("tags %s + CHANGELOG OK",
                            paste(required_tags, collapse = ", "))))
  }
  status <- if (strict) "FAIL" else "WARN"
  mk_check("release_metadata", "Release metadata (tags + CHANGELOG)",
           status, paste(problems, collapse = "; "))
}

check_soak_record <- function(project_root, no_write = FALSE,
                                next_actions_ref = NULL) {
  soak_path <- file.path(project_root,
                           "qepm/observability/readiness/soak_log.json")
  if (!file.exists(soak_path)) {
    if (!is.null(next_actions_ref)) {
      assign("v8_next_actions",
             c(get("v8_next_actions", envir = next_actions_ref),
               "soak_log.json 첫 생성 — 3일 내 readiness gate 2회 이상 실행 필요"),
             envir = next_actions_ref)
    }
    return(mk_check("soak_record", "3-day soak record",
                    "WARN", "soak_log.json 부재 (첫 실행)",
                    soak_path))
  }
  data <- tryCatch(fromJSON(soak_path, simplifyVector = TRUE),
                    error = function(e) NULL)
  if (is.null(data) || is.null(data$runs) ||
      length(data$runs) == 0) {
    return(mk_check("soak_record", "3-day soak record",
                    "WARN", "soak_log.json empty"))
  }
  # Recent 3-day runs
  now <- Sys.time()
  runs <- as.data.frame(data$runs, stringsAsFactors = FALSE)
  if (!"ran_at" %in% names(runs)) {
    return(mk_check("soak_record", "3-day soak record",
                    "WARN", "soak_log schema invalid"))
  }
  ts_parsed <- tryCatch(
    as.POSIXct(runs$ran_at, format = "%Y-%m-%dT%H:%M:%S"),
    error = function(e) NULL
  )
  if (is.null(ts_parsed)) {
    return(mk_check("soak_record", "3-day soak record",
                    "WARN", "ran_at parse fail"))
  }
  recent_3d <- sum(!is.na(ts_parsed) &
                     as.numeric(now - ts_parsed, units = "days") <= 3)
  critical_count <- sum(runs$critical_failure_count %||% 0L,
                         na.rm = TRUE)
  if (recent_3d >= 2 && critical_count == 0) {
    return(mk_check("soak_record", "3-day soak record",
                    "PASS",
                    sprintf("%d runs 최근 3일 내, critical=0", recent_3d),
                    soak_path))
  }
  if (!is.null(next_actions_ref)) {
    assign("v8_next_actions",
           c(get("v8_next_actions", envir = next_actions_ref),
             "v8 설계 착수 전 human 확인 의무 — 3일 내 readiness gate 2회+ critical 0 필요"),
           envir = next_actions_ref)
  }
  mk_check("soak_record", "3-day soak record",
           "WARN",
           sprintf("recent_3d=%d critical=%d (요구: recent>=2 + critical=0)",
                   recent_3d, critical_count),
           soak_path)
}

# v7.2.1 Sprint 6 — 15번째 check
check_memory_health <- function(project_root, no_write = FALSE) {
  health_script <- file.path(project_root,
                             "02_Infrastructure/memory/memory_knowledge_health.R")
  if (!file.exists(health_script)) {
    return(mk_check("memory_health",
                    "Memory Knowledge Health Gate (v7.2.1)",
                    "FAIL", "memory_knowledge_health.R 부재"))
  }
  sot_path <- file.path(project_root,
                        "qepm/memory/axioms/axiom_sot_map.json")
  if (!file.exists(sot_path)) {
    return(mk_check("memory_health",
                    "Memory Knowledge Health Gate (v7.2.1)",
                    "FAIL", "axiom_sot_map.json 부재"))
  }
  helper_path <- file.path(project_root,
                           "02_Infrastructure/memory/memory_metadata_normalize.R")
  if (!file.exists(helper_path)) {
    return(mk_check("memory_health",
                    "Memory Knowledge Health Gate (v7.2.1)",
                    "FAIL", "memory_metadata_normalize.R helper 부재"))
  }
  if (no_write) {
    # Read latest report only
    report_path <- file.path(project_root,
                             "qepm/observability/memory_health_latest.json")
    if (!file.exists(report_path)) {
      return(mk_check("memory_health",
                      "Memory Knowledge Health Gate (v7.2.1)",
                      "WARN",
                      "memory_health_latest.json 부재 (no_write — skip rerun)"))
    }
    rep <- tryCatch(fromJSON(report_path, simplifyVector = TRUE),
                    error = function(e) NULL)
    if (is.null(rep)) {
      return(mk_check("memory_health",
                      "Memory Knowledge Health Gate (v7.2.1)",
                      "WARN", "memory_health_latest parse fail"))
    }
    hard <- rep$summary$hard_fail_count %||% 0L
    warn <- rep$summary$warning_count %||% 0L
    status <- if (hard == 0) "PASS" else "FAIL"
    return(mk_check("memory_health",
                    "Memory Knowledge Health Gate (v7.2.1)",
                    status,
                    sprintf("hard=%d warn=%d (cached)", hard, warn),
                    report_path))
  }
  out <- run_cmd("Rscript",
                 c("02_Infrastructure/memory/memory_knowledge_health.R"),
                 wd = project_root)
  status <- if (out$rc == 0) "PASS" else "FAIL"
  mk_check("memory_health",
           "Memory Knowledge Health Gate (v7.2.1)",
           status,
           sprintf("rc=%d", out$rc))
}

# ─────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────

run_v8_readiness_gate <- function(project_root = ".",
                                    write_report = TRUE,
                                    strict = TRUE,
                                    no_write = FALSE) {
  if (no_write) write_report <- FALSE
  ran_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

  next_actions_env <- new.env()
  assign("v8_next_actions", character(), envir = next_actions_env)

  checks <- list(
    check_hook_dryrun(project_root, no_write),
    check_e2e_kernel(project_root, no_write),
    check_router_selftest(project_root, no_write),
    check_state_machine_selftest(project_root, no_write),
    check_cert_rules_selftest(project_root, no_write, strict),
    check_schema_active_wt(project_root, no_write),
    check_legacy_active_hook_zero(project_root, no_write),
    check_synthetic_residue_zero(project_root, no_write, strict),
    check_qvest_search(project_root, no_write),
    check_qvest_wt(project_root, no_write),
    check_timeline_generation(project_root, no_write),
    check_registry_integrity(project_root, no_write),
    check_release_metadata(project_root, no_write, strict),
    check_soak_record(project_root, no_write, next_actions_env),
    check_memory_health(project_root, no_write)
  )

  statuses <- sapply(checks, function(c) c$status)
  pass <- sum(statuses == "PASS")
  fail <- sum(statuses == "FAIL")
  warn <- sum(statuses == "WARN")
  skip <- sum(statuses == "SKIP")

  overall <- if (fail > 0) "FAIL" else if (warn > 0) "WARN" else "PASS"
  ready <- (overall == "PASS") ||
           (!strict && overall == "WARN" && fail == 0)

  next_actions <- get("v8_next_actions", envir = next_actions_env)
  if (overall == "FAIL") {
    failed_ids <- sapply(checks[statuses == "FAIL"], function(c) c$id)
    next_actions <- c(next_actions,
                       sprintf("FAIL check 해소 필요: %s",
                               paste(failed_ids, collapse = ", ")))
  }
  if (overall == "PASS") {
    next_actions <- c(next_actions,
                       "v8.0 설계 착수 가능 — soak 3일 추가 권장")
  }

  result <- list(
    gate_id = "v8_design_readiness",
    ran_at = ran_at,
    project_root = normalizePath(project_root, mustWork = FALSE),
    overall = overall,
    ready_for_v8_design = ready,
    checks = checks,
    summary = list(pass = pass, fail = fail, warn = warn, skip = skip),
    next_actions = I(as.character(next_actions)),  # I() forces JSON array even at length 1 (auto_unbox=TRUE 회피 — Python iterate 시 글자별 split 방지)
    strict = strict,
    no_write = no_write
  )

  # Write report
  if (write_report && !no_write) {
    out_dir <- file.path(project_root, "qepm/observability/readiness")
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    latest <- file.path(out_dir, "v8_readiness_latest.json")
    ts_path <- file.path(out_dir,
                          sprintf("v8_readiness_%s.json",
                                  format(Sys.time(), "%Y%m%d_%H%M%S")))
    write_json(result, latest, pretty = TRUE, auto_unbox = TRUE,
                null = "null")
    write_json(result, ts_path, pretty = TRUE, auto_unbox = TRUE,
                null = "null")

    # Append to soak_log
    soak_path <- file.path(out_dir, "soak_log.json")
    soak_data <- if (file.exists(soak_path)) {
      tryCatch(fromJSON(soak_path, simplifyVector = FALSE),
                error = function(e) list(runs = list()))
    } else list(runs = list())
    if (is.null(soak_data$runs)) soak_data$runs <- list()
    critical_count <- sum(sapply(checks, function(c)
      isTRUE(c$status == "FAIL")))
    soak_data$runs[[length(soak_data$runs) + 1]] <- list(
      ran_at = ran_at,
      overall = overall,
      pass = pass, fail = fail, warn = warn, skip = skip,
      critical_failure_count = critical_count
    )
    write_json(soak_data, soak_path, pretty = TRUE, auto_unbox = TRUE,
                null = "null")
    result$report_paths <- list(latest = latest,
                                  timestamped = ts_path,
                                  soak_log = soak_path)
  }

  result
}
