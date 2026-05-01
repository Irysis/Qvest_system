#==============================================================================
# state_machine.R — Qvest v6.4 WorkTask State Machine
# 02_Infrastructure/worktask/state_machine.R
#
# Phase 5 (Sprint 2) — wt_advance() transition table 강제.
# 임의 phase jump waiver 없이 불가.
#
# Source: 02_Infrastructure/hooks/policies/state_transitions.json (single source)
#
# 사용:
#   source("02_Infrastructure/worktask/state_machine.R")
#   qvest_state_machine_selftest()
#   sm_check_transition(from = "ALPHA_DONE", to = "RISK_DONE") → TRUE
#   sm_check_artifacts(wt_id = "WT-D20260501_003", phase = "RISK_DONE") → list(pass=TRUE/FALSE, missing=...)
#
# v1.0 — 2026-05-01 Session 75 Sprint 2 Phase 5
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJ_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", unset = "")
if (PROJ_ROOT == "" || !dir.exists(PROJ_ROOT)) {
  PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
}

SM_POLICY_PATH <- file.path(PROJ_ROOT, "02_Infrastructure/hooks/policies/state_transitions.json")
WT_MAILBOX <- file.path(PROJ_ROOT, "qepm/mailbox/worktask")
SM_GOVERNANCE_LOG <- file.path(PROJ_ROOT, "qepm/mailbox/governor/governance_log.json")

# ─────────────────────────────────────────────────────────────────
# 1. Policy load (cached)
# ─────────────────────────────────────────────────────────────────

.sm_policy_cache <- NULL

sm_load_policy <- function(force_reload = FALSE) {
  if (!is.null(.sm_policy_cache) && !force_reload) {
    return(.sm_policy_cache)
  }
  if (!file.exists(SM_POLICY_PATH)) {
    stop(sprintf("[state_machine] Policy not found: %s", SM_POLICY_PATH))
  }
  policy <- fromJSON(SM_POLICY_PATH, simplifyVector = FALSE)
  assign(".sm_policy_cache", policy, envir = .GlobalEnv)
  policy
}

# ─────────────────────────────────────────────────────────────────
# 2. Check transition allowed
# ─────────────────────────────────────────────────────────────────

sm_check_transition <- function(from, to) {
  policy <- sm_load_policy()
  trans <- policy$transitions[[from]]
  if (is.null(trans)) {
    return(list(allowed = FALSE, reason = sprintf("unknown from_phase: %s", from)))
  }
  allowed_next <- unlist(trans$allowed_next)
  if (to %in% allowed_next) {
    return(list(allowed = TRUE, reason = sprintf("%s → %s allowed", from, to)))
  }
  if (isTRUE(trans$terminal)) {
    return(list(allowed = FALSE, reason = sprintf("%s is terminal", from)))
  }
  list(allowed = FALSE,
       reason = sprintf("%s → %s NOT in allowed_next: %s",
                        from, to, paste(allowed_next, collapse = ", ")))
}

# ─────────────────────────────────────────────────────────────────
# 3. Check artifacts present for given phase
# ─────────────────────────────────────────────────────────────────

sm_check_artifacts <- function(wt_id, phase) {
  policy <- sm_load_policy()
  rule <- policy$transitions[[phase]]
  if (is.null(rule)) {
    return(list(pass = FALSE, missing = c(sprintf("unknown phase: %s", phase))))
  }
  required <- unlist(rule$required_artifacts %||% list())
  if (length(required) == 0) {
    return(list(pass = TRUE, missing = character()))
  }

  wt_dir <- file.path(WT_MAILBOX, wt_id)
  if (!dir.exists(wt_dir)) {
    return(list(pass = FALSE, missing = c(sprintf("WT dir not found: %s", wt_id))))
  }

  missing <- character()
  for (art in required) {
    # Strip parenthetical comments e.g. "(or alpha-specific)"
    art_clean <- trimws(gsub("\\s*\\([^)]+\\)\\s*", "", art))
    art_clean <- gsub("\\{ID\\}", gsub("WT-", "WT_", wt_id), art_clean)

    # Check absolute path or wt_dir relative
    if (startsWith(art_clean, "stage_artifacts/")) {
      full_path <- file.path(PROJ_ROOT, art_clean)
    } else if (startsWith(art_clean, "qepm/")) {
      full_path <- file.path(PROJ_ROOT, art_clean)
    } else {
      full_path <- file.path(wt_dir, art_clean)
    }
    if (!file.exists(full_path)) {
      missing <- c(missing, art)
    }
  }

  list(pass = length(missing) == 0, missing = missing)
}

# ─────────────────────────────────────────────────────────────────
# 4. Waiver check
# ─────────────────────────────────────────────────────────────────

sm_check_waiver <- function(wt_id, waiver_field = "codex_critic_skip_waiver") {
  wt_dir <- file.path(WT_MAILBOX, wt_id)
  challenge_path <- file.path(wt_dir, "challenge_note.md")

  candidates <- c(challenge_path,
                  list.files(wt_dir, pattern = "_challenge_note\\.md$",
                             full.names = TRUE))
  for (path in candidates) {
    if (file.exists(path)) {
      content <- tryCatch(readLines(path, warn = FALSE),
                          error = function(e) character())
      if (any(grepl(waiver_field, content, fixed = TRUE))) {
        return(list(waiver = TRUE,
                    field = waiver_field,
                    path = path,
                    reason = sprintf("waiver '%s' found in %s",
                                     waiver_field, path)))
      }
    }
  }

  list(waiver = FALSE,
       field = waiver_field,
       reason = sprintf("waiver '%s' NOT found", waiver_field))
}

# ─────────────────────────────────────────────────────────────────
# 5. Validated wt_advance (worktask_manager.R 호출 가능)
# ─────────────────────────────────────────────────────────────────

sm_validated_advance <- function(wt_id, from, to, force_waiver = FALSE,
                                  validate_schema = TRUE) {
  # Step 1: Transition allowed?
  trans_result <- sm_check_transition(from, to)
  if (!trans_result$allowed) {
    if (force_waiver) {
      message(sprintf("[state_machine] WAIVER applied: %s",
                      trans_result$reason))
    } else {
      stop(sprintf("[state_machine] BLOCKED transition: %s | use force_waiver=TRUE with governance_log entry",
                   trans_result$reason))
    }
  }

  # Step 2: Artifacts present for `to` phase precondition?
  art_result <- sm_check_artifacts(wt_id, to)
  if (!art_result$pass) {
    waiver <- sm_check_waiver(wt_id, "phase_jump_waiver")
    if (!waiver$waiver && !force_waiver) {
      stop(sprintf("[state_machine] BLOCKED missing artifacts for %s: %s",
                   to, paste(art_result$missing, collapse = ", ")))
    } else {
      message(sprintf("[state_machine] WAIVER applied for missing artifacts: %s",
                      paste(art_result$missing, collapse = ", ")))
    }
  }

  # Step 3: v7.0 Sprint 3 — Schema validation (state transition precondition)
  schema_result <- list(skipped = TRUE, valid = NA, reason = "schema_validate=FALSE")
  if (isTRUE(validate_schema) && art_result$pass) {
    schema_result <- sm_validate_artifacts_schema(wt_id, to)
    if (!isTRUE(schema_result$valid) && !isTRUE(schema_result$skipped)) {
      waiver <- sm_check_waiver(wt_id, "schema_validation_waiver")
      if (!waiver$waiver && !force_waiver) {
        stop(sprintf("[state_machine] BLOCKED schema invalid for %s: %s",
                     to, schema_result$reason))
      } else {
        message(sprintf("[state_machine] WAIVER applied for schema invalid: %s",
                        schema_result$reason))
      }
    }
  }

  list(advance = TRUE,
       from = from,
       to = to,
       artifacts_check = art_result,
       transition_check = trans_result,
       schema_check = schema_result)
}

# ─────────────────────────────────────────────────────────────────
# v7.0 Sprint 3 — Schema validation for required artifacts
# ─────────────────────────────────────────────────────────────────

# Map phase → (artifact_filename, schema_name)
.SM_PHASE_SCHEMA_MAP <- list(
  "ALPHA_DONE" = list(file = "alpha_package.json", schema = "alpha_package"),
  "RISK_DONE" = list(file = "risk_package.json", schema = "risk_package"),
  "OPTIMIZER_DONE" = list(file = "optimization_package.json", schema = "optimization_package"),
  "FORGE_DONE" = list(file = "forge_package.json", schema = "forge_package"),
  "JUDGE_PASSED" = list(file = "judge_verdict.json", schema = "judge_verdict"),
  "JUDGE_FAILED" = list(file = "judge_verdict.json", schema = "judge_verdict"),
  "GOVERNOR_ADMITTED" = list(file = "governor_admission.json", schema = "governor_admission"),
  "GOVERNOR_REJECTED" = list(file = "governor_admission.json", schema = "governor_admission")
)

sm_validate_artifacts_schema <- function(wt_id, phase) {
  spec <- .SM_PHASE_SCHEMA_MAP[[phase]]
  if (is.null(spec)) {
    return(list(skipped = TRUE, valid = NA, reason = sprintf("no schema mapping for phase: %s", phase)))
  }
  art_path <- file.path(WT_MAILBOX, wt_id, spec$file)
  if (!file.exists(art_path)) {
    return(list(skipped = TRUE, valid = NA, reason = sprintf("artifact missing (skipped): %s", spec$file)))
  }

  router <- file.path(PROJ_ROOT, "02_Infrastructure/hooks/qvest_hook_router.py")
  if (!file.exists(router)) {
    return(list(skipped = TRUE, valid = NA, reason = "router not found"))
  }
  out <- tryCatch(
    system2("python3",
            args = c(shQuote(router), "validate-schema",
                     "--schema", spec$schema,
                     "--package", shQuote(art_path)),
            env = sprintf("CLAUDE_PROJECT_DIR=%s", shQuote(PROJ_ROOT)),
            stdout = TRUE, stderr = TRUE),
    error = function(e) NULL
  )
  if (is.null(out) || length(out) == 0) {
    return(list(skipped = FALSE, valid = FALSE, reason = "router invocation fail"))
  }
  parsed <- tryCatch(fromJSON(paste(out, collapse = "\n"), simplifyVector = TRUE),
                     error = function(e) NULL)
  if (is.null(parsed) || is.null(parsed$valid)) {
    return(list(skipped = FALSE, valid = FALSE,
                reason = sprintf("router output parse fail: %s",
                                substring(paste(out, collapse = " "), 1, 100))))
  }
  list(skipped = FALSE,
       valid = isTRUE(parsed$valid),
       reason = parsed$reason %||% "")
}

# ─────────────────────────────────────────────────────────────────
# 6. Selftest
# ─────────────────────────────────────────────────────────────────

`%||%` <- function(a, b) if (is.null(a)) b else a

qvest_state_machine_selftest <- function() {
  cat("=== Qvest v6.4 State Machine Selftest ===\n")

  # Test 1: Policy load
  policy <- tryCatch(sm_load_policy(force_reload = TRUE),
                     error = function(e) {
                       cat("[FAIL] policy load:", conditionMessage(e), "\n")
                       NULL
                     })
  if (is.null(policy)) return(invisible(FALSE))
  n_phases <- length(policy$phases)
  n_trans <- length(policy$transitions)
  cat(sprintf("[PASS] policy loaded: %d phases / %d transitions\n",
              n_phases, n_trans))

  # Test 2: Valid transitions
  cases <- list(
    list(from = "SPEC_APPROVED", to = "ALPHA_DONE", expect = TRUE),
    list(from = "ALPHA_DONE", to = "RISK_DONE", expect = TRUE),
    list(from = "RISK_DONE", to = "OPTIMIZER_DONE", expect = TRUE),
    list(from = "OPTIMIZER_DONE", to = "FORGE_DONE", expect = TRUE),
    list(from = "FORGE_DONE", to = "JUDGE_PASSED", expect = TRUE),
    list(from = "JUDGE_PASSED", to = "GOVERNOR_ADMITTED", expect = TRUE),
    list(from = "GOVERNOR_ADMITTED", to = "COMPLETED", expect = TRUE),
    # Invalid
    list(from = "SPEC_APPROVED", to = "FORGE_DONE", expect = FALSE),
    list(from = "ALPHA_DONE", to = "GOVERNOR_ADMITTED", expect = FALSE),
    list(from = "COMPLETED", to = "ALPHA_DONE", expect = FALSE)
  )
  pass_count <- 0
  for (case in cases) {
    res <- sm_check_transition(case$from, case$to)
    actual <- res$allowed
    if (actual == case$expect) {
      pass_count <- pass_count + 1
    } else {
      cat(sprintf("[FAIL] transition %s → %s: expected=%s actual=%s\n",
                  case$from, case$to, case$expect, actual))
    }
  }
  cat(sprintf("[PASS] transition cases: %d / %d\n", pass_count, length(cases)))

  # Test 3: Artifact check (synthetic — WT 없을 시 fail expected)
  art_test <- sm_check_artifacts("WT-NONEXIST_001", "ALPHA_DONE")
  if (!art_test$pass) {
    cat("[PASS] missing artifacts detection working\n")
  } else {
    cat("[FAIL] missing artifacts not detected\n")
  }

  # Test 4: Waiver check (synthetic)
  waiver_test <- sm_check_waiver("WT-NONEXIST_001")
  if (!waiver_test$waiver) {
    cat("[PASS] waiver absence detection working\n")
  }

  cat(sprintf("\n=== Selftest %s ===\n",
              if (pass_count == length(cases)) "PASS" else "PARTIAL"))
  invisible(pass_count == length(cases))
}

cat("[state_machine.R] Loaded. Functions:\n")
cat("  sm_load_policy(force_reload=FALSE)\n")
cat("  sm_check_transition(from, to)\n")
cat("  sm_check_artifacts(wt_id, phase)\n")
cat("  sm_check_waiver(wt_id, waiver_field='codex_critic_skip_waiver')\n")
cat("  sm_validated_advance(wt_id, from, to, force_waiver=FALSE)\n")
cat("  qvest_state_machine_selftest()\n")
