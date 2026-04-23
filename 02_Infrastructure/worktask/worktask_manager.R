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

# ─── WT ID 생성 (v6.1 wt_type 접두사) ───────────────────
wt_generate_id <- function(wt_type = "discovery") {
  today <- format(Sys.Date(), "%Y%m%d")
  prefix <- if (wt_type == "discovery") "WT-D" else "WT-P"
  existing <- list.files(WT_ROOT, pattern = sprintf("^%s%s_", prefix, today))
  seq <- length(existing) + 1
  sprintf("%s%s_%03d", prefix, today, seq)
}

# ─── WT 디렉토리 + request.json 생성 ─────────────────────
# v6.1 R1+R13: wt_type 분기 + Discovery/Deployment 이원화
#   wt_type="discovery" → Soft 제약 면제, breadth 허용, alpha 존재 확인 목적
#   wt_type="deployment" → 모든 제약 강제, production 편성 목적
# theme만 주고 hypothesis_title=NULL이면 Alpha Agent Step 0 (Hypothesis Discovery) 자동 활성화
wt_create <- function(hypothesis_title = NULL,
                       theme = NULL,
                       wt_type = "discovery",
                       discovery_of = NULL,
                       hypothesis_description = "",
                       universe = "KOSPI200_KOSDAQ150_intersection",
                       benchmark = "KOSPI200_total_return",
                       as_of_date = Sys.Date(),
                       forecast_horizon = "1M",
                       rebalance_frequency = "monthly",
                       current_portfolio = "STR_1631_80_STR_1656_20",
                       long_only = NULL,
                       max_names = NULL,
                       override_constraints = NULL) {

  if (is.null(hypothesis_title) && is.null(theme)) {
    stop("[wt_create] hypothesis_title 또는 theme 중 최소 하나 필요")
  }
  if (!wt_type %in% c("discovery", "deployment")) {
    stop("[wt_create] wt_type must be 'discovery' or 'deployment'")
  }
  if (wt_type == "deployment" && is.null(discovery_of)) {
    warning("[wt_create] Deployment WT without discovery_of — graduation_criteria 우회 허용 (검증 완료된 alpha 직접 편성 목적).")
  }

  task_id <- wt_generate_id(wt_type = wt_type)
  wt_dir <- file.path(WT_ROOT, task_id)
  dir.create(wt_dir, recursive = TRUE, showWarnings = FALSE)

  # 기본 제약 로드 (v6.1 3-tier)
  defaults <- fromJSON(WT_CONSTRAINT_DEFAULTS, simplifyVector = FALSE)

  # Hypothesis source 결정
  hyp_source <- if (!is.null(hypothesis_title)) "user_defined" else "alpha_agent_discovered"

  # v6.1 R1+R13: wt_type별 제약 분기
  if (wt_type == "discovery") {
    # Discovery: HARD만, SOFT는 null (breadth 허용)
    liquidity_floor <- defaults$tier_hard_mandate$liquidity_floor_won_20d_avg
    effective_max_names <- if (!is.null(max_names)) max_names else NULL
    effective_long_only <- if (!is.null(long_only)) long_only else "configurable"
    effective_bounds <- defaults$discovery_defaults$weight_bounds
  } else {
    # Deployment: HARD + SOFT 모두 강제
    liquidity_floor <- defaults$tier_soft_deployment$liquidity_min_won_20d_avg
    effective_max_names <- 20L
    effective_long_only <- TRUE
    effective_bounds <- defaults$tier_soft_deployment$weight_bounds
  }

  # Request 조립
  request <- list(
    task_id = task_id,
    wt_type = wt_type,
    discovery_of = discovery_of,
    graduation_criteria = defaults$tier_graduation,
    theme = theme,
    hypothesis_title = hypothesis_title,
    hypothesis_description = hypothesis_description,
    hypothesis_source = hyp_source,
    as_of_date = format(as.Date(as_of_date), "%Y-%m-%d"),
    forecast_horizon = forecast_horizon,
    rebalance_frequency = rebalance_frequency,
    universe_definition = list(
      label = universe,
      liquidity_min_won_20d_avg = liquidity_floor,
      max_names_total = 500L
    ),
    benchmark_definition = benchmark,
    data_lag_rules = defaults$tier_hard_mandate$data_lag_rules_default,
    cost_model_version = defaults$tier_soft_deployment$cost_model_version,
    current_portfolio = current_portfolio,
    hard_mandate = list(
      pit_enforcement = "C1-C15 all enforced",
      liquidity_floor_won_20d_avg = defaults$tier_hard_mandate$liquidity_floor_won_20d_avg,
      mandate_restrictions = defaults$tier_hard_mandate$mandate_restrictions,
      long_only_mandate = effective_long_only
    ),
    hard_constraints = list(
      max_names = effective_max_names,
      weight_bounds = effective_bounds,
      sector_active_weight_cap = if (wt_type == "deployment") defaults$tier_soft_deployment$sector_active_weight_cap else NULL,
      liquidity_min_won_20d_avg = liquidity_floor
    ),
    soft_penalties = if (wt_type == "deployment") list(
      turnover_cap_annual = defaults$tier_soft_deployment$turnover_cap_annual,
      beta_target = 1.0,
      style_exposure_cap = 2.0
    ) else list(),
    capacity_limits = list(
      adv_multiplier = defaults$tier_soft_deployment$capacity_adv_multiplier,
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
  display_title <- if (!is.null(hypothesis_title)) hypothesis_title else sprintf("[theme] %s (Alpha Agent 자동 발굴)", theme)
  gov_log <- list(
    task_id = task_id,
    events = list(list(
      timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      agent = "q-lead",
      action = "WT_CREATED",
      summary = sprintf("Work Task 생성: %s | source=%s", display_title, hyp_source)
    ))
  )
  write_json(gov_log, file.path(wt_dir, "governance_log.json"),
             pretty = TRUE, auto_unbox = TRUE, null = "null")

  cat(sprintf("[wt_create] %s 생성 완료: %s\n", task_id, wt_dir))
  cat(sprintf("  WT Type: %s\n", toupper(wt_type)))
  if (!is.null(hypothesis_title)) {
    cat(sprintf("  Hypothesis: %s (user_defined)\n", hypothesis_title))
  } else {
    cat(sprintf("  Theme: %s (alpha_agent_discovered mode)\n", theme))
    cat("  → Alpha Agent Step 0 Hypothesis Discovery 활성화\n")
  }
  if (!is.null(discovery_of)) {
    cat(sprintf("  Discovery parent: %s\n", discovery_of))
  }
  cat(sprintf("  Universe: %s\n", universe))
  cat(sprintf("  Constraints tier: %s\n",
              if (wt_type == "discovery") "HARD mandate only (SOFT 면제, breadth 허용)" else "HARD + SOFT (20종/20%%/15bps 전부 강제)"))
  cat(sprintf("  Current phase: SPEC_APPROVED (Alpha Agent 대기)\n"))

  invisible(task_id)
}

# ─── Graduation 검증 (Discovery → Deployment 전환 조건) ──
wt_check_graduation <- function(task_id) {
  wt_dir <- file.path(WT_ROOT, task_id)
  if (!dir.exists(wt_dir)) stop(sprintf("[graduation] %s 없음", task_id))

  req_path <- file.path(wt_dir, "request.json")
  req <- fromJSON(req_path, simplifyVector = FALSE)

  if (req$wt_type != "discovery") {
    cat("[graduation] Discovery WT만 해당\n")
    return(invisible(list(pass = NA, reason = "not_discovery_wt")))
  }

  alpha_path <- file.path(wt_dir, "alpha_package.json")
  if (!file.exists(alpha_path)) {
    return(list(pass = FALSE, reason = "alpha_package missing"))
  }

  alpha_pkg <- fromJSON(alpha_path, simplifyVector = FALSE)
  criteria <- req$graduation_criteria
  diag <- alpha_pkg$diagnostics

  checks <- list(
    rank_ic = list(
      actual = diag$rank_ic %||% 0,
      threshold = criteria$min_rank_ic,
      pass = (diag$rank_ic %||% 0) >= criteria$min_rank_ic
    ),
    icir = list(
      actual = diag$icir %||% 0,
      threshold = criteria$min_icir,
      pass = (diag$icir %||% 0) >= criteria$min_icir
    ),
    subperiod_stability = list(
      actual = diag$subperiod_stability %||% 0,
      threshold = criteria$min_subperiod_stability,
      pass = (diag$subperiod_stability %||% 0) >= criteria$min_subperiod_stability
    ),
    harvey_t = list(
      actual = diag$harvey_t_stat %||% 0,
      threshold = criteria$min_harvey_t_stat,
      pass = (diag$harvey_t_stat %||% 0) >= criteria$min_harvey_t_stat
    )
  )

  all_pass <- all(sapply(checks, function(x) isTRUE(x$pass)))

  result <- list(
    pass = all_pass,
    task_id = task_id,
    checks = checks
  )

  cat(sprintf("=== Graduation Check: %s ===\n", task_id))
  for (nm in names(checks)) {
    c <- checks[[nm]]
    cat(sprintf("  %s: actual=%.4f / threshold=%.4f | %s\n",
                nm, c$actual, c$threshold,
                if (isTRUE(c$pass)) "PASS" else "FAIL"))
  }
  cat(sprintf("Overall: %s\n", if (all_pass) "GRADUATION PASS" else "NOT READY FOR DEPLOYMENT"))

  invisible(result)
}

`%||%` <- function(a, b) if (!is.null(a) && !is.na(a)) a else b

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
  if (is.null(status$challenge_round)) status$challenge_round <- 0L
  if (is.null(status$challenge_history)) status$challenge_history <- list()

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

# ─── Challenge Loop (R3) ────────────────────────────────
# Risk/Optimizer 에이전트가 Alpha/Risk 설계에 반론 제기.
# challenge_round >= 3 시 Hook이 block → Q-Lead 수동 개입.
# wt_challenge(task_id, from_agent, to_agent, reason)
wt_challenge <- function(task_id, from_agent, to_agent, reason) {
  stopifnot(from_agent %in% c("risk", "optimizer"))
  stopifnot(to_agent %in% c("alpha", "risk"))

  wt_dir <- file.path(WT_ROOT, task_id)
  if (!dir.exists(wt_dir)) stop(sprintf("[wt_challenge] %s 없음", task_id))
  status_path <- file.path(wt_dir, "status.json")
  status <- fromJSON(status_path, simplifyVector = FALSE)

  round_n <- (status$challenge_round %||% 0L) + 1L
  if (is.null(status$challenge_history)) status$challenge_history <- list()

  new_phase <- switch(to_agent,
    "alpha" = "ALPHA_REVISE_REQUIRED",
    "risk" = "RISK_REVISE_REQUIRED"
  )

  status$current_phase <- new_phase
  status$challenge_round <- round_n
  status$challenge_history[[length(status$challenge_history) + 1]] <- list(
    round = round_n,
    from_agent = from_agent,
    to_agent = to_agent,
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    challenge_reason = reason,
    resolution = NULL
  )
  status$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

  write_json(status, status_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

  # challenge_note artifact (target agent가 읽음)
  note_path <- file.path(wt_dir, sprintf("%s_challenge_note.json", to_agent))
  note <- list(
    task_id = task_id,
    round = round_n,
    from_agent = from_agent,
    to_agent = to_agent,
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    challenge_reason = reason,
    resolution_required = TRUE
  )
  write_json(note, note_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

  # governance_log
  gov_path <- file.path(wt_dir, "governance_log.json")
  gov <- fromJSON(gov_path, simplifyVector = FALSE)
  gov$events[[length(gov$events) + 1]] <- list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    agent = from_agent,
    action = "CHALLENGE_RAISED",
    summary = sprintf("Round %d: %s -> %s | %s", round_n, from_agent, to_agent, substr(reason, 1, 100))
  )
  write_json(gov, gov_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

  cat(sprintf("[wt_challenge] %s round %d: %s -> %s\n", task_id, round_n, from_agent, to_agent))
  if (round_n >= 2) cat("  WARN: round 2 도달 — Q-Lead 개입 검토 권장\n")
  if (round_n >= 3) cat("  BLOCK: round 3 — Hook이 차단. 수동 개입 필수\n")
  invisible(round_n)
}

# Challenge 해결 기록 (Alpha/Risk가 revise 완료 후 호출)
wt_resolve_challenge <- function(task_id, resolution_note) {
  wt_dir <- file.path(WT_ROOT, task_id)
  status_path <- file.path(wt_dir, "status.json")
  status <- fromJSON(status_path, simplifyVector = FALSE)

  n_hist <- length(status$challenge_history %||% list())
  if (n_hist == 0) {
    cat("[wt_resolve_challenge] challenge_history 비어있음\n")
    return(invisible(FALSE))
  }
  status$challenge_history[[n_hist]]$resolution <- resolution_note
  status$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

  write_json(status, status_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[wt_resolve_challenge] %s round %d resolved\n", task_id, n_hist))
  invisible(TRUE)
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

# ─── WT 전수 목록 (v6.1 WT-D/WT-P + legacy WT 모두 지원) ─
wt_list <- function(include_completed = FALSE) {
  wts <- list.files(WT_ROOT,
                    pattern = "^WT-?[DP]?[0-9]{8}_[0-9]{3}$",
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
      type_tag <- if (grepl("^WT-D", id)) "[D]" else if (grepl("^WT-P", id)) "[P]" else "[L]"
      cat(sprintf("  %s %s | %s | updated %s\n",
                  type_tag, id, st$current_phase, st$updated_at))
    }
  }
  invisible(wts)
}

cat("[worktask_manager.R] Loaded. Functions:\n")
cat("  wt_create(hypothesis_title, wt_type='discovery'|'deployment', ...)\n")
cat("  wt_status(task_id)\n")
cat("  wt_advance(task_id, new_phase, blocker=NULL)\n")
cat("  wt_challenge(task_id, from_agent, to_agent, reason)\n")
cat("  wt_resolve_challenge(task_id, resolution_note)\n")
cat("  wt_check_graduation(task_id)\n")
cat("  wt_validate_package(task_id, package_type)\n")
cat("  wt_list(include_completed=FALSE)\n")
