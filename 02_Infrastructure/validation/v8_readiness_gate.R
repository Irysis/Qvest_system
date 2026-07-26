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
# Checks — 개수는 여기에 적지 않는다(2026-07-26 VRG-3 부수 수리).
#   구 주석은 "14 Checks" 였고 실제는 16 이었다. 주석·부팅 라인·문서 세 곳에 개수를 박아
#   두면 check 를 추가할 때마다 세 곳을 같이 고쳐야 하고, 안 고치면 그 자체가 낡은 기대값이
#   된다(이 세션이 qvest.md 체크리스트에서 겪은 것과 동형). 개수는 런타임 산출이 정본:
#   summary 의 pass+fail+warn+skip 과 length(checks) 를 bootstrap:490~ 가 대조하고
#   불일치 시 "readiness 자가검산 불일치" WARN 을 발행한다.
# ─────────────────────────────────────────────────────────────────

#──────────────────────────────────────────────────────────────────────────────
# Hook dry-run 배터리 — 결과 파일 위치 + 판정 (2026-07-26 수리)
#
# [기전] 구현은 `08_Tests/hooks/results.json` 을 읽었으나, 러너는 2026-07-25
#   artifact-storage 이관 이후 `.cache/test_results/hook_dryrun_results.json` 에
#   쓴다(run_all_hooks.sh:53-57). 구 경로는 그 이후 **영구 부재** →
#   배터리가 127 pass / 0 fail 로 통과해도 게이트는 그것을 못 보고
#   no_write 에선 WARN("검증 불충분"), run 모드에선 FAIL("results.json 생성 실패")
#   을 냈다. 즉 이 체크의 판정이 **배터리 실측과 무관**했다(대리 판정).
#
# [설계] ① 러너 산출 경로가 정본, 구 경로는 fallback 으로만 남긴다(구 체크아웃/
#   외부 CI 호환). **둘 다 부재 = 명시 FAIL** — "결과가 없다"는 "통과"가 아니다.
#   ② 총계 하드코딩(구 `pass >= 17`)은 제거한다. 스위트가 늘 때마다 라벨과 문턱을
#   같이 고쳐야 하는 동형 함정이고(30/30 → 17/17 → 실제 127 로 이미 두 번 표류),
#   **총계 래칫은 suite_totals_watch.sh 가 전담**한다
#   (06_Registry/suite_totals_baseline.json, 감소 시 exit 1). 게이트는
#   "실패 0 + 계측이 살아 있었는가" 만 본다.
#   ③ 단 `total_pass == 0` / `tests[] == 0` 은 통과가 아니라 **계측 사망**이므로
#   여기서 FAIL 로 잡는다(러너 자신의 UNREPORTED 가드와 이중 방어).
#──────────────────────────────────────────────────────────────────────────────
HOOK_DRYRUN_NAME <- "Hook dry-run 배터리 (총계 = 러너 산출)"
HOOK_DRYRUN_RESULT_RELS <- c(
  ".cache/test_results/hook_dryrun_results.json",  # 현행 정본 (run_all_hooks.sh)
  "08_Tests/hooks/results.json"                    # 구 경로 (fallback)
)
# no_write 모드는 러너를 안 돌리므로 판정이 과거 산출에 기댄다. daily_refresh 가
# 매일 suite_totals_watch --collect 로 러너를 돌리므로(주기 1일), 이 임계를 넘긴
# 캐시는 "현재 상태의 증거"가 아니다 → PASS 아닌 WARN.
HOOK_DRYRUN_MAX_AGE_DAYS <- 7

.hook_dryrun_find_results <- function(project_root) {
  for (rel in HOOK_DRYRUN_RESULT_RELS) {
    p <- file.path(project_root, rel)
    if (file.exists(p)) {
      return(list(found = TRUE, path = p, rel = rel,
                  mtime = file.info(p)$mtime))
    }
  }
  list(found = FALSE, path = NA_character_, rel = NA_character_,
       mtime = as.POSIXct(NA))
}

# 판정 = PASS/FAIL + 실패 수 + 계측 생존. 문턱(총계 하한) 없음 — 위 설계 ②.
.hook_dryrun_verdict <- function(data) {
  bad <- function(reason) list(ok = FALSE, reason = reason, summary = reason)
  if (is.null(data) || !is.list(data)) return(bad("결과 JSON parse 실패"))
  tp <- suppressWarnings(as.numeric(data$total_pass %||% NA))
  tf <- suppressWarnings(as.numeric(data$total_fail %||% NA))
  n_suites <- NROW(data$tests %||% NULL)
  if (length(tp) != 1L || length(tf) != 1L || is.na(tp) || is.na(tf)) {
    return(bad("total_pass/total_fail 필드 부재 또는 비수치 (계측 산출 손상)"))
  }
  summary <- sprintf("%g pass / %g fail / suite %d", tp, tf, n_suites)
  if (tf != 0) {
    return(list(ok = FALSE,
                reason = sprintf("%s — 실패 %g건", summary, tf),
                summary = summary))
  }
  if (tp <= 0) {
    return(list(ok = FALSE,
                reason = sprintf("%s — total_pass=0 = 계측 사망(통과 아님)", summary),
                summary = summary))
  }
  if (n_suites <= 0) {
    return(list(ok = FALSE,
                reason = sprintf("%s — tests[] 비어 있음 = 스위트 0건 실행", summary),
                summary = summary))
  }
  st <- data$status %||% ""
  if (nzchar(st) && !identical(toupper(st), "PASS")) {
    return(list(ok = FALSE,
                reason = sprintf("%s — status 필드='%s' 불일치(산출 손상/수기 편집 의심)",
                                 summary, st),
                summary = summary))
  }
  list(ok = TRUE, reason = "", summary = summary)
}

check_hook_dryrun <- function(project_root, no_write = FALSE) {
  runner_rel <- "08_Tests/hooks/run_all_hooks.sh"
  hook_runner <- file.path(project_root, runner_rel)
  if (!file.exists(hook_runner)) {
    return(mk_check("hook_dryrun", HOOK_DRYRUN_NAME,
                    "FAIL", "run_all_hooks.sh 부재"))
  }
  searched <- paste(HOOK_DRYRUN_RESULT_RELS, collapse = " | ")

  if (no_write) {
    found <- .hook_dryrun_find_results(project_root)
    if (!found$found) {
      # 조용한 통과 금지: 러너를 안 돌렸고 캐시도 없으면 '미검증'이며, 미검증은 실패다.
      return(mk_check("hook_dryrun", HOOK_DRYRUN_NAME,
                      "FAIL",
                      sprintf("결과 파일 부재 (탐색: %s) — no_write 는 러너를 돌리지 않으므로 미검증 = 통과 아님",
                              searched)))
    }
    data <- tryCatch(fromJSON(found$path, simplifyVector = TRUE),
                     error = function(e) NULL)
    v <- .hook_dryrun_verdict(data)
    age_days <- as.numeric(difftime(Sys.time(), found$mtime, units = "days"))
    if (!isTRUE(v$ok)) {
      return(mk_check("hook_dryrun", HOOK_DRYRUN_NAME,
                      "FAIL",
                      sprintf("%s [%s]", v$reason, found$rel),
                      found$path))
    }
    if (is.finite(age_days) && age_days > HOOK_DRYRUN_MAX_AGE_DAYS) {
      return(mk_check("hook_dryrun", HOOK_DRYRUN_NAME,
                      "WARN",
                      sprintf("%s — 단 캐시 %.1f일 경과(>%d일): 현재 상태 증거 아님 (daily_refresh/suite_totals_watch --collect 확인) [%s]",
                              v$summary, age_days, HOOK_DRYRUN_MAX_AGE_DAYS,
                              found$rel),
                      found$path))
    }
    return(mk_check("hook_dryrun", HOOK_DRYRUN_NAME,
                    "PASS",
                    sprintf("%s (cached %.1fh 경과, no_write — 재실행 skip) [%s]",
                            v$summary, age_days * 24, found$rel),
                    found$path))
  }

  # run 모드: 러너를 직접 돌린 뒤, **이번 실행이 갱신한 산출**만 판정 근거로 삼는다.
  # (구 산출이 남아 있으면 러너가 죽어도 옛 성공을 현재 성공으로 오독 — 존재=유효 함정)
  t0 <- Sys.time()
  out <- run_cmd("bash", c(runner_rel), timeout_sec = 900L, wd = project_root)
  found <- .hook_dryrun_find_results(project_root)
  if (!found$found) {
    return(mk_check("hook_dryrun", HOOK_DRYRUN_NAME,
                    "FAIL",
                    sprintf("결과 파일 생성 실패 (rc=%s, 탐색: %s)", out$rc, searched)))
  }
  # 파일시스템 시각 해상도/시계 오차 여유 5초.
  if (is.finite(as.numeric(found$mtime)) &&
      as.numeric(difftime(found$mtime, t0, units = "secs")) < -5) {
    return(mk_check("hook_dryrun", HOOK_DRYRUN_NAME,
                    "FAIL",
                    sprintf("러너가 결과를 갱신하지 못함 (rc=%s, mtime=%s < 실행시작=%s) — 구 산출 재사용 차단",
                            out$rc,
                            format(found$mtime, "%Y-%m-%dT%H:%M:%S"),
                            format(t0, "%Y-%m-%dT%H:%M:%S")),
                    found$path))
  }
  data <- tryCatch(fromJSON(found$path, simplifyVector = TRUE),
                   error = function(e) NULL)
  v <- .hook_dryrun_verdict(data)
  if (!isTRUE(v$ok)) {
    return(mk_check("hook_dryrun", HOOK_DRYRUN_NAME,
                    "FAIL",
                    sprintf("%s (rc=%s) [%s]", v$reason, out$rc, found$rel),
                    found$path))
  }
  mk_check("hook_dryrun", HOOK_DRYRUN_NAME,
           "PASS",
           sprintf("%s (rc=%s) [%s]", v$summary, out$rc, found$rel),
           found$path)
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
  # bare python3 = Windows Store 스텁(rc 9009/49) — QVEST_PY 우선 (2026-07-18 수리)
  py_bin <- Sys.getenv("QVEST_PY", "python3")
  out <- run_cmd(py_bin, c(router_rel, "selftest"), wd = project_root)
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
    # L-314 + v8.0: terminal(처분완료) WT는 schema 검증 무의미 — active WT만 검증.
    # ARCHIVED/REJECT + JUDGE_FAILED/PASSED/COMPLETED/GRADUATION_FAIL/GOVERNOR 종결 포함.
    status_data <- tryCatch(jsonlite::fromJSON(sf, simplifyVector = FALSE),
                            error = function(e) NULL)
    if (!is.null(status_data)) {
      # phase 키 변종 수용: current_phase | phase (status.json 작성 주체별 상이).
      phase_val <- status_data$current_phase %||% status_data$phase %||% ""
      if (grepl("^ARCHIVED_|^REJECT_|_REJECT_|^REJECTED|JUDGE_FAILED|JUDGE_PASSED|GRADUATION_FAIL|^COMPLETED|GOVERNOR_REJECTED|GOVERNOR_ADMITTED",
                phase_val)) next
      # result/codex_stance 기반 종결 신호: standalone FAIL / 모든 hard gate 탈락 / Codex REJECT
      # = 비-admit 종결 리서치 WT (alpha_vector 부재가 정상, schema 검증 무의미).
      result_val <- status_data$result %||% ""
      stance_val <- status_data$codex_stance %||% ""
      if (grepl("FAIL|REJECT", result_val, ignore.case = TRUE) ||
          identical(toupper(stance_val), "REJECT")) next
    }
    # Try alpha_package validation if present
    alpha_pkg_abs <- file.path(wt_dir, "alpha_package.json")
    if (file.exists(alpha_pkg_abs)) {
      # Relative path from project_root (한글 absolute path 회피)
      alpha_pkg_rel <- sub(paste0(project_root, "/?"), "", alpha_pkg_abs)
      router_rel2 <- "02_Infrastructure/hooks/qvest_hook_router.py"
      # bare python3 = Windows Store 스텁(rc 9009/49) — QVEST_PY 우선.
      # [2026-07-25] :240 은 07-18 에 수리됐으나 같은 파일의 이 지점이 누락돼 있었다.
      # 여기서 스텁이 잡히면 rc!=0 → alpha_package 가 전부 "INVALID" 로 계상돼
      # readiness 판정이 **스키마 문제로 오귀속**된다(계측이 아니라 판정의 오염).
      py_bin2 <- Sys.getenv("QVEST_PY", "python3")
      out <- run_cmd(py_bin2,
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
  # (2026-06-10 fix) system2 env= 인자는 Windows에서 명령행 앞에 "VAR=0"이 붙어 rc=127 거짓 FAIL 유발.
  # --no-auto-rebuild 플래그가 이미 동일 효과이므로 env 인자 제거.
  out <- run_cmd("bash",
                  c(tool$rel, "governor", "--limit", "3", "--no-auto-rebuild"),
                  wd = project_root)
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
  recent_idx <- !is.na(ts_parsed) &
                  as.numeric(now - ts_parsed, units = "days") <= 3
  recent_3d <- sum(recent_idx)
  #──────────────────────────────────────────────────────────────────────────
  # (2026-07-26 VRG-5 수리, probe② 감사 확정) critical 합산을 **최근 3일 창**으로 한정.
  #   구현은 recent_3d 만 창을 적용하고 critical 은 soak_log 전 이력을 합산해,
  #   06-26(3)+07-18(4)=누적 7 이 영구히 박혀 이후 clean 실행을 아무리 쌓아도
  #   critical_count==0 이 성립 불가 → soak_record 영구 WARN(false-red).
  #   "3-day soak record" 라는 체크 이름과 판정 모집단이 어긋나 있던 것.
  # 컬럼 부재는 0 폴백(fail-open) 대신 schema invalid 로 승격 — 필드 개명 시
  #   critical 전멸을 0 으로 오독하는 경로 차단(:645 ran_at 부재 처리와 동형).
  #──────────────────────────────────────────────────────────────────────────
  if (is.null(runs$critical_failure_count)) {
    return(mk_check("soak_record", "3-day soak record",
                    "WARN",
                    "soak_log schema invalid — critical_failure_count 컬럼 부재(필드 개명 의심). 0 폴백 금지",
                    soak_path))
  }
  critical_count <- sum(runs$critical_failure_count[recent_idx], na.rm = TRUE)
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
    #──────────────────────────────────────────────────────────────────────────
    # (2026-07-26 MKH-01/VRG-4 수리, probe② 감사 확정 · 도훈 승인) 두 결함:
    #  ① 캐시 나이 미검증 — 같은 파일의 soak_record 는 ran_at 을 검사하는데(:645) 이
    #     체크만 누락. 헬스 파이프라인이 몇 주 멈춰도 낡은 스냅샷의 hard=0 을
    #     "PASS (cached)" 로 **현재형** 보고했다.
    #  ② `%||% 0L` 폴백 — summary 필드가 결측/개명되면 hard=0 → 무조건 PASS.
    #     스키마 드리프트가 곧바로 거짓 초록(결측=미관측이지 0이 아니다).
    #──────────────────────────────────────────────────────────────────────────
    if (is.null(rep$summary$hard_fail_count)) {
      return(mk_check("memory_health", "Memory Knowledge Health Gate (v7.2.1)",
                      "WARN",
                      "summary$hard_fail_count 필드 부재 — 스키마 드리프트 의심(0 폴백 금지)",
                      report_path))
    }
    hard <- rep$summary$hard_fail_count
    warn <- rep$summary$warning_count %||% NA_integer_
    age_h <- NA_real_
    ran <- rep$ran_at %||% rep$generated_at %||% NULL
    if (!is.null(ran)) {
      age_h <- tryCatch(as.numeric(difftime(Sys.time(),
                          as.POSIXct(substr(as.character(ran)[1], 1, 19),
                                     format = "%Y-%m-%dT%H:%M:%S"),
                          units = "hours")),
                        error = function(e) NA_real_)
    }
    MH_MAX_AGE_H <- 24   # 부팅이 매 세션 갱신하므로 24h 초과 = 파이프라인 정지 신호
    if (hard != 0) {
      status <- "FAIL"
    } else if (is.na(age_h)) {
      status <- "WARN"
    } else if (age_h > MH_MAX_AGE_H) {
      status <- "WARN"
    } else {
      status <- "PASS"
    }
    detail <- sprintf("hard=%s warn=%s (cached%s)", format(hard), format(warn),
                      if (is.na(age_h)) ", ★나이 미상 — 신선 취급 금지"
                      else sprintf(", %.1fh 경과%s", age_h,
                                   if (age_h > MH_MAX_AGE_H)
                                     sprintf(" ★>%dh: 낡은 스냅샷이라 현재 상태의 증거 아님",
                                             MH_MAX_AGE_H) else ""))
    return(mk_check("memory_health",
                    "Memory Knowledge Health Gate (v7.2.1)",
                    status, detail, report_path))
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
# v8.0 architecture 정합 (effort/skills/python-policy/axiom_inject/SR2.5/naming/perf)
# ─────────────────────────────────────────────────────────────────
check_v8_architecture <- function(project_root, no_write = FALSE) {
  rl <- function(p) tryCatch(readLines(file.path(project_root, p), warn = FALSE),
                             error = function(e) character())
  has_fm <- function(agent, key) any(grepl(paste0("^", key, ":"),
                    rl(file.path(".claude/agents", paste0(agent, ".md")))))
  ok <- character(); bad <- character()
  core <- c("alpha-research", "risk-research", "optimizer-research", "forge", "judge", "governor")
  skl  <- c("alpha-research", "risk-research", "optimizer-research", "judge", "governor")
  if (all(vapply(core, has_fm, logical(1), key = "effort"))) ok <- c(ok, "effort") else bad <- c(bad, "effort_frontmatter")
  if (all(vapply(skl,  has_fm, logical(1), key = "skills"))) ok <- c(ok, "skills") else bad <- c(bad, "skills_frontmatter")
  if (length(rl(".claude/rules/python-policy.md"))   > 0) ok <- c(ok, "python-policy") else bad <- c(bad, "python-policy.md")
  if (length(rl("02_Infrastructure/docs/rules/artifact-naming.md")) > 0) ok <- c(ok, "artifact-naming") else bad <- c(bad, "artifact-naming.md")
  if (length(rl("02_Infrastructure/eval/harness_perf_eval.R")) > 0) ok <- c(ok, "perf-eval") else bad <- c(bad, "harness_perf_eval.R")
  sj <- paste(rl(".claude/settings.json"), collapse = "\n")
  if (grepl("axiom_context_inject", sj)) ok <- c(ok, "axiom_inject_registered") else bad <- c(bad, "axiom_context_inject_unregistered")
  if (!grepl("unified_agent_guard", sj)) ok <- c(ok, "unified_retired") else bad <- c(bad, "unified_agent_guard_still_registered")
  cm <- paste(rl("CLAUDE.md"), collapse = "\n")
  if (grepl("SR 2\\.5", cm)) ok <- c(ok, "SR2.5") else bad <- c(bad, "SR_target_2.5")
  status <- if (length(bad) == 0) "PASS" else "FAIL"
  mk_check("v8_architecture",
           "v8.0 구조 정합 (effort/skills/python-policy/axiom_inject/SR2.5/naming/perf)",
           status,
           sprintf("ok=%d [%s]%s", length(ok), paste(ok, collapse = ","),
                   if (length(bad)) sprintf(" | FAIL=%d [%s]", length(bad), paste(bad, collapse = ",")) else ""))
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
    check_memory_health(project_root, no_write),
    check_v8_architecture(project_root, no_write)
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
