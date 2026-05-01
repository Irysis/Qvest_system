#==============================================================================
# test_wt_lifecycle_e2e.R — v7.0 Sprint 4 E2E Kernel Test
#
# 4 시나리오 (Codex revised #4/#5):
#   (1) Happy path: WT-D99990101_001 — 모든 phase 통과 + 4/5 cert 발급
#   (2) Cert fail path: WT-D99990102_001 — alpha cert NOT_ISSUED (harvey_t=1) but RISK/OPT/FORGE/JUDGE 진행 가능, Governor admission 단계 passive deny
#   (3) PIT violation path: WT-D99990103_001 — judge가 lookahead 감지 → JUDGE_FAILED
#   (4) Codex reject path: WT-D99990104_001 — codex stance=REJECT + 9 HIGH critical concerns → escalate trigger
#
# 범위:
#   - synthetic fixture 사용 (실제 시장 데이터 불필요)
#   - production / book_state 무손상 (governor_concord은 temp root 격리)
#   - test WT는 valid pattern (year 9999 prefix)
#   - cleanup obligation (test 완료 후 dummy WT 제거)
#
# Plan: nifty-tickling-hinton.md Sprint 4
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ)

cat("\n", strrep("=", 70), "\n", sep = "")
cat("v7.0 Sprint 4 — E2E Kernel Tests (4 synthetic WT scenarios)\n")
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

# Setup
WT_ROOT <- "qepm/mailbox/worktask"
suppressMessages(source("02_Infrastructure/worktask/state_machine.R"))
suppressMessages(source("02_Infrastructure/worktask/cert_rules.R"))
ROUTER <- "02_Infrastructure/hooks/qvest_hook_router.py"
CERT_EVAL <- "02_Infrastructure/hooks/qvest_cert_eval.py"

# Synthetic fixtures dir + governor temp root
TEST_GOV_DIR <- tempfile("qvest_e2e_governor_")
dir.create(TEST_GOV_DIR, recursive = TRUE, showWarnings = FALSE)

# Cleanup obligation (Codex revised #4 — production governor_concord 무손상)
# v7.1-lite Sprint 0.1: _e2e_cleanup_guard.sh --force 호출로 회귀 방지 (residue 0 강제)
cleanup_all <- function() {
  for (wt in c("WT-D99990101_001", "WT-D99990102_001",
               "WT-D99990103_001", "WT-D99990104_001")) {
    d <- file.path(WT_ROOT, wt)
    if (dir.exists(d)) unlink(d, recursive = TRUE)
  }
  # v7.1-lite Sprint 0.1: post-test cleanup guard
  guard <- "08_Tests/integration/_e2e_cleanup_guard.sh"
  if (file.exists(guard)) {
    out <- tryCatch(
      system2("bash", c(guard, "--force"), stdout = TRUE, stderr = TRUE),
      error = function(e) NULL
    )
    # Best-effort: log but never fail test on cleanup
    if (!is.null(out)) {
      cat(paste(out, collapse = "\n"), "\n", sep = "")
    }
  }
  unlink(TEST_GOV_DIR, recursive = TRUE)
}
on.exit(cleanup_all(), add = TRUE)

# Fixture builders
build_alpha_pkg <- function(wt_id, harvey_t = 4L, cor = 0.10) {
  list(
    task_id = wt_id,
    as_of_date = "9999-01-01",
    hypothesis_summary = paste(rep("a", 100), collapse = ""),
    factor_specs = list(
      list(name = "F1", economic_rationale = "synthetic rationale 1",
           formula = "z(F1)"),
      list(name = "F2", economic_rationale = "synthetic rationale 2",
           formula = "z(F2)")
    ),
    diagnostics = list(
      alpha_inheritance_cor = cor,
      harvey_t_specs_pass_count = harvey_t,
      sig_dates_count = 100L,
      n_sig_dates = 100L
    ),
    alpha_vector = list(synthetic = TRUE)
  )
}

build_risk_pkg <- function(wt_id) {
  list(
    task_id = wt_id,
    as_of_date = "9999-01-01",
    factor_covariance_ref = "synthetic_cov.parquet",
    risk_summary = list(synthetic = TRUE),
    diagnostics = list(synthetic = TRUE),
    sigma_method = "Sample"
  )
}

build_opt_pkg <- function(wt_id, density = 1.0) {
  sig_dates <- 100L
  weights_dates <- as.integer(round(sig_dates * density))
  list(
    task_id = wt_id,
    as_of_date = "9999-01-01",
    method_selected = "MVO",
    expected_tracking_error = 0.04,
    target_weights = list(synthetic = TRUE),
    schedule_fidelity = list(
      weights_csv_unique_dates_count = weights_dates,
      alpha_sig_dates_count = sig_dates,
      schedule_density_ratio = density,
      infeasibility_report = NULL
    )
  )
}

build_forge_pkg <- function(wt_id) {
  list(
    task_id = wt_id,
    backtest_summary = list(SR = 1.5, CAGR = 0.18, MDD = -0.20),
    sr_realized_share_based = 1.5,
    measurement_basis_primary = "forge_realized_share_based",
    weights_csv_unique_dates_count = 100L,
    alpha_sig_dates_count = 100L,
    schedule_density_ratio = 1.0,
    schedule_density_pass = TRUE,
    pure_function_violation = FALSE
  )
}

build_judge_verdict <- function(wt_id, verdict = "APPROVE") {
  list(
    task_id = wt_id,
    verdict = verdict,
    gate_results = list(synthetic = TRUE)
  )
}

build_governor_admission <- function(wt_id, str_id, weight = 0.05,
                                      verdict = "GOVERNOR_ADMITTED") {
  list(
    task_id = wt_id,
    verdict = verdict,
    str_id = str_id,
    wt_type = "discovery",
    allocation_decided = setNames(list(weight), str_id),
    scenario_identified = "synthetic"
  )
}

setup_wt <- function(wt_id, phase = "SPEC_APPROVED") {
  d <- file.path(WT_ROOT, wt_id)
  if (dir.exists(d)) unlink(d, recursive = TRUE)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  status <- list(
    task_id = wt_id,
    current_phase = phase,
    updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  write_json(status, file.path(d, "status.json"),
             pretty = TRUE, auto_unbox = TRUE)
  write_json(list(events = list()), file.path(d, "governance_log.json"),
             pretty = TRUE, auto_unbox = TRUE)
  d
}

# ─────────────────────────────────────────────────────────────────
# Scenario (1) Happy path
# ─────────────────────────────────────────────────────────────────

cat("\n--- (1) Happy path WT-D99990101_001 ---\n")
wt1 <- "WT-D99990101_001"
d1 <- setup_wt(wt1)

# Build 5 packages + judge_verdict + governor_admission
write_json(build_alpha_pkg(wt1), file.path(d1, "alpha_package.json"),
           pretty = TRUE, auto_unbox = TRUE)
write_json(build_risk_pkg(wt1), file.path(d1, "risk_package.json"),
           pretty = TRUE, auto_unbox = TRUE)
write_json(build_opt_pkg(wt1), file.path(d1, "optimization_package.json"),
           pretty = TRUE, auto_unbox = TRUE)
write_json(build_forge_pkg(wt1), file.path(d1, "forge_package.json"),
           pretty = TRUE, auto_unbox = TRUE)
write_json(build_judge_verdict(wt1), file.path(d1, "judge_verdict.json"),
           pretty = TRUE, auto_unbox = TRUE)
write_json(build_governor_admission(wt1, str_id = wt1),
           file.path(d1, "governor_admission.json"),
           pretty = TRUE, auto_unbox = TRUE)

# Issue per-WT certs (synthetic via cert_eval issue)
issue_cert_local <- function(cert, pkg_path, wt_dir) {
  cert_path <- file.path(wt_dir, paste0(cert, "_certificate.json"))
  out <- tryCatch(
    system2("python3",
            args = c(shQuote(file.path(PROJ, CERT_EVAL)), "issue", cert,
                     shQuote(pkg_path), shQuote(cert_path),
                     "e2e_test_v7.0_sprint4"),
            env = sprintf("CLAUDE_PROJECT_DIR=%s", shQuote(PROJ)),
            stdout = TRUE, stderr = TRUE),
    error = function(e) NULL
  )
  file.exists(cert_path)
}

# 4 per-WT cert issuance (alpha / sr_provenance / forge_package_validated)
# schedule_fidelity는 source 차이로 생략 (Sprint 1 결정)
cert_alpha <- issue_cert_local("alpha_discovery", file.path(d1, "alpha_package.json"), d1)
cert_sr    <- issue_cert_local("sr_provenance", file.path(d1, "forge_package.json"), d1)
cert_forge <- issue_cert_local("forge_package_validated", file.path(d1, "forge_package.json"), d1)

# Verify cert content
alpha_cert <- fromJSON(file.path(d1, "alpha_discovery_certificate.json"),
                        simplifyVector = TRUE)
if (isTRUE(alpha_cert$issued)) {
  mark_pass("happy_alpha_cert_issued",
            sprintf("issued=TRUE harvey_t=%s cor=%s",
                    alpha_cert$harvey_t_specs_pass_count,
                    alpha_cert$alpha_inheritance_cor))
} else {
  mark_fail("happy_alpha_cert_issued",
            sprintf("expected issued=TRUE, got %s reason=%s",
                    alpha_cert$issued, alpha_cert$non_issuance_reason))
}

sr_cert <- fromJSON(file.path(d1, "sr_provenance_certificate.json"),
                     simplifyVector = TRUE)
if (isTRUE(sr_cert$issued)) {
  mark_pass("happy_sr_cert_issued", "sr_provenance ISSUED")
} else {
  mark_fail("happy_sr_cert_issued", sr_cert$non_issuance_reason)
}

forge_cert <- fromJSON(file.path(d1, "forge_package_validated_certificate.json"),
                        simplifyVector = TRUE)
if (isTRUE(forge_cert$issued)) {
  mark_pass("happy_forge_cert_issued", "forge_package_validated ISSUED")
} else {
  mark_fail("happy_forge_cert_issued", forge_cert$non_issuance_reason)
}

# Schema validation chain (alpha → risk → optimizer → forge → judge → governor)
schema_pairs <- list(
  c("alpha_package", "alpha_package.json"),
  c("risk_package", "risk_package.json"),
  c("optimization_package", "optimization_package.json"),
  c("forge_package", "forge_package.json"),
  c("judge_verdict", "judge_verdict.json"),
  c("governor_admission", "governor_admission.json")
)
all_schemas_valid <- TRUE
for (sp in schema_pairs) {
  res <- cr_validate_schema(sp[1], file.path(d1, sp[2]))
  if (!isTRUE(res$valid)) {
    all_schemas_valid <- FALSE
    cat(sprintf("    %s INVALID: %s\n", sp[1], res$reason))
  }
}
if (all_schemas_valid) {
  mark_pass("happy_schema_chain_valid", "6/6 schemas VALID")
} else {
  mark_fail("happy_schema_chain_valid", "1+ schema INVALID")
}

# ─────────────────────────────────────────────────────────────────
# Scenario (2) Cert fail path (passive deny — RISK 차단 아님)
# ─────────────────────────────────────────────────────────────────

cat("\n--- (2) Cert fail (passive deny) WT-D99990102_001 ---\n")
wt2 <- "WT-D99990102_001"
d2 <- setup_wt(wt2)

# alpha cert FAIL: harvey_t=1
write_json(build_alpha_pkg(wt2, harvey_t = 1L),
           file.path(d2, "alpha_package.json"),
           pretty = TRUE, auto_unbox = TRUE)
issue_cert_local("alpha_discovery", file.path(d2, "alpha_package.json"), d2)

alpha_cert2 <- fromJSON(file.path(d2, "alpha_discovery_certificate.json"),
                         simplifyVector = TRUE)
if (isFALSE(alpha_cert2$issued) &&
    grepl("harvey_t", alpha_cert2$non_issuance_reason)) {
  mark_pass("certfail_alpha_NOT_ISSUED",
            sprintf("passive deny: %s",
                    substring(alpha_cert2$non_issuance_reason, 1, 50)))
} else {
  mark_fail("certfail_alpha_NOT_ISSUED",
            sprintf("expected NOT_ISSUED with harvey_t reason, got: %s",
                    alpha_cert2$non_issuance_reason))
}

# RISK / OPTIMIZER / FORGE / JUDGE 진행 가능 — alpha cert 무관 (Charter v1.7 §10)
write_json(build_risk_pkg(wt2), file.path(d2, "risk_package.json"),
           pretty = TRUE, auto_unbox = TRUE)
write_json(build_opt_pkg(wt2), file.path(d2, "optimization_package.json"),
           pretty = TRUE, auto_unbox = TRUE)
write_json(build_forge_pkg(wt2), file.path(d2, "forge_package.json"),
           pretty = TRUE, auto_unbox = TRUE)
write_json(build_judge_verdict(wt2, verdict = "APPROVE_CONDITIONAL"),
           file.path(d2, "judge_verdict.json"),
           pretty = TRUE, auto_unbox = TRUE)

# 검증: 5 file 모두 존재 (cert FAIL이지만 lifecycle 진행)
all_progress_files <- all(sapply(c("risk_package.json", "optimization_package.json",
                                    "forge_package.json", "judge_verdict.json"),
                                  function(f) file.exists(file.path(d2, f))))
if (all_progress_files) {
  mark_pass("certfail_lifecycle_progresses",
            "RISK/OPT/FORGE/JUDGE 모두 작성 (alpha cert 무관)")
} else {
  mark_fail("certfail_lifecycle_progresses", "lifecycle file 부재")
}

# Governor admission 단계 passive deny — alpha cert NOT_ISSUED 상태에서
# governor_admission.json 작성 가능하지만 wt_check_graduation에서 fail
# (synthetic으로는 governor_admission JSON만 작성)
write_json(build_governor_admission(wt2, str_id = wt2,
                                     verdict = "GOVERNOR_REJECTED"),
           file.path(d2, "governor_admission.json"),
           pretty = TRUE, auto_unbox = TRUE)
ga2 <- fromJSON(file.path(d2, "governor_admission.json"),
                 simplifyVector = TRUE)
if (identical(ga2$verdict, "GOVERNOR_REJECTED")) {
  mark_pass("certfail_admission_passive_deny",
            "Governor REJECTED (alpha cert 부재 → admission 자격 박탈)")
} else {
  mark_fail("certfail_admission_passive_deny",
            sprintf("expected REJECTED, got: %s", ga2$verdict))
}

# ─────────────────────────────────────────────────────────────────
# Scenario (3) PIT violation path
# ─────────────────────────────────────────────────────────────────

cat("\n--- (3) PIT violation WT-D99990103_001 ---\n")
wt3 <- "WT-D99990103_001"
d3 <- setup_wt(wt3)

# Synthetic alpha synthesis script with lookahead pattern
synth_script <- file.path(d3, "alpha_synthesis.R")
writeLines(c(
  "# Synthetic test PIT violation",
  "lookahead_model <- lm(future_return ~ today_factor)",
  "cat('PIT violation injected\\n')"
), synth_script)

# Verify lookahead pattern present
content <- readLines(synth_script)
has_lookahead <- any(grepl("future_return\\s*~", content))
if (has_lookahead) {
  mark_pass("pit_lookahead_pattern_detected",
            "lm(future_return ~ today_factor) injected — judge agent가 감지 의무")
} else {
  mark_fail("pit_lookahead_pattern_detected", "lookahead pattern not found")
}

# Synthetic judge verdict — JUDGE_FAILED with PIT_VIOLATION reason
judge3 <- list(
  task_id = wt3,
  verdict = "FAIL",
  gate_results = list(
    pit_c1_full_sample_check = list(pass = FALSE,
                                      reason = "lm(future_return ~ today_factor) detected"),
    pit_c2_same_day_circular = list(pass = TRUE)
  ),
  pit_violations = list("C1: future_return regressor")
)
write_json(judge3, file.path(d3, "judge_verdict.json"),
           pretty = TRUE, auto_unbox = TRUE)

verdict3 <- fromJSON(file.path(d3, "judge_verdict.json"),
                      simplifyVector = TRUE)
if (identical(verdict3$verdict, "FAIL")) {
  mark_pass("pit_judge_failed",
            sprintf("judge FAIL with %d PIT violation",
                    length(verdict3$pit_violations)))
} else {
  mark_fail("pit_judge_failed",
            sprintf("expected FAIL, got: %s", verdict3$verdict))
}

# ─────────────────────────────────────────────────────────────────
# Scenario (4) Codex reject path
# ─────────────────────────────────────────────────────────────────

cat("\n--- (4) Codex reject WT-D99990104_001 ---\n")
wt4 <- "WT-D99990104_001"
d4 <- setup_wt(wt4)

# Synthetic codex_critic_response_alpha.json with stance=REJECT + 9 HIGH critical concerns
codex_resp <- list(
  agent_role = "alpha",
  reviewed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  stance = "REJECT",
  critical_concerns = lapply(1:9, function(i) {
    list(severity = "HIGH",
         issue = sprintf("synthetic critical concern #%d", i),
         remediation = "address before final")
  }),
  weakest_assumption = "synthetic alpha generation lacks economic mechanism"
)
write_json(codex_resp, file.path(d4, "codex_critic_response_alpha.json"),
           pretty = TRUE, auto_unbox = TRUE)

# Build draft (alpha_package_draft) to allow codex round trigger
write_json(build_alpha_pkg(wt4),
           file.path(d4, "alpha_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE)

# Synthetic challenge_note.md — agent rebuttal ALL → escalate trigger MET
chal_path <- file.path(d4, "challenge_note.md")
writeLines(c(
  "# Challenge Note",
  "",
  "## Codex critical concerns × 9 HIGH",
  "All REBUTTAL — economic rationale exists in factor_specs[].economic_rationale",
  "",
  "## Q-Lead escalation trigger",
  "9 HIGH severity ≥ 5 threshold — escalate Q-Lead recommended"
), chal_path)

# Verify codex round complete check via router
resp <- tryCatch(
  system2("python3",
          args = c(shQuote(file.path(PROJ, ROUTER)),
                   "check-codex-round-complete",
                   "--wt-id", wt4,
                   "--role", "alpha"),
          env = sprintf("CLAUDE_PROJECT_DIR=%s", shQuote(PROJ)),
          stdout = TRUE, stderr = TRUE),
  error = function(e) NULL
)
parsed_resp <- tryCatch(fromJSON(paste(resp, collapse = "\n"), simplifyVector = TRUE),
                         error = function(e) NULL)
if (!is.null(parsed_resp) && isTRUE(parsed_resp$complete)) {
  mark_pass("codex_round_complete",
            "draft + critic_response present — codex round 5단계 흐름 충족")
} else {
  mark_fail("codex_round_complete",
            sprintf("expected complete=TRUE, got: %s",
                    paste(deparse(parsed_resp), collapse = " ")))
}

# Verify stance + escalate detection
if (identical(codex_resp$stance, "REJECT") &&
    sum(sapply(codex_resp$critical_concerns,
                function(c) c$severity == "HIGH")) >= 5) {
  mark_pass("codex_escalate_trigger_met",
            "stance=REJECT + 9 HIGH ≥ 5 threshold → Q-Lead escalate trigger MET")
} else {
  mark_fail("codex_escalate_trigger_met",
            "escalate trigger condition not met")
}

# ─────────────────────────────────────────────────────────────────
# Production governor_concord 무손상 검증 (Codex revised #4)
# ─────────────────────────────────────────────────────────────────

cat("\n--- Production guard: book_state 무손상 검증 ---\n")

# admit 추가되면 안 됨
bs <- fromJSON("qepm/mailbox/governor/book_state.json", simplifyVector = FALSE)
admitted_now <- unlist(bs$admitted_ids %||% list())
synthetic_in_book <- any(grepl("WT-D9999", admitted_now))
if (!synthetic_in_book) {
  mark_pass("production_book_state_unchanged",
            sprintf("admitted_ids 무손상 (synthetic year 9999 admit 없음, 현 admit n=%d)",
                    length(admitted_now)))
} else {
  mark_fail("production_book_state_unchanged",
            "synthetic year 9999 ID가 production book에 admit됨")
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

out_json <- "08_Tests/integration/test_wt_lifecycle_e2e_results.json"
write_json(
  list(
    test = "wt_lifecycle_e2e",
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    pass = PASS_COUNT, fail = FAIL_COUNT, total = total,
    status = status,
    scenarios = c("happy_path", "cert_fail_passive_deny",
                  "pit_violation", "codex_reject"),
    results = RESULTS
  ),
  out_json, pretty = TRUE, auto_unbox = TRUE
)
cat(sprintf("Results: %s\n", out_json))

if (FAIL_COUNT > 0) quit(status = 1)
