#==============================================================================
# test_execution_path_unified.R — v7.0 Sprint 1 Integration Test
#
# 검증 대상:
#   (a) wt_advance() 가 sm_validated_advance() 호출 (transition 검증)
#   (b) cert hook + cert_backfill + router 결과 일치 (synthetic alpha_package fixture)
#   (c) waiver 없이 phase jump 시도 시 block
#
# Plan: nifty-tickling-hinton.md Sprint 1 작업 항목 6
# Verification 섹션 line 618: Rscript tests/integration/test_execution_path_unified.R → PASS
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

# ─── Project root ────────────────────────────────────────────────────────────
# [fix 2026-07-25] 구 하드코딩 PROJ = "/mnt/c/Users/User/OneDrive/바탕 화면/..."
# (WSL 전용 경로)는 Windows R에서 현재 드라이브 기준 "C:/mnt/..."로 해석된다.
# 그 위치에 빈 디렉토리 잔재가 남아 있어 setwd()가 *조용히 성공*하고, 이후 모든
# source()가 "No such file or directory"로 halt → 두 스위트가 단 1건의 assertion도
# 실행하지 못한 채 exit 1. dir.exists()만으로는 이 잔재를 걸러내지 못하므로
# marker 파일 존재로 검증한다 (config.R 후보 순서와 동형, 검증만 강화).
# ★후보 순서는 CLAUDE_PROJECT_DIR 우선 — 본 스위트가 source하는 모듈들
# (cert_rules.R `.qvest_find_root` · essence_backfill.R · distilled.R)이 전부
# CLAUDE_PROJECT_DIR→QM_ROOT 순이다. 여기서 QM_ROOT를 앞에 두면 worktree 실행 시
# 테스트 PROJ(=main)와 모듈 PROJ_ROOT(=worktree)가 갈려 존재하는 파일이
# "package not found"로 기각된다(split root). config.R만 반대 순서인 예외.
# 주의: ~/.Renviron이 QM_ROOT를 고정하므로 쉘 export로는 덮이지 않는다 —
# 실행 루트를 바꾸려면 CLAUDE_PROJECT_DIR를 쓸 것.
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

# ─── Python 인터프리터 ───────────────────────────────────────────────────────
# [fix 2026-07-25] bare "python3"는 Windows에서 Store 스텁으로 해석돼 "Python"만
# 출력하고 rc 49로 종료한다 — router가 아예 실행되지 않으므로 아래 (b) parity
# assertion들이 실측 JSON이 아닌 스텁 출력을 파싱하게 된다.
# QVEST_PY(부트 검증된 실인터프리터) → venv 순으로 해석
# (state_machine.R:256 · cert_rules.R:437 동형).
PY_BIN <- Sys.getenv("QVEST_PY", unset = "")
if (!nzchar(PY_BIN) || !file.exists(PY_BIN)) {
  PY_BIN <- file.path(PROJ, ".venv_qvest_ml/Scripts/python.exe")
}
if (!file.exists(PY_BIN)) PY_BIN <- "python3"

cat("\n", strrep("=", 70), "\n", sep = "")
cat("v7.0 Sprint 1 — Execution Path Unified Integration Test\n")
cat(strrep("=", 70), "\n", sep = "")

PASS_COUNT <- 0L
FAIL_COUNT <- 0L
RESULTS <- list()

# ─── Cleanup 등록 ────────────────────────────────────────────────────────────
# [fix 2026-07-25] 구 코드는 최상위에서 on.exit(unlink(...))로 정리를 등록했으나,
# on.exit는 *함수 프레임*에 등록되므로 스크립트 최상위에서는 조용히 no-op이다
# (실측: 정상종료/error halt/quit(status=1) 3경로 전부 미발화) → synthetic WT가
# production qepm/mailbox/worktask/ 에 실행마다 누적됐다.
# reg.finalizer(onexit=TRUE)는 3경로 전부에서 발화(실측)하므로 이걸로 교체한다.
.CLEANUP_PATHS <- character(0)
register_cleanup <- function(p) .CLEANUP_PATHS <<- unique(c(.CLEANUP_PATHS, p))
invisible(reg.finalizer(globalenv(), function(e) {
  for (p in .CLEANUP_PATHS) if (dir.exists(p) || file.exists(p)) {
    unlink(p, recursive = TRUE)
  }
}, onexit = TRUE))

mark_pass <- function(name, msg = "") {
  PASS_COUNT <<- PASS_COUNT + 1L
  RESULTS[[name]] <<- list(status = "PASS", message = msg)
  cat(sprintf("[PASS] %s%s\n", name, if (nzchar(msg)) sprintf(" — %s", msg) else ""))
}

mark_fail <- function(name, msg = "") {
  FAIL_COUNT <<- FAIL_COUNT + 1L
  RESULTS[[name]] <<- list(status = "FAIL", message = msg)
  cat(sprintf("[FAIL] %s — %s\n", name, msg))
}

# ─────────────────────────────────────────────────────────────────
# Test (a): wt_advance() → sm_validated_advance() 위임 + invalid transition block
# ─────────────────────────────────────────────────────────────────

cat("\n--- Test (a): wt_advance → sm_validated_advance 위임 ---\n")

suppressMessages(source("02_Infrastructure/worktask/worktask_manager.R"))

# Synthetic temp WT (year 9999 — production 오염 방지)
fake_wt <- "WT-D99999999_999"
fake_dir <- file.path("qepm/mailbox/worktask", fake_wt)
dir.create(fake_dir, recursive = TRUE, showWarnings = FALSE)
register_cleanup(fake_dir)

writeLines('{"current_phase":"SPEC_APPROVED","task_id":"WT-D99999999_999"}',
           file.path(fake_dir, "status.json"))
writeLines('{"events":[]}', file.path(fake_dir, "governance_log.json"))

# (a.1) Invalid transition (SPEC_APPROVED → GOVERNOR_ADMITTED, skip middle) → BLOCKED
res_a1 <- tryCatch(
  wt_advance(fake_wt, "GOVERNOR_ADMITTED"),
  error = function(e) conditionMessage(e)
)
if (is.character(res_a1) && grepl("BLOCKED|state_machine", res_a1)) {
  mark_pass("a1_invalid_transition_blocked",
            sprintf("phase jump SPEC→GOV ADM 차단 (%s)",
                    substring(res_a1, 1, 80)))
} else {
  mark_fail("a1_invalid_transition_blocked",
            sprintf("expected stop() with BLOCKED, got: %s",
                    paste(deparse(res_a1), collapse = " ")))
}

# (a.2) Valid transition (SPEC_APPROVED → ALPHA_DONE) — artifact 부재로 BLOCKED expected
res_a2 <- tryCatch(
  wt_advance(fake_wt, "ALPHA_DONE"),
  error = function(e) conditionMessage(e)
)
if (is.character(res_a2) && grepl("missing artifacts|BLOCKED", res_a2)) {
  mark_pass("a2_artifact_check_blocked",
            sprintf("missing artifact 차단 (%s)", substring(res_a2, 1, 80)))
} else {
  mark_fail("a2_artifact_check_blocked",
            sprintf("expected stop() with missing artifacts, got: %s",
                    paste(deparse(res_a2), collapse = " ")))
}

# ─────────────────────────────────────────────────────────────────
# Test (b): cert eligibility parity — router / R wrapper / cert_backfill 결과 일치
# ─────────────────────────────────────────────────────────────────

cat("\n--- Test (b): cert eligibility 3-source parity ---\n")

suppressMessages(source("02_Infrastructure/worktask/cert_rules.R"))
# ★(2026-09-25 Q19) 이 source 가 cert_backfill_audit.R 의 CLI 본체(--auto)를 돌려 운영
#   qepm/mailbox/governor/governance_log.json 에 append·.bak 을 남겼다(구 가드 `>= 0` 항상 참).
#   가드는 정본에서 고쳤고(.cba_is_cli_main · 08_Tests/ops/test_cert_backfill_main_guard.R),
#   여기서는 함수만 쓰므로 NO_MAIN 으로 한 번 더 막는다.
Sys.setenv(QVEST_CERT_BACKFILL_NO_MAIN = "1")
suppressMessages(source("02_Infrastructure/ops/cert_backfill_audit.R"))

# Synthetic alpha_package fixtures
# [fix 2026-07-25] 구 "/tmp/v70_sprint1_fixtures"는 Windows에서 "C:/tmp/..."로
# 해석돼 프로젝트 밖에 잔재를 남겼다(정리도 dead on.exit이라 미발화).
# tempfile() = 프로세스별 격리 + 세션 종료 시 자동 회수 (e2e 스위트 동형).
fixtures_dir <- tempfile("v70_sprint1_fixtures_")
dir.create(fixtures_dir, recursive = TRUE, showWarnings = FALSE)
register_cleanup(fixtures_dir)

# (b.1) Eligible alpha_package (4 AND condition 충족)
positive_pkg <- list(
  task_id = "WT-D99999999_991",
  hypothesis_summary = paste(rep("a", 100), collapse = ""),
  factor_specs = list(
    list(name = "F1", economic_rationale = "rationale 1", formula = "z(F1)"),
    list(name = "F2", economic_rationale = "rationale 2", formula = "z(F2)")
  ),
  diagnostics = list(
    alpha_inheritance_cor = 0.10,
    harvey_t_specs_pass_count = 4L
  )
)
positive_path <- file.path(fixtures_dir, "alpha_pos.json")
write_json(positive_pkg, positive_path, pretty = TRUE, auto_unbox = TRUE)

# Router via Python
router <- "02_Infrastructure/hooks/qvest_hook_router.py"
r1_router <- system2(PY_BIN,
                      c(router, "check-cert", "--cert", "alpha_discovery",
                        "--package-path", positive_path),
                      stdout = TRUE, stderr = TRUE)
r1_router_obj <- fromJSON(paste(r1_router, collapse = "\n"))
# R wrapper
r1_r <- cr_check_alpha_discovery(positive_path)
# cert_backfill wrapper (uses temp WT dir)
b1_dir <- file.path(fixtures_dir, "WT-D99999999_991")
dir.create(b1_dir, showWarnings = FALSE)
file.copy(positive_path, file.path(b1_dir, "alpha_package.json"), overwrite = TRUE)
r1_backfill <- check_alpha_discovery_eligibility(b1_dir)

if (isTRUE(r1_router_obj$eligible) && isTRUE(r1_r$eligible) && isTRUE(r1_backfill$eligible)) {
  mark_pass("b1_positive_parity",
            "router=R wrapper=cert_backfill 모두 eligible=TRUE")
} else {
  mark_fail("b1_positive_parity",
            sprintf("router=%s R=%s backfill=%s",
                    r1_router_obj$eligible, r1_r$eligible, r1_backfill$eligible))
}

# (b.2) Ineligible — harvey_t_count fail
neg_pkg <- positive_pkg
neg_pkg$diagnostics$harvey_t_specs_pass_count <- 1L
neg_path <- file.path(fixtures_dir, "alpha_neg_harvey.json")
write_json(neg_pkg, neg_path, pretty = TRUE, auto_unbox = TRUE)

r2_router <- system2(PY_BIN,
                      c(router, "check-cert", "--cert", "alpha_discovery",
                        "--package-path", neg_path),
                      stdout = TRUE, stderr = TRUE)
r2_router_obj <- fromJSON(paste(r2_router, collapse = "\n"))
r2_r <- cr_check_alpha_discovery(neg_path)
b2_dir <- file.path(fixtures_dir, "WT-D99999999_992")
dir.create(b2_dir, showWarnings = FALSE)
file.copy(neg_path, file.path(b2_dir, "alpha_package.json"), overwrite = TRUE)
r2_backfill <- check_alpha_discovery_eligibility(b2_dir)

if (isFALSE(r2_router_obj$eligible) && isFALSE(r2_r$eligible) && isFALSE(r2_backfill$eligible)) {
  mark_pass("b2_negative_harvey_parity",
            sprintf("3 source 모두 INELIGIBLE — reason: %s",
                    substring(r2_r$reason, 1, 50)))
} else {
  mark_fail("b2_negative_harvey_parity",
            sprintf("router=%s R=%s backfill=%s",
                    r2_router_obj$eligible, r2_r$eligible, r2_backfill$eligible))
}

# (b.3) Ineligible — alpha_inheritance_cor fail
cor_pkg <- positive_pkg
cor_pkg$diagnostics$alpha_inheritance_cor <- 0.99
cor_path <- file.path(fixtures_dir, "alpha_neg_cor.json")
write_json(cor_pkg, cor_path, pretty = TRUE, auto_unbox = TRUE)

r3_router <- system2(PY_BIN,
                      c(router, "check-cert", "--cert", "alpha_discovery",
                        "--package-path", cor_path),
                      stdout = TRUE, stderr = TRUE)
r3_router_obj <- fromJSON(paste(r3_router, collapse = "\n"))
r3_r <- cr_check_alpha_discovery(cor_path)
b3_dir <- file.path(fixtures_dir, "WT-D99999999_993")
dir.create(b3_dir, showWarnings = FALSE)
file.copy(cor_path, file.path(b3_dir, "alpha_package.json"), overwrite = TRUE)
r3_backfill <- check_alpha_discovery_eligibility(b3_dir)

if (isFALSE(r3_router_obj$eligible) && isFALSE(r3_r$eligible) && isFALSE(r3_backfill$eligible)) {
  mark_pass("b3_negative_cor_parity",
            sprintf("3 source 모두 INELIGIBLE — reason: %s",
                    substring(r3_r$reason, 1, 50)))
} else {
  mark_fail("b3_negative_cor_parity",
            sprintf("router=%s R=%s backfill=%s",
                    r3_router_obj$eligible, r3_r$eligible, r3_backfill$eligible))
}

# ─────────────────────────────────────────────────────────────────
# Test (c): waiver 없이 phase jump 시도 시 block (artifact 부재 case로 검증)
# ─────────────────────────────────────────────────────────────────

cat("\n--- Test (c): waiver 없이 phase jump block 검증 ---\n")

# (c.1) sm_validated_advance 직접 호출 — invalid transition 차단
suppressMessages(source("02_Infrastructure/worktask/state_machine.R"))
res_c1 <- tryCatch(
  sm_validated_advance(fake_wt, from = "ALPHA_DONE", to = "GOVERNOR_ADMITTED",
                        force_waiver = FALSE),
  error = function(e) conditionMessage(e)
)
if (is.character(res_c1) && grepl("BLOCKED transition", res_c1)) {
  mark_pass("c1_invalid_transition_block",
            "ALPHA_DONE → GOV_ADM (invalid) BLOCKED")
} else {
  mark_fail("c1_invalid_transition_block",
            sprintf("expected BLOCKED, got: %s", res_c1))
}

# (c.2) force_waiver=TRUE 시 통과 (단 artifact가 있어야 함; 여기선 force로 두 검증 모두 우회)
res_c2 <- tryCatch(
  sm_validated_advance(fake_wt, from = "SPEC_APPROVED", to = "GOVERNOR_ADMITTED",
                        force_waiver = TRUE),
  error = function(e) conditionMessage(e)
)
if (is.list(res_c2) && isTRUE(res_c2$advance)) {
  mark_pass("c2_force_waiver_pass",
            "force_waiver=TRUE 통과 (governance_log entry 의무)")
} else {
  mark_fail("c2_force_waiver_pass",
            sprintf("expected list(advance=TRUE), got: %s",
                    paste(deparse(res_c2), collapse = " ")))
}

# ─────────────────────────────────────────────────────────────────
# Final
# ─────────────────────────────────────────────────────────────────

total <- PASS_COUNT + FAIL_COUNT
cat("\n", strrep("=", 70), "\n", sep = "")
cat(sprintf("FINAL: %d pass / %d fail / %d total\n",
            PASS_COUNT, FAIL_COUNT, total))
status <- if (FAIL_COUNT == 0) "ALL PASS" else "FAIL"
cat(sprintf("STATUS: %s%s\n",
            if (FAIL_COUNT == 0) "✅ " else "❌ ",
            status))
cat(strrep("=", 70), "\n", sep = "")

# JSON results
# 결과는 재생성 가능한 산출물 → 코드 존(08_Tests) 밖 캐시에 쓴다
# (artifact-storage.md §1·§3, 2026-07-25 도훈 confirm).
out_dir  <- ".cache/test_results"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_json <- file.path(out_dir, "test_execution_path_unified_results.json")
write_json(
  list(
    test = "execution_path_unified",
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    pass = PASS_COUNT, fail = FAIL_COUNT, total = total,
    status = status,
    results = RESULTS
  ),
  out_json, pretty = TRUE, auto_unbox = TRUE
)
cat(sprintf("Results: %s\n", out_json))

# 2026-08-20: 배터리는 마지막 유효 JSON 줄만 읽는다 — 이 줄이 없어 미편입 상태였다.
cat(sprintf("{\"test\":\"test_execution_path_unified\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", PASS_COUNT, FAIL_COUNT, PASS_COUNT + FAIL_COUNT))
if (FAIL_COUNT > 0) quit(status = 1)
