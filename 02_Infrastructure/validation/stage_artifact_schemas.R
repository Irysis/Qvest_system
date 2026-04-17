#==============================================================================
# Stage Artifact Schemas — Factor Research Process v4.0
# stage_artifact_schemas.R
#
# Defines required fields, types, and constraints for each S-stage artifact.
# Used by stage_gate_engine.R to validate artifacts before stage transitions.
#==============================================================================

# ─── Schema Definitions ───────────────────────────────────────────────────────

ARTIFACT_SCHEMAS <- list(

  # S0: Idea Record (Scout)
  s0_record = list(
    required = c("factor_id", "hypothesis", "economic_rationale", "prior_art",
                  "source_reference", "expected_orthogonality"),
    types = list(
      factor_id = "character",
      hypothesis = "character",
      economic_rationale = "character",
      prior_art = "character",
      source_reference = "character",
      expected_orthogonality = "character"
    ),
    constraints = list(
      prior_art = c("Existing", "Variant", "Novel"),
      hypothesis = list(min_length = 10),        # 빈 문자열 방지
      economic_rationale = list(min_length = 10)  # 빈 문자열 방지
    )
  ),

  # S1: Factor Construction (Forge)
  s1_construction = list(
    required = c("factor_id", "signal_file", "coverage", "period", "pit_log"),
    types = list(
      factor_id = "character",
      signal_file = "character",
      coverage = "numeric",
      period = "character"
    ),
    constraints = list(
      coverage = list(min = 1)
    ),
    nested_required = list(
      pit_log = c("data_dates_verified", "rolling_window_expanding_only",
                   "zscore_historical_only", "connector_api_used")
    )
  ),

  # S2: Standalone Profile (Forge)
  s2_profile = list(
    required = c("factor_id", "ic_ir", "t_stat", "tag", "monotonicity",
                  "turnover", "quintile_spread"),
    types = list(
      factor_id = "character",
      ic_ir = "numeric",
      t_stat = "numeric",
      tag = "character",
      monotonicity = "numeric",
      turnover = "numeric",
      quintile_spread = "numeric"
    ),
    constraints = list(
      tag = c("Strong", "Moderate", "Weak"),
      ic_ir = list(min = -5, max = 5),
      monotonicity = list(min = 0, max = 1)
    )
  ),

  # S3: Orthogonality Scan (Scout)
  s3_orthogonality = list(
    required = c("factor_id", "max_abs_corr_db", "most_correlated_factor",
                  "independence_class", "value_matrix_cell", "n_compared",
                  "computed_date"),
    types = list(
      factor_id = "character",
      max_abs_corr_db = "numeric",
      most_correlated_factor = "character",
      independence_class = "character",
      value_matrix_cell = "character",
      n_compared = "numeric",
      computed_date = "character"
    ),
    constraints = list(
      independence_class = c("independent", "partial", "redundant"),
      max_abs_corr_db = list(min = 0, max = 1),
      n_compared = list(min = 10)  # 최소 10개 팩터와 비교
    )
  ),

  # S4: Integration Test (Forge)
  s4_integration = list(
    required = c("factor_id", "base_portfolio", "base_sharpe", "extended_sharpe",
                  "delta_sharpe", "kospi_beat", "best_combination", "best_weighting",
                  "methods_tested"),
    types = list(
      factor_id = "character",
      base_portfolio = "character",
      base_sharpe = "numeric",
      extended_sharpe = "numeric",
      delta_sharpe = "numeric",
      kospi_beat = "logical",
      best_combination = "character",
      best_weighting = "character"
    ),
    constraints = list(
      base_portfolio = c("KOSPI", "factor_pool"),
      delta_sharpe = list(min = -10, max = 10)
    ),
    list_required = list(
      methods_tested = c("combination", "weight", "sharpe", "kospi_beat")
    )
  ),

  # S5: Mutation Lab (Forge) — v7: 3-Axis Parallel + Synthesis
  s5_mutation = list(
    required = c("factor_id", "mutations_attempted", "checklist_exhausted",
                  "f_category_count", "mutations", "synthesis_tested"),
    types = list(
      factor_id = "character",
      mutations_attempted = "numeric",
      checklist_exhausted = "logical",
      f_category_count = "numeric",
      synthesis_tested = "logical"
    ),
    constraints = list(
      mutations_attempted = list(min = 9),    # 최소 9개 변형
      f_category_count = list(min = 2)        # F 카테고리 최소 2개
    ),
    list_required = list(
      mutations = c("category", "description", "result_delta_sharpe")
    )
  ),

  # S6: Statistical Validation (Judge)
  # v53 확장: schema_version == "v53" 시만 추가 검증 (backward-compat)
  s6_validation = list(
    required = c("factor_id", "gates", "verdict", "pit_audit",
                  "complexity_check", "process_audit"),
    types = list(
      factor_id = "character"
    ),
    nested_required = list(
      verdict = c("grade", "pass", "disposition"),
      pit_audit = c("clean", "violations_found"),
      complexity_check = c("tier_fc", "tier_wd", "is_oos_gap", "baseline_exists")
    ),
    # ── v53 Sprint 2 S2.4: Grade 객관화 (opt-in 스키마) ──
    # schema_version="v53" 필드 존재 시만 추가 검증. 기존 130+ artifact는 영향 없음.
    v53_conditional = list(
      trigger_field = "schema_version",
      trigger_value = "v53",
      additional_required = c("hurdle_embed", "hurdle_artifact_hash",
                              "grade_source"),
      nested_required_hurdle_embed = c("pass", "total_score", "grade"),
      grade_source_allowed = c("hurdle_gate", "judge_override"),
      override_rules = list(
        condition_field = "grade_source",
        condition_value_trigger = "judge_override",
        required_if_triggered = c("grade_override_reason",
                                   "override_approved_by"),
        min_reason_length = 500
      )
    )
  ),

  #===========================================================================
  # PG0-PG3: Portfolio Governor Artifact Schemas (v7)
  #===========================================================================

  # PG0: Portfolio Gap Diagnosis (Governor)
  pg0_gap_review = list(
    required = c("portfolio_id", "as_of_date", "current_profile", "target_profile",
                  "gap_vector", "sleeve_needs", "regime_state", "cold_start_phase"),
    types = list(
      portfolio_id = "character",
      as_of_date = "character",
      cold_start_phase = "numeric"
    ),
    nested_required = list(
      current_profile = c("cagr", "sharpe", "mdd"),
      target_profile = c("cagr", "sharpe", "mdd"),
      gap_vector = c("return_gap", "sharpe_gap", "mdd_gap"),
      regime_state = c("category", "score")
    ),
    constraints = list(
      cold_start_phase = list(min = 0, max = 3)
    )
  ),

  # PG1: Candidate Admission (Governor)
  pg1_admission = list(
    required = c("portfolio_id", "candidate_id", "validated_role",
                  "admission_decision", "anti_pattern_check", "loo_results"),
    types = list(
      portfolio_id = "character",
      candidate_id = "character",
      validated_role = "character",
      admission_decision = "character"
    ),
    constraints = list(
      validated_role = c("Validated_Core", "Validated_Diversifier", "Validated_Defense"),
      admission_decision = c("ADMIT", "DEFER", "REJECT")
    ),
    nested_required = list(
      anti_pattern_check = c("patterns_detected", "severity", "pass"),
      loo_results = c("crisis_pass", "regime_pass", "subperiod_pass")
    )
  ),

  # PG2: Allocation Plan (Governor)
  pg2_allocation_plan = list(
    required = c("portfolio_id", "allocation_method", "sleeve_weights",
                  "rebalance_plan", "regime_overlay", "pit_lag_verified"),
    types = list(
      portfolio_id = "character",
      allocation_method = "character",
      pit_lag_verified = "logical"
    ),
    constraints = list(
      allocation_method = c("equal_weight", "risk_parity", "min_variance",
                            "mean_variance", "regime_conditional")
    ),
    nested_required = list(
      rebalance_plan = c("frequency", "buffer_zone", "max_turnover")
    )
  ),

  # PG3: Live Monitoring (Governor)
  pg3_monitoring = list(
    required = c("portfolio_id", "monitoring_date", "nav_snapshot",
                  "drift_check", "regime_check", "alerts"),
    types = list(
      portfolio_id = "character",
      monitoring_date = "character"
    ),
    nested_required = list(
      nav_snapshot = c("total_nav", "daily_return", "mtd_return"),
      drift_check = c("max_drift", "rebalance_needed"),
      regime_check = c("current_regime", "regime_changed")
    )
  ),

  # S6 Enhanced: Role Honesty + LOO (v7)
  s6_validation_v7 = list(
    required = c("factor_id", "gates", "verdict", "pit_audit",
                  "complexity_check", "process_audit",
                  "role_honesty_audit", "loo_results"),
    types = list(
      factor_id = "character"
    ),
    nested_required = list(
      verdict = c("grade", "pass", "disposition", "role_validated"),
      pit_audit = c("clean", "violations_found"),
      complexity_check = c("tier_fc", "tier_wd", "is_oos_gap", "baseline_exists"),
      role_honesty_audit = c("honest", "declared_role", "detected_role"),
      loo_results = c("crisis_pass", "regime_pass", "subperiod_pass")
    )
  )
)


# ─── Validation Function ──────────────────────────────────────────────────────

#' Validate artifact fields against schema
#'
#' @param artifact List (parsed JSON)
#' @param schema_name Character: one of names(ARTIFACT_SCHEMAS)
#' @return list(valid = TRUE/FALSE, errors = character vector)
validate_artifact_fields <- function(artifact, schema_name) {

  if (!schema_name %in% names(ARTIFACT_SCHEMAS)) {
    return(list(valid = FALSE, errors = paste0("Unknown schema: ", schema_name)))
  }

  schema <- ARTIFACT_SCHEMAS[[schema_name]]
  errors <- character(0)

  # 1. Required fields
  missing <- setdiff(schema$required, names(artifact))
  if (length(missing) > 0) {
    errors <- c(errors, paste0("Missing required fields: ", paste(missing, collapse = ", ")))
  }

  # 2. Type checks (only for present fields)
  if (!is.null(schema$types)) {
    for (field in intersect(names(schema$types), names(artifact))) {
      expected_type <- schema$types[[field]]
      actual_value <- artifact[[field]]

      type_ok <- switch(expected_type,
        "character" = is.character(actual_value),
        "numeric"   = is.numeric(actual_value) || is.integer(actual_value),
        "logical"   = is.logical(actual_value),
        TRUE
      )

      if (!type_ok) {
        errors <- c(errors, sprintf("Field '%s': expected %s, got %s",
                                     field, expected_type, class(actual_value)[1]))
      }
    }
  }

  # 3. Value constraints
  if (!is.null(schema$constraints)) {
    for (field in intersect(names(schema$constraints), names(artifact))) {
      constraint <- schema$constraints[[field]]
      value <- artifact[[field]]

      if (is.character(constraint)) {
        # Enum constraint
        if (!value %in% constraint) {
          errors <- c(errors, sprintf("Field '%s': '%s' not in {%s}",
                                       field, value, paste(constraint, collapse = ", ")))
        }
      } else if (is.list(constraint)) {
        # Numeric range or string length
        if (!is.null(constraint$min) && is.numeric(value) && value < constraint$min) {
          errors <- c(errors, sprintf("Field '%s': %s < min %s", field, value, constraint$min))
        }
        if (!is.null(constraint$max) && is.numeric(value) && value > constraint$max) {
          errors <- c(errors, sprintf("Field '%s': %s > max %s", field, value, constraint$max))
        }
        if (!is.null(constraint$min_length) && is.character(value) && nchar(value) < constraint$min_length) {
          errors <- c(errors, sprintf("Field '%s': length %d < min %d",
                                       field, nchar(value), constraint$min_length))
        }
      }
    }
  }

  # 4-pre. v53 conditional (schema_version='v53' opt-in 검증)
  # 기존 130+ artifact (schema_version 없음)는 영향 없음.
  if (!is.null(schema$v53_conditional)) {
    cond <- schema$v53_conditional
    sv <- artifact[[cond$trigger_field]]
    if (!is.null(sv) && identical(as.character(sv), cond$trigger_value)) {
      # v53 필수 추가 필드
      v53_missing <- setdiff(cond$additional_required, names(artifact))
      if (length(v53_missing) > 0) {
        errors <- c(errors, sprintf("v53 schema missing required: %s",
                                     paste(v53_missing, collapse = ", ")))
      }
      # hurdle_embed nested 검증
      if ("hurdle_embed" %in% names(artifact) && is.list(artifact$hurdle_embed)) {
        he_missing <- setdiff(cond$nested_required_hurdle_embed,
                              names(artifact$hurdle_embed))
        if (length(he_missing) > 0) {
          errors <- c(errors, sprintf("hurdle_embed missing: %s",
                                       paste(he_missing, collapse = ", ")))
        }
      }
      # grade_source enum 검증
      gs <- artifact[[cond$override_rules$condition_field]]
      if (!is.null(gs) && !as.character(gs) %in% cond$grade_source_allowed) {
        errors <- c(errors, sprintf("grade_source '%s' not in {%s}",
                                     gs, paste(cond$grade_source_allowed,
                                                collapse = ", ")))
      }
      # override 조건부 필수 필드
      if (!is.null(gs) && identical(as.character(gs),
                                     cond$override_rules$condition_value_trigger)) {
        ov_missing <- setdiff(cond$override_rules$required_if_triggered,
                              names(artifact))
        if (length(ov_missing) > 0) {
          errors <- c(errors, sprintf("grade_source='judge_override' requires: %s",
                                       paste(ov_missing, collapse = ", ")))
        }
        # reason 길이 검증
        if ("grade_override_reason" %in% names(artifact)) {
          reason_len <- nchar(as.character(artifact$grade_override_reason))
          min_len <- cond$override_rules$min_reason_length
          if (reason_len < min_len) {
            errors <- c(errors, sprintf("grade_override_reason length %d < min %d",
                                         reason_len, min_len))
          }
        }
      }
    }
  }

  # 4. Nested required fields
  if (!is.null(schema$nested_required)) {
    for (parent in names(schema$nested_required)) {
      if (parent %in% names(artifact)) {
        child_fields <- schema$nested_required[[parent]]
        if (is.list(artifact[[parent]])) {
          child_missing <- setdiff(child_fields, names(artifact[[parent]]))
          if (length(child_missing) > 0) {
            errors <- c(errors, sprintf("Nested '%s' missing: %s",
                                         parent, paste(child_missing, collapse = ", ")))
          }
        }
      }
    }
  }

  # 5. List element required fields
  if (!is.null(schema$list_required)) {
    for (list_field in names(schema$list_required)) {
      if (list_field %in% names(artifact)) {
        items <- artifact[[list_field]]
        req_fields <- schema$list_required[[list_field]]
        if (is.list(items) && length(items) > 0) {
          first_item <- if (is.data.frame(items)) items else items[[1]]
          if (is.list(first_item) || is.data.frame(first_item)) {
            item_missing <- setdiff(req_fields, names(first_item))
            if (length(item_missing) > 0) {
              errors <- c(errors, sprintf("List '%s' items missing: %s",
                                           list_field, paste(item_missing, collapse = ", ")))
            }
          }
        }
      }
    }
  }

  list(valid = length(errors) == 0, errors = errors)
}


cat("[stage_artifact_schemas] Loaded. 12 artifact schemas defined (S0-S6 + PG0-PG3 + S6v7).\n")
