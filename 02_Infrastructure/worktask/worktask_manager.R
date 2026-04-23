#==============================================================================
# QEPM Work Task Manager — v1.0
# 2026-04-23 Session 69 Day 1
#
# 1 Work Task = QEPM Full Pipeline 1회 = Alpha → Risk → Optimizer → Forge → Judge → Governor
#
# Usage:
#   source("02_Infrastructure/worktask/worktask_manager.R")
#   wt_create(hypothesis = "Rate Hedge Defense", universe = "KOSPI200_KOSDAQ150_intersection")
#   wt_status("WT20260423_001")
#   wt_advance("WT20260423_001", "ALPHA_DONE")
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

WT_ROOT <- "qepm/mailbox/worktask"
WT_SCHEMA <- "02_Infrastructure/worktask/schema.json"
WT_CONSTRAINT_DEFAULTS <- "02_Infrastructure/worktask/constraint_defaults.json"

# ─── WT ID 생성 ──────────────────────────────────────────
wt_generate_id <- function() {
  today <- format(Sys.Date(), "%Y%m%d")
  existing <- list.files(WT_ROOT, pattern = sprintf("^WT%s_", today))
  seq <- length(existing) + 1
  sprintf("WT%s_%03d", today, seq)
}

# ─── WT 디렉토리 + request.json 생성 ─────────────────────
wt_create <- function(hypothesis_title,
                       hypothesis_description = "",
                       universe = "KOSPI200_KOSDAQ150_intersection",
                       benchmark = "KOSPI200_total_return",
                       as_of_date = Sys.Date(),
                       forecast_horizon = "1M",
                       rebalance_frequency = "monthly",
                       current_portfolio = "STR_1631_80_STR_1656_20",
                       override_constraints = NULL) {

  task_id <- wt_generate_id()
  wt_dir <- file.path(WT_ROOT, task_id)
  dir.create(wt_dir, recursive = TRUE, showWarnings = FALSE)

  # 기본 제약 로드
  defaults <- fromJSON(WT_CONSTRAINT_DEFAULTS, simplifyVector = FALSE)

  # Request 조립
  request <- list(
    task_id = task_id,
    hypothesis_title = hypothesis_title,
    hypothesis_description = hypothesis_description,
    as_of_date = format(as.Date(as_of_date), "%Y-%m-%d"),
    forecast_horizon = forecast_horizon,
    rebalance_frequency = rebalance_frequency,
    universe_definition = list(
      label = universe,
      liquidity_min_won_20d_avg = defaults$hard_constraints$liquidity_min_won_20d_avg,
      max_names_total = 500L
    ),
    benchmark_definition = benchmark,
    data_lag_rules = defaults$data_lag_rules_default,
    cost_model_version = defaults$cost_model$cost_model_version,
    current_portfolio = current_portfolio,
    hard_constraints = list(
      max_names = defaults$hard_constraints$max_names,
      weight_bounds = defaults$hard_constraints$weight_bounds,
      sector_active_weight_cap = defaults$hard_constraints$sector_active_weight_cap,
      liquidity_min_won_20d_avg = defaults$hard_constraints$liquidity_min_won_20d_avg
    ),
    soft_penalties = defaults$soft_penalties,
    capacity_limits = list(
      adv_multiplier = defaults$cost_model$capacity_adv_multiplier,
      capacity_max_aum_won = 100e9
    )
  )

  # Override constraints (사용자 정의)
  if (!is.null(override_constraints)) {
    for (k in names(override_constraints)) {
      request$hard_constraints[[k]] <- override_constraints[[k]]
    }
  }

  # request.json 저장
  write_json(request, file.path(wt_dir, "request.json"),
             pretty = TRUE, auto_unbox = TRUE, null = "null")

  # status.json 초기화
  status <- list(
    task_id = task_id,
    current_phase = "SPEC_APPROVED",
    updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    blocker = NULL
  )
  write_json(status, file.path(wt_dir, "status.json"),
             pretty = TRUE, auto_unbox = TRUE, null = "null")

  # governance_log 초기화
  gov_log <- list(
    task_id = task_id,
    events = list(list(
      timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      agent = "q-lead",
      action = "WT_CREATED",
      summary = sprintf("Work Task 생성: %s", hypothesis_title)
    ))
  )
  write_json(gov_log, file.path(wt_dir, "governance_log.json"),
             pretty = TRUE, auto_unbox = TRUE, null = "null")

  cat(sprintf("[wt_create] %s 생성 완료: %s\n", task_id, wt_dir))
  cat(sprintf("  Hypothesis: %s\n", hypothesis_title))
  cat(sprintf("  Universe: %s\n", universe))
  cat(sprintf("  Current phase: SPEC_APPROVED (Alpha Agent 대기)\n"))

  invisible(task_id)
}

# ─── WT 상태 조회 ───────────────────────────────────────
wt_status <- function(task_id) {
  wt_dir <- file.path(WT_ROOT, task_id)
  if (!dir.exists(wt_dir)) {
    stop(sprintf("[wt_status] WT %s 존재하지 않음", task_id))
  }

  status_path <- file.path(wt_dir, "status.json")
  if (!file.exists(status_path)) {
    stop(sprintf("[wt_status] %s/status.json 없음", task_id))
  }

  status <- fromJSON(status_path, simplifyVector = TRUE)

  cat(sprintf("=== %s ===\n", task_id))
  cat(sprintf("  Phase: %s\n", status$current_phase))
  cat(sprintf("  Updated: %s\n", status$updated_at))
  if (!is.null(status$blocker) && nchar(status$blocker) > 0) {
    cat(sprintf("  Blocker: %s\n", status$blocker))
  }

  # 존재 artifact 확인
  artifacts <- list(
    alpha_package = file.exists(file.path(wt_dir, "alpha_package.json")),
    risk_package = file.exists(file.path(wt_dir, "risk_package.json")),
    optimization_package = file.exists(file.path(wt_dir, "optimization_package.json"))
  )
  cat("  Packages:\n")
  for (nm in names(artifacts)) {
    cat(sprintf("    %s: %s\n", nm, if (artifacts[[nm]]) "✓" else "✗"))
  }

  invisible(status)
}

# ─── WT 단계 전이 ────────────────────────────────────────
wt_advance <- function(task_id, new_phase, blocker = NULL) {
  wt_dir <- file.path(WT_ROOT, task_id)
  if (!dir.exists(wt_dir)) stop(sprintf("[wt_advance] %s 없음", task_id))

  status_path <- file.path(wt_dir, "status.json")
  status <- fromJSON(status_path, simplifyVector = TRUE)
  old_phase <- status$current_phase

  status$current_phase <- new_phase
  status$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  status$blocker <- blocker

  write_json(status, status_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

  # governance_log 업데이트
  gov_path <- file.path(wt_dir, "governance_log.json")
  gov <- fromJSON(gov_path, simplifyVector = FALSE)
  gov$events[[length(gov$events) + 1]] <- list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    agent = "q-lead",
    action = "PHASE_ADVANCE",
    summary = sprintf("%s -> %s", old_phase, new_phase)
  )
  write_json(gov, gov_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

  cat(sprintf("[wt_advance] %s: %s -> %s\n", task_id, old_phase, new_phase))
  invisible(new_phase)
}

# ─── Package 검증 (schema 기반) ──────────────────────────
wt_validate_package <- function(task_id, package_type) {
  wt_dir <- file.path(WT_ROOT, task_id)
  pkg_path <- file.path(wt_dir, sprintf("%s.json", package_type))

  if (!file.exists(pkg_path)) {
    return(list(valid = FALSE, reason = "file_missing"))
  }

  pkg <- tryCatch(fromJSON(pkg_path, simplifyVector = TRUE),
                  error = function(e) NULL)
  if (is.null(pkg)) {
    return(list(valid = FALSE, reason = "invalid_json"))
  }

  # 필수 필드 (스키마 일부만 간단 체크)
  required_fields <- switch(package_type,
    "alpha_package" = c("task_id", "as_of_date", "alpha_vector", "factor_specs", "diagnostics"),
    "risk_package" = c("task_id", "as_of_date", "factor_covariance_ref", "risk_summary", "diagnostics"),
    "optimization_package" = c("task_id", "as_of_date", "method_selected", "expected_tracking_error"),
    character(0)
  )

  missing <- setdiff(required_fields, names(pkg))
  if (length(missing) > 0) {
    return(list(valid = FALSE, reason = "missing_fields",
                missing = missing))
  }

  list(valid = TRUE)
}

# ─── WT 전수 목록 ───────────────────────────────────────
wt_list <- function(include_completed = FALSE) {
  wts <- list.files(WT_ROOT, pattern = "^WT[0-9]{8}_[0-9]{3}$",
                    full.names = FALSE)
  if (length(wts) == 0) {
    cat("(WT 없음)\n")
    return(invisible(character(0)))
  }

  cat(sprintf("=== Work Tasks (%d) ===\n", length(wts)))
  for (id in wts) {
    status_path <- file.path(WT_ROOT, id, "status.json")
    if (file.exists(status_path)) {
      st <- fromJSON(status_path, simplifyVector = TRUE)
      if (!include_completed && st$current_phase %in% c("COMPLETED", "ABORTED")) next
      cat(sprintf("  %s | %s | updated %s\n",
                  id, st$current_phase, st$updated_at))
    }
  }
  invisible(wts)
}

cat("[worktask_manager.R] Loaded. Functions:\n")
cat("  wt_create(hypothesis_title, universe, ...)\n")
cat("  wt_status(task_id)\n")
cat("  wt_advance(task_id, new_phase, blocker=NULL)\n")
cat("  wt_validate_package(task_id, package_type)\n")
cat("  wt_list(include_completed=FALSE)\n")
