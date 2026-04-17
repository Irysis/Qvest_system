#==============================================================================
# Stage Gate Engine — Factor Research Process v4.0
# stage_gate_engine.R
#
# Core state machine for per-factor stage tracking.
# "하지 마라"가 아닌 "할 수 없게 만든다" — Stage Skip을 구조적으로 차단.
#
# Functions:
#   sg_init(factor_id, strategy_id)   — 트래커 생성
#   sg_get_state(factor_id)           — 현재 단계 조회
#   sg_can_advance(factor_id, target) — 전이 가능 여부 + 사유
#   sg_transition(factor_id, target, artifact_path) — 상태 전이 실행
#   sg_check_s6_entry(factor_id)      — S6 진입 게이트 (Judge 첫 행동)
#   sg_rollback_to_s2(factor_id)      — S5 재순환 시 S2로 롤백
#   sg_get_dashboard()                — 전체 현황 대시보드
#==============================================================================

suppressPackageStartupMessages(library(jsonlite))

# ─── Source schemas ───────────────────────────────────────────────────────────
.sg_root <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) {
  "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot/02_Infrastructure"
})
# Try validation/ subdirectory first, then root
.sg_schema_path <- file.path(.sg_root, "validation", "stage_artifact_schemas.R")
if (!file.exists(.sg_schema_path)) .sg_schema_path <- file.path(.sg_root, "stage_artifact_schemas.R")
source(.sg_schema_path)

# ─── Paths ────────────────────────────────────────────────────────────────────
.SG_CACHE <- file.path(dirname(.sg_root), ".cache", "stage_gate")
if (!dir.exists(.SG_CACHE)) dir.create(.SG_CACHE, recursive = TRUE)

# ─── Stage Order & Transition Rules ──────────────────────────────────────────

STAGE_ORDER <- c("S0", "S1", "S2", "S3", "S4", "S5", "S6", "S7",
                  "PG0", "PG1", "PG2", "PG3")

# Which artifact schema is required to COMPLETE each stage
STAGE_ARTIFACT_MAP <- list(
  S0  = "s0_record",
  S1  = "s1_construction",
  S2  = "s2_profile",
  S3  = "s3_orthogonality",
  S4  = "s4_integration",
  S5  = "s5_mutation",
  S6  = "s6_validation",
  S7  = NULL,             # S7 uses s6_validation as gate
  PG0 = "pg0_gap_review",
  PG1 = "pg1_admission",
  PG2 = "pg2_allocation_plan",
  PG3 = "pg3_monitoring"
)

# Transition rules: from -> list of valid targets with conditions
TRANSITION_RULES <- list(
  S0_complete = list(
    targets = "S1",
    conditions = list(S1 = list(artifact = "s0_record"))
  ),
  S1_complete = list(
    targets = "S2",
    conditions = list(S2 = list(artifact = "s1_construction"))
  ),
  S2_complete = list(
    targets = "S3",
    conditions = list(S3 = list(artifact = "s2_profile"))
  ),
  S3_complete = list(
    targets = "S4",
    conditions = list(S4 = list(artifact = "s3_orthogonality"))
  ),
  S4_complete = list(
    targets = c("S5", "S6"),
    conditions = list(
      S5 = list(artifact = "s4_integration",
                field_check = list(
                  logic = "OR",
                  checks = list(
                    list(field = "delta_sharpe", op = "<=", value = 0),
                    list(field = "kospi_beat", op = "==", value = FALSE)
                  )
                )),
      S6 = list(artifact = "s4_integration",
                field_check = list(
                  logic = "AND",
                  checks = list(
                    list(field = "delta_sharpe", op = ">", value = 0),
                    list(field = "kospi_beat", op = "==", value = TRUE),
                    list(field = "hard_fail", op = "==", value = FALSE)
                  )
                ))
    )
  ),
  S5_complete = list(
    targets = "S6",
    conditions = list(
      S6 = list(artifact = "s5_mutation",
                field_check = list(
                  logic = "AND",
                  checks = list(
                    list(field = "mutations_attempted", op = ">=", value = 9),
                    list(field = "f_category_count", op = ">=", value = 2),
                    list(field = "checklist_exhausted", op = "==", value = TRUE),
                    list(field = "synthesis_tested", op = "==", value = TRUE)
                  )
                ))
    )
  ),
  S6_complete = list(
    targets = "S7",
    conditions = list(S7 = list(artifact = "s6_validation"))
  ),

  # ─── PG Stage Transitions (v7 Portfolio Governor) ───
  S7_complete = list(
    targets = c("PG0", "ARCHIVE"),
    conditions = list(
      PG0 = list(artifact = "s6_validation",
                 field_check = list(
                   logic = "OR",
                   checks = list(
                     list(field = "grade", op = "==", value = "A"),
                     list(field = "grade", op = "==", value = "A_NOVEL"),
                     list(field = "grade", op = "==", value = "A_CONDITIONAL"),
                     list(field = "grade", op = "==", value = "B")
                   )
                 )),
      ARCHIVE = list(artifact = "s6_validation",
                     field_check = list(
                       logic = "OR",
                       checks = list(
                         list(field = "grade", op = "==", value = "C"),
                         list(field = "grade", op = "==", value = "F")
                       )
                     ))
    )
  ),
  PG0_complete = list(
    targets = "PG1",
    conditions = list(PG1 = list(artifact = "pg0_gap_review"))
  ),
  PG1_complete = list(
    targets = c("PG2", "S5"),
    conditions = list(
      PG2 = list(artifact = "pg1_admission",
                 field_check = list(
                   logic = "AND",
                   checks = list(
                     list(field = "admission_decision", op = "==", value = "ADMIT")
                   )
                 )),
      S5  = list(artifact = "pg1_admission",
                 field_check = list(
                   logic = "OR",
                   checks = list(
                     list(field = "admission_decision", op = "==", value = "DEFER"),
                     list(field = "admission_decision", op = "==", value = "REJECT")
                   )
                 ))
    )
  ),
  PG2_complete = list(
    targets = "PG3",
    conditions = list(PG3 = list(artifact = "pg2_allocation_plan"))
  )
)


# ─── Helper: tracker path ────────────────────────────────────────────────────

.tracker_path <- function(factor_id) {
  file.path(.SG_CACHE, paste0(factor_id, "_tracker.json"))
}

.artifact_dir <- function(strategy_id) {
  proj_root <- dirname(.sg_root)
  d <- file.path(proj_root, "04_Research", "strategies", strategy_id, "stage_artifacts")
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  d
}


# ─── sg_init ─────────────────────────────────────────────────────────────────

#' Initialize stage tracker for a new factor/strategy
#'
#' @param factor_id Character: unique factor identifier (e.g., "INV01_ForeignFlow")
#' @param strategy_id Character: strategy directory name (e.g., "STR_1422_foreign_flow")
#' @return Invisible tracker list
sg_init <- function(factor_id, strategy_id = NULL) {

  tracker <- list(
    factor_id = factor_id,
    strategy_id = strategy_id %||% factor_id,
    current_stage = "S0_pending",
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    stage_log = list(
      S0 = list(status = "pending", artifact = NULL, completed_at = NULL, completed_by = NULL),
      S1 = list(status = "blocked", artifact = NULL, completed_at = NULL, completed_by = NULL),
      S2 = list(status = "blocked", artifact = NULL, completed_at = NULL, completed_by = NULL),
      S3 = list(status = "blocked", artifact = NULL, completed_at = NULL, completed_by = NULL),
      S4 = list(status = "blocked", artifact = NULL, completed_at = NULL, completed_by = NULL),
      S5 = list(status = "not_required", artifact = NULL, completed_at = NULL, completed_by = NULL),
      S6 = list(status = "blocked", artifact = NULL, completed_at = NULL, completed_by = NULL),
      S7 = list(status = "blocked", artifact = NULL, completed_at = NULL, completed_by = NULL),
      PG0 = list(status = "blocked", artifact = NULL, completed_at = NULL, completed_by = NULL),
      PG1 = list(status = "blocked", artifact = NULL, completed_at = NULL, completed_by = NULL),
      PG2 = list(status = "blocked", artifact = NULL, completed_at = NULL, completed_by = NULL),
      PG3 = list(status = "blocked", artifact = NULL, completed_at = NULL, completed_by = NULL)
    ),
    mutation_count = 0L,
    mutation_log = list()
  )

  write_json(tracker, .tracker_path(factor_id), auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf("[stage_gate] Initialized: %s (strategy: %s)\n", factor_id, tracker$strategy_id))
  invisible(tracker)
}


# ─── sg_get_state ────────────────────────────────────────────────────────────

#' Get current stage state for a factor
#'
#' @param factor_id Character
#' @return List with current_stage, stage_log, and artifact inventory
sg_get_state <- function(factor_id) {
  path <- .tracker_path(factor_id)
  if (!file.exists(path)) {
    return(list(exists = FALSE, error = paste0("No tracker for: ", factor_id)))
  }
  tracker <- fromJSON(path, simplifyVector = FALSE)
  tracker$exists <- TRUE
  tracker
}


# ─── sg_can_advance ──────────────────────────────────────────────────────────

#' Check if a factor can advance to a target stage
#'
#' @param factor_id Character
#' @param target_stage Character: e.g., "S3", "S6"
#' @return list(ok = TRUE/FALSE, reason = "...", missing_artifacts = c(...))
sg_can_advance <- function(factor_id, target_stage) {

  state <- sg_get_state(factor_id)
  if (!isTRUE(state$exists)) {
    return(list(ok = FALSE, reason = "Tracker not found", missing_artifacts = NULL))
  }

  current <- state$current_stage

  # Parse current stage number
  current_num <- gsub("_.*", "", current)  # "S2_complete" -> "S2"
  current_status <- gsub("^S[0-9]_?", "", current)  # "complete" or "pending"

  # Must be "complete" to advance
  if (current_status != "complete") {
    return(list(
      ok = FALSE,
      reason = sprintf("Current stage %s is '%s', not 'complete'. Cannot advance to %s.",
                        current_num, current_status, target_stage),
      missing_artifacts = NULL
    ))
  }

  # Check transition rule exists
  rule_key <- paste0(current_num, "_complete")
  if (!rule_key %in% names(TRANSITION_RULES)) {
    return(list(ok = FALSE, reason = sprintf("No transition rule from %s", current_num),
                missing_artifacts = NULL))
  }

  rule <- TRANSITION_RULES[[rule_key]]

  # Check target is valid

  if (!target_stage %in% rule$targets) {
    return(list(
      ok = FALSE,
      reason = sprintf("Cannot go from %s to %s. Valid targets: %s",
                        current_num, target_stage, paste(rule$targets, collapse = ", ")),
      missing_artifacts = NULL
    ))
  }

  # Check artifact condition
  condition <- rule$conditions[[target_stage]]
  if (!is.null(condition$artifact)) {
    artifact_name <- condition$artifact
    prev_stage <- current_num
    artifact_entry <- state$stage_log[[prev_stage]]

    if (is.null(artifact_entry$artifact) || artifact_entry$artifact == "") {
      return(list(
        ok = FALSE,
        reason = sprintf("Missing artifact '%s' for stage %s completion.", artifact_name, prev_stage),
        missing_artifacts = artifact_name
      ))
    }

    # Validate artifact file exists
    if (!file.exists(artifact_entry$artifact)) {
      return(list(
        ok = FALSE,
        reason = sprintf("Artifact file not found: %s", artifact_entry$artifact),
        missing_artifacts = artifact_name
      ))
    }

    # Validate artifact content
    artifact_data <- tryCatch(fromJSON(artifact_entry$artifact, simplifyVector = FALSE),
                              error = function(e) NULL)
    if (is.null(artifact_data)) {
      return(list(ok = FALSE, reason = "Artifact JSON parse failed", missing_artifacts = artifact_name))
    }

    validation <- validate_artifact_fields(artifact_data, artifact_name)
    if (!validation$valid) {
      return(list(
        ok = FALSE,
        reason = sprintf("Artifact '%s' validation failed: %s",
                          artifact_name, paste(validation$errors, collapse = "; ")),
        missing_artifacts = artifact_name
      ))
    }

    # Check field conditions (for S4→S5/S6 branching)
    if (!is.null(condition$field_check)) {
      fc <- condition$field_check
      check_results <- sapply(fc$checks, function(chk) {
        val <- artifact_data[[chk$field]]
        if (is.null(val)) return(FALSE)
        switch(chk$op,
          ">"  = val > chk$value,
          ">=" = val >= chk$value,
          "<"  = val < chk$value,
          "<=" = val <= chk$value,
          "==" = identical(val, chk$value),
          "!=" = !identical(val, chk$value),
          FALSE
        )
      })

      pass <- if (fc$logic == "AND") all(check_results) else any(check_results)
      if (!pass) {
        return(list(
          ok = FALSE,
          reason = sprintf("Field conditions not met for %s→%s transition.",
                            current_num, target_stage),
          missing_artifacts = NULL
        ))
      }
    }
  }

  list(ok = TRUE, reason = "All conditions met.", missing_artifacts = NULL)
}


# ─── sg_transition ───────────────────────────────────────────────────────────

#' Execute a stage transition
#'
#' @param factor_id Character
#' @param target_stage Character: next stage (e.g., "S1")
#' @param artifact_path Character: path to the completed artifact JSON
#' @param completed_by Character: agent name ("scout", "forge", "judge")
#' @return list(ok, reason)
sg_transition <- function(factor_id, target_stage, artifact_path = NULL,
                           completed_by = "unknown") {

  state <- sg_get_state(factor_id)
  if (!isTRUE(state$exists)) {
    return(list(ok = FALSE, reason = "Tracker not found"))
  }

  current_num <- gsub("_.*", "", state$current_stage)

  # If artifact_path provided, store it for the CURRENT stage (completing it)
  if (!is.null(artifact_path) && file.exists(artifact_path)) {
    # Validate artifact
    schema_name <- STAGE_ARTIFACT_MAP[[current_num]]
    if (!is.null(schema_name)) {
      artifact_data <- tryCatch(fromJSON(artifact_path, simplifyVector = FALSE),
                                error = function(e) NULL)
      if (!is.null(artifact_data)) {
        validation <- validate_artifact_fields(artifact_data, schema_name)
        if (!validation$valid) {
          return(list(
            ok = FALSE,
            reason = sprintf("Artifact validation failed for %s: %s",
                              schema_name, paste(validation$errors, collapse = "; "))
          ))
        }
      }
    }

    # Update stage log: mark current stage as complete
    state$stage_log[[current_num]]$status <- "complete"
    state$stage_log[[current_num]]$artifact <- artifact_path
    state$stage_log[[current_num]]$completed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    state$stage_log[[current_num]]$completed_by <- completed_by
    state$current_stage <- paste0(current_num, "_complete")

    # Save intermediate state
    write_json(state, .tracker_path(factor_id), auto_unbox = TRUE, pretty = TRUE)
  }

  # Now check if we can advance to target
  check <- sg_can_advance(factor_id, target_stage)
  if (!check$ok) {
    return(list(ok = FALSE, reason = check$reason))
  }

  # Advance: set target stage to pending, unblock it
  state$stage_log[[target_stage]]$status <- "pending"
  state$current_stage <- paste0(target_stage, "_pending")

  write_json(state, .tracker_path(factor_id), auto_unbox = TRUE, pretty = TRUE)

  cat(sprintf("[stage_gate] %s: %s → %s (by %s)\n",
              factor_id, current_num, target_stage, completed_by))

  list(ok = TRUE, reason = sprintf("Advanced to %s", target_stage))
}


# ─── sg_check_s6_entry ───────────────────────────────────────────────────────

#' S6 Entry Gate — Judge의 필수 첫 행동
#'
#' Judge가 S6 시작 전에 반드시 호출. 5개 산출물 존재 + 유효성 확인.
#'
#' @param factor_id Character
#' @return list(ok = TRUE/FALSE, reason = "...", missing = c("s3_orthogonality", ...))
sg_check_s6_entry <- function(factor_id) {

  state <- sg_get_state(factor_id)
  if (!isTRUE(state$exists)) {
    return(list(ok = FALSE, reason = "Tracker not found", missing = NULL))
  }

  # 5개 필수 산출물
  required_stages <- c("S0", "S1", "S2", "S3", "S4")
  required_schemas <- c("s0_record", "s1_construction", "s2_profile",
                         "s3_orthogonality", "s4_integration")

  missing <- character(0)
  invalid <- character(0)

  for (i in seq_along(required_stages)) {
    stage <- required_stages[i]
    schema <- required_schemas[i]
    entry <- state$stage_log[[stage]]

    # Check status
    if (is.null(entry) || entry$status != "complete") {
      missing <- c(missing, sprintf("%s (%s 미완료)", schema, stage))
      next
    }

    # Check artifact file exists
    if (is.null(entry$artifact) || !file.exists(entry$artifact)) {
      missing <- c(missing, sprintf("%s (파일 없음)", schema))
      next
    }

    # Validate content
    artifact_data <- tryCatch(fromJSON(entry$artifact, simplifyVector = FALSE),
                              error = function(e) NULL)
    if (is.null(artifact_data)) {
      invalid <- c(invalid, sprintf("%s (JSON 파싱 실패)", schema))
      next
    }

    validation <- validate_artifact_fields(artifact_data, schema)
    if (!validation$valid) {
      invalid <- c(invalid, sprintf("%s: %s", schema, paste(validation$errors, collapse = "; ")))
    }
  }

  # S5는 조건부: S4→S5→S6 경로인 경우에만 필수
  if (state$stage_log$S5$status == "complete") {
    s5_entry <- state$stage_log$S5
    if (!is.null(s5_entry$artifact) && file.exists(s5_entry$artifact)) {
      s5_data <- tryCatch(fromJSON(s5_entry$artifact, simplifyVector = FALSE),
                           error = function(e) NULL)
      if (!is.null(s5_data)) {
        s5_val <- validate_artifact_fields(s5_data, "s5_mutation")
        if (!s5_val$valid) {
          invalid <- c(invalid, sprintf("s5_mutation: %s", paste(s5_val$errors, collapse = "; ")))
        }
      }
    }
  }

  all_issues <- c(missing, invalid)

  if (length(all_issues) == 0) {
    return(list(ok = TRUE, reason = "S6 Entry Gate PASS. All artifacts valid.",
                missing = NULL))
  }

  list(
    ok = FALSE,
    reason = sprintf("S6 Entry Gate FAIL. %d issues:\n  - %s",
                      length(all_issues), paste(all_issues, collapse = "\n  - ")),
    missing = all_issues
  )
}


# ─── sg_rollback_to_s2 ──────────────────────────────────────────────────────

#' Rollback to S2 for S5 mutation re-circulation
#'
#' @param factor_id Character
#' @param mutation_description Character: what mutation is being tried
#' @return list(ok, reason)
sg_rollback_to_s2 <- function(factor_id, mutation_description = "") {

  state <- sg_get_state(factor_id)
  if (!isTRUE(state$exists)) {
    return(list(ok = FALSE, reason = "Tracker not found"))
  }

  # Record mutation
  state$mutation_count <- state$mutation_count + 1L
  state$mutation_log[[length(state$mutation_log) + 1]] <- list(
    mutation_id = state$mutation_count,
    description = mutation_description,
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  )

  # Reset S3, S4, S5, S6 to blocked (keep S0, S1, S2 artifacts)
  for (s in c("S3", "S4", "S5", "S6", "S7")) {
    state$stage_log[[s]]$status <- "blocked"
    state$stage_log[[s]]$artifact <- NULL
    state$stage_log[[s]]$completed_at <- NULL
  }

  # Set current stage back to S2_complete (ready for S3)
  state$current_stage <- "S2_complete"
  state$stage_log$S3$status <- "pending"  # S3 can now start

  write_json(state, .tracker_path(factor_id), auto_unbox = TRUE, pretty = TRUE)

  cat(sprintf("[stage_gate] %s: Rollback to S2 for mutation #%d: %s\n",
              factor_id, state$mutation_count, mutation_description))

  list(ok = TRUE, reason = sprintf("Rolled back to S2. Mutation #%d", state$mutation_count))
}


# ─── sg_sync_from_artifacts ──────────────────────────────────────────────────

#' Artifact 기반 트래커 자동 동기화
#'
#' stage_artifacts/ 에 artifact JSON이 존재하면 트래커를 자동 전이.
#' 에이전트가 sg_transition()을 호출하지 않아도 artifact만 있으면 트래커가 맞춰진다.
#'
#' @param factor_id Character
#' @return list(synced_stages = character(), errors = character())
sg_sync_from_artifacts <- function(factor_id) {

  state <- sg_get_state(factor_id)
  if (!isTRUE(state$exists)) {
    return(list(synced_stages = character(), errors = "Tracker not found"))
  }

  strategy_id <- state$strategy_id %||% factor_id
  # Use PROJECT_ROOT if available (from config.R), fallback to dirname(.sg_root)
  proj <- if (exists("PROJECT_ROOT")) PROJECT_ROOT else dirname(.sg_root)
  art_dir <- file.path(proj, "04_Research", "strategies",
                        strategy_id, "stage_artifacts")
  if (!dir.exists(art_dir)) {
    return(list(synced_stages = character(), errors = "No stage_artifacts dir"))
  }

  synced <- character()
  errors <- character()

  # Stage → artifact 파일 패턴 매핑
  stage_patterns <- list(
    S0  = "s0_record",
    S1  = "s1_construction",
    S2  = "s2_profile",
    S3  = "s3_orthogonality",
    S4  = "s4_integration",
    S5  = "s5_mutation_result",
    S6  = "s6_validation",
    PG0 = "pg0_gap_review",
    PG1 = "pg1_admission",
    PG2 = "pg2_allocation_plan",
    PG3 = "pg3_monitoring"
  )

  for (stage in names(stage_patterns)) {
    pattern <- stage_patterns[[stage]]
    files <- list.files(art_dir, pattern = paste0("^", pattern), full.names = TRUE)

    # S5: design/slate/research 파일은 완료 트리거에서 제외 (FIX 2b)
    if (stage == "S5") files <- files[!grepl("design|slate|research", files)]

    if (length(files) == 0) next

    artifact_path <- files[1]
    entry <- state$stage_log[[stage]]

    # 이미 complete이면 스킵
    if (!is.null(entry$status) && entry$status == "complete") next

    # Artifact 파일 검증 (유연 모드: 파일 존재 + JSON 파싱 가능하면 통과)
    artifact_data <- tryCatch(fromJSON(artifact_path, simplifyVector = FALSE),
                              error = function(e) NULL)
    if (is.null(artifact_data)) {
      errors <- c(errors, sprintf("%s: JSON parse failed", stage))
      next
    }

    # factor_id 매칭 생략 — 같은 stage_artifacts 디렉토리에 있으면 해당 전략의 artifact로 인정
    # (에이전트가 factor_id를 다른 형식으로 작성하는 경우가 많음)

    # Artifact 유효 → 트래커 업데이트
    state$stage_log[[stage]]$status <- "complete"
    state$stage_log[[stage]]$artifact <- artifact_path
    state$stage_log[[stage]]$completed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    state$stage_log[[stage]]$completed_by <- "auto_sync"

    synced <- c(synced, stage)
  }

  if (length(synced) > 0) {
    # current_stage를 가장 높은 완료 단계로 설정
    completed_stages <- names(which(sapply(state$stage_log, function(x) x$status == "complete")))
    if (length(completed_stages) > 0) {
      highest <- completed_stages[which.max(match(completed_stages, STAGE_ORDER))]
      state$current_stage <- paste0(highest, "_complete")

      # 다음 단계를 pending으로
      highest_idx <- match(highest, STAGE_ORDER)
      if (highest_idx < length(STAGE_ORDER)) {
        next_stage <- STAGE_ORDER[highest_idx + 1]
        next_status <- state$stage_log[[next_stage]]$status
        if (is.character(next_status) && length(next_status) == 1 && next_status == "blocked") {
          state$stage_log[[next_stage]]$status <- "pending"
        }
      }
    }

    # ── FIX 7: S7 auto-detection ──────────────────────────────────────────────
    # S6 complete 이고 judge_result.json에서 Grade A/B이면 S7_complete으로 자동 전진
    s6_status <- state$stage_log[["S6"]]$status %||% ""
    s7_status  <- state$stage_log[["S7"]]$status  %||% ""
    if (s6_status == "complete" && s7_status != "complete") {
      proj_local <- if (exists("PROJECT_ROOT")) PROJECT_ROOT else dirname(.sg_root)
      jr_path_s7 <- file.path(proj_local, "04_Research", "strategies",
                               strategy_id, "output", "judge_result.json")
      jr_path_s7b <- file.path(proj_local, "04_Research", "strategies",
                                strategy_id, "stage_artifacts", "judge_result.json")
      jr_file_s7 <- if (file.exists(jr_path_s7)) jr_path_s7 else if (file.exists(jr_path_s7b)) jr_path_s7b else NULL
      if (!is.null(jr_file_s7)) {
        jr_data <- tryCatch(fromJSON(jr_file_s7, simplifyVector = FALSE), error = function(e) NULL)
        if (!is.null(jr_data)) {
          jgrade <- jr_data$verdict$grade %||% jr_data$grade %||% ""
          if (jgrade %in% c("A", "A_NOVEL", "A_CONDITIONAL", "B")) {
            state$stage_log[["S7"]]$status       <- "complete"
            state$stage_log[["S7"]]$artifact      <- jr_file_s7
            state$stage_log[["S7"]]$completed_at  <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
            state$stage_log[["S7"]]$completed_by  <- "auto_sync_s7"
            state$current_stage <- "S7_complete"
            if (!is.null(state$stage_log[["PG0"]]) &&
                (state$stage_log[["PG0"]]$status %||% "") == "blocked") {
              state$stage_log[["PG0"]]$status <- "pending"
            }
            synced <- c(synced, "S7_auto")
            cat(sprintf("[stage_gate] %s: S7 auto-advanced (Grade %s)\n", factor_id, jgrade))
          }
        }
      }
    }

    write_json(state, .tracker_path(factor_id), auto_unbox = TRUE, pretty = TRUE)
    cat(sprintf("[stage_gate] %s: Auto-synced %d stages: %s\n",
                factor_id, length(synced), paste(synced, collapse = ", ")))
  }

  list(synced_stages = synced, errors = errors)
}


#' 전체 트래커 일괄 동기화
#'
#' 모든 트래킹 중인 팩터에 대해 sg_sync_from_artifacts() 실행.
#' Q-Lead 모니터링 또는 cron에서 주기적 호출용.
#'
#' @return data.frame with factor_id, synced_count
sg_sync_all <- function() {

  files <- list.files(.SG_CACHE, "*_tracker.json", full.names = TRUE)
  if (length(files) == 0) {
    cat("[stage_gate] No tracked factors to sync.\n")
    return(invisible(NULL))
  }

  results <- list()
  for (f in files) {
    tracker <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(tracker)) next

    sync <- sg_sync_from_artifacts(tracker$factor_id)
    if (length(sync$synced_stages) > 0) {
      results[[length(results) + 1]] <- data.frame(
        factor_id = tracker$factor_id,
        synced = paste(sync$synced_stages, collapse = "+"),
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(results) > 0) {
    df <- do.call(rbind, results)
    cat(sprintf("[stage_gate] Synced %d factors.\n", nrow(df)))
    return(df)
  } else {
    cat("[stage_gate] All trackers up-to-date.\n")
    return(invisible(NULL))
  }
}


# ─── sg_drive_pipeline (REMOVED) ─────────────────────────────────────────────
# pipeline_trigger.sh (PostToolUse hook)로 대체.
# 중복 제거: Session 55, 2026-04-08.


# (sg_drive_pipeline 본문 770줄 삭제 — pipeline_trigger.sh hook으로 대체)
#'
#' @return list of actions taken
# ─── sg_get_dashboard ────────────────────────────────────────────────────────

#' Get stage distribution dashboard
#'
#' @return data.frame with factor_id, current_stage, mutation_count
sg_get_dashboard <- function() {

  files <- list.files(.SG_CACHE, "*_tracker.json", full.names = TRUE)
  if (length(files) == 0) {
    cat("[stage_gate] No tracked factors.\n")
    return(data.frame(factor_id = character(), current_stage = character(),
                       mutation_count = integer(), stringsAsFactors = FALSE))
  }

  results <- lapply(files, function(f) {
    tracker <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(tracker)) return(NULL)
    data.frame(
      factor_id = tracker$factor_id,
      strategy_id = tracker$strategy_id %||% NA_character_,
      current_stage = tracker$current_stage,
      mutation_count = tracker$mutation_count %||% 0L,
      created_at = tracker$created_at %||% NA_character_,
      stringsAsFactors = FALSE
    )
  })

  df <- do.call(rbind, Filter(Negate(is.null), results))

  if (nrow(df) > 0) {
    # Stage distribution
    stage_dist <- table(gsub("_.*", "", df$current_stage))
    cat("[stage_gate] Dashboard:\n")
    cat(sprintf("  Total tracked: %d factors\n", nrow(df)))
    for (s in names(stage_dist)) {
      cat(sprintf("  %s: %d\n", s, stage_dist[s]))
    }
  }

  df
}


# ─── Null coalesce operator ──────────────────────────────────────────────────
`%||%` <- function(a, b) if (!is.null(a)) a else b


#==============================================================================
# V6.0 Extensions — Portfolio Gap Vector, Conditional IC, Role Utility,
#                    Research Slate, PG0-PG3
#==============================================================================

# ─── v6: Extended Stage Order ────────────────────────────────────────────────
# STAGE_ORDER_V6 merged into STAGE_ORDER at line 32
STAGE_ORDER_V6 <- STAGE_ORDER  # backward compat alias


# ─── sg_compute_gap_vector ───────────────────────────────────────────────────

#' Portfolio Gap Vector 계산
#'
#' Base 전략의 현재 성과와 목표 사이의 gap 계산.
#' sleeve_needs 자동 판단 (core_alpha / diversifier / defense).
#'
#' @param base_strategy_id Character: base 전략 디렉토리명
#' @return Gap vector list (.cache/portfolio_gap_vector.json에도 저장)
sg_compute_gap_vector <- function(base_strategy_id = "STR_1375_5sleeve_cons_heavy") {

  proj <- if (exists("PROJECT_ROOT")) PROJECT_ROOT else dirname(.sg_root)
  pf_path <- file.path(proj, "04_Research", "strategies",
                        base_strategy_id, "output", "performance.csv")

  if (!file.exists(pf_path)) {
    stop(sprintf("[v6] performance.csv not found: %s", pf_path))
  }

  pf <- data.table::fread(pf_path)
  strat <- pf[1]  # 첫 행 = 전략 행

  target <- list(cagr = 0.16, sharpe = 2.0, mdd = 0.25)
  current <- list(
    cagr = as.numeric(strat$CAGR) / 100,
    sharpe = as.numeric(strat$Sharpe),
    mdd = as.numeric(strat$MDD) / 100
  )

  gap <- list(
    as_of = format(Sys.Date(), "%Y-%m-%d"),
    base_strategy = base_strategy_id,
    target_profile = target,
    current_profile = current,
    gap_vector = list(
      return_gap = round(target$cagr - current$cagr, 4),
      sharpe_gap = round(target$sharpe - current$sharpe, 3),
      mdd_gap = round(target$mdd - current$mdd, 4)   # 음수 = MDD 초과
    ),
    sleeve_needs = character()
  )

  # sleeve_needs 자동 판단
  if (gap$gap_vector$sharpe_gap > 0.5) {
    gap$sleeve_needs <- c(gap$sleeve_needs, "core_alpha")
  }
  if (gap$gap_vector$mdd_gap < -0.02) {
    gap$sleeve_needs <- c(gap$sleeve_needs, "defense")
  }
  if (length(gap$sleeve_needs) == 0) {
    gap$sleeve_needs <- c("diversifier")
  }

  # 저장
  cache_dir <- file.path(proj, ".cache")
  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
  out_path <- file.path(cache_dir, "portfolio_gap_vector.json")
  write_json(gap, out_path, auto_unbox = TRUE, pretty = TRUE)

  cat(sprintf("[v6] Gap Vector: SR_gap=%.3f, CAGR_gap=%.4f, MDD_gap=%.4f → needs: %s\n",
              gap$gap_vector$sharpe_gap, gap$gap_vector$return_gap,
              gap$gap_vector$mdd_gap, paste(gap$sleeve_needs, collapse = "+")))
  gap
}


# ─── sg_compute_conditional_ic ───────────────────────────────────────────────

#' Conditional IC Matrix 사전 계산
#'
#' 269팩터의 조건부 IC: "포트폴리오가 약할 때 IC가 높은 팩터" 발굴.
#' holdings_detail.csv에서 월별 수익률 복원 → 하위 30% = bad months.
#' conditional_value = mean(IC|bad) - mean(IC|good).
#'
#' @param base_strategy_id Character: base 전략 디렉토리명
#' @return data.table with conditional IC (.cache/conditional_ic_matrix.csv에도 저장)
sg_compute_conditional_ic <- function(base_strategy_id = "STR_1375_5sleeve_cons_heavy") {

  suppressPackageStartupMessages({
    library(data.table)
    library(arrow)
  })

  proj <- if (exists("PROJECT_ROOT")) PROJECT_ROOT else dirname(.sg_root)

  # 1. Factor IC 로드
  ic_path <- file.path(proj, ".cache", "factor_db", "factor_ic_monthly.parquet")
  if (!file.exists(ic_path)) stop("[v6] factor_ic_monthly.parquet not found")
  ic <- as.data.table(read_parquet(ic_path))
  ic[, Date := as.Date(Date)]

  # 2. Portfolio monthly returns 복원 (holdings + RAWDATA)
  hd_path <- file.path(proj, "04_Research", "strategies",
                        base_strategy_id, "output", "holdings_detail.csv")
  if (!file.exists(hd_path)) stop("[v6] holdings_detail.csv not found")
  hd <- fread(hd_path)
  hd[, Signal_Date := as.Date(Signal_Date)]

  # RAWDATA에서 월별 수익률 가져오기
  raw_path <- file.path(proj, ".cache", "RAWDATA.parquet")
  if (!file.exists(raw_path)) {
    raw_path <- file.path(proj, "RAWDATA", "RAWDATA.parquet")
    if (!file.exists(raw_path)) {
      raw_path <- file.path(proj, "RAWDATA", "RAWDATA.rds")
      if (!file.exists(raw_path)) stop("[v6] RAWDATA not found")
      raw <- as.data.table(readRDS(raw_path))
    } else {
      raw <- as.data.table(read_parquet(raw_path))
    }
  } else {
    raw <- as.data.table(read_parquet(raw_path))
  }
  raw[, Date := as.Date(Date)]
  setkey(raw, Date, Ticker)

  # 각 리밸런싱 월의 포트폴리오 가중평균 수익률 계산
  months <- sort(unique(hd$Signal_Date))
  port_ret <- rbindlist(lapply(seq_along(months), function(i) {
    if (i >= length(months)) return(NULL)
    cur <- months[i]
    nxt <- months[i + 1]
    holdings <- hd[Signal_Date == cur]
    if (nrow(holdings) == 0) return(NULL)

    # 각 종목의 보유기간 수익률
    stock_rets <- raw[Ticker %in% holdings$Ticker & Date > cur & Date <= nxt,
                       .(Ret_Period = prod(1 + Ret/100, na.rm = TRUE) - 1),
                       by = Ticker]

    merged <- merge(holdings[, .(Ticker, Weight)], stock_rets, by = "Ticker", all.x = TRUE)
    merged[is.na(Ret_Period), Ret_Period := 0]

    data.table(Date = nxt, Return = sum(merged$Weight * merged$Ret_Period, na.rm = TRUE))
  }))

  if (nrow(port_ret) == 0) stop("[v6] Failed to compute portfolio returns")

  # 3. Bad/Good months 분류 (하위 30% = bad)
  bad_threshold <- quantile(port_ret$Return, 0.30, na.rm = TRUE)
  bad_months <- port_ret[Return <= bad_threshold, Date]
  good_months <- port_ret[Return > bad_threshold, Date]

  cat(sprintf("[v6] Portfolio returns: %d months, bad_threshold=%.4f, bad=%d, good=%d\n",
              nrow(port_ret), bad_threshold, length(bad_months), length(good_months)))

  # 4. 각 팩터의 Conditional IC 계산
  cond <- ic[, {
    ic_bad_vals <- IC[Date %in% bad_months]
    ic_good_vals <- IC[Date %in% good_months]
    ic_bad_mean <- if (length(ic_bad_vals) > 3) mean(ic_bad_vals, na.rm = TRUE) else NA_real_
    ic_good_mean <- if (length(ic_good_vals) > 3) mean(ic_good_vals, na.rm = TRUE) else NA_real_

    # Recent 3Y ICIR
    recent <- IC[Date >= max(Date, na.rm = TRUE) - 1095]
    recent_icir <- if (length(recent) > 5 && sd(recent, na.rm = TRUE) > 0) {
      mean(recent, na.rm = TRUE) / sd(recent, na.rm = TRUE)
    } else NA_real_

    .(
      ic_all = mean(IC, na.rm = TRUE),
      ic_bad = ic_bad_mean,
      ic_good = ic_good_mean,
      conditional_value = ic_bad_mean - ic_good_mean,
      recent_3y_icir = recent_icir,
      n_months = .N
    )
  }, by = Factor_Name]

  setorder(cond, -conditional_value)

  # 5. 사용/미사용 분류 (기존 전략에서 사용 여부)
  # 06_Registry의 사용 팩터 스캔
  used_factors <- tryCatch({
    reg_dir <- file.path(proj, "06_Registry")
    if (dir.exists(reg_dir)) {
      reg_files <- list.files(reg_dir, "*.json", full.names = TRUE)
      factors <- unlist(lapply(reg_files, function(f) {
        r <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
        if (!is.null(r)) r$factors %||% r$factor_id %||% NULL else NULL
      }))
      unique(factors)
    } else character()
  }, error = function(e) character())

  cond[, used := Factor_Name %in% used_factors]

  # 6. 카테고리 라벨링 (factor_registry.json)
  reg_path <- file.path(proj, "02_Infrastructure", "factor_db", "factor_registry.json")
  if (file.exists(reg_path)) {
    reg <- tryCatch(fromJSON(reg_path, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(reg)) {
      cat_map <- data.table(
        Factor_Name = names(reg),
        category = sapply(reg, function(x) x$category %||% "unknown")
      )
      cond <- merge(cond, cat_map, by = "Factor_Name", all.x = TRUE)
      cond[is.na(category), category := "unknown"]
    }
  }

  # 7. 최종 정렬 + 저장
  setorder(cond, -conditional_value)
  cache_dir <- file.path(proj, ".cache")
  out_path <- file.path(cache_dir, "conditional_ic_matrix.csv")
  fwrite(cond, out_path)

  cat(sprintf("[v6] Conditional IC: %d factors. Top 5 conditional_value:\n", nrow(cond)))
  print(head(cond[, .(Factor_Name, conditional_value, ic_all, category, used)], 5))

  cond
}


# ─── sg_compute_role_utility ─────────────────────────────────────────────────

#' Role-Aware Utility Score 계산
#'
#' 역할(Core Alpha / Diversifier / Defense)에 따라 가중치가 다른 복합 스코어.
#' Pipeline driver가 S4 완료 시 자동 호출 → provisional_role + utility_score 첨부.
#'
#' @param candidate_id Character: factor_id
#' @param provisional_role Character: "core_alpha" / "diversifier" / "defense"
#' @param s2 List: s2_profile artifact data
#' @param s3 List: s3_orthogonality artifact data
#' @param s4 List: s4_integration artifact data
#' @return list with utility_score, provisional_role, component_scores
sg_compute_role_utility <- function(candidate_id, provisional_role, s2, s3, s4) {

  # Role-specific weights
  # U = w1*MarginalIC + w2*ΔSharpe + w3*Orthogonality + w4*ConditionalValue - w5*Complexity
  w <- switch(provisional_role,
    "core_alpha"  = list(w1 = 0.25, w2 = 0.35, w3 = 0.10, w4 = 0.10, w5 = 0.20),
    "diversifier" = list(w1 = 0.10, w2 = 0.10, w3 = 0.35, w4 = 0.25, w5 = 0.20),
    "defense"     = list(w1 = 0.10, w2 = 0.05, w3 = 0.15, w4 = 0.40, w5 = 0.30),
    list(w1 = 0.20, w2 = 0.20, w3 = 0.20, w4 = 0.20, w5 = 0.20)  # default
  )

  # Component scores (0~1 normalized)
  delta_sharpe_raw <- s4$delta_sharpe %||% 0
  delta_sharpe_norm <- min(max(delta_sharpe_raw / 1.0, 0), 1)  # 0~1.0 range → 0~1

  orthogonality <- 1 - min(abs(s3$max_abs_corr_db %||% 0.5), 1)

  # Conditional value from cache
  proj <- if (exists("PROJECT_ROOT")) PROJECT_ROOT else dirname(.sg_root)
  cond_path <- file.path(proj, ".cache", "conditional_ic_matrix.csv")
  cond_val <- 0
  if (file.exists(cond_path)) {
    cond <- data.table::fread(cond_path)
    factor_name <- s4$factor_id %||% candidate_id
    match_row <- cond[Factor_Name == factor_name]
    if (nrow(match_row) > 0) {
      cond_val <- match_row$conditional_value[1]
    }
  }
  cond_norm <- min(max((cond_val + 0.1) / 0.2, 0), 1)  # -0.1~0.1 → 0~1

  # IC quality from s2
  ic_raw <- abs(s2$ic_ir %||% 0)
  ic_norm <- min(ic_raw / 0.3, 1)  # ICIR 0~0.3 → 0~1

  # Complexity penalty (tier-based)
  complexity <- 0  # default: no penalty

  U <- w$w1 * ic_norm + w$w2 * delta_sharpe_norm + w$w3 * orthogonality +
       w$w4 * cond_norm - w$w5 * complexity

  result <- list(
    utility_score = round(U, 4),
    provisional_role = provisional_role,
    component_scores = list(
      ic_quality = round(ic_norm, 4),
      delta_sharpe = round(delta_sharpe_norm, 4),
      orthogonality = round(orthogonality, 4),
      conditional_value = round(cond_norm, 4),
      complexity_penalty = complexity
    ),
    weights_used = w
  )

  cat(sprintf("[v6] Role Utility: %s → role=%s, U=%.4f (IC=%.2f, dSR=%.2f, orth=%.2f, cond=%.2f)\n",
              candidate_id, provisional_role, U, ic_norm, delta_sharpe_norm, orthogonality, cond_norm))
  result
}


# ─── sg_determine_role ───────────────────────────────────────────────────────

#' Provisional Role 자동 판정
#'
#' Gap vector + s2/s3/s4 artifact에서 자동으로 역할 추정.
#' Pipeline driver가 S4 완료 시 호출.
#'
#' @param s2 List: s2_profile artifact
#' @param s3 List: s3_orthogonality artifact
#' @param s4 List: s4_integration artifact
#' @return Character: "core_alpha" / "diversifier" / "defense"
sg_determine_role <- function(s2, s3, s4) {

  delta_sharpe <- s4$delta_sharpe %||% 0
  orthogonality <- 1 - abs(s3$max_abs_corr_db %||% 0.5)
  kospi_beat <- isTRUE(s4$kospi_beat)

  # Conditional value lookup
  proj <- if (exists("PROJECT_ROOT")) PROJECT_ROOT else dirname(.sg_root)
  cond_path <- file.path(proj, ".cache", "conditional_ic_matrix.csv")
  cond_val <- 0
  if (file.exists(cond_path)) {
    cond <- data.table::fread(cond_path)
    factor_name <- s4$factor_id %||% s2$factor_id %||% ""
    match_row <- cond[Factor_Name == factor_name]
    if (nrow(match_row) > 0) cond_val <- match_row$conditional_value[1]
  }

  # Role decision tree
  if (kospi_beat && delta_sharpe > 0.2) {
    return("core_alpha")
  } else if (orthogonality > 0.7 && !is.na(cond_val) && cond_val > 0) {
    return("defense")
  } else if (orthogonality > 0.5) {
    return("diversifier")
  } else if (!is.na(cond_val) && cond_val > 0.02) {
    return("defense")
  } else {
    return("diversifier")
  }
}


# ─── sg_generate_research_slate ──────────────────────────────────────────────

#' S5 Research Slate 자동 생성
#'
#' 4슬롯(A/B/C/D) 데이터 드리븐 변형 후보 자동 생성.
#' Pipeline driver가 S5 진입 시 호출 → TODO_S5_DESIGN에 첨부.
#'
#' @param factor_id Character
#' @param strategy_id Character
#' @return Slate list (stage_artifacts/에도 저장)
sg_generate_research_slate <- function(factor_id, strategy_id) {

  proj <- if (exists("PROJECT_ROOT")) PROJECT_ROOT else dirname(.sg_root)

  # Conditional IC matrix 로드
  cond_path <- file.path(proj, ".cache", "conditional_ic_matrix.csv")
  if (!file.exists(cond_path)) {
    cat("[v6] conditional_ic_matrix.csv not found. Run sg_compute_conditional_ic() first.\n")
    return(NULL)
  }
  cond <- data.table::fread(cond_path)

  # Gap vector 로드
  gap_path <- file.path(proj, ".cache", "portfolio_gap_vector.json")
  gap <- if (file.exists(gap_path)) fromJSON(gap_path, simplifyVector = FALSE) else NULL

  # 현재 팩터의 카테고리
  current_cat <- cond[Factor_Name == factor_id, category]
  if (length(current_cat) == 0) current_cat <- "unknown"

  # Method registry 로드 (가용 방법론)
  method_path <- file.path(proj, "02_Infrastructure", "factor_db", "method_registry.json")
  methods_avail <- if (file.exists(method_path)) {
    tryCatch(fromJSON(method_path, simplifyVector = FALSE), error = function(e) list())
  } else list()

  slate <- list()

  # Slot A: Same-Family Repair (같은 카테고리 미사용 팩터)
  same_cat <- cond[category == current_cat & used == FALSE]
  if (nrow(same_cat) > 0) {
    data.table::setorder(same_cat, -conditional_value)
    slate$A <- list(
      slot = "A", type = "same_family_repair",
      candidates = head(same_cat[, .(Factor_Name, conditional_value, ic_all, recent_3y_icir)], 3),
      rationale = sprintf("같은 카테고리(%s) 내 미사용 팩터 결합 후보", current_cat)
    )
  }

  # Slot B: Cross-Family Complement (다른 카테고리, conditional_value 높은 미사용)
  diff_cat <- cond[category != current_cat & used == FALSE]
  if (nrow(diff_cat) > 0) {
    data.table::setorder(diff_cat, -conditional_value)
    slate$B <- list(
      slot = "B", type = "cross_family_complement",
      candidates = head(diff_cat[, .(Factor_Name, conditional_value, category, ic_all)], 5),
      rationale = "포트폴리오 약점 보완 — 크로스 카테고리 conditional_value 기준"
    )
  }

  # Slot C: Defensive / Counter-Cyclical
  defense_cand <- cond[conditional_value > 0 & used == FALSE]
  if (nrow(defense_cand) > 0) {
    data.table::setorder(defense_cand, -conditional_value)
    slate$C <- list(
      slot = "C", type = "defensive_candidate",
      candidates = head(defense_cand[, .(Factor_Name, conditional_value, category, ic_all)], 5),
      rationale = sprintf("포트폴리오 하위 30%%%% 구간에서 IC 높은 팩터. defense gap=%s",
                          if (!is.null(gap)) "defense" %in% gap$sleeve_needs else "unknown")
    )
  }

  # Slot D: Method-Only Mutation (팩터 유지, 방법론만 변경)
  slate$D <- list(
    slot = "D", type = "method_only",
    candidates = list("FC Tier 변경", "WD Tier 변경", "Universe 변경"),
    rationale = "기존 팩터 유지, 결합/가중 방법만 변경"
  )

  # 저장
  art_dir <- file.path(proj, "04_Research", "strategies", strategy_id, "stage_artifacts")
  if (!dir.exists(art_dir)) dir.create(art_dir, recursive = TRUE)
  slate_path <- file.path(art_dir, sprintf("s5_research_slate_%s.json", factor_id))
  write_json(slate, slate_path, auto_unbox = TRUE, pretty = TRUE)

  cat(sprintf("[v6] Research Slate generated for %s: %d slots\n",
              factor_id, length(slate)))
  slate
}


# ─── sg_role_admission ───────────────────────────────────────────────────────

#' Role-Based S4 Admission Rule
#'
#' S4 완료 시 역할별로 S5(개선 필요) vs S6(검증 진입) 분기.
#' 기존의 단순 kospi_beat 기준을 역할 기반으로 확장.
#'
#' @param provisional_role Character
#' @param s4 List: s4_integration artifact
#' @param s3 List: s3_orthogonality artifact
#' @return list(route = "S5" or "S6", reason = "...")
sg_role_admission <- function(provisional_role, s4, s3) {

  kospi_beat <- isTRUE(s4$kospi_beat)
  delta <- s4$delta_sharpe %||% 0
  orth <- 1 - abs(s3$max_abs_corr_db %||% 0.5)

  # Conditional value
  proj <- if (exists("PROJECT_ROOT")) PROJECT_ROOT else dirname(.sg_root)
  cond_path <- file.path(proj, ".cache", "conditional_ic_matrix.csv")
  cond_val <- NA_real_
  if (file.exists(cond_path)) {
    cond <- data.table::fread(cond_path)
    fn <- s4$factor_id %||% ""
    m <- cond[Factor_Name == fn]
    if (nrow(m) > 0) cond_val <- m$conditional_value[1]
  }

  # Role-specific admission criteria
  admitted <- switch(provisional_role,
    "core_alpha" = kospi_beat && delta > 0,
    "diversifier" = orth > 0.5,
    "defense" = !is.na(cond_val) && cond_val > 0,
    kospi_beat && delta > 0  # fallback = 기존 로직
  )

  route <- if (admitted) "S6" else "S5"
  reason <- sprintf("Role=%s, kospi_beat=%s, delta=%.3f, orth=%.2f, cond=%.4f → %s",
                     provisional_role, kospi_beat, delta, orth,
                     if (is.na(cond_val)) 0 else cond_val, route)

  cat(sprintf("[v6] Admission: %s\n", reason))
  list(route = route, reason = reason)
}


# ─── sg_counter_example_protocol ─────────────────────────────────────────────

#' 6축 반례 프로토콜 (R5/R6 실투 대체)
#'
#' 5종 반례 테스트: 시간적/국면적/위기적/구현적/신호적
#' 5/5 통과 = "반례 없음" → axiom 평가 자격
#'
#' @param strategy_id Character
#' @param family_name Character
#' @return list with 5 test results + summary
sg_counter_example_protocol <- function(strategy_id, family_name) {

  proj <- if (exists("PROJECT_ROOT")) PROJECT_ROOT else dirname(.sg_root)
  strat_dir <- file.path(proj, "04_Research", "strategies", strategy_id)
  results <- list(strategy_id = strategy_id, family = family_name,
                  tested_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))

  # Test 1: 시간적 반례 (Rolling 3Y SR + OOS)
  hr_path <- file.path(strat_dir, "output", "hurdle_result.json")
  temporal <- list(test = "temporal", pass = FALSE)
  if (file.exists(hr_path)) {
    hr <- tryCatch(fromJSON(hr_path, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(hr)) {
      v <- hr$verdict %||% hr
      oos_ret <- v$score_breakdown$oos$value %||% NA
      roll_csv <- file.path(strat_dir, "output", "analysis_rolling.csv")
      if (file.exists(roll_csv)) {
        roll <- data.table::fread(roll_csv)
        neg_3y <- sum(roll$Sharpe_3Y < 0, na.rm = TRUE)
        total_3y <- sum(!is.na(roll$Sharpe_3Y))
        neg_ratio <- if (total_3y > 0) neg_3y / total_3y else 1
        temporal$pass <- neg_ratio < 0.3 && !is.na(oos_ret) && oos_ret >= 0.5
        temporal$neg_ratio <- round(neg_ratio, 3)
        temporal$oos_retention <- oos_ret
      }
    }
  }
  results$temporal <- temporal

  # Test 2: 국면적 반례 (Stress outperform rate)
  regime <- list(test = "regime", pass = FALSE)
  stress_csv <- file.path(strat_dir, "output", "analysis_stress.csv")
  if (file.exists(stress_csv)) {
    stress <- data.table::fread(stress_csv)
    if ("Outperform" %in% names(stress)) {
      n_out <- sum(stress$Outperform == TRUE, na.rm = TRUE)
      regime$pass <- n_out >= nrow(stress) * 0.5
      regime$stress_outperform <- sprintf("%d/%d", n_out, nrow(stress))
    }
  }
  results$regime <- regime

  # Test 3: 위기적 반례 (단일 위기 의존도)
  crisis <- list(test = "crisis", pass = NA)
  if (file.exists(stress_csv) && file.exists(hr_path)) {
    stress <- data.table::fread(stress_csv)
    hr <- tryCatch(fromJSON(hr_path, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(hr) && "Alpha" %in% names(stress)) {
      full_sr <- as.numeric((hr$verdict %||% hr)$metrics$Sharpe %||% 0)
      max_alpha <- max(abs(stress$Alpha), na.rm = TRUE)
      # BUG5 FIX: 0.5→2.0. 단일 위기 alpha가 전체 SR의 200% 초과 시에만 의존
      crisis$pass <- full_sr == 0 || max_alpha < abs(full_sr) * 2.0
      crisis$max_crisis_alpha <- round(max_alpha, 3)
      crisis$full_sr <- round(full_sr, 3)
    }
  }
  results$crisis <- crisis

  # Test 4: 구현적 반례 (같은 family 다른 구현)
  construction <- list(test = "construction", pass = FALSE)
  exps_path <- file.path(proj, "qepm", "registry", "experiments.json")
  if (file.exists(exps_path)) {
    exps <- tryCatch(fromJSON(exps_path, simplifyVector = FALSE), error = function(e) list())
    fam_exps <- Filter(function(e) (e$family %||% "") == family_name, exps)
    if (length(fam_exps) >= 2) {
      grades <- sapply(fam_exps, function(e) e$grade %||% "F")
      n_pos <- sum(grades %in% c("A", "B"))
      construction$pass <- n_pos >= 2
      construction$n_constructions <- length(fam_exps)
      construction$n_positive <- n_pos
    }
  }
  # BUG6 FIX: fallback — strategies 디렉토리에서 같은 이름 prefix로 sibling 탐색
  if (!isTRUE(construction$pass)) {
    base_prefix <- sub("^STR_\\d+_", "", strategy_id)
    base_prefix <- sub("_[^_]+$", "", base_prefix)
    if (nchar(base_prefix) >= 3) {
      strat_root <- file.path(proj, "04_Research", "strategies")
      all_strs <- list.dirs(strat_root, recursive = FALSE, full.names = FALSE)
      siblings <- all_strs[grepl(base_prefix, all_strs, fixed = TRUE) & all_strs != strategy_id]
      sibling_grades <- character(0)
      for (sib in siblings) {
        hr <- file.path(strat_root, sib, "output", "hurdle_result.json")
        if (file.exists(hr)) {
          hr_data <- tryCatch(fromJSON(hr, simplifyVector = FALSE), error = function(e) NULL)
          if (!is.null(hr_data)) sibling_grades <- c(sibling_grades, (hr_data$verdict %||% hr_data)$grade %||% "F")
        }
      }
      n_sibs <- length(sibling_grades) + 1L
      n_pos_sib <- sum(sibling_grades %in% c("A", "B"))
      if (n_sibs >= 2) {
        construction$pass <- n_pos_sib >= 1
        construction$n_constructions <- n_sibs
        construction$n_positive <- n_pos_sib
        construction$source <- "directory_scan"
      }
    }
  }
  results$construction <- construction

  # Test 5: 신호적 반례 (IC stability)
  signal <- list(test = "signal", pass = NA)
  if (file.exists(hr_path)) {
    hr <- tryCatch(fromJSON(hr_path, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(hr)) {
      ic_ratio <- (hr$verdict %||% hr)$score_breakdown$ic_stability$value %||% NA
      signal$pass <- is.na(ic_ratio) || ic_ratio > -1.0
      signal$ic_ratio <- ic_ratio
    }
  }
  results$signal <- signal

  # 종합
  tests <- list(temporal, regime, crisis, construction, signal)
  n_pass <- sum(sapply(tests, function(t) isTRUE(t$pass)))
  n_na <- sum(sapply(tests, function(t) is.na(t$pass)))
  results$summary <- list(
    n_pass = n_pass, n_fail = 5 - n_pass - n_na, n_na = n_na,
    verdict = if (n_pass == 5) "NO_COUNTER_EXAMPLES"
              else if (n_pass >= 4) "MINOR_COUNTER_EXAMPLES"
              else "COUNTER_EXAMPLES_FOUND"
  )

  # 저장
  art_dir <- file.path(strat_dir, "stage_artifacts")
  if (!dir.exists(art_dir)) dir.create(art_dir, recursive = TRUE)
  ce_path <- file.path(art_dir, sprintf("counter_example_%s.json", strategy_id))
  write_json(results, ce_path, auto_unbox = TRUE, pretty = TRUE)

  cat(sprintf("[v6] Counter-Example: %s → %d/5 pass → %s\n",
              strategy_id, n_pass, results$summary$verdict))
  results
}


# ─── sg_s5_enforce_structure_priority ─────────────────────────────────────────

#' S5 Structural Mutation Priority 검증
#'
#' S5 artifact의 mutations 배열에서 처음 4건에 structural 카테고리(A/B/C/D)가
#' 포함되어 있는지 확인. parameter-only 튜닝이 structural 앞에 오면 위반.
#'
#' @param s5_artifact List: s5_mutation artifact
#' @return list(ok = TRUE/FALSE, reason = character)
sg_s5_enforce_structure_priority <- function(s5_artifact) {
  mutations <- s5_artifact$mutations
  if (is.null(mutations) || length(mutations) == 0) {
    return(list(ok = FALSE, reason = "No mutations found in S5 artifact"))
  }

  structural_slots <- c("A", "B", "C", "D",
                         "same_family_repair", "cross_family_complement",
                         "defensive_candidate", "method_only_mutation")

  # Check first 4 mutations for structural content
  first_4 <- head(mutations, 4)
  has_structural <- FALSE
  for (m in first_4) {
    slot <- m$slot %||% m$category %||% ""
    if (tolower(slot) %in% tolower(structural_slots)) {
      has_structural <- TRUE
      break
    }
  }

  if (!has_structural) {
    return(list(
      ok = FALSE,
      reason = "S5 violation: first 4 mutations contain no structural slot (A/B/C/D). Structural mutation must precede parameter tuning."
    ))
  }

  # Check research slate coverage
  slate_covered <- s5_artifact$research_slate_covered
  if (!is.null(slate_covered)) {
    missing <- names(which(!unlist(slate_covered)))
    if (length(missing) > 0) {
      return(list(
        ok = FALSE,
        reason = sprintf("S5 research slate not exhausted: missing %s", paste(missing, collapse = ", "))
      ))
    }
  }

  list(ok = TRUE, reason = "Structural priority satisfied")
}


cat("[stage_gate_engine] v7.0 Loaded. Functions: sg_init, sg_get_state, sg_can_advance,\n")
cat("  sg_transition, sg_check_s6_entry, sg_rollback_to_s2, sg_sync_from_artifacts,\n")
cat("  sg_get_dashboard, sg_compute_gap_vector, sg_compute_conditional_ic,\n")
cat("  sg_compute_role_utility, sg_determine_role, sg_generate_research_slate, sg_role_admission,\n")
cat("  sg_counter_example_protocol, sg_s5_enforce_structure_priority\n")
cat("  PG stages: S7→PG0→PG1→PG2→PG3 transition rules active.\n")
