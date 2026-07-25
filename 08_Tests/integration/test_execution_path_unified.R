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

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ)

cat("\n", strrep("=", 70), "\n", sep = "")
cat("v7.0 Sprint 1 — Execution Path Unified Integration Test\n")
cat(strrep("=", 70), "\n", sep = "")

PASS_COUNT <- 0L
FAIL_COUNT <- 0L
RESULTS <- list()

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
on.exit(unlink(fake_dir, recursive = TRUE), add = TRUE)

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
suppressMessages(source("02_Infrastructure/ops/cert_backfill_audit.R"))

# Synthetic alpha_package fixtures
fixtures_dir <- "/tmp/v70_sprint1_fixtures"
dir.create(fixtures_dir, showWarnings = FALSE)
on.exit(unlink(fixtures_dir, recursive = TRUE), add = TRUE)

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
r1_router <- system2("python3",
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

r2_router <- system2("python3",
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

r3_router <- system2("python3",
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

if (FAIL_COUNT > 0) quit(status = 1)
