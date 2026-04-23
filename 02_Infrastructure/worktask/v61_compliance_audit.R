#==============================================================================
# QEPM v6.1 Compliance Audit — L-203 (2026-04-24)
#
# Purpose: 8 원칙(P1~P8) 자동 검증. WT 전수 또는 개별 WT 감사.
#
#   P1: Selection Freedom  — method_shopping_log 전수 + candidates 분포
#   P2: Data Separation    — lockbox access audit zero-violation
#   P3: Role-specific Obj  — selection_objective 도메인 준수
#   P4: Challenge Obligation — challenge_note count ≥ 1 (Risk/Opt)
#   P5: Book-level Primacy — Governor admission에 book_state 참조 필수
#   P6: Hard vs Soft       — Discovery SOFT 면제 + Deployment 전수 적용
#   P7: Lineage            — artifact_lineage.json git_commit + hash 전수
#   P8: Monitoring         — admitted 2개월+ monitoring 누락 없음
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

`%||%` <- function(a, b) if (!is.null(a)) a else b

WT_ROOT <- "qepm/mailbox/worktask"
LOCKBOX_LOG_PATTERN <- "/tmp/qvest_lockbox_access_%s.log"
BOOK_STATE <- "qepm/mailbox/governor/book_state.json"
MONITORING_DIR <- "qepm/mailbox/monitoring/reports"

# ─── P1 Selection Freedom ───────────────────────────────
audit_p1_selection_freedom <- function(wt_id) {
  wt_dir <- file.path(WT_ROOT, wt_id)
  log_path <- file.path(wt_dir, "method_shopping_log.json")
  alpha_path <- file.path(wt_dir, "alpha_package.json")

  if (!file.exists(log_path)) {
    return(list(principle = "P1", pass = FALSE,
                reason = "method_shopping_log.json missing"))
  }
  log <- fromJSON(log_path, simplifyVector = FALSE)

  limits <- list(alpha_agent = 5, risk_agent = 5, optimizer_agent = 10)
  issues <- c()
  for (agent in names(limits)) {
    n <- log[[agent]]$candidates_tried %||% 0
    if (n > limits[[agent]]) {
      issues <- c(issues, sprintf("%s candidates_tried %d > %d",
                                   agent, n, limits[[agent]]))
    }
  }

  list(
    principle = "P1",
    pass = length(issues) == 0,
    reason = if (length(issues) == 0) "within_limits" else paste(issues, collapse = "; "),
    details = log
  )
}

# ─── P2 Data Separation ─────────────────────────────────
audit_p2_data_separation <- function(wt_id) {
  log_path <- sprintf(LOCKBOX_LOG_PATTERN, wt_id)
  if (!file.exists(log_path)) {
    return(list(principle = "P2", pass = TRUE,
                reason = "no_lockbox_access (clean)"))
  }
  lines <- readLines(log_path)
  non_judge <- grep("\\| (alpha|risk|optimizer|opt_|forge)", lines, value = TRUE)
  list(
    principle = "P2",
    pass = length(non_judge) == 0,
    reason = if (length(non_judge) == 0) "judge_only_access"
             else sprintf("CONTAMINATION: %d non-judge accesses", length(non_judge)),
    violations = non_judge
  )
}

# ─── P3 Role-specific Objective ─────────────────────────
audit_p3_role_objective <- function(wt_id) {
  wt_dir <- file.path(WT_ROOT, wt_id)
  packages <- list(
    alpha = list(
      path = file.path(wt_dir, "alpha_package.json"),
      allowed = c("rank_ic", "icir", "monotonicity", "subperiod_stability")
    ),
    risk = list(
      path = file.path(wt_dir, "risk_package.json"),
      allowed = c("condition_number", "stress_robust", "crowding", "shrinkage_quality")
    ),
    optimizer = list(
      path = file.path(wt_dir, "optimization_package.json"),
      allowed = c("net_ir", "to_adj_ret", "uncertainty_penalty", "crowding_adj_ret")
    )
  )

  issues <- c()
  for (agent in names(packages)) {
    p <- packages[[agent]]
    if (!file.exists(p$path)) next
    pkg <- fromJSON(p$path, simplifyVector = FALSE)
    obj <- pkg$selection_objective %||% NA
    if (is.na(obj) || !obj %in% p$allowed) {
      issues <- c(issues, sprintf("%s selection_objective='%s' not in [%s]",
                                   agent, obj, paste(p$allowed, collapse = ",")))
    }
  }

  list(
    principle = "P3",
    pass = length(issues) == 0,
    reason = if (length(issues) == 0) "all_agents_within_domain" else paste(issues, collapse = "; ")
  )
}

# ─── P4 Challenge Obligation ────────────────────────────
# Risk & Optimizer가 최소 한 번 반론 검토 (null이어도 명시)
audit_p4_challenge <- function(wt_id) {
  wt_dir <- file.path(WT_ROOT, wt_id)
  gov_path <- file.path(wt_dir, "governance_log.json")
  if (!file.exists(gov_path)) {
    return(list(principle = "P4", pass = FALSE, reason = "governance_log_missing"))
  }
  gov <- fromJSON(gov_path, simplifyVector = FALSE)
  events <- gov$events %||% list()
  # GAP-1 수정: CHALLENGE_REVIEWED 도 인정 (NO_OBJECTION 명시 기록 포함)
  challenges <- Filter(function(e) {
    e$action %in% c("CHALLENGE_RAISED", "CHALLENGE_NO_OBJECTION", "CHALLENGE_REVIEWED")
  }, events)
  # Risk / Optimizer 각각 최소 1회 review 필수
  reviewers <- unique(sapply(challenges, function(e) e$agent %||% ""))
  has_risk <- "risk" %in% reviewers
  has_opt <- "optimizer" %in% reviewers
  pass <- has_risk && has_opt
  list(
    principle = "P4",
    pass = pass,
    reason = sprintf("challenge_events=%d / risk=%s / optimizer=%s (둘 다 필수)",
                     length(challenges), has_risk, has_opt),
    details = challenges
  )
}

# ─── P5 Book-level Primacy ──────────────────────────────
audit_p5_book_primacy <- function(wt_id) {
  wt_dir <- file.path(WT_ROOT, wt_id)
  adm_path <- file.path(wt_dir, "governor_admission.json")
  if (!file.exists(adm_path)) {
    return(list(principle = "P5", pass = NA, reason = "not_yet_admitted"))
  }
  adm <- fromJSON(adm_path, simplifyVector = FALSE)
  has_ref <- !is.null(adm$book_state_ref) || !is.null(adm$book_state_snapshot)
  list(
    principle = "P5",
    pass = has_ref,
    reason = if (has_ref) "book_state_referenced" else "book_state_missing_in_admission"
  )
}

# ─── P6 Hard vs Soft Tier ───────────────────────────────
audit_p6_tier <- function(wt_id) {
  wt_dir <- file.path(WT_ROOT, wt_id)
  req_path <- file.path(wt_dir, "request.json")
  if (!file.exists(req_path)) {
    return(list(principle = "P6", pass = FALSE, reason = "request.json missing"))
  }
  req <- fromJSON(req_path, simplifyVector = FALSE)
  wt_type <- req$wt_type %||% NA
  hc <- req$hard_constraints %||% list()

  if (wt_type == "discovery") {
    # SOFT 면제: max_names NULL 또는 SOFT 기록 금지
    if (!is.null(hc$max_names) && !is.na(hc$max_names) && hc$max_names > 0) {
      # discovery가 max_names 20 적용했다면 SOFT 주입 의심
      return(list(principle = "P6", pass = TRUE,
                  reason = sprintf("discovery with max_names=%s (allowed if user override)",
                                   hc$max_names)))
    }
    return(list(principle = "P6", pass = TRUE, reason = "discovery_soft_exempt"))
  } else if (wt_type == "deployment") {
    # SOFT 전수 강제
    issues <- c()
    if (is.null(hc$max_names) || hc$max_names > 20) issues <- c(issues, "max_names>20")
    bounds <- hc$weight_bounds %||% c(NA, NA)
    if (length(bounds) < 2 || bounds[2] > 0.20) issues <- c(issues, "weight_bound>0.20")
    lfloor <- hc$liquidity_min_won_20d_avg %||% 0
    if (lfloor < 2e8) issues <- c(issues, "liquidity<2e8")
    list(
      principle = "P6",
      pass = length(issues) == 0,
      reason = if (length(issues) == 0) "deployment_all_soft_enforced" else paste(issues, collapse = "; ")
    )
  } else {
    list(principle = "P6", pass = FALSE, reason = sprintf("invalid_wt_type=%s", wt_type))
  }
}

# ─── P7 Lineage ─────────────────────────────────────────
audit_p7_lineage <- function(wt_id) {
  wt_dir <- file.path(WT_ROOT, wt_id)
  lin_path <- file.path(wt_dir, "artifact_lineage.json")
  if (!file.exists(lin_path)) {
    return(list(principle = "P7", pass = FALSE, reason = "artifact_lineage.json missing"))
  }
  lin <- fromJSON(lin_path, simplifyVector = FALSE)
  entries <- lin$entries %||% list()
  if (length(entries) == 0) {
    return(list(principle = "P7", pass = FALSE, reason = "no_entries"))
  }
  # 전수 git_commit + file_hash 확인
  missing <- Filter(function(e) {
    is.null(e$git_commit) || is.null(e$file_hash_sha256) ||
      e$git_commit %in% c("unknown", "") || nchar(e$file_hash_sha256 %||% "") < 16
  }, entries)

  list(
    principle = "P7",
    pass = length(missing) == 0 && length(entries) >= 3,
    reason = sprintf("entries=%d missing_hash_or_commit=%d",
                     length(entries), length(missing))
  )
}

# ─── P8 Monitoring Coverage ─────────────────────────────
audit_p8_monitoring <- function() {
  if (!file.exists(BOOK_STATE)) {
    return(list(principle = "P8", pass = TRUE, reason = "no_book_state_yet"))
  }
  bs <- fromJSON(BOOK_STATE, simplifyVector = FALSE)
  admitted <- bs$admitted_ids %||% list()
  if (length(admitted) == 0) {
    return(list(principle = "P8", pass = TRUE, reason = "no_admitted_wts"))
  }
  # 최근 2개월 내 monitoring_report 존재 여부
  now <- Sys.Date()
  last_2m <- seq(now, by = "-1 month", length.out = 3)[-1]
  months <- format(c(now, last_2m), "%Y%m")

  reports <- list.files(MONITORING_DIR, pattern = "monitoring_report_", full.names = TRUE)
  if (length(reports) == 0 && length(admitted) > 0) {
    return(list(principle = "P8", pass = FALSE,
                reason = sprintf("%d admitted WTs with no monitoring reports", length(admitted))))
  }

  recent <- reports[sapply(reports, function(p) {
    any(sapply(months, function(m) grepl(m, p)))
  })]

  list(
    principle = "P8",
    pass = length(recent) >= 1,
    reason = sprintf("recent_reports=%d (expected ≥ 1 within 2 months)",
                     length(recent))
  )
}

# ─── Full audit per WT ──────────────────────────────────
audit_wt <- function(wt_id, verbose = TRUE) {
  results <- list(
    p1 = audit_p1_selection_freedom(wt_id),
    p2 = audit_p2_data_separation(wt_id),
    p3 = audit_p3_role_objective(wt_id),
    p4 = audit_p4_challenge(wt_id),
    p5 = audit_p5_book_primacy(wt_id),
    p6 = audit_p6_tier(wt_id),
    p7 = audit_p7_lineage(wt_id)
  )

  if (verbose) {
    cat(sprintf("\n=== v6.1 Compliance Audit: %s ===\n", wt_id))
    for (k in names(results)) {
      r <- results[[k]]
      mark <- if (isTRUE(r$pass)) "✓" else if (is.na(r$pass)) "—" else "✗"
      cat(sprintf("  %s %s: %s — %s\n",
                  mark, r$principle, if (isTRUE(r$pass)) "PASS" else if (is.na(r$pass)) "SKIP" else "FAIL",
                  r$reason))
    }
  }

  # Pass ratio (NA 제외)
  passes <- sapply(results, function(r) isTRUE(r$pass))
  skips <- sapply(results, function(r) is.na(r$pass))
  pass_count <- sum(passes)
  total_count <- sum(!skips)
  pass_rate <- if (total_count == 0) NA else pass_count / total_count

  list(
    task_id = wt_id,
    results = results,
    pass_count = pass_count,
    total_count = total_count,
    pass_rate = pass_rate,
    all_pass = all(passes | skips)
  )
}

# ─── Full audit across all active WTs + P8 global ────────
audit_all <- function() {
  wts <- list.files(WT_ROOT,
                    pattern = "^WT-?[DP]?[0-9]{8}_[0-9]{3}$",
                    full.names = FALSE)

  cat(sprintf("=== QEPM v6.1 Compliance Audit — %s ===\n",
              format(Sys.time(), "%Y-%m-%d %H:%M")))
  cat(sprintf("WTs audited: %d\n\n", length(wts)))

  per_wt <- lapply(wts, audit_wt, verbose = TRUE)
  names(per_wt) <- wts

  p8 <- audit_p8_monitoring()
  cat(sprintf("\n=== Global P8 Monitoring ===\n"))
  cat(sprintf("  %s P8: %s — %s\n",
              if (isTRUE(p8$pass)) "✓" else "✗",
              if (isTRUE(p8$pass)) "PASS" else "FAIL", p8$reason))

  # Aggregate
  pass_counts <- sapply(per_wt, function(x) x$pass_count)
  total_counts <- sapply(per_wt, function(x) x$total_count)

  cat(sprintf("\n=== Aggregate ===\n"))
  cat(sprintf("  Per-WT passes: %d / %d total checks\n",
              sum(pass_counts), sum(total_counts)))
  cat(sprintf("  P8 global: %s\n", if (isTRUE(p8$pass)) "PASS" else "FAIL"))

  invisible(list(per_wt = per_wt, p8 = p8))
}

cat("[v61_compliance_audit.R] L-203 Loaded. Functions:\n")
cat("  audit_wt(wt_id)      — single WT P1~P7 audit\n")
cat("  audit_all()          — all WTs + P8 global\n")
cat("  audit_p1..audit_p8   — individual principle\n")
