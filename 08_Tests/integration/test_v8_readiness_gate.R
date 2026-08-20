#==============================================================================
# test_v8_readiness_gate.R — Integration Test for v8 Design Readiness Gate
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

# ─── Project root ────────────────────────────────────────────────────────────
# [fix 2026-07-25] 구 하드코딩 PROJ = "/mnt/c/Users/User/OneDrive/바탕 화면/..."
# (WSL 전용 경로)는 Windows R에서 현재 드라이브 기준 "C:/mnt/..."로 해석된다.
# 그 위치에 빈 디렉토리 잔재가 남아 있어 setwd()가 *조용히 성공*하고, 이후 상대경로
# source()가 전부 파일 부재로 실패 → 0 pass / 1 fail. dir.exists()만으로는 이 잔재를
# 걸러내지 못하므로 marker 파일 존재로 검증한다.
# (test_execution_path_unified.R · test_wt_lifecycle_e2e.R 동형)
# ★후보 순서는 CLAUDE_PROJECT_DIR 우선 — 모듈측 관례(cert_rules.R `.qvest_find_root`
# 등)와 맞춘다. QM_ROOT를 앞에 두면 worktree 실행 시 split root가 발생한다.
# 주의: ~/.Renviron이 QM_ROOT를 고정하므로 쉘 export로는 덮이지 않는다.
.resolve_proj <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot",
             "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) {
    stop("project root 미발견 — QM_ROOT 환경변수를 설정하세요 (marker: ", marker, ")")
  }
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)

cat("\n", strrep("=", 70), "\n", sep = "")
cat("v8 Readiness Gate Integration Test\n")
cat(strrep("=", 70), "\n", sep = "")

PASS_COUNT <- 0L
FAIL_COUNT <- 0L
RESULTS <- list()

mark_pass <- function(name, msg = "") {
  PASS_COUNT <<- PASS_COUNT + 1L
  RESULTS[[name]] <<- list(status = "PASS", message = msg)
  cat(sprintf("[PASS] %s%s\n", name,
              if (nzchar(msg)) sprintf(" — %s", msg) else ""))
}

mark_fail <- function(name, msg = "") {
  FAIL_COUNT <<- FAIL_COUNT + 1L
  RESULTS[[name]] <<- list(status = "FAIL", message = msg)
  cat(sprintf("[FAIL] %s — %s\n", name, msg))
}

# Test 1: source loads
GATE_PATH <- "02_Infrastructure/validation/v8_readiness_gate.R"
loaded <- tryCatch({
  suppressMessages(source(GATE_PATH))
  TRUE
}, error = function(e) {
  mark_fail("source_load", conditionMessage(e))
  FALSE
})
if (loaded) mark_pass("source_load", "v8_readiness_gate.R 로드 성공")

# Test 2: run returns list
res <- NULL
if (loaded) {
  res <- tryCatch(
    run_v8_readiness_gate(project_root = PROJ,
                            strict = FALSE,
                            write_report = FALSE,
                            no_write = TRUE),
    error = function(e) {
      mark_fail("run_returns_list",
                sprintf("crash: %s", conditionMessage(e)))
      NULL
    }
  )
  if (!is.null(res) && is.list(res)) {
    mark_pass("run_returns_list",
              sprintf("list with %d top-level fields", length(res)))
  }
}

# Test 3: JSON serializable
if (!is.null(res)) {
  ser <- tryCatch({
    json <- toJSON(res, auto_unbox = TRUE, null = "null")
    parsed <- fromJSON(json, simplifyVector = FALSE)
    !is.null(parsed)
  }, error = function(e) {
    mark_fail("json_serializable", conditionMessage(e))
    FALSE
  })
  if (isTRUE(ser)) mark_pass("json_serializable", "toJSON roundtrip OK")
}

# Test 4: required fields
if (!is.null(res)) {
  required_fields <- c("gate_id", "ran_at", "overall",
                        "ready_for_v8_design", "checks", "summary",
                        "next_actions")
  missing <- setdiff(required_fields, names(res))
  if (length(missing) == 0) {
    mark_pass("required_fields_present",
              sprintf("all %d fields", length(required_fields)))
  } else {
    mark_fail("required_fields_present",
              sprintf("missing: %s", paste(missing, collapse = ", ")))
  }

  if (identical(res$gate_id, "v8_design_readiness")) {
    mark_pass("gate_id_valid", "v8_design_readiness")
  } else {
    mark_fail("gate_id_valid", sprintf("got: %s", res$gate_id))
  }

  if (is.list(res$checks) && length(res$checks) >= 14) {
    mark_pass("checks_count",
              sprintf("%d checks (>= 14)", length(res$checks)))
  } else {
    mark_fail("checks_count",
              sprintf("got %d", length(res$checks %||% list())))
  }

  check_struct_ok <- all(sapply(res$checks, function(c) {
    is.list(c) && all(c("id", "name", "status", "details") %in% names(c))
  }))
  if (check_struct_ok) {
    mark_pass("check_structure",
              "all checks have id+name+status+details")
  } else {
    mark_fail("check_structure", "some checks missing fields")
  }

  summary <- res$summary %||% list()
  if (all(c("pass", "fail", "warn", "skip") %in% names(summary))) {
    mark_pass("summary_fields",
              sprintf("pass=%d fail=%d warn=%d skip=%d",
                      summary$pass, summary$fail, summary$warn,
                      summary$skip))
  } else {
    mark_fail("summary_fields", "summary missing fields")
  }
}

# Test 5: status values valid
if (!is.null(res)) {
  valid_statuses <- c("PASS", "FAIL", "WARN", "SKIP")
  invalid <- sapply(res$checks, function(c) !c$status %in% valid_statuses)
  if (sum(invalid) == 0) {
    mark_pass("status_values_valid",
              "모든 check status valid")
  } else {
    mark_fail("status_values_valid",
              sprintf("%d invalid", sum(invalid)))
  }
}

# Test 6: resolve_tool works
if (loaded) {
  for (tool_name in c("qvest_search", "qvest_wt", "qvest_observe")) {
    rt <- resolve_tool(tool_name, PROJ)
    if (rt$found) {
      mark_pass(sprintf("resolve_%s", tool_name),
                sprintf("found at %s", rt$rel))
    } else {
      mark_pass(sprintf("resolve_%s", tool_name),
                sprintf("clear FAIL (%d candidates)",
                        length(rt$candidates)))
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Test 7: hook_dryrun 위반 주입 (2026-07-26 수리 동반)
#
# 왜: 이 체크는 2026-07-25 산출 경로 이관(08_Tests/hooks/results.json →
#   .cache/test_results/hook_dryrun_results.json) 이후 **읽는 파일이 영구 부재**라
#   배터리 127/0 통과와 무관하게 판정했다. 경로만 고치면 "이제 PASS 나온다"로
#   끝나기 쉬운데, 그건 검사가 살아 있다는 증거가 아니다 — 틀린 입력을 주입해
#   실제로 FAIL 이 나오는지 봐야 한다(오탐 제거와 검사 사망은 겉보기가 같다).
# ─────────────────────────────────────────────────────────────────────────────
if (loaded) {
  .mkroot <- function() {
    r <- file.path(tempfile("v8gate_inject_"))
    dir.create(file.path(r, "08_Tests/hooks"), recursive = TRUE,
               showWarnings = FALSE)
    dir.create(file.path(r, ".cache/test_results"), recursive = TRUE,
               showWarnings = FALSE)
    writeLines("#!/usr/bin/env bash\nexit 0",
               file.path(r, "08_Tests/hooks/run_all_hooks.sh"))
    r
  }
  .put <- function(root, rel, txt, age_days = 0) {
    p <- file.path(root, rel)
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    writeLines(txt, p)
    if (age_days > 0) {
      Sys.setFileTime(p, Sys.time() - age_days * 86400)
    }
    p
  }
  .ok_json <- function(pass = 127, fail = 0, status = "PASS",
                       tests = '[{"test":"a","pass":127,"fail":0,"total":127}]') {
    sprintf('{"suite":"qvest_v6_4_hook_dryrun","total_pass":%d,"total_fail":%d,"total":%d,"status":"%s","tests":%s}',
            pass, fail, pass + fail, status, tests)
  }
  .expect <- function(label, root, want) {
    got <- tryCatch(check_hook_dryrun(root, no_write = TRUE),
                    error = function(e) list(status = paste0("ERROR:",
                                                             conditionMessage(e)),
                                             details = ""))
    if (identical(got$status, want)) {
      mark_pass(label, sprintf("%s — %s", want, substr(got$details, 1, 70)))
    } else {
      mark_fail(label, sprintf("기대 %s / 실제 %s — %s",
                               want, got$status, substr(got$details, 1, 90)))
    }
    invisible(got)
  }

  # (1) 결과 파일 둘 다 부재 = 미검증 → FAIL (조용한 통과 0)
  r1 <- .mkroot()
  .expect("inject_hook_dryrun_no_results", r1, "FAIL")

  # (2) 러너 자체 부재 → FAIL
  r2 <- .mkroot(); file.remove(file.path(r2, "08_Tests/hooks/run_all_hooks.sh"))
  .expect("inject_hook_dryrun_no_runner", r2, "FAIL")

  # (3) 실패 있는 산출 → FAIL
  r3 <- .mkroot()
  .put(r3, ".cache/test_results/hook_dryrun_results.json",
       .ok_json(pass = 120, fail = 3, status = "FAIL",
                tests = '[{"test":"a","pass":120,"fail":3,"total":123}]'))
  .expect("inject_hook_dryrun_has_failures", r3, "FAIL")

  # (4) 0 pass / 0 fail 을 "ALL PASS"로 위장한 계측 사망 → FAIL
  r4 <- .mkroot()
  .put(r4, ".cache/test_results/hook_dryrun_results.json",
       .ok_json(pass = 0, fail = 0, status = "PASS", tests = "[]"))
  .expect("inject_hook_dryrun_zero_total", r4, "FAIL")

  # (5) pass>0 이지만 tests[] 가 비어 있음(스위트 0건 실행) → FAIL
  r5 <- .mkroot()
  .put(r5, ".cache/test_results/hook_dryrun_results.json",
       .ok_json(pass = 27, fail = 0, status = "PASS", tests = "[]"))
  .expect("inject_hook_dryrun_empty_suites", r5, "FAIL")

  # (6) status 필드 불일치(수기 편집/산출 손상) → FAIL
  r6 <- .mkroot()
  .put(r6, ".cache/test_results/hook_dryrun_results.json",
       .ok_json(status = "FAIL"))
  .expect("inject_hook_dryrun_status_mismatch", r6, "FAIL")

  # (7) 손상 JSON → FAIL
  r7 <- .mkroot()
  .put(r7, ".cache/test_results/hook_dryrun_results.json", "{not json")
  .expect("inject_hook_dryrun_corrupt_json", r7, "FAIL")

  # (8) 정상 산출 → PASS (검사가 통과도 낼 수 있어야 함 — 항상-FAIL 은 검사가 아님)
  r8 <- .mkroot()
  .put(r8, ".cache/test_results/hook_dryrun_results.json", .ok_json())
  .expect("inject_hook_dryrun_healthy_pass", r8, "PASS")

  # (9) 구 경로만 존재 = fallback 실효
  r9 <- .mkroot()
  .put(r9, "08_Tests/hooks/results.json", .ok_json())
  g9 <- .expect("inject_hook_dryrun_legacy_fallback", r9, "PASS")
  if (grepl("08_Tests/hooks/results.json", g9$details, fixed = TRUE)) {
    mark_pass("inject_hook_dryrun_legacy_labeled", "fallback 경로가 details에 명시")
  } else {
    mark_fail("inject_hook_dryrun_legacy_labeled",
              sprintf("어느 경로를 읽었는지 불명: %s", g9$details))
  }

  # (10) 통과 산출이지만 8일 경과 = 현재 상태 증거 아님 → WARN (PASS 아님)
  r10 <- .mkroot()
  .put(r10, ".cache/test_results/hook_dryrun_results.json", .ok_json(),
       age_days = 8)
  .expect("inject_hook_dryrun_stale_cache", r10, "WARN")

  # (11) 현행 경로 우선순위: 현행=정상 / 구=실패 → 현행을 읽어 PASS
  r11 <- .mkroot()
  .put(r11, ".cache/test_results/hook_dryrun_results.json", .ok_json())
  .put(r11, "08_Tests/hooks/results.json",
       .ok_json(pass = 1, fail = 9, status = "FAIL",
                tests = '[{"test":"a","pass":1,"fail":9,"total":10}]'))
  .expect("inject_hook_dryrun_current_path_priority", r11, "PASS")

  unlink(c(r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11),
         recursive = TRUE, force = TRUE)
}

# ─────────────────────────────────────────────────────────────────────────────
# Test 8: schema_active_wt 위반 주입 (2026-08-13 수리 동반)
#
# 왜: check_schema_active_wt 는 "종결 WT 는 검증 대상 아님"을 **자유 서술 phase 문자열
#   정규식**으로 판정했다. 실측 238 status.json 에서 종결 표현이 26종으로 갈라져 있어
#   ALPHA_NEGATIVE_NO_MATERIAL(재료 자격 arm 0 = alpha_vector 미발행이 정상)이
#   'alpha INVALID' 로 계상됐다 — 정상 종결을 결함으로 오독. 음성 종결은 이 시스템의
#   표준 산출이므로 라운드마다 재발하는 상시 FAIL 이고, 상시 FAIL 은 진짜 FAIL 을 가린다.
#   수리 = 정규식 확장이 아니라 **구조화 필드**(advance_to_risk) 판독.
#   ★수리가 검사를 죽이지 않았음을 여기서 고정한다: advance 를 선언한 WT 의 invalid 는
#   여전히 FAIL 이어야 하고, 필드가 없는 legacy 도 종전대로 FAIL 이어야 한다.
# ─────────────────────────────────────────────────────────────────────────────
if (loaded) {
  # 스텁 router — alpha_vector 가 null 이면 rc=1(INVALID). 실제 스키마 검증은
  # 별도 테스트 소관이고, 여기서 시험하는 것은 게이트의 **분기**(검증할지 건너뛸지)다.
  .stub_router <- c(
    "import sys, io",
    "args = sys.argv[1:]",
    "pkg = None",
    "for i, a in enumerate(args):",
    "    if a == '--package' and i + 1 < len(args):",
    "        pkg = args[i + 1]",
    "txt = io.open(pkg, encoding='utf-8').read() if pkg else ''",
    "sys.exit(1 if 'null' in txt else 0)")

  .mkwt <- function(tag) {
    r <- gsub("\\\\", "/", tempfile(paste0("v8gate_wt_", tag, "_")))
    dir.create(file.path(r, "02_Infrastructure/hooks"), recursive = TRUE,
               showWarnings = FALSE)
    writeLines(.stub_router,
               file.path(r, "02_Infrastructure/hooks/qvest_hook_router.py"))
    r
  }
  # advance: TRUE / FALSE / NA(필드 자체를 안 씀) · valid: alpha_vector 유효 여부
  .add_wt <- function(root, wt_id, advance, valid) {
    d <- file.path(root, "qepm/mailbox/worktask", wt_id)
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    adv <- if (is.na(advance)) "" else
      sprintf(',\n  "advance_to_risk": %s', if (advance) "true" else "false")
    writeLines(sprintf('{\n  "task_id": "%s",\n  "current_phase": "ALPHA_NEGATIVE_NO_MATERIAL"%s\n}',
                       wt_id, adv),
               file.path(d, "status.json"))
    writeLines(if (valid) '{"alpha_vector": [{"ticker": "005930", "alpha": 0.01}]}'
               else '{"alpha_vector": null}',
               file.path(d, "alpha_package.json"))
    invisible(d)
  }
  .expect_wt <- function(label, root, want, want_detail = NULL) {
    got <- tryCatch(check_schema_active_wt(root, no_write = TRUE),
                    error = function(e) list(status = paste0("ERROR:",
                                                             conditionMessage(e)),
                                             details = ""))
    ok <- identical(got$status, want) &&
      (is.null(want_detail) || grepl(want_detail, got$details, fixed = TRUE))
    if (ok) mark_pass(label, sprintf("%s — %s", want, substr(got$details, 1, 70)))
    else    mark_fail(label, sprintf("기대 %s%s / 실제 %s — %s", want,
                                     if (is.null(want_detail)) "" else
                                       sprintf("(+'%s')", want_detail),
                                     got$status, substr(got$details, 1, 90)))
    invisible(got)
  }

  # (1) ★수리 대상: 비-전진 선언 WT 의 alpha_vector 결측은 결함이 아니다.
  #     같은 root 에 정상 WT 를 함께 둬서 "건너뛰었다"를 validated=1 failed=0 으로 실증
  #     (WARN='validable WT 없음' 으로 새는 경로와 구분된다).
  w1 <- .mkwt("declared_stop")
  .add_wt(w1, "WT-D20260101_001", advance = FALSE, valid = FALSE)
  .add_wt(w1, "WT-D20260101_002", advance = NA,    valid = TRUE)
  .expect_wt("inject_schema_declared_stop_skipped", w1, "PASS", "validated=1 failed=0")

  # (2) ★검사 생존: 전진을 선언했는데 alpha_vector 가 없으면 여전히 FAIL
  w2 <- .mkwt("advancing_invalid")
  .add_wt(w2, "WT-D20260101_001", advance = TRUE, valid = FALSE)
  .expect_wt("inject_schema_advancing_invalid", w2, "FAIL", "failed=1")

  # (3) ★기존 동작 불변: 필드 없는 legacy WT 의 invalid 는 종전대로 FAIL
  w3 <- .mkwt("legacy_invalid")
  .add_wt(w3, "WT-D20260101_001", advance = NA, valid = FALSE)
  .expect_wt("inject_schema_no_field_invalid", w3, "FAIL", "failed=1")

  # (4) ★양성 대조: 정상 WT 는 PASS (항상-FAIL 은 검사가 아니다)
  w4 <- .mkwt("healthy")
  .add_wt(w4, "WT-D20260101_001", advance = TRUE, valid = TRUE)
  .expect_wt("inject_schema_healthy_pass", w4, "PASS", "failed=0")

  # (5) 비-전진 선언만 있으면 검증 대상 0 — PASS 로 새지 않고 WARN 으로 보고
  w5 <- .mkwt("all_stopped")
  .add_wt(w5, "WT-D20260101_001", advance = FALSE, valid = FALSE)
  .expect_wt("inject_schema_all_skipped_is_warn", w5, "WARN")

  unlink(c(w1, w2, w3, w4, w5), recursive = TRUE, force = TRUE)
}

# Final
total <- PASS_COUNT + FAIL_COUNT
cat("\n", strrep("=", 70), "\n", sep = "")
cat(sprintf("FINAL: %d pass / %d fail / %d total\n",
            PASS_COUNT, FAIL_COUNT, total))
status <- if (FAIL_COUNT == 0) "ALL PASS" else "FAIL"
cat(sprintf("STATUS: %s%s\n",
            if (FAIL_COUNT == 0) "✅ " else "❌ ", status))
cat(strrep("=", 70), "\n", sep = "")

# 2026-08-20: 배터리는 마지막 유효 JSON 줄만 읽는다 — 이 줄이 없어 미편입 상태였다.
cat(sprintf("{\"test\":\"test_v8_readiness_gate\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", PASS_COUNT, FAIL_COUNT, PASS_COUNT + FAIL_COUNT))
if (FAIL_COUNT > 0) quit(status = 1)
